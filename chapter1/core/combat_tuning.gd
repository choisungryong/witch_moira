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
const FLOAT_KEYS := ["speed","ring_min_m","ring_max_m","radius_m"]
## Optional block (D11 A6): a document without it runs the plain spawn rules, and so does one with "enabled": false.
const RHYTHM_KEYS := ["enabled","initial_pack","gate_rest_ticks","beats","trial","boss"]
const BEAT_KEYS := ["id","zone","from_bps","max_ticks","amount","interval_ticks","alive_cap","hp_bps","mix","wave"]
const OPENING_STEP_KEYS := ["id","max_ticks","kills","amount","interval_ticks","alive_cap","ring_m","heading","speed_bps","acquire_m","orb_pull_m","crest","mix","first_visit_only"]
const BEAT_OPTIONAL :=["ranged_from_ticks","charger_from_ticks","taste_crest","xp_bps","ranged_cap"]
## D19 C1: optional keys of the rhythm block (a level table of its own, seal kills, the guardian's grace, the sweep bonus). Absent = the old rules.
const RHYTHM_C1 := ["xp_thresholds","seal_kills","guardian_grace","kill_burst","guardian"]
const KILL_BURST_KEYS := ["window_ticks","min_kills","xp_bonus_bps","descent_bonus_bps"]
const PACE_KEYS := ["soft_after_ticks","ramp_bps_per_s","max_bps"]
## Optional blocks (D13 G0). A document without them runs the plain rules, and so does one with "enabled": false.
## "grace" (boon cadence, tools and grades, D13 4.3/4.11), "elites" (W4-a body) and "extras" (W5-a guarded sites, shrines) are
## checked in full; extras keeps room for the keys of W5-b/c ("unguarded", "rituals", "grade"), which are only required to be objects.
const OPTIONAL_ROOT := ["rhythm","grace","elites","extras","meteor","loot_flow","stat_caps","gear_conditions"]
## D23 T1-B: totals the core cuts whatever the equipment says (absent block = no cap), and the three windows of the gear condition
## lines (absent block = those lines never hold).
const STAT_CAPS_KEYS := ["damage_reduction_bps","condition_damage_bps"]
const GEAR_CONDITIONS_KEYS := ["after_dash_ticks","moving_ticks","lowhp_bps"]
## D23 T17: optional, both or neither.
const GEAR_CONDITIONS_STREAK_KEYS := ["streak_kills","streak_window_ticks"]
## D20: the evolved ember falls from the sky instead of flying. Absent block = it flies as before.
const METEOR_KEYS := ["fall_ticks","lead_bps","scatter_cm","radius_bps","damage_bps"]
## D21 N2: gear of a high enough quality stays on the ground and is gathered when a gate opens. Absent block or "enabled": false = the old 180 s rule.
## The quality names are checked against loot.json when the run starts (the loader has no loot tables).
const LOOT_FLOW_KEYS := ["enabled","keep_min_quality","gate_sweep_min_quality"]
const ELITES_KEYS := ["enabled","balance_status","per_zone","at_seal_bps","kinds","hp","damage_bps","speed_bps","radius_bps","xp","affixes_per_zone","affixes"]
const EXTRAS_KEYS := ["enabled","balance_status","guarded","shrines","chests"]
const EXTRAS_LATER := ["unguarded","rituals","grade"]
const GUARDED_KEYS := ["sites","distance_m","leash_m","aggro_m","alert_ticks","return_far_m","return_after_ticks","tiers","potions"]
const SITE_KEYS := ["id","zone","at_bps","kind","pool","points"]
## Gear stats a shrine may add for a while (never max_hp_raw: the body is not rebuilt by a timed buff).
const SHRINE_STATS := ["damage_bps","cooldown_bps","damage_reduction_bps","pickup_radius_cm","move_speed_bps","dash_cooldown_bps","soul_gain_bps"]
const SHRINE_QUALITIES := ["rare","legendary","unique"]
const GRACE_KEYS := ["enabled","balance_status","evolve_min_level","final_offer","min_gap_ticks","tools","survival_from_level","pact_from_level","link_slots","grades"]
const GRACE_PROTECT_WORDS := ["evolve_keystone","evolve","passive","axis","survival"]
const GRACE_BANISH_KINDS := ["unlock","axis","rank","survival","link","pact"]
const GRADE_KEYS := ["enabled","kinds","rare_bps","jackpot_bps","cap_bps","near_bps","pity","final_offer_jackpot_mul_bps","luck","rare","jackpot"]
const GRADE_KINDS := ["unlock","axis","rank","survival","link"]
const TRIAL_KEYS := ["enabled","hold_ticks","radius_m","amount","interval_ticks","alive_cap","hp_bps","mix","clear_ticks"]
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
	if not v is Dictionary: return ["root keys"]
	var base_keys: Dictionary = v
	for optional in OPTIONAL_ROOT:
		if v.has(optional):
			if base_keys == v: base_keys = v.duplicate()
			base_keys.erase(optional)
	if not GrowthCatalog.keys_match(base_keys,ROOT_KEYS): return ["root keys"]
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
	if v.has("rhythm"):
		# The per-beat alive_cap is bounded by the document's own alive_cap, so that one has to be sound first.
		issues.append_array(_rhythm_issues(v.rhythm,int(v.alive_cap) if integer(v.alive_cap,1,100000) else 1))
	if v.has("meteor"): issues.append_array(_meteor_issues(v.meteor))
	if v.has("grace"): issues.append_array(_grace_issues(v.grace))
	if v.has("elites"): issues.append_array(_elites_issues(v.elites))
	if v.has("extras"): issues.append_array(_extras_issues(v.extras))
	if v.has("loot_flow"): issues.append_array(_loot_flow_issues(v.loot_flow))
	if v.has("stat_caps"):
		if not v.stat_caps is Dictionary or not GrowthCatalog.keys_match(v.stat_caps,STAT_CAPS_KEYS): issues.append("stat_caps keys")
		else:
			if not integer(v.stat_caps.damage_reduction_bps,1,10000): issues.append("stat_caps damage_reduction_bps")
			if not integer(v.stat_caps.condition_damage_bps,1,100000): issues.append("stat_caps condition_damage_bps")
	if v.has("gear_conditions"):
		# D23 T17: streak_kills and streak_window_ticks are optional and come together (both or neither); the three required keys stay exact.
		var gear_conditions_ok: bool = v.gear_conditions is Dictionary
		if gear_conditions_ok:
			var streak_keys := 0
			var required := {}
			for key in v.gear_conditions:
				if key in GEAR_CONDITIONS_STREAK_KEYS: streak_keys += 1
				else: required[key] = v.gear_conditions[key]
			gear_conditions_ok = streak_keys != 1 and GrowthCatalog.keys_match(required,GEAR_CONDITIONS_KEYS)
			if gear_conditions_ok and streak_keys == 2:
				if not integer(v.gear_conditions.streak_kills,1,200): issues.append("gear_conditions streak_kills")
				if not integer(v.gear_conditions.streak_window_ticks,1,3600): issues.append("gear_conditions streak_window_ticks")
		if not gear_conditions_ok: issues.append("gear_conditions keys")
		else:
			if not integer(v.gear_conditions.after_dash_ticks,1,3600): issues.append("gear_conditions after_dash_ticks")
			if not integer(v.gear_conditions.moving_ticks,1,600): issues.append("gear_conditions moving_ticks")
			if not integer(v.gear_conditions.lowhp_bps,1,10000): issues.append("gear_conditions lowhp_bps")
	return issues

