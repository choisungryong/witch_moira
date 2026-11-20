extends RefCounted
## Pure run growth. No world simulation, rendering, native profile reads or writes.
## RNG docs: https://docs.godotengine.org/en/4.5/classes/class_randomnumbergenerator.html
const Catalog = preload("res://chapter1/core/growth_catalog.gd")
const Spells = preload("res://chapter1/core/run_spells.gd")
const MAX_XP := 1000000000
## The grade stream is split off the run seed by this constant (D13 4.11.1), so grades never move the card draw.
const GRADE_SALT := 0x47524144
const MAX_EVENTS := 64
var errors: Array[String] = []
var _doc: Dictionary = {}
var _skills: Dictionary = {}
var _passives: Dictionary = {}
var _ranks: Dictionary = {}
var _owned_passives: Array[String] = []
var _evolved: Array[String] = []
var _xp := 0
var _level := 1
var _primary := ""
var _pending: Array[int] = []
var _offer: Dictionary = {}
var _epoch := 0
var _offer_sequence := 0
var _rng := RandomNumberGenerator.new()
## Permanent-build options (set_options): start rank, evolution without a crystal, re-draws. Empty = none.
var _options: Dictionary = {}
var _evolve_free := false
var _rerolls_left := 0
## In-run spell composition (chapter1/data/run_spells.json, D12 G5). Empty = off: every rule below stays out of the way
## and the run is exactly the one without the file. _axes: {spell id: {damage, reach}}; _evolve_partner: {spell id: pair id}.
var _spells: Dictionary = {}
var _starts: Dictionary = {}
var _owner_skill: Dictionary = {}
var _axes: Dictionary = {}
var _evolve_partner: Dictionary = {}
## Boon cadence, tools and grades (D13 K3a/K3b-1). _grace is the validated combat_tuning "grace" block; {} = off, and then
## nothing below draws a number, adds a snapshot key or changes a card. _grade_rng is a stream of its own.
var _grace: Dictionary = {}
var _run_seed := 0
var _grade_rng := RandomNumberGenerator.new()
var _banished: Array[String] = []
var _banishes_left := 0
var _holds_left := 0
## The card set aside for the next offer: {id, card, info} or {}.
var _held: Dictionary = {}
var _spins := 0
var _pity := 0
## Grades of the standing offer (not part of the offer itself, which stays as it was): {grades:{card id: info}, spin, forced, odds, final, has_jackpot, held_dropped}.
var _offer_meta: Dictionary = {}
var _luck := {"shrine_mul_bps":10000,"reward_grade":0,"gear_bps":0}
var _events: Array[Dictionary] = []
var _redraw := false
var _relax_lock := false

func configure(candidate: Variant, primary_skill: String, run_seed: int) -> bool:
	var issues := Catalog.validate(candidate)
	if not issues.is_empty():
		errors = issues
		return false
	var new_skills: Dictionary = {}
	var new_passives: Dictionary = {}
	for s in candidate.skills: new_skills[s.id] = s.duplicate(true)
	for p in candidate.passives: new_passives[p.id] = p.duplicate(true)
	if not new_skills.has(primary_skill):
		errors.assign(["Unknown primary skill"])
		return false
	_doc = candidate.duplicate(true)
	_skills = new_skills
	_passives = new_passives
	_primary = primary_skill
	_ranks = {primary_skill:1}
	_owned_passives.clear()
	_evolved.clear()
	_pending.clear()
	_offer.clear()
	_xp = 0
	_level = 1
	_epoch += 1
	_offer_sequence = 0
	_options = {}
	_evolve_free = false
	_rerolls_left = 0
	_spells = {}
	_starts = {}
	_owner_skill = {}
	_axes = {}
	_evolve_partner = {}
	_rng.seed = run_seed
	_run_seed = run_seed
	_grace = {}
	_banished.clear()
	_banishes_left = 0
	_holds_left = 0
	_held = {}
	_spins = 0
	_pity = 0
	_offer_meta = {}
	_luck = {"shrine_mul_bps":10000,"reward_grade":0,"gear_bps":0}
	_events.clear()
	_redraw = false
	_relax_lock = false
	errors.clear()
	return true

## Permanent-build options (G1 R5/R6), applied right after configure() and before any experience:
## {start_rank 1..2, evolve_without_passive, grace_rerolls 0..3}. A rejected set changes nothing.
## Empty or default values leave the run (and its snapshot) exactly as without options.
func set_options(options: Dictionary) -> bool:
	if _doc.is_empty() or _xp != 0 or not _pending.is_empty() or not _offer.is_empty():
		errors.assign(["Growth options need a freshly configured run"])
		return false
	var start_rank: Variant = options.get("start_rank",1)
	var rerolls: Variant = options.get("grace_rerolls",0)
	var free: Variant = options.get("evolve_without_passive",false)
	for key in options:
		if not key in ["start_rank","grace_rerolls","evolve_without_passive"]:
			errors.assign(["Unknown growth option "+str(key)])
			return false
	if not Catalog.integer(start_rank,1,2) or not Catalog.integer(rerolls,0,3) or not free is bool:
		errors.assign(["Growth option out of range"])
		return false
	# With the spell composition on, the rank of a spell is not used (axis cards replace rank cards).
	_ranks[_primary] = int(start_rank) if _spells.is_empty() else 1
	_rerolls_left = int(rerolls)
	_evolve_free = free
	_options = {}
	if int(start_rank) > 1 or int(rerolls) > 0 or free:
		_options = {"start_rank":int(start_rank),"grace_rerolls":int(rerolls),"evolve_without_passive":free}
	errors.clear()
	return true

func rerolls_left() -> int:
	return _rerolls_left

## Throw the standing offer away and draw a new one by the same rules (protected card included) from the same
## random stream. Needs a live offer with this token and a re-draw left.
func reroll(token: String) -> bool:
	if _rerolls_left <= 0 or _offer.is_empty() or token != _offer.token or _pending.is_empty():
		errors.assign(["No re-draw left or expired growth offer"])
		return false
	var previous := _offer
	var previous_meta := _offer_meta
	var sequence := _offer_sequence
	_rerolls_left -= 1
	_offer = {}
	_offer_meta = {}
	# A re-draw is a new offer (and a new pull of the grades), but it must not use up the card set aside for the next level.
	_redraw = true
	var drawn := next_offer()
	_redraw = false
	if drawn.is_empty():
		_rerolls_left += 1
		_offer = previous
		_offer_meta = previous_meta
		_offer_sequence = sequence
		return false
	errors.clear()
	return true

func award_xp(amount: Variant) -> bool:
	if _doc.is_empty() or not Catalog.integer(amount,0,MAX_XP):
		errors.assign(["XP must be a bounded nonnegative integer on a configured run"])
		return false
	_xp = mini(MAX_XP,_xp+int(amount))
	var next_level := 1
	for threshold in _doc.xp_thresholds:
		if _xp >= int(threshold): next_level += 1
	next_level -= 1
	for earned in range(_level+1,next_level+1): _pending.append(earned)
	_level = next_level
	errors.clear()
	return true

