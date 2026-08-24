extends Control
class_name PortraitSlot
## One party portrait: a live 3D bust of a combatant inside an ornate plate,
## with the character name and an HP bar underneath.
##
## The bust is a *copy* of the combatant's CharacterModel rendered in a private
## SubViewport world (own light, flat backdrop) rather than a camera pointed at
## the real character in the battlefield — that keeps the dungeon out of the
## frame and the lighting consistent regardless of where the fight moves to.
## The copy's AnimationPlayer is re-synced whenever the source changes clip, so
## the portrait still reacts when its owner attacks, gets hit or goes down.

const UiScaleScript := preload("res://scripts/ui_scale.gd")

## Authored sizes, at UiScale.REFERENCE_HEIGHT. Everything actually drawn uses the scaled
## values below (_px, _bar_h, ...), computed once in setup() — a portrait owns a SubViewport
## rendering a live 3D bust, so unlike the flat panels it is far too heavy to tear down and
## rebuild on every window resize. The plate is sized for the window it was created in.
const PORTRAIT_SIZE_BASE := Vector2i(112, 112)
const BAR_HEIGHT_BASE := 20
const LABEL_HEIGHT_BASE := 17
const HP_FONT_SIZE_BASE := 15
const NAME_FONT_SIZE_BASE := 15

## Allies and enemies get visually distinct plates. They differ in silhouette
## (square vs cut-corner octagon) as well as hue, so they stay tellable apart
## without relying on colour vision.
enum Style { ALLY, ENEMY }

## Per-style plate. `inset` is how far the border intrudes on each side, measured
## off each sprite's alpha channel — the render is inset by that much so it sits
## inside the opening rather than underneath the border. `tint` multiplies the
## sprite, so it only works cleanly on a neutral-coloured frame (Box23 is silver).
const FRAME_STYLES := {
	Style.ALLY: {
		"texture": "res://assets/UI/SPR_FantasyWarrior_Frame_Box22_Variant01.png",
		"inset": 0.105,
		"tint": Color(1.0, 1.0, 1.0),
	},
	Style.ENEMY: {
		"texture": "res://assets/UI/SPR_FantasyWarrior_Frame_Box23.png",
		"inset": 0.122,
		"tint": Color(0.85, 0.32, 0.28),
	},
}

## Fraction of max hp at or below which the bar turns red (matches the pack's
## red HP plate variant on sheet 03).
const LOW_HP_FRACTION := 0.35

const COLOR_HP_OK := Color(0.36, 0.72, 0.35)
const COLOR_HP_LOW := Color(0.78, 0.22, 0.20)
const COLOR_HP_EMPTY := Color(0.18, 0.18, 0.20)
const COLOR_BACKDROP := Color(0.078, 0.161, 0.220)   # the pack's dark teal
const COLOR_DEAD_TINT := Color(0.35, 0.35, 0.40)
const COLOR_ACTIVE_TINT := Color(1.45, 1.35, 1.05)

const BAR_UNDER_TEX := "res://assets/UI/SPR_FantasyWarrior_Bar_Horizontal03_Mask.png"
const BAR_FILL_TEX := "res://assets/UI/SPR_FantasyWarrior_Bar_Horizontal05.png"

## Sockets whose contents are ignored when measuring the model. A held sword or
## a shield raised above the head would otherwise inflate the bounding box and
## push the crop off the character's face.
const MEASURE_EXCLUDE: Array[String] = ["WeaponSocket", "ShieldSocket"]

## Rig bone the framing is measured from — mid-torso on these models, see
## _frame_bust(). Present on all of them as lowercase "head".
const BUST_BONE := "head"

## Camera framing, derived from the model's own rig and bounding box so it works
## across the soldier / orc / goblin models without per-model tuning.
## Height of the crop in bone heights (see BUST_BONE); larger zooms out.
@export_range(0.6, 4.0) var bust_zoom: float = 1.95
## Height of the framing centre, also in bone heights. Tuned so the face lands on
## the middle of the plate rather than sagging into the lower half.
@export_range(0.5, 3.0) var face_height: float = 1.45
## Camera elevation above the subject; positive looks slightly down at them.
@export var cam_elevation_degrees: float = 3.0
@export var cam_fov: float = 32.0
## Yaw so the bust is turned slightly rather than staring straight ahead.
@export var model_yaw_degrees: float = 22.0

var combatant: Node = null

## Scaled sizes, filled in by setup() before anything is built.
var _s := 1.0
var _px := PORTRAIT_SIZE_BASE
var _bar_h := BAR_HEIGHT_BASE
var _label_h := LABEL_HEIGHT_BASE

var _viewport: SubViewport
var _stage: Node3D
var _model: Node3D
var _camera: Camera3D
var _frame: TextureRect
var _hp_bar: TextureProgressBar
var _hp_text: Label
var _name_label: Label
var _active_glow: Panel

var _src_anim: AnimationPlayer = null
var _dst_anim: AnimationPlayer = null
var _last_anim := ""

