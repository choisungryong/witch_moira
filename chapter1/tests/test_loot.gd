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
	name_checks(loot)
	finish()

## D5 (a): names and descriptions are presentation. validate() checks ids and numbers; dress() rebuilds the text.
func name_checks(loot: RefCounted) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 52117
	# L-1: dress() rebuilds exactly what the roll wrote, for every quality and slot.
	var dressed_same := true
	var first_diff := ""
	var rolled := 0
	for quality in ["common","magic","rare","legendary"]:
		for slot in loot.data.slots:
			for i in 30:
				var item: Dictionary = loot.roll_item(rng,1+(i*7)%30,quality,slot)
				rolled += 1
				var dressed: Dictionary = loot.dress(item)
				if not loot.validate(item).is_empty() or not loot.validate(dressed).is_empty(): dressed_same = false
				if dressed.name != item.name or dressed.description != item.description or dressed.stats != item.stats:
					dressed_same = false
					if first_diff.is_empty(): first_diff = JSON.stringify(item)
	for row in loot.data.uniques:
		var unique: Dictionary = loot.make_unique(row.id,int(row.level))
		var dressed: Dictionary = loot.dress(unique)
		if not loot.validate(unique).is_empty(): dressed_same = false
		if dressed.name != unique.name or dressed.description != unique.description: dressed_same = false
		rolled += 1
	check(rolled >= 800 and dressed_same,"L-1 dress() reproduces the rolled name and description for %d items %s"%[rolled,first_diff])
	# L-2b: every name and description the data can produce passes the text rules.
	var text_ok := true
	var words: Array = []
	words.append_array(loot.data.rare_names.first)
	words.append_array(loot.data.rare_names.second)
	for table in ["bases","affixes","legendaries","uniques"]:
		for row in loot.data[table]:
			words.append(row.name)
	for word in words:
		if not loot._check_text({"name":str(word),"description":""}).is_empty(): text_ok = false
	for table in ["legendaries","uniques"]:
		for row in loot.data[table]:
			if not loot._check_text({"name":"x","description":str(row.description)}).is_empty(): text_ok = false
	for first_word in loot.data.rare_names.first:
		for second_word in loot.data.rare_names.second:
			if not loot._check_text({"name":str(first_word)+" "+str(second_word),"description":""}).is_empty(): text_ok = false
	check(text_ok and words.size() > 20,"L-2b every base, affix, legendary, unique and rare-name word from the data passes the text rules")
	# L-2: any text of a valid shape is accepted, including rare names of one or three words.
	var texts_ok := true
	for quality in ["common","magic","rare","legendary"]:
		var item: Dictionary = loot.roll_item(rng,12,quality,"weapon")
		var variants: Array[Dictionary] = [{"name":"x","description":""},{"name":"가".repeat(160),"description":"설".repeat(300)},{"name":"한낱말","description":"임의의 글"},{"name":"세 낱말 이름","description":""}]
		for variant in variants:
			var copy: Dictionary = item.duplicate(true)
			copy.name = variant.name
			copy.description = variant.description
			if not loot.validate(copy).is_empty(): texts_ok = false
	var uniq: Dictionary = loot.make_unique("winter_heart",12)
	uniq.name = "다른 이름"
	uniq.description = "다른 설명"
	check(texts_ok and loot.validate(uniq).is_empty(),"L-2 any well-formed name and description validates (all qualities and uniques)")
	# L-3: malformed text is rejected.
	var shape_ok := true
	var base_item: Dictionary = loot.roll_item(rng,12,"rare","weapon")
	for patch in [{"name":"a\nb"},{"name":"a\u0085b"},{"name":"a\u202Eb"},{"name":"a\u2066b"},{"name":"a\u2028b"},{"name":"a\u2029b"},{"description":"a\u0085b"},{"description":"a\u202Eb"},{"description":"a\u2029b"},{"description":"a\rb"},{"name":5},{"name":"가".repeat(161)},{"name":""},{"description":"설".repeat(301)},{"description":7},{"name":"a\u0001b"},{"description":"a\tb"}]:
		var copy: Dictionary = base_item.duplicate(true)
		for key in patch: copy[key] = patch[key]
		if loot.validate(copy).is_empty(): shape_ok = false
	var newline_ok: Dictionary = base_item.duplicate(true)
	newline_ok.description = "첫 줄\n둘째 줄"
	check(shape_ok and loot.validate(newline_ok).is_empty(),"L-3 non-string, empty, over-long and control-character text rejected; a newline is allowed")
	# L-4: identity forgery is still rejected.
	var forged_ok := true
	var item: Dictionary = loot.roll_item(rng,20,"rare","weapon")
	var copy: Dictionary = item.duplicate(true)
	copy.affixes[0].value = 99999
	if loot.validate(copy).is_empty(): forged_ok = false
	copy = item.duplicate(true)
	copy.affixes[0].id = "no_such_affix"
	if loot.validate(copy).is_empty(): forged_ok = false
	copy = loot.make_unique("ash_bloom",12)
	for stat in copy.stats:
		copy.stats[stat] = int(copy.stats[stat])+1
		break
	if loot.validate(copy).is_empty(): forged_ok = false
	var legendary: Dictionary = loot.roll_item(rng,20,"legendary","weapon")
	check(legendary.quality == "legendary" and legendary.has("legendary_id"),"L-4 the legendary used for the forgery check really is a legendary")
	var other_slot := ""
	for row in loot.data.legendaries:
		if not "weapon" in row.slots: other_slot = row.id
	if not other_slot.is_empty():
		copy = legendary.duplicate(true)
		copy.legendary_id = other_slot
		if loot.validate(copy).is_empty(): forged_ok = false
	copy = item.duplicate(true)
	copy.required_level = int(copy.required_level)+1
	if loot.validate(copy).is_empty(): forged_ok = false
	check(forged_ok,"L-4 affix range, unknown affix, unique stats, legendary of another slot and required level are still rejected")
	# L-5: a renamed unique goes back to the data's name and description.
	var renamed: Dictionary = loot.make_unique("winter_heart",12)
	var original: Dictionary = renamed.duplicate(true)
	renamed.name = "옛 이름"
	renamed.description = "옛 설명"
	var back: Dictionary = loot.dress(renamed)
	check(back.name == original.name and back.description == original.description and back.stats == original.stats,"L-5 dress() restores a unique's name and description from the data")
	# Rare names are kept as written (the data has no word ids).
	var rare: Dictionary = loot.roll_item(rng,12,"rare","head")
	rare.name = "세 낱말 이름"
	check(loot.dress(rare).name == "세 낱말 이름","L-5b dress() keeps a rare item's own name")
	# L-6: the frozen bundle of items rolled at the baseline data still validates.
	var bundle_text := FileAccess.get_file_as_string("res://chapter1/tests/fixtures/loot_compat_items.json")
	var bundle: Variant = JSON.parse_string(bundle_text)
	var bundle_ok: bool = bundle is Dictionary and bundle.get("items") is Array and bundle.items.size() >= 200
	var bad := 0
	if bundle_ok:
		for entry in bundle.items:
			var fixed: Dictionary = entry.duplicate(true)
			# JSON turns integers into floats; the profile reader converts them back before validating.
			fixed.item_level = int(fixed.item_level)
			fixed.required_level = int(fixed.required_level)
			fixed.grammar = int(fixed.grammar)
			for stat in fixed.stats: fixed.stats[stat] = int(fixed.stats[stat])
			for affix in fixed.affixes: affix.value = int(affix.value)
			if not loot.validate(fixed).is_empty(): bad += 1
	check(bundle_ok and bad == 0,"L-6 every item in loot_compat_items.json validates against the current data (%d failing)"%bad)
	# L-7: a renamed copy of the data is honoured; items rolled with the original data still validate and are re-dressed.
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Loot.DATA_PATH))
	raw.bases[0].name = "새 기본 이름"
	raw.affixes[0].name = "새 접두"
	raw.uniques[0].name = "새 고유 이름"
	raw.uniques[0].description = "새 고유 설명"
	var copy_path := "res://_local/d5/loot-renamed.json"
	DirAccess.make_dir_recursive_absolute("res://_local/d5")
	var handle := FileAccess.open(copy_path,FileAccess.WRITE)
	check(handle != null,"L-7 the renamed data copy can be written under _local")
	if handle == null: return
	handle.store_string(JSON.stringify(raw,"\t"))
	handle.close()
	var renamed_loot = Loot.new()
	check(renamed_loot.load_file(copy_path),"L-7 renamed data copy loads: "+str(renamed_loot.errors))
	var old_unique: Dictionary = loot.make_unique(String(raw.uniques[0].id),int(raw.uniques[0].level))
	var old_base_item: Dictionary = {}
	var old_affix_item: Dictionary = {}
	var base_id := String(raw.bases[0].id)
	var affix_id := String(raw.affixes[0].id)
	for i in 4000:
		var rolled_item: Dictionary = loot.roll_item(rng,1+i%30,["common","magic"][i%2])
		if old_base_item.is_empty() and rolled_item.base_id.ends_with("."+base_id) and rolled_item.quality == "common": old_base_item = rolled_item
		if old_affix_item.is_empty():
			for entry in rolled_item.affixes:
				if entry.id == affix_id: old_affix_item = rolled_item
		if not old_base_item.is_empty() and not old_affix_item.is_empty(): break
	var renamed_ok := not old_base_item.is_empty() and not old_affix_item.is_empty()
	if renamed_ok:
		renamed_ok = renamed_loot.validate(old_unique).is_empty() and renamed_loot.validate(old_base_item).is_empty() and renamed_loot.validate(old_affix_item).is_empty()
		renamed_ok = renamed_ok and renamed_loot.dress(old_unique).name == "새 고유 이름" and renamed_loot.dress(old_unique).description == "새 고유 설명"
		renamed_ok = renamed_ok and "새 기본 이름" in renamed_loot.dress(old_base_item).name and "새 접두" in renamed_loot.dress(old_affix_item).name
	check(renamed_ok,"L-7 items rolled with the old names validate against renamed data and dress() uses the new names")

func finish() -> void:
	print("CHAPTER1_LOOT_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"scope":"loot grammar v2 only; not wired into the running chapter"}))
	quit(0 if failures.is_empty() else 1)
