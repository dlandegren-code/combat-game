extends Node3D
## A hit-point bar floating over a character's head.
##
## The floating nameplate says WHO somebody is; this says what state they are in. Two goblins
## with the same name and different wounds used to be indistinguishable on the battlefield —
## the numbers were on the party portraits, which only cover your own side, so an enemy's
## condition could only be inferred from the damage numbers as they scrolled past.
##
## Colour and threshold are taken from portrait_slot.gd rather than chosen again here, so a
## hero's bar over their head and the same hero's bar in the party panel never disagree about
## whether they are in trouble.
##
## Built in code and hung on the combatant at runtime (Combatant._ready), not placed in the
## scene: there are seven combatants in quest_scene.tscn and no reason for seven copies of this to be
## maintained by hand.

const PortraitSlot := preload("res://scripts/portrait_slot.gd")

## Metres. About half a character wide, so it reads as a label belonging to them rather than a
## shelf they are standing under.
const WIDTH := 0.7
const HEIGHT := 0.11
## Starting height above the character's origin, in local space. Only a placeholder: the
## combatant measures its own model and moves the bar to sit a fixed gap over that particular
## head — see Combatant.HEAD_CLEARANCE and _place_floating_labels. A fixed height here put one
## bar a hand's width over its owner and another three times that, because the models differ by
## half a metre.
const Y := 0.80
## How far the dark backing sticks out past the fill on every side, in metres. Small, but it is
## what stops a nearly-dead sliver of red vanishing against whatever is behind it.
const BORDER := 0.015

const COLOR_BACK := Color(0.06, 0.07, 0.09, 0.85)

## The reading printed across the bar. Sized to sit inside HEIGHT with a little air, and
## outlined, because it has to stay legible over both the green and the red beneath it.
## Height works out at FONT_SIZE * PIXEL_SIZE = 0.12 m, a shade TALLER than the 0.11 bar it is
## printed on. Deliberately: the number is the thing being read and the bar is its backdrop, so
## letting it overhang slightly keeps it legible on a bar this slim instead of squeezing it
## down to fit. The outline is what carries it over both the green and the red.
const TEXT_PIXEL_SIZE := 0.0040
const TEXT_FONT_SIZE := 30
const TEXT_OUTLINE := 10
const COLOR_TEXT := Color(1, 1, 1)
const COLOR_TEXT_OUTLINE := Color(0, 0, 0, 0.85)

## Draw order within the bar. The number must come after the two quads it lies on top of —
## see _build_text for why this, and not a depth offset, is what puts it in front.
const PRIORITY_BACK := 0
const PRIORITY_FILL := 1
const PRIORITY_TEXT := 2

var _fill_pivot: Node3D
var _fill: MeshInstance3D
var _text: Label3D


static func build(parent: Node3D) -> Node3D:
	# Loaded by path rather than by class_name, and typed explicitly: a script cannot preload
	# itself, and `new()` on a runtime-loaded GDScript has no inferable type.
	var bar: Node3D = load("res://scripts/health_bar_3d.gd").new()
	bar.name = "HealthBar3D"
	bar.position = Vector3(0, Y, 0)
	parent.add_child(bar)
	return bar


func _ready() -> void:
	_build_back()
	_build_fill()
	_build_text()


func set_hp(current: int, maximum: int, alive: bool = true) -> void:
	## Resize, recolour and relabel. A dead character's bar is hidden rather than emptied: an
	## empty bar still draws a rectangle, and a row of them over the corpses reads as live
	## enemies.
	visible = alive
	if not alive:
		return
	if _text:
		_text.text = "%d/%d" % [current, maxi(maximum, 0)]
	if _fill_pivot == null:
		return
	var f: float = clampf(float(current) / float(maxi(maximum, 1)), 0.0, 1.0)
	# Scaled on a pivot at the LEFT edge so the bar drains rightward like every other health
	# bar ever drawn, rather than shrinking toward its middle.
	_fill_pivot.scale.x = maxf(f, 0.0001)
	if _fill:
		var mat := _fill.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = PortraitSlot.COLOR_HP_LOW if f <= PortraitSlot.LOW_HP_FRACTION \
				else PortraitSlot.COLOR_HP_OK


func _build_back() -> void:
	var mi := _quad(WIDTH + BORDER * 2.0, HEIGHT + BORDER * 2.0, COLOR_BACK, PRIORITY_BACK)
	add_child(mi)


func _build_text() -> void:
	## The hit points, printed across the middle of the bar.
	##
	## Stacking here is by RENDER PRIORITY, not by nudging things along Z, and it has to be:
	## every layer billboards, which spins each quad to face the camera about its own origin
	## while the offsets BETWEEN them stay in the bar's own unrotated space. Orbit the camera
	## halfway round and a "slightly in front" offset is slightly behind. Priority does not
	## care where the camera is.
	##
	## The quads also stop writing depth (see _quad), so the number is not occluded by the very
	## bar it is printed on — while opaque world geometry still hides all three, so a wall
	## between you and a goblin hides its readout along with its bar.
	_text = Label3D.new()
	_text.name = "Reading"
	_text.text = "0/0"
	_text.pixel_size = TEXT_PIXEL_SIZE
	_text.font_size = TEXT_FONT_SIZE
	_text.outline_size = TEXT_OUTLINE
	_text.modulate = COLOR_TEXT
	_text.outline_modulate = COLOR_TEXT_OUTLINE
	_text.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_text.shaded = false
	_text.render_priority = PRIORITY_TEXT
	_text.outline_render_priority = PRIORITY_TEXT
	add_child(_text)


func _build_fill() -> void:
	_fill_pivot = Node3D.new()
	_fill_pivot.name = "Fill"
	# The pivot sits on the bar's left edge; the quad hangs half its own width to the right of
	# it. Scaling the pivot then pins the left edge and moves only the right one.
	_fill_pivot.position = Vector3(-WIDTH * 0.5, 0, 0)
	add_child(_fill_pivot)
	_fill = _quad(WIDTH, HEIGHT, PortraitSlot.COLOR_HP_OK, PRIORITY_FILL)
	_fill.position = Vector3(WIDTH * 0.5, 0, 0)
	_fill_pivot.add_child(_fill)


func _quad(w: float, h: float, colour: Color, priority: int) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(w, h)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	# Unshaded, or the dungeon's one directional light would dim a bar depending on which way
	# the character happened to be facing.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# No depth WRITE, so the layers of the bar cannot occlude one another and the number stays
	# readable; depth TEST is left on, so the world still occludes the bar as a whole.
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.render_priority = priority
	# Y-billboard, matching the nameplate above it: the bar turns to face the camera as it
	# orbits, but never tips, so it stays a horizontal bar rather than a lozenge.
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mi.material_override = mat
	return mi
