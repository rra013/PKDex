//
//  PKDexTests.swift
//  PKDexTests
//
//  Created by Rishi Anand on 4/16/26.
//

import Testing
@testable import PKDex

// MARK: - Known Damage Range Tests

@Suite("Known Damage Ranges")
struct KnownDamageRangeTests {

    private let noAbilityMods = AbilityModResult()

    /// Helper to call calcDamageRange with sensible defaults.
    private func damage(
        level: Int = 50, power: Int = 80, atk: Int = 150, def: Int = 100,
        multi: Bool = false,
        weatherMult: Double = 1.0, glaiveRush: Bool = false,
        crit: Bool = false, critMultiplier: Double = 1.5,
        stab: Double = 1.0, typeEff: Double = 1.0,
        burn: Double = 1.0, abilityMods: AbilityModResult? = nil,
        zMoveBypass: Bool = false
    ) -> (min: Double, max: Double) {
        calcDamageRange(
            level: level, movePower: power, userAtk: atk, defenderDef: def,
            multi: multi,
            weatherMult: weatherMult, glaiveRush: glaiveRush,
            crit: crit, critMultiplier: critMultiplier,
            stabBonus: stab, typeEffect: typeEff,
            burnReduction: burn, abilityMods: abilityMods ?? noAbilityMods,
            zMoveBypass: zMoveBypass
        )
    }

    // MARK: - Vanilla (no modifiers)

    // Lv50, 80 BP, 150 Atk, 100 Def
    // scaledLevel = (2*50/5)+2 = 22
    // base = 22*80*150/100 = 2640; 2640/50+2 = 54
    // min = 54*85/100 = 45, max = 54
    @Test func vanillaLv50() {
        let r = damage()
        #expect(r.min == 45)
        #expect(r.max == 54)
    }

    // Lv100: scaledLevel = 42; base = 42*80*150/100 = 5040; 5040/50+2 = 102
    // min = 102*85/100 = 86, max = 102
    @Test func vanillaLv100() {
        let r = damage(level: 100)
        #expect(r.min == 86)
        #expect(r.max == 102)
    }

    // Lv1: scaledLevel = (2/5)+2 = 2; base = 2*80*150/100 = 240; 240/50+2 = 6
    // min = 6*85/100 = 5, max = 6
    @Test func vanillaLv1() {
        let r = damage(level: 1)
        #expect(r.min == 5)
        #expect(r.max == 6)
    }

    // MARK: - STAB

    // base min=45, max=54; floor(45*1.5)=67, floor(54*1.5)=81
    @Test func stabBoost() {
        let r = damage(stab: 1.5)
        #expect(r.min == 67)
        #expect(r.max == 81)
    }

    // MARK: - Type Effectiveness

    // 2x SE: floor(45*2.0)=90, floor(54*2.0)=108
    @Test func superEffective2x() {
        let r = damage(typeEff: 2.0)
        #expect(r.min == 90)
        #expect(r.max == 108)
    }

    // 4x SE: floor(45*4.0)=180, floor(54*4.0)=216
    @Test func superEffective4x() {
        let r = damage(typeEff: 4.0)
        #expect(r.min == 180)
        #expect(r.max == 216)
    }

    // 0.5x NVE: floor(45*0.5)=22, floor(54*0.5)=27
    @Test func notVeryEffective() {
        let r = damage(typeEff: 0.5)
        #expect(r.min == 22)
        #expect(r.max == 27)
    }

    // 0.25x NVE: floor(45*0.25)=11, floor(54*0.25)=13
    @Test func quarterEffective() {
        let r = damage(typeEff: 0.25)
        #expect(r.min == 11)
        #expect(r.max == 13)
    }

    // Immune: 0
    @Test func immune() {
        let r = damage(typeEff: 0.0)
        #expect(r.min == 0)
        #expect(r.max == 0)
    }

    // MARK: - STAB + Type Effectiveness Combined

    // STAB then 2x: floor(45*1.5)=67 -> floor(67*2.0)=134; floor(54*1.5)=81 -> floor(81*2.0)=162
    @Test func stabPlusSuperEffective() {
        let r = damage(stab: 1.5, typeEff: 2.0)
        #expect(r.min == 134)
        #expect(r.max == 162)
    }

    // STAB then 4x: 67 -> floor(67*4.0)=268; 81 -> floor(81*4.0)=324
    @Test func stabPlus4xSuperEffective() {
        let r = damage(stab: 1.5, typeEff: 4.0)
        #expect(r.min == 268)
        #expect(r.max == 324)
    }

    // MARK: - Critical Hit

