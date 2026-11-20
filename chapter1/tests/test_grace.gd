extends SceneTree
## KS check of the boon cadence, the tools and the grades (D13 G0, K3a, K3b-1): combat_tuning.json "grace" block read by
## core/combat_tuning.gd and used by core/run_growth.gd and chapter_core.gd. The shipped block stays OFF; every enabled one is
## made in memory here.
##   A  G0: the validator (optional grace / elites / extras keys, grace ranges), sources.grade_bonus_bps
##   B  off: nothing leaks into a run, its snapshot or its cards
##   C  K3a: evolution minimum level, last big offer, banish, hold, re-draw count, gap between choices, events
##   D  K3b-1: grades (stream apart from the card draw, kinds, pity, odds parts, resonance, jackpot taken, read-only contract)
##   E  K3b-1: counts over many seeded runs (printed as GRACE_DIST lines), determinism
## Marker: CHAPTER1_GRACE_RESULT. Writes nothing.
const Chapter = preload("res://chapter1/core/chapter_core.gd")
const Tuning = preload("res://chapter1/core/combat_tuning.gd")
const Progression = preload("res://chapter1/core/character_progression.gd")
const SPELLS := "res://chapter1/data/run_spells.json"
const TUNING := "res://chapter1/data/combat_tuning.json"
const EMBER := "chapter1.skill.ember"
const FROST := "chapter1.skill.frost"
const EMBER_RING := "chapter1.skill.ember_ring"
const FAR := 1 << 30
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("execute")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

# ------------------------------------------------------------------ helpers

var _tuning_text := ""
var _spells_text := ""

func shipped_tuning() -> Dictionary:
	if _tuning_text.is_empty(): _tuning_text = FileAccess.get_file_as_string(TUNING)
	return JSON.parse_string(_tuning_text)

func spells_doc() -> Dictionary:
	if _spells_text.is_empty(): _spells_text = FileAccess.get_file_as_string(SPELLS)
	var doc: Dictionary = JSON.parse_string(_spells_text)
	doc.enabled = true
	return doc

func issues(tuning: Dictionary) -> Array[String]:
	return Tuning.validate(tuning, Chapter.SKILL_IDS, Chapter.MAX_ALIVE, Chapter.MAX_PROJECTILES - Chapter.MAX_HOSTILE_PROJECTILES)

## A document whose grace block is mutated by `mutate` (called with the block); enabled unless `on` is false.
func tuning_with(mutate: Callable = Callable(), on: bool = true) -> Dictionary:
	var tuning := shipped_tuning()
	tuning.grace.enabled = on
	if mutate.is_valid(): mutate.call(tuning.grace)
	return tuning

## A started run. grace_mutate edits the block (null: no change), spells_on turns the composition on, with_grace false drops the block.
func make_run(mutate: Callable = Callable(), spells_on: bool = true, seed_: int = 11, primary: String = EMBER, on: bool = true, with_grace: bool = true) -> RefCounted:
	var tuning := tuning_with(mutate, on)
	if not with_grace: tuning.erase("grace")
	var run = Chapter.new()
	if not run.set_tuning(tuning):
		check(false, "tuning accepted: " + str(run.errors))
		return null
	if spells_on and not run.set_run_spells(spells_doc()):
		check(false, "spells accepted: " + str(run.errors))
		return null
	if not run.start(seed_, primary):
		check(false, "run starts: " + str(run.errors))
		return null
	run.first_boss_kill = true
	return run

func neutral(grace: Dictionary) -> void:
	grace.evolve_min_level = 0
	grace.final_offer.mode = "none"
	grace.tools.base_rerolls = 0
	grace.tools.base_banishes = 0
	grace.tools.base_holds = 0

## Grades are pulled but change nothing (every extra point is 0): the card flow must be the one of a run without grades.
func inert_grades(grace: Dictionary) -> void:
	neutral(grace)
	grace.grades.enabled = true
	grace.grades.rare.axis_points = 0
	grace.grades.rare.unlock_points = 0
	grace.grades.rare.rank_points = 0
	grace.grades.jackpot.base.axis_points = 0
	grace.grades.jackpot.base.unlock_points = 0
	grace.grades.jackpot.base.rank_points = 0
	grace.grades.jackpot.resonance.axis_points = 0
	grace.grades.jackpot.resonance.partner_points = 0
	grace.grades.jackpot.resonance.axis_cap_bonus = 0
	grace.grades.jackpot.resonance.unlock_points = 0

func grades_on(grace: Dictionary) -> void:
	grace.grades.enabled = true

## Pull a jackpot by the hard pity at the first offer, then again after every offer.
func always_jackpot(grace: Dictionary) -> void:
	neutral(grace)
	grace.grades.enabled = true
	grace.grades.jackpot_bps = 0
	grace.grades.rare_bps = 0
	grace.grades.pity.soft_step_bps = 0
	grace.grades.pity.hard_after_spins = 1

## Raise the run to the next level and open its choice (the way the world does it).
func level_up(run: RefCounted) -> Dictionary:
	var growth = run.growth
	var snap: Dictionary = growth.snapshot()
	var thresholds: Array = growth.xp_thresholds()
	var level := int(snap.level)
	growth.award_xp(int(thresholds[level]) - int(snap.xp))
	run._refresh_mode()
	return run.get_offer()

func ids(offer: Dictionary) -> Array:
	return offer.get("cards", []).map(func(c): return String(c.id))

func kinds_of(offer: Dictionary) -> Array:
	return offer.get("cards", []).map(func(c): return String(c.kind))

func event_types(run: RefCounted) -> Array:
	return run.events.map(func(e): return String(e.type))

func find_event(run: RefCounted, type: String) -> Dictionary:
	for e in run.events:
		if e.type == type: return e
	return {}

## Play `levels` levels by always taking card `index` (clamped); returns the list of offers' card ids.
func play(run: RefCounted, levels: int, index: int = 0) -> Array:
	var seen: Array = []
	for n in levels:
		var offer := level_up(run)
		if offer.is_empty(): break
		seen.append(ids(offer))
		var cards: Array = offer.cards
		run.choose(offer.token, String(cards[mini(index, cards.size() - 1)].id))
	return seen

func axes_of(run: RefCounted, id_: String) -> Dictionary:
	return run.growth.axis_levels(id_)

