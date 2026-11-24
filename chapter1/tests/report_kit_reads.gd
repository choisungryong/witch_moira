extends SceneTree
## VR-B: what a gear kit gives each primary, read the way the game's equipment verdict v2 (loot.json upgrade_verdict) reads it. A MODEL answer (a hand calculation on the
## kit's summed stats, base stats included), not a measurement: how a kit plays is only known from the played runs.
##
##   --script res://chapter1/tests/report_kit_reads.gd -- --kits-file=_local/x/kits.json --kits=kit.d1_end,kit.f2.@.r15,kit.f2v.@.r15 --primaries=ember,frost,arc --cross --out=_local/x/reads.json
##   --kits-file=_local/..   extra kits (the --kits-file of measure_rhythm); the fixture tests/fixtures/gear_kits.json is always loaded
##   --kits=a,b              kit names, "@" = the primary's own series (ember / frost / arc), like measure_rhythm --gear-kit
##   --primaries=ember,...   default ember,frost,arc
##   --cross                 for a kit with "@": every primary also reads every series' kit (3x3)
##   --out=_local/..json     default _local/kit_reads.json
## Per kit x primary: damage factor (upgrade_verdict.damage_keys, each max(.05, 1 + sum/10000)), rate factor (cooldown_key), shape factor (shape_keys, shape_base, shape_share, shots_r1),
## single = damage * rate, P = single * shape, the unread attack lines (attack_keys not in reads[primary]) and V = loot._verdict_worth. All keys come from loot.json, none is written here.
## Self check: log_weight * ln(P) + score(rest) computed here must equal loot._verdict_worth within 1e-6, else exit 4. The game's files are only read.
const GearKits = preload("res://chapter1/tests/support/gear_kits.gd")
const LootData = preload("res://chapter1/core/loot.gd")

func _initialize() -> void:
	var kits_file := ""
	var kit_names: Array = []
	var prim_names: Array = ["ember", "frost", "arc"]
	var cross := false
	var out := "_local/kit_reads.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--kits-file="): kits_file = arg.trim_prefix("--kits-file=")
		elif arg.begins_with("--kits="): kit_names = Array(arg.trim_prefix("--kits=").split(","))
		elif arg.begins_with("--primaries="): prim_names = Array(arg.trim_prefix("--primaries=").split(","))
		elif arg == "--cross": cross = true
		elif arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		else:
			push_error("report_kit_reads: unknown argument %s" % arg)
			quit(1)
			return
	if kit_names.is_empty():
		push_error("report_kit_reads: --kits= is required")
		quit(1)
		return
	for path in [kits_file, out]:
		if path != "" and (not path.begins_with("_local/") or path.contains("..") or path.contains(":")):
			push_error("report_kit_reads: paths must be relative under _local/ (got %s)" % path)
			quit(1)
			return
	var fixture := GearKits.load_fixture()
	if kits_file != "":
		var extra := GearKits.load_fixture("res://" + kits_file)
		for k in extra.get("kits", {}): fixture.kits[k] = extra.kits[k]
	var loot = LootData.new()
	if fixture.is_empty() or not loot.load_file():
		push_error("report_kit_reads: fixture or loot data unreadable")
		quit(1)
		return
	var block: Dictionary = loot.data.get("upgrade_verdict", {})
	if block.is_empty():
		push_error("report_kit_reads: loot.json has no upgrade_verdict")
		quit(1)
		return
	var rows: Array = []
	var worst_diff := 0.0
	for template in kit_names:
		var own_rows: Array = []
		for prim in prim_names:
			var kit_name := String(template).replace("@", String(prim))
			var reads_of := [kit_name]
			if cross and String(template).contains("@"):
				reads_of = []
				for series in prim_names: reads_of.append(String(template).replace("@", String(series)))
			for read_kit in reads_of:
				var row := _row(loot, block, fixture, String(read_kit), String(prim))
				if row.has("error"):
					push_error("report_kit_reads: %s" % row.error)
					quit(1)
					return
				row["template"] = String(template)
				row["own"] = String(read_kit) == kit_name
				worst_diff = maxf(worst_diff, absf(float(row.v_check_diff)))
				rows.append(row)
				if row.own: own_rows.append(row)
		print("READS kit=%s" % template)
		for row in own_rows:
			print("  %-6s kit=%-22s dmg=%.3f rate=%.3f single-1=%+.3f shape=%.3f P=%.3f V=%.2f unread=%s" % [row.primary, row.kit, row.damage, row.rate, row.single - 1.0, row.shape, row.p, row.v, JSON.stringify(row.unread)])
		if own_rows.size() >= 2:
			var hi := -INF
			var lo := INF
			var order: Array = own_rows.duplicate()
			order.sort_custom(func(a, b): return a.single > b.single)
			var names: Array = []
			for row in own_rows:
				hi = maxf(hi, float(row.single) - 1.0)
				lo = minf(lo, float(row.single) - 1.0)
			for row in order: names.append("%s %.3f" % [row.primary, float(row.single) - 1.0])
			print("  order(single-1, high to low)=%s  max/min=%s" % [" > ".join(names), ("%.3f" % (hi / lo)) if lo > 0.0 else "n/a (min<=0)"])
	if cross:
		print("CROSS single-1 (rows: reading primary, columns: whose kit)")
		for template in kit_names:
			if not String(template).contains("@"): continue
			print("  template %s" % template)
			for prim in prim_names:
				var cells: Array = []
				for row in rows:
					if row.template == template and row.primary == prim: cells.append("%s %+.3f" % [row.kit.get_slice(".", 2) if row.kit.count(".") >= 3 else row.kit, float(row.single) - 1.0])
				print("    %-6s %s" % [prim, " | ".join(cells)])
	print("SELF_CHECK max |V - (log_weight*ln(P) + score(rest))| = %.9f (limit 1e-6)" % worst_diff)
	var abs_path := ProjectSettings.globalize_path("res://" + out)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		push_error("report_kit_reads: cannot write %s" % abs_path)
		quit(3)
		return
	f.store_string(JSON.stringify({"note": "model answer: a hand calculation on kit stats (base stats included), not a measurement", "self_check_max_diff": worst_diff, "rows": rows}, "\t"))
	f.close()
	if worst_diff > 0.000001:
		push_error("report_kit_reads: SELF CHECK FAILED (%.9f)" % worst_diff)
		quit(4)
		return
	quit(0)

