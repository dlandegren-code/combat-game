extends Node3D
## A whole-character body from the POLYGON Dungeon pack — a skeleton, a ghost, a golem — driven by
## the same clips as the Sidekick bodies.
##
## Root script of scenes/characters/polygon_model.tscn. Where a Sidekick body is assembled from
## parts and dressed by its gear, a Polygon character is ONE mesh with its outfit modelled on —
## the Skeleton Knight's armour is part of the skeleton — so this body shows one character and
## does not change with what is worn. What it shares with the Sidekick body is everything that
## moves: the pack was imported through Godot's humanoid retarget, so its bones carry the profile
## names (Hips, RightHand...) the shared clip library is written in, and SidekickBody's clips and
## clip overrides drive it unchanged.
##
## Every Polygon character prefab carries all sixteen characters' meshes on one skeleton with one
## switched on; this takes the skeleton and switches on the one asked for.

const SidekickBodyScript := preload("res://scripts/sidekick_body.gd")

## Any of the pack's character prefabs will do as the source: they all hold every mesh.
const PREFAB := "res://assets/PolygonDungeon/Prefabs/Characters/Character_Skeleton_Soldier_01.tscn"
## Where to copy the prop bones from — see _add_prop_bones.
const SIDEKICK_RIG := "res://assets/sidekick/base/SK_HUMN_BASE_01_10TORS_HU01.fbx"

## Same as the Sidekick body: 0.5 before Combatant's 1.6, the environment's 0.8. The Polygon
## characters stand 1.87 against Sidekick's 1.8, so the two sit together.
const MODEL_SCALE := 0.5

## Held things go on prop bones this body ADDS (the Polygon rig has none), copied from the
## Sidekick rig's own, so every item's worn_* grip tuned on a Sidekick hand fits this one too.
const SOCKET_BONES := {"weapon": "prop_r", "shield": "prop_l", "head": "Head", "back": "UpperChest"}

## Where the characters come from: any scene holding a pack's characters as meshes on one
## humanoid-retargeted skeleton. The Dungeon pack's prefab by default; the Viking pack's
## VikingRealm_Characters.fbx is another (imported through bonemaps/polygon_bonemap.tres).
@export var source := PREFAB
## Which character: the name of its mesh in `source` (Character_Skeleton_Soldier_01,
## Character_Ghost_01, SM_Chr_Warrior_Male_01 ...).
@export var character := "Character_Skeleton_Soldier_01"
## Characters to pick from instead, one at random per body — so a pack of goblins is not one
## goblin five times. Cosmetic only: which one turns up is not part of any seed's contract.
@export var character_pool: Array = []
## Pack attachments to show as well (SM_Item_Goblin_Hair, SM_Chr_Attach_Fur_01...) — meshes in
## `source` skinned to the same skeleton, so they need no fitting.
@export var attachments: Array = []
## One more attachment, picked at random per body (cosmetic, like character_pool). "" in the list
## is a legal pick: nothing.
@export var attachment_pool: Array = []
## The atlas to draw the body with, for a pack whose meshes arrive untextured (the Vikings).
## Empty keeps the meshes' own materials (the Dungeon pack's prefabs carry theirs).
@export var texture := ""
## Or one of these, at random per body: a pack's A / B / C atlases are the same layout in
## different colours, which is cheap variety for a warband.
@export var texture_pool: Array = []
## Meshes worn on the Head bone — the Viking pack ships its helmets, beards and crowns as their
## own head-local FBX files rather than skinned into the characters. Each entry is a scene path,
## or an Array of them to pick one from at random per body ("" in it is a legal pick: nothing).
@export var head_attachments: Array = []
## As SidekickBody.clip_overrides.
@export var clip_overrides: Dictionary = {}
## Float this high off the floor, bobbing gently — for a ghost, which has a trail where its legs
## would be. In the body's own units (it is 1.87 tall). 0 stands on the floor.
@export var hover := 0.0
const HOVER_BOB := 0.05
const HOVER_PERIOD := 2.6
var _bob_t := 0.0

var skeleton: Skeleton3D
var anim: AnimationPlayer


func _ready() -> void:
	if skeleton != null:
		return
	# A duplicate (party portrait) arrives built; take over what is there. See SidekickBody._ready.
	var existing := get_node_or_null("Skeleton3D") as Skeleton3D
	if existing != null:
		skeleton = existing
		anim = get_node_or_null("AnimationPlayer") as AnimationPlayer
		return
	build()


