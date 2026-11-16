extends SceneTree
## Loot grammar v2 checks: data validity, generated items, v1 compatibility, tamper detection.
const Loot = preload("res://chapter1/core/loot.gd")
const ItemsV1 = preload("res://chapter1/core/chapter_items.gd")
var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("execute")

func execute() -> void:
	var loot = Loot.new()
	check(loot.load_file(),"loot data loads: "+str(loot.errors))
	if not failures.is_empty():
		finish(); return
	check(loot.data.equip_slots.size() == 8,"eight equip slots")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261114
	var valid := true
	var first_issue := ""
	var seen_slots: Dictionary = {}
	var seen_bases: Dictionary = {}
	var counts_ok := true
	for i in 20000:
		var level := 1+i%30
		var quality: String = ["common","magic","rare","legendary"][i%4]
		var item: Dictionary = loot.roll_item(rng,level,quality)
		var issues: Array[String] = loot.validate(item)
		if not issues.is_empty() and valid:
			valid = false; first_issue = str(issues)+" "+JSON.stringify(item)
		seen_slots[item.slot] = true; seen_bases[item.base_id] = true
		if item.quality == "rare" and item.affixes.size() < 2: counts_ok = false
		if item.quality == "legendary" and not item.has("legendary_id"): counts_ok = false
	check(valid,"20000 generated items validate: "+first_issue)
	check(counts_ok,"rare has at least two affixes and legendary carries its effect")
	check(seen_slots.size() == 7,"every slot is reachable")
	check(seen_bases.size() == loot.data.bases.size(),"every base is reachable")
	# Item level gates affix tiers.
	var low_only := true
	for i in 3000:
		var item: Dictionary = loot.roll_item(rng,3,"rare")
		for entry in item.affixes:
			if entry.id in ["wrath2","wrath3","haste2","vigor2","ward2"]: low_only = false
	check(low_only,"level 3 items never roll higher-tier affixes")
	var high_tier := false
	for i in 3000:
		var item: Dictionary = loot.roll_item(rng,20,"rare")
		for entry in item.affixes:
			if entry.id == "wrath3": high_tier = true
			if entry.id in ["wrath","haste","vigor","ward"]: low_only = false
	check(high_tier and low_only,"level 20 items roll top tiers and no expired tier-1 affixes")
	# v1 items stay valid through the v2 validator.
	var old_rng := RandomNumberGenerator.new(); old_rng.seed = 7
	var v1_ok := true
	for i in 3000:
		var old: Dictionary = ItemsV1.roll(old_rng,1+i%12,["common","magic","rare"][i%3])
		if not loot.validate(old).is_empty(): v1_ok = false
	for i in 3:
		if not loot.validate(ItemsV1.unique(i,12)).is_empty(): v1_ok = false
	check(v1_ok,"3003 v1 items remain valid")
	# Tampering is rejected.
	var forged: Dictionary = loot.roll_item(rng,10,"rare","weapon")
	forged.stats.damage_bps = 29999
	check(not loot.validate(forged).is_empty(),"forged stat rejected")
	forged = loot.roll_item(rng,10,"magic","weapon")
	forged.quality = "legendary"; forged.legendary_id = "splitting"
	check(not loot.validate(forged).is_empty(),"relabelled legendary rejected")
	forged = loot.make_unique("winter_heart",12); forged.stats.shatter_count = 8
	check(not loot.validate(forged).is_empty(),"forged unique rejected")
	forged = loot.roll_item(rng,10,"rare","feet"); forged.slot = "weapon"
	check(not loot.validate(forged).is_empty(),"slot swap rejected")
	forged = loot.roll_item(rng,10,"common","ring"); forged.grammar = 3
	check(not loot.validate(forged).is_empty(),"unknown grammar rejected")
	# Uniques and treasure classes.
	for id_ in ["ash_bloom","winter_heart","forked_covenant"]:
		check(loot.validate(loot.make_unique(id_,12)).is_empty(),"unique validates "+id_)
	var first: Array[Dictionary] = loot.roll_class(rng,"boss_first_kill",12,"chapter1.skill.frost")
	check(first.size() == 1 and first[0].base_id == "chapter1.full.unique.winter_heart","first boss kill grants the primary unique")
	var champion_ok := true
	for i in 500:
		var drops: Array[Dictionary] = loot.roll_class(rng,"champion",8,"chapter1.skill.ember")
		if drops.size() != 3 or drops[0].quality != "rare": champion_ok = false
		for item in drops:
			if not loot.validate(item).is_empty() or item.item_level != 11: champion_ok = false
	check(champion_ok,"champion drops three items, first rare, at zone level + 3")
	check(loot.roll_class(rng,"missing",8).is_empty(),"unknown treasure class yields nothing")
	# Determinism.
	var a := RandomNumberGenerator.new(); a.seed = 99
	var b := RandomNumberGenerator.new(); b.seed = 99
	var same := true
	for i in 300:
		if JSON.stringify(loot.roll_class(a,"boss",12,"chapter1.skill.arc")) != JSON.stringify(loot.roll_class(b,"boss",12,"chapter1.skill.arc")): same = false
	check(same,"same seed gives the same drops")
	# Upgrade prompt rule.
	var weak: Dictionary = loot.roll_item(rng,1,"common","weapon")
	var strong: Dictionary = loot.roll_item(rng,20,"rare","weapon")
	while loot.score(strong,"chapter1.skill.frost") <= loot.score(weak,"chapter1.skill.frost")*1.05+.5: strong = loot.roll_item(rng,20,"rare","weapon")
	check(loot.is_upgrade(strong,weak,"chapter1.skill.frost") and not loot.is_upgrade(weak,strong,"chapter1.skill.frost"),"better item prompts, worse item does not")
	check(loot.is_upgrade(weak,{},"chapter1.skill.frost"),"empty slot always prompts")
	check(loot.is_upgrade(loot.make_unique("ash_bloom",12),strong,"chapter1.skill.frost"),"unique always prompts")
	finish()

func finish() -> void:
	print("CHAPTER1_LOOT_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"scope":"loot grammar v2 only; not wired into the running chapter"}))
	quit(0 if failures.is_empty() else 1)
