---
name: equipment-slots
overview: >-
  Finish the equipped-slot system: unequip support, dedicated equipment panel,
  and a bug fix on the ground item.
createdAt: '2026-06-18T05:52:13.471Z'
todos:
  - id: unequip-ui
    content: Add unequip support to inventory_ui.gd equip button
    status: completed
  - id: equipment-panel
    content: 'Create a dedicated EquipmentPanel UI showing RH, LH, Armor'
    status: completed
  - id: fix-ground-shield
    content: Fix GroundShield in main.tscn to use ground_item.gd script
    status: completed
  - id: verify
    content: 'Open scene, run and verify'
    status: completed
---
The inventory_component already has right_hand, left_hand, and armor slots with 2H/1H conflict handling. What's missing: (1) a way to unequip from the UI, (2) a clear visual panel showing the three equipped slots, (3) the pre-placed GroundShield on the map is using the wrong script. I'll add an Equip/Unequip toggle in the inventory list, add a new EquipmentPanel CanvasLayer above the inventory, and switch the ground shield to use ground_item.gd.
