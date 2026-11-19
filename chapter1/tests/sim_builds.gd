extends SceneTree
## Build-spread meter (D11 G / D12 K1 measurement policy). Plays whole runs on the real core with the pilot's movement,
## equipment and potion logic UNCHANGED (chapter_pilot.gd is not edited), and replaces only the growth (grace) pick:
## while the core is in "choice" mode this tool picks the card by the chosen POLICY before pilot.decide() runs, so the pilot
## never sees a choice. Policy "pilot" lets the pilot pick (exactly the current behaviour = baseline).
## The policy RNG is a separate RandomNumberGenerator (seeded from run seed + policy index); it never touches the core's streams.
## It does not load chapter_profile.gd, never writes the user folder, and --out must be under _local/.
##   python tools/dev/godot.py --headless --path . --script res://chapter1/tests/sim_builds.gd -- --seeds=11 --runs=5 --primaries=ember,frost,arc --policies=pilot,random,worst,narrow --out=_local/builds/now.json [--rhythm-on]
## Bot results are stability/balance reference only. Fun is NOT evaluated here.
const Core = preload("res://chapter1/core/chapter_core.gd")
const Pilot = preload("res://chapter1/core/chapter_pilot.gd")

const ALL_POLICIES := ["pilot", "random", "worst", "narrow", "greedy_area", "greedy_single", "greedy_chain", "spread"]
## The card data has NO role field (only skill id, kind, numeric effects). Roles are assigned here by what the skill's numbers do:
## ember = projectiles + radius + death_burst (area burst), frost = pierce + slow + freeze + shatter (single line / control),
## arc = chain_targets + branches (chain). This table is a tool-side convention, not data.
const ROLE_OF := {"chapter1.skill.ember": "area", "chapter1.skill.frost": "single", "chapter1.skill.arc": "chain"}
const KIND_ORDER := {"evolve": 4, "rank": 3, "unlock": 2, "passive": 1}
## Time-table beats (D11 A2) used when the core does not emit beat_started (rhythm off).
const BEAT_TABLE := [["기", 60.0], ["승1", 130.0], ["승2", 285.0], ["전A", 345.0], ["전B", 390.0], ["전C", 1.0e9]]
const BEAT_NAMES := {"gi": "기", "seung1": "승1", "seung2": "승2", "jeon_a": "전A", "trial": "전B", "boss": "전C"}
const BEAT_ORDER := ["기", "승1", "승2", "전A", "전B", "전C"]
const MIN_TICKS := 300
const DIVERGE_KPM := 0.85
const DIVERGE_DMG := 1.25

var rhythm_on := false
## Step cap per run in seconds of game time. A run still going at the cap is recorded as "timeout" (neither win nor defeat).
var cap_s := 600.0

func _initialize() -> void:
	call_deferred("execute")

