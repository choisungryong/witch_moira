extends SceneTree
## Input check of the pause window and its confirm window (A10 W2), on the real core with real GUI routing (events pushed into the window), keyboard and mouse:
##   keyboard: Esc opens it, the default focus is "resume" (never a danger button), Tab walks resume > gear > give up > quit > shake switch, Enter on resume goes back,
##             Enter on "give up" opens the confirm window whose focus is "cancel", Esc closes only that window and the focus comes back, Esc again goes back to the run
##   mouse:    a click on "gear" lifts the pause and opens the gear window (Esc closes it to the run), a click on the shake switch flips the setting, a click on resume goes back
## Needs a real renderer and --chapter1-profile-off. No pilot (a person's input is what is checked).
##
##   python tools/dev/godot.py --fixed-fps 60 --resolution 1280x720 --path . --script res://chapter1/tests/pause_input_check.gd -- \
##       --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11
##
## Output: PAUSE_INPUT lines and a PAUSE_INPUT_RESULT line; exit 1 when a check failed.
var view: Node
var results: Dictionary = {}

func _initialize() -> void:
	if not "--chapter1-profile-off" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		print("PAUSE_INPUT_ARGS ",JSON.stringify({"error":"needs --chapter1-profile-off and a real renderer"}))
		quit(2)
		return
	view = (load("res://chapter1/ChapterOne.tscn") as PackedScene).instantiate()
	root.add_child(view)
	_run.call_deferred()

func _frames(count: int) -> void:
	for i in count: await process_frame

func _key(code: int) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code as Key; event.physical_keycode = code as Key; event.pressed = pressed
		view.get_window().push_input(event)

func _click(button: Control) -> void:
	var centre: Vector2 = view.get_window().get_final_transform()*button.get_global_rect().get_center()
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = centre; event.global_position = centre; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
		view.get_window().push_input(event)

func _record(name_: String, ok: bool, detail := {}) -> void:
	results[name_] = ok
	detail["name"] = name_
	detail["ok"] = ok
	print("PAUSE_INPUT ",JSON.stringify(detail))

func _find(node: Node, node_name: String) -> Node:
	return node.find_child(node_name,true,false)

func _focus_name() -> String:
	var owner := view.get_viewport().gui_get_focus_owner()
	return String(owner.name) if owner != null else ""

func _pause_window() -> Node:
	for child in view.hud.root.get_children():
		if child.name == "PauseWindow" and not child.closing: return child
	return null

func _run() -> void:
	var run: RefCounted = view.run
	var hud = view.hud
	await _frames(5)
	view.start_run("chapter1.skill.frost")
	await _frames(40)
	# 1. Esc opens the window; the default focus is resume
	_key(KEY_ESCAPE)
	await _frames(20)
	var window := _pause_window()
	_record("esc_opens_pause",run.mode == "paused" and window != null,{"mode":run.mode})
	_record("default_focus_is_resume",_focus_name() == "ResumeRun",{"focus":_focus_name()})
	# 2. Tab order
	var order: Array[String] = [_focus_name()]
	for i in 5:
		_key(KEY_TAB)
		await _frames(3)
		order.append(_focus_name())
	_record("tab_order",order == ["ResumeRun","OpenEquipment","AbandonRun","QuitGame","MotionToggle","ResumeRun"],{"order":order})
	# 3. Enter on resume goes back to the run
	_key(KEY_ENTER)
	await _frames(20)
	_record("enter_resumes",run.mode == "playing" and _pause_window() == null,{"mode":run.mode})
	# 4. the confirm window: Enter on give up, focus on cancel, Esc closes only it
	_key(KEY_ESCAPE)
	await _frames(20)
	window = _pause_window()
	var give_up: Button = _find(window,"AbandonRun") if window != null else null
	if give_up == null:
		_record("abandon_confirm",false,{"why":"no give up button"})
	else:
		give_up.grab_focus()
		await _frames(2)
		_key(KEY_ENTER)
		await _frames(20)
		var opened: bool = hud.flow_dialog_open() and hud._flow_kind == "abandon"
		var focus_on_cancel := _focus_name() == "Flow_cancel"
		_key(KEY_ESCAPE)
		await _frames(30)
		var back: bool = not hud.flow_dialog_open() and run.mode == "paused" and _focus_name() == "AbandonRun"
		_record("abandon_confirm",opened and focus_on_cancel and back,{"opened":opened,"focus_on_cancel":focus_on_cancel,"back_to_pause":back,"focus_after":_focus_name()})
	# 5. Esc goes back to the run
	_key(KEY_ESCAPE)
	await _frames(20)
	_record("esc_resumes",run.mode == "playing",{"mode":run.mode})
	# 6. mouse: gear
	_key(KEY_ESCAPE)
	await _frames(20)
	window = _pause_window()
	if window == null:
		_record("mouse_gear",false,{"why":"no pause window"})
	else:
		_click(_find(window,"OpenEquipment"))
		await _frames(20)
		var in_gear: bool = run.mode == "inventory"
		_key(KEY_ESCAPE)
		await _frames(20)
		_record("mouse_gear",in_gear and run.mode == "playing",{"in_gear":in_gear,"mode_after_esc":run.mode})
	# 7. mouse: the shake switch and resume
	_key(KEY_ESCAPE)
	await _frames(20)
	window = _pause_window()
	if window == null:
		_record("mouse_toggle",false,{"why":"no pause window"})
	else:
		var was: bool = hud.motion_enabled
		_click(_find(window,"MotionToggle"))
		await _frames(6)
		var flipped: bool = hud.motion_enabled != was
		_click(_find(window,"MotionToggle"))
		await _frames(6)
		_record("mouse_toggle",flipped and hud.motion_enabled == was,{"was":was,"flipped":flipped})
		_click(_find(window,"ResumeRun"))
		await _frames(20)
		_record("mouse_resume",run.mode == "playing",{"mode":run.mode})
	var failed: Array[String] = []
	for key in results:
		if not results[key]: failed.append(key)
	print("PAUSE_INPUT_RESULT ",JSON.stringify({"checks":results.size(),"failed":failed}))
	quit(1 if not failed.is_empty() or results.size() < 9 else 0)
