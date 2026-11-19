extends SceneTree
## U-1 check of the descent (D15 A, chapter1/data/descent.json). Every document is switched on IN MEMORY (set_descent); the
## shipped file stays off. Parts: off (nothing changes), validator, gauge (one event at a time), the stop (mode "descent",
## no tick), the three element shapes, strong enemies, the trial's cap, the end tick (orbs, items, level choice), the hero's
## invulnerability, the spawn breath, the view and the events, determinism. Writes nothing.
## Not covered here: the app calling release_descent() after the cut-in (A7 item 9; there is no cut-in layer yet, U-2).
## Marker: CHAPTER1_DESCENT_TEST_RESULT.
const Chapter = preload("res://chapter1/core/chapter_core.gd")
const Pilot = preload("res://chapter1/core/chapter_pilot.gd")
const Policy = preload("res://chapter1/tests/descent_policy.gd")
const DESCENT := "res://chapter1/data/descent.json"
const TUNING := "res://chapter1/data/combat_tuning.json"
const SPELLS := "res://chapter1/data/run_spells.json"
const UNIT := 256
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("execute")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func shipped() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(DESCENT))

func doc_on(mutate: Callable = Callable()) -> Dictionary:
	var doc := shipped()
	doc.enabled = true
	if mutate.is_valid(): mutate.call(doc)
	return doc

## A quiet stage: nothing spawns, the hero casts nothing (so only the descent kills), enemies stand still, and the hero's life is
## topped up by tick_run(). `tuning_mutate` / `spells` / `with_rhythm` change the other documents of the run.
func stage(element: String, mutate: Callable = Callable(), seed_: int = 11, spells: bool = false, tuning_mutate: Callable = Callable(), slow_xp: bool = true) -> RefCounted:
	var run = Chapter.new()
	if tuning_mutate.is_valid() or slow_xp:
		var tuning: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TUNING))
		# Orbs of the killed enemies would open the card screen in the middle of a sweep; the thresholds are far away unless asked.
		if slow_xp:
			var far: Array = []
			for i in 12: far.append(i * 90000)
			tuning.xp_thresholds = far
		if tuning_mutate.is_valid(): tuning_mutate.call(tuning)
		check(run.set_tuning(tuning), "stage: the tuning is accepted " + str(run.errors))
	if spells:
		var spells_doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SPELLS))
		spells_doc.enabled = true
		check(run.set_run_spells(spells_doc), "stage: the spell document is accepted " + str(run.errors))
	check(run.set_descent(doc_on(mutate)), "stage: the descent document is accepted " + str(run.errors))
	check(run.start(seed_, "chapter1.skill." + element), "stage: the run starts " + str(run.errors))
	run.first_boss_kill = true
	run.enemies.clear()
	run._alive = 0
	run._next_spawn = 1 << 30
	for id_ in run._skill_ids: run._next_cast[id_] = 1 << 30
	return run

func put(run: RefCounted, position: Vector2, kind: String = "walker") -> int:
	check(run._spawn(kind, position), "put: spawned")
	var id_: int = run._enemy_sequence
	run.enemies[id_].definition.speed = 0.0
	return id_

func put_strong(run: RefCounted, position: Vector2, role: String = "champion") -> int:
	var id_ := put(run, position, "elite")
	var e: Dictionary = run.enemies[id_]
	var life: int = int({"champion": 1400, "boss": 4500, "elite": 600}[role]) * UNIT
	e.hp_raw = life
	e.max_hp_raw = life
	if role == "champion": e.title_key = "enemy.champion.0.name"
	if role == "boss": e.chapter_boss = true
	return id_

func mark(e: Dictionary, count: int) -> void:
	e.status = {"heat": {"n": count, "src": "test", "until": 1 << 30, "by": {}}}

## n ticks with the hero topped up; the events of every tick, in order.
func tick_run(run: RefCounted, n: int) -> Array:
	var out: Array = []
	for i in n:
		if run.mode != "playing": break
		run.hero.hp_raw = run.hero.max_hp_raw
		run.step(Vector2.ZERO)
		out.append_array(run.events.duplicate(true))
	return out

func of_type(events: Array, type: String) -> Array:
	return events.filter(func(e): return e.type == type)

func ready(run: RefCounted) -> void:
	run._descent_add(int(run.descent.cost[0]))

## Call, release, and play the whole sweep (+ extra ticks). Returns {called, events, start}.
func fire(run: RefCounted, extra: int = 0) -> Dictionary:
	check(run.request_descent(), "fire: the call is accepted")
	var called: Array = of_type(run.events, "descent_called")
	check(run.release_descent(), "fire: the release is accepted")
	var start: int = run.tick
	var ticks := int(run.descent.elements[run._d_element].sweep_ticks) + extra
	return {"called": called[called.size() - 1] if called.size() > 0 else {}, "events": tick_run(run, ticks), "start": start}

## Enemies on a square grid inside the circle (step `gap`, at most `limit` of them, nearest the corner first is not wanted: row order).
func grid(run: RefCounted, gap: float, half: int, limit: int = 1 << 20, centre: Vector2 = Vector2.ZERO) -> Array:
	var ids: Array = []
	for ix in range(-half, half + 1):
		for iy in range(-half, half + 1):
			var p := centre + Vector2(ix, iy) * gap
			if p.length() < 1.0 or p.length() > 12.5 or ids.size() >= limit: continue
			ids.append(put(run, p))
	return ids

func alive_ids(run: RefCounted, ids: Array) -> Array:
	return ids.filter(func(i): return run.enemies.has(i) and run.enemies[i].hp_raw > 0)

# ------------------------------------------------------------------ off

