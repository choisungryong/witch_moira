extends SceneTree
## Build-spread meter (D11 G / D12 K1 measurement policy). Plays whole runs on the real core with the pilot's movement,
## equipment and potion logic UNCHANGED (chapter_pilot.gd is not edited), and replaces only the growth (grace) pick:
## while the core is in "choice" mode this tool picks the card by the chosen POLICY before pilot.decide() runs, so the pilot
## never sees a choice. Policy "pilot" lets the pilot pick (exactly the current behaviour = baseline).
## The policy RNG is a separate RandomNumberGenerator (seeded from run seed + policy index); it never touches the core's streams.
## It does not load chapter_profile.gd, never writes the user folder, and --out must be under _local/.
##   python tools/dev/godot.py --headless --path . --script res://chapter1/tests/sim_builds.gd -- --seeds=11 --runs=5 --primaries=ember,frost,arc --policies=pilot,random,worst,narrow --out=_local/builds/now.json [--rhythm-on]
##   --no-equip   baseline state (D12 P10): dropped gear is picked up but never worn.   --policies=all   every policy.
##   15 runs per cell: --runs=15 (seeds 11..25). A cell can be split over processes with --seeds=<first> --runs=<n> and recombined with --merge=<files> --out=...
##   (merge re-aggregates; it keeps the rhythm_on / no_equip flags of the files, which must agree).
## Bot results are stability/balance reference only. Fun is NOT evaluated here.
const Core = preload("res://chapter1/core/chapter_core.gd")
const Pilot = preload("res://chapter1/core/chapter_pilot.gd")