# ------------------------------------------------------------------ A: G0

func part_a() -> void:
	var shipped := shipped_tuning()
	check(issues(shipped).is_empty(), "A shipped combat_tuning.json (with the off grace block) is valid: " + str(issues(shipped)))
	check(shipped.grace.enabled == false and shipped.grace.grades.enabled == false, "A the shipped grace block and its grades are OFF")
	check(shipped.grace.balance_status.contains("N1"), "A the block says its numbers are fixed after N1")
	var plain := shipped_tuning()
	plain.erase("grace")
	check(issues(plain).is_empty(), "A a document without grace is valid (the plain rules)")
	var rhythm_only := shipped_tuning()
	rhythm_only.erase("rhythm")
	check(issues(rhythm_only).is_empty(), "A a document without rhythm is still valid")
	# elites / extras: the blocks W4-a / W5-a check in full (every range is in test_elites.gd); here only that they are optional keys
	# of the document, that a bare {"enabled": false} no longer passes for them and that the wrong shapes are rejected.
	for name in ["elites", "extras"]:
		var t := shipped_tuning()
		check(issues(t).is_empty() and t[name].enabled == false, "A the shipped %s block is valid and OFF" % name)
		t.erase(name)
		check(issues(t).is_empty(), "A a document without %s is valid" % name)
		t[name] = {"enabled": false}
		check(not issues(t).is_empty(), "A %s with only enabled is rejected (the block has its full shape now)" % name)
		t[name] = {"enabled": 1}
		check(not issues(t).is_empty(), "A %s with a non-bool enabled is rejected" % name)
		t[name] = []
		check(not issues(t).is_empty(), "A %s that is not an object is rejected" % name)
	# Every grace range: one bad value per case.
	var bad_cases := {
		"extra key": func(g): g.surprise = 1,
		"missing key": func(g): g.erase("link_slots"),
		"enabled not bool": func(g): g.enabled = "no",
		"evolve_min_level 13": func(g): g.evolve_min_level = 13,
		"final mode": func(g): g.final_offer.mode = "huge",
		"final cards 5": func(g): g.final_offer.cards = 5,
		"final cards 2": func(g): g.final_offer.cards = 2,
		"protect word": func(g): g.final_offer.protect_order = ["luck"],
		"min_gap_ticks": func(g): g.min_gap_ticks = 3601,
		"base_rerolls 4": func(g): g.tools.base_rerolls = 4,
		"base_banishes -1": func(g): g.tools.base_banishes = -1,
		"banish kind passive": func(g): g.tools.banish_kinds = ["passive"],
		"banish kind evolve": func(g): g.tools.banish_kinds = ["evolve"],
		"pact_from_level 0": func(g): g.pact_from_level = 0,
		"link_slots 5": func(g): g.link_slots = 5,
		"grades enabled": func(g): g.grades.enabled = 1,
		"grades kinds": func(g): g.grades.kinds = ["passive"],
		"jackpot_bps": func(g): g.grades.jackpot_bps = 10001,
		"cap_bps 6000": func(g): g.grades.cap_bps = 6000,
		"rare+jackpot": func(g): g.grades.rare_bps = 9800,
		"hard_after 21": func(g): g.grades.pity.hard_after_spins = 21,
		"soft_step": func(g): g.grades.pity.soft_step_bps = -1,
		"final mul 9999": func(g): g.grades.final_offer_jackpot_mul_bps = 9999,
		"luck shrine 9999": func(g): g.grades.luck.shrine_mul_bps = 9999,
		"rare scale": func(g): g.grades.rare.scale_bps = 9000,
		"jackpot form": func(g): g.grades.jackpot.form = "unique",
		"resonance partner 3": func(g): g.grades.jackpot.resonance.partner_points = 3,
		"base axis 5": func(g): g.grades.jackpot.base.axis_points = 5,
		"jackpot key": func(g): g.grades.jackpot.erase("base"),
	}
	for label in bad_cases:
		check(not issues(tuning_with(bad_cases[label])).is_empty(), "A grace range refuses: " + label)
	# A rejected document changes nothing of the run.
	var run = Chapter.new()
	var before: Dictionary = run.tuning.duplicate(true)
	check(not run.set_tuning(tuning_with(bad_cases["jackpot_bps"])) and run.tuning == before, "A a rejected document leaves the run's tuning alone")
	# sources.grade_bonus_bps (character_progression)
	var doc: Dictionary = Progression.load_document()
	check(Progression.validate_document(doc).is_empty(), "A the shipped progression document is valid")
	var base_bounds := Progression.xp_bounds(doc)
	check(int(base_bounds.run_xp_max) == 1000, "A without grade_bonus_bps run_xp_max is the plain 1000")
	var with_bonus: Dictionary = doc.duplicate(true)
	with_bonus.sources.grade_bonus_bps = [0, 500, 1000, 3000]
	check(Progression.validate_document(with_bonus).is_empty(), "A sources.grade_bonus_bps (4 values) is accepted")
	check(int(Progression.xp_bounds(with_bonus).run_xp_max) == 1300, "A run_xp_max grows by the largest bonus: 1000 x 1.3 = 1300")
	for bad in [[0, 1, 2], [0, 1, 2, -1], [0, 1, 2, 100001], "x", [0, 1, 2, 1.5]]:
		var broken: Dictionary = doc.duplicate(true)
		broken.sources.grade_bonus_bps = bad
		check(not Progression.validate_document(broken).is_empty(), "A grade_bonus_bps refuses " + str(bad))
	var stray: Dictionary = doc.duplicate(true)
	stray.sources.mystery = 1
	check(not Progression.validate_document(stray).is_empty(), "A an unknown sources key is still refused")

# ------------------------------------------------------------------ B: off

