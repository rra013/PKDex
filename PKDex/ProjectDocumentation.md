# PKDex — Project Documentation

PKDex is a SwiftUI + SwiftData iOS app that serves as a Pokemon reference tool. It has two main features: a **Pokedex browser** with generation-based filtering and web detail views, and a **competitive damage calculator** with full EV/IV/nature/ability/item support.

---

## Architecture Overview

```
PKDexApp.swift          App entry point, SwiftData container, startup sync
    |
ContentView.swift       TabView: Pokedex tab + Damage Calc tab
    |
    +-- Pokedex Tab
    |     pokedb.swift              PKMN model (national dex entries with Serebii links)
    |     dexitCheck89.swift        Gen8Pokemon / Gen9Pokemon models + PokeAPIResponse DTO
    |     champsDex.swift           Champions roster set (hardcoded list)
    |     populateDexitCheck.swift  PokedexDataHandler (legacy sync, unused)
    |     pokedbPopulator.swift     PokeSyncManager (REST-based Pokedex sync)
    |
    +-- Damage Calc Tab
          damageCalculator.swift    Damage engine, CalcSide model, DamageCalcVM, all views
          PokemonStatsModels.swift  PKMNStats, MoveData, Nature, SavedSpread, weather,
                                    items, abilities, stat formulas
          PokeAPIGraphQL.swift      GraphQL fetcher + CalcDataSyncManager
```

---

## File-by-File Reference

### PKDexApp.swift

**Purpose:** App entry point and data bootstrapping.

| Component | Description |
|-----------|-------------|
| `PokedexApp` | `@main` App struct. Creates the `ModelContainer` with all SwiftData models. |
| `ModelContainer` init | Attempts normal init; on migration failure, deletes the store file and retries. Clears UserDefaults sync flags so data re-downloads. |
| `performStartupSync()` | Runs on launch via `.task`. Two independent sync passes: Pokedex (REST) and Calc data (GraphQL). Each is gated by a UserDefaults flag (`hasCompletedInitialSync`, `hasCompletedCalcSyncV2`). |

**SwiftData schema includes:** `PKMN`, `Gen8Pokemon`, `Gen9Pokemon`, `PKMNStats`, `MoveData`, `SavedSpread`

---

### ContentView.swift

**Purpose:** Root view with tab navigation and the Pokedex browser.

| Component | Description |
|-----------|-------------|
| `ContentView` | `TabView` with two tabs: Pokedex and Damage Calc. |
| `PokedexTab` | Navigation stack with search, generation filter menu, and emergency reset button. |
| `PokedexFilter` | Enum of all generations + "Champions". Each case maps to a `PKMN` link property. |
| `FilteredList` | Uses `@Query` with a `Predicate` built from the selected filter. Checks if the corresponding gen link is non-nil. Search filters by name or dex number. |
| `PokemonRow` | Simple row: dex number + name. |
| `PokemonDetailView` | Shows the generation label, a link, and an embedded `WKWebView` pointing to the Serebii page. |
| `PokemonWebView` | Platform-adaptive `WKWebView` wrapper (iOS: `UIViewRepresentable`, macOS: `NSViewRepresentable`). |

**Emergency Reset:** Deletes all model types from the context and clears UserDefaults sync flags. User must restart the app to re-sync.

---

### pokedb.swift

**Purpose:** Core Pokedex data model.

| Component | Description |
|-----------|-------------|
| `PKMN` | SwiftData `@Model`. Stores a Pokemon's name, national dex number (unique key), and optional Serebii URL strings for each generation (Gen I through Gen IX) plus Champions. |

Each generation link is `nil` if the Pokemon doesn't exist in that generation. Links are constructed during sync using Serebii URL patterns.

---

### dexitCheck89.swift

**Purpose:** Auxiliary models for Gen 8/9 availability checking.

| Component | Description |
|-----------|-------------|
| `Gen8Pokemon` | SwiftData model with just a unique `name`. Populated from PokeAPI regional dex endpoints (Galar, Armor, Tundra). |
| `Gen9Pokemon` | Same as above for Gen 9 (Paldea, Kitakami, Blueberry). |
| `PokeAPIResponse` | Codable DTO for the `/pokedex/{id}/` REST endpoint. Used by `PokedexDataHandler`. |

