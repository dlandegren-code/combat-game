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

### `build_armor_meshes.gd` — dropped-armour graphics

Generates a cuirass from the soldier's **body** mesh, one variant per armour type:

| Output | Palette cell | Used by |
|--------|--------------|---------|
| `assets/models/kenney/mini-arena/armor_heavy.res` | steel blue-grey `(0.42, 0.44, 0.53)` | `heavy_armor.tres` |
| `assets/models/kenney/mini-arena/armor_leather.res` | leather brown `(0.71, 0.40, 0.26)` | `leather_armor.tres` |
| `assets/models/kenney/mini-arena/armor_leather_dark.res` | dark brown `(0.55, 0.33, 0.26)` | `reinforced_leather_armor.tres` |

Armour tiers are Leather `+1`, Reinforced Leather `+2`, Heavy `+3 / +10% resist`.

Add a tier by adding one entry to `VARIANTS` and pointing a `.tres` at the output.
**Parts of the atlas are smooth gradient ramps, not flat cells** — a UV rounding
half a pixel either way lands on a different shade there. Give such UVs as an
exact texel centre, `(px + 0.5) / 512`, as `armor_leather_dark` does, and verify
the sampled colour after regenerating rather than trusting the intended value.

The project ships **no armour model** — the Synty PolygonDungeon pack has chests,
crates and a weapon rack but no torso armour, and the Kenney sets have none. So
the geometry is borrowed from the character body, which keeps it on-style for free.

**How it differs from the helmet split.** The body is one connected shell, so it
does *not* separate by topology the way the head does. It separates cleanly by
**skin weights** instead: the triangles whose dominant bone is `torso` (74 of 272)
form exactly a sleeveless chest piece. The test is per-*triangle*, not per-vertex —
a vertex-level test leaves ragged holes along the shoulder and waist seams where
weights blend between bones.

**Colour comes from UV repainting**, pinning every vertex to one flat cell of the
shared `colormap.png`, rather than from new textures or flat material overrides.
That keeps both variants on-palette and lets one mesh shape serve several armour
tiers. Swatch UVs were picked by dumping the body mesh's UV histogram and sampling
the atlas, not by eye — the same method identified the silver skull in the head.

Armour has no `BoneAttachment3D` socket (only weapons, shields and helmets do), so
`model_path` on an armour `.tres` affects **only** the dropped-item visual.

Expected console output:

```
[armor] kept tris=74
[armor] armor_heavy    verts=132 aabb=[P: (-0.157651, -0.011567, -0.134111), S: (0.315302, 0.178567, 0.268222)]
[armor] armor_leather  verts=132 aabb=(same)
```

### `build_wizard_hair.gd` — grey streaked hair for the wizard

Writes `assets/models/kenney/mini-characters-1/wizard_head_grey.res`, applied as a
`head-mesh` override on `wizard_model.tscn` **only** — the Archer uses the same
`.glb` and keeps its original ginger hair.

`character-male-d`'s head is one skinned surface, so a material override would
recolour the face and ears too; repainting UVs is the only way to touch just the
hair. The hair is found the same way as the soldier's crest — **the component whose
AABB reaches highest** (comp 141, 129 verts). Colour cannot be used to find it: the
ginger hair and the skin tones overlap in the atlas.

**Streaks are one UV per TRIANGLE, not per vertex.** Per-vertex striping lets a
triangle straddling a stripe boundary interpolate its UV between two distant atlas
cells, smearing unrelated colours across it. The tool therefore emits fresh
vertices per triangle (375 -> 663 verts, still trivial).

The **forehead quiff** is dropped too (`drop_forehead_tuft`): a fan of 13 triangles
sitting at z 0.168, proud of the skull's own front face at 0.158, while every other
hair triangle sits at z <= 0.154. Cutting by "centroid in front of the skull"
isolates it exactly. The tool prints **hair boundary edges before and after** the
cut — both must stay 0, or the tuft was plugging the cap and there is now a hole at
the hairline.

