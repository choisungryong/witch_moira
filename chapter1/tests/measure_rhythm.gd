extends SceneTree
## Difficulty-rhythm meter (D11 G2). Plays whole pilot runs on the real core and only READS core state/events.
## It never calls anything that draws random numbers or mutates the core besides the normal step(); it does not load
## chapter_profile.gd. Output goes to stdout (tables) and --out (JSON, only under _local/).
##   python tools/dev/godot.py --headless --path . --script res://chapter1/tests/measure_rhythm.gd -- --seeds=11,12,13 --primaries=ember,frost,arc --out=_local/w0/rhythm.json --bin=30
## Grouping: fixed-size time bins (--bin seconds), D11 A2 beats, and zones. Beats are grouped by `beat_started` core
## events when the core emits them; otherwise by the time boundaries in BEATS (the output says which).
const Core = preload("res://chapter1/core/chapter_core.gd")
const Pilot = preload("res://chapter1/core/chapter_pilot.gd")
const DescentPolicy = preload("res://chapter1/tests/descent_policy.gd")

## D11 A2 targets [hypothesis]. from/to are the time boundaries used when the core has no beat_started event.
## The guardian windows in the A2 table overlap the neighbouring beats; they are folded into those beats here.
## null = no target for that metric.
const BEATS := [
	{"name": "기", "from": 0.0, "to": 60.0, "alive_avg": [5, 15], "alive_max": 20, "kpm": [80, 180], "hits_pm": [0, 2], "dmg30": 0.15},
	{"name": "승1", "from": 60.0, "to": 130.0, "alive_avg": [15, 35], "alive_max": 45, "kpm": [220, 380], "hits_pm": [2, 6], "dmg30": 0.30},
	{"name": "승2", "from": 130.0, "to": 285.0, "alive_avg": [30, 60], "alive_max": 75, "kpm": [380, 600], "hits_pm": [4, 9], "dmg30": 0.45},
	{"name": "전A", "from": 285.0, "to": 345.0, "alive_avg": [50, 85], "alive_max": 100, "kpm": [550, 850], "hits_pm": [6, 12], "dmg30": 0.60},
	{"name": "전B", "from": 345.0, "to": 390.0, "alive_avg": [70, 100], "alive_max": 100, "kpm": [700, 1100], "hits_pm": [8, 14], "dmg30": 0.70},
	{"name": "전C", "from": 390.0, "to": 1.0e9, "alive_avg": [10, 25], "alive_max": 30, "kpm": null, "hits_pm": null, "dmg30": null},
]
## Core beat ids (combat_tuning.json rhythm.beats, plus the trial and the boss) -> the names of the A2 table above.
const BEAT_NAMES := {"gi": "기", "seung1": "승1", "seung2": "승2", "jeon_a": "전A", "trial": "전B", "boss": "전C"}
const METRICS := ["alive_avg", "alive_max", "kpm", "hits_pm", "dmg30"]
const MIN_TICKS := 300

var bin_s := 30.0
## --rhythm-on: test switch. The shipped document is read, rhythm.enabled and trial.enabled are set in memory only.
var rhythm_on := false
## --stop-s=N: end every run after N seconds (a short look at the first minutes, e.g. the run opening with --bin=10).
var stop_s := 0.0
## --descent=off|now|hold|panic: switch the descent on in memory (descent.json stays off) and let the bot use it by that rule (D15 A6.5).
## "off" counts the gauge but never calls. --spells-on: the in-run spell composition on in memory (the pilot picks its own cards).
var descent_policy := ""
var spells_on := false

func _initialize() -> void:
	call_deferred("execute")

