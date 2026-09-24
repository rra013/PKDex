# Calc core extraction & EV solver — handoff

Working notes for the in-progress work that turns the damage calculator into
something an EV solver can drive. Companion to `ShowdownPort-NOTES.md`, which
covers the vendored `@smogon/calc` port itself. (That file isn't in the repo
as of 2026-09-23.)

## Why any of this

The EV solver (feature: "solve for the minimum EVs to survive X / KO Y /
outspeed Z") needs to run the damage calc thousands of times off the main
thread. Two things blocked that:

1. `DamageCalcVM` is `@MainActor` and `CalcSide` holds a `PKMNStats`
   SwiftData model, so no calc input could leave the main actor.
2. The module builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` plus
   `SWIFT_UPCOMING_FEATURE_INFER_ISOLATED_CONFORMANCES`, so *every* unannotated
   type — including pure value types — is main-actor-isolated, and their
   synthesized conformances with them.

The search space is small enough to scan exhaustively: only multiples of 4
move a mainline stat (64 values), and Champions stat points are 0–32 (33
values). That avoids any monotonicity assumption. The expensive case is a
combined defensive solve, which sweeps a 64 x 64 (HP, Def) grid ≈ 8k
evaluations — hence the need to get off the main actor.

## Status

| Phase | What | State |
|---|---|---|
| 1.1 | `ShowdownPaste.swift` — paste text ⇄ structs | done, tested |
| 1.2 | `ShowdownPasteImport.swift` — resolve against Pokedex, validate | done, tested |
| 1.3 | `PasteImportSheet.swift` — paste import + copy/share export on the calc | done, tested, checked in the simulator |
| 2.1a | `CalcSnapshot.swift` — Sendable snapshot/outcome types | done, tested |
| 2.1b | `CalcEngine.swift` — legacy engine extracted, VM delegates | done, tested |
| 2.1c | Vendored port made nonisolated | done, tested |
| 2.1d | Champions/Showdown path extracted | done, tested |
| 2.2 | `EVSolver.swift` — survive / KO / outspeed solves | done, tested |
| 2.3 | `EVSolverSheet.swift` — solver UI on the calc's move rows | done, checked in the simulator |

Last full run (after the spread-move rules fix): **873 of 873 passing**. The test-randomness
fixes held for three runs in a row before that. See "Randomness in tests" below. Both
engines are behind `CalcEngine`, so the whole damage suite exercises the
extracted code.

## The `nonisolated` convention

Every pure computational type in the calc path is explicitly `nonisolated`.
This is load-bearing, not stylistic — without it the type is main-actor-bound
and unusable from the solver. Same convention as `PokeAPIGraphQL.swift`'s DTOs.

Annotated so far, in dependency order (each was forced by a cascade from the
one above):

- `ShowdownPaste.swift` — all 5 types
- `ShowdownCalc.swift` — `toID`, `ShowdownStat`, `ShowdownStats`,
  `ShowdownNature`, `ShowdownNatures`, `ShowdownStatsCalc`,
  `ShowdownGameType`, `ShowdownWeather`, `ShowdownTerrain`, `ShowdownSide`,
  `ShowdownField`
- `PokemonStatsModels.swift` — `calcHP`, `calcStat`, `statStageMultiplier`,
  `Nature` (+ `StatKey`), `allNatures`, `HeldItem`, `WeatherCondition`,
  `TerrainCondition`, the four EV cap constants, `championsEVToMain`,
  `ItemModResult`, `AbilityModResult`, `computeItemModifiers`,
  `computeAbilityModifiers`, `DamageAbility`, `typeBoostingItemMap`,
  `typeResistBerryMap`
- `damageCalculator.swift` — `typeEffectivenessChart`, `calcDamageRange`,
  `computeTypeEffectiveness`, `pokeFloor`
- `MegaForms.swift` — `MegaForm`, `MegaForms`
- `BattleSimSeed.swift` — `normalize`
- `ShowdownRuntime.swift` — `ShowdownType`, `ShowdownCategory`,
  `ShowdownStatus`, `ShowdownSpecies`, `ShowdownMoveData`,
  `ShowdownGeneration` (protocol), its `nature(_:)` default witness,
  `ShowdownMove`, `ShowdownPokemon`, `SPECIAL_TYPES`
- `ShowdownMechanics.swift` — all 26 free functions, `ShowdownDamageValue`,
  `ShowdownResult`, `EV_ITEMS`
- `ShowdownChampions.swift` — all 10 `calculate*` free functions
- `ShowdownItems.swift` — `ShowdownItems`
- `ShowdownData.swift` — `ShowdownGen0` (+ `@unchecked Sendable`)
- `damageCalculator.swift` — `formatAbilityName` (2.1d; the Champions path
  formats ability names before handing them to the port)

Three lessons from doing it:

- **`nonisolated` only widens.** It cannot break an existing main-actor call
  site, which is why this was safe to apply to central files.
- **Protocol default witnesses bite.** `ShowdownGen0`'s conformance stayed
  main-actor-isolated even after annotating the class *and* the conformance,
  because the `nature(_:)` default implementation in an unannotated
  `extension ShowdownGeneration` was the isolated witness. If you see
  "conformance ... crosses into main actor-isolated code", look for a default
  implementation, not the conformer.
- **Expect cascades.** Each pass exposed the next layer: `HeldItem` →
  `MegaForms`/`normalize`; `calcDamageRange` → `pokeFloor`;
  `ShowdownPokemon` → `SPECIAL_TYPES`/`ShowdownStatsCalc`; the mechanics
  functions → `EV_ITEMS`. Annotate, check diagnostics, repeat.

## What 2.1d landed

Both engines now live in `CalcEngine` as `static` members of the `nonisolated`
enum, taking snapshots rather than `CalcSide`:

| Was (private on `DamageCalcVM`) | Now on `CalcEngine` |
|---|---|
| `showdownResult` | `evaluateChampions(move:attacker:defender:field:) -> CalcOutcome?` |
| `showdownSpecies(for:)` | `showdownSpecies(_:for:)` |
| `resolveMegaSpecies` | same, `moves: [MoveSnapshot]` |
| `damageRange` | returns `(min:max:rolls:)` |
| `makeShowdownPokemon` | takes the generation plus `FieldSnapshot` (for `burn`) |
| `makeShowdownField` | takes `FieldSnapshot` |
| `showdownItemName`, `typePlateName` | unchanged bodies |

`CalcEngine.evaluate(move:attacker:defender:field:)` is the single entry point
and owns the Champions-then-legacy precedence, so a solve and the on-screen
result can't disagree about which engine answered.
`DamageCalcVM.computeSingleResult` is now just snapshot → evaluate → dress.

Three things to know before building on it:

- **`CalcOutcome.rolls` is populated on the Champions path**, but only for
  `ShowdownDamageValue.rolls`. `.fixed` has no spread, and a multi-hit /
  Parental Bond `.matrix` is summed per hit — its row minima don't co-occur as
  one roll of the whole move, so reporting them as rolls would misstate KO
  chance. Both stay nil, and `ohkoChance` is nil with them.
- **Do not let the solver construct a non-Champions Showdown request.**
  `calculateShowdown` `preconditionFailure`s for any gen != 0 (see
  `ShowdownPort-NOTES.md`). `evaluateChampions`'s guard chain returns nil and
  falls back to legacy; it is load-bearing, not defensive. Widen it only
  alongside the port.
- **Ordering changed in one place.** `computeSingleResult` used to try the
  Showdown branch *before* the `snapshot()` nil-guard; it now snapshots first.
  Both bail to `emptyResult` for a side with no species (`showdownResult` had
  its own `pokemon != nil` guard), so this is a no-op — but it's the only
  behavioural difference, and `DamageCalcMegaEvolutionTests` plus the
  `BattleTier` files are where a mistake would surface.

**Current-HP bug fixed (2026-09-23).** `makeShowdownPokemon` converted the
calc's current-HP percentage against a max HP computed with 0 HP points
(its comment claimed Champions max HP is fixed; HP stat points change it).
With HP investment below 100%, the port got too little HP: at "50%" with 32
HP points it saw 76/185 (41%), and Eruption did 29–35 instead of 35–42.
That affected Eruption, Water Spout, Flail, Reversal, Wring Out, Crush Grip,
the ⅓-HP pinch abilities, and Pain Split / Endeavor / Final Gambit. It hit
both the calc and the battle sim, which feeds current HP through the same
bridge. It now converts against the port's own `maxHP()`.
`CurrentHPBridgeTests` failed on the old code and pass now.

## What 2.2 landed

`EVSolver` is a `nonisolated` enum with three solves, all returning
`Result<Solution, Failure>`:

| Solve | Varies | Goal |
|---|---|---|
| `minimumToSurvive(move:attacker:defender:field:certainty:)` | defender HP + the defensive stat the engine reads | survives from full HP |
| `minimumToKO(move:attacker:defender:field:certainty:)` | the attacker's offensive stat the engine reads | OHKO from full HP |
| `minimumToOutspeed(_:targetSpeed:multiplier:allowTie:)` | Speed | beats (or ties) a speed stat |

Things to know before building the UI on it:

- **Stats are probed, not hardcoded.** Each candidate stat is set to 0 and
  to the cap; the one that moves `damageMax` most is the one solved. That's
  how Psyshock picks Def, Body Press picks the user's Def, and Foul Play
  reports `.noRelevantStat` on the Champions path. The legacy engine
  models none of those, and the probe follows whichever engine answered.
  Tests cover all three.
- **`Certainty.chance` needs rolls.** Without them (legacy path, multi-hit)
  it falls back to `.guaranteed`, the conservative reading, and
  `Solution.usedRolls` is false. The UI should say which one applied.
- **Budget.** The EVs available are the total cap minus what the side
  already has in *other* stats. Existing investment in the solved stats is
  freed, since the solve replaces it.
- **Minimality is exact, not heuristic.** The survive solve scans the full
  grid and prunes only on cost. Ties go to the spread that takes the least
  worst-case damage. `EVSolverTests` checks minimality by an independent
  brute force over every cheaper spread.
- **Full HP only.** Both engines compare damage against max HP, so the
  solves ignore `currentHPPercent`. Chip damage, hazards and multi-turn
  goals (2HKO, survive two hits) aren't modelled yet.
- **Speed takes a caller-supplied multiplier** (Scarf 1.5, Tailwind 2,
  paralysis 0.5). The solver doesn't read items or side conditions for
  speed.
- **Unreachable goals report `best`**, the outcome at maximum investment,
  so the UI can show how close the spread gets.

## What 2.3 landed

Every damaging move row on the calc now has a **Solve EVs** button. It opens
`EVSolverSheet` for that move and direction, which shows three things:

- the defender's cheapest survive spread,
- the attacker's cheapest OHKO investment,
- each side's Speed needed to outspeed the other.

Each answer has an **Apply** button that writes the EVs back to the
`CalcSide`, and the calc updates immediately.

- **Solves run in a detached task** on snapshots taken when the sheet opens.
  `SolveResults` is `nonisolated` for that reason.
- **"Every roll" / "Most rolls (≥ 50%)"** only appears when both sides are
  in Champions mode. If a matchup falls back to the legacy engine anyway,
  the sheet says the answer is the every-roll one.
- **Rows show current → new**, so applying an answer that *lowers*
  existing investment is visible before it happens.
- **Mirror matches** label the sides "(P1)" / "(P2)".
- Checked in the simulator (Garchomp vs Garchomp, Outrage). The solver said
  0 HP / 31 Def survives at 83.1–99.5%; after Apply the calc showed exactly
  152–182 (83.1%–99.5%), 2HKO.

**Speed rows use final Speed (2026-09-23).** `CalcEngine.finalSpeed` runs a
side through the port's `getFinalSpeed`, so the Outspeed answers include
Choice Scarf / Iron Ball, Tailwind, weather and terrain speed abilities,
Unburden, Quick Feet, Protosynthesis / Quark Drive, and paralysis. It
returns nil off the Champions path, like `evaluateChampions`. The sheet then
falls back to the raw stat and says so in the footnote, rather than keeping
a fourth copy of the speed rules. `EVSolver.minimumToOutspeed` now takes a
`speedOf` function instead of a fixed multiplier, and both sides are
measured with it. `FinalSpeedTests` checks that it matches
`CalcSnapshot.speed` exactly when no modifiers apply.

The app still has several speed calculations. The Speed Tiers screen used
0.25x for paralysis (the Gen 1–6 rule) while the sim, the port and the
solver use 0.5x. It was fixed on 2026-09-23, and
`SpeedTierTests.paralysisMatchesShowdownPort` now ties the two together so
they can't drift apart again.

**Speed Tiers checked against the port for every combination
(2026-09-23).** Moving Speed Tiers wholesale onto `getFinalSpeed` would
lose its "what if" nature: it applies modifier categories to every Pokedex
species, many outside the Champions data. It keeps its own table, and
`SpeedTierPortParityTests` compares every benchmark x item x ability combo
with the port on three species. That found 84 mismatches, now fixed:
- **Champions "Min" used 0 IV.** Champions fixes IVs at 31. The label is
  now "Min (0 EV, -Spe, lowest IV)".
- **Unburden + item stacked.** Unburden means the item is used up, so the
  item is now ignored (Scarf + Unburden showed 3x).
- **Two modifiers were multiplied as decimals and truncated.** They now use
  `applySpeedModifiers`, which chains them in 1/4096 steps with `pokeRound`
  like the games.

**Survive / KO from current HP (2026-09-23).** `CalcOutcome` has an
optional `defenderCurrentHP` (nil = full). `isGuaranteedOHKO`,
`isGuaranteedSurvival` and `ohkoChance` measure against it. Percentages
stay relative to max HP, as the calc displays them. Both engines fill it
in: the Champions path from the port's `curHP()`, the legacy path from
`CalcSnapshot.currentHP` (same percentage-of-max conversion). As the solver
varies HP EVs, current HP stays the same percentage of the new max, so the
answer is "cheapest spread to survive from 60%". The sheet's headings add
"from N% HP" when the defender isn't full. Nothing changes at full HP.

**Two-hit goals (2026-09-23), `TwoHitSolver.swift`.** "Survive two hits"
and "guaranteed 2HKO" are played out in the **battle simulator**, not summed:
the attacker uses the move on two consecutive turns (end-of-turn effects
apply between hits) against a passive defender. Sitrus Berry, Multiscale,
Stamina, Weak Armor, Leftovers, HP-scaling moves and so on come from the
sim's own rules. Design points:
- **"Guaranteed" = pinned rolls:** max for surviving, min for KOing. Crits
  only if the calc's Crit toggle is on. `RollOverride.suppressChanceEvents`
  turns off misses and every luck-based effect (secondary effects, Focus
  Band, contact abilities, Quick Claw…); all engine chance draws now go
  through `luck(_:)` / `accuracyRoll()`.
- **HP berries break "max roll is worst".** A bigger first hit can trigger
  Sitrus sooner and leave more HP. With an HP berry, the first hit is
  scanned across 17 points of its range (`RollOverride.Roll.fraction`), and
  the goal must hold at every one. Mutation-checked: without the scan, the
  answer faints at the lowest first-hit rolls.
- **Sim/calc parity:** `singleHitParity` asserts a single simulated hit
  equals `CalcEngine.evaluate` at min and max rolls.
- **Refuses** what the sim can't reproduce: Helping Hand, Friend Guard,
  Protect, Glaive Rush, Z-bypass, the misc multiplier, mainline IVs ≠ 31,
  and a sleeping or frozen attacker.
- **Doubles spread:** with the calc's doubles toggle and a spread move, the
  run is a doubles battle with a very bulky placeholder partner next to the
  defender, so both hits take 0.75x.
- Runs on the main actor (the sim's damage path uses `DamageCalcVM`), about
  0.4 ms per two-hit simulation, and yields between runs.

**Spread moves fixed at the same time.** `SpreadMoves.swift` reads each
move's `target` from the Showdown data, replacing the sim's hand-written
list (19 of 39 spread moves, and it wrongly included Earth Power). The sim
applies 0.75x only when a move has more than one target at the time it's
used, so a lone surviving foe takes full damage. `allAdjacent` moves
(Earthquake, Surf, Explosion) now also hit the user's ally. Wide Guard
still blocks per side by move type. The calc's legacy engine applied the
doubles toggle to *every* move and now applies it to spread moves only; the
Champions port already did.

Follow-ups (2026-09-23):
- **Expanding Force** now hits both foes in the sim in Psychic Terrain when
  the user is grounded. `performMove` reroutes it to the spread path at the
  moment it's used, since terrain can change earlier in the turn. The port
  still supplies the 1.5x boost.
- **New `BattleEngine.isGrounded(_:)`**: Gravity or Smack Down always
  ground; otherwise Flying-type, Levitate and Eelevate float. Switch-in
  hazards use it now, so under Gravity a Flying-type takes Spikes, Toxic
  Spikes and Sticky Web. Air Balloon and Iron Ball aren't modelled.
  `BattleHazardRemovalTests` covers it: a Flying type skips Spikes normally
  and takes exactly what a grounded Pokemon takes under Gravity.
- **Hazard damage rounding fixed (2026-09-23).** The sim rounded Spikes and
  Stealth Rock damage to the nearest HP. Pokemon Showdown's `damage()`
  rounds down and deals at least 1 (`clampIntRange` → `Math.floor`). Now
  `BattleEngine.spikesDamage` (`[0,3,4,6][layers] * maxHP / 24`) and
  `stealthRockDamage` (`maxHP * effectiveness / 8`) match. Tests use HP
  values where the two rounding rules differ. No other chip damage in the
  sim used round-to-nearest.
- **Spread moves follow the same rules as single-target moves
  (2026-09-23).** `performSpreadMove` skipped Disable, Encore, Pressure,
  Destiny Bond clearing and `lastMoveIndex` tracking (so a later Encore or
  Disable hit the *previous* move). It now runs the same steps in the same
  order. Both paths use `usesSpreadPath(_:attacker:)` to decide where a move
  runs, so Encore or a charged move redirecting between spread and
  single-target moves lands on the right path without looping.
  `SpreadMoveRulesTests` (6) all failed on the old code.
- **The battle AI is unaffected by the new spread list.** The policy model's
  inputs are species indices and 105 continuous features. `isSpread` is only
  used after the model picks a move, to route the action. No retraining is
  needed, and PR #9's warning about that was over-cautious.

## Design decisions worth not re-litigating

- **Snapshots hold raw inputs, not finished stats.** The solver varies an EV
  and recomputes, so it needs base stats + EVs + IVs + nature + stages and the
  same formula the UI uses. `CalcSnapshot.stat(_:)` collapses `CalcSide`'s five
  near-identical accessors into one to limit drift; `CalcSnapshotTests` asserts
  the two agree rather than hardcoding numbers.
- **`CalcOutcome.rolls` is optional.** The legacy engine produces a min/max
  `Double` pair and nothing in between. Only the Showdown port has real rolls.
  Don't design the constraint API around rolls being always available.
- **`CalcOutcome` uses `Double` for damage**, matching both engines' own
  arithmetic (they `floor()` a Double product and never round to Int).
- **`snapshot()` returns nil with no species.** The calc UI tolerates an empty
  side (stats fall back to 1); solving against a phantom 1/1/1 statline would
  silently produce garbage.
- **`PasteImporter.validator` is a required parameter**, not defaulted:
  building a `ChampionsValidator` parses ~600 KB of JSON, so the owning view
  must construct the importer once and hold it, not rebuild per keystroke.
- **Imported sets with no nature default to Serious**, not `SavedSpread`'s own
  `"adamant"` default, which would silently hand a set a +Atk/−SpA spread.

## Open items

- **Randomness in tests — resolved 2026-09-23.** Five tests could fail by
  chance (Berserk found later the same day); all are now deterministic or effectively so. Each fix was
  mutation-checked: the mechanic was broken on purpose, the test failed, and
  the source was restored.

  | Test | Cause | Fix |
  |---|---|---|
  | `heavySlamHitsHarderAgainstLightTarget` | at `power: 1` the roll range is 2–6, swamping 60 vs 120 BP (~16%) | pinned rolls |
  | `lowKickScalesWithDefenderWeight` | roll range 2–4 overlaps 80 vs 120 BP (~22%) | pinned rolls |
  | `earthquakeHitsDiggingTargetForDoubleDamage` | a crit in either run skewed the ratio (~8%) | pinned rolls; assertion tightened from `> 1.5x` to exactly `2x` |
  | `compoundEyesLandsMoreThanBaseline` | 200 samples put the 5pp threshold ~2 SD from the mean (~2%) | 1000 samples (~1 in 500k), plus a new exact test of `effectiveAccuracy` |
  | `berserkOnlyFiresOnce` | a random crit (~4%) could KO from 60% HP and skip the trigger | pinned rolls; `berserkWindowHoldsAtBothRollExtremes` checks every non-crit roll still lands in the window |

  **The tool:** `BattleEngine.rollOverride`. Set
  `.init(crit: false, roll: .max)` on each engine before `executeTurn()`. It
  pins `rollCrit` and every damage roll (moves, Struggle, confusion self-hits
  all go through `rollDamage`); nil keeps normal random play. Use it for any
  new test that compares damage across engine runs. **Do not** loosen
  thresholds instead: at `power: 1` the bands are close enough that a
  tolerant threshold would also stop the test detecting the mechanic failing
  outright.

  **Checked and left alone:** the crit-stage tests in `BattleCritTests`
  average 40 rolls (ratio error ~1% against a ±10% band, and a real bug
  shows as ~0.5), and the "at least one proc in 50–100 tries" tests at 30%
  per try (false failure ~10⁻⁸ or less). The engine still has ~35 other
  random draws (paralysis, confusion, sleep length, speed ties, contact
  abilities, …); `rollOverride` doesn't cover them, so a new test depending
  on one needs its own guard. Three full runs on the old build surfaced no
  flakes beyond the four above.
- **Phase 1.3 landed** (`PasteImportSheet.swift`). Each calc side has
  **Paste** and **Export** buttons. Paste opens a sheet with a live preview;
  Export is a menu with Copy first and Share second. Import goes through the
  same `loadSpread` path as the Load button. Details:
  - Unmodelled mainline items (Covert Cloak, Loaded Dice, …) show as grey
    info notes, not errors. Legality violations show in orange as warnings
    and don't block the import.
  - **Ambiguous EV scale now defaults to the calc side's scale**, via
    `ShowdownPaste.parse(_:ambiguousDefault:)`. The parser's own default is
    still mainline. This was a real bug: a Champions export written only in
    multiples of 4 (`32 HP / 32 Atk`) fits both scales, so it re-imported as
    mainline EVs and came back as 4 / 4 points. `PasteRoundTripTests` covers
    it, and a mutation check confirmed the test catches it. The toggle still
    shows whenever the numbers fit both scales.
  - Export writes EVs in the side's own scale. A Champions set exports as
    stat points, which is what the parser expects for Champions pastes. It is
    *not* converted to mainline EVs for use in a mainline Showdown format.
    If that's wanted, `showdownText(scale: .mainline)` already does it.
  - Only one set is loaded per calc side; a pasted team shows a picker.
    **Whole teams import from the Teams screen** (`TeamPasteImport.swift`,
    the clipboard button next to +). Each set becomes a `SavedSpread` named
    "Team · Pokemon", and the `SavedTeam`'s slots point at those spreads, so
    `resolvedSlots` and the calc's Load list both see them. Spread names are
    made unique against existing spreads **and** team-slot references, since
    AI slots like "Garchomp (AI)" have no spread and a new spread with that
    name would take the slot over. Blocked sets are skipped, only the first
    six are imported, and a blocked set shows just its blocking reason
    because its legality warnings all follow from the unknown species.
    `TeamPasteImportTests` cover the planning, which builds the models
    without inserting them, so no SwiftData container is needed.
- **Model downloader hardening — done 2026-09-23** (`05_PokiiModelDownloader.swift`,
  tests in `ModelFileSafetyTests`). Both audit items are fixed, plus a gap
  found next to them:
  - **Manifest names are validated** before anything touches disk. Only
    plain relative paths made of `[A-Za-z0-9._-]` components are allowed,
    with no `..`, absolute paths or backslashes, and a containment check on
    top. Reserved names (`manifest.json`, `verified.json`) are rejected, as
    are duplicates, negative sizes and malformed SHA-256 strings. A bad
    manifest fails the download ("Manifest rejected: …"). `isModelInstalled`
    applies the same validation to the saved manifest. All 8 names in the
    real pinned manifest (3b-v3) pass these rules.
  - **Skipping an existing file now needs a verification record**
    (`verified.json`), written only after a file's SHA-256 matches. Before,
    a right-sized file was skipped unhashed, so a download killed between
    finishing and verifying installed an unchecked file. An oversized
    partial is now deleted and restarted rather than treated as complete.
  - `isModelInstalled` stays a size-only check by design: the saved
    manifest is only written after every file has been verified.
  - Not changed: the manifest itself is trusted via HTTPS plus the commit
    pin, with no hash of it embedded in the app.

## Verifying

Xcode's `BuildProject` / `RunSomeTests` could not retrieve a build log in this
environment and reported tests as "not run" without executing them. `xcodebuild`
against a simulator works:

```
xcodebuild test -project PKDex.xcodeproj -scheme PKDex \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -parallel-testing-enabled NO
```

There is no plain "iPhone 17" simulator on this machine. Turning off
parallel testing matters: the default clones the simulator, and a clone
left over from an interrupted run makes the next launch fail with
"Application failed preflight checks" (Busy).

`xcodebuild` also sometimes hangs *after* the tests finish (the Swift Testing
summary prints, the process never exits). If you script repeat runs, kill it
once the `Test run with N tests` line appears rather than waiting on it.
`-test-iterations` doesn't repeat Swift Testing tests; loop
`test-without-building` instead.

The existing suites are the parity gate for the calc extraction — the nine
`BattleTier` files, `DamageCalcMegaEvolutionTests`, `AbilityTests`,
`BattleItemsTests`, `TypeChartTests`, `Known Damage Ranges` and `Damage Engine`
all run through `computeSingleResult`. They encode expected damage numbers that
can't be re-derived, so if they pass, the extraction is faithful. There is no
old-vs-new parity test and there can't be: relocating the body removed the
reference implementation.

`XcodeRefreshCodeIssuesInFile` is a fast per-file type/isolation check and was
used throughout, but it is not a build — it won't catch cross-file or link
issues. It also times out on newly-added files; retrying two or three times
works.
