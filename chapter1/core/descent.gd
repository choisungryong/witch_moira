extends RefCounted
## Loader and validator for chapter1/data/descent.json (D15 A + D24 schema 2, the ultimate "descent"): gauge points, cost per use,
## the screen rectangle it covers, the share a strong enemy takes, and the three ultimates (ember fragments, frost storm, arc bolts). With "enabled": false (or without the file) the core reads
## nothing of it. Pure data: no node, no profile I/O. Every number lives in the file; the ids below are structure.
const GrowthCatalog = preload("res://chapter1/core/growth_catalog.gd")
const DEFAULT_PATH := "res://chapter1/data/descent.json"
const ROOT_KEYS := ["schema_version","provenance","balance_status","enabled","cost","points","area","normal","strong","after","hold_bonus","cue","ultimates","blocked_phases","crown"]
const ELEMENTS := ["ember","frost","arc"]
## Beat ids the kill points may name: the rhythm beats of combat_tuning.json plus its trial and boss.
const BEAT_IDS := ["gi","seung1","seung2","jeon_a","trial","boss"]
const POINT_KEYS := ["kill_by_beat","kill_default","elite_kill","champion_kill","strong_damage_per_pct","vs_cc_hit","detonate","kit_detonate","combo_cap_per_tick","marks_refund_per_stack","marks_refund_cap"]
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
	if not _int(v.schema_version,2,2) or v.provenance != "independent_design": issues.append("descent version/provenance")
	if not v.balance_status is String or String(v.balance_status).is_empty(): issues.append("descent balance_status")
	if not v.enabled is bool: issues.append("descent enabled")
	if not v.cost is Array or v.cost.size() < 1 or v.cost.size() > 6: issues.append("descent cost size")
	else:
		for amount in v.cost:
			if not _int(amount,1000,30000): issues.append("descent cost range");break
	issues.append_array(_points_issues(v.points))
	var area: Variant = v.area
	if not _keys(area,["shape","right_deg","half_w_m","half_h_m","edge_m"]) or area.shape != "screen": issues.append("descent area keys")
	elif not _number(area.right_deg,-180.0,180.0) or not _number(area.half_w_m,6.0,30.0) or not _number(area.half_h_m,6.0,30.0) or not _number(area.edge_m,0.0,4.0): issues.append("descent area range")
	if not _keys(v.normal,["trial_kill_cap"]) or not _int(v.normal.trial_kill_cap,0,400): issues.append("descent normal")
	var s: Variant = v.strong
	if not _keys(s,["elite_bps","champion_bps","boss_bps","per_mark_bps","marks_cap_bps","cut_windup_ticks","champion_stun_ticks","boss_stagger_ticks","boss_cap_bps"]): issues.append("descent strong keys")
	else:
		for key in ["elite_bps","champion_bps","boss_bps","per_mark_bps","marks_cap_bps"]:
			if not _int(s[key],0,10000): issues.append("descent strong "+key)
		for key in ["cut_windup_ticks","champion_stun_ticks","boss_stagger_ticks"]:
			if not _int(s[key],1 if key=="cut_windup_ticks" else 0,600): issues.append("descent strong "+key)
		if not _int(s.boss_cap_bps,0,10000) or (_int(s.boss_bps,0,10000) and int(s.boss_cap_bps) < int(s.boss_bps)): issues.append("descent strong boss_cap_bps")
	var a: Variant = v.after
	if not _keys(a,["iframe_ticks","spawn_pause_ticks","sweep_spawn_bps"]) or not _int(a.iframe_ticks,0,600) or not _int(a.spawn_pause_ticks,0,600) or not _int(a.sweep_spawn_bps,0,30000): issues.append("descent after")
	var hb: Variant = v.hold_bonus
	if not _keys(hb,["per_points","step_bps","max_bps","cap_points"]) or not _int(hb.per_points,1,100000) or not _int(hb.step_bps,0,10000) or not _int(hb.max_bps,0,10000) or not _int(hb.cap_points,0,1000000): issues.append("descent hold_bonus")
	var cue: Variant = v.cue
	if not _keys(cue,["normals_min","crest_ticks"]) or not _int(cue.normals_min,0,500) or not _int(cue.crest_ticks,0,3600): issues.append("descent cue")
	issues.append_array(_ultimate_issues(v.ultimates))
	if not v.blocked_phases is Array or v.blocked_phases.size() > PHASES.size(): issues.append("descent blocked_phases")
	else:
		for phase in v.blocked_phases:
			if not phase is String or not phase in PHASES: issues.append("descent blocked_phases word");break
	var c: Variant = v.crown
	if not _keys(c,["charge_bps","power_bps"]): issues.append("descent crown keys")
	else:
		if not c.charge_bps is Array or c.charge_bps.size() != 3: issues.append("descent crown charge_bps")
		else:
			for bps in c.charge_bps:
				if not _int(bps,0,10000): issues.append("descent crown charge_bps range");break
		if not _int(c.power_bps,10000,20000): issues.append("descent crown power")
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

