extends Node3D
## A Synty Sidekick character assembled from parts, with gear that REPLACES parts.
##
## TEST / PROTOTYPE for the gear-driven look (see the roadmap). A Sidekick character is a bare
## body cut into slots — head, hair, torso, upper and lower arms, hands, hips, legs, feet and so
## on — every slot one skinned mesh on the same 88-bone rig. An outfit is the same slots cut
## from armour instead of skin, plus ATTACHMENTS that have no bare-body counterpart (shoulder
## pads, elbow and knee guards, hip plates, a helmet). So wearing a cuirass is: take the bare
## torso and arms off, put the cuirass's torso and arms on, add its pauldrons. Nothing is fitted
## or squashed, because every piece was modelled on this rig.
##
## Built at runtime from the imported FBX parts: one Skeleton3D is taken from the first part
## and every other part's mesh is moved onto it. That works because each part's Skin binds by
## BONE NAME, and all parts and all the Sword Combat clips share the rig's bone names.
##
## The clips target "Skeleton3D:<bone>", so an AnimationPlayer whose root is this node plays
## them as imported.

const BASE_DIR := "res://assets/sidekick/base/"
const OUTFIT_DIR := "res://assets/sidekick/outfits/"
const ANIM_DIR := "res://assets/sidekick/anims/"
## Skin, hair and eye colours for the bare body: one of the pack's species palettes.
const BASE_COLORMAP := "res://assets/sidekick/textures/T_HumanSpecies_01ColorMap.png"

## The bare body, slot by slot. Sidekick numbers its slots; the two digits before the slot code
## are that number, and the name after the code is what the slot is.
const BASE_PARTS := {
	"head": "SK_HUMN_BASE_01_01HEAD_HU01",
	"hair": "SK_HUMN_BASE_01_02HAIR_HU01",
	"brow_l": "SK_HUMN_BASE_01_03EBRL_HU01",
	"brow_r": "SK_HUMN_BASE_01_04EBRR_HU01",
	"eye_l": "SK_HUMN_BASE_01_05EYEL_HU01",
	"eye_r": "SK_HUMN_BASE_01_06EYER_HU01",
	"ear_l": "SK_HUMN_BASE_01_07EARL_HU01",
	"ear_r": "SK_HUMN_BASE_01_08EARR_HU01",
	"facial_hair": "SK_HUMN_BASE_01_09FCHR_HU01",
	"torso": "SK_HUMN_BASE_01_10TORS_HU01",
	"upper_arm_l": "SK_HUMN_BASE_01_11AUPL_HU01",
	"upper_arm_r": "SK_HUMN_BASE_01_12AUPR_HU01",
	"lower_arm_l": "SK_HUMN_BASE_01_13ALWL_HU01",
	"lower_arm_r": "SK_HUMN_BASE_01_14ALWR_HU01",
	"hand_l": "SK_HUMN_BASE_01_15HNDL_HU01",
	"hand_r": "SK_HUMN_BASE_01_16HNDR_HU01",
	"hips": "SK_HUMN_BASE_01_17HIPS_HU01",
	"leg_l": "SK_HUMN_BASE_01_18LEGL_HU01",
	"leg_r": "SK_HUMN_BASE_01_19LEGR_HU01",
	"foot_l": "SK_HUMN_BASE_01_20FOTL_HU01",
	"foot_r": "SK_HUMN_BASE_01_21FOTR_HU01",
	"nose": "SK_HUMN_BASE_01_35NOSE_HU01",
	"teeth": "SK_HUMN_BASE_01_36TETH_HU01",
	"tongue": "SK_HUMN_BASE_01_37TONG_HU01",
}

