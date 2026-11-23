extends RefCounted
## Loot grammar v2: eight equip slots, five qualities, prefix/suffix affixes gated by
## item level, legendary effects, uniques and treasure classes. Data lives in
## chapter1/data/loot.json. Items made by the v1 grammar (chapter_items.gd) remain
## valid: they carry no "grammar" key and are checked by the v1 validator.
## Not yet wired into the running chapter; see SYSTEMS-DESIGN L1.
const DATA_PATH := "res://chapter1/data/loot.json"
const ItemsV1 := preload("res://chapter1/core/chapter_items.gd")
const BASE_PREFIX := "chapter1.full."
const UNIQUE_PREFIX := "chapter1.full.unique."
const AFFIX_COUNTS := {"common":[0,0],"magic":[1,2],"rare":[2,4],"legendary":[1,3],"unique":[0,0]}
const KIND_CAPS := {"magic":1,"rare":2,"legendary":2}
## D23 T1: what validate() accepts whatever the switch says (the widest grammar; it never narrows, so older saves stay loadable).
## The data block `affix_rolls` must lie inside it (checked at load). Rolling off uses AFFIX_COUNTS/KIND_CAPS above, unchanged.
const VALID_COUNTS := {"common":[0,0],"magic":[1,2],"rare":[2,5],"legendary":[1,3],"unique":[0,0]}
const VALID_KIND_CAPS := {"magic":1,"rare":3,"legendary":2}
const VALID_CLASS_CAPS := {"magic":{"condition":1,"skill":0},"rare":{"condition":2,"skill":1},"legendary":{"condition":2,"skill":1}}
const AFFIX_CLASSES := ["number","shape","condition","skill"]
## Which lines profile belongs to which quality (the `lines` table of the affix_rolls block).
const LINE_PROFILES := {"magic":"magic","rare":"rare","rare_boss":"rare","legendary":"legendary"}
## The stat keys the running core reads (D23 T1 2.2-7). The affix_rolls roll draws no row whose stat is not listed here. A patch that
## makes the core read one more key adds it HERE in the same patch; the data's `core_reads` flag is a mirror that test_loot compares.
const STATS_READ := ["damage_bps","cooldown_bps","max_hp_raw","damage_reduction_bps","pickup_radius_cm","projectiles","pierce","chain_targets","shatter_count","radius_cm","slow_bps","fire_damage_bps","fire_burst","frost_threshold","arc_branches","arc_damage_bps","move_speed_bps","dash_cooldown_bps","soul_gain_bps","max_hp_bps","after_dash_guard_bps","after_dash_bps","moving_damage_bps","lowhp_cooldown_bps","vs_elite_bps","vs_frozen_bps","vs_marked_bps","thorns_bps","streak_projectiles"]

var data: Dictionary = {}
var errors: Array[String] = []
var _bases: Dictionary = {}
var _affixes: Dictionary = {}
var _legendaries: Dictionary = {}
var _uniques: Dictionary = {}
## affix_rolls (D23 T1): the switch in memory, the ladders in data order, and the window of every live row for the union check.
var _affix_on := false
var _ladders: Array[Dictionary] = []
var _tier_share: Dictionary = {}
var _legacy_windows: Dictionary = {}
## D23 T9: the drop pity block (optional) and its switch in memory.
const PITY_KEYS := ["enabled","runs_without_legendary","upgrade"]
var _pity_on := false

func load_file(path: String = DATA_PATH) -> bool:
	errors.clear()
	if not FileAccess.file_exists(path):
		errors.append("Missing loot data: "+path)
		return false
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		errors.append("Loot data is not a JSON object")
		return false
	var candidate: Dictionary = _ints(parser.data)
	var issues := _check(candidate)
	if not issues.is_empty():
		errors = issues
		return false
	data = candidate
	_bases.clear(); _affixes.clear(); _legendaries.clear(); _uniques.clear()
	for row in data.bases: _bases[row.id] = row
	for row in data.affixes: _affixes[row.id] = row
	for row in data.legendaries: _legendaries[row.id] = row
	for row in data.uniques: _uniques[row.id] = row
	_index_affix_rolls()
	_pity_on = data.has("pity") and data.pity.enabled == true
	return true

## D23 T1: the pool rows join the id table (validate and the read helpers find them; the off roll walks data.affixes only), the ladders
## are built in data order (affixes first, then pool; a ladder sits where its first row appeared) and the switch takes the data's value.
func _index_affix_rolls() -> void:
	_ladders.clear(); _tier_share.clear(); _legacy_windows.clear()
	_affix_on = false
	var block: Dictionary = data.get("affix_rolls",{})
	if block.is_empty(): return
	_affix_on = block.enabled == true
	_legacy_windows = block.legacy_windows
	for row in block.pool: _affixes[row.id] = row
	for entry in block.tiers: _tier_share[int(entry.tier)] = int(entry.share)
	var by_key: Dictionary = {}
	var rows: Array = []
	rows.append_array(data.affixes)
	rows.append_array(block.pool)
	for row in rows:
		var key := String(row.group)+"|"+String(row.stat)
		if not by_key.has(key):
			by_key[key] = _ladders.size()
			_ladders.append({"group":row.group,"stat":row.stat,"kind":row.kind,"class":String(row.get("class","")),"rows":[],"weight":int(row.weight),"low_tier":int(row.get("tier",1))})
		var ladder: Dictionary = _ladders[by_key[key]]
		var window: Dictionary = _legacy_windows.get(row.id,{})
		ladder.rows.append({"def":row,"lo":int(window.get("level",row.level)),"hi":int(window.get("max_level",row.max_level))})
		# A ladder's weight is that of its lowest-tier row, whether that tier is open at the item level or not.
		if int(row.get("tier",1)) < int(ladder.low_tier):
			ladder.low_tier = int(row.get("tier",1)); ladder.weight = int(row.weight)

