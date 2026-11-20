extends SceneTree
## D19 C1 check: the growth-pace keys of the chapter core (docs/specs/D19-growth-pace-and-combat-thrill-20261120.ko.md 6.2).
## Every key is off in the shipped data and is switched on IN MEMORY here; no data file is edited. Parts:
##   A  the validator: accepts the first values, refuses values outside the 8-table ranges and unknown keys
##   B  C1-a level table (length = level cap, the default stays 12) and C1-b seal kills
##   C  C1-c the guardian's level (cause "guardian", never the last level, boss grace unchanged)
##   D  C1-d beat / trial orb multipliers
##   E  C1-e the sweep bonus: window, minimum, no double count, who counts, descent gauge share
##   F  C1-f the pace: rises after soft_after_ticks, capped, back to 1x at a level-up, no key when off
##   G  off equals today: the same snapshot with the keys absent, neutral, or the rhythm off; no new snapshot key when off
##   H  determinism (a pilot run with everything on, twice) and the trial switch name "pace"
## Marker: CHAPTER1_GROWTH_PACE_RESULT. Writes nothing.
const Chapter = preload("res://chapter1/core/chapter_core.gd")
const Pilot = preload("res://chapter1/core/chapter_pilot.gd")
const TrialDocs = preload("res://chapter1/tests/support/trial_docs.gd")
const TrialPace = preload("res://chapter1/app/trial_pace.gd")
const TUNING := "res://chapter1/data/combat_tuning.json"
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

## The shipped document with the rhythm (and its opening) on, then `mutate` applied.
func document(mutate: Callable = Callable(), rhythm_on := true) -> Dictionary:
	var doc := shipped()
	doc.rhythm.enabled = rhythm_on
	doc.rhythm.opening.enabled = rhythm_on
	if mutate.is_valid(): mutate.call(doc)
	return doc

func make_run(doc: Dictionary, seed_: int = 11, primary: String = "chapter1.skill.ember", with_descent := false) -> RefCounted:
	var run = Chapter.new()
	if not run.set_tuning(doc):
		check(false, "document accepted: " + str(run.errors))
		return null
	if with_descent and not TrialDocs.enable_descent_problem(run).is_empty():
		check(false, "descent enabled")
		return null
	if not run.start(seed_, primary):
		check(false, "run starts: " + str(run.errors))
		return null
	run.first_boss_kill = true
	return run

func with_burst(window := 30, min_kills := 10, xp_bps := 5000, descent_bps := 10000) -> Callable:
	return func(d): d.rhythm.kill_burst = {"window_ticks": window, "min_kills": min_kills, "xp_bonus_bps": xp_bps, "descent_bonus_bps": descent_bps}

func hash_of(run: RefCounted) -> String:
	return JSON.stringify(run.snapshot()).sha256_text()

func accepted(doc: Dictionary) -> bool:
	var loader = Chapter.new()
	return loader.set_tuning(doc)

func rejects(name: String, mutate: Callable) -> void:
	check(not accepted(document(mutate)), "validator refuses " + name)

func accepts(name: String, mutate: Callable) -> void:
	var doc := document(mutate)
	var loader = Chapter.new()
	check(loader.set_tuning(doc), "validator accepts " + name + " " + str(loader.errors))

# ------------------------------------------------------------------ A

