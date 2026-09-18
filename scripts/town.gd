extends Node3D
## The town: a clearing in a birch wood, and the hub the whole game loop turns on.
##
## A BACKDROP, not a level. The camera never moves, nothing in the 3D scene can be clicked,
## and nobody walks anywhere — the player's decisions are all buttons, and the clearing exists
## to make those buttons feel like somewhere. That is what keeps it cheap: a walkable town
## would want collision, navigation, a character controller and a camera rig, for exactly the
## same four choices.
##
## Everything is built in code from town_layout.gd rather than authored in the .tscn, because
## the roster is meant to VARY — not every service open every visit, and Phase 4's quest board
## adding its own — and a scene file cannot say "one of these three, today".
##
## The buttons float over the buildings they belong to: each service's `sign_at` is a point in
## world space, projected through the camera onto the screen. They are ordinary Buttons in a
## CanvasLayer, so they behave like buttons; only where they sit is 3D.

const ScreenPanelScript := preload("res://scripts/screen_panel.gd")
const CharacterDataScript := preload("res://scripts/character_data.gd")
const CharacterClassesScript := preload("res://scripts/character_classes.gd")
const SaveGameScript := preload("res://scripts/save_game.gd")
const ProgressionScript := preload("res://scripts/progression.gd")
const CombatantScript := preload("res://scripts/combatant.gd")
const TownLayoutScript := preload("res://scripts/town_layout.gd")
const SyntyModelScript := preload("res://scripts/synty_model.gd")
const TownAmbienceScript := preload("res://scripts/town_ambience.gd")

const FARM_PREFABS := "res://assets/Synty/PolygonFarm/Prefabs/"

const QUEST_SCENE := "res://scenes/quest_scene.tscn"
const CREATION_SCENE := "res://scenes/character_creation.tscn"
const TITLE_SCENE := "res://scenes/title_screen.tscn"
const TRAINING_SCENE := "res://scenes/training.tscn"
const SHOP_SCENE := "res://scenes/shop.tscn"
const BOARD_SCENE := "res://scenes/quest_board.tscn"
const CAMP_SCENE := "res://scenes/hire_camp.tscn"

var _camera: Camera3D
var _world: Node3D
var _ui: CanvasLayer
var _signs: Array = []            ## [{button, at}] — repositioned when the window resizes
var _save_note := ""


func _ready() -> void:
	# Arriving in town IS the checkpoint — see SaveGame for why this is the only place the game
	# writes. Done first so that a failed save is on screen from the first frame.
	_autosave()
	_build_world()
	_build_clearing()
	_build_services()
	_build_dressing()
	_build_ambience()
	_build_ui()
	get_viewport().size_changed.connect(_position_signs)


# --- The place -------------------------------------------------------------

func _build_world() -> void:
	var env := WorldEnvironment.new()
	env.name = "Weather"
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = TownLayoutScript.SKY_TOP
	sky_mat.sky_horizon_color = TownLayoutScript.SKY_HORIZON
	sky_mat.ground_bottom_color = TownLayoutScript.GROUND_COLOUR
	sky_mat.ground_horizon_color = TownLayoutScript.SKY_HORIZON
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.85
	# Depth fog, gently: it is what puts air between the clearing and the wood behind it, and
	# air is what makes the far trees read as distance rather than as clutter.
	e.fog_enabled = true
	e.fog_light_color = TownLayoutScript.FOG_COLOUR
	# 0.008 put a third of a white veil over the middle of the clearing; this is thin enough
	# to only show up on the far tree line, which is all it was ever for.
	e.fog_density = 0.0015
	e.fog_sky_affect = 0.0
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = TownLayoutScript.SUN_ROTATION
	sun.light_color = TownLayoutScript.SUN_COLOUR
	sun.light_energy = TownLayoutScript.SUN_ENERGY
	sun.shadow_enabled = true
	# A fixed camera sees a fixed depth range, so the shadow distance is pulled in tight and
	# spends its resolution where the buildings actually are. Everything that matters — the
	# village and the near tree line — is inside 45 m; the wood behind it does not cast at all
	# (see _disable_shadow_casting).
	sun.directional_shadow_max_distance = 48.0
	add_child(sun)

	_camera = Camera3D.new()
	_camera.name = "View"
	_camera.position = TownLayoutScript.CAMERA_POSITION
	_camera.fov = TownLayoutScript.CAMERA_FOV
	add_child(_camera)
	_camera.look_at(TownLayoutScript.CAMERA_TARGET, Vector3.UP)

	_world = Node3D.new()
	_world.name = "Clearing"
	add_child(_world)

	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(TownLayoutScript.GROUND_SIZE, TownLayoutScript.GROUND_SIZE)
	ground.mesh = plane
	var soil := StandardMaterial3D.new()
	soil.albedo_color = TownLayoutScript.GROUND_TINT
	soil.roughness = 0.95
	soil.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	ground.material_override = soil
	_world.add_child(ground)


