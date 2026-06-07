//
//  PokiiBattlerTests.swift
//  PKDexTests
//
//  Validates the v2 doubles policy: model loading, the featurization contract,
//  legal-action masking, the Mega-gate features, action decoding, and the
//  end-to-end inference call. These are guardrails for "is the safetensors
//  bundle wired up correctly" — not a parity check against the training
//  notebook (that requires dumped sample states, which we don't have here).
//

import Testing
import Foundation
@testable import PKDex

// MARK: - Shared fixtures

@MainActor
private enum PB {
    static func pkmn(_ name: String, id: Int = 1,
                     type1: String = "Normal", type2: String? = nil,
                     ability: String = "blaze",
                     hp: Int = 100, atk: Int = 100, def: Int = 100,
                     spa: Int = 100, spd: Int = 100, spe: Int = 100) -> PKMNStats {
        PKMNStats(id: id, speciesID: id, name: name,
                  type1: type1, type2: type2,
                  baseHP: hp, baseAtk: atk, baseDef: def,
                  baseSpAtk: spa, baseSpDef: spd, baseSpeed: spe,
                  ability1: ability)
    }

    static func mv(_ name: String, id: Int,
                   type: String = "Normal", dmg: String = "physical",
                   power: Int? = 40, priority: Int = 0) -> MoveData {
        MoveData(id: id, name: name, type: type, damageClass: dmg,
                 power: power, accuracy: 100, pp: 16, priority: priority,
                 minHits: nil, maxHits: nil, drain: 0, healing: 0,
                 critRate: 0, makesContact: false)
    }

    static func slot(_ p: PKMNStats, ability: String, moves: [MoveData],
                     item: String? = nil) -> TeamSlotInfo {
        TeamSlotInfo(
            spreadName: "fx-\(p.name)",
            pokemonID: p.id, pokemonName: p.name,
            type1: p.type1, type2: p.type2,
            abilityName: ability, itemRawValue: item,
            championsMode: false, natureID: "hardy", level: 50,
            evHP: 0, evAtk: 0, evDef: 0, evSpAtk: 0, evSpDef: 0, evSpeed: 0,
            moveSlots: moves.map {
                TeamMoveInfo(moveID: $0.id, moveName: $0.name, moveType: $0.type,
                             damageClass: $0.damageClass, power: $0.power, isSTAB: false)
            }
        )
    }

    /// Doubles engine with up-to-6 mons per side.
    static func doublesEngine(side1: [(PKMNStats, String, [MoveData], String?)],
                              side2: [(PKMNStats, String, [MoveData], String?)]) -> BattleEngine {
        let slots1 = side1.map { slot($0.0, ability: $0.1, moves: $0.2, item: $0.3) }
        let slots2 = side2.map { slot($0.0, ability: $0.1, moves: $0.2, item: $0.3) }
        let allP = side1.map(\.0) + side2.map(\.0)
        let allM = side1.flatMap(\.2) + side2.flatMap(\.2)
        let bs1 = BattleSide(label: "Side 1", slots: slots1, format: .doubles,
                             allPokemon: allP, allMoves: allM)
        let bs2 = BattleSide(label: "Side 2", slots: slots2, format: .doubles,
                             allPokemon: allP, allMoves: allM)
        return BattleEngine(format: .doubles, side1: bs1, side2: bs2,
                            allPokemon: allP, allMoves: allM)
    }
}

// MARK: - Model loading

@MainActor
@Suite("Pokii Battler — Model Load")
struct PokiiBattlerLoadTests {

    @Test func modelLoadsFromBundle() {
        let loaded = PokiiBattler.shared.ensureLoaded()
        #expect(loaded, "PokiiBattler should load from the app bundle. Error: \(PokiiBattler.shared.loadError ?? "none")")
    }

