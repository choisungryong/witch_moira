extends SceneTree
## Drop simulation for loot grammar v2. Rolls the treasure classes for a whole
## dungeon run many times and reports what one run yields on average.
##
##   --script res://chapter1/tests/sim_loot.gd                 10000 runs, checks targets
##   ... -- --runs=2000 --primary=chapter1.skill.ember
##   ... -- --affix-rolls=on --luck=3000                       D23 3.16 (needs the core's affix_rolls branch and, for --luck>0, set_luck + quality_weights: else exit 3, see below)
##   ... -- --pity=on                                          D23 T9: every simulated run counts as a win; after 5 runs without a legendary or unique the
##                                                               next boss's first guaranteed line is a legendary. Adds pity_fired_runs; the drought line is judged.
##
## Kill counts for ordinary enemies, champions and the boss come from the golden
## replay of the current chapter (seed 11, frost). Elites and the treasure carrier
## are planned content: their counts are assumptions until those enemies exist.
##
## Output. Line 1 `LOOT_SIM {...}` is the original result and the only line that decides the exit code (run_all, judge_targets read it;
## nothing in it changed). Line 2 `LOOT_AFFIX_SIM {...}` is D23 T3 and is information while the core has no affix_rolls branch:
##   rare_lines_per_source   mean lines of a rare from ordinary sources / from champion, boss, ritual chest (the sources D23 3.3 gives a
##                           heavier line distribution), counted on the classes the run rolls, with the line-count histogram
##   rare_lines_by_slot      the same histogram per slot, taken from the rares of the run
##   rare_lines_direct       roll_item(level, "rare", slot) 4000 times per slot at item levels 6, 11, 15 on a separate generator
##                           (D23 0: "body, feet always 2 lines; weapon, head, hands always 3"). max_lines_by_slot > 4 says a slot can reach 5 lines.
##   five_line_rares_per_run, runs_with_tier5 (a rare or legendary with a tier-5 line), runs_with_jackpot (5 lines or tier 5),
##   affix_lines_by_tier_per_run (tier comes from the data row's `tier`; 0 = the row has no tier), legend_unique_drought (longest
##   run of simulated runs without a legendary or unique, and how many dry spells reach 5).
##   pool_capacity           from the DATA, not from rolls: per slot and item level how many prefix/suffix groups are eligible and the most
##                           lines a rare could hold, now (rows of `affixes`, caps 2/2) and with `affix_rolls` (pool + legacy_windows, caps and
##                           class caps of the block). Also counted with only the stats the core reads today (core_reads).
##   d23_targets / d23_misses  the 3.16 lines. They are only enforced (exit code 1) with --affix-rolls=on; with the switch off they are
##                           listed for information, because the current core cannot meet them.
## D23 T1 appendix A.6 (1), F2 wear policy: --wear [--wear-runs=2000] [--wear-seeds=11,12,13] [--kits-out=_local/x.json] (with none of these nothing above changes).
##   Careers of 30 consecutive runs per series (ember, frost, arc as the primary) and seed; every run's drops (the same drop loop as above) are worn when the game's own rule says so
##   (loot.is_upgrade: empty slot, legendary/unique, or a clearly higher score; rings go to the first free ring slot, else replace the worse ring). Required level is NOT enforced (the hero is
##   assumed to be level enough). --wear-runs = runs per series and seed (careers = runs / 30). The wear after run 3, 15 and 30 of every career is the sample for kit.f2.<series>.r3 / r15 / r30;
##   the kit is the REAL wear of the career whose total score (sum of loot.score) is the median of all careers (seeds pooled). Output: LOOT_WEAR {...} (score and stat sums p10/p50/p90 per series and
##   snapshot, the median wear) and, with --kits-out, a file of the same shape as tests/fixtures/gear_kits.json (`kits`), every item checked with loot.validate.
## --affix-rolls=on and --luck=N need the core branch of D23 T1: the loot object must offer set_affix_rolls(enabled: bool) -> bool.
## Without it this script prints LOOT_AFFIX_SIM_UNSUPPORTED and exits 3. It never reports a value it did not measure.
## --luck=N>0 also needs set_luck(enabled) and quality_weights(class, mods) (D23 T8): missing -> LOOT_AFFIX_SIM_UNSUPPORTED, exit 3; set_luck(true) refused -> exit 2.
##   Before the run it prints LOOT_LUCK_PROBE {luck, weights_off, weights_on, changed} (quality_weights("normal",{}) vs {"luck_bps":N}); changed=false -> exit 3.
##   weights_on is on the 100x scale of LKB1 (LUCK_WEIGHT_SCALE) when luck is applied; that is expected.
## --seed=N: seed of the drop generator of the main run (default 4141; without it the output is the same as before).
const Loot = preload("res://chapter1/core/loot.gd")
const GearKits = preload("res://chapter1/tests/support/gear_kits.gd")
const ZONE_LEVELS := [4,8,12]
const NORMAL_KILLS := [1245,1941,1587]
const ELITES_PER_ZONE := 2
const CARRIERS_PER_RUN := 1
## Per-run averages the design asks for (SYSTEMS-DESIGN 5.4).
const TARGETS := {"rare":[3.0,5.0],"jewelry":[0.6,1.6],"legendary":[0.25,0.45],"unique":[0.12,0.28]}
## D23 3.3: the sources whose rares draw from the heavier line distribution (`rare_boss`).
const RARE_BOSS_CLASSES := ["champion","boss","boss_g1","boss_g2","boss_g3","boss_g4","ritual_chest"]
const DIRECT_LEVELS := [6,11,15]
const DIRECT_ROLLS := 4000
const DIRECT_SEED := 20261122
const CAPACITY_LEVELS := [4,8,12,15]
## D23 3.16. Only enforced with --affix-rolls=on.
const D23_TARGETS := {"rare_lines_general":[3.35,3.55],"rare_lines_boss":[3.6,3.8],"five_line_rares_per_run":[0.30,0.45],"runs_with_tier5":[0.10,0.18],"runs_with_jackpot":[0.35,0.50]}
const D23_DROUGHT_MAX := 5
const D23_UNIQUE_AT_MAX_LUCK := 0.28