var _glow_style: StyleBoxFlat = null
var _is_active := false
## Resolved entry from FRAME_STYLES, set in setup().
var _style: Dictionary = FRAME_STYLES[Style.ALLY]


func setup(who: Node, style: Style = Style.ALLY) -> void:
	## Build the slot for `who`. Call once, right after adding to the tree.
	combatant = who
	_style = FRAME_STYLES[style]

	_s = UiScaleScript.of(get_viewport())
	_px = Vector2i(roundi(PORTRAIT_SIZE_BASE.x * _s), roundi(PORTRAIT_SIZE_BASE.y * _s))
	_bar_h = roundi(BAR_HEIGHT_BASE * _s)
	_label_h = roundi(LABEL_HEIGHT_BASE * _s)

	custom_minimum_size = Vector2(_px.x, _px.y + _bar_h + _label_h)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_active_glow()
	_build_viewport()
	_build_frame()
	_build_bars()

	_spawn_bust()

	if combatant.has_signal("health_changed"):
		combatant.health_changed.connect(_on_health_changed)
	_refresh_hp()


func _build_active_glow() -> void:
	## Sits behind the portrait and lights up on this combatant's turn.
	_active_glow = Panel.new()
	_active_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_active_glow.position = Vector2(-6.0 * _s, -6.0 * _s)
	_active_glow.size = Vector2(_px.x + 12.0 * _s, _px.y + 12.0 * _s)
	_glow_style = StyleBoxFlat.new()
	_glow_style.bg_color = Color(1.0, 0.84, 0.42, 0.0)
	_glow_style.set_corner_radius_all(8)
	_active_glow.add_theme_stylebox_override("panel", _glow_style)
	add_child(_active_glow)


func _build_viewport() -> void:
	var inset := int(round(_px.x * float(_style["inset"])))
	var inner := Vector2i(_px.x - inset * 2, _px.y - inset * 2)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.position = Vector2(inset, inset)
	container.size = Vector2(inner)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.size = inner
	# Private world so the battlefield (and its lighting) stays out of the shot.
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_viewport)

	_stage = Node3D.new()
	_viewport.add_child(_stage)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = COLOR_BACKDROP
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.75)
	env.ambient_light_energy = 0.9
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_stage.add_child(world_env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-28, 145, 0)
	key.light_energy = 1.5
	_stage.add_child(key)

	_camera = Camera3D.new()
	_camera.fov = cam_fov
	_camera.near = 0.01
	_camera.current = true
	_stage.add_child(_camera)


func _build_frame() -> void:
	_frame = TextureRect.new()
	_frame.texture = load(_style["texture"])
	# Without IGNORE_SIZE the source texture (512²) becomes the node's minimum
	# size and the explicit size below is clamped straight back up to it.
	_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_frame.size = Vector2(_px)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)


func _build_bars() -> void:
	# TextureProgressBar's minimum size is its texture size (256x64 here) and
	# can't be overridden, so the bar is built at native size and scaled down to
	# the slot width instead of resized.
	const BAR_NATIVE := Vector2(256, 64)
	_hp_bar = TextureProgressBar.new()
	_hp_bar.texture_under = load(BAR_UNDER_TEX)
	_hp_bar.texture_progress = load(BAR_FILL_TEX)
	_hp_bar.tint_under = COLOR_HP_EMPTY
	_hp_bar.tint_progress = COLOR_HP_OK
	_hp_bar.size = BAR_NATIVE
	_hp_bar.scale = Vector2(_px.x / BAR_NATIVE.x, _bar_h / BAR_NATIVE.y)
	_hp_bar.position = Vector2(0, _px.y)
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hp_bar)

	# "12/20" centred on the bar.
	_hp_text = Label.new()
	_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_text.add_theme_font_size_override("font_size", roundi(HP_FONT_SIZE_BASE * _s))
	_hp_text.add_theme_color_override("font_color", Color(1, 1, 1))
	_hp_text.add_theme_constant_override("outline_size", 3)
	_hp_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	# Positioned against the bar's on-screen footprint, not its unscaled size.
	_hp_text.position = Vector2(0, _px.y)
	_hp_text.size = Vector2(_px.x, _bar_h)
	_hp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hp_text)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", roundi(NAME_FONT_SIZE_BASE * _s))
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.87, 0.60))
	_name_label.add_theme_constant_override("outline_size", 3)
	_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_name_label.position = Vector2(0, _px.y + _bar_h)
	_name_label.size = Vector2(_px.x, _label_h)
	_name_label.text = str(combatant.character_name)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)


func _spawn_bust() -> void:
	## Clone the combatant's visual model into our private world.
	var src := combatant.get_node_or_null("CharacterModel") as Node3D
	if not src:
		push_warning("PortraitSlot: %s has no CharacterModel; portrait will be empty."
			% combatant.name)
		return

	_model = src.duplicate() as Node3D
	_stage.add_child(_model)
	_model.position = Vector3.ZERO
	_model.rotation_degrees = Vector3(0, model_yaw_degrees, 0)
	# Scale is left as duplicated — Combatant applies CHARACTER_SCALE to the live
	# model, and the portrait should match the proportions on the battlefield.

	_src_anim = src.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_dst_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer

	_frame_bust()