## D23 T5: loot_flow may carry one more key, "boss_spray" (guardian and boss loot spills on the floor and is pulled to the hero later).
const BOSS_SPRAY_KEYS := ["enabled","guardian_pull_ticks","boss_pull_ticks","arrive_ticks","ring_min_cm","ring_max_cm"]

static func _loot_flow_issues(b: Variant) -> Array[String]:
	if not b is Dictionary: return ["loot_flow keys"]
	var base: Dictionary = b.duplicate()
	base.erase("boss_spray")
	if not GrowthCatalog.keys_match(base,LOOT_FLOW_KEYS): return ["loot_flow keys"]
	var issues: Array[String] = []
	if b.has("boss_spray"):
		var spray: Variant = b.boss_spray
		if not spray is Dictionary or not GrowthCatalog.keys_match(spray,BOSS_SPRAY_KEYS): issues.append("loot_flow boss_spray keys")
		else:
			if not spray.enabled is bool: issues.append("loot_flow boss_spray enabled")
			if not integer(spray.guardian_pull_ticks,1,1800) or not integer(spray.boss_pull_ticks,1,1800) or not integer(spray.arrive_ticks,1,600): issues.append("loot_flow boss_spray ticks")
			if not integer(spray.ring_min_cm,50,2000) or not integer(spray.ring_max_cm,50,2000) or int(spray.ring_max_cm) < int(spray.ring_min_cm): issues.append("loot_flow boss_spray ring")
	if not b.enabled is bool: issues.append("loot_flow enabled")
	for key in ["keep_min_quality","gate_sweep_min_quality"]:
		if not b[key] is String or String(b[key]).is_empty(): issues.append("loot_flow "+key)
	return issues

## D20 ranges: fall 0.1 to 2 s, lead 0 to 1, scatter up to 6 m, radius and damage multipliers 0.3x to 3x.
static func _meteor_issues(m: Variant) -> Array[String]:
	if not m is Dictionary or not GrowthCatalog.keys_match(m,METEOR_KEYS): return ["meteor keys"]
	var issues: Array[String] = []
	if not integer(m.fall_ticks,6,120): issues.append("meteor fall_ticks")
	if not integer(m.lead_bps,0,10000): issues.append("meteor lead_bps")
	if not integer(m.scatter_cm,0,600): issues.append("meteor scatter_cm")
	if not integer(m.radius_bps,3000,30000): issues.append("meteor radius_bps")
	if not integer(m.damage_bps,3000,30000): issues.append("meteor damage_bps")
	return issues

static func _bps(v: Variant, high: int = 10000) -> bool:
	return integer(v,0,high)

