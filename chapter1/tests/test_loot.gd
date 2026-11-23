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
	affix_checks(loot)
	roll_checks(loot)
	pity_checks(loot)
	luck_checks()
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
	for entry in loot.data.rare_names.first: words.append(entry.name)
	for entry in loot.data.rare_names.second: words.append(entry.name)
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
			if not loot._check_text({"name":str(first_word.name)+" "+str(second_word.name),"description":""}).is_empty(): text_ok = false
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

## D23 T1-A. The hash of 84,000 off-path rolls (7 slots x levels 6/11/15 x 4,000, quality cycling common/magic/rare/legendary, seed 20261123)
## taken with loot.gd as it was before T1-A (main c3c26db). The off path must keep producing exactly these items.
const OFF_PATH_HASH := "da3485dd7275ccbe409f434292fd2590a22510478961b468ba80b014a06efe9a"
const AFFIX_FIXTURE := "res://chapter1/tests/fixtures/loot_affix_v2_items.json"
const BAD_DIR := "res://_local/d23t1a"

## Item dictionaries read from a fixture file, with the integer fields JSON turned into floats put back.
func fixture_items(path: String) -> Array:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var list: Array = []
	if not doc is Dictionary or not doc.get("items") is Array: return list
	for entry in doc.items:
		var fixed: Dictionary = entry.duplicate(true)
		fixed.item_level = int(fixed.item_level)
		fixed.required_level = int(fixed.required_level)
		fixed.grammar = int(fixed.grammar)
		for stat in fixed.stats: fixed.stats[stat] = int(fixed.stats[stat])
		for affix in fixed.affixes: affix.value = int(affix.value)
		list.append(fixed)
	return list

func bad_block_loads(raw: Dictionary, mutate: Callable, name_: String) -> bool:
	var doc: Dictionary = raw.duplicate(true)
	mutate.call(doc)
	DirAccess.make_dir_recursive_absolute(BAD_DIR)
	var path := BAD_DIR+"/"+name_+".json"
	var handle := FileAccess.open(path,FileAccess.WRITE)
	handle.store_string(JSON.stringify(doc,"\t"))
	handle.close()
	var probe = Loot.new()
	return probe.load_file(path)

func mutate_nothing(_doc: Dictionary) -> void:
	pass

func mutate_good_profile(doc: Dictionary) -> void:
	doc.treasure_classes.champion["lines_profile"] = "rare_boss"

func mutate_dup_id(doc: Dictionary) -> void:
	doc.affix_rolls.pool[1].id = doc.affix_rolls.pool[0].id

func mutate_unknown_stat(doc: Dictionary) -> void:
	doc.affix_rolls.pool[0].stat = "no_such_stat"

func mutate_low_above_high(doc: Dictionary) -> void:
	doc.affix_rolls.pool[0].low = int(doc.affix_rolls.pool[0].high)+1

func mutate_ladder_values_fall(doc: Dictionary) -> void:
	for row in doc.affix_rolls.pool:
		if row.id == "wrath4":
			row.low = 1000
			row.high = 1200

func mutate_unknown_tier(doc: Dictionary) -> void:
	doc.affix_rolls.pool[0].tier = 9

func mutate_unknown_lines_profile(doc: Dictionary) -> void:
	doc.treasure_classes.champion["lines_profile"] = "no_such_profile"

func mutate_bad_class(doc: Dictionary) -> void:
	doc.affix_rolls.pool[0]["class"] = "weird"

func mutate_legacy_unknown_id(doc: Dictionary) -> void:
	doc.affix_rolls.legacy_windows["ghost"] = {"level":1,"max_level":9}