These models exist solely to determine which Pokemon appear in Gen 8/9 dexes, since those generations don't include all national dex Pokemon.

---

### champsDex.swift

**Purpose:** Hardcoded roster for Pokemon Champions (the game).

| Component | Description |
|-----------|-------------|
| `championsRoster` | A `Set<String>` of ~130 Pokemon names available in Pokemon Champions. Organized by generation in comments. Includes regional forms (Alolan, Galarian, Hisuian). |

This set is duplicated in `pokedbPopulator.swift` as `PokeSyncManager.championsRoster`. Both are used during sync to determine which Pokemon get a `champsLink`.

---

### populateDexitCheck.swift

**Purpose:** Legacy sync handler (appears to be unused in current flow).

| Component | Description |
|-----------|-------------|
| `PokedexDataHandler` | `@MainActor` class that fetches Gen 8/9 regional dex data from the REST API and inserts `Gen8Pokemon`/`Gen9Pokemon` records. |

**Note:** This functionality is now handled by `PokeSyncManager` in `pokedbPopulator.swift`, which fetches Gen 8/9 names as part of the unified Pokedex sync. This file may be dead code.

---

### pokedbPopulator.swift

**Purpose:** Primary Pokedex sync manager (REST API).

| Component | Description |
|-----------|-------------|
| `PokeSyncManager` | `@ModelActor` that orchestrates the full Pokedex sync. |
| `refreshPokedex()` | 1) Fetches Gen 8/9 names from regional dex endpoints. 2) Fetches the national dex. 3) Wipes existing `PKMN`, `Gen8Pokemon`, `Gen9Pokemon` data. 4) Inserts all Pokemon with generation-appropriate Serebii links. |
| `championsRoster` | Static set (duplicate of `champsDex.swift`) used to assign `champsLink` during sync. |
| DTOs | `PokedexResponseDTO`, `PokemonEntryDTO`, `PokemonSpeciesDTO` — Codable structs for the REST API response. |

**Link construction:** Gen I-VII use the dex number format (`/pokedex-xy/025.shtml`). Gen VIII-IX use the name format (`/pokedex-swsh/pikachu/`). Champions uses `/pokedex-champions/`.

---

### PokeAPIGraphQL.swift

**Purpose:** GraphQL data fetcher for the damage calculator (Pokemon stats, moves, learnsets).

| Component | Description |
|-----------|-------------|
| `PokeGraphQLFetcher` | Actor that sends GraphQL queries to `beta.pokeapi.co/graphql/v1beta`. |
| `fetchAllPokemon()` | Fetches all default-form Pokemon with types, base stats, abilities, and full learnsets (all damage classes including status). |
| `fetchAllForms()` | Fetches all alternate forms (Megas, regionals, etc.) with types, stats, abilities. No learnsets (inherited from base species). |
| `fetchAllMoves()` | Fetches all moves with type, damage class, power, accuracy, PP, priority, and meta (multi-hit, drain, healing, crit rate). Includes physical, special, and status moves. |
| `CalcDataSyncManager` | `@ModelActor` that coordinates the sync. Fetches all three datasets in parallel, then: 1) Clears existing `PKMNStats` and `MoveData`. 2) Inserts default Pokemon. 3) Inserts non-cosmetic alternate forms (skips forms with identical stats/types to base). 4) Inserts all moves. |
| Helper functions | `formatPokemonName`, `parseStats`, `parseTypes`, `parseAbilities` — convert GraphQL DTOs to model-friendly values. |

**Cosmetic form filtering:** Forms where both stats and types match the base species are skipped (e.g., Pikachu costumes). Forms with different stats or types are included (e.g., Alolan forms, Megas).

**Learnset inheritance:** Alternate forms have no learnset data in PokeAPI. They inherit their base species' learnset via `speciesMap`.

---

### PokemonStatsModels.swift

**Purpose:** All data models and game mechanics for the damage calculator.

#### Data Models

