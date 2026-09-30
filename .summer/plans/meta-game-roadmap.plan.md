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
    status: completed
  - id: quest-board
    content: >-
      Phase 4: Quest Board UI generating 3-5 random QuestDefs each visit with
      name / difficulty / reward
    status: completed
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
    status: completed
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

## Progression redesigned: two experiences (2026-09-18)

Skills no longer rise off a shared pool. Each keeps its own.

- **SKILL XP** belongs to a skill and is earned BY that skill. Using it pays 1, a
  critical — a natural 5 or 1 on the game's d5 — pays 3. An ordinary use stops
  paying after 3 in one quest; a critical ignores that roof. So swinging a sword
  teaches swordsmanship, and standing in a cleared room shoving a wall teaches
  nothing, which is the point of having a roof at all.
- **GENERAL XP** comes from quests and kills and may be pushed into a skill ONE
  point per skill per quest. It is a trickle for nudging along something you did
  not get to use, not a pool to buy skills with.
- **Levelling** a skill spends that skill's own xp: 4 + 2 x current, so the first
  level costs 4 and the fifteenth 32.
- **Training** buys skill xp with gold (8 + 3 x current per point) and does NOT
  raise the skill. Deliberately a poor rate: a quest where a skill is used and
  crits once is worth about 200 gold of tuition.
- **Attributes** are raised by neither and are off the training screen until they
  have a currency of their own. An honest gap beats an undecided system.

Where it hooks into combat, all of it through code that was already there:
`Ability.trains_skill()` names the skill an action teaches and `Player._use()`
awards it centrally, so a new skill declares itself in one line. The attacker's
die is rolled by the DEFENDER (`_attempt_defense`), so the defender hands it back
via `note_skill_die` and the attacker reads it once the swing resolves. Parrying
awards itself where the parry die is rolled, sneaking on every step in
`roll_stealth`, lockpicking on every lock in `LootContainer._try_unlock`. The
ledger lives on the body and is handed to the character at the end of the quest,
like every other quest result; a goblin keeps one and it dies with it.

Verified: 712 checks. The roof is tested directly (40 uses of one skill in a
quest banks 3 xp), as is a crit paying over it, one skill's roof not being
another's, the one-per-quest assignment refusing a second and refunding nothing,
the allowance refreshing when a quest ends, and every pot surviving the save
format. Two checks go through REAL combat rather than calling the award: a blow
aimed at the hero earns parry, and the attacker is told what their die came up.

`QuestScene.capture_party()` was extracted while doing this. The test had its own
copy of what leaving a dungeon does to a party, and that copy silently stopped
matching the moment skills began earning experience — so there is now one
definition and the test calls it.

## Phase 4 begins: a quest is a thing you can be offered (2026-09-18)

Two of Phase 4's five pieces: quests can now be DESCRIBED and TAKEN. What they
cannot yet do is build the place they describe — that is the spawner, the loot
tables and the parameterised room builder, and until those land every accepted
job runs the one authored dungeon.

- `scripts/quest_def.gd` — a quest is a SEED and a TIER, and everything else is
  derived from those two integers: its name, its theme, its enemy and loot
  budgets, what it pays. That is what makes the rest cheap. A board stores one
  number and re-derives its offers; a save stores two; the generator, when it
  arrives, is handed the same two and has everything it needs. Verification for
  the phase is written against exactly this property — "the same seed reproduces
  the same quest" — so it is tested directly rather than inferred from a screen.
  The draws come off one generator seeded once, which makes the ORDER of those
  draws part of the contract: new rolls go at the end, the same discipline the
  item enums are kept under.
- `scripts/quest_board.gd` + `scenes/quest_board.tscn` — four jobs, hardest
  last, coloured against the party's level so a tier number means something on a
  first read. Tiers are spread AROUND the party, one below and two above: a board
  with nothing safe on it and a board with nothing dangerous on it are the same
  broken board in opposite directions.
