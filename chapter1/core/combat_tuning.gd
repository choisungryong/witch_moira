extends RefCounted
## Loader and validator for chapter1/data/combat_tuning.json: enemy, zone, potion, XP and
## role (primary / secondary) numbers of the chapter core. The core never reads a number
## from a code constant that this file owns. A rejected document leaves the previous one alone.
const GrowthCatalog = preload("res://chapter1/core/growth_catalog.gd")
const DEFAULT_PATH := "res://chapter1/data/combat_tuning.json"
const ROOT_KEYS := ["schema_version","provenance","alive_cap","friendly_projectile_cap","spawn","enemies","hp_time_bps_per_s","hp_time_from_s",
	"champions","boss_ward","potion","orbs","xp_thresholds","primary_bonus","secondary","children",
	"seal_kills","presentation","marks","heavy_hit","final_level_on_boss_spawn","hero_shot"]
const KINDS := ["walker","ranged","charger"]
const STAGES := ["r1","r2","r3","r4","evo"]
const SECONDARY_KEYS := ["damage_bps","hit_budget_bps","cooldown_bps","max_chain_targets","max_branches"]
## Values that stay floats after normalisation; every other integral number becomes an int.
const FLOAT_KEYS := ["speed","ring_min_m","ring_max_m"]
var errors: Array[String] = []
var _document: Dictionary = {}

static func number(v: Variant, low: float, high: float) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and float(v) >= low and float(v) <= high

static func integer(v: Variant, low: int, high: int) -> bool:
	return GrowthCatalog.integer(v,low,high)

static func int_array(v: Variant, size: int, low: int, high: int) -> bool:
	if not v is Array or v.size() != size: return false
	for item in v:
		if not integer(item,low,high): return false
	return true

static func number_array(v: Variant, size: int, low: float, high: float) -> bool:
	if not v is Array or v.size() != size: return false
	for item in v:
		if not number(item,low,high): return false
	return true

## Every problem found, as short paths. Empty means the document is usable.
static func validate(v: Variant, skill_ids: Array, max_alive: int, max_projectiles: int) -> Array[String]:
	var issues: Array[String] = []
	if not v is Dictionary or not GrowthCatalog.keys_match(v,ROOT_KEYS): return ["root keys"]
	if not integer(v.schema_version,1,1) or v.provenance != "independent_design": issues.append("version/provenance")
	if not integer(v.alive_cap,1,max_alive-2): issues.append("alive_cap")
	if not integer(v.friendly_projectile_cap,0,max_projectiles): issues.append("friendly_projectile_cap")
	issues.append_array(_spawn_issues(v.spawn))
	issues.append_array(_enemy_issues(v.enemies))
	if not integer(v.hp_time_bps_per_s,0,100000): issues.append("hp_time_bps_per_s")
	if not integer(v.hp_time_from_s,0,600): issues.append("hp_time_from_s")
	if not v.champions is Array or v.champions.size() != 3: issues.append("champions size")
	else:
		for champion in v.champions:
			if not champion is Dictionary or not GrowthCatalog.keys_match(champion,["hp","damage","windup","recover","xp"]): issues.append("champion fields");continue
			if not integer(champion.hp,1,100000) or not integer(champion.damage,0,500) or not integer(champion.windup,1,600) or not integer(champion.recover,1,600) or not integer(champion.xp,0,100000):
				issues.append("champion range")
	if not v.boss_ward is Dictionary or not GrowthCatalog.keys_match(v.boss_ward,["damage"]) or not integer(v.boss_ward.damage,0,500): issues.append("boss_ward")
	issues.append_array(_potion_issues(v.potion))
	if not v.orbs is Dictionary or not GrowthCatalog.keys_match(v.orbs,["overflow","vacuum_on_seal"]) or not v.orbs.overflow in ["last","nearest"] or not v.orbs.vacuum_on_seal is bool: issues.append("orbs")
	if not v.xp_thresholds is Array or v.xp_thresholds.size() != 12: issues.append("12 xp_thresholds required")
	else:
		var previous := -1
		for amount in v.xp_thresholds:
			if not integer(amount,0,1000000) or amount <= previous: issues.append("xp_thresholds must strictly increase");break
			previous = int(amount)
		if v.xp_thresholds[0] != 0: issues.append("xp_thresholds start at zero")
	issues.append_array(_primary_issues(v.primary_bonus,skill_ids))
	issues.append_array(_secondary_issues(v.secondary))
	issues.append_array(_children_issues(v.children,skill_ids))
	if not int_array(v.seal_kills,3,1,100000): issues.append("seal_kills")
	if not v.presentation is Dictionary or not GrowthCatalog.keys_match(v.presentation,["arc_stripe_ticks"]) or not integer(v.presentation.arc_stripe_ticks,1,120): issues.append("presentation")
	if not v.marks is Dictionary or not GrowthCatalog.keys_match(v.marks,["mark_bps","mark_ticks"]) or not integer(v.marks.mark_bps,0,100000) or not integer(v.marks.mark_ticks,1,3600): issues.append("marks")
	issues.append_array(_heavy_issues(v.heavy_hit))
	if not v.final_level_on_boss_spawn is bool: issues.append("final_level_on_boss_spawn")
	if not v.hero_shot is Dictionary or not GrowthCatalog.keys_match(v.hero_shot,["spread_mrad"]) or not integer(v.hero_shot.spread_mrad,0,1000): issues.append("hero_shot")
	return issues

