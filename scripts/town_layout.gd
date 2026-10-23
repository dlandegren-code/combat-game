extends RefCounted
class_name TownLayout
## Where everything in the town stands, as data.
##
## The town is built from this table rather than authored in a .tscn, for two reasons. The
## roster is meant to VARY — not every service is open every visit, and Phase 4's quest board
## will want to add and remove them — and a scene file cannot express "one of these three
## buildings, if the healer is in town today". The other reason is plainer: every position
## below was written against measured model sizes (tools/measure_prefabs.gd), and a table of
## numbers is the only form in which those measurements are checkable.
##
## COORDINATES
## The camera looks down -Z from +Z, so -Z is the far side of the clearing and +X is screen
## right. Buildings stand at y = 0: Synty pivots sit at the intended ground point, and some
## models dip a little below it on purpose (a dirt skirt), which is why nothing is lifted to
## its bounding box. If something floats or sinks, nudge its `y`.
##
## WHAT IS MISSING AND WHY
## There is exactly one real house across both packs the project owns — the meadow pack's
## Stone Cabin (6 x 4 x 8 m). The mushroom "houses" measure 38 cm; they are ornaments, so the
## magician's is one of them scaled up to cottage size, which is the sort of thing that only
## works in a fairytale wood. The three shops are market stalls. The soldiers' fort is a
## compound assembled from several packs (BARRACKS). When a Synty fantasy village pack
## arrives, the fix is to change `model` on these entries and nothing else.

## Where the camera sits, what it looks at, and how wide a view it takes. A FIXED camera: this
## is a backdrop, not a place to walk around, and fixing it is what lets the scene be dressed
## for one composition instead of having to hold up from every angle.
const CAMERA_POSITION := Vector3(0.0, 13.5, 34.0)
const CAMERA_TARGET := Vector3(0.0, 3.5, -3.0)
const CAMERA_FOV := 52.0

## Late afternoon, low and warm, coming from the left so the buildings cast their shadows
## across the clearing towards the camera.
const SUN_ROTATION := Vector3(-34.0, 46.0, 0.0)
const SUN_COLOUR := Color(1.0, 0.93, 0.78)
const SUN_ENERGY := 1.35
const SKY_TOP := Color(0.29, 0.53, 0.85)
const SKY_HORIZON := Color(0.78, 0.86, 0.92)
const GROUND_COLOUR := Color(0.36, 0.45, 0.26)
const FOG_COLOUR := Color(0.74, 0.82, 0.86)

## The flat ground the clearing sits on, under the scattered grass.
## Big enough that its far edge is well beyond the tree line: at 150 the edge of the
## plane was visible as a hard horizon across the middle of the shot.
const GROUND_SIZE := 600.0
const GROUND_TINT := Color(0.33, 0.44, 0.22)

## Services the player can visit. `screen` is the scene its button opens, or "" for something
## that is only scenery with a name. `label` is what the button says.
##
## `model` is a meadow model name (SyntyModel.meadow) unless prefixed "farm:", which loads the
## farm pack's Godot prefab instead.
##
## `sign_at` is where the button floats, in world space — usually just above the roof. The
## button is placed by projecting this point through the camera, so it tracks the building
## rather than being pinned to a corner of the screen.
const SERVICES := [
	{
		"id": "healer",
		"label": "Healer's House",
		"screen": "",
		"note": "Rest and mend. Free while there is nothing else to spend a night on.",
		# The stone cabin, dressed as a hedge-witch's: see WITCH_HUT.
		"model": "compound:witch_hut",
		"position": Vector3(-16.8, 0.0, -5.6),
		"rotation": 18.0,
		"scale": 1.0,
		"sign_at": Vector3(-16.8, 6.4, -5.6),
		"action": "rest",
	},
	{
		"id": "magician",
		"label": "Magician's House",
		"screen": "",
		"note": "Training for those who cast. Nothing to buy here yet.",
		# 38 cm ornament scaled to a 3.5 m cottage — see the note at the top of this file.
		"model": "SM_Prop_MushroomHouse_01",
		"position": Vector3(12.0, 0.0, -9.0),
		"rotation": -22.0,
		"scale": 15.0,
		"sign_at": Vector3(12.0, 6.4, -9.0),
		"action": "training",
	},
	{
		"id": "fort",
		"label": "Soldiers' Fort",
		"screen": "",
		"note": "Drill and instruction, behind a palisade.",
		# Not one model but a yard of them — see BARRACKS below.
		"model": "compound:barracks",
		"position": Vector3(21.0, 0.0, -6.5),
		"rotation": -30.0,
		"scale": 1.0,
		"clear": 10.0,   ## the stockade is 15 m across; nothing may grow through it
		"sign_at": Vector3(21.0, 7.0, -6.5),
		"action": "training",
	},
	{
		"id": "armorer",
		"label": "Armorer",
		"screen": "",
		"note": "Armour and shields.",
		# The market stall, dressed as an armourer's: see ARMOUR_STALL.
		"model": "compound:armour_stall",
		"position": Vector3(-8.6, 0.0, 2.0),
		"rotation": 8.0,
		"scale": 1.0,
		"sign_at": Vector3(-8.6, 4.2, 2.0),
		"action": "shop",
	},
	{
		"id": "weaponsmith",
		"label": "Weapon Shop",
		"screen": "",
		"note": "Blades, bows and hafted things.",
		# The market stall, dressed as a weaponsmith's: see WEAPON_STALL.
		"model": "compound:weapon_stall",
		"position": Vector3(1.6, 0.0, 3.5),
		"rotation": -4.0,
		"scale": 1.0,
		"sign_at": Vector3(1.6, 4.2, 3.5),
		"action": "shop",
	},
	{
		"id": "general",
		"label": "General Store",
		"screen": "",
		"note": "Potions, arrows and everything else.",
		# A trader's pavilion rather than a third market stall: see GENERAL_STORE.
		"model": "compound:general_store",
		"position": Vector3(7.6, 0.0, 2.4),
		"rotation": -14.0,
		"scale": 1.0,
		"sign_at": Vector3(7.6, 4.8, 2.4),
		"action": "shop",
	},
	{
		"id": "camp",
		"label": "Mercenary Camp",
		"screen": "",
		"note": "Sell-swords looking for work, and a fire to wait by.",
		# A SECOND tent, deliberately the same model as the soldiers' fort: these are the same
		# kind of people, and a camp that matched nothing else in the clearing would read as a
		# building rather than as somebody's pitch. Its own fire stands beside it (SCENERY),
		# which is what tells the two tents apart at a glance.
		"model": "SM_Prop_Camp_Tent_01",
		"position": Vector3(-10.0, 0.0, -12.5),
		"rotation": 26.0,
		"scale": 2.4,
		# Flown higher than the shops' signs (4.2) on purpose: the camp sits almost directly
		# behind the healer's house from this camera, and at the same height the two labels
		# ended up shoulder to shoulder. Lifting one of them is cheaper than moving a building
		# into somebody else's plot.
		"sign_at": Vector3(-10.0, 6.0, -12.5),
		"action": "hire",
	},
	{
		"id": "adventure",
		"label": "Go Adventuring",
		"screen": "",
		"note": "The way out of the clearing, and down.",
		"model": "SM_Bld_Warpgate_01",
		"position": Vector3(-1.0, 0.0, -17.0),
		"rotation": 0.0,
		"scale": 1.0,
		"sign_at": Vector3(-1.0, 9.2, -17.0),
		"action": "adventure",
	},
]

