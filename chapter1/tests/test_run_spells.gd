extends SceneTree
## KS check of the in-run spell composition (D12 B0, G5): chapter1/data/run_spells.json read by core/run_spells.gd, the ring
## cast, statuses and same-element detonation (chapter_core.gd / combat_core.gd), axis cards, slots, evolution pairs and
## protected cards (run_growth.gd). The shipped file stays OFF; every enabled document is made in memory here.
##   A  the shipped file is off and the run is the old run (no new keys, same snapshot as a parked disabled document)
##   B  the validator refuses documents that disagree with themselves
##   C  ring cast: only with an enemy inside, shape and radius, pulses, target count, preferred status
##   D  statuses and detonation: own status never detonates, other spell's does (multiplier, consume), freeze, strong-enemy damping
##   E  cards: axis caps, slots, own ring only, evolution partner, protected cards, composed effect, read-only view
##   F  whole enabled runs: three witches x two policies, and one run with the rhythm on (set RUN_SPELLS_SKIP_RUNS=1 or --fast to skip F)
## Marker: CHAPTER1_RUN_SPELLS_RESULT. Writes nothing. Policy picks and results of F are printed as RUN_SPELLS_PLAY lines.
const Chapter = preload("res://chapter1/core/chapter_core.gd")
const Pilot = preload("res://chapter1/core/chapter_pilot.gd")
const RunSpells = preload("res://chapter1/core/run_spells.gd")
const SPELLS := "res://chapter1/data/run_spells.json"
const TUNING := "res://chapter1/data/combat_tuning.json"
const EMBER := "chapter1.skill.ember"
const FROST := "chapter1.skill.frost"
const ARC := "chapter1.skill.arc"
const EMBER_RING := "chapter1.skill.ember_ring"
const FROST_RING := "chapter1.skill.frost_ring"
const ARC_RING := "chapter1.skill.arc_ring"
const FAR := 1 << 30
var checks := 0
var failures: Array[String] = []
var plays: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("execute")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func shipped() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SPELLS))

func enabled_doc(mutate: Callable = Callable()) -> Dictionary:
	var doc := shipped()
	doc.enabled = true
	if mutate.is_valid(): mutate.call(doc)
	return doc

func make_run(doc: Variant, seed_: int = 11, primary: String = EMBER, tuning: Dictionary = {}) -> RefCounted:
	var run = Chapter.new()
	if not tuning.is_empty() and not run.set_tuning(tuning):
		check(false, "tuning accepted: " + str(run.errors))
		return null
	if doc is Dictionary and not run.set_run_spells(doc):
		check(false, "document accepted: " + str(run.errors))
		return null
	if not run.start(seed_, primary):
		check(false, "run starts: " + str(run.errors))
		return null
	run.first_boss_kill = true
	return run

func owners_and_starts() -> Dictionary:
	var probe = Chapter.new()
	return probe._spell_inputs()

func problems(doc: Variant) -> Array[String]:
	var inputs := owners_and_starts()
	return RunSpells.validate(doc, Chapter.SKILL_IDS, inputs.owners, inputs.starts)

# ------------------------------------------------------------------ bench helpers

## A started run with the composition on, no enemies, nothing spawning and nothing casting (the test frees what it needs).
func bench(primary: String = EMBER, doc: Dictionary = {}) -> RefCounted:
	var run := make_run(doc if not doc.is_empty() else enabled_doc(), 11, primary)
	run.enemies.clear()
	run._alive = 0
	run._next_spawn = FAR
	for id_ in run._skill_ids: run._next_cast[id_] = FAR
	return run

func give(run: RefCounted, id_: String, damage: int = 0, reach: int = 0) -> void:
	run.growth._ranks[id_] = 1
	run.growth._axes[id_] = {"damage": damage, "reach": reach}

## A walker that stands still with a lot of health, so a hit cannot kill it. It is held in a recovery that never ends (not
## stunned: a stunned body would count as controlled for the aim and the vs_cc rules).
func enemy(run: RefCounted, at: Vector2, elite: bool = false) -> int:
	run._spawn("walker", at)
	var id_: int = run._enemy_sequence
	var e: Dictionary = run.enemies[id_]
	e.state = "recover"
	e.state_until = FAR
	e.hp_raw = 100000 * 256
	e.max_hp_raw = e.hp_raw
	e.elite = elite
	return id_

func strike(run: RefCounted, target: int, skill_id: String, depth: int = 0) -> Dictionary:
	var effects: Dictionary = run.effective_skill(skill_id).effects.duplicate(true)
	run._cast_sequence += 1
	var context := {"uid": run._cast_sequence, "skill_id": skill_id, "effects": effects, "remaining_hits": 50, "hit_ids": [], "evolved": false}
	run.events.clear()
	run._damage_enemy(target, context, depth)
	var found := {"effects": effects, "hit": {}, "detonate": {}}
	for event in run.events:
		if event.type == "hit": found.hit = event
		elif event.type == "detonate": found.detonate = event
	return found

func put_status(run: RefCounted, target: int, status: String, n: int, by: Dictionary, until_in: int = 600) -> void:
	var e: Dictionary = run.enemies[target]
	if not e.has("status"): e.status = {}
	var last := ""
	for who in by: last = who
	e.status[status] = {"n": n, "src": last, "until": run.tick + until_in, "by": by.duplicate()}

func status_n(run: RefCounted, target: int, status: String) -> int:
	return int(run.enemies[target].get("status", {}).get(status, {}).get("n", 0))

func card_ids(cards: Array) -> Array:
	return cards.map(func(c): return String(c.id))

# ------------------------------------------------------------------ A

func part_a() -> void:
	var file_doc := shipped()
	check(file_doc.enabled == false, "A the shipped run_spells.json says enabled false")
	check(problems(file_doc).is_empty(), "A the shipped document validates: " + str(problems(file_doc)))
	var off_run := make_run(null)
	check(off_run.spells.is_empty() and off_run._skill_ids == Chapter.SKILL_IDS, "A shipped (disabled) file: no spells, SKILL_IDS unchanged")
	check(off_run.run_spells_view() == {"enabled": false}, "A run_spells_view() is {enabled:false} while off")
	var parked_off := make_run(file_doc)
	var hash_a := ""
	var hash_b := ""
	var pilot_a = Pilot.new()
	var pilot_b = Pilot.new()
	pilot_a.run = off_run
	pilot_b.run = parked_off
	var status_keys := 0
	for i in 1500:
		off_run.step(pilot_a.decide())
		parked_off.step(pilot_b.decide())
		for e in off_run.enemies.values():
			if e.has("status"): status_keys += 1
	hash_a = JSON.stringify(off_run.snapshot()).sha256_text()
	hash_b = JSON.stringify(parked_off.snapshot()).sha256_text()
	check(hash_a == hash_b, "A no document and a parked disabled document give the same snapshot after 1500 ticks")
	check(status_keys == 0, "A no enemy has a status key while off")
	var snap: Dictionary = off_run.snapshot()
	check(not snap.has("spells") and not snap.growth.has("axes") and not snap.growth.has("evolve_partner") and not snap.metrics.has("detonate"), "A no spell keys in the snapshot while off")
	check(not off_run.growth.spells_active() and off_run.growth.snapshot().ranks.size() >= 1, "A growth is the old growth while off")
	# The old card kinds are still offered (rank, not axis).
	var fresh_off := make_run(null)
	fresh_off.growth.award_xp(10)
	var kinds := {}
	for card in fresh_off.growth.next_offer().cards: kinds[card.kind] = true
	check(not kinds.is_empty() and not kinds.has("axis"), "A the old card kinds only, no axis card while off (%s)" % str(kinds.keys()))
	check(owners_and_starts().owners.size() == 3, "A the character catalog gives three owners")

# ------------------------------------------------------------------ B

func part_b() -> void:
	var labels: Array[String] = ["cap_per_axis above cap_per_spell", "cap_per_axis 9", "damage_bps first value", "damage_bps length", "cooldown_bps range", "slots 5", "enabled not bool", "protect level 1", "status max 21", "status expire 10", "unknown status", "spell missing", "ring id unknown", "ring without owner", "ring owner of another element", "ring owner unknown", "basic with an owner", "base key unknown", "ring key on a basic", "ring_targets 13", "ring_radius 801", "ring base without radius", "reach length", "reach key", "applies unknown status", "detonate without consume", "detonate with both multipliers", "freeze_bonus on heat", "vs_strong_bps 10001", "pair a does not apply the status", "pair b does not detonate the status", "interlock a does not put the control on", "interlock b has no vs_cc", "pair spell unknown", "pair with itself", "pair duplicate id", "pair kind", "reaction id shape", "reaction same element", "evolve partner_detonate_bps below 1x", "composed effect without a shot", "root key"]
	for label in labels:
		var doc := enabled_doc()
		mutate(doc, label)
		check(not problems(doc).is_empty(), "B refused: " + label)
		var run = Chapter.new()
		check(not run.set_run_spells(doc) and run._pending_spells.is_empty(), "B set_run_spells keeps the run unchanged: " + label)
	# Reaction pairs (the next work package) pass: only the shape is checked.
	check(problems(enabled_doc()).is_empty(), "B the enabled shipped document validates")
	check(enabled_doc().pairs.filter(func(p): return p.kind == "reaction").size() == 3, "B the shipped file lists the three reaction pairs and they validate")
	var bad_run = Chapter.new()
	check(bad_run.set_run_spells(enabled_doc()) and not bad_run.set_run_spells(enabled_doc(func(d): d.slots = 9)) and bool(bad_run._pending_spells.enabled), "B a refused document leaves the parked one in place")