static func _word_list(v: Variant, allowed: Array, max_size: int) -> bool:
	if not v is Array or v.size() > max_size: return false
	for item in v:
		if not item is String or not item in allowed: return false
	return true

## D13 4.3 and 4.11.6 ranges. Every problem is one short path; an empty list means the block is usable.
static func _grace_issues(g: Variant) -> Array[String]:
	if not g is Dictionary: return ["grace keys"]
	# D19 C1-f: "pace" is the one optional key of the block.
	var grace_base: Dictionary = g
	if g.has("pace"):
		grace_base = g.duplicate()
		grace_base.erase("pace")
	if not GrowthCatalog.keys_match(grace_base,GRACE_KEYS): return ["grace keys"]
	var issues: Array[String] = []
	if g.has("pace"):
		var pace: Variant = g.pace
		if not pace is Dictionary or not GrowthCatalog.keys_match(pace,PACE_KEYS) or not integer(pace.soft_after_ticks,60,36000) or not integer(pace.ramp_bps_per_s,0,10000) or not integer(pace.max_bps,10000,50000): issues.append("grace pace")
	if not g.enabled is bool: issues.append("grace enabled")
	if not g.balance_status is String: issues.append("grace balance_status")
	if not integer(g.evolve_min_level,0,12): issues.append("grace evolve_min_level")
	var f: Variant = g.final_offer
	if not f is Dictionary or not GrowthCatalog.keys_match(f,["mode","cards","protect_order"]): issues.append("grace final_offer keys")
	else:
		if not f.mode in ["none","big"]: issues.append("grace final_offer mode")
		if not integer(f.cards,3,4): issues.append("grace final_offer cards")
		if not _word_list(f.protect_order,GRACE_PROTECT_WORDS,5): issues.append("grace final_offer protect_order")
	if not integer(g.min_gap_ticks,0,3600): issues.append("grace min_gap_ticks")
	var t: Variant = g.tools
	if not t is Dictionary or not GrowthCatalog.keys_match(t,["base_rerolls","base_banishes","base_holds","banish_kinds"]): issues.append("grace tools keys")
	else:
		for key in ["base_rerolls","base_banishes","base_holds"]:
			if not integer(t[key],0,3): issues.append("grace tools "+key)
		if not _word_list(t.banish_kinds,GRACE_BANISH_KINDS,6): issues.append("grace tools banish_kinds")
	if not integer(g.survival_from_level,1,12) or not integer(g.pact_from_level,1,12) or not integer(g.link_slots,0,4): issues.append("grace survival/pact/link keys")
	issues.append_array(_grade_issues(g.grades))
	return issues

static func _grade_issues(d: Variant) -> Array[String]:
	if not d is Dictionary or not GrowthCatalog.keys_match(d,GRADE_KEYS): return ["grace grades keys"]
	var issues: Array[String] = []
	if not d.enabled is bool: issues.append("grace grades enabled")
	if not _word_list(d.kinds,GRADE_KINDS,5): issues.append("grace grades kinds")
	if not _bps(d.rare_bps) or not _bps(d.jackpot_bps) or not integer(d.cap_bps,0,5000) or not _bps(d.near_bps): issues.append("grace grades bps")
	elif int(d.rare_bps)+int(d.jackpot_bps) > 10000: issues.append("grace grades rare+jackpot over 10000")
	var p: Variant = d.pity
	if not p is Dictionary or not GrowthCatalog.keys_match(p,["soft_step_bps","hard_after_spins"]) or not _bps(p.soft_step_bps) or not integer(p.hard_after_spins,0,20): issues.append("grace grades pity")
	if not integer(d.final_offer_jackpot_mul_bps,10000,100000): issues.append("grace grades final_offer_jackpot_mul_bps")
	var l: Variant = d.luck
	if not l is Dictionary or not GrowthCatalog.keys_match(l,["shrine_mul_bps","per_reward_grade_bps","gear_cap_bps"]) or not integer(l.shrine_mul_bps,10000,100000) or not _bps(l.per_reward_grade_bps,1000) or not _bps(l.gear_cap_bps): issues.append("grace grades luck")
	var r: Variant = d.rare
	if not r is Dictionary or not GrowthCatalog.keys_match(r,["axis_points","unlock_points","rank_points","scale_bps"]) or not integer(r.axis_points,0,4) or not integer(r.unlock_points,0,4) or not integer(r.rank_points,0,3) or not integer(r.scale_bps,10000,100000): issues.append("grace grades rare")
	var j: Variant = d.jackpot
	if not j is Dictionary or not GrowthCatalog.keys_match(j,["form","base","resonance","evolve_partner_bonus_bps"]): issues.append("grace grades jackpot keys")
	else:
		if not j.form in ["resonance","big"]: issues.append("grace grades jackpot form")
		var b: Variant = j.base
		if not b is Dictionary or not GrowthCatalog.keys_match(b,["axis_points","unlock_points","rank_points","scale_bps"]) or not integer(b.axis_points,0,4) or not integer(b.unlock_points,0,4) or not integer(b.rank_points,0,3) or not integer(b.scale_bps,10000,100000): issues.append("grace grades jackpot base")
		var q: Variant = j.resonance
		if not q is Dictionary or not GrowthCatalog.keys_match(q,["axis_points","partner_points","axis_cap_bonus","unlock_points","link_scale_bps"]) or not integer(q.axis_points,0,4) or not integer(q.partner_points,0,2) or not integer(q.axis_cap_bonus,0,2) or not integer(q.unlock_points,0,4) or not integer(q.link_scale_bps,10000,100000): issues.append("grace grades jackpot resonance")
		if not integer(j.evolve_partner_bonus_bps,0,100000): issues.append("grace grades jackpot evolve_partner_bonus_bps")
	return issues

