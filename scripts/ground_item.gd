extends MeshInstance3D
## A visible item on the ground that can be picked up

var item_resource: ItemResource

func _ready() -> void:
	add_to_group("pickups")
	_apply_visual()


func _apply_visual() -> void:
	if not item_resource:
		return

	match item_resource.item_type:
		ItemResource.ItemType.WEAPON:
			_set_color(Color(0.82, 0.65, 0.18, 1))  ## gold for weapons
			_set_size(Vector3(0.35, 0.08, 0.2))
		ItemResource.ItemType.THROWABLE:
			_set_color(Color(0.75, 0.55, 0.15, 1))  ## darker gold
			_set_size(Vector3(0.3, 0.08, 0.15))
		ItemResource.ItemType.AMMO:
			_set_color(Color(0.3, 0.5, 0.85, 1))  ## blue for ammo
			_set_size(Vector3(0.15, 0.15, 0.15))
		ItemResource.ItemType.CONSUMABLE:
			_set_color(Color(0.85, 0.2, 0.2, 1))  ## red for consumables
			_set_size(Vector3(0.18, 0.18, 0.18))

	# Add a name label floating above
	var label := Label3D.new()
	label.name = "ItemLabel"
	label.text = item_resource.item_name
	label.font_size = 18
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 0.5, 0)
	label.modulate = Color(1, 1, 1, 1)
	add_child(label)

	# Add a simple collision area for pickup detection
	var area := Area3D.new()
	area.name = "PickupArea"
	var col_shape := CollisionShape3D.new()
	col_shape.shape = BoxShape3D.new()
	col_shape.shape.size = Vector3(1.2, 0.5, 1.2)
	area.add_child(col_shape)
	add_child(area)


func _set_color(c: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	material_override = mat
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.08, 0.15)
	mesh = box


func _set_size(s: Vector3) -> void:
	if mesh is BoxMesh:
		mesh.size = s
