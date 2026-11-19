extends SceneTree
## Audio request recorder (check script, not product code). Plays one pilot run on the real core with no view
## and no audio device, and writes every sound request the game would make today, with its tick.
## The event -> sound mapping is the game's own: chapter1/presentation/audio_routes.gd (route() for the first pass of
## chapter_one._consume_events__chapter, late() for _consume_events), nothing is copied. Not part of it: the step-distance
## cue, and the pilot's growth choice (the app plays "equip" from choose(); the pilot calls the core directly, so the
## request is added here at the choice tick as a model of a human choosing).
## The core is only read: nothing here writes core state, the profile, or the user folder.
## Rules (cooldown, voices, pitch, variants) are NOT applied here; tools/dev/audio_mix_offline.py applies them.
##   python tools/dev/godot.py --headless --path . --script res://chapter1/tests/report_audio_requests.gd -- --seed=11 --primary=chapter1.skill.ember --out=_local/audio/requests/req_ember.json
## AU-RS0 (opt-in; without these two arguments the output is byte-for-byte what it was):
##   --run-spells=on          run with the in-run spell composition ON, by this tool only (chapter1/tests/spells_pick.gd; the data
##                            file stays "enabled": false). Requests get a 6th column gain_db (a 7th "long" when set) and the report
##                            a "run_spells_counts" block: ring casts per minute, targets per cast, casts with a controlled
##                            ordinary enemy, stagger.cut / detonate / hit.vs_cc / cast.prefer per minute, and the basic hits
##                            the old mapping lost to ring hits in the impact cooldown (a cooldown-only model of the answer).
##   --spells-pick=synergy    (needs --run-spells=on) the tool picks the growth cards with the same rule as hud_dump.gd.
const Core = preload("res://chapter1/core/chapter_core.gd")
const Pilot = preload("res://chapter1/core/chapter_pilot.gd")
const Routes = preload("res://chapter1/presentation/audio_routes.gd")
const Audio = preload("res://chapter1/presentation/combat_audio.gd")
const SpellsPick = preload("res://chapter1/tests/spells_pick.gd")

var requests: Array = []                 # [tick, cue, ui(0/1), playing(0/1), source(, gain_db(, "long"))]
var by_source: Dictionary = {}           # source -> {cue -> n}
var event_counts: Dictionary = {}
var spells_on := false
var origin: Dictionary = {}              # "cue<-ring" / "cue<-basic" -> n (fire, cold, lightning, impact requests by origin)
var tick_mismatch := 0

func _initialize() -> void:
	call_deferred("execute")

func _request(cue: String, tick: int, ui: bool, playing: bool, source: String, gain_db: float = 0.0, long: bool = false) -> void:
	var row: Array = [tick, cue, 1 if ui else 0, 1 if playing else 0, source]
	if spells_on:
		row.append(gain_db)
		if long: row.append("long")
	requests.append(row)
	if not by_source.has(source): by_source[source] = {}
	by_source[source][cue] = int(by_source[source].get(cue, 0)) + 1

## One tick of the --run-spells=on counters. `routed` is what audio_routes.route() returned for `fresh`.
func _count_tick(c: Dictionary, fresh: Array, routed: Array, run: RefCounted, tick: int, playing: bool, impact_list: Array) -> void:
	var rings: Dictionary = Routes.ring_elements(run.spells)
	var det_tick := {}
	var has_tail := false
	var has_pulse := false
	var cut_now := false
	var ring_kill := false
	for r in routed:
		var cue := String(r.cue)
		if cue in ["fire", "cold", "lightning", "impact"]:
			var from_ring: bool = rings.has(String(r.get("skill_id", "")))
			_bump(c.requests_from_ring if from_ring else c.requests_from_basic, cue)
		elif cue == "ring_body":
			has_pulse = true
			_bump(c.pulse_gain_db, "%.1f" % float(r.gain_db))
		elif cue.begins_with("ring_tail_"): has_tail = true; c["ring_tails"] = int(c.ring_tails) + 1
		elif cue == "ward_cut": c["ward_cut_requests"] = int(c.ward_cut_requests) + 1
		elif cue.begins_with("interlock_"): _bump(c.interlock_requests, cue)
		elif cue.begins_with("detonate_"):
			_bump(c.detonate_requests, cue)
			if bool(r.get("long", false)): c["long_detonations"] = int(c.long_detonations) + 1
	for event in fresh:
		var sid := String(event.get("skill_id", ""))
		match String(event.type):
			"cast":
				if rings.has(sid):
					c["ring_casts"] = int(c.ring_casts) + 1
					_bump(c.ring_targets, _bucket(event.targets.size()))
				elif event.has("prefer"): c["cast_prefer"] = int(c.cast_prefer) + 1
			"hit":
				var is_ring: bool = rings.has(sid)
				if is_ring:
					c["ring_hits"] = int(c.ring_hits) + 1
					if bool(event.get("frozen", false)): c["frozen_ring_hits"] = int(c.frozen_ring_hits) + 1
				else: c["basic_hits"] = int(c.basic_hits) + 1
				var cls := String(event.get("vs_cc", ""))
				if cls != "":
					_bump(c.hit_vs_cc, cls)
					if is_ring: _bump(c.hit_vs_cc_ring_hits, cls)
				if playing: impact_list.append([tick, is_ring])
			"stagger":
				c["stagger"] = int(c.stagger) + 1
				if bool(event.get("cut", false)):
					c["stagger_cut"] = int(c.stagger_cut) + 1
					cut_now = true
			"stun": _bump(c.stun, "ring" if rings.has(sid) else "basic")
			"detonate":
				var status := String(event.status)
				_bump(c.detonate, status)
				det_tick[status] = int(det_tick.get(status, 0)) + 1
			"death":
				if rings.has(sid): ring_kill = true
	for status in det_tick: _bump(c.detonate_per_tick, "%s:n=%d" % [status, int(det_tick[status])])
	if has_pulse:
		if has_tail: c["ring_casts_controlled"] = int(c.ring_casts_controlled) + 1
		if cut_now or ring_kill or not det_tick.is_empty(): c["ring_casts_payoff"] = int(c.ring_casts_payoff) + 1