func execute() -> void:
	var seeds: Array = [11, 12, 13, 14, 15]
	var prims: Array = ["chapter1.skill.ember", "chapter1.skill.frost", "chapter1.skill.arc"]
	var policies: Array = ["pilot", "random", "worst", "narrow"]
	var runs_n := 0
	var merge: Array = []
	var out := "_local/builds/sim_builds.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seeds = []
			for p in arg.trim_prefix("--seeds=").split(","): seeds.append(int(p))
		elif arg.begins_with("--runs="): runs_n = maxi(1, int(arg.trim_prefix("--runs=")))
		elif arg.begins_with("--primaries="):
			prims = []
			for p in arg.trim_prefix("--primaries=").split(","):
				prims.append(p if p.begins_with("chapter1.skill.") else "chapter1.skill." + p)
		elif arg.begins_with("--policies="):
			policies = []
			var spec := arg.trim_prefix("--policies=")
			if spec == "all": policies = ALL_POLICIES.duplicate()
			else:
				for p in spec.split(","): policies.append(String(p))
		elif arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		elif arg == "--rhythm-on": rhythm_on = true
		elif arg.begins_with("--cap="): cap_s = maxf(60.0, float(arg.trim_prefix("--cap=")))
		elif arg.begins_with("--merge="):
			for p in arg.trim_prefix("--merge=").split(","): merge.append(String(p))
	if not out.begins_with("_local/") or out.contains("..") or out.contains(":") or out.begins_with("/"):
		push_error("sim_builds: --out must be a relative path under _local/ (got %s)" % out)
		quit(1)
		return
	for p in policies:
		if not p in ALL_POLICIES:
			push_error("sim_builds: unknown policy %s" % p)
			quit(1)
			return
	if runs_n > 0:
		var first: int = int(seeds[0]) if seeds.size() > 0 else 11
		seeds = []
		for i in runs_n: seeds.append(first + i)
	var runs: Array = []
	if not merge.is_empty():
		# Re-aggregate runs from earlier files (parallel processes write one file each). Nothing is played.
		prims = []
		policies = []
		seeds = []
		for m in merge:
			if not String(m).begins_with("_local/") or String(m).contains(".."):
				push_error("sim_builds: --merge files must be under _local/")
				quit(1)
				return
			var doc = JSON.parse_string(FileAccess.get_file_as_string("res://" + String(m)))
			if doc == null:
				push_error("sim_builds: cannot read %s" % m)
				quit(2)
				return
			rhythm_on = bool(doc.rhythm_on)
			for r in doc.runs:
				runs.append(r)
				var pk: String = "chapter1.skill." + String(r.primary)
				if not pk in prims: prims.append(pk)
				if not String(r.policy) in policies: policies.append(String(r.policy))
				if not int(r.seed) in seeds: seeds.append(int(r.seed))
		var ordered: Array = []
		for p in ALL_POLICIES:
			if p in policies: ordered.append(p)
		policies = ordered
		var ordered_p: Array = []
		for p in ["chapter1.skill.ember", "chapter1.skill.frost", "chapter1.skill.arc"]:
			if p in prims: ordered_p.append(p)
		prims = ordered_p
		seeds.sort()
	for prim in prims:
		for pol in policies:
			if not merge.is_empty(): break
			for s in seeds:
				var r := play(int(s), String(prim), String(pol))
				if r.is_empty():
					quit(2)
					return
				runs.append(r)
				print("RUN %-13s %-5s seed=%d %-7s secs=%6.1f kills=%4d lvl=%2d hp_end=%.2f potions=%d death=%s build=%s" % [r.policy, r.primary, r.seed, r.mode, r.secs, r.kills, r.level, r.hp_end, r.potions, r.death_beat, r.build_text])
	var groups := aggregate(runs, prims, policies)
	var gaps := gap_table(groups, prims, policies)
	print_tables(groups, gaps, prims, policies)
	var result := {"rhythm_on": rhythm_on, "cap_s": cap_s, "seeds": seeds, "primaries": prims, "policies": policies, "runs": runs, "groups": groups, "gaps": gaps,
		"thresholds": {"diverge_kpm_ratio_below": DIVERGE_KPM, "diverge_dmg30_ratio_above": DIVERGE_DMG},
		"roles": ROLE_OF, "note": "pilot movement/equipment/potions, no permanent tree, first_boss_kill=true; policy changes only the grace pick; bot results are stability/balance reference only, fun is unevaluated"}
	var abs_path := ProjectSettings.globalize_path("res://" + out)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		push_error("sim_builds: cannot write %s" % abs_path)
		quit(3)
		return
	f.store_string(JSON.stringify(result, "\t"))
	f.close()
	var brief: Array = []
	for pr in prims:
		for pol in policies:
			var g: Dictionary = groups[group_key(String(pol), String(pr))]
			brief.append({"policy": pol, "primary": String(pr).trim_prefix("chapter1.skill."), "n": g.n, "wins": g.wins, "win_rate": g.win_rate, "secs_median": g.secs_median})
	print("CHAPTER1_SIM_BUILDS_RESULT " + JSON.stringify({"out": out, "rhythm_on": rhythm_on, "groups": brief}))
	quit(0)

# ---------- growth pick policies ----------
func pilot_score(card: Dictionary, primary: String) -> int:
	# Same numbers as chapter_pilot.gd decide() (copied; the pilot file is not touched).
	var score := 10
	if card.skill_id == primary: score = 100 if card.kind == "evolve" else (90 if card.kind == "rank" else 80)
	elif card.kind == "unlock": score = 65
	elif card.kind == "evolve": score = 60
	elif card.kind == "rank": score = 50
	return score

func argmin_pilot(cards: Array, primary: String) -> int:
	var best := 0
	var bs := 1 << 30
	for i in cards.size():
		var s := pilot_score(cards[i], primary)
		if s < bs:
			bs = s
			best = i
	return best

