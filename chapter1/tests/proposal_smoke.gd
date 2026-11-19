extends SceneTree
## Headless smoke test of the screen proposals: builds every fixture, plays the intro, moves the focus, confirms, re-pulls, and
## prints SCRIPT ERRORs (nothing is drawn: this only proves the code runs). Does not replace looking at the captures.
##   python tools/dev/godot.py --headless --path . --script res://chapter1/tests/proposal_smoke.gd -- --proposals=growth_choice/slot_fated,growth_choice/c_two_beat
const Kit = preload("res://chapter1/tests/proposals/growth_choice/kit.gd")
const FIXTURE_DIR := "res://chapter1/tests/fixtures/ui/"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var names: Array = ["growth_choice/slot_fated", "growth_choice/c_two_beat", "growth_choice/b_seal", "growth_choice/a_oath"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--proposals="): names = arg.trim_prefix("--proposals=").split(",")
	var failures := 0
	var ran := 0
	for name_ in names:
		var script: GDScript = load("res://chapter1/tests/proposals/%s.gd" % name_)
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
