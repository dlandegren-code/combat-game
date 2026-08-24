extends "res://scripts/abilities/ability.gd"
## Firebolt: the wizard's attack at range. A bolt of fire that costs mana as well as time and
## scales off spell power, so it gets stronger with willpower rather than with equipment.
##
## Deliberately NOT a weapon attack. Its reach is the spell's own constant rather than
## get_ranged_range(), because the caster is not throwing the staff — reach being a weapon
## property applies to weapons, and a spell brings its own.
##
## The bolt is resolved as a missile (Combatant._do_firebolt passes is_ranged), so a shield can
## still bat it aside and a pillar still gives cover. That keeps one set of defence rules
## rather than a separate one for magic.

## Mana per cast. At 5, a 25-point pool (willpower 5) is five bolts a fight.
const MANA_COST := 5
## Tiles. Under Combatant.RANGE_FREE_TILES on purpose, so a bolt never takes the distance
## penalty — a spell's limit is its reach, not its accuracy falling off.
const RANGE_TILES := 8
## Added to the caster's spell power to get damage: a stronger will burns hotter.
const DAMAGE_BONUS := 2


func _init() -> void:
	display_name = "Firebolt"
	target_kind = TargetKind.ENEMY


func get_cost(actor) -> int:
	return actor.spell_cost


func get_range(_actor) -> int:
	return RANGE_TILES


func can_use(actor) -> bool:
	return actor.can_cast and actor.mana >= MANA_COST


func can_target(actor, target) -> bool:
	if target == null or not can_use(actor):
		return false
	var dist: float = abs(target.position.x - actor.position.x) + abs(target.position.z - actor.position.z)
	return dist <= RANGE_TILES * actor.GRID_SIZE and actor._has_line_of_sight(target)


func unavailable_reason(actor) -> String:
	## "resource" gives the help cursor, "range" the forbidden one. Not being a caster and
	## being out of mana are both resource problems; anything else is geometry.
	if not actor.can_cast or actor.mana < MANA_COST:
		return "resource"
	return "range"


func is_spell() -> bool:
	return true


func get_mana_cost(_actor) -> int:
	return MANA_COST


func get_icon_path() -> String:
	return "res://assets/UI/icons/ICON_FantasyWarrior_Inventory_Magic01_Clean.png"


func get_description(_actor) -> String:
	return "A bolt of fire. Ignores armour, but resistance still soaks it."


func get_damage_text(actor) -> String:
	return "%d fire" % [actor.get_spell_power() + DAMAGE_BONUS]


func execute(actor, target) -> void:
	# The Kenney rig has no casting clip, so this borrows the two-handed ranged one — it reads
	# acceptably for a staff thrust forward. Swap it when a cast animation exists.
	actor._play_attack_anim("holding-both-shoot")
	# Awaited, unlike every other ability's execute(): the bolt is a projectile that has to
	# fly and land before the attack is rolled, and player.gd waits on this call so the turn
	# does not end while it is still in the air.
	await actor._do_firebolt(target)
