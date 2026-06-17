---
name: inventory-system
overview: >-
  Add per-character inventory with pickup/drop/equip, ground item spawning, and
  a compact inventory UI panel.
createdAt: '2026-06-05T18:40:10.263Z'
todos:
  - id: item-resource
    content: >-
      Create item_resource.gd ÃÃÂ¢ base item class (name, type, icon hint,
      stats)
    status: completed
  - id: inventory-component
    content: >-
      Create inventory_component.gd ÃÃÂ¢ per-character inventory with
      add/remove/equip/drop
    status: completed
  - id: wire-inventory
    content: >-
      Add inventory to player.gd and enemy.gd ÃÃÂ¢ connect to character
      lifecycle
    status: completed
  - id: ground-item
    content: >-
      Create ground item scene ÃÃÂ¢ MeshInstance3D with PickupItem script for
      world items
    status: completed
  - id: pickup-action
    content: >-
      Add Pick Up action (key 7) and button ÃÃÂ¢ costs time, picks up nearby
      ground items
    status: completed
  - id: thrown-weapon-item
    content: Update thrown weapon to drop actual weapon item (not just visual)
    status: completed
  - id: inventory-ui
    content: 'Add inventory UI panel ÃÃÂ¢ CanvasLayer showing slots, equip/drop buttons'
    status: completed
  - id: verify
    content: verify ÃÃÂ¢ runAndVerify compile and visual check
    status: completed
---
## Inventory System

### Item Resource (item_resource.gd)
- `item_name: String` ÃÃÂ¢ display name
- `item_type: int` ÃÃÂ¢ WEAPON, AMMO, CONSUMABLE, THROWABLE
- `attack_bonus: int` ÃÃÂ¢ added to attack_skill when equipped
- `damage_bonus: int` ÃÃÂ¢ added to attack_dmg when equipped
- `durability: int` ÃÃÂ¢ for weapons

### Inventory Component (inventory_component.gd)
- Attached to each character as a child Node
- `slots: Array[ItemResource]` ÃÃÂ¢ max 4 slots
- `equipped_slot: int` ÃÃÂ¢ which slot is the active weapon (-1 = fists)
- `add_item(item) -> bool` ÃÃÂ¢ adds to first empty slot, returns false if full
- `remove_item(slot_index)` ÃÃÂ¢ removes and drops
- `equip(slot_index)` ÃÃÂ¢ sets equipped slot, updates character stats
- `has_weapon_equipped()` ÃÃÂ¢ check for attack/parry

### Ground Item (ground_item.tscn / ground_item.gd)
- Small colored box/cylinder with a Label3D showing name
- CollisionArea for proximity detection
- `item_resource: ItemResource` ÃÃÂ¢ what this ground item represents
- Added to "pickups" group

### Pick Up Action
- New action: Action.PICKUP (index 7, key 7, button "Pick Up")
- When executed, scans "pickups" group for items within 1 tile
- Picks up the nearest one into inventory
- Costs 1 time unit
- Shows feedback text: "Picked up X"

### Thrown Weapon Integration
- When a throw misses/hits, spawn a GroundItem with the thrown weapon's item data
- The visual uses the same GroundItem scene

### Inventory UI
- Small panel (right side of screen, below turn order)
- Shows character name + 4 item slots
- Each slot: item name, [Equip] button, [Drop] button  
- Equipped slot highlighted
- Only visible during player-controlled turns