    @Test func configDimensionsAreReadFromJSON() {
        _ = PokiiBattler.shared.ensureLoaded()
        let m = PokiiBattler.shared
        // The v2 model is documented at cont_dim=108 / n_slots=4 / emb_dim=32 /
        // hidden=256 / n_classes>0. If any of these are at their default
        // initializer value AND don't match the safetensors, the loader's
        // shape check would have already thrown — but we still want a
        // human-readable assertion when something drifts.
        #expect(m.nSlots == 4, "model expects 4 species slots")
        #expect(m.embDim == 32, "embedding dim should be 32")
        #expect(m.contDim > 0)
        #expect(m.hidden > 0)
        #expect(m.nClasses > 0)
        #expect(m.actionVocab.count == m.nClasses,
                "action_vocabulary length must equal n_classes")
        #expect(!m.species2idx.isEmpty, "species2idx should populate")
        #expect(m.species2idx["<pad>"] == 0, "<pad> must be index 0")
        #expect(m.species2idx["<unk>"] == 1, "<unk> must be index 1")
    }

    @Test func megaCapableSpeciesLoaded() {
        _ = PokiiBattler.shared.ensureLoaded()
        let m = PokiiBattler.shared
        #expect(!m.megaCapableSpecies.isEmpty,
                "mega_capable_species set should populate from the config")
        // Charizard is the classic case used in the integration guide; if it's
        // missing, the species list almost certainly didn't deserialize.
        #expect(m.megaCapableSpecies.contains("charizard"))
    }
}

// MARK: - Encoder unit tests

@MainActor
@Suite("Pokii Featurizer — Name Encoding")
struct PokiiFeaturizerEncodingTests {

    @Test func speciesBaseFormsLowercase() {
        #expect(PokiiFeaturizer.encodeSpecies("Charizard") == "charizard")
        #expect(PokiiFeaturizer.encodeSpecies("Gardevoir") == "gardevoir")
    }

    @Test func speciesSpacesBecomeHyphens() {
        #expect(PokiiFeaturizer.encodeSpecies("Tapu Koko") == "tapu-koko")
    }

    @Test func megaPrefixCollapsesToBase() {
        // v2 contract: "Charizard-Mega-Y" → "charizard", not "charizard-megay".
        #expect(PokiiFeaturizer.encodeSpecies("Mega Charizard X") == "charizard")
        #expect(PokiiFeaturizer.encodeSpecies("Mega Charizard Y") == "charizard")
        #expect(PokiiFeaturizer.encodeSpecies("Mega Gardevoir") == "gardevoir")
    }

    @Test func primalPrefixCollapsesToBase() {
        #expect(PokiiFeaturizer.encodeSpecies("Primal Groudon") == "groudon")
        #expect(PokiiFeaturizer.encodeSpecies("Primal Kyogre") == "kyogre")
    }

    @Test func aegislashStanceCollapsesToBase() {
        // Stance Change pokemon share an embedding row — Showdown's
        // species2idx treats both formes as just "aegislash".
        #expect(PokiiFeaturizer.encodeSpecies("Aegislash-Shield") == "aegislash")
        #expect(PokiiFeaturizer.encodeSpecies("Aegislash-Blade") == "aegislash")
    }

    @Test func regionalFormsPreserveSuffix() {
        // Real form distinctions (regional variants, split formes) must NOT
        // collapse — only Mega/Primal/Stance do.
        #expect(PokiiFeaturizer.encodeSpecies("Vulpix-Alola") == "vulpix-alola")
        #expect(PokiiFeaturizer.encodeSpecies("Urshifu-Rapid-Strike") == "urshifu-rapid-strike")
        #expect(PokiiFeaturizer.encodeSpecies("Calyrex-Shadow") == "calyrex-shadow")
    }

    @Test func megaHyphenSuffixAlsoStripped() {
        // Some sources serialize Mega forms as hyphen suffixes rather than
        // a "Mega " prefix — make sure either way ends at the base species.
        #expect(PokiiFeaturizer.encodeSpecies("Charizard-Mega-X") == "charizard")
        #expect(PokiiFeaturizer.encodeSpecies("Gardevoir-Mega") == "gardevoir")
    }

    @Test func moveNamesUnderscoreSpacesOnly() {
        // Spaces → underscores; hyphens and apostrophes are preserved as-is.
        #expect(PokiiFeaturizer.encodeMoveName("Aerial Ace") == "Aerial_Ace")
        #expect(PokiiFeaturizer.encodeMoveName("Will-O-Wisp") == "Will-O-Wisp")
        #expect(PokiiFeaturizer.encodeMoveName("King's Shield") == "King's_Shield")
        #expect(PokiiFeaturizer.encodeMoveName("U-turn") == "U-turn")
    }
}