func _initialize() -> void:
	call_deferred("execute")

func execute() -> void:
	var runs := 10000
	var primary := "chapter1.skill.frost"
	var affix_arg := "off"
	var pity_arg := "off"
	var luck := 0
	var wear_on := false
	var wear_runs := 2000
	var wear_seeds: Array = [11,12,13]
	var kits_out := ""
	var seed_arg := 4141
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--runs="): runs = maxi(1,int(arg.trim_prefix("--runs=")))
		elif arg.begins_with("--primary="): primary = arg.trim_prefix("--primary=")
		elif arg.begins_with("--affix-rolls="): affix_arg = arg.trim_prefix("--affix-rolls=")
		elif arg.begins_with("--pity="): pity_arg = arg.trim_prefix("--pity=")
		elif arg.begins_with("--luck="): luck = int(arg.trim_prefix("--luck="))
		elif arg.begins_with("--seed="): seed_arg = int(arg.trim_prefix("--seed="))
		elif arg == "--wear": wear_on = true
		elif arg.begins_with("--wear-runs="): wear_runs = maxi(30,int(arg.trim_prefix("--wear-runs=")))
		elif arg.begins_with("--wear-seeds="):
			wear_seeds = []
			for part in arg.trim_prefix("--wear-seeds=").split(","): wear_seeds.append(int(part))
		elif arg.begins_with("--kits-out="): kits_out = arg.trim_prefix("--kits-out=")
	if not affix_arg in ["on","off"] or not pity_arg in ["on","off"] or luck < 0 or luck > 3000:
		push_error("usage: --affix-rolls=on|off  --pity=on|off  --luck=0..3000"); quit(2); return
	var pity_on := pity_arg == "on"
	var affix_on := affix_arg == "on"
	var loot = Loot.new()
	if not loot.load_file():
		push_error(str(loot.errors)); quit(2); return
	if affix_on or luck > 0:
		# A switch the core does not have must not be measured as if it did.
		if not loot.has_method("set_affix_rolls"):
			var missing: Array[String] = []
			if affix_on: missing.append("--affix-rolls=on")
			if luck > 0: missing.append("--luck="+str(luck))
			print("LOOT_AFFIX_SIM_UNSUPPORTED ",JSON.stringify({"requested":missing,"reason":"코어에 affix_rolls 가지가 없어 잴 수 없음 (loot.gd에 set_affix_rolls(enabled) 없음, D23 T1 전)","measured":false}))
			push_error("affix_rolls branch missing in the core: nothing was measured")
			quit(3); return
		if not loot.call("set_affix_rolls",affix_on):
			push_error("set_affix_rolls refused (the affix_rolls block is invalid)"); quit(2); return
	if luck > 0:
		# D23 T11 B5: a luck the core cannot apply must not be "measured" (before this the run ended 0 with luck_bps ignored by roll_class).
		if not loot.has_method("set_luck") or not loot.has_method("quality_weights"):
			print("LOOT_AFFIX_SIM_UNSUPPORTED ",JSON.stringify({"requested":["--luck="+str(luck)],"reason":"코어에 운 가지 없음(D23 T8 전)","measured":false}))
			push_error("luck branch missing in the core: nothing was measured")
			quit(3); return
		if not loot.call("set_luck",true):
			push_error("set_luck refused (loot.json has no luck block)"); quit(2); return
		var weights_off: Dictionary = loot.call("quality_weights","normal",{})
		var weights_on: Dictionary = loot.call("quality_weights","normal",{"luck_bps":luck})
		var probe_changed := JSON.stringify(weights_off) != JSON.stringify(weights_on)
		print("LOOT_LUCK_PROBE ",JSON.stringify({"luck":luck,"weights_off":weights_off,"weights_on":weights_on,"changed":probe_changed}))
		if not probe_changed:
			push_error("luck probe: quality_weights did not change with luck_bps; nothing would be measured")
			quit(3); return
	# D23 T9: --pity=on counts every simulated run as a win to the boss; after pity_runs() runs without a legendary or unique the next boss's
	# first guaranteed line is a legendary (loot.roll_class first_quality), exactly what the core does for an armed run.
	if pity_on and not loot.set_pity(true):
		push_error("set_pity refused (loot.json has no pity block)"); quit(2); return
	var pity_fired_runs := 0
	var mods: Dictionary = {"luck_bps":luck} if luck > 0 else {}
	if wear_on:
		quit(_wear_main(loot,wear_runs,wear_seeds,kits_out,mods,affix_arg))
		return
	var tier_of := _tier_table(loot)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_arg
	var totals := {"items":0,"common":0,"magic":0,"rare":0,"legendary":0,"unique":0,"jewelry":0}
	var by_slot: Dictionary = {}
	var runs_with := {"legendary":0,"unique":0,"jewelry":0}
	var per_run_items: Array[int] = []
	# D23 T3 accumulators (they read the drops; they draw nothing).
	var rare_count := {"general":0,"boss":0}
	var rare_lines := {"general":0,"boss":0}
	var rare_hist := {"general":{},"boss":{}}
	var rare_slot_hist: Dictionary = {}
	var five_line_rares := 0
	var tier_lines: Dictionary = {}
	var runs_tier5 := 0
	var runs_jackpot := 0
	var dry_now := 0
	var dry_max := 0
	var dry_spells_ge5 := 0
	for run in runs:
		var drops: Array[Dictionary] = []
		var sources: Array[String] = []
		for zone in 3:
			var level: int = ZONE_LEVELS[zone]
			for i in NORMAL_KILLS[zone]:
				var batch: Array[Dictionary] = loot.roll_class(rng,"normal",level,primary,mods)
				if not batch.is_empty(): _take(drops,sources,batch,"normal")
			for i in ELITES_PER_ZONE: _take(drops,sources,loot.roll_class(rng,"elite",level,primary,mods),"elite")
			var boss_class := "boss" if zone == 2 else "champion"
			var armed: bool = pity_on and zone == 2 and dry_now >= loot.pity_runs()
			var boss_batch: Array[Dictionary] = loot.roll_class(rng,boss_class,level,primary,mods,"legendary" if armed else "")
			if armed and not boss_batch.is_empty() and boss_batch[0].quality == "legendary": pity_fired_runs += 1
			_take(drops,sources,boss_batch,boss_class)
		for i in CARRIERS_PER_RUN: _take(drops,sources,loot.roll_class(rng,"carrier",ZONE_LEVELS[1],primary,mods),"carrier")
		var seen := {"legendary":false,"unique":false,"jewelry":false}
		var run_tier5 := false
		var run_five := false
		for index in drops.size():
			var item: Dictionary = drops[index]
			totals.items += 1
			totals[item.quality] += 1
			by_slot[item.slot] = int(by_slot.get(item.slot,0))+1
			if item.slot in loot.data.jewelry_slots:
				totals.jewelry += 1; seen.jewelry = true
			if seen.has(item.quality): seen[item.quality] = true
			var lines: int = item.affixes.size()
			for entry in item.affixes:
				var tier: int = int(tier_of.get(entry.id,0))
				tier_lines[tier] = int(tier_lines.get(tier,0))+1
				if tier == 5 and item.quality in ["rare","legendary"]: run_tier5 = true
			if item.quality == "rare":
				var origin := "boss" if sources[index] in RARE_BOSS_CLASSES else "general"
				rare_count[origin] += 1
				rare_lines[origin] += lines
				rare_hist[origin][lines] = int(rare_hist[origin].get(lines,0))+1
				if not rare_slot_hist.has(item.slot): rare_slot_hist[item.slot] = {}
				rare_slot_hist[item.slot][lines] = int(rare_slot_hist[item.slot].get(lines,0))+1
				if lines >= 5:
					five_line_rares += 1; run_five = true
		for key in seen:
			if seen[key]: runs_with[key] += 1
		per_run_items.append(drops.size())
		if run_tier5: runs_tier5 += 1
		if run_tier5 or run_five: runs_jackpot += 1
		if seen.legendary or seen.unique:
			if dry_now >= 5: dry_spells_ge5 += 1
			dry_now = 0
		else:
			dry_now += 1
			dry_max = maxi(dry_max,dry_now)
	if dry_now >= 5: dry_spells_ge5 += 1
	per_run_items.sort()
	var average: Dictionary = {}
	for key in totals: average[key] = snappedf(float(totals[key])/runs,.001)
	var share: Dictionary = {}
	for key in runs_with: share[key] = snappedf(float(runs_with[key])/runs,.001)
	var slots: Dictionary = {}
	for key in by_slot: slots[key] = snappedf(float(by_slot[key])/runs,.01)
	var misses: Array[String] = []
	for key in TARGETS:
		if float(average[key]) < float(TARGETS[key][0]) or float(average[key]) > float(TARGETS[key][1]):
			misses.append("%s %.3f outside %s" % [key,average[key],str(TARGETS[key])])
	print("LOOT_SIM ",JSON.stringify({"runs":runs,"primary":primary,"per_run_average":average,"share_of_runs_with":share,"per_run_by_slot":slots,
		"items_per_run_p10_p50_p90":[per_run_items[runs/10],per_run_items[runs/2],per_run_items[runs*9/10]],"targets":TARGETS,"mismatches":misses,
		"assumptions":{"normal_kills":NORMAL_KILLS,"elites_per_zone":ELITES_PER_ZONE,"carriers_per_run":CARRIERS_PER_RUN,"first_kill_reward_excluded":true}}))
	# ---- D23 T3 report
	var per_source: Dictionary = {}
	for origin in ["general","boss"]:
		per_source[origin] = {"rares":int(rare_count[origin]),"mean_lines":_ratio(rare_lines[origin],rare_count[origin]),"lines":_shares(rare_hist[origin])}
	var by_slot_lines: Dictionary = {}
	for slot in loot.data.slots:
		var hist: Dictionary = rare_slot_hist.get(slot,{})
		by_slot_lines[slot] = {"rares":_sum(hist),"mean_lines":_mean_of(hist),"lines":_shares(hist)}
	var direct := _direct(loot)
	var tier_per_run: Dictionary = {}
	for tier in tier_lines: tier_per_run[str(tier)] = snappedf(float(tier_lines[tier])/runs,.001)
	var d23_values := {"rare_lines_general":float(per_source.general.mean_lines),"rare_lines_boss":float(per_source.boss.mean_lines),"five_line_rares_per_run":snappedf(float(five_line_rares)/runs,.001),
		"runs_with_tier5":snappedf(float(runs_tier5)/runs,.001),"runs_with_jackpot":snappedf(float(runs_jackpot)/runs,.001)}
	var d23_misses: Array[String] = []
	for key in D23_TARGETS:
		var value: float = float(d23_values[key])
		if value < float(D23_TARGETS[key][0]) or value > float(D23_TARGETS[key][1]): d23_misses.append("%s %.3f outside %s" % [key,value,str(D23_TARGETS[key])])
	for slot in loot.data.slots:
		if int(direct.max_lines_by_slot[slot]) < 5: d23_misses.append("%s cannot roll 5 lines (max %d)" % [slot,int(direct.max_lines_by_slot[slot])])
	if dry_max > D23_DROUGHT_MAX: d23_misses.append("drought %d > %d (%s)" % [dry_max,D23_DROUGHT_MAX,"pity on" if pity_on else "no pity in the core"])
	print("LOOT_AFFIX_SIM ",JSON.stringify({"runs":runs,"affix_rolls":affix_arg,"luck":luck,"core_branch":loot.has_method("set_affix_rolls"),
		"rare_lines_per_source":per_source,"rare_lines_by_slot":by_slot_lines,"rare_lines_direct":direct.table,"max_lines_by_slot":direct.max_lines_by_slot,
		"five_line_rares_per_run":d23_values.five_line_rares_per_run,"runs_with_tier5":d23_values.runs_with_tier5,"runs_with_jackpot":d23_values.runs_with_jackpot,
		"affix_lines_by_tier_per_run":tier_per_run,"legend_unique_drought":{"longest_dry_runs":dry_max,"dry_spells_of_5_or_more":dry_spells_ge5,"pity":({"mode":"on","runs_without_legendary":loot.pity_runs(),"pity_fired_runs":snappedf(float(pity_fired_runs)/runs,.0001),"pity_fired_count":pity_fired_runs,"runs":runs,"every_run_counted_as_a_win":true} if pity_on else "none in the core")},
		"pool_capacity":_capacity_report(loot),"d23_targets":D23_TARGETS,"d23_misses":d23_misses,"d23_enforced":affix_on,
		"note":"rolls of the real core (loot.gd) with the seeds above; pool_capacity is computed from the data file, not rolled; drop rolls say nothing about fun"}))
	var d23_fail := affix_on and not d23_misses.is_empty()
	if affix_on and luck >= 3000 and float(average.unique) > D23_UNIQUE_AT_MAX_LUCK:
		d23_fail = true
		push_error("unique %.3f above %.2f at luck 3000" % [average.unique,D23_UNIQUE_AT_MAX_LUCK])
	if pity_on and dry_max > D23_DROUGHT_MAX:
		d23_fail = true
		push_error("pity on: longest run without a legendary or unique %d > %d" % [dry_max,D23_DROUGHT_MAX])
	quit(0 if (misses.is_empty() and not d23_fail) else 1)

