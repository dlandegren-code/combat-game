@tool
extends RefCounted
## Every enemy template there is, and the choosing between them.
##
## A list of paths rather than a scan of resources/enemies/, because a directory listing of
## res:// is not dependable in an exported build — and because the ORDER here is part of the
## generator's contract: the same seed walks the same list. New templates go at the END.

const TEMPLATES := [
	"res://resources/enemies/goblin.tres",
	"res://resources/enemies/goblin_archer.tres",
	"res://resources/enemies/goblin_brute.tres",
	"res://resources/enemies/goblin_warchief.tres",
	"res://resources/enemies/bandit.tres",
	"res://resources/enemies/bandit_archer.tres",
	"res://resources/enemies/sellsword.tres",
	"res://resources/enemies/bandit_captain.tres",
	"res://resources/enemies/ghoul.tres",
	"res://resources/enemies/grave_robber.tres",
	"res://resources/enemies/cultist.tres",
	"res://resources/enemies/crypt_lord.tres",
]

## Who fills a dungeon whose theme nothing is listed for. Should never happen; if it does, it is
## a dungeon of goblins rather than an empty one.
const FALLBACK_THEME := "warren"

static var _cache: Array = []


static func all() -> Array:
	if _cache.is_empty():
		for path in TEMPLATES:
			var t = load(path)
			if t != null:
				_cache.append(t)
	return _cache


static func find(id: String) -> Resource:
	for t in all():
		if t.id == id:
			return t
	return null


static func candidates(theme: String, tier: int, bosses: bool) -> Array:
	## The templates that fit, in TEMPLATES order.
	var out: Array = []
	for t in all():
		if t.is_boss == bosses and t.fits(theme, tier):
			out.append(t)
	if out.is_empty() and theme != FALLBACK_THEME:
		return candidates(FALLBACK_THEME, tier, bosses)
	return out


static func pick(rng: RandomNumberGenerator, pool: Array) -> Resource:
	## One of `pool`, by weight.
	if pool.is_empty():
		return null
	var total := 0.0
	for t in pool:
		total += maxf(t.weight, 0.0)
	var roll := rng.randf() * total
	for t in pool:
		roll -= maxf(t.weight, 0.0)
		if roll <= 0.0:
			return t
	return pool[-1]