## One mutation per label that makes the document disagree with itself.
func mutate(d: Dictionary, label: String) -> void:
	match label:
		"cap_per_axis above cap_per_spell":
			d.axis.cap_per_axis = 7
			d.axis.cap_per_spell = 6
		"cap_per_axis 9":
			d.axis.cap_per_axis = 9
		"damage_bps first value":
			d.axis.power.damage_bps[0] = 9000
		"damage_bps length":
			d.axis.power.damage_bps.append(23000)
		"cooldown_bps range":
			d.axis.power.cooldown_bps[2] = 70000
		"slots 5":
			d.slots = 5
		"enabled not bool":
			d.enabled = "yes"
		"protect level 1":
			d.protect.ring_at_level = 1
		"status max 21":
			d.statuses.heat.max = 21
		"status expire 10":
			d.statuses.shock.expire_ticks = 10
		"unknown status":
			d.statuses.burn = {"max": 2, "expire_ticks": 60}
		"spell missing":
			d.spells.erase(ARC)
		"ring id unknown":
			d.spells["chapter1.skill.moon_ring"] = d.spells[EMBER_RING].duplicate(true)
		"ring without owner":
			d.spells[EMBER_RING].erase("owner")
		"ring owner of another element":
			d.spells[EMBER_RING].owner = "chapter1.character.frost"
		"ring owner unknown":
			d.spells[EMBER_RING].owner = "chapter1.character.nobody"
		"basic with an owner":
			d.spells[EMBER].owner = "chapter1.character.ember"
		"base key unknown":
			d.spells[EMBER].base.mana = 3
		"ring key on a basic":
			d.spells[EMBER].base.ring_radius_cm = 100
		"ring_targets 13":
			d.spells[ARC_RING].base.ring_targets = 13
		"ring_radius 801":
			d.spells[EMBER_RING].base.ring_radius_cm = 801
		"ring base without radius":
			d.spells[EMBER_RING].base.erase("ring_radius_cm")
		"reach length":
			d.spells[EMBER].reach.pop_back()
		"reach key":
			d.spells[EMBER].reach[1].damage = 5
		"applies unknown status":
			d.spells[EMBER].applies = {"burn": 1}
		"detonate without consume":
			d.spells[EMBER_RING].detonates.heat.erase("consume")
		"detonate with both multipliers":
			d.spells[EMBER_RING].detonates.heat.per_stack_bps = 100
		"freeze_bonus on heat":
			d.spells[EMBER_RING].detonates.heat.freeze_bonus = 1
		"vs_strong_bps 10001":
			d.spells[EMBER_RING].vs_strong_bps = 10001
		"interlock a does not put the control on":
			d.pairs[3].via = ["stunned"]
		"pair a does not apply the status":
			d.pairs[0].status = "shock"
		"pair b does not detonate the status":
			d.spells[EMBER_RING].detonates = {}
		"interlock b has no vs_cc":
			d.spells[EMBER].vs_cc = {}
		"pair spell unknown":
			d.pairs[0].b = "chapter1.skill.nothing"
		"pair with itself":
			d.pairs[0].b = EMBER
		"pair duplicate id":
			d.pairs[1].id = d.pairs[0].id
		"pair kind":
			d.pairs[0].kind = "merge"
		"reaction id shape":
			d.pairs[10].reaction = "steam"
		"reaction same element":
			d.pairs[10].elements = ["ember", "ember"]
		"evolve partner_detonate_bps below 1x":
			d.evolve.partner_detonate_bps = 5000
		"composed effect without a shot":
			d.spells[EMBER].base.projectiles = 0
		"root key":
			d.extra = 1

# ------------------------------------------------------------------ C

func part_c() -> void:
	var run := bench(EMBER)
	check(run.spells.has("spells") and run._skill_ids.size() == 6 and run._skill_ids.slice(0, 3) == Chapter.SKILL_IDS, "C enabled: the six spell ids, the three old ones first")
	give(run, EMBER_RING)
	var ring_r := float(run.effective_skill(EMBER_RING).effects.ring_radius_cm) / 100.0
	check(is_equal_approx(ring_r, 2.2), "C ember ring radius 2.2 m (%f)" % ring_r)
	var far := enemy(run, Vector2(5, 0))
	run._next_cast[EMBER_RING] = 0
	run.step()
	check(int(run.metrics.casts.get(EMBER_RING, 0)) == 0 and int(run._next_cast[EMBER_RING]) == 0, "C no enemy inside the ring: no cast and the cooldown is not spent")
	check(run.events.filter(func(e): return e.type == "cast").is_empty(), "C no cast event without an enemy inside")
	var near := enemy(run, Vector2(1.5, 0))
	run.step()
	var casts: Array = run.events.filter(func(e): return e.type == "cast" and e.skill_id == EMBER_RING)
	check(casts.size() == 1 and casts[0].shape == "ring" and int(casts[0].radius_cm) == 220, "C an enemy inside: one ring cast with shape ring and radius_cm 220")
	var hits: Array = run.events.filter(func(e): return e.type == "hit" and e.skill_id == EMBER_RING)
	check(hits.size() == 1 and int(hits[0].target_id) == near, "C the ring hit the enemy inside only (the one 5 m away is untouched)")
	check(int(run.enemies[far].hp_raw) == int(run.enemies[far].max_hp_raw), "C the far enemy took nothing")
	check(int(run._next_cast[EMBER_RING]) == run.tick + int(run.effective_skill(EMBER_RING).effects.cooldown_ticks), "C the cooldown is reserved at the cast")
	# Pulses: a second pulse 24 ticks later.
	var pulse_doc := enabled_doc(func(d): d.spells[EMBER_RING].base.ring_pulses = 2)
	var pulsed := bench(EMBER, pulse_doc)
	give(pulsed, EMBER_RING)
	enemy(pulsed, Vector2(1.5, 0))
	pulsed._next_cast[EMBER_RING] = 0
	var cast_ticks: Array[int] = []
	var pulse_flags: Array = []
	for i in 40:
		pulsed.step()
		for e in pulsed.events:
			if e.type == "cast" and e.skill_id == EMBER_RING:
				cast_ticks.append(int(e.tick))
				pulse_flags.append(int(e.get("pulse", 1)))
	check(cast_ticks.size() == 2 and cast_ticks[1] - cast_ticks[0] == 24 and pulse_flags == [1, 2], "C ring_pulses 2: the second pulse 24 ticks later (%s %s)" % [str(cast_ticks), str(pulse_flags)])
	check(int(pulsed.metrics.casts.get(EMBER_RING, 0)) == 1, "C the pulse is not a second cast in the cast count")
	# Arc ring: ring_targets caps the targets, a shocked enemy comes first.
	var arc := bench(ARC)
	give(arc, ARC_RING)
	var ids: Array[int] = []
	for i in 7: ids.append(enemy(arc, Vector2(1.0 + float(i) * .15, 0.0)))
	arc._rebuild_grid()
	var targets: Array[int] = arc._ring_targets(ARC_RING, arc.effective_skill(ARC_RING).effects)
	# ring_targets 5, plus the one spare a shock detonation (block_targets 1) may earn.
	check(targets.size() == 6 and int(arc.effective_skill(ARC_RING).effects.ring_targets) == 5, "C arc ring: 5 targets at the start, one spare for a detonation (%d)" % targets.size())
	var last: int = ids[6]
	put_status(arc, last, "shock", 1, {ARC: 1})
	targets = arc._ring_targets(ARC_RING, arc.effective_skill(ARC_RING).effects)
	check(targets[0] == last and targets.size() == 6, "C arc ring: the shocked enemy is struck first although it is the farthest")
	# A hit budget smaller than the targets stops the strikes.
	var small_doc := enabled_doc(func(d): d.spells[EMBER_RING].base.hit_budget = 2; d.spells[EMBER_RING].reach[0] = {})
	var small := bench(EMBER, small_doc)
	give(small, EMBER_RING)
	for i in 5: enemy(small, Vector2(1.0 + float(i) * .2, 0.0))
	small._next_cast[EMBER_RING] = 0
	small.step()
	check(small.events.filter(func(e): return e.type == "hit" and e.skill_id == EMBER_RING).size() == 2, "C the ring never hits more targets than its hit budget")
	# Without the composition the ring ids are not spells at all.
	var plain := make_run(null)
	check(plain.effective_skill(EMBER_RING).is_empty() and not plain._is_ring(EMBER_RING), "C off: a ring id is no spell")

# ------------------------------------------------------------------ D