func effective_skill(id_: String) -> Dictionary:
	if not _ranks.has(id_): return {}
	if not _spells.is_empty() and _spells.spells.has(id_): return _spell_skill(id_,_axes[id_])
	var rank: int = _ranks[id_]
	var definition: Dictionary = _skills[id_]
	var effect: Dictionary = definition.evolution if id_ in _evolved else definition.ranks[rank-1]
	return {"id":id_,"rank":rank,"evolved":id_ in _evolved,
		"name_key":"skill.%s.%s"%[id_,"evolved_name" if id_ in _evolved else "name"],
		"effects":effect.duplicate(true)}

func xp_thresholds() -> Array:
	return _doc.get("xp_thresholds",[0]).duplicate()

## The level the run is at now (the same number snapshot().level carries, without copying the rest).
func current_level() -> int:
	return _level

## C1-a (D19): a run whose rhythm is on has its own level table, 12 to 20 entries, starting at 0 and strictly rising. Only on a fresh
## run, right after configure(); a rejected table changes nothing. The table is the level cap: is_final_level() reads its length.
func set_thresholds(table: Array) -> bool:
	if _doc.is_empty() or _xp != 0 or not _pending.is_empty() or not _offer.is_empty():
		errors.assign(["Level table needs a freshly configured run"])
		return false
	if table.size() < 12 or table.size() > 20 or not Catalog.integer(table[0],0,0):
		errors.assign(["Level table must have 12 to 20 entries and start at 0"])
		return false
	var previous := -1
	for amount in table:
		if not Catalog.integer(amount,0,1000000) or int(amount) <= previous:
			errors.assign(["Level table must rise strictly"])
			return false
		previous = int(amount)
	_doc.xp_thresholds = table.duplicate()
	errors.clear()
	return true

func _eligible_cards() -> Array[Dictionary]:
	if not _spells.is_empty(): return _spell_cards()
	var result: Array[Dictionary] = []
	# Catalog order is authoritative; no hash-table iteration is used for the draw.
	for s in _doc.skills:
		var rank := int(_ranks.get(s.id,0))
		if rank == 0 and _ranks.size() < int(_doc.max_active_skills):
			result.append({"id":"unlock:"+s.id,"kind":"unlock","skill_id":s.id,"rank":1,"weight":int(s.weight),"title_key":"skill.%s.name"%s.id,"after":s.ranks[0].duplicate(true)})
		elif rank > 0 and rank < 4:
			result.append({"id":"rank:%s:%d" % [s.id,rank+1],"kind":"rank","skill_id":s.id,"rank":rank+1,"weight":int(s.weight),"title_key":"skill.%s.name"%s.id,"after":s.ranks[rank].duplicate(true)})
		# With evolve_without_passive the primary's crystal card does nothing but unlock evolution, so it is not offered.
		if rank >= 2 and not s.passive_id in _owned_passives and _owned_passives.size() < int(_doc.max_passives) and not (_evolve_free and s.id == _primary):
			var p: Dictionary = _passives[s.passive_id]
			result.append({"id":"passive:"+p.id,"kind":"passive","skill_id":s.id,"passive_id":p.id,"weight":int(p.weight),"title_key":"grace.passive.%s.name"%p.id})
		if rank == 4 and (s.passive_id in _owned_passives or (_evolve_free and s.id == _primary)) and not s.id in _evolved and not _evolve_locked():
			result.append({"id":"evolve:"+s.id,"kind":"evolve","skill_id":s.id,"rank":4,"weight":int(s.weight),"title_key":"skill.%s.evolved_name"%s.id,"after":s.evolution.duplicate(true)})
	return result

func _protected_card(cards: Array[Dictionary]) -> int:
	if not _spells.is_empty(): return _protected_spell_card(cards)
	# Keep a reachable primary evolution path; the player still chooses it or another card.
	for preferred in ["evolve","rank","passive"]:
		for i in cards.size():
			if cards[i].skill_id == _primary and cards[i].kind == preferred: return i
	return -1

func next_offer() -> Dictionary:
	if not _offer.is_empty(): return _offer.duplicate(true)
	if _doc.is_empty() or _pending.is_empty(): return {}
	# The card set aside (D13 K3a hold) comes back at the next offer; a re-draw leaves it set aside.
	var held := {}
	if grace_on() and not _redraw and not _held.is_empty():
		held = _held
		_held = {}
	var pool := _pool()
	var selected: Array[Dictionary] = []
	var carried := {}
	if not held.is_empty():
		for i in pool.size():
			if String(pool[i].id) == String(held.id):
				selected.append(pool[i])
				pool.remove_at(i)
				carried[String(held.id)] = held.info
				break
	if pool.is_empty() and selected.is_empty():
		_held = held
		errors.assign(["No legal growth candidates"])
		return {}
	var final := _is_final_offer()
	var target := int(_grace.final_offer.cards) if final else 3
	var protected := _final_protected_card(pool) if final else -1
	if protected < 0: protected = _protected_card(pool)
	if protected >= 0:
		selected.append(pool[protected])
		pool.remove_at(protected)
	while selected.size() < target and not pool.is_empty():
		selected.append(_draw_weighted(pool))
	_offer_sequence += 1
	_offer = {"token":"%d:%d" % [_epoch,_offer_sequence],"level":_pending[0],"cards":selected}
	_offer_meta = {}
	if grace_on():
		_offer_meta = _roll_offer(selected,carried,final)
		_offer_meta.held_dropped = not held.is_empty() and carried.is_empty()
		if final: _push_event("grace_final_offer",{"level":int(_pending[0]),"cards":selected.size()})
	return _offer.duplicate(true)

## One weighted draw from `pool` (removed from it), on the card stream.
func _draw_weighted(pool: Array[Dictionary]) -> Dictionary:
	var total := 0
	for card in pool: total += int(card.weight)
	var roll := _rng.randi_range(1,total)
	var index := 0
	while roll > int(pool[index].weight):
		roll -= int(pool[index].weight)
		index += 1
	var picked: Dictionary = pool[index]
	pool.remove_at(index)
	return picked

func choose(token: String, card_id: String) -> bool:
	if _offer.is_empty() or token != _offer.token or _pending.is_empty():
		errors.assign(["Expired or missing growth offer"])
		return false
	var chosen: Dictionary = {}
	for card in _offer.cards:
		if card.id == card_id: chosen = card
	if chosen.is_empty():
		errors.assign(["Card was not offered"])
		return false
	if grace_on() and not _held.is_empty() and String(_held.id) == card_id:
		errors.assign(["A held card waits for the next offer"])
		return false
	# The grade's effect is judged on the build at this moment (D13 4.11.2), before the card's own change.
	var info: Dictionary = _offer_meta.get("grades",{}).get(card_id,{})
	var plan := {}
	if grades_on() and String(info.get("grade","common")) != "common": plan = _grade_plan(chosen,String(info.grade))
	match chosen.kind:
		"unlock","rank","axis": _apply_card_effect(chosen)
		"passive": _owned_passives.append(chosen.passive_id)
		"evolve":
			_evolved.append(chosen.skill_id)
			if not _spells.is_empty(): _evolve_partner[chosen.skill_id] = String(chosen.partner_pair)
	if not plan.is_empty():
		_apply_plan_extras(chosen,plan)
		if String(info.grade) == "jackpot":
			_push_event("grace_jackpot_taken",{"card_id":card_id,"resonance":bool(plan.resonance),"partner_skill":String(plan.partner_skill),"evolve_ready":_can_evolve(String(chosen.get("skill_id",""))) if not _spells.is_empty() else false})
	_pending.pop_front()
	_offer = {}
	_offer_meta = {}
	errors.clear()
	return true