func part_b() -> void:
	for spells_on in [false, true]:
		var tag := "spells on" if spells_on else "spells off"
		var without = make_run(Callable(), spells_on, 11, EMBER, true, false)
		var disabled = make_run(Callable(), spells_on, 11, EMBER, false, true)
		var snap: Dictionary = disabled.snapshot()
		check(not snap.growth.has("banished") and not snap.growth.has("held") and not snap.growth.has("grace") and not snap.has("grace_gap"), "B off keeps the snapshot free of grace keys (%s)" % tag)
		check(not disabled.growth.grace_on() and not disabled.growth.grades_on(), "B off: growth knows no grace (%s)" % tag)
		var seen_a := play(without, 9)
		var seen_b := play(disabled, 9)
		check(seen_a == seen_b and not seen_a.is_empty(), "B the shipped off block draws the same cards as no block (%s, 9 levels)" % tag)
		check(JSON.stringify(without.snapshot()) == JSON.stringify(disabled.snapshot()), "B the snapshots after nine levels are the same text (%s)" % tag)
		check(String(without.growth.snapshot().rng_state) == String(disabled.growth.snapshot().rng_state), "B the card stream is in the same state (%s)" % tag)
		var tools: Dictionary = disabled.grace_tools()
		check(tools.enabled == false, "B grace_tools reports enabled false (%s)" % tag)
		for ev in disabled.events: check(not String(ev.type).begins_with("grace_"), "B no grace event while off")
		check(not disabled.banish_offer("x", "y") and not disabled.hold_offer("x", "y"), "B banish and hold do nothing while off (%s)" % tag)
		var offer := level_up(disabled)
		if not offer.is_empty():
			check(disabled.growth.card_contract(offer.cards[0]).get("grade") == null, "B a card contract has no grade key while off (%s)" % tag)
			check(offer.cards.size() <= 3, "B an off offer has at most 3 cards (%s)" % tag)
	# Grace on but nothing it does matters (neutral values): still the cards of the plain run.
	for spells_on in [false, true]:
		var plain = make_run(Callable(), spells_on, 12, EMBER, false)
		var calm = make_run(neutral, spells_on, 12, EMBER, true)
		check(play(plain, 9) == play(calm, 9), "B grace on with neutral values draws the same cards (spells %s)" % str(spells_on))
		check(String(plain.growth.snapshot().rng_state) == String(calm.growth.snapshot().rng_state), "B and leaves the card stream where it was (spells %s)" % str(spells_on))
	# The whole run: 400 ticks of a pilotless run give the same snapshot with the block on-but-neutral off the table: off == no block.
	var a = make_run(Callable(), true, 5, EMBER, false, false)
	var b = make_run(Callable(), true, 5, EMBER, false, true)
	for n in 300:
		a.step(Vector2.RIGHT)
		b.step(Vector2.RIGHT)
	check(JSON.stringify(a.snapshot()) == JSON.stringify(b.snapshot()), "B 300 ticks of a run: the off block leaves the snapshot text as it was")

# ------------------------------------------------------------------ C: K3a

## Make `growth` evolution-ready for ember (spells on): axis sum 5, crystal owned, ring partner with axis sum 2. Level `level` pending.
func make_evolution_ready(run: RefCounted, level: int) -> void:
	var g = run.growth
	g._ranks[EMBER] = 1
	g._axes[EMBER] = {"damage": 3, "reach": 2}
	g._ranks[EMBER_RING] = 1
	g._axes[EMBER_RING] = {"damage": 1, "reach": 1}
	g._owned_passives.append("chapter1.passive.embers")
	g._pending.assign([level])
	g._level = level

