extends SceneTree
## Headless smoke test of the screen proposals: builds every fixture, plays the intro, moves the focus, confirms, re-pulls, and
## prints SCRIPT ERRORs (nothing is drawn: this only proves the code runs). Does not replace looking at the captures.
##   python tools/dev/godot.py --headless --path . --script res://chapter1/tests/proposal_smoke.gd -- --proposals=growth_choice/slot_fated,growth_choice/c_two_beat
const Kit = preload("res://chapter1/tests/proposals/growth_choice/kit.gd")
const LayoutDump = preload("res://chapter1/tests/layout_dump.gd")
const Parts = preload("res://chapter1/tests/proposals/title/parts.gd")
const FIXTURE_DIR := "res://chapter1/tests/fixtures/ui/"
var dump_dir := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var names: Array = ["growth_choice/slot_fated", "growth_choice/c_two_beat", "growth_choice/b_seal", "growth_choice/a_oath"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--proposals="): names = arg.trim_prefix("--proposals=").split(",")
		elif arg.begins_with("--dump-dir="): dump_dir = arg.trim_prefix("--dump-dir=")
	var failures := 0
	var ran := 0
	for name_ in names:
		var script: GDScript = load("res://chapter1/tests/proposals/%s.gd" % name_)
		if String(name_).begins_with("title/"):
			var r: Dictionary = await _run_title(String(name_), script)
			ran += int(r.ran)
			failures += int(r.failures)
			continue
		for f in DirAccess.get_files_at(FIXTURE_DIR):
			if not f.begins_with("growth_choice.") or not f.ends_with(".json"): continue
			var is_slot := f.begins_with("growth_choice.slot_")
			if is_slot != name_.ends_with("slot_fated"): continue
			var contract := Kit.read_json(FIXTURE_DIR + f)
			var node: Control = script.make(contract)
			root.add_child(node)
			for i in 3: await process_frame
			node.play_intro()
			var guard := 0
			while node.state == "intro" and guard < 3000:
				await process_frame
				guard += 1
			if node.state != "ready":
				print("SMOKE_FAIL ", name_, " ", f, " state=", node.state)
				failures += 1
			node.set_focus(1)
			for i in 20: await process_frame
			node.set_focus(node.best_index())
			for i in 30: await process_frame
			guard = 0
			while node.clock < node.unlock_abs and guard < 3000:
				await process_frame
				guard += 1
			node.try_pick(node.best_index())
			guard = 0
			while not node.events.any(func(e): return e.e == "confirm_done") and guard < 3000:
				await process_frame
				guard += 1
			if node.state != "done":
				print("SMOKE_FAIL ", name_, " ", f, " after pick state=", node.state)
				failures += 1
			node.queue_free()
			await process_frame
			ran += 1
	print("PROPOSAL_SMOKE ", JSON.stringify({"ran": ran, "failures": failures}))
	quit(1 if failures > 0 else 0)

## Control dump in scene_shot's format (settled state), for tools/dev/hud_layout_check.py. Headless: layout only, nothing is drawn.
func _dump(name_: String, fixture_file: String, label: String) -> void:
	var rows: Array = []
	LayoutDump.describe(root, 0, rows, true)
	var stem := "%s.%s.%s" % [name_.get_slice("/", 1), fixture_file.trim_prefix("title_v0.").trim_suffix(".json"), label]
	var doc := {"order": [stem], "dumps": {stem: rows}, "meta": {"extra": true, "note": "title proposal, headless layout dump", "scene": name_, "variant": stem,
		"combat": false, "canvas": [root.get_visible_rect().size.x, root.get_visible_rect().size.y], "window": [root.size.x, root.size.y]}}
	DirAccess.make_dir_recursive_absolute(dump_dir)
	var f := FileAccess.open(dump_dir.path_join(stem + ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e

## Title proposals: time is stepped by hand (advance_to), so the run does not depend on the frame rate. Per fixture: intro, placement
## report (BRIEF 1.8 lines 3 and 4 on the settled geometry), focus moves, title -> select (c), confirm to the end, the same with
## motion 0, and the input rules (a key in the intro skips, Enter right after the skip is refused, Space does nothing).
func _run_title(name_: String, script: GDScript) -> Dictionary:
	var failures := 0
	var ran := 0
	var reports: Array = []
	for f in DirAccess.get_files_at(FIXTURE_DIR):
		if not f.begins_with("title_v0.") or not f.ends_with(".json"):
			continue
		for mode in ["full", "motion0", "input"]:
			var contract := Kit.read_json(FIXTURE_DIR + f)
			var node: Control = script.make(contract)
			if mode == "motion0":
				node.set_motion(0.0)
			root.add_child(node)
			for i in 3: await process_frame
			var t := 0.0
			node.advance_to(t)
			node.play_intro()
			if mode == "input":
				t += 0.3
				node.advance_to(t)
				node._unhandled_key_input(_key(KEY_ENTER))
				var skipped: bool = node.events.any(func(e): return e.e == "intro_skipped")
				t += 0.2
				node.advance_to(t)
				node._unhandled_key_input(_key(KEY_ENTER))
				var refused: bool = node.events.any(func(e): return e.e == "pick_rejected") or node.stage_target == "select"
				node._unhandled_key_input(_key(KEY_SPACE))
				var still_ready: bool = node.state == "ready"
				if not (skipped and refused and still_ready and node.state != "confirm"):
					print("SMOKE_FAIL ", name_, " ", f, " input rules skipped=", skipped, " refused=", refused, " state=", node.state)
					failures += 1
				node.queue_free()
				await process_frame
				ran += 1
				continue
			while node.state == "intro" and t < 6.0:
				t += 1.0 / 60.0
				node.advance_to(t)
			if node.state != "ready":
				print("SMOKE_FAIL ", name_, " ", f, " ", mode, " intro state=", node.state)
				failures += 1
			var rep: Dictionary = node.layout_report()
			if mode == "full" and dump_dir != "":
				for s in 30:
					t += 1.0 / 60.0
					node.advance_to(t)
				if name_.ends_with("/c"):
					_dump(name_, f, "title")
					node.send("title_start")
					for s in 45:
						t += 1.0 / 60.0
						node.advance_to(t)
				_dump(name_, f, "select")
			if mode == "full":
				reports.append({"fixture": f, "ok": rep.ok, "rows": rep.rows})
				# placement truth: where the portrait really puts the painting's face point, against the number the layout report uses
				var fi: int = node.focus_index
				var fig: Node2D = (node.portraits[fi] as Node2D).get("_fig")
				if fig != null:
					var got: Vector2 = fig.get_global_transform() * Parts.FACE[fi]
					var want: Vector2 = (node.settled_geometry(fi)[fi].face as Vector2) * Parts.K
					if got.distance_to(want) > 1.5:
						print("SMOKE_FAIL ", name_, " ", f, " face placement got=", got, " want=", want)
						failures += 1
			if not bool(rep.ok):
				print("SMOKE_FAIL ", name_, " ", f, " layout ", JSON.stringify(rep))
				failures += 1
			for k in 3:
				node.send("focus_next")
				for s in 40:
					t += 1.0 / 60.0
					node.advance_to(t)
					if s % 10 == 0:
						await process_frame
			if name_.ends_with("/c"):
				node.send("title_start")
				for s in 30:
					t += 1.0 / 60.0
					node.advance_to(t)
			node.set_focus(node.best_index())
			for s in 60:
				t += 1.0 / 60.0
				node.advance_to(t)
			if node.focus_index != node.best_index():
				print("SMOKE_FAIL ", name_, " ", f, " focus ", node.focus_index)
				failures += 1
			node.send("confirm")
			if node.state != "confirm":
				print("SMOKE_FAIL ", name_, " ", f, " ", mode, " confirm not accepted state=", node.state, " events=", JSON.stringify(node.events.slice(-4)))
				failures += 1
			var guard := 0
			while node.state == "confirm" and guard < 400:
				t += 1.0 / 60.0
				node.advance_to(t)
				guard += 1
				if guard % 5 == 0:
					await process_frame  # lets the deferred _draw of the effects run (nothing is drawn headless, but the code is)
			if node.state != "done":
				print("SMOKE_FAIL ", name_, " ", f, " ", mode, " confirm never ended state=", node.state)
				failures += 1
			node.queue_free()
			await process_frame
			ran += 1
	print("TITLE_LAYOUT ", name_, " ", JSON.stringify(reports.slice(0, 1)))
	return {"ran": ran, "failures": failures}
