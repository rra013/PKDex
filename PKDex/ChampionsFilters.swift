//
//  ChampionsFilters.swift
//  PKDex
//
//  Type / ability / move filters layered on top of the Champions Mon Index.
//  The Champions roster is small enough (~250 species) that we evaluate the
//  filter inline on the visible list — no SwiftData predicate required.
//  Available abilities and moves come straight from `ChampionsLearnsetStore`
//  so the pickers stay in sync with whatever regulation JSON is bundled.
//

import SwiftUI

// MARK: - Filter State

struct ChampionsFilters: Equatable {
    var type1: String? = nil     // canonical type name from `allTypes`, e.g. "Fire"
    var type2: String? = nil     // optional second type; ordering is cosmetic
    var ability: String? = nil   // ability slug from Champions JSON, e.g. "intimidate"
    var move: String? = nil      // move display name from Champions JSON

    var isActive: Bool {
        type1 != nil || type2 != nil || ability != nil || move != nil
    }

    var activeCount: Int {
        [type1, type2, ability, move].compactMap { $0 }.count
    }

    /// The set of types that must all be present on some form of the species
    /// for a row to survive the filter. `Set` makes the dual-typing match
    /// order-independent (Grass/Fire == Fire/Grass) and ignores accidental
    /// duplicates if the user picks the same type in both slots.
    var requiredTypes: Set<String> {
        Set([type1, type2].compactMap { $0 })
    }

    static let none = ChampionsFilters()
}

// MARK: - Available Filter Values

enum ChampionsFilterOptions {
    /// All ability slugs that appear on any base / mega / alternate form
    /// across the live regulation roster. Precomputed once per regulation
    /// inside `ChampionsLearnsetStore` — this used to scan the roster on
    /// every call and was the dominant cost of every search-bar keystroke
    /// (the `.sheet` content closure re-evaluated this argument every
    /// time `PokedexTab.body` ran).
    static func availableAbilities() -> [String] {
        ChampionsLearnsetStore.shared.allAbilities
    }

    /// All move display names usable by any Champions species (base + alt
    /// forms; megas inherit base learnsets). Same precomputation as
    /// `availableAbilities()`.
    static func availableMoves() -> [String] {
        ChampionsLearnsetStore.shared.allMoves
    }
}

// MARK: - Predicate

extension ChampionsFilters {
    /// Convenience that resolves `ChampionsLearnsetStore.shared` on the
    /// caller's behalf. Use the `store:`-taking overload from tight loops
    /// — resolving `.shared` per row was burning a `UserDefaults` read and
    /// an `NSLock` acquire per visible species (~250 round-trips per Mon
    /// Index render before this).
    func matches(speciesName: String, formStats: [PKMNStats]) -> Bool {
        matches(speciesName: speciesName, formStats: formStats, store: .shared)
    }

    /// Returns true when `species` (looked up via the provided `store`)
    /// satisfies every active filter. Types are evaluated against the
    /// matching `PKMNStats` form set because Champions JSON doesn't carry
    /// typing. Hoist `store = ChampionsLearnsetStore.shared` outside the
    /// per-row loop and pass it in.
    func matches(speciesName: String,
                 formStats: [PKMNStats],
                 store: ChampionsLearnsetStore) -> Bool {
        if !isActive { return true }

        let species = store.data(for: speciesName)

        // Type — when both slots are set, some form must carry both types
        // (dual-typing match, order-independent). When one slot is set, any
        // form carrying that type in either of its slots satisfies. Falls
        // back to false when we have no stats to check.
        let required = requiredTypes
        if !required.isEmpty {
            let hasMatchingForm = formStats.contains { s in
                let formTypes = Set([s.type1, s.type2].compactMap { $0 })
                return required.isSubset(of: formTypes)
            }
            if !hasMatchingForm { return false }
        }

        // Ability — check base + megas + alternate forms in the Champions JSON.
        if let abilityFilter = ability {
            guard let species else { return false }
            var pool = species.abilities
            for mega in species.megas { pool.append(contentsOf: mega.abilities) }
            for alt  in species.alternateForms { pool.append(contentsOf: alt.abilities) }
            if !pool.contains(abilityFilter) { return false }
        }

        // Move — base learnset plus any alternate-form-specific learnsets.
        // Megas inherit the base learnset (see `ChampionsForm.moves` comment),
        // so we don't need to consider them separately here.
        if let moveFilter = move {
            guard let species else { return false }
            if species.moves.contains(moveFilter) { return true }
            for alt in species.alternateForms {
                if alt.moves?.contains(moveFilter) == true { return true }
            }
            return false
        }

        return true
    }
}

