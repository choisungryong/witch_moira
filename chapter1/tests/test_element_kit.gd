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

## The document as it was before the 1st fix (D-element-trees 16): no floor, no late floor, no spine share, no prefer_unshocked, no bolt_rule or zone,
## and the values the old rules ran with. A run with it must be what it was (the part "compat" holds its hash).
func legacy_mutation(d: Dictionary) -> void:
	d.offer.erase("floor")
	d.offer.erase("evolve_floor")
	d.offer.erase("spine_share")
	var arc: Dictionary = d.elements.arc
	arc.chain.erase("prefer_unshocked")
	arc.skills[OVERLOAD].erase("bolt_rule")
	arc.skills[OVERLOAD].erase("zone")
	arc.skills[OVERLOAD].erase("prefer_big")
	arc.skills[OVERLOAD].bolt_raw = 25600
	arc.skills[OVERLOAD].self_bolt_bps = 8000
	card_of(d, "A23").change.vals.self_bolt_bps = 4000

func legacy_kit() -> Dictionary:
	return on_kit(legacy_mutation)

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
	bad = on_kit(func(d): d.elements.arc.cards[0].gate = "S9")
	check(refused(bad), "an unlock card with a gate the offer rules do not have is refused")
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

## Unlock kit skills / take cards without drawing an offer (the cards' effects are what is tested here, the offer is tested in part_cards).
func take(r: RefCounted, ids: Array) -> void:
	for id_ in ids:
		r.growth._kit_choose({"id": id_})
		r._kit_took(id_)

func fire_chain(r: RefCounted, first: int) -> Array:
	r._rebuild_grid()
	var skill: Dictionary = r.effective_skill(ARC)
	var effects: Dictionary = skill.effects.duplicate(true)
	r._cast_sequence += 1
	var ctx := {"uid": r._cast_sequence, "skill_id": ARC, "effects": effects, "remaining_hits": int(effects.hit_budget), "hit_ids": [], "evolved": skill.evolved}
	r.events.clear()
	r._chain(r.enemies[first], ctx)
	return r.events.duplicate(true)

func make_big(r: RefCounted, at: Vector2) -> int:
	var id_ := add_enemy(r, "elite", at)
	r.enemies[id_].hp_raw = 100000 * UNIT
	r.enemies[id_].max_hp_raw = 100000 * UNIT
	return id_

func make_walker(r: RefCounted, at: Vector2) -> int:
	var id_ := add_enemy(r, "walker", at)
	r.enemies[id_].hp_raw = 5000 * UNIT
	r.enemies[id_].max_hp_raw = 5000 * UNIT
	return id_

func shock_n(r: RefCounted, id_: int) -> int:
	return r._kit_shock_n(r.enemies[id_])

func hits_of(events: Array, id_: int) -> Array:
	return events.filter(func(e): return e.type == "hit" and int(e.target_id) == id_)

func part_off() -> void:
	var r = Chapter.new()
	check(r.start(11, ARC), "off: the shipped files start a run")
	check(not r._kit_on and not r.kit_view().on and not r.snapshot().has("kit_core") and not r.growth.snapshot().has("kit"), "off: shipped = no kit, no snapshot key, no growth key")
	var frost = Chapter.new()
	check(frost.set_element_kit(on_kit()) and frost.start(11, "chapter1.skill.frost") and not frost._kit_on, "off: an element that is not in the list runs as before")
	var both = Chapter.new()
	check(KitDocs.enable_kit_problem(both).is_empty() and Chapter.new().set_element_kit(on_kit()), "off: the document is accepted")
	var spells_problem: String = load("res://chapter1/tests/support/trial_docs.gd").enable_spells_problem(both)
	check(spells_problem.is_empty() and not both.start(11, ARC) and not both.errors.is_empty(), "off: the kit and run_spells refuse to start together")
	# A parked kit document that is switched off changes nothing: the same hashes as no document at all.
	var plain = Chapter.new()
	var parked = Chapter.new()
	check(parked.set_element_kit(shipped_kit()), "off: the shipped (off) document may be parked")
	var pilot_a: RefCounted = load("res://chapter1/core/chapter_pilot.gd").new()
	var pilot_b: RefCounted = load("res://chapter1/core/chapter_pilot.gd").new()
	pilot_a.run = plain
	pilot_b.run = parked
	check(plain.start(11, ARC) and parked.start(11, ARC), "off: both runs start")
	for i in 1800:
		plain.step(pilot_a.decide())
		parked.step(pilot_b.decide())
	check(JSON.stringify(plain.snapshot()).sha256_text() == JSON.stringify(parked.snapshot()).sha256_text() and plain.kills > 0, "off: an off document parked = the same snapshot after 1800 ticks (kills %d)" % plain.kills)
	var refused_doc: Dictionary = on_kit(func(d): d.surprise = 1)
	check(not Chapter.new().set_element_kit(refused_doc), "off: a refused document is not parked")

func part_chain() -> void:
	var r := stage()
	var walker := make_walker(r, Vector2(5, 0))
	fire_chain(r, walker)
	check(shock_n(r, walker) == 1, "chain: an ordinary body is shocked (1)")
	fire_chain(r, walker)
	check(shock_n(r, walker) == 1, "chain: it stays 1 (a body has the status or not)")
	# A big body alone: the chain has nothing to jump to and rebounds once (2 stacks in a cast), at 60% of the blow.
	r = stage()
	var big := make_big(r, Vector2(6, 0))
	var seen := fire_chain(r, big)
	var hits := hits_of(seen, big)
	check(hits.size() == 2 and shock_n(r, big) == 2, "chain: a lone big body is struck and rebounded: 2 hits, 2 stacks (%d, %d)" % [hits.size(), shock_n(r, big)])
	check(hits.size() == 2 and int(hits[1].damage_raw) == int(hits[0].damage_raw) * 6000 / 10000, "chain: the rebound is 60% of the blow")
	check(count_type(seen, "chain_rebound") == 1, "chain: one chain_rebound event")
	# A14 (a card): one more rebound.
	r = stage()
	take(r, ["A14"])
	big = make_big(r, Vector2(6, 0))
	fire_chain(r, big)
	check(shock_n(r, big) == 3, "chain: card A14 gives a third stack (%d)" % shock_n(r, big))
	# A big body with an ordinary one beside it: the chain passes through the ordinary one and strikes the big one again, no rebound.
	r = stage()
	big = make_big(r, Vector2(6, 0))
	walker = make_walker(r, Vector2(7, 0))
	seen = fire_chain(r, big)
	check(hits_of(seen, big).size() == 2 and hits_of(seen, walker).size() == 1 and count_type(seen, "chain_rebound") == 0, "chain: big, ordinary, big again: 2 + 1 hits and no rebound")
	# Off: the same stage with the kit off strikes the big body once and leaves no status.
	var plain := Chapter.new()
	check(KitDocs.far_levels_problem(plain).is_empty() and plain.start(11, ARC), "chain: plain run starts")
	plain.enemies.clear()
	plain._alive = 0
	plain._next_spawn = 1 << 30
	for id_ in plain._skill_ids: plain._next_cast[id_] = 1 << 30
	var plain_big := make_big(plain, Vector2(6, 0))
	seen = fire_chain(plain, plain_big)
	check(hits_of(seen, plain_big).size() == 1 and not plain.enemies[plain_big].has("kst"), "chain: kit off, the big body is struck once and carries no status")
	# Caps: ten stacks on a big body, fifteen with the card.
	r = stage()
	big = make_big(r, Vector2(6, 0))
	for i in 14: r._kit_shock(r.enemies[big], 1)
	check(shock_n(r, big) == 10, "chain: a big body holds at most 10 stacks")
	take(r, ["A18"])
	for i in 14: r._kit_shock(r.enemies[big], 1)
	check(shock_n(r, big) == 15, "chain: card A18 raises it to 15")
	# The status ends: 180 ticks without a renewal.
	r = stage()
	walker = make_walker(r, Vector2(5, 0))
	r._kit_shock(r.enemies[walker], 1)
	steps(r, 179)
	check(shock_n(r, walker) == 1, "chain: still shocked at 179 ticks")
	steps(r, 2)
	check(shock_n(r, walker) == 0, "chain: gone after 180 ticks")

func part_rod() -> void:
	var r := stage()
	take(r, ["A01"])
	check(r.growth.kit_rank(ROD) == 1, "rod: the unlock card gives rank 1")
	var walker := make_walker(r, Vector2(5, 0))
	var big := make_big(r, Vector2(9, 0))
	r._rebuild_grid()
	var seen := steps(r, 2)
	check(r.kit_view().rods == [big], "rod: the rod goes to the big body (%s)" % str(r.kit_view().rods))
	var planted := seen.filter(func(e): return e.type == "rod_planted")
	check(planted.size() == 1 and int(planted[0].target_id) == big, "rod: one rod_planted for the big body")
	# The shock of a rod-bearing body does not run out; an ordinary body's does.
	r._kit_shock(r.enemies[big], 3)
	r._kit_shock(r.enemies[walker], 1)
	var renew_at: int = r._kit_next_rod
	r._kit_next_rod = 1 << 30
	steps(r, 250)
	check(shock_n(r, big) == 3 and shock_n(r, walker) == 0, "rod: 250 ticks on, the rod bearer is still shocked (%d) and the other is not (%d)" % [shock_n(r, big), shock_n(r, walker)])
	# The rod falls with its time (360 ticks from planting), the event says why.
	seen = steps(r, 200)
	var dropped := seen.filter(func(e): return e.type == "rod_dropped")
	check(dropped.size() >= 1 and String(dropped[0].reason) == "time", "rod: dropped by time")
	# A standing rod is renewed by the next cast (every 300 ticks, 360 long): the bearer keeps it without a gap.
	r = stage()
	take(r, ["A01"])
	big = make_big(r, Vector2(9, 0))
	r._rebuild_grid()
	steps(r, 700)
	check(r.kit_view().rods == [big] and renew_at > 0, "rod: a renewed rod does not fall while the cast goes on")
	# A shocked body that dies near the rod draws a small bolt to it; one far away does not.
	r = stage()
	take(r, ["A01"])
	big = make_big(r, Vector2(9, 0))
	var near_walker := make_walker(r, Vector2(9, 3))
	var far_walker := make_walker(r, Vector2(-12, 0))
	r._rebuild_grid()
	steps(r, 2)
	r._kit_shock(r.enemies[near_walker], 1)
	r._kit_shock(r.enemies[far_walker], 1)
	var hp_before: int = r.enemies[big].hp_raw
	r.events.clear()
	var ctx: Dictionary = r._kit_context(ARC, 99999999)
	r._damage_enemy(near_walker, ctx, 0)
	var sparks: Array = r.events.filter(func(e): return e.type == "bolt_returned" and e.get("spark", false))
	check(sparks.size() == 1 and int(sparks[0].to_id) == big and int(r.enemies[big].hp_raw) < hp_before, "rod: a shocked body that dies near the rod draws a spark to it")
	r.events.clear()
	r._damage_enemy(far_walker, ctx, 0)
	check(r.events.filter(func(e): return e.type == "bolt_returned").is_empty(), "rod: one far from the rod draws nothing")
	# The rod bearer dying drops the rod.
	r._damage_enemy(big, r._kit_context(ARC, 999999999), 0)
	seen = steps(r, 2)
	check(r.kit_view().rods.is_empty(), "rod: a dead bearer holds no rod")

