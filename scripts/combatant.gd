extends CharacterBody3D
class_name Combatant
## Base class for all combatants (player- and AI-controlled).
## Holds the shared stats, grid movement, defense/damage, equipment sockets,
## animation and health-bar logic. Player and Enemy extend this and add only
## their control-specific behaviour (input vs AI).

const GRID_SIZE := 2.0
## Fallback play bound, used only when there is no DungeonRoom to ask — see _is_in_arena.
## A square, which is what "the arena" used to mean, back when the level WAS one square room.
const ARENA_MIN := -14.0
const ARENA_MAX := 14.0

## Cap on a single move while exploring. Not a budget — there is no clock out of combat — just
## a ceiling that keeps the BFS bounded. See get_move_range.
const EXPLORE_MOVE_RANGE := 40

## Collision layers used by ray queries.
const LAYER_GROUND := 1
const LAYER_ENEMY := 2
const LAYER_OBSTACLE := 4
const LAYER_PLAYER := 8              ## player-controlled combatants (assigned in _ready)
## Pointer-only layer: bodies that exist so a fitting can be CLICKED where it is drawn, and for
## nothing else. Deliberately absent from every other mask in the game — a picker must not block
## a step, stop an arrow or break a line of sight, or it would be scenery instead of a hit box.
## See Door._build_picker and Player._resolve_at.
const LAYER_INTERACT := 16
## Line-of-sight mask. MUST contain both combatant layers: _has_line_of_sight_from asks
## "did the ray reach the target before anything else", so the target's own layer has to
## be in the mask or the ray sails straight through it and the check can never pass.
## Players used to sit on the default layer 1, which this mask omitted — so every AI
## line-of-sight test against a hero returned false and the archer never took a shot.
const LAYER_LOS_BLOCKERS := 14       ## enemy (2) + obstacle (4) + player (8)

## Height above the body's origin that movement / line-of-sight rays are cast at.
const EYE_HEIGHT := 0.5

## Where a projectile is spawned relative to the hand holding the weapon: up towards the staff
## head or the nocking point, then forward so it clears the shooter's own model. Shared by the
## Firebolt and the bow (see get_projectile_origin).
const PROJECTILE_ORIGIN_LIFT := 0.30
const PROJECTILE_ORIGIN_REACH := 0.25

## Where a projectile is aimed on the target, above its body origin. That origin already sits
## at about chest height, so this is a nudge onto the sternum rather than a real offset. Doubles
## as where a wound bleeds from, since that is the same place.
const PROJECTILE_IMPACT_HEIGHT := 0.12

## Damage worth a full-strength blood splash. Everything scales off it, so a 2-point scratch
## spatters and a 12-point crit really opens someone up. Set near a solid hit rather than near
## the maximum: most blows should look like an ordinary wound, not a restrained one.
const BLOOD_REFERENCE_DAMAGE := 7.0

## Damage worth a full-size sword arc, and how long the attack animation winds up before the
## blade is actually travelling. The delay is visual only — see _swing_arc.
const SWING_REFERENCE_DAMAGE := 7.0
const SWING_WINDUP := 0.14

## Attacker skill worth a full-size shower of parry sparks. Skill rather than damage, because
## a parried blow never rolls its damage — see _parry_sparks.
const PARRY_REFERENCE_SKILL := 10.0

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

## Bonus to a Protection-stance parry roll. Melee only, on purpose: planting your feet and
## keeping the guard up is worth something against a blade in front of you and nothing at all
## against an arrow, which is what stops Protection being the strictly-best stance.
const GUARD_PARRY_BONUS := 2

## Reach of a Protection-stance guardian's zone, in tiles. One square by default, which is
## exactly the ring _is_adjacent already covers — so an enemy stopped at the edge of the zone
## is, by definition, already within the guardian's melee reach and he within its. Exists as a
## constant so a polearm could widen it without touching the logic.
const GUARD_RADIUS := 1

## Movement is divided by this while guarding — planted feet. Floored at 1 in get_move_range(),
## so holding a line never leaves a character genuinely stuck.
const GUARD_MOVE_DIVISOR := 2

## Dual-wield free off-hand attack (see _do_melee_attack).
const OFFHAND_HIT_PENALTY := 5    ## to-hit penalty for the off-hand strike (0 with dual_wield_skill)
const OFFHAND_DELAY := 0.3        ## beat between the main hit and the off-hand follow-up

## Sound family (ItemResource.WeaponSound) of the hand currently mid-strike, or -1 for a hand
## with no weapon in it. Set at the top of each melee strike and read back by everything the
## blow sets off — the whoosh, the parry clang, the wound — because those fire from three
## different places (_swing_arc here, _parry_sparks and take_damage on the DEFENDER) and only
## the attacker knows which of its two hands is swinging. Kept as state rather than threaded
## through take_damage: what a weapon sounds like is no business of the damage rules.
var _swing_sound: int = -1

## Shortest gap between two lines from the same throat, in seconds. Sized just over
## OFFHAND_DELAY: a dual-wielder's main and off-hand strikes land 0.3 s apart and would
## otherwise have both the attacker grunt and the defender cry out twice over themselves on
## every single attack. One gate for grunts, cries and battle cries alike, because a character
## has one voice and everything they might say competes for it.
const VOICE_GAP := 0.45
var _last_voice_ms: int = -100000

## A charge is a once-a-fight thing. Without this every enemy would bellow on every turn it
## spent walking, which is most turns, and the moment they first come at you would be worth
## nothing.
var _has_charged := false

## What a hit is made of, which decides which defences apply to it (see _calculate_damage).
## PHYSICAL is the default everywhere, so every existing blade, arrow and shove keeps behaving
## exactly as it did; only something that explicitly asks for another type gets other rules.
enum DamageType { PHYSICAL, FIRE }

## Hit points per point of stamina. Set so the old hand-authored totals fall out of whole
## stamina scores: 4 stamina = the 20 hp a hero used to be given outright, 6 = the boss's 30.
const HP_PER_STAMINA := 5

## Mana per point of willpower, matching HP_PER_STAMINA so the two pools read on one scale.
## Only characters with `can_cast` get a pool at all; for everyone else it is 0.
const MANA_PER_WILLPOWER := 5

## Defence debt per point of stamina — how many ticks of "already spent reacting" a character
## can carry before the guard drops (see defense_debt / is_overwhelmed). Stamina because this
## is endurance, the same attribute behind HP_PER_STAMINA.
##
## At 1 the cast reads boss 6, hero 4, wizard 3, goblin 2. Kept here after playtesting: a
## guard drops after only a handful of reactions, which reads as a real limit on how much one
## character can cover at once. Doubling it (boss 12, hero 8) puts the threshold out of reach
## in a four-enemy fight, because the advancing clock drains debt about as fast as parries and
## interceptions add it — the mechanic technically works but never visibly fires.
const DEBT_PER_STAMINA := 1
## How near the limit counts as strained. Only the initiative readout uses it, to warn amber
## before the guard actually drops rather than after.
const DEBT_WARN_MARGIN := 2

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
## Shooting at someone lying down: a much smaller silhouette, and a still one behind whatever
## is on the floor between you.
##
## Just under the scrum penalty, because a prone man is a hard shot but not as hard as a moving
## gap between two people. MISSILES ONLY — being down is still a disaster in melee, where the
## dodge penalty in _attempt_defense goes on applying. A trip is now a genuine trade rather
## than a strict win: it wrecks its victim at arm's length and shelters them from the archers.
const PRONE_TARGET_PENALTY := 4

## Time to get back on your feet. Going DOWN is free — dropping is not something you have to
## find time for — but getting up is a real part of a turn, and paying for it is what makes
## lying down a decision rather than a permanent upgrade against archers.
const STAND_UP_COST := 1

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
## Which of voice_sfx.gd's voice sets this character speaks with — "male_a" through "male_d",
## "female_a", "female_b". A string rather than an enum so it reads as itself in a scene diff;
## an unrecognised one falls back to the default with a warning rather than going silent.
@export var voice: String = "male_a"
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
## No dodge_skill: dodging is agility (see get_dodge_skill), so there is one number to tune
## rather than two that can contradict each other.
## Ids are load-bearing and append-only — see Stance for the catalogue and the warning.
@export_enum("Parry", "Dodge", "Protection") var defensive_option: int = 0
@export var shove_skill: int = 5
@export var trip_skill: int = 4
@export var shove_cost: int = 2
@export var trip_cost: int = 2
@export var dual_wield_skill: bool = false  ## trained off-hand: no -5 penalty on the free off-hand attack
@export var ranged_skill: int = 3       ## used for bow/distance attacks
@export var ranged_cost: int = 3
@export var ammo: int = 0
@export var max_ammo: int = 0
## What the arrows still in a quiver become when their owner dies — see _gather_spare_arrows.
const ARROW_BUNDLE_ITEM := "res://resources/items/arrow_bundle.tres"
## Moving quietly, and hearing somebody who is. See CombatantStats for what the numbers mean
## and roll_stealth / is_unheard_by for how they meet.
@export var stealth_skill: int = 3
@export var perception_skill: int = 7
## What an unremarkable attribute is: CombatantStats defaults every one of them to this, so it
## is the line an attribute is above or below rather than a number of its own. Read by
## get_stealth_skill to turn agility into a bonus.
const AVERAGE_ATTRIBUTE := 3
@export var throw_skill: int = 3        ## used for thrown weapon attacks
## One time unit — a throw is a single quick action, cheaper than a bow shot (which has to
## be nocked and drawn) and cheaper than a melee exchange. Note you also give up the weapon,
## so the real price is fetching it back off the floor.
@export var throw_cost: int = 1
@export var equip_cost: int = 1         ## time cost to swap equipped weapon/shield
## Time to work a door, a chest or a lever. One tick: cheaper than a swing, because throwing a
## door open is not meant to be a decision — it is meant to be the thing you do on the way.
@export var interact_cost: int = 1
## Trade skill, not a combat one: added to a 1-5 roll against a lock's difficulty.
##
## ZERO MEANS UNTRAINED, and untrained does not roll at all — a character with no idea how a
## lock works does not get lucky with one. That is what keeps a locked chest a real obstacle
## rather than a delay everybody eventually passes.
@export var lockpick_skill: int = 0

## Whether this character can cast at all. Off by default, so only a character explicitly
## marked a caster gets a mana pool or any spell power — willpower is a universal attribute,
## and gating on the capability rather than on the attribute is what keeps a stubborn goblin
## stubborn without also making it a sorcerer. A non-caster reports 0 for both.
@export var can_cast: bool = false
## Time units a spell takes. Spells also cost mana, which is per-spell (see the ability), so
## this is only the tempo half of the price.
@export var spell_cost: int = 3

## Whether this character may take the Protection stance at all (Stance.PROTECTION). Off by
## default and gated on the capability rather than on what happens to be in hand, exactly as
## can_cast gates spellcasting: a wizard who picks up a shield is still no line-holder. The
## stance also needs a weapon or shield to actually DO anything, but that is checked when the
## defence resolves, not when the stance is chosen.
@export var can_guard: bool = false

## Core attributes. Reach is deliberately NOT here: how far a weapon throws or shoots is a
## property of the weapon, so ranged_range / throw_range live on ItemResource and are read
## through get_ranged_range() / get_throw_range().
##
## Each attribute that drives something drives it EXCLUSIVELY — there is no separate trained
## value alongside it, so a nimble character cannot also be a poor dodger and a tough one
## cannot be short of hit points. Anything derived is computed in _derive_stats() or a
## get_*() accessor rather than stored twice.
##
## `intelligence` and `charisma` are the two that still drive nothing; they are carried and
## shown so the sheet has a complete block.
@export_group("Attributes")
## Shove distance and knock-back resistance (_try_shove / _apply_push).
@export var strength: int = 3
## The dodge roll, one-for-one (get_dodge_skill).
@export var agility: int = 3
## Max hit points, HP_PER_STAMINA each (_derive_stats).
@export var stamina: int = 3
@export var intelligence: int = 3
## Spell power (get_spell_power) and the mana pool, MANA_PER_WILLPOWER each (_derive_stats).
@export var willpower: int = 3
@export var charisma: int = 3
## Body mass, used by shove and trip rather than shown as an attribute.
@export var weight: int = 2