# ---------------------------------------------------------------- D23 T1 appendix A.6 (1): the F2 wear policy

const WEAR_SERIES := ["ember","frost","arc"]
const WEAR_CAREER_RUNS := 30
const WEAR_SNAPS := [3,15,30]
const WEAR_EQUIP := ["weapon","head","body","hands","feet","charm","ring","ring2"]

## The same drop loop as the main run, for one run. Draws only from rng.
func _run_drops(loot, rng: RandomNumberGenerator, primary: String, mods: Dictionary) -> Array[Dictionary]:
	var drops: Array[Dictionary] = []
	var sources: Array[String] = []
	for zone in 3:
		var level: int = ZONE_LEVELS[zone]
		for i in NORMAL_KILLS[zone]:
			var batch: Array[Dictionary] = loot.roll_class(rng,"normal",level,primary,mods)
			if not batch.is_empty(): _take(drops,sources,batch,"normal")
		for i in ELITES_PER_ZONE: _take(drops,sources,loot.roll_class(rng,"elite",level,primary,mods),"elite")
		var boss_class := "boss" if zone == 2 else "champion"
		_take(drops,sources,loot.roll_class(rng,boss_class,level,primary,mods),boss_class)
	_take(drops,sources,loot.roll_class(rng,"carrier",ZONE_LEVELS[1],primary,mods),"carrier")
	return drops