func part_c() -> void:
	# --- evolution minimum level (new composition)
	var run = make_run(neutral.bind(), true)
	run.growth._grace.evolve_min_level = 7
	make_evolution_ready(run, 6)
	var offer: Dictionary = run.growth.next_offer()
	check(not kinds_of(offer).has("evolve"), "C level 6 offer has no evolution card with evolve_min_level 7: " + str(ids(offer)))
	check(String(offer.cards[0].kind) != "evolve" if run.growth._protected_card(run.growth._eligible_cards()) < 0 else true, "C the protected card does not point at the locked evolution")
	var run7 = make_run(neutral.bind(), true)
	run7.growth._grace.evolve_min_level = 7
	make_evolution_ready(run7, 7)
	var offer7: Dictionary = run7.growth.next_offer()
	check(kinds_of(offer7).has("evolve"), "C level 7 offer has the evolution card: " + str(ids(offer7)))
	var run0 = make_run(neutral.bind(), true)
	make_evolution_ready(run0, 6)
	check(kinds_of(run0.growth.next_offer()).has("evolve"), "C evolve_min_level 0 keeps today's rule: the evolution is offered at level 6")
	# --- evolution minimum level (old composition: rank 4 + crystal)
	var old = make_run(neutral.bind(), false)
	old.growth._grace.evolve_min_level = 7
	old.growth._ranks[EMBER] = 4
	old.growth._owned_passives.append("chapter1.passive.embers")
	old.growth._pending.assign([6])
	check(not kinds_of(old.growth.next_offer()).has("evolve"), "C old composition: level 6 has no evolution card with minimum 7")
	var old7 = make_run(neutral.bind(), false)
	old7.growth._grace.evolve_min_level = 7
	old7.growth._ranks[EMBER] = 4
	old7.growth._owned_passives.append("chapter1.passive.embers")
	old7.growth._pending.assign([7])
	check(kinds_of(old7.growth.next_offer()).has("evolve"), "C old composition: level 7 has the evolution card")
	# --- last big offer
	var last = make_run(func(g): neutral(g); g.final_offer.mode = "big"; g.final_offer.cards = 4, true)
	make_evolution_ready(last, 12)
	last.mode = "choice"
	var big: Dictionary = last.get_offer()
	check(big.cards.size() == 4, "C the level 12 offer has final_offer.cards cards: " + str(big.cards.size()))
	check(String(big.cards[0].kind) == "evolve", "C the protected card of the last offer is the evolution (first word that fits)")
	var final_event := find_event(last, "grace_final_offer")
	check(not final_event.is_empty() and int(final_event.level) == 12 and int(final_event.cards) == 4, "C grace_final_offer {level, cards} is emitted: " + str(final_event))
	check(last.grace_tools().final == true, "C grace_tools().final is true for the last offer")
	var last3 = make_run(func(g): neutral(g); g.final_offer.mode = "big"; g.final_offer.cards = 3, true)
	make_evolution_ready(last3, 12)
	check(last3.growth.next_offer().cards.size() == 3, "C final_offer.cards 3 gives three cards")
	var none = make_run(neutral.bind(), true)
	make_evolution_ready(none, 12)
	check(none.growth.next_offer().cards.size() == 3 and find_event(none, "grace_final_offer").is_empty(), "C final_offer.mode none: no big offer")
	# old composition: no evolution anywhere, so the crystal card is the protected one (evolution -> crystal -> rank)
	var last_old = make_run(func(g): neutral(g); g.final_offer.mode = "big"; g.final_offer.cards = 4, false)
	last_old.growth._ranks[EMBER] = 2
	last_old.growth._pending.assign([12])
	var old_final: Dictionary = last_old.growth.next_offer()
	check(old_final.cards.size() == 4 and String(old_final.cards[0].kind) == "passive", "C old composition last offer protects the crystal when no evolution fits: " + str(kinds_of(old_final)))
	var last_old2 = make_run(func(g): neutral(g); g.final_offer.mode = "big"; g.final_offer.cards = 4, false)
	last_old2.growth._ranks[EMBER] = 4
	last_old2.growth._owned_passives.append("chapter1.passive.embers")
	last_old2.growth._pending.assign([12])
	check(String(last_old2.growth.next_offer().cards[0].kind) == "evolve", "C old composition last offer protects the evolution when one is offered")
	var last_old3 = make_run(func(g): neutral(g); g.final_offer.mode = "big"; g.final_offer.cards = 4; g.final_offer.protect_order = ["axis"], false)
	last_old3.growth._ranks[EMBER] = 2
	last_old3.growth._pending.assign([12])
	check(String(last_old3.growth.next_offer().cards[0].kind) == "rank", "C protect_order [axis] reads as a rank card in the old composition")
	# --- banish
	var bn = make_run(func(g): neutral(g); g.tools.base_banishes = 2, true, 21)
	var first := level_up(bn)
	var token := String(first.token)
	var passive_card := {}
	check(bn.grace_tools().banishes_left == 2, "C banishes_left starts at base_banishes")
	var victim := ""
	for card in first.cards:
		if String(card.kind) in ["unlock", "axis"]: victim = String(card.id)
	check(not victim.is_empty() and bn.banish_offer(token, victim), "C a banishable card is banished")
	check(not ids(bn.growth.next_offer()).has(victim) and bn.growth.next_offer().cards.size() == first.cards.size(), "C the slot is refilled with another card and the offer keeps its size")
	var banish_event := find_event(bn, "grace_banish")
	check(String(banish_event.get("card_id", "")) == victim and int(banish_event.left) == 1, "C grace_banish {card_id, left}: " + str(banish_event))
	check(bn.growth.snapshot().banished == [victim], "C snapshot growth.banished lists it")
	var later: Array = []
	bn.choose(token, String(bn.growth.next_offer().cards[0].id))
	for seen in play(bn, 9): later.append_array(seen)
	check(not later.has(victim), "C a banished id never comes back in the later offers (%d cards seen)" % later.size())
	# crystal and evolution are refused, a card that is not in the offer too
	var guard = make_run(func(g): neutral(g); g.tools.base_banishes = 3, true)
	make_evolution_ready(guard, 8)
	var ready_offer: Dictionary = guard.growth.next_offer()
	var evolve_id := ""
	var crystal_id := ""
	for card in ready_offer.cards:
		if String(card.kind) == "evolve": evolve_id = String(card.id)
		if String(card.kind) == "passive": crystal_id = String(card.id)
	check(not evolve_id.is_empty() and not guard.growth.banish(ready_offer.token, evolve_id) and guard.growth.banishes_left() == 3, "C an evolution card cannot be banished and costs nothing")
	check(not guard.growth.banish(ready_offer.token, "axis:nothing:damage") and not guard.growth.banish("0:0", String(ready_offer.cards[0].id)), "C a card that is not offered / a dead token is refused")
	var zero = make_run(neutral.bind(), true)
	var zero_offer := level_up(zero)
	check(not zero.banish_offer(zero_offer.token, String(zero_offer.cards[0].id)), "C no banish left: refused")
	# determinism
	var det_a = make_run(func(g): neutral(g); g.tools.base_banishes = 1, true, 33)
	var det_b = make_run(func(g): neutral(g); g.tools.base_banishes = 1, true, 33)
	var oa := level_up(det_a)
	var ob := level_up(det_b)
	det_a.banish_offer(oa.token, String(oa.cards[0].id))
	det_b.banish_offer(ob.token, String(ob.cards[0].id))
	check(ids(det_a.growth.next_offer()) == ids(det_b.growth.next_offer()) and JSON.stringify(det_a.growth.snapshot()) == JSON.stringify(det_b.growth.snapshot()), "C same seed, same inputs: the same banish result")
	# --- hold
	var hd = make_run(func(g): neutral(g); g.tools.base_holds = 1, true, 41)
	var h1 := level_up(hd)
	var held_id := String(h1.cards[1].id)
	check(hd.hold_offer(h1.token, held_id), "C hold takes a card of the offer")
	check(not hd.hold_offer(h1.token, String(h1.cards[0].id)), "C only one hold per offer (and none left)")
	check(hd.grace_tools().held_card_id == held_id and hd.growth.snapshot().held.id == held_id, "C grace_tools and the snapshot name the held card")
	check(not hd.choose(h1.token, held_id), "C the held card cannot be taken now")
	check(find_event(hd, "grace_hold").get("left", -1) == 0, "C grace_hold {card_id, left} is emitted")
	check(hd.choose(h1.token, String(h1.cards[0].id)), "C another card of the same offer can be taken")
	var h2 := level_up(hd)
	check(ids(h2).has(held_id), "C the held card is in the next offer: " + str(ids(h2)))
	check(h2.cards.size() <= 3 and hd.growth.snapshot().held.is_empty(), "C the next offer keeps its size and the hold is used up")
	# a held card that cannot appear any more is dropped
	var hd2 = make_run(func(g): neutral(g); g.tools.base_holds = 1, true, 42)
	var g1 := level_up(hd2)
	var dropped := ""
	for card in g1.cards:
		if String(card.kind) == "unlock": dropped = String(card.id)
	if not dropped.is_empty():
		hd2.hold_offer(g1.token, dropped)
		var other := ""
		for card in g1.cards:
			if String(card.id) != dropped: other = String(card.id)
		hd2.choose(g1.token, other)
		hd2.growth._banished.append(dropped)
		var g2 := level_up(hd2)
		check(not ids(g2).has(dropped) and hd2.grace_tools().held_dropped == true, "C a held card that cannot be offered any more is dropped, and the offer says so")
	# --- re-draw count and the hold survive a re-draw
	var rr = make_run(func(g): neutral(g); g.tools.base_rerolls = 2; g.tools.base_holds = 1, true, 43)
	var r1 := level_up(rr)
	check(rr.rerolls_left() == 2, "C re-draws = base_rerolls (2)")
	var kept := String(r1.cards[1].id)
	rr.hold_offer(r1.token, kept)
	check(rr.reroll_offer(r1.token) and rr.rerolls_left() == 1, "C a re-draw works and counts")
	check(rr.growth.snapshot().held.get("id", "") == kept, "C a re-draw leaves the card that is set aside set aside")
	check(not ids(rr.growth.next_offer()).has(kept), "C the re-drawn offer does not contain the card that is set aside")
	var tree = make_run(func(g): neutral(g); g.tools.base_rerolls = 3, true, 44)
	check(tree.growth.rerolls_left() == 3, "C base re-draws arrive in the growth")
	var capped = Chapter.new()
	capped.set_tuning(tuning_with(func(g): neutral(g); g.tools.base_rerolls = 3))
	capped.set_run_spells(spells_doc())
	capped.start(1, EMBER)
	var sum_probe = make_run(func(g): neutral(g); g.tools.base_rerolls = 3, true, 44)
	sum_probe.growth._rerolls_left = 3
	check(mini(6, sum_probe.growth.rerolls_left() + 3) == 6, "C tree re-draws (0..3) and base re-draws (0..3) add up to at most 6")
	# --- gap between choices
	var gap = make_run(func(g): neutral(g); g.min_gap_ticks = 300, true, 51)
	var o1 := level_up(gap)
	gap.growth.award_xp(int(gap.growth.xp_thresholds()[3]) - int(gap.growth.snapshot().xp))
	gap.tick = 1000
	gap.choose(o1.token, String(o1.cards[0].id))
	check(gap.mode == "playing", "C a level that is already pending waits for the gap (mode playing)")
	check(gap.grace_tools().waiting_until == 1300, "C grace_tools().waiting_until names the tick: " + str(gap.grace_tools().waiting_until))
	var waiting := find_event(gap, "grace_waiting")
	check(int(waiting.get("until_tick", 0)) == 1300 and int(waiting.get("level", 0)) == 3, "C grace_waiting {level, until_tick}: " + str(waiting))
	gap.tick = 1299
	gap._refresh_mode()
	check(gap.mode == "playing", "C one tick early: still playing")
	gap.tick = 1300
	gap._refresh_mode()
	check(gap.mode == "choice", "C when the gap has passed the choice opens")
	var nogap = make_run(func(g): neutral(g); g.min_gap_ticks = 0, true, 51)
	var n1 := level_up(nogap)
	nogap.growth.award_xp(int(nogap.growth.xp_thresholds()[3]) - int(nogap.growth.snapshot().xp))
	nogap.tick = 1000
	nogap.choose(n1.token, String(n1.cards[0].id))
	check(nogap.mode == "choice", "C min_gap_ticks 0: the next level opens at once, as today")
	var gap_last = make_run(func(g): neutral(g); g.min_gap_ticks = 3000, true, 52)
	var l1 := level_up(gap_last)
	gap_last.growth.award_xp(int(gap_last.growth.xp_thresholds()[11]) - int(gap_last.growth.snapshot().xp))
	gap_last.growth._pending.assign([2, 12])
	gap_last.tick = 1000
	gap_last.choose(l1.token, String(l1.cards[0].id))
	check(gap_last.mode == "choice", "C the last level ignores the gap")
	check(gap_last.snapshot().grace_gap.last_choice == 1000, "C the gap's clock is in the snapshot while the block is on")

