extends CharacterBody3D
class_name Combatant
## Base class for all combatants (player- and AI-controlled).
## Holds the shared stats, grid movement, defense/damage, equipment sockets,
## animation and health-bar logic. Player and Enemy extend this and add only
## their control-specific behaviour (input vs AI).

const GRID_SIZE := 2.0
const ARENA_MIN := -14.0
const ARENA_MAX := 14.0

## Collision layers used by ray queries.
const LAYER_GROUND := 1
const LAYER_ENEMY := 2
const LAYER_OBSTACLE := 4
const LAYER_PLAYER := 8              ## player-controlled combatants (assigned in _ready)
## Line-of-sight mask. MUST contain both combatant layers: _has_line_of_sight_from asks
## "did the ray reach the target before anything else", so the target's own layer has to
## be in the mask or the ray sails straight through it and the check can never pass.
## Players used to sit on the default layer 1, which this mask omitted — so every AI
## line-of-sight test against a hero returned false and the archer never took a shot.
const LAYER_LOS_BLOCKERS := 14       ## enemy (2) + obstacle (4) + player (8)

## Height above the body's origin that movement / line-of-sight rays are cast at.
const EYE_HEIGHT := 0.5

## The 8 grid steps (cardinals + diagonals) used by every path search.
const GRID_DIRS := [
	Vector3(GRID_SIZE, 0, 0), Vector3(-GRID_SIZE, 0, 0),
	Vector3(0, 0, GRID_SIZE), Vector3(0, 0, -GRID_SIZE),
	Vector3(GRID_SIZE, 0, GRID_SIZE), Vector3(GRID_SIZE, 0, -GRID_SIZE),
	Vector3(-GRID_SIZE, 0, GRID_SIZE), Vector3(-GRID_SIZE, 0, -GRID_SIZE)
]

## Partial cover (ranged & thrown only): a short obstacle between shooter and target.
const COVER_DEFENSE_BONUS := 3    ## added to an active dodge/parry roll when in cover
const COVER_SAVE_CHANCE := 25     ## % chance the obstacle eats the shot when we can't actively defend
const COVER_RAY_DROP := 0.6       ## metres below eye-line for the "does a short prop block us" ray

## Dual-wield free off-hand attack (see _do_melee_attack).
const OFFHAND_HIT_PENALTY := 5    ## to-hit penalty for the off-hand strike (0 with dual_wield_skill)
const OFFHAND_DELAY := 0.3        ## beat between the main hit and the off-hand follow-up

## Missile to-hit penalties, applied to bow shots AND thrown weapons alike by
## get_missile_skill(). Distance uses the same Manhattan measure the range checks do.
##
## Three flat bands rather than a per-distance slope: clean inside the free range, one
## penalty out to half the weapon's reach, a heavier one past that. The far band scales with
## the weapon, so a longbow stays accurate further out than a shortbow without either
## needing its own numbers.
##
## A square is one combatant's fighting space — reckon it at 1.5 m if you are converting a
## real weapon's range (a 300 m longbow is 200 squares).
const RANGE_FREE_TILES := 10       ## shots out to here are clean
const RANGE_PENALTY_NEAR := 3      ## beyond the free range, out to half the weapon's range
const RANGE_PENALTY_FAR := 6       ## beyond half the weapon's range
## Shooting at someone already in melee with one of ours: you are picking a gap in a scrum.
const ENGAGED_PENALTY := 5

## Optional data-driven stat block (a CombatantStats resource). When assigned,
## its values are copied onto this combatant at _ready (overriding the
## per-instance @export values below). Leave null to use scene / default values.
## Typed as Resource because the CombatantStats global class is not always
## registered when this base script first compiles; the .tres still carries it.
@export var stats: Resource

## Movement tunables (subclasses may override in _pre_setup / from stats).
var move_speed: float = 6.0
var move_range: int = 4

@export var initiative: int = 10
@export var character_name: String = "Hero"
@export var is_player_controlled: bool = true
## Time units charged per PAIR of tiles walked (see get_move_cost). At the default 1 a
## stride of 2-3 tiles costs one unit, 4-5 costs two, and so on — striding out is cheaper
## per tile than shuffling. The name is kept for the saved stat blocks in resources/stats.
@export var move_cost_per_tile: int = 1
@export var attack_cost: int = 2
@export var armor: int = 0
@export var physical_resistance: int = 0  ## percentage 0-100
@export var attack_skill: int = 5       ## used in attack vs defense rolls
@export var parry_skill: int = 4        ## parry defense skill
@export var dodge_skill: int = 5        ## dodge defense skill
@export_enum("Parry", "Dodge") var defensive_option: int = 0  ## 0=Parry, 1=Dodge
@export var shove_skill: int = 5
@export var trip_skill: int = 4
@export var shove_cost: int = 2
@export var trip_cost: int = 2
@export var dual_wield_skill: bool = false  ## trained off-hand: no -5 penalty on the free off-hand attack
@export var ranged_skill: int = 3       ## used for bow/distance attacks
@export var ranged_cost: int = 3
@export var ammo: int = 0
@export var max_ammo: int = 0
@export var ranged_range: int = 15      ## max tiles for ranged (accurate only to RANGE_FREE_TILES)
@export var throw_skill: int = 3        ## used for thrown weapon attacks
## One time unit — a throw is a single quick action, cheaper than a bow shot (which has to
## be nocked and drawn) and cheaper than a melee exchange. Note you also give up the weapon,
## so the real price is fetching it back off the floor.
@export var throw_cost: int = 1
@export var throw_range: int = 3        ## max tiles for thrown
@export var equip_cost: int = 1         ## time cost to swap equipped weapon/shield
@export var strength: int = 3
@export var weight: int = 2

var next_turn_at: int = 0
var is_prone: bool = false

var is_moving := false
var target_position := Vector3.ZERO
## Remaining waypoints for a routed move (set by _follow_path); empty = single hop.
var _move_path: Array = []
## Tiles the move in progress covers, recorded when the route is queued and read by
## get_move_cost() to price the move by distance. Zero when nothing is moving.
var _move_tiles: int = 0

## Emitted whenever hp / max_hp / is_alive change, so HUD elements (the party
## portraits) can refresh without polling. Fired from _update_health_bar(),
## which every damage and heal path already funnels through.
signal health_changed(hp: int, max_hp: int, is_alive: bool)

var hp := 20
var max_hp := 20
var attack_dmg := 4
var is_alive := true

var health_bar: Label3D
var inventory: Node  ## InventoryComponent

## Actions/skills this combatant can perform, as Ability resources. Populated by
## subclasses (player builds the action-bar set; enemies can be given their own).
var abilities: Array = []

## Time-unit cost of the action in progress; charged when the move/action finishes.
@warning_ignore("unused_private_class_variable")
var _pending_cost: int = 0

## Set by subclasses to the Action they performed; read when charging turn cost.
@warning_ignore("unused_private_class_variable")
var _action_used: int = 0

const TwoHandedGripScript := preload("res://scripts/two_handed_grip.gd")
const GroundItemScript := preload("res://scripts/ground_item.gd")

var _weapon_socket = null
var _shield_socket = null
var _helmet_socket = null
## Torso-mounted socket a TWO-HANDED weapon hangs off, so its angle is fixed relative to the
## chest and both arms can be posed onto it. Null when the rig has no torso bone, in which
## case two-handers fall back to the one-handed right-fist placement.
var _grip_socket: BoneAttachment3D = null
var _grip: SkeletonModifier3D = null
## Set while an attack animation plays: the grip is released and the weapon handed back to
## the right fist so the swing actually animates (see _play_attack_anim).
var _grip_suspended := false
var _center_target := 0.0
var _last_right_hand: ItemResource = null
var _last_left_hand: ItemResource = null
var _last_helmet: ItemResource = null
var _anim_player = null
var _is_attacking := false
## Rest-position of CharacterModel, cached on the first shove so overlapping
## knock-back slides always ease back to the same home instead of compounding.
var _model_home_pos := Vector3.INF
## Active cosmetic knock-back tween (see _animate_push_slide).
var _push_tween: Tween = null