## Wear one drop by the game's own rule (loot.is_upgrade). worn = {equip slot: item}.
func _wear(loot, worn: Dictionary, item: Dictionary, primary: String) -> void:
	var slot: String = item.slot
	if slot != "ring":
		if loot.is_upgrade(item,worn.get(slot,{}),primary): worn[slot] = item
		return
	if not worn.has("ring"): worn["ring"] = item; return
	if not worn.has("ring2"): worn["ring2"] = item; return
	var low := "ring" if loot.score(worn["ring"],primary) <= loot.score(worn["ring2"],primary) else "ring2"
	if loot.is_upgrade(item,worn[low],primary): worn[low] = item

func _percentile(sorted_values: Array, share: float) -> float:
	if sorted_values.is_empty(): return 0.0
	return float(sorted_values[clampi(int(float(sorted_values.size()-1)*share),0,sorted_values.size()-1)])

func _worn_sums(worn: Dictionary) -> Dictionary:
	var sums := {}
	for slot in worn:
		for stat in worn[slot].stats: sums[stat] = int(sums.get(stat,0))+int(worn[slot].stats[stat])
	return sums

## A kit item spec (the shape of gear_kits.json) from a real item.
func _kit_item(equip: String, item: Dictionary) -> Dictionary:
	var spec := {"equip":equip,"slot":item.slot,"quality":item.quality,"item_level":int(item.item_level)}
	if item.quality == "unique": spec["unique"] = String(item.base_id).trim_prefix("chapter1.full.unique.")
	else:
		spec["base"] = String(item.base_id).trim_prefix("chapter1.full.")
		if item.has("legendary_id"): spec["legendary"] = String(item.legendary_id)
		var lines: Array = []
		for entry in item.affixes: lines.append([String(entry.id),int(entry.value)])
		spec["affixes"] = lines
	return spec

