extends "res://scripts/combatant.gd"
## Enemy: AI-controlled combatant with multiple enemy types.
## Shared combat/movement/equipment logic lives in Combatant (combatant.gd).

enum EnemyType { GOBLIN, ARCHER, BOSS }

@export var enemy_type: int = EnemyType.GOBLIN

enum Action { MOVE, ATTACK, SHOVE, TRIP, RANGED, THROW }

## Distance (in tiles) an archer is happy to shoot from. At or beyond this it just looses an
## arrow; closer than this it spends the turn repositioning. Capped at the archer's actual
## ranged range.
##
## Tied to the penalty-free band deliberately: standing further back than this buys no safety
## the bow can pay for, since every band beyond it costs to-hit (Combatant.RANGE_FREE_TILES).
const ARCHER_PREFERRED_DIST := RANGE_FREE_TILES


# --- Not having noticed anybody yet ----------------------------------------
#
# An enemy has two lives. Before the alarm it is furniture with opinions: it walks a beat, or it
# loiters — stands about, goes and leans on the casks, takes the throne, finds a corner to lie
# down in — and every pulse it has another look round the room (see idle_step and
# notices_intruders, driven by CombatManager._idle_pulse). After the alarm it is what it always
# was: take_turn and the AI below, untouched.
#
# The two never overlap. `alerted` is set once, by CombatManager.raise_alarm, for every enemy
# at once: one goblin seeing you is the whole room knowing, which is what a shout is for and
# is far easier to reason about than per-enemy awareness spreading through a crowd.

enum IdleRole {
	SENTRY,    ## Loiters. Kept as the scene default; identical to WANDERER since _idle_loiter.
	WANDERER,  ## Loiters: stands about, visits the furniture, lies down, drifts a few squares.
	PATROL,    ## Walks patrol_route end to end and back again.
}

## Whether this one walks a beat or loiters. Whatever the scene says is overwritten at the start
## of exploration by CombatManager._cast_idle_roles, which decides who patrols by rolling for it
## — so this is the fallback for a scene with no manager in it rather than the setting.
@export var idle_role: int = IdleRole.SENTRY

## Squares a PATROL walks, in order, then back along the same line. Only x and z are read.
##
## Authored per enemy in the scene rather than generated, because a beat that matters is level
## design: it decides what the player can watch, time and slip behind. A patroller with none set
## borrows the room's own ring (RoomBuilder.patrol_ring), which is what makes it possible to
## decide WHO patrols at runtime without every candidate needing a route — see _idle_patrol.
@export var patrol_route: Array[Vector3] = []

## How far this one can see a hero, in tiles. Sight still needs an unobstructed line, so a shut
## door beats any amount of it (Combatant._has_line_of_sight).
@export var sight_tiles: int = 10

## How far it can HEAR one, in tiles. Shorter than sight, and no clear line needed — that is
## the whole point of it.
##
## Sight on its own let the party get within a couple of squares before anybody reacted, and
## the reason is the room rather than the number: the eight pillars and the stone vessel in the
## middle of the chamber are all LOS blockers at eye height, so a hero crossing it is out of
## sight far more of the time than the open floor makes it look. Hearing is the floor under
## that — a goblin does not need to see you to know somebody is moving about a stone room.
@export var hear_tiles: int = 5

## How far a loiterer drifts from where it started, when it is drifting rather than going
## somewhere in particular. Small on purpose: a room full of drifters should still read as a room
## full of drifters and not slowly empty into the corridor. Going to the casks or the throne
## ignores it — those are somewhere it MEANT to be, and the room says where they are.
@export var wander_tiles: int = 3

## Chance per pulse that an enemy standing about looks another way. Cheap, so it can be high:
## a room where nobody ever turns their head is a waxworks.
const SENTRY_LOOK_CHANCE := 0.25

## What an idle enemy decides to do when it has finished whatever it was doing, as weights —
## they are rolled against in this order and want to sum to 1.
##
## Weighted towards standing about on purpose. The room should read as a guardroom between
## rounds: mostly bodies at rest, with one or two of them up and doing something at any moment.
## Every one of them ambling all the time is as mechanical as none of them moving.
const IDLE_STAY_WEIGHT := 0.40     ## stand where you are a while longer
const IDLE_VISIT_WEIGHT := 0.30    ## go and stand at something: the throne, the casks, the crates
const IDLE_REST_WEIGHT := 0.10     ## get off its feet somewhere out of the way — _idle_bolthole
## Whatever is left over is a drift to a random square nearby — see _idle_loiter.

## Pulses an idle enemy stays put. Rolled per stop, so two enemies who happen to stop together
## do not then move together forever after.
##
## Three lengths, because they are three different things. Standing about is a pause. Sitting is
## settling in. SLEEPING is the longest by a distance: a goblin that lies down for a few seconds
## and bounces straight back up has not had a nap, it has had a fall — and the whole value of one
## asleep in a corner is that the party can come across it like that.
const IDLE_STAND_PULSES := Vector2i(2, 6)
const IDLE_SIT_PULSES := Vector2i(8, 20)
const IDLE_SLEEP_PULSES := Vector2i(25, 55)
## Tiles of an idle move taken per pulse. A few at a time rather than the whole route, so a
## patrol ambles and the noticing check gets a look in between.
const IDLE_STEP_TILES := 2
## Attempts at finding somewhere to drift to before giving up for this pulse.
const WANDER_TRIES := 8
## Seconds a sentry takes to turn its head.
const SENTRY_TURN_TIME := 0.5
## Seconds to climb onto the throne, or down off it. Slid rather than snapped so it reads as
## getting into a chair; comfortably inside one idle pulse either way.
const PERCH_CLIMB_TIME := 0.45

## How far proud of a seat a sitter's hips are left, in world units.
##
## Hips exactly ON the surface is the geometrically right answer and reads as slightly sunk,
## because the underside of a low-poly torso is a flat face and putting it level with the seat
## makes the two coplanar — the same reason the hand-built helmet floated its shell a fraction
## clear of the skull (tools/build_soldier_helmet.gd's shell_offset).
##
## The one number here picked by eye rather than measured, and a taste dial: big enough to read
## as sitting ON the throne, small enough not to read as hovering over it.
const SEAT_CLEARANCE := 0.06

## Whether the alarm has gone up. False means this enemy has never seen a hero and is running
## the idle behaviour above; CombatManager.raise_alarm is the only thing that sets it.
var alerted := false

