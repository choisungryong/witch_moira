extends SceneTree
## Frame and tick timing probe for exported builds and the editor (QA tool, never product code).
## Driven by tools/dev/perf_ab.py; the JSON it writes is read by the same tool. It replays ChapterOne's
## _physics_process/_process by hand so every tick and every presenter call can be timed, and it never writes game state.
##
##   <exe | godot --path <folder>> --resolution 1920x1080 --script <this file> -- --chapter1-start --chapter1-pilot
##       --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --chapter1-primary=chapter1.skill.ember
##       --probe-seconds=300 --probe-out=<file.json> [--x-<switch>[=value] ...]
##
## chapter1/tests/ is left out of the exported pack, so an exe is given this file by absolute path
## (perf_ab.py does that). It loads perf_probe_mark.gd from the folder it sits in.
## Fields of the JSON that perf_ab.py reads: info{...}, f_* (per frame, microseconds) and k_* (per tick).
## Experiment switches --x-<name>[=value] (all default off; they change what is drawn, so a run that uses one is not a
## measurement of the shipped game): no-world no-light no-env no-hud no-particles audio-pause no-hero no-physics no-3d
## pool-detach hide=<TopLevelName+Name2> ticks-after spin-us=<us> dump-at=<sec> no-fx-sync no-juice-sync no-hud-sync
## no-world-sync scan-only marks delay-start prewarm bar-hidden no-fxnodes.
## Product hooks it relies on (all optional except the first group): view.run/world/actors/effects/hud/audio and
## view._pilot_input/_move_input/_consume_events/start_run/_audio_*; optional: view.juice, actors.t2/T2_NAMES (per-section
## counters, not in the product), actors._pool25_root/pool25_created. Missing optional hooks are skipped.
var view: Node
var out_path := ""
var seconds := 420.0
var started_us := -1
var last_us := -1
var xs: Dictionary = {}
var k_tick := PackedInt32Array(); var k_pilot := PackedInt32Array(); var k_step := PackedInt32Array(); var k_cons := PackedInt32Array(); var k_audio := PackedInt32Array()
var k_enemies := PackedInt32Array(); var k_t := PackedInt64Array()
var f_t := PackedInt64Array(); var f_dt := PackedInt64Array(); var f_nticks := PackedInt32Array(); var f_tick := PackedInt32Array()
var f_phys := PackedInt32Array(); var f_cam := PackedInt32Array(); var f_act := PackedInt32Array(); var f_fx := PackedInt32Array()
var f_juice := PackedInt32Array(); var f_hud := PackedInt32Array(); var f_world := PackedInt32Array(); var f_x := PackedInt32Array()
var f_proc := PackedFloat32Array(); var f_pproc := PackedFloat32Array(); var f_draw := PackedInt32Array(); var f_en := PackedInt32Array()
var f_rcpu := PackedFloat32Array(); var f_rgpu := PackedFloat32Array(); var f_rsetup := PackedFloat32Array()
var f_objs := PackedInt32Array(); var f_prims := PackedInt32Array()
var f_pipe := PackedInt32Array(); var f_nodes := PackedInt32Array(); var f_res := PackedInt32Array(); var f_obj := PackedInt32Array()
var f_pool := PackedInt32Array()
var f_gap := PackedInt32Array(); var f_drawus := PackedInt32Array(); var f_head := PackedInt32Array(); var f_ours := PackedInt32Array()
var ts_pre := 0
var ts_pf := 0
var m_early: Node
var menu_frames := 0
var focus_samples: Array = []
var start_run_us := -1
var start_run_pipe := [0, 0]
var menu_last_us := -1
var menu_dts: Array = []
var menu_started := false
var prewarm_done := false
var m_late: Node
var f_pf := PackedInt32Array(); var f_early := PackedInt32Array(); var f_late := PackedInt32Array(); var f_prd := PackedInt32Array()
var ts_post := 0
var ts_proc_end := 0
var ts_proc_start := 0
var have_ts := false
var f_mode := PackedStringArray()
var t2_names: Array = []
var t2_cols: Array = []
var snap := PackedInt64Array()
var ticks_this_frame := 0
var phys_us_this_frame := 0
var frame_no := 0
var rid: RID
var vsync_start := -1
var vsync_mid := -1
var x_pending := 0
var x_applied := false
var x_scan_us := 0
var x_spin_us := 0
var x_dump_at := -1.0
var x_dumped := false
var x_dumps: Array = []
var x_env: Dictionary = {}
var x_pool_detached := false
var x_has_physics_off := false
var x_markers: Array = []
var pipe_first := -1
const CLASSES := ["Node3D", "MeshInstance3D", "MultiMeshInstance3D", "Skeleton3D", "AnimationPlayer", "Light3D", "GPUParticles3D", "CPUParticles3D", "CollisionObject3D", "AudioStreamPlayer", "AudioStreamPlayer3D", "Control", "CanvasLayer", "Label3D", "Sprite3D", "Timer", "Camera3D", "WorldEnvironment", "SubViewport", "Decal", "GeometryInstance3D", "VisualInstance3D"]

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-out="): out_path = arg.trim_prefix("--probe-out=")
		elif arg.begins_with("--probe-seconds="): seconds = float(arg.trim_prefix("--probe-seconds="))
		elif arg.begins_with("--x-"):
			var kv := arg.trim_prefix("--x-").split("=", true, 1)
			xs[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if xs.has("dump-at"): x_dump_at = float(xs["dump-at"])
	if xs.has("spin-us"): x_spin_us = int(xs["spin-us"])
	OS.delta_smoothing = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	rid = root.get_viewport_rid()
	process_frame.connect(func(): ts_pf = Time.get_ticks_usec())
	RenderingServer.frame_pre_draw.connect(func(): ts_pre = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func(): ts_post = Time.get_ticks_usec())
	RenderingServer.viewport_set_measure_render_time(rid, true)
	vsync_start = DisplayServer.window_get_vsync_mode()
	var scene: PackedScene = load("res://chapter1/ChapterOne.tscn")
	view = scene.instantiate()
	root.add_child(view)
	view.set_physics_process(false)
	view.set_process(false)
	if xs.has("marks"):
		var mk = load(get_script().resource_path.get_base_dir().path_join("perf_probe_mark.gd"))
		m_early = Node.new(); m_early.set_script(mk); m_early.process_priority = -1000000; root.add_child(m_early)
		m_late = Node.new(); m_late.set_script(mk); m_late.process_priority = 1000000; root.add_child(m_late)
	var a = view.get("actors")
	if a != null and a.get("t2") != null:
		t2_names = Array(a.get_script().get_script_constant_map()["T2_NAMES"])
		for i in t2_names.size(): t2_cols.append(PackedInt32Array())
		snap.resize(t2_names.size())

func _us() -> int: return Time.get_ticks_usec()

func _do_tick() -> void:
	var run = view.run
	var a := _us()
	var movement: Vector2 = view._pilot_input() if view._pilot else view._move_input()
	var b := _us()
	run.step(movement)
	var c := _us()
	view._consume_events()
	var d := _us()
	if run.mode == "playing":
		view._audio_step_distance += run.hero.position.distance_to(view._audio_previous)
		if view._audio_step_distance > 1.15:
			view.audio.play("step", run.tick); view._audio_step_distance = 0
	view._audio_previous = run.hero.position
	var e := _us()
	if started_us >= 0:
		k_tick.append(run.tick); k_pilot.append(b-a); k_step.append(c-b); k_cons.append(d-c); k_audio.append(e-d); k_enemies.append(run.enemies.size()); k_t.append(a-started_us)
	phys_us_this_frame += e-a

func _physics_process(_delta: float) -> bool:
	if view == null or not view.is_inside_tree(): return false
	if view.is_physics_processing(): view.set_physics_process(false)
	var run = view.run
	if view._qa_quit_sent or run.mode == "menu": return false
	ticks_this_frame += 1
	if xs.has("ticks-after"):
		x_pending += 1
		return false
	_do_tick()
	return false

# ---------------- experiment helpers ----------------
func _count_tree(node: Node, acc: Dictionary) -> void:
	acc["nodes"] += 1
	if node.is_processing() or node.is_physics_processing(): acc["proc"] += 1
	if node.is_processing_internal() or node.is_physics_processing_internal(): acc["proc_int"] += 1
	if node is Node3D and not (node as Node3D).visible: acc["hidden3d"] += 1
	for cls in CLASSES:
		if node.is_class(cls): acc[cls] = int(acc.get(cls, 0)) + 1
	for c in node.get_children(): _count_tree(c, acc)

func _new_acc() -> Dictionary:
	return {"nodes": 0, "proc": 0, "proc_int": 0, "hidden3d": 0}

func _tree_report() -> Dictionary:
	var rep := {"viewport_children": [], "totals": {}, "view_children": {}}
	var tot := _new_acc()
	for c in root.get_children(): _count_tree(c, tot)
	rep["totals"] = tot
	var groups := {}
	for c in view.get_children():
		var nm := String(c.name)
		var key := nm if not nm.begins_with("@") else "@anon:" + c.get_class()
		if not groups.has(key): groups[key] = {"count": 0, "acc": _new_acc(), "class": c.get_class(), "visible": (c.visible if "visible" in c else null)}
		groups[key]["count"] += 1
		_count_tree(c, groups[key]["acc"])
	rep["view_children"] = groups
	for c in root.get_children():
		rep["viewport_children"].append({"name": String(c.name), "class": c.get_class()})
	var mon := {}
	for pair in [["OBJECT_COUNT", Performance.OBJECT_COUNT], ["OBJECT_NODE_COUNT", Performance.OBJECT_NODE_COUNT], ["OBJECT_RESOURCE_COUNT", Performance.OBJECT_RESOURCE_COUNT], ["OBJECT_ORPHAN_NODE_COUNT", Performance.OBJECT_ORPHAN_NODE_COUNT],
			["RENDER_TOTAL_OBJECTS", Performance.RENDER_TOTAL_OBJECTS_IN_FRAME], ["RENDER_TOTAL_PRIMS", Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME], ["RENDER_TOTAL_DRAW", Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME],
			["RENDER_VIDEO_MEM", Performance.RENDER_VIDEO_MEM_USED], ["RENDER_TEXTURE_MEM", Performance.RENDER_TEXTURE_MEM_USED], ["RENDER_BUFFER_MEM", Performance.RENDER_BUFFER_MEM_USED],
			["PHYS3D_ACTIVE", Performance.PHYSICS_3D_ACTIVE_OBJECTS], ["PHYS3D_PAIRS", Performance.PHYSICS_3D_COLLISION_PAIRS], ["PHYS3D_ISLANDS", Performance.PHYSICS_3D_ISLAND_COUNT],
			["AUDIO_LATENCY", Performance.AUDIO_OUTPUT_LATENCY], ["MEM_STATIC", Performance.MEMORY_STATIC], ["TIME_PROCESS", Performance.TIME_PROCESS], ["TIME_PHYSICS", Performance.TIME_PHYSICS_PROCESS], ["TIME_NAV", Performance.TIME_NAVIGATION_PROCESS]]:
		mon[pair[0]] = Performance.get_monitor(pair[1])
	rep["monitors"] = mon
	return rep

func _env_report() -> Dictionary:
	var out := {}
	for c in view.get_children():
		if c is WorldEnvironment:
			var e: Environment = c.environment
			if e != null:
				out["env"] = {"bg": e.background_mode, "glow": e.glow_enabled, "fog": e.fog_enabled, "vfog": e.volumetric_fog_enabled, "ssao": e.ssao_enabled, "ssil": e.ssil_enabled, "sdfgi": e.sdfgi_enabled, "adjust": e.adjustment_enabled, "tonemap": e.tonemap_mode, "ssr": e.ssr_enabled}
			out["camera_attributes"] = (c.camera_attributes != null)
	var cam: Camera3D = view.world.camera
	if cam != null:
		out["camera"] = {"proj": cam.projection, "size": cam.size, "near": cam.near, "far": cam.far, "attributes": cam.attributes != null}
	out["msaa"] = root.msaa_3d; out["scale3d"] = root.scaling_3d_scale; out["taa"] = root.use_taa; out["fxaa"] = root.screen_space_aa; out["scaling_mode"] = root.scaling_3d_mode
	out["lights"] = []
	var stack: Array = [view]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Light3D:
			out["lights"].append({"name": String(n.name), "cls": n.get_class(), "shadow": n.shadow_enabled, "energy": n.light_energy, "parent": String(n.get_parent().name)})
		for c in n.get_children(): stack.append(c)
	return out

func _apply_static() -> void:
	x_applied = true
	x_env = _env_report()
	if xs.has("no-3d"): root.disable_3d = true
	if xs.has("no-world") and view.world.root != null: view.world.root.visible = false
	if xs.has("no-physics"):
		PhysicsServer3D.set_active(false); x_has_physics_off = true
	if xs.has("no-env"):
		for c in view.get_children():
			if c is WorldEnvironment and c.environment != null:
				var e: Environment = c.environment
				e.glow_enabled = false; e.fog_enabled = false; e.volumetric_fog_enabled = false; e.ssao_enabled = false; e.ssil_enabled = false
				e.sdfgi_enabled = false; e.adjustment_enabled = false; e.ssr_enabled = false
				c.camera_attributes = null
		if view.world.camera != null: view.world.camera.attributes = null
	if xs.has("hide"):
		var names: PackedStringArray = String(xs["hide"]).split("+")
		for c in view.get_children():
			if String(c.name) in names and "visible" in c: c.visible = false
		for c in root.get_children():
			if String(c.name) in names and "visible" in c: c.visible = false
	if xs.has("no-fxnodes"):
		for c in view.get_children():
			if c is MultiMeshInstance3D or c is MeshInstance3D or String(c.name) in ["CombatJuice", "GroundNameLeaders26"]: c.visible = false
	if xs.has("pool-detach"):
		var pr = view.actors.get("_pool25_root")
		if pr != null and pr.get_parent() != null:
			pr.get_parent().remove_child(pr); x_pool_detached = true

func _scan_node(n: Node) -> void:
	if n is Light3D and xs.has("no-light"): n.visible = false
	elif (n is GPUParticles3D or n is CPUParticles3D) and xs.has("no-particles"):
		n.visible = false
	elif n is CanvasLayer and xs.has("no-hud"): n.visible = false
	elif n is AudioStreamPlayer or n is AudioStreamPlayer3D:
		if xs.has("audio-pause"): n.stream_paused = true
	for c in n.get_children(): _scan_node(c)

func _periodic() -> void:
	var t := _us()
	if xs.has("no-light") or xs.has("no-particles") or xs.has("no-hud") or xs.has("audio-pause") or xs.has("scan-only"):
		_scan_node(view)
		for c in root.get_children():
			if c != view: _scan_node(c)
	if xs.has("no-hero") and view.actors.hero != null: view.actors.hero.visible = false
	x_scan_us = _us() - t

func _process(delta: float) -> bool:
	if view == null or not view.is_inside_tree(): return true
	if view.is_processing(): view.set_process(false)
	var run = view.run
	var now := _us()
	if started_us < 0 and xs.has("delay-start") and run.mode == "menu":
		var mn := _us()
		if menu_last_us >= 0: menu_dts.append(float(mn - menu_last_us) / 1000.0)
		menu_last_us = mn
		menu_frames += 1
		var pr = view.actors.get("_pool25_root")
		if xs.has("prewarm") and pr != null:
			if menu_frames == 20: pr.visible = true
			elif menu_frames == 24: pr.visible = false; prewarm_done = true
		if menu_frames >= 120 and not menu_started:
			menu_started = true
			var sr0 := _us()
			start_run_pipe[0] = _pipe_total()
			view.start_run(view.primary)
			start_run_us = _us() - sr0
			start_run_pipe[1] = _pipe_total()
		return false
	if started_us < 0:
		if run.mode != "playing": return false
		started_us = now
		vsync_mid = DisplayServer.window_get_vsync_mode()
		if not x_applied: _apply_static()
		pipe_first = _pipe_total()
	var x_t0 := _us()
	var xu := 0
	if frame_no % 60 == 0:
		_periodic(); xu += x_scan_us
	if x_dump_at >= 0.0 and not x_dumped and float(now - started_us) / 1e6 >= x_dump_at:
		x_dumped = true
		var t_d := _us()
		x_dumps.append({"at": float(now - started_us) / 1e6, "report": _tree_report()})
		xu += _us() - t_d
	if x_spin_us > 0 and ticks_this_frame > 0:
		var t_s := _us()
		while _us() - t_s < x_spin_us: pass
	var cam := 0; var act := 0; var fx := 0; var jc := 0; var hd := 0; var wd := 0
	var p0 := _us()
	var actors_ref = view.actors
	var have_t2: bool = t2_names.size() > 0
	if have_t2:
		for i in snap.size(): snap[i] = 0
	if not run.hero.is_empty():
		view.world.update_camera(run.hero.position, delta)
		var p1 := _us()
		actors_ref.sync(run, delta)
		var p2 := _us()
		if have_t2:
			var src: PackedInt64Array = actors_ref.t2
			for i in snap.size(): snap[i] = src[i]
			actors_ref.t2_reset()
		if not xs.has("no-fx-sync"): view.effects.sync(run, delta)
		var p3 := _us()
		if view.juice != null and not xs.has("no-juice-sync"): view.juice.sync(run, delta)
		var p4 := _us()
		cam = p1-p0; act = p2-p1; fx = p3-p2; jc = p4-p3
		p0 = p4
	if not xs.has("no-hud-sync"): view.hud.sync(run, delta)
	if xs.has("bar-hidden"):
		var cb = view.hud.get("combat_bar")
		if cb != null and is_instance_valid(cb): cb.visible = false
	var p5 := _us()
	hd = p5-p0
	view.audio.set_paused(run.mode != "playing" or xs.has("audio-pause"))
	var p6 := _us()
	if not xs.has("no-world-sync"): view.world.sync(run, delta)
	var p7 := _us()
	wd = p7-p6
	var nt_report := ticks_this_frame
	if xs.has("ticks-after") and x_pending > 0:
		# the ticks that the engine ran before _process in the normal replay run here, after all presentation
		for i in x_pending:
			if view._qa_quit_sent or run.mode == "menu": break
			_do_tick()
		x_pending = 0
	if last_us >= 0:
		f_t.append(now-started_us); f_dt.append(now-last_us); f_nticks.append(nt_report); f_tick.append(run.tick)
		f_phys.append(phys_us_this_frame); f_cam.append(cam); f_act.append(act); f_fx.append(fx); f_juice.append(jc); f_hud.append(hd); f_world.append(wd)
		f_x.append(xu)
		if have_ts and ts_pre >= ts_proc_end and ts_post >= ts_pre:
			f_gap.append(ts_pre - ts_proc_end); f_drawus.append(ts_post - ts_pre); f_head.append(now - ts_post - phys_us_this_frame); f_ours.append(ts_proc_end - ts_proc_start)
		else:
			f_gap.append(-1); f_drawus.append(-1); f_head.append(-1); f_ours.append(-1)
		if m_early != null and ts_pf >= ts_proc_end and m_early.stamp >= ts_pf and m_late.stamp >= m_early.stamp and ts_pre >= m_late.stamp:
			f_pf.append(ts_pf - ts_proc_end); f_early.append(m_early.stamp - ts_pf); f_late.append(m_late.stamp - m_early.stamp); f_prd.append(ts_pre - m_late.stamp)
		else:
			f_pf.append(-1); f_early.append(-1); f_late.append(-1); f_prd.append(-1)
		f_proc.append(float(Performance.get_monitor(Performance.TIME_PROCESS))*1000.0)
		f_pproc.append(float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))*1000.0)
		f_draw.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		f_objs.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
		f_prims.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		f_rcpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
		f_rgpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		f_rsetup.append(RenderingServer.get_frame_setup_time_cpu())
		f_pipe.append(_pipe_total())
		f_nodes.append(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		f_res.append(int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)))
		f_obj.append(int(Performance.get_monitor(Performance.OBJECT_COUNT)))
		f_en.append(run.enemies.size()); f_mode.append(run.mode)
		var pool_created = actors_ref.get("pool25_created")
		f_pool.append(int(pool_created) if pool_created != null else 0)
		if have_t2:
			for i in snap.size(): t2_cols[i].append(int(snap[i]))
		if frame_no % 240 == 0: focus_samples.append(1 if root.has_focus() else 0)
		frame_no += 1
	ticks_this_frame = 0; phys_us_this_frame = 0
	last_us = now
	ts_proc_start = now; ts_proc_end = _us(); have_ts = true
	if run.mode in ["victory", "defeat"]:
		_finish(); return true
	if now-started_us >= int(seconds*1000000.0):
		_finish(); return true
	return false

