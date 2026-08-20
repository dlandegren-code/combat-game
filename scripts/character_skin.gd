extends Node3D
## Applies a body material to the instanced character GLB at runtime.
## The .tscn property-override on instanced GLB children is not reliably
## applied at runtime; setting material_override from code guarantees it.
## The head-mesh is left untouched so original facial features are preserved.
## When show_robe is enabled a tapered cylinder mesh is added around the
## upper legs to give a robe/skirt silhouette distinct from other characters.

@export var body_material: Material
## Optional extra materials for a body mesh split into surfaces by
## tools/build_archer_body_split.gd (0 = torso + arms, 1 = legs, 2 = boots). Leave
## unset to paint the whole body alike.
@export var legs_material: Material
@export var boots_material: Material
@export var show_robe: bool = false
@export var robe_color: Color = Color(0.12, 0.06, 0.28, 1.0)
@export var show_quiver: bool = false

## Long hair hanging from the head bone, in alternating light/dark strands.
## The hair ON the skull is a separate thing: it is baked into the head mesh by
## tools/build_wizard_hair.gd. Keep these two colours matching the palette cells
## that tool paints with, or crown and strands will not read as one head of hair.
@export var show_long_hair: bool = false
@export var hair_color_main: Color = Color(0.937, 0.937, 0.969, 1.0)
@export var hair_color_streak: Color = Color(0.271, 0.263, 0.302, 1.0)
## Beard and moustache, in the same two tones as the hair.
@export var show_beard: bool = false
@export var show_eyebrows: bool = false

## Belt, chest strap and shoulder caps, to break up an otherwise flat outfit. The
## archer's leather texture is 98% two near-identical dark shades, so it reads as one
## slab of colour at camera distance; these are the accents that give it definition.
@export var show_outfit_trim: bool = false
## Light brown from this rig's own palette, for the leather pieces.
@export var trim_color_leather: Color = Color(0.624, 0.361, 0.259, 1.0)
## The palette's only greens are teal, which would clash, so the cloth green is a
## plain dark olive chosen to sit against the near-black leather.
@export var trim_color_cloth: Color = Color(0.180, 0.320, 0.180, 1.0)

## The equipped quiver instantiates the SAME scene the ground pickup uses, so the two
## can never drift apart. It previously rebuilt an approximation in code with a flat
## brown StandardMaterial3D body and only two arrows, which is why it read as far more
## monotonous than the pickup: the scene's body carries the textured Synty atlas, and
## it has three arrows.
const QUIVER_SCENE := "res://scenes/items/quiver.tscn"
## The scene's body cylinder is 0.3 tall; the socket placement was tuned around 0.25.
const QUIVER_SCALE := 0.833
const QUIVER_POS := Vector3(0.18, -0.02, -0.12)
const QUIVER_ROT := Vector3(15.0, 0.0, -20.0)

## Long hair, in head-bone local space. The head bone sits at the BASE of the skull
## (its origin is y = 0.343 in mesh space, with the skull spanning 0.343 .. 0.722),
## so the crown is about +0.38 above the socket and the skull is ~0.34 wide.
const HAIR_STRANDS := 11
## Arc swept around the head, in degrees. 0 is straight ahead, so this runs from one
## cheek round the back to the other and leaves the face clear.
const HAIR_ARC_START := 42.0
const HAIR_ARC_END := 318.0
## Just outside the skull shell (its surface is at radius 0.17) so the strands sit on
## the hair rather than intersecting it.
const HAIR_RADIUS := 0.178
## Where a strand's top sits, level with the temples rather than the crown.
const HAIR_TOP_Y := 0.235
## Length is in mesh units and CHARACTER_SCALE (1.6) multiplies it on screen, so this
## is much shorter than it looks. Strand tops land at world y 1.04 and the arena floor
## is at 0.2, so 0.52 here would drag the hair along the ground; 0.34 puts the ends
## between world y 0.49 and 0.60 — shoulder to mid-back.
const HAIR_LENGTH := 0.34
## Every third strand is cut a little shorter so the ends are ragged, not a blunt line.
const HAIR_LENGTH_STEP := 0.035
const HAIR_STRAND_WIDTH := 0.055
const HAIR_STRAND_DEPTH := 0.032
## Slight outward lean so the hair falls over the shoulders instead of hugging the neck.
const HAIR_FLARE_DEG := 7.0