## Where this one was standing when the level started, and so what a drift counts as home.
var _idle_home := Vector3.ZERO
## The square this one has decided to be at, INF for nowhere in particular, and what it means to
## do when it gets there. See _idle_loiter.
var _idle_goal := Vector3.INF
var _idle_face := Vector3.INF
## What to do on arriving: "" to stand about, "sit" to take the chair, "lie" to lie down.
var _idle_settle := ""
## Where to put ourselves on arrival, for a spot that is climbed ONTO rather than stood beside —
## the throne. INF for everywhere else. See _idle_take_perch.
var _idle_perch := Vector3.INF
## Set while sitting up on one, so getting up knows to climb down again.
var _perched := false
var _perch_tween: Tween = null
## How far below the body's origin this rig's hips end up once it is sitting, measured off the
## posed skeleton the first time it sits. Negative until then. See _seated_hip_drop.
var _hip_drop := -1.0
## Pulses left to stay put before deciding again. Counted down by idle_step, and while it is
## running this enemy does nothing at all — which is most of the time, and the point.
var _idle_hold := 0
## Index into patrol_route, and which way along it we are walking (+1 / -1).
var _patrol_at := 0
var _patrol_dir := 1
## True while an idle amble is in flight, so _on_move_complete knows the arrival is not a turn
## ending. See there.
var _idling := false
## The head-turn currently animating, so it can be dropped when something else wants to decide
## which way this one is facing — see _idle_stop_looking.
var _look_tween: Tween = null


func _pre_setup() -> void:
	# main.tscn does not store is_player_controlled on enemy nodes; enforce it.
	# All numeric stats (including move_speed/move_range) come from the assigned
	# `stats` resource, applied by the base before this hook runs.
	is_player_controlled = false
	# Read before anything has had a chance to move us, which is the only time it is the
	# starting post rather than wherever the last idle pulse left us.
	_idle_home = _snap_to_grid(position)
	_apply_enemy_visual()


func notices_intruders() -> bool:
	## Whether this enemy can see a hero from where it stands. The trigger for the whole alarm,
	## asked once per pulse by CombatManager.
	##
	## Two ways to notice somebody, and a hero only has to trip one.
	##
	## SEEING is range plus an unobstructed line, cheap test first so a room full of goblins is
	## not casting rays at a party three walls away. The line is the same _has_line_of_sight the
	## archer aims with, so a goblin notices you exactly where an archer could shoot you.
	##
	## HEARING is range plus a WALKABLE ROUTE, and the route is what makes it honest. A plain
	## distance check would carry sound straight through the masonry, and through the shut door
	## the party is meant to be safe behind. Asking _find_path instead — bounded to hear_tiles,
	## and with doors_openable left false so a shut one is a wall — means noise travels the way
	## a person would: out through the doorway, not through the wall beside it. So the party in
	## the room is unheard however close they stand to the door, and the moment it opens they
	## are not.
	if alerted or not is_alive:
		return false
	var here: Vector3 = _snap_to_grid(position)
	var see: float = sight_tiles * GRID_SIZE
	var hear: float = hear_tiles * GRID_SIZE
	for hero in _player_candidates():
		var there: Vector3 = _snap_to_grid((hero as Node3D).position)
		var gap: float = here.distance_to(there)
		# Stealth is tested BEFORE the route, and only against hearing: it is cheaper than a
		# path search, and it is the answer to noise and to nothing else. A hero who creeps
		# into the open is still standing in the open — see the sight test below, which no
		# roll touches.
		if gap <= hear and not hero.is_unheard_by(self) \
				and _find_path(here, there, hear_tiles).size() > 1:
			return true
		if gap <= see and _has_line_of_sight(hero):
			return true
	return false


func idle_step() -> void:
	## One pulse of doing nothing in particular. Never ends a turn and never charges anything —
	## there is no clock in exploration for it to spend.
	##
	## Three things can be true of an idle enemy, and they are checked in this order: it is
	## waiting (standing about, or lying down, for a rolled number of pulses); it is on its way
	## somewhere it has decided to be; or it is at a loose end, and picks something to do.
	if alerted or not is_alive or is_moving:
		return
	if _idle_hold > 0:
		_idle_hold -= 1
		if _idle_hold == 0:
			_idle_rouse()
		elif not is_prone and _held_pose == "":
			_idle_look_around()
		return
	if idle_role == IdleRole.PATROL:
		_idle_patrol()
		return
	if _idle_goal != Vector3.INF:
		_idle_continue()
		return
	_idle_loiter()


func _idle_rouse() -> void:
	## Done waiting: get up off the floor, or down off the throne, before deciding anything else.
	##
	## Its own pulse, rather than the first frame of walking away: standing up takes a moment,
	## and the next decision is made on the pulse after this one — which is also the room a
	## climb down off the throne needs to finish in.
	lie_down_quietly(false)
	_idle_leave_perch(false)
	release_pose()


func _idle_look_around() -> void:
	## Every so often, look somewhere else.
	##
	## Cosmetic today: _has_line_of_sight casts in every direction, so which way an enemy faces
	## does not yet change what it notices. It is here because a motionless guard reads as
	## scenery, and because the day facing DOES gate sight this is already the thing that would
	## have to move.
	##
	## Turns the MODEL and not the body, which is the whole of the bug this used to be. Facing
	## lives on the CharacterModel everywhere else — _face_target, _face_point, and the walk
	## rotation in Combatant._physics_process all set model.rotation.y from a direction in the
	## PARENT's space, which is only the direction it looks like if the body under it is square
	## to the world. Turning the body left the model's angle being measured from a rotated
	## frame, so a goblin that had looked over its shoulder then walked crabwise ever after.
	## It only ever showed on the ones that move: a sentry that never left its post looked fine
	## with a rotated body, and a patroller never stands still long enough to look round.
	if randf() > SENTRY_LOOK_CHANCE:
		return
	var model := get_node_or_null("CharacterModel") as Node3D
	if model == null:
		return
	var turn: float = [90.0, -90.0, 180.0][randi() % 3]
	_idle_stop_looking()
	_look_tween = create_tween()
	_look_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_look_tween.tween_property(model, "rotation:y",
		model.rotation.y + deg_to_rad(turn), SENTRY_TURN_TIME)


func _idle_stop_looking() -> void:
	## Drop a head-turn in progress. Called before walking off and before facing something on
	## purpose, because both set the same angle the tween is animating and two things writing
	## one rotation is a twitch.
	if _look_tween and _look_tween.is_valid():
		_look_tween.kill()
	_look_tween = null


