extends Node
## The dungeon runs in one of two modes, and this owns both of them.
##
## EXPLORATION is the party walking a room nobody has been alerted in. There is no clock and
## no initiative: one hero is active at a time, the player switches between them freely, and a
## move costs nothing because nothing is being raced. The enemies are not in an order either —
## they mill about on a timer (see _idle_pulse), watching for someone to walk into view.
##
## COMBAT is the original tick-based time-unit system: initiative order, action costs, a
## current_tick that only ever goes forward.
##
## raise_alarm() takes the party from the first into the second, and _stand_down() brings them
## back — but only by WINNING. A fight is not left by walking away from it: a party that could
## drop out of combat at will would break every defence-debt guarantee the tick system makes,
## and "the goblins lose interest" is still nobody's code. When the last enemy falls there is
## nothing left to guarantee, so the clock stops and the dungeon goes back to being explored.
##
## Both modes drive the SAME current_combatant and turn_changed signal, deliberately. Every
## piece of UI — the toolbar, the party portraits, the character and spell sheets — is already
## written against "who is active", and in exploration the active hero is simply the selected
## one rather than the one whose turn it is. That is what let a second mode go in without
## touching any of them.

signal turn_changed(combatant: Node)

## The two ways a quest can be decided, announced for whoever is running the quest to act on
## (QuestScene). The combat layer deliberately does not act on them itself — it knows when a
## fight is over, not what that means for the adventure.
##
## fight_won is NOT "quest cleared": the last goblin falling leaves a room with a chest in it
## and loot on the floor, and the party is meant to go and collect it. So this says the way
## out is open, and something above decides when to take it. See _stand_down.
##
## party_wiped IS final. There is nobody left to give an order to, so there is no play left
## and the only question is how the defeat is reported.
signal fight_won
signal party_wiped

const GroundItemScript := preload("res://scripts/ground_item.gd")

## Beat between an enemy's turn lighting up and it acting, so the player can register
## whose turn it is instead of the AI moving the instant they finish their own action.
const ENEMY_TURN_DELAY := 0.6

## Seconds between exploration pulses: one look round for intruders, then a step of whatever
## the unalerted enemies are each doing. Slow on purpose — this is ambient movement in a room
## the player is creeping through, not a turn being taken.
const IDLE_PULSE_TIME := 1.2

enum Mode { EXPLORATION, COMBAT }

var mode: int = Mode.EXPLORATION
var combatants: Array[Node] = []
var current_combatant: Node = null
var current_tick: int = 0
var game_over := false

var turn_label: Label
var order_list: VBoxContainer
## The initiative readout, hidden while exploring: there is no order to show, and a stale one
## would be worse than none.
var initiative_panel: CanvasLayer

var _idle_timer: Timer
## Set when the alarm goes up UNDER a hero's action — see raise_alarm. The order then starts
## when that action reports in rather than on top of it.
var _combat_pending := false


func _ready() -> void:
	turn_label = get_parent().get_node("HUD/TurnLabel")
	order_list = get_parent().get_node("InitiativePanel/Panel/OrderList")
	initiative_panel = get_parent().get_node_or_null("InitiativePanel")
	# Deferred, because who is IN this fight is no longer settled by the time this node is
	# ready. _ready runs bottom-up — every child before its parent — so the scene root has not
	# had its turn yet, and the root is what assembles the party now: QuestScene spawns a body
	# for each member of GameState.party and retires the hand-placed ones. Collecting here
	# would deal the old test scenario's heroes into the order and miss the real party.
	# Phase 4's generated rooms will place their enemies from the same hook.
	call_deferred("_boot")


func _boot() -> void:
	_collect_combatants()
	_spawn_ground_items()
	if combatants.is_empty():
		return
	_start_exploration()


# --- Exploration -----------------------------------------------------------

func is_exploring() -> bool:
	## Asked from all over: Combatant.get_move_range wants to know whether to ration steps,
	## and Enemy wants to know whether it is still milling about.
	return mode == Mode.EXPLORATION and not game_over


