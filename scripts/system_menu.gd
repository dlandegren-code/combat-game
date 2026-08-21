extends CanvasLayer
## The game-level controls, as a row of round plates in the very bottom-left corner:
## Options, Save, Quit. Deliberately separate from the action toolbar — these belong to the
## player, not to whoever's turn it is, so they stay put and stay enabled all the time.
##
## Options and Save are drawn and clickable but have nothing behind them yet (there is no
## settings screen and no serialisation); they say so rather than doing nothing silently.
## Quit is real.

const HudSlotScript := preload("res://scripts/hud_slot.gd")

const CELL := 46.0
const GAP := 8.0
const MARGIN := 12.0

## Each entry becomes one round plate, left to right.
const BUTTONS := [
	{"id": "options", "glyph": "⚙", "caption": "Options"},
	{"id": "save", "glyph": "▣", "caption": "Save"},
	{"id": "quit", "glyph": "✕", "caption": "Quit"},
]

var _root: Control
var _confirm: ConfirmationDialog
var _toast: Label
var _toast_tween: Tween = null


func _ready() -> void:
	layer = 3
	_build()


func _build() -> void:
	_root = Control.new()
	_root.name = "SystemCluster"
	_root.anchor_top = 1.0
	_root.anchor_bottom = 1.0
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var y := -(CELL + HudSlotScript.CAPTION_HEIGHT + MARGIN)
	var x := MARGIN
	for spec in BUTTONS:
		var slot := Control.new()
		slot.set_script(HudSlotScript)
		_root.add_child(slot)
		slot.build(CELL, HudSlotScript.FRAME_RING, HudSlotScript.FRAME_RING, true)
		slot.position = Vector2(x, y)
		slot.set_glyph(spec["glyph"])
		slot.set_caption(spec["caption"])
		slot.pressed.connect(_on_pressed.bind(spec["id"]))
		x += CELL + GAP

	_confirm = ConfirmationDialog.new()
	_confirm.dialog_text = "Quit the game? Any progress in this fight is lost."
	_confirm.title = "Quit Game"
	_confirm.confirmed.connect(func(): get_tree().quit())
	_root.add_child(_confirm)

	# Feedback for the two controls that have no system behind them yet. Sits just above the
	# cluster so it reads as a response to the click.
	_toast = Label.new()
	_toast.position = Vector2(MARGIN, y - 26.0)
	_toast.add_theme_font_size_override("font_size", 14)
	_toast.add_theme_color_override("font_color", Color(1.0, 0.87, 0.60))
	_toast.add_theme_constant_override("outline_size", 5)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toast)


func _on_pressed(id: String) -> void:
	match id:
		"quit":
			_confirm.popup_centered()
		"options":
			_show_toast("Options screen not built yet")
		"save":
			_show_toast("Saving not implemented yet")


func _show_toast(text: String) -> void:
	_toast.text = text
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.4)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)