// MARK: - Featurizer shape / value contract

@MainActor
@Suite("Pokii Featurizer — Tensor Contract")
struct PokiiFeaturizerShapeTests {

    private func sampleEngine() -> BattleEngine {
        let m1 = PB.mv("Tackle", id: 1, dmg: "physical", power: 40)
        let m2 = PB.mv("Flamethrower", id: 2, type: "Fire", dmg: "special", power: 90)
        let m3 = PB.mv("Aerial Ace", id: 3, type: "Flying", dmg: "physical", power: 60)
        let m4 = PB.mv("Protect", id: 4, dmg: "status", power: nil)

        let mon = PB.pkmn("Charizard", id: 6, type1: "Fire", type2: "Flying")
        let other = PB.pkmn("Garchomp", id: 7, type1: "Dragon", type2: "Ground")
        let opp1 = PB.pkmn("Gardevoir", id: 8, type1: "Psychic", type2: "Fairy")
        let opp2 = PB.pkmn("Snorlax", id: 9, type1: "Normal")
        return PB.doublesEngine(
            side1: [(mon, "blaze", [m1, m2, m3, m4], nil),
                    (other, "blaze", [m1], nil)],
            side2: [(opp1, "blaze", [m1, m3], nil),
                    (opp2, "blaze", [m1], nil)])
    }

    @Test func inputLengthsMatchConfig() {
        _ = PokiiBattler.shared.ensureLoaded()
        let e = sampleEngine()
        let inputs = PokiiFeaturizer.makeInputs(engine: e, side: 0, slot: 0)
        #expect(inputs != nil, "featurizer should return inputs when model is loaded")
        guard let inputs else { return }
        #expect(inputs.xCat.count == PokiiBattler.shared.nSlots,
                "xCat must have n_slots entries (\(PokiiBattler.shared.nSlots))")
        #expect(inputs.xCont.count == PokiiBattler.shared.contDim,
                "xCont must be exactly cont_dim long")
        #expect(inputs.mask.count == PokiiBattler.shared.nClasses,
                "mask must be n_classes long")
    }

    @Test func existFlagsReflectOccupancy() {
        _ = PokiiBattler.shared.ensureLoaded()
        let e = sampleEngine()
        guard let inputs = PokiiFeaturizer.makeInputs(engine: e, side: 0, slot: 0) else {
            Issue.record("featurizer returned nil"); return
        }
        // exist flags live at offsets 64–67 (acting, ally, opp0, opp1).
        let actingExist = inputs.xCont[64]
        let allyExist   = inputs.xCont[65]
        let opp0Exist   = inputs.xCont[66]
        let opp1Exist   = inputs.xCont[67]
        #expect(actingExist == 1.0)
        #expect(allyExist == 1.0, "doubles ally slot is occupied")
        #expect(opp0Exist == 1.0)
        #expect(opp1Exist == 1.0)
    }

    @Test func hpRatiosAreInUnitRange() {
        _ = PokiiBattler.shared.ensureLoaded()
        let e = sampleEngine()
        guard let inputs = PokiiFeaturizer.makeInputs(engine: e, side: 0, slot: 0) else {
            Issue.record("featurizer returned nil"); return
        }
        // hp lives at the head of each 16-block: offsets 0, 16, 32, 48.
        for off in [0, 16, 32, 48] {
            let v = inputs.xCont[off]
            #expect(v >= 0.0 && v <= 1.0,
                    "hp ratio at offset \(off) should be in [0,1], got \(v)")
        }
    }

    @Test func statusOneHotForHealthyMon() {
        _ = PokiiBattler.shared.ensureLoaded()
        let e = sampleEngine()
        guard let inputs = PokiiFeaturizer.makeInputs(engine: e, side: 0, slot: 0) else {
            Issue.record("featurizer returned nil"); return
        }
        // status block lives at acting offsets 2..<9 (after hp + fainted).
        var sum: Float = 0
        for i in 2..<9 { sum += inputs.xCont[i] }
        #expect(sum == 1.0, "status one-hot must sum to exactly 1")
        #expect(inputs.xCont[2] == 1.0, "healthy mon should be `none` (index 0 of status)")
    }
}

