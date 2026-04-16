import Testing
@testable import PKDex

// MARK: - Attacker Abilities

@Suite("Attacker Abilities")
struct AttackerAbilityTests {

    private func atkMods(
        ability: String,
        moveType: String = "Normal", movePower: Int = 80,
        isPhysical: Bool = true, isContact: Bool = false,
        isSTAB: Bool = false, typeEff: Double = 1.0,
        weather: WeatherCondition = .none,
        atkFullHP: Bool = true, defFullHP: Bool = true,
        defenderTypes: [String] = [],
        terrain: TerrainCondition = .none
    ) -> AbilityModResult {
        computeAbilityModifiers(
            attackerAbility: ability, defenderAbility: nil,
            moveType: moveType, movePower: movePower,
            isPhysical: isPhysical, isContact: isContact,
            isSTAB: isSTAB, typeEffectiveness: typeEff,
            weather: weather,
            attackerAtFullHP: atkFullHP, defenderAtFullHP: defFullHP,
            defenderTypes: defenderTypes,
            terrain: terrain
        )
    }

    // MARK: STAB Modifiers

    @Test func adaptabilityBoostsSTAB() {
        let r = atkMods(ability: "adaptability", isSTAB: true)
        #expect(r.stabOverride == 2.0)
    }

    @Test func adaptabilityNoEffectWithoutSTAB() {
        let r = atkMods(ability: "adaptability", isSTAB: false)
        #expect(r.stabOverride == nil)
    }

    @Test func proteanGrantsSTABOnNonSTABMove() {
        let r = atkMods(ability: "protean", moveType: "Ice", isSTAB: false)
        #expect(r.stabOverride == 1.5)
    }

    @Test func proteanNoOverrideOnNaturalSTAB() {
        let r = atkMods(ability: "protean", moveType: "Water", isSTAB: true)
        #expect(r.stabOverride == nil)
    }

    @Test func liberoGrantsSTAB() {
        let r = atkMods(ability: "libero", isSTAB: false)
        #expect(r.stabOverride == 1.5)
    }

    // MARK: Stat Multipliers

    @Test func hugePowerDoublesPhysicalAtk() {
        let phys = atkMods(ability: "huge-power", isPhysical: true)
        #expect(phys.atkMultiplier == 2.0)
        let spec = atkMods(ability: "huge-power", isPhysical: false)
        #expect(spec.atkMultiplier == 1.0)
    }

    @Test func purePowerDoublesPhysicalAtk() {
        let r = atkMods(ability: "pure-power", isPhysical: true)
        #expect(r.atkMultiplier == 2.0)
    }

    @Test func hustleBoostsPhysicalAtk() {
        let phys = atkMods(ability: "hustle", isPhysical: true)
        #expect(phys.atkMultiplier == 1.5)
        let spec = atkMods(ability: "hustle", isPhysical: false)
        #expect(spec.atkMultiplier == 1.0)
    }

    @Test func gorillaTacticsBoostsPhysicalAtk() {
        let r = atkMods(ability: "gorilla-tactics", isPhysical: true)
        #expect(r.atkMultiplier == 1.5)
    }

    @Test func solarPowerBoostsSpAtkInSun() {
        let sunSpec = atkMods(ability: "solar-power", isPhysical: false, weather: .sun)
        #expect(sunSpec.atkMultiplier == 1.5)
        let noSun = atkMods(ability: "solar-power", isPhysical: false, weather: .none)
        #expect(noSun.atkMultiplier == 1.0)
        let sunPhys = atkMods(ability: "solar-power", isPhysical: true, weather: .sun)
        #expect(sunPhys.atkMultiplier == 1.0)
    }

    // MARK: Type-Boosting Power Multipliers

    @Test func waterBubbleBoostsWaterPower() {
        let water = atkMods(ability: "water-bubble", moveType: "Water")
        #expect(water.powerMultiplier == 2.0)
        let fire = atkMods(ability: "water-bubble", moveType: "Fire")
        #expect(fire.powerMultiplier == 1.0)
    }

