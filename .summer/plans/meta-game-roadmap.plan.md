---
name: meta-game-roadmap
overview: >-
  Build the meta-game layer around the existing combat slice: persistent
  character data, character creation -> town -> quest -> results -> town loop,
  saves, progression/economy, random quest generation, and finally party
  hirelings.
createdAt: '2026-09-16T00:00:00.000Z'
todos:
  - id: gamestate-autoload
    content: >-
      Phase 0: GameState autoload holding party (Array[CharacterData]), gold,
      and current quest info; survives all scene changes
    status: completed
  - id: characterdata-resource
    content: >-
      Phase 0: CharacterData resource (name, class/model, stats, skill levels,
      XP, inventory as item paths + counts, equipment slots) with
      to_dict()/from_dict()
    status: completed
  - id: extract-quest-scene
    content: >-
      Phase 0: extract the battlefield out of main.tscn into quest_scene.tscn;
      main.tscn becomes a thin bootstrapper that decides which screen to show
    status: completed
  - id: hydration-roundtrip
    content: >-
      Phase 0: quest scene spawns the player Combatant from CharacterData on
      load and writes results back (XP, loot kept, gold) on quest end -
      proof-of-architecture milestone, test before building anything else
    status: completed
  - id: quest-end-contract
    content: >-
      Phase 1: explicit victory/defeat signal from the combat layer -> results
      screen (XP, loot summary) -> back to town
    status: completed
  - id: town-screen
    content: >-
      Phase 1: town screen as pure UI (background + Shop / Training / Quest
      Board / Adventure buttons) - no walkable 3D town yet
    status: completed
  - id: character-creation
    content: >-
      Phase 1: character creation screen (name + class from existing
      soldier/wizard/archer models + starting stats) feeding a fresh
      CharacterData into GameState
    status: completed
  - id: save-load
    content: >-
      Phase 2: save/load to user:// as JSON with a schema version field;
      autosave on every return to town
    status: completed
  - id: xp-training
    content: >-
      Phase 3: XP -> skill/stat progression rules; Training screen in town
      spends gold to improve skills
    status: completed
  - id: shop
    content: >-
      Phase 3: shop buy/sell using existing ItemResource items; add a gold
      value field to ItemResource
    status: completed
  - id: questdef-resource
    content: >-
      Phase 4: QuestDef resource (seed, difficulty tier, theme, enemy budget,
      loot budget, reward gold)
    status: pending
  - id: quest-board
    content: >-
      Phase 4: Quest Board UI generating 3-5 random QuestDefs each visit with
      name / difficulty / reward
    status: pending
  - id: enemy-templates
    content: >-
      Phase 4: enemy template data files (stats, model scene, abilities,
      difficulty cost, loot table) + a spawner that spends the enemy budget
    status: pending
  - id: loot-tables
    content: >-
      Phase 4: loot tables per theme/difficulty; generator places loot
      containers
    status: pending
  - id: room-builder-params
    content: >-
      Phase 4: parameterize room_builder.gd - seed + difficulty + theme ->
      layout + spawn points + loot points (room-and-corridor patterns first)
    status: pending
  - id: party-hirelings
    content: >-
      Phase 5: GameState.party becomes multi-member; hire screen in town; quest
      scene spawns all members as player-controlled combatants
    status: pending
---
## Goal

Create a main character (later a party with hirelings) that progresses skills
and collects items across many quests. Flow:

    character creation -> town (training / purchases / quest board)
                       -> quest scene -> results -> town

with random quest generation (layout, enemies, loot) at varying difficulty
tiers. The aim of play is to make the character more powerful and skilled so it
can solve harder and harder quests.

## Current state (assessed 2026-09-16)

The tactical combat slice - the hard part of this genre - is well developed:

- Turn-based combat core: `combat_manager.gd`, `combatant.gd` (class_name
  Combatant), `player.gd`, `enemy.gd`, `combatant_stats.gd`, ~12 ability
  scripts under `scripts/abilities/` (move, melee, ranged, firebolt, shove,
  trip, sneak, throw, ...)