func _idle_loiter() -> void:
	## Pick something to do with a quiet minute: stay put, go and stand at something, find a
	## corner to lie down in, or drift a few squares.
	##
	## Rolled fresh every time rather than cycled, so no two enemies fall into step and none of
	## them has a routine the player can learn. The weights are in the constants above; a choice
	## the room cannot offer (no throne, nowhere free to lie down) falls through to the next one
	## rather than wasting the pulse.
	var roll: float = randf()
	if roll < IDLE_STAY_WEIGHT:
		_idle_wait(IDLE_STAND_PULSES)
		return
	roll -= IDLE_STAY_WEIGHT
	if roll < IDLE_VISIT_WEIGHT and _idle_go_to_spot(_idle_haunt()):
		return
	roll -= IDLE_VISIT_WEIGHT
	if roll < IDLE_REST_WEIGHT and _idle_go_to_spot(_idle_bolthole(), true):
		return
	var tile: Vector3 = _random_tile_near(_idle_home, wander_tiles)
	if tile != Vector3.INF:
		_idle_set_goal(tile, Vector3.INF)
	else:
		# Boxed in, or every square it fancied was taken. Stand about and ask again later
		# rather than spending every pulse from here on re-asking the same question.
		_idle_wait(IDLE_STAND_PULSES)


func _idle_haunt() -> String:
	## Which of the room's spots this one would take itself to, given the choice.
	##
	## The boss keeps to his throne, because that is what a throne is for, and because a warlord
	## found pacing about among the casks is not a warlord. Everybody else has the run of the
	## stores.
	return "seat" if enemy_type == EnemyType.BOSS else "stores"


func _idle_bolthole() -> String:
	## Where this one goes to get off its feet. A goblin finds a corner and lies down in it; the
	## boss has a chair for that, and a warlord asleep on the flagstones in the corner of his
	## own hall is not the picture. What arriving there LOOKS like is decided by the spot and
	## not by this — see _idle_arrive.
	return "seat" if enemy_type == EnemyType.BOSS else "corner"


func _idle_go_to_spot(kind: String, stay: bool = false) -> bool:
	## Set off for one of the room's idle spots of `kind`. False when the room offers none, or
	## none that can be reached, so the caller can try something else on the same pulse.
	##
	## `stay` asks for a long stop rather than a look round. What that stop looks like is the
	## SPOT's business: a chair is for sitting in whether you meant to stop long or not, and a
	## corner is only worth walking to if you meant to lie down in it.
	var spots: Array = _room_idle_spots(kind)
	if spots.is_empty():
		return false
	# Shuffled rather than taken in order, so three goblins with the same idea do not all queue
	# at the same cask.
	spots = spots.duplicate()
	spots.shuffle()
	var settle: String = "sit" if kind == "seat" else ("lie" if stay else "")
	var here: Vector3 = _snap_to_grid(position)
	for spot in spots:
		var at: Vector3 = _snap_to_grid(Vector3(spot["at"].x, position.y, spot["at"].z))
		if at.distance_to(here) < 0.5:
			# Already standing on it: settle in, rather than walking a lap to arrive where we
			# already are.
			_idle_arrive(spot["face"], settle, spot["perch"])
			return true
		if _is_obstacle_at(at) or _is_tile_occupied_by_others(at, self):
			continue
		if _find_path(here, at).size() <= 1:
			continue
		_idle_set_goal(at, spot["face"], settle, spot["perch"])
		return true
	return false


func _room_idle_spots(kind: String) -> Array:
	## The room's own list, or empty when the scene has no DungeonRoom in it — asked the same way
	## Combatant._is_in_arena asks it about the floor, and for the same reason: where the
	## furniture stands is the room's business and not ours.
	var room := get_parent().get_node_or_null("DungeonRoom") if get_parent() else null
	if room == null or not room.has_method("idle_spots"):
		return []
	return room.idle_spots(kind)


func _idle_set_goal(tile: Vector3, face: Vector3, settle: String = "",
		perch: Vector3 = Vector3.INF) -> void:
	_idle_goal = tile
	_idle_face = face
	_idle_settle = settle
	_idle_perch = perch
	_idle_continue()


func _idle_continue() -> void:
	## Another few steps towards wherever we decided to be.
	##
	## Arriving ends the errand. Being unable to get any further ABANDONS it, which is the
	## important half: a goal that has become unreachable — a door shut behind us, somebody
	## standing on the square — must not leave this enemy walking into a wall for the rest of
	## the level.
	var here: Vector3 = _snap_to_grid(position)
	if here.distance_to(_idle_goal) < 0.5:
		_idle_arrive(_idle_face, _idle_settle, _idle_perch)
		return
	if not _idle_walk_to(_idle_goal):
		_idle_clear_goal()
		_idle_wait(IDLE_STAND_PULSES)


func _idle_arrive(face: Vector3, settle: String, perch: Vector3 = Vector3.INF) -> void:
	## Got there: turn to face whatever we came for, then stay a while. Sitting and sleeping are
	## both long stops — the point of them is being caught in one.
	var climb: Vector3 = perch
	_idle_clear_goal()
	if face != Vector3.INF:
		_face_point(face)
	match settle:
		"sit":
			hold_pose("sit")
			_idle_take_perch(climb)
			_idle_wait(IDLE_SIT_PULSES)
		"lie":
			lie_down_quietly(true)
			_idle_wait(IDLE_SLEEP_PULSES)
		_:
			_idle_wait(IDLE_STAND_PULSES)


func _idle_take_perch(perch: Vector3) -> void:
	## Climb onto the thing we came to sit on.
	##
	## The throne is 1.9 units wide astride the line x = 0, so the chair has no grid square of
	## its own: the two squares it covers are half each, and the middle of the seat is ON the
	## line between them. Sitting on either square would be sitting on an arm of the chair, and
	## a square cannot be added between two squares.
	##
	## So the body goes to the seat itself, OFF the grid centre, and is left to snap: every rule
	## in the game asks _snap_to_grid which square a position is in, and from the middle of the
	## seat the answer is one of the throne's own two — squares already reserved as obstacles
	## (RoomBuilder._reserve_cell), so nothing will try to walk into the chair while he is in it,
	## and nothing needs telling that he is there. Walking OFF is unaffected: _find_path never
	## asks whether the square it starts on is passable, only the ones it steps to.
	##
	## Body and not just the model, so the collider comes too — the boss on his throne has to be
	## clickable where he is DRAWN, which is the same reason doors grew a picker.
	if perch == Vector3.INF:
		return
	_idle_stop_perching()
	_perched = true
	var to := Vector3(perch.x, perch.y + _seated_hip_drop() + SEAT_CLEARANCE, perch.z)
	_perch_tween = create_tween()
	_perch_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_perch_tween.tween_property(self, "position", to, PERCH_CLIMB_TIME)


