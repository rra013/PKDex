//
//  TeamPasteImport.swift
//  PKDex
//
//  Imports a whole Showdown team paste as a `SavedTeam`.
//
//  A team slot doesn't hold its set by itself: `TeamSlotInfo.spreadName`
//  points at a `SavedSpread`, and `SavedTeam.resolvedSlots` swaps in the live
//  spread so edits flow through. So an import creates one saved spread per
//  set, and a team whose slots point at them. That also puts every imported
//  set in the spread library, where the calc's Load button can reach it.
//
//  Spread names must be unique, and not only against other spreads. A team
//  slot whose spread was never saved (AI-generated slots use "X (AI)") falls
//  back to its snapshot, so a new spread with that name would silently take
//  the slot over. `TeamPasteImport.uniqueName` checks both.
//
//  The planning step builds the models without inserting them, so it can be
//  tested without a SwiftData container. The sheet inserts the plan.
//

import SwiftUI
import SwiftData

// MARK: - Planning

/// What an import will create, before anything is saved.
@MainActor
struct TeamImportPlan {
    var team: SavedTeam
    var spreads: [SavedSpread]
    /// Sets that couldn't be imported because their species didn't resolve.
    var skippedBlocked: [String]
    /// Importable sets past the six-slot limit, which are left out.
    var droppedOverLimit: [String]
}

@MainActor
enum TeamPasteImport {
    static let maxSlots = 6

    /// `base`, or `base 2`, `base 3`, … — the first that isn't in `taken`.
    static func uniqueName(_ base: String, taken: Set<String>) -> String {
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    /// Every name a new spread must avoid: existing spreads, plus the
    /// spread names team slots already point at.
    static func takenNames(spreads: [SavedSpread], teams: [SavedTeam]) -> Set<String> {
        var taken = Set(spreads.map(\.name))
        for team in teams {
            for slot in team.slots { taken.insert(slot.spreadName) }
        }
        return taken
    }

    /// Plans the spreads and team for a resolved paste. nil when nothing is
    /// importable. Blocked sets are skipped, and anything past six is left
    /// out; both are reported so the sheet can say so.
    static func plan(preview: ImportPreview, importer: PasteImporter,
                     teamName: String, taken: Set<String>) -> TeamImportPlan? {
        let name = teamName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTeamName = name.isEmpty ? "Imported Team" : name

        let importable = preview.importableSlots
        guard !importable.isEmpty else { return nil }
        let kept = importable.prefix(maxSlots)

        var taken = taken
        var spreads: [SavedSpread] = []
        var slots: [TeamSlotInfo] = []
        for slot in kept {
            let spreadName = uniqueName("\(finalTeamName) · \(slot.displayName)", taken: taken)
            taken.insert(spreadName)
            guard let spread = importer.savedSpread(for: slot, name: spreadName),
                  let teamSlot = importer.teamSlot(for: slot, spreadName: spreadName)
            else { continue }
            spreads.append(spread)
            slots.append(teamSlot)
        }
        guard !slots.isEmpty else { return nil }

        return TeamImportPlan(
            team: SavedTeam(name: finalTeamName, slots: slots),
            spreads: spreads,
            skippedBlocked: preview.slots.filter(\.isBlocked).map(\.displayName),
            droppedOverLimit: importable.dropFirst(maxSlots).map(\.displayName))
    }
}

// MARK: - Sheet

struct TeamPasteImportSheet: View {
    let savedSpreads: [SavedSpread]
    let savedTeams: [SavedTeam]
    let allPokemon: [PKMNStats]
    let allMoves: [MoveData]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultGeneration") private var defaultGeneration: String = PokedexFilter.champions.rawValue

    @State private var text = ""
    @State private var teamName = ""
    /// Built once; the Champions validator parses ~600 KB of JSON.
    @State private var importer: PasteImporter?
    @State private var preview: ImportPreview?

    private var scale: StatScale {
        defaultGeneration == PokedexFilter.champions.rawValue ? .champions : .mainline
    }

    private func refresh() {
        preview = importer?.preview(ShowdownPaste.parse(text, ambiguousDefault: scale))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Imported Team", text: $teamName)
                } header: {
                    Text("Team name")
                }

                Section {
                    TextEditor(text: $text)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 180)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    PasteButton(payloadType: String.self) { strings in
                        if let first = strings.first { text = first }
                    }
                } header: {
                    Text("Showdown team paste")
                } footer: {
                    Text("Each set is also saved as a spread, named after the team, so you can load it into the calc or edit it.")
                }

                if let preview, !preview.slots.isEmpty {
                    membersSection(preview)
                }
            }
            .navigationTitle("Import Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { importTeam() }
                        .disabled(!(preview?.isImportable ?? false))
                }
            }
            .task {
                guard importer == nil else { return }
                importer = PasteImporter(
                    allPokemon: allPokemon, allMoves: allMoves,
                    validator: scale == .champions ? ChampionsValidator() : nil,
                    targetScale: scale)
                refresh()
            }
            .onChange(of: text) { refresh() }
        }
    }

    @ViewBuilder
    private func membersSection(_ preview: ImportPreview) -> some View {
        let importable = preview.importableSlots
        Section {
            ForEach(preview.slots) { slot in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: statusIcon(slot))
                            .foregroundStyle(statusColor(slot))
                        Text(slot.displayName).font(.body.bold())
                        if let index = importable.firstIndex(where: { $0.id == slot.id }),
                           index >= TeamPasteImport.maxSlots {
                            Text("over 6 — left out").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    // A blocked set only needs its blocking reason. Its
                    // legality checks all cascade from the unknown species
                    // ("Ability is empty", "No learnset data", …) and bury it.
                    let issues = slot.isBlocked ? slot.issues.filter(\.isBlocking) : slot.issues
                    let violations = slot.isBlocked ? [] : slot.violations
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        ImportIssueRow(issue: issue)
                    }
                    ForEach(Array(violations.enumerated()), id: \.offset) { _, violation in
                        Label(violation.message, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(violation.category.isLegality ? .orange : .secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Members (\(min(importable.count, TeamPasteImport.maxSlots))/6 importable)")
        }

        if !preview.teamViolations.isEmpty {
            Section("Team") {
                ForEach(Array(preview.teamViolations.enumerated()), id: \.offset) { _, violation in
                    Label(violation.message, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
        }
    }

    private func statusIcon(_ slot: ResolvedSlot) -> String {
        if slot.isBlocked { return "xmark.octagon.fill" }
        if !slot.legalityViolations.isEmpty { return "exclamationmark.triangle.fill" }
        return "checkmark.circle.fill"
    }

    private func statusColor(_ slot: ResolvedSlot) -> Color {
        if slot.isBlocked { return .red }
        if !slot.legalityViolations.isEmpty { return .orange }
        return .green
    }

    private func importTeam() {
        guard let importer, let preview,
              let plan = TeamPasteImport.plan(
                preview: preview, importer: importer, teamName: teamName,
                taken: TeamPasteImport.takenNames(spreads: savedSpreads, teams: savedTeams))
        else { return }
        for spread in plan.spreads { modelContext.insert(spread) }
        modelContext.insert(plan.team)
        dismiss()
    }
}