## D13 5.1 (D2 5.1) ranges. Every problem is one short path; an empty list means the block is usable. The affixes of D2 E2 are not
## built yet: the block must say none (all zero, empty), so a document cannot ask for what the core does not do.
static func _elites_issues(b: Variant) -> Array[String]:
	if not b is Dictionary or not GrowthCatalog.keys_match(b,ELITES_KEYS): return ["elites keys"]
	var issues: Array[String] = []
	if not b.enabled is bool: issues.append("elites enabled")
	if not b.balance_status is String: issues.append("elites balance_status")
	if not int_array(b.per_zone,3,0,4): issues.append("elites per_zone")
	var rises: bool = b.at_seal_bps is Array and b.at_seal_bps.size() >= 1 and b.at_seal_bps.size() <= 4
	if rises:
		var previous := 0
		for amount in b.at_seal_bps:
			if not integer(amount,1,9999) or int(amount) <= previous: rises = false;break
			previous = int(amount)
	if not rises: issues.append("elites at_seal_bps")
	elif int_array(b.per_zone,3,0,4):
		for count in b.per_zone:
			if int(count) > b.at_seal_bps.size(): issues.append("elites per_zone above the at_seal_bps entries");break
	if not b.kinds is Array or b.kinds.size() != 3: issues.append("elites kinds")
	else:
		for weights in b.kinds:
			var ok: bool = weights is Dictionary and not weights.is_empty()
			var total := 0
			if ok:
				for kind in weights:
					if not kind in KINDS or not integer(weights[kind],0,100): ok = false;break
					total += int(weights[kind])
			if not ok or total < 1: issues.append("elites kinds weights");break
	if not int_array(b.hp,3,1,5000): issues.append("elites hp")
	for key in ["damage_bps","speed_bps","radius_bps"]:
		if not integer(b[key],5000,30000): issues.append("elites "+key)
	if not int_array(b.xp,3,0,1000): issues.append("elites xp")
	if not int_array(b.affixes_per_zone,3,0,0) or not b.affixes is Dictionary or not b.affixes.is_empty(): issues.append("elites affixes (not built: all zero and empty)")
	return issues

## D13 5.2 ranges (guarded sites, shrines, chests). The keys of W5-b/c may be present as plain objects.
static func _extras_issues(b: Variant) -> Array[String]:
	if not b is Dictionary: return ["extras keys"]
	var base_keys: Dictionary = b.duplicate()
	for later in EXTRAS_LATER:
		if b.has(later):
			if not b[later] is Dictionary: return ["extras "+later]
			base_keys.erase(later)
	if not GrowthCatalog.keys_match(base_keys,EXTRAS_KEYS): return ["extras keys"]
	var issues: Array[String] = []
	if not b.enabled is bool: issues.append("extras enabled")
	if not b.balance_status is String: issues.append("extras balance_status")
	var kinds: Variant = null
	var pools: Variant = null
	var s: Variant = b.shrines
	if not s is Dictionary or not GrowthCatalog.keys_match(s,["touch_radius_m","stay_ticks","guarded_ticks_bps","kinds","pool"]): issues.append("extras shrines keys")
	else:
		if not number(s.touch_radius_m,.5,4.0): issues.append("extras shrines touch_radius_m")
		if not integer(s.stay_ticks,60,7200): issues.append("extras shrines stay_ticks")
		if not integer(s.guarded_ticks_bps,5000,30000): issues.append("extras shrines guarded_ticks_bps")
		issues.append_array(_shrine_kind_issues(s.kinds))
		if s.kinds is Dictionary and not s.kinds.is_empty(): kinds = s.kinds
		if not s.pool is Dictionary or s.pool.is_empty(): issues.append("extras shrines pool")
		else:
			pools = s.pool
			for key in s.pool:
				var list: Variant = s.pool[key]
				var ok: bool = list is Array and list.size() >= 1 and list.size() <= 8
				if ok:
					for kind in list:
						if not kind is String or kinds == null or not kinds.has(kind): ok = false;break
				if not ok: issues.append("extras shrines pool "+str(key))
	issues.append_array(_guarded_issues(b.guarded,pools))
	var c: Variant = b.chests
	if not c is Dictionary or not GrowthCatalog.keys_match(c,["open_radius_m","orb_xp","class"]) or not number(c.open_radius_m,.5,4.0) or not integer(c.orb_xp,0,100) or not c["class"] is String or String(c["class"]).is_empty(): issues.append("extras chests")
	return issues