| Component | Description |
|-----------|-------------|
| `PKMNStats` | SwiftData model. Stores a Pokemon's ID, species ID, name, form name, types, all 6 base stats, up to 3 abilities, and learnable move IDs. |
| `MoveData` | SwiftData model. Stores a move's ID, name, type, damage class (physical/special/status), power, accuracy, PP, priority, multi-hit range, drain/healing %, crit rate, and contact flag. |
| `Nature` | Value type with ID, name, boosted stat, lowered stat. Provides `modifier(for:)` returning 1.1/0.9/1.0. |
| `allNatures` | Array of all 25 natures (5 neutral + 20 with boosts/drops). |
| `SavedSpread` | SwiftData model. Persists a full Pokemon build: name, Pokemon ID, ability, item, nature, level, all EVs/IVs, Champions mode flag, and 4 move IDs. Timestamped for sort order. |

#### Stat Formulas

| Function | Description |
|----------|-------------|
| `calcHP(base:iv:ev:level:)` | Gen III+ HP formula. Returns 1 for Shedinja (base 1). |
| `calcStat(base:iv:ev:level:natureMod:)` | Gen III+ stat formula for Atk/Def/SpAtk/SpDef/Speed. |
| `statStageMultiplier(stage:)` | Converts -6..+6 stage to multiplier (e.g., +1 = 1.5x, -1 = 0.67x). |

#### EV System

| Constant/Function | Description |
|-------------------|-------------|
| `maxEVPerStat` (252) | Standard per-stat EV cap. |
| `maxTotalEVs` (510) | Standard total EV cap. |
| `championsMaxEVPerStat` (32) | Champions mode per-stat cap. |
| `championsMaxTotalEVs` (66) | Champions mode total cap. |
| `championsEVToMain(_:)` | Converts Champions-scale EV (0-32) to main-series value for stat formulas. |

#### Held Items

| Component | Description |
|-----------|-------------|
| `HeldItem` | Enum of competitively relevant items: Choice Band/Specs, Life Orb, Expert Belt, type-boost, Assault Vest, Eviolite, Light Ball, Thick Club, Metronome. |
| `ItemModResult` | Struct with multipliers for Atk, SpAtk, Def, SpDef, and a final damage multiplier. |
| `computeItemModifiers(...)` | Returns an `ItemModResult` based on attacker and defender items. |

#### Weather

| Component | Description |
|-----------|-------------|
| `WeatherCondition` | Enum: None, Sun, Rain, Sand, Snow. |
| `moveDamageMultiplier(moveType:)` | Sun boosts Fire/weakens Water. Rain boosts Water/weakens Fire. |
| `sandSpDefMultiplier(defenderTypes:)` | Rock types get 1.5x SpDef in Sand. |
| `snowDefMultiplier(defenderTypes:)` | Ice types get 1.5x Def in Snow. |

#### Abilities

| Component | Description |
|-----------|-------------|
| `DamageAbility` | Enum listing all implemented abilities (used for documentation/reference, not directly in the calc switch). |
| `AbilityModResult` | Struct with Atk/Def/power multipliers, optional STAB/crit/type-effectiveness overrides, and a final multiplier. |
| `computeAbilityModifiers(...)` | Giant switch on attacker and defender ability strings. See [AbilityReference.md](AbilityReference.md) for full details. |

---

### damageCalculator.swift

**Purpose:** The damage calculation engine, view model, and all UI for the Damage Calc tab.

#### Damage Engine

| Component | Description |
|-----------|-------------|
| `typeEffectivenessChart` | 18x18 type matchup dictionary. Only stores non-1.0 values. |
| `pokeFloor(_:_:)` | `floor(value * modifier)` — matches the game's integer truncation. |
| `calcDamageRange(...)` | Gen V+ damage formula. Applies pre-random modifiers (multi-target, Parental Bond, weather, Glaive Rush, crit), forks at the random roll (85-100), then applies post-random modifiers (STAB, type effectiveness, burn, ability final mult, Z-move bypass). Returns (min, max) damage. |
| `computeTypeEffectiveness(moveType:defenderTypes:)` | Multiplies matchups for each defender type. |

#### CalcSide Model

