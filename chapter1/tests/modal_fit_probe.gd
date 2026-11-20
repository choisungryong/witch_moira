extends SceneTree
## Real-run probe for the two in-run windows: the equipment compare ("장비와 전투 선택") and the growth choice ("성장 선택").
## It runs the pilot on the real core (no fixtures), and at each probe moment opens the window the game would open and measures
## whether the main action button is on screen and inside the window, and whether the window stays inside the canvas.
## Read only: it never calls choose/equip, and it needs --chapter1-profile-off (no save is opened).
##
##   python tools/dev/godot.py --fixed-fps 60 --resolution 1280x720 --path . --script res://chapter1/tests/modal_fit_probe.gd -- \
##       --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --until=30000 [--shots=_local/shots/<dir>]
##
## Output: MODAL_FIT lines (one per probe) and a MODAL_FIT_RESULT line. Exit 1 when any probe finds a hidden button or an
## overflowing window. --shots saves the worst equipment compare and the longest growth choice it met (under _local/shots/).
var view: Node
var frame := 0
var until_tick := 30000
var shots_dir := ""
var next_probe := 600
var step := 0
var wait_until := 0
var queue: Array = []
var probes: Array = []
var bad := 0
var worst_equip := {"lines":-1}
var worst_boon := {"lines":-1}
var saved_boon_lines := -1
var saved_equip_lines := -1

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--until="): until_tick = int(arg.trim_prefix("--until="))
		elif arg.begins_with("--shots="): shots_dir = arg.trim_prefix("--shots=")
	if not "--chapter1-profile-off" in OS.get_cmdline_user_args():
		print("MODAL_FIT_ARGS ",JSON.stringify({"error":"--chapter1-profile-off is required"}))
		quit(2)
		return
	if not shots_dir.is_empty():
		var global := ProjectSettings.globalize_path(shots_dir if shots_dir.begins_with("res://") else "res://"+shots_dir).replace("\\","/")+"/"
		if not "/_local/shots/" in global:
			print("MODAL_FIT_ARGS ",JSON.stringify({"error":"--shots must be under _local/shots/"}))
			quit(2)
			return
		DirAccess.make_dir_recursive_absolute(global)
	view = (load("res://chapter1/ChapterOne.tscn") as PackedScene).instantiate()
	root.add_child(view)

func _find_button(node: Node, prefixes: Array) -> Button:
	if node is Button:
		for p in prefixes:
			if String(node.text).begins_with(p): return node
	for child in node.get_children():
		var found := _find_button(child,prefixes)
		if found != null: return found
	return null

func _scroll_above(node: Node) -> ScrollContainer:
	var cursor := node.get_parent()
	while cursor != null:
		if cursor is ScrollContainer: return cursor
		cursor = cursor.get_parent()
	return null

func _delta_lines(node: Node) -> int:
	if node is Label and String(node.text) == "현재 장비에서 변화":
		var sibling := node.get_parent().get_child(1) as Label
		return String(sibling.text).split("\n").size()
	for child in node.get_children():
		var n := _delta_lines(child)
		if n >= 0: return n
	return -1

func _canvas() -> Rect2:
	return root.get_visible_rect()

func _measure_equipment(uid: int) -> Dictionary:
	var hud = view.hud
	var button := _find_button(hud.modal,["이 장비 장착","장착 중","레벨 부족"])
	var out := {"kind":"equipment","tick":view.run.tick,"uid":uid,"found":button != null}
	if button == null: return out
	var rect := button.get_global_rect()
	var scroll := _scroll_above(button)
	var modal_rect: Rect2 = hud.modal.get_global_rect()
	out.lines = maxi(_delta_lines(hud.modal),0)
	out.button = [snappedf(rect.position.x,.1),snappedf(rect.position.y,.1),snappedf(rect.size.x,.1),snappedf(rect.size.y,.1)]
	out.in_scroll = scroll != null
	var clip := _canvas()
	if scroll != null: clip = clip.intersection(scroll.get_global_rect())
	# Fully visible: the whole button lies inside the area that is drawn (the canvas, or the scroll port when it sits in one).
	out.visible = clip.encloses(rect.grow(-1)) and modal_rect.encloses(rect.grow(-1))
	out.window_inside = _canvas().encloses(modal_rect)
	out.pass_ = bool(out.visible) and bool(out.window_inside)
	return out