## Uniform scale applied to the CharacterModel (and its held weapons) so the
## ~1-unit Kenney models fill the 2-unit grid cells. Multiplies any per-type
## scale an enemy sets. Tune to taste.
const CHARACTER_SCALE := 1.6

## Set true in project to re-enable verbose equipment logging.
const DEBUG_EQUIPMENT := false

# Preloaded weapon models
const SWORD_MODEL_PATH := "res://assets/models/kenney/mini-arena/weapon-sword.glb"
const BOW_MODEL_PATH := "res://assets/weapons/bow.fbx"
const SHIELD_MODEL_PATH := "res://assets/weapons/Shield_1.obj"
const HAMMER_MODEL_PATH := "res://Assets/PolygonDungeon/Models/SM_Wep_Hammer_Small_01.res"
const AXE_MODEL_PATH := "res://Assets/PolygonDungeon/Models/SM_Wep_Goblin_Axe_Large_01.res"
const SYNTY_MATERIAL_PATH := "res://Assets/PolygonDungeon/Materials/Dungeon_Material_01_mat.tres"


func _ready() -> void:
	target_position = position
	position.y = _ground_y()
	health_bar = get_node_or_null("HealthBar")
	inventory = get_node_or_null("Inventory")
	_apply_stats()
	_readd_equipment_bonuses()
	_pre_setup()
	# Put each side on its own physics layer. main.tscn only ever set layer 2 on the
	# enemies, leaving the heroes on the default layer 1 — the same layer as the floor,
	# which both broke AI line-of-sight (see LAYER_LOS_BLOCKERS) and let a click on a
	# party member register as a ground hit. _pre_setup is where enemies force
	# is_player_controlled, so this has to run after it.
	collision_layer = LAYER_PLAYER if is_player_controlled else LAYER_ENEMY
	_apply_character_scale()
	_setup_sockets()
	_update_health_bar()
	add_to_group("combatants")
	if not is_player_controlled:
		add_to_group("enemies")
	call_deferred("_play_idle_anim")
	_post_setup()


## Hook: runs before sockets/health bar are set up (enemy configures stats here).
func _pre_setup() -> void:
	pass


func _apply_character_scale() -> void:
	var model := get_node_or_null("CharacterModel") as Node3D
	if model:
		model.scale *= CHARACTER_SCALE


## Hook: runs at the end of _ready (player wires up UI here).
func _post_setup() -> void:
	pass


## Copy the assigned stat block onto the runtime vars. No-op if unassigned,
## leaving the scene-exported / default values in place.
func _apply_stats() -> void:
	if stats == null:
		return
	# Variant-typed local so field access is dynamic (base is exported as Resource).
	var s: Variant = stats
	character_name = s.character_name
	initiative = s.initiative
	max_hp = s.max_hp
	hp = s.max_hp
	attack_dmg = s.attack_dmg
	move_speed = s.move_speed
	move_range = s.move_range
	move_cost_per_tile = s.move_cost_per_tile
	attack_skill = s.attack_skill
	attack_cost = s.attack_cost
	shove_skill = s.shove_skill
	shove_cost = s.shove_cost
	trip_skill = s.trip_skill
	trip_cost = s.trip_cost
	dual_wield_skill = s.dual_wield_skill
	armor = s.armor
	physical_resistance = s.physical_resistance
	parry_skill = s.parry_skill
	dodge_skill = s.dodge_skill
	defensive_option = s.defensive_option
	ranged_skill = s.ranged_skill
	ranged_cost = s.ranged_cost
	ranged_range = s.ranged_range
	ammo = s.ammo
	max_ammo = s.max_ammo
	throw_skill = s.throw_skill
	throw_cost = s.throw_cost
	throw_range = s.throw_range
	strength = s.strength
	weight = s.weight
	equip_cost = s.equip_cost


## Restore the armor/resistance bonuses of already-equipped gear after a stat block
## has been applied.
##
## `Inventory` is a CHILD node, so InventoryComponent._ready() runs before ours: it
## equips the starting items and folds their bonuses into us via `armor += ...`.
## _apply_stats() then *assigns* armor and physical_resistance straight from the
## stat block, silently discarding those bonuses — so equipped armour counted for
## nothing on any combatant with a `stats` resource (i.e. every enemy).
##
## Only runs when a stat block was actually applied. With no stat block nothing was
## overwritten and the bonuses are already in place; re-adding would double-count.
func _readd_equipment_bonuses() -> void:
	if stats == null or inventory == null:
		return
	var counted: Array = []
	for slot in ["right_hand", "left_hand", "armor", "helmet"]:
		var item: ItemResource = inventory.get(slot)
		if item == null:
			continue
		# A two-handed weapon sits in BOTH hands as the same object, and
		# InventoryComponent applies its bonus once — dedupe to match.
		if counted.has(item):
			continue
		counted.append(item)
		armor += item.armor_bonus
		physical_resistance += item.resistance_bonus


func _lay_prone() -> void:
	## Get knocked down (tripped / shoved off balance): drop to the prone pose. Getting up
	## is a separate action charged at the unit's next turn (_stand_up_if_prone).
	if is_prone:
		return
	is_prone = true
	_show_condition_text("PRONE!")
	_update_health_bar()
	_update_prone_anim()


func _stand_up_if_prone() -> void:
	## Auto-stand costs 1 time unit (charged via the combat manager).
	if not is_prone:
		return
	is_prone = false
	_show_condition_text("Stood up")
	_update_health_bar()
	_update_prone_anim()
	_charge_defense_cost()


func _safe_load_scene(path: String) -> PackedScene:
	if not ResourceLoader.exists(path):
		return null
	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if loaded is PackedScene:
		return loaded as PackedScene
	# OBJ files load as Mesh, wrap in a one-node scene
	if loaded is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = loaded as Mesh
		var wrapper := PackedScene.new()
		wrapper.pack(mi)
		return wrapper
	return null


func _center_on_origin(n: Node3D) -> void:
	var meshes: Array = []
	_find_mesh_instances(n, meshes)
	if meshes.is_empty():
		return
	var aabb: AABB = AABB(Vector3.ZERO, Vector3.ZERO)
	var first := true
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh:
			var maabb: AABB = mi.transform * mi.mesh.get_aabb()
			if first:
				aabb = maabb
				first = false
			else:
				aabb = aabb.merge(maabb)
	if first:
		return
	var offset: Vector3 = aabb.get_center()
	for m in meshes:
		var mi := m as MeshInstance3D
		mi.position -= offset
	var max_dim: float = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
	if max_dim > 0.01 and max_dim < 100:
		var target: float = 1.2
		if _center_target != 0.0:
			target = _center_target
		var s: float = target / max_dim
		n.scale = Vector3(s, s, s)


func _find_mesh_instances(node: Node, out_list: Array) -> void:
	if node is MeshInstance3D:
		out_list.append(node)
	for child in node.get_children():
		_find_mesh_instances(child, out_list)


func _setup_sockets() -> void:
	var model: Node = get_node_or_null("CharacterModel")
	if not model:
		return
	var skeleton: Skeleton3D = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if not skeleton:
		return
	# Find existing BoneAttachment3D nodes from the wrapper scene
	_weapon_socket = skeleton.find_child("WeaponSocket", false, false) as BoneAttachment3D
	_shield_socket = skeleton.find_child("ShieldSocket", false, false) as BoneAttachment3D
	_helmet_socket = skeleton.find_child("HelmetSocket", false, false) as BoneAttachment3D
	# Fallback: create at runtime if wrapper scene doesn't have them
	if not _weapon_socket:
		_weapon_socket = BoneAttachment3D.new()
		_weapon_socket.name = "WeaponSocket"
		_weapon_socket.bone_name = "arm-right"
		skeleton.add_child(_weapon_socket)
	if not _shield_socket:
		_shield_socket = BoneAttachment3D.new()
		_shield_socket.name = "ShieldSocket"
		_shield_socket.bone_name = "arm-left"
		skeleton.add_child(_shield_socket)
	if not _helmet_socket:
		_helmet_socket = BoneAttachment3D.new()
		_helmet_socket.name = "HelmetSocket"
		_helmet_socket.bone_name = "head"
		skeleton.add_child(_helmet_socket)
	_setup_two_handed_grip(skeleton)


