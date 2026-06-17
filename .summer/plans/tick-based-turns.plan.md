---
name: tick-based-turns
overview: >-
  Refactor turn system to tick-based time units: actions cost time, next actor
  is whoever has the lowest next-turn tick, initiative breaks ties.
createdAt: '2026-06-02T11:56:34.548Z'
todos:
  - id: combat-manager-refactor
    content: >-
      Rewrite combat_manager.gd: tick counter, next_turn_at per combatant,
      action-cost API, find-next-actor logic, initiative tiebreaker
    status: completed
  - id: player-time-cost
    content: >-
      Update player.gd: track tiles moved per turn, report move + attack costs
      via action_cost signal/call
    status: completed
  - id: scene-properties
    content: >-
      Add time_cost export to scenes: default move_cost=1 per tile,
      attack_cost=2 for all combatants
    status: completed
  - id: initiative-panel-fix
    content: Update initiative panel to sort by next_turn_at instead of raw initiative
    status: completed
  - id: verify
    content: 'runAndVerify: clean compile, tick system working with multiple characters'
    status: completed
---
## Tick-Based Time System

### Core concept
- Global `current_tick` counter starts at 0
- Each combatant has `next_turn_at`: the tick they act next
- All start at `next_turn_at = 0`
- Initial sort: by initiative (descending), then assign incrementing ticks (0, 0, 0 with initiative tiebreaker)
- After action completes: `next_turn_at += action_cost`
- Find next actor: minimum `next_turn_at`. Ties broken by raw initiative (higher goes first)

### Action costs (exports on combatants)
- Move: 1 time unit per tile (tiles_moved * 1)
- Basic Attack: 2 time units
- Total turn cost = move_cost + (attack_cost if attacked)

### CombatManager changes
- `current_tick: int = 0`
- `_activate_next()`: finds combatant with minimum `next_turn_at`, advances `current_tick` to that value
- `turn_done(action_cost: int)`: adds cost to current combatant's `next_turn_at`, calls `_activate_next()`
- `on_character_died()`: removes from queue, same logic

### Player.gd changes
- Track `_tiles_moved_this_turn: int`
- Reset to 0 on `enable_turn()`
- On click-to-move: calculate tiles_moved from Manhattan distance
- On move complete: store tiles_moved
- On attack: store that an attack happened
- `_on_move_complete()`: calculates total cost, calls `combat_mgr.turn_done(cost)`

### Queue display
- Sort by `next_turn_at` ascending, then initiative descending
- Show each combatant with their next_turn_at tick number
