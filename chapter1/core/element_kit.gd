extends RefCounted
## Loader and validator for the element kit (D-element-trees, ET-A): chapter1/data/element_kit.json (in-run stack / lay / burst skills,
## cards, offer rules, the switch) and chapter1/data/element_trees.json (permanent trees whose nodes open cards).
## Pure data, no node, no profile I/O. Nothing here knows an element by name beyond the ELEMENTS list: every rule reads the document.
## With "enabled": false (the shipped value) or without the file, nothing of it reaches the core (no random number, no snapshot key).
const GrowthCatalog = preload("res://chapter1/core/growth_catalog.gd")
const RunSpells = preload("res://chapter1/core/run_spells.gd")
const SkillTree = preload("res://chapter1/core/skill_tree.gd")
const DEFAULT_PATH := "res://chapter1/data/element_kit.json"
const TREES_PATH := "res://chapter1/data/element_trees.json"
const ROOT_KEYS := ["schema_version","provenance","balance_status","enabled","enabled_elements","offer","fillers","elements"]
const ELEMENTS := ["ember","frost","arc"]
const KINDS := ["unlock","rank","rune","evolve","variant","survival","filler"]
const ANSWERS := ["crowd","big","survival"]
const ROLES := ["stack","lay","burst"]
## Structure, not tuning: the keys a card's change may touch (value range = how far a card may push it) and the rule flags it may raise.
const VAL_KEYS := {"bolts_add":[0,4],"lone_rebounds":[0,3],"branches":[0,2],"rod_count":[0,2],"rod_target_bps":[0,20000],"max_big":[0,20],
	"overload_cd_bps":[-9000,20000],"overload_max_bolts":[-8,8],"overload_bolt_bps":[0,20000],"self_bolt_bps":[0,20000],"hp_max":[0,100],"move_bps":[0,3000]}
const FLAG_KEYS := ["chain_on_death","discharge_ring","conductor_pop","storm_rod","static_shell","bolt_heal","stride_shock"]
## Per role: the skill keys a document may set (in the base and in a rank entry).
const SKILL_KEYS := {"lay":["cooldown_ticks","damage_raw","rod_ticks","keep_radius_cm"],
	"burst":["cooldown_ticks","reach_cm","bolt_raw","max_bolts","self_bolt_bps","bolt_bps"]}
const STATUS_KEYS := ["id","max","max_big","expire_ticks"]
const ROD_KEYS := ["ticks","range_cm","count","keep_radius_cm","death_spark_raw"]
const CHAIN_KEYS := ["big_rehit","lone_rebounds","rebound_bps"]
const PARAM_NAMES := ["shell","discharge","pop","bolt_heal","stride","death_chain"]
const WEIGHT_KINDS := ["unlock","rank","variant","rune","evolve","survival"]
const FILLER_EFFECT_KEYS := ["heal_bps","potion","heal_bps_if_full"]
const TREE_NODE_KINDS := ["card","rule","stat"]
const RULE_KEYS := ["grace_rerolls"]
var errors: Array[String] = []
var _document: Dictionary = {}

# ---------------------------------------------------------------- the shared documents (read once per process, or parked by a tool)

static var _shared: Dictionary = {}
static var _shared_loaded := false
static var _override: Dictionary = {}
static var _has_override := false

## The kit document in force: the parked one (tools and tests), else the shipped file. {} when there is none or it is unreadable.
static func current() -> Dictionary:
	if _has_override: return _override
	if not _shared_loaded:
		_shared_loaded = true
		if FileAccess.file_exists(DEFAULT_PATH):
			var loader = _make()
			if loader.load_file(DEFAULT_PATH): _shared = loader.snapshot()
			else: push_error("Element kit failed to load: " + str(loader.errors))
	return _shared

## Park a validated kit document for this process (tools and tests; `use_override({})` removes it). False and nothing changed when refused.
static func use_override(doc: Variant) -> bool:
	if doc is Dictionary and doc.is_empty():
		_override = {};_has_override = false;return true
	var loader = _make()
	if not loader.replace_document(doc): return false
	_override = loader.snapshot();_has_override = true
	return true

