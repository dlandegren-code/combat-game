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
    status: pending
  - id: town-screen
    content: >-
      Phase 1: town screen as pure UI (background + Shop / Training / Quest
      Board / Adventure buttons) - no walkable 3D town yet
    status: pending
  - id: character-creation
    content: >-
      Phase 1: character creation screen (name + class from existing
      soldier/wizard/archer models + starting stats) feeding a fresh
      CharacterData into GameState
    status: pending
  - id: save-load
    content: >-
      Phase 2: save/load to user:// as JSON with a schema version field;
      autosave on every return to town
    status: pending
  - id: xp-training
    content: >-
      Phase 3: XP -> skill/stat progression rules; Training screen in town
      spends gold to improve skills
    status: pending
  - id: shop
    content: >-
      Phase 3: shop buy/sell using existing ItemResource items; add a gold
      value field to ItemResource
    status: pending
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
