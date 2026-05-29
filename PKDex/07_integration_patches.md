# PKReference Integration Patches

Small edits to existing PKReference files to wire up the AI Builder. Each patch is shown as a before/after snippet; apply them in order.

---

## 1. `SetBuilder.swift` — add AI button to `NewSetSheet`

The `NewSetSheet` already has a Cancel/Save toolbar. Add an "AI Generate" button as a `.bottomBar` placement (or in the Pokemon section header — your call). Easiest insertion point is right after the navigation title modifier inside `NewSetSheet.body`.

**Find:**
```swift
.navigationTitle("New Set")
.navigationBarTitleDisplayMode(.inline)
.toolbar {
    ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
```

**Replace with:**
```swift
.navigationTitle("New Set")
.navigationBarTitleDisplayMode(.inline)
.toolbar {
    ToolbarItem(placement: .principal) {
        AIBuilderButton(mode: .singleSet) { result in
            switch result {
            case .success(let generatedSet):
                applyGeneratedSet(generatedSet)
            case .failure:
                break  // sheet shows its own error UI
            }
        }
    }
    ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
```

Then **add this method** to `NewSetSheet` (above `saveAndDismiss`):

```swift
private func applyGeneratedSet(_ generated: PokemonSet) {
    // Find matching Pokemon in the SwiftData store
    if let match = allPokemon.first(where: { $0.name == generated.species }) {
        side.pokemon = match
        side.selectedAbility = generated.ability
        side.heldItem = HeldItem(rawValue: generated.item ?? "") ?? .none
        side.nature = allNatures.first(where: { $0.name == generated.nature })
                  ?? side.nature
        side.championsMode = true  // AI builder always uses Champions scale
        side.evHP = generated.statPoints.hp
        side.evAtk = generated.statPoints.atk
        side.evDef = generated.statPoints.def
        side.evSpAtk = generated.statPoints.spa
        side.evSpDef = generated.statPoints.spd
        side.evSpeed = generated.statPoints.spe
        side.ivHP = 31; side.ivAtk = 31; side.ivDef = 31
        side.ivSpAtk = 31; side.ivSpDef = 31; side.ivSpeed = 31

        // Resolve moves by name
        for i in 0..<4 {
            let moveName = i < generated.moves.count ? generated.moves[i] : ""
            side.moves[i] = allMoves.first(where: { $0.name == moveName })
        }

        // Suggest a name based on species + a qualifier
        if name.isEmpty {
            name = "\(generated.species) (AI)"
        }
    }
}
```

**Note on item mapping:** `HeldItem` in PKReference is a narrow enum (Choice Band, Specs, Life Orb, etc.). The AI model can emit items outside that list (Gardevoirite, Choice Scarf, Sitrus Berry, etc.). For v1, items not in the enum fall through as `.none` — the user can adjust in the sheet. Long-term, expand `HeldItem` to cover the full Champions item pool, or split `selectedItemName: String?` off as a separate field.

---

## 2. `TeamBuilder.swift` — add AI button to `NewTeamSheet`

Same idea but for teams. The current single-set generator returns one set at a time, so for v1 the team button just opens the single-set sheet repeatedly — the user picks "Use this set" and it's added as a team member, then they can tap AI again to add another.

**Find this block in `NewTeamSheet.body`'s toolbar:**
```swift
ToolbarItem(placement: .cancellationAction) {
    Button("Cancel") {
        if hasChanges {
```

**Add this `ToolbarItem` right above it:**
```swift
ToolbarItem(placement: .principal) {
    AIBuilderButton(mode: .singleSet) { result in
        if case .success(let generatedSet) = result {
            appendGeneratedToTeam(generatedSet)
        }
    }
}
ToolbarItem(placement: .cancellationAction) {
    Button("Cancel") {
        if hasChanges {
```

Then **add this method** to `NewTeamSheet`:

```swift
private func appendGeneratedToTeam(_ generated: PokemonSet) {
    guard slots.count < 6 else { return }
    guard let pokemon = allPokemon.first(where: { $0.name == generated.species })
    else { return }
    // Build a TeamSlotInfo from scratch (we don't go through SavedSpread
    // for AI-generated members)
    let moveSlots: [TeamMoveInfo] = generated.moves.compactMap { moveName in
        guard let move = allMoves.first(where: { $0.name == moveName })
        else { return nil }
        let types = [pokemon.type1] + [pokemon.type2].compactMap { $0 }
        return TeamMoveInfo(
            moveID: move.id, moveName: move.name, moveType: move.type,
            damageClass: move.damageClass, power: move.power,
            isSTAB: move.damageClass != "status" && types.contains(move.type)
        )
    }
    let slot = TeamSlotInfo(
        spreadName: "\(generated.species) (AI)",
        pokemonID: pokemon.id,
        pokemonName: pokemon.name,
        type1: pokemon.type1, type2: pokemon.type2,
        abilityName: generated.ability,
        itemRawValue: generated.item,
        championsMode: true,
        natureID: allNatures.first(where: { $0.name == generated.nature })?.id
                  ?? "adamant",
        level: 50,
        evHP: generated.statPoints.hp, evAtk: generated.statPoints.atk,
        evDef: generated.statPoints.def, evSpAtk: generated.statPoints.spa,
        evSpDef: generated.statPoints.spd, evSpeed: generated.statPoints.spe,
        moveSlots: moveSlots
    )
    slots.append(slot)
}
```

