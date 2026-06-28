---
name: fix-weapon-visuals
overview: >-
  Fix weapon/shield visibility, scaling, positioning, and rotation on all
  characters
createdAt: '2026-06-25T20:31:26.316Z'
todos:
  - id: fix-refresh-socket
    content: >-
      Overhaul _refresh_socket in both player.gd and enemy.gd: proper scaling,
      positioning, rotation, bow detection
    status: in_progress
  - id: fix-center-on-origin
    content: Update _center_on_origin to use a larger target size (1.2 instead of 0.5)
    status: in_progress
  - id: fix-shield-offset
    content: Offset shield outward from left arm bone
    status: in_progress
  - id: remove-debug-prints
    content: Remove debug print statements after verifying fix
    status: pending
  - id: verify
    content: Run game and visually verify weapons are visible and properly positioned
    status: pending
---
## Problem Analysis

The `_refresh_socket` function attaches weapon models to BoneAttachment3D sockets on the character skeleton. Issues:

1. **Weapons too small**: `_center_on_origin` scales to `0.5 / max_dim` making swords ~0.5 units (barely visible on a ~1.5 unit character)
2. **No weapon offset/rotation**: Weapons placed at bone origin with no offset, so they're inside the body
3. **Bow loads as sword**: The Short Bow item for Player2 is ONE_HANDED by default, so it loads the sword model. Need to detect bows by name.
4. **Shield needs outward offset**: Shield is at the arm-left bone origin, needs to be pushed outward

## Fix Plan

In both player.gd and enemy.gd:
- Update `_center_on_origin` to use target size 1.2 instead of 0.5
- After loading a weapon model, set proper position offset and rotation on the weapon node:
  - Swords/daggers: position (0, -0.3, 0.1), rotation degrees (-90, 0, 0) so blade points down
  - Bows: position (0, 0, 0.15), no rotation needed
  - Shields: position (-0.15, 0, 0.1) to push outward from left arm
- Fix bow detection: check if item_name contains "bow" (case insensitive) to load bow model
- Remove debug prints after confirming