var next_turn_at: int = 0
## What next_turn_at was set to by the ACTION this character took, before any defending.
## CombatManager.turn_done stamps it; defense_debt() subtracts it back out. See there for why.
var action_turn_at: int = 0
var is_prone: bool = false
## Whether this character is deliberately moving quietly. A standing choice rather than a
## per-move one — see set_sneaking and SneakAbility — so the player picks it once and every step
## after is rolled for.
var sneaking: bool = false
## The last stealth roll made, and so how quiet this character's current move turned out to be.
## Meaningless unless `sneaking`. See roll_stealth.
var _stealth_roll: int = 0
## An animation held on purpose while nothing else is happening — see hold_pose. Empty means
## the usual walk/idle driver has the character.
var _held_pose := ""

var is_moving := false
var target_position := Vector3.ZERO
## Remaining waypoints for a routed move (set by _follow_path); empty = single hop.
var _move_path: Array = []
## Tiles the move in progress covers, recorded when the route is queued and read by
## get_move_cost() to price the move by distance. Zero when nothing is moving.
var _move_tiles: int = 0
## Who this move was aimed at, or null for a move aimed at a tile rather than a combatant
## (every player move, and an archer repositioning). Read only by _clip_at_guard, to tell a
## unit that walked INTO a guardian on purpose from one that was going somewhere else and got
## stopped. Set at each move initiation site, never left stale.
var _move_intent: Node = null

## Emitted whenever hp / max_hp / is_alive change, so HUD elements (the party
## portraits) can refresh without polling. Fired from _update_health_bar(),
## which every damage and heal path already funnels through.
signal health_changed(hp: int, max_hp: int, is_alive: bool)

var hp := 20
var max_hp := 20
## Spell resource, derived from willpower in _derive_stats() and 0 for anyone without
## `can_cast`. Spend it through spend_mana() so nothing has to remember to clamp.
var mana := 0
var max_mana := 0
var attack_dmg := 4
var is_alive := true

## Metres of air between the crown of a character's head and the bottom of their health bar.
##
## The same for everybody, which is the point: these models differ by half a metre — the Boss
## tops out at world 1.67 and the Hero at 1.17 — so a fixed HEIGHT put one bar a hand's width
## over its owner and another three times that. Measured per character instead, and this is the
## one number that decides how the whole floating cluster sits.
const HEAD_CLEARANCE := 0.25
## And between the bar and the nameplate above it. The bar is about 0.11 tall, so this leaves
## them near enough to read as one label.
const PLATE_OVER_BAR := 0.32

## How far out a part of a helmet has to reach to count as the part that WRAPS the head, rather
## than the part that only decorates it, as a fraction of the helmet's own half-width. A brow
## band reaches the full width and a crest does not, and this is the line between them — see
## _model_core, its one caller.
const HELMET_CORE_WIDTH := 0.6

## The stance this character was configured with, captured before play starts. Restored when
## Protection is broken — see _lay_prone. Never Protection itself: that one has to be chosen.
var _default_stance: int = Stance.PARRY

## Emitted when this corpse's loot changes, so an open loot window repaints. Named to match
## LootContainer's, because the loot window talks to both through the same three methods.
signal contents_changed

## What is left on the body, once there is a body. Array[ItemResource], filled by _die from
## whatever this character was carrying — see _gather_corpse_loot.
##
## Named `contents` rather than something more descriptive because that IS the name: it is the
## property loot_ui.gd reads, and a corpse and a chest have to answer to the same one or the
## window would need to know which it was looking at.
var contents: Array = []

## Last measured crown height, in local space. Kept so the labels are only moved when the
## silhouette actually changed — putting a helmet on is worth a re-measure, taking a hit is not.
var _crown_y := INF

var health_bar: Label3D
## The hit-point bar over this character's head. Built at runtime rather than placed in the
## scene — see health_bar_3d.gd.
var hp_bar: Node3D
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
const ArrowProjectileScript := preload("res://scripts/fx/arrow_projectile.gd")
const BloodSplashScript := preload("res://scripts/fx/blood_splash.gd")
const SwordSwingScript := preload("res://scripts/fx/sword_swing.gd")
const ParrySparksScript := preload("res://scripts/fx/parry_sparks.gd")
const WeaponSfxScript := preload("res://scripts/fx/weapon_sfx.gd")
const HealthBar3DScript := preload("res://scripts/health_bar_3d.gd")
const HealBurstScript := preload("res://scripts/fx/heal_burst.gd")
const VoiceSfxScript := preload("res://scripts/fx/voice_sfx.gd")

var _weapon_socket = null
var _shield_socket = null
var _helmet_socket = null
## The head a helmet has to fit, as an AABB in HelmetSocket space. Measured once by
## _measure_head, before anything is hanging off the bone to be measured as part of it. A zero
## size means this rig had no head mesh to measure, and helmets are then placed exactly as the
## item asks — see _fit_helmet_to_head.
var _head_bounds := AABB()
## This rig's head geometry, found once at setup. Switched off while a helmet is worn — see
## _show_bare_head.
var _head_meshes: Array = []
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

## Traces every routed move against the guard zones: whether the route met one, at which step,
## who the mover was aimed at, and whether that counted as an interception. Worth switching on
## again if interceptions ever stop firing when they look like they should.
const DEBUG_GUARD := false

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
	hp_bar = HealthBar3DScript.build(self)
	_place_floating_labels()
	inventory = get_node_or_null("Inventory")
	_apply_stats()
	# After the stat block has had its say, so it is the character's real starting stance and
	# not the export default. Protection is not a fallback — a guardian knocked down falls back
	# to fighting, not to guarding from the floor.
	_default_stance = defensive_option if defensive_option != Stance.PROTECTION else Stance.PARRY
	_readd_equipment_bonuses()
	_pre_setup()
	# After both the stat block and the subclass hook have had their say, so it derives from
	# the attributes this character actually ended up with.
	_derive_stats()
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
	# No max_hp here — it is derived from stamina by _derive_stats().
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
	defensive_option = s.defensive_option
	ranged_skill = s.ranged_skill
	ranged_cost = s.ranged_cost
	ammo = s.ammo
	max_ammo = s.max_ammo
	stealth_skill = s.stealth_skill
	perception_skill = s.perception_skill
	throw_skill = s.throw_skill
	throw_cost = s.throw_cost
	can_cast = s.can_cast
	can_guard = s.can_guard
	spell_cost = s.spell_cost
	strength = s.strength
	agility = s.agility
	stamina = s.stamina
	intelligence = s.intelligence
	willpower = s.willpower
	charisma = s.charisma
	weight = s.weight
	equip_cost = s.equip_cost


func _derive_stats() -> void:
	## Fill in the values that are computed from attributes rather than authored. Runs for
	## everyone, stat block or not, so a scene-configured player and a .tres-configured enemy
	## get the same treatment.
	##
	## Both pools are set to full here. That is fine at spawn but means this must NOT be called
	## again mid-fight, or changing an attribute would heal and refill as a side effect.
	max_hp = maxi(1, stamina * HP_PER_STAMINA)
	hp = max_hp
	max_mana = maxi(0, willpower * MANA_PER_WILLPOWER) if can_cast else 0
	mana = max_mana


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
	for slot in ["right_hand", "left_hand", "armor", "helmet", "legs"]:
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


func _lay_prone(announce: bool = true) -> void:
	## Get knocked down (tripped / shoved off balance): drop to the prone pose. Getting up
	## is a separate action charged at the unit's next turn (_stand_up_if_prone).
	##
	## `announce` is false for a character lying down of its own accord with nobody watching —
	## see lie_down_quietly. Being knocked off your feet is news; having a doze is not.
	if is_prone:
		return
	is_prone = true
	if announce:
		_show_condition_text("PRONE!")
	# Protection is a stance you hold on your feet. Knocked off them, the character drops back
	# to whatever they fight as normally rather than nominally guarding a line from the floor.
	#
	# The stance has to actually CHANGE, not merely stop working: is_guarding() already refused
	# while prone, so the zone and its aura went — but the stance itself stayed Protection, and
	# with it the melee parry bonus (see _attempt_defense) and the word "Protection" on the
	# toolbar. The picture said the guard was broken and the numbers said it was not.
	if defensive_option == Stance.PROTECTION:
		defensive_option = _default_stance
		_show_condition_text("Guard broken!")
		# The stance cell on the toolbar is painted from defensive_option; without this it goes
		# on advertising a stance this character is no longer in.
		get_tree().call_group("action_toolbar", "refresh")
	_update_health_bar()
	_update_prone_anim()


func toggle_prone() -> void:
	## Drop, or get up. The player's Prone action; the AI still stands automatically at the top
	## of its turn (see Enemy.enable_turn).
	##
	## Going down routes through _lay_prone so it breaks a Protection stance exactly as being
	## knocked down does: choosing to lie in a doorway must not be a way to hold the line from
	## the floor.
	if is_prone:
		is_prone = false
		_show_condition_text("Stood up")
		_update_health_bar()
		_update_prone_anim()
	else:
		_lay_prone()


func lie_down_quietly(down: bool) -> void:
	## Lie down, or get up, with no caption and nothing charged: the idle-time twin of
	## toggle_prone.
	##
	## Quiet because a goblin dozing in a corner before anybody has walked into the room is not
	## a combat event, and "PRONE!" floating over it reads as one. Uncharged because there is no
	## clock in exploration to charge — see CombatManager.is_exploring — while the same goblin
	## getting up once the alarm goes IS billed, by _stand_up_if_prone on its first turn, which
	## is the price of having been caught lying down.
	if is_prone == down:
		return
	if down:
		_lay_prone(false)
		return
	is_prone = false
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
	# Before the sockets exist, so a helmet already hanging off one can never be measured as
	# part of the head it is supposed to fit.
	_head_meshes = _find_head_meshes(skeleton)
	_head_bounds = _measure_head(skeleton, _head_meshes)
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


func _find_head_meshes(skeleton: Skeleton3D) -> Array:
	## This rig's head geometry, by mesh name — which is how these rigs ship a head (a separate
	## "head-mesh" under the skeleton), and the same lookup tools/build_soldier_helmet.gd uses
	## to cut one up.
	var out: Array = []
	var meshes: Array = []
	_find_mesh_instances(skeleton, meshes)
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh != null and String(mi.name).to_lower().find("head") >= 0:
			out.append(mi)
	return out


func _measure_head(skeleton: Skeleton3D, heads: Array) -> AABB:
	## The head's own bounds in head-bone space — what a helmet has to sit on. A zero AABB for a
	## rig with no head bone or no head mesh, which the caller reads as "do not fit".
	var bone := skeleton.find_bone("head")
	if bone < 0:
		return AABB()
	var to_bone := skeleton.get_bone_global_pose(bone).affine_inverse()
	var out := AABB()
	var first := true
	for m in heads:
		var mi := m as MeshInstance3D
		var a: AABB = to_bone * (_xform_within(mi, skeleton) * mi.mesh.get_aabb())
		out = a if first else out.merge(a)
		first = false
	return out


func _show_bare_head(shown: bool) -> void:
	## A helmet REPLACES the head's surface rather than covering it.
	##
	## Geometry cannot do that job on its own, and four rounds of trying say so. This helmet is
	## a human-shaped shell and these rigs have a cube for a head, so whatever the scale and
	## seating, some corner of the cube is outside the shell: fitted to cover the face it left
	## the back of the head bare, and made deep enough to cover the back it sat behind the head
	## instead. Measured, the shell's rear wall passes THROUGH the skull at ear height, 0.08 to
	## 0.11 in FRONT of the head's own back face — which is scalp showing from behind, at any
	## placement.
	##
	## So the head is switched off while a helmet is on, which is what the split it was built
	## with was always for: tools/build_soldier_helmet.gd cut the soldier's head into a helmet
	## and a repainted bare skull so that the helmet could come OFF, and the skull is the
	## helmetless case. Nothing is lost that a helmet was not hiding anyway — and see
	## _show_helmet_interior for what is behind the visor once the face is gone.
	for m in _head_meshes:
		if is_instance_valid(m):
			(m as MeshInstance3D).visible = shown


func _show_helmet_interior(model: Node3D) -> void:
	## Draw a worn helmet from the inside as well as the outside.
	##
	## With the head switched off there is nothing behind the visor, and Godot culls back faces:
	## every gap in the grille would look straight through the character at the dungeon behind
	## it. Double-sided, those gaps look into the helmet instead, which comes out dark — the
	## faces they land on are pointing away from the light — and a dark slot is what a visor is.
	##
	## On a COPY of the material, never the pack's own: one material is shared by every
	## character in the set, and flipping it there would turn the goblins inside out too.
	var meshes: Array = []
	_find_mesh_instances(model, meshes)
	for m in meshes:
		var mi := m as MeshInstance3D
		var flipped := mi.get_active_material(0)
		if flipped == null:
			continue
		var copy := flipped.duplicate() as BaseMaterial3D
		if copy == null:
			continue
		copy.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = copy


