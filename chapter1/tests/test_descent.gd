extends SceneTree
## U-1 check of the descent (D15 A, chapter1/data/descent.json). Every document is switched on IN MEMORY (set_descent); the
## shipped file stays off. Parts: off (nothing changes), validator (schema 2), the screen rectangle, the seed hash, gauge (one
## event at a time), the stop (mode "descent", no tick), the three ultimates (ember fragments, frost storm, arc bolts; D24),
## strong enemies, the trial's cap, the cause of every kill (Q-D8), the end tick (orbs, items, level choice), the hero's
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

## Call, release, and play the whole sweep (+ extra ticks). Returns {called, events, start}.
func fire(run: RefCounted, extra: int = 0) -> Dictionary:
	check(run.request_descent(), "fire: the call is accepted")
	var called: Array = of_type(run.events, "descent_called")
	check(run.release_descent(), "fire: the release is accepted")
	var start: int = run.tick
	var ticks := int(run.descent.ultimates[run._d_element].sweep_ticks) + extra
	return {"called": called[called.size() - 1] if called.size() > 0 else {}, "events": tick_run(run, ticks), "start": start}

## Enemies on a square grid near the hero (step `gap`, at most `limit` of them, row order).
func grid(run: RefCounted, gap: float, half: int, limit: int = 1 << 20, centre: Vector2 = Vector2.ZERO) -> Array:
	var ids: Array = []
	for ix in range(-half, half + 1):
		for iy in range(-half, half + 1):
			var p := centre + Vector2(ix, iy) * gap
			if p.length() < 1.0 or p.length() > 12.5 or ids.size() >= limit: continue
			ids.append(put(run, p))
	return ids

## Ordinary enemies on a lattice over the whole screen rectangle around the hero (D24): only places the zone clamp leaves alone.
func spread(run: RefCounted, gap: float, limit: int = 1 << 20) -> Array:
	var ids: Array = []
	var nu := int(float(run.descent.area.half_w_m) / gap)
	var nv := int(float(run.descent.area.half_h_m) / gap)
	for iu in range(-nu, nu + 1):
		for iv in range(-nv, nv + 1):
			var p: Vector2 = run.hero.position + run._d_right * (float(iu) * gap) + run._d_up * (float(iv) * gap)
			if p.distance_to(run.hero.position) < 1.5 or ids.size() >= limit or not run._clamp_point(p).is_equal_approx(p): continue
			ids.append(put(run, p))
	return ids

func on_screen(run: RefCounted, id_: int) -> bool:
	return run.enemies.has(id_) and run._descent_inside(run.enemies[id_].position, run.hero.position)

func screen_normals_alive(run: RefCounted) -> int:
	var n := 0
	for id_ in run.enemies:
		var e: Dictionary = run.enemies[id_]
		if e.hp_raw > 0 and run._enemy_role(e) == "normal" and run._descent_inside(e.position, run.hero.position): n += 1
	return n

# ------------------------------------------------------------------ validator

func validator_checks() -> void:
	var run = Chapter.new()
	check(run.set_descent(shipped()), "validator: the shipped document is accepted")
	check(run.set_descent(doc_on()), "validator: the enabled document is accepted")
	rejects("not a dictionary", func(d): d.clear())
	rejects("unknown root key", func(d): d.extra = 1)
	rejects("missing root key", func(d): d.erase("crown"))
	rejects("enabled as a number", func(d): d.enabled = 1)
	rejects("schema_version 1", func(d): d.schema_version = 1)
	rejects("schema_version 3", func(d): d.schema_version = 3)
	rejects("the old reach_m key", func(d): d.reach_m = 13.0)
	rejects("the old elements key", func(d): d.elements = {})
	rejects("empty cost", func(d): d.cost = [])
	rejects("seven costs", func(d): d.cost = [1000, 1000, 1000, 1000, 1000, 1000, 1000])
	rejects("cost 999", func(d): d.cost = [999])
	rejects("cost 30001", func(d): d.cost = [30001])
	rejects("a point of 2001", func(d): d.points.vs_cc_hit = 2001)
	rejects("a negative point", func(d): d.points.detonate = -1)
	rejects("kill_by_beat naming a beat that does not exist", func(d): d.points.kill_by_beat.slow = 3)
	rejects("kill_by_beat empty", func(d): d.points.kill_by_beat = {})
	rejects("a point key missing", func(d): d.points.erase("elite_kill"))
	rejects("area half_w 5.9", func(d): d.area.half_w_m = 5.9)
	rejects("area half_h 30.1", func(d): d.area.half_h_m = 30.1)
	rejects("area edge 4.1", func(d): d.area.edge_m = 4.1)
	rejects("area right_deg 181", func(d): d.area.right_deg = 181.0)
	rejects("area shape disc", func(d): d.area.shape = "disc")
	rejects("area key missing", func(d): d.area.erase("edge_m"))
	rejects("trial_kill_cap 401", func(d): d.normal.trial_kill_cap = 401)
	rejects("strong bps 10001", func(d): d.strong.boss_bps = 10001)
	rejects("cut_windup_ticks 0", func(d): d.strong.cut_windup_ticks = 0)
	rejects("strong boss_stagger_ticks 601", func(d): d.strong.boss_stagger_ticks = 601)
	rejects("strong champion_stun_ticks missing", func(d): d.strong.erase("champion_stun_ticks"))
	rejects("after.iframe_ticks 601", func(d): d.after.iframe_ticks = 601)
	rejects("ember sweep_ticks 0", func(d): d.ultimates.ember.sweep_ticks = 0)
	rejects("ember sweep_ticks 601", func(d): d.ultimates.ember.sweep_ticks = 601)
	rejects("ember grid 0 columns", func(d): d.ultimates.ember.grid = [0, 3])
	rejects("ember 33 pieces", func(d): d.ultimates.ember.grid = [8, 4])
	rejects("ember aimed 5", func(d): d.ultimates.ember.aimed = 5)
	rejects("ember big_count below aimed", func(d): d.ultimates.ember.big_count = 1)
	rejects("ember last_land_step before the first", func(d): d.ultimates.ember.last_land_step = 30)
	rejects("ember last_land_step after the sweep", func(d): d.ultimates.ember.last_land_step = 133)
	rejects("ember gap_ticks reversed", func(d): d.ultimates.ember.gap_ticks = [8, 4])
	rejects("ember share 10001", func(d): d.ultimates.ember.first_hit_share_bps = 10001)
	rejects("frost onset not before the pulses", func(d): d.ultimates.frost.onset_step = 30)
	rejects("frost pulses run past the sweep", func(d): d.ultimates.frost.pulse_count = 20)
	rejects("frost pulses pay more than the share", func(d): d.ultimates.frost.pulse_share_bps = 1300)
	rejects("frost sweep_ticks 0", func(d): d.ultimates.frost.sweep_ticks = 0)
	rejects("arc 65 bolts", func(d): d.ultimates.arc.bolts = 65)
	rejects("arc forks 9", func(d): d.ultimates.arc.forks = 9)
	rejects("arc first_step not before last_step", func(d): d.ultimates.arc.first_step = 114)
	rejects("arc last_step after the sweep", func(d): d.ultimates.arc.last_step = 121)
	rejects("arc gap_ticks reversed", func(d): d.ultimates.arc.gap_ticks = [5, 0])
	rejects("an element missing", func(d): d.ultimates.erase("arc"))
	rejects("an unknown element", func(d): d.ultimates.stone = {})
	rejects("blocked_phases with a stranger", func(d): d.blocked_phases = ["night"])
	rejects("blocked_phases not an array", func(d): d.blocked_phases = "trial")
	rejects("crown with two charge values", func(d): d.crown.charge_bps = [1000, 2000])
	rejects("crown power_bps 9999", func(d): d.crown.power_bps = 9999)
	rejects("crown with the old reach_add_m", func(d): d.crown.reach_add_m = 1.0)
	# a refused document changes nothing: the run keeps the parked one
	var holder = Chapter.new()
	holder.set_descent(doc_on(func(d): d.cost = [1234]))
	var bad := shipped()
	bad.cost = []
	check(not holder.set_descent(bad), "validator: the broken document is refused")
	check(holder.start(11, "chapter1.skill.ember") and int(holder.descent.cost[0]) == 1234, "validator: a refused document left the parked one alone")