func _frame_bust() -> void:
	## Both the zoom and the framing height are expressed in multiples of the rig's
	## `head` bone height — the bone sits at mid-torso, so its height above the
	## feet is a clean measure of body size.
	##
	## Deliberately NOT measured against the crown of the head: headgear varies
	## wildly (the Hero's helmet crest adds ~15% to his silhouette, the Archer is
	## bare-headed), so a crown-relative crop zooms each character differently and
	## the same character would rescale on equipping a helmet.
	var box := _visual_bounds(_model)
	if box.size.y <= 0.0:
		push_warning("PortraitSlot: could not measure %s; using an untargeted camera."
			% combatant.name)
		return

	var centre := box.get_center()
	# Fallback for a model with no usable rig: the bone sits at roughly this
	# share of total height on the rigs we do have.
	var bone_height: float = box.size.y * 0.42
	var aim_x: float = centre.x
	var aim_z: float = centre.z

	var skel := _model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel:
		var bone := skel.find_bone(BUST_BONE)
		if bone >= 0:
			var pose: Vector3 = skel.global_transform * skel.get_bone_global_pose(bone).origin
			bone_height = maxf(0.05, pose.y)
			# Centre on the torso rather than the bounding box, whose x is skewed
			# by outstretched arms.
			aim_x = pose.x
			aim_z = pose.z

	var covered: float = bone_height * bust_zoom
	var focus := Vector3(aim_x, bone_height * face_height, aim_z)
	var distance: float = (covered * 0.5) / tan(deg_to_rad(cam_fov) * 0.5)

	# Orbit the camera to the requested elevation and look back at the focus, so
	# the subject stays dead-centre. Tilting *after* look_at instead would slide
	# the framing by distance * tan(elevation) and eat into the space above the head.
	var elevation := deg_to_rad(cam_elevation_degrees)
	var offset := Vector3(0.0, sin(elevation), cos(elevation)) * distance

	_camera.fov = cam_fov
	_camera.position = focus + offset
	_camera.look_at(focus, Vector3.UP)


func _visual_bounds(root: Node) -> AABB:
	## Union of every VisualInstance3D AABB under `root`, in stage space, skipping
	## the equipment sockets listed in MEASURE_EXCLUDE.
	var out := AABB()
	var found := false
	for node in _measurable(root):
		var vi := node as VisualInstance3D
		if not vi:
			continue
		var world := vi.global_transform * vi.get_aabb()
		out = world if not found else out.merge(world)
		found = true
	return out


func _measurable(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in root.get_children():
		if child.name in MEASURE_EXCLUDE:
			continue  # prune the whole subtree, gear included
		out.append(child)
		out.append_array(_measurable(child))
	return out


func _process(_delta: float) -> void:
	_sync_animation()


func _sync_animation() -> void:
	## Re-play the source's current clip on the copy when it changes. We don't
	## seek every frame — that stutters the copy and the two drifting slightly
	## out of phase is not noticeable at portrait size.
	if not _src_anim or not _dst_anim:
		return
	var current := _src_anim.current_animation
	if current == _last_anim:
		return
	_last_anim = current
	if current != "" and _dst_anim.has_animation(current):
		_dst_anim.play(current)


func _on_health_changed(_hp: int, _max_hp: int, _is_alive: bool) -> void:
	_refresh_hp()


func _refresh_hp() -> void:
	if not is_instance_valid(combatant):
		return
	var hp: int = combatant.hp
	var max_hp: int = maxi(1, combatant.max_hp)
	_hp_bar.max_value = max_hp
	_hp_bar.value = clampi(hp, 0, max_hp)
	_hp_text.text = "%d/%d" % [maxi(0, hp), max_hp]

	var fraction := float(hp) / float(max_hp)
	_hp_bar.tint_progress = COLOR_HP_LOW if fraction <= LOW_HP_FRACTION else COLOR_HP_OK

	if not combatant.is_alive:
		_hp_bar.tint_progress = COLOR_HP_EMPTY
	_apply_frame_tint()


func set_active(active: bool) -> void:
	## Highlight this slot while it's the combatant's turn.
	_is_active = active
	_apply_frame_tint()


func _apply_frame_tint() -> void:
	## Death wins over the active highlight — a downed combatant never lights up.
	var dead: bool = is_instance_valid(combatant) and not combatant.is_alive
	if dead:
		_frame.modulate = COLOR_DEAD_TINT
		_name_label.modulate = COLOR_DEAD_TINT
		_glow_style.bg_color.a = 0.0
		return
	# Brightening the plate reads far better at this size than the ring alone,
	# which is nearly invisible against gold. Multiplied onto the style's own
	# tint so an enemy plate brightens to a hot red rather than turning gold.
	var base: Color = _style["tint"]
	_frame.modulate = base * COLOR_ACTIVE_TINT if _is_active else base
	_name_label.modulate = Color.WHITE
	_glow_style.bg_color.a = 0.5 if _is_active else 0.0