func _xform_within(node: Node3D, root: Node3D) -> Transform3D:
	## `node`'s transform relative to `root`, EXCLUDING root's own — identity when they are the
	## same node.
	var t := Transform3D.IDENTITY
	var n: Node3D = node
	while n != null and n != root:
		t = n.transform * t
		n = n.get_parent() as Node3D
	return t


func _model_mesh_xform(mi: MeshInstance3D, model: Node3D) -> Transform3D:
	## A mesh's place inside an item model, in socket axes: the item's own rotation, then the
	## mesh's own offset within the model, and NOT the scale or offset instantiate_model left on
	## the top node — both of which a fit is about to replace.
	return Transform3D(model.basis.orthonormalized(), Vector3.ZERO) * _xform_within(mi, model)


func _model_bounds(model: Node3D) -> AABB:
	## Everything the model is, as one box in socket axes.
	var meshes: Array = []
	_find_mesh_instances(model, meshes)
	var out := AABB()
	var first := true
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var a: AABB = _model_mesh_xform(mi, model) * mi.mesh.get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out


func _model_core(model: Node3D, bounds: AABB) -> AABB:
	## The bounds of the part of a helmet that WRAPS a head, as against the part that merely
	## decorates it. Empty when there is nothing to measure, which the caller reads as "no
	## separate depth fit".
	##
	## Told apart by width, because that is what tells them apart: a brow band and a dome are as
	## wide as the helmet gets, while a crest or a plume is a narrow strip laid along it. So the
	## core is every vertex out past HELMET_CORE_WIDTH of the half-width — which on the Synty
	## helm keeps a dome reaching 0.126 either side of the centreline and drops a crest that
	## never passes 0.068, while that crest is carrying 37% of the whole model's depth.
	##
	## Vertices rather than bounding boxes, because a box drawn round a helmet AND its crest
	## cannot afterwards be asked which part of it was the crest. Read once, when the helmet is
	## put on.
	var limit: float = bounds.size.x * 0.5 * HELMET_CORE_WIDTH
	var mid_x: float = bounds.get_center().x
	var meshes: Array = []
	_find_mesh_instances(model, meshes)
	var out := AABB()
	var first := true
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var t: Transform3D = _model_mesh_xform(mi, model)
		for si in range(mi.mesh.get_surface_count()):
			var arrays: Array = mi.mesh.surface_get_arrays(si)
			if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			for v in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				var p: Vector3 = t * v
				if absf(p.x - mid_x) < limit:
					continue
				out = AABB(p, Vector3.ZERO) if first else out.expand(p)
				first = false
	return out


func _fit_helmet_to_head(model: Node3D, item: ItemResource) -> void:
	## Size and seat a helmet on the head it is going on, instead of trusting the item's own
	## numbers to land it.
	##
	## Two coordinate systems meet at this socket and neither is negotiable. A helmet mesh is
	## cut off whatever character the art pack modelled it on — the Synty knight stands 1.87
	## units tall with his helm up at y=1.65 — while the socket is a bone on OUR rig, where a
	## head is about a third of a unit across and sits at the bone's origin. model_scale cannot
	## bridge that, because it is also the size the item is drawn at on the floor and in the
	## bag, and one number cannot be both: at the 0.3 that suits the floor, the knight's helm
	## arrived scaled to 47% and a clear two head-heights above the crown.
	##
	## So the floor and the bag keep model_scale, and the head measures for itself.
	##
	## SCALE makes the helmet exactly as WIDE as the head. Width against width, and not the
	## longest side of either: the helmet's longest side is a crest trailing behind the skull,
	## and scaling that to fit a head is what left a thimble on top of one.
	##
	## Width is the measurement that decides whether this reads as a helmet at all, because it
	## is the head's whole silhouette from the front. Matching the head's DEPTH instead — on the
	## theory that a skull is as wide as it is deep, and that the head's own width is inflated by
	## ears a helmet need not cover — came out a quarter too narrow and sat on the head like a
	## cap with the ears and temples still showing. These rigs have a CUBE for a head, wider
	## than it is deep, and the ear tabs are part of its outline rather than something a helmet
	## can be excused from covering.
	##
	## DEPTH is then fitted SEPARATELY, and it has to be: no single number puts this helmet on
	## this head. The head is a cube a third wider than it is deep; the helmet is human-shaped
	## and half again deeper than it is wide, a 2:1 disagreement. Scaled by one number, matching
	## the width leaves it three times too deep — the dome and crest trailing away behind a
	## forehead that pokes out the front of them, which is what "too far back" was — and
	## matching the depth leaves it half the head's width, which was "too small".
	##
	## So the part of the helmet that WRAPS the head is squashed to the head's own depth, and
	## the crest comes along for the ride and trails whatever is left. See _model_core for how
	## the one is told from the other. The helmet is a squashed copy of itself from the side, by
	## about half; on rigs whose heads are boxes that is what fitting one means, and the front
	## view — the one the player is looking at — keeps the proportions the artist drew.
	##
	## SEATING puts the two vertical CENTRES together — centres, not bottoms.
	##
	## Sitting the helmet's lowest point on the head's lowest point is the obvious rule and it
	## rides far too high, because this helmet is twice the height of the head: crest above,
	## chin guard below, so resting it on the jaw lifts the eye slit clear over the crown.
	## Measured, the slit landed at y=0.340 with the head's eyes at 0.113 — a visor above the
	## top of the head. Centring lands it at 0.128, inside the eye band of 0.058..0.168.
	##
	## Both of those anchors were measured off the art rather than guessed: the slit is the ten
	## near-black triangles across the front of the helm and the eyes are the fourteen on the
	## head, each found by sampling that pack's atlas through the triangle's own UV — the trick
	## tools/build_synty_armor.gd uses to tell goblin hide from the straps worn over it. They
	## are not consulted here, because opening a texture to hang a hat would be a poor trade;
	## they are what says this rule is right, and what to re-measure with if a helmet looks off.
	##
	## In z the WRAPPING part is front-aligned on the face, which — now that it is also as deep
	## as the head — puts it around the head instead of behind it. The visor comes out flush
	## with the face it covers rather than floating ahead of it, and what is left over goes
	## backwards and upwards, which is where a crest belongs and what the nameplate re-measures
	## the crown for.
	##
	## model_hand_position stays live on top of the fit, as a nudge for an item that wants one.
	if _head_bounds.size == Vector3.ZERO:
		return
	var bounds: AABB = _model_bounds(model)
	if bounds.size.x < 0.001 or _head_bounds.size.x <= 0.0:
		return
	var s: float = _head_bounds.size.x / bounds.size.x
	# The squash has to line up with the helmet's own front-to-back axis, and model.scale is
	# applied before the node's rotation. A helmet asking to be turned in the socket would get
	# it along the wrong axis, so that one keeps a plain uniform scale. None asks yet.
	var core: AABB = _model_core(model, bounds)
	var sz: float = s
	if core.size.z > 0.001 and _head_bounds.size.z > 0.0 \
			and item.model_hand_rotation.is_zero_approx():
		sz = _head_bounds.size.z / core.size.z
	else:
		core = bounds
	model.scale = Vector3(s, s, sz)
	model.position = Vector3(
		-bounds.get_center().x * s,
		_head_bounds.get_center().y - bounds.get_center().y * s,
		_head_bounds.end.z - core.end.z * sz) + item.model_hand_position


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
	# The helmet does not sit over the head, it stands in for it — see _show_bare_head.
	_show_bare_head(helmet_item == null)


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
			# A hand is a hand whatever it holds, so a weapon lands where the item says. A head
			# is a measurable thing a helmet has to FIT, so a helmet is fitted to it instead.
			if socket == _helmet_socket:
				_fit_helmet_to_head(model_node, item)
				_show_helmet_interior(model_node)
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


func _step_blocked_by_wall(from_tile: Vector3, to_tile: Vector3,
		ignore: Array[RID] = []) -> bool:
	## True if a wall (obstacle-layer collision) lies on the edge between two adjacent
	## tiles. Used per-step by _find_path so routes can't cross walls but pass freely
	## through the collision-free doorway. Combatants (layer 2) are ignored here.
	##
	## `ignore` drops named bodies from the cast, and exists for one caller: _is_side_solid
	## needs to know whether a WALL seals an edge while a pillar happens to be standing in
	## the cell beyond it. See there — nothing else should need it.
	var space_state := get_world_3d().direct_space_state
	var from_pos := Vector3(from_tile.x, position.y + EYE_HEIGHT, from_tile.z)
	var to_pos := Vector3(to_tile.x, position.y + EYE_HEIGHT, to_tile.z)
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.collision_mask = LAYER_OBSTACLE
	var excluded: Array[RID] = [get_rid()]
	excluded.append_array(ignore)
	query.exclude = excluded
	return not space_state.intersect_ray(query).is_empty()


func _is_corner_blocked(from_tile: Vector3, to_tile: Vector3) -> bool:
	## True when a DIAGONAL step would squeeze between two cells that are SEALED — filled
	## edge to edge, the way a wall or the throne's slab is. Rounding a single obstacle's
	## corner (one side free) stays legal, so units keep their diagonal mobility. Cardinal
	## steps always return false.
	##
	## The per-step wall ray can't catch this on its own. Cast between the two cell centres,
	## a diagonal ray passes a comfortable 1.4 units clear of anything standing in either
	## flanking cell, so it reports a gap even where two slabs meet at their corners with no
	## gap at all. Testing the two flanking cells instead is what closes that.
	##
	## What counts as sealed is the flanking cell's own business, NOT merely whether
	## something stands in it — see _is_side_solid. A pillar owns its square and still leaves
	## room to walk past, which is the case this used to get wrong: the eight arena pillars
	## sit in diagonally-touching PAIRS — (5,3)+(3,5) and its three mirrors — and cutting
	## between a pair was refused even though the gap between the two stones is nearly two
	## units of open floor.
	##
	## Only static geometry counts here; units still slip diagonally past each other.
	if abs(to_tile.x - from_tile.x) < 0.5 or abs(to_tile.z - from_tile.z) < 0.5:
		return false
	var side_a := Vector3(to_tile.x, from_tile.y, from_tile.z)
	var side_b := Vector3(from_tile.x, from_tile.y, to_tile.z)
	return _is_side_solid(from_tile, side_a) and _is_side_solid(from_tile, side_b)


func _is_side_solid(from_tile: Vector3, side: Vector3) -> bool:
	## Whether the cell at `side` SEALS the corner that a diagonal step cuts past.
	##
	## A different question from _is_obstacle_at, which asks whether you may stand there, and
	## the distinction is the whole point: a pillar is half a metre of stone in the middle of
	## a two-metre square. It owns the square — you cannot stand in it — but it does not close
	## it, so two pillars meeting at their corners leave a gap a unit walks straight through.
	## A wall, a throne or a stone slab does fill its square, and those still seal.
	##
	## Obstacles declare which they are by answering fills_cell(); see _obstacle_fills_cell
	## for what silence means.
	var slim: Array[RID] = []
	for o in _obstacles_at(side):
		if _obstacle_fills_cell(o):
			return true
		_collect_body_rids(o, slim)
	# Nothing in the cell closes it, so only geometry on the EDGE can — a wall between here
	# and there, or a shut door. The slim props found above are dropped from that cast: a
	# pillar stands dead centre of its cell, so a ray aimed at that centre spears it every
	# time and would otherwise be mistaken for the wall it is standing in front of.
	return _step_blocked_by_wall(from_tile, side, slim)


func _collect_body_rids(node: Node, out: Array[RID]) -> void:
	## Every physics body at or under `node`, for excluding a prop from a ray.
	##
	## Recursive rather than just testing `node` itself, because an obstacle is not reliably
	## its own collider: a pillar IS a StaticBody3D, but the props RoomBuilder places are a
	## MeshInstance3D with the body hung underneath, and a LootContainer keeps its Blocker as
	## a child. Ask only the group member itself and the next slim prop to opt out would be
	## excluded in name only, its collider still spearing every ray aimed at its cell.
	if node is CollisionObject3D:
		out.append((node as CollisionObject3D).get_rid())
	for child in node.get_children():
		_collect_body_rids(child, out)