    // Crit applied pre-random: floor(54*1.5)=81; min=81*85/100=68, max=81
    @Test func criticalHit() {
        let r = damage(crit: true)
        #expect(r.min == 68)
        #expect(r.max == 81)
    }

    // Crit + STAB: base after crit=81; min=68,max=81; STAB: floor(68*1.5)=102, floor(81*1.5)=121
    @Test func critPlusSTAB() {
        let r = damage(crit: true, stab: 1.5)
        #expect(r.min == 102)
        #expect(r.max == 121)
    }

    // MARK: - Burn

    // floor(45*0.5)=22, floor(54*0.5)=27
    @Test func burnReduction() {
        let r = damage(burn: 0.5)
        #expect(r.min == 22)
        #expect(r.max == 27)
    }

    // STAB + burn: floor(45*1.5)=67 -> floor(67*0.5)=33; floor(54*1.5)=81 -> floor(81*0.5)=40
    @Test func stabPlusBurn() {
        let r = damage(stab: 1.5, burn: 0.5)
        #expect(r.min == 33)
        #expect(r.max == 40)
    }

    // MARK: - Weather

    // Sun boosting Fire (1.5x): applied pre-random like crit
    // floor(54*1.5)=81; min=81*85/100=68, max=81
    @Test func weatherSunBoost() {
        let r = damage(weatherMult: 1.5)
        #expect(r.min == 68)
        #expect(r.max == 81)
    }

    // Rain weakening Fire (0.5x): floor(54*0.5)=27; min=27*85/100=22, max=27
    @Test func weatherRainWeaken() {
        let r = damage(weatherMult: 0.5)
        #expect(r.min == 22)
        #expect(r.max == 27)
    }

    // MARK: - Multi-Target

    // floor(54*0.75)=40; min=40*85/100=34, max=40
    @Test func multiTarget() {
        let r = damage(multi: true)
        #expect(r.min == 34)
        #expect(r.max == 40)
    }

    // MARK: - Parental Bond (via ability)

    // powerMultiplier=1.25: effectivePower=floor(80*1.25)=100
    // base = 22*100*150/100 = 3300; 3300/50+2 = 68
    // min = 68*85/100 = 57, max = 68
    @Test func parentalBondAbility() {
        var mods = AbilityModResult()
        mods.powerMultiplier = 1.25
        let r = damage(abilityMods: mods)
        #expect(r.min == 57)
        #expect(r.max == 68)
    }

    // MARK: - Glaive Rush

    // floor(54*2.0)=108; min=108*85/100=91, max=108
    @Test func glaiveRush() {
        let r = damage(glaiveRush: true)
        #expect(r.min == 91)
        #expect(r.max == 108)
    }

    // MARK: - Z-Move Bypass

    // min=45, max=54; floor(45*0.25)=11, floor(54*0.25)=13
    @Test func zMoveBypass() {
        let r = damage(zMoveBypass: true)
        #expect(r.min == 11)
        #expect(r.max == 13)
    }

    // MARK: - Ability Modifier Integration

    // Huge Power (2x Atk): effectiveAtk = floor(150*2.0) = 300
    // base = 22*80*300/100 = 5280; 5280/50+2 = 107 (5280/50=105 int div, +2=107)
    // min = 107*85/100 = 90, max = 107
    @Test func hugePowerAbility() {
        var mods = AbilityModResult()
        mods.atkMultiplier = 2.0
        let r = damage(abilityMods: mods)
        #expect(r.min == 90)
        #expect(r.max == 107)
    }

    // Adaptability (STAB override 2.0): min=floor(45*2.0)=90, max=floor(54*2.0)=108
    @Test func adaptabilitySTAB() {
        var mods = AbilityModResult()
        mods.stabOverride = 2.0
        let r = damage(abilityMods: mods)
        #expect(r.min == 90)
        #expect(r.max == 108)
    }

    // Sniper crit (2.25x): floor(54*2.25)=floor(121.5)=121; min=121*85/100=102, max=121
    @Test func sniperCrit() {
        var mods = AbilityModResult()
        mods.critMultiplierOverride = 2.25
        let r = damage(crit: true, abilityMods: mods)
        #expect(r.min == 102)
        #expect(r.max == 121)
    }

    // Filter/Solid Rock (0.75x final) with 2x SE:
    // min=floor(45*2.0)=90 -> floor(90*0.75)=67; max=floor(54*2.0)=108 -> floor(108*0.75)=81
    @Test func filterWithSuperEffective() {
        var mods = AbilityModResult()
        mods.finalMultiplier = 0.75
        let r = damage(typeEff: 2.0, abilityMods: mods)
        #expect(r.min == 67)
        #expect(r.max == 81)
    }