`CharacterSkin._apply_long_hair()` adds what makes the hair *long*: 11 box strands
on a `HairSocket` bone attachment, alternating `hair_color_main` /
`hair_color_streak`. **Those two colours must stay matching the palette cells the
tool paints with**, or crown and strands stop reading as one head of hair.

`_apply_beard()` and `_apply_eyebrows()` add the rest of the facial hair the same
way, on a `BeardSocket` and a `BrowSocket`. All three share `_head_socket()` and
`_hair_materials()` rather than each rebuilding a socket and duplicate materials.

Landmarks measured on this rig, in head-bone local space: the chin is level with the
bone origin (y 0), the face plane is at z 0.160, the mouth quad spans y 0.058 .. 0.092
and the eye quads sit at x +/-0.072 spanning y 0.119 .. 0.168. **male_d has no brow
geometry of its own** — the soldier head does, this one does not — so the eyebrows are
built from scratch rather than recoloured.

Strand length is in mesh units and `CHARACTER_SCALE` (1.6) multiplies it on screen,
so it is far shorter than it looks: strand tops sit at world y 1.04 and the floor is
at 0.2, so a length of 0.52 dragged the hair along the ground. 0.34 lands the ends
at world y 0.49..0.60 — shoulder to mid-back.

### `build_archer_body_split.gd` — legs on their own material

Writes `assets/models/kenney/mini-characters-1/archer_body_split.res`: the same body
geometry, but as **three surfaces** — 0 torso + arms (282 tris), 1 legs (110 tris),
2 boots (98 tris) — cut per triangle by dominant bone, then legs subdivided by height
at `boot_cut_y`. Applied as a `body-mesh` override on `male_d_model.tscn`, with
`legs_material` and `boots_material` on the script. Surface AABBs overlap slightly
around a cut because triangles straddle it; each belongs wholly to one surface.

**Why a split and not a UV repaint.** The armour and hair tools recolour by pointing
UVs at flat cells of the shared colormap atlas. That cannot work for the archer: its
body-mesh is driven by `archer_leather_albedo.png`, which is 98% one dark shade, so
every UV lands on the same colour — there is no distinct region to aim at. A mesh takes
one material per *surface*, so a differently-coloured leg needs its own surface.

`CharacterSkin.legs_material` drives it, and the pairing matters: **`material_override`
paints every surface and would defeat the split**, so when `legs_material` is set the
script assigns `set_surface_override_material(0/1, ...)` and leaves `material_override`
clear. With no `legs_material` (the wizard) it keeps the old blanket path.

Note the belt lands at world y 0.404 .. 0.450, just above the split at 0.392 — so the
light-brown belt separates the dark torso from the olive legs rather than abutting them.

### Outfit trim (`_apply_outfit_trim`)

The archer's `archer_leather_albedo.png` is **98% two near-identical dark shades**
(79.6% at `0.2,0.1,0.1`, 18.5% at `0.2,0.2,0.1`) — only 8 distinct buckets in a
1024² image — so it reads as one slab of colour at camera distance. `show_outfit_trim`
on `male_d_model.tscn` adds a light-brown belt plus a dark-olive chest strap and
shoulder caps on a `TrimSocket` to give it definition.

The leather brown is a palette cell from this rig's atlas. **The cloth green is not** —
the palette's only greens are teal (`0.11, 0.52, 0.42`), which clashes against
near-black leather, so `trim_color_cloth` is a plain dark olive instead.

Trim geometry is in **torso-bone** local space: the bone sits at mesh y 0.176, z -0.029,
and the torso spans local y 0 .. 0.167, x +/-0.139, z -0.123 .. 0.129 — a world span of
y 0.393 .. 0.660. Two collisions to keep in mind when retuning:

- the chest strap is easily longer than the torso once tilted, and pokes through the
  shoulder and below the waist;