static func enabled_elements(doc: Dictionary = {}) -> Array:
	var d: Dictionary = doc if not doc.is_empty() else current()
	if d.is_empty() or not bool(d.get("enabled",false)): return []
	return d.enabled_elements.duplicate()

static func element_of_skill(skill_id: String) -> String:
	return skill_id.get_slice(".",2)

## True when a run of this signature skill uses the kit in `doc`.
static func is_on_for(primary: String, doc: Dictionary = {}) -> bool:
	return element_of_skill(primary) in enabled_elements(doc)

static func is_element_tree(tree: Dictionary) -> bool:
	return tree.has("element")

# ---------------------------------------------------------------- validation

static func _make() -> RefCounted:
	return load("res://chapter1/core/element_kit.gd").new()

static func _int(v: Variant, low: int, high: int) -> bool:
	return GrowthCatalog.integer(v,low,high)

static func _keys_ok(d: Variant, required: Array, optional: Array = []) -> bool:
	if not d is Dictionary: return false
	for key in required:
		if not d.has(key): return false
	for key in d:
		if not key in required and not key in optional: return false
	return true

static func validate(v: Variant) -> Array[String]:
	var issues: Array[String] = []
	if not v is Dictionary or not GrowthCatalog.keys_match(v,ROOT_KEYS): return ["root keys"]
	if not _int(v.schema_version,1,1) or v.provenance != "independent_design" or not v.balance_status is String: issues.append("version/provenance")
	if not v.enabled is bool: issues.append("enabled")
	var elements: Variant = v.elements
	if not elements is Dictionary or elements.is_empty(): issues.append("elements");return issues
	if not v.enabled_elements is Array or v.enabled_elements.size() > ELEMENTS.size(): issues.append("enabled_elements");return issues
	for el in v.enabled_elements:
		if not el is String or not el in ELEMENTS or v.enabled_elements.count(el) > 1 or not elements.has(el): issues.append("enabled_elements entry " + str(el))
	if bool(v.enabled) and v.enabled_elements.is_empty(): issues.append("enabled without an element")
	var filler_ids := _fillers_issues(v.fillers,issues)
	_offer_issues(v.offer,filler_ids,issues)
	for el in elements:
		if not el in ELEMENTS: issues.append("element " + str(el));continue
		_element_issues(String(el),elements[el],filler_ids,v.offer.get("gates",{}) if v.offer is Dictionary and v.offer.get("gates") is Dictionary else {},issues)
		if issues.size() > 12: return issues
	return issues

static func _fillers_issues(f: Variant, issues: Array[String]) -> Array:
	var ids: Array = []
	if not f is Dictionary or f.is_empty(): issues.append("fillers");return ids
	for id_ in f:
		var entry: Variant = f[id_]
		if not id_ is String or not _keys_ok(entry,["kind","answers","effect"]) or entry.kind != "filler" or not _answers_ok(entry.answers) or not entry.effect is Dictionary or entry.effect.is_empty():
			issues.append("filler " + str(id_));continue
		for key in entry.effect:
			if not key in FILLER_EFFECT_KEYS or not _int(entry.effect[key],0,10000): issues.append("filler effect " + str(id_) + " " + str(key))
		ids.append(String(id_))
	return ids

static func _answers_ok(a: Variant) -> bool:
	if not a is Array or a.is_empty() or a.size() > ANSWERS.size(): return false
	for x in a:
		if not x is String or not x in ANSWERS or a.count(x) > 1: return false
	return true