func _seated_hip_drop() -> float:
	## How far below the body's origin to find the hips of a SEATED character — which is what
	## has to land on a seat, and so what decides where the body goes.
	##
	## Not the feet, which was the bug: standing bodies are placed by the floor under their soles
	## (Combatant._ground_y), and placing a seated one the same way put its soles on the seat and
	## left it hovering a hand's width over the chair with its legs hanging through the seat.
	## This rig's sit clip lowers the whole body by 0.3 and swings the legs out from the hip
	## rather than folding anything, so the hips are the only contact there is.
	##
	## Measured off the posed skeleton rather than written down, because it is a fact about the
	## animation and the rig's proportions. The legs hang from the hips, so on these rigs the
	## leg bones ARE the hips; a rig that names them something else gets the old feet-on-the-seat
	## placement, which is wrong by a few centimetres rather than broken.
	##
	## Measured once, on the first sit, and the pose it leaves applied is the one being taken
	## anyway. Cached because it cannot change: nothing about the clip or the rig moves.
	if _hip_drop >= 0.0:
		return _hip_drop
	_hip_drop = _ground_y()
	var model := get_node_or_null("CharacterModel") as Node3D
	if model == null:
		return _hip_drop
	var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var ap := _ensure_anim_player()
	if skel == null or ap == null or not ap.has_animation("sit"):
		return _hip_drop
	ap.play("sit")
	# Applied on the spot, not on the next frame: the answer is wanted now, to place the body
	# this same call.
	ap.seek(0.0, true)
	skel.force_update_all_bone_transforms()
	var total := 0.0
	var found := 0
	for i in range(skel.get_bone_count()):
		if String(skel.get_bone_name(i)).to_lower().find("leg") < 0:
			continue
		total += position.y - (skel.global_transform * skel.get_bone_global_pose(i).origin).y
		found += 1
	if found > 0:
		_hip_drop = total / float(found)
	return _hip_drop


func _idle_leave_perch(instant: bool) -> void:
	## Get down off it, back to the middle of the square the seat snaps to and back to the floor.
	##
	## `instant` for the alarm, which is a hard cut: a boss ambling down off his chair while the
	## room is already fighting looks like the fight is waiting for him. Sliding otherwise,
	## because _idle_rouse gives it a whole pulse before the next decision.
	if not _perched:
		return
	_idle_stop_perching()
	_perched = false
	var down: Vector3 = _snap_to_grid(position)
	down.y = _ground_y()
	if instant:
		position = down
		return
	_perch_tween = create_tween()
	_perch_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_perch_tween.tween_property(self, "position", down, PERCH_CLIMB_TIME)


func _idle_stop_perching() -> void:
	if _perch_tween and _perch_tween.is_valid():
		_perch_tween.kill()
	_perch_tween = null


func _idle_clear_goal() -> void:
	_idle_goal = Vector3.INF
	_idle_face = Vector3.INF
	_idle_settle = ""
	_idle_perch = Vector3.INF


func _idle_wait(pulses: Vector2i) -> void:
	_idle_hold = randi_range(pulses.x, pulses.y)


func _face_point(at: Vector3) -> void:
	## Turn to look at a PLACE rather than at a body: _face_target wants a node, and a cask is
	## a position in a list by the time it reaches here.
	var model := get_node_or_null("CharacterModel") as Node3D
	if model == null:
		return
	_idle_stop_looking()
	var dir: Vector3 = at - position
	dir.y = 0.0
	if dir.length() > 0.01:
		model.rotation.y = atan2(dir.x, dir.z)


func _idle_patrol() -> void:
	## Walk the beat. Arriving at a waypoint advances to the next one on the same pulse, so a
	## patrol never spends a beat standing on a corner deciding.
	if patrol_route.is_empty():
		# Nothing authored for this one. It gets the room's own beat rather than standing to
		# attention forever, which is what lets the patrol be CAST at runtime — see
		# cast_idle_role — instead of every possible patroller needing a route in the scene.
		var ring: Array = _room_patrol_ring()
		if ring.is_empty():
			# No room to ask, so there is no beat to walk. Loiter instead of freezing.
			_idle_loiter()
			return
		patrol_route.assign(ring)
		_patrol_at = randi() % patrol_route.size()
		_patrol_dir = 1 if randf() < 0.5 else -1
	var goal: Vector3 = _patrol_goal()
	if _snap_to_grid(position).distance_to(goal) < 0.5:
		_advance_patrol()
		goal = _patrol_goal()
	if not _idle_walk_to(goal):
		# Blocked on the beat — most often another patroller on the same square. Skip to the
		# next waypoint rather than shoving at it every pulse for the rest of the level.
		_advance_patrol()


func _room_patrol_ring() -> Array:
	var room := get_parent().get_node_or_null("DungeonRoom") if get_parent() else null
	if room == null or not room.has_method("patrol_ring"):
		return []
	return room.patrol_ring()


func keeps_to_its_post() -> bool:
	## Whether this one is exempt from the patrol draw. The boss is: see
	## CombatManager._cast_idle_roles, and _idle_haunt for where he goes instead.
	return enemy_type == EnemyType.BOSS


func cast_idle_role(patrols: bool) -> void:
	## Told, at the start of exploration, whether this one walks a beat or loiters. See
	## CombatManager._cast_idle_roles for who decides and why it is decided there.
	##
	## A scene-authored patrol_route is left alone either way: the route is level design even
	## when the roll says this particular goblin is not the one walking it today.
	idle_role = IdleRole.PATROL if patrols else IdleRole.WANDERER
	_idle_clear_goal()
	_idle_hold = 0
	# Nobody is on the throne when roles are first cast, but being re-cast is not a reason to be
	# left up there, and a body sitting a storey off its own grid square is not a state to start
	# anything from.
	_idle_leave_perch(true)
	release_pose()


