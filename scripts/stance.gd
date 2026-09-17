extends RefCounted
class_name Stance
## Catalogue of defensive stances: what the stance selector lists, and how each one reads.
##
## `id` is the value Combatant.defensive_option stores, so these numbers are load-bearing —
## 0 = Parry and 1 = Dodge are baked into quest_scene.tscn and every stat block in resources/stats.
## Append new stances rather than renumbering.
##
## IMPORTANT: adding an entry here puts it in the selector immediately, but the selector is
## only the front half. Combatant._attempt_defense branches on `defensive_option != DODGE`
## for parry and treats DODGE alone as dodge, so a new stance will silently resolve AS a
## PARRY until that function learns about it. Add the branch there in the same change.

const PARRY := 0
const DODGE := 1
## Holds ground instead of trading blows: enemies that come within a square of a guardian
## must stop and fight him. Resolves defensively as a parry with a melee-only bonus — see
## Combatant._attempt_defense and Combatant.is_guarding.
const PROTECTION := 2

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
	{
		"id": PROTECTION,
		"name": "Protection",
		"icon": "res://assets/UI/SPR_FantasyWarrior_Greeble_Shield01.png",
		"hint": "Plant your feet and hold the line. Enemies that come within a square must stop and fight you. Parries, but only a fighter can take it.",
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


static func available_for(who: Node) -> Array[Dictionary]:
	## Which stances a given combatant may take. Parry and Dodge are open to everyone.
	## Protection is gated on `can_guard`, so holding a line is a fighter's trade rather than
	## something the wizard can pick up mid-battle — the same shape as Combatant.can_cast
	## gating spellcasting on the capability rather than on the attribute behind it.
	##
	## `get()` on a missing property returns null (falsy), so a caller that is not a Combatant
	## simply sees the ungated stances instead of erroring.
	var out: Array[Dictionary] = []
	for s in ALL:
		if s["id"] == PROTECTION and not (who != null and who.get("can_guard")):
			continue
		out.append(s)
	return out
