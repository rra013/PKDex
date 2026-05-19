//
//  BattleSimulator.swift
//  PKDex
//
//  Created by Rishi Anand on 5/17/26.
//

import SwiftUI
import SwiftData

// MARK: - Format

enum BattleFormat: String, CaseIterable, Identifiable {
    case singles, doubles
    var id: String { rawValue }
    var label: String { self == .singles ? "Singles" : "Doubles" }
    var activeSlots: Int { self == .singles ? 1 : 2 }
}

// MARK: - Status & Move Effects

enum BattleStatus: String, Equatable {
    case none, burn, paralysis, poison, toxic, sleep

    var shortLabel: String {
        switch self {
        case .none: return ""
        case .burn: return "BRN"
        case .paralysis: return "PAR"
        case .poison: return "PSN"
        case .toxic: return "TOX"
        case .sleep: return "SLP"
        }
    }

    var color: Color {
        switch self {
        case .burn: return .red
        case .paralysis: return .yellow
        case .poison, .toxic: return .purple
        case .sleep: return .gray
        case .none: return .clear
        }
    }
}

enum BattleStatChange {
    case selfMod([(Nature.StatKey, Int)])
    case opponentMod([(Nature.StatKey, Int)])
}

enum BattleHazard {
    case stealthRock, spikes, stickyWeb
}

/// Lookup tables for non-damaging move effects. Keys are normalized via
/// `BattleSimSeed.normalize` (lowercased, alphanumerics only) so the engine works
/// whether `MoveData.name` arrives as "Swords Dance", "swords-dance", or "SwordsDance".
enum BattleMoveEffects {

    static let spreadMoves: Set<String> = [
        "earthquake", "surf", "rockslide", "discharge", "heatwave",
        "blizzard", "muddywater", "lavaplume", "eruption", "icywind",
        "dazzlinggleam", "hypervoice", "snarl", "boomburst", "earthpower",
        "sludgewave", "bulldoze", "explosion", "selfdestruct",
    ]

    static let statChanges: [String: BattleStatChange] = [
        "swordsdance":   .selfMod([(.atk, 2)]),
        "dragondance":   .selfMod([(.atk, 1), (.speed, 1)]),
        "calmmind":      .selfMod([(.spAtk, 1), (.spDef, 1)]),
        "nastyplot":     .selfMod([(.spAtk, 2)]),
        "irondefense":   .selfMod([(.def, 2)]),
        "bulkup":        .selfMod([(.atk, 1), (.def, 1)]),
        "quiverdance":   .selfMod([(.spAtk, 1), (.spDef, 1), (.speed, 1)]),
        "shellsmash":    .selfMod([(.atk, 2), (.spAtk, 2), (.speed, 2), (.def, -1), (.spDef, -1)]),
        "agility":       .selfMod([(.speed, 2)]),
        "rockpolish":    .selfMod([(.speed, 2)]),
        "amnesia":       .selfMod([(.spDef, 2)]),
        "coil":          .selfMod([(.atk, 1), (.def, 1)]),
        "cosmicpower":   .selfMod([(.def, 1), (.spDef, 1)]),
        "howl":          .selfMod([(.atk, 1)]),
        "tailglow":      .selfMod([(.spAtk, 3)]),
        "growl":         .opponentMod([(.atk, -1)]),
        "leer":          .opponentMod([(.def, -1)]),
        "tailwhip":      .opponentMod([(.def, -1)]),
        "charm":         .opponentMod([(.atk, -2)]),
        "screech":       .opponentMod([(.def, -2)]),
        "metalsound":    .opponentMod([(.spDef, -2)]),
        "stringshot":    .opponentMod([(.speed, -1)]),
    ]

    static let statusInflicts: [String: BattleStatus] = [
        "willowisp":     .burn,
        "thunderwave":   .paralysis,
        "stunspore":     .paralysis,
        "glare":         .paralysis,
        "toxic":         .toxic,
        "poisonpowder":  .poison,
        "poisongas":     .poison,
        "sleeppowder":   .sleep,
        "spore":         .sleep,
        "hypnosis":      .sleep,
        "sing":          .sleep,
        "lovelykiss":    .sleep,
    ]

    static let weatherSetters: [String: WeatherCondition] = [
        "sunnyday":         .sun,
        "raindance":        .rain,
        "sandstorm":        .sand,
        "snowscape":        .snow,
        "hail":             .snow,
        "chillyreception":  .snow,
    ]

    static let terrainSetters: [String: TerrainCondition] = [
        "electricterrain": .electric,
        "grassyterrain":   .grassy,
        "mistyterrain":    .misty,
        "psychicterrain":  .psychic,
    ]

    static let hazardSetters: [String: BattleHazard] = [
        "stealthrock": .stealthRock,
        "spikes":      .spikes,
        "stickyweb":   .stickyWeb,
    ]

    /// Abilities that automatically set weather when the Pokemon enters the field
    /// (initial send-out, regular switch, forced switch after a KO, or Mega Evolution).
    /// Keyed by ability ID (matching `computeAbilityModifiers`), not by move name.
    static let weatherAbilities: [String: WeatherCondition] = [
        "drought":         .sun,
        "drizzle":         .rain,
        "sand-stream":     .sand,
        "snow-warning":    .snow,
        "desolate-land":   .sun,
        "primordial-sea":  .rain,
        "orichalcum-pulse": .sun,
    ]

    /// Abilities that automatically set terrain on entry.
    static let terrainAbilities: [String: TerrainCondition] = [
        "electric-surge": .electric,
        "grassy-surge":   .grassy,
        "misty-surge":    .misty,
        "psychic-surge":  .psychic,
        "hadron-engine":  .electric,
    ]
}

// MARK: - Live Participant

@Observable
final class BattleParticipant: Identifiable {
    let id = UUID()
    let slot: TeamSlotInfo
    let stats: PKMNStats?
    let moves: [MoveData]
    let nature: Nature
    let heldItem: HeldItem
    let maxHP: Int

    var currentHP: Int
    var pp: [Int]
    var status: BattleStatus = .none
    var sleepTurnsRemaining: Int = 0
    var toxicCounter: Int = 0

    var atkStage: Int = 0
    var defStage: Int = 0
    var spAtkStage: Int = 0
    var spDefStage: Int = 0
    var speedStage: Int = 0

    /// Set when this Pokemon has Mega Evolved this battle. Persists across switches.
    var megaForm: MegaForm? = nil

    /// True after a one-shot held item (berry, Focus Sash, Mental/White Herb) has
    /// been used. After this point `effectiveHeldItem` returns `.none`.
    var consumedItem: Bool = false

    /// True after Knock Off (or a future item-removal move) has stripped the item.
    var knockedOff: Bool = false

    init(slot: TeamSlotInfo, allPokemon: [PKMNStats], allMoves: [MoveData]) {
        self.slot = slot
        self.stats = allPokemon.first(where: { $0.id == slot.pokemonID })
        self.moves = slot.moveSlots.compactMap { tm in allMoves.first(where: { $0.id == tm.moveID }) }
        self.pp = self.moves.map { $0.pp }
        self.nature = allNatures.first(where: { $0.id == slot.natureID }) ?? allNatures[0]
        self.heldItem = slot.itemRawValue.flatMap { HeldItem(rawValue: $0) } ?? .none

        let base = self.stats?.baseHP ?? 1
        let evHP = slot.championsMode ? championsEVToMain(slot.evHP) : slot.evHP
        let hp = calcHP(base: base, iv: 31, ev: evHP, level: slot.level)
        self.maxHP = hp
        self.currentHP = hp
    }

    var fainted: Bool { currentHP <= 0 }
    var atFullHP: Bool { currentHP >= maxHP }

    // Display + active accessors — swap to the Mega form's values once evolved.
    var displayName: String { megaForm?.displayName ?? slot.pokemonName }
    var activeType1: String { megaForm?.type1 ?? slot.type1 }
    var activeType2: String? { megaForm?.type2 ?? slot.type2 }
    var activeAbility: String? { megaForm?.ability ?? slot.abilityName }

    var types: [String] {
        var t = [activeType1]
        if let t2 = activeType2 { t.append(t2) }
        return t
    }

    var baseAtk: Int   { megaForm?.baseAtk   ?? stats?.baseAtk   ?? 1 }
    var baseDef: Int   { megaForm?.baseDef   ?? stats?.baseDef   ?? 1 }
    var baseSpAtk: Int { megaForm?.baseSpAtk ?? stats?.baseSpAtk ?? 1 }
    var baseSpDef: Int { megaForm?.baseSpDef ?? stats?.baseSpDef ?? 1 }
    var baseSpeed: Int { megaForm?.baseSpeed ?? stats?.baseSpeed ?? 1 }

    var speed: Int {
        let ev = slot.championsMode ? championsEVToMain(slot.evSpeed) : slot.evSpeed
        let raw = calcStat(base: baseSpeed, iv: 31, ev: ev,
                           level: slot.level, natureMod: nature.modifier(for: .speed))
        var v = Int(Double(raw) * statStageMultiplier(stage: speedStage))
        if status == .paralysis { v /= 2 }
        if effectiveHeldItem == .choiceScarf { v = Int(Double(v) * 1.5) }
        return v
    }