func _obstacle_fills_cell(o: Node) -> bool:
	## Whether an obstacle occupies its whole square or merely stands in the middle of it.
	##
	## Silence means it fills. That is the conservative answer and it is the right default for
	## everything that has never thought about the question — the reserved cells behind the
	## throne, a wall prop, a plain marker — so only the slim things have to opt out, and
	## forgetting to opt out costs a little mobility rather than letting units walk through
	## scenery.
	if o.has_method("fills_cell"):
		return o.fills_cell()
	return true


func _obstacles_at(tile: Vector3) -> Array:
	## Every member of the "obstacles" group whose cell is `tile`. The snapping matches
	## _is_obstacle_at exactly — an obstacle is placed at a position, not at a cell, and the
	## two have to agree on which cell that lands in.
	var out: Array = []
	for o in get_tree().get_nodes_in_group("obstacles"):
		if not is_instance_valid(o) or not (o is Node3D):
			continue
		var obs: Node3D = o
		var obs_tile := Vector3(
			(floor(obs.position.x / GRID_SIZE) + 0.5) * GRID_SIZE,
			tile.y,
			(floor(obs.position.z / GRID_SIZE) + 0.5) * GRID_SIZE)
		if obs_tile.distance_to(tile) < 0.5:
			out.append(obs)
	return out


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


func is_guarding() -> bool:
	## A planted guardian, holding the ring of tiles around them against anyone hostile.
	##
	## Every clause is a way the line can fail: dead or knocked prone, no weapon or shield to
	## hold it WITH (the same test a parry makes), or already overwhelmed — out of time to
	## react at all. That last one is what makes the shield wall crumble under a swarm instead
	## of holding forever; see is_overwhelmed.
	return is_alive and not is_prone \
		and defensive_option == Stance.PROTECTION \
		and (_has_usable_weapon() or _has_shield_equipped()) \
		and not is_overwhelmed()


func _in_guard_zone_of(guardian: Node, tile: Vector3) -> bool:
	## Chebyshev (king-move) reach, written out against GUARD_RADIUS rather than calling
	## _is_adjacent so that widening the zone stays a one-constant change. At radius 1 the
	## two are identical.
	var g: Vector3 = guardian._snap_to_grid(guardian.position)
	return max(abs(tile.x - g.x), abs(tile.z - g.z)) <= GRID_SIZE * (GUARD_RADIUS + 0.5)


func _guard_at(tile: Vector3) -> Node:
	## The ENEMY guardian whose zone covers `tile`, or null. Called on the mover, so "enemy"
	## means hostile to US — a guardian never blocks its own side, which is what lets allies
	## walk freely through a hero's zone.
	for c in get_tree().get_nodes_in_group("combatants"):
		if c == self or not is_instance_valid(c):
			continue
		if not _is_hostile(c):
			continue
		if not (c.has_method("is_guarding") and c.is_guarding()):
			continue
		if _in_guard_zone_of(c, tile):
			return c
	return null


func on_interception(mover: Node) -> void:
	## Called on the GUARDIAN when its zone actually turned someone aside — see _clip_at_guard
	## for what counts as "actually".
	##
	## The cost and the caption land on different characters, deliberately. The tick is the
	## guardian's: same price a successful parry pays, charged the same way, because it is the
	## same kind of expense — time spent reacting to someone else instead of acting. That is
	## also what feeds defense_debt, so a guardian holding off a crowd spends himself doing it
	## and is eventually overwhelmed, which drops his zone; interception and overwhelm are each
	## other's limiter.
	##
	## The label goes on the MOVER, because that is who was stopped and where the eye already
	## is. Parented to it, so it rides along as the unit finishes walking to the tile the clip
	## left it on.
	if mover != null and mover.has_method("_show_action_text"):
		mover._show_action_text("Blocked!")
	_charge_defense_cost()


func on_disengage(mover: Node) -> void:
	## A free swing at someone breaking out of our reach. Called on the GUARDIAN.
	##
	## It costs a tick, exactly as a parry and an interception do. Everything reactive in this
	## system is paid for out of the reactor's own next turn — that is what defense_debt IS —
	## and charging it keeps the swing inside the overwhelm limiter instead of being an
	## unbounded source of free damage. A guardian who has spent himself holding the line stops
	## getting them for nothing: is_guarding() goes false, and there is then no zone left to
	## break out of.
	if mover == null or not is_instance_valid(mover) or not mover.is_alive:
		return
	_show_action_text("Opportunity!")
	_face_target(mover)
	# Charged before the swing, so the tick lands even if the attack finishes the mover and
	# unwinds through _die().
	_charge_defense_cost()
	_do_melee_attack(mover)


func _tile_key(tile: Vector3) -> String:
	return str(int(round(tile.x))) + "," + str(int(round(tile.z)))


func _find_path(from_tile: Vector3, to_tile: Vector3, max_steps: int = -1,
		doors_openable: bool = false) -> Array:
	## BFS on the grid returning the shortest cardinal path [from .. to], routing around
	## walls, obstacles and EVERY other living combatant (allies included). The goal tile
	## stays passable so an enemy can still path onto its target's cell (the caller stops
	## short). Pass max_steps to bound search depth (players cap it at move_range).
	##
	## `doors_openable` answers a different question: not "where can I walk this turn" but
	## "where can I get to at all", counting a shut unlocked door as a step somebody could
	## spend a turn opening. Movement must leave it false — you cannot walk through a shut
	## door — and target-picking wants it true, or a party that shuts a door behind them stops
	## being anybody's problem.
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
			var is_goal: bool = nxt.distance_to(to_tile) < 0.5
			# Where somebody stands, and — see _claimed_by_mover — where somebody walking is
			# going to be. Routing through a square another unit has already claimed is what
			# let two idle enemies cross the same square and walk through one another; in
			# combat, where one unit moves at a time, there is never a claim to trip over.
			if not is_goal and (_get_combatant_at(nxt, self) != null
					or _claimed_by_mover(nxt, self)):
				continue
			if not _step_open(cur, nxt, doors_openable):
				continue
			visited[k] = true
			var new_path: Array = path.duplicate()
			new_path.append(nxt)
			queue.append(new_path)
	return []


func _openable_door_at(tile: Vector3) -> Node:
	## A door standing on `tile` that is shut but could be opened — something in the way now
	## that a turn spent on it would put out of the way. Null for an open door, a locked one,
	## or no door at all.
	for d in get_tree().get_nodes_in_group("interactables"):
		if not is_instance_valid(d) or not d.has_method("blocks_openably"):
			continue
		if not d.blocks_openably():
			continue
		var node := d as Node3D
		if node == null:
			continue
		# Snapped first, exactly as _is_obstacle_at does it. A door stands ON the wall line,
		# which is the boundary BETWEEN two squares — comparing its raw position against a
		# square's centre matches nothing, ever.
		var cell: Vector3 = _snap_to_grid(node.global_position)
		if absf(cell.x - tile.x) < 0.5 and absf(cell.z - tile.z) < 0.5:
			return d
	return null


func _step_open(cur: Vector3, nxt: Vector3, doors_openable: bool) -> bool:
	## Whether the SCENERY lets us step from `cur` to `nxt`. Units are the caller's business.
	##
	## `doors_openable` is the difference between "where can I walk" and "where can I get to".
	## A shut door is impassable to a move and a one-turn detour to a plan, and the two
	## questions want different answers from the same geometry.
	var door: Node = _openable_door_at(nxt) if doors_openable else null
	if door != null and (absf(nxt.x - cur.x) < 0.5 or absf(nxt.z - cur.z) < 0.5):
		# Cardinal step onto a door we could open: the door is the only thing in the way, so
		# say yes. Diagonals do NOT qualify — the jamb beside a doorway is still masonry, and
		# no amount of opening the door moves it.
		return true
	if _is_obstacle_at(nxt) and door == null:
		return false
	# Leaving a door's own square needs no special case: the ray starts inside the door's
	# collider, and Godot does not report a hit from inside a shape.
	return not (_step_blocked_by_wall(cur, nxt) or _is_corner_blocked(cur, nxt))


func _approach_field(goal_tile: Vector3, limit: int = 60) -> Dictionary:
	## Steps from `goal_tile` out to everywhere it can reach, by the same walls-and-obstacles
	## rules _find_path uses but IGNORING other units.
	##
	## Ignoring units is the point. This measures the shape of the DUNGEON, not the shape of
	## the queue standing in it — so a goblin still knows the doorway is the way to the hero
	## even while two of its friends are plugging it.
	var field: Dictionary = {}
	var start: Vector3 = _snap_to_grid(goal_tile)
	field[_tile_key(start)] = 0
	var queue: Array = [start]
	while not queue.is_empty():
		var cur: Vector3 = queue.pop_front()
		var d: int = field[_tile_key(cur)]
		if d >= limit:
			continue
		for dir in GRID_DIRS:
			var nxt: Vector3 = _snap_to_grid(cur + dir)
			var k: String = _tile_key(nxt)
			if field.has(k):
				continue
			# Doors count as passable here. The field is what tells a unit which way to walk,
			# and the way to somebody behind a shut door is TO that door — a field that stopped
			# at it would leave the unit milling about in the middle of the room instead.
			if not _step_open(cur, nxt, true):
				continue
			field[k] = d + 1
			queue.append(nxt)
	return field


func _approach_score(tile: Vector3, goal_tile: Vector3, field: Dictionary) -> float:
	## How good a place `tile` is to end up when heading for `goal_tile`. Lower is better.
	##
	## Steps through the dungeon where the field reached us, and straight-line distance plus a
	## penalty where it did not. The penalty is what makes ANY tile connected to the goal beat
	## EVERY tile that is not — and the straight-line fallback is what still points a unit at a
	## shut door when the goal is sealed off behind it, which is the one time walking at
	## something in a straight line is exactly the right idea.
	var k: String = _tile_key(tile)
	if field.has(k):
		return float(field[k])
	return 1000.0 + max(abs(tile.x - goal_tile.x), abs(tile.z - goal_tile.z)) / GRID_SIZE


func _find_approach_path(goal_tile: Vector3, max_steps: int) -> Array:
	## The best move available when there is no route to `goal_tile` at all: the path to
	## whichever reachable tile ends up CLOSEST to it, or [] when standing still is already as
	## close as we can get.
	##
	## _find_path answers "how do I get there" and gives up with nothing when the answer is
	## "you can't". That is the right answer for a route and the wrong one for a turn: a unit
	## that cannot reach its target should still be walking at it, not standing in the back
	## rank waiting for the crowd to clear.
	var start: Vector3 = _snap_to_grid(position)
	var field: Dictionary = _approach_field(goal_tile)
	var best_path: Array = []
	var best_score: float = _approach_score(start, goal_tile, field)

	var queue: Array = [[start]]
	var visited: Dictionary = {}
	visited[_tile_key(start)] = true
	while not queue.is_empty():
		var path: Array = queue.pop_front()
		var cur: Vector3 = path[path.size() - 1]
		if path.size() - 1 >= max_steps:
			continue
		for dir in GRID_DIRS:
			var nxt: Vector3 = _snap_to_grid(cur + dir)
			var k: String = _tile_key(nxt)
			if visited.has(k):
				continue
			visited[k] = true
			# NOT doors_openable: this one is a real move, and a shut door is a wall to it. The
			# field above already points us at the door; this walks us up to it.
			if _is_tile_occupied_by_others(nxt, self) or not _step_open(cur, nxt, false):
				continue
			var new_path: Array = path.duplicate()
			new_path.append(nxt)
			queue.append(new_path)
			# Strictly better, and BFS hands us shorter paths first, so of two tiles that get
			# equally close we take the one that costs less to walk to.
			var score: float = _approach_score(nxt, goal_tile, field)
			if score < best_score:
				best_score = score
				best_path = new_path
	return best_path


func _start_path_move(target: Vector3, intent: Node = null) -> void:
	## Begin a routed move to `target`: follow the BFS path waypoint-by-waypoint so the
	## unit walks around walls / enemies instead of sliding straight through them.
	##
	## `intent` is who we are crossing the floor to get AT, when there is somebody — a
	## move-and-attack passes their victim. Null for a plain move to a square, where nobody was
	## "come for". _clip_at_guard reads it to tell whether a guardian we end up beside is the
	## one we were after or merely in the way.
	_move_intent = intent
	var path: Array = _find_path(_snap_to_grid(position), target, get_move_range())
	if path.size() <= 1:
		# No route found (MoveAbility.can_target already pathed here, so this is a
		# belt-and-braces fallback). Slide straight over and charge it as one step.
		target_position = _snap_to_grid(target)
		_move_path = []
		_move_tiles = 1
		is_moving = true
	else:
		_follow_path(path)