    @Test func transistorBoostsElectric() {
        let elec = atkMods(ability: "transistor", moveType: "Electric")
        #expect(elec.powerMultiplier == 1.3)
        let fire = atkMods(ability: "transistor", moveType: "Fire")
        #expect(fire.powerMultiplier == 1.0)
    }

    @Test func dragonsMawBoostsDragon() {
        let r = atkMods(ability: "dragons-maw", moveType: "Dragon")
        #expect(r.powerMultiplier == 1.5)
    }

    @Test func steelworkerBoostsSteel() {
        let r = atkMods(ability: "steelworker", moveType: "Steel")
        #expect(r.powerMultiplier == 1.5)
    }

    @Test func darkAuraBoostsDark() {
        let r = atkMods(ability: "dark-aura", moveType: "Dark")
        #expect(r.powerMultiplier == 1.33)
    }

    @Test func fairyAuraBoostsFairy() {
        let r = atkMods(ability: "fairy-aura", moveType: "Fairy")
        #expect(r.powerMultiplier == 1.33)
    }

    // MARK: Pinch Abilities

    @Test func blazeBoostsFireAtLowHP() {
        let low = atkMods(ability: "blaze", moveType: "Fire", atkFullHP: false)
        #expect(low.powerMultiplier == 1.5)
        let full = atkMods(ability: "blaze", moveType: "Fire", atkFullHP: true)
        #expect(full.powerMultiplier == 1.0)
    }

    @Test func torrentBoostsWaterAtLowHP() {
        let r = atkMods(ability: "torrent", moveType: "Water", atkFullHP: false)
        #expect(r.powerMultiplier == 1.5)
    }

    @Test func overgrowBoostsGrassAtLowHP() {
        let r = atkMods(ability: "overgrow", moveType: "Grass", atkFullHP: false)
        #expect(r.powerMultiplier == 1.5)
    }

    @Test func swarmBoostsBugAtLowHP() {
        let r = atkMods(ability: "swarm", moveType: "Bug", atkFullHP: false)
        #expect(r.powerMultiplier == 1.5)
    }

    // MARK: Move-Category Boosters

    @Test func technicianBoostsLowBP() {
        let low = atkMods(ability: "technician", movePower: 60)
        #expect(low.powerMultiplier == 1.5)
        let high = atkMods(ability: "technician", movePower: 61)
        #expect(high.powerMultiplier == 1.0)
    }

    @Test func toughClawsBoostsContact() {
        let contact = atkMods(ability: "tough-claws", isContact: true)
        #expect(contact.powerMultiplier == 1.3)
        let noContact = atkMods(ability: "tough-claws", isContact: false)
        #expect(noContact.powerMultiplier == 1.0)
    }

    @Test func ironFistBoosts() {
        let r = atkMods(ability: "iron-fist")
        #expect(r.powerMultiplier == 1.2)
    }

    @Test func strongJawBoosts() {
        let r = atkMods(ability: "strong-jaw")
        #expect(r.powerMultiplier == 1.5)
    }

    @Test func megaLauncherBoosts() {
        let r = atkMods(ability: "mega-launcher")
        #expect(r.powerMultiplier == 1.5)
    }

    @Test func punkRockAttackBoosts() {
        let r = atkMods(ability: "punk-rock")
        #expect(r.powerMultiplier == 1.3)
    }

    @Test func recklessBoosts() {
        let r = atkMods(ability: "reckless")
        #expect(r.powerMultiplier == 1.2)
    }

    @Test func sheerForceBoosts() {
        let r = atkMods(ability: "sheer-force")
        #expect(r.powerMultiplier == 1.3)
    }

    // MARK: Conditional / Situational

    @Test func analyticBoosts() {
        let r = atkMods(ability: "analytic")
        #expect(r.powerMultiplier == 1.3)
    }

    @Test func stakeoutBoosts() {
        let r = atkMods(ability: "stakeout")
        #expect(r.powerMultiplier == 2.0)
    }