    /// Volatile state that doesn't survive a switch. Status and mega state persist;
    /// the toxic counter resets and stat stages clear.
    func resetVolatile() {
        atkStage = 0; defStage = 0; spAtkStage = 0; spDefStage = 0; speedStage = 0
        toxicCounter = 0
    }

    var hasAnyPP: Bool { pp.contains(where: { $0 > 0 }) }

    /// The held item the damage calc should treat this Pokemon as carrying. Returns
    /// `.none` after Mega Evolution (stone is spent), Knock Off, or one-shot
    /// consumption (Focus Sash, berries, etc.).
    var effectiveHeldItem: HeldItem {
        if megaForm != nil { return .none }
        if knockedOff || consumedItem { return .none }
        return heldItem
    }

    /// Move names that show up in this participant's move slots — used by Rayquaza's
    /// Mega Evolution eligibility check (needs Dragon Ascent).
    var moveNames: [String] { moves.map { $0.name } }
}

// MARK: - Side

@Observable
final class BattleSide: Identifiable {
    let id = UUID()
    let label: String
    var participants: [BattleParticipant]
    var activeIndices: [Int]

    // Hazards on this side's field — affect Pokemon switching IN on this side.
    var stealthRock: Bool = false
    var spikesLayers: Int = 0
    var stickyWeb: Bool = false

    /// Each side may Mega Evolve only one Pokemon per battle.
    var hasUsedMega: Bool = false

    init(label: String, slots: [TeamSlotInfo], format: BattleFormat,
         allPokemon: [PKMNStats], allMoves: [MoveData]) {
        self.label = label
        let parts = slots.map { BattleParticipant(slot: $0, allPokemon: allPokemon, allMoves: allMoves) }
        self.participants = parts
        self.activeIndices = Array(0..<min(format.activeSlots, parts.count))
    }

    var hasUnfainted: Bool { participants.contains(where: { !$0.fainted }) }

    func active(at slot: Int) -> BattleParticipant? {
        guard slot < activeIndices.count else { return nil }
        let i = activeIndices[slot]
        return participants.indices.contains(i) ? participants[i] : nil
    }

    func benchIndices() -> [Int] {
        participants.indices.filter { !activeIndices.contains($0) && !participants[$0].fainted }
    }

    var hazardSummary: String {
        var parts: [String] = []
        if stealthRock { parts.append("SR") }
        if spikesLayers > 0 { parts.append("Spikes×\(spikesLayers)") }
        if stickyWeb { parts.append("Web") }
        return parts.joined(separator: " ")
    }
}

// MARK: - Action

enum BattleAction {
    case move(moveIndex: Int, targetSide: Int, targetSlot: Int)
    case spreadMove(moveIndex: Int)
    case switchTo(benchIndex: Int)
    case struggle(targetSide: Int, targetSlot: Int)
}

private struct PlannedAction {
    let sideIndex: Int
    let actorSlot: Int
    let action: BattleAction
}

// MARK: - Log

struct BattleLogEntry: Identifiable {
    let id = UUID()
    let text: String
    var emphasis: Bool = false
}

// MARK: - Engine

@MainActor
@Observable
final class BattleEngine {
    let format: BattleFormat
    let side1: BattleSide
    let side2: BattleSide
    let allPokemon: [PKMNStats]
    let allMoves: [MoveData]

    var log: [BattleLogEntry] = []
    var turn: Int = 1
    var winner: Int? = nil
    var pendingActions: [[BattleAction?]]
    var pendingForceSwitches: [ForceSwitch] = []

    var weather: WeatherCondition = .none
    var weatherTurns: Int = 0
    var terrain: TerrainCondition = .none
    var terrainTurns: Int = 0

    /// When true for a given [side][slot], that actor will Mega Evolve at the start of
    /// the next executed turn (before any action). Cleared once processed.
    var pendingMega: [[Bool]]

    struct ForceSwitch: Identifiable, Equatable {
        let side: Int
        let slot: Int
        var id: String { "\(side)-\(slot)" }
    }

    init(format: BattleFormat, side1: BattleSide, side2: BattleSide,
         allPokemon: [PKMNStats], allMoves: [MoveData]) {
        self.format = format
        self.side1 = side1
        self.side2 = side2
        self.allPokemon = allPokemon
        self.allMoves = allMoves
        let slots = format.activeSlots
        self.pendingActions = [Array(repeating: nil, count: slots),
                               Array(repeating: nil, count: slots)]
        self.pendingMega = [Array(repeating: false, count: slots),
                            Array(repeating: false, count: slots)]
        self.log.append(BattleLogEntry(text: "Turn 1 begin", emphasis: true))
        for s in 0..<2 {
            let side = self.side(at: s)
            for slot in 0..<format.activeSlots {
                if let p = side.active(at: slot) {
                    self.log.append(BattleLogEntry(text: "\(side.label) sent out \(p.displayName)!"))
                    self.activateEntryAbility(for: p, ownSide: s)
                }
            }
        }
    }

    func side(at i: Int) -> BattleSide { i == 0 ? side1 : side2 }

    func setAction(side: Int, slot: Int, action: BattleAction) {
        pendingActions[side][slot] = action
    }

    func clearAction(side: Int, slot: Int) {
        pendingActions[side][slot] = nil
        pendingMega[side][slot] = false
    }

    // MARK: Mega Evolution

    /// Returns true if the actor at (side, slot) is eligible to Mega Evolve right now:
    /// their side hasn't used its mega yet, they aren't already mega'd, and their
    /// species + held item (or Dragon Ascent, for Rayquaza) maps to a known Mega form.
    func canMegaEvolve(side sIdx: Int, slot: Int) -> Bool {
        if side(at: sIdx).hasUsedMega { return false }
        guard let actor = side(at: sIdx).active(at: slot), !actor.fainted else { return false }
        if actor.megaForm != nil { return false }
        return MegaForms.form(forSpecies: actor.slot.pokemonName,
                              heldItem: actor.heldItem,
                              moveNames: actor.moveNames) != nil
    }

    func megaBinding(side: Int, slot: Int) -> Binding<Bool> {
        Binding(
            get: { self.pendingMega[side][slot] },
            set: { self.pendingMega[side][slot] = $0 }
        )
    }

    /// Evolves any actors that asked to Mega Evolve this turn, in speed order. Honors
    /// the once-per-side limit even if both slots in doubles toggled it on.
    private func processPendingMegas() {
        struct Candidate { let side: Int; let slot: Int; let speed: Int }
        var candidates: [Candidate] = []
        for s in 0..<2 {
            for slot in 0..<format.activeSlots {
                guard pendingMega[s][slot] else { continue }
                guard canMegaEvolve(side: s, slot: slot) else { continue }
                let speed = side(at: s).active(at: slot)?.speed ?? 0
                candidates.append(Candidate(side: s, slot: slot, speed: speed))
            }
        }
        candidates.sort { $0.speed > $1.speed }

        for c in candidates {
            // The first mega on a side disqualifies any second candidate on the same side.
            if side(at: c.side).hasUsedMega { continue }
            guard let actor = side(at: c.side).active(at: c.slot) else { continue }
            guard let form = MegaForms.form(forSpecies: actor.slot.pokemonName,
                                            heldItem: actor.heldItem,
                                            moveNames: actor.moveNames) else { continue }
            actor.megaForm = form
            side(at: c.side).hasUsedMega = true
            log.append(BattleLogEntry(text: "\(actor.slot.pokemonName) Mega Evolved into \(form.displayName)!", emphasis: true))
            // The post-Mega ability is now active and may set weather/terrain/Intimidate.
            activateEntryAbility(for: actor, ownSide: c.side)
        }

        let slots = format.activeSlots
        pendingMega = [Array(repeating: false, count: slots),
                       Array(repeating: false, count: slots)]
    }

    var allActionsChosen: Bool {
        if winner != nil { return false }
        if !pendingForceSwitches.isEmpty { return false }
        for s in 0..<2 {
            for i in 0..<format.activeSlots {
                guard let active = side(at: s).active(at: i) else { continue }
                if active.fainted { continue }
                // A participant with no moves and no bench cannot act at all; skip.
                if active.moves.isEmpty && side(at: s).benchIndices().isEmpty { continue }
                if pendingActions[s][i] == nil { return false }
            }
        }
        return true
    }

    // MARK: Turn Execution

