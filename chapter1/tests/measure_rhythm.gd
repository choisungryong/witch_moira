extends SceneTree
## Difficulty-rhythm meter (D11 G2). Plays whole pilot runs on the real core and only READS core state/events.
## It never calls anything that draws random numbers or mutates the core besides the normal step(); it does not load
## chapter_profile.gd. Output goes to stdout (tables) and --out (JSON, only under _local/).
##   python tools/dev/godot.py --headless --path . --script res://chapter1/tests/measure_rhythm.gd -- --seeds=11,12,13 --primaries=ember,frost,arc --out=_local/w0/rhythm.json --bin=30
## D19 V0 (read-only; with none of these the printed output is unchanged): --thirds (a table per third of the run + sweep counts: casts, kills per cast, 0.5 s windows with
## >= 10 kills, screen clears, one-shot share of walkers, lifetimes by kind, big enemies appear -> death), --tuning=_local/x.json (a tuning copy, see tools/dev/tuning_copy.py),
## --descent-doc=_local/y.json, --policy=synergy|random|... (the grace pick of sim_builds.gd). Example with a copy and the synergy pick:
##   python tools/dev/godot.py --headless --path . --script res://chapter1/tests/measure_rhythm.gd -- --thirds --tuning=_local/d19/v0/wd_1.json --policy=synergy --out=_local/d19/v0/x.json
## D22 R0-A (read-only, only this tool; with none of these the printed output of a rhythm-off run is unchanged): --no-trial-arena (--rhythm-on does not switch the 45 s hold on, the same run as the app's
## `--chapter1-trial=rhythm`), --stand (the pilot's movement is zeroed; casting and the grace pick stay the pilot's; prints when and in which beat / opening step the hero fell),
## --targets=d22 (the D22 3.4 table, with the opening as its own beat), and with --thirds: wave-crest / lull ratios, grace-density figures, and the card kinds offered after level 12.
## D23 T1 appendix A.6 (2), layer 2 (with none of these the output is unchanged): --gear-kit=none,kit.f2.@.r3,kit.d1_end,... wears the kit from the START of every run (core.import_starting_gear, memory only; the
##   data files and the saves are untouched) and prints a table against the bare hero ("none", same seed): damage taken (whole run, worst 60 s window), guardian / boss kill time, defeats, run length, with the
##   A.5 verdicts. "@" in a kit name = the primary's series (ember / frost / arc). Kits come from tests/fixtures/gear_kits.json plus --kits-file=_local/..json (the F2 kits of sim_loot.gd --wear). The kit order is
##   the outer loop, so a run list is kit by kit; the printed per-run lines are short in this mode.
## D-run-curve RC-A (read-only, this tool only; with no --rc the stdout and the JSON are byte-for-byte the same as before): --rc adds a per-run "rc" block to the JSON (no extra stdout): the raw
##   records tools/dev/rc_read.py judges the RC-T table from (core events with ticks: beat_started / wave_crest / gate_opened / chapter_champion / potion_pickup / item_drop /
##   descent_ready / descent_called / level_choice, and a potion drink read from the potion count falling; the hero's lowest life ratio and the potion count per second; every offer with its card ids and the state the 4.3 crisis rule reads;
##   the picks). It only reads core state and events; nothing here draws a random number or writes the core.
## Grouping: fixed-size time bins (--bin seconds), D11 A2 beats, and zones. Beats are grouped by `beat_started` core
## events when the core emits them; otherwise by the time boundaries in BEATS (the output says which).
const Core = preload("res://chapter1/core/chapter_core.gd")
const Pilot = preload("res://chapter1/core/chapter_pilot.gd")
const DescentPolicy = preload("res://chapter1/tests/descent_policy.gd")
const TrialDocs = preload("res://chapter1/tests/support/trial_docs.gd")
const GracePolicies = preload("res://chapter1/tests/support/grace_policies.gd")
const KitDocs = preload("res://chapter1/tests/support/kit_docs.gd")
const KitPolicies = preload("res://chapter1/tests/support/kit_policies.gd")

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
## D22 3.4 table (--targets=d22), pilot-centre values [hypothesis]. The opening is its own beat; "기" starts after it. from/to are the time boundaries
## used when the core has no beat_started event (the guardian windows are folded into the neighbours). alive_max here is the upper bound only (the cap);
## the crest / lull rows are checked against crest_min (crest peak share of the cap, 10 s after a crest), lull_max (alive at the end of a lull / cap) and
## crest_count_max (the absolute peak, for the early beats). "stand": what the standing hero is expected to do ("survive" / "die_here").
const BEATS_D22 := [
	{"name": "도입", "from": 0.0, "to": 65.0, "alive_avg": [0, 6], "alive_max": 12, "kpm": [10, 60], "hits_pm": [0, 0], "dmg30": 0.05, "crest_count_max": 12, "stand": "survive"},
	{"name": "기", "from": 65.0, "to": 105.0, "alive_avg": [6, 15], "alive_max": 20, "kpm": [100, 200], "hits_pm": [0, 2], "dmg30": 0.10, "crest_count_max": 20, "stand": "survive"},
	{"name": "승1", "from": 105.0, "to": 172.0, "alive_avg": [12, 25], "alive_max": 45, "kpm": [300, 420], "hits_pm": [2, 6], "dmg30": 0.30, "crest_min": 0.75, "lull_max": 0.30, "stand": "survive"},
	{"name": "승2", "from": 172.0, "to": 302.0, "alive_avg": [18, 35], "alive_max": 75, "kpm": [450, 650], "hits_pm": [4, 9], "dmg30": 0.45, "crest_min": 0.70, "lull_max": 0.30, "stand": "die_here"},
	{"name": "전A", "from": 302.0, "to": 380.0, "alive_avg": [30, 55], "alive_max": 100, "kpm": [600, 900], "hits_pm": [6, 12], "dmg30": 0.60, "crest_min": 0.75, "lull_max": 0.40},
	{"name": "전C", "from": 380.0, "to": 1.0e9, "alive_avg": [10, 25], "alive_max": null, "kpm": null, "hits_pm": null, "dmg30": null},
]
const OPENING_NAME := "도입"
const GearKits = preload("res://chapter1/tests/support/gear_kits.gd")
const LootData = preload("res://chapter1/core/loot.gd")
## D23 T1 appendix A.5, layer 2 [hypothesis]: damage taken (60 s window) and guardian / boss kill time against the bare hero, defeats 0. kill_floor = "too easy" below it.
const A5_ROWS := {
	"r3": {"label": "r3 / d1_start", "dmg": [0.65, 0.85], "kill": [0.70, 0.85], "kill_floor": 0.70},
	"r15": {"label": "r15 / d1_end", "dmg": [0.40, 0.65], "kill": [0.50, 0.70], "kill_floor": 0.50},
	"r30": {"label": "r30 / d2_mid", "dmg": null, "kill": [0.40, 1.0], "kill_floor": 0.40},
}
const CREST_AFTER_TICKS := 600        ## the peak of the alive count is taken over 10 s after a wave_crest
const BEAT_NAMES := {"gi": "기", "seung1": "승1", "seung2": "승2", "jeon_a": "전A", "trial": "전B", "boss": "전C"}
const METRICS := ["alive_avg", "alive_max", "kpm", "hits_pm", "dmg30"]
const MIN_TICKS := 300

