extends Node3D
## A character body made of Synty Sidekick parts, whose look comes from what it WEARS.
##
## Root script of scenes/characters/sidekick_model.tscn — the CharacterModel a hero or a human
## enemy is spawned with. It builds itself in _ready, before its Combatant's _ready runs (children
## are ready first), so the skeleton, sockets and clips are all there when Combatant goes looking.
##
## --- Parts and slots ---
##
## A Sidekick character is a bare body cut into slots, every slot one skinned mesh on the same
## rig, and each part's file name says which slot it is: SK_<set>_<NN><CODE>_HU01, where NN+CODE
## is the slot ("10TORS" torso, "15HNDL" left hand, "29ASHL" left shoulder attachment...). So an
## item only has to LIST the parts it is made of (ItemResource.worn_parts): a part whose code is a
## body slot replaces the bare part there, and a part whose code is an attachment slot (22-34:
## helmet, back, hips, shoulders, elbows, knees) is added in that slot. Nothing is fitted or
## squashed — every piece was modelled on this rig.
##
## --- One skeleton ---
##
## The parts do not all ship the same skeleton (body 88 bones, beard 91, hair and capes 92 — the
## extras are the bones strands and cloth swing on), so the body's skeleton is the UNION of every
## part's (see _merge_bones). Skins bind by bone name, so any part can go on any body. Everything —
## parts, Sword Combat clips, the Quaternius libraries — is imported through a humanoid BoneMap
## (assets/animations/bonemaps/), so the core bones carry profile names (Hips, Head, RightHand)
## and every clip plays on every body.
##
## --- Colour ---
##
## Sidekick paints every part through ONE swatch layout, and a palette texture decides what the
## swatches are. A part is drawn with its own set's palette (the bare body with the species
## palette); an item can name another (ItemResource.worn_palette), which is how one cuirass can
## be leather-brown or steel.

const PART_DIRS := ["res://assets/sidekick/base/", "res://assets/sidekick/outfits/",
	"res://assets/sidekick/knights/"]
const TEXTURE_DIR := "res://assets/sidekick/textures/"

## How big the body is drawn, before Combatant's CHARACTER_SCALE (1.6). 0.5 x 1.6 = 0.8, the
## environment's own SCALE (room_builder.gd): the walls, doors and furniture are Synty pieces at
## 0.8, modelled for Synty characters, so a Sidekick body at 0.8 is in proportion with all of it.
const MODEL_SCALE := 0.5

## The bones the game hangs things on. Combatant asks (socket_bone) rather than assuming the
## Kenney rig's arm-right / arm-left / head.
const SOCKET_BONES := {"weapon": "prop_r", "shield": "prop_l", "head": "Head", "back": "UpperChest"}

## Slot codes that are the bare body. Anything else (22..34) is an attachment.
const BODY_SLOTS := ["01HEAD", "02HAIR", "03EBRL", "04EBRR", "05EYEL", "06EYER", "07EARL",
	"08EARR", "09FCHR", "10TORS", "11AUPL", "12AUPR", "13ALWL", "14ALWR", "15HNDL", "16HNDR",
	"17HIPS", "18LEGL", "19LEGR", "20FOTL", "21FOTR", "35NOSE", "36TETH", "37TONG"]

## The bare body: every BODY_SLOTS code, from one base set.
const BASE_SET := "SK_HUMN_BASE_01"