- Items / inventory: `item_resource.gd` (class_name ItemResource, .tres items),
  `inventory_component.gd`, equipment + inventory + loot UI, `ground_item.gd`,
  `loot_container.gd`
- Level: `room_builder.gd`, `door.gd`, `dungeon_floor.gd`,
  `camera_controller.gd`
- `party_panel.gd` / `scenes/party_panel.tscn` already exist - good news for
  the later hirelings goal
- Assets: PolygonDungeon pack (16 enemy prefabs, weapons, props); player models
  soldier / wizard / archer / male_d

What is missing is the entire meta-game layer:

- `main.tscn` (root "Battlefield") is the only game scene
- no `[autoload]` section in `project.godot`
- no save system, no `user://` writes
- zero `change_scene` calls anywhere in `scripts/`

## Design flaws to fix (ordered by risk)

1. **All character state lives inside the battle scene.** Stats, skills,
   inventory and equipment are properties on nodes inside `main.tscn`. The
   moment a scene switch happens (town -> quest -> town) those nodes are freed
   and everything is lost. This is the #1 architectural blocker. Fix with a
   data/view split: a persistent `CharacterData` resource in an autoload, with
   the `Combatant` node as a disposable view hydrated from that data at quest
   start and written back at quest end.
2. **No persistence layer at all.** A progression game without saves is not a
   progression game. Version the save schema from day one - the character
   format will change many times.
3. **Single-scene architecture.** `main.tscn` is simultaneously the game, the
   level and the UI. The battlefield must become one scene among several
   (character creation, town, quest, results) with a thin flow controller
   deciding what loads next.
4. **Shared item resources are a save/load trap.** `.tres` items are great for
   authoring, but (a) saving an inventory needs stable item IDs or resource
   paths, and (b) any runtime mutation (durability, enchantments) must
   `duplicate()` first or every sword in the game changes. Decision: items stay
   immutable templates referenced by path to start; instance-with-state only if
   a feature demands it.
5. **Enemies and loot are hand-placed / hardcoded.** Random generation needs
   enemy *templates* (data: stats, model, abilities, difficulty cost, loot
   table) rather than configured scene nodes. The existing enemy/Combatant
   split makes this very doable.
6. **No victory/defeat flow contract.** `combat_manager.gd` knows when combat
   ends, but nothing above it listens. Quest end conditions (all enemies dead /
   reach exit / party down) must be an explicit signal the flow controller can
   act on.
7. **`room_builder.gd` is coupled to the test scenario.** For random generation
   it needs to take seed + difficulty + theme and output layout + spawn points
   + loot points. Refactor toward that shape rather than rewriting.

None of these are deep flaws - the combat layer is cleanly separated. The
design simply grew as a single test scenario, which is what it was.

## Phase 0 - Foundations (before any new screens)

1. `GameState` autoload: party (`Array[CharacterData]`), gold, current quest.
2. `CharacterData` resource with `to_dict()` / `from_dict()`.
3. Extract the battlefield into `quest_scene.tscn`; `main.tscn` becomes a thin
   bootstrapper.
4. Hydration round-trip: spawn the player Combatant from `CharacterData`, write
   results back on quest end.

Highest-risk refactor, so do it first, while the codebase is still one scene.
Every later phase gets easier, and nothing in Phases 1-5 is worth building
until character state survives a scene change.

## Phase 1 - Game loop skeleton

5. Quest end contract -> results screen -> town.
6. Town screen as pure UI (full loop for ~5% of the effort of a 3D town; can be
   replaced later without touching anything else).
7. Character creation screen -> fresh `CharacterData` into `GameState`.

At the end of Phase 1 the complete loop exists. Everything after is content and
depth.

## Phase 2 - Persistence

8. Versioned JSON save/load to `user://`; autosave on every return to town
   (the natural checkpoint - avoids mid-quest save complexity entirely).

## Phase 3 - Progression and economy

9. XP -> skill/stat progression; Training screen spends gold.
10. Shop buy/sell; `ItemResource` gains a gold value field.