    // Multiscale (0.5x final): min=floor(45*0.5)=22, max=floor(54*0.5)=27
    @Test func multiscaleFinalMultiplier() {
        var mods = AbilityModResult()
        mods.finalMultiplier = 0.5
        let r = damage(abilityMods: mods)
        #expect(r.min == 22)
        #expect(r.max == 27)
    }

    // Type immunity override: typeEffOverride = 0.0
    @Test func abilityTypeImmunity() {
        var mods = AbilityModResult()
        mods.typeEffOverride = 0.0
        let r = damage(typeEff: 2.0, abilityMods: mods)
        #expect(r.min == 0)
        #expect(r.max == 0)
    }

    // Power multiplier (1.3x Technician): effectivePower = floor(80*1.3) = 104
    // base = 22*104*150/100 = 3432; 3432/50+2 = 70 (3432/50=68 int div, +2=70)
    // min = 70*85/100 = 59, max = 70
    @Test func powerMultiplier() {
        var mods = AbilityModResult()
        mods.powerMultiplier = 1.3
        let r = damage(abilityMods: mods)
        #expect(r.min == 59)
        #expect(r.max == 70)
    }

    // MARK: - Full Stack Combination

    // Lv100, crit, STAB, 2x SE, weather 1.5x
    // base = 42*80*150/100 = 5040; 5040/50+2 = 102
    // weather: floor(102*1.5) = 153
    // crit: floor(153*1.5) = 229 (floor(229.5))
    // min = 229*85/100 = 194 (19465/100=194), max = 229
    // STAB: floor(194*1.5)=291, floor(229*1.5)=floor(343.5)=343
    // 2x: floor(291*2.0)=582, floor(343*2.0)=686
    @Test func fullStackLv100() {
        let r = damage(level: 100, weatherMult: 1.5, crit: true, stab: 1.5, typeEff: 2.0)
        #expect(r.min == 582)
        #expect(r.max == 686)
    }

    // MARK: - Edge Cases

    @Test func zeroPowerReturnsZero() {
        let r = damage(power: 0)
        #expect(r.min == 0)
        #expect(r.max == 0)
    }

    @Test func zeroAtkReturnsZero() {
        let r = damage(atk: 0)
        #expect(r.min == 0)
        #expect(r.max == 0)
    }

    @Test func zeroDefReturnsZero() {
        let r = damage(def: 0)
        #expect(r.min == 0)
        #expect(r.max == 0)
    }

    // Very high stats: Lv100, 250 BP, 500 Atk, 50 Def
    // scaledLevel = 42; base = 42*250*500/50 = 105000; 105000/50+2 = 2102
    // min = 2102*85/100 = 1786 (178670/100=1786), max = 2102
    @Test func highStatScenario() {
        let r = damage(level: 100, power: 250, atk: 500, def: 50)
        #expect(r.min == 1786)
        #expect(r.max == 2102)
    }

    // Low power move: Lv50, 10 BP, 100 Atk, 200 Def
    // base = 22*10*100/200 = 110; 110/50+2 = 4
    // min = 4*85/100 = 3, max = 4
    @Test func lowPowerMove() {
        let r = damage(power: 10, atk: 100, def: 200)
        #expect(r.min == 3)
        #expect(r.max == 4)
    }
}

// MARK: - Stat Calculation Tests

@Suite("Stat Calculations")
struct StatCalculationTests {

    // HP formula: ((2*base + iv + ev/4) * level / 100) + level + 10
    // Shedinja: always 1
    @Test func shedinjaHP() {
        #expect(calcHP(base: 1, iv: 31, ev: 252, level: 50) == 1)
    }

    // 100 base, 31 IV, 252 EV, Lv50:
    // (2*100 + 31 + 63) * 50 / 100 + 50 + 10 = 294*50/100 + 60 = 147+60 = 207
    @Test func standardHP() {
        #expect(calcHP(base: 100, iv: 31, ev: 252, level: 50) == 207)
    }

    // 0 EV, 0 IV, Lv50: (200+0+0)*50/100 + 60 = 100+60 = 160
    @Test func zeroInvestmentHP() {
        #expect(calcHP(base: 100, iv: 0, ev: 0, level: 50) == 160)
    }

    // Stat formula: ((2*base + iv + ev/4) * level / 100 + 5) * natureMod
    // 100 base, 31 IV, 252 EV, Lv50, neutral: (294*50/100+5)*1.0 = 152
    @Test func standardStatNeutral() {
        #expect(calcStat(base: 100, iv: 31, ev: 252, level: 50, natureMod: 1.0) == 152)
    }