## Scenery with no button on it. Same fields, minus the service ones.
const SCENERY := [
	# The landmark on the ridge. Its blades are their own mesh, which is what lets them turn.
	{"model": "SM_Bld_Windmill_01", "position": Vector3(-25.0, 0.0, -20.0), "rotation": 25.0, "scale": 1.0,
		"clear": 13.0},   ## its sails sweep nearly 10 m across; nothing may grow inside that
	{"model": "SM_Prop_Camp_Fireplace_01", "position": Vector3(3.0, 0.0, 11.0), "rotation": 0.0, "scale": 1.3},
	{"model": "SM_Prop_Camp_Tanning_Rack_01", "position": Vector3(-11.8, 0.0, 4.8), "rotation": 24.0, "scale": 1.2},
	# The mercenaries' fire, in front of their tent, with a cook pot over it and a crate to sit
	# on. The clearing already has a campfire down by the bench (above); this is a second one,
	# and it is what makes the second tent read as a camp rather than as a spare fort.
	{"model": "SM_Prop_Camp_Fireplace_Stones_01", "position": Vector3(-7.0, 0.0, -10.8), "rotation": 0.0, "scale": 1.3},
	{"model": "SM_Prop_Camp_Fire_Tripod_01", "position": Vector3(-7.0, 0.0, -10.8), "rotation": 14.0, "scale": 1.3},
	{"model": "SM_Prop_Camp_Crate_01", "position": Vector3(-5.2, 0.0, -12.2), "rotation": -32.0, "scale": 1.1},
	{"model": "SM_Prop_Bridge_01", "position": Vector3(24.0, 0.0, 8.0), "rotation": 74.0, "scale": 1.2},
	{"model": "SM_Prop_Birdhouse_01", "position": Vector3(-22.5, 0.0, 2.0), "rotation": 0.0, "scale": 1.0},
	# Washing on the line, for the wind to move.
	{"model": "farm:SM_Prop_ClothesLine_01", "position": Vector3(-23.0, 0.0, -1.0), "rotation": 74.0, "scale": 1.0},
	{"model": "farm:SM_Prop_ClothesLine_02", "position": Vector3(-24.0, 0.0, 4.5), "rotation": 62.0, "scale": 1.0},
	# The smithy, between the armourer and the weaponsmith who both buy from it. Scenery rather
	# than a service: there is nothing to do there yet but watch. See SMITHY.
	{"model": "compound:smithy", "position": Vector3(-3.6, 0.0, 1.6), "rotation": 4.0, "scale": 1.0},
	# Crates and barrels around the stalls.
	{"model": "SM_Prop_Camp_Crate_01", "position": Vector3(3.9, 0.0, 5.0), "rotation": -26.0, "scale": 1.1},
	{"model": "SM_Prop_Camp_Bucket_01", "position": Vector3(-12.0, 0.0, 0.4), "rotation": 0.0, "scale": 1.0},
	{"model": "SM_Prop_Camp_Bucket_02", "position": Vector3(-13.2, 0.0, 0.2), "rotation": 30.0, "scale": 1.0},
	{"model": "farm:SM_Prop_Bench_01", "position": Vector3(-1.0, 0.0, 9.0), "rotation": 186.0, "scale": 1.0},
	{"model": "farm:SM_Prop_Hay_Pile_01", "position": Vector3(17.5, 0.0, 3.0), "rotation": 12.0, "scale": 1.0},
	# A fairy ring of the ornament mushrooms, by the magician's.
	{"model": "SM_Prop_Mushroom_Group_02", "position": Vector3(15.0, 0.0, -5.5), "rotation": 0.0, "scale": 6.0},
	{"model": "SM_Prop_Mushroom_Group_03", "position": Vector3(9.0, 0.0, -5.0), "rotation": 40.0, "scale": 5.0},
	{"model": "SM_Prop_Mushroom_01", "position": Vector3(13.0, 0.0, -4.0), "rotation": 0.0, "scale": 7.0},
]

## The mercenaries' fire, lit. The stones and the cook tripod are scenery above; this is where
## the flame and its light go (Town passes it to TownAmbience.add_campfire), and it is a
## constant rather than a literal in town.gd so the prop and the fire in it cannot drift apart.
const MERC_FIRE := Vector3(-7.0, 0.0, -10.8)

