//
//  TournamentsView.swift
//  PKDex
//
//  Created by Rishi Anand on 5/1/26.
//

import SwiftUI
import SwiftData
import WebKit

// MARK: - View Model

@Observable
final class TournamentsViewModel {
    var games: [LimitlessGame] = []
    var tournaments: [LimitlessTournament] = []
    var selectedGameID: String = "VGC"
    var selectedFormatID: String?
    var searchText = ""
    var minPlayers: Int = 0
    var isLoading = false
    var errorMessage: String?
    var currentPage = 1
    var hasMorePages = true

    var selectedGame: LimitlessGame? {
        games.first { $0.id == selectedGameID }
    }

    var availableFormats: [(key: String, value: String)] {
        guard let game = selectedGame else { return [] }
        return game.formats.sorted { $0.value < $1.value }
    }

    var filteredTournaments: [LimitlessTournament] {
        var result = tournaments
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedStandardContains(searchText) }
        }
        if minPlayers > 0 {
            result = result.filter { $0.players >= minPlayers }
        }
        return result
    }

    var selectedFormatName: String? {
        guard let formatID = selectedFormatID, let game = selectedGame else { return nil }
        return game.formats[formatID]
    }

    func loadGames() async {
        do {
            games = try await LimitlessAPIService.shared.fetchGames()
        } catch {
            errorMessage = "Failed to load games: \(error.localizedDescription)"
        }
    }

    func loadTournaments(reset: Bool = true) async {
        if reset {
            currentPage = 1
            hasMorePages = true
        }
        isLoading = true
        errorMessage = nil
        do {
            let results = try await LimitlessAPIService.shared.fetchTournaments(
                game: selectedGameID,
                format: selectedFormatID,
                limit: 50,
                page: currentPage
            )
            if reset {
                tournaments = results
            } else {
                tournaments.append(contentsOf: results)
            }
            hasMorePages = results.count >= 50
        } catch {
            errorMessage = "Failed to load tournaments: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func loadNextPage() async {
        guard hasMorePages, !isLoading else { return }
        currentPage += 1
        await loadTournaments(reset: false)
    }
}

// MARK: - Tournaments Tab