## "synergy_now" is appended LAST on purpose: the policy RNG seed uses the index in this list, so inserting earlier would change the old runs.
const ALL_POLICIES := ["pilot", "random", "worst", "narrow", "greedy_area", "greedy_single", "greedy_chain", "spread", "synergy_now"]
## Loss-cause classification (D12 P8, adapted to what the core exposes; see classify_end). The window is the last 30 s of game time.
const CAUSE_WINDOW_TICKS := 1800
const CROWD_ALIVE_SHARE := 0.8
const STRONG_FIGHT_FACTOR := 1.5
const ELITE_WINDOW_S := 8.0
const CHAMPION_WINDOW_S := [25.0, 30.0, 40.0]
const CAUSES := ["crowd", "strong", "both", "other"]
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
## --no-equip: the baseline state of D12 P10 (8 empty gear slots). Items still drop and are picked up exactly as before (same RNG flow);
## the tool only hides the inventory from pilot.decide() for that one call so the pilot never finds anything to equip.
var no_equip := false

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
		elif arg == "--no-equip": no_equip = true
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
			no_equip = bool(doc.get("no_equip", false))
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
				print("RUN %-13s %-5s seed=%d %-7s secs=%6.1f kills=%4d lvl=%2d hp_end=%.2f potions=%d death=%s cause=%s equipped=%d inv=%d build=%s" % [r.policy, r.primary, r.seed, r.mode, r.secs, r.kills, r.level, r.hp_end, r.potions, r.death_beat, r.cause, r.equipped_end, r.inventory_end, r.build_text])
	var groups := aggregate(runs, prims, policies)
	var gaps := gap_table(groups, prims, policies)
	var summary := policy_summary(groups, prims, policies)
	var verdict := rank_verdict(summary, groups, prims)
	print_tables(groups, gaps, prims, policies)
	print_summary(summary, verdict, prims)
	var result := {"rhythm_on": rhythm_on, "no_equip": no_equip, "summary": summary, "rank_verdict": verdict, "cause_rules": {"window_s": CAUSE_WINDOW_TICKS / 60, "crowd_alive_share_of_cap": CROWD_ALIVE_SHARE,
			"strong_fight_factor": STRONG_FIGHT_FACTOR, "elite_window_s": ELITE_WINDOW_S, "champion_window_s": CHAMPION_WINDOW_S},"cap_s": cap_s, "seeds": seeds, "primaries": prims, "policies": policies, "runs": runs, "groups": groups, "gaps": gaps,
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
	print("CHAPTER1_SIM_BUILDS_RESULT " + JSON.stringify({"out": out, "rhythm_on": rhythm_on, "no_equip": no_equip, "groups": brief, "rank_verdict": verdict}))
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

## Policy "synergy_now": plays the synergies the CURRENT data really has. There are exactly two (read from the data, not invented):
##  (1) Mark resonance (combat_tuning.json marks {mark_bps 9000, mark_ticks 360}; chapter_core.gd hit logic): a hit of the primary on an enemy
##      that a secondary skill marked in the last 6 s deals +90% per live mark. A secondary only marks once it has been unlocked (a card) and
##      it marks as many enemies as it hits, so a ranked secondary keeps more marks alive. Both secondaries unlocked = up to +180%.
##  (2) Crystal card + evolution (growth_quality37.json passive_id / evolution): evolve:<skill> needs rank 4 AND that skill's passive card.
## There is no skill tree in the baseline state (no permanent tree) and no cross-skill rule beyond these two.
## Order: evolve the primary > primary rank 2 (the base) > unlock a secondary (opens a mark) > the primary's crystal card > primary rank 3-4
##        > the lowest-ranked secondary's rank card (keeps marks alive) > pilot score.
## ---- Place for the new skill composition (run_spells.json does NOT exist yet; not created here) ----
## When docs/specs/D12 B0's run_spells.json arrives, build this policy from its fields instead of the table above: read each spell's role
## (single / around-hero circle / other), its pair field (which spell/element it combos with) and its axis (damage / range) from the file,
## and score a card by "fills a missing role" + "adds to the axis the pair needs" + "completes a pair". Keep the old two-rule version as
## "synergy_now" so the old numbers stay reproducible; name the new one e.g. "synergy_spells".
func pick_synergy_now(cards: Array, snap: Dictionary, primary: String) -> int:
	var best := 0
	var bs := -1
	for i in cards.size():
		var c: Dictionary = cards[i]
		var sk: String = String(c.skill_id)
		var rk: int = int(snap.ranks.get(sk, 0))
		var prim_rk: int = int(snap.ranks.get(primary, 1))
		var score := 10
		if sk == primary:
			if c.kind == "evolve": score = 100
			elif c.kind == "rank" and int(c.rank) == 2: score = 90
			elif c.kind == "passive": score = 70
			elif c.kind == "rank": score = 60
			else: score = 50
		else:
			if c.kind == "unlock": score = 80 if prim_rk >= 2 else 55
			elif c.kind == "rank": score = 55 - rk * 3
			else: score = 20
		if score > bs:
			bs = score
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
		"synergy_now":
			return pick_synergy_now(cards, snap, primary)
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
	var samples: Array = []
	var hit_log: Array = []
	var elite_first: Dictionary = {}
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
		var hidden_inv: Array = []
		if no_equip:
			# Hide the inventory from the pilot for this call only; restored before the core steps, so drops/pickups are untouched.
			hidden_inv = run.inventory.duplicate()
			run.inventory.clear()
		var mv: Vector2 = pilot.decide()
		if no_equip:
			run.inventory.assign(hidden_inv)
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
				# Attribution is approximate: `from` is the attacker's position for melee/circle hits and a projectile or hazard position
				# otherwise. A hit counts as "from a strong enemy" when the nearest living enemy within 1.5 m of `from` is an elite.
				var src_elite := false
				var from_pos: Vector2 = ev.get("from", Vector2(1.0e6, 1.0e6))
				var nd := 2.25
				for e in run.enemies.values():
					if e.hp_raw <= 0: continue
					var dd: float = from_pos.distance_squared_to(e.position)
					if dd < nd:
						nd = dd
						src_elite = bool(e.elite)
				hit_log.append([int(ev.tick), d, src_elite])
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
			# One sample per 0.1 s for the loss-cause window: living enemies, elites alive and how long the longest-lived one has been fought.
			var elite_n := 0
			var fight_ratio := 0.0
			var fight_s := 0.0
			var live_ids: Dictionary = {}
			for e in run.enemies.values():
				if e.hp_raw <= 0 or not bool(e.elite): continue
				elite_n += 1
				var eid: int = int(e.id)
				live_ids[eid] = true
				if not elite_first.has(eid): elite_first[eid] = int(run.tick)
				var win_s := ELITE_WINDOW_S
				if String(e.get("title_key", "")) != "": win_s = float(CHAMPION_WINDOW_S[clampi(int(run.zone), 0, 2)])
				var fs: float = float(int(run.tick) - int(elite_first[eid])) / 60.0
				if fs / win_s > fight_ratio:
					fight_ratio = fs / win_s
					fight_s = fs
			samples.append([int(run.tick), n, elite_n, fight_ratio, fight_s])
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
	var cause_info: Dictionary = {"cause": "-"} if mode == "victory" else classify_end(samples, hit_log, int(run.tick), int(run.tuning.alive_cap))
	return {"no_equip": no_equip, "equipped_end": run.equipped.size(), "inventory_end": run.inventory.size(), "cause": cause_info.cause, "cause_detail": cause_info,
		"policy": policy, "primary": prim.trim_prefix("chapter1.skill."), "seed": seed_, "mode": mode, "secs": snappedf(secs, 0.1),
		"kills": int(run.kills), "level": int(snap.level), "hp_end": snappedf(hp_end, 0.01), "hp_min": snappedf(min_hp, 0.01),
		"potions": int(pilot.potion_uses), "dmg_total": snappedf(dmg_total, 0.001), "hits_total": hits_total,
		"death_beat": ("-" if mode == "victory" else (end_beat if mode == "defeat" else "T:" + end_beat)), "death_s": snappedf(secs, 0.1) if mode == "defeat" else -1.0,
		"death_zone": int(run.zone) if mode == "defeat" else -1, "death_pos": [snappedf(pos.x, 0.1), snappedf(pos.y, 0.1)] if mode == "defeat" else [],
		"ranks": ranks, "passives": passives, "evolved": evolved, "build_text": build_text, "beat_source": "beat_started event" if event_beats else "time table (A2)",
		"picks": pilot.selections.map(func(s): return String(s.id).replace("chapter1.", "")), "beats": beat_out, "marks": marks}

## Loss-cause classification for a run that ended in defeat or at the time cap (state of the last 30 s of game time).
## D12 P8 gives: crowd = living enemies >= 80% of the cap and >= 60% of the damage from common contact; single-shortage = an elite/guardian/boss
## alive with >= 50% of the damage from it OR a fight longer than the allowed window x 1.5. The core's hero_hit event has no attacker id, so:
##  - crowd  : mean living enemies over the last 30 s >= CROWD_ALIVE_SHARE x tuning.alive_cap (the 60%-of-damage clause is NOT used; stated limit).
##  - strong : at the end an elite is alive whose fight time (time since first seen alive) > STRONG_FIGHT_FACTOR x its window
##             (plain elite 8 s; seal champion 25/30/40 s by zone, D12 P2), OR >= 50% of the damage taken in the window is attributed to elites
##             (nearest-living-enemy attribution of the hit position; undercounts elite projectiles/hazards) with an elite alive at some sample.
##  - both   : both of the above. other : neither (a fast death, charges, ranged fire...).
## A time-cap run (the hero neither died nor won) is classified the same way and kept apart as a timeout.
func classify_end(samples: Array, hit_log: Array, end_tick: int, alive_cap: int) -> Dictionary:
	var from_tick := end_tick - CAUSE_WINDOW_TICKS
	var alive_sum := 0.0
	var alive_n := 0
	var elite_samples := 0
	for s in samples:
		if int(s[0]) < from_tick: continue
		alive_sum += float(s[1])
		alive_n += 1
		if int(s[2]) > 0: elite_samples += 1
	var alive_mean := alive_sum / maxf(1.0, float(alive_n))
	var last_ratio := 0.0
	var last_fight_s := 0.0
	var last_elite := 0
	if not samples.is_empty():
		var ls: Array = samples[samples.size() - 1]
		last_elite = int(ls[2])
		last_ratio = float(ls[3])
		last_fight_s = float(ls[4])
	var dmg_all := 0.0
	var dmg_elite := 0.0
	for h in hit_log:
		if int(h[0]) < from_tick: continue
		dmg_all += float(h[1])
		if bool(h[2]): dmg_elite += float(h[1])
	var elite_share := dmg_elite / dmg_all if dmg_all > 0.0 else 0.0
	var crowd: bool = alive_mean >= CROWD_ALIVE_SHARE * float(alive_cap)
	var strong: bool = (last_elite > 0 and last_ratio > STRONG_FIGHT_FACTOR) or (elite_samples > 0 and elite_share >= 0.5)
	var cause := "other"
	if crowd and strong: cause = "both"
	elif crowd: cause = "crowd"
	elif strong: cause = "strong"
	return {"cause": cause, "alive_mean_30s": snappedf(alive_mean, 0.1), "alive_cap": alive_cap, "elite_alive_samples_share": snappedf(float(elite_samples) / maxf(1.0, float(alive_n)), 0.01),
		"elite_fight_s_end": snappedf(last_fight_s, 0.1), "elite_fight_ratio_end": snappedf(last_ratio, 0.01), "elite_dmg_share_30s": snappedf(elite_share, 0.01), "dmg_30s": snappedf(dmg_all, 0.001)}

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
			var defeat_causes: Dictionary = {}
			var timeout_causes: Dictionary = {}
			for c in CAUSES:
				defeat_causes[c] = 0
				timeout_causes[c] = 0
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
					var cz := String(r.get("cause", "other"))
					if not cz in CAUSES: cz = "other"
					if r.mode == "defeat": defeat_causes[cz] = int(defeat_causes[cz]) + 1
					else: timeout_causes[cz] = int(timeout_causes[cz]) + 1
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
				"defeat_causes": defeat_causes, "timeout_causes": timeout_causes, "death_beats": death_beats, "death_times": death_times, "rank_mean": rank_mean, "passives_mean": snappedf(pas / maxf(1.0, float(n)), 0.1),
				"evolved_mean": snappedf(evo / maxf(1.0, float(n)), 0.1), "per_beat": per_beat}
	return groups