- `GameState.board_seed` — the board itself, as one integer. Closing the screen
  and opening it again shows the same notices; the list changes when the party
  comes back from a quest (`reroll_board`, called from the settlement), which is
  also what stops a contract being cleared twice by walking straight back out of
  town. It is saved, so the jobs a player walked away from are still there when
  they come back.
- `GameState.current_quest` is now a QuestDef (or null) rather than the Phase 0
  placeholder dictionary. Null is a real state and a used one: a trip through the
  gate on the party's own account has no contract, which is what the gate is for.
- The contract pays on CLEARING and only on clearing. Kills pay for the fighting
  (unchanged), the contract pays for finishing the job, and a party that walks
  back out keeps the first and forfeits the second. The results screen says which
  it was, by name.

TIER NUMBERS: tier 1 is sized to about the five-enemy dungeon's kill income, so
taking a contract for a room you were going to clear anyway roughly doubles the
trip. Rewards carry a 15% wobble so two tier-3 jobs on one board are not visibly
the same job twice — narrow enough that it can never reorder the tiers, which is
checked across 40 seeded pairs, because a lucky Simple job out-paying an unlucky
Steady one would make the labels on the board lie.

`QuestScene.settle()` was extracted while doing this, for the third time and the
same reason: the round-trip test cannot call `finish_quest` (it ends by changing
scene, which would free the test), so the test had its own idea of what leaving a
dungeon means — and that copy had already gone stale once when skills started
earning experience. It would have gone stale again the moment a quest could be
worth a contract. There is one definition, it returns the settlement, and the
test calls it. `capture_party` stays separate because it is the half that has to
stay symmetrical with hydration.

Verified: 759 checks, up from 712. The new ones cover determinism both ways (the
same seed gives the same quest; 24 seeds give a spread), the tier ladder rising
in pay and in danger with no overlap between adjacent tiers, clamping past both
ends, a quest surviving being written down, a board being stable under re-reading
and changing under a reroll, a level-1 party always being offered level-1 work,
and the board surviving a save with the same jobs on it. Payment goes through the
REAL settlement path three times over: a contract cleared pays, one walked out of
pays nothing and says so, and an uncontracted trip through the gate settles with
no job attached. The board screen is mounted and read but not pressed — every
button on it changes scene, and a scene change would free the test — so the
taking is covered against settle() instead.

## Phase 5: the mercenary camp (2026-09-18)

Taken out of order, and on purpose: the user asked for it because being one
character is hard, which is a better reason to build something than its position
in a list. Phase 4's remaining three pieces (the spawner, loot tables, the
parameterised room builder) are untouched.

It was cheap because Phase 0 paid for it in advance. `GameState.party` has been
an array since the first day and `QuestScene` has always spawned one body per
member, so this is a screen, a price and a generator rather than a refactor.

- `scripts/hireling.gd` — a camp is ONE seed and the people at it are derived
  from it, exactly as a quest board is. A candidate stays a plain Dictionary
  until somebody pays: minting an id and building a bag of gear four times over
  on every redraw, for people who will never be hired, is work nobody asked for.
  `make_character` is the moment a candidate becomes a person.
- `CharacterClasses.growth_for` — what a class gets better at, best first. A
  hireling's levels are spent down that list rather than at random, so a level 4
  archer is reliably an ARCHER. Their xp pools are left EMPTY: they bring what
  they have learned, not a pot for their new employer to cash in.
- `scripts/hire_camp.gd` + `scenes/hire_camp.tscn` — the company and the fire on
  one screen, because "can I afford this, and who would I be replacing" is one
  question. Parting company asks twice, in place, on the button itself.
- `Progression.hire_cost` — a fee plus a price per skill level they already have.
  Priced off what they BRING, not the level on their badge, so a class whose
  experience does not currently buy many skill levels is cheap rather than
  quietly a bad deal. A raw recruit is 40 gold — half a cleared tier-1 dungeon,
  so a lone hero can afford company after one trip, which is the whole point.
  ONE-OFF, no upkeep: a wage per quest is a second economy to balance, and what
  actually costs money is keeping them alive and armed.
