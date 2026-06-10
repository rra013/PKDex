//
//  DamageCalcMegaEvolutionTests.swift
//  PKDexTests
//
//  Covers the in-place Mega Evolution toggle on the damage calculator's
//  `CalcSide`. The contract:
//    - Toggling Mega never resets the user's set (EVs, IVs, moves, nature,
//      ability pick all survive).
//    - The toggle is only effective when prerequisites hold — correct stone
//      for the species, or Rayquaza holding Dragon Ascent.
//    - When active, `effective*` accessors swap to Mega values; the damage
//      calc routes through those, so a Mega Charizard Y attacks as a 159
//      base Sp.Atk Drought sweeper without the user changing anything else.
//

import Testing
import Foundation
@testable import PKDex

@MainActor
@Suite("Damage Calculator — Mega Evolution Toggle")
struct DamageCalcMegaEvolutionTests {

    // MARK: - Fixtures

    private func charizard() -> PKMNStats {
        PKMNStats(id: 6, speciesID: 6, name: "Charizard",
                  type1: "Fire", type2: "Flying",
                  baseHP: 78, baseAtk: 84, baseDef: 78,
                  baseSpAtk: 109, baseSpDef: 85, baseSpeed: 100,
                  ability1: "blaze",
                  ability2: nil,
                  hiddenAbility: "solar-power")
    }

    private func venusaur() -> PKMNStats {
        PKMNStats(id: 3, speciesID: 3, name: "Venusaur",
                  type1: "Grass", type2: "Poison",
                  baseHP: 80, baseAtk: 82, baseDef: 83,
                  baseSpAtk: 100, baseSpDef: 100, baseSpeed: 80,
                  ability1: "overgrow",
                  hiddenAbility: "chlorophyll")
    }

    private func rayquaza() -> PKMNStats {
        PKMNStats(id: 384, speciesID: 384, name: "Rayquaza",
                  type1: "Dragon", type2: "Flying",
                  baseHP: 105, baseAtk: 150, baseDef: 90,
                  baseSpAtk: 150, baseSpDef: 90, baseSpeed: 95,
                  ability1: "air-lock")
    }

    private func dragonAscent() -> MoveData {
        MoveData(id: 620, name: "Dragon Ascent", type: "Flying", damageClass: "physical",
                 power: 120, accuracy: 100, pp: 5, priority: 0,
                 minHits: nil, maxHits: nil, drain: 0, healing: 0,
                 critRate: 0, makesContact: true)
    }

    private func flamethrower() -> MoveData {
        MoveData(id: 53, name: "Flamethrower", type: "Fire", damageClass: "special",
                 power: 90, accuracy: 100, pp: 15, priority: 0,
                 minHits: nil, maxHits: nil, drain: 0, healing: 0,
                 critRate: 0, makesContact: false)
    }

    /// Apply a non-trivial set so we can confirm nothing resets on toggle.
    private func loadedCharizardSide() -> CalcSide {
        let s = CalcSide()
        s.pokemon = charizard()
        s.selectedAbility = "blaze"
        s.heldItem = .charizarditeY
        s.nature = allNatures.first(where: { $0.id == "timid" })!
        s.level = 50
        s.evHP = 4; s.evSpAtk = 252; s.evSpeed = 252
        s.ivHP = 31; s.ivAtk = 0; s.ivDef = 31
        s.ivSpAtk = 31; s.ivSpDef = 31; s.ivSpeed = 31
        s.moves = [flamethrower(), nil, nil, nil]
        return s
    }

    // MARK: - Eligibility Predicate

    @Test func cannotMegaEvolveWithoutPokemon() {
        let s = CalcSide()
        #expect(!s.canMegaEvolve)
        #expect(s.availableMegaForm == nil)
        #expect(s.activeMegaForm == nil)
    }

    @Test func cannotMegaEvolveWithoutStone() {
        let s = CalcSide()
        s.pokemon = charizard()
        s.heldItem = .none
        #expect(!s.canMegaEvolve)
        // Even if the user flipped the toggle on, no form is active.
        s.megaActive = true
        #expect(s.activeMegaForm == nil)
    }

    @Test func cannotMegaEvolveWithWrongStone() {
        // Charizardite Y belongs to Charizard. Venusaur with that stone
        // shouldn't get a Mega — the lookup is keyed off species AND stone.
        let s = CalcSide()
        s.pokemon = venusaur()
        s.heldItem = .charizarditeY
        #expect(!s.canMegaEvolve)
    }

