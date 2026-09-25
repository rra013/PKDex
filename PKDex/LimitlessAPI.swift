//
//  LimitlessAPI.swift
//  PKDex
//
//  Created by Rishi Anand on 5/1/26.
//

import Foundation

// MARK: - API Models

nonisolated struct LimitlessGame: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let formats: [String: String]
    let platforms: [String: String]
    let metagame: Bool
}

// `LimitlessTournament` and `LimitlessStanding` are `Codable` rather than just
// `Decodable` because `TeamCorpusStore` caches them on disk in the API's own
// shape, and `nonisolated` so the store can build its corpus off the main actor.

nonisolated struct LimitlessTournament: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let game: String
    let format: String
    let date: String
    let players: Int

    var parsedDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: date) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: date)
    }

    var displayDate: String {
        guard let parsed = parsedDate else { return date }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt.string(from: parsed)
    }
}

nonisolated struct LimitlessTournamentDetail: Decodable, Sendable {
    let id: String
    let name: String
    let game: String
    let format: String
    let date: String
    let players: Int
    let organizer: Organizer?
    let isOnline: Bool?
    let phases: [Phase]?

    struct Organizer: Decodable, Sendable {
        let id: Int?
        let name: String?
        let logo: String?
    }

    struct Phase: Decodable, Sendable {
        let phase: Int?
        let type: String?
        let rounds: Int?
        let mode: String?
    }
}

nonisolated struct LimitlessStanding: Codable, Identifiable, Sendable {
    var id: String { player }
    let player: String
    let name: String
    let country: String?
    /// nil for players Limitless didn't rank — in practice, players who
    /// dropped (`drop` is set). Common: 11 of 22 sampled events had some, and
    /// a non-optional `Int` failed to decode those events entirely. The API
    /// lists these players before first place; see `sortedByPlacing`.
    let placing: Int?
    let record: Record?
    let deck: Deck?
    let decklist: [TeamMember]?
    let drop: Int?

    struct Record: Codable, Sendable {
        let wins: Int
        let losses: Int
        let ties: Int

        var display: String {
            ties > 0 ? "\(wins)-\(losses)-\(ties)" : "\(wins)-\(losses)"
        }
    }

    struct Deck: Codable, Sendable {
        let id: String?
        let name: String?
        let icons: [String]?
    }

    struct TeamMember: Codable, Identifiable, Sendable {
        var id: String { name }
        let name: String
        /// Limitless's species slug ("arcanine-hisui", "indeedee-f"). Closer
        /// to the Pokedex's row names than `name` ("Hisuian Arcanine").
        let limitlessID: String?
        let item: String?
        let ability: String?
        let attacks: [String]?
        /// Sent for every member in recent events; nil in older ones.
        /// Casing isn't consistent ("Jolly", "jolly").
        let nature: String?
        let tera: String?

        private enum CodingKeys: String, CodingKey {
            case name, item, ability, attacks, nature, tera
            case limitlessID = "id"
        }
    }

    /// Ranked players by placing, then unranked players in the order the
    /// API sent them. The API puts unranked players first, which would put
    /// dropped players above the winner.
    static func sortedByPlacing(_ standings: [LimitlessStanding]) -> [LimitlessStanding] {
        standings.enumerated()
            .sorted { lhs, rhs in
                let l = lhs.element.placing ?? .max
                let r = rhs.element.placing ?? .max
                return l != r ? l < r : lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

// MARK: - Errors

/// A response Limitless didn't answer normally. Before this existed, a rate
/// limit (HTTP 429, whose body isn't JSON) surfaced as a decoding error.
nonisolated enum LimitlessAPIError: LocalizedError, Equatable, Sendable {
    /// HTTP 429. `retryAfter` is the server's Retry-After, in seconds, when
    /// it sent one.
    case rateLimited(retryAfter: TimeInterval?)
    /// Any other status outside 200–299.
    case http(status: Int)

    var errorDescription: String? {
        switch self {
        case .rateLimited(let retryAfter?):
            return "Limitless is limiting requests right now. Try again in \(Int(retryAfter.rounded(.up))) seconds."
        case .rateLimited(nil):
            return "Limitless is limiting requests right now. Try again in a minute."
        case .http(let status):
            return "Limitless returned an error (HTTP \(status))."
        }
    }

    /// Worth retrying after a pause: rate limits and server errors.
    var isTransient: Bool {
        switch self {
        case .rateLimited: return true
        case .http(let status): return status >= 500
        }
    }

    /// Throws for any HTTP status outside 200–299. Other response types pass.
    static func check(_ response: URLResponse, now: Date = Date()) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 429:
            throw Self.rateLimited(retryAfter: retryAfter(
                httpResponse.value(forHTTPHeaderField: "Retry-After"), now: now))
        default:
            throw Self.http(status: httpResponse.statusCode)
        }
    }

    /// A Retry-After header in seconds. It's either a number of seconds or an
    /// HTTP date; nil when it's missing or unreadable.
    static func retryAfter(_ value: String?, now: Date) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            return nil
        }
        if let seconds = TimeInterval(value) { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
    }
}

