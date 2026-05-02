//
//  LimitlessAPI.swift
//  PKDex
//
//  Created by Rishi Anand on 5/1/26.
//

import Foundation

// MARK: - API Models

struct LimitlessGame: Decodable, Identifiable {
    let id: String
    let name: String
    let formats: [String: String]
    let platforms: [String: String]
    let metagame: Bool
}

struct LimitlessTournament: Decodable, Identifiable {
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

struct LimitlessTournamentDetail: Decodable {
    let id: String
    let name: String
    let game: String
    let format: String
    let date: String
    let players: Int
    let organizer: Organizer?
    let isOnline: Bool?
    let phases: [Phase]?

    struct Organizer: Decodable {
        let id: Int?
        let name: String?
        let logo: String?
    }

    struct Phase: Decodable {
        let phase: Int?
        let type: String?
        let rounds: Int?
        let mode: String?
    }
}

struct LimitlessStanding: Decodable, Identifiable {
    var id: String { player }
    let player: String
    let name: String
    let country: String?
    let placing: Int
    let record: Record?
    let deck: Deck?
    let drop: Int?

    struct Record: Decodable {
        let wins: Int
        let losses: Int
        let ties: Int

        var display: String {
            ties > 0 ? "\(wins)-\(losses)-\(ties)" : "\(wins)-\(losses)"
        }
    }

    struct Deck: Decodable {
        let id: String?
        let name: String?
        let icons: [String]?
    }
}

// MARK: - API Service

actor LimitlessAPIService {
    static let shared = LimitlessAPIService()
    private let baseURL = "https://play.limitlesstcg.com/api"
    private let decoder = JSONDecoder()

    func fetchGames() async throws -> [LimitlessGame] {
        let url = URL(string: "\(baseURL)/games")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try decoder.decode([LimitlessGame].self, from: data)
    }

    func fetchTournaments(
        game: String? = nil,
        format: String? = nil,
        limit: Int = 50,
        page: Int = 1
    ) async throws -> [LimitlessTournament] {
        var components = URLComponents(string: "\(baseURL)/tournaments")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "page", value: String(page))
        ]
        if let game { items.append(URLQueryItem(name: "game", value: game)) }
        if let format { items.append(URLQueryItem(name: "format", value: format)) }
        components.queryItems = items

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try decoder.decode([LimitlessTournament].self, from: data)
    }

    func fetchTournamentDetail(id: String) async throws -> LimitlessTournamentDetail {
        let url = URL(string: "\(baseURL)/tournaments/\(id)/details")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try decoder.decode(LimitlessTournamentDetail.self, from: data)
    }

    func fetchStandings(tournamentID: String) async throws -> [LimitlessStanding] {
        let url = URL(string: "\(baseURL)/tournaments/\(tournamentID)/standings")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try decoder.decode([LimitlessStanding].self, from: data)
    }
}