func validator_checks() -> void:
	var table: Array = TrialPace.FIRST_VALUES.xp_thresholds
	accepts("the shipped document", func(d): pass)
	accepts("the first values", func(d): TrialPace.apply(d))
	accepts("a 12 entry table", func(d): d.rhythm.xp_thresholds = [0, 10, 23, 71, 186, 444, 740, 1167, 1772, 2552, 3898, 12000])
	accepts("a 20 entry table", func(d): d.rhythm.xp_thresholds = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19])
	rejects("an 11 entry table", func(d): d.rhythm.xp_thresholds = table.slice(0, 11))
	rejects("a 21 entry table", func(d): d.rhythm.xp_thresholds = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20])
	rejects("a table that does not rise", func(d): d.rhythm.xp_thresholds = [0, 27, 50, 72, 72, 263, 442, 600, 820, 1070, 1330, 1580])
	rejects("a table not starting at 0", func(d): d.rhythm.xp_thresholds = [1, 27, 50, 72, 114, 263, 442, 600, 820, 1070, 1330, 1580])
	rejects("a table with a float", func(d): d.rhythm.xp_thresholds = [0, 27, 50, 72, 114, 263, 442, 600, 820, 1070, 1330, 1580.5])
	rejects("seal_kills of 2 entries", func(d): d.rhythm.seal_kills = [365, 975])
	rejects("seal_kills 0", func(d): d.rhythm.seal_kills = [0, 975, 540])
	rejects("seal_kills 5001", func(d): d.rhythm.seal_kills = [365, 5001, 540])
	accepts("seal_kills 1 and 5000", func(d): d.rhythm.seal_kills = [1, 5000, 540])
	rejects("guardian_grace as text", func(d): d.rhythm.guardian_grace = "yes")
	rejects("a beat xp_bps of 999", func(d): d.rhythm.beats[0].xp_bps = 999)
	rejects("a beat xp_bps of 50001", func(d): d.rhythm.beats[1].xp_bps = 50001)
	accepts("beat xp_bps 1000 and 50000", func(d):
		d.rhythm.beats[0].xp_bps = 1000
		d.rhythm.beats[1].xp_bps = 50000)
	rejects("a trial xp_bps of 999", func(d): d.rhythm.trial.xp_bps = 999)
	accepts("a trial xp_bps of 12000", func(d): d.rhythm.trial.xp_bps = 12000)
	rejects("kill_burst window 5", with_burst(5))
	rejects("kill_burst window 121", with_burst(121))
	rejects("kill_burst min_kills 2", with_burst(30, 2))
	rejects("kill_burst min_kills 41", with_burst(30, 41))
	rejects("kill_burst xp bonus 20001", with_burst(30, 10, 20001))
	rejects("kill_burst descent bonus 20001", with_burst(30, 10, 5000, 20001))
	rejects("kill_burst negative bonus", with_burst(30, 10, -1))
	rejects("kill_burst with an unknown key", func(d): d.rhythm.kill_burst = {"window_ticks": 30, "min_kills": 10, "xp_bonus_bps": 5000, "descent_bonus_bps": 10000, "x": 1})
	rejects("kill_burst missing a key", func(d): d.rhythm.kill_burst = {"window_ticks": 30, "min_kills": 10, "xp_bonus_bps": 5000})
	accepts("kill_burst edge values", with_burst(6, 3, 0, 20000))
	accepts("kill_burst upper edge values", with_burst(120, 40, 20000, 0))
	accepts("a pace", func(d): d.grace.pace = {"soft_after_ticks": 2100, "ramp_bps_per_s": 800, "max_bps": 25000})
	rejects("pace soft 59", func(d): d.grace.pace = {"soft_after_ticks": 59, "ramp_bps_per_s": 800, "max_bps": 25000})
	rejects("pace max below 1x", func(d): d.grace.pace = {"soft_after_ticks": 2100, "ramp_bps_per_s": 800, "max_bps": 9999})
	rejects("pace max 50001", func(d): d.grace.pace = {"soft_after_ticks": 2100, "ramp_bps_per_s": 800, "max_bps": 50001})
	rejects("pace ramp 10001", func(d): d.grace.pace = {"soft_after_ticks": 2100, "ramp_bps_per_s": 10001, "max_bps": 25000})
	rejects("pace with an unknown key", func(d): d.grace.pace = {"soft_after_ticks": 2100, "ramp_bps_per_s": 800, "max_bps": 25000, "x": 1})
	rejects("pace missing a key", func(d): d.grace.pace = {"soft_after_ticks": 2100, "ramp_bps_per_s": 800})
	var plain := shipped()
	check(not plain.rhythm.has("xp_thresholds") and not plain.rhythm.has("seal_kills") and not plain.rhythm.has("guardian_grace") and not plain.rhythm.has("kill_burst") and not plain.grace.has("pace"), "A the data file carries none of the C1 keys")
	var loose := false
	for beat in plain.rhythm.beats:
		if beat.has("xp_bps"): loose = true
	check(not loose and not plain.rhythm.trial.has("xp_bps"), "A the data file has no xp_bps")

