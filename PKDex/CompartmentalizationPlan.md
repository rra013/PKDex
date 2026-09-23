# Data Compartmentalization Plan

Goal: when regulations change or new Pokemon / mega forms / battle gimmicks
ship, the app should be updateable by editing a small number of bundled JSON
files. No hunting through Swift, no parallel lists that can drift apart.

This document is an audit + a prioritized migration plan. Nothing here is
implemented yet — pick items off as they become relevant.

---

## 1. Current State (Snapshot, 2026-06-10)

### Already well compartmentalized

| System | Source of truth | Notes |
|---|---|---|
| Champions species roster | `champions-m-a.json` → `species_whitelist` | Read via `ChampionsRegulation.speciesWhitelist()`, cached, single-source. Comment at `ChampionsRegulation.swift:18` documents the prior bug where this lived in 3 places. |
| Per-species abilities, base stats, legal moves, mega/alt forms | `champions-m-a-learnsets.json` | Loaded once into `ChampionsLearnsetStore.shared`. |
| Champions roster shim | `champsDex.swift` | Now just forwards to `ChampionsRegulation.current.speciesWhitelist()`. |
| Pokedex base data (nat-dex) | PokeAPI → SwiftData (`PKMN`, `PKMNStats`) | Fetched dynamically, no hardcoded species list. |
| Move damage class (physical / special / status) | `move_categories.json` | Already external. |
| ML featurizer config | `feature_config.json` | Already external. |
| Regulation enum | `ChampionsRegulation.swift` | Adding a new regulation = drop two JSONs + add one enum case + bump `current`. |

### Gaps — single source of truth missing or partial

| System | Where it lives | Problem |
|---|---|---|
| **Gimmick legality flags** (`tera_allowed`, `dynamax_allowed`, `z_moves_allowed`, `mega_evolutions_allowed`, `mega_rayquaza_allowed`) | `champions-m-a.json:14-18` | **Schema exists in JSON but no Swift code reads any of these flags.** Confirmed by grep — only matches are in the JSON itself. A new regulation that flips `tera_allowed: true` would have no effect today. |
| **Numeric regulation rules** (`stat_points_max_total: 66`, `stat_points_max_per_stat: 32`, `iv_locked_at: 31`, `max_restricted_per_team: 0`, `team_size: 6`) | `champions-m-a.json:7-13` AND `03_ChampionsValidator.swift:78-79` | Validator hardcodes `statPointTotalCap = 66` and `statPointPerStatCap = 32` instead of reading the JSON. Two sources of truth, will drift. |
| **Mega forms** (63 entries) | `MegaForms.swift:52-342` (hardcoded `static let all`) | Adding a new mega = Swift edit + rebuild. Tolerable today (rare event) but blocks fast iteration. |
| **Held items** (~72 entries including all mega stones) | `HeldItem` enum in `PokemonStatsModels.swift:352-531` | Enum is type-safe, but new items (new generation, new event items) require Swift edits. `isMegaStone` already does the right thing dynamically against `MegaForms.all`. |
| **Battle move effect tables** | `BattleSimulator.swift:60-200`: `spreadMoves`, `firstTurnOnlyMoves`, `statChanges` (~50 entries), `statusInflicts`, `weatherSetters`, `terrainSetters`, `hazardSetters`, `protectFamily`, `pivotMoves` | All hardcoded. New move in a future gen = code edit. Hard to keep in sync with `move_categories.json`. |
| **Type chart** | `damageCalculator.swift:13-35` (`allTypes`, `typeEffectivenessChart`) | Hardcoded. Stable in practice, but balance changes (or fan-game support) require code edit. |
| **Setup moves + choice items list** | `03_ChampionsValidator.swift:169-179` | Hardcoded with a comment defending it ("setup moves are stable"). Fair, but inconsistent with the rest of the regulation-driven design. |
| **Gimmick-aware battle state** | Not implemented | `SavedSpread` has no `teraType`, no dynamax state, no Z-move slot. So even if flags were wired up, there's nothing to wire. |

### No duplications found