func _cast_idle_roles() -> void:
	## Decide who walks a beat and who loiters, once, before the party takes its first step.
	##
	## Rolled here rather than authored per enemy in the scene, so the room is not the same
	## tableau every run: which goblin is the one on his feet is exactly the sort of thing that
	## should be different on a second visit, while WHERE a beat goes is level design and stays
	## in patrol_route (see Enemy.cast_idle_role).
	##
	## Exactly one of them. A patrol is the thing the player watches, times and slips behind, and
	## that only works if there is something to slip behind TO: a room where everybody is
	## marching is a parade, and one where everybody is standing still is a waxworks. Two
	## walkers in a room this size was already most of the floor covered most of the time. The
	## rest loiter, which is its own kind of busy — see Enemy.idle_step.
	##
	## WHICH one is still the roll, which is the part that matters for a second visit.
	##
	## The boss is not in the draw. He has a throne, and a warlord doing laps of his own hall is
	## not a warlord.
	var pool: Array = []
	for c in combatants:
		if not is_instance_valid(c) or c.is_player_controlled or not c.is_alive:
			continue
		if not c.has_method("cast_idle_role"):
			continue
		if c.has_method("keeps_to_its_post") and c.keeps_to_its_post():
			c.cast_idle_role(false)
			continue
		pool.append(c)
	pool.shuffle()
	for i in range(pool.size()):
		pool[i].cast_idle_role(i == 0)


func _start_exploration() -> void:
	mode = Mode.EXPLORATION
	current_tick = 0
	_cast_idle_roles()
	if initiative_panel:
		initiative_panel.visible = false
	_idle_timer = Timer.new()
	_idle_timer.name = "IdlePulse"
	_idle_timer.wait_time = IDLE_PULSE_TIME
	_idle_timer.autostart = true
	_idle_timer.timeout.connect(_idle_pulse)
	add_child(_idle_timer)
	var party := party_members()
	if party.is_empty():
		return
	set_explorer(party[0])


func party_members() -> Array:
	## Every hero still standing, in scene order. The pool exploration hands control around.
	var out: Array = []
	for c in combatants:
		if is_instance_valid(c) and c.is_alive and c.is_player_controlled:
			out.append(c)
	return out


func _check_party_wiped() -> bool:
	## Has the party been wiped out? If so, stop the clock and say so, once.
	##
	## game_over rather than a stand-down: there is no exploring a dungeon with no explorers,
	## and every route into a turn checks this flag. The bodies are left where they fell —
	## whoever is running the quest still has to read what the party was carrying off them
	## (QuestScene.finish_quest).
	if game_over:
		return false
	if not party_members().is_empty():
		return false
	# An empty room is not a defeat: with no combatants at all there is nobody to lose.
	if combatants.is_empty():
		return false
	game_over = true
	_highlight_active(null)
	if initiative_panel:
		initiative_panel.visible = false
	if _idle_timer:
		_idle_timer.stop()
	if turn_label:
		turn_label.text = "The party has fallen..."
	party_wiped.emit()
	return true


func enemies_alive() -> bool:
	## Is there anybody left to fight? The condition the fight ends on — see _stand_down.
	for c in combatants:
		if is_instance_valid(c) and c.is_alive and not c.is_player_controlled:
			return true
	return false


func set_explorer(who: Node) -> void:
	## Hand control to one hero. The others are stood down, so exactly one character is taking
	## orders at a time — the same invariant combat relies on, reached a different way.
	if not is_exploring() or who == null or not is_instance_valid(who) or not who.is_alive:
		return
	for c in party_members():
		if c != who and c.has_method("disable_turn"):
			c.disable_turn()
	current_combatant = who
	who.enable_turn()
	_highlight_active(who)
	_update_turn_label(who)
	turn_changed.emit(who)


func cycle_explorer(step: int = 1) -> void:
	## Next hero along, wrapping. Refused mid-walk: handing control away from a character who
	## is still crossing the floor would leave them walking with nobody driving, and their move
	## would then report in against whoever had been switched to.
	if not is_exploring():
		return
	var party := party_members()
	if party.size() < 2:
		return
	if is_instance_valid(current_combatant) and current_combatant.is_moving:
		return
	var i: int = party.find(current_combatant)
	if i < 0:
		# Nobody valid was active — the last selection died, or this is the first call. Take
		# the front of the party rather than stepping off an index of -1.
		set_explorer(party[0])
		return
	set_explorer(party[posmod(i + step, party.size())])


