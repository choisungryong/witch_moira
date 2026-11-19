extends RefCounted
## Loader and validator for chapter1/data/descent.json (D15 A, the ultimate "descent"): gauge points, cost per use, reach,
## the share a strong enemy takes, and the three element shapes. With "enabled": false (or without the file) the core reads
## nothing of it. Pure data: no node, no profile I/O. Every number lives in the file; the ids below are structure.
const GrowthCatalog = preload("res://chapter1/core/growth_catalog.gd")
const DEFAULT_PATH := "res://chapter1/data/descent.json"
const ROOT_KEYS := ["schema_version","provenance","balance_status","enabled","cost","points","reach_m","normal","strong","after","elements","blocked_phases","crown"]
const ELEMENTS := ["ember","frost","arc"]
## Beat ids the kill points may name: the rhythm beats of combat_tuning.json plus its trial and boss.
const BEAT_IDS := ["gi","seung1","seung2","jeon_a","trial","boss"]
const POINT_KEYS := ["kill_by_beat","kill_default","elite_kill","champion_kill","strong_damage_per_pct","vs_cc_hit","detonate","combo_cap_per_tick","marks_refund_per_stack","marks_refund_cap"]
const PHASES := ["trial","boss"]
var errors: Array[String] = []
var _document: Dictionary = {}

static func _number(v: Variant, low: float, high: float) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and float(v) >= low and float(v) <= high

static func _int(v: Variant, low: int, high: int) -> bool:
	return GrowthCatalog.integer(v,low,high)

static func _keys(v: Variant, names: Array) -> bool:
	return v is Dictionary and GrowthCatalog.keys_match(v,names)

## Every problem found, as short paths. Empty means the document is usable.
static func validate(v: Variant) -> Array[String]:
	var issues: Array[String] = []
	if not _keys(v,ROOT_KEYS): return ["descent root keys"]
	if not _int(v.schema_version,1,1) or v.provenance != "independent_design": issues.append("descent version/provenance")
	if not v.balance_status is String or String(v.balance_status).is_empty(): issues.append("descent balance_status")
	if not v.enabled is bool: issues.append("descent enabled")
	if not v.cost is Array or v.cost.size() < 1 or v.cost.size() > 6: issues.append("descent cost size")
	else:
		for amount in v.cost:
			if not _int(amount,1000,30000): issues.append("descent cost range");break
	issues.append_array(_points_issues(v.points))
	if not _number(v.reach_m,6.0,19.0): issues.append("descent reach_m")
	if not _keys(v.normal,["trial_kill_cap"]) or not _int(v.normal.trial_kill_cap,0,180): issues.append("descent normal")
	var s: Variant = v.strong
	if not _keys(s,["elite_bps","champion_bps","boss_bps","per_mark_bps","marks_cap_bps","cut_windup_ticks"]): issues.append("descent strong keys")
	else:
		for key in ["elite_bps","champion_bps","boss_bps","per_mark_bps","marks_cap_bps"]:
			if not _int(s[key],0,10000): issues.append("descent strong "+key)
		if not _int(s.cut_windup_ticks,1,600): issues.append("descent strong cut_windup_ticks")
	var a: Variant = v.after
	if not _keys(a,["iframe_ticks","spawn_pause_ticks"]) or not _int(a.iframe_ticks,0,600) or not _int(a.spawn_pause_ticks,0,600): issues.append("descent after")
	issues.append_array(_element_issues(v.elements))
	if not v.blocked_phases is Array or v.blocked_phases.size() > PHASES.size(): issues.append("descent blocked_phases")
	else:
		for phase in v.blocked_phases:
			if not phase is String or not phase in PHASES: issues.append("descent blocked_phases word");break
	var c: Variant = v.crown
	if not _keys(c,["charge_bps","power_bps","reach_add_m"]): issues.append("descent crown keys")
	else:
		if not c.charge_bps is Array or c.charge_bps.size() != 3: issues.append("descent crown charge_bps")
		else:
			for bps in c.charge_bps:
				if not _int(bps,0,10000): issues.append("descent crown charge_bps range");break
		if not _int(c.power_bps,10000,20000) or not _number(c.reach_add_m,0.0,6.0): issues.append("descent crown power/reach")
	return issues

static func _points_issues(p: Variant) -> Array[String]:
	if not _keys(p,POINT_KEYS): return ["descent points keys"]
	var issues: Array[String] = []
	for key in POINT_KEYS:
		if key != "kill_by_beat" and not _int(p[key],0,2000): issues.append("descent points "+key)
	var by_beat: Variant = p.kill_by_beat
	if not by_beat is Dictionary or by_beat.is_empty(): issues.append("descent points kill_by_beat")
	else:
		for id_ in by_beat:
			if not id_ in BEAT_IDS or not _int(by_beat[id_],0,2000): issues.append("descent points kill_by_beat "+str(id_))
	return issues

static func _element_issues(e: Variant) -> Array[String]:
	if not _keys(e,ELEMENTS): return ["descent elements keys"]
	var issues: Array[String] = []
	var ember: Variant = e.ember
	if not _keys(ember,["sweep_ticks","heading_deg","burn_ticks","burn_every_ticks","burn_heat"]): issues.append("descent ember keys")
	elif not _int(ember.sweep_ticks,1,600) or not _number(ember.heading_deg,-180.0,180.0) or not _int(ember.burn_ticks,1,600) or not _int(ember.burn_every_ticks,1,600) or not _int(ember.burn_heat,0,6): issues.append("descent ember range")
	var frost: Variant = e.frost
	if not _keys(frost,["sweep_ticks","break_at_ticks","normal_after_freeze_ticks","strong_freeze_ticks"]): issues.append("descent frost keys")
	elif not _int(frost.sweep_ticks,1,600) or not _int(frost.break_at_ticks,1,600) or int(frost.break_at_ticks) > int(frost.sweep_ticks) or not _int(frost.normal_after_freeze_ticks,1,600) or not _int(frost.strong_freeze_ticks,1,600): issues.append("descent frost range")
	var arc: Variant = e.arc
	if not _keys(arc,["sweep_ticks","round_ticks","per_round","spread_m","spread_count","normal_stun_ticks","strong_stun_ticks"]): issues.append("descent arc keys")
	elif not _int(arc.sweep_ticks,1,600) or not _int(arc.round_ticks,1,600) or int(arc.round_ticks) > int(arc.sweep_ticks) or not _int(arc.per_round,1,64) or not _number(arc.spread_m,0.0,13.0) or not _int(arc.spread_count,0,8) or not _int(arc.normal_stun_ticks,1,600) or not _int(arc.strong_stun_ticks,1,600): issues.append("descent arc range")
	return issues

## Whole numbers become ints; every reader casts the metre and degree values it needs back to float.
static func normalize(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key in value: out[key] = normalize(value[key])
		return out
	if value is Array:
		var list := []
		for item in value: list.append(normalize(item))
		return list
	if value is float and is_finite(value) and value == floor(value): return int(value)
	return value

func load_file(path: String = DEFAULT_PATH) -> bool:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		errors.assign(["Cannot read descent: "+path])
		return false
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		errors.assign(["Descent JSON line %d: %s" % [parser.get_error_line(),parser.get_error_message()]])
		return false
	return replace_document(parser.data)

func replace_document(candidate: Variant) -> bool:
	var issues := validate(candidate)
	if not issues.is_empty():
		errors = issues
		return false
	errors.clear()
	_document = normalize(candidate)
	return true

func snapshot() -> Dictionary:
	return _document.duplicate(true)
