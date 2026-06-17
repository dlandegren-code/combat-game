---
name: initiative-system
overview: >-
  Refactor turn system into initiative-based combat with multiple characters and
  a visual turn-order tracker.
createdAt: '2026-06-02T10:19:50.183Z'
todos:
  - id: player-refactor
    content: >-
      Refactor player.gd: add initiative, character_name exports, add to
      combatants group, update turn manager refs
    status: completed
  - id: enemy-refactor
    content: >-
      Refactor enemy.gd: add initiative, character_name exports, add to
      combatants/enemies groups, update turn manager refs
    status: completed
  - id: combat-manager
    content: >-
      Write combat_manager.gd: initiative queue, round cycling, AI turn
      handling, game-over checks, UI updates
    status: completed
  - id: scene-update
    content: >-
      Update main.tscn: replace TurnManager with CombatManager, add Player2, add
      InitiativePanel UI
    status: completed
  - id: verify
    content: runAndVerify to confirm clean compile and playable initiative loop
    status: completed
---
## Initiative System Architecture

### CombatManager (replaces TurnManager)
- Collects all combatants from the "combatants" group
- Sorts by initiative descending each round
- Cycles through combatants, skipping dead ones
- Player-controlled: calls enable_turn(), waits for turn_done()
- AI-controlled: calls enable_turn() then take_turn()
- Handles death: removes from queue, checks win/loss
- Updates InitiativePanel UI each activation

### InitiativePanel (CanvasLayer, top-right)
- VBoxContainer listing all combatants sorted by initiative
- Current actor highlighted with ">" prefix
- Dead combatants shown as greyed out

### Player2
- Second player character with init=8, name="Archer"
- Starts at position (-3, 1.1, 3) away from Hero

### Turn flow
1. CombatManager.activate_combatant(idx)
2. Combatant acts (player clicks, or AI auto-acts)
3. Combatant calls combat_mgr.turn_done()
4. CombatManager advances index, activates next
5. When queue exhausted: new round, re-sort by initiative