## Per policy across the primaries: win rate, defeat-cause shares, timeout share. n counts every run of the policy (primaries x runs).
func policy_summary(groups: Dictionary, prims: Array, policies: Array) -> Dictionary:
	var out: Dictionary = {}
	for pol in policies:
		var n := 0
		var wins := 0
		var timeouts := 0
		var defeats := 0
		var dc: Dictionary = {}
		var tc: Dictionary = {}
		for c in CAUSES:
			dc[c] = 0
			tc[c] = 0
		var per_primary: Dictionary = {}
		var kpm_sum := 0.0
		var secs_sum := 0.0
		var boss_end := 0
		for pr in prims:
			var short := String(pr).trim_prefix("chapter1.skill.")
			var g: Dictionary = groups[group_key(String(pol), short)]
			n += int(g.n)
			wins += int(g.wins)
			timeouts += int(g.timeouts)
			defeats += int(g.n) - int(g.wins) - int(g.timeouts)
			for c in CAUSES:
				dc[c] = int(dc[c]) + int(g.defeat_causes[c])
				tc[c] = int(tc[c]) + int(g.timeout_causes[c])
			per_primary[short] = g.win_rate
			kpm_sum += float(g.kills_per_min_mean)
			secs_sum += float(g.secs_median)
			for k in g.death_beats:
				if String(k).ends_with("전C"): boss_end += int(g.death_beats[k])
		var dratio: Dictionary = {}
		for c in CAUSES: dratio[c] = snappedf(float(dc[c]) / float(defeats), 0.01) if defeats > 0 else 0.0
		out[String(pol)] = {"n": n, "wins": wins, "win_rate": snappedf(float(wins) / maxf(1.0, float(n)), 0.001), "defeats": defeats, "timeouts": timeouts,
			"timeout_rate": snappedf(float(timeouts) / maxf(1.0, float(n)), 0.001), "defeat_causes": dc, "defeat_cause_ratio": dratio, "timeout_causes": tc, "win_by_primary": per_primary,
			"kills_per_min_mean": snappedf(kpm_sum / maxf(1.0, float(prims.size())), 1.0), "secs_median_mean_of_primaries": snappedf(secs_sum / maxf(1.0, float(prims.size())), 0.1),
			"ended_at_boss_beat_non_win": boss_end}
	return out

