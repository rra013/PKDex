# Siri, Spotlight and Shortcuts: implementation plan

Status: **planned** (2026-09-30). Nothing is built yet. The questions in §7
come first.

The goal: people can ask Siri to look things up, run the calc or search
teams without opening the app, on iPhone, iPad and the Mac. The same actions
appear in Spotlight (on the Mac, macOS 26 runs app actions straight from
Spotlight) and in the Shortcuts app.

---

## 1. How it works

Apple's **App Intents** framework is the one integration point. The app
declares:

- **Intents**: actions with typed parameters and a `perform()` that returns
  a spoken or shown answer, or opens the app somewhere.
- **Entities**: the things intents act on (a Pokémon, a move, a saved set),
  with a query that resolves what someone said ("Mega Charizard X") to one.
- **App Shortcuts**: phrases that work in Siri with no setup, such as "What
  is Garchomp weak to in PK Reference". Apple requires the app's name in
  each phrase.

The system then offers them in Siri, Spotlight, Shortcuts and, on iPhone,
the Action button. With Apple Intelligence on, Siri matches looser requests
to the same intents, and Shortcuts' "Use Model" action can chain them. The
more conversational "new Siri" understands requests through App Intents
too; how freely it uses a custom app's intents depends on the OS version,
so these intents are the foundation either way.

Nothing here is Mac-only. It's built on `main` and ships to both platforms.

**None of Apple's assistant schemas fit.** They cover set domains (mail,
photos, books, browsers, files, journals and the like); a Pokémon reference
isn't one, so the intents are plain App Intents with clear titles and
descriptions.

---

## 2. What the app has to build on

- **`CalcEngine.evaluate(move:attacker:defender:field:)`** is pure and
  doesn't need the main actor. `CalcSide.snapshot()` and
  `MoveData.snapshot()` build its inputs, so an intent can run the same
  calc the screen does, from a `CalcSide` it fills in.
- **`calcStat`** (`PokemonStatsModels.swift`) and
  `ShowdownStatsCalc.calcStatChampions` give final stats for speed
  comparisons.
- **`ChampionsValidator(regulation:)`** checks a set's legality.
- **`TypeChart.bundled`** has every type matchup.
- **`TeamSearchModel.setText(_:)`** takes a plain-language query; the
  on-device model already interprets it (`TeamQueryInterpreter`).

What's missing:

- **Data outside a window.** The SwiftData container is created inside
  `PokedexApp`. Intents that don't open the app need the same store, so it
  moves to one shared place, with its migration fallback intact, and is
  registered with `AppDependencyManager` for intents to take as a
  `@Dependency`.
- **A way to open the app somewhere.** The selected tab is `@State` in
  `ContentView`. An `@Observable` navigator owned by the app (tab to show,
  and a pending request: a Pokémon to open, a Team Search query, a set to
  load into the calc) lets an intent that opens the app say where; the tabs
  consume the pending request when they appear.

---

## 3. Phase 1: the foundation and three actions (one PR)

1. **Shared container and navigator**, as above. No behavior change in the
   app; the full suite and a simulator check prove it.
2. **`PokemonEntity`**, keyed by the Pokémon's PokeAPI id (stable across
   launches), shown as its name with its form. Its query matches names
   loosely: case, accents ("Pokemon"), punctuation ("Mr. Mime"), and forms
   said either way ("Mega Charizard X", "Charizard Mega X", "Alolan
   Ninetales"). Suggestions: the current regulation's roster.
3. **Intents**:
   - **Look Up Pokémon**: answers with its types, what it's weak to and
     resists, and its base stat total, with an option to open its page.
   - **Calculate Damage**: attacker, move, defender; answers with the
     damage range as a percentage and the hits to KO. Uses the calc's mode
     (Champions or mainline) from the Default Generation setting. How it
     picks stats is question §7.1.
   - **Search Teams**: opens Team Search with the query, which its existing
     interpreter handles.
4. **App Shortcuts**, a few phrases each, for example "What is \(Pokémon)
   weak to in PK Reference", "Look up \(Pokémon) in PK Reference", "Search
   teams in PK Reference".
5. **When there's no data yet** (the Pokédex downloads on first launch), an
   intent answers "Open PK Reference once to download its data" rather than
   failing.

The answers are built by plain functions (for example, weaknesses as a
sentence), separate from the intents, so they can be tested directly.

## 4. Phase 2: more actions (one or two PRs)

- **Compare Speed**: "Is Dragapult faster than Tapu Koko?", with each
  one's final speed.
- **Check Legality**: "Is Incineroar legal in Regulation M-C?", from the
  validator, with the reason when it isn't.
- **Saved sets and teams as entities**, from SwiftData by persistent id:
  "Load my Screenshot Test set into the calc" (opens the calc), "Show my
  Sand Offense team".
- **Spotlight indexing** of saved sets and teams (`IndexedEntity`), so they
  show up in Spotlight search by name.

## 5. Phase 3: richer answers

- **Snippet views** (iOS and macOS 26) for answers that read better than
  they sound: the damage range bar, weaknesses as type badges. Small
  SwiftUI views reusing `TypeBadge` and the calc's colors.
- **Parameter prompts and follow-ups**, such as asking for the move when
  only two Pokémon were named.
- Revisit once the conversational Siri is on the owner's devices: which
  requests it maps to these intents, and which descriptions need work.

---

## 6. Checking it

- **Tests** (new `AppIntentsTests`): the answer functions against numbers
  the damage suites already pin; the entity query on awkward names; each
  intent's `perform()` with an in-memory container; the "no data yet"
  answer.
- **Registration**: the build writes the intents and phrases to
  `Metadata.appintents` inside the built app. Reading that shows what the
  system will offer, with no device needed.
- **Siri and Spotlight themselves**: these need a person. The owner tries
  the phrases on the Mac (Siri and Spotlight) and the iPhone. The simulator
  can run Shortcuts but not Apple Intelligence.

---

## 7. Questions to settle first

1. **Stats for Calculate Damage when no set is named.** Options: no
   investment (clear, but rarely what's meant); the most recently saved set
   for that species if there is one, else no investment; or a standard
   spread (full investment in the attacking stat). Whatever it picks, the
   answer says which.
2. **Answer in Siri or open the app?** Proposed: lookups and the calc
   answer in place, with an option to open; Team Search and loading a set
   open the app.
3. **Which actions first.** Proposed: Phase 1's three.
