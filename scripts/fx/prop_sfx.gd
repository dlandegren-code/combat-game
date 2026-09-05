extends RefCounted
## The sounds things in the world make when they are used: doors, chests, barrels, locks.
##
## The third palette alongside weapon_sfx.gd and voice_sfx.gd, and the one for everything that
## is neither a fighter nor their gear. Kept separate rather than folded into weapon_sfx so the
## interact action never has to reach into a file about swords.

const AudioKit := preload("res://scripts/fx/audio_kit.gd")

const DOOR_OPEN := "res://assets/audio/props/door_open.mp3"
const DOOR_CLOSE := "res://assets/audio/props/door_close.mp3"
## The handle refusing to turn. A lock clunking rather than a rattle, because the bundle has no
## rattle — it is the closest thing to "that is not going to move" it ships.
const DOOR_LOCKED := "res://assets/audio/props/door_locked.mp3"

## Loud enough to carry across the chamber — a door opening somewhere in the dungeon is
## information, and the player should hear one they did not open themselves.
const DOOR_VOLUME_DB := -4.0
## Doors are big and slow. Almost no jitter: the same hinge should sound like the same hinge
## every time, which is exactly the opposite of what the weapon clips want.
const PITCH_JITTER := 0.02


## A lid coming up. Three of them, because a chest gets opened once a room while a door gets
## worked over and over — the variety is worth more here than anywhere else.
const CHEST_OPEN := [
	"res://assets/audio/props/chest_open_1.mp3",
	"res://assets/audio/props/chest_open_2.mp3",
	"res://assets/audio/props/chest_open_3.mp3",
]
## Hands going through junk. What a barrel gives instead of a lid.
const RUMMAGE := "res://assets/audio/props/rummage.mp3"
## A lock giving way, to a key or to a pick. The reward sound for the one roll in the dungeon
## that can fail, so it sits a little above the rest.
const LOCK_OPEN := "res://assets/audio/props/lock_open.mp3"
const LOCK_VOLUME_DB := -2.0


static func chest_open(parent: Node, at: Vector3) -> void:
	AudioKit.one_shot(parent, at, AudioKit.pick(CHEST_OPEN), DOOR_VOLUME_DB, PITCH_JITTER)


static func rummage(parent: Node, at: Vector3) -> void:
	AudioKit.one_shot(parent, at, RUMMAGE, DOOR_VOLUME_DB, PITCH_JITTER)


static func lock_open(parent: Node, at: Vector3) -> void:
	AudioKit.one_shot(parent, at, LOCK_OPEN, LOCK_VOLUME_DB, PITCH_JITTER)


static func door(parent: Node, at: Vector3, opening: bool) -> void:
	## The hinge and the latch. Fired as the swing STARTS, not when it finishes — a door you
	## hear a moment before it has finished moving reads as the sound causing the motion.
	AudioKit.one_shot(
		parent, at, DOOR_OPEN if opening else DOOR_CLOSE, DOOR_VOLUME_DB, PITCH_JITTER)


static func door_locked(parent: Node, at: Vector3) -> void:
	## Somebody tried a door that will not open. The only feedback a locked door gives, so it
	## has to be audible over a fight — hence level with the door itself rather than under it.
	AudioKit.one_shot(parent, at, DOOR_LOCKED, DOOR_VOLUME_DB, PITCH_JITTER)