# ------------------------------------------------------------------ B

func level_table_checks() -> void:
	var table: Array = TrialPace.FIRST_VALUES.xp_thresholds
	var base := make_run(document(), 11)
	check(base != null and base.growth.xp_thresholds().size() == 12 and base.growth.is_final_level(12) and not base.growth.is_final_level(11), "B without the key a rhythm run has the old 12 level table")
	var off := make_run(document(func(d): d.rhythm.xp_thresholds = table, false), 11)
	check(off != null and off.growth.xp_thresholds().size() == 12, "B the table is ignored while the rhythm is off")
	var run := make_run(document(func(d): d.rhythm.xp_thresholds = table), 11)
	check(run != null and run.growth.xp_thresholds() == table, "B the rhythm run takes its own table")
	check(run.growth.is_final_level(16) and not run.growth.is_final_level(15) and not run.growth.is_final_level(12), "B the cap is the table's length: 16 is the last level, 12 is not")
	check(run.growth.award_xp(int(table[14])) and run.growth.current_level() == 15, "B xp at the 15th entry gives level 15")
	check(run.growth.award_xp(1000000) and run.growth.current_level() == 16, "B a huge gain stops at level 16")
	check(run.growth.snapshot().level == 16 and run.growth.snapshot().pending_levels.size() == 15, "B level 2..16 are pending offers (15 of them)")
	var short := make_run(document(func(d): d.rhythm.xp_thresholds = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95]), 11)
	check(short != null and short.growth.is_final_level(20) and not short.growth.is_final_level(19), "B a 20 entry table caps at 20")
	var loader = Chapter.new()
	check(not loader.growth.set_thresholds(table), "B set_thresholds refuses a run that was never configured")
	check(base.growth.set_thresholds(table) == false and base.growth.xp_thresholds().size() == 12, "B set_thresholds refuses a run that has started its life later (xp taken)") if base.growth.award_xp(1) else check(false, "B award")
	# C1-b: seal kills
	var seal := make_run(document(func(d): d.rhythm.seal_kills = [3, 5, 7]), 11)
	seal.hero.position = Chapter.ZONES[0]
	seal._zone_entered = true
	check(seal.objective().total == 3 and seal.objective().kind == "seal_kills", "B objective() shows rhythm.seal_kills")
	seal.zone_kills = 2
	seal._spawn_wave()
	check(seal._champion_id == -1, "B two kills of 3: no guardian yet")
	seal.zone_kills = 3
	seal._spawn_wave()
	check(seal._champion_id > 0 and seal.seals[0].champion_spawned, "B the guardian comes at rhythm.seal_kills[0]")
	check(seal._zone_bps() == 10000, "B the zone is at 100 percent once the guardian is called")
	var plain := make_run(document(), 11)
	check(plain.objective().total == int(plain.tuning.seal_kills[0]), "B without the key objective() shows tuning.seal_kills")
	var off_seal := make_run(document(func(d): d.rhythm.seal_kills = [3, 5, 7], false), 11)
	check(off_seal.objective().total == int(off_seal.tuning.seal_kills[0]), "B rhythm.seal_kills is ignored while the rhythm is off")
	var zone_two := make_run(document(func(d): d.rhythm.seal_kills = [3, 5, 7]), 11)
	zone_two.zone = 2
	check(zone_two.objective().total == 7, "B zone 2 reads the third figure")

# ------------------------------------------------------------------ C

## A run whose guardian of `zone_` stands in the field, then fell. Returns the events of the fall.
func guardian_fall(run: RefCounted, zone_: int) -> Array:
	run.zone = zone_
	run.hero.position = Chapter.ZONES[zone_]
	run._zone_entered = true
	run.zone_kills = run._seal_total(zone_)
	run._spawn_wave()
	run.events.clear()
	var e: Dictionary = run.enemies[run._champion_id]
	run._on_elite_defeated(e)
	return run.events.duplicate(true)

func grace_events(events: Array) -> Array:
	return events.filter(func(e): return e.type == "seal_grace")

