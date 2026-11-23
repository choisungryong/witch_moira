extends SceneTree
## QA tool (never product code): pictures and frame times of the descent's three sweeps (D24 12.2), on the real ChapterOne scene.
## Two sources of events:
##   --source=fake  (default) the core is frozen after the setup (physics off) and FAKE events of D24 9.4 are fed to the presenter
##                  (chapter1/tests/support/descent_fake_events.gd): the picture does not depend on a core patch. Extra walkers / ranged /
##                  chargers are spawned on the screen's rectangle so the effect is judged over a real crowd; they stand still.
##   --source=core  the pilot plays and the REAL core's events drive the presenter; the tool presses R (call_descent) once the gauge is full.
## Real renderer needed (no --headless). With --fixed-fps 60 one frame is one sweep step; without it the steps follow the wall clock.
##
##   python tools/dev/godot.py --timeout-s=900 --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/descent_fx_shots.gd -- --chapter1-start --chapter1-pilot --chapter1-trial=descent --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --chapter1-descent-cost=1000 --chapter1-primary=chapter1.skill.ember --element=ember --enemies=70 --shots=_local/shots/d24-fx --tag=ember
## (--chapter1-start is needed or the run stays in the menu; --chapter1-pilot is needed for --source=core; --chapter1-descent-cost must be 1000 or more,
##  a lower value is rejected by the validator and the descent is switched off.)
## Options: --element=ember|frost|arc  --steps=14,24,30,...  (sweep steps to take a picture at; default per element)  --enemies=N
##   --source=fake|core  --perf=<repeats> (frame times, no pictures: idle / sweep / tail p50 p95 max)  --projectiles=N (fake ones, drawn only)
##   --cutin-at=<seconds,...> (core and fake) pictures of the cut-in at these times after the call (frame clock: with --fixed-fps 60 one frame is 1/60 s), files <tag>-cutin-t<ms>.png
##   --cutin-shot (fake source) alias of --cutin-at=0.43   --end-shots=<frames,...> (core) pictures this many frames after the sweep ended (state left "sweep"), files <tag>-end-f<n>.png
##   --luma-series=<json under _local/> (core) mean luma of the play area per frame from sweep s1 to end+30 frames, and the most swings above 0.08 inside any 1 s window (light sensitivity)
##   --skip-at=<seconds> (core) a key press (--skip-key=esc|space|mouse, default esc) this long after the call; DESCENT_SKIP lines say what the core did (mode, tick, hero) at the press and after it
##   --call=long|short (fake, with --perf) a descent_called of that variant is fed before each sweep and its frames are timed as the "cut" phase (long = the demon's video when the slot has one)
##   --fx-off (core) the presenter draws nothing: the same scene (same seed, same step) without the descent's own layers, to measure what the descent adds
##   --second=<n> (core) after the first descent has ended fill the gauge (QA only) and call a second one: the cut-in pictures of it (--second-at=<seconds,...>, default 0.1,0.3) are <tag>-b-cutin-t<ms>.png
##   --wall-s=<seconds> (core) safety stop by wall clock, default 780   --out=<json under _local/>  --first-wait=<frames>  --every=<n> (only every n-th default step)
## Prints DESCENT_SHOT lines and DESCENT_FX_PERF / DESCENT_SHOTS_RESULT.
const Fake = preload("res://chapter1/tests/support/descent_fake_events.gd")
const DEFAULT_STEPS := {
	"ember": [1, 14, 24, 32, 52, 80, 112, 133, 140, 175],
	"frost": [6, 12, 20, 45, 100, 149, 151, 154, 160, 190],
	"arc": [2, 8, 20, 40, 66, 90, 112, 121, 124, 150],
}
var view: Node
var element := "ember"
var steps: Array = []
var enemies_n := 70
var shots_dir := ""
var tag := ""
var source := "fake"
var perf_repeats := 0
var projectiles_n := 0
var out_path := ""
var first_wait := 90
var every := 1
var cutin_shot := false
var cutin_at: Array = []
var end_shots: Array = []
var luma_path := ""
var call_mode := ""           ## --call=long|short (fake source, with --perf): a descent_called of that variant before the sweep; its frames are the "cut" phase
var phase_now := ""
var fx_off := false           ## --fx-off: the presenter draws nothing (descent_fx.qa_hidden): the same scene without the descent's layers, for the "what the descent adds" difference
var skip_at := -1.0
var skip_key := "esc"
var second_n := 0
var second_at: Array = [0.1, 0.3]
var _skip_sent := false
var _skip_probes: Array = []   ## call-clock seconds at which the state after the press is printed
var wall_s := 780.0
const PLAY_BOX := [0, 90, 1920, 900]            ## same as tools/dev/shot_review.py DEFAULTS["play"] / ["exclude"] (1080p coordinates)
const EXCLUDE_BOX := [1500, 0, 1920, 200]
const LUMA_W := 240
const LUMA_H := 135
const LUMA_SWING := 0.08
var _call_clock := -1.0     ## seconds since the call (sum of frame deltas), -1 before the call

