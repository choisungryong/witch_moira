extends SceneTree
## W1 check of the run rhythm in the chapter core (D11 A). The shipped combat_tuning.json is read and the rhythm is switched
## on IN MEMORY only (rhythm.enabled / trial.enabled); no data file is edited. Parts:
##   A  one stationary hero: beat order, time limits, per-beat alive cap, lulls, crest fans (taste crest and wave crests)
##   B  a whole pilot run with a short seal and a short trial: trial events, the circle, the boss after it, the last grace,
##      the boss's phase break, objective() and run_progress()
##   C  determinism (A and B twice with the same seed)
##   D  with the rhythm off the snapshots do not depend on a rhythm block being present
##   E  the validator refuses values outside the D11 A6 ranges
##   F  event fields that are always attached (hit.dealt_raw, item_drop.source)
## Marker: CHAPTER1_RHYTHM_TEST_RESULT. Writes nothing.
const Chapter = preload("res://chapter1/core/chapter_core.gd")
const Pilot = preload("res://chapter1/core/chapter_pilot.gd")
const TUNING := "res://chapter1/data/combat_tuning.json"
const DROP_SOURCES := ["normal","forced","chest","elite","carrier","ritual","champion","boss","first_kill","quest","shop"]
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
	return JSON.parse_string(FileAccess.get_file_as_string(TUNING))

## The shipped document with the rhythm switched on (and the trial, when asked), then `mutate` applied.
func document(trial: bool, mutate: Callable = Callable()) -> Dictionary:
	var doc := shipped()
	doc.rhythm.enabled = true
	doc.rhythm.trial.enabled = trial
	if mutate.is_valid(): mutate.call(doc)
	return doc

func make_run(doc: Dictionary, seed_: int = 11, primary: String = "chapter1.skill.ember") -> RefCounted:
	var run = Chapter.new()
	if not run.set_tuning(doc):
		check(false, "document accepted: " + str(run.errors))
		return null
	if not run.start(seed_, primary):
		check(false, "run starts: " + str(run.errors))
		return null
	run.first_boss_kill = true
	return run

## One tick. The hero cannot die (this check is about spawning, not survival); growth choices are taken by the pilot.
func advance(run: RefCounted, pilot: RefCounted, stationary: bool, override_move: Variant = null) -> void:
	var move: Vector2 = pilot.decide()
	if stationary: move = Vector2.ZERO
	if override_move is Vector2: move = override_move
	run.hero.hp_raw = run.hero.max_hp_raw
	run.step(move)

func spawn_events(events: Array) -> Array:
	return events.filter(func(e): return e.type == "spawn" and not e.elite)

## The cap the spawner works under right now (null when the legacy boss-phase rule is in charge).
func cap_now(run: RefCounted) -> Variant:
	var rhythm: Dictionary = run.tuning.rhythm
	if run._trial_phase == "hold": return int(rhythm.trial.alive_cap)
	if run.zone == 2 and run._champion_id > 0: return null
	var beat: Dictionary = rhythm.beats[run._beat_index]
	var cap := mini(int(beat.alive_cap), int(run.tuning.alive_cap))
	if run._in_lull: cap = cap * int(beat.wave.lull_cap_bps) / 10000
	return cap

func lull_amount_now(run: RefCounted) -> int:
	var beat: Dictionary = run.tuning.rhythm.beats[run._beat_index]
	return maxi(1, int(beat.amount) * int(beat.wave.lull_amount_bps) / 10000)

# ------------------------------------------------------------------ A

