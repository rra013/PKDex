# Damage Calculator — Ability Reference

This document lists every competitively relevant ability and whether it is implemented in the damage calculator, how it works, and any simplifications made.

## Legend

- **Implemented** — Fully modeled in `computeAbilityModifiers()`
- **Simplified** — Implemented but with approximations (e.g. always-on when it should be conditional on move flags)
- **Not Implemented** — Not in the calculator (with reason)

---

## Attacker Abilities

### Stat Multipliers

| Ability | Status | How it works | Notes |
|---------|--------|--------------|-------|
| **Huge Power** | Implemented | 2x physical Attack | — |
| **Pure Power** | Implemented | 2x physical Attack | Identical to Huge Power |
| **Hustle** | Implemented | 1.5x physical Attack | Accuracy drop not modeled (irrelevant to damage) |
| **Gorilla Tactics** | Implemented | 1.5x physical Attack | Move-lock not modeled |
| **Solar Power** | Implemented | 1.5x Sp.Atk in Sun | HP drain not modeled |

### STAB Modifiers

| Ability | Status | How it works | Notes |
|---------|--------|--------------|-------|
| **Adaptability** | Implemented | STAB becomes 2.0x (from 1.5x) | — |
| **Protean** | Implemented | Grants STAB on every move | User's type changes to match the move, so every attack gets 1.5x STAB |
| **Libero** | Implemented | Grants STAB on every move | Identical to Protean (Gen IX limited to once per switch-in; simplified) |

### Type-Boosting (Power Multipliers)

| Ability | Status | How it works | Notes |
|---------|--------|--------------|-------|
| **Transistor** | Implemented | 1.3x Electric moves | — |
| **Dragon's Maw** | Implemented | 1.5x Dragon moves | — |
| **Steelworker** | Implemented | 1.5x Steel moves | — |
| **Dark Aura** | Implemented | 1.33x Dark moves (field-wide) | Aura Break inversion not modeled |
| **Fairy Aura** | Implemented | 1.33x Fairy moves (field-wide) | Aura Break inversion not modeled |
| **Water Bubble** | Implemented | 2x Water moves (attacker) + halves Fire damage (defender) | Both sides handled |
| **Sand Force** | Implemented | 1.3x Rock/Ground/Steel moves in Sandstorm | — |

### Pinch Abilities (1/3 HP trigger)

| Ability | Status | How it works | Notes |
|---------|--------|--------------|-------|
| **Blaze** | Implemented | 1.5x Fire moves at low HP | Triggered when "At Full HP" is unchecked |
| **Torrent** | Implemented | 1.5x Water moves at low HP | Same trigger |
| **Overgrow** | Implemented | 1.5x Grass moves at low HP | Same trigger |
| **Swarm** | Implemented | 1.5x Bug moves at low HP | Same trigger |

### Move-Category Boosters

| Ability | Status | How it works | Notes |
|---------|--------|--------------|-------|
| **Technician** | Implemented | 1.5x moves with BP ≤ 60 | Checks base power directly |
| **Tough Claws** | Implemented | 1.3x contact moves | Uses `makesContact` flag |
| **Iron Fist** | Simplified | 1.2x always applied | Should only apply to punching moves; no move flag available |
| **Strong Jaw** | Simplified | 1.5x always applied | Should only apply to biting moves; no move flag available |
| **Mega Launcher** | Simplified | 1.5x always applied | Should only apply to pulse/aura moves; no move flag available |
| **Punk Rock** | Simplified | 1.3x attack / 0.5x defense always applied | Should only apply to sound moves; no move flag available |
| **Reckless** | Simplified | 1.2x always applied | Should only apply to recoil moves; no move flag available |
| **Sheer Force** | Simplified | 1.3x always applied | Should only apply to moves with secondary effects; no flag available. Also removes Life Orb recoil (not modeled) |

### Type-Changing Abilities (–ate)