## The change of an unlock, rank or axis card itself (no grade).
func _apply_card_effect(chosen: Dictionary) -> void:
	match chosen.kind:
		"unlock","rank":
			_ranks[chosen.skill_id] = int(chosen.rank)
			if not _spells.is_empty(): _axes[chosen.skill_id] = {"damage":0,"reach":0}
		"axis": _axes[chosen.skill_id][chosen.axis] = int(_axes[chosen.skill_id][chosen.axis])+1

func snapshot() -> Dictionary:
	var result := {"xp":_xp,"level":_level,"primary":_primary,"ranks":_ranks.duplicate(true),
		"passives":_owned_passives.duplicate(),"evolved":_evolved.duplicate(),
		"pending_levels":_pending.duplicate(),"offer":_offer.duplicate(true),
		"epoch":_epoch,"rng_state":str(_rng.state)}
	# Only a run with the spell composition carries these two keys.
	if not _spells.is_empty():
		result.axes = _axes.duplicate(true)
		result.evolve_partner = _evolve_partner.duplicate(true)
	# Only a run with permanent-build options carries this key.
	if not _options.is_empty(): result.options = {"start_rank":int(_options.start_rank),"grace_rerolls":int(_options.grace_rerolls),"rerolls_left":_rerolls_left,"evolve_without_passive":_evolve_free}
	# Only a run with the grace block on carries these (D13 K3a/K3b-1); the standing offer's cards stay as they were.
	if grace_on():
		result.banished = _banished.duplicate()
		result.held = _held.duplicate(true)
		result.grace = {"rerolls_left":_rerolls_left,"banishes_left":_banishes_left,"holds_left":_holds_left,"spins":_spins,"pity":_pity,
			"grade_rng_state":str(_grade_rng.state),"luck":_luck.duplicate(),"offer_meta":_offer_meta.duplicate(true)}
	return result

# ---------------------------------------------------------------- spell composition (D12 B0, G5)

## Take the validated run_spells document for this run (right after configure(), before any experience).
## `owner_skill` maps a character id to the signature skill of that witch (decides whose ring is offered).
## An empty document leaves the run as it was. A rejected set changes nothing.
func set_spells(doc: Dictionary, owner_skill: Dictionary) -> bool:
	if _doc.is_empty() or _xp != 0 or not _pending.is_empty() or not _offer.is_empty():
		errors.assign(["Run spells need a freshly configured run"])
		return false
	if doc.is_empty(): return true
	var starts := {}
	for id_ in _skills:
		if not doc.get("spells",{}).has(id_):
			errors.assign(["Run spells miss catalog skill "+str(id_)])
			return false
		starts[id_] = _skills[id_].ranks[0].duplicate(true)
	_spells = doc.duplicate(true)
	_starts = starts
	_owner_skill = owner_skill.duplicate()
	_ranks = {_primary:1}
	_axes = {_primary:{"damage":0,"reach":0}}
	_evolve_partner = {}
	errors.clear()
	return true

func spells_active() -> bool:
	return not _spells.is_empty()

func _spell_skill(id_: String, axes: Dictionary) -> Dictionary:
	var evolved := id_ in _evolved
	return {"id":id_,"rank":1+int(axes.damage)+int(axes.reach),"evolved":evolved,
		"name_key":"skill.%s.%s"%[id_,"evolved_name" if evolved else "name"],
		"effects":Spells.compose(_spells,id_,int(axes.damage),int(axes.reach),_starts.get(id_,{}))}

func _axis_sum(id_: String) -> int:
	var axes: Dictionary = _axes.get(id_,{})
	return int(axes.get("damage",0))+int(axes.get("reach",0))

## Catalog skills in catalog order, then the other spells in document order. The draw never iterates a hash table.
func _spell_order() -> Array[String]:
	var order: Array[String] = []
	for s in _doc.skills: order.append(String(s.id))
	for id_ in _spells.spells:
		if not id_ in order: order.append(String(id_))
	return order

func owned_spells() -> Array[String]:
	var owned: Array[String] = []
	for id_ in _spell_order():
		if _ranks.has(id_): owned.append(id_)
	return owned

## Pair ids that link `id_` with any of `others` (each id once, in the order of the others).
func _pairs_with(id_: String, others: Array) -> Array[String]:
	var found: Array[String] = []
	for other in others:
		var pair := Spells.pair_between(_spells,id_,String(other))
		if not pair.is_empty() and not pair in found: found.append(pair)
	return found

## The owned spell linked to `id_` with the highest axis sum (ties: spell order). {} when none.
func _best_partner(id_: String) -> Dictionary:
	var best := {}
	for other in owned_spells():
		if other == id_: continue
		var pair := Spells.pair_between(_spells,id_,other)
		if pair.is_empty(): continue
		var sum := _axis_sum(other)
		if best.is_empty() or sum > int(best.sum): best = {"skill":other,"pair":pair,"sum":sum}
	return best

func _passive_ready(id_: String) -> bool:
	if not _spells.evolve.needs_passive: return true
	return _skills[id_].passive_id in _owned_passives or (_evolve_free and id_ == _primary)

func _can_evolve(id_: String) -> bool:
	if not _skills.has(id_) or id_ in _evolved or not _ranks.has(id_): return false
	if _axis_sum(id_) < int(_spells.evolve.axis_sum) or not _passive_ready(id_): return false
	var partner := _best_partner(id_)
	return not partner.is_empty() and int(partner.sum) >= int(_spells.evolve.partner_axis_sum)

func _spell_cards() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var caps: Dictionary = _spells.axis
	for id_ in _spell_order():
		var spell: Dictionary = _spells.spells[id_]
		var weight := int(spell.weight)
		var title := "skill.%s.name" % id_
		if not _ranks.has(id_):
			if _ranks.size() >= int(_spells.slots): continue
			# A ring belongs to one witch.
			if spell.role == "ring" and String(_owner_skill.get(String(spell.owner),"")) != _primary: continue
			result.append({"id":"unlock:"+id_,"kind":"unlock","skill_id":id_,"rank":1,"weight":weight,"title_key":title,
				"after":Spells.compose(_spells,id_,0,0,_starts.get(id_,{}))})
			continue
		var axes: Dictionary = _axes[id_]
		var sum := _axis_sum(id_)
		if sum < int(caps.cap_per_spell):
			for axis in ["damage","reach"]:
				if int(axes[axis]) >= int(caps.cap_per_axis): continue
				var next: Dictionary = axes.duplicate()
				next[axis] = int(next[axis])+1
				result.append({"id":"axis:%s:%s" % [id_,axis],"kind":"axis","skill_id":id_,"axis":axis,"level":int(next[axis]),"rank":1+sum+1,"weight":weight,"title_key":title,
					"after":Spells.compose(_spells,id_,int(next.damage),int(next.reach),_starts.get(id_,{}))})
		if not _skills.has(id_): continue
		var s: Dictionary = _skills[id_]
		# The crystal card needs one axis point on the spell (the old rank 2).
		if sum >= 1 and not s.passive_id in _owned_passives and _owned_passives.size() < int(_doc.max_passives) and not (_evolve_free and id_ == _primary):
			var p: Dictionary = _passives[s.passive_id]
			result.append({"id":"passive:"+p.id,"kind":"passive","skill_id":id_,"passive_id":p.id,"weight":int(p.weight),"title_key":"grace.passive.%s.name"%p.id})
		if _can_evolve(id_) and not _evolve_locked():
			var partner := _best_partner(id_)
			result.append({"id":"evolve:"+id_,"kind":"evolve","skill_id":id_,"rank":1+sum,"weight":weight,"title_key":"skill.%s.evolved_name"%id_,
				"partner_pair":String(partner.pair),"partner_skill":String(partner.skill),"after":Spells.compose(_spells,id_,int(axes.damage),int(axes.reach),_starts.get(id_,{}))})
	return result

