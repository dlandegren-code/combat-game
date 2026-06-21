---
name: item-based-defense
overview: >-
  Move shield/parry-ranged/dodge-ranged properties from characters to equipped
  items; make weapon/shield swap a turn-ending action.
createdAt: '2026-06-17T20:15:26.667Z'
todos:
  - id: item-resource
    content: Add shield/parry/dodge properties and SHIELD type to ItemResource
    status: completed
  - id: inventory-component
    content: 'Update InventoryComponent starting vars, equip rules, and property helpers'
    status: completed
  - id: player-defense
    content: >-
      Remove character defense toggles and read them from equipped item in
      Player
    status: completed
  - id: player-equip-action
    content: Add equip action and turn-ending equip_weapon in Player
    status: completed
  - id: enemy-defense
    content: Remove character defense toggles and read them from equipped item in Enemy
    status: completed
  - id: inventory-ui
    content: Wire Inventory UI equip button to equip_weapon and show shield info
    status: completed
  - id: ground-item-shield
    content: Add shield visual color to ground items
    status: completed
  - id: scene-setup
    content: >-
      Spawn a shield pickup on the battlefield and update main.tscn starting
      items
    status: completed
  - id: verify
    content: Run and verify clean diagnostics
    status: completed
---
Changes needed:
- ItemResource: add `is_shield`, `parry_ranged`, `dodge_ranged` properties and a `SHIELD` item type.
- InventoryComponent: add matching starting-item export vars; remove auto-equip on pickup; allow equipping shields; expose helpers (`is_shield_equipped`, `can_parry_ranged`, `can_dodge_ranged`).
- Player/Enemy: delete the old `has_shield`, `can_parry_ranged`, `can_dodge_ranged` export vars; read those properties from the currently equipped item; add `equip_weapon(slot_index)` which equips and ends the turn.
- Inventory UI: wire the Equip button to the new `equip_weapon()` action; display shield/parry/dodge info.
- Ground item visual: give shields a distinct color.
- CombatManager: spawn a shield pickup on the battlefield.
- main.tscn: set Player's starting item to a shield so the mechanic is immediately testable.
