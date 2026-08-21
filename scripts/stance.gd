extends RefCounted
class_name Stance
## Catalogue of defensive stances: what the stance selector lists, and how each one reads.
##
## `id` is the value Combatant.defensive_option stores, so these numbers are load-bearing —
## 0 = Parry and 1 = Dodge are baked into main.tscn and every stat block in resources/stats.
## Append new stances rather than renumbering.
##
## IMPORTANT: adding an entry here puts it in the selector immediately, but the selector is
## only the front half. Combatant._attempt_defense branches on `defensive_option == 0` for
## parry and treats everything else as dodge, so a new stance will silently resolve AS a
## dodge until that function learns about it. Add the branch there in the same change.

const PARRY := 0
const DODGE := 1

## Ordered as they appear in the popup. `icon` is a Fantasy Warrior HUD greeble; `hint` is
## the one-line explanation shown beside the name.
const ALL: Array[Dictionary] = [
	{
		"id": PARRY,
		"name": "Parry",
		"icon": "res://assets/UI/SPR_FantasyWarrior_Greeble_Swords01.png",
		"hint": "Turn blades aside. Needs a weapon or shield in hand; only a shield can parry arrows.",
	},
	{
		"id": DODGE,
		"name": "Dodge",
		"icon": "res://assets/UI/SPR_FantasyWarrior_Greeble_Wings01.png",
		"hint": "Slip out of the way. Works empty-handed, but nothing dodges arrows without a dodge-capable item.",
	},
]


static func by_id(id: int) -> Dictionary:
	for s in ALL:
		if s["id"] == id:
			return s
	return ALL[0]


static func display_name(id: int) -> String:
	return by_id(id)["name"]


static func icon_path(id: int) -> String:
	return by_id(id)["icon"]


static func available_for(_who: Node) -> Array[Dictionary]:
	## Which stances a given combatant may take. Everyone can use both of the current two, so
	## this returns the lot — it exists as the hook for stances gated on a class, a skill or a
	## piece of equipment, so the selector never has to grow that logic itself.
	return ALL