func build() -> void:
	if not character_pool.is_empty():
		character = String(character_pool[randi() % character_pool.size()])
	var shown_attachments: Array = attachments.duplicate()
	if not attachment_pool.is_empty():
		var extra := String(attachment_pool[randi() % attachment_pool.size()])
		if extra != "":
			shown_attachments.append(extra)
	if not texture_pool.is_empty():
		texture = String(texture_pool[randi() % texture_pool.size()])
	scale *= MODEL_SCALE
	var root := (load(source) as PackedScene).instantiate()
	var src := root.find_child("GeneralSkeleton", true, false) as Skeleton3D
	if src == null:
		src = root.find_child("Skeleton3D", true, false) as Skeleton3D
	# See SidekickBody._take_mesh: disown before moving, or every node warns.
	for n in [src] + src.find_children("*", "", true, false):
		n.owner = null
	src.get_parent().remove_child(src)
	root.free()
	src.name = "Skeleton3D"
	add_child(src)
	skeleton = src
	var shown := 0
	for mi in skeleton.find_children("*", "MeshInstance3D", true, false):
		var on: bool = mi.name == character or shown_attachments.has(String(mi.name))
		mi.visible = on
		if on:
			shown += 1
		# The prefab's meshes name their skeleton by its old unique name (%GeneralSkeleton), which
		# the rename breaks — the skeleton then animates and the mesh stays in its bind pose, a
		# T-posed skeleton holding a moving sword. Point them at it by position instead.
		if mi.get_parent() == skeleton:
			(mi as MeshInstance3D).skeleton = NodePath("..")
		if on and texture != "":
			(mi as MeshInstance3D).material_override = _atlas(texture)
	if shown == 0:
		push_warning("PolygonBody: no character mesh called %s" % character)
	# The prefab's own Attachments node holds the sword and shield it was posed with; the game
	# puts its own in the hands, so everything not asked for is dropped rather than just hidden.
	for mi in skeleton.find_children("*", "MeshInstance3D", true, false):
		if not mi.visible:
			mi.get_parent().remove_child(mi)
			mi.queue_free()
	_add_prop_bones()
	_add_head_attachments()
	# Different ghosts bob out of step with each other.
	_bob_t = randf() * HOVER_PERIOD
	set_process(hover > 0.0)
	anim = AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	add_child(anim)
	anim.add_animation_library("", SidekickBodyScript.library_with(clip_overrides))


static var _atlases := {}


static func _atlas(path: String) -> StandardMaterial3D:
	if _atlases.has(path):
		return _atlases[path]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.roughness = 0.85
	_atlases[path] = m
	return m


func _add_head_attachments() -> void:
	var head := skeleton.find_bone("Head")
	if head < 0 or head_attachments.is_empty():
		return
	var socket := BoneAttachment3D.new()
	socket.name = "HeadAttachments"
	socket.bone_name = "Head"
	skeleton.add_child(socket)
	for entry in head_attachments:
		var path := String(entry[randi() % entry.size()]) if entry is Array else String(entry)
		if path == "" or not ResourceLoader.exists(path):
			continue
		var node := (load(path) as PackedScene).instantiate() as Node3D
		if texture != "":
			for mi in node.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_override = _atlas(texture)
		socket.add_child(node)


func _add_prop_bones() -> void:
	## prop_r and prop_l, under RightHand and LeftHand, at the rest the Sidekick rig gives its own.
	## Both rigs went through the same humanoid retarget, which rewrites every mapped bone's axes
	## to the profile's, so a hand is the same frame on both and a pose relative to it carries over.
	var ps: PackedScene = load(SIDEKICK_RIG)
	if ps == null:
		return
	var rig_root := ps.instantiate()
	var rig := rig_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if rig != null:
		for pair in [["prop_r", "RightHand"], ["prop_l", "LeftHand"]]:
			var src_bone := rig.find_bone(pair[0])
			var hand := skeleton.find_bone(pair[1])
			if src_bone < 0 or hand < 0 or skeleton.find_bone(pair[0]) >= 0:
				continue
			var idx := skeleton.get_bone_count()
			skeleton.add_bone(pair[0])
			skeleton.set_bone_parent(idx, hand)
			skeleton.set_bone_rest(idx, rig.get_bone_rest(src_bone))
			skeleton.set_bone_pose(idx, rig.get_bone_rest(src_bone))
	rig_root.free()


func _process(delta: float) -> void:
	## The skeleton rides up and down, not this node: Combatant moves the CharacterModel itself
	## (the shove stagger), and a bob on the same node would fight it.
	if skeleton == null:
		return
	_bob_t += delta
	skeleton.position.y = hover + sin(_bob_t / HOVER_PERIOD * TAU) * HOVER_BOB


# --- What Combatant asks — the same answers a SidekickBody gives ------------

func socket_bone(kind: String) -> String:
	return String(SOCKET_BONES.get(kind, ""))


func wears_gear() -> bool:
	## Yes, in the sense Combatant means it: hold items on this body's prop bones, at their worn
	## size. Its LOOK does not change with armour — that is modelled on — so wear_items is empty.
	return true


func wear_items(_items: Array) -> void:
	pass


func part_in(_code: String) -> String:
	return ""


func play(clip: String) -> void:
	if anim and anim.has_animation(clip):
		anim.play(clip)