func scenario_a(verify: bool) -> Dictionary:
	# gi: taste crest at tick 120 and a time limit of 600; seung1 follows by time; seung2 / jeon_a by their (short) limits.
	var doc := document(false, func(d):
		d.rhythm.beats[0].taste_crest.at_ticks = 120
		d.rhythm.beats[0].max_ticks = 600
		d.rhythm.beats[1].max_ticks = 2500
		d.rhythm.beats[2].max_ticks = 60)
	var run := make_run(doc)
	var pilot = Pilot.new()
	pilot.run = run
	var rec := {"beats": [], "crests": [], "lulls": [], "over_cap": 0, "lull_over": 0, "surge_max": 0, "lull_max": 0, "lull_steps": 0, "hash": ""}
	check(run.alive_count() == int(doc.rhythm.initial_pack), "A rhythm on: the opening pack is rhythm.initial_pack (%d)" % run.alive_count())
	var last_seq := -1
	for i in 3300:
		var alive_before: int = run.alive_count()
		advance(run, pilot, true)
		if run.mode != "playing" and run.mode != "choice": break
		var fresh_events: Array = run.events.filter(func(e): return int(e.seq) > last_seq)
		if not fresh_events.is_empty(): last_seq = int(fresh_events[fresh_events.size() - 1].seq)
		var fresh := spawn_events(fresh_events)
		var cap = cap_now(run)
		var crest_tick := false
		for e in fresh_events:
			match String(e.type):
				"beat_started": rec.beats.append({"id": e.id, "tick": int(e.tick)})
				"lull_started": rec.lulls.append({"beat": e.beat, "tick": int(e.tick)})
				"wave_crest":
					crest_tick = true
					var seq_of_crest := int(e.seq)
					var placed: Array = []
					for s in run.events:
						if s.type == "spawn" and not s.elite and int(s.seq) < seq_of_crest: placed.append(s)
					placed = placed.slice(maxi(0, placed.size() - int(e.count)))
					rec.crests.append({"tick": int(e.tick), "beat": e.beat, "count": int(e.count), "direction": e.direction, "placed": placed.map(func(s): return s.position - run.hero.position)})
		if cap != null and not fresh.is_empty() and not crest_tick:
			# Spawning never lifts the count past the cap of the rule in force (the cap only stops spawning, it removes nobody).
			if alive_before + fresh.size() > int(cap): rec.over_cap += 1
			if run._in_lull:
				rec.lull_steps += 1
				rec.lull_max = maxi(int(rec.lull_max), fresh.size())
				if fresh.size() > lull_amount_now(run): rec.lull_over += 1
			elif run._beat_index == 1: rec.surge_max = maxi(int(rec.surge_max), fresh.size())
		elif cap != null and crest_tick and alive_before + fresh.size() > int(cap) + 0: rec.over_cap += 1
	rec.hash = JSON.stringify(run.snapshot()).sha256_text()
	rec.events_dropped = int(run.metrics.get("events_dropped", 0))
	if not verify: return rec
	var ids: Array = rec.beats.map(func(b): return b.id)
	check(ids == ["gi", "seung1", "seung2", "jeon_a"], "A beat_started comes in table order: " + str(ids))
	if rec.beats.size() == 4:
		check(int(rec.beats[0].tick) == 1, "A the first beat starts on tick 1 (tick %d)" % int(rec.beats[0].tick))
		check(int(rec.beats[1].tick) == int(rec.beats[0].tick) + 600, "A gi hands over by its time limit (max_ticks 600): %d -> %d" % [int(rec.beats[0].tick), int(rec.beats[1].tick)])
		check(int(rec.beats[2].tick) == int(rec.beats[1].tick) + 2500, "A seung1 hands over by its time limit: %d -> %d" % [int(rec.beats[1].tick), int(rec.beats[2].tick)])
		check(int(rec.beats[3].tick) == int(rec.beats[2].tick) + 60, "A seung2 hands over by its time limit: %d -> %d" % [int(rec.beats[2].tick), int(rec.beats[3].tick)])
	check(int(rec.over_cap) == 0, "A spawning never takes the alive count past the beat's cap (%d violations)" % int(rec.over_cap))
	check(rec.crests.size() >= 2, "A at least the taste crest and one wave crest happened (%d)" % rec.crests.size())
	for crest in rec.crests:
		var arc_deg: float = float({"gi": 60, "seung1": 70, "seung2": 80, "jeon_a": 90}[String(crest.beat)])
		var heading: float = crest.direction.angle()
		var worst := 0.0
		for offset in crest.placed:
			worst = maxf(worst, absf(angle_difference(heading, offset.angle())))
		check(crest.placed.size() == int(crest.count) and int(crest.count) > 0, "A crest at tick %d placed its %d bodies" % [int(crest.tick), int(crest.count)])
		check(worst <= deg_to_rad(arc_deg) * .5 + 0.01, "A crest at tick %d lies inside its %.0f degree fan (worst %.1f degrees off the heading)" % [int(crest.tick), arc_deg, rad_to_deg(worst)])
	if rec.crests.size() > 0: check(String(rec.crests[0].beat) == "gi" and int(rec.crests[0].tick) >= 120 and int(rec.crests[0].tick) < 130, "A the taste crest comes at at_ticks (120)")
	var seung1_start: int = int(rec.beats[1].tick) if rec.beats.size() > 1 else 0
	check(rec.lulls.size() >= 1 and String(rec.lulls[0].beat) == "seung1" and int(rec.lulls[0].tick) == seung1_start + 2400 - 720, "A the first lull starts at period - lull_ticks after the beat (%s)" % str(rec.lulls))
	check(int(rec.lull_steps) > 0 and int(rec.lull_over) == 0, "A in a lull one spawn step brings at most the lull amount (%d steps, %d over)" % [int(rec.lull_steps), int(rec.lull_over)])
	check(int(rec.surge_max) > int(rec.lull_max), "A a surge step brings more than a lull step (%d vs %d)" % [int(rec.surge_max), int(rec.lull_max)])
	return rec