# ------------------------------------------------------------------ D24 1 and 2: the rectangle and the hash

func rectangle_checks() -> void:
	# (1) the screen rectangle: the four sides and corners, inside and outside, for three turning angles and a moved centre
	for right_deg in [-38.2, 0.0, 90.0]:
		var run := stage("ember", func(d): d.area.right_deg = right_deg)
		var hw := 17.3 + 1.0
		var hh := 13.4 + 1.0
		var centre := Vector2(2.5, -1.5)
		var right := Vector2.from_angle(deg_to_rad(right_deg))
		var up := Vector2(right.y, -right.x)
		var tag := "angle %.1f" % right_deg
		check(run._descent_inside(centre, centre), "rect (%s): the centre is inside" % tag)
		check(run._descent_inside(centre + right * (hw - 0.01), centre) and run._descent_inside(centre - right * (hw - 0.01), centre), "rect (%s): just inside the left and right sides" % tag)
		check(not run._descent_inside(centre + right * (hw + 0.01), centre) and not run._descent_inside(centre - right * (hw + 0.01), centre), "rect (%s): just outside the left and right sides" % tag)
		check(run._descent_inside(centre + up * (hh - 0.01), centre) and run._descent_inside(centre - up * (hh - 0.01), centre), "rect (%s): just inside the top and bottom" % tag)
		check(not run._descent_inside(centre + up * (hh + 0.01), centre) and not run._descent_inside(centre - up * (hh + 0.01), centre), "rect (%s): just outside the top and bottom" % tag)
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				check(run._descent_inside(centre + right * (sx * (hw - 0.02)) + up * (sy * (hh - 0.02)), centre), "rect (%s): the corner (%d,%d) just inside" % [tag, int(sx), int(sy)])
				check(not run._descent_inside(centre + right * (sx * (hw + 0.02)) + up * (sy * (hh - 0.02)), centre), "rect (%s): the corner (%d,%d) pushed out along the width" % [tag, int(sx), int(sy)])
				check(not run._descent_inside(centre + right * (sx * (hw - 0.02)) + up * (sy * (hh + 0.02)), centre), "rect (%s): the corner (%d,%d) pushed out along the height" % [tag, int(sx), int(sy)])
	# a circle of 13 m would have missed these; the rectangle takes them
	var wide := stage("ember")
	var reach := Vector2.from_angle(deg_to_rad(-38.2)) * 17.0
	check(wide._descent_inside(reach, Vector2.ZERO) and reach.length() > 13.0, "rect: a point 17 m to the right is on the screen (a 13 m circle would miss it)")
	# the edge is data
	var tight := stage("ember", func(d): d.area.edge_m = 0.0)
	check(not tight._descent_inside(reach.normalized() * 17.35, Vector2.ZERO) and tight._descent_inside(reach.normalized() * 17.25, Vector2.ZERO), "rect: edge_m 0 puts the side at 17.3 m")

func hash_checks() -> void:
	# (2) the integer hash: three fixed inputs (values computed by an independent implementation, tools-free: lowbias32 in Python)
	check(Chapter.descent_hash(1145393992, 1, 0, 1) == 1729976043, "hash: (seed 11^mask, use 1, k 0, salt 1) = 1729976043 (%d)" % Chapter.descent_hash(1145393992, 1, 0, 1))
	check(Chapter.descent_hash(1145393999, 2, 13, 5) == 2296148150, "hash: (seed 12^mask, use 2, k 13, salt 5) = 2296148150 (%d)" % Chapter.descent_hash(1145393999, 2, 13, 5))
	check(Chapter.descent_hash(0, 0, 0, 0) == 0, "hash: (0,0,0,0) = 0")
	var run := stage("ember", Callable(), 11)
	check(int(run._d_seed) == (11 ^ 0x44455343), "hash: the run's descent seed is the seed xor the mask")
	check(run._dhash(1, 0, 1) == 1729976043, "hash: the core's own hash agrees with the pinned value")
	var all_in_range := true
	var seen := {}
	for k in 200:
		var h: int = run._dhash(1, k, 7)
		all_in_range = all_in_range and h >= 0 and h <= 0xffffffff
		seen[h] = true
	check(all_in_range and seen.size() > 195, "hash: 200 keys give 32-bit values that do not collide (%d distinct)" % seen.size())
	# no stream of the core is drawn by a sweep that kills nothing
	for element in ["ember", "frost", "arc"]:
		var quiet := stage(element)
		var states := [quiet._spawn_rng.state, quiet._loot_rng.state, quiet._extras_rng.state]
		ready(quiet)
		fire(quiet)
		check(states == [quiet._spawn_rng.state, quiet._loot_rng.state, quiet._extras_rng.state], "hash: a %s sweep drew nothing from the spawn, loot and extras streams" % element)

