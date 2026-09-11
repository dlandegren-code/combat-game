extends RefCounted
## Inventory cells that show the actual item, by photographing its 3D model.
##
## The Fantasy Warrior icon set has one picture per CATEGORY — every sword is the same sword —
## which is fine until the bag holds a Rusty Sword and a Ranger Dagger and both read as "some
## blade". So each item's own art (ItemResource.display_model_path, the same model the floor
## and the character's hand use) is rendered once into a small texture and kept.
##
## --- How ---
##
## One SubViewport with its own World3D, reused for every shot: the model goes in, a frame is
## drawn, the result is copied out as an ImageTexture, and the model is thrown away. A viewport
## per item would be hundreds of render targets for a bag of twenty things.
##
## Rendering needs a frame, so this is a coroutine and callers must await it. ItemSlot shows the
## flat category icon immediately and swaps in the photograph when it arrives — nothing ever
## waits on a blank cell, and the swap only happens once because of the cache.

const SIZE := 128
## Breathing room, as a fraction. Barely any: the Synty reference sheets run their weapons
## almost corner to corner, and the whole complaint about the first version was that the items
## looked small in their cells.
const MARGIN := 1.06

## How much longer than it is wide something has to be before it is laid along the DIAGONAL.
##
## A square cell's diagonal is 1.41 times its side, so a sword turned to run corner-to-corner
## can be drawn half again as large as one stood upright. That is exactly what the reference
## sheets do with blades and polearms — and exactly what they do NOT do with shields and
## breastplates, which stay square-on. This is the line between the two.
const ELONGATED := 1.6

## The screen directions the model's own axes are aimed at. The camera looks down -Z, so X is
## across the picture, Y up it, and Z toward the viewer.
const DIAGONAL := Vector3(0.70710678, 0.70710678, 0.0)
const ACROSS_DIAGONAL := Vector3(-0.70710678, 0.70710678, 0.0)

## Squat items get turned away from the camera by this much, elongated ones do not.
##
## A breastplate's thinnest axis is its depth, so aiming that at the viewer shows its flat
## front — and since build_armor_meshes.gd paints each piece one solid colour off the atlas,
## a flat front lit evenly is a rectangle. That is the "it looks like a box". Turning it gives
## the shell a visible edge and lets the two lights fall off across it.
##
## Blades keep the square-on view: their silhouette IS the read, and turning one only makes it
## shorter.
const TURN_YAW := 34.0
const TURN_PITCH := 16.0

## Synty .res meshes ship without a resolved material and render untextured white. The same
## atlas ground_item.gd assigns for the same reason.
const SYNTY_MAT := "res://Assets/PolygonDungeon/Materials/Dungeon_Material_01_mat.tres"

const COLOR_KEY := Color(0.5, 0.55, 0.62)
const COLOR_FILL := Color(1.05, 1.02, 0.98)

static var _cache: Dictionary = {}
static var _viewport: SubViewport
static var _holder: Node3D
static var _busy := false


static func texture_for(tree: SceneTree, item: ItemResource) -> Texture2D:
	## The item's photograph, rendering it first if this is the first time anybody asked.
	## Null when the item has no model to photograph — the caller keeps its flat icon.
	if item == null or tree == null:
		return null
	# An item that names its own icon has hand-drawn art, and hand-drawn wins.
	#
	# Nothing takes this path today. It was added for the armour, whose models were flat-painted
	# shells carved off the Kenney soldier rig that rendered as slabs from every angle — and then
	# the drawn icon that replaced them didn't match the thing lying on the floor, which was
	# worse. The armour now points at pieces cut off the Synty characters (build_synty_armor.gd)
	# and photographs properly, so the escape hatch stays only for art that genuinely has no
	# model worth showing.
	if item.icon_path != "":
		return null
	var path: String = item.display_model_path()
	if path == "":
		return null
	if _cache.has(path):
		return _cache[path]
	# One shot at a time: the viewport is shared, and two items rendering into it at once would
	# each get a picture of the other.
	while _busy:
		await tree.process_frame
	if _cache.has(path):
		return _cache[path]
	_busy = true
	var tex: Texture2D = await _render(tree, item, path)
	_cache[path] = tex
	_busy = false
	return tex