// MARK: - API Service

actor LimitlessAPIService {
    static let shared = LimitlessAPIService()
    private let baseURL = "https://play.limitlesstcg.com/api"
    private let cacheTTL: TimeInterval = 300

    private struct CacheEntry<T> {
        let value: T
        let timestamp: Date

        func isValid(ttl: TimeInterval) -> Bool {
            Date().timeIntervalSince(timestamp) < ttl
        }
    }

    private var gamesCache: CacheEntry<[LimitlessGame]>?
    private var tournamentsCache: [String: CacheEntry<[LimitlessTournament]>] = [:]
    private var detailCache: [String: CacheEntry<LimitlessTournamentDetail>] = [:]
    private var standingsCache: [String: CacheEntry<[LimitlessStanding]>] = [:]

    /// Fetches and decodes, throwing `LimitlessAPIError` for a non-2xx status
    /// so a rate limit isn't mistaken for bad JSON.
    private func get<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: url)
        try LimitlessAPIError.check(response)
        return try JSONDecoder().decode(type, from: data)
    }

    func fetchGames() async throws -> [LimitlessGame] {
        if let cached = gamesCache, cached.isValid(ttl: cacheTTL) {
            return cached.value
        }
        let url = URL(string: "\(baseURL)/games")!
        let result = try await get([LimitlessGame].self, from: url)
        gamesCache = CacheEntry(value: result, timestamp: Date())
        return result
    }

    func fetchTournaments(
        game: String? = nil,
        format: String? = nil,
        limit: Int = 50,
        page: Int = 1
    ) async throws -> [LimitlessTournament] {
        let cacheKey = "\(game ?? "")|\(format ?? "")|\(limit)|\(page)"
        if let cached = tournamentsCache[cacheKey], cached.isValid(ttl: cacheTTL) {
            return cached.value
        }

        var components = URLComponents(string: "\(baseURL)/tournaments")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "page", value: String(page))
        ]
        if let game { items.append(URLQueryItem(name: "game", value: game)) }
        if let format { items.append(URLQueryItem(name: "format", value: format)) }
        components.queryItems = items

        let result = try await get([LimitlessTournament].self, from: components.url!)
        tournamentsCache[cacheKey] = CacheEntry(value: result, timestamp: Date())
        return result
    }

    func fetchTournamentDetail(id: String) async throws -> LimitlessTournamentDetail {
        if let cached = detailCache[id], cached.isValid(ttl: cacheTTL) {
            return cached.value
        }
        let url = URL(string: "\(baseURL)/tournaments/\(id)/details")!
        let result = try await get(LimitlessTournamentDetail.self, from: url)
        detailCache[id] = CacheEntry(value: result, timestamp: Date())
        return result
    }

    func fetchStandings(tournamentID: String) async throws -> [LimitlessStanding] {
        if let cached = standingsCache[tournamentID], cached.isValid(ttl: cacheTTL) {
            return cached.value
        }
        let url = URL(string: "\(baseURL)/tournaments/\(tournamentID)/standings")!
        let result = try await get([LimitlessStanding].self, from: url)
        standingsCache[tournamentID] = CacheEntry(value: result, timestamp: Date())
        return result
    }
}
