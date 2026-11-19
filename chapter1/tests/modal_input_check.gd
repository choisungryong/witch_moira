extends SceneTree
## Input check on the real core for the two in-run windows, with real GUI routing (events pushed into the window):
##   growth choice  - a mouse click on a card's pick button, then the keyboard (the focused button + Enter)
##   equipment      - a mouse click on "이 장비 장착", then the keyboard (focus that button + Enter)
## It plays the pilot until the moment exists, parks the pilot for the check, and reports what the core did.
## Needs a real renderer and --chapter1-profile-off. The pilot, not a person, makes every other choice.
##
##   python tools/dev/godot.py --fixed-fps 60 --resolution 1280x720 --path . --script res://chapter1/tests/modal_input_check.gd -- \
##       --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11
##
## Output: MODAL_INPUT lines and a MODAL_INPUT_RESULT line; exit 1 when a check failed or a check never found its moment.
var view: Node
var frame := 0
var wait_until := 0
var step := 0
var results: Dictionary = {}
var current := ""
var tries := 0
var picked_uid := -1
var before_pending := 0
var before_equipped := {}

func _initialize() -> void:
	if not "--chapter1-profile-off" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		print("MODAL_INPUT_ARGS ",JSON.stringify({"error":"needs --chapter1-profile-off and a real renderer"}))
		quit(2)
		return
	view = (load("res://chapter1/ChapterOne.tscn") as PackedScene).instantiate()
	root.add_child(view)
	# Optional: the run with the spell composition on (this tool only; the data file stays off). The run has not started yet here.
	if "--run-spells=on" in OS.get_cmdline_user_args():
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://chapter1/data/run_spells.json"))
		if not doc is Dictionary:
			print("MODAL_INPUT_ARGS ",JSON.stringify({"error":"run_spells.json unreadable"}));quit(2);return
		doc["enabled"] = true
		if not view.run.set_run_spells(doc):
			print("MODAL_INPUT_ARGS ",JSON.stringify({"error":"run_spells refused","errors":view.run.errors}));quit(2);return

func _find_buttons(node: Node, prefix: String, out: Array) -> void:
	if node is Button and String(node.text).begins_with(prefix): out.append(node)
	for child in node.get_children(): _find_buttons(child,prefix,out)

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

func _pending() -> int:
	return view.run.growth.snapshot().pending_levels.size()

func _record(name_: String, ok: bool, detail: Dictionary) -> void:
	results[name_] = ok
	detail.name = name_
	detail.ok = ok
	print("MODAL_INPUT ",JSON.stringify(detail))

func _unworn_wearable() -> int:
	var run: RefCounted = view.run
	for item in run.inventory:
		if run.equip_slot_of(int(item.uid)).is_empty() and run.can_equip(item): return int(item.uid)
	return -1

func _process(_delta: float) -> bool:
	if view == null or not view.is_inside_tree(): return true
	frame += 1
	var run: RefCounted = view.run
	var hud = view.hud
	match step:
		0:
			if frame == 5: view.start_run("chapter1.skill.frost"); step = 1
		1:
			# Choice moments: the first answers to the mouse, the second to the keyboard.
			if run.mode == "choice" and not results.has("boon_keyboard"):
				current = "boon_mouse" if not results.has("boon_mouse") else "boon_keyboard"
				view._pilot = false
				before_pending = _pending()
				wait_until = frame+75
				step = 2
			elif run.mode == "playing" and results.has("boon_keyboard") and not results.has("equip_keyboard") and run.tick > 1500:
				var uid := _unworn_wearable()
				if uid >= 0:
					picked_uid = uid
					current = "equip_mouse" if not results.has("equip_mouse") else "equip_keyboard"
					view._pilot = false
					before_equipped = run.equipped.duplicate()
					view.open_equipment()
					hud._selected_item = uid
					hud.invalidate()
					wait_until = frame+30
					step = 3
			elif results.has("equip_keyboard"):
				_finish()
				return true
		2:
			if frame >= wait_until:
				var cards: Array = []
				_find_buttons(hud.modal,"서약 선택",cards)
				if cards.size() < 2:
					_record(current,false,{"why":"card buttons not found","count":cards.size()})
					view._pilot = true; step = 1
					return false
				if current == "boon_mouse":
					_click(cards[1])
				else:
					var owner := root.gui_get_focus_owner()
					results["focus_owner_text"] = String(owner.text) if owner is Button else "(none)"
					if not (owner is Button): cards[0].grab_focus()
					_key(KEY_ENTER)
				wait_until = frame+12
				step = 4
		3:
			if frame >= wait_until:
				var buttons: Array = []
				_find_buttons(hud.modal,"이 장비 장착",buttons)
				if buttons.is_empty():
					_record(current,false,{"why":"equip button not found","mode":run.mode,"uid":picked_uid})
					view.close_equipment(); view._pilot = true; step = 1
					return false
				var button: Button = buttons[0]
				if current == "equip_mouse":
					_click(button)
				else:
					button.grab_focus()
					_key(KEY_ENTER)
				wait_until = frame+12
				step = 5
		4:
			if frame >= wait_until:
				var progressed: bool = _pending() < before_pending or run.mode != "choice"
				_record(current,progressed,{"mode":run.mode,"pending_before":before_pending,"pending_after":_pending(),"focus":results.get("focus_owner_text","")})
				view._pilot = true
				step = 1
		5:
			if frame >= wait_until:
				var slot_of: String = run.equip_slot_of(picked_uid)
				_record(current,not slot_of.is_empty(),{"uid":picked_uid,"slot":slot_of,"mode":run.mode})
				if run.mode == "inventory": view.close_equipment()
				view._pilot = true
				step = 1
	if frame > 100000:
		_finish()
		return true
	return false

func _finish() -> void:
	var bad := 0
	for name_ in ["boon_mouse","boon_keyboard","equip_mouse","equip_keyboard"]:
		if not results.get(name_,false): bad += 1
	print("MODAL_INPUT_RESULT ",JSON.stringify({"results":results,"failed_or_missing":bad,"window":[root.size.x,root.size.y],"tick":view.run.tick}))
	quit(1 if bad > 0 else 0)