struct TournamentsTab: View {
    @State private var vm = TournamentsViewModel()
    @State private var showFilters = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.tournaments.isEmpty {
                    ProgressView("Loading tournaments…")
                } else if let error = vm.errorMessage, vm.tournaments.isEmpty {
                    ContentUnavailableView {
                        Label("Failed to Load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") {
                            Task { await vm.loadTournaments() }
                        }
                    }
                } else if vm.filteredTournaments.isEmpty {
                    ContentUnavailableView.search(text: vm.searchText)
                } else {
                    tournamentList
                }
            }
            .navigationTitle("Tournaments")
            .searchable(text: $vm.searchText, prompt: "Search tournaments")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showFilters = true
                    } label: {
                        Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showFilters) {
                TournamentFilterSheet(vm: vm)
            }
            .task {
                if vm.games.isEmpty {
                    await vm.loadGames()
                }
                if vm.tournaments.isEmpty {
                    await vm.loadTournaments()
                }
            }
        }
    }

    private var tournamentList: some View {
        List {
            if let formatName = vm.selectedFormatName {
                Section {
                    HStack {
                        Label(vm.selectedGame?.name ?? vm.selectedGameID, systemImage: "gamecontroller")
                        Spacer()
                        Text(formatName)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }

            Section {
                ForEach(vm.filteredTournaments) { tournament in
                    NavigationLink {
                        TournamentDetailView(tournament: tournament)
                    } label: {
                        TournamentRow(tournament: tournament)
                    }
                }

                if vm.hasMorePages && vm.searchText.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .task {
                            await vm.loadNextPage()
                        }
                }
            } header: {
                Text("\(vm.filteredTournaments.count) tournaments")
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - Tournament Row

private struct TournamentRow: View {
    let tournament: LimitlessTournament

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tournament.name)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 12) {
                Label(tournament.displayDate, systemImage: "calendar")
                Label("\(tournament.players)", systemImage: "person.2")
                Text(tournament.format)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.fill.tertiary, in: Capsule())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Filter Sheet

private struct TournamentFilterSheet: View {
    @Bindable var vm: TournamentsViewModel
    @Environment(\.dismiss) private var dismiss

    private let playerThresholds = [0, 8, 16, 32, 64, 128, 256]

    var body: some View {
        NavigationStack {
            Form {
                Section("Game") {
                    Picker("Game", selection: $vm.selectedGameID) {
                        ForEach(vm.games.filter { $0.metagame }) { game in
                            Text(game.name).tag(game.id)
                        }
                    }
                    .onChange(of: vm.selectedGameID) {
                        vm.selectedFormatID = nil
                    }
                }

                Section("Format") {
                    if vm.availableFormats.isEmpty {
                        Text("No formats available")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Format", selection: Binding(
                            get: { vm.selectedFormatID ?? "__all__" },
                            set: { vm.selectedFormatID = $0 == "__all__" ? nil : $0 }
                        )) {
                            Text("All Formats").tag("__all__")
                            ForEach(vm.availableFormats, id: \.key) { key, value in
                                Text(value).tag(key)
                            }
                        }
                    }
                }

                Section("Minimum Players") {
                    Picker("Min Players", selection: $vm.minPlayers) {
                        Text("Any").tag(0)
                        ForEach(playerThresholds.dropFirst(), id: \.self) { count in
                            Text("\(count)+").tag(count)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        dismiss()
                        Task { await vm.loadTournaments() }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Tournament Detail

struct TournamentDetailView: View {
    let tournament: LimitlessTournament
    @State private var detail: LimitlessTournamentDetail?
    @State private var standings: [LimitlessStanding] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var selectedPlacingFilter: PlacingFilter = .all

    enum PlacingFilter: String, CaseIterable, Identifiable {
        case all, top4, top8, top16, top32
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .top4: return "Top 4"
            case .top8: return "Top 8"
            case .top16: return "Top 16"
            case .top32: return "Top 32"
            }
        }
        var maxPlacing: Int? {
            switch self {
            case .all: return nil
            case .top4: return 4
            case .top8: return 8
            case .top16: return 16
            case .top32: return 32
            }
        }
    }

    private var filteredStandings: [LimitlessStanding] {
        var result = standings
        if let maxPlacing = selectedPlacingFilter.maxPlacing {
            result = result.filter { $0.placing <= maxPlacing }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedStandardContains(searchText) ||
                ($0.deck?.name?.localizedStandardContains(searchText) ?? false) ||
                ($0.decklist ?? []).contains { $0.name.localizedStandardContains(searchText) }
            }
        }
        return result
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading details…")
            } else if let error = errorMessage {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                }
            } else {
                standingsContent
            }
        }
        .navigationTitle(tournament.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadData()
        }
    }

    private var standingsContent: some View {
        List {
            tournamentInfoSection

            if !standings.isEmpty {
                standingsSection
            }
        }
        .searchable(text: $searchText, prompt: "Search players or teams")
        .scrollDismissesKeyboard(.interactively)
    }

    private var tournamentInfoSection: some View {
        Section("Tournament Info") {
            LabeledContent("Game", value: tournament.game)
            LabeledContent("Format", value: tournament.format)
            LabeledContent("Date", value: tournament.displayDate)
            LabeledContent("Players", value: "\(tournament.players)")
            if let detail {
                if let org = detail.organizer?.name {
                    LabeledContent("Organizer", value: org)
                }
                if let isOnline = detail.isOnline {
                    LabeledContent("Type", value: isOnline ? "Online" : "In-Person")
                }
                if let phases = detail.phases, !phases.isEmpty {
                    LabeledContent("Rounds") {
                        let totalRounds = phases.compactMap(\.rounds).reduce(0, +)
                        Text("\(totalRounds)")
                    }
                }
            }
        }
    }

    private var standingsSection: some View {
        Section {
            Picker("Filter", selection: $selectedPlacingFilter) {
                ForEach(PlacingFilter.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            ForEach(filteredStandings) { standing in
                if standing.decklist != nil {
                    NavigationLink {
                        StandingDetailView(standing: standing)
                    } label: {
                        StandingRow(standing: standing)
                    }
                } else {
                    StandingRow(standing: standing)
                }
            }
        } header: {
            Text("Standings (\(filteredStandings.count))")
        }
    }

    private func loadData() async {
        isLoading = true
        do {
            async let detailFetch = LimitlessAPIService.shared.fetchTournamentDetail(id: tournament.id)
            async let standingsFetch = LimitlessAPIService.shared.fetchStandings(tournamentID: tournament.id)
            detail = try await detailFetch
            standings = try await standingsFetch
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Standing Row

private struct StandingRow: View {
    let standing: LimitlessStanding

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("#\(standing.placing)")
                    .font(.headline)
                    .foregroundStyle(placingColor)
                    .frame(width: 44, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if let country = standing.country {
                            Text(flagEmoji(for: country))
                        }
                        Text(standing.name)
                            .font(.body.weight(.medium))
                    }

                    HStack(spacing: 8) {
                        if let record = standing.record {
                            Text(record.display)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let deckName = standing.deck?.name {
                            Text(deckName)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.fill.tertiary, in: Capsule())
                        }
                        if standing.drop != nil {
                            Text("Dropped")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Spacer()
            }

            if let team = standing.decklist, !team.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(team) { member in
                        Text(member.name)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.fill.quaternary, in: Capsule())
                    }
                }
                .padding(.leading, 44)
            }
        }
        .padding(.vertical, 2)
    }

    private var placingColor: Color {
        switch standing.placing {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .primary
        }
    }

    private func flagEmoji(for countryCode: String) -> String {
        let base: UInt32 = 127397
        return countryCode
            .uppercased()
            .unicodeScalars
            .compactMap { Unicode.Scalar(base + $0.value) }
            .map { String($0) }
            .joined()
    }
}

// MARK: - Standing Detail (Team View)

private struct StandingDetailView: View {
    let standing: LimitlessStanding
    @Query(sort: \PKMN.nationalPokedexNumber) private var allPokemon: [PKMN]
    @Query(sort: \PKMNStats.name) private var allStats: [PKMNStats]
    @Query(sort: \MoveData.name) private var allMoves: [MoveData]
    @Environment(\.modelContext) private var modelContext
    @State private var savedMemberName: String?

    var body: some View {
        List {
            Section("Player") {
                LabeledContent("Name", value: standing.name)
                if let country = standing.country {
                    LabeledContent("Country", value: flagEmoji(for: country) + " " + country)
                }
                LabeledContent("Placing", value: "#\(standing.placing)")
                if let record = standing.record {
                    LabeledContent("Record", value: record.display)
                }
            }

            if let team = standing.decklist, !team.isEmpty {
                Section("Team (\(team.count))") {
                    ForEach(team) { member in
                        TeamMemberRow(
                            member: member,
                            pokemon: findPokemon(named: member.name),
                            onSave: { saveSet(member: member) }
                        )
                        .overlay(alignment: .topTrailing) {
                            if savedMemberName == member.name {
                                Text("Saved!")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.green)
                                    .transition(.opacity)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(standing.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func findPokemon(named name: String) -> PKMN? {
        let lower = name.lowercased()
        return allPokemon.first { $0.name.lowercased() == lower }
    }

    private func matchAbility(displayName: String?, on stats: PKMNStats?) -> String? {
        guard let displayName, let stats else { return nil }
        let normalized = displayName.lowercased().replacingOccurrences(of: " ", with: "-")
        return stats.allAbilities.first { $0.lowercased() == normalized } ?? normalized
    }

    private func saveSet(member: LimitlessStanding.TeamMember) {
        let stats = allStats.first { $0.name.lowercased() == member.name.lowercased() }
        let abilityRaw = matchAbility(displayName: member.ability, on: stats)

        let moveIDs: [Int?] = (member.attacks ?? []).map { attackName in
            let lower = attackName.lowercased()
            return allMoves.first { $0.name.lowercased() == lower }?.id
        }

        let spread = SavedSpread(
            name: member.name,
            pokemonID: stats?.id,
            pokemonName: stats?.name ?? member.name,
            abilityName: abilityRaw,
            itemRawValue: member.item,
            moveID1: moveIDs.count > 0 ? moveIDs[0] : nil,
            moveID2: moveIDs.count > 1 ? moveIDs[1] : nil,
            moveID3: moveIDs.count > 2 ? moveIDs[2] : nil,
            moveID4: moveIDs.count > 3 ? moveIDs[3] : nil
        )
        modelContext.insert(spread)

        withAnimation {
            savedMemberName = member.name
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                if savedMemberName == member.name {
                    savedMemberName = nil
                }
            }
        }
    }

    private func flagEmoji(for countryCode: String) -> String {
        let base: UInt32 = 127397
        return countryCode
            .uppercased()
            .unicodeScalars
            .compactMap { Unicode.Scalar(base + $0.value) }
            .map { String($0) }
            .joined()
    }
}

private struct TeamMemberRow: View {
    let member: LimitlessStanding.TeamMember
    let pokemon: PKMN?
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let pokemon, let url = pokemon.detailURL {
                    NavigationLink {
                        MonIndexDetailView(pokemon: pokemon, detailURL: url)
                    } label: {
                        Text(member.name)
                            .font(.headline)
                    }
                } else {
                    Text(member.name)
                        .font(.headline)
                }
                if let tera = member.tera {
                    Text("Tera: \(tera)")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.fill.tertiary, in: Capsule())
                }
                Spacer()
                Button {
                    onSave()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 12) {
                if let ability = member.ability {
                    Label(ability, systemImage: "sparkles")
                }
                if let item = member.item {
                    Label(item, systemImage: "bag")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let attacks = member.attacks, !attacks.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(attacks, id: \.self) { move in
                        Text(move)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Mon Index Detail (from tournament)

private struct MonIndexDetailView: View {
    let pokemon: PKMN
    let detailURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Link(detailURL.absoluteString, destination: detailURL)
                .font(.footnote)
            TournamentWebView(url: detailURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .navigationTitle(pokemon.name)
        .padding()
    }
}

private struct TournamentWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }
}

// MARK: - PKMN Detail URL Helper

private extension PKMN {
    var detailURL: URL? {
        let link = champsLink ?? genNineLink ?? genEightLink ?? genSevenLink ?? genSixLink ?? genFiveLink ?? genFourLink ?? genThreeLink ?? genTwoLink ?? genOneLink
        guard let link else { return nil }
        return URL(string: link)
    }
}