func _patrol_goal() -> Vector3:
	## The current waypoint, on OUR y so the distance tests above compare squares and not
	## heights — patrol_route is authored as tiles and its y is not meant to mean anything.
	var wp: Vector3 = patrol_route[clampi(_patrol_at, 0, patrol_route.size() - 1)]
	return _snap_to_grid(Vector3(wp.x, position.y, wp.z))


func _advance_patrol() -> void:
	## Step to the next waypoint, turning round at either end.
	##
	## It bounces rather than wrapping, and that is the point of a beat: a route that looped
	## would need its two ends to join up, and a hand-authored line of squares almost never
	## does. Turning round means any list of waypoints is a valid patrol.
	_patrol_at += _patrol_dir
	if _patrol_at >= patrol_route.size():
		_patrol_at = maxi(patrol_route.size() - 2, 0)
		_patrol_dir = -1
	elif _patrol_at < 0:
		_patrol_at = mini(1, patrol_route.size() - 1)
		_patrol_dir = 1


func _idle_walk_to(tile: Vector3) -> bool:
	## Amble up to IDLE_STEP_TILES along the route to `tile`. False when no step could be taken
	## at all, which is the caller's cue to give up on wherever it was going — see _idle_continue.
	##
	## The same _find_path/_follow_path the combat AI walks, so an idle goblin rounds pillars
	## and stops at shut doors exactly as a charging one does. What it does NOT do is open them:
	## _try_open_door_toward is a combat decision about reaching somebody, and a goblin with no
	## reason to think anybody is there has no reason to work a latch.
	var path: Array = _find_path(_snap_to_grid(position), tile)
	if path.size() <= 1:
		return false
	var steps: int = mini(IDLE_STEP_TILES, path.size() - 1)
	while steps >= 1 and _is_tile_occupied_by_others(path[steps], self):
		steps -= 1
	if steps < 1:
		return false
	# The walk rotation in _physics_process is about to take over this model's angle; a head-turn
	# still running would be fighting it for the first half-second of the stroll.
	_idle_stop_looking()
	_idling = true
	_follow_path(path.slice(0, steps + 1))
	return true


func _random_tile_near(home: Vector3, radius: int) -> Vector3:
	## A free, actually-reachable square within `radius` of `home`, or Vector3.INF.
	##
	## Reachability is checked with _find_path rather than trusted from the distance, because
	## "three squares away" and "three squares' walk away" are different numbers the moment a
	## wall is involved — and a wanderer that picked a square through the masonry would stand
	## still forever, looking broken rather than idle.
	var here: Vector3 = _snap_to_grid(position)
	for _try in range(WANDER_TRIES):
		var tile: Vector3 = _snap_to_grid(home + Vector3(
			randi_range(-radius, radius) * GRID_SIZE, 0.0,
			randi_range(-radius, radius) * GRID_SIZE))
		if tile.distance_to(here) < 0.5:
			continue
		if not _is_in_arena(tile) or _is_obstacle_at(tile):
			continue
		if _is_tile_occupied_by_others(tile, self):
			continue
		if _find_path(here, tile).size() > 1:
			return tile
	return Vector3.INF


func _apply_enemy_visual() -> void:
	## Scale the CharacterModel and old Mesh based on enemy_type
	var model_node: Node3D = get_node_or_null("CharacterModel")
	var old_mesh: MeshInstance3D = get_node_or_null("Mesh")

	match enemy_type:
		EnemyType.GOBLIN:
			if model_node: model_node.scale = Vector3(1, 1, 1)
			if old_mesh: old_mesh.scale = Vector3(1, 1, 1)
		EnemyType.ARCHER:
			if model_node: model_node.scale = Vector3(0.85, 0.9, 0.85)
			if old_mesh: old_mesh.scale = Vector3(0.85, 0.9, 0.85)
		EnemyType.BOSS:
			if model_node: model_node.scale = Vector3(1.3, 1.25, 1.3)
			if old_mesh: old_mesh.scale = Vector3(1.3, 1.25, 1.3)


func enable_turn() -> void:
	if not is_alive:
		return
	_stand_up_if_prone()


func disable_turn() -> void:
	## Nothing to stand down as such — an enemy has no cursor or action bar to take away — but a
	## held idle pose has to go, and this is called on every combatant the moment the alarm turns
	## exploration into a fight (CombatManager._begin_combat). A boss who stayed sitting through
	## the fight would be a boss fighting from an armchair.
	##
	## And off the throne with him, instantly: while he is up there his body is off its grid
	## centre and a storey up, which is fine for scenery and no way to start a turn.
	_idle_leave_perch(true)
	release_pose()


func take_turn() -> void:
	if not is_alive:
		end_my_turn(0)
		return

	match enemy_type:
		EnemyType.GOBLIN:
			_take_turn_goblin()
		EnemyType.ARCHER:
			_take_turn_archer()
		EnemyType.BOSS:
			_take_turn_boss()
		_:
			_take_turn_goblin()


func _take_turn_goblin() -> void:
	## Original goblin AI: move toward nearest, weighted random adjacent — unless a guardian
	## has it pinned, in which case that is who it fights (see _pinning_guard).
	var player := _pinning_guard()
	if player == null:
		player = _find_nearest_reachable_player()
	if not player or not player.is_alive:
		end_my_turn(0)
		return

	if _is_adjacent(player.position):
		_do_adjacent_action(player)
		await get_tree().create_timer(0.3).timeout
		end_my_turn(_pending_cost)
		return

	if is_prone:
		end_my_turn(1)
		return

	# A shut door in the way is worth a turn: open it, and come through it next turn.
	if _try_open_door_toward(player):
		end_my_turn(_pending_cost)
		return

	# Move toward the nearest player, avoiding occupied tiles
	_begin_move_toward(player)