# ------------------------------------------------------------------ B

func scenario_b(verify: bool) -> Dictionary:
	var doc := document(true, func(d):
		d.seal_kills = [40, 40, 40]
		d.rhythm.trial.hold_ticks = 600
		d.rhythm.trial.clear_ticks = 180)
	var run := make_run(doc)
	var pilot = Pilot.new()
	pilot.run = run
	var rec := {"events": [], "max_out": 0.0, "min_out": 1.0e9, "objective_trial": [], "progress_trial": [], "progress_boss": [], "objective_boss": [], "champion_tick": -1, "xp_at_boss": -1, "level_at_boss": -1, "spawns_in_clear": 0, "over_cap": 0, "hold_start": -1, "hold_end": -1}
	var last_seq := -1
	var push_dir := Vector2.ZERO
	var last_threshold: int = int(doc.xp_thresholds[doc.xp_thresholds.size() - 1])
	for i in 60000:
		var alive_before: int = run.alive_count()
		var holding: bool = run._trial_phase == "hold"
		# During the hold the hero pushes against the wall of the circle.
		var push: Variant = null
		# Toward the far side of the zone, so the zone's own wall cannot be what stops the hero first.
		if holding:
			if push_dir == Vector2.ZERO: push_dir = Vector2.RIGHT if run.hero.position.x < 96.0 else Vector2.LEFT
			push = push_dir
		advance(run, pilot, false, push)
		if run.mode == "choice" or run.mode == "playing":
			pass
		else:
			break
		var fresh_events: Array = run.events.filter(func(e): return int(e.seq) > last_seq)
		if not fresh_events.is_empty(): last_seq = int(fresh_events[fresh_events.size() - 1].seq)
		var fresh := spawn_events(fresh_events)
		var cap = cap_now(run) if run._beat_index >= 0 else null
		if cap != null and not fresh.is_empty() and alive_before + fresh.size() > int(cap) + 0:
			# A crest tick may also have spawned regular bodies; both obey the same cap, so this holds for the sum.
			rec.over_cap += 1
		for e in fresh_events:
			rec.events.append({"type": e.type, "tick": int(e.tick), "id": e.get("id", ""), "zone": e.get("zone", -1)})
			match String(e.type):
				"trial_started":
					rec.hold_start = int(e.tick)
					rec.until_tick = int(e.until_tick)
					rec.radius = float(e.radius_m)
					rec.center = e.position
				"trial_completed": rec.hold_end = int(e.tick)
				"chapter_champion":
					if int(e.zone) == 2:
						rec.champion_tick = int(e.tick)
						rec.xp_at_boss = int(run.growth.snapshot().xp)
						rec.level_at_boss = int(run.growth.snapshot().level)
				"spawn":
					if not e.elite and run._trial_phase == "clear": rec.spawns_in_clear += 1
		if run._trial_phase == "hold":
			var away: float = run.hero.position.distance_to(run._trial_center)
			rec.max_out = maxf(float(rec.max_out), away)
			rec.min_out = minf(float(rec.min_out), away)
			if rec.objective_trial.size() < 3 or run.tick % 100 == 0: rec.objective_trial.append(run.objective())
			if rec.progress_trial.size() < 3: rec.progress_trial.append(run.run_progress())
		if run.zone == 2 and run._champion_id > 0 and run.enemies.has(run._champion_id):
			if rec.objective_boss.size() < 2: rec.objective_boss.append(run.objective())
			if rec.progress_boss.size() < 2: rec.progress_boss.append(run.run_progress())
	rec.mode = run.mode
	rec.tick = run.tick
	rec.hash = JSON.stringify(run.snapshot()).sha256_text()
	if not verify: return rec
	check(run.mode == "victory", "B the run reaches the victory (mode %s, tick %d)" % [run.mode, run.tick])
	var ids: Array = []
	for e in rec.events:
		if e.type == "beat_started": ids.append(e.id)
	check(ids == ["gi", "seung1", "seung2", "jeon_a", "trial", "boss"], "B beats come in order, then the trial and the boss: " + str(ids))
	check(int(rec.hold_start) > 0 and int(rec.hold_end) == int(rec.hold_start) + 600, "B the trial holds hold_ticks (%d -> %d)" % [int(rec.hold_start), int(rec.hold_end)])
	check(int(rec.until_tick) == int(rec.hold_start) + 600 and is_equal_approx(float(rec.radius), 12.0), "B trial_started carries until_tick and radius_m")
	check(float(rec.max_out) <= 12.0 + 0.0001, "B the hero never leaves the circle (farthest %.4f m of 12)" % float(rec.max_out))
	check(float(rec.max_out) >= 11.99, "B the circle really held the hero back (farthest %.4f m)" % float(rec.max_out))
	check(int(rec.champion_tick) >= int(rec.hold_end) + 180, "B the boss comes after the clearing time (hold end %d, boss %d)" % [int(rec.hold_end), int(rec.champion_tick)])
	check(int(rec.spawns_in_clear) == 0, "B nothing spawns while the arena is cleared")
	check(int(rec.level_at_boss) == int(doc.xp_thresholds.size()) and int(rec.xp_at_boss) >= last_threshold, "B the last grace lands when the boss appears (level %d, xp %d)" % [int(rec.level_at_boss), int(rec.xp_at_boss)])
	var graces: Array = []
	for e in rec.events:
		if e.type == "seal_grace": graces.append(int(e.tick))
	check(graces.size() <= 1 and (graces.is_empty() or graces[0] == int(rec.champion_tick)), "B the last grace is not before the boss spawns (%s)" % str(graces))
	check(int(rec.over_cap) == 0, "B spawning never takes the count past the cap (%d violations)" % int(rec.over_cap))
	check(rec.objective_trial.size() > 0, "B objective() was read during the trial")
	for o in rec.objective_trial:
		check(o.kind == "trial" and int(o.total) == 600 and int(o.done) >= 0 and int(o.done) <= 600, "B objective during the trial is kind trial with the ticks left: " + str(o.kind) + " " + str(o.done))
	if rec.objective_trial.size() > 1: check(int(rec.objective_trial[0].done) > int(rec.objective_trial[rec.objective_trial.size() - 1].done), "B the ticks left fall during the trial")
	check(rec.objective_boss.size() > 0 and rec.objective_boss[0].kind == "boss" and int(rec.objective_boss[0].hp_max) > 0, "B objective during the boss is kind boss with its health")
	check(rec.progress_trial.size() > 0 and rec.progress_trial[0].phase == "trial" and rec.progress_trial[0].beat_id == "trial", "B run_progress says trial while it holds")
	check(rec.progress_boss.size() > 0 and rec.progress_boss[0].phase == "boss", "B run_progress says boss while the boss lives")
	for p in rec.progress_trial + rec.progress_boss:
		check(p.keys() == ["beat_id", "zone", "zone_bps", "phase", "markers"] and int(p.zone) == 2 and int(p.zone_bps) >= 0 and int(p.zone_bps) <= 10000 and p.markers is Array and p.markers.size() == 4, "B run_progress has its shape: " + str(p.keys()))
	# phase break: no floor strike is announced within phase_break_ticks of the half-health change
	var phase_tick := -1
	for e in rec.events:
		if e.type == "boss_phase": phase_tick = int(e.tick)
	check(phase_tick > 0, "B the boss reached its second phase")
	var announced_in_break := 0
	for e in rec.events:
		if e.type == "chapter_warning" and int(e.tick) >= phase_tick and int(e.tick) < phase_tick + 120: announced_in_break += 1
	check(phase_tick > 0 and announced_in_break == 0, "B no floor strike is announced during the 120-tick phase break (%d)" % announced_in_break)
	return rec