static func _offer_issues(o: Variant, filler_ids: Array, issues: Array[String]) -> void:
	if not _keys_ok(o,["cards","final_cards","protect_primary","final_protect","weights","gates","filler"]): issues.append("offer keys");return
	if not _int(o.cards,2,5) or not _int(o.final_cards,2,6) or not o.protect_primary is bool: issues.append("offer numbers")
	if not o.final_protect is Array or o.final_protect.size() > 4: issues.append("offer final_protect")
	else:
		for word in o.final_protect:
			if not word is String or not (word == "evolve" or (word.begins_with("answers:") and word.trim_prefix("answers:") in ANSWERS)): issues.append("offer final_protect word " + str(word))
	if not _keys_ok(o.weights,WEIGHT_KINDS): issues.append("offer weights")
	else:
		for kind in WEIGHT_KINDS:
			if not _int(o.weights[kind],1,10000): issues.append("offer weight " + kind)
	if not o.gates is Dictionary: issues.append("offer gates")
	else:
		for gate in o.gates:
			if not gate is String or not _keys_ok(o.gates[gate],["after_picks"]) or not _int(o.gates[gate].after_picks,0,40): issues.append("offer gate " + str(gate))
	if not o.filler is Array or o.filler.size() > 4: issues.append("offer filler")
	else:
		for id_ in o.filler:
			if not id_ is String or not id_ in filler_ids: issues.append("offer filler id " + str(id_))

static func _element_issues(el: String, e: Variant, filler_ids: Array, gates: Dictionary, issues: Array[String]) -> void:
	var tag := "element " + el + " "
	if not _keys_ok(e,["primary","status","rod","chain","skills","evolution","params","cards"]): issues.append(tag + "keys");return
	if not e.primary is String or element_of_skill(e.primary) != el: issues.append(tag + "primary");return
	if not _keys_ok(e.status,STATUS_KEYS) or not e.status.id is String or not _int(e.status.max,1,20) or not _int(e.status.max_big,1,40) or not _int(e.status.expire_ticks,30,1800) or int(e.status.max_big) < int(e.status.max):
		issues.append(tag + "status")
	if not _keys_ok(e.rod,ROD_KEYS): issues.append(tag + "rod keys")
	else:
		var limits := {"ticks":[30,3600],"range_cm":[200,3000],"count":[1,2],"keep_radius_cm":[100,2000],"death_spark_raw":[0,100000]}
		for key in ROD_KEYS:
			if not _int(e.rod[key],limits[key][0],limits[key][1]): issues.append(tag + "rod " + key)
	if not _keys_ok(e.chain,CHAIN_KEYS) or not _int(e.chain.big_rehit,1,4) or not _int(e.chain.lone_rebounds,0,3) or not _int(e.chain.rebound_bps,1000,20000): issues.append(tag + "chain")
	if not e.params is Dictionary: issues.append(tag + "params")
	else:
		for name in e.params:
			if not name in PARAM_NAMES or not e.params[name] is Dictionary: issues.append(tag + "param " + str(name));continue
			for key in e.params[name]:
				if not _int(e.params[name][key],0,1000000): issues.append(tag + "param value " + str(name) + "." + str(key))
	var skill_ids: Array = []
	if not e.skills is Dictionary: issues.append(tag + "skills");return
	for id_ in e.skills:
		var s: Variant = e.skills[id_]
		if not id_ is String or not String(id_).begins_with("chapter1.skill." + el + "_") or not s is Dictionary or not String(s.get("role","")) in ["lay","burst"] or not s.has("ranks") or not s.ranks is Array or s.ranks.is_empty() or s.ranks.size() > 4:
			issues.append(tag + "skill " + str(id_));continue
		var allowed: Array = SKILL_KEYS[s.role]
		for key in s:
			if key == "role" or key == "ranks": continue
			if not key in allowed or not _int(s[key],0,10000000): issues.append(tag + "skill key " + str(id_) + "." + str(key))
		for entry in s.ranks:
			if not entry is Dictionary: issues.append(tag + "skill rank entry " + str(id_));continue
			for key in entry:
				if not key in allowed or not _int(entry[key],0,10000000): issues.append(tag + "skill rank key " + str(id_) + "." + str(key))
		skill_ids.append(String(id_))
	var evo: Variant = e.evolution
	if not _keys_ok(evo,["skill","passive","storm"]) or evo.skill != e.primary or not evo.passive is String or not _keys_ok(evo.storm,["every_ticks","targets","damage_bps"]) \
			or not _int(evo.storm.every_ticks,6,600) or not _int(evo.storm.targets,1,6) or not _int(evo.storm.damage_bps,100,40000):
		issues.append(tag + "evolution");return
	_cards_issues(el,e,skill_ids,gates,issues)

