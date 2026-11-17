extends Control
## A small window over the current modal (D4-U confirm windows, D5-U refused-save notice).
## Presentation only: it reports which button was chosen through `chosen(id)` and nothing else. The owner (the HUD)
## decides what a choice means. Keyboard: Tab / arrow keys cycle through the buttons only, Enter or Space presses the
## focused one, Esc answers with `esc_id` (an empty `esc_id` means Esc does nothing).
const Palette=preload("res://chapter1/view/hud/palette.gd")
signal chosen(id: String)
var esc_id := ""
var buttons: Array[Button]=[]
var button_ids: Array[String]=[]
var panel: PanelContainer
var title_label: Label
var _default_index := 0

## spec: {width, title, content (Control or null), buttons: [{id, text}], default_id, esc_id}.
## `hud` supplies the shared look: _label(text,size,color), _button(text,action), _style(color,border).
func setup(hud: RefCounted,spec: Dictionary) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	esc_id=String(spec.get("esc_id",""))
	var dim := ColorRect.new();dim.color=Palette.SCRIM;dim.mouse_filter=Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(dim)
	var center := CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(center)
	panel=PanelContainer.new();panel.name="FlowDialogPanel";panel.custom_minimum_size.x=float(spec.get("width",760.0))
	# A confirm window edge is plain brass; the bright brass is reserved for the focused button.
	var frame: StyleBoxFlat=hud._style(Palette.SURFACE,Palette.BRASS)
	panel.add_theme_stylebox_override("panel",frame);center.add_child(panel)
	var column := VBoxContainer.new();column.add_theme_constant_override("separation",16);panel.add_child(column)
	title_label=hud._label(String(spec.get("title","")),30,Palette.INK);title_label.name="FlowDialogTitle";column.add_child(title_label)
	var content: Control=spec.get("content")
	if content!=null:column.add_child(content)
	var row := HFlowContainer.new();row.name="FlowDialogButtons"
	row.add_theme_constant_override("h_separation",14);row.add_theme_constant_override("v_separation",10)
	row.alignment=FlowContainer.ALIGNMENT_END;column.add_child(row)
	var default_id := String(spec.get("default_id",""))
	for entry in spec.get("buttons",[]):
		var id_: String=String(entry.id)
		var button: Button=hud._button(String(entry.text),func():chosen.emit(id_))
		button.name="Flow_"+id_
		button.gui_input.connect(_button_input)
		row.add_child(button);buttons.append(button);button_ids.append(id_)
		if id_==default_id:_default_index=buttons.size()-1
	# Focus stays inside this window: every direction cycles through its buttons.
	for i in buttons.size():
		var next_path := buttons[i].get_path_to(buttons[(i+1)%buttons.size()]) if buttons.size()>1 else NodePath("")
		var previous_path := buttons[i].get_path_to(buttons[(i+buttons.size()-1)%buttons.size()]) if buttons.size()>1 else NodePath("")
		if buttons.size()==1:next_path=buttons[i].get_path_to(buttons[i]);previous_path=next_path
		buttons[i].focus_next=next_path;buttons[i].focus_previous=previous_path
		buttons[i].focus_neighbor_right=next_path;buttons[i].focus_neighbor_bottom=next_path
		buttons[i].focus_neighbor_left=previous_path;buttons[i].focus_neighbor_top=previous_path

func focus_default() -> void:
	if buttons.is_empty():return
	buttons[_default_index].grab_focus()

func _button_input(event: InputEvent) -> void:
	_route_key(event)

func _gui_input(event: InputEvent) -> void:
	_route_key(event)

func _route_key(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.is_action_pressed("ui_cancel") and not esc_id.is_empty():
		accept_event();get_viewport().set_input_as_handled()
		chosen.emit(esc_id)