func _setup_two_handed_grip(skeleton: Skeleton3D) -> void:
	## The torso socket a two-hander hangs off, plus the modifier that poses the arms onto
	## it. Both are skipped on a rig without a torso bone — the socket would otherwise sit at
	## the skeleton origin and park the weapon at the character's feet.
	if skeleton.find_bone(TwoHandedGripScript.TORSO_BONE) < 0:
		return
	_grip_socket = skeleton.find_child("GripSocket", false, false) as BoneAttachment3D
	if not _grip_socket:
		_grip_socket = BoneAttachment3D.new()
		_grip_socket.name = "GripSocket"
		_grip_socket.bone_name = TwoHandedGripScript.TORSO_BONE
		skeleton.add_child(_grip_socket)
	_grip = TwoHandedGripScript.new()
	_grip.name = "TwoHandedGrip"
	skeleton.add_child(_grip)
	if not _grip.is_solved():
		# Rig is missing an arm bone; drop back to one-handed placement entirely.
		_grip.queue_free()
		_grip = null
		_grip_socket = null


func _update_equipment_visuals() -> void:
	if not inventory:
		return
	var main: ItemResource = inventory.get("right_hand")
	var off: ItemResource = inventory.get("left_hand")
	var helmet_item: ItemResource = inventory.get("helmet")
	if DEBUG_EQUIPMENT:
		print("[Combatant] %s: right_hand=%s left_hand=%s helmet=%s" % [character_name, main.item_name if main else "null", off.item_name if off else "null", helmet_item.item_name if helmet_item else "null"])
	if main == _last_right_hand and off == _last_left_hand and helmet_item == _last_helmet:
		return
	_last_right_hand = main
	_last_left_hand = off
	_last_helmet = helmet_item
	# A two-handed weapon sits in BOTH hand slots as the same object.
	var two_handed: bool = main != null and main == off
	# Held in two hands only when the weapon opts in (bows do not — see
	# ItemResource.use_two_handed_grip), while we have a grip to hold it with, and outside an
	# attack — mid-swing the weapon goes back to the right fist so it follows the arm.
	var use_grip: bool = two_handed and main.use_two_handed_grip \
		and _grip != null and not _grip_suspended
	_refresh_grip_socket(main if use_grip else null)
	_refresh_socket(_weapon_socket, null if use_grip else main)
	_refresh_socket(_shield_socket, null if two_handed else off)
	_refresh_socket(_helmet_socket, helmet_item)


func _refresh_grip_socket(item: ItemResource) -> void:
	## Hang a two-hander off the chest and switch the arm-posing modifier on.
	##
	## Building goes through _refresh_socket so every per-item model rule (data-driven model,
	## legacy name lookup, Synty material, placeholder box) stays in exactly one place; only
	## the placement is redone afterwards, since the hand offsets _refresh_socket applies are
	## tuned for a fist and mean nothing on the torso.
	if _grip_socket == null or _grip == null:
		return
	_refresh_socket(_grip_socket, item)
	_grip.active = item != null
	if item == null:
		return
	if _grip_socket.get_child_count() > 0:
		_grip.place_weapon(_grip_socket.get_child(0) as Node3D, item.model_grip_roll)


func _set_grip_suspended(suspended: bool) -> void:
	## Release or retake the two-handed grip, rebuilding the equipment visuals so the weapon
	## moves between the chest socket and the right fist. The cached-item early-out in
	## _update_equipment_visuals would otherwise swallow the change, so clear the cache.
	if _grip == null or _grip_suspended == suspended:
		return
	if suspended and not _grip.active:
		return  # nothing is being held two-handed, so there is no grip to release
	_grip_suspended = suspended
	_last_right_hand = null
	_last_left_hand = null
	_last_helmet = null
	_update_equipment_visuals()


func _refresh_socket(socket, item: ItemResource) -> void:
	if not socket:
		return
	for c in socket.get_children():
		c.queue_free()
	if not item:
		return
	# Data-driven model: if the item declares its own model, use it directly.
	if item.has_model():
		var model_node := item.instantiate_model()
		if model_node:
			model_node.position = item.model_hand_position
			model_node.rotation_degrees = item.model_hand_rotation
			_apply_offhand_mirror(model_node, socket, item)
			socket.add_child(model_node)
			return
	# Otherwise fall back to the name/type-based lookup below.
	# Determine weapon kind by name: bow vs hammer vs axe/cleaver vs sword/dagger.
	var lower_name: String = item.item_name.to_lower()
	var is_bow: bool = lower_name.find("bow") >= 0
	var is_hammer: bool = lower_name.find("hammer") >= 0
	var is_axe: bool = lower_name.find("axe") >= 0 or lower_name.find("cleaver") >= 0
	var is_synty: bool = is_hammer or is_axe  # Synty meshes need the atlas material assigned
	# Try to load the 3D model for this weapon type
	var packed: PackedScene = null
	match item.item_type:
		ItemResource.ItemType.WEAPON:
			if is_bow:
				packed = _safe_load_scene(BOW_MODEL_PATH)
			elif is_hammer:
				packed = _safe_load_scene(HAMMER_MODEL_PATH)
			elif is_axe:
				packed = _safe_load_scene(AXE_MODEL_PATH)
			else:
				packed = _safe_load_scene(SWORD_MODEL_PATH)
		ItemResource.ItemType.SHIELD:
			packed = _safe_load_scene(SHIELD_MODEL_PATH)
	if packed != null:
		var node: Node = packed.instantiate()
		if node is Node3D:
			var n3d := node as Node3D
			# Set per-type target size for scaling
			match item.item_type:
				ItemResource.ItemType.WEAPON:
					if is_bow:
						_center_target = 0.8
					elif is_hammer:
						_center_target = 0.6
					elif is_axe:
						_center_target = 0.7
					else:
						_center_target = 0.5
				ItemResource.ItemType.SHIELD:
					_center_target = 0.7
				_:
					_center_target = 1.2
			_center_on_origin(n3d)
			# The Synty hammer mesh ships without a resolved material; assign the
			# shared dungeon atlas material to every mesh surface so it renders textured.
			if is_synty:
				var hammer_mat: Material = load(SYNTY_MATERIAL_PATH)
				if hammer_mat:
					var hammer_meshes: Array = []
					_find_mesh_instances(n3d, hammer_meshes)
					for m in hammer_meshes:
						(m as MeshInstance3D).material_override = hammer_mat
			# Apply per-weapon-type position and rotation offsets
			match item.item_type:
				ItemResource.ItemType.WEAPON:
					if is_bow:
						# Bow model lies flat along Z (AABB: 0.3x0.1x1.25), rotate X 90 to make vertical
						# Mirror with Y 180 and shift towards right arm (negative X)
						n3d.position = Vector3(-0.15, 0, 0.08)
						n3d.rotation_degrees = Vector3(90, 180, 0)
					elif is_hammer:
						# Synty hammer: starting grip offset (tune position/rotation to taste).
						n3d.position = Vector3(-0.2, 0.1, 0.08)
						n3d.rotation_degrees = Vector3(0, 30, 190)
					elif is_axe:
						# Synty goblin greataxe: starting grip offset (tune to taste).
						n3d.position = Vector3(-0.2, 0.15, 0.08)
						n3d.rotation_degrees = Vector3(0, 30, 10)
					else:
						# Sword model is already vertical (Y is longest axis)
						# Flip 180 on Z so blade points down, push away from body
						n3d.position = Vector3(-0.25, 0.15, 0.08)
						n3d.rotation_degrees = Vector3(0, 30, 190)
				ItemResource.ItemType.SHIELD:
					# Shield is already vertical (Y longest, X=0.84 wide, Z=0.14 thin)
					# Push outward on left arm (positive X = outward from body on left side)
					n3d.position = Vector3(0.2, 0, 0.15)
					n3d.rotation_degrees = Vector3(0, 20, 0)
			_apply_offhand_mirror(n3d, socket, item)
		socket.add_child(node)
		return
	# Fallback: procedural box placeholder
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	var box := BoxMesh.new()
	match item.item_type:
		ItemResource.ItemType.WEAPON:
			if item.handedness == ItemResource.Handedness.TWO_HANDED:
				box.size = Vector3(0.2, 2.0, 0.2)
				mat.albedo_color = Color(0.55, 0.3, 0.1)
				mi.position = Vector3(0, 0.6, 0.15)
			else:
				box.size = Vector3(0.2, 1.2, 0.2)
				mat.albedo_color = Color(0.7, 0.6, 0.15)
				mi.position = Vector3(0, 0.5, 0.15)
		ItemResource.ItemType.SHIELD:
			box.size = Vector3(0.7, 0.05, 0.7)
			mat.albedo_color = Color(0.4, 0.3, 0.2)
			mi.position = Vector3(0, 0.35, 0.15)
		_:
			return
	mi.mesh = box
	mi.material_override = mat
	socket.add_child(mi)


