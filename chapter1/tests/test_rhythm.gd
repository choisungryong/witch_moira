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
##   R1B the optional threat keys of D22 (crest.mix, squad, ranged_cap, guardian, count_jitter_bps) and the wider crest count
## Marker: CHAPTER1_RHYTHM_TEST_RESULT. Writes nothing.
const Chapter = preload("res://chapter1/core/chapter_core.gd")
const Pilot = preload("res://chapter1/core/chapter_pilot.gd")
const TrialDocs = preload("res://chapter1/tests/support/trial_docs.gd")
const TUNING :="res://chapter1/data/combat_tuning.json"
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

func make_run(doc: Dictionary, seed_: int = 11, primary: String = "chapter1.skill.ember", first_visit: bool = true) -> RefCounted:
	var run = Chapter.new()
	if not run.set_tuning(doc):
		check(false, "document accepted: " + str(run.errors))
		return null
	run.opening_first_visit = first_visit
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
		# The shipped gi has no taste crest since D15 O-2 (the opening carries the first pack); this scenario gives it one.
		d.rhythm.beats[0].taste_crest = {"at_ticks": 120, "count": 8, "arc_deg": 60}
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
	# W1b: the time limit hands over inside the zone only. seung1 is the last beat of zone 0 and its limit (2500) runs out
	# during the loop, yet seung2 / jeon_a (later zones, the latter with a 60 tick limit on seung2) never start.
	check(ids == ["gi", "seung1"], "A time limits hand over inside the zone only, never into a later zone's beat: " + str(ids))
	if rec.beats.size() == 2:
		check(int(rec.beats[0].tick) == 1, "A the first beat starts on tick 1 (tick %d)" % int(rec.beats[0].tick))
		check(int(rec.beats[1].tick) == int(rec.beats[0].tick) + 600, "A gi hands over by its time limit (max_ticks 600): %d -> %d" % [int(rec.beats[0].tick), int(rec.beats[1].tick)])
		check(int(rec.beats[1].tick) + 2500 < 3300, "A the loop outlasted seung1's time limit (%d)" % int(rec.beats[1].tick))
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
				if String(e.type) in ["beat_started", "wave_crest", "lull_started", "trial_started", "trial_completed", "opening_step", "opening_end"]: rhythm_events += 1
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
	# The clock factor is read from the shipped data (160 until 2026-11-20, 65 since D19 W-D), not written here.
	var clock := int(shipped().hp_time_bps_per_s)
	check(clock > 0 and off.enemies[off._enemy_sequence].max_hp_raw == 14 * (10000 + clock * 31) / 10000 * 256, "A with the rhythm off the factor is not read")
	# W1b: rhythm on, clock factor left at its shipped value: the clock must not multiply on top of the beat's factor.
	var on = make_run(document(false))
	check(int(on.tuning.hp_time_bps_per_s) == clock, "W1b the shipped clock factor is unchanged in the enabled document")
	on.enemies.clear()
	on._alive = 0
	on.tick = 300 * 60
	on._spawn_hp_bps = 20000
	on._spawn("walker", Vector2(6, 0))
	check(on.enemies[on._enemy_sequence].max_hp_raw == 14 * 2 * 256, "W1b rhythm on: no clock factor on top of hp_bps at 300 s (%d)" % int(on.enemies[on._enemy_sequence].max_hp_raw))

## W1b: with the rhythm on a time limit never crosses a zone border; the last beat of a zone stays.
func zone_limit_check() -> void:
	var run := make_run(document(false, func(d):
		for b in d.rhythm.beats: b.max_ticks = 60))
	var pilot = Pilot.new()
	pilot.run = run
	var seen: Array = []
	for i in 1200:
		advance(run, pilot, true)
		if run.mode != "playing" and run.mode != "choice": break
		for e in run.events:
			if e.type == "beat_started" and not seen.has(e.id): seen.append(e.id)
	check(seen == ["gi", "seung1"] and run.zone == 0, "W1b a beat limit of 60 ticks passes gi -> seung1 and stops at the zone edge: " + str(seen))
	# the zone border moves the beat only through the zone and seal progress
	run._beat_index = 1
	run._beat_tick = 0
	run.zone = 1
	run._zone_entered = true
	run.tick = 5000
	run._rhythm_tick()
	check(run._beat_index == 2, "W1b entering zone 1 starts seung2 by zone progress, not by time")

# ------------------------------------------------------------------ O (D15 O-1, the run opening)

func opening_doc(mutate: Callable = Callable()) -> Dictionary:
	return document(false, func(d):
		d.rhythm.opening.enabled = true
		if mutate.is_valid(): mutate.call(d))

func step_rule(doc: Dictionary, id: String) -> Dictionary:
	for s in doc.rhythm.opening.steps:
		if s.id == id: return s
	return {}

