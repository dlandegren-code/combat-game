extends RefCounted
## The healing palette: what a mended wound is made of.
##
## The counterpart to fire_fx.gd. Only the colours live here — turning a ramp into a working
## emitter is particle_kit.gd's job, shared with every other effect — and having one palette for
## every healing emitter is what makes the motes and the ring read as one spell rather than two
## green effects that happen to fire together.
##
## Green going to gold rather than green alone: a flat green cloud reads as poison, which is
## exactly the wrong thing for the one effect in the game that means good news.

const ParticleKit := preload("res://scripts/fx/particle_kit.gd")

const PALE := Color(0.86, 1.00, 0.88)
const LEAF := Color(0.36, 0.90, 0.50)
const DEEP := Color(0.10, 0.55, 0.32)
const GOLD := Color(1.00, 0.93, 0.60)


static func mote_ramp() -> GradientTexture1D:
	## A mote lights pale, warms through green, and goes out gold.
	return ParticleKit.ramp(
		[0.0, 0.25, 0.70, 1.0],
		[PALE, LEAF, Color(GOLD, 0.75), Color(GOLD, 0.0)])


static func spark_ramp() -> GradientTexture1D:
	## Brighter and shorter: the few points that catch the eye first.
	return ParticleKit.ramp([0.0, 0.6, 1.0], [Color(1, 1, 1), PALE, Color(LEAF, 0.0)])


static func ring_ramp() -> GradientTexture1D:
	## The ring at the feet, which is the deepest colour of the three so it reads as ground
	## rather than as more motes.
	return ParticleKit.ramp([0.0, 0.35, 1.0], [PALE, Color(DEEP, 0.55), Color(DEEP, 0.0)])