    @Test func supremeOverlordBoosts() {
        let r = atkMods(ability: "supreme-overlord")
        #expect(r.powerMultiplier == 1.1)
    }

    @Test func sandForceBoostsInSand() {
        let rock = atkMods(ability: "sand-force", moveType: "Rock", weather: .sand)
        #expect(rock.powerMultiplier == 1.3)
        let ground = atkMods(ability: "sand-force", moveType: "Ground", weather: .sand)
        #expect(ground.powerMultiplier == 1.3)
        let steel = atkMods(ability: "sand-force", moveType: "Steel", weather: .sand)
        #expect(steel.powerMultiplier == 1.3)
        let fire = atkMods(ability: "sand-force", moveType: "Fire", weather: .sand)
        #expect(fire.powerMultiplier == 1.0)
        let noSand = atkMods(ability: "sand-force", moveType: "Rock", weather: .none)
        #expect(noSand.powerMultiplier == 1.0)
    }

    @Test func tintedLensDoublesNVE() {
        let nve = atkMods(ability: "tinted-lens", typeEff: 0.5)
        #expect(nve.finalMultiplier == 2.0)
        let neutral = atkMods(ability: "tinted-lens", typeEff: 1.0)
        #expect(neutral.finalMultiplier == 1.0)
        let se = atkMods(ability: "tinted-lens", typeEff: 2.0)
        #expect(se.finalMultiplier == 1.0)
        let immune = atkMods(ability: "tinted-lens", typeEff: 0.0)
        #expect(immune.finalMultiplier == 1.0)
    }

    @Test func sniperBoostsCrit() {
        let r = atkMods(ability: "sniper")
        #expect(r.critMultiplierOverride == 2.25)
    }

    @Test func normalizeBoostsPower() {
        let r = atkMods(ability: "normalize")
        #expect(r.powerMultiplier == 1.2)
    }

    // MARK: -ate Abilities

    @Test func aerilateBoostsNormalMoves() {
        let normal = atkMods(ability: "aerilate", moveType: "Normal")
        #expect(normal.powerMultiplier == 1.2)
        let fire = atkMods(ability: "aerilate", moveType: "Fire")
        #expect(fire.powerMultiplier == 1.0)
    }

    @Test func pixilateBoostsNormalMoves() {
        let r = atkMods(ability: "pixilate", moveType: "Normal")
        #expect(r.powerMultiplier == 1.2)
    }

    @Test func refrigerateBoostsNormalMoves() {
        let r = atkMods(ability: "refrigerate", moveType: "Normal")
        #expect(r.powerMultiplier == 1.2)
    }

    @Test func galvanizeBoostsNormalMoves() {
        let r = atkMods(ability: "galvanize", moveType: "Normal")
        #expect(r.powerMultiplier == 1.2)
    }

    // MARK: Scrappy / Mind's Eye

    @Test func scrappyNormalHitsGhost() {
        let r = atkMods(ability: "scrappy", moveType: "Normal", typeEff: 0.0, defenderTypes: ["Ghost"])
        #expect(r.typeEffOverride == 1.0)
    }

    @Test func scrappyFightingHitsGhost() {
        let r = atkMods(ability: "scrappy", moveType: "Fighting", typeEff: 0.0, defenderTypes: ["Ghost"])
        #expect(r.typeEffOverride == 1.0)
    }

    @Test func scrappyNormalVsGhostDark() {
        // Normal vs Ghost/Dark: Ghost immunity removed, Dark is neutral to Normal = 1.0x
        let r = atkMods(ability: "scrappy", moveType: "Normal", typeEff: 0.0, defenderTypes: ["Ghost", "Dark"])
        #expect(r.typeEffOverride == 1.0)
    }

    @Test func scrappyFightingVsGhostDark() {
        // Fighting vs Ghost/Dark: Ghost immunity removed, Dark is 2x SE
        let r = atkMods(ability: "scrappy", moveType: "Fighting", typeEff: 0.0, defenderTypes: ["Ghost", "Dark"])
        #expect(r.typeEffOverride == 2.0)
    }