## Beard, also in head-bone local space. Measured landmarks on this rig: the chin is
## level with the bone origin (y 0), the face plane is at z 0.160, and the mouth quad
## spans y 0.058 .. 0.092.
const BEARD_Z := 0.138
## Just under the lower lip, so the beard covers the jaw and not the mouth.
const BEARD_TOP_Y := 0.055
## Per-strand half-widths out from centre, and the length of each. Longest in the
## middle so the beard comes to a point like a wizard's should. Lengths are mesh
## units and CHARACTER_SCALE (1.6) multiplies them: 0.21 reaches world y 0.42,
## roughly mid-chest.
const BEARD_STRANDS := [
	Vector2(-0.062, 0.115),
	Vector2(-0.032, 0.170),
	Vector2(0.0, 0.210),
	Vector2(0.032, 0.170),
	Vector2(0.062, 0.115),
]
const BEARD_STRAND_WIDTH := 0.036
const BEARD_STRAND_DEPTH := 0.030
## Moustache: a single bar across the top lip.
const MOUSTACHE_Y := 0.098
const MOUSTACHE_SIZE := Vector3(0.105, 0.026, 0.028)

## Eyebrows. This rig has no brow geometry of its own (the soldier does, male_d does
## not), so they are built from scratch. The eye quads sit at x +/-0.072 spanning
## y 0.462 .. 0.511 in mesh space — local y 0.119 .. 0.168 — so the brows ride just
## above that, and slightly proud of the face plane so they read as bushy.
const BROW_X := 0.072
const BROW_Y := 0.185
const BROW_Z := 0.166
const BROW_SIZE := Vector3(0.060, 0.020, 0.022)
## Outer ends dropped a little; a characterful slant rather than a flat bar.
const BROW_TILT_DEG := 7.0

## Outfit trim, in TORSO-bone local space. The torso bone sits at mesh y 0.176,
## z -0.029, and the torso itself spans local y 0 .. 0.167, x +/-0.139, z -0.123 .. 0.129
## (measured from the triangles that bone dominates), so its front face is z 0.129 and
## its depth centre is z 0.003.
const BELT_Y := 0.022
const BELT_RADIUS := 0.145
const BELT_HEIGHT := 0.028
## Chest strap for the quiver, which rides the +x side, so the strap runs over that
## shoulder and down to the opposite hip.
const STRAP_POS := Vector3(0.025, 0.085, 0.128)
## 0.200 long overshot the torso at both ends (poking above the shoulder and below the
## waist); at this tilt 0.175 keeps it inside the torso's world span.
const STRAP_SIZE := Vector3(0.042, 0.175, 0.022)
const STRAP_TILT_DEG := -32.0
## Shoulder caps sit on the torso rather than the arm bones: the arm bones' rest pose
## points outward, so an offset along them is guesswork, while shoulders barely move
## relative to the torso.
const SHOULDER_X := 0.105
## 0.158 put the caps' underside at world y 0.620, clipping the top of the quiver at
## 0.635; 0.168 lifts them clear while still straddling the shoulder line (0.660).
const SHOULDER_Y := 0.168
const SHOULDER_SIZE := Vector3(0.075, 0.030, 0.100)

## Pouch hanging off the belt. Placed on -x, opposite the quiver (which rides +x), and
## just proud of the torso's 0.139 half-width so it reads as hanging rather than sunk.
const POUCH_POS := Vector3(-0.118, -0.004, 0.055)
const POUCH_SIZE := Vector3(0.055, 0.062, 0.042)

## Bracers, in ARM-bone local space. All four limb bones have an identity basis, so
## these offsets are axis-aligned, and being bone-local they stay on the forearm
## whatever the animation does with the arm. The left arm's own triangles run
## x 0 .. 0.284 out from the shoulder, so x 0.205 lands on the forearm; the right arm
## mirrors on x.
const BRACER_X := 0.205
## Measured cross-section at that slice: 0.133 tall, 0.164 deep, depth centred on
## z 0.042 (NOT on the bone axis). The band must exceed those or it renders INSIDE the
## arm and is invisible — an earlier 0.105 x 0.105 was swallowed whole.
const BRACER_Z := 0.042
const BRACER_SIZE := Vector3(0.075, 0.148, 0.178)

func _ready() -> void:
	call_deferred("_apply_body_material")
	call_deferred("_apply_quiver")
	call_deferred("_apply_long_hair")
	call_deferred("_apply_beard")
	call_deferred("_apply_eyebrows")
	call_deferred("_apply_outfit_trim")