static func _heavy_issues(rule: Variant) -> Array[String]:
	if not rule is Dictionary or not GrowthCatalog.keys_match(rule,["heavy_bps","gap_ticks","iframe_ticks","graze_bps","ward_gap_ticks"]): return ["heavy_hit keys"]
	var issues: Array[String] = []
	# The ranges hold even while the rule is off (heavy_bps 0): a disabled document must still be a sane one.
	if not (integer(rule.heavy_bps,0,0) or integer(rule.heavy_bps,1000,10000)): issues.append("heavy_hit heavy_bps")
	if not integer(rule.iframe_ticks,24,120): issues.append("heavy_hit iframe_ticks")
	elif not integer(rule.gap_ticks,int(rule.iframe_ticks),600): issues.append("heavy_hit gap_ticks")
	if not integer(rule.graze_bps,500,10000): issues.append("heavy_hit graze_bps")
	if not integer(rule.ward_gap_ticks,0,600): issues.append("heavy_hit ward_gap_ticks")
	return issues

static func _spawn_issues(spawn: Variant) -> Array[String]:
	var issues: Array[String] = []
	if not spawn is Dictionary or not GrowthCatalog.keys_match(spawn,["ring_min_m","ring_max_m","opening","zones","boss_phase","mix"]): return ["spawn keys"]
	if not number(spawn.ring_min_m,2.0,19.0) or not number(spawn.ring_max_m,2.0,19.0) or float(spawn.ring_min_m) > float(spawn.ring_max_m): issues.append("spawn ring")
	if not spawn.opening is Array or spawn.opening.size() > 8: issues.append("spawn opening")
	else:
		var previous := 0
		for step in spawn.opening:
			if not step is Dictionary or not GrowthCatalog.keys_match(step,["until_s","amount"]) or not integer(step.until_s,previous+1,600) or not integer(step.amount,0,32):
				issues.append("spawn opening step");break
			previous = int(step.until_s)
	if not spawn.zones is Array or spawn.zones.size() != 3: issues.append("spawn zones")
	else:
		for entry in spawn.zones:
			if not _wave_valid(entry): issues.append("spawn zone entry")
	if not _wave_valid(spawn.boss_phase): issues.append("spawn boss_phase")
	# Specialist mix: a roll 0..99 of at least roll-zone*zone_step makes that kind, once its minute has come.
	var mix: Variant = spawn.mix
	if not mix is Dictionary or not GrowthCatalog.keys_match(mix,["charger_from_s","charger_roll","ranged_from_s","ranged_roll","zone_step"]): issues.append("spawn mix keys")
	elif not integer(mix.charger_from_s,0,600) or not integer(mix.ranged_from_s,0,600) or not integer(mix.charger_roll,0,100) or not integer(mix.ranged_roll,0,100) or not integer(mix.zone_step,0,50): issues.append("spawn mix range")
	return issues

static func _wave_valid(entry: Variant) -> bool:
	return entry is Dictionary and GrowthCatalog.keys_match(entry,["amount","interval_ticks"]) and integer(entry.amount,0,32) and integer(entry.interval_ticks,6,600)

static func _enemy_issues(enemies: Variant) -> Array[String]:
	var issues: Array[String] = []
	if not enemies is Dictionary or not GrowthCatalog.keys_match(enemies,KINDS): return ["enemies keys"]
	for kind in KINDS:
		var rules: Variant = enemies[kind]
		var keys := ["hp","damage","speed"]
		if kind == "walker": keys.append_array(["opening_hp","opening_until_s"])
		if not rules is Dictionary or not GrowthCatalog.keys_match(rules,keys): issues.append("enemy fields "+kind);continue
		if not int_array(rules.hp,3,1,100000): issues.append("enemy hp "+kind)
		if not int_array(rules.damage,3,0,500): issues.append("enemy damage "+kind)
		if not number_array(rules.speed,3,.1,12.0): issues.append("enemy speed "+kind)
		if kind == "walker" and (not integer(rules.opening_hp,1,100000) or not integer(rules.opening_until_s,0,600)): issues.append("walker opening")
	return issues