func _build_clearing() -> void:
	## The wood, and the floor of the clearing. Scattered from a FIXED seed: a town that
	## reshuffled its trees on every visit would be unsettling in a way nobody could name.
	var rng := RandomNumberGenerator.new()
	rng.seed = TownLayoutScript.FOREST_SEED

	var big: AABB = TownLayoutScript.KEEP_CLEAR_BIG
	var small: AABB = TownLayoutScript.KEEP_CLEAR_SMALL
	# Where the buildings and props stand, so nothing is planted through them. Read from the
	# layout rather than from the scene, because the wood is grown before they are placed.
	var taken := _occupied_spots()

	for band in TownLayoutScript.FOREST_BANDS:
		_scatter(rng, band["models"], band["count"], band["radius"], band["scale"], big,
			taken, band["lod"], float(band.get("max_z", 1000.0)))
	_scatter(rng, TownLayoutScript.BUSH_MODELS, TownLayoutScript.BUSH_COUNT,
		TownLayoutScript.BUSH_RADIUS, Vector2(0.8, 1.4), big, taken)
	_scatter(rng, TownLayoutScript.ROCK_MODELS, TownLayoutScript.ROCK_COUNT,
		TownLayoutScript.ROCK_RADIUS, Vector2(0.7, 1.6), big, taken)
	_scatter(rng, TownLayoutScript.GRASS_MODELS, TownLayoutScript.GRASS_COUNT,
		TownLayoutScript.GRASS_RADIUS, Vector2(0.7, 1.5), small, taken)
	_scatter(rng, TownLayoutScript.FLOWER_MODELS, TownLayoutScript.FLOWER_COUNT,
		TownLayoutScript.FLOWER_RADIUS, Vector2(0.8, 1.3), small, taken)
	_scatter(rng, TownLayoutScript.COVER_MODELS, TownLayoutScript.COVER_COUNT,
		TownLayoutScript.COVER_RADIUS, Vector2(0.9, 1.6), small, taken)
	_scatter(rng, [TownLayoutScript.HILL_MODEL], TownLayoutScript.HILL_COUNT,
		TownLayoutScript.HILL_RADIUS, TownLayoutScript.HILL_SCALE, big, taken, 0)


func _occupied_spots() -> Array:
	## Every placed object and how much room it needs around it, as [{at, radius}].
	##
	## This is what stopped a birch growing through the windmill: the mill's sails sweep ten
	## metres and a scatter that only avoids a box around the village had no reason to leave
	## them alone.
	var spots: Array = []
	for group in [TownLayoutScript.SERVICES, TownLayoutScript.SCENERY, TownLayoutScript.TOWNSFOLK]:
		for entry in group:
			spots.append({
				"at": entry["position"],
				"radius": float(entry.get("clear", TownLayoutScript.DEFAULT_CLEARANCE)),
			})
	return spots