func _pipe_total() -> int:
	var s := 0
	for k in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		s += int(RenderingServer.get_rendering_info(k))
	return s

func _finish() -> void:
	var info := {"seconds": seconds, "frames": f_dt.size(), "ticks": k_tick.size(), "focus": root.has_focus(),
		"final_mode": view.run.mode, "final_tick": view.run.tick, "juice_present": view.get("juice") != null,
		"display_server": DisplayServer.get_name(), "user_args": Array(OS.get_cmdline_user_args()), "gpu": RenderingServer.get_video_adapter_name(),
		"window_size": [root.size.x, root.size.y], "display_window_size": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"screen_size": [DisplayServer.screen_get_size().x, DisplayServer.screen_get_size().y], "window_mode": DisplayServer.window_get_mode(),
		"vsync_mode_at_init": vsync_start, "vsync_mode_at_start": vsync_mid, "vsync_mode_at_end": DisplayServer.window_get_vsync_mode(), "vsync_mode_enum": {"disabled": 0, "enabled": 1, "adaptive": 2, "mailbox": 3},
		"max_fps": Engine.max_fps, "max_physics_steps": Engine.max_physics_steps_per_frame, "msaa_3d": root.msaa_3d, "scaling_3d_scale": root.scaling_3d_scale,
		"rendering_method": RenderingServer.get_current_rendering_method(), "t2_present": t2_names.size() > 0, "x_env": x_env, "x_switches": xs, "x_pool_detached": x_pool_detached, "menu_dts": menu_dts, "menu_frames": menu_frames, "focus_samples": focus_samples, "start_run_us": start_run_us, "start_run_pipe": start_run_pipe, "prewarm_done": prewarm_done,
		"debug_build": OS.is_debug_build(), "has_qa": OS.has_feature("qa"), "pipe_first": pipe_first,
		"godot": Engine.get_version_info().get("string", ""), "x_final_tree": _tree_report()}
	var data := {"info": info, "x_dumps": x_dumps, "k_tick": Array(k_tick), "k_pilot": Array(k_pilot), "k_step": Array(k_step), "k_cons": Array(k_cons), "k_audio": Array(k_audio), "k_enemies": Array(k_enemies), "k_t": Array(k_t),
		"f_t": Array(f_t), "f_dt": Array(f_dt), "f_nticks": Array(f_nticks), "f_tick": Array(f_tick), "f_phys": Array(f_phys), "f_cam": Array(f_cam), "f_act": Array(f_act),
		"f_fx": Array(f_fx), "f_juice": Array(f_juice), "f_hud": Array(f_hud), "f_world": Array(f_world), "f_x": Array(f_x), "f_proc": Array(f_proc), "f_pproc": Array(f_pproc),
		"f_draw": Array(f_draw), "f_en": Array(f_en), "f_mode": Array(f_mode),
		"f_objs": Array(f_objs), "f_prims": Array(f_prims), "f_rcpu": Array(f_rcpu), "f_rgpu": Array(f_rgpu), "f_rsetup": Array(f_rsetup),
		"f_pipe": Array(f_pipe), "f_nodes": Array(f_nodes), "f_res": Array(f_res), "f_obj": Array(f_obj), "f_pool": Array(f_pool), "f_gap": Array(f_gap), "f_drawus": Array(f_drawus), "f_head": Array(f_head), "f_ours": Array(f_ours), "f_pf": Array(f_pf), "f_early": Array(f_early), "f_late": Array(f_late), "f_prd": Array(f_prd), "t2_names": t2_names}
	var cols := {}
	for i in t2_names.size(): cols[t2_names[i]] = Array(t2_cols[i])
	data["t2"] = cols
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null: push_error("cannot write "+out_path)
	else: file.store_string(JSON.stringify(data)); file.close()
	print("X_PROBE_RESULT ", JSON.stringify(info))
	view.queue_free()
	quit(0)
