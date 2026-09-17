extends RefCounted
class_name SaveGame
## Reading and writing the save file. The only place in the game that touches the disk.
##
## What a save CONTAINS is GameState's business (GameState.to_dict) and a character's own
## (CharacterData.to_dict). This file owns the rest: where it lives, what happens when it is
## half-written, and what to do about one that came from a different version of the game.
##
## JSON rather than a packed resource, deliberately. A save is a thing you sometimes have to
## look at when something has gone wrong, and `binary_to_variant` on a .res will happily
## instantiate whatever script a file names — which is a real hazard for a file a player can
## edit or swap. JSON can only ever give us dictionaries, numbers and strings.
##
## WHEN IT IS WRITTEN
## On reaching town, and on any action there that changes the party (see Town). Town is the
## checkpoint because it is the only place the game is quiet: no turn half-taken, no arrow in
## flight, no action owed. Saving inside a quest would mean serialising all of that, and the
## reward for it is letting somebody re-roll a bad die — so it is not done, and the quest's
## Save button says so.

const CharacterDataScript := preload("res://scripts/character_data.gd")

const PATH := "user://savegame.json"

## The FILE format: the envelope, not the contents. Bumped when the shape of what is around
## `state` changes. The state itself carries its own versions — GameState.SCHEMA_VERSION and
## CharacterData.SCHEMA_VERSION — so a change to how a character is stored does not need this
## number touched, and a change to how saves are stored does not need theirs.
const SAVE_VERSION := 1

## Written beside the state so a title screen can say who is in the save without loading it
## and trampling the party that might already be in memory. See peek.
const SUMMARY_KEY := "summary"


static func has_save(path: String = PATH) -> bool:
	return FileAccess.file_exists(path)


static func save(path: String = PATH) -> bool:
	## Write the party, the purse and everything they are carrying. Returns false if it could
	## not be written, having changed nothing.
	var payload := {
		"save_version": SAVE_VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		SUMMARY_KEY: _summarise(),
		"state": GameState.to_dict(),
	}
	var text := JSON.stringify(payload, "  ")
	if not _write_atomically(path, text):
		push_error("SaveGame: could not write %s" % path)
		return false
	return true


static func load_into_state(path: String = PATH) -> bool:
	## Replace whatever is in GameState with the contents of the save. Returns false and
	## leaves GameState untouched if the file is missing, unreadable, malformed, or from a
	## version of the game that this one cannot read.
	var payload := read(path)
	if payload.is_empty():
		return false
	var state: Dictionary = payload.get("state", {})
	if state.is_empty():
		push_error("SaveGame: %s has no party in it" % path)
		return false
	GameState.from_dict(state)
	return true


static func read(path: String = PATH) -> Dictionary:
	## The save file as a dictionary, or {} if there is nothing usable there. Does not touch
	## GameState, so it is also how the title screen looks inside a save.
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SaveGame: could not open %s (error %d)" % [path, FileAccess.get_open_error()])
		return {}
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		# A file that exists but is not a save. Kept rather than deleted: it is the player's
		# file, it might be recoverable by hand, and silently throwing it away is the one
		# unforgivable thing a save system can do.
		push_error("SaveGame: %s is not a save file" % path)
		return {}

	var version: int = int(parsed.get("save_version", 0))
	if version > SAVE_VERSION:
		push_error("SaveGame: %s was written by a newer version of the game (%d > %d)"
			% [path, version, SAVE_VERSION])
		return {}
	return _migrate(parsed, version)


static func peek(path: String = PATH) -> Dictionary:
	## Who is in the save, for a screen that has to offer it before loading it: {party, gold,
	## saved_at}, or {} for no readable save.
	var payload := read(path)
	if payload.is_empty():
		return {}
	var summary: Dictionary = payload.get(SUMMARY_KEY, {})
	summary["saved_at"] = int(payload.get("saved_at", 0))
	return summary


static func delete(path: String = PATH) -> bool:
	## For starting over. Only ever called with the player having said so out loud.
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(path) == OK


static func describe_age(saved_at: int) -> String:
	## "just now" / "14 minutes ago" / a date, for a save-slot line.
	if saved_at <= 0:
		return "unknown"
	var seconds: int = int(Time.get_unix_time_from_system()) - saved_at
	if seconds < 60:
		return "just now"
	# floori of a float division rather than int/int: the result is the same and the intent is
	# stated, which is what the integer-division warning is asking for.
	if seconds < 3600:
		return "%d minutes ago" % floori(seconds / 60.0)
	if seconds < 86400:
		return "%d hours ago" % floori(seconds / 3600.0)
	return Time.get_datetime_string_from_unix_time(saved_at, true).left(10)


# --- Internals -------------------------------------------------------------

static func _migrate(payload: Dictionary, from_version: int) -> Dictionary:
	## Bring an older save up to the current format.
	##
	## Empty today — version 1 is the only version there has ever been — and here from the
	## start anyway, because the alternative is discovering on the day of the first format
	## change that every existing save has to be thrown away. Each step should be written as
	## "if from_version < N: ...", so a save skipping two versions walks through both.
	if from_version < 1:
		# No version stamp at all: written by something that was not this function.
		push_warning("SaveGame: a save with no version; reading it as version 1")
	return payload


static func _summarise() -> Dictionary:
	var members: Array = []
	for member in GameState.party:
		members.append({
			"character_name": member.character_name,
			"class_id": member.class_id,
			"level": member.level,
			"xp": member.xp,
		})
	return {"party": members, "gold": GameState.gold}


static func _write_atomically(path: String, text: String) -> bool:
	## Write to a temporary file and move it into place, so a crash or a full disk mid-write
	## cannot leave a half-written save where the real one used to be. A player losing a run
	## to a bug is bad; losing the character is worse.
	var temp := path + ".part"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		push_error("SaveGame: could not open %s (error %d)" % [temp, FileAccess.get_open_error()])
		return false
	file.store_string(text)
	# Explicitly, and before the move: the file has to be closed and flushed, or the move can
	# beat the write to the disk.
	file.close()

	if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
		push_error("SaveGame: could not replace %s" % path)
		return false
	if DirAccess.rename_absolute(temp, path) != OK:
		push_error("SaveGame: could not move %s into place" % temp)
		return false
	return true