    @Test func scrappyNoEffectOnOtherTypes() {
        // Fire vs Ghost is NVE (0.5), not immune — Scrappy doesn't trigger
        let r = atkMods(ability: "scrappy", moveType: "Fire", typeEff: 0.5, defenderTypes: ["Ghost"])
        #expect(r.typeEffOverride == nil)
    }

    @Test func scrappyNoEffectWhenNotImmune() {
        // Normal vs Normal: 1.0x, Scrappy doesn't activate
        let r = atkMods(ability: "scrappy", moveType: "Normal", typeEff: 1.0, defenderTypes: ["Normal"])
        #expect(r.typeEffOverride == nil)
    }

    @Test func mindsEyeNormalHitsGhost() {
        let r = atkMods(ability: "minds-eye", moveType: "Normal", typeEff: 0.0, defenderTypes: ["Ghost"])
        #expect(r.typeEffOverride == 1.0)
    }

    @Test func mindsEyeFightingHitsGhost() {
        let r = atkMods(ability: "minds-eye", moveType: "Fighting", typeEff: 0.0, defenderTypes: ["Ghost"])
        #expect(r.typeEffOverride == 1.0)
    }

    // MARK: Guts / Toxic Boost / Flare Boost

    @Test func gutsBoostsPhysicalAtk() {
        let phys = atkMods(ability: "guts", isPhysical: true)
        #expect(phys.atkMultiplier == 1.5)
        let spec = atkMods(ability: "guts", isPhysical: false)
        #expect(spec.atkMultiplier == 1.0)
    }

    @Test func toxicBoostBoostsPhysicalAtk() {
        let phys = atkMods(ability: "toxic-boost", isPhysical: true)
        #expect(phys.atkMultiplier == 1.5)
        let spec = atkMods(ability: "toxic-boost", isPhysical: false)
        #expect(spec.atkMultiplier == 1.0)
    }

    @Test func flareBoostBoostsSpecialAtk() {
        let spec = atkMods(ability: "flare-boost", isPhysical: false)
        #expect(spec.atkMultiplier == 1.5)
        let phys = atkMods(ability: "flare-boost", isPhysical: true)
        #expect(phys.atkMultiplier == 1.0)
    }

    // MARK: Defeatist / Slow Start

    @Test func defeatistHalvesAtkAtLowHP() {
        let low = atkMods(ability: "defeatist", atkFullHP: false)
        #expect(low.atkMultiplier == 0.5)
        let full = atkMods(ability: "defeatist", atkFullHP: true)
        #expect(full.atkMultiplier == 1.0)
    }

    @Test func slowStartHalvesPhysicalAtk() {
        let phys = atkMods(ability: "slow-start", isPhysical: true)
        #expect(phys.atkMultiplier == 0.5)
        let spec = atkMods(ability: "slow-start", isPhysical: false)
        #expect(spec.atkMultiplier == 1.0)
    }

    // MARK: Type-Boosting (New)

    @Test func rockyPayloadBoostsRock() {
        let rock = atkMods(ability: "rocky-payload", moveType: "Rock")
        #expect(rock.powerMultiplier == 1.5)
        let fire = atkMods(ability: "rocky-payload", moveType: "Fire")
        #expect(fire.powerMultiplier == 1.0)
    }

    @Test func steelySpritBoostsSteel() {
        let steel = atkMods(ability: "steely-spirit", moveType: "Steel")
        #expect(steel.powerMultiplier == 1.5)
        let fire = atkMods(ability: "steely-spirit", moveType: "Fire")
        #expect(fire.powerMultiplier == 1.0)
    }

    @Test func sharpnessBoosts() {
        let r = atkMods(ability: "sharpness")
        #expect(r.powerMultiplier == 1.5)
    }

    // MARK: Neuroforce