var gen: RefCounted
var sim_step := -1          # -1 idle, 0 released, 1.. steps
var sim_total := 0
var acc := 0.0
var wall_clock_steps := true
var frame_ms: Array = []
var phase_ms := {"idle": [], "cut": [], "sweep": [], "tail": []}
var _rng := RandomNumberGenerator.new()
var _last_us := -1
var _tail_left := 0
var _called := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--element="): element = arg.trim_prefix("--element=")
		elif arg.begins_with("--steps="):
			steps = []
			for part in arg.trim_prefix("--steps=").split(",", false): steps.append(int(part))
		elif arg.begins_with("--enemies="): enemies_n = int(arg.trim_prefix("--enemies="))
		elif arg.begins_with("--shots="): shots_dir = arg.trim_prefix("--shots=")
		elif arg.begins_with("--tag="): tag = arg.trim_prefix("--tag=")
		elif arg.begins_with("--source="): source = arg.trim_prefix("--source=")
		elif arg.begins_with("--perf="): perf_repeats = int(arg.trim_prefix("--perf="))
		elif arg.begins_with("--projectiles="): projectiles_n = int(arg.trim_prefix("--projectiles="))
		elif arg.begins_with("--out="): out_path = arg.trim_prefix("--out=")
		elif arg.begins_with("--first-wait="): first_wait = int(arg.trim_prefix("--first-wait="))
		elif arg == "--cutin-shot": cutin_shot = true
		elif arg.begins_with("--cutin-at="):
			cutin_at = []
			for part in arg.trim_prefix("--cutin-at=").split(",", false): cutin_at.append(float(part))
			cutin_at.sort()
		elif arg.begins_with("--end-shots="):
			end_shots = []
			for part in arg.trim_prefix("--end-shots=").split(",", false): end_shots.append(int(part))
			end_shots.sort()
		elif arg.begins_with("--luma-series="): luma_path = arg.trim_prefix("--luma-series=")
		elif arg == "--fx-off": fx_off = true
		elif arg.begins_with("--call="): call_mode = arg.trim_prefix("--call=")
		elif arg.begins_with("--skip-at="): skip_at = float(arg.trim_prefix("--skip-at="))
		elif arg.begins_with("--skip-key="): skip_key = arg.trim_prefix("--skip-key=")
		elif arg.begins_with("--second="): second_n = int(arg.trim_prefix("--second="))
		elif arg.begins_with("--second-at="):
			second_at = []
			for part in arg.trim_prefix("--second-at=").split(",", false): second_at.append(float(part))
			second_at.sort()
		elif arg.begins_with("--wall-s="): wall_s = float(arg.trim_prefix("--wall-s="))
		elif arg.begins_with("--every="): every = maxi(1, int(arg.trim_prefix("--every=")))
	if cutin_shot and cutin_at.is_empty(): cutin_at = [26.0 / 60.0]
	if steps.is_empty():
		for i in (DEFAULT_STEPS[element] as Array).size():
			if i % every == 0: steps.append(DEFAULT_STEPS[element][i])
	if tag.is_empty(): tag = element
	if perf_repeats > 0:
		OS.delta_smoothing = false
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_rng.seed = 7
	view = (load("res://chapter1/ChapterOne.tscn") as PackedScene).instantiate()
	root.add_child(view)
	call_deferred("execute")