func execute() -> void:
	var seeds: Array = [11, 12, 13]
	var prims: Array = ["chapter1.skill.ember", "chapter1.skill.frost", "chapter1.skill.arc"]
	var out := "_local/w0/rhythm.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seeds = []
			for p in arg.trim_prefix("--seeds=").split(","): seeds.append(int(p))
		elif arg.begins_with("--primaries="):
			prims = []
			for p in arg.trim_prefix("--primaries=").split(","):
				prims.append(p if p.begins_with("chapter1.skill.") else "chapter1.skill." + p)
		elif arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		elif arg == "--rhythm-on": rhythm_on = true
		elif arg.begins_with("--stop-s="): stop_s = maxf(0.0, float(arg.trim_prefix("--stop-s=")))
		elif arg.begins_with("--descent="):
			descent_policy = arg.trim_prefix("--descent=")
			if not DescentPolicy.valid(descent_policy):
				push_error("measure_rhythm: --descent must be one of %s" % str(DescentPolicy.POLICIES))
				quit(1)
				return
		elif arg == "--spells-on": spells_on = true
		elif arg.begins_with("--bin="): bin_s = maxf(5.0, float(arg.trim_prefix("--bin=")))
	if not out.begins_with("_local/") or out.contains("..") or out.contains(":") or out.begins_with("/"):
		push_error("measure_rhythm: --out must be a relative path under _local/ (got %s)" % out)
		quit(1)
		return
	var runs: Array = []
	for prim in prims:
		for s in seeds:
			var r := play(int(s), String(prim))
			if r.is_empty():
				quit(2)
				return
			runs.append(r)
			print_run(r)
	var cross := cross_summary(runs)
	print_cross(cross)
	var result := {"bin_s": bin_s, "seeds": seeds, "primaries": prims, "runs": runs, "cross": cross,
		"note": "pilot input, no permanent tree, first_boss_kill=true; bot results are stability/balance reference only, fun is unevaluated"}
	var abs_path := ProjectSettings.globalize_path("res://" + out)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		push_error("measure_rhythm: cannot write %s" % abs_path)
		quit(3)
		return
	f.store_string(JSON.stringify(result, "\t"))
	f.close()
	var brief: Array = []
	for r in runs:
		brief.append({"primary": r.primary, "seed": r.seed, "mode": r.mode, "secs": r.secs, "kills": r.kills,
			"grace": r.summary.grace_count, "grace_first75": r.summary.grace_first75, "beat_source": r.beat_source})
	print("CHAPTER1_RHYTHM_RESULT " + JSON.stringify({"out": out, "runs": brief}))
	quit(0)

# ---------- accumulators ----------
func new_acc(label: String, from_s: float) -> Dictionary:
	return {"label": label, "from_s": from_s, "first_s": from_s, "last_s": from_s, "ticks": 0, "kills": 0, "alive": [], "alive_max": 0,
		"hits": 0, "dmg": 0.0, "attacks": 0, "prim_hits": 0, "grace": 0, "grace_times": [], "drops": 0, "drops_by_source": {}, "drops_nosrc": 0,
		"waves": 0, "extras": {}, "events_dropped": 0}

func touch(a: Dictionary, sec: float) -> void:
	a.first_s = minf(float(a.first_s), sec)
	a.last_s = maxf(float(a.last_s), sec)

func add_event(a: Dictionary, ev: Dictionary, run, prim: String) -> void:
	match String(ev.type):
		"death": a.kills += 1
		"hero_hit":
			a.hits += 1
			a.dmg += float(ev.get("damage_raw", 0)) / maxf(1.0, float(run.hero.max_hp_raw))
		"enemy_attack": a.attacks += 1
		"hit":
			if String(ev.get("skill_id", "")) == prim: a.prim_hits += 1
		"item_drop":
			a.drops += 1
			if ev.has("source"):
				var src := String(ev.source)
				a.drops_by_source[src] = int(a.drops_by_source.get(src, 0)) + 1
			else:
				a.drops_nosrc += 1
		"wave_crest": a.waves += 1
		_:
			var t := String(ev.type)
			if t.begins_with("ritual") or t.begins_with("chest") or t.begins_with("shrine") or t.begins_with("trial") or t == "lull_started" or t == "carrier_kill":
				a.extras[t] = int(a.extras.get(t, 0)) + 1

func beat_name_by_time(sec: float) -> String:
	for b in BEATS:
		if sec < float(b.to): return String(b.name)
	return String(BEATS[BEATS.size() - 1].name)