func _apply_offhand_mirror(node: Node3D, socket, item: ItemResource) -> void:
	## Hand placement offsets are tuned for the right-hand socket. The left-hand
	## (shield) socket is a mirrored bone, so mirror non-shield items across X or
	## they end up flipped and floating near the neck.
	if socket != _shield_socket:
		return
	if item.item_type == ItemResource.ItemType.SHIELD or item.is_shield:
		return
	var p: Vector3 = node.position
	p.x = -p.x
	node.position = p
	var r: Vector3 = node.rotation_degrees
	r.y = -r.y
	r.z = -r.z
	node.rotation_degrees = r


func _step_blocked_by_wall(from_tile: Vector3, to_tile: Vector3) -> bool:
	## True if a wall (obstacle-layer collision) lies on the edge between two adjacent
	## tiles. Used per-step by _find_path so routes can't cross walls but pass freely
	## through the collision-free doorway. Combatants (layer 2) are ignored here.
	var space_state := get_world_3d().direct_space_state
	var from_pos := Vector3(from_tile.x, position.y + EYE_HEIGHT, from_tile.z)
	var to_pos := Vector3(to_tile.x, position.y + EYE_HEIGHT, to_tile.z)
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.collision_mask = LAYER_OBSTACLE
	query.exclude = [get_rid()]
	return not space_state.intersect_ray(query).is_empty()


func _is_corner_blocked(from_tile: Vector3, to_tile: Vector3) -> bool:
	## True when a DIAGONAL step would squeeze through the corner-to-corner gap between two
	## solid cells — i.e. BOTH cells the diagonal passes between are blocked. Rounding a
	## single obstacle's corner (one side free) stays legal, so units keep their diagonal
	## mobility. Cardinal steps always return false.
	##
	## The per-step wall ray can't catch this on its own: it is cast at eye height, and the
	## arena's pillars are deliberately short (they grant partial cover rather than blocking
	## a shot — see _has_partial_cover_from), so the ray flies straight over them. Worse, the
	## pillars sit in diagonally-touching PAIRS — (5,3)+(3,5) and its three mirrors — so a
	## unit cutting that corner walked visibly between and through the pair. Testing the two
	## orthogonal cells is height-independent and fixes it.
	##
	## Only static geometry counts here; units still slip diagonally past each other.
	if abs(to_tile.x - from_tile.x) < 0.5 or abs(to_tile.z - from_tile.z) < 0.5:
		return false
	var side_a := Vector3(to_tile.x, from_tile.y, from_tile.z)
	var side_b := Vector3(from_tile.x, from_tile.y, to_tile.z)
	return _is_side_solid(from_tile, side_a) and _is_side_solid(from_tile, side_b)


func _is_side_solid(from_tile: Vector3, side: Vector3) -> bool:
	return _is_obstacle_at(side) or _step_blocked_by_wall(from_tile, side)


func _is_hostile(other: Node) -> bool:
	## Two combatants are hostile when they sit on opposite sides. Same side = allies.
	return other != null and "is_player_controlled" in other \
		and other.is_player_controlled != is_player_controlled


func _hostile_combatant_at(tile: Vector3) -> Node:
	for c in get_tree().get_nodes_in_group("combatants"):
		if c == self or not is_instance_valid(c):
			continue
		if "is_alive" in c and not c.is_alive:
			continue
		if not _is_hostile(c):
			continue
		if c._snap_to_grid(c.position).distance_to(tile) < 0.5:
			return c
	return null


func _tile_key(tile: Vector3) -> String:
	return str(int(round(tile.x))) + "," + str(int(round(tile.z)))


func _find_path(from_tile: Vector3, to_tile: Vector3, max_steps: int = -1) -> Array:
	## BFS on the grid returning the shortest cardinal path [from .. to], routing around
	## walls, obstacles and EVERY other living combatant (allies included). The goal tile
	## stays passable so an enemy can still path onto its target's cell (the caller stops
	## short). Pass max_steps to bound search depth (players cap it at move_range).
	# 8-directional: cardinals + diagonals, so a unit can slip through a diagonal gap
	# between two obstacles instead of being forced around. Walls still block via the
	# per-step ray, and an obstacle/unit ON the diagonal cell is still rejected.
	#
	# Allies block too (not just hostiles): a unit can't actually step onto a tile a
	# squadmate occupies, so treating them as walk-through produced a path whose next
	# step was blocked — the mover then trimmed it to nothing and froze in place instead
	# of routing around. This bit hardest when a pillar funnelled several enemies into a
	# single-file gap. Routing around allies makes them detour to a free approach tile.
	var queue: Array = [[from_tile]]
	var visited: Dictionary = {}
	visited[_tile_key(from_tile)] = true

	while not queue.is_empty():
		var path: Array = queue.pop_front()
		var cur: Vector3 = path[path.size() - 1]
		if cur.distance_to(to_tile) < 0.5:
			return path
		var steps: int = path.size() - 1
		if max_steps >= 0 and steps >= max_steps:
			continue
		if steps > 50:
			continue
		for d in GRID_DIRS:
			var nxt: Vector3 = _snap_to_grid(cur + d)
			var k: String = _tile_key(nxt)
			if visited.has(k):
				continue
			if _is_obstacle_at(nxt):
				continue
			var is_goal: bool = nxt.distance_to(to_tile) < 0.5
			if not is_goal and _get_combatant_at(nxt, self) != null:
				continue
			if _step_blocked_by_wall(cur, nxt) or _is_corner_blocked(cur, nxt):
				continue
			visited[k] = true
			var new_path: Array = path.duplicate()
			new_path.append(nxt)
			queue.append(new_path)
	return []


func _start_path_move(target: Vector3) -> void:
	## Begin a routed move to `target`: follow the BFS path waypoint-by-waypoint so the
	## unit walks around walls / enemies instead of sliding straight through them.
	var path: Array = _find_path(_snap_to_grid(position), target, move_range)
	if path.size() <= 1:
		# No route found (MoveAbility.can_target already pathed here, so this is a
		# belt-and-braces fallback). Slide straight over and charge it as one step.
		target_position = _snap_to_grid(target)
		_move_path = []
		_move_tiles = 1
		is_moving = true
	else:
		_follow_path(path)


