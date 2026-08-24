extends RefCounted
## The fire palette: what the Firebolt's trail and its splash are made of.
##
## Only the colours live here — the mechanics of turning a ramp into a working emitter are in
## particle_kit.gd, shared with the other effects. One ramp for every fire emitter is what
## makes the trail and the splash look like the same fire rather than two orange effects.

const ParticleKit := preload("res://scripts/fx/particle_kit.gd")

const HOT := Color(1.00, 0.95, 0.72)
const FLAME := Color(1.00, 0.55, 0.13)
const DEEP := Color(0.82, 0.18, 0.03)
const EMBER := Color(1.00, 0.72, 0.24)
const SMOKE := Color(0.16, 0.14, 0.13)


static func fire_ramp() -> GradientTexture1D:
	## White-hot at birth, orange through the middle, dying to a dark ember.
	return ParticleKit.ramp(
		[0.0, 0.22, 0.55, 1.0],
		[HOT, FLAME, Color(DEEP, 0.7), Color(0.25, 0.04, 0.02, 0.0)])


static func ember_ramp() -> GradientTexture1D:
	## Embers hold their colour and then wink out rather than cooling through the ramp — a
	## spark that faded to dark red would just read as dirt.
	return ParticleKit.ramp([0.0, 0.7, 1.0], [HOT, EMBER, Color(EMBER, 0.0)])


static func smoke_ramp() -> GradientTexture1D:
	## Smoke starts lit by the fire it came out of, then goes cold and thins away.
	##
	## Kept very low in alpha on purpose. The pack's smoke texture is a hard-edged faceted
	## blob rather than a soft cloud, so at any real opacity it stops reading as smoke and
	## starts reading as pale grey polygons sitting in front of the fire.
	return ParticleKit.ramp(
		[0.0, 0.18, 1.0],
		[Color(0.34, 0.18, 0.09, 0.30), Color(SMOKE, 0.22), Color(SMOKE, 0.0)])