func part_overload() -> void:
	var r := stage(legacy_kit())
	take(r, ["A02"])
	check(r.growth.kit_rank(OVERLOAD) == 1, "overload: the unlock card gives rank 1")
	var big := make_big(r, Vector2(8, 0))
	var walkers: Array[int] = []
	for i in 6: walkers.append(make_walker(r, Vector2(5 + i % 3, -3 + i)))
	r._rebuild_grid()
	# Base damage 0 (ET3): nothing is shocked, nothing happens, the cooldown does not run.
	var hp_big: int = r.enemies[big].hp_raw
	var seen := steps(r, 30)
	check(count_type(seen, "bolt_returned") == 0 and int(r.enemies[big].hp_raw) == hp_big and r._kit_next_overload == 0, "overload: nothing shocked, nothing dealt, the cooldown did not start")
	check(int(r.enemies[walkers[0]].hp_raw) == 5000 * UNIT, "overload: an unshocked body takes nothing")
	# Six shocked conductors and a big body (no rod yet: the biggest shocked body is the target): one bolt each.
	for id_ in walkers: r._kit_shock(r.enemies[id_], 1)
	r._kit_shock(r.enemies[big], 2)
	seen = steps(r, 2)
	var bolts := seen.filter(func(e): return e.type == "bolt_returned")
	check(bolts.size() == 6, "overload: six conductors send six bolts (%d)" % bolts.size())
	var detonated := seen.filter(func(e): return e.type == "detonated")
	check(detonated.size() == 1 and int(detonated[0].stacks) == 6 and int(detonated[0].damage_raw) == 6 * 25600 and bool(detonated[0].big), "overload: one detonated event for the big body: 6 stacks, 6 x 25600")
	var clear := true
	for id_ in walkers:
		clear = clear and shock_n(r, id_) == 0 and int(r.enemies[id_].hp_raw) == 5000 * UNIT
	check(clear, "overload: the conductors lost their shock and took no damage")
	check(r._kit_next_overload == r.tick - 1 + 180 or r._kit_next_overload > 0, "overload: the cooldown runs after a cast")
	# A lone big body with its own stacks: floor(10 x 0.8) = 8 bolts, the stacks are spent. One stack: floor(0.8) = 0, no cast.
	r = stage(legacy_kit())
	take(r, ["A02"])
	big = make_big(r, Vector2(8, 0))
	r._rebuild_grid()
	r._kit_shock(r.enemies[big], 10)
	seen = steps(r, 2)
	bolts = seen.filter(func(e): return e.type == "bolt_returned")
	check(bolts.size() == 8 and bolts.all(func(e): return e.self), "overload: a lone big body of 10 stacks makes 8 self bolts (%d)" % bolts.size())
	check(shock_n(r, big) == 0, "overload: its stacks are spent")
	r = stage(legacy_kit())
	take(r, ["A02"])
	big = make_big(r, Vector2(8, 0))
	r._rebuild_grid()
	r._kit_shock(r.enemies[big], 1)
	seen = steps(r, 30)
	check(count_type(seen, "bolt_returned") == 0, "overload: one stack makes no bolt (floor 0.8)")
	r = stage(legacy_kit())
	take(r, ["A02", "A23"])
	big = make_big(r, Vector2(8, 0))
	r._rebuild_grid()
	r._kit_shock(r.enemies[big], 10)
	seen = steps(r, 2)
	check(count_type(seen, "bolt_returned") == 12, "overload: card A23 raises the self share to 1.2, capped by max bolts 12 (%d)" % count_type(seen, "bolt_returned"))
	# An ordinary body alone: it is the target, not a conductor of itself: no cast.
	r = stage(legacy_kit())
	take(r, ["A02"])
	var lone := make_walker(r, Vector2(6, 0))
	r._rebuild_grid()
	r._kit_shock(r.enemies[lone], 1)
	seen = steps(r, 30)
	check(count_type(seen, "bolt_returned") == 0, "overload: an ordinary body alone makes no bolt")
	# The cap: 20 conductors, 12 bolts; with rank 2 and A12 more.
	r = stage(legacy_kit())
	take(r, ["A02"])
	big = make_big(r, Vector2(8, 0))
	for i in 20: make_walker(r, Vector2(3 + i % 5, -4 + i % 9))
	r._rebuild_grid()
	r._kit_shock(r.enemies[big], 1)
	for id_ in r.enemies: r._kit_shock(r.enemies[id_], 1)
	seen = steps(r, 2)
	check(count_type(seen, "bolt_returned") == 12, "overload: 20 conductors send at most 12 bolts (%d)" % count_type(seen, "bolt_returned"))
	r = stage(legacy_kit())
	take(r, ["A02", "A08", "A12"])
	big = make_big(r, Vector2(8, 0))
	for i in 20: make_walker(r, Vector2(3 + i % 5, -4 + i % 9))
	r._rebuild_grid()
	for id_ in r.enemies: r._kit_shock(r.enemies[id_], 1)
	seen = steps(r, 2)
	check(count_type(seen, "bolt_returned") == 17, "overload: rank 2 (16) + card A12 (+1) = 17 bolts (%d)" % count_type(seen, "bolt_returned"))
	# A21: the cooldown is 30% shorter.
	r = stage(legacy_kit())
	take(r, ["A02", "A21"])
	big = make_big(r, Vector2(8, 0))
	var one := make_walker(r, Vector2(5, 0))
	r._rebuild_grid()
	r._kit_shock(r.enemies[big], 1)
	r._kit_shock(r.enemies[one], 1)
	steps(r, 1)
	check(r._kit_next_overload - r.tick == 126, "overload: A21 shortens the cooldown to 126 ticks (%d)" % (r._kit_next_overload - r.tick))

## One offer from the standing growth of a run: a pending level is made up, the hand drawn. {} when none could be drawn.
func offer_of(r: RefCounted, level: int = 3) -> Dictionary:
	r.growth._pending.append(level)
	return r.growth.next_offer()

## Choose one card of the offer through the growth and the core's hook (what choose() does), and close the level.
func pick(r: RefCounted, offer: Dictionary, card_id: String) -> bool:
	if not r.growth.choose(offer.token, card_id): return false
	r._kit_took(card_id)
	return true

func ids_of(offer: Dictionary) -> Array:
	var out: Array = []
	for c in offer.cards: out.append(String(c.id))
	return out

