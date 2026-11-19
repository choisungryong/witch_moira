extends SceneTree
## W7 check of the battle recorder (chapter1/app/run_record.gd, D11 F1).
##   godot --headless --path . --script res://chapter1/tests/test_run_record.gd -- [--all | --primaries=ember,frost,arc] [--seed=11]
## (default: one whole run with the frost start skill; --all plays all three)
## Plays whole pilot runs on the real core with the recorder attached and checks:
##   A  skill damage equals the sum of the hit events' dealt_raw (overflow excluded) per skill, within 1 % of the total too;
##      kills equal the core's kill count, deaths by skill add up, potions, damage taken, item sources, ticks, xp
##   B  to_last_record() keeps the key set and the ranges of docs/specs/T6-save-schema5-directives-20261119.ko.md 4.3
##   C  the same seed twice gives the same record and summary
##   D  a run with the recorder and one without it have the same snapshot hash chain (the recorder changes nothing)
##   E  reading the same events twice changes nothing, finish() twice changes nothing, summary() is a copy
##   F  a lost run (hero standing still; abandoned if it survives) carries the "why did I lose" material
## Marker: CHAPTER1_RUN_RECORD_TEST_RESULT. Also prints RUN_RECORD_SAMPLE lines (one record per skill line, for reports).
## Writes nothing.
const Chapter = preload("res://chapter1/core/chapter_core.gd")
const Pilot = preload("res://chapter1/core/chapter_pilot.gd")
const RunRecord = preload("res://chapter1/app/run_record.gd")
const ID_PATTERN := "^[a-z0-9][a-z0-9_.:-]{0,79}\\z"
const DEPTH_PATTERN := "^d[0-9]{1,2}\\z"
const RECORD_KEYS := ["depth", "victory", "ticks", "kills", "elite_kills", "champion_kills", "boss_kill", "grade", "potions_used", "damage_taken", "xp_gained", "essence_gained", "items", "skills"]
const SKILL_KEYS := ["id", "got_tick", "got_level", "rank", "evolved", "damage", "kills"]
const MAX_TICKS := 12 * 60 * 60 + 500
const HASH_EVERY := 1200
## Ticks played by the repeat runs of C and D (the whole runs are played once each by A and B).
const CHECK_TICKS := 9000
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("execute")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func in_range(value: Variant, low: int, high: int) -> bool:
	return value is int and int(value) >= low and int(value) <= high