    @Test func canMegaEvolveWithCorrectStoneY() {
        let s = CalcSide()
        s.pokemon = charizard()
        s.heldItem = .charizarditeY
        #expect(s.canMegaEvolve)
        #expect(s.availableMegaForm?.displayName == "Mega Charizard Y")
    }

    @Test func canMegaEvolveWithCorrectStoneX() {
        // Same species + a different stone surfaces the X form. Pinning both
        // X and Y guards the species-by-stone discrimination in MegaForms.
        let s = CalcSide()
        s.pokemon = charizard()
        s.heldItem = .charizarditeX
        #expect(s.canMegaEvolve)
        #expect(s.availableMegaForm?.displayName == "Mega Charizard X")
        #expect(s.availableMegaForm?.type1 == "Fire")
        #expect(s.availableMegaForm?.type2 == "Dragon")
    }

    @Test func canMegaEvolveRayquazaWithDragonAscent() {
        // Rayquaza needs no stone — Dragon Ascent in the moveset is the key.
        let s = CalcSide()
        s.pokemon = rayquaza()
        s.heldItem = .lifeOrb
        s.moves = [dragonAscent(), nil, nil, nil]
        #expect(s.canMegaEvolve)
        #expect(s.availableMegaForm?.displayName == "Mega Rayquaza")
        #expect(s.availableMegaForm?.stone == nil)
    }

    @Test func cannotMegaEvolveRayquazaWithoutDragonAscent() {
        let s = CalcSide()
        s.pokemon = rayquaza()
        s.heldItem = .lifeOrb
        s.moves = [flamethrower(), nil, nil, nil]
        #expect(!s.canMegaEvolve)
    }

    // MARK: - Set Preservation

    @Test func togglingMegaDoesNotResetTheSet() {
        // The whole point of the in-place toggle — flipping Mega on must
        // not touch the user's spread.
        let s = loadedCharizardSide()
        let beforeAbility = s.selectedAbility
        let beforeItem = s.heldItem
        let beforeNature = s.nature.id
        let beforeLevel = s.level
        let beforeEVHP = s.evHP
        let beforeEVSpA = s.evSpAtk
        let beforeEVSpe = s.evSpeed
        let beforeIVAtk = s.ivAtk
        let beforeMoves = s.moves.map { $0?.id }

        s.megaActive = true
        s.megaActive = false
        s.megaActive = true   // Several flips, just to be thorough.

        #expect(s.selectedAbility == beforeAbility)
        #expect(s.heldItem == beforeItem)
        #expect(s.nature.id == beforeNature)
        #expect(s.level == beforeLevel)
        #expect(s.evHP == beforeEVHP)
        #expect(s.evSpAtk == beforeEVSpA)
        #expect(s.evSpeed == beforeEVSpe)
        #expect(s.ivAtk == beforeIVAtk)
        #expect(s.moves.map { $0?.id } == beforeMoves)
    }

    // MARK: - Effective State

    @Test func effectiveBaseStatsReflectMegaWhenActive() {
        // Mega Charizard Y: 78 / 104 / 78 / 159 / 115 / 100 (HP carries from base).
        let s = loadedCharizardSide()
        s.megaActive = true
        #expect(s.effectiveBaseAtk == 104)
        #expect(s.effectiveBaseDef == 78)
        #expect(s.effectiveBaseSpAtk == 159)
        #expect(s.effectiveBaseSpDef == 115)
        #expect(s.effectiveBaseSpeed == 100)
    }

    @Test func effectiveBaseStatsRevertWhenMegaToggledOff() {
        let s = loadedCharizardSide()
        s.megaActive = true
        s.megaActive = false
        #expect(s.effectiveBaseAtk == 84)
        #expect(s.effectiveBaseSpAtk == 109)
        #expect(s.effectiveBaseSpDef == 85)
    }

    @Test func effectiveTypesReflectMegaWhenActive() {
        // Mega Charizard X is Fire/Dragon. Toggling on must surface that
        // typing for both the type chart UI and the damage calc's STAB calc.
        let s = loadedCharizardSide()
        s.heldItem = .charizarditeX
        s.megaActive = true
        #expect(s.effectiveTypes == ["Fire", "Dragon"])
        // `types` is the legacy accessor that should now also reflect Mega.
        #expect(s.types == ["Fire", "Dragon"])
    }

    @Test func baseTypesRetainedWhenMegaInactive() {
        let s = loadedCharizardSide()
        s.heldItem = .charizarditeX
        s.megaActive = false
        #expect(s.effectiveTypes == ["Fire", "Flying"])
    }

