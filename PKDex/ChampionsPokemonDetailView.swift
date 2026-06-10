//
//  ChampionsPokemonDetailView.swift
//  PKDex
//
//  Structured detail page for a Pokémon in the Champions regulation. Replaces
//  the Serebii WebView with parsed data from `champions-m-a-learnsets.json`,
//  organized into Stats / Abilities / Type Chart / Moves sections with a TOC
//  jump strip, a searchable move list, a form picker (base / mega / alternate),
//  and a pinned "Build a Set" entry point into the Set Builder.
//

import SwiftUI
import SwiftData

struct ChampionsPokemonDetailView: View {
    let pokemon: PKMN
    let detailURL: URL?

    @Query(sort: \PKMNStats.id) private var allPokemonStats: [PKMNStats]
    @Query(sort: \MoveData.name) private var allMoves: [MoveData]

    @State private var selectedForm: FormChoice = .base
    @State private var moveSearch: String = ""
    @State private var showSetSheet: Bool = false

    private var species: ChampionsSpecies? {
        ChampionsLearnsetStore.shared.data(for: pokemon.name)
    }

    private var basePKMNStats: PKMNStats? {
        if let base = allPokemonStats.first(where: { $0.name == pokemon.name && !$0.isForm }) {
            return base
        }
        return allPokemonStats.first(where: { $0.name == pokemon.name })
    }

    var body: some View {
        Group {
            if let species {
                content(species: species)
            } else {
                ContentUnavailableView {
                    Label("No Data", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("No Champions reference data is available for \(pokemon.name).")
                }
            }
        }
        .navigationTitle(pokemon.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .sheet(isPresented: $showSetSheet) {
            NewSetSheet(allPokemon: allPokemonStats,
                        allMoves: allMoves,
                        initialPokemon: basePKMNStats)
        }
    }

    @ViewBuilder
    private func content(species: ChampionsSpecies) -> some View {
        let display = displayedForm(for: species)
        let displayedTypes = typesForDisplay(formName: display.name)

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sourceLink
                        .id(SectionID.top)

                    formPicker(species: species)

                    statsSection(display: display)
                        .id(SectionID.stats)

                    abilitiesSection(display: display, basePKMNStats: basePKMNStats)
                        .id(SectionID.abilities)

                    typeChartSection(types: displayedTypes)
                        .id(SectionID.typeChart)

                    movesSection(display: display)
                        .id(SectionID.moves)
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top, spacing: 0) {
                sectionNav(proxy: proxy)
            }
        }
        .safeAreaInset(edge: .bottom) {
            buildSetBar
        }
    }

    // MARK: - Sub-Views

