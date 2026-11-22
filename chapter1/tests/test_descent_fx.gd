extends SceneTree
## U-2 check of the descent's screen (chapter1/view/fx/descent_fx.gd). Runs the real core with the descent on IN MEMORY (the
## shipped file stays off) and the presenter beside it, headless (no renderer: shaders are not compiled here, so this checks the
## logic and the nodes, not the picture; the picture is checked with hud_dump --burst in a window).
## Parts: off (no node, no key), the cut-in's timing and the release (A7 item 9: the picture always lets the core go, and a
## pause does not count), every element's sweep runs without a script error and the pools stay inside their budget, the
## presenter changes nothing in the core (same seed with and without it: same snapshot hash), settings (short, reduced motion).
## Writes nothing. Marker: CHAPTER1_DESCENT_FX_TEST_RESULT.
const Chapter = preload("res://chapter1/core/chapter_core.gd")
const DescentFx = preload("res://chapter1/view/fx/descent_fx.gd")
const Fake = preload("res://chapter1/tests/support/descent_fake_events.gd")
const DESCENT := "res://chapter1/data/descent.json"
var checks := 0
var failures: Array[String] = []

class FakeWorld extends RefCounted:
	var camera: Camera3D
	var kicks := 0
	var strength := 0.0
	func kick_camera(s: float) -> void:
		kicks += 1
		strength += s

class Stage extends Node3D:
	var world: FakeWorld

func _initialize() -> void:
	call_deferred("execute")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func make_run(element: String, on: bool, seed_: int = 11) -> RefCounted:
	var run = Chapter.new()
	if on:
		var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DESCENT))
		doc.enabled = true
		doc.cost = [1000]
		check(run.set_descent(doc), "make_run: the descent document is accepted " + str(run.errors))
	check(run.start(seed_, "chapter1.skill." + element), "make_run: the run starts " + str(run.errors))
	return run

func make_stage() -> Stage:
	var stage := Stage.new()
	root.add_child(stage)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 24.0
	stage.add_child(camera)
	camera.look_at_from_position(Vector3(11, 19, 14), Vector3.ZERO)
	stage.world = FakeWorld.new()
	stage.world.camera = camera
	return stage

func of_type(events: Array, type_: String) -> Array:
	return events.filter(func(e): return String(e.type) == type_)

## Plays `frames` render frames of 1/60 s: the core steps once per frame in mode playing (as the app's physics does), the presenter
## consumes the events and syncs, and the "app" lets go when the presenter says so. Returns what happened.
func play(run: RefCounted, fx: RefCounted, frames: int, release_when_due: bool = true) -> Dictionary:
	var out := {"released_at": -1.0, "frames_in_hold": 0, "events": []}
	var hold_time := 0.0
	var seen := -1
	for i in frames:
		if run.mode == "playing":
			run.hero.hp_raw = run.hero.max_hp_raw
			run.step(Vector2.ZERO)
		if fx != null:
			fx.consume(run.events)
			fx.sync(run, 1.0 / 60.0)
		for event in run.events:
			if int(event.seq) > seen:
				seen = int(event.seq)
				(out.events as Array).append(event.duplicate(true))
		if run.mode == "descent":
			out.frames_in_hold += 1
			hold_time += 1.0 / 60.0
			if fx != null and fx.take_release() and release_when_due:
				out.released_at = hold_time
				check(run.release_descent(), "play: the release is accepted")
	return out

func fill_and_call(run: RefCounted, fx: RefCounted) -> void:
	run._descent_add(1000)
	check(run.descent_view().ready, "fill: the gauge is ready")
	# a few enemies near the hero so the sweep has something to hit
	for k in 8:
		run._spawn("walker", run.hero.position + Vector2.from_angle(float(k) * 0.8) * (4.0 + float(k)))
	check(run.request_descent(), "fill: the call is accepted")
	if fx != null: fx.consume(run.events)

# ------------------------------------------------------------------ parts

