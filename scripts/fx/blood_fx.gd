extends RefCounted
## The blood palette: what an arrow that gets through throws out of the target.
##
## Companion to fire_fx.gd — same arrangement, different colours. The mechanics live in
## particle_kit.gd.
##
## Blood is the one effect here that must NOT be additive. Additive blood glows pink against
## a dark floor and disappears entirely against a bright one; blended dark red reads as blood
## on both. Everything below is therefore mixed rather than added, and the ramps carry real
## alpha rather than fading to black.

const ParticleKit := preload("res://scripts/fx/particle_kit.gd")

## Fresh arterial red for the spray, a darker venous red for the chunks and the pooling, and
## a desaturated brown for the mist so it does not read as a second, pinker spray.
const FRESH := Color(0.72, 0.06, 0.05)
const DEEP := Color(0.50, 0.05, 0.04)
const DARK := Color(0.27, 0.03, 0.03)
const MIST := Color(0.38, 0.09, 0.08)


static func spray_ramp() -> GradientTexture1D:
	## Droplets stay solid for most of their flight and only give out at the end. Blood that
	## faded evenly would read as smoke tinted red.
	return ParticleKit.ramp(
		[0.0, 0.15, 0.75, 1.0],
		[Color(FRESH, 0.95), Color(FRESH, 1.0), Color(DEEP, 0.9), Color(DARK, 0.0)])


static func chunk_ramp() -> GradientTexture1D:
	## Gobbets are darker than the spray and hold on slightly longer — they are the heavy
	## part of the splash and the last thing still moving.
	return ParticleKit.ramp(
		[0.0, 0.8, 1.0], [Color(DEEP, 1.0), Color(DARK, 0.95), Color(DARK, 0.0)])


static func mist_ramp() -> GradientTexture1D:
	## The short-lived haze right at the wound. Thin, and gone well before the droplets land.
	return ParticleKit.ramp(
		[0.0, 0.25, 1.0],
		[Color(MIST, 0.55), Color(MIST, 0.30), Color(DARK, 0.0)])


static func pool_ramp() -> GradientTexture1D:
	## The stain left on the floor: darkens as it spreads, then soaks away.
	return ParticleKit.ramp(
		[0.0, 0.3, 1.0], [Color(DEEP, 0.0), Color(DARK, 0.75), Color(DARK, 0.0)])