func _take_turn_archer() -> void:
	## Archer AI: hold the tile that is FURTHEST from the heroes while still giving a clear
	## shot, and fire from there. It only ever walks a real BFS route, so it rounds pillars
	## and walls instead of sliding through them, and it only draws a blade when out of arrows.
	var player := _find_nearest_player()
	if not player or not player.is_alive:
		end_my_turn(0)
		return

	if is_prone:
		end_my_turn(1)
		return

	# Pinned in a guardian's zone. The reposition search below would pick a firing tile it
	# cannot legally reach — the guard clip truncates the route to nothing — and the archer
	# would spend the turn shuffling on the spot. Fight what is in front of it instead: point
	# blank if there are arrows left, steel if not.
	var pin := _pinning_guard()
	if pin != null:
		if ammo > 0:
			await _fire_arrow(pin)
		else:
			_action_used = Action.ATTACK
			_do_melee_attack(pin)
			_pending_cost = attack_cost
			await get_tree().create_timer(0.3).timeout
			end_my_turn(_pending_cost)
		return

	# Out of ammo: kiting is pointless (arrows never come back), so close in and melee.
	# This also walks a stranded archer back toward the fight.
	if ammo <= 0:
		if _is_adjacent(player.position):
			_action_used = Action.ATTACK
			_do_melee_attack(player)
			_pending_cost = attack_cost
			await get_tree().create_timer(0.3).timeout
			end_my_turn(_pending_cost)
			return
		_begin_move_toward(player)
		return

	# Effective max range (an equipped bow may extend the base stat).
	var max_range: int = get_ranged_range()
	var preferred: float = min(ARCHER_PREFERRED_DIST, max_range) * GRID_SIZE

	var cur: Vector3 = _snap_to_grid(position)
	var can_fire_now: bool = _can_fire_from(cur, player, max_range)
	var cur_dist: float = _min_player_dist(cur)

	# Already standing far enough back with a clear line: just shoot. This is what stops
	# the "maximise distance" search below from backing up forever and never firing.
	if can_fire_now and cur_dist >= preferred:
		await _fire_arrow(player)
		return

	# Too close (or no shot from here): spend the turn walking to the best firing tile
	# we can actually reach — furthest from the nearest hero, still inside bow range,
	# still with line of sight.
	var path: Array = _best_firing_path(player, max_range, cur_dist)
	if not path.is_empty():
		# Backing off to a firing tile, not closing on anyone — so a guardian met on the way
		# has genuinely turned us aside. See _move_intent.
		_move_intent = null
		_follow_path(path)
		_action_used = Action.MOVE
		_pending_cost = get_move_cost()
		return

	# Nothing reachable improves on where we stand. Cornered archers still loose a
	# point-blank arrow — it beats their dismal melee.
	if can_fire_now:
		await _fire_arrow(player)
		return

	# No shot from anywhere within a turn's walk (out of range, or fully blocked):
	# close the gap to set one up.
	_begin_move_toward(player)


func _can_fire_from(tile: Vector3, target: Node, max_range: int) -> bool:
	## Could we put an arrow into `target` while standing on `tile`? Same two conditions the
	## shot itself needs: inside the bow's range, and a clear line to the target.
	var dist: float = abs(target.position.x - tile.x) + abs(target.position.z - tile.z)
	if dist > max_range * GRID_SIZE:
		return false
	return _has_line_of_sight_from(tile, target)


func _best_firing_path(target: Node, max_range: int, cur_dist: float) -> Array:
	## Of every tile we could walk to this turn, the best place to shoot from: ACCURACY first,
	## then distance from the heroes. Returns its BFS path, or [] when standing still is
	## already as good. Ties go to the shorter walk.
	##
	## Accuracy has to lead now that the bow outranges its own useful range. Scoring purely on
	## distance — "as far away as possible, but within range" — would kite the archer out to
	## 15 tiles and a -6 to hit, where it is safe and completely useless. Range penalties come
	## in bands, so within a band it still backs off as far as it can for free.
	##
	## Distance is measured to the nearest hero (not just our target) so the archer never
	## backs away from one and straight into another.
	var best_path: Array = []
	var best_dist: float = cur_dist
	var best_penalty: int = _range_penalty(target, max_range, _snap_to_grid(position))
	var best_steps: int = 0
	for path in _reachable_paths(get_move_range()):
		var tile: Vector3 = path[path.size() - 1]
		if not _can_fire_from(tile, target, max_range):
			continue
		var d: float = _min_player_dist(tile)
		var pen: int = _range_penalty(target, max_range, tile)
		var steps: int = path.size() - 1
		if pen < best_penalty:
			best_penalty = pen
			best_dist = d
			best_path = path
			best_steps = steps
		elif pen > best_penalty:
			continue
		elif d > best_dist + 0.01:
			best_dist = d
			best_path = path
			best_steps = steps
		elif not best_path.is_empty() and absf(d - best_dist) < 0.01 and steps < best_steps:
			best_path = path
			best_steps = steps
	return best_path


func _reachable_paths(max_steps: int) -> Array:
	## Every tile we could end this turn on, each as its BFS path from where we stand.
	## Uses the same rules as Combatant._find_path — obstacles, wall edges, other units and
	## no diagonal corner-cutting — just flooded outward instead of aimed at one goal.
	var start: Vector3 = _snap_to_grid(position)
	var out: Array = []
	var queue: Array = [[start]]
	var visited: Dictionary = {}
	visited[_tile_key(start)] = true

	while not queue.is_empty():
		var path: Array = queue.pop_front()
		var cur: Vector3 = path[path.size() - 1]
		if path.size() - 1 >= max_steps:
			continue
		for d in GRID_DIRS:
			var nxt: Vector3 = _snap_to_grid(cur + d)
			var k: String = _tile_key(nxt)
			if visited.has(k):
				continue
			visited[k] = true
			if not _is_in_arena(nxt) or _is_tile_occupied_by_others(nxt, self):
				continue
			if _step_blocked_by_wall(cur, nxt) or _is_corner_blocked(cur, nxt):
				continue
			var new_path: Array = path.duplicate()
			new_path.append(nxt)
			out.append(new_path)
			queue.append(new_path)
	return out


func _begin_move_toward(target: Node) -> void:
	## _move_toward queues the route first, so get_move_cost() can price it by distance.
	# Recorded before the route is built: _clip_at_guard needs to know whether a guardian we
	# end up next to is who we were actually coming for.
	_move_intent = target
	# The one place the AI decides to go and get someone, which is exactly what a battle cry
	# is for. _charge_cry fires only the first time in a fight, so this is the moment the
	# enemy comes at you rather than a bellow on every turn it spends walking.
	_charge_cry()
	_move_toward(target)
	_action_used = Action.MOVE
	_pending_cost = get_move_cost()

	# There used to be an unconditional `is_moving = true` here. It was redundant — _follow_path
	# sets the flag whenever it queues a real route — and actively harmful: with nothing queued
	# it left the unit drifting toward a stale target_position from the previous move, which is
	# what used to (accidentally) end the turn of an enemy that was fully boxed in.
	#
	# Three outcomes now, and each has to end the turn exactly once:
	#   route queued   -> is_moving true; _physics_process reaches _on_move_complete.
	#   pinned in a zone -> _follow_path billed the floor and deferred the hook itself.
	#   no route at all -> nothing queued and no hook pending, so end it here.
	#
	# _move_tiles separates the last two: _move_toward zeroes it before pathing and only
	# _follow_path raises it, so 0 means we never got as far as queueing anything. Without this
	# branch a trapped enemy would stop the clock for good.
	if not is_moving and _move_tiles == 0:
		end_my_turn(_pending_cost)


