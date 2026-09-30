# Problem Solver: implementation plan

Status: **Phases 1 and 2 built** (2026-09-30): the solver
(`ProblemSolver.swift`) and the Problem Solver tab (`ProblemSolverView.swift`),
with `ProblemSolverTests`. **Phase 3 in progress,** one PR per feature (§8):
field options, grouping by Pokémon and the two-hit mode are built; usage
ranking and the Siri action are next. The owner's decisions are in §8; what
building it showed is in §9.

The goal: a player picks a Pokémon set that's giving them trouble, and the
app lists the Pokémon, move and investment combinations that knock it out in
one hit, and says which of them also move first. Each answer can be opened
in the damage calc to check it, or saved as a set.

---

## 1. What it answers

**The problem set** is what the player wants to beat. It's either a saved
set, or a Pokémon with an investment choice, the same choices Siri's calc
offers: no investment, full investment, or full investment and a boosting
nature. That fixes its HP, defenses, Speed, ability and item, and its Mega
when it holds the stone.

**A counter** is a combination the regulation allows:

- a Pokémon, or its Mega
- one of its abilities
- an item
- a nature
- stat points (at most 32 in a stat and 66 in all)
- one move

To count, the move's **lowest damage roll must be at least the problem
set's HP: a guaranteed one-hit KO** (§8).

**The rules are Champions doubles** (§8):

- Level 50, every IV 31, the regulation's stat-point caps.
- Spread moves take the 0.75× doubles reduction, as if both foes are on the
  field. That's the conservative case: a spread move that hits only one foe
  does more.
- The problem set's own ability counts. Intimidate lowers a physical
  counter's Attack by one stage, with a switch to turn it off (§8).
- No weather, terrain or partner support by default. These are options for
  later (§6).
- "Guaranteed" means no critical hit and the lowest roll. Accuracy isn't
  rolled, but a move under 100% accuracy is marked. So are moves with
  drawbacks: must recharge (Hyper Beam), faints the user (Explosion),
  charges first (Solar Beam without sun).

**Results come in three groups:**

1. **Outspeeds and OHKOs.** It moves first and wins outright.
2. **OHKOs with priority.** A move such as Sucker Punch or Extreme Speed
   gets there first regardless of Speed.
3. **OHKOs but slower.** It needs Trick Room, Tailwind or a switch-in to
   get the hit off.

Within a group, results are ranked by fewest stat points, then accuracy,
then drawbacks.

---

## 2. Heuristic or brute force

**Brute force, pruned by a heuristic.** The owner's idea was to check
Pokémon with a super-effective STAB move, using their strongest move at full
investment, then scale the investment down. That idea stays, but as the
order of the search and a cheap filter, not as the rule for what counts.
Checking only super-effective STAB moves would miss real answers and give
wrong ones:

- **A neutral move can beat a super-effective one.** A 120-power neutral
  move with Adaptability, a Pixilate-type ability or Huge Power can hit
  harder than a weak super-effective one.
- **Megas change the stats and abilities.**
- **The problem set can change the numbers.** Multiscale, Thick Fat,
  Levitate and Flash Fire; Intimidate; the spread reduction.
- **The strongest move isn't always usable.** Explosion, Hyper Beam and
  two-turn moves are traps. Body Press, Foul Play and Psyshock use
  unexpected stats; `EVSolver` already detects which stat matters.

**It's cheap enough to check everything.** Measured on 2026-09-30 in the app
on the simulator, debug build: every Champions M-C roster Pokémon's damaging
moves against a fully invested Incineroar, doubles, was 11,552 calcs in
0.47 s, about 41 µs each. The full search is:

- **The first pass:** 231 species × their legal damaging moves (9,154 pairs,
  about 40 each), each of their abilities (2.45 on average), plus 81 Megas.
  That's about 30,000 calcs, around 1.2 s.
- **Scaling down:** for each OHKO found, scanning 33 attack values, usually
  a few hundred OHKOs. That's under 0.5 s.

A pruning bound (§3.2) can cut the first pass if an iPhone release build
turns out slower. Measure that before building the screen.

---

## 3. The search

### 3.1 Candidates