## Protected card of the composition (D12 B0.4): level ring_at_level offers the witch's own ring; the pair-opening
## levels offer a spell that pairs with one owned (or, slots full, the weaker owner of an owned pair gets an axis card);
## every other offer shows the card that brings the nearest evolution closer. Shown, never forced.
func _protected_spell_card(cards: Array[Dictionary]) -> int:
	var rule: Dictionary = _spells.protect
	var level := int(_pending[0])
	if level == int(rule.ring_at_level):
		for i in cards.size():
			if cards[i].kind == "unlock" and String(_spells.spells[cards[i].skill_id].role) == "ring": return i
	if level in rule.pair_open_levels:
		var opened := _pair_open_card(cards)
		if opened >= 0: return opened
	if bool(rule.toward_evolve): return _toward_evolve_card(cards)
	return -1

## Index of the axis card of a spell whose level is lower (damage on a tie); -1 when the spell has none in the pool.
func _axis_card_index(cards: Array[Dictionary], id_: String) -> int:
	var best := -1
	for i in cards.size():
		if cards[i].kind != "axis" or cards[i].skill_id != id_: continue
		if best < 0 or int(_axes[id_][cards[i].axis]) < int(_axes[id_][cards[best].axis]): best = i
	return best

func _pair_open_card(cards: Array[Dictionary]) -> int:
	var owned := owned_spells()
	var best := -1
	var best_count := 0
	for i in cards.size():
		if cards[i].kind != "unlock": continue
		var count := _pairs_with(String(cards[i].skill_id),owned).size()
		if count > best_count:
			best = i
			best_count = count
	if best >= 0: return best
	var weakest := ""
	var weakest_sum := 1000
	for id_ in owned:
		if _pairs_with(id_,owned).is_empty() or _axis_card_index(cards,id_) < 0: continue
		if _axis_sum(id_) < weakest_sum:
			weakest = id_
			weakest_sum = _axis_sum(id_)
	return _axis_card_index(cards,weakest) if not weakest.is_empty() else -1

func _toward_evolve_card(cards: Array[Dictionary]) -> int:
	var rule: Dictionary = _spells.evolve
	var ranked: Array[Dictionary] = []
	for id_ in owned_spells():
		if not _skills.has(id_) or id_ in _evolved: continue
		var gap_axis := maxi(0,int(rule.axis_sum)-_axis_sum(id_))
		var gap_passive := 0 if _passive_ready(id_) else 1
		var partner := _best_partner(id_)
		var gap_partner := int(rule.partner_axis_sum)+1 if partner.is_empty() else maxi(0,int(rule.partner_axis_sum)-int(partner.sum))
		ranked.append({"id":id_,"dist":gap_axis+gap_passive+gap_partner,"gap_axis":gap_axis,"gap_passive":gap_passive,"partner":partner,"order":ranked.size()})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.order) < int(b.order) if int(a.dist) == int(b.dist) else int(a.dist) < int(b.dist))
	for entry in ranked:
		var id_: String = entry.id
		# Ready to evolve but the level is too early (grace.evolve_min_level): the card is not in the pool, so protect the next thing.
		if _evolve_locked() and int(entry.dist) == 0: continue
		for i in cards.size():
			if cards[i].kind == "evolve" and cards[i].skill_id == id_: return i
		if int(entry.gap_axis) > 0:
			var axis_index := _axis_card_index(cards,id_)
			if axis_index >= 0: return axis_index
		if int(entry.gap_passive) > 0:
			for i in cards.size():
				if cards[i].kind == "passive" and cards[i].skill_id == id_: return i
		if entry.partner.is_empty():
			for i in cards.size():
				if cards[i].kind == "unlock" and not Spells.pair_between(_spells,id_,String(cards[i].skill_id)).is_empty(): return i
		else:
			var partner_index := _axis_card_index(cards,String(entry.partner.skill))
			if partner_index >= 0: return partner_index
	return -1

# ---- read only (screen and measurement)

func axis_levels(id_: String) -> Dictionary:
	return _axes.get(id_,{"damage":0,"reach":0}).duplicate()

## Pair ids this spell forms with the spells owned now.
func pairs_owned(id_: String) -> Array[String]:
	return _pairs_with(id_,owned_spells())

## Pair ids a card would form with the spells owned now. [] when the composition is off.
func pairs_if_taken(card: Dictionary) -> Array[String]:
	var none: Array[String] = []
	if _spells.is_empty() or not card.has("skill_id"): return none
	return _pairs_with(String(card.skill_id),owned_spells())

## The card contract for the screen (read only, nothing is stored: the standing offer and the snapshot stay as they are).
## {} when the composition is off or the card names no spell of the document. Keys:
##  pairs_if_taken [pair id]  the older flat list (one pair per owned spell), kept for the screens that read it
##  pair_links [{id,kind,other,a,b,card_is,status|via|elements+reaction}]  every link with an owned spell, BOTH directions of a
##     spell pair (detonate and interlock), document order; `a` puts the state on, `b` finishes; card_is "a" or "b"
##  role, element, passive_id ("" for a ring), passive_owned, applies [status id], prefer (status id or ""), prefer_kinds [kind],
##  prefer_i0 (true when the spell aims at a kind of enemy first), before (the effect now; {} for an unlock), after (the card's),
##  changed {effect key: {before, after}} (axis cards: only the keys that move)
func card_contract(card: Dictionary) -> Dictionary:
	var grade := grade_fields(card)
	if _spells.is_empty() or not card.has("skill_id"): return grade
	var id_ := String(card.skill_id)
	if not _spells.spells.has(id_): return grade
	var spell: Dictionary = _spells.spells[id_]
	var passive_id := String(_skills[id_].passive_id) if _skills.has(id_) else ""
	var applies: Array[String] = []
	for status in spell.applies: applies.append(String(status))
	var kinds: Array[String] = []
	for kind in spell.get("prefer_kinds",[]): kinds.append(String(kind))
	var before: Dictionary = effective_skill(id_).get("effects",{}).duplicate(true) if _ranks.has(id_) else {}
	var after: Dictionary = card.get("after",{}).duplicate(true)
	var changed := {}
	if String(card.get("kind","")) == "axis":
		for key in after:
			if before.get(key) != after[key]: changed[String(key)] = {"before":before.get(key,0),"after":after[key]}
	var contract := {"pairs_if_taken":pairs_if_taken(card),"pair_links":_pair_links(id_),"role":String(spell.role),"element":String(spell.element),
		"passive_id":passive_id,"passive_owned":passive_id in _owned_passives,"applies":applies,"prefer":String(spell.get("prefer","")),
		"prefer_kinds":kinds,"prefer_i0":not kinds.is_empty(),"before":before,"after":after,"changed":changed}
	# With the grades on the same dictionary carries grade, roll, rare and jackpot (D13 4.11.5); without, the keys are not there.
	contract.merge(grade)
	return contract