func part_d() -> void:
	var run := bench(EMBER)
	give(run, EMBER_RING)
	give(run, FROST)
	var tick_before: int = run.tick
	# D1 own status never detonates.
	var walker := enemy(run, Vector2(1.5, 0))
	var ring_effects: Dictionary = run.effective_skill(EMBER_RING).effects
	put_status(run, walker, "heat", 3, {EMBER_RING: 3})
	var own := strike(run, walker, EMBER_RING)
	check(own.detonate.is_empty() and not bool(own.hit.get("detonate", false)) and int(own.hit.damage_raw) == int(ring_effects.damage_raw), "D the ring does not detonate heat it put there itself (damage %d)" % int(own.hit.damage_raw))
	# D2 another spell's heat: per_stack 4000 x n, consumed.
	var other := enemy(run, Vector2(1.6, 0.3))
	put_status(run, other, "heat", 3, {EMBER: 3})
	var hot := strike(run, other, EMBER_RING)
	var want: int = int(ring_effects.damage_raw) * (10000 + 4000) / 10000
	check(int(hot.hit.damage_raw) == want and bool(hot.hit.get("detonate", false)), "D heat from the basic spell: the ring's flat +40% (%d, want %d)" % [int(hot.hit.damage_raw), want])
	check(not hot.detonate.is_empty() and hot.detonate.by_skill == EMBER_RING and hot.detonate.status == "heat" and hot.detonate.src_skill == EMBER and int(hot.detonate.stacks) == 3 and int(hot.detonate.target_id) == other and hot.detonate.has("cast_uid"), "D detonate event fields: " + str(hot.detonate))
	check(status_n(run, other, "heat") == 0, "D consume: the heat is gone after the detonation")
	var again := strike(run, other, EMBER_RING)
	check(again.detonate.is_empty() and int(again.hit.damage_raw) == int(ring_effects.damage_raw), "D a second ring hit finds no heat")
	# D3 mixed contributions: only the other spell's stacks count.
	var mixed := enemy(run, Vector2(1.7, -0.3))
	put_status(run, mixed, "heat", 5, {EMBER: 2, EMBER_RING: 3})
	var mixed_hit := strike(run, mixed, EMBER_RING)
	check(int(mixed_hit.detonate.get("stacks", -1)) == 2 and int(mixed_hit.hit.damage_raw) == int(ring_effects.damage_raw) * (10000 + 4000) / 10000, "D only the stacks another spell put there are multiplied (2 of 5)")
	# D4 expired status does nothing.
	var old := enemy(run, Vector2(1.8, 0.5))
	put_status(run, old, "heat", 4, {EMBER: 4}, -1)
	check(strike(run, old, EMBER_RING).detonate.is_empty(), "D an expired status is not detonated")
	# D5 depth 1 hit: no detonation.
	var deep := enemy(run, Vector2(1.2, 0.8))
	put_status(run, deep, "heat", 4, {EMBER: 4})
	var deep_hit := strike(run, deep, EMBER_RING, 1)
	check(deep_hit.detonate.is_empty() and status_n(run, deep, "heat") == 4, "D a triggered (depth 1) hit neither detonates nor consumes")
	# D6 the basic spell applies the status on a direct hit.
	var fresh := enemy(run, Vector2(1.0, -0.8))
	strike(run, fresh, EMBER)
	var heat: Dictionary = run.enemies[fresh].status.heat
	check(int(heat.n) == 1 and heat.src == EMBER and int(heat.until) == run.tick + 180, "D a direct ember hit puts heat 1, src ember, expiry 180 ticks on")
	for i in 8: strike(run, fresh, EMBER)
	check(status_n(run, fresh, "heat") == 6, "D heat stops at its maximum 6")
	var stack_hit := strike(run, fresh, EMBER_RING)
	check(int(stack_hit.hit.damage_raw) == int(ring_effects.damage_raw) * (10000 + 4000) / 10000, "D heat 6: still the flat +40% (bonus_bps, not per stack)")
	check(int(run.metrics.detonate.count) >= 3 and int(run.metrics.detonate.extra_raw) > 0 and run.metrics.detonate.pairs.has("pair.ember.basic_ring"), "D the detonation tally counts by pair: " + str(run.metrics.detonate))
	# D7 strong enemies take the damped share from the ring, a walker the full damage.
	var guardian := enemy(run, Vector2(1.9, -0.9), true)
	var strong := strike(run, guardian, EMBER_RING)
	check(int(strong.hit.damage_raw) == int(ring_effects.damage_raw) * 7500 / 10000, "D vs_strong_bps 7500: the ring deals three quarters to an elite (%d)" % int(strong.hit.damage_raw))
	var walker2 := enemy(run, Vector2(-1.5, 0))
	check(int(strike(run, walker2, EMBER_RING).hit.damage_raw) == int(ring_effects.damage_raw), "D a walker takes the full ring damage")
	var basic_on_elite := strike(run, guardian, EMBER)
	check(int(basic_on_elite.hit.damage_raw) == int(basic_on_elite.effects.damage_raw), "D a spell without vs_strong_bps deals full damage to an elite")
	check(run.tick == tick_before, "D the direct strikes did not advance the clock")
	# D8 evolved pair: the detonation bonus x1.5.
	var evo := bench(EMBER)
	give(evo, EMBER_RING)
	evo.growth._evolved.append(EMBER)
	evo.growth._evolve_partner[EMBER] = "pair.ember.basic_ring"
	var target := enemy(evo, Vector2(1.5, 0))
	put_status(evo, target, "heat", 2, {EMBER: 2})
	var evo_effects: Dictionary = evo.effective_skill(EMBER_RING).effects
	var evo_hit := strike(evo, target, EMBER_RING)
	check(int(evo_hit.hit.damage_raw) == int(evo_effects.damage_raw) * (10000 + 4000 * 15000 / 10000) / 10000, "D an evolved partner makes the pair's detonation x1.5 (%d)" % int(evo_hit.hit.damage_raw))
	# D9 frost: the ring detonates the lance's chill (flat +40%, consumed) and the detonation lengthens its freeze (block_bps).
	var cold := bench(FROST)
	give(cold, FROST_RING)
	var c1 := enemy(cold, Vector2(1.5, 0))
	put_status(cold, c1, "chill", 2, {FROST: 2})
	var cold_ring := strike(cold, c1, FROST_RING)
	check(int(cold_ring.hit.damage_raw) == int(cold_ring.effects.damage_raw) * 14000 / 10000 and not cold_ring.detonate.is_empty() and status_n(cold, c1, "chill") == 0, "D the frost ring on the lance's chill: +40%, consumed")
	check(int(cold.enemies[c1].frozen_until) == cold.tick + 120, "D that detonation freezes 120 ticks (80 x block_bps 15000)")
	var c2 := enemy(cold, Vector2(1.4, 0.4))
	put_status(cold, c2, "chill", 3, {FROST: 3})
	var self_lance := strike(cold, c2, FROST)
	check(self_lance.detonate.is_empty() and cold.tick < int(cold.enemies[c2].frozen_until) and status_n(cold, c2, "chill") == 0, "D chill the lance put there itself is not detonated; its fourth stack freezes (freeze_at 4)")
	var c3 := enemy(cold, Vector2(1.3, -0.4))
	strike(cold, c3, FROST_RING)
	check(status_n(cold, c3, "chill") == 0 and int(cold.enemies[c3].slow_bps) == 4000 and int(cold.enemies[c3].slow_until) == cold.tick + 90 and int(cold.enemies[c3].frozen_until) == cold.tick + 80, "D the frost ring puts no chill; slow 40% for 90 ticks, frozen 80 ticks")
	# D10 arc ring detonates shock (flat +40%, consumed).
	var spark := bench(ARC)
	give(spark, ARC_RING)
	var s1 := enemy(spark, Vector2(1.5, 0))
	strike(spark, s1, ARC)
	check(status_n(spark, s1, "shock") == 1, "D a direct arc hit puts shock")
	var ring_hit := strike(spark, s1, ARC_RING)
	check(int(ring_hit.hit.damage_raw) == int(ring_hit.effects.damage_raw) * 14000 / 10000 and status_n(spark, s1, "shock") == 0, "D the arc ring detonates shock: +40%, consumed")
	# D11 reaction pairs have no effect yet: a frost spell on an enemy with heat does nothing special.
	var steam := bench(EMBER)
	give(steam, FROST)
	var t := enemy(steam, Vector2(1.5, 0))
	put_status(steam, t, "heat", 3, {EMBER: 3})
	var cold_hit := strike(steam, t, FROST)
	check(cold_hit.detonate.is_empty() and int(cold_hit.hit.damage_raw) == int(cold_hit.effects.damage_raw) and not cold_hit.hit.has("reaction"), "D a reaction pair (ember x frost) is only a link now: no effect")

# ------------------------------------------------------------------ E

func pool(run: RefCounted) -> Array[Dictionary]:
	return run.growth._eligible_cards()