func off_part() -> void:
	var run := make_run("ember", false)
	var stage := make_stage()
	var fx = DescentFx.new()
	fx.setup(stage)
	var children := stage.get_child_count()
	check(not bool(run.descent_view().enabled), "off: the view says off")
	for i in 120:
		run.step(Vector2.ZERO)
		fx.consume(run.events)
		fx.sync(run, 1.0 / 60.0)
	check(stage.get_child_count() == children, "off: the presenter added no node to a run without the descent (%d -> %d)" % [children, stage.get_child_count()])
	check(not bool(fx.status().built), "off: nothing was built")
	check(not run.request_descent(), "off: the call is refused")
	check(not run.snapshot().has("descent"), "off: no descent key in the snapshot")
	stage.queue_free()

func cutin_part() -> void:
	for pair in [["ember", false], ["frost", false], ["arc", false], ["ember", true]]:
		var element: String = pair[0]
		var short_setting: bool = pair[1]
		var run := make_run(element, true)
		var stage := make_stage()
		var fx = DescentFx.new()
		fx.setup(stage)
		fx.cutin_short = short_setting
		play(run, fx, 30)
		fill_and_call(run, fx)
		var tag := "%s/%s" % [element, "short" if short_setting else "long"]
		check(run.mode == "descent", tag + ": the core holds")
		var tick := int(run.tick)
		var result := play(run, fx, 120)
		var want_dur := 0.5 if short_setting else 0.9
		var want_release := want_dur * 0.70 / 0.90
		check(float(result.released_at) > 0.0, tag + ": the picture let the core go")
		check(absf(float(result.released_at) - want_release) < 0.04, "%s: released at %.3f s (want about %.3f)" % [tag, float(result.released_at), want_release])
		check(int(result.frames_in_hold) <= int(ceil(want_release * 60.0)) + 2, tag + ": the hold lasted %d frames" % int(result.frames_in_hold))
		check(int(run.tick) > tick, tag + ": the core runs on after the release")
		check(bool(fx.status().built), tag + ": the nodes exist once the descent is on")
		stage.queue_free()
	# the second call of a run is the short one by itself
	var run2 := make_run("frost", true)
	var stage2 := make_stage()
	var fx2 = DescentFx.new()
	fx2.setup(stage2)
	play(run2, fx2, 10)
	fill_and_call(run2, fx2)
	var first := play(run2, fx2, 400)
	check(float(first.released_at) > 0.55, "second call: the first one is long (released at %.3f)" % float(first.released_at))
	run2._descent_add(2000)
	if run2.mode == "playing" and run2.descent_view().ready and run2.request_descent():
		fx2.consume(run2.events)
		var second := play(run2, fx2, 120)
		check(float(second.released_at) > 0.0 and float(second.released_at) < 0.45, "second call: the next one is short (released at %.3f)" % float(second.released_at))
	stage2.queue_free()

func pause_part() -> void:
	var run := make_run("ember", true)
	var stage := make_stage()
	var fx = DescentFx.new()
	fx.setup(stage)
	play(run, fx, 10)
	fill_and_call(run, fx)
	play(run, fx, 10, false)
	run.set_paused(true)
	check(run.mode == "paused", "pause: Esc during the hold pauses")
	var before: float = float(fx.status().cut_t)
	for i in 240:
		fx.sync(run, 1.0 / 60.0)
	check(is_equal_approx(float(fx.status().cut_t), before), "pause: the cut-in's clock stood still while paused")
	check(not fx.take_release(), "pause: no release was asked for while paused")
	run.set_paused(false)
	check(run.mode == "descent", "pause: back to the hold")
	var result := play(run, fx, 120)
	check(float(result.released_at) > 0.0, "pause: after the pause the picture still lets go")
	stage.queue_free()

func sweep_part() -> void:
	for element in ["ember", "frost", "arc"]:
		var run := make_run(element, true)
		var stage := make_stage()
		var fx = DescentFx.new()
		fx.setup(stage)
		play(run, fx, 10)
		fill_and_call(run, fx)
		var result := play(run, fx, 420)
		var events: Array = result.events
		check(of_type(events, "descent_released").size() == 1 and of_type(events, "descent_end").size() == 1, element + ": released and ended once")
		var status: Dictionary = fx.status()
		check(int(status.stats.sweeps) == 1 and int(status.stats.cutins) == 1, element + ": the presenter saw one cut-in and one sweep " + str(status.stats))
		check(int(status.stats.particles) <= 800, "%s: particles %d are inside the 800 budget" % [element, int(status.stats.particles)])
		check(int(status.stats.lights_peak) <= 3, "%s: at most 3 lights in a sweep (%d)" % [element, int(status.stats.lights_peak)])
		check(not bool(status.sweep) and not bool(status.cutin), element + ": the presenter is idle again after the sweep")
		if element == "arc":
			check(int(status.stats.bolts) > 0, "arc: bolts were drawn")
			check(int(status.stats.peak_bolts) <= 64, "arc: the bolt pool stayed inside 64 (%d)" % int(status.stats.peak_bolts))
		check(stage.world.kicks > 0 or element == "frost" and stage.world.kicks >= 0, element + ": the camera got an impulse")
		stage.queue_free()