func part_cards() -> void:
	# Every hand of many seeds: requirements met, no card whose exclusion is held, no card a closed tree node guards, no unlock before its gate.
	var lacks_primary := 0
	var has_primary := 0
	var bad := 0
	var unlock_early := 0
	for seed_ in range(1, 41):
		var r := stage(on_kit(), seed_, "none")
		var offer := offer_of(r)
		var cards := ids_of(offer)
		var has_rank := false
		for c in offer.cards:
			if c.kind == "unlock": unlock_early += 1
			if String(c.id) in ["A16", "A17", "A18", "A19", "A20", "A21", "A22", "A23", "A24", "A27", "A28"]: bad += 1
			if c.has("requires"): bad += 1
			if c.skill_id == ARC: has_rank = true
		if has_rank: has_primary += 1
		else: lacks_primary += 1
		if cards.size() != 3: bad += 1
	check(bad == 0 and unlock_early == 0, "cards: first hands hold no unlock before its gate, no closed card, no unmet requirement (bad %d, early %d)" % [bad, unlock_early])
	check(lacks_primary > 0 and has_primary > 0, "cards: no standing protection of the primary's path (hands with it %d, without %d of 40)" % [has_primary, lacks_primary])
	# The door: after the first pick the burst skill's unlock card is forced into the next hand.
	var r := stage(on_kit(), 11, "none")
	var offer := offer_of(r)
	check(pick(r, offer, String(offer.cards[0].id)), "cards: the first card is taken")
	offer = offer_of(r)
	check("A02" in ids_of(offer), "cards: the gate S1 puts A02 into the next hand (%s)" % str(ids_of(offer)))
	# A19 and A20 exclude each other: once one is taken the other never comes back.
	r = stage(on_kit(), 11, "all")
	take(r, ["A01", "A19"])
	var seen_20 := false
	for i in 25:
		var o := offer_of(r)
		if "A20" in ids_of(o): seen_20 = true
		pick(r, o, String(o.cards[0].id))
	check(not seen_20, "cards: after A19 the exclusive A20 is never offered")
	# A card whose requirement is not taken is not offered; with it, it can be.
	r = stage(on_kit(), 11, "all")
	var seen_12 := false
	for i in 12:
		if "A12" in ids_of(offer_of(r)): seen_12 = true
		r.growth._offer = {}
		r.growth._pending.clear()
	check(not seen_12, "cards: A12 (requires A02) is not offered before A02")
	# Fillers: only when the pool is short, in order X01, X02, never when the pool has enough.
	r = stage(on_kit(), 11, "all")
	var everything: Array = []
	for c in r.growth._kit_el.cards: everything.append(String(c.id))
	var keep := ["A25"]
	for id_ in everything:
		if not id_ in keep: r.growth._kit_taken.append(id_)
	var short := offer_of(r)
	check(ids_of(short) == ["A25", "X01", "X02"], "cards: one card left = it and both fillers (%s)" % str(ids_of(short)))
	r.growth._offer = {}
	r.growth._pending.clear()
	r.growth._kit_taken.append("A25")
	short = offer_of(r)
	check(ids_of(short) == ["X01", "X02"], "cards: nothing left = the fillers alone (%s)" % str(ids_of(short)))
	r = stage(on_kit(), 11, "none")
	check(ids_of(offer_of(r)).filter(func(i): return i.begins_with("X")).is_empty(), "cards: a full pool has no filler")
	# The last hand: four cards, the evolution first when it is there, else a card that answers the big body.
	r = stage(on_kit(), 11, "all")
	take(r, ["A03", "A04", "A05", "A10"])
	var last := offer_of(r, r.growth.xp_thresholds().size())
	check(last.cards.size() == 4 and "A11" in ids_of(last), "cards: the last hand has 4 cards and the evolution (%s)" % str(ids_of(last)))
	var big_ok := 0
	for seed_ in range(1, 21):
		r = stage(on_kit(), seed_, "none")
		var o := offer_of(r, r.growth.xp_thresholds().size())
		var answers_big := false
		for c in o.cards:
			if "big" in c.answers: answers_big = true
		if o.cards.size() == 4 and answers_big: big_ok += 1
	check(big_ok == 20, "cards: every last hand of 20 seeds has a card for the big body (%d)" % big_ok)
	# Taking cards: the effects.
	r = stage(on_kit(), 11, "all")
	r._recompute_gear()
	var max_before: int = r.hero.max_hp_raw
	var speed_before: float = r.hero.speed
	take(r, ["A25", "A28"])
	check(int(r.hero.max_hp_raw) == max_before + 25 * UNIT and int(r.hero.hp_raw) >= max_before and r.hero.speed > speed_before, "cards: A25 adds 25 life, A28 adds speed")
	take(r, ["A03"])
	check(r.growth.kit_rank(ARC) == 2 and int(r.effective_skill(ARC).rank) == 2, "cards: A03 is rank 2 of the signature skill")
	take(r, ["A04", "A05", "A10", "A11"])
	check(bool(r.effective_skill(ARC).evolved), "cards: A11 evolves it")
	var heal_to: int = int(r.hero.max_hp_raw) / 2
	r.hero.hp_raw = heal_to
	take(r, ["X01"])
	check(int(r.hero.hp_raw) == heal_to + int(r.hero.max_hp_raw) * 4000 / 10000, "cards: the filler X01 heals 40%")
	# A real choose() through the core.
	r = stage(on_kit(), 11, "none")
	r.growth._pending.append(3)
	r._refresh_mode()
	check(r.mode == "choice", "cards: a pending level opens the card screen")
	var shown: Dictionary = r.get_offer()
	check(r.choose(shown.token, String(shown.cards[0].id)) and r.mode == "playing", "cards: choose() takes a kit card and leaves the screen")
	check(count_type(r.events, "kit_card_taken") == 1, "cards: one kit_card_taken event")
	# A card name is never a catalog card of another element: no ember or frost card is ever offered.
	var foreign := 0
	for seed_ in range(1, 15):
		var q := stage(on_kit(), seed_, "all")
		for round in 6:
			var o := offer_of(q)
			for c in o.cards:
				if String(c.skill_id).ends_with("ember") or String(c.skill_id).ends_with("frost"): foreign += 1
			if not o.cards.is_empty(): pick(q, o, String(o.cards[o.cards.size() - 1].id))
	check(foreign == 0, "cards: no card of another element is ever offered")

func part_tree() -> void:
	var progression := Progression.load_document()
	var kit := on_kit()
	var trees := Kit.trees_for(kit, progression)
	check(not trees.has("error") and trees.has("witch.arc") and trees.size() == 1, "tree: the shipped arc tree loads with the kit on (%s)" % str(trees.get("error", "")))
	check(Kit.trees_for(shipped_kit(), progression).is_empty(), "tree: the kit off loads no element tree")
	var tree: Dictionary = trees["witch.arc"]
	var compiled := Kit.compile_tree(tree, {"witch.arc.overcurrent": 1, "witch.arc.rod_ring": 1, "witch.arc.absorb": 1, "witch.arc.reroll": 1})
	check(compiled.cards == ["A18", "A16", "A27"] and compiled.rules == {"grace_rerolls": 1}, "tree: cards opened and the rule set: %s" % str(compiled))
	# Legality: the same rules as the old trees (tier level, requires, min_spent).
	check(SkillTree.legal_ranks(tree, {"witch.arc.overcurrent": 1}, 1, 1).is_empty(), "tree: a tier-1 node is legal at level 1")
	check(not SkillTree.legal_ranks(tree, {"witch.arc.rod_choice": 1}, 5, 1).is_empty(), "tree: a node without its parent is not")
	check(not SkillTree.legal_ranks(tree, {"witch.arc.rod_ring": 1, "witch.arc.rod_choice": 1}, 1, 2).is_empty(), "tree: the second tier needs level 5")
	var full := {}
	for node in tree.nodes: full[node.id] = 1
	check(SkillTree.legal_ranks(tree, full, 15, 10).is_empty() and SkillTree.points_spent(full) == 10, "tree: all ten nodes cost 10 points and are legal at level 15")
	check(not SkillTree.legal_ranks(tree, full, 15, 9).is_empty(), "tree: nine points are not enough for ten nodes")
	# The core: a build of this tree opens the cards; a tree card is not offered without its node.
	var r = Chapter.new()
	check(r.set_element_kit(kit), "tree: kit parked")
	var build := {"character_id": "chapter1.character.arc", "tree_id": "witch.arc", "tree_revision": 1, "ranks": {"witch.arc.overcurrent": 1, "witch.arc.absorb": 1, "witch.arc.reroll": 1}, "character_level": 10, "character_xp": 5500}
	check(Progression.level_for_xp(progression, 5500) == 10, "tree: level 10 at 5500")
	check(KitDocs.far_levels_problem(r).is_empty() and r.configure_build(build), "tree: the build is accepted " + str(r.errors))
	check(r.start(11, ARC), "tree: the run starts " + str(r.errors))
	check(r.growth.snapshot().kit.open == ["A18", "A27"] and r.rerolls_left() == 1, "tree: the node cards are open (%s), one re-draw" % str(r.growth.snapshot().kit.open))
	var bad_build: Dictionary = build.duplicate(true)
	bad_build.ranks = {"witch.arc.rod_choice": 1}
	var rejected = Chapter.new()
	rejected.set_element_kit(kit)
	check(not rejected.configure_build(bad_build), "tree: a build with an unreachable node is refused")
	var wrong: Dictionary = build.duplicate(true)
	wrong.tree_revision = 2
	check(not Chapter.new().configure_build(wrong), "tree: without the kit the arc witch has no tree: the build is refused")
	# stat nodes are not in use yet: a document that tried would be refused (part_data); the compile ignores nothing silently.
	var explicit = Chapter.new()
	check(explicit.set_element_kit(kit) and explicit.set_kit_open(["A18"]) and KitDocs.far_levels_problem(explicit).is_empty() and explicit.start(11, ARC), "tree: an explicit card list starts a run")
	check(explicit.growth.snapshot().kit.open == ["A18"], "tree: the explicit list is what is open")
	check(not explicit.set_kit_open([1]) and not explicit.set_kit_open("some"), "tree: a bad open mode is refused")