func _scatter(rng: RandomNumberGenerator, models: Array, count: int, radius: Vector2,
		scale_range: Vector2, keep_clear: AABB, taken: Array, lod: int = 0,
		max_z: float = 1000.0) -> void:
	for i in range(count):
		var model_name: String = models[rng.randi() % models.size()]
		# Rejection sampling: a bush standing in a shopfront is worse than a slightly thinner
		# scatter, and at these counts the rejections cost nothing.
		var at := Vector3.ZERO
		var placed := false
		for attempt in range(16):
			var angle := rng.randf() * TAU
			var distance := rng.randf_range(radius.x, radius.y)
			at = Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
			if at.z > max_z:
				continue   # behind the camera; see FOREST_BANDS
			if keep_clear.has_point(at) or _too_close(at, taken):
				continue
			placed = true
			break
		if not placed:
			continue
		var node := SyntyModelScript.meadow(model_name, lod)
		if node == null:
			continue
		if lod > 0:
			# The distant bands are lit but cast nothing. Every tree in the shadow range is
			# drawn a second time into the shadow map, and a wood eighty metres back throws
			# its shadows onto ground the camera cannot see.
			_disable_shadow_casting(node)
		node.position = at
		node.rotation_degrees = Vector3(0.0, rng.randf() * 360.0, 0.0)
		node.scale = Vector3.ONE * rng.randf_range(scale_range.x, scale_range.y)
		_world.add_child(node)


func _disable_shadow_casting(node: Node) -> void:
	var mesh_node := node as MeshInstance3D
	if mesh_node != null:
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_shadow_casting(child)


func _too_close(at: Vector3, taken: Array) -> bool:
	for spot in taken:
		var gap: Vector3 = at - spot["at"]
		# Horizontal distance only: everything here stands on the same flat ground.
		if Vector2(gap.x, gap.z).length() < float(spot["radius"]):
			return true
	return false


# --- The buildings ---------------------------------------------------------

func _build_services() -> void:
	for entry in TownLayoutScript.SERVICES:
		var node := _place(entry)
		if node != null:
			node.name = "Service_" + String(entry["id"])


func _build_dressing() -> void:
	for entry in TownLayoutScript.SCENERY:
		_place(entry)
	for run in TownLayoutScript.FENCES:
		_build_fence(run[0], run[1])
	for folk in TownLayoutScript.TOWNSFOLK:
		_place_townsfolk(folk)


func _place(entry: Dictionary) -> Node3D:
	var model_name: String = entry["model"]
	var node: Node3D = null
	if model_name.begins_with("farm:"):
		# The farm pack came as a Godot package with its materials already on it, so it needs
		# none of the LOD-pruning and painting that the raw meadow FBX do.
		var packed := load(FARM_PREFABS + _farm_path(model_name.trim_prefix("farm:"))) as PackedScene
		if packed != null:
			node = packed.instantiate() as Node3D
	else:
		node = SyntyModelScript.meadow(model_name)
	if node == null:
		push_warning("Town: could not place %s" % model_name)
		return null
	node.position = entry["position"]
	node.rotation_degrees = Vector3(0.0, float(entry.get("rotation", 0.0)), 0.0)
	node.scale = Vector3.ONE * float(entry.get("scale", 1.0))
	_world.add_child(node)
	return node


func _farm_path(prefab: String) -> String:
	## The farm pack files its prefabs by category, so the category is derived from the name
	## rather than written into every layout entry.
	var folder := "Props"
	if prefab.begins_with("SM_Bld_"):
		folder = "Buildings"
	elif prefab.begins_with("SM_Env_"):
		folder = "Environment"
	elif prefab.begins_with("SM_Chr_"):
		folder = "Characters"
	return "%s/%s.tscn" % [folder, prefab]


func _build_fence(from: Vector3, to: Vector3) -> void:
	var run := to - from
	var span := TownLayoutScript.FENCE_SPAN
	var panels := int(floor(run.length() / span))
	var heading := rad_to_deg(atan2(run.x, run.z)) - 90.0
	for i in range(panels):
		var node := SyntyModelScript.meadow(TownLayoutScript.FENCE_MODEL)
		if node == null:
			return
		node.position = from + run.normalized() * (span * i)
		node.rotation_degrees = Vector3(0.0, heading, 0.0)
		_world.add_child(node)


func _place_townsfolk(folk: Dictionary) -> void:
	var packed := load(String(folk["model"])) as PackedScene
	if packed == null:
		return
	var node := packed.instantiate() as Node3D
	node.position = folk["position"]
	node.rotation_degrees = Vector3(0.0, float(folk.get("rotation", 0.0)), 0.0)
	node.scale = Vector3.ONE * TownLayoutScript.TOWNSFOLK_SCALE
	_world.add_child(node)
	# The game's own hero models, already rigged with the idle the combat scene plays, so a
	# townsperson breathes instead of standing there like a shop dummy.
	var anim := _find_anim_player(node)
	if anim != null and anim.has_animation("idle"):
		anim.play("idle")