func argmax_pilot(cards: Array, primary: String) -> int:
	var best := 0
	var bs := -1
	for i in cards.size():
		var s := pilot_score(cards[i], primary)
		if s > bs:
			bs = s
			best = i
	return best

func pick(policy: String, cards: Array, run, rng: RandomNumberGenerator) -> int:
	var snap: Dictionary = run.growth.snapshot()
	var primary: String = String(snap.primary)
	match policy:
		"random":
			return rng.randi_range(0, cards.size() - 1)
		"worst":
			return argmin_pilot(cards, primary)
		"narrow":
			# Only the primary's own cards (rank / passive / evolve); when none is offered take the pilot's lowest score.
			var best := -1
			var bs := -1
			for i in cards.size():
				if cards[i].skill_id == primary:
					var s := pilot_score(cards[i], primary)
					if s > bs:
						bs = s
						best = i
			return best if best >= 0 else argmin_pilot(cards, primary)
		"spread":
			# The card of the skill with the fewest ranks so far (unlock = 0), ties by the pilot score.
			var best2 := 0
			var key := Vector2i(1 << 30, -1)
			for i in cards.size():
				var rk: int = int(snap.ranks.get(cards[i].skill_id, 0))
				var k := Vector2i(rk, -pilot_score(cards[i], primary))
				if k.x < key.x or (k.x == key.x and k.y < key.y):
					key = k
					best2 = i
			return best2
		"greedy_area", "greedy_single", "greedy_chain":
			var role := policy.trim_prefix("greedy_")
			var best3 := -1
			var bo := -1
			for i in cards.size():
				if String(ROLE_OF.get(cards[i].skill_id, "")) == role:
					var o: int = int(KIND_ORDER.get(cards[i].kind, 0))
					if o > bo:
						bo = o
						best3 = i
			return best3 if best3 >= 0 else argmax_pilot(cards, primary)
	return argmax_pilot(cards, primary)

# ---------- one run ----------
func new_beat() -> Dictionary:
	return {"ticks": 0, "kills": 0, "alive_sum": 0, "alive_n": 0, "alive_max": 0, "hits": 0, "dmg": 0.0}

func beat_by_time(sec: float) -> String:
	for b in BEAT_TABLE:
		if sec < float(b[1]): return String(b[0])
	return "전C"

