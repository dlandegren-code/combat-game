extends RefCounted
## What a character says: going in, swinging, taking a wound, and dying of one.
##
## Six voices from the Medieval Fantasy 2 bundle, picked per character by the `voice` export on
## Combatant. Keyed by STRING rather than by an enum ordinal on purpose — the value is set on
## nodes in main.tscn, and "male_d" in a scene diff says what an anonymous `4` never would.
## An unknown key is a warning and silence, not a crash mid-fight.
##
## Every character in the arena is currently a man or an orc, so only the male voices are
## spoken for; the two female sets are here because the roster is data, not code, and adding a
## woman to the party should not also mean going and finding clips for her.

const AudioKit := preload("res://scripts/fx/audio_kit.gd")

## The default, and what an unrecognised voice falls back to.
const DEFAULT := "male_a"

const DEATH := {
	"male_a": [
		"res://assets/audio/voices/male_a_death_1.mp3",
		"res://assets/audio/voices/male_a_death_2.mp3",
	],
	"male_b": [
		"res://assets/audio/voices/male_b_death_1.mp3",
		"res://assets/audio/voices/male_b_death_2.mp3",
		"res://assets/audio/voices/male_b_death_3.mp3",
	],
	"male_c": [
		"res://assets/audio/voices/male_c_death_1.mp3",
		"res://assets/audio/voices/male_c_death_2.mp3",
		"res://assets/audio/voices/male_c_death_3.mp3",
	],
	"male_d": [
		"res://assets/audio/voices/male_d_death_1.mp3",
		"res://assets/audio/voices/male_d_death_2.mp3",
		"res://assets/audio/voices/male_d_death_3.mp3",
		"res://assets/audio/voices/male_d_death_4.mp3",
	],
	"female_a": [
		"res://assets/audio/voices/female_a_death_1.mp3",
		"res://assets/audio/voices/female_a_death_2.mp3",
	],
	"female_b": [
		"res://assets/audio/voices/female_b_death_1.mp3",
		"res://assets/audio/voices/female_b_death_2.mp3",
	],
}

## Grunts and gasps, one per wound that actually got through. MaleA has nine of them and
## MaleC only three, which is the bundle's doing rather than a choice — the thin sets repeat
## sooner, and there is nothing to be done about it short of borrowing another actor's throat.
const WOUND := {
	"male_a": [
		"res://assets/audio/voices/male_a_wound_1.mp3",
		"res://assets/audio/voices/male_a_wound_2.mp3",
		"res://assets/audio/voices/male_a_wound_3.mp3",
		"res://assets/audio/voices/male_a_wound_4.mp3",
		"res://assets/audio/voices/male_a_wound_5.mp3",
		"res://assets/audio/voices/male_a_wound_6.mp3",
		"res://assets/audio/voices/male_a_wound_7.mp3",
		"res://assets/audio/voices/male_a_wound_8.mp3",
		"res://assets/audio/voices/male_a_wound_9.mp3",
	],
	"male_b": [
		"res://assets/audio/voices/male_b_wound_1.mp3",
		"res://assets/audio/voices/male_b_wound_2.mp3",
		"res://assets/audio/voices/male_b_wound_3.mp3",
		"res://assets/audio/voices/male_b_wound_4.mp3",
		"res://assets/audio/voices/male_b_wound_5.mp3",
	],
	"male_c": [
		"res://assets/audio/voices/male_c_wound_1.mp3",
		"res://assets/audio/voices/male_c_wound_2.mp3",
		"res://assets/audio/voices/male_c_wound_3.mp3",
	],
	"male_d": [
		"res://assets/audio/voices/male_d_wound_1.mp3",
		"res://assets/audio/voices/male_d_wound_2.mp3",
		"res://assets/audio/voices/male_d_wound_3.mp3",
		"res://assets/audio/voices/male_d_wound_4.mp3",
		"res://assets/audio/voices/male_d_wound_5.mp3",
	],
	"female_a": [
		"res://assets/audio/voices/female_a_wound_1.mp3",
		"res://assets/audio/voices/female_a_wound_2.mp3",
		"res://assets/audio/voices/female_a_wound_3.mp3",
	],
	"female_b": [
		"res://assets/audio/voices/female_b_wound_1.mp3",
		"res://assets/audio/voices/female_b_wound_2.mp3",
	],
}