static func _shrine_kind_issues(kinds: Variant) -> Array[String]:
	if not kinds is Dictionary or kinds.is_empty() or kinds.size() > 8: return ["extras shrines kinds"]
	var issues: Array[String] = []
	for id_ in kinds:
		var k: Variant = kinds[id_]
		var tag := "extras shrines kind "+str(id_)+" "
		if not id_ is String or String(id_).is_empty() or not k is Dictionary or not integer(k.get("ticks"),60,7200): issues.append(tag+"ticks");continue
		var allowed := ["ticks","stats","drop_bps","quality_bps","heal_bps"]
		var effects := 0
		for key in k:
			if not key in allowed: issues.append(tag+"key "+str(key))
		if k.has("stats"):
			effects += 1
			if not k.stats is Dictionary or k.stats.is_empty(): issues.append(tag+"stats")
			else:
				for stat in k.stats:
					if not stat in SHRINE_STATS or not integer(k.stats[stat],1,10000): issues.append(tag+"stat "+str(stat))
		if k.has("drop_bps"):
			effects += 1
			if not integer(k.drop_bps,10000,100000): issues.append(tag+"drop_bps")
		if k.has("quality_bps"):
			var q: Variant = k.quality_bps
			if not q is Dictionary or q.is_empty(): issues.append(tag+"quality_bps")
			else:
				for quality in q:
					if not quality in SHRINE_QUALITIES or not integer(q[quality],10000,100000): issues.append(tag+"quality_bps "+str(quality))
		if k.has("heal_bps"):
			effects += 1
			if not integer(k.heal_bps,1,10000): issues.append(tag+"heal_bps")
		if effects == 0: issues.append(tag+"has no effect")
	return issues

static func _guarded_issues(g: Variant, pools: Variant) -> Array[String]:
	if not g is Dictionary or not GrowthCatalog.keys_match(g,GUARDED_KEYS): return ["extras guarded keys"]
	var issues: Array[String] = []
	if not g.sites is Array or g.sites.size() < 1 or g.sites.size() > 4: issues.append("extras guarded sites");return issues
	var seen := {}
	var previous_zone := 0
	var previous_at := -1
	for index in g.sites.size():
		var site: Variant = g.sites[index]
		var tag := "extras guarded site %d " % index
		if not site is Dictionary or not GrowthCatalog.keys_match(site,SITE_KEYS): issues.append(tag+"keys");continue
		if not site.id is String or String(site.id).is_empty() or seen.has(site.id): issues.append(tag+"id")
		else: seen[site.id] = true
		if not integer(site.zone,0,1) or not integer(site.at_bps,0,9999): issues.append(tag+"zone/at_bps");continue
		# The core walks the list once: zone order, then the progress at which a site is put down.
		if int(site.zone) < previous_zone or (int(site.zone) == previous_zone and int(site.at_bps) <= previous_at): issues.append(tag+"order")
		previous_zone = int(site.zone);previous_at = int(site.at_bps)
		if not site.kind in ["shrine","chest"]: issues.append(tag+"kind")
		elif site.kind == "shrine" and (not site.pool is String or pools == null or not pools.has(site.pool)): issues.append(tag+"pool")
		elif site.kind == "chest" and site.pool != "": issues.append(tag+"pool (a chest has none)")
		var ok_points: bool = site.points is Array and site.points.size() >= 1 and site.points.size() <= 8
		if ok_points:
			for point in site.points:
				if not number_array(point,2,-17.0,17.0): ok_points = false;break
		if not ok_points: issues.append(tag+"points (1..8 of [x,y] within 17 m of the zone centre)")
	if not number_array(g.distance_m,2,4.0,18.0) or float(g.distance_m[0]) > float(g.distance_m[1]): issues.append("extras guarded distance_m")
	if not number(g.leash_m,2.0,12.0): issues.append("extras guarded leash_m")
	if not number(g.aggro_m,1.0,8.0): issues.append("extras guarded aggro_m")
	elif number(g.leash_m,2.0,12.0) and float(g.aggro_m) > float(g.leash_m): issues.append("extras guarded aggro_m above leash_m")
	if not integer(g.alert_ticks,0,120): issues.append("extras guarded alert_ticks")
	if not number(g.return_far_m,6.0,30.0): issues.append("extras guarded return_far_m")
	if not integer(g.return_after_ticks,60,1800): issues.append("extras guarded return_after_ticks")
	if not integer(g.potions,0,3): issues.append("extras guarded potions")
	if not g.tiers is Array or g.tiers.size() < 1 or g.tiers.size() > 3: issues.append("extras guarded tiers")
	else:
		var ids := {}
		for tier in g.tiers:
			if not tier is Dictionary or not GrowthCatalog.keys_match(tier,["id","weight","elite_hp_bps","chest_class"]) or not tier.id is String or String(tier.id).is_empty() or ids.has(tier.id) \
				or not integer(tier.weight,1,10000) or not integer(tier.elite_hp_bps,5000,40000) or not tier.chest_class is String or String(tier.chest_class).is_empty():
				issues.append("extras guarded tier");break
			ids[tier.id] = true
	return issues