func _wear_main(loot, wear_runs: int, seeds: Array, kits_out: String, mods: Dictionary, affix_arg: String) -> int:
	if kits_out != "" and (not kits_out.begins_with("_local/") or kits_out.contains("..") or kits_out.contains(":") or kits_out.begins_with("/")):
		push_error("--kits-out must be a relative path under _local/ (got %s)" % kits_out)
		return 2
	var careers_per_seed := wear_runs/WEAR_CAREER_RUNS
	var report := {}
	var kits := {}
	var invalid := 0
	var kit_items := 0
	for series_index in WEAR_SERIES.size():
		var series: String = WEAR_SERIES[series_index]
		var primary := "chapter1.skill."+series
		# samples[snap] = [{score, sums, worn}]
		var samples := {}
		for snap in WEAR_SNAPS: samples[snap] = []
		for seed_ in seeds:
			var rng := RandomNumberGenerator.new()
			rng.seed = int(seed_)*1000003+series_index*7919+1
			for career in careers_per_seed:
				var worn := {}
				for run in WEAR_CAREER_RUNS:
					for item in _run_drops(loot,rng,primary,mods): _wear(loot,worn,item,primary)
					if (run+1) in WEAR_SNAPS:
						var score := 0.0
						for slot in worn: score += loot.score(worn[slot],primary)
						samples[run+1].append({"score":score,"sums":_worn_sums(worn),"worn":worn.duplicate()})
		var series_report := {}
		for snap in WEAR_SNAPS:
			var list: Array = samples[snap]
			list.sort_custom(func(a, b): return float(a.score) < float(b.score))
			var scores: Array = list.map(func(e): return float(e.score))
			var median: Dictionary = list[(list.size()-1)/2]
			var stat_p := {}
			for stat in ["damage_bps","cooldown_bps","max_hp_raw","damage_reduction_bps","fire_damage_bps","chain_targets","projectiles"]:
				var values: Array = list.map(func(e): return float(e.sums.get(stat,0)))
				values.sort()
				stat_p[stat] = [_percentile(values,.1),_percentile(values,.5),_percentile(values,.9)]
			var med_items := {}
			var med_quality := {}
			for slot in median.worn:
				med_items[slot] = "%s %s il%d" % [median.worn[slot].quality,String(median.worn[slot].base_id).split(".")[-1],int(median.worn[slot].item_level)]
				med_quality[median.worn[slot].quality] = int(med_quality.get(median.worn[slot].quality,0))+1
			series_report["r%d"%snap] = {"careers":list.size(),"score_p10_p50_p90":[snappedf(_percentile(scores,.1),.01),snappedf(_percentile(scores,.5),.01),snappedf(_percentile(scores,.9),.01)],
				"sum_p10_p50_p90":stat_p,"median_kit":{"score":snappedf(float(median.score),.01),"sums":median.sums,"items":med_items,"quality":med_quality,"slots_filled":median.worn.size()}}
			var kit_specs: Array = []
			for slot in WEAR_EQUIP:
				if not median.worn.has(slot): continue
				var spec := _kit_item(slot,median.worn[slot])
				var check := _check_kit_item(loot,spec)
				kit_items += 1
				if not check.is_empty():
					invalid += 1
					push_error("kit item %s %s refused: %s" % [series,slot,str(check)])
				kit_specs.append(spec)
			kits["kit.f2.%s.r%d" % [series,snap]] = {"what":"F2 wear policy, series %s, after run %d of a career: the real wear of the median-score career (of %d, seeds %s pooled)" % [series,snap,list.size(),str(seeds)],
				"items":kit_specs,"budget_layer2":{"r3":"A.5 row 1","r15":"A.5 row 2","r30":"A.5 row 3"}["r%d" % snap]}
		report[series] = series_report
	print("LOOT_WEAR ",JSON.stringify({"policy":"F2: loot.is_upgrade on every drop, rings into free slot or replace the worse, required level ignored","careers_per_series_and_seed":careers_per_seed,"career_runs":WEAR_CAREER_RUNS,"seeds":seeds,
		"affix_rolls":affix_arg,"kit_items":kit_items,"kit_items_refused_by_validate":invalid,"series":report,"note":"drop rolls and a bot-free wear rule only; nothing here says how a kit plays"}))
	if kits_out != "":
		var out := {"schema":1,"note":"D23 T1 appendix A.6 (1): kits made by sim_loot.gd --wear (F2 wear policy). Same shape as gear_kits.json; build with tests/support/gear_kits.gd.","affix_rolls":affix_arg,"kits":kits}
		var abs_path := ProjectSettings.globalize_path("res://"+kits_out)
		DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
		var f := FileAccess.open(abs_path,FileAccess.WRITE)
		if f == null:
			push_error("cannot write "+abs_path)
			return 3
		f.store_string(JSON.stringify(out,"\t"))
		f.close()
	return 0 if invalid == 0 else 1