- the shoulder caps sit right where the **quiver** top is (world y 0.634), so they must
  ride above it.

Bracers ride their own **arm-bone** sockets, so they stay on the forearm through the
animation. All four limb bones have an identity basis, so the offsets are axis-aligned.
**Size a limb band from the measured cross-section at that slice, not by eye:** the
forearm at x 0.20 .. 0.24 is 0.133 tall and 0.164 deep with its depth centred on
z 0.042 — *not* on the bone axis — so a 0.105 x 0.105 band centred on the axis rendered
entirely inside the arm and was invisible. Anything wrapping a limb must exceed that
slice's extent and use its true centre.

### Adding an `@export` that a wrapper scene sets

**Check `main.tscn` for a stale instance-level override before trusting the wrapper.**
Adding `show_long_hair` left `main.tscn` carrying `show_long_hair = false` on
`Wizard/CharacterModel`, which silently beat the `true` in `wizard_model.tscn` — the
strands simply never appeared, with no error. An instance override always wins over
the scene it instances, and the editor serialises one as soon as it sees a new
property while that scene is open. Verify a new export's value **at runtime**, not by
reading the wrapper scene.

### `build_quiver_body.gd` — quiver body UVs

Writes `assets/PolygonDungeon/Models/quiver_body.res`, used by
`scenes/items/quiver.tscn` — which **both** the ground pickup and the equipped quiver
instantiate, so it fixes them together.

**Never put a texture ATLAS on a procedural primitive mesh.** The body was a
`CylinderMesh`, whose generated UVs span the whole 0..1 square, while
`Dungeon_Material_01_mat` points at an atlas — so the entire atlas was stretched around
the quiver. Sweeping the circumference ran through unrelated swatches: blue-grey
`(0.33,0.52,0.70)`, pink `(0.74,0.44,0.56)`, orange `(0.86,0.59,0.35)`, teal
`(0.39,0.59,0.62)`, then leather brown. Those read as stripes running **lengthwise
along the mesh** — vertical on the worn quiver, horizontal on the pickup lying on its
side (`model_ground_rotation` is `-90` about X). One artifact, two orientations.

A `PrimitiveMesh`'s UVs cannot be edited, so the cylinder is baked to an `ArrayMesh`
with its UVs replaced: one leather cell for the body, and a **grey** cell for the top
rim — the grey detail is what the quiver is meant to read with, since the blue-grey
swatch in the old accidental banding was what made it look right. A darker brown rim
tried first lost that and read as all-brown.
Banding by **height** gives horizontal rings on the worn quiver and stays uniform
around the circumference. As with the hair streaks, UVs are assigned **per triangle**
so no triangle straddling the band interpolates between two distant atlas cells.

Note `body.mesh as ArrayMesh` returns **null** for a primitive — call
`surface_get_arrays(0)` on the `Mesh` directly when probing.

### `brighten_wizard_robe.gd` — brighter robe texture

Bakes `assets/materials/wizard_robe_bright.res` from `assets/images/wizard_robe_albedo.png`,
consumed by `assets/materials/wizard_body.tres`.

**The wizard's "robe" is two surfaces**, and both must be kept in step or he goes
two-tone: the painted body texture (93% of its pixels are the robe) *and* the
tapered skirt cylinder that `CharacterSkin._add_robe()` builds, coloured by the
`robe_color` export on `wizard_model.tscn`.

Brightening uses a **power curve, not a multiply** — the source already peaks at
1.0, so scaling would clip its highlights flat. The exponent is derived so the
texture's dominant tone lands on the skirt's brightness (`0.28 ^ 0.56 ≈ 0.49`);
re-derive it if `robe_color` changes. Output is a baked `.res` `ImageTexture`
rather than a `.png` because a new `.png` needs a Godot re-import before it is
usable, which a headless tool run cannot trigger.

## Ground-item visuals

