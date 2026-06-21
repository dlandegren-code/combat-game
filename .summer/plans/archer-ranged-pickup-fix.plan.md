---
name: archer-ranged-pickup-fix
overview: Fix the archer ranged attack not working and arrow pickups having no effect.
createdAt: '2026-06-17T13:09:53.562Z'
todos:
  - id: fix-line-of-sight
    content: >-
      Fix line-of-sight ray in player.gd and enemy.gd to target the intended
      enemy and use chest height.
    status: completed
  - id: fix-pickup
    content: >-
      Fix _do_pickup in player.gd so ammo/consumables apply immediately and
      enable max_ammo when needed.
    status: completed
  - id: set-max-ammo
    content: >-
      Set Player2.max_ammo in main.tscn so the Archer can display and hold
      arrows.
    status: completed
  - id: verify
    content: Run the game and verify the archer can shoot and pickups work.
    status: completed
---
The main scene has an Archer character (Player2) with ammo=2 but max_ammo=0, so ammo is invisible and pickups are clamped to zero. There are also two logic bugs: the line-of-sight ray returns true if any enemy is hit (not the intended target) and uses a top-edge height that can graze; and pickups add Ammo/Consumable items to inventory but never call use_consumable(), so arrows and potions appear to do nothing.

Changes:
- res://scripts/player.gd: rewrite _has_line_of_sight to accept the target Node and check it is the first hit; adjust ray height to chest level. Pass the collider node from _can_target. Auto-apply Ammo/Consumable pickups in _do_pickup, setting max_ammo if it was zero.
- res://scripts/enemy.gd: apply the same _has_line_of_sight fix; pass the player node in the archer AI.
- res://main.tscn: set Player2.max_ammo = 10 so the Archer can actually hold and display arrows.

Verify with runAndVerify after the edits.