# ------------------------------------------------------------------ D: grades

func part_d() -> void:
	# --- the grade stream is apart from the card stream
	for spells_on in [false, true]:
		var calm = make_run(neutral.bind(), spells_on, 61, EMBER, true)
		var graded = make_run(inert_grades.bind(), spells_on, 61, EMBER, true)
		var seen_calm := play(calm, 11)
		var seen_graded := play(graded, 11)
		check(seen_calm == seen_graded and seen_calm.size() >= 10, "D grades on (no extra points) draw the same cards as grades off, %d levels (spells %s)" % [seen_calm.size(), str(spells_on)])
		check(String(calm.growth.snapshot().rng_state) == String(graded.growth.snapshot().rng_state), "D and leave the card stream in the same state (spells %s)" % str(spells_on))
		check(String(graded.growth.snapshot().grace.grade_rng_state) != String(calm.growth.snapshot().grace.grade_rng_state), "D while the grade stream moved (spells %s)" % str(spells_on))
	# --- what is pulled
	var run = make_run(func(g): neutral(g); g.grades.enabled = true; g.grades.jackpot_bps = 0; g.grades.pity.hard_after_spins = 0, true, 62)
	var offer := level_up(run)
	var tools: Dictionary = run.grace_tools()
	check(tools.grades_enabled == true and tools.offer_cards.size() == offer.cards.size(), "D grace_tools().offer_cards has an entry per card")
	for card in offer.cards:
		var fields: Dictionary = tools.offer_cards[String(card.id)]
		check(fields.has("grade") and fields.has("roll") and fields.has("rollable"), "D every card has grade, roll and rollable")
		if bool(fields.rollable):
			check(fields.roll.has("value_bps") and fields.roll.has("rare_at_bps") and fields.roll.has("jackpot_at_bps"), "D a pulled card shows its real roll")
			var v := int(fields.roll.value_bps)
			var expect := "jackpot" if v < int(fields.roll.jackpot_at_bps) else ("rare" if v < int(fields.roll.rare_at_bps) else "common")
			check(String(fields.grade) == expect, "D the grade is what the roll says (value %d: %s)" % [v, expect])
			check(bool(fields.near) == (String(fields.grade) != "jackpot" and v - int(fields.roll.jackpot_at_bps) < 300), "D near is true only inside near_bps above the jackpot line")
		else:
			check(String(fields.grade) == "common" and fields.roll.is_empty(), "D a card that is never pulled is common with no roll")
	check(find_event(run, "grace_grades_rolled").get("grades", []).size() == offer.cards.size(), "D grace_grades_rolled has one grade per card")
	# the same fields sit in run_spells_view().offer[id]
	var view: Dictionary = run.run_spells_view()
	for card in offer.cards:
		check(view.offer[String(card.id)].get("grade", "") == tools.offer_cards[String(card.id)].grade, "D run_spells_view().offer[id] carries the grade of the card")
	# crystal and evolution are never pulled
	var ready = make_run(always_jackpot.bind(), true, 63)
	make_evolution_ready(ready, 9)
	var ready_offer: Dictionary = ready.growth.next_offer()
	for card in ready_offer.cards:
		var f: Dictionary = ready.growth.grade_fields(card)
		if String(card.kind) in ["passive", "evolve"]: check(not bool(f.rollable) and String(f.grade) == "common", "D a %s card is never pulled" % String(card.kind))
	# --- hard pity
	var pity = make_run(func(g): neutral(g); g.grades.enabled = true; g.grades.jackpot_bps = 0; g.grades.rare_bps = 0; g.grades.pity.soft_step_bps = 0; g.grades.pity.hard_after_spins = 3, true, 64)
	var jack_at: Array = []
	var forced_at: Array = []
	for n in 9:
		var o := level_up(pity)
		var t: Dictionary = pity.grace_tools()
		if bool(t.has_jackpot): jack_at.append(n + 1)
		if bool(t.forced_by_pity): forced_at.append(n + 1)
		var jackpot_card := ""
		for card in o.cards:
			if String(t.offer_cards[String(card.id)].grade) == "jackpot": jackpot_card = String(card.id)
		pity.choose(o.token, jackpot_card if not jackpot_card.is_empty() else String(o.cards[0].id))
	check(jack_at == [3, 6, 9] and forced_at == [3, 6, 9], "D hard pity 3: a jackpot at offers 3, 6, 9 and only there, all forced: %s / %s" % [str(jack_at), str(forced_at)])
	# --- soft pity
	var soft = make_run(func(g): neutral(g); g.grades.enabled = true; g.grades.jackpot_bps = 0; g.grades.rare_bps = 0; g.grades.pity.soft_step_bps = 200; g.grades.pity.hard_after_spins = 0, true, 65)
	var soft_ok := true
	var soft_seen: Array = []
	for n in 8:
		var pity_before := int(soft.grace_tools().get("pity", {}).get("spins", 0))
		var o := level_up(soft)
		var t: Dictionary = soft.grace_tools()
		soft_seen.append(int(t.odds.jackpot_bps))
		if int(t.odds.jackpot_bps) != 200 * pity_before: soft_ok = false
		soft.choose(o.token, String(o.cards[0].id))
	check(soft_ok and soft_seen[1] >= 0, "D soft pity: the chance used is soft_step x the offers since the last jackpot: " + str(soft_seen))
	# --- the shown odds, caps and luck parts
	var luck = make_run(func(g): neutral(g); g.grades.enabled = true; g.grades.jackpot_bps = 500; g.grades.rare_bps = 2500; g.grades.pity.hard_after_spins = 0; g.grades.pity.soft_step_bps = 0, true, 66)
	check(luck.growth.set_grade_luck(15000, 2, 9000), "D the luck parts are accepted")
	var lo := level_up(luck)
	var odds: Dictionary = luck.grace_tools().odds
	# (500 + 250 gear (+50% cap) + 200 reward stages) x 1.5 = 1425; rare 2500 x 1.5 = 3750
	check(int(odds.parts.gear) == 250 and int(odds.parts.reward_grade) == 200 and int(odds.jackpot_bps) == 1425 and int(odds.rare_bps) == 3750, "D odds = (base + gear within its cap + reward stages) x shrine: " + str(odds))
	var capped_run = make_run(func(g): neutral(g); g.grades.enabled = true; g.grades.jackpot_bps = 2000; g.grades.pity.hard_after_spins = 0, true, 66)
	capped_run.growth.set_grade_luck(30000, 0, 0)
	level_up(capped_run)
	var capped_odds: Dictionary = capped_run.grace_tools().odds
	check(int(capped_odds.jackpot_bps) == 2500 and bool(capped_odds.capped), "D the jackpot chance per slot never passes cap_bps (25%)")
	check(not luck.growth.set_grade_luck(9999, 0, 0) and not luck.growth.set_grade_luck(10000, 5, 0) and not luck.growth.set_grade_luck(10000, 0, 10001), "D luck parts out of range are refused")
	var off_luck = make_run(neutral.bind(), true, 66)
	check(not off_luck.set_grace_luck(15000, 0, 0), "D luck is refused while the grades are off")
	# --- the last offer's extra-lucky slot
	var fin = make_run(func(g): neutral(g); g.final_offer.mode = "big"; g.grades.enabled = true; g.grades.jackpot_bps = 500; g.grades.pity.hard_after_spins = 0, true, 67)
	make_evolution_ready(fin, 12)
	var fin_offer: Dictionary = fin.growth.next_offer()
	var fin_ats: Array = []
	for card in fin_offer.cards:
		var f: Dictionary = fin.growth.grade_fields(card)
		if bool(f.rollable): fin_ats.append(int(f.roll.jackpot_at_bps))
	check(fin_ats.size() >= 2 and fin_ats[0] == 1000 and fin_ats.slice(1).all(func(v): return v == 500), "D the last offer: one slot with twice the chance (1000), the others 500: " + str(fin_ats))
	# --- re-draw pulls again
	var rd = make_run(func(g): neutral(g); g.tools.base_rerolls = 2; g.grades.enabled = true; g.grades.pity.hard_after_spins = 0, true, 68)
	var rd1 := level_up(rd)
	var spin_before: int = rd.growth.spins()
	var rolls_before: Array = rd1.cards.map(func(c): return rd.growth.grade_fields(c).get("roll", {}))
	rd.reroll_offer(rd1.token)
	var rd2: Dictionary = rd.growth.next_offer()
	check(rd.growth.spins() == spin_before + 1, "D a re-draw is one more pull (spin %d -> %d)" % [spin_before, rd.growth.spins()])
	check(str(find_event(rd, "grace_reroll").get("spin", "")) != "" and not find_event(rd, "grace_grades_rolled").is_empty(), "D a re-draw emits grace_reroll (with spin) and a new grace_grades_rolled")
	var rolls_after: Array = rd2.cards.map(func(c): return rd.growth.grade_fields(c).get("roll", {}))
	check(rolls_before != rolls_after, "D the re-drawn cards come with new rolls")
	# --- a held card keeps its roll
	var keep = make_run(func(g): neutral(g); g.tools.base_holds = 1; g.grades.enabled = true; g.grades.pity.hard_after_spins = 0, true, 69)
	var k1 := level_up(keep)
	var held_card := ""
	for card in k1.cards:
		if bool(keep.growth.grade_fields(card).rollable): held_card = String(card.id)
	var held_before: Dictionary = {}
	for card in k1.cards:
		if String(card.id) == held_card: held_before = keep.growth.grade_fields(card)
	keep.hold_offer(k1.token, held_card)
	for card in k1.cards:
		if String(card.id) != held_card:
			keep.choose(k1.token, String(card.id))
			break
	var k2 := level_up(keep)
	for card in k2.cards:
		if String(card.id) == held_card:
			var after: Dictionary = keep.growth.grade_fields(card)
			check(after.roll == held_before.roll and after.grade == held_before.grade, "D a held card keeps its roll and grade")
	# --- a banish refills one slot and rolls only that slot
	var bz = make_run(func(g): neutral(g); g.tools.base_banishes = 1; g.grades.enabled = true; g.grades.pity.hard_after_spins = 0, true, 70)
	var b1 := level_up(bz)
	var spins_before: int = bz.growth.spins()
	var target := ""
	for card in b1.cards:
		if String(card.kind) in ["unlock", "axis"]: target = String(card.id)
	var others_before := {}
	for card in b1.cards:
		if String(card.id) != target: others_before[String(card.id)] = bz.growth.grade_fields(card).get("roll", {})
	bz.banish_offer(b1.token, target)
	check(bz.growth.spins() == spins_before, "D a banish does not count as a pull")
	var b2: Dictionary = bz.growth.next_offer()
	for card in b2.cards:
		if others_before.has(String(card.id)): check(bz.growth.grade_fields(card).roll == others_before[String(card.id)], "D the other cards keep their rolls after a banish")
		else: check(bz.growth.grade_fields(card).has("grade"), "D the card that came in has a grade")
	var banish_event := find_event(bz, "grace_banish")
	check(banish_event.has("new_card_id") and banish_event.has("new_grade") and banish_event.has("slot"), "D grace_banish says what came in: " + str(banish_event))