# ------------------------------------------------------------------ D

func off_runs() -> void:
	var with_block := shipped()
	var without := shipped()
	without.erase("rhythm")
	var trial_only := shipped()
	trial_only.rhythm.trial.enabled = true
	var hashes: Array = []
	for doc in [with_block, without, trial_only]:
		var run := make_run(doc, 11, "chapter1.skill.frost")
		var pilot = Pilot.new()
		pilot.run = run
		var trail: Array[String] = []
		var hits := 0
		var dealt_ok := true
		var sources_ok := true
		var rhythm_events := 0
		for i in 2400:
			run.step(pilot.decide())
			if i % 400 == 399: trail.append(JSON.stringify(run.snapshot()).sha256_text())
			for e in run.events:
				if e.type == "hit":
					hits += 1
					dealt_ok = dealt_ok and e.has("dealt_raw") and int(e.dealt_raw) >= 0 and int(e.dealt_raw) <= int(e.damage_raw)
				if e.type == "item_drop": sources_ok = sources_ok and e.has("source") and String(e.source) in DROP_SOURCES
				if String(e.type) in ["beat_started", "wave_crest", "lull_started", "trial_started", "trial_completed"]: rhythm_events += 1
			if run.mode == "defeat": break
		hashes.append(trail)
		check(hits > 0 and dealt_ok, "F every hit carries dealt_raw, never above damage_raw (%d hits)" % hits)
		check(sources_ok, "F every item_drop carries a known source")
		check(rhythm_events == 0, "D rhythm off emits no rhythm event (%d)" % rhythm_events)
		var progress: Dictionary = run.run_progress()
		check(progress.keys() == ["beat_id", "zone", "zone_bps", "phase", "markers"] and progress.beat_id == "" and progress.phase in ["surge", "rest"], "D run_progress works with the rhythm off: " + str(progress))
		check(run.objective().kind in ["seal_kills", "move", "champion"], "D objective keeps its old kinds with the rhythm off")
	check(hashes[0] == hashes[1] and hashes[0] == hashes[2], "D rhythm off: snapshots equal with the block, without it, and with only the trial flag on")
	check(hashes[0].size() >= 5, "D the comparison ran long enough (%d checkpoints)" % hashes[0].size())