func _pair_links(id_: String) -> Array[Dictionary]:
	var links: Array[Dictionary] = []
	for other in owned_spells():
		if other == id_: continue
		var found := false
		for pair in _spells.pairs:
			if not (pair.kind in ["detonate","interlock"]): continue
			if not ((pair.a == id_ and pair.b == other) or (pair.a == other and pair.b == id_)): continue
			found = true
			var link := {"id":String(pair.id),"kind":String(pair.kind),"other":other,"a":String(pair.a),"b":String(pair.b),"card_is":"a" if pair.a == id_ else "b"}
			if pair.kind == "detonate": link.status = String(pair.status)
			else: link.via = pair.via.duplicate()
			links.append(link)
		if found: continue
		var reaction := Spells.pair_between(_spells,id_,other)
		if reaction.is_empty(): continue
		for pair in _spells.pairs:
			if pair.id == reaction:
				links.append({"id":reaction,"kind":"reaction","other":other,"a":id_,"b":other,"card_is":"a","elements":pair.elements.duplicate(),"reaction":String(pair.reaction)})
	return links

## How far a spell is from its evolution. {} for a spell that cannot evolve.
## {axis:{have,need}, passive:{have,need}, partner:{have,need,skill,pair}}
func evolve_progress(id_: String) -> Dictionary:
	if _spells.is_empty() or not _skills.has(id_) or not _ranks.has(id_): return {}
	var rule: Dictionary = _spells.evolve
	var partner := _best_partner(id_)
	return {"axis":{"have":_axis_sum(id_),"need":int(rule.axis_sum)},
		"passive":{"have":_passive_ready(id_) if bool(rule.needs_passive) else true,"need":bool(rule.needs_passive)},
		"partner":{"have":int(partner.get("sum",0)),"need":int(rule.partner_axis_sum),"skill":String(partner.get("skill","")),"pair":String(partner.get("pair",""))}}

func evolve_partner_of(id_: String) -> String:
	return String(_evolve_partner.get(id_,""))

# ---------------------------------------------------------------- boon cadence, tools and grades (D13 K3a, K3b-1)
# Everything here is inert while _grace is {}: no draw, no snapshot key, no change to a card or to the card stream (_rng).

func grace_on() -> bool:
	return not _grace.is_empty()

func grades_on() -> bool:
	return not _grace.is_empty() and bool(_grace.grades.enabled)

## Take the validated combat_tuning "grace" block right after configure() / set_spells() / set_options(), before any experience.
## An empty or disabled block leaves the run as it was. The re-draws it grants are added to the tree's (sum 0..6).
func set_grace(rules: Dictionary) -> bool:
	if _doc.is_empty() or _xp != 0 or not _pending.is_empty() or not _offer.is_empty():
		errors.assign(["Grace rules need a freshly configured run"])
		return false
	if rules.is_empty() or not bool(rules.get("enabled",false)): return true
	_grace = rules.duplicate(true)
	_grade_rng.seed = _run_seed ^ GRADE_SALT
	_rerolls_left = mini(6,_rerolls_left+int(_grace.tools.base_rerolls))
	_banishes_left = int(_grace.tools.base_banishes)
	_holds_left = int(_grace.tools.base_holds)
	errors.clear()
	return true

## The parts that raise the chance of a grade (D13 4.11.3): the shrine's multiplier, the reward stage reached, the gear's share.
## The core only keeps them and uses them; where the numbers come from (W5, K6) is not decided here.
func set_grade_luck(shrine_mul_bps: int, reward_grade: int, gear_bps: int) -> bool:
	if not grades_on() or not Catalog.integer(shrine_mul_bps,10000,100000) or not Catalog.integer(reward_grade,0,4) or not Catalog.integer(gear_bps,0,10000):
		errors.assign(["Grade luck out of range or grades off"])
		return false
	_luck = {"shrine_mul_bps":shrine_mul_bps,"reward_grade":reward_grade,"gear_bps":gear_bps}
	errors.clear()
	return true

func banishes_left() -> int:
	return _banishes_left

func holds_left() -> int:
	return _holds_left

func spins() -> int:
	return _spins

## The events the grace rules made since the last call ({type, data}); the core turns them into events. Not in the snapshot.
func take_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_events)
	_events.clear()
	return out

func _push_event(type: String, data: Dictionary) -> void:
	if not grace_on(): return
	if _events.size() >= MAX_EVENTS: _events.pop_front()
	_events.append({"type":type,"data":data})

func _offer_level() -> int:
	return int(_pending[0]) if not _pending.is_empty() else 0

## First pending level (0 when none) and whether a level is the last threshold (the boss-spawn level).
func next_pending_level() -> int:
	return _offer_level()

func is_final_level(level: int) -> bool:
	return level >= _doc.get("xp_thresholds",[0]).size()

func _evolve_locked() -> bool:
	return grace_on() and not _relax_lock and _offer_level() < int(_grace.evolve_min_level)

func _is_final_offer() -> bool:
	return grace_on() and String(_grace.final_offer.mode) == "big" and not _pending.is_empty() and is_final_level(int(_pending[0]))

func _filtered_pool() -> Array[Dictionary]:
	var pool := _eligible_cards()
	if not grace_on(): return pool
	var kept: Array[Dictionary] = []
	var held_id := String(_held.get("id",""))
	for card in pool:
		var id_ := String(card.id)
		if id_ in _banished or id_ == held_id: continue
		kept.append(card)
	return kept

## The candidates: the eligible cards without banished ones and without the card set aside. When the too-early evolution lock
## would leave nothing, the lock is lifted for this one draw (a stuck level is worse than an early evolution).
func _pool() -> Array[Dictionary]:
	var pool := _filtered_pool()
	if pool.is_empty() and _evolve_locked():
		_relax_lock = true
		pool = _filtered_pool()
		_relax_lock = false
	return pool

## Protected card of the last offer: the first card of the first word of protect_order that the pool has (D13 4.4 (2)).
## "evolve_keystone" has no candidate before the tree work (K5) and is skipped. -1 when nothing fits.
func _final_protected_card(pool: Array[Dictionary]) -> int:
	for word in _grace.final_offer.protect_order:
		var kinds: Array = []
		if word == "evolve": kinds = ["evolve"]
		elif word == "passive": kinds = ["passive"]
		elif word == "axis": kinds = ["axis","rank"]
		elif word == "survival": kinds = ["survival"]
		if kinds.is_empty(): continue
		for i in pool.size():
			if String(pool[i].kind) in kinds: return i
	return -1