## THE SOLDIERS' FORT, as a compound.
##
## None of the packs has a medieval barracks, so this one is put together from parts: the
## meadow's stone cabin as the bunkhouse, the farm's open lean-to as the armoury, and the
## dungeon pack's goblin watch-stand, weapon rack, braziers and red hall banners for
## everything that says "soldiers" rather than "farmer". The cabin is the same model as the
## healer's house, which is why this one is dressed so heavily: the banners and stockade are
## what stop it reading as a second healer.
##
## Every position here is LOCAL to the fort's own `position` and `rotation` in SERVICES, with
## +Z the open front facing the clearing, so the whole yard can be moved or turned as one.
## `model` takes "dungeon:<folder>/<name>" for PolygonDungeon prefabs, as well as the usual
## meadow names and "farm:" prefabs. `scale` may be a Vector3 where a part is stretched.
const BARRACKS := [
	# The bunkhouse, porch to the front. Unturned, the cabin's porch already faces +Z.
	{"model": "SM_Bld_Stone_Cabin_01", "position": Vector3(0.0, 0.0, -1.3), "rotation": 0.0, "scale": 1.05},
	# The watch-stand in the back corner, standing over the stockade.
	{"model": "dungeon:Props/SM_Prop_Goblin_Tower_01", "position": Vector3(-5.4, 0.0, -3.8), "rotation": 20.0, "scale": 1.35},
	# The armoury: an open lean-to with the rack and the spare kit under it.
	{"model": "farm:SM_Bld_Shelter_01", "position": Vector3(6.0, 0.0, -2.8), "rotation": 0.0, "scale": 0.95},
	{"model": "dungeon:Props/SM_Prop_WeaponRack_01", "position": Vector3(6.0, 0.0, -3.6), "rotation": 0.0, "scale": 1.1},
	{"model": "dungeon:Weapons/SM_Wep_Spear_01", "position": Vector3(5.4, 0.55, -3.45), "rotation": 0.0, "scale": 1.1},
	{"model": "dungeon:Weapons/SM_Wep_Spear_01", "position": Vector3(6.0, 0.55, -3.45), "rotation": 0.0, "scale": 1.1},
	{"model": "dungeon:Weapons/SM_Wep_Spear_01", "position": Vector3(6.6, 0.55, -3.45), "rotation": 0.0, "scale": 1.1},
	{"model": "dungeon:Weapons/SM_Wep_Shield_Heater_01", "position": Vector3(4.4, 0.55, -2.9), "rotation": 14.0, "scale": 1.2},
	{"model": "dungeon:Weapons/SM_Wep_Shield_Heater_01", "position": Vector3(7.6, 0.55, -2.9), "rotation": -10.0, "scale": 1.2},
	{"model": "dungeon:Props/SM_Prop_Crate_Wood_01", "position": Vector3(7.8, 0.0, -0.6), "rotation": 12.0, "scale": 0.8},
	{"model": "dungeon:Props/SM_Prop_Barrel_01", "position": Vector3(4.6, 0.0, -0.4), "rotation": 0.0, "scale": 1.0},
	# Braziers either side of the bunkhouse door; lit by Town (BARRACKS_FIRES).
	{"model": "dungeon:Props/SM_Prop_Brazier_01", "position": Vector3(-2.6, 0.0, 3.6), "rotation": 0.0, "scale": 1.0},
	{"model": "dungeon:Props/SM_Prop_Brazier_01", "position": Vector3(2.6, 0.0, 3.6), "rotation": 0.0, "scale": 1.0},
	# The colours, on poles at the mouth of the yard. Each is the bare banner pole with a hall
	# banner hung from its crossbar: the pole's pivot sits 0.32 m above its foot and its bar
	# 1.42 m up, and the hall banner hangs DOWN from its pivot, so at a pole scale of 2 the bar
	# is at 0.64 + 2.84 = 3.48. Squashed vertically so the cloth stops clear of the grass.
	{"model": "dungeon:Weapons/SM_Wep_Banner_01", "position": Vector3(-4.2, 0.64, 4.6), "rotation": 0.0, "scale": 2.0},
	{"model": "dungeon:Props/SM_Prop_Wall_Banner_01", "position": Vector3(-4.2, 3.48, 4.68), "rotation": 0.0, "scale": Vector3(0.95, 0.6, 0.8)},
	{"model": "dungeon:Weapons/SM_Wep_Banner_01", "position": Vector3(4.2, 0.64, 4.6), "rotation": 0.0, "scale": 2.0},
	{"model": "dungeon:Props/SM_Prop_Wall_Banner_01", "position": Vector3(4.2, 3.48, 4.68), "rotation": 0.0, "scale": Vector3(0.95, 0.6, 0.8)},
]

## THE SHOPS AND THE SMITHY, dressed the same way as the fort: a list of parts local to the
## entry's own position and rotation, +Z to the front.
##
## The two stalls are the farm pack's produce stand, which is a vegetable stall and looked like
## one. What makes them a weaponsmith's and an armourer's is what is on and around them. The
## stand is 3.1 m square at scale 1, its counter at the front, top about 1.0 m up and 0.25 to
## 1.5 m forward of the pivot. At the 1.15 the stalls stand at, the top is at 1.15 and its
## front edge at z = 1.75.
##
## `rotation` may be a Vector3 for a part that has to lie down: a sword on a counter.
const _STAND := {"model": "farm:SM_Bld_ProduceStand_01", "position": Vector3.ZERO, "rotation": 0.0, "scale": 1.15}

## Blades on the counter, more in a rack at the side, spears stood in a barrel at the other.
## The dungeon pack's swords stand on their pommels with the pivot 0.16 m above it, so a y of
## 0.16 puts one on the ground; turned 90 about Z it lies flat with the hilt at the pivot.
const WEAPON_STALL := [
	_STAND,
	# Everything on this stall is scaled up from life, deliberately: the townsfolk stand at
	# TOWNSFOLK_SCALE and a sword sized for a real hand was a grey sliver from the camera.
	{"model": "dungeon:Weapons/SM_Wep_Straightsword_01", "position": Vector3(-0.1, 1.18, 1.05), "rotation": Vector3(0.0, 8.0, 90.0), "scale": 1.6},
	{"model": "dungeon:Weapons/SM_Wep_Ornate_Sword_01", "position": Vector3(1.0, 1.18, 1.3), "rotation": Vector3(90.0, 90.0, 0.0), "scale": 1.4},
	{"model": "dungeon:Weapons/SM_Wep_HandAxe_01", "position": Vector3(0.55, 1.18, 0.7), "rotation": Vector3(0.0, -20.0, 90.0), "scale": 1.6},
	# The rack, turned side-on beside the stall with its blades stood in it.
	{"model": "dungeon:Props/SM_Prop_WeaponRack_01", "position": Vector3(2.4, 0.0, 0.7), "rotation": -82.0, "scale": 1.4},
	{"model": "dungeon:Weapons/SM_Wep_GreatSword_01", "position": Vector3(2.45, 0.27, -0.2), "rotation": Vector3(0.0, -82.0, 6.0), "scale": 1.5},
	{"model": "dungeon:Weapons/SM_Wep_Straightsword_01", "position": Vector3(2.45, 0.26, 0.45), "rotation": Vector3(0.0, -82.0, -5.0), "scale": 1.6},
	{"model": "dungeon:Weapons/SM_Wep_Axe_01", "position": Vector3(2.45, 0.27, 1.05), "rotation": Vector3(0.0, -82.0, 4.0), "scale": 1.6},
	{"model": "dungeon:Weapons/SM_Wep_Ornate_Axe_01", "position": Vector3(2.45, 0.27, 1.6), "rotation": Vector3(0.0, -82.0, -6.0), "scale": 1.6},
	# Spears in a barrel. Their pivot is 0.48 m above the butt; this sinks the butts into it.
	{"model": "dungeon:Props/SM_Prop_Barrel_01", "position": Vector3(-2.25, 0.0, 1.0), "rotation": 0.0, "scale": 1.2},
	{"model": "dungeon:Weapons/SM_Wep_Spear_01", "position": Vector3(-2.35, 0.95, 0.9), "rotation": Vector3(-6.0, 0.0, 7.0), "scale": 1.3},
	{"model": "dungeon:Weapons/SM_Wep_Spear_02", "position": Vector3(-2.1, 0.95, 1.05), "rotation": Vector3(5.0, 40.0, -6.0), "scale": 1.3},
	{"model": "dungeon:Weapons/SM_Wep_Ornate_Spear_01", "position": Vector3(-2.25, 0.95, 1.2), "rotation": Vector3(8.0, 0.0, 2.0), "scale": 1.3},
]