    @ViewBuilder
    private var sourceLink: some View {
        if let detailURL {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("Source: \(detailURL.absoluteString)", destination: detailURL)
                    .font(.footnote)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    @ViewBuilder
    private func formPicker(species: ChampionsSpecies) -> some View {
        if !species.megas.isEmpty || !species.alternateForms.isEmpty {
            Menu {
                Button("Base — \(species.name)") { selectedForm = .base }
                if !species.megas.isEmpty {
                    Section("Mega Evolutions") {
                        ForEach(species.megas) { mega in
                            Button(mega.name) { selectedForm = .mega(mega.name) }
                        }
                    }
                }
                if !species.alternateForms.isEmpty {
                    Section("Alternate Forms") {
                        ForEach(species.alternateForms) { alt in
                            Button(alt.name) { selectedForm = .alternate(alt.name) }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.stack")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Form:")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                        .layoutPriority(1)
                    Text(currentFormDisplayName(species: species))
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func sectionNav(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SectionID.allCases, id: \.self) { id in
                        Button {
                            withAnimation { proxy.scrollTo(id, anchor: .top) }
                        } label: {
                            Text(id.label)
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .foregroundStyle(.white)
                                .background(Color.accentColor, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            Divider()
        }
        .background(.bar)
    }

    @ViewBuilder
    private func statsSection(display: DisplayedForm) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Base Stats", systemImage: "chart.bar.fill")

            if let stats = display.stats {
                VStack(spacing: 6) {
                    StatBar(label: "HP",   value: stats.hp,  color: .green)
                    StatBar(label: "Atk",  value: stats.atk, color: .red)
                    StatBar(label: "Def",  value: stats.def, color: .orange)
                    StatBar(label: "SpA",  value: stats.spa, color: .blue)
                    StatBar(label: "SpD",  value: stats.spd, color: .teal)
                    StatBar(label: "Spe",  value: stats.spe, color: .pink)
                }

                HStack {
                    Spacer()
                    Text("Total: \(stats.total)")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            } else {
                Text("Stats not available for this form.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func abilitiesSection(display: DisplayedForm, basePKMNStats: PKMNStats?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Abilities", systemImage: "sparkles")

            if display.abilities.isEmpty {
                Text("No abilities listed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(display.abilities, id: \.self) { ability in
                        let isHidden = isHiddenAbility(ability, base: basePKMNStats, displayName: display.name)
                        // Tap-through to the Ability Dex web view. The detail
                        // view slugifies the *display* name, so format the
                        // hyphenated slug ("flash-fire") into the Serebii-
                        // expected display form ("Flash Fire") before passing.
                        NavigationLink {
                            AbilityDetailView(ability: formatAbilityName(ability))
                        } label: {
                            AbilityChip(name: ability, isHidden: isHidden)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func typeChartSection(types: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Type Chart (Defensive)", systemImage: "shield.lefthalf.filled")

            if types.isEmpty {
                Text("Type information not available for this form.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    Text("Types:").font(.caption).foregroundStyle(.secondary)
                    ForEach(types, id: \.self) { TypeBadge(type: $0) }
                    Spacer()
                }

                let buckets = defensiveBuckets(for: types)
                ForEach(MultiplierBucket.displayOrder, id: \.self) { bucket in
                    if let entries = buckets[bucket], !entries.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bucket.label)
                                .font(.caption.bold())
                                .foregroundStyle(bucket.tint)
                            FlowLayout(spacing: 6) {
                                ForEach(entries, id: \.self) { type in
                                    TypeBadge(type: type)
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func movesSection(display: DisplayedForm) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Moves", systemImage: "bolt.horizontal")

            let moves = display.moves
            let filtered = filteredMoves(from: moves)

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search moves", text: $moveSearch)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled(true)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                if !moveSearch.isEmpty {
                    Button { moveSearch = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Text(moveSearch.isEmpty ? "\(moves.count) moves"
                                        : "\(filtered.count) of \(moves.count) moves")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if filtered.isEmpty {
                Text(moves.isEmpty ? "No moves listed." : "No moves match your search.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                // Tag with the form name so SwiftUI tears down and rebuilds
                // the move list when the user switches forms — otherwise it
                // can keep stale rows from the previous learnset.
                VStack(spacing: 0) {
                    ForEach(filtered, id: \.self) { name in
                        let data = moveLookup(name)
                        if let data {
                            NavigationLink {
                                MoveDetailView(move: data, genFilter: .champions)
                            } label: {
                                MoveRow(name: name, data: data)
                            }
                            .buttonStyle(.plain)
                        } else {
                            MoveRow(name: name, data: nil)
                        }
                        Divider()
                    }
                }
                .id("moves-\(display.name)")
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private var buildSetBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                showSetSheet = true
            } label: {
                HStack {
                    Image(systemName: "square.and.pencil")
                    Text("Build a Set With \(pokemon.name)")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .disabled(basePKMNStats == nil)
        }
        .background(.thinMaterial)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title).font(.headline)
            Spacer()
        }
    }

    private func currentFormDisplayName(species: ChampionsSpecies) -> String {
        switch selectedForm {
        case .base: return "Base — \(species.name)"
        case .mega(let name): return name
        case .alternate(let name): return name
        }
    }

    private func displayedForm(for species: ChampionsSpecies) -> DisplayedForm {
        switch selectedForm {
        case .base:
            return DisplayedForm(name: species.name,
                                 abilities: species.abilities,
                                 stats: species.stats,
                                 moves: species.moves)
        case .mega(let name):
            if let mega = species.megas.first(where: { $0.name == name }) {
                return DisplayedForm(name: mega.name,
                                     abilities: mega.abilities,
                                     stats: mega.stats,
                                     moves: species.moves) // megas inherit base moves
            }
            return DisplayedForm(name: species.name,
                                 abilities: species.abilities,
                                 stats: species.stats,
                                 moves: species.moves)
        case .alternate(let name):
            if let alt = species.alternateForms.first(where: { $0.name == name }) {
                return DisplayedForm(name: alt.name,
                                     abilities: alt.abilities,
                                     stats: alt.stats,
                                     moves: alt.moves ?? species.moves)
            }
            return DisplayedForm(name: species.name,
                                 abilities: species.abilities,
                                 stats: species.stats,
                                 moves: species.moves)
        }
    }

    private func filteredMoves(from moves: [String]) -> [String] {
        let q = moveSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return moves }
        return moves.filter { $0.lowercased().contains(q) }
    }

    private func moveLookup(_ name: String) -> MoveData? {
        // The Champions JSON uses Showdown-style names with hyphens and
        // apostrophes (e.g. "Will-O-Wisp", "Forest's Curse", "U-turn"), while
        // `MoveData.name` is the PokeAPI slug rebuilt with spaces
        // ("Will O Wisp", "Forests Curse", "U Turn"). Compare under the same
        // alphanumeric-only normalization used everywhere else in the app.
        let normalized = BattleSimSeed.normalize(name)
        guard !normalized.isEmpty else { return nil }
        return allMoves.first { BattleSimSeed.normalize($0.name) == normalized }
    }

    private func isHiddenAbility(_ name: String, base: PKMNStats?, displayName: String) -> Bool {
        // Only flag a "Hidden Ability" badge on the base form, where PKMNStats
        // gives us a reliable hidden ability marker. For mega/alt forms the
        // hidden slot doesn't map cleanly across data sources.
        guard displayName == pokemon.name, let base, let hidden = base.hiddenAbility else {
            return false
        }
        return hidden == name
    }

    private func typesForDisplay(formName: String) -> [String] {
        guard let base = basePKMNStats else { return [] }
        let baseTypes = [base.type1] + [base.type2].compactMap { $0 }

        // Base form — use the base species' types directly.
        if formName == pokemon.name { return baseTypes }

        // Try an exact name match first (cheap path).
        if let exact = allPokemonStats.first(where: { $0.name == formName }) {
            return [exact.type1] + [exact.type2].compactMap { $0 }
        }

        // Fuzzy match: restrict to PKMNStats sharing the base speciesID, then
        // pick the form whose name/formName matches the keyword embedded in the
        // displayed form name. JSON form names use phrases like "Mega Charizard
        // X" / "Hisuian Form", while PKMNStats uses PokeAPI slugs like
        // "Charizard-Mega-X" / formName "hisui". The keyword bridges the two.
        let candidates = allPokemonStats.filter {
            $0.speciesID == base.speciesID && $0.isForm
        }
        guard !candidates.isEmpty else { return baseTypes }

        let lower = formName.lowercased()
        let keywords: [String]
        if lower.hasPrefix("mega ") {
            if lower.hasSuffix(" x") { keywords = ["mega-x", "megax"] }
            else if lower.hasSuffix(" y") { keywords = ["mega-y", "megay"] }
            else { keywords = ["mega"] }
        } else if lower.contains("primal") {
            keywords = ["primal"]
        } else if lower.contains("hisui") {
            keywords = ["hisui"]
        } else if lower.contains("galar") {
            keywords = ["galar"]
        } else if lower.contains("alola") {
            keywords = ["alola"]
        } else if lower.contains("paldea") {
            keywords = ["paldea"]
        } else {
            keywords = []
        }

        for keyword in keywords {
            if let match = candidates.first(where: {
                $0.name.lowercased().contains(keyword)
                || ($0.formName ?? "").lowercased().contains(keyword)
            }) {
                return [match.type1] + [match.type2].compactMap { $0 }
            }
        }

        return baseTypes
    }

    private func defensiveBuckets(for defenderTypes: [String]) -> [MultiplierBucket: [String]] {
        var result: [MultiplierBucket: [String]] = [:]
        for attackingType in allTypes {
            var mult = 1.0
            for t in defenderTypes {
                mult *= typeEffectivenessChart[attackingType]?[t] ?? 1.0
            }
            let bucket = MultiplierBucket.bucket(for: mult)
            result[bucket, default: []].append(attackingType)
        }
        return result
    }

    // MARK: - Inner Types

    enum FormChoice: Hashable {
        case base
        case mega(String)
        case alternate(String)
    }

    struct DisplayedForm {
        let name: String
        let abilities: [String]
        let stats: ChampionsBaseStats?
        let moves: [String]
    }

    enum SectionID: String, CaseIterable, Hashable {
        case top, stats, abilities, typeChart, moves

        var label: String {
            switch self {
            case .top: return "Top"
            case .stats: return "Stats"
            case .abilities: return "Abilities"
            case .typeChart: return "Type Chart"
            case .moves: return "Moves"
            }
        }
    }

    enum MultiplierBucket: Hashable {
        case x4, x2, x1, xHalf, xQuarter, xZero

        static let displayOrder: [MultiplierBucket] = [.x4, .x2, .xHalf, .xQuarter, .xZero]

        var label: String {
            switch self {
            case .x4:       return "Takes 4× damage from"
            case .x2:       return "Takes 2× damage from"
            case .x1:       return "Takes 1× damage from"
            case .xHalf:    return "Takes ½× damage from"
            case .xQuarter: return "Takes ¼× damage from"
            case .xZero:    return "Immune to"
            }
        }

        var tint: Color {
            switch self {
            case .x4:       return .red
            case .x2:       return .orange
            case .x1:       return .secondary
            case .xHalf:    return .green
            case .xQuarter: return .mint
            case .xZero:    return .gray
            }
        }

        static func bucket(for mult: Double) -> MultiplierBucket {
            if mult == 0 { return .xZero }
            if mult >= 4 { return .x4 }
            if mult >= 2 { return .x2 }
            if mult <= 0.25 { return .xQuarter }
            if mult <= 0.5 { return .xHalf }
            return .x1
        }
    }
}

// MARK: - Stat Bar

private struct StatBar: View {
    let label: String
    let value: Int
    let color: Color

    private static let maxStat: Double = 255.0

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.bold())
                .frame(width: 40, alignment: .leading)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.caption.monospacedDigit())
                .frame(width: 36, alignment: .trailing)
            GeometryReader { geo in
                let fraction = min(max(Double(value) / Self.maxStat, 0), 1)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 10)
        }
    }
}

// MARK: - Ability Chip

private struct AbilityChip: View {
    let name: String
    let isHidden: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(formatAbilityName(name))
                .font(.subheadline.bold())
            if isHidden {
                Text("HA")
                    .font(.caption2.bold())
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .foregroundStyle(.white)
                    .background(Color.purple, in: Capsule())
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.orange.opacity(0.15), in: Capsule())
        .foregroundStyle(.orange)
    }
}

// MARK: - Move Row

private struct MoveRow: View {
    let name: String
    let data: MoveData?

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.bold())
                if let d = data {
                    HStack(spacing: 6) {
                        if let pp = ppText(d) {
                            Text(pp).font(.caption2).foregroundStyle(.secondary)
                        }
                        if let acc = d.accuracy {
                            Text("Acc \(acc)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            if let d = data {
                if let power = d.power, power > 0 {
                    Text("\(power) BP")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                DamageClassBadge(damageClass: d.damageClass)
                TypeBadge(type: d.type)
                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
            } else {
                Text("—")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func ppText(_ d: MoveData) -> String? {
        guard d.pp > 0 else { return nil }
        return "PP \(d.pp)"
    }
}

// MARK: - Card Modifier

private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 12))
    }
}

private extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
}