    func executeTurn() {
        // Mega Evolutions resolve before any action this turn.
        processPendingMegas()

        var actions: [PlannedAction] = []
        for s in 0..<2 {
            for i in 0..<format.activeSlots {
                guard let active = side(at: s).active(at: i), !active.fainted else { continue }
                guard let a = pendingActions[s][i] else { continue }
                actions.append(PlannedAction(sideIndex: s, actorSlot: i, action: a))
            }
        }

        // Switches first, then by move priority (desc), then by speed (desc), random ties.
        actions.sort { a, b in
            let aIsSwitch = isSwitchAction(a.action)
            let bIsSwitch = isSwitchAction(b.action)
            if aIsSwitch && !bIsSwitch { return true }
            if !aIsSwitch && bIsSwitch { return false }
            if aIsSwitch && bIsSwitch { return Bool.random() }

            let pa = priority(side: a.sideIndex, slot: a.actorSlot, action: a.action)
            let pb = priority(side: b.sideIndex, slot: b.actorSlot, action: b.action)
            if pa != pb { return pa > pb }
            let sa = side(at: a.sideIndex).active(at: a.actorSlot)?.speed ?? 0
            let sb = side(at: b.sideIndex).active(at: b.actorSlot)?.speed ?? 0
            if sa != sb { return sa > sb }
            return Bool.random()
        }

        for action in actions {
            performAction(action)
            checkForKOsAndEnd()
            if winner != nil { break }
        }

        if winner == nil {
            endOfTurnEffects()
            checkForKOsAndEnd()
        }

        let slots = format.activeSlots
        pendingActions = [Array(repeating: nil, count: slots),
                          Array(repeating: nil, count: slots)]

        if winner == nil {
            updateForceSwitchQueue()
            if pendingForceSwitches.isEmpty {
                turn += 1
                log.append(BattleLogEntry(text: "—"))
                log.append(BattleLogEntry(text: "Turn \(turn) begin", emphasis: true))
            }
        }
    }

    private func isSwitchAction(_ a: BattleAction) -> Bool {
        if case .switchTo = a { return true }
        return false
    }

    private func priority(side: Int, slot: Int, action: BattleAction) -> Int {
        guard let actor = self.side(at: side).active(at: slot) else { return 0 }
        switch action {
        case .move(let mi, _, _), .spreadMove(let mi):
            return actor.moves.indices.contains(mi) ? actor.moves[mi].priority : 0
        case .struggle:
            return 0
        case .switchTo:
            return 6
        }
    }

    private func performAction(_ pa: PlannedAction) {
        guard let actor = side(at: pa.sideIndex).active(at: pa.actorSlot), !actor.fainted else { return }
        _ = actor
        switch pa.action {
        case .switchTo(let bench):
            performSwitch(sideIndex: pa.sideIndex, slot: pa.actorSlot, benchIndex: bench)
        case .move(let mi, let ts, let tslot):
            performMove(attackerSide: pa.sideIndex, attackerSlot: pa.actorSlot,
                        moveIndex: mi, defenderSide: ts, defenderSlot: tslot)
        case .spreadMove(let mi):
            performSpreadMove(attackerSide: pa.sideIndex, attackerSlot: pa.actorSlot, moveIndex: mi)
        case .struggle(let ts, let tslot):
            performStruggle(attackerSide: pa.sideIndex, attackerSlot: pa.actorSlot,
                            defenderSide: ts, defenderSlot: tslot)
        }
    }

    // MARK: Switches & Hazards

    private func performSwitch(sideIndex i: Int, slot: Int, benchIndex: Int) {
        let s = side(at: i)
        guard benchIndex < s.participants.count,
              !s.participants[benchIndex].fainted,
              !s.activeIndices.contains(benchIndex) else { return }
        let outgoing = s.active(at: slot)
        outgoing?.resetVolatile()
        s.activeIndices[slot] = benchIndex
        let incoming = s.participants[benchIndex]
        if let outName = outgoing?.displayName {
            log.append(BattleLogEntry(text: "\(s.label) withdrew \(outName)."))
        }
        log.append(BattleLogEntry(text: "\(s.label) sent out \(incoming.displayName)!"))
        applyHazardsOnSwitchIn(p: incoming, side: s)
        if !incoming.fainted { activateEntryAbility(for: incoming, ownSide: i) }
    }

    func forceSwitch(side: Int, slot: Int, benchIndex: Int) {
        let s = self.side(at: side)
        guard benchIndex < s.participants.count,
              !s.participants[benchIndex].fainted,
              !s.activeIndices.contains(benchIndex) else { return }
        s.activeIndices[slot] = benchIndex
        let p = s.participants[benchIndex]
        log.append(BattleLogEntry(text: "\(s.label) sent out \(p.displayName)!"))
        applyHazardsOnSwitchIn(p: p, side: s)
        if !p.fainted { activateEntryAbility(for: p, ownSide: side) }
        pendingForceSwitches.removeAll { $0.side == side && $0.slot == slot }
        checkForKOsAndEnd()
        if pendingForceSwitches.isEmpty && winner == nil {
            turn += 1
            log.append(BattleLogEntry(text: "—"))
            log.append(BattleLogEntry(text: "Turn \(turn) begin", emphasis: true))
        }
    }

    private func applyHazardsOnSwitchIn(p: BattleParticipant, side: BattleSide) {
        let grounded = !p.types.contains("Flying")

        if side.stealthRock {
            let rockEff = computeTypeEffectiveness(moveType: "Rock", defenderTypes: p.types)
            let dmg = Int((Double(p.maxHP) / 8.0 * rockEff).rounded())
            if dmg > 0 {
                p.currentHP = max(0, p.currentHP - dmg)
                log.append(BattleLogEntry(text: "\(p.displayName) is hurt by Stealth Rock! (-\(dmg) HP)"))
            }
        }
        if side.spikesLayers > 0 && grounded {
            let denom: Double = side.spikesLayers == 1 ? 8 : (side.spikesLayers == 2 ? 6 : 4)
            let dmg = max(1, Int((Double(p.maxHP) / denom).rounded()))
            p.currentHP = max(0, p.currentHP - dmg)
            log.append(BattleLogEntry(text: "\(p.displayName) is hurt by Spikes! (-\(dmg) HP)"))
        }
        if side.stickyWeb && grounded {
            p.speedStage = max(-6, p.speedStage - 1)
            log.append(BattleLogEntry(text: "\(p.displayName) was caught in Sticky Web! Speed fell."))
        }
        if p.fainted {
            log.append(BattleLogEntry(text: "\(p.displayName) fainted!", emphasis: true))
        }
    }

    // MARK: Move Execution

    private func preMoveStatusCheck(_ p: BattleParticipant) -> Bool {
        if p.status == .sleep {
            p.sleepTurnsRemaining -= 1
            if p.sleepTurnsRemaining <= 0 {
                p.status = .none
                log.append(BattleLogEntry(text: "\(p.displayName) woke up!"))
            } else {
                log.append(BattleLogEntry(text: "\(p.displayName) is fast asleep."))
                return false
            }
        }
        if p.status == .paralysis && Double.random(in: 0..<1) < 0.25 {
            log.append(BattleLogEntry(text: "\(p.displayName) is fully paralyzed! It can't move!"))
            return false
        }
        return true
    }

    private func performMove(attackerSide: Int, attackerSlot: Int,
                             moveIndex: Int, defenderSide: Int, defenderSlot: Int) {
        let aSide = side(at: attackerSide)
        let dSide = side(at: defenderSide)
        guard let attacker = aSide.active(at: attackerSlot), !attacker.fainted else { return }
        guard moveIndex < attacker.moves.count else { return }
        let move = attacker.moves[moveIndex]

        if !preMoveStatusCheck(attacker) { return }

        if attacker.pp.indices.contains(moveIndex), attacker.pp[moveIndex] <= 0 {
            log.append(BattleLogEntry(text: "\(attacker.displayName) has no PP left for \(move.name)!"))
            return
        }

        log.append(BattleLogEntry(text: "\(attacker.displayName) used \(move.name)!"))
        if attacker.pp.indices.contains(moveIndex) { attacker.pp[moveIndex] -= 1 }

        if let acc = move.accuracy {
            let roll = Int.random(in: 1...100)
            if roll > acc {
                log.append(BattleLogEntry(text: "It missed!"))
                return
            }
        }

        // Retarget if the intended target fainted before this action resolved.
        var defender = dSide.active(at: defenderSlot)
        if defender == nil || defender?.fainted == true {
            defender = (0..<format.activeSlots).compactMap { dSide.active(at: $0) }
                .first(where: { !$0.fainted })
        }

        if move.damageClass == "status" {
            applyStatusMoveEffect(move: move, attacker: attacker,
                                  attackerSideIdx: attackerSide,
                                  defender: defender, defenderSideIdx: defenderSide)
            return
        }

        guard let defender else {
            log.append(BattleLogEntry(text: "\(attacker.displayName)'s attack had no target."))
            return
        }

        applyDamageHit(attacker: attacker, defender: defender, move: move, isSpread: false)
    }

