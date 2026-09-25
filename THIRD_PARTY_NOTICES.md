# Third-party notices

PK Reference is licensed under the GNU General Public License, version 3 or
later (see [`LICENSE`](LICENSE)). The components below are included in this
repository and in the app under their own licenses, all compatible with the
GPL. Each license text is bundled with the app and shown under
**Settings → Acknowledgements & Licenses**.

| Component | Copyright | License | Where | License text |
|---|---|---|---|---|
| [PokéFinder](https://github.com/Admiral-Fish/PokeFinder) | © 2017–2024 Admiral_Fish, bumba and EzPzStreamz | **GPL-3.0-or-later** | `PKDex/Core` (generators, searchers, encounter data); algorithms ported in `RNGToolsView.swift` and `PFBridge*` | [`PKDex/Core/COPYING`](PKDex/Core/COPYING) |
| [@smogon/calc](https://github.com/smogon/damage-calc) | © 2013–2025 Honko and other contributors | MIT | Swift port in `PKDex/Show*.swift`, data in `PKDex/showdown-champions-data.json`, source in `tools/vendor/damage-calc` | [`PKDex/Licenses/License-smogon-damage-calc.txt`](PKDex/Licenses/License-smogon-damage-calc.txt) |
| [Pokémon Showdown](https://github.com/smogon/pokemon-showdown) | © 2011–2026 Guangcong Luo and other contributors | MIT | Source in `tools/vendor/pokemon-showdown`, used as the reference for Champions mechanics and data | [`PKDex/Licenses/License-pokemon-showdown.txt`](PKDex/Licenses/License-pokemon-showdown.txt) |
| [EonTimer](https://github.com/DasAmpharos/EonTimer) | © 2019 DasAmpharos | MIT | Timer ported in `RNGToolsView.swift` | [`PKDex/Licenses/License-EonTimer.txt`](PKDex/Licenses/License-EonTimer.txt) |
| [JSON for Modern C++](https://github.com/nlohmann/json) 3.12.0 | © 2013–2026 Niels Lohmann | MIT | `PKDex/Core/External/nlohmann` | [`PKDex/Licenses/License-nlohmann-json.txt`](PKDex/Licenses/License-nlohmann-json.txt) |
| [Flash Perfect Hash Table](https://github.com/renzibei/fph-table) | © 2022–2026 renzibei (includes code derived from robin-hood-hashing and Abseil) | Apache-2.0 | `PKDex/Core/External/fph` | [`PKDex/Licenses/License-fph-table.txt`](PKDex/Licenses/License-fph-table.txt), NOTICE in [`PKDex/Licenses/Notice-fph-table.txt`](PKDex/Licenses/Notice-fph-table.txt) |
| [Zstandard](https://github.com/facebook/zstd) | © Meta Platforms, Inc. and affiliates | BSD (dual-licensed BSD / GPLv2; used under BSD) | `zstd/`, `PKDex/Core/External/zstd` | [`PKDex/Licenses/License-zstd.txt`](PKDex/Licenses/License-zstd.txt) |

## The GPL-3.0 component

PokéFinder is licensed under the GNU General Public License, version 3 or
later. It's why PK Reference as a whole uses the same license. The changes made
to PokéFinder's files, and to fph-table's header, are listed in
[`PKDex/Core/MODIFICATIONS.md`](PKDex/Core/MODIFICATIONS.md), and each changed
file carries a notice. The Swift ports of PokéFinder's algorithms in
`RNGToolsView.swift` are marked "PokeFinder Port".

## Sources of the license texts

- GPL-3.0: the official text from <https://www.gnu.org/licenses/gpl-3.0.txt>,
  used for [`LICENSE`](LICENSE), `PKDex/Core/COPYING` and
  `PKDex/Licenses/License-GPL-3.0.txt`.
- @smogon/calc and Pokémon Showdown: the `LICENSE` files in `tools/vendor`.
- EonTimer: `LICENSE.md` from the upstream repository. The current `main`
  branch's README declares the MIT License but no longer includes the file,
  so the text comes from the `3.x-python` branch.
- JSON for Modern C++, Flash Perfect Hash Table and Zstandard: the upstream
  repositories' license files, plus fph-table's `NOTICE`.

## Data

The app also reads data from [PokeAPI](https://pokeapi.co),
[Serebii.net](https://www.serebii.net) and
[Limitless](https://play.limitlesstcg.com), under each site's own terms. None of
them is affiliated with PK Reference.