func off_checks() -> void:
	var run = Chapter.new()
	check(run.start(11, "chapter1.skill.ember"), "off: the run starts with the shipped file")
	check(not shipped().enabled, "off: the shipped descent.json says enabled:false")
	check(not run.request_descent(), "off: request_descent() is false")
	check(not run.release_descent(), "off: release_descent() is false")
	check(run.descent_view() == {"enabled": false}, "off: descent_view() is {enabled:false}: " + str(run.descent_view()))
	check(not run.snapshot().has("descent"), "off: no descent key in the snapshot")
	check(not run.metrics.has("descent"), "off: no descent metrics")
	# Off by an explicit disabled document and off by the shipped file are the same run.
	var other = Chapter.new()
	var disabled := shipped()
	disabled.enabled = false
	check(other.set_descent(disabled), "off: a disabled document is accepted")
	check(other.start(11, "chapter1.skill.ember"), "off: the run starts with a disabled document")
	var pilot_a = Pilot.new()
	pilot_a.run = run
	var pilot_b = Pilot.new()
	pilot_b.run = other
	for i in 900:
		run.step(pilot_a.decide())
		other.step(pilot_b.decide())
	check(JSON.stringify(run.snapshot()).sha256_text() == JSON.stringify(other.snapshot()).sha256_text(), "off: shipped file and a disabled document give the same snapshot after 900 ticks")
	var requested := false
	for i in 20:
		requested = requested or run.request_descent()
	check(not requested and run.mode == "playing", "off: no call ever stops the core")

# ------------------------------------------------------------------ validator

func rejects(label: String, mutate: Callable) -> void:
	var doc := shipped()
	mutate.call(doc)
	var run = Chapter.new()
	var ok: bool = run.set_descent(doc)
	var named := false
	for line in run.errors:
		if String(line).begins_with("descent"): named = true
	check(not ok and named, "validator refuses: " + label + " " + str(run.errors))

func validator_checks() -> void:
	var run = Chapter.new()
	check(run.set_descent(shipped()), "validator: the shipped document is accepted")
	check(run.set_descent(doc_on()), "validator: the enabled document is accepted")
	rejects("not a dictionary", func(d): d.clear())
	rejects("unknown root key", func(d): d.extra = 1)
	rejects("missing root key", func(d): d.erase("crown"))
	rejects("enabled as a number", func(d): d.enabled = 1)
	rejects("schema_version 2", func(d): d.schema_version = 2)
	rejects("empty cost", func(d): d.cost = [])
	rejects("seven costs", func(d): d.cost = [1000, 1000, 1000, 1000, 1000, 1000, 1000])
	rejects("cost 999", func(d): d.cost = [999])
	rejects("cost 30001", func(d): d.cost = [30001])
	rejects("a point of 2001", func(d): d.points.vs_cc_hit = 2001)
	rejects("a negative point", func(d): d.points.detonate = -1)
	rejects("kill_by_beat naming a beat that does not exist", func(d): d.points.kill_by_beat.slow = 3)
	rejects("kill_by_beat empty", func(d): d.points.kill_by_beat = {})
	rejects("a point key missing", func(d): d.points.erase("elite_kill"))
	rejects("reach 5.9", func(d): d.reach_m = 5.9)
	rejects("reach 19.1", func(d): d.reach_m = 19.1)
	rejects("trial_kill_cap 181", func(d): d.normal.trial_kill_cap = 181)
	rejects("strong bps 10001", func(d): d.strong.boss_bps = 10001)
	rejects("cut_windup_ticks 0", func(d): d.strong.cut_windup_ticks = 0)
	rejects("after.iframe_ticks 601", func(d): d.after.iframe_ticks = 601)
	rejects("ember heading 181", func(d): d.elements.ember.heading_deg = 181.0)
	rejects("ember sweep_ticks 0", func(d): d.elements.ember.sweep_ticks = 0)
	rejects("ember sweep_ticks 601", func(d): d.elements.ember.sweep_ticks = 601)
	rejects("frost break after the sweep", func(d): d.elements.frost.break_at_ticks = 46)
	rejects("arc round longer than the sweep", func(d): d.elements.arc.round_ticks = 61)
	rejects("arc per_round 0", func(d): d.elements.arc.per_round = 0)
	rejects("arc per_round 65", func(d): d.elements.arc.per_round = 65)
	rejects("arc spread_m 14", func(d): d.elements.arc.spread_m = 14.0)
	rejects("an element missing", func(d): d.elements.erase("arc"))
	rejects("an unknown element", func(d): d.elements.stone = {})
	rejects("blocked_phases with a stranger", func(d): d.blocked_phases = ["night"])
	rejects("blocked_phases not an array", func(d): d.blocked_phases = "trial")
	rejects("crown with two charge values", func(d): d.crown.charge_bps = [1000, 2000])
	rejects("crown power_bps 9999", func(d): d.crown.power_bps = 9999)
	# a refused document changes nothing: the run keeps the parked one
	var holder = Chapter.new()
	holder.set_descent(doc_on(func(d): d.cost = [1234]))
	var bad := shipped()
	bad.cost = []
	check(not holder.set_descent(bad), "validator: the broken document is refused")
	check(holder.start(11, "chapter1.skill.ember") and int(holder.descent.cost[0]) == 1234, "validator: a refused document left the parked one alone")

# ------------------------------------------------------------------ gauge

func gauge(run: RefCounted) -> int:
	return int(run.descent_view().gauge)