| Ability | Status | How it works | Notes |
|---------|--------|--------------|-------|
| **Aerilate** | Implemented | Normal→Flying + 1.2x boost | Type change must be done manually by user; power boost is applied when move type is Normal |
| **Pixilate** | Implemented | Normal→Fairy + 1.2x boost | Same |
| **Refrigerate** | Implemented | Normal→Ice + 1.2x boost | Same |
| **Galvanize** | Implemented | Normal→Electric + 1.2x boost | Same |
| **Normalize** | Implemented | All moves→Normal + 1.2x boost | Type change must be done manually; 1.2x power boost applied |

### Conditional / Situational

| Ability | Status | How it works | Notes |
|---------|--------|--------------|-------|
| **Analytic** | Simplified | 1.3x always applied | Should only apply when moving last; user responsible for toggling |
| **Stakeout** | Simplified | 2.0x always applied | Should only apply when target switched in this turn |
| **Supreme Overlord** | Simplified | 1.1x always applied | Actually 1.1x per fainted ally (up to 1.5x for 5 fainted); simplified to 1 fainted |
| **Tinted Lens** | Implemented | 2x damage on "not very effective" hits | Doubles the final multiplier when type effectiveness < 1.0 |
| **Sniper** | Implemented | Crit multiplier becomes 2.25x (from 1.5x) | Only active when Crit toggle is on |

---

## Defender Abilities

### Damage Reduction

| Ability | Status | How it works | Notes |
|---------|--------|--------------|-------|
| **Multiscale** | Implemented | 0.5x damage at full HP | Uses "At Full HP" toggle |
| **Shadow Shield** | Implemented | 0.5x damage at full HP | Identical to Multiscale |
| **Filter** | Implemented | 0.75x super-effective damage | — |
| **Solid Rock** | Implemented | 0.75x super-effective damage | Identical to Filter |
| **Prism Armor** | Implemented | 0.75x super-effective damage | Identical to Filter |
| **Fluffy** | Implemented | 0.5x contact damage, 2x Fire damage | Both effects applied |
| **Heatproof** | Implemented | 0.5x Fire damage | — |
| **Water Bubble** | Implemented | 0.5x incoming Fire damage | Attacker side (2x Water) also handled |
| **Punk Rock** | Simplified | 0.5x always applied as defender | Should only apply to sound moves; no flag available |

### Stat Modifiers (Defense)

| Ability | Status | How it works | Notes |
|---------|--------|--------------|-------|
| **Fur Coat** | Implemented | 2x physical Defense | — |
| **Ice Scales** | Implemented | 2x special Defense (effectively) | Applied as Def multiplier on special moves |
| **Marvel Scale** | Simplified | 1.5x physical Defense always | Should only activate when the Pokemon has a status condition |
| **Thick Fat** | Implemented | Halves effective Atk of Fire/Ice moves | Applied as 0.5x to attacker's Atk stat |

### Type Immunities

| Ability | Status | How it works | Notes |
|---------|--------|--------------|-------|
| **Levitate** | Implemented | Immune to Ground | Sets type effectiveness to 0 |
| **Flash Fire** | Implemented | Immune to Fire | Sets type effectiveness to 0 |
| **Water Absorb** | Implemented | Immune to Water | Sets type effectiveness to 0 |
| **Storm Drain** | Implemented | Immune to Water | Same as Water Absorb + Sp.Atk boost (boost not modeled) |
| **Volt Absorb** | Implemented | Immune to Electric | Sets type effectiveness to 0 |
| **Lightning Rod** | Implemented | Immune to Electric | Same as Volt Absorb + Sp.Atk boost (boost not modeled) |
| **Motor Drive** | Implemented | Immune to Electric | Same as Volt Absorb + Speed boost (boost not modeled) |
| **Sap Sipper** | Implemented | Immune to Grass | Sets type effectiveness to 0 |
| **Dry Skin** | Implemented | Immune to Water + 1.25x Fire damage | Both effects modeled |
| **Wonder Guard** | Implemented | Immune to non-super-effective moves | Only super-effective hits deal damage |

---

## Abilities NOT Implemented (and why)

These abilities exist on Pokemon in the database but are **not** modeled in the damage calculator because they don't directly affect the damage formula, or their effect is too situational/complex to meaningfully approximate.

### Battle Mechanics (no damage formula impact)