The previously-feared duplication of "Mega Stone" between `HeldItem` and
`MegaForms` is **not** an issue — they serve different roles
(`HeldItem` = held item picker, `MegaForms` = species-to-stone map) and
`HeldItem.isMegaStone` queries `MegaForms.all` dynamically.

---

## 2. Migration Plan (Prioritized)

Each item is independent. Ship in any order. Each has: why, what to create,
what to change, callsites to update.

### Priority 1 — Wire the regulation JSON rules block end-to-end

**Why:** This is the highest-leverage fix. The JSON already has the schema;
the Swift just isn't reading it. Today, flipping `tera_allowed: true` in
`champions-m-a.json` does nothing. That's the exact failure mode the user is
trying to prevent.

**Step 1a — Extend `ChampionsRegulation` to expose the rules block.**

Add a `rules()` accessor that decodes and caches the whole `rules` object
from the bundled JSON, similar to how `speciesWhitelist()` works.

Suggested model (new file or appended to `ChampionsRegulation.swift`):

```swift
struct ChampionsRules: Decodable, Sendable {
    let species_clause: Bool
    let item_clause: Bool
    let stat_points_max_total: Int
    let stat_points_max_per_stat: Int
    let iv_locked_at: Int
    let team_size: Int
    let max_restricted_per_team: Int
    let mega_evolutions_allowed: Bool
    let mega_rayquaza_allowed: Bool
    let tera_allowed: Bool
    let z_moves_allowed: Bool
    let dynamax_allowed: Bool
}
```

Cache it the same way the whitelist is cached
(`ChampionsRegulation.swift:75-98`).

**Step 1b — Replace hardcoded validator constants.**

- `03_ChampionsValidator.swift:78` → `ChampionsRegulation.current.rules().stat_points_max_total`
- `03_ChampionsValidator.swift:79` → `ChampionsRegulation.current.rules().stat_points_max_per_stat`
- Pass `rules.iv_locked_at` into IV validation
- Use `rules.team_size` for roster size checks
- Use `rules.max_restricted_per_team` for restricted-list enforcement

Audit `03_ChampionsValidator.swift` end-to-end for any other magic numbers
(`6`, `31`, `0`) that should come from the rules block.

**Step 1c — Wire gimmick flags into the UI and battle systems.**

Audit and gate:

- `MegaForms.form(forSpecies:heldItem:moveNames:)` — return `nil` if
  `!rules.mega_evolutions_allowed`. Special case Rayquaza behind
  `rules.mega_rayquaza_allowed` (Rayquaza's own move check stays).
- `SetBuilder.swift` / `TeamBuilder.swift` — hide the Tera-type picker
  unless `rules.tera_allowed`. Same for Dynamax / Z-Move UI when added.
- `BattleSimulator.swift` — gate Mega activation, future Tera activation,
  etc. on the same flags read at battle init.
- `SetPredictor.swift` / `PokiiBattleAI.swift` — never propose a Tera type
  or a Z-Move on a roster where the regulation forbids it.

**Result:** the regulation JSON becomes the actual source of truth. Adding
M-B with Tera on = one JSON edit + one enum case.

---

### Priority 2 — Externalize battle move effect tables

**Why:** `BattleSimulator.swift:60-200` has ~10 lookup tables covering
~100 moves total. Every new generation adds moves; today each one is a code
edit. Also, `move_categories.json` already exists for damage class — these
tables are the natural sibling.

**Create `battle_moves.json`** at the project root, bundled the same way as
`move_categories.json`:

```json
{
  "spread_moves": ["earthquake", "surf", "rockslide", "discharge", "heatwave"],
  "first_turn_only": ["fakeout", "firstimpression"],
  "protect_family": ["protect", "detect", "spikyshield", "banefulbunker"],
  "stat_changes": {
    "swordsdance":  { "target": "self",     "mods": [["atk", 2]] },
    "dragondance":  { "target": "self",     "mods": [["atk", 1], ["speed", 1]] },
    "tearfullook":  { "target": "opponent", "mods": [["atk", -1], ["spAtk", -1]] }
  },
  "status_inflicts": {
    "willowisp":   "burn",
    "thunderwave": "paralysis",
    "toxic":       "toxic"
  },
  "weather_setters":  { "sunnyday": "sun", "raindance": "rain", "sandstorm": "sand", "snowscape": "snow" },
  "terrain_setters":  { "electricterrain": "electric", "grassyterrain": "grassy", "mistyterrain": "misty", "psychicterrain": "psychic" },
  "hazard_setters":   { "stealthrock": "stealthRock", "spikes": "spikes", "stickyweb": "stickyWeb", "toxicspikes": "toxicSpikes" },
  "pivot_moves":      { "uturn": "damage", "voltswitch": "damage", "batonpass": "force" }
}
```

**Create `BattleMoveCatalog`** — a singleton like `ChampionsLearnsetStore`
that loads `battle_moves.json` once and exposes typed accessors:

```swift
final class BattleMoveCatalog {
    static let shared = BattleMoveCatalog()
    let spreadMoves: Set<String>
    let firstTurnOnly: Set<String>
    let protectFamily: Set<String>
    let statChanges: [String: BattleStatChange]
    let statusInflicts: [String: BattleStatus]
    let weatherSetters: [String: WeatherCondition]
    let terrainSetters: [String: TerrainCondition]
    let hazardSetters: [String: BattleHazard]
    let pivotMoves: [String: PivotKind]
}
```

The existing Swift enum cases (`.burn`, `.sun`, `.electric`, etc.) become
the decoding targets — keep enums type-safe in Swift, store as strings in
JSON.

**Then delete the hardcoded sets/dicts** at
`BattleSimulator.swift:65-197` and replace references with
`BattleMoveCatalog.shared.statChanges[...]` etc.

**Watch out for:** the `protectFamily` set is also used implicitly in
multi-turn move tracking. Make sure call sites grep cleanly before deleting.

---

### Priority 3 — Externalize the type chart

**Why:** `damageCalculator.swift:13-35` hardcodes the 18 types and the
effectiveness matrix. Stable in practice but inconsistent with the rest
of the data-driven design. Also useful if you ever want a fan-game mode.

**Create `type_chart.json`:**

```json
{
  "types": ["Normal", "Fire", "Water", "Electric", "Grass", "Ice", "Fighting",
            "Poison", "Ground", "Flying", "Psychic", "Bug", "Rock", "Ghost",
            "Dragon", "Dark", "Steel", "Fairy"],
  "effectiveness": {
    "Normal": { "Rock": 0.5, "Ghost": 0, "Steel": 0.5 },
    "Fire":   { "Fire": 0.5, "Water": 0.5, "Grass": 2.0, "Ice": 2.0,
                "Bug": 2.0, "Rock": 0.5, "Dragon": 0.5, "Steel": 2.0 }
  }
}
```

(only non-1.0 multipliers need entries — keeps the file readable)

**Create `TypeChart.shared`** with `allTypes: [String]` and
`multiplier(attacker:defender:) -> Double` accessors. Replace direct
dictionary lookups in `damageCalculator.swift`.

---

### Priority 4 — Externalize Mega Forms

**Why:** Today's hardcoded list in `MegaForms.swift:52-342` is fine for
"Mega is stable", but the user's stated goal is *adding new megas should be
a JSON edit*. Migration is mechanical.

**Create `mega_forms.json`:**

```json
{
  "forms": [
    {
      "species_key": "venusaur",
      "display_name": "Mega Venusaur",
      "stone": "Venusaurite",
      "requires_move": null,
      "type1": "Grass",
      "type2": "Poison",
      "base_stats": { "hp": 80, "atk": 100, "def": 123, "spAtk": 122, "spDef": 120, "speed": 80 },
      "ability": "Thick Fat"
    },
    {
      "species_key": "rayquaza",
      "display_name": "Mega Rayquaza",
      "stone": null,
      "requires_move": "dragonascent",
      "...": "..."
    }
  ]
}
```

**Keep the Swift `MegaForm` struct** — it stays type-safe. Just change
`static let all` to load from JSON via a `MegaForms.load()` initializer
(or lazy static), cached.

**Watch out for:**

- `HeldItem.isMegaStone` queries `MegaForms.all.contains { $0.stone == self }`
  — that contract still holds, but `HeldItem` still has to enumerate every
  mega stone as an enum case (for the held item picker). That's the next
  item.
- Name normalization: `MegaForm.form(forSpecies:...)` calls
  `BattleSimSeed.normalize()` — preserve that normalization in the loader.

---

### Priority 5 — Externalize Held Items (optional, lower urgency)

**Why:** Same logic as megas. Adding a new gen's items shouldn't require
editing a Swift enum.

This is the **highest-friction migration** because `HeldItem` is a
`String`-rawValue enum used everywhere (`SavedSpread.itemRawValue`,
damage calc bonuses, `typeBoostingItemMap`, `typeResistBerryMap`).

Two viable approaches:

- **A. Replace enum with a struct backed by JSON** — drops compile-time
  exhaustiveness checks; gains data-driven additions. Type-boosting and
  resist-berry maps move into the same JSON. Cleanest long-term.
- **B. Keep the enum, but generate it** — write a build-time codegen step
  that reads `held_items.json` and emits the Swift enum. Preserves type
  safety; adds build complexity.

Recommend approach A *only if* you actually add items often. Otherwise
defer indefinitely — the current enum works.

---

### Priority 6 — Externalize Champions-specific move lists

**Why:** Consistency. `03_ChampionsValidator.swift:169-179` hardcodes setup
moves and choice items with a comment defending it. That defense is weaker
once Tera ships (Tera Blast interacts with setup moves) or once a future
regulation legalizes more choice items.

**Add to `champions-m-a.json`:**

```json
"legal_choice_items": ["Choice Scarf"],
"recognized_setup_moves": [
  "Swords Dance", "Dragon Dance", "Nasty Plot", "Calm Mind", ...
]
```

Read in the validator's init instead of hardcoding.

---

### Priority 7 — Gimmick state on `SavedSpread`

**Why:** Even with flags wired up, there's nowhere to store a Tera type or
Dynamax level. The model has to grow before Tera UI can be added.

**`PokemonStatsModels.swift` — extend `SavedSpread`:**

```swift
var teraType: String?         // nil if not Tera'd or regulation forbids it
var dynamaxLevel: Int?        // 0-10, nil for regulations without Dynamax
var zMoveSlot: Int?           // index 0-3 into moves, nil otherwise
```

Schema migration needed. Optional fields = additive, low risk.

Battle systems then read `rules.tera_allowed && spread.teraType != nil`
before activating.

---

## 3. Suggested Order

1. **P1 — wire rules JSON end-to-end.** Smallest change, biggest payoff.
   Catches the existing drift bug (66/32 in two places) and unblocks every
   future regulation.
2. **P4 — Mega forms JSON.** User's explicit ask. Mechanical.
3. **P7 — `SavedSpread` gimmick fields.** Prereq for Tera/Dynamax UI.
4. **P2 — battle move tables.** Biggest file, but high value before adding
   Gen 10 moves or Tera Blast.
5. **P3 — type chart.** Easy, low risk.
6. **P6 — setup moves into regulation JSON.** Consistency win.
7. **P5 — held items.** Defer unless item churn picks up.

---

## 4. Litmus Test: "Add Regulation M-B with Tera on"

After P1 + P4 + P7, adding a hypothetical Regulation M-B with Tera enabled
should look like this:

1. Drop `champions-m-b.json` (with `tera_allowed: true` + updated whitelist).
2. Drop `champions-m-b-learnsets.json`.
3. Drop `mega_forms.json` updates if any new megas were legalized.
4. In `ChampionsRegulation.swift`: add `case mB = "m-b"`, bump
   `current = .mB`.
5. Build & ship.

No edits to `MegaForms.swift`. No edits to validator constants. No edits
to `BattleSimulator.swift` (after P2). No edits to UI gimmick gates.

That's the bar.

---

## 5. Out of Scope (for now)

- The `PokemonStatsModels.PKMNStats` model — base stats live in SwiftData,
  populated from PokeAPI. No action needed; new species arrive via the
  next sync.
- ML model assets (`pokii_battler.safetensors`, `feature_config.json`,
  vocabs) — already external and versioned together.
- Encounter/RNG generators in `Core/Gen3/` — out of scope for the
  competitive-data compartmentalization question.