func _idle_pulse() -> void:
	## One beat of the unalerted world: everybody looks, then everybody moves.
	##
	## Looking comes first for ALL of them before anybody takes a step. Interleaved, a goblin
	## that could already see the party might wander off on the same pulse it spotted them, and
	## which of those two happened would come down to scene order.
	if not is_exploring():
		return
	for c in combatants:
		if not _is_idle_enemy(c):
			continue
		if c.has_method("notices_intruders") and c.notices_intruders():
			raise_alarm(c)
			return
	for c in combatants:
		if _is_idle_enemy(c) and c.has_method("idle_step"):
			c.idle_step()


func _is_idle_enemy(c) -> bool:
	return is_instance_valid(c) and c.is_alive and not c.is_player_controlled


func raise_alarm(by: Node = null) -> void:
	## Exploration is over. Called two ways, and they are NOT the same call.
	##
	## An enemy noticing somebody (_idle_pulse) happens between actions, with nothing running,
	## so the fight starts on the spot.
	##
	## A hero starting something (Player._handle_click) happens BEFORE their action does, and
	## must only be booked. Switching mode out from under a running action broke it three ways
	## at once: disable_turn stripped the cursor and can_act from the character still executing;
	## _activate_next handed the turn to an enemy that then acted 0.6s later, on top of the
	## hero's own swing; and worst, get_move_range collapsed from EXPLORE_MOVE_RANGE to the
	## combat allowance mid-click, so _start_path_move could no longer path to the tile the
	## cursor had just promised and fell through to its slide-straight-there fallback — the
	## character crossing the room in a straight line while the shout that should have covered
	## the run played at the start of it.
	##
	## So a player-raised alarm changes nothing yet. The action finishes as an exploration
	## action — full movement, correct route, sounds where they belong — and turn_done does the
	## actual switch when it reports in.
	if mode == Mode.COMBAT or _combat_pending or game_over:
		return
	if by != null and "is_player_controlled" in by and by.is_player_controlled:
		_combat_pending = true
		return
	_engage(by)


func _engage(shouted_by: Node, opening_actor: Node = null, opening_cost: int = 0) -> void:
	## Do the switch: the whole room knows, the clock starts, the order begins.
	##
	## `shouted_by` is whoever gets the "Alarm!" caption, or null for nobody — a fight the
	## party started needs no caption, because the swing that started it is the announcement.
	##
	## `opening_actor` / `opening_cost` bill the action that started the fight, when there was
	## one. It is NOT free: exploration movement is uncapped, so a free opening action would
	## mean charging the length of the room and swinging for nothing. Billed, it is priced by
	## the tick per tile it actually took, which is its own limit on how far a charge is worth
	## starting from.
	mode = Mode.COMBAT
	if _idle_timer:
		_idle_timer.stop()
	if initiative_panel:
		initiative_panel.visible = true
	for c in combatants:
		if not is_instance_valid(c):
			continue
		if "alerted" in c:
			c.alerted = true
		# A sneak does not survive the alarm, and it must not: Sneak greys out in combat
		# (there is nobody left to creep past), so a character who carried the flag across
		# would be stuck at half movement for the whole fight with no way to switch it off.
		if "sneaking" in c and c.sneaking:
			c.set_sneaking(false)
		# Everybody's clock starts here, at zero. Exploration never advanced next_turn_at, but
		# it is reset rather than trusted: this is the moment the tick system takes over, and
		# it should not inherit anything.
		c.next_turn_at = 0
		c.action_turn_at = 0
	if opening_actor != null and is_instance_valid(opening_actor):
		# The only clock that is not zero. Everyone else acts before this character comes round
		# again, which is the right shape for it: you got your blow in unopposed, and now the
		# room answers all at once.
		opening_actor.next_turn_at = maxi(opening_cost, 1)
		opening_actor.action_turn_at = opening_actor.next_turn_at
	if shouted_by != null and shouted_by.has_method("_show_action_text"):
		shouted_by._show_action_text("Alarm!")
	_begin_combat()


func _begin_combat() -> void:
	for c in combatants:
		if is_instance_valid(c) and c.has_method("disable_turn"):
			c.disable_turn()
	current_combatant = null
	_start_combat()