| Property / Method | Description |
|-------------------|-------------|
| `pokemon`, `searchText` | Selected Pokemon and search state. |
| `nature`, `level` | Nature and level (default: Adamant, 50). |
| `selectedAbility`, `heldItem`, `atFullHP` | Ability, item, and full-HP flag (for Multiscale, pinch abilities). |
| `moves[4]`, `moveSearchTexts[4]`, `filterLegalMoves` | 4 move slots with per-slot search and legal-moves-only filter. |
| `championsMode` | When true, EVs use 0-32 scale and IVs lock to 31. |
| `evHP..evSpeed`, `ivHP..ivSpeed` | Raw EV/IV storage. |
| `atkStage..speedStage` | Stat stages (-6 to +6). |
| `hp`, `atk`, `def`, `spAtk`, `spDef`, `speed` | Computed final stats (base + IV + EV + nature + stage). |
| `toSavedSpread(name:)` | Serializes the full build (including 4 move IDs) to a `SavedSpread`. |
| `loadSpread(_:allPokemon:allMoves:)` | Restores a saved build, looking up Pokemon and moves by ID. |
| `setChampionsMode(_:)` | Converts EVs between scales when toggling Champions mode. |
| `maxAllowedEV(excluding:)` | Dynamic per-stat cap that respects the total EV budget. |
| `cappedEVBinding(_:)` | Creates a `Binding<Int>` that enforces the EV cap. |

#### DamageCalcVM

| Property / Method | Description |
|-------------------|-------------|
| `side1`, `side2` | Two symmetric `CalcSide` instances (no attacker/defender distinction). |
| `crit`, `burn`, `multi`, `parentalBond`, `glaiveRush`, `zMoveBypass` | Global modifier toggles. |
| `weather`, `miscMultiplier` | Weather condition and a freeform multiplier. |
| `side1Results`, `side2Results` | Computed arrays of `MoveResult` — damage for each of side1's moves vs side2, and vice versa. |
| `computeSingleResult(move:attacker:defender:)` | Calculates one move's full damage range including items, abilities, weather, and all modifiers. Returns a `MoveResult` with min/max damage, percentages, KO count, effectiveness, and STAB flag. |
| `filteredMoves(for:slotIndex:allMoves:allPokemon:)` | Searches moves by name, optionally filtered to the side's Pokemon learnset. Falls back to base species learnset for alternate forms. |

#### MoveResult

| Field | Description |
|-------|-------------|
| `move` | The `MoveData` reference. |
| `damageMin`, `damageMax` | Raw damage numbers (post-item-multiplier). |
| `minPercent`, `maxPercent` | Damage as % of defender HP (capped at 999%). |
| `hitsToKO` | String like "1HKO", "2-3HKO", or "--". |
| `effectiveness` | Final type effectiveness value (after ability overrides). |
| `effectivenessLabel`, `effectivenessColor` | Display string ("2x", "Immune", etc.) and color. |
| `isSTAB` | Whether the attacker gets STAB on this move. |

#### Views

| View | Description |
|------|-------------|
| `DamageCalculatorView` | Root view. ScrollView with Result card, two Side cards, and Modifiers card. Shows a syncing placeholder if no Pokemon data. |
| `ResultCard` | Shows modifier badges (weather, abilities, items) and two `DirectionResultsView` sections (side1->side2 and side2->side1). |
| `DirectionResultsView` | Header ("Pikachu -> Charizard") plus a `MoveResultRow` for each selected move. Shows "No moves selected" placeholder. |
| `MoveResultRow` | Per-move result: name, type badge, damage class badge, STAB indicator, effectiveness pill, KO pill, damage range text, and percentage bar. Status moves show "Status move -- no damage" instead of numbers. |
| `SideCard` | Full Pokemon configuration card: search/select Pokemon, 4 move slots, save/load spread, ability/item pickers, level/nature, Champions mode toggle, EV/IV sliders, stat stages, final stats display. |
| `MoveSlotsSection` | 4 `MoveSlotView` instances with a legal-only toggle. |
| `MoveSlotView` | If a move is selected: shows name, type, power, class, and X button. If empty: shows a search field with dropdown results. |
| `ModifiersCard` | Weather picker (segmented), toggle badges for Crit/Burn/Multi-hit/Parental Bond/Glaive Rush/Z-Move Bypass, and a misc multiplier field. |
| `SaveSpreadSheet` | Form sheet for naming and saving the current build. Shows a summary of Pokemon, nature, EVs, IVs, mode, and moves. |
| `LoadSpreadSheet` | List sheet of saved spreads with swipe-to-delete. Shows name, Pokemon, nature, ability, item, and EV summary. |

#### Reusable Components

