extends SceneTree
## QA tool (never product code): pictures and frame times of the descent's three sweeps (D24 12.2), on the real ChapterOne scene.
## Two sources of events:
##   --source=fake  (default) the core is frozen after the setup (physics off) and FAKE events of D24 9.4 are fed to the presenter
##                  (chapter1/tests/support/descent_fake_events.gd): the picture does not depend on a core patch. Extra walkers / ranged /
##                  chargers are spawned on the screen's rectangle so the effect is judged over a real crowd; they stand still.
##   --source=core  the pilot plays and the REAL core's events drive the presenter; the tool presses R (call_descent) once the gauge is full.
## Real renderer needed (no --headless). With --fixed-fps 60 one frame is one sweep step; without it the steps follow the wall clock.
##
##   python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/descent_fx_shots.gd -- \
##       --chapter1-trial=descent --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --chapter1-descent-cost=1000 \
##       --element=ember --enemies=70 --shots=_local/shots/d24-fx --tag=ember
## Options: --element=ember|frost|arc  --steps=14,24,30,...  (sweep steps to take a picture at; default per element)  --enemies=N
##   --source=fake|core  --perf=<repeats> (frame times, no pictures: idle / sweep / tail p50 p95 max)  --projectiles=N (fake ones, drawn only)
##   --cutin-shot (fake source) one picture of the cut-in mid-slide, then stop   --out=<json under _local/>  --first-wait=<frames>  --every=<n> (only every n-th default step)
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

var gen: RefCounted
var sim_step := -1          # -1 idle, 0 released, 1.. steps
var sim_total := 0
var acc := 0.0
var wall_clock_steps := true
var frame_ms: Array = []
var phase_ms := {"idle": [], "sweep": [], "tail": []}
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
		elif arg.begins_with("--every="): every = maxi(1, int(arg.trim_prefix("--every=")))
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
	if cutin_shot:
		# the cut-in alone: the core's mode is set to "descent" by this tool for a moment (the presenter's clock runs in that mode only)
		run.mode = "descent"
		fx.consume([{"type": "descent_called", "seq": 99999, "tick": run.tick, "element": element, "variant": "long", "position": run.hero.position, "center": run.hero.position}])
		for i in 26: await process_frame
		await RenderingServer.frame_post_draw
		save_shot(90, 0, fx)
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
		(phase_ms[phase] as Array).append(ms)
		if ms > 50.0 and phase != "idle": spikes.append([snappedf(ms, 0.1), sim_step])
	_last_us = now
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

func save_shot(index: int, step: int, fx: RefCounted) -> void:
	if shots_dir.is_empty(): return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(shots_dir))
	var image := root.get_viewport().get_texture().get_image()
	var file := "%s-%02d-s%03d.png" % [tag, index, step]
	var path := shots_dir.path_join(file)
	image.save_png(ProjectSettings.globalize_path("res://").path_join(path))
	var st: Dictionary = fx.status()
	print("DESCENT_SHOT ", JSON.stringify({"file": path, "step": step, "t": snappedf(float(st.sweep_t), 0.001), "element": element, "demon": snappedf(float(st.demon), 0.01),
		"particles": st.stats.particles, "lights_peak": st.stats.lights_peak, "bolts": st.bolts, "w": image.get_width(), "h": image.get_height()}))

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

## The real core's events: the tool presses R once the gauge is full and takes the pictures at the sweep steps it reaches.
func execute_core() -> void:
	var run: RefCounted = view.run
	var fx = view.descent_fx
	var shot_i := 0
	var guard := 0
	var seen_step := -1
	var hold_frames := 0
	while guard < 60 * 60 * 25:
		guard += 1
		await process_frame
		var v: Dictionary = run.descent_view()
		if bool(v.get("enabled", false)) and bool(v.ready) and run.mode == "playing" and not _called:
			_called = true
			view.call_descent()
		if String(v.get("state", "")) == "hold":
			hold_frames += 1
			if hold_frames == 28:
				await RenderingServer.frame_post_draw
				save_shot(90, 0, fx)       # the cut-in, mid-slide (the core stands still in mode "descent")
		if String(v.get("state", "")) == "sweep":
			var s := int(v.sweep_ticks) - int(v.sweep_left_ticks)
			if s != seen_step:
				seen_step = s
				if shot_i < steps.size() and s >= int(steps[shot_i]):
					await RenderingServer.frame_post_draw
					save_shot(shot_i, s, fx)
					shot_i += 1
		if shot_i >= steps.size(): break
	finish(fx)