# ---------- one run ----------
func play(seed_: int, prim: String) -> Dictionary:
	var run = Core.new()
	var pilot = Pilot.new()
	pilot.run = run
	run.first_boss_kill = true
	if rhythm_on:
		var doc = JSON.parse_string(FileAccess.get_file_as_string("res://chapter1/data/combat_tuning.json"))
		doc.rhythm.enabled = true
		doc.rhythm.trial.enabled = true
		# D15 O-1: the run opening comes with the rhythm in a trial run (`--chapter1-trial=...,rhythm`), so it does here.
		if doc.rhythm.has("opening"): doc.rhythm.opening.enabled = true
		if not run.set_tuning(doc):
			push_error("measure_rhythm: rhythm document rejected %s" % str(run.errors))
			return {}
	if spells_on:
		var spells_doc = JSON.parse_string(FileAccess.get_file_as_string("res://chapter1/data/run_spells.json"))
		spells_doc.enabled = true
		if not run.set_run_spells(spells_doc):
			push_error("measure_rhythm: spells document rejected %s" % str(run.errors))
			return {}
	if descent_policy != "":
		var descent_doc = JSON.parse_string(FileAccess.get_file_as_string("res://chapter1/data/descent.json"))
		descent_doc.enabled = true
		if not run.set_descent(descent_doc):
			push_error("measure_rhythm: descent document rejected %s" % str(run.errors))
			return {}
	if not run.start(seed_, prim):
		push_error("measure_rhythm: start failed %s" % str(run.errors))
		return {}
	var bins: Dictionary = {}
	var beats: Dictionary = {}
	var beat_order: Array = []
	var zones: Dictionary = {}
	var marks: Array = []
	var seen_sel := 0
	var last_seq := -1
	var last_tick: int = int(run.tick)
	var last_dropped := 0
	var event_beats := false
	var cur_beat := "(시작 전)"
	var guard := 0
	var all_types: Dictionary = {}
	var level_first := -1.0
	var descent_ends: Array = []
	while run.mode not in ["victory", "defeat"] and guard < 12 * 60 * 60 and (stop_s <= 0.0 or float(run.tick) < stop_s * 60.0):
		var mv: Vector2 = pilot.decide()
		var called_events: Array = DescentPolicy.use(run, descent_policy) if descent_policy != "" else []
		run.step(mv)
		guard += 1
		var adv: int = int(run.tick) - last_tick
		last_tick = int(run.tick)
		var sec: float = float(run.tick) / 60.0
		var zname := "zone%d" % int(run.zone)
		# events (by seq so a mode that does not advance the tick is never double counted)
		for ev in called_events + run.events:
			if int(ev.seq) <= last_seq: continue
			last_seq = int(ev.seq)
			all_types[String(ev.type)] = int(all_types.get(String(ev.type), 0)) + 1
			var esec: float = float(ev.tick) / 60.0
			if String(ev.type) == "beat_started":
				event_beats = true
				cur_beat = str(ev.get("id", ev.get("beat", ev.get("name", "beat%d" % beat_order.size()))))
				cur_beat = String(BEAT_NAMES.get(cur_beat, cur_beat))
			match String(ev.type):
				"gate_opened": marks.append("%.0fs gate%d" % [esec, int(ev.get("zone", 0))])
				"chapter_champion": marks.append("%.0fs champ%d" % [esec, int(ev.get("zone", 0))])
				"zone_entered": marks.append("%.0fs enter%d" % [esec, int(ev.get("zone", 0))])
				"beat_started": marks.append("%.0fs beat:%s" % [esec, cur_beat])
				"opening_step": marks.append("%.1fs open:%s" % [esec, String(ev.get("id", ""))])
				"opening_end": marks.append("%.1fs open:end" % esec)
				"descent_ready": marks.append("%.0fs descent ready" % esec)
				"descent_called": marks.append("%.0fs descent used" % esec)
				"descent_end": descent_ends.append({"tick": int(ev.tick), "kills": int(ev.kills), "strong_hits": int(ev.strong_hits), "strong_damage_raw": int(ev.strong_damage_raw), "marks_taken": int(ev.marks_taken), "refund": int(ev.refund)})
				"level_choice":
					if level_first < 0.0:
						level_first = esec
						marks.append("%.1fs first level-up" % esec)
			var accs := [bin_acc(bins, esec),
				get_beat(beats, beat_order, cur_beat if event_beats else beat_name_by_time(esec), esec),
				get_acc(zones, zname, zname, esec)]
			for a in accs:
				touch(a, esec)
				add_event(a, ev, run, prim)
		# per-step accounting
		var dropped_now := int(run.metrics.get("events_dropped", 0))
		var bn := cur_beat if event_beats else beat_name_by_time(sec)
		var step_accs := [bin_acc(bins, sec),
			get_beat(beats, beat_order, bn, sec), get_acc(zones, zname, zname, sec)]
		for a in step_accs:
			touch(a, sec)
			a.ticks += maxi(0, adv)
			a.events_dropped += dropped_now - last_dropped
			var n: int = run.alive_count()
			a.alive_max = maxi(int(a.alive_max), n)
			if adv > 0 and int(run.tick) % 6 == 0: a.alive.append(n)
		last_dropped = dropped_now
		while seen_sel < pilot.selections.size():
			var sel: Dictionary = pilot.selections[seen_sel]
			seen_sel += 1
			var ssec: float = float(int(sel.tick)) / 60.0
			var gbn := cur_beat if event_beats else beat_name_by_time(ssec)
			for a in [bin_acc(bins, ssec), get_beat(beats, beat_order, gbn, ssec), get_acc(zones, zname, zname, ssec)]:
				a.grace += 1
				a.grace_times.append(snappedf(ssec, 0.1))
	var secs: float = float(run.tick) / 60.0
	var bin_list: Array = []
	var bkeys := bins.keys()
	bkeys.sort_custom(func(x, y): return int(x) < int(y))
	for k in bkeys:
		var m := finalize(bins[k])
		if float(m.secs) < 0.5: continue
		bin_list.append(m)
	var beat_list: Array = []
	for n in beat_order:
		var m := finalize(beats[n])
		m.check = check_beat(String(n), m, bin_list)
		beat_list.append(m)
	var zone_list: Array = []
	var zkeys := zones.keys()
	zkeys.sort()
	for k in zkeys: zone_list.append(finalize(zones[k]))
	# run summary
	var times: Array = []
	for sel in pilot.selections: times.append(float(int(sel.tick)) / 60.0)
	var longest_gap := 0.0
	for i in range(1, times.size()): longest_gap = maxf(longest_gap, float(times[i]) - float(times[i - 1]))
	var first75 := 0
	for t in times:
		if float(t) <= 75.0: first75 += 1
	var worst: Dictionary = {}
	for b in bin_list:
		if worst.is_empty() or int(b.hits) > int(worst.hits) or (int(b.hits) == int(worst.hits) and float(b.dmg) > float(worst.dmg)): worst = b
	var hit_total := 0
	for b in bin_list: hit_total += int(b.hits)
	var summary := {"secs": snappedf(secs, 0.1), "mode": String(run.mode), "kills": int(run.kills), "level": int(run.growth.snapshot().level),
		"grace_count": times.size(), "grace_times": times.map(func(t): return snappedf(t, 0.1)), "grace_first_s": (snappedf(times[0], 0.1) if times.size() > 0 else -1.0),
		"grace_longest_gap_s": snappedf(longest_gap, 0.1), "grace_last_to_end_s": (snappedf(secs - float(times[times.size() - 1]), 0.1) if times.size() > 0 else -1.0),
		"grace_first75": first75, "level_first_s": snappedf(level_first, 0.1), "worst_bin": String(worst.get("label", "")), "worst_bin_hits": int(worst.get("hits", 0)), "worst_bin_dmg": worst.get("dmg", 0.0),
		"hits_total": hit_total, "events_dropped": int(run.metrics.get("events_dropped", 0)), "event_types": all_types}
	return {"primary": prim.trim_prefix("chapter1.skill."), "seed": seed_, "mode": String(run.mode), "secs": snappedf(secs, 0.1), "kills": int(run.kills),
		"beat_source": "beat_started event" if event_beats else "time table (A2)", "marks": marks, "summary": summary,
		"descent": {"policy": descent_policy, "metrics": run.metrics.get("descent", {}).duplicate(true), "ends": descent_ends, "view": run.descent_view()},
		"bins": bin_list, "beats": beat_list, "zones": zone_list}