func guardian_checks() -> void:
	var table: Array = TrialPace.FIRST_VALUES.xp_thresholds
	var on := func(d):
		d.rhythm.xp_thresholds = table
		d.rhythm.guardian_grace = true
	var run := make_run(document(on), 11)
	check(run.growth.current_level() == 1 and int(run.growth.snapshot().xp) == 0, "C a fresh run is at level 1 with no xp")
	var events := guardian_fall(run, 0)
	var graces := grace_events(events)
	check(graces.size() == 1 and graces[0].get("cause", "") == "guardian" and int(graces[0].amount) == int(table[1]) and int(graces[0].level) == 2, "C the first guardian fills level 2 (event seal_grace {level 2, amount %d, cause guardian}): %s" % [int(table[1]), str(graces)])
	check(run.growth.current_level() == 2 and int(run.growth.snapshot().xp) == int(table[1]) and run.growth.snapshot().pending_levels == [2], "C level 2 is pending as an offer")
	# A second guardian with orbs still on the ground: the orbs flow in first, the grace fills only what is left of the NEXT level.
	run.growth.award_xp(10)
	var level_before: int = run.growth.current_level()
	var xp_before: int = int(run.growth.snapshot().xp)
	var second := guardian_fall(run, 1)
	var second_graces := grace_events(second)
	check(second_graces.size() == 1 and int(run.growth.snapshot().xp) == int(table[level_before]) and run.growth.current_level() == level_before + 1, "C the second guardian lifts the run exactly one more level (%d -> %d, xp %d -> %d)" % [level_before, run.growth.current_level(), xp_before, int(run.growth.snapshot().xp)])
	# Never into the last level: from level 15 a guardian gives nothing.
	var high := make_run(document(on), 12)
	high.growth.award_xp(int(table[14]))
	var high_events := guardian_fall(high, 0)
	check(high.growth.current_level() == 15 and grace_events(high_events).is_empty(), "C at level 15 of 16 a guardian does not give the last level")
	# Off: false, absent, and a rhythm that is off.
	var no := make_run(document(func(d):
		d.rhythm.xp_thresholds = table
		d.rhythm.guardian_grace = false), 11)
	check(grace_events(guardian_fall(no, 0)).is_empty() and no.growth.current_level() == 1, "C guardian_grace false: no grace")
	var absent := make_run(document(), 11)
	check(grace_events(guardian_fall(absent, 0)).is_empty() and absent.growth.current_level() == 1, "C guardian_grace absent: no grace")
	var off := make_run(document(func(d): d.rhythm.guardian_grace = true, false), 11)
	check(grace_events(guardian_fall(off, 0)).is_empty() and off.growth.current_level() == 1, "C the rhythm off: guardian_grace is ignored")
	# The boss: the last grace stays as it was (no cause key) and now fills the table's last entry.
	var boss := make_run(document(on), 11)
	boss.zone = 2
	boss.hero.position = Chapter.ZONES[2]
	boss._zone_entered = true
	boss.zone_kills = boss._seal_total(2)
	boss.events.clear()
	boss._spawn_wave()
	var boss_graces := grace_events(boss.events)
	check(boss_graces.size() == 1 and not boss_graces[0].has("cause") and boss.growth.current_level() == 16 and boss.growth.is_final_level(16), "C the boss spawn still gives the last level (16) and the old event: %s" % str(boss_graces))
	var boss_old := make_run(document(), 11)
	boss_old.zone = 2
	boss_old.hero.position = Chapter.ZONES[2]
	boss_old._zone_entered = true
	boss_old.zone_kills = boss_old._seal_total(2)
	boss_old._spawn_wave()
	check(boss_old.growth.current_level() == 12, "C without the table the boss spawn still gives level 12")

# ------------------------------------------------------------------ D

func orb_value(run: RefCounted, amount: int) -> int:
	run.orbs.clear()
	run._drop_orb(Vector2(3, 3), amount)
	return int(run.orbs[run.orbs.size() - 1].amount)

