//
//  LimitlessAPI.swift
//  PKDex
//
//  Created by Rishi Anand on 5/1/26.
//

import Foundation

// MARK: - API Models

struct LimitlessGame: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let formats: [String: String]
    let platforms: [String: String]
    let metagame: Bool
}

struct LimitlessTournament: Decodable, Identifiable, Sendable {
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

struct LimitlessStanding: Decodable, Identifiable, Sendable {
    var id: String { player }
    let player: String
    let name: String
    let country: String?
    let placing: Int
    let record: Record?
    let deck: Deck?
    let decklist: [TeamMember]?
    let drop: Int?

    struct Record: Decodable, Sendable {
        let wins: Int
        let losses: Int
        let ties: Int

        var display: String {
            ties > 0 ? "\(wins)-\(losses)-\(ties)" : "\(wins)-\(losses)"
        }
    }

    struct Deck: Decodable, Sendable {
        let id: String?
        let name: String?
        let icons: [String]?
    }

    struct TeamMember: Decodable, Identifiable, Sendable {
        var id: String { name }
        let name: String
        let item: String?
        let ability: String?
        let attacks: [String]?
        let tera: String?
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

    func fetchGames() async throws -> [LimitlessGame] {
        if let cached = gamesCache, cached.isValid(ttl: cacheTTL) {
            return cached.value
        }
        let url = URL(string: "\(baseURL)/games")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let result = try JSONDecoder().decode([LimitlessGame].self, from: data)
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

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let result = try JSONDecoder().decode([LimitlessTournament].self, from: data)
        tournamentsCache[cacheKey] = CacheEntry(value: result, timestamp: Date())
        return result
    }

    func fetchTournamentDetail(id: String) async throws -> LimitlessTournamentDetail {
        if let cached = detailCache[id], cached.isValid(ttl: cacheTTL) {
            return cached.value
        }
        let url = URL(string: "\(baseURL)/tournaments/\(id)/details")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let result = try JSONDecoder().decode(LimitlessTournamentDetail.self, from: data)
        detailCache[id] = CacheEntry(value: result, timestamp: Date())
        return result
    }

    func fetchStandings(tournamentID: String) async throws -> [LimitlessStanding] {
        if let cached = standingsCache[tournamentID], cached.isValid(ttl: cacheTTL) {
            return cached.value
        }
        let url = URL(string: "\(baseURL)/tournaments/\(tournamentID)/standings")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let result = try JSONDecoder().decode([LimitlessStanding].self, from: data)
        standingsCache[tournamentID] = CacheEntry(value: result, timestamp: Date())
        return result
    }
}
