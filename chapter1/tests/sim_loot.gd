extends SceneTree
## Drop simulation for loot grammar v2. Rolls the treasure classes for a whole
## dungeon run many times and reports what one run yields on average.
##
##   --script res://chapter1/tests/sim_loot.gd                 10000 runs, checks targets
##   ... -- --runs=2000 --primary=chapter1.skill.ember
##
## Kill counts for ordinary enemies, champions and the boss come from the golden
## replay of the current chapter (seed 11, frost). Elites and the treasure carrier
## are planned content: their counts are assumptions until those enemies exist.
const Loot = preload("res://chapter1/core/loot.gd")
const ZONE_LEVELS := [4,8,12]
const NORMAL_KILLS := [1245,1941,1587]
const ELITES_PER_ZONE := 2
const CARRIERS_PER_RUN := 1
## Per-run averages the design asks for (SYSTEMS-DESIGN 5.4).
const TARGETS := {"rare":[3.0,5.0],"jewelry":[0.6,1.6],"legendary":[0.25,0.45],"unique":[0.12,0.28]}

func _initialize() -> void:
	call_deferred("execute")

func execute() -> void:
	var runs := 10000
	var primary := "chapter1.skill.frost"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--runs="): runs = maxi(1,int(arg.trim_prefix("--runs=")))
		elif arg.begins_with("--primary="): primary = arg.trim_prefix("--primary=")
	var loot = Loot.new()
	if not loot.load_file():
		push_error(str(loot.errors)); quit(2); return
	var rng := RandomNumberGenerator.new()
	rng.seed = 4141
	var totals := {"items":0,"common":0,"magic":0,"rare":0,"legendary":0,"unique":0,"jewelry":0}
	var by_slot: Dictionary = {}
	var runs_with := {"legendary":0,"unique":0,"jewelry":0}
	var per_run_items: Array[int] = []
	for run in runs:
		var drops: Array[Dictionary] = []
		for zone in 3:
			var level: int = ZONE_LEVELS[zone]
			for i in NORMAL_KILLS[zone]: drops.append_array(loot.roll_class(rng,"normal",level,primary))
			for i in ELITES_PER_ZONE: drops.append_array(loot.roll_class(rng,"elite",level,primary))
			drops.append_array(loot.roll_class(rng,"boss" if zone == 2 else "champion",level,primary))
		for i in CARRIERS_PER_RUN: drops.append_array(loot.roll_class(rng,"carrier",ZONE_LEVELS[1],primary))
		var seen := {"legendary":false,"unique":false,"jewelry":false}
		for item in drops:
			totals.items += 1
			totals[item.quality] += 1
			by_slot[item.slot] = int(by_slot.get(item.slot,0))+1
			if item.slot in loot.data.jewelry_slots:
				totals.jewelry += 1; seen.jewelry = true
			if seen.has(item.quality): seen[item.quality] = true
		for key in seen:
			if seen[key]: runs_with[key] += 1
		per_run_items.append(drops.size())
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
	quit(0 if misses.is_empty() else 1)
