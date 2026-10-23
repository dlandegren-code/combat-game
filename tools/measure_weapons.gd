extends Node3D
## Dev tool: the merged mesh bounds of held-item models, in each one's own space (what sits on
## the prop bone), to size a pack's weapons against the ones already tuned. Writes
## .summer/local/weapon_sizes.txt and quits.

const MODELS := [
	"res://assets/PolygonDungeon/Models/SM_Wep_Straightsword_01.res",
	"res://assets/PolygonDungeon/Models/SM_Wep_Goblin_Shiv_Stone_01.res",
	"res://assets/PolygonDungeon/Models/SM_Wep_Shield_Plank_01.res",
	"res://assets/vikings/weapons/SM_Wep_Sword_01.fbx",
	"res://assets/vikings/weapons/SM_Wep_Sword_02.fbx",
	"res://assets/vikings/weapons/SM_Wep_Sword_03.fbx",
	"res://assets/vikings/weapons/SM_Wep_Sword_04.fbx",
	"res://assets/vikings/weapons/SM_Wep_Sword_Short_01.fbx",
	"res://assets/vikings/weapons/SM_Wep_Axe_01.fbx",
	"res://assets/vikings/weapons/SM_Wep_Axe_02.fbx",
	"res://assets/vikings/weapons/SM_Wep_Axe_03.fbx",
	"res://assets/vikings/weapons/SM_Wep_Axe_04.fbx",
	"res://assets/vikings/weapons/SM_Wep_Knife_01.fbx",
	"res://assets/vikings/weapons/SM_Wep_Spear_01.fbx",
	"res://assets/vikings/weapons/SM_Wep_Hammer_01.fbx",
	"res://assets/vikings/weapons/SM_Wep_Shield_01.fbx",
	"res://assets/vikings/weapons/SM_Wep_Shield_Set_03.fbx",
	"res://assets/vikings/weapons/SM_Wep_Shield_Set_Optimised_03.fbx",
	"res://assets/vikings/weapons/SM_Wep_Bow_Rigged_01.fbx",
	"res://assets/weapons/bow.fbx",
	"res://assets/vikings/attachments/SM_Chr_Attach_Helmet_01.fbx",
	"res://assets/vikings/attachments/SM_Chr_Attach_Beard_01.fbx",
	"res://assets/vikings/attachments/SM_Chr_Attach_Crown_02.fbx",
]


func _ready() -> void:
	var out: Array = []
	for path in MODELS:
		var res: Resource = load(path)
		var node: Node3D
		if res is PackedScene:
			node = (res as PackedScene).instantiate()
		elif res is Mesh:
			node = MeshInstance3D.new()
			(node as MeshInstance3D).mesh = res
		else:
			out.append("%s: unloadable" % path.get_file())
			continue
		add_child(node)
		var box := AABB()
		var first := true
		var info: Array = []
		for mi in ([node] if node is MeshInstance3D else []) + node.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var b: AABB = node.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
			box = b if first else box.merge(b)
			first = false
			var mat: Material = m.get_active_material(0)
			info.append("%s skin=%s mat=%s tex=%s" % [m.name, m.skin != null, mat.resource_name if mat else "-",
				(mat as BaseMaterial3D).albedo_texture != null if mat is BaseMaterial3D else "?"])
		var players := node.find_children("*", "AnimationPlayer", true, false)
		out.append("%s pos=%s size=%s players=%d %s" % [path.get_file(), box.position.snapped(Vector3.ONE * 0.001), box.size.snapped(Vector3.ONE * 0.001), players.size(), info])
		node.queue_free()
	var f := FileAccess.open("res://.summer/local/weapon_sizes.txt", FileAccess.WRITE)
	f.store_string("\n".join(out))
	f.close()
	get_tree().quit()
