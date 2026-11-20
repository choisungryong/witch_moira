extends SceneTree
## QA tool (never product code): frame times of the real ChapterOne scene while N extra fire projectiles are DRAWN.
## The fakes are appended to run.projectiles in _process (right before the view syncs the effects) and dropped by the core at its next step (expires 0). Real renderer, no --fixed-fps:
##
##   python tools/dev/godot.py --path . --resolution 1920x1080 --script res://chapter1/tests/fx_stress_probe.gd -- \
##       --chapter1-start --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 \
##       --primary=chapter1.skill.ember --probe-fire=384 [--probe-evolved] --probe-seconds=40 --probe-out=_local/perf/<f>.json
## Prints FX_STRESS {frames, p50, p95, p99, max (ms), enemies_mean, projectiles_drawn}. Frames of the first 8 s are dropped.
var view: Node
var fire_n := 384
var evolved := false
var seconds := 40.0
var out_path := ""
var started_us := -1
var last_us := -1
var dts: Array = []
var enemy_counts: Array = []
var injected := 0
var shot_path := ""   # --probe-shot=<png under _local/>: one viewport capture 12 s in (use small --probe-fire for a readable picture)
var spread := 9.0     # --probe-spread=<m> half-width of the scatter
var _rng := RandomNumberGenerator.new()

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-fire="): fire_n = int(arg.trim_prefix("--probe-fire="))
		elif arg == "--probe-evolved": evolved = true
		elif arg.begins_with("--probe-seconds="): seconds = float(arg.trim_prefix("--probe-seconds="))
		elif arg.begins_with("--probe-shot="): shot_path = arg.trim_prefix("--probe-shot=")
		elif arg.begins_with("--probe-spread="): spread = float(arg.trim_prefix("--probe-spread="))
		elif arg.begins_with("--probe-out="): out_path = arg.trim_prefix("--probe-out=")
	OS.delta_smoothing = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_rng.seed = 5
	view = (load("res://chapter1/ChapterOne.tscn") as PackedScene).instantiate()
	root.add_child(view)

func _process(_delta: float) -> bool:
	var run: RefCounted = view.run
	var now := Time.get_ticks_usec()
	if started_us < 0:
		if run.mode != "playing" or run.hero.is_empty(): return false
		started_us = now
	if last_us >= 0 and now-started_us > 8000000:
		dts.append(float(now-last_us)/1000.0); enemy_counts.append(run.enemies.size())
	last_us = now
	if shot_path != "" and now-started_us > 12000000:
		view.get_viewport().get_texture().get_image().save_png(shot_path); shot_path = ""
	if run.mode in ["victory","defeat"]: view.retry()
	if not run.hero.is_empty() and fire_n > 0:
		var list: Array[Dictionary] = run.projectiles.duplicate()
		var c: Vector2 = run.hero.position
		for i in fire_n:
			var a := _rng.randf()*TAU
			var d := Vector2(cos(a),sin(a))
			list.append({"position":c+Vector2(_rng.randf_range(-spread,spread),_rng.randf_range(-spread*.66,spread*.66)),"direction":d,"hostile":false,"child":false,
				"skill_id":"chapter1.skill.ember","expires":0,"previous":c,"radius":.25 if evolved else .12,"uid":1000000+i})
		run.projectiles = list
		injected = fire_n
	if now-started_us >= int(seconds*1000000.0):
		dts.sort()
		var n := dts.size()
		var em := 0.0
		for e in enemy_counts: em += float(e)
		var info := {"frames":n,"p50":dts[n/2],"p95":dts[int(n*.95)],"p99":dts[int(n*.99)],"max":dts[n-1],
			"enemies_mean":em/maxf(1.0,float(enemy_counts.size())),"projectiles_drawn":fire_n,"evolved":evolved,"final_tick":run.tick}
		print("FX_STRESS ",JSON.stringify(info))
		if out_path != "":
			var f := FileAccess.open(out_path,FileAccess.WRITE)
			if f != null: f.store_string(JSON.stringify(info)); f.close()
		view.queue_free()
		quit(0)
		return true
	return false