static func _mix_valid(mix: Variant) -> bool:
	if not mix is Dictionary or not GrowthCatalog.keys_match(mix,["walker","ranged","charger"]): return false
	for kind in KINDS:
		if not integer(mix[kind],0,100): return false
	return int(mix.walker)+int(mix.ranged)+int(mix.charger) >= 1

## D22 R1-B: a wave's crest is a fan with two optional keys: mix (kinds of the head, sum 100) and count_jitter_bps.
static func _crest_issues(crest: Variant,tag: String) -> Array[String]:
	var issues: Array[String] = []
	if not crest is Dictionary: return [tag+"wave crest"]
	var base: Dictionary=crest.duplicate()
	base.erase("mix");base.erase("count_jitter_bps")
	if not _fan_valid(base,["count","arc_deg"]): issues.append(tag+"wave crest")
	if crest.has("count_jitter_bps") and not integer(crest.count_jitter_bps,0,3000): issues.append(tag+"wave crest count_jitter_bps")
	if crest.has("mix"):
		var mix: Variant=crest.mix
		var ok: bool = mix is Dictionary and not mix.is_empty()
		var total := 0
		if ok:
			for kind in mix:
				if not kind in KINDS or not integer(mix[kind],0,100): ok = false;break
				total += int(mix[kind])
		if not ok or total != 100: issues.append(tag+"wave crest mix")
	return issues

## squad {count 0..8, ring_m [lo, hi] inside 6..14, at_ticks inside the part of the period before the lull}.
static func _squad_valid(sq: Variant, w: Dictionary) -> bool:
	if not sq is Dictionary or not GrowthCatalog.keys_match(sq,["count","ring_m","at_ticks"]): return false
	if not integer(sq.count,0,8) or not sq.ring_m is Array or sq.ring_m.size() != 2: return false
	if not number(sq.ring_m[0],6.0,14.0) or not number(sq.ring_m[1],6.0,14.0) or float(sq.ring_m[0]) > float(sq.ring_m[1]): return false
	if not integer(w.period_ticks,60,36000) or not integer(w.lull_ticks,0,36000): return false
	return integer(sq.at_ticks,0,int(w.period_ticks)-int(w.lull_ticks)-1)

static func _fan_valid(entry: Variant, keys: Array) -> bool:
	return entry is Dictionary and GrowthCatalog.keys_match(entry,keys) and integer(entry.count,1,60) and integer(entry.arc_deg,10,360)