# ------------------------------------------------------------------ elements

func element_ember() -> void:
	var run := stage("ember")
	var crowd := spread(run, 3.2)
	var boss := put_strong(run, Vector2(6, -4), "boss")
	var champion := put_strong(run, Vector2(-7, 5), "champion")
	var elite := put_strong(run, Vector2(2, 9), "elite")
	var far := put(run, Vector2(0, 0))
	run.enemies[far].position = Vector2(-16, 16)
	var far_shot := {"uid": 9001, "position": Vector2(5, 5), "previous": Vector2(5, 5), "direction": Vector2.LEFT, "speed": 4.0, "radius": .16, "skill_id": "hostile.walker", "hostile": true, "damage_raw": 5 * UNIT, "expires": run.tick + 500, "cast_id": 0, "pierce_left": 0, "hit_ids": []}
	run.projectiles.append(far_shot)
	run._hostile_src[9001] = {"id": 1, "kind": "walker"}
	run.chapter_hazards.append({"uid": 77, "position": Vector2(3, 3), "radius": 1.8, "started": run.tick, "expires": run.tick + 5000, "damage_raw": 65 * UNIT})
	check(crowd.size() > 60, "ember: a crowd of %d ordinary enemies over the screen" % crowd.size())
	ready(run)
	var shot := fire(run, 0)
	var called: Dictionary = shot.called
	check(called.element == "ember" and int(called.index) == 1 and called.variant == "long" and called.area.half_w_m == 17.3 and called.area.half_h_m == 13.4, "ember: descent_called carries element, index 1, variant long and the area: " + str(called))
	check(int(called.normals_in_reach) == crowd.size() and int(called.strongs_in_reach) == 3, "ember: descent_called counts the screen's bodies (%d normals, %d strong)" % [int(called.normals_in_reach), int(called.strongs_in_reach)])
	var events: Array = shot.events
	# (3) after the sweep no ordinary body is left on the screen, and the one far off is untouched
	check(screen_normals_alive(run) == 0 and alive_ids(run, crowd).is_empty(), "ember: every ordinary enemy on the screen is dead (%d left)" % screen_normals_alive(run))
	check(run.enemies[far].hp_raw > 0, "ember: one far outside the screen is left alone")
	check(run.projectiles.filter(func(p): return p.hostile).is_empty() and not run._hostile_src.has(9001), "ember: the enemy shot is gone and forgotten")
	check(run.chapter_hazards.size() == 1, "ember: the boss's floor strike stays")
	var released: Array = of_type(events, "descent_released")
	check(released.size() == 1 and int(released[0].tick) == int(shot.start) + 1 and int(released[0].cleared_shots) == 1 and int(released[0].sweep_ticks) == 132, "ember: descent_released one tick after the release, 132 ticks, 1 shot cleared: " + str(released))
	check(released[0].area == {"right_deg": -38.2, "half_w_m": 17.3, "half_h_m": 13.4} and released[0].center == run.hero.position and not released[0].has("cleared_positions") == false, "ember: descent_released carries the area and the centre")
	# (6) the booking: 14 fragments, all on the screen, land steps in range and in order, the aimed ones on the strong bodies
	var books: Array = of_type(events, "descent_book")
	check(books.size() == 1 and int(books[0].tick) == int(shot.start) + 1, "ember: one descent_book on step 1")
	var fragments: Array = books[0].fragments
	check(fragments.size() == 14, "ember: fourteen fragments are booked (%d)" % fragments.size())
	var inside_all := true
	var steps_ok := true
	var big_n := 0
	var last_step := 0
	for f in fragments:
		inside_all = inside_all and run._descent_inside(f.pos, run.hero.position)
		steps_ok = steps_ok and int(f.land_step) >= 30 and int(f.land_step) <= 126 and int(f.land_step) >= last_step
		last_step = int(f.land_step)
		big_n += 1 if bool(f.big) else 0
		check(is_equal_approx(float(f.radius_m), 4.5 if bool(f.big) else 3.0), "ember: fragment %d has the radius of its size" % int(f.k))
	check(inside_all, "ember: every fragment lands on the screen rectangle")
	check(steps_ok and int(fragments[0].land_step) == 30, "ember: land steps run from 30 to at most 126, never backwards (first %d, last %d)" % [int(fragments[0].land_step), last_step])
	check(big_n == 5, "ember: five fragments are big (%d)" % big_n)
	check(int(fragments[0].aimed_id) == boss and int(fragments[6].aimed_id) == champion, "ember: the aimed fragments are the first and the seventh, on the boss and then the guardian (%d, %d)" % [int(fragments[0].aimed_id), int(fragments[6].aimed_id)])
	var aimed_total := 0
	for f in fragments:
		if int(f.aimed_id) > 0:
			aimed_total += 1
			check(f.pos.is_equal_approx(Vector2(6, -4)) or f.pos.is_equal_approx(Vector2(-7, 5)), "ember: an aimed fragment sits where its strong body stood")
			check(bool(f.big), "ember: an aimed fragment is big")
	check(aimed_total == 2, "ember: exactly two fragments are aimed")
	var impacts: Array = of_type(events, "descent_strike").filter(func(e): return e.phase == "impact")
	check(impacts.size() == 14, "ember: fourteen impacts (%d)" % impacts.size())
	var impact_ok := true
	for i in impacts.size():
		impact_ok = impact_ok and int(impacts[i].k) == i and int(impacts[i].step) == int(fragments[i].land_step) and impacts[i].pos == fragments[i].pos and bool(impacts[i].big) == bool(fragments[i].big)
	check(impact_ok, "ember: each impact is the booked fragment, on its land step")
	var storm: Array = of_type(events, "descent_strike").filter(func(e): return e.phase == "firestorm")
	check(storm.size() == 1 and int(storm[0].step) == 132, "ember: one firestorm strike on the last step")
	var ends: Array = of_type(events, "descent_end")
	check(ends.size() == 1 and int(ends[0].duration_ticks) == 132 and int(ends[0].kills) == crowd.size() and int(ends[0].strong_hits) == 3, "ember: descent_end reports the kills in 132 ticks and 3 strong bodies: " + str(ends))
	check(int(ends[0].get("marks_taken", -1)) == 0 and ends[0].has("boss_share_bps"), "ember: no marks taken, and the boss share is reported")
	# strong bodies: share exactly 12 / 20 / 50 percent, a boss kneels 45 ticks, a guardian is stunned 45 ticks
	var end_tick: int = int(ends[0].tick)
	for pair in [[boss, 4500, 1200], [champion, 1400, 2000], [elite, 600, 5000]]:
		var life: int = int(pair[1]) * UNIT
		check(int(run.enemies[pair[0]].hp_raw) == life - life * int(pair[2]) / 10000, "ember: a strong body loses exactly %d bps of its life (%d of %d)" % [int(pair[2]), int(run.enemies[pair[0]].hp_raw), life])
	check(int(run.enemies[boss].get("staggered_until", 0)) == end_tick + 45, "ember: the boss kneels 45 ticks from the closing blow")
	check(int(run.enemies[champion].get("stunned_until", 0)) == end_tick + 45, "ember: the guardian is stunned 45 ticks from the closing blow")
	check(int(ends[0].boss_share_bps) == 1200, "ember: boss_share_bps is 1200 (%d)" % int(ends[0].boss_share_bps))
	# without a strong body the aimed ones go to the fullest cells
	var plain := stage("ember")
	var herd := spread(plain, 3.2)
	for i in 12: put(plain, Vector2(5.0, 4.0) + Vector2(i % 4, i / 4) * 0.5)
	ready(plain)
	var plain_shot := fire(plain)
	var plain_frag: Array = of_type(plain_shot.events, "descent_book")[0].fragments
	check(int(plain_frag[0].aimed_id) == 0 and int(plain_frag[6].aimed_id) == 0 and plain_frag.size() == 14, "ember: with no strong body the aimed fragments carry no target")
	check(plain._descent_inside(plain_frag[0].pos, Vector2.ZERO) and plain._descent_inside(plain_frag[6].pos, Vector2.ZERO) and not plain_frag[0].pos.is_equal_approx(plain_frag[6].pos), "ember: and still land on the screen, on two different places")
	check(herd.size() > 0 and screen_normals_alive(plain) == 0, "ember: and the screen is empty of ordinary enemies after it")
	# one that slips behind is caught on the last tick (it was outside until then)
	var late := stage("ember")
	var behind := put(late, Vector2.ZERO)
	late.enemies[behind].position = Vector2(60, 60)
	ready(late)
	late.request_descent()
	late.release_descent()
	var start_late: int = late.tick
	tick_run(late, 100)
	late.enemies[behind].position = Vector2(-9, 4)
	var rest := tick_run(late, 40)
	var late_death: Array = rest.filter(func(e): return e.type == "death")
	check(late_death.size() == 1 and int(late_death[0].tick) == start_late + 132, "ember: an enemy that comes on the screen late dies on the last tick (tick %d, expected %d)" % [int(late_death[0].tick) if late_death.size() == 1 else -1, start_late + 132])