func affix_checks(loot: RefCounted) -> void:
	var block: Dictionary = loot.data.get("affix_rolls",{})
	check(not block.is_empty() and not loot.affix_rolls_on(),"T1-A the shipped data carries the affix_rolls block and it is off")
	if block.is_empty(): return
	# Off path unchanged: the hash of the rolls taken before the change.
	check(loot.set_affix_rolls(false) and not loot.affix_rolls_on(),"T1-A set_affix_rolls(false) is always accepted")
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var hash_rng := RandomNumberGenerator.new()
	hash_rng.seed = 20261123
	var rolled := 0
	for slot in loot.data.slots:
		for level in [6,11,15]:
			for i in 4000:
				ctx.update(JSON.stringify(loot.roll_item(hash_rng,level,["common","magic","rare","legendary"][i%4],slot)).to_utf8_buffer())
				rolled += 1
	var off_hash := ctx.finish().hex_encode()
	check(rolled == 84000 and off_hash == OFF_PATH_HASH,"T1-A off path: %d rolls hash to the value taken before the change (got %s)"%[rolled,off_hash])
	# Data: core_reads mirrors STATS_READ; the window rule; skill rows.
	var mirror_ok := true
	for row in block.pool:
		if bool(row.core_reads) != (String(row.stat) in Loot.STATS_READ): mirror_ok = false
	for stat in Loot.STATS_READ:
		if not loot.data.limits.has(stat): mirror_ok = false
	check(mirror_ok,"T1-A the data's core_reads flag equals membership in STATS_READ for every pool row")
	var tier_min: Dictionary = {}
	for entry in block.tiers: tier_min[int(entry.tier)] = int(entry.min_level)
	var ladders: Dictionary = {}
	var all_rows: Array = []
	all_rows.append_array(loot.data.affixes)
	all_rows.append_array(block.pool)
	for row in all_rows:
		var key := String(row.group)+"|"+String(row.stat)
		if not ladders.has(key): ladders[key] = []
		ladders[key].append(row)
	var window_ok := true
	var window_first := ""
	for key in ladders:
		var rows: Array = ladders[key]
		var full: bool = rows.size() == tier_min.size()
		for row in rows:
			var live: Dictionary = block.legacy_windows.get(row.id,{})
			var lo := int(live.get("level",row.level))
			var hi := int(live.get("max_level",row.max_level))
			var tier := int(row.tier)
			var want_hi := int(loot.data.max_item_level)
			if full and tier_min.has(tier+int(block.tier_window)): want_hi = int(tier_min[tier+int(block.tier_window)])-1
			var skill_floor := int(block.skill_min_item_level) if row["class"] == "skill" else 0
			var lo_ok: bool = lo >= int(tier_min[tier]) if tier == 1 else lo == maxi(int(tier_min[tier]),skill_floor)
			if row["class"] == "skill" and lo < skill_floor: lo_ok = false
			if hi != want_hi or not lo_ok:
				window_ok = false
				if window_first.is_empty(): window_first = "%s tier %d window %d-%d, want hi %d"%[row.id,tier,lo,hi,want_hi]
	check(window_ok,"T1-A every ladder row's level window follows tier_window %d from the tiers table; skill rows open at skill_min_item_level (%s)"%[int(block.tier_window),window_first])
	# A broken block is refused by load_file; the unmodified copy and a valid lines_profile are accepted.
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Loot.DATA_PATH))
	check(bad_block_loads(raw,mutate_nothing,"control"),"T1-A control: an unmodified copy of the data loads")
	check(bad_block_loads(raw,mutate_good_profile,"good_profile"),"T1-A control: a lines_profile that exists in lines loads")
	var bad_cases := {
		"dup_id": mutate_dup_id,
		"unknown_stat": mutate_unknown_stat,
		"low_above_high": mutate_low_above_high,
		"ladder_values_fall": mutate_ladder_values_fall,
		"unknown_tier": mutate_unknown_tier,
		"unknown_lines_profile": mutate_unknown_lines_profile,
		"bad_class": mutate_bad_class,
		"legacy_window_unknown_id": mutate_legacy_unknown_id,
	}
	for name_ in bad_cases:
		check(not bad_block_loads(raw,bad_cases[name_],"bad_"+name_),"T1-A a block with "+name_+" fails load_file")
	# On path: every slot x level, violations counted.
	check(loot.set_affix_rolls(true) and loot.affix_rolls_on(),"T1-A set_affix_rolls(true) is accepted for a valid block")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1123
	var violations := {"count":0,"dup_group":0,"kind_cap":0,"class_cap":0,"excludes":0,"unread_stat":0,"invalid":0}
	var first_violation := ""
	var rolled_on := 0
	var kept: Array = []
	for slot in loot.data.slots:
		for level in [6,11,15]:
			for i in 1500:
				var quality: String = ["magic","rare","legendary","rare"][i%4]
				var item: Dictionary = loot.roll_item(rng,level,quality,slot,{},"rare_boss" if i%8 == 3 else "")
				rolled_on += 1
				if kept.size() < 1000 and i%5 == 0: kept.append(item)
				var lines: int = item.affixes.size()
				var table_key: String = "rare_boss" if item.quality == "rare" and i%8 == 3 else String(item.quality)
				var allowed: Dictionary = block.lines.get(table_key,{})
				if item.quality in ["magic","rare","legendary"] and not allowed.has(str(lines)):
					violations.count += 1
					if first_violation.is_empty(): first_violation = "count "+JSON.stringify(item)
				var seen_groups: Dictionary = {}
				var kinds := {"prefix":0,"suffix":0}
				var classes: Dictionary = {}
				for entry in item.affixes:
					var def: Dictionary = loot.affix_def(entry.id)
					if seen_groups.has(def.group): violations.dup_group += 1
					seen_groups[def.group] = true
					kinds[def.kind] += 1
					classes[def["class"]] = int(classes.get(def["class"],0))+1
					if not String(def.stat) in Loot.STATS_READ: violations.unread_stat += 1
					if item.quality == "legendary":
						for stat in def.get("excludes",[]):
							if loot._legendaries[item.legendary_id].stats.has(stat): violations.excludes += 1
				var kind_cap := int(block.kind_caps.get(item.quality,0))
				if int(kinds.prefix) > kind_cap or int(kinds.suffix) > kind_cap: violations.kind_cap += 1
				for kind in classes:
					if int(classes[kind]) > int(block.class_caps.get(item.quality,{}).get(kind,99)): violations.class_cap += 1
				if not loot.validate(item).is_empty():
					violations.invalid += 1
					if first_violation.is_empty(): first_violation = "invalid "+str(loot.validate(item))+" "+JSON.stringify(item)
	var total_violations := 0
	for key in violations: total_violations += int(violations[key])
	check(total_violations == 0,"T1-A on path %d rolls (slot x level 6/11/15): lines in range, no repeated group, kind and class caps, legendary excludes, only STATS_READ stats, all validate: %s %s"%[rolled_on,JSON.stringify(violations),first_violation])
	# Same seed, same items.
	var twin_a := RandomNumberGenerator.new()
	twin_a.seed = 77
	var twin_b := RandomNumberGenerator.new()
	twin_b.seed = 77
	var twin_same := true
	for i in 600:
		var level_twin := 1+i%30
		if JSON.stringify(loot.roll_item(twin_a,level_twin,"rare","",{},"rare_boss")) != JSON.stringify(loot.roll_item(twin_b,level_twin,"rare","",{},"rare_boss")): twin_same = false
	check(twin_same,"T1-A on path: same seed gives the same items")
	# Items rolled ON stay valid with the switch OFF.
	var off_failures := 0
	loot.set_affix_rolls(false)
	for item in kept:
		if not loot.validate(item).is_empty(): off_failures += 1
	check(kept.size() == 1000 and off_failures == 0,"T1-A %d items rolled with the switch on all validate with it off (%d failing)"%[kept.size(),off_failures])
	# Frozen bundles, switch off and on.
	var frozen: Array = fixture_items(AFFIX_FIXTURE)
	var old_bundle: Array = fixture_items("res://chapter1/tests/fixtures/loot_compat_items.json")
	var five := 0
	for item in frozen:
		if item.quality == "rare" and item.affixes.size() == 5: five += 1
	var frozen_bad := 0
	var old_bad := 0
	for mode in [false,true]:
		loot.set_affix_rolls(mode)
		for item in frozen:
			if not loot.validate(item).is_empty(): frozen_bad += 1
		for item in old_bundle:
			if not loot.validate(item).is_empty(): old_bad += 1
	check(frozen.size() >= 600 and five >= 5 and frozen_bad == 0,"T1-A loot_affix_v2_items.json (%d items, %d five-line rares) validates with the switch off and on (%d failing)"%[frozen.size(),five,frozen_bad])
	check(old_bundle.size() >= 200 and old_bad == 0,"T1-A loot_compat_items.json (%d items) validates with the switch off and on (%d failing)"%[old_bundle.size(),old_bad])
	# validate still rejects what it did not widen: a sixth line.
	loot.set_affix_rolls(false)
	var strict_ok := false
	for item in frozen:
		if item.quality == "rare" and item.affixes.size() == 5:
			var six: Dictionary = item.duplicate(true)
			six.affixes.append(six.affixes[0].duplicate(true))
			strict_ok = not loot.validate(six).is_empty()
			break
	check(strict_ok,"T1-A validate still rejects a rare item with a sixth line")
	# Read helpers.
	check(loot.affix_tier("wrath5") == 5 and loot.affix_tier("wrath") == 1 and loot.affix_tier("no_such") == 0 and loot.affix_class("wrath5") == "number" and loot.affix_def("wrath5").get("stat","") == "damage_bps" and loot.affix_def("no_such").is_empty(),"T1-A affix_tier, affix_class and affix_def read live and pool rows")
	loot.set_affix_rolls(bool(block.enabled))