## D11 A6 ranges. Every problem is one short path; an empty list means the block is usable.
static func _rhythm_issues(r: Variant, alive_cap: int) -> Array[String]:
	if not r is Dictionary: return ["rhythm keys"]
	var base_keys: Dictionary = r.duplicate()
	for key in ["opening"]+RHYTHM_C1: base_keys.erase(key)
	if not GrowthCatalog.keys_match(base_keys,RHYTHM_KEYS): return ["rhythm keys"]
	var issues: Array[String] = []
	if not r.enabled is bool: issues.append("rhythm enabled")
	if not integer(r.initial_pack,0,40): issues.append("rhythm initial_pack")
	if not integer(r.gate_rest_ticks,0,3600): issues.append("rhythm gate_rest_ticks")
	issues.append_array(_rhythm_c1_issues(r))
	if not r.beats is Array or r.beats.size() < 1 or r.beats.size() > 8: issues.append("rhythm beats");return issues
	var seen_ids := {}
	var previous_zone := 0
	var previous_from := -1
	for index in r.beats.size():
		var b: Variant = r.beats[index]
		var tag := "rhythm beat %d " % index
		if not b is Dictionary: issues.append(tag+"entry");continue
		var ok_keys := true
		for key in BEAT_KEYS:
			if not b.has(key): ok_keys = false
		for key in b:
			if not key in BEAT_KEYS and not key in BEAT_OPTIONAL: ok_keys = false
		if not ok_keys: issues.append(tag+"keys");continue
		if not b.id is String or String(b.id).is_empty() or b.id in ["trial","boss"] or seen_ids.has(b.id): issues.append(tag+"id")
		else: seen_ids[b.id] = true
		if not integer(b.zone,0,2) or int(b.zone) < previous_zone: issues.append(tag+"zone");continue
		# from_bps rises beat by beat inside one zone; a new zone starts the order again. The first beat covers progress 0 of zone 0.
		if not integer(b.from_bps,0,9999) or (int(b.zone) == previous_zone and index > 0 and int(b.from_bps) <= previous_from) or (index == 0 and (int(b.zone) != 0 or int(b.from_bps) != 0)): issues.append(tag+"from_bps")
		previous_zone = int(b.zone)
		previous_from = int(b.from_bps) if integer(b.from_bps,0,9999) else previous_from
		if not integer(b.max_ticks,60,108000): issues.append(tag+"max_ticks")
		if not integer(b.amount,0,30): issues.append(tag+"amount")
		if not integer(b.interval_ticks,12,600): issues.append(tag+"interval_ticks")
		if not integer(b.alive_cap,1,alive_cap): issues.append(tag+"alive_cap")
		if not int_array(b.hp_bps,2,5000,80000): issues.append(tag+"hp_bps")
		if not _mix_valid(b.mix): issues.append(tag+"mix")
		for key in ["ranged_from_ticks","charger_from_ticks"]:
			if b.has(key) and not integer(b[key],0,108000): issues.append(tag+key)
		if b.has("xp_bps") and not integer(b.xp_bps,1000,50000): issues.append(tag+"xp_bps")
		if b.has("ranged_cap") and not integer(b.ranged_cap,0,40): issues.append(tag+"ranged_cap")
		if b.has("taste_crest") and not (_fan_valid(b.taste_crest,["at_ticks","count","arc_deg"]) and integer(b.taste_crest.at_ticks,0,108000)): issues.append(tag+"taste_crest")
		if b.wave != null:
			var w: Variant = b.wave
			var wave_base: Variant=w.duplicate() if w is Dictionary else w
			if wave_base is Dictionary: wave_base.erase("squad")
			if not w is Dictionary or not GrowthCatalog.keys_match(wave_base,["period_ticks","lull_ticks","lull_amount_bps","lull_cap_bps","crest"]): issues.append(tag+"wave keys");continue
			if not integer(w.period_ticks,60,36000) or not integer(w.lull_ticks,0,36000) or int(w.period_ticks) <= int(w.lull_ticks): issues.append(tag+"wave period/lull")
			if not integer(w.lull_amount_bps,0,10000) or not integer(w.lull_cap_bps,0,10000): issues.append(tag+"wave lull bps")
			issues.append_array(_crest_issues(w.crest,tag))
			if w.has("squad") and not _squad_valid(w.squad,w): issues.append(tag+"wave squad")
	var t: Variant = r.trial
	var trial_base: Variant = t
	if t is Dictionary and t.has("xp_bps"):
		trial_base = t.duplicate()
		trial_base.erase("xp_bps")
	if not t is Dictionary or not GrowthCatalog.keys_match(trial_base,TRIAL_KEYS): issues.append("rhythm trial keys")
	else:
		if t.has("xp_bps") and not integer(t.xp_bps,1000,50000): issues.append("rhythm trial xp_bps")
		if not t.enabled is bool: issues.append("rhythm trial enabled")
		if not integer(t.hold_ticks,600,5400): issues.append("rhythm trial hold_ticks")
		if not number(t.radius_m,4.0,19.0): issues.append("rhythm trial radius_m")
		if not integer(t.amount,0,30): issues.append("rhythm trial amount")
		if not integer(t.interval_ticks,12,600): issues.append("rhythm trial interval_ticks")
		if not integer(t.alive_cap,1,alive_cap): issues.append("rhythm trial alive_cap")
		if not integer(t.hp_bps,5000,80000): issues.append("rhythm trial hp_bps")
		if not _mix_valid(t.mix): issues.append("rhythm trial mix")
		if not integer(t.clear_ticks,0,1800): issues.append("rhythm trial clear_ticks")
	if not r.boss is Dictionary or not GrowthCatalog.keys_match(r.boss,["phase_break_ticks"]) or not integer(r.boss.phase_break_ticks,0,600): issues.append("rhythm boss")
	if r.has("opening"):
		# The opening's per-step cap is bounded by the first beat's own cap (which is bounded by the document's).
		var first_cap := alive_cap
		var first: Variant = r.beats[0]
		if first is Dictionary and integer(first.get("alive_cap"),1,alive_cap): first_cap = int(first.alive_cap)
		issues.append_array(_opening_issues(r.opening,first_cap))
	return issues