func gauge_checks() -> void:
	# rhythm off: an ordinary kill is kill_default
	var run := stage("ember")
	run._emit("death", Vector2(999, 999), {"target_id": 1, "kind": "walker", "elite": false, "role": "normal"})
	check(gauge(run) == 5, "gauge: a kill with the rhythm off gives kill_default 5 (%d)" % gauge(run))
	run._emit("death", Vector2(999, 999), {"target_id": 1, "kind": "elite", "elite": true, "role": "elite"})
	check(gauge(run) == 405, "gauge: an elite kill gives 400 (%d)" % gauge(run))
	run._emit("death", Vector2(999, 999), {"target_id": 1, "kind": "elite", "elite": true, "role": "champion"})
	check(gauge(run) == 1205, "gauge: a guardian kill gives 800 (%d)" % gauge(run))
	run._emit("hero_hit", Vector2.ZERO, {"damage_raw": 1000})
	check(gauge(run) == 1205, "gauge: a hit on the hero changes nothing")
	# a combination hit and a detonation
	var combo := stage("ember")
	combo._emit("hit", Vector2.ZERO, {"target_id": 0, "vs_cc": "frozen", "dealt_raw": 0})
	check(gauge(combo) == 20, "gauge: a vs_cc hit gives 20 (%d)" % gauge(combo))
	combo._emit("detonate", Vector2.ZERO, {"target_id": 0})
	check(gauge(combo) == 50, "gauge: a detonation gives 30 (%d)" % gauge(combo))
	combo.tick += 1
	for i in 40: combo._emit("detonate", Vector2.ZERO, {"target_id": 0})
	check(gauge(combo) == 50 + 300, "gauge: combination points stop at 300 within one tick (%d)" % gauge(combo))
	combo.tick += 1
	combo._emit("detonate", Vector2.ZERO, {"target_id": 0})
	check(gauge(combo) == 50 + 330, "gauge: the next tick counts again (%d)" % gauge(combo))
	# one percent of a guardian's life, with the remainder carried
	var strong := stage("ember")
	var champion := put_strong(strong, Vector2(20, 0))
	var life: int = strong.enemies[champion].max_hp_raw
	strong._emit("hit", Vector2.ZERO, {"target_id": champion, "dealt_raw": life / 100})
	check(gauge(strong) == 10, "gauge: 1 percent of a guardian's life gives 10 (%d)" % gauge(strong))
	strong._emit("hit", Vector2.ZERO, {"target_id": champion, "dealt_raw": life / 200})
	check(gauge(strong) == 10, "gauge: half a percent gives nothing yet (%d)" % gauge(strong))
	strong._emit("hit", Vector2.ZERO, {"target_id": champion, "dealt_raw": life / 200})
	check(gauge(strong) == 20, "gauge: the carried halves make another 10 (%d)" % gauge(strong))
	var walker := put(strong, Vector2(20, 5))
	strong._emit("hit", Vector2.ZERO, {"target_id": walker, "dealt_raw": 5})
	check(gauge(strong) == 20, "gauge: damage to an ordinary enemy gives nothing")
	# the beat table, with the rhythm on
	var rhythm := stage("ember", Callable(), 11, false, func(t): t.rhythm.enabled = true)
	rhythm.step(Vector2.ZERO)
	check(String(rhythm.run_progress().beat_id) == "gi", "gauge: the first beat is gi")
	rhythm._emit("death", Vector2(999, 999), {"target_id": 1, "kind": "walker", "elite": false, "role": "normal"})
	check(gauge(rhythm) == 16, "gauge: a kill in gi gives 16 (%d)" % gauge(rhythm))
	rhythm._trial_phase = "hold"
	rhythm._emit("death", Vector2(999, 999), {"target_id": 1, "kind": "walker", "elite": false, "role": "normal"})
	check(gauge(rhythm) == 18, "gauge: a kill in the trial gives 2 (%d)" % gauge(rhythm))
	# ready, then the overflow is thrown away
	var full := stage("ember", func(d): d.cost = [1000, 2000])
	full._descent_add(990)
	check(gauge(full) == 990 and not bool(full.descent_view().ready), "gauge: below the cost it is not ready")
	full._descent_add(30)
	var view: Dictionary = full.descent_view()
	check(int(view.gauge) == 1000 and bool(view.ready) and view.state == "ready" and int(view.ratio_bps) == 10000, "gauge: it fills to the cost and is ready: " + str(view))
	check(int(full.snapshot().descent.wasted) == 20, "gauge: the part over the cost is wasted (20): " + str(full.snapshot().descent.wasted))
	var ready_events: Array = of_type(full.events, "descent_ready")
	check(ready_events.size() == 1 and int(ready_events[0].uses) == 0 and int(ready_events[0].cost) == 1000, "gauge: descent_ready came once with {uses, cost}: " + str(ready_events))
	full._descent_add(500)
	check(gauge(full) == 1000 and int(full.snapshot().descent.wasted) == 520 and of_type(full.events, "descent_ready").size() == 1, "gauge: a ready gauge only wastes (520)")
	check(int(full.metrics.descent.wasted) == 520, "gauge: metrics.descent.wasted follows")
	# the cost rises with each use; from the last entry on it stays
	check(full.request_descent() and full.release_descent(), "gauge: the call and the release are accepted")
	check(int(full.descent_view().cost_now) == 2000 and int(full.descent_view().uses) == 1 and gauge(full) == 0, "gauge: after one use the next cost is 2000 and the gauge is empty")
	full._d_sweep = {}
	full._d_uses = 5
	check(int(full.descent_view().cost_now) == 2000, "gauge: past the table the last cost repeats")
	# nothing counts from the call until the end of the sweep
	var quiet := stage("ember")
	ready(quiet)
	var before := gauge(quiet)
	quiet.request_descent()
	quiet._emit("death", Vector2(999, 999), {"target_id": 1, "kind": "walker", "elite": false, "role": "normal"})
	check(gauge(quiet) == before, "gauge: no point while the descent is called")
	# a run with one spell never gets combination points (no other spell puts a control or a status on anything)
	var solo := stage("ember", Callable(), 11, true)
	solo._next_cast.clear()
	solo._next_spawn = 30
	var normal_deaths := 0
	for i in 1800:
		if solo.mode != "playing": break
		solo.hero.hp_raw = solo.hero.max_hp_raw
		solo.step(Vector2.ZERO)
		for e in solo.events:
			if e.type == "death" and e.role == "normal": normal_deaths += 1
	var in_gauge: int = int(solo.metrics.descent.gauge_in) + int(solo.metrics.descent.wasted)
	check(normal_deaths > 0 and in_gauge == normal_deaths * 5, "gauge: one spell alone: only kills fill it (%d deaths, %d points)" % [normal_deaths, in_gauge])
	check(int(solo.metrics.ward.vs_cc_hits) == 0 and int(solo.metrics.detonate.count) == 0, "gauge: one spell alone: no vs_cc hit and no detonation")