    @Test func neuroforceBoostsSuperEffective() {
        let se = atkMods(ability: "neuroforce", typeEff: 2.0)
        #expect(se.finalMultiplier == 1.25)
        let neutral = atkMods(ability: "neuroforce", typeEff: 1.0)
        #expect(neutral.finalMultiplier == 1.0)
        let nve = atkMods(ability: "neuroforce", typeEff: 0.5)
        #expect(nve.finalMultiplier == 1.0)
    }

    // MARK: Orichalcum Pulse / Hadron Engine

    @Test func orichalcumPulseBoostsAtkInSun() {
        let sunPhys = atkMods(ability: "orichalcum-pulse", isPhysical: true, weather: .sun)
        #expect(sunPhys.atkMultiplier > 1.33 && sunPhys.atkMultiplier < 1.34)
        let noSun = atkMods(ability: "orichalcum-pulse", isPhysical: true, weather: .none)
        #expect(noSun.atkMultiplier == 1.0)
        let sunSpec = atkMods(ability: "orichalcum-pulse", isPhysical: false, weather: .sun)
        #expect(sunSpec.atkMultiplier == 1.0)
    }

    @Test func hadronEngineBoostsSpAtkInElectricTerrain() {
        let specTerrain = atkMods(ability: "hadron-engine", isPhysical: false, terrain: .electric)
        #expect(specTerrain.atkMultiplier > 1.33 && specTerrain.atkMultiplier < 1.34)
        let noTerrain = atkMods(ability: "hadron-engine", isPhysical: false, terrain: .none)
        #expect(noTerrain.atkMultiplier == 1.0)
        let physTerrain = atkMods(ability: "hadron-engine", isPhysical: true, terrain: .electric)
        #expect(physTerrain.atkMultiplier == 1.0)
    }

    // MARK: Battery / Power Spot

    @Test func batteryBoostsSpecialDamage() {
        let spec = atkMods(ability: "battery", isPhysical: false)
        #expect(spec.finalMultiplier == 1.3)
        let phys = atkMods(ability: "battery", isPhysical: true)
        #expect(phys.finalMultiplier == 1.0)
    }

    @Test func powerSpotBoostsDamage() {
        let r = atkMods(ability: "power-spot")
        #expect(r.finalMultiplier == 1.3)
    }

    // MARK: Parental Bond

    @Test func parentalBondBoostsPower() {
        let r = atkMods(ability: "parental-bond")
        #expect(r.powerMultiplier == 1.25)
    }

    // MARK: Ruin Abilities (Attacker Side)

    @Test func swordOfRuinReducesPhysicalDef() {
        let phys = atkMods(ability: "sword-of-ruin", isPhysical: true)
        #expect(phys.defMultiplier == 0.75)
        let spec = atkMods(ability: "sword-of-ruin", isPhysical: false)
        #expect(spec.defMultiplier == 1.0)
    }

    @Test func beadsOfRuinReducesSpecialDef() {
        let spec = atkMods(ability: "beads-of-ruin", isPhysical: false)
        #expect(spec.defMultiplier == 0.75)
        let phys = atkMods(ability: "beads-of-ruin", isPhysical: true)
        #expect(phys.defMultiplier == 1.0)
    }
}

// MARK: - Defender Abilities

@Suite("Defender Abilities")
struct DefenderAbilityTests {

    private func defMods(
        ability: String,
        moveType: String = "Normal", movePower: Int = 80,
        isPhysical: Bool = true, isContact: Bool = false,
        isSTAB: Bool = false, typeEff: Double = 1.0,
        weather: WeatherCondition = .none,
        atkFullHP: Bool = true, defFullHP: Bool = true,
        defenderTypes: [String] = []
    ) -> AbilityModResult {
        computeAbilityModifiers(
            attackerAbility: nil, defenderAbility: ability,
            moveType: moveType, movePower: movePower,
            isPhysical: isPhysical, isContact: isContact,
            isSTAB: isSTAB, typeEffectiveness: typeEff,
            weather: weather,
            attackerAtFullHP: atkFullHP, defenderAtFullHP: defFullHP,
            defenderTypes: defenderTypes
        )
    }

    // MARK: Damage Reduction