func _offer_index(card_id: String) -> int:
	var cards: Array = _offer.get("cards",[])
	for i in cards.size():
		if String(cards[i].id) == card_id: return i
	return -1

## Cards that could fill a freed slot now: the pool without the cards already in the offer.
func _refill_candidates() -> Array[Dictionary]:
	var shown := {}
	for card in _offer.get("cards",[]): shown[String(card.id)] = true
	var found: Array[Dictionary] = []
	for card in _pool():
		if not shown.has(String(card.id)): found.append(card)
	return found

## D13 4.4 (4). Needs a standing offer, a banish left, a card whose kind may be banished (never a crystal or an evolution),
## not the card that is set aside. The id never comes back this run; the slot is refilled from the card stream (or shrinks).
func banish(token: String, card_id: String) -> bool:
	if not grace_on() or _banishes_left <= 0 or _offer.is_empty() or token != _offer.token or _pending.is_empty():
		errors.assign(["No banish left or expired growth offer"])
		return false
	var index := _offer_index(card_id)
	if index < 0 or not String(_offer.cards[index].kind) in _grace.tools.banish_kinds or (not _held.is_empty() and String(_held.id) == card_id):
		errors.assign(["This card cannot be banished"])
		return false
	_banishes_left -= 1
	_banished.append(card_id)
	var grades: Dictionary = _offer_meta.get("grades",{})
	grades.erase(card_id)
	var pool := _refill_candidates()
	var new_id := ""
	var new_grade := ""
	if pool.is_empty():
		_offer.cards.remove_at(index)
	else:
		var card := _draw_weighted(pool)
		_offer.cards[index] = card
		new_id = String(card.id)
		if grades_on():
			var odds: Dictionary = _offer_meta.odds
			grades[new_id] = _roll_slot(int(odds.jackpot_bps),int(odds.rare_bps)) if _rollable(card) else _plain_grade()
			new_grade = String(grades[new_id].grade)
			if new_grade == "jackpot": _push_event("grace_jackpot_shown",{"level":int(_offer.level),"slots":[index],"matched":[_matched_now(card)]})
	_recount_jackpot()
	_push_event("grace_banish",{"card_id":card_id,"left":_banishes_left,"slot":index,"new_card_id":new_id,"new_grade":new_grade})
	errors.clear()
	return true

## D13 4.4 (5). The card is not taken now; it stays set aside and comes back in the next offer (with its grade). The offer
## stays open: one of the other cards is chosen. One card per offer, never the only card.
func hold(token: String, card_id: String) -> bool:
	if not grace_on() or _holds_left <= 0 or _offer.is_empty() or token != _offer.token or _pending.is_empty() or not _held.is_empty():
		errors.assign(["No hold left, one is already set aside, or expired growth offer"])
		return false
	var index := _offer_index(card_id)
	if index < 0 or _offer.cards.size() < 2:
		errors.assign(["This card cannot be held"])
		return false
	_holds_left -= 1
	_held = {"id":card_id,"card":_offer.cards[index].duplicate(true),"info":_offer_meta.get("grades",{}).get(card_id,{}).duplicate(true)}
	_push_event("grace_hold",{"card_id":card_id,"left":_holds_left})
	errors.clear()
	return true

# ---- grades

func _plain_grade() -> Dictionary:
	return {"grade":"common","rollable":false,"roll":{},"near":false,"forced":false}

## Only these cards are pulled (D13 4.11.1): never a crystal, an evolution or a pact. A rank card exists only in the old
## composition and an axis or unlock card only in the new one, so no grade is rolled for a card whose grade could do nothing.
func _rollable(card: Dictionary) -> bool:
	var kind := String(card.kind)
	if not kind in _grace.grades.kinds: return false
	if kind == "rank": return _spells.is_empty()
	if kind == "unlock" or kind == "axis": return not _spells.is_empty()
	return kind == "survival" or kind == "link"

## The chances this offer uses (read from the live luck and pity): bps of 10000 per slot. The soft pity, the reward stage and the
## gear add to the base chance, the shrine multiplies the sum (the rare chance too), and the cap bounds the jackpot chance.
func _grade_odds() -> Dictionary:
	var d: Dictionary = _grace.grades
	var base := int(d.jackpot_bps)
	var parts := {"base":base,"gear":base*mini(int(d.luck.gear_cap_bps),int(_luck.gear_bps))/10000,
		"reward_grade":int(d.luck.per_reward_grade_bps)*int(_luck.reward_grade),"pity":int(d.pity.soft_step_bps)*_pity}
	var shrine := int(_luck.shrine_mul_bps)
	var raw: int = (int(parts.base)+int(parts.gear)+int(parts.reward_grade)+int(parts.pity))*shrine/10000
	var jackpot := mini(raw,int(d.cap_bps))
	var rare := mini(int(d.rare_bps)*shrine/10000,10000-jackpot)
	return {"jackpot_bps":jackpot,"rare_bps":rare,"shrine_mul_bps":shrine,"parts":parts,"capped":raw > jackpot}

## One pull of the grade stream. value in 0..9999; below jackpot_at is a jackpot, below rare_at a rare, else common.
## near: a miss within near_bps above the jackpot line (the screen may call it "close" only then).
func _roll_slot(jackpot_at: int, rare_chance: int) -> Dictionary:
	var value := _grade_rng.randi_range(0,9999)
	var rare_at := mini(10000,jackpot_at+rare_chance)
	var grade := "common"
	if value < jackpot_at: grade = "jackpot"
	elif value < rare_at: grade = "rare"
	var near := grade != "jackpot" and value-jackpot_at < int(_grace.grades.near_bps)
	return {"grade":grade,"rollable":true,"roll":{"value_bps":value,"rare_at_bps":rare_at,"jackpot_at_bps":jackpot_at},"near":near,"forced":false}

func _matched_now(card: Dictionary) -> bool:
	return not _spells.is_empty() and card.has("skill_id") and not _pairs_with(String(card.skill_id),owned_spells()).is_empty()

func _recount_jackpot() -> void:
	if _offer_meta.is_empty(): return
	var any := false
	for id_ in _offer_meta.get("grades",{}):
		if String(_offer_meta.grades[id_].grade) == "jackpot": any = true
	_offer_meta.has_jackpot = any

