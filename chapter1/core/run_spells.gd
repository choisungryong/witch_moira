extends RefCounted
## Loader and validator for chapter1/data/run_spells.json (D12 B0.8, G5): in-run spell roles, slots, axis cards,
## statuses, same-element detonation and pairs. With "enabled": false (or without the file) the core reads nothing of it.
## Pure data: no node, no profile I/O. The composed effect of a spell is built here (compose) so the validator and the
## run growth agree on one formula: base, then the reach overrides, then the damage axis multipliers.
const GrowthCatalog = preload("res://chapter1/core/growth_catalog.gd")
const DEFAULT_PATH := "res://chapter1/data/run_spells.json"
const ROOT_KEYS := ["schema_version","provenance","balance_status","enabled","slots","protect","axis","evolve","statuses","spells","pairs"]
const ELEMENTS := ["ember","frost","arc"]
const STATUS_IDS := ["heat","chill","shock"]
## The ring spell ids and their element. Roles are structure, not tuning numbers.
const RING_IDS := {"chapter1.skill.ember_ring":"ember","chapter1.skill.frost_ring":"frost","chapter1.skill.arc_ring":"arc"}
## Effect keys only a ring has (G5-3.1): distance falloff, the ring's own controls and the proportional hit on strong enemies.
## A key a ring's base does not name keeps the neutral value of effect_defaults().
const RING_LIMITS := {"ring_radius_cm":[0,800],"ring_pulses":[1,3],"ring_targets":[0,12],
	"near_cm":[0,800],"falloff_floor_bps":[1000,10000],"stagger_ticks":[0,180],"freeze_ticks":[0,240],"stun_ticks":[0,120],
	"strong_pct_bps":[0,3000],"strong_floor_bps":[0,9000]}
const SPELL_KEYS := ["role","element","applies","detonates","weight","base","reach"]
## vs_cc, prefer_cc_cm and the prefer_kind keys belong to a basic spell (I1, I0); a ring has none of them.
const SPELL_OPTIONAL := ["owner","prefer","vs_strong_bps","slow_ticks","vs_cc","prefer_cc_cm","prefer_kinds","prefer_kind_cm","prefer_when_clear_cm"]
const DETONATE_OPTIONAL := ["per_stack_bps","bonus_bps","consume","freeze_bonus","block_bps","block_targets"]
## The controls an interlock pair may name, and the enemy kinds I0 may aim at first.
const CC_CLASSES := ["frozen","stunned","staggered","slowed"]
const PREFER_KINDS := ["ranged","charger"]
## Optional top-level key: marks_resonance (the old mark bonus stays off while the composition is on unless this says true).
const ROOT_OPTIONAL := ["marks_resonance"]
## The catalog arc spell stuns on a direct hit by itself; no key in the document says so.
const ARC_ID := "chapter1.skill.arc"
var errors: Array[String] = []
var _document: Dictionary = {}

## Neutral values for the effect keys a spell's base does not name (structure, not tuning). Rings start from here.
static func effect_defaults() -> Dictionary:
	return {"damage_raw":1,"cooldown_ticks":60,"projectiles":0,"chain_targets":0,"branches":1,"pierce":0,"radius_cm":0,"slow_bps":0,
		"freeze_stacks":0,"shatter_count":0,"death_burst":0,"proc_depth":0,"hit_budget":1,"ring_radius_cm":0,"ring_pulses":1,"ring_targets":0,
		"near_cm":0,"falloff_floor_bps":10000,"stagger_ticks":0,"freeze_ticks":0,"stun_ticks":0,"strong_pct_bps":0,"strong_floor_bps":0}

static func _effect_key_ok(key: String, value: Variant) -> bool:
	if GrowthCatalog.LIMITS.has(key): return GrowthCatalog.integer(value,GrowthCatalog.LIMITS[key][0],GrowthCatalog.LIMITS[key][1])
	if RING_LIMITS.has(key):
		# ring_targets is 1..12 when written; absent means "up to the hit budget".
		var low: int = 1 if key == "ring_targets" else int(RING_LIMITS[key][0])
		return GrowthCatalog.integer(value,low,RING_LIMITS[key][1])
	return false