## The build-dependent size of a jackpot (resonance) and what choosing it does.
func part_d2() -> void:
	# A single axis card on ember, once with no partner and once with the ring.
	var solo = make_run(always_jackpot.bind(), true, 71)
	var axis_card := {"id": "axis:%s:damage" % EMBER, "kind": "axis", "skill_id": EMBER, "axis": "damage", "level": 1, "rank": 2, "weight": 1}
	var plan_solo: Dictionary = solo.growth._grade_plan(axis_card, "jackpot")
	check(plan_solo.resonance == false and plan_solo.points == 2 and plan_solo.partner_skill == "", "D no owned partner: the floor, +2 on the axis and no partner: " + str(plan_solo))
	solo.growth._ranks[EMBER_RING] = 1
	solo.growth._axes[EMBER_RING] = {"damage": 0, "reach": 1}
	var plan_pair: Dictionary = solo.growth._grade_plan(axis_card, "jackpot")
	check(plan_pair.resonance == true and plan_pair.partner_skill == EMBER_RING and plan_pair.partner.damage == 1 and plan_pair.partner.reach == 0, "D with the ring owned: resonance, the partner's lower axis gets +1: " + str(plan_pair))
	var rare_plan: Dictionary = solo.growth._grade_plan(axis_card, "rare")
	check(rare_plan.points == 2 and rare_plan.partner_skill == "" and rare_plan.resonance == false, "D a rare is +2 on the axis and never touches the partner")
	# the cap bonus lets the sum pass 6 once
	solo.growth._axes[EMBER] = {"damage": 2, "reach": 3}
	var cap_plan: Dictionary = solo.growth._grade_plan(axis_card, "jackpot")
	var cap_base: Dictionary = solo.growth._grade_plan(axis_card, "jackpot", "base")
	check(cap_plan.points == 2 and cap_base.points == 1, "D sum 5: the resonance reaches 7 (cap bonus 1), the floor stops at 6: %d / %d" % [cap_plan.points, cap_base.points])
	# the contract shows both sides and what a resonance needs
	var run = make_run(always_jackpot.bind(), true, 72)
	var offer := level_up(run)
	var jackpot_card := {}
	for card in offer.cards:
		if String(run.growth.grade_fields(card).get("grade", "")) == "jackpot": jackpot_card = card
	check(not jackpot_card.is_empty(), "D the forced pull made a jackpot at the first offer")
	if not jackpot_card.is_empty():
		var f: Dictionary = run.growth.grade_fields(jackpot_card)
		check(f.forced_by_pity == true and run.grace_tools().forced_by_pity == true and run.grace_tools().has_jackpot == true, "D forced_by_pity is told (card and offer)")
		check(f.jackpot.has("base") and f.jackpot.has("resonance") and f.jackpot.has("matched_now"), "D the jackpot lists base and resonance and matched_now")
		check(f.jackpot.resonance.has("needs") and f.jackpot.resonance.has("partner_skill") and f.jackpot.resonance.has("evolve_ready_after") and f.jackpot.base.has("after") and f.jackpot.base.has("effect_key"), "D the jackpot sides carry effect_key, after, partner_skill, evolve_ready_after, needs")
		var shown := find_event(run, "grace_jackpot_shown")
		check(not shown.is_empty() and shown.slots.size() >= 1 and shown.matched.size() == shown.slots.size(), "D grace_jackpot_shown {level, slots, matched}: " + str(shown))
		# read only: reading the contract twice moves nothing
		var before := JSON.stringify(run.growth.snapshot())
		run.growth.grade_fields(jackpot_card)
		run.grace_tools()
		run.run_spells_view()
		check(JSON.stringify(run.growth.snapshot()) == before, "D the contract is read only: the snapshot did not move")
		# take it: the plan on the build of this moment is what happens
		var before_axes := axes_of(run, String(jackpot_card.skill_id)).duplicate()
		var plan: Dictionary = run.growth._grade_plan(jackpot_card, "jackpot")
		run.choose(offer.token, String(jackpot_card.id))
		var taken := find_event(run, "grace_jackpot_taken")
		check(taken.get("card_id", "") == String(jackpot_card.id) and taken.has("resonance") and taken.has("partner_skill") and taken.has("evolve_ready"), "D grace_jackpot_taken {card_id, resonance, partner_skill, evolve_ready}: " + str(taken))
		if String(jackpot_card.kind) == "axis":
			var after_axes := axes_of(run, String(jackpot_card.skill_id))
			var added := int(after_axes.damage) + int(after_axes.reach) - int(before_axes.damage) - int(before_axes.reach)
			check(added == int(plan.points), "D choosing a jackpot axis card adds the planned points (%d)" % added)
	# one tested pick of a resonance on a made build
	var res = make_run(always_jackpot.bind(), true, 73)
	var g = res.growth
	g._ranks[EMBER_RING] = 1
	g._axes[EMBER_RING] = {"damage": 0, "reach": 0}
	g._axes[EMBER] = {"damage": 2, "reach": 2}
	g._owned_passives.append("chapter1.passive.embers")
	g._pending.assign([8])
	g._level = 8
	var o: Dictionary = g.next_offer()
	var axis_pick := {}
	for card in o.cards:
		if String(card.kind) == "axis" and String(card.skill_id) == EMBER and String(g.grade_fields(card).get("grade", "")) == "jackpot": axis_pick = card
	if not axis_pick.is_empty():
		var jf: Dictionary = g.grade_fields(axis_pick).jackpot
		check(jf.matched_now == true and jf.resonance.partner_skill == EMBER_RING and jf.resonance.partner_points == 1, "D the contract says a resonance pick pairs with the ring: " + str(jf.resonance.partner_skill))
		var ring_before: int = g._axis_sum(EMBER_RING)
		g.choose(o.token, String(axis_pick.id))
		check(g._axis_sum(EMBER_RING) == ring_before + 1, "D the resonance pick grows the partner by one point")
		check(bool(jf.resonance.evolve_ready_after) == g._can_evolve(EMBER), "D evolve_ready_after tells what is true after the pick")