func play(seed_: int, prim: String, policy: String) -> Dictionary:
	var run = Core.new()
	var pilot = Pilot.new()
	pilot.run = run
	run.first_boss_kill = true
	if rhythm_on:
		var doc = JSON.parse_string(FileAccess.get_file_as_string("res://chapter1/data/combat_tuning.json"))
		doc.rhythm.enabled = true
		doc.rhythm.trial.enabled = true
		if not run.set_tuning(doc):
			push_error("sim_builds: rhythm document rejected %s" % str(run.errors))
			return {}
	if not run.start(seed_, prim):
		push_error("sim_builds: start failed %s" % str(run.errors))
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = (seed_ * 2654435761) ^ (ALL_POLICIES.find(policy) * 40503 + 977)
	var beats: Dictionary = {}
	var event_beats := false
	var cur_beat := "기"
	var last_seq := -1
	var last_tick: int = int(run.tick)
	var last_kills := 0
	var guard := 0
	var picks: Array = []
	var dmg_total := 0.0
	var hits_total := 0
	var min_hp := 1.0
	var marks: Array = []
	while run.mode not in ["victory", "defeat"] and guard < int(cap_s * 60.0):
		if policy != "pilot":
			var g2 := 0
			while run.mode == "choice" and g2 < 64:
				g2 += 1
				var offer: Dictionary = run.get_offer()
				var cards: Array = offer.cards
				var chosen: Dictionary = cards[pick(policy, cards, run, rng)]
				pilot.selections.append({"tick": run.tick, "id": chosen.id, "kind": chosen.kind})
				if not run.choose(offer.token, chosen.id):
					push_error("sim_builds: choice rejected %s" % str(run.errors))
					return {}
		var mv: Vector2 = pilot.decide()
		run.step(mv)
		guard += 1
		var adv: int = int(run.tick) - last_tick
		last_tick = int(run.tick)
		var sec: float = float(run.tick) / 60.0
		for ev in run.events:
			if int(ev.seq) <= last_seq: continue
			last_seq = int(ev.seq)
			var t := String(ev.type)
			if t == "beat_started":
				event_beats = true
				var raw := str(ev.get("id", ev.get("beat", ev.get("name", ""))))
				cur_beat = String(BEAT_NAMES.get(raw, raw))
				marks.append("%.0fs %s" % [float(ev.tick) / 60.0, cur_beat])
			elif t == "hero_hit":
				var bn0 := cur_beat if event_beats else beat_by_time(float(ev.tick) / 60.0)
				if not beats.has(bn0): beats[bn0] = new_beat()
				var d: float = float(ev.get("damage_raw", 0)) / maxf(1.0, float(run.hero.max_hp_raw))
				beats[bn0].hits += 1
				beats[bn0].dmg += d
				dmg_total += d
				hits_total += 1
		var bn := cur_beat if event_beats else beat_by_time(sec)
		if not beats.has(bn): beats[bn] = new_beat()
		var b: Dictionary = beats[bn]
		b.ticks += maxi(0, adv)
		var kd: int = int(run.kills) - last_kills
		last_kills = int(run.kills)
		b.kills += maxi(0, kd)
		var n: int = run.alive_count()
		b.alive_max = maxi(int(b.alive_max), n)
		if adv > 0 and int(run.tick) % 6 == 0:
			b.alive_sum += n
			b.alive_n += 1
		min_hp = minf(min_hp, float(run.hero.hp_raw) / maxf(1.0, float(run.hero.max_hp_raw)))
	var snap: Dictionary = run.growth.snapshot()
	var secs: float = float(run.tick) / 60.0
	var end_beat: String = cur_beat if event_beats else beat_by_time(secs)
	var mode := String(run.mode)
	var hp_end := maxf(0.0, float(run.hero.hp_raw) / maxf(1.0, float(run.hero.max_hp_raw)))
	var ranks: Dictionary = {}
	for k in snap.ranks: ranks[String(k).trim_prefix("chapter1.skill.")] = int(snap.ranks[k])
	var passives: Array = snap.passives.map(func(p): return String(p).trim_prefix("chapter1.passive."))
	var evolved: Array = snap.evolved.map(func(p): return String(p).trim_prefix("chapter1.skill."))
	var rank_parts: Array = []
	for k in ranks: rank_parts.append("%s%d" % [String(k).substr(0, 2), ranks[k]])
	var build_text := "%s p%d e%d" % [",".join(PackedStringArray(rank_parts)), passives.size(), evolved.size()]
	var beat_out: Dictionary = {}
	for k in beats: beat_out[k] = beats[k]
	var pos: Vector2 = run.hero.position
	return {"policy": policy, "primary": prim.trim_prefix("chapter1.skill."), "seed": seed_, "mode": mode, "secs": snappedf(secs, 0.1),
		"kills": int(run.kills), "level": int(snap.level), "hp_end": snappedf(hp_end, 0.01), "hp_min": snappedf(min_hp, 0.01),
		"potions": int(pilot.potion_uses), "dmg_total": snappedf(dmg_total, 0.001), "hits_total": hits_total,
		"death_beat": ("-" if mode == "victory" else (end_beat if mode == "defeat" else "T:" + end_beat)), "death_s": snappedf(secs, 0.1) if mode == "defeat" else -1.0,
		"death_zone": int(run.zone) if mode == "defeat" else -1, "death_pos": [snappedf(pos.x, 0.1), snappedf(pos.y, 0.1)] if mode == "defeat" else [],
		"ranks": ranks, "passives": passives, "evolved": evolved, "build_text": build_text, "beat_source": "beat_started event" if event_beats else "time table (A2)",
		"picks": pilot.selections.map(func(s): return String(s.id).replace("chapter1.", "")), "beats": beat_out, "marks": marks}

# ---------- aggregation ----------
func group_key(policy: String, prim: String) -> String:
	return "%s|%s" % [policy, prim.trim_prefix("chapter1.skill.")]

func median(arr: Array) -> float:
	if arr.is_empty(): return 0.0
	var s := arr.duplicate()
	s.sort()
	var n := s.size()
	return float(s[n / 2]) if n % 2 == 1 else (float(s[n / 2 - 1]) + float(s[n / 2])) * 0.5

func mean(arr: Array) -> float:
	if arr.is_empty(): return 0.0
	var t := 0.0
	for v in arr: t += float(v)
	return t / float(arr.size())

