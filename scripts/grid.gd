extends MeshInstance3D
## Draws a flat grid on the battlefield showing movement cells

@export var grid_size := 16
@export var cell_size := 2.0
@export var line_color := Color(0.2, 0.2, 0.2, 0.5)
@export var line_height := 0.12

func _ready() -> void:
	mesh = _build_grid_mesh()


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
