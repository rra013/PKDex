# Team Search: implementation plan

Status: **phases 1 and 2 done** (2026-09-24). Phase 1 merged in #16; phase 2
(query parsing and the search engine) is on branch `team-search-engine`. Next is
phase 3, the UI. Decisions are recorded in §7.

The goal: a user describes a team idea in plain words, for example *"Trick Room
with Mega Gardevoir, no Incineroar"*. The app shows popular team compositions
from real results that match the idea. The user can open any of them and save
it as a `SavedTeam`.

---

## 1. Data sources (checked 2026-09-24)

The requested name is "Smogon Team Search", so I checked what Smogon publishes
for Champions before designing around it.

| Source | What it has | What it lacks |
|---|---|---|
| **Smogon usage stats** (`smogon.com/stats/<month>/chaos/<format>-<rating>.json`) | Champions formats exist: `gen9championsvgc2026regmb` (+`bo3`), `gen9championsbssregmb`, `gen9championsou`, `gen9championsuu`. Per species: usage, moves, items, abilities, spreads, and **Teammates** (pairs only). | **No whole teams.** Monthly only. The latest month (2026-08) is Reg M-B. M-C data (from 2026-09-09) won't appear until September's upload, early October. Each file is 11–13 MB. Names use Showdown forms (`Charizard-Mega-Y`, `Floette-Mega`). |
| **Limitless** (`play.limitlesstcg.com/api`, already wrapped by `LimitlessAPIService`) | The VGC game has formats `M-A` / `M-B` / `M-C`, matching `ChampionsRegulation.rawValue.uppercased()`. The first page of M-C results held 50 tournaments from Sep 17–24, 28 of them with 32+ players. The largest (388 players) had a decklist for every player: species, item, ability, 4 moves, and **nature** (every member). | No stat points. Doubles (VGC) only, so no singles. |

Measured on the 3 largest M-C events (622 teams):

- There were **396 distinct six-Pokémon sets**, and the most common appeared 42 times. Most teams are unique at 6/6, so near-identical teams must be grouped or "popular compositions" is mostly a list of one-offs.
- The top four-Pokémon cores each appeared 55–73 times, so shared cores are where the popularity is.
- 201 of the 622 teams (32%) run Trick Room. Tagging teams by archetype from their moves carries real information.

**Recommendation:** use Limitless as the team corpus, because it is the only
source with complete teams that have placings. Add Smogon stats later (phase 4)
as a ranking signal, to suggest ways to fill out a partial core, and to cover
singles formats. As a result, most of what users see comes from tournaments,
not Smogon. The feature is better named **Team Search**, with sources credited
in the UI. That is decision #1 below.

---

## 2. What we build on

| Existing piece | Where | Use |
|---|---|---|
| `LimitlessAPIService` (actor, 5-min memory cache) | `LimitlessAPI.swift` | Tournament list + standings fetches |
| `PasteImporter` + `TeamPasteImport.plan` | `ShowdownPasteImport.swift:251`, `TeamPasteImport.swift:63` | Name resolution (`NameIndex`), validation, unique spread names, a plan step you can test without SwiftData. **The save path goes through these.** |
| `TournamentSpeciesAlias` | `LimitlessTeamImport.swift` (moved in phase 1) | Maps Limitless display names to local rows |
| `MegaForms.form(forSpecies:heldItem:moveNames:)` | `MegaForms.swift:32` | Post-Mega ability for archetype tags (Charizardite Y → Drought) |
| `ChampionsRegulation.current`, `speciesWhitelist()` | `ChampionsRegulation.swift:158` | Default format, parser vocabulary |
| `ChampionsValidator` (learnsets, abilities) | `03_ChampionsValidator.swift` | Move/ability vocabulary for the parser |
| `FlowLayout` | `TeamBuilder.swift:742` | Species chips |
| `AppTab` registry | `ContentView.swift` | New tab. `onAppear` (line 150) turns new tabs on for existing users automatically. |