## One stationary hero in the opening: every event of interest with the step it fell in.
func scenario_o(doc: Dictionary, ticks: int, first_visit: bool = true, seed_: int = 11) -> Dictionary:
	var run := make_run(doc, seed_, "chapter1.skill.ember", first_visit)
	var pilot = Pilot.new()
	pilot.run = run
	var rec := {"steps": [], "spawns": [], "crests": [], "ends": [], "beats": [], "cast_far": 0, "casts": {}, "far_ticks": {}, "xp_pickups": {}, "kills": {},
		"alive_max": {}, "alive_at": {}, "level_tick": -1, "hash": "", "snap_step": []}
	var cur := ""
	var last_seq := -1
	for i in ticks:
		advance(run, pilot, true)
		if run.mode != "playing" and run.mode != "choice": break
		var near := 1.0e9
		var alive := 0
		for e in run.enemies.values():
			if e.hp_raw > 0:
				alive += 1
				near = minf(near, e.position.distance_to(run.hero.position))
		var acquire := 13.0
		for e in run.events:
			if int(e.seq) <= last_seq: continue
			last_seq = int(e.seq)
			match String(e.type):
				"opening_step":
					cur = String(e.id)
					rec.steps.append({"id": cur, "index": int(e.index), "tick": int(e.tick), "heading": e.heading, "ring": e.ring_m})
				"opening_end": rec.ends.append({"tick": int(e.tick), "finished": bool(e.finished), "kills": int(e.kills)})
				"beat_started": rec.beats.append({"id": String(e.id), "tick": int(e.tick)})
				"spawn":
					if not e.elite:
						var enemy: Dictionary = run.enemies[int(e.target_id)]
						rec.spawns.append({"step": cur, "tick": int(e.tick), "rel": e.position - run.hero.position, "opening": bool(e.get("opening", false)), "first": bool(e.get("first_of_step", false)), "speed": float(enemy.definition.speed)})
				"wave_crest": rec.crests.append({"step": cur, "tick": int(e.tick), "count": int(e.count), "direction": e.direction})
				"death":
					rec.kills[cur] = int(rec.kills.get(cur, 0)) + 1
					if not rec.has("kill_ticks"): rec["kill_ticks"] = {}
					if not rec.kill_ticks.has(cur): rec.kill_ticks[cur] = []
					rec.kill_ticks[cur].append(int(e.tick))
				"xp_pickup": rec.xp_pickups[cur] = int(rec.xp_pickups.get(cur, 0)) + 1
				"level_choice":
					if rec.level_tick < 0: rec.level_tick = int(e.tick)
				"cast":
					rec.casts[cur] = int(rec.casts.get(cur, 0)) + 1
					var rule := step_rule(doc, cur)
					if not rule.is_empty() and rule.acquire_m != null: acquire = float(rule.acquire_m)
					if near > acquire + 0.001: rec.cast_far += 1
		var rule_now := step_rule(doc, cur)
		var acquire_now := 13.0 if rule_now.is_empty() or rule_now.acquire_m == null else float(rule_now.acquire_m)
		if near > acquire_now + 0.2 and near < 13.0: rec.far_ticks[cur] = int(rec.far_ticks.get(cur, 0)) + 1
		rec.alive_max[cur] = maxi(int(rec.alive_max.get(cur, 0)), alive)
		if run.tick == 360 or run.tick == 361: rec.alive_at[run.tick] = alive
		if run.tick % 600 == 0: rec.snap_step.append(JSON.stringify(run.snapshot().rhythm.get("opening", {}), "", false))
	rec.hash = JSON.stringify(run.snapshot()).sha256_text()
	rec.run = run
	return rec

