extends RefCounted
## What weapons sound like: a melee blow — the swing and then whatever the swing found — and
## a bow, from the release to the arrow landing.
##
## The audio counterpart to sword_swing.gd and blood_splash.gd, and it fires from the same
## places they do — the whoosh beside the arc in Combatant._swing_arc, the impacts beside the
## sparks and the blood in _attempt_defense and take_damage, the bow around the projectile in
## _loose_arrow_at. Keeping them together is what stops the sound and the picture drifting
## apart when either is retimed.
##
## Clips are from the Medieval Fantasy 2 bundle (_sound/), 320 kbps mono-ish one-shots between
## half a second and two seconds. Every set is a variation group played through AudioKit.pick,
## and every one-shot is pitch-jittered: a fight is dozens of swings, and three sword clips at
## a fixed pitch stop being a sword and start being a metronome inside one turn.

const AudioKit := preload("res://scripts/fx/audio_kit.gd")

# --- Swings ----------------------------------------------------------------

## Whoosh-and-steel per weapon family, keyed by ItemResource.WeaponSound. A family is a SOUND
## family, not a game rule: the cleaver swings like an axe and the staff like a stick, and
## neither the rules nor the models care, so it is a field on the item rather than derived.
const SWING := {
	ItemResource.WeaponSound.SWORD: [
		"res://assets/audio/weapons/sword_1.mp3",
		"res://assets/audio/weapons/sword_2.mp3",
		"res://assets/audio/weapons/sword_3.mp3",
	],
	ItemResource.WeaponSound.AXE: [
		"res://assets/audio/weapons/axe_1.mp3",
		"res://assets/audio/weapons/axe_2.mp3",
		"res://assets/audio/weapons/axe_3.mp3",
	],
	ItemResource.WeaponSound.DAGGER: [
		"res://assets/audio/weapons/dagger_1.mp3",
		"res://assets/audio/weapons/dagger_2.mp3",
		"res://assets/audio/weapons/dagger_3.mp3",
	],
	ItemResource.WeaponSound.HAMMER: [
		"res://assets/audio/weapons/hammer_1.mp3",
		"res://assets/audio/weapons/hammer_2.mp3",
		"res://assets/audio/weapons/hammer_3.mp3",
	],
	ItemResource.WeaponSound.STICK: [
		"res://assets/audio/weapons/stick_1.mp3",
		"res://assets/audio/weapons/stick_2.mp3",
	],
}

# --- Landings --------------------------------------------------------------

## A wound: an edge going into a body. Used for the blades.
const CUT_FLESH := [
	"res://assets/audio/weapons/cut_flesh_1.mp3",
	"res://assets/audio/weapons/cut_flesh_2.mp3",
	"res://assets/audio/weapons/cut_flesh_3.mp3",
	"res://assets/audio/weapons/cut_flesh_4.mp3",
]

## Everything that lands without opening anything: a parried blade, a blow armour turned, and
## any wound dealt by something blunt. One set for all three because they are the same physical
## event — a hard thing stopped by another hard thing — and the picture already tells the
## player which of the three it was.
const IMPACT := [
	"res://assets/audio/weapons/impact_1.mp3",
	"res://assets/audio/weapons/impact_2.mp3",
	"res://assets/audio/weapons/impact_3.mp3",
	"res://assets/audio/weapons/impact_4.mp3",
]

## Which families open a wound rather than just bruising one. Anything not listed lands as an
## IMPACT even when it draws blood, which is what a warhammer should sound like.
const EDGED := [
	ItemResource.WeaponSound.SWORD,
	ItemResource.WeaponSound.AXE,
	ItemResource.WeaponSound.DAGGER,
]

# --- The bow ---------------------------------------------------------------

