extends RefCounted
## The mouse pointer as action feedback: what the armed action would do to the thing under it.
##
## Godot ships seventeen cursor shapes and none of them mean "swing a sword here", so the ones
## that matter carry a picture instead — the same inventory icons the rest of the UI uses, so a
## Bows cursor and the Bows icon in the bag are recognisably the same thing.
##
## --- How a custom cursor actually works ---
##
## Input.set_custom_mouse_cursor REPLACES THE IMAGE OF AN EXISTING SHAPE rather than adding a
## new one. So this hangs every action picture off CURSOR_CROSS, which already means "you can
## act on this" everywhere in player.gd, and swaps that one shape's image as the armed action
## changes. Nothing else in the project uses CROSS, so nothing else is disturbed.
##
## Icons are 256px art and a cursor may be at most 256px, but a 256px pointer would swallow the
## square it is pointing at — so each one is decoded, resized once and cached.

## Cursor edge, in pixels. Big enough to read as a sword or a bow at a glance, small enough not
## to cover the tile it is aimed at.
const SIZE := 40

## Spec values that are NOT an icon path. Returned by Ability.get_cursor_icon when a built-in
## shape says it better than any picture would.
const HELP := "help"            ## the action applies here but something is missing
const NONE := ""                ## no art for this action; the plain "can act" cross

static var _cache: Dictionary = {}
static var _applied := ""


static func show_action(spec: String) -> void:
	## Put the pointer into whatever state `spec` describes. Called every frame the mouse moves,
	## so the common path — same action as last frame — must do nothing but set a shape.
	if spec == HELP:
		Input.set_default_cursor_shape(Input.CURSOR_HELP)
		return
	if spec == NONE:
		Input.set_default_cursor_shape(Input.CURSOR_CROSS)
		return
	if spec != _applied:
		var tex: ImageTexture = _cursor_texture(spec)
		if tex == null:
			# Missing art is not worth breaking targeting over: the plain cross still tells the
			# player the action would land here, it just does not say which action.
			Input.set_default_cursor_shape(Input.CURSOR_CROSS)
			return
		Input.set_custom_mouse_cursor(tex, Input.CURSOR_CROSS, Vector2(SIZE, SIZE) * 0.5)
		_applied = spec
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)


static func forbidden() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_FORBIDDEN)


static func move() -> void:
	## Movement keeps a built-in shape. It is the fallback action, it already has the floor
	## indicator marking the destination, and no icon in the set says "walk" better than a
	## pointing hand does.
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)


static func neutral() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


static func _cursor_texture(icon_path: String) -> ImageTexture:
	## Decode an icon once and keep it. The hotspot is the centre of the image (see show_action)
	## because these pointers are aimed AT something rather than clicked with a tip.
	if _cache.has(icon_path):
		return _cache[icon_path]
	var src: Texture2D = load(icon_path)
	if src == null:
		push_warning("Cursor icon missing: " + icon_path)
		_cache[icon_path] = null
		return null
	var img: Image = src.get_image()
	if img == null:
		push_warning("Cursor icon has no image: " + icon_path)
		_cache[icon_path] = null
		return null
	img = img.duplicate()
	# The icons import lossless (compress/mode=0), so this is normally a no-op — it is here so
	# that flipping one to VRAM compression later degrades to a working cursor rather than a
	# blank one.
	if img.is_compressed():
		img.decompress()
	img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	var tex := ImageTexture.create_from_image(img)
	_cache[icon_path] = tex
	return tex