## Phase 4 - Random quests (the payoff)

11. `QuestDef` resource.
12. Quest Board UI: 3-5 random quests per visit.
13. Enemy templates + budget-spending spawner (the 16 dungeon prefabs give a
    ready roster).
14. Loot tables per theme/difficulty.
15. Parameterized `room_builder.gd`.

## Phase 5 - Party / hirelings

16. Multi-member `GameState.party`, hire screen in town, quest scene spawns all
    members as player-controlled combatants. The turn-based combat manager and
    `party_panel.gd` already cover most of this layer - which is why it is safe
    to defer.

## Verification per phase

- Phase 0: character state (stats, XP, inventory, equipment) survives a
  town -> quest -> town round-trip.
- Phase 1: full loop runs - create character, town, quest, results, town.
- Phase 2: quit, relaunch, continue - same character, same gear, same gold.
- Phase 4: two different seeds produce two different layouts, enemy sets and
  loot; the same seed reproduces the same quest.

## Phase 0 as built (2026-09-16)

All four Phase 0 steps are done and verified. What exists now:

- `scripts/game_state.gd` — the `GameState` autoload (registered in
  `project.godot`): `party` (Array of CharacterData), `gold`, `current_quest`,
  `last_result`, plus `award_xp` / `add_gold` / `rest_party` and
  `to_dict` / `from_dict` for Phase 2 to write.
- `scripts/character_data.gd` — `CharacterData`: identity, class, its own
  `CombatantStats` block, level/xp, carried wounds, bag + equipment map, and
  the hydration pair `apply_to` (before the node enters the tree, so `_ready`
  derives hit points from the right block) / `restore_into` (gear and vitals
  once it is live) / `capture_from` (write-back).
- `scenes/quest_scene.tscn` + `scripts/quest_scene.gd` — the battlefield, now
  one scene among several, with the root script owning hydration and capture.
- `scenes/bootstrap.tscn` + `scripts/bootstrap.gd` — the new main scene: flow
  controller plus a placeholder town readout (party, gold, last result, Rest,
  Go Adventuring).
- `scenes/characters/hero.tscn` — the body a party member is spawned into; the
  model is added per `class_id` at spawn.
- `tools/test_meta_roundtrip.tscn` — run it to check the round trip. 105
  checks, four laps, and it fails on stat drift rather than only on a broken
  first trip.

Deviations from the plan above, and why:

- **`scenes/bootstrap.tscn` is the main scene, not `main.tscn`.** The old
  `main.tscn` WAS the battlefield, so it became `scenes/quest_scene.tscn` and
  the bootstrapper is a new file. `main.tscn` is deleted (recoverable from git).
- **The first quest seeds the party from the hand-placed heroes** rather than
  from a creation screen, which does not exist until Phase 1. Their attributes
  and starting gear were the only record of what a starting hero is made of.
  Every later run spawns from data and retires those bodies.
- **Quest end is a Town button in the system menu** (`finish_quest`). Victory
  and defeat get their own signal in Phase 1; both land on the same function.
- **Quest rewards are counted in corpses** (`XP_PER_KILL`, `GOLD_PER_KILL` in
  quest_scene.gd). Phase 4 replaces that with `QuestDef.reward_gold`.
- **Items now carry `template_path`** (`ItemResource.make_instance()`), which
  is what makes a saved inventory possible — flaw 4 above, settled the simple
  way: immutable templates, per-character instances that know their template.
- `CombatManager` now boots deferred, so the party and (in Phase 4) the
  generated room are assembled before the initiative order is dealt.

Editor caveat: the quest scene's root script was added by editing the `.tscn`
directly, because the MCP cannot assign a script property. The editor may still
hold a cached copy of that scene WITHOUT the script — reload the scene tab
before editing it, or a save from that tab will drop the root script. The
symptom is the Town button reporting "this is not a quest", and the round-trip
test fails immediately.

## Phase 1 as built (2026-09-17)

