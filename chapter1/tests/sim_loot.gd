extends SceneTree
## Drop simulation for loot grammar v2. Rolls the treasure classes for a whole
## dungeon run many times and reports what one run yields on average.
##
##   --script res://chapter1/tests/sim_loot.gd                 10000 runs, checks targets
##   ... -- --runs=2000 --primary=chapter1.skill.ember
##   ... -- --affix-rolls=on --luck=3000                       D23 3.16 (needs the core's affix_rolls branch, see below)
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
## --affix-rolls=on and --luck=N need the core branch of D23 T1: the loot object must offer set_affix_rolls(enabled: bool) -> bool.
## Without it this script prints LOOT_AFFIX_SIM_UNSUPPORTED and exits 3. It never reports a value it did not measure.
const Loot = preload("res://chapter1/core/loot.gd")
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
	var luck := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--runs="): runs = maxi(1,int(arg.trim_prefix("--runs=")))
		elif arg.begins_with("--primary="): primary = arg.trim_prefix("--primary=")
		elif arg.begins_with("--affix-rolls="): affix_arg = arg.trim_prefix("--affix-rolls=")
		elif arg.begins_with("--luck="): luck = int(arg.trim_prefix("--luck="))
	if not affix_arg in ["on","off"] or luck < 0 or luck > 3000:
		push_error("usage: --affix-rolls=on|off  --luck=0..3000"); quit(2); return
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
	var mods: Dictionary = {"luck_bps":luck} if luck > 0 else {}
	var tier_of := _tier_table(loot)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4141
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
			_take(drops,sources,loot.roll_class(rng,boss_class,level,primary,mods),boss_class)
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
	if dry_max > D23_DROUGHT_MAX: d23_misses.append("drought %d > %d (no pity in the core)" % [dry_max,D23_DROUGHT_MAX])
	print("LOOT_AFFIX_SIM ",JSON.stringify({"runs":runs,"affix_rolls":affix_arg,"luck":luck,"core_branch":loot.has_method("set_affix_rolls"),
		"rare_lines_per_source":per_source,"rare_lines_by_slot":by_slot_lines,"rare_lines_direct":direct.table,"max_lines_by_slot":direct.max_lines_by_slot,
		"five_line_rares_per_run":d23_values.five_line_rares_per_run,"runs_with_tier5":d23_values.runs_with_tier5,"runs_with_jackpot":d23_values.runs_with_jackpot,
		"affix_lines_by_tier_per_run":tier_per_run,"legend_unique_drought":{"longest_dry_runs":dry_max,"dry_spells_of_5_or_more":dry_spells_ge5,"pity":"none in the core"},
		"pool_capacity":_capacity_report(loot),"d23_targets":D23_TARGETS,"d23_misses":d23_misses,"d23_enforced":affix_on,
		"note":"rolls of the real core (loot.gd) with the seeds above; pool_capacity is computed from the data file, not rolled; drop rolls say nothing about fun"}))
	var d23_fail := affix_on and not d23_misses.is_empty()
	if affix_on and luck >= 3000 and float(average.unique) > D23_UNIQUE_AT_MAX_LUCK:
		d23_fail = true
		push_error("unique %.3f above %.2f at luck 3000" % [average.unique,D23_UNIQUE_AT_MAX_LUCK])
	quit(0 if (misses.is_empty() and not d23_fail) else 1)

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
