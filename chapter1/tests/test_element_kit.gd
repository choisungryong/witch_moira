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
	var r := stage()
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
	r = stage()
	take(r, ["A02"])
	big = make_big(r, Vector2(8, 0))
	r._rebuild_grid()
	r._kit_shock(r.enemies[big], 10)
	seen = steps(r, 2)
	bolts = seen.filter(func(e): return e.type == "bolt_returned")
	check(bolts.size() == 8 and bolts.all(func(e): return e.self), "overload: a lone big body of 10 stacks makes 8 self bolts (%d)" % bolts.size())
	check(shock_n(r, big) == 0, "overload: its stacks are spent")
	r = stage()
	take(r, ["A02"])
	big = make_big(r, Vector2(8, 0))
	r._rebuild_grid()
	r._kit_shock(r.enemies[big], 1)
	seen = steps(r, 30)
	check(count_type(seen, "bolt_returned") == 0, "overload: one stack makes no bolt (floor 0.8)")
	r = stage()
	take(r, ["A02", "A23"])
	big = make_big(r, Vector2(8, 0))
	r._rebuild_grid()
	r._kit_shock(r.enemies[big], 10)
	seen = steps(r, 2)
	check(count_type(seen, "bolt_returned") == 12, "overload: card A23 raises the self share to 1.2, capped by max bolts 12 (%d)" % count_type(seen, "bolt_returned"))
	# An ordinary body alone: it is the target, not a conductor of itself: no cast.
	r = stage()
	take(r, ["A02"])
	var lone := make_walker(r, Vector2(6, 0))
	r._rebuild_grid()
	r._kit_shock(r.enemies[lone], 1)
	seen = steps(r, 30)
	check(count_type(seen, "bolt_returned") == 0, "overload: an ordinary body alone makes no bolt")
	# The cap: 20 conductors, 12 bolts; with rank 2 and A12 more.
	r = stage()
	take(r, ["A02"])
	big = make_big(r, Vector2(8, 0))
	for i in 20: make_walker(r, Vector2(3 + i % 5, -4 + i % 9))
	r._rebuild_grid()
	r._kit_shock(r.enemies[big], 1)
	for id_ in r.enemies: r._kit_shock(r.enemies[id_], 1)
	seen = steps(r, 2)
	check(count_type(seen, "bolt_returned") == 12, "overload: 20 conductors send at most 12 bolts (%d)" % count_type(seen, "bolt_returned"))
	r = stage()
	take(r, ["A02", "A08", "A12"])
	big = make_big(r, Vector2(8, 0))
	for i in 20: make_walker(r, Vector2(3 + i % 5, -4 + i % 9))
	r._rebuild_grid()
	for id_ in r.enemies: r._kit_shock(r.enemies[id_], 1)
	seen = steps(r, 2)
	check(count_type(seen, "bolt_returned") == 17, "overload: rank 2 (16) + card A12 (+1) = 17 bolts (%d)" % count_type(seen, "bolt_returned"))
	# A21: the cooldown is 30% shorter.
	r = stage()
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

# ---------------------------------------------------------------- run

func execute() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--part="): only = arg.trim_prefix("--part=")
	for name in ["data", "off", "chain", "rod", "overload", "cards", "tree", "profile", "rest", "snapshot"]:
		if only.is_empty() or only == name: call("part_" + name)
	print("CHAPTER1_ELEMENT_KIT_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