func _clip_at_guard(path: Array) -> Array:
	## Walk a routed path against every hostile guard zone on it and decide where the move
	## really ends. Two distinct events, tested per step:
	##
	##   ENTERING the zone of a guardian we were not already engaged with ends the move on that
	##   tile. A hostile zone is a wall you may step INTO but never THROUGH, which is what stops
	##   anything crossing a guardian's reach in a single stride.
	##
	##   LEAVING the zone of a guardian who held us is a disengage: he gets a free swing
	##   (on_disengage) and we keep walking. Moving WITHIN his reach is neither event, so a unit
	##   can still circle him freely.
	##
	## Together those price a crossing at two turns and a free hit rather than forbidding it
	## outright. An earlier version pinned anyone standing in a zone completely still — which
	## left no exit for an opportunity attack to punish, and made the zone a cage rather than a
	## threat.
	##
	## Chosen over marking guarded tiles impassable inside _find_path: see the note there
	## about a route whose next step is blocked being trimmed to nothing, which freezes the
	## mover in place instead of rerouting it.
	if path.size() <= 1:
		return path
	var prev_guard: Node = _guard_at(path[0])
	for i in range(1, path.size()):
		var cur_guard: Node = _guard_at(path[i])

		if prev_guard != null and cur_guard != prev_guard:
			# Breaking away. Resolved before we clear the square, so the swing can drop us
			# mid-route — stop where we stand rather than walking a corpse to its destination.
			if DEBUG_GUARD:
				print("[guard] %s: breaks away from %s at step %d -> OPPORTUNITY" % [
					character_name, prev_guard.character_name, i])
			prev_guard.on_disengage(self)
			if not is_alive:
				return path.slice(0, i)

		if cur_guard != null and cur_guard != prev_guard:
			# Only a genuine redirect costs the guardian a tick, and the test is INTENT, not
			# path length. An earlier version asked "did the clip shorten the route?" — which
			# looks equivalent and is not. When a mover's intended destination already sits
			# inside the zone, the zone captures it without shortening anything: the boss
			# closing on the wizard from two tiles out gets exactly the tile it wanted and is
			# still turned aside, because the target lock makes it fight the guardian next turn.
			# That read as "route ended there anyway" and went uncharged and unannounced.
			#
			# So the question is who the mover was coming for: if it came FOR the guardian and
			# reached him, he is not holding anyone off, he is simply being attacked.
			var redirected: bool = _move_intent != cur_guard
			if DEBUG_GUARD:
				print("[guard] %s: %d-step route meets %s's zone at step %d (aimed at %s) -> %s" % [
					character_name, path.size() - 1, cur_guard.character_name, i,
					_move_intent.character_name if _move_intent else "a tile",
					"INTERCEPTED" if redirected else "came for the guardian, no charge"])
			if redirected:
				cur_guard.on_interception(self)
			return path.slice(0, i + 1)

		prev_guard = cur_guard
	if DEBUG_GUARD and path.size() > 1:
		# Distinguishes the two ways this can come up empty: nobody is holding a line, or
		# somebody is and this route simply never touched it.
		var active := 0
		for c in get_tree().get_nodes_in_group("combatants"):
			if is_instance_valid(c) and _is_hostile(c) and c.has_method("is_guarding") and c.is_guarding():
				active += 1
		print("[guard] %s: %d-step route, no guarded tile on it (hostile guardians active: %d)" % [
			character_name, path.size() - 1, active])
	return path


func _follow_path(path: Array) -> void:
	## Queue a routed path as waypoints for _physics_process to walk one at a time, and
	## record its length so the move can be priced by distance. `path` starts on our own
	## tile, so it must hold at least two entries.
	##
	## Every routed move in the game funnels through here — players via _start_path_move,
	## enemies via _move_toward and _best_firing_path — which is why the guard clip lives
	## here rather than being repeated in each caller.
	##
	## And why the stealth roll does: one roll per MOVE is the rule, and this is what a move is.
	## Rolled as the character sets off rather than on arrival, because the listeners are asked
	## on their own pulse and may well ask while the walk is still happening — a roll made at
	## the far end would leave the noisiest part of the journey uncovered by any roll at all.
	if sneaking:
		roll_stealth()
	path = _clip_at_guard(path)
	if path.size() <= 1:
		# Pinned by a guardian before taking a single step. Two things still have to happen or
		# combat stops dead:
		#
		# The move floor is billed anyway (get_move_cost's comment explains why a zero-cost
		# action hands the same unit its turn straight back), and the completion hook is
		# driven by hand — nothing is moving, so _physics_process will never reach it, and an
		# AI turn waiting on _on_move_complete would hang forever.
		#
		# Deferred, not inline: Enemy._begin_move_toward sets _pending_cost AFTER _move_toward
		# returns, so calling the hook straight away would bill whatever the previous action
		# happened to leave in it.
		_move_tiles = 1
		_move_path = []
		is_moving = false
		_on_move_complete.call_deferred()
		return
	_move_tiles = max(1, path.size() - 1)
	_move_path = path.slice(1)
	target_position = _move_path.pop_front()
	is_moving = true


func get_move_range() -> int:
	## Tiles a single move may cover. Holding a line costs mobility: a guardian has his feet
	## planted, so he shuffles rather than strides.
	##
	## Floored at 1 on purpose. A stance that pinned its own user in place would be a trap
	## rather than a choice — and now that leaving a zone costs an opportunity attack rather
	## than being forbidden (see on_disengage), an exit has to exist for that price to mean
	## anything at all.
	##
	## Every range check goes through here rather than reading move_range directly, so the
	## penalty applies to the move indicator, the reachability test and the AI alike — and so
	## the exploration case below lands in all three at once.
	if is_player_controlled and _exploring():
		# Out of combat there is no clock, so rationing steps measures nothing. A hero walks as
		# far as the floor goes, in one click. EXPLORE_MOVE_RANGE is a cap only so the BFS
		# stays bounded, and it sits under _find_path's own 50-step ceiling.
		return EXPLORE_MOVE_RANGE
	if not is_guarding():
		return move_range
	@warning_ignore("integer_division")
	var reduced: int = move_range / GUARD_MOVE_DIVISOR
	return max(1, reduced)


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


func heal(amount: int) -> void:
	## Put hit points back, and show it.
	##
	## THE one place hp goes up, the way take_damage is the one place it goes down. A potion
	## goes through here, and so will a healing spell, a shrine or a night's rest — none of
	## which will have to be taught to bloom, animate or make a noise.
	##
	## A heal that would overflow is clamped and reports what was ACTUALLY restored: "+8 HP" on
	## a character missing two is a lie about the potion you just spent.
	if not is_alive or amount <= 0:
		return
	var before: int = hp
	hp = mini(hp + amount, max_hp)
	var gained: int = hp - before
	if gained <= 0:
		_show_action_text("Already whole")
		return
	_show_action_text("+%d HP" % gained)
	_update_health_bar()
	# The gesture: a hand raised to the mouth or held out. The rig has no drink or cast clip,
	# and "interact" is the nearest thing to either — it is what Pick Up borrows too.
	_play_attack_anim("interact-right")
	HealBurstScript.bloom(
		get_parent(), global_position + Vector3(0, EYE_HEIGHT, 0), get_feet_y())


func take_damage(amount: int, attacker_skill: int = 0, is_ranged: bool = false,
		attacker: Node = null, damage_type: int = DamageType.PHYSICAL) -> bool:
	## `damage_type` is last and defaulted so every existing caller is unaffected.
	## Note it is independent of `is_ranged`: that one decides whether the hit can be dodged,
	## parried or blocked by cover, while damage_type only decides what soaks it afterwards.
	## A firebolt is both a missile and fire.
	if not is_alive:
		return false

	var def_result: Dictionary = _attempt_defense(attacker_skill, is_ranged, attacker)
	if def_result.defended:
		return true

	var effective: int = _calculate_damage(amount, damage_type)
	hp -= effective
	if effective > 0:
		_show_damage_number(effective)
		_spill_blood(effective, attacker, damage_type)
	# A blow that got past the defence always lands on something, so this sits outside the
	# `effective > 0` guard: armour turning a strike dead is a sound, not a silence. What it
	# is NOT is a wound, which is the flag weapon_sfx uses to pick a cut over a clang.
	#
	# Melee only, keyed off is_ranged exactly as _spill_blood keys off damage_type: arrows,
	# thrown weapons and spells all reach here too, and each wants its own clip rather than a
	# borrowed sword.
	if not is_ranged:
		_melee_landing_sound(attacker, effective > 0)
	_update_health_bar()
	if hp <= 0:
		is_alive = false
		_die()
	else:
		_play_hit_anim()
		# Inside the else, so a killing blow gets the death cry and not both: a man does not
		# grunt and then die of it a frame later. Gated on effective, because _play_hit_anim
		# also flinches at a blow armour stopped dead, and that one is not a wound.
		if effective > 0:
			_wound_sound(is_ranged)
	return false


func _attempt_defense(attacker_skill: int, is_ranged: bool = false, attacker: Node = null) -> Dictionary:
	var attack_roll := attacker_skill + randi_range(1, 5)
	var effective_dodge: int = get_dodge_skill() - (2 if is_prone else 0)
	var result := { "defended": false, "attack_roll": attack_roll, "defense_roll": 0 }

	# Partial cover: a short prop (pillar / vessel) on the line from the shooter hinders
	# ranged & thrown attacks. It boosts an active dodge/parry, and — since even a
	# defenceless target gains from ducking behind a pillar — grants a flat save when no
	# active defence is possible. Melee (is_ranged == false) is point-blank, so cover is off.
	var has_cover: bool = is_ranged and attacker != null and _has_partial_cover_from(attacker)
	var cover_bonus: int = COVER_DEFENSE_BONUS if has_cover else 0

	# Overwhelmed: too much of our next turn is already spent reacting, so there is no time
	# left to put a blade or a shoulder in the way. This deliberately falls through to the
	# same cover-only path a bare-handed defender takes, which buys two things for free —
	# armour, resistance and a pillar all still apply, so the cliff is cushioned rather than
	# lethal; and because that path never charges a tick, the debt stops growing HERE instead
	# of spiralling. See defense_debt.
	if is_overwhelmed():
		_show_defense_result("Overwhelmed!")
		return _resolve_cover_only(has_cover, result)

	# Everything that is not DODGE resolves as a parry — Parry itself and Protection, which is
	# a parry from a planted position. Written as != DODGE rather than a match so that a future
	# stance defaults to the branch that at least CHECKS for a weapon, instead of silently
	# becoming a free empty-handed dodge.
	if defensive_option != Stance.DODGE:
		if not (_has_usable_weapon() or _has_shield_equipped()):
			return _resolve_cover_only(has_cover, result)
		if is_ranged and not _can_parry_ranged():
			return _resolve_cover_only(has_cover, result)
		# is_guarding(), not a bare stance check: the bonus, the zone that stops enemies, and
		# the aura on the floor are three faces of one thing and must never disagree about
		# whether the line is being held. Reading the stance directly let a guardian who was
		# prone — or overwhelmed, or had lost their weapon — keep parrying at +2 while the
		# floor showed no zone at all.
		var guard_bonus: int = GUARD_PARRY_BONUS if (is_guarding() and not is_ranged) else 0
		result.defense_roll = get_parry_skill() + randi_range(1, 5) + cover_bonus + guard_bonus
		if result.defense_roll >= attack_roll:
			if inventory and inventory.has_method("degrade_equipped_weapon"):
				inventory.degrade_equipped_weapon()
			_show_defense_result("Cover parry!" if has_cover else "Parry!")
			_parry_sparks(attacker, attacker_skill, is_ranged)
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


