---
name: bone-attachment-scenes
overview: >-
  Move BoneAttachment3D sockets from runtime script creation into scene files,
  one per model type. Add helmet socket. Make _setup_sockets idempotent.
createdAt: '2026-06-25T12:37:27.560Z'
todos:
  - id: create-scenes-dir
    content: 'Create res://scenes/characters/ directory'
    status: completed
  - id: soldier-wrapper
    content: >-
      Create soldier_model.tscn wrapping soldier.glb + 3 BoneAttachment3D
      sockets
    status: completed
  - id: orc-wrapper
    content: Create orc_model.tscn wrapping orc.glb + 3 BoneAttachment3D sockets
    status: completed
  - id: maled-wrapper
    content: Create male_d_model.tscn wrapping male-d.glb + 3 BoneAttachment3D sockets
    status: completed
  - id: idempotent-sockets
    content: >-
      Update _setup_sockets() in player.gd and enemy.gd to detect existing
      sockets
    status: completed
  - id: update-main-tscn
    content: Update main.tscn CharacterModel instances to use wrapper scenes
    status: completed
  - id: verify
    content: runAndVerify - compile check and visual sanity
    status: completed
---
## Model → Wrapper Scene Mapping

| Character | Model | Wrapper Scene |
|-----------|-------|--------------|
| Player | character-soldier.glb | soldier_model.tscn |
| Enemy | character-orc.glb | orc_model.tscn |
| ArcherEnemy, BossEnemy, Player2 | character-male-d.glb | male_d_model.tscn |

## Scene Structure (per wrapper scene)

```
Node3D (root)
├── [instance of .glb]  (the whole model, named "Model")
│   └── Armature/Skeleton3D
│       ├── BoneAttachment3D "WeaponSocket" → arm-right
│       ├── BoneAttachment3D "ShieldSocket" → arm-left
│       └── BoneAttachment3D "HelmetSocket" → head
```

## Script Change

`_setup_sockets()` checks if "WeaponSocket" already exists under the skeleton. If yes, grabs the existing nodes instead of creating new ones. Safe fallback: creates them at runtime if missing.

## Verification

- runAndVerify compile check
- Preview frame to confirm characters load with sockets