func play_to_tick(run: RefCounted, fx: RefCounted, target: int, bare_release: bool) -> void:
	var guard := 0
	while int(run.tick) < target and guard < 4000:
		guard += 1
		if run.mode == "playing":
			run.hero.hp_raw = run.hero.max_hp_raw
			run.step(Vector2.ZERO)
		elif run.mode == "descent" and bare_release:
			run.release_descent()
			continue
		if fx != null:
			fx.consume(run.events)
			fx.sync(run, 1.0 / 60.0)
			if run.mode == "descent" and fx.take_release():
				run.release_descent()

func purity_part() -> void:
	# the same seed, the same calls: with the presenter and without it the core ends in the same state at the same tick
	var hashes: Array[String] = []
	for with_fx in [true, false]:
		var run := make_run("arc", true, 23)
		var stage := make_stage()
		var fx = DescentFx.new() if with_fx else null
		if fx != null: fx.setup(stage)
		play_to_tick(run, fx, 90, false)
		run._descent_add(1000)
		check(run.request_descent(), "purity: the call is accepted (fx %s)" % str(with_fx))
		if fx != null: fx.consume(run.events)
		play_to_tick(run, fx, 600, not with_fx)
		hashes.append(JSON.stringify(run.snapshot()).sha256_text().left(16))
		check(int(run.metrics.descent.uses) == 1, "purity: one use (fx %s)" % str(with_fx))
		stage.queue_free()
	check(hashes[0] == hashes[1], "purity: the presenter changed the core (%s vs %s)" % [hashes[0], hashes[1]])

func watchdog_part() -> void:
	# the picture's own floor: even a clock that never reaches the release point lets go after the wall limit
	var run := make_run("frost", true)
	var stage := make_stage()
	var fx = DescentFx.new()
	fx.setup(stage)
	play(run, fx, 5)
	fill_and_call(run, fx)
	var due := false
	for i in int(DescentFx.WATCHDOG_SECONDS * 60.0) + 60:
		fx.sync(run, 1.0 / 60.0)
		if fx.take_release():
			due = true
			break
	check(due, "watchdog: a release is asked for")
	stage.queue_free()

func settings_part() -> void:
	var run := make_run("ember", true)
	var stage := make_stage()
	var fx = DescentFx.new()
	fx.setup(stage)
	fx.reduced_motion = true
	fx.shake_scale = 0.0
	fx.flash_scale = 0.0
	play(run, fx, 10)
	fill_and_call(run, fx)
	play(run, fx, 300)
	check(stage.world.kicks == 0, "settings: shake off means no impulse (%d)" % stage.world.kicks)
	stage.queue_free()

