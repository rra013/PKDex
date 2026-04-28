//
//  TeamBuilder.swift
//  PKDex
//
//  Created by Rishi Anand on 4/16/26.
//

import SwiftUI
import SwiftData

// MARK: - Team List

struct TeamListView: View {
    @Query(sort: \SavedTeam.createdAt, order: .reverse) private var savedTeams: [SavedTeam]
    @Query(sort: \SavedSpread.createdAt, order: .reverse) private var savedSpreads: [SavedSpread]
    @Query(sort: \PKMNStats.name) private var allPokemon: [PKMNStats]
    @Query(sort: \MoveData.name) private var allMoves: [MoveData]
    @Environment(\.modelContext) private var modelContext
    @State private var showNewTeam = false

    var body: some View {
        NavigationStack {
            Group {
                if savedTeams.isEmpty {
                    ContentUnavailableView {
                        Label("No Teams", systemImage: "person.3")
                    } description: {
                        Text("Create a team of six to see type coverage analysis.")
                    } actions: {
                        Button("New Team") { showNewTeam = true }
                            .buttonStyle(.borderedProminent).tint(.red)
                    }
                } else {
                    List {
                        ForEach(savedTeams) { team in
                            NavigationLink {
                                TeamDetailView(team: team, savedSpreads: savedSpreads, allPokemon: allPokemon, allMoves: allMoves)
                            } label: {
                                TeamRowView(team: team)
                            }
                        }
                        .onDelete { indices in
                            for i in indices { modelContext.delete(savedTeams[i]) }
                        }
                    }
                }
            }
            .navigationTitle("Teams")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showNewTeam = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNewTeam) {
                NewTeamSheet(savedSpreads: savedSpreads, allPokemon: allPokemon, allMoves: allMoves)
            }
        }
    }
}

// MARK: - Team Row

private struct TeamRowView: View {
    let team: SavedTeam

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(team.name).font(.headline)
            let slots = team.slots
            if slots.isEmpty {
                Text("Empty team").font(.caption).foregroundStyle(.tertiary)
            } else {
                HStack(spacing: 6) {
                    ForEach(slots) { slot in
                        Text(slot.pokemonName)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(.secondarySystemBackground), in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - New Team Sheet

private struct NewTeamSheet: View {
    let savedSpreads: [SavedSpread]
    let allPokemon: [PKMNStats]
    let allMoves: [MoveData]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var slots: [TeamSlotInfo] = []
    @State private var showDiscardAlert = false

    private var hasChanges: Bool {
        !slots.isEmpty || !name.isEmpty
    }

    var body: some View {
        NavigationStack {
            TeamEditorContent(name: $name, slots: $slots, savedSpreads: savedSpreads, allPokemon: allPokemon, allMoves: allMoves)
                .navigationTitle("New Team")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            if hasChanges {
                                showDiscardAlert = true
                            } else {
                                dismiss()
                            }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let finalName = name.isEmpty ? "Untitled Team" : name
                            let team = SavedTeam(name: finalName, slots: slots)
                            modelContext.insert(team)
                            dismiss()
                        }
                        .disabled(slots.isEmpty)
                    }
                }
                .confirmationDialog("Discard Changes?", isPresented: $showDiscardAlert, titleVisibility: .visible) {
                    Button("Discard", role: .destructive) { dismiss() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("You have unsaved changes. Are you sure you want to discard them?")
                }
        }
        .interactiveDismissDisabled(hasChanges)
        .presentationDetents([.large])
    }
}

// MARK: - Team Detail View

struct TeamDetailView: View {
    let team: SavedTeam
    let savedSpreads: [SavedSpread]
    let allPokemon: [PKMNStats]
    let allMoves: [MoveData]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var slots: [TeamSlotInfo] = []
    @State private var hasLoaded = false
    @State private var isSaved = true
    @State private var showDiscardAlert = false
    @State private var originalName = ""
    @State private var originalSlots: [TeamSlotInfo] = []

    private var hasChanges: Bool {
        !isSaved && (name != originalName || slots != originalSlots)
    }

    var body: some View {
        TeamEditorContent(name: $name, slots: $slots, savedSpreads: savedSpreads, allPokemon: allPokemon, allMoves: allMoves)
            .navigationTitle(team.name)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(hasChanges)
            .toolbar {
                if hasChanges {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            showDiscardAlert = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        team.name = name.isEmpty ? team.name : name
                        team.slots = slots
                        isSaved = true
                        originalName = name
                        originalSlots = slots
                    }
                    .bold(hasChanges)
                    .disabled(!hasChanges)
                }
                if hasChanges {
                    ToolbarItem(placement: .principal) {
                        Text("Unsaved Changes")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                }
            }
            .onAppear {
                guard !hasLoaded else { return }
                hasLoaded = true
                name = team.name
                slots = team.slots
                originalName = name
                originalSlots = slots
            }
            .onChange(of: name) { isSaved = false }
            .onChange(of: slots) { isSaved = false }
            .confirmationDialog("Unsaved Changes", isPresented: $showDiscardAlert, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You have unsaved changes. Discard them?")
            }
    }
}

// MARK: - Shared Team Editor Content

private struct TeamEditorContent: View {
    @Binding var name: String
    @Binding var slots: [TeamSlotInfo]
    let savedSpreads: [SavedSpread]
    let allPokemon: [PKMNStats]
    let allMoves: [MoveData]
    @State private var showAddSlot = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Team Name
                VStack(alignment: .leading, spacing: 6) {
                    Label("Team Name", systemImage: "pencil")
                        .font(.headline)
                    TextField("Team Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                .padding()
                .background(.background, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)

                // Team Slots
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Team (\(slots.count)/6)", systemImage: "person.3.fill").font(.headline)
                        Spacer()
                        if slots.count < 6 {
                            Button { showAddSlot = true } label: {
                                Label("Add", systemImage: "plus.circle.fill")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered).tint(.red)
                        }
                    }
                    Divider()

                    if slots.isEmpty {
                        Text("Add sets from your saved spreads to build your team.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    } else {
                        ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                            TeamSlotCard(slot: slot, onRemove: { slots.remove(at: index) })
                        }
                    }
                }
                .padding()
                .background(.background, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)

                // Coverage Analysis
                if !slots.isEmpty {
                    TypeCoverageCard(slots: slots)
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showAddSlot) {
            AddSlotSheet(slots: $slots, savedSpreads: savedSpreads, allPokemon: allPokemon, allMoves: allMoves)
        }
    }
}

// MARK: - Team Slot Card

private struct TeamSlotCard: View {
    let slot: TeamSlotInfo
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(slot.pokemonName).font(.subheadline.bold())
                TypeBadge(type: slot.type1)
                if let t2 = slot.type2 { TypeBadge(type: t2) }
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }

            if !slot.moveSlots.isEmpty {
                HStack(spacing: 6) {
                    ForEach(slot.moveSlots) { move in
                        HStack(spacing: 3) {
                            Text(move.moveName)
                                .font(.caption2)
                            if move.isSTAB {
                                Text("STAB")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.yellow)
                            }
                        }
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background((typeColorMap[move.moveType] ?? .gray).opacity(0.2), in: Capsule())
                        .font(.caption2)
                    }
                }
            }

            if let ability = slot.abilityName {
                HStack(spacing: 6) {
                    Text(formatAbilityName(ability))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    if let item = slot.itemRawValue {
                        Text(item)
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }

            Text("EVs: \(slot.evHP)/\(slot.evAtk)/\(slot.evDef)/\(slot.evSpAtk)/\(slot.evSpDef)/\(slot.evSpeed)")
                .font(.caption2.monospaced()).foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Add Slot Sheet (pick from saved spreads)

private struct AddSlotSheet: View {
    @Binding var slots: [TeamSlotInfo]
    let savedSpreads: [SavedSpread]
    let allPokemon: [PKMNStats]
    let allMoves: [MoveData]
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [SavedSpread] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return savedSpreads }
        return savedSpreads.filter {
            ($0.name.lowercased().contains(q)) ||
            ($0.pokemonName?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if savedSpreads.isEmpty {
                    ContentUnavailableView {
                        Label("No Saved Sets", systemImage: "tray")
                    } description: {
                        Text("Create sets in the Sets tab first, then add them to your team here.")
                    }
                } else {
                    List(filtered) { spread in
                        Button {
                            addSpread(spread)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(spread.name).font(.headline)
                                    Spacer()
                                    if spread.championsMode {
                                        Text("Champions")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .foregroundStyle(.red)
                                            .background(Color.red.opacity(0.15), in: Capsule())
                                    }
                                }
                                if let pkmn = spread.pokemonName {
                                    Text(pkmn).font(.subheadline).foregroundStyle(.secondary)
                                }
                                let moveIDs = [spread.moveID1, spread.moveID2, spread.moveID3, spread.moveID4].compactMap { $0 }
                                let moveNames = moveIDs.compactMap { mid in allMoves.first(where: { $0.id == mid })?.name }
                                if !moveNames.isEmpty {
                                    Text(moveNames.joined(separator: " / "))
                                        .font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(slots.count >= 6)
                    }
                    .searchable(text: $searchText, prompt: "Search sets...")
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationTitle("Add Set to Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func addSpread(_ spread: SavedSpread) {
        guard slots.count < 6 else { return }
        let pokemon = allPokemon.first(where: { $0.id == spread.pokemonID })
        if let slotInfo = TeamSlotInfo.from(spread: spread, pokemon: pokemon, moves: allMoves) {
            slots.append(slotInfo)
            dismiss()
        }
    }
}

// MARK: - Type Coverage Analysis

struct CoverageSource: Identifiable {
    let id = UUID()
    let pokemonName: String
    let moveName: String
    let moveType: String
    let isSTAB: Bool
}

struct TypeCoverageEntry: Identifiable {
    let id: String // the defender type
    let defenderType: String
    let stabSources: [CoverageSource]
    let nonStabSources: [CoverageSource]

    var isCovered: Bool { !stabSources.isEmpty || !nonStabSources.isEmpty }
    var hasSTABCoverage: Bool { !stabSources.isEmpty }
}

func computeTypeCoverage(slots: [TeamSlotInfo]) -> [TypeCoverageEntry] {
    allTypes.map { defenderType in
        var stabSources: [CoverageSource] = []
        var nonStabSources: [CoverageSource] = []

        for slot in slots {
            for move in slot.moveSlots {
                // Skip status moves (no power)
                guard move.damageClass != "status", let power = move.power, power > 0 else { continue }

                let effectiveness = typeEffectivenessChart[move.moveType]?[defenderType] ?? 1.0
                if effectiveness > 1.0 {
                    let source = CoverageSource(
                        pokemonName: slot.pokemonName,
                        moveName: move.moveName,
                        moveType: move.moveType,
                        isSTAB: move.isSTAB
                    )
                    if move.isSTAB {
                        stabSources.append(source)
                    } else {
                        nonStabSources.append(source)
                    }
                }
            }
        }

        return TypeCoverageEntry(
            id: defenderType,
            defenderType: defenderType,
            stabSources: stabSources,
            nonStabSources: nonStabSources
        )
    }
}

// MARK: - Type Coverage Card

private struct TypeCoverageCard: View {
    let slots: [TeamSlotInfo]

    private var entries: [TypeCoverageEntry] {
        computeTypeCoverage(slots: slots)
    }

    private var stabCovered: [TypeCoverageEntry] {
        entries.filter { $0.hasSTABCoverage }
    }

    private var nonStabOnly: [TypeCoverageEntry] {
        entries.filter { !$0.hasSTABCoverage && $0.isCovered }
    }

    private var uncovered: [TypeCoverageEntry] {
        entries.filter { !$0.isCovered }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Type Coverage", systemImage: "shield.checkered").font(.headline)
            Divider()

            // Summary bar
            HStack(spacing: 12) {
                CoverageStat(label: "STAB SE", count: stabCovered.count, total: allTypes.count, color: .green)
                CoverageStat(label: "Non-STAB SE", count: nonStabOnly.count, total: allTypes.count, color: .yellow)
                CoverageStat(label: "Uncovered", count: uncovered.count, total: allTypes.count, color: .red)
            }

            // STAB super-effective
            if !stabCovered.isEmpty {
                CoverageSectionView(
                    title: "STAB Super-Effective",
                    icon: "checkmark.circle.fill",
                    iconColor: .green,
                    entries: stabCovered,
                    showSTAB: true
                )
            }

            // Non-STAB super-effective
            if !nonStabOnly.isEmpty {
                CoverageSectionView(
                    title: "Non-STAB Super-Effective",
                    icon: "checkmark.circle",
                    iconColor: .yellow,
                    entries: nonStabOnly,
                    showSTAB: false
                )
            }

            // Uncovered
            if !uncovered.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        Text("No Super-Effective Coverage").font(.subheadline.bold())
                    }

                    FlowLayout(spacing: 6) {
                        ForEach(uncovered) { entry in
                            TypeBadge(type: entry.defenderType)
                        }
                    }
                }
            }

            if uncovered.isEmpty {
                HStack {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    Text("Full type coverage!").font(.subheadline.bold()).foregroundStyle(.green)
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

private struct CoverageStat: View {
    let label: String
    let count: Int
    let total: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)").font(.title2.bold()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CoverageSectionView: View {
    let title: String
    let icon: String
    let iconColor: Color
    let entries: [TypeCoverageEntry]
    let showSTAB: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon).foregroundStyle(iconColor)
                Text(title).font(.subheadline.bold())
            }

            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    TypeBadge(type: entry.defenderType)

                    let sources = showSTAB ? entry.stabSources : entry.nonStabSources
                    ForEach(sources) { source in
                        HStack(spacing: 4) {
                            Text(source.pokemonName)
                                .font(.caption.bold())
                            Text("with")
                                .font(.caption).foregroundStyle(.tertiary)
                            Text(source.moveName)
                                .font(.caption)
                            TypeBadge(type: source.moveType)
                            if source.isSTAB {
                                Text("STAB")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 3).padding(.vertical, 1)
                                    .foregroundStyle(.yellow)
                                    .background(Color.yellow.opacity(0.2), in: Capsule())
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - Flow Layout (for type badges)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                                  proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