func multiplier_checks() -> void:
	var run := make_run(document(func(d):
		d.rhythm.beats[0].xp_bps = 20000
		d.rhythm.beats[1].xp_bps = 1000
		d.rhythm.trial.xp_bps = 30000), 11)
	run.step(Vector2.ZERO)
	check(run._beat_index == 0, "D the first beat is running")
	check(orb_value(run, 3) == 6 and orb_value(run, 1) == 2, "D beat xp_bps 20000 doubles an orb")
	run._beat_index = 1
	check(orb_value(run, 1) == 1 and orb_value(run, 3) == 1 and orb_value(run, 12) == 1, "D xp_bps 1000 rounds down but never below 1")
	run._beat_index = 2
	check(orb_value(run, 3) == 3, "D a beat without xp_bps pays the plain value")
	run._beat_index = 0
	run._trial_phase = "hold"
	check(orb_value(run, 3) == 9, "D the trial's own xp_bps")
	run._trial_phase = ""
	run.zone = 2
	run._champion_id = 5
	check(orb_value(run, 3) == 3, "D the boss's phase pays the plain value")
	var odd := make_run(document(func(d): d.rhythm.beats[0].xp_bps = 15000), 11)
	odd.step(Vector2.ZERO)
	check(orb_value(odd, 3) == 4 and orb_value(odd, 1) == 1, "D 1.5x of 3 is 4, of 1 is 1 (integer, rounded down)")
	var off := make_run(document(func(d): d.rhythm.beats[0].xp_bps = 20000, false), 11)
	off.step(Vector2.ZERO)
	check(orb_value(off, 3) == 3, "D the rhythm off: no multiplier")

# ------------------------------------------------------------------ E

## A walker that exists in the core, killed the way the core does it up to the event: the death event is what the bonus listens to.
func kill_one(run: RefCounted, role := "normal", skill := "chapter1.skill.ember", kind := "walker") -> void:
	var made: bool = run._spawn(kind, run.hero.position + Vector2(4, 0))
	check(made, "E a body can be placed")
	var id_: int = run._enemy_sequence
	var e: Dictionary = run.enemies[id_]
	run._emit("death", e.position, {"target_id": id_, "kind": e.kind, "elite": false, "skill_id": skill, "role": role})

func bursts(run: RefCounted) -> Array:
	return run.events.filter(func(e): return e.type == "kill_burst")