func _fire_arrow(player: Node) -> void:
	_face_target(player)
	_action_used = Action.RANGED
	ammo -= 1
	_update_health_bar()
	_play_attack_anim("holding-both-shoot")
	_show_action_text("Arrow fired!")
	_pending_cost = ranged_cost
	# The flight IS the beat between loosing and the turn passing, so the shot is awaited here
	# and the old flat 0.3s pause is gone. _loose_arrow_at rolls the hit on impact and leaves
	# the blood, so nothing about the shot resolves before the arrow gets there.
	await _loose_arrow_at(player)
	end_my_turn(_pending_cost)


func _take_turn_boss() -> void:
	## Boss AI: target weakest player, shove to separate, attack otherwise. A guardian's zone
	## overrides the pick — the boss is the one enemy that deliberately dives the weakest hero,
	## so it is also the one interception has real work to do against.
	var target := _pinning_guard()
	if target == null:
		target = _find_weakest_reachable_player()
	if not target or not target.is_alive:
		end_my_turn(0)
		return

	if is_prone:
		end_my_turn(1)
		return

	# Same as the goblins: a door is a turn's work, not a dead end. Checked before the
	# adjacency test below cannot fire — a door between us and the target means we are not
	# adjacent to the target anyway.
	if not _is_adjacent(target.position) and _try_open_door_toward(target):
		end_my_turn(_pending_cost)
		return

	# If adjacent: smart action selection
	if _is_adjacent(target.position):
		_face_target(target)
		var roll := randi_range(1, 100)
		var has_ally_adjacent := _has_ally_adjacent_to(target)
		if has_ally_adjacent and roll <= 35:
			# Shove to separate from allies
			_action_used = Action.SHOVE
			_play_attack_anim("attack-kick-right")
			_try_shove(target)
			_pending_cost = shove_cost
		elif roll <= 80:
			# Attack
			_action_used = Action.ATTACK
			_do_melee_attack(target)
			_pending_cost = attack_cost
		else:
			# Trip
			_action_used = Action.TRIP
			_play_attack_anim("attack-kick-right")
			_try_trip(target)
			_pending_cost = trip_cost
		await get_tree().create_timer(0.3).timeout
		end_my_turn(_pending_cost)
		return

	# Move toward target
	_begin_move_toward(target)


func _on_weapon_broke(item: ItemResource) -> void:
	## Goblins do not fight on with a ruined weapon: they throw it down and draw whatever else
	## they are carrying. Both are FREE — no _pending_cost is touched and end_my_turn is not
	## called, so this costs no time and never interrupts the turn it happened during. It can
	## fire on the defender's side of someone else's attack, which is exactly why it must not
	## try to drive the turn machinery.
	if inventory == null:
		return
	var slot: int = inventory.get_item_slot(item)
	if slot >= 0:
		inventory.remove_item(slot)  # also unequips it from whichever hand held it
	else:
		inventory.unequip_item(item)
	_drop_at_feet(item)

	var replacement: int = inventory.find_weapon_slot()
	if replacement >= 0:
		inventory.equip(replacement)
		var drawn: ItemResource = inventory.get_equipped_weapon()
		if drawn:
			_show_action_text("Drew " + drawn.item_name)
	_update_health_bar()


func _door_to_open_for(target: Node) -> Node:
	## The shut door standing between us and `target`, if we are already close enough to work
	## it. Null when there is nothing to open, or nothing worth opening.
	##
	## Checked against the route we could take with the doors AS THEY ARE first: if there is
	## already a way round, we take it rather than stopping to open something we never needed.
	## So a door only gets opened when it is genuinely the way through.
	var from_tile: Vector3 = _snap_to_grid(position)
	var to_tile: Vector3 = _snap_to_grid(target.position)
	if _find_path(from_tile, to_tile).size() > 1:
		return null
	var route: Array = _find_path(from_tile, to_tile, -1, true)
	if route.size() <= 1:
		return null
	for tile in route:
		var door: Node = _openable_door_at(tile)
		if door == null:
			continue
		# The FIRST door on the route and no further: a second one behind it is next turn's
		# problem, and we cannot reach past this one to work it anyway.
		#
		# Adjacency is measured to the door's SQUARE, not to the door. _is_adjacent allows half
		# a square of slack, which is right between two units standing on square centres and
		# wrong for a door standing on the line between two — measured raw, a goblin could
		# reach out and work a latch from a square and a half away.
		return door if _is_adjacent(_snap_to_grid((door as Node3D).global_position)) else null
	return null


func _try_open_door_toward(target: Node) -> bool:
	## Spend the turn opening the door in our way, if there is one within reach. True when we
	## did, and the caller should end its turn on that.
	var door: Node = _door_to_open_for(target)
	if door == null:
		return false
	_face_target(door as Node3D)
	door.interact(self)
	_show_action_text("Open!")
	_pending_cost = interact_cost
	return true


func _player_candidates() -> Array:
	## Every hero still standing. The raw pool both target pickers choose from.
	var out: Array = []
	for c in get_tree().get_nodes_in_group("combatants"):
		if not is_instance_valid(c) or c == self:
			continue
		if not c.is_player_controlled or not c.is_alive:
			continue
		out.append(c)
	return out


func _can_reach(target: Node) -> bool:
	## Is there a route to `target` at all — not this turn, but ever, as the board stands?
	## Asked with the same _find_path the move itself uses, so a target we call reachable is one
	## we can genuinely walk at. Somebody already at arm's length trivially counts.
	if _is_adjacent(target.position):
		return true
	# doors_openable: a shut door is a turn's work, not a wall. Without this a party could put
	# a door between themselves and the goblins and simply stop being a target.
	return _find_path(_snap_to_grid(position), _snap_to_grid(target.position), -1, true).size() > 1