func _follow_path(path: Array) -> void:
	## Queue a routed path as waypoints for _physics_process to walk one at a time, and
	## record its length so the move can be priced by distance. `path` starts on our own
	## tile, so it must hold at least two entries.
	_move_tiles = max(1, path.size() - 1)
	_move_path = path.slice(1)
	target_position = _move_path.pop_front()
	is_moving = true


func get_move_cost(tiles: int = -1) -> int:
	## Time-unit cost of walking `tiles` grid cells (defaults to the move in progress).
	## Movement is charged per PAIR of tiles, rounded down, so covering ground in one long
	## stride beats taking the same distance in dribs and drabs: 1-3 tiles cost one unit,
	## 4-5 cost two, 6-7 three.
	##
	## The floor of 1 matters — it is not just rounding. A zero-cost action does not
	## advance the tick, so the combat manager hands the same unit its turn straight back:
	## the player could step one tile at a time forever for free, and an AI whose route
	## comes back empty (fully boxed in) would spin on the spot without the clock ever
	## moving.
	if tiles < 0:
		tiles = _move_tiles
	@warning_ignore("integer_division")
	return max(1, tiles / 2) * move_cost_per_tile


func _has_line_of_sight(target: Node) -> bool:
	return _has_line_of_sight_from(position, target)


func _has_line_of_sight_from(from_tile: Vector3, target: Node) -> bool:
	## Clear shot at `target` from `from_tile`? Taking the origin as a parameter lets the AI
	## score firing positions it has not walked to yet; passing `position` is the plain
	## "can I shoot from where I stand" check.
	var target_node := target as Node3D
	if not target_node:
		return false
	var space_state := get_world_3d().direct_space_state
	var from_pos := Vector3(from_tile.x, position.y + EYE_HEIGHT, from_tile.z)
	var to_pos := target_node.position + Vector3(0, EYE_HEIGHT, 0)
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.collision_mask = LAYER_LOS_BLOCKERS
	query.exclude = [get_rid()]
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return false
	return result.collider == target


func take_damage(amount: int, attacker_skill: int = 0, is_ranged: bool = false, attacker: Node = null) -> bool:
	if not is_alive:
		return false

	var def_result: Dictionary = _attempt_defense(attacker_skill, is_ranged, attacker)
	if def_result.defended:
		return true

	var effective: int = _calculate_damage(amount)
	hp -= effective
	if effective > 0:
		_show_damage_number(effective)
	_update_health_bar()
	if hp <= 0:
		is_alive = false
		_die()
	else:
		_play_hit_anim()
	return false


func _attempt_defense(attacker_skill: int, is_ranged: bool = false, attacker: Node = null) -> Dictionary:
	var attack_roll := attacker_skill + randi_range(1, 5)
	var effective_dodge: int = dodge_skill - (2 if is_prone else 0)
	var result := { "defended": false, "attack_roll": attack_roll, "defense_roll": 0 }

	# Partial cover: a short prop (pillar / vessel) on the line from the shooter hinders
	# ranged & thrown attacks. It boosts an active dodge/parry, and — since even a
	# defenceless target gains from ducking behind a pillar — grants a flat save when no
	# active defence is possible. Melee (is_ranged == false) is point-blank, so cover is off.
	var has_cover: bool = is_ranged and attacker != null and _has_partial_cover_from(attacker)
	var cover_bonus: int = COVER_DEFENSE_BONUS if has_cover else 0

	if defensive_option == 0:
		if not (_has_usable_weapon() or _has_shield_equipped()):
			return _resolve_cover_only(has_cover, result)
		if is_ranged and not _can_parry_ranged():
			return _resolve_cover_only(has_cover, result)
		result.defense_roll = get_parry_skill() + randi_range(1, 5) + cover_bonus
		if result.defense_roll >= attack_roll:
			if inventory and inventory.has_method("degrade_equipped_weapon"):
				inventory.degrade_equipped_weapon()
			_show_defense_result("Cover parry!" if has_cover else "Parry!")
			_update_health_bar()
			_charge_defense_cost()
			result.defended = true
	else:
		if is_ranged and not _can_dodge_ranged():
			return _resolve_cover_only(has_cover, result)
		result.defense_roll = effective_dodge + randi_range(1, 5) + cover_bonus
		if result.defense_roll >= attack_roll:
			_show_defense_result("Cover dodge!" if has_cover else "Dodge!")
			_charge_defense_cost()
			result.defended = true
	return result


func _resolve_cover_only(has_cover: bool, result: Dictionary) -> Dictionary:
	## Reached when no active defence was possible. A target in partial cover still has a
	## flat chance for the prop to swallow the shot ("Cover!"); this is passive, so unlike a
	## dodge/parry it costs no time. Otherwise the hit lands.
	if has_cover and randi_range(1, 100) <= COVER_SAVE_CHANCE:
		_show_defense_result("Cover!")
		result.defended = true
	return result


func _has_partial_cover_from(attacker: Node) -> bool:
	## True when a SHORT obstacle (pillar / vessel) sits on the line between `attacker` and
	## us: it blocks a waist-height ray but not the head-height LOS ray, so the shot is still
	## possible, just hindered. Tall walls block both rays (they're full cover / no shot, and
	## the shooter's own LOS check already stops those), so they don't register here.
	var atk := attacker as Node3D
	if atk == null:
		return false
	var space_state := get_world_3d().direct_space_state
	var from_pos := Vector3(atk.position.x, atk.position.y - COVER_RAY_DROP, atk.position.z)
	var to_pos := Vector3(position.x, position.y - COVER_RAY_DROP, position.z)
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.collision_mask = LAYER_OBSTACLE
	query.exclude = [get_rid()]
	return not space_state.intersect_ray(query).is_empty()


func _calculate_damage(raw: int) -> int:
	var dmg := raw - armor
	if dmg <= 0:
		return 0
	dmg = roundi(dmg * (1.0 - physical_resistance / 100.0))
	return max(dmg, 0)


func _apply_impact_damage(amount: int) -> void:
	var effective: int = _calculate_damage(amount)
	if effective <= 0:
		return
	hp -= effective
	_show_damage_number(effective)
	_update_health_bar()
	if hp <= 0:
		hp = 0
		is_alive = false
		_die()
	else:
		_play_hit_anim()


func _apply_push(push_dir: Vector3, force: int) -> void:
	if force <= 0:
		return
	# Snap the push to one of the 8 grid directions. Both axes fire for a diagonal
	# shove, so an enemy shoved from a diagonal square is knocked back diagonally
	# rather than sideways. push_dir is normalized: a cardinal push has one ~1.0
	# component and one ~0.0; a diagonal push has two ~0.7 components.
	var dir := Vector3.ZERO
	if abs(push_dir.x) > 0.4:
		dir.x = sign(push_dir.x)
	if abs(push_dir.z) > 0.4:
		dir.z = sign(push_dir.z)
	if dir == Vector3.ZERO:
		dir.x = 1.0
	var start: Vector3 = _snap_to_grid(position)
	var landed := 0  # tiles actually travelled before hitting a wall / blocker / the end
	for i in range(1, force + 1):
		var prev: Vector3 = _snap_to_grid(start + dir * GRID_SIZE * (i - 1))
		var next: Vector3 = _snap_to_grid(start + dir * GRID_SIZE * i)
		if next.x < ARENA_MIN or next.x > ARENA_MAX or next.z < ARENA_MIN or next.z > ARENA_MAX:
			_apply_impact_damage((force - i + 1) * 2)
			break
		# Same per-step obstacle-layer ray _find_path uses: stops a diagonal shove from
		# cutting the corner across a prop that sits on a grid crossing (the vessel),
		# whose collider blocks the edge even though no cell is reserved via _is_obstacle_at.
		if _is_obstacle_at(next) or _step_blocked_by_wall(prev, next):
			_apply_impact_damage((force - i + 1) * 2)
			break
		var blocker: Node = _get_combatant_at(next, self)
		if blocker != null:
			var remaining: int = force - i + 1
			_apply_impact_damage(remaining)
			if blocker.has_method("_apply_impact_damage"):
				blocker._apply_impact_damage(remaining)
			var chain: int = remaining - blocker.weight
			if chain > 0 and blocker.has_method("_apply_push"):
				blocker._apply_push(dir, chain)
			position = _snap_to_grid(start + dir * GRID_SIZE * (i - 1))
			target_position = position
			break
		position = next
		target_position = next
		landed = i
	# The grid position has already snapped to the destination (above), so occupancy
	# and turn logic stay instant. Layer a purely cosmetic slide on top so the shove
	# reads as a stagger across the floor rather than a teleport.
	if landed > 0:
		_animate_push_slide(start, position, landed)