func bin_acc(d: Dictionary, sec: float) -> Dictionary:
	var k := int(sec / bin_s)
	return get_acc(d, str(k), "%d-%ds" % [int(k * bin_s), int((k + 1) * bin_s)], float(k) * bin_s)

func get_acc(d: Dictionary, key: String, label: String, from_s: float) -> Dictionary:
	if not d.has(key): d[key] = new_acc(label, from_s)
	return d[key]

func get_beat(d: Dictionary, order: Array, name: String, sec: float) -> Dictionary:
	if not d.has(name):
		d[name] = new_acc(name, sec)
		order.append(name)
	return d[name]

func finalize(a: Dictionary) -> Dictionary:
	var secs := float(a.ticks) / 60.0
	var al: Array = a.alive.duplicate()
	al.sort()
	var avg := 0.0
	for v in al: avg += float(v)
	if al.size() > 0: avg /= float(al.size())
	var p90 := 0.0
	if al.size() > 0: p90 = float(al[clampi(int(ceil(0.9 * al.size())) - 1, 0, al.size() - 1)])
	var per_min := 60.0 / maxf(secs, 0.001)
	var src_note := "event" if a.drops_by_source.size() > 0 and int(a.drops_nosrc) == 0 else ("출처 없음" if int(a.drops) > 0 else "-")
	return {"label": a.label, "from_s": snappedf(float(a.first_s), 0.1), "to_s": snappedf(float(a.last_s), 0.1), "secs": snappedf(secs, 0.1),
		"kills": int(a.kills), "kpm": snappedf(float(a.kills) * per_min, 0.1), "alive_avg": snappedf(avg, 0.1), "alive_p90": p90, "alive_max": int(a.alive_max),
		"hits": int(a.hits), "hits_pm": snappedf(float(a.hits) * per_min, 0.1), "dmg": snappedf(float(a.dmg), 0.001),
		"dmg30": snappedf(float(a.dmg) / maxf(secs, 0.001) * 30.0, 0.001), "attacks": int(a.attacks),
		"prim_hits": int(a.prim_hits), "prim_hits_per_kill": snappedf(float(a.prim_hits) / maxf(1.0, float(a.kills)), 0.01),
		"grace": int(a.grace), "grace_times": a.grace_times, "drops": int(a.drops), "drops_by_source": a.drops_by_source, "drops_source": src_note,
		"wave_crests": int(a.waves), "extras": a.extras, "events_dropped": int(a.events_dropped), "reached": int(a.ticks) >= MIN_TICKS}