func burst_checks() -> void:
	var run := make_run(document(with_burst()), 11)
	run.step(Vector2.ZERO)
	run.events.clear()
	run.orbs.clear()
	for i in 9: kill_one(run)
	check(bursts(run).is_empty() and run.orbs.is_empty(), "E nine kills: no burst, no orb")
	kill_one(run)
	var list := bursts(run)
	check(list.size() == 1 and int(list[0].count) == 10 and list[0].has("position"), "E the tenth kill inside the window bursts (count 10, position)")
	check(run.orbs.size() == 1 and int(run.orbs[0].amount) == 5, "E the bonus is one orb of half the ten kills' experience (5): %s" % str(run.orbs))
	check(int(run.metrics.kill_burst.bursts) == 1 and int(run.metrics.kill_burst.kills) == 10 and int(run.metrics.kill_burst.xp) == 5, "E metrics.kill_burst counts it")
	# No double count: five more kills are not a burst, ten more kills are one (the first ten are spent).
	run.events.clear()
	for i in 5: kill_one(run)
	check(bursts(run).is_empty(), "E the ten kills are spent: five more do not burst again")
	for i in 5: kill_one(run)
	check(bursts(run).size() == 1 and int(bursts(run)[0].count) == 10, "E ten new kills burst once more")
	# The window: five kills, then 30 ticks pass, then five more: the first five are out of the window.
	var timed := make_run(document(with_burst()), 11)
	timed.step(Vector2.ZERO)
	timed.events.clear()
	for i in 5: kill_one(timed)
	timed.tick += 30
	for i in 5: kill_one(timed)
	check(bursts(timed).is_empty(), "E five kills and five more 30 ticks later are not a burst of 10 (window 30)")
	for i in 5: kill_one(timed)
	check(bursts(timed).size() == 1, "E five more inside the window of the last five make ten")
	var edge := make_run(document(with_burst()), 11)
	edge.step(Vector2.ZERO)
	edge.events.clear()
	for i in 5: kill_one(edge)
	edge.tick += 29
	for i in 5: kill_one(edge)
	check(bursts(edge).size() == 1, "E the last tick of the window still counts (29 ticks apart)")
	# Who counts.
	var who := make_run(document(with_burst(30, 3)), 11)
	who.step(Vector2.ZERO)
	who.events.clear()
	for i in 4: kill_one(who, "elite")
	for i in 4: kill_one(who, "champion")
	for i in 4: kill_one(who, "boss")
	for i in 4: kill_one(who, "normal", "descent.ember")
	check(bursts(who).is_empty(), "E strong bodies and the descent's own sweep do not count")
	for i in 3: kill_one(who)
	check(bursts(who).size() == 1 and int(bursts(who)[0].count) == 3, "E three ordinary kills of the witch's own damage burst at min_kills 3")
	# Orb value follows the beat's multiplier; charger and ranged pay their own value.
	var rich := make_run(document(func(d):
		d.rhythm.kill_burst = {"window_ticks": 30, "min_kills": 3, "xp_bonus_bps": 10000, "descent_bonus_bps": 0}
		d.rhythm.beats[0].xp_bps = 20000), 11)
	rich.step(Vector2.ZERO)
	rich.events.clear()
	rich.orbs.clear()
	kill_one(rich, "normal", "chapter1.skill.ember", "walker")
	kill_one(rich, "normal", "chapter1.skill.ember", "ranged")
	kill_one(rich, "normal", "chapter1.skill.ember", "charger")
	check(rich.orbs.size() == 1 and int(rich.orbs[0].amount) == 2 + 4 + 6, "E the bonus is the sum of the kills' orb values (2+4+6 with a 2x beat, bonus 100 percent): %s" % str(rich.orbs))
	var zero := make_run(document(func(d): d.rhythm.kill_burst = {"window_ticks": 30, "min_kills": 3, "xp_bonus_bps": 0, "descent_bonus_bps": 0}), 11)
	zero.step(Vector2.ZERO)
	zero.events.clear()
	zero.orbs.clear()
	for i in 3: kill_one(zero)
	check(bursts(zero).size() == 1 and zero.orbs.is_empty(), "E a bonus of 0 still sends the event but drops no orb")
	# The descent gauge's share.
	var gauge := make_run(document(with_burst(30, 10, 0, 10000)), 11, "chapter1.skill.ember", true)
	gauge.step(Vector2.ZERO)
	var each: int = gauge._descent_kill_points()
	var gauge_before: int = int(gauge.metrics.descent.gauge_in)
	for i in 10: kill_one(gauge)
	check(int(gauge.metrics.descent.gauge_in) - gauge_before == each * 10 * 2, "E the gauge gets the kills' points twice over with descent_bonus_bps 10000 (%d each)" % each)
	var gauge_off := make_run(document(with_burst(30, 10, 0, 0)), 11, "chapter1.skill.ember", true)
	gauge_off.step(Vector2.ZERO)
	var before_off: int = int(gauge_off.metrics.descent.gauge_in)
	for i in 10: kill_one(gauge_off)
	check(int(gauge_off.metrics.descent.gauge_in) - before_off == each * 10, "E descent_bonus_bps 0 leaves the gauge as it was")
	var no_descent := make_run(document(with_burst()), 11)
	no_descent.step(Vector2.ZERO)
	for i in 10: kill_one(no_descent)
	check(not no_descent.metrics.has("descent"), "E a run without the descent has no gauge and still bursts")
	# Off.
	var absent := make_run(document(), 11)
	absent.step(Vector2.ZERO)
	absent.events.clear()
	for i in 12: kill_one(absent)
	check(bursts(absent).is_empty() and not absent.metrics.has("kill_burst"), "E no kill_burst key: no event, no metrics")
	var off := make_run(document(with_burst(), false), 11)
	off.step(Vector2.ZERO)
	off.events.clear()
	for i in 12: kill_one(off)
	check(bursts(off).is_empty() and not off.metrics.has("kill_burst"), "E the rhythm off: kill_burst is ignored")

# ------------------------------------------------------------------ F

func pace_doc(soft := 600, ramp := 6000, max_bps := 20000) -> Callable:
	return func(d):
		d.grace.enabled = true
		d.grace.pace = {"soft_after_ticks": soft, "ramp_bps_per_s": ramp, "max_bps": max_bps}