---

## 3. `SettingsView.swift` — add download UI

Find the existing `Form { ... }` body. Add a new section anywhere appropriate (between "Data Management" and "About" is natural):

**Find:**
```swift
// MARK: - Disclaimers
Section("About") {
```

**Insert above:**
```swift
// MARK: - AI Builder
AIModelDownloadView()

// MARK: - Disclaimers
Section("About") {
```

That's it — `AIModelDownloadView` returns a `Section` itself, so it slots straight into a `Form`.

---

## 4. Xcode project setup

A few one-time changes outside of code:

### 4a. Add MLX Swift Examples as a package dependency

In Xcode: **File → Add Package Dependencies**

URL: `https://github.com/ml-explore/mlx-swift-examples`

Version: latest (works with current MLX Swift; pin to a tag if you want reproducibility).

When prompted, check these products and add them to the PKReference target:
- `MLXLLM`
- `MLXLMCommon`
- `MLXTokenizers`
- `Tokenizers` (transitive dep, may auto-add)

### 4b. Add the validator data files to the bundle

Drop these into the Xcode project (drag into the Project navigator, check "Copy items if needed" and the PKReference target):

- `champions-m-a.json` — copy from `pokemon-llm-training/data/champions-m-a.json`
- `champions-m-a-learnsets.json` — copy from the training repo
- `move_categories.json` — generate via this Python one-liner from your scraped move data:

```bash
cd pokemon-llm-training
python3 -c "
import json
moves = json.load(open('data/moves.json'))
out = {m['name']: m['category'] for m in moves
       if m.get('category') in ('physical', 'special', 'status')}
json.dump(out, open('data/move_categories.json', 'w'))
print(f'wrote {len(out)} moves')
"
```

These files are small (~600 KB combined) and live happily in the app bundle. They're used by `ChampionsValidator` and `MoveCategories` to enforce legality and coherence on every AI-generated set.

### 4c. Increase iOS deployment target

MLX Swift requires iOS 16 minimum. PKReference is already targeting recent iOS, but verify in the project settings:

**Target → General → Minimum Deployments → iOS 16.0 or later**

### 4d. Enable "Increased Memory Limit" capability

The model takes ~4 GB resident. iOS will OOM-kill the app without this entitlement.

**Target → Signing & Capabilities → + Capability → Increased Memory Limit**

This is allowed only on iPhone (not iPad), which is fine for v1. iPad needs separate handling — MLX Swift works there too, just verify the device has 6 GB RAM minimum (iPad Pro M-series, or recent base iPads).

### 4e. Background download support (optional but recommended)

If you want the 5 GB download to continue when the user backgrounds the app:

**Target → Signing & Capabilities → + Capability → Background Modes**, check **Background fetch** and **Background processing**.

Then in `PokiiModelDownloader`, change the URLSessionConfiguration to `.background(withIdentifier: "ai.pkreference.modeldownload")`. This is a meaningful refactor — the delegate model differs — so I left it out of v1. Users currently need to keep the app foreground for the download.

---

## 5. Quick smoke test before shipping

Build & run on a real device (the simulator can run MLX in theory but is slow and doesn't reflect real memory pressure). On first launch:

1. Go to Settings → AI Builder → tap Download. Wait ~10 minutes on wifi.
2. Tap Sets → tap +. The AI Generate button should appear in the toolbar.
3. Type "bulky Gardevoir" and tap Generate.
4. Confirm the returned set has reasonable values (Calm/Bold nature, defensive stat point spread, defensive moves like Wish/Protect/Moonblast/Will-O-Wisp).
5. Tap "Use this set" — verify it populates the form correctly.
6. Tap Save — confirm it persists.

Test failure modes:
- Airplane mode + tap Generate → should fail cleanly (model is already loaded, generation works offline, so this should actually succeed; airplane mode only breaks download).
- Delete model in Settings, then tap AI Generate button → should show the "go to Settings" alert, not crash.
- Type junk like "asdfghjkl" → should fail after max retries with a clean error message rather than returning garbage.

---

## 6. What's deliberately NOT in v1

Acknowledging the scope gaps so you can prioritize:

- **Team-level prompts.** "Build me a Trick Room team" → the current setup makes 6 sequential single-set calls and lets the user pick. A real team builder would generate 6 sets in one call with awareness of synergy. That's a separate training run for a team-output model, not just an inference change.
- **Streaming generation.** Current UX shows a single spinner. Token-by-token streaming would feel snappier but requires a different `MLXLMCommon.generate` callback pattern. Worth doing in v1.1.
- **History.** Generated sets aren't saved unless the user taps "Use this set." A "recent AI generations" list would help iteration.
- **Item field expansion.** `HeldItem` enum is too narrow — see note in patch 1.
- **iPad memory handling.** Untested; may need device-class gating.

These are all small follow-ups, but each has a real cost. Ship v1 first, see what users actually do with it, then prioritize.