func rect_point(center: Vector2, margin: float = 1.5) -> Vector2:
	var rad := deg_to_rad(-38.2)
	var right := Vector2(cos(rad), sin(rad))
	var down := right.rotated(PI * 0.5)
	var u := _rng.randf_range(-17.3 + margin, 17.3 - margin)
	var v := _rng.randf_range(-13.4 + margin, 13.4 - margin)
	return center + right * u + down * v

func populate(run: RefCounted, n: int) -> PackedVector2Array:
	var list := PackedVector2Array()
	var kinds := ["walker", "walker", "walker", "ranged", "charger"]
	var tries := 0
	while list.size() < n and tries < n * 6:
		tries += 1
		var at := rect_point(run.hero.position)
		if at.distance_to(run.hero.position) < 2.5: continue
		if run._spawn(kinds[list.size() % kinds.size()], at): list.append(at)
	return list

func execute() -> void:
	var run: RefCounted = view.run
	# wait for the run to start
	var guard := 0
	while (run.mode != "playing" or run.hero.is_empty()) and guard < 1200:
		guard += 1
		await process_frame
	for i in first_wait: await process_frame
	if source == "core":
		await execute_core()
		return
	view.set_physics_process(false)
	var fx = view.descent_fx
	var positions := populate(run, enemies_n)
	if projectiles_n > 0: add_projectiles(run, projectiles_n)
	for i in 20: await process_frame
	if not cutin_at.is_empty():
		# the cut-in alone: the core's mode is set to "descent" by this tool for a moment (the presenter's clock runs in that mode only)
		run.mode = "descent"
		fx.consume([{"type": "descent_called", "seq": 99999, "tick": run.tick, "element": element, "variant": "long", "position": run.hero.position, "center": run.hero.position}])
		var f := 0
		for t in cutin_at:
			var want_f := int(round(float(t) * 60.0))
			while f < want_f:
				await process_frame
				f += 1
			await RenderingServer.frame_post_draw
			save_shot(90, 0, fx, "%s-cutin-t%04d.png" % [tag, int(round(float(t) * 1000.0))])
		run.mode = "playing"
		fx.take_release()
		for i in 90: await process_frame
		finish(fx)
		return
	var total := int(Fake.SWEEP_TICKS[element])
	var repeats := maxi(1, perf_repeats)
	for rep in repeats:
		gen = Fake.new(element, 11 + rep, positions)
		if perf_repeats > 0:
			# idle frames first (the presenter has nothing to draw), then the sweep, then its tail
			_last_us = -1
			for i in 90: await process_frame
		if call_mode != "":
			run.mode = "descent"
			phase_now = "cut"
			fx.consume([{"type": "descent_called", "seq": 99990 + rep, "tick": run.tick, "element": element, "variant": call_mode, "position": run.hero.position, "center": run.hero.position, "hold_bonus_bps": 0}])
			var cut_guard := 0
			await process_frame
			while bool(fx.status().cutin) and cut_guard < 900:
				cut_guard += 1
				await process_frame
			phase_now = ""
			run.mode = "playing"
		sim_total = total
		sim_step = 0
		acc = 0.0
		var released: Array = gen.release(run.hero.position, int(run.tick))
		fx.consume(released)
		if perf_repeats > 0 and rep == 0: phase_label = "sweep"
		var shot_i := 0
		while sim_step <= total + (260 if perf_repeats == 0 else 200):
			await process_frame
			if perf_repeats == 0 and shot_i < steps.size() and sim_step >= int(steps[shot_i]):
				await RenderingServer.frame_post_draw
				save_shot(shot_i, int(steps[shot_i]), fx)
				shot_i += 1
				if shot_i >= steps.size(): break
		if perf_repeats > 0:
			var guard2 := 0
			while bool(fx.status().sweep) and guard2 < 1200:
				guard2 += 1
				await process_frame
	finish(view.descent_fx)

var phase_label := "idle"
var spikes: Array = []     ## frames over 50 ms outside the idle phase: [ms, sweep step]