Everything comes from the regulation's files, through
`ChampionsLearnsetStore`, so a new regulation needs no changes here:

- **Pokémon:** the roster, its Megas (when the rules allow Mega Evolution;
  Mega Rayquaza has its own switch) and its alternate forms. Match
  regulation names to the Pokédex's by `IntentNames.key`, as Check Legality
  does. The benchmark's plain name match found 216 of the 231.
- **Moves:** each Pokémon's legal damaging moves. A Mega uses its base
  form's moves.
- **Abilities:** each of its legal abilities. A Mega has its own.
- **Items:** the move type's 1.2× booster. M-C has one for every type
  (Charcoal, Mystic Water, Spell Tag and the rest), and nothing stronger:
  no Life Orb, Choice Band or Choice Specs. A Normal move also tries Normal
  Gem. A Mega holds its stone. Choice Scarf is a Speed option (§3.4, §8).

### 3.2 Pruning (optional)

An upper bound on damage from plain arithmetic:

- power
- STAB, at the most any ability makes it
- type effectiveness
- the highest attacking stat 32 points and a boosting nature allow
- the item
- the largest multiplier any legal ability gives

Measured against the problem set's HP and its lower defense (Psyshock-style
moves use the other), anything that can't reach the HP is skipped. The
bound must never undercount, or it would drop real answers. A test compares
it against the exact calc for every pair in the benchmark.

### 3.3 The exact check

Each surviving candidate runs through `CalcEngine.evaluate`, the same door
the calc screen and `EVSolver` use. It gets 32 points in the attacking stat,
a boosting nature and the item. It's kept when `damageMin >= defenderHP`.

### 3.4 Scaling down, and Speed

For each OHKO:

1. **Attack points.** `EVSolver`'s KO goal finds the fewest attacking points
   that still guarantee it. It scans all 33 values, because damage isn't
   always even in the stat.
2. **The problem set's Speed.** Its final Speed: points, nature, Mega and
   Choice Scarf, through `applySpeedModifiers`.
3. **Speed points.** `EVSolver`'s outspeed goal finds the fewest Speed
   points to be strictly faster. A tie is marked as a tie, not a win. A
   priority move skips this step.
4. **Nature.** Try both an attacking nature and a Speed nature (Adamant or
   Modest vs Jolly or Timid). Keep whichever meets the goals with fewer
   points in all.
5. **Budget.** Attack and Speed points together must fit in 66, and each in
   32. If outspeeding doesn't fit, the result goes in "OHKOs but slower",
   with the points it would need.
6. **Choice Scarf** (§8): a second pass for results that can't outspeed,
   holding Scarf instead of the booster. They're only kept if the OHKO
   still holds without the booster.

### 3.5 Running it

- **Off the main thread.** `CalcEngine` and `EVSolver` are `nonisolated`,
  and candidates are built on the main actor as `Sendable` snapshots, as
  `EVSolver` does.
- **Results appear as they're found.** A change to the problem set
  cancels the run and starts again.
- **Results are cached** by the problem set's snapshot and the regulation.

---

## 4. The screen

A **Problem Solver** tab (`AppTab.problemSolver`), in the tab bar on iPad
and the Mac sidebar, and in More on the iPhone by default.

- **Problem.** A saved set, or a Pokémon with an investment choice. It shows
  the resulting HP, Def, SpD and Speed, and its ability and item.
- **Options.** The regulation (from Settings) and the Intimidate switch;
  field options later (§6).
- **Results.** The three groups, each as a list. A row shows:
  - the Pokémon (or Mega), with type badges
  - the move and its item
  - the ability and nature
  - the points ("28 SpA / 20 Spe")
  - the damage range as a percentage
  - Speed against the problem set's

  Marks show accuracy under 100%, drawbacks and ties.
- **Row actions:**
  - **Open in Damage Calc** loads both sides exactly as solved. That needs
    a `CalcRequest` that carries full spreads, not just the investment
    choices.
  - **Save as Set.**
- **Mac and iPad:** a list and detail split, like the other tabs, with the
  calc numbers in the detail.

---

## 5. What already exists

- **`CalcEngine.evaluate`:** pure and `nonisolated`, with the Champions
  port and the legacy engine behind one door.