## A suit on a stand either side, a helm on the counter, shields hung off its front.
## The armour meshes (tools/build_synty_armor.gd) were cut off the dungeon knight and keep
## their place on his body: the cuirass spans 0.94 - 1.55 m and the helm 1.44 - 1.87 m above
## his feet. So a cuirass and helm at the SAME position are already a knight with nobody in
## him, and a fence post through the middle is all the stand there is to build. Scaled up
## from life like the weapon stall's stock, post and all, so the post still ends inside the helm.
const ARMOUR_STALL := [
	_STAND,
	# Knight's harness on the left.
	{"model": "SM_Prop_Meadow_Fence_Post_01", "position": Vector3(-2.4, 0.21, 0.9), "rotation": 0.0, "scale": 1.4},
	{"model": "res://assets/models/synty_armor/plate_cuirass.res", "position": Vector3(-2.4, 0.0, 0.9), "rotation": 0.0, "scale": 1.4},
	{"model": "res://assets/models/synty_armor/plate_helm.res", "position": Vector3(-2.4, 0.0, 0.9), "rotation": 0.0, "scale": 1.4},
	# Leather on the right.
	{"model": "SM_Prop_Meadow_Fence_Post_01", "position": Vector3(2.4, 0.21, 0.9), "rotation": 0.0, "scale": 1.4},
	{"model": "res://assets/models/synty_armor/studded_leather.res", "position": Vector3(2.4, 0.0, 0.9), "rotation": 0.0, "scale": 1.55},
	# A spare helm on the counter, lowered by the height its own mesh starts at (1.44 x 1.3).
	{"model": "res://assets/models/synty_armor/plate_helm.res", "position": Vector3(-0.4, -0.72, 1.2), "rotation": -20.0, "scale": 1.3},
	# Shields hung along the counter's front edge, faces out.
	{"model": "dungeon:Weapons/SM_Wep_Shield_Round_01", "position": Vector3(-1.0, 0.62, 1.8), "rotation": 0.0, "scale": 1.4},
	{"model": "dungeon:Weapons/SM_Wep_Shield_Heater_01", "position": Vector3(0.0, 0.8, 1.8), "rotation": 0.0, "scale": 1.4},
	{"model": "dungeon:Weapons/SM_Wep_Shield_Heater_02", "position": Vector3(1.0, 0.8, 1.8), "rotation": 0.0, "scale": 1.4},
]

## The general store: a red canvas pavilion over a long trestle of wares, with its stock in
## bookcases behind and crates, a chest and sacks spilling out round the sides. Deliberately
## NOT the produce stand the two specialist shops use — red cloth against their grey tin roofs
## is what makes it read as a different kind of shop from across the clearing.
## The pavilion is the goblin camp's awning, its canvas about 3.4 m up at this scale. The
## table top is 0.96 m up; everything on it sits on its own base pivot, except the coin purses,
## whose pivot is at their middle (0.14 m up at scale 1). (Not Barrel_02 for the arrows: that
## one is a tapped cask lying on a stand, and arrows stood in it come out sideways.)
const GENERAL_STORE := [
	{"model": "dungeon:Props/SM_Prop_Goblin_Tent_03", "position": Vector3.ZERO, "rotation": 0.0, "scale": 1.25},
	# Stock at the back.
	{"model": "dungeon:Props/SM_Prop_Bookcase_01", "position": Vector3(-0.85, 0.0, -1.3), "rotation": 0.0, "scale": 1.25},
	{"model": "dungeon:Props/SM_Prop_Bookcase_02", "position": Vector3(0.85, 0.0, -1.3), "rotation": 0.0, "scale": 1.25},
	# The trestle, and what is laid out on it: potions down one end, scales and coin in the
	# middle, jars and a book at the other, a lantern at each corner.
	{"model": "dungeon:Props/SM_Prop_Table_01", "position": Vector3(0.0, 0.0, 0.55), "rotation": 0.0, "scale": 1.0},
	{"model": "dungeon:Items/SM_Item_Potion_01", "position": Vector3(-1.05, 0.96, 0.55), "rotation": 0.0, "scale": 1.8},
	{"model": "dungeon:Items/SM_Item_Potion_02", "position": Vector3(-0.7, 0.96, 0.75), "rotation": 30.0, "scale": 1.8},
	{"model": "dungeon:Items/SM_Item_Potion_03", "position": Vector3(-0.75, 0.96, 0.3), "rotation": 0.0, "scale": 1.8},
	{"model": "dungeon:Items/SM_Item_Potion_05", "position": Vector3(-0.4, 0.96, 0.6), "rotation": 60.0, "scale": 1.8},
	{"model": "dungeon:Items/SM_Item_Scale_01", "position": Vector3(0.05, 0.96, 0.45), "rotation": 0.0, "scale": 2.0},
	{"model": "dungeon:Items/SM_Item_Jar_01", "position": Vector3(0.65, 0.96, 0.45), "rotation": 0.0, "scale": 1.1},
	{"model": "dungeon:Items/SM_Item_Jar_02", "position": Vector3(1.0, 0.96, 0.65), "rotation": 0.0, "scale": 1.1},
	{"model": "dungeon:Items/SM_Item_Book_01", "position": Vector3(0.7, 0.96, 0.85), "rotation": 25.0, "scale": 1.6},
	{"model": "dungeon:Props/SM_Prop_Lantern_01", "position": Vector3(-1.35, 0.96, 0.2), "rotation": 0.0, "scale": 1.4},
	{"model": "dungeon:Props/SM_Prop_Lantern_02", "position": Vector3(1.35, 0.96, 0.2), "rotation": 0.0, "scale": 1.4},
	# Round the sides: a chest and a barrel of arrows on the left, a stack of crates and
	# sacks on the right.
	{"model": "dungeon:Props/SM_Prop_Chest_Wood_01", "position": Vector3(-2.35, 0.0, 0.2), "rotation": 28.0, "scale": 1.1},
	{"model": "dungeon:Props/SM_Prop_Barrel_01", "position": Vector3(-2.2, 0.0, 1.45), "rotation": 0.0, "scale": 1.0},
	# The arrow model lies along Z with its pivot at the middle, so it is stood up with -90
	# about X and lifted half its length (0.93 m x 1.4) to put the butt in the barrel.
	{"model": "dungeon:Items/SM_Arrow_01", "position": Vector3(-2.25, 1.0, 1.4), "rotation": Vector3(-84.0, 0.0, 5.0), "scale": 1.4},
	{"model": "dungeon:Items/SM_Arrow_01", "position": Vector3(-2.1, 1.0, 1.5), "rotation": Vector3(-96.0, 60.0, -4.0), "scale": 1.4},
	{"model": "dungeon:Items/SM_Arrow_01", "position": Vector3(-2.3, 1.0, 1.55), "rotation": Vector3(-88.0, 120.0, 8.0), "scale": 1.4},
	{"model": "dungeon:Items/SM_Arrow_01", "position": Vector3(-2.15, 1.0, 1.35), "rotation": Vector3(-92.0, 200.0, -7.0), "scale": 1.4},
	{"model": "dungeon:Props/SM_Prop_Crate_Wood_02", "position": Vector3(2.4, 0.0, -0.2), "rotation": -12.0, "scale": 0.85},
	{"model": "dungeon:Props/SM_Prop_Crate_Wood_03", "position": Vector3(2.45, 0.93, -0.2), "rotation": 14.0, "scale": 0.65},
	{"model": "dungeon:Props/SM_Prop_Crate_Wood_01", "position": Vector3(2.6, 0.0, 1.0), "rotation": 20.0, "scale": 0.7},
	{"model": "dungeon:Items/SM_Item_Bag_Large", "position": Vector3(1.9, 0.6, 1.5), "rotation": 0.0, "scale": 4.0},
	{"model": "dungeon:Items/SM_Item_Bags", "position": Vector3(2.4, 0.55, 1.75), "rotation": 40.0, "scale": 4.0},
]

