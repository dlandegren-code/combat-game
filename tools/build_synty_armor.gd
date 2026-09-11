@tool
extends Node
## Carves wearable armour off the Synty dungeon characters and saves each piece as its own mesh.
##
## --- Why ---
##
## The armour items used to point at armor_leather.res and friends: torso shells cut off the
## Kenney soldier rig by build_armor_meshes.gd and pinned to one flat cell of the colormap atlas.
## One flat colour on a smooth shell has no edges to catch the light, so from every angle it
## rendered as a rectangle. Painting a drawn Fantasy Warrior icon over the top fixed the cell and
## broke the pairing: the bag showed one thing and the floor another.
##
## The dungeon pack's characters wear armour that is actually modelled -- plate with pauldrons
## and a visored helm on the knights, strapping and studded belts on the goblins. This lifts
## those off and hands the SAME mesh to the floor, the icon and the detail card, so all three
## agree.
##
## --- How a piece is cut ---
##
## Same dominant-bone selection as build_armor_meshes.gd: a triangle belongs to whichever bone
## holds the most weight across its three corners, and a piece is the union of a few bones. It
## has to be a GROUP, not one bone -- this rig gives Spine, Chest and UpperChest a narrow band of
## the body each, so cutting one bone yields a slice of a breastplate rather than a breastplate.
##
## --- Cutting the wearer out of the armour ---
##
## The goblins' armour is straps and belts over bare hide, so a bone cut brings the goblin along
## with it. The drop-hide pass discards triangles whose atlas texel is goblin olive, leaving the
## harness behind. The pack paints everything from one palette texture and ships every character
## as a single surface, so a triangle's UV is the only thing that says what material it is --
## there are no submeshes to filter by.
##
## Run once from tools/build_synty_armor.tscn; the .res files it writes are what
## resources/items/*.tres point at. Kept in the repo so the meshes can be rebuilt rather than
## being artefacts nobody can reproduce.

const OUT_DIR := "res://assets/models/synty_armor/"

## --- The two source packs ---
##
## They differ in every mechanical detail: where the characters live, what they ship as (the
## dungeon pack was converted to .mesh with a sidecar Skin, Fantasy Rivals is raw .fbx that Godot
## imports as a scene), which atlas paints them, and -- the one that actually bites -- how the
## rig names its bones. Dungeon uses Godot naming, Rivals uses Unreal's.
const DUNGEON := {
	"dir": "res://Assets/PolygonDungeon/Models/Characters/IndividualCharacters/",
	"fbx": false,
	# The characters' own material. Same texture as the prop atlas but without its emission pass,
	# which would make a breastplate glow.
	"mat": "res://Assets/PolygonDungeon/Materials/Dungeons_Material_Characters_01_mat.tres",
	"atlas": "res://Assets/PolygonDungeon/Textures/Dungeons_Texture_01.png",
}
const RIVALS := {
	"dir": "res://assets/models/synty_rivals/",
	"fbx": true,
	"mat": "res://assets/models/synty_rivals/fantasy_rivals_mat.tres",
	"atlas": "res://assets/models/synty_rivals/FantasyRivals_Texture_01_A.png",
}

## Everything from the collarbone down to the waist, plus the shoulders -- which is where the
## pauldrons live, and a breastplate without them reads as a barrel.
const TORSO := ["Spine", "Chest", "UpperChest", "LeftShoulder", "RightShoulder"]
## The same, minus the waist. The shaman's belt is a separate loop of geometry a hand's width
## below his mantle, so taking the whole torso gives two objects with a gap of nothing between
## them rather than one garment.
const MANTLE := ["Chest", "UpperChest", "LeftShoulder", "RightShoulder"]
const LEGS := ["LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg",
	"LeftFoot", "RightFoot"]

## Rivals torso. Spine only, and deliberately NOT the clavicles: this rig hangs the whole arm
## down to the wrist off clavicle_l/r, so including them the way TORSO includes the shoulders
## drags both arms into the cut.
const TORSO_UE := ["spine_01", "spine_02", "spine_03"]

## out name, pack, source character, bones, strip hide
const PIECES := [
	["plate_cuirass", DUNGEON, "Character_Hero_Knight_Male", TORSO, false],
	["plate_helm", DUNGEON, "Character_Hero_Knight_Male", ["Head"], false],
	["studded_harness", DUNGEON, "Character_Goblin_WarChief", TORSO, true],
	["hide_mantle", DUNGEON, "Character_Goblin_Shaman", MANTLE, true],
	["hide_greaves", DUNGEON, "Character_Goblin_WarChief", LEGS, true],
	# The party's two leather tiers. The goblins' own gear reads as goblin gear -- straps over
	# bare hide, bone spikes -- which is right on a goblin and wrong on a hero, so the party's
	# leather is cut from characters built as people. Those two goblin pieces stay: they are what
	# goblin_leather_armor.tres and reinforced_goblin_leather.tres wear.
	["dwarf_jerkin", RIVALS, "SK_BR_Character_Dwarf_01", TORSO_UE, false],
	["studded_leather", RIVALS, "SK_Character_DarkElf_01", TORSO_UE, false],
]

var _atlas: Image


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for piece in PIECES:
		_atlas = _load_atlas(piece[1]["atlas"])
		var mesh := _cut(piece[1], piece[2], piece[3], piece[4], piece[0])
		if mesh == null:
			continue
		var path: String = OUT_DIR + piece[0] + ".res"
		print("ARMOR %s -> %s err=%d" % [piece[0], path, ResourceSaver.save(mesh, path)])
	print("ARMOR done")


