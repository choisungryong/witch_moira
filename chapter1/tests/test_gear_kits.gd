extends SceneTree
## D23 T1-M: the fixed gear kits of fixtures/gear_kits.json build into items that the core accepts (loot.validate), except the lines that exist only
## in affix_rolls.pool (tagged "pool": they must stay in the pool's ranges and limits, and validate() is allowed to refuse them until T1-A);
## a kit worn on a real core run gives exactly the summed stats. Writes nothing.
const Loot = preload("res://chapter1/core/loot.gd")
const GearKits = preload("res://chapter1/tests/support/gear_kits.gd")
const Core = preload("res://chapter1/core/chapter_core.gd")
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
	var fixture := GearKits.load_fixture()
	check(loot.load_file(), "loot data loads")
	check(not fixture.is_empty() and fixture.kits.size() >= 6, "fixture loads with the kits")
	if not failures.is_empty():
		finish()
		return
	for name in ["kit.d1_start", "kit.d1_end", "kit.d2_mid", "kit.d1_end_v1"]:
		check(fixture.kits.has(name), "kit present: " + name)
	for kit in GearKits.kit_names(fixture):
		var built := GearKits.items(loot, fixture, String(kit))
		check(bool(built.ok), "%s builds: %s" % [kit, str(built.errors)])
		if not bool(built.ok): continue
		var uids := {}
		var slots := {}
		var pool_lines := 0
		for entry in built.items:
			var item: Dictionary = entry.item
			uids[item.uid] = true
			slots[entry.equip] = true
			check(entry.equip in loot.data.equip_slots, "%s %s: equip slot is real" % [kit, entry.equip])
			pool_lines += int(entry.pool_lines)
			var issues: Array[String] = loot.validate(item)
			if int(entry.pool_lines) == 0:
				check(issues.is_empty(), "%s %s validates: %s" % [kit, entry.equip, str(issues)])
			else:
				# A pool line: the core may refuse it until T1-A; the line itself must sit in the pool row's range and its stat in limits.
				for line in item.affixes:
					var row := {}
					for r in loot.data.affix_rolls.pool:
						if r.id == line.id: row = r
					if row.is_empty(): continue
					check(int(line.value) >= int(row.low) and int(line.value) <= int(row.high), "%s %s: pool line %s value in range" % [kit, entry.equip, line.id])
					check(item.item_level >= int(row.level) and item.item_level <= int(row.max_level), "%s %s: pool line %s item level in its window" % [kit, entry.equip, line.id])
					check(item.slot in row.slots, "%s %s: pool line %s allowed on the slot" % [kit, entry.equip, line.id])
		check(uids.size() == built.items.size(), kit + ": unique uids")
		check(slots.size() == built.items.size(), kit + ": one item per equip slot")
		var tagged: bool = "pool" in built.needs
		check((pool_lines > 0) == tagged, "%s: the 'pool' tag matches the pool lines (%d lines, tag %s)" % [kit, pool_lines, str(tagged)])
		# Worn on a real run: the core's own sum equals the kit's.
		var run = Core.new()
		check(run.start(11, "chapter1.skill.frost"), kit + ": run starts")
		GearKits.install(run, built)
		var sums := GearKits.totals(built)
		var same := true
		for stat in sums:
			if int(run._gear_stats.get(stat, 0)) != int(sums[stat]): same = false
		check(same, "%s: the core's gear stats equal the kit sums" % kit)
		check(int(run.hero.max_hp_raw) == GearKits.BASE_HP_RAW + int(sums.get("max_hp_raw", 0)), kit + ": hero life = base + kit life")
	# Variants differ from their base only in the replaced slot.
	var base := GearKits.items(loot, fixture, "kit.d1_end")
	var v1 := GearKits.items(loot, fixture, "kit.d1_end_v1")
	check(base.items.size() == v1.items.size(), "v1 has the same slots as d1_end")
	var diff := 0
	for i in base.items.size():
		if JSON.stringify(base.items[i].item.stats) != JSON.stringify(v1.items[i].item.stats): diff += 1
	check(diff == 1, "v1 differs from d1_end in exactly one item (got %d)" % diff)
	finish()

func finish() -> void:
	print("CHAPTER1_GEAR_KITS_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