`ground_item.gd` resolves a dropped item's model in three tiers: `model_path` on
the `.tres` (preferred, data-driven), then an ammo-bundle special case, then a
name-based fallback for items that have no `model_path` yet.

**The fallback matches by substring, never exact name.** It used to be an exact
`match` on three names, so every other weapon — `Rusty Sword`, `Short Bow`,
`Ranger Dagger`, `Goblin Dagger`, `Boss Cleaver` — silently fell through to a
coloured placeholder box. `_weapon_kind()` now classifies into
`bow`/`hammer`/`axe`/`shield`/`blade` using the *same* heuristics as
`Combatant._refresh_socket`, so a dropped weapon and a held one resolve to the
same model. **Add new weapons to `_weapon_kind()`, or give them a `model_path`.**

Two traps when adding ground visuals:

- **Rest models on the ground, don't just centre them.** Centring alone let long
  models (the cleaver) hang below the floor. Both branches now call
  `_rest_on_ground` after `add_child`, so every pickup's lowest point sits at its
  spawn height.
- **Synty `.res` meshes ship without a resolved material** and render untextured
  white unless the shared atlas (`SYNTY_MAT`) is assigned explicitly.

Note the two scale fields mean different things: `ItemResource.model_scale` is a
*normalized target* for the longest dimension, while `_get_item_model_scale()` in
the fallback path is a *multiplier* on the model's native size.

`_apply_visual()` is **idempotent** via `_visual_built`, and must stay that way: both
spawners call it deferred *and* `_ready()` calls it, so without the guard every pickup
carried two overlapping copies of its model.

**If an item looks different equipped vs dropped, check whether the two paths share an
asset.** The equipped quiver used to be rebuilt in code with a flat brown
`StandardMaterial3D` body and two arrows, while the pickup instantiated
`scenes/items/quiver.tscn` — textured Synty atlas, three arrows. `_apply_quiver` now
instantiates that same scene, so they cannot drift.

**Spawn pickups at `GroundItem.DROP_Y` (0.2), an absolute world height — never
offset from a combatant's `position`.** Combatant origins sit at
`Combatant._ground_y()` = **1.11**, about a metre above the floor, because their
`CharacterModel` is offset downwards to meet it. `inventory_ui._on_drop` used
`active.position + Vector3(x, 0.2, z)` and so left every dropped item hanging at
y ≈ 1.31. `_rest_on_ground` cannot save this — it settles a model onto the ground
item's *own* y, so a wrong node height passes straight through.

## Stat blocks vs equipment bonuses

`Inventory` is a **child** node, so `InventoryComponent._ready()` runs before its
combatant's: it equips the starting gear and folds the bonuses in with
`character.armor += item.armor_bonus`. `Combatant._ready()` then calls
`_apply_stats()`, which *assigns* `armor` and `physical_resistance` straight from
the stat block — discarding those bonuses.

`Combatant._readd_equipment_bonuses()` repairs that, running right after
`_apply_stats()`. Two things it must keep doing:

- **Only when `stats != null`.** With no stat block nothing was overwritten and
  the bonuses are already in place; re-adding would double-count. The player
  characters have no stat block, so they take that path.
- **Dedupe by item.** A two-handed weapon sits in `right_hand` *and* `left_hand`
  as the same object, and `InventoryComponent` applies its bonus once.

**Stat blocks therefore hold BASE values, with equipment added on top.** This is
why `boss_stats.tres` reads `armor = 0` — the Goblin Boss's protection comes from
its equipped Heavy Armor (`+3`), giving the same effective 3 it always had. When
changing an enemy's armour, decide whether the value belongs on the stat block or
the item, and remember they now sum.

Watch out for negative bases: resistance is applied as
`dmg * (1.0 - physical_resistance / 100.0)` (`combatant.gd:700`), so a negative
value turns into a damage *amplifier* rather than a reduction.

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