func _find_anim_player(node: Node) -> AnimationPlayer:
	var player := node as AnimationPlayer
	if player != null:
		return player
	for child in node.get_children():
		var found := _find_anim_player(child)
		if found != null:
			return found
	return null


func _build_ambience() -> void:
	var ambience := TownAmbienceScript.new()
	ambience.name = "Ambience"
	add_child(ambience)
	ambience.setup(_world)
	# The cabin's chimney, the magician's, then the fire in the middle of the clearing.
	ambience.add_chimney_smoke(Vector3(-12.2, 4.6, -5.4))
	ambience.add_chimney_smoke(Vector3(12.0, 4.4, -9.0), 9)
	ambience.add_campfire(Vector3(3.0, 0.0, 11.0))
	# The mercenaries' fire. Its stones and cook tripod are laid out with the rest of the
	# scenery; this is the flame in them, so the camp reads as occupied from across the
	# clearing rather than as an empty tent.
	ambience.add_campfire(TownLayoutScript.MERC_FIRE)
	ambience.add_falling_leaves(Vector3(0.0, 9.0, -2.0), Vector3(26.0, 4.0, 18.0))
	ambience.add_butterflies(Vector3(0.0, 0.0, 2.0), 14.0)


# --- The buttons -----------------------------------------------------------

func _build_ui() -> void:
	if _ui != null:
		_ui.queue_free()
	_signs.clear()
	_ui = CanvasLayer.new()
	_ui.name = "TownUI"
	add_child(_ui)

	_build_party_panel()
	_build_service_signs()
	_build_system_buttons()
	_position_signs()


func _build_party_panel() -> void:
	var panel := VBoxContainer.new()
	panel.name = "PartyPanel"
	panel.position = Vector2(24, 20)
	panel.add_theme_constant_override("separation", 4)
	_ui.add_child(panel)

	_label(panel, "Riverwatch", ScreenPanelScript.TITLE_SIZE, ScreenPanelScript.TITLE)
	if not GameState.has_party():
		_label(panel, "Nobody here yet.", ScreenPanelScript.HEADING_SIZE, ScreenPanelScript.HEADING)
		var make := Button.new()
		make.text = "Create a character"
		make.pressed.connect(_on_create)
		panel.add_child(make)
		return

	var purse := "%d gold" % GameState.gold
	if _save_note != "":
		purse += "      " + _save_note
	_label(panel, purse, ScreenPanelScript.HEADING_SIZE, ScreenPanelScript.HEADING)
	for member in GameState.party:
		_label(panel, "%s the %s — level %d, %d xp to spend, %s" % [
			member.character_name,
			CharacterClassesScript.display_name(member.class_id),
			member.level,
			member.xp,
			_condition(member),
		], ScreenPanelScript.BODY_SIZE, ScreenPanelScript.BODY)


func _build_service_signs() -> void:
	for entry in TownLayoutScript.SERVICES:
		var button := Button.new()
		button.text = _service_text(entry)
		button.tooltip_text = String(entry.get("note", ""))
		button.pressed.connect(_on_service.bind(entry))
		button.disabled = not _service_enabled(entry)
		_ui.add_child(button)
		_signs.append({"button": button, "at": entry["sign_at"]})


func _position_signs() -> void:
	## Put each button where its building is on screen.
	##
	## Projected in code rather than parented to a Node3D because the camera never moves: one
	## projection when the town is built is enough, and the only thing that can invalidate it
	## is the window being resized.
	if _camera == null:
		return
	var viewport := get_viewport().get_visible_rect().size
	for sign_entry in _signs:
		var button: Button = sign_entry["button"]
		if not is_instance_valid(button):
			continue
		var screen_pos := _camera.unproject_position(sign_entry["at"])
		var size := button.get_minimum_size()
		button.size = size
		# Centred on the point, and kept inside the window, so a building near the edge cannot
		# push its own label off the screen.
		button.position = Vector2(
			clampf(screen_pos.x - size.x * 0.5, 8.0, maxf(8.0, viewport.x - size.x - 8.0)),
			clampf(screen_pos.y - size.y * 0.5, 8.0, maxf(8.0, viewport.y - size.y - 8.0)))