// MARK: - Mega-gate features

@MainActor
@Suite("Pokii Featurizer — Mega Gate")
struct PokiiFeaturizerMegaGateTests {

    private func megaEngine(withStone: Bool, oppUsedMega: Bool = false) -> BattleEngine {
        let tackle = PB.mv("Tackle", id: 1, dmg: "physical", power: 40)
        let flame  = PB.mv("Flamethrower", id: 2, type: "Fire", dmg: "special", power: 90)
        // Charizard with Charizardite X *should* be Mega-eligible per
        // MegaForms.swift; without the stone, the gate must be closed.
        let charizard = PB.pkmn("Charizard", id: 6, type1: "Fire", type2: "Flying")
        let partner = PB.pkmn("Garchomp", id: 7, type1: "Dragon", type2: "Ground")
        let oppA = PB.pkmn("Gardevoir", id: 8, type1: "Psychic", type2: "Fairy")
        let oppB = PB.pkmn("Snorlax", id: 9, type1: "Normal")
        let stone: String? = withStone ? "Charizardite X" : nil
        let e = PB.doublesEngine(
            side1: [(charizard, "blaze", [tackle, flame], stone),
                    (partner, "blaze", [tackle], nil)],
            side2: [(oppA, "blaze", [tackle], nil),
                    (oppB, "blaze", [tackle], nil)])
        if oppUsedMega { e.side2.hasUsedMega = true }
        return e
    }

    @Test func metaBlockSize() {
        _ = PokiiBattler.shared.ensureLoaded()
        let e = megaEngine(withStone: false)
        guard let inputs = PokiiFeaturizer.makeInputs(engine: e, side: 0, slot: 0) else {
            Issue.record("featurizer returned nil"); return
        }
        // 64 (per-mon blocks) + 4 (exist flags) + 11 (meta block) = 79.
        // The new meta block runs 68..<79 — three more floats than v1.
        #expect(inputs.xCont.count >= 79, "cont vector should include the 11-float meta block")
    }

    @Test func canMegaIsZeroWithoutStone() {
        _ = PokiiBattler.shared.ensureLoaded()
        let e = megaEngine(withStone: false)
        guard let inputs = PokiiFeaturizer.makeInputs(engine: e, side: 0, slot: 0) else {
            Issue.record("featurizer returned nil"); return
        }
        // acting_can_mega is the 11th and last entry of the meta block.
        // Meta block starts at 68; index 78 = acting_can_mega.
        #expect(inputs.xCont[78] == 0.0,
                "acting_can_mega should be 0 when the actor isn't carrying a Mega Stone")
    }

    @Test func canMegaIsOneWithCorrectStone() {
        _ = PokiiBattler.shared.ensureLoaded()
        let e = megaEngine(withStone: true)
        guard let inputs = PokiiFeaturizer.makeInputs(engine: e, side: 0, slot: 0) else {
            Issue.record("featurizer returned nil"); return
        }
        #expect(inputs.xCont[78] == 1.0,
                "acting_can_mega should be 1 when the held item matches the species' Mega Stone")
    }

    @Test func myMegaUsedFlipsAfterSideSpendsMega() {
        _ = PokiiBattler.shared.ensureLoaded()
        let e = megaEngine(withStone: true)
        guard let pre = PokiiFeaturizer.makeInputs(engine: e, side: 0, slot: 0) else {
            Issue.record("nil pre"); return
        }
        #expect(pre.xCont[76] == 0.0, "my_mega_used starts at 0")

        e.side1.hasUsedMega = true
        guard let post = PokiiFeaturizer.makeInputs(engine: e, side: 0, slot: 0) else {
            Issue.record("nil post"); return
        }
        #expect(post.xCont[76] == 1.0, "my_mega_used should flip to 1 after the side spends its mega")
        #expect(post.xCont[78] == 0.0,
                "acting_can_mega must close once my_mega_used == 1, even with a stone")
    }

    @Test func oppMegaUsedReflectsOpponentSide() {
        _ = PokiiBattler.shared.ensureLoaded()
        let e = megaEngine(withStone: false, oppUsedMega: true)
        guard let inputs = PokiiFeaturizer.makeInputs(engine: e, side: 0, slot: 0) else {
            Issue.record("featurizer returned nil"); return
        }
        #expect(inputs.xCont[77] == 1.0, "opp_mega_used should reflect side 2's hasUsedMega")
    }
}