    private func performSpreadMove(attackerSide: Int, attackerSlot: Int, moveIndex: Int) {
        let aSide = side(at: attackerSide)
        let defenderSideIdx = 1 - attackerSide
        let dSide = side(at: defenderSideIdx)
        guard let attacker = aSide.active(at: attackerSlot), !attacker.fainted else { return }
        guard moveIndex < attacker.moves.count else { return }
        let move = attacker.moves[moveIndex]

        if !preMoveStatusCheck(attacker) { return }

        if attacker.pp.indices.contains(moveIndex), attacker.pp[moveIndex] <= 0 {
            log.append(BattleLogEntry(text: "\(attacker.displayName) has no PP left for \(move.name)!"))
            return
        }

        log.append(BattleLogEntry(text: "\(attacker.displayName) used \(move.name)!"))
        if attacker.pp.indices.contains(moveIndex) { attacker.pp[moveIndex] -= 1 }

        if let acc = move.accuracy {
            let roll = Int.random(in: 1...100)
            if roll > acc {
                log.append(BattleLogEntry(text: "It missed!"))
                return
            }
        }

        if move.damageClass == "status" {
            let first = (0..<format.activeSlots).compactMap { dSide.active(at: $0) }
                .first(where: { !$0.fainted })
            applyStatusMoveEffect(move: move, attacker: attacker,
                                  attackerSideIdx: attackerSide,
                                  defender: first, defenderSideIdx: defenderSideIdx)
            return
        }

        for slot in 0..<format.activeSlots {
            guard let defender = dSide.active(at: slot), !defender.fainted else { continue }
            applyDamageHit(attacker: attacker, defender: defender, move: move, isSpread: true)
        }
    }

    private func performStruggle(attackerSide: Int, attackerSlot: Int,
                                 defenderSide: Int, defenderSlot: Int) {
        let aSide = side(at: attackerSide)
        let dSide = side(at: defenderSide)
        guard let attacker = aSide.active(at: attackerSlot), !attacker.fainted else { return }

        if !preMoveStatusCheck(attacker) { return }

        log.append(BattleLogEntry(text: "\(attacker.displayName) used Struggle!"))

        var defender = dSide.active(at: defenderSlot)
        if defender == nil || defender?.fainted == true {
            defender = (0..<format.activeSlots).compactMap { dSide.active(at: $0) }
                .first(where: { !$0.fainted })
        }
        guard let defender else {
            log.append(BattleLogEntry(text: "No target remained."))
            return
        }

        // Compute struggle damage directly with calcDamageRange, bypassing the
        // VM (Struggle has no real MoveData and no type-effect / STAB).
        let proxyA = CalcSide(); configure(side: proxyA, from: attacker, withMove: nil)
        let proxyD = CalcSide(); configure(side: proxyD, from: defender, withMove: nil)
        let burn = attacker.status == .burn ? 0.5 : 1.0

        let raw = calcDamageRange(
            level: attacker.slot.level, movePower: 50,
            userAtk: proxyA.atk, defenderDef: proxyD.def,
            multi: false, weatherMult: 1.0, glaiveRush: false,
            crit: false, critMultiplier: 1.5,
            stabBonus: 1.0, typeEffect: 1.0,
            burnReduction: burn, abilityMods: AbilityModResult(),
            zMoveBypass: false
        )

        let dMin = Int(raw.min)
        let dMax = max(Int(raw.max), dMin)
        let damage = dMin == dMax ? dMin : Int.random(in: dMin...dMax)
        defender.currentHP = max(0, defender.currentHP - damage)
        log.append(BattleLogEntry(text: "\(defender.displayName) took \(damage) damage."))
        if defender.fainted {
            log.append(BattleLogEntry(text: "\(defender.displayName) fainted!", emphasis: true))
        }

        // Recoil: 1/4 of attacker's max HP.
        let recoil = max(1, attacker.maxHP / 4)
        attacker.currentHP = max(0, attacker.currentHP - recoil)
        log.append(BattleLogEntry(text: "\(attacker.displayName) is hit with recoil! (-\(recoil) HP)"))
        if attacker.fainted {
            log.append(BattleLogEntry(text: "\(attacker.displayName) fainted!", emphasis: true))
        }
    }

    private func applyDamageHit(attacker: BattleParticipant, defender: BattleParticipant,
                                move: MoveData, isSpread: Bool) {
        // Snapshot data we need *before* the hit lands: damage calc reads
        // effectiveHeldItem, and item-related effects below need the pre-hit state.
        let defenderHadItemBefore = defender.effectiveHeldItem != .none
        let preBerry = defender.effectiveHeldItem
        let wasFullHP = defender.atFullHP

        let isKnockOff = BattleSimSeed.normalize(move.name) == "knockoff"

        let result = computeDamage(attacker: attacker, defender: defender, move: move, isSpread: isSpread)
        if result.eff == 0 {
            log.append(BattleLogEntry(text: "It doesn't affect \(defender.displayName)…"))
            return
        }
        let dMin = Int(result.min)
        let dMax = max(Int(result.max), dMin)
        var damage = dMin == dMax ? dMin : Int.random(in: dMin...dMax)
        // Knock Off: 1.5x damage when the defender has a removable item (any item
        // except Mega Stones counts here for the boost; Sticky Hold doesn't block the
        // boost, only the removal).
        if isKnockOff && defenderHadItemBefore && !preBerry.isMegaStone {
            damage = Int(Double(damage) * 1.5)
        }

        defender.currentHP = max(0, defender.currentHP - damage)

        // Focus Sash / Focus Band — survive a would-be OHKO at 1 HP.
        if defender.currentHP == 0 {
            if wasFullHP && defender.effectiveHeldItem == .focusSash {
                defender.currentHP = 1
                defender.consumedItem = true
                log.append(BattleLogEntry(text: "\(defender.displayName) hung on with its Focus Sash!"))
            } else if defender.effectiveHeldItem == .focusBand && Double.random(in: 0..<1) < 0.1 {
                defender.currentHP = 1
                log.append(BattleLogEntry(text: "\(defender.displayName) hung on using Focus Band!"))
            }
        }

        var effText = ""
        if result.eff > 1 { effText = " It's super effective!" }
        else if result.eff < 1 && result.eff > 0 { effText = " It's not very effective…" }
        log.append(BattleLogEntry(text: "\(defender.displayName) took \(damage) damage.\(effText)"))

        // Type-resist berry consumption — the damage halving was already baked in by
        // `computeItemModifiers`; we just need to mark the berry spent.
        if !defender.consumedItem,
           let resistedType = typeResistBerryMap[preBerry],
           resistedType == move.type, result.eff > 1.0 {
            defender.consumedItem = true
            log.append(BattleLogEntry(text: "\(defender.displayName)'s \(preBerry.rawValue) weakened the attack!"))
        } else if !defender.consumedItem, preBerry == .chilanBerry, move.type == "Normal" {
            defender.consumedItem = true
            log.append(BattleLogEntry(text: "\(defender.displayName)'s Chilan Berry weakened the attack!"))
        }

        // HP-restore berry (Sitrus, Oran) after the hit.
        maybeTriggerHPBerry(for: defender)

        // Shell Bell — attacker recovers a slice of damage dealt.
        if !attacker.fainted,
           attacker.effectiveHeldItem == .shellBell,
           damage > 0, attacker.currentHP < attacker.maxHP {
            let heal = max(1, damage / 8)
            attacker.currentHP = min(attacker.maxHP, attacker.currentHP + heal)
            log.append(BattleLogEntry(text: "\(attacker.displayName) recovered HP via Shell Bell."))
        }

        // Knock Off — strip the item if defender survived and Sticky Hold doesn't
        // protect it. Mega Stones can't be knocked off.
        if isKnockOff, defenderHadItemBefore, !defender.fainted {
            if defender.activeAbility == "sticky-hold" {
                log.append(BattleLogEntry(text: "\(defender.displayName)'s Sticky Hold kept its item!"))
            } else if !preBerry.isMegaStone {
                defender.knockedOff = true
                log.append(BattleLogEntry(text: "\(defender.displayName)'s \(preBerry.rawValue) was knocked off!"))
            }
        }

        if defender.fainted {
            log.append(BattleLogEntry(text: "\(defender.displayName) fainted!", emphasis: true))
        }
    }

    /// Trigger Sitrus / Oran when HP drops to 1/2 or below. One-shot per battle.
    private func maybeTriggerHPBerry(for p: BattleParticipant) {
        guard !p.consumedItem, p.currentHP > 0 else { return }
        let hpFrac = Double(p.currentHP) / Double(max(p.maxHP, 1))
        switch p.effectiveHeldItem {
        case .sitrusBerry where hpFrac <= 0.5:
            let heal = max(1, p.maxHP / 4)
            p.currentHP = min(p.maxHP, p.currentHP + heal)
            p.consumedItem = true
            log.append(BattleLogEntry(text: "\(p.displayName) ate its Sitrus Berry! Restored HP."))
        case .oranBerry where hpFrac <= 0.5:
            let heal = 10
            p.currentHP = min(p.maxHP, p.currentHP + heal)
            p.consumedItem = true
            log.append(BattleLogEntry(text: "\(p.displayName) ate its Oran Berry! Restored 10 HP."))
        default:
            break
        }
    }

