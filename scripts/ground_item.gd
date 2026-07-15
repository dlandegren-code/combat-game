extends MeshInstance3D
## A visible item on the ground that can be picked up

@export var item_resource: ItemResource

## Enlarge dropped loot to sit right next to the scaled-up characters.
const GROUND_SCALE := 1.6

func _ready() -> void:
	add_to_group("pickups")
	_apply_visual()


func _apply_visual() -> void:
	if not item_resource:
		return

	if item_resource.has_model():
		# Data-driven: the item builds its own model (material + scale handled there).
		mesh = null
		var node := item_resource.instantiate_model()
		if node:
			node.scale *= GROUND_SCALE
			node.rotation_degrees = item_resource.model_ground_rotation
			add_child(node)
			_rest_on_ground(node)
	else:
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
					model_node.scale = _get_item_model_scale() * GROUND_SCALE
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


# --- Legacy name-based lookup (fallback for items without a model_path) ---

func _get_item_model_path() -> String:
	match item_resource.item_name:
		"Longbow":
			return "res://assets/weapons/bow.fbx"
		"Dagger":
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


func _rest_on_ground(model_node: Node3D) -> void:
	## Lift the model so its lowest point sits at the ground item's spawn height,
	## instead of being centered (which buries the bottom half of standing items).
	## Must run after the node is in the tree so global transforms are up to date.
	var meshes: Array = []
	_collect_meshes(model_node, meshes)
	var aabb := AABB()
	var first := true
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh:
			var box: AABB = mi.global_transform * mi.mesh.get_aabb()  # world space
			aabb = box if first else aabb.merge(box)
			first = false
	if first:
		return
	# aabb.position.y is the model's lowest world point; raise it to our spawn y.
	model_node.position.y += global_position.y - aabb.position.y


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
		"Wooden Shield":
			return Vector3(0.4, 0.4, 0.4)
	return Vector3(1.0, 1.0, 1.0)