## D19 C1 ranges (a, b, c, e). Absent keys are fine; a present one must be sound.
static func _rhythm_c1_issues(r: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	if r.has("xp_thresholds"):
		var table: Variant = r.xp_thresholds
		if not table is Array or table.size() < 12 or table.size() > 20: issues.append("rhythm xp_thresholds size")
		else:
			var previous := -1
			for amount in table:
				if not integer(amount,0,1000000) or amount <= previous: issues.append("rhythm xp_thresholds must strictly increase");break
				previous = int(amount)
			if table[0] != 0: issues.append("rhythm xp_thresholds start at zero")
	if r.has("seal_kills") and not int_array(r.seal_kills,3,1,5000): issues.append("rhythm seal_kills")
	if r.has("guardian_grace") and not r.guardian_grace is bool: issues.append("rhythm guardian_grace")
	if r.has("guardian"):
		var g: Variant=r.guardian
		var g_base: Variant=g.duplicate() if g is Dictionary else g
		if g_base is Dictionary: g_base.erase("crest")
		if not g is Dictionary or not GrowthCatalog.keys_match(g_base,["steady_bps"]) or not integer(g.steady_bps,0,10000) or (g.has("crest") and not g.crest is bool): issues.append("rhythm guardian")
	if r.has("kill_burst"):
		var k: Variant = r.kill_burst
		if not k is Dictionary or not GrowthCatalog.keys_match(k,KILL_BURST_KEYS) or not integer(k.window_ticks,6,120) or not integer(k.min_kills,3,40) 			or not integer(k.xp_bonus_bps,0,20000) or not integer(k.descent_bonus_bps,0,20000): issues.append("rhythm kill_burst")
	return issues

## D15 O-1 ranges. Every problem is one short path; an empty list means the block is usable.
static func _opening_issues(o: Variant, first_cap: int) -> Array[String]:
	if not o is Dictionary or not GrowthCatalog.keys_match(o,["enabled","steps"]): return ["rhythm opening keys"]
	var issues: Array[String] = []
	if not o.enabled is bool: issues.append("rhythm opening enabled")
	if not o.steps is Array or o.steps.size() < 1 or o.steps.size() > 8: issues.append("rhythm opening steps");return issues
	var seen := {}
	for index in o.steps.size():
		var s: Variant = o.steps[index]
		var tag := "rhythm opening step %d " % index
		if not s is Dictionary: issues.append(tag+"entry");continue
		var ok_keys := true
		for key in OPENING_STEP_KEYS:
			if not s.has(key): ok_keys = false
		for key in s:
			if not key in OPENING_STEP_KEYS and key != "returning_max_ticks": ok_keys = false
		if not ok_keys: issues.append(tag+"keys");continue
		if not s.id is String or String(s.id).is_empty() or seen.has(s.id): issues.append(tag+"id")
		else: seen[s.id] = true
		if not integer(s.max_ticks,60,3600): issues.append(tag+"max_ticks")
		if s.has("returning_max_ticks") and not integer(s.returning_max_ticks,60,3600): issues.append(tag+"returning_max_ticks")
		if not integer(s.kills,0,200): issues.append(tag+"kills")
		if not integer(s.amount,0,30): issues.append(tag+"amount")
		if not integer(s.interval_ticks,12,600): issues.append(tag+"interval_ticks")
		if not integer(s.alive_cap,0,first_cap) or (int(s.get("alive_cap",0)) == 0 and integer(s.get("amount"),1,30)): issues.append(tag+"alive_cap")
		if not (s.ring_m is Array and s.ring_m.size() == 2 and number(s.ring_m[0],2.0,19.0) and number(s.ring_m[1],2.0,19.0) and float(s.ring_m[0]) <= float(s.ring_m[1])): issues.append(tag+"ring_m")
		issues.append_array(_opening_heading_issues(s.heading,index,tag))
		if not integer(s.speed_bps,3000,10000): issues.append(tag+"speed_bps")
		if s.acquire_m != null and not number(s.acquire_m,6.0,13.0): issues.append(tag+"acquire_m")
		if s.orb_pull_m != null and not number(s.orb_pull_m,2.0,20.0): issues.append(tag+"orb_pull_m")
		if s.crest != null and not (_fan_valid(s.crest,["at_ticks","count","arc_deg"]) and integer(s.crest.at_ticks,0,3600)): issues.append(tag+"crest")
		if not _mix_valid(s.mix): issues.append(tag+"mix")
		if not s.first_visit_only is bool: issues.append(tag+"first_visit_only")
	return issues

## heading: {arc_deg} plus how the direction is chosen: choices_deg (one of the listed world angles), same_as_previous,
## opposite_of_previous, or nothing at all (then the fan must be the full circle). The first step has no previous step.
static func _opening_heading_issues(h: Variant, index: int, tag: String) -> Array[String]:
	if not h is Dictionary or not h.has("arc_deg") or not number(h.arc_deg,1.0,360.0): return [tag+"heading"]
	var modes := 0
	for key in h:
		if not key in ["arc_deg","choices_deg","same_as_previous","opposite_of_previous"]: return [tag+"heading keys"]
		if key != "arc_deg": modes += 1
	if modes > 1: return [tag+"heading modes"]
	if h.has("choices_deg"):
		var c: Variant = h.choices_deg
		if not c is Array or c.size() < 1 or c.size() > 4: return [tag+"heading choices_deg"]
		for angle in c:
			if not number(angle,-180.0,180.0): return [tag+"heading choices_deg"]
	for key in ["same_as_previous","opposite_of_previous"]:
		if h.has(key) and (h[key] != true or index == 0): return [tag+"heading "+key]
	if modes == 0 and float(h.arc_deg) < 360.0: return [tag+"heading needs a direction or the full circle"]
	return []

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
	if not spawn is Dictionary: return ["spawn keys"]
	## Optional: the bodies standing at the start of a normal run (rhythm off). Absent = 12, the old start.
	var spawn_keys: Dictionary = (spawn as Dictionary).duplicate()
	if spawn_keys.has("initial_pack"):
		if not (spawn_keys.initial_pack is float or spawn_keys.initial_pack is int) or float(spawn_keys.initial_pack) != floor(float(spawn_keys.initial_pack)) or float(spawn_keys.initial_pack) < 0 or float(spawn_keys.initial_pack) > 40: return ["spawn initial_pack"]
		spawn_keys.erase("initial_pack")
	if not GrowthCatalog.keys_match(spawn_keys,["ring_min_m","ring_max_m","opening","zones","boss_phase","mix"]): return ["spawn keys"]
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