func _apply_body_material() -> void:
	if body_material == null:
		return
	var skeleton := get_node_or_null("character-male-d/character-male-d/Skeleton3D") as Skeleton3D
	var body_mesh := get_node_or_null("character-male-d/character-male-d/Skeleton3D/body-mesh") as MeshInstance3D
	if body_mesh:
		var surfaces: int = body_mesh.mesh.get_surface_count() if body_mesh.mesh else 0
		if legs_material != null and surfaces > 1:
			# material_override paints EVERY surface, which would defeat the split, so
			# assign per surface instead and leave material_override clear.
			body_mesh.set_surface_override_material(0, body_material)
			body_mesh.set_surface_override_material(1, legs_material)
			if boots_material != null and surfaces > 2:
				body_mesh.set_surface_override_material(2, boots_material)
		else:
			body_mesh.material_override = body_material
	if show_robe and skeleton:
		_add_robe(skeleton)

func _add_robe(skeleton: Skeleton3D) -> void:
	var robe := MeshInstance3D.new()
	robe.name = "Robe"
	var cyl := CylinderMesh.new()
	cyl.height = 0.20
	cyl.top_radius = 0.14
	cyl.bottom_radius = 0.22
	cyl.radial_segments = 12
	robe.mesh = cyl
	robe.position = Vector3(0.0, 0.11, -0.01)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = robe_color
	mat.roughness = 0.85
	robe.material_override = mat
	skeleton.add_child(robe)


func _bone_socket(socket_name: String, bone: String) -> BoneAttachment3D:
	## A bone attachment, so whatever hangs off it follows that bone as it animates.
	## Returns null when there is no skeleton to attach to.
	var skeleton := get_node_or_null("character-male-d/character-male-d/Skeleton3D") as Skeleton3D
	if skeleton == null:
		return null
	var socket := BoneAttachment3D.new()
	socket.name = socket_name
	socket.bone_name = bone
	skeleton.add_child(socket)
	return socket


func _head_socket(socket_name: String) -> BoneAttachment3D:
	return _bone_socket(socket_name, "head")


func _hair_materials() -> Array:
	## [main, streak]. One material per tone, shared by every piece using it, rather
	## than one per piece — 11 strands would otherwise mean 11 identical materials.
	var mats := []
	for c in [hair_color_main, hair_color_streak]:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.85
		mats.append(m)
	return mats


func _apply_long_hair() -> void:
	if not show_long_hair:
		return
	var socket := _head_socket("HairSocket")
	if socket == null:
		return
	var mats := _hair_materials()

	for i in HAIR_STRANDS:
		var t: float = float(i) / float(HAIR_STRANDS - 1)
		var ang := deg_to_rad(lerp(HAIR_ARC_START, HAIR_ARC_END, t))
		var length: float = HAIR_LENGTH - (i % 3) * HAIR_LENGTH_STEP

		var strand := MeshInstance3D.new()
		strand.name = "HairStrand" + str(i + 1)
		var box := BoxMesh.new()
		box.size = Vector3(HAIR_STRAND_WIDTH, length, HAIR_STRAND_DEPTH)
		strand.mesh = box
		# Alternating tones are what make it read as striped.
		strand.material_override = mats[i % 2]

		# Box mesh is centred on its origin, so drop it half its length to hang the
		# top edge at HAIR_TOP_Y.
		var dir := Vector3(sin(ang), 0.0, cos(ang))
		strand.position = dir * HAIR_RADIUS + Vector3(0.0, HAIR_TOP_Y - length * 0.5, 0.0)
		# Face the strand outward, then lean it away from the neck.
		strand.rotation_degrees = Vector3(0.0, rad_to_deg(ang), 0.0)
		strand.rotate_object_local(Vector3.RIGHT, deg_to_rad(-HAIR_FLARE_DEG))
		socket.add_child(strand)


func _apply_beard() -> void:
	if not show_beard:
		return
	var socket := _head_socket("BeardSocket")
	if socket == null:
		return
	var mats := _hair_materials()

	for i in BEARD_STRANDS.size():
		var spec: Vector2 = BEARD_STRANDS[i]
		var strand := MeshInstance3D.new()
		strand.name = "BeardStrand" + str(i + 1)
		var box := BoxMesh.new()
		box.size = Vector3(BEARD_STRAND_WIDTH, spec.y, BEARD_STRAND_DEPTH)
		strand.mesh = box
		strand.material_override = mats[i % 2]
		# Box is centred on its origin, so drop it half its length to hang from the jaw.
		strand.position = Vector3(spec.x, BEARD_TOP_Y - spec.y * 0.5, BEARD_Z)
		socket.add_child(strand)

	var mous := MeshInstance3D.new()
	mous.name = "Moustache"
	var mbox := BoxMesh.new()
	mbox.size = MOUSTACHE_SIZE
	mous.mesh = mbox
	mous.material_override = mats[0]
	mous.position = Vector3(0.0, MOUSTACHE_Y, BEARD_Z + 0.012)
	socket.add_child(mous)