## Pulls the grades of a freshly made offer (D13 4.11.1/4.11.3). A card that was set aside keeps the grade it had. Counts the
## spin (a re-draw is one too), the soft and hard pity, and queues the three events for the screen.
func _roll_offer(selected: Array[Dictionary], carried: Dictionary, final: bool) -> Dictionary:
	var meta := {"grades":{},"spin":_spins,"forced":false,"odds":{},"final":final,"has_jackpot":false}
	if not grades_on(): return meta
	var d: Dictionary = _grace.grades
	var odds := _grade_odds()
	meta.odds = odds
	var grades: Dictionary = meta.grades
	var rolled: Array[String] = []
	# The last offer's one extra-lucky slot is the first card that is pulled (D13 4.11.3).
	var final_slot := -1
	if final:
		for i in selected.size():
			if not carried.has(String(selected[i].id)) and _rollable(selected[i]):
				final_slot = i
				break
	for i in selected.size():
		var id_ := String(selected[i].id)
		if carried.has(id_):
			grades[id_] = carried[id_].duplicate(true)
			continue
		if not _rollable(selected[i]):
			grades[id_] = _plain_grade()
			continue
		var at := int(odds.jackpot_bps)
		if i == final_slot: at = mini(int(d.cap_bps),at*int(d.final_offer_jackpot_mul_bps)/10000)
		grades[id_] = _roll_slot(at,int(odds.rare_bps))
		rolled.append(id_)
	if rolled.is_empty():
		meta.has_jackpot = _any_jackpot(grades)
		return meta
	_spins += 1
	var natural := false
	for id_ in rolled:
		if String(grades[id_].grade) == "jackpot": natural = true
	var forced := false
	var hard := int(d.pity.hard_after_spins)
	if not natural and hard > 0 and _pity+1 >= hard:
		var pick: String = rolled[_grade_rng.randi_range(0,rolled.size()-1)]
		grades[pick].grade = "jackpot"
		grades[pick].forced = true
		grades[pick].near = false
		forced = true
	_pity = 0 if natural or forced else _pity+1
	meta.spin = _spins
	meta.forced = forced
	meta.has_jackpot = _any_jackpot(grades)
	var names: Array[String] = []
	var nears: Array[bool] = []
	var slots: Array[int] = []
	var matches: Array[bool] = []
	for i in selected.size():
		var info: Dictionary = grades[String(selected[i].id)]
		names.append(String(info.grade))
		nears.append(bool(info.near))
		if String(info.grade) == "jackpot":
			slots.append(i)
			matches.append(_matched_now(selected[i]))
	_push_event("grace_grades_rolled",{"level":int(_pending[0]),"grades":names,"near":nears,"forced_by_pity":forced,"spin":_spins})
	if not slots.is_empty(): _push_event("grace_jackpot_shown",{"level":int(_pending[0]),"slots":slots,"matched":matches})
	return meta

func _any_jackpot(grades: Dictionary) -> bool:
	for id_ in grades:
		if String(grades[id_].grade) == "jackpot": return true
	return false

## What a grade does to this card on the build as it is now (D13 4.11.2, the resonance form). mode "base" forces the floor of
## a jackpot, "resonance" forces its resonance size (the partner part still needs a real partner). {} for a card without a grade effect.
##  points         what the spell gets in total (axis points, or 1 + the extra rank steps)
##  self           axis points ADDED ON TOP of the card's own change {damage, reach}
##  partner_*      the owned spell that is paired with this one and the points it gets (a pick that makes a resonance)
##  resonance      a real resonance: a jackpot, form "resonance", and an owned partner exists
func _grade_plan(card: Dictionary, grade: String, mode: String = "") -> Dictionary:
	var d: Dictionary = _grace.grades
	var kind := String(card.kind)
	var plan := {"grade":grade,"kind":kind,"resonance":false,"effect_key":kind,"points":0,"self":{"damage":0,"reach":0},
		"partner_skill":"","partner":{"damage":0,"reach":0},"rank_extra":0,"cap_bonus":0}
	var jack: Dictionary = d.jackpot
	if kind == "rank":
		var extra := int(d.rare.rank_points) if grade == "rare" else int(jack.base.rank_points)
		plan.rank_extra = clampi(extra,0,4-int(card.rank))
		plan.points = 1+int(plan.rank_extra)
		return plan
	if _spells.is_empty() or not (kind == "axis" or kind == "unlock"): return {}
	var id_ := String(card.skill_id)
	var caps: Dictionary = _spells.axis
	var cap_axis := int(caps.cap_per_axis)
	var cap_sum := int(caps.cap_per_spell)
	var matched := _matched_now(card)
	var is_jackpot := grade == "jackpot"
	var use_res := is_jackpot and mode != "base" and (String(jack.form) == "big" or mode == "resonance" or matched)
	var partner_on := is_jackpot and mode != "base" and String(jack.form) == "resonance" and matched
	var points := 0
	if grade == "rare": points = int(d.rare.axis_points) if kind == "axis" else int(d.rare.unlock_points)
	elif use_res: points = int(jack.resonance.axis_points) if kind == "axis" else int(jack.resonance.unlock_points)
	else: points = int(jack.base.axis_points) if kind == "axis" else int(jack.base.unlock_points)
	plan.cap_bonus = int(jack.resonance.axis_cap_bonus) if use_res else 0
	var added := {"damage":0,"reach":0}
	if kind == "axis":
		var axis := String(card.axis)
		var have: Dictionary = _axes[id_]
		var allowed := maxi(1,mini(points,mini(cap_axis-int(have[axis]),cap_sum+int(plan.cap_bonus)-_axis_sum(id_))))
		added[axis] = allowed-1
		plan.effect_key = axis
		plan.points = allowed
	else:
		added = _spread({"damage":0,"reach":0},points,cap_axis,cap_sum+int(plan.cap_bonus))
		plan.points = int(added.damage)+int(added.reach)
	plan.self = added
	if partner_on:
		plan.resonance = true
		var target := _partner_target(id_,int(jack.resonance.partner_points))
		if not target.is_empty():
			plan.partner_skill = String(target.skill)
			plan.partner = target.axis
	return plan

## `points` one by one onto the lower axis (damage on a tie) that still has room: each axis up to cap_axis, `sum_room` points in all.
func _spread(have: Dictionary, points: int, cap_axis: int, sum_room: int) -> Dictionary:
	var added := {"damage":0,"reach":0}
	var cur := {"damage":int(have.damage),"reach":int(have.reach)}
	for _n in points:
		if sum_room <= 0: break
		var pick := ""
		for axis in ["damage","reach"]:
			if int(cur[axis]) >= cap_axis: continue
			if pick.is_empty() or int(cur[axis]) < int(cur[pick]): pick = axis
		if pick.is_empty(): break
		cur[pick] = int(cur[pick])+1
		added[pick] = int(added[pick])+1
		sum_room -= 1
	return added

## The owned spell paired with `id_` that has the lowest axis sum and still room (ties: spell order), with the points it gets.
## {} when no paired spell has room. The caps of the partner are never exceeded.
func _partner_target(id_: String, points: int) -> Dictionary:
	var caps: Dictionary = _spells.axis
	var cap_axis := int(caps.cap_per_axis)
	var cap_sum := int(caps.cap_per_spell)
	var best := ""
	var best_sum := 1000
	for other in owned_spells():
		if other == id_ or Spells.pair_between(_spells,id_,other).is_empty(): continue
		var sum := _axis_sum(other)
		if sum >= cap_sum or (int(_axes[other].damage) >= cap_axis and int(_axes[other].reach) >= cap_axis): continue
		if sum < best_sum:
			best = other
			best_sum = sum
	if best.is_empty(): return {}
	var added := _spread(_axes[best],points,cap_axis,cap_sum-best_sum)
	if int(added.damage)+int(added.reach) == 0: return {}
	return {"skill":best,"axis":added}

