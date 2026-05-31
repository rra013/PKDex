# Battle Simulator — Champions Engine Alignment Plan

> **For: the Claude running inside Xcode (it can build + run tests; the planning
> environment could not).**
> **Branch:** `claude/battle-simulator-champions-alignment-dF3fB` (already
> fast-forwarded to include all `rng-development` battle-sim code).
> **Primary file:** `PKDex/BattleSimulator.swift` (~2,200 lines).
> Do not push to `rng-development` or `main`.

## Goal

Close the gaps between the existing turn-based battle engine and real battle
mechanics, and add an enforced **Champions battle format**. "Champions
mechanics" are treated as already-coded canon: **Lv 50, 66-total / 32-per-stat
stat points, IVs locked to 31** (`championsEVToMain`, `ChampionsValidator`). Do
**not** invent real-game rules beyond what these encode.

## Orientation (read first)

- `PKDex/BattleSimulator.swift`
  - `BattleParticipant` (class, ~line 156): live mon — `currentHP`, `pp`,
    `status`, stat stages, `effectiveHeldItem`, `activeAbility`, `resetVolatile()`.
  - `BattleMoveEffects` (enum, ~line 59): static lookup tables keyed by
    `BattleSimSeed.normalize(name)` (lowercased, alphanumerics only). **All new
    move tables go here** and follow this keying.
  - `applyDamageHit(attacker:defender:move:isSpread:)` (~line 851): the single
    choke point where one damaging hit lands. **Phases 1–3, 5 mostly live here.**
  - `computeDamage(...)` (~line 1262): bridges to `DamageCalcVM`. **Phase 4 here.**
  - `rollCrit(attacker:move:)` (~line 1279).
  - `performMove` (~707) / `performSpreadMove` (~756): PP, accuracy, dispatch.
  - `applyStatusMoveEffect(...)` (~971): status-move dispatch (add healing moves here).
  - `endOfTurnEffects()` (~1337): DoT, Leftovers, weather; add Speed Boost here.
  - `BattleSimulatorView` (~1447) / `TeamPickerCard` (~1573): setup UI (Phase 6).
- `PKDex/PokemonStatsModels.swift`: `MoveData` (has `power, accuracy, pp,
  priority, minHits, maxHits, drain, healing, critRate, makesContact`),
  `HeldItem` enum (`.lifeOrb`, `.rockyHelmet`? verify it exists; berries;
  `.choiceBand/.choiceSpecs/.choiceScarf`), `championsEVToMain`.
- `PKDex/damageCalculator.swift`: `formatAbilityName(_:)` (~line 1439) — converts
  ability id (`"rough-skin"`) → display (`"Rough Skin"`).
- `PKDex/03_ChampionsValidator.swift`: `ChampionsValidator` (`init?()` loads from
  bundle), `validate(team:) -> [Violation]`, `PokemonSet` + `PokemonSet.StatPoints`,
  `Violation.Category.isLegality`. Caps: `statPointTotalCap = 66`,
  `statPointPerStatCap = 32`, `requiredTeamSize = 6`, `requiredMoveCount = 4`.
- Champions JSON (`champions-m-a.json`, `champions-m-a-learnsets.json`) use
  **display names** for species/abilities/moves/items.

## Build / verify protocol (every phase)

1. Build the PKDex scheme in Xcode; fix all errors/warnings you introduce.
2. Run the existing Swift Testing suite — **must stay green**:
   `AbilityTests`, `BattleEngineAbilityTests`, `BattleItemsTests`,
   `TypeChartTests`, `PKDexTests`, `SpeedTierTests`, `TeamBuilderTests`.
3. Add the new tests listed per phase (Swift `Testing` framework, `@MainActor`,
   mirror `BattleEngineAbilityTests.swift` fixtures/`makeEngine` style).
4. Commit per phase with a descriptive message.

### Data caveat to resolve before Phases 3 & 5
`MoveData.makesContact` may be unreliable (older docs note it defaulting to
`false`). Before relying on it for contact-recoil (Phase 5), check whether the
GraphQL sync populates it (inspect a synced `Crunch`/`Close Combat` in the
running app, or `PokeAPIGraphQL.swift`). If it is not reliably populated, add a
fallback `BattleMoveEffects.contactMoves: Set<String>` (normalized) for the
common physical contact moves and use `move.makesContact || contactMoves.contains(key)`.

---

## Phase 1 — Multi-hit moves

**Where:** `applyDamageHit` + new helper + `BattleMoveEffects`.

Currently each damaging move lands exactly one hit. Use `move.minHits`/`maxHits`.