- `GameState.PARTY_MAX = 4`, `add_member` now refuses and reports rather than
  silently overfilling, `remove_member` refuses to dismiss the main character.
  `GameState.hire()` is the ONE place hiring happens, so paying and joining
  cannot come apart.
- Dismissal takes their gear with them. That is the honest reading of paying
  somebody off, and it stops the camp being a way to launder a cheap recruit into
  a free set of leather armour. If it ever needs softening it softens in
  `remove_member`.
- The town gained a second tent and a lit fire at (-10, -12.5); its sign shows
  `Mercenary Camp — 1/4`, because party size is the number the camp exists to
  change. `TownAmbience` kept its campfire light in a single variable, so adding
  a second fire would have left the first frozen — it is an array now, each fire
  phase-offset so two fires in one clearing do not pulse in unison.

REAL BUG FOUND AND FIXED: `QuestScene._spare_mark` — the square a party member
gets when the authored scenario has no hand-placed body for them — stepped +x
from the last mark and hoped. That was harmless while it was never called, and
the moment a fourth body could be hired it became a way to stand somebody inside
a wall. It now SEARCHES outward in rings for a square with floor under it and
nobody on it, asking `DungeonRoom.is_floor_at` — the same authority
`Combatant._is_in_arena` uses — so it keeps working when Phase 4's generator
starts building the room.

Verified: 816 checks, up from 759. The camp gets the same treatment the board
does (same seed, same people; stable under re-reading; re-rolled on return from a
quest; survives a save), plus what is particular to hiring: price rising with
experience, a purse that cannot cover it buying NOTHING rather than half, the cap
turning a fifth away without charging for them, the hero being undismissable, and
a hireling being better at their trade than a fresh recruit without any skill
going over the cap even when handed 400 levels. The camp screen is walked by
pressing its real buttons, including that parting company does nothing until it
is confirmed. It ends underground: a party of three, every one of them with a
body, on real floor, no two on a square, all dealt into the turn order, and a
hireling's wounds written back like anybody else's.

STILL MISSING: hirelings cannot be equipped from town — the shop's party picker
reaches them, but there is no screen that moves an item from one member's pack to
another's. They fight with what their class gave them plus whatever they pick up.

## The party becomes visible, and gear moves between packs (2026-09-19)

Three asks, one theme: the company existed in data and on a battlefield, but in
town it was a list of lines in the corner. Now it stands in the clearing and can
be inspected and re-packed.

- `TownLayout.PARTY_STAND` + `Town._build_party_models` — the actual party, one
  body per member, downstage in the meadow facing the camera. Built from each
  member's own class body and model props, so the archer standing here has the
  quiver the archer downstairs has. MODELS ONLY: no Combatant, no inventory, no
  collision. A town body is a picture of a character, and everything a Combatant
  brings would be machinery in aid of a picture. Their name floats over them as a
  billboarded Label3D — staggered in height, because four names on one line at
  this spacing read as one long smear.
- Their GEAR is not shown on those bodies. The sockets that put a sword in a hand
  are built by Combatant off the model's skeleton, and lifting that out for a
  silhouette is a job for the day somebody asks to see their armour from outside.
- `scripts/party_sheet.gd` + `scenes/party_sheet.tscn` — Gear, Sheet and Spells
  for one member at a time, with a member picker. The town's toolbar (bottom
  left, opposite the system buttons) opens it on a chosen page; which page
  travels on the screen's own `static var opening_tab`, because that is a
  property of this trip to that screen and not of the game.

WHY NOT THE QUEST SCREEN'S PANELS: `inventory_ui.gd`, `character_sheet_ui.gd` and
`spell_sheet_ui.gd` all read `CombatManager.current_combatant` and work on a live
Combatant with an Inventory child, and the inventory one routes its clicks
through `Player.equip_weapon`, which charges time and ENDS THE TURN. None of that
exists in town and none of it should — there is no turn to end and no body to
fold an armour bonus into. So the party sheet reads CharacterData and edits it
through the operations CharacterData already owns, the same ones the shop buys
and sells through. Derived numbers (hit points from stamina, mana from willpower)
are computed from Combatant's constants exactly as `CharacterClasses.summary_lines`
already does for the creation screen.