    // MARK: Status-move dispatch

    private func applyStatusMoveEffect(move: MoveData, attacker: BattleParticipant,
                                       attackerSideIdx: Int,
                                       defender: BattleParticipant?,
                                       defenderSideIdx: Int) {
        let key = BattleSimSeed.normalize(move.name)

        if let change = BattleMoveEffects.statChanges[key] {
            applyStatChange(change, attacker: attacker, defender: defender)
            return
        }
        if let status = BattleMoveEffects.statusInflicts[key] {
            if let d = defender {
                tryInflictStatus(status, on: d)
            }
            return
        }
        if let w = BattleMoveEffects.weatherSetters[key] {
            setWeather(w, name: move.name)
            return
        }
        if let t = BattleMoveEffects.terrainSetters[key] {
            setTerrain(t, name: move.name)
            return
        }
        if let h = BattleMoveEffects.hazardSetters[key] {
            setHazard(h, sideIdx: defenderSideIdx, moveName: move.name)
            return
        }
        log.append(BattleLogEntry(text: "(\(move.name) had no simulated effect.)"))
    }

    private func applyStatChange(_ change: BattleStatChange,
                                 attacker: BattleParticipant,
                                 defender: BattleParticipant?) {
        switch change {
        case .selfMod(let mods):
            for (stat, delta) in mods {
                changeStage(attacker, stat: stat, by: delta)
            }
            log.append(BattleLogEntry(text: "\(attacker.displayName)'s stats changed!"))
        case .opponentMod(let mods):
            guard let d = defender else { return }
            // Drops from the attacker flow through opposing-drop logic so guard
            // abilities (Clear Body, Hyper Cutter, ...) and reactive abilities
            // (Defiant, Competitive) trigger the same way they do off Intimidate.
            for (stat, delta) in mods {
                applyOpposingStatDrop(to: d, stat: stat, delta: delta)
            }
            log.append(BattleLogEntry(text: "\(d.displayName)'s stats changed!"))
        }
    }

    private func changeStage(_ p: BattleParticipant, stat: Nature.StatKey, by delta: Int) {
        switch stat {
        case .atk:   p.atkStage   = max(-6, min(6, p.atkStage + delta))
        case .def:   p.defStage   = max(-6, min(6, p.defStage + delta))
        case .spAtk: p.spAtkStage = max(-6, min(6, p.spAtkStage + delta))
        case .spDef: p.spDefStage = max(-6, min(6, p.spDefStage + delta))
        case .speed: p.speedStage = max(-6, min(6, p.speedStage + delta))
        }
    }

    private func tryInflictStatus(_ status: BattleStatus, on target: BattleParticipant) {
        guard target.status == .none else {
            log.append(BattleLogEntry(text: "But \(target.displayName) already has a status condition!"))
            return
        }
        guard canApplyStatus(status, to: target) else {
            log.append(BattleLogEntry(text: "It had no effect on \(target.displayName)."))
            return
        }
        target.status = status
        if status == .sleep {
            target.sleepTurnsRemaining = Int.random(in: 1...3)
        }
        if status == .toxic {
            target.toxicCounter = 0
        }
        log.append(BattleLogEntry(text: "\(target.displayName) was afflicted with \(status.shortLabel)!"))

        // Status-curing berry kicks in immediately if the holder has the right berry.
        maybeTriggerStatusBerry(for: target)
    }

    /// Consume Lum / Cheri / Chesto / Pecha / Rawst / Aspear when the holder picks
    /// up the matching status, clearing the status the same turn it was inflicted.
    private func maybeTriggerStatusBerry(for p: BattleParticipant) {
        guard !p.consumedItem, p.status != .none else { return }
        let item = p.effectiveHeldItem
        let cures: Bool
        switch item {
        case .lumBerry:    cures = true
        case .cheriBerry:  cures = p.status == .paralysis
        case .chestoBerry: cures = p.status == .sleep
        case .pechaBerry:  cures = p.status == .poison || p.status == .toxic
        case .rawstBerry:  cures = p.status == .burn
        case .aspearBerry: cures = false // no freeze in this engine yet
        default:           cures = false
        }
        guard cures else { return }
        let prior = p.status
        p.status = .none
        p.toxicCounter = 0
        p.sleepTurnsRemaining = 0
        p.consumedItem = true
        log.append(BattleLogEntry(text: "\(p.displayName) ate its \(item.rawValue), curing \(prior.shortLabel)."))
    }

    private func canApplyStatus(_ status: BattleStatus, to target: BattleParticipant) -> Bool {
        let t = target.types
        switch status {
        case .burn:      return !t.contains("Fire")
        case .paralysis: return !t.contains("Electric")
        case .poison, .toxic: return !t.contains("Poison") && !t.contains("Steel")
        case .sleep:     return true
        case .none:      return false
        }
    }

    private func setWeather(_ w: WeatherCondition, name: String) {
        weather = w
        weatherTurns = 5
        log.append(BattleLogEntry(text: "\(name): the weather is now \(w.rawValue)."))
    }

    private func setTerrain(_ t: TerrainCondition, name: String) {
        terrain = t
        terrainTurns = 5
        log.append(BattleLogEntry(text: "\(name): the terrain is now \(t.rawValue)."))
    }

    /// Fires the participant's on-entry ability effects: weather/terrain setters and
    /// Intimidate. Called on initial send-out, after a regular or forced switch, and
    /// after Mega Evolution. Uses `activeAbility` so post-Mega abilities (Drought from
    /// Mega Charizard Y, Sand Stream from Mega Tyranitar, Intimidate from Mega
    /// Manectric, etc.) also trigger correctly.
    private func activateEntryAbility(for p: BattleParticipant, ownSide: Int) {
        guard let ability = p.activeAbility else { return }

        if let w = BattleMoveEffects.weatherAbilities[ability], weather != w {
            weather = w
            weatherTurns = 5
            log.append(BattleLogEntry(text: "\(p.displayName)'s \(formatAbilityName(ability)) set the weather to \(w.rawValue)!"))
        }
        if let t = BattleMoveEffects.terrainAbilities[ability], terrain != t {
            terrain = t
            terrainTurns = 5
            log.append(BattleLogEntry(text: "\(p.displayName)'s \(formatAbilityName(ability)) set \(t.rawValue) Terrain!"))
        }
        if ability == "intimidate" {
            applyIntimidate(from: p, ownSide: ownSide)
        }
    }

    // MARK: Stat Drops & Reactive Abilities

    /// Reads the current stage for a given stat. Used to detect whether an opposing
    /// drop actually moved the needle (e.g. -1 against a stat already at -6 is a no-op,
    /// and should NOT trigger Defiant/Competitive).
    private func currentStage(of p: BattleParticipant, stat: Nature.StatKey) -> Int {
        switch stat {
        case .atk:   return p.atkStage
        case .def:   return p.defStage
        case .spAtk: return p.spAtkStage
        case .spDef: return p.spDefStage
        case .speed: return p.speedStage
        }
    }

    /// Applies a stat change to `target` coming from an *opposing* source (Intimidate
    /// switch-in, Growl, Leer, Screech, etc.). Negative deltas pass through guard
    /// abilities (Clear Body, Hyper Cutter, ...) and trigger reactive abilities
    /// (Defiant, Competitive) when a drop succeeds. Non-negative deltas pass through
    /// unchanged.
    @discardableResult
    private func applyOpposingStatDrop(to target: BattleParticipant,
                                       stat: Nature.StatKey,
                                       delta: Int) -> Bool {
        guard delta < 0 else {
            changeStage(target, stat: stat, by: delta)
            return true
        }

        if let ability = target.activeAbility {
            let blanketBlockers: Set<String> = ["clear-body", "white-smoke", "full-metal-body"]
            if blanketBlockers.contains(ability) {
                log.append(BattleLogEntry(text: "\(target.displayName)'s \(formatAbilityName(ability)) prevented the stat drop!"))
                return false
            }
            if ability == "hyper-cutter" && stat == .atk {
                log.append(BattleLogEntry(text: "\(target.displayName)'s Hyper Cutter prevented the Attack drop!"))
                return false
            }
            if ability == "big-pecks" && stat == .def {
                log.append(BattleLogEntry(text: "\(target.displayName)'s Big Pecks prevented the Defense drop!"))
                return false
            }
        }

        let before = currentStage(of: target, stat: stat)
        changeStage(target, stat: stat, by: delta)
        let after = currentStage(of: target, stat: stat)
        // No reactive trigger if the stat was already at -6 (clamped to no change).
        guard after < before else { return false }

        if let ability = target.activeAbility {
            switch ability {
            case "defiant":
                changeStage(target, stat: .atk, by: 2)
                log.append(BattleLogEntry(text: "\(target.displayName)'s Defiant sharply raised its Attack!"))
            case "competitive":
                changeStage(target, stat: .spAtk, by: 2)
                log.append(BattleLogEntry(text: "\(target.displayName)'s Competitive sharply raised its Sp. Atk!"))
            default:
                break
            }
        }
        return true
    }