## The smithy: the fort's lean-to again, over a stone forge with an iron hood and a flue up
## through the roof, an anvil out front and a barrel to quench in. The forge pit is 2.9 m
## across at scale 1 — a dungeon foundry's — so it is taken down to 0.6.
## The hood's pivot is at its middle; the flue's at its foot, which sits on the hood's top.
const SMITHY := [
	{"model": "farm:SM_Bld_Shelter_01", "position": Vector3.ZERO, "rotation": 0.0, "scale": 0.95},
	{"model": "dungeon:Props/SM_Prop_Forge_FirePit_01", "position": Vector3(-1.1, 0.0, -0.5), "rotation": 0.0, "scale": 0.6},
	{"model": "dungeon:Props/SM_Prop_Forge_Ventilation_01", "position": Vector3(-1.1, 2.0, -0.5), "rotation": 0.0, "scale": 0.6},
	{"model": "dungeon:Props/SM_Prop_Forge_Ventilation_Pipe_01", "position": Vector3(-1.1, 2.5, -0.5), "rotation": 0.0, "scale": 0.6},
	{"model": "farm:SM_Prop_Anvil_01", "position": Vector3(0.8, 0.0, 0.7), "rotation": 12.0, "scale": 1.4},
	{"model": "dungeon:Weapons/SM_Wep_Hammer_Small_01", "position": Vector3(1.45, 0.47, 1.0), "rotation": Vector3(0.0, 30.0, -14.0), "scale": 1.0},
	{"model": "farm:SM_Prop_Barrel_02", "position": Vector3(1.75, 0.0, -0.6), "rotation": 0.0, "scale": 1.0},
	{"model": "dungeon:Weapons/SM_Wep_BrokenSword_01", "position": Vector3(0.6, 0.83, 0.68), "rotation": Vector3(0.0, 12.0, 90.0), "scale": 1.0},
]

## Where the braziers' flames go, local to the fort like BARRACKS. Just above the bowl.
const BARRACKS_FIRES := [Vector3(-2.6, 0.35, 3.6), Vector3(2.6, 0.35, 3.6)]

## The stockade: sharpened stakes round the back and sides, open to the clearing, as a
## polyline local to the fort. The left side is cut short on purpose: run full length it put
## the stockade through the magician's house, and the watch-stand covers that corner anyway. The stakes' pivot is at their middle, so `y` buries the foot.
## Mixed lengths and a little lean, from a fixed seed, so the wall reads as cut by hand.
const PALISADE := [Vector3(-7.0, 0.0, -1.0), Vector3(-7.0, 0.0, -5.8), Vector3(8.4, 0.0, -5.8), Vector3(8.4, 0.0, 3.2)]
const PALISADE_SPACING := 0.42
const PALISADE_STAKES := [
	{"model": "dungeon:Props/SM_Prop_Log_Spike_01", "y": 0.95},   ## 3.1 m stake, 0.6 m in the ground
	{"model": "dungeon:Props/SM_Prop_Log_Spike_01", "y": 1.15},
	{"model": "dungeon:Props/SM_Prop_Log_Spike_03", "y": 0.85},   ## 2.0 m stake, nearly all of it showing
]
const PALISADE_SEED := 4417