## Rank check: target order synergy_now > narrow > random (user's rule, D12 P0). Reports each gap in percentage points, overall and per primary.
## Holds only when both gaps are strictly positive. Nothing is judged when a needed policy was not run.
func rank_verdict(summary: Dictionary, groups: Dictionary, prims: Array) -> Dictionary:
	if not (summary.has("synergy_now") and summary.has("narrow") and summary.has("random")): return {"evaluated": false}
	var s: float = float(summary.synergy_now.win_rate)
	var nw: float = float(summary.narrow.win_rate)
	var r: float = float(summary.random.win_rate)
	var by_primary: Dictionary = {}
	for pr in prims:
		var short := String(pr).trim_prefix("chapter1.skill.")
		var ps: float = float(groups[group_key("synergy_now", short)].win_rate)
		var pn: float = float(groups[group_key("narrow", short)].win_rate)
		var prr: float = float(groups[group_key("random", short)].win_rate)
		by_primary[short] = {"synergy_minus_narrow_pp": snappedf((ps - pn) * 100.0, 0.1), "narrow_minus_random_pp": snappedf((pn - prr) * 100.0, 0.1), "holds": ps > pn and pn > prr}
	var d1 := snappedf((s - nw) * 100.0, 0.1)
	var d2 := snappedf((nw - r) * 100.0, 0.1)
	var extra: Dictionary = {}
	if summary.has("pilot"): extra["synergy_minus_pilot_pp"] = snappedf((s - float(summary.pilot.win_rate)) * 100.0, 0.1)
	if summary.has("spread"): extra["random_minus_spread_pp"] = snappedf((r - float(summary.spread.win_rate)) * 100.0, 0.1)
	# When every win rate is saturated (e.g. 0% in the no-equip baseline) the win gap says nothing; the same order is also checked on kills/min.
	var ks: float = float(summary.synergy_now.kills_per_min_mean)
	var kn: float = float(summary.narrow.kills_per_min_mean)
	var kr: float = float(summary.random.kills_per_min_mean)
	extra["kills_per_min_synergy_narrow_random"] = [ks, kn, kr]
	extra["kills_per_min_order_holds"] = ks > kn and kn > kr
	return {"evaluated": true, "holds": d1 > 0.0 and d2 > 0.0, "synergy_minus_narrow_pp": d1, "narrow_minus_random_pp": d2, "synergy_minus_random_pp": snappedf((s - r) * 100.0, 0.1),
		"by_primary": by_primary, "extra": extra, "rule": "synergy_now > narrow > random; each gap > 0 pp. Bot result, fun unevaluated"}

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
func print_summary(summary: Dictionary, verdict: Dictionary, prims: Array) -> void:
	print("== SUMMARY: per policy over %d primaries (rhythm_on=%s no_equip=%s) ==" % [prims.size(), str(rhythm_on), str(no_equip)])
	print("policy         n   win%%  wins/def/timeout | defeat cause crowd/strong/both/other (share of defeats) | timeout%% | win%% by primary")
	for pol in summary:
		var g: Dictionary = summary[pol]
		var dc: Dictionary = g.defeat_causes
		var dr: Dictionary = g.defeat_cause_ratio
		var wp: Array = []
		for k in g.win_by_primary: wp.append("%s %.0f%%" % [k, float(g.win_by_primary[k]) * 100.0])
		print("%-13s %3d %5.1f%%  %3d/%3d/%3d | %d/%d/%d/%d (%.0f%%/%.0f%%/%.0f%%/%.0f%%) | %5.1f%% | %s" % [pol, g.n, float(g.win_rate) * 100.0, g.wins, g.defeats, g.timeouts,
			dc.crowd, dc.strong, dc.both, dc.other, float(dr.crowd) * 100.0, float(dr.strong) * 100.0, float(dr.both) * 100.0, float(dr.other) * 100.0, float(g.timeout_rate) * 100.0, " ".join(PackedStringArray(wp))])
	if not bool(verdict.evaluated):
		print("RANK: not evaluated (needs synergy_now, narrow, random)")
		return
	print("RANK synergy_now > narrow > random: %s | synergy-narrow %+.1f pp, narrow-random %+.1f pp, synergy-random %+.1f pp" % ["HOLDS" if verdict.holds else "DOES NOT HOLD", verdict.synergy_minus_narrow_pp, verdict.narrow_minus_random_pp, verdict.synergy_minus_random_pp])
	for k in verdict.by_primary:
		var v: Dictionary = verdict.by_primary[k]
		print("  %-5s synergy-narrow %+.1f pp, narrow-random %+.1f pp -> %s" % [k, v.synergy_minus_narrow_pp, v.narrow_minus_random_pp, "holds" if v.holds else "no"])
	if not verdict.extra.is_empty(): print("  extra: %s" % str(verdict.extra))

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