## The kit builder of the bench (support/gear_kits.gd) must give back an item loot.validate accepts.
func _check_kit_item(loot, spec: Dictionary) -> Array:
	var built: Dictionary = GearKits.build_item(loot,spec)
	if built.has("error"): return [built.error]
	return loot.validate(built.item)

func _take(drops: Array[Dictionary], sources: Array[String], batch: Array[Dictionary], class_id: String) -> void:
	for item in batch:
		drops.append(item)
		sources.append(class_id)

func _ratio(part: int, whole: int) -> float:
	return snappedf(float(part)/float(whole),.001) if whole > 0 else 0.0

func _sum(hist: Dictionary) -> int:
	var total := 0
	for key in hist: total += int(hist[key])
	return total

func _mean_of(hist: Dictionary) -> float:
	var total := _sum(hist)
	if total == 0: return 0.0
	var lines := 0
	for key in hist: lines += int(key)*int(hist[key])
	return snappedf(float(lines)/total,.001)

## {"2":0.5,"3":0.5} for a histogram {2:n,3:m}, keys in ascending order.
func _shares(hist: Dictionary) -> Dictionary:
	var total := _sum(hist)
	var keys: Array = hist.keys()
	keys.sort()
	var result: Dictionary = {}
	for key in keys: result[str(key)] = snappedf(float(hist[key])/float(total),.0001)
	return result