    @Test func multiscaleHalvesDamageAtFullHP() {
        let full = defMods(ability: "multiscale", defFullHP: true)
        #expect(full.finalMultiplier == 0.5)
        let notFull = defMods(ability: "multiscale", defFullHP: false)
        #expect(notFull.finalMultiplier == 1.0)
    }

    @Test func shadowShieldHalvesDamageAtFullHP() {
        let r = defMods(ability: "shadow-shield", defFullHP: true)
        #expect(r.finalMultiplier == 0.5)
    }

    @Test func filterReducesSuperEffective() {
        let se = defMods(ability: "filter", typeEff: 2.0)
        #expect(se.finalMultiplier == 0.75)
        let neutral = defMods(ability: "filter", typeEff: 1.0)
        #expect(neutral.finalMultiplier == 1.0)
    }

    @Test func solidRockReducesSuperEffective() {
        let r = defMods(ability: "solid-rock", typeEff: 2.0)
        #expect(r.finalMultiplier == 0.75)
    }

    @Test func prismArmorReducesSuperEffective() {
        let r = defMods(ability: "prism-armor", typeEff: 4.0)
        #expect(r.finalMultiplier == 0.75)
    }

    @Test func fluffyReducesContactBoostsFire() {
        let contact = defMods(ability: "fluffy", moveType: "Normal", isContact: true)
        #expect(contact.finalMultiplier == 0.5)
        let fire = defMods(ability: "fluffy", moveType: "Fire", isContact: false)
        #expect(fire.finalMultiplier == 2.0)
        let fireContact = defMods(ability: "fluffy", moveType: "Fire", isContact: true)
        #expect(fireContact.finalMultiplier == 1.0) // 0.5 * 2.0
    }

    @Test func heatproofHalvesFireDamage() {
        let fire = defMods(ability: "heatproof", moveType: "Fire")
        #expect(fire.finalMultiplier == 0.5)
        let water = defMods(ability: "heatproof", moveType: "Water")
        #expect(water.finalMultiplier == 1.0)
    }

    @Test func waterBubbleDefHalvesFireDamage() {
        let fire = defMods(ability: "water-bubble", moveType: "Fire")
        #expect(fire.finalMultiplier == 0.5)
        let water = defMods(ability: "water-bubble", moveType: "Water")
        #expect(water.finalMultiplier == 1.0)
    }

    @Test func punkRockDefHalvesDamage() {
        let r = defMods(ability: "punk-rock")
        #expect(r.finalMultiplier == 0.5)
    }

    // MARK: Stat Modifiers

    @Test func furCoatDoublesPhysicalDef() {
        let phys = defMods(ability: "fur-coat", isPhysical: true)
        #expect(phys.defMultiplier == 2.0)
        let spec = defMods(ability: "fur-coat", isPhysical: false)
        #expect(spec.defMultiplier == 1.0)
    }

    @Test func iceScalesDoublesSpecialDef() {
        let spec = defMods(ability: "ice-scales", isPhysical: false)
        #expect(spec.defMultiplier == 2.0)
        let phys = defMods(ability: "ice-scales", isPhysical: true)
        #expect(phys.defMultiplier == 1.0)
    }

    @Test func marvelScaleBoostsPhysicalDef() {
        let phys = defMods(ability: "marvel-scale", isPhysical: true)
        #expect(phys.defMultiplier == 1.5)
        let spec = defMods(ability: "marvel-scale", isPhysical: false)
        #expect(spec.defMultiplier == 1.0)
    }

    @Test func thickFatHalvesFireIceAtk() {
        let fire = defMods(ability: "thick-fat", moveType: "Fire")
        #expect(fire.atkMultiplier == 0.5)
        let ice = defMods(ability: "thick-fat", moveType: "Ice")
        #expect(ice.atkMultiplier == 0.5)
        let water = defMods(ability: "thick-fat", moveType: "Water")
        #expect(water.atkMultiplier == 1.0)
    }

    // MARK: Type Immunities