    @Test func effectiveAbilityReflectsMegaWhenActive() {
        // User picked Blaze. With Mega Charizard Y active the effective
        // ability is Drought — but `selectedAbility` (their pick) stays
        // intact for when they toggle Mega back off.
        let s = loadedCharizardSide()
        #expect(s.selectedAbility == "blaze")
        s.megaActive = true
        #expect(s.effectiveAbility == "drought")
        #expect(s.selectedAbility == "blaze",
                "Mega should not overwrite the user's ability selection.")
        s.megaActive = false
        #expect(s.effectiveAbility == "blaze")
    }

    @Test func effectiveAbilityChangesWhenSwappingMegaStones() {
        // Same Pokemon, two stones, two different Mega abilities.
        let s = loadedCharizardSide()
        s.heldItem = .charizarditeY
        s.megaActive = true
        #expect(s.effectiveAbility == "drought")
        s.heldItem = .charizarditeX
        #expect(s.effectiveAbility == "tough-claws")
    }

    // MARK: - Item Consumption

    @Test func effectiveHeldItemBecomesNoneOnStoneMega() {
        // Stone-based Megas consume the stone — the damage calc shouldn't
        // pretend the Mega is still holding the item.
        let s = loadedCharizardSide()
        #expect(s.effectiveHeldItem == .charizarditeY)
        s.megaActive = true
        #expect(s.effectiveHeldItem == .none)
    }

    @Test func effectiveHeldItemPreservedOnRayquazaMega() {
        // Rayquaza's MegaForm has no stone, so a held Life Orb on Mega
        // Rayquaza still applies during damage calc.
        let s = CalcSide()
        s.pokemon = rayquaza()
        s.heldItem = .lifeOrb
        s.moves = [dragonAscent(), nil, nil, nil]
        s.megaActive = true
        #expect(s.activeMegaForm?.displayName == "Mega Rayquaza")
        #expect(s.effectiveHeldItem == .lifeOrb)
    }

    // MARK: - Stale Toggle Gating

    @Test func toggleStaysSetButHasNoEffectIfStoneRemoved() {
        // If the user toggled Mega on, then swapped items away, the form is
        // no longer available — but `megaActive` stays true so that putting
        // the stone back instantly re-arms the Mega.
        let s = loadedCharizardSide()
        s.megaActive = true
        #expect(s.activeMegaForm?.displayName == "Mega Charizard Y")

        s.heldItem = .lifeOrb
        #expect(s.megaActive)
        #expect(s.activeMegaForm == nil)
        #expect(s.effectiveBaseSpAtk == 109,
                "Without an active Mega the stat block reverts to base.")
        #expect(s.effectiveAbility == "blaze",
                "Without an active Mega the user's ability pick is in effect.")

        // Restoring the stone re-arms without the user touching the toggle.
        s.heldItem = .charizarditeY
        #expect(s.activeMegaForm?.displayName == "Mega Charizard Y")
        #expect(s.effectiveAbility == "drought")
    }

    @Test func displayNameSwitchesToMegaForm() {
        let s = loadedCharizardSide()
        #expect(s.effectiveDisplayName == "Charizard")
        s.megaActive = true
        #expect(s.effectiveDisplayName == "Mega Charizard Y")
    }

    // MARK: - UI Surface (Toggle Visibility / Hint)

    @Test func hasAnyMegaFormFalseWithoutPokemon() {
        let s = CalcSide()
        #expect(!s.hasAnyMegaForm)
        #expect(s.megaDisabledReason == nil)
    }

    @Test func hasAnyMegaFormFalseForNonMegaSpecies() {
        // Chansey has no Mega — the toggle should not render at all.
        let chansey = PKMNStats(id: 113, speciesID: 113, name: "Chansey",
                                type1: "Normal",
                                baseHP: 250, baseAtk: 5, baseDef: 5,
                                baseSpAtk: 35, baseSpDef: 105, baseSpeed: 50,
                                ability1: "natural-cure")
        let s = CalcSide()
        s.pokemon = chansey
        #expect(!s.hasAnyMegaForm)
        #expect(s.megaDisabledReason == nil)
    }

    @Test func hasAnyMegaFormTrueForMegaSpeciesWithoutStone() {
        // Charizard has a Mega, even with no stone equipped. The toggle
        // should render (disabled) so the user can discover the feature.
        let s = CalcSide()
        s.pokemon = charizard()
        s.heldItem = .none
        #expect(s.hasAnyMegaForm)
        #expect(!s.canMegaEvolve)
    }

    @Test func megaDisabledReasonListsBothStonesForDualMegaSpecies() {
        // Charizard has two Mega stones — the hint should mention both so
        // the user knows there's a choice.
        let s = CalcSide()
        s.pokemon = charizard()
        s.heldItem = .none
        let hint = s.megaDisabledReason ?? ""
        #expect(hint.contains("Charizardite X"))
        #expect(hint.contains("Charizardite Y"))
    }

    @Test func megaDisabledReasonForRayquazaNamesDragonAscent() {
        let s = CalcSide()
        s.pokemon = rayquaza()
        s.heldItem = .lifeOrb
        s.moves = [flamethrower(), nil, nil, nil]
        #expect(s.hasAnyMegaForm)
        #expect(!s.canMegaEvolve)
        #expect(s.megaDisabledReason == "Must know Dragon Ascent")
    }

    @Test func megaDisabledReasonNilWhenToggleIsEnabled() {
        // No hint needed once the prerequisites are met.
        let s = loadedCharizardSide()
        #expect(s.canMegaEvolve)
        #expect(s.megaDisabledReason == nil)
    }

    // MARK: - Pokémon Legends Z-A Coverage

    /// The Z-A Megas live in the same `MegaForms.all` table as the originals.
    /// This pins Delphox specifically because that's the species the user
    /// reported the missing toggle on — the screenshot showed Delphox +
    /// Delphoxite with no Mega row visible.
    @Test func delphoxWithDelphoxiteCanMegaEvolve() {
        let delphox = PKMNStats(id: 655, speciesID: 655, name: "Delphox",
                                type1: "Fire", type2: "Psychic",
                                baseHP: 75, baseAtk: 69, baseDef: 72,
                                baseSpAtk: 114, baseSpDef: 100, baseSpeed: 104,
                                ability1: "blaze",
                                hiddenAbility: "magician")
        let s = CalcSide()
        s.pokemon = delphox
        s.heldItem = .delphoxite
        #expect(s.hasAnyMegaForm)
        #expect(s.canMegaEvolve)
        #expect(s.availableMegaForm?.displayName == "Mega Delphox")
        // Mega Sp.Atk should jump from 114 to 159 with Levitate.
        s.megaActive = true
        #expect(s.effectiveBaseSpAtk == 159)
        #expect(s.effectiveAbility == "levitate")
    }

    @Test func delphoxWithoutStoneShowsHint() {
        let delphox = PKMNStats(id: 655, speciesID: 655, name: "Delphox",
                                type1: "Fire", type2: "Psychic",
                                baseHP: 75, baseAtk: 69, baseDef: 72,
                                baseSpAtk: 114, baseSpDef: 100, baseSpeed: 104,
                                ability1: "blaze")
        let s = CalcSide()
        s.pokemon = delphox
        s.heldItem = .none
        #expect(s.hasAnyMegaForm)
        #expect(!s.canMegaEvolve)
        #expect(s.megaDisabledReason == "Hold Delphoxite")
    }

    /// Regression net: every Mega species advertised in
    /// `champions-m-a-learnsets.json` must be reachable from `MegaForms.all`
    /// via the held-item lookup. Catches the bug class where Z-A adds
    /// another wave of Megas and the table goes stale.
    @Test func everyChampionsMegaSpeciesHasATableEntry() {
        // Walk the JSON for any species that lists a `megas` array; for each
        // such species, confirm `MegaForms.all` contains at least one entry
        // keyed off the normalized species name. We don't pin the exact
        // form name (Mega Charizard X vs Y) since some species have multiple
        // — only that the species → form mapping exists at all.
        guard let url = Bundle.main.url(forResource: "champions-m-a-learnsets",
                                        withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let species = root["species"] as? [String: [String: Any]] else {
            print("[Mega] champions-m-a-learnsets.json not bundled — skipping coverage check.")
            return
        }

        var missing: [String] = []
        for (name, entry) in species {
            guard let megas = entry["megas"] as? [[String: Any]], !megas.isEmpty else { continue }
            let key = BattleSimSeed.normalize(name)
            // Rayquaza is handled by the special-case branch in
            // `MegaForms.form(forSpecies:...)`, not by an `all` entry.
            if key == "rayquaza" { continue }
            if !MegaForms.all.contains(where: { $0.speciesKey == key }) {
                missing.append(name)
            }
        }
        #expect(missing.isEmpty,
                "Champions JSON advertises Megas for species missing from MegaForms.all: \(missing.sorted())")
    }
}
