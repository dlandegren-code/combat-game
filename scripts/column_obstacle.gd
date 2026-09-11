extends StaticBody3D
## Impassable column obstacle: its grid cell can't be entered.
##
## It does NOT block line of sight. The collider is deliberately short — below the eye-height
## LOS ray but above the waist-height cover ray — so a pillar hinders a shot rather than
## stopping it (Combatant._has_partial_cover_from). Raising it would turn every pillar into
## full cover.

func _ready() -> void:
	add_to_group("obstacles")


func fills_cell() -> bool:
	## No. The collider is a half-unit radius standing in the middle of a two-unit cell, so a
	## pillar leaves three quarters of its square as open floor — and two pillars touching at
	## their corners leave nearly two units of gap between the stones.
	##
	## Which means a diagonal step between a pair of them is a walk past two pillars, not a
	## squeeze through a wall, and Combatant._is_side_solid must not treat it as the latter.
	## Standing IN the cell is still refused; that is _is_obstacle_at's business and this does
	## not touch it.
	return false
