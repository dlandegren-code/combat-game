---
name: slot-based-equipment
overview: >-
  Replace single equipped item with dedicated slots: Right Hand, Left Hand,
  Armor. Support 1H/2H weapons and shield+weapon combos.
createdAt: '2026-06-18T05:39:27.795Z'
todos:
  - id: extend-item-resource
    content: 'Extend ItemResource with handedness, equip_slot, and armor stats'
    status: completed
  - id: rewrite-inventory-slots
    content: 'Rewrite InventoryComponent with Right Hand, Left Hand, and Armor slots'
    status: completed
  - id: update-player-equipment
    content: Update Player.gd to use slot-based equipment and remove old weapon flags
    status: completed
  - id: update-enemy-equipment
    content: Update Enemy.gd to use slot-based equipment and remove old weapon flags
    status: completed
  - id: update-inventory-ui
    content: Update Inventory UI for multi-slot equip display
    status: completed
  - id: update-scene-gear
    content: Update main.tscn with starting gear and ground pickups
    status: in_progress
  - id: verify-build
    content: Run and verify the build
    status: pending
---
Slot design:
- Right Hand: weapon (1H or 2H)
- Left Hand: shield or 1H weapon (offhand)
- Armor slot: armor pieces (not hands)
- 2H weapon occupies both hands and blocks offhand/shield
- Armor provides armor / resistance bonuses while equipped

Implementation steps:
1. Extend ItemResource with `handedness` (1H/2H) and `equip_slot` (RIGHT_HAND, LEFT_HAND, ARMOR, ANY_HAND). Add `armor_bonus` and `resistance_bonus` for armor.
2. Rewrite InventoryComponent to track `right_hand`, `left_hand`, `armor` item references. Add equip/unequip by slot, validation for 2H blocking, and combined stat getters (attack from right hand + compatible offhand, defense from shield + armor).
3. Update Player.gd: remove `has_weapon`, `weapon_durability`, `weapon_broken` exports; replace with inventory queries. Make equip action accept target slot. Update health bar text.
4. Update Enemy.gd: same cleanup, remove old weapon booleans, use inventory for defense checks.
5. Update inventory_ui.gd: show equipment slots (Right Hand, Left Hand, Armor) and equip buttons that place items into the correct slot.
6. Update main.tscn: give each character proper starting equipment (Rusty Sword in right hand, Wooden Shield in left hand, Leather Armor in armor slot for player; appropriate gear for enemies). Add ground pickups for shield/bow based on earlier choice (mixed: shield on ground, player starts with sword).
7. Verify with runAndVerify and fix any runtime errors.
