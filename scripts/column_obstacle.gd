extends StaticBody3D
## Impassable column obstacle: its grid cell can't be entered, and units can't cut the
## diagonal corner past it (see Combatant._is_corner_blocked).
##
## It does NOT block line of sight. The collider is deliberately short — below the eye-height
## LOS ray but above the waist-height cover ray — so a pillar hinders a shot rather than
## stopping it (Combatant._has_partial_cover_from). Raising it would turn every pillar into
## full cover.

func _ready() -> void:
	add_to_group("obstacles")