## id -> tier for every row the loot data names (the live `affixes` list and, when present, the `affix_rolls` pool). 0 = no tier on the row.
func _tier_table(loot) -> Dictionary:
	var table: Dictionary = {}
	for row in loot.data.affixes: table[row.id] = int(row.get("tier",0))
	var block: Dictionary = loot.data.get("affix_rolls",{})
	for row in block.get("pool",[]): table[row.id] = int(row.get("tier",0))
	return table

## D23 0 check on the real core: a rare at item level 6, 11, 15 for every slot, 4000 draws each on its own generator.
func _direct(loot) -> Dictionary:
	var drng := RandomNumberGenerator.new()
	drng.seed = DIRECT_SEED
	var table: Dictionary = {}
	var max_by_slot: Dictionary = {}
	for slot in loot.data.slots:
		table[slot] = {}
		var best := 0
		for level in DIRECT_LEVELS:
			var hist: Dictionary = {}
			var not_rare := 0
			for i in DIRECT_ROLLS:
				var item: Dictionary = loot.roll_item(drng,level,"rare",slot)
				if item.quality != "rare":
					not_rare += 1
					continue
				var lines: int = item.affixes.size()
				hist[lines] = int(hist.get(lines,0))+1
				best = maxi(best,lines)
			table[slot][str(level)] = {"rolls":DIRECT_ROLLS,"downgraded":not_rare,"mean_lines":_mean_of(hist),"lines":_shares(hist)}
		max_by_slot[slot] = best
	return {"table":table,"max_lines_by_slot":max_by_slot}