func part_e() -> void:
	var run := bench(EMBER)
	var ids := card_ids(pool(run))
	check("axis:%s:damage" % EMBER in ids and "axis:%s:reach" % EMBER in ids and "unlock:" + EMBER_RING in ids and "unlock:" + FROST in ids and "unlock:" + ARC in ids, "E fresh run: axis cards for the basic spell, unlock cards for the ring and both borrowed spells")
	check(not "unlock:" + FROST_RING in ids and not "unlock:" + ARC_RING in ids, "E the ember witch is not offered another witch's ring")
	check(not ids.any(func(i): return String(i).begins_with("rank:")), "E no rank card with the composition on")
	var frost := bench(FROST)
	check("unlock:" + FROST_RING in card_ids(pool(frost)) and not "unlock:" + EMBER_RING in card_ids(pool(frost)), "E the frost witch is offered her own ring only")
	# Caps: 4 per axis, 6 per spell.
	run.growth._axes[EMBER] = {"damage": 4, "reach": 1}
	ids = card_ids(pool(run))
	check(not "axis:%s:damage" % EMBER in ids and "axis:%s:reach" % EMBER in ids, "E damage axis at 4: no 5th point, reach still offered")
	run.growth._axes[EMBER] = {"damage": 3, "reach": 3}
	ids = card_ids(pool(run))
	check(not ids.any(func(i): return String(i).begins_with("axis:" + EMBER)), "E axis sum 6: no axis card for that spell at all")
	run.growth._axes[EMBER] = {"damage": 4, "reach": 2}
	check(not card_ids(pool(run)).any(func(i): return String(i).begins_with("axis:" + EMBER)), "E damage 4 + reach 2 = 6: capped")
	run.growth._axes[EMBER] = {"damage": 0, "reach": 0}
	# A card that was not offered cannot be chosen (the 5th point, a foreign ring).
	run.growth._axes[EMBER] = {"damage": 4, "reach": 0}
	run.growth.award_xp(10)
	var offer: Dictionary = run.growth.next_offer()
	check(not run.growth.choose(String(offer.token), "axis:%s:damage" % EMBER), "E choosing axis damage 5 is refused")
	check(not run.growth.choose(String(offer.token), "unlock:" + FROST_RING), "E choosing another witch's ring is refused")
	run.growth._axes[EMBER] = {"damage": 0, "reach": 0}
	# Slots: three spells fill the bar; no unlock card then.
	var full := bench(EMBER)
	give(full, FROST)
	check(card_ids(pool(full)).any(func(i): return String(i).begins_with("unlock:")), "E two of three slots used: unlock cards exist")
	give(full, ARC)
	ids = card_ids(pool(full))
	check(not ids.any(func(i): return String(i).begins_with("unlock:")) and ids.any(func(i): return String(i).begins_with("axis:")), "E three spells: no unlock card, axis cards remain")
	var tight := bench(EMBER, enabled_doc(func(d): d.slots = 2))
	give(tight, EMBER_RING)
	check(not card_ids(pool(tight)).any(func(i): return String(i).begins_with("unlock:")), "E slots 2 in the document: the second spell fills the bar")
	# Evolution: axis sum 5 + crystal; a pair partner with axis sum 2.
	var evo := bench(EMBER)
	evo.growth._axes[EMBER] = {"damage": 3, "reach": 2}
	evo.growth._owned_passives.append("chapter1.passive.embers")
	check(not "evolve:" + EMBER in card_ids(pool(evo)), "E axis 5 + crystal but no partner: no evolve card")
	give(evo, EMBER_RING, 1, 0)
	check(not "evolve:" + EMBER in card_ids(pool(evo)), "E partner with axis 1: still no evolve card")
	give(evo, EMBER_RING, 1, 1)
	var evolve_cards := pool(evo).filter(func(c): return c.kind == "evolve")
	check(evolve_cards.size() == 1 and evolve_cards[0].partner_pair == "pair.ember.basic_ring" and evolve_cards[0].partner_skill == EMBER_RING, "E partner axis 2: the evolve card appears and names the pair")
	evo.growth._axes[EMBER] = {"damage": 3, "reach": 1}
	check(not "evolve:" + EMBER in card_ids(pool(evo)), "E own axis sum 4: no evolve card")
	evo.growth._axes[EMBER] = {"damage": 3, "reach": 2}
	evo.growth._owned_passives.clear()
	check(not "evolve:" + EMBER in card_ids(pool(evo)), "E no crystal: no evolve card")
	evo.growth._owned_passives.append("chapter1.passive.embers")
	var progress: Dictionary = evo.growth.evolve_progress(EMBER)
	check(int(progress.axis.have) == 5 and int(progress.axis.need) == 5 and bool(progress.passive.have) and int(progress.partner.have) == 2 and int(progress.partner.need) == 2 and progress.partner.skill == EMBER_RING, "E evolve_progress: " + str(progress))
	# Choosing it records the pair.
	evo.growth.award_xp(10)
	var evo_offer: Dictionary = evo.growth.next_offer()
	var evolve_offered := false
	for card in evo_offer.cards: evolve_offered = evolve_offered or card.kind == "evolve"
	check(evolve_offered, "E the evolve card is in the offer (protected: it is the nearest to evolution)")
	if evolve_offered:
		check(evo.growth.choose(String(evo_offer.token), "evolve:" + EMBER), "E the evolve card can be chosen")
		var snap: Dictionary = evo.growth.snapshot()
		check(snap.evolved.has(EMBER) and snap.evolve_partner.get(EMBER, "") == "pair.ember.basic_ring", "E the snapshot keeps the evolve partner pair: " + str(snap.evolve_partner))
	# Protected cards (B0.4).
	for seed_ in 12:
		var r = make_run(enabled_doc(), 20 + seed_, EMBER)
		r.growth.award_xp(10)
		var level2: Dictionary = r.growth.next_offer()
		check(int(level2.level) == 2 and "unlock:" + EMBER_RING in card_ids(level2.cards), "E level 2 always offers the witch's ring (seed %d)" % (20 + seed_))
		check(level2.cards.size() == 3, "E the offer has three cards (seed %d)" % (20 + seed_))
	var third := bench(EMBER)
	give(third, EMBER_RING)
	third.growth._pending.assign([3])
	var level3: Array[Dictionary] = pool(third)
	var pick3: int = third.growth._protected_spell_card(level3)
	check(pick3 >= 0 and level3[pick3].kind == "unlock" and not Spells_pair(third, String(level3[pick3].skill_id)).is_empty(), "E level 3: a spell that pairs with one owned is protected (%s)" % (level3[pick3].id if pick3 >= 0 else "none"))
	var fifth := bench(EMBER)
	give(fifth, EMBER_RING, 0, 0)
	give(fifth, FROST, 2, 0)
	fifth.growth._axes[EMBER] = {"damage": 2, "reach": 0}
	fifth.growth._pending.assign([5])
	var level5: Array[Dictionary] = pool(fifth)
	var pick5: int = fifth.growth._protected_spell_card(level5)
	check(pick5 >= 0 and level5[pick5].kind == "axis" and level5[pick5].skill_id == EMBER_RING, "E level 5, slots full: the weaker owner of an owned pair gets the protected axis card (%s)" % (level5[pick5].id if pick5 >= 0 else "none"))
	var late := bench(EMBER)
	give(late, EMBER_RING, 1, 1)
	late.growth._axes[EMBER] = {"damage": 2, "reach": 2}
	late.growth._pending.assign([8])
	var level8: Array[Dictionary] = pool(late)
	var pick8: int = late.growth._protected_spell_card(level8)
	check(pick8 >= 0 and level8[pick8].kind == "axis" and level8[pick8].skill_id == EMBER, "E level 8: the protected card brings the nearest evolution closer (%s)" % (level8[pick8].id if pick8 >= 0 else "none"))
	late.growth._axes[EMBER] = {"damage": 3, "reach": 2}
	var level8b: Array[Dictionary] = pool(late)
	var pick8b: int = late.growth._protected_spell_card(level8b)
	check(pick8b >= 0 and level8b[pick8b].kind == "passive", "E axis sum 5 but no crystal: the crystal card is the protected one")
	var off_protect := bench(EMBER, enabled_doc(func(d): d.protect.toward_evolve = false))
	off_protect.growth._pending.assign([8])
	check(off_protect.growth._protected_spell_card(pool(off_protect)) == -1, "E toward_evolve false: nothing protected after the opening levels")
	# Composed effect: base, then reach, then damage and cooldown multipliers; primary_bonus is not read.
	var comp := bench(EMBER)
	var zero: Dictionary = comp.effective_skill(EMBER).effects
	check(int(zero.damage_raw) == 3584 and int(zero.cooldown_ticks) == 48 and int(zero.projectiles) == 1 and int(zero.radius_cm) == 0 and int(zero.hit_budget) == 1, "E level 0: the base values, primary_bonus unused (%s)" % str(zero))
	comp.growth._axes[EMBER] = {"damage": 2, "reach": 2}
	var two: Dictionary = comp.effective_skill(EMBER).effects
	check(int(two.damage_raw) == 3584 * 18000 / 10000 and int(two.cooldown_ticks) == 48 * 8600 / 10000 and int(two.radius_cm) == 120 and int(two.projectiles) == 2 and int(two.hit_budget) == 8, "E damage 2 / reach 2 composes (%s)" % str(two))
	check(int(comp.effective_skill(EMBER).rank) == 5, "E the rank number the screen reads is 1 + axis points")
	give(comp, FROST)
	var borrowed: Dictionary = comp.effective_skill(FROST).effects
	check(int(borrowed.damage_raw) == 3072 and int(borrowed.chain_targets) <= 4, "E a borrowed spell starts at its base values and keeps the borrow rules")
	# Read-only view.
	var view_run := bench(EMBER)
	give(view_run, EMBER_RING, 1, 0)
	var view: Dictionary = view_run.run_spells_view()
	check(view.enabled and view.spells.size() == 2 and view.spells[EMBER_RING].role == "ring" and JSON.stringify(view.spells[EMBER].pairs_owned) == '["pair.ember.basic_ring"]', "E run_spells_view lists the owned spells with their pairs")
	check(view.spells[EMBER_RING].axis == {"damage": 1, "reach": 0} and view.spells[EMBER].evolve_progress.partner.skill == EMBER_RING and view.spells[EMBER_RING].evolve_progress.is_empty(), "E run_spells_view: axis levels, evolve progress (none for a ring)")
	view_run.growth.award_xp(10)
	var standing: Dictionary = view_run.growth.next_offer()
	var before_state := JSON.stringify(view_run.snapshot())
	var view2: Dictionary = view_run.run_spells_view()
	check(JSON.stringify(view_run.snapshot()) == before_state, "E run_spells_view changes nothing")
	var all_listed := true
	for card in standing.cards: all_listed = all_listed and view2.offer.has(String(card.id))
	check(all_listed and view2.offer.size() == standing.cards.size(), "E every card of the standing offer has its pairs_if_taken")
	var frost_card := {"skill_id": FROST}
	check(view_run.growth.pairs_if_taken(frost_card).has("pair.react.steam"), "E pairs_if_taken: frost with ember owned forms the steam pair link")
	var drawn := bench(EMBER)
	var stream: String = drawn.growth.snapshot().rng_state
	drawn.run_spells_view()
	check(drawn.growth.snapshot().rng_state == stream, "E the view never draws an offer or moves the random stream")

func Spells_pair(run: RefCounted, id_: String) -> Array[String]:
	return run.growth.pairs_if_taken({"skill_id": id_})

# ------------------------------------------------------------------ G (G5-3.1: falloff, stagger, ring controls, I0, I1, I2, culprit records)

## A body of any kind held in a recovery that never ends (still, not controlled).
func foe(run: RefCounted, kind: String, at: Vector2) -> int:
	run._spawn(kind, at)
	var id_: int = run._enemy_sequence
	var e: Dictionary = run.enemies[id_]
	e.state = "recover"
	e.state_until = FAR
	if kind != "elite":
		e.hp_raw = 100000 * 256
		e.max_hp_raw = e.hp_raw
	return id_

## Puts the body into a wind-up that ends on the next step, aimed at the hero.
func ready_to_strike(run: RefCounted, id_: int, attack_kind: String) -> void:
	var e: Dictionary = run.enemies[id_]
	e.state = "windup"
	e.state_until = run.tick + 1
	e.telegraph = {}
	e.attack_kind = attack_kind
	e.attack_direction = (run.hero.position - e.position).normalized()

func events_of(run: RefCounted, type_: String) -> Array:
	return run.events.filter(func(e): return e.type == type_)

func first_hero_hit(run: RefCounted, steps: int) -> Dictionary:
	for i in steps:
		run.step()
		var hits := events_of(run, "hero_hit")
		if not hits.is_empty(): return hits[0]
		if run.mode != "playing": break
	return {}

func part_g() -> void:
	g_validation()
	g_falloff_and_control()
	g_strong()
	g_vs_cc_and_aim()
	g_interlock()
	g_culprit()
	g_off()

func g_validation() -> void:
	var labels: Array[String] = ["interlock via empty", "interlock via unknown class", "interlock via duplicate", "interlock key", "vs_cc unknown class", "vs_cc 20001", "vs_cc on a ring",
		"prefer_kinds three", "prefer_kinds walker", "prefer_kinds duplicate", "prefer_kind_cm 1301", "prefer_when_clear_cm 401", "prefer_cc_cm 1301", "prefer_kinds on a ring",
		"block_bps 9999", "block_bps on a basic", "block_targets without ring_targets", "near_cm beyond the radius", "falloff 999", "stagger 181", "freeze 241", "stun 121",
		"strong_pct 3001", "strong_floor 9001", "stagger on a basic", "marks_resonance not bool", "interlock b has no vs_cc for the class"]
	for label in labels:
		var doc := enabled_doc()
		match label:
			"interlock via empty": doc.pairs[3].via = []
			"interlock via unknown class": doc.pairs[3].via = ["floating"]
			"interlock via duplicate": doc.pairs[3].via = ["staggered", "staggered"]
			"interlock key": doc.pairs[3].extra = 1
			"vs_cc unknown class": doc.spells[EMBER].vs_cc.burning = 100
			"vs_cc 20001": doc.spells[EMBER].vs_cc.frozen = 20001
			"vs_cc on a ring": doc.spells[EMBER_RING].vs_cc = {"frozen": 100}
			"prefer_kinds three": doc.spells[EMBER].prefer_kinds = ["ranged", "charger", "ranged"]
			"prefer_kinds walker": doc.spells[EMBER].prefer_kinds = ["walker"]
			"prefer_kinds duplicate": doc.spells[EMBER].prefer_kinds = ["ranged", "ranged"]
			"prefer_kind_cm 1301": doc.spells[EMBER].prefer_kind_cm = 1301
			"prefer_when_clear_cm 401": doc.spells[EMBER].prefer_when_clear_cm = 401
			"prefer_cc_cm 1301": doc.spells[EMBER].prefer_cc_cm = 1301
			"prefer_kinds on a ring": doc.spells[EMBER_RING].prefer_kinds = ["ranged"]
			"block_bps 9999": doc.spells[EMBER_RING].detonates.heat.block_bps = 9999
			"block_bps on a basic": doc.spells[EMBER].detonates = {"heat": {"bonus_bps": 100, "consume": true, "block_bps": 15000}}
			"block_targets without ring_targets": doc.spells[EMBER_RING].detonates.heat.block_targets = 1
			"near_cm beyond the radius": doc.spells[EMBER_RING].base.near_cm = 300
			"falloff 999": doc.spells[EMBER_RING].base.falloff_floor_bps = 999
			"stagger 181": doc.spells[EMBER_RING].base.stagger_ticks = 181
			"freeze 241": doc.spells[FROST_RING].base.freeze_ticks = 241
			"stun 121": doc.spells[ARC_RING].base.stun_ticks = 121
			"strong_pct 3001": doc.spells[ARC_RING].base.strong_pct_bps = 3001
			"strong_floor 9001": doc.spells[ARC_RING].base.strong_floor_bps = 9001
			"stagger on a basic": doc.spells[EMBER].base.stagger_ticks = 10
			"marks_resonance not bool": doc.marks_resonance = "no"
			"interlock b has no vs_cc for the class": doc.spells[EMBER].vs_cc.erase("staggered")
		check(not problems(doc).is_empty(), "G refused: " + label)
		var run = Chapter.new()
		check(not run.set_run_spells(doc) and run._pending_spells.is_empty(), "G set_run_spells keeps the run unchanged: " + label)
	# What stays legal: no marks_resonance key at all, and the older detonation pair kind.
	var plain := enabled_doc()
	plain.erase("marks_resonance")
	check(problems(plain).is_empty(), "G marks_resonance is optional: " + str(problems(plain)))
	check(enabled_doc().pairs.filter(func(p): return p.kind == "detonate").size() == 3, "G the shipped file keeps the three same-element detonation pairs (applier, then ring)")
	var no_detonate := enabled_doc()
	no_detonate.pairs = no_detonate.pairs.filter(func(p): return p.kind != "detonate")
	check(problems(no_detonate).is_empty(), "G a document with interlock and reaction pairs only validates: " + str(problems(no_detonate)))
	check(enabled_doc().pairs.filter(func(p): return p.kind == "interlock").size() == 7, "G the shipped file lists three ring and four borrowed interlock pairs")
	check(problems(enabled_doc()).is_empty() and enabled_doc().enabled and not shipped().enabled, "G the shipped file validates and stays off")

