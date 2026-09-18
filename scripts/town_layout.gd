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
## works in a fairytale wood. The three shops are market stalls. When a Synty fantasy village
## pack arrives, the fix is to change `model` on these entries and nothing else.

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
		"model": "SM_Bld_Stone_Cabin_01",
		"position": Vector3(-13.5, 0.0, -5.0),
		"rotation": 18.0,
		"scale": 1.0,
		"sign_at": Vector3(-13.5, 5.4, -5.0),
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
		"note": "Drill and instruction, in a tent until somebody builds a fort.",
		"model": "SM_Prop_Camp_Tent_01",
		"position": Vector3(20.5, 0.0, -2.0),
		"rotation": -38.0,
		"scale": 2.4,
		"sign_at": Vector3(20.5, 4.2, -2.0),
		"action": "training",
	},
	{
		"id": "armorer",
		"label": "Armorer",
		"screen": "",
		"note": "Armour and shields.",
		"model": "farm:SM_Bld_ProduceStand_01",
		"position": Vector3(-6.5, 0.0, 2.0),
		"rotation": 8.0,
		"scale": 1.15,
		"sign_at": Vector3(-6.5, 4.2, 2.0),
		"action": "shop",
	},
	{
		"id": "weaponsmith",
		"label": "Weapon Shop",
		"screen": "",
		"note": "Blades, bows and hafted things.",
		"model": "farm:SM_Bld_ProduceStand_01",
		"position": Vector3(0.5, 0.0, 3.5),
		"rotation": -4.0,
		"scale": 1.15,
		"sign_at": Vector3(0.5, 4.2, 3.5),
		"action": "shop",
	},
	{
		"id": "general",
		"label": "General Store",
		"screen": "",
		"note": "Potions, arrows and everything else.",
		"model": "farm:SM_Bld_ProduceStand_01",
		"position": Vector3(7.5, 0.0, 2.5),
		"rotation": -14.0,
		"scale": 1.15,
		"sign_at": Vector3(7.5, 4.2, 2.5),
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
	{"model": "SM_Prop_Camp_Tanning_Rack_01", "position": Vector3(-9.5, 0.0, 4.5), "rotation": 24.0, "scale": 1.2},
	# The mercenaries' fire, in front of their tent, with a cook pot over it and a crate to sit
	# on. The clearing already has a campfire down by the bench (above); this is a second one,
	# and it is what makes the second tent read as a camp rather than as a spare fort.
	{"model": "SM_Prop_Camp_Fireplace_Stones_01", "position": Vector3(-7.0, 0.0, -10.8), "rotation": 0.0, "scale": 1.3},
	{"model": "SM_Prop_Camp_Fire_Tripod_01", "position": Vector3(-7.0, 0.0, -10.8), "rotation": 14.0, "scale": 1.3},
	{"model": "SM_Prop_Camp_Crate_01", "position": Vector3(-5.2, 0.0, -12.2), "rotation": -32.0, "scale": 1.1},
	{"model": "SM_Prop_Bridge_01", "position": Vector3(24.0, 0.0, 8.0), "rotation": 74.0, "scale": 1.2},
	{"model": "SM_Prop_Birdhouse_01", "position": Vector3(-17.5, 0.0, 1.0), "rotation": 0.0, "scale": 1.0},
	# Washing on the line, for the wind to move.
	{"model": "farm:SM_Prop_ClothesLine_01", "position": Vector3(-18.0, 0.0, -2.0), "rotation": 74.0, "scale": 1.0},
	{"model": "farm:SM_Prop_ClothesLine_02", "position": Vector3(-19.5, 0.0, 3.5), "rotation": 62.0, "scale": 1.0},
	# The armourer's anvil, and crates and barrels around the stalls.
	{"model": "farm:SM_Prop_Anvil_01", "position": Vector3(-8.6, 0.0, 3.6), "rotation": 32.0, "scale": 1.3},
	{"model": "SM_Prop_Camp_Crate_01", "position": Vector3(-4.6, 0.0, 3.4), "rotation": 18.0, "scale": 1.1},
	{"model": "SM_Prop_Camp_Crate_01", "position": Vector3(2.6, 0.0, 4.8), "rotation": -26.0, "scale": 1.1},
	{"model": "farm:SM_Prop_Barrel_01", "position": Vector3(9.4, 0.0, 3.8), "rotation": 0.0, "scale": 1.0},
	{"model": "farm:SM_Prop_Barrel_02", "position": Vector3(6.0, 0.0, 4.4), "rotation": 40.0, "scale": 1.0},
	{"model": "SM_Prop_Camp_Bucket_01", "position": Vector3(-12.0, 0.0, 0.4), "rotation": 0.0, "scale": 1.0},
	{"model": "SM_Prop_Camp_Bucket_02", "position": Vector3(-15.2, 0.0, -0.6), "rotation": 30.0, "scale": 1.0},
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

## Fence runs, as [start, end] pairs. Posts are placed along each run at the model's length.
## Meadow_Fence_01 measures 2.59 along x with its pivot at one end, so a run is laid out in
## 2.5 m steps and the last panel is dropped rather than overshooting.
const FENCE_MODEL := "SM_Prop_Meadow_Fence_01"
const FENCE_SPAN := 2.5
const FENCES := [
	[Vector3(-22.0, 0.0, 6.0), Vector3(-12.0, 0.0, 7.5)],
	[Vector3(11.0, 0.0, 7.5), Vector3(22.0, 0.0, 5.0)],
]

## Where the game's own hero models stand around as townsfolk. Using these rather than the
## farm pack's characters on purpose: the farm's people are modern farmers in caps and
## overalls, and these are the game's own soldier, wizard and ranger, already rigged with the
## idle animation the combat scene plays.
## The combat scene scales these same models by Combatant.CHARACTER_SCALE, and without it a
## townsperson stands about half a metre tall.
## 1.6 is what the combat scene uses, where everything is scaled to a 2 m grid. Next to a
## 4 m cabin and a 3.3 m market stall those same models read as children, so the town
## stands them at roughly human height instead.
const TOWNSFOLK_SCALE := 2.75
const TOWNSFOLK := [
	{"model": "res://scenes/characters/soldier_model.tscn", "position": Vector3(-3.5, 0.0, 6.5), "rotation": 166.0},
	{"model": "res://scenes/characters/wizard_model.tscn", "position": Vector3(10.0, 0.0, -3.0), "rotation": -140.0},
	{"model": "res://scenes/characters/male_d_model.tscn", "position": Vector3(-10.5, 0.0, 7.5), "rotation": 200.0},
]

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