## Test gear, as the ItemResource fields would hold it: the slots a piece takes over (a bare
## part is hidden, or swapped for the piece's own part of that slot), and attachments it adds.
## `hides` lists bare slots a piece covers without replacing — a helmet over the hair.
const GEAR := {
	"knight_cuirass": {
		"slots": {
			"torso": "SK_FANT_KNGT_17_10TORS_HU01",
			"upper_arm_l": "SK_FANT_KNGT_17_11AUPL_HU01",
			"upper_arm_r": "SK_FANT_KNGT_17_12AUPR_HU01",
			"lower_arm_l": "SK_FANT_KNGT_17_13ALWL_HU01",
			"lower_arm_r": "SK_FANT_KNGT_17_14ALWR_HU01",
		},
		"attach": ["SK_FANT_KNGT_17_29ASHL_HU01", "SK_FANT_KNGT_17_30ASHR_HU01",
			"SK_FANT_KNGT_17_31AEBL_HU01", "SK_FANT_KNGT_17_32AEBR_HU01",
			"SK_FANT_KNGT_17_24ABAC_HU01"],
	},
	"knight_greaves": {
		"slots": {
			"hips": "SK_FANT_KNGT_17_17HIPS_HU01",
			"leg_l": "SK_FANT_KNGT_17_18LEGL_HU01",
			"leg_r": "SK_FANT_KNGT_17_19LEGR_HU01",
		},
		"attach": ["SK_FANT_KNGT_17_25AHPF_HU01", "SK_FANT_KNGT_17_26AHPB_HU01",
			"SK_FANT_KNGT_17_27AHPL_HU01", "SK_FANT_KNGT_17_28AHPR_HU01",
			"SK_FANT_KNGT_17_33AKNL_HU01", "SK_FANT_KNGT_17_34AKNR_HU01"],
	},
	"knight_boots": {
		"slots": {"foot_l": "SK_FANT_KNGT_17_20FOTL_HU01", "foot_r": "SK_FANT_KNGT_17_21FOTR_HU01"},
	},
	"knight_gauntlets": {
		"slots": {"hand_l": "SK_FANT_KNGT_17_15HNDL_HU01", "hand_r": "SK_FANT_KNGT_17_16HNDR_HU01"},
	},
	"knight_helm": {
		"attach": ["SK_FANT_KNGT_17_22AHED_HU01", "SK_FANT_KNGT_17_23AFAC_HU01"],
		"hides": ["hair", "ear_l", "ear_r"],
	},
	"villain_hood": {
		"attach": ["SK_HORR_VILN_01_22AHED_HU01"],
		"hides": ["hair", "ear_l", "ear_r"],
	},
}

const CLIPS := {
	"idle": "A_MOD_SWD_Idle_Base_Neut",
	"attack": "A_MOD_SWD_Attack_LightCombo01A_Neut",
	"heavy": "A_MOD_SWD_Attack_HeavyCombo01A_Neut",
	"hit": "A_MOD_SWD_Hit_F_React_Neut",
	"block": "A_MOD_SWD_Block_Loop_Neut",
	"die": "A_MOD_SWD_Death_F_Neut",
}

## A base slot to leave out, for tracking down a part that renders wrong.
var omit := ""
var skeleton: Skeleton3D
var anim: AnimationPlayer
## slot -> the MeshInstance3D showing in it now.
var _slots := {}
## Meshes added by gear attachments, so taking the gear off removes them.
var _attached := {}
var _worn: Array = []
static var _base_mat: StandardMaterial3D = null


func build(gear: Array = []) -> void:
	for slot in BASE_PARTS:
		if slot == omit:
			continue
		_set_slot(slot, BASE_DIR + BASE_PARTS[slot] + ".fbx", true)
	for g in gear:
		wear(g)
	_build_animation()


func wear(gear_id: String) -> void:
	var g: Dictionary = GEAR.get(gear_id, {})
	if g.is_empty() or _worn.has(gear_id):
		return
	_worn.append(gear_id)
	var slots: Dictionary = g.get("slots", {})
	for slot in slots:
		_set_slot(slot, OUTFIT_DIR + slots[slot] + ".fbx", false)
	for slot in g.get("hides", []):
		if _slots.has(slot):
			(_slots[slot] as Node3D).visible = false
	var added: Array = []
	for part in g.get("attach", []):
		var mi := _take_mesh(OUTFIT_DIR + part + ".fbx", false)
		if mi:
			added.append(mi)
	_attached[gear_id] = added


