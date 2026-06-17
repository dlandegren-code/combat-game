---
name: tactical-rpg-base
overview: >-
  Build the minimum playable tactical RPG slice: 3D battlefield with grid
  movement, player character, enemy, and turn system.
createdAt: '2026-06-01T14:00:00.217Z'
todos:
  - id: scene-skeleton
    content: >-
      Write main.tscn: 3D ground plane, isometric camera, directional light,
      player and enemy primitives
    status: completed
  - id: player-movement
    content: >-
      Write player.gd: click-to-move on a grid with movement range visual
      feedback
    status: completed
  - id: turn-system
    content: 'Write turn_manager.gd: player-turn/enemy-turn cycle with HUD label'
    status: completed
  - id: enemy-ai
    content: 'Write enemy.gd: basic AI moves toward player on enemy turn'
    status: completed
  - id: input-and-verify
    content: 'Set main scene, bind input actions, runAndVerify to confirm playable loop'
    status: completed
---
## Scene Hierarchy

```
main.tscn (Node3D)
  WorldEnvironment (procedural sky)
  DirectionalLight3D (sun, shadows)
  Camera3D (isometric angle: pos (12, 14, 12), looking at origin)
  Ground (StaticBody3D + PlaneMesh + CollisionShape3D) - grid material
  Player (CharacterBody3D + script + capsule mesh + collision)
  Enemy (CharacterBody3D + script + capsule mesh + collision, red)
  TurnManager (Node + script) - tracks current turn, emits signals
  CanvasLayer/HUD - Label showing whose turn it is
```

## Key Decisions

- 3D, isometric-ish camera angle for tactical overview
- GDScript (default, no C# preference indicated)
- Grid-based movement: 1-unit cells, player clicks a cell to move
- Movement range: player can move up to 5 cells per turn
- Turn system: player acts first, then enemy, repeat
- Grid rendered via a GridMap or custom grid drawing on the ground

## Verification

- runAndVerify: game boots, camera shows battlefield from isometric angle
- Click ground: player capsule moves to clicked grid cell
- After player moves, enemy takes a turn (moves 1 cell toward player)
- Turn label toggles between "Your Turn" and "Enemy Turn"