func _build_system_buttons() -> void:
	var column := VBoxContainer.new()
	column.name = "SystemButtons"
	column.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	column.position = Vector2(-24, -24)
	column.add_theme_constant_override("separation", 6)
	_ui.add_child(column)

	var board := Button.new()
	board.text = "Quest Board"
	board.pressed.connect(_on_quest_board)
	column.add_child(board)

	var menu := Button.new()
	menu.text = "Main Menu"
	menu.pressed.connect(_on_title)
	column.add_child(menu)

	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func(): get_tree().quit())
	column.add_child(quit)


func _label(parent: Node, text: String, font_size: int, colour: Color) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", colour)
	# An outline, because this text sits over a bright 3D scene rather than on a dark panel.
	item.add_theme_constant_override("outline_size", 6)
	item.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	parent.add_child(item)
	return item


# --- What the buttons do ---------------------------------------------------

func _service_text(entry: Dictionary) -> String:
	var label: String = entry["label"]
	if String(entry.get("action", "")) == "rest" and _anyone_hurt():
		return "%s — %d gold" % [label, _rest_price()]
	if String(entry.get("action", "")) == "hire" and GameState.has_party():
		# How many are following you, on the sign, because that is the number the camp is
		# there to change and the one thing a player wants to know before walking over.
		return "%s — %d/%d" % [label, GameState.party.size(), GameState.PARTY_MAX]
	return label


func _service_enabled(entry: Dictionary) -> bool:
	if not GameState.has_party():
		return false
	if String(entry.get("action", "")) == "rest":
		return _anyone_hurt() and GameState.gold >= _rest_price()
	return true


func _on_service(entry: Dictionary) -> void:
	match String(entry.get("action", "")):
		"shop":
			get_tree().change_scene_to_file(SHOP_SCENE)
		"training":
			get_tree().change_scene_to_file(TRAINING_SCENE)
		"hire":
			get_tree().change_scene_to_file(CAMP_SCENE)
		"adventure":
			get_tree().change_scene_to_file(QUEST_SCENE)
		"rest":
			_on_rest()
		_:
			ScreenPanelScript.toast(_toast_host(), "%s is not open yet." % entry["label"])


func _on_rest() -> void:
	var price := _rest_price()
	if not GameState.spend_gold(price):
		ScreenPanelScript.toast(_toast_host(), "A bed costs %d gold and the party has %d."
			% [price, GameState.gold])
		return
	GameState.rest_party()
	_autosave()
	_build_ui()
	ScreenPanelScript.toast(_toast_host(), "Rested. Arrows are not included — buy those.")


func _on_quest_board() -> void:
	if not GameState.has_party():
		ScreenPanelScript.toast(_toast_host(), "There is nobody here to take a job.")
		return
	get_tree().change_scene_to_file(BOARD_SCENE)


func _on_create() -> void:
	get_tree().change_scene_to_file(CREATION_SCENE)


func _on_title() -> void:
	get_tree().change_scene_to_file(TITLE_SCENE)


func _toast_host() -> Control:
	## ScreenPanel.toast hangs its message on a Control, and this scene's root is 3D.
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(host)
	return host


# --- Party state -----------------------------------------------------------

func _autosave() -> void:
	if not GameState.has_party():
		return
	if SaveGameScript.save():
		_save_note = "Saved."
	else:
		_save_note = "COULD NOT SAVE — see the console. Your progress is not on disk."


func _condition(member) -> String:
	if member.hp == CharacterDataScript.VITALS_FULL:
		return "unhurt"
	return "wounded (%d hp)" % member.hp


func _anyone_hurt() -> bool:
	for member in GameState.party:
		if member.hp != CharacterDataScript.VITALS_FULL:
			return true
	return false


func _rest_price() -> int:
	var missing := 0
	for member in GameState.party:
		if member.hp != CharacterDataScript.VITALS_FULL:
			missing += maxi(0, _max_hp_of(member) - member.hp)
	return maxi(1, missing * ProgressionScript.REST_GOLD_PER_HP)


func _max_hp_of(member) -> int:
	return maxi(1, int(member.stats.stamina) * CombatantScript.HP_PER_STAMINA)