static func _potion_issues(potion: Variant) -> Array[String]:
	if not potion is Dictionary or not GrowthCatalog.keys_match(potion,["drop_one_in","seal_drops","start","carry_max","heal_bps","cooldown_ticks"]): return ["potion keys"]
	var issues: Array[String] = []
	if not integer(potion.drop_one_in,1,100000): issues.append("potion drop_one_in")
	if not integer(potion.seal_drops,0,16): issues.append("potion seal_drops")
	if not integer(potion.carry_max,0,99) or not integer(potion.start,0,99) or int(potion.start) > int(potion.carry_max): issues.append("potion start/carry_max")
	if not integer(potion.heal_bps,0,100000): issues.append("potion heal_bps")
	if not integer(potion.cooldown_ticks,0,3600): issues.append("potion cooldown_ticks")
	return issues

static func _primary_issues(table: Variant, skill_ids: Array) -> Array[String]:
	var issues: Array[String] = []
	if not table is Dictionary: return ["primary_bonus"]
	for skill_id in table:
		if not skill_id in skill_ids or not table[skill_id] is Dictionary: issues.append("primary_bonus skill "+str(skill_id));continue
		for stage in table[skill_id]:
			var bonus: Variant = table[skill_id][stage]
			if not stage in STAGES or not bonus is Dictionary: issues.append("primary_bonus stage "+str(stage));continue
			for op in bonus:
				if op == "cooldown_bps":
					if not integer(bonus[op],0,100000): issues.append("primary_bonus cooldown_bps")
				elif op == "add" or op == "mul_bps":
					if not bonus[op] is Dictionary: issues.append("primary_bonus "+str(op));continue
					for stat in bonus[op]:
						if not GrowthCatalog.LIMITS.has(stat) or stat == "cooldown_ticks": issues.append("primary_bonus stat "+str(stat)+" (cooldown only through cooldown_bps)");continue
						if op == "add" and not integer(bonus[op][stat],-1000000,1000000): issues.append("primary_bonus add "+str(stat))
						if op == "mul_bps" and not integer(bonus[op][stat],0,100000): issues.append("primary_bonus mul_bps "+str(stat))
				else: issues.append("primary_bonus op "+str(op))
	return issues

static func _secondary_issues(secondary: Variant) -> Array[String]:
	if not secondary is Dictionary: return ["secondary"]
	if secondary.is_empty(): return []
	if not GrowthCatalog.keys_match(secondary,SECONDARY_KEYS): return ["secondary keys"]
	var issues: Array[String] = []
	for key in ["damage_bps","hit_budget_bps","cooldown_bps"]:
		if not integer(secondary[key],0,100000): issues.append("secondary "+key)
	if not integer(secondary.max_chain_targets,1,32): issues.append("secondary max_chain_targets")
	if not integer(secondary.max_branches,1,4): issues.append("secondary max_branches")
	return issues

static func _children_issues(children: Variant, skill_ids: Array) -> Array[String]:
	var issues: Array[String] = []
	if not children is Dictionary: return ["children"]
	for skill_id in children:
		var rule: Variant = children[skill_id]
		if not skill_id in skill_ids or not rule is Dictionary or not GrowthCatalog.keys_match(rule,["count","life_ticks","speed","per_cast","evolved_only"]): issues.append("children entry "+str(skill_id));continue
		if not rule.evolved_only is bool: issues.append("children evolved_only "+str(skill_id))
		if not integer(rule.count,0,8) or not integer(rule.life_ticks,1,300) or not number(rule.speed,.1,30.0) or not integer(rule.per_cast,0,64): issues.append("children range "+str(skill_id))
	return issues

## Whole numbers become ints so the core never meets 14.0 where it expects 14.
static func normalize(value: Variant, key: String = "") -> Variant:
	if value is Dictionary:
		var result := {}
		for name in value: result[name] = normalize(value[name],str(name))
		return result
	if value is Array:
		var list := []
		for item in value: list.append(normalize(item,key))
		return list
	if value is float and not key in FLOAT_KEYS and value == floor(value): return int(value)
	return value

func load_file(path: String = DEFAULT_PATH, skill_ids: Array = [], max_alive: int = 180, max_projectiles: int = 192) -> bool:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		errors.assign(["Cannot read combat tuning: "+path])
		return false
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		errors.assign(["Combat tuning JSON line %d: %s" % [parser.get_error_line(),parser.get_error_message()]])
		return false
	return replace_document(parser.data,skill_ids,max_alive,max_projectiles)

func replace_document(candidate: Variant, skill_ids: Array, max_alive: int, max_projectiles: int) -> bool:
	var issues := validate(candidate,skill_ids,max_alive,max_projectiles)
	if not issues.is_empty():
		errors = issues
		return false
	errors.clear()
	_document = normalize(candidate)
	return true

## Makes a document and everything nested in it read-only.
static func lock(value: Variant) -> void:
	if value is Dictionary:
		for key in value: lock(value[key])
		value.make_read_only()
	elif value is Array:
		for item in value: lock(item)
		value.make_read_only()

func snapshot() -> Dictionary:
	return _document.duplicate(true)
