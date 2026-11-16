extends SceneTree
## Plays whole pilot runs on the real core and reports what actually dropped,
## what was picked up and what the hero ended up wearing.
##   --script res://chapter1/tests/report_run_loot.gd -- --seeds=11,12,13 --primary=chapter1.skill.frost
const Core = preload("res://chapter1/core/chapter_core.gd")
const Pilot = preload("res://chapter1/core/chapter_pilot.gd")

func _initialize() -> void:
	call_deferred("execute")

func execute() -> void:
	var seeds: Array = [11]
	var primary := "chapter1.skill.frost"
	var first_kill := true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seeds = []
			for part in arg.trim_prefix("--seeds=").split(","): seeds.append(int(part))
		elif arg.begins_with("--primary="): primary = arg.trim_prefix("--primary=")
		elif arg == "--repeat-clear": first_kill = false
	for seed_ in seeds:
		var run = Core.new()
		var pilot = Pilot.new()
		pilot.run = run
		run.first_boss_kill = first_kill
		if not run.start(seed_,primary):
			push_error(str(run.errors)); quit(2); return
		var dropped := {"common":0,"magic":0,"rare":0,"legendary":0,"unique":0}
		var dropped_slots: Dictionary = {}
		var guard := 0
		while run.mode not in ["victory","defeat"] and guard < 12*60*60+500:
			run.step(pilot.decide()); guard += 1
			for event in run.events:
				if event.type == "item_drop":
					dropped[event.item.quality] += 1
					dropped_slots[event.item.slot] = int(dropped_slots.get(event.item.slot,0))+1
		var worn: Dictionary = {}
		for slot in run.equipped:
			for item in run.inventory:
				if int(item.uid) == int(run.equipped[slot]): worn[slot] = "%s(%s, lv%d)" % [item.name,item.quality,item.item_level]
		print("RUN_LOOT ",JSON.stringify({"seed":seed_,"primary":primary,"mode":run.mode,"seconds":run.tick/60,"kills":run.kills,"level":run.growth.snapshot().level,
			"dropped":dropped,"dropped_by_slot":dropped_slots,"in_bag":run.inventory.size(),"pending":run.pending_rewards.size(),"overflow":run.metrics.get("overflow_items",0),
			"worn_slots":run.equipped.size(),"worn":worn,"hero_speed":snappedf(float(run.hero.speed),.01),"max_hp":int(run.hero.max_hp_raw)/256}))
	quit(0)
