extends Resource
class_name CharacterData
## The persistent half of a hero: everything that has to outlive the scene they were last
## seen in.
##
## The combat layer works with Combatant NODES, and a node dies with its scene. That is why
## every stat, skill and item used to be lost the moment the game left the battlefield: the
## character WAS the node. So the split is this — a CharacterData is the character, and a
## Combatant node is only a VIEW of one, built for the length of a single quest and thrown
## away at the end of it.
##
## GameState holds these. QuestScene hydrates a node from one on the way in (apply_to, then
## restore_into once it is in the tree) and writes the node back into it on the way out
## (capture_from). Nothing in here knows about a node path, a scene or a screen, and nothing
## outside QuestScene should have to.

const CombatantStatsScript := preload("res://scripts/combatant_stats.gd")

## Bumped whenever a stored field changes MEANING, so a save written by an older build can be
## recognised rather than silently misread. Adding a field with a sensible default does not
## need a bump; renaming one, or changing its units, does. Nothing reads saves yet (that is
## Phase 2), but the number is stamped from the first day so there is never a save on disk
## without one.
const SCHEMA_VERSION := 1

## What each class LOOKS like: the model wrapper scene under scenes/characters, and any
## property that wrapper needs set — the same ones the authored battlefield heroes were built
## with, so a spawned hero and a hand-placed one are the same character.
##
## `props` is not decoration. The authored archer's model carries `show_quiver = true`, and a
## spawned archer without it is an archer with no quiver on their back (see CharacterSkin).
##
## A class is a string rather than an enum on purpose: it is stored in saves, and a string
## survives someone reordering this table. "archer" has no model of its own yet and borrows
## male_d, which is what the authored archer used.
##
## Only the body lives here. What a NEW character of a class starts with — stats, gear, a
## name for the screen — is character_classes.gd, which is authoring data rather than
## something every spawn needs.
const CLASS_BODIES := {
	"soldier": {"model": "res://scenes/characters/soldier_model.tscn", "props": {}},
	"wizard": {"model": "res://scenes/characters/wizard_model.tscn", "props": {}},
	"archer": {"model": "res://scenes/characters/male_d_model.tscn", "props": {"show_quiver": true}},
}

const DEFAULT_CLASS := "soldier"

## Where a hero's model sits inside the body. The authored heroes all use this, and a spawned
## one has to match or it stands a metre above the floor.
const MODEL_OFFSET := Vector3(0, -1, 0)

## Vitals stored as "arrive at full" rather than as a number. A fresh character has no hp yet
## — max_hp is derived from stamina by Combatant._derive_stats, which cannot run until there
## is a node — so there is no honest number to write down until after the first quest.
const VITALS_FULL := -1

@export var id: String = ""
@export var character_name: String = "Hero"
## Which body this hero wears — a key of CLASS_BODIES. Decides the model at spawn and nothing
## else yet; Phase 1's creation screen and Phase 3's training will hang starting stats and
## skill costs off it.
@export var class_id: String = DEFAULT_CLASS
@export var voice: String = "male_a"

## This character's OWN stat block, and the one place their trained skills live. Never share
## one between two characters: training writes into it, so a shared block would train the
## whole party at once.
##
## Typed Resource rather than CombatantStats for the same reason Combatant.stats is — see the
## comment there. The .tres still carries the real class.
@export var stats: Resource

## Level and experience. `xp` is a POOL — it is spent on training and goes down — so it cannot
## also be the measure of how far a character has come; `xp_total` is what they have earned in
## their life and only ever rises. Level is derived from the total (see Progression.level_for)
## and stored so that a screen can show it without the rules having to be loaded.
@export var level: int = 1
@export var xp: int = 0
@export var xp_total: int = 0

## Wounds carried between quests. VITALS_FULL means "arrive at full", which is what a hero
## who has never fought yet is. Phase 1 decides what resting in town costs; until then a
## quest hands these straight back.
@export var hp: int = VITALS_FULL
@export var mana: int = VITALS_FULL
@export var ammo: int = VITALS_FULL