# --- The look that is not gear ---
## Hair, brows and beard, each the name of a part (any base set: SK_HUMN_BASE_01.._10 ship
## different styles). Empty keeps BASE_SET's; "none" shows nothing in that slot.
@export var hair := ""
@export var brows := ""
@export var facial_hair := ""
## Skin, eye and hair colours.
@export var skin_palette := "T_HumanSpecies_01ColorMap.png"
## Parts worn whatever the inventory says — an NPC's clothes, or a preview's.
@export var outfit: Array = []
## A quiver on the back: Goblin War Camp's leather quiver of three arrows, the same model the
## Quiver pickup shows on the floor. (No Sidekick set has a quiver among its back pieces.)
## Combatants do not set this — theirs follows the Quiver item they have slung (wear_items);
## it is for bodies with no inventory, such as a ranger in town.
@export var show_quiver := false
const QUIVER_MODEL := "res://assets/goblin_camp/SM_Prop_Quiver_01.fbx"
const QUIVER_MATERIAL := "res://assets/goblin_camp/goblin_camp_mat_01_A.tres"
## Clips this body plays in place of the usual ones, game name -> clip name in CLIPS: a ghoul
## shambles {"walk": "zombie-walk"} where everyone else walks. Combatant asks for "walk" and
## "attack-melee-right" as it always does and never needs to know.
@export var clip_overrides: Dictionary = {}

var skeleton: Skeleton3D
var anim: AnimationPlayer

## slot code -> MeshInstance3D showing there now, and the part name it was made from.
var _slots := {}
var _part_names := {}
## slot codes of the bare body that are currently replaced or hidden.
var _covered := {}
## Items last worn, so wear_items can tell a real change from a repeat.
var _worn_key := ""
var _quiver: Node3D = null

static var _materials := {}
static var _library: AnimationLibrary = null


func _ready() -> void:
	if skeleton != null:
		return
	# A DUPLICATE of a built body (the party portraits clone the live model) arrives with its
	# skeleton, parts and clips already in it as children, and only its script variables empty.
	# Building again would stack a second body inside the first, so take over what is there.
	var existing := get_node_or_null("Skeleton3D") as Skeleton3D
	if existing != null:
		skeleton = existing
		anim = get_node_or_null("AnimationPlayer") as AnimationPlayer
		for child in skeleton.get_children():
			if child is MeshInstance3D:
				_slots[String(child.name)] = child
				_part_names[String(child.name)] = String(child.get_meta("part", ""))
		return
	build()


func build() -> void:
	scale *= MODEL_SCALE
	for code in BODY_SLOTS:
		_put(code, _base_part(code), true)
	_dress_outfit()
	anim = AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	add_child(anim)
	anim.add_animation_library("", _library_for_body())
	if show_quiver:
		_add_quiver()


# --- What Combatant asks ---------------------------------------------------

func socket_bone(kind: String) -> String:
	return String(SOCKET_BONES.get(kind, ""))


func part_in(code: String) -> String:
	## Which part is showing in a slot ("" for nothing, or hidden) — for tests and tools.
	if not _slots.has(code) or not is_instance_valid(_slots[code]):
		return ""
	if not (_slots[code] as Node3D).visible:
		return ""
	return String(_part_names.get(code, ""))


func wears_gear() -> bool:
	## Whether worn items change this body's look. The Kenney bodies say no by not having this.
	return true


func wear_items(items: Array) -> void:
	## Dress the body in these items (ItemResource or null), on top of `outfit`. Called by
	## Combatant whenever equipment changes; repeats are free.
	var key := ""
	for it in items:
		key += (it.resource_path + it.item_name + ";") if it != null else "-;"
	if key == _worn_key:
		return
	_worn_key = key
	_undress()
	_dress_outfit()
	var slung := false
	for it in items:
		if it == null or not ("worn_parts" in it):
			continue
		_apply_parts(it.worn_parts, it.worn_hides, it.worn_palette)
		if it.item_type == ItemResource.ItemType.QUIVER:
			slung = true
	_show_quiver_model(show_quiver or slung)


# --- Building --------------------------------------------------------------

func _base_part(code: String) -> String:
	match code:
		"02HAIR":
			if hair != "":
				return hair
		"03EBRL", "04EBRR":
			if brows != "":
				return brows if brows == "none" else brows.replace("03EBRL", code).replace("04EBRR", code)
		"09FCHR":
			if facial_hair != "":
				return facial_hair
	return "%s_%s_HU01" % [BASE_SET, code]