Rearranging gear in town is FREE, where in the dungeon it costs a turn. That
difference is the point of doing it here: sorting out who carries the spare
shield is planning, and planning is what a town is for.

GEAR TRANSFER: one recipient is chosen up front and then one Give button per
item, rather than a button per item per member — with four in the company that
would be three buttons on every line of a full pack. An item leaves the giver
FIRST (`bag_remove_at`, which also takes it off, the honest reading of handing
somebody the shield off your arm) and goes straight back to them untouched if the
receiver has no room. An item must never be able to evaporate between two packs.

`Player.build_abilities()` was made static so the spell page can ask what a
character can cast without a body to hang it on. The page lists whatever answers
`is_spell()`, so a second spell appears there the day it is written rather than
the day somebody remembers this screen exists.

A REAL UI PROBLEM the test found: the member picker and the recipient row were
both rows of bare names, so a press meant for one landed on the other. It was the
test that got caught, but a player would have been caught the same way — the
recipient buttons now read "Hand to Wren", and the test asserts which one moved.

Verified: 847 checks, up from 816. The new ones walk the real screen: taking gear
off and putting it back on, switching member, the Give button not existing until
a recipient is chosen, a transfer leaving exactly one pack and arriving in
exactly one other, gear handed over straight off the body coming off on the way,
and a full pack refusing the gift with the giver keeping it. Both other pages are
opened through the toolbar's own mechanism, and the spell page is checked to list
Firebolt for a wizard and say plainly that a soldier is no caster.

`tools/capture_town.gd` now populates a FULL company of four, one of each class,
because a town screenshot with one hero in it cannot show whether the fourth mark
stands somebody in a fence.

STILL MISSING: nothing moves gear between a member and the GROUND from town, and
there is no "sell from any pack" — the shop still sells out of whichever member
its own picker is on.

## The town screens get a face: INTERFACE - Fantasy Menus (2026-09-19)

Pass one of two. The town is now gold-on-navy Synty rather than text on black, the
market lists what it sells with pictures, and the party sheet's gear reads the
way the dungeon's backpack does. Pass two — re-skinning the in-dungeon HUD to
match — has not been done yet.

- `assets/UI/FantasyMenus/` — 30 sprites, a curated cut of the pack's 234. Frames,
  a damask, a vignette, dividers, flourishes, a scrollbar.
- `scripts/ui_kit.gd` REPLACES `screen_panel.gd`, and deliberately keeps its shape:
  mount / title / heading / label / button / row / separator / spacer / toast take
  the same arguments and mean the same things. Porting eight screens was changing
  one preload line each. What changed is what those calls DRAW. screen_panel.gd is
  deleted; nothing referenced it by its class name.
- `UiKit.item_row` is the piece the ask was really about: icon, name, what it
  does, what it costs, and the buttons that act on it. The icon is an `ItemSlot`
  — the very widget the dungeon's backpack grid is made of — so a potion on the
  shelf is the same picture as the potion in the bag it ends up in.
- The shop's shelf and the player's pack are both item rows now, with Buy and
  Sell beside them. So is the party sheet's worn-and-carried gear, with Take off
  / Put on / Give to.
- The town's own floating buttons — the shop signs over the stalls, the party
  toolbar, the system column — go through `UiKit.style_button`, so the clearing
  does not look like a different game from the screens it opens.

THE PACK SHIPS ITS ART IN TWO HALVES: a white silhouette to tint and a gold frame
to lay over it. Godot's Button takes ONE StyleBox per state, so the two are
composited in `UiKit._plate` — `blend_rect_mask` paints the tint through the
silhouette's alpha, `blend_rect` drops the gold on top — and cached. The four
button states are then one texture under four `modulate_color` values, because a
pressed button in this pack is the same button a shade darker.

