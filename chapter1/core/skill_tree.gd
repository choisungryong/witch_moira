extends RefCounted
## Stateless rules for permanent skill trees (data/skill_trees.json). Holds no profile state:
## every function takes the tree document and the ranks it should look at.
## Algorithms (topological cycle rejection, greedy reachability, legal investment) follow the
## skill_tree52 prototype; points come from character level, not from receipts.
const Progression = preload("res://chapter1/core/character_progression.gd")
const Catalog = preload("res://chapter1/core/growth_catalog.gd")
const DEFAULT_PATH := "res://chapter1/data/skill_trees.json"
const MAX_NODES := 64
const NO_LIMIT := 1 << 30
const RULE_IDS := ["R1", "R2", "R3", "R4", "R5", "R6"]

# Effect-block grammar (spec 3.3). These are the allowed keys and ranges, not tuning values.
const SKILL_ADD := {"projectiles": [0, 4], "pierce": [0, 4], "hit_budget": [0, 48], "shatter_count": [0, 6], "slow_bps": [0, 3000], "radius_cm": [0, 200]}
const SKILL_MUL := {"damage_raw": [10000, 15000]}
const COOLDOWN_RANGE := [8000, 10000]
const SKILL_AT_LEAST := {"shatter_count": [0, 8], "proc_depth": [0, 1], "hit_budget": [0, 32]}
const SKILL_AT_MOST := {"freeze_stacks": [2, 6]}
const HERO := {"max_hp": [0, 60], "damage_reduction_bps": [0, 1500], "potion_start": [0, 2]}
const RULE_INTS := {"elite_damage_bps": [0, 6000], "shatter_radius_cm": [0, 200], "grace_rerolls": [0, 3], "start_rank": [1, 2]}
const FIELD_KEYS := ["interval_ticks", "radius_cm", "duration_ticks", "slow_bps", "freeze_every_ticks", "max_fields", "pulse_every_ticks", "pulse_damage_bps"]
const FIELD_ADD := {"radius_cm": [0, 200], "max_fields": [0, 2], "pulse_damage_bps": [0, 6000], "slow_bps_at_least": [0, 8500]}
const ADDITIVE_RULES := ["elite_damage_bps", "shatter_radius_cm", "grace_rerolls"]
const EQUAL_PATHS := ["rules.frost_field.interval_ticks", "rules.frost_field.freeze_every_ticks"]
const STAGES := ["r1", "r2", "r3", "r4", "evo"]

static func integer_(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= low and float(value) <= high

static func _in(value: Variant, range_: Array) -> bool:
	return integer_(value, int(range_[0]), int(range_[1]))

# ---------------------------------------------------------------- loading

## {tree_id: tree}, or {"error": reason}. Every tree is validated against the progression document.
static func load_trees(path := DEFAULT_PATH, progression := {}) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "cannot open " + path}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not integer_(parsed.get("schema_version"), 1, 1) or not parsed.get("trees") is Array:
		return {"error": "malformed tree document: " + path}
	var doc: Dictionary = progression
	if doc.is_empty():
		doc = Progression.load_document()
	if doc.has("error") or doc.is_empty():
		return {"error": "progression document unavailable"}
	var trees := {}
	for tree in parsed.trees:
		if not tree is Dictionary or not tree.get("tree_id") is String or trees.has(tree.tree_id):
			return {"error": "bad or duplicate tree_id"}
		var errors := validate_tree(tree, doc)
		if not errors.is_empty():
			return {"error": "%s: %s" % [tree.tree_id, errors[0]]}
		trees[tree.tree_id] = tree
	return trees

# ---------------------------------------------------------------- lookups

static func index_nodes(tree: Dictionary) -> Dictionary:
	var out := {}
	for node in tree.get("nodes", []):
		if node is Dictionary and node.get("id") is String:
			out[node.id] = node
	return out

static func node_level(tree: Dictionary, node: Dictionary) -> int:
	var tiers: Array = tree.get("tiers", [])
	var tier := int(node.get("tier", 1))
	if tier < 1 or tier > tiers.size():
		return NO_LIMIT
	return int(tiers[tier - 1].level)

static func points_spent(ranks: Dictionary) -> int:
	var total := 0
	for id_ in ranks:
		total += int(ranks[id_])
	return total

# ---------------------------------------------------------------- validation