## The bag, exactly as InventoryComponent lays it out: MAX_SLOTS long, with nulls for the
## empty slots. Kept sparse rather than packed because `equipped` points INTO it by index,
## and packing would quietly re-point a sword at a potion.
@export var bag: Array = []

## What is worn and held: ItemResource.EquipSlot -> index into `bag`. A two-handed weapon
## legitimately appears under both hands with the same index, which is how
## InventoryComponent models it too.
@export var equipped: Dictionary = {}


static func make_id() -> String:
	## Unique enough to tell two heroes apart in a save file, and not meaningful to anything.
	return "%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000]


# --- Hydration: data -> node ------------------------------------------------

func apply_to(c: Node) -> void:
	## The half of hydration that MUST happen before the node enters the tree.
	##
	## Combatant._ready copies the stat block onto itself and derives max hp and mana from the
	## attributes it finds there (_apply_stats, then _derive_stats). Assigning stats afterwards
	## would leave a hero with a trained block and an untrained body, so it is done here, while
	## the node is still just an object.
	c.character_name = character_name
	c.voice = voice
	c.is_player_controlled = true
	if stats != null:
		# The stat block carries a name of its own, because an enemy .tres is authored with one
		# ("Goblin"), and Combatant._apply_stats copies it onto the body during _ready — after
		# this function has run. So a character created with a name and a fresh block would
		# walk into the dungeon called "Hero". The character's name is the real one; the block
		# mirrors it.
		stats.character_name = character_name
		c.stats = stats


func restore_into(c: Node) -> void:
	## The other half, once the node is in the tree and its _ready chain has run.
	##
	## Gear first, vitals second. Equipping is what folds a shield's parry bonus and armour's
	## protection into the body (InventoryComponent._equip_to), and _ready has just filled both
	## pools to their derived maximum — so the stored hp has to be written after all of that or
	## it would be overwritten by a full heal.
	_restore_inventory(c)
	if hp != VITALS_FULL:
		c.hp = clampi(hp, 1, c.max_hp)
	if mana != VITALS_FULL:
		c.mana = clampi(mana, 0, c.max_mana)
	if ammo != VITALS_FULL and c.max_ammo > 0:
		c.ammo = clampi(ammo, 0, c.max_ammo)
	# One call refreshes the nameplate, the bar over the head, the portraits AND the equipment
	# sockets, so the hero is holding what the data says they hold.
	c._update_health_bar()


func model_scene_path() -> String:
	return _body()["model"]


func model_props() -> Dictionary:
	## Properties to set on the instanced model — see CLASS_BODIES.
	return _body()["props"]


func _body() -> Dictionary:
	return CLASS_BODIES.get(class_id, CLASS_BODIES[DEFAULT_CLASS])


func _restore_inventory(c: Node) -> void:
	var inv: Node = c.inventory
	if inv == null:
		return
	# A spawned hero's bag is empty and this is a no-op. It matters for a node that was
	# authored in the scene with starting gear of its own: clearing BEFORE anything else
	# unwinds that gear's stat bonuses from the body while they still match what is equipped.
	inv.clear_all()
	for item in bag:
		if item != null:
			inv.add_item(item)
	# Equipment only after the whole bag has arrived: a two-hander claims both hands and an
	# offhand needs its partner present, so an item that had not been added yet could be
	# refused a slot it is entitled to.
	var already: Array = []
	for slot in equipped.keys():
		var idx: int = int(equipped[slot])
		if idx < 0 or idx >= bag.size() or bag[idx] == null:
			continue
		# A two-handed weapon is stored under both hands, and equipping it once fills both
		# (InventoryComponent._equip_to). Equipping it a second time would take its bonuses
		# off the hand it is being moved out of and never give them back.
		if already.has(bag[idx]):
			continue
		already.append(bag[idx])
		# int() because a Dictionary round-tripped through JSON hands its keys back as strings.
		inv.equip_into(int(slot), bag[idx])


# --- The bag, out of the dungeon -------------------------------------------
# A town screen has no live InventoryComponent to work through — there is no body in town —
# so buying, selling and wearing things there happen here instead. The invariant these keep is
# the one the whole bag depends on: `equipped` points INTO `bag` by index, so an item can never
# be removed without the slots pointing at it being cleared too.