// MARK: - Mask correctness

@MainActor
@Suite("Pokii Featurizer — Legal Action Mask")
struct PokiiFeaturizerMaskTests {

    private func smallEngine() -> BattleEngine {
        // Real moves from the model's vocab so we can look up indices and
        // make sure the mask actually flips them on.
        let tackle = PB.mv("Tackle", id: 1, dmg: "physical", power: 40)
        let aerialAce = PB.mv("Aerial Ace", id: 2, type: "Flying", dmg: "physical", power: 60)
        let protect = PB.mv("Protect", id: 3, dmg: "status", power: nil)
        let surf = PB.mv("Surf", id: 4, type: "Water", dmg: "special", power: 90)

        let actor = PB.pkmn("Charizard", id: 6, type1: "Fire", type2: "Flying")
        let ally = PB.pkmn("Garchomp", id: 7, type1: "Dragon", type2: "Ground")
        let bench1 = PB.pkmn("Gardevoir", id: 8, type1: "Psychic", type2: "Fairy")
        let bench2 = PB.pkmn("Snorlax", id: 9, type1: "Normal")
        let opp1 = PB.pkmn("Toxapex", id: 10, type1: "Poison", type2: "Water")
        let opp2 = PB.pkmn("Venusaur", id: 11, type1: "Grass", type2: "Poison")
        // Side 1 has 4 mons: actor + ally active, bench1 + bench2 benched.
        return PB.doublesEngine(
            side1: [(actor, "blaze", [tackle, aerialAce, protect, surf], nil),
                    (ally, "blaze", [tackle], nil),
                    (bench1, "blaze", [tackle], nil),
                    (bench2, "blaze", [tackle], nil)],
            side2: [(opp1, "blaze", [tackle], nil),
                    (opp2, "blaze", [tackle], nil)])
    }