func target_of(name: String) -> Dictionary:
	for b in BEATS:
		if String(b.name) == name: return b
	return {}

func range_verdict(v: float, t) -> String:
	if t == null: return "-"
	if t is Array:
		if v < float(t[0]): return "낮음"
		if v > float(t[1]): return "높음"
		return "안"
	return "안" if v <= float(t) else "높음"

func check_beat(name: String, m: Dictionary, bin_list: Array) -> Dictionary:
	var t := target_of(name)
	if t.is_empty() or not bool(m.reached): return {}
	var worst30 := 0.0
	for b in bin_list:
		if float(b.from_s) >= float(m.from_s) - 0.01 and float(b.from_s) < float(m.to_s) and float(b.secs) >= 10.0: worst30 = maxf(worst30, float(b.dmg30))
	var vals := {"alive_avg": m.alive_avg, "alive_max": m.alive_max, "kpm": m.kpm, "hits_pm": m.hits_pm, "dmg30": snappedf(worst30, 0.001)}
	var out := {}
	for k in METRICS:
		out[k] = {"value": vals[k], "target": t[k], "verdict": range_verdict(float(vals[k]), t[k])}
	return out

# ---------- cross-run ----------
func median(arr: Array) -> float:
	if arr.is_empty(): return 0.0
	var s := arr.duplicate()
	s.sort()
	var n := s.size()
	return float(s[n / 2]) if n % 2 == 1 else (float(s[n / 2 - 1]) + float(s[n / 2])) * 0.5

func cross_summary(runs: Array) -> Dictionary:
	var out := {}
	for b in BEATS:
		var name := String(b.name)
		var row := {"runs_reached": 0, "metrics": {}}
		var per: Dictionary = {}
		for k in METRICS: per[k] = {"vals": [], "inside": 0, "low": 0, "high": 0}
		for r in runs:
			for bm in r.beats:
				if String(bm.label) != name or bm.check.is_empty(): continue
				row.runs_reached += 1
				for k in METRICS:
					var c: Dictionary = bm.check[k]
					per[k].vals.append(float(c.value))
					match String(c.verdict):
						"안": per[k].inside += 1
						"낮음": per[k].low += 1
						"높음": per[k].high += 1
		for k in METRICS:
			var v: Array = per[k].vals
			var mn := 0.0
			var mx := 0.0
			if v.size() > 0:
				mn = float(v.min())
				mx = float(v.max())
			row.metrics[k] = {"target": b[k], "median": snappedf(median(v), 0.01), "min": mn, "max": mx, "inside": per[k].inside, "low": per[k].low, "high": per[k].high}
		out[name] = row
	# rhythm ordering: kills per minute must rise 기 < 승1 < 승2 < 전A (D11 G1)
	var ordered := 0
	for r in runs:
		var kp: Array = []
		for n in ["기", "승1", "승2", "전A"]:
			for bm in r.beats:
				if String(bm.label) == n and bool(bm.reached): kp.append(float(bm.kpm))
		if kp.size() == 4 and kp[0] < kp[1] and kp[1] < kp[2] and kp[2] < kp[3]: ordered += 1
	out["kpm_ordered_runs"] = ordered
	out["run_count"] = runs.size()
	return out

