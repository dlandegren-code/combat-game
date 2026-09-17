extends Node
## The main scene, and the thinnest thing in the game: it decides which screen the player
## actually starts on and immediately hands over.
##
## Three cases, in order of what the player most likely wants:
##
##   a party already in memory   -> town. Only happens on a scene reload during development;
##                                  the game never starts this way.
##   a save file on disk         -> the title screen, which offers to continue it
##   neither                     -> character creation, because there is nothing to continue
##
## It does NOT load the save itself. Loading replaces the party in memory, and that is a
## decision the player makes on the title screen rather than something that happens to them
## on the way past.

const SaveGameScript := preload("res://scripts/save_game.gd")

const TOWN_SCENE := "res://scenes/town.tscn"
const TITLE_SCENE := "res://scenes/title_screen.tscn"
const CREATION_SCENE := "res://scenes/character_creation.tscn"


func _ready() -> void:
	# Deferred: change_scene_to_file frees the current scene, and the current scene is this
	# node, mid-_ready. Godot handles the request by waiting for idle time anyway — asking for
	# it explicitly is what makes that safe rather than lucky.
	call_deferred("_route")


func _route() -> void:
	get_tree().change_scene_to_file(_next_screen())


func _next_screen() -> String:
	if GameState.has_party():
		return TOWN_SCENE
	if SaveGameScript.has_save():
		return TITLE_SCENE
	return CREATION_SCENE