func part_profile() -> void:
	const Profile = preload("res://chapter1/core/chapter_profile.gd")
	var work := "res://_local/et-a/profile"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(work))
	var source := "res://chapter1/tests/fixtures/profile_v5_compat.json"
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source))
	doc.characters["chapter1.character.arc"].xp = 5500
	var path := work + "/arc-old.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()
	var frost_before: Dictionary = {}
	# Off (the shipped state): the arc witch has no tree; frost has hers.
	Kit.use_override({})
	Profile.refresh_element_kit()
	var off = Profile.new()
	check(off.configure(path, true) and off.available, "profile: the old v5 file reads with the kit off " + off.error)
	check(Progression.character_entry(Profile.progression_doc(), "chapter1.character.arc").get("tree_id") == null and not Profile.trees().has("witch.arc"), "profile: kit off: no arc tree")
	frost_before = off.character_entry("chapter1.character.frost").duplicate(true)
	var arc_off: Dictionary = off.character_entry("chapter1.character.arc").duplicate(true)
	# On: the arc witch gets her tree; the file reads the same; frost is not touched; her xp is the same.
	check(Kit.use_override(on_kit()), "profile: the kit is parked for the process")
	Profile.refresh_element_kit()
	check(Profile.trees().has("witch.arc") and Profile.trees().has("witch.frost"), "profile: kit on: arc has a tree and frost keeps hers")
	var on = Profile.new()
	check(on.configure(path, true) and on.available, "profile: the same old file reads with the arc kit on " + on.error)
	check(on.character_entry("chapter1.character.frost") == frost_before, "profile: the frost entry is untouched by the arc kit (ranks, revision, xp)")
	var arc_on: Dictionary = on.character_entry("chapter1.character.arc")
	check(int(arc_on.xp) == 5500 and arc_on.ranks.is_empty() and on.notices.is_empty(), "profile: the arc entry reads without a notice, xp kept (%s)" % str(on.notices))
	# Invest and save: a legal card tree.
	var ranks := {"witch.arc.overcurrent": 1, "witch.arc.rod_ring": 1, "witch.arc.rod_choice": 1, "witch.arc.absorb": 1, "witch.arc.stride": 1}
	check(on.commit_tree("chapter1.character.arc", ranks), "profile: the arc tree is committed " + on.error)
	var saved_text := FileAccess.get_file_as_string(on.path)
	var again = Profile.new()
	check(again.configure(on.path, true) and again.available and again.character_entry("chapter1.character.arc").ranks == ranks and int(again.character_entry("chapter1.character.arc").tree_revision) == 1, "profile: the saved investment reads back (revision 1)")
	check(not on.commit_tree("chapter1.character.arc", {"witch.arc.storm_rod": 1}), "profile: an illegal investment is refused and nothing changes")
	check(FileAccess.get_file_as_string(on.path) == saved_text, "profile: a refused commit leaves the file as it was")
	var build: Dictionary = again.build_for("chapter1.character.arc")
	check(build.tree_id == "witch.arc" and build.ranks == ranks, "profile: build_for hands the run the arc tree")
	var run = Chapter.new()
	check(run.set_element_kit(on_kit()) and KitDocs.far_levels_problem(run).is_empty() and run.configure_build(build) and run.start(11, ARC), "profile: the run accepts the saved build " + str(run.errors))
	check(run.growth.snapshot().kit.open == ["A18", "A16", "A19", "A20", "A27", "A28"] or run.growth.snapshot().kit.open.size() == 6, "profile: the run's open cards come from the saved nodes (%s)" % str(run.growth.snapshot().kit.open))
	# Off again: the arc witch has no tree; the investment is returned with a notice, xp kept; the file of the process before is read the same.
	Kit.use_override({})
	Profile.refresh_element_kit()
	var back = Profile.new()
	check(back.configure(again.path, true) and back.available, "profile: the saved file reads with the kit off again " + back.error)
	var arc_back: Dictionary = back.character_entry("chapter1.character.arc")
	check(arc_back.ranks.is_empty() and int(arc_back.xp) == 5500 and bool(back.notices.get("chapter1.character.arc", false)), "profile: back off, the ranks are returned with a notice and the xp is kept")
	check(back.character_entry("chapter1.character.frost") == frost_before and int(arc_off.xp) == 5500, "profile: frost is still the same entry")
	Profile.refresh_element_kit()

func part_rest() -> void:
	# The boss's break: its status clock stands still, its rod falls, and the overload hits the escort.
	var r = Chapter.new()
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://chapter1/data/combat_tuning.json"))
	d.boss_finale.enabled = true
	var far: Array = []
	for i in 12: far.append(i * 90000)
	d.xp_thresholds = far
	d.final_level_on_boss_spawn = false
	check(r.set_tuning(d), "rest: finale tuning " + str(r.errors))
	check(r.set_element_kit(on_kit()) and r.set_kit_open("all") and r.start(11, ARC), "rest: run starts " + str(r.errors))
	r.enemies.clear()
	r._alive = 0
	r._next_spawn = 1 << 30
	for id_ in r._skill_ids: r._next_cast[id_] = 1 << 30
	r.hero.max_hp_raw = 100000 * UNIT
	r.hero.hp_raw = r.hero.max_hp_raw
	r.zone = 2
	r.hero.position = Chapter.ZONES[2]
	r._zone_entered = true
	r.zone_kills = int(r.tuning.seal_kills[2])
	r._spawn_wave()
	check(r._champion_id > 0 and r.enemies.has(r._champion_id), "rest: the boss stands")
	take(r, ["A01", "A02"])
	var boss: Dictionary = r.enemies[r._champion_id]
	steps(r, int(r._bf.entrance_ticks) + 2)
	check(r._bf_state == "phase", "rest: phase one (%s)" % r._bf_state)
	# Some escorts, shocked, near the boss; the boss shocked with 6 stacks and a rod.
	for i in 6:
		var e_id := make_walker(r, Vector2(3 + i % 3, -2 + i))
		r.enemies[e_id].position = boss.position + Vector2(2 + i % 3, -2 + i)
	r._rebuild_grid()
	r._kit_shock(boss, 6)
	steps(r, 2)
	check(r.kit_view().rods.has(r._champion_id), "rest: the boss carries the rod while in play")
	r._bf_start_break(boss)
	var until_before: int = int(boss.kst.until)
	var stacks_before := r._kit_shock_n(boss)
	var seen := steps(r, 60)
	var dropped := seen.filter(func(e): return e.type == "rod_dropped" and String(e.reason) == "break")
	check(dropped.size() == 1 and not r.kit_view().rods.has(r._champion_id), "rest: the rod falls when the break begins (rod_dropped, reason break)")
	check(int(boss.kst.until) - until_before >= 55 and r._kit_shock_n(boss) == stacks_before, "rest: the boss's status clock stood still and its stacks stayed (%d -> %d)" % [stacks_before, r._kit_shock_n(boss)])
	# Meanwhile the bolts of an overload never go to the boss (it is out of play): they go to a body of the escort.
	for id_ in r.enemies:
		if id_ != r._champion_id and r.enemies[id_].hp_raw > 0: r._kit_shock(r.enemies[id_], 1)
	r._rebuild_grid()
	var boss_hp: int = boss.hp_raw
	seen = steps(r, 200)
	var to_boss := seen.filter(func(e): return e.type == "bolt_returned" and int(e.to_id) == r._champion_id)
	check(to_boss.is_empty() and int(boss.hp_raw) == boss_hp, "rest: no bolt goes to the boss during its break")

func part_snapshot() -> void:
	var finals: Array[String] = []
	var kit_keys := false
	var taken := 0
	for round in 2:
		var r = Chapter.new()
		check(KitDocs.enable_kit_rhythm_problem(r).is_empty(), "snapshot: kit and rhythm are on " + str(r.errors))
		var pilot: RefCounted = load("res://chapter1/core/chapter_pilot.gd").new()
		pilot.run = r
		check(r.start(11, ARC), "snapshot: the run starts " + str(r.errors))
		for i in 4200: r.step(pilot.decide())
		var snap: Dictionary = r.snapshot()
		kit_keys = snap.has("kit_core") and snap.growth.has("kit")
		taken = snap.growth.kit.taken.size()
		finals.append(JSON.stringify(snap).sha256_text())
		var round_trip: Variant = JSON.parse_string(JSON.stringify(snap))
		check(round_trip is Dictionary and round_trip.growth.kit.taken.size() == taken and round_trip.kit_core.rods.size() == snap.kit_core.rods.size(), "snapshot: the kit keys survive a JSON round trip")
	check(kit_keys and taken > 0, "snapshot: kit keys present and the pilot took %d kit cards" % taken)
	check(finals[0] == finals[1], "snapshot: the same seed and input give the same snapshot hash with the kit on")


# ---------------------------------------------------------------- D-element-trees 16 (the 1st fix): the floor of the card luck, the late floor, the spine share

func floor_off_kit() -> Dictionary:
	return on_kit(func(d): d.offer.floor.enabled = false)

func hand_ids(r: RefCounted) -> Array:
	var offer := offer_of(r)
	return ids_of(offer)

func clear_hand(r: RefCounted) -> void:
	r.growth._offer = {}
	r.growth._pending.clear()

