extends "res://chapter1/view/hud/window_frame.gd"
## The pause window (A10 W2), window weight: dim, contract board, small title plaque, then the way back (primary, with the Esc key plate), the gear window (secondary,
## key I), the two things that cannot be undone (danger: give up the run, quit), the controls once, and the one setting there is (screen shake, the brass switch).
## Presentation only. It asks through signals; chapter_hud.gd hands them on and chapter_one.gd decides (the gear window from the pause is the app's rule: it lifts the
## pause and opens the window, the core stays the judge).
const Loc = preload("res://chapter1/view/loc.gd")
signal resume
signal equipment
signal abandon
signal quit_game
signal motion_changed(on: bool)

var resume_button: Button
var motion_toggle: Control

var _title_kind := false

## motion_on: the "screen shake" setting as it is now. reduce: play the open as a plain fade.
## kind "run" (default): the window of a run in progress, as before. kind "title": the small window of the first screen (T13): the way back (TitleResume, Esc), the
## screen-shake switch (MotionToggle) and quitting the game (QuitGame); no gear, no give-up, no controls text.
func apply(motion_on: bool, reduce := false, kind := "run") -> void:
	reduce_motion = reduce
	build_frame(Loc.t("hud.pause.title"), 500.0, 360.0, 30)
	name = "PauseWindow"
	if kind == "title":
		_apply_title(motion_on)
		return
	body.add_theme_constant_override("separation", 14)
	var keys := UiStyle.text_label(Loc.t("hud.pause.keys"), "t6")
	keys.name = "Controls"
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(keys)
	resume_button = UiStyle.kit_button(Loc.t("hud.pause.resume"), func(): resume.emit(), "primary", true, "Esc")
	resume_button.name = "ResumeRun"
	resume_button.custom_minimum_size.x = 300
	var gear := UiStyle.kit_button(Loc.t("hud.pause.equipment"), func(): equipment.emit(), "secondary", false, "I")
	gear.name = "OpenEquipment"
	gear.custom_minimum_size.x = 300
	var column := VBoxContainer.new()
	column.name = "PauseActions"
	column.add_theme_constant_override("separation", 34)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(column)
	for b in [resume_button, gear]:
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(b)
	var row := HBoxContainer.new()
	row.name = "PauseFlowActions"
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var give_up := UiStyle.kit_button(Loc.t("hud.pause.abandon"), func(): abandon.emit(), "danger")
	give_up.name = "AbandonRun"
	var quit_ := UiStyle.kit_button(Loc.t("hud.pause.quit"), func(): quit_game.emit(), "danger")
	quit_.name = "QuitGame"
	give_up.custom_minimum_size.x = 180
	quit_.custom_minimum_size.x = 180
	row.add_child(give_up)
	row.add_child(quit_)
	column.add_child(row)
	var toggle := Parts.toggle(body, Loc.t("hud.pause.shake"), motion_on, 300.0)
	toggle.name = "MotionToggle"
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	toggle.changed.connect(func(on: bool): motion_changed.emit(on))
	motion_toggle = toggle
	# Focus order: resume, gear, give up, quit, the switch. Resume is the default, never a danger button.
	var chain: Array[Control] = [resume_button, gear, give_up, quit_, toggle]
	for i in chain.size():
		chain[i].focus_next = chain[i].get_path_to(chain[(i + 1) % chain.size()])
		chain[i].focus_previous = chain[i].get_path_to(chain[(i + chain.size() - 1) % chain.size()])
		chain[i].focus_neighbor_bottom = chain[i].focus_next
		chain[i].focus_neighbor_top = chain[i].focus_previous

func focus_default() -> void:
	if is_instance_valid(resume_button): resume_button.grab_focus()

## The first screen's Esc window. Focus order: resume, switch, quit. Resume is the default, never the danger button. Esc is the way back.
func _apply_title(motion_on: bool) -> void:
	_title_kind = true
	body.add_theme_constant_override("separation", 22)
	resume_button = UiStyle.kit_button(Loc.t("hud.pause.resume"), func(): resume.emit(), "primary", true, "Esc")
	resume_button.name = "TitleResume"
	resume_button.custom_minimum_size.x = 300
	resume_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(resume_button)
	var toggle := Parts.toggle(body, Loc.t("hud.pause.shake"), motion_on, 300.0)
	toggle.name = "MotionToggle"
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	toggle.changed.connect(func(on: bool): motion_changed.emit(on))
	motion_toggle = toggle
	var quit_ := UiStyle.kit_button(Loc.t("hud.pause.quit"), func(): quit_game.emit(), "danger")
	quit_.name = "QuitGame"
	quit_.custom_minimum_size.x = 180
	quit_.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(quit_)
	var chain: Array[Control] = [resume_button, toggle, quit_]
	for i in chain.size():
		chain[i].focus_next = chain[i].get_path_to(chain[(i + 1) % chain.size()])
		chain[i].focus_previous = chain[i].get_path_to(chain[(i + chain.size() - 1) % chain.size()])
		chain[i].focus_neighbor_bottom = chain[i].focus_next
		chain[i].focus_neighbor_top = chain[i].focus_previous

func _unhandled_key_input(e: InputEvent) -> void:
	if _title_kind and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		resume.emit()
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()