func _animate_push_slide(from_tile: Vector3, to_tile: Vector3, tiles: int) -> void:
	## Cosmetic only. The logical grid position is already at `to_tile`; here we snap the
	## visual CharacterModel back to `from_tile` and ease it home, flipping through random
	## "tumble" clips so a shove looks like a staggering slide instead of a teleport.
	var model := get_node_or_null("CharacterModel") as Node3D
	if model == null:
		return
	# Cache the true rest-position the first time, so repeat shoves never compound.
	if _model_home_pos == Vector3.INF:
		_model_home_pos = model.position
	# Cancel any in-flight slide before starting a new one (kills its coroutine's loop too).
	if _push_tween and _push_tween.is_valid():
		_push_tween.kill()

	var offset := from_tile - to_tile
	offset.y = 0.0
	if offset.length() < 0.01:
		model.position = _model_home_pos
		return

	# Keep whatever facing the character already had — a shove slides the body across
	# the floor; it shouldn't turn to "walk" in the push direction.

	# Jump the visual back to the origin tile, then ease it to the resting spot.
	model.position = _model_home_pos + offset
	var per_tile := 0.4  # seconds per tile — deliberately slow so the shove reads
	var tween := create_tween()
	_push_tween = tween
	tween.tween_property(model, "position", _model_home_pos, per_tile * tiles) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Cycle random tumble animations for as long as the slide is running.
	var ap := _ensure_anim_player()
	if ap:
		var clips := ["crouch", "fall", "jump", "walk"]
		while tween.is_valid() and tween.is_running():
			var clip: String = clips[randi() % clips.size()]
			if ap.has_animation(clip):
				ap.play(clip)
			await get_tree().create_timer(per_tile).timeout

	# Settle back to the neutral pose, unless a newer slide took over or we were downed.
	if _push_tween == tween and is_alive and not is_prone and not _is_attacking:
		_play_rest_anim()


func _try_shove(target: Node) -> int:
	## Returns the number of tiles pushed, or -1 if the shove was defended.
	var def_result: Dictionary = target._attempt_defense(shove_skill)
	if def_result.defended:
		return -1

	var push_tiles: int = max(1, strength - target.weight)
	var push_dir: Vector3 = (target.position - position)
	push_dir.y = 0
	if push_dir.length() < 0.01:
		push_dir = Vector3.RIGHT
	push_dir = push_dir.normalized()

	target._apply_push(push_dir, push_tiles)
	return push_tiles


func _try_trip(target: Node) -> bool:
	## Returns true if the trip connected (was not defended).
	var def_result: Dictionary = target._attempt_defense(trip_skill)
	if def_result.defended:
		return false
	target._lay_prone()
	return true


func _spawn_ground_item(item: ItemResource, at: Vector3) -> void:
	## Put an item on the floor as a pickup. Lives on Combatant rather than Player because
	## enemies drop things too (a goblin ditching a broken weapon).
	var gi := MeshInstance3D.new()
	gi.name = "GroundItem"
	gi.set_script(GroundItemScript)
	gi.position = at
	gi.item_resource = item
	get_parent().add_child(gi)
	# Defer visual so the node is fully in the tree
	gi.call_deferred("_apply_visual")


func _drop_at_feet(item: ItemResource) -> void:
	## Drop onto our own square, jittered so several drops do not stack into one mesh. The
	## floor height is absolute: our own y is the elevated body origin, not ground level.
	if item == null:
		return
	_spawn_ground_item(item, Vector3(
		position.x + randf_range(-0.6, 0.6),
		GroundItemScript.DROP_Y,
		position.z + randf_range(-0.6, 0.6)))


func _on_weapon_broke(_item: ItemResource) -> void:
	## Hook: a held weapon just broke and has been renamed. The item is left equipped by
	## default — a player decides for themselves what to do with a ruined blade. Enemy
	## overrides this to throw it down and draw a spare.
	pass


func _charge_defense_cost() -> void:
	var combat_mgr := get_parent().get_node_or_null("CombatManager")
	if combat_mgr:
		combat_mgr.charge_defense_cost(self)


func _is_in_arena(tile: Vector3) -> bool:
	return tile.x >= ARENA_MIN and tile.x <= ARENA_MAX and tile.z >= ARENA_MIN and tile.z <= ARENA_MAX


func _is_obstacle_at(tile: Vector3) -> bool:
	for o in get_tree().get_nodes_in_group("obstacles"):
		if not is_instance_valid(o):
			continue
		var obs_tile := Vector3((floor(o.position.x / GRID_SIZE) + 0.5) * GRID_SIZE, tile.y, (floor(o.position.z / GRID_SIZE) + 0.5) * GRID_SIZE)
		if obs_tile.distance_to(tile) < 0.5:
			return true
	return false


func _get_combatant_at(tile: Vector3, exclude: Node = null) -> Node:
	for c in get_tree().get_nodes_in_group("combatants"):
		if not is_instance_valid(c) or c == exclude:
			continue
		if "is_alive" in c and not c.is_alive:
			continue
		if c.has_method("_snap_to_grid") and c._snap_to_grid(c.position).distance_to(tile) < 0.5:
			return c
	return null


func _is_tile_occupied_by_others(tile: Vector3, exclude: Node = null) -> bool:
	for c in get_tree().get_nodes_in_group("combatants"):
		if not is_instance_valid(c) or c == exclude:
			continue
		# Dead combatants linger in the group (invisible) until cleaned up; they must
		# not keep blocking their tile, or units can't move where a corpse fell.
		if "is_alive" in c and not c.is_alive:
			continue
		if c._snap_to_grid(c.position).distance_to(tile) < 0.5:
			return true
		# Reserve a MOVING unit's destination too (so two movers don't pick the same
		# cell). A stationary unit only occupies the tile it actually stands on, so a
		# stale target_position can't phantom-block an empty square.
		if c.is_moving and c._snap_to_grid(c.target_position).distance_to(tile) < 0.5:
			return true
	return _is_obstacle_at(tile)


func _is_adjacent(target_pos: Vector3, source_pos: Vector3 = Vector3.INF) -> bool:
	if source_pos == Vector3.INF:
		source_pos = position
	# King-move adjacency: any of the 8 surrounding cells (or the same cell) counts,
	# so diagonal squares are "adjacent" for melee/shove/trip and the enemy AI.
	var dx: float = abs(target_pos.x - source_pos.x)
	var dz: float = abs(target_pos.z - source_pos.z)
	return max(dx, dz) <= GRID_SIZE * 1.5


func _has_usable_weapon() -> bool:
	if inventory and inventory.has_method("has_weapon_equipped"):
		return inventory.has_weapon_equipped()
	return false


func _has_shield_equipped() -> bool:
	if inventory and inventory.has_method("is_shield_equipped"):
		return inventory.is_shield_equipped()
	return false


func _can_parry_ranged() -> bool:
	if inventory and inventory.has_method("can_parry_ranged"):
		return inventory.can_parry_ranged()
	return false


func _can_dodge_ranged() -> bool:
	if inventory and inventory.has_method("can_dodge_ranged"):
		return inventory.can_dodge_ranged()
	return false