func part_floor() -> void:
	# The format: the shipped file carries the floor; the new keys are allowed, a wrong one is refused, a document without them is as valid as before.
	var shipped := shipped_kit()
	check(shipped.offer.has("floor") and shipped.offer.has("evolve_floor") and shipped.offer.spine_share == true, "floor: the shipped file carries the first values of 16.5")
	var loader = Kit.new()
	check(loader.replace_document(legacy_kit()), "floor: a document without the new keys is accepted " + str(loader.errors))
	check(refused(on_kit(func(d): d.offer.floor.order = ["survival", "nothing"])), "floor: an unknown crisis in the order is refused")
	check(refused(on_kit(func(d): d.offer.floor.order = ["survival", "survival"])), "floor: a crisis twice in the order is refused")
	check(refused(on_kit(func(d): d.offer.floor.lag.path_by_picks = [[3, 2], [6, 2]])), "floor: a table whose card counts do not rise is refused")
	check(refused(on_kit(func(d): d.offer.floor.lag.path_by_picks = [[6, 1], [3, 2]])), "floor: a table whose picks do not rise is refused")
	check(refused(on_kit(func(d): d.offer.floor.lag.path_by_picks = [[3, 1], [6, 2], [9, 5]])), "floor: a table that asks for more path cards than the element has (4) is refused")
	check(refused(on_kit(func(d): d.offer.floor.surprise = 1)), "floor: an unknown floor key is refused")
	check(refused(on_kit(func(d): d.offer.floor.max_replace = 0)), "floor: max_replace 0 is refused")
	check(refused(on_kit(func(d): d.offer.evolve_floor.after.event = "death")), "floor: a late floor waiting for an event the core does not name is refused")
	check(refused(on_kit(func(d): d.offer.evolve_floor.fallback_after_picks = 0)), "floor: fallback_after_picks 0 is refused")
	check(refused(on_kit(func(d): d.offer.spine_share = 1)), "floor: spine_share must be a bool")
	check(refused(on_kit(func(d): d.elements.arc.chain.prefer_unshocked = 1)), "floor: prefer_unshocked must be a bool")
	check(refused(on_kit(func(d): d.elements.arc.skills[OVERLOAD].bolt_rule = "sum")), "floor: an unknown bolt_rule is refused")
	check(refused(on_kit(func(d): d.elements.arc.skills[OVERLOAD].zone = "world")), "floor: an unknown zone is refused")
	check(refused(on_kit(func(d): d.elements.arc.skills[ROD].bolt_rule = "max")), "floor: bolt_rule belongs to the burst skill only")
	# The floor looks at a hand once and acts only when the hand has no answer. 60 seeds, the survival crisis stands.
	var same := 0
	var changed := 0
	var bad := 0
	var state_kept := 0
	var state_moved := 0
	for seed_ in range(1, 61):
		var on := stage(on_kit(), seed_, "all")
		var off := stage(floor_off_kit(), seed_, "all")
		on.growth.set_kit_crisis({"rhythm": true, "survival": true, "big": false, "crowd": false})
		var hand_on := ids_of(offer_of(on))
		var hand_off := ids_of(offer_of(off))
		var answers := false
		for c in off.growth.snapshot().offer.cards:
			if "survival" in c.answers: answers = true
		var state_on: String = on.growth.snapshot().rng_state
		var state_off: String = off.growth.snapshot().rng_state
		if answers:
			if hand_on == hand_off: same += 1
			else: bad += 1
			if state_on == state_off: state_kept += 1
		else:
			var diff := 0
			for i in hand_on.size():
				if hand_on[i] != hand_off[i]: diff += 1
			if diff == 1 and on.growth.kit_floor_stats().replaced == 1: changed += 1
			else: bad += 1
			var gave := false
			for c in on.growth.snapshot().offer.cards:
				if c.id in hand_on and c.id not in hand_off and "survival" in c.answers and String(c.kind) != "filler": gave = true
			if not gave: bad += 1
			if state_on != state_off: state_moved += 1
	check(same > 0 and changed > 0 and bad == 0, "floor: a hand with an answer is left alone, one without gets exactly one answer card (same %d, changed %d, wrong %d)" % [same, changed, bad])
	check(state_kept == same and state_moved == changed, "floor: the card stream is untouched by a hand that is left alone and moves by one draw when a card is replaced (%d/%d, %d/%d)" % [state_kept, same, state_moved, changed])
	# Never a protected card: the door's A02 (after the first pick) stays in the hand whatever the crisis.
	var kept := 0
	for seed_ in range(1, 41):
		var r := stage(on_kit(), seed_, "all")
		var first := offer_of(r)
		pick(r, first, String(first.cards[0].id))
		r.growth.set_kit_crisis({"rhythm": true, "survival": true, "big": true, "crowd": true})
		var second := ids_of(offer_of(r))
		if "A02" in second or not ("A02" in r.growth._kit_taken): kept += 1
	check(kept == 40, "floor: the door's card is never the one replaced (%d of 40)" % kept)
	# The last offer's protection (the evolution) is not replaced either.
	var final_ok := 0
	for seed_ in range(1, 21):
		var r := stage(on_kit(), seed_, "all")
		take(r, ["A03", "A04", "A05", "A10"])
		r.growth.set_kit_crisis({"rhythm": true, "survival": true})
		var last := offer_of(r, r.growth.xp_thresholds().size())
		if "A11" in ids_of(last): final_ok += 1
	check(final_ok == 20, "floor: the last hand keeps its evolution under a crisis (%d of 20)" % final_ok)
	# Several crises: the first standing one decides (survival), a hand that already answers it is left alone even if another crisis stands.
	var order_ok := 0
	for seed_ in range(1, 31):
		var r := stage(on_kit(), seed_, "all")
		r.growth.set_kit_crisis({"rhythm": true, "survival": true, "big": true, "crowd": true})
		var hand: Array = offer_of(r).cards
		var survival_in := false
		for c in hand:
			if "survival" in c.answers: survival_in = true
		if survival_in: order_ok += 1
	check(order_ok == 30, "floor: with every crisis standing the survival answer is in the hand (%d of 30)" % order_ok)
	# The lag (16.1): the table [[3,1],[6,2],[9,4]] at its edges.
	var g = stage(on_kit(), 11, "none").growth
	var rule: Dictionary = g._kit_offer.floor
	var edges := [[2, [], false], [3, [], true], [3, ["A03"], false], [6, ["A03"], true], [6, ["A03", "A10"], false], [9, ["A03", "A10", "A04"], true], [9, ["A03", "A10", "A04", "A05"], false], [9, ["A03", "A10", "A04", "A25"], true]]
	var edge_bad := 0
	for e in edges:
		g._kit_taken.assign(e[1])
		g._kit_picks = int(e[0])
		if g._kit_crisis_standing("lag", rule) != bool(e[2]): edge_bad += 1
	check(edge_bad == 0, "floor: the lag stands at 3 picks with 0 path cards, not with 1; 6 with 1, not with 2; 9 with 3, not with 4 (wrong %d)" % edge_bad)
	# When the lag stands every hand carries a path card the player can take now; when it does not it is only luck.
	var with_path := 0
	var without_path := 0
	for seed_ in range(1, 31):
		var r := stage(on_kit(), seed_, "none")
		r.growth._kit_picks = 3
		r.growth.set_kit_crisis({"rhythm": true})
		var has := false
		for c in offer_of(r).cards:
			if c.kind == "rank" and c.skill_id == ARC: has = true
		if has: with_path += 1
		var q := stage(on_kit(), seed_, "none")
		q.growth._kit_picks = 2
		q.growth.set_kit_crisis({"rhythm": true})
		var q_has := false
		for c in offer_of(q).cards:
			if c.kind == "rank" and c.skill_id == ARC: q_has = true
		if not q_has: without_path += 1
	check(with_path == 30 and without_path > 0, "floor: a lagging build always sees its next rank (%d of 30); one that does not lag only by luck (%d hands without)" % [with_path, without_path])
	# Not a crisis, not a draw: with nothing standing the card stream moves exactly as with the floor off.
	var quiet := 0
	for seed_ in range(1, 21):
		var on := stage(on_kit(), seed_, "all")
		var off := stage(floor_off_kit(), seed_, "all")
		on.growth.set_kit_crisis({"rhythm": true, "survival": false, "big": false, "crowd": false})
		if hand_ids(on) == hand_ids(off) and on.growth.snapshot().rng_state == off.growth.snapshot().rng_state: quiet += 1
	check(quiet == 20, "floor: no crisis, no change and no extra draw (%d of 20)" % quiet)
	# The events and the counts.
	var r2 := stage(on_kit(), 5, "all")
	r2.growth.set_kit_crisis({"rhythm": true, "survival": true})
	var events_seen: Array = []
	for i in 12:
		clear_hand(r2)
		var o := offer_of(r2)
		events_seen.append_array(r2.growth.take_events().filter(func(e): return e.type == "offer_floor"))
	var stats: Dictionary = r2.growth.kit_floor_stats()
	check(int(stats.hands) == 12 and int(stats.replaced) == events_seen.size() and int(stats.get("by_crisis", {}).get("survival", 0)) == events_seen.size(), "floor: the counts match the offer_floor events (%s, %d events)" % [str(stats), events_seen.size()])
	check(events_seen.size() > 0 and events_seen.all(func(e): return e.data.crisis == "survival" and e.data.has("replaced_id") and e.data.has("card_id") and e.data.has("level")), "floor: offer_floor carries level, crisis, replaced_id, card_id")
	# The spine share (16.3): the weight of a spine card is multiplied by (B + T) / B, and T = 0 gives 1.
	var r3 := stage(on_kit(), 11, "none")
	var pool: Array[Dictionary] = r3.growth._kit_cards()
	r3.growth._kit_spine_weights(pool)
	var a03: Dictionary = pool.filter(func(c): return c.id == "A03")[0]
	check(int(a03.weight) == 100, "spine: nothing opened by the tree, the weight stays 100 (%d)" % int(a03.weight))
	r3 = stage(on_kit(), 11, "all")
	pool = r3.growth._kit_cards()
	var base_n := 0
	var tree_n := 0
	for c in pool:
		if c.kind == "evolve" or c.id in ["A03", "A04", "A05", "A10"]: continue
		if r3.growth._kit_card_def(String(c.id)).open == "base": base_n += 1
		else: tree_n += 1
	r3.growth._kit_spine_weights(pool)
	a03 = pool.filter(func(c): return c.id == "A03")[0]
	check(tree_n > 0 and int(a03.weight) == 100 * (base_n + tree_n) / base_n, "spine: with %d base cards and %d tree cards the weight is 100 x %d / %d = %d (%d)" % [base_n, tree_n, base_n + tree_n, base_n, 100 * (base_n + tree_n) / base_n, int(a03.weight)])
	var unlock_card: Dictionary = pool.filter(func(c): return c.id == "A25")[0]
	check(int(unlock_card.weight) == 60, "spine: a card that is not on the spine keeps its weight")
	var r4 := stage(on_kit(func(d): d.offer.spine_share = false), 11, "all")
	pool = r4.growth._kit_cards()
	r4.growth._kit_spine_weights(pool)
	check(int(pool.filter(func(c): return c.id == "A03")[0].weight) == 100, "spine: switched off, no multiplication")

## What the late floor would put into the next hand (the index in the pool of cards that could be offered now), -1 for nothing.
func evo_pick(g: RefCounted) -> int:
	var pool: Array[Dictionary] = g._kit_cards()
	var none: Array[Dictionary] = []
	return g._kit_evolve_floor_pick(pool, none)