## --- Attacking -------------------------------------------------------------
##
## Three tiers of effort, chosen by what is in the character's hand (see effort_for_weapon):
## a dagger is a quick snap, a warhammer is a heave. The bundle splits the male sets as
## Attack/AttackFast/AttackHeavy and the female ones as AttackMedium/Fast/Heavy; both are
## folded into the same three tiers here so nothing downstream has to know that.

const ATTACK_FAST := {
	"male_a": [
		"res://assets/audio/voices/male_a_attack_fast_1.mp3",
		"res://assets/audio/voices/male_a_attack_fast_2.mp3",
	],
	"male_b": [
		"res://assets/audio/voices/male_b_attack_fast_1.mp3",
		"res://assets/audio/voices/male_b_attack_fast_2.mp3",
	],
	"male_c": [
		"res://assets/audio/voices/male_c_attack_fast_1.mp3",
		"res://assets/audio/voices/male_c_attack_fast_2.mp3",
	],
	"male_d": [
		"res://assets/audio/voices/male_d_attack_fast_1.mp3",
		"res://assets/audio/voices/male_d_attack_fast_2.mp3",
		"res://assets/audio/voices/male_d_attack_fast_3.mp3",
	],
	"female_a": [
		"res://assets/audio/voices/female_a_attack_fast_1.mp3",
		"res://assets/audio/voices/female_a_attack_fast_2.mp3",
	],
	"female_b": [
		"res://assets/audio/voices/female_b_attack_fast_1.mp3",
		"res://assets/audio/voices/female_b_attack_fast_2.mp3",
	],
}

const ATTACK_MEDIUM := {
	"male_a": [
		"res://assets/audio/voices/male_a_attack_medium_1.mp3",
	],
	"male_b": [
		"res://assets/audio/voices/male_b_attack_medium_1.mp3",
		"res://assets/audio/voices/male_b_attack_medium_2.mp3",
		"res://assets/audio/voices/male_b_attack_medium_3.mp3",
		"res://assets/audio/voices/male_b_attack_medium_4.mp3",
		"res://assets/audio/voices/male_b_attack_medium_5.mp3",
		"res://assets/audio/voices/male_b_attack_medium_6.mp3",
	],
	"male_c": [
		"res://assets/audio/voices/male_c_attack_medium_1.mp3",
		"res://assets/audio/voices/male_c_attack_medium_2.mp3",
		"res://assets/audio/voices/male_c_attack_medium_3.mp3",
		"res://assets/audio/voices/male_c_attack_medium_4.mp3",
		"res://assets/audio/voices/male_c_attack_medium_5.mp3",
		"res://assets/audio/voices/male_c_attack_medium_6.mp3",
	],
	"male_d": [
		"res://assets/audio/voices/male_d_attack_medium_1.mp3",
		"res://assets/audio/voices/male_d_attack_medium_2.mp3",
		"res://assets/audio/voices/male_d_attack_medium_3.mp3",
	],
	"female_a": [
		"res://assets/audio/voices/female_a_attack_medium_1.mp3",
		"res://assets/audio/voices/female_a_attack_medium_2.mp3",
	],
	"female_b": [
		"res://assets/audio/voices/female_b_attack_medium_1.mp3",
		"res://assets/audio/voices/female_b_attack_medium_2.mp3",
	],
}

