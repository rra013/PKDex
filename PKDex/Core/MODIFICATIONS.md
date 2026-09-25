# Changes to PokéFinder

This directory holds the core of [PokéFinder](https://github.com/Admiral-Fish/PokeFinder),
© 2017–2024 Admiral_Fish, bumba and EzPzStreamz, licensed under the GNU General
Public License, version 3 or later ([`COPYING`](COPYING)). The Flash Perfect Hash
Table in `External/fph` is © renzibei, under the Apache License 2.0.

It was imported into PK Reference on 2026-04-18 (commit `805b4fc`) and then
modified by rra013, as listed below. As GPLv3 section 5(a) and Apache-2.0
section 4(b) require, each modified file also carries a one-line notice under its
license header. The exact changes are in the history:
`git log -p 805b4fc.. -- PKDex/Core`.

- **2026-04-24** (commit `db8b5a5`): fixes for clang warnings when building with
  Xcode. These initialize local variables and members, add explicit casts and
  explicit `this` in lambda captures, mark an unused function
  `[[maybe_unused]]`, correct doc comments, and add pragmas in fph-table's
  header that silence two warnings. 58 files.
- **2026-04-26** (commit `464b076`): progress totals for the Gen 3 and Gen 4
  wild searchers (`setMaxProgress`), and an initial `maxProgress` in
  `SearcherBase`, so the app can show search progress.
- **2026-09-24** (commit `d3f5dd5`): added `COPYING`, the GPL-3.0 text.
- **2026-09-25**: added the modification notices and this file.

## Modified files

- `External/fph/meta_fph_table.h`
- `Gen3/Generators/EggGenerator3.cpp`
- `Gen3/Generators/GameCubeGenerator.cpp`
- `Gen3/Searchers/ChannelSeedSearcher.cpp`
- `Gen3/Searchers/ColoSeedSearcher.cpp`
- `Gen3/Searchers/GalesSeedSearcher.cpp`
- `Gen3/Searchers/GalesSeedSearcher.hpp`
- `Gen3/Searchers/GameCubeSearcher.cpp`
- `Gen3/Searchers/GameCubeSearcher.hpp`
- `Gen3/Searchers/WildSearcher3.cpp`
- `Gen3/ShadowLock.cpp`
- `Gen3/States/EggState3.hpp`
- `Gen3/States/PokeSpotState.hpp`
- `Gen3/Tools/JirachiPattern.cpp`
- `Gen3/Tools/JirachiPattern.hpp`
- `Gen4/Generators/WildGenerator4.cpp`
- `Gen4/Searchers/WildSearcher4.cpp`
- `Gen4/States/EggState4.hpp`
- `Gen5/Encounters5.hpp`
- `Gen5/Generators/DreamRadarGenerator.hpp`
- `Gen5/Generators/EggGenerator5.cpp`
- `Gen5/Generators/HiddenGrottoGenerator.cpp`
- `Gen5/Generators/HiddenGrottoGenerator.hpp`
- `Gen5/Generators/StaticGenerator5.cpp`
- `Gen5/Generators/StaticGenerator5.hpp`
- `Gen5/Generators/WildGenerator5.cpp`
- `Gen5/Generators/WildGenerator5.hpp`
- `Gen5/IVCache.cpp`
- `Gen5/IVCache.hpp`
- `Gen5/PGF.hpp`
- `Gen5/Searchers/IVCacheSearcher.cpp`
- `Gen5/Searchers/IVCacheSearcher.hpp`
- `Gen5/Searchers/ProfileSearcher5.cpp`
- `Gen5/Searchers/ProfileSearcher5.hpp`
- `Gen5/Searchers/SHA1CacheSearcher.cpp`
- `Gen5/Searchers/SHA1CacheSearcher.hpp`
- `Gen5/Searchers/SearcherBase5.hpp`
- `Gen5/States/EggState5.hpp`
- `Gen8/EncounterArea8.hpp`
- `Gen8/Encounters8.cpp`
- `Gen8/Encounters8.hpp`
- `Gen8/Generators/EggGenerator8.cpp`
- `Gen8/Generators/EventGenerator8.cpp`
- `Gen8/Generators/RaidGenerator.hpp`
- `Gen8/Generators/UndergroundGenerator.cpp`
- `Gen8/States/IDState8.hpp`
- `Gen8/States/State8.hpp`
- `Gen8/UndergroundArea.hpp`
- `Gen8/WB8.hpp`
- `Parents/Filters/StateFilter.hpp`
- `Parents/PersonalInfo.hpp`
- `Parents/Searchers/SearcherBase.hpp`
- `RNG/LCRNGReverse.cpp`
- `RNG/LCRNGReverse.hpp`
- `RNG/Xoroshiro.hpp`
- `Util/Translator.cpp`
- `Util/Utilities.cpp`
- `Util/Utilities.hpp`