static func slot_of(part: String) -> String:
	## "SK_FANT_KNGT_01_10TORS_HU01" -> "10TORS".
	var bits := part.split("_")
	return bits[bits.size() - 2] if bits.size() >= 2 else ""


func _dress_outfit() -> void:
	## The body's own clothes — what every re-dress starts from.
	_apply_parts(outfit, [], "")


func _apply_parts(parts, hides, palette: String) -> void:
	for part in parts:
		var code := slot_of(part)
		if code == "":
			continue
		_put(code, part, false, palette)
		if code in BODY_SLOTS:
			_covered[code] = true
	for code in hides:
		if _slots.has(code):
			(_slots[code] as Node3D).visible = false
			_covered[code] = true


func _undress() -> void:
	## Back to the bare body: every replaced or hidden body slot restored, every attachment gone.
	for code in _slots.keys():
		if not (code in BODY_SLOTS):
			var n := _slots[code] as Node
			n.get_parent().remove_child(n)
			n.queue_free()
			_slots.erase(code)
			_part_names.erase(code)
	for code in _covered.keys():
		_put(code, _base_part(code), true)
	_covered.clear()


func _put(code: String, part: String, bare: bool, palette: String = "") -> void:
	if _slots.has(code):
		var old := _slots[code] as Node
		old.get_parent().remove_child(old)
		old.queue_free()
		_slots.erase(code)
		_part_names.erase(code)
	if part == "none":
		return
	var mi := _take_mesh(part, bare, palette)
	if mi:
		mi.name = code
		mi.set_meta("part", part)
		_slots[code] = mi
		_part_names[code] = part


func _part_path(part: String) -> String:
	for dir in PART_DIRS:
		var p: String = dir + part + ".fbx"
		if ResourceLoader.exists(p):
			return p
	return ""


func _take_mesh(part: String, bare: bool, palette: String) -> MeshInstance3D:
	## Instance a part's scene, keep its skeleton if we have none yet, and move its mesh onto ours.
	var path := _part_path(part)
	if path == "":
		push_warning("SidekickBody: no part %s" % part)
		return null
	var root := (load(path) as PackedScene).instantiate()
	var src_skel := root.find_child("Skeleton3D", true, false) as Skeleton3D
	var mi: MeshInstance3D = null
	for n in root.find_children("*", "MeshInstance3D", true, false):
		mi = n
		break
	if mi == null:
		root.free()
		return null
	# Out of the part's own scene: a node keeps the scene that instanced it as its owner, and
	# moving it under a different one with that still set draws an "inconsistent owner" warning
	# for every part of every body.
	mi.owner = null
	if src_skel != null:
		src_skel.owner = null
	if skeleton == null and src_skel != null:
		src_skel.get_parent().remove_child(src_skel)
		src_skel.name = "Skeleton3D"
		add_child(src_skel)
		skeleton = src_skel
	else:
		if src_skel != null:
			_merge_bones(src_skel)
		mi.get_parent().remove_child(mi)
		skeleton.add_child(mi)
		mi.skeleton = NodePath("..")
	_style(mi, part, bare, palette)
	root.free()
	return mi


func _merge_bones(src: Skeleton3D) -> void:
	## Give our skeleton any bones this part's rig has and ours lacks — see the header. Without
	## it a beard's vertices follow nothing and stretch into a plank down to the floor.
	var added := false
	for i in range(src.get_bone_count()):
		var bone_name := src.get_bone_name(i)
		if skeleton.find_bone(bone_name) >= 0:
			continue
		var idx := skeleton.get_bone_count()
		skeleton.add_bone(bone_name)
		var parent := src.get_bone_parent(i)
		if parent >= 0:
			skeleton.set_bone_parent(idx, skeleton.find_bone(src.get_bone_name(parent)))
		skeleton.set_bone_rest(idx, src.get_bone_rest(i))
		skeleton.set_bone_pose(idx, src.get_bone_rest(i))
		added = true
	if added:
		# Meshes already bound resolved their Skin against the old bone list; make them look again.
		for c in skeleton.get_children():
			if c is MeshInstance3D:
				var m := c as MeshInstance3D
				m.skeleton = NodePath()
				m.skeleton = NodePath("..")