# ------------------------------------------------------------------ E

func rejects(label: String, mutate: Callable) -> void:
	var doc := shipped()
	mutate.call(doc)
	var run = Chapter.new()
	var ok: bool = run.set_tuning(doc)
	var named := false
	for line in run.errors:
		if String(line).begins_with("rhythm"): named = true
	check(not ok and named, "E refused: " + label + " " + str(run.errors))

func validator_checks() -> void:
	var run = Chapter.new()
	check(run.set_tuning(shipped()), "E the shipped document (rhythm off) is accepted")
	var bare := shipped()
	bare.erase("rhythm")
	check(run.set_tuning(bare), "E a document without a rhythm block is accepted")
	var on_doc := document(true)
	check(run.set_tuning(on_doc), "E the document with the rhythm and the trial on is accepted")
	rejects("amount 31", func(d): d.rhythm.beats[0].amount = 31)
	rejects("amount -1", func(d): d.rhythm.beats[0].amount = -1)
	rejects("interval_ticks 11", func(d): d.rhythm.beats[1].interval_ticks = 11)
	rejects("interval_ticks 601", func(d): d.rhythm.beats[1].interval_ticks = 601)
	rejects("alive_cap above the document cap", func(d): d.rhythm.beats[2].alive_cap = 101)
	rejects("alive_cap 0", func(d): d.rhythm.beats[2].alive_cap = 0)
	rejects("hp_bps start 4999", func(d): d.rhythm.beats[0].hp_bps = [4999, 10000])
	rejects("hp_bps end 80001", func(d): d.rhythm.beats[0].hp_bps = [10000, 80001])
	rejects("hp_bps single number in a beat", func(d): d.rhythm.beats[0].hp_bps = 10000)
	rejects("from_bps not rising inside a zone", func(d): d.rhythm.beats[1].from_bps = 0)
	rejects("from_bps 10000", func(d): d.rhythm.beats[1].from_bps = 10000)
	rejects("zones going back", func(d):
		d.rhythm.beats[2].zone = 2
		d.rhythm.beats[3].zone = 1)
	rejects("first beat not at zone 0 progress 0", func(d): d.rhythm.beats[0].from_bps = 100)
	rejects("period not above lull", func(d): d.rhythm.beats[1].wave.lull_ticks = 2400)
	rejects("hold_ticks 599", func(d): d.rhythm.trial.hold_ticks = 599)
	rejects("hold_ticks 5401", func(d): d.rhythm.trial.hold_ticks = 5401)
	rejects("trial hp_bps 4999", func(d): d.rhythm.trial.hp_bps = 4999)
	rejects("trial radius 0", func(d): d.rhythm.trial.radius_m = 0.0)
	rejects("trial amount 31", func(d): d.rhythm.trial.amount = 31)
	rejects("unknown key in a beat", func(d): d.rhythm.beats[0].extra = 1)
	rejects("beat without mix", func(d): d.rhythm.beats[0].erase("mix"))
	rejects("mix of zeros", func(d): d.rhythm.beats[0].mix = {"walker": 0, "ranged": 0, "charger": 0})
	rejects("duplicate beat id", func(d): d.rhythm.beats[1].id = "gi")
	rejects("enabled as a number", func(d): d.rhythm.enabled = 1)
	rejects("no trial block", func(d): d.rhythm.erase("trial"))
	rejects("crest count 0", func(d): d.rhythm.beats[1].wave.crest.count = 0)
	rejects("phase_break_ticks 601", func(d): d.rhythm.boss.phase_break_ticks = 601)
	rejects("initial_pack 41", func(d): d.rhythm.initial_pack = 41)
	rejects("rhythm not a dictionary", func(d): d.rhythm = [])
	# the replacement is atomic: a refused document leaves the run's tuning alone
	var holder = Chapter.new()
	holder.set_tuning(shipped())
	var before: String = JSON.stringify(holder.tuning)
	var bad := shipped()
	bad.rhythm.beats[0].amount = 99
	check(not holder.set_tuning(bad) and JSON.stringify(holder.tuning) == before, "E a refused document changes nothing")

