extends Node3D
## Dev tool: how fast the walk clip actually walks, per body, in world units per second — the
## ground speed its feet imply — against the speed the body is moved at. Plays "walk" in place
## and tracks how far a foot sweeps back along the body's facing while it is down. Writes
## .summer/local/walk_probe.txt and quits.

const QuestScene := preload("res://scenes/quest_scene.tscn")
const RosterScript := preload("res://scripts/enemy_roster.gd")
const HERO := preload("res://scenes/characters/hero.tscn")
const SIDEKICK := preload("res://scenes/characters/sidekick_model.tscn")

@export var template_ids: Array = ["bandit", "goblin", "skeleton_warrior", "viking_raider", "ghoul", "rock_golem"]


func _ready() -> void:
	var out: Array = []
	var bodies: Array = []
	var hero := HERO.instantiate()
	var model := SIDEKICK.instantiate()
	model.name = "CharacterModel"
	model.position = Vector3(0, -1, 0)
	hero.add_child(model)
	add_child(hero)
	bodies.append(["hero", hero])
	var dresser := QuestScene.instantiate()
	for id in template_ids:
		var t = RosterScript.find(String(id))
		if t == null:
			continue
		var e: Node = dresser._dress(t)
		add_child(e)
		bodies.append([id, e])
	dresser.free()
	for b in bodies:
		var n: Node3D = b[1]
		n.set_process(false)
		n.set_physics_process(false)
		n.position = Vector3(bodies.find(b) * 6.0, 0, 0)
	await get_tree().process_frame
	for clip in ["walk", "run"]:
		await _measure(bodies, clip, out)
	# And what the game itself makes of them (Combatant's gait code).
	for b in bodies:
		var n: Node3D = b[1]
		out.append("%s game: leg=%.2f walk=%.2f run=%.2f gait=%s travel=%.2f (move_speed %.1f)" % [
			b[0], n._leg_length(), n._gait_speed("walk"), n._gait_speed("run"), n._gait_clip(),
			n._travel_speed(), float(n.get("move_speed"))])
	var f := FileAccess.open("res://.summer/local/walk_probe.txt", FileAccess.WRITE)
	f.store_string("\n".join(out))
	f.close()
	get_tree().quit()


func _measure(bodies: Array, clip: String, out: Array) -> void:
	for b in bodies:
		var n: Node3D = b[1]
		var ap := n.get_node("CharacterModel").find_child("AnimationPlayer", true, false) as AnimationPlayer
		ap.play(clip)
		ap.speed_scale = 1.0
	for i in range(3):
		await get_tree().process_frame
	# Sample both feet for one clip length.
	var samples := {}
	var t := 0.0
	var length := 0.0
	for b in bodies:
		var ap := (b[1] as Node3D).get_node("CharacterModel").find_child("AnimationPlayer", true, false) as AnimationPlayer
		length = maxf(length, ap.get_animation(ap.current_animation).length)
		samples[b[0]] = []
	while t < length:
		for b in bodies:
			var n: Node3D = b[1]
			var model_node := n.get_node("CharacterModel") as Node3D
			var sk := model_node.find_child("Skeleton3D", true, false) as Skeleton3D
			var fwd: Vector3 = model_node.global_transform.basis.z.normalized()
			var row := []
			for foot in ["LeftFoot", "RightFoot"]:
				var i := sk.find_bone(foot)
				var p: Vector3 = sk.global_transform * sk.get_bone_global_pose(i).origin
				row.append([(p - n.global_position).dot(fwd), p.y - n.global_position.y])
			samples[b[0]].append(row)
		await get_tree().process_frame
		t += get_process_delta_time()
	for b in bodies:
		var n: Node3D = b[1]
		var ap := n.get_node("CharacterModel").find_child("AnimationPlayer", true, false) as AnimationPlayer
		var clip_len: float = ap.get_animation(ap.current_animation).length
		var reach := 0.0
		for k in [0, 1]:
			var lo := INF
			var hi := -INF
			for row in samples[b[0]]:
				lo = minf(lo, row[k][0])
				hi = maxf(hi, row[k][0])
			reach = maxf(reach, hi - lo)
		# A foot sweeps the full stride back during its stance, about half the cycle; two
		# strides per cycle, so ground speed is about 2 * stride / cycle length.
		var speed := 2.0 * reach / clip_len
		var sk := n.get_node("CharacterModel").find_child("Skeleton3D", true, false) as Skeleton3D
		var hips_i := sk.find_bone("Hips")
		var foot_i := sk.find_bone("LeftFoot")
		var leg: float = (sk.global_transform * sk.get_bone_global_rest(hips_i).origin).y \
			- (sk.global_transform * sk.get_bone_global_rest(foot_i).origin).y
		out.append("%s clip=%s len=%.2f stride=%.2f speed=%.2f move_speed=%.1f ratio=%.2f leg=%.2f speed_per_leg=%.2f" % [
			b[0], clip, clip_len, reach, speed, float(n.get("move_speed")),
			float(n.get("move_speed")) / maxf(speed, 0.01), leg, speed / maxf(leg, 0.01)])