func add_projectiles(run: RefCounted, n: int) -> void:
	var list: Array[Dictionary] = run.projectiles.duplicate()
	var c: Vector2 = run.hero.position
	for i in n:
		var a := _rng.randf() * TAU
		list.append({"position": c + Vector2(_rng.randf_range(-12, 12), _rng.randf_range(-8, 8)), "direction": Vector2(cos(a), sin(a)), "hostile": false, "child": false,
			"skill_id": "chapter1.skill.ember", "expires": 100000000, "previous": c, "radius": .12, "uid": 1000000 + i})
	run.projectiles = list

func _process(delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if _last_us >= 0 and perf_repeats > 0:
		var ms := float(now - _last_us) / 1000.0
		var phase := "idle"
		if sim_step >= 1 and sim_step <= sim_total: phase = "sweep"
		elif sim_step > sim_total: phase = "tail"
		if phase_now != "": phase = phase_now
		(phase_ms[phase] as Array).append(ms)
		if ms > 50.0 and phase != "idle": spikes.append([snappedf(ms, 0.1), sim_step])
	_last_us = now
	if _call_clock >= 0.0: _call_clock += delta
	if source != "fake" or sim_step < 0 or gen == null: return false
	var fx = view.descent_fx
	var run: RefCounted = view.run
	if sim_step > sim_total + 400: return false
	acc += delta
	var want := int(acc * 60.0 + 0.0001)
	if sim_step < want:
		# one step per frame at most with a fixed frame rate; with a real clock several may be due (the sweep follows wall time)
		while sim_step < want:
			sim_step += 1
			if sim_step <= sim_total: fx.consume(gen.step(sim_step))
	return false

func save_shot(index: int, step: int, fx: RefCounted, file_name := "") -> void:
	if shots_dir.is_empty(): return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(shots_dir))
	var image := root.get_viewport().get_texture().get_image()
	var file := file_name if not file_name.is_empty() else "%s-%02d-s%03d.png" % [tag, index, step]
	var path := shots_dir.path_join(file)
	image.save_png(ProjectSettings.globalize_path("res://").path_join(path))
	var st: Dictionary = fx.status()
	print("DESCENT_SHOT ", JSON.stringify({"file": path, "step": step, "t": snappedf(float(st.sweep_t), 0.001), "element": element, "demon": snappedf(float(st.demon), 0.01),
		"particles": st.stats.particles, "lights_peak": st.stats.lights_peak, "bolts": st.bolts, "w": image.get_width(), "h": image.get_height(),
		"cut": st.get("cut_kind", ""), "cut_t": snappedf(float(st.cut_t), 0.001), "hud_hidden": st.get("hud_hidden", false), "band_up": st.get("band_up", false), "skipped": st.get("skipped", false), "call_clock": snappedf(_call_clock, 0.001)}))

func pct(list: Array, q: float) -> float:
	if list.is_empty(): return 0.0
	var sorted := list.duplicate()
	sorted.sort()
	return float(sorted[mini(sorted.size() - 1, int(float(sorted.size()) * q))])

func finish(fx: RefCounted) -> void:
	var report := {"element": element, "source": source, "enemies": view.run.enemies.size(), "projectiles": view.run.projectiles.size(), "stats": fx.status().stats}
	if perf_repeats > 0:
		for key in phase_ms:
			var list: Array = phase_ms[key]
			report[key] = {"frames": list.size(), "p50": snappedf(pct(list, 0.5), 0.01), "p95": snappedf(pct(list, 0.95), 0.01), "p99": snappedf(pct(list, 0.99), 0.01), "max": snappedf(pct(list, 1.0), 0.01)}
		report["spikes_over_50ms"] = spikes
		print("DESCENT_FX_PERF ", JSON.stringify(report))
	if not out_path.is_empty():
		var f := FileAccess.open(ProjectSettings.globalize_path("res://").path_join(out_path), FileAccess.WRITE)
		if f != null: f.store_string(JSON.stringify(report, "  "))
	print("DESCENT_SHOTS_RESULT ", JSON.stringify(report))
	quit(0)

