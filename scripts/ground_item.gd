extends MeshInstance3D
## A visible item on the ground that can be picked up

@export var item_resource: ItemResource

func _ready() -> void:
	add_to_group("pickups")
	_apply_visual()


func _apply_visual() -> void:
	if not item_resource:
		return

	var model_path := _get_item_model_path()
	if model_path != "":
		mesh = null
		var res = load(model_path)
		if res:
			var model_node = null
			if res is PackedScene:
				model_node = res.instantiate()
			elif res is Mesh:
				var mi := MeshInstance3D.new()
				mi.mesh = res
				model_node = mi
			if model_node and model_node is Node3D:
				_center_mesh_on_origin(model_node)
				model_node.rotation_degrees = _get_item_model_rotation()
				model_node.scale = _get_item_model_scale()
				add_child(model_node)
	else:
		match item_resource.item_type:
			ItemResource.ItemType.WEAPON:
				_set_color(Color(0.82, 0.65, 0.18, 1))  ## gold for weapons
				_set_size(Vector3(0.35, 0.08, 0.2))
			ItemResource.ItemType.THROWABLE:
				_set_color(Color(0.75, 0.55, 0.15, 1))  ## darker gold
				_set_size(Vector3(0.3, 0.08, 0.15))
			ItemResource.ItemType.SHIELD:
				_set_color(Color(0.6, 0.7, 0.8, 1))  ## silver-blue for shields
				_set_size(Vector3(0.3, 0.12, 0.3))
			ItemResource.ItemType.AMMO:
				_set_color(Color(0.3, 0.5, 0.85, 1))  ## blue for ammo
				_set_size(Vector3(0.15, 0.15, 0.15))
			ItemResource.ItemType.CONSUMABLE:
				_set_color(Color(0.85, 0.2, 0.2, 1))  ## red for consumables
				_set_size(Vector3(0.18, 0.18, 0.18))
			ItemResource.ItemType.ARMOR:
				_set_color(Color(0.4, 0.6, 0.4, 1))  ## green for armor
				_set_size(Vector3(0.35, 0.12, 0.25))

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


func _get_item_model_path() -> String:
	match item_resource.item_name:
		"Longbow":
			return "res://assets/weapons/bow.fbx"
		"Dagger", "Warhammer":
			return "res://assets/models/kenney/mini-arena/weapon-sword.glb"
		"Wooden Shield":
			return "res://assets/weapons/Shield_1.obj"
	return ""


func _center_mesh_on_origin(n: Node3D) -> void:
	var meshes: Array = []
	_collect_meshes(n, meshes)
	if meshes.is_empty():
		return
	var aabb := AABB()
	var first := true
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh:
			var maabb: AABB = mi.transform * mi.mesh.get_aabb()
			aabb = maabb if first else aabb.merge(maabb)
			first = false
	if first:
		return
	var offset := aabb.get_center()
	for m in meshes:
		(m as MeshInstance3D).position -= offset


func _collect_meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)


func _get_item_model_rotation() -> Vector3:
	match item_resource.item_name:
		"Longbow":
			return Vector3(0, 180, 0)  # same orientation as equipped
		_:
			return Vector3(-90, 0, 0)   # lay flat for sword/shield


func _get_item_model_scale() -> Vector3:
	match item_resource.item_name:
		"Longbow":
			return Vector3(0.6, 0.6, 0.6)
		"Dagger":
			return Vector3(0.7, 0.7, 0.7)
		"Warhammer":
			return Vector3(0.9, 0.9, 0.9)
		"Wooden Shield":
			return Vector3(0.4, 0.4, 0.4)
	return Vector3(1.0, 1.0, 1.0)