// MARK: - Active Filter Chip Strip

struct ChampionsFilterChipStrip: View {
    @Binding var filters: ChampionsFilters

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let t1 = filters.type1 {
                    chip(label: t1, tint: typeColorMap[t1] ?? .gray) {
                        filters.type1 = nil
                    }
                }
                if let t2 = filters.type2 {
                    chip(label: t2, tint: typeColorMap[t2] ?? .gray) {
                        filters.type2 = nil
                    }
                }
                if let ability = filters.ability {
                    chip(label: formatAbilityName(ability), tint: .orange) {
                        filters.ability = nil
                    }
                }
                if let move = filters.move {
                    chip(label: move, tint: .blue) {
                        filters.move = nil
                    }
                }
                if filters.activeCount > 1 {
                    Button("Clear All") { filters = .none }
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func chip(label: String, tint: Color, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption.bold())
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .foregroundStyle(.white)
        .background(tint, in: Capsule())
    }
}

// MARK: - Filter Sheet

struct ChampionsFilterSheet: View {
    @Binding var filters: ChampionsFilters
    let availableAbilities: [String]
    let availableMoves: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var abilitySearch: String = ""
    @State private var moveSearch: String = ""

    /// Type-ahead: empty query → empty list. Dumping ~hundreds of abilities
    /// by default made the sheet impossible to skim; users now narrow the
    /// list as they type (matching the Types section's two-tap dropdown UX
    /// in spirit). The currently-selected ability still appears as a chip
    /// outside the sheet and as the "Clear ability filter" row inside it.
    private var filteredAbilities: [String] {
        let q = abilitySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return availableAbilities.filter {
            formatAbilityName($0).localizedStandardContains(q)
        }
    }

    private var filteredMoves: [String] {
        let q = moveSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return availableMoves.filter { $0.localizedStandardContains(q) }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Active-filter recap. Mirrors the chip strip on the Mon Index
                // so users can see (and remove) what's set without scrolling
                // through the type-ahead search lists below.
                if filters.isActive {
                    Section {
                        ChampionsFilterChipStrip(filters: $filters)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    } header: {
                        Text("Active Filters")
                    }
                }

                Section {
                    Picker("Type", selection: $filters.type1) {
                        Text("Any").tag(String?.none)
                        ForEach(allTypes, id: \.self) { t in
                            Text(t).tag(Optional(t))
                        }
                    }
                    Picker("Secondary Type", selection: $filters.type2) {
                        Text("Any").tag(String?.none)
                        ForEach(allTypes, id: \.self) { t in
                            Text(t).tag(Optional(t))
                        }
                    }
                } header: {
                    Text("Type")
                } footer: {
                    // Make the dual-typing contract AND the cross-section
                    // AND-combination explicit so users don't have to discover
                    // either rule empirically.
                    Text("When both slots are set, only Pokémon with both types on the same form match. Order doesn't matter. Type, Ability, and Move filters combine with AND — e.g. Ability = Contrary + Move = Skill Swap returns Contrary Pokémon that learn Skill Swap.")
                        .font(.caption)
                }

                Section("Ability") {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search abilities", text: $abilitySearch)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled(true)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                        if !abilitySearch.isEmpty {
                            Button { abilitySearch = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if filters.ability != nil {
                        Button(role: .destructive) {
                            filters.ability = nil
                        } label: {
                            Label("Clear ability filter", systemImage: "xmark.circle")
                        }
                    }
                    if abilitySearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Start typing to search abilities")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if filteredAbilities.isEmpty {
                        Text("No abilities match “\(abilitySearch)”")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(filteredAbilities, id: \.self) { ability in
                        Button {
                            filters.ability = ability
                        } label: {
                            HStack {
                                Text(formatAbilityName(ability))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if filters.ability == ability {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }

                Section("Move") {
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
                    if filters.move != nil {
                        Button(role: .destructive) {
                            filters.move = nil
                        } label: {
                            Label("Clear move filter", systemImage: "xmark.circle")
                        }
                    }
                    if moveSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Start typing to search moves")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if filteredMoves.isEmpty {
                        Text("No moves match “\(moveSearch)”")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(filteredMoves, id: \.self) { move in
                        Button {
                            filters.move = move
                        } label: {
                            HStack {
                                Text(move).foregroundStyle(.primary)
                                Spacer()
                                if filters.move == move {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Champions Filters")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { filters = .none }
                        .disabled(!filters.isActive)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