static func _render(tree: SceneTree, item: ItemResource, path: String) -> Texture2D:
	_ensure_viewport(tree)
	# instantiate_model() is the item's OWN builder: it resolves model_material_path, which is
	# the difference between a potion and a grey blob. This used to test for a "get_model"
	# method that does not exist, so every item silently fell through to the bare loader below
	# and rendered unmaterialled — the potion came out putty-coloured and the bow as a white
	# hairline.
	var model: Node3D = item.instantiate_model()
	if model == null:
		model = _instance_of(path)
		_apply_atlas(model)
	if model == null:
		return null
	_holder.add_child(model)
	# Whatever the model was scaled for elsewhere, here it is framed to fill the picture.
	_frame(model, item)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	# Two frames: one for the viewport to draw, and post_draw so the texture is readable.
	await RenderingServer.frame_post_draw
	var img: Image = _viewport.get_texture().get_image()
	model.queue_free()
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


static func _instance_of(path: String) -> Node3D:
	var res: Resource = load(path)
	if res is PackedScene:
		return (res as PackedScene).instantiate() as Node3D
	if res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res
		return mi
	return null


static func _apply_atlas(model: Node3D) -> void:
	## Paint a raw Synty mesh with the shared dungeon atlas. Only for the weapon-kind fallback
	## models, which no ItemResource names a material for.
	if model == null:
		return
	var atlas: Material = load(SYNTY_MAT)
	if atlas == null:
		return
	for mi in _mesh_nodes(model):
		if mi.mesh != null and mi.mesh.surface_get_material(0) == null 				and mi.material_override == null:
			mi.material_override = atlas


static func _mesh_nodes(node: Node, out: Array = []) -> Array:
	var mi := node as MeshInstance3D
	if mi != null:
		out.append(mi)
	for child in node.get_children():
		_mesh_nodes(child, out)
	return out


static func _frame(model: Node3D, item: ItemResource = null) -> void:
	## Turn the model square-on to the camera, lay it out to use as much of the cell as it can,
	## and centre it.
	##
	## An item carrying an icon_rotation is turned to exactly that and the ranking below is
	## skipped — see ItemResource.icon_rotation_override. Only the fit is still measured, so an
	## authored angle still fills its cell.
	##
	## The model is aimed by its OWN proportions rather than by a fixed camera angle. Its
	## thinnest axis is turned toward the viewer, so what is drawn is the item's full silhouette
	## — a sword's profile, not a sword end-on — and its longest axis is laid either up the
	## picture or along the diagonal depending on how long it is. Anything scaled to fill the
	## frame then fills it, instead of being scaled by a number picked for the average item.
	var boxes: Array = []
	_collect(model, boxes, model)
	if boxes.is_empty():
		return
	var total: AABB = boxes[0]
	for i in range(1, boxes.size()):
		total = total.merge(boxes[i])
	var size := total.size
	if maxf(maxf(size.x, size.y), size.z) <= 0.0:
		return

	if item != null and item.icon_rotation_override:
		_fit(model, total, Basis.from_euler(Vector3(
			deg_to_rad(item.icon_rotation.x),
			deg_to_rad(item.icon_rotation.y),
			deg_to_rad(item.icon_rotation.z))))
		return

	# Rank the model's axes: longest, middling, thinnest.
	var axes := [0, 1, 2]
	axes.sort_custom(func(a, b): return size[a] > size[b])
	var long_axis: int = axes[0]
	var mid_axis: int = axes[1]
	var thin_axis: int = axes[2]
	var long_len: float = size[long_axis]
	var mid_len: float = size[mid_axis]

	var aim := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var elongated: bool = mid_len > 0.0 and long_len / mid_len >= ELONGATED
	if elongated:
		# Long and thin: corner to corner, the way the reference sheets lay out blades.
		aim[long_axis] = DIAGONAL
		aim[mid_axis] = ACROSS_DIAGONAL
	else:
		# Squat: stood upright, then turned — see TURN_YAW.
		aim[long_axis] = Vector3.UP
		aim[mid_axis] = Vector3.RIGHT
	aim[thin_axis] = Vector3.BACK

	var basis := Basis(aim[0], aim[1], aim[2])
	# Ranking the axes can hand back a mirrored frame — three of the six orderings are
	# left-handed. Flipping the axis pointed at the camera un-mirrors it without disturbing the
	# layout, which matters for anything with a readable face.
	if basis.determinant() < 0.0:
		aim[thin_axis] = Vector3.FORWARD
		basis = Basis(aim[0], aim[1], aim[2])
	if not elongated:
		basis = Basis.from_euler(
			Vector3(deg_to_rad(TURN_PITCH), deg_to_rad(TURN_YAW), 0.0)) * basis

	_fit(model, total, basis)