func _style(mi: MeshInstance3D, part: String, bare: bool, palette: String) -> void:
	## The palette this part is drawn with: the item's, else its own set's, else the species one.
	## Sampled NEAREST, because they are tiny swatch maps and filtering bleeds one swatch into the
	## next at every seam.
	var tex := palette
	if tex == "":
		tex = skin_palette if bare else _set_palette(part)
	if tex == "":
		# A part that brought its own texture (the starter knight): keep it, unfiltered.
		if mi.mesh:
			for s in range(mi.mesh.get_surface_count()):
				var m := mi.mesh.surface_get_material(s) as StandardMaterial3D
				if m and m.albedo_texture:
					mi.material_override = _material_for(m.albedo_texture.resource_path)
					return
		tex = skin_palette
	mi.material_override = _material_for(tex if tex.begins_with("res://") else TEXTURE_DIR + tex)


static func _set_palette(part: String) -> String:
	## Fantasy Knights sets 01-06 each have their own palette; the later sets are single pieces
	## (helmets, capes) with none, and borrow set 01's.
	if part.begins_with("SK_FANT_KNGT_"):
		var n := int(part.substr(13, 2))
		if n >= 1 and n <= 6:
			return "T_FantasyKnights_%02dColorMap.png" % n
		if n <= 15:
			return "T_FantasyKnights_01ColorMap.png"
	return ""


static func _material_for(path: String) -> StandardMaterial3D:
	if _materials.has(path):
		return _materials[path]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 0.85
	_materials[path] = m
	return m


func _show_quiver_model(on: bool) -> void:
	if on and _quiver == null:
		_add_quiver()
	if _quiver != null:
		_quiver.visible = on


func _add_quiver() -> void:
	var bone := socket_bone("back")
	if skeleton == null or skeleton.find_bone(bone) < 0:
		return
	var socket := BoneAttachment3D.new()
	socket.name = "QuiverSocket"
	socket.bone_name = bone
	skeleton.add_child(socket)
	_quiver = (load(QUIVER_MODEL) as PackedScene).instantiate() as Node3D
	var mat: Material = load(QUIVER_MATERIAL)
	for mi in _quiver.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
	# Placed in the body's own frame (facing +Z, +X its left) and carried into the bone's: the
	# UpperChest bone leans with the spine, and the skeleton node is turned from the FBX's Z-up,
	# so an offset in either space tips the quiver out backwards.
	var rest := _skeleton_frame() * skeleton.get_bone_global_rest(skeleton.find_bone(bone))
	var want := Transform3D(Basis.from_euler(QUIVER_ROTATION * PI / 180.0).scaled(Vector3.ONE * QUIVER_SCALE),
		rest.origin + QUIVER_OFFSET)
	_quiver.transform = rest.affine_inverse() * want
	socket.add_child(_quiver)


func _skeleton_frame() -> Transform3D:
	## The skeleton's transform in this body's frame.
	var t := Transform3D.IDENTITY
	var n: Node = skeleton
	while n != null and n != self:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## Behind the shoulder blades, tipped so the arrows come up over the right shoulder. The X tilt
## leans it back at rest: every stance clip hunches the upper chest forward some 25 degrees,
## which would otherwise swing the quiver's foot out behind the archer.
const QUIVER_OFFSET := Vector3(0.0, -0.05, -0.115)
const QUIVER_ROTATION := Vector3(-22, 0, 22)
const QUIVER_SCALE := 0.72


# --- Clips -----------------------------------------------------------------

