extends SceneTree
## Plays whole pilot runs on the real core and reports what actually dropped,
## what was picked up and what the hero ended up wearing.
##   --script res://chapter1/tests/report_run_loot.gd -- --seeds=11,12,13 --primary=chapter1.skill.frost
## GM-B: --upgrade-verdict=on|off switches loot.json's upgrade_verdict in memory and adds a "verdict" block to the RUN_LOOT line: at every item_pickup the
## core's pickup_verdict() is asked (read only; the pilot still wears by its own rule) and the answers are counted. Without the argument nothing is
## asked and the line is as before.
const Core = preload("res://chapter1/core/chapter_core.gd")
const Pilot = preload("res://chapter1/core/chapter_pilot.gd")

func _initialize() -> void:
	call_deferred("execute")

func execute() -> void:
	var seeds: Array = [11]
	var primary := "chapter1.skill.frost"
	var first_kill := true
	var verdict_arg := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seeds = []
			for part in arg.trim_prefix("--seeds=").split(","): seeds.append(int(part))
		elif arg.begins_with("--primary="): primary = arg.trim_prefix("--primary=")
		elif arg == "--repeat-clear": first_kill = false
		elif arg.begins_with("--upgrade-verdict="): verdict_arg = arg.trim_prefix("--upgrade-verdict=")
	if not verdict_arg in ["","on","off"]:
		push_error("usage: --upgrade-verdict=on|off"); quit(2); return
	for seed_ in seeds:
		var run = Core.new()
		var pilot = Pilot.new()
		pilot.run = run
		run.first_boss_kill = first_kill
		if not run.start(seed_,primary):
			push_error(str(run.errors)); quit(2); return
		if verdict_arg != "" and not run.loot.set_verdict(verdict_arg == "on"):
			push_error("loot.json has no upgrade_verdict block"); quit(2); return
		var counts := {"pickups":0,"better_yes":0,"notice":0,"auto_equip":0,"card_note_empty_no_effect":0,"card_note_weak":0,"open":0,"open_better_yes":0}
		var dropped := {"common":0,"magic":0,"rare":0,"legendary":0,"unique":0}
		var dropped_slots: Dictionary = {}
		var guard := 0
		while run.mode not in ["victory","defeat"] and guard < 12*60*60+500:
			run.step(pilot.decide()); guard += 1
			for event in run.events:
				if event.type == "item_drop":
					dropped[event.item.quality] += 1
					dropped_slots[event.item.slot] = int(dropped_slots.get(event.item.slot,0))+1
				elif event.type == "item_pickup" and verdict_arg != "":
					var answer: Dictionary = run.pickup_verdict(int(event.item.uid))
					if answer.is_empty(): continue
					counts.pickups += 1
					if answer.better == "yes": counts.better_yes += 1
					if answer.react in ["card","open","auto_equip"]: counts.notice += 1
					if answer.react == "auto_equip": counts.auto_equip += 1
					if answer.react == "open":
						counts.open += 1
						if answer.better == "yes": counts.open_better_yes += 1
					if String(answer.get("note","")) == "empty_no_effect": counts.card_note_empty_no_effect += 1
					if String(answer.get("note","")) == "weak_for_primary": counts.card_note_weak += 1
		var worn: Dictionary = {}
		for slot in run.equipped:
			for item in run.inventory:
				if int(item.uid) == int(run.equipped[slot]): worn[slot] = "%s(%s, lv%d)" % [item.name,item.quality,item.item_level]
		var line := {"seed":seed_,"primary":primary,"mode":run.mode,"seconds":run.tick/60,"kills":run.kills,"level":run.growth.snapshot().level,
			"dropped":dropped,"dropped_by_slot":dropped_slots,"in_bag":run.inventory.size(),"pending":run.pending_rewards.size(),"overflow":run.metrics.get("overflow_items",0),
			"worn_slots":run.equipped.size(),"worn":worn,"hero_speed":snappedf(float(run.hero.speed),.01),"max_hp":int(run.hero.max_hp_raw)/256}
		if verdict_arg != "": line["verdict"] = {"switch":verdict_arg,"counts":counts}
		print("RUN_LOOT ",JSON.stringify(line))
	quit(0)