func aggregate(runs: Array, prims: Array, policies: Array) -> Dictionary:
	var groups: Dictionary = {}
	for pr in prims:
		for pol in policies:
			var key := group_key(String(pol), String(pr))
			var rs: Array = runs.filter(func(r): return String(r.policy) == String(pol) and String(r.primary) == String(pr).trim_prefix("chapter1.skill."))
			var wins := 0
			var timeouts := 0
			var secs: Array = []
			var hp_end: Array = []
			var potions: Array = []
			var dmg: Array = []
			var kills_pm: Array = []
			var death_beats: Dictionary = {}
			var death_times: Array = []
			var rank_sum: Dictionary = {}
			var pas := 0.0
			var evo := 0.0
			var level: Array = []
			for r in rs:
				if r.mode == "victory": wins += 1
				elif r.mode != "defeat": timeouts += 1
				secs.append(r.secs)
				potions.append(r.potions)
				dmg.append(r.dmg_total)
				level.append(r.level)
				kills_pm.append(float(r.kills) / maxf(0.1, float(r.secs)) * 60.0)
				if r.mode == "victory": hp_end.append(r.hp_end)
				else:
					death_beats[r.death_beat] = int(death_beats.get(r.death_beat, 0)) + 1
					if r.mode == "defeat": death_times.append(r.death_s)
				for k in r.ranks: rank_sum[k] = float(rank_sum.get(k, 0.0)) + float(r.ranks[k])
				pas += float(r.passives.size())
				evo += float(r.evolved.size())
			var n := rs.size()
			var rank_mean: Dictionary = {}
			for k in rank_sum: rank_mean[k] = snappedf(float(rank_sum[k]) / maxf(1.0, float(n)), 0.1)
			var per_beat: Dictionary = {}
			for bname in BEAT_ORDER:
				var ticks := 0
				var kills := 0
				var alive_sum := 0
				var alive_n := 0
				var dm := 0.0
				var hits := 0
				var reached := 0
				for r in rs:
					if not r.beats.has(bname): continue
					var b: Dictionary = r.beats[bname]
					if int(b.ticks) < MIN_TICKS: continue
					reached += 1
					ticks += int(b.ticks)
					kills += int(b.kills)
					alive_sum += int(b.alive_sum)
					alive_n += int(b.alive_n)
					dm += float(b.dmg)
					hits += int(b.hits)
				var mins: float = float(ticks) / 3600.0
				per_beat[bname] = {"reached": reached, "secs": snappedf(float(ticks) / 60.0, 0.1), "kpm": snappedf(float(kills) / maxf(mins, 0.001), 0.1) if reached > 0 else 0.0,
					"alive_avg": snappedf(float(alive_sum) / maxf(1.0, float(alive_n)), 0.1), "dmg30": snappedf(dm / maxf(mins * 2.0, 0.001), 0.001) if reached > 0 else 0.0,
					"dmg": snappedf(dm / maxf(1.0, float(reached)), 0.001), "hits": hits}
			groups[key] = {"policy": pol, "primary": String(pr).trim_prefix("chapter1.skill."), "n": n, "wins": wins, "timeouts": timeouts,
				"win_rate": snappedf(float(wins) / maxf(1.0, float(n)), 0.01), "secs_median": snappedf(median(secs), 0.1), "secs_min": snappedf(float(secs.min()) if n > 0 else 0.0, 0.1),
				"secs_max": snappedf(float(secs.max()) if n > 0 else 0.0, 0.1), "hp_end_mean_wins": snappedf(mean(hp_end), 0.01), "potions_mean": snappedf(mean(potions), 0.1),
				"dmg_total_mean": snappedf(mean(dmg), 0.01), "kills_per_min_mean": snappedf(mean(kills_pm), 1.0), "level_mean": snappedf(mean(level), 0.1),
				"death_beats": death_beats, "death_times": death_times, "rank_mean": rank_mean, "passives_mean": snappedf(pas / maxf(1.0, float(n)), 0.1),
				"evolved_mean": snappedf(evo / maxf(1.0, float(n)), 0.1), "per_beat": per_beat}
	return groups