The loop is closed: creation -> town -> quest -> results -> town.

- `scripts/bootstrap.gd` is now genuinely thin — one decision (is there a party?)
  and a scene change. Phase 2 adds "is there a save?" in front of it.
- `scenes/character_creation.tscn` + `scripts/character_creation.gd` — name,
  class, a readout of what that class is, Begin. Also a door back to the old
  test scenario, which starts a quest with an empty party and lets the seeding
  path make the authored trio real.
- `scripts/character_classes.gd` — the catalogue: soldier / archer / wizard,
  each with the stats and gear the authored heroes had, so a created character
  is the same character the dungeon was balanced around. `stats` lists only
  what differs from CombatantStats' defaults.
- `scenes/town.tscn` + `scripts/town.gd` — Riverwatch. Party roster, gold, Go
  Adventuring, Rest, and buttons for Quest Board / Shop / Training that say
  which phase they belong to rather than being absent.
- `scenes/results_screen.tscn` + `scripts/results_screen.gd` — outcome, kills,
  xp, gold, what was carried out, who was carried home. Consumes
  `GameState.last_result` so an adventure is never reported twice.
- `scripts/screen_panel.gd` — shared furniture for those three flat screens.
- `CombatManager` now emits `fight_won` and `party_wiped`. `fight_won` is
  deliberately NOT "quest cleared" — the room still has a chest in it — so the
  quest scene only records that the field is held, and the Town button then
  reads "Leave Victorious" and finishes as a victory. `party_wiped` IS final
  and goes straight to the results screen.
- Defeat is now handled at all. Before this, a wiped party left the surviving
  goblins taking turns against corpses with no way to end the run.

Bugs found and fixed while building on Phase 0:

- `lockpick_skill` and `interact_cost` were Combatant exports with no field in
  `CombatantStats`, so they silently reverted to defaults on the first capture —
  the authored archer lost their lockpicking. Both are now in the stat block.
- A created character arrived in the dungeon named "Hero": the stat block
  carries a name of its own and `_apply_stats` copies it over during `_ready`,
  after hydration had set the right one. `CharacterData.apply_to` now keeps the
  block's name in step.
- A spawned archer had no quiver. `show_quiver` is a property of the authored
  model node, not of an item, so class bodies now carry model properties
  (`CharacterData.CLASS_BODIES`) and the spawner sets them before the model
  enters the tree.

The round-trip test now covers all of this and runs 615 checks. The check that
caught the lost stats compares every script variable on an authored hero against
the rebuilt one, and it deliberately does NOT take its field list from
CombatantStats — doing that would make it blind to exactly this class of bug.

Balance note, not a bug: the one dungeon holds five enemies and was built for
three heroes, so a single created character will struggle. That is what the
"take the test party" door and Phase 5's hirelings are for; Phase 4's
difficulty tiers are the real answer.

## Phase 2 as built (2026-09-17)

The game now remembers. Quit from town, relaunch, continue.

- `scripts/save_game.gd` — the only place that touches the disk.
  `user://savegame.json`, written atomically (to a `.part` file, then moved into
  place) so a crash mid-write cannot replace a good save with half of one.
  JSON rather than a packed resource on purpose: a save is a file a player can
  edit or swap, and `binary_to_variant` on a .res will instantiate whatever
  script the file names.
- The envelope carries its own `save_version`, separate from
  `GameState.SCHEMA_VERSION` and `CharacterData.SCHEMA_VERSION`, so a change to
  how a character is stored does not need the file format bumped and vice versa.
  `_migrate` is written as `if from_version < N` steps and is empty today —
  there so the first format change is not the day every existing save has to be
  thrown away. A save from a NEWER version is refused outright rather than
  half-read.
- A `summary` block is written beside the state (party names, classes, levels,
  gold) so the title screen can say what is in a save without loading it and
  trampling whatever is in memory.
- `scenes/title_screen.tscn` — Continue / New Character / Quit, reached only
  when a save exists. New Character confirms first and says what is lost; the
  old save is left on disk until the new character actually reaches town, so
  backing out of creation costs nothing.