# ------------------------------------------------------------------ B1 (tech review 2026-11-23): the ON path, roll by roll
# The golden's one affix-on run can miss a data branch by luck, so the draws are checked here one branch at a time: fixed seeds, the
# affix_rolls roll switched on in memory, thousands of rolls, and every expected number is READ from the data (loot.json affix_rolls),
# never typed here (only ROLL_HASH is). A count is accepted within 5 sigma of its expectation (sigma = sqrt(n p (1-p))), plus one.
# Also covers B4: a ladder weight put back (vs_status 10 -> 40) is seen by the ladder-weight check.
# ROLL_HASH: if the data or the roll order changes ON PURPOSE, run this test, copy the "got" value from the failing line and update it
# in the same commit (say so in the message). An unplanned change of the hash is the finding.
const ROLL_SEED := 20261124
const ROLL_HASH := "3c87957fd56293156975d00c5cb66053491ec88127656293ee529670df78b684"
const SIGMAS := 5.0

func sigma_ok(observed: int, n: int, p: float) -> bool:
	return absf(float(observed) - float(n) * p) <= SIGMAS * sqrt(float(n) * p * (1.0 - p)) + 1.0

func row_tier(row: Dictionary) -> int:
	return int(row.get("tier", 1))

## Every row of the roll (live rows first, then the pool), as the roll sees it.
func all_rows(loot: RefCounted) -> Array:
	var rows: Array = []
	rows.append_array(loot.data.affixes)
	rows.append_array(loot.data.affix_rolls.pool)
	return rows

## [lo, hi] item levels where a row is open (a live row follows legacy_windows when it has an entry).
func row_window(block: Dictionary, row: Dictionary) -> Array:
	var legacy: Dictionary = block.legacy_windows.get(row.id, {})
	return [int(legacy.get("level", row.level)), int(legacy.get("max_level", row.max_level))]

## ladder key -> {weight, tiers: {tier: true}, rows}: rows with the same group and stat; the weight is the lowest tier row's.
func ladders_of(loot: RefCounted) -> Dictionary:
	var out: Dictionary = {}
	for row in all_rows(loot):
		var key := String(row.group) + "|" + String(row.stat)
		if not out.has(key): out[key] = {"weight": int(row.weight), "low": row_tier(row), "tiers": {}, "rows": []}
		var ladder: Dictionary = out[key]
		ladder.rows.append(row)
		ladder.tiers[row_tier(row)] = true
		if row_tier(row) < int(ladder.low):
			ladder.low = row_tier(row)
			ladder.weight = int(row.weight)
	return out

## ladder key -> weight of the ladders that can give a first line to this slot at this item level.
func open_ladders(loot: RefCounted, slot: String, level: int) -> Dictionary:
	var block: Dictionary = loot.data.affix_rolls
	var out: Dictionary = {}
	var ladders := ladders_of(loot)
	for key in ladders:
		var ladder: Dictionary = ladders[key]
		for row in ladder.rows:
			var win := row_window(block, row)
			if slot in row.slots and level >= win[0] and level <= win[1] and String(row.stat) in Loot.STATS_READ:
				out[key] = int(ladder.weight)
				break
	return out