    @Test func levitateImmuneToGround() {
        let ground = defMods(ability: "levitate", moveType: "Ground")
        #expect(ground.typeEffOverride == 0.0)
        let fire = defMods(ability: "levitate", moveType: "Fire")
        #expect(fire.typeEffOverride == nil)
    }

    @Test func flashFireImmuneToFire() {
        let r = defMods(ability: "flash-fire", moveType: "Fire")
        #expect(r.typeEffOverride == 0.0)
    }

    @Test func waterAbsorbImmuneToWater() {
        let r = defMods(ability: "water-absorb", moveType: "Water")
        #expect(r.typeEffOverride == 0.0)
    }

    @Test func stormDrainImmuneToWater() {
        let r = defMods(ability: "storm-drain", moveType: "Water")
        #expect(r.typeEffOverride == 0.0)
    }

    @Test func voltAbsorbImmuneToElectric() {
        let r = defMods(ability: "volt-absorb", moveType: "Electric")
        #expect(r.typeEffOverride == 0.0)
    }

    @Test func lightningRodImmuneToElectric() {
        let r = defMods(ability: "lightning-rod", moveType: "Electric")
        #expect(r.typeEffOverride == 0.0)
    }

    @Test func motorDriveImmuneToElectric() {
        let r = defMods(ability: "motor-drive", moveType: "Electric")
        #expect(r.typeEffOverride == 0.0)
    }

    @Test func sapSipperImmuneToGrass() {
        let r = defMods(ability: "sap-sipper", moveType: "Grass")
        #expect(r.typeEffOverride == 0.0)
    }

    @Test func drySkinImmuneToWaterWeakToFire() {
        let water = defMods(ability: "dry-skin", moveType: "Water")
        #expect(water.typeEffOverride == 0.0)
        let fire = defMods(ability: "dry-skin", moveType: "Fire")
        #expect(fire.finalMultiplier == 1.25)
    }

    @Test func wonderGuardBlocksNonSuperEffective() {
        let neutral = defMods(ability: "wonder-guard", typeEff: 1.0)
        #expect(neutral.typeEffOverride == 0.0)
        let nve = defMods(ability: "wonder-guard", typeEff: 0.5)
        #expect(nve.typeEffOverride == 0.0)
        let se = defMods(ability: "wonder-guard", typeEff: 2.0)
        #expect(se.typeEffOverride == nil)
    }

    // MARK: Purifying Salt

    @Test func purifyingSaltHalvesGhostDamage() {
        let ghost = defMods(ability: "purifying-salt", moveType: "Ghost")
        #expect(ghost.finalMultiplier == 0.5)
        let normal = defMods(ability: "purifying-salt", moveType: "Normal")
        #expect(normal.finalMultiplier == 1.0)
    }

    // MARK: Well-Baked Body

    @Test func wellBakedBodyImmuneToFire() {
        let fire = defMods(ability: "well-baked-body", moveType: "Fire")
        #expect(fire.typeEffOverride == 0.0)
        let water = defMods(ability: "well-baked-body", moveType: "Water")
        #expect(water.typeEffOverride == nil)
    }

    // MARK: Earth Eater

    @Test func earthEaterImmuneToGround() {
        let ground = defMods(ability: "earth-eater", moveType: "Ground")
        #expect(ground.typeEffOverride == 0.0)
        let fire = defMods(ability: "earth-eater", moveType: "Fire")
        #expect(fire.typeEffOverride == nil)
    }

    // MARK: Tera Shell

    @Test func teraShellReducesSEAtFullHP() {
        let seFull = defMods(ability: "tera-shell", typeEff: 2.0, defFullHP: true)
        #expect(seFull.typeEffOverride == 0.5)
        let seNotFull = defMods(ability: "tera-shell", typeEff: 2.0, defFullHP: false)
        #expect(seNotFull.typeEffOverride == nil)
        let neutralFull = defMods(ability: "tera-shell", typeEff: 1.0, defFullHP: true)
        #expect(neutralFull.typeEffOverride == nil)
    }

    // MARK: Ruin Abilities (Defender Side)