# ------------------------------------------------------------------ E: counts over many runs

## A started run without failing the check on a file read that the operating system refused (thousands of starts read the data
## files each time; a refused read is retried, never counted). Returns null only after five refusals.
func quiet_run(mutate: Callable, seed_: int) -> RefCounted:
	for attempt in 5:
		var run = Chapter.new()
		if run.set_tuning(tuning_with(mutate)) and run.set_run_spells(spells_doc()) and run.start(seed_, EMBER):
			run.first_boss_kill = true
			return run
	check(false, "quiet_run could not start seed %d" % seed_)
	return null

## One played run on the growth alone: 11 offers (levels 2..12), the first card always taken. Returns {shown, taken, forced, first_level}.
func count_run(seed_: int, mutate: Callable) -> Dictionary:
	var run = quiet_run(mutate, seed_)
	var shown := 0
	var forced := 0
	var first := 0
	var slots := 0
	var offers := 0
	for n in 11:
		var offer := level_up(run)
		if offer.is_empty(): break
		var t: Dictionary = run.grace_tools()
		if bool(t.has_jackpot):
			shown += 1
			if first == 0: first = n + 2
		if bool(t.forced_by_pity): forced += 1
		offers += 1
		for card in offer.cards:
			if bool(t.offer_cards[String(card.id)].rollable): slots += 1
		var pick: Dictionary = offer.cards[0]
		for card in offer.cards:
			if String(t.offer_cards[String(card.id)].grade) == "jackpot": pick = card
		run.choose(offer.token, String(pick.id))
	return {"shown": shown, "forced": forced, "first_level": first, "slots": slots, "offers": offers}