func line_key(line: Dictionary) -> String:
	return String(line.group) + "|" + String(line.stat)

func roll_checks(loot: RefCounted) -> void:
	var block: Dictionary = loot.data.get("affix_rolls", {})
	if block.is_empty():
		check(false, "B1 the data has no affix_rolls block")
		return
	check(loot.set_affix_rolls(true) and loot.affix_rolls_on(), "B1 the affix_rolls roll is switched on in memory")
	var seen_stats: Dictionary = {}
	var out_of_range := 0
	var unread := 0
	var line_total := 0
	var ladders := ladders_of(loot)
	var unread_ids: Dictionary = {}
	for row in all_rows(loot):
		if not String(row.stat) in Loot.STATS_READ: unread_ids[row.id] = true
	check(unread_ids.size() > 0, "B1 the data still has rows whose stat the core does not read (%d), so check (e) is not empty" % unread_ids.size())
	# (a) the number of lines: the treasure class's profile, read from the data
	var boss_class: Dictionary = loot.data.treasure_classes.boss
	check(String(boss_class.get("lines_profile", "")) == "rare_boss" and block.lines.has("rare_boss") and block.lines.has("rare"), "B1 boss carries lines_profile rare_boss and the data has both rare tables")
	var rolls := 6000
	var boss_counts: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = ROLL_SEED
	for i in rolls:
		var drops: Array[Dictionary] = loot.roll_class(rng, "boss", 12, "chapter1.skill.ember")
		var first: Dictionary = drops[0]
		boss_counts[first.affixes.size()] = int(boss_counts.get(first.affixes.size(), 0)) + 1
		line_total += first.affixes.size()
		for line in first.affixes:
			seen_stats[line.stat] = true
			if String(line.id) in unread_ids: unread += 1
			var def: Dictionary = loot.affix_def(line.id)
			if int(line.value) < int(def.low) or int(line.value) > int(def.high): out_of_range += 1
	var boss_total := 0
	for k in block.lines.rare_boss: boss_total += int(block.lines.rare_boss[k])
	for k in block.lines.rare_boss:
		var p := float(block.lines.rare_boss[k]) / float(boss_total)
		check(sigma_ok(int(boss_counts.get(int(k), 0)), rolls, p), "B1 (a) boss guaranteed rare: %s lines in %d of %d rolls, rare_boss table says %.3f (got %.3f)" % [k, int(boss_counts.get(int(k), 0)), rolls, p, float(boss_counts.get(int(k), 0)) / rolls])
	var plain_counts: Dictionary = {}
	rng.seed = ROLL_SEED + 1
	for i in rolls:
		var item: Dictionary = loot.roll_item(rng, 15, "rare", "")
		plain_counts[item.affixes.size()] = int(plain_counts.get(item.affixes.size(), 0)) + 1
		for line in item.affixes:
			seen_stats[line.stat] = true
			if String(line.id) in unread_ids: unread += 1
			var def2: Dictionary = loot.affix_def(line.id)
			if int(line.value) < int(def2.low) or int(line.value) > int(def2.high): out_of_range += 1
	var rare_total := 0
	for k in block.lines.rare: rare_total += int(block.lines.rare[k])
	for k in block.lines.rare:
		var p2 := float(block.lines.rare[k]) / float(rare_total)
		check(sigma_ok(int(plain_counts.get(int(k), 0)), rolls, p2), "B1 (a) an ordinary rare: %s lines in %d of %d rolls, rare table says %.3f (got %.3f)" % [k, int(plain_counts.get(int(k), 0)), rolls, p2, float(plain_counts.get(int(k), 0)) / rolls])
	var profile_gap := absf(float(block.lines.rare_boss.get("3", 0)) / boss_total - float(block.lines.rare.get("3", 0)) / rare_total)
	check(profile_gap > 0.10, "B1 (a) the two tables differ by %.2f in the three-line share, so a lost lines_profile would be seen" % profile_gap)
	# (b) + (c) the tiers open at each item level, and their shares, over rare items of random slots
	var tiers: Array = block.tiers
	var window := int(block.tier_window)
	var full: Dictionary = {}
	for key in ladders:
		var ok := String(ladders[key].rows[0].stat) in Loot.STATS_READ
		for entry in tiers:
			if not ladders[key].tiers.has(int(entry.tier)): ok = false
		if ok: full[key] = true
	check(full.size() >= 5, "B1 the data has %d full five-tier ladders that the core reads" % full.size())
	var tier_seen_at: Dictionary = {}
	for level in [1, 4, 5, 8, 9, 12, 13, 14, 15, 30]:
		var open: Array = []
		for entry in tiers:
			if int(level) >= int(entry.min_level): open.append(int(entry.tier))
		open.sort()
		var window_tiers: Array = open.slice(maxi(0, open.size() - window))
		var top: int = open.max() if not open.is_empty() else 1
		var share_sum := 0
		var share_of: Dictionary = {}
		for entry in tiers: share_of[int(entry.tier)] = int(entry.share)
		for t in window_tiers: share_sum += int(share_of[t])
		rng.seed = ROLL_SEED + 100 + int(level)
		var by_tier: Dictionary = {}
		var on_full := 0
		var above := 0
		var below := 0
		for i in 2500:
			var item2: Dictionary = loot.roll_item(rng, int(level), "rare", "")
			for line in item2.affixes:
				seen_stats[line.stat] = true
				if String(line.id) in unread_ids: unread += 1
				var def3: Dictionary = loot.affix_def(line.id)
				if int(line.value) < int(def3.low) or int(line.value) > int(def3.high): out_of_range += 1
				var t := row_tier(def3)
				tier_seen_at[str(level) + ":" + str(t)] = true
				if t > top: above += 1
				if full.has(line_key(line)):
					on_full += 1
					by_tier[t] = int(by_tier.get(t, 0)) + 1
					if not t in window_tiers: below += 1
		check(above == 0, "B1 (b) item level %d: no line above tier %d, the highest tier opened by tiers.min_level (%d lines above)" % [level, top, above])
		check(below == 0, "B1 (b) item level %d: lines on full ladders stay in the top %d open tiers %s (%d outside)" % [level, window, str(window_tiers), below])
		if level == 15 or level == 13 or level == 9:
			for t in window_tiers:
				var p3 := float(share_of[t]) / float(share_sum)
				check(sigma_ok(int(by_tier.get(t, 0)), on_full, p3), "B1 (c) item level %d: tier %d took %d of %d lines on full ladders, share says %.3f (got %.3f)" % [level, t, int(by_tier.get(t, 0)), on_full, p3, float(by_tier.get(t, 0)) / maxf(1.0, on_full)])
	var v_min := 0
	for entry in tiers:
		if int(entry.tier) == 5: v_min = int(entry.min_level)
	check(tier_seen_at.has("15:5") and tier_seen_at.has("15:4") and tier_seen_at.has("13:4"), "B1 (b) tiers IV and V do come out (V at level 15, IV from 13)")
	var five_early := false
	for level in [1, 4, 5, 8, 9, 12, 13, 14]:
		if tier_seen_at.has(str(level) + ":5"): five_early = true
	check(v_min == 15 and not five_early, "B1 (b) tier V only from item level %d (the data's min_level), never below it" % v_min)
	# (d) ladder weights: the first line of a rare item picks a ladder with the weight of its lowest-tier row (B4: vs_status ladders)
	for combo in [["hands", 15], ["hands", 9], ["weapon", 15], ["head", 12]]:
		var slot: String = combo[0]
		var level: int = combo[1]
		var expect := open_ladders(loot, slot, level)
		var weight_total := 0
		for key in expect: weight_total += int(expect[key])
		rng.seed = ROLL_SEED + 500 + level + slot.length()
		var firsts: Dictionary = {}
		var n_first := 20000
		for i in n_first:
			var item3: Dictionary = loot.roll_item(rng, level, "rare", slot)
			if item3.affixes.is_empty(): continue
			var key2 := line_key(item3.affixes[0])
			firsts[key2] = int(firsts.get(key2, 0)) + 1
			for line in item3.affixes:
				seen_stats[line.stat] = true
				if String(line.id) in unread_ids: unread += 1
				var def4: Dictionary = loot.affix_def(line.id)
				if int(line.value) < int(def4.low) or int(line.value) > int(def4.high): out_of_range += 1
		var stranger := false
		for key3 in firsts:
			if not expect.has(key3): stranger = true
		check(not stranger and weight_total > 0, "B1 (d) %s at level %d: every first line comes from a ladder the data opens there (%d ladders)" % [slot, level, expect.size()])
		for key4 in expect:
			var p4 := float(expect[key4]) / float(weight_total)
			check(sigma_ok(int(firsts.get(key4, 0)), n_first, p4), "B1 (d) %s at level %d: ladder %s picked %d of %d, weight %d of %d says %.4f (got %.4f)" % [slot, level, key4, int(firsts.get(key4, 0)), n_first, int(expect[key4]), weight_total, p4, float(firsts.get(key4, 0)) / n_first])
		if slot == "hands" and level == 15:
			var vs_n := 0
			var vs_w := 0
			var ref_key := "damage|damage_bps"
			for key5 in expect:
				if key5.begins_with("vs_status|"):
					vs_n += int(firsts.get(key5, 0))
					vs_w += int(expect[key5])
			var ref_w := int(expect.get(ref_key, 0))
			var ladders_vs := 0
			for key6 in ladders:
				if key6.begins_with("vs_status|") and expect.has(key6): ladders_vs += 1
			check(ladders_vs >= 2 and ref_w > 0, "B1 (d) hands at 15: %d vs_status ladders the core reads weigh %d together against %d for damage" % [ladders_vs, vs_w, ref_w])
			# B4: the meaning of the data trim: every vs_status ladder (all four, read or not) weighs less than every other condition ladder.
			var other_condition_min := 1 << 30
			var vs_max := 0
			var vs_ladders := 0
			for key7 in ladders:
				var ladder7: Dictionary = ladders[key7]
				if key7.begins_with("vs_status|"):
					vs_ladders += 1
					vs_max = maxi(vs_max, int(ladder7.weight))
				elif String(ladder7.rows[0].get("class", "")) == "condition":
					other_condition_min = mini(other_condition_min, int(ladder7.weight))
			check(vs_ladders == 4 and vs_max < other_condition_min, "B1 (d)/B4 the four vs_status ladders weigh at most %d, below every other condition ladder (lowest %d)" % [vs_max, other_condition_min])
			var ref_n := int(firsts.get(ref_key, 0))
			var ratio_expect := float(vs_w) / float(ref_w)
			check(absf(float(vs_n) / maxf(1.0, ref_n) - ratio_expect) <= ratio_expect * 0.35 + 0.01, "B1 (d) hands at 15: vs_status first lines against damage first lines %d : %d = %.3f, the weights say %.3f" % [vs_n, ref_n, float(vs_n) / maxf(1.0, ref_n), ratio_expect])
	# (e) no row the core does not read ever comes out; (f) every value lies inside its row's low..high
	check(unread == 0, "B1 (e) rows whose stat is not in STATS_READ never rolled (%d lines of %d unread rows)" % [unread, unread_ids.size()])
	var stranger_stat := false
	for stat in seen_stats:
		if not String(stat) in Loot.STATS_READ: stranger_stat = true
	check(not stranger_stat and seen_stats.size() >= 15, "B1 (e) every rolled stat is in STATS_READ (%d different stats seen)" % seen_stats.size())
	check(out_of_range == 0, "B1 (f) every rolled value lies inside its row's low..high (%d outside)" % out_of_range)
	# the pinned hash: a mixed batch of qualities, levels, slots and treasure classes, in a fixed order
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var pin_rng := RandomNumberGenerator.new()
	pin_rng.seed = ROLL_SEED + 9000
	var pinned := 0
	for level in [3, 9, 13, 15]:
		for quality in ["magic", "rare", "legendary"]:
			for i in 150:
				ctx.update(JSON.stringify(loot.roll_item(pin_rng, level, quality, "", {}, "rare_boss" if i % 3 == 0 else "")).to_utf8_buffer())
				pinned += 1
	for class_id in ["normal", "elite", "carrier", "champion", "boss", "chest"]:
		for i in 100:
			ctx.update(JSON.stringify(loot.roll_class(pin_rng, class_id, 12, "chapter1.skill.frost")).to_utf8_buffer())
			pinned += 1
	var got := ctx.finish().hex_encode()
	check(pinned == 2400 and got == ROLL_HASH, "B1 pinned hash of %d rolls on the ON path is %s (got %s; update ROLL_HASH only for a planned data or roll-order change)" % [pinned, ROLL_HASH, got])
	loot.set_affix_rolls(bool(block.enabled))