func opening_checks() -> void:
	var doc := opening_doc()
	var a := scenario_o(doc, 4000)
	var ids: Array = a.steps.map(func(s): return s.id)
	check(ids == ["look", "one", "two", "pack", "around"], "O the five steps come in order: " + str(ids))
	check(a.ends.size() == 1 and a.ends[0].finished, "O opening_end comes once, finished: " + str(a.ends))
	check(a.beats.size() >= 1 and a.beats[0].id == "gi" and int(a.beats[0].tick) == 1, "O the first beat is gi from tick 1: " + str(a.beats))
	var first_spawn_tick := 1 << 30
	for s in a.spawns: first_spawn_tick = mini(first_spawn_tick, int(s.tick))
	check(first_spawn_tick == 361, "O nothing spawns during the first 6 seconds (the look step), the first body at tick %d" % first_spawn_tick)
	check(int(a.alive_at.get(360, -1)) == 0, "O no one is alive at 6.0 s (%s)" % str(a.alive_at.get(360, -1)))
	check(a.steps.size() >= 2 and int(a.steps[1].tick) == int(a.steps[0].tick) + 360, "O look hands over by its time limit (360 ticks)")
	# one: 15..16.5 m away, inside the heading +-15 degrees, 65 % speed, flagged
	var one_spawns: Array = a.spawns.filter(func(s): return s.step == "one")
	check(one_spawns.size() >= 3, "O the step one spawned bodies (%d)" % one_spawns.size())
	var one_heading: Vector2 = a.steps[1].heading if a.steps.size() > 1 else Vector2.ZERO
	var worst_deg := 0.0
	var dist_ok := true
	var speed_ok := true
	var flags_ok := true
	for s in one_spawns:
		var d: float = s.rel.length()
		dist_ok = dist_ok and d >= 15.0 - 0.001 and d <= 16.5 + 0.001
		worst_deg = maxf(worst_deg, absf(rad_to_deg(angle_difference(one_heading.angle(), s.rel.angle()))))
		speed_ok = speed_ok and is_equal_approx(float(s.speed), 2.25 * 0.65)
		flags_ok = flags_ok and bool(s.opening)
	check(dist_ok, "O one spawns 15..16.5 m from the hero")
	check(worst_deg <= 15.0 + 0.01, "O one spawns inside heading +-15 degrees (worst %.2f)" % worst_deg)
	check(is_equal_approx(absf(one_heading.angle()), deg_to_rad(38.2)) or is_equal_approx(one_heading.angle(), deg_to_rad(141.8)), "O the heading of one is one of the two screen sides (%.1f)" % rad_to_deg(one_heading.angle()))
	check(speed_ok, "O one bodies walk at 65 percent of 2.25 m/s")
	check(flags_ok and bool(one_spawns[0].first) and not bool(one_spawns[1].first), "O spawn events carry opening, and first_of_step only on the first body of the step")
	check(int(a.alive_max.get("one", 0)) <= 1 and int(a.alive_max.get("two", 0)) <= 2, "O alive cap of one (%d) and two (%d)" % [int(a.alive_max.get("one", 0)), int(a.alive_max.get("two", 0))])
	# aim: basic spells fire only at 10 m (one) and 11 m (two) in those steps, although the body is visible from 15 m
	check(int(a.cast_far) == 0, "O no cast at a body beyond the step's aim distance (%d)" % int(a.cast_far))
	check(int(a.casts.get("one", 0)) > 0 and int(a.far_ticks.get("one", 0)) > 20, "O in one a body walked in unshot for a while (%d ticks) before the first cast (%d casts)" % [int(a.far_ticks.get("one", 0)), int(a.casts.get("one", 0))])
	# orbs: kills at 10 m are collected by a hero who never moves (orb pull 18 m)
	check(int(a.xp_pickups.get("one", 0)) >= 1, "O the orbs of the kills in one fly to the standing hero (%d pickups, %d kills)" % [int(a.xp_pickups.get("one", 0)), int(a.kills.get("one", 0))])
	check(a.steps.size() >= 3 and int(a.steps[2].tick) - int(a.steps[1].tick) <= 1200, "O one lasts at most its time limit (1200 ticks)")
	# an orb 12 m away: drawn in during the opening (pull 18 m), left alone without it (plain pull is radius + 2 m)
	var orb_with := make_run(opening_doc())
	var orb_without := make_run(document(false))
	for pair in [[orb_with, true], [orb_without, false]]:
		var orb_run: RefCounted = pair[0]
		var orb_pilot = Pilot.new()
		orb_pilot.run = orb_run
		advance(orb_run, orb_pilot, true)
		orb_run.orbs.append({"uid": 9001, "position": Vector2(12, 0), "amount": 1})
		for i in 240: advance(orb_run, orb_pilot, true)
		var left: int = orb_run.orbs.size()
		check((left == 0) == bool(pair[1]), "O an orb 12 m away is %s (orbs left %d)" % ["collected in the opening" if pair[1] else "left alone without the opening", left])
	# steps hand over by kills: one with a single kill ends at that kill
	var kills_doc := opening_doc(func(d): d.rhythm.opening.steps[1].kills = 1)
	var k := scenario_o(kills_doc, 1400)
	var k_ticks: Array = k.kill_ticks.get("one", [])
	check(k.steps.size() >= 3 and k_ticks.size() >= 1 and int(k.steps[2].tick) == int(k_ticks[0]) + 1 and int(k.kills.get("one", 0)) == 1, "O one ends right after its 1st kill when kills is 1 (kill %s, two at %d)" % [str(k_ticks), int(k.steps[2].tick) if k.steps.size() >= 3 else -1])
	# directions: two keeps the side (+-45 degrees), pack comes from the opposite side
	if a.steps.size() >= 4:
		check(a.steps[2].heading.is_equal_approx(a.steps[1].heading), "O two keeps the side of one")
		check(is_equal_approx(absf(angle_difference(a.steps[3].heading.angle(), a.steps[2].heading.angle())), PI), "O pack comes from the opposite side")
		var two_worst := 0.0
		for s in a.spawns.filter(func(x): return x.step == "two"): two_worst = maxf(two_worst, absf(rad_to_deg(angle_difference(a.steps[2].heading.angle(), s.rel.angle()))))
		check(two_worst <= 45.01, "O two spawns inside +-45 degrees (worst %.1f)" % two_worst)
		check(a.steps[3].heading.length() > 0.99 and a.steps[4].heading == Vector2.ZERO if a.steps.size() >= 5 else true, "O around has no single heading")
	var pack_crest: Array = a.crests.filter(func(c): return c.step == "pack")
	check(pack_crest.size() == 1 and int(pack_crest[0].count) == 5 and a.steps.size() >= 4 and int(pack_crest[0].tick) == int(a.steps[3].tick) + 120, "O the pack's crest of 5 comes 120 ticks into the step: " + str(pack_crest))
	var around_crest: Array = a.crests.filter(func(c): return c.step == "around")
	if a.steps.size() >= 5: check(around_crest.size() == 1 and int(around_crest[0].tick) == int(a.steps[4].tick) + 480, "O the crest of around comes 480 ticks into the step: " + str(around_crest))
	var pack_speed_ok := true
	for s in a.spawns.filter(func(x): return x.step == "pack"): pack_speed_ok = pack_speed_ok and is_equal_approx(float(s.speed), 2.25 * 0.85)
	check(pack_speed_ok, "O pack bodies walk at 85 percent")
	check(int(a.level_tick) > 0 and int(a.level_tick) < 3600, "O the first level-up happens inside the opening (tick %d)" % int(a.level_tick))
	# the snapshot carries the opening only while it is on
	var snap: Dictionary = a.run.snapshot()
	check(snap.rhythm.has("opening") and snap.rhythm.opening.has("done") and bool(snap.rhythm.opening.done), "O the snapshot's rhythm block has opening {step, step_tick, step_kills, heading, done}")
	# determinism
	var b := scenario_o(doc, 4000)
	check(a.hash == b.hash and JSON.stringify(a.steps) == JSON.stringify(b.steps) and JSON.stringify(a.spawns) == JSON.stringify(b.spawns), "O the opening twice with the same seed: same snapshot, steps and spawns")
	# the first beat's clock starts when the opening ends (a time limit of 600 for gi, a one-step opening of 120 ticks)
	var short_doc := opening_doc(func(d):
		d.rhythm.opening.steps = [d.rhythm.opening.steps[0]]
		d.rhythm.opening.steps[0].max_ticks = 120
		d.rhythm.beats[0].max_ticks = 600)
	var c := scenario_o(short_doc, 900)
	var seung1_tick := -1
	for beat in c.beats:
		if beat.id == "seung1": seung1_tick = int(beat.tick)
	check(c.ends.size() == 1 and int(c.ends[0].tick) == 121 and seung1_tick == 121 + 600, "O gi's time limit counts from the end of the opening (end %s, seung1 at %d)" % [str(c.ends), seung1_tick])
	# a returning player: first_visit_only steps drop out, look is short
	var r := scenario_o(doc, 1500, false)
	var rids: Array = r.steps.map(func(s): return s.id)
	check(rids == ["look", "pack", "around"], "O a returning player skips the first_visit_only steps: " + str(rids))
	check(r.steps.size() >= 2 and int(r.steps[1].tick) == int(r.steps[0].tick) + 120, "O the returning look lasts returning_max_ticks (120)")
	var returning_spawn := 1 << 30
	for s in r.spawns: returning_spawn = mini(returning_spawn, int(s.tick))
	check(returning_spawn == 121, "O the returning player meets the first body at tick %d (121 expected)" % returning_spawn)
	# the opening is dropped when a later beat takes over (huge progress by kills)
	var drop_doc := opening_doc(func(d): d.seal_kills = [100, 100, 100])
	var drop := make_run(drop_doc)
	var drop_pilot = Pilot.new()
	drop_pilot.run = drop
	for i in 5:
		advance(drop, drop_pilot, true)
	check(drop._op_active, "O the opening is running on tick 5")
	drop.zone_kills = 40
	advance(drop, drop_pilot, true)
	check(not drop._op_active and drop._op_done and drop._beat_index == 1, "O a later beat (seung1 from_bps 3400 of 100 kills) ends the opening: beat %d" % drop._beat_index)

