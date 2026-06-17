---
name: enemy-and-item-expansion
overview: >-
  Add more enemy types to the battlefield, spawn ground items (potions, ammo,
  weapons), and expand weapon variety with different tradeoffs.
createdAt: '2026-06-05T19:05:21.999Z'
todos:
  - id: add-enemies-to-scene
    content: >-
      Add Archer Goblin and Boss Goblin to main.tscn battlefield with balanced
      positions
    status: completed
  - id: spawn-ground-items
    content: >-
      Spawn health potions, ammo packs, and a new weapon on the battlefield at
      startup
    status: completed
  - id: weapon-variety
    content: >-
      Expand weapon types in ItemResource with different stat tradeoffs (Iron
      Sword, Warhammer, Dagger, Battle Axe)
    status: completed
  - id: improve-ai-defend
    content: >-
      Fix enemy defense not using inventory weapon checks (boss uses parry but
      has no inventory weapon)
    status: cancelled
  - id: run-and-verify
    content: Run the game and verify all new content compiles and plays correctly
    status: completed
---
## Scene additions

### New enemies (3D positions on grid):
- Goblin Archer: position (-4, 1.1, 6), enemy_type=ARCHER (teal-green, smaller scale)
- Goblin Boss: position (7, 1.1, -2), enemy_type=BOSS (dark red, larger scale)

### Ground items spawned at startup:
- Health Potion at (-2, 0.2, 5): CONSUMABLE, heal_amount=8
- Arrow Bundle at (3, 0.2, -3): AMMO, ammo_amount=4
- Warhammer at (1, 0.2, -5): WEAPON, ATK+1, DMG+3, durability=8, slower but harder hitting

### Weapon variety expansion:
Add to ItemResource or create items with different profiles:
- Iron Sword: ATK+2, DMG+1, durability=10 (balanced, existing)
- Warhammer: ATK+1, DMG+3, durability=8 (slow, heavy)
- Dagger: ATK+4, DMG+0, durability=5 (fast, fragile)
- Battle Axe: ATK+3, DMG+2, durability=6 (aggressive, breaks fast)

### Enemy defense fix:
The Boss enemy has defensive_option=0 (Parry) and has_weapon=true, but no inventory weapon. The _attempt_defense function checks has_weapon which doesn't degrade through inventory. Fix by making enemies use inventory system for weapons, or fix the defense check to work with their native weapon_durability.