func _in_card(node: Node, stop: Node) -> bool:
	var cursor := node.get_parent()
	while cursor != null and cursor != stop:
		if cursor is PanelContainer: return true
		cursor = cursor.get_parent()
	return false

func _measure_boon() -> Dictionary:
	# the grace screen (A8 G6) is a fixed 1600 x 900 composition: every card must lie inside the canvas
	var screen = view.hud._grace_screen
	var out := {"kind":"boon","tick":view.run.tick,"found":screen != null}
	if screen == null: return out
	var inside := true
	for card in screen.card_nodes:
		if not _canvas().encloses((card as Control).get_global_rect().grow(-1)): inside = false
	out.buttons_inside = inside
	out.window_inside = _canvas().encloses(screen.get_global_rect())
	out.pass_ = inside and bool(out.window_inside)
	return out

func _shot(name_: String) -> void:
	if shots_dir.is_empty(): return
	var image := root.get_viewport().get_texture().get_image()
	if image != null: image.save_png((shots_dir if shots_dir.begins_with("res://") else "res://"+shots_dir).path_join(name_+".png"))

func _record(m: Dictionary) -> void:
	probes.append(m)
	if not bool(m.get("pass_",true)): bad += 1
	print("MODAL_FIT ",JSON.stringify(m))

func _process(_delta: float) -> bool:
	if view == null or not view.is_inside_tree(): return true
	frame += 1
	var run: RefCounted = view.run
	match step:
		0:
			if frame == 5: view.start_run("chapter1.skill.frost"); step = 1
		1:
			# Growth choice: park the pilot, let the HUD build the cards, measure, release.
			if run.mode == "choice":
				view._pilot = false
				wait_until = frame+8
				step = 2
			elif run.mode == "playing" and run.tick >= next_probe and not run.inventory.is_empty():
				next_probe = run.tick+900
				queue.clear()
				for item in run.inventory: queue.append(int(item.uid))
				view.open_equipment()
				step = 3
				wait_until = frame+4
		2:
			if frame >= wait_until:
				var m := _measure_boon()
				_record(m)
				if int(m.get("lines",0)) > saved_boon_lines:
					saved_boon_lines = int(m.lines); _shot("boon-longest")
				view._pilot = true
				step = 1
		3:
			if frame >= wait_until:
				if queue.is_empty():
					view.close_equipment(); step = 1
				else:
					var uid: int = queue.pop_back()
					view.hud._selected_item = uid
					view.hud.invalidate()
					step = 4
					wait_until = frame+4
		4:
			if frame >= wait_until:
				var uid2: int = view.hud._selected_item
				var m2 := _measure_equipment(uid2)
				_record(m2)
				if int(m2.get("lines",0)) > saved_equip_lines:
					saved_equip_lines = int(m2.lines); _shot("equipment-longest")
				step = 3
				wait_until = frame+1
	if (run.tick >= until_tick or run.mode in ["victory","defeat"]) and step in [1]:
		_finish()
		return true
	if frame > 400000:
		_finish(); return true
	return false

func _finish() -> void:
	var equip := 0
	var boon := 0
	var max_equip_lines := 0
	var max_boon_lines := 0
	for m in probes:
		if m.kind == "equipment": equip += 1; max_equip_lines = maxi(max_equip_lines,int(m.get("lines",0)))
		else: boon += 1; max_boon_lines = maxi(max_boon_lines,int(m.get("lines",0)))
	print("MODAL_FIT_RESULT ",JSON.stringify({"equipment_probes":equip,"boon_probes":boon,"max_delta_lines":max_equip_lines,"max_card_lines":max_boon_lines,"failed":bad,"final_tick":view.run.tick,"window":[root.size.x,root.size.y],"canvas":[_canvas().size.x,_canvas().size.y]}))
	quit(1 if bad > 0 else 0)