    // Boosting nature (+10%): floor(152*1.1) = 167
    @Test func standardStatBoosted() {
        #expect(calcStat(base: 100, iv: 31, ev: 252, level: 50, natureMod: 1.1) == 167)
    }

    // Hindering nature (-10%): floor(152*0.9) = 136
    @Test func standardStatHindered() {
        #expect(calcStat(base: 100, iv: 31, ev: 252, level: 50, natureMod: 0.9) == 136)
    }

    // Stage multipliers
    @Test func stageMultipliers() {
        #expect(statStageMultiplier(stage: 0) == 1.0)
        #expect(statStageMultiplier(stage: 1) == 1.5)
        #expect(statStageMultiplier(stage: 2) == 2.0)
        #expect(statStageMultiplier(stage: 6) == 4.0)
        #expect(statStageMultiplier(stage: -1) == 2.0 / 3.0)
        #expect(statStageMultiplier(stage: -6) == 0.25)
    }

    // Champions EV conversion: 32 -> 252, 0 -> 0, 16 -> 126
    @Test func championsEVConversion() {
        #expect(championsEVToMain(32) == 252)
        #expect(championsEVToMain(0) == 0)
        #expect(championsEVToMain(16) == 126)
    }
}

// MARK: - Type Effectiveness Tests

@Suite("Type Effectiveness")
struct TypeEffectivenessTests {

    @Test func singleTypeSuperEffective() {
        #expect(computeTypeEffectiveness(moveType: "Fire", defenderTypes: ["Grass"]) == 2.0)
        #expect(computeTypeEffectiveness(moveType: "Water", defenderTypes: ["Fire"]) == 2.0)
        #expect(computeTypeEffectiveness(moveType: "Electric", defenderTypes: ["Water"]) == 2.0)
    }

    @Test func singleTypeNotVeryEffective() {
        #expect(computeTypeEffectiveness(moveType: "Fire", defenderTypes: ["Water"]) == 0.5)
        #expect(computeTypeEffectiveness(moveType: "Grass", defenderTypes: ["Fire"]) == 0.5)
    }

    @Test func singleTypeImmune() {
        #expect(computeTypeEffectiveness(moveType: "Normal", defenderTypes: ["Ghost"]) == 0.0)
        #expect(computeTypeEffectiveness(moveType: "Ground", defenderTypes: ["Flying"]) == 0.0)
        #expect(computeTypeEffectiveness(moveType: "Electric", defenderTypes: ["Ground"]) == 0.0)
        #expect(computeTypeEffectiveness(moveType: "Ghost", defenderTypes: ["Normal"]) == 0.0)
        #expect(computeTypeEffectiveness(moveType: "Dragon", defenderTypes: ["Fairy"]) == 0.0)
    }

    @Test func dualType4xEffective() {
        // Fire vs Grass/Steel = 2 * 2 = 4
        #expect(computeTypeEffectiveness(moveType: "Fire", defenderTypes: ["Grass", "Steel"]) == 4.0)
        // Ground vs Fire/Electric = 2 * 2 = 4 (Lanturn without Water)
        #expect(computeTypeEffectiveness(moveType: "Ice", defenderTypes: ["Dragon", "Flying"]) == 4.0)
    }

    @Test func dualTypeQuarterEffective() {
        // Fire vs Water/Dragon = 0.5 * 0.5 = 0.25
        #expect(computeTypeEffectiveness(moveType: "Fire", defenderTypes: ["Water", "Dragon"]) == 0.25)
    }

    @Test func dualTypeImmunityOverrides() {
        // Normal vs Ghost/Dark: Ghost immunity makes it 0 regardless
        #expect(computeTypeEffectiveness(moveType: "Normal", defenderTypes: ["Ghost", "Dark"]) == 0.0)
        // Ground vs Flying/Water: Flying immunity makes it 0
        #expect(computeTypeEffectiveness(moveType: "Ground", defenderTypes: ["Flying", "Water"]) == 0.0)
    }

    @Test func dualTypeNeutral() {
        // Fire vs Water/Grass = 0.5 * 2.0 = 1.0
        #expect(computeTypeEffectiveness(moveType: "Fire", defenderTypes: ["Water", "Grass"]) == 1.0)
    }

    @Test func neutralMatchup() {
        #expect(computeTypeEffectiveness(moveType: "Fire", defenderTypes: ["Normal"]) == 1.0)
        #expect(computeTypeEffectiveness(moveType: "Water", defenderTypes: ["Psychic"]) == 1.0)
    }
}
