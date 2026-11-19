extends SceneTree
## Input check for the battle record window, with real GUI routing (events pushed into the window):
##   mouse     - click "전투 기록" on the result window, click the close button
##   keyboard  - focus the open button, Enter opens, Esc closes; open again, Enter on the (default) close button closes;
##               Down scrolls a tall record; R while the record is open does not leave the result window
## The result window is put up on the real core by forcing its end mode (like scene_shot.gd); the record is a fixture
## (chapter1/tests/fixtures/ui/combat_record.<variant>.json), so this checks the window's input, not the recorder.
## Needs a real renderer and --chapter1-profile-off.
##
##   python tools/dev/godot.py --fixed-fps 60 --resolution 1280x720 --path . --script res://chapter1/tests/record_input_check.gd -- \
##       --chapter1-profile-off [--variant=long]
##
## Output: RECORD_INPUT lines and a RECORD_INPUT_RESULT line; exit 1 when a check failed.
var view: Node
var results: Dictionary = {}
var retries := 0
var variant := "normal"

func _initialize() -> void:
	if not "--chapter1-profile-off" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		print("RECORD_INPUT_ARGS ",JSON.stringify({"error":"needs --chapter1-profile-off and a real renderer"}))
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=")
	view = (load("res://chapter1/ChapterOne.tscn") as PackedScene).instantiate()
	if view.get_script() == null or view.get("run") == null:
		push_error("ChapterOne failed to load its script; see the errors above")
		quit(3)
		return
	root.add_child(view)
	_run.call_deferred()

func _frames(count: int) -> void:
	for i in count: await process_frame

func _find_button(node: Node, name_: String) -> Button:
	if node is Button and node.name == name_: return node
	for child in node.get_children():
		var found := _find_button(child,name_)
		if found != null: return found
	return null

func _click(button: Button) -> void:
	var centre: Vector2 = view.get_window().get_final_transform()*button.get_global_rect().get_center()
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = centre; event.global_position = centre; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
		view.get_window().push_input(event)

func _key(code: int) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code as Key; event.physical_keycode = code as Key; event.pressed = pressed
		view.get_window().push_input(event)

func _record(name_: String, ok: bool, detail: Dictionary = {}) -> void:
	results[name_] = ok
	detail.name = name_
	detail.ok = ok
	print("RECORD_INPUT ",JSON.stringify(detail))

func _focus_name() -> String:
	var owner: Control = view.hud.root.get_viewport().gui_get_focus_owner()
	return "" if owner == null else String(owner.name)

func _run() -> void:
	var hud = view.hud
	var run: RefCounted = view.run
	hud.retry.connect(func(): retries += 1)
	var fx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://chapter1/tests/fixtures/ui/combat_record.%s.json" % variant))
	view.start_run("chapter1.skill.frost")
	await _frames(3)
	hud.motion_enabled = false
	hud.set_run_record(fx.view.duplicate(true))
	run._terminal_mode = String(fx.mode)
	run.mode = String(fx.mode)
	hud.invalidate()
	for i in 300:
		await process_frame
		if hud.overlay.visible: break
	await _frames(20)
	var open_button := _find_button(hud.modal,"CombatRecord")
	_record("button_present",open_button != null,{"variant":variant})
	if open_button == null:
		_finish()
		return
	# mouse: open, then close with the close button
	_click(open_button)
	await _frames(10)
	_record("mouse_open",hud.combat_record_open(),{"focus":_focus_name()})
	var close_button := _find_button(hud._flow_dialog,"Flow_close")
	_record("close_button_has_focus",close_button != null and close_button.has_focus(),{"focus":_focus_name()})
	_click(close_button)
	await _frames(10)
	_record("mouse_close",not hud.combat_record_open(),{"focus":_focus_name()})
	_record("focus_after_mouse_close",_focus_name() != "",{"focus":_focus_name()})
	# keyboard: focus the open button, Enter opens; Esc closes
	open_button = _find_button(hud.modal,"CombatRecord")
	open_button.grab_focus()
	await _frames(3)
	_key(KEY_ENTER)
	await _frames(10)
	_record("key_open_enter",hud.combat_record_open(),{"focus":_focus_name()})
	# R while the record is open must not leave the result window
	var before := retries
	_key(KEY_R)
	await _frames(6)
	_record("r_blocked_while_open",retries == before and hud.combat_record_open(),{"retries":retries})
	# Down scrolls when the record is taller than the window
	var scroll: ScrollContainer = hud._flow_dialog.find_child("RecordScroll",true,false)
	var scrolls := scroll != null and scroll.get_v_scroll_bar().max_value > scroll.size.y + 1.0
	var top := scroll.scroll_vertical if scroll != null else 0
	_key(KEY_DOWN)
	await _frames(4)
	if scrolls:
		_record("down_scrolls_tall_record",scroll.scroll_vertical > top,{"before":top,"after":scroll.scroll_vertical})
	else:
		_record("down_scrolls_tall_record",true,{"note":"the record fits, nothing to scroll"})
	_key(KEY_ESCAPE)
	await _frames(10)
	_record("key_close_esc",not hud.combat_record_open(),{"focus":_focus_name()})
	_record("focus_back_on_open_button",_focus_name() == "CombatRecord",{"focus":_focus_name()})
	# keyboard: open again, Enter on the default (close) button closes
	_key(KEY_ENTER)
	await _frames(10)
	var reopened: bool = hud.combat_record_open()
	_key(KEY_ENTER)
	await _frames(10)
	_record("key_close_enter",reopened and not hud.combat_record_open(),{"reopened":reopened,"focus":_focus_name()})
	# the result window's own buttons still work afterwards
	_record("result_window_intact",hud.overlay.visible and _find_button(hud.modal,"RetrySameWitch") != null)
	_finish()

func _finish() -> void:
	var failed: Array[String] = []
	for key in results:
		if not results[key]: failed.append(key)
	print("RECORD_INPUT_RESULT ",JSON.stringify({"checks":results.size(),"failures":failed}))
	quit(1 if not failed.is_empty() else 0)