func _bucket(n: int) -> String:
	return "1" if n <= 1 else ("2-3" if n <= 3 else ("4-7" if n <= 7 else "8+"))

func _bump(table: Dictionary, key: String, by: int = 1) -> void:
	table[key] = int(table.get(key, 0)) + by

## The impact cooldown (ticks) applied to a list of [tick, is_ring] requests, as the player does it (cooldown only; the
## voice limit is not modelled). Returns one played flag per request.
func _impact_sim(list: Array) -> Array:
	var cooldown: int = int(Audio.COOLDOWNS["impact"])
	var last := -100000
	var flags: Array = []
	for item in list:
		var ok: bool = int(item[0]) - last >= cooldown
		if ok: last = int(item[0])
		flags.append(ok)
	return flags

func execute() -> void:
	var seed_ := 11
	var primary := "chapter1.skill.ember"
	var out := ""
	var run_spells_arg := ""
	var spells_pick := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_ = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--primary="): primary = arg.trim_prefix("--primary=")
		elif arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		elif arg.begins_with("--run-spells="): run_spells_arg = arg.trim_prefix("--run-spells=")
		elif arg.begins_with("--spells-pick="): spells_pick = arg.trim_prefix("--spells-pick=")
	if out != "" and not out.begins_with("_local/"):
		push_error("--out must be under _local/"); quit(2); return
	if not run_spells_arg.is_empty() and run_spells_arg != "on":
		push_error("--run-spells=%s is unknown (on)" % run_spells_arg); quit(2); return
	if not spells_pick.is_empty() and (spells_pick != "synergy" or run_spells_arg != "on"):
		push_error("--spells-pick needs --run-spells=on and the value synergy"); quit(2); return
	spells_on = run_spells_arg == "on"
	var run = Core.new()
	var pilot = Pilot.new()
	pilot.run = run
	var routes = Routes.new()
	if spells_on:
		var problem: String = SpellsPick.enable(run)
		if not problem.is_empty():
			push_error("report_audio_requests: " + problem); quit(2); return
	var picks: Array = []
	# --run-spells=on counters
	var c := {"ring_casts": 0, "ring_targets": {}, "ring_casts_controlled": 0, "ring_casts_payoff": 0, "ring_tails": 0,
		"stagger": 0, "stagger_cut": 0, "stun": {}, "detonate": {}, "detonate_per_tick": {},
		"hit_vs_cc": {}, "hit_vs_cc_ring_hits": {}, "cast_prefer": 0, "frozen_ring_hits": 0, "ring_hits": 0, "basic_hits": 0,
		"requests_from_ring": {}, "requests_from_basic": {}, "long_detonations": 0, "ward_cut_requests": 0,
		"interlock_requests": {}, "detonate_requests": {}, "pulse_gain_db": {}}
	var impact_list: Array = []             # [tick, is_ring] of every hit that the OLD mapping sent to impact while playing
	var pulse_ticks: Array = []
	if not run.start(seed_, primary):
		push_error(str(run.errors)); quit(2); return
	var guard := 0
	var last_seq := -1
	var prev: Vector2 = run.hero.position
	var step_dist := 0.0
	var windup_prev: Dictionary = {}
	var windup_starts := 0
	var low_hp_cross := 0
	var was_low := false
	while run.mode not in ["victory", "defeat"] and guard < 12 * 60 * 60 + 500:
		if not spells_pick.is_empty() and run.mode == "choice":
			var row: Dictionary = SpellsPick.pick(run, "report_audio_requests")
			if not row.is_empty():
				picks.append(row)
				_request("equip", run.tick, true, false, "choose")
		var picks_before: int = pilot.selections.size()
		var movement: Vector2 = pilot.decide()
		if pilot.selections.size() > picks_before:
			_request("equip", run.tick, true, false, "choose")
		run.step(movement)
		guard += 1
		var playing: bool = run.mode == "playing"
		var tick: int = run.tick
		var fresh: Array = []
		for event in run.events:
			if int(event.seq) <= last_seq: continue
			last_seq = int(event.seq)
			fresh.append(event)
			var t := String(event.type)
			event_counts[t] = int(event_counts.get(t, 0)) + 1
		# pass 1: _consume_events__chapter, then pass 2: _consume_events (the game's own mapping, audio_routes.gd)
		var routed: Array = routes.route(fresh, run.spells, tick)
		for r in routed:
			_request(String(r.cue), tick, bool(r.ui), playing, String(r.source), float(r.gain_db), bool(r.get("long", false)))
		for event in fresh:
			for r in routes.late(event):
				_request(String(r.cue), tick, bool(r.ui), playing, String(r.source), float(r.gain_db), bool(r.get("long", false)))
		if spells_on:
			_count_tick(c, fresh, routed, run, tick, playing, impact_list)
			for event in fresh:
				if int(event.tick) != tick: tick_mismatch += 1
		if playing:
			step_dist += run.hero.position.distance_to(prev)
			if step_dist > 1.15:
				_request("step", tick, false, playing, "step_distance")
				step_dist = 0.0
		prev = run.hero.position
		for e in run.enemies.values():
			var w: bool = String(e.get("state", "")) == "windup" and int(e.hp_raw) > 0
			if w and not windup_prev.get(e.id, false): windup_starts += 1
			windup_prev[e.id] = w
		var hp_ratio: float = float(run.hero.hp_raw) / maxf(1.0, float(run.hero.max_hp_raw))
		if hp_ratio < .3 and not was_low: low_hp_cross += 1; was_low = true
		elif hp_ratio > .5: was_low = false
	var report := {
		"seed": seed_, "primary": primary, "mode": run.mode, "ticks": run.tick, "seconds": run.tick / 60.0,
		"kills": run.kills, "events": event_counts, "requests_by_source": by_source,
		"request_count": requests.size(), "windup_starts": windup_starts, "low_hp_30_crossings": low_hp_cross,
		"note": "playing=0 requests are dropped by the player unless ui=1; tick is run.tick (does not advance in choice screens)",
		"requests": requests,
	}
	if spells_on:
		var minutes: float = float(run.tick) / 3600.0
		var old_flags: Array = _impact_sim(impact_list)
		var new_list: Array = impact_list.filter(func(item): return not item[1])
		var new_flags: Array = _impact_sim(new_list)
		var j := 0
		var eaten := 0
		var basic_playing := 0
		var old_basic_dropped := 0
		for i in impact_list.size():
			if impact_list[i][1]: continue
			basic_playing += 1
			if not old_flags[i]: old_basic_dropped += 1
			if new_flags[j] and not old_flags[i]: eaten += 1
			j += 1
		var per_min := func(n) -> float: return snappedf(float(n) / maxf(minutes, .0001), .01)
		var detonate_total := 0
		for status in c.detonate: detonate_total += int(c.detonate[status])
		var vs_cc_total := 0
		for cls in c.hit_vs_cc: vs_cc_total += int(c.hit_vs_cc[cls])
		c["minutes"] = snappedf(minutes, .001)
		c["ring_casts_per_min"] = per_min.call(c.ring_casts)
		c["stagger_cut_per_min"] = per_min.call(c.stagger_cut)
		c["detonate_per_min"] = per_min.call(detonate_total)
		c["hit_vs_cc_per_min"] = per_min.call(vs_cc_total)
		c["cast_prefer_per_min"] = per_min.call(c.cast_prefer)
		c["impact_sim"] = {"basic_hit_requests_playing": basic_playing, "ring_hit_requests_playing": impact_list.size() - basic_playing,
			"basic_dropped_by_cooldown_old_mapping": old_basic_dropped, "basic_dropped_by_cooldown_new_mapping": new_list.size() - new_flags.count(true),
			"basic_lost_to_ring_hits_old_mapping": eaten, "note": "cooldown only (impact, %d ticks), voice limit not modelled; counted over requests while playing" % int(Audio.COOLDOWNS["impact"])}
		report["run_spells_counts"] = c
		report["run_spells"] = "on"
		report["spells_pick"] = spells_pick
		report["picks"] = picks
		report["tick_mismatch_events_vs_requests"] = tick_mismatch
	var summary := report.duplicate()
	summary.erase("requests")
	print("AUDIO_REQUEST_LOG ", JSON.stringify(summary))
	if out != "":
		var path := ProjectSettings.globalize_path("res://" + out)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(report))
		f.close()
	quit(0)