## An opening block that is switched off (or absent) must not change a rhythm-on run, and an enabled opening on a
## rhythm-off run must change nothing at all.
func opening_off_checks() -> void:
	var hashes := {}
	var off_but_opening := shipped()
	off_but_opening.rhythm.opening.enabled = true
	var docs := {
		"block_off": document(false),
		"block_absent": document(false, func(d): d.rhythm.erase("opening")),
		"rhythm_off_opening_on": off_but_opening,
		"rhythm_off_plain": shipped(),
	}
	for name in docs:
		var run := make_run(docs[name], 11, "chapter1.skill.arc")
		var pilot = Pilot.new()
		pilot.run = run
		var opening_events := 0
		for i in 1800:
			run.step(pilot.decide())
			for e in run.events:
				if String(e.type) in ["opening_step", "opening_end"] or bool(e.get("opening", false)): opening_events += 1
			if run.mode == "defeat": break
		hashes[name] = JSON.stringify(run.snapshot()).sha256_text()
		check(opening_events == 0, "O %s emits no opening event (%d)" % [name, opening_events])
		check(not run.snapshot().get("rhythm", {}).has("opening"), "O %s: no opening key in the snapshot" % name)
	# initial_pack 0 in the shipped file is the rhythm's value; with the rhythm off 12 bodies start the run as before
	check(hashes.block_off == hashes.block_absent, "O rhythm on: an opening block that is off equals no block")
	check(hashes.rhythm_off_opening_on == hashes.rhythm_off_plain, "O rhythm off: an enabled opening block changes nothing")

func opening_validator_checks() -> void:
	check(Chapter.new().set_tuning(opening_doc()), "E the shipped document with the opening on is accepted")
	rejects("opening not a dictionary", func(d): d.rhythm.opening = [])
	rejects("opening without enabled", func(d): d.rhythm.opening.erase("enabled"))
	rejects("opening enabled as a number", func(d): d.rhythm.opening.enabled = 1)
	rejects("opening without steps", func(d): d.rhythm.opening.steps = [])
	rejects("opening with 9 steps", func(d):
		var list: Array = []
		for i in 9:
			var s: Dictionary = d.rhythm.opening.steps[1].duplicate(true)
			s.id = "s%d" % i
			list.append(s)
		d.rhythm.opening.steps = list)
	rejects("opening step without ring_m", func(d): d.rhythm.opening.steps[1].erase("ring_m"))
	rejects("opening step with an unknown key", func(d): d.rhythm.opening.steps[1].extra = 1)
	rejects("opening duplicate step id", func(d): d.rhythm.opening.steps[2].id = "one")
	rejects("opening max_ticks 59", func(d): d.rhythm.opening.steps[1].max_ticks = 59)
	rejects("opening max_ticks 3601", func(d): d.rhythm.opening.steps[1].max_ticks = 3601)
	rejects("opening returning_max_ticks 59", func(d): d.rhythm.opening.steps[0].returning_max_ticks = 59)
	rejects("opening kills 201", func(d): d.rhythm.opening.steps[1].kills = 201)
	rejects("opening amount 31", func(d): d.rhythm.opening.steps[1].amount = 31)
	rejects("opening interval_ticks 11", func(d): d.rhythm.opening.steps[1].interval_ticks = 11)
	rejects("opening alive_cap above the first beat's cap", func(d): d.rhythm.opening.steps[4].alive_cap = 19)
	rejects("opening alive_cap 0 with amount 1", func(d): d.rhythm.opening.steps[1].alive_cap = 0)
	rejects("opening ring_m below 2", func(d): d.rhythm.opening.steps[1].ring_m = [1.0, 5.0])
	rejects("opening ring_m above 19", func(d): d.rhythm.opening.steps[1].ring_m = [15.0, 19.5])
	rejects("opening ring_m reversed", func(d): d.rhythm.opening.steps[1].ring_m = [16.0, 15.0])
	rejects("opening ring_m of three", func(d): d.rhythm.opening.steps[1].ring_m = [15.0, 16.0, 17.0])
	rejects("opening speed_bps 2999", func(d): d.rhythm.opening.steps[1].speed_bps = 2999)
	rejects("opening speed_bps 10001", func(d): d.rhythm.opening.steps[1].speed_bps = 10001)
	rejects("opening acquire_m 5.9", func(d): d.rhythm.opening.steps[1].acquire_m = 5.9)
	rejects("opening acquire_m 13.1", func(d): d.rhythm.opening.steps[1].acquire_m = 13.1)
	rejects("opening orb_pull_m 1.9", func(d): d.rhythm.opening.steps[1].orb_pull_m = 1.9)
	rejects("opening orb_pull_m 20.1", func(d): d.rhythm.opening.steps[1].orb_pull_m = 20.1)
	rejects("opening crest count 0", func(d): d.rhythm.opening.steps[3].crest.count = 0)
	rejects("opening crest at_ticks 3601", func(d): d.rhythm.opening.steps[3].crest.at_ticks = 3601)
	rejects("opening mix of zeros", func(d): d.rhythm.opening.steps[1].mix = {"walker": 0, "ranged": 0, "charger": 0})
	rejects("opening first_visit_only as a number", func(d): d.rhythm.opening.steps[1].first_visit_only = 1)
	rejects("opening heading without a direction under 360", func(d): d.rhythm.opening.steps[1].heading = {"arc_deg": 30})
	rejects("opening heading with two direction modes", func(d): d.rhythm.opening.steps[2].heading = {"same_as_previous": true, "opposite_of_previous": true, "arc_deg": 30})
	rejects("opening heading unknown key", func(d): d.rhythm.opening.steps[1].heading.extra = 1)
	rejects("opening first step same_as_previous", func(d): d.rhythm.opening.steps[0].heading = {"same_as_previous": true, "arc_deg": 30})
	rejects("opening heading choice above 180", func(d): d.rhythm.opening.steps[1].heading.choices_deg = [181.0])
	rejects("opening heading arc 0", func(d): d.rhythm.opening.steps[1].heading.arc_deg = 0)

