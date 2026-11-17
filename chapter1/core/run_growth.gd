extends RefCounted
## Pure run growth. No world simulation, rendering, native profile reads or writes.
## RNG docs: https://docs.godotengine.org/en/4.5/classes/class_randomnumbergenerator.html
const Catalog = preload("res://chapter1/core/growth_catalog.gd")
const MAX_XP := 1000000000
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
	_rng.seed = run_seed
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
	_ranks[_primary] = int(start_rank)
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
	var sequence := _offer_sequence
	_rerolls_left -= 1
	_offer = {}
	if next_offer().is_empty():
		_rerolls_left += 1
		_offer = previous
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
	var rank: int = _ranks[id_]
	var definition: Dictionary = _skills[id_]
	var effect: Dictionary = definition.evolution if id_ in _evolved else definition.ranks[rank-1]
	return {"id":id_,"rank":rank,"evolved":id_ in _evolved,
		"name_key":"skill.%s.%s"%[id_,"evolved_name" if id_ in _evolved else "name"],
		"effects":effect.duplicate(true)}

func xp_thresholds() -> Array:
	return _doc.get("xp_thresholds",[0]).duplicate()

func _eligible_cards() -> Array[Dictionary]:
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
		if rank == 4 and (s.passive_id in _owned_passives or (_evolve_free and s.id == _primary)) and not s.id in _evolved:
			result.append({"id":"evolve:"+s.id,"kind":"evolve","skill_id":s.id,"rank":4,"weight":int(s.weight),"title_key":"skill.%s.evolved_name"%s.id,"after":s.evolution.duplicate(true)})
	return result

func _protected_card(cards: Array[Dictionary]) -> int:
	# Keep a reachable primary evolution path; the player still chooses it or another card.
	for preferred in ["evolve","rank","passive"]:
		for i in cards.size():
			if cards[i].skill_id == _primary and cards[i].kind == preferred: return i
	return -1

func next_offer() -> Dictionary:
	if not _offer.is_empty(): return _offer.duplicate(true)
	if _doc.is_empty() or _pending.is_empty(): return {}
	var pool := _eligible_cards()
	if pool.is_empty():
		errors.assign(["No legal growth candidates"])
		return {}
	var selected: Array[Dictionary] = []
	var protected := _protected_card(pool)
	if protected >= 0:
		selected.append(pool[protected])
		pool.remove_at(protected)
	while selected.size() < 3 and not pool.is_empty():
		var total := 0
		for card in pool: total += int(card.weight)
		var roll := _rng.randi_range(1,total)
		var index := 0
		while roll > int(pool[index].weight):
			roll -= int(pool[index].weight)
			index += 1
		selected.append(pool[index])
		pool.remove_at(index)
	_offer_sequence += 1
	_offer = {"token":"%d:%d" % [_epoch,_offer_sequence],"level":_pending[0],"cards":selected}
	return _offer.duplicate(true)

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
	match chosen.kind:
		"unlock","rank": _ranks[chosen.skill_id] = int(chosen.rank)
		"passive": _owned_passives.append(chosen.passive_id)
		"evolve": _evolved.append(chosen.skill_id)
	_pending.pop_front()
	_offer = {}
	errors.clear()
	return true

func snapshot() -> Dictionary:
	var result := {"xp":_xp,"level":_level,"primary":_primary,"ranks":_ranks.duplicate(true),
		"passives":_owned_passives.duplicate(),"evolved":_evolved.duplicate(),
		"pending_levels":_pending.duplicate(),"offer":_offer.duplicate(true),
		"epoch":_epoch,"rng_state":str(_rng.state)}
	# Only a run with permanent-build options carries this key.
	if not _options.is_empty(): result.options = {"start_rank":int(_options.start_rank),"grace_rerolls":int(_options.grace_rerolls),"rerolls_left":_rerolls_left,"evolve_without_passive":_evolve_free}
	return result