# ------------------------------------------------------------------ the stop

func stop_checks() -> void:
	var results: Array = []
	var ticks_seen: Array = []
	for held in [0, 30, 54]:
		var run := stage("frost")
		grid(run, 2.5, 4)
		tick_run(run, 120)
		ready(run)
		var tick_before: int = run.tick
		check(run.request_descent(), "stop: accepted (N=%d)" % held)
		check(run.mode == "descent" and run.descent_view().state == "hold", "stop: mode descent, state hold (N=%d)" % held)
		var hash_before := JSON.stringify(run.snapshot()).sha256_text()
		for i in held: run.step(Vector2.RIGHT)
		check(run.tick == tick_before and JSON.stringify(run.snapshot()).sha256_text() == hash_before, "stop: %d steps changed neither the tick nor the snapshot" % held)
		check(not run.request_descent(), "stop: a second call during the hold is refused")
		check(not run.open_inventory(), "stop: the bag does not open during the hold")
		run.set_paused(true)
		check(run.mode == "paused" and not run.release_descent(), "stop: the pause shows over the hold and nothing is released from it")
		run.set_paused(false)
		check(run.mode == "descent", "stop: back to the hold after the pause")
		check(run.release_descent() and run.mode == "playing", "stop: released")
		check(not run.release_descent(), "stop: a second release is refused")
		tick_run(run, 100)
		results.append(JSON.stringify(run.snapshot()).sha256_text())
		ticks_seen.append(run.tick)
	check(results[0] == results[1] and results[1] == results[2], "stop: the result after the release is the same for N = 0, 30, 54")
	check(ticks_seen[0] == ticks_seen[1] and ticks_seen[1] == ticks_seen[2], "stop: the tick count is the same too (%s)" % str(ticks_seen))
	# not callable when not ready, not playing
	var cold := stage("ember", Callable(), 11, false, Callable(), false)
	check(not cold.request_descent(), "stop: a gauge that is not ready cannot call")
	ready(cold)
	cold.set_paused(true)
	check(not cold.request_descent(), "stop: a paused core cannot call")
	cold.set_paused(false)
	cold._drop_orb(Vector2(2, 0), 30)
	tick_run(cold, 5)
	check(cold.mode == "choice" and not cold.request_descent(), "stop: a core on the card screen cannot call (mode %s)" % cold.mode)
	# blocked phases: a data switch, empty today
	var blocked := stage("ember", func(d): d.blocked_phases = ["trial"])
	ready(blocked)
	blocked._trial_phase = "hold"
	check(not blocked.request_descent(), "stop: blocked_phases [trial] refuses a call in the trial's hold")
	blocked._trial_phase = ""
	check(blocked.request_descent(), "stop: and accepts it outside the trial")
	var open := stage("ember")
	ready(open)
	open._trial_phase = "hold"
	check(open.request_descent(), "stop: with blocked_phases [] the trial's hold does not refuse (the shipped rule)")

# ------------------------------------------------------------------ elements

func element_ember() -> void:
	var run := stage("ember")
	var dir := Vector2.from_angle(deg_to_rad(float(run.descent.elements.ember.heading_deg)))
	var side := dir.orthogonal()
	var line: Dictionary = {}
	for p in [-12.0, -6.0, 0.0, 6.0, 12.0]:
		line[p] = put(run, dir * p + side * (0.5 if p != 0.0 else 2.0))
	var outside := put(run, dir * 14.0)
	var rim := put(run, side * 13.5)
	var far_shot := {"uid": 9001, "position": Vector2(5, 5), "previous": Vector2(5, 5), "direction": Vector2.LEFT, "speed": 4.0, "radius": .16, "skill_id": "hostile.walker", "hostile": true, "damage_raw": 5 * UNIT, "expires": run.tick + 500, "cast_id": 0, "pierce_left": 0, "hit_ids": []}
	run.projectiles.append(far_shot)
	run._hostile_src[9001] = {"id": 1, "kind": "walker"}
	run.chapter_hazards.append({"uid": 77, "position": Vector2(3, 3), "radius": 1.8, "started": run.tick, "expires": run.tick + 5000, "damage_raw": 65 * UNIT})
	ready(run)
	var shot := fire(run, 0)
	var called: Dictionary = shot.called
	check(called.element == "ember" and int(called.index) == 1 and called.variant == "long" and is_equal_approx(float(called.reach_m), 13.0), "ember: descent_called carries element, index 1, variant long, reach: " + str(called))
	check(int(called.normals_in_reach) == 5 and int(called.strongs_in_reach) == 0 and int(called.marks_in_reach) == 0 and not bool(called.in_trial) and not bool(called.boss_alive), "ember: descent_called counts 5 ordinary enemies in reach and no mark: " + str(called))
	var events: Array = shot.events
	for p in line:
		var id_: int = line[p]
		check(run.enemies[id_].hp_raw <= 0, "ember: the enemy at %.0f m along the heading is dead" % p)
		var death: Array = events.filter(func(e): return e.type == "death" and int(e.target_id) == id_)
		var expected := ceili((float(p) + 13.0) * 60.0 / 26.0)
		check(death.size() == 1 and absi(int(death[0].tick) - int(shot.start) - maxi(1, expected)) <= 1, "ember: the wall reaches %.0f m on step %d (died on step %d)" % [p, maxi(1, expected), (int(death[0].tick) - int(shot.start)) if death.size() == 1 else -1])
	check(run.enemies[outside].hp_raw > 0 and run.enemies[rim].hp_raw > 0, "ember: enemies beyond 13 m are left alone")
	check(run.projectiles.filter(func(p): return p.hostile).is_empty() and not run._hostile_src.has(9001), "ember: the enemy shot is gone and forgotten")
	check(run.chapter_hazards.size() == 1, "ember: the boss's floor strike stays")
	var released: Array = of_type(events, "descent_released")
	check(released.size() == 1 and int(released[0].tick) == int(shot.start) + 1 and int(released[0].cleared_shots) == 1 and released[0].heading.is_equal_approx(dir) and int(released[0].sweep_ticks) == 60, "ember: descent_released one tick after the release with the heading and 1 shot cleared: " + str(released))
	var strikes: Array = of_type(events, "descent_strike")
	var phases_ok := strikes.size() > 0
	var steps_up := true
	var last_step := 0
	for s in strikes:
		phases_ok = phases_ok and (s.phase == "wall" or s.phase == "sweep_end") and s.target_ids.size() <= 64 and s.positions.size() == s.target_ids.size()
		steps_up = steps_up and int(s.step) >= last_step
		last_step = int(s.step)
	check(phases_ok and steps_up, "ember: strikes are wall / sweep_end events with matching positions and ids, in step order")
	var ends: Array = of_type(events, "descent_end")
	check(ends.size() == 1 and int(ends[0].kills) == 5 and int(ends[0].duration_ticks) == 60 and int(ends[0].strong_hits) == 0 and int(ends[0].refund) == 0, "ember: descent_end reports 5 kills in 60 ticks: " + str(ends))
	check(int(ends[0].get("marks_taken", -1)) == 0, "ember: no marks taken without marks")
	# one that slips behind the wall is caught on the last tick
	var late := stage("ember")
	var behind := put(late, Vector2.ZERO)
	late.enemies[behind].position = Vector2(15, 15)
	ready(late)
	late.request_descent()
	late.release_descent()
	var start_late: int = late.tick
	tick_run(late, 40)
	late.enemies[behind].position = dir * -10.0
	var rest := tick_run(late, 25)
	var late_death: Array = rest.filter(func(e): return e.type == "death")
	check(late_death.size() == 1 and int(late_death[0].tick) == start_late + 60, "ember: an enemy behind the wall dies on the last tick (tick %d, expected %d)" % [int(late_death[0].tick) if late_death.size() == 1 else -1, start_late + 60])
	var ends_late: Array = of_type(rest, "descent_strike").filter(func(e): return e.phase == "sweep_end")
	check(ends_late.size() == 1, "ember: that catch is a sweep_end strike")