Conventions to follow:
- Pure logic types are `nonisolated` (the module defaults to `MainActor`; see `CalcCore-HANDOFF.md`).
- `PKDex/` and `PKDexTests/` are synced folders, so new `.swift` files, and JSON placed *inside* `PKDex/`, are added to the build automatically. There is no `project.pbxproj` edit to make.
- Tests use Swift Testing and must not depend on network or SwiftData, following `TeamPasteImportTests`.

---

## 3. Architecture

```
TeamSearchView  (@MainActor UI)
    │ text
    ▼
TeamQueryParser (nonisolated, pure) ◄── vocab: regulation JSONs + team_search_vocab.json
    │ TeamQuery
    ▼
TeamSearchEngine (nonisolated, pure): filter → score → group → rank
    ▲ TeamCorpus
TeamCorpusStore (actor) ── LimitlessAPIService + disk cache (Caches/TeamSearch/)
                                              │
                         "Save team" ─────────▼
LimitlessTeamImport (@MainActor): CorpusTeam → [ShowdownPasteSet] → PasteImporter → TeamPasteImport.plan
```

---

## 4. Components

### 4.1 Corpus: `TeamCorpus.swift`

- `CorpusTeam` (nonisolated, Codable, Sendable): tournament id/name/date/player count, player name, placing, record, and `members: [CorpusMember]` (raw species, item, ability, moves, nature). Derived fields are computed once at build time: `speciesKey` (sorted, normalized), `megaSpecies`, and `tags: Set<Archetype>`.
- `TeamCorpusStore` actor:
  - `corpus(for regulation:) async throws -> TeamCorpus`
  - Page through `fetchTournaments(game: "VGC", format: "M-C")` until tournament dates fall before `regulation.validFrom`. Keep events with at least 16 players (a tunable constant).
  - **Cache each tournament's standings on disk permanently.** A finished event doesn't change, so a refresh only calls the list endpoint plus any new events. Only the list is subject to a TTL (6 h).
  - Fetch standings for at most 3–4 events at a time and report progress (`loaded n of m events`) to the UI.
  - Keep every team that has a decklist, not only the top cut. Popularity needs the full field; placing enters through weighting in §4.4.
  - Put fetching behind a `TeamCorpusFetching` protocol so tests can inject captured JSON.
- `LimitlessStanding` changes (these affect the Tournaments tab too):
  - ✅ **Done:** `placing` is now `Int?`. The API sends `null` for players who dropped (11 of 22 sampled events had some) and lists them before first place. The old non-optional `Int` failed to decode those events. `LimitlessStanding.sortedByPlacing` puts unranked players last. Corpus scoring treats `nil` as unplaced.
  - ✅ **Done:** `TeamMember` decodes `nature` and Limitless's species slug (`id` → `limitlessID`).
- **As built, differences from this sketch:** `CorpusTeam` wraps the tournament and its `LimitlessStanding` instead of copying members into a new type. The cache holds the API's own JSON shape. The crawl doesn't stop at `validFrom`, because the Limitless format filter already limits it to one regulation. Archetype tags and species keys will be derived in phase 2, not stored.

### 4.2 Query parsing: `TeamQueryParser.swift`

`TeamQuery` (nonisolated, Equatable):

```swift
struct TeamQuery {
    var includeSpecies: [SpeciesRef]     // SpeciesRef(base: "Gardevoir", mega: true)
    var excludeSpecies: [String]
    var includeMoves: [String]; var excludeMoves: [String]
    var archetypes: Set<Archetype>; var excludedArchetypes: Set<Archetype>
    var unrecognized: [String]           // shown to the user, never silently dropped
}
```