1. Add helper:
   ```swift
   /// Number of times a multi-hit move strikes this turn.
   private func hitCount(for move: MoveData, attacker: BattleParticipant) -> Int {
       guard let maxH = move.maxHits, maxH > 1 else { return 1 }
       let minH = move.minHits ?? maxH
       if minH == maxH { return maxH }                 // fixed (Double Kick = 2)
       if attacker.activeAbility == "skill-link" { return maxH }   // always max
       // Gen V+ 2–5 distribution: 35/35/15/15.
       let r = Double.random(in: 0..<1)
       switch r {
       case ..<0.35: return 2
       case ..<0.70: return 3
       case ..<0.85: return 4
       default:      return 5
       }
   }
   ```
   Optional fallback table in `BattleMoveEffects` for cases where sync didn't
   populate hit counts (`bulletseed, rockblast, iciclespear, pinmissile,
   tailslap, bonemerang(2), dualchop(2), doublekick(2), watershuriken`, etc.).
2. Refactor the body of `applyDamageHit` so the **per-hit** work (crit roll via
   `rollCrit`, `computeDamage`, apply HP loss, Focus Sash/Band at-1-HP save,
   type-resist berry mark, King's Rock flinch) runs inside a loop. Roll crit
   **independently per hit** (Gen VI+). Stop the loop early if the defender
   faints. Accumulate `totalDamage` and `hitsLanded`.
3. Log once after the loop: e.g. `"Hit 3 time(s)! (-N HP total)"` plus the
   existing effectiveness text. Keep a single `"A critical hit!"` line if any hit
   crit.
4. **Important ordering:** drain/recoil/Life Orb (Phase 2) and secondary effects
   (Phase 3) apply **after** the whole hit loop, using `totalDamage` /
   "did the move connect at all". HP-restore berry check and Shell Bell stay as
   they are but operate on totals.

**Tests (`BattleMultiHitTests.swift`):** fixed 2-hit deals ~2× a single hit;
Skill Link forces 5; loop stops when defender faints mid-sequence.

---

## Phase 2 — Drain, heal, and recoil

**Where:** end of `applyDamageHit` (drain/recoil/Life Orb) and
`applyStatusMoveEffect` (self-heal moves).

`MoveData.drain` is signed: **`> 0` = heal attacker by that % of damage dealt;
`< 0` = recoil to attacker = that % of damage dealt.** `MoveData.healing > 0` =
self-heal as % of max HP (status moves like Recover).

After the Phase-1 hit loop, with `totalDamage` and attacker alive:

1. **Drain** (`move.drain > 0`, `totalDamage > 0`, attacker not full HP):
   `heal = max(1, totalDamage * move.drain / 100)`, clamp to maxHP, log
   `"<name> drained HP!"`.
2. **Move recoil** (`move.drain < 0`, `totalDamage > 0`):
   `recoil = max(1, totalDamage * -move.drain / 100)`.
   **Skip if** `attacker.activeAbility == "rock-head"` or `"magic-guard"`.
   Apply, log `"<name> is hit with recoil! (-N HP)"`, then faint-check.
3. **Life Orb recoil** (`attacker.effectiveHeldItem == .lifeOrb`, `totalDamage > 0`):
   lose `max(1, maxHP / 10)`. **Skip if** ability is `"magic-guard"`. (Life Orb's
   damage boost already comes from `computeItemModifiers`; this only adds the
   recoil.) Apply once per move use (not per hit). Faint-check + log.

**Self-heal status moves** — in `applyStatusMoveEffect`, before the final
"no simulated effect" fallback, add a healing branch:
```swift
if move.damageClass == "status", move.healing > 0 {
    let heal = max(1, attacker.maxHP * move.healing / 100)
    attacker.currentHP = min(attacker.maxHP, attacker.currentHP + heal)
    log.append(BattleLogEntry(text: "\(attacker.displayName) restored HP!"))
    // Rest: full heal + sleep (2 turns) even at full HP intent.
    if BattleSimSeed.normalize(move.name) == "rest" {
        attacker.currentHP = attacker.maxHP
        attacker.status = .sleep
        attacker.sleepTurnsRemaining = 2
        log.append(BattleLogEntry(text: "\(attacker.displayName) fell asleep and became healthy!"))
    }
    return
}
```
(Covers Recover, Roost, Soft-Boiled, Synthesis, Morning Sun, Moonlight, Slack
Off, Milk Drink, Rest. Wish/delayed heal out of scope.)

**Tests (`BattleDrainRecoilTests.swift`):** Giga Drain heals ≈50% of damage;
Brave Bird/Double-Edge recoil ≈33%; Rock Head zeroes recoil; Life Orb chips
1/10 max HP; Recover restores ≈50% max HP.

---

## Phase 3 — Move secondary effects

**Where:** new tables in `BattleMoveEffects`; roller called after the Phase-1
hit loop (target must have survived for status/flinch). Reuse existing
`tryInflictStatus`, `applyOpposingStatDrop`, `changeStage`, `canApplyStatus`.

`MoveData` has no ailment/chance data, so encode it in static tables:

```swift
struct SecondaryEffect {
    var chance: Int                              // percent (printed)
    var status: BattleStatus? = nil              // inflicted on the TARGET
    var flinch: Bool = false
    var targetDrops: [(Nature.StatKey, Int)] = [] // negative deltas on TARGET
}

// Probabilistic on-hit effects (target must survive).
static let secondaryEffects: [String: SecondaryEffect] = [
    "flamethrower": .init(chance: 10, status: .burn),
    "fireblast":    .init(chance: 10, status: .burn),
    "scald":        .init(chance: 30, status: .burn),
    "lavaplume":    .init(chance: 30, status: .burn),
    "thunderbolt":  .init(chance: 10, status: .paralysis),
    "thunder":      .init(chance: 30, status: .paralysis),
    "discharge":    .init(chance: 30, status: .paralysis),
    "bodyslam":     .init(chance: 30, status: .paralysis),
    "sludgebomb":   .init(chance: 30, status: .poison),
    "poisonjab":    .init(chance: 30, status: .poison),
    "ironhead":     .init(chance: 30, flinch: true),
    "airslash":     .init(chance: 30, flinch: true),
    "rockslide":    .init(chance: 30, flinch: true),
    "zenheadbutt":  .init(chance: 20, flinch: true),
    "crunch":       .init(chance: 20, targetDrops: [(.def, -1)]),
    "shadowball":   .init(chance: 20, targetDrops: [(.spDef, -1)]),
    "psychic":      .init(chance: 10, targetDrops: [(.spDef, -1)]),
    "energyball":   .init(chance: 10, targetDrops: [(.spDef, -1)]),
    "flashcannon":  .init(chance: 10, targetDrops: [(.spDef, -1)]),
    "earthpower":   .init(chance: 10, targetDrops: [(.spDef, -1)]),
    "icebeam":      .init(chance: 10, status: .freeze),   // see freeze note
    "blizzard":     .init(chance: 10, status: .freeze),
    // extend as desired
]

// ALWAYS-on self stat changes after a damaging hit (not probabilistic).
static let selfStatChangesOnHit: [String: [(Nature.StatKey, Int)]] = [
    "closecombat": [(.def, -1), (.spDef, -1)],
    "superpower":  [(.atk, -1), (.def, -1)],
    "dracometeor": [(.spAtk, -2)],
    "overheat":    [(.spAtk, -2)],
    "leafstorm":   [(.spAtk, -2)],
    "fleurcannon": [(.spAtk, -2)],
    "makeitrain":  [(.spAtk, -1)],
]
```

Roller (after the hit loop, only if the move connected at least once):
```swift
let key = BattleSimSeed.normalize(move.name)
// Self drops always apply (attacker alive).
if !attacker.fainted, let drops = BattleMoveEffects.selfStatChangesOnHit[key] {
    for (stat, d) in drops { changeStage(attacker, stat: stat, by: d) }
    log.append(BattleLogEntry(text: "\(attacker.displayName)'s stats dropped!"))
}
// Probabilistic secondary on the target.
if !defender.fainted, let sec = BattleMoveEffects.secondaryEffects[key] {
    // Shield Dust blocks; Serene Grace doubles chance; Sheer Force removed it.
    let shielded = defender.activeAbility == "shield-dust"
    if !shielded && attacker.activeAbility != "sheer-force" {
        var chance = sec.chance
        if attacker.activeAbility == "serene-grace" { chance = min(100, chance * 2) }
        if Int.random(in: 1...100) <= chance {
            if let st = sec.status { tryInflictStatus(st, on: defender) }
            if sec.flinch { defender.flinched = true }
            for (stat, d) in sec.targetDrops {
                applyOpposingStatDrop(to: defender, stat: stat, delta: d)
            }
        }
    }
}
```

**Freeze note:** the engine has no `.freeze` case today. Either (a) add it in
Phase 5 (recommended, small) so Ice Beam/Blizzard work, or (b) drop the two ice
entries from `secondaryEffects` until then. Don't ship a `secondaryEffects`
entry whose `status` case doesn't exist.

**Tests (`BattleSecondaryEffectTests.swift`):** force RNG via repeated runs or
a seam — verify Scald can burn a non-Fire target; Shield Dust blocks it;
Sheer Force suppresses it; Close Combat always drops the user's Def/SpDef;
secondary can't fire when the hit KOs the target.

---

## Phase 4 — Critical hits ignore stat stages

**Where:** `computeDamage(...)`.

A crit ignores the **attacker's negative** offensive stages and the
**defender's positive** defensive stages. `configure(...)` copies all stages
into the `CalcSide` proxies; after configuring, when `crit == true`, clamp:

```swift
if crit {
    vm.side1.atkStage   = max(0, vm.side1.atkStage)
    vm.side1.spAtkStage = max(0, vm.side1.spAtkStage)
    vm.side2.defStage   = min(0, vm.side2.defStage)
    vm.side2.spDefStage = min(0, vm.side2.spDefStage)
}
```
This is purely local to the damage computation (the proxies are throwaway), so
the participants' real stages are untouched.

**Tests (`BattleCritTests.swift`):** with defender at +2 Def, a crit deals the
same damage as a crit at +0 Def; with attacker at −2 Atk, a crit matches a crit
at +0 Atk; non-crit still respects the stages.

---

## Phase 5 — Additional missing mechanics

Implement **Tier A** (required). **Tier B** is stretch — do it if Tier A + all
other phases are green and time allows; otherwise leave a `// TODO` and note it
in the final summary.

### Tier A

**A1. Choice item lock.** Choice Band/Specs/Scarf lock the holder into the first
move used until it switches out.
- Add to `BattleParticipant`: `var choiceLockedMoveIndex: Int? = nil`.
- Clear it in `resetVolatile()` (switching frees the lock).
- In `performMove`/`performSpreadMove`, after the move is confirmed to execute
  (PP ok, not asleep/flinched), if `effectiveHeldItem` is `.choiceBand`,
  `.choiceSpecs`, or `.choiceScarf` and `choiceLockedMoveIndex == nil`, set it to
  the chosen `moveIndex`.
- Enforce in the UI: in `ActorActionCard.moveOrStruggleButtons`, disable every
  move button whose index ≠ `actor.choiceLockedMoveIndex` when that is non-nil
  (and the item is still effective). Also short-circuit in the engine: if a
  locked actor's action targets a different move index, ignore/replace with the
  locked move (defensive).

**A2. Contact recoil from defender (resolve the makesContact caveat first).**
After a contact damaging move connects (use the `makesContact || contactMoves`
fallback), with the attacker still alive:
- Defender holds **Rocky Helmet** → attacker loses `max(1, maxHP/6)`.
- Defender ability **Rough Skin / Iron Barbs** → attacker loses `max(1, maxHP/8)`.
- Skip entirely if attacker ability is `"magic-guard"`. Apply once per move use
  (after the hit loop). Faint-check + log. (Confirm `HeldItem.rockyHelmet`
  exists; if not, add the case + give it no offensive modifier in
  `computeItemModifiers`.)

### Tier B (stretch)

**B1. Freeze status.** Add `.freeze` to `BattleStatus` (label "FRZ", color
`.cyan`). In `preMoveStatusCheck`, a frozen mon has a 20% thaw-and-act chance
each turn, otherwise can't move; Fire-type moves it uses thaw it; types immune =
Ice (handle in `canApplyStatus`). Enables the Ice Beam/Blizzard entries in
Phase 3. Aspear Berry already references freeze in `maybeTriggerStatusBerry`.

**B2. Speed Boost.** In `endOfTurnEffects`, for an alive mon whose
`activeAbility == "speed-boost"`, `changeStage(p, stat: .speed, by: 1)` (it's
already clamped to +6). Log it.

**B3. Protect / Detect.** New volatile `protectedThisTurn` set when the move is
used (priority already high in real games; in this engine it resolves by speed —
acceptable). Track consecutive-use success probability (1, 1/3, 1/9…). Damaging
and most status moves targeting a protected mon fail. This is the largest item;
only attempt if everything else is solid.

**Tests:** `BattleChoiceLockTests` (lock set on first use, freed on switch);
contact-recoil test (Rocky Helmet/Rough Skin chip the attacker, Magic Guard
exempt); plus tests for any Tier B item you implement.

---

## Phase 6 — Champions battle format (enforced)

**Where:** `BattleSimulatorView` + `TeamPickerCard` (+ a small mapping helper).

Add a Champions format that (a) forces Lv 50 + Champions stat scaling and
(b) blocks battles with teams that fail `ChampionsValidator` hard-legality.

1. **Setup state.** In `BattleSimulatorView` add
   `@State private var championsFormat = false` and a toggle in `formatCard`
   ("Champions Regulation"). Default it on when
   `@AppStorage("defaultGeneration")` equals `PokedexFilter.champions.rawValue`
   (matches how the damage calc defaults Champions Mode).
2. **Validator.** Lazily build `ChampionsValidator()` once (it parses ~600 KB).
   If `init?()` returns nil (JSON not bundled), disable the Champions toggle and
   surface a small "Champions data unavailable" note instead of crashing.
3. **Set mapping helper** (display-name aware — abilities need conversion):
   ```swift
   private func championsSet(from slot: TeamSlotInfo) -> PokemonSet {
       let sp: PokemonSet.StatPoints = slot.championsMode
           ? .init(hp: slot.evHP, atk: slot.evAtk, def: slot.evDef,
                   spa: slot.evSpAtk, spd: slot.evSpDef, spe: slot.evSpeed)
           : .init(hp: slot.evHP*32/252, atk: slot.evAtk*32/252, def: slot.evDef*32/252,
                   spa: slot.evSpAtk*32/252, spd: slot.evSpDef*32/252, spe: slot.evSpeed*32/252)
       return PokemonSet(
           species: slot.pokemonName,                          // display name ✓
           ability: slot.abilityName.map(formatAbilityName) ?? "", // id → display ✓
           item: slot.itemRawValue,                            // display name ✓
           nature: slot.natureID,
           teraType: nil,
           moves: slot.moveSlots.map { $0.moveName },          // display names ✓
           statPoints: sp, role: nil)
   }
   ```
   - **Verify** `formatAbilityName` output matches the JSON exactly for a few
     abilities (`"snow-warning"` → `"Snow Warning"`, `"rough-skin"` →
     `"Rough Skin"`). Patch any irregular cases (e.g. hyphenated species
     abilities) with a small override map if needed.
   - **Regional forms:** species names like `"Alolan Ninetales"` may not match
     the whitelist's naming. Check `champions-m-a.json`'s `species_whitelist` /
     `regional_forms_allowed` and add a name-normalization step if the formats
     differ. Note any unresolved mismatch in the final summary.
4. **Validate full team (all 6), not just active slots.** Resolve a team's slots
   (`SavedTeam.resolvedSlots(...)` as already used in `startBattle`), map each to
   a `PokemonSet`, and call `validator.validate(team:)`.
5. **Surface results in `TeamPickerCard`** when `championsFormat` is on: list
   violations. Split into hard legality (`$0.category.isLegality == true`) vs.
   coherence (warnings). Color legality red, coherence orange.
6. **Gate Start.** When `championsFormat` is on, `canStart` additionally requires
   **zero hard-legality violations** on both teams. Coherence warnings don't block.
7. **Force the format on the engine.** When starting a Champions battle, ensure
   every slot battles at Lv 50 with Champions scaling. Cleanest approach: map the
   resolved slots through a normalizer that sets `level = 50` and
   `championsMode = true` (converting main-series EVs → 0–32 scale with
   `ev*32/252` when a slot wasn't already in Champions mode) **before**
   constructing `BattleSide`. Add this as a pure helper so it's unit-testable;
   don't mutate the persisted `SavedSpread`/`SavedTeam`.

**Tests (`ChampionsFormatTests.swift`):** a legal 6-mon Champions team yields no
hard-legality violations; an over-cap stat-point set (e.g. 68 total) trips
`statPointsOverCap`; an illegal species/item/ability/move trips the right
category; the Lv-50 normalizer forces level 50 and champions scaling and never
exceeds 66 total.

---

## Suggested commit sequence

1. `Battle: multi-hit moves`
2. `Battle: drain, recoil, and self-heal moves`
3. `Battle: move secondary effects`
4. `Battle: crits ignore beneficial stat stages`
5. `Battle: choice lock + contact recoil (+ Tier B as done)`
6. `Battle: enforced Champions regulation format`

## Definition of done

- All pre-existing tests still pass; new per-phase tests added and passing.
- No new build warnings.
- Champions format blocks illegal teams and runs legal ones at Lv 50 with the
  66/32 stat-point scaling.
- Final summary notes any Tier B items deferred and any species/ability
  name-mapping caveats discovered in Phase 6.
