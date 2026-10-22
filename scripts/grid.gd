extends MeshInstance3D
## Draws a flat grid on the battlefield showing movement cells

@export var grid_size := 16
@export var cell_size := 2.0
@export var line_color := Color(0.2, 0.2, 0.2, 0.5)
@export var line_height := 0.12

## A floor tile is this many cells a side (DungeonLayout.TILE / GRID).
const CELLS_PER_TILE := 2

func _ready() -> void:
	# Deferred: the dungeon is built by DungeonRoom, which comes after this node in the scene and
	# so is not ready yet.
	call_deferred("_rebuild")


func _rebuild() -> void:
	var room := get_parent().get_node_or_null("DungeonRoom") if get_parent() else null
	if room != null and room.has_method("floor_tiles"):
		mesh = _build_floor_grid_mesh(room.floor_tiles())
	else:
		mesh = _build_grid_mesh()


func _build_floor_grid_mesh(tiles: Array) -> ArrayMesh:
	## The cells of a generated dungeon: every floor tile's 2x2 squares outlined, and nothing
	## over the rock between rooms.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var tile := cell_size * CELLS_PER_TILE
	for t in tiles:
		var x0: float = t.x * tile
		var z0: float = t.y * tile
		for i in range(CELLS_PER_TILE + 1):
			var o := float(i) * cell_size
			st.set_color(line_color)
			st.add_vertex(Vector3(x0, line_height, z0 + o))
			st.add_vertex(Vector3(x0 + tile, line_height, z0 + o))
			st.set_color(line_color)
			st.add_vertex(Vector3(x0 + o, line_height, z0))
			st.add_vertex(Vector3(x0 + o, line_height, z0 + tile))
	return st.commit()


func _build_grid_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	var half := float(grid_size) * cell_size / 2.0

	for i in range(grid_size + 1):
		var offset := -half + float(i) * cell_size

		# Lines along X
		st.set_color(line_color)
		st.add_vertex(Vector3(-half, line_height, offset))
		st.add_vertex(Vector3(half, line_height, offset))

		# Lines along Z
		st.set_color(line_color)
		st.add_vertex(Vector3(offset, line_height, -half))
		st.add_vertex(Vector3(offset, line_height, half))

	return st.commit()