## Every way the record can differ from T6 4.3. Empty means it keeps the shape.
func record_errors(record: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var keys: Array = record.keys()
	keys.sort()
	var want: Array = RECORD_KEYS.duplicate()
	want.sort()
	if keys != want:
		errors.append("key set %s" % str(keys))
		return errors
	if not record.depth is String or RegEx.create_from_string(DEPTH_PATTERN).search(record.depth) == null:
		errors.append("depth")
	for key in ["victory", "boss_kill"]:
		if not record[key] is bool:
			errors.append(key + " not bool")
	for key in ["ticks", "kills", "elite_kills", "potions_used", "damage_taken", "xp_gained", "essence_gained"]:
		if not in_range(record[key], 0, 1000000000):
			errors.append(key + " range")
	if not in_range(record.champion_kills, 0, 16):
		errors.append("champion_kills range")
	if not in_range(record.grade, 0, 4):
		errors.append("grade range")
	if not record.items is Dictionary or record.items.size() > 16:
		errors.append("items shape")
	else:
		for key in record.items:
			if not key is String or RegEx.create_from_string(ID_PATTERN).search(key) == null or not in_range(record.items[key], 0, 1000000000):
				errors.append("items entry " + str(key))
	if not record.skills is Array or record.skills.size() > 16:
		errors.append("skills shape")
	else:
		for row in record.skills:
			if not row is Dictionary:
				errors.append("skill row type")
				continue
			var row_keys: Array = row.keys()
			row_keys.sort()
			var want_row: Array = SKILL_KEYS.duplicate()
			want_row.sort()
			if row_keys != want_row:
				errors.append("skill key set %s" % str(row_keys))
				continue
			if not row.id is String or RegEx.create_from_string(ID_PATTERN).search(row.id) == null:
				errors.append("skill id")
			if not in_range(row.got_tick, 0, 1000000000) or not in_range(row.got_level, 0, 99) or not in_range(row.rank, 0, 99) or not in_range(row.kills, 0, 1000000000) or not in_range(row.damage, 0, 1000000000000):
				errors.append("skill range " + str(row.get("id", "")))
			if not row.evolved is bool:
				errors.append("skill evolved")
	return errors

## One whole run. `with_recorder` false plays the same loop without the recorder. `stand_still` ignores the pilot's movement.
func play(seed_: int, primary: String, with_recorder: bool, stand_still: bool = false, abandon_at: int = -1, feed_twice: bool = false, tick_limit: int = MAX_TICKS) -> Dictionary:
	var run: RefCounted = Chapter.new()
	var pilot: RefCounted = Pilot.new()
	pilot.run = run
	run.first_boss_kill = true
	if not run.start(seed_, primary):
		return {"error": "start rejected: " + str(run.errors)}
	var recorder: RefCounted = RunRecord.new()
	if with_recorder:
		recorder.begin(run, "d1")
	var dealt: Dictionary = {}
	var full: Dictionary = {}
	var deaths: Dictionary = {}
	var taken := 0
	var hashes: Array[String] = []
	var guard := 0
	var started := Time.get_ticks_msec()
	var tally_seq := -1
	var hit_log: Array = []
	var hp_log: Array = []
	while run.mode not in ["victory", "defeat"] and guard < tick_limit:
		var move: Vector2 = pilot.decide()
		if with_recorder:
			recorder.consume(run.events)
			if feed_twice:
				recorder.consume(run.events)
		run.step(Vector2.ZERO if stand_still else move)
		guard += 1
		if with_recorder:
			recorder.consume(run.events)
			if feed_twice:
				recorder.consume(run.events)
			recorder.observe(run)
		for event in run.events:
			# step() does nothing outside "playing" and leaves the list as it was: count an event once.
			if int(event.seq) <= tally_seq:
				continue
			tally_seq = int(event.seq)
			match String(event.type):
				"hit":
					var id_ := String(event.skill_id)
					dealt[id_] = int(dealt.get(id_, 0)) + int(event.dealt_raw)
					hit_log.append([int(event.tick), int(event.dealt_raw)])
					full[id_] = int(full.get(id_, 0)) + int(event.damage_raw)
				"death":
					deaths[String(event.skill_id)] = int(deaths.get(String(event.skill_id), 0)) + 1
				"hero_hit":
					taken += int(event.damage_raw)
					hp_log.append([int(event.tick), int(event.hp_after_raw)])
		if run.tick % HASH_EVERY == 0:
			hashes.append(JSON.stringify(run.snapshot()).sha256_text())
		if abandon_at >= 0 and run.tick >= abandon_at and run.mode == "playing":
			run.abandon()
			if with_recorder:
				recorder.consume(run.events)
	hashes.append(JSON.stringify(run.snapshot()).sha256_text())
	if with_recorder:
		recorder.finish(run)
		if feed_twice:
			recorder.finish(run)
	print("RUN_RECORD_TIME ", primary, " recorder=", with_recorder, " ticks=", guard, " ms=", Time.get_ticks_msec() - started)
	return {"run": run, "pilot": pilot, "recorder": recorder, "dealt": dealt, "full": full, "deaths": deaths, "taken": taken, "hit_log": hit_log, "hp_log": hp_log, "hashes": hashes, "ticks": guard}

func sample_lines(label: String, data: Dictionary) -> void:
	var recorder: RefCounted = data.recorder
	var summary: Dictionary = recorder.summary()
	var record: Dictionary = summary.record
	print("RUN_RECORD_SAMPLE ", label, " ", JSON.stringify({"victory": record.victory, "ticks": record.ticks, "kills": record.kills, "elite_kills": record.elite_kills, "champion_kills": record.champion_kills,
		"boss_kill": record.boss_kill, "potions_used": record.potions_used, "damage_taken": record.damage_taken, "xp_gained": record.xp_gained, "items": record.items,
		"total_damage": summary.total_damage, "events_dropped": summary.events_dropped, "pairs": summary.pairs.size(), "beats": summary.beats.size()}))
	for row in summary.skills:
		print("RUN_RECORD_SKILL ", label, " ", JSON.stringify(row))

func check_run(label: String, data: Dictionary) -> void:
	check(not data.has("error"), "%s: run started (%s)" % [label, str(data.get("error", ""))])
	if data.has("error"):
		return
	var run: RefCounted = data.run
	var recorder: RefCounted = data.recorder
	var unit := int(run.UNIT)
	check(run.mode in ["victory", "defeat"], "%s: the run ended (mode %s after %d ticks)" % [label, run.mode, int(data.ticks)])
	check(recorder.is_finished(), "%s: the recorder is finished" % label)
	var record: Dictionary = recorder.to_last_record()
	var errors := record_errors(record)
	check(errors.is_empty(), "%s: to_last_record keeps the T6 4.3 shape: %s" % [label, str(errors)])
	# A: skill damage = sum of dealt_raw per skill, floor by unit
	var recorded_total := 0
	var skill_kills := 0
	var seen: Dictionary = {}
	for row in record.skills:
		seen[row.id] = true
		recorded_total += int(row.damage)
		skill_kills += int(row.kills)
		check(int(row.damage) == int(data.dealt.get(row.id, 0)) / unit, "%s: %s damage %d equals the event sum %d" % [label, row.id, int(row.damage), int(data.dealt.get(row.id, 0)) / unit])
		check(int(row.kills) == int(data.deaths.get(row.id, 0)), "%s: %s kills %d equal the death events %d" % [label, row.id, int(row.kills), int(data.deaths.get(row.id, 0))])
	for id_ in data.dealt:
		check(seen.has(id_), "%s: skill %s with damage is in the table" % [label, id_])
	var event_total := 0
	var full_total := 0
	for id_ in data.dealt:
		event_total += int(data.dealt[id_]) / unit
		full_total += int(data.full[id_])
	check(absf(float(recorded_total) - float(event_total)) <= maxf(1.0, float(event_total) * 0.01), "%s: total damage %d within 1 %% of the event sum %d" % [label, recorded_total, event_total])
	check(recorded_total <= int(run.metrics.damage_raw) / unit, "%s: recorded damage %d is not above metrics.damage_raw %d (overflow excluded)" % [label, recorded_total, int(run.metrics.damage_raw) / unit])
	check(skill_kills == int(run.kills) and int(record.kills) == int(run.kills), "%s: kills %d, skill kills %d equal the core's %d" % [label, int(record.kills), skill_kills, int(run.kills)])
	check(int(record.ticks) == int(run.tick) and bool(record.victory) == (run.mode == "victory"), "%s: ticks and victory" % label)
	check(bool(record.boss_kill) == (run.mode == "victory"), "%s: boss_kill follows the win" % label)
	check(int(record.potions_used) == int(data.pilot.potion_uses), "%s: potions %d equal the pilot's %d" % [label, int(record.potions_used), int(data.pilot.potion_uses)])
	check(int(record.damage_taken) == int(data.taken) / unit, "%s: damage taken %d equals the hero_hit sum %d" % [label, int(record.damage_taken), int(data.taken) / unit])
	var item_total := 0
	for key in record.items:
		item_total += int(record.items[key])
	check(item_total == int(run.metrics.dropped_items), "%s: items by source %d equal the core's dropped items %d" % [label, item_total, int(run.metrics.dropped_items)])
	check(int(record.xp_gained) == int(run.progress_summary().get("xp_gained", 0)), "%s: xp_gained equals the core's progress" % label)
	check(int(run.metrics.get("events_dropped", 0)) == 0 and int(recorder.summary().events_dropped) == 0, "%s: no event was dropped (MAX_EVENTS)" % label)
	check(record.skills.size() > 0 and String(record.skills[0].id) != "" and int(record.skills[0].damage) > 0, "%s: the skill table has a first row with damage" % label)
	var primary: String = String(run.growth.snapshot().primary)
	var primary_row := {}
	for row in record.skills:
		if row.id == primary:
			primary_row = row
	check(not primary_row.is_empty() and int(primary_row.got_tick) == 0 and int(primary_row.got_level) == 1, "%s: the primary skill was got at tick 0, level 1" % label)
	var summary: Dictionary = recorder.summary()
	check(bool(summary.ready) and JSON.stringify(summary.record) == JSON.stringify(record), "%s: summary carries the same record" % label)
	var share := 0
	for row in summary.skills:
		share += int(row.share_bps)
	check(absi(share - 10000) <= summary.skills.size(), "%s: shares add up to 100 %% (%d bps)" % [label, share])
	check((summary.loss as Dictionary).is_empty() == (run.mode == "victory"), "%s: loss material only for a lost run" % label)
	# The screen's extra material: final level, primary skill, damage per second of the last 60 seconds, the named picks.
	check(int(summary.level) == int(run.growth.snapshot().level) and int(summary.level) >= 2, "%s: summary.level is the final level (%d)" % [label, int(summary.level)])
	check(String(summary.primary_id) == primary, "%s: summary.primary_id is the primary skill" % label)
	var recent_raw := 0
	for entry in data.hit_log:
		if int(entry[0]) / int(run.HZ) * int(run.HZ) >= int(run.tick) - 60 * int(run.HZ):
			recent_raw += int(entry[1])
	var recent_ticks := mini(int(run.tick), 60 * int(run.HZ))
	check(int(summary.recent_window_ticks) == recent_ticks and int(summary.recent_dps_tenths) == recent_raw * int(run.HZ) * 10 / unit / maxi(1, recent_ticks), "%s: recent_dps_tenths %d equals the last-60-second event sum" % [label, int(summary.recent_dps_tenths)])
	check(int(summary.recent_dps_tenths) > 0 or run.mode == "defeat", "%s: a run that ended has recent damage per second" % label)
	check(summary.picks.size() > 0, "%s: the record lists the picks" % label)
	for pick in summary.picks:
		var named_ok: bool = String(pick.title_key).begins_with("skill.") or String(pick.title_key).begins_with("grace.passive.")
		var expect_key := ""
		match String(pick.kind):
			"unlock", "rank", "axis": expect_key = "skill.%s.name" % pick.skill_id
			"evolve": expect_key = "skill.%s.evolved_name" % pick.skill_id
			"passive": expect_key = String(pick.title_key)
		check(named_ok and String(pick.title_key) == expect_key and String(pick.card).begins_with(String(pick.kind) + ":"), "%s: pick %s carries kind, skill and title_key (%s)" % [label, pick.card, JSON.stringify(pick)])
		check(String(pick.kind) != "rank" or int(pick.rank) >= 2, "%s: a rank pick carries its rank" % label)
	summary.record.kills = -5
	check(int(recorder.summary().record.kills) == int(record.kills), "%s: summary() is a copy" % label)

func execute() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/_local/appdata/"):
		print("CHAPTER1_RUN_RECORD_TEST_RESULT ", JSON.stringify({"checks": 0, "failures": ["user data dir is not isolated: refusing to run"]}))
		quit(1)
		return
	var primaries: Array = ["frost"]
	var seed_ := 11
	for arg in OS.get_cmdline_user_args():
		if arg == "--all":
			primaries = ["ember", "frost", "arc"]
		elif arg.begins_with("--primaries="):
			primaries = Array(arg.trim_prefix("--primaries=").split(","))
		elif arg.begins_with("--seed="):
			seed_ = int(arg.trim_prefix("--seed="))
		else:
			push_error("Unknown argument " + arg)
			quit(2)
			return
	var first: Dictionary = {}
	for name in primaries:
		var id_ := "chapter1.skill." + String(name)
		var data := play(seed_, id_, true)
		check_run(String(name), data)
		if not data.has("error"):
			sample_lines(String(name), data)
		if first.is_empty() and not data.has("error"):
			first = {"name": String(name), "id": id_, "data": data}
	if not first.is_empty():
		# C: same seed twice, D: without the recorder. The first CHECK_TICKS ticks are enough for both and keep the check short.
		var one := play(seed_, first.id, true, false, -1, false, CHECK_TICKS)
		var again := play(seed_, first.id, true, false, -1, false, CHECK_TICKS)
		check(not one.has("error") and not again.has("error") and JSON.stringify(again.recorder.to_last_record()) == JSON.stringify(one.recorder.to_last_record()), "C %s twice with the same seed: same record" % first.name)
		check(not one.has("error") and not again.has("error") and JSON.stringify(again.recorder.summary()) == JSON.stringify(one.recorder.summary()), "C %s twice with the same seed: same summary" % first.name)
		var bare := play(seed_, first.id, false, false, -1, false, CHECK_TICKS)
		check(not one.has("error") and not bare.has("error") and bare.hashes == one.hashes and bare.hashes.size() > 3, "D %s with and without the recorder: same snapshot hash chain (%d hashes over %d ticks)" % [first.name, one.hashes.size(), CHECK_TICKS])
		check(not bare.has("error") and int(bare.run.tick) == int(one.run.tick) and int(bare.run.kills) == int(one.run.kills), "D %s with and without the recorder: same end tick and kills" % first.name)
	# E: events read twice, finish twice
	var once := play(seed_, "chapter1.skill.frost", true, false, 2400)
	var twice := play(seed_, "chapter1.skill.frost", true, false, 2400, true)
	check(not once.has("error") and not twice.has("error") and JSON.stringify(once.recorder.summary()) == JSON.stringify(twice.recorder.summary()), "E reading the events twice and finishing twice gives the same summary")
	# F: a lost run
	var lost := play(seed_, "chapter1.skill.frost", true, true, 14000)
	check(not lost.has("error") and lost.run.mode == "defeat", "F the hero standing still ends in a defeat")
	if not lost.has("error"):
		var summary: Dictionary = lost.recorder.summary()
		var loss: Dictionary = summary.loss
		check(not loss.is_empty() and not bool(summary.record.victory), "F a lost run is not a win and has loss material")
		check(record_errors(summary.record).is_empty(), "F the record of a lost run keeps the T6 4.3 shape: %s" % str(record_errors(summary.record)))
		check(loss.has("by_source") and loss.has("alive_trend") and loss.has("last_hit") and int(loss.hits) > 0, "F the material has damage by source, the living-enemy trend and the last blow")
		check((loss.alive_trend as Array).size() >= 20 and (loss.alive_trend as Array).size() <= 32, "F about 30 one-second samples of the living enemies (%d)" % (loss.alive_trend as Array).size())
		var by_source_life := 0
		for kind in loss.by_source:
			by_source_life += int(loss.by_source[kind].hits)
		check(by_source_life == int(loss.hits), "F hits by source add up")
		check(int(loss.last_hit.ticks_before_end) <= int(loss.window_ticks), "F the last blow lies inside the window")
		check(not bool(summary.abandoned), "F a real defeat is not marked abandoned")
		# alive_trend.hp_bps is the real life (sampled from the hero), and hp_low_bps comes from hero_hit.hp_after_raw.
		var lost_run: RefCounted = lost.run
		var trend: Array = loss.alive_trend
		var low := 10001
		var high := -1
		var end_bps := -1
		for sample in trend:
			low = mini(low, int(sample.hp_bps))
			high = maxi(high, int(sample.hp_bps))
			if int(sample.ticks_before_end) == 0:
				end_bps = int(sample.hp_bps)
		check(low < high and low >= 0 and high <= 10000, "F alive_trend.hp_bps moves with the hero's real life (%d..%d)" % [low, high])
		check(end_bps == int(lost_run.hero.hp_raw) * 10000 / int(lost_run.hero.max_hp_raw), "F the sample at the end equals the hero's real life (%d)" % end_bps)
		var expect_low := -1
		for entry in lost.hp_log:
			if int(entry[0]) >= int(lost_run.tick) - int(loss.window_ticks):
				var bps := int(entry[1]) * 10000 / int(lost_run.hero.max_hp_raw)
				expect_low = bps if expect_low < 0 else mini(expect_low, bps)
		check(int(loss.hp_low_bps) == expect_low and expect_low >= 0, "F loss.hp_low_bps %d equals the lowest hero_hit.hp_after_raw in the window %d" % [int(loss.hp_low_bps), expect_low])
		print("RUN_RECORD_LOSS ", JSON.stringify(loss))
		check_run("lost", lost)
	# Picks of an event without the core's `card` detail are named from the card id.
	var fake_run: RefCounted = Chapter.new()
	fake_run.start(seed_, "chapter1.skill.frost")
	var fake: RefCounted = RunRecord.new()
	fake.begin(fake_run, "d1")
	fake.consume([{"seq": 1, "tick": 10, "type": "growth", "card_id": "axis:chapter1.skill.ember:reach", "growth": {"level": 3, "ranks": {}}},
		{"seq": 2, "tick": 20, "type": "growth", "card_id": "rank:chapter1.skill.frost:3", "growth": {"level": 4, "ranks": {}}},
		{"seq": 3, "tick": 30, "type": "growth", "card_id": "passive:chapter1.passive.crystal", "growth": {"level": 5, "ranks": {}}}])
	fake.finish(fake_run)
	var fake_picks: Array = fake.summary().picks
	check(fake_picks.size() == 3 and fake_picks[0].axis == "reach" and fake_picks[0].skill_id == "chapter1.skill.ember" and fake_picks[0].title_key == "skill.chapter1.skill.ember.name" and fake_picks[1].rank == 3 and fake_picks[2].title_key == "grace.passive.chapter1.passive.crystal.name", "G picks without the core's card detail are named from the id: " + JSON.stringify(fake_picks))
	var gave_up := play(seed_, "chapter1.skill.frost", true, false, 1800)
	check(not gave_up.has("error") and gave_up.run.mode == "defeat" and bool(gave_up.recorder.summary().abandoned) and not bool(gave_up.recorder.to_last_record().victory), "F an abandoned run is a defeat marked abandoned")
	print("CHAPTER1_RUN_RECORD_TEST_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