## D22 R0-B: the app's "first-time visitor" for the run opening (profile on: runs of all witches < 2; off: true; the argument wins).
func first_visit_checks() -> void:
	var App = load("res://chapter1/app/chapter_one.gd")
	var none := PackedStringArray()
	var returning := PackedStringArray(["--chapter1-opening=returning"])
	var expect := {0: true, 1: true, 2: false, 5: false}
	for runs in expect:
		check(App.opening_first_visit_for(true, runs, none) == expect[runs], "R0-B profile on, %d runs: first visit %s" % [runs, expect[runs]])
		check(not App.opening_first_visit_for(true, runs, returning), "R0-B profile on, %d runs, opening=returning: false" % runs)
	check(App.opening_first_visit_for(false, 0, none) and App.opening_first_visit_for(false, 9, none), "R0-B profile off: true whatever the count")
	check(not App.opening_first_visit_for(false, 0, returning), "R0-B profile off, opening=returning: false")
	check(TrialDocs.TRIAL_NAMES.has("elites") and TrialDocs.switches(PackedStringArray(["--chapter1-profile-off", "--chapter1-trial=rhythm,elites"])) == ["trial:rhythm", "trial:elites"], "R0-B elites is a known trial name")

# ------------------------------------------------------------------ R1-B: the threat keys (D22 4, D17 4.2 4.3 4.6)

## A rhythm run whose hero stands still, casts nothing and cannot die: only the spawner acts. `mutate` edits the document.
## Beat 0 hands over to seung1 on tick 60. Returns {run, events}.
func threat_run(mutate: Callable, ticks: int, seed_: int = 11, setup: Callable = Callable(), purge: int = 0) -> Dictionary:
	var doc := document(false, func(d):
		d.rhythm.beats[0].max_ticks = 60
		if mutate.is_valid(): mutate.call(d))
	var run := make_run(doc, seed_)
	for id_ in run._skill_ids: run._next_cast[id_] = 1 << 30
	if setup.is_valid(): setup.call(run)
	var events: Array = []
	for i in ticks:
		pump(run, events, purge)
		if run.mode != "playing": break
	return {"run": run, "events": events}

## One tick; every `purge` ticks the field is emptied (the guardian, if one was set, stays) so that the alive cap never binds.
func pump(run: RefCounted, events: Array, purge: int) -> void:
	if purge > 0 and int(run.tick) % purge == 0:
		for id_ in run.enemies.keys():
			if int(id_) != int(run._champion_id): run.enemies.erase(id_)
		run._alive = run.enemies.size()
	run.hero.hp_raw = run.hero.max_hp_raw
	run.step(Vector2.ZERO)
	events.append_array(run.events.duplicate(true))

func of_kind(events: Array, type: String) -> Array:
	return events.filter(func(e): return e.type == type)

## The bodies a wave_crest / wave_squad event just placed: the last `count` ordinary spawns before it.
func placed_by(events: Array, index: int) -> Array:
	var marker: Dictionary = events[index]
	var out: Array = []
	for k in range(index - 1, -1, -1):
		var e: Dictionary = events[k]
		if e.type == "spawn" and not e.elite: out.append(e)
		if out.size() >= int(marker.count): break
	return out

func living_kind(run: RefCounted, kind: String) -> int:
	var n := 0
	for id_ in run.enemies:
		var e: Dictionary = run.enemies[id_]
		if e.hp_raw > 0 and e.kind == kind: n += 1
	return n

func threat_validator_checks() -> void:
	var run = Chapter.new()
	var ok_doc := document(false, func(d):
		d.rhythm.beats[1].wave.crest.mix = {"charger": 30, "walker": 70}
		d.rhythm.beats[1].wave.crest.count_jitter_bps = 1500
		d.rhythm.beats[1].wave.squad = {"count": 4, "ring_m": [9, 12], "at_ticks": 840}
		d.rhythm.beats[1].ranged_cap = 4
		d.rhythm.guardian = {"steady_bps": 4000})
	check(run.set_tuning(ok_doc), "R1B the document with all five keys is accepted " + str(run.errors))
	check(run.set_tuning(document(false, func(d): d.rhythm.guardian = {"steady_bps": 4000, "crest": true})), "R1B guardian with crest true is accepted")
	check(run.set_tuning(document(false, func(d): d.rhythm.beats[3].wave.crest.count = 60)), "R1B crest count 60 is accepted (widened from 40)")
	check(run.set_tuning(document(false, func(d): d.rhythm.beats[3].wave.crest.count = 80)), "GS-R1 wave crest count 80 is accepted (widened from 60)")
	rejects("crest count 81", func(d): d.rhythm.beats[3].wave.crest.count = 81)
	check(run.set_tuning(document(false, func(d): d.rhythm.beats[1].wave.squad = {"count": 12, "ring_m": [9, 12], "at_ticks": 840})), "GS-R1 squad count 12 is accepted (widened from 8)")
	rejects("taste_crest count 61", func(d): d.rhythm.beats[0].taste_crest = {"at_ticks": 120, "count": 61, "arc_deg": 60})
	rejects("crest mix not summing to 100", func(d): d.rhythm.beats[1].wave.crest.mix = {"charger": 30, "walker": 60})
	rejects("crest mix with a stranger kind", func(d): d.rhythm.beats[1].wave.crest.mix = {"charger": 30, "walker": 60, "boss": 10})
	rejects("crest mix empty", func(d): d.rhythm.beats[1].wave.crest.mix = {})
	rejects("crest mix share 101", func(d): d.rhythm.beats[1].wave.crest.mix = {"walker": 101})
	rejects("count_jitter_bps 3001", func(d): d.rhythm.beats[1].wave.crest.count_jitter_bps = 3001)
	rejects("count_jitter_bps -1", func(d): d.rhythm.beats[1].wave.crest.count_jitter_bps = -1)
	rejects("crest with a stranger key", func(d): d.rhythm.beats[1].wave.crest.extra = 1)
	rejects("squad count 13", func(d): d.rhythm.beats[1].wave.squad = {"count": 13, "ring_m": [9, 12], "at_ticks": 840})
	rejects("squad ring_m below 6", func(d): d.rhythm.beats[1].wave.squad = {"count": 4, "ring_m": [5, 12], "at_ticks": 840})
	rejects("squad ring_m above 14", func(d): d.rhythm.beats[1].wave.squad = {"count": 4, "ring_m": [9, 15], "at_ticks": 840})
	rejects("squad ring_m reversed", func(d): d.rhythm.beats[1].wave.squad = {"count": 4, "ring_m": [12, 9], "at_ticks": 840})
	rejects("squad ring_m of three", func(d): d.rhythm.beats[1].wave.squad = {"count": 4, "ring_m": [9, 10, 12], "at_ticks": 840})
	rejects("squad at_ticks inside the lull", func(d): d.rhythm.beats[1].wave.squad = {"count": 4, "ring_m": [9, 12], "at_ticks": 1700})
	rejects("squad at_ticks negative", func(d): d.rhythm.beats[1].wave.squad = {"count": 4, "ring_m": [9, 12], "at_ticks": -1})
	rejects("squad without at_ticks", func(d): d.rhythm.beats[1].wave.squad = {"count": 4, "ring_m": [9, 12]})
	rejects("ranged_cap 41", func(d): d.rhythm.beats[1].ranged_cap = 41)
	rejects("ranged_cap -1", func(d): d.rhythm.beats[1].ranged_cap = -1)
	rejects("guardian steady_bps 10001", func(d): d.rhythm.guardian = {"steady_bps": 10001})
	rejects("guardian without steady_bps", func(d): d.rhythm.guardian = {"crest": true})
	rejects("guardian crest as a number", func(d): d.rhythm.guardian = {"steady_bps": 4000, "crest": 1})
	rejects("guardian with a stranger key", func(d): d.rhythm.guardian = {"steady_bps": 4000, "x": 1})