## Mean luma (Rec. 709 weights, as shot_review.py) of the play area on the picture shown now, from a copy shrunk to LUMA_W x LUMA_H.
func play_luma() -> float:
	var image := root.get_viewport().get_texture().get_image()
	image.resize(LUMA_W, LUMA_H, Image.INTERPOLATE_TRILINEAR)
	var fx_ := float(LUMA_W) / 1920.0
	var fy_ := float(LUMA_H) / 1080.0
	var x0 := int(round(PLAY_BOX[0] * fx_))
	var x1 := int(round(PLAY_BOX[2] * fx_))
	var y0 := int(round(PLAY_BOX[1] * fy_))
	var y1 := int(round(PLAY_BOX[3] * fy_))
	var ex0 := int(round(EXCLUDE_BOX[0] * fx_))
	var ex1 := int(round(EXCLUDE_BOX[2] * fx_))
	var ey0 := int(round(EXCLUDE_BOX[1] * fy_))
	var ey1 := int(round(EXCLUDE_BOX[3] * fy_))
	var sum := 0.0
	var n := 0
	for y in range(y0, y1):
		var in_ey := y >= ey0 and y < ey1
		for x in range(x0, x1):
			if in_ey and x >= ex0 and x < ex1: continue
			var c := image.get_pixel(x, y)
			sum += c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			n += 1
	return sum / float(maxi(1, n))

## Zigzag of the series: a swing is a move of at least LUMA_SWING from the last extreme, counted at the frame that confirms it.
## A 1 s window is 60 frames (fixed frame rate). Returns swings, rises, falls, the most swings (and rises) in any 1 s window.
func analyse_luma(series: Array) -> Dictionary:
	var swings: Array = []   # [frame_index, +1 rise / -1 fall]
	if series.size() > 1:
		var y0 := float(series[0].y)
		var lo := y0
		var hi := y0
		var lo_i := 0
		var hi_i := 0
		var dir := 0
		for i in range(1, series.size()):
			var y := float(series[i].y)
			if dir == 0:
				if y > hi:
					hi = y
					hi_i = i
				if y < lo:
					lo = y
					lo_i = i
				if hi - lo >= LUMA_SWING:
					if hi_i > lo_i:
						swings.append([i, 1])
						dir = 1
						hi = y
					else:
						swings.append([i, -1])
						dir = -1
						lo = y
			elif dir == 1:
				if y > hi: hi = y
				elif hi - y >= LUMA_SWING:
					swings.append([i, -1])
					dir = -1
					lo = y
			else:
				if y < lo: lo = y
				elif y - lo >= LUMA_SWING:
					swings.append([i, 1])
					dir = 1
					hi = y
	var rises := 0
	var falls := 0
	var best := 0
	var best_r := 0
	var best_at := 0
	for sw in swings:
		if int(sw[1]) > 0: rises += 1
		else: falls += 1
	for a in swings.size():
		var cnt := 0
		var cr := 0
		for b in range(a, swings.size()):
			if int(swings[b][0]) - int(swings[a][0]) >= 60: break
			cnt += 1
			if int(swings[b][1]) > 0: cr += 1
		if cnt > best:
			best = cnt
			best_at = int(swings[a][0])
		best_r = maxi(best_r, cr)
	return {"swing_threshold": LUMA_SWING, "swings": swings.size(), "rises": rises, "falls": falls, "max_swings_1s": best, "max_rises_1s": best_r, "window_start_frame": best_at}