func element_frost() -> void:
	var run := stage("frost")
	var near := put(run, Vector2(4, 0))
	var far := put(run, Vector2(-9, 6))
	var champion := put_strong(run, Vector2(0, -7))
	var windup: Dictionary = run.enemies[champion]
	windup.state = "windup"
	windup.state_until = run.tick + 50
	windup.telegraph = {"remaining_ticks": 50}
	ready(run)
	run.request_descent()
	run.release_descent()
	var start: int = run.tick
	tick_run(run, 2)
	check(run.tick < int(run.enemies[near].frozen_until) and run.tick < int(run.enemies[far].frozen_until), "frost: everything in reach is frozen on the first tick")
	check(run.tick < int(run.enemies[champion].frozen_until) and int(run.enemies[champion].frozen_until) <= run.tick + 30, "frost: the strong one is frozen for at most 30 ticks")
	check(windup.state == "recover" and windup.telegraph.is_empty(), "frost: the strong one's windup was cut (state %s)" % windup.state)
	check(run.enemies[near].hp_raw > 0 and run.enemies[far].hp_raw > 0, "frost: nobody is hit before the break")
	tick_run(run, 7)
	var newcomer := put(run, Vector2(6, 6))
	tick_run(run, 1)
	check(run.tick < int(run.enemies[newcomer].frozen_until), "frost: one that comes in during the sweep is frozen on the tick it is there")
	var events := tick_run(run, 45 - (run.tick - start))
	var deaths: Array = of_type(events, "death")
	check(deaths.size() == 3 and deaths.all(func(e): return int(e.tick) == start + 45), "frost: all three ordinary enemies break on tick start+45: " + str(deaths.map(func(e): return int(e.tick) - start)))
	check(of_type(events, "descent_strike").any(func(e): return e.phase == "break" and e.target_ids.size() == 4), "frost: one break strike names every frozen body (4)")
	var life := 1400 * UNIT
	check(int(run.enemies[champion].hp_raw) == life - life * 1200 / 10000, "frost: the guardian lost 12 percent of its life, once (%d of %d)" % [int(run.enemies[champion].hp_raw), life])
	check(int(of_type(events, "hit").filter(func(e): return int(e.target_id) == champion).size()) == 1, "frost: and was struck exactly once")
	check(of_type(events, "hit").all(func(e): return String(e.skill_id) == "descent.frost"), "frost: every hit says descent.frost")
	check(of_type(events, "descent_end").size() == 1, "frost: descent_end at the break tick")
	check(of_type(events, "descent_end").size() == 1 and int(of_type(events, "descent_end")[0].duration_ticks) == 45, "frost: the sweep is 45 ticks long")
	# the trial's cap leaves the rest frozen for 90 ticks
	var trial := stage("frost")
	var crowd := grid(trial, 1.6, 6)
	trial._trial_phase = "hold"
	trial._trial_center = trial.hero.position
	ready(trial)
	var trial_events: Dictionary = fire(trial)
	var dead: Array = crowd.filter(func(i): return trial.enemies[i].hp_raw <= 0)
	check(crowd.size() > 60 and dead.size() == 40, "frost: in the trial hold only 40 of %d ordinary enemies die (%d)" % [crowd.size(), dead.size()])
	var left: Array = alive_ids(trial, crowd)
	check(left.size() == crowd.size() - 40 and left.all(func(i): return int(trial.enemies[i].frozen_until) >= trial.tick + 85), "frost: the ones left are frozen for about 90 ticks more")