const InventoryComponentScript := preload("res://scripts/inventory_component.gd")


func bag_has_room() -> bool:
	return _free_slot() >= 0


func bag_add(item) -> bool:
	## Put something in the pack. False if there is no room, having changed nothing.
	if item == null:
		return false
	var slot: int = _free_slot()
	if slot < 0:
		return false
	if slot >= bag.size():
		bag.resize(slot + 1)
	bag[slot] = item
	return true


func bag_remove_at(idx: int):
	## Take something out of the pack for good — sold, or dropped. Returns the item, or null.
	if idx < 0 or idx >= bag.size() or bag[idx] == null:
		return null
	var item = bag[idx]
	unequip_index(idx)
	bag[idx] = null
	return item


func is_equipped(idx: int) -> bool:
	for slot in equipped:
		if int(equipped[slot]) == idx:
			return true
	return false


func unequip_index(idx: int) -> void:
	## Clear every slot pointing at this bag index. Every one, not the first: a two-handed
	## weapon is held in both hands and listed under both.
	for slot in equipped.keys():
		if int(equipped[slot]) == idx:
			equipped.erase(slot)


func equip_from_bag(idx: int) -> bool:
	## Wear or wield something out of the pack, displacing whatever is in the way.
	##
	## The town-side counterpart of InventoryComponent._equip_to, and it follows the same rules
	## — the slot comes from InventoryComponent.preferred_slot, a two-hander takes both hands,
	## and a one-hander cannot share a hand with one. It has to be a separate implementation
	## because the live one needs a body to fold the item's bonuses into, and that body does
	## not exist until the next quest starts.
	if idx < 0 or idx >= bag.size() or bag[idx] == null:
		return false
	var item = bag[idx]
	var slot: int = InventoryComponentScript.preferred_slot(item)
	if slot < 0:
		return false   # carried, not worn: arrows, potions, keys
	var two_handed: bool = item.handedness == ItemResource.Handedness.TWO_HANDED
	var into_hand: bool = slot == ItemResource.EquipSlot.RIGHT_HAND \
		or slot == ItemResource.EquipSlot.LEFT_HAND
	if into_hand:
		var held: int = int(equipped.get(ItemResource.EquipSlot.RIGHT_HAND, -1))
		var offhand: int = int(equipped.get(ItemResource.EquipSlot.LEFT_HAND, -1))
		# Both hands come free for a two-hander, and both come free if a two-hander is what is
		# currently in them.
		if two_handed or (held != -1 and held == offhand):
			equipped.erase(ItemResource.EquipSlot.RIGHT_HAND)
			equipped.erase(ItemResource.EquipSlot.LEFT_HAND)
	equipped[slot] = idx
	if two_handed:
		equipped[ItemResource.EquipSlot.RIGHT_HAND] = idx
		equipped[ItemResource.EquipSlot.LEFT_HAND] = idx
	return true


func slot_is_free(item) -> bool:
	## Whether this item's usual slot is empty — the test for whether putting it on would take
	## a decision away from the player. Used when buying: new gear goes on if there is nothing
	## to displace, and waits in the pack if there is.
	var slot: int = InventoryComponentScript.preferred_slot(item)
	if slot < 0:
		return false
	if item.handedness == ItemResource.Handedness.TWO_HANDED:
		return not equipped.has(ItemResource.EquipSlot.RIGHT_HAND) \
			and not equipped.has(ItemResource.EquipSlot.LEFT_HAND)
	return not equipped.has(slot)


func _free_slot() -> int:
	for i in range(bag.size()):
		if bag[i] == null:
			return i
	if bag.size() < InventoryComponentScript.MAX_SLOTS:
		return bag.size()
	return -1


# --- Capture: node -> data --------------------------------------------------

static func from_combatant(c: Node) -> CharacterData:
	## Build a character out of a combatant that was placed by hand in a scene.
	##
	## This is the bridge off the old single-scene design: the authored battlefield heroes are
	## the only record of what a starting hero is made of — their attributes are scene
	## exports and their gear is a list of .tres on the Inventory node — so the first quest
	## reads them out into real characters instead of that knowledge dying with quest_scene.tscn.
	## Phase 1's creation screen will make characters the other way, from a class and a name.
	var data := CharacterData.new()
	data.id = make_id()
	data.class_id = _class_of(c)
	data.stats = stats_from_combatant(c)
	data.capture_from(c)
	return data