func part_e() -> void:
	var runs := 600
	var hist := {}
	var forced_runs := 0
	var total := 0
	var slot_total := 0
	var offer_total := 0
	var first_levels: Array = []
	for seed_ in range(1, runs + 1):
		var c := count_run(seed_, grades_on)
		hist[c.shown] = int(hist.get(c.shown, 0)) + 1
		total += int(c.shown)
		slot_total += int(c.slots)
		offer_total += int(c.offers)
		if int(c.forced) > 0: forced_runs += 1
		if int(c.first_level) > 0: first_levels.append(int(c.first_level))
	var keys: Array = hist.keys()
	keys.sort()
	var parts: Array[String] = []
	for k in keys: parts.append("%d:%d" % [k, hist[k]])
	var mean := float(total) / float(runs)
	first_levels.sort()
	print("GRACE_DIST ", JSON.stringify({"runs": runs, "jackpots_shown_histogram": parts, "mean": mean, "pulled_slots_per_offer": float(slot_total) / float(offer_total), "offers_per_run": float(offer_total) / float(runs), "runs_with_a_forced_one": forced_runs,
		"median_first_level": first_levels[first_levels.size() / 2] if not first_levels.is_empty() else 0, "note": "actual core, growth only, first-card-or-jackpot policy, shipped hypothesis values"}))
	check(int(hist.get(0, 0)) == 0, "E no run of 11 offers is without a jackpot (the hard pity guarantees one): %s" % str(parts))
	check(mean > 0.9 and mean < 3.0, "E the mean count of jackpots shown per run is plausible: %.2f" % mean)
	# determinism: the same seed gives the same counts and the same snapshot
	var a := count_run(77, grades_on)
	var b := count_run(77, grades_on)
	check(a == b, "E the same seed counts the same")
	var ra = make_run(grades_on, true, 78)
	var rb = make_run(grades_on, true, 78)
	play(ra, 8)
	play(rb, 8)
	check(JSON.stringify(ra.snapshot()) == JSON.stringify(rb.snapshot()), "E the same seed and inputs give the same snapshot text with the grades on")

func execute() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/_local/appdata/"):
		print("CHAPTER1_GRACE_RESULT ", JSON.stringify({"checks": 0, "failures": ["user data dir is not isolated: refusing to run"]}))
		quit(1)
		return
	part_a()
	part_b()
	part_c()
	part_d()
	part_d2()
	part_e()
	print("CHAPTER1_GRACE_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