| View | Description |
|------|-------------|
| `CalcSection` | Card wrapper with title, icon, divider, and shadow. |
| `DamageClassBadge` | "Phys" (orange), "Spec" (indigo), or "Status" (gray) pill. |
| `TypeBadge` | Colored capsule with the type name (e.g., "Fire" on red). |
| `StatMini` | Compact label + bold value column. |
| `InfoBadge` | Small colored capsule for modifier indicators. |
| `PercentageBar` | Gradient bar showing min-max damage range. Green->orange->red. |
| `CappedEVRow` | Slider + text field for EVs, dynamically capped to respect total budget. |
| `EVIVRow` | Slider + text field for IVs with fixed range. |
| `StageRow` | Stepper for stat stages (-6 to +6) with color coding. |
| `ToggleBadge` | Button-style toggle that highlights red when active. |

---

## Data Flow

### Startup Sync

```
App Launch
  |
  +-- hasCompletedInitialSync == false?
  |     -> PokeSyncManager.refreshPokedex()
  |        Fetches national dex + Gen 8/9 regional dexes from REST API
  |        Inserts PKMN records with Serebii links
  |        Inserts Gen8Pokemon / Gen9Pokemon for availability filtering
  |
  +-- hasCompletedCalcSyncV2 == false?
        -> CalcDataSyncManager.syncCalcData()
           Fetches Pokemon + forms + moves from GraphQL API (in parallel)
           Inserts PKMNStats (with learnsets) and MoveData
```

### Damage Calculation Flow

```
User selects Pokemon + moves on both sides
  |
  v
DamageCalcVM.side1Results / side2Results (computed properties)
  |
  v
For each selected move:
  computeSingleResult(move, attacker, defender)
    |
    +-- computeTypeEffectiveness(moveType, defenderTypes)
    +-- computeItemModifiers(attackerItem, defenderItem, ...)
    +-- computeAbilityModifiers(attackerAbility, defenderAbility, ...)
    +-- Weather multipliers (move damage, Sand SpDef, Snow Def)
    +-- Effective Atk/Def (base stat * stage * item)
    +-- calcDamageRange(level, power, atk, def, modifiers...)
    +-- Apply item damage mult (Life Orb, Expert Belt, etc.)
    |
    v
  MoveResult { damageMin, damageMax, minPercent, maxPercent, hitsToKO, ... }
```

---

## SwiftData Models Summary

| Model | Purpose | Unique Key |
|-------|---------|------------|
| `PKMN` | National dex entry with per-gen Serebii links | `nationalPokedexNumber` |
| `Gen8Pokemon` | Gen 8 availability flag | `name` |
| `Gen9Pokemon` | Gen 9 availability flag | `name` |
| `PKMNStats` | Pokemon base stats, types, abilities, learnset | `id` |
| `MoveData` | Move stats (power, type, class, etc.) | `id` |
| `SavedSpread` | Saved Pokemon build (EVs, IVs, nature, moves) | None (timestamped) |

---

## Known Simplifications & Limitations

1. **Move-specific ability flags** — Iron Fist, Strong Jaw, Mega Launcher, Punk Rock, Reckless, Sheer Force always apply their boost when selected, because the app lacks move flag data (punching, biting, sound, etc.).

2. **Type-changing abilities** (Aerilate, Pixilate, Protean, Normalize) — The power boost is applied, but the user must manually account for the type change when interpreting results.

3. **Conditional abilities** (Analytic, Stakeout, Supreme Overlord, Marvel Scale) — Always apply when selected. The user is responsible for understanding when they'd actually activate in battle.

4. **Terrain** — Not implemented. Electric/Grassy/Psychic/Misty Terrain multipliers are not in the calculator.

5. **Stat stage abilities** (Intimidate, Download, Beast Boost, etc.) — Not implemented as abilities. The user can manually adjust stat stages to account for them.

6. **Champions roster** — Hardcoded in two places (`champsDex.swift` and `PokeSyncManager`). These must be updated manually when the roster changes.

7. **`makesContact` flag** — Always defaults to `false` since it's not fetched from PokeAPI. This affects Tough Claws and Fluffy calculations.

8. **populateDexitCheck.swift** — `PokedexDataHandler` appears to be legacy dead code, superseded by `PokeSyncManager`.