func element_frost() -> void:
	var run := stage("frost")
	var near := put(run, Vector2(4, 0))
	var far_off := put(run, Vector2(-9, 6))
	var champion := put_strong(run, Vector2(0, -7))
	var boss := put_strong(run, Vector2(8, 8), "boss")
	var outside := put(run, Vector2(0, 0))
	run.enemies[outside].position = Vector2(-16, 16)
	var windup: Dictionary = run.enemies[champion]
	windup.state = "windup"
	windup.state_until = run.tick + 50
	windup.telegraph = {"remaining_ticks": 50}
	ready(run)
	run.request_descent()
	run.release_descent()
	var start: int = run.tick
	var early := tick_run(run, 17)
	check(run.enemies[near].frozen_until == 0 and run.enemies[far_off].frozen_until == 0, "frost: nothing is frozen before step 18")
	early.append_array(tick_run(run, 1))
	check(of_type(early, "descent_strike").any(func(e): return e.phase == "onset" and int(e.step) == 18 and e.target_ids.size() == 4), "frost: on step 18 one onset strike names the four bodies on the screen")
	check(run.tick < int(run.enemies[near].frozen_until) and int(run.enemies[near].frozen_until) == start + 151, "frost: an ordinary body is frozen until the break (start+151)")
	check(run.tick < int(run.enemies[champion].frozen_until) and int(run.enemies[champion].frozen_until) <= run.tick + 30, "frost: the strong one is frozen for at most 30 ticks")
	check(windup.state == "recover" and windup.telegraph.is_empty(), "frost: the strong one's windup was cut (state %s)" % windup.state)
	check(run.enemies[outside].frozen_until == 0, "frost: a body outside the screen is not frozen")
	check(run.enemies[near].hp_raw > 0 and run.enemies[far_off].hp_raw > 0, "frost: nobody is hit before the break")
	# (7) one that comes on the screen later freezes on the tick it is there; the frozen list outlives the screen
	tick_run(run, 7)
	var newcomer := put(run, Vector2(6, 6))
	var after := tick_run(run, 1)
	check(run.tick < int(run.enemies[newcomer].frozen_until) and of_type(after, "descent_strike").any(func(e): return e.phase == "freeze" and e.target_ids.has(newcomer)), "frost: one that comes in during the storm is frozen on the tick it is there")
	run.enemies[far_off].position = Vector2(80, 80)
	check(run.enemies[far_off].hp_raw > 0, "frost: (a frozen body is pushed off the screen)")
	# pulses: the guardian is paid a sixteenth each time, the ordinary bodies nothing
	var pulses_seen: Array = []
	var life := 1400 * UNIT
	var full := life * 2000 / 10000
	var checked_pulse := false
	for i in 140:
		var tick_events := tick_run(run, 1)
		for e in tick_events:
			if e.type == "descent_strike" and e.phase == "pulse": pulses_seen.append(int(e.step))
		var n := pulses_seen.size()
		if n == 1 and not checked_pulse and run.tick - start == 30:
			check(int(run.enemies[champion].hp_raw) == life - full * 625 / 10000, "frost: the first pulse took a sixteenth of the guardian's share (%d)" % int(run.enemies[champion].hp_raw))
			checked_pulse = true
		if run.enemies[near].hp_raw <= 0: break
	var wanted: Array = []
	for i in 8: wanted.append(30 + 15 * i)
	check(pulses_seen == wanted, "frost: eight pulses on steps 30, 45 ... 135 (%s)" % str(pulses_seen))
	var break_tick: int = run.tick
	check(break_tick == start + 150 and run.enemies[near].hp_raw <= 0 and run.enemies[far_off].hp_raw <= 0 and run.enemies[newcomer].hp_raw <= 0, "frost: on step 150 the frozen bodies break together, the one that left the screen too (tick %d)" % (break_tick - start))
	check(run.enemies[outside].hp_raw > 0, "frost: the body that was never on the screen is spared")
	var boss_life := 4500 * UNIT
	check(int(run.enemies[boss].hp_raw) == boss_life - boss_life * 1200 / 10000, "frost: the boss lost exactly 12 percent over eight pulses and the break")
	check(int(run.enemies[champion].hp_raw) == life - full, "frost: the guardian lost exactly its 20 percent")
	check(int(run.enemies[champion].frozen_until) == break_tick + 30 and int(run.enemies[boss].frozen_until) == break_tick + 30, "frost: the strong ones that remain are frozen 30 ticks more")
	check(int(run.enemies[boss].get("staggered_until", 0)) == break_tick + 45, "frost: the boss kneels 45 ticks")
	# the ground stays: a slow of 30 percent over the screen
	check(run._d_burn.size() == 1 and run._d_burn[0].kind == "frost", "frost: the ground frost is kept after the break")
	tick_run(run, 3)
	check(int(run.enemies[boss].slow_bps) == 3000 and int(run.enemies[champion].slow_bps) == 3000, "frost: the ground slows the strong ones by 30 percent")
	# the trial's cap: the rest of the crowd stays frozen
	var trial := stage("frost")
	var crowd := spread(trial, 2.0)
	trial._trial_phase = "hold"
	trial._trial_center = trial.hero.position
	ready(trial)
	fire(trial)
	var dead: Array = crowd.filter(func(i): return trial.enemies[i].hp_raw <= 0)
	check(crowd.size() > 180 and dead.size() == 180, "frost: in the trial hold only 180 of %d ordinary enemies die (%d)" % [crowd.size(), dead.size()])
	var left: Array = alive_ids(trial, crowd)
	check(left.size() == crowd.size() - 180 and left.all(func(i): return int(trial.enemies[i].frozen_until) >= trial.tick + 25), "frost: the ones left are frozen for about 30 ticks more")