## The effect of one spell at the given axis levels. `start` is the catalog rank-1 effect for a basic spell
## (ignored for a ring, which starts from effect_defaults()). Integers only; no clamping beyond the floors below.
static func compose(doc: Dictionary, id_: String, damage_level: int, reach_level: int, start: Dictionary) -> Dictionary:
	var spell: Dictionary = doc.spells[id_]
	var effect: Dictionary = effect_defaults() if String(spell.role) == "ring" else start.duplicate(true)
	for key in spell.base: effect[key] = int(spell.base[key])
	var reach: Dictionary = spell.reach[reach_level]
	for key in reach: effect[key] = int(reach[key])
	var power: Dictionary = doc.axis.power
	effect.damage_raw = maxi(1,int(effect.damage_raw)*int(power.damage_bps[damage_level])/10000)
	effect.cooldown_ticks = maxi(1,int(effect.cooldown_ticks)*int(power.cooldown_bps[damage_level])/10000)
	return effect

## The pair id that links two different spells: a detonation pair first, then an interlock pair (either direction), then the
## element reaction pair. "" when they are not linked. Reaction pairs only link; their effect is the next work package.
static func pair_between(doc: Dictionary, x: String, y: String) -> String:
	if x == y or not doc.spells.has(x) or not doc.spells.has(y): return ""
	for kind in ["detonate","interlock"]:
		for pair in doc.pairs:
			if pair.kind == kind and ((pair.a == x and pair.b == y) or (pair.a == y and pair.b == x)): return String(pair.id)
	var ex: String = doc.spells[x].element
	var ey: String = doc.spells[y].element
	if ex == ey: return ""
	for pair in doc.pairs:
		if pair.kind == "reaction" and ((pair.elements[0] == ex and pair.elements[1] == ey) or (pair.elements[0] == ey and pair.elements[1] == ex)): return String(pair.id)
	return ""