# --- Floating text helpers -------------------------------------------------

func _spawn_floating_label(text: String, font_size: int, start_y: float, end_y: float,
		color: Color, rise_time: float, hold_time: float, fade_time: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	# Dark outline keeps the lighter colours (white dodges especially) readable against
	# the pale floor. It's a separate modulate, so fade it alongside the main text below.
	label.outline_size = maxi(6, int(font_size * 0.25))
	label.outline_modulate = Color(0, 0, 0, 1)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, start_y, 0)
	label.modulate = color
	add_child(label)
	# Float up, hold at full opacity for hold_time so it lingers, then fade out and free.
	var tween := create_tween()
	tween.tween_property(label, "position:y", end_y, rise_time).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, fade_time).set_delay(hold_time)
	tween.parallel().tween_property(label, "outline_modulate:a", 0.0, fade_time).set_delay(hold_time)
	tween.tween_callback(label.queue_free)


func _show_action_text(text: String) -> void:
	_spawn_floating_label(text, 48, 3.0, 4.2, Color(1, 0.7, 0.3, 1), 0.6, 1.3, 0.6)


func _show_condition_text(text: String) -> void:
	_spawn_floating_label(text, 44, 1.8, 3.0, Color(0.9, 0.3, 0.3, 1), 0.7, 1.4, 0.7)


func _show_defense_result(text: String) -> void:
	# Parry / Dodge read white; anything cover-related (incl. "Cover parry!") reads orange.
	var color := Color(1, 0.6, 0.1, 1) if "Cover" in text else Color(1, 1, 1, 1)
	_spawn_floating_label(text, 52, 2.5, 3.8, color, 0.7, 1.5, 0.7)


func _show_damage_number(amount: int) -> void:
	_spawn_floating_label(str(amount), 64, 2.0, 3.5, Color(1, 0.2, 0.2, 1), 0.8, 1.6, 0.8)


# --- Active-turn highlight --------------------------------------------------

var _turn_ring: MeshInstance3D = null


func set_turn_active(active: bool) -> void:
	## Toggle the glowing ring that marks whose turn it is. The combat manager lights the
	## active unit and clears the rest, so the ring lingers under a unit for its whole turn.
	if active:
		_ensure_turn_ring()
		_turn_ring.visible = true
	elif _turn_ring != null:
		_turn_ring.visible = false


func _ensure_turn_ring() -> void:
	if _turn_ring != null:
		return
	var ring := MeshInstance3D.new()
	ring.name = "TurnRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.05
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.85, 0.2, 0.45)  # alpha < 1 so the floor shows through
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.15)
	mat.emission_energy_multiplier = 1.4
	ring.material_override = mat
	# Rest it just above the floor regardless of the body's ground offset (feet ~world 0.18).
	ring.position = Vector3(0, 0.18 - _ground_y(), 0)
	add_child(ring)
	_turn_ring = ring


# --- Grid / movement -------------------------------------------------------

func _snap_to_grid(pos: Vector3) -> Vector3:
	return Vector3(
		(floor(pos.x / GRID_SIZE) + 0.5) * GRID_SIZE,
		pos.y,
		(floor(pos.z / GRID_SIZE) + 0.5) * GRID_SIZE
	)


func _can_move() -> bool:
	return not is_prone


func _is_in_range(target: Vector3) -> bool:
	var dist: float = abs(target.x - position.x) + abs(target.z - position.z)
	return dist <= move_range * GRID_SIZE


# --- Ability stat accessors -------------------------------------------------
# Main-hand attack = base stat + the RIGHT-hand weapon's bonus only. The off-hand
# variants use the LEFT-hand weapon. Holding two weapons never stacks onto one swing.

func get_attack_skill() -> int:
	return attack_skill + _inv_bonus("main_hand_attack_bonus")


func get_attack_damage() -> int:
	## Floored at 1 so a broken weapon's damage penalty can never turn a hit into a no-op —
	## armour still gets its say afterwards in _calculate_damage.
	return maxi(1, attack_dmg + _inv_bonus("main_hand_damage_bonus"))


func get_missile_skill(base_skill: int, target: Node, max_range: int,
		from_tile: Vector3 = Vector3.INF) -> int:
	## A bow or throw skill after the missile penalties. Both missile paths resolve through
	## here so they cannot drift apart. `max_range` is the weapon's reach in tiles (its half
	## sets where the far band starts); `from_tile` lets the AI price a shot from a square it
	## has not walked to yet, and defaults to where we stand.
	var penalty: int = _range_penalty(target, max_range, from_tile)
	if _is_engaged(target):
		penalty += ENGAGED_PENALTY
	# A ruined bow shoots as badly as a ruined blade cuts. The melee paths get this through
	# _weapon_bonus; missiles never consult it, so the penalty has to be applied here.
	if inventory and inventory.has_method("get_equipped_weapon"):
		var w: ItemResource = inventory.get_equipped_weapon()
		if w and w.broken:
			penalty += ItemResource.BROKEN_HIT_PENALTY
	return base_skill - penalty


func _range_penalty(target: Node, max_range: int, from_tile: Vector3 = Vector3.INF) -> int:
	## Clean inside RANGE_FREE_TILES, RANGE_PENALTY_NEAR out to half the weapon's range, and
	## RANGE_PENALTY_FAR past that.
	var t := target as Node3D
	if t == null:
		return 0
	if from_tile == Vector3.INF:
		from_tile = position
	var tiles: float = (abs(t.position.x - from_tile.x) + abs(t.position.z - from_tile.z)) / GRID_SIZE
	if tiles <= RANGE_FREE_TILES:
		return 0
	return RANGE_PENALTY_NEAR if tiles <= max_range / 2.0 else RANGE_PENALTY_FAR


func _is_engaged(target: Node) -> bool:
	## True when the target stands in melee contact with someone hostile to IT other than us
	## — that is, we would be shooting into a scrum one of our own side is standing in.
	##
	## We are excluded on purpose: this models the risk of hitting a friend, not the
	## awkwardness of loosing a bow at someone in your own face. Drop the `c == self` skip to
	## make point-blank shots suffer it too.
	for c in get_tree().get_nodes_in_group("combatants"):
		if c == self or c == target or not is_instance_valid(c):
			continue
		if "is_alive" in c and not c.is_alive:
			continue
		if not target._is_hostile(c):
			continue
		if _is_adjacent(c.position, target.position):
			return true
	return false


func get_parry_skill() -> int:
	## Parry skill including whatever is in our hands (a shield, or a weapon made for
	## turning blades). Dodge has no equivalent: nothing worn or carried feeds that roll.
	return parry_skill + _inv_bonus("parry_bonus")


func get_offhand_attack_skill() -> int:
	return attack_skill + _inv_bonus("offhand_attack_bonus")


func get_offhand_attack_damage() -> int:
	return maxi(1, attack_dmg + _inv_bonus("offhand_damage_bonus"))


func _inv_bonus(method: String) -> int:
	if inventory and inventory.has_method(method):
		return inventory.call(method)
	return 0


func _do_melee_attack(target) -> void:
	## Shared melee routine for players and AI: main-hand strike, plus a free off-hand
	## follow-up when dual-wielding two melee weapons. Runs as a coroutine so the off-hand
	## lands a beat after the main hit (right anim, then left anim) instead of overwriting it.
	# Only an off-hand weapon held (main hand empty): the lone strike IS an off-hand attack.
	if inventory and inventory.has_method("offhand_only") and inventory.offhand_only():
		_offhand_attack(target)
		return
	_play_attack_anim("attack-melee-right")
	target.take_damage(get_attack_damage(), get_attack_skill(), false, self)

	if not (inventory and inventory.has_method("has_offhand_weapon") and inventory.has_offhand_weapon()):
		return
	if not (is_instance_valid(target) and target.is_alive):
		return  # main hit finished the target — nothing left to follow up on
	await get_tree().create_timer(OFFHAND_DELAY).timeout
	if not (is_alive and is_instance_valid(target) and target.is_alive and _is_adjacent(target.position)):
		return
	_offhand_attack(target)