const ATTACK_HEAVY := {
	"male_a": [
		"res://assets/audio/voices/male_a_attack_heavy_1.mp3",
		"res://assets/audio/voices/male_a_attack_heavy_2.mp3",
	],
	"male_b": [
		"res://assets/audio/voices/male_b_attack_heavy_1.mp3",
		"res://assets/audio/voices/male_b_attack_heavy_2.mp3",
		"res://assets/audio/voices/male_b_attack_heavy_3.mp3",
		"res://assets/audio/voices/male_b_attack_heavy_4.mp3",
	],
	"male_c": [
		"res://assets/audio/voices/male_c_attack_heavy_1.mp3",
		"res://assets/audio/voices/male_c_attack_heavy_2.mp3",
		"res://assets/audio/voices/male_c_attack_heavy_3.mp3",
		"res://assets/audio/voices/male_c_attack_heavy_4.mp3",
	],
	"male_d": [
		"res://assets/audio/voices/male_d_attack_heavy_1.mp3",
	],
	"female_a": [
		"res://assets/audio/voices/female_a_attack_heavy_1.mp3",
		"res://assets/audio/voices/female_a_attack_heavy_2.mp3",
	],
	"female_b": [
		"res://assets/audio/voices/female_b_attack_heavy_1.mp3",
		"res://assets/audio/voices/female_b_attack_heavy_2.mp3",
	],
}

## The battle cry of someone closing the distance. Males only — the bundle ships no female
## Charge set, so those voices fall back to their heaviest attack shout, which is the nearest
## thing to a roar they have.
const CHARGE := {
	"male_a": [
		"res://assets/audio/voices/male_a_charge_1.mp3",
		"res://assets/audio/voices/male_a_charge_2.mp3",
	],
	"male_b": [
		"res://assets/audio/voices/male_b_charge_1.mp3",
		"res://assets/audio/voices/male_b_charge_2.mp3",
		"res://assets/audio/voices/male_b_charge_3.mp3",
	],
	"male_c": [
		"res://assets/audio/voices/male_c_charge_1.mp3",
		"res://assets/audio/voices/male_c_charge_2.mp3",
		"res://assets/audio/voices/male_c_charge_3.mp3",
	],
	"male_d": [
		"res://assets/audio/voices/male_d_charge_1.mp3",
		"res://assets/audio/voices/male_d_charge_2.mp3",
		"res://assets/audio/voices/male_d_charge_3.mp3",
		"res://assets/audio/voices/male_d_charge_4.mp3",
		"res://assets/audio/voices/male_d_charge_5.mp3",
	],
}

## Drawing on a target. Males only again; a voice with no aim set simply shoots in silence
## rather than borrowing a grunt that would read as a melee swing.
const AIM := {
	"male_a": [
		"res://assets/audio/voices/male_a_aim_1.mp3",
		"res://assets/audio/voices/male_a_aim_2.mp3",
	],
	"male_b": [
		"res://assets/audio/voices/male_b_aim_1.mp3",
		"res://assets/audio/voices/male_b_aim_2.mp3",
		"res://assets/audio/voices/male_b_aim_3.mp3",
		"res://assets/audio/voices/male_b_aim_4.mp3",
	],
	"male_c": [
		"res://assets/audio/voices/male_c_aim_1.mp3",
		"res://assets/audio/voices/male_c_aim_2.mp3",
		"res://assets/audio/voices/male_c_aim_3.mp3",
	],
	"male_d": [
		"res://assets/audio/voices/male_d_aim_1.mp3",
		"res://assets/audio/voices/male_d_aim_2.mp3",
		"res://assets/audio/voices/male_d_aim_3.mp3",
	],
}

## Effort tiers, in the order they are meant to escalate.
enum Effort { FAST, MEDIUM, HEAVY }


static func effort_for_weapon(family: int) -> int:
	## How hard a swing with this weapon looks, which is what decides how hard it should sound.
	## Bare hands (family -1) land on MEDIUM: a punch is neither a flick nor a heave, and it is
	## the tier every voice in the bundle actually has.
	match family:
		ItemResource.WeaponSound.DAGGER:
			return Effort.FAST
		ItemResource.WeaponSound.AXE, ItemResource.WeaponSound.HAMMER:
			return Effort.HEAVY
		_:
			return Effort.MEDIUM

