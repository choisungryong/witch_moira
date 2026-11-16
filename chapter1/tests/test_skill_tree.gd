extends SceneTree
## P1 checks of the stateless permanent-growth modules: core/skill_tree.gd and core/character_progression.gd.
const SkillTree = preload("res://chapter1/core/skill_tree.gd")
const Progression = preload("res://chapter1/core/character_progression.gd")
const FROST := "witch.frost"
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

func has_code(errors: Array[String], code: String) -> bool:
	for error in errors:
		if error.begins_with(code):
			return true
	return false

func node_of(tree: Dictionary, id_: String) -> Dictionary:
	return SkillTree.index_nodes(tree)[id_]

func rejects(tree: Dictionary, doc: Dictionary, code: String, label: String) -> void:
	var errors := SkillTree.validate_tree(tree, doc)
	check(has_code(errors, code), "%s (wanted %s, got %s)" % [label, code, str(errors)])

func _initialize() -> void:
	var doc := Progression.load_document()
	check(not doc.has("error") and not doc.is_empty(), "character_progression.json loads")
	check(Progression.validate_document(doc).is_empty(), "progression document passes its validator: " + str(Progression.validate_document(doc)))
	var trees := SkillTree.load_trees()
	check(not trees.has("error"), "skill_trees.json passes the validator: " + str(trees.get("error", "")))
	if trees.has("error") or doc.is_empty():
		finish(null)
		return
	var tree: Dictionary = trees[FROST]
	var nodes := SkillTree.index_nodes(tree)
	var rank_sum := 0
	for id_ in nodes:
		rank_sum += int(nodes[id_].max_rank)
	check(nodes.size() == 13 and rank_sum == 42, "frost tree has 13 nodes and rank sum 42")
	var levels: Array = []
	for tier in tree.tiers:
		levels.append(int(tier.level))
	check(levels == [1, 6, 12, 18] and int(nodes["witch.frost.deep_oath"].min_spent) == 15, "tier levels 1/6/12/18 and deep oath min_spent 15 come from data")

	# ---- validator rejects bad documents
	var bad: Dictionary = tree.duplicate(true)
	bad.nodes[0].requires = {"witch.frost.volley": 1}
	rejects(bad, doc, "cycle", "requires cycle rejected")
	bad = tree.duplicate(true)
	bad.nodes[1].requires = {"witch.frost.ghost": 1}
	rejects(bad, doc, "requires", "missing prerequisite rejected")
	bad = tree.duplicate(true)
	bad.nodes[1].requires = {"witch.frost.needle": 6}
	rejects(bad, doc, "requires", "prerequisite rank above the parent's max_rank rejected")
	bad = tree.duplicate(true)
	bad.nodes[0].ranks.pop_back()
	rejects(bad, doc, "node", "ranks length != max_rank rejected")
	bad = tree.duplicate(true)
	bad.nodes[0].ranks[0].skill.add["warp_speed"] = 1
	rejects(bad, doc, "block", "unknown effect key rejected")
	bad = tree.duplicate(true)
	bad.nodes[0].ranks[0].skill.add.pierce = 9
	rejects(bad, doc, "block", "out of range effect value rejected")
	bad = tree.duplicate(true)
	bad.tiers[3].level = 21
	rejects(bad, doc, "tier", "tier level above level_cap rejected")
	bad = tree.duplicate(true)
	bad.nodes[1].ranks[0].skill.add.erase("hit_budget")
	rejects(bad, doc, "block", "projectiles without hit_budget rejected")
	bad = tree.duplicate(true)
	bad.nodes[0].ranks[2].skill.add.pierce = 0
	rejects(bad, doc, "monotonic", "weaker higher rank rejected")
	bad = tree.duplicate(true)
	bad.nodes[0].id = "witch.ember.needle"
	rejects(bad, doc, "node", "another witch's node rejected")
	bad = tree.duplicate(true)
	bad.nodes[4].ranks[1].rules.frost_field = {}
	rejects(bad, doc, "block", "malformed frost_field rejected")
	bad = tree.duplicate(true)
	bad.character_id = "chapter1.character.ember"
	rejects(bad, doc, "character", "tree owned by another character rejected")
	var bad_doc: Dictionary = doc.duplicate(true)
	bad_doc.xp_thresholds[5] = bad_doc.xp_thresholds[4]
	check(not Progression.validate_document(bad_doc).is_empty(), "non-increasing xp curve rejected")
	bad_doc = doc.duplicate(true)
	bad_doc.xp_thresholds[0] = 5
	check(not Progression.validate_document(bad_doc).is_empty(), "xp curve not starting at 0 rejected")
	bad_doc = doc.duplicate(true)
	bad_doc.xp_thresholds.pop_back()
	check(not Progression.validate_document(bad_doc).is_empty(), "xp curve shorter than level_cap rejected")
	check(SkillTree.validate_tree(tree, doc).is_empty(), "the original tree is untouched by the mutations above")

	# ---- levels and points
	check(Progression.level_for_xp(doc, 0) == 1 and Progression.level_for_xp(doc, 249) == 1 and Progression.level_for_xp(doc, 250) == 2, "level boundaries at 249/250")
	check(Progression.level_for_xp(doc, 1000) == 4 and Progression.level_for_xp(doc, 25000) == 20 and Progression.level_for_xp(doc, 900000000) == 20, "1000 xp is Lv 4, curve caps at Lv 20")
	check(Progression.points_earned(doc, 1000, ["champion:0", "champion:1", "boss"]) == 6, "first winning run: Lv 4 plus 3 first kills = 6 points")
	check(Progression.points_earned(doc, 25000, ["champion:0", "champion:1", "boss"]) == 22, "Lv 20 with every first kill = 22 points")
	check(Progression.points_earned(doc, 250, ["boss", "boss", "nonsense"]) == 2, "duplicate and unknown first-kill receipts earn once or nothing")
	check(Progression.xp_for_next(doc, 3880) == 620 and Progression.xp_for_next(doc, 30000) == 0, "xp_for_next counts to the next threshold, 0 at the cap")
	var bounds := Progression.xp_bounds(doc)
	check(int(bounds.run_xp_max) == 1000 and int(bounds.points_cap) == 22 and int(bounds.migration_xp_max) == 5000, "xp_bounds: one winning run 1000 xp, 22 points, migration 5000")

	# ---- investing
	var free_one := SkillTree.can_invest(tree, {}, "witch.frost.needle", 1, 1)
	check(free_one.ok and free_one.reasons.is_empty(), "tier 1 root node is investable at Lv 1 with a point")
	var locked := SkillTree.can_invest(tree, {"witch.frost.needle": 1}, "witch.frost.volley", 3, 5)
	check(not locked.ok and "level:6" in locked.reasons and "requires:witch.frost.needle:2" in locked.reasons, "volley refused: level 6 and needle 2 both reported")
	check("no_points" in SkillTree.can_invest(tree, {}, "witch.frost.needle", 1, 0).reasons, "no free points refused")
	check("max_rank" in SkillTree.can_invest(tree, {"witch.common.favor": 2}, "witch.common.favor", 20, 5).reasons, "max rank refused")
	check("unknown_node" in SkillTree.can_invest(tree, {}, "witch.frost.nope", 20, 5).reasons, "unknown node refused")
	var deep := SkillTree.can_invest(tree, {"witch.frost.needle": 5, "witch.frost.rime": 5, "witch.common.vigor": 4}, "witch.frost.deep_oath", 18, 3)
	check("min_spent:15" in deep.reasons and deep.reasons.size() == 1, "deep oath needs 15 points spent (14 is not enough)")
	check(SkillTree.can_invest(tree, {"witch.frost.needle": 5, "witch.frost.rime": 5, "witch.common.vigor": 5}, "witch.frost.deep_oath", 18, 3).ok, "deep oath opens at 15 points spent and Lv 18")
	check("level:18" in SkillTree.can_invest(tree, {"witch.frost.needle": 5, "witch.frost.rime": 5, "witch.common.vigor": 5}, "witch.frost.deep_oath", 17, 3).reasons, "deep oath refused below Lv 18")

	# ---- legal ranks
	var legal := {"witch.frost.needle": 3, "witch.frost.volley": 2, "witch.common.vigor": 1}
	check(SkillTree.legal_ranks(tree, legal, 6, 6).is_empty(), "a legal build passes at Lv 6 with 6 points")
	check(has_code(SkillTree.legal_ranks(tree, legal, 5, 6), "level"), "tier 2 node rejected below Lv 6")
	check(has_code(SkillTree.legal_ranks(tree, legal, 6, 5), "points"), "spent above earned rejected")
	check(has_code(SkillTree.legal_ranks(tree, {"witch.frost.volley": 1}, 6, 6), "unreachable"), "volley without needle rejected")
	check(has_code(SkillTree.legal_ranks(tree, {"witch.frost.needle": 6}, 6, 6), "rank_range"), "rank above max rejected")
	check(has_code(SkillTree.legal_ranks(tree, {"witch.frost.mystery": 1}, 6, 6), "unknown_node"), "unknown node in ranks rejected")
	check(has_code(SkillTree.legal_ranks(tree, {"witch.frost.deep_oath": 1, "witch.frost.needle": 5}, 18, 22), "unreachable"), "deep oath with only 6 points spent is unreachable")

	# ---- staged investment can be taken back for free
	var committed := {"witch.frost.needle": 2}
	check(SkillTree.can_refund_staged(tree, committed, {"witch.frost.needle": 2, "witch.frost.volley": 1}, "witch.frost.volley"), "staged volley rank refunds")
	check(not SkillTree.can_refund_staged(tree, committed, {"witch.frost.needle": 2}, "witch.frost.needle"), "committed ranks cannot be refunded")
	check(SkillTree.can_refund_staged(tree, committed, {"witch.frost.needle": 3, "witch.frost.volley": 1}, "witch.frost.needle"), "staged needle rank above the committed ones refunds")
	check(not SkillTree.can_refund_staged(tree, {}, {"witch.frost.needle": 2, "witch.frost.volley": 1}, "witch.frost.needle"), "refund that would orphan a staged volley is refused")
	check(not SkillTree.can_refund_staged(tree, {}, {"witch.frost.needle": 1}, "witch.common.vigor"), "refunding an uninvested node is refused")

	# ---- compile
	var empty := SkillTree.compile(tree, {})
	check(empty.skill.is_empty() and empty.hero.is_empty() and empty.rules.is_empty(), "empty ranks compile to an empty block")
	var needle3 := SkillTree.compile(tree, {"witch.frost.needle": 3})
	check(int(needle3.skill.add.pierce) == 2 and int(needle3.skill.add.hit_budget) == 8 and int(needle3.skill.mul_bps.damage_raw) == 10500 and needle3.rules.is_empty(), "needle rank 3 compiles to pierce +2, budget +8, damage x1.05, no synergy without the target")
	var lance := SkillTree.compile(tree, {"witch.frost.needle": 5, "witch.frost.volley": 3, "witch.frost.oath_lance": 2})
	check(int(lance.rules.elite_damage_bps) == 3000 + 5 * 300 and int(lance.skill.add.projectiles) == 2 and int(lance.skill.cooldown_bps) == 9200 and int(lance.skill.add.pierce) == 3, "needle -> oath lance synergy adds 3%p per needle rank")
	var control := SkillTree.compile(tree, {"witch.frost.rime": 5, "witch.frost.field": 3, "witch.frost.dominion": 2})
	check(int(control.rules.frost_field.radius_cm) == 400 and int(control.rules.frost_field.duration_ticks) == 180 and int(control.rules.frost_field_add.radius_cm) == 100 + 5 * 20 and int(control.rules.frost_field_add.max_fields) == 1 and int(control.rules.frost_field_add.slow_bps_at_least) == 6500 and int(control.skill.add.slow_bps) == 2500, "rime -> dominion synergy adds 0.2 m per rime rank; field and dominion blocks merge")
	var shatter := SkillTree.compile(tree, {"witch.frost.chill": 3, "witch.frost.shatter": 3, "witch.frost.cascade": 2})
	check(int(shatter.skill.at_most.freeze_stacks) == 2 and int(shatter.skill.at_least.shatter_count) == 4 and int(shatter.skill.add.shatter_count) == 2 + 2 and int(shatter.skill.at_least.proc_depth) == 1 and int(shatter.skill.at_least.hit_budget) == 16 and int(shatter.rules.shatter_radius_cm) == 100, "shatter branch: at_most freeze 2, at_least shatter 4, add 2+2, radius +1.0 m")
	var oath := SkillTree.compile(tree, {"witch.common.vigor": 5, "witch.common.ward": 3, "witch.common.favor": 2, "witch.frost.deep_oath": 1})
	check(int(oath.hero.max_hp) == 40 and int(oath.hero.damage_reduction_bps) == 900 and int(oath.hero.potion_start) == 1 and int(oath.rules.grace_rerolls) == 2 and int(oath.rules.start_rank) == 2 and oath.rules.evolve_without_passive == true, "oath branch: hero, grace rerolls, start rank, evolve flag")
	var synthetic := {"nodes": [
		{"id": "a", "ranks": [{"skill": {"mul_bps": {"damage_raw": 10500}, "cooldown_bps": 9600, "at_least": {"hit_budget": 8}, "at_most": {"freeze_stacks": 4}}}]},
		{"id": "b", "ranks": [{"skill": {"mul_bps": {"damage_raw": 10500}, "cooldown_bps": 9600, "at_least": {"hit_budget": 16}, "at_most": {"freeze_stacks": 3}}}]}]}
	var merged := SkillTree.compile(synthetic, {"a": 1, "b": 1})
	check(int(merged.skill.mul_bps.damage_raw) == 11025 and int(merged.skill.cooldown_bps) == 9216 and int(merged.skill.at_least.hit_budget) == 16 and int(merged.skill.at_most.freeze_stacks) == 3, "merge rules: multiply with integer floor, max of at_least, min of at_most")
	var odd := SkillTree.compile({"nodes": [{"id": "a", "ranks": [{"skill": {"mul_bps": {"damage_raw": 10333}}}]}, {"id": "b", "ranks": [{"skill": {"mul_bps": {"damage_raw": 10333}}}]}]}, {"a": 1, "b": 1})
	check(int(odd.skill.mul_bps.damage_raw) == 10677, "multiplication floors after each node (10333 x 10333 / 10000 = 10677)")
	var reversed_ranks := {}
	for id_ in ["witch.frost.oath_lance", "witch.frost.volley", "witch.frost.needle"]:
		reversed_ranks[id_] = 2
	var forward_ranks := {}
	for id_ in ["witch.frost.needle", "witch.frost.volley", "witch.frost.oath_lance"]:
		forward_ranks[id_] = 2
	check(SkillTree.compile(tree, reversed_ranks) == SkillTree.compile(tree, forward_ranks), "compile does not depend on the order of the ranks dictionary")

	# ---- describe
	check(str(SkillTree.describe(tree, "witch.frost.needle", 3)) == str(["관통 +2", "피해 +5%"]), "describe needle 3: " + str(SkillTree.describe(tree, "witch.frost.needle", 3)))
	check(str(SkillTree.describe(tree, "witch.frost.volley", 2)) == str(["창 +1발", "시전 간격 −4%"]), "describe volley 2: " + str(SkillTree.describe(tree, "witch.frost.volley", 2)))
	check(str(SkillTree.describe(tree, "witch.frost.chill", 3)) == str(["2번 맞으면 빙결"]), "describe chill 3")
	check(str(SkillTree.describe(tree, "witch.frost.field", 2)) == str(["서리 지대: 반경 3.5 m · 2.5초 · 감속 45%"]), "describe field 2: " + str(SkillTree.describe(tree, "witch.frost.field", 2)))
	check(str(SkillTree.describe(tree, "witch.common.ward", 3)) == str(["받는 피해 −9%", "시작 회복약 +1"]), "describe ward 3")
	check(str(SkillTree.describe(tree, "witch.frost.oath_lance", 1)) == str(["수호자·우두머리 피해 +15%"]), "describe oath lance 1")
	check(str(SkillTree.describe(tree, "witch.frost.deep_oath", 1)) == str(["서리창 랭크 2으로 시작", "결정 은총 없이 진화"]), "describe deep oath")
	check(SkillTree.describe(tree, "witch.frost.needle", 0).is_empty() and SkillTree.describe(tree, "witch.frost.needle", 6).is_empty() and SkillTree.describe(tree, "nope", 1).is_empty(), "describe of rank 0, rank above max or unknown node is empty")
	var hidden := true
	for id_ in nodes:
		for r in int(nodes[id_].max_rank):
			for line in SkillTree.describe(tree, id_, r + 1):
				hidden = hidden and not line.contains("budget") and not line.contains("예산")
			check(not SkillTree.describe(tree, id_, r + 1).is_empty(), "every node rank has a description: %s %d" % [id_, r + 1])
	check(hidden, "hit_budget is never shown")

	# ---- static power table
	var growth := read_json("res://chapter1/data/growth_quality37.json")
	var tuning := read_json("res://chapter1/data/combat_tuning.json")
	var lv20 := {"witch.frost.needle": 5, "witch.frost.volley": 3, "witch.frost.oath_lance": 3, "witch.common.vigor": 5, "witch.common.ward": 2, "witch.common.favor": 1}
	check(SkillTree.legal_ranks(tree, lv20, 20, 22).is_empty(), "the Lv 20 lance build used below is itself legal")
	var empty_table := SkillTree.power_table(tree, {}, growth, tuning)
	var full_table := SkillTree.power_table(tree, lv20, growth, tuning)
	check(not empty_table.has("error") and not full_table.has("error"), "power_table runs on the growth and tuning documents")
	check(is_equal_approx(float(empty_table.tree_ratio_r4), 1.0) and is_equal_approx(float(empty_table.stages.evo.ratio), 1.0), "an empty build changes nothing")
	check(int(empty_table.stages.r1.base.hits_per_cast) == 4 and int(empty_table.stages.r1.base.cooldown_ticks) == 54, "base rank 1 estimate with the shipped round-2 primary bonus: 4 hits per cast, 54 ticks (was 3 / 84 before 2026-11-16)")
	check(float(empty_table.grace_ratio_base) >= 4.0, "grace stays alive: base rank 1 -> 4 throughput ratio %.2f >= 4" % float(empty_table.grace_ratio_base))
	check(float(full_table.grace_ratio_build) >= 4.0, "grace stays alive with the Lv 20 lance build: ratio %.2f >= 4" % float(full_table.grace_ratio_build))
	check(float(full_table.stages.r4.ratio) > 1.0 and float(full_table.stages.r1.ratio) > 1.0, "the tree raises throughput at rank 1 and rank 4")
	print("POWER_TABLE ", JSON.stringify({"empty_grace_ratio": empty_table.grace_ratio_base, "lv20_lance_grace_ratio": full_table.grace_ratio_build,
		"lv20_lance_tree_ratio_r4": full_table.tree_ratio_r4, "lv20_lance_tree_ratio_r1": full_table.stages.r1.ratio, "lv20_lance_tree_ratio_evo": full_table.stages.evo.ratio}))
	finish(tree)

func finish(_tree: Variant) -> void:
	print("CHAPTER1_SKILL_TREE_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if not failures.is_empty() else 0)