func write_luma(series: Array) -> void:
	if luma_path.is_empty(): return
	var out := analyse_luma(series)
	out["play_box"] = PLAY_BOX
	out["exclude_box"] = EXCLUDE_BOX
	out["sample"] = "%dx%d trilinear copy of the 1080p frame, Rec.709 weights on sRGB values (as shot_review.py)" % [LUMA_W, LUMA_H]
	out["element"] = element
	out["frames"] = series.size()
	var ymin := 1.0
	var ymax := 0.0
	var rows: Array = []
	for e in series:
		ymin = minf(ymin, float(e.y))
		ymax = maxf(ymax, float(e.y))
		rows.append([int(e.f), int(e.s), snappedf(float(e.y), 0.0001)])
	out["y_min"] = snappedf(ymin if not series.is_empty() else 0.0, 0.0001)
	out["y_max"] = snappedf(ymax, 0.0001)
	out["series_columns"] = ["frame_since_s1", "sweep_step(-1 after the sweep ended)", "luma"]
	out["series"] = rows
	var path := ProjectSettings.globalize_path("res://").path_join(luma_path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null: f.store_string(JSON.stringify(out))
	print("DESCENT_LUMA ", JSON.stringify({"file": luma_path, "frames": series.size(), "swings": out.swings, "max_swings_1s": out.max_swings_1s, "max_rises_1s": out.max_rises_1s,
		"y_min": out.y_min, "y_max": out.y_max}))

## The real core's events: the tool presses R once the gauge is full and takes the pictures at the sweep steps it reaches.
## After the sweep ends (state leaves "sweep") the --end-shots pictures and the luma tail are taken, then it ends. A step beyond the sweep length is reported, not waited for.
## Safety: the wall clock (--wall-s) ends the run with a warning and whatever was taken.
## A key press as the player would make it (Input.parse_input_event goes through the viewport, so the app's _input sees it first).
func send_skip(run: RefCounted, fx: RefCounted) -> void:
	print_skip_state("press", run, fx)
	if skip_key == "mouse":
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE_BUTTON_LEFT
		m.pressed = true
		m.position = Vector2(400, 300)
		Input.parse_input_event(m)
	else:
		var k := InputEventKey.new()
		k.keycode = KEY_SPACE if skip_key == "space" else KEY_ESCAPE
		k.physical_keycode = k.keycode
		k.pressed = true
		Input.parse_input_event(k)
	for dt in [0.1, 0.3, 0.6, 1.0, 1.5, 2.2]: _skip_probes.append(_call_clock + dt)

func print_skip_state(label: String, run: RefCounted, fx: RefCounted) -> void:
	var st: Dictionary = fx.status()
	print("DESCENT_SKIP ", JSON.stringify({"when": label, "call_clock": snappedf(_call_clock, 0.001), "mode": run.mode, "tick": int(run.tick), "hero": [snappedf(run.hero.position.x, 0.001), snappedf(run.hero.position.y, 0.001)],
		"cut": st.get("cut_kind", ""), "cut_t": snappedf(float(st.cut_t), 0.001), "skipped": st.get("skipped", false), "hud_hidden": st.get("hud_hidden", false), "band_up": st.get("band_up", false), "release_due": st.release_due,
		"paused": run.mode == "paused"}))

## The second descent of the run (--second): the gauge is filled by the QA tool (a cheat that only this tool has), then the same call; the cut-in pictures are <tag>-b-cutin-t<ms>.png.
func second_descent() -> void:
	var run: RefCounted = view.run
	var fx = view.descent_fx
	run._descent_add(5000)
	var guard := 0
	while guard < 1200 and not (run.mode == "playing" and bool(run.descent_view().get("ready", false))):
		guard += 1
		await process_frame
	_skip_sent = false
	_call_clock = 0.0
	view.call_descent()
	var cut_i := 0
	var end_f := -1
	var number_shot := false
	var frames := 0
	while frames < 1500:
		frames += 1
		await process_frame
		while cut_i < second_at.size() and _call_clock >= float(second_at[cut_i]):
			await RenderingServer.frame_post_draw
			save_shot(95, 0, fx, "%s-b-cutin-t%04d.png" % [tag, int(round(float(second_at[cut_i]) * 1000.0))])
			cut_i += 1
		var st := String(run.descent_view().get("state", ""))
		if st != "sweep" and st != "hold" and frames > 30 and cut_i >= second_at.size():
			end_f += 1
			if end_f == 0 or end_f == 30:
				await RenderingServer.frame_post_draw
				save_shot(96, 0, fx, "%s-b-end-f%03d.png" % [tag, end_f])
			if end_f > 30: break
	print("DESCENT_SECOND ", JSON.stringify({"frames": frames, "shots": cut_i, "stats": fx.status().stats}))

func execute_core() -> void:
	var run: RefCounted = view.run
	var fx = view.descent_fx
	if fx_off: fx.qa_hidden = true
	var shot_i := 0
	var cut_i := 0
	var seen_step := -1
	var hold_frames := 0
	var seen_sweep := false
	var end_frames := -1
	var end_i := 0
	var series: Array = []
	var series_f := 0
	var start_ms := Time.get_ticks_msec()
	var need_end := not end_shots.is_empty() or not luma_path.is_empty()
	var tail_frames := 0
	if not end_shots.is_empty(): tail_frames = int(end_shots.back())
	if not luma_path.is_empty(): tail_frames = maxi(tail_frames, 30)
	var stop_reason := "steps_done"
	while true:
		if float(Time.get_ticks_msec() - start_ms) / 1000.0 > wall_s:
			stop_reason = "wall_clock"
			print("DESCENT_SHOTS_WARN wall clock limit %.0f s reached (called=%s seen_sweep=%s mode=%s)" % [wall_s, str(_called), str(seen_sweep), str(run.mode)])
			break
		await process_frame
		var v: Dictionary = run.descent_view()
		if bool(v.get("enabled", false)) and bool(v.ready) and run.mode == "playing" and not _called:
			_called = true
			_call_clock = 0.0
			view.call_descent()
		if _called and skip_at >= 0.0 and not _skip_sent and _call_clock >= skip_at:
			_skip_sent = true
			send_skip(run, fx)
		while not _skip_probes.is_empty() and _call_clock >= float(_skip_probes[0]):
			_skip_probes.pop_front()
			print_skip_state("after", run, fx)
		if _called and cut_i < cutin_at.size() and _call_clock >= float(cutin_at[cut_i]):
			await RenderingServer.frame_post_draw
			save_shot(90, 0, fx, "%s-cutin-t%04d.png" % [tag, int(round(float(cutin_at[cut_i]) * 1000.0))])
			cut_i += 1
		var st := String(v.get("state", ""))
		if st == "hold":
			hold_frames += 1
			if hold_frames == 28 and cutin_at.is_empty():
				await RenderingServer.frame_post_draw
				save_shot(90, 0, fx)       # the cut-in, mid-slide (the core stands still in mode "descent")
		if st == "sweep":
			seen_sweep = true
			var s := int(v.sweep_ticks) - int(v.sweep_left_ticks)
			if s != seen_step:
				seen_step = s
				if shot_i < steps.size() and s >= int(steps[shot_i]):
					await RenderingServer.frame_post_draw
					save_shot(shot_i, s, fx)
					shot_i += 1
			if not luma_path.is_empty():
				await RenderingServer.frame_post_draw
				series.append({"f": series_f, "s": s, "y": play_luma()})
				series_f += 1
		elif seen_sweep:
			if end_frames < 0:
				end_frames = 0
				if shot_i < steps.size():
					print("DESCENT_SHOTS_WARN the sweep ended at step %d; steps %s were not reached and are skipped" % [seen_step, str(steps.slice(shot_i))])
			else:
				end_frames += 1
			while end_i < end_shots.size() and end_frames >= int(end_shots[end_i]):
				await RenderingServer.frame_post_draw
				save_shot(91 + end_i, 0, fx, "%s-end-f%03d.png" % [tag, int(end_shots[end_i])])
				end_i += 1
			if not luma_path.is_empty() and end_frames <= 30:
				await RenderingServer.frame_post_draw
				series.append({"f": series_f, "s": -1, "y": play_luma()})
				series_f += 1
			if end_frames >= tail_frames:
				stop_reason = "end_scene_done"
				break
		if not need_end and shot_i >= steps.size() and cut_i >= cutin_at.size():
			break
	write_luma(series)
	if second_n > 0 and stop_reason == "end_scene_done": await second_descent()
	if cut_i < cutin_at.size(): print("DESCENT_SHOTS_WARN cut-in times not taken: %s" % str(cutin_at.slice(cut_i)))
	print("DESCENT_CORE_STOP ", JSON.stringify({"reason": stop_reason, "wall_s": snappedf(float(Time.get_ticks_msec() - start_ms) / 1000.0, 0.1), "steps_taken": shot_i, "steps_asked": steps.size(),
		"end_shots_taken": end_i, "cutin_taken": cut_i, "called": _called, "sweep_seen": seen_sweep}))
	finish(fx)