func g_falloff_and_control() -> void:
	# Falloff: 10000 is no falloff at all; 4000 gives 100% inside near_cm and 40% at the edge, straight in between.
	var flat := bench(EMBER)
	give(flat, EMBER_RING)
	var a := enemy(flat, Vector2(1.0, 0))
	var b := enemy(flat, Vector2(2.2, 0))
	var full_damage := int(flat.effective_skill(EMBER_RING).effects.damage_raw)
	check(int(strike(flat, a, EMBER_RING).hit.damage_raw) == full_damage and int(strike(flat, b, EMBER_RING).hit.damage_raw) == full_damage, "G falloff_floor_bps 10000: every distance deals the same")
	var sloped := bench(EMBER, enabled_doc(func(d): d.spells[EMBER_RING].base.falloff_floor_bps = 4000))
	give(sloped, EMBER_RING)
	var s1 := enemy(sloped, Vector2(1.0, 0))
	var s2 := enemy(sloped, Vector2(1.7, 0))
	var s3 := enemy(sloped, Vector2(2.2, 0))
	var base_damage := int(sloped.effective_skill(EMBER_RING).effects.damage_raw)
	check(int(strike(sloped, s1, EMBER_RING).hit.damage_raw) == base_damage, "G falloff 4000: inside near_cm 100%")
	check(int(strike(sloped, s2, EMBER_RING).hit.damage_raw) == base_damage * 7000 / 10000, "G falloff 4000: halfway between near and the edge 70%")
	check(int(strike(sloped, s3, EMBER_RING).hit.damage_raw) == base_damage * 4000 / 10000, "G falloff 4000: at the edge 40%")
	var cold := bench(FROST, enabled_doc(func(d): d.spells[FROST_RING].base.falloff_floor_bps = 4000))
	give(cold, FROST_RING)
	var edge := enemy(cold, Vector2(2.2, 0))
	strike(cold, edge, FROST_RING)
	check(int(cold.enemies[edge].frozen_until) == cold.tick + 80, "G the falloff never scales a control: the edge enemy is frozen the full 80 ticks")
	# Stagger: a body in its wind-up loses the attack, stands still, and does not start another while staggered.
	var run := bench(EMBER)
	give(run, EMBER_RING)
	var winding := foe(run, "walker", Vector2(1.0, 0))
	ready_to_strike(run, winding, "circle")
	run.enemies[winding].telegraph = {"shape": "circle", "remaining_ticks": 5}
	var hit := strike(run, winding, EMBER_RING)
	var e: Dictionary = run.enemies[winding]
	var staggers := events_of(run, "stagger")
	check(e.state == "recover" and int(e.state_until) == run.tick + 60 and e.telegraph.is_empty() and int(e.staggered_until) == run.tick + 60, "G the ring cuts a wind-up: recover for 60 ticks, no telegraph (%s)" % str(e.state))
	check(staggers.size() == 1 and bool(staggers[0].cut) and int(staggers[0].target_id) == winding, "G the stagger event says cut:true")
	check(e.cc_src.staggered == EMBER_RING, "G the stagger remembers the ring as its source")
	var dashing := foe(run, "charger", Vector2(3.0, 0))
	run.enemies[dashing].state = "dash"
	run.enemies[dashing].state_until = run.tick + 20
	run.enemies[dashing].attack_direction = Vector2.LEFT
	strike(run, dashing, EMBER_RING)
	check(run.enemies[dashing].state == "recover" and not events_of(run, "stagger").is_empty() and bool(events_of(run, "stagger")[0].cut), "G the ring stops a dash on the spot")
	var idle := foe(run, "walker", Vector2(-1.0, 0))
	strike(run, idle, EMBER_RING)
	check(not bool(events_of(run, "stagger")[0].cut) and int(run.enemies[idle].staggered_until) == run.tick + 60, "G a body that was not attacking is staggered with cut:false")
	# Standing still, starting nothing: 59 ticks (the 60th hands it back).
	var still_at: Vector2 = run.enemies[idle].position
	run.enemies[idle].state = "move"
	run.enemies[idle].state_until = 0
	var begun := false
	for i in 59:
		run.step()
		begun = begun or run.enemies[idle].state != "move"
	check(begun == false and run.enemies[idle].position == still_at, "G staggered for 60 ticks: it neither moves nor begins an attack")
	run.step()
	run.step()
	check(run.enemies[idle].position != still_at or run.enemies[idle].state != "move", "G once the stagger is over it acts again")
	var guardian := enemy(run, Vector2(1.5, 0.5), true)
	strike(run, guardian, EMBER_RING)
	check(not run.enemies[guardian].has("staggered_until") and events_of(run, "stagger").is_empty(), "G a strong enemy is never staggered")
	# Direct freeze and stun by the rings.
	var ice := bench(FROST)
	give(ice, FROST_RING)
	var plain := enemy(ice, Vector2(1.0, 0))
	var elite := enemy(ice, Vector2(1.2, 0.2), true)
	strike(ice, plain, FROST_RING)
	strike(ice, elite, FROST_RING)
	check(int(ice.enemies[plain].frozen_until) == ice.tick + 80 and int(ice.enemies[elite].frozen_until) == ice.tick + 12, "G the frost ring freezes an ordinary enemy 80 ticks and a strong one 12")
	check(ice.enemies[plain].cc_src.frozen == FROST_RING, "G the freeze remembers the frost ring")
	var storm := bench(ARC)
	give(storm, ARC_RING)
	var s_plain := enemy(storm, Vector2(1.0, 0))
	var s_elite := enemy(storm, Vector2(1.2, 0.2), true)
	strike(storm, s_plain, ARC_RING)
	var first_stun := events_of(storm, "stun")
	strike(storm, s_elite, ARC_RING)
	check(int(storm.enemies[s_plain].stunned_until) == storm.tick + 45 and first_stun.size() == 1 and int(first_stun[0].duration_ticks) == 45, "G the arc ring stuns an ordinary enemy 45 ticks (stun event)")
	check(int(storm.enemies[s_elite].stunned_until) == storm.tick + Chapter.ARC_ELITE_STUN_TICKS36, "G a strong enemy is stunned by the direct-hit rule (6 ticks)")
	var until_before: int = storm.enemies[s_elite].stunned_until
	strike(storm, s_elite, ARC_RING)
	check(int(storm.enemies[s_elite].stunned_until) == until_before and events_of(storm, "stun").is_empty(), "G a strong enemy is not stunned again inside the immunity")
	# I2: a detonation lengthens the controls by block_bps and frees one more target.
	var fire := bench(EMBER)
	give(fire, EMBER_RING)
	var marked := enemy(fire, Vector2(1.0, 0))
	put_status(fire, marked, "heat", 2, {EMBER: 2})
	strike(fire, marked, EMBER_RING)
	check(int(fire.enemies[marked].staggered_until) == fire.tick + 90, "G heat from the basic spell lengthens the stagger by 150% (90 ticks)")
	var unmarked := enemy(fire, Vector2(1.1, 0.2))
	strike(fire, unmarked, EMBER_RING)
	check(int(fire.enemies[unmarked].staggered_until) == fire.tick + 60, "G no heat: the plain 60 ticks")
	var spark := bench(ARC)
	give(spark, ARC_RING)
	var ids: Array[int] = []
	for i in 7: ids.append(enemy(spark, Vector2(1.0 + float(i) * .15, 0.0)))
	spark._next_cast[ARC_RING] = 0
	spark.step()
	check(events_of(spark, "hit").filter(func(h): return h.skill_id == ARC_RING).size() == 5, "G arc ring without shock: 5 targets")
	var shock := bench(ARC)
	give(shock, ARC_RING)
	var s_ids: Array[int] = []
	for i in 7: s_ids.append(enemy(shock, Vector2(1.0 + float(i) * .15, 0.0)))
	put_status(shock, s_ids[3], "shock", 1, {ARC: 1})
	shock._next_cast[ARC_RING] = 0
	shock.step()
	var struck := events_of(shock, "hit").filter(func(h): return h.skill_id == ARC_RING)
	var shown: Array = events_of(shock, "cast").filter(func(c): return c.skill_id == ARC_RING)[0].targets
	check(struck.size() == 6 and shown.size() == 5, "G a shock detonation frees one more target: 6 struck, the cast event shows the 5 chosen (%d, %d)" % [struck.size(), shown.size()])
	check(int(shock.metrics.ward.i2_hits) == 1 and int(shock.metrics.ward.casts) == 1 and int(shock.metrics.ward.hits) == 6 and int(shock.metrics.ward.stuns) == 6, "G ward tally: " + str(shock.metrics.ward))
	check(events_of(shock, "detonate")[0].pair == "pair.arc.basic_ring", "G the detonate event names the pair")
	var tally := bench(EMBER)
	give(tally, EMBER_RING)
	for i in 3: enemy(tally, Vector2(1.0 + float(i) * .3, 0.0))
	tally._next_cast[EMBER_RING] = 0
	tally.step()
	check(int(tally.metrics.ward.casts) == 1 and int(tally.metrics.ward.hits) == 3 and int(tally.metrics.ward.staggers) == 3 and int(tally.metrics.ward.kills) == 0, "G ward tally of an ember ring cast: " + str(tally.metrics.ward))

