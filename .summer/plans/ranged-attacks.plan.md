---
name: ranged-attacks
overview: >-
  Add ranged bow attacks (ammo-based) and thrown weapon attacks (one-use) to the
  tactical combat system.
createdAt: '2026-06-05T14:03:48.848Z'
todos:
  - id: add-action-enum
    content: >-
      Add RANGED/THROW to Action enum, ranged_skill/ammo/throw_skill exports in
      player.gd and enemy.gd
    status: completed
  - id: ranged-targeting
    content: >-
      Implement ranged targeting: click enemy within max_range tiles, raycast
      LOS check
    status: completed
  - id: ranged-logic
    content: >-
      Implement ranged attack logic: attack roll, ammo decrement, damage
      application
    status: completed
  - id: throw-logic
    content: 'Implement throw attack logic: throw roll, weapon lost after throw'
    status: completed
  - id: action-bar-buttons
    content: 'Add Range (5) and Throw (6) buttons to action bar, bind keys 5/6'
    status: completed
  - id: wire-buttons
    content: Wire up button connections in combat_manager.gd and player.gd
    status: completed
  - id: character-stats
    content: 'Give Archer ranged stats, give Hero throw capability'
    status: completed
  - id: verify
    content: runAndVerify to test compile and gameplay
    status: completed
---
## Ranged Attacks

### New Actions
- **RANGED (bow)**: Target enemy within 8 tiles, LOS check. Roll attack_skill + 1d5 vs defense. Uses 1 ammo. Cannot be used with 0 ammo.
- **THROW**: Target enemy within 5 tiles. Roll throw_skill + 1d5 vs defense. Weapon is lost after throw (set weapon_broken = true).

### New Exports (both player.gd and enemy.gd)
- `ranged_skill: int` - base skill for ranged attacks
- `ammo: int` - current ammo count
- `max_ammo: int` - max ammo capacity
- `throw_skill: int` - base skill for thrown weapons
- `ranged_range: int` - max tiles for ranged (default 8)
- `throw_range: int` - max tiles for thrown (default 5)

### Character Config
- Archer: ranged_skill=6, ammo=8, max_ammo=8, ranged_range=8
- Hero: throw_skill=4, throw_range=5 (can throw weapon as desperation)
- Goblin: throw_skill=1 (weak throw)

### Action Bar
- New buttons: "Range (5)", "Throw (6)"
- Input map: action_5 (key 5), action_6 (key 6)

### Targeting
- Cursor changes to cross when hovering enemy within range
- Click to execute
- LOS check via raycast (no shooting through walls/obstacles)

### Ammo Display
- Show in health bar: "Ammo:8" when ammo > 0, "Ammo:Empty" when 0
