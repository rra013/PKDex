# PK Reference: handoff

State of `main` as of 2026-09-27, how the codebase fits together for the
next change, and what's worth doing next. The [README](README.md) describes
the app itself; this file is for whoever works on it.

## Contents

1. [Recent work](#recent-work)
2. [Where things live](#where-things-live)
3. [Recipes](#recipes)
4. [Conventions](#conventions)
5. [Building and testing](#building-and-testing)
6. [Known limitations](#known-limitations)
7. [What's next](#whats-next)
8. [Other documents](#other-documents)

---

## Recent work

The last twelve PRs made the UI consistent and customizable. Each one's
description says what changed and what was checked on the simulator.

| PR | Change |
|---|---|
| [#23](https://github.com/rra013/PKDex/pull/23) | Hidden tabs stay hidden across launches; tabs can be reordered (`TabLayout`) |
| [#24](https://github.com/rra013/PKDex/pull/24) | One type palette with readable badge text (`Theme.swift` starts) |
| [#25](https://github.com/rra013/PKDex/pull/25) | Shared colors for Pokémon 1/2, ability and item (`ColorRole`) |
| [#26](https://github.com/rra013/PKDex/pull/26) | One card style; cards have an edge in dark mode |
| [#27](https://github.com/rra013/PKDex/pull/27) | One primary action button style |
| [#28](https://github.com/rra013/PKDex/pull/28) | Screens work at large Dynamic Type sizes |
| [#29](https://github.com/rra013/PKDex/pull/29) | The same for the Battle Sim screen |
| [#30](https://github.com/rra013/PKDex/pull/30) | Type badge style and density options; settings keys in `AppSettings` |
| [#31](https://github.com/rra013/PKDex/pull/31) | Optional type-colored backgrounds |
| [#32](https://github.com/rra013/PKDex/pull/32) | The app's own More tab (no doubled back button); asks before closing a tab with work in progress |
| [#33](https://github.com/rra013/PKDex/pull/33) | Forms show their species' Dex number; no thousands separator |
| [#35](https://github.com/rra013/PKDex/pull/35) | A Settings switch turns the set delete prompt back on after "Don't Ask Again" |

Full suite at #35: 1032 tests, all passing.

---

## Where things live

**`PKDex/Theme.swift`**: every shared style. Use these rather than
hand-rolling colors, radii or paddings.

| Piece | What it's for |
|---|---|
| `TypePalette` | Type colors, the text color for each, and the tint and wash strengths. WCAG math lives here too. |
| `TypeBadge`, `typeBadgeBackground(_:)` | A type's capsule, in the viewer's badge style (filled or tinted). |
| `ColorRole` | Colors with one meaning: `ability`, `item`, `nature`, and `field` (the calc's weather, terrain and other field conditions), each with light and dark values. |
| `MatchupColors`, `MatchupSide` | The viewer's colors for Pokémon 1 and 2 in the calc (Teal & Pink, Blue & Gold, Blue & Red). Draw a side with `matchupColors.color(for:)`, reading `\.matchupColors`. |
| `card()`, `insetCard()`, `cardPage()`, `CardStack`, `SectionCard`, `CardMetrics`, `Density` | Card surfaces, their spacing, and Compact density. `types:` adds the type-colored wash. |
| `.buttonStyle(.primaryAction)` | A screen's main action. Add `.tint(.red)` for stop or cancel. |
| `scaledWidth`, `scaledFont`, `AdaptiveStack`, `FlowLayout`, `DynamicTypeSize.gridColumns(_:)` | Layouts that hold up at large text sizes. |
| `EnvironmentValues`: `typeBadgeStyle`, `matchupColors`, `density`, `typeBackgrounds` | Set once in `ContentView`, read by the views above. |

**`PKDex/AppSettings.swift`**: every app-wide setting's key and default.
Views use `@AppStorage(AppSettings.x)`. The RNG tools' `finder_*` keys are
form inputs and stay where they are.

**`PKDex/TabLayout.swift`**: the user's tab order and hidden tabs, and
`compactSplit`, which decides what goes in the iPhone tab bar and what goes
under More.

**`PKDex/MoreTab.swift`**: the iPhone More tab. `TabNavigationStack` is a
tab's navigation root that joins More's stack when opened from it.
`leaveWarning(_:)` is how a tab says closing it loses work.
`TabReselectGuard` stops a second tap on More from closing a tab silently.
It works by sitting in front of the UITabBarController's delegate, the only
code that changes how the tab bar behaves underneath SwiftUI, so check it
first if tab switching ever misbehaves.

**Game data in `PKDex/`**: facts that change with games and regulations
are JSON, each loaded strictly (a misspelled name fails the file) and
checked by a test that it loads:

| File | Holds | Loaded by |
|---|---|---|
| `champions-<id>.json` | a regulation's species, items, Mega stones and `rules` | `ChampionsRegulation`, `ChampionsValidator` |
| `mega_forms.json` | every Mega form; its stone becomes a held item | `MegaForms` |
| `battle_moves.json` | the Battle Sim's move effects, and setup moves | `BattleMoveEffects` |
| `type_chart.json` | the 18 types and their matchups | `TypeChart` |

The Showdown damage port has its own data (`showdown-champions-data.json`);
`TypeChartTests` checks the two type charts agree.

---

## Recipes

**Adding a tab**
1. Add a case to `AppTab` (`ContentView.swift`) with a label and icon, and
   add it to `allUserTabs`. Existing users' saved order gains it at the end
   automatically.
2. Wrap its root view in `TabNavigationStack`, not `NavigationStack`, or it
   shows two back buttons under More.
3. If it holds work that closing it would lose, add
   `.leaveWarning(condition ? "What would be lost." : nil)` to its `body`.
4. Lay it out with `cardPage()`, `CardStack` and `SectionCard`, and use
   `.primaryAction` for its main button.
5. For a list beside the selected item's page in wide layouts, use
   `ListDetailSplit { list } detail: { page }` (`ContentView.swift`), not a
   `NavigationSplitView`. On iOS it is one; on the Mac, a split view inside
   the app's sidebar pushed its page right by the sidebar's width a second
   time, so there it's a resizable split in the tab's navigation stack.
6. In a form, give a text field a title and put its example in `prompt:`,
   with `.labelsHidden()` if a header or label already names it: a Mac form
   shows the title as a label beside the field. Segmented pickers get
   `.labelsHidden()` too; iOS never shows their label, and on the Mac it
   repeated the caption above them.
7. A sheet's content gets `.sheetSize()`: a Mac sheet is as big as its
   content asks, and a list asks for no height. Give it a Cancel or Done
   toolbar button (Mac sheets can't be swiped away), and don't put a button
   at `.principal`, which a Mac sheet doesn't show.
8. Rows that delete by swiping also get a Mac-only `.contextMenu` with the
   same Delete: swipes need a trackpad, and Mac lists have no edit mode.

**Adding a setting**
1. Add a `SettingKey` to `AppSettings`.
2. Add its name and default to `AppSettingsTests` (the names are pinned:
   renaming one resets that setting for everyone).
3. If it changes how many views draw, read it in `AppearanceSettings`
   (`ContentView.swift`) and pass it through `EnvironmentValues`, as
   `density` does. That modifier also dresses the Mac's Settings window.

**Adding a Battle Sim move effect**: add the move to the right table in
`PKDex/battle_moves.json` (its `notes` say what each holds), keyed by its
normalized name (`BattleSimSeed.normalize`: "Swords Dance" is
`swordsdance`). That's all when the effect is one the engine already has.
A move that needs new behavior needs code; the dispatch lists for those
(tier 3 and 5 status moves, fixed damage, damage modifiers) are in
`BattleMoveEffects`. `BattleMovesDataTests` fails on a misspelled kind,
stat or key.

**Adding a Mega Evolution**: add a line to `PKDex/mega_forms.json` (its
`about` field explains each key). Its stone becomes a held item from that
line; there's nothing to add in Swift. For a Champions regulation, the
stone also needs to be in that regulation's `mega_stones` and item list.

**Adding a held item** (not a Mega stone): items have effects, so this is
code. In `PokemonStatsModels.swift`, add a `static let` to `HeldItem` and
put it in `HeldItem.builtIns`, in picker order; then implement its effect
where the others are (`computeItemModifiers`, the Battle Sim). A 1.2×
type item or a resist berry only needs an entry in `typeBoostingItemMap`
or `typeResistBerryMap`. If the Champions calc doesn't model the item, add
it to `HeldItem.nonChampionsItems` too: Champions-mode pickers then leave it
out, and a set already holding it shows it marked "not in Champions".

**Adding a color with meaning**: add a case to `ColorRole` with light and
dark values. `ColorRoleTests` fails until both clear 4.5:1 contrast, and
until the new role is at least 12 apart from every other role and 8 from
every matchup side (distance in OKLab ×100).

**Adding a matchup pair**: add a case to `MatchupColors` with a label and
both sides' light and dark values. `ColorRoleTests` holds each pair to the
same contrast rules, and checks its sides stay apart from each other and
from the ability and item colors.

**Adding a note or build input inside `PKDex/`**: the folder is synced, so
Xcode copies every file in it into the app. Add a file the app doesn't
read to the "Exceptions for PKDex folder" list in the target's file
membership (Xcode's File inspector, or `membershipExceptions` in
`project.pbxproj`), as the developer notes and PokéFinder's generator
inputs are. The list takes files, not folders: a folder path is ignored.
Or keep notes at the repository root.

PokéFinder's `Core/Resources/embed.py` compiles its `i18n/*.txt` and
`Personal/*.bin` into `i18n.hpp` and `Personal.hpp`, which the app builds
from. Those inputs, the scripts and `Core/External/CMakeLists.txt` are
excluded; a new file in those folders needs adding to the list too.

---

## Conventions

**`nonisolated` for pure types.** The module builds with main-actor default
isolation, so every unannotated type, value types included, is
main-actor-bound. Anything that runs off the main thread (the damage port,
calc snapshots, the EV and two-hit solvers, the paste parser, Team Search's
engine and stores) is explicitly `nonisolated`. It's load-bearing, not
style. Three things learned applying it:
- It only widens; it can't break an existing main-actor caller.
- A protocol's default implementation in an unannotated extension stays
  main-actor-isolated and drags the conformance with it. If you see
  "conformance … crosses into main actor-isolated code", look for a default
  implementation, not the conforming type.
- Expect cascades: annotate, check diagnostics, repeat.

**Champions rules come from the regulation JSON.** Stat-point caps, the IV
lock, team size, clauses and which gimmicks are allowed live in each
`champions-<id>.json`'s `rules` block. Read them with
`ChampionsRegulation.current.rules()`, or `championsMaxEVPerStat`,
`championsMaxTotalEVs` and `championsLockedIV`; don't type 66, 32 or 31.
The one fixed number is `championsStatPointsPer252EVs`, the exchange rate
between EVs and stat points, which is a game mechanic.

**Calc snapshots.** `CalcSnapshot` holds raw inputs (base stats, EVs, IVs,
nature, stages), not finished stats, because the solvers vary an EV and
recompute. `CalcOutcome.rolls` is optional (only the Showdown port has real
rolls), damage is `Double` as both engines compute it, and `snapshot()`
returns nil with no species rather than solving against a phantom 1/1/1
statline. Imported sets with no nature default to Serious.

**Deterministic battle tests.** Set `BattleEngine.rollOverride` to
`.init(crit: false, roll: .max)` before `executeTurn()` in any test that
compares damage across runs. Don't loosen thresholds instead: at low power
the damage bands are close enough that a loose threshold stops the test
catching the mechanic failing. It covers crits and damage rolls only; a test
that depends on another random draw (paralysis, sleep length, speed ties…)
needs its own guard.

**Parity suites.** The nine `BattleTier` files, `DamageCalcMegaEvolutionTests`,
`AbilityTests`, `BattleItemsTests`, `TypeChartTests`, "Known Damage Ranges"
and "Damage Engine" encode damage numbers that can't be re-derived. If a calc
change keeps them passing, it's faithful.

**UI changes are checked on the simulator**, in light and dark mode and, for
layout changes, at an accessibility text size. Each PR lists what was and
wasn't checked.

---

## Building and testing

```bash
xcodebuild test -project PKDex.xcodeproj -scheme PKDex \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -parallel-testing-enabled NO
```

- **Keep `-parallel-testing-enabled NO`.** The default clones the simulator,
  and a clone left by an interrupted run makes the next launch fail
  ("Application failed preflight checks"). With more than one simulator of
  that name, pass `id=<udid>` instead.
- `xcodebuild` sometimes hangs after the tests finish. Once the
  `Test run with N tests` line appears, it's safe to stop it.
- `-test-iterations` doesn't repeat Swift Testing tests; loop
  `test-without-building` instead.
- The device's text size and appearance can be switched from the command
  line for checks: `xcrun simctl ui <udid> content_size accessibility-large`
  and `xcrun simctl ui <udid> appearance dark`.

The Mac app builds from the same target (on `mac-main` until it merges).
This signs it to run on this Mac only:

```bash
xcodebuild build -project PKDex.xcodeproj -scheme PKDex -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
```

- **Wrap iOS-only APIs in `#if os(iOS)`**, or the Mac build fails:
  `navigationBarTitleDisplayMode`, `keyboardType`,
  `textInputAutocapitalization`, `UIApplication`, `UIPasteboard`,
  `EditMode`/`EditButton`, and the `.topBarLeading`/`.topBarTrailing`
  placements. The compiler reports only the first in each modifier chain, so
  after fixing one, search the file for the rest.
- **Mac builds use no entitlements file** (`CODE_SIGN_ENTITLEMENTS[sdk=macosx*]`
  is empty): the iOS file's increased-memory-limit entitlement doesn't exist
  on macOS. The sandbox, outgoing-network and user-selected-file
  entitlements come from the build settings.
- The iOS background colors the views name (`systemGroupedBackground` and
  three others) are defined for `NSColor` in `Theme.swift`, with iOS's
  values.
- **Checking Mac screens: use the app's own snapshots, not screen capture**
  (the owner prefers no screen access). Debug Mac builds draw their windows
  into pictures themselves (`DebugSnapshot.swift`). Run the app's binary
  with launch arguments; settings passed the same way apply to that run only:

  ```bash
  <path>/PKDex.app/Contents/MacOS/PKDex -debugSnapshot calc -debugSnapshotQuit YES \
    -debugSnapshotStdout YES -defaultTab damageCalc -appAppearance light \
    -debugWindowSize 1280x820 > run.log
  ```

  Each open window's picture is printed as a `[DebugSnapshot png <name>]
  <base64>` line; decode those from the log. Don't read the pictures from
  the app's container: macOS asks permission before another app reads it,
  and the prompt stalls a script. To reach a screen:
  - `-debugOpenFirst YES`: the first item in Mon Index, Sets, Teams or Team
    Search.
  - `-debugOpenSheet <name>`: `save`, `paste` or `load` (the calc), `newSet`
    (Sets). A presenter adds a name with `DebugSnapshot.openSheet`.
  - `-debugOpenSettings YES`: the Settings window, as `<name>-Settings`.
  - `-debugMenus YES` prints the menu bar with shortcuts, as `[menu]` lines.

  Glass comes out blank (the app's sidebar, search fields), as do web
  views. For a screen reached by hand, Debug › Save Window Snapshot (⇧⌘S)
  saves the window into the container and plays a sound; ask the owner to
  share it.
- **If every Mac window opens blank**, a layout blew up once and the window
  saved it as its sidebar's divider position (widths in the billions under
  `NSSplitView Subview Frames` in the app's preferences). Delete those
  entries with `defaults delete` on the container's preferences file.
  Opening an already-running app doesn't reload it: quit it first to try a
  new build.

---

## Known limitations

From the recent PRs, each also noted in its description:

- **Launching into a tab with a search field under More.** When a tab with a
  search field (Mon Index, Move Index, Ability Index, Speed Tiers,
  Tournaments, Team Search) is under More *and* set as Open To, its large
  title appears only after the first scroll at launch (iOS 26.4). Tapping
  into it is fine; four workarounds didn't help. (#32)
- **Mon Index haptic under More.** The selection tick when opening a Pokémon
  is skipped while Mon Index is under More, because More's stack has no path
  of Mon Index's to watch. (#32)
- **The iPad tab bar pages.** A wide iPad window's tab bar can't show all
  twelve tabs, so it scrolls, and the open tab can scroll out of view. The
  sidebar-adaptable tab style fixes that, but on iPadOS 26.4 a split-view tab
  (Sets, Teams, Team Search) first opened from its sidebar lays out under the
  floating tab bar, which covers the tab's own buttons, so it was reverted.
  (#37)
- **Resizing an iPad window across the compact width** reopens the tabs
  after the fourth in their new place (the tab bar or the app's More list),
  so work in them is lost. (#37)
- **Not checked on screen:**
  - iPad in landscape: the simulator panel can't rotate a device
  - the leave prompt for the RNG searches (the timer's was checked in #37)
  - type-colored backgrounds on the compare page, and with large text or
    Compact density (#31)
- **Battle log at accessibility sizes.** It stays at a fixed 220pt, which is
  about three lines at the largest size. Usable, but it could shrink there.
  (#29)

---

## What's next

Roughly in order of value for effort.

1. **Data compartmentalization.** [`PKDex/CompartmentalizationPlan.md`](PKDex/CompartmentalizationPlan.md)
   lists seven migrations of game data into JSON, all done: each
   regulation's `rules` block (P1), the Battle Sim's move tables (P2), the
   type chart (P3), the Mega forms (P4), Mega stones as held items (P5), the
   validator's setup moves and Choice items (P6) and a set's Tera type (P7).
   See the plan for what each covers and leaves; what's left are the parts
   of P5 and P7 that need features first (items, Tera, Dynamax).
2. **Mac app, distributed outside the App Store.** Work happens on
   `mac-main`, with a PR into it per step; merge `main` into it as `main`
   moves, and `mac-main` into `main` once the Mac app is ready.
   1. Builds and runs. Done: iOS-only APIs guarded, Mac entitlements.
   2. App shell. Done: the tabs in a sidebar (`.sidebarAdaptable`), with no
      More list; Settings as the ⌘, window; a 1280×820 default window, at
      least 900×600; wider list columns in split-view tabs. The sidebar
      itself hasn't been seen, since snapshots can't draw glass.
   3. Screen pass. Done: list/detail tabs in `ListDetailSplit`; form text
      fields and segmented pickers without stray labels; a right-click
      Delete where rows only swiped (Sets, Teams, Load Spread); every sheet
      sized with `sheetSize()` (all 17 already had Done or Cancel); Edit ›
      Find (⌘F) and the tabs in the View menu (⌘1–⌘9), which the owner
      checked on the Mac along with right-click Delete. Left out: a
      paste-import command, since the calc has two sides to paste into.
   4. Developer ID signing, the hardened runtime, notarization, and releases
      on GitHub, with the tagged source for the GPL. Optionally Sparkle for
      updates.
3. **Team Search open risks.**
   - Confirm Limitless's rate limits and terms before corpus builds grow.
   - Early in a regulation there's little data. An "include last
     regulation's teams" option (keeping only teams legal now) was planned
     but not built.
   - Names Limitless writes that the alias table doesn't know still search,
     but saving a team reports them; a log of them would show the gaps.
4. **Gen 9 in the Showdown port.** Only Champions is ported; other
   generations use the legacy engine, and `calculateShowdown` stops with a
   clear error for them. See [`PKDex/ShowdownPort-NOTES.md`](PKDex/ShowdownPort-NOTES.md).
5. **App Store.** Blocked on the GPL until PokéFinder's authors give
   permission, or the RNG core is rewritten per
   [`RNGRewrite-PLAN.md`](RNGRewrite-PLAN.md) (on hold).

---

## Other documents

| File | What it covers |
|---|---|
| [`README.md`](README.md) | The app: features, architecture, building, data sources, license |
| [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) | Bundled third-party code and its licenses |
| [`PKDex/Core/MODIFICATIONS.md`](PKDex/Core/MODIFICATIONS.md) | Changes made to PokéFinder's code (required by its GPL) |
| [`PKDex/ShowdownPort-NOTES.md`](PKDex/ShowdownPort-NOTES.md) | Scope and wiring of the `@smogon/calc` port |
| [`PKDex/AbilityReference.md`](PKDex/AbilityReference.md) | Which abilities the legacy damage engine models |
| [`PKDex/CompartmentalizationPlan.md`](PKDex/CompartmentalizationPlan.md) | Plan for moving game data into JSON (not started) |
| [`RNGRewrite-PLAN.md`](RNGRewrite-PLAN.md) | Plan for an independent RNG core (on hold) |
| [`tools/README.md`](tools/README.md) | Scripts that regenerate the bundled data |

Removed on 2026-09-27, all in git history: `CalcCore-HANDOFF.md` (the EV
solver work, finished; its conventions are above; it was also being copied
into the app),
`TeamSearch-PLAN.md` (finished; its open risks are above) and
`PKDex/ProjectDocumentation.md` (an April file-by-file reference, replaced by
the README's architecture section).
