extends RefCounted
## D23 T1-M: builds the fixed gear kits of tests/fixtures/gear_kits.json into core item dictionaries (grammar 2, the shape loot.gd rolls).
## Read-only on the data: nothing here writes a data file or a save. Used by sim_power.gd (--gear-kit=) and test_gear_kits.gd.
##   items(loot, fixture, kit)      -> {"ok", "errors", "items": [{"item", "equip", "pool_lines"}], "needs": [...]}   (variants `from` + `replace` resolved)
##   install(run, built)            puts the items into the core's bag and wears them (private helpers of the core, like sim_power's other bench hooks)
##   totals(built)                  summed stats of the worn items
const PATH := "res://chapter1/tests/fixtures/gear_kits.json"
const UID0 := 9000          ## kit item uids: far above the core's own item counter
const BASE_HP_RAW := 120 * 256

static func load_fixture(path: String = PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

static func kit_names(fixture: Dictionary) -> Array:
	return fixture.get("kits", {}).keys()

## Item specs of a kit by equip slot, variants resolved: `from` takes the base kit, `replace` swaps whole slots.
static func specs(fixture: Dictionary, kit: String) -> Dictionary:
	var kits: Dictionary = fixture.get("kits", {})
	if not kits.has(kit): return {}
	var def: Dictionary = kits[kit]
	var by_slot: Dictionary = {}
	var order: Array = []
	if def.has("from"):
		var base := specs(fixture, String(def.from))
		by_slot = base.by_slot
		order = base.order
	for spec in def.get("items", []):
		if not by_slot.has(spec.equip): order.append(spec.equip)
		by_slot[spec.equip] = spec
	for slot in def.get("replace", {}):
		if not by_slot.has(slot): order.append(slot)
		by_slot[slot] = def.replace[slot]
	var needs: Array = def.get("needs", []).duplicate()
	if def.has("from"):
		for n in specs(fixture, String(def.from)).needs:
			if not n in needs: needs.append(n)
	return {"by_slot": by_slot, "order": order, "needs": needs}

static func _find(rows: Array, id_: String) -> Dictionary:
	for row in rows:
		if String(row.id) == id_: return row
	return {}

static func _ints(value: Variant) -> Variant:
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

## One item from its spec. pool_lines counts the lines that exist only in affix_rolls.pool.
static func build_item(loot, spec: Dictionary) -> Dictionary:
	var il := int(spec.item_level)
	if String(spec.quality) == "unique":
		var made: Dictionary = loot.make_unique(String(spec.unique), il)
		if made.is_empty(): return {"error": "unknown unique " + String(spec.unique)}
		return {"item": made, "equip": String(spec.equip), "pool_lines": 0}
	var base := _find(loot.data.bases, String(spec.base))
	if base.is_empty(): return {"error": "unknown base " + String(spec.base)}
	var stats: Dictionary = base.stats.duplicate(true)
	var lines: Array = []
	var pool_lines := 0
	var pool: Array = loot.data.get("affix_rolls", {}).get("pool", [])
	for pair in spec.get("affixes", []):
		var row := _find(loot.data.affixes, String(pair[0]))
		if row.is_empty():
			row = _find(pool, String(pair[0]))
			if not row.is_empty(): pool_lines += 1
		if row.is_empty(): return {"error": "unknown affix " + String(pair[0])}
		var value := int(pair[1])
		stats[row.stat] = clampi(int(stats.get(row.stat, 0)) + value, int(loot.data.limits[row.stat][0]), int(loot.data.limits[row.stat][1]))
		lines.append({"id": String(row.id), "group": String(row.group), "stat": String(row.stat), "value": value})
	var legendary_id := String(spec.get("legendary", ""))
	var description := ""
	var name_ := String(base.name)
	if legendary_id != "":
		var legend := _find(loot.data.legendaries, legendary_id)
		if legend.is_empty(): return {"error": "unknown legendary " + legendary_id}
		for stat in legend.stats: stats[stat] = clampi(int(stats.get(stat, 0)) + int(legend.stats[stat]), int(loot.data.limits[stat][0]), int(loot.data.limits[stat][1]))
		name_ = String(legend.name) + " " + name_
		description = String(legend.description)
	elif String(spec.quality) in ["magic", "rare"]:
		name_ = name_ + " (kit)"
	var item := {"grammar": 2, "base_id": loot.BASE_PREFIX + String(base.id), "name": name_, "slot": String(spec.slot), "stats": stats, "quality": String(spec.quality),
		"item_level": il, "affixes": lines, "description": description}
	if legendary_id != "": item["legendary_id"] = legendary_id
	item["required_level"] = loot.required_level(item)
	return {"item": item, "equip": String(spec.equip), "pool_lines": pool_lines}

## The whole kit. Items get uids UID0+1.. in equip order.
static func items(loot, fixture: Dictionary, kit: String) -> Dictionary:
	var sp := specs(fixture, kit)
	if sp.is_empty(): return {"ok": false, "errors": ["unknown kit " + kit], "items": [], "needs": []}
	var out: Array = []
	var errors: Array = []
	for slot in sp.order:
		var built := build_item(loot, sp.by_slot[slot])
		if built.has("error"):
			errors.append("%s %s: %s" % [kit, slot, built.error])
			continue
		built.item["uid"] = UID0 + out.size() + 1
		out.append(built)
	return {"ok": errors.is_empty(), "errors": errors, "items": out, "needs": sp.needs}

static func totals(built: Dictionary) -> Dictionary:
	var sums := {}
	for entry in built.items:
		for stat in entry.item.stats: sums[stat] = int(sums.get(stat, 0)) + int(entry.item.stats[stat])
	return sums

## Wear the kit on a core run: bag + equip map by slot, then the core's own gear recompute. Returns the equip map.
static func install(run, built: Dictionary) -> Dictionary:
	var map := {}
	run.inventory.clear()
	for entry in built.items:
		run.inventory.append(entry.item.duplicate(true))
		map[entry.equip] = int(entry.item.uid)
	run.equipped = map.duplicate()
	run._recompute_gear()
	return map

## Wear the kit from tick 0 through the core's own starting-gear import (the way a run starts with town gear; required levels are not enforced there).
static func wear_from_start(run, built: Dictionary) -> bool:
	var gear: Array[Dictionary] = []
	var n := 0
	for entry in built.items:
		var item: Dictionary = entry.item.duplicate(true)
		n += 1
		item["storage_id"] = "kit-%d" % n
		item["equip_slot"] = String(entry.equip)
		gear.append(item)
	return run.import_starting_gear(gear)

## Model of the standing-power ratio S(kit) / S(baseline): contact damage scales with (1 - damage reduction), life with max_hp, the potion share is the same
## (D12 P4 S definition). A model answer, not a measurement. dr_bps is the plain sum of the kit's damage_reduction_bps (no cap in the core today).
static func s_ratio(sums: Dictionary) -> float:
	var hp_ratio := float(BASE_HP_RAW + int(sums.get("max_hp_raw", 0))) / float(BASE_HP_RAW)
	var dr := clampi(int(sums.get("damage_reduction_bps", 0)), 0, 9999)
	return hp_ratio / (1.0 - float(dr) / 10000.0)
