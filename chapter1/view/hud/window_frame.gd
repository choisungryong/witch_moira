extends Control
## The frame every window-weight screen shares (A10 1.2): the window dim (SCRIM), the contract board of ui.kit.board, a small title plaque sitting on the
## board's top edge, and a body column under it. Pause, the confirm windows and (later) the battle record and the settings are this frame with their own body.
## It opens over Motion.WINDOW_IN (the whole frame fades in, the board grows from 0.97 to 1.0 in height) and closes over Motion.WINDOW_OUT; with reduced motion
## only the fade stays. Presentation only: it never reads the core, and says nothing but what its owner asks of it.
const Parts = preload("res://chapter1/view/hud/ui_parts.gd")
const UiStyle = preload("res://chapter1/view/hud/ui_style.gd")
const Palette = preload("res://chapter1/view/hud/palette.gd")
const Motion = preload("res://chapter1/view/hud/ui_motion.gd")

## How much of the plaque's height rides above the board's top edge.
const PLAQUE_OVERHANG := 0.5
const PLAQUE_ASPECT := 3.0
## The share of the plaque width that the title may fill (the brass field between the buckle straps).
const PLAQUE_FIELD := 0.56

var board: PanelContainer
var body: VBoxContainer
var plaque: Control
var stack: VBoxContainer
var dim: Control
var reduce_motion := false
var closing := false
var _tween: Tween
## 0..1: how much of the frame shows. Whole-frame modulate plus the pictures drawn with the art shader (which ignore modulate).
var fade := 1.0:
	set(value):
		fade = value
		modulate.a = value
		Parts.set_art_alpha(self, value)

## title: the plaque's words. width: the board's minimum width (code units). plaque_width: 0 = fitted to the title.
func build_frame(title: String, width: float, plaque_width := 0.0, title_size := 30, sub := "") -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	dim = UiStyle.scrim("window")
	dim.name = "Dim"
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	stack = VBoxContainer.new()
	stack.name = "WindowStack"
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(stack)
	# The plaque's brass field between its two buckle straps is about 0.56 of its width: the title takes the largest size of the scale (30, 26, 20) that fits it,
	# the plaque widens up to 560 when even 20 does not.
	var pw := plaque_width if plaque_width > 0.0 else 420.0
	var size_used := 20
	for step in [title_size, 26, 20]:
		if step > title_size: continue
		size_used = step
		if Parts.text_width(title, step, "heading") <= pw * PLAQUE_FIELD: break
	if plaque_width <= 0.0 and Parts.text_width(title, size_used, "heading") > pw * PLAQUE_FIELD:
		pw = minf(560.0, Parts.text_width(title, size_used, "heading") / PLAQUE_FIELD + 10.0)
	plaque = Parts.title(stack, title, pw, sub, size_used, PLAQUE_FIELD)
	plaque.custom_minimum_size = plaque.size
	plaque.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	plaque.z_index = 1
	var overhang := plaque.size.y * PLAQUE_OVERHANG
	stack.add_theme_constant_override("separation", -int(overhang))
	board = PanelContainer.new()
	board.name = "WindowBoard"
	board.custom_minimum_size.x = width
	board.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := UiStyle.window("board")
	style.content_margin_top = overhang + 22.0
	board.add_theme_stylebox_override("panel", style)
	stack.add_child(board)
	body = VBoxContainer.new()
	body.name = "WindowBody"
	body.add_theme_constant_override("separation", 16)
	board.add_child(body)
	fade = 0.0

## The frame fades in once it is in the tree and laid out. Call after add_child.
func open() -> void:
	if _tween != null: _tween.kill()
	fade = 0.0
	await get_tree().process_frame
	if closing or not is_inside_tree(): return
	stack.pivot_offset = stack.size * 0.5
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "fade", 1.0, Motion.WINDOW_IN if not reduce_motion else Motion.WINDOW_OUT)
	if not reduce_motion:
		stack.scale = Vector2(1.0, 0.97)
		_tween.tween_property(stack, "scale", Vector2.ONE, Motion.WINDOW_IN)

## Takes the frame out of play at once (no more clicks, no keys) and fades it over Motion.WINDOW_OUT, then frees it.
func close(instant := false) -> void:
	if closing: return
	closing = true
	if instant:
		# a window that is replaced by another at once (no crossfade of two windows)
		if get_parent() != null: get_parent().remove_child(self)
		queue_free()
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _tween != null: _tween.kill()
	if not is_inside_tree():
		queue_free()
		return
	_tween = create_tween()
	_tween.tween_property(self, "fade", 0.0, Motion.WINDOW_OUT)
	_tween.tween_callback(queue_free)

## A row of buttons under the body, centred; `keys` hang under each when the button has a key.
func button_row(buttons: Array) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 22)
	row.add_theme_constant_override("v_separation", 30)
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	for b in buttons: row.add_child(b)
	body.add_child(row)
	return row