## D23 T9: the drop pity block and roll_class(first_quality).
func mutate_pity_enabled_text(doc: Dictionary) -> void:
	doc.pity.enabled = "yes"

func mutate_pity_runs_zero(doc: Dictionary) -> void:
	doc.pity.runs_without_legendary = 0

func mutate_pity_runs_51(doc: Dictionary) -> void:
	doc.pity.runs_without_legendary = 51

func mutate_pity_upgrade(doc: Dictionary) -> void:
	doc.pity.upgrade = "anything_else"

func mutate_pity_extra_key(doc: Dictionary) -> void:
	doc.pity["more"] = 1

func mutate_pity_missing_key(doc: Dictionary) -> void:
	doc.pity.erase("upgrade")

func mutate_pity_absent(doc: Dictionary) -> void:
	doc.erase("pity")

func pity_checks(loot: RefCounted) -> void:
	check(loot.data.has("pity") and not loot.pity_on() and loot.pity_runs() == 5,"T9 the shipped data has the pity block, off, 5 runs")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Loot.DATA_PATH))
	var bad := {"enabled_not_bool": mutate_pity_enabled_text,"runs_zero": mutate_pity_runs_zero,"runs_51": mutate_pity_runs_51,"upgrade_other": mutate_pity_upgrade,"extra_key": mutate_pity_extra_key,"missing_key": mutate_pity_missing_key}
	for name_ in bad:
		check(not bad_block_loads(raw,bad[name_],"pity_"+name_),"T9 a pity block with "+name_+" fails load_file")
	check(bad_block_loads(raw,mutate_pity_absent,"pity_absent"),"T9 data without a pity block loads (the pity is off)")
	var no_pity = Loot.new()
	check(no_pity.load_file(BAD_DIR+"/pity_absent.json") and not no_pity.pity_on() and not no_pity.set_pity(true) and no_pity.set_pity(false),"T9 without a block set_pity(true) is refused and the pity stays off")
	check(loot.set_pity(true) and loot.pity_on() and loot.set_pity(false) and not loot.pity_on(),"T9 set_pity switches it in memory")
	# roll_class: the first guaranteed line of the boss class becomes a legendary; the rest is left alone.
	var rng := RandomNumberGenerator.new()
	rng.seed = 90909
	var first_ok := true
	var later_not_all_legendary := false
	var identity_ok := true
	for i in 300:
		var drops: Array[Dictionary] = loot.roll_class(rng,"boss",15,"chapter1.skill.frost",{},"legendary")
		if drops.size() != 5 or drops[0].quality != "legendary" or not drops[0].has("legendary_id") or not loot.validate(drops[0]).is_empty(): first_ok = false
		for j in range(1,drops.size()):
			if drops[j].quality != "legendary": later_not_all_legendary = true
	check(first_ok and later_not_all_legendary,"T9 roll_class(boss, first_quality legendary): the first of five is a valid legendary, the other lines are rolled as before")
	var champion_drops: Array[Dictionary] = loot.roll_class(rng,"champion",8,"chapter1.skill.ember")
	check(champion_drops.size() == 3,"T9 the champion class is unchanged without the argument")
	for class_id in ["normal","elite","champion","boss","chest","ritual_chest"]:
		var plain := RandomNumberGenerator.new()
		plain.seed = 4242
		var empty := RandomNumberGenerator.new()
		empty.seed = 4242
		for i in 300:
			if JSON.stringify(loot.roll_class(plain,class_id,12,"chapter1.skill.arc")) != JSON.stringify(loot.roll_class(empty,class_id,12,"chapter1.skill.arc",{},"")): identity_ok = false
	check(identity_ok,"T9 an empty first_quality draws exactly what the call without it draws (6 classes x 300 rolls)")