func element_arc() -> void:
	var run := stage("arc")
	var crowd := spread(run, 3.4)
	var boss := put_strong(run, Vector2(0, 11), "boss")
	var boss_e: Dictionary = run.enemies[boss]
	boss_e.state = "windup"
	boss_e.state_until = run.tick + 40
	boss_e.telegraph = {"remaining_ticks": 40}
	ready(run)
	var shot := fire(run)
	var strikes: Array = of_type(shot.events, "descent_strike")
	# (8) forty bolts, steps 4..114, some on one tick, forks at most 3
	var bolts: Array = strikes.filter(func(e): return e.phase == "bolt")
	check(bolts.size() == 40, "arc: forty bolts fall (%d)" % bolts.size())
	var ks_ok := true
	var steps: Array = []
	var forks_ok := true
	for i in bolts.size():
		ks_ok = ks_ok and int(bolts[i].k) == i
		steps.append(int(bolts[i].step))
		forks_ok = forks_ok and bolts[i].forks.size() <= 3 and bolts[i].forks.all(func(f): return f.size() == 2 and f[0] == bolts[i].pos)
	check(ks_ok, "arc: the bolts are numbered 0..39 in order")
	var sorted_steps := steps.duplicate()
	sorted_steps.sort()
	check(steps == sorted_steps and steps[0] == 4 and steps[steps.size() - 1] <= 114, "arc: steps run from 4 to at most 114 and never backwards (%d..%d)" % [steps[0], steps[steps.size() - 1]])
	var same_tick := 0
	for i in range(1, steps.size()):
		if steps[i] == steps[i - 1]: same_tick += 1
	check(same_tick >= 1, "arc: bolts may share a tick (%d pairs)" % same_tick)
	var burst_ok := true
	for i in bolts.size():
		var shares: bool = (i > 0 and steps[i - 1] == steps[i]) or (i + 1 < steps.size() and steps[i + 1] == steps[i])
		burst_ok = burst_ok and bool(bolts[i].burst) == shares
	check(burst_ok, "arc: burst is true exactly for the bolts that share a tick")
	check(forks_ok, "arc: at most three forks, each starting where the bolt fell")
	var fork_total := 0
	for b in bolts: fork_total += b.forks.size()
	check(fork_total > 0, "arc: some bolts fork (%d forks)" % fork_total)
	var finale: Array = strikes.filter(func(e): return e.phase == "finale")
	check(finale.size() == 1 and int(finale[0].step) == 120, "arc: one finale strike on step 120")
	check(screen_normals_alive(run) == 0 and alive_ids(run, crowd).is_empty(), "arc: every ordinary enemy on the screen is dead by the end (%d left)" % screen_normals_alive(run))
	var life := 4500 * UNIT
	check(int(boss_e.hp_raw) == life - life * 1200 / 10000, "arc: the boss lost exactly 12 percent (%d)" % int(boss_e.hp_raw))
	check(int(boss_e.get("stunned_until", 0)) > int(shot.start) and boss_e.state == "recover" and boss_e.telegraph.is_empty(), "arc: the boss's windup was cut and it is stunned a moment")
	# bolts keep their distance from the last three (on an empty screen nothing pulls them onto a body)
	var empty := stage("arc")
	ready(empty)
	var empty_shot := fire(empty)
	var empty_bolts: Array = of_type(empty_shot.events, "descent_strike").filter(func(e): return e.phase == "bolt")
	var near_pairs := 0
	for i in empty_bolts.size():
		for j in range(maxi(0, i - 3), i):
			if empty_bolts[i].pos.distance_to(empty_bolts[j].pos) <= 5.0: near_pairs += 1
	check(empty_bolts.size() == 40 and near_pairs == 0, "arc: on an empty screen no bolt falls within 5 m of the three before it (%d near pairs)" % near_pairs)
	var all_in := empty_bolts.all(func(e): return empty._descent_inside(e.pos, empty.hero.position))
	check(all_in, "arc: every bolt falls on the screen")
	# a body within 3.5 m of the point pulls the bolt onto itself: the first bolt of this seed has an enemy placed on its place
	var probe := stage("arc")
	ready(probe)
	var probe_shot := fire(probe)
	var first_bolt: Dictionary = of_type(probe_shot.events, "descent_strike").filter(func(e): return e.phase == "bolt")[0]
	var snapped := stage("arc")
	var lure := put(snapped, first_bolt.pos + Vector2(2.0, 1.0))
	var lure_at: Vector2 = snapped.enemies[lure].position
	ready(snapped)
	var snapped_shot := fire(snapped)
	var snapped_first: Dictionary = of_type(snapped_shot.events, "descent_strike").filter(func(e): return e.phase == "bolt")[0]
	check(snapped_first.pos.is_equal_approx(lure_at) and snapped_first.target_ids.has(lure), "arc: a bolt that falls within 3.5 m of a body is pulled onto it")
	# a cluster: each bolt forks to the neighbours
	var packed := stage("arc")
	var ids: Array = []
	for g in [Vector2(8, 0), Vector2(-6, 6), Vector2(-6, -6)]:
		for k in 5: ids.append(put(packed, g + Vector2(k * 0.8, 0)))
	ready(packed)
	fire(packed)
	check(alive_ids(packed, ids).is_empty(), "arc: and everyone in the clusters is dead at the end")
	# the trial's cap leaves the rest stunned
	var trial := stage("arc")
	var crowd_t := spread(trial, 2.0)
	trial._trial_phase = "hold"
	trial._trial_center = trial.hero.position
	ready(trial)
	fire(trial)
	var left: Array = alive_ids(trial, crowd_t)
	check(crowd_t.size() > 180 and left.size() == crowd_t.size() - 180, "arc: in the trial hold 180 ordinary enemies die (%d left of %d)" % [left.size(), crowd_t.size()])
	check(left.all(func(i): return int(trial.enemies[i].get("stunned_until", 0)) > trial.tick), "arc: the ones left are stunned")