## D23 T9: the drop pity. pity_on() = the block is there and enabled; pity_runs() = runs without a legendary or unique after which the
## next final boss's first guaranteed line is a legendary. set_pity() switches it in memory (on is refused without a block).
func pity_on() -> bool:
	return _pity_on

func pity_runs() -> int:
	return int(data.get("pity",{}).get("runs_without_legendary",0))

func set_pity(enabled: bool) -> bool:
	if enabled and not data.has("pity"): return false
	_pity_on = enabled
	return true

## Turn the affix_rolls roll on or off in memory (the data file is never written). On is refused (false) when the data has no valid block.
func set_affix_rolls(enabled: bool) -> bool:
	if enabled and (not data.has("affix_rolls") or _ladders.is_empty()): return false
	_affix_on = enabled
	return true

func affix_rolls_on() -> bool:
	return _affix_on

## Read-only helpers for the screen and tools: the live row or pool row of an id ({} when unknown), its tier (0 when none) and class.
func affix_def(id_: String) -> Dictionary:
	return _affixes.get(id_,{}).duplicate(true)

func affix_tier(id_: String) -> int:
	return int(_affixes.get(id_,{}).get("tier",0))

func affix_class(id_: String) -> String:
	return String(_affixes.get(id_,{}).get("class",""))

## JSON numbers arrive as floats. Game data is integral: convert once at the boundary.
func _ints(value: Variant) -> Variant:
	if value is float and value == floorf(value): return int(value)
	if value is Array:
		var list: Array = []
		for entry in value: list.append(_ints(entry))
		return list
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[key] = _ints(value[key])
		return result
	return value