- **`EVSolver`:** "KO a target" and "outspeed" goals, exhaustive scans, and
  probing for which stat a move uses.
- **`ChampionsLearnsetStore` and the regulation JSONs:** legal moves,
  abilities, Megas and forms. **`ChampionsValidator`** for legality.
- **`MegaForms`** and **`CalcSide.loadUninvested`**, which already loads a
  Mega as its species holding the stone, Mega Evolved.
- **`SpreadMoves`**, the 0.75× reduction (`FieldSnapshot.multi`) and
  **`applySpeedModifiers`**.
- **`AppNavigator`** and **`CalcRequest`**, for opening the calc.

---

## 6. Phases

1. **The solver** (one PR):
   - candidates from the regulation, the exact check, scaling down, Speed,
     the budget and the groups
   - pure, and tested apart from any screen
   - a timing test on the full roster
2. **The screen** (one PR): the tab, choosing the problem set, the results,
   Open in Damage Calc (the spread-carrying `CalcRequest`), Save as Set, and
   the Mac and iPad layouts.
3. **Extras** (one PR each, in this order):
   - **Built:** field options (weather, terrain, Helping Hand, Tailwind,
     Trick Room), and answers grouped by Pokémon, a Pokémon's other moves
     behind "N more".
   - **Built:** a two-hit mode (§8.8).
   - Ranking by tournament usage (§8.9; Limitless data is already in the
     app).
   - A Siri action: "PK Reference, what beats Incineroar?", answering with
     the top three in place, like the others (§8.10).

---

## 7. Checking it

- **Known matchups,** pinned against the calc screen's numbers: an OHKO, a
  near miss that must be excluded (its lowest roll one point short), a
  spread move under 0.75×, Intimidate, a Mega, a priority move and a speed
  tie.
- **Scaling down:** the points found are the fewest. One fewer point must
  fail, checked by the calc.
- **The pruning bound** never undercounts, checked against every pair in
  the benchmark.
- **Timing:** the full roster sweep within a budget on the simulator, and
  measured once on an iPhone release build.
- **Spot checks:** open a few results in the calc and compare.

---

## 8. Decisions

All settled with the owner on 2026-09-30:

1. **Champions doubles** rules (§1).
2. **Guaranteed OHKO only:** the lowest roll must KO.
3. **Brute force, pruned by the owner's heuristic** (§2).
4. **The problem set's Intimidate applies** to physical counters, with a
   switch to turn it off.
5. **Items:** the move type's booster, or a Mega's stone. **Choice Scarf is
   an extra pass** for counters that can't otherwise outspeed.
6. **Both natures are tried,** attacking and Speed, and the one needing
   fewer points in all is kept.
7. **Where the tab lives:** in More on the iPhone, in the bar on iPad and
   the Mac.

Settled for Phase 3, also on 2026-09-30:

8. **Two-hit mode: fast, then verify.** Two lowest rolls must reach the
   target's HP, across the whole roster. When the target has something that
   acts between hits (Sitrus Berry, Leftovers, Multiscale), each answer is
   re-checked in the battle simulator, as `TwoHitSolver` does.
9. **Usage is a sort option:** "Fewest points" (as now) or "Most used",
   from the Limitless data Team Search downloads, with each row showing the
   Pokémon's usage.
10. **Siri asks for the target's investment** each time: no investment,
    full HP and Defense, full HP and Sp. Def, or a saved set of that
    Pokémon.
11. **One PR per feature.**

---

## 9. What building Phase 1 showed

- **Speed:** 25,922 candidates (all 231 M-C species, their forms and
  Megas, each ability and legal damaging move) are built in 0.2 s and
  solved in 1.9 s, against full HP and Defense Incineroar, in a debug build
  on the simulator. The pruning bound (§3.2) isn't needed, so it isn't
  built.
- **Negative priority.** Focus Punch (−3) came out as outspeeding at first.
  A move with negative priority goes last whatever the Speeds, so it's
  "slower" and marked as moving last. Focus Punch is also marked as failing
  if the user is hit (`fails_if_hit_moves` in `battle_moves.json`, beside
  the new `recharge_moves` and `self_ko_moves`).