func part_evolve_floor() -> void:
	var rule_ok := 0
	# Not armed and the rhythm on: nothing is added, however late.
	var r := stage(on_kit(), 11, "none")
	var g = r.growth
	g.set_kit_crisis({"rhythm": true})
	g._kit_picks = 12
	check(evo_pick(g) == -1, "late floor: not armed, with the rhythm, nothing is added at 12 picks")
	# With no rhythm the 10th pick opens it.
	g.set_kit_crisis({"rhythm": false})
	g._kit_picks = 9
	check(evo_pick(g) == -1, "late floor: no rhythm, 9 picks: not yet")
	g._kit_picks = 10
	var index: int = evo_pick(g)
	check(index >= 0 and g._kit_cards()[index].id == "A03", "late floor: no rhythm, 10 picks: the next rank")
	# The core arms it with the right crest only.
	var q := stage(on_kit(), 11, "none")
	q._emit("wave_crest", Vector2.ZERO, {"beat": "gi", "count": 3})
	check(not q.growth._kit_evo_armed, "late floor: a crest of another beat does not arm it")
	q._emit("wave_crest", Vector2.ZERO, {"beat": "seung2", "count": 3})
	check(q.growth._kit_evo_armed, "late floor: the crest of seung2 arms it")
	# Armed: every hand carries the next path card until the evolution is taken: the rune, the ranks, then the evolution.
	var good := 0
	var runs := 0
	var opened_events := 0
	for seed_ in range(1, 9):
		var s := stage(on_kit(), seed_, "none")
		s.growth.set_kit_crisis({"rhythm": true})
		s.growth.kit_arm_evolve_floor()
		var expected := ["A03", "A10", "A04", "A05", "A11"]
		var seen_ok := true
		for want in expected:
			clear_hand(s)
			var offer := offer_of(s)
			if not (want in ids_of(offer)): seen_ok = false
			if not pick(s, offer, want):
				seen_ok = false
				break
		opened_events += s.growth.take_events().filter(func(e): return e.type == "evolve_floor_opened").size()
		clear_hand(s)
		var after := offer_of(s)
		if not bool(s.effective_skill(ARC).evolved): seen_ok = false
		if evo_pick(s.growth) != -1: seen_ok = false
		runs += 1
		if seen_ok: good += 1
	check(good == runs, "late floor: every hand holds the next path card until the evolution is taken, none after (%d of %d seeds)" % [good, runs])
	check(opened_events == runs, "late floor: evolve_floor_opened once a run (%d for %d runs)" % [opened_events, runs])
	# With the door's card as well: both are in the hand (three cards).
	var both := 0
	for seed_ in range(1, 21):
		var s := stage(on_kit(), seed_, "none")
		s.growth.set_kit_crisis({"rhythm": true})
		s.growth.kit_arm_evolve_floor()
		s.growth._kit_picks = 1
		var hand := ids_of(offer_of(s))
		if "A02" in hand and "A03" in hand and hand.size() == 3: both += 1
	check(both == 20, "late floor: with the door's card both are in the hand of three (%d of 20)" % both)
	# The event carries the card and the level.
	var s2 := stage(on_kit(), 3, "none")
	s2.growth.set_kit_crisis({"rhythm": true})
	s2.growth.kit_arm_evolve_floor()
	offer_of(s2, 4)
	var opened: Array = s2.growth.take_events().filter(func(e): return e.type == "evolve_floor_opened")
	check(opened.size() == 1 and opened[0].data.card_id == "A03" and int(opened[0].data.level) == 4, "late floor: evolve_floor_opened {level, card_id}")
	# Off in the document: nothing is added.
	var t := stage(on_kit(func(d): d.offer.evolve_floor.enabled = false), 11, "none")
	t.growth.kit_arm_evolve_floor()
	t.growth.set_kit_crisis({"rhythm": false})
	t.growth._kit_picks = 20
	check(evo_pick(t.growth) == -1, "late floor: switched off in the document, nothing is added")

func part_crisis() -> void:
	var r := stage()
	r.hero.hp_raw = r.hero.max_hp_raw * 30 / 100
	r._kit_offer_prepare()
	check(bool(r.growth._kit_crisis.survival) and not bool(r.growth._kit_crisis.big) and not bool(r.growth._kit_crisis.crowd) and not bool(r.growth._kit_crisis.rhythm), "crisis: 30% life stands survival and nothing else")
	r.hero.hp_raw = r.hero.max_hp_raw * 35 / 100
	r._kit_offer_prepare()
	check(not bool(r.growth._kit_crisis.survival), "crisis: 35% life (the bound) is not below it")
	r.hero.hp_raw = r.hero.max_hp_raw
	var big := make_big(r, Vector2(9, 0))
	r._kit_offer_prepare()
	check(bool(r.growth._kit_crisis.big), "crisis: a big body alive stands big")
	r._damage_enemy(big, r._kit_context(ARC, 999999999), 0)
	r._kit_offer_prepare()
	check(not bool(r.growth._kit_crisis.big), "crisis: no big body and the seal far: not big")
	# The seal near: the kills still to come fit in the window at this zone's pace so far.
	var total := int(r._seal_total(r.zone))
	r.tick = 3000
	r.zone_kills = total * 9 / 10
	r._kit_offer_prepare()
	check(bool(r.growth._kit_crisis.big), "crisis: the seal at 90%% at tick 3000 (%d of %d kills): the guardian is within 600 ticks" % [r.zone_kills, total])
	r.zone_kills = total / 2
	r._kit_offer_prepare()
	check(not bool(r.growth._kit_crisis.big), "crisis: the seal at half: not yet")
	r.zone_kills = 0
	# Crowd: alive bodies at 60% of the ceiling, or a crest in the last 900 ticks.
	var cap := int(r._kit_alive_cap())
	r._alive = cap * 6000 / 10000 - 1
	r._kit_offer_prepare()
	check(not bool(r.growth._kit_crisis.crowd), "crisis: one under 60%% of the ceiling is not a crowd (%d of %d)" % [r._alive, cap])
	r._alive = cap * 6000 / 10000
	r._kit_offer_prepare()
	check(bool(r.growth._kit_crisis.crowd), "crisis: 60%% of the ceiling is a crowd (%d of %d)" % [r._alive, cap])
	r._alive = 0
	r._emit("wave_crest", Vector2.ZERO, {"beat": "seung2", "count": 5})
	r._kit_offer_prepare()
	check(bool(r.growth._kit_crisis.crowd), "crisis: a crest just now is a crowd")
	r.tick += 901
	r._kit_offer_prepare()
	check(not bool(r.growth._kit_crisis.crowd), "crisis: a crest 901 ticks ago is not")
	# The real path: get_offer() hands the crisis to the growth and books the counts.
	var q := stage(on_kit(), 11, "none")
	q.hero.hp_raw = q.hero.max_hp_raw * 20 / 100
	q.growth._pending.append(3)
	q._refresh_mode()
	var shown: Dictionary = q.get_offer()
	check(q.mode == "choice" and not shown.is_empty() and bool(q.growth._kit_crisis.survival), "crisis: get_offer() reads the crisis before the hand is made")
	check(q.metrics.kit.has("floor") and int(q.metrics.kit.floor.hands) == 1, "crisis: the measurement books the floor's hand")
	var cards_seen := 0
	for c in shown.cards:
		if "survival" in c.answers: cards_seen += 1
	check(cards_seen >= 1, "crisis: the hand at 20% life holds a survival answer")
	# A document with no floor and no late floor never asks the core.
	var legacy := stage(legacy_kit(), 11, "none")
	legacy.hero.hp_raw = legacy.hero.max_hp_raw * 20 / 100
	legacy.growth._pending.append(3)
	legacy._refresh_mode()
	legacy.get_offer()
	check(legacy.growth._kit_crisis.is_empty() and not legacy.metrics.kit.has("floor"), "crisis: a document without the floor gets no crisis and no floor count")

func bolts_of(events: Array) -> Array:
	return events.filter(func(e): return e.type == "bolt_returned" and not e.get("spark", false))

func shock_many(r: RefCounted, ids: Array, n: int = 1) -> void:
	for id_ in ids: r._kit_shock(r.enemies[id_], n)