static func _fit(model: Node3D, total: AABB, basis: Basis) -> void:
	## Scale the turned model to fill the cell and centre it.
	##
	## Measured, not predicted: push the box's eight corners through the rotation and read the
	## picture it actually covers. The old arithmetic assumed the two in-frame axes stayed axis
	## aligned, which stopped being true the moment anything was turned.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in range(8):
		var p: Vector3 = basis * total.get_endpoint(i)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var span: float = maxf(hi.x - lo.x, hi.y - lo.y)

	# ORDER MATTERS. Rotation and scale first, then the offset that centres the thing, computed
	# THROUGH the basis those two just set.
	#
	# Doing it the other way round — offset, then rotate — spins the offset as well, which is
	# fine while a model sits near its own origin and catastrophic when it does not. The bow's
	# mesh is authored seven units off to the side of its scene root, so rotating its centring
	# offset threw it clean out of frame and the cell rendered empty.
	model.basis = basis.scaled(Vector3.ONE * (1.0 / maxf(span * MARGIN, 0.0001)))
	model.position = -(model.basis * total.get_center())


static func _collect(node: Node, out: Array, root: Node3D) -> void:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		# Into the root's space, so children with their own transforms are measured where they
		# actually sit rather than where their mesh was authored.
		out.append(root.global_transform.affine_inverse() * (mi.global_transform * mi.mesh.get_aabb()))
	for child in node.get_children():
		_collect(child, out, root)


static func _ensure_viewport(tree: SceneTree) -> void:
	if _viewport != null and is_instance_valid(_viewport):
		return
	_viewport = SubViewport.new()
	_viewport.name = "ItemThumbnails"
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.transparent_bg = true
	# Its own world, or the dungeon's lighting, fog and every prop in it would turn up in the
	# picture. This viewport contains exactly one item and the two lights pointed at it.
	_viewport.own_world_3d = true
	_viewport.world_3d = World3D.new()
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(_viewport)

	_holder = Node3D.new()
	_viewport.add_child(_holder)

	var cam := Camera3D.new()
	# Orthogonal, so the item is measured rather than perspective-distorted — a cell is a
	# catalogue photograph, not a scene.
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.0
	cam.position = Vector3(0, 0, 2)
	cam.near = 0.01
	cam.far = 10.0
	_viewport.add_child(cam)

	# A key light off to one side to give the shape some form, and a fill from the camera so
	# nothing goes to pure black.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -40, 0)
	# Bright: the Synty atlas is a fairly dark palette and a cell is 54 pixels of it, so a
	# photograph lit for a scene comes out as a silhouette in a bag.
	key.light_energy = 2.4
	key.light_color = COLOR_FILL
	_viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, 150, 0)
	fill.light_energy = 1.0
	fill.light_color = COLOR_KEY
	_viewport.add_child(fill)