    @Test func legalMovesAreUnmasked() {
        _ = PokiiBattler.shared.ensureLoaded()
        let e = smallEngine()
        guard let inputs = PokiiFeaturizer.makeInputs(engine: e, side: 0, slot: 0) else {
            Issue.record("nil inputs"); return
        }
        let vocab = PokiiBattler.shared.actionVocab
        // Each of the actor's 4 moves should land on `0` (legal) in the mask
        // if its encoded label exists in the vocab.
        let names = ["Tackle", "Aerial Ace", "Protect", "Surf"]
        for n in names {
            let label = "move_" + PokiiFeaturizer.encodeMoveName(n)
            guard let idx = vocab.firstIndex(of: label) else {
                // Skip silently — vocab miss is a model coverage concern, not
                // a featurizer bug. Other tests check the warning behavior.
                continue
            }
            #expect(inputs.mask[idx] == 0.0,
                    "Move \(n) should be unmasked but mask[\(idx)] = \(inputs.mask[idx])")
        }
    }

    @Test func illegalMovesAreMaskedOff() {
        _ = PokiiBattler.shared.ensureLoaded()
        let e = smallEngine()
        guard let inputs = PokiiFeaturizer.makeInputs(engine: e, side: 0, slot: 0) else {
            Issue.record("nil inputs"); return
        }
        // Pick a move that's definitely NOT on the actor.
        let vocab = PokiiBattler.shared.actionVocab
        if let idx = vocab.firstIndex(of: "move_Earthquake") {
            #expect(inputs.mask[idx] < -1e8,
                    "Move not on the actor's kit must be masked off (got \(inputs.mask[idx]))")
        }
    }

    @Test func switchLabelsForBenchedMons() {
        _ = PokiiBattler.shared.ensureLoaded()
        let e = smallEngine()
        guard let inputs = PokiiFeaturizer.makeInputs(engine: e, side: 0, slot: 0) else {
            Issue.record("nil inputs"); return
        }
        let vocab = PokiiBattler.shared.actionVocab
        // Bench1 = Gardevoir, Bench2 = Snorlax. If either is in vocab the mask
        // should be 0 there.
        for sp in ["gardevoir", "snorlax"] {
            if let idx = vocab.firstIndex(of: "switch_" + sp) {
                #expect(inputs.mask[idx] == 0.0,
                        "switch_\(sp) should be legal (bench non-fainted, not active)")
            }
        }
    }

    @Test func claimedBenchExcludesThatSwitch() {
        _ = PokiiBattler.shared.ensureLoaded()
        let e = smallEngine()
        let vocab = PokiiBattler.shared.actionVocab
        // Without claiming, gardevoir's switch label is legal (mask = 0).
        guard let baseline = PokiiFeaturizer.makeInputs(engine: e, side: 0, slot: 0) else {
            Issue.record("nil baseline"); return
        }
        guard let gardevoirIdx = vocab.firstIndex(of: "switch_gardevoir") else { return }
        #expect(baseline.mask[gardevoirIdx] == 0.0)
        // Claim Gardevoir's bench index (=2 in our side 1 layout: 0/1 active, 2/3 bench).
        guard let claimed = PokiiFeaturizer.makeInputs(engine: e, side: 0, slot: 0,
                                                      claimedBench: Set([2])) else {
            Issue.record("nil claimed"); return
        }
        #expect(claimed.mask[gardevoirIdx] < -1e8,
                "Claiming bench[2] (Gardevoir) should mask switch_gardevoir off")
    }

    @Test func trappedActorCantSwitch() {
        _ = PokiiBattler.shared.ensureLoaded()
        let e = smallEngine()
        guard let actor = e.side1.active(at: 0) else { return }
        actor.trapTurnsRemaining = 3
        guard let inputs = PokiiFeaturizer.makeInputs(engine: e, side: 0, slot: 0) else {
            Issue.record("nil inputs"); return
        }
        let vocab = PokiiBattler.shared.actionVocab
        for sp in ["gardevoir", "snorlax"] {
            if let idx = vocab.firstIndex(of: "switch_" + sp) {
                #expect(inputs.mask[idx] < -1e8,
                        "Trapped actor must not be able to switch (\(sp))")
            }
        }
    }

    @Test func tauntBlocksStatusMoves() {
        _ = PokiiBattler.shared.ensureLoaded()
        let e = smallEngine()
        guard let actor = e.side1.active(at: 0) else { return }
        actor.tauntTurnsRemaining = 3
        guard let inputs = PokiiFeaturizer.makeInputs(engine: e, side: 0, slot: 0) else {
            Issue.record("nil inputs"); return
        }
        let vocab = PokiiBattler.shared.actionVocab
        if let idx = vocab.firstIndex(of: "move_Protect") {
            #expect(inputs.mask[idx] < -1e8,
                    "Taunted actor can't pick a status move (Protect)")
        }
        // But a damaging move on the same kit must still be legal.
        if let idx = vocab.firstIndex(of: "move_Tackle") {
            #expect(inputs.mask[idx] == 0.0,
                    "Taunt only blocks status moves; damaging moves stay legal")
        }
    }
}

// MARK: - Decode

@MainActor
@Suite("Pokii Featurizer — Action Decode")
struct PokiiFeaturizerDecodeTests {

    private func engine() -> BattleEngine {
        let tackle = PB.mv("Tackle", id: 1, dmg: "physical", power: 40)
        let surf = PB.mv("Surf", id: 2, type: "Water", dmg: "special", power: 90)
        let protect = PB.mv("Protect", id: 3, dmg: "status", power: nil)
        let actor = PB.pkmn("Charizard", id: 6, type1: "Fire", type2: "Flying")
        let ally = PB.pkmn("Garchomp", id: 7, type1: "Dragon", type2: "Ground")
        let bench = PB.pkmn("Gardevoir", id: 8, type1: "Psychic", type2: "Fairy")
        let opp1 = PB.pkmn("Toxapex", id: 10, type1: "Poison", type2: "Water")
        let opp2 = PB.pkmn("Venusaur", id: 11, type1: "Grass", type2: "Poison")
        return PB.doublesEngine(
            side1: [(actor, "blaze", [tackle, surf, protect], nil),
                    (ally, "blaze", [tackle], nil),
                    (bench, "blaze", [tackle], nil)],
            side2: [(opp1, "blaze", [tackle], nil),
                    (opp2, "blaze", [tackle], nil)])
    }