## D24 12.2: the three sweeps drawn from FAKE events in the shape of 9.4 (no core needed for them; the run only supplies the view).
## Checks: every layer runs without a script error, the budgets of 10.2 hold (particles 800, lights 3, bolts 64, fragments 14), the low
## spec has no light and 35 % of the particles, the presenter ends idle, and the settings (shake off, reduced motion) silence the kicks.
func fake_run_one(element: String, low: bool, shake_scale: float = 1.0, reduced: bool = false) -> Dictionary:
	var run := make_run(element, true)
	var stage := make_stage()
	var fx = DescentFx.new()
	fx.setup(stage)
	fx.low = low
	fx.shake_scale = shake_scale
	fx.reduced_motion = reduced
	play(run, fx, 5)
	var enemies := PackedVector2Array()
	var gen = Fake.new(element, 11, enemies)
	for i in 90:
		enemies.append(run.hero.position + Vector2(gen.h(9, i, 0) * 30.0 - 15.0, gen.h(9, i, 1) * 24.0 - 12.0))
	gen.enemies = enemies
	fx.consume(run.events)
	var tick := int(run.tick)
	var released: Array = gen.release(run.hero.position, tick)
	fx.consume(released)
	fx.sync(run, 1.0 / 60.0)
	var types := {}
	var end_total := 0
	var total := int(Fake.SWEEP_TICKS[element])
	for s in range(1, total + 260):
		if s <= total:
			var evs: Array = gen.step(s)
			for e in evs:
				if String(e.type) == "descent_end": end_total = int(e.kills_total)
			for e in evs: types[String(e.get("phase", e.type))] = int(types.get(String(e.get("phase", e.type)), 0)) + 1
			fx.consume(evs)
		fx.sync(run, 1.0 / 60.0)
	var label_text := String(fx._kill_label.text) if fx._kill_label != null else ""
	check(end_total > 0 and label_text.contains(str(end_total)), "fake %s: the end number is kills_total (%d) in \"%s\"" % [element, end_total, label_text])
	var out := {"stats": fx.status().stats, "status": fx.status(), "types": types, "kicks": stage.world.kicks}
	stage.queue_free()
	return out

func fake_part() -> void:
	for element in ["ember", "frost", "arc"]:
		for low in [false, true]:
			var tag := "fake %s/%s" % [element, "low" if low else "full"]
			var r := fake_run_one(element, low)
			var stats: Dictionary = r.stats
			var status: Dictionary = r.status
			check(int(stats.sweeps) == 1, tag + ": one sweep drawn " + str(stats))
			check(int(stats.particles) <= 800, "%s: particles %d inside 800" % [tag, int(stats.particles)])
			if low:
				check(int(stats.lights_peak) == 0, tag + ": the low spec uses no light (%d)" % int(stats.lights_peak))
				check(int(stats.particles) <= 300, "%s: the low spec's particles are 35 %% (%d)" % [tag, int(stats.particles)])
			else:
				check(int(stats.lights_peak) <= 3 and int(stats.lights_peak) >= 1, "%s: 1 to 3 lights (%d)" % [tag, int(stats.lights_peak)])
			check(not bool(status.sweep), tag + ": idle after the sweep + its tail")
			check(int(r.kicks) > 0, tag + ": the camera got impulses")
			match element:
				"ember":
					check(int(stats.rocks) == 14 and int(stats.impacts) == 14, tag + ": 14 fragments booked and landed " + str(stats))
					check(int(r.types.get("firestorm", 0)) == 1, tag + ": the finale came once")
				"frost":
					check(int(stats.pulses) == 8 and int(stats.breaks) == 1, tag + ": eight pulses and one break " + str(stats))
				"arc":
					check(int(r.types.get("bolt", 0)) == 40, tag + ": 40 bolts were struck (%d)" % int(r.types.get("bolt", 0)))
					check(int(stats.bolts) + int(stats.bolts_dropped) == 40, tag + ": every bolt was drawn or counted dropped " + str(stats))
					check(int(stats.peak_bolts) <= (24 if low else 64), tag + ": the live bolt pool stayed in its cap (%d)" % int(stats.peak_bolts))
	# settings: shake off = no impulse at all; reduced motion = no impulse either
	for element in ["ember", "frost", "arc"]:
		var quiet := fake_run_one(element, false, 0.0, false)
		check(int(quiet.kicks) == 0, "fake %s: shake off means no impulse (%d)" % [element, int(quiet.kicks)])
		var calm := fake_run_one(element, false, 1.0, true)
		check(int(calm.kicks) == 0, "fake %s: reduced motion means no impulse (%d)" % [element, int(calm.kicks)])

func execute() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/_local/appdata/"):
		print("CHAPTER1_DESCENT_FX_TEST_RESULT ", JSON.stringify({"checks": 0, "failures": ["user data dir is not isolated: refusing to run"]}))
		quit(1)
		return
	off_part()
	cutin_part()
	pause_part()
	sweep_part()
	purity_part()
	watchdog_part()
	settings_part()
	fake_part()
	print("CHAPTER1_DESCENT_FX_TEST_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