func _calculate_damage(raw: int, damage_type: int = DamageType.PHYSICAL) -> int:
	## Armour is plate, mail and boiled leather: it turns a blade or an arrow, and a bolt of
	## fire goes straight past it. So FIRE skips the armour subtraction entirely.
	##
	## Resistance still applies to everything. It represents the body's own toughness rather
	## than what is worn, which is why it is not bypassed — despite being named
	## `physical_resistance`, it is now the general damage resistance and the name lags.
	var dmg := raw
	if damage_type == DamageType.PHYSICAL:
		dmg -= armor
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
	# Being shoved into a wall opens you up like anything else does. No attacker to spray away
	# from here — the wall did it — so the splash picks its own heading.
	_spill_blood(effective, null, DamageType.PHYSICAL)
	_update_health_bar()
	if hp <= 0:
		hp = 0
		is_alive = false
		_die()
	else:
		_play_hit_anim()
		# A wall knocks the breath out of you the same as a blade does, and this is the one
		# injury in the game with no weapon behind it. No wind-up to wait for either — the
		# impact already happened.
		_wound_sound(true)


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


func _combat_mgr() -> Node:
	## The turn clock. Every combatant sits as a direct child of the battlefield root alongside
	## the manager, so this is a sibling lookup rather than a search.
	var p := get_parent()
	return p.get_node_or_null("CombatManager") if p else null


func _exploring() -> bool:
	## Whether the party is walking the dungeon rather than fighting in it. The manager owns
	## the mode; nothing here keeps a copy of it, because a stale copy of which mode you are in
	## is the one bug this would not survive.
	##
	## Answers false with no manager at all, so a combatant dropped into a bare test scene
	## behaves as it always did rather than gaining unlimited movement.
	var cm := _combat_mgr()
	return cm != null and cm.has_method("is_exploring") and cm.is_exploring()


func _charge_defense_cost() -> void:
	var combat_mgr := _combat_mgr()
	if combat_mgr:
		combat_mgr.charge_defense_cost(self)


func defense_debt() -> int:
	## How much of the time before our next turn we have spent REACTING — parries and dodges,
	## and nothing else. Zero for a character who has not defended since they last acted, and
	## it climbs by one for every successful parry or dodge via charge_defense_cost.
	##
	## Reacting, not acting, and the difference is the whole point. next_turn_at is pushed back
	## by BOTH: the action a character chose on their turn, and every defence they have made
	## since. Reading the raw gap to the clock therefore billed characters for their own turn —
	## a hero who spent five ticks crossing the room was over a stamina-4 limit the instant he
	## stopped walking, and was told his guard had dropped without an enemy having swung at him
	## once. Subtracting action_turn_at leaves only the reactions.
	##
	## Still derived rather than counted, which is what keeps recovery free: as everyone else
	## acts, current_tick climbs past action_turn_at and eats into the reactions on its own.
	## There is no counter to reset and no hook to remember to call.
	var mgr := _combat_mgr()
	if mgr == null:
		return 0
	return maxi(0, next_turn_at - maxi(mgr.current_tick, action_turn_at))


func get_defense_debt_limit() -> int:
	## Debt we can carry before the guard drops. See DEBT_PER_STAMINA.
	return stamina * DEBT_PER_STAMINA


func is_overwhelmed() -> bool:
	## Out of time to defend with. Note only SUCCESSFUL defences charge a tick, so this taxes
	## characters who are actually good at defending — a goblin that keeps missing its dodge
	## never builds debt, it just gets hit.
	return defense_debt() > get_defense_debt_limit()


func is_defense_strained() -> bool:
	## Within DEBT_WARN_MARGIN of being overwhelmed: still defending, but not for much longer.
	return not is_overwhelmed() and defense_debt() + DEBT_WARN_MARGIN > get_defense_debt_limit()


func _is_in_arena(tile: Vector3) -> bool:
	## Is there dungeon floor under this square?
	##
	## Asked by the three things that need somewhere to PUT a unit or an object rather than a
	## route to walk: a shove's landing square (_apply_push), the archer's choice of firing
	## position, and where a thrown weapon comes to rest. Movement does not consult it at all —
	## _find_path is bounded by walls, which is why the party can already walk through the door.
	##
	## It used to be the ±14 square in the constants above, and that square predated the room
	## through the north door: the room starts at z = 16, so every square of it read as off the
	## board. A shove in there would have been scored as a shove into the void. The floor plan
	## is DungeonRoom's business, so it is asked, and the square is kept only as the answer for
	## a scene that has no DungeonRoom in it.
	var room := get_parent().get_node_or_null("DungeonRoom") if get_parent() else null
	if room != null and room.has_method("is_floor_at"):
		return room.is_floor_at(tile.x, tile.z)
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
	return _claimed_by_mover(tile, exclude) or _is_obstacle_at(tile)


func _claimed_by_mover(tile: Vector3, exclude: Node = null) -> bool:
	## Whether another unit is already walking THROUGH this square — anywhere along the route it
	## is currently walking, not merely the step it happens to be taking now.
	##
	## The whole route, because that is where two idle enemies were ending up on the same
	## square. _follow_path keeps only the NEXT waypoint in target_position and the rest of the
	## route in _move_path, so reserving target_position alone reserved one step of a stroll
	## several squares long: a goblin two steps from where it was going had not yet claimed the
	## square it was going to, and the next goblin to look found it free and set off for it too.
	##
	## Only for units actually in motion. A stationary unit occupies the square it stands on and
	## nothing else, so a stale target_position cannot phantom-block an empty square.
	##
	## Costs nothing in combat, where exactly one unit is ever moving, and is what keeps the
	## exploration pulse — which moves everybody at once — from walking them through each other.
	for c in get_tree().get_nodes_in_group("combatants"):
		if not is_instance_valid(c) or c == exclude or not c.is_moving:
			continue
		if "is_alive" in c and not c.is_alive:
			continue
		if c._snap_to_grid(c.target_position).distance_to(tile) < 0.5:
			return true
		for step in c._move_path:
			if c._snap_to_grid(step).distance_to(tile) < 0.5:
				return true
	return false


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
var _guard_zone: MeshInstance3D = null


func set_turn_active(active: bool) -> void:
	## Toggle the glowing ring that marks whose turn it is. The combat manager lights the
	## active unit and clears the rest, so the ring lingers under a unit for its whole turn.
	if active:
		_ensure_turn_ring()
		_turn_ring.visible = true
	elif _turn_ring != null:
		_turn_ring.visible = false
	# Piggy-backed on purpose: _highlight_active calls this on EVERY combatant at every turn
	# change, which is the only hook that fires when the clock — rather than this character —
	# is what changed. Overwhelm is driven by current_tick advancing, so without a
	# clock-driven refresh a spent guardian would keep painting a zone he no longer holds.
	_refresh_guard_zone()


func _refresh_guard_zone() -> void:
	## Show the guarded tiles while we actually hold them. Cheap enough to call freely; the
	## mesh is built once, on the first turn the stance is taken, and never for anyone who
	## never guards.
	var on: bool = is_guarding()
	if not on:
		if _guard_zone != null:
			_guard_zone.visible = false
		return
	_ensure_guard_zone()
	_guard_zone.visible = true


func _ensure_guard_zone() -> void:
	if _guard_zone != null:
		return
	var plate := MeshInstance3D.new()
	plate.name = "GuardZone"
	var quad := PlaneMesh.new()
	# The full ring the zone covers, derived from GUARD_RADIUS so widening the rule widens
	# the decal with it: radius 1 -> 3 tiles across -> 6 world units.
	var side: float = (GUARD_RADIUS * 2 + 1) * GRID_SIZE
	quad.size = Vector2(side, side)
	plate.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Cool steel blue, to stay clearly distinct from the gold turn ring it sits under.
	mat.albedo_color = Color(0.38, 0.68, 1.0, 0.20)
	mat.emission_enabled = true
	mat.emission = Color(0.30, 0.60, 1.0)
	mat.emission_energy_multiplier = 0.8
	plate.material_override = mat
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Just above the floor and a hair above the turn ring, so the translucent plate lays over
	# the gold rather than z-fighting it. Parented to the body, so it tracks every move and
	# every shove for free — exactly as the turn ring does.
	plate.position = Vector3(0, 0.20 - _ground_y(), 0)
	add_child(plate)
	_guard_zone = plate


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
	return dist <= get_move_range() * GRID_SIZE


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
	# Both missile paths and the AI's shot-pricing all come through here, so a prone target is
	# a worse shot for the goblin archer choosing where to stand as well as for the player.
	if "is_prone" in target and target.is_prone:
		penalty += PRONE_TARGET_PENALTY
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


func get_spell_power() -> int:
	## How hard a spell lands, the way attack_skill decides how hard a blade does. Willpower
	## one-for-one for a caster, and 0 for everyone else — a fighter with a strong will is
	## stubborn, not magical.
	##
	## Nothing casts yet, so this is currently only read by the character sheet. It exists as
	## the single place a spell should ask, so that when spells arrive they cannot start
	## inventing their own scaling.
	return willpower if can_cast else 0


func spend_mana(amount: int) -> bool:
	## Pay for a spell. Returns false and spends nothing when the caster cannot cast or the
	## pool is short, so a caller can use it as the affordability check and the payment in one:
	##     if not spend_mana(cost): return
	if not can_cast:
		return false
	if amount <= 0:
		return true
	if mana < amount:
		return false
	mana -= amount
	_update_health_bar()
	return true


func restore_mana(amount: int) -> void:
	if not can_cast or amount <= 0:
		return
	mana = mini(max_mana, mana + amount)
	_update_health_bar()


func get_dodge_skill() -> int:
	## Dodging IS agility — there is no separate trained value, so a nimble character cannot be
	## a poor dodger. Note the asymmetry with get_parry_skill(): parrying is done with a weapon
	## or shield and so takes an equipment bonus, whereas dodging is done with the body alone
	## and takes none. Adding a `dodge_bonus` to ItemResource (a cloak, light boots) would be
	## the place to change that.
	return agility


func get_stealth_skill() -> int:
	## How quietly this character can cross a room: what they have been taught, plus half of
	## whatever agility they have over an average body.
	##
	## Both halves earn their place. Creeping is a CRAFT, so the trained number leads and is the
	## per-character dial. But it is a craft done with the body, so the nimble are better at it —
	## which is what makes the ranger the best sneak in this party without anybody having to
	## write it down: agility 7 against the soldier's 5 and the wizard's 3, on stealth 3 each,
	## comes out 5 / 4 / 3.
	##
	## HALF the difference rather than all of it, because the attribute spread in this party is
	## four points and a die is five: at full weight the ranger would never be heard and the
	## wizard never missed, and the roll would stop being a roll. Halved, against a goblin's
	## perception of 7, they get through on 80% / 60% / 40% of moves.
	##
	## Nothing WORN feeds it yet, and armour should — a man in plate has no business
	## out-sneaking one in leather. ItemResource growing a stealth_penalty is where that goes,
	## in the same breath as the parry_bonus get_parry_skill reads.
	@warning_ignore("integer_division")
	var nimble: int = (agility - AVERAGE_ATTRIBUTE) / 2
	return stealth_skill + nimble


func roll_stealth() -> int:
	## Make one attempt at moving quietly, and remember it: skill + 1d5, the same roll the
	## attack, the parry and the lockpick all make.
	##
	## Remembered rather than returned to a caller, because the roll and the question are asked
	## by different people at different times. The mover rolls as it sets off (_follow_path);
	## the listeners ask on their own pulse, which may be a second later and may be several of
	## them. One roll per move, checked by everybody who might have heard it.
	_stealth_roll = get_stealth_skill() + randi_range(1, 5)
	return _stealth_roll


func is_unheard_by(listener) -> bool:
	## Whether this character's last move got past `listener`'s ears.
	##
	## Only ever about NOISE. Somebody sneaking is still there to be seen, and no roll hides a
	## hero who walks into a goblin's line of sight — see Enemy.notices_intruders, which tests
	## hearing and sight separately for exactly this reason.
	##
	## Ties go to the sneak, as they do to a lockpick (LootContainer._try_unlock): the roll with
	## the die in it is the active attempt, and the flat number it beats is a difficulty.
	if not sneaking or not _exploring():
		return false
	if listener == null or not ("perception_skill" in listener):
		return false
	return _stealth_roll >= listener.perception_skill


func set_sneaking(on: bool) -> void:
	## Start or stop creeping. Rolled on entering as well as on every move after, so standing
	## still and sneaking is a state with a number behind it rather than a free pass.
	if sneaking == on:
		return
	sneaking = on
	if on:
		roll_stealth()
	_show_action_text("Sneaking" if on else "Walking openly")
	# Repainted by group rather than through a method, for the same reason _lay_prone does it:
	# this class has no toolbar of its own and enemies have no toolbar at all.
	get_tree().call_group("action_toolbar", "refresh")