## Per primary and policy: per beat, kpm and dmg30 ratio to the pilot policy, and the first beat that crosses the thresholds.
## Caveat (survivorship): a beat is only counted from runs that reached it (>= 5 s), so a policy that dies early is compared on a thinner sample.
func gap_table(groups: Dictionary, prims: Array, policies: Array) -> Dictionary:
	var out: Dictionary = {}
	if not "pilot" in policies: return out
	for pr in prims:
		var short := String(pr).trim_prefix("chapter1.skill.")
		var base: Dictionary = groups[group_key("pilot", short)]
		for pol in policies:
			if pol == "pilot": continue
			var g: Dictionary = groups[group_key(String(pol), short)]
			var rows: Dictionary = {}
			var first := "-"
			for bname in BEAT_ORDER:
				var a: Dictionary = g.per_beat[bname]
				var b: Dictionary = base.per_beat[bname]
				if int(a.reached) == 0 or int(b.reached) == 0:
					rows[bname] = {"kpm_ratio": null, "dmg30_ratio": null, "reached": a.reached, "base_reached": b.reached}
					continue
				var kr: float = float(a.kpm) / maxf(0.001, float(b.kpm))
				var dr: float = float(a.dmg30) / maxf(0.001, float(b.dmg30)) if float(b.dmg30) > 0.0 else -1.0
				rows[bname] = {"kpm_ratio": snappedf(kr, 0.01), "dmg30_ratio": snappedf(dr, 0.01), "reached": a.reached, "base_reached": b.reached}
				if first == "-" and (kr < DIVERGE_KPM or dr > DIVERGE_DMG): first = bname
			out[group_key(String(pol), short)] = {"win_rate_delta": snappedf(float(g.win_rate) - float(base.win_rate), 0.01), "first_diverging_beat": first, "beats": rows}
	return out

# ---------- printing ----------
func print_tables(groups: Dictionary, gaps: Dictionary, prims: Array, policies: Array) -> void:
	print("== TABLE A: policy x primary (rhythm_on=%s) ==" % str(rhythm_on))
	print("policy        prim  n  win%%  secs(med min-max)   kill/min lvl  hp_end potions dmg(xHP) | death beats | final build (mean ranks, passives, evolved)")
	for pr in prims:
		for pol in policies:
			var g: Dictionary = groups[group_key(String(pol), String(pr).trim_prefix("chapter1.skill."))]
			var rm := []
			for k in g.rank_mean: rm.append("%s%.1f" % [String(k).substr(0, 2), g.rank_mean[k]])
			print("%-13s %-5s %2d %4.0f%% %6.1f %5.1f-%5.1f  %7.0f %4.1f  %5.2f %6.1f %7.2f | %s | %s p%.1f e%.1f" % [g.policy, g.primary, g.n, float(g.win_rate) * 100.0, g.secs_median, g.secs_min, g.secs_max,
				g.kills_per_min_mean, g.level_mean, g.hp_end_mean_wins, g.potions_mean, g.dmg_total_mean, str(g.death_beats), " ".join(PackedStringArray(rm)), g.passives_mean, g.evolved_mean])
	print("== TABLE B: per beat (kpm / alive_avg / dmg30 = damage per 30 s as a share of max HP; reached runs) ==")
	for pr in prims:
		var short := String(pr).trim_prefix("chapter1.skill.")
		print("-- primary %s" % short)
		print("policy        " + " | ".join(PackedStringArray(BEAT_ORDER.map(func(b): return "%-26s" % b))))
		for pol in policies:
			var g: Dictionary = groups[group_key(String(pol), short)]
			var cells: Array = []
			for bname in BEAT_ORDER:
				var b: Dictionary = g.per_beat[bname]
				cells.append("n%d k%4.0f a%4.1f d%5.2f      " % [b.reached, b.kpm, b.alive_avg, b.dmg30])
			print("%-13s %s" % [pol, " | ".join(PackedStringArray(cells))])
	print("== TABLE C: ratio to pilot per beat (kpm_ratio/dmg30_ratio); first diverging beat = kpm<%.2f or dmg30>%.2f ==" % [DIVERGE_KPM, DIVERGE_DMG])
	for key in gaps:
		var gp: Dictionary = gaps[key]
		var cells: Array = []
		for bname in BEAT_ORDER:
			var r: Dictionary = gp.beats[bname]
			cells.append("%s %s/%s" % [bname, ("-" if r.kpm_ratio == null else "%.2f" % float(r.kpm_ratio)), ("-" if r.dmg30_ratio == null else "%.2f" % float(r.dmg30_ratio))])
		print("%-20s dWin=%+.2f first=%-3s | %s" % [key, gp.win_rate_delta, gp.first_diverging_beat, "  ".join(PackedStringArray(cells))])