func _reachable_or_all(candidates: Array) -> Array:
	## The candidates we can actually get to, or — if that is none of them — all of them.
	##
	## Reachability as the FIRST sort key, ahead of distance or hp. The hero behind a guarded
	## doorway may be the closest thing on the board, or the most wounded, and still be someone
	## we cannot lay a hand on; picking him anyway is how a goblin spends an entire fight
	## walking into a wall while a wizard stands in the open just beyond him.
	##
	## The fallback matters as much as the rule. When the whole party is behind one shut door
	## nothing is reachable, and an empty list would freeze the AI — so we go back to the full
	## pool and let _find_approach_path walk us at the door, which is the right instinct anyway.
	var reachable: Array = candidates.filter(_can_reach)
	return candidates if reachable.is_empty() else reachable


func _nearest_of(candidates: Array) -> Node:
	var best: Node = null
	var best_dist: float = INF
	for c in candidates:
		var dist: float = abs(c.position.x - position.x) + abs(c.position.z - position.z)
		if dist < best_dist:
			best_dist = dist
			best = c
	return best


func _weakest_of(candidates: Array) -> Node:
	var best: Node = null
	var lowest_hp: int = 0
	for c in candidates:
		if best == null or c.hp < lowest_hp:
			lowest_hp = c.hp
			best = c
	return best


func _find_weakest_reachable_player() -> Node:
	## The most wounded hero we can get to. The boss's pick — see _reachable_or_all for why
	## "can get to" comes before "most wounded".
	return _weakest_of(_reachable_or_all(_player_candidates()))


func _find_nearest_reachable_player() -> Node:
	## The nearest hero we can get to. What anything that closes to melee should be walking at.
	return _nearest_of(_reachable_or_all(_player_candidates()))


func _has_ally_adjacent_to(target: Node) -> bool:
	## Returns true if another enemy is adjacent to the given target
	for c in get_tree().get_nodes_in_group("combatants"):
		if c == self or c == target:
			continue
		if not is_instance_valid(c) or not c.is_alive:
			continue
		if c.is_player_controlled:
			continue
		if _is_adjacent(c.position, target.position):
			return true
	return false


func _min_player_dist(tile: Vector3) -> float:
	## Manhattan distance from a tile to the CLOSEST alive player. Used so the
	## archer backs away from the whole group, not just one hero.
	var best := INF
	for c in get_tree().get_nodes_in_group("combatants"):
		if not is_instance_valid(c) or not c.is_player_controlled or not c.is_alive:
			continue
		var d: float = abs(c.position.x - tile.x) + abs(c.position.z - tile.z)
		if d < best:
			best = d
	return best


func _move_toward(target: Node) -> void:
	## Walk the BFS route toward `target`, up to move_range tiles, following it waypoint
	## by waypoint so we route around walls/obstacles/heroes instead of cutting corners.
	## Stop on the last unoccupied tile (the target's own cell / an ally is never a
	## valid endpoint), so movement never ends on — or slices through — another unit.
	var from_tile: Vector3 = _snap_to_grid(position)
	var to_tile: Vector3 = _snap_to_grid(target.position)

	# Cleared up front so a bail-out below can't leave the previous move's tile count
	# behind for get_move_cost() to bill. A unit that goes nowhere still pays the floor
	# of 1, which is what keeps a boxed-in enemy from taking free turns forever.
	_move_tiles = 0

	var path: Array = _find_path(from_tile, to_tile)
	var step_count := 0
	if path.size() > 1:
		step_count = min(get_move_range(), path.size() - 1)
		while step_count >= 1 and _is_tile_occupied_by_others(path[step_count], self):
			step_count -= 1

	if step_count < 1:
		# Either there is no route to the target at all, or every tile we could stop on along
		# the one there is has somebody standing on it. Both used to end the turn on the spot,
		# which is how a bottleneck — a guarded doorway, say — left the goblins at the back
		# standing around in the chamber all fight while the two at the front did the work.
		#
		# Get as close as we can instead. A unit that cannot reach you should still be coming.
		path = _find_approach_path(to_tile, get_move_range())
		if path.size() <= 1:
			return
		# _find_approach_path only ever ends on a free tile, so there is nothing to walk back.
		step_count = path.size() - 1

	_follow_path(path.slice(0, step_count + 1))


func _pinning_guard() -> Node:
	## The guardian whose zone we are standing in, or null. A pinned enemy fights the guardian
	## and nobody else — it does not reach around him for the softer target behind.
	##
	## This is not the goblin getting clever; it is the opposite. The man in armour is in its
	## face, so that is what it hits. Targeting everywhere else stays exactly as dumb as it was.
	##
	## It is also load-bearing, not flavour. _find_nearest_player measures MANHATTAN distance
	## while _is_adjacent is CHEBYSHEV, so with GRID_SIZE 2 a goblin standing DIAGONALLY off the
	## guardian rates him at 4 — worse than a cardinally-adjacent wizard's 2, and level with a
	## wizard two clear tiles away. Without this the goblin would swing past the guardian's
	## shoulder at her, and since that tie breaks on scene-tree order it would look random.
	return _guard_at(_snap_to_grid(position))


func _find_nearest_player() -> Node:
	## The nearest alive hero, reachable or not.
	##
	## Deliberately NOT the reachable-first pick, and only the archer still uses it: an archer
	## shoots, so being unable to WALK to someone says nothing about being able to hit them.
	## A hero holding a doorway is the archer's best target precisely because he is standing in
	## the one gap in the wall, and filtering him out for being unwalkable would have the
	## archer turn away from the clearest shot on the board.
	return _nearest_of(_player_candidates())


func _do_adjacent_action(player: Node) -> void:
	## Weighted random action when adjacent: 60% attack, 25% shove, 15% trip
	_face_target(player)
	var roll := randi_range(1, 100)
	if roll <= 60:
		_action_used = Action.ATTACK
		_do_melee_attack(player)
		_pending_cost = attack_cost
	elif roll <= 85:
		_action_used = Action.SHOVE
		_play_attack_anim("attack-kick-right")
		_try_shove(player)
		_pending_cost = shove_cost
	else:
		_action_used = Action.TRIP
		_play_attack_anim("attack-kick-right")
		_try_trip(player)
		_pending_cost = trip_cost


func _on_move_complete() -> void:
	if _idling:
		# An idle amble is not a turn. Exploration has no clock, so there is nothing to bill,
		# and nothing is waiting on us — calling end_my_turn here would hand turn_done a
		# current_combatant that is one of the HEROES and stand them back up mid-order.
		_idling = false
		return
	end_my_turn(_pending_cost)


func end_my_turn(cost: int) -> void:
	var combat_mgr := _combat_mgr()
	if combat_mgr:
		combat_mgr.turn_done(cost)