# ---------- printing ----------
func print_run(r: Dictionary) -> void:
	var s: Dictionary = r.summary
	print("RUN %s seed=%d mode=%s secs=%.1f kills=%d level=%d  beats by: %s" % [r.primary, r.seed, r.mode, r.secs, r.kills, s.level, r.beat_source])
	print("  marks: ", ", ".join(PackedStringArray(r.marks)))
	if r.descent.policy != "":
		var dm: Dictionary = r.descent.metrics
		var dk := 0
		for d in r.descent.ends: dk += int(d.kills)
		print("  descent[%s]: uses=%d ready_at=%s used_at=%s kills_by_descent=%d gauge_in=%d wasted=%d refunded=%d strong_dmg_raw=%d" % [r.descent.policy, int(dm.get("uses", 0)),
			str(dm.get("ready_ticks", []).map(func(t): return snappedf(float(t) / 60.0, 0.1))), str(dm.get("call_ticks", []).map(func(t): return snappedf(float(t) / 60.0, 0.1))), dk,
			int(dm.get("gauge_in", 0)), int(dm.get("wasted", 0)), int(dm.get("refunded", 0)), int(dm.get("strong_damage_raw", 0))])
	print("  grace: n=%d first=%.1fs longest_gap=%.1fs last_to_end=%.1fs first75=%d at %s" % [s.grace_count, s.grace_first_s, s.grace_longest_gap_s, s.grace_last_to_end_s, s.grace_first75, str(s.grace_times)])
	print("  worst bin: %s hits=%d dmg/maxhp=%.2f   hits_total=%d events_dropped=%d" % [s.worst_bin, s.worst_bin_hits, float(s.worst_bin_dmg), s.hits_total, s.events_dropped])
	print("  bin       | kills kpm  | alive avg p90 max | hits dmg  | atk  | pHit/kill | grace | drops(src)        | dropped_ev")
	for b in r.bins:
		print("  %-9s | %5d %5.0f | %5.1f %4.0f %3d | %4d %4.2f | %4d | %5.2f | %d | %3d (%s%s) | %d" % [b.label, b.kills, b.kpm, b.alive_avg, b.alive_p90, b.alive_max, b.hits, b.dmg, b.attacks, b.prim_hits_per_kill, b.grace, b.drops,
			b.drops_source, (" " + str(b.drops_by_source)) if b.drops_by_source.size() > 0 else "", b.events_dropped])
	print("  beat      | secs  kpm  | alive avg p90 max | hits/min dmg30max | verdict(alive_avg alive_max kpm hits_pm dmg30)")
	for b in r.beats:
		var v := "미도달/목표 없음"
		if not b.check.is_empty():
			var parts: Array = []
			for k in METRICS: parts.append("%s=%s" % [k, b.check[k].verdict])
			v = " ".join(PackedStringArray(parts))
		print("  %-9s | %5.1f %5.0f | %5.1f %4.0f %3d | %5.1f   %4.2f | %s" % [b.label, b.secs, b.kpm, b.alive_avg, b.alive_p90, b.alive_max, b.hits_pm, (b.check.dmg30.value if not b.check.is_empty() else b.dmg30), v])

func print_cross(c: Dictionary) -> void:
	print("CROSS beats (target vs value across runs that reached the beat; inside/low/high counts)")
	for b in BEATS:
		var row: Dictionary = c[String(b.name)]
		print("  %s runs=%d" % [b.name, row.runs_reached])
		for k in METRICS:
			var m: Dictionary = row.metrics[k]
			print("    %-9s target=%s median=%s min=%s max=%s in=%d low=%d high=%d" % [k, str(m.target), str(m.median), str(m.min), str(m.max), m.inside, m.low, m.high])
	print("CROSS kpm strictly rising 기<승1<승2<전A: %d/%d runs" % [c.kpm_ordered_runs, c.run_count])
