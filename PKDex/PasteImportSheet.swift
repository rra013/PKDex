//
//  PasteImportSheet.swift
//  PKDex
//
//  Phase 1.3: Showdown paste import and export for the damage calc.
//
//  Import runs the paste through `ShowdownPaste.parse` (text → structs) and
//  `PasteImporter.preview` (structs → app data), shows what resolved and
//  what didn't, and applies the chosen set to a `CalcSide` through the same
//  `loadSpread` path the Load button uses, so a pasted set and a saved one
//  can't be applied differently.
//
//  Export goes the other way: `CalcSide.showdownPasteSet()` builds the
//  lossless paste struct and `showdownText` renders it.
//

import SwiftUI

struct PasteImportSheet: View {
    let side: CalcSide
    let allPokemon: [PKMNStats]
    let allMoves: [MoveData]

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    /// Built once when the sheet opens. Constructing the Champions validator
    /// parses ~600 KB of JSON, so it must not happen per keystroke.
    @State private var importer: PasteImporter?
    /// The user's pick on the scale toggle. nil = automatic: detected when
    /// the numbers are unambiguous, this side's scale when they fit both.
    @State private var forcedScale: StatScale?
    @State private var selectedSlot = 0
    /// Cached so a render doesn't re-parse and re-resolve the paste several
    /// times; refreshed whenever the text, the scale pick or the importer
    /// changes.
    @State private var parsed = ParsedPaste()
    @State private var preview: ImportPreview?

    private var sideScale: StatScale { side.championsMode ? .champions : .mainline }

    private func refresh() {
        parsed = forcedScale.map { ShowdownPaste.parse(text, forcedScale: $0) }
            ?? ShowdownPaste.parse(text, ambiguousDefault: sideScale)
        preview = importer?.preview(parsed)
    }

