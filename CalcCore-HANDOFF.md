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

Last full run (after the solver speed modifiers): **826 of 826 passing**, twice. The test-randomness
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

The app has several speed calculations that disagree. The Speed Tiers
screen uses 0.25x for paralysis; the sim, the port and the solver use the
modern 0.5x. That's flagged as a separate fix.

Not yet done: goals beyond one hit (2HKO, surviving two hits) and survival
from less than full HP.

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
  - Only one set is loaded per side. A pasted team shows a picker for which
    set to load. Importing a whole team into `SavedTeam` isn't wired up,
    though `PasteImporter.teamSlot(for:)` exists for it.
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
