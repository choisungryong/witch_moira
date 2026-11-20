extends SceneTree
## Real-time frame interval recorder for the ChapterOne scene (QA tool, no gameplay writes).
## Run inside the dev stage with a real renderer, never with --fixed-fps:
##
##   godot --path <stage> --resolution 1920x1080 --script res://chapter1/tests/frame_probe.gd -- \
##       --chapter1-start --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus \
##       --chapter1-seed=11 [--chapter1-no-juice] --probe-seconds=190 --probe-out=<file.json> [--probe-vsync=on]
##
## Vsync is switched off unless --probe-vsync=on. Intervals are Time.get_ticks_usec deltas between
## _process callbacks; clock starts at the first frame in mode "playing". Finished runs are retried
## (seed+1) so the sampled window stays inside combat.
var view: Node
var out_path := ""
var seconds := 190.0
var vsync_on := false
var no_glow := false
var env_overrides := ""
var scale3d := 0.0
var started_us := -1
var last_us := -1
var t_us := PackedInt64Array()
var dt_us := PackedInt64Array()
var spells_pick := false ## A9: --probe-spells-pick takes growth cards with tests/spells_pick.gd (ring unlock first) so the fence is really on
var modes := PackedStringArray()
var ring_on := PackedInt32Array() ## A9: 1 when the ring spell is owned and drawn on that frame (the fence only exists with --chapter1-trial=spells)
var ticks := PackedInt32Array()
var enemies := PackedInt32Array()
var draw_calls := PackedInt32Array()
var proc_ms := PackedFloat32Array()
var restarts := 0
var unfocused := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-out="): out_path = arg.trim_prefix("--probe-out=")
		elif arg.begins_with("--probe-seconds="): seconds = float(arg.trim_prefix("--probe-seconds="))
		elif arg == "--probe-vsync=on": vsync_on = true
		elif arg == "--probe-spells-pick": spells_pick = true
		elif arg == "--probe-no-glow": no_glow = true
		elif arg.begins_with("--probe-env="): env_overrides = arg.trim_prefix("--probe-env=")
		elif arg.begins_with("--probe-scale3d="): scale3d = float(arg.trim_prefix("--probe-scale3d="))
	OS.delta_smoothing = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_on else DisplayServer.VSYNC_DISABLED)
	var scene: PackedScene = load("res://chapter1/ChapterOne.tscn")
	view = scene.instantiate()
	if view.get_script() == null or view.get("run") == null:
		push_error("ChapterOne failed to load its script")
		quit(3)
		return
	root.add_child(view)
	if no_glow:
		var env := _find_env(view)
		if env != null and env.environment != null:
			env.environment.glow_enabled = false
			env.environment.adjustment_enabled = false
	# Ablation: "--probe-env=glow_enabled=false;adjustment_enabled=false" sets Environment properties
	# after the view built its look (values parsed with str_to_var). "--probe-scale3d=0.8333" sets
	# the root viewport 3D render scale.
	if env_overrides != "":
		var env2 := _find_env(view)
		if env2 != null and env2.environment != null:
			for pair in env_overrides.split(";", false):
				var kv := pair.split("=", false)
				if kv.size() == 2: env2.environment.set(kv[0], str_to_var(kv[1]))
	if scale3d > 0.0: root.scaling_3d_scale = scale3d

func _find_env(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment: return node
	for child in node.get_children():
		var found := _find_env(child)
		if found != null: return found
	return null

func _process(_delta: float) -> bool:
	if view == null or not view.is_inside_tree(): return true
	var run: RefCounted = view.run
	if spells_pick and run.mode == "choice": preload("res://chapter1/tests/spells_pick.gd").pick(run,"frame_probe")
	var now := Time.get_ticks_usec()
	if started_us < 0:
		if run.mode != "playing": return false
		started_us = now
	if last_us >= 0:
		t_us.append(now-started_us); dt_us.append(now-last_us)
		modes.append(run.mode); ticks.append(run.tick); enemies.append(run.enemies.size())
		var ring_fx: Variant = view.effects.get("_ring_fx") if view.get("effects") != null else null
		ring_on.append(1 if ring_fx != null and String(ring_fx.ring_id) != "" else 0)
		draw_calls.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		proc_ms.append(float(Performance.get_monitor(Performance.TIME_PROCESS))*1000.0)
		if not root.has_focus(): unfocused += 1
	last_us = now
	if run.mode in ["victory","defeat"]:
		restarts += 1
		view.retry()
	if now-started_us >= int(seconds*1000000.0):
		_finish()
		return true
	return false

func _finish() -> void:
	var info := {
		"seconds_requested": seconds, "frames": dt_us.size(), "restarts": restarts, "unfocused_frames": unfocused,
		"window_size": [root.size.x, root.size.y], "window_mode": DisplayServer.window_get_mode(),
		"content_scale_size": [root.content_scale_size.x, root.content_scale_size.y],
		"render_size": [view.get_viewport().get_texture().get_width(), view.get_viewport().get_texture().get_height()],
		"vsync_mode": DisplayServer.window_get_vsync_mode(), "vsync_requested_on": vsync_on, "max_fps": Engine.max_fps,
		"delta_smoothing": OS.delta_smoothing, "gpu": RenderingServer.get_video_adapter_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(),
		"display_server": DisplayServer.get_name(), "user_args": Array(OS.get_cmdline_user_args()), "engine_args": Array(OS.get_cmdline_args()),
		"no_glow": no_glow, "env_overrides": env_overrides, "scale3d": scale3d, "msaa_3d": root.msaa_3d, "juice_present": view.get("juice") != null, "engine": Engine.get_version_info().string,
		"final_mode": view.run.mode, "final_tick": view.run.tick, "kills": view.run.kills,
	}
	var data := {"info": info, "t_us": Array(t_us), "dt_us": Array(dt_us), "modes": Array(modes), "ticks": Array(ticks),
		"enemies": Array(enemies), "ring_on": Array(ring_on), "draw_calls": Array(draw_calls), "proc_ms": Array(proc_ms)}
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write "+out_path)
	else:
		file.store_string(JSON.stringify(data)); file.close()
	print("FRAME_PROBE_RESULT ", JSON.stringify(info))
	view.queue_free()
	quit(0)