## D23 T8: the luck block, quality_weights and the weights roll_class draws from. LK1~LK9 of the T11 directive.
func mutate_luck_missing_key(doc: Dictionary) -> void:
	doc.luck.erase("snapshot")

func mutate_luck_extra_key(doc: Dictionary) -> void:
	doc.luck["more"] = 1

func mutate_luck_enabled_text(doc: Dictionary) -> void:
	doc.luck.enabled = "yes"

func mutate_luck_cap_zero(doc: Dictionary) -> void:
	doc.luck.cap_bps = 0

func mutate_luck_k_rare_zero(doc: Dictionary) -> void:
	doc.luck.k.rare = 0

func mutate_luck_snapshot_other(doc: Dictionary) -> void:
	doc.luck.snapshot = "every_roll"

func mutate_luck_absent(doc: Dictionary) -> void:
	doc.erase("luck")

func luck_expected(base: Dictionary, shrine: Dictionary, luck: int, ks: Dictionary, cap: int) -> Dictionary:
	var out: Dictionary = base.duplicate()
	for quality in shrine:
		if out.has(quality): out[quality] = int(out[quality]) * int(shrine[quality]) / 10000
	var l := mini(luck, cap)
	if l > 0:
		for quality in ks:
			var k := int(ks[quality])
			out[quality] = int(out[quality]) * (10000 + l * k / (l + k)) / 10000
	return out

