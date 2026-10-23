extends Node3D
## Dev tool: every hand-held item on a Sidekick body, close up, for tuning how it is held
## (ItemResource.worn_model_path / worn_position / worn_rotation). Play tools/preview_held.tscn.
##
## Uses the real Combatant placement code — each figure is a hero.tscn body with a Sidekick model,
## holding the item through Combatant._refresh_socket — so what is tuned here is what the game
## draws. Writes .summer/local/held_front.png and held_side.png, then keeps running.

const HERO_SCENE := preload("res://scenes/characters/hero.tscn")
const SIDEKICK := preload("res://scenes/characters/sidekick_model.tscn")
const ITEMS := [
	"rusty_sword", "dagger", "ranger_dagger", "boss_cleaver", "warhammer", "gemstone_staff",
	"short_bow", "longbow", "wooden_shield", "viking_axe", "dane_axe", "viking_sword", "seax",
	"viking_spear", "round_shield", "painted_shield",
]
const DX := 1.45
## Tuning mode: when non-empty, rows of ONE item each in several candidate worn_rotation values
## (and worn_scale), instead of the line-up of everything. Labels say which is which.
var TUNE: Array = []
const CLOTHES := ["SK_FANT_KNGT_06_10TORS_HU01", "SK_FANT_KNGT_04_17HIPS_HU01",
	"SK_FANT_KNGT_04_18LEGL_HU01", "SK_FANT_KNGT_04_19LEGR_HU01",
	"SK_FANT_KNGT_04_20FOTL_HU01", "SK_FANT_KNGT_04_21FOTR_HU01"]

var _cam: Camera3D


func _ready() -> void:
	_stage()
	var lineup: Array = []
	if TUNE.is_empty():
		for name in ITEMS:
			lineup.append({"item": load("res://resources/items/%s.tres" % name), "label": "", "z": 0.0})
	else:
		for r in range(TUNE.size()):
			for rot in TUNE[r]["rots"]:
				var it: ItemResource = (load("res://resources/items/%s.tres" % TUNE[r]["item"]) as ItemResource).duplicate()
				it.worn_rotation = rot
				it.worn_scale = TUNE[r]["scale"]
				if TUNE[r].has("pos"):
					it.worn_position = TUNE[r]["pos"][lineup.size() % TUNE[r]["rots"].size()]
				lineup.append({"item": it, "label": str(rot), "z": -1.6 * r})
	var per_row: int = ITEMS.size() if TUNE.is_empty() else TUNE[0]["rots"].size()
	var x0 := -DX * (per_row - 1) / 2.0
	for i in range(lineup.size()):
		var item: ItemResource = lineup[i]["item"]
		var hero := HERO_SCENE.instantiate()
		var model := SIDEKICK.instantiate()
		model.name = "CharacterModel"
		model.position = Vector3(0, -1, 0)
		model.set("outfit", CLOTHES)
		hero.add_child(model)
		hero.position = Vector3(x0 + (i % per_row) * DX, 0, lineup[i]["z"])
		var inv := hero.get_node("Inventory")
		inv.set("starting_item_1", item)
		add_child(hero)
		hero.set_process(false)
		hero.set_physics_process(false)
		# Physics drives the idle in the game; with it off, start the idle here or the body T-poses.
		model.play("idle")
		# The game's own name and health readouts would cover the labels this tool is for.
		for c in hero.get_children():
			if c is VisualInstance3D and c.name != "CharacterModel":
				c.visible = false
		hero.set_meta("row", int(round(-lineup[i]["z"] / 1.6)))
		var label := Label3D.new()
		label.text = item.item_name + ("\n" + lineup[i]["label"] if lineup[i]["label"] != "" else "")
		label.font_size = 26
		label.pixel_size = 0.004
		label.outline_size = 8
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(hero.position.x, 1.9, hero.position.z)
		add_child(label)
	await get_tree().create_timer(0.6).timeout
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.summer/local"))
	if TUNE.is_empty():
		get_viewport().get_texture().get_image().save_png("res://.summer/local/held_front.png")
		_cam.position = Vector3(6.5, 1.4, 2.2)
		_cam.look_at(Vector3(0, 0.9, 0), Vector3.UP)
		await get_tree().create_timer(0.3).timeout
		get_viewport().get_texture().get_image().save_png("res://.summer/local/held_side.png")
	else:
		# One shot per row, from a three-quarter front so a flat thing shows which way it faces.
		for r in range(TUNE.size()):
			for c in get_children():
				if c.has_meta("row"):
					c.visible = int(c.get_meta("row")) == r
			for c in get_children():
				if c is Label3D:
					c.visible = absf(c.position.z + 1.6 * r) < 0.1
			_cam.position = Vector3(1.6, 1.3, -1.6 * r + 3.9)
			_cam.look_at(Vector3(0, 0.75, -1.6 * r), Vector3.UP)
			await get_tree().create_timer(0.3).timeout
			get_viewport().get_texture().get_image().save_png("res://.summer/local/held_tune_%d.png" % r)
	print("[PreviewHeld] screenshots written")


func _stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 20, 0)
	sun.light_energy = 1.2
	add_child(sun)
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 1.1, 5.8)
	_cam.rotation_degrees = Vector3(-4, 0, 0)
	_cam.fov = 55
	add_child(_cam)
	_cam.make_current()
