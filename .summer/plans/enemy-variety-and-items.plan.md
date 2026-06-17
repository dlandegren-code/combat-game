---
name: enemy-variety-and-items
overview: >-
  Add enemy variety (Archer Goblin, Boss), consumable item support, and world
  item spawns
createdAt: '2026-06-05T18:56:15.552Z'
todos:
  - id: consumable-support
    content: >-
      Extend ItemResource with heal/ammo fields and add consume logic to
      InventoryComponent
    status: completed
  - id: enemy-types
    content: >-
      Refactor enemy.gd to support multiple enemy types (Archer, Boss) with
      different stats, AI, and visuals
    status: in_progress
  - id: add-enemies-to-scene
    content: Add ArcherGoblin and Boss enemy instances to main.tscn
    status: pending
  - id: world-item-spawns
    content: >-
      Add WorldSpawner autoload/script that scatters health potions, ammo packs,
      and weapons at combat start
    status: pending
  - id: consumable-use
    content: >-
      Wire up consumable use (health potion heals, ammo pack restores ammo) from
      inventory UI
    status: pending
  - id: weapon-variety
    content: >-
      Add varied weapon pickups with different stat tradeoffs (heavy, light,
      balanced)
    status: pending
  - id: verify
    content: runAndVerify to confirm everything compiles and runs
    status: pending
---
## Enemy variety + items plan

### Enemy types to add
- **ArcherGoblin**: Ranged attacker, stays at range 4-10 tiles, fires arrows, low HP (8), dodge stance
- **Boss**: High HP (30), high armor (3), parry stance with weapon, smart AI (target weakest, shove to separate, attack when adjacent)

### Item types to add
- **Health Potion**: CONSUMABLE, heals 6 HP when used
- **Ammo Pack**: AMMO type, +3 arrows when used
- **Weapon pickups**: Battle Axe (ATK+1, DMG+3, Dur:6), Rapier (ATK+3, DMG+1, Dur:8), Mace (ATK+2, DMG+1, Dur:12)

### World spawns
- Scatter 3-5 items at combat start at random grid positions
- Ammo packs, health potions, and weapon pickups mixed