    /// Intimidate's on-entry effect: lowers each opposing active Pokemon's Attack by
    /// one stage. Respects the Gen 8+ Intimidate-only immunities (Inner Focus,
    /// Oblivious, Own Tempo, Scrappy) plus the blanket guard abilities and reactive
    /// boosts handled by `applyOpposingStatDrop`.
    private func applyIntimidate(from source: BattleParticipant, ownSide: Int) {
        let oppSide = side(at: 1 - ownSide)
        log.append(BattleLogEntry(text: "\(source.displayName)'s Intimidate kicks in!"))
        let intimImmune: Set<String> = ["inner-focus", "oblivious", "own-tempo", "scrappy"]
        for slot in 0..<format.activeSlots {
            guard let target = oppSide.active(at: slot), !target.fainted else { continue }
            if let ability = target.activeAbility, intimImmune.contains(ability) {
                log.append(BattleLogEntry(text: "\(target.displayName)'s \(formatAbilityName(ability)) shrugged off Intimidate!"))
                continue
            }
            applyOpposingStatDrop(to: target, stat: .atk, delta: -1)
        }
    }

    private func setHazard(_ h: BattleHazard, sideIdx: Int, moveName: String) {
        let s = side(at: sideIdx)
        switch h {
        case .stealthRock:
            if s.stealthRock {
                log.append(BattleLogEntry(text: "Stealth Rock is already set on \(s.label)'s field."))
                return
            }
            s.stealthRock = true
        case .spikes:
            if s.spikesLayers >= 3 {
                log.append(BattleLogEntry(text: "Spikes are already at max on \(s.label)'s field."))
                return
            }
            s.spikesLayers += 1
        case .stickyWeb:
            if s.stickyWeb {
                log.append(BattleLogEntry(text: "Sticky Web is already set on \(s.label)'s field."))
                return
            }
            s.stickyWeb = true
        }
        log.append(BattleLogEntry(text: "\(moveName) set hazards on \(s.label)'s field."))
    }

    // MARK: Damage Bridge

    /// Reuse the existing damage calculator end-to-end so STAB, ability, item, weather,
    /// terrain, type, and stat-stage logic stays the single source of truth.
    private func computeDamage(attacker: BattleParticipant, defender: BattleParticipant,
                               move: MoveData, isSpread: Bool) -> (min: Double, max: Double, eff: Double) {
        let vm = DamageCalcVM()
        configure(side: vm.side1, from: attacker, withMove: move)
        configure(side: vm.side2, from: defender, withMove: nil)
        vm.multi = isSpread
        vm.burn = attacker.status == .burn
        vm.weather = weather
        vm.terrain = terrain
        guard let r = vm.side1Results.first else { return (0, 0, 1) }
        return (r.damageMin, r.damageMax, r.effectiveness)
    }

    private func configure(side: CalcSide, from p: BattleParticipant, withMove move: MoveData?) {
        if let mega = p.megaForm {
            // Feed the damage calc a transient PKMNStats representing the Mega form so
            // types, base stats, and ability all reflect post-evolution values.
            side.pokemon = PKMNStats(
                id: p.stats?.id ?? 0,
                speciesID: p.stats?.speciesID ?? 0,
                name: mega.displayName,
                formName: "mega",
                type1: mega.type1, type2: mega.type2,
                baseHP: p.stats?.baseHP ?? 1,
                baseAtk: mega.baseAtk, baseDef: mega.baseDef,
                baseSpAtk: mega.baseSpAtk, baseSpDef: mega.baseSpDef,
                baseSpeed: mega.baseSpeed,
                ability1: mega.ability, ability2: nil, hiddenAbility: nil,
                learnableMoveIDs: []
            )
            side.selectedAbility = mega.ability
        } else {
            side.pokemon = p.stats
            side.selectedAbility = p.slot.abilityName
        }
        side.level = p.slot.level
        side.nature = p.nature
        side.heldItem = p.effectiveHeldItem
        side.atFullHP = p.atFullHP
        side.championsMode = p.slot.championsMode
        side.evHP = p.slot.evHP
        side.evAtk = p.slot.evAtk
        side.evDef = p.slot.evDef
        side.evSpAtk = p.slot.evSpAtk
        side.evSpDef = p.slot.evSpDef
        side.evSpeed = p.slot.evSpeed
        side.ivHP = 31; side.ivAtk = 31; side.ivDef = 31
        side.ivSpAtk = 31; side.ivSpDef = 31; side.ivSpeed = 31
        side.atkStage = p.atkStage
        side.defStage = p.defStage
        side.spAtkStage = p.spAtkStage
        side.spDefStage = p.spDefStage
        side.speedStage = p.speedStage
        if let m = move { side.moves[0] = m }
    }

    // MARK: End-of-turn

    private func endOfTurnEffects() {
        for s in 0..<2 {
            for slot in 0..<format.activeSlots {
                guard let p = side(at: s).active(at: slot), !p.fainted else { continue }

                if weather == .sand {
                    let immune: Set<String> = ["Rock", "Ground", "Steel"]
                    if !p.types.contains(where: { immune.contains($0) }) {
                        let dmg = max(1, p.maxHP / 16)
                        p.currentHP = max(0, p.currentHP - dmg)
                        log.append(BattleLogEntry(text: "\(p.displayName) is buffeted by the sandstorm! (-\(dmg) HP)"))
                    }
                }

                switch p.status {
                case .burn:
                    let dmg = max(1, p.maxHP / 16)
                    p.currentHP = max(0, p.currentHP - dmg)
                    log.append(BattleLogEntry(text: "\(p.displayName) is hurt by its burn. (-\(dmg) HP)"))
                case .poison:
                    let dmg = max(1, p.maxHP / 8)
                    p.currentHP = max(0, p.currentHP - dmg)
                    log.append(BattleLogEntry(text: "\(p.displayName) is hurt by poison. (-\(dmg) HP)"))
                case .toxic:
                    p.toxicCounter = min(15, p.toxicCounter + 1)
                    let dmg = max(1, p.maxHP * p.toxicCounter / 16)
                    p.currentHP = max(0, p.currentHP - dmg)
                    log.append(BattleLogEntry(text: "\(p.displayName) is hurt by toxic poison. (-\(dmg) HP)"))
                default:
                    break
                }

                // Leftovers — recover 1/16 max HP at end of turn if not full and alive.
                if !p.fainted,
                   p.effectiveHeldItem == .leftovers,
                   p.currentHP < p.maxHP {
                    let heal = max(1, p.maxHP / 16)
                    p.currentHP = min(p.maxHP, p.currentHP + heal)
                    log.append(BattleLogEntry(text: "\(p.displayName) restored HP with Leftovers."))
                }

                // Status DoT may have dropped HP enough to trigger a pinch berry.
                if !p.fainted { maybeTriggerHPBerry(for: p) }

                if p.fainted {
                    log.append(BattleLogEntry(text: "\(p.displayName) fainted!", emphasis: true))
                }
            }
        }

        if weatherTurns > 0 {
            weatherTurns -= 1
            if weatherTurns == 0 {
                log.append(BattleLogEntry(text: "The weather subsided."))
                weather = .none
            }
        }
        if terrainTurns > 0 {
            terrainTurns -= 1
            if terrainTurns == 0 {
                log.append(BattleLogEntry(text: "The terrain faded."))
                terrain = .none
            }
        }
    }

    // MARK: KO / Force Switches

    private func checkForKOsAndEnd() {
        if !side1.hasUnfainted {
            winner = 2
            log.append(BattleLogEntry(text: "\(side2.label) wins!", emphasis: true))
            return
        }
        if !side2.hasUnfainted {
            winner = 1
            log.append(BattleLogEntry(text: "\(side1.label) wins!", emphasis: true))
        }
    }

    private func updateForceSwitchQueue() {
        pendingForceSwitches.removeAll()
        for s in 0..<2 {
            for slot in 0..<format.activeSlots {
                if let p = side(at: s).active(at: slot), p.fainted,
                   !side(at: s).benchIndices().isEmpty {
                    pendingForceSwitches.append(ForceSwitch(side: s, slot: slot))
                }
            }
        }
    }
}

// MARK: - Main View

struct BattleSimulatorView: View {
    @Query(sort: \SavedTeam.createdAt, order: .reverse) private var teams: [SavedTeam]
    @Query(sort: \SavedSpread.createdAt, order: .reverse) private var savedSpreads: [SavedSpread]
    @Query(sort: \PKMNStats.name) private var allPokemon: [PKMNStats]
    @Query(sort: \MoveData.name) private var allMoves: [MoveData]

    @State private var format: BattleFormat = .singles
    @State private var team1ID: PersistentIdentifier?
    @State private var team2ID: PersistentIdentifier?
    @State private var engine: BattleEngine?