func _load_atlas(path: String) -> Image:
	var tex: Texture2D = load(path)
	var img: Image = tex.get_image() if tex else null
	# Imported textures arrive VRAM-compressed, and get_pixel on those reads nothing useful.
	if img != null and img.is_compressed():
		img.decompress()
	return img


func _source(pack: Dictionary, who: String) -> Array:
	## The character's mesh and the Skin that names its bones, however this pack ships them.
	##
	## The dungeon pack was converted to a bare .mesh with the Skin as a sidecar resource; Rivals
	## is raw .fbx, which Godot imports as a whole scene, so the mesh and its Skin have to be dug
	## out of a MeshInstance3D inside it.
	if not pack["fbx"]:
		return [load(pack["dir"] + who + ".mesh"), load(pack["dir"] + who + "_skin.tres")]
	var res: Resource = load(pack["dir"] + who + ".fbx")
	if not (res is PackedScene):
		return [null, null]
	for node in _walk((res as PackedScene).instantiate()):
		var mi := node as MeshInstance3D
		if mi != null and mi.mesh != null and mi.skin != null:
			return [mi.mesh, mi.skin]
	return [null, null]


func _walk(node: Node, out: Array = []) -> Array:
	out.append(node)
	for c in node.get_children():
		_walk(c, out)
	return out


func _cut(pack: Dictionary, who: String, bones_wanted: Array, drop_hide: bool,
		label: String) -> ArrayMesh:
	var found: Array = _source(pack, who)
	var src: Mesh = found[0]
	var skin: Skin = found[1]
	if src == null or skin == null:
		push_warning("build_synty_armor: no source for %s" % label)
		return null

	var binds := []
	for b in range(skin.get_bind_count()):
		binds.append(str(skin.get_bind_name(b)))
	var want := {}
	for b in bones_wanted:
		var k: int = binds.find(b)
		if k >= 0:
			want[k] = true
	if want.is_empty():
		push_warning("build_synty_armor: %s matched no bones" % label)
		return null

	var arr: Array = src.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var ids: PackedInt32Array = arr[Mesh.ARRAY_INDEX]

	# Weights per vertex is 4 or 8 depending on how the mesh was authored — Godot sets
	# ARRAY_FLAG_USE_8_BONE_WEIGHTS for the denser ones. The dungeon characters are all 4, but
	# assuming that reads every vertex's bones from the wrong offset on an 8-weight mesh, and the
	# cut comes out as confetti sprayed over the whole body rather than a torso.
	var stride: int = 8 if verts.size() > 0 and bones.size() / verts.size() >= 8 else 4
	var keep := PackedInt32Array()
	for t in range(0, ids.size(), 3):
		var tally := {}
		for e in range(3):
			var v: int = ids[t + e]
			for w in range(stride):
				var bi: int = bones[v * stride + w]
				tally[bi] = tally.get(bi, 0.0) + weights[v * stride + w]
		var best := -1
		var best_w := 0.0
		for bi in tally:
			if tally[bi] > best_w:
				best_w = tally[bi]
				best = bi
		if not want.has(best):
			continue
		if drop_hide and _is_hide(uvs, ids, t):
			continue
		for e in range(3):
			keep.append(ids[t + e])

	if keep.is_empty():
		push_warning("build_synty_armor: %s cut nothing" % label)
		return null

	# Compact down to only the vertices the kept triangles actually use, so the saved piece is
	# not the whole character's vertex buffer with most of it unreferenced.
	var remap := {}
	var nv := PackedVector3Array()
	var nn := PackedVector3Array()
	var nuv := PackedVector2Array()
	var ni := PackedInt32Array()
	for v in keep:
		if not remap.has(v):
			remap[v] = nv.size()
			nv.append(verts[v])
			if norms.size() > v:
				nn.append(norms[v])
			if uvs.size() > v:
				nuv.append(uvs[v])
		ni.append(remap[v])

	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = nv
	if nn.size() == nv.size():
		out[Mesh.ARRAY_NORMAL] = nn
	if nuv.size() == nv.size():
		out[Mesh.ARRAY_TEX_UV] = nuv
	out[Mesh.ARRAY_INDEX] = ni

	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	# Baked in rather than left to the caller: ground_item and item_thumbnails both only reach
	# for the shared atlas when a surface has NO material, so a piece that carries its own is
	# painted correctly in both places without either of them learning about characters.
	m.surface_set_material(0, load(pack["mat"]))
	print("ARMOR cut %s: %d tris, %s" % [label, ni.size() / 3, str(m.get_aabb().size)])
	return m


func _is_hide(uvs: PackedVector2Array, ids: PackedInt32Array, t: int) -> bool:
	## True when the triangle samples goblin hide off the palette.
	##
	## Hide is olive -- red and green close together with the blue well below both. Leather is
	## browner (red clearly above green), and bone, steel and cloth are near-neutral, so the test
	## catches the goblin without eating the straps he is wearing.
	if uvs.is_empty() or _atlas == null:
		return false
	var uv := (uvs[ids[t]] + uvs[ids[t + 1]] + uvs[ids[t + 2]]) / 3.0
	# No V flip. Godot's UV origin and Image row 0 are both top-left; flipping sampled a blank
	# grey band of the atlas, and every triangle came back the same colour.
	var x: int = clampi(int(uv.x * _atlas.get_width()), 0, _atlas.get_width() - 1)
	var y: int = clampi(int(uv.y * _atlas.get_height()), 0, _atlas.get_height() - 1)
	var c: Color = _atlas.get_pixel(x, y)
	return c.b < c.r * 0.78 and absf(c.r - c.g) < 0.08 and c.g > 0.3