static func _cards_issues(el: String, e: Dictionary, skill_ids: Array, gates: Dictionary, issues: Array[String]) -> void:
	var tag := "element " + el + " "
	if not e.cards is Array or e.cards.is_empty() or e.cards.size() > 64: issues.append(tag + "cards");return
	var seen := {}
	var rune_cards := 0
	var evolve_cards := 0
	for card in e.cards:
		if not card is Dictionary or not card.get("id") is String or String(card.id).is_empty() or seen.has(card.id): issues.append(tag + "card id");continue
		var t := tag + "card " + String(card.id) + " "
		for key in card:
			if not key in ["id","kind","skill","rank","gate","requires","excludes","change","answers","open"]: issues.append(t + "unknown key " + str(key))
		if not card.get("kind") is String or not card.kind in KINDS or card.kind == "filler": issues.append(t + "kind");seen[card.id] = true;continue
		if not _answers_ok(card.get("answers")): issues.append(t + "answers")
		if not card.get("open") is String or String(card.open).is_empty(): issues.append(t + "open")
		for list_key in ["requires","excludes"]:
			if not card.has(list_key): continue
			if not card[list_key] is Array or card[list_key].size() > 4: issues.append(t + list_key);continue
			for ref in card[list_key]:
				# A requirement must come earlier in the list (so no cycle); an exclusion may name a later card (the pair).
				if not ref is String or ref == card.id or (list_key == "requires" and not seen.has(ref)): issues.append(t + list_key + " " + str(ref))
		match card.kind:
			"unlock","rank":
				if not card.get("skill") is String or not (card.skill in skill_ids or (card.kind == "rank" and card.skill == e.primary)): issues.append(t + "skill")
				if card.kind == "rank" and not _int(card.get("rank"),2,4): issues.append(t + "rank")
				if card.kind == "unlock" and (not card.get("gate") is String or not gates.has(card.gate)): issues.append(t + "gate")
				if card.kind == "rank" and card.has("skill") and card.skill in skill_ids and int(card.get("rank",0)) > e.skills[card.skill].ranks.size(): issues.append(t + "rank beyond the skill's ranks")
			"rune": rune_cards += 1
			"evolve": evolve_cards += 1
			"variant","survival":
				var change: Variant = card.get("change")
				if not _keys_ok(change,[],["vals","flags"]) or change.is_empty(): issues.append(t + "change");continue
				var vals: Variant = change.get("vals",{})
				if not vals is Dictionary: issues.append(t + "change vals")
				else:
					for key in vals:
						if not VAL_KEYS.has(key) or not _int(vals[key],VAL_KEYS[key][0],VAL_KEYS[key][1]): issues.append(t + "change val " + str(key))
				var flags: Variant = change.get("flags",[])
				if not flags is Array: issues.append(t + "change flags")
				else:
					for flag in flags:
						if not flag is String or not flag in FLAG_KEYS: issues.append(t + "change flag " + str(flag))
		seen[card.id] = true
	if rune_cards != 1 or evolve_cards != 1: issues.append(tag + "needs exactly one rune and one evolve card")
	# An exclusion must be mutual and name a card of this element.
	for card in e.cards:
		for other in card.get("excludes",[]):
			var found := false
			for candidate in e.cards:
				if candidate.id == other and card.id in candidate.get("excludes",[]): found = true
			if not found: issues.append(tag + "exclusion not mutual " + String(card.id) + " " + str(other))

# ---------------------------------------------------------------- the permanent trees