## The healer's house, as a hedge-witch's round house. No pack has one, so it is built:
## the walls are the dungeon pack's round tower block (a stone drum 5.1 m across and 5 m tall)
## squashed to one storey, and the roof is the farm pack's hay pile — a low thatch-coloured
## dome — stretched over it with an overhang. An arched stone door frame and a plank door on
## the front, and a stubby stone flue through the thatch.
## On the house hang the witch's things: a horned skull under the eave over the door,
## shrunken heads hung from the eave either side, brambles round the foot of the wall,
## toadstools, and a cauldron bubbling green in the yard. Local like the others, +Z the door.
##
## Measurements the numbers below rest on: the drum's pivot is at its base and centre, so at
## (1.25, 0.55, 1.25) its wall face is 3.2 m out and its top 2.77 m up. The hay pile's pivot is
## at its base; at (3.4, 2.6, 3.2) it spans 8.4 m and rises 2.9 m, so its eave is about 4.2 m
## out at the 2.6 m it is set at. The door's hinge is its pivot, 0.04 m in from its left edge.
## The skull is the dungeon pack's dragon skull, nine metres long as shipped; at 0.09 it is a
## goat's. The shrunken heads' pivot is at their middle. The brambles lie along Z.
const WITCH_HUT := [
	# The house: stone drum, thatch dome, a flue through the thatch, the door on the front.
	{"model": "dungeon:Environments/Pillars/SM_Env_Wall_Round_01", "position": Vector3.ZERO, "rotation": 0.0, "scale": Vector3(1.25, 0.55, 1.25)},
	{"model": "farm:SM_Prop_Hay_Pile_01", "position": Vector3(0.0, 2.6, 0.0), "rotation": 15.0, "scale": Vector3(3.4, 2.6, 3.2)},
	{"model": "dungeon:Environments/Pillars/SM_Env_Pillar_Round_Simple_01", "position": Vector3(1.4, 3.3, -0.9), "rotation": 0.0, "scale": Vector3(0.45, 0.6, 0.45)},
	{"model": "dungeon:Environments/Walls/SM_Env_Door_Frame_Round_01", "position": Vector3(0.0, 0.0, 3.15), "rotation": 0.0, "scale": 0.85},
	{"model": "dungeon:Environments/Walls/SM_Env_Door_01", "position": Vector3(-0.47, 0.0, 3.25), "rotation": 0.0, "scale": 0.72},
	# Over the door, and hung from the eave either side of it.
	{"model": "dungeon:Environments/Bones/SM_Env_Bone_Skull_01", "position": Vector3(0.0, 2.12, 3.45), "rotation": 0.0, "scale": 0.08},
	{"model": "dungeon:Items/SM_Item_Shrunken_Head", "position": Vector3(-1.6, 2.05, 3.85), "rotation": 15.0, "scale": 3.0},
	{"model": "dungeon:Items/SM_Item_Shrunken_Head", "position": Vector3(1.7, 2.0, 3.8), "rotation": -25.0, "scale": 3.0},
	{"model": "dungeon:Items/SM_Item_Shrooms", "position": Vector3(1.05, 2.15, 3.95), "rotation": 0.0, "scale": 4.0},
	# Brambles round the foot of the wall, tangent to it.
	{"model": "dungeon:Environments/Misc/SM_Env_Vine_Spikes_01", "position": Vector3(-3.4, 0.0, -0.8), "rotation": 0.0, "scale": 1.3},
	{"model": "dungeon:Environments/Misc/SM_Env_Vine_Spikes_01", "position": Vector3(3.4, 0.0, -1.6), "rotation": 180.0, "scale": 1.2},
	{"model": "dungeon:Environments/Misc/SM_Env_Vine_Spikes_01", "position": Vector3(-1.5, 0.0, -3.4), "rotation": 90.0, "scale": 1.1},
	# Toadstools — the meadow's ornament mushrooms, scaled up the way the magician's are.
	{"model": "SM_Prop_Mushroom_Group_02", "position": Vector3(-3.4, 0.0, 2.6), "rotation": 0.0, "scale": 6.0},
	{"model": "SM_Prop_Mushroom_Group_03", "position": Vector3(3.3, 0.0, 1.2), "rotation": 70.0, "scale": 5.5},
	{"model": "SM_Prop_Mushroom_01", "position": Vector3(2.6, 0.0, 4.6), "rotation": 0.0, "scale": 6.0},
	{"model": "SM_Prop_Mushroom_02", "position": Vector3(-0.9, 0.0, 5.8), "rotation": 30.0, "scale": 5.0},
	# The cauldron in the yard, on a ring of stones. Lit green by Town (COMPOUNDS fires).
	{"model": "SM_Prop_Camp_Fireplace_Stones_01", "position": Vector3(-2.4, 0.0, 5.4), "rotation": 0.0, "scale": 1.5},
	{"model": "dungeon:Props/SM_Prop_Cauldron_01", "position": Vector3(-2.4, 0.05, 5.4), "rotation": 25.0, "scale": 1.4},
	# Potions hung on poles at the yard's edge, candles on the porch step, a dead stump, and a
	# skull on a stake for anyone who missed the one over the door.
	{"model": "dungeon:Items/SM_Item_Potion_Pole_01", "position": Vector3(1.7, 0.0, 5.6), "rotation": -30.0, "scale": 1.3},
	{"model": "dungeon:Items/SM_Item_Potion_Pole_01", "position": Vector3(3.4, 0.0, 3.6), "rotation": -110.0, "scale": 1.3},
	{"model": "dungeon:Props/SM_Prop_Candles_01", "position": Vector3(0.9, 0.0, 4.4), "rotation": 0.0, "scale": 1.8},
	{"model": "dungeon:Props/SM_Prop_Candles_01", "position": Vector3(-0.9, 0.0, 4.5), "rotation": 40.0, "scale": 1.6},
	{"model": "farm:SM_Env_Tree_Stump_01", "position": Vector3(-4.6, 0.6, 0.8), "rotation": 40.0, "scale": 0.9},
	{"model": "dungeon:Props/SM_Prop_Log_Spike_03", "position": Vector3(-4.2, 0.75, 4.6), "rotation": 0.0, "scale": 1.0},
	{"model": "dungeon:Environments/Bones/SM_Env_Bone_Skull_01", "position": Vector3(-4.2, 1.78, 4.6), "rotation": 30.0, "scale": 0.05},
]