| Ability | Reason not implemented |
|---------|----------------------|
| **Intimidate** | Lowers opponent's Attack by 1 stage on switch-in. User can manually set stat stages. |
| **Download** | Raises Atk or SpAtk based on opponent's lower stat. User can set stat stages. |
| **Beast Boost** | Raises highest stat on KO. User can set stat stages. |
| **Moxie** | Raises Atk on KO. User can set stat stages. |
| **Soul-Heart** | Raises SpAtk on KO. User can set stat stages. |
| **Speed Boost** | Raises Speed each turn. User can set stat stages. |
| **Moody** | Random stat changes. User can set stat stages. |
| **Competitive** | +2 SpAtk when a stat is lowered. User can set stat stages. |
| **Defiant** | +2 Atk when a stat is lowered. User can set stat stages. |
| **Clear Body / White Smoke / Full Metal Body** | Prevents stat drops. Not a damage modifier. |
| **Unaware** | Ignores opponent's stat stage changes. Too complex to model cleanly—user can zero out stages manually. |

### Speed / Priority / Turn Order

| Ability | Reason not implemented |
|---------|----------------------|
| **Prankster** | +1 priority to status moves. No damage impact. |
| **Gale Wings** | +1 priority to Flying moves at full HP. No damage impact. |
| **Triage** | +3 priority to healing moves. No damage impact. |
| **Quick Draw** | Random chance to move first. No damage impact. |
| **Stall** | Always moves last. No damage impact. |
| **Mycelium Might** | Status moves ignore abilities but go last. No damage impact. |

### Entry Hazards / Weather / Terrain

| Ability | Reason not implemented |
|---------|----------------------|
| **Drought / Drizzle / Sand Stream / Snow Warning** | Sets weather. User can set weather manually. |
| **Electric Surge / Grassy Surge / Misty Surge / Psychic Surge** | Terrain effects not modeled in calc. |
| **Desolate Land / Primordial Sea / Delta Stream** | Primal weather. User can approximate with weather toggle. |

### Healing / Residual Damage

| Ability | Reason not implemented |
|---------|----------------------|
| **Regenerator** | Heals 1/3 HP on switch. No damage formula impact. |
| **Poison Heal** | Heals from poison instead of taking damage. Not a damage modifier. |
| **Rain Dish / Ice Body** | Small HP recovery in weather. Not a damage modifier. |
| **Magic Guard** | Prevents indirect damage (not direct hits). Not a damage formula modifier. |

### Defensive Utility (non-damage)

| Ability | Reason not implemented |
|---------|----------------------|
| **Sturdy** | Survives at 1 HP from full. Not a damage modifier. |
| **Disguise** | Blocks one hit (Mimikyu). Not a damage multiplier. |
| **Ice Face** | Blocks one physical hit (Eiscue). Not a damage multiplier. |
| **Magic Bounce** | Reflects status moves. No damage impact. |
| **Natural Cure** | Heals status on switch. No damage impact. |

### Ability Suppression / Modification

| Ability | Reason not implemented |
|---------|----------------------|
| **Mold Breaker / Teravolt / Turboblaze** | Ignores defender abilities. User can manually set defender ability to "None". |
| **Neutralizing Gas** | Suppresses all abilities. User can set abilities to "None". |
| **Aura Break** | Reverses Dark Aura / Fairy Aura. Too niche to implement. |

### Other

| Ability | Reason not implemented |
|---------|----------------------|
| **Parental Bond** | Hits twice (second hit at 0.25x). Modeled as a separate toggle in Modifiers, not an ability. |
| **Skill Link** | Multi-hit moves always hit 5 times. Not a damage-per-hit modifier. |
| **Compound Eyes / No Guard** | Accuracy changes. No damage impact. |
| **Trace / Imposter / Illusion** | Copy/disguise abilities. No damage formula impact. |
| **Slow Start** | Halves Atk/Speed for 5 turns. User can approximate with stat stages. |
| **Defeatist** | Halves Atk/SpAtk below 50% HP. Could be implemented; user can approximate with "At Full HP" off + manual adjustment. |
