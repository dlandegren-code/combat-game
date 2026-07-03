extends StaticBody3D
## Impassable column obstacle. Blocks character movement and ranged line of sight.

func _ready() -> void:
	add_to_group("obstacles")