func g_strong() -> void:
	var run := bench(ARC)
	give(run, ARC_RING)
	var big := enemy(run, Vector2(1.0, 0), true)
	var e: Dictionary = run.enemies[big]
	var raw := int(run.effective_skill(ARC_RING).effects.damage_raw)
	var plain_part := raw * 7500 / 10000
	var hp := int(e.hp_raw)
	var share := hp * 400 / 10000
	var strong := strike(run, big, ARC_RING)
	check(int(strong.hit.damage_raw) == plain_part + share, "G the arc ring adds 4%% of a strong enemy's current life (%d, want %d)" % [int(strong.hit.damage_raw), plain_part + share])
	# The floor: the proportional share never takes the life below 40% of its maximum.
	var low := enemy(run, Vector2(1.2, 0.3), true)
	run.enemies[low].hp_raw = int(run.enemies[low].max_hp_raw) * 4100 / 10000
	var floor_hp := int(run.enemies[low].max_hp_raw) * 4000 / 10000
	strike(run, low, ARC_RING)
	check(int(run.enemies[low].hp_raw) == floor_hp, "G the proportional share stops at 40%% of the maximum life (%d, want %d)" % [int(run.enemies[low].hp_raw), floor_hp])
	var under := enemy(run, Vector2(1.4, -0.3), true)
	run.enemies[under].hp_raw = int(run.enemies[under].max_hp_raw) * 3000 / 10000
	var before := int(run.enemies[under].hp_raw)
	strike(run, under, ARC_RING)
	check(before - int(run.enemies[under].hp_raw) == plain_part, "G below the floor only the plain hit lands")
	var walker := enemy(run, Vector2(-1.0, 0))
	check(int(strike(run, walker, ARC_RING).hit.damage_raw) == raw, "G an ordinary enemy takes no proportional share")
	var fire := bench(EMBER)
	give(fire, EMBER_RING)
	var fire_big := enemy(fire, Vector2(1.0, 0), true)
	check(int(strike(fire, fire_big, EMBER_RING).hit.damage_raw) == int(fire.effective_skill(EMBER_RING).effects.damage_raw) * 7500 / 10000, "G the other rings have no proportional share")

func g_vs_cc_and_aim() -> void:
	var run := bench(EMBER)
	give(run, EMBER_RING)
	give(run, FROST)
	var raw := int(run.effective_skill(EMBER).effects.damage_raw)
	var chilled := enemy(run, Vector2(1.5, 0))
	var e: Dictionary = run.enemies[chilled]
	e.frozen_until = FAR
	run._set_cc_src(e, "frozen", FROST_RING)
	var hit := strike(run, chilled, EMBER)
	check(int(hit.hit.damage_raw) == raw * 16000 / 10000 and hit.hit.vs_cc == "frozen", "G a basic hit on an enemy the ring froze: +60%% (%d)" % int(hit.hit.damage_raw))
	check(int(run.metrics.ward.vs_cc_hits) == 1 and int(run.metrics.ward.vs_cc_extra_raw) == raw * 16000 / 10000 - raw, "G ward counts the vs_cc hit and what it added")
	run._set_cc_src(e, "frozen", EMBER)
	check(not strike(run, chilled, EMBER).hit.has("vs_cc"), "G a control the spell itself put on gives it no bonus")
	e.frozen_until = 0
	e.slow_until = run.tick + 100
	e.slow_bps = 2000
	e.cc_src.erase("slowed")
	check(int(strike(run, chilled, EMBER).hit.damage_raw) == raw * 12500 / 10000, "G a slowed enemy (20%% or more): +25%%")
	e.slow_bps = 1500
	check(not strike(run, chilled, EMBER).hit.has("vs_cc"), "G a slow under 20% counts for nothing")
	e.slow_bps = 2000
	e.stunned_until = FAR
	check(int(strike(run, chilled, EMBER).hit.damage_raw) == raw * 16000 / 10000, "G stunned and slowed: the biggest one only, not both")
	check(not strike(run, chilled, EMBER, 1).hit.has("vs_cc"), "G a triggered (depth 1) hit gets no vs_cc")
	e.stunned_until = 0
	# The lance's own slow gives the lance nothing; the other basic spell gets its 25%.
	var cold := enemy(run, Vector2(1.6, 0.4))
	strike(run, cold, FROST)
	check(not strike(run, cold, FROST).hit.has("vs_cc") and strike(run, cold, EMBER).hit.get("vs_cc", "") == "slowed", "G the lance gets nothing from its own slow, the ember spell does")
	var bolt := bench(ARC)
	give(bolt, ARC_RING)
	var victim := enemy(bolt, Vector2(1.5, 0))
	strike(bolt, victim, ARC)
	check(bolt.tick < int(bolt.enemies[victim].stunned_until) and bolt.enemies[victim].cc_src.stunned == ARC, "G a direct arc hit stuns and remembers itself")
	check(not strike(bolt, victim, ARC).hit.has("vs_cc"), "G the arc spell gets nothing from its own stun")
	check(strike(bolt, victim, ARC_RING).hit.damage_raw > 0 and not strike(bolt, victim, ARC_RING).hit.has("vs_cc"), "G a ring never takes vs_cc")
	# Aim: I1 (controlled enemy first), I0 (a far shooter when the near side is clear).
	var aim := bench(EMBER)
	var near := foe(aim, "walker", Vector2(3.0, 0))
	var held := foe(aim, "walker", Vector2(6.0, 0))
	aim.enemies[held].frozen_until = FAR
	aim._set_cc_src(aim.enemies[held], "frozen", FROST_RING)
	aim._rebuild_grid()
	var chosen: Dictionary = aim._aim(EMBER, aim._near(aim.hero.position, 13.0))
	check(chosen.id == held and chosen.how == "cc", "G I1: the controlled enemy within 9 m is aimed at before the nearest")
	aim._set_cc_src(aim.enemies[held], "frozen", EMBER)
	chosen = aim._aim(EMBER, aim._near(aim.hero.position, 13.0))
	check(chosen.id == near and chosen.how == "", "G I1: a control the spell put there itself is not preferred")
	aim._set_cc_src(aim.enemies[held], "frozen", FROST_RING)
	aim.enemies[held].position = Vector2(10.0, 0)
	aim._rebuild_grid()
	chosen = aim._aim(EMBER, aim._near(aim.hero.position, 13.0))
	check(chosen.id == near and chosen.how == "", "G I1: beyond 9 m it is not preferred")
	var eye := bench(EMBER)
	var nearby := foe(eye, "walker", Vector2(1.5, 0))
	var shooter := foe(eye, "ranged", Vector2(5.0, 0))
	var charger := foe(eye, "charger", Vector2(4.0, 0))
	eye._rebuild_grid()
	chosen = eye._aim(EMBER, eye._near(eye.hero.position, 13.0))
	check(chosen.id == nearby and chosen.how == "", "G I0: an uncontrolled ordinary enemy within 2 m: the nearest is aimed at")
	eye.enemies[nearby].frozen_until = FAR
	chosen = eye._aim(EMBER, eye._near(eye.hero.position, 13.0))
	check(chosen.id == shooter and chosen.how == "kind", "G I0: the enemy within 2 m is frozen, so the shooter within 9 m comes first (not the nearer charger)")
	eye.enemies[nearby].frozen_until = 0
	eye.enemies[nearby].staggered_until = FAR
	check(eye._aim(EMBER, eye._near(eye.hero.position, 13.0)).how == "kind", "G I0: a staggered near enemy counts as controlled")
	eye.enemies[nearby].staggered_until = 0
	eye.enemies[nearby].stunned_until = FAR
	check(eye._aim(EMBER, eye._near(eye.hero.position, 13.0)).how == "kind", "G I0: a stunned near enemy counts as controlled")
	eye.enemies[nearby].stunned_until = 0
	eye.enemies[nearby].position = Vector2(3.0, 0)
	eye._rebuild_grid()
	chosen = eye._aim(EMBER, eye._near(eye.hero.position, 13.0))
	check(chosen.id == shooter and chosen.how == "kind", "G I0: nobody within 2 m: the shooter at 5 m is aimed at, not the walker at 3 m")
	eye.enemies[shooter].position = Vector2(9.5, 0)
	eye._rebuild_grid()
	chosen = eye._aim(EMBER, eye._near(eye.hero.position, 13.0))
	check(chosen.id == nearby and chosen.how == "", "G I0: a shooter beyond 9 m is not aimed at")
	eye.enemies[shooter].position = Vector2(5.0, 0)
	var guard := foe(eye, "elite", Vector2(1.0, 0.5))
	eye.enemies.erase(nearby)
	eye._rebuild_grid()
	chosen = eye._aim(EMBER, eye._near(eye.hero.position, 13.0))
	check(chosen.id == shooter and chosen.how == "kind" and guard > 0, "G I0: a strong enemy at the hero does not count as an ordinary enemy being near")
	# With no shooter in range the I1 rule and then the nearest take over.
	eye.enemies.erase(shooter)
	eye.enemies.erase(guard)
	eye._rebuild_grid()
	chosen = eye._aim(EMBER, eye._near(eye.hero.position, 13.0))
	check(chosen.id == charger and chosen.how == "", "G I0: no shooter, no controlled enemy: the nearest (charger is not in prefer_kinds)")
	var wide := bench(EMBER, enabled_doc(func(d): d.spells[EMBER].prefer_kinds = ["ranged", "charger"]))
	var wide_charger := foe(wide, "charger", Vector2(4.0, 0))
	foe(wide, "walker", Vector2(3.0, 0))
	wide._rebuild_grid()
	chosen = wide._aim(EMBER, wide._near(wide.hero.position, 13.0))
	check(chosen.id == wide_charger and chosen.how == "kind", "G I0: prefer_kinds [ranged, charger] also reaches the charger")
	# A real cast: the event carries prefer:"kind", the shot flies at the shooter, the tally counts it.
	var live := bench(EMBER)
	var far_shooter := foe(live, "ranged", Vector2(0, 5.0))
	foe(live, "walker", Vector2(4.0, 0))
	live._next_cast[EMBER] = 0
	live.step()
	var casts := events_of(live, "cast").filter(func(c): return c.skill_id == EMBER)
	check(casts.size() == 1 and casts[0].get("prefer", "") == "kind" and casts[0].direction.is_equal_approx(Vector2(0, 1)) and int(live.metrics.ward.i0_casts) == 1 and far_shooter > 0, "G I0: the real cast aims at the shooter and says prefer:kind")
	var arc_live := bench(ARC)
	var arc_shooter := foe(arc_live, "ranged", Vector2(0, 5.0))
	foe(arc_live, "walker", Vector2(4.0, 0))
	arc_live._next_cast[ARC] = 0
	arc_live.step()
	var arc_hits := events_of(arc_live, "hit").filter(func(h): return h.skill_id == ARC)
	check(not arc_hits.is_empty() and int(arc_hits[0].target_id) == arc_shooter, "G I0: the arc chain starts at the shooter")
	# I0 does not exist without the composition: the nearest enemy is shot at.
	var plain := make_run(null)
	plain.enemies.clear()
	plain._next_spawn = FAR
	for id_ in plain._skill_ids: plain._next_cast[id_] = FAR
	plain._spawn("ranged", Vector2(0, 5.0))
	plain._spawn("walker", Vector2(4.0, 0))
	plain._next_cast[EMBER] = 0
	plain.step()
	var plain_casts := events_of(plain, "cast").filter(func(c): return c.skill_id == EMBER)
	check(plain_casts.size() == 1 and not plain_casts[0].has("prefer") and plain_casts[0].direction.is_equal_approx(Vector2(1, 0)), "G off: the nearest enemy is aimed at and the cast has no prefer key")
	# Marks: off while the composition is on, on again when the document says so.
	var marks := bench(EMBER)
	check(int(marks.tuning.marks.mark_bps) > 0, "G the tuning has a mark bonus to switch off")
	var marked := enemy(marks, Vector2(1.5, 0))
	marks.enemies[marked].mark_until_a = marks.tick + 100
	var base_hit := strike(marks, marked, EMBER)
	check(int(base_hit.hit.damage_raw) == int(base_hit.effects.damage_raw), "G the composition on: no mark resonance")
	var back := bench(EMBER, enabled_doc(func(d): d.marks_resonance = true))
	var back_marked := enemy(back, Vector2(1.5, 0))
	back.enemies[back_marked].mark_until_a = back.tick + 100
	var back_hit := strike(back, back_marked, EMBER)
	check(int(back_hit.hit.damage_raw) == int(back_hit.effects.damage_raw) * (10000 + int(back.tuning.marks.mark_bps)) / 10000, "G marks_resonance true: the mark bonus is back")