## A cry carries further than a blade and matters more than one, so it sits above both the
## swing and the landing.
const DEATH_VOLUME_DB := -3.0
## Under the death cry, and under the impact that caused it. A grunt happens many times a
## fight where a death cry happens once, and the thing that wears a mix out is not the loud
## sound — it is the frequent one.
const WOUND_VOLUME_DB := -6.0
## The effort of a swing, not the point of it — under the wound it may cause and well under
## the blade itself. Attacks are the most frequent voice line in the game by a wide margin.
const ATTACK_VOLUME_DB := -8.0
## A battle cry is meant to carry. Once per enemy per fight, so it can afford to.
const CHARGE_VOLUME_DB := -4.0

## Half the jitter the weapons get. A voice is a person, and pitching one about as freely as a
## sword clip turns the same actor into a different character every time they die.
const PITCH_JITTER := 0.03


static func attack(parent: Node, at: Vector3, voice: String, effort: int) -> void:
	## The grunt of swinging something. Fired at the start of the strike rather than on contact
	## — the effort goes in before the blade lands, and a character who shouts only on a hit
	## sounds like they knew it was going to connect.
	var set: Dictionary = ATTACK_MEDIUM
	match effort:
		Effort.FAST:
			set = ATTACK_FAST
		Effort.HEAVY:
			set = ATTACK_HEAVY
	_say(parent, at, set, voice, ATTACK_VOLUME_DB)


static func charge(parent: Node, at: Vector3, voice: String) -> void:
	## Coming for you. Falls back to the heaviest attack shout for a voice with no charge set
	## (see CHARGE) rather than to the default actor: a woman roaring in a man's voice is a
	## worse wrong answer than a woman roaring a little too much like she is swinging an axe.
	var set: Dictionary = CHARGE if CHARGE.has(voice) else ATTACK_HEAVY
	_say(parent, at, set, voice, CHARGE_VOLUME_DB)


static func aim(parent: Node, at: Vector3, voice: String) -> void:
	## Drawing on a target. Silent for a voice with no aim set — see AIM.
	if not AIM.has(voice):
		return
	_say(parent, at, AIM, voice, ATTACK_VOLUME_DB)


static func wound(parent: Node, at: Vector3, voice: String, delay: float = 0.0) -> void:
	## Being hurt. Fired only for damage that actually got through — armour turning a blow
	## dead already has its own clang, and grunting at a strike that did nothing would tell the
	## player they were hurt when the number says they were not.
	##
	## `delay` exists for melee: the blade does not visibly connect until the attack animation
	## has wound up, and a cry that beats the sword to the body reads as flinching early. See
	## WeaponSfx.landed for why the wait is taken here rather than on the node being hit.
	if delay > 0.0:
		if parent == null or not parent.is_inside_tree():
			return
		await parent.get_tree().create_timer(delay).timeout
		if not is_instance_valid(parent) or not parent.is_inside_tree():
			return
	_say(parent, at, WOUND, voice, WOUND_VOLUME_DB)


static func death(parent: Node, at: Vector3, voice: String) -> void:
	## The last cry, played at the body. Fired from Combatant._die before the animation starts,
	## so the sound leads the fall rather than trailing it.
	##
	## Parented to the arena by AudioKit.one_shot, which matters more here than anywhere else:
	## this is the one sound whose subject is, by definition, on its way out.
	_say(parent, at, DEATH, voice, DEATH_VOLUME_DB)


static func _say(parent: Node, at: Vector3, set: Dictionary, voice: String,
		volume_db: float) -> void:
	## Pick a line from one voice's set and play it. An unrecognised voice is a warning and the
	## default actor rather than silence: a character who never makes a sound reads as a bug in
	## the audio, while a character with the wrong voice reads as a character.
	var clips: Array = set.get(voice, [])
	if clips.is_empty():
		push_warning("Unknown voice '%s'; falling back to %s." % [voice, DEFAULT])
		clips = set[DEFAULT]
	AudioKit.one_shot(parent, at, AudioKit.pick(clips), volume_db, PITCH_JITTER)