func _check(doc: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	for key in ["schema_version","slots","equip_slots","jewelry_slots","qualities","max_item_level","limits","bases","affixes","legendaries","uniques","rare_names","slot_weights","treasure_classes"]:
		if not doc.has(key): issues.append("Missing "+key)
	if not issues.is_empty(): return issues
	if doc.schema_version != 2: issues.append("Unsupported schema")
	issues.append_array(_check_rare_names(doc.rare_names))
	if doc.has("pickup_flow"): issues.append_array(_check_pickup_flow(doc.pickup_flow,doc.qualities))
	var seen: Dictionary = {}
	for row in doc.bases:
		if seen.has("b:"+str(row.id)): issues.append("Duplicate base "+str(row.id))
		seen["b:"+str(row.id)] = true
		if not row.slot in doc.slots: issues.append("Base slot "+str(row.id))
		issues.append_array(_check_stats(doc,row.stats,"base "+str(row.id)))
	for slot in doc.slots:
		var has_level_one := false
		for row in doc.bases:
			if row.slot == slot and int(row.level) <= 1: has_level_one = true
		if not has_level_one: issues.append("Slot has no level-1 base: "+str(slot))
		if not doc.slot_weights.has(slot): issues.append("Slot weight missing: "+str(slot))
	for row in doc.affixes:
		if seen.has("a:"+str(row.id)): issues.append("Duplicate affix "+str(row.id))
		seen["a:"+str(row.id)] = true
		if not row.kind in ["prefix","suffix"]: issues.append("Affix kind "+str(row.id))
		if not doc.limits.has(row.stat): issues.append("Affix stat "+str(row.id))
		if int(row.low) > int(row.high) or int(row.level) > int(row.max_level) or int(row.weight) <= 0: issues.append("Affix range "+str(row.id))
		for slot in row.slots:
			if not slot in doc.slots: issues.append("Affix slot "+str(row.id))
	for row in doc.legendaries:
		issues.append_array(_check_stats(doc,row.stats,"legendary "+str(row.id)))
		for slot in row.slots:
			if not slot in doc.slots: issues.append("Legendary slot "+str(row.id))
	for row in doc.uniques:
		if not row.slot in doc.slots: issues.append("Unique slot "+str(row.id))
		issues.append_array(_check_stats(doc,row.stats,"unique "+str(row.id)))
	for id_ in doc.treasure_classes:
		var tc: Dictionary = doc.treasure_classes[id_]
		if int(tc.picks) < 1 or int(tc.drop) < 0 or int(tc.no_drop) < 0 or int(tc.drop)+int(tc.no_drop) <= 0: issues.append("Treasure class shape "+str(id_))
		var total := 0
		for quality in tc.quality:
			if not quality in doc.qualities: issues.append("Treasure class quality "+str(id_))
			total += int(tc.quality[quality])
		if total <= 0: issues.append("Treasure class has no quality weight "+str(id_))
	if doc.has("affix_rolls"): issues.append_array(_check_affix_rolls(doc))
	if doc.has("pity"):
		var pity: Variant = doc.pity
		var pity_shape_ok: bool = pity is Dictionary and pity.size() == PITY_KEYS.size()
		if pity_shape_ok:
			for key in PITY_KEYS:
				if not pity.has(key): pity_shape_ok = false
		if not pity_shape_ok: issues.append("pity keys")
		else:
			if not pity.enabled is bool: issues.append("pity enabled")
			if not pity.runs_without_legendary is int or pity.runs_without_legendary < 1 or pity.runs_without_legendary > 50: issues.append("pity runs_without_legendary")
			if pity.upgrade != "first_guaranteed_to_legendary": issues.append("pity upgrade")
	return issues

## D23 T1 2.2-6: the `affix_rolls` block. A wrong block fails load_file like a wrong `affixes` list does.
func _check_affix_rolls(doc: Dictionary) -> Array[String]:
	var block: Variant = doc.affix_rolls
	if not block is Dictionary: return ["affix_rolls shape"]
	for key in ["enabled","lines","kind_caps","class_caps","tier_window","tiers","legacy_windows","pool"]:
		if not block.has(key): return ["affix_rolls missing "+key]
	var issues: Array[String] = []
	if not block.enabled is bool: issues.append("affix_rolls enabled")
	if not block.lines is Dictionary or not block.kind_caps is Dictionary or not block.class_caps is Dictionary or not block.tiers is Array or not block.legacy_windows is Dictionary or not block.pool is Array: return issues+(["affix_rolls types"] as Array[String])
	# lines: profile -> {"3": weight, ...}. Keys are line counts inside what validate() accepts for the profile's quality.
	for profile in block.lines:
		var table: Variant = block.lines[profile]
		if not LINE_PROFILES.has(profile) or not table is Dictionary or table.is_empty(): issues.append("affix_rolls lines profile "+str(profile)); continue
		var bounds: Array = VALID_COUNTS[LINE_PROFILES[profile]]
		var sum := 0
		for count in table:
			if not String(count).is_valid_int() or int(count) < int(bounds[0]) or int(count) > int(bounds[1]) or int(count) < 1: issues.append("affix_rolls lines count "+str(profile)+" "+str(count)); continue
			if not table[count] is int or int(table[count]) <= 0: issues.append("affix_rolls lines weight "+str(profile)+" "+str(count)); continue
			sum += int(table[count])
		if sum <= 0: issues.append("affix_rolls lines sum "+str(profile))
	for quality in block.kind_caps:
		if not VALID_KIND_CAPS.has(quality) or not block.kind_caps[quality] is int or int(block.kind_caps[quality]) < 0 or int(block.kind_caps[quality]) > int(VALID_KIND_CAPS[quality]): issues.append("affix_rolls kind_caps "+str(quality))
	for quality in block.class_caps:
		if not VALID_CLASS_CAPS.has(quality) or not block.class_caps[quality] is Dictionary: issues.append("affix_rolls class_caps "+str(quality)); continue
		for kind in block.class_caps[quality]:
			if not kind in AFFIX_CLASSES or not block.class_caps[quality][kind] is int or int(block.class_caps[quality][kind]) < 0 or int(block.class_caps[quality][kind]) > int(VALID_CLASS_CAPS[quality].get(kind,99)): issues.append("affix_rolls class_caps "+str(quality)+" "+str(kind))
	# tiers: tier 1..5 ascending, min_level ascending, share > 0.
	var tier_numbers: Dictionary = {}
	var last_tier := 0
	var last_level := 0
	for entry in block.tiers:
		if not entry is Dictionary or not entry.has_all(["tier","min_level","share"]) or not entry.tier is int or not entry.min_level is int or not entry.share is int: issues.append("affix_rolls tiers shape"); continue
		if int(entry.tier) < 1 or int(entry.tier) > 5 or int(entry.tier) <= last_tier: issues.append("affix_rolls tiers order")
		if int(entry.min_level) < last_level: issues.append("affix_rolls tiers min_level order")
		if int(entry.share) <= 0: issues.append("affix_rolls tiers share")
		last_tier = int(entry.tier); last_level = int(entry.min_level)
		tier_numbers[int(entry.tier)] = true
	if tier_numbers.is_empty(): issues.append("affix_rolls tiers empty")
	if not block.tier_window is int or int(block.tier_window) < 1: issues.append("affix_rolls tier_window")
	# Rows: ids are unique over `affixes` and `pool`; every number lies inside the stat's limits.
	var ids: Dictionary = {}
	for row in doc.affixes: ids[row.id] = true
	var ladders: Dictionary = {}
	var order: Array[String] = []
	for row in block.pool:
		if not row is Dictionary or not row.has_all(["id","kind","group","stat","slots","level","max_level","low","high","weight","tier","class","core_reads"]): issues.append("affix_rolls pool row shape"); continue
		var label := "affix_rolls pool "+str(row.id)
		if ids.has(row.id): issues.append(label+" duplicate id")
		ids[row.id] = true
		if not row.kind in ["prefix","suffix"]: issues.append(label+" kind")
		if not row.stat is String or not doc.limits.has(row.stat): issues.append(label+" stat"); continue
		if not row.low is int or not row.high is int or not row.level is int or not row.max_level is int or not row.weight is int: issues.append(label+" number type"); continue
		if int(row.low) > int(row.high) or int(row.level) > int(row.max_level) or int(row.weight) <= 0: issues.append(label+" range")
		if int(row.low) < int(doc.limits[row.stat][0]) or int(row.high) > int(doc.limits[row.stat][1]): issues.append(label+" outside limits")
		if not row.slots is Array or row.slots.is_empty(): issues.append(label+" slots")
		else:
			for slot in row.slots:
				if not slot in doc.slots: issues.append(label+" slot")
		if not row.tier is int or not tier_numbers.has(int(row.tier)): issues.append(label+" tier")
		if not row.class is String or not row.class in AFFIX_CLASSES: issues.append(label+" class")
		if not row.core_reads is bool: issues.append(label+" core_reads")
		if row.has("excludes"):
			if not row.excludes is Array: issues.append(label+" excludes")
			else:
				for stat in row.excludes:
					if not stat is String or not doc.limits.has(stat): issues.append(label+" excludes key")
	# Ladders (same group and stat): one kind, one class, no tier twice, ranges never fall as the tier rises (end points may be shared).
	var members: Array = []
	members.append_array(doc.affixes)
	members.append_array(block.pool)
	for row in members:
		if not row is Dictionary or not row.has_all(["group","stat","kind","tier","low","high"]) or not row.tier is int or not row.low is int or not row.high is int: continue
		var key := String(row.group)+"|"+String(row.stat)
		if not ladders.has(key): ladders[key] = []; order.append(key)
		ladders[key].append(row)
	for key in order:
		var rows: Array = ladders[key]
		rows.sort_custom(func(a, b): return int(a.tier) < int(b.tier))
		for index in rows.size():
			var row: Dictionary = rows[index]
			if row.kind != rows[0].kind or String(row.get("class","")) != String(rows[0].get("class","")): issues.append("affix_rolls ladder kind/class "+key)
			if index > 0:
				if int(row.tier) == int(rows[index-1].tier): issues.append("affix_rolls ladder tier twice "+key)
				elif int(row.low) < int(rows[index-1].high): issues.append("affix_rolls ladder values fall "+key+" tier "+str(row.tier))
	var live_ids: Dictionary = {}
	for row in doc.affixes: live_ids[row.id] = true
	for id_ in block.legacy_windows:
		var window: Variant = block.legacy_windows[id_]
		if not live_ids.has(id_) or not window is Dictionary or not window.has_all(["level","max_level"]) or not window.level is int or not window.max_level is int or int(window.level) > int(window.max_level): issues.append("affix_rolls legacy_windows "+str(id_))
	for id_ in doc.treasure_classes:
		var tc: Dictionary = doc.treasure_classes[id_]
		if tc.has("lines_profile") and not (tc.lines_profile is String and block.lines.has(tc.lines_profile)): issues.append("Treasure class lines_profile "+str(id_))
	return issues

## rare_names = {"first": [{"id","name"}...], "second": [...]}. Ids are permanent (saved items point at them), unique over both
## lists and made of lowercase letters and digits; a word is one non-empty token without spaces or control characters.
## D21 N3: optional block read by Chapter.pickup_verdict (the first three keys) and by the screen (the three time keys).
func _check_pickup_flow(b: Variant, qualities: Array) -> Array[String]:
	var keys := ["card_min","open_min_quality","auto_equip_empty","auto_equip_veiled","merge_seconds","card_seconds","auto_equip_seconds"]
	if not b is Dictionary or b.size() != keys.size(): return ["pickup_flow keys"]
	for key in keys:
		if not b.has(key): return ["pickup_flow keys"]
	var issues: Array[String] = []
	if not b.card_min in ["better","any"]: issues.append("pickup_flow card_min")
	if not b.open_min_quality in qualities: issues.append("pickup_flow open_min_quality")
	if not b.auto_equip_empty is bool: issues.append("pickup_flow auto_equip_empty")
	if not b.auto_equip_veiled is bool: issues.append("pickup_flow auto_equip_veiled")
	for key in ["merge_seconds","card_seconds","auto_equip_seconds"]:
		if not (b[key] is int or b[key] is float) or float(b[key]) < 0.0 or float(b[key]) > 60.0: issues.append("pickup_flow "+key)
	return issues

func _check_rare_names(names: Variant) -> Array[String]:
	var issues: Array[String] = []
	if not names is Dictionary or not names.has("first") or not names.has("second") or names.size() != 2:
		issues.append("Rare names shape")
		return issues
	var ids := {}
	var id_rule := RegEx.create_from_string("^[a-z][a-z0-9]{0,7}\\z")
	for part in ["first","second"]:
		if not names[part] is Array or names[part].is_empty():
			issues.append("Rare names list "+part)
			continue
		for entry in names[part]:
			if not entry is Dictionary or not (entry.size() == 2 or (entry.size() == 3 and entry.has("legacy_names"))) or not entry.has("id") or not entry.has("name") or not entry.id is String or not entry.name is String:
				issues.append("Rare word shape in "+part)
				continue
			# `legacy_names`: earlier texts of this word, only for matching the item names of schema 1-3 saves (never shown).
			if entry.has("legacy_names"):
				if not entry.legacy_names is Array or entry.legacy_names.is_empty(): issues.append("Rare word legacy names "+str(entry.id))
				else:
					for old in entry.legacy_names:
						if not old is String or old.is_empty() or old.length() > 40 or old.contains(" "): issues.append("Rare word legacy name "+str(entry.id))
			if id_rule.search(entry.id) == null or ids.has(entry.id): issues.append("Rare word id "+str(entry.id))
			ids[entry.id] = true
			if entry.name.is_empty() or entry.name.length() > 40 or entry.name.contains(" "): issues.append("Rare word text "+str(entry.id))
			if not _check_text({"name":entry.name,"description":""}).is_empty(): issues.append("Rare word characters "+str(entry.id))
	return issues

## The two word ids a rare name is made of ("first second"), or [] when it is not exactly one word from each list.
func rare_word_ids(item_name: String) -> Array:
	var parts := item_name.split(" ")
	if parts.size() != 2: return []
	var first_id := ""
	var second_id := ""
	for entry in data.rare_names.first:
		if entry.name == parts[0] or parts[0] in entry.get("legacy_names",[]): first_id = entry.id
	for entry in data.rare_names.second:
		if entry.name == parts[1] or parts[1] in entry.get("legacy_names",[]): second_id = entry.id
	if first_id.is_empty() or second_id.is_empty(): return []
	return [first_id,second_id]

## The display name for two word ids. A word the data no longer has shows as its own id, never as invented text.
func rare_name_for(words: Array) -> String:
	if words.size() != 2: return ""
	var parts: Array[String] = []
	for index in 2:
		var list: Array = data.rare_names.first if index == 0 else data.rare_names.second
		var shown := String(words[index])
		for entry in list:
			if entry.id == words[index]: shown = entry.name
		parts.append(shown)
	return parts[0]+" "+parts[1]

## True when both word ids exist in the data.
func rare_words_known(words: Array) -> bool:
	if words.size() != 2: return false
	var found := 0
	for index in 2:
		for entry in (data.rare_names.first if index == 0 else data.rare_names.second):
			if entry.id == words[index]: found += 1
	return found == 2

func _check_stats(doc: Dictionary, stats: Dictionary, label: String) -> Array[String]:
	var issues: Array[String] = []
	for stat in stats:
		if not doc.limits.has(stat): issues.append("Unknown stat in "+label)
		elif int(stats[stat]) < int(doc.limits[stat][0]) or int(stats[stat]) > int(doc.limits[stat][1]): issues.append("Stat out of limits in "+label)
	return issues

func _weighted(rng: RandomNumberGenerator, weights: Dictionary, order: Array) -> String:
	var total := 0
	for key in order: total += int(weights.get(key,0))
	if total <= 0: return ""
	var draw := rng.randi_range(1,total)
	for key in order:
		draw -= int(weights.get(key,0))
		if draw <= 0: return key
	return ""

func _clamp_level(level: int) -> int:
	return clampi(level,1,int(data.max_item_level))

func required_level(item: Dictionary) -> int:
	return maxi(1,int(item.item_level)-3)

func _pick_base(rng: RandomNumberGenerator, slot: String, level: int) -> Dictionary:
	var pool: Array = []
	for row in data.bases:
		if row.slot == slot and int(row.level) <= level: pool.append(row)
	return pool[rng.randi_range(0,pool.size()-1)]

func _apply(stats: Dictionary, stat: String, amount: int) -> void:
	stats[stat] = clampi(int(stats.get(stat,0))+amount,int(data.limits[stat][0]),int(data.limits[stat][1]))

func _compose(base: Dictionary, quality: String, affixes: Array, legendary_id: String, rare_name: String) -> Dictionary:
	var stats: Dictionary = base.stats.duplicate(true)
	var prefix := ""
	var suffix := ""
	for entry in affixes:
		var def: Dictionary = _affixes[entry.id]
		_apply(stats,def.stat,int(entry.value))
		if def.kind == "prefix" and prefix.is_empty(): prefix = def.name
		elif def.kind == "suffix" and suffix.is_empty(): suffix = def.name
	var name_: String = base.name
	var description := ""
	if quality == "magic":
		if not prefix.is_empty(): name_ = prefix+"의 "+name_
		if not suffix.is_empty(): name_ = name_+" — "+suffix
	elif quality == "rare":
		name_ = rare_name
	elif quality == "legendary":
		var legend: Dictionary = _legendaries[legendary_id]
		for stat in legend.stats: _apply(stats,stat,int(legend.stats[stat]))
		name_ = legend.name+" "+name_
		description = legend.description
	return {"name":name_,"stats":stats,"description":description}

## Roll one non-unique item. An empty slot means "use the global slot weights".
func roll_item(rng: RandomNumberGenerator, item_level: int, quality: String, slot: String = "", slot_weights: Dictionary = {}, lines_profile: String = "") -> Dictionary:
	var level := _clamp_level(item_level)
	var legendary_id := ""
	if quality == "legendary":
		var legends: Array = []
		for row in data.legendaries:
			if int(row.level) <= level and (slot.is_empty() or slot in row.slots): legends.append(row)
		if legends.is_empty(): quality = "rare"
		else:
			var legend: Dictionary = legends[rng.randi_range(0,legends.size()-1)]
			legendary_id = legend.id
			if slot.is_empty(): slot = legend.slots[rng.randi_range(0,legend.slots.size()-1)]
	if slot.is_empty(): slot = _weighted(rng,data.slot_weights if slot_weights.is_empty() else slot_weights,data.slots)
	var base := _pick_base(rng,slot,level)
	if _affix_on: return _roll_item_v2(rng,level,quality,slot,base,legendary_id,lines_profile)
	var bounds: Array = AFFIX_COUNTS[quality]
	var wanted := 0 if int(bounds[1]) == 0 else rng.randi_range(maxi(int(bounds[0]),int(bounds[1])-1),int(bounds[1]))
	var chosen: Array = []
	var groups: Dictionary = {}
	var kinds := {"prefix":0,"suffix":0}
	for i in wanted:
		var candidates: Array = []
		var total := 0
		for row in data.affixes:
			if slot in row.slots and int(row.level) <= level and level <= int(row.max_level) and not groups.has(row.group) and int(kinds[row.kind]) < int(KIND_CAPS[quality]):
				candidates.append(row); total += int(row.weight)
		if candidates.is_empty(): break
		var draw := rng.randi_range(1,total)
		var picked: Dictionary = candidates[0]
		for row in candidates:
			draw -= int(row.weight)
			if draw <= 0: picked = row; break
		groups[picked.group] = true
		kinds[picked.kind] = int(kinds[picked.kind])+1
		chosen.append({"id":picked.id,"group":picked.group,"stat":picked.stat,"value":rng.randi_range(int(picked.low),int(picked.high))})
	# A slot with too few eligible affixes cannot carry the quality it rolled.
	if quality == "rare" and chosen.size() < 2: quality = "magic" if chosen.size() >= 1 else "common"
	elif quality == "magic" and chosen.is_empty(): quality = "common"
	var rare_name := ""
	if quality == "rare":
		rare_name = String(data.rare_names.first[rng.randi_range(0,data.rare_names.first.size()-1)].name)+" "+String(data.rare_names.second[rng.randi_range(0,data.rare_names.second.size()-1)].name)
	var composed := _compose(base,quality,chosen,legendary_id,rare_name)
	var item := {"grammar":2,"base_id":BASE_PREFIX+String(base.id),"name":composed.name,"slot":slot,"stats":composed.stats,"quality":quality,"item_level":level,"affixes":chosen,"description":composed.description}
	if quality == "legendary": item.legendary_id = legendary_id
	item.required_level = required_level(item)
	return item

## D23 T1 (affix_rolls on): same quality, slot and base draws as above (they happened before the branch); then the lines roll of 2.3.
func _roll_item_v2(rng: RandomNumberGenerator, level: int, quality: String, slot: String, base: Dictionary, legendary_id: String, lines_profile: String) -> Dictionary:
	var chosen: Array = _roll_lines_v2(rng,level,quality,slot,legendary_id,lines_profile)
	if quality == "rare" and chosen.size() < 2: quality = "magic" if chosen.size() >= 1 else "common"
	elif quality == "magic" and chosen.is_empty(): quality = "common"
	var rare_name := ""
	if quality == "rare":
		rare_name = String(data.rare_names.first[rng.randi_range(0,data.rare_names.first.size()-1)].name)+" "+String(data.rare_names.second[rng.randi_range(0,data.rare_names.second.size()-1)].name)
	var composed := _compose(base,quality,chosen,legendary_id,rare_name)
	var item := {"grammar":2,"base_id":BASE_PREFIX+String(base.id),"name":composed.name,"slot":slot,"stats":composed.stats,"quality":quality,"item_level":level,"affixes":chosen,"description":composed.description}
	if quality == "legendary": item.legendary_id = legendary_id
	item.required_level = required_level(item)
	return item

## Line count by weight (keys ascending), then per line three draws: ladder, tier, value. Candidates follow the data order. Common and
## unique items have no lines and draw nothing. A line with no candidate ends the roll early (and draws nothing).
func _roll_lines_v2(rng: RandomNumberGenerator, level: int, quality: String, slot: String, legendary_id: String, lines_profile: String) -> Array:
	var chosen: Array = []
	if not quality in ["magic","rare","legendary"]: return chosen
	var block: Dictionary = data.affix_rolls
	var profile := "rare_boss" if quality == "rare" and lines_profile == "rare_boss" and block.lines.has("rare_boss") else quality
	var table: Dictionary = block.lines.get(profile,{})
	var counts: Array = table.keys()
	counts.sort_custom(func(a, b): return int(a) < int(b))
	var wanted := int(_weighted(rng,table,counts)) if not table.is_empty() else 0
	var banned: Dictionary = _legendaries[legendary_id].stats if quality == "legendary" and _legendaries.has(legendary_id) else {}
	var kind_caps: Dictionary = block.kind_caps
	var class_caps: Dictionary = block.class_caps.get(quality,{})
	var groups: Dictionary = {}
	var kinds := {"prefix":0,"suffix":0}
	var classes: Dictionary = {}
	for i in wanted:
		var open: Array = []
		var total := 0
		for ladder in _ladders:
			if groups.has(ladder.group) or int(kinds[ladder.kind]) >= int(kind_caps.get(quality,0)): continue
			if class_caps.has(ladder["class"]) and int(classes.get(ladder["class"],0)) >= int(class_caps[ladder["class"]]): continue
			var rows: Array = []
			for entry in ladder.rows:
				var def: Dictionary = entry.def
				if not slot in def.slots or level < int(entry.lo) or level > int(entry.hi) or not String(def.stat) in STATS_READ: continue
				var blocked := false
				for stat in def.get("excludes",[]):
					if banned.has(stat): blocked = true
				if not blocked: rows.append(entry)
			if rows.is_empty(): continue
			open.append([ladder,rows])
			total += int(ladder.weight)
		if open.is_empty(): break
		var draw := rng.randi_range(1,total)
		var picked: Array = open[0]
		for pair in open:
			draw -= int(pair[0].weight)
			if draw <= 0: picked = pair; break
		var ladder_picked: Dictionary = picked[0]
		var tier_total := 0
		for entry in picked[1]: tier_total += int(_tier_share.get(int(entry.def.tier),0))
		var tier_draw := rng.randi_range(1,tier_total)
		var row: Dictionary = picked[1][0].def
		for entry in picked[1]:
			tier_draw -= int(_tier_share.get(int(entry.def.tier),0))
			if tier_draw <= 0: row = entry.def; break
		groups[ladder_picked.group] = true
		kinds[ladder_picked.kind] = int(kinds[ladder_picked.kind])+1
		classes[ladder_picked["class"]] = int(classes.get(ladder_picked["class"],0))+1
		chosen.append({"id":row.id,"group":row.group,"stat":row.stat,"value":rng.randi_range(int(row.low),int(row.high))})
	return chosen

func make_unique(id_: String, item_level: int) -> Dictionary:
	if not _uniques.has(id_): return {}
	var def: Dictionary = _uniques[id_]
	var item := {"grammar":2,"base_id":UNIQUE_PREFIX+String(def.id),"name":def.name,"slot":def.slot,"stats":def.stats.duplicate(true),"quality":"unique","item_level":_clamp_level(maxi(item_level,int(def.level))),"affixes":[],"description":def.description}
	item.required_level = required_level(item)
	return item

func _roll_unique(rng: RandomNumberGenerator, level: int, primary: String, primary_only: bool) -> Dictionary:
	var pool: Array = []
	for row in data.uniques:
		if int(row.level) <= level and (not primary_only or row.element == primary): pool.append(row)
	if pool.is_empty(): return {}
	return make_unique(pool[rng.randi_range(0,pool.size()-1)].id,level)

## Resolve one treasure class into zero or more items. `mods` (D13 5.2 shrine of luck) is optional: {drop_bps: share of the drop weight
## in ten-thousandths, quality_bps: {quality: share of that quality's weight}}. Without it (the default) the draws and their count are
## exactly what they were before the argument existed.
## `first_quality` (D23 T9, last parameter): "legendary" turns the first guaranteed line of a class whose first guarantee is "rare" into a legendary
## (the drop pity). Empty = the draws are exactly what they were before the parameter existed.
func roll_class(rng: RandomNumberGenerator, class_id: String, zone_level: int, primary: String = "", mods: Dictionary = {}, first_quality: String = "") -> Array[Dictionary]:
	var drops: Array[Dictionary] = []
	if not data.treasure_classes.has(class_id): return drops
	var tc: Dictionary = data.treasure_classes[class_id]
	var drop_weight := int(tc.drop)
	var quality_weights: Dictionary = tc.quality
	if not mods.is_empty():
		drop_weight = drop_weight*int(mods.get("drop_bps",10000))/10000
		var shares: Dictionary = mods.get("quality_bps",{})
		if not shares.is_empty():
			quality_weights = tc.quality.duplicate()
			for quality in shares:
				if quality_weights.has(quality): quality_weights[quality] = int(quality_weights[quality])*int(shares[quality])/10000
	var level := _clamp_level(zone_level+int(tc.level_bonus))
	var weights: Dictionary = tc.get("slot_weights",{})
	var guaranteed: Array = tc.get("guaranteed",[])
	var lines_profile := String(tc.get("lines_profile",""))
	for pick in int(tc.picks):
		var item: Dictionary = {}
		if pick < guaranteed.size():
			if guaranteed[pick] == "unique_primary": item = _roll_unique(rng,level,primary,true)
			else:
				var guaranteed_quality := String(guaranteed[pick])
				if pick == 0 and first_quality == "legendary" and guaranteed_quality == "rare": guaranteed_quality = "legendary"
				item = roll_item(rng,level,guaranteed_quality,"",weights,lines_profile)
		else:
			if rng.randi_range(1,int(tc.no_drop)+drop_weight) <= int(tc.no_drop): continue
			var quality := _weighted(rng,quality_weights,data.qualities)
			if quality == "unique":
				item = _roll_unique(rng,level,primary,false)
				if item.is_empty(): quality = "legendary"
			if item.is_empty(): item = roll_item(rng,level,quality,"",weights,lines_profile)
		if not item.is_empty(): drops.append(item)
	return drops

func validate(item: Dictionary) -> Array[String]:
	# v1 items keep their original rules, so existing saves stay loadable.
	if not item.has("grammar"): return ItemsV1.validate(item)
	var issues: Array[String] = []
	for key in ["base_id","name","slot","stats","quality","item_level","affixes","description","required_level"]:
		if not item.has(key): issues.append("Missing "+key)
	if not issues.is_empty(): return issues
	if item.grammar != 2: return ["Unknown grammar"]
	if not item.slot in data.slots: issues.append("Unknown slot")
	if not item.quality in data.qualities: issues.append("Unknown quality")
	if not item.stats is Dictionary or not item.affixes is Array: return ["Stats/affixes shape"]
	if not item.item_level is int or item.item_level < 1 or item.item_level > int(data.max_item_level): return ["Item level"]
	if not issues.is_empty(): return issues
	if item.required_level != required_level(item): issues.append("Required level")
	for stat in item.stats:
		if not data.limits.has(stat): issues.append("Unknown stat")
		elif not item.stats[stat] is int or item.stats[stat] < int(data.limits[stat][0]) or item.stats[stat] > int(data.limits[stat][1]): issues.append("Stat range/type")
	if item.quality == "unique":
		var uid := String(item.base_id).trim_prefix(UNIQUE_PREFIX)
		if not String(item.base_id).begins_with(UNIQUE_PREFIX) or not _uniques.has(uid): return issues+(["Unknown unique"] as Array[String])
		var def: Dictionary = _uniques[uid]
		if item.slot != def.slot or item.stats != def.stats or not item.affixes.is_empty() or item.item_level < int(def.level): issues.append("Unique identity/stats")
		issues.append_array(_check_text(item))
		return issues
	var bid := String(item.base_id).trim_prefix(BASE_PREFIX)
	if not _bases.has(bid): return issues+(["Unknown base"] as Array[String])
	var base: Dictionary = _bases[bid]
	if item.slot != base.slot or item.item_level < int(base.level): issues.append("Base eligibility")
	var bounds: Array = VALID_COUNTS[item.quality]
	if item.affixes.size() < int(bounds[0]) or item.affixes.size() > int(bounds[1]): issues.append("Affix count")
	var groups: Dictionary = {}
	var classes: Dictionary = {}
	var kinds := {"prefix":0,"suffix":0}
	for entry in item.affixes:
		if not entry is Dictionary or not entry.has_all(["id","group","stat","value"]) or not _affixes.has(entry.id): return issues+(["Affix shape"] as Array[String])
		var def: Dictionary = _affixes[entry.id]
		if groups.has(def.group): issues.append("Duplicate affix group")
		groups[def.group] = true
		kinds[def.kind] = int(kinds[def.kind])+1
		if def.has("class"): classes[def.class] = int(classes.get(def.class,0))+1
		if entry.group != def.group or entry.stat != def.stat or not item.slot in def.slots or not _in_window(def,item.item_level) or not entry.value is int or entry.value < int(def.low) or entry.value > int(def.high): issues.append("Affix eligibility/range")
	var cap := int(VALID_KIND_CAPS.get(item.quality,0))
	if int(kinds.prefix) > cap or int(kinds.suffix) > cap: issues.append("Affix kind cap")
	var class_caps: Dictionary = VALID_CLASS_CAPS.get(item.quality,{})
	for kind in classes:
		if class_caps.has(kind) and int(classes[kind]) > int(class_caps[kind]): issues.append("Affix class cap")
	var legendary_id := String(item.get("legendary_id",""))
	if item.quality == "legendary":
		if not _legendaries.has(legendary_id) or not item.slot in _legendaries[legendary_id].slots or item.item_level < int(_legendaries[legendary_id].level): return issues+(["Legendary identity"] as Array[String])
	elif not legendary_id.is_empty(): issues.append("Unexpected legendary effect")
	if not issues.is_empty(): return issues
	# Name and description are presentation: only their type and length are checked (see dress()).
	var expected := _compose(base,item.quality,item.affixes,legendary_id,"")
	if item.stats != expected.stats: issues.append("Base+affix identity/stats")
	issues.append_array(_check_text(item))
	return issues

## The item levels a row may appear at: a pool row its own window; a live row its own window or the affix_rolls `legacy_windows` one.
func _in_window(def: Dictionary, level: int) -> bool:
	if level >= int(def.level) and level <= int(def.max_level): return true
	var window: Dictionary = _legacy_windows.get(def.id,{})
	return not window.is_empty() and level >= int(window.level) and level <= int(window.max_level)

## Name 1..160 characters on one line, description 0..300 characters (line breaks allowed); no control characters.
func _check_text(item: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	if not item.name is String or item.name.length() < 1 or item.name.length() > 160: issues.append("Name format")
	if not item.description is String or item.description.length() > 300: issues.append("Description format")
	if not issues.is_empty(): return issues
	# A name is one line; a description may have line breaks. Neither may carry control, line-separator or
	# bidirectional-override characters (they would break or reorder a HUD line).
	for field in ["name","description"]:
		var text: String = item[field]
		for i in text.length():
			var code: int = text.unicode_at(i)
			var is_break: bool = code == 10 and field == "description"
			if not is_break and (code < 32 or code == 127 or (code >= 0x80 and code <= 0x9F) or code == 0x2028 or code == 0x2029 or (code >= 0x202A and code <= 0x202E) or (code >= 0x2066 and code <= 0x2069)):
				issues.append("Text control character")
				return issues
	return issues

## A copy of `item` with name and description rebuilt from the current data (rare names are kept).
## Call only on an item that passed validate(). Never changes stats or ids. v1 items are returned unchanged.
func dress(item: Dictionary) -> Dictionary:
	var result: Dictionary = item.duplicate(true)
	if not item.has("grammar"): return result
	if item.quality == "unique":
		var uid := String(item.base_id).trim_prefix(UNIQUE_PREFIX)
		if _uniques.has(uid):
			result.name = _uniques[uid].name
			result.description = _uniques[uid].description
		return result
	var bid := String(item.base_id).trim_prefix(BASE_PREFIX)
	if not _bases.has(bid): return result
	var composed := _compose(_bases[bid],item.quality,item.affixes,String(item.get("legendary_id","")),String(item.name))
	result.description = composed.description
	if item.quality != "rare": result.name = composed.name
	return result

## Rough worth of an item for a given signature skill. Used only to decide whether
## a pickup deserves a prompt; it never changes combat.
func score(item: Dictionary, primary: String = "") -> float:
	var weights := {"damage_bps":.006,"cooldown_bps":.008,"max_hp_raw":.001,"damage_reduction_bps":.01,"pickup_radius_cm":.03,"projectiles":16.0,"pierce":7.0,"radius_cm":.02,"move_speed_bps":.006,"dash_cooldown_bps":.003,"soul_gain_bps":.004,"max_hp_bps":.006,"after_dash_guard_bps":.005,"lowhp_cooldown_bps":.004,"after_dash_bps":.003,"moving_damage_bps":.003,"thorns_bps":.003,"streak_projectiles":8.0,"vs_elite_bps":.003,"vs_frozen_bps":.003,"vs_marked_bps":.003}
	var own := {"chapter1.skill.ember":{"fire_damage_bps":.006,"fire_burst":25.0},"chapter1.skill.frost":{"slow_bps":.004,"shatter_count":6.0,"frost_threshold":25.0},"chapter1.skill.arc":{"chain_targets":10.0,"arc_branches":25.0,"arc_damage_bps":.006}}
	var total := 0.0
	for stat in item.stats:
		var weight := float(weights.get(stat,0.0))
		if own.has(primary): weight = float(own[primary].get(stat,weight))
		total += float(item.stats[stat])*weight
	return total

## True when a pickup should be announced: empty slot, legendary or unique (their
## effects cannot be compared by score), or a clearly higher score.
func is_upgrade(candidate: Dictionary, current: Dictionary, primary: String = "") -> bool:
	if current.is_empty(): return true
	if candidate.quality in ["legendary","unique"]: return true
	return score(candidate,primary) > score(current,primary)*1.05+.5