func g_interlock() -> void:
	var run := bench(EMBER)
	give(run, EMBER_RING)
	give(run, FROST)
	check(JSON.stringify(run.growth.pairs_owned(EMBER)) == '["pair.borrow.frost_ember","pair.ember.basic_ring"]', "G interlock pairs link ember with its ring and with the borrowed lance: " + JSON.stringify(run.growth.pairs_owned(EMBER)))
	var doc := enabled_doc()
	check(RunSpells.pair_between(doc, EMBER, EMBER_RING) == "pair.ember.basic_ring" and RunSpells.pair_between(doc, EMBER_RING, EMBER) == "pair.ember.basic_ring", "G pair_between reads an interlock in both directions")
	check(RunSpells.pair_between(doc, ARC, EMBER) == "pair.borrow.arc_ember" and RunSpells.pair_between(doc, FROST, ARC) == "pair.borrow.frost_arc", "G pair_between finds the borrowed interlocks")
	check(RunSpells.pair_between(doc, EMBER_RING, FROST) == "pair.react.steam", "G a ring and a foreign basic spell are linked by the reaction pair only")

func g_culprit() -> void:
	var run := bench(EMBER)
	# A walker's blow.
	var walker := foe(run, "walker", Vector2(1.0, 0))
	ready_to_strike(run, walker, "circle")
	var hp_before: int = run.hero.hp_raw
	var hit := first_hero_hit(run, 1)
	check(hit.get("source_kind", "") == "walker" and int(hit.get("source_id", -1)) == walker and int(hit.hp_after_raw) == int(run.hero.hp_raw) and int(run.hero.hp_raw) < hp_before, "G hero_hit: a walker's blow names walker and its id (%s)" % str(hit.get("source_kind", "?")))
	# A shot of a shooter that is already gone.
	var gun := bench(EMBER)
	var archer := foe(gun, "ranged", Vector2(6.0, 0))
	ready_to_strike(gun, archer, "fan")
	gun.step()
	gun.enemies.erase(archer)
	check(not gun._hostile_src.is_empty(), "G the side table remembers who shot")
	var shot := first_hero_hit(gun, 250)
	check(shot.get("source_kind", "") == "ranged" and int(shot.get("source_id", -1)) == archer and int(shot.hp_after_raw) == int(gun.hero.hp_raw), "G hero_hit: a shot names ranged and the shooter's id although the shooter died first (%s)" % str(shot.get("source_kind", "?")))
	check(gun._hostile_src.size() < 3, "G the side table forgets a shot that has landed")
	for p in gun.projectiles: check(not p.has("source_id") and not p.has("src") and not p.has("source_kind"), "G an enemy projectile gets no new key")
	# A charger's dash.
	var bull := bench(EMBER)
	var rusher := foe(bull, "charger", Vector2(2.0, 0))
	bull.enemies[rusher].state = "dash"
	bull.enemies[rusher].state_until = bull.tick + 32
	bull.enemies[rusher].attack_direction = Vector2.LEFT
	bull.enemies[rusher].attacked = false
	var dash := first_hero_hit(bull, 30)
	check(dash.get("source_kind", "") == "charger" and int(dash.get("source_id", -1)) == rusher, "G hero_hit: a dash names charger")
	# The strong ones: a body blow and a shot name the role.
	for role in ["elite", "champion", "boss"]:
		var arena := bench(EMBER)
		var big := foe(arena, "elite", Vector2(2.0, 0))
		if role != "elite": arena.enemies[big].title_key = "enemy.champion.0.name"
		if role == "boss": arena.enemies[big].chapter_boss = true
		check(arena._enemy_role(arena.enemies[big]) == role, "G _enemy_role names the %s" % role)
		ready_to_strike(arena, big, "circle")
		var blow := first_hero_hit(arena, 1)
		check(blow.get("source_kind", "") == role and int(blow.get("source_id", -1)) == big, "G hero_hit: the %s's circle names %s (%s)" % [role, role, str(blow.get("source_kind", "?"))])
		var volley := bench(EMBER)
		var shooter := foe(volley, "elite", Vector2(6.0, 0))
		if role != "elite": volley.enemies[shooter].title_key = "enemy.champion.0.name"
		if role == "boss": volley.enemies[shooter].chapter_boss = true
		ready_to_strike(volley, shooter, "fan")
		var fan := first_hero_hit(volley, 200)
		check(fan.get("source_kind", "") == role and int(fan.get("source_id", -1)) == shooter, "G hero_hit: the %s's fan of shots names %s (%s)" % [role, role, str(fan.get("source_kind", "?"))])
	# The final boss's floor strike.
	var ward := bench(EMBER)
	var warden := foe(ward, "elite", Vector2(15.0, 0))
	ward.enemies[warden].chapter_boss = true
	ward.enemies[warden].title_key = "enemy.champion.2.name"
	ward._champion_id = warden
	ward.zone = 2
	ward._boss_phase = 1
	ward._next_ward = FAR
	ward.chapter_hazards.append({"uid": 1, "position": ward.hero.position, "radius": 1.8, "started": ward.tick, "expires": ward.tick + 1, "damage_raw": 5 * 256})
	var strike_hit := first_hero_hit(ward, 2)
	check(strike_hit.get("source_kind", "") == "boss_ward" and int(strike_hit.get("source_id", -1)) == 0 and int(strike_hit.hp_after_raw) == int(ward.hero.hp_raw), "G hero_hit: the boss's floor strike names boss_ward (%s)" % str(strike_hit.get("source_kind", "?")))
	# Any other floor danger.
	var floor_run := bench(EMBER)
	floor_run._hero_damage(256, Vector2.ZERO)
	var floor_hit: Dictionary = events_of(floor_run, "hero_hit")[0]
	check(floor_hit.source_kind == "hazard" and int(floor_hit.source_id) == 0 and int(floor_hit.hp_after_raw) == int(floor_run.hero.hp_raw), "G hero_hit: a floor hazard names hazard, id 0")
	floor_run.events.clear()
	floor_run._invulnerable_until = floor_run.tick + 10
	floor_run._hero_damage(256, Vector2.ZERO)
	check(events_of(floor_run, "hero_hit").is_empty(), "G a blocked hit (invulnerable) makes no hero_hit event")
	# death.role.
	var deaths := bench(EMBER)
	give(deaths, EMBER_RING)
	var weak := enemy(deaths, Vector2(1.0, 0))
	deaths.enemies[weak].hp_raw = 1
	strike(deaths, weak, EMBER_RING)
	check(events_of(deaths, "death")[0].role == "normal", "G death.role: normal")
	var guard := enemy(deaths, Vector2(1.5, 0.3), true)
	deaths.enemies[guard].hp_raw = 1
	deaths.enemies[guard].title_key = "enemy.champion.0.name"
	strike(deaths, guard, EMBER_RING)
	check(events_of(deaths, "death")[0].role == "champion", "G death.role: champion")
	var knight := bench(EMBER)
	give(knight, EMBER_RING)
	var captain := enemy(knight, Vector2(1.0, 0), true)
	knight.enemies[captain].hp_raw = 1
	strike(knight, captain, EMBER_RING)
	check(events_of(knight, "death")[0].role == "elite", "G death.role: elite")
	# detonate.pair
	var pair_run := bench(EMBER)
	give(pair_run, EMBER_RING)
	var marked := enemy(pair_run, Vector2(1.0, 0))
	put_status(pair_run, marked, "heat", 1, {EMBER: 1})
	check(strike(pair_run, marked, EMBER_RING).detonate.get("pair", "") == "pair.ember.basic_ring" and pair_run.metrics.detonate.pairs.has("pair.ember.basic_ring"), "G detonate.pair is the id the tally counts")

