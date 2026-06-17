---
name: conditions-shove-trip
overview: >-
  Add Prone condition, Shove and Trip attack actions with action bar UI, defense
  system integration, and prone recovery.
createdAt: '2026-06-05T12:37:40.421Z'
todos:
  - id: combatant-exports
    content: >-
      Add is_prone, shove_skill, trip_skill, and selected_action exports to
      player.gd and enemy.gd
    status: completed
  - id: action-hud
    content: >-
      Add action bar CanvasLayer to main.tscn and wire action selection in
      player.gd
    status: completed
  - id: shove-logic
    content: >-
      Implement Shove: skill roll vs defense, push target by margin tiles on
      success
    status: completed
  - id: trip-logic
    content: 'Implement Trip: skill roll vs defense, set target is_prone on success'
    status: completed
  - id: prone-effects
    content: 'Enforce prone: no movement, auto-stand costs 1 time unit at turn start'
    status: completed
  - id: enemy-uses
    content: Let enemy AI randomly use Shove/Trip when adjacent
    status: completed
  - id: verify
    content: 'runAndVerify: clean compile, shove/trip/prone working in combat'
    status: completed
---
## Conditions System

### Prone condition
- `is_prone: bool` on every combatant
- While prone: cannot move, cannot attack/shove/trip. Only option is to stand up.
- At start of turn: if prone, auto-stand costs 1 time unit and enables normal actions
- Defense works against Shove/Trip normally (Parry/Dodge)

### Shove attack
- Action cost: 2 time units
- Roll: `shove_skill + 1d5` vs defender's `(parry/dodge)_skill + 1d5`
- If attacker wins: push target `margin` tiles away from attacker
- If defender wins (dodge/parry): no effect, defense cost applied
- Shoved characters stop if they hit a wall/edge or another character

### Trip attack
- Action cost: 2 time units
- Roll: `trip_skill + 1d5` vs defender's `(parry/dodge)_skill + 1d5`
- If attacker wins: target becomes Prone
- If defender wins: no effect

### Action bar UI
- CanvasLayer at bottom of screen
- Three buttons: Attack (1), Shove (2), Trip (3)
- Active action highlighted
- Keyboard shortcuts: 1=Attack, 2=Shove, 3=Trip
- Visible only during player's turn

### Defaults
- Hero: shove_skill=4, trip_skill=3
- Archer: shove_skill=1, trip_skill=2
- Goblin: shove_skill=2, trip_skill=1