## Issues of the trees document against a kit document and the progression characters. Same node rules as skill_tree.gd (tiers,
## branches, requires, reachability) but a node does not carry an effect block: kind "card" opens cards, "rule" sets a run option,
## "stat" is a place held for later and is refused today.
static func validate_trees(v: Variant, kit: Dictionary, progression: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	if not _keys_ok(v,["schema_version","provenance","balance_status","characters","trees"]) or not _int(v.schema_version,2,2) or v.provenance != "independent_design": return ["root keys"]
	if not v.characters is Array or not v.trees is Array or v.trees.is_empty(): return ["characters or trees"]
	var seen := {}
	for tree in v.trees:
		if not tree is Dictionary or not tree.get("tree_id") is String or seen.has(tree.tree_id): issues.append("tree id");continue
		seen[tree.tree_id] = true
		issues.append_array(_tree_issues(tree,kit,progression))
	var link_ok := {}
	for entry in v.characters:
		if not _keys_ok(entry,["id","element","tree_id"]) or not seen.has(entry.get("tree_id")): issues.append("characters entry");continue
		link_ok[entry.tree_id] = entry
	for tree in v.trees:
		if tree is Dictionary and seen.has(tree.get("tree_id")) and not link_ok.has(tree.tree_id): issues.append("tree without a characters entry " + String(tree.tree_id))
	return issues

static func _tree_issues(tree: Dictionary, kit: Dictionary, progression: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var id_ := String(tree.tree_id)
	for key in ["tree_id","character_id","signature_skill_id","element"]:
		if not tree.get(key) is String or String(tree[key]).is_empty(): out.append(id_ + " field " + key)
	if not _int(tree.get("revision"),1,1000000): out.append(id_ + " revision")
	if not out.is_empty(): return out
	var el := String(tree.element)
	if not el in ELEMENTS or not kit.get("elements",{}).has(el) or kit.elements[el].primary != tree.signature_skill_id: out.append(id_ + " element or signature skill");return out
	var entry := {}
	for c in progression.get("characters",[]):
		if c.id == tree.character_id: entry = c
	if entry.is_empty() or entry.signature_skill_id != tree.signature_skill_id: out.append(id_ + " character");return out
	var cap := int(progression.get("level_cap",0))
	var prefixes: Variant = tree.get("node_prefixes")
	if not prefixes is Array or prefixes.is_empty(): out.append(id_ + " node_prefixes");return out
	var tiers: Variant = tree.get("tiers")
	if not tiers is Array or tiers.is_empty() or tiers.size() > 8: out.append(id_ + " tiers");return out
	var last := 0
	for t in tiers:
		if not t is Dictionary or not t.get("name") is String or not _int(t.get("level"),1,1000000) or int(t.level) > cap or int(t.level) <= last: out.append(id_ + " tier");return out
		last = int(t.level)
	var branch_ids := {}
	if not tree.get("branches") is Array or tree.branches.is_empty(): out.append(id_ + " branches");return out
	for b in tree.branches:
		if not _keys_ok(b,["id","name","color"]) or branch_ids.has(b.id): out.append(id_ + " branch");return out
		branch_ids[b.id] = true
	if not tree.get("nodes") is Array or tree.nodes.is_empty() or tree.nodes.size() > SkillTree.MAX_NODES: out.append(id_ + " nodes");return out
	var cards_by_id := {}
	for card in kit.elements[el].cards: cards_by_id[card.id] = card
	var nodes := {}
	var opened := {}
	for node in tree.nodes:
		if not node is Dictionary or not node.get("id") is String or nodes.has(node.id): out.append(id_ + " node id");continue
		var nid := String(node.id)
		var owned := false
		for p in prefixes: owned = owned or nid.begins_with(String(p))
		if not owned: out.append(nid + " belongs to another tree")
		for key in node:
			if not key in ["id","kind","branch","tier","max_rank","requires","min_spent","opens","rule","name","lore"]: out.append(nid + " unknown key " + str(key))
		for key in ["name","lore"]:
			if not node.get(key) is String or String(node[key]).is_empty(): out.append(nid + " " + key)
		if not branch_ids.has(node.get("branch")) or not _int(node.get("tier"),1,tiers.size()) or not _int(node.get("max_rank"),1,1) or not node.get("requires") is Dictionary or not _int(node.get("min_spent"),0,6400):
			out.append(nid + " shape");continue
		var kind: Variant = node.get("kind")
		if not kind is String or not kind in TREE_NODE_KINDS: out.append(nid + " kind");continue
		if kind == "stat": out.append(nid + " stat nodes are not used yet");continue
		if kind == "card":
			if node.has("rule") or not node.get("opens") is Array or node.opens.is_empty() or node.opens.size() > 2: out.append(nid + " opens");continue
			for cid in node.opens:
				if not cards_by_id.has(cid) or cards_by_id[cid].open != nid or opened.has(cid): out.append(nid + " opens a card that does not name it, is base, or is opened twice " + str(cid))
				opened[cid] = nid
		else:
			if node.has("opens") or not _keys_ok(node.get("rule"),[],RULE_KEYS) or node.rule.is_empty(): out.append(nid + " rule");continue
			for key in node.rule:
				if not _int(node.rule[key],1,3): out.append(nid + " rule value " + str(key))
		nodes[nid] = node
	# Every card that names a node is opened by that node (and the node is in this tree).
	for cid in cards_by_id:
		var open: String = cards_by_id[cid].open
		if open != "base" and open.begins_with(String(prefixes[0])) and not opened.has(cid): out.append("card " + str(cid) + " names " + open + " but no node opens it")
	if not out.is_empty(): return out
	for nid in nodes:
		for parent_id in nodes[nid].requires:
			if not parent_id is String or parent_id == nid or not nodes.has(parent_id): out.append(nid + " requires " + str(parent_id));continue
			if not _int(nodes[nid].requires[parent_id],1,1) or int(nodes[parent_id].tier) >= int(nodes[nid].tier): out.append(nid + " requires " + str(parent_id) + " badly")
	if not out.is_empty(): return out
	var full := {}
	for nid in nodes: full[nid] = 1
	if not SkillTree.reachable_(nodes,full): out.append(id_ + " the full tree cannot be built")
	return out

## The cards a build of this element tree opens and the run options its rule nodes set. {"cards": [card ids], "rules": {key: int}}.
static func compile_tree(tree: Dictionary, ranks: Dictionary) -> Dictionary:
	var cards: Array = []
	var rules := {}
	for node in tree.nodes:
		if int(ranks.get(node.id,0)) < 1: continue
		if node.kind == "card": cards.append_array(node.opens)
		elif node.kind == "rule":
			for key in node.rule: rules[key] = int(rules.get(key,0)) + int(node.rule[key])
	return {"cards":cards,"rules":rules}

static var _trees_cache: Dictionary = {}

## {tree_id: tree} of the shipped trees file for the elements `kit` turns on, validated against `kit` and `progression`. {} when none are on.
## {"error": reason} when the file is unreadable or refused (a caller treats it like a failed skill-tree load).
static func trees_for(kit: Dictionary, progression: Dictionary) -> Dictionary:
	var on := enabled_elements(kit)
	if on.is_empty(): return {}
	var key := str(kit.hash()) + ":" + str(progression.hash())
	if _trees_cache.has(key): return _trees_cache[key]
	var file := FileAccess.open(TREES_PATH,FileAccess.READ)
	if file == null: return {"error":"cannot open " + TREES_PATH}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK: return {"error":"element trees JSON line %d" % parser.get_error_line()}
	var doc: Variant = RunSpells.normalize(parser.data)
	var issues := validate_trees(doc,kit,progression)
	if not issues.is_empty(): return {"error":"element trees: " + issues[0]}
	var out := {}
	for tree in doc.trees:
		if tree.element in on: out[tree.tree_id] = tree
	_trees_cache[key] = out
	return out

## The progression document with the witches of the elements that are on pointing at their element tree (a copy; the input is not touched).
static func patch_progression(progression: Dictionary, trees: Dictionary) -> Dictionary:
	if trees.is_empty() or trees.has("error"): return progression
	var out: Dictionary = progression.duplicate(true)
	for entry in out.characters:
		for tree_id in trees:
			if trees[tree_id].character_id == entry.id: entry.tree_id = tree_id
	return out

# ---------------------------------------------------------------- loading

func load_file(path: String) -> bool:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		errors.assign(["Cannot read element kit: " + path]);return false
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		errors.assign(["Element kit JSON line %d: %s" % [parser.get_error_line(),parser.get_error_message()]]);return false
	return replace_document(parser.data)

func replace_document(candidate: Variant) -> bool:
	var issues := validate(candidate)
	if not issues.is_empty():
		errors = issues;return false
	errors.clear()
	_document = RunSpells.normalize(candidate)
	return true

func snapshot() -> Dictionary:
	return _document.duplicate(true)