func luck_checks() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Loot.DATA_PATH))
	var loot = Loot.new()
	check(loot.load_file(), "LK loot data loads")
	check(loot.data.has("luck") and not loot.luck_on() and loot.luck_cap_bps() == 3000, "LK1 the shipped data has the luck block, off, cap 3000")
	# LK1 the block shape. (The directive says six keys; the block it shows has five: enabled, stat, cap_bps, k, snapshot.)
	var bad := {"missing_key": mutate_luck_missing_key, "extra_key": mutate_luck_extra_key, "enabled_text": mutate_luck_enabled_text, "cap_zero": mutate_luck_cap_zero, "k_rare_zero": mutate_luck_k_rare_zero, "snapshot_other": mutate_luck_snapshot_other}
	for name_ in bad:
		check(not bad_block_loads(raw, bad[name_], "luck_" + name_), "LK1 a luck block with " + name_ + " fails load_file")
	check(bad_block_loads(raw, mutate_luck_absent, "luck_absent"), "LK1 data without a luck block loads")
	var none = Loot.new()
	check(none.load_file(BAD_DIR + "/luck_absent.json") and not none.luck_on() and not none.set_luck(true) and none.set_luck(false) and none.luck_cap_bps() == 0, "LK1 without a block set_luck(true) is refused and the luck stays off")
	# LK2 quality_weights without effect
	var plain := JSON.stringify(loot.data.treasure_classes.normal.quality)
	check(JSON.stringify(loot.quality_weights("normal")) == plain and JSON.stringify(loot.quality_weights("normal", {})) == plain and JSON.stringify(loot.quality_weights("normal", {"luck_bps": 0})) == plain and JSON.stringify(loot.quality_weights("normal", {"luck_bps": 3000})) == plain, "LK2 quality_weights: no mods, {}, luck 0 and luck-off luck 3000 all give the data weights (same values, same order)")
	check(loot.quality_weights("no_such_class", {"luck_bps": 3000}).is_empty(), "LK2 an unknown class has no weights")
	# LK3 / LK4 the formula
	check(loot.set_luck(true) and loot.luck_on(), "LK3 set_luck(true) works with the block")
	var ks: Dictionary = loot.data.luck.k
	var cap: int = loot.luck_cap_bps()
	var formula_ok := true
	var rest_ok := true
	var shrine_ok := true
	var cap_ok := true
	var shrine := {"rare": 20000, "legendary": 20000, "unique": 20000, "magic": 5000}
	for class_id in ["normal", "elite", "chest", "boss"]:
		var base: Dictionary = loot.data.treasure_classes[class_id].quality
		for luck in [1, 500, 1000, 3000]:
			var got: Dictionary = loot.quality_weights(class_id, {"luck_bps": luck})
			if JSON.stringify(got) != JSON.stringify(luck_expected(base, {}, luck, ks, cap)): formula_ok = false
			for quality in ["common", "magic"]:
				if int(got[quality]) != int(base[quality]): rest_ok = false
			var with_shrine: Dictionary = loot.quality_weights(class_id, {"luck_bps": luck, "quality_bps": shrine})
			if JSON.stringify(with_shrine) != JSON.stringify(luck_expected(base, shrine, luck, ks, cap)): shrine_ok = false
		if JSON.stringify(loot.quality_weights(class_id, {"luck_bps": 9000})) != JSON.stringify(loot.quality_weights(class_id, {"luck_bps": 3000})): cap_ok = false
	check(formula_ok, "LK3 luck on: rare, legendary and unique weights are w*(10000+L*K/(L+K))/10000 to the integer (K from the data)")
	check(rest_ok, "LK3 common and magic weights are untouched by luck")
	check(shrine_ok, "LK3 the shrine quality_bps is applied first, then luck")
	check(cap_ok, "LK4 luck_bps 9000 gives the weights of 3000 (cap)")
	# LK5 luck off: the draws are the draws of a call without mods
	var off = Loot.new()
	check(off.load_file() and not off.luck_on(), "LK5 a fresh table has the luck off")
	var identity_ok := true
	for class_id in ["normal", "elite", "champion", "boss", "chest", "ritual_chest"]:
		var a := RandomNumberGenerator.new()
		a.seed = 5151
		var b := RandomNumberGenerator.new()
		b.seed = 5151
		for i in 300:
			if JSON.stringify(off.roll_class(a, class_id, 12, "chapter1.skill.arc")) != JSON.stringify(off.roll_class(b, class_id, 12, "chapter1.skill.arc", {"luck_bps": 3000})): identity_ok = false
	check(identity_ok, "LK5 with the luck off, luck_bps 3000 in mods draws exactly what a call without mods draws (6 classes x 300 rolls)")
	# LK6 distribution: chest class (one pick, no_drop 0), level 8. The directive names normal; its 0.55% drop makes 200000 rolls only ~1100 items.
	var rolls := 200000
	var expected_on: Dictionary = loot.quality_weights("chest", {"luck_bps": 3000})
	var expected_off: Dictionary = loot.data.treasure_classes.chest.quality
	var counts_on := {"common": 0, "magic": 0, "rare": 0, "legendary": 0, "unique": 0}
	var counts_off := counts_on.duplicate()
	var rng_on := RandomNumberGenerator.new()
	rng_on.seed = 777
	var rng_off := RandomNumberGenerator.new()
	rng_off.seed = 777
	for i in rolls:
		for item in loot.roll_class(rng_on, "chest", 8, "chapter1.skill.frost", {"luck_bps": 3000}): counts_on[item.quality] += 1
		for item in loot.roll_class(rng_off, "chest", 8, "chapter1.skill.frost", {}): counts_off[item.quality] += 1
	var total_on := 0
	var total_off := 0
	for quality in expected_on: total_on += int(expected_on[quality])
	for quality in expected_off: total_off += int(expected_off[quality])
	var dist_ok := true
	var more_ok := true
	for quality in ["magic", "rare", "legendary", "unique"]:
		if not sigma_ok(int(counts_on[quality]), rolls, float(expected_on[quality]) / float(total_on)): dist_ok = false
		if not sigma_ok(int(counts_off[quality]), rolls, float(expected_off[quality]) / float(total_off)): dist_ok = false
	for quality in ["rare", "legendary", "unique"]:
		if int(counts_on[quality]) <= int(counts_off[quality]): more_ok = false
	print("LK6 chest x%d level 8, luck 3000 / luck 0: rare %d/%d legendary %d/%d unique %d/%d magic %d/%d" % [rolls, counts_on.rare, counts_off.rare, counts_on.legendary, counts_off.legendary, counts_on.unique, counts_off.unique, counts_on.magic, counts_off.magic])
	check(dist_ok, "LK6 the grade counts are within 5 sigma of the formula shares, with luck 3000 and with luck 0")
	check(more_ok, "LK6 with luck 3000 rare, legendary and unique all come more often than with luck 0 on the same seed")
	# LK7 the guaranteed line is not touched
	var guaranteed_ok := true
	for i in 300:
		var x := RandomNumberGenerator.new()
		x.seed = 8000 + i
		var y := RandomNumberGenerator.new()
		y.seed = 8000 + i
		var with_luck: Array[Dictionary] = loot.roll_class(x, "boss", 15, "chapter1.skill.frost", {"luck_bps": 3000})
		var without: Array[Dictionary] = loot.roll_class(y, "boss", 15, "chapter1.skill.frost", {})
		if with_luck[0].quality != "rare" or JSON.stringify(with_luck[0]) != JSON.stringify(without[0]): guaranteed_ok = false
	var pity_first_ok := true
	for i in 100:
		var z := RandomNumberGenerator.new()
		z.seed = 9000 + i
		var drops: Array[Dictionary] = loot.roll_class(z, "boss", 15, "chapter1.skill.frost", {"luck_bps": 3000}, "legendary")
		if drops[0].quality != "legendary": pity_first_ok = false
	check(guaranteed_ok, "LK7 the boss guaranteed first line (rare) is the same item with luck 3000 as with luck 0 (300 seeds)")
	check(pity_first_ok, "LK7 the pity first_quality line is untouched by luck")
	loot.set_luck(false)
	# LK8 data consistency
	var luck_block_on := bool(raw.get("luck", {}).get("enabled", false))
	check(not bool(raw.get("affix_rolls", {}).get("enabled", false)) or luck_block_on, "LK8 affix_rolls.enabled in the data implies luck.enabled (no luck lines rolled with no effect)")
	# LK9 core_reads mirror (T1-A also checks it for all rows); grace_luck stays unread
	var luck_rows := 0
	var grace_rows := 0
	var luck_ok := true
	var grace_ok := true
	for row in raw.affix_rolls.pool:
		if String(row.stat) == "luck_bps":
			luck_rows += 1
			if not bool(row.core_reads): luck_ok = false
		if String(row.stat) == "grace_luck_bps":
			grace_rows += 1
			if bool(row.core_reads): grace_ok = false
	check(luck_rows == 5 and luck_ok and "luck_bps" in Loot.STATS_READ, "LK9 the five luck_* rows are read (core_reads true, luck_bps in STATS_READ)")
	check(grace_rows == 3 and grace_ok and not "grace_luck_bps" in Loot.STATS_READ, "LK9 the grace_luck_* rows stay unread (core_reads false, not in STATS_READ)")

func finish() -> void:
	print("CHAPTER1_LOOT_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"scope":"loot grammar v2 only; not wired into the running chapter"}))
	quit(0 if failures.is_empty() else 1)