func capture_from(c: Node) -> void:
	## Write a quest's worth of events back into the character: their wounds, and whatever
	## they are carrying now.
	##
	## Deliberately does NOT touch the stat block of a character that already has one. A
	## combatant's runtime `armor` has its equipment folded into it, so copying the body back
	## over the block would bake the shield into the hero and do it again next quest. Skills
	## change in town, not here — see GameState.award_xp.
	character_name = c.character_name
	voice = c.voice
	if stats == null:
		stats = stats_from_combatant(c)
	hp = c.hp if c.is_alive else 1
	mana = c.mana
	ammo = c.ammo
	_capture_inventory(c)


func _capture_inventory(c: Node) -> void:
	bag = []
	equipped = {}
	var inv: Node = c.inventory
	if inv == null:
		return
	# The bag is copied slot for slot, nulls included, because the equipment map below points
	# into it by index.
	bag = inv.items.duplicate()
	for pair in [
		[ItemResource.EquipSlot.RIGHT_HAND, inv.right_hand],
		[ItemResource.EquipSlot.LEFT_HAND, inv.left_hand],
		[ItemResource.EquipSlot.ARMOR, inv.armor],
		[ItemResource.EquipSlot.HELMET, inv.helmet],
		[ItemResource.EquipSlot.LEGS, inv.legs],
	]:
		var item: ItemResource = pair[1]
		if item == null:
			continue
		var idx: int = bag.find(item)
		# Equipping never removes an item from the bag, so anything held should be in there.
		# If it somehow is not, it is carried as loose gear rather than dropped on the floor.
		if idx < 0:
			bag.append(item)
			idx = bag.size() - 1
		equipped[int(pair[0])] = idx


static func stats_from_combatant(c: Node) -> Resource:
	## Read a stat block off a live combatant, field by field, by asking CombatantStats what
	## it stores. Copying by name rather than by a hand-written list of thirty assignments
	## means a new stat added to CombatantStats is captured without anyone remembering to
	## come back here.
	var s: Resource = CombatantStatsScript.new()
	for prop in s.get_property_list():
		var name: String = prop["name"]
		if not (prop["usage"] & PROPERTY_USAGE_STORAGE):
			continue
		# Resource's own bookkeeping, and `script` — which exists on BOTH a resource and a
		# node, so copying it would staple the combatant's script onto the stat block.
		if name == "script" or name.begins_with("resource_"):
			continue
		if not (name in c):
			continue
		s.set(name, c.get(name))
	# Undo what the character is wearing. _apply_stats ASSIGNS armor and physical_resistance
	# from the block and InventoryComponent then adds each equipped item's bonus on top, so
	# the runtime values we just copied have the gear counted in them. Storing those would
	# make the armour permanent, and wearing it again next quest would count it twice.
	var worn := _worn_bonuses(c)
	s.armor = maxi(0, s.armor - worn.x)
	s.physical_resistance = maxi(0, s.physical_resistance - worn.y)
	return s


static func _worn_bonuses(c: Node) -> Vector2i:
	## Armour and resistance currently owed to equipment. Mirrors
	## Combatant._readd_equipment_bonuses, including its dedupe: a two-handed weapon sits in
	## both hands as one object and is only counted once.
	var inv: Node = c.inventory
	if inv == null:
		return Vector2i.ZERO
	var total := Vector2i.ZERO
	var counted: Array = []
	for slot in ["right_hand", "left_hand", "armor", "helmet", "legs"]:
		var item: ItemResource = inv.get(slot)
		if item == null or counted.has(item):
			continue
		counted.append(item)
		total.x += item.armor_bonus
		total.y += item.resistance_bonus
	return total