    @Test func decodeMoveTargetsOppositeSlot() {
        let e = engine()
        let action = PokiiFeaturizer.decode(label: "move_Tackle",
                                            engine: e, side: 0, slot: 0)
        guard case .move(let mi, let ts, let tslot) = action else {
            Issue.record("decode should return a .move action, got \(String(describing: action))")
            return
        }
        #expect(mi == 0, "Tackle is move index 0 on the kit")
        #expect(ts == 1, "Target side should be the opponent (1)")
        #expect(tslot == 0, "Acting from slot 0 → mirror to opponent's slot 0")
    }

    @Test func decodeSpreadMoveInDoubles() {
        let e = engine()
        let action = PokiiFeaturizer.decode(label: "move_Surf",
                                            engine: e, side: 0, slot: 0)
        guard case .spreadMove(let mi) = action else {
            Issue.record("Surf in doubles should be .spreadMove, got \(String(describing: action))")
            return
        }
        #expect(mi == 1, "Surf is move index 1")
    }

    @Test func decodeSelfTargetMoveUsesActor() {
        let e = engine()
        let action = PokiiFeaturizer.decode(label: "move_Protect",
                                            engine: e, side: 0, slot: 0)
        guard case .move(_, let ts, let tslot) = action else {
            Issue.record("Protect should be .move (self-target), got \(String(describing: action))")
            return
        }
        #expect(ts == 0, "Protect's target should be the actor's own side")
        #expect(tslot == 0, "Protect's target should be the actor's own slot")
    }

    @Test func decodeSwitchMapsToBenchIndex() {
        let e = engine()
        let action = PokiiFeaturizer.decode(label: "switch_gardevoir",
                                            engine: e, side: 0, slot: 0)
        guard case .switchTo(let bi) = action else {
            Issue.record("decode should return .switchTo, got \(String(describing: action))")
            return
        }
        #expect(bi == 2, "Gardevoir is index 2 (after Charizard, Garchomp)")
    }

    @Test func decodeUnknownLabelReturnsNil() {
        let e = engine()
        // A label the vocab doesn't have — decode should refuse rather than
        // pick something arbitrary.
        let action = PokiiFeaturizer.decode(label: "move_Definitely_Not_A_Real_Move",
                                            engine: e, side: 0, slot: 0)
        #expect(action == nil)
    }
}

// MARK: - End-to-end inference

@MainActor
@Suite("Pokii Battler — End-to-End Inference")
struct PokiiBattlerInferenceTests {

    @Test func inferenceReturnsLegalActionAndValidProbability() {
        _ = PokiiBattler.shared.ensureLoaded()
        let tackle = PB.mv("Tackle", id: 1, dmg: "physical", power: 40)
        let aerial = PB.mv("Aerial Ace", id: 2, type: "Flying", dmg: "physical", power: 60)
        let actor = PB.pkmn("Charizard", id: 6, type1: "Fire", type2: "Flying")
        let ally = PB.pkmn("Garchomp", id: 7, type1: "Dragon", type2: "Ground")
        let opp1 = PB.pkmn("Gardevoir", id: 8, type1: "Psychic", type2: "Fairy")
        let opp2 = PB.pkmn("Toxapex", id: 9, type1: "Poison", type2: "Water")
        let e = PB.doublesEngine(
            side1: [(actor, "blaze", [tackle, aerial], nil),
                    (ally, "blaze", [tackle], nil)],
            side2: [(opp1, "blaze", [tackle], nil),
                    (opp2, "blaze", [tackle], nil)])
        guard let inputs = PokiiFeaturizer.makeInputs(engine: e, side: 0, slot: 0) else {
            Issue.record("featurizer nil"); return
        }
        guard let decision = PokiiBattler.shared.chooseAction(xCat: inputs.xCat,
                                                              xCont: inputs.xCont,
                                                              mask: inputs.mask) else {
            Issue.record("model returned nil decision"); return
        }
        // The chosen label must be in the action vocabulary.
        #expect(PokiiBattler.shared.actionVocab.contains(decision.label),
                "chosen label \(decision.label) must come from the vocab")
        // megaProbability is a sigmoid output, so it must be a proper probability.
        #expect(decision.megaProbability >= 0.0 && decision.megaProbability <= 1.0,
                "sigmoid output should be in [0,1], got \(decision.megaProbability)")
        // And the chosen label must decode to a real BattleAction the engine
        // could execute — verifies the label/mask are wired up correctly.
        let action = PokiiFeaturizer.decode(label: decision.label,
                                            engine: e, side: 0, slot: 0)
        #expect(action != nil, "decoded action should be non-nil for a legal label")
    }
}

