extends SceneTree
## Real-time frame interval while the growth-choice window is open (QA tool, no gameplay writes). The built-in pilot plays to the first choice, is parked,
## and 300 frames are timed after the first second (the intro of the grace screen is over by then). Needs a real renderer, never --fixed-fps:
##
##   python tools/dev/godot.py --resolution 1920x1080 --path . --script res://chapter1/tests/choice_frame_probe.gd -- --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --primary=chapter1.skill.frost
##
## Output: CHOICE_FRAME_PROBE {"frames":300,"mean_ms":..,"p50_ms":..,"p95_ms":..,"p99_ms":..,"max_ms":..}. Vsync is switched off. Run the same line on the tree before and after
## a change to the window and compare the numbers (one run is a sample; run it three times).
var view: Node
var frame := 0
var parked_at := -1
var last_us := -1
var dts: Array = []

func _initialize() -> void:
	if not "--chapter1-profile-off" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		print("CHOICE_FRAME_PROBE_ARGS ", JSON.stringify({"error": "needs --chapter1-profile-off and a real renderer"}))
		quit(2)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	view = (load("res://chapter1/ChapterOne.tscn") as PackedScene).instantiate()
	root.add_child(view)

func _process(_delta: float) -> bool:
	if view == null: return false
	frame += 1
	if parked_at < 0 and view.run.mode == "choice":
		view._pilot = false
		parked_at = frame
	if parked_at >= 0:
		var now := Time.get_ticks_usec()
		if last_us > 0 and frame - parked_at > 60: dts.append(float(now - last_us) / 1000.0)
		last_us = now
		if dts.size() >= 300:
			dts.sort()
			var sum := 0.0
			for v in dts: sum += float(v)
			print("CHOICE_FRAME_PROBE ", JSON.stringify({"frames": dts.size(), "mean_ms": snappedf(sum / dts.size(), 0.01), "p50_ms": snappedf(dts[dts.size() / 2], 0.01),
				"p95_ms": snappedf(dts[int(dts.size() * 0.95)], 0.01), "p99_ms": snappedf(dts[int(dts.size() * 0.99)], 0.01), "max_ms": snappedf(dts[dts.size() - 1], 0.01)}))
			quit(0)
			return true
	if frame > 20000:
		print("CHOICE_FRAME_PROBE ", JSON.stringify({"error": "no choice window reached"}))
		quit(1)
		return true
	return false
