extends "res://scripts/abilities/ability.gd"

const ActionCursors := preload("res://scripts/action_cursors.gd")
## Open/Close: work whatever is within reach on the clicked tile — a door today, a chest or a
## lever the day one exists.
##
## The ability knows nothing about doors. It looks for a node in the "interactables" group and
## asks it three questions:
##
##   can_interact(actor) -> bool     may this be worked right now (an unlocked door: yes)
##   interact_verb() -> String       what the action is called on THIS thing, right now
##   interact(actor) -> void         do it
##
## That is the whole contract. A chest that answers those three joins the action without either
## side learning about the other, which is the point of it being one action rather than an
## Open Door action and an Open Chest action.
##
## Tile-targeted rather than enemy-targeted, so it goes through the same click path Pick Up
## already uses: select it, click the square the thing is on.

func _init() -> void:
	display_name = "Open/Close"
	target_kind = TargetKind.TILE


func get_cost(actor) -> int:
	return actor.interact_cost


func get_range(actor) -> int:
	return actor.INTERACT_REACH_TILES


func can_target(actor, target) -> bool:
	return actor._interactable_at(target) != null


func unavailable_reason(_actor) -> String:
	## Never a resource problem: opening a door costs time and nothing else. Everything that
	## can go wrong here is "there is nothing there, or it is too far away".
	return "range"


func get_description(_actor) -> String:
	return "Open or close a door, chest or other fitting within reach."


func execute(actor, target) -> void:
	actor._do_interact(target)


func get_cursor_icon(actor, target) -> String:
	## One action, three pointers: a hand going into a box, a dagger at a lock it could pick,
	## and the help cursor over a lock it could not.
	##
	## The help cursor rather than the forbidden one, and rather than refusing the target
	## outright: a locked chest IS a legal thing to click — clicking it rattles the lock and
	## says so — it just will not open. Refusing it would drop the click through to a move
	## order, which is how you end up walking into a chest you meant to try.
	var thing = actor._interactable_at(target)
	if thing == null:
		return ""
	var hint: String = ""
	if thing.has_method("interact_cursor_hint"):
		hint = thing.interact_cursor_hint(actor)
	match hint:
		"pick":
			return CURSOR_DAGGER
		"shut":
			return ActionCursors.HELP
		_:
			return CURSOR_ITEMS