func _row(loot, block: Dictionary, fixture: Dictionary, kit_name: String, prim: String) -> Dictionary:
	var primary := "chapter1.skill." + prim
	if not block.reads.has(primary): return {"error": "unknown primary " + prim}
	var built := GearKits.items(loot, fixture, kit_name)
	if not built.ok: return {"error": "kit %s: %s" % [kit_name, str(built.errors)]}
	var totals := GearKits.totals(built)
	var worn := {}
	for entry in built.items: worn[String(entry.equip)] = entry.item
	var damage := 1.0
	var used := {}
	for key in block.damage_keys[primary]:
		damage *= maxf(.05, 1.0 + float(totals.get(key, 0)) / 10000.0)
		used[key] = true
	used[block.cooldown_key] = true
	var rate := maxf(.1, 1.0 + float(totals.get(block.cooldown_key, 0)) / 10000.0)
	var count := 0
	for key in block.shape_keys[primary]:
		count += int(totals.get(key, 0))
		used[key] = true
	var base := maxi(1, int(block.shots_r1[primary]))
	var shape := maxf(.05, 1.0 + float(block.shape_share) * float(count) / float(base))
	var single := damage * rate
	var p := single * shape
	var reads: Array = block.reads[primary]
	var rest := {}
	var unread := {}
	for stat in totals:
		if used.has(stat): continue
		if stat in block.attack_keys and not stat in reads:
			unread[stat] = totals[stat]
			continue
		rest[stat] = totals[stat]
	var own_v: float = float(block.log_weight) * log(p) + loot.score({"stats": rest}, primary)
	var game_v: float = loot._verdict_worth(worn, primary, {})
	var item_rows: Array = []
	for entry in built.items: item_rows.append({"equip": String(entry.equip), "name": String(entry.item.name), "quality": String(entry.item.quality), "stats": entry.item.stats.duplicate(true)})
	var carriers := {}
	for stat in unread:
		var names: Array = []
		for entry in built.items:
			if int(entry.item.stats.get(stat, 0)) != 0: names.append("%s:%s=%d" % [entry.equip, entry.item.name, int(entry.item.stats[stat])])
		carriers[stat] = names
	return {"kit": kit_name, "primary": prim, "damage": damage, "rate": rate, "shape": shape, "single": single, "p": p, "v": game_v, "v_own": own_v,
		"v_check_diff": absf(own_v - game_v), "unread": unread, "unread_carriers": carriers, "totals": totals, "items": item_rows}