    @Test func tabletsOfRuinReducesPhysicalAtk() {
        let phys = defMods(ability: "tablets-of-ruin", isPhysical: true)
        #expect(phys.atkMultiplier == 0.75)
        let spec = defMods(ability: "tablets-of-ruin", isPhysical: false)
        #expect(spec.atkMultiplier == 1.0)
    }

    @Test func vesselOfRuinReducesSpecialAtk() {
        let spec = defMods(ability: "vessel-of-ruin", isPhysical: false)
        #expect(spec.atkMultiplier == 0.75)
        let phys = defMods(ability: "vessel-of-ruin", isPhysical: true)
        #expect(phys.atkMultiplier == 1.0)
    }

    // MARK: Friend Guard

    @Test func friendGuardReducesDamage() {
        let r = defMods(ability: "friend-guard")
        #expect(r.finalMultiplier == 0.75)
    }
}

// MARK: - Damage Engine Integration

@Suite("Damage Engine")
struct DamageEngineTests {

    @Test func proteanActuallyChangesDamageNumbers() {
        let noAbility = AbilityModResult()
        let base = calcDamageRange(
            level: 50, movePower: 90, userAtk: 150, defenderDef: 100,
            multi: false,
            weatherMult: 1.0, glaiveRush: false,
            crit: false, critMultiplier: 1.5,
            stabBonus: 1.0, typeEffect: 1.0,
            burnReduction: 1.0, abilityMods: noAbility,
            zMoveBypass: false
        )

        var proteanMods = AbilityModResult()
        proteanMods.stabOverride = 1.5
        let boosted = calcDamageRange(
            level: 50, movePower: 90, userAtk: 150, defenderDef: 100,
            multi: false,
            weatherMult: 1.0, glaiveRush: false,
            crit: false, critMultiplier: 1.5,
            stabBonus: 1.0, typeEffect: 1.0,
            burnReduction: 1.0, abilityMods: proteanMods,
            zMoveBypass: false
        )

        #expect(boosted.max > base.max)
        // Floor rounding means exact 1.5x won't hold, but it should be close
        let ratio = boosted.max / base.max
        #expect(ratio > 1.45 && ratio < 1.55, "Protean should multiply damage by ~1.5x (ratio was \(ratio))")
    }

    @Test func zeroPowerReturnsZeroDamage() {
        let r = calcDamageRange(
            level: 50, movePower: 0, userAtk: 150, defenderDef: 100,
            multi: false,
            weatherMult: 1.0, glaiveRush: false,
            crit: false, critMultiplier: 1.5,
            stabBonus: 1.0, typeEffect: 1.0,
            burnReduction: 1.0, abilityMods: AbilityModResult(),
            zMoveBypass: false
        )
        #expect(r.min == 0)
        #expect(r.max == 0)
    }

    @Test func typeEffectivenessCalculation() {
        #expect(computeTypeEffectiveness(moveType: "Fire", defenderTypes: ["Grass"]) == 2.0)
        #expect(computeTypeEffectiveness(moveType: "Fire", defenderTypes: ["Water"]) == 0.5)
        #expect(computeTypeEffectiveness(moveType: "Fire", defenderTypes: ["Grass", "Steel"]) == 4.0)
        #expect(computeTypeEffectiveness(moveType: "Normal", defenderTypes: ["Ghost"]) == 0.0)
        #expect(computeTypeEffectiveness(moveType: "Fire", defenderTypes: ["Normal"]) == 1.0)
    }

    @Test func minDamageIsLessThanMax() {
        let r = calcDamageRange(
            level: 50, movePower: 100, userAtk: 200, defenderDef: 100,
            multi: false,
            weatherMult: 1.0, glaiveRush: false,
            crit: false, critMultiplier: 1.5,
            stabBonus: 1.5, typeEffect: 2.0,
            burnReduction: 1.0, abilityMods: AbilityModResult(),
            zMoveBypass: false
        )
        #expect(r.min > 0)
        #expect(r.min <= r.max)
    }
}