## The extra part of a grade, applied after the card's own change.
func _apply_plan_extras(card: Dictionary, plan: Dictionary) -> void:
	var id_ := String(card.get("skill_id",""))
	if String(plan.kind) == "rank":
		_ranks[id_] = mini(4,int(_ranks[id_])+int(plan.rank_extra))
		return
	for axis in ["damage","reach"]:
		_axes[id_][axis] = int(_axes[id_][axis])+int(plan.self[axis])
	if not String(plan.partner_skill).is_empty():
		var other := String(plan.partner_skill)
		for axis in ["damage","reach"]:
			_axes[other][axis] = int(_axes[other][axis])+int(plan.partner[axis])

## Would the spell (and its partner) be ready to evolve after this pick? Tries it on a copy of the state and puts the state back.
func _ready_after(card: Dictionary, plan: Dictionary) -> Dictionary:
	var axes_saved := _axes.duplicate(true)
	var ranks_saved := _ranks.duplicate(true)
	_apply_card_effect(card)
	if not plan.is_empty(): _apply_plan_extras(card,plan)
	var id_ := String(card.get("skill_id",""))
	var other := String(plan.get("partner_skill",""))
	var result := {"self":_can_evolve(id_),"partner":_can_evolve(other) if not other.is_empty() else false}
	_axes = axes_saved
	_ranks = ranks_saved
	return result

func _compose_levels(id_: String, damage: int, reach: int) -> Dictionary:
	return Spells.compose(_spells,id_,damage,reach,_starts.get(id_,{}))

## One side of a card's grade for the screen: values -> values, nothing is stored.
func _plan_view(card: Dictionary, plan: Dictionary) -> Dictionary:
	var kind := String(card.kind)
	var id_ := String(card.get("skill_id",""))
	var view := {"effect_key":String(plan.effect_key),"points":int(plan.points),"after":{},"changed":{},"partner_skill":"","partner_points":0,"partner_after":{},"evolve_ready_after":false,"partner_evolve_ready_after":false,"axis_cap_bonus":int(plan.cap_bonus)}
	if kind == "rank":
		var rank_after := mini(4,int(card.rank)+int(plan.rank_extra))
		view.after = _skills[id_].ranks[rank_after-1].duplicate(true)
		view.rank_after = rank_after
		return view
	var now: Dictionary = _axes.get(id_,{"damage":0,"reach":0})
	var damage := int(now.damage)+int(plan.self.damage)+(1 if kind == "axis" and String(card.axis) == "damage" else 0)
	var reach := int(now.reach)+int(plan.self.reach)+(1 if kind == "axis" and String(card.axis) == "reach" else 0)
	view.after = _compose_levels(id_,damage,reach)
	if _ranks.has(id_):
		var before: Dictionary = effective_skill(id_).get("effects",{})
		for key in view.after:
			if before.get(key) != view.after[key]: view.changed[String(key)] = {"before":before.get(key,0),"after":view.after[key]}
	var other := String(plan.partner_skill)
	if not other.is_empty():
		var have: Dictionary = _axes[other]
		view.partner_skill = other
		view.partner_axis = plan.partner.duplicate()
		view.partner_points = int(plan.partner.damage)+int(plan.partner.reach)
		view.partner_after = _compose_levels(other,int(have.damage)+int(plan.partner.damage),int(have.reach)+int(plan.partner.reach))
	var ready := _ready_after(card,plan)
	view.evolve_ready_after = bool(ready.self)
	view.partner_evolve_ready_after = bool(ready.partner)
	return view

## The grade part of the card contract (read only; draws nothing, stores nothing). {} while the grades are off.
## grade "common"|"rare"|"jackpot", rollable (false: this card is never pulled), roll {value_bps, rare_at_bps, jackpot_at_bps}
## (the real pull; {} when not pulled), near (a real miss within near_bps above the jackpot line), forced_by_pity,
## rare {points, after, changed, ...} (grade rare), jackpot {matched_now, base:{...}, resonance:{..., needs}} (grade jackpot).
func grade_fields(card: Dictionary) -> Dictionary:
	if not grades_on(): return {}
	var info: Dictionary = _offer_meta.get("grades",{}).get(String(card.get("id","")),{})
	var grade := String(info.get("grade","common"))
	var out := {"grade":grade,"rollable":bool(info.get("rollable",false)),"roll":info.get("roll",{}).duplicate(),"near":bool(info.get("near",false)),"forced_by_pity":bool(info.get("forced",false))}
	if grade == "common" or not bool(out.rollable): return out
	if grade == "rare":
		var rare_plan := _grade_plan(card,"rare")
		if not rare_plan.is_empty(): out.rare = _plan_view(card,rare_plan)
		return out
	var matched := _matched_now(card)
	var base_plan := _grade_plan(card,"jackpot","base")
	var res_plan := _grade_plan(card,"jackpot","resonance")
	if base_plan.is_empty() or res_plan.is_empty(): return out
	var resonance := _plan_view(card,res_plan)
	var needs: Array[String] = []
	if not matched and not _spells.is_empty() and card.has("skill_id"):
		for other in _spell_order():
			if other != String(card.skill_id) and not _ranks.has(other) and not Spells.pair_between(_spells,String(card.skill_id),other).is_empty(): needs.append(other)
	resonance.needs = needs
	out.jackpot = {"matched_now":matched,"form":String(_grace.grades.jackpot.form),"base":_plan_view(card,base_plan),"resonance":resonance}
	return out

## For the screen (chapter_core.grace_tools adds the core's part). Reads only.
func grace_view() -> Dictionary:
	if not grace_on(): return {"enabled":false,"rerolls_left":_rerolls_left}
	var refill := not _offer.is_empty() and not _refill_candidates().is_empty()
	var would := {}
	var banishable := {}
	for card in _offer.get("cards",[]):
		var id_ := String(card.id)
		would[id_] = refill
		banishable[id_] = _banishes_left > 0 and String(card.kind) in _grace.tools.banish_kinds and String(_held.get("id","")) != id_
	var banished: Array[String] = []
	banished.assign(_banished)
	var view := {"enabled":true,"grades_enabled":grades_on(),"rerolls_left":_rerolls_left,"banishes_left":_banishes_left,"holds_left":_holds_left,
		"held_card_id":String(_held.get("id","")),"banished":banished,"banish_would_refill":would,"banishable":banishable,
		"final":bool(_offer_meta.get("final",false)),"held_dropped":bool(_offer_meta.get("held_dropped",false))}
	if not grades_on(): return view
	var cards := {}
	for card in _offer.get("cards",[]): cards[String(card.id)] = grade_fields(card)
	var odds: Dictionary = _offer_meta.get("odds",{})
	var luck := _luck.duplicate()
	luck.reward_grade_bps = int(_grace.grades.luck.per_reward_grade_bps)*int(_luck.reward_grade)
	luck.gear_cap_bps = int(_grace.grades.luck.gear_cap_bps)
	view.merge({"spin":int(_offer_meta.get("spin",_spins)),"has_jackpot":bool(_offer_meta.get("has_jackpot",false)),"forced_by_pity":bool(_offer_meta.get("forced",false)),
		"odds":odds.duplicate(true),"pity":{"spins":_pity,"hard_after":int(_grace.grades.pity.hard_after_spins),"soft_step_bps":int(_grace.grades.pity.soft_step_bps)},
		"near_bps":int(_grace.grades.near_bps),"luck":luck,"offer_cards":cards})
	return view
