extends "res://chapter1/tests/hud_dump.gd"
## Walk probe (T9 B1-b): the hero's new body, in the real game scene, while the pilot moves it. Per render frame it reads the hero's
## position, whether it is walking, the clip time, and the world position of both toe bones. Only runs of 1 s or more of continuous
## movement count. One line at the end:  HERO_MOTION_PROBE {json}
##   avg_speed_mps        mean displayed speed of the hero over those runs
##   rate_measured        motion rate: clip time gained / real (simulated frame) seconds, the game's own  r = v x L / stride
##   slip_rms_mps         stance slip: RMS of the toe's ground speed along the hero's heading, over stance frames
##   slip_rms_horiz_mps   the same with the whole horizontal speed (turns and sideways drift included)
##   stance_samples, runs, windows_used, segment_seconds (the pilot dithers at times: only straight 1 s windows count, see _windows)
## Stance = toe height within 3 cm of the lowest toe height seen in those runs (same rule as the manager's character screen, motion_math.py).
##
##   python tools/dev/godot.py --headless --fixed-fps 60 --path . --script res://chapter1/tests/hero_motion_probe.gd -- \
##       --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-hero-models --chapter1-primary=chapter1.skill.frost \
##       --chapter1-seed=11 --primary=chapter1.skill.frost --until=2400 [--pose-override={"clip":"walk","run_time_scale":0.96667,"stride_world_m":4.313}] \
##       [--shots=<dir>   (needs a window: saves 24 consecutive frames of a walk, walk_NN.png)] [--motion-json=<file under _local/>]
##
## --stop-tick=<n> ends the probe at that tick (the walk numbers are taken before the first gear changes the move speed, ~tick 900).
## --drive=square holds the game's move keys instead of the pilot walking; --min-straight=<0..1> (default .99) keeps straight 1 s windows only; --motion-frames adds raw rows.
## --pose-override changes this process only: after the body has become the frost body (_hero_slot_id == actor.hero.frost.model) the view's
## _clip_run, _run_time_scale and _hero_stride are replaced once. No product file and no core state is touched.
## Reading the skeleton in a headless run works if the PROBE_BONES line shows both toe bones found and the toe heights move (R7 of the T9 spec).
const FROST_SLOT := "actor.hero.frost.model"
var body_slot := FROST_SLOT   ## --slot=actor.hero.arc.model measures another witch body (default frost)
const STANCE_BAND_M := .03
const MIN_SEGMENT_S := 1.0
const MIN_STRAIGHT_DEFAULT := .99
const SETTLE_FRAMES := 12   ## the first frames of a run still blend from the idle pose (a 7 m/s toe jump at the start): left out of the windows
const SHOT_FRAMES := 24
var shot_frames := SHOT_FRAMES   ## --shot-frames=N saves N frames instead of 24 (a video needs hundreds)
var shot_step := 1   ## --shot-step=2 saves every 2nd rendered frame (60 fps -> 30 fps video)
var _shot_tick := 0
var shot_crop := Rect2i()   ## --shot-crop=x,y,w,h saves only that part of the screen (much faster than a full 1080p png)
const TOE_NAMES := {"l": ["mixamorig_LeftToeBase", "mixamorig:LeftToeBase", "LeftToeBase"], "r": ["mixamorig_RightToeBase", "mixamorig:RightToeBase", "RightToeBase"]}
var override: Dictionary = {}
var override_arg := ""
var motion_json := ""
var keep_frames := false
var stop_tick := 0
var _stopped := false
var drive := ""
var leg_ticks := 150
var _held_key := -1
var min_straight := MIN_STRAIGHT_DEFAULT
var _override_done := false
var _bones: Dictionary = {}
var _bones_tried := false
var _segments: Array = []
var _seg: Array = []
var _shot_count := 0
var _shot_done := false
var _prev_clip_time := -1.0
var _frames_seen := 0
var _body_frames := 0
var _pose_check: Dictionary = {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pose-override="): override_arg = arg.trim_prefix("--pose-override=")
		elif arg.begins_with("--motion-json="): motion_json = arg.trim_prefix("--motion-json=")
		elif arg.begins_with("--shot-frames="): shot_frames = maxi(1, int(arg.trim_prefix("--shot-frames=")))
		elif arg.begins_with("--shot-step="): shot_step = maxi(1, int(arg.trim_prefix("--shot-step=")))
		elif arg.begins_with("--shot-crop="):
			var c := arg.trim_prefix("--shot-crop=").split(",")
			if c.size() == 4: shot_crop = Rect2i(int(c[0]), int(c[1]), int(c[2]), int(c[3]))
		elif arg.begins_with("--slot="): body_slot = arg.trim_prefix("--slot=")
		elif arg == "--motion-frames": keep_frames = true
		elif arg.begins_with("--stop-tick="): stop_tick = int(arg.trim_prefix("--stop-tick="))
		elif arg.begins_with("--drive="): drive = arg.trim_prefix("--drive=")
		elif arg.begins_with("--leg-ticks="): leg_ticks = maxi(30, int(arg.trim_prefix("--leg-ticks=")))
		elif arg.begins_with("--min-straight="): min_straight = float(arg.trim_prefix("--min-straight="))
	if not override_arg.is_empty():
		var parsed: Variant = JSON.parse_string(override_arg)
		if not parsed is Dictionary:
			push_error("hero_motion_probe: --pose-override is not a json object")
			print("HERO_MOTION_PROBE ", JSON.stringify({"error": "bad_pose_override"}))
			quit(2); return
		override = parsed
		for key in ["clip", "run_time_scale", "stride_world_m"]:
			if not override.has(key):
				push_error("hero_motion_probe: --pose-override needs clip, run_time_scale, stride_world_m")
				print("HERO_MOTION_PROBE ", JSON.stringify({"error": "bad_pose_override", "missing": key}))
				quit(2); return
	if not drive in ["", "square"]:
		print("HERO_MOTION_PROBE ", JSON.stringify({"error": "bad_drive", "drive": drive}))
		quit(2); return
	if "--chapter1-old-hero" in OS.get_cmdline_user_args():
		push_error("hero_motion_probe: --chapter1-old-hero measures the old mage body, not the witch bodies")
		print("HERO_MOTION_PROBE ", JSON.stringify({"error": "needs_hero_models_switch"}))
		quit(2); return
	if not motion_json.is_empty():
		var folder := motion_json.get_base_dir()
		if not ("/_local/" in ("/" + ProjectSettings.globalize_path(motion_json if motion_json.begins_with("res://") else "res://" + motion_json)).replace("\\", "/")):
			print("HERO_MOTION_PROBE ", JSON.stringify({"error": "motion_json_must_be_under__local"}))
			quit(2); return
		if not folder.is_empty(): DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder if folder.begins_with("res://") else "res://" + folder))
	super._initialize()
	if view != null: process_frame.connect(_probe_frame)