- Autosave is on ARRIVAL IN TOWN, and on anything done there (resting). Town is
  the checkpoint because it is the only quiet moment: no turn half-taken, no
  arrow in flight, no action owed. A failed save says so on screen and stays
  there — it is the one error that costs the player something no amount of
  skill gets back.
- The quest's Save button now says "the party is saved when they reach town"
  rather than "not implemented": mid-quest saving is a decision, not a gap.
  Saving inside a fight would mean serialising the tick clock and every owed
  action, and the reward for it is letting somebody re-roll a bad die.
- Town gained a Main Menu button, which is the way to a different character.

Verified: the round-trip test is up to 643 checks and covers the save path —
written, peeked at without loading, loaded back with every stat, wound, item
and trained skill intact, plus the three failure cases (no file, a file from a
newer version, a file that is not a save at all), each of which must leave the
party in memory untouched. The test writes to a save path of its own; a dev tool
has no business touching the player's slot.

A real save was written by hand to check the boot path end to end — the game
opens on the title screen, lists the saved character and reports its age — then
deleted, so the next launch is a clean first run.

## Phase 3 as built (2026-09-17)

Gold and xp now buy something, which makes the loop a progression rather than a
circuit.

- `scripts/progression.gd` — all the rules in one file, because these numbers
  only mean anything against each other. Training spends BOTH xp and gold, so
  neither is ever the only thing worth having: a rich character with no
  experience has nothing to train, an experienced one with no money has to go
  and earn some. Cost per point = step * the value being bought, so the tenth
  point of a skill costs twice the fifth. Skills cap at 15 and attributes at 10
  — rolls are skill + 1d5, so a gap of ten makes the die a formality.
- `scenes/training.tscn` — 9 skills and 5 attributes, each with its current
  value, what the next point costs, and a line on what it actually does. A
  party picker when there is more than one member. Disabled buttons say why.
- `scenes/shop.tscn` — a fixed stock of 13 items already in resources/items.
  Buying puts gear in the pack and puts it ON only when the slot it wants is
  empty; buying a second sword is a decision about which to hold, and the
  dungeon inventory is where that is made. Selling unequips on the way out,
  which is why it goes through CharacterData rather than poking the array.
- `ItemResource.value` + `gold_value()` / `sell_value()` — prices DERIVED from
  what an item does, with `value` as a per-item override. No .tres needed
  touching, and rebalancing what armour is worth reaches every piece of armour
  at once. Shops sell at full and buy at 40%, which is what stops a dungeon
  full of goblin daggers from being an income.
- `CharacterData` gained the bag operations town needs — `bag_add`,
  `bag_remove_at`, `equip_from_bag`, `is_equipped`, `slot_is_free` — because
  there is no live InventoryComponent in town and the `equipped`-points-into-
  `bag` invariant has to hold anyway. `CharacterClasses` now builds its
  starting loadout through the same functions instead of its own copy of the
  rules, and `InventoryComponent.preferred_slot` is the one place that decides
  where a piece of gear goes.
- `xp` is now a POOL that training spends, so `xp_total` was added to carry the
  character's history and the level is derived from that. A save written before
  this reads its old `xp` as the lifetime total, which is what it was.
- Resting costs 2 gold per missing hit point, and mends hp and mana but NOT
  ammunition. Arrows are bought — that is what makes the bundle on the shelf
  worth anything and an archer's upkeep different from a soldier's.

How it adds up: one clear of the five-enemy dungeon pays 100 xp and 75 gold. A
skill point is 60 xp / 30 gold, an attribute 200-240 xp / 100-120 gold, heavy
armour 66 gold, and putting a badly mauled hero back together about 32. Gold is
the slightly tighter constraint, which is what gives it a job.

Verified: 706 checks. The new ones cover the level curve, training refusing and
explaining itself, the cap, price ordering and the buy/sell spread, a full pack,
selling something that is being worn, and — the part that matters — a trained
skill and a bought weapon arriving in the dungeon on the right body.