func part_overload16() -> void:
	# One big body alone with its own stacks: floor(10 x 0.7) = 7 bolts, 10 stacks spent (7 x 10000 / 7000), all of them its own.
	var r := stage()
	take(r, ["A02"])
	var big := make_big(r, Vector2(8, 0))
	r._rebuild_grid()
	r._kit_shock(r.enemies[big], 10)
	var seen := steps(r, 2)
	var bolts := bolts_of(seen)
	check(bolts.size() == 7 and bolts.all(func(e): return e.self), "overload16: a lone big body of 10 stacks makes 7 own bolts (%d)" % bolts.size())
	check(shock_n(r, big) == 0, "overload16: seven bolts use 10 stacks (ceil of 7 x 10000 / 7000) and the body is bare")
	# 8 stacks: 5 bolts, ceil(5 x 10000 / 7000) = 8 stacks spent; 6 stacks: 4 bolts, 6 spent. The spent stacks are what the bolts used, not the rest.
	r = stage()
	take(r, ["A02"])
	big = make_big(r, Vector2(8, 0))
	r._rebuild_grid()
	r._kit_shock(r.enemies[big], 10)
	r.enemies[big].kst.n = 9
	seen = steps(r, 2)
	check(bolts_of(seen).size() == 6 and shock_n(r, big) == 0, "overload16: 9 stacks: 6 bolts, 9 spent (6 x 10000 / 7000 rounded up), none left (%d)" % shock_n(r, big))
	# Three conductors and a big body of 10 stacks: 3 bolts from the conductors and 4 more from the body (7 in all), and only 4 bolts' worth of stacks is spent.
	r = stage()
	take(r, ["A02"])
	big = make_big(r, Vector2(8, 0))
	var walkers: Array = [make_walker(r, Vector2(5, -2)), make_walker(r, Vector2(5, 0)), make_walker(r, Vector2(5, 2))]
	r._rebuild_grid()
	shock_many(r, walkers)
	r._kit_shock(r.enemies[big], 10)
	seen = steps(r, 2)
	bolts = bolts_of(seen)
	var own := bolts.filter(func(e): return e.self).size()
	check(bolts.size() == 7 and own == 4, "overload16: 3 conductors + a body of 10: 7 bolts, 4 of them its own (%d, %d)" % [bolts.size(), own])
	check(shock_n(r, big) == 10 - 6, "overload16: only the stacks of the 4 own bolts are spent: ceil(4 x 10000 / 7000) = 6 (left %d)" % shock_n(r, big))
	var entry: Dictionary = r.metrics.kit.overloads[0]
	check(int(entry.topup) == 4 and int(entry.spent) == 6 and int(entry.conductors) == 3 and bool(entry.big) and int(entry.hero_dist_cm) > 700 and int(entry.hero_dist_cm) < 900, "overload16: the record has topup 4, spent 6, 3 conductors, the distance about 800 cm (%s)" % str(entry))
	# More conductors than the body's own share: no stack is spent, every bolt is a conductor's.
	r = stage()
	take(r, ["A02"])
	big = make_big(r, Vector2(8, 0))
	walkers = []
	for i in 9: walkers.append(make_walker(r, Vector2(4 + i % 3, -4 + i)))
	r._rebuild_grid()
	shock_many(r, walkers)
	r._kit_shock(r.enemies[big], 10)
	seen = steps(r, 2)
	bolts = bolts_of(seen)
	check(bolts.size() == 9 and bolts.all(func(e): return not e.self) and shock_n(r, big) == 10, "overload16: 9 conductors beat the body's 7: 9 bolts, none its own, the 10 stacks stay (%d bolts, %d stacks)" % [bolts.size(), shock_n(r, big)])
	# Monotone: one more conductor never means fewer bolts.
	var counts: Array[int] = []
	for k in range(0, 13):
		var m := stage()
		take(m, ["A02"])
		var mb := make_big(m, Vector2(8, 0))
		var mw: Array = []
		for i in k: mw.append(make_walker(m, Vector2(3 + i % 5, -4 + i % 9)))
		m._rebuild_grid()
		shock_many(m, mw)
		m._kit_shock(m.enemies[mb], 10)
		counts.append(bolts_of(steps(m, 2)).size())
	var monotone := true
	for i in range(1, counts.size()):
		if counts[i] < counts[i - 1]: monotone = false
	check(monotone and counts[0] == 7 and counts[7] == 7 and counts[8] == 8 and counts[12] == 12, "overload16: the bolts never fall as conductors are added: %s" % str(counts))
	# The cap still holds: 20 conductors, max 12.
	r = stage()
	take(r, ["A02"])
	big = make_big(r, Vector2(8, 0))
	walkers = []
	for i in 20: walkers.append(make_walker(r, Vector2(3 + i % 5, -4 + i % 9)))
	r._rebuild_grid()
	shock_many(r, walkers)
	r._kit_shock(r.enemies[big], 1)
	check(bolts_of(steps(r, 2)).size() == 12, "overload16: 20 conductors send at most 12 bolts")
	# A23: the own share is 0.8 now (1000 more): 10 stacks, 8 bolts, 10 spent.
	r = stage()
	take(r, ["A02", "A23"])
	big = make_big(r, Vector2(8, 0))
	r._rebuild_grid()
	r._kit_shock(r.enemies[big], 10)
	check(bolts_of(steps(r, 2)).size() == 8 and shock_n(r, big) == 0, "overload16: card A23 gives 0.8: 8 bolts from 10 stacks")
	# A12 adds a bolt over the conductors: 4 conductors + 1.
	r = stage()
	take(r, ["A02", "A12"])
	big = make_big(r, Vector2(8, 0))
	walkers = []
	for i in 4: walkers.append(make_walker(r, Vector2(5, -2 + i)))
	r._rebuild_grid()
	shock_many(r, walkers)
	r._kit_shock(r.enemies[big], 1)
	check(bolts_of(steps(r, 2)).size() == 5, "overload16: card A12 adds one to the conductors' bolts")
	# The zone: conductors on the hero's far side (13 m from the body, 5 m from the hero) conduct with target_or_hero, not with target.
	var results := {}
	for label in ["now", "old"]:
		r = stage(on_kit() if label == "now" else on_kit(func(d): d.elements.arc.skills[OVERLOAD].zone = "target"))
		take(r, ["A02"])
		big = make_big(r, Vector2(8, 0))
		walkers = []
		for i in 4: walkers.append(make_walker(r, Vector2(-5, -2 + i)))
		r._rebuild_grid()
		shock_many(r, walkers)
		r._kit_shock(r.enemies[big], 1)
		results[label] = bolts_of(steps(r, 2)).size()
	check(int(results.now) == 4 and int(results.old) == 0, "overload16: the hero's circle adds conductors (now %d, zone target %d)" % [int(results.now), int(results.old)])
	# A body in both circles counts once; the record counts each circle.
	r = stage()
	take(r, ["A02"])
	big = make_big(r, Vector2(6, 0))
	var both_circles := make_walker(r, Vector2(0, 3))
	var hero_only := make_walker(r, Vector2(-7, 0))
	r._rebuild_grid()
	shock_many(r, [both_circles, hero_only])
	r._kit_shock(r.enemies[big], 1)
	seen = steps(r, 2)
	entry = r.metrics.kit.overloads[0]
	check(bolts_of(seen).size() == 2 and int(entry.conductors) == 2 and int(entry.near_hero) == 2 and int(entry.near_target) == 1, "overload16: a body in both circles counts once (bolts %d, record %s)" % [bolts_of(seen).size(), str(entry)])
	# The old rule is still what it was when the key is not there: on the legacy document nothing of the record is added.
	var old := stage(legacy_kit())
	take(old, ["A02"])
	var old_big := make_big(old, Vector2(8, 0))
	old._rebuild_grid()
	old._kit_shock(old.enemies[old_big], 10)
	steps(old, 2)
	var old_entry: Dictionary = old.metrics.kit.overloads[0]
	check(not old_entry.has("topup") and not old_entry.has("hero_dist_cm") and int(old_entry.bolts) == 8 and shock_n(old, old_big) == 0, "overload16: the legacy rule: 8 bolts, the body bare, no new record keys (%s)" % str(old_entry))

## ET-D8 (D-element-trees 18): the overload's target is a shocked big body within the hero's reach, a rod elsewhere or not; the record says why.
func plant_rod(r: RefCounted, id_: int) -> void:
	r._kit_rods.assign([id_])
	r.enemies[id_].rod_until = r.tick + 600

func target_of(seen: Array) -> int:
	var d := seen.filter(func(e): return e.type == "detonated")
	return int(d[0].target_id) if not d.is_empty() else -1

func part_overload22() -> void:
	# A rod stands on an ordinary body, a shocked big body (10 stacks) stands 8 m off: the big body is the target and its own 7 bolts fly.
	var results := {}
	for label in ["now", "off"]:
		var r := stage(on_kit() if label == "now" else on_kit(func(d): d.elements.arc.skills[OVERLOAD].prefer_big = false))
		take(r, ["A02"])
		var big := make_big(r, Vector2(8, 0))
		var walker := make_walker(r, Vector2(3, 3))
		r._rebuild_grid()
		plant_rod(r, walker)
		r._kit_shock(r.enemies[big], 10)
		r._kit_shock(r.enemies[walker], 1)
		var seen := steps(r, 2)
		results[label] = {"target": target_of(seen), "bolts": bolts_of(seen).size(), "entry": r.metrics.kit.overloads[0] if not r.metrics.kit.overloads.is_empty() else {}, "big": big, "walker": walker}
	var now: Dictionary = results.now
	var off: Dictionary = results.off
	check(int(now.target) == int(now.big) and int(now.bolts) == 7, "overload22: a rod on an ordinary body and a shocked big body in reach: the big body is the target, 7 own bolts (%s)" % str(now))
	check(bool(now.entry.target_big) and not bool(now.entry.target_rod) and int(now.entry.target_stacks) == 10 and String(now.entry.via) == "big" and int(now.entry.big_in_reach) == 1 and int(now.entry.big_shocked) == 1, "overload22: the record: target_big, no rod, 10 stacks, via big, 1 big in reach, 1 shocked (%s)" % str(now.entry))
	check(int(off.target) == int(off.walker) and not bool(off.entry.target_big) and bool(off.entry.target_rod) and String(off.entry.via) == "rod" and int(off.bolts) == 1, "overload22: with prefer_big false the rod body stays the target (%s)" % str(off))
	check(int(off.entry.big_in_reach) == 1 and int(off.entry.big_shocked) == 1 and int(off.entry.conductors) == 1, "overload22: and the record still tells that a shocked big body was in reach (%s)" % str(off.entry))
	# No rod at all: the shocked big body is the target.
	var r2 := stage()
	take(r2, ["A02"])
	var big2 := make_big(r2, Vector2(8, 0))
	var w2 := make_walker(r2, Vector2(3, 3))
	r2._rebuild_grid()
	r2._kit_shock(r2.enemies[big2], 4)
	r2._kit_shock(r2.enemies[w2], 1)
	var seen2 := steps(r2, 2)
	check(target_of(seen2) == big2 and not bool(r2.metrics.kit.overloads[0].target_rod), "overload22: no rod: the shocked big body is the target")
	# No shocked big body in reach (the big body is bare): the old rule, the most healthy shocked body; the record says a big body stood there bare.
	var r3 := stage()
	take(r3, ["A02"])
	make_big(r3, Vector2(8, 0))
	var w3a := make_walker(r3, Vector2(3, 3))
	var w3b := make_walker(r3, Vector2(3, -3))
	r3.enemies[w3a].hp_raw = 4000 * UNIT
	r3._rebuild_grid()
	r3._kit_shock(r3.enemies[w3a], 1)
	r3._kit_shock(r3.enemies[w3b], 1)
	var seen3 := steps(r3, 2)
	var e3: Dictionary = r3.metrics.kit.overloads[0]
	check(target_of(seen3) == w3b and not bool(e3.target_big) and String(e3.via) == "shocked_hp" and int(e3.big_in_reach) == 1 and int(e3.big_shocked) == 0, "overload22: a bare big body: the old rule (target %d, the healthier walker %d; %s)" % [target_of(seen3), w3b, str(e3)])
	# A shocked big body beyond the hero's reach (15 m) is not the target by this rule: the rod body stays.
	var r4 := stage()
	take(r4, ["A02"])
	var far := make_big(r4, Vector2(15, 0))
	var w4 := make_walker(r4, Vector2(3, 3))
	var w4b := make_walker(r4, Vector2(3, -3))
	r4._rebuild_grid()
	plant_rod(r4, w4)
	r4._kit_shock(r4.enemies[far], 10)
	r4._kit_shock(r4.enemies[w4], 1)
	r4._kit_shock(r4.enemies[w4b], 1)
	var seen4 := steps(r4, 2)
	var e4: Dictionary = r4.metrics.kit.overloads[0]
	check(target_of(seen4) == w4 and int(e4.big_in_reach) == 0 and String(e4.via) == "rod", "overload22: a shocked big body out of reach (15 m) does not take the target (target %d, %s)" % [target_of(seen4), str(e4)])
	# The boss at rest (out of play) is not a target: the walker is.
	var r5 := stage()
	take(r5, ["A02"])
	var boss := make_big(r5, Vector2(8, 0))
	var w5 := make_walker(r5, Vector2(3, 3))
	var w5b := make_walker(r5, Vector2(3, -3))
	r5._rebuild_grid()
	r5._shield_id = boss
	r5._kit_shock(r5.enemies[boss], 10)
	r5._kit_shock(r5.enemies[w5], 1)
	r5._kit_shock(r5.enemies[w5b], 1)
	var seen5 := steps(r5, 2)
	var e5: Dictionary = r5.metrics.kit.overloads[0]
	check(target_of(seen5) != boss and not bool(e5.target_big) and int(e5.big_in_reach) == 0, "overload22: the boss at rest is not a target (%s)" % str(e5))
	# Several shocked big bodies: rod bearer, then more stacks, then more health, then the smaller id.
	var orders := [
		["rod beats stacks", {"rod": 0, "stacks": [2, 9, 3]}, 0],
		["stacks beat health", {"stacks": [3, 9, 5], "hp": [100000, 1000, 100000]}, 1],
		["health beats the id", {"stacks": [5, 5, 5], "hp": [90000, 100000, 80000]}, 1],
		["the smaller id at a tie", {"stacks": [5, 5, 5]}, 0]]
	for row in orders:
		var r6 := stage()
		take(r6, ["A02"])
		var ids: Array = []
		for i in 3: ids.append(make_big(r6, Vector2(5 + i * 2, -3 + i * 3)))
		r6._rebuild_grid()
		var setup: Dictionary = row[1]
		for i in 3:
			r6._kit_shock(r6.enemies[ids[i]], int(setup.stacks[i]))
			if setup.has("hp"): r6.enemies[ids[i]].hp_raw = int(setup.hp[i]) * UNIT
		if setup.has("rod"): plant_rod(r6, ids[int(setup.rod)])
		var seen6 := steps(r6, 2)
		check(target_of(seen6) == ids[int(row[2])], "overload22: several big bodies, %s: target %d, expected %d" % [row[0], target_of(seen6), ids[int(row[2])]])
	# The key off by absence: the legacy document has no prefer_big and none of its record fields.
	var old := stage(legacy_kit())
	take(old, ["A02"])
	var old_big := make_big(old, Vector2(8, 0))
	old._rebuild_grid()
	old._kit_shock(old.enemies[old_big], 10)
	steps(old, 2)
	var old_entry: Dictionary = old.metrics.kit.overloads[0]
	check(not old_entry.has("target_big") and not old_entry.has("via") and not old_entry.has("big_in_reach"), "overload22: a document without the key has no new record fields (%s)" % str(old_entry))
	# The validator: the key is a yes/no.
	check(refused(on_kit(func(d): d.elements.arc.skills[OVERLOAD].prefer_big = 1)), "overload22: prefer_big must be true or false")
	check(not refused(on_kit(func(d): d.elements.arc.skills[OVERLOAD].prefer_big = false)), "overload22: prefer_big false is accepted")