## Every compound by name, with what it lights. `fires` and `smoke` are local like the parts;
## `palisade` builds the stockade (PALISADE) round it.
const COMPOUNDS := {
	"barracks": {"parts": BARRACKS, "fires": BARRACKS_FIRES, "palisade": true},
	"weapon_stall": {"parts": WEAPON_STALL},
	"armour_stall": {"parts": ARMOUR_STALL},
	"general_store": {"parts": GENERAL_STORE},
	# The cauldron glows green rather than orange, and so does what comes out of the chimney.
	# The smoke comes out of the top of the flue (3.3 m + 3.95 x 0.6).
	"witch_hut": {"parts": WITCH_HUT,
		"fires": [{"at": Vector3(-2.4, 1.15, 5.4), "tint": Color(0.45, 1.0, 0.35, 0.8), "light": Color(0.45, 1.0, 0.4)}],
		"smoke": [{"at": Vector3(1.4, 5.7, -0.9), "tint": Color(0.62, 0.86, 0.52)}]},
	# The forge glows rather than blazes: the flame sits down in the pit, and the smoke comes
	# out of the top of the flue.
	"smithy": {"parts": SMITHY, "fires": [Vector3(-1.1, 0.45, -0.5)], "smoke": [Vector3(-1.1, 3.55, -0.5)]},
}

## Fence runs, as [start, end] pairs. Posts are placed along each run at the model's length.
## Meadow_Fence_01 measures 2.59 along x with its pivot at one end, so a run is laid out in
## 2.5 m steps and the last panel is dropped rather than overshooting.
const FENCE_MODEL := "SM_Prop_Meadow_Fence_01"
const FENCE_SPAN := 2.5
const FENCES := [
	[Vector3(-22.0, 0.0, 6.0), Vector3(-12.0, 0.0, 7.5)],
	[Vector3(11.0, 0.0, 7.5), Vector3(22.0, 0.0, 5.0)],
]

## Who stands around the clearing for atmosphere. Sidekick bodies (sidekick_body.gd), the same
## as the party and the human enemies, dressed by `props` — set on the body before it is built,
## exactly as a class's look is (CharacterData.CLASS_BODIES). Not the farm pack's characters on
## purpose: those are modern farmers in caps and overalls.
##
## Scaled by TOWNSFOLK_SCALE on top of the body's own MODEL_SCALE, the same as the party line-up
## (Town._place_party_member), so the guard and the party stand at the same height. 2.75 was
## chosen for the old Kenney models, which next to a 4 m cabin and a 3.3 m stall read as
## children at the combat scene's 1.6.
const TOWNSFOLK_SCALE := 2.75
const _TOWN_BODY := "res://scenes/characters/sidekick_model.tscn"
## Tunic, trousers and boots — the same plain clothes the party wears under its gear.
const _TOWN_CLOTHES := ["SK_FANT_KNGT_06_10TORS_HU01", "SK_FANT_KNGT_04_17HIPS_HU01",
	"SK_FANT_KNGT_04_18LEGL_HU01", "SK_FANT_KNGT_04_19LEGR_HU01",
	"SK_FANT_KNGT_04_20FOTL_HU01", "SK_FANT_KNGT_04_21FOTR_HU01"]
const TOWNSFOLK := [
	# A town guard by the market, in Knight 01's white-and-gold plate.
	{"model": _TOWN_BODY, "position": Vector3(-3.5, 0.0, 6.5), "rotation": 166.0, "props": {
		# No hair: the helm is open at the crest, and hair pokes straight through it.
		"hair": "none", "facial_hair": "SK_HUMN_BASE_03_09FCHR_HU01",
		"outfit": ["SK_FANT_KNGT_01_10TORS_HU01", "SK_FANT_KNGT_01_11AUPL_HU01",
			"SK_FANT_KNGT_01_12AUPR_HU01", "SK_FANT_KNGT_01_13ALWL_HU01",
			"SK_FANT_KNGT_01_14ALWR_HU01", "SK_FANT_KNGT_01_15HNDL_HU01",
			"SK_FANT_KNGT_01_16HNDR_HU01", "SK_FANT_KNGT_01_17HIPS_HU01",
			"SK_FANT_KNGT_01_18LEGL_HU01", "SK_FANT_KNGT_01_19LEGR_HU01",
			"SK_FANT_KNGT_01_20FOTL_HU01", "SK_FANT_KNGT_01_21FOTR_HU01",
			"SK_FANT_KNGT_01_29ASHL_HU01", "SK_FANT_KNGT_01_30ASHR_HU01",
			"SK_FANT_KNGT_01_22AHED_HU01"]}},
	# The magician, outside his own house: long hair, a beard, a tabard over plain clothes.
	{"model": _TOWN_BODY, "position": Vector3(10.0, 0.0, -3.0), "rotation": -140.0, "props": {
		"hair": "SK_HUMN_BASE_09_02HAIR_HU01", "facial_hair": "SK_HUMN_BASE_10_09FCHR_HU01",
		"skin_palette": "T_HumanSpecies_02ColorMap.png",
		"outfit": _TOWN_CLOTHES + ["SK_FANT_KNGT_04_25AHPF_HU01", "SK_FANT_KNGT_04_27AHPL_HU01",
			"SK_FANT_KNGT_04_28AHPR_HU01"]}},
	# A ranger passing through, quiver on her back.
	{"model": _TOWN_BODY, "position": Vector3(-10.5, 0.0, 7.5), "rotation": 200.0, "props": {
		"hair": "SK_HUMN_BASE_07_02HAIR_HU01", "facial_hair": "none",
		"skin_palette": "T_HumanSpecies_03ColorMap.png",
		"outfit": _TOWN_CLOTHES, "show_quiver": true}},
]

## Where the PARTY stands, one mark per member, main character first.
##
## Different from TOWNSFOLK above in the way that matters: those are three fixed models placed
## for atmosphere, and these are whoever is actually in GameState.party, built from each
## member's own class body and model props — so an archer in the party has their quiver on
## their back here exactly as they do in the dungeon.
##
## Downstage and facing the camera, in the open grass to the right of the bench. That is the
## one part of the clearing with nothing in it, and it is where a party photograph belongs:
## close enough to read faces, far enough forward that nobody is standing in a shopfront.
## Turned a few degrees off straight-on so four of them do not line up like a police lineup.
## `clear` is deliberately tiny next to DEFAULT_CLEARANCE: these marks are in the meadow, and
## the point of standing the party in long grass is that they are standing in long grass. It
## only has to be enough that nobody is wearing a bush.
## The marks are spread as far as the clearing allows; the NAMES sort themselves out in screen
## space, where a collision can actually be measured (Town._position_name_tags). An earlier
## version staggered the label heights here instead, which reads as a guess and was one: it
## held for "Wren" and came apart for "Tobin the Quiet".
const PARTY_STAND := [
	{"position": Vector3(5.0, 0.0, 9.0), "rotation": 172.0, "clear": 1.5},
	{"position": Vector3(7.8, 0.0, 9.8), "rotation": 186.0, "clear": 1.5},
	{"position": Vector3(10.6, 0.0, 9.0), "rotation": 168.0, "clear": 1.5},
	{"position": Vector3(13.4, 0.0, 9.8), "rotation": 192.0, "clear": 1.5},
]

