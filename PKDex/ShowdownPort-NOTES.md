# Showdown damage-calc port — scope & wiring notes

This is a **faithful, near-line-by-line Swift port** of Smogon's
[`@smogon/calc`](https://github.com/smogon/damage-calc) (MIT). Source is
vendored under `tools/vendor/damage-calc` (and `pokemon-showdown` for the
Champions mod data). File/function names mirror upstream so the port stays
diffable against future updates.

## Decision: port everything, wire only what the app uses

We port the **full** calc — including mechanics Pokémon **Champions does not use**
— but leave the unused parts **present-but-unwired** so they're ready to expose
later without re-deriving them. Do **not** simplify these away when porting:

- **Z-Moves** (`getZMoveName`, `useZ`, Z typings)
- **Dynamax / Max Moves / G-Max** (`useMax`, `isDynamaxed`, `getMaxMoveName`, max HP scaling)
- **Terastallization** (`teraType`, Stellar)
- **Older generations** (RBY/GSC/ADV/DPP/BW/XY/SM/SS stat + mechanics paths in `gen12/gen3/gen4/gen56/gen789`)
- Multi-hit / Metronome-item / Parental Bond nuances, ruin abilities, etc.

### What IS wired to the app (Phase 1)
- **Champions (upstream "gen 0")** damage: the full `mechanics/champions.ts`
  pipeline is ported in `ShowdownChampions.swift`
  (`calculateChampions` + `calculateBasePower/Attack/Defense/BaseDamage/FinalMods`
  and their `*Mods` helpers), reached via the `calculateShowdown(gen:…)` entry
  point (upstream `calc.ts`'s `MECHANICS[gen.num]` dispatch). Verified numerically
  against hand-computed rolls; `desc` is dropped (see deviation below).
- Stat math: `calcStatChampions` (0–32 SP: HP `base+sp+75`, others
  `floor(nature·(base+sp+20))`) and `calcStatADV` for Gen 9.

### Still TODO for Phase 1
- **Gen 9 (SV)** damage: `mechanics/gen789.ts` is **not yet ported** — only the
  Gen 9 stat formula (`calcStatADV`) exists. `calculateShowdown` currently
  `preconditionFailure`s for any gen ≠ 0. Add a `ShowdownGen789.swift` pipeline
  and route it in the dispatch when SV support is wanted.

### What is ported-but-DORMANT (no UI/engine entry point yet)
Everything in the bullet list above. It compiles and is unit-tested via parity
vectors where practical, but nothing in the app constructs it. Candidates for
later exposure: a Tera toggle in the calc, a full multi-gen calculator, or
Phase 2's battle-engine port (`pokemon-showdown/sim`).

## Deviation: `RawDesc` text not ported (damage-only)
The calc's `desc` / `RawDesc` (the human-readable "252+ Atk … 90.1% chance to
OHKO" string) is **not** ported. It is write-only in the damage path — no damage
number depends on it — and the app renders its own result UI. Every `desc.X = …`
line from `champions.ts`/`util.ts` is simply dropped; the math is otherwise
line-for-line. If the calc's description text is ever wanted, add a `RawDesc`
sink and re-thread it.

## Champions specifics (from Showdown's official mods)
Champions rules/data live upstream in `pokemon-showdown/data/mods/champions`
(+ `championsregmb`) and in the calc's `mechanics/champions.ts`. We vendor that
data (see the data generator in `tools/`) rather than hand-rolling rules.

## Licensing
MIT (both repos). Attribution + license text bundled under
`PKDex/Showdown-LICENSE`; per-file "ported from …" headers retained.