func element_trial_cap() -> void:
	# (4) the trial's cap is data: 7 kills 7 in each shape; and with the shipped 180 a crowd of 250 loses 180
	for element in ["ember", "frost", "arc"]:
		var small := stage(element, func(d): d.normal.trial_kill_cap = 7)
		var group := spread(small, 4.0)
		small._trial_phase = "hold"
		small._trial_center = small.hero.position
		ready(small)
		fire(small)
		check(group.size() > 7 and group.size() - alive_ids(small, group).size() == 7, "%s: normal.trial_kill_cap 7 kills 7 (%d of %d)" % [element, group.size() - alive_ids(small, group).size(), group.size()])
	var big := stage("ember")
	var crowd := spread(big, 2.0)
	big._trial_phase = "hold"
	big._trial_center = big.hero.position
	ready(big)
	fire(big)
	check(crowd.size() > 180 and crowd.size() - alive_ids(big, crowd).size() == 180, "ember: in the trial hold the shipped cap 180 kills 180 of %d" % crowd.size())
	# outside the trial's hold nothing is held back
	var open := stage("ember")
	var herd := spread(open, 2.0)
	ready(open)
	fire(open)
	check(herd.size() > 180 and alive_ids(open, herd).is_empty(), "ember: outside the trial all %d ordinary enemies die" % herd.size())

# ------------------------------------------------------------------ strong enemies and marks

func strong_checks() -> void:
	# (5) the share is exact for every element, with 0 and 4 marks, and never above; a boss kneels 45 ticks
	for element in ["ember", "frost", "arc"]:
		for marks in [0, 2, 4, 9]:
			var run := stage(element)
			var ids := {}
			var spots := {"elite": Vector2(3, 0), "champion": Vector2(-8, 6), "boss": Vector2(6, -7)}
			for role in ["elite", "champion", "boss"]:
				ids[role] = put_strong(run, spots[role], role)
				mark(run.enemies[ids[role]], marks)
			ready(run)
			check(run.request_descent() and run.release_descent(), "strong: %s: the call and the release are accepted" % element)
			var never_over := true
			var sweep := int(run.descent.ultimates[element].sweep_ticks)
			var bases := {"elite": [600, 5000], "champion": [1400, 2000], "boss": [4500, 1200]}
			for i in sweep:
				tick_run(run, 1)
				for role in ids:
					var life: int = int(bases[role][0]) * UNIT
					var share: int = life * (int(bases[role][1]) + mini(marks * 150, 600)) / 10000
					never_over = never_over and life - int(run.enemies[ids[role]].hp_raw) <= share
			check(never_over, "strong: %s %d marks: no strong body ever lost more than its share" % [element, marks])
			for role in ids:
				var life: int = int(bases[role][0]) * UNIT
				var bps: int = int(bases[role][1]) + mini(marks * 150, 600)
				check(int(run.enemies[ids[role]].hp_raw) == life - life * bps / 10000, "strong: %s: a %s with %d marks loses exactly %d bps of its life (%d of %d)" % [element, role, marks, bps, int(run.enemies[ids[role]].hp_raw), life])
			check(int(run.enemies[ids.boss].get("staggered_until", 0)) >= run.tick + 44, "strong: %s: the boss kneels 45 ticks (until %d, now %d)" % [element, int(run.enemies[ids.boss].get("staggered_until", 0)), run.tick])
			check(int(run.enemies[ids.champion].get("stunned_until", 0)) >= run.tick + 44, "strong: %s: the guardian is stunned 45 ticks" % element)
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
	stale.request_descent()
	var stale_call: Dictionary = of_type(stale.events, "descent_called").back() if of_type(stale.events, "descent_called").size() > 0 else {}
	check(int(stale_call.get("marks_in_reach", -1)) == 0, "marks: an expired status does not count")
	var counted := stage("ember")
	mark(counted.enemies[put(counted, Vector2(3, 3))], 2)
	ready(counted)
	counted.request_descent()
	check(int(of_type(counted.events, "descent_called").back().marks_in_reach) == 2, "marks: descent_called counts the marks on the screen")

# ------------------------------------------------------------------ Q-D8: every kill is named