Version 1 is deterministic:
- **Species:** find every whitelist match, longest first, marking matched text as used so shorter names can't match inside it. `mega X` sets the mega flag. A small table covers common shorthand (`chomp`, `incin`, `rilla`, `gambit`, `zard`, …). Regional adjectives are handled (`hisuian arcanine` → `Arcanine-Hisui`). Fuzzy matching through `NameIndex.closestName` applies only to tokens of 5+ characters.
- **Moves:** multi-word learnset moves plus a short list of team-defining single-word moves. Moves nearly every team has, such as Protect, are ignored.
- **Archetypes:** keywords come from `team_search_vocab.json` (§4.3), so the parser and the tagger share one list.
- **Negation** (`no`, `without`, `not`, `except`, `avoid`) applies only to the *next* entity. This looks back a few words from each entity for a negation word, rather than using a greedy regex. (The removed LLM prompt normalizer did the same for "trick room".) For example, *"no Incineroar but Trick Room"* excludes Incineroar and includes Trick Room.

The UI shows the parsed query as editable chips: tap a chip to remove it or flip it between include and exclude. Letting users fix a misparse matters more than parser cleverness.

An optional later phase (§6) uses Apple's on-device FoundationModels with a `@Generable` `TeamQuery`. It works only on Apple Intelligence devices, and its output is checked against the same vocabulary. It does not use the Pokii LLM, which is a 4.5 GB download tuned to emit set JSON.

### 4.3 Archetype tagging: in `TeamSearchEngine.swift`, rules in `PKDex/team_search_vocab.json`

Tags are computed from team contents:

| Tag | Signal (any member) |
|---|---|
| trickRoom | move Trick Room |
| tailwind | move Tailwind |
| sun / rain / sand / snow | Drought / Drizzle / Sand Stream / Snow Warning, **post-Mega** via `MegaForms`, or the matching weather move |
| psychic / grassy / electric / misty terrain | matching Surge ability |
| redirection | Follow Me / Rage Powder |
| perishTrap | Perish Song + a trapping ability |

Each archetype's JSON entry holds its keywords (for the parser) and signals (for the tagger). This follows the direction set in `CompartmentalizationPlan.md` §2. Finer labels ("hard TR" vs "TR mode", "hyper offense") come later.

### 4.4 Match, group, rank: `TeamSearchEngine.swift` (nonisolated, pure)

1. **Hard filters:** every requested species is present, and a Mega request means that member holds the species' stone. No excluded species, moves, or archetypes.
2. **Relaxation:** with fewer than 10 hits, also accept teams missing exactly one requested species. These are labelled "partial match".
3. **Grouping:** group by exact species set, then merge groups sharing 5 of 6 into the larger group as variants. Ties break by a stable order so results are deterministic.
4. **Ranking:** `matchScore × Σ(placementWeight × recencyWeight)`
   - placementWeight = `1 + max(0, log2(players) − log2(placing))`, or 1 when placing is nil
   - recencyWeight uses a 14-day half-life
   - The constants live in one place. Tests pin the ordering, not the numbers.
5. **Output** is a `Composition` holding the core species, team count, variants, best placing (and in which event), number of events, archetype tags, a "why it matched" list, and a few sample teams.

A corpus is a few thousand teams per regulation, so a linear scan over precomputed sets takes a few milliseconds.

### 4.5 Saving a team: extract `LimitlessTeamImport.swift`

- An adapter turns `CorpusMember` / `LimitlessStanding.TeamMember` into `ShowdownPasteSet` (species, item, ability, nature, moves). The adapter chooses the species string: `TournamentSpeciesAlias`, Basculegion by move split (moved out of `StandingDetailView`), and regional adjectives. The result feeds into `PasteImporter.preview` and then `TeamPasteImport.plan`, which bring fuzzy resolution, validation, blocked-slot reporting, and **unique spread names** along with them.
- Switch `StandingDetailView.saveFullTeam` to the same path so both tabs share one importer. ✅ The spread-name collision is already fixed. Tournaments used to save spreads named just `member.name`, and `SavedTeam.resolvedSlots` looks spreads up by name. Saves now use `TeamPasteImport.spreadNames` / `uniqueName`, giving `<player>'s Team · <species>`. Teams saved before the fix are not repaired.
- The "Predict Stats & Nature" option stays. Now that Limitless sends nature, the predictor only fills in stat points.