func element_arc() -> void:
	var run := stage("arc")
	var crowd := grid(run, 4.0, 3)
	var expected_order := crowd.duplicate()
	expected_order.sort_custom(func(a, b):
		var da: float = run.enemies[a].position.length_squared()
		var db: float = run.enemies[b].position.length_squared()
		return a < b if is_equal_approx(da, db) else da < db)
	var champion := put_strong(run, Vector2(0, 11), "boss")
	var boss: Dictionary = run.enemies[champion]
	boss.state = "windup"
	boss.state_until = run.tick + 40
	boss.telegraph = {"remaining_ticks": 40}
	ready(run)
	var shot := fire(run)
	var strikes: Array = of_type(shot.events, "descent_strike").filter(func(e): return e.phase == "bolt")
	check(strikes.size() > 0 and int(strikes[0].step) == 6 and strikes.all(func(e): return int(e.step) % 6 == 0), "arc: bolts fall on every 6th step (%s)" % str(strikes.map(func(e): return int(e.step))))
	var first_round: Array = strikes[0].target_ids
	check(first_round.size() >= 12 and first_round.slice(0, 12) == expected_order.slice(0, 12), "arc: the first round starts with the nearest 12, nearest first (%d named)" % first_round.size())
	check(crowd.size() > 12 and strikes.size() >= 2, "arc: more rounds follow (%d enemies, %d rounds)" % [crowd.size(), strikes.size()])
	check(alive_ids(run, crowd).is_empty(), "arc: every ordinary enemy in reach is dead by the end")
	var life := 4500 * UNIT
	check(int(boss.hp_raw) == life - life * 800 / 10000, "arc: the boss lost 8 percent, once (%d)" % int(boss.hp_raw))
	check(int(of_type(shot.events, "hit").filter(func(e): return int(e.target_id) == champion).size()) == 1, "arc: and was struck exactly once")
	check(int(boss.get("stunned_until", 0)) > int(shot.start), "arc: it is stunned a moment")
	var lone := stage("arc")
	var lone_boss: Dictionary = lone.enemies[put_strong(lone, Vector2(0, 8), "boss")]
	lone_boss.state = "windup"
	lone_boss.state_until = lone.tick + 40
	lone_boss.telegraph = {"remaining_ticks": 40}
	ready(lone)
	lone.request_descent()
	lone.release_descent()
	tick_run(lone, 7)
	check(lone_boss.state == "recover" and lone_boss.telegraph.is_empty(), "arc: a boss that winds up is cut by the first bolt that reaches it (state %s)" % lone_boss.state)
	# a cluster: each bolt jumps to two neighbours
	var packed := stage("arc")
	var ids: Array = []
	for g in [Vector2(8, 0), Vector2(-6, 6), Vector2(-6, -6)]:
		for k in 5: ids.append(put(packed, g + Vector2(k * 0.8, 0)))
	ready(packed)
	var packed_shot := fire(packed)
	var round_one: Array = of_type(packed_shot.events, "descent_strike").filter(func(e): return e.phase == "bolt")[0].target_ids
	check(round_one.size() > 12 and round_one.size() <= 36, "arc: with neighbours within 3 m the first round reaches more than 12 (%d)" % round_one.size())
	check(alive_ids(packed, ids).is_empty(), "arc: and everyone in the clusters is dead at the end")
	# the trial's cap leaves the rest stunned
	var trial := stage("arc")
	var crowd_t := grid(trial, 1.6, 6)
	trial._trial_phase = "hold"
	trial._trial_center = trial.hero.position
	ready(trial)
	fire(trial)
	var left: Array = alive_ids(trial, crowd_t)
	check(left.size() == crowd_t.size() - 40, "arc: in the trial hold 40 ordinary enemies die (%d left of %d)" % [left.size(), crowd_t.size()])
	check(left.all(func(i): return int(trial.enemies[i].get("stunned_until", 0)) > trial.tick), "arc: the ones left are stunned")

func element_ember_trial() -> void:
	var trial := stage("ember")
	var crowd := grid(trial, 1.6, 6)
	trial._trial_phase = "hold"
	trial._trial_center = trial.hero.position
	ready(trial)
	fire(trial)
	var left: Array = alive_ids(trial, crowd)
	check(crowd.size() - left.size() == 40, "ember: in the trial hold 40 ordinary enemies die (%d of %d)" % [crowd.size() - left.size(), crowd.size()])
	# the cap is data
	var small := stage("ember", func(d): d.normal.trial_kill_cap = 7)
	var group := grid(small, 1.6, 4)
	small._trial_phase = "hold"
	small._trial_center = small.hero.position
	ready(small)
	fire(small)
	check(group.size() - alive_ids(small, group).size() == 7, "ember: normal.trial_kill_cap 7 kills 7")

# ------------------------------------------------------------------ strong enemies and marks

