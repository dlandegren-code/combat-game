# Agent Notes

Project-specific guidance for AI agents lives here.

## Mesh-surgery tools (`res://tools/`)

Scripts under `tools/` are one-off asset generators, not game code. Each has a
matching `.tscn`; run it with `summer_play` on that scene and read the console.
They only write `.res` files under `assets/`, and always read their input from the
pristine source `.glb`, so re-running is safe and idempotent.

### `build_soldier_helmet.gd` — equippable helmet for the Hero

Generates two meshes from `character-soldier.glb`:

| Output | What it is |
|--------|-----------|
| `assets/models/kenney/mini-arena/soldier_helmet.res` | the removable helmet — static, baked into head-bone space |
| `assets/models/kenney/mini-arena/soldier_head_bare.res` | the head underneath — still skinned |

Consumed by `resources/items/knight_helmet.tres` (`model_path`) and
`scenes/characters/soldier_model.tscn` (overrides `head-mesh`) respectively.

**Why a tool is needed at all.** The Kenney soldier's head is a *single skinned
surface* with no sub-nodes, so the built-in helmet cannot be hidden by toggling
visibility or swapping a material — it has to be split geometrically.

**How the split works.**

1. **Weld + union-find.** Vertices are grouped by rounded position, then unioned
   across triangle edges to find connected components. The weld matters: UV-seam
   duplicates share a position but are distinct vertices, and without welding a
   single visual piece fragments into several components.
2. **Classify.** The head is 9 components. Sampling `colormap.png` through each
   one's average UV identifies them:

   | Component | Verts | Colour | What it is |
   |-----------|-------|--------|-----------|
   | 28 | 127 | silver `(0.87, 0.87, 0.94)` | **the skull — this *is* the helmet** |
   | 58 | 160 | white | the crest / plume |
   | 80, 85 | 42 each | skin `(0.86, 0.62, 0.47)` | ears |
   | 94, 102, 110, 138, 144 | 4–8 | dark greys / red | eye, brow and mouth quads |

   Two traps here. The soldier has **no skin-coloured skull** — the silver shell
   *is* the head shape, so the bare head must be repainted (with the ears' own
   skin UV) rather than merely uncovered. And the crest has **more** vertices
   than the skull, so "largest component = skull" picks the wrong piece; the
   crest is found by height, the skull as the largest of the remainder.
3. **Helmet** = silver shell + crest, rebaked into head-bone space with skinning
   stripped. The crest is weighted to the `head` bone alone, so a rigid
   `BoneAttachment3D` reproduces it *exactly* rather than approximating.
4. **Bare head** = everything except the crest, skull repainted skin, staying in
   mesh space with bones/weights intact so it animates as before.

**Tuning** (exported, editable in the inspector on the tool scene):

- `shell_offset` (0.012) — how far the shell floats off the skull. Large enough
  to avoid z-fighting, small enough not to read as a gap.
- `y_top_cut` (0.53), `z_back` (0.05), `y_back_cut` (0.40) — the face opening.
  Needed because the shell sits *outside* the skull while the eye/brow/mouth
  quads are flush *with* it, so a closed shell renders in front of the face and
  hides it. **For a fully closed great-helm, set both `y_*_cut` to 0.**
- `skin_uv` — palette swatch the bare skull is repainted with.

**Regenerating.** Only needed if `character-soldier.glb` itself changes; the
`.res` outputs are baked copies and survive a plain re-import. Expected console
output for the current tuning:

```
[helm] crest=58 (verts=160) skull=28 (verts=127)
[helm] helmet crest_tris=96 shell_tris=43 aabb=[P: (-0.172, -0.005367, -0.335), S: (0.344, 0.498442, 0.530733)]
[helm] head skull_tris=75 other_tris=70 aabb=[P: (-0.226751, 0.29325, -0.157361), S: (0.453502, 0.368075, 0.345)]
```

## Equipment visuals

Helmets ride `HelmetSocket` (a `BoneAttachment3D` on the `head` bone) via
`Combatant._refresh_socket`, the same path as weapons and shields.

**`ItemResource.model_scale` is a target size, not a multiplier.** It sets the
model's longest dimension *in the socket's local space* — which for bone sockets
is raw GLB skeleton units, where a whole head is only ~0.45 wide. A plausible
looking `0.15` renders at roughly a quarter of head size. Set `model_scale = 0.0`
to keep a mesh's native scale, which is what `knight_helmet.tres` does since its
geometry is already in the right units.

Head-bone origin sits at the *base* of the skull, not its centre, so a helmet
positioned at the socket origin ends up inside the head.