`tools/capture_screens.gd` was written first, before any of it. The flat screens
are the part of the game that is ENTIRELY look, and nothing about a wrong
nine-patch margin raises an error — the round-trip test can only say that a button
exists and does what it says. It shoots all ten screens with a real party and
prints each panel's size next to the window's, warning when one stops fitting.

THREE LAYOUT BUGS IT CAUGHT, none of which would have raised an error:
1. A NinePatchRect is not a container — it never grows to fit its children. The
   first build put a 400-pixel frame around 900 pixels of market and spilled the
   shelf out the bottom. Both the panel and the row plates are PanelContainers
   with a StyleBoxTexture now, which take the same nine-patch art, size to their
   child, and take their padding off the stylebox.
2. A nine-patch draws its corners at the TEXTURE's pixel size, so a 1024-pixel
   frame with 250-pixel corners puts 500 pixels of ornament into a panel 800
   wide. Each composited plate is now resized to the job: 400 for the panel, 96
   for a button, whose smallest instance is 36 pixels tall.
3. A TextureRect reports its texture as its minimum size unless told otherwise,
   and the dividers in this pack are 1024 wide — so panels came out eighteen
   hundred pixels across, sized to the rule under a heading rather than to the
   words beside it. Every TextureRect the kit builds sets EXPAND_IGNORE_SIZE.

BUTTON LABELS AND BUTTON NAMES: a shelf where every row's button repeats its own
item's name is noise, so the label is "Buy". But six buttons all reading "Buy"
are unpressable by name, and the round-trip test walks these screens by pressing
buttons. So the label stays short and the NODE is named for both — "Buy Health
Potion" — and `_find_button` matches either. The alternative was a test that
presses the wrong row and passes.

Verified: 847 checks, unchanged — this pass moved no rules, only the furniture,
and the point of running it was to prove that. The screens themselves are checked
by eye, from .summer/local/screens/.