func _stand_down() -> void:
	## The fight is won: the clock stops, the order goes away, and the party is exploring again.
	##
	## The one way back through raise_alarm's door, and it is not the goblins losing interest —
	## it is that there are no goblins. Nothing the tick system promises can be broken by
	## stopping a clock nobody is racing: every defence debt left over is owed to a corpse.
	##
	## Deliberately NOT game_over. Winning the fight in the chamber is not the end of the
	## dungeon — there is a room through the north door with a chest in it, and loot on the
	## floor to go and collect — and game_over stops all three from happening: is_exploring()
	## goes false, turn_done returns early, and _activate_next refuses to hand anybody a turn.
	## That is what left the party frozen under "Victory!" with a battlefield still to walk.
	if mode == Mode.EXPLORATION:
		return
	mode = Mode.EXPLORATION
	# A fight that was booked but never begun must not begin now: a hero who killed the last
	# enemy with the opening blow of an ambush has _combat_pending set and an alarm still owed.
	_combat_pending = false
	if initiative_panel:
		initiative_panel.visible = false
	if _idle_timer:
		_idle_timer.start()
	# The field is held. Announced before the tidying-up below so that whoever is running the
	# quest hears it at the moment the fight ends rather than a few statements later, and note
	# that it says the fight is won and not that the quest is over — there is still a room to
	# search. See the signal's own comment.
	fight_won.emit()
	# The clock is wound back to where _start_exploration leaves it, and this is not cosmetic:
	# defense_debt() is derived from the gap between next_turn_at and current_tick, so a hero
	# who ended the fight owing two ticks of parries would carry that debt into exploration —
	# unable to hold a guard line, with the initiative panel hidden and no way to see why.
	current_tick = 0
	for c in combatants:
		if not is_instance_valid(c):
			continue
		c.next_turn_at = 0
		c.action_turn_at = 0
		# The zone reads is_overwhelmed(), which the debt above was faking. Repainted here for
		# the same reason charge_defense_cost does it: the floor must not advertise a line the
		# character cannot hold, or go on hiding one they can.
		if c.has_method("_refresh_guard_zone"):
			c._refresh_guard_zone()
	var party := party_members()
	if party.is_empty():
		return
	# Whoever was up keeps control if they are still standing, so winning a fight does not also
	# shuffle the party selection under the player.
	var who: Node = current_combatant if party.has(current_combatant) else party[0]
	if who == current_combatant and not who.can_act:
		# Their action is still running — the last enemy fell to a blow that has not finished
		# landing (see on_character_died for when that happens). Standing them up now would
		# hand the player a second action inside their first; their turn_done does it when the
		# action reports in, which is where every other end of turn goes through anyway. The
		# mode is already switched, so it lands in the exploration branch there and bills
		# nothing.
		_update_turn_label(who)
		return
	set_explorer(who)
	# Symmetric with _engage's "Alarm!": the caption that starts a fight comes from whoever
	# shouted, and the one that ends it from whoever is left holding the field.
	if who.has_method("_show_action_text"):
		who._show_action_text("Victory!")


func _collect_combatants() -> void:
	var all := get_tree().get_nodes_in_group("combatants")
	for c in all:
		if is_instance_valid(c):
			c.next_turn_at = 0
			c.action_turn_at = 0
			combatants.append(c)


func _start_combat() -> void:
	# Initial order: initiative descending (higher goes first at tick 0)
	combatants.sort_custom(func(a, b): return a.initiative > b.initiative)
	current_tick = 0
	_activate_next()


func _activate_next() -> void:
	if game_over:
		return

	# Before anything is handed a turn: is there still a party? Checked here for the same
	# reason the enemy check below is — this is the one guaranteed clean turn boundary — and
	# without it a fight the party had lost went on being played, with the surviving goblins
	# taking turn after turn against corpses and nobody able to end it.
	if _check_party_wiped():
		return

	# Nobody left to fight. Tested here because this is the one moment that is guaranteed to be
	# a clean turn boundary — the clock has just stopped, nothing is mid-action — and because
	# every route out of a combat turn comes through it, whichever side's blow ended the fight
	# and whether or not the corpse has finished falling. See _stand_down.
	if mode == Mode.COMBAT and not enemies_alive():
		_stand_down()
		return

	# Find combatant with minimum next_turn_at; ties broken by initiative
	var best: Node = null
	var best_tick: int = 0x7FFFFFFF
	var best_init: int = -1

	for c in combatants:
		if not is_instance_valid(c) or not c.is_alive:
			continue
		if c.next_turn_at < best_tick:
			best_tick = c.next_turn_at
			best_init = c.initiative
			best = c
		elif c.next_turn_at == best_tick and c.initiative > best_init:
			best_init = c.initiative
			best = c

	if not best:
		game_over = true
		_highlight_active(null)
		if turn_label:
			turn_label.text = "The battlefield is silent..."
		return

	current_tick = best_tick
	current_combatant = best

	_update_initiative_display()
	_update_turn_label(best)
	_highlight_active(best)

	best.enable_turn()
	turn_changed.emit(best)

	if not best.is_player_controlled and best.has_method("take_turn"):
		# Highlight now, act after a short beat — the player finishing their move no longer
		# snaps straight into the enemy's action.
		get_tree().create_timer(ENEMY_TURN_DELAY).timeout.connect(_begin_enemy_action.bind(best))