func pace_checks() -> void:
	var run := make_run(document(pace_doc(), false), 11)
	check(run._pace_on and run.snapshot().has("pace"), "F the pace is on with grace.pace")
	check(run._gain_xp(10) == 10, "F at tick 0 the pace is 1x")
	run.tick = 600
	check(run._pace_bps() == 10000, "F exactly at soft_after_ticks it is still 1x")
	run.tick = 660
	check(run._pace_bps() == 16000, "F one second after: +6000 bps (%d)" % run._pace_bps())
	run.tick = 1200
	check(run._pace_bps() == 20000, "F capped at max_bps (%d)" % run._pace_bps())
	run.tick = 100000
	check(run._pace_bps() == 20000, "F the cap holds for ever")
	run.tick = 660
	var got: int = run._gain_xp(10)
	check(got == 16, "F ten xp at 1.6x gives 16 (%d)" % got)
	# The carry keeps the fractions: three single points at 1.5x make 4 (1,2,1 -> 1+1+2 with the carry).
	var carry := make_run(document(pace_doc(60, 3000, 20000), false), 11)
	carry.tick = 60 + 120
	check(carry._pace_bps() == 16000 or carry._pace_bps() == 16000, "F 120 ticks of ramp at 3000 bps/s is 1.6x")
	var total := 0
	for i in 5: total += carry._gain_xp(1)
	check(total == 8, "F five single points at 1.6x are 8 together (carry), got %d" % total)
	# A level-up (by xp or by a grace) puts the clock back to 1x.
	var reset := make_run(document(pace_doc(), false), 11)
	reset.tick = 5000
	check(reset._pace_bps() == 20000, "F late: 2x")
	reset._gain_xp(30)
	check(reset.growth.current_level() >= 2 and reset._pace_since == 5000 and reset._pace_bps() == 10000, "F a level-up resets the clock (level %d, since %d)" % [reset.growth.current_level(), reset._pace_since])
	check(reset._gain_xp(1) == 1, "F the next point is 1x")
	reset.tick = 5000 + 600 + 120
	check(reset._pace_bps() == 10000 + 120 * 6000 / 60 or reset._pace_bps() == 20000, "F the ramp starts again after the new soft time")
	var snap: Dictionary = reset.snapshot().pace
	check(int(snap.level) == reset.growth.current_level() and int(snap.since) == 5000, "F the snapshot carries level, since and carry")
	var grace_fill := make_run(document(func(d):
		pace_doc().call(d)
		d.rhythm.guardian_grace = true), 11)
	grace_fill.tick = 4000
	guardian_fall(grace_fill, 0)
	check(grace_fill.growth.current_level() == 2 and grace_fill._pace_since == grace_fill.tick, "F a guardian's level resets the clock too")
	# Off.
	var off := make_run(document(func(d): d.grace.enabled = true, false), 11)
	off.tick = 5000
	check(off.snapshot().has("pace") == false and off._gain_xp(10) == 10, "F no pace key: 1x always and no snapshot key")
	var grace_off := make_run(document(func(d): d.grace.pace = {"soft_after_ticks": 600, "ramp_bps_per_s": 6000, "max_bps": 20000}, false), 11)
	grace_off.tick = 5000
	check(grace_off._gain_xp(10) == 10 and not grace_off.snapshot().has("pace"), "F grace.pace under a disabled grace block is ignored")

# ------------------------------------------------------------------ G

func play(doc: Dictionary, ticks: int, seed_: int = 11, descent := false) -> RefCounted:
	var run := make_run(doc, seed_, "chapter1.skill.ember", descent)
	var pilot = Pilot.new()
	pilot.run = run
	for i in ticks:
		if run.mode in ["victory", "defeat"]: break
		run.hero.hp_raw = run.hero.max_hp_raw
		run.step(pilot.decide())
	return run

func neutral(d: Dictionary) -> void:
	d.rhythm.xp_thresholds = d.xp_thresholds.duplicate()
	d.rhythm.seal_kills = d.seal_kills.duplicate()
	d.rhythm.guardian_grace = false
	for beat in d.rhythm.beats: beat.xp_bps = 10000
	d.rhythm.trial.xp_bps = 10000