DECORATION, SECOND PASS: the first cut used the pack's ornate bars (Frame_Bar_06)
as section rules and separators. Those are drawn to be seen at about four to one,
and a divider across this panel is nearer sixty to one — squashed that far, the
scrollwork came apart into a row of smears. Rules are now Line_Horizontal_01, a
soft gradient along its own length, which only gets longer when stretched; the
ornate bar moved to under the title, where a centred flourish has room to be
shown at its own proportions. Two button fixes went with it: a standalone button
no longer clips its label (the board was offering to "Take: Sanctify the Hollow
Tomb", one letter short of the truth), and the text padding is now tied to
BOX_SLICE so a long label cannot sit on top of the corner brackets.

THE MARKET BECAME TWO COLUMNS (2026-09-20): stacked, the shelf and the pack meant
scrolling past thirteen things on sale to reach your own kit — and buying and
selling are the same decision seen from two sides, so the two lists want to be
readable against each other. `UiKit.mount_wide` + `UiKit.split` put them in two
framed boxes that scroll independently, with the title, picker, purse line and
the way out spanning both.

That needed the kit to stop measuring everything against one WIDTH constant: a
column now CARRIES its width and the helpers ask it (`_width_of`). The wide panel
sizes itself off the viewport rather than a fixed number, because there is no
window size in project.godot — the game runs at Godot's default and the editor's
play window is whatever it was left at.

Three things had to give to fit a list into a third of a window: an item name
wraps now (a Label that will not wrap reports its whole text as a minimum width,
which was enough to push the two columns wider than the window); the price moved
onto the name's line instead of a column of its own; and row-action buttons got a
tighter text inset, because the padding that keeps a long label off the corner
brackets leaves a 76-pixel "Take off" reading "Take".

THE THREE STALLS SELL THREE DIFFERENT THINGS (2026-09-21): the armourer, the
weapon shop and the general store all opened the same shelf. They are still one
scene — a shop is not different enough from another shop to be its own — but
`Shop.opening_shop`, set by Town from the service's own id, decides the sign over
the door and what is on the shelf.

The split is by the item's OWN type rather than three hand-written lists:
armourer takes SHIELD/ARMOR/HELMET/LEGS, weapon shop WEAPON/THROWABLE/AMMO. The
general store's list is EMPTY, and that is the point — it means "whatever the
other two do not take". Add a kind of item nobody claims and it appears on its
shelf without the table being touched, which is the only version of "everything
else" that stays true. The test checks that property directly: every item is on
exactly one shelf, and the three shelves together are the whole stock.

The three bottles already in resources/items were put on sale at the same time.
Split by type, the general store had one item on it — a potion — and a shop with
one thing in it is a worse answer to the request than the one-shop version was.

NOT changed: any stall will still BUY anything. Restricting that too would mean
three visits to clear a mixed haul after every dungeon, which is a chore rather
than a decision. The ask was about what is for sale.

THE SHOP SHOWS THE REAL ITEMS (2026-09-21): asked whether the Fantasy Warrior HUD
pack has 3D versions of its item icons. It does not — it is an INTERFACE pack,
1883 PNGs and nothing else, no meshes in the zip or the unitypackage. The 3D
comes from POLYGON - Dungeon Pack, which the items already point at.

Nothing needed building, because `item_thumbnails.gd` has photographed each
item's own model into its cell since the inventory was written. What was wrong
was one line in `UiKit.item_row`: the ItemSlot was given its item BEFORE it was
added to the tree, and `ItemSlot._apply_thumbnail` gives up immediately on a cell
with no tree to await frames from. Every row in the market therefore kept the
flat category icon — one sword picture for every sword — which is exactly the
thing the thumbnail system exists to avoid. Added to the tree first, the shelves
show the actual Synty models.

`ITEM_CELL` went back up to 56 with it. It had been trimmed to 44 to fit the
split market, which is fine for a flat icon and not fine for a photograph: at 44
a rendered sword is a grey smudge.

A NOTE ON THE CAPTURE TOOL: its SETTLE_FRAMES was 4, which is enough to lay a
screen out and nowhere near enough to photograph its items — the renders go
through one shared viewport, one item per frame. At 4 frames every screenshot
taken during the UI work showed fallback icons, which is why this went unnoticed
for so long. It is 90 now, and the shots show what the player sees.

THE FLOATING PARTY NAMES STOPPED COLLIDING (2026-09-21): they were Label3D in the
world, with staggered heights in TownLayout meant to keep them apart. That was a
guess and it only held for short names — a world-space label cannot be kept off
the one beside it, because the heroes stand under three metres apart, the names
are as long as a hireling happens to be called, and a fixed-size 3D label keeps
its pixel size while the gap between two heroes shrinks with the window.

They are screen-space Labels now, projected through the same camera the shop
signs use, and the collision is MEASURED rather than guessed. Each name tries a
short list of rows and takes the first that hits nothing. The shop signs are
placed first and passed in as occupied space, so a name dodges a sign as well as
another name — the signs keep their places because a sign that wandered off its
roof would stop naming anything, while a name a few pixels up still points at the
person standing there.

The row order is up, then DOWN, then further out alternately. Lifting only
upwards was the first attempt and it walks a name into the row of shop signs
above the party: it ran out of tries still overlapping "General Store" and left
it there. Below a hero is open grass.

`capture_town.gd` now populates the party with hireling-length names — "Ilse the
Patient", "Tobin Two-Coin" — rather than the short ones a screenshot would
prefer. The long names are the case this has to survive, so they are the case the
picture shows.

KNOWN, NOT FIXED: the BUILDING signs still overlap each other — Armorer / Weapon
Shop / General Store sit shoulder to shoulder, and Mercenary Camp crowds Healer's
House. The same measured placement would sort them, but a shop sign cannot simply
move: it has to stay on its own roof to mean anything, so that is a job for the
positions in TownLayout rather than for a runtime nudge.

PASS TWO, DONE (2026-09-21): the dungeon HUD wears the same clothes as the town.
Character sheet, spell book, inventory, action toolbar, party portraits and the
HUD slots all come off UiKit now; the only Fantasy Warrior art left in the game is
the inventory ICON set (which is drawn art with no equivalent in the newer pack)
and the three stance greebles in stance.gd.

`tools/capture_hud.gd` was written first, as capture_screens.gd was for the town.
It loads the quest scene, hands the turn to a hero — the panels draw whoever is
active, and combat often starts on a goblin, who has no character sheet worth
drawing — opens each panel in turn and shoots it.

WHAT IT CAUGHT, all of it invisible to the round-trip test:
- The town's big ornate frame is WRONG at HUD size. Its corner scrollwork is a
  quarter of a 300-pixel sheet and swallowed the section headings. HUD panels use
  the bracket frame instead (UiKit.hud_plate), which is the same family — it is
  what a market row is drawn in — with corners small enough to put text near.
- The sheets' padding was 16, which was fine against the old backplate because
  that plate had no edge to speak of. Against a real frame the whole left column
  sat on the gold line. It is 26.
- The inventory panel had NO plate at all: it was the scene's default grey Panel
  showing through. Adding one covered its title, which is a sibling authored in
  the .tscn — so the plate goes on the panel and is pushed to the back.
- Enemy portraits came out as four red BLOCKS across the top of the screen. The
  first attempt paired a heavier frame with a hard red; the frames are matched in
  weight now and the red is softened. They are still a different SHAPE from an
  ally's, which was the original author's point and does not depend on colour
  vision.

TWO THINGS THE PACK COULD NOT DO. There is no steel frame in Fantasy Menus — it
is gold throughout — so a hotbar cell and the SELECTED hotbar cell are now the
same sprite at two temperatures, via a per-frame tint multiplied into the state
tint. And the system cluster is square rather than round: the pack ships a circle
frame, but the editor will not import new files into this project (see below), so
the cluster is told apart by its corners instead.

THE CORNER ORNAMENT HAD TO GO (2026-09-22): every framed box in this pack carries
something at its corners — brackets, scrollwork, spikes — which is fine on a
button or a market row, where the frame is most of what you are looking at. In
the dungeon it lands on the content: the panel corners jutted into the first line
of every section, the portrait frames sat on the face inside them, and the Town
and Quit buttons had curls hanging off them.

So the HUD frames are DRAWN now, in StyleBoxFlat, not taken from the pack: the
panels are navy with a plain double gold line, a portrait is a single line, a
hotbar cell is a single line. The pack ships a plain double-line rectangle for
exactly this and the project cannot import it (see below), so it is reproduced in
six lines of code. ItemSlot reached the same conclusion about its own cells long
before this, and for the same reason — art too heavy for the job is worse than no
art, and a line is a line.

Two things came back with it. The system cluster is ROUND again (a corner radius
of half the cell is a circle), which it had been under the old pack and stopped
being when this was sprites. And the ally/enemy portraits are told apart by SHAPE
as well as colour — rounded corners against square ones — which was the original
author's accessibility point and which the sprite swap had been about to lose.

THE MISTAKE WORTH RECORDING: renaming UiKit._hud_box to frame_style left one call
site behind. A broken UiKit stops the GAME booting, with no output at all — not a
crash, not an error in the console, just silence — so every scene appeared to hang
and reverting the two widgets I had just edited changed nothing. summer_get_script_errors
on ui_kit.gd had been run BEFORE the rename and said zero. The lesson is narrow
and worth keeping: re-check the file you renamed a function in, after the rename,
and when everything hangs at once suspect the thing everything depends on rather
than the thing you touched last.

THE IMPORT PROBLEM, which shaped all of this: Godot here does not rescan for files
added outside the editor, whatever is done to provoke it. Every texture in the
re-skin therefore had to come from the thirty sprites that happened to be imported
on the first scan. If that ever unsticks, the frames worth revisiting are a circle
for the system cluster and a second box shape for the hotbar.