## Where the clips come from. Every one of these files is imported with a humanoid BoneMap, so
## their tracks are all in Godot's humanoid profile — Hips, Chest, LeftUpperArm — whatever rig
## they were authored on, and so are the parts' bones. That is what lets a Quaternius walk drive
## a Synty body.
const SWORD := "res://assets/sidekick/anims/"
const UAL1 := "res://assets/animations/quaternius/UAL1_Standard.glb"
const UAL2 := "res://assets/animations/quaternius/UAL2_Standard.glb"
## Mixamo clips the user downloaded (Adobe, free with an account), one clip per file.
const MIX := "res://assets/animations/mixamo/"

## The game's clip names -> [source, clip in it, loops]. The left-hand names are the ones the
## Kenney models carry and Combatant already plays ("walk", "attack-melee-right", ...), so the
## combat code does not have to learn new ones; the rest are new moves the old bodies never had.
##
## The bow and the kicks come from Mixamo: neither Quaternius library has a bow draw or a kick.
const CLIPS := {
	"idle": [UAL1, "Idle", true],
	"idle-armed": [SWORD + "A_MOD_SWD_Idle_Base_Neut.fbx", "", true],
	"walk": [UAL1, "Walk", true],
	"run": [UAL1, "Jog_Fwd", true],
	"crouch": [MIX + "Crouch Idle 01.fbx", "", true],
	"crouch-walk": [UAL1, "Crouch_Fwd", true],
	"sit": [UAL1, "Sitting_Idle", true],
	"sit-down": [UAL1, "Sitting_Enter", false],
	"stand-up": [UAL1, "Sitting_Exit", false],
	"die": [SWORD + "A_MOD_SWD_Death_F_Neut.fbx", "", false],
	"attack-melee-right": [SWORD + "A_MOD_SWD_Attack_LightCombo01A_Neut.fbx", "", false],
	"attack-melee-left": [UAL2, "Sword_Regular_B", false],
	"attack-heavy": [SWORD + "A_MOD_SWD_Attack_HeavyCombo01A_Neut.fbx", "", false],
	"punch": [UAL1, "Punch_Cross", false],
	"punch-jab": [UAL1, "Punch_Jab", false],
	"attack-kick-right": [MIX + "Standing Melee Attack Kick Ver. 2.fbx", "", false],
	"kick-roundhouse": [MIX + "Roundhouse Kick.fbx", "", false],
	"kick-front": [MIX + "Kicking.fbx", "", false],
	"kick-shield": [MIX + "Sword And Shield Kick.fbx", "", false],
	"holding-both-shoot": [MIX + "Standing Draw Arrow.fbx", "", false],
	"bow-aim": [MIX + "Standing Aim Recoil.fbx", "", false],
	"bow-ready": [MIX + "Standing Equip Bow.fbx", "", false],
	"throw": [UAL2, "OverhandThrow", false],
	"cast": [MIX + "Standing 2H Magic Attack 02.fbx", "", false],
	"cast-channel": [MIX + "Magic Spell Casting.fbx", "", false],
	"cast-alt": [MIX + "Spell Casting.fbx", "", false],
	"cast-ready": [MIX + "Standing Idle 03_preparing Spell.fbx", "", true],
	"cast-simple": [UAL1, "Spell_Simple_Shoot", false],
	"idle-relaxed": [MIX + "Standing Idle 01.fbx", "", true],
	"hit-light": [MIX + "Reaction.fbx", "", false],
	"hit-light-2": [MIX + "Reaction (1).fbx", "", false],
	"hit-heavy": [MIX + "Standing React Large From Right.fbx", "", false],
	"zombie-hit": [MIX + "Zombie Reaction Hit.fbx", "", false],
	"pick-up": [UAL1, "PickUp_Table", false],
	"interact-right": [UAL1, "Interact", false],
	"open-chest": [UAL2, "Chest_Open", false],
	"hit": [SWORD + "A_MOD_SWD_Hit_F_React_Neut.fbx", "", false],
	"block": [SWORD + "A_MOD_SWD_Block_Loop_Neut.fbx", "", true],
	"dodge": [UAL1, "Roll", false],
	"knocked-down": [UAL2, "Hit_Knockback", false],
	"get-up": [UAL2, "LayToIdle", false],
	"drink": [UAL2, "Consume", false],
	"zombie-idle": [UAL2, "Zombie_Idle", true],
	"zombie-walk": [UAL2, "Zombie_Walk_Fwd", true],
	"zombie-attack": [UAL2, "Zombie_Scratch", false],
}