## Validation. `skill_ids`: the catalog skills (all must appear as role "basic"). `owners`: {character_id: signature skill id}.
## `starts`: {skill id: catalog rank-1 effect} so every composed effect can be checked. Every problem is a short path.
static func validate(v: Variant, skill_ids: Array, owners: Dictionary, starts: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	if not v is Dictionary: return ["root keys"]
	var root_names: Array = ROOT_KEYS.duplicate()
	for optional in ROOT_OPTIONAL:
		if v.has(optional): root_names.append(optional)
	if not GrowthCatalog.keys_match(v,root_names): return ["root keys"]
	if v.has("marks_resonance") and not v.marks_resonance is bool: issues.append("marks_resonance")
	if not GrowthCatalog.integer(v.schema_version,1,1) or v.provenance != "independent_design" or not v.balance_status is String: issues.append("version/provenance")
	if not v.enabled is bool: issues.append("enabled")
	if not GrowthCatalog.integer(v.slots,1,4): issues.append("slots")
	if not v.protect is Dictionary or not GrowthCatalog.keys_match(v.protect,["ring_at_level","pair_open_levels","toward_evolve"]): issues.append("protect keys")
	else:
		if not GrowthCatalog.integer(v.protect.ring_at_level,2,12): issues.append("protect ring_at_level")
		if not v.protect.toward_evolve is bool: issues.append("protect toward_evolve")
		var levels: Variant = v.protect.pair_open_levels
		if not levels is Array or levels.size() > 11: issues.append("protect pair_open_levels")
		else:
			for level in levels:
				if not GrowthCatalog.integer(level,2,12): issues.append("protect pair_open_levels range");break
	var cap_axis := 0
	var cap_spell := 0
	var axis_ok := false
	if not v.axis is Dictionary or not GrowthCatalog.keys_match(v.axis,["cap_per_axis","cap_per_spell","power"]): issues.append("axis keys")
	elif not GrowthCatalog.integer(v.axis.cap_per_axis,1,8) or not GrowthCatalog.integer(v.axis.cap_per_spell,1,8) or int(v.axis.cap_per_axis) > int(v.axis.cap_per_spell): issues.append("axis caps")
	elif not v.axis.power is Dictionary or not GrowthCatalog.keys_match(v.axis.power,["damage_bps","cooldown_bps"]): issues.append("axis power keys")
	else:
		cap_axis = int(v.axis.cap_per_axis)
		cap_spell = int(v.axis.cap_per_spell)
		axis_ok = true
		for key in ["damage_bps","cooldown_bps"]:
			var list: Variant = v.axis.power[key]
			if not list is Array or list.size() != cap_axis+1: issues.append("axis power %s length" % key);axis_ok = false;continue
			for entry in list:
				if not GrowthCatalog.integer(entry,1000,60000): issues.append("axis power %s range" % key);axis_ok = false;break
			if axis_ok and int(list[0]) != 10000: issues.append("axis power %s first value" % key);axis_ok = false
	if not v.evolve is Dictionary or not GrowthCatalog.keys_match(v.evolve,["axis_sum","needs_passive","partner_axis_sum","partner_detonate_bps"]): issues.append("evolve keys")
	else:
		if not GrowthCatalog.integer(v.evolve.axis_sum,1,8) or (cap_spell > 0 and int(v.evolve.axis_sum) > cap_spell): issues.append("evolve axis_sum")
		if not v.evolve.needs_passive is bool: issues.append("evolve needs_passive")
		if not GrowthCatalog.integer(v.evolve.partner_axis_sum,0,8) or (cap_spell > 0 and int(v.evolve.partner_axis_sum) > cap_spell): issues.append("evolve partner_axis_sum")
		if not GrowthCatalog.integer(v.evolve.partner_detonate_bps,10000,60000): issues.append("evolve partner_detonate_bps")
	var statuses_ok := true
	if not v.statuses is Dictionary or v.statuses.is_empty(): issues.append("statuses");statuses_ok = false
	else:
		for status in v.statuses:
			var entry: Variant = v.statuses[status]
			if not status in STATUS_IDS or not entry is Dictionary: issues.append("status id " + str(status));statuses_ok = false;continue
			var keys_ok: bool = GrowthCatalog.keys_match(entry,["max","expire_ticks","freeze_at"] if status == "chill" and entry.has("freeze_at") else ["max","expire_ticks"])
			if not keys_ok: issues.append("status keys " + status);statuses_ok = false;continue
			if not GrowthCatalog.integer(entry.max,1,20) or not GrowthCatalog.integer(entry.expire_ticks,30,1800): issues.append("status range " + status);statuses_ok = false
			if entry.has("freeze_at") and not GrowthCatalog.integer(entry.freeze_at,1,20): issues.append("status freeze_at");statuses_ok = false
	if not v.spells is Dictionary or v.spells.is_empty(): issues.append("spells");return issues
	var spell_ok := {}
	for id_ in skill_ids:
		if not v.spells.has(id_): issues.append("spell missing " + str(id_))
	for id_ in v.spells:
		var spell: Variant = v.spells[id_]
		var problem := _spell_issue(String(id_),spell,v,skill_ids,owners,starts,cap_axis,statuses_ok)
		if not problem.is_empty(): issues.append(problem)
		else: spell_ok[id_] = true
	# A broken status table or axis block already has its issue; the pair and composition checks would read garbage.
	if not statuses_ok or not axis_ok: return issues
	issues.append_array(_pair_issues(v.pairs,v.spells,spell_ok,v.statuses))
	if issues.is_empty():
		# Every composed effect stays inside the catalog's limits (a basic spell also needs a projectile or a chain).
		for id_ in v.spells:
			var spell: Dictionary = v.spells[id_]
			if spell.role == "basic" and not starts.has(id_): issues.append("start effect missing " + str(id_));continue
			for d in cap_axis+1:
				for r in cap_axis+1:
					var effect := compose(v,String(id_),d,r,starts.get(id_,{}))
					for key in GrowthCatalog.LIMITS:
						if not GrowthCatalog.integer(effect.get(key,-1),GrowthCatalog.LIMITS[key][0],GrowthCatalog.LIMITS[key][1]): issues.append("composed %s %s %d/%d" % [id_,key,d,r])
					if spell.role == "basic" and int(effect.projectiles) <= 0 and int(effect.chain_targets) <= 0: issues.append("composed %s has no shot %d/%d" % [id_,d,r])
					if spell.role == "ring" and int(effect.ring_radius_cm) < 1: issues.append("composed %s has no radius %d/%d" % [id_,d,r])
					if spell.role == "ring" and int(effect.near_cm) > int(effect.ring_radius_cm): issues.append("composed %s near_cm beyond the radius %d/%d" % [id_,d,r])
					if issues.size() > 8: return issues
	return issues

static func _spell_issue(id_: String, s: Variant, doc: Dictionary, skill_ids: Array, owners: Dictionary, starts: Dictionary, cap_axis: int, statuses_ok: bool) -> String:
	var tag := "spell " + id_ + " "
	if not s is Dictionary: return tag + "entry"
	for key in SPELL_KEYS:
		if not s.has(key): return tag + "key " + key
	for key in s:
		if not key in SPELL_KEYS and not key in SPELL_OPTIONAL: return tag + "unknown key " + str(key)
	if not s.role is String or not s.role in ["basic","ring"]: return tag + "role"
	if s.role == "basic" and not id_ in skill_ids: return tag + "basic id is not a catalog skill"
	if s.role == "ring" and not RING_IDS.has(id_): return tag + "ring id"
	if not s.element is String or not s.element in ELEMENTS: return tag + "element"
	if s.role == "ring":
		if String(RING_IDS[id_]) != s.element: return tag + "ring element"
		if not s.has("owner") or not s.owner is String or not owners.has(s.owner): return tag + "owner"
		if not owners.has(s.owner) or String(owners[s.owner]).get_slice(".",2) != s.element: return tag + "owner element"
	elif s.has("owner"): return tag + "owner on a basic spell"
	elif String(id_).get_slice(".",2) != s.element: return tag + "basic element"
	if not GrowthCatalog.integer(s.weight,1,10000): return tag + "weight"
	if s.has("vs_strong_bps") and not GrowthCatalog.integer(s.vs_strong_bps,0,10000): return tag + "vs_strong_bps"
	if s.has("slow_ticks") and not GrowthCatalog.integer(s.slow_ticks,6,600): return tag + "slow_ticks"
	var aim_issue := _aim_issue(s,tag)
	if not aim_issue.is_empty(): return aim_issue
	if not statuses_ok: return ""
	if s.has("prefer") and (not s.prefer is String or not doc.statuses.has(s.prefer)): return tag + "prefer"
	if not s.applies is Dictionary: return tag + "applies"
	for status in s.applies:
		if not doc.statuses.has(status) or not GrowthCatalog.integer(s.applies[status],1,20): return tag + "applies " + str(status)
	if not s.detonates is Dictionary: return tag + "detonates"
	for status in s.detonates:
		var rule: Variant = s.detonates[status]
		if not doc.statuses.has(status) or not rule is Dictionary: return tag + "detonates " + str(status)
		for key in rule:
			if not key in DETONATE_OPTIONAL: return tag + "detonates key " + str(key)
		if not rule.has("consume") or not rule.consume is bool: return tag + "detonates consume"
		# Exactly one of the two multipliers.
		if rule.has("per_stack_bps") == rule.has("bonus_bps"): return tag + "detonates multiplier"
		for key in ["per_stack_bps","bonus_bps"]:
			if rule.has(key) and not GrowthCatalog.integer(rule[key],1,100000): return tag + "detonates " + key
		if rule.has("freeze_bonus") and (status != "chill" or not GrowthCatalog.integer(rule.freeze_bonus,1,5)): return tag + "detonates freeze_bonus"
		# I2: block_bps lengthens this hit's freeze/stagger/stun, block_targets adds struck targets. Only a ring blocks,
		# and block_targets needs a ring that has a target count.
		if (rule.has("block_bps") or rule.has("block_targets")) and s.role != "ring": return tag + "detonates block on a basic spell"
		if rule.has("block_bps") and not GrowthCatalog.integer(rule.block_bps,10000,60000): return tag + "detonates block_bps"
		if rule.has("block_targets") and (not GrowthCatalog.integer(rule.block_targets,1,6) or not s.base is Dictionary or not s.base.has("ring_targets")): return tag + "detonates block_targets"
	if not s.base is Dictionary or s.base.is_empty(): return tag + "base"
	for key in s.base:
		if not _effect_key_ok(String(key),s.base[key]): return tag + "base " + str(key)
		if s.role == "basic" and RING_LIMITS.has(key): return tag + "ring key on a basic spell"
	if s.role == "ring":
		for key in ["damage_raw","cooldown_ticks","ring_radius_cm","hit_budget"]:
			if not s.base.has(key): return tag + "ring base needs " + key
	if cap_axis <= 0: return ""
	if not s.reach is Array or s.reach.size() != cap_axis+1: return tag + "reach length"
	for entry in s.reach:
		if not entry is Dictionary: return tag + "reach entry"
		for key in entry:
			if not _effect_key_ok(String(key),entry[key]): return tag + "reach " + str(key)
			if s.role == "basic" and RING_LIMITS.has(key): return tag + "ring key on a basic spell"
	return ""

## I1 (vs_cc, prefer_cc_cm) and I0 (prefer_kinds, prefer_kind_cm, prefer_when_clear_cm): keys of a basic spell only.
static func _aim_issue(s: Dictionary, tag: String) -> String:
	for key in ["vs_cc","prefer_cc_cm","prefer_kinds","prefer_kind_cm","prefer_when_clear_cm"]:
		if s.has(key) and s.role != "basic": return tag + key + " on a ring"
	if s.has("vs_cc"):
		if not s.vs_cc is Dictionary: return tag + "vs_cc"
		for cls in s.vs_cc:
			if not cls in CC_CLASSES or not GrowthCatalog.integer(s.vs_cc[cls],0,20000): return tag + "vs_cc " + str(cls)
	if s.has("prefer_cc_cm") and not GrowthCatalog.integer(s.prefer_cc_cm,0,1300): return tag + "prefer_cc_cm"
	if s.has("prefer_kind_cm") and not GrowthCatalog.integer(s.prefer_kind_cm,0,1300): return tag + "prefer_kind_cm"
	if s.has("prefer_when_clear_cm") and not GrowthCatalog.integer(s.prefer_when_clear_cm,0,400): return tag + "prefer_when_clear_cm"
	if s.has("prefer_kinds"):
		if not s.prefer_kinds is Array or s.prefer_kinds.size() > 2: return tag + "prefer_kinds"
		for kind in s.prefer_kinds:
			if not kind is String or not kind in PREFER_KINDS or s.prefer_kinds.count(kind) > 1: return tag + "prefer_kinds"
	return ""

## True when the spell puts the control `cls` on an enemy (read from its base and reach entries and its statuses).
static func controls(spell: Dictionary, id_: String, cls: String, statuses: Dictionary) -> bool:
	var layers: Array = [spell.base]
	layers.append_array(spell.reach)
	for layer in layers:
		match cls:
			"frozen":
				if int(layer.get("freeze_ticks",0)) > 0: return true
			"staggered":
				if int(layer.get("stagger_ticks",0)) > 0: return true
			"stunned":
				if int(layer.get("stun_ticks",0)) > 0: return true
			"slowed":
				if int(layer.get("slow_bps",0)) >= 2000: return true
	if cls == "stunned" and id_ == ARC_ID: return true
	# The chill status freezes at its threshold.
	if cls == "frozen" and spell.applies.has("chill") and statuses.get("chill",{}).has("freeze_at"): return true
	return false

static func _pair_issues(pairs: Variant, spells: Dictionary, spell_ok: Dictionary, statuses: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	if not pairs is Array or pairs.is_empty(): return ["pairs"]
	var seen := {}
	for index in pairs.size():
		var p: Variant = pairs[index]
		var tag := "pair %d " % index
		if not p is Dictionary or not p.get("id") is String or String(p.id).is_empty() or seen.has(p.id): issues.append(tag + "id");continue
		seen[p.id] = true
		tag = "pair " + String(p.id) + " "
		if p.get("kind") == "detonate":
			if not GrowthCatalog.keys_match(p,["id","kind","a","b","status"]): issues.append(tag + "keys");continue
			if not p.a is String or not p.b is String or not spell_ok.has(p.a) or not spell_ok.has(p.b) or p.a == p.b: issues.append(tag + "spells");continue
			if not p.status is String or not p.status in STATUS_IDS: issues.append(tag + "status");continue
			if not spells[p.a].applies.has(p.status): issues.append(tag + "a does not apply the status");continue
			if not spells[p.b].detonates.has(p.status): issues.append(tag + "b does not detonate the status")
		elif p.get("kind") == "interlock":
			# a puts the control on, b finishes the controlled enemy harder (vs_cc). Which spell is the ring is not decided here.
			if not GrowthCatalog.keys_match(p,["id","kind","a","b","via"]): issues.append(tag + "keys");continue
			if not p.a is String or not p.b is String or not spell_ok.has(p.a) or not spell_ok.has(p.b) or p.a == p.b: issues.append(tag + "spells");continue
			if not p.via is Array or p.via.is_empty() or p.via.size() > CC_CLASSES.size(): issues.append(tag + "via");continue
			for cls in p.via:
				if not cls is String or not cls in CC_CLASSES or p.via.count(cls) > 1: issues.append(tag + "via class");break
				if not controls(spells[p.a],String(p.a),cls,statuses): issues.append(tag + "a does not put " + cls + " on an enemy");break
				if int(spells[p.b].get("vs_cc",{}).get(cls,0)) <= 0: issues.append(tag + "b has no vs_cc for " + cls);break
		elif p.get("kind") == "reaction":
			# The reaction ids belong to the next work package; only the shape is checked here.
			if not GrowthCatalog.keys_match(p,["id","kind","elements","reaction"]): issues.append(tag + "keys");continue
			var elements: Variant = p.elements
			if not elements is Array or elements.size() != 2 or elements[0] == elements[1] or not elements[0] in ELEMENTS or not elements[1] in ELEMENTS: issues.append(tag + "elements");continue
			if not p.reaction is String or not String(p.reaction).begins_with("react."): issues.append(tag + "reaction")
		else: issues.append(tag + "kind")
	return issues

## Integral floats (what JSON parsing gives) become ints; everything else is copied as it is.
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

func load_file(path: String, skill_ids: Array, owners: Dictionary, starts: Dictionary) -> bool:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		errors.assign(["Cannot read run spells: "+path])
		return false
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		errors.assign(["Run spells JSON line %d: %s" % [parser.get_error_line(),parser.get_error_message()]])
		return false
	return replace_document(parser.data,skill_ids,owners,starts)

func replace_document(candidate: Variant, skill_ids: Array, owners: Dictionary, starts: Dictionary) -> bool:
	var issues := validate(candidate,skill_ids,owners,starts)
	if not issues.is_empty():
		errors = issues
		return false
	errors.clear()
	_document = normalize(candidate)
	return true

func snapshot() -> Dictionary:
	return _document.duplicate(true)