func _apply_eyebrows() -> void:
	if not show_eyebrows:
		return
	var socket := _head_socket("BrowSocket")
	if socket == null:
		return
	var mats := _hair_materials()

	for x in [-BROW_X, BROW_X]:
		var brow := MeshInstance3D.new()
		brow.name = "Brow" + ("L" if x < 0.0 else "R")
		var box := BoxMesh.new()
		box.size = BROW_SIZE
		brow.mesh = box
		brow.material_override = mats[0]
		brow.position = Vector3(x, BROW_Y, BROW_Z)
		# Rotating about Z lifts the +X end, so flip the sign per side to drop the
		# OUTER end of each brow rather than tilting both the same way.
		brow.rotation_degrees = Vector3(0.0, 0.0, BROW_TILT_DEG * (1.0 if x < 0.0 else -1.0))
		socket.add_child(brow)


func _apply_outfit_trim() -> void:
	## Belt, chest strap and shoulder caps on the torso bone.
	if not show_outfit_trim:
		return
	var socket := _bone_socket("TrimSocket", "torso")
	if socket == null:
		return

	var leather := StandardMaterial3D.new()
	leather.albedo_color = trim_color_leather
	leather.roughness = 0.85
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = trim_color_cloth
	cloth.roughness = 0.9
	## Darker leather for the pouch, so it separates from the belt it hangs off rather
	## than merging into one brown mass.
	var dark := StandardMaterial3D.new()
	dark.albedo_color = trim_color_leather.darkened(0.45)
	dark.roughness = 0.9

	var belt := MeshInstance3D.new()
	belt.name = "Belt"
	var cyl := CylinderMesh.new()
	cyl.height = BELT_HEIGHT
	cyl.top_radius = BELT_RADIUS
	cyl.bottom_radius = BELT_RADIUS
	cyl.radial_segments = 12
	belt.mesh = cyl
	belt.material_override = leather
	belt.position = Vector3(0.0, BELT_Y, 0.003)
	socket.add_child(belt)

	var strap := MeshInstance3D.new()
	strap.name = "ChestStrap"
	var sbox := BoxMesh.new()
	sbox.size = STRAP_SIZE
	strap.mesh = sbox
	strap.material_override = cloth
	strap.position = STRAP_POS
	strap.rotation_degrees = Vector3(0.0, 0.0, STRAP_TILT_DEG)
	socket.add_child(strap)

	for x in [-SHOULDER_X, SHOULDER_X]:
		var cap := MeshInstance3D.new()
		cap.name = "Shoulder" + ("L" if x < 0.0 else "R")
		var cbox := BoxMesh.new()
		cbox.size = SHOULDER_SIZE
		cap.mesh = cbox
		cap.material_override = cloth
		cap.position = Vector3(x, SHOULDER_Y, 0.003)
		socket.add_child(cap)

	var pouch := MeshInstance3D.new()
	pouch.name = "BeltPouch"
	var pbox := BoxMesh.new()
	pbox.size = POUCH_SIZE
	pouch.mesh = pbox
	pouch.material_override = dark
	pouch.position = POUCH_POS
	socket.add_child(pouch)

	# Bracers ride their own arm bones so they follow the arms, not the torso.
	for side in [["arm-left", 1.0], ["arm-right", -1.0]]:
		var bone: String = side[0]
		var mirror: float = side[1]
		var arm_socket := _bone_socket("Bracer" + ("L" if mirror > 0.0 else "R"), bone)
		if arm_socket == null:
			continue
		var bracer := MeshInstance3D.new()
		bracer.name = "Bracer"
		var bbox := BoxMesh.new()
		bbox.size = BRACER_SIZE
		bracer.mesh = bbox
		bracer.material_override = leather
		bracer.position = Vector3(BRACER_X * mirror, 0.0, BRACER_Z)
		arm_socket.add_child(bracer)


func _apply_quiver() -> void:
	## Instantiates the shared quiver scene rather than rebuilding one, so the equipped
	## quiver and the ground pickup are literally the same asset.
	if not show_quiver:
		return
	var socket := _bone_socket("QuiverSocket", "torso")
	if socket == null:
		return
	var scene: PackedScene = load(QUIVER_SCENE)
	if scene == null:
		return
	var quiver := scene.instantiate() as Node3D
	quiver.name = "Quiver"
	quiver.position = QUIVER_POS
	quiver.rotation_degrees = QUIVER_ROT
	quiver.scale = Vector3.ONE * QUIVER_SCALE
	socket.add_child(quiver)