func strong_checks() -> void:
	for pair in [["champion", 1400, 1200], ["boss", 4500, 800], ["elite", 600, 3500]]:
		var run := stage("ember")
		var id_ := put_strong(run, Vector2(3, 0), pair[0])
		ready(run)
		fire(run)
		var e: Dictionary = run.enemies[id_]
		var life: int = int(pair[1]) * UNIT
		check(int(e.hp_raw) == life - life * int(pair[2]) / 10000, "strong: a %s loses %d bps of its maximum life (%d of %d)" % [pair[0], int(pair[2]), int(e.hp_raw), life])
	# marks lift the share: 1.5 points each, at most 6
	for pair in [[0, 1200], [2, 1500], [4, 1800], [9, 1800]]:
		var run := stage("frost")
		var id_ := put_strong(run, Vector2(3, 0))
		mark(run.enemies[id_], int(pair[0]))
		ready(run)
		fire(run)
		var life := 1400 * UNIT
		check(int(run.enemies[id_].hp_raw) == life - life * int(pair[1]) / 10000, "strong: %d marks give %d bps (%d)" % [int(pair[0]), int(pair[1]), int(run.enemies[id_].hp_raw)])
	# the marks are taken and the gauge gets 6 each back, 1500 at most
	var refund := stage("arc", func(d): d.cost = [3000, 8000])
	for k in 5: mark(refund.enemies[put(refund, Vector2(2 + k, 3))], 3)
	ready(refund)
	var shot := fire(refund)
	var end: Dictionary = of_type(shot.events, "descent_end")[0]
	check(int(end.marks_taken) == 15 and int(end.refund) == 90, "marks: 15 marks taken give 90 back: " + str(end))
	check(gauge(refund) == 90 and int(refund.descent_view().cost_now) == 8000, "marks: the gauge of the next descent starts at 90 (%d)" % gauge(refund))
	check(of_type(shot.events, "descent_strike").any(func(e): return e.marks_at.size() > 0), "marks: descent_strike names where marks were taken")
	var cap := stage("frost", func(d): d.cost = [3000, 8000])
	for k in 20: mark(cap.enemies[put(cap, Vector2(-2.0 - k * 0.4, 5))], 20)
	ready(cap)
	var cap_shot := fire(cap)
	var cap_end: Dictionary = of_type(cap_shot.events, "descent_end")[0]
	check(int(cap_end.marks_taken) == 400 and int(cap_end.refund) == 1500 and gauge(cap) == 1500, "marks: the give-back stops at 1500: " + str(cap_end))
	# a status that has run out is not taken
	var stale := stage("ember")
	var id_stale := put(stale, Vector2(3, 3))
	stale.enemies[id_stale].status = {"heat": {"n": 4, "src": "test", "until": stale.tick - 1, "by": {}}}
	ready(stale)
	var stale_call: Dictionary = {}
	stale.request_descent()
	stale_call = of_type(stale.events, "descent_called").back() if of_type(stale.events, "descent_called").size() > 0 else {}
	check(int(stale_call.get("marks_in_reach", -1)) == 0, "marks: an expired status does not count")
	# marks are counted in descent_called
	var counted := stage("ember")
	mark(counted.enemies[put(counted, Vector2(3, 3))], 2)
	ready(counted)
	counted.request_descent()
	check(int(of_type(counted.events, "descent_called").back().marks_in_reach) == 2, "marks: descent_called counts the marks in reach")

# ------------------------------------------------------------------ end tick, invulnerability, spawn breath, view

func end_checks() -> void:
	var run := stage("ember")
	var near_orbs := [Vector2(6, 0), Vector2(-9, 3), Vector2(0, -11)]
	for p in near_orbs: run._drop_orb(p, 1)
	var item := {"uid": 5001, "position": Vector2(4, 4), "collected": false, "drop_tick": 0, "stats": {}, "quality": "common", "slot": "weapon"}
	var far_item := {"uid": 5002, "position": Vector2(18, 0), "collected": false, "drop_tick": 0, "stats": {}, "quality": "common", "slot": "weapon"}
	run.items.append(item)
	run.items.append(far_item)
	var inventory_before: int = run.inventory.size()
	put(run, Vector2(3, 3))
	ready(run)
	var shot := fire(run)
	var vacuum: Array = of_type(shot.events, "orb_vacuum")
	check(vacuum.size() == 1 and String(vacuum[0].by) == "descent" and run.orbs.is_empty(), "end: the orbs on the floor come in with orb_vacuum {by: descent}: " + str(vacuum.map(func(e): return e.get("by", ""))))
	var pickups: Array = of_type(shot.events, "item_pickup").filter(func(e): return bool(e.get("swept", false)) and String(e.get("by", "")) == "descent")
	check(pickups.size() == 1 and run.inventory.size() == inventory_before + 1 and run.items.size() == 1 and int(run.items[0].uid) == 5002, "end: the item in reach goes to the bag, the far one stays on the floor")
	var end_tick: int = int(of_type(shot.events, "descent_end")[0].tick)
	check(end_tick == int(shot.start) + 60 and int(vacuum[0].tick) == end_tick, "end: the vacuum and the report come on the last tick (%d)" % end_tick)
	# the level that the orbs bring opens the card screen at once
	var lucky := stage("arc", Callable(), 11, false, Callable(), false)
	lucky._drop_orb(Vector2(5, 0), 30)
	lucky._drop_orb(Vector2(-5, 0), 30)
	ready(lucky)
	lucky.request_descent()
	lucky.release_descent()
	var saw_end := false
	for i in 80:
		lucky.hero.hp_raw = lucky.hero.max_hp_raw
		lucky.step(Vector2.ZERO)
		if of_type(lucky.events, "descent_end").size() > 0:
			saw_end = true
			break
	check(saw_end and lucky.mode == "choice", "end: the card screen opens on the tick the orbs arrive (mode %s)" % lucky.mode)
	# the hero cannot be hurt from the release until sweep + 30 ticks, and can be after
	var guard := stage("ember")
	ready(guard)
	guard.request_descent()
	guard.release_descent()
	var start: int = guard.tick
	var hit_log: Array = []
	for i in 95:
		guard.hero.hp_raw = guard.hero.max_hp_raw
		guard.step(Vector2.ZERO)
		var life_before: int = guard.hero.hp_raw
		guard._hero_damage(10 * UNIT, Vector2(1, 0), "hazard", 0)
		hit_log.append(guard.hero.hp_raw < life_before)
	var first_hurt := hit_log.find(true)
	check(first_hurt == 89, "invulnerable: the first blow that lands is on step %d after the release (expected 90 = 60 + 30, index 89)" % (first_hurt + 1))
	check(int(guard.descent_view().iframe_until_tick) == start + 90, "invulnerable: the view names the tick it ends (%d)" % int(guard.descent_view().iframe_until_tick))
	# the breath: nothing ordinary spawns for 60 ticks after the end
	var breath := stage("ember")
	breath._next_spawn = 0
	ready(breath)
	breath.request_descent()
	breath.release_descent()
	var timeline := tick_run(breath, 60)
	check(of_type(timeline, "descent_end").size() == 1, "breath: the sweep ended")
	var after := tick_run(breath, 70)
	var spawns: Array = of_type(after, "spawn").filter(func(e): return not e.elite)
	var first_spawn: int = int(spawns[0].tick) if spawns.size() > 0 else -1
	var end_at: int = int(of_type(timeline, "descent_end")[0].tick)
	check(first_spawn > end_at + 59, "breath: the first new enemy comes %d ticks after the end (60 expected or more)" % (first_spawn - end_at))

