extends RefCounted
## Pure run growth. No world simulation, rendering, native profile reads or writes.
## RNG docs: https://docs.godotengine.org/en/4.5/classes/class_randomnumbergenerator.html
const Catalog = preload("res://chapter1/core/growth_catalog.gd")
const Spells = preload("res://chapter1/core/run_spells.gd")
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
## In-run spell composition (chapter1/data/run_spells.json, D12 G5). Empty = off: every rule below stays out of the way
## and the run is exactly the one without the file. _axes: {spell id: {damage, reach}}; _evolve_partner: {spell id: pair id}.
var _spells: Dictionary = {}
var _starts: Dictionary = {}
var _owner_skill: Dictionary = {}
var _axes: Dictionary = {}
var _evolve_partner: Dictionary = {}

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
	if not _spells.is_empty() and _spells.spells.has(id_): return _spell_skill(id_,_axes[id_])
	var rank: int = _ranks[id_]
	var definition: Dictionary = _skills[id_]
	var effect: Dictionary = definition.evolution if id_ in _evolved else definition.ranks[rank-1]
	return {"id":id_,"rank":rank,"evolved":id_ in _evolved,
		"name_key":"skill.%s.%s"%[id_,"evolved_name" if id_ in _evolved else "name"],
		"effects":effect.duplicate(true)}

func xp_thresholds() -> Array:
	return _doc.get("xp_thresholds",[0]).duplicate()

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
		if rank == 4 and (s.passive_id in _owned_passives or (_evolve_free and s.id == _primary)) and not s.id in _evolved:
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
		"unlock","rank":
			_ranks[chosen.skill_id] = int(chosen.rank)
			if not _spells.is_empty(): _axes[chosen.skill_id] = {"damage":0,"reach":0}
		"axis": _axes[chosen.skill_id][chosen.axis] = int(_axes[chosen.skill_id][chosen.axis])+1
		"passive": _owned_passives.append(chosen.passive_id)
		"evolve":
			_evolved.append(chosen.skill_id)
			if not _spells.is_empty(): _evolve_partner[chosen.skill_id] = String(chosen.partner_pair)
	_pending.pop_front()
	_offer = {}
	errors.clear()
	return true

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
		if _can_evolve(id_):
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
