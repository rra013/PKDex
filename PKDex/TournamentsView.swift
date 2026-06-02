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
    @State private var fullTeamSaveState: FullTeamSaveState = .idle
    /// Persistent alert payload — one line per Limitless name that didn't
    /// resolve. Mixes species mismatches ("no match found for X") and move
    /// mismatches ("no match found for move X on Y") in a single list so the
    /// user sees the full debug report in one pass.
    @State private var unmatchedAlertLines: [String] = []
    @State private var showUnmatchedAlert: Bool = false
    /// When on, every spread saved from this screen (single member OR full
    /// team) runs through `StatNaturePredictor` so the saved record has a
    /// best-guess EV spread + nature instead of the defaults. The Limitless
    /// API doesn't expose stats or nature, so this toggle is the only way
    /// downloaded teams gain those fields.
    @State private var predictStatsAndNature: Bool = false

    /// Tracks the result of the most recent "Save Full Team" press so we can flash
    /// feedback in the toolbar without committing to a long-lived banner.
    private enum FullTeamSaveState: Equatable {
        case idle
        case saved(savedCount: Int)
        case noTeam
    }

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
                Section {
                    Toggle(isOn: $predictStatsAndNature) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Predict Stats & Nature", systemImage: "sparkles")
                                .font(.subheadline)
                            Text("Fills in EV spread + nature using the on-device model. Limitless doesn't expose these.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.purple)
                }

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    saveFullTeam()
                } label: {
                    Label("Save Full Team", systemImage: "square.and.arrow.down.on.square")
                }
                .disabled((standing.decklist ?? []).isEmpty)
            }
            // Inline feedback so the user knows the save happened. Stays in the
            // toolbar so it doesn't push the team list around.
            if case .saved(let savedCount) = fullTeamSaveState {
                ToolbarItem(placement: .status) {
                    Text("Saved \(savedCount)-mon team")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
            } else if case .noTeam = fullTeamSaveState {
                ToolbarItem(placement: .status) {
                    Text("No decklist to save")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
            }
        }
        .alert("Couldn't match team data",
               isPresented: $showUnmatchedAlert,
               presenting: unmatchedAlertLines) { _ in
            Button("OK", role: .cancel) {}
        } message: { lines in
            // Each entry is already formatted (species: "no match found for X";
            // move: "no match found for move X on Y") so the user can copy the
            // names straight into the alias map or sync logs.
            Text(lines.joined(separator: "\n"))
        }
    }

    private func findPokemon(named name: String) -> PKMN? {
        let candidates = TournamentSpeciesAlias.candidates(for: name)
        for candidate in candidates {
            let lower = candidate.lowercased()
            if let hit = allPokemon.first(where: { $0.name.lowercased() == lower }) {
                return hit
            }
        }
        return nil
    }

    /// Limitless reports several form-changing Pokemon under their base name
    /// (e.g. "Aegislash") even though the local Pokedex stores them as separate
    /// PKMNStats rows keyed by form (e.g. "Aegislash-Shield"). This walks an
    /// alias list so the team downloader resolves them to the canonical row.
    ///
    /// Some species need move-aware disambiguation (Basculegion-Male vs
    /// Basculegion-Female): the report doesn't say which form was used, so we
    /// infer it from the moveset. That's why the lookup takes the full member
    /// rather than just a name.
    private func findStats(for member: LimitlessStanding.TeamMember) -> PKMNStats? {
        let candidates = candidateRowNames(for: member)
        for candidate in candidates {
            let lower = candidate.lowercased()
            if let hit = allStats.first(where: { $0.name.lowercased() == lower }) {
                return hit
            }
        }
        return nil
    }

    /// Returns the ordered list of local PKMNStats row names to try for a given
    /// team member. Wraps `TournamentSpeciesAlias.candidates` and overlays any
    /// species that need contextual disambiguation (Basculegion form by moveset).
    private func candidateRowNames(for member: LimitlessStanding.TeamMember) -> [String] {
        if member.name.lowercased() == "basculegion" {
            return basculegionFormCandidates(for: member.attacks ?? [])
        }
        return TournamentSpeciesAlias.candidates(for: member.name)
    }

    /// Counts physical vs. special damage classes for each named attack and
    /// hands the totals to the shared Basculegion selector. Status moves and
    /// unknown move names are ignored.
    private func basculegionFormCandidates(for attacks: [String]) -> [String] {
        var physical = 0, special = 0
        for attack in attacks {
            let lower = attack.lowercased()
            guard let move = allMoves.first(where: { $0.name.lowercased() == lower })
            else { continue }
            switch move.damageClass {
            case "physical": physical += 1
            case "special":  special += 1
            default:         break
            }
        }
        return TournamentSpeciesAlias.basculegionFormCandidates(
            physicalCount: physical, specialCount: special)
    }

    /// Limitless move names don't agree with PokeAPI on hyphen/space/apostrophe
    /// placement — "U-turn" (Limitless) vs "U Turn" (synced) is the canonical
    /// example. Match by stripping everything but alphanumerics + lowercasing,
    /// which collapses "U-turn", "U Turn", "U-Turn" and "uturn" all to "uturn"
    /// and lets the lookup hit. Returns nil if nothing comes close.
    private func findMove(named attackName: String) -> MoveData? {
        let target = BattleSimSeed.normalize(attackName)
        guard !target.isEmpty else { return nil }
        return allMoves.first { BattleSimSeed.normalize($0.name) == target }
    }

    /// Ability matching uses the same normalization so "King's Rock", "Kings
    /// Rock", or "kings-rock" all hit the same entry. Falls back to a
    /// hyphenated guess so a new-but-known-syntax ability still saves cleanly
    /// even when the species's local ability list hasn't caught up yet.
    private func matchAbility(displayName: String?, on stats: PKMNStats?) -> String? {
        guard let displayName, let stats else { return nil }
        let normalized = BattleSimSeed.normalize(displayName)
        if let hit = stats.allAbilities.first(where: { BattleSimSeed.normalize($0) == normalized }) {
            return hit
        }
        // Fallback to the hyphenated guess so engine-keyed handlers (which
        // expect "stance-change"-style IDs) still resolve when the species's
        // ability list doesn't list it.
        return displayName.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    private func saveSet(member: LimitlessStanding.TeamMember) {
        _ = buildAndInsertSpread(for: member)
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

    /// Inserts a SavedSpread for the given team member and returns the spread plus
    /// the matched `PKMNStats` (when found). Shared by the per-member save button
    /// and the full-team save action so both paths produce identical records.
    ///
    /// When the screen-level `predictStatsAndNature` toggle is on, the saved
    /// record's EV spread + nature come from the on-device predictor instead
    /// of the SavedSpread defaults (Adamant, all-0 EVs). The flag is captured
    /// inside this helper so both the per-member save button and the
    /// full-team save use the same branch.
    private func buildAndInsertSpread(for member: LimitlessStanding.TeamMember)
        -> (spread: SavedSpread, stats: PKMNStats?)
    {
        let stats = findStats(for: member)
        let abilityRaw = matchAbility(displayName: member.ability, on: stats)

        let moveIDs: [Int?] = (member.attacks ?? []).map { findMove(named: $0)?.id }

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
        if predictStatsAndNature {
            applyPredictedStatsAndNature(to: spread, member: member)
        }
        modelContext.insert(spread)
        return (spread, stats)
    }

    /// Runs the stat/nature predictor and writes the result back onto the
    /// spread. Failure here is silent — if the model isn't bundled or the
    /// predictor returns nil, the spread keeps its defaults rather than
    /// blocking the save. Predicted stat points are stored as EV values in
    /// Champions mode (0–32 per stat, total 66).
    private func applyPredictedStatsAndNature(to spread: SavedSpread,
                                              member: LimitlessStanding.TeamMember) {
        let pred = StatNaturePredictor.shared.predict(
            name: member.name,
            item: member.item,
            ability: member.ability,
            moves: member.attacks ?? [],
            role: nil   // Limitless doesn't expose role; predictor handles UNK
        )
        guard let pred else { return }
        spread.championsMode = true
        spread.evHP    = pred.statPoints.hp
        spread.evAtk   = pred.statPoints.atk
        spread.evDef   = pred.statPoints.def
        spread.evSpAtk = pred.statPoints.spa
        spread.evSpDef = pred.statPoints.spd
        spread.evSpeed = pred.statPoints.spe
        if let nature = pred.natureRecord {
            spread.natureID = nature.id
        }
    }

    /// Walks the standing's decklist, persisting a SavedSpread per member and a
    /// SavedTeam that references them by name.
    ///
    /// **Pre-flight validation:** before inserting anything, every member name
    /// and every move name is run through the normalized lookups. If anything
    /// fails to resolve we abort the save and surface a persistent alert
    /// listing each unmatched entry — silently saving a partial team or partial
    /// moveset makes the gap impossible to debug. Alert lines follow the
    /// "no match found for <X>" / "no match found for move <X> on <Y>" format
    /// so the missing names are easy to copy into the alias map or sync logs.
    private func saveFullTeam() {
        guard let members = standing.decklist, !members.isEmpty else {
            withAnimation { fullTeamSaveState = .noTeam }
            scheduleFullTeamStateReset()
            return
        }

        // 1. Pre-flight: collect every species AND move that didn't resolve.
        var lines: [String] = []
        for member in members {
            if findStats(for: member) == nil {
                lines.append("no match found for \(member.name)")
            }
            for attack in member.attacks ?? [] {
                if findMove(named: attack) == nil {
                    lines.append("no match found for move \(attack) on \(member.name)")
                }
            }
        }
        if !lines.isEmpty {
            unmatchedAlertLines = lines
            showUnmatchedAlert = true
            return
        }

        // 2. All species + moves matched — persist spreads and a SavedTeam.
        var slots: [TeamSlotInfo] = []
        for member in members {
            let result = buildAndInsertSpread(for: member)
            // The pre-flight guarantees `stats` is non-nil here, so
            // `TeamSlotInfo.from` shouldn't fail; force-checking with a
            // safe fallback keeps the type happy without resurrecting a
            // silent-skip path.
            if let slot = TeamSlotInfo.from(spread: result.spread,
                                            pokemon: result.stats,
                                            moves: allMoves) {
                slots.append(slot)
            }
        }

        let teamName = "\(standing.name)'s Team"
        let team = SavedTeam(name: teamName, slots: slots)
        modelContext.insert(team)

        withAnimation { fullTeamSaveState = .saved(savedCount: slots.count) }
        scheduleFullTeamStateReset()
    }

    private func scheduleFullTeamStateReset() {
        let snapshot = fullTeamSaveState
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                if fullTeamSaveState == snapshot {
                    fullTeamSaveState = .idle
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
// MARK: - Tournament Species Aliases

/// Limitless tournament reports list several form-changing Pokemon under names
/// that don't match the local PKMNStats row exactly:
///   - Shared base name across forms: "Aegislash" → "Aegislash-Shield"/"-Blade"
///   - Canonical English name vs Showdown form: "Eternal Flower Floette" or
///     "Floette" (Champions context) → "Floette-Eternal"
/// This helper expands a Limitless name to a prioritized candidate list so the
/// downloader can find the canonical row. **Aliases take priority over the raw
/// name** because for some species (notably Floette) the raw name resolves to
/// the wrong row — regular Floette and Floette-Eternal are both in the Pokedex
/// but Champions reports always mean the Eternal Flower form.
enum TournamentSpeciesAlias {
    /// Maps a base species name (or canonical English name) to one or more
    /// canonical row names, in priority order. The first hit wins; the raw name
    /// is appended last as a fallback. Keep entries to genuinely ambiguous form
    /// names — anything stored under its own name already round-trips fine.
    static let table: [String: [String]] = [
        "Aegislash":              ["Aegislash-Shield", "Aegislash-Blade"],
        "Floette":                ["Floette-Eternal"],
        "Eternal Flower Floette": ["Floette-Eternal"],
        "Floette-Eternal":        ["Floette-Eternal"],
        "Wishiwashi":             ["Wishiwashi-Solo", "Wishiwashi-School"],
        "Mimikyu":                ["Mimikyu-Disguised", "Mimikyu"],
        "Minior":                 ["Minior-Meteor", "Minior-Red-Meteor"],
        "Morpeko":                ["Morpeko-Full-Belly", "Morpeko"],
        "Eiscue":                 ["Eiscue-Ice", "Eiscue-Noice"],
        "Zacian":                 ["Zacian-Crowned", "Zacian-Hero"],
        "Zamazenta":              ["Zamazenta-Crowned", "Zamazenta-Hero"],
    ]

    /// Returns the lookup order for a Limitless name: aliases first (so we
    /// prefer the canonical form-specific row), raw name last as a fallback.
    /// Case-insensitive on the key side. The raw name is always included — if
    /// no alias entry exists, it's the only candidate.
    static func candidates(for rawName: String) -> [String] {
        var result: [String] = []
        for (key, aliases) in table where key.lowercased() == rawName.lowercased() {
            result.append(contentsOf: aliases)
        }
        // Always include the raw name as a final fallback, deduped.
        if !result.contains(where: { $0.lowercased() == rawName.lowercased() }) {
            result.append(rawName)
        }
        return result
    }

    /// Basculegion's two forms can't be told apart by Limitless's "Basculegion"
    /// label, but their stat focuses are mirror images: Male leans physical
    /// (Atk 112 vs SpA 80), Female leans special (Atk 92 vs SpA 100). Pick the
    /// form whose stat focus matches the team's actual moveset. Strictly more
    /// physical moves than special → Male; tie / mostly special / mostly status
    /// → Female (per the requested rule: "if using mostly attacking moves,
    /// assume male. otherwise female").
    static func basculegionFormCandidates(physicalCount: Int,
                                          specialCount: Int) -> [String] {
        if physicalCount > specialCount {
            return ["Basculegion-Male", "Basculegion-Female", "Basculegion"]
        } else {
            return ["Basculegion-Female", "Basculegion-Male", "Basculegion"]
        }
    }
}

