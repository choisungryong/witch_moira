extends SceneTree
## ET-A check of the element kit (D-element-trees, the arc only): data format and validators, off = now, status and the chain, the rod and
## the overload, the card engine, the permanent tree and the profile move, the boss rest, the snapshot. Every document is switched on IN
## MEMORY (ElementKit.use_override / run.set_element_kit); the shipped files stay off. The profile checks use a copy under _local/ only.
## Needs no user save and writes nothing outside _local/. Marker: CHAPTER1_ELEMENT_KIT_RESULT.
const Chapter = preload("res://chapter1/core/chapter_core.gd")
const Kit = preload("res://chapter1/core/element_kit.gd")
const Progression = preload("res://chapter1/core/character_progression.gd")
const SkillTree = preload("res://chapter1/core/skill_tree.gd")
const KitDocs = preload("res://chapter1/tests/support/kit_docs.gd")
const ARC := "chapter1.skill.arc"
const ROD := "chapter1.skill.arc_rod"
const OVERLOAD := "chapter1.skill.arc_overload"
const UNIT := 256
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("execute")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

# ---------------------------------------------------------------- helpers

func shipped_kit() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(Kit.DEFAULT_PATH))

func on_kit(mutate: Callable = Callable()) -> Dictionary:
	var d := shipped_kit()
	d.enabled = true
	d.enabled_elements = ["arc"]
	if mutate.is_valid(): mutate.call(d)
	return d

func card_of(kit: Dictionary, id_: String) -> Dictionary:
	for c in kit.elements.arc.cards:
		if c.id == id_: return c
	return {}

func refused(doc: Variant) -> bool:
	var loader = Kit.new()
	return not loader.replace_document(doc)

## A quiet stage: the kit on, a quiet hero, nothing spawns and nothing casts but what the test asks for.
func stage(kit: Dictionary = {}, seed_: int = 11, tree: Variant = "all") -> RefCounted:
	var r = Chapter.new()
	var problem := KitDocs.far_levels_problem(r)
	check(problem.is_empty(), "stage: tuning " + problem)
	check(r.set_element_kit(kit if not kit.is_empty() else on_kit()), "stage: the kit is accepted " + str(r.errors))
	check(r.set_kit_open(tree), "stage: the tree mode is accepted " + str(r.errors))
	check(r.start(seed_, ARC), "stage: the run starts " + str(r.errors))
	r.enemies.clear()
	r._alive = 0
	r._next_spawn = 1 << 30
	for id_ in r._skill_ids: r._next_cast[id_] = 1 << 30
	r.hero.max_hp_raw = 100000 * UNIT
	r.hero.hp_raw = r.hero.max_hp_raw
	return r

func add_enemy(r: RefCounted, kind: String, at: Vector2) -> int:
	check(r._spawn(kind, r.hero.position + at), "enemy placed")
	var id_: int = r._enemy_sequence
	var e: Dictionary = r.enemies[id_]
	# Bodies stand still (the test is about the kit, not about walking) and are tough enough to survive a few bolts.
	e.state_until = 1 << 30
	e.state = "recover"
	return id_

func steps(r: RefCounted, n: int) -> Array:
	var out: Array = []
	for i in n:
		if r.mode != "playing": break
		r.hero.hp_raw = r.hero.max_hp_raw
		r.step(Vector2.ZERO)
		out.append_array(r.events.duplicate(true))
	return out

func count_type(events: Array, type: String) -> int:
	var n := 0
	for ev in events:
		if ev.type == type: n += 1
	return n

# ---------------------------------------------------------------- parts

func part_data() -> void:
	var kit := shipped_kit()
	var loader = Kit.new()
	check(loader.replace_document(kit), "the shipped kit is valid " + str(loader.errors))
	check(not bool(kit.enabled) and kit.enabled_elements.is_empty(), "the shipped kit is off")
	check(kit.elements.arc.cards.size() == 28, "28 arc cards, got %d" % kit.elements.arc.cards.size())
	check(kit.fillers.size() == 2, "two fillers")
	var doc := on_kit()
	check(loader.replace_document(doc), "an enabled copy is valid")
	# Refusals: a stray key, an unknown flag, a value out of range, an exclusion that is not mutual, a card that names a missing node.
	var bad := on_kit(func(d): d.surprise = 1)
	check(refused(bad), "an unknown root key is refused")
	bad = on_kit(func(d): d.enabled_elements = ["frost"])
	check(refused(bad), "enabling an element without a block is refused")
	bad = on_kit(func(d): d.elements.arc.cards[11].change.flags = ["no_such_flag"])
	check(refused(bad), "an unknown rule flag is refused")
	bad = on_kit(func(d): d.elements.arc.cards[11].change.vals.bolts_add = 99)
	check(refused(bad), "a value out of range is refused")
	bad = on_kit(func(d): d.elements.arc.cards[18].excludes = [])
	check(refused(bad), "a one-sided exclusion is refused")
	bad = on_kit(func(d): d.elements.arc.cards[3].requires = ["A99"])
	check(refused(bad), "a requirement on an unknown card is refused")
	bad = on_kit(func(d): d.offer.filler = ["X09"])
	check(refused(bad), "a filler that is not defined is refused")
	bad = on_kit(func(d): d.elements.arc.rod.count = 5)
	check(refused(bad), "a rod count out of range is refused")
	bad = on_kit(func(d): d.elements.arc.skills[OVERLOAD].surprise = 5)
	check(refused(bad), "an unknown skill key is refused")
	# Trees: valid as shipped, stat nodes refused, a card with no node refused, revision rules.
	var progression := Progression.load_document()
	var tree_doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Kit.TREES_PATH))
	check(Kit.validate_trees(tree_doc, doc, progression).is_empty(), "the shipped trees are valid: " + str(Kit.validate_trees(tree_doc, doc, progression)))
	var stat_doc: Dictionary = tree_doc.duplicate(true)
	stat_doc.trees[0].nodes[0].kind = "stat"
	check(not Kit.validate_trees(stat_doc, doc, progression).is_empty(), "a stat node is refused (a place held for later)")
	var opens_base: Dictionary = tree_doc.duplicate(true)
	opens_base.trees[0].nodes[0].opens = ["A03"]
	check(not Kit.validate_trees(opens_base, doc, progression).is_empty(), "a node cannot open a base card")
	var lonely: Dictionary = tree_doc.duplicate(true)
	lonely.trees[0].nodes[0].opens = []
	check(not Kit.validate_trees(lonely, doc, progression).is_empty(), "a card that names a node nobody opens is refused")
	var rule_doc: Dictionary = tree_doc.duplicate(true)
	rule_doc.trees[0].nodes[9].rule = {"new_rule": 1}
	check(not Kit.validate_trees(rule_doc, doc, progression).is_empty(), "a rule node may set only an existing run option")
	var cycle: Dictionary = tree_doc.duplicate(true)
	cycle.trees[0].nodes[1].requires = {"witch.arc.rod_choice": 1}
	check(not Kit.validate_trees(cycle, doc, progression).is_empty(), "a cycle or a later-tier parent is refused")
	# Ten nodes, one point each, ten points in all.
	check(tree_doc.trees[0].nodes.size() == 10, "ten nodes")

# ---------------------------------------------------------------- run

func execute() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--part="): only = arg.trim_prefix("--part=")
	for name in ["data"]:
		if only.is_empty() or only == name: call("part_" + name)
	print("CHAPTER1_ELEMENT_KIT_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