static func _class_of(c: Node) -> String:
	## Which class an authored hero belongs to, worked out from the model they were built
	## with. The scene is the only place that knows — there was no such thing as a class
	## before this — so the body is the evidence.
	var model: Node = c.get_node_or_null("CharacterModel")
	if model != null:
		var scene_path: String = model.scene_file_path
		for cls in CLASS_BODIES:
			if CLASS_BODIES[cls]["model"] == scene_path:
				return cls
	return DEFAULT_CLASS


# --- Serialisation ---------------------------------------------------------
# Used by the save system in Phase 2. Written now so that the shape of a stored character is
# decided in one place, next to the fields it stores, rather than invented later somewhere
# else.

func to_dict() -> Dictionary:
	var out := {
		"schema": SCHEMA_VERSION,
		"id": id,
		"character_name": character_name,
		"class_id": class_id,
		"voice": voice,
		"level": level,
		"xp": xp,
		"xp_total": xp_total,
		"hp": hp,
		"mana": mana,
		"ammo": ammo,
		"stats": _stats_to_dict(),
		"bag": [],
		"equipped": {},
	}
	for item in bag:
		out["bag"].append(_item_to_dict(item))
	for slot in equipped:
		# JSON object keys are strings; from_dict reads them back with int().
		out["equipped"][str(slot)] = equipped[slot]
	return out


static func from_dict(d: Dictionary) -> CharacterData:
	var data := CharacterData.new()
	data.id = d.get("id", make_id())
	data.character_name = d.get("character_name", "Hero")
	data.class_id = d.get("class_id", DEFAULT_CLASS)
	data.voice = d.get("voice", "male_a")
	data.level = int(d.get("level", 1))
	data.xp = int(d.get("xp", 0))
	# A save written before xp was a spendable pool has no lifetime total; what it does have is
	# an xp figure that was never spent, so it IS the lifetime total.
	data.xp_total = int(d.get("xp_total", data.xp))
	data.hp = int(d.get("hp", VITALS_FULL))
	data.mana = int(d.get("mana", VITALS_FULL))
	data.ammo = int(d.get("ammo", VITALS_FULL))
	data.stats = _stats_from_dict(d.get("stats", {}))
	data.bag = []
	for entry in d.get("bag", []):
		data.bag.append(_item_from_dict(entry))
	data.equipped = {}
	for slot in d.get("equipped", {}):
		data.equipped[int(slot)] = int(d["equipped"][slot])
	return data


func _stats_to_dict() -> Dictionary:
	var out := {}
	if stats == null:
		return out
	for prop in stats.get_property_list():
		var name: String = prop["name"]
		if not (prop["usage"] & PROPERTY_USAGE_STORAGE):
			continue
		if name == "script" or name.begins_with("resource_"):
			continue
		out[name] = stats.get(name)
	return out


static func _stats_from_dict(d: Dictionary) -> Resource:
	var s: Resource = CombatantStatsScript.new()
	for name in d:
		# Only fields the current CombatantStats still has: a stat dropped since the save was
		# written is ignored rather than crashing the load.
		if name in s:
			s.set(name, d[name])
	return s


static func _item_to_dict(item) -> Dictionary:
	## An item is stored as the template it came from plus the few things play can change
	## about it. The alternative — writing all forty of ItemResource's fields per item — would
	## also freeze every item in the game at the values it had when the save was written, so a
	## balance change would never reach an existing character's sword.
	if item == null:
		return {}
	return {
		"template": item.template_path,
		"item_name": item.item_name,
		"durability": item.durability,
		"broken": item.broken,
		"ammo_amount": item.ammo_amount,
	}


static func _item_from_dict(d: Dictionary):
	if d == null or d.is_empty():
		return null
	var template_path: String = d.get("template", "")
	if template_path == "" or not ResourceLoader.exists(template_path):
		push_warning("CharacterData: dropping saved item with no loadable template: %s" % template_path)
		return null
	var template = load(template_path)
	if template == null:
		return null
	var item = template.make_instance()
	item.item_name = d.get("item_name", item.item_name)
	item.durability = int(d.get("durability", item.durability))
	item.broken = bool(d.get("broken", item.broken))
	item.ammo_amount = int(d.get("ammo_amount", item.ammo_amount))
	return item