func _begin_enemy_action(who: Node) -> void:
	# Guard against the world changing during the delay (turn advanced, unit died, game over).
	if game_over or current_combatant != who or not is_instance_valid(who) or not who.is_alive:
		return
	who.take_turn()


func _highlight_active(active: Node) -> void:
	## Light the ring under `active` and clear it from everyone else (null = clear all).
	for c in combatants:
		if is_instance_valid(c) and c.has_method("set_turn_active"):
			c.set_turn_active(c == active and c.is_alive)


func turn_done(cost: int) -> void:
	if game_over or not current_combatant:
		return

	if _combat_pending:
		# A hero started the fight and their action has now finished, in exploration, exactly
		# as it would have if nothing had been started. THIS is where the room wakes up — see
		# raise_alarm for why it cannot happen any earlier.
		_combat_pending = false
		_engage(null, current_combatant, cost)
		return

	if mode == Mode.EXPLORATION:
		# Exploration has no clock, so there is nothing to bill and nobody waiting on this
		# character to be done. They are put through the same stand-down/stand-up a real turn
		# boundary would do — that is what clears a queued swing, a half-finished loot and the
		# cursor — and then handed straight back to the player.
		var who: Node = current_combatant
		if is_instance_valid(who) and who.is_alive:
			if who.has_method("disable_turn"):
				who.disable_turn()
			who.enable_turn()
			_update_turn_label(who)
		return

	if is_instance_valid(current_combatant) and current_combatant.has_method("disable_turn"):
		current_combatant.disable_turn()

	current_combatant.next_turn_at += cost
	# Stamped so defense_debt() can tell the two things that push next_turn_at apart: this,
	# the action just taken, and the +1 per successful defence in charge_defense_cost. Only
	# the latter is debt — see Combatant.defense_debt.
	current_combatant.action_turn_at = current_combatant.next_turn_at
	current_combatant = null
	_activate_next.call_deferred()


func on_character_died(who: Node) -> void:
	if game_over:
		return

	# Loss before win, because losing is the end of the game and winning is not. A party that
	# went down with the last goblin has still lost, and asked the other way round it would
	# stand a dead party up to explore with.
	if party_members().is_empty():
		game_over = true
		turn_label.text = "Defeat! All heroes have fallen."
		_update_initiative_display()
		return
	if not enemies_alive():
		# Won, so the party stands down rather than the game ending — see _stand_down.
		#
		# Usually already done by the time this runs: _die() awaits the death animation before
		# reporting in, so the killing blow's turn has normally ended and _activate_next has
		# already caught the empty battlefield. This is the other ordering — a model with no
		# "die" clip reports in the instant it is hit, with the swing still resolving — and
		# _stand_down is written to be safe either way.
		_stand_down()
		return

	# If dead combatant was the current actor, advance
	if current_combatant == who:
		if mode == Mode.EXPLORATION:
			# No order to advance through. Control goes to whoever is left standing; a party
			# that has lost somebody out of combat is still a party being driven.
			current_combatant = null
			cycle_explorer(0)
			return
		current_combatant = null
		_activate_next()


