extends Node3D
## Dev tool: every Sidekick back attachment (slot 24ABAC) on a plain body, seen from behind, in
## a labelled grid — to find which of them are quivers, capes, bedrolls... Writes
## .summer/local/backs.png and quits.

const SIDEKICK := preload("res://scenes/characters/sidekick_model.tscn")
const CLOTHES := ["SK_FANT_KNGT_06_10TORS_HU01", "SK_FANT_KNGT_04_17HIPS_HU01",
	"SK_FANT_KNGT_04_18LEGL_HU01", "SK_FANT_KNGT_04_19LEGR_HU01",
	"SK_FANT_KNGT_04_20FOTL_HU01", "SK_FANT_KNGT_04_21FOTR_HU01"]
## When non-empty: bodies wearing show_quiver, close up, one per facing listed (degrees of yaw;
## 180 is back to the camera).
@export var only: Array = [180, 135, 90, 0]
const PER_ROW := 6
const DX := 1.1
const DZ := 1.6


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.72)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 160, 0)
	add_child(sun)
	var parts: Array = []
	for dir in ["res://assets/sidekick/outfits/", "res://assets/sidekick/knights/"]:
		for f in DirAccess.get_files_at(dir):
			if f.contains("24ABAC") and f.ends_with(".fbx") and not parts.has(f.get_basename()):
				parts.append(f.get_basename())
	parts.sort()
	if not only.is_empty():
		parts = only.duplicate()
	for i in range(parts.size()):
		var body := SIDEKICK.instantiate()
		if not only.is_empty():
			body.set("outfit", CLOTHES)
			body.set("show_quiver", true)
		else:
			body.set("outfit", CLOTHES + [parts[i]])
		body.position = Vector3((i % PER_ROW) * DX, 0, -(i / PER_ROW) * DZ)
		# Back to the camera.
		body.rotation_degrees = Vector3(0, float(parts[i]) if not only.is_empty() else 180.0, 0)
		add_child(body)
		var label := Label3D.new()
		label.text = str(parts[i]).replace("SK_FANT_KNGT_", "").replace("_24ABAC_HU01", "").replace("T_FantasyKnights_", "").replace("ColorMap.png", "")
		label.font_size = 40
		label.pixel_size = 0.004
		label.outline_size = 8
		label.position = body.position + Vector3(0, 1.0, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)
		body.play("idle")
	var cam := Camera3D.new()
	add_child(cam)
	var rows: int = (parts.size() + PER_ROW - 1) / PER_ROW
	var mid := Vector3((PER_ROW - 1) * DX / 2.0, 0.5, -(rows - 1) * DZ / 2.0)
	cam.position = mid + (Vector3(0.3, 0.5, 2.6) if not only.is_empty() else Vector3(0, 1.6, 4.2))
	cam.look_at(mid, Vector3.UP)
	cam.make_current()
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png("res://.summer/local/backs.png")
	get_tree().quit()