func _offhand_attack(target) -> void:
	## The free off-hand strike: left-hand anim, half damage, -5 to hit unless the character
	## has the dual_wield_skill. Charges no time cost (called inside the main attack action).
	_play_attack_anim("attack-melee-left")
	var penalty: int = 0 if dual_wield_skill else OFFHAND_HIT_PENALTY
	var dmg: int = maxi(1, int(get_offhand_attack_damage() / 2.0))
	_show_action_text("Off-hand!")
	target.take_damage(dmg, get_offhand_attack_skill() - penalty, false, self)


func get_ranged_range() -> int:
	if inventory and inventory.has_method("get_equipped_ranged_range"):
		var r: int = inventory.get_equipped_ranged_range()
		if r > 0:
			return r
	return ranged_range


func get_throw_range() -> int:
	if inventory and inventory.has_method("get_equipped_throw_range"):
		var r: int = inventory.get_equipped_throw_range()
		if r > 0:
			return r
	return throw_range


func _physics_process(delta: float) -> void:
	if not is_moving:
		return

	var dir := target_position - position
	dir.y = 0  # Only move horizontally
	var dist := dir.length()

	if dist > 0.1:
		var model := get_node_or_null("CharacterModel") as Node3D
		if model:
			model.rotation.y = lerp_angle(model.rotation.y, atan2(dir.x, dir.z), delta * 15.0)

	if dist < 0.12:
		position = target_position
		position.y = _ground_y()
		if not _move_path.is_empty():
			# More of the routed path to walk: head to the next waypoint.
			target_position = _move_path.pop_front()
		else:
			is_moving = false
			velocity = Vector3.ZERO
			_on_move_complete()
	else:
		position += dir.normalized() * move_speed * delta
		position.y = _ground_y()

	if is_alive and not _is_attacking and not is_prone:
		var model := get_node_or_null("CharacterModel") as Node3D
		if model:
			if _anim_player == null:
				_anim_player = model.find_child("AnimationPlayer", true, false)
			if _anim_player:
				var target_anim := "walk" if is_moving else "idle"
				var ap := _anim_player as AnimationPlayer
				if ap.current_animation != target_anim:
					ap.play(target_anim)


## Called when a move finishes. Subclasses charge the appropriate turn cost.
func _on_move_complete() -> void:
	pass


func _ground_y() -> float:
	return 1.11


# --- Animation -------------------------------------------------------------

func _ensure_anim_player() -> AnimationPlayer:
	if _anim_player == null:
		var model := get_node_or_null("CharacterModel") as Node3D
		if model:
			_anim_player = model.find_child("AnimationPlayer", true, false)
	return _anim_player as AnimationPlayer


func _freeze_downed_pose(ap: AnimationPlayer) -> void:
	## Snap to and hold the final lying-down frame of the "die" clip (our shared pose for
	## both corpses and knocked-down units). Used to re-assert a downed pose WITHOUT
	## replaying the fall, so a stale action coroutine resuming after a death/knockdown
	## can't leave the body standing.
	if ap.current_animation != "die":
		ap.play("die")
	var die_anim := ap.get_animation("die")
	if die_anim:
		ap.seek(die_anim.length, true)
	ap.pause()


func _play_rest_anim() -> void:
	## The neutral pose a combatant returns to when no action is animating. Dead and prone
	## units stay down; everyone else idles. Every action coroutine funnels its
	## "back to neutral" through here, so a death or knockdown that lands mid-animation is
	## never overwritten when the old `await animation_finished` finally resumes.
	var ap := _ensure_anim_player()
	if not ap:
		return
	if not is_alive or is_prone:
		_freeze_downed_pose(ap)
	elif ap.current_animation != "idle":
		ap.play("idle")


func _update_prone_anim() -> void:
	## Deliberate pose transition: the fall into prone ("die") or the rise back to standing
	## ("idle"). Held poses are re-asserted afterwards by _play_rest_anim.
	var ap := _ensure_anim_player()
	if not ap:
		return
	ap.play("die" if is_prone else "idle")


func _play_idle_anim() -> void:
	var ap := _ensure_anim_player()
	if ap:
		ap.play("idle")


func _play_crouch_anim() -> void:
	## Flinch/crouch hit-reaction, then settle back to the neutral pose. Skipped when the
	## unit is already down (dead/prone) so a hit can't animate a corpse up into a crouch.
	if not _anim_player or _is_attacking or is_prone or not is_alive:
		return
	var ap := _anim_player as AnimationPlayer
	ap.play("crouch")
	await ap.animation_finished
	_play_rest_anim()


func _play_hit_anim() -> void:
	_play_crouch_anim()


func _play_attack_anim(anim_name: String) -> void:
	var ap := _ensure_anim_player()
	if not ap:
		return
	_is_attacking = true
	# Let go of the two-handed stance for the swing: the modifier pins both arms, so leaving
	# it on would hold the ready pose and the attack would not animate at all.
	_set_grip_suspended(true)
	ap.play(anim_name)
	await ap.animation_finished
	_is_attacking = false
	_set_grip_suspended(false)
	_play_rest_anim()


func _face_target(target: Node3D) -> void:
	var model := get_node_or_null("CharacterModel") as Node3D
	if not model or not target:
		return
	var dir := target.position - position
	dir.y = 0
	if dir.length() > 0.01:
		model.rotation.y = atan2(dir.x, dir.z)


func _die() -> void:
	can_act = false
	# Take the corpse off its physics layer so targeting/LOS raycasts pass straight
	# through it. Dead units are already ignored by the tile/occupancy checks (which
	# gate on is_alive), so a live combatant sharing this tile can no longer be
	# shadowed by the body lying on it (e.g. shoving the corpse instead of the enemy).
	collision_layer = 0
	var ap := _ensure_anim_player()
	if ap:
		ap.play("die")
		await ap.animation_finished
		# Freeze on the final laying-down frame so the corpse stays down instead of
		# snapping back to a rest pose. The body is left visible (a corpse on the floor);
		# dead units no longer block tiles (see _is_tile_occupied_by_others).
		_freeze_downed_pose(ap)
	# Drop the floating health bar so a "0/xx" label isn't hovering over the corpse.
	if health_bar:
		health_bar.visible = false
	var combat_mgr := get_parent().get_node_or_null("CombatManager")
	if combat_mgr:
		combat_mgr.on_character_died(self)


# can_act is only meaningful for player-controlled combatants but is declared
# here so the shared _die()/turn plumbing can reference it uniformly.
var can_act := false


func _update_health_bar() -> void:
	## Refreshes the floating nameplate above the character (and, via health_changed, the
	## party portraits). Deliberately does NOT show hp or the equipped item list: hp lives on
	## the portrait bars, and the gear is on the character model and the equipment panel, so
	## repeating either here just crowded the battlefield. What is left is the state you
	## cannot read off the model at a glance.
	_update_equipment_visuals()
	# Emitted before the Label3D early-out so listeners fire even for combatants
	# that have no floating nameplate node.
	health_changed.emit(hp, max_hp, is_alive)
	if not health_bar:
		return
	var lines: Array = [character_name]
	# Defensive stats, not gear: these are the totals AFTER equipment bonuses are folded in.
	var defense := ""
	if armor > 0:
		defense = "Armor:" + str(armor)
	if physical_resistance > 0:
		defense += (" " if defense != "" else "") + "Res:" + str(physical_resistance) + "%"
	if defense != "":
		lines.append(defense)
	lines.append("Stance:Parry" if defensive_option == 0 else "Stance:Dodge")
	if is_prone:
		lines.append("[PRONE]")
	if max_ammo > 0:
		lines.append("Ammo:" + (str(ammo) if ammo > 0 else "Empty"))
	health_bar.text = "\n".join(lines)