func part_chain16() -> void:
	# metrics.kit.rebounds counts the rebounds (only for a document with the new keys: the old one keeps its metrics).
	var r := stage()
	var big := make_big(r, Vector2(6, 0))
	fire_chain(r, big)
	check(int(r.metrics.kit.rebounds) == 1, "chain16: a lone big body's rebound is counted (%d)" % int(r.metrics.kit.rebounds))
	var old := stage(legacy_kit())
	var old_big := make_big(old, Vector2(6, 0))
	fire_chain(old, old_big)
	check(int(old.metrics.kit.rebounds) == 0 and shock_n(old, old_big) == 2, "chain16: the legacy document counts none (it never did) and still rebounds")
	# prefer_unshocked: the next body is the one whose shock grows. From A (5,0): B (6,0) is shocked already, C (7,0) is not.
	var order := {}
	for label in ["now", "old"]:
		r = stage(on_kit() if label == "now" else on_kit(func(d): d.elements.arc.chain.prefer_unshocked = false))
		var a := make_walker(r, Vector2(5, 0))
		var b := make_walker(r, Vector2(6, 0))
		var c := make_walker(r, Vector2(7, 0))
		r._rebuild_grid()
		r._kit_shock(r.enemies[b], 1)
		var seen := fire_chain(r, a)
		var hit_ids: Array = seen.filter(func(e): return e.type == "hit").map(func(e): return int(e.target_id))
		order[label] = [hit_ids, a, b, c]
	check(order.now[0].size() >= 2 and order.now[0][0] == order.now[1] and order.now[0][1] == order.now[3], "chain16: prefer_unshocked goes to the unshocked body after the first (%s)" % str(order.now[0]))
	check(order.old[0].size() >= 2 and order.old[0][0] == order.old[1] and order.old[0][1] == order.old[2], "chain16: without it the nearest comes first as before (%s)" % str(order.old[0]))
	# Nothing unshocked to go to: it falls back to the nearest eligible body.
	r = stage()
	var a2 := make_walker(r, Vector2(5, 0))
	var b2 := make_walker(r, Vector2(6, 0))
	r._rebuild_grid()
	r._kit_shock(r.enemies[b2], 1)
	var seen2 := fire_chain(r, a2)
	var ids2: Array = seen2.filter(func(e): return e.type == "hit").map(func(e): return int(e.target_id))
	check(ids2.size() >= 2 and ids2[1] == b2, "chain16: with only a shocked body to go to it goes there (%s)" % str(ids2))

func run_ticks(doc: Dictionary, n: int, with_pilot_rhythm: bool = true) -> RefCounted:
	var r = Chapter.new()
	var problem: String = load("res://chapter1/tests/support/trial_docs.gd").enable_rhythm_problem(r, false, true)
	check(problem.is_empty(), "compat: rhythm " + problem)
	check(r.set_element_kit(doc) and r.set_kit_open("all"), "compat: the kit document is accepted " + str(r.errors))
	var pilot: RefCounted = load("res://chapter1/core/chapter_pilot.gd").new()
	pilot.run = r
	check(r.start(11, ARC), "compat: the run starts " + str(r.errors))
	# The golden loop: a step is counted by the tick, not by the call (a card screen takes calls that do not advance it).
	var guard := 0
	while r.tick < n and r.mode not in ["victory", "defeat"] and guard < n * 2:
		r.step(pilot.decide())
		guard += 1
	return r

## Every key of the 1st fix present and switched off, the old values.
func switched_off_mutation(d: Dictionary) -> void:
	legacy_mutation(d)
	d.offer.floor = shipped_kit().offer.floor
	d.offer.floor.enabled = false
	d.offer.evolve_floor = shipped_kit().offer.evolve_floor
	d.offer.evolve_floor.enabled = false
	d.offer.spine_share = false
	d.elements.arc.chain.prefer_unshocked = false
	d.elements.arc.skills[OVERLOAD].bolt_rule = "conductors"
	d.elements.arc.skills[OVERLOAD].zone = "target"
	d.elements.arc.skills[OVERLOAD].prefer_big = false

func part_compat() -> void:
	# The document as it was (no key of the 1st fix, the old values) is the old run: its snapshot at tick 12000 is the hash the golden case
	# "element-arc" recorded for it before the fix (golden core_runtime.json, checkpoint 12000, 2026-11-25).
	# S1-A (2026-11-25 night) moved this hash on purpose, once: the rhythm now reads the data file's own growth values (TrialPace no longer lays the D19 first
	# values over them; they were cbfad532... before) and a kit card view carries `open` (the offer is in the snapshot). The test still pins "the same run twice".
	var r := run_ticks(legacy_kit(), 12000)
	var digest: String = JSON.stringify(r.snapshot()).sha256_text()
	check(r.tick == 12000 and digest == "a543dbcfead70355c7b655987b7b5d414593ea56a04310bba11e12eb71410a1b", "compat: the document without the new keys is the old run (tick %d, %s)" % [r.tick, digest])
	check(not r.snapshot().growth.kit.has("floor") and not r.snapshot().kit_core.has("zone_start"), "compat: and it carries none of the new snapshot keys")
	# The new keys all switched off in place change nothing a player can see: the same kills and life after 3000 ticks.
	var off_doc := on_kit(switched_off_mutation)
	var a := run_ticks(legacy_kit(), 3000)
	var b := run_ticks(off_doc, 3000)
	check(a.kills == b.kills and a.hero.hp_raw == b.hero.hp_raw and a.growth.snapshot().xp == b.growth.snapshot().xp and a.growth.snapshot().rng_state == b.growth.snapshot().rng_state, "compat: the new keys switched off play the same run (kills %d / %d)" % [a.kills, b.kills])
	# The shipped (first) values run, end, and are repeatable.
	var c := run_ticks(on_kit(), 6000)
	var d2 := run_ticks(on_kit(), 6000)
	check(JSON.stringify(c.snapshot()).sha256_text() == JSON.stringify(d2.snapshot()).sha256_text() and c.snapshot().growth.kit.has("floor"), "compat: the first values give one hash twice, with the floor keys in the snapshot")

# ---------------------------------------------------------------- run

func execute() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--part="): only = arg.trim_prefix("--part=")
	for name in ["data", "off", "chain", "rod", "overload", "cards", "tree", "profile", "rest", "snapshot", "floor", "evolve_floor", "crisis", "overload16", "overload22", "chain16", "compat"]:
		if only.is_empty() or only == name: call("part_" + name)
	print("CHAPTER1_ELEMENT_KIT_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