func view_checks() -> void:
	var run := stage("frost", func(d): d.cost = [2000, 4000])
	var view: Dictionary = run.descent_view()
	check(view.keys() == ["enabled", "element", "gauge", "cost_now", "ratio_bps", "ready", "state", "uses", "first", "sweep_left_ticks", "iframe_until_tick"], "view: the keys are as the contract says: " + str(view.keys()))
	check(view.enabled and view.element == "frost" and int(view.gauge) == 0 and int(view.cost_now) == 2000 and view.state == "charging" and not view.ready and int(view.uses) == 0 and view.first, "view: charging: " + str(view))
	run._descent_add(500)
	check(int(run.descent_view().ratio_bps) == 2500, "view: ratio_bps is the share of cost_now (2500)")
	run._descent_add(1500)
	check(run.descent_view().state == "ready" and run.descent_view().ready, "view: ready")
	run.request_descent()
	check(run.descent_view().state == "hold" and run.descent_view().first, "view: hold, and it is the first")
	run.release_descent()
	var swept: Dictionary = run.descent_view()
	check(swept.state == "sweep" and int(swept.sweep_left_ticks) == 45 and int(swept.uses) == 1 and swept.first and int(swept.gauge) == 0, "view: sweep with 45 ticks left, still the first: " + str(swept))
	tick_run(run, 10)
	check(int(run.descent_view().sweep_left_ticks) == 35, "view: the ticks left run down")
	tick_run(run, 40)
	var after: Dictionary = run.descent_view()
	check(after.state == "charging" and int(after.cost_now) == 4000 and int(after.uses) == 1 and not after.first, "view: charging again toward 4000, no longer the first: " + str(after))
	# the view changes nothing
	var snapshot_a := JSON.stringify(run.snapshot()).sha256_text()
	for i in 5: run.descent_view()
	check(JSON.stringify(run.snapshot()).sha256_text() == snapshot_a, "view: reading it changes nothing")
	# the second one is a short cut-in
	run._descent_add(4000)
	run.request_descent()
	check(of_type(run.events, "descent_called").back().variant == "short" and int(of_type(run.events, "descent_called").back().index) == 2, "view: the second call is index 2, variant short")

# ------------------------------------------------------------------ burn, determinism, the bot

func burn_check() -> void:
	var run := stage("ember", Callable(), 11, true)
	var champion := put_strong(run, Vector2(5, 0))
	ready(run)
	fire(run)
	check(not run._d_burn.is_empty(), "burn: with the spell composition the fire stays after the sweep")
	tick_run(run, 31)
	var status: Dictionary = run.enemies[champion].get("status", {})
	check(status.has("heat") and int(status.heat.n) >= 1 and status.heat.by.has("descent.ember"), "burn: the strong enemy that stayed gets heat from the fire (%s)" % str(status))
	var plain := stage("ember")
	put_strong(plain, Vector2(5, 0))
	ready(plain)
	fire(plain)
	check(plain._d_burn.is_empty(), "burn: without the composition there is no fire left")

func play_with_policy(policy: String, seed_: int, primary: String, ticks: int) -> Dictionary:
	var run = Chapter.new()
	check(run.set_descent(doc_on(func(d):
		d.cost = [1000, 1000, 1000]
		d.points.kill_default = 200)), "play: the descent document is accepted")
	check(run.start(seed_, primary), "play: starts")
	run.first_boss_kill = true
	var pilot = Pilot.new()
	pilot.run = run
	var ends: Array = []
	var calls: Array = []
	for i in ticks:
		var move: Vector2 = pilot.decide()
		for e in Policy.use(run, policy):
			if e.type == "descent_called": calls.append(int(e.tick))
		run.step(move)
		for e in run.events:
			if e.type == "descent_end": ends.append({"tick": int(e.tick), "kills": int(e.kills)})
		if run.mode == "defeat" or run.mode == "victory": break
	return {"hash": JSON.stringify(run.snapshot()).sha256_text(), "ends": ends, "calls": calls, "uses": int(run.descent_view().uses), "tick": run.tick, "mode": run.mode}

func determinism_checks() -> void:
	for primary in ["chapter1.skill.ember", "chapter1.skill.frost", "chapter1.skill.arc"]:
		var a := play_with_policy("now", 11, primary, 2400)
		var b := play_with_policy("now", 11, primary, 2400)
		check(a.hash == b.hash and JSON.stringify(a.ends) == JSON.stringify(b.ends), "determinism: %s twice with the same seed and the bot's calls: same snapshot" % primary)
		check(int(a.uses) >= 1 and a.ends.size() >= 1 and a.calls.size() >= 1, "determinism: %s the bot used the descent (%d times, ends %d)" % [primary, int(a.uses), a.ends.size()])
		var off := play_with_policy("off", 11, primary, 2400)
		check(int(off.uses) == 0 and off.ends.is_empty(), "determinism: %s with the policy off nothing is used" % primary)
	# policies
	var held := play_with_policy("hold", 11, "chapter1.skill.ember", 1800)
	var now := play_with_policy("now", 11, "chapter1.skill.ember", 1800)
	check(int(now.uses) > int(held.uses), "policy: hold uses it less than now in a run without a trial or a boss (%d vs %d)" % [int(held.uses), int(now.uses)])
	check(not Policy.valid("sometimes") and Policy.valid("panic"), "policy: names")

func execute() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/_local/appdata/"):
		print("CHAPTER1_DESCENT_TEST_RESULT ", JSON.stringify({"checks": 0, "failures": ["user data dir is not isolated: refusing to run"]}))
		quit(1)
		return
	off_checks()
	validator_checks()
	gauge_checks()
	stop_checks()
	element_ember()
	element_frost()
	element_arc()
	element_ember_trial()
	strong_checks()
	end_checks()
	view_checks()
	burn_check()
	determinism_checks()
	print("CHAPTER1_DESCENT_TEST_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
