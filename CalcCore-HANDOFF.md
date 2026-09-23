# Calc core extraction & EV solver — handoff

Working notes for the in-progress work that turns the damage calculator into
something an EV solver can drive. Companion to `ShowdownPort-NOTES.md`, which
covers the vendored `@smogon/calc` port itself.

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
| 1.3 | Import sheet + `ShareLink` export UI | **not started** |
| 2.1a | `CalcSnapshot.swift` — Sendable snapshot/outcome types | done, tested |
| 2.1b | `CalcEngine.swift` — legacy engine extracted, VM delegates | done, tested |
| 2.1c | Vendored port made nonisolated | done, tested |
| 2.1d | Champions/Showdown path extracted | done, tested |
| 2.2 | `EVSolver.swift` | **not started** |
| 2.3 | Solver UI | **not started** |

Last full run (after 2.1d): **787 of 788 passing**. The single failure was
`lowKickScalesWithDefenderWeight`, one of the random-roll flaky tests — see
"Known flaky tests" below. Both engines are now behind `CalcEngine`, so the
whole damage suite exercises the extracted code.

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

## Next step: 2.2 — `EVSolver.swift`

Nothing structural is in the way now: `CalcEngine.evaluate` is `nonisolated`,
takes and returns `Sendable` values, and covers both formats. The remaining
design work is the constraint API, and the one constraint the snapshot layer
already anticipates is roll granularity — available on the Champions path
only, so the predicate set has to degrade to
`isGuaranteedOHKO` / `isGuaranteedSurvival` when `rolls` is nil.

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

- **Known flaky tests — two, one root cause.** The battle-tier suite compares
  two independent `BattleEngine` runs and asserts a ratio between them, but
  every run randomises both the crit and the damage roll, so any two runs can
  collide. Neither test is wrong about the mechanic; both are unpinnable as
  written.

  - `earthquakeHitsDiggingTargetForDoubleDamage` (`BattleTier8Tests.swift:160`),
    ~8% of runs. Crits are rolled randomly (`rollCrit`,
    `BattleSimulator.swift:2439`) and a crit in the *control* engine deflates
    the ratio below the test's 1.5 threshold — `2.0 x 71 = 142` vs
    `1.5 x 75 = 112` gives 1.27. Without a crit the ratio is bounded to
    [1.7, 2.35] and it always passes.
  - `lowKickScalesWithDefenderWeight` (`BattleTier9Tests.swift:146`), ~22% of
    runs. The damage roll (`Int.random(in: dMin...dMax)`,
    `BattleSimulator.swift:2447`) happens *before* the tier-5 weight
    multiplier is applied. At `power: 1` both sides compute to 120 Atk / 120
    Def and a 2–4 damage range; Wisp is unknown so it falls back to 50 kg →
    80 BP (**not** the 60 BP the test's comment claims — the table's `< 50`
    band excludes 50), Snorlax is 460 kg → 120 BP. Outcomes are
    {160, 240, 320} vs {240, 360, 480}, so the assertion fails whenever
    Snorlax rolls a 2 and Wisp rolls a 3 or 4.

  Recommended fix, covering both: an optional roll override on `BattleEngine`
  that `rollCrit` *and* the damage-roll line consult, so ratio tests can take
  variance off the table. This is latent across the whole battle-tier suite,
  not two bad assertions. **Do not** just loosen the thresholds — at
  `power: 1` the bands are close enough that a tolerant threshold would also
  stop the tests detecting the mechanic failing outright.
- **Phase 1.3 UI is unstarted**, so the paste parser and importer are dead code
  from the app's point of view. When building the import sheet: unmodelled
  *mainline* items (Covert Cloak, Safety Goggles, Booster Energy, Clear Amulet,
  Loaded Dice, Weakness Policy, Punching Glove) fire `itemUnrecognized`
  constantly because `HeldItem` covers all 58 Champions-legal items but not the
  wider pool. Style that as informational, not an error, or good pastes look
  broken.
- **Ambiguous EV scale.** A low-investment paste (`4 HP / 8 Atk`) fits both
  scales; the parser defaults to mainline and sets `scaleWasAmbiguous`. The
  import sheet should turn that flag into a units toggle
  (`parse(_:forcedScale:)` accepts the override).
- **Security items from the earlier audit are unaddressed**, notably the
  size-only model integrity check (`05_PokiiModelDownloader.swift:110`, `:281`)
  and the unvalidated manifest filenames used as path components (`:228`,
  `:299`).

## Verifying

Xcode's `BuildProject` / `RunSomeTests` could not retrieve a build log in this
environment and reported tests as "not run" without executing them. `xcodebuild`
against a simulator works:

```
xcodebuild test -project PKDex.xcodeproj -scheme PKDex \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0'
```

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