    /// Show the toggle whenever the numbers fit both scales, including after
    /// the user has picked one (a forced parse no longer reports ambiguity).
    private var scaleIsAmbiguous: Bool {
        parsed.scaleWasAmbiguous || forcedScale != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 160)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Garchomp @ Choice Scarf\nAbility: Rough Skin\nEVs: 252 Atk / 4 Def / 252 Spe\nJolly Nature\n- Earthquake")
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8).padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                    PasteButton(payloadType: String.self) { strings in
                        if let first = strings.first { text = first }
                    }
                } header: {
                    Text("Showdown paste")
                } footer: {
                    Text("Paste one set, or a whole team and pick the set to load.")
                }

                if let preview, !parsed.isEmpty {
                    previewSections(preview)
                } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        Text(importer == nil ? "Loading…" : "No Pokemon found in this text.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Import Paste")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { importSelected() }
                        .disabled(slotToImport == nil)
                }
            }
            .task {
                guard importer == nil else { return }
                importer = PasteImporter(
                    allPokemon: allPokemon, allMoves: allMoves,
                    // Legality only means something for Champions sets.
                    validator: side.championsMode ? ChampionsValidator() : nil,
                    targetScale: sideScale)
                refresh()
            }
            .onChange(of: text) {
                selectedSlot = 0
                forcedScale = nil
                refresh()
            }
            .onChange(of: forcedScale) { refresh() }
        }
    }

    // MARK: - Preview

    private var slotToImport: ResolvedSlot? {
        guard let slots = preview?.slots, slots.indices.contains(selectedSlot) else { return nil }
        let slot = slots[selectedSlot]
        return slot.isBlocked ? nil : slot
    }

    @ViewBuilder
    private func previewSections(_ preview: ImportPreview) -> some View {
        if scaleIsAmbiguous {
            Section {
                Picker("EVs are", selection: scaleBinding) {
                    Text("Mainline (0–252)").tag(StatScale.mainline)
                    Text("Champions (0–32)").tag(StatScale.champions)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("These numbers fit both scales, so this defaults to the calc's current scale. Change it if the paste was written in the other one.")
            }
        }

        if preview.slots.count > 1 {
            Section("Set to load") {
                Picker("Set", selection: $selectedSlot) {
                    ForEach(Array(preview.slots.enumerated()), id: \.offset) { index, slot in
                        Text(slot.displayName).tag(index)
                    }
                }
            }
        }

        if preview.slots.indices.contains(selectedSlot) {
            slotSection(preview.slots[selectedSlot], targetScale: preview.targetScale)
        }

        let lineIssues = preview.parseDiagnostics.filter {
            $0.kind != .ambiguousEVScale
                && ($0.setIndex == nil || $0.setIndex == selectedSlot)
        }
        if !lineIssues.isEmpty {
            Section("Couldn't read") {
                ForEach(Array(lineIssues.enumerated()), id: \.offset) { _, diagnostic in
                    Label("Line \(diagnostic.line): \(diagnostic.message)",
                          systemImage: "text.badge.xmark")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
        }
    }

    private var scaleBinding: Binding<StatScale> {
        Binding(get: { forcedScale ?? parsed.detectedScale },
                set: { forcedScale = $0 })
    }

    @ViewBuilder
    private func slotSection(_ slot: ResolvedSlot, targetScale: StatScale) -> some View {
        Section {
            LabeledContent("Pokemon", value: slot.displayName)
            if let ability = slot.ability {
                LabeledContent("Ability", value: formatAbilityName(ability))
            }
            LabeledContent("Item", value: itemText(slot))
            LabeledContent("Nature", value: slot.nature.name)
            LabeledContent("Level", value: "\(slot.level)")
            LabeledContent(targetScale == .champions ? "Stat points" : "EVs",
                           value: evText(slot.evs))
            ForEach(Array(slot.moves.enumerated()), id: \.offset) { index, move in
                if let move {
                    LabeledContent("Move \(index + 1)", value: move.name)
                } else if index < slot.source.moves.count {
                    LabeledContent("Move \(index + 1)") {
                        Text(slot.source.moves[index]).strikethrough().foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Preview")
        }

        let notes = slot.issues
        let violations = slot.violations
        if !notes.isEmpty || !violations.isEmpty {
            Section("Notes") {
                ForEach(Array(notes.enumerated()), id: \.offset) { _, issue in
                    ImportIssueRow(issue: issue)
                }
                ForEach(Array(violations.enumerated()), id: \.offset) { _, violation in
                    Label(violation.message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(violation.category.isLegality ? .orange : .secondary)
                }
            }
        }
    }

    private func itemText(_ slot: ResolvedSlot) -> String {
        if slot.item != .none { return slot.item.rawValue }
        if let raw = slot.source.item, !raw.isEmpty { return "\(raw) (not modelled)" }
        return "None"
    }

    private func evText(_ evs: ShowdownStats) -> String {
        let parts = [("HP", evs.hp), ("Atk", evs.atk), ("Def", evs.def),
                     ("SpA", evs.spa), ("SpD", evs.spd), ("Spe", evs.spe)]
            .filter { $0.1 != 0 }
            .map { "\($0.1) \($0.0)" }
        return parts.isEmpty ? "None" : parts.joined(separator: " / ")
    }

    // MARK: - Import

    private func importSelected() {
        guard let importer, let slot = slotToImport,
              let spread = importer.savedSpread(for: slot, name: slot.displayName)
        else { return }
        side.loadSpread(spread, allPokemon: allPokemon, allMoves: allMoves)
        // Pasted, not loaded from the saved list.
        side.loadedSpreadName = nil
        dismiss()
    }
}

// MARK: - Shared rows

/// One `ImportIssue`, colored by how much it matters: blocking in red,
/// things the import worked around in orange, purely informational in grey.
/// Unmodelled mainline items (Covert Cloak, Loaded Dice, …) are
/// informational, or good pastes look broken. Shared by the calc's paste
/// sheet and the team import.
struct ImportIssueRow: View {
    let issue: ImportIssue

    var body: some View {
        let (icon, color): (String, Color) = {
            if issue.isBlocking { return ("xmark.octagon", .red) }
            switch issue {
            case .itemUnrecognized, .levelDefaulted, .evScaleConverted:
                return ("info.circle", .secondary)
            default:
                return ("exclamationmark.circle", .orange)
            }
        }()
        Label(issue.message, systemImage: icon)
            .font(.footnote).foregroundStyle(color)
    }
}

// MARK: - Export

extension CalcSide {
    /// This side as a paste set, EVs in the side's own scale. nil with no
    /// species. Champions IVs are fixed at 31, so they're written as 31
    /// (and omitted from the text) whatever the stored values say.
    func showdownPasteSet() -> ShowdownPasteSet? {
        guard let pokemon else { return nil }
        var set = ShowdownPasteSet(species: pokemon.name)
        set.item = heldItem == .none ? nil : heldItem.rawValue
        set.ability = selectedAbility.map { formatAbilityName($0) }
        set.level = level
        set.nature = nature.name
        set.evScale = championsMode ? .champions : .mainline
        set.evs = ShowdownStats(hp: evHP, atk: evAtk, def: evDef,
                                spa: evSpAtk, spd: evSpDef, spe: evSpeed)
        set.ivs = championsMode
            ? ShowdownPasteSet.defaultIVs
            : ShowdownStats(hp: ivHP, atk: ivAtk, def: ivDef,
                            spa: ivSpAtk, spd: ivSpDef, spe: ivSpeed)
        set.moves = moves.compactMap { $0?.name }
        return set
    }
}