func hp_factor_check() -> void:
	var doc := document(false, func(d): d.hp_time_bps_per_s = 0)
	var run := make_run(doc)
	run.enemies.clear()
	run._alive = 0
	run.tick = 31 * 60
	run._spawn_hp_bps = 20000
	run._spawn("walker", Vector2(6, 0))
	check(run.enemies[run._enemy_sequence].max_hp_raw == 14 * 2 * 256, "A the beat's hp factor multiplies the zone's base health (walker 14 x 2.0)")
	run._spawn_hp_bps = 10000
	var off = make_run(shipped())
	off.tick = 31 * 60
	off._spawn_hp_bps = 20000
	off.enemies.clear()
	off._alive = 0
	off._spawn("walker", Vector2(6, 0))
	check(off.enemies[off._enemy_sequence].max_hp_raw == 14 * (10000 + 160 * 31) / 10000 * 256, "A with the rhythm off the factor is not read")

func execute() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/_local/appdata/"):
		print("CHAPTER1_RHYTHM_TEST_RESULT ", JSON.stringify({"checks": 0, "failures": ["user data dir is not isolated: refusing to run"]}))
		quit(1)
		return
	validator_checks()
	hp_factor_check()
	var a1 := scenario_a(true)
	var a2 := scenario_a(false)
	check(a1.hash == a2.hash and JSON.stringify(a1.beats) == JSON.stringify(a2.beats) and JSON.stringify(a1.crests) == JSON.stringify(a2.crests), "C scenario A twice with the same seed: same snapshot, beats and crests")
	var b1 := scenario_b(true)
	var b2 := scenario_b(false)
	check(b1.hash == b2.hash and int(b1.tick) == int(b2.tick) and JSON.stringify(b1.events) == JSON.stringify(b2.events), "C scenario B twice with the same seed: same snapshot (tick %d) and same event stream" % int(b1.tick))
	off_runs()
	print("CHAPTER1_RHYTHM_TEST_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