func _actors() -> Object:
	return view.get("actors") if view != null else null

## --drive=square: no built-in pilot walking (it dithers); the probe holds the game's own move keys W, D, S, A in turn, leg_ticks ticks each, through the same
## Input path a player uses (the app reads Input.is_physical_key_pressed). The pilot is let in only while a growth card is on offer, so the run never stalls.
const SQUARE_KEYS := [KEY_W, KEY_D, KEY_S, KEY_A]
func _drive_keys() -> void:
	var run: RefCounted = view.run
	var mode := String(run.mode)
	if mode != "playing" and mode != "choice": return
	view._pilot = mode == "choice"
	var want: int = SQUARE_KEYS[(int(run.tick) / leg_ticks) % 4] if mode == "playing" else -1
	if want == _held_key: return
	if _held_key >= 0: _send_key(_held_key, false)
	if want >= 0: _send_key(want, true)
	_held_key = want

func _send_key(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code as Key
	ev.keycode = code as Key
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _find_bone(skeleton: Skeleton3D, names: Array) -> int:
	for n in names:
		var idx := skeleton.find_bone(n)
		if idx >= 0: return idx
	return -1

func _setup_bones(actors: Object) -> void:
	_bones_tried = true
	var skeleton: Skeleton3D = actors.get("rig_skeleton")
	if skeleton == null: return
	var missing: Array = []
	for side in TOE_NAMES:
		var idx := _find_bone(skeleton, TOE_NAMES[side])
		if idx < 0: missing.append(side)
		else: _bones[side] = idx
	var names: Array = []
	for i in skeleton.get_bone_count(): names.append(skeleton.get_bone_name(i))
	print("PROBE_BONES ", JSON.stringify({"display": DisplayServer.get_name(), "found": {"l": skeleton.get_bone_name(int(_bones["l"])) if _bones.has("l") else "", "r": skeleton.get_bone_name(int(_bones["r"])) if _bones.has("r") else ""}, "missing": missing, "bone_count": names.size(), "names_head": names.slice(0, 12)}))

func _apply_override(actors: Object) -> void:
	_override_done = true
	if override.is_empty(): return
	var player: AnimationPlayer = actors.get("rig_player")
	if player == null or not player.has_animation(String(override.clip)):
		print("HERO_MOTION_PROBE ", JSON.stringify({"error": "override_clip_missing", "clip": override.clip, "clips": Array(player.get_animation_list()) if player != null else []}))
		quit(2); return
	actors.set("_clip_run", String(override.clip))
	actors.set("_run_time_scale", float(override.run_time_scale))
	actors.set("_hero_stride", float(override.stride_world_m))
	print("PROBE_POSE_OVERRIDE ", JSON.stringify({"clip": actors.get("_clip_run"), "run_time_scale": actors.get("_run_time_scale"), "stride_world_m": actors.get("_hero_stride")}))

func _wrap_diff(a: float, b: float, length: float) -> float:
	return fposmod(a - b + length * .5, length) - length * .5

## Runs once per frame before the nodes process: the state it sees is the one the previous frame left (hero position, bone poses, phase all
## come from the same sync), so the numbers belong together.
func _probe_frame() -> void:
	if view == null or view.get("run") == null: return
	if stop_tick > 0 and not _stopped and int(view.run.tick) >= stop_tick:
		_stopped = true   # --stop-tick: end the probe here (the dump flow of hud_dump would run on to tick 1500 and past the first gear)
		_finish(); quit(0); return
	if drive == "square": _drive_keys()
	var actors := _actors()
	if actors == null or actors.get("hero") == null or actors.get("rig_skeleton") == null: return
	_frames_seen += 1
	if String(actors.get("_hero_slot_id")) != body_slot: return
	_body_frames += 1
	if not _override_done: _apply_override(actors)
	if not _bones_tried: _setup_bones(actors)
	if _bones.size() < 2: return
	var run: RefCounted = view.run
	var walking: bool = String(run.mode) == "playing" and not run.hero.is_empty() and int(run.hero.hp_raw) > 0 and int(run.tick) < int(actors.get("_hero_move_until"))
	if not walking:
		_close_segment()
		return
	var skeleton: Skeleton3D = actors.get("rig_skeleton")
	var gt := skeleton.global_transform
	var hero_pos: Vector3 = actors.hero.global_position
	var length := float(actors.get("_run_time_scale"))
	var clip_time := fposmod(float(actors.get("_phase")) * length, length)
	var toe_l: Vector3 = gt * skeleton.get_bone_global_pose(int(_bones.l)).origin
	var toe_r: Vector3 = gt * skeleton.get_bone_global_pose(int(_bones.r)).origin
	_seg.append({"f": Engine.get_process_frames(), "tick": int(run.tick), "frac": Engine.get_physics_interpolation_fraction(), "dt": view.get_process_delta_time(), "hero": hero_pos, "ct": clip_time, "l": toe_l, "r": toe_r, "clip": String(actors.get("_clip_run")), "L": length})
	var min_frames := int(ceil(MIN_SEGMENT_S * 60.0))
	if not shots_dir.is_empty() and not _shot_done and _seg.size() >= min_frames and DisplayServer.get_name() != "headless":
		_save_walk_shot()

func _save_walk_shot() -> void:
	_shot_tick += 1
	if (_shot_tick - 1) % shot_step != 0: return
	var image := root.get_viewport().get_texture().get_image()
	if image == null: return
	DirAccess.make_dir_recursive_absolute(shots_dir)
	if shot_crop.size.x > 0: image = image.get_region(shot_crop)
	image.save_png(shots_dir.path_join("walk_%02d.png" % _shot_count))
	_shot_count += 1
	if _shot_count >= shot_frames:
		_shot_done = true
		if shot_frames > SHOT_FRAMES and stop_tick == 0 or shot_frames > SHOT_FRAMES and stop_tick > int(view.run.tick): stop_tick = int(view.run.tick) + 1   # a video capture ends with its last frame

func _close_segment() -> void:
	if _seg.is_empty(): return
	var seconds := 0.0
	for k in range(1, _seg.size()): seconds += float(_seg[k].dt)
	if seconds >= MIN_SEGMENT_S: _segments.append(_seg)
	_seg = []
	if not _shot_done and _shot_count > 0 and _shot_count < shot_frames: _shot_count = 0   # a walk that ended before 24 frames: start over on the next one

## The pilot sometimes dithers (direction flips every tick, path far longer than the net move). Those stretches are not a walk: each continuous run is
## cut into 1 s windows (61 frames) and only windows whose net displacement is at least MIN_STRAIGHT of the path walked count (all counts are reported).
func _windows() -> Array:
	var out: Array = []
	var frames_per := int(round(MIN_SEGMENT_S * 60.0))
	for seg in _segments:
		var start := SETTLE_FRAMES
		while start + frames_per < seg.size():
			out.append(seg.slice(start, start + frames_per + 1))
			start += frames_per
	return out

func _window_path(w: Array) -> float:
	var path := 0.0
	for k in range(1, w.size()): path += Vector2(w[k].hero.x - w[k - 1].hero.x, w[k].hero.z - w[k - 1].hero.z).length()
	return path

func _summarize() -> Dictionary:
	_close_segment()
	var all_windows := _windows()
	var used: Array = []
	for w in all_windows:
		var path := _window_path(w)
		var net := Vector2(w[-1].hero.x - w[0].hero.x, w[-1].hero.z - w[0].hero.z).length()
		if path > 0.0 and net / path >= min_straight: used.append(w)
	var floor_y := INF
	for w in used:
		for r in w: floor_y = minf(floor_y, minf(r.l.y, r.r.y))
	var total_path := 0.0
	var total_net := 0.0
	var total_time := 0.0
	var clip_gain := 0.0
	var sq_fwd := 0.0
	var sq_horiz := 0.0
	var stance := 0
	var rows_out: Array = []
	var toe_min := INF
	var toe_max := -INF
	for w in used:
		var secs := 0.0
		var gain := 0.0
		var w_stance := 0
		var w_sq := 0.0
		var heading_v := Vector2(w[-1].hero.x - w[0].hero.x, w[-1].hero.z - w[0].hero.z)
		var heading := heading_v.normalized()
		for k in range(1, w.size()):
			var a: Dictionary = w[k - 1]
			var b: Dictionary = w[k]
			var dt := float(b.dt)
			if dt <= 0.0: continue
			secs += dt
			gain += _wrap_diff(float(b.ct), float(a.ct), float(b.L))
			for side in ["l", "r"]:
				toe_min = minf(toe_min, b[side].y); toe_max = maxf(toe_max, b[side].y)
				if a[side].y > floor_y + STANCE_BAND_M or b[side].y > floor_y + STANCE_BAND_M: continue
				var v := Vector2(b[side].x - a[side].x, b[side].z - a[side].z) / dt
				var fwd := v.dot(heading)
				sq_fwd += fwd * fwd
				sq_horiz += v.length_squared()
				w_sq += fwd * fwd
				w_stance += 1
		var path := _window_path(w)
		total_path += path; total_net += heading_v.length(); total_time += secs; clip_gain += gain; stance += w_stance
		rows_out.append({"tick": int(w[0].tick), "straight": snappedf(heading_v.length() / path, .001) if path > 0 else 0.0, "seconds": snappedf(secs, .001), "speed": snappedf(heading_v.length() / secs, .001) if secs > 0 else 0.0, "rate": snappedf(gain / secs, .0001) if secs > 0 else 0.0, "stance": w_stance, "slip_rms": snappedf(sqrt(w_sq / w_stance), .001) if w_stance > 0 else null})
	var clip_name := String(_segments[0][0].clip) if not _segments.is_empty() else ""
	var length := float(_segments[0][0].L) if not _segments.is_empty() else 0.0
	var doc := {
		"display": DisplayServer.get_name(), "override": override, "clip": clip_name, "L": length,
		"stride_world_m": _stride_now(), "runs": _segments.size(), "windows_total": all_windows.size(), "windows_used": used.size(), "min_straight": min_straight,
		"segment_seconds": snappedf(total_time, .001),
		"avg_speed_mps": snappedf(total_net / total_time, .0001) if total_time > 0 else null,
		"path_speed_mps": snappedf(total_path / total_time, .0001) if total_time > 0 else null,
		"rate_measured": snappedf(clip_gain / total_time, .0001) if total_time > 0 else null,
		"slip_rms_mps": snappedf(sqrt(sq_fwd / stance), .0001) if stance > 0 else null,
		"slip_rms_horiz_mps": snappedf(sqrt(sq_horiz / stance), .0001) if stance > 0 else null,
		"stance_samples": stance, "floor_y": snappedf(floor_y, .0001) if floor_y < INF else null,
		"toe_y_range": [snappedf(toe_min, .0001), snappedf(toe_max, .0001)] if toe_min < INF else null,
		"body_frames": _body_frames, "frames_seen": _frames_seen, "walk_shots": _shot_count, "final_tick": int(view.run.tick), "per_window": rows_out,
	}
	if keep_frames:
		var rows: Array = []
		for w in used:
			for r in w: rows.append([r.f, r.tick, snappedf(r.frac, .001), snappedf(r.dt, .00001), snappedf(r.hero.x, .0001), snappedf(r.hero.z, .0001), snappedf(r.ct, .0001), snappedf(r.l.x, .0001), snappedf(r.l.y, .0001), snappedf(r.l.z, .0001), snappedf(r.r.x, .0001), snappedf(r.r.y, .0001), snappedf(r.r.z, .0001)])
			rows.append([])
		doc["frames_cols"] = ["f", "tick", "frac", "dt", "hero_x", "hero_z", "clip_time", "l_x", "l_y", "l_z", "r_x", "r_y", "r_z"]
		doc["frames"] = rows
	return doc

func _stride_now() -> Variant:
	var actors := _actors()
	return snappedf(float(actors.get("_hero_stride")), .0001) if actors != null else null

func _finish() -> void:
	var doc := _summarize()
	print("HERO_MOTION_PROBE ", JSON.stringify(doc))
	if not motion_json.is_empty():
		var target := motion_json if motion_json.begins_with("res://") else "res://" + motion_json
		var file := FileAccess.open(ProjectSettings.globalize_path(target), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(doc, "  "))
			file.close()
	super._finish()
