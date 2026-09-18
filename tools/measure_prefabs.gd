extends Node3D
## Dev tool: prints the real size of every imported Synty prefab.
##
## Run it by playing tools/measure_prefabs.tscn; it writes .summer/local/prefab_sizes.txt and
## quits. Nothing else in the game uses it.
##
## WHY
## The town is laid out from a table of positions (town_layout.gd), and a table of positions
## written without knowing how big a barn is puts the barn through the farmhouse. This reports
## the merged bounding box of each prefab's meshes — footprint, height, and how far the pivot
## sits above the model's lowest point — so the layout can be written from measurements.

const REPORT := "res://.summer/local/prefab_sizes.txt"
const ROOTS := ["res://assets/Synty/PolygonFarm/Prefabs", "res://assets/Synty/PolygonMeadow/Models"]

var _lines: Array[String] = []


func _ready() -> void:
	for root in ROOTS:
		_walk(root)
	_lines.sort()
	var out := PackedStringArray([
		"# Synty prefab sizes, in world units.",
		"# origin_y = how far the pivot sits above the lowest point (0 = pivot on the ground).",
		"# off = where the model's centre sits relative to its pivot, on x and z.",
		"",
	])
	for line in _lines:
		out.append(line)
	DirAccess.make_dir_recursive_absolute(REPORT.get_base_dir())
	var f := FileAccess.open(REPORT, FileAccess.WRITE)
	f.store_string("\n".join(out) + "\n")
	f.close()
	print("[Measure] wrote %s (%d prefabs)" % [REPORT, _lines.size()])
	get_tree().quit()


func _walk(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("Measure: cannot open %s" % dir_path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_walk(full)
		elif entry.ends_with(".tscn") or entry.ends_with(".fbx"):
			# .fbx as well as .tscn: an imported FBX IS a PackedScene as far as load() cares,
			# and the meadow pack ships raw FBX rather than prefabs.
			_measure(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _measure(path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var node := packed.instantiate()
	# Into the tree, because a mesh's global transform only means anything once it has one —
	# the windmill's blades sit nine metres up, and a prefab measured out of the tree would
	# report only its base.
	add_child(node)
	var box := _merged_aabb(node)
	remove_child(node)
	node.queue_free()
	if box.size == Vector3.ZERO:
		return
	_lines.append("%-42s size %6.2f,%6.2f,%6.2f   origin_y %6.2f   off %6.2f,%6.2f" % [
		path.get_file().trim_suffix(".tscn").trim_suffix(".fbx"),
		box.size.x, box.size.y, box.size.z,
		-box.position.y,
		box.get_center().x, box.get_center().z,
	])


func _merged_aabb(node: Node) -> AABB:
	## Every mesh under `node`, merged, expressed in THIS tool's space — which is the prefab's
	## own space, since the prefab is parented directly to the tool.
	var box := AABB()
	var started := false
	var mesh_node := node as MeshInstance3D
	if mesh_node != null and mesh_node.mesh != null:
		var relative: Transform3D = global_transform.affine_inverse() * mesh_node.global_transform
		box = relative * mesh_node.get_aabb()
		started = true
	for child in node.get_children():
		var child_box := _merged_aabb(child)
		if child_box.size == Vector3.ZERO:
			continue
		box = child_box if not started else box.merge(child_box)
		started = true
	return box if started else AABB()