## Empty array means the tree is acceptable. Messages start with a stable code.
static func validate_tree(tree: Dictionary, progression: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key in ["tree_id", "character_id", "signature_skill_id"]:
		if not tree.get(key) is String or String(tree[key]).is_empty():
			errors.append("field:" + key)
	if not integer_(tree.get("revision"), 1, 1000000):
		errors.append("field:revision")
	if not errors.is_empty():
		return errors
	var cap := int(progression.get("level_cap", 0))
	var entry := Progression.character_entry(progression, tree.character_id)
	if entry.is_empty() or entry.get("tree_id") != tree.tree_id or entry.get("signature_skill_id") != tree.signature_skill_id:
		errors.append("character:" + String(tree.character_id) + " does not own this tree")
	var prefixes: Variant = tree.get("node_prefixes")
	if not prefixes is Array or prefixes.is_empty():
		errors.append("field:node_prefixes")
		return errors
	# tiers
	var tiers: Variant = tree.get("tiers")
	if not tiers is Array or tiers.is_empty() or tiers.size() > 8:
		errors.append("field:tiers")
		return errors
	var last_level := 0
	for t in tiers.size():
		var tier: Variant = tiers[t]
		if not tier is Dictionary or not tier.get("name") is String or String(tier.name).is_empty() or not integer_(tier.get("level"), 1, 1000000):
			errors.append("tier:%d malformed" % (t + 1))
			continue
		if int(tier.level) > cap:
			errors.append("tier:%d level %d above level_cap %d" % [t + 1, int(tier.level), cap])
		if int(tier.level) <= last_level:
			errors.append("tier:%d level not increasing" % (t + 1))
		last_level = int(tier.level)
	# branches
	var branch_ids := {}
	var branches: Variant = tree.get("branches")
	if not branches is Array or branches.is_empty():
		errors.append("field:branches")
		return errors
	for branch in branches:
		if not branch is Dictionary or not branch.get("id") is String or not branch.get("name") is String or not branch.get("color") is String or branch_ids.has(branch.get("id")):
			errors.append("branch malformed or duplicate")
			continue
		branch_ids[branch.id] = true
	# nodes
	var nodes_value: Variant = tree.get("nodes")
	if not nodes_value is Array or nodes_value.is_empty() or nodes_value.size() > MAX_NODES:
		errors.append("field:nodes")
		return errors
	var nodes := {}
	for node in nodes_value:
		var node_errors := _node_errors(node, nodes, branch_ids, tiers.size(), prefixes)
		errors.append_array(node_errors)
		if node_errors.is_empty():
			nodes[node.id] = node
	if not errors.is_empty():
		return errors
	# requires
	for id_ in nodes:
		var node: Dictionary = nodes[id_]
		for parent_id in node.requires:
			if not parent_id is String or parent_id == id_ or not nodes.has(parent_id):
				errors.append("requires:%s -> %s missing" % [id_, str(parent_id)])
				continue
			var parent: Dictionary = nodes[parent_id]
			if not integer_(node.requires[parent_id], 1, int(parent.max_rank)):
				errors.append("requires:%s needs %s rank outside 1..%d" % [id_, parent_id, int(parent.max_rank)])
			if parent.branch != node.branch:
				errors.append("requires:%s crosses branches" % id_)
	if not errors.is_empty():
		return errors
	# cycles: deterministic topological elimination
	var resolved := {}
	for pass_ in nodes.size() + 1:
		for id_ in nodes:
			if resolved.has(id_):
				continue
			var ready := true
			for parent_id in nodes[id_].requires:
				ready = ready and resolved.has(parent_id)
			if ready:
				resolved[id_] = true
	if resolved.size() != nodes.size():
		errors.append("cycle:requires graph is not acyclic")
		return errors
	for id_ in nodes:
		for parent_id in nodes[id_].requires:
			if int(nodes[parent_id].tier) >= int(nodes[id_].tier):
				errors.append("requires:%s parent is not in an earlier tier" % id_)
	if not errors.is_empty():
		return errors
	var maximum := {}
	for id_ in nodes:
		maximum[id_] = int(nodes[id_].max_rank)
	if not reachable_(nodes, maximum):
		errors.append("unreachable:full tree cannot be built (min_spent too high?)")
	# effect blocks
	var field_nodes := 0
	for id_ in nodes:
		var previous := {}
		for r in nodes[id_].ranks.size():
			var block: Variant = nodes[id_].ranks[r]
			var where := "%s rank %d" % [id_, r + 1]
			var block_errors := block_errors_(block, where, false)
			errors.append_array(block_errors)
			if block_errors.is_empty():
				var flat := _flat(block)
				if r > 0:
					errors.append_array(_monotonic_errors(previous, flat, where))
				previous = flat
				if block.get("rules", {}).has("frost_field") and r == 0:
					field_nodes += 1
	if field_nodes > 1:
		errors.append("frost_field:only one node may define it")
	# synergies
	var synergies: Variant = tree.get("synergies", [])
	if not synergies is Array:
		errors.append("field:synergies")
	else:
		for syn in synergies:
			if not syn is Dictionary or not nodes.has(syn.get("target")) or not nodes.has(syn.get("source")) or syn.get("target") == syn.get("source"):
				errors.append("synergy:unknown or identical endpoints")
				continue
			errors.append_array(block_errors_(syn.get("per_rank"), "synergy %s<-%s" % [syn.target, syn.source], true))
	return errors

static func _node_errors(node: Variant, known: Dictionary, branch_ids: Dictionary, tier_count: int, prefixes: Array) -> Array[String]:
	var errors: Array[String] = []
	if not node is Dictionary:
		errors.append("node:not an object")
		return errors
	var id_: String = node.get("id") if node.get("id") is String else ""
	if id_.is_empty() or known.has(id_):
		errors.append("node:empty or duplicate id " + id_)
		return errors
	var owned := false
	for prefix in prefixes:
		owned = owned or id_.begins_with(String(prefix))
	if not owned:
		errors.append("node:%s belongs to another tree" % id_)
	for key in ["name", "lore"]:
		if not node.get(key) is String or String(node[key]).is_empty():
			errors.append("node:%s field %s" % [id_, key])
	if not branch_ids.has(node.get("branch")):
		errors.append("node:%s unknown branch" % id_)
	if not integer_(node.get("tier"), 1, tier_count):
		errors.append("node:%s tier out of range" % id_)
	if not integer_(node.get("max_rank"), 1, 10):
		errors.append("node:%s max_rank out of range" % id_)
	if not node.get("requires") is Dictionary:
		errors.append("node:%s requires must be an object" % id_)
	if not integer_(node.get("min_spent"), 0, 6400):
		errors.append("node:%s min_spent out of range" % id_)
	if node.get("new_rule") != null and not (node.new_rule is String and node.new_rule in RULE_IDS):
		errors.append("node:%s new_rule unknown" % id_)
	if not node.get("ranks") is Array:
		errors.append("node:%s ranks must be an array" % id_)
	elif integer_(node.get("max_rank"), 1, 10) and node.ranks.size() != int(node.max_rank):
		errors.append("node:%s ranks length %d != max_rank %d" % [id_, node.ranks.size(), int(node.max_rank)])
	return errors

## Grammar and range check of one effect block. additive_only is used for synergy blocks.
static func block_errors_(block: Variant, where: String, additive_only: bool) -> Array[String]:
	var errors: Array[String] = []
	if not block is Dictionary or block.is_empty():
		errors.append("block:%s must be a non-empty object" % where)
		return errors
	for section in block:
		if not section in ["skill", "hero", "rules"]:
			errors.append("block:%s unknown section %s" % [where, str(section)])
	var skill: Variant = block.get("skill", {})
	if not skill is Dictionary:
		errors.append("block:%s skill must be an object" % where)
	else:
		for key in skill:
			if key == "add":
				errors.append_array(_table_errors(skill.add, SKILL_ADD, where + " skill.add"))
			elif additive_only:
				errors.append("block:%s synergy may only add (skill.%s)" % [where, str(key)])
			elif key == "mul_bps":
				errors.append_array(_table_errors(skill.mul_bps, SKILL_MUL, where + " skill.mul_bps"))
			elif key == "cooldown_bps":
				if not _in(skill.cooldown_bps, COOLDOWN_RANGE):
					errors.append("block:%s skill.cooldown_bps out of range" % where)
			elif key == "at_least":
				errors.append_array(_table_errors(skill.at_least, SKILL_AT_LEAST, where + " skill.at_least"))
			elif key == "at_most":
				errors.append_array(_table_errors(skill.at_most, SKILL_AT_MOST, where + " skill.at_most"))
			else:
				errors.append("block:%s unknown skill key %s" % [where, str(key)])
		var added: Variant = skill.get("add")
		if added is Dictionary and (int(added.get("projectiles", 0)) > 0 or int(added.get("pierce", 0)) > 0) and int(added.get("hit_budget", 0)) <= 0:
			errors.append("block:%s adds projectiles or pierce without hit_budget" % where)
	if block.has("hero"):
		errors.append_array(_table_errors(block.hero, HERO, where + " hero"))
	var rules: Variant = block.get("rules", {})
	if not rules is Dictionary:
		errors.append("block:%s rules must be an object" % where)
		return errors
	for key in rules:
		if key in ADDITIVE_RULES or (not additive_only and RULE_INTS.has(key)):
			if not _in(rules[key], RULE_INTS[key]):
				errors.append("block:%s rules.%s out of range" % [where, key])
		elif key == "frost_field_add":
			errors.append_array(_table_errors(rules[key], FIELD_ADD, where + " rules.frost_field_add"))
		elif key == "frost_field" and not additive_only:
			errors.append_array(_field_errors(rules[key], where))
		elif key == "evolve_without_passive" and not additive_only:
			if not rules[key] is bool:
				errors.append("block:%s rules.evolve_without_passive must be a boolean" % where)
		else:
			errors.append("block:%s unknown rules key %s" % [where, str(key)])
	return errors

static func _table_errors(value: Variant, table: Dictionary, where: String) -> Array[String]:
	var errors: Array[String] = []
	if not value is Dictionary or value.is_empty():
		errors.append("block:%s must be a non-empty object" % where)
		return errors
	for key in value:
		if not table.has(key):
			errors.append("block:%s unknown key %s" % [where, str(key)])
		elif not _in(value[key], table[key]):
			errors.append("block:%s %s out of range" % [where, str(key)])
	return errors

static func _field_errors(field: Variant, where: String) -> Array[String]:
	var errors: Array[String] = []
	if not field is Dictionary or field.size() != FIELD_KEYS.size():
		errors.append("block:%s frost_field needs exactly %d keys" % [where, FIELD_KEYS.size()])
		return errors
	var ranges := {"interval_ticks": [120, 600], "radius_cm": [200, 600], "duration_ticks": [60, 300], "slow_bps": [0, 8500], "max_fields": [1, 3], "pulse_damage_bps": [0, 6000]}
	for key in FIELD_KEYS:
		if not field.has(key):
			errors.append("block:%s frost_field.%s missing" % [where, key])
		elif key in ["freeze_every_ticks", "pulse_every_ticks"]:
			if not (integer_(field[key], 0, 0) or integer_(field[key], 15, 120)):
				errors.append("block:%s frost_field.%s must be 0 or 15..120" % [where, key])
		elif not _in(field[key], ranges[key]):
			errors.append("block:%s frost_field.%s out of range" % [where, key])
	return errors

static func _flat(block: Dictionary) -> Dictionary:
	var out := {}
	var skill: Dictionary = block.get("skill", {})
	for section in ["add", "mul_bps", "at_least", "at_most"]:
		for key in skill.get(section, {}):
			out["skill.%s.%s" % [section, key]] = int(skill[section][key])
	if skill.has("cooldown_bps"):
		out["skill.cooldown_bps"] = int(skill.cooldown_bps)
	for key in block.get("hero", {}):
		out["hero." + key] = int(block.hero[key])
	var rules: Dictionary = block.get("rules", {})
	for key in rules:
		var value: Variant = rules[key]
		if value is Dictionary:
			for inner in value:
				out["rules.%s.%s" % [key, inner]] = int(value[inner])
		elif value is bool:
			out["rules." + key] = 1 if value else 0
		else:
			out["rules." + key] = int(value)
	return out

static func _neutral(path: String) -> int:
	if path.begins_with("skill.mul_bps.") or path == "skill.cooldown_bps":
		return 10000
	if path.begins_with("skill.at_most."):
		return NO_LIMIT
	if path in EQUAL_PATHS:
		return -1
	return 0

## A higher rank must never be weaker than the one before it.
static func _monotonic_errors(previous: Dictionary, current: Dictionary, where: String) -> Array[String]:
	var errors: Array[String] = []
	var paths := {}
	for path in previous:
		paths[path] = true
	for path in current:
		paths[path] = true
	for path in paths:
		var neutral := _neutral(path)
		var before: int = previous.get(path, neutral)
		var after: int = current.get(path, neutral)
		var weaker := false
		if path in EQUAL_PATHS:
			weaker = before != after
		elif path == "rules.frost_field.pulse_every_ticks":
			weaker = before != 0 and before != after
		elif path == "skill.cooldown_bps" or path.begins_with("skill.at_most."):
			weaker = after > before
		else:
			weaker = after < before
		if weaker:
			errors.append("monotonic:%s %s gets weaker (%d -> %d)" % [where, path, before, after])
	return errors

# ---------------------------------------------------------------- graph

static func _step_legal(nodes: Dictionary, built: Dictionary, id_: String) -> bool:
	if not nodes.has(id_):
		return false
	var node: Dictionary = nodes[id_]
	if int(built.get(id_, 0)) >= int(node.max_rank) or points_spent(built) < int(node.min_spent):
		return false
	for parent in node.requires:
		if int(built.get(parent, 0)) < int(node.requires[parent]):
			return false
	return true

## True when some order of single-rank investments builds exactly `target` (levels ignored).
static func reachable_(nodes: Dictionary, target: Dictionary) -> bool:
	var built := {}
	var remaining := points_spent(target)
	for id_ in target:
		if not nodes.has(id_):
			return false
	for pass_ in remaining + 1:
		if remaining == 0:
			return true
		var progressed := false
		for id_ in nodes:
			if int(built.get(id_, 0)) < int(target.get(id_, 0)) and _step_legal(nodes, built, id_):
				built[id_] = int(built.get(id_, 0)) + 1
				remaining -= 1
				progressed = true
		if not progressed:
			return false
	return remaining == 0

## Why one more rank of node_id is not allowed now. {ok, reasons}; reasons are codes such as
## "unknown_node", "max_rank", "level:6", "requires:<node>:<rank>", "min_spent:15", "no_points".
static func can_invest(tree: Dictionary, ranks: Dictionary, node_id: String, level: int, points_free: int) -> Dictionary:
	var reasons: Array[String] = []
	var nodes := index_nodes(tree)
	if not nodes.has(node_id):
		reasons.append("unknown_node")
		return {"ok": false, "reasons": reasons}
	var node: Dictionary = nodes[node_id]
	if int(ranks.get(node_id, 0)) >= int(node.max_rank):
		reasons.append("max_rank")
	if level < node_level(tree, node):
		reasons.append("level:%d" % node_level(tree, node))
	for parent in node.requires:
		if int(ranks.get(parent, 0)) < int(node.requires[parent]):
			reasons.append("requires:%s:%d" % [parent, int(node.requires[parent])])
	if points_spent(ranks) < int(node.min_spent):
		reasons.append("min_spent:%d" % int(node.min_spent))
	if points_free < 1:
		reasons.append("no_points")
	return {"ok": reasons.is_empty(), "reasons": reasons}

## Staged (not yet committed) ranks may be taken back for free, one rank at a time, but never below
## the committed ranks and never so that a staged dependent loses its prerequisite or min_spent.
static func can_refund_staged(tree: Dictionary, committed: Dictionary, staged: Dictionary, node_id: String) -> bool:
	var nodes := index_nodes(tree)
	if not nodes.has(node_id):
		return false
	var now := int(staged.get(node_id, 0))
	if now <= int(committed.get(node_id, 0)) or now < 1:
		return false
	var next := staged.duplicate()
	if now == 1:
		next.erase(node_id)
	else:
		next[node_id] = now - 1
	return reachable_(nodes, next)

## Empty array means `ranks` is a legal state for this level and number of earned points.
static func legal_ranks(tree: Dictionary, ranks: Dictionary, level: int, points_earned: int) -> Array[String]:
	var errors: Array[String] = []
	var nodes := index_nodes(tree)
	for id_ in ranks:
		if not nodes.has(id_):
			errors.append("unknown_node:" + str(id_))
		elif not integer_(ranks[id_], 1, int(nodes[id_].max_rank)):
			errors.append("rank_range:" + str(id_))
		elif level < node_level(tree, nodes[id_]):
			errors.append("level:%s needs %d" % [id_, node_level(tree, nodes[id_])])
	if not errors.is_empty():
		return errors
	if points_spent(ranks) > points_earned:
		errors.append("points:spent %d > earned %d" % [points_spent(ranks), points_earned])
	if not reachable_(nodes, ranks):
		errors.append("unreachable:requires or min_spent cannot be satisfied")
	return errors

# ---------------------------------------------------------------- compile

## Merge the current rank blocks (in the data's node order) and the active synergies into one
## {skill, hero, rules} block. Integer math only; see spec 3.3 for the merge rules.
static func compile(tree: Dictionary, ranks: Dictionary) -> Dictionary:
	var out := {"skill": {}, "hero": {}, "rules": {}}
	for node in tree.get("nodes", []):
		var rank := int(ranks.get(node.id, 0))
		if rank >= 1 and rank <= node.ranks.size():
			_merge(out, node.ranks[rank - 1], 1)
	for syn in tree.get("synergies", []):
		var source_rank := int(ranks.get(syn.source, 0))
		if int(ranks.get(syn.target, 0)) >= 1 and source_rank >= 1:
			_merge(out, syn.per_rank, source_rank)
	return out

static func _sub(out: Dictionary, section: String, key: String) -> Dictionary:
	if not out[section].has(key):
		out[section][key] = {}
	return out[section][key]

static func _merge(out: Dictionary, block: Dictionary, scale: int) -> void:
	var skill: Dictionary = block.get("skill", {})
	for key in skill.get("add", {}):
		var add: Dictionary = _sub(out, "skill", "add")
		add[key] = int(add.get(key, 0)) + int(skill.add[key]) * scale
	for key in skill.get("mul_bps", {}):
		var mul: Dictionary = _sub(out, "skill", "mul_bps")
		mul[key] = int(mul.get(key, 10000)) * int(skill.mul_bps[key]) / 10000
	if skill.has("cooldown_bps"):
		out.skill.cooldown_bps = int(out.skill.get("cooldown_bps", 10000)) * int(skill.cooldown_bps) / 10000
	for key in skill.get("at_least", {}):
		var least: Dictionary = _sub(out, "skill", "at_least")
		least[key] = maxi(int(least.get(key, 0)), int(skill.at_least[key]))
	for key in skill.get("at_most", {}):
		var most: Dictionary = _sub(out, "skill", "at_most")
		most[key] = mini(int(most.get(key, NO_LIMIT)), int(skill.at_most[key]))
	for key in block.get("hero", {}):
		out.hero[key] = int(out.hero.get(key, 0)) + int(block.hero[key]) * scale
	var rules: Dictionary = block.get("rules", {})
	for key in rules:
		var value: Variant = rules[key]
		if key in ADDITIVE_RULES:
			out.rules[key] = int(out.rules.get(key, 0)) + int(value) * scale
		elif key == "start_rank":
			out.rules[key] = maxi(int(out.rules.get(key, 0)), int(value))
		elif key == "evolve_without_passive":
			out.rules[key] = bool(out.rules.get(key, false)) or bool(value)
		elif key == "frost_field":
			var copy := {}
			for inner in value:
				copy[inner] = int(value[inner])
			out.rules[key] = copy
		elif key == "frost_field_add":
			var sum: Dictionary = _sub(out, "rules", key)
			for inner in value:
				if inner == "slow_bps_at_least":
					sum[inner] = maxi(int(sum.get(inner, 0)), int(value[inner]))
				else:
					sum[inner] = int(sum.get(inner, 0)) + int(value[inner]) * scale

# ---------------------------------------------------------------- display

static func _hundredths(value: int) -> String:
	var whole := value / 100
	var frac := value % 100
	if frac == 0:
		return str(whole)
	if frac % 10 == 0:
		return "%d.%d" % [whole, frac / 10]
	return "%d.%02d" % [whole, frac]

## Display lines for one effect block (spec 8.2 table). hit_budget and similar internals are hidden.
static func describe_block(block: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var skill: Dictionary = block.get("skill", {})
	var add: Dictionary = skill.get("add", {})
	if int(add.get("pierce", 0)) != 0:
		lines.append("관통 +%d" % int(add.pierce))
	if int(add.get("projectiles", 0)) != 0:
		lines.append("스피어 +%d발" % int(add.projectiles))
	if int(add.get("shatter_count", 0)) != 0:
		lines.append("파편 +%d" % int(add.shatter_count))
	if int(add.get("slow_bps", 0)) != 0:
		lines.append("감속 +%s%%p" % _hundredths(int(add.slow_bps)))
	if int(add.get("radius_cm", 0)) != 0:
		lines.append("반경 +%s m" % _hundredths(int(add.radius_cm)))
	var mul: Dictionary = skill.get("mul_bps", {})
	if mul.has("damage_raw") and int(mul.damage_raw) != 10000:
		lines.append("피해 +%s%%" % _hundredths(int(mul.damage_raw) - 10000))
	if skill.has("cooldown_bps") and int(skill.cooldown_bps) != 10000:
		lines.append("시전 간격 −%s%%" % _hundredths(10000 - int(skill.cooldown_bps)))
	if skill.get("at_most", {}).has("freeze_stacks"):
		lines.append("%d번 맞으면 빙결" % int(skill.at_most.freeze_stacks))
	if skill.get("at_least", {}).has("shatter_count"):
		lines.append("파쇄 파편 최소 %d" % int(skill.at_least.shatter_count))
	var hero: Dictionary = block.get("hero", {})
	if int(hero.get("max_hp", 0)) != 0:
		lines.append("최대 생명 +%d" % int(hero.max_hp))
	if int(hero.get("damage_reduction_bps", 0)) != 0:
		lines.append("받는 피해 −%s%%" % _hundredths(int(hero.damage_reduction_bps)))
	if int(hero.get("potion_start", 0)) != 0:
		lines.append("시작 회복약 +%d" % int(hero.potion_start))
	var rules: Dictionary = block.get("rules", {})
	if int(rules.get("elite_damage_bps", 0)) != 0:
		lines.append("수호자·우두머리 피해 +%s%%" % _hundredths(int(rules.elite_damage_bps)))
	if int(rules.get("shatter_radius_cm", 0)) != 0:
		lines.append("파쇄 반경 +%s m" % _hundredths(int(rules.shatter_radius_cm)))
	if rules.has("frost_field"):
		var field: Dictionary = rules.frost_field
		lines.append("서리 지대: 반경 %s m · %s초 · 감속 %s%%" % [_hundredths(int(field.radius_cm)), _hundredths(int(field.duration_ticks) * 100 / 60), _hundredths(int(field.slow_bps))])
	var field_add: Dictionary = rules.get("frost_field_add", {})
	if int(field_add.get("radius_cm", 0)) != 0:
		lines.append("지대 반경 +%s m" % _hundredths(int(field_add.radius_cm)))
	if int(field_add.get("max_fields", 0)) != 0:
		lines.append("지대 동시 +%d개" % int(field_add.max_fields))
	if int(field_add.get("pulse_damage_bps", 0)) != 0:
		lines.append("지대 피해: 스피어 피해의 %s%%" % _hundredths(int(field_add.pulse_damage_bps)))
	if int(field_add.get("slow_bps_at_least", 0)) != 0:
		lines.append("지대 감속 %s%%" % _hundredths(int(field_add.slow_bps_at_least)))
	if int(rules.get("grace_rerolls", 0)) != 0:
		lines.append("권능 다시 청하기 %d회" % int(rules.grace_rerolls))
	if rules.has("start_rank"):
		lines.append("아이스 스피어 랭크 %d으로 시작" % int(rules.start_rank))
	if rules.get("evolve_without_passive", false):
		lines.append("하갈라즈 룬 없이 진화")
	return lines

## Display lines of the cumulative effect at `rank` (empty for rank 0 or an unknown node).
static func describe(tree: Dictionary, node_id: String, rank: int) -> Array[String]:
	var nodes := index_nodes(tree)
	if not nodes.has(node_id) or rank < 1 or rank > nodes[node_id].ranks.size():
		var none: Array[String] = []
		return none
	return describe_block(nodes[node_id].ranks[rank - 1])

## The same lines as describe_block, as keys and number arguments: [{key, args}]. The screen words them
## (view/hud/tree_text.gd, keys tree.effect.*). Numbers that were shown with up to two decimals are strings ("3.5").
static func describe_block_keys(block: Dictionary) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	var skill: Dictionary = block.get("skill", {})
	var add: Dictionary = skill.get("add", {})
	if int(add.get("pierce", 0)) != 0:
		lines.append(_line("pierce_add", {"n": int(add.pierce)}))
	if int(add.get("projectiles", 0)) != 0:
		lines.append(_line("projectiles_add", {"n": int(add.projectiles)}))
	if int(add.get("shatter_count", 0)) != 0:
		lines.append(_line("shatter_add", {"n": int(add.shatter_count)}))
	if int(add.get("slow_bps", 0)) != 0:
		lines.append(_line("slow_add", {"v": _hundredths(int(add.slow_bps))}))
	if int(add.get("radius_cm", 0)) != 0:
		lines.append(_line("radius_add", {"v": _hundredths(int(add.radius_cm))}))
	var mul: Dictionary = skill.get("mul_bps", {})
	if mul.has("damage_raw") and int(mul.damage_raw) != 10000:
		lines.append(_line("damage_add", {"v": _hundredths(int(mul.damage_raw) - 10000)}))
	if skill.has("cooldown_bps") and int(skill.cooldown_bps) != 10000:
		lines.append(_line("interval_less", {"v": _hundredths(10000 - int(skill.cooldown_bps))}))
	if skill.get("at_most", {}).has("freeze_stacks"):
		lines.append(_line("freeze_at", {"n": int(skill.at_most.freeze_stacks)}))
	if skill.get("at_least", {}).has("shatter_count"):
		lines.append(_line("shatter_min", {"n": int(skill.at_least.shatter_count)}))
	var hero: Dictionary = block.get("hero", {})
	if int(hero.get("max_hp", 0)) != 0:
		lines.append(_line("max_hp_add", {"n": int(hero.max_hp)}))
	if int(hero.get("damage_reduction_bps", 0)) != 0:
		lines.append(_line("reduction_add", {"v": _hundredths(int(hero.damage_reduction_bps))}))
	if int(hero.get("potion_start", 0)) != 0:
		lines.append(_line("potion_start", {"n": int(hero.potion_start)}))
	var rules: Dictionary = block.get("rules", {})
	if int(rules.get("elite_damage_bps", 0)) != 0:
		lines.append(_line("elite_damage", {"v": _hundredths(int(rules.elite_damage_bps))}))
	if int(rules.get("shatter_radius_cm", 0)) != 0:
		lines.append(_line("shatter_radius", {"v": _hundredths(int(rules.shatter_radius_cm))}))
	if rules.has("frost_field"):
		var field: Dictionary = rules.frost_field
		lines.append(_line("frost_field", {"radius": _hundredths(int(field.radius_cm)), "seconds": _hundredths(int(field.duration_ticks) * 100 / 60), "slow": _hundredths(int(field.slow_bps))}))
	var field_add: Dictionary = rules.get("frost_field_add", {})
	if int(field_add.get("radius_cm", 0)) != 0:
		lines.append(_line("field_radius_add", {"v": _hundredths(int(field_add.radius_cm))}))
	if int(field_add.get("max_fields", 0)) != 0:
		lines.append(_line("field_count_add", {"n": int(field_add.max_fields)}))
	if int(field_add.get("pulse_damage_bps", 0)) != 0:
		lines.append(_line("field_pulse", {"v": _hundredths(int(field_add.pulse_damage_bps))}))
	if int(field_add.get("slow_bps_at_least", 0)) != 0:
		lines.append(_line("field_slow_min", {"v": _hundredths(int(field_add.slow_bps_at_least))}))
	if int(rules.get("grace_rerolls", 0)) != 0:
		lines.append(_line("rerolls", {"n": int(rules.grace_rerolls)}))
	if rules.has("start_rank"):
		lines.append(_line("start_rank", {"rank": int(rules.start_rank)}))
	if rules.get("evolve_without_passive", false):
		lines.append(_line("evolve_free", {}))
	return lines

static func _line(name_: String, args: Dictionary) -> Dictionary:
	return {"key": "tree.effect." + name_, "args": args}

## Key lines of the cumulative effect at `rank` (empty for rank 0 or an unknown node).
static func describe_keys(tree: Dictionary, node_id: String, rank: int) -> Array[Dictionary]:
	var nodes := index_nodes(tree)
	if not nodes.has(node_id) or rank < 1 or rank > nodes[node_id].ranks.size():
		var none: Array[Dictionary] = []
		return none
	return describe_block_keys(nodes[node_id].ranks[rank - 1])

# ---------------------------------------------------------------- static power estimate

static func _limited(stat: String, amount: int) -> int:
	return clampi(amount, int(Catalog.LIMITS[stat][0]), int(Catalog.LIMITS[stat][1]))

## One stage of the signature skill: growth definition, then the tree block (spec 3.3 order), then the
## primary-stage bonus from combat tuning. Gear is not modelled.
static func _stage_effect(definition: Dictionary, block: Dictionary, bonus: Dictionary) -> Dictionary:
	var effect := definition.duplicate(true)
	for key in effect:
		effect[key] = int(effect[key])
	for stat in block.get("add", {}):
		effect[stat] = int(effect[stat]) + int(block.add[stat])
	for stat in block.get("at_least", {}):
		effect[stat] = maxi(int(effect[stat]), int(block.at_least[stat]))
	for stat in block.get("at_most", {}):
		effect[stat] = int(block.at_most[stat]) if int(effect[stat]) == 0 else mini(int(effect[stat]), int(block.at_most[stat]))
	for stat in block.get("mul_bps", {}):
		effect[stat] = int(effect[stat]) * int(block.mul_bps[stat]) / 10000
	if block.has("cooldown_bps"):
		effect.cooldown_ticks = maxi(12, int(effect.cooldown_ticks) * int(block.cooldown_bps) / 10000)
	for stat in effect:
		effect[stat] = _limited(stat, int(effect[stat]))
	effect.pierce = mini(8, int(effect.pierce))
	for stat in bonus.get("add", {}):
		effect[stat] = _limited(stat, int(effect[stat]) + int(bonus.add[stat]))
	for stat in bonus.get("mul_bps", {}):
		effect[stat] = _limited(stat, int(effect[stat]) * int(bonus.mul_bps[stat]) / 10000)
	if bonus.has("cooldown_bps"):
		effect.cooldown_ticks = maxi(12, int(effect.cooldown_ticks) * int(bonus.cooldown_bps) / 10000)
	effect.cooldown_ticks = maxi(12, int(effect.cooldown_ticks))
	return effect

static func _stage_power(effect: Dictionary) -> Dictionary:
	var hits := mini(int(effect.hit_budget), maxi(1, int(effect.projectiles)) * (int(effect.pierce) + 1))
	return {"hits_per_cast": hits, "cooldown_ticks": int(effect.cooldown_ticks), "damage_raw": int(effect.damage_raw),
		"throughput": float(hits) * float(effect.damage_raw) / float(effect.cooldown_ticks)}

## Static throughput estimate of the signature skill per in-run stage (r1..r4, evo), without and with the
## build. throughput = min(hit_budget, projectiles * (pierce + 1)) * damage_raw / cooldown_ticks.
## Returns {"stages": {stage: {"base", "build", "ratio"}}, "grace_ratio_base", "grace_ratio_build", "tree_ratio_r4"}
## or {"error": reason}. Ratios are floats.
static func power_table(tree: Dictionary, ranks: Dictionary, growth_doc: Dictionary, tuning: Dictionary) -> Dictionary:
	var skill: Dictionary = {}
	for entry in growth_doc.get("skills", []):
		if entry is Dictionary and entry.get("id") == tree.get("signature_skill_id"):
			skill = entry
	if skill.is_empty():
		return {"error": "signature skill not in growth document"}
	var block: Dictionary = compile(tree, ranks).skill
	var bonuses: Dictionary = tuning.get("primary_bonus", {}).get(skill.id, {})
	var stages := {}
	for stage in STAGES:
		var definition: Dictionary = skill.evolution if stage == "evo" else skill.ranks[int(stage.substr(1)) - 1]
		var bonus: Dictionary = bonuses.get(stage, {})
		var base := _stage_power(_stage_effect(definition, {}, bonus))
		var build := _stage_power(_stage_effect(definition, block, bonus))
		stages[stage] = {"base": base, "build": build, "ratio": build.throughput / base.throughput}
	return {
		"stages": stages,
		"grace_ratio_base": stages.r4.base.throughput / stages.r1.base.throughput,
		"grace_ratio_build": stages.r4.build.throughput / stages.r1.build.throughput,
		"tree_ratio_r4": stages.r4.ratio,
	}