- **Intimidate cuts both ways.** Against Intimidate Incineroar, Competitive
  Empoleon and Defiant Falinks are among the best answers, because
  Intimidate powers them up. `ProblemSolver.intimidated(ability:)` covers
  the blocking abilities (Clear Body, Inner Focus and the like), Defiant,
  Competitive, Contrary, Guard Dog, Simple and Rattled.
- **Sharing work.** Abilities that give the same damage at full investment
  share one scaling down, and are listed together on one answer.
- **Speed and the budget.** Only two stats are ever solved, each at most 32,
  so they always fit in 66. The only limit that matters is 32 in Speed.
- **The screen reuses the calc's editor.** The set to beat is a calc
  `SideCard` without its moves, so loading, pasting, saving, Megas, stages
  and side conditions (Reflect, Light Screen) all work as in the calc, and
  the solver honours them. It's held to Champions rules.
- **Opening an answer in the calc** uses `CalcSides`: both sides captured
  whole as `SideSetup`s, with doubles on. On the iPhone, Empoleon's Surf
  against Intimidate Incineroar opened at 218–258 (107.9–127.7%), exactly as
  the solver had it.
- **Running it:** `ProblemSolverModel` solves 0.4 s after the last edit, off
  the main thread (`@concurrent`), cancelling the last run, with the
  candidates cached per regulation. Results arrive together rather than
  streaming, since the whole search is a second or two.
- **`-debugNavigate problem:Incineroar,intimidate,bulky`** opens the tab on a
  set, through `AppNavigator.Request.problemSolver`, which a Siri "what
  beats X" action can use later.
- **Field options** (Phase 3): weather and terrain go on the field;
  Helping Hand and Tailwind on each counter. Under Trick Room the slower
  Pokémon moves first, so only a nature lowering Speed is tried (Brave,
  Quiet, Relaxed), with no Speed points, and Choice Scarf is skipped.
  Psychic Terrain stops priority moves hitting a grounded target, so they
  aren't answers then. A two-turn move that weather skips (Solar Beam in
  sun) loses its "charges first" mark in that weather. Answers open in the
  calc with the same weather and terrain.
- **Two hits** (Phase 3): the same move on two turns running, so moves
  that recharge, faint the user, only work on the first turn or charge
  first (unless the weather skips it) are left out. The fast check runs
  over the whole roster and allows for what the battle simulator models
  between hits: the second hit comes after Multiscale or Shadow Shield and
  a resist berry are spent, after Knock Off takes the item, and after the
  attacker's own drops (Draco Meteor); a Sitrus or Oran Berry heals at
  half HP, then Leftovers or Grassy Terrain at the end of the turn. Every
  first-hit roll is tried, so a bigger first hit setting off the berry is
  caught. Points are found by halving the range (ten times as many answers
  as one hit); where more points don't always help, an answer can be a
  point or two above the fewest, never below what KOs.
- **The simulator re-check:** when anything acts between the hits, every
  answer is played out in the battle simulator (`TwoHitSolver.simulate`)
  at the worst first roll and the lowest, and given more points if it
  needs them. Answers show as soon as the fast check has them; the screen
  shows the simulator's progress. Against full HP and Defense Intimidate
  Incineroar with a Sitrus Berry, M-C has 584 answers from 196 Pokémon:
  2.1 s for the fast check and half a second for the simulator (debug
  build), which confirmed every one as it was. Helping Hand isn't in the simulator, so with it on
  the fast check stands, and the answer says so.
- **Running it on the main actor** (the simulator's damage goes through
  `DamageCalcVM`): yielding after every answer cost a pass of the run loop
  each, and the re-check took over 15 s in the app. It now works in 25 ms
  slices, and the progress bar is its own view so it doesn't redraw the
  list.
- **Two simulator bugs the re-check found,** both fixed: the calc reported
  a move's effectiveness from its listed type, so a Liquid Voice Psychic
  Noise read as having no effect on Dark types and the simulator skipped
  it (the Showdown port now returns the move's final type and
  effectiveness); and the simulator added Knock Off's 1.5× on top of the
  Champions calc's own.