func threat_checks() -> void:
	threat_validator_checks()
	# 1. crest.mix: the head takes the mix, and its chargers stand in the front half (the ring's near half)
	var ring_min := 7.5
	var ring_max := 10.5
	var mid := ring_min + (ring_max - ring_min) * .5
	var _m1 := func(d):
		d.rhythm.beats[1].alive_cap = 100
		d.rhythm.beats[1].charger_from_ticks = 0
		d.rhythm.beats[1].wave.crest.count = 60
		d.rhythm.beats[1].wave.crest.mix = {"charger": 40, "walker": 60}
	var mixed := threat_run(_m1, 400)
	var crests := of_kind(mixed.events, "wave_crest")
	check(crests.size() >= 1, "R1B mix: a head came")
	if crests.size() >= 1:
		var index: int = mixed.events.find(crests[0])
		var bodies := placed_by(mixed.events, index)
		var chargers := bodies.filter(func(b): return b.kind == "charger")
		var walkers := bodies.filter(func(b): return b.kind == "walker")
		check(bodies.size() == int(crests[0].count) and int(crests[0].count) == 60, "R1B mix: the head has its 60 bodies (%d)" % bodies.size())
		check(chargers.size() + walkers.size() == bodies.size() and chargers.size() > 12 and chargers.size() < 36, "R1B mix: about 40 percent chargers, the rest walkers, no ranged (%d / %d)" % [chargers.size(), walkers.size()])
		var near_ok := chargers.all(func(b): return (b.position - mixed.run.hero.position).length() <= mid + 0.02)
		var far_walker := walkers.any(func(b): return (b.position - mixed.run.hero.position).length() > mid + 0.2)
		check(near_ok and far_walker, "R1B mix: every charger stands within %.2f m (the near half of the ring), walkers fill the whole ring" % mid)
	# a doc without the key puts the beat's own mix (ranged and chargers by the beat's shares) and no half-ring rule
	var _m2 := func(d):
		d.rhythm.beats[1].alive_cap = 100
		d.rhythm.beats[1].charger_from_ticks = 0
		d.rhythm.beats[1].wave.crest.count = 60
	var plain := threat_run(_m2, 400)
	var plain_crest: Dictionary = of_kind(plain.events, "wave_crest")[0]
	var plain_bodies := placed_by(plain.events, plain.events.find(plain_crest))
	check(plain_bodies.any(func(b): return b.kind == "ranged") or plain_bodies.any(func(b): return b.kind == "charger"), "R1B mix: without the key the head follows the beat's mix")
	# 2. ranged_cap: living ranged bodies stay at the cap, the surplus share is walkers; a cap above the need changes nothing
	var _m3 := func(d):
		d.rhythm.beats[1].alive_cap = 100
		d.rhythm.beats[1].ranged_from_ticks = 0
		d.rhythm.beats[1].mix = {"walker": 10, "ranged": 90, "charger": 0}
		d.rhythm.beats[1].ranged_cap = 3
	var capped := threat_run(_m3, 900)
	var _m4 := func(d):
		d.rhythm.beats[1].alive_cap = 100
		d.rhythm.beats[1].ranged_from_ticks = 0
		d.rhythm.beats[1].mix = {"walker": 10, "ranged": 90, "charger": 0}
	var uncapped := threat_run(_m4, 900)
	var ranged_alive := living_kind(capped.run, "ranged")
	check(ranged_alive == 3, "R1B ranged_cap 3: exactly 3 living ranged bodies after 900 ticks (%d)" % ranged_alive)
	check(living_kind(uncapped.run, "ranged") > 8, "R1B without ranged_cap the same doc fills with ranged bodies (%d)" % living_kind(uncapped.run, "ranged"))
	check(living_kind(capped.run, "walker") > living_kind(uncapped.run, "walker"), "R1B ranged_cap: the surplus ranged share turned into walkers (%d vs %d)" % [living_kind(capped.run, "walker"), living_kind(uncapped.run, "walker")])
	var worst := 0
	var _m5 := func(d):
		d.rhythm.beats[1].alive_cap = 100
		d.rhythm.beats[1].ranged_from_ticks = 0
		d.rhythm.beats[1].mix = {"walker": 10, "ranged": 90, "charger": 0}
		d.rhythm.beats[1].ranged_cap = 3
	var probe := threat_run(_m5, 1)
	for i in 900:
		probe.run.hero.hp_raw = probe.run.hero.max_hp_raw
		probe.run.step(Vector2.ZERO)
		worst = maxi(worst, living_kind(probe.run, "ranged"))
	check(worst <= 3, "R1B ranged_cap 3: never more than 3 living ranged at any tick (%d)" % worst)
	var _m6 := func(d):
		d.rhythm.beats[1].ranged_cap = 40
	var roomy := threat_run(_m6, 1500)
	var none := threat_run(Callable(), 1500)
	check(JSON.stringify(roomy.run.snapshot()).sha256_text() == JSON.stringify(none.run.snapshot()).sha256_text(), "R1B ranged_cap 40 that never binds leaves the run exactly as it was (same snapshot)")
	# 3. squad: once per wave, away from the head, inside the ring, ranged; the wave_squad event carries {beat, direction, count}
	var squad_doc := func(d):
		d.rhythm.beats[1].alive_cap = 100
		d.rhythm.beats[1].wave.squad = {"count": 4, "ring_m": [9, 12], "at_ticks": 840}
	var squad := threat_run(squad_doc, 60 + 2400 * 2 + 200, 11, Callable(), 300)
	var squads := of_kind(squad.events, "wave_squad")
	var heads := of_kind(squad.events, "wave_crest")
	check(squads.size() == 2 and heads.size() >= 2, "R1B squad: one squad per wave period (%d squads, %d heads)" % [squads.size(), heads.size()])
	check(squads.all(func(e): return e.has_all(["beat", "direction", "count"]) and String(e.beat) == "seung1" and e.direction is Vector2 and int(e.count) == 4), "R1B squad: wave_squad carries {beat, direction, count}")
	for k in mini(squads.size(), 2):
		var s_event: Dictionary = squads[k]
		var members := placed_by(squad.events, squad.events.find(s_event))
		check(members.size() == 4 and members.all(func(b): return b.kind == "ranged"), "R1B squad %d: four ranged bodies" % k)
		var distances := members.map(func(b): return (b.position - squad.run.hero.position).length())
		check(distances.all(func(dist): return dist >= 8.99 and dist <= 12.01), "R1B squad %d: all inside ring_m 9..12 (%s)" % [k, str(distances.map(func(x): return snappedf(x, 0.1)))])
		var spread := 0.0
		for a in members:
			for b in members: spread = maxf(spread, (a.position - b.position).length())
		check(spread < 6.5, "R1B squad %d: they stand together (widest gap %.1f m)" % [k, spread])
		var head_event: Dictionary = {}
		for h in heads:
			if int(h.tick) <= int(s_event.tick): head_event = h
		var turn: float = absf(angle_difference(s_event.direction.angle(), head_event.direction.angle()))
		check(turn >= deg_to_rad(90.0) - 0.001, "R1B squad %d: %.0f degrees from the head's heading (90..180)" % [k, rad_to_deg(turn)])
		var toward: float = (members[0].position - squad.run.hero.position).angle()
		check(absf(angle_difference(toward, s_event.direction.angle())) < deg_to_rad(25.0), "R1B squad %d: the bodies stand on the event's direction" % k)
	var first_beat: int = int(of_kind(squad.events, "beat_started").filter(func(e): return e.id == "seung1")[0].tick)
	check(squads.size() > 0 and int(squads[0].tick) - first_beat >= 840 and int(squads[0].tick) - first_beat < 900, "R1B squad: it comes at_ticks (840) into the period (%d)" % (int(squads[0].tick) - first_beat if squads.size() > 0 else -1))
	var squad_again := threat_run(squad_doc, 60 + 2400 * 2 + 200, 11, Callable(), 300)
	check(JSON.stringify(squad_again.run.snapshot()) == JSON.stringify(squad.run.snapshot()) and JSON.stringify(of_kind(squad_again.events, "wave_squad")) == JSON.stringify(squads), "R1B squad: the same seed gives the same squads and the same snapshot")
	check(squad.run.snapshot().rhythm.has("threat") and not none.run.snapshot().rhythm.has("threat"), "R1B squad: the snapshot carries the threat state only when a key is on")
	check(of_kind(none.events, "wave_squad").is_empty(), "R1B squad: no wave_squad without the key")
	# the squad respects the alive cap
	var _m7 := func(d):
		d.rhythm.beats[1].alive_cap = 14
		d.rhythm.beats[1].wave.squad = {"count": 8, "ring_m": [9, 12], "at_ticks": 840}
	var tight := threat_run(_m7, 60 + 2400 + 300)
	check(int(tight.run.alive_count()) <= 14, "R1B squad: the alive cap holds (%d alive, cap 14)" % tight.run.alive_count())
	# 4. guardian: while one lives the inflow runs at steady_bps and, without crest, no head or squad comes
	var make_guard := func(run):
		run._spawn("elite", Vector2(14, 0))
		run._champion_id = run._enemy_sequence
		run.enemies[run._champion_id].title_key = "enemy.champion.0.name"
		run.enemies[run._champion_id].definition.speed = 0.0
	var wide := func(d):
		d.rhythm.beats[1].alive_cap = 100
		d.rhythm.beats[1].wave.squad = {"count": 4, "ring_m": [9, 12], "at_ticks": 840}
	var guard_plain := threat_run(wide, 1300, 11, make_guard, 300)
	var _m8 := func(d):
		wide.call(d)
		d.rhythm.guardian = {"steady_bps": 4000}
	var guard_slow := threat_run(_m8, 1300, 11, make_guard, 300)
	var _m9 := func(d):
		wide.call(d)
		d.rhythm.guardian = {"steady_bps": 4000, "crest": true}
	var guard_heads := threat_run(_m9, 1300, 11, make_guard, 300)
	var count_spawns := func(events: Array): return of_kind(events, "spawn").filter(func(e): return not e.elite).size()
	var inflow_plain: int = count_spawns.call(guard_plain.events) - of_kind(guard_plain.events, "wave_crest").map(func(e): return int(e.count)).reduce(func(a, b): return a + b, 0) - of_kind(guard_plain.events, "wave_squad").map(func(e): return int(e.count)).reduce(func(a, b): return a + b, 0)
	var inflow_slow: int = count_spawns.call(guard_slow.events)
	check(of_kind(guard_plain.events, "wave_crest").size() >= 1 and of_kind(guard_plain.events, "wave_squad").size() >= 1, "R1B guardian: without the key a guardian changes nothing (heads and squads come)")
	check(of_kind(guard_slow.events, "wave_crest").is_empty() and of_kind(guard_slow.events, "wave_squad").is_empty(), "R1B guardian: steady_bps without crest: no head and no squad while the guardian lives")
	check(inflow_slow > 0 and inflow_slow * 10 <= inflow_plain * 5, "R1B guardian: the plain inflow runs at 40 percent (%d against %d)" % [inflow_slow, inflow_plain])
	check(of_kind(guard_heads.events, "wave_crest").size() >= 1 and of_kind(guard_heads.events, "wave_squad").size() >= 1, "R1B guardian: with crest true the heads and squads go on")
	var _m10 := func(d):
		wide.call(d)
		d.rhythm.guardian = {"steady_bps": 4000}
	var idle_guard := threat_run(_m10, 1300)
	var idle_none := threat_run(wide, 1300)
	check(JSON.stringify(idle_guard.run.snapshot()) == JSON.stringify(idle_none.run.snapshot()), "R1B guardian: with no guardian alive the key changes nothing (same snapshot)")
	var _m11 := func(d):
		wide.call(d)
		d.rhythm.guardian = {"steady_bps": 4000}
	var gone := threat_run(_m11, 700, 11, make_guard, 300)
	gone.run.enemies[gone.run._champion_id].hp_raw = 0
	var after := 0
	var tail: Array = []
	for i in 2400: pump(gone.run, tail, 300)
	after = of_kind(tail, "wave_crest").size()
	check(after >= 1, "R1B guardian: once the guardian is dead the heads come again")
	# 5. count_jitter_bps: rolled once per beat from the spawn stream, same seed same roll, other seeds other rolls
	var jit := func(d):
		d.rhythm.beats[1].alive_cap = 100
		d.rhythm.beats[1].wave.crest.count = 20
		d.rhythm.beats[1].wave.crest.count_jitter_bps = 1500
	var rolled := threat_run(jit, 60 + 2400 * 2 + 100, 11, Callable(), 300)
	var sizes := of_kind(rolled.events, "wave_crest").map(func(e): return int(e.count))
	check(sizes.size() >= 2 and sizes.all(func(n): return n == sizes[0]) and sizes[0] >= 17 and sizes[0] <= 23, "R1B jitter: every head of the beat has the one rolled size, within 20 +- 15 percent (%s)" % str(sizes))
	var rolled_again := threat_run(jit, 60 + 2400 * 2 + 100, 11, Callable(), 300)
	check(JSON.stringify(of_kind(rolled_again.events, "wave_crest")) == JSON.stringify(of_kind(rolled.events, "wave_crest")) and JSON.stringify(rolled_again.run.snapshot()) == JSON.stringify(rolled.run.snapshot()), "R1B jitter: the same seed gives the same heads and snapshot")
	var seen := {}
	for seed_ in [11, 12, 13, 14, 15, 16, 17, 18]:
		var r := threat_run(jit, 200, seed_)
		var h := of_kind(r.events, "wave_crest")
		if h.size() > 0: seen[int(h[0].count)] = true
	check(seen.size() >= 3, "R1B jitter: other seeds roll other sizes (%s)" % str(seen.keys()))
	var _m12 := func(d):
		d.rhythm.beats[1].alive_cap = 100
		d.rhythm.beats[1].wave.crest.count = 20
	var steady := threat_run(_m12, 200)
	check(int(of_kind(steady.events, "wave_crest")[0].count) == 20, "R1B jitter: without the key the head is exactly its count (20)")
	var _m13 := func(d):
		d.rhythm.beats[1].alive_cap = 100
		d.rhythm.beats[1].wave.crest.count = 20
		d.rhythm.beats[1].wave.crest.count_jitter_bps = 0
	var zero := threat_run(_m13, 1500)
	var _m14 := func(d):
		d.rhythm.beats[1].alive_cap = 100
		d.rhythm.beats[1].wave.crest.count = 20
	var base := threat_run(_m14, 1500)
	check(JSON.stringify(zero.run.snapshot()) == JSON.stringify(base.run.snapshot()), "R1B jitter: 0 draws nothing (same snapshot as no key)")
	# the keys do not touch a run with the rhythm off
	var off_doc := shipped()
	off_doc.rhythm.beats[1].wave.squad = {"count": 4, "ring_m": [9, 12], "at_ticks": 840}
	off_doc.rhythm.guardian = {"steady_bps": 4000}
	var off_run := make_run(off_doc)
	var off_ref := make_run(shipped())
	for i in 600:
		off_run.step(Vector2.ZERO)
		off_ref.step(Vector2.ZERO)
	check(JSON.stringify(off_run.snapshot()) == JSON.stringify(off_ref.snapshot()) and not off_run.snapshot().has("rhythm"), "R1B the keys in a document with the rhythm off change nothing")

func execute() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/_local/appdata/"):
		print("CHAPTER1_RHYTHM_TEST_RESULT ", JSON.stringify({"checks": 0, "failures": ["user data dir is not isolated: refusing to run"]}))
		quit(1)
		return
	validator_checks()
	hp_factor_check()
	zone_limit_check()
	var a1 := scenario_a(true)
	var a2 := scenario_a(false)
	check(a1.hash == a2.hash and JSON.stringify(a1.beats) == JSON.stringify(a2.beats) and JSON.stringify(a1.crests) == JSON.stringify(a2.crests), "C scenario A twice with the same seed: same snapshot, beats and crests")
	var b1 := scenario_b(true)
	var b2 := scenario_b(false)
	check(b1.hash == b2.hash and int(b1.tick) == int(b2.tick) and JSON.stringify(b1.events) == JSON.stringify(b2.events), "C scenario B twice with the same seed: same snapshot (tick %d) and same event stream" % int(b1.tick))
	off_runs()
	opening_validator_checks()
	opening_checks()
	opening_off_checks()
	first_visit_checks()
	threat_checks()
	print("CHAPTER1_RHYTHM_TEST_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
