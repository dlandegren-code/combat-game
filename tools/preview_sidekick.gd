extends Node3D
## Dev tool: a catalogue of the Sidekick outfits there are, to choose what each item wears.
## Play tools/preview_sidekick.tscn. Writes .summer/local/sidekick_catalogue.png and keeps
## running (everyone idles).
##
## Row 1: the bare body, then every full outfit set (knights 01-06 and the starter knight, 17).
## Row 2: the single pieces — helmets 07-13 and capes/back pieces 14-15 — each on a bare body.

const SidekickBody := preload("res://scripts/sidekick_body.gd")
const SETS := ["", "SK_FANT_KNGT_01", "SK_FANT_KNGT_02", "SK_FANT_KNGT_03", "SK_FANT_KNGT_04",
	"SK_FANT_KNGT_05", "SK_FANT_KNGT_06", "SK_FANT_KNGT_17"]
const PIECES := ["SK_FANT_KNGT_07", "SK_FANT_KNGT_08", "SK_FANT_KNGT_09", "SK_FANT_KNGT_10",
	"SK_FANT_KNGT_11", "SK_FANT_KNGT_12", "SK_FANT_KNGT_13", "SK_FANT_KNGT_14", "SK_FANT_KNGT_15"]
const DX := 0.62
const SHOT := "res://.summer/local/sidekick_catalogue.png"


func _ready() -> void:
	_stage()
	_row(SETS, 0.0, true)
	_row(PIECES, -1.6, false)
	await get_tree().create_timer(0.8).timeout
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.summer/local"))
	get_viewport().get_texture().get_image().save_png(SHOT)
	print("[SidekickCatalogue] screenshot written")


func _row(sets: Array, z: float, whole: bool) -> void:
	var x0 := -DX * (sets.size() - 1) / 2.0
	for i in range(sets.size()):
		var body := SidekickBody.new()
		var prefix: String = sets[i]
		if prefix != "":
			var parts := SidekickBody.parts_of_set(prefix)
			if not whole:
				# A helmet or a cape on its own, not the hair that came with it.
				var keep := PackedStringArray()
				for p in parts:
					if SidekickBody.slot_of(p) in ["22AHED", "23AFAC", "24ABAC"]:
						keep.append(p)
				parts = keep
			body.outfit = parts
		body.position = Vector3(x0 + i * DX, 0, z)
		add_child(body)
		body.play("idle")
		var label := Label3D.new()
		label.text = prefix.replace("SK_FANT_KNGT_", "Knight ") if prefix != "" else "Bare"
		label.font_size = 24
		label.pixel_size = 0.0035
		label.outline_size = 8
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = body.position + Vector3(0, 1.0, 0)
		add_child(label)


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
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 8)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.29, 0.27)
	floor_mesh.material_override = fm
	add_child(floor_mesh)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.25, 3.3)
	cam.rotation_degrees = Vector3(-14, 0, 0)
	cam.fov = 55
	add_child(cam)
	cam.make_current()