func cause_checks() -> void:
	# (9) every kill of the descent is named in a descent_strike of the same tick, even when more than 64 die at once
	for element in ["ember", "frost", "arc"]:
		var run := stage(element)
		var crowd := spread(run, 2.0)
		put_strong(run, Vector2(5, 5), "champion")
		ready(run)
		var shot := fire(run)
		var named := {}
		var biggest := 0
		for e in of_type(shot.events, "descent_strike"):
			var key := int(e.tick)
			if not named.has(key): named[key] = {}
			for id_ in e.target_ids: named[key][int(id_)] = true
			biggest = maxi(biggest, e.target_ids.size())
			check(e.target_ids.size() <= 64 and e.positions.size() == e.target_ids.size() and e.marks_at.size() <= 32 and e.has("center") and e.has("element") and e.has("step"), "cause: %s: a strike event keeps its shape (<=64 ids, parallel positions)" % element)
		var unnamed := 0
		var kills := 0
		for e in of_type(shot.events, "death"):
			if String(e.skill_id).begins_with("descent."):
				kills += 1
				if not (named.has(int(e.tick)) and named[int(e.tick)].has(int(e.target_id))): unnamed += 1
		check(kills >= crowd.size() and unnamed == 0, "cause: %s: all %d descent kills are named in the strike events of their tick (%d unnamed)" % [element, kills, unnamed])
		if element != "frost": check(biggest > 0, "cause: %s: strikes name bodies" % element)

# ------------------------------------------------------------------ end tick, invulnerability, spawn breath, view

func end_checks() -> void:
	var run := stage("ember")
	var near_orbs := [Vector2(6, 0), Vector2(-9, 3), Vector2(0, -11)]
	for p in near_orbs: run._drop_orb(p, 1)
	var item := {"uid": 5001, "position": Vector2(4, 4), "collected": false, "drop_tick": 0, "stats": {}, "quality": "common", "slot": "weapon"}
	var edge_item := {"uid": 5003, "position": Vector2.from_angle(deg_to_rad(-38.2)) * 16.0, "collected": false, "drop_tick": 0, "stats": {}, "quality": "common", "slot": "weapon"}
	var far_item := {"uid": 5002, "position": Vector2(60, 0), "collected": false, "drop_tick": 0, "stats": {}, "quality": "common", "slot": "weapon"}
	run.items.append(item)
	run.items.append(edge_item)
	run.items.append(far_item)
	var inventory_before: int = run.inventory.size()
	put(run, Vector2(3, 3))
	ready(run)
	var shot := fire(run)
	var vacuum: Array = of_type(shot.events, "orb_vacuum")
	check(vacuum.size() == 1 and String(vacuum[0].by) == "descent" and run.orbs.is_empty(), "end: the orbs on the floor come in with orb_vacuum {by: descent}: " + str(vacuum.map(func(e): return e.get("by", ""))))
	var pickups: Array = of_type(shot.events, "item_pickup").filter(func(e): return bool(e.get("swept", false)) and String(e.get("by", "")) == "descent")
	check(pickups.size() == 2 and run.inventory.size() == inventory_before + 2 and run.items.size() == 1 and int(run.items[0].uid) == 5002, "end: the items on the screen (one 16 m to the right) go to the bag, the far one stays on the floor")
	var end_tick: int = int(of_type(shot.events, "descent_end")[0].tick)
	check(end_tick == int(shot.start) + 132 and int(vacuum[0].tick) == end_tick, "end: the vacuum and the report come on the last tick (%d)" % end_tick)
	# the level that the orbs bring opens the card screen at once
	var lucky := stage("arc", Callable(), 11, false, Callable(), false)
	lucky._drop_orb(Vector2(5, 0), 30)
	lucky._drop_orb(Vector2(-5, 0), 30)
	ready(lucky)
	lucky.request_descent()
	lucky.release_descent()
	var saw_end := false
	for i in 130:
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
	for i in 170:
		guard.hero.hp_raw = guard.hero.max_hp_raw
		guard.step(Vector2.ZERO)
		var life_before: int = guard.hero.hp_raw
		guard._hero_damage(10 * UNIT, Vector2(1, 0), "hazard", 0)
		hit_log.append(guard.hero.hp_raw < life_before)
	var first_hurt := hit_log.find(true)
	check(first_hurt == 161, "invulnerable: the first blow that lands is on step %d after the release (expected 162 = 132 + 30, index 161)" % (first_hurt + 1))
	check(int(guard.descent_view().iframe_until_tick) == start + 162, "invulnerable: the view names the tick it ends (%d)" % int(guard.descent_view().iframe_until_tick))
	# (10) the breath: nothing ordinary spawns from the release on, and not until 90 ticks after the end
	for element in ["ember", "frost", "arc"]:
		var breath := stage(element)
		breath._next_spawn = 0
		ready(breath)
		breath.request_descent()
		breath.release_descent()
		var release_tick: int = breath.tick
		var sweep := int(breath.descent.ultimates[element].sweep_ticks)
		var timeline := tick_run(breath, sweep)
		check(of_type(timeline, "descent_end").size() == 1, "breath: %s: the sweep ended" % element)
		check(of_type(timeline, "spawn").filter(func(e): return not e.elite).is_empty(), "breath: %s: nothing ordinary spawned during the sweep" % element)
		var after := tick_run(breath, 120)
		var spawns: Array = of_type(after, "spawn").filter(func(e): return not e.elite)
		var first_spawn: int = int(spawns[0].tick) if spawns.size() > 0 else -1
		var end_at: int = int(of_type(timeline, "descent_end")[0].tick)
		check(first_spawn >= end_at + 90 and first_spawn <= end_at + 92, "breath: %s: the first new enemy comes %d ticks after the end (90 expected, from the release %d)" % [element, first_spawn - end_at, first_spawn - release_tick])