func play(clip: String) -> void:
	if anim and anim.has_animation(clip):
		anim.play(clip)


func _set_slot(slot: String, path: String, bare: bool) -> void:
	if _slots.has(slot):
		(_slots[slot] as Node).queue_free()
		_slots.erase(slot)
	var mi := _take_mesh(path, bare)
	if mi:
		_slots[slot] = mi


func _take_mesh(path: String, bare: bool) -> MeshInstance3D:
	## Instance a part's scene, keep its skeleton if we have none yet, and move its mesh onto
	## ours.
	var ps: PackedScene = load(path)
	if ps == null:
		push_warning("SidekickBody: missing part %s" % path)
		return null
	var root := ps.instantiate()
	var src_skel := root.find_child("Skeleton3D", true, false) as Skeleton3D
	var mi: MeshInstance3D = null
	for n in root.find_children("*", "MeshInstance3D", true, false):
		mi = n
		break
	if skeleton == null and src_skel != null:
		src_skel.get_parent().remove_child(src_skel)
		src_skel.name = "Skeleton3D"
		add_child(src_skel)
		skeleton = src_skel
		# The first part's mesh came along with its skeleton; it is already in place.
		if mi != null and mi.get_parent() == skeleton:
			_style(mi, bare)
			root.free()
			return mi
	if mi == null:
		root.free()
		return null
	if src_skel != null:
		_merge_bones(src_skel)
	mi.get_parent().remove_child(mi)
	skeleton.add_child(mi)
	mi.skeleton = NodePath("..")
	_style(mi, bare)
	root.free()
	return mi


func _merge_bones(src: Skeleton3D) -> void:
	## Give our skeleton any bones this part's rig has and ours lacks.
	##
	## The parts do NOT all ship the same skeleton: the body is 88 bones, the beard 91, the hair
	## and the cape 92 — the extras are the strands and cloth those pieces swing on. A mesh whose
	## Skin names a bone the skeleton does not have leaves those vertices following nothing, which
	## is what stretched the beard into a plank down to the floor and dropped the cape in a heap
	## at the feet. Copied with their parent and rest, so they hang where the part expects.
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


func _style(mi: MeshInstance3D, bare: bool) -> void:
	## Bare-body parts come in with an untextured material: give them the species palette.
	## Outfit parts brought their own palette texture. Both are tiny swatch maps, so they are
	## sampled NEAREST — filtered, neighbouring swatches bleed into each other at the seams.
	if bare:
		if _base_mat == null:
			_base_mat = StandardMaterial3D.new()
			_base_mat.albedo_texture = load(BASE_COLORMAP)
			_base_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			_base_mat.roughness = 0.9
		mi.material_override = _base_mat
		return
	if mi.mesh == null:
		return
	for s in range(mi.mesh.get_surface_count()):
		var m := mi.mesh.surface_get_material(s) as StandardMaterial3D
		if m:
			var own := m.duplicate() as StandardMaterial3D
			own.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mi.set_surface_override_material(s, own)


func _build_animation() -> void:
	anim = AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	add_child(anim)
	var lib := AnimationLibrary.new()
	for key in CLIPS:
		var ps: PackedScene = load(ANIM_DIR + CLIPS[key] + ".fbx")
		if ps == null:
			continue
		var root := ps.instantiate()
		var ap := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap:
			var src_lib := ap.get_animation_library(ap.get_animation_library_list()[0])
			var a: Animation = src_lib.get_animation(src_lib.get_animation_list()[0]).duplicate()
			a.loop_mode = Animation.LOOP_LINEAR if key in ["idle", "block"] else Animation.LOOP_NONE
			lib.add_animation(key, a)
		root.free()
	anim.add_animation_library("", lib)
