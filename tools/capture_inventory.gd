extends Node
## Dev tool: the inventory panel open on a real party member in a real quest — the created
## archer by default, so the Back socket has a quiver in it. Writes
## .summer/local/inventory.png and quits.

const QuestScene := preload("res://scenes/quest_scene.tscn")
const CharacterClassesScript := preload("res://scripts/character_classes.gd")
const QuestDefScript := preload("res://scripts/quest_def.gd")
const InventoryUIScript := preload("res://scripts/inventory_ui.gd")

@export var member := "Wren"


func _ready() -> void:
	GameState.clear()
	for c in [["soldier", "Aldric"], ["archer", "Wren"], ["wizard", "Maelis"]]:
		GameState.add_member(CharacterClassesScript.make(c[0], c[1]))
	GameState.accept_quest(QuestDefScript.generate(7171, 2))
	var quest := QuestScene.instantiate()
	add_child(quest)
	for i in range(20):
		await get_tree().process_frame
	var who: Node = null
	for p in quest._party_views:
		if String(p.character_name) == member:
			who = p
	var cm: Node = quest.get_node("CombatManager")
	cm.current_combatant = who
	for n in quest.find_children("*", "", true, false):
		if n.get_script() == InventoryUIScript:
			n.visible = true
	for i in range(10):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://.summer/local/inventory.png")
	get_tree().quit()