### 4.6 UI: `TeamSearchView.swift`

- **Entry point:** a new `AppTab.teamSearch` ("Team Search", `sparkle.magnifyingglass`). It follows how every other feature is exposed, and users can hide or reorder it. With 11 tabs already, iPhone puts it under More. That's the same as other features, but see decision #3.
- **Search screen:**
  - Search field with an example prompt, plus a regulation picker defaulting to `ChampionsRegulation.current`.
  - Parsed-query chips below the field.
  - Result rows show species chips (`FlowLayout`), archetype tags, a summary like "42 teams · best 1st of 388 · 3 events", and a one-line "why it matched".
  - States: building (with progress), empty, error with retry, and an "Updated 3 h ago" note with pull to refresh.
- **Composition detail:** variants and a teams list (player, placing, event, date). Each team shows its members, reusing `TeamMemberRow` (make it `internal`; it's private in `TournamentsView.swift`), with **Save Team** through `LimitlessTeamImport` and a link to the event in Tournaments.
- Wide layouts use `NavigationSplitView`, following `TeamListView`'s `hSize` pattern.
- Parsing and search re-run 300 ms after typing stops, and off the main actor.

### 4.7 Settings

A "Team Search data" row in Data Management shows the last update and cache size, with Refresh and Clear cache buttons.

---

## 5. Tests (Swift Testing, no network or SwiftData)

| Suite | Covers |
|---|---|
| `TeamQueryParserTests` | Finding several species; `mega X`; shorthand and regional names; negation applying only to the next item (*"no incin but TR"*); archetype keywords; `tr`/`sun` not matching inside other words; unknown tokens surfaced |
| `TeamArchetypeTests` | Charizardite Y → sun via `MegaForms`; Trick Room / Tailwind / Surge tagging; perishTrap needs both parts |
| `TeamSearchEngineTests` | Hard filters, one-missing-species relaxation, deterministic 5-of-6 grouping, ranking order with a fixed `now` |
| `TeamCorpusStoreTests` | Trimmed Limitless JSON captured from the API, including a `null` placing; paging stops at `validFrom`; per-event disk cache in a temp dir; list TTL with an injected clock |
| `LimitlessTeamImportTests` | **Regression:** two imports sharing a species get distinct spread names; Basculegion / `Hisuian X` / `Eternal Flower Floette` resolution; blocked species reported rather than dropped |

---

## 6. Phases (one PR each, as in recent history)

0. ✅ **Tournaments bug fixes** (branch `limitless-standings-fixes`): optional `placing` with unranked players sorted last, and unique spread names on tournament saves.
1. ✅ **Corpus + shared importer (no new UI):** `TeamCorpus`, `TeamCorpusStore`, `nature` on `TeamMember`, `LimitlessTeamImport`, with `StandingDetailView` moved onto it. What landed:
   - `TeamCorpus.swift`: `TeamCorpusStore` caches each event's standings on disk (`Caches/TeamSearch/v1/<format>/`) and treats them as final once fetched 48 h after the event starts. It never refetches final events, keeps at most 4 requests in flight, and degrades to cached data on failure. Live check for M-C: 41 events with 16+ players, 2,435 teams, 14,610 members, every one with a nature and a Limitless ID. First build 1.3 s, cached rebuild 0.06 s, 2.7 MB on disk.
   - `LimitlessTeamImport.swift`: `LimitlessSpeciesResolver` (aliases → Limitless slug → name → most specific row whose words all appear → unique default form) resolves all 275 distinct species names in a 22-event sample. Before, 35 failed, including "Hisuian Arcanine" (167 teams) and "Indeedee ♀" (143). `LimitlessTeamImporter` routes saves through `PasteImporter` / `TeamPasteImport.plan`.
   - The paste importer now saves unmodelled items as text (Air Balloon, Red Card and 9 other Champions items aren't `HeldItem` cases). Before, it dropped them.
   - Follow-up: the Tournaments Mon Index link (`findPokemon`) still matches `PKMN` by raw name, so "Hisuian Arcanine" has no link. It could go through the resolver → `speciesID`.
2. ✅ **Query + engine:** `TeamQueryParser`, `TeamSearchVocabulary`, `team_search_vocab.json`, `TeamSearchEngine`, all with fixture tests (36). What landed, and where it differs from §4.2–4.4:
   - **One vocabulary file**, `PKDex/team_search_vocab.json`. It holds the styles (keywords, signals, `requires`), negation, connector and contrast words, stop words, form filler words, nicknames and the single-word move allowlist. `TeamSearchVocabulary` combines it with the regulation's two JSONs: species, form words (from alternate forms and allowed regional forms), Mega Stones with their Mega abilities, and legal moves.
   - **Species identity** is base species plus form words, limited to forms the regulation lists (so Limitless's `floette-eternal` and `floette` match). A query form must be a subset of the member's forms, and "male" means "not female".
   - **Negation:** it carries across "or", "nor" and commas, and ends at a contrast word ("and", "but") or an unknown word. This replaces "next entity only".
   - **Parser extras:** form suffixes (`arcanine-h`, `indeedee-f`), "Charizard Y" as a Mega variant, Mega Stone names, and typo correction within 1–2 edits for words of 5 or more letters, which are reported in `corrections`.
   - **Grouping** folds a group into the first heavier composition that shares all but one Pokémon, indexed by "all but one" subsets.
   - **Live check on M-C** (2,528 teams): 1 member outside the vocabulary (an Alomomola, not M-C-legal), 16 form identities, and 875 compositions. The top three hold 145, 117 and 101 teams. Searches take a few ms once event dates are parsed at index time. Parsing them per team per search cost up to 250 ms.
   - **Found while testing, then fixed:** Limitless answers HTTP 429 when hit repeatedly. `LimitlessAPIService` now checks status codes and throws `LimitlessAPIError` (`.rateLimited(retryAfter:)`, `.http(status:)`). `TeamCorpusStore` retries rate limits and 5xx errors up to 3 times, waiting for Retry-After or backing off from 2 s, capped at 60 s. Other errors still leave the event missing until the next refresh.
3. **UI:** the `AppTab` case, search and detail views, the save flow, the Settings row, and a check in the simulator.
4. *(optional)* **Smogon enrichment:** a `SmogonStatsService` that fetches the monthly chaos JSON, cached per month, and maps Showdown form names. It adds usage/teammate tie-breaks, "suggested fill" for partial cores, and singles formats (BSS/OU), shown as usage-based cores since Smogon has no complete teams.
5. *(optional)* **FoundationModels parser** for free-form descriptions.

---

## 7. Decisions and risks

1. ✅ **Naming and source (decided):** the feature is called "Team Search", and the UI credits both Limitless and Smogon.
2. ✅ **Scope (decided):** the prototype covers Champions doubles (VGC) only. Singles formats wait for the Smogon phase.
3. ✅ **Entry point (decided):** a new `AppTab.teamSearch` tab.
4. **Limitless API use.** The public endpoints worked without a key. Before shipping something that fetches dozens of standings per build, confirm the rate limits and terms. Mitigations: at most 3–4 requests at once, permanent per-event cache, and only list-endpoint refreshes.
5. **Early in a regulation there is little data.** M-C began 2026-09-09. Offer an "include M-B teams" toggle that keeps only teams whose species are all legal now.
6. **Name coverage.** Limitless uses display names (`Hisuian Arcanine`, `Eternal Flower Floette`). Search still works on unresolved names, but saving reports them (as the Tournaments alert does today). A debug log of unresolved names shows gaps in the alias table.