func _library_for_body() -> AnimationLibrary:
	return library_with(clip_overrides)


static func library_with(overrides: Dictionary) -> AnimationLibrary:
	## The shared clips, or — for a body with overrides — a library of its own in which those
	## names point at other clips. The animations themselves are shared either way; only the
	## names are this body's. Static, so any body on the humanoid profile (PolygonBody) can use it.
	var base := shared_library()
	if overrides.is_empty():
		return base
	var lib := AnimationLibrary.new()
	for clip_name in base.get_animation_list():
		lib.add_animation(clip_name, base.get_animation(clip_name))
	for key in overrides:
		var src := String(overrides[key])
		if not base.has_animation(src):
			push_warning("SidekickBody: override %s -> %s, but there is no %s" % [key, src, src])
			continue
		if lib.has_animation(key):
			lib.remove_animation(key)
		lib.add_animation(key, base.get_animation(src))
	return lib


func play(clip: String) -> void:
	if anim and anim.has_animation(clip):
		anim.play(clip)


static func shared_library() -> AnimationLibrary:
	## Every clip, built once and shared by every body: the animations are read-only once made,
	## and building them means instancing two large libraries.
	if _library != null:
		return _library
	_library = AnimationLibrary.new()
	var sources := {}
	for key in CLIPS:
		var entry: Array = CLIPS[key]
		var a := _clip_from(sources, String(entry[0]), String(entry[1]))
		if a == null:
			push_warning("SidekickBody: no clip %s in %s" % [entry[1], entry[0]])
			continue
		a.loop_mode = Animation.LOOP_LINEAR if entry[2] else Animation.LOOP_NONE
		_library.add_animation(key, a)
	for k in sources:
		(sources[k] as Node).free()
	return _library


static func _clip_from(sources: Dictionary, path: String, clip: String) -> Animation:
	## One clip out of a source file, with its tracks re-pointed at OUR skeleton. Each library
	## keeps its skeleton somewhere different ("Rig/Skeleton3D", "Armature/Skeleton3D", plain
	## "Skeleton3D") and a track's path names it; everything after the colon is the (already
	## humanoid-renamed) bone, so only the node half is rewritten.
	if not sources.has(path):
		var ps: PackedScene = load(path)
		if ps == null:
			return null
		sources[path] = ps.instantiate()
	var ap := (sources[path] as Node).find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:
		return null
	var src: Animation = null
	for lib_name in ap.get_animation_library_list():
		var lib := ap.get_animation_library(lib_name)
		if clip == "":
			src = lib.get_animation(lib.get_animation_list()[0])
		elif lib.has_animation(clip):
			src = lib.get_animation(clip)
		if src != null:
			break
	if src == null:
		return null
	var a: Animation = src.duplicate(true)
	for t in range(a.get_track_count()):
		var tp := String(a.track_get_path(t))
		var colon := tp.find(":")
		if colon >= 0:
			a.track_set_path(t, NodePath("Skeleton3D" + tp.substr(colon)))
	return a


# --- For tools -------------------------------------------------------------

static func parts_of_set(set_prefix: String) -> PackedStringArray:
	## Every part of one outfit set (e.g. "SK_FANT_KNGT_02"), by listing the part folders. Only for
	## dev tools: a res:// directory listing is not dependable in an exported build.
	var out := PackedStringArray()
	for dir in PART_DIRS:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			if f.begins_with(set_prefix + "_") and f.ends_with(".fbx"):
				var part := f.trim_suffix(".fbx")
				if not out.has(part):
					out.append(part)
	return out