func g_off() -> void:
	# Without the composition: the new event keys are still there, the enemy and snapshot shapes are the old ones.
	var off := make_run(null)
	var pilot = Pilot.new()
	pilot.run = off
	var kind_seen := false
	var keys_seen := 0
	# The hero stands still so that something hits it.
	for i in 1500:
		off.step()
		for ev in off.events:
			if ev.type == "hero_hit":
				kind_seen = kind_seen or (ev.has("source_kind") and ev.has("source_id") and ev.has("hp_after_raw") and int(ev.hp_after_raw) == int(off.hero.hp_raw))
			elif ev.type == "death" and not ev.has("role"): keys_seen += 1
		for e in off.enemies.values():
			if e.has("staggered_until") or e.has("cc_src") or e.has("status"): keys_seen += 1
	check(keys_seen == 0, "G off: no staggered_until, cc_src or status key on any enemy and every death has a role")
	check(kind_seen, "G off: hero_hit carries the culprit keys whether or not the composition is on")
	check(not off.metrics.has("ward") and off._hostile_src.size() <= 200, "G off: no ward tally")
	var a := make_run(enabled_doc(), 5)
	var b := make_run(enabled_doc(), 5)
	var c := make_run(null, 5)
	var pa = Pilot.new()
	var pb = Pilot.new()
	var pc = Pilot.new()
	pa.run = a
	pb.run = b
	pc.run = c
	for i in 600:
		a.step(pa.decide())
		b.step(pb.decide())
		c.step(pc.decide())
	check(JSON.stringify(a.snapshot()).sha256_text() == JSON.stringify(b.snapshot()).sha256_text(), "G an enabled run twice from the same seed: the same snapshot")
	check(JSON.stringify(a.snapshot()).sha256_text() != JSON.stringify(c.snapshot()).sha256_text(), "G an enabled run is not the disabled run")

# ------------------------------------------------------------------ F

func pair_of(run: RefCounted, primary: String) -> Array:
	for p in run.spells.pairs:
		if p.kind == "detonate" and (p.a == primary or p.b == primary): return [p.a, p.b]
	return []

func spell_sum(run: RefCounted, id_: String) -> int:
	var axes: Dictionary = run.growth.snapshot().axes.get(id_, {})
	return int(axes.get("damage", 0)) + int(axes.get("reach", 0))

func card_score(run: RefCounted, policy: String, card: Dictionary, primary: String, pair: Array) -> int:
	var id_ := String(card.get("skill_id", ""))
	if policy == "narrow":
		if id_ != primary: return 1
		match String(card.kind):
			"evolve": return 200
			"passive": return 150
			"axis": return 100 + (5 if spell_sum(run, id_) % 2 == 0 and card.axis == "damage" or spell_sum(run, id_) % 2 == 1 and card.axis == "reach" else 0)
		return 1
	# synergy: build the same-element pair around the basic spell (ring + basic), evolve, then keep the two balanced.
	if not id_ in pair: return 5
	var other: String = pair[1] if id_ == pair[0] else pair[0]
	match String(card.kind):
		"evolve": return 200
		"passive": return 150
		"unlock": return 140
		"axis": return 110 + (10 if spell_sum(run, id_) <= spell_sum(run, other) else 0) + (1 if card.axis == "damage" else 0)
	return 5

func pick(run: RefCounted, policy: String) -> Dictionary:
	var offer: Dictionary = run.get_offer()
	if offer.is_empty() or offer.cards.is_empty(): return {}
	var primary: String = run.growth.snapshot().primary
	var pair := pair_of(run, primary)
	var best := -1
	var chosen: Dictionary = offer.cards[0]
	for card in offer.cards:
		var score := card_score(run, policy, card, primary, pair)
		if score > best:
			best = score
			chosen = card
	return {"token": offer.token, "card": chosen, "level": int(offer.level)}

func play(doc: Dictionary, seed_: int, primary: String, policy: String, max_ticks: int, tuning: Dictionary = {}, label: String = "") -> Dictionary:
	var run := make_run(doc, seed_, primary, tuning)
	if run == null: return {}
	var pilot = Pilot.new()
	pilot.run = run
	var picks: Array[String] = []
	var guard := 0
	while run.mode not in ["victory", "defeat"] and run.tick < max_ticks and guard < max_ticks + 500:
		guard += 1
		while run.mode == "choice":
			var chosen := pick(run, policy)
			if chosen.is_empty() or not run.choose(String(chosen.token), String(chosen.card.id)):
				check(false, "F %s %s %s: a growth choice was refused: %s" % [label, primary, policy, str(run.errors)])
				return {}
			picks.append("L%d %s" % [int(chosen.level), String(chosen.card.id).replace("chapter1.skill.", "")])
		if run.mode in ["victory", "defeat"]: break
		run.step(pilot.decide())
	var snap: Dictionary = run.snapshot()
	var detonate: Dictionary = run.metrics.get("detonate", {"count": 0, "extra_raw": 0})
	var total := maxi(1, int(run.metrics.damage_raw))
	var result := {"label": label, "primary": primary.replace("chapter1.skill.", ""), "policy": policy, "seed": seed_, "mode": run.mode, "ticks": run.tick, "seconds": snappedf(float(run.tick) / 60.0, .1),
		"level": int(snap.growth.level), "kills": run.kills, "zone": run.zone, "zone_kills": run.zone_kills, "picks": picks, "evolved": snap.growth.evolved, "evolve_partner": snap.growth.get("evolve_partner", {}),
		"axes": snap.growth.get("axes", {}), "casts": run.metrics.casts, "detonations": int(detonate.count), "detonate_extra_raw": int(detonate.extra_raw),
		"detonate_share_pct": snappedf(float(detonate.extra_raw) * 100.0 / float(total), .1), "damage_raw": int(run.metrics.damage_raw),
		"events_dropped": int(run.metrics.get("events_dropped", 0)), "hash": JSON.stringify(snap).sha256_text().substr(0, 16)}
	plays.append(result)
	print("RUN_SPELLS_PLAY ", JSON.stringify(result))
	return result

## The shipped numbers with every spell's base damage multiplied and every cooldown cut to a third, so a whole chapter can be
## finished (the base kit is meant to be weak; the structure, not the balance, is under test there). The cooldown cut is
## new with G5-3.1: the rings are now a 2.2 m close-in ring and the arc witch kills one body at a time, so damage alone no
## longer got her past the second zone inside 36000 ticks (measured: zone 1 at 36000 with damage x20; victory at 21000 ticks
## with the cooldowns cut as well). Nothing in the document's structure is changed.
func boosted_doc(factor: int) -> Dictionary:
	var doc := enabled_doc()
	for id_ in doc.spells:
		var spell: Dictionary = doc.spells[id_]
		spell.base.damage_raw = int(spell.base.damage_raw) * factor
		spell.base.cooldown_ticks = maxi(12, int(spell.base.cooldown_ticks) / 3)
		for entry in spell.reach:
			if entry.has("cooldown_ticks"): entry.cooldown_ticks = maxi(12, int(entry.cooldown_ticks) / 3)
	return doc

func arg_value(name: String, fallback: int) -> int:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with(name + "="): return int(String(arg).trim_prefix(name + "="))
	return fallback

func part_f() -> void:
	var doc := enabled_doc()
	var cap := arg_value("--cap", 18000)
	# Determinism: the same seed and the same policy twice.
	var a := play(doc, 31, EMBER, "synergy", 2400, {}, "determinism-1")
	var b := play(doc, 31, EMBER, "synergy", 2400, {}, "determinism-2")
	check(not a.is_empty() and a.hash == b.hash and a.picks == b.picks, "F the same seed and the same picks give the same snapshot (%s)" % a.get("hash", ""))
	# Three witches, two policies, the shipped numbers, cut at `cap` ticks (the weak base kit may not reach the boss in time).
	for primary in [EMBER, FROST, ARC]:
		for policy in ["synergy", "narrow"]:
			var r := play(doc, 11, primary, policy, cap, {}, "shipped")
			check(not r.is_empty() and int(r.events_dropped) == 0, "F %s %s (shipped numbers): ran %d ticks, no refused pick, events_dropped 0 (%d)" % [primary, policy, int(r.get("ticks", 0)), int(r.get("events_dropped", -1))])
			if r.is_empty(): continue
			if policy == "synergy":
				check(r.picks.any(func(p): return String(p).contains("unlock:" + primary.replace("chapter1.skill.", "") + "_ring")), "F %s synergy picked her ring" % primary)
	# A whole chapter to its end for each witch (boosted base damage): zones, guardians, boss, victory or defeat.
	var strong := boosted_doc(arg_value("--boost", 20))
	for primary in [EMBER, FROST, ARC]:
		var r := play(strong, 11, primary, "synergy", 36000, {}, "boosted")
		# An arc witch kills one body at a time and can need longer than the cap to bring the last guardian down: ending or
		# having reached the last zone (zone 2) both show that zones, guardians and gates run with the composition on.
		check(not r.is_empty() and (r.mode in ["victory", "defeat"] or int(r.zone) == 2) and int(r.events_dropped) == 0, "F %s boosted: the run ends or reaches the last zone, no event dropped (%s, zone %d, %d ticks)" % [primary, r.get("mode", "?"), int(r.get("zone", -1)), int(r.get("ticks", 0))])
	# The rhythm switched on as well as the composition.
	var tuning: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TUNING))
	tuning.rhythm.enabled = true
	tuning.rhythm.trial.enabled = true
	var rhythm := play(strong, 11, EMBER, "synergy", 36000, tuning, "boosted-rhythm-on")
	check(not rhythm.is_empty() and (rhythm.mode in ["victory", "defeat"] or int(rhythm.zone) == 2) and int(rhythm.events_dropped) == 0, "F rhythm on x composition on: the run ends or reaches the last zone, no event dropped (%s, zone %d, %d ticks)" % [rhythm.get("mode", "?"), int(rhythm.get("zone", -1)), int(rhythm.get("ticks", 0))])
	# Off again afterwards: nothing leaked into the next run.
	var off := make_run(null)
	check(off.spells.is_empty() and off._skill_ids == Chapter.SKILL_IDS, "F a later run without a parked document is off again")

func execute() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/_local/appdata/"):
		print("CHAPTER1_RUN_SPELLS_RESULT ", JSON.stringify({"checks": 0, "failures": ["user data dir is not isolated: refusing to run"]}))
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var skip_runs := args.has("--fast") or OS.get_environment("RUN_SPELLS_SKIP_RUNS") == "1"
	if not args.has("--runs-only"):
		part_a()
		part_b()
		part_c()
		part_d()
		part_e()
		part_g()
	if not skip_runs: part_f()
	print("CHAPTER1_RUN_SPELLS_RESULT ", JSON.stringify({"checks": checks, "failures": failures, "full_runs": not skip_runs}))
	quit(0 if failures.is_empty() else 1)
