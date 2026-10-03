# Third-party notices

PK Reference is licensed under the GNU General Public License, version 3 or
later (see [`LICENSE`](LICENSE)). The components below are included in this
repository and in the app under their own licenses, all compatible with the
GPL. Each license text is bundled with the app and shown under
**Settings → Acknowledgements & Licenses**.

| Component | Copyright | License | Where | License text |
|---|---|---|---|---|
| [PokéFinder](https://github.com/Admiral-Fish/PokeFinder) | © 2017–2024 Admiral_Fish, bumba and EzPzStreamz | **GPL-3.0-or-later** | `PKReference/Core` (generators, searchers, encounter data); algorithms ported in `RNGToolsView.swift` and `PFBridge*` | [`PKReference/Core/COPYING`](PKReference/Core/COPYING) |
| [@smogon/calc](https://github.com/smogon/damage-calc) | © 2013–2025 Honko and other contributors | MIT | Swift port in `PKReference/Show*.swift`, data in `PKReference/showdown-champions-data.json`, source in `tools/vendor/damage-calc` | [`PKReference/Licenses/License-smogon-damage-calc.txt`](PKReference/Licenses/License-smogon-damage-calc.txt) |
| [Pokémon Showdown](https://github.com/smogon/pokemon-showdown) | © 2011–2026 Guangcong Luo and other contributors | MIT | Source in `tools/vendor/pokemon-showdown`, used as the reference for Champions mechanics and data | [`PKReference/Licenses/License-pokemon-showdown.txt`](PKReference/Licenses/License-pokemon-showdown.txt) |
| [EonTimer](https://github.com/DasAmpharos/EonTimer) | © 2019 DasAmpharos | MIT | Timer ported in `RNGToolsView.swift` | [`PKReference/Licenses/License-EonTimer.txt`](PKReference/Licenses/License-EonTimer.txt) |
| [Ten Lines](https://github.com/Lincoln-LM/ten-lines) | © Lincoln-LM | **GPL-3.0** | FireRed/LeafGreen initial seeds and calibration ported in `PKReference/FRLGSeeds.swift` and `PKReference/PFBridge.mm` (seed list layouts, held-button offsets, initial seed search, timing, Teachy TV, calibration search, IV calculator) | [`PKReference/Licenses/License-GPL-3.0.txt`](PKReference/Licenses/License-GPL-3.0.txt) |
| [JSON for Modern C++](https://github.com/nlohmann/json) 3.12.0 | © 2013–2026 Niels Lohmann | MIT | `PKReference/Core/External/nlohmann` | [`PKReference/Licenses/License-nlohmann-json.txt`](PKReference/Licenses/License-nlohmann-json.txt) |
| [Flash Perfect Hash Table](https://github.com/renzibei/fph-table) | © 2022–2026 renzibei (includes code derived from robin-hood-hashing and Abseil) | Apache-2.0 | `PKReference/Core/External/fph` | [`PKReference/Licenses/License-fph-table.txt`](PKReference/Licenses/License-fph-table.txt), NOTICE in [`PKReference/Licenses/Notice-fph-table.txt`](PKReference/Licenses/Notice-fph-table.txt) |
| [Zstandard](https://github.com/facebook/zstd) | © Meta Platforms, Inc. and affiliates | BSD (dual-licensed BSD / GPLv2; used under BSD) | `zstd/`, `PKReference/Core/External/zstd` | [`PKReference/Licenses/License-zstd.txt`](PKReference/Licenses/License-zstd.txt) |

## The GPL-3.0 component

PokéFinder is licensed under the GNU General Public License, version 3 or
later. It's why PK Reference as a whole uses the same license. The changes made
to PokéFinder's files, and to fph-table's header, are listed in
[`PKReference/Core/MODIFICATIONS.md`](PKReference/Core/MODIFICATIONS.md), and each changed
file carries a notice. The Swift ports of PokéFinder's algorithms in
`RNGToolsView.swift` are marked "PokeFinder Port".

Ten Lines is licensed under the GPL, version 3, with no "or later" grant, so
the code ported from it in `FRLGSeeds.swift` stays under version 3. PK
Reference's GPL-3.0-or-later license allows that: the app as a whole is
distributed under version 3's terms.

## Sources of the license texts

- GPL-3.0: the official text from <https://www.gnu.org/licenses/gpl-3.0.txt>,
  used for [`LICENSE`](LICENSE), `PKReference/Core/COPYING` and
  `PKReference/Licenses/License-GPL-3.0.txt`.
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

The FireRed and LeafGreen seed lists (`PKReference/frlg-seeds-*.csv`) are the
Pokémon RNG community's, farmed on each version and shared as public Google
Sheets; they're the same lists Ten Lines builds from. `tools/update_frlg_seeds.sh`
downloads them, and the Finder's Update Seed Lists does the same in the app.