## Where a party member's name floats, above their feet. Their models stand about 1.8 m at
## TOWNSFOLK_SCALE, so this clears the tallest hat in the set.
const PARTY_LABEL_Y := 2.35

## Font size for a floating name. Smaller than a shop sign: it labels a person, not a door.
const PARTY_LABEL_SIZE := 15

## The trees that make it a clearing rather than a field: a ring of birches with bigger meadow
## trees behind them for canopy mass. Generated rather than listed — forty hand-written tree
## positions would be forty numbers nobody will ever read — but from a FIXED seed, so the wood
## looks the same every time the player walks into town.
## How close a scattered plant may come to a placed object when that object does not say. Six
## metres keeps a bush out of a shopfront without thinning the clearing.
const DEFAULT_CLEARANCE := 6.0

const FOREST_SEED := 20260917
const BIRCH_MODELS := ["SM_Env_Tree_Birch_01", "SM_Env_Tree_Birch_02", "SM_Env_Tree_Birch_03"]
const CANOPY_MODELS := ["SM_Env_Tree_Meadow_01", "SM_Env_Tree_Meadow_02"]
const BUSH_MODELS := ["SM_Env_Bush_01", "SM_Env_Bush_02", "SM_Env_Bush_03"]
const GRASS_MODELS := ["SM_Env_Grass_Med_Clump_01", "SM_Env_Grass_Med_Clump_02", "SM_Env_Grass_Med_Clump_03"]
const FLOWER_MODELS := ["SM_Env_Flowers_Flat_01", "SM_Env_Flowers_Flat_02", "SM_Env_Flowers_Flat_03"]
const COVER_MODELS := ["SM_Env_Ground_Cover_01", "SM_Env_Ground_Cover_02", "SM_Env_Ground_Cover_03"]
const ROCK_MODELS := ["SM_Env_Rock_01", "SM_Env_Rock_02", "SM_Env_Rock_03", "SM_Env_Rock_04"]

## THE FOREST, IN THREE BANDS
## One ring of trees left the sky showing between the trunks, and a clearing with a visible
## horizon is a field. So the wood is built in depth instead: a near line you can read
## individual trees in, then two bands behind it that exist only to close the gap between the
## trunks and the sky.
##
## Each band is cheaper than the one in front of it. `lod` picks which of Synty's baked levels
## to keep — a birch is 20,000 verts at LOD0 and 5,700 at LOD2, indistinguishable at 60 m —
## which is what makes a wood this deep affordable at all. See SyntyModel.meadow.
## `max_z` drops a band's trees behind the camera, which stands at z = +34 and looks the other
## way. Without it a third of every band grows where nothing can ever see it — paid for in
## vertices and given back as nothing.
const FOREST_BANDS := [
	{"models": BIRCH_MODELS, "count": 46, "radius": Vector2(18.0, 34.0), "scale": Vector2(0.85, 1.25), "lod": 0},
	{"models": BIRCH_MODELS, "count": 80, "radius": Vector2(34.0, 58.0), "scale": Vector2(0.9, 1.35), "lod": 1, "max_z": 22.0},
	{"models": BIRCH_MODELS, "count": 110, "radius": Vector2(58.0, 96.0), "scale": Vector2(1.0, 1.5), "lod": 2, "max_z": 22.0},
	# The big canopy trees go behind the birches, where their mass reads as depth rather than
	# as a single tree hogging the frame.
	{"models": CANOPY_MODELS, "count": 14, "radius": Vector2(30.0, 52.0), "scale": Vector2(0.9, 1.3), "lod": 1, "max_z": 22.0},
	{"models": CANOPY_MODELS, "count": 24, "radius": Vector2(52.0, 92.0), "scale": Vector2(1.0, 1.4), "lod": 2, "max_z": 22.0},
	# THE SKYLINE BAND, and the only one that actually hides the horizon.
	#
	# The camera stands 13.5 m up and looks down, so its eye line runs ABOVE every ten-metre
	# birch on flat ground however many of them there are — which is why the first deep wood
	# still left sky showing along the edges of the frame. Only a tree taller than the camera
	# can cross that line, so these are the pack's big meadow trees (15-18 m) scaled half
	# again, standing far enough back to read as the mass of a forest rather than as
	# individual trees.
	{"models": CANOPY_MODELS, "count": 44, "radius": Vector2(62.0, 112.0), "scale": Vector2(1.6, 2.4), "lod": 2, "max_z": 24.0},
]

## Low mounds on the skyline behind the wood, so the far tree line stands against something
## rather than against flat sky.
const HILL_MODEL := "SM_Env_Background_Hill_01"
const HILL_COUNT := 10
const HILL_RADIUS := Vector2(115.0, 150.0)
const HILL_SCALE := Vector2(2.5, 5.0)

## Counts and the bands they are scattered in. The clearing floor is kept clear of trees so
## the buildings and the buttons over them are never hidden behind a trunk.
const BUSH_COUNT := 16
const BUSH_RADIUS := Vector2(16.0, 30.0)
const GRASS_COUNT := 90
const GRASS_RADIUS := Vector2(6.0, 26.0)
const FLOWER_COUNT := 45
const FLOWER_RADIUS := Vector2(5.0, 24.0)
const COVER_COUNT := 40
const COVER_RADIUS := Vector2(4.0, 25.0)
const ROCK_COUNT := 14
const ROCK_RADIUS := Vector2(10.0, 28.0)

## Two exclusion zones, because "keep it clear" means different things for a birch and for a
## clump of grass.
##
## BIG things — trees, bushes, boulders — are kept out of the whole near and middle field.
## That is not about the buildings: it is about the CAMERA. A boulder scattered at z = +20
## sits between the lens and the village and blocks half the shot, which is exactly what the
## first build of this scene did.
const KEEP_CLEAR_BIG := AABB(Vector3(-30.0, -1.0, -14.0), Vector3(60.0, 30.0, 52.0))

## SMALL things — grass, flowers, ground cover — only have to stay off the shopfronts. Grass
## in the near field is welcome; it frames the shot.
const KEEP_CLEAR_SMALL := AABB(Vector3(-24.0, -1.0, -12.0), Vector3(48.0, 20.0, 18.0))