func get_parry_skill() -> int:
	## Parry skill including whatever is in our hands (a shield, or a weapon made for
	## turning blades). Dodge has no equivalent: nothing worn or carried feeds that roll.
	return parry_skill + _inv_bonus("parry_bonus")


func get_offhand_attack_skill() -> int:
	return attack_skill + _inv_bonus("offhand_attack_bonus")


func get_offhand_attack_damage() -> int:
	return maxi(1, attack_dmg + _inv_bonus("offhand_damage_bonus"))


func get_weapon_sound(offhand: bool) -> int:
	## Sound family of one hand's weapon, or -1 when that hand holds no weapon (see
	## InventoryComponent.get_weapon_sound). Bare hands and shields are silent on the swing.
	if inventory and inventory.has_method("get_weapon_sound"):
		return inventory.get_weapon_sound(offhand)
	return -1


func get_swing_sound() -> int:
	## What the blow now landing was struck with. Only meaningful between the start of a melee
	## strike and its resolution, which is the only window anything asks in.
	return _swing_sound


func _inv_bonus(method: String) -> int:
	if inventory and inventory.has_method(method):
		return inventory.call(method)
	return 0


func _do_melee_attack(target) -> void:
	## Shared melee routine for players and AI: main-hand strike, plus a free off-hand
	## follow-up when dual-wielding two melee weapons. Runs as a coroutine so the off-hand
	## lands a beat after the main hit (right anim, then left anim) instead of overwriting it.
	# Only an off-hand weapon held (main hand empty): the lone strike IS an off-hand attack.
	var lone_offhand: bool = 		inventory and inventory.has_method("offhand_only") and inventory.offhand_only()
	# One shout per attack action, here rather than in _offhand_attack: a dual-wielder's free
	# follow-up is part of the same effort, and grunting twice would say otherwise. Sited before
	# the branch so a lone off-hand strike still gets a voice, sized by the hand actually
	# swinging.
	_attack_cry(get_weapon_sound(lone_offhand))
	if lone_offhand:
		_offhand_attack(target)
		return
	_play_attack_anim("attack-melee-right")
	_swing_sound = get_weapon_sound(false)
	var dmg: int = get_attack_damage()
	_swing_arc(target, dmg)
	target.take_damage(dmg, get_attack_skill(), false, self)

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
	_swing_sound = get_weapon_sound(true)
	var penalty: int = 0 if dual_wield_skill else OFFHAND_HIT_PENALTY
	var dmg: int = maxi(1, int(get_offhand_attack_damage() / 2.0))
	_show_action_text("Off-hand!")
	# Mirrored, so the follow-up visibly crosses the main-hand cut instead of repeating it.
	_swing_arc(target, dmg, true)
	target.take_damage(dmg, get_offhand_attack_skill() - penalty, false, self)


func get_ranged_range() -> int:
	## Reach comes entirely from the weapon — a character has no innate shooting range, so
	## empty-handed or holding a sword this is 0 and the Ranged ability simply cannot target.
	## There is deliberately no character-level fallback to paper over a missing bow.
	if inventory and inventory.has_method("get_equipped_ranged_range"):
		return inventory.get_equipped_ranged_range()
	return 0


func get_throw_range() -> int:
	## Also purely the weapon's (ItemResource.throw_range, which defaults to a short lob so an
	## ordinary weapon can still be thrown).
	if inventory and inventory.has_method("get_equipped_throw_range"):
		return inventory.get_equipped_throw_range()
	return 0


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

	if is_alive and not _is_attacking and not is_prone and _held_pose == "":
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
	elif _held_pose != "":
		if ap.current_animation != _held_pose:
			ap.play(_held_pose)
	elif ap.current_animation != "idle":
		ap.play("idle")


func hold_pose(anim: String) -> void:
	## Hold a pose until somebody lets go of it — the boss sitting on his throne.
	##
	## A flag rather than just playing the clip, because the animation driver in
	## _physics_process re-asserts "walk or idle" EVERY FRAME for anybody upright. A sit played
	## without this blinks back to standing on the next frame, which is the same reason prone is
	## a state there and not a clip.
	var ap := _ensure_anim_player()
	if ap == null or not ap.has_animation(anim):
		return
	_held_pose = anim
	ap.play(anim)


func release_pose() -> void:
	## Let go of a held pose and settle back to neutral. Safe to call when nothing is held,
	## which is what lets the alarm shout it at the whole room without asking who was sitting.
	if _held_pose == "":
		return
	_held_pose = ""
	_play_rest_anim()


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


func get_projectile_origin(toward: Vector3) -> Vector3:
	## Where a projectile leaves this character — the Firebolt's bolt, the bow's arrow.
	##
	## The weapon socket if the rig has one: a shot that starts at the staff or the bow reads
	## as cast or loosed, while one that starts at the body reads as fired out of the chest.
	## During an attack the two-handed grip is suspended and the weapon is handed back to the
	## right fist (see _play_attack_anim), so the socket is where the weapon actually is while
	## this is called.
	##
	## The lift and reach are deliberately in WORLD space rather than along the socket's own
	## axes: the fist rolls with the animation, and an offset that rolled with it would swing
	## the spawn point around the character mid-cast.
	var base := global_position + Vector3(0, EYE_HEIGHT * 0.4, 0)
	if _weapon_socket is Node3D and (_weapon_socket as Node3D).is_inside_tree():
		base = (_weapon_socket as Node3D).global_position
	var origin := base + Vector3(0, PROJECTILE_ORIGIN_LIFT, 0)
	var dir := toward - origin
	dir.y = 0
	if dir.length() > 0.01:
		origin += dir.normalized() * PROJECTILE_ORIGIN_REACH
	return origin


func get_feet_y() -> float:
	## World height of the floor this character is standing on. `position.y` is the body's
	## origin, which sits _ground_y() above the floor, so effects that belong on the ground
	## (a scorch mark, a stain) subtract it rather than assuming the arena floor is at zero.
	return global_position.y - _ground_y()


func take_held_weapon_visual() -> Node3D:
	## A detached copy of whatever model is currently in this character's hands, ready to be
	## flown as a thrown projectile. Null if they are holding nothing with a model.
	##
	## Copying the live node rather than rebuilding from the ItemResource is deliberate. The
	## rules for turning an item into a model — data-driven model_path first, then a name-based
	## fallback table, then per-type scaling and the Synty atlas override — already live in
	## _refresh_socket and again in ground_item.gd, and a third copy here would be the one that
	## drifted. This also cannot disagree with what the player can see in the fist.
	var socket: Node3D = null
	if _weapon_socket is Node3D and (_weapon_socket as Node3D).get_child_count() > 0:
		socket = _weapon_socket as Node3D
	elif _grip_socket != null and _grip_socket.get_child_count() > 0:
		# Two-handers hang off the chest instead. Mid-attack the grip is suspended and the
		# weapon is back in the fist, so this branch is the belt-and-braces case.
		socket = _grip_socket
	if socket == null:
		return null
	var copy := socket.get_child(0).duplicate() as Node3D
	return copy


func _parry_sparks(attacker: Node, attacker_skill: int, is_ranged: bool) -> void:
	## Steel on steel where a parry catches the blow. The mirror of _spill_blood: that one says
	## the strike went in, this one says it was stopped, and between them every resolved attack
	## now leaves something behind.
	##
	## Only real parries reach here — a dodge is avoidance, with nothing meeting, and the
	## passive cover save is a pillar eating the shot rather than anyone catching it.
	var atk := attacker as Node3D
	if atk == null:
		return
	var attacker_at := atk.global_position
	var defender_at := global_position
	# A harder blow is a heavier thing to turn aside. Attacker skill is the only measure of the
	# incoming strike available at this point — the damage is never rolled on a parry.
	var force: float = clampf(float(attacker_skill) / PARRY_REFERENCE_SKILL, 0.6, 1.5)
	# Read before the wait below, for the same reason _swing_arc does it.
	var sound_family: int = attacker.get_swing_sound() if attacker.has_method("get_swing_sound") else -1
	if not is_ranged:
		# Melee sparks wait out the same wind-up the attacker's arc does, so the blades meet
		# rather than the parry flashing before the swing arrives. An arrow needs no such wait:
		# take_damage already happens the moment it lands.
		await get_tree().create_timer(SWING_WINDUP).timeout
		if not is_inside_tree():
			return
	ParrySparksScript.clash(get_parent(), defender_at, attacker_at, force)
	# Melee only for now: a parried arrow deserves its own clip rather than a sword's, and
	# ArrowImpact is sitting unused in the same bundle for whoever adds it.
	if not is_ranged:
		WeaponSfxScript.landed(
			get_parent(), defender_at + Vector3(0, EYE_HEIGHT, 0), sound_family, false)


func _swing_arc(target, damage: int, mirrored: bool = false) -> void:
	## The blade's arc across the target. Fired for every melee strike whatever it lands —
	## unlike the blood, which is only for wounds — because the swing happened either way, and
	## a parry with nothing to parry reads as the defender flinching at air.
	##
	## Not awaited by the caller, and deliberately so: it runs a short delay of its own to let
	## the attack animation wind up, so the arc arrives with the blade rather than with the
	## button press. Melee is the one attack whose timing this does NOT change — the roll still
	## resolves on the frame it always did.
	var victim := target as Node3D
	if victim == null:
		return
	var from := global_position
	var to := victim.global_position
	# Bigger weapons cut bigger arcs. Scaled off damage because that is the only size the game
	# actually models — reach is a range rule, not a blade length.
	# Named arc_scale, not strength: `strength` is a character stat on this class, and shadowing
	# it here would read as the swing scaling off the attacker's muscle rather than the weapon.
	var arc_scale: float = clampf(float(damage) / SWING_REFERENCE_DAMAGE, 0.6, 1.6)
	# Read before the wait, not after: by the time the arc is drawn the off-hand follow-up may
	# already have set a different weapon swinging.
	var sound_family: int = _swing_sound
	# Halfway to the target and up at chest height — where the arc is drawn, and near enough to
	# both bodies that no attenuation model can tell the difference.
	var sound_at: Vector3 = from.lerp(to, 0.5) + Vector3(0, EYE_HEIGHT, 0)
	await get_tree().create_timer(SWING_WINDUP).timeout
	if not is_inside_tree():
		return
	SwordSwingScript.swing(get_parent(), from, to, arc_scale, mirrored)
	WeaponSfxScript.swing(get_parent(), sound_at, sound_family)


func _claim_voice() -> bool:
	## True if this character's voice is free, and claims it if so. Every line goes through
	## here; whoever asks first inside a VOICE_GAP window wins and the rest stay quiet.
	var now: int = Time.get_ticks_msec()
	if now - _last_voice_ms < int(VOICE_GAP * 1000.0):
		return false
	_last_voice_ms = now
	return true


func _voice_at() -> Vector3:
	## Where a character's voice comes from: the head, not the feet.
	return global_position + Vector3(0, EYE_HEIGHT, 0)


func _attack_cry(family: int) -> void:
	## The effort of a swing, at the START of the strike rather than on contact — the breath
	## goes in before the blade lands, and a character who only shouts on a hit sounds like
	## they knew it was going to connect. `family` is the hand doing the work, which sets how
	## hard the shout is.
	if not _claim_voice():
		return
	VoiceSfxScript.attack(
		get_parent(), _voice_at(), voice, VoiceSfxScript.effort_for_weapon(family))


func _aim_cry() -> void:
	## Drawing on someone. Silent for voices the bundle gave no aim lines to.
	if not _claim_voice():
		return
	VoiceSfxScript.aim(get_parent(), _voice_at(), voice)


func _charge_cry() -> void:
	## The battle cry, the first time this character closes on an enemy in a fight.
	##
	## Deliberately NOT behind _claim_voice: it happens once, at the top of a move, where
	## nothing else is competing for the throat — and of everything a character says, this is
	## the line that should never lose a race.
	if _has_charged:
		return
	_has_charged = true
	# Claimed but not checked: the cry goes out regardless, and marking the throat busy stops
	# an attack grunt landing on top of it if the charge ends adjacent and the swing follows
	# immediately.
	_claim_voice()
	VoiceSfxScript.charge(get_parent(), _voice_at(), voice)


