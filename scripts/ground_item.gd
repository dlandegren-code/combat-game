extends MeshInstance3D
## A visible item on the ground that can be picked up

@export var item_resource: ItemResource

## Enlarge dropped loot to sit right next to the scaled-up characters.
const GROUND_SCALE := 1.6

## World-space Y that pickups rest at — the arena floor sits just below this, and
## _rest_on_ground() settles each model's lowest point here.
##
## Always an ABSOLUTE height: never derive a drop position from a combatant's
## `position`. Combatant origins sit at Combatant._ground_y() (1.11), high above
## the floor because their CharacterModel is offset downwards to meet it, so
## offsetting from one leaves the item floating about a metre up.
const DROP_Y := 0.2

## Arrow graphic used to render an ammo bundle (one arrow per unit of ammo).
const ARROW_MESH := "res://Assets/PolygonDungeon/Models/SM_Arrow_01.res"
const SYNTY_MAT := "res://Assets/PolygonDungeon/Materials/Dungeon_Material_01_mat.tres"

## Guards against building the visual twice. Both spawners (CombatManager._spawn_gi and
## Player._spawn_ground_item) call _apply_visual deferred *and* _ready calls it, which
## used to leave every pickup carrying two overlapping copies of its model.
var _visual_built := false

func _ready() -> void:
	add_to_group("pickups")
	_apply_visual()


func _apply_visual() -> void:
	if not item_resource or _visual_built:
		return
	_visual_built = true

	if item_resource.has_model():
		# Data-driven: the item builds its own model (material + scale handled there).
		mesh = null
		var node := item_resource.instantiate_model()
		if node:
			node.scale *= GROUND_SCALE
			node.rotation_degrees = item_resource.model_ground_rotation
			add_child(node)
			_rest_on_ground(node)
	elif item_resource.item_type == ItemResource.ItemType.AMMO and item_resource.ammo_amount > 0:
		# Show one arrow graphic per unit of ammo, as a loose bundle. It stays a single
		# pickup: one ground_item node carrying one item_resource.
		mesh = null
		_build_arrow_bundle(item_resource.ammo_amount)
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
					# Synty .res meshes ship without a resolved material; assign the shared
					# atlas or they render untextured white.
					if _weapon_kind() in ["axe", "hammer"]:
						var atlas: Material = load(SYNTY_MAT)
						if atlas:
							var synty_meshes: Array = []
							_collect_meshes(model_node, synty_meshes)
							for m in synty_meshes:
								(m as MeshInstance3D).material_override = atlas
					_center_mesh_on_origin(model_node)
					model_node.rotation_degrees = _get_item_model_rotation()
					model_node.scale = _get_item_model_scale() * GROUND_SCALE
					add_child(model_node)
					# Centering alone lets a long model (the cleaver) hang below the
					# floor, so settle it on the ground like the data-driven path does.
					_rest_on_ground(model_node)
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


func _build_arrow_bundle(count: int) -> void:
	## Lay `count` arrow meshes flat on the ground, fanned into a loose bundle.
	var arrow_mesh: Mesh = load(ARROW_MESH)
	if arrow_mesh == null:
		return
	var mat: Material = load(SYNTY_MAT)
	var n: int = clampi(count, 1, 20)
	for i in range(n):
		var a := MeshInstance3D.new()
		a.mesh = arrow_mesh
		if mat:
			a.material_override = mat
		# Random position + heading (kept within the grid cell) so it reads as a spilled
		# pile rather than a neat row. Small per-arrow y stagger avoids z-fighting.
		a.rotation_degrees = Vector3(0, randf_range(0.0, 360.0), 0)
		a.position = Vector3(randf_range(-0.55, 0.55), 0.02 + 0.01 * i, randf_range(-0.55, 0.55))
		a.scale = Vector3.ONE * (GROUND_SCALE * 0.7)
		add_child(a)


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
#
# Matched by SUBSTRING, not exact name. The old exact-name table only knew
# "Longbow", "Dagger" and "Wooden Shield", so every other weapon ("Rusty Sword",
# "Short Bow", "Ranger Dagger", "Goblin Dagger", "Boss Cleaver") fell through to
# the coloured placeholder box. These are the same name heuristics
# Combatant._refresh_socket uses for the equipped visual, so a dropped weapon and
# a held one resolve to the same model.

func _weapon_kind() -> String:
	## "bow" | "hammer" | "axe" | "shield" | "blade" | "" (no model known)
	if item_resource.item_type == ItemResource.ItemType.SHIELD or item_resource.is_shield:
		return "shield"
	if item_resource.item_type != ItemResource.ItemType.WEAPON \
			and item_resource.item_type != ItemResource.ItemType.THROWABLE:
		return ""
	var n := item_resource.item_name.to_lower()
	if n.find("bow") >= 0:
		return "bow"
	if n.find("hammer") >= 0:
		return "hammer"
	if n.find("axe") >= 0 or n.find("cleaver") >= 0:
		return "axe"
	# Anything else edged (sword, dagger, ...) shares the one blade model.
	return "blade"


func _get_item_model_path() -> String:
	match _weapon_kind():
		"bow":
			return "res://assets/weapons/bow.fbx"
		"hammer":
			return "res://Assets/PolygonDungeon/Models/SM_Wep_Hammer_Small_01.res"
		"axe":
			return "res://Assets/PolygonDungeon/Models/SM_Wep_Goblin_Axe_Large_01.res"
		"shield":
			return "res://assets/weapons/Shield_1.obj"
		"blade":
			return "res://assets/models/kenney/mini-arena/weapon-sword.glb"
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
	match _weapon_kind():
		"bow":
			return Vector3(0, 180, 0)   # standing, same orientation as equipped
		"axe", "hammer":
			return Vector3(0, 0, 90)    # Synty hafts run along Y; tip them onto their side
	return Vector3(-90, 0, 0)           # lay flat for blade / shield


func _get_item_model_scale() -> Vector3:
	## Multiplies the model's NATIVE size (unlike ItemResource.model_scale, which is
	## a normalized target). Tuned so each dropped weapon reads at roughly its
	## real length without overflowing a 2.0 grid tile — see _weapon_kind().
	var s := 1.0
	match _weapon_kind():
		"bow":
			s = 0.6
		"axe":
			s = 0.5
		"hammer":
			s = 0.7
		"shield":
			s = 0.4
		"blade":
			# One model serves both; a dagger reads as a shortened sword.
			s = 0.7 if item_resource.item_name.to_lower().find("dagger") >= 0 else 1.0
	return Vector3(s, s, s)