    var body: some View {
        NavigationStack {
            Group {
                if let engine {
                    BattleView(engine: engine) { self.engine = nil }
                        .navigationTitle("Turn \(engine.turn)")
                } else {
                    setupView
                        .navigationTitle("Battle Simulator")
                }
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    private var setupView: some View {
        ScrollView {
            VStack(spacing: 16) {
                if allPokemon.isEmpty || allMoves.isEmpty {
                    syncingCard
                } else if teams.isEmpty {
                    emptyTeamsCard
                } else {
                    formatCard
                    TeamPickerCard(label: "Side 1", selectedID: $team1ID,
                                   teams: teams, savedSpreads: savedSpreads,
                                   allPokemon: allPokemon, allMoves: allMoves,
                                   format: format)
                    TeamPickerCard(label: "Side 2", selectedID: $team2ID,
                                   teams: teams, savedSpreads: savedSpreads,
                                   allPokemon: allPokemon, allMoves: allMoves,
                                   format: format)

                    Button {
                        startBattle()
                    } label: {
                        Label("Start Battle", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canStart)
                }
            }
            .padding()
        }
    }

    private var formatCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Format", systemImage: "rectangle.split.2x1").font(.headline)
            Picker("Format", selection: $format) {
                ForEach(BattleFormat.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }

    private var syncingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Waiting for Pokemon & move data…")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }

    private var emptyTeamsCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.3.fill")
                .font(.title).foregroundStyle(.secondary)
            Text("No saved teams").font(.headline)
            Text("Create teams in the Teams tab before starting a battle.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }

    private var canStart: Bool {
        guard let t1 = team(for: team1ID), let t2 = team(for: team2ID) else { return false }
        let need = format.activeSlots
        return t1.slots.count >= need && t2.slots.count >= need
    }

    private func team(for id: PersistentIdentifier?) -> SavedTeam? {
        guard let id else { return nil }
        return teams.first(where: { $0.persistentModelID == id })
    }

    private func startBattle() {
        guard let t1 = team(for: team1ID), let t2 = team(for: team2ID) else { return }
        // Resolve through the live SavedSpread records so edits made in the Sets tab
        // (move swaps, EV tweaks, ability changes) propagate into the battle.
        let s1Slots = t1.resolvedSlots(allSpreads: savedSpreads, allPokemon: allPokemon, allMoves: allMoves)
        let s2Slots = t2.resolvedSlots(allSpreads: savedSpreads, allPokemon: allPokemon, allMoves: allMoves)
        let s1 = BattleSide(label: "Side 1", slots: s1Slots, format: format,
                            allPokemon: allPokemon, allMoves: allMoves)
        let s2 = BattleSide(label: "Side 2", slots: s2Slots, format: format,
                            allPokemon: allPokemon, allMoves: allMoves)
        engine = BattleEngine(format: format, side1: s1, side2: s2,
                              allPokemon: allPokemon, allMoves: allMoves)
    }
}

// MARK: - Team Picker

private struct TeamPickerCard: View {
    let label: String
    @Binding var selectedID: PersistentIdentifier?
    let teams: [SavedTeam]
    let savedSpreads: [SavedSpread]
    let allPokemon: [PKMNStats]
    let allMoves: [MoveData]
    let format: BattleFormat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.headline)
            Picker("Team", selection: $selectedID) {
                Text("Select a team…").tag(PersistentIdentifier?.none)
                ForEach(teams) { t in
                    Text("\(t.name) (\(t.slots.count))").tag(Optional(t.persistentModelID))
                }
            }
            .pickerStyle(.menu)

            if let t = teams.first(where: { $0.persistentModelID == selectedID }) {
                let liveSlots = t.resolvedSlots(allSpreads: savedSpreads,
                                                allPokemon: allPokemon,
                                                allMoves: allMoves)
                let names = liveSlots.prefix(6).map { $0.pokemonName }.joined(separator: ", ")
                if !names.isEmpty {
                    Text(names).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if t.slots.count < format.activeSlots {
                    Label("Need at least \(format.activeSlots) Pokemon for \(format.label).",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Battle Screen

private struct BattleView: View {
    @Bindable var engine: BattleEngine
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    globalsBar
                    SideFieldView(side: engine.side2, isOpponent: true)
                    SideFieldView(side: engine.side1, isOpponent: false)
                    Divider()
                    actionPanel
                }
                .padding()
            }
            Divider()
            BattleLogView(entries: engine.log).frame(maxHeight: 220)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Exit") { onExit() }
            }
        }
    }

    @ViewBuilder
    private var globalsBar: some View {
        if engine.weather != .none || engine.terrain != .none {
            HStack(spacing: 6) {
                if engine.weather != .none {
                    Label("\(engine.weather.rawValue) (\(engine.weatherTurns))", systemImage: "cloud.sun")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.cyan.opacity(0.15), in: Capsule())
                        .foregroundStyle(.cyan)
                }
                if engine.terrain != .none {
                    Label("\(engine.terrain.rawValue) Terrain (\(engine.terrainTurns))", systemImage: "leaf")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var actionPanel: some View {
        if let winner = engine.winner {
            VStack(spacing: 12) {
                Text(winner == 1 ? "Side 1 Wins!" : "Side 2 Wins!").font(.title2.bold())
                Button("New Battle", action: onExit).buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding()
        } else if !engine.pendingForceSwitches.isEmpty {
            ForceSwitchPanel(engine: engine)
        } else {
            ActionChooserPanel(engine: engine)
        }
    }
}

// MARK: - Field Views

private struct SideFieldView: View {
    var side: BattleSide
    let isOpponent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(side.label).font(.subheadline.bold())
                if !side.hazardSummary.isEmpty {
                    Text(side.hazardSummary)
                        .font(.caption2.bold())
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                }
                Spacer()
                HStack(spacing: 3) {
                    ForEach(side.participants.indices, id: \.self) { i in
                        Circle()
                            .fill(side.participants[i].fainted ? Color.gray.opacity(0.4) : Color.green)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(side.activeIndices.contains(i) ? Color.primary : Color.clear, lineWidth: 1.5))
                    }
                }
            }
            ForEach(Array(side.activeIndices.enumerated()), id: \.offset) { _, idx in
                if side.participants.indices.contains(idx) {
                    ParticipantField(p: side.participants[idx])
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isOpponent ? Color.red.opacity(0.06) : Color.blue.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ParticipantField: View {
    var p: BattleParticipant
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(p.displayName).font(.subheadline.bold())
                TypeBadge(type: p.activeType1)
                if let t2 = p.activeType2 { TypeBadge(type: t2) }
                if p.megaForm != nil {
                    Text("MEGA")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .foregroundStyle(.white)
                        .background(Color.pink, in: Capsule())
                }
                if p.status != .none {
                    Text(p.status.shortLabel)
                        .font(.caption2.bold())
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .foregroundStyle(.white)
                        .background(p.status.color, in: Capsule())
                }
                Spacer()
                Text("Lv\(p.slot.level)").font(.caption2).foregroundStyle(.secondary)
            }
            HPBar(current: p.currentHP, maxHP: p.maxHP)
            HStack {
                Text("\(p.currentHP) / \(p.maxHP) HP")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                if p.fainted {
                    Text("FAINTED").font(.caption2.bold()).foregroundStyle(.red)
                }
            }
        }
        .padding(8)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct HPBar: View {
    let current: Int
    let maxHP: Int
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.2)).frame(height: 8)
                let pct = maxHP > 0 ? Double(current) / Double(maxHP) : 0
                Capsule()
                    .fill(barColor(pct: pct))
                    .frame(width: geo.size.width * pct, height: 8)
            }
        }
        .frame(height: 8)
    }

    private func barColor(pct: Double) -> Color {
        if pct > 0.5 { return .green }
        if pct > 0.2 { return .yellow }
        return .red
    }
}

// MARK: - Action Chooser

private struct ActionChooserPanel: View {
    @Bindable var engine: BattleEngine

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<2, id: \.self) { sIdx in
                ForEach(0..<engine.format.activeSlots, id: \.self) { slotIdx in
                    if let actor = engine.side(at: sIdx).active(at: slotIdx), !actor.fainted {
                        ActorActionCard(engine: engine,
                                        sideIndex: sIdx, slotIndex: slotIdx,
                                        actor: actor)
                    }
                }
            }
            Button {
                engine.executeTurn()
            } label: {
                Label("Execute Turn", systemImage: "forward.end.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!engine.allActionsChosen)
        }
    }
}

private struct ActorActionCard: View {
    @Bindable var engine: BattleEngine
    let sideIndex: Int
    let slotIndex: Int
    var actor: BattleParticipant

    @State private var showSwitchSheet = false
    @State private var pendingChoice: PendingTargetChoice? = nil

    private enum PendingTargetChoice {
        case move(Int)
        case struggle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(engine.side(at: sideIndex).label): \(actor.displayName)")
                    .font(.subheadline.bold())
                if engine.pendingActions[sideIndex][slotIndex] != nil {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Spacer()
                Text("Spe \(actor.speed)")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }

            if engine.canMegaEvolve(side: sideIndex, slot: slotIndex) {
                Toggle(isOn: engine.megaBinding(side: sideIndex, slot: slotIndex)) {
                    Label("Mega Evolve", systemImage: "sparkles")
                        .font(.caption.bold())
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .tint(.pink)
                .controlSize(.small)
            }

            if let pending = engine.pendingActions[sideIndex][slotIndex] {
                HStack {
                    Text(pendingLabel(pending))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Change") {
                        engine.clearAction(side: sideIndex, slot: slotIndex)
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            } else {
                moveOrStruggleButtons
                Button {
                    showSwitchSheet = true
                } label: {
                    Label("Switch", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(engine.side(at: sideIndex).benchIndices().isEmpty)
            }
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .sheet(isPresented: $showSwitchSheet) {
            SwitchSheet(engine: engine, sideIndex: sideIndex,
                        slotIndex: slotIndex, isPresented: $showSwitchSheet)
        }
        .confirmationDialog(
            "Choose target",
            isPresented: Binding(
                get: { pendingChoice != nil },
                set: { if !$0 { pendingChoice = nil } }
            ),
            titleVisibility: .visible
        ) {
            ForEach(enemyTargets()) { t in
                Button(t.name) {
                    commit(choice: pendingChoice, target: t)
                    pendingChoice = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingChoice = nil }
        }
    }

    @ViewBuilder
    private var moveOrStruggleButtons: some View {
        if actor.moves.isEmpty || !actor.hasAnyPP {
            // No usable moves: Struggle path.
            Button { chooseStruggle() } label: {
                Label("Struggle", systemImage: "bolt.slash")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.gray)
        } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(0..<actor.moves.count, id: \.self) { mi in
                    let move = actor.moves[mi]
                    let curPP = actor.pp.indices.contains(mi) ? actor.pp[mi] : 0
                    let maxPP = move.pp
                    MoveButton(move: move, currentPP: curPP, maxPP: maxPP) {
                        chooseMove(mi)
                    }
                    .disabled(curPP <= 0)
                }
            }
        }
    }

    private func chooseMove(_ moveIndex: Int) {
        guard moveIndex < actor.moves.count else { return }
        let move = actor.moves[moveIndex]
        let normalized = BattleSimSeed.normalize(move.name)
        let isSpread = BattleMoveEffects.spreadMoves.contains(normalized)

        // Doubles + spread → auto-target both opponents, no picker.
        if engine.format == .doubles && isSpread && move.damageClass != "status" {
            engine.setAction(side: sideIndex, slot: slotIndex,
                             action: .spreadMove(moveIndex: moveIndex))
            return
        }

        let targets = enemyTargets()
        if targets.count <= 1 {
            if let t = targets.first {
                engine.setAction(side: sideIndex, slot: slotIndex,
                                 action: .move(moveIndex: moveIndex,
                                               targetSide: t.side, targetSlot: t.slot))
            } else {
                // No targets (status move targeting nothing): still record the move so the
                // turn can progress. Target side is the opposing side, slot 0.
                let opp = 1 - sideIndex
                engine.setAction(side: sideIndex, slot: slotIndex,
                                 action: .move(moveIndex: moveIndex,
                                               targetSide: opp, targetSlot: 0))
            }
        } else {
            pendingChoice = .move(moveIndex)
        }
    }

    private func chooseStruggle() {
        let targets = enemyTargets()
        if targets.count <= 1 {
            if let t = targets.first {
                engine.setAction(side: sideIndex, slot: slotIndex,
                                 action: .struggle(targetSide: t.side, targetSlot: t.slot))
            }
        } else {
            pendingChoice = .struggle
        }
    }

    private func commit(choice: PendingTargetChoice?, target: EnemyTarget) {
        switch choice {
        case .move(let mi):
            engine.setAction(side: sideIndex, slot: slotIndex,
                             action: .move(moveIndex: mi,
                                           targetSide: target.side, targetSlot: target.slot))
        case .struggle:
            engine.setAction(side: sideIndex, slot: slotIndex,
                             action: .struggle(targetSide: target.side, targetSlot: target.slot))
        case .none:
            break
        }
    }

    private struct EnemyTarget: Identifiable {
        let side: Int
        let slot: Int
        let name: String
        var id: String { "\(side)-\(slot)" }
    }

    private func enemyTargets() -> [EnemyTarget] {
        let enemy = 1 - sideIndex
        let enemySide = engine.side(at: enemy)
        var t: [EnemyTarget] = []
        for i in 0..<engine.format.activeSlots {
            if let p = enemySide.active(at: i), !p.fainted {
                t.append(EnemyTarget(side: enemy, slot: i, name: p.displayName))
            }
        }
        return t
    }

    private func pendingLabel(_ action: BattleAction) -> String {
        let megaPrefix = engine.pendingMega[sideIndex][slotIndex] ? "✦ Mega + " : ""
        switch action {
        case .move(let mi, let ts, let tslot):
            guard mi < actor.moves.count else { return megaPrefix + "Move" }
            let name = actor.moves[mi].name
            if engine.format == .doubles, let target = engine.side(at: ts).active(at: tslot) {
                return "\(megaPrefix)Use \(name) → \(target.displayName)"
            }
            return "\(megaPrefix)Use \(name)"
        case .spreadMove(let mi):
            guard mi < actor.moves.count else { return megaPrefix + "Spread move" }
            return "\(megaPrefix)Use \(actor.moves[mi].name) (spread)"
        case .switchTo(let bench):
            let s = engine.side(at: sideIndex)
            guard bench < s.participants.count else { return "Switch" }
            return "Switch to \(s.participants[bench].displayName)"
        case .struggle(let ts, let tslot):
            if engine.format == .doubles, let target = engine.side(at: ts).active(at: tslot) {
                return "\(megaPrefix)Struggle → \(target.displayName)"
            }
            return "\(megaPrefix)Struggle"
        }
    }
}

private struct MoveButton: View {
    let move: MoveData
    let currentPP: Int
    let maxPP: Int
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(move.name).font(.caption.bold()).lineLimit(1)
                    Spacer()
                    TypeBadge(type: move.type)
                }
                HStack(spacing: 6) {
                    Text("\(move.power ?? 0) BP")
                        .font(.caption2).foregroundStyle(.secondary)
                    if move.priority != 0 {
                        let sign = move.priority > 0 ? "+" : ""
                        Text("Prio \(sign)\(move.priority)")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                    Spacer()
                    DamageClassBadge(damageClass: move.damageClass)
                }
                HStack {
                    Text("PP \(currentPP)/\(maxPP)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(currentPP == 0 ? .red : .secondary)
                    Spacer()
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            .opacity(currentPP == 0 ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
    }
}

private struct SwitchSheet: View {
    @Bindable var engine: BattleEngine
    let sideIndex: Int
    let slotIndex: Int
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                let bench = engine.side(at: sideIndex).benchIndices()
                if bench.isEmpty {
                    Text("No available Pokemon to switch in.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(bench, id: \.self) { bi in
                        let p = engine.side(at: sideIndex).participants[bi]
                        Button {
                            engine.setAction(side: sideIndex, slot: slotIndex,
                                             action: .switchTo(benchIndex: bi))
                            isPresented = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.displayName).font(.subheadline.bold())
                                    HStack(spacing: 4) {
                                        TypeBadge(type: p.slot.type1)
                                        if let t2 = p.slot.type2 { TypeBadge(type: t2) }
                                        if p.status != .none {
                                            Text(p.status.shortLabel)
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 4).padding(.vertical, 1)
                                                .foregroundStyle(.white)
                                                .background(p.status.color, in: Capsule())
                                        }
                                    }
                                }
                                Spacer()
                                Text("\(p.currentHP)/\(p.maxHP)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Switch In")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Force Switch Panel

private struct ForceSwitchPanel: View {
    @Bindable var engine: BattleEngine

    var body: some View {
        VStack(spacing: 12) {
            ForEach(engine.pendingForceSwitches) { fs in
                let s = engine.side(at: fs.side)
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(s.label) must send out a replacement.")
                        .font(.subheadline.bold())
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(s.benchIndices(), id: \.self) { bi in
                            let p = s.participants[bi]
                            Button {
                                engine.forceSwitch(side: fs.side, slot: fs.slot, benchIndex: bi)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.displayName).font(.caption.bold())
                                    Text("\(p.currentHP)/\(p.maxHP) HP")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

// MARK: - Battle Log

private struct BattleLogView: View {
    let entries: [BattleLogEntry]
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(entries) { e in
                        Text(e.text)
                            .font(e.emphasis ? .footnote.bold() : .footnote)
                            .foregroundStyle(e.emphasis ? .primary : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(e.id)
                    }
                }
                .padding(10)
            }
            .background(Color(.secondarySystemBackground))
            .onChange(of: entries.count) { _, _ in
                if let last = entries.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }
}

#Preview {
    BattleSimulatorView()
        .modelContainer(for: [PKMNStats.self, MoveData.self, SavedTeam.self, SavedSpread.self])
}
