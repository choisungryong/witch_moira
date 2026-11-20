extends "res://chapter1/view/hud/window_frame.gd"
## A small window over the current modal (D4-U confirm windows, D5-U refused-save notice, the battle record), in the window frame of A10 (WindowFrame: dim,
## contract board, title plaque, 0.18 s open and 0.12 s close).
## Presentation only: it reports which button was chosen through `chosen(id)` and nothing else. The owner (the HUD) decides what a choice means.
## Keyboard: Tab / arrow keys cycle through the buttons only, Enter or Space presses the focused one, Esc answers with `esc_id` (an empty `esc_id` means Esc does
## nothing). The default focus is never a danger button (the owner names `default_id`); the Esc button wears a key plate.
signal chosen(id: String)
var esc_id := ""
var buttons: Array[Button] = []
var button_ids: Array[String] = []
var panel: PanelContainer
var title_label: Label
var _default_index := 0

## spec: {width, title, content (Control or null), buttons: [{id, text, kind}], default_id, esc_id}. kind = primary / secondary / danger (default secondary).
## `hud` supplies the shared look: _dialog_text(text) for a plain body.
func setup(_hud: RefCounted, spec: Dictionary) -> void:
	esc_id = String(spec.get("esc_id", ""))
	build_frame(String(spec.get("title", "")), float(spec.get("width", 760.0)))
	name = "FlowDialog"
	panel = board
	board.name = "FlowDialogPanel"
	title_label = plaque.get_node_or_null("Title")
	var content: Control = spec.get("content")
	if content != null:
		if content is Label:
			content.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			content.size_flags_horizontal = Control.SIZE_FILL
		body.add_child(content)
	var entries: Array = spec.get("buttons", [])
	var default_id := String(spec.get("default_id", ""))
	var made: Array[Button] = []
	for entry in entries:
		var id_: String = String(entry.id)
		var kind: String = String(entry.get("kind", "secondary"))
		var key := "Esc" if id_ == esc_id and not esc_id.is_empty() else ""
		var button: Button = UiStyle.kit_button(String(entry.text), func(): chosen.emit(id_), kind, String(entry.text).length() > 6, key)
		button.name = "Flow_" + id_
		button.gui_input.connect(_route_key)
		made.append(button)
		buttons.append(button)
		button_ids.append(id_)
		if id_ == default_id: _default_index = buttons.size() - 1
	button_row(made).name = "FlowDialogButtons"
	# Focus stays inside this window: every direction cycles through its buttons.
	for i in buttons.size():
		var next_path := buttons[i].get_path_to(buttons[(i + 1) % buttons.size()]) if buttons.size() > 1 else NodePath("")
		var previous_path := buttons[i].get_path_to(buttons[(i + buttons.size() - 1) % buttons.size()]) if buttons.size() > 1 else NodePath("")
		if buttons.size() == 1:
			next_path = buttons[i].get_path_to(buttons[i])
			previous_path = next_path
		buttons[i].focus_next = next_path
		buttons[i].focus_previous = previous_path
		buttons[i].focus_neighbor_right = next_path
		buttons[i].focus_neighbor_bottom = next_path
		buttons[i].focus_neighbor_left = previous_path
		buttons[i].focus_neighbor_top = previous_path

## Leaves over Motion.WINDOW_OUT; the buttons give up the focus at once so no key reaches them.
func close(instant := false) -> void:
	for b in buttons:
		b.release_focus()
		b.focus_mode = Control.FOCUS_NONE
	super.close(instant)

## Puts the focus on the default button (the caller defers it until the window is in the tree).
func focus_default() -> void:
	if buttons.is_empty(): return
	buttons[_default_index].grab_focus()

func _gui_input(event: InputEvent) -> void:
	_route_key(event)

func _route_key(event: InputEvent) -> void:
	if closing: return
	if event is InputEventKey and event.pressed and not event.echo and event.is_action_pressed("ui_cancel") and not esc_id.is_empty():
		accept_event()
		get_viewport().set_input_as_handled()
		chosen.emit(esc_id)