func view_checks() -> void:
	var run := stage("frost", func(d): d.cost = [2000, 4000])
	var view: Dictionary = run.descent_view()
	check(view.keys() == ["enabled", "element", "gauge", "cost_now", "ratio_bps", "ready", "state", "uses", "first", "sweep_left_ticks", "iframe_until_tick", "area", "sweep_ticks"], "view: the keys are as the contract says: " + str(view.keys()))
	check(view.enabled and view.element == "frost" and int(view.gauge) == 0 and int(view.cost_now) == 2000 and view.state == "charging" and not view.ready and int(view.uses) == 0 and view.first, "view: charging: " + str(view))
	check(view.area == {"right_deg": -38.2, "half_w_m": 17.3, "half_h_m": 13.4} and int(view.sweep_ticks) == 150, "view: the area and this element's sweep length: " + str(view.area))
	run._descent_add(500)
	check(int(run.descent_view().ratio_bps) == 2500, "view: ratio_bps is the share of cost_now (2500)")
	run._descent_add(1500)
	check(run.descent_view().state == "ready" and run.descent_view().ready, "view: ready")
	run.request_descent()
	check(run.descent_view().state == "hold" and run.descent_view().first, "view: hold, and it is the first")
	run.release_descent()
	var swept: Dictionary = run.descent_view()
	check(swept.state == "sweep" and int(swept.sweep_left_ticks) == 150 and int(swept.uses) == 1 and swept.first and int(swept.gauge) == 0, "view: sweep with 150 ticks left, still the first: " + str(swept))
	tick_run(run, 10)
	check(int(run.descent_view().sweep_left_ticks) == 140, "view: the ticks left run down")
	tick_run(run, 140)
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
	# the sweep in the snapshot: the contract's keys, and no centre (it is the hero's place every tick)
	var snap := stage("ember")
	ready(snap)
	snap.request_descent()
	snap.release_descent()
	tick_run(snap, 40)
	var sweep: Dictionary = snap.snapshot().descent.sweep
	check(sweep.has_all(["element", "start_tick", "until_tick", "hit_ids", "strong_paid", "frozen", "booked", "next_k"]) and not sweep.has("center") and not sweep.has("heading"), "view: the snapshot's sweep has the contract's keys and no centre: " + str(sweep.keys()))
	check(sweep.booked.size() == 14 and int(sweep.next_k) >= 1 and snap.snapshot().descent.burn is Array, "view: 14 booked fragments, some landed; burn is a list")

# ------------------------------------------------------------------ burn, determinism, the bot

func burn_check() -> void:
	var run := stage("ember", Callable(), 11, true)
	var champion := put_strong(run, Vector2(5, 0))
	ready(run)
	fire(run)
	check(run._d_burn.size() == 14 and run._d_burn.all(func(b): return b.kind == "ember"), "burn: with the spell composition a fire stays at each of the 14 places")
	var status: Dictionary = run.enemies[champion].get("status", {})
	check(status.has("heat") and int(status.heat.n) >= 1 and status.heat.by.has("descent.ember"), "burn: the guardian where an aimed fragment fell gets heat from the fire (%s)" % str(status))
	tick_run(run, 200)
	check(run._d_burn.is_empty(), "burn: the fires burn out (180 ticks)")
	var plain := stage("ember")
	put_strong(plain, Vector2(5, 0))
	ready(plain)
	fire(plain)
	check(plain._d_burn.is_empty(), "burn: without the composition there is no fire left")
	# the frost ground chills with the composition and slows without it
	var cold := stage("frost", Callable(), 11, true)
	var boss := put_strong(cold, Vector2(5, 0), "boss")
	ready(cold)
	fire(cold)
	tick_run(cold, 35)
	var chill: Dictionary = cold.enemies[boss].get("status", {})
	check(chill.has("chill") and int(chill.chill.n) >= 1 and int(cold.enemies[boss].slow_bps) == 3000, "burn: the frost ground chills (%s) and slows the boss by 30 percent" % str(chill))
	tick_run(cold, 200)
	check(cold._d_burn.is_empty(), "burn: the frost ground melts after 180 ticks")

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
	var books: Array = []
	for i in ticks:
		var move: Vector2 = pilot.decide()
		for e in Policy.use(run, policy):
			if e.type == "descent_called": calls.append(int(e.tick))
		run.step(move)
		for e in run.events:
			if e.type == "descent_end": ends.append({"tick": int(e.tick), "kills": int(e.kills)})
			if e.type == "descent_book": books.append(JSON.stringify(e.fragments))
		if run.mode == "defeat" or run.mode == "victory": break
	return {"hash": JSON.stringify(run.snapshot()).sha256_text(), "ends": ends, "calls": calls, "books": books, "uses": int(run.descent_view().uses), "tick": run.tick, "mode": run.mode}

func determinism_checks() -> void:
	for primary in ["chapter1.skill.ember", "chapter1.skill.frost", "chapter1.skill.arc"]:
		# (11) the same seed and the same input twice: the same snapshot; another seed: other places
		var a := play_with_policy("now", 11, primary, 2400)
		var b := play_with_policy("now", 11, primary, 2400)
		check(a.hash == b.hash and JSON.stringify(a.ends) == JSON.stringify(b.ends) and a.books == b.books, "determinism: %s twice with the same seed and the bot's calls: same snapshot" % primary)
		check(int(a.uses) >= 1 and a.ends.size() >= 1 and a.calls.size() >= 1, "determinism: %s the bot used the descent (%d times, ends %d)" % [primary, int(a.uses), a.ends.size()])
		var off := play_with_policy("off", 11, primary, 2400)
		check(int(off.uses) == 0 and off.ends.is_empty(), "determinism: %s with the policy off nothing is used" % primary)
		var other := play_with_policy("now", 12, primary, 2400)
		check(other.hash != a.hash, "determinism: %s another seed gives another run" % primary)
	# the places of the fragments and bolts follow the seed (the hash), not the stage
	var places: Array = []
	for seed_ in [11, 12]:
		var run := stage("ember", Callable(), seed_)
		ready(run)
		var shot := fire(run)
		places.append(JSON.stringify(of_type(shot.events, "descent_book")[0].fragments))
	check(places[0] != places[1], "determinism: another seed puts the fragments elsewhere")
	var again := stage("ember", Callable(), 11)
	ready(again)
	check(JSON.stringify(of_type(fire(again).events, "descent_book")[0].fragments) == places[0], "determinism: the same seed puts them on the same places")
	var arcs: Array = []
	for seed_ in [11, 12]:
		var run := stage("arc", Callable(), seed_)
		ready(run)
		arcs.append(JSON.stringify(of_type(fire(run).events, "descent_strike").filter(func(e): return e.phase == "bolt").map(func(e): return [e.step, e.pos])))
	check(arcs[0] != arcs[1], "determinism: another seed drops the bolts elsewhere and at other times")
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
	rectangle_checks()
	hash_checks()
	gauge_checks()
	stop_checks()
	element_ember()
	element_frost()
	element_arc()
	element_trial_cap()
	strong_checks()
	cause_checks()
	end_checks()
	view_checks()
	burn_check()
	determinism_checks()
	print("CHAPTER1_DESCENT_TEST_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
