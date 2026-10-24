extends Node
## Dev tool: a real quest scene with a real party, screenshotted close up — the only way to see
## how characters look in the dungeon. Play tools/capture_quest.tscn.
##
## Builds a soldier, an archer and a wizard (CharacterClasses.make, so they carry their starting
## gear), takes a tier-2 dungeon-themed contract so there are bandits, and writes to .summer/local/:
##   quest_party.png    the party at the entrance
##   quest_enemy.png    the nearest enemy group
##   quest_swing.png    the soldier mid-swing, for how a held weapon sits
## then quits. Touches nothing on disk but those files.

const QuestScene := preload("res://scenes/quest_scene.tscn")
const CharacterClassesScript := preload("res://scripts/character_classes.gd")
const QuestDefScript := preload("res://scripts/quest_def.gd")

@export var quest_seed := 7171
@export var tier := 2
@export var theme := "crypt"
## Frame the first enemy whose name starts with this, if any (else the first dressing body).
@export var focus_enemy := "Ghoul"
## Also seat the boss on his throne and shoot him there (quest_throne.png), then again once
## he has climbed down (quest_throne_down.png).
@export var seat_boss := false


func _ready() -> void:
	GameState.clear()
	for c in [["soldier", "Aldric"], ["archer", "Wren"], ["wizard", "Maelis"]]:
		GameState.add_member(CharacterClassesScript.make(c[0], c[1]))
	var def = QuestDefScript.generate(quest_seed, tier)
	def.theme = theme
	GameState.accept_quest(def)
	var quest := QuestScene.instantiate()
	add_child(quest)
	for i in range(20):
		await get_tree().process_frame
	var cam := quest.get_node("Camera3D") as Camera3D
	if cam.has_method("set"):
		cam.set("follow_active", false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.summer/local"))

	var party: Array = quest._party_views
	var centre := Vector3.ZERO
	for p in party:
		centre += p.global_position
	centre /= maxf(1.0, party.size())
	await _shoot(cam, centre, "res://.summer/local/quest_party.png")
	await _shoot(cam, centre, "res://.summer/local/quest_overview.png", 16.0)
	# Low and from outside the room, so a wall stands between the lens and the party: what the
	# occlusion fader is for.
	cam.global_position = centre + Vector3(0.0, 3.5, 11.0)
	cam.look_at(centre, Vector3.UP)
	cam.set("pivot", centre)
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png("res://.summer/local/quest_low.png")

	var enemies: Array = []
	for n in get_tree().get_nodes_in_group("enemies"):
		if quest.is_ancestor_of(n) and n.get("is_player_controlled") == false:
			enemies.append(n)
	# The enemy whose template is a dressing body, if any, so the shot shows the new look.
	var pick: Node3D = null
	for e in enemies:
		if focus_enemy != "" and String(e.character_name).begins_with(focus_enemy):
			pick = e
			break
	for e in enemies:
		if pick != null:
			break
		if e.get_node_or_null("CharacterModel") != null and e.get_node("CharacterModel").has_method("wears_gear"):
			pick = e
			break
	if pick == null and not enemies.is_empty():
		pick = enemies[0]
	if pick != null:
		await _shoot(cam, pick.global_position, "res://.summer/local/quest_enemy.png")

	# A room with a long table in it, for a theme whose kit lays them (the raiders' mead hall).
	var room_node = get_tree().root.find_child("DungeonRoom", true, false)
	if room_node != null and room_node.layout != null:
		var shot := {}
		for f in room_node.layout.features:
			for kind in ["table", "barrel", "chest", "vessel", "rack", "statue", "runestone"]:
				if f["type"] == kind and not shot.has(kind):
					shot[kind] = true
					await _shoot(cam, f["at"], "res://.summer/local/quest_%s.png" % kind,
						8.0 if kind in ["table", "vessel", "statue", "runestone"] else 4.0)

	if seat_boss:
		for e in enemies:
			if e.get("enemy_type") != 2:
				continue
			var spots: Array = e._room_idle_spots("seat")
			if spots.is_empty():
				break
			e.position = Vector3(spots[0]["at"].x, e.position.y, spots[0]["at"].z)
			e._idle_arrive(spots[0]["face"], "sit", spots[0]["perch"])
			await get_tree().create_timer(1.0).timeout
			await _shoot(cam, e.global_position, "res://.summer/local/quest_throne.png", 3.6)
			# And from the side, which is where sitting too high, too low or too far forward shows.
			var out: Vector3 = (spots[0]["face"] - spots[0]["at"])
			out.y = 0.0
			var side := out.normalized().cross(Vector3.UP)
			var focus: Vector3 = e.global_position + Vector3(0, 0.3, 0)
			cam.global_position = focus + side * 3.2 + out.normalized() * 1.0 + Vector3(0, 0.6, 0)
			cam.look_at(focus, Vector3.UP)
			for i in range(4):
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("res://.summer/local/quest_throne_side.png")
			var skel := e.get_node("CharacterModel").find_child("Skeleton3D", true, false) as Skeleton3D
			var hips := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Hips")).origin
			print("[CaptureQuest] perch=%s body=%s hips=%s hip_drop=%s" % [spots[0]["perch"], e.global_position, hips, e._hip_drop])
			var f := FileAccess.open("res://.summer/local/throne_probe.txt", FileAccess.WRITE)
			f.store_string("perch=%s body=%s hips=%s hip_drop=%s face=%s at=%s" % [spots[0]["perch"], e.global_position, hips, e._hip_drop, spots[0]["face"], spots[0]["at"]])
			f.close()
			e._idle_leave_perch(false)
			e.release_pose()
			await get_tree().create_timer(1.0).timeout
			await _shoot(cam, e.global_position, "res://.summer/local/quest_throne_down.png", 3.6)
			break

	var soldier = party[0]
	soldier._play_attack_anim("attack-melee-right")
	await get_tree().create_timer(0.35).timeout
	await _shoot(cam, soldier.global_position, "res://.summer/local/quest_swing.png", 3.2)
	# The same enemy mid-attack, for its fighting clip.
	if pick != null and pick.has_method("_play_attack_anim"):
		pick._play_attack_anim("attack-melee-right")
		await get_tree().create_timer(0.5).timeout
		await _shoot(cam, pick.global_position, "res://.summer/local/quest_enemy_attack.png", 3.2)
	print("[CaptureQuest] done: %d party, %d enemies" % [party.size(), enemies.size()])
	get_tree().quit()


func _shoot(cam: Camera3D, at: Vector3, path: String, dist := 5.5) -> void:
	## From the middle of the room `at` is in, so a wall behind the subject is the backdrop and
	## not the thing in front of the lens.
	var focus := at + Vector3(0, 0.3, 0)
	var back := Vector3(0, 0, 1)
	var room = get_tree().root.find_child("DungeonRoom", true, false)
	if room != null and room.get("layout") != null:
		var L = room.layout
		var id: int = L.region_at(at.x, at.z)
		if id >= 0:
			var c: Vector3 = L.centre_of(L.regions[id]["rect"])
			var d := Vector3(c.x - at.x, 0, c.z - at.z)
			if d.length() > 1.0:
				back = d.normalized()
	cam.global_position = focus + Vector3(0.0, dist * 0.55, 0.0) + back * dist
	cam.look_at(focus, Vector3.UP)
	# Where the camera is looking is one of the things the roof lifts for (OcclusionFader), and
	# the fade takes a moment; set it, and give it that moment.
	if cam.get("pivot") is Vector3:
		cam.set("pivot", focus)
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(path)
