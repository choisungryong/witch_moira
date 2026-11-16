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

var data: Dictionary = {}
var errors: Array[String] = []
var _bases: Dictionary = {}
var _affixes: Dictionary = {}
var _legendaries: Dictionary = {}
var _uniques: Dictionary = {}

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
	return true

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
	return issues

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
func roll_item(rng: RandomNumberGenerator, item_level: int, quality: String, slot: String = "", slot_weights: Dictionary = {}) -> Dictionary:
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
		rare_name = String(data.rare_names.first[rng.randi_range(0,data.rare_names.first.size()-1)])+" "+String(data.rare_names.second[rng.randi_range(0,data.rare_names.second.size()-1)])
	var composed := _compose(base,quality,chosen,legendary_id,rare_name)
	var item := {"grammar":2,"base_id":BASE_PREFIX+String(base.id),"name":composed.name,"slot":slot,"stats":composed.stats,"quality":quality,"item_level":level,"affixes":chosen,"description":composed.description}
	if quality == "legendary": item.legendary_id = legendary_id
	item.required_level = required_level(item)
	return item

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

## Resolve one treasure class into zero or more items.
func roll_class(rng: RandomNumberGenerator, class_id: String, zone_level: int, primary: String = "") -> Array[Dictionary]:
	var drops: Array[Dictionary] = []
	if not data.treasure_classes.has(class_id): return drops
	var tc: Dictionary = data.treasure_classes[class_id]
	var level := _clamp_level(zone_level+int(tc.level_bonus))
	var weights: Dictionary = tc.get("slot_weights",{})
	var guaranteed: Array = tc.get("guaranteed",[])
	for pick in int(tc.picks):
		var item: Dictionary = {}
		if pick < guaranteed.size():
			if guaranteed[pick] == "unique_primary": item = _roll_unique(rng,level,primary,true)
			else: item = roll_item(rng,level,String(guaranteed[pick]),"",weights)
		else:
			if rng.randi_range(1,int(tc.no_drop)+int(tc.drop)) <= int(tc.no_drop): continue
			var quality := _weighted(rng,tc.quality,data.qualities)
			if quality == "unique":
				item = _roll_unique(rng,level,primary,false)
				if item.is_empty(): quality = "legendary"
			if item.is_empty(): item = roll_item(rng,level,quality,"",weights)
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
		if item.slot != def.slot or item.stats != def.stats or item.name != def.name or item.description != def.description or not item.affixes.is_empty() or item.item_level < int(def.level): issues.append("Unique identity/stats")
		return issues
	var bid := String(item.base_id).trim_prefix(BASE_PREFIX)
	if not _bases.has(bid): return issues+(["Unknown base"] as Array[String])
	var base: Dictionary = _bases[bid]
	if item.slot != base.slot or item.item_level < int(base.level): issues.append("Base eligibility")
	var bounds: Array = AFFIX_COUNTS[item.quality]
	if item.affixes.size() < int(bounds[0]) or item.affixes.size() > int(bounds[1]): issues.append("Affix count")
	var groups: Dictionary = {}
	var kinds := {"prefix":0,"suffix":0}
	for entry in item.affixes:
		if not entry is Dictionary or not entry.has_all(["id","group","stat","value"]) or not _affixes.has(entry.id): return issues+(["Affix shape"] as Array[String])
		var def: Dictionary = _affixes[entry.id]
		if groups.has(def.group): issues.append("Duplicate affix group")
		groups[def.group] = true
		kinds[def.kind] = int(kinds[def.kind])+1
		if entry.group != def.group or entry.stat != def.stat or not item.slot in def.slots or item.item_level < int(def.level) or item.item_level > int(def.max_level) or not entry.value is int or entry.value < int(def.low) or entry.value > int(def.high): issues.append("Affix eligibility/range")
	var cap := int(KIND_CAPS.get(item.quality,0))
	if int(kinds.prefix) > cap or int(kinds.suffix) > cap: issues.append("Affix kind cap")
	var legendary_id := String(item.get("legendary_id",""))
	if item.quality == "legendary":
		if not _legendaries.has(legendary_id) or not item.slot in _legendaries[legendary_id].slots or item.item_level < int(_legendaries[legendary_id].level): return issues+(["Legendary identity"] as Array[String])
	elif not legendary_id.is_empty(): issues.append("Unexpected legendary effect")
	if not issues.is_empty(): return issues
	var expected := _compose(base,item.quality,item.affixes,legendary_id,String(item.name))
	if item.quality == "rare":
		var parts := String(item.name).split(" ")
		if parts.size() != 2 or not parts[0] in data.rare_names.first or not parts[1] in data.rare_names.second: issues.append("Rare name")
	elif item.name != expected.name: issues.append("Name")
	if item.stats != expected.stats or item.description != expected.description: issues.append("Base+affix identity/stats")
	return issues

## Rough worth of an item for a given signature skill. Used only to decide whether
## a pickup deserves a prompt; it never changes combat.
func score(item: Dictionary, primary: String = "") -> float:
	var weights := {"damage_bps":.006,"cooldown_bps":.008,"max_hp_raw":.001,"damage_reduction_bps":.01,"pickup_radius_cm":.03,"projectiles":16.0,"pierce":7.0,"radius_cm":.02,"move_speed_bps":.006,"dash_cooldown_bps":.003,"soul_gain_bps":.004}
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