## Rows as {group, kind, cls, slots, level, max_level, readable}. `with_pool` applies the block's legacy_windows and adds its pool.
func _capacity_rows(loot, with_pool: bool) -> Array[Dictionary]:
	var block: Dictionary = loot.data.get("affix_rolls",{})
	var windows: Dictionary = block.get("legacy_windows",{}) if with_pool else {}
	var rows: Array[Dictionary] = []
	for row in loot.data.affixes:
		var level := int(row.level)
		var max_level := int(row.max_level)
		if windows.has(row.id):
			level = int(windows[row.id].level)
			max_level = int(windows[row.id].max_level)
		rows.append({"group":String(row.group),"kind":String(row.kind),"cls":String(row.get("class","number")),"slots":row.slots,"level":level,"max_level":max_level,"readable":true})
	if with_pool:
		for row in block.get("pool",[]):
			rows.append({"group":String(row.group),"kind":String(row.kind),"cls":String(row.get("class","number")),"slots":row.slots,"level":int(row.level),"max_level":int(row.max_level),"readable":bool(row.get("core_reads",true))})
	return rows

## Groups of one slot that have a row open at `level`: [{group, kind, cls}].
func _eligible(rows: Array[Dictionary], slot: String, level: int, readable_only: bool) -> Array[Dictionary]:
	var seen: Dictionary = {}
	var groups: Array[Dictionary] = []
	for row in rows:
		if not slot in row.slots or level < int(row.level) or level > int(row.max_level): continue
		if readable_only and not row.readable: continue
		if seen.has(row.group): continue
		seen[row.group] = true
		groups.append({"group":row.group,"kind":row.kind,"cls":row.cls})
	return groups

## Most lines a rare can hold from these groups: at most `cap` of each kind and the class caps (e.g. {"condition":2,"skill":1}).
func _max_lines(groups: Array[Dictionary], cap: int, class_caps: Dictionary) -> int:
	var count := groups.size()
	var best := 0
	for mask in range(1,1 << count):
		var picked := 0
		var kinds := {"prefix":0,"suffix":0}
		var classes: Dictionary = {}
		var ok := true
		for bit in count:
			if (mask >> bit) & 1 == 0: continue
			var group: Dictionary = groups[bit]
			picked += 1
			kinds[group.kind] += 1
			classes[group.cls] = int(classes.get(group.cls,0))+1
			if int(kinds[group.kind]) > cap or (class_caps.has(group.cls) and int(classes[group.cls]) > int(class_caps[group.cls])):
				ok = false
				break
		if ok and picked > best: best = picked
	return best

func _capacity_report(loot) -> Dictionary:
	var block: Dictionary = loot.data.get("affix_rolls",{})
	var report: Dictionary = {"now":{},"with_pool":{}}
	var cap_new := int(block.get("kind_caps",{}).get("rare",3))
	var class_caps: Dictionary = block.get("class_caps",{}).get("rare",{})
	var rows_now := _capacity_rows(loot,false)
	var rows_new := _capacity_rows(loot,true)
	for slot in loot.data.slots:
		report.now[slot] = {}
		report.with_pool[slot] = {}
		for level in CAPACITY_LEVELS:
			var now := _eligible(rows_now,slot,level,false)
			report.now[slot][str(level)] = {"prefix_groups":_kind_count(now,"prefix"),"suffix_groups":_kind_count(now,"suffix"),"max_lines":_max_lines(now,2,{})}
			if block.has("pool"):
				var full := _eligible(rows_new,slot,level,false)
				var ready := _eligible(rows_new,slot,level,true)
				report.with_pool[slot][str(level)] = {"prefix_groups":_kind_count(full,"prefix"),"suffix_groups":_kind_count(full,"suffix"),"max_lines":_max_lines(full,cap_new,class_caps),
					"prefix_groups_core_reads":_kind_count(ready,"prefix"),"suffix_groups_core_reads":_kind_count(ready,"suffix"),"max_lines_core_reads":_max_lines(ready,cap_new,class_caps)}
	if not block.has("pool"): report.erase("with_pool")
	return report

func _kind_count(groups: Array[Dictionary], kind: String) -> int:
	var total := 0
	for group in groups:
		if group.kind == kind: total += 1
	return total