func off_equals_today_checks() -> void:
	var plain := play(document(), 2400)
	var neutral_run := play(document(neutral), 2400)
	check(hash_of(plain) == hash_of(neutral_run) and plain.tick == neutral_run.tick, "G neutral values (the old table and seal kills, 1x, no guardian grace) play exactly like no keys")
	var snap: Dictionary = plain.snapshot()
	check(not snap.rhythm.has("kill_burst") and not snap.has("pace") and not snap.metrics.has("kill_burst"), "G a plain rhythm run has none of the new snapshot keys")
	var ignored := play(document(func(d):
		TrialPace.apply(d)
		d.rhythm.beats[0].xp_bps = 30000
		d.rhythm.trial.xp_bps = 30000, false), 1200)
	var bare := play(document(Callable(), false), 1200)
	check(hash_of(ignored) == hash_of(bare), "G the rhythm off: every C1 key is ignored (same snapshot after 1200 ticks)")
	var no_rhythm := shipped()
	var plain_off := Chapter.new()
	check(plain_off.set_tuning(no_rhythm) and plain_off.start(11, "chapter1.skill.ember") and not plain_off.snapshot().has("rhythm") and not plain_off.snapshot().has("pace"), "G the shipped default run has no rhythm and no pace key")
	var with_grace_plain := play(document(func(d): d.grace.enabled = true, false), 1200)
	var with_grace_neutral := play(document(func(d):
		d.grace.enabled = true
		d.grace.pace = {"soft_after_ticks": 36000, "ramp_bps_per_s": 0, "max_bps": 10000}, false), 1200)
	check(with_grace_neutral.snapshot().has("pace") and not with_grace_plain.snapshot().has("pace"), "G pace only adds its own snapshot key")
	var left: Dictionary = with_grace_neutral.snapshot()
	left.erase("pace")
	check(JSON.stringify(left).sha256_text() == hash_of(with_grace_plain), "G a pace that never leaves 1x changes nothing but its own key")

# ------------------------------------------------------------------ H

func everything_on(d: Dictionary) -> void:
	TrialPace.apply(d)
	d.grace.enabled = true
	d.grace.pace = {"soft_after_ticks": 600, "ramp_bps_per_s": 800, "max_bps": 25000}

func determinism_checks() -> void:
	var a := play(document(everything_on), 3000)
	var b := play(document(everything_on), 3000)
	check(hash_of(a) == hash_of(b) and a.kills == b.kills and a.growth.current_level() == b.growth.current_level(), "H a pilot run with every C1 key on, twice: the same snapshot (tick %d, kills %d, level %d)" % [a.tick, a.kills, a.growth.current_level()])
	check(int(a.metrics.kill_burst.bursts) == int(b.metrics.kill_burst.bursts), "H the same number of bursts (%d)" % int(a.metrics.kill_burst.bursts))
	check(a.growth.xp_thresholds().size() == 16 and a._seal_total(0) == 365, "H the trial values reached the run (16 levels, seal 365)")
	var run := Chapter.new()
	check(TrialDocs.TRIAL_NAMES.has("pace") and TrialDocs.enable_rhythm_problem(run, false, true).is_empty() and run.start(11, "chapter1.skill.ember") and run.growth.xp_thresholds().size() == 16 and run.tuning.rhythm.kill_burst.min_kills == 10, "H the trial switch name is pace and it turns the first values on in memory")
	var file := shipped()
	check(not file.rhythm.has("kill_burst") and not file.rhythm.has("xp_thresholds"), "H the data file stays free of the keys after a trial document was built")
	var run2 := Chapter.new()
	check(TrialDocs.enable_rhythm_problem(run2).is_empty() and run2.start(11, "chapter1.skill.ember") and run2.growth.xp_thresholds().size() == 12, "H the rhythm trial without pace keeps the 12 level table")

func execute() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/_local/appdata/"):
		print("CHAPTER1_GROWTH_PACE_RESULT ", JSON.stringify({"checks": 0, "failures": ["user data dir is not isolated: refusing to run"]}))
		quit(1)
		return
	validator_checks()
	level_table_checks()
	guardian_checks()
	multiplier_checks()
	burst_checks()
	pace_checks()
	off_equals_today_checks()
	determinism_checks()
	print("CHAPTER1_GROWTH_PACE_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