## The release. Two dry shots and two where the arrow whistles as it goes; they are mixed into
## one set rather than split by distance, because four variations is what stops an archer's
## turn sounding like the same button pressed twice.
const BOW_SHOT := [
	"res://assets/audio/weapons/bow_shot_1.mp3",
	"res://assets/audio/weapons/bow_shot_2.mp3",
	"res://assets/audio/weapons/bow_whistle_shot_1.mp3",
	"res://assets/audio/weapons/bow_whistle_shot_2.mp3",
]

## The arrival, played wherever the arrow ends up and whatever it found — a hit, a shield, or
## a shaft skittering off stone. Unlike a melee blow this does NOT branch on the outcome: the
## defender's own "Parry!" / "Dodge!" text already says which it was, and a second clip layered
## on top of a 0.6 s arrow flight only muddies the moment it lands.
const ARROW_IMPACT := [
	"res://assets/audio/weapons/arrow_impact_1.mp3",
	"res://assets/audio/weapons/arrow_impact_2.mp3",
]

# --- Levels ----------------------------------------------------------------
# Relative to each other first and to the SFX bus second: the landing is the moment of the
# attack, so it sits above the swing that set it up. Both are trims off clips the bundle
# masters hot, not a statement about how loud combat should be overall — that dial is the bus.

const SWING_VOLUME_DB := -9.0
const IMPACT_VOLUME_DB := -5.0
## Still under the impacts — a string letting go is not a blade being turned — but well clear
## of the swing. The release is heard from the shooter's own square, often across the arena
## from wherever the camera is looking, so it needs the headroom.
const BOW_VOLUME_DB := -7.0

## ±6%. Enough to break the pattern, small enough that a sword never sounds like a toy or a
## church bell.
const PITCH_JITTER := 0.06


static func swing(parent: Node, at: Vector3, family: int) -> void:
	## The blade going through the air. Fired for every melee strike whatever it lands, in step
	## with the visible arc — a swing that turns out to be parried still happened.
	##
	## A family with no clips (an empty hand, which has no whoosh to give) is silent rather
	## than borrowed from a weapon that is not there.
	var clips: Array = SWING.get(family, [])
	if clips.is_empty():
		return
	AudioKit.one_shot(parent, at, AudioKit.pick(clips), SWING_VOLUME_DB, PITCH_JITTER)


static func landed(parent: Node, at: Vector3, family: int, wounded: bool,
		delay: float = 0.0) -> void:
	## What the blow found. `wounded` is whether damage actually got through, which — together
	## with the family — is the whole difference between a cut and a clang: an edge that drew
	## blood cuts, an edge that armour turned does not.
	##
	## `delay` waits out the attack animation's wind-up so the sound arrives with the blade
	## rather than with the roll. It is waited HERE, in a static function hanging off the
	## arena, rather than in the defender that called us: a killing blow frees its target
	## during that same frame, and a coroutine on a freed node never resumes — which would
	## make the one sound the player most wants to hear the one sound that never plays.
	if delay > 0.0:
		if parent == null or not parent.is_inside_tree():
			return
		await parent.get_tree().create_timer(delay).timeout
		if not is_instance_valid(parent) or not parent.is_inside_tree():
			return
	var edged: bool = wounded and EDGED.has(family)
	AudioKit.one_shot(
		parent, at, AudioKit.pick(CUT_FLESH if edged else IMPACT),
		IMPACT_VOLUME_DB, PITCH_JITTER)


static func bow_shot(parent: Node, at: Vector3) -> void:
	## The string letting go, at the archer. Fired the moment the arrow is created, because
	## that is the moment it leaves the bow — the flight and the landing are the arrow's.
	AudioKit.one_shot(parent, at, AudioKit.pick(BOW_SHOT), BOW_VOLUME_DB, PITCH_JITTER)


static func arrow_impact(parent: Node, at: Vector3) -> void:
	## The arrow arriving, wherever it arrived.
	AudioKit.one_shot(parent, at, AudioKit.pick(ARROW_IMPACT), IMPACT_VOLUME_DB, PITCH_JITTER)