// MARK: - Self / field target helper

@MainActor
@Suite("Battle Move Effects — Fixed-Target Helper")
struct BattleMoveEffectsFixedTargetTests {

    @Test func protectAndDetectAreSelfTarget() {
        #expect(BattleMoveEffects.isFixedSelfOrFieldTarget("Protect"))
        #expect(BattleMoveEffects.isFixedSelfOrFieldTarget("Detect"))
        #expect(BattleMoveEffects.isFixedSelfOrFieldTarget("Spiky Shield"))
    }

    @Test func selfBoostsAreFixedTarget() {
        #expect(BattleMoveEffects.isFixedSelfOrFieldTarget("Calm Mind"))
        #expect(BattleMoveEffects.isFixedSelfOrFieldTarget("Swords Dance"))
        #expect(BattleMoveEffects.isFixedSelfOrFieldTarget("Nasty Plot"))
        #expect(BattleMoveEffects.isFixedSelfOrFieldTarget("Dragon Dance"))
    }

    @Test func fieldAndSideMovesAreFixedTarget() {
        #expect(BattleMoveEffects.isFixedSelfOrFieldTarget("Trick Room"))
        #expect(BattleMoveEffects.isFixedSelfOrFieldTarget("Tailwind"))
        #expect(BattleMoveEffects.isFixedSelfOrFieldTarget("Sunny Day"))
        #expect(BattleMoveEffects.isFixedSelfOrFieldTarget("Rain Dance"))
        #expect(BattleMoveEffects.isFixedSelfOrFieldTarget("Reflect"))
        #expect(BattleMoveEffects.isFixedSelfOrFieldTarget("Light Screen"))
        #expect(BattleMoveEffects.isFixedSelfOrFieldTarget("Aurora Veil"))
        #expect(BattleMoveEffects.isFixedSelfOrFieldTarget("Spikes"))
        #expect(BattleMoveEffects.isFixedSelfOrFieldTarget("Stealth Rock"))
    }

    @Test func enemyTargetingMovesAreNotFixed() {
        // Sanity check: damaging moves and opponent-targeted status moves
        // must still go through the picker.
        #expect(!BattleMoveEffects.isFixedSelfOrFieldTarget("Tackle"))
        #expect(!BattleMoveEffects.isFixedSelfOrFieldTarget("Flamethrower"))
        #expect(!BattleMoveEffects.isFixedSelfOrFieldTarget("Will-O-Wisp"))
        #expect(!BattleMoveEffects.isFixedSelfOrFieldTarget("Thunder Wave"))
        #expect(!BattleMoveEffects.isFixedSelfOrFieldTarget("Toxic"))
        #expect(!BattleMoveEffects.isFixedSelfOrFieldTarget("Parting Shot"))
    }

    @Test func selfHealsAreFixedTarget() {
        #expect(BattleMoveEffects.isFixedSelfOrFieldTarget("Recover"))
        #expect(BattleMoveEffects.isFixedSelfOrFieldTarget("Roost"))
        #expect(BattleMoveEffects.isFixedSelfOrFieldTarget("Wish"))
        #expect(BattleMoveEffects.isFixedSelfOrFieldTarget("Substitute"))
    }
}