func _charge_shout() -> void:
	## A battle cry as the character sets off at somebody — every time, not once a fight.
	##
	## The other one, _charge_cry, is the AI's: it fires once per enemy per fight so a room of
	## goblins does not bellow every turn they spend walking. A player charge is a thing the
	## player just chose to do, one click at a time, and it should be answered each time.
	##
	## Voice-gated, so it cannot land on top of the attack grunt at the far end of a short run.
	if not _claim_voice():
		return
	VoiceSfxScript.charge(get_parent(), _voice_at(), voice)


func _wound_sound(is_ranged: bool) -> void:
	## Us crying out. Only for damage that got through — the caller checks that, because only
	## the caller knows whether anything actually landed.
	##
	## Melee waits out SWING_WINDUP so the grunt arrives with the blade, exactly as the cut and
	## the blood do; an arrow or a bolt is already at the body by the time we are called.
	if not _claim_voice():
		return
	VoiceSfxScript.wound(
		get_parent(), _voice_at(), voice, 0.0 if is_ranged else SWING_WINDUP)


func _melee_landing_sound(attacker: Node, wounded: bool) -> void:
	## The blade arriving on us: a cut if it opened something, a clang if armour or a shield
	## turned it. The audio mirror of _spill_blood and _parry_sparks, and it waits out the same
	## SWING_WINDUP they do so all three land on the frame the arc does.
	##
	## Nothing is awaited here — see WeaponSfx.landed for why the wait cannot live on a node
	## that this very blow might be about to kill. `get_parent()` is read now, while we are
	## still in the tree, for the same reason.
	if attacker == null:
		return
	var family: int = attacker.get_swing_sound() if attacker.has_method("get_swing_sound") else -1
	WeaponSfxScript.landed(
		get_parent(), global_position + Vector3(0, EYE_HEIGHT, 0), family, wounded, SWING_WINDUP)


func _spill_blood(effective: int, attacker: Node, damage_type: int) -> void:
	## Blood for any wound that actually got through, from wherever — a blade, an arrow, a
	## thrown axe, a wall. It lives here, off take_damage and _apply_impact_damage, rather than
	## in each attack: one rule for the whole game, and anything added later bleeds without
	## having to be taught to.
	##
	## FIRE is the one exception. A Firebolt already bursts into flame on whoever it hits (see
	## player.gd::_do_firebolt), and a red splash underneath that only muddies it. Delete this
	## guard if you would rather burns bled too.
	if damage_type == DamageType.FIRE:
		return
	# Away from whoever landed the blow, which for an arrow is exactly the line it was flying.
	# Left at zero when nobody did (a shove into a wall); BloodSplash picks a heading itself.
	var away := Vector3.ZERO
	var atk := attacker as Node3D
	if atk:
		away = global_position - atk.global_position
	BloodSplashScript.burst(
		get_parent(),
		global_position + Vector3(0, PROJECTILE_IMPACT_HEIGHT, 0),
		away,
		get_feet_y(),
		clampf(float(effective) / BLOOD_REFERENCE_DAMAGE, 0.5, 1.6))


func _loose_arrow_at(target: Node) -> void:
	## Fly an arrow to `target`, then resolve the shot where it lands: the roll, the damage and
	## — on a hit — the blood all happen on impact, so they read as one event rather than as a
	## number appearing half a second before the arrow that caused it.
	##
	## Lives here rather than in player.gd or enemy.gd because the hero's bow and the goblin
	## archer's do exactly the same thing; both `await` it, so neither ends its turn while the
	## arrow is still in the air. Ammo, animation and turn cost stay with the callers, which is
	## where they differ.
	var impact_point: Vector3 = target.global_position + Vector3(0, PROJECTILE_IMPACT_HEIGHT, 0)
	var origin := get_projectile_origin(impact_point)
	var arrow = ArrowProjectileScript.loose(get_parent(), origin, impact_point)
	_aim_cry()
	WeaponSfxScript.bow_shot(get_parent(), origin)
	await arrow.impacted
	# Before the early-out below, not after: an arrow loosed at someone who died mid-flight
	# still lands somewhere, and going silent exactly when the shot is wasted would read as
	# the game dropping the sound rather than as the shot being wasted.
	WeaponSfxScript.arrow_impact(get_parent(), impact_point)

	if not is_instance_valid(target) or not target.is_alive:
		return
	# The blood is not spawned here: take_damage does it for every hit that gets through, and
	# it works out the same spray direction from `self` that this function would have passed.
	var to_hit: int = get_missile_skill(ranged_skill, target, get_ranged_range())
	target.take_damage(get_attack_damage(), to_hit, true, self)


func _die() -> void:
	# First, before the animation and before the corpse leaves its collision layer: the cry is
	# what tells the player someone just went down, and it should lead the fall rather than
	# arrive under it.
	VoiceSfxScript.death(get_parent(), global_position + Vector3(0, EYE_HEIGHT, 0), voice)
	can_act = false
	# What was being carried becomes the pile on the body. Done HERE, at the top, and not after
	# the death animation below: that stretch is behind an `await`, so a character whose model
	# has no "die" clip — or whose clip is interrupted — would never become lootable at all.
	# Dying is what makes a body searchable, not finishing the fall.
	_gather_corpse_loot()
	if not contents.is_empty():
		add_to_group("interactables")
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
	# Drop the floating nameplate and the bar so neither hovers over the corpse.
	if health_bar:
		health_bar.visible = false
	if hp_bar:
		hp_bar.visible = false
	var combat_mgr := _combat_mgr()
	if combat_mgr:
		combat_mgr.on_character_died(self)


# can_act is only meaningful for player-controlled combatants but is declared
# here so the shared _die()/turn plumbing can reference it uniformly.
var can_act := false


# --- A corpse is a container --------------------------------------------------
#
# The same three questions doors and chests answer (can_interact / interact_verb / interact),
# plus the two the loot window needs (contents, take). Nothing new had to be taught to the
# Open/Close action or to loot_ui.gd: a body with things on it IS a container, and writing the
# action against a contract rather than against chests is what makes that free.

func can_interact(_actor) -> bool:
	## Only a corpse, and only one with something on it. A living character is not scenery, and
	## an empty body is not worth walking over to — nor worth a pointer suggesting it is.
	return not is_alive and not contents.is_empty()


func interact_verb() -> String:
	return "Search"


func interact(_actor) -> void:
	## Nothing to open — a body is already open. The window does the rest; Player._do_interact
	## puts it up once this returns.
	pass


func wants_loot_window() -> bool:
	return not is_alive and not contents.is_empty()


func blocks_openably() -> bool:
	## A corpse is never a door. Pathfinding asks this of everything in "interactables", and a
	## body that answered yes would have goblins queueing up to open it.
	return false


func take(index: int, actor) -> bool:
	## Move one item off this body and into `actor`'s bag.
	if index < 0 or index >= contents.size() or actor == null:
		return false
	var inv = actor.inventory if "inventory" in actor else null
	if inv == null or not inv.has_method("add_item"):
		return false
	var item: ItemResource = contents[index]
	if not inv.add_item(item):
		if actor.has_method("_show_action_text"):
			actor._show_action_text("Bag is full!")
		return false
	contents.remove_at(index)
	# Off the body as well as out of the pile, or the corpse goes on visibly holding a weapon
	# somebody else now owns.
	if inventory and inventory.has_method("forget"):
		inventory.forget(item)
	_update_equipment_visuals()
	if actor.has_method("_show_action_text"):
		actor._show_action_text(item.item_name)
	contents_changed.emit()
	return true


func _gather_corpse_loot() -> void:
	## Everything this character was carrying becomes the pile on the body.
	##
	## Straight off `items`, which is enough for everything in the bag: equipping never took
	## anything OUT of it (InventoryComponent._equip_to), so the sword in a goblin's hand is in
	## there too.
	contents.clear()
	_gather_spare_arrows()
	if inventory == null or not ("items" in inventory):
		return
	for item in inventory.items:
		if item != null:
			contents.append(item)


func _gather_spare_arrows() -> void:
	## Whatever is left in the quiver, as a bundle on the pile.
	##
	## Needed because arrows are not an ITEM while they are in a quiver — they are a number on
	## the character (`ammo`, filled from CombatantStats and spent a shaft at a time by
	## Enemy._do_ranged_attack), and a number is not something a body can be searched for. So an
	## archer dropped his bow, his dagger and his jerkin and left four arrows nowhere at all.
	##
	## It matters more than tidiness: ammunition is the one thing a bow cannot be used without,
	## there is exactly one bundle in the crates, and the archers are carrying the rest of the
	## level's supply. Killing one and taking his arrows is how the party's own bow keeps
	## shooting, which is a fair trade to have to notice.
	if ammo <= 0:
		return
	var bundle: ItemResource = load(ARROW_BUNDLE_ITEM)
	if bundle == null:
		return
	# Duplicated, because a .tres is a shared cached object: written to directly, the arrow
	# bundle in the crates would quietly become however many arrows the last archer died with.
	# The same reason CombatManager._spawn_item duplicates before dropping one.
	var spare := bundle.duplicate() as ItemResource
	spare.ammo_amount = ammo
	contents.append(spare)
	# The quiver is empty now — they are in the pile. Nothing reads a corpse's ammo today, and
	# this is so that nothing can ever read it and find the same arrows twice.
	ammo = 0


func _model_crown_y() -> float:
	## Height of the top of this character's art, in LOCAL space — so it can be compared
	## against, and used to place, the label offsets.
	##
	## Off the meshes' own bounding boxes, which for a skinned mesh are the REST pose and do not
	## follow the animation. That is what makes this stable: measuring the animated silhouette
	## would raise the bar every time somebody lifted a sword over their head.
	var model := get_node_or_null("CharacterModel") as Node3D
	if model == null:
		return 0.6
	var top := -INF
	for mi in _mesh_instances(model):
		var box: AABB = mi.get_aabb()
		for i in range(8):
			top = maxf(top, (mi.global_transform * box.get_endpoint(i)).y)
	if top == -INF:
		return 0.6
	return top - global_position.y


func _mesh_instances(node: Node, out: Array = []) -> Array:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		out.append(mi)
	for child in node.get_children():
		_mesh_instances(child, out)
	return out


func _place_floating_labels() -> void:
	## Sit the bar HEAD_CLEARANCE over the crown and the nameplate above that, for whatever
	## height this particular character turns out to be.
	##
	## Overrides the y the scene's Label3D was placed at: it is the same rule for all seven
	## combatants in main.tscn, and nobody should have to keep seven transforms agreeing.
	var crown: float = _model_crown_y()
	# A centimetre of slack, so an animation frame that nudges a bounding box does not set the
	# labels twitching.
	if absf(crown - _crown_y) < 0.01:
		return
	_crown_y = crown
	if hp_bar:
		hp_bar.position.y = crown + HEAD_CLEARANCE
	if health_bar:
		health_bar.position.y = crown + HEAD_CLEARANCE + PLATE_OVER_BAR


func _update_health_bar() -> void:
	## Refreshes the floating nameplate above the character (and, via health_changed, the
	## party portraits and the bar over the head).
	##
	## The name, and the two conditions you cannot see on the model — prone, and an empty
	## quiver. Nothing else. Armour, resistance and stance used to be here and are not any
	## more: four lines of text over every one of seven characters is a wall in front of the
	## fight, and all three live on the character sheet where they can be read at leisure.
	##
	## Hit points are not here either. They are printed across the bar itself (health_bar_3d),
	## where the number and the length of the bar it labels are one thing to look at instead of
	## two stacked above each other.
	_update_equipment_visuals()
	# After the gear, before anything reads the labels: a helmet or a two-handed grip changes
	# how tall the character is, and the bar has to follow the new crown.
	_place_floating_labels()
	# Before the Label3D early-out, like the signal below: what a character is holding and
	# whether they are still standing both feed is_guarding(), and that has to stay true for
	# combatants with no floating nameplate too.
	_refresh_guard_zone()
	# Emitted before the Label3D early-out so listeners fire even for combatants
	# that have no floating nameplate node.
	health_changed.emit(hp, max_hp, is_alive)
	# The bar over the head, driven from the same call as the portraits and the nameplate so
	# all three are refreshed by anything that touches hp, without a fourth place to remember.
	if hp_bar:
		hp_bar.set_hp(hp, max_hp, is_alive)
	if not health_bar:
		return
	var lines: Array = [character_name]
	if is_prone:
		lines.append("[PRONE]")
	if max_ammo > 0:
		lines.append("Ammo:" + (str(ammo) if ammo > 0 else "Empty"))
	health_bar.text = "\n".join(lines)