func _update_initiative_display() -> void:
	if not order_list:
		return
	for child in order_list.get_children():
		child.queue_free()

	var sorted := combatants.duplicate()
	sorted.sort_custom(func(a, b):
		if a.next_turn_at != b.next_turn_at:
			return a.next_turn_at < b.next_turn_at
		return a.initiative > b.initiative
	)

	for c in sorted:
		if not is_instance_valid(c):
			continue

		var label := Label.new()
		label.add_theme_font_size_override("font_size", 14)

		# Defence debt: ticks of this character's next turn already spent reacting. Shown as
		# "+N" because it is time owed on top of T, and it is the resource that decides
		# whether they can still defend at all — see Combatant.defense_debt.
		#
		# The active combatant is never shown a debt: their next_turn_at IS current_tick by
		# definition, so it always reads zero, which is also why the amber/red states below
		# can never fight the yellow "it's your turn" highlight.
		var debt: int = c.defense_debt() if c.has_method("defense_debt") else 0
		var text: String = c.character_name + "  T" + str(c.next_turn_at)
		if debt > 0:
			text += "  +" + str(debt)
		if not c.is_alive:
			label.self_modulate = Color(0.5, 0.5, 0.5, 1)
		elif c == current_combatant and not game_over:
			text = "> " + text + " <"
			label.self_modulate = Color(1, 1, 0.3, 1)
		elif c.is_overwhelmed():
			text += "!"
			label.self_modulate = Color(1, 0.36, 0.30, 1)
		elif c.is_defense_strained():
			label.self_modulate = Color(1, 0.72, 0.26, 1)
		else:
			label.self_modulate = Color(1, 1, 1, 1)

		label.text = text
		label.size_flags_horizontal = Control.SIZE_SHRINK_END
		order_list.add_child(label)


func charge_defense_cost(defender: Node) -> void:
	## Called when a defender successfully parries or dodges. Costs 1 time unit.
	##
	## The panel is repainted here, not just on turn changes: this is the only place debt
	## grows, and a debt readout that only refreshed between turns would hide the very moment
	## a defender is being ground down.
	if is_instance_valid(defender):
		defender.next_turn_at += 1
		_update_initiative_display()
		# This is the moment a defender can tip over into overwhelmed, mid-exchange and
		# nowhere near a turn boundary. Their guard zone has to drop with it, or the floor
		# keeps advertising a line they can no longer hold.
		if defender.has_method("_refresh_guard_zone"):
			defender._refresh_guard_zone()


func _update_turn_label(combatant: Node) -> void:
	if not turn_label:
		return
	if mode == Mode.EXPLORATION:
		# No tick to report, so the line says who is being driven and how to drive somebody
		# else — which is the only thing the player needs to be told about this mode.
		#
		# It names the portraits rather than the Tab key, because the portraits are the thing
		# that reliably works: Tab is also ui_focus_next, and whether the GUI eats it before
		# _unhandled_input sees it depends on whether a Control happens to hold focus.
		var switch_hint: String = "  ·  click a portrait to switch" \
			if party_members().size() > 1 else ""
		turn_label.text = combatant.character_name + "  ·  exploring" + switch_hint
		return
	turn_label.text = combatant.character_name + "'s Turn  (T" + str(current_tick) + ")"


func _spawn_ground_items() -> void:
	## Spawn pickups on the battlefield at combat start (data-driven from .tres).
	_spawn_item("res://resources/items/health_potion.tres", Vector3(-1, 0.2, 5))
	_spawn_item("res://resources/items/arrow_bundle.tres", Vector3(3, 0.2, -3))
	_spawn_item("res://resources/items/quiver.tres", Vector3(4, 0.2, -3))
	_spawn_item("res://resources/items/warhammer.tres", Vector3(1, 0.2, -5))
	_spawn_item("res://resources/items/dagger.tres", Vector3(-7, 0.2, -3))
	_spawn_item("res://resources/items/wooden_shield.tres", Vector3(-3, 0.2, -7))
	_spawn_item("res://resources/items/longbow.tres", Vector3(5, 0.2, 5))
	_spawn_item("res://resources/items/knight_helmet.tres", Vector3(-5, 0.2, -5))


func _spawn_item(path: String, at: Vector3) -> void:
	var item: ItemResource = load(path)
	if item:
		# An instance, so runtime changes (durability, pickup) don't mutate the cached .tres,
		# and so the item can be saved once picked up (ItemResource.make_instance).
		_spawn_gi(item.make_instance(), at)


func _spawn_gi(item: ItemResource, at: Vector3) -> void:
	GroundItemScript.drop(get_parent(), item, at)