The test now also MOUNTS each town screen with a real party and presses its
buttons, which is the only way to cover the glue between a button and a rule
without a mouse. It logs every press into the report, because a button-walking
test that matches the wrong button passes just as happily as one that does not.
Those screens save as they go, so the test backs up the player's save file and
puts it back, and asserts at the end that it left it as it found it.

## The town became a place (2026-09-17)

Phase 1 deliberately built the town as flat UI, with a note that a proper town would
"replace this file and nothing else". That is what happened: `scenes/town.tscn` is
now a 3D clearing in a birch wood, and the buttons, flow and save behaviour came
across untouched.

- `scripts/town_layout.gd` — every position, as data, because the roster is meant
  to vary. Written against measured model sizes (`tools/measure_prefabs.gd`).
- `scripts/town.gd` — builds the clearing, the buildings and the buttons. The
  buttons float over the buildings they belong to, projected through a fixed camera.
- `scripts/town_ambience.gd` — the mill turning, washing on the line, chimney smoke,
  a flickering campfire, falling leaves, butterflies.
- `assets/shaders/wind_sway.gdshader` — the pack's Unity wind shader, rewritten for
  Godot: height-weighted sway with a gust and a flutter, phase-offset by world
  position so the clearing moves like air is passing through it.
- `scripts/synty_model.gd` — instancing raw Synty FBX: prunes the baked LOD meshes
  (a birch arrives as four stacked trees) and paints each mesh from the pack's
  material list.

ASSETS: a dependency-resolved 6.3 MB subset of the Farm pack (47 prefabs, Godot-ready)
and 43 MB of the Meadow pack (52 FBX, TGAs converted to PNG). Paths normalised to
lowercase `res://assets/` so this does not inherit the dungeon pack's case-sensitivity
trap.

WHAT THE PACKS CANNOT DO: there is one real house across both (the meadow Stone Cabin).
The farm pack's buildings are a modern American farm — clapboard houses, red barns, a
steel water tower — which would clash with a game about goblins and warhammers, so none
of them are placed. The magician's is a 38 cm ornament mushroom scaled to cottage size;
the three shops are market stalls; the soldiers' fort is a tent. A Synty fantasy village
pack would make this a five-minute change: swap `model` on the SERVICES entries.

TOOLS ADDED, all dev-only: `measure_prefabs` (footprints, so the layout is written from
numbers), `inspect_model` (mesh names, surfaces and UV bounds — how the material mapping
was established), `compare_tree_materials` (four canopy treatments side by side, which is
what settled the foliage), `capture_town` (screenshots the town into
.summer/local/town_preview.png, the only way to see visual work here).

### Forest depth and clearance (2026-09-18)

- Nothing is scattered within a clearance radius of a placed object, read from the layout
  rather than from the scene (the wood is grown before the buildings are placed). The
  windmill asks for 13 m, because its sails sweep nearly ten.
- The wood is FIVE bands rather than one ring, each cheaper than the one in front: near
  birches at Synty's LOD0, then LOD1 and LOD2 bands behind, and a skyline band of the big
  meadow trees scaled half again.
- The skyline band is the only one that actually hides the horizon, and the reason is
  geometry: the camera stands 13.5 m up and looks down, so its eye line runs ABOVE every
  ten-metre birch on flat ground no matter how many are planted. Only a tree taller than the
  camera crosses that line. A deep wood of ordinary birches still showed sky at the frame
  edges; 44 big trees at 60-112 m closed it.
- `max_z` on a band drops its trees behind the camera, which never sees them.
- The distant bands do not cast shadows and are not swayed by the wind shader — both are
  invisible at that range. With the shadow range pulled to 48 m that took the scene from
  2.19M primitives and 491 draw calls to 1.24M and 306, for an identical picture.
- `tools/capture_town.gd` now writes .summer/local/town_stats.txt beside the screenshot
  (fps, frame time, primitives, draw calls), because a forest is easy to overbuild and "it
  looked fine in a screenshot" is not the same as "it runs".
