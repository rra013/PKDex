# RNG Tools rewrite: implementation plan

Status: **on hold** (2026-09-25). The app was relicensed under
GPL-3.0-or-later instead, the same license as PokéFinder, which settles the
licensing for the repository and for builds distributed outside the App
Store. This plan matters again only for App Store distribution without
PokéFinder's authors' permission, or to return to a permissive license.
Nothing is built. The decisions in §8 would come first.

The goal: RNG Tools keeps working, but none of its code comes from
PokéFinder. The app could then be distributed under a license of its choosing,
including on the App Store, which the GPL-3.0 doesn't allow in practice.

---

## 1. What a rewrite has to be

**A translation doesn't fix the license.** Converting PokéFinder's C++ into
Swift line by line, or file by file, produces a derivative work, and a
derivative of GPL code is still GPL. The same applies to the Swift ports
already in the app (`LCRNG`, `LCRNGReverse`, the IV checker, the Gen 3/4
static generators and more in `RNGToolsView.swift`, each marked "PokeFinder
Port").

What copyright protects is the *expression*: the code, its structure, and
its comments. It doesn't protect the *facts and algorithms*: that Gen 3 uses
the LCRNG `seed × 0x41C64E6D + 0x6073`, that Method 1 draws the PID before
the IVs, or that Gen 5 seeds come from a SHA-1 of the date, time and
hardware values. So the rewrite must be an **independent implementation of
the games' behavior, written from public descriptions of that behavior, not
from PokéFinder**.

The process that makes that credible, and leaves a paper trail:

1. **Specs first, from public sources.** For each feature, write a short
   plain-English spec (`docs/rng-spec/*.md`) describing the game's behavior,
   with every fact cited to a public, non-PokéFinder source (§4).
2. **Implement from the spec only.** While implementing, don't open
   `PKDex/Core`, `PFBridge*`, or the existing "PokeFinder Port" Swift code.
   Structure, names and decomposition come from the spec and Swift idiom,
   not from PokéFinder's classes.
3. **Test against PokéFinder as a black box.** Before PokéFinder is removed,
   record its *outputs* for many inputs as test fixtures (§5). The new code
   must reproduce them. According to the FSF's GPL FAQ, a program's output
   generally isn't covered by the program's copyright. Recording
   input→output pairs doesn't copy its code.
4. **Record where everything came from.** `docs/rng-spec/PROVENANCE.md` lists
   each spec's sources, and each data file's origin (§4).

**Two caveats:**
- **A strict clean room needs different people.** The strict standard has
  one person read the original and write the spec, and a different person,
  who has never seen it, implement it. Nobody in this project qualifies:
  you've worked with this code, and I (Claude) have read the bridge and the
  Swift ports in this repo, and have probably seen PokéFinder's public
  source in training. The practical standard above (independent
  implementation, cited specs, no reference to the source, black-box tests)
  is what I can do. If the stricter standard matters, someone who hasn't
  read PokéFinder should write the specs or the code.
- **This isn't legal advice.** Clean-room reimplementation is a way to
  defend against a claim of copying, not a guarantee against one. If App
  Store distribution is the goal, a short review by a lawyer before
  submitting is worth it.

Old versions stay GPL in the git history. That's fine: releases made after
the last PokéFinder-derived code is removed can use another license, as long
as everyone with code in the app agrees. Today that's only rra013.

---

## 2. What there is today

### 2.1 PokéFinder's code (`PKDex/Core`, GPL-3.0)

| Area | Lines (C++, incl. headers) | What it holds |
|---|---|---|
| `RNG/` | 4,443 | LCRNG (32/64-bit), reverse LCRNG, MT19937, SFMT, TinyMT, Xorshift, Xoroshiro, SHA-1, SIMD helpers |
| `Parents/` | 4,429 | Base generators, searchers, states, filters, profiles, personal info, encounter areas |
| `Util/` | 2,965 | Date/time, IV checker, IV→PID, natures, encounter slots, translator |
| `Enum/` | 617 | Game, method, lead, encounter, shiny and similar enums |
| `Gen3/` | 6,796 | GBA and GameCube: static, wild, eggs, IDs, shadow locks, PokéSpots, Channel, seed-to-time, seed searchers |
| `Gen4/` | 7,269 | DPPt/HGSS: Method J/K, eggs, IDs and ID search, seed-to-time, roamers, coin flips, calls |
| `Gen5/` | 7,458 | BW/BW2: SHA-1 seeding (Nazos, keypresses, Timer0/VCount), static, wild, eggs, IDs, searchers, Hidden Grottos, Dream Radar, event PGFs |
| `Gen8/` | 4,853 | SwSh raids and dens; BDSP static, wild, eggs, IDs, Underground |
| `Resources/` | ~2.5 MB generated | Encounter tables (Gen 3/4/5/8), personal info for each game (`.bin`), strings in 8 languages, and the Python scripts that embed them |
| `External/` | 29,339 | nlohmann/json (MIT), fph-table (Apache-2.0), zstd (BSD). Not GPL, but only PokéFinder uses them |

**Total GPL code:** about 39,000 lines of C++, plus the generated data.
**Not needed:** SFMT and TinyMT (used by no generator the app reaches), and
the non-English strings (the app always asks for English).

### 2.2 The app's side

- **`PFBridge.h` / `.mm`** (3,864 lines): a C bridge of about 85 functions
  over PokéFinder's classes. It was written against PokéFinder's API, so
  it's derived code too.
- **`PFBridgeSwift.swift`** (2,195 lines): the Swift facade. There's a
  `PFBridge` enum with 82 static functions, plus `PF…Swift` result types.
  **The UI calls only this facade**, so it's the seam to swap behind.
- **Ports in Swift** (about 1,900 lines of `RNGToolsView.swift`): LCRNG and
  reverse LCRNG, IV↔PID recovery, Finder types and profiles, the Gen 3
  origin seed, Gen 3/4 static generators and searchers, Gen 3/4
  seed-to-time, the Gen 5 static generator, seed verification, coin flips,
  Elm/Irwin calls, and the IV checker. All marked as ports and all GPL.
- **Not affected:** the RNG timer is ported from EonTimer (MIT). The UI
  views are the app's own. The Hidden Power calculator is a formula.
- **Tests:** `RNGToolsTests.swift` has 132 tests. The timer tests stay. The
  port tests get replaced by spec-based and fixture tests.

Tabs and what they use:

| Tab | Uses |
|---|---|
| Timer | EonTimer port (stays) |
| Finder | Static/wild generate and search, Gen 3/4/5/8, Methods 1/2/4, J/K, 5; seed-to-time; coin flips; calls |
| Routes | Encounter tables for Gen 3/4/5/8 |
| Statics | Static encounter templates for Gen 3/4/5/8 |
| Eggs | Egg generators for Gen 3/4/5/8 |
| TID/SID | ID generators for Gen 3/4/5/8 (RS, FRLGE, XD/Colo), and the Gen 4 ID search |
| GameCube | Shadow and static generate/search, PokéSpots, Colo/Gales/Channel seed search, Jirachi pattern |
| IV Calc, IV→PID, HP | IV checker, IV↔PID, the Hidden Power formula |

---

## 3. Target design

- **A new folder, `PKDex/RNG/`,** of pure Swift. Types are `nonisolated`,
  because the module defaults to main-actor isolation, so searches can run
  off the main thread.
  - `RNG/Engines/`: `LCRNG32` (the GBA/NDS and GameCube constants, and
    reverse stepping), `LCRNG64` (BW), `MersenneTwister` (MT19937),
    `Xorshift128` (BDSP), `Xoroshiro128Plus` (SwSh), and a fixed-length
    SHA-1 for Gen 5 seeding, written from FIPS 180-4, with a
    `SIMD4<UInt32>` version for searches.
  - `RNG/Model/`: profiles (game, TID/SID, console), states, filters (IVs,
    nature, Hidden Power, shiny, ability, gender, slot), natures, stat
    formulas, the IV checker, and IV↔PID recovery.
  - `RNG/Gen3/`, `Gen4/`, `Gen5/`, `GameCube/`, `Gen8/`: generators and
    searchers, written from `docs/rng-spec`.
  - `RNG/Data/`: loaders for the regenerated data (§4.2).
- **An `RNGEngine` facade** replaces `PFBridge`, with neutral names
  (`RNGWildResult` instead of `PFWildGeneratorStateSwift`, for example).
  - Its signatures stay close to the UI's current calls, so switching the
    UI is mostly renaming.
  - Searches become `async` functions that report progress through an
    `AsyncStream` and stop on task cancellation. That replaces the C
    handle/poll/free protocol.
- **Performance:** the C++ searchers use SIMD and threads. The Swift ones
  will use:
  - `SIMD4` lanes for LCRNG and SHA-1
  - `withTaskGroup` over seed ranges
  - unsafe buffers only in the inner loops

  Target: every search within 1.5× of the C++ baseline on the same device
  (§5).
- **Removed at the end:** `PKDex/Core`, `PFBridge.h/.mm`,
  `PFBridgeSwift.swift`, the bridging header (it only imports `PFBridge.h`),
  the C++ build settings, and the top-level `zstd/` and the `External/`
  libraries, since only PokéFinder uses them.

---

## 4. Sources

### 4.1 Behavior (for the specs)

Every fact in a spec cites where it came from. Acceptable sources:

- **Published algorithms:**
  - MT19937 (Matsumoto & Nishimura's reference and paper)
  - Xorshift (Marsaglia's paper)
  - Xoroshiro128+ (Blackman & Vigna, public domain)
  - SHA-1 (FIPS 180-4)
  - LCRNG constants and reverse-stepping math, which are facts
- **Community research write-ups** on how each generation creates Pokémon:
  RNG research threads and guides, and wikis describing PID/IV generation,
  encounter slots, leads, eggs, and Gen 5 seeding and Nazo values. Use them
  for facts. Don't copy their text.
- **Game decompilations** (for example, pret's GBA/NDS projects), read to
  understand what the game does. Check each project's license, and never
  copy code from them.
- **Not allowed:** PokéFinder's source, PFBridge, the existing Swift ports,
  or any other GPL implementation (PKHeX, RNG Reporter forks and similar).

### 4.2 Data

The embedded PokéFinder data is replaced with data rebuilt from other
sources. A generator script in `tools/rng-data/` writes JSON into
`PKDex/RNGData/`, and each record says where it came from.

| Data | Source | Notes |
|---|---|---|
| Per-generation base stats, types, gender ratios, abilities | Pokémon Showdown's per-generation mods (`gen4`, `gen5`, `gen8`, `gen8bdsp`, `gen3colosseum` and others; MIT, already vendored in `tools/vendor`) | Older generations' stats differ (the Gen 6 buffs), and the mods record them. Gen 3 inherits Gen 4's Pokédex data |
| Names (species, moves, abilities, items, natures) | Data the app already has (PokeAPI, Showdown) | English only, as today |
| Gen 3–5 wild encounter slots (slot number, rate, level range, method, time/season/swarm conditions) | PokeAPI's encounter tables (veekun-derived) | Confirm the license, and that slot numbers match the games' slot order |
| Static encounters, gifts, roamers, starters | Hand-written JSON, each entry citing a public source | A few hundred entries |
| Gen 5 Nazo values, Timer0/VCount/GxStat defaults per game, language and console | Hand-written JSON from published research tables | Small |
| GameCube shadow Pokémon and their lock teams; PokéSpot tables | Hand-written JSON from published research | The hardest data to source |
| SwSh dens and raid tables; BDSP Underground tables | **Not sourced yet** | PokeAPI has no SwSh encounters. See decision 2 |

PokéFinder's tables may be used only to **check** the rebuilt data: a
report of what's missing or different, investigated against the public
sources. They are never a source.

---

## 5. Verification

1. **Golden fixtures (phase 0, while PokéFinder is still built in):**
   - A test-only recorder runs the current `PFBridge` over a large grid of
     inputs: seeds, advances, profiles, methods, leads, filters, encounter
     areas, dates and keypresses.
   - It writes the outputs as JSON fixtures in `PKDexTests/Fixtures/RNG/`:
     PID, IVs, nature, ability, gender, shininess, slot, level, advance,
     seed and time.
   - About 50,000 cases, split by feature and compressed.
   - The fixtures record outputs only, never PokéFinder's data tables.
2. **Parity tests:** each phase's new code must match its fixtures exactly.
   A mismatch is investigated against the spec. PokéFinder could have a bug,
   in which case the spec wins and the difference is documented.
3. **Behavior tests from the specs:** small hand-checked cases for each
   spec, such as a known Method 1 seed → PID, a known Gen 4 seed → date and
   delay, or a known Gen 5 message → SHA-1 seed. These don't depend on
   PokéFinder at all.
4. **Differential mode (DEBUG builds, until phase 8):** each facade call
   runs both implementations and logs any mismatch. That catches inputs the
   fixtures miss.
5. **Performance baseline:** before starting, time each searcher through the
   C++ bridge on a device. Each phase's Swift searcher must be within 1.5×.
   Gen 5 searches are the heavy ones.
6. **Simulator checks** of each tab after its switch, on the one iPhone 17
   Pro Max simulator, as usual.

---

## 6. Phases (one PR each)

Each phase switches only its own facade calls to Swift. PokéFinder stays
built in until phase 8, so the app works at every step.

0. **Groundwork**
   - The `RNGEngine` facade and neutral result types, still backed by
     PFBridge. The UI moves onto it, renaming only.
   - The golden-fixture recorder and fixtures.
   - The performance baseline.
   - An empty `docs/rng-spec/` with its provenance log.
1. **Engines and shared model**
   - Specs and code: LCRNG32/64 (forward and reverse), MT19937, Xorshift128,
     Xoroshiro128+, SHA-1 (scalar and SIMD).
   - Also natures, stat formulas, Hidden Power, the IV checker, and IV↔PID
     recovery.
   - This replaces the "PokeFinder Port" code in `RNGToolsView.swift`, and
     switches IV Calc, IV→PID and HP.
2. **Data**
   - The `tools/rng-data` pipeline: per-generation personal info, Gen 3–5
     wild encounters, statics, Nazos.
   - A coverage report against the current tables.
   - This switches Routes and Statics for Gen 3–5.
3. **Gen 3 (GBA)**
   - Methods 1/2/4 static and wild (Method H: slots, levels, leads,
     Synchronize and Cute Charm), and their searchers.
   - Eggs (RS, Emerald, FRLG), TID/SID (RS clock, FRLGE), seed-to-time, the
     Jirachi pattern.
4. **Gen 4**
   - Method J/K static and wild (DPPt and HGSS slot rules, leads), and their
     searchers.
   - Eggs, TID/SID generation and ID search, seed-to-time (date, hour,
     delay), coin flips, Elm/Irwin calls, HGSS roamers.
5. **Gen 5**
   - SHA-1 seeding (MAC address, date, time, keypresses, Timer0, VCount,
     GxStat, frame, Nazos), BWRNG plus MT.
   - Static, wild, eggs, IDs, and the time-range searchers with keypresses.
     This is where the SIMD SHA-1 matters.
   - Hidden Grottos, Dream Radar and event PGFs, if kept (decision 1).
6. **GameCube**
   - Colosseum/XD shadow Pokémon with nature/gender locks, statics,
     PokéSpots, Channel/Jirachi.
   - The Colo/Gales/Channel seed searchers.
7. **Gen 8**
   - BDSP (Xorshift): static, wild, eggs, IDs, Underground.
   - SwSh (Xoroshiro): raids from den data.
   - Only what decision 2 keeps.
8. **Removal and relicensing**
   - Delete `PKDex/Core`, the bridge, the C++ settings and the external
     libraries.
   - Remove differential mode.
   - Update:
     - `LICENSE`: the license chosen then, in place of the GPL
     - `THIRD_PARTY_NOTICES.md`: remove PokéFinder, zstd, nlohmann/json and
       fph-table, and credit the research sources
     - Acknowledgements and its test
     - README and the Settings text
   - Credit the research community in the RNG Credits tab as sources of
     facts, not code.

The logic phases (1, 3–7) are each about the size of a Team Search phase or
larger. Phase 5 and phase 6 are the biggest. The finished Swift should come
to roughly 12,000–18,000 lines, plus the data pipeline.

---

## 7. Risks

1. **Data sourcing is the long pole.**
   - Wild encounter slots for Gen 3–5 look covered.
   - GameCube lock data, SwSh dens and BDSP Underground tables have no
     permissive source identified yet.
   - Fallback: cut those features rather than take data from PokéFinder.
2. **Parity gaps.** Fixtures can't cover every combination. Differential
   mode and per-spec tests narrow the gap. Mismatches after release get
   fixed against the spec.
3. **Performance.** Gen 5 time searches do millions of SHA-1s. If Swift
   can't reach 1.5×, narrow the default search ranges, or run searches in
   stages (seconds first, then keypresses).
4. **Taint concerns** (§1). This process is the practical standard. It
   can't make anyone who has read PokéFinder "clean".
5. **Scope creep.** The rewrite reproduces today's features. New features
   wait until phase 8 is done.

---

## 8. Decisions needed before starting

1. **Scope.** Keep every current feature, or cut some? The candidates are
   the ones that are costly or hard to source:
   - SwSh raids/dens
   - BDSP Underground
   - GameCube shadow locks
   - Gen 5 Hidden Grottos, Dream Radar and event PGFs

   Recommended: keep Gen 3, 4 and 5 and BDSP's core generators. Decide on
   the rest after phase 2 shows what data can be sourced.
2. **Gen 8 data.** If no permissive source turns up for dens and Underground
   tables, drop those features or hand-build a subset?
3. **Clean-room standard.** The practical process in §1, or the strict one
   with someone who hasn't read PokéFinder writing specs or code? And a
   legal review before an App Store release?
4. **Cheaper routes, worth checking first:**
   - **Ask PokéFinder's authors** (Admiral_Fish, bumba, EzPzStreamz, and
     other contributors with code in the copied files) for an App Store
     exception to the GPL. Every copyright holder of the copied code has to
     agree. If they do, none of this is needed.
   - **Ship an App Store build without RNG Tools** while the rewrite is in
     progress, if a release comes first.