var bin_s := 30.0
## D22 R0-A switches (see the header).
var no_trial_arena := false
var stand_on := false
## D22 CB-R1 (N94, N97), this tool only: --stand-from=<beat name, e.g. 승2> = the hero stands still from the first zone_entered after that beat started (casting and the grace pick stay the pilot's);
## --move-bps=N = the pilot's movement vector is scaled by N/10000 (5000 = half speed, a stand-in for a slower human). Without both the output is unchanged.
var stand_from := ""
var stand_from_id := ""
var move_bps := 10000
## --xp-trace=N (read-only, this tool): every N seconds the run's xp, level and live enemy count go into the run JSON ("xp_trace": [[s, xp, level, alive]]) and one line "XPTRACE" is printed (to see why a grace gap is long).
var xp_trace_s := 0.0
var targets_name := ""
var targets: Array = BEATS
var gear_kit_names: Array = []
var kits_file := ""
var cur_kit := ""
var kit_fixture: Dictionary = {}
var kit_loot = null
## --rhythm-on: test switch. The shipped document is read, rhythm.enabled and trial.enabled are set in memory only.
var rhythm_on := false
## --stop-s=N: end every run after N seconds (a short look at the first minutes, e.g. the run opening with --bin=10).
var stop_s := 0.0
## --descent=off|now|hold|panic|crest|boss|boss_break|boss_phase (D24: crest = call when the screen is full, boss = call when the boss is on the screen; BF-C: boss_break = in the finale's first break that finds it ready, boss_phase = in the finale's first phase): switch the descent on in memory (descent.json stays off) and let the bot use it by that rule (D15 A6.5).
## "off" counts the gauge but never calls. --spells-on: the in-run spell composition on in memory (the pilot picks its own cards).
var descent_policy := ""
var spells_on := false
## ET-A (D-element-trees 8.2): --element-kit turns the element kit of the run's element on in memory (the files stay off); --kit-tree=none|all|A18,A16 which cards the
## permanent tree opens (default all); --kit-policy=link|main|random how the pilot's card pick is replaced (default link); --kit-seed=N changes only the random policy's stream.
## With none of them nothing here runs and the output is as before.
var element_kit_on := false
var kit_tree: Variant = "all"
var kit_policy := "link"
var kit_seed := 0
## ET-B: --kit-doc=_local/..json hands the kit a full element_kit document of this tool's own (a copy of the shipped file with other values) instead of the shipped one; absent = the shipped file.
var kit_doc_path := ""
## --extras-on: the strong elites (D13 W4-a) and the guarded shrine / chest (W5-a) on in memory (the files stay off).
## --pilot-extras: this tool only (chapter_pilot.gd is untouched): the pilot's step is replaced by a walk to a freed shrine, or to a locked
## site within 20 m when the run is in a lull (or has no rhythm), or while its guard is already fighting; it stands still next to the guard.
var extras_on := false
var pilot_extras := false
## D19 V0 (all read-only; none of them changes what the default output prints):
## --tuning=_local/x.json     a tuning copy (a whole combat_tuning.json) read instead of the shipped one (make it with a tool, never edit data/).
## --descent-doc=_local/y.json  the same for descent.json (used with --descent=...; "enabled" is set true in memory).
## --policy=NAME              the grace pick of sim_builds.gd (support/grace_policies.gd; "synergy" = synergy_now). Not given: the pilot's own pick.
## --thirds                   print the thirds table (each run cut in three by its length), the sweep counts and the big enemies.
var tuning_path := ""
var descent_doc_path := ""
var policy_name := ""
var thirds_on := false
## --hurt-by-source (GM-A): per run, the damage taken split by source (whole run and the worst 60 s window), hits, heavy hits and grazes, into the JSON "hurt". Read-only; absent = the output is unchanged.
var hurt_on := false
## --rc (RC-A): the raw records of the run-curve meter. `rc` is the record of the run being played (reset in play()).
var rc_on := false
var rc: Dictionary = {}
## The sweep counts are always collected into the JSON ("sweep" per run); they are printed only with --thirds.
const SWEEP_WINDOW_TICKS := 30        ## "0.5 s" window
const SWEEP_MIN_KILLS := 10
const CLEAR_HIGH_SHARE := 0.5         ## screen clear (D19 5.2): alive >= 50% of the beat's cap ...
const CLEAR_LOW_SHARE := 0.15         ## ... then <= 15% of it ...
const CLEAR_WITHIN_TICKS := 360       ## ... within 6 s.
const ORDINARY := ["walker", "ranged", "charger"]

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
		elif arg.begins_with("--tuning="): tuning_path = arg.trim_prefix("--tuning=")
		elif arg.begins_with("--descent-doc="): descent_doc_path = arg.trim_prefix("--descent-doc=")
		elif arg.begins_with("--policy="):
			policy_name = arg.trim_prefix("--policy=")
			if policy_name == "synergy": policy_name = "synergy_now"
			if not policy_name in GracePolicies.ALL_POLICIES:
				push_error("measure_rhythm: --policy must be one of %s (or synergy)" % str(GracePolicies.ALL_POLICIES))
				quit(1)
				return
		elif arg == "--thirds": thirds_on = true
		elif arg == "--hurt-by-source": hurt_on = true
		elif arg == "--rc": rc_on = true
		elif arg == "--no-trial-arena": no_trial_arena = true
		elif arg == "--stand": stand_on = true
		elif arg.begins_with("--stand-from="):
			stand_from = arg.trim_prefix("--stand-from=")
			for bid in BEAT_NAMES:
				if String(BEAT_NAMES[bid]) == stand_from: stand_from_id = String(bid)
			if stand_from_id == "":
				push_error("measure_rhythm: --stand-from must be a beat name of %s (got %s)" % [str(BEAT_NAMES.values()), stand_from])
				quit(1)
				return
		elif arg.begins_with("--xp-trace="): xp_trace_s = maxf(1.0, float(arg.trim_prefix("--xp-trace=")))
		elif arg.begins_with("--move-bps="):
			move_bps = clampi(int(arg.trim_prefix("--move-bps=")), 0, 10000)
		elif arg.begins_with("--gear-kit="):
			gear_kit_names = []
			for part in arg.trim_prefix("--gear-kit=").split(","): gear_kit_names.append(String(part))
		elif arg.begins_with("--kits-file="): kits_file = arg.trim_prefix("--kits-file=")
		elif arg.begins_with("--targets="):
			targets_name = arg.trim_prefix("--targets=")
			if targets_name != "d22":
				push_error("measure_rhythm: --targets must be d22 (the default is the D11 A2 table)")
				quit(1)
				return
			targets = BEATS_D22
		elif arg == "--spells-on": spells_on = true
		elif arg == "--element-kit": element_kit_on = true
		elif arg.begins_with("--kit-tree="):
			var tree_arg := arg.trim_prefix("--kit-tree=")
			kit_tree = tree_arg if tree_arg in ["none", "all"] else Array(tree_arg.split(",", false))
		elif arg.begins_with("--kit-policy="):
			kit_policy = arg.trim_prefix("--kit-policy=")
			if not KitPolicies.valid(kit_policy):
				push_error("measure_rhythm: --kit-policy must be one of %s" % str(KitPolicies.ALL))
				quit(1)
				return
		elif arg.begins_with("--kit-seed="): kit_seed = int(arg.trim_prefix("--kit-seed="))
		elif arg.begins_with("--kit-doc="):
			kit_doc_path = arg.trim_prefix("--kit-doc=")
			if not kit_doc_path.begins_with("_local/") or kit_doc_path.contains("..") or kit_doc_path.contains(":"):
				push_error("measure_rhythm: --kit-doc must be a relative path under _local/ (got %s)" % kit_doc_path)
				quit(1)
				return
		elif arg == "--extras-on": extras_on = true
		elif arg == "--pilot-extras": pilot_extras = true
		elif arg.begins_with("--bin="): bin_s = maxf(5.0, float(arg.trim_prefix("--bin=")))
	if not out.begins_with("_local/") or out.contains("..") or out.contains(":") or out.begins_with("/"):
		push_error("measure_rhythm: --out must be a relative path under _local/ (got %s)" % out)
		quit(1)
		return
	for p in [tuning_path, descent_doc_path]:
		if p != "" and (not String(p).begins_with("_local/") or String(p).contains("..") or String(p).contains(":")):
			push_error("measure_rhythm: --tuning / --descent-doc must be a relative path under _local/ (got %s)" % p)
			quit(1)
			return
	var tuning_doc: Dictionary = {}
	if tuning_path != "":
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://" + tuning_path)))
		if not parsed is Dictionary:
			push_error("measure_rhythm: cannot read the tuning copy %s" % tuning_path)
			quit(1)
			return
		tuning_doc = parsed
	var descent_doc: Dictionary = {}
	if descent_doc_path != "":
		var parsed2 = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://" + descent_doc_path)))
		if not parsed2 is Dictionary:
			push_error("measure_rhythm: cannot read the descent copy %s" % descent_doc_path)
			quit(1)
			return
		descent_doc = parsed2
	var gear_mode := not gear_kit_names.is_empty()
	if gear_mode:
		kit_fixture = GearKits.load_fixture()
		if kits_file != "":
			if not kits_file.begins_with("_local/") or kits_file.contains("..") or kits_file.contains(":"):
				push_error("measure_rhythm: --kits-file must be a relative path under _local/ (got %s)" % kits_file)
				quit(1)
				return
			var extra := GearKits.load_fixture("res://" + kits_file)
			for k in extra.get("kits", {}): kit_fixture.kits[k] = extra.kits[k]
		kit_loot = LootData.new()
		if kit_fixture.is_empty() or not kit_loot.load_file():
			push_error("measure_rhythm: gear kit fixture or loot data unreadable")
			quit(1)
			return
	var kit_list: Array = gear_kit_names if gear_mode else [""]
	var runs: Array = []
	for kit in kit_list:
		for prim in prims:
			for s in seeds:
				cur_kit = String(kit)
				var r := play(int(s), String(prim), tuning_doc, descent_doc)
				if r.is_empty():
					quit(2)
					return
				runs.append(r)
				if gear_mode:
					print(gear_line(r))
					continue
				print_run(r)
				if thirds_on: print_sweep_run(r)
	var cross := cross_summary(runs)
	if gear_mode:
		print_gear_table(runs)
	else:
		print_cross(cross)
	if descent_policy != "" and not gear_mode: print_descent_cross(runs)
	if stand_on and not gear_mode: print_stand_cross(runs)
	if stand_from != "" and not gear_mode: print_stand_from_cross(runs)
	if thirds_on and not gear_mode: print_thirds(runs)
	var result := {"targets": (targets_name if targets_name != "" else "d11-a2"), "stand": stand_on, "no_trial_arena": no_trial_arena, "crest_lull": crest_lull_summary(runs), "descent_cross": (descent_cross(runs) if descent_policy != "" else {}), "tuning": tuning_path, "descent_doc": descent_doc_path, "policy": policy_name, "bin_s": bin_s, "seeds": seeds, "primaries": prims, "runs": runs, "cross": cross,
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
	for b in targets:
		if sec < float(b.to): return String(b.name)
	return String(targets[targets.size() - 1].name)

# ---------- one run ----------
func play(seed_: int, prim: String, tuning_copy: Dictionary = {}, descent_copy: Dictionary = {}) -> Dictionary:
	var run = Core.new()
	var pilot = Pilot.new()
	pilot.run = run
	run.first_boss_kill = true
	if rhythm_on or extras_on or not tuning_copy.is_empty():
		var doc = tuning_copy.duplicate(true) if not tuning_copy.is_empty() else JSON.parse_string(FileAccess.get_file_as_string("res://chapter1/data/combat_tuning.json"))
		if rhythm_on:
			doc.rhythm.enabled = true
			if not no_trial_arena: doc.rhythm.trial.enabled = true
			# D15 O-1: the run opening comes with the rhythm in a trial run (`--chapter1-trial=...,rhythm`), so it does here.
			if doc.rhythm.has("opening"): doc.rhythm.opening.enabled = true
		if extras_on:
			doc.elites.enabled = true
			doc.extras.enabled = true
		if not run.set_tuning(doc):
			push_error("measure_rhythm: rhythm document rejected %s" % str(run.errors))
			return {}
	if spells_on:
		var spells_problem := TrialDocs.enable_spells_problem(run)
		if not spells_problem.is_empty():
			push_error("measure_rhythm: " + spells_problem)
			return {}
	if element_kit_on:
		var element_problem := KitDocs.enable_kit_problem(run, kit_tree, [String(prim).get_slice(".", 2)], kit_doc_path)
		if not element_problem.is_empty():
			push_error("measure_rhythm: " + element_problem)
			return {}
	if descent_policy != "":
		if descent_copy.is_empty():
			var descent_problem := TrialDocs.enable_descent_problem(run)
			if not descent_problem.is_empty():
				push_error("measure_rhythm: " + descent_problem)
				return {}
		else:
			var ddoc: Dictionary = descent_copy.duplicate(true)
			ddoc["enabled"] = true
			if not run.set_descent(ddoc):
				push_error("measure_rhythm: descent copy refused " + str(run.errors))
				return {}
	if not run.start(seed_, prim):
		push_error("measure_rhythm: start failed %s" % str(run.errors))
		return {}
	if cur_kit != "" and cur_kit != "none":
		var kit_problem := install_kit(run, cur_kit, prim)
		if kit_problem != "":
			push_error("measure_rhythm: " + kit_problem)
			return {}
	if rc_on: rc = rc_new()
	var dmg_raw_s: Array = []
	var hurt_log: Array = []
	var volley_placed := 0
	var volley_shooters := {}
	var volley_beats := {}
	var volley_marked := {}   ## VR-B: id -> {"frozen": bool}; bodies seen carrying `volley` (the first-shot mark) after a placement, until they fire or die
	var volley_tally := {"marked": 0, "killed_before_fire": 0, "stopped_frozen": 0, "frozen_killed": 0}
	if hurt_on:
		for b in run.tuning.get("rhythm", {}).get("beats", []):
			if JSON.stringify(b).contains("\"volley\""): volley_beats[String(b.get("id", ""))] = true
	var policy_rng := RandomNumberGenerator.new()
	policy_rng.seed = (seed_ * 2654435761) ^ (GracePolicies.ALL_POLICIES.find(policy_name) * 40503 + 977)
	var kit_rng := RandomNumberGenerator.new()
	kit_rng.seed = (seed_ * 2654435761) ^ (kit_seed * 7919 + 4421)
	var kit_hands: Array = []
	var kit_picks: Array = []
	var sw := new_sweep(run)
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
	var descent_calls: Array = []
	var op_active := false
	var op_step_id := ""
	var boss_tick := -1
	var offers: Array = []
	var open_on: bool = bool(run.tuning.get("rhythm", {}).get("enabled", false)) and bool(run.tuning.get("rhythm", {}).get("opening", {}).get("enabled", false))
	var first_beat_id := ""
	var xp_trace: Array = []
	var sf := {"armed": false, "on": false, "start_s": -1.0, "zone": -1, "champs": {}, "last_hit": {}}
	if run.tuning.get("rhythm", {}).get("beats", []).size() > 0: first_beat_id = String(run.tuning.rhythm.beats[0].id)
	var ex := {"born": {}, "engaged": {}, "walk_in_s": [], "guard_fight_s": [], "guard_placed_s": [], "guard_unlocked_s": [], "taken_s": [], "chest_s": [], "expired": 0, "locked_expired": 0}
	while run.mode not in ["victory", "defeat"] and guard < 12 * 60 * 60 and (stop_s <= 0.0 or float(run.tick) < stop_s * 60.0):
		if policy_name != "" and policy_name != "pilot":
			# The same place as sim_builds.gd: the pick is made while the core waits in "choice", before the pilot sees it.
			var g2 := 0
			while run.mode == "choice" and g2 < 64:
				g2 += 1
				var offer: Dictionary = run.get_offer()
				var cards: Array = offer.cards
				note_offer(run, offers, offer)
				var chosen: Dictionary = cards[GracePolicies.pick(policy_name, cards, run.growth.snapshot(), policy_rng)]
				pilot.selections.append({"tick": run.tick, "id": chosen.id, "kind": chosen.kind})
				if not run.choose(offer.token, chosen.id):
					push_error("measure_rhythm: choice rejected %s" % str(run.errors))
					return {}
		if element_kit_on:
			# ET-A: the kit's cards are picked by the tool's policy, while the core waits in "choice" (the pilot would take its own order).
			var g3 := 0
			while run.mode == "choice" and g3 < 64:
				g3 += 1
				var kit_offer: Dictionary = run.get_offer()
				var hand: Array = kit_offer.cards
				note_offer(run, offers, kit_offer)
				var at := KitPolicies.pick(kit_policy, hand, String(prim).get_slice(".", 2), kit_rng)
				var hand_ids: Array = []
				for c in hand: hand_ids.append(String(c.id))
				kit_hands.append([int(run.tick), hand_ids])
				kit_picks.append([int(run.tick), String(hand[at].id)])
				pilot.selections.append({"tick": run.tick, "id": hand[at].id, "kind": hand[at].kind})
				if not run.choose(kit_offer.token, hand[at].id):
					push_error("measure_rhythm: kit choice rejected %s" % str(run.errors))
					return {}
		if run.mode == "choice": note_offer(run, offers, run.get_offer())
		var mv: Vector2 = pilot.decide()
		if move_bps != 10000: mv = mv * (float(move_bps) / 10000.0)
		if stand_on or bool(sf.on): mv = Vector2.ZERO
		if pilot_extras: mv = extras_move(run, mv)
		var called_events: Array = DescentPolicy.use(run, descent_policy) if descent_policy != "" else []
		run.step(mv)
		if rc_on: rc_tick(run)
		if hurt_on:
			for uid in run._hostile_src:
				var hs = run._hostile_src[uid]
				if String(hs.get("attack_id", "")) == "volley": volley_shooters[int(hs.id)] = true
			for vid in volley_marked.keys():
				var ve = run.enemies.get(int(vid))
				var vm: Dictionary = volley_marked[vid]
				if volley_shooters.has(int(vid)) or ve == null or int(ve.hp_raw) <= 0:
					# resolved: fired, or died / left with the mark still on
					volley_marked.erase(vid)
					volley_tally.marked += 1
					if bool(vm.frozen): volley_tally.stopped_frozen += 1
					if not volley_shooters.has(int(vid)):
						volley_tally.killed_before_fire += 1
						if bool(vm.frozen): volley_tally.frozen_killed += 1
				elif run.tick < int(ve.frozen_until): vm.frozen = true
		guard += 1
		if xp_trace_s > 0.0 and int(run.tick) % int(xp_trace_s * 60.0) == 0 and (xp_trace.is_empty() or int(xp_trace[xp_trace.size() - 1][0]) != int(int(run.tick) / 60)):
			var gs0: Dictionary = run.growth.snapshot()
			xp_trace.append([int(int(run.tick) / 60), int(gs0.xp), int(gs0.level), int(run.alive_count())])
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
			sweep_event(sw, ev, run, prim)
			if rc_on: rc_event(ev)
			if stand_from != "" or stand_on:
				match String(ev.type):
					"beat_started":
						if stand_from != "" and String(ev.get("id", "")) == stand_from_id: sf.armed = true
					"zone_entered":
						if bool(sf.armed) and not bool(sf.on):
							sf.on = true
							sf.start_s = snappedf(esec, 0.1)
							sf.zone = int(ev.get("zone", -1))
					"chapter_champion": sf.champs[int(ev.get("zone", -1))] = snappedf(esec, 0.1)
					"hero_hit": sf.last_hit = {"kind": String(ev.get("source_kind", "")), "attack": String(ev.get("attack_id", "")), "s": snappedf(esec, 0.1)}
			if String(ev.type) == "hero_hit":
				bump(dmg_raw_s, int(int(ev.tick) / 60), float(ev.get("damage_raw", 0)))
				if hurt_on: hurt_log.append(hurt_note(run, ev))
			if hurt_on and String(ev.type) == "wave_squad" and volley_beats.has(String(ev.get("beat", ""))):
				volley_placed += int(ev.get("count", 0))
				for eid in run.enemies:
					if run.enemies[eid].has("volley") and not volley_marked.has(int(eid)): volley_marked[int(eid)] = {"frozen": false}
			if extras_on: ex_event(ex, ev)
			if String(ev.type) == "beat_started":
				event_beats = true
				cur_beat = str(ev.get("id", ev.get("beat", ev.get("name", "beat%d" % beat_order.size()))))
				cur_beat = String(BEAT_NAMES.get(cur_beat, cur_beat))
			if String(ev.type) == "opening_step":
				op_active = true
				op_step_id = String(ev.get("id", ""))
			elif String(ev.type) == "opening_end":
				op_active = false
			elif String(ev.type) == "chapter_champion" and int(ev.get("zone", 0)) == 2 and boss_tick < 0:
				boss_tick = int(ev.tick)
			match String(ev.type):
				"gate_opened": marks.append("%.0fs gate%d" % [esec, int(ev.get("zone", 0))])
				"chapter_champion": marks.append("%.0fs champ%d" % [esec, int(ev.get("zone", 0))])
				"zone_entered": marks.append("%.0fs enter%d" % [esec, int(ev.get("zone", 0))])
				"beat_started": marks.append("%.0fs beat:%s" % [esec, cur_beat])
				"opening_step": marks.append("%.1fs open:%s" % [esec, String(ev.get("id", ""))])
				"opening_end": marks.append("%.1fs open:end" % esec)
				"descent_ready": marks.append("%.0fs descent ready" % esec)
				"descent_called":
					marks.append("%.0fs descent used" % esec)
					descent_calls.append({"tick": int(ev.tick), "normals": int(ev.get("normals_in_reach", 0)), "strongs": int(ev.get("strongs_in_reach", 0)), "alive": int(run.alive_count()), "hold_bonus_bps": int(ev.get("hold_bonus_bps", 0))})
				"descent_end": descent_ends.append({"tick": int(ev.tick), "kills": int(ev.kills), "strong_hits": int(ev.strong_hits), "strong_damage_raw": int(ev.strong_damage_raw), "marks_taken": int(ev.marks_taken), "refund": int(ev.refund), "boss_share_bps": int(ev.get("boss_share_bps", 0)), "kills_total": int(ev.get("kills_total", 0)), "normals_at_call": int(ev.get("normals_at_call", 0)), "entered": int(ev.get("entered", 0)), "clear_ratio_bps": int(ev.get("clear_ratio_bps", 0))})
				"level_choice":
					if level_first < 0.0:
						level_first = esec
						marks.append("%.1fs first level-up" % esec)
			# The first beat's start with an opening is filed under the opening (opening_step follows in the same tick), not under "기".
			var ebn := OPENING_NAME if op_active else (cur_beat if event_beats else beat_name_by_time(esec))
			var skip_accs: bool = open_on and String(ev.type) == "beat_started" and String(ev.get("id", "")) == first_beat_id
			var accs := [] if skip_accs else [bin_acc(bins, esec),
				get_beat(beats, beat_order, ebn, esec),
				get_acc(zones, zname, zname, esec)]
			for a in accs:
				touch(a, esec)
				add_event(a, ev, run, prim)
		# per-step accounting
		var dropped_now := int(run.metrics.get("events_dropped", 0))
		var bn := OPENING_NAME if op_active else (cur_beat if event_beats else beat_name_by_time(sec))
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
		if adv > 0 and int(run.tick) % 6 == 0: sweep_sample(sw, run)
		while seen_sel < pilot.selections.size():
			var sel: Dictionary = pilot.selections[seen_sel]
			seen_sel += 1
			var ssec: float = float(int(sel.tick)) / 60.0
			var gbn := OPENING_NAME if op_active else (cur_beat if event_beats else beat_name_by_time(ssec))
			sw.graces.append([snappedf(ssec, 0.1), gbn])
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
	summary.merge(grace_density(pilot.selections, boss_tick, secs), true)
	summary["offers_l12"] = offers_l12(offers)
	var end_beat := OPENING_NAME if op_active else (cur_beat if event_beats else beat_name_by_time(secs))
	var defeat := {"mode": String(run.mode), "s": snappedf(secs, 0.1), "beat": end_beat, "opening_active": op_active, "opening_step": op_step_id if op_active else "", "last_opening_step": op_step_id}
	if xp_trace_s > 0.0:
		defeat["xp_trace"] = xp_trace
		print("  XPTRACE %s seed=%d [s,xp,level,alive]: %s" % [prim.trim_prefix("chapter1.skill."), seed_, str(xp_trace)])
	if stand_from != "" or stand_on:
		defeat["stand"] = {"from": stand_from, "started": bool(sf.on), "start_s": sf.start_s, "zone": sf.zone, "champions_s": sf.champs.duplicate(), "last_hit": sf.last_hit, "cause": hit_cause(sf.last_hit)}
	var result := {"primary": prim.trim_prefix("chapter1.skill."), "seed": seed_, "mode": String(run.mode), "secs": snappedf(secs, 0.1), "kills": int(run.kills),
		"beat_source": "beat_started event" if event_beats else "time table (A2)", "marks": marks, "summary": summary,
		"descent": {"policy": descent_policy, "metrics": run.metrics.get("descent", {}).duplicate(true), "ends": descent_ends, "calls": descent_calls, "view": run.descent_view()},
		"elites": extras_summary(run, ex),
		"bins": bin_list, "beats": beat_list, "zones": zone_list, "sweep": finish_sweep(sw, secs, int(run.tick), prim),
		"kit": cur_kit, "gear": gear_summary(run, dmg_raw_s), "end": defeat, "offers": offers.map(func(o): return [int(o.level), int(o.cards), int(o.kinds)])}
	if rc_on: result["rc"] = rc_finish(pilot, secs)
	if element_kit_on:
		result["element_kit"] = {"policy": kit_policy, "tree": kit_tree, "kit_seed": kit_seed, "view": run.kit_view(), "metrics": run.metrics.get("kit", {}).duplicate(true), "hands": kit_hands, "picks": kit_picks, "casts": run.metrics.casts.duplicate(true), "hits": run.metrics.hits.duplicate(true)}
		if kit_doc_path != "": result.element_kit["doc"] = kit_doc_path
	if hurt_on:
		result["hurt"] = hurt_summary(hurt_log)
		result["volley"] = {"placed": volley_placed, "fired": volley_shooters.size()}
		# VR-B (record only): of the bodies that carried the first-shot mark, killed_before_fire = died with the mark still on (never in volley_shooters), stopped_frozen = frozen at
		# least one tick while marked (a freeze pauses the windup clock, it does not cancel the shot), frozen_killed = both; unresolved = still marked and alive at the end.
		for vid in volley_marked:
			volley_tally.marked += 1
			if bool(volley_marked[vid].frozen): volley_tally.stopped_frozen += 1
		result["volley"]["marked"] = volley_tally.marked
		result["volley"]["killed_before_fire"] = volley_tally.killed_before_fire
		result["volley"]["stopped_frozen"] = volley_tally.stopped_frozen
		result["volley"]["frozen_killed"] = volley_tally.frozen_killed
		result["volley"]["unresolved"] = volley_marked.size()
	return result

# ---------- RC-A: run-curve raw records (read-only; see the header) ----------
## core event type -> short tag of the rc record.
const RC_EVENTS := {"beat_started": "beat", "wave_crest": "crest", "gate_opened": "gate", "chapter_champion": "champ", "zone_entered": "zone",
	"potion_pickup": "pp", "descent_ready": "dr", "descent_called": "dc", "level_choice": "lc", "item_drop": "drop"}

func rc_new() -> Dictionary:
	return {"ev": [], "hp_s": [], "pot_s": [], "offers": [], "last_crest_tick": -1, "last_pot": -1}

## Once per core step: the lowest life ratio of each second and the potion count at the last step of it.
func rc_tick(run) -> void:
	var sec := int(int(run.tick) / 60)
	var ratio := clampf(float(run.hero.hp_raw) / maxf(1.0, float(run.hero.max_hp_raw)), 0.0, 1.0)
	while rc.hp_s.size() <= sec:
		rc.hp_s.append(ratio)
		rc.pot_s.append(int(run.potions))
	rc.hp_s[sec] = minf(float(rc.hp_s[sec]), ratio)
	rc.pot_s[sec] = int(run.potions)
	# The pilot drinks BEFORE step() (its potion_used event is gone when the events are read), so a drink is read as the potion count falling (only drinking lowers it): tag "pu".
	if int(rc.last_pot) >= 0 and int(run.potions) < int(rc.last_pot): rc.ev.append([int(run.tick), "pu", int(run.potions)])
	rc.last_pot = int(run.potions)

## D-boss-finale (BF-T1..T4, T6, read-only): present in the JSON as rc.fin only for a run in which the finale ran (a boss_entrance event came),
## so a run without it has the same rc block as before. rows: be [tick,"be",ticks] | bp [tick,"bp",phase,id] | bs [tick,"bs",index,ticks] |
## bx [tick,"bx",index] | bc [tick,"bc",bps,total_bps] | bo [tick,"bo"]. fin = {boss_id, brk (open break index or -1), phase, kills_break {index: ordinary kills},
## hurt_break {index: damage taken raw}, hurt_phase {phase: damage taken raw}, hits_break {index: hero hits}, boss_dealt {skill_id: life taken off the boss, raw},
## other_dealt (life taken off everything else after the boss came, raw), last_hit {tick, source_kind, attack_id, damage_raw, hp_after_raw, telegraphed},
## hit_by {attack_id or "src_"+source_kind: [hits, damage_raw, grazes]}}.
const RC_FINALE := ["boss_entrance", "boss_phase", "boss_break_started", "boss_break_ended", "boss_chip", "boss_potion", "boss_break_struck"]
const RC_FINALE_TAG := {"boss_entrance": "be", "boss_phase": "bp", "boss_break_started": "bs", "boss_break_ended": "bx", "boss_chip": "bc", "boss_potion": "bo", "boss_break_struck": "bk"}

func rc_finale(ev: Dictionary) -> void:
	var t := String(ev.type)
	if t == "boss_entrance" and not rc.has("fin"):
		rc["fin"] = {"boss_id": int(ev.get("target_id", 0)), "brk": -1, "phase": 0, "kills_break": {}, "hurt_break": {}, "hurt_phase": {}, "hits_break": {}, "boss_dealt": {}, "other_dealt": 0, "last_hit": {}, "hit_by": {}}
	if not rc.has("fin"): return
	var fin: Dictionary = rc.fin
	match t:
		"boss_entrance": rc.ev.append([int(ev.tick), "be", int(ev.get("ticks", 0))])
		"boss_phase":
			fin.phase = int(ev.get("phase", 0))
			rc.ev.append([int(ev.tick), "bp", int(ev.get("phase", 0)), String(ev.get("id", ""))])
		"boss_break_started":
			fin.brk = int(ev.get("index", -1))
			rc.ev.append([int(ev.tick), "bs", int(ev.get("index", -1)), int(ev.get("ticks", 0))])
		"boss_break_ended":
			fin.brk = -1
			rc.ev.append([int(ev.tick), "bx", int(ev.get("index", -1))])
		"boss_chip": rc.ev.append([int(ev.tick), "bc", int(ev.get("bps", 0)), int(ev.get("total_bps", 0))])
		"boss_potion": rc.ev.append([int(ev.tick), "bo"])
		"boss_break_struck":
			# BF-C: the descent's blow on the boss in a break, raw per break index (struck_break), and one row [tick, "bk", index, damage_raw].
			var sb: Dictionary = fin.get("struck_break", {})
			sb[str(int(ev.get("index", -1)))] = int(sb.get(str(int(ev.get("index", -1))), 0)) + int(ev.get("damage", 0))
			fin["struck_break"] = sb
			rc.ev.append([int(ev.tick), "bk", int(ev.get("index", -1)), int(ev.get("damage", 0))])
		"death":
			if int(fin.brk) >= 0 and String(ev.get("role", "")) == "normal":
				var k := str(int(fin.brk))
				fin.kills_break[k] = int(fin.kills_break.get(k, 0)) + 1
		"hit":
			var dealt := int(ev.get("dealt_raw", ev.get("damage_raw", 0)))
			if int(ev.get("target_id", 0)) == int(fin.boss_id):
				var sk := String(ev.get("skill_id", ""))
				fin.boss_dealt[sk] = int(fin.boss_dealt.get(sk, 0)) + dealt
			else: fin.other_dealt = int(fin.other_dealt) + dealt
		"hero_hit":
			var raw := int(ev.get("damage_raw", 0))
			var ph := str(int(fin.phase))
			fin.hurt_phase[ph] = int(fin.hurt_phase.get(ph, 0)) + raw
			if int(fin.brk) >= 0:
				var b := str(int(fin.brk))
				fin.hurt_break[b] = int(fin.hurt_break.get(b, 0)) + raw
				fin.hits_break[b] = int(fin.hits_break.get(b, 0)) + 1
			fin.last_hit = {"tick": int(ev.tick), "source_kind": String(ev.get("source_kind", "")), "attack_id": String(ev.get("attack_id", "")), "damage_raw": raw, "hp_after_raw": int(ev.get("hp_after_raw", 0))}
			# hit_by {attack_id (or "src_"+source_kind when the hit has none): [hits, damage_raw taken, grazes]} (BF-B, read-only)
			var hk := String(ev.get("attack_id", ""))
			if hk == "": hk = "src_" + String(ev.get("source_kind", ""))
			var hb: Array = fin.hit_by.get(hk, [0, 0, 0])
			fin.hit_by[hk] = [int(hb[0]) + 1, int(hb[1]) + raw, int(hb[2]) + (1 if bool(ev.get("graze", false)) else 0)]

func rc_event(ev: Dictionary) -> void:
	var t := String(ev.type)
	if rc.has("fin") or t == "boss_entrance": rc_finale(ev)
	if t in RC_FINALE: return
	if not RC_EVENTS.has(t): return
	var row: Array = [int(ev.tick), String(RC_EVENTS[t])]
	match t:
		"beat_started": row.append(String(ev.get("id", "")))
		"wave_crest":
			row.append(String(ev.get("beat", "")))
			row.append(int(ev.get("count", 0)))
			rc.last_crest_tick = int(ev.tick)
		"gate_opened", "chapter_champion", "zone_entered": row.append(int(ev.get("zone", 0)))
		"potion_pickup": row.append(int(ev.get("remaining", 0)))
		"descent_ready": row.append(int(ev.get("uses", 0)))
		"level_choice": row.append(int(ev.get("level", 0)))
		"item_drop":
			var item: Dictionary = ev.get("item", {})
			row.append(String(item.get("quality", "")))
			row.append(String(ev.get("source", "")))
	rc.ev.append(row)

## One offer with the state the D-run-curve 4.3 crisis rule reads (alive vs the beat cap, ticks since the last crest, a guardian alive, life, seal progress).
func rc_offer(run, offer: Dictionary) -> void:
	var cards: Array = []
	for c in offer.cards: cards.append([String(c.get("id", "")), String(c.get("kind", ""))])
	var cap := int(run.tuning.alive_cap)
	var rh: Dictionary = run.tuning.get("rhythm", {})
	if bool(run._rhythm_on):
		if String(run._trial_phase) == "hold": cap = mini(cap, int(rh.get("trial", {}).get("alive_cap", cap)))
		elif int(run._beat_index) >= 0 and int(run._beat_index) < rh.get("beats", []).size(): cap = mini(cap, int(rh.beats[int(run._beat_index)].alive_cap))
	var hp_bps := int(float(run.hero.hp_raw) * 10000.0 / maxf(1.0, float(run.hero.max_hp_raw)))
	rc.offers.append({"tick": int(run.tick), "level": int(run.growth.snapshot().level), "cards": cards, "alive": int(run.alive_count()), "cap": cap,
		"crest_age": (int(run.tick) - int(rc.last_crest_tick)) if int(rc.last_crest_tick) >= 0 else -1, "champ_alive": bool(run._guardian_alive()),
		"zone": int(run.zone), "zone_bps": int(run._zone_bps()), "hp_bps": hp_bps})

func rc_finish(pilot, secs: float) -> Dictionary:
	var picks: Array = []
	for sel in pilot.selections: picks.append([int(sel.tick), String(sel.id), String(sel.kind)])
	var hp: Array = []
	for v in rc.hp_s: hp.append(snappedf(float(v), 0.001))
	var out := {"secs": snappedf(secs, 0.1), "ev": rc.ev, "hp_s": hp, "pot_s": rc.pot_s, "offers": rc.offers, "picks": picks,
		"defs": "ev rows = [tick, tag, ...]: beat id | crest beat count | gate zone | champ zone | zone zone | pu remaining (read from the potion count falling) | pp remaining | dr uses | dc | lc level | drop quality source. hp_s = lowest life ratio per second; pot_s = potions at the end of the second. offers.crest_age = ticks since the last wave_crest (-1 none)."}
	if rc.has("fin"): out["fin"] = rc.fin
	return out

# ---------- GM-A: damage taken by source (read-only) ----------
## One hero_hit as [second, source_kind, attack_id, damage_raw, graze, heavy]. heavy = the hit before any graze was at least heavy_bps of the maximum life (the core's own test).
func hurt_note(run, ev: Dictionary) -> Array:
	var rule: Dictionary = run.tuning.get("heavy_hit", {})
	var heavy_bps := int(rule.get("heavy_bps", 0))
	var heavy: bool = heavy_bps > 0 and int(ev.get("incoming_raw", 0)) * 10000 >= heavy_bps * int(run.hero.max_hp_raw)
	return [int(int(ev.tick) / 60), String(ev.get("source_kind", "")), String(ev.get("attack_id", "")), int(ev.get("damage_raw", 0)), bool(ev.get("graze", false)), heavy]

func hurt_summary(log_: Array) -> Dictionary:
	var per_sec: Array = []
	for h in log_: bump(per_sec, int(h[0]), float(h[3]))
	var worst := -1.0
	var worst_lo := 0
	var window := 0.0
	for i in per_sec.size():
		window += float(per_sec[i])
		if i >= 60: window -= float(per_sec[i - 60])
		if window > worst:
			worst = window
			worst_lo = maxi(0, i - 59)
	var worst_hi := worst_lo + 59
	var out := {"worst_window_s": [worst_lo, worst_hi], "all": {}, "w60": {}, "attack_all": {}, "attack_w60": {}, "hits_by_attack": {"all": {}, "w60": {}}, "hits": 0, "heavy": 0, "graze": 0, "hits_w60": 0, "heavy_w60": 0, "graze_w60": 0}
	for h in log_:
		var inw: bool = int(h[0]) >= worst_lo and int(h[0]) <= worst_hi
		var dmg := float(h[3]) / 256.0
		var kind := String(h[1])
		var atk := "%s/%s" % [kind, String(h[2])]
		out.all[kind] = snappedf(float(out.all.get(kind, 0.0)) + dmg, 0.001)
		out.attack_all[atk] = snappedf(float(out.attack_all.get(atk, 0.0)) + dmg, 0.001)
		out.hits_by_attack.all[atk] = int(out.hits_by_attack.all.get(atk, 0)) + 1
		out.hits += 1
		if bool(h[5]): out.heavy += 1
		if bool(h[4]): out.graze += 1
		if inw:
			out.w60[kind] = snappedf(float(out.w60.get(kind, 0.0)) + dmg, 0.001)
			out.attack_w60[atk] = snappedf(float(out.attack_w60.get(atk, 0.0)) + dmg, 0.001)
			out.hits_by_attack.w60[atk] = int(out.hits_by_attack.w60.get(atk, 0)) + 1
			out.hits_w60 += 1
			if bool(h[5]): out.heavy_w60 += 1
			if bool(h[4]): out.graze_w60 += 1
	return out

# ---------- D22 R0-A helpers (read-only) ----------
## The name (as the beat tables use), cap and lull length of a core beat id; the opening steps report as the opening. {} = not a beat of the table.
func beat_cap(sw: Dictionary, id: String) -> Dictionary:
	for b in sw.beats:
		if String(b.get("id", "")) == id:
			var lt := 0
			if b.get("wave") is Dictionary: lt = int(b.wave.get("lull_ticks", 0))
			return {"name": String(BEAT_NAMES.get(id, id)), "cap": mini(int(b.get("alive_cap", sw.alive_cap)), int(sw.alive_cap)), "lull_ticks": lt}
	if id == "trial": return {"name": String(BEAT_NAMES.get(id, id)), "cap": int(sw.trial_cap), "lull_ticks": 0}
	for st in sw.opening_steps:
		if String(st.get("id", "")) == id: return {"name": OPENING_NAME, "cap": mini(int(st.get("alive_cap", sw.alive_cap)), int(sw.alive_cap)), "lull_ticks": 0}
	return {}

## One offer into the log (once per token). level = the growth level the offer is made at.
func note_offer(run, offers: Array, offer: Dictionary) -> void:
	if offer.is_empty() or not offer.has("cards"): return
	var token := String(offer.get("token", ""))
	if offers.size() > 0 and String(offers[offers.size() - 1].token) == token: return
	var kinds := {}
	for c in offer.cards: kinds[String(c.get("kind", ""))] = true
	offers.append({"token": token, "level": int(run.growth.snapshot().level), "cards": offer.cards.size(), "kinds": kinds.size()})
	if rc_on: rc_offer(run, offer)

func offers_l12(offers: Array) -> Dictionary:
	var kinds: Array = []
	for o in offers:
		if int(o.level) >= 12: kinds.append(float(o.kinds))
	return {"rule": "offers made at growth level >= 12", "n": kinds.size(), "kinds_min": (int(kinds.min()) if kinds.size() > 0 else -1), "kinds_median": (median(kinds) if kinds.size() > 0 else -1.0),
		"kinds_lt2": kinds.filter(func(k): return k < 2.0).size()}

## Grace density figures from the pilot's picks (tick-stamped). "boss fill" = the pick(s) made at or after the zone-3 guardian's appearance (guardian_grace fills the last level there);
## natural = made before it. A run with no zone-3 guardian (fell earlier) has no fill and no boss gap (-1).
func grace_density(selections: Array, boss_tick: int, secs: float) -> Dictionary:
	var per_sec := {}
	var same_max := 0
	var nat: Array = []
	for sel in selections:
		var sec := int(int(sel.tick) / 60)
		per_sec[sec] = int(per_sec.get(sec, 0)) + 1
		same_max = maxi(same_max, int(per_sec[sec]))
		if boss_tick < 0 or int(sel.tick) < boss_tick: nat.append(float(int(sel.tick)) / 60.0)
	var gap_nofill := 0.0
	for i in range(1, nat.size()): gap_nofill = maxf(gap_nofill, float(nat[i]) - float(nat[i - 1]))
	var last_to_boss := -1.0
	if boss_tick >= 0 and nat.size() > 0: last_to_boss = float(boss_tick) / 60.0 - float(nat[nat.size() - 1])
	return {"grace_same_sec_max": same_max, "grace_longest_gap_nofill_s": snappedf(gap_nofill, 0.1), "grace_last_natural_to_boss_s": snappedf(last_to_boss, 0.1), "boss_appear_s": snappedf(float(boss_tick) / 60.0, 0.1) if boss_tick >= 0 else -1.0}

## Crest peak and lull end per beat, medians over all runs (measured values; n = the number of crests / lulls behind each median).
func crest_lull_summary(runs: Array) -> Dictionary:
	var out := {}
	for r in runs:
		for c in r.sweep.crests:
			var k := String(c[0])
			if not out.has(k): out[k] = {"crest_ratio": [], "crest_max": [], "lull_ratio": []}
			out[k].crest_ratio.append(float(c[3]))
			out[k].crest_max.append(float(c[1]))
		for l in r.sweep.lulls:
			var k2 := String(l[0])
			if not out.has(k2): out[k2] = {"crest_ratio": [], "crest_max": [], "lull_ratio": []}
			out[k2].lull_ratio.append(float(l[3]))
	var res := {}
	for k in out:
		var d: Dictionary = out[k]
		res[k] = {"crest_n": d.crest_ratio.size(), "crest_ratio_median": snappedf(median(d.crest_ratio), 0.001), "crest_max_median": median(d.crest_max),
			"lull_n": d.lull_ratio.size(), "lull_ratio_median": snappedf(median(d.lull_ratio), 0.001)}
	return res

# ---------- D19 V0: sweep counts (read-only; they only read events and run.alive_count()) ----------
func new_sweep(run) -> Dictionary:
	return {"cap": int(run.tuning.alive_cap), "alive_cap": int(run.tuning.alive_cap), "beats": run.tuning.get("rhythm", {}).get("beats", []),
		"trial_cap": int(run.tuning.get("rhythm", {}).get("trial", {}).get("alive_cap", run.tuning.alive_cap)),
		"opening_steps": run.tuning.get("rhythm", {}).get("opening", {}).get("steps", []),
		"s": {"kills": [], "okills": [], "pk": [], "dmg": [], "hh": [], "alive": [], "an": [], "casts": [], "sweeps": [], "clears": [], "clears_d": [], "walk": [], "one": []},
		"casts_by_skill": {}, "kills_by_skill": {}, "window": [], "last_high": -1, "desc_tick": -1, "born": {}, "hitn": {}, "lives": [], "big_open": {}, "big": [], "graces": [],
		"crest_open": [], "crests": [], "lull_wait": [], "lulls": [], "prev_n": 0, "prev_tick": -1}

func bump(a: Array, i: int, v: float = 1.0) -> void:
	while a.size() <= i: a.append(0.0)
	a[i] += v

func sweep_event(sw: Dictionary, ev: Dictionary, run, prim: String) -> void:
	var sec := int(int(ev.tick) / 60)
	var s: Dictionary = sw.s
	match String(ev.type):
		"beat_started":
			var id := String(ev.get("id", ""))
			var cap := int(sw.alive_cap)
			if id == "trial": cap = int(sw.trial_cap)
			for b in sw.beats:
				if String(b.get("id", "")) == id: cap = int(b.get("alive_cap", cap))
			sw.cap = mini(cap, int(sw.alive_cap))
		"descent_called", "descent_end": sw.desc_tick = int(ev.tick)
		"wave_crest":
			var cb := String(ev.get("beat", ""))
			var cinfo := beat_cap(sw, cb)
			if not cinfo.is_empty():
				sw.crest_open.append({"name": String(cinfo.name), "cap": int(cinfo.cap), "end": int(ev.tick) + CREST_AFTER_TICKS, "max": 0})
		"lull_started":
			var lb := String(ev.get("beat", ""))
			var linfo := beat_cap(sw, lb)
			if not linfo.is_empty() and int(linfo.lull_ticks) > 0:
				sw.lull_wait.append({"name": String(linfo.name), "cap": int(linfo.cap), "at": int(ev.tick) + int(linfo.lull_ticks)})
		"cast":
			if not ev.has("pulse"):
				bump(s.casts, sec)
				var sid := String(ev.get("skill_id", ""))
				sw.casts_by_skill[sid] = int(sw.casts_by_skill.get(sid, 0)) + 1
		"hero_hit":
			bump(s.hh, sec)
			bump(s.dmg, sec, float(ev.get("damage_raw", 0)) / maxf(1.0, float(run.hero.max_hp_raw)))
		"spawn":
			if String(ev.kind) in ORDINARY and not bool(ev.get("elite", false)): sw.born[int(ev.target_id)] = [int(ev.tick), String(ev.kind)]
		"chapter_champion":
			var cid := int(ev.target_id)
			sw.born.erase(cid)
			sw.hitn.erase(cid)
			sw.big_open[cid] = {"kind": "guardian%d" % (int(ev.zone) + 1), "spawn_s": snappedf(float(ev.tick) / 60.0, 0.1), "g_start": float(sw.get("prim_total", 0.0))}
		"elite_spawned":
			var eid := int(ev.target_id)
			sw.born.erase(eid)
			sw.big_open[eid] = {"kind": "elite" if int(ev.get("guard_uid", 0)) == 0 else "elite_guard", "spawn_s": snappedf(float(ev.tick) / 60.0, 0.1)}
		"hit":
			var tid := int(ev.target_id)
			sw.hitn[tid] = int(sw.hitn.get(tid, 0)) + 1
			if String(ev.get("skill_id", "")) == prim:
				bump(s.pk, sec)
				# CB-G1: the primary's damage (dealt_raw, else damage_raw) in total and on an open guardian (the role is known from chapter_champion, the same as the enemies' role).
				var pdmg := float(ev.get("dealt_raw", ev.get("damage_raw", 0)))
				sw.prim_total = float(sw.get("prim_total", 0.0)) + pdmg
				if sw.big_open.has(tid) and String(sw.big_open[tid].kind).begins_with("guardian"):
					sw.big_open[tid]["g_hit"] = float(sw.big_open[tid].get("g_hit", 0.0)) + pdmg
		"death":
			var did := int(ev.target_id)
			bump(s.kills, sec)
			var dsk := String(ev.get("skill_id", ""))
			sw.kills_by_skill[dsk] = int(sw.kills_by_skill.get(dsk, 0)) + 1
			if sw.big_open.has(did):
				var o: Dictionary = sw.big_open[did]
				if o.has("g_start"): o["g_all"] = float(sw.get("prim_total", 0.0)) - float(o.g_start)
				o["death_s"] = snappedf(float(ev.tick) / 60.0, 0.1)
				o["lived_s"] = snappedf(float(o.death_s) - float(o.spawn_s), 0.1)
				sw.big.append(o)
				sw.big_open.erase(did)
				sw.hitn.erase(did)
				return
			var hits_taken := int(sw.hitn.get(did, 0))
			sw.hitn.erase(did)
			if String(ev.kind) in ORDINARY and not bool(ev.get("elite", false)):
				bump(s.okills, sec)
				if String(ev.kind) == "walker":
					bump(s.walk, sec)
					if hits_taken == 1: bump(s.one, sec)
				if sw.born.has(did):
					var b: Array = sw.born[did]
					sw.lives.append([snappedf(float(b[0]) / 60.0, 0.1), snappedf(float(int(ev.tick) - int(b[0])) / 60.0, 0.1), ORDINARY.find(String(b[1]))])
					sw.born.erase(did)
				# A sweep moment: >= SWEEP_MIN_KILLS ordinary deaths within the last SWEEP_WINDOW_TICKS; the window empties after one is counted.
				var w: Array = sw.window
				w.append(int(ev.tick))
				while w.size() > 0 and int(w[0]) <= int(ev.tick) - SWEEP_WINDOW_TICKS: w.pop_front()
				if w.size() >= SWEEP_MIN_KILLS:
					bump(s.sweeps, sec)
					w.clear()

func sweep_sample(sw: Dictionary, run) -> void:
	var tick := int(run.tick)
	var sec := int(tick / 60)
	var n: int = run.alive_count()
	var cap := float(sw.cap)
	bump(sw.s.alive, sec, float(n))
	bump(sw.s.an, sec)
	# D22 R0-A: the lull's end is read from the last sample before it (the next crest lands on that very tick); the crest peak is over the 10 s after it.
	var still_wait: Array = []
	for w in sw.lull_wait:
		if tick >= int(w.at) and int(sw.prev_tick) >= 0:
			sw.lulls.append([String(w.name), int(sw.prev_n), int(w.cap), snappedf(float(sw.prev_n) / maxf(1.0, float(w.cap)), 0.001)])
		else:
			still_wait.append(w)
	sw.lull_wait = still_wait
	var still_open: Array = []
	for c in sw.crest_open:
		c["max"] = maxi(int(c.max), n)
		if tick >= int(c.end):
			sw.crests.append([String(c.name), int(c.max), int(c.cap), snappedf(float(c.max) / maxf(1.0, float(c.cap)), 0.001)])
		else:
			still_open.append(c)
	sw.crest_open = still_open
	sw.prev_n = n
	sw.prev_tick = tick
	if float(n) >= CLEAR_HIGH_SHARE * cap:
		sw.last_high = tick
	elif float(n) <= CLEAR_LOW_SHARE * cap and int(sw.last_high) >= 0 and tick - int(sw.last_high) <= CLEAR_WITHIN_TICKS:
		bump(sw.s.clears, sec)
		if int(sw.desc_tick) >= int(sw.last_high): bump(sw.s.clears_d, sec)
		sw.last_high = -1

func finish_sweep(sw: Dictionary, secs: float, end_tick: int, prim: String) -> Dictionary:
	var unres: Array = []
	for id in sw.born:
		var b: Array = sw.born[id]
		unres.append([snappedf(float(b[0]) / 60.0, 0.1), snappedf(float(end_tick - int(b[0])) / 60.0, 0.1), ORDINARY.find(String(b[1]))])
	var big: Array = sw.big.duplicate(true)
	for id in sw.big_open:
		var o: Dictionary = sw.big_open[id].duplicate()
		if o.has("g_start"): o["g_all"] = float(sw.get("prim_total", 0.0)) - float(o.g_start)
		o["death_s"] = -1.0
		o["lived_s"] = snappedf(secs - float(o.spawn_s), 0.1)
		big.append(o)
	var out := {"s": sw.s, "casts_by_skill": sw.casts_by_skill, "kills_by_skill": sw.kills_by_skill, "lives": sw.lives, "unresolved": unres, "big": big,
		"graces": sw.graces, "crests": sw.crests, "lulls": sw.lulls, "defs": {"crest": "[beat, peak alive within 10 s after the wave_crest, beat cap, ratio]; a crest cut by the run end is dropped",
			"lull": "[beat, alive at the last sample before lull start + lull_ticks, beat cap, ratio]", "sweep": "%d ordinary deaths in %d ticks" % [SWEEP_MIN_KILLS, SWEEP_WINDOW_TICKS],
			"clear": "alive >= %.0f%% of the beat cap, then <= %.0f%% within %d ticks" % [CLEAR_HIGH_SHARE * 100.0, CLEAR_LOW_SHARE * 100.0, CLEAR_WITHIN_TICKS],
			"lives": "[born_s, life_s, kind index of %s]; unresolved = still alive at the run end (life_s so far)" % str(ORDINARY)}}
	out["thirds"] = thirds_of(out, secs)
	return out

func slice_sum(a: Array, lo: float, hi: float) -> float:
	var t := 0.0
	for i in a.size():
		var c := float(i) + 0.5
		if c >= lo and c < hi: t += float(a[i])
	return t

func thirds_of(sw: Dictionary, secs: float) -> Array:
	var out: Array = []
	var s: Dictionary = sw.s
	var gr: Array = sw.graces
	for k in 3:
		var lo := secs * float(k) / 3.0
		var hi := secs * float(k + 1) / 3.0 if k < 2 else secs + 1.0
		var dur := secs / 3.0
		var gaps: Array = []
		var n_gr := 0
		var prev := 0.0
		for g in gr:
			var t := float(g[0])
			if t >= lo and t < hi:
				n_gr += 1
				gaps.append(t - prev)
			prev = t
		var kills := slice_sum(s.kills, lo, hi)
		var alive := slice_sum(s.alive, lo, hi) / maxf(1.0, slice_sum(s.an, lo, hi))
		var kps := kills / dur
		var okills := slice_sum(s.okills, lo, hi)
		var casts := slice_sum(s.casts, lo, hi)
		var lives_dead: Array = []
		var lives_all: Array = []
		for l in sw.lives:
			if float(l[0]) >= lo and float(l[0]) < hi:
				lives_dead.append(float(l[1]))
				lives_all.append(float(l[1]))
		var unres_n := 0
		for l in sw.unresolved:
			if float(l[0]) >= lo and float(l[0]) < hi:
				unres_n += 1
				lives_all.append(float(l[1]))
		var gmax := 0.0
		var gsum := 0.0
		for gp in gaps:
			gmax = maxf(gmax, float(gp))
			gsum += float(gp)
		var walk := slice_sum(s.walk, lo, hi)
		out.append({"from_s": snappedf(lo, 0.1), "to_s": snappedf(minf(hi, secs), 0.1), "grace_n": n_gr, "gap_mean": snappedf(gsum / float(gaps.size()), 0.1) if gaps.size() > 0 else -1.0, "gap_max": snappedf(gmax, 0.1) if gaps.size() > 0 else -1.0,
			"kps": snappedf(kps, 0.01), "alive": snappedf(alive, 0.1), "life_little": snappedf(alive / kps, 0.1) if kps > 0.0 else -1.0,
			"life_med": snappedf(median(lives_dead), 0.1), "life_med_all": snappedf(median(lives_all), 0.1), "dead_n": lives_dead.size(), "unresolved_n": unres_n,
			"hits_per_kill": snappedf(slice_sum(s.pk, lo, hi) / maxf(1.0, kills), 0.01), "dmg30": snappedf(slice_sum(s.dmg, lo, hi) / dur * 30.0, 0.001), "dmg": snappedf(slice_sum(s.dmg, lo, hi), 0.001),
			"hits_taken_pm": snappedf(slice_sum(s.hh, lo, hi) / dur * 60.0, 0.1), "casts": int(casts), "kills_per_cast": snappedf(okills / maxf(1.0, casts), 0.01),
			"sweeps": int(slice_sum(s.sweeps, lo, hi)), "sweeps_pm": snappedf(slice_sum(s.sweeps, lo, hi) / dur * 60.0, 0.01),
			"clears": int(slice_sum(s.clears, lo, hi)), "clears_descent": int(slice_sum(s.clears_d, lo, hi)),
			"one_shot_share": snappedf(slice_sum(s.one, lo, hi) / walk, 0.01) if walk > 0.0 else -1.0, "walker_deaths": int(walk)})
	return out

## --pilot-extras: where the bot walks (see the header of this file). Reads the core's read-only views; the core is moved only by step().
func extras_move(run, mv: Vector2) -> Vector2:
	var view: Dictionary = run.extras_view()
	if not bool(view.enabled) or run.mode != "playing": return mv
	var lull: bool = String(run.run_progress().phase) == "lull" or not rhythm_on
	var goal := Vector2.ZERO
	var found := false
	var best := INF
	for site in view.sites:
		var d: float = run.hero.position.distance_to(site.position)
		var wanted := false
		if site.state == "open": wanted = true
		elif site.state == "locked": wanted = (d <= 20.0 and lull) or site.guard_state in ["alert", "fight"]
		if wanted and d < best:
			best = d
			goal = site.position
			found = true
	if not found: return mv
	# A freed shrine is walked onto; a locked site is approached to 3 m and then the bot waits for its guard to fall.
	var open_goal := false
	for site in view.sites:
		if site.state == "open" and site.position == goal: open_goal = true
	if best <= (0.8 if open_goal else 3.0): return Vector2.ZERO
	return (goal - run.hero.position).normalized()

## One event into the run's elite / site record (only with --extras-on).
func ex_event(ex: Dictionary, ev: Dictionary) -> void:
	var sec: float = float(ev.tick) / 60.0
	match String(ev.type):
		"elite_spawned":
			if int(ev.guard_uid) == 0: ex.born[int(ev.target_id)] = int(ev.tick)
		"death":
			if String(ev.get("role", "")) == "elite" and ex.born.has(int(ev.target_id)):
				ex.walk_in_s.append(snappedf(float(int(ev.tick) - int(ex.born[int(ev.target_id)])) / 60.0, 0.1))
		"guard_spawned": ex.guard_placed_s.append(snappedf(sec, 0.1))
		"guard_engaged": ex.engaged[int(ev.uid)] = int(ev.tick)
		"guard_unlocked":
			ex.guard_unlocked_s.append(snappedf(sec, 0.1))
			if ex.engaged.has(int(ev.uid)): ex.guard_fight_s.append(snappedf(float(int(ev.tick) - int(ex.engaged[int(ev.uid)])) / 60.0, 0.1))
		"shrine_taken": ex.taken_s.append(snappedf(sec, 0.1))
		"chest_opened": ex.chest_s.append(snappedf(sec, 0.1))
		"shrine_expired": ex.expired += 1
		"guard_expired": ex.locked_expired += 1

func extras_summary(run, ex: Dictionary) -> Dictionary:
	if not extras_on: return {"on": false}
	var sites: Dictionary = run.metrics.get("sites", {})
	var placed := int(sites.get("placed", 0))
	return {"on": true, "pilot_extras": pilot_extras, "metrics_sites": sites.duplicate(true), "metrics_elites": {"spawned": int(run.metrics.elites.spawned), "killed": int(run.metrics.elites.killed), "skipped": int(run.metrics.elites.skipped)},
		"walk_in_ttk_s": ex.walk_in_s, "guard_fight_s": ex.guard_fight_s, "guard_placed_s": ex.guard_placed_s, "guard_unlocked_s": ex.guard_unlocked_s, "shrine_taken_s": ex.taken_s, "chest_opened_s": ex.chest_s,
		"shrines_lapsed": int(ex.expired), "locked_expired": int(ex.locked_expired), "sites_placed": placed, "unlock_rate": snappedf(float(int(sites.get("unlocked", 0))) / maxf(1.0, float(placed)), 0.01)}

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
	for b in targets:
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

# ---------- D23 T1 appendix A.6 (2): the kit worn from the start, and its table ----------
## The kit (name, "@" = the series) worn through the core's own starting-gear import. "" = ok.
func install_kit(run, kit: String, prim: String) -> String:
	var name := kit.replace("@", prim.trim_prefix("chapter1.skill."))
	var built := GearKits.items(kit_loot, kit_fixture, name)
	if not bool(built.ok): return "gear kit %s: %s" % [name, str(built.errors)]
	# The worn-from-the-start import lives in support/gear_kits.gd (this file keeps no reference to the profile or the import: test_profile_v5 V5-16).
	if not GearKits.wear_from_start(run, built): return "the core refused the kit %s (validate or slots)" % name
	return ""

## Damage taken (HP) of the whole run and of the worst 60 s window, from the hero_hit events (damage_raw is after reduction).
func gear_summary(run, dmg_raw_s: Array) -> Dictionary:
	var total := 0.0
	for v in dmg_raw_s: total += float(v)
	var worst := 0.0
	var window := 0.0
	for i in dmg_raw_s.size():
		window += float(dmg_raw_s[i])
		if i >= 60: window -= float(dmg_raw_s[i - 60])
		worst = maxf(worst, window)
	return {"dmg_hp": snappedf(total / 256.0, 0.1), "dmg_worst60_hp": snappedf(worst / 256.0, 0.1), "max_hp": snappedf(float(run.hero.max_hp_raw) / 256.0, 0.1)}

func guardian_times(r: Dictionary) -> Dictionary:
	var out := {}
	for b in r.sweep.big:
		if String(b.kind).begins_with("guardian") and float(b.death_s) >= 0.0: out[String(b.kind)] = float(b.lived_s)
	return out

func gear_line(r: Dictionary) -> String:
	var g: Dictionary = r.gear
	var times := guardian_times(r)
	return "RUN %s seed=%d kit=%s mode=%s secs=%.1f kills=%d level=%d maxhp=%.0f dmg_hp=%.0f worst60_hp=%.0f guardians_s=%s guardian_share=%s" % [r.primary, r.seed, String(r.kit), r.mode, r.secs, r.kills, r.summary.level, float(g.max_hp), float(g.dmg_hp), float(g.dmg_worst60_hp), str(times), guardian_share_text(r)]

## CB-G1: the share of the primary's damage on the guardian(s), over the guardian fights (spawn to death, or to the run end): sum on guardians / sum of all primary damage in those windows.
func guardian_share_text(r: Dictionary) -> String:
	var hit := 0.0
	var all := 0.0
	for b in r.sweep.big:
		if String(b.kind).begins_with("guardian") and b.has("g_all"):
			hit += float(b.get("g_hit", 0.0))
			all += float(b.g_all)
	return "%.3f" % (hit / all) if all > 0.0 else "-"

func kit_row(kit: String) -> String:
	for key in ["r3", "r15", "r30"]:
		if kit.ends_with("." + key): return key
	if kit == "kit.d1_start": return "r3"
	if kit == "kit.d1_end" or kit.begins_with("kit.d1_end_v1"): return "r15"
	if kit == "kit.d2_mid": return "r30"
	return ""

func ratio_word(v: float, rng_: Variant) -> String:
	if not rng_ is Array: return "기록"
	if v < float(rng_[0]): return "아래(쉬움)"
	if v > float(rng_[1]): return "위(약함)"
	return "안"

## The layer-2 table: each kit against "none" (same primary and seed). Ratios are medians of the paired ratios; the verdicts are the A.5 rows (kit name -> row).
func print_gear_table(runs: Array) -> void:
	var by_key := {}
	for r in runs: by_key["%s|%s|%d" % [r.kit, r.primary, r.seed]] = r
	var kits: Array = []
	for r in runs:
		if not String(r.kit) in kits: kits.append(String(r.kit))
	print("")
	print("LAYER2 table (paired with 'none' by primary and seed; medians of the paired ratios; ratio < 1 = less damage taken / faster kill; mode %s)" % ("rhythm on" if rhythm_on else "rhythm off (shipped)"))
	print("%-24s %-6s %3s | %8s %8s | %8s %8s %8s | %7s %6s | %s" % ["kit", "primary", "n", "dmg tot", "dmg w60", "kill all", "kill g3", "kill g1", "defeat", "secs", "A.5 verdict (damage w60 / kill / defeat)"])
	var groups: Array = ["all"]
	for p in ["ember", "frost", "arc"]:
		for r in runs:
			if String(r.primary) == p and not p in groups:
				groups.append(p)
				break
	for kit in kits:
		if kit == "none": continue
		for grp in groups:
			var dt: Array = []
			var dw: Array = []
			var ka: Array = []
			var k3: Array = []
			var k1: Array = []
			var sc: Array = []
			var defeats := 0
			var n := 0
			for r in runs:
				if String(r.kit) != kit or (grp != "all" and String(r.primary) != grp): continue
				var kitname := String(r.kit).replace("@", String(r.primary))
				var base: Dictionary = by_key.get("none|%s|%d" % [r.primary, r.seed], {})
				if base.is_empty(): continue
				n += 1
				if String(r.mode) == "defeat": defeats += 1
				var g: Dictionary = r.gear
				var bg: Dictionary = base.gear
				if float(bg.dmg_hp) > 0.0:
					dt.append(float(g.dmg_hp) / float(bg.dmg_hp))
					dw.append(float(g.dmg_worst60_hp) / maxf(0.001, float(bg.dmg_worst60_hp)))
				var gt := guardian_times(r)
				var bt := guardian_times(base)
				var rs: Array = []
				for k in gt:
					if bt.has(k) and float(bt[k]) > 0.0:
						rs.append(float(gt[k]) / float(bt[k]))
						if k == "guardian3": k3.append(rs[rs.size() - 1])
						if k == "guardian1": k1.append(rs[rs.size() - 1])
				if not rs.is_empty(): ka.append(median(rs))
				sc.append(float(r.secs) / maxf(0.1, float(base.secs)))
			var row: Dictionary = A5_ROWS.get(kit_row(kit.replace("@", "x")), {})
			var verdict := "-"
			if not row.is_empty() and not dw.is_empty() and not ka.is_empty():
				verdict = "%s: %s / %s / %s" % [String(row.label), ratio_word(median(dw), row.dmg), ratio_word(median(ka), row.kill), ("안" if defeats == 0 else "밖(%d)" % defeats)]
			print("%-24s %-6s %3d | %8s %8s | %8s %8s %8s | %7d %6s | %s" % [kit, grp, n, med_text(dt), med_text(dw), med_text(ka), med_text(k3), med_text(k1), defeats, med_text(sc), verdict])
	print("note: damage = hero_hit damage_raw / 256 (HP) summed over the run; w60 = the worst 60 s window. The kit is worn from tick 0 although its required levels are above level 1 (the core's starting-gear import allows it, as the town does).")

func med_text(v: Array) -> String:
	return "%.2f" % median(v) if not v.is_empty() else "-"

# ---------- cross-run ----------
func median(arr: Array) -> float:
	if arr.is_empty(): return 0.0
	var s := arr.duplicate()
	s.sort()
	var n := s.size()
	return float(s[n / 2]) if n % 2 == 1 else (float(s[n / 2 - 1]) + float(s[n / 2])) * 0.5

func cross_summary(runs: Array) -> Dictionary:
	var out := {}
	for b in targets:
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

# ---------- D24 1st edition: the descent's medians over all uses of a policy ----------
func median_of(list: Array) -> float:
	if list.is_empty(): return -1.0
	var sorted_list := list.duplicate()
	sorted_list.sort()
	var n := sorted_list.size()
	return float(sorted_list[n / 2]) if n % 2 == 1 else (float(sorted_list[n / 2 - 1]) + float(sorted_list[n / 2])) / 2.0

func descent_cross(runs: Array) -> Dictionary:
	var out := {"policy": descent_policy, "runs": runs.size(), "uses": 0, "by_primary": {}}
	var all: Dictionary = {}
	for r in runs:
		if r.descent.policy == "": continue
		var prim := String(r.primary)
		if not out.by_primary.has(prim): out.by_primary[prim] = {}
		for i in r.descent.ends.size():
			var e: Dictionary = r.descent.ends[i]
			var c: Dictionary = r.descent.calls[i] if i < r.descent.calls.size() else {}
			for scope in [all, out.by_primary[prim]]:
				for key in ["kills_total", "kills", "normals_at_call", "entered", "clear_ratio_bps", "boss_share_bps"]:
					if not scope.has(key): scope[key] = []
					scope[key].append(int(e.get(key, 0)))
				if not scope.has("hold_bonus_bps"): scope["hold_bonus_bps"] = []
				scope["hold_bonus_bps"].append(int(c.get("hold_bonus_bps", 0)))
			out.uses = int(out.uses) + 1
	var summarize := func(scope: Dictionary) -> Dictionary:
		var row := {"uses": 0}
		for key in scope:
			row["median_" + key] = median_of(scope[key])
			row["min_" + key] = (scope[key].min() if scope[key].size() > 0 else -1)
			row["max_" + key] = (scope[key].max() if scope[key].size() > 0 else -1)
			row["uses"] = scope[key].size()
		return row
	out["all"] = summarize.call(all)
	var by: Dictionary = {}
	for prim in out.by_primary: by[prim] = summarize.call(out.by_primary[prim])
	out["by_primary"] = by
	return out

func print_descent_cross(runs: Array) -> void:
	var c := descent_cross(runs)
	print("DESCENT_CROSS " + JSON.stringify(c))

# ---------- printing ----------
func print_run(r: Dictionary) -> void:
	var s: Dictionary = r.summary
	print("RUN %s seed=%d mode=%s secs=%.1f kills=%d level=%d  beats by: %s" % [r.primary, r.seed, r.mode, r.secs, r.kills, s.level, r.beat_source])
	print("  marks: ", ", ".join(PackedStringArray(r.marks)))
	if stand_on: print(stand_line(r))
	if stand_from != "": print(stand_from_line(r))
	if r.descent.policy != "":
		var dm: Dictionary = r.descent.metrics
		var dk := 0
		var kill_list: Array = []
		var boss_bps := 0
		for d in r.descent.ends:
			dk += int(d.kills)
			kill_list.append(int(d.kills))
			boss_bps += int(d.get("boss_share_bps", 0))
		kill_list.sort()
		print("  descent bodies on screen at the call (normals/strongs/alive)=%s" % str(r.descent.calls.map(func(c): return "%d/%d/%d" % [int(c.normals), int(c.strongs), int(c.alive)])))
		print("  descent kills(own) per use=%s median=%s boss_share_bps_total=%d" % [str(kill_list), str(kill_list[kill_list.size() / 2]) if kill_list.size() > 0 else "-", boss_bps])
		print("  descent per use (D24 1st edition): at_call/entered/kills_total/own/clear_ratio_bps/hold_bonus_bps/boss_share_bps = %s" % str(range(r.descent.ends.size()).map(func(i): return "%d/%d/%d/%d/%d/%d/%d" % [int(r.descent.ends[i].normals_at_call), int(r.descent.ends[i].entered), int(r.descent.ends[i].kills_total), int(r.descent.ends[i].kills), int(r.descent.ends[i].clear_ratio_bps), int(r.descent.calls[i].hold_bonus_bps) if i < r.descent.calls.size() else 0, int(r.descent.ends[i].boss_share_bps)])))
		print("  descent[%s]: uses=%d ready_at=%s used_at=%s kills_by_descent=%d gauge_in=%d wasted=%d refunded=%d strong_dmg_raw=%d" % [r.descent.policy, int(dm.get("uses", 0)),
			str(dm.get("ready_ticks", []).map(func(t): return snappedf(float(t) / 60.0, 0.1))), str(dm.get("call_ticks", []).map(func(t): return snappedf(float(t) / 60.0, 0.1))), dk,
			int(dm.get("gauge_in", 0)), int(dm.get("wasted", 0)), int(dm.get("refunded", 0)), int(dm.get("strong_damage_raw", 0))])
	if bool(r.elites.on):
		var el: Dictionary = r.elites
		print("  elites[pilot_extras=%s]: walk-in spawned=%d killed=%d skipped=%d ttk_s=%s | sites placed=%d engaged=%d unlocked=%d (rate %.2f) chests=%d shrines_taken=%d lapsed=%d locked_expired=%d skipped=%d | guard fight_s=%s placed_at=%s" % [str(el.pilot_extras),
			int(el.metrics_elites.spawned) - int(el.sites_placed), int(el.metrics_elites.killed), int(el.metrics_elites.skipped), str(el.walk_in_ttk_s), int(el.sites_placed), int(el.metrics_sites.get("engaged", 0)), int(el.metrics_sites.get("unlocked", 0)),
			float(el.unlock_rate), int(el.metrics_sites.get("chests_opened", 0)), int(el.metrics_sites.get("shrines_taken", 0)), int(el.shrines_lapsed), int(el.locked_expired), int(el.metrics_sites.get("skipped", 0)), str(el.guard_fight_s), str(el.guard_placed_s)])
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

const THIRD_COLS := [["grace_n", "은총 수", "%.0f"], ["gap_mean", "간격 평균(초)", "%.1f"], ["gap_max", "간격 최장(초)", "%.1f"], ["kps", "초당 처치", "%.2f"],
	["alive", "살아 있는 적", "%.1f"], ["life_little", "살아 있는 시간(리틀, 초)", "%.1f"], ["life_med", "죽은 보통 적의 수명 중앙(초)", "%.1f"], ["life_med_all", "수명 중앙(안 죽은 것 포함)", "%.1f"],
	["unresolved_n", "끝까지 산 보통 적", "%.0f"], ["hits_per_kill", "처치당 주력 명중", "%.2f"], ["dmg30", "30초 받은 피해(최대 생명 비)", "%.3f"], ["hits_taken_pm", "분당 피격", "%.1f"],
	["casts", "시전 수", "%.0f"], ["kills_per_cast", "시전당 보통 처치", "%.2f"], ["sweeps_pm", "분당 쓸기(0.5초 10처치)", "%.2f"], ["clears", "화면 비움", "%.0f"], ["clears_descent", "그중 강림", "%.0f"],
	["one_shot_share", "보행자 한 발 몫", "%.2f"]]

func print_sweep_run(r: Dictionary) -> void:
	var sw: Dictionary = r.sweep
	print("  THIRDS %s seed=%d (secs=%.1f mode=%s)" % [r.primary, r.seed, r.secs, r.mode])
	var line := "    third | "
	for t in 3: line += "%d(%s-%ss) " % [t + 1, str(sw.thirds[t].from_s), str(sw.thirds[t].to_s)]
	print(line)
	for col in THIRD_COLS:
		var row := "    %-30s" % col[1]
		for t in 3: row += " %8s" % (col[2] % float(sw.thirds[t][col[0]]))
		print(row)
	print("    casts by skill: %s | kills by skill: %s" % [str(sw.casts_by_skill), str(sw.kills_by_skill)])
	var gs: Dictionary = r.summary
	print("    은총 밀도(1판): 같은 초 최대 %d / 우두머리 채움 뺀 가장 긴 간격 %.1f초 / 마지막 자연 은총 → 우두머리 등장 %.1f초 (등장 %.1f초, -1 = 우두머리 없음)" % [int(gs.grace_same_sec_max), float(gs.grace_longest_gap_nofill_s), float(gs.grace_last_natural_to_boss_s), float(gs.boss_appear_s)])
	var o12: Dictionary = gs.offers_l12
	print("    레벨 12 뒤 제안(1판, %d개): 카드 종류 수 최소 %d 중앙 %.1f, 2종 미만 %d개" % [int(o12.n), int(o12.kinds_min), float(o12.kinds_median), int(o12.kinds_lt2)])
	var bigs: Array = []
	for b in sw.big: bigs.append("%s spawn %.1fs %s" % [b.kind, float(b.spawn_s), ("died after %.1fs" % float(b.lived_s)) if float(b.death_s) >= 0.0 else ("alive at end, %.1fs" % float(b.lived_s))])
	print("    big enemies: %s" % (", ".join(PackedStringArray(bigs)) if bigs.size() > 0 else "-"))

func fmt_med(vals: Array, f: String) -> String:
	var v: Array = vals.filter(func(x): return float(x) >= 0.0)
	if v.is_empty(): return "-"
	return (f + " (" + f + "~" + f + ")") % [median(v), float(v.min()), float(v.max())]

func print_thirds(runs: Array) -> void:
	print("THIRDS across %d runs (median (min~max); a run enters a cell only when it has a value there; '-' = none)" % runs.size())
	print("  %-34s | %-26s | %-26s | %-26s" % ["", "앞 1/3", "가운데 1/3", "뒤 1/3"])
	for col in THIRD_COLS:
		var cells: Array = []
		for t in 3:
			var vals: Array = []
			for r in runs: vals.append(r.sweep.thirds[t][col[0]])
			cells.append(fmt_med(vals, col[2]))
		print("  %-34s | %-26s | %-26s | %-26s" % [col[1], cells[0], cells[1], cells[2]])
	# ratios the director's targets are written in
	var ratio: Array = []
	var gaps_last: Array = []
	for r in runs:
		var g1: float = float(r.sweep.thirds[1].gap_mean)
		var g2: float = float(r.sweep.thirds[2].gap_mean)
		if g1 > 0.0 and g2 > 0.0: ratio.append(g2 / g1)
		gaps_last.append(float(r.summary.grace_longest_gap_s))
	print("  뒤/가운데 은총 간격 평균 비: %s | 판 안의 가장 긴 간격(초): %s | 은총 수: %s | 판 길이(초): %s" % [fmt_med(ratio, "%.2f"), fmt_med(gaps_last, "%.1f"),
		fmt_med(runs.map(func(r): return float(r.summary.grace_count)), "%.1f"), fmt_med(runs.map(func(r): return float(r.secs)), "%.0f")])
	print_crest_lull(runs)
	var gden: Array = [[], [], []]
	var okinds: Array = []
	var olt2 := 0
	var on_total := 0
	for r in runs:
		gden[0].append(float(r.summary.grace_same_sec_max))
		if float(r.summary.grace_longest_gap_nofill_s) > 0.0: gden[1].append(float(r.summary.grace_longest_gap_nofill_s))
		gden[2].append(float(r.summary.grace_last_natural_to_boss_s))
		var oo: Dictionary = r.summary.offers_l12
		on_total += int(oo.n)
		olt2 += int(oo.kinds_lt2)
		if int(oo.n) > 0: okinds.append(float(oo.kinds_min))
	print("  은총 밀도(%d판): 같은 초 최대 %s | 우두머리 채움 뺀 가장 긴 간격(초) %s | 마지막 자연 은총 → 우두머리 등장(초, -1 = 우두머리 없음) %s" % [runs.size(), fmt_med(gden[0], "%.0f"), fmt_med(gden[1], "%.1f"), fmt_med(gden[2], "%.1f")])
	print("  레벨 12 뒤 제안(%d판, 제안 %d개): 판마다 카드 종류 수 최소 %s | 종류 2 미만인 제안 %d개" % [runs.size(), on_total, fmt_med(okinds, "%.0f"), olt2])
	var modes := {}
	for r in runs: modes[String(r.mode)] = int(modes.get(String(r.mode), 0)) + 1
	var dmg_all: Array = []
	for r in runs:
		var d := 0.0
		for t in 3: d += float(r.sweep.thirds[t].dmg)
		dmg_all.append(d)
	print("  끝 상태: %s | 판 전체 받은 피해(최대 생명 비 합): %s" % [str(modes), fmt_med(dmg_all, "%.2f")])
	# grace gap per beat (the gap ending at a grace taken in that beat)
	var by_beat: Dictionary = {}
	for r in runs:
		var prev := 0.0
		for g in r.sweep.graces:
			var b := String(g[1])
			if not by_beat.has(b): by_beat[b] = []
			by_beat[b].append(float(g[0]) - prev)
			prev = float(g[0])
	var parts: Array = []
	for b in by_beat: parts.append("%s %s(n=%d)" % [b, fmt_med(by_beat[b], "%.1f"), by_beat[b].size()])
	print("  마디별 은총 간격(초): " + " / ".join(PackedStringArray(parts)))
	var guard_times: Dictionary = {}
	for r in runs:
		for b in r.sweep.big:
			var k := String(b.kind)
			if not guard_times.has(k): guard_times[k] = {"died": [], "alive": []}
			if float(b.death_s) >= 0.0: guard_times[k].died.append(float(b.lived_s))
			else: guard_times[k].alive.append(float(b.lived_s))
	var gparts: Array = []
	for k in guard_times: gparts.append("%s 잡음 %d판 %s / 못 잡고 끝 %d판 %s" % [k, guard_times[k].died.size(), fmt_med(guard_times[k].died, "%.1f"), guard_times[k].alive.size(), fmt_med(guard_times[k].alive, "%.1f")])
	print("  큰 적 등장 → 죽음(초): " + " | ".join(PackedStringArray(gparts)))

## D17 3.3 classes: 무리 (walker / charger), 탄 (ranged), 큰 적 (elite / champion / boss / boss_ward), 기타 (floor hazards). A shot carries its owner's kind, so a ranged body = 탄.
func hit_cause(h: Dictionary) -> String:
	if h.is_empty(): return "(맞은 적 없음)"
	match String(h.kind):
		"walker", "charger": return "무리"
		"ranged": return "탄"
		"elite", "champion", "boss", "boss_ward": return "큰 적"
	return "기타(%s)" % String(h.kind)

## --stand-from: when it began to stand, when and where the hero fell, the cause, and whether the guardian of that zone had appeared by then (N94 3: it must fall BEFORE guardian 2).
func stand_from_line(r: Dictionary) -> String:
	var e: Dictionary = r.end
	var st: Dictionary = e.stand
	if not bool(st.started): return "  STAND-FROM %s %s seed=%d: 서기 시작 못 함(%s 마디가 시작되고 구역에 들어서기 전에 끝남, 끝 상태=%s %.1f초)" % [stand_from, r.primary, r.seed, stand_from, String(e.mode), float(e.s)]
	var zc = st.champions_s.get(int(st.zone), null)
	var champ_txt := "수호자 미등장" if zc == null else "수호자 등장 %.1f초" % float(zc)
	if String(e.mode) != "defeat":
		return "  STAND-FROM %s %s seed=%d: 서기 시작 %.1f초(구역 %d), 쓰러지지 않음(끝 %s %.1f초, 마디=%s), %s | 목표(수호자 전에 쓰러짐) 밖" % [stand_from, r.primary, r.seed, float(st.start_s), int(st.zone), String(e.mode), float(e.s), String(e.beat), champ_txt]
	var before: bool = zc == null or float(e.s) < float(zc)
	return "  STAND-FROM %s %s seed=%d: 서기 시작 %.1f초(구역 %d), 쓰러짐 %.1f초(서고 %.1f초 뒤), 마디=%s, 원인=%s, %s | 목표(수호자 전에 쓰러짐) %s" % [stand_from, r.primary, r.seed, float(st.start_s), int(st.zone), float(e.s), float(e.s) - float(st.start_s), String(e.beat), String(st.cause), champ_txt, ("안" if before else "밖(수호자 뒤)")]

## --stand: when the standing hero fell and in which beat / opening step (D22 R0-A).
func stand_line(r: Dictionary) -> String:
	var e: Dictionary = r.end
	var line := ""
	if String(e.mode) == "defeat":
		line = "  STAND %s seed=%d: 쓰러짐 %.1f초, 마디=%s, 도입부 단계=%s" % [r.primary, r.seed, float(e.s), String(e.beat), (String(e.opening_step) if bool(e.opening_active) else "(도입부 아님)")]
	else:
		line = "  STAND %s seed=%d: 쓰러지지 않음(끝 상태=%s %.1f초, 마디=%s)" % [r.primary, r.seed, String(e.mode), float(e.s), String(e.beat)]
	if targets_name == "d22": line += " | D22 3.4 서 있는 주인공: " + stand_verdict(e)
	return line

func stand_verdict(e: Dictionary) -> String:
	var t := target_of(String(e.beat))
	var fell := String(e.mode) == "defeat"
	if not fell: return "승 2 안에 쓰러지지 않음 = 목표 밖"
	if String(t.get("stand", "")) == "die_here": return "승 2 안에 쓰러짐 = 목표 안"
	if String(t.get("stand", "")) == "survive": return "%s에서 쓰러짐(서서 버텨야 하는 구간) = 목표 밖" % String(e.beat)
	return "%s에서 쓰러짐(승 2 뒤) = 목표 밖" % String(e.beat)

func print_stand_cross(runs: Array) -> void:
	var fell: Array = []
	var by_beat := {}
	var kept := 0
	for r in runs:
		if String(r.end.mode) == "defeat":
			fell.append(float(r.end.s))
			by_beat[String(r.end.beat)] = int(by_beat.get(String(r.end.beat), 0)) + 1
		else:
			kept += 1
	print("STAND across %d runs (measured, pilot casting, movement zeroed): 쓰러짐 %d판 / 끝까지 %d판 | 쓰러진 시각(초) %s | 쓰러진 마디 %s" % [runs.size(), fell.size(), kept, fmt_med(fell, "%.1f"), str(by_beat)])

func print_stand_from_cross(runs: Array) -> void:
	var fell: Array = []
	var before := 0
	var causes := {}
	var not_started := 0
	for r in runs:
		var st: Dictionary = r.end.stand
		if not bool(st.started):
			not_started += 1
			continue
		if String(r.end.mode) != "defeat": continue
		fell.append(float(r.end.s) - float(st.start_s))
		causes[String(st.cause)] = int(causes.get(String(st.cause), 0)) + 1
		var zc = st.champions_s.get(int(st.zone), null)
		if zc == null or float(r.end.s) < float(zc): before += 1
	print("STAND-FROM %s across %d runs (measured, pilot casting, movement zeroed from the zone entry): 쓰러짐 %d판 / 수호자 전에 쓰러짐 %d판 (목표 7/9) / 서기 시작 못 함 %d판 | 서고 나서 쓰러진 시간(초) %s | 원인 %s" % [stand_from, runs.size(), fell.size(), before, not_started, fmt_med(fell, "%.1f"), str(causes)])

## Crest peak / lull end, median per beat over all runs (--thirds).
func print_crest_lull(runs: Array) -> void:
	var cl := crest_lull_summary(runs)
	if cl.is_empty():
		print("  파도·골: 파도(wave_crest)·골(lull_started)이 없는 판(리듬 꺼짐)")
		return
	print("  파도·골(마디별 중앙; 파도 뒤 10초 살아 있는 적 최고 ÷ 마디 상한 / 골 끝(골 시작 + lull_ticks) 살아 있는 적 ÷ 마디 상한; n = 파도·골 수, 목표는 --targets=d22일 때):")
	var names: Array = []
	for b in targets: names.append(String(b.name))
	for k in cl:
		if not k in names: names.append(String(k))
	for k in names:
		if not cl.has(k): continue
		var d: Dictionary = cl[k]
		var t := target_of(String(k))
		var note := ""
		if targets_name == "d22" and not t.is_empty():
			if t.has("crest_min") and int(d.crest_n) > 0: note += " 머리 뒤 최고 ≥ %.2f: %s" % [float(t.crest_min), ("안" if float(d.crest_ratio_median) >= float(t.crest_min) else "낮음")]
			if t.has("crest_count_max") and int(d.crest_n) > 0: note += " 머리 뒤 최고 ≤ %d마리: %s" % [int(t.crest_count_max), ("안" if float(d.crest_max_median) <= float(t.crest_count_max) else "높음")]
			if t.has("lull_max") and int(d.lull_n) > 0: note += " 골 끝 ≤ %.2f: %s" % [float(t.lull_max), ("안" if float(d.lull_ratio_median) <= float(t.lull_max) else "높음")]
		print("    %-4s 머리 뒤 최고/상한 %.2f (최고 %.0f마리, n=%d) | 골 끝/상한 %.2f (n=%d)%s" % [k, float(d.crest_ratio_median), float(d.crest_max_median), int(d.crest_n), float(d.lull_ratio_median), int(d.lull_n), note])

func print_cross(c: Dictionary) -> void:
	print("CROSS beats (target vs value across runs that reached the beat; inside/low/high counts)")
	for b in targets:
		var row: Dictionary = c[String(b.name)]
		print("  %s runs=%d" % [b.name, row.runs_reached])
		for k in METRICS:
			var m: Dictionary = row.metrics[k]
			print("    %-9s target=%s median=%s min=%s max=%s in=%d low=%d high=%d" % [k, str(m.target), str(m.median), str(m.min), str(m.max), m.inside, m.low, m.high])
	print("CROSS kpm strictly rising 기<승1<승2<전A: %d/%d runs" % [c.kpm_ordered_runs, c.run_count])