static func _pair(v: Variant, low: int, high: int) -> bool:
	return v is Array and v.size() == 2 and _int(v[0],low,high) and _int(v[1],low,high) and int(v[0]) <= int(v[1])

static func _ultimate_issues(e: Variant) -> Array[String]:
	if not _keys(e,ELEMENTS): return ["descent ultimates keys"]
	var issues: Array[String] = []
	var ember: Variant = e.ember
	if not _keys(ember,["sweep_ticks","grid","aimed","big_count","big_radius_m","small_radius_m","first_land_step","gap_ticks","last_land_step","first_hit_share_bps","next_hit_share_bps","burn_ticks","burn_every_ticks","burn_heat"]): issues.append("descent ember keys")
	else:
		var grid_ok: bool = ember.grid is Array and ember.grid.size() == 2 and _int(ember.grid[0],1,8) and _int(ember.grid[1],1,8)
		var pieces: int = int(ember.grid[0])*int(ember.grid[1])+int(ember.aimed) if grid_ok and _int(ember.aimed,0,4) else 0
		if not grid_ok or not _int(ember.aimed,0,4) or pieces < 1 or pieces > 32 or not _int(ember.big_count,int(ember.aimed),maxi(int(ember.aimed),pieces)): issues.append("descent ember pieces")
		elif not _int(ember.sweep_ticks,1,600) or not _number(ember.big_radius_m,0.5,12.0) or not _number(ember.small_radius_m,0.5,12.0) or not _pair(ember.gap_ticks,0,120) or not _int(ember.first_land_step,1,600) or not _int(ember.last_land_step,1,600) or int(ember.first_land_step) >= int(ember.last_land_step) or int(ember.last_land_step) > int(ember.sweep_ticks) or not _int(ember.first_hit_share_bps,0,10000) or not _int(ember.next_hit_share_bps,0,10000) or not _int(ember.burn_ticks,1,600) or not _int(ember.burn_every_ticks,1,600) or not _int(ember.burn_heat,0,6): issues.append("descent ember range")
	var frost: Variant = e.frost
	if not _keys(frost,["sweep_ticks","onset_step","pulse_from_step","pulse_every_ticks","pulse_count","pulse_share_bps","strong_freeze_ticks","after_freeze_ticks","ground_ticks","ground_chill","ground_slow_bps"]): issues.append("descent frost keys")
	elif not _int(frost.sweep_ticks,1,600) or not _int(frost.onset_step,1,600) or not _int(frost.pulse_from_step,1,600) or not _int(frost.pulse_every_ticks,1,600) or not _int(frost.pulse_count,0,32) or not _int(frost.pulse_share_bps,0,10000) or not _int(frost.strong_freeze_ticks,1,600) or not _int(frost.after_freeze_ticks,0,600) or not _int(frost.ground_ticks,1,600) or not _int(frost.ground_chill,0,6) or not _int(frost.ground_slow_bps,0,8500): issues.append("descent frost range")
	elif int(frost.onset_step) >= int(frost.pulse_from_step) or int(frost.pulse_from_step)+int(frost.pulse_every_ticks)*(maxi(1,int(frost.pulse_count))-1) >= int(frost.sweep_ticks) or int(frost.pulse_share_bps)*int(frost.pulse_count) > 10000: issues.append("descent frost order")
	var arc: Variant = e.arc
	if not _keys(arc,["sweep_ticks","bolts","first_step","gap_ticks","last_step","min_apart_m","retries","snap_m","splash_m","forks","fork_m","touch_share_bps","normal_stun_ticks","strong_stun_ticks"]): issues.append("descent arc keys")
	elif not _int(arc.sweep_ticks,1,600) or not _int(arc.bolts,1,64) or not _int(arc.first_step,1,600) or not _int(arc.last_step,1,600) or not _pair(arc.gap_ticks,0,120) or not _number(arc.min_apart_m,0.0,30.0) or not _int(arc.retries,0,16) or not _number(arc.snap_m,0.0,13.0) or not _number(arc.splash_m,0.1,13.0) or not _int(arc.forks,0,8) or not _number(arc.fork_m,0.0,13.0) or not _int(arc.touch_share_bps,0,10000) or not _int(arc.normal_stun_ticks,1,600) or not _int(arc.strong_stun_ticks,1,600): issues.append("descent arc range")
	elif int(arc.first_step) >= int(arc.last_step) or int(arc.last_step) > int(arc.sweep_ticks): issues.append("descent arc order")
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
