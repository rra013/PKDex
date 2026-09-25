# PK Reference (PKDex)

**PK Reference** is a SwiftUI + SwiftData app for competitive Pokémon players.
It is built mainly around **Pokémon Champions**, and it also covers the whole
National Pokédex and the classic RNG-manipulation games. Everything lives in
one app:

- a Pokédex, a move index and an ability index
- a damage calculator ported line by line from Smogon's `@smogon/calc`, with an EV solver
- set and team builders with Showdown paste import and export
- a speed tier checker
- a singles and doubles battle simulator with an on-device AI opponent
- a full suite of Gen 3–5 RNG tools, ported from PokéFinder and EonTimer
- tournament results and team sheets from Limitless

The Xcode project and target are named `PKDex`, and the app's display name is
**PK Reference** (bundle ID `yukisoft.PKReference`).

> PK Reference is an unofficial, fan-made tool. It is not affiliated with,
> endorsed by, or associated with Nintendo, The Pokémon Company, Creatures Inc.,
> or GAME FREAK. Pokémon and all related names are trademarks of their
> respective owners.

---

## Contents

1. [Features at a glance](#features-at-a-glance)
2. [The tabs in detail](#the-tabs-in-detail)
3. [Pokémon Champions support](#pokémon-champions-support)
4. [On-device machine learning](#on-device-machine-learning)
5. [Architecture](#architecture)
6. [Building, running and testing](#building-running-and-testing)
7. [Repository layout](#repository-layout)
8. [Data sources and credits](#data-sources-and-credits)
9. [License](#license)

---

## Features at a glance

| Tab | What it does |
|---|---|
| **Mon Index** | National Pokédex filtered by generation or by the current Champions roster. Champions entries open a structured page with stats, abilities, type chart, movepool, Mega and alternate forms, and comparison. |
| **Move Index** | Every move with its type, category and power. Tapping a move opens its Serebii Attackdex page. |
| **Ability Index** | Every ability. Tapping one opens its Serebii Abilitydex page. |
| **Damage Calc** | Two-sided calculator using a Swift port of Smogon's calc for Champions, with a legacy engine as fallback. Includes field conditions, Mega Evolution, Showdown paste import and export, saved spreads, and an **EV solver**. |
| **Sets** | Library of saved spreads, with a set editor and an on-device **set predictor**. |
| **Teams** | Six-slot teams built from saved sets, with type-coverage analysis and whole-team Showdown paste import. |
| **Speed Tiers** | Your Pokémon's final Speed, after every modifier, ranked against the roster. |
| **Battle Sim** | Singles and doubles battle engine using your saved teams, with Mega Evolution and an on-device AI that can play either side. |
| **RNG Tools** | Timer, seed finder, wild and static encounters, eggs, TID/SID, GameCube (Colosseum/XD), IV calculator, IV→PID and Hidden Power, for Gen 3–5, plus Sword/Shield raid dens. |
| **Tournaments** | Tournaments, standings and team sheets from Limitless, with one-tap import of any team. |
| **Team Search** | Describe a team idea in plain words and see the popular tournament teams that match it, grouped into compositions. |
| **Settings** | Appearance, accent color, visible tabs, default tab and generation, active Champions regulation, data management, and acknowledgements and licenses. |

Every tab except Settings can be hidden or made the default tab. On iPad and
wide iPhone layouts, the list-based tabs switch to a split view with the list
and the detail side by side.

---

## The tabs in detail

### Mon Index

- **Generation filter:** All, Gen I–IX, or **Champions**. Each generation's
  list comes from the National Pokédex and PokeAPI's regional dexes, and each
  entry links to the matching Serebii page, shown in an in-app web view.
- **Champions filters:** narrow the Champions roster by type, ability or move.
  The pickers are built from the active regulation's learnset data, so they
  always match the current format.
- **Champions detail page** (`ChampionsPokemonDetailView`): parsed data
  rather than a web page. It has:
  - base stats, abilities and a defensive type chart
  - a searchable movepool
  - a form picker for base, Mega and alternate forms
  - "Compare With…", for comparing two Pokémon side by side
  - a pinned **Build a Set** button that opens the Set Builder

### Move Index and Ability Index

Searchable lists of every move and ability, synced from PokeAPI. Move rows
show type, category and power. Tapping an entry opens its Serebii page in an
in-app web view: the Attackdex for the selected generation (including the
Champions Attackdex) or the Abilitydex.

### Damage Calc

The calculator has two symmetric sides, so either one can attack. You can set
each side's:

- **Pokémon:** species, level and nature, plus ability and held item.
- **Investment:** EVs and IVs. In **Champions mode**, EVs become stat points
  (0–32 per stat, 66 total) and IVs are fixed at 31.
- **State:** stat stages, current HP %, status, and Mega Evolution.
- **Moves:** four move slots, optionally limited to the Pokémon's legal moves.

Field and side conditions include weather, terrain, Reflect, Light Screen,
Aurora Veil, Helping Hand, Friend Guard, Protect, Tailwind, Stealth Rock,
critical hits, spread damage and a free-form multiplier.

**Engines.** There are two, behind one entry point (`CalcEngine.evaluate`):

1. **The Champions engine** is a faithful Swift port of Smogon's
   [`@smogon/calc`](https://github.com/smogon/damage-calc). It follows the
   upstream code line by line, including modifier order and rounding, and
   runs on data generated from the calc's own tables. The whole calc is
   ported, including Z-Moves, Dynamax and Tera, but only what Champions uses
   is switched on. See [`PKDex/ShowdownPort-NOTES.md`](PKDex/ShowdownPort-NOTES.md).
2. **The legacy engine** implements the Gen V+ damage formula directly. It
   handles anything the port can't represent, such as a side that isn't in
   Champions mode. [`PKDex/AbilityReference.md`](PKDex/AbilityReference.md)
   lists which abilities it models.

**Showdown paste import and export.** Paste any Showdown set to load it into
a side. The importer shows exactly what did and didn't match, and converts
between mainline EVs and Champions stat points. You can export the current
side as paste text.

**EV solver.** It answers three questions for a move row, and can write the
answer back to the calc:

- the cheapest HP and defensive investment for the defender to survive the hit
- the cheapest offensive investment for the attacker to OHKO
- the Speed each side needs to outspeed the other

It checks every possible value rather than searching, so abilities and
berries that make damage non-monotonic can't mislead it. Two-hit goals
("survive two hits", "guaranteed 2HKO") are played out in the battle
simulator, so effects between the hits count: Sitrus Berry, Multiscale,
Stamina, Leftovers and doubles spread damage.

### Sets

A library of saved spreads (`SavedSpread`). Each has a species, ability,
item, nature, level, EVs/IVs (mainline or Champions scale) and four moves.
The editor can limit moves to legal ones. **Predict Set** runs a small
on-device model: you give it a species and a style (Competitive, Defensive,
Offensive, Setup, Slow Attacker or Trick Room Setter), and it fills in a
complete, legal Champions set.

### Teams

Teams of up to six saved sets. Each team slot refers to a saved set by name,
so edits to the set show up in every team that uses it. The team page shows
**type coverage**: STAB and super-effective coverage across the whole team.
**Import Paste** turns a complete Showdown team paste into a team plus one
saved set per Pokémon, all with unique names.

### Speed Tiers

Enter a Pokémon, or load a saved set, and set its modifiers: nature, Speed
EVs or stat points, IV, stage, item, ability or status, level and Mega
Evolution. The tab then shows where its final Speed falls against a benchmark
list. That list can be limited to the Champions roster, with or without Mega
Evolutions. Speed values match the Showdown port for every combination of
modifiers.

### Battle Sim

A turn-based battle engine with these features:

- **Formats:** singles or doubles, with VGC-style team preview (bring 3 in
  singles, 4 in doubles).
- **Teams and legality:** battles use your saved teams, with optional
  Champions regulation legality.
- **Mechanics:** Mega Evolution, abilities and items, weather, terrain,
  hazards and screens, spread moves, Disable, Encore, Pressure and more.
- **AI opponent:** the on-device **Pokii** doubles model can control one side
  or both. With both sides under AI control, the battle plays itself.
- **Coverage notes:** the engine lists anything on your team that it doesn't
  fully model yet.
- **Demo teams:** a fresh install adds a few sample teams, so you can try a
  battle straight away.

### RNG Tools

A full RNG-manipulation toolkit with 11 sub-tabs. Its algorithms run on
PokéFinder's C++ core, which is compiled into the app and called through an
Objective-C++ bridge (`PFBridge.mm`).

| Sub-tab | What it does |
|---|---|
| **Timer** | Precise multi-phase timers for Gen 3/4/5 and custom setups, with calibration and console-specific frame rates, ported from EonTimer. |
| **Finder** | Seed searching and generators, including Method 1 / 1R / 2 / 4, XD/Colo, Channel and Cute Charm. Also has Gen 4 Elm/Irwin calls, Chatot pitches and Pokétch coin flips, and Gen 5 keypresses and SHA-1 seeds. |
| **Routes** | Wild encounter tables by game and location, with slot rates and levels. |
| **Statics** | Static and gift encounters. |
| **Eggs** | Egg generation with parents, Everstone, Destiny Knot, Power items and compatibility. |
| **TID/SID** | Trainer ID manipulation, and seed-to-time for DS clocks. |
| **GameCube** | Colosseum and XD: shadow templates, Poké Spot, Jirachi pattern and seed finding. |
| **IV Calc** | IVs from stats, with characteristic and Hidden Power filtering. |
| **IV→PID** | Reverses IVs to PIDs using LCRNG meet-in-the-middle techniques. |
| **HP** | Hidden Power type and power. |
| **Credits** | The sources the tools are ported from. |

Covered games include Ruby, Sapphire, Emerald, FireRed, LeafGreen, Colosseum,
XD, Diamond, Pearl, Platinum, HeartGold, SoulSilver, Black, White, Black 2
and White 2, plus Sword and Shield Max Raid dens. Profiles store console
details such as MAC address and DS type.

### Tournaments

Browse recent Limitless tournaments by game and format, including Champions
regulations M-A, M-B and M-C, and filter by minimum player count. Open an
event to see:

- **Standings,** filterable to the top 4, 8, 16 or 32. Players who dropped
  are listed after the ranked players.
- **Team sheets:** each player's six Pokémon with items, abilities and moves.
- **Saving:** save one Pokémon, or **Save Full Team** to create a team plus
  its saved sets.

Limitless sends species, item, ability, moves and nature, but no stat points.
Turning on **Predict Stats & Nature** lets an on-device model fill in the
stat points, and the nature too when an event didn't record one.

Imports go through a shared importer (`LimitlessTeamImport.swift`), which maps
Limitless names to Pokédex entries: "Hisuian Arcanine" becomes Arcanine-Hisui,
"Indeedee ♀" becomes Indeedee-Female, and "Maushold" becomes its default
form. If any Pokémon or move can't be matched, nothing is saved, and an alert
lists every name that failed.

### Team Search

Describe the team you're thinking of, such as *"Trick Room with Mega
Gardevoir, no Incineroar"*, and Team Search finds the teams that match in
recent Limitless events for the chosen Champions regulation.

- **What it understands:** Pokémon (with nicknames such as "Chomp", regional
  and gendered forms such as "Hisuian Arcanine" or "Indeedee ♀", and Megas
  such as "Mega Charizard Y" or "Charizardite Y"), moves such as "Fake Out"
  and "Follow Me", and team styles: Trick Room, Tailwind, sun, rain, sand,
  snow, the four terrains, redirection and Perish Trap. "No", "without" and
  similar words exclude things.
- **Chips:** what it understood shows as chips under the search field. Tap a
  chip to switch it between include and exclude, or tap × to remove it.
  Typo fixes ("incinaroar → Incineroar") and words it didn't understand show
  too.
- **Results:** matching teams are grouped into compositions. Teams sharing
  five of their six Pokémon count as variants of the same composition.
  Compositions are ranked by how well their teams placed and how recent the
  events were. Each shows its style tags, team and event counts, and best
  finish. With an empty search, the tab shows the most popular compositions.
- **Details:** a composition lists why it matched, its variants and its
  teams. Each team opens the same team sheet as the Tournaments tab, with
  the same save buttons.
- **Partial matches:** when fewer than 10 teams match everything, teams
  missing one of the requested Pokémon are shown too, marked "Partial match".
- **Data:** each event's results are downloaded once and cached; pull to
  refresh for new events. If Limitless is limiting requests, the app waits
  and retries. Settings → Clear Team Search Data frees the cache.

### Settings

- **Appearance:** system, light or dark mode, and one of 11 accent colors.
- **Tab bar:** choose which tabs are visible, and which one the app opens to.
- **Default generation:** the Mon Index list the app opens with.
- **Champions regulation:** the active format. New installs default to the
  newest regulation.
- **Data management:** re-download the Pokémon and move data, clear Team
  Search's cached tournament data, or reset all data.
- **Acknowledgements & Licenses:** the data sources and open-source
  components the app uses, with each license's full text.

---

## Pokémon Champions support

Each Champions ranked regulation is described by two bundled JSON files:

| Regulation | Legal period | Species |
|---|---|---|
| M-A | 2026-04-08 → 2026-06-16 | 186 |
| M-B | 2026-06-17 → 2026-09-02 | 208 |
| M-C | 2026-09-09 → 2026-12-02 | 231 |

- `champions-<id>.json`: format rules (stat point caps, species clause, which
  gimmicks are allowed) and the species, item, berry and Mega Stone lists.
- `champions-<id>-learnsets.json`: each species' abilities, base stats, legal
  moves, Megas and alternate forms.

`ChampionsRegulation` is the single source of truth. By default it uses the
newest regulation, and the one in use can be changed in Settings. The Mon
Index, set and team builders, validator, battle simulator, set predictor and
Tournaments tab all read from it. Adding a new regulation takes two JSON
files and one enum case; [`tools/README.md`](tools/README.md) walks through
it step by step.

Champions-specific mechanics that are modelled include:

- the 0–32 stat point system with a 66-point total, and IVs fixed at 31
- Champions stat formulas, taken from the Showdown port
- every Mega Evolution in the regulations, including the new Champions Megas

---

## On-device machine learning

All inference runs on the device.

| Model | Files | Used by | Runtime |
|---|---|---|---|
| **Set predictor**: species + style → complete set | `name_qual_weights.npz`, `name_qual_vocab.json` | Sets → Predict Set | `PokiiLite` (Accelerate) |
| **Stat & nature predictor**: species, item, ability and moves → stat points + nature | `stat_nature_model.npz`, `stat_nature_vocab.json` | Tournaments → Predict Stats & Nature | `PokiiLite` |
| **Pokii doubles policy**: battle state → action, and whether to Mega Evolve | `pokii_battler.safetensors`, `feature_config.json` | Battle Sim AI | `PokiiBattler` (Accelerate) |

All three are small multilayer perceptrons (MLPs), bundled with the app and
run in plain Swift on Accelerate. Decoding respects the rules: predicted
abilities and moves are limited to the species' legal options, and stat
points are rebalanced to the 66-point budget. `pokii_parity_samples.json`
lets the tests check the Swift inference against the training outputs.

The set predictor replaced an earlier on-device LLM set builder, which ran a
4-bit "Pokii" model with MLX Swift. That code has been removed; it's still in
the git history.

---

## Architecture

- **UI:** SwiftUI, with split-view layouts for regular width.
- **Persistence:** SwiftData models:
  - `PKMN`: Pokédex entries and Serebii links
  - `Gen8Pokemon` / `Gen9Pokemon`: which Pokémon are in the Gen 8 and 9 regional dexes
  - `PKMNStats`: species, forms, stats, abilities and learnsets
  - `MoveData`: moves
  - `SavedSpread`: saved sets
  - `SavedTeam`: saved teams
- **Data at startup:** on first launch, the app syncs the Pokédex from PokeAPI's
  REST API and the calculator data (species, forms, moves and learnsets) from
  PokeAPI's GraphQL API. Regulation data, Showdown calc data and the ML models
  ship in the app bundle.
- **Concurrency:** the module uses main-actor default isolation. Pure
  computational types, such as the damage port, calc snapshots, EV solver,
  paste parser and tournament data store, are explicitly `nonisolated`, so
  solvers and network work run off the main thread. See
  [`CalcCore-HANDOFF.md`](CalcCore-HANDOFF.md).
- **C++ core:** PokéFinder's generators and searchers live in `PKDex/Core`,
  and `PFBridge.h/.mm` wraps them. `PFBridgeSwift.swift` gives the RNG
  views a Swift interface to them.
- **Networking:** `LimitlessAPIService` (an actor with a short in-memory cache)
  and `TeamCorpusStore` (a disk cache of tournament standings for Team Search,
  which retries after rate limits and server errors).

More internal documentation:
[`PKDex/ProjectDocumentation.md`](PKDex/ProjectDocumentation.md) (an early
file-by-file reference),
[`PKDex/CompartmentalizationPlan.md`](PKDex/CompartmentalizationPlan.md)
(moving game data into JSON), and
[`PKDex/ShowdownPort-NOTES.md`](PKDex/ShowdownPort-NOTES.md).

---

## Building, running and testing

**Requirements:** Xcode 27, with the iOS 26.4 SDK or later. The deployment
target is iOS 26.4, and the device families are iPhone, iPad and Apple
Vision. The project has no Swift package dependencies.

1. Open `PKDex.xcodeproj` and select the **PKDex** scheme.
2. Run on a simulator or a device. The first launch downloads Pokémon and move
   data from PokeAPI, so it needs a network connection; later launches work
   offline, except for Tournaments.

**Tests:** 955 tests written with Swift Testing. They cover the damage engines
and the port, the battle engine by mechanic tier, the EV and two-hit solvers,
speed tiers, paste parsing and import, Champions filters and legality, RNG
tools, ML parity, the tournament import and data store, Team Search's parser
and engine, and the bundled license files. None of them need the network or a
SwiftData store.

```bash
xcodebuild test -project PKDex.xcodeproj -scheme PKDex -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

**Developer tools** (not shipped in the app):

- `tools/gen_mc.py` and `tools/scrape_mc.py` build a new regulation's JSON
  files from Serebii's Champions pages. See [`tools/README.md`](tools/README.md).
- `tools/gen_showdown_data.ts` regenerates
  `PKDex/showdown-champions-data.json` from the vendored `@smogon/calc` data:

  ```bash
  npx tsx tools/gen_showdown_data.ts
  ```

- `tools/vendor/` holds the upstream `damage-calc` and `pokemon-showdown`
  sources that the port and data are based on.

---

## Repository layout

| Path | Contents |
|---|---|
| `PKDex/` | App sources (a synced folder: new files are added to the target automatically) |
| `PKDex/Core/` | PokéFinder's C++ RNG core, plus its vendored libraries (`External/`) and encounter resources |
| `PKDex/Show*.swift` | The `@smogon/calc` port (`ShowdownCalc`, `ShowdownRuntime`, `ShowdownMechanics`, `ShowdownChampions`, `ShowdownItems`, `ShowdownData`) and Showdown paste parsing and import |
| `PKDex/showdown-champions-data.json` | Species, move and type data generated from `@smogon/calc` |
| `PKDexTests/` | Swift Testing suites |
| `champions-m-*.json` | Regulation definitions and learnsets |
| `move_categories.json` | Move damage classes (physical, special, status) |
| `*.npz`, `*_vocab.json`, `pokii_battler.safetensors`, `feature_config.json` | On-device model weights and vocabularies |
| `zstd/` | Zstandard sources, compiled into the app for PokéFinder's compressed resources |
| `PKDex/Licenses/` | License and notice texts for the bundled third-party code, shipped in the app |
| `THIRD_PARTY_NOTICES.md` | Every third-party component, its copyright and its license |
| `tools/` | Regulation scrapers, the Showdown data generator, and vendored upstream sources |

---

## Data sources and credits

PK Reference is built on the work of many people and projects. Thank you all.

### Game data

| Source | What it provides | Where it's used |
|---|---|---|
| [**PokeAPI**](https://pokeapi.co): REST (`pokeapi.co/api/v2`) and GraphQL (`graphql.pokeapi.co/v1beta2`) | National and regional Pokédex, species and forms, base stats, types, abilities, learnsets, and every move's data | Mon Index, Move Index, Ability Index, Damage Calc, Sets, Teams, Battle Sim, Speed Tiers |
| [**Serebii.net**](https://www.serebii.net) | Pokédex, Attackdex and Abilitydex pages, plus the Champions Pokédex and regulation pages | In-app detail pages and links; the developer scripts that build each regulation's JSON files |
| [**Limitless**](https://play.limitlesstcg.com) (`play.limitlesstcg.com/api`) | Tournament listings, standings and published team sheets | Tournaments tab and Team Search |
| [**Smogon**](https://www.smogon.com) | `@smogon/calc` and its data (below), and usage statistics | Damage Calc, EV solver, Speed Tiers, Battle Sim damage. Smogon usage stats are planned for Team Search. |

### Ported and vendored code

| Project | Authors | License | Used for |
|---|---|---|---|
| [**@smogon/calc** (damage-calc)](https://github.com/smogon/damage-calc) | Created by Honko; maintained by Austin, Kris and the damage-calc contributors | MIT | The Champions damage engine (a line-by-line Swift port), stat formulas, and the bundled species, move and type data |
| [**Pokémon Showdown**](https://github.com/smogon/pokemon-showdown) | Guangcong Luo and contributors | MIT | Vendored under `tools/vendor` as the reference for Champions mechanics and data |
| [**PokéFinder**](https://github.com/Admiral-Fish/PokeFinder) | Admiral_Fish, bumba and EzPzStreamz | **GPL-3.0-or-later** | The RNG core in `PKDex/Core` (generators, searchers, encounter data), and the algorithms behind the IV calculator, IV→PID and seed recovery |
| [**EonTimer**](https://github.com/DasAmpharos/EonTimer) | DasAmpharos | MIT | The RNG timer: phase calculations, calibration, console frame rates and rounding |
| [**nlohmann/json**](https://github.com/nlohmann/json) 3.12.0 | Niels Lohmann | MIT | JSON parsing in the C++ core (bundled with PokéFinder) |
| [**Flash Perfect Hash Table**](https://github.com/renzibei/fph-table) (fph) | renzibei (includes code derived from robin-hood-hashing and Abseil) | Apache-2.0 | Perfect hash maps in the C++ core (bundled with PokéFinder) |
| [**Zstandard**](https://github.com/facebook/zstd) | Meta Platforms, Inc. and affiliates | BSD (dual-licensed BSD / GPLv2; used under BSD) | Decompressing PokéFinder's embedded resources |

The RNG tools also build on research from the Pokémon RNG community, including
RNG Reporter, PPRNG and 3DSRNG Tool. The LCRNG reversal techniques
(meet-in-the-middle and Euclidean-divisor methods) follow discussions on
crypto.stackexchange.com.

### Models

The on-device models were trained in a separate training repository by the
author of this app.

### Pokémon

Pokémon, Pokémon Champions, and all related names, characters and imagery are
trademarks and © of Nintendo, The Pokémon Company, Creatures Inc. and GAME
FREAK inc. This project is not affiliated with or endorsed by them.

---

## License

The app's own code is released under the [MIT License](LICENSE)
(© 2026 rra013).

Third-party components keep their own licenses. They're listed with their
copyright holders in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md), and the
license texts ship with the app, shown under Settings → Acknowledgements &
Licenses. In particular, **the PokéFinder code in `PKDex/Core` is licensed
under the GPL-3.0-or-later** ([`PKDex/Core/COPYING`](PKDex/Core/COPYING)), not
MIT. Review the GPL's requirements before distributing builds that include it.
