extends Node3D
## Editor tool: bakes a brighter copy of the wizard's robe texture.
##
## Run it by playing tools/brighten_wizard_robe.tscn (summer_play), then read the
## console. It writes one .res and touches nothing else.
##
## WHY A BAKED .res AND NOT A .png
## Writing a new .png would need Godot to re-import it before the file is usable,
## which a headless tool run cannot trigger. An ImageTexture saved as .res is a
## native resource, so `wizard_body.tres` can point at it immediately.
##
## WHY GAMMA AND NOT A MULTIPLY
## The source already contains pixels at full brightness (measured range
## 0.098 .. 1.000), so scaling would clip its highlights to flat white. A power
## curve lifts shadows and midtones while leaving 0 at 0 and 1 at 1.
##
## The exponent is derived, not eyeballed: the robe's dominant tone is ~0.28 and
## the skirt mesh (CharacterSkin.robe_color on wizard_model.tscn) is 0.49, so
##     0.28 ^ exponent = 0.49  ->  exponent = ln(0.49) / ln(0.28) = 0.56
## which lands the painted robe on the same brightness as the skirt it meets.

const SRC := "res://assets/images/wizard_robe_albedo.png"
const OUT := "res://assets/materials/wizard_robe_bright.res"

## Lower = brighter. See the derivation above before changing this.
@export var exponent := 0.56


func _ready() -> void:
	var tex: Texture2D = load(SRC)
	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	print("[bright] src=%s %dx%d fmt=%d" % [SRC, img.get_width(), img.get_height(), img.get_format()])

	var before := _stats(img)
	for y in img.get_height():
		for x in img.get_width():
			var c: Color = img.get_pixel(x, y)
			img.set_pixel(x, y, Color(
				pow(c.r, exponent), pow(c.g, exponent), pow(c.b, exponent), c.a))
	var after := _stats(img)

	print("[bright] mean  %.3f -> %.3f" % [before.mean, after.mean])
	print("[bright] range %.3f..%.3f -> %.3f..%.3f" % [
		before.vmin, before.vmax, after.vmin, after.vmax])
	print("[bright] clipped-to-white pixels: %d -> %d" % [before.white, after.white])

	var out := ImageTexture.create_from_image(img)
	print("[bright] save %s -> %d" % [OUT, ResourceSaver.save(out, OUT)])
	print("[bright] DONE")


func _stats(img: Image) -> Dictionary:
	var vmin := 1.0
	var vmax := 0.0
	var sum := 0.0
	var n := 0
	var white := 0
	var step: int = 4
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var c: Color = img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var v: float = max(c.r, max(c.g, c.b))
			vmin = min(vmin, v)
			vmax = max(vmax, v)
			sum += v
			n += 1
			if c.r >= 0.999 and c.g >= 0.999 and c.b >= 0.999:
				white += 1
	return {"vmin": vmin, "vmax": vmax, "mean": sum / max(1, n), "white": white}
