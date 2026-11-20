extends RefCounted
## The adapter of the grace screen (A8 G6, T8 3): the core's read-only state of a standing growth choice -> the contract chapter1/view/hud/screens/growth_choice.gd reads
## (schema chapter1/tests/contracts/growth_choice.contract.json). The one place of the view that asks the core for the offer. It writes nothing to the core.
## Called when the choice window is rebuilt (never every frame). All words are Loc keys; all numbers come from the cards and the spell document.
## app_state: {"growth": the frame's growth snapshot (the host already has it), "describe": Callable(card) -> the host's description text of a card}. Both are optional.
##
## get_offer() is the exception T8 allows to this file only: it draws the offer when none is standing yet. When the core draws the offer on entering the choice mode
## (T8 S0-c, gameplay-systems) this call becomes a pure read and this note goes.
const CONTRACT_VERSION := 1
const Palette = preload("res://chapter1/view/hud/palette.gd")
const Loc = preload("res://chapter1/view/loc.gd")
const BASIC_EMBLEM := {"ember": "orb", "frost": "lance", "arc": "bolt"}
const ROMAN := ["", "Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ"]
const BASE_SKILLS := ["chapter1.skill.ember", "chapter1.skill.frost", "chapter1.skill.arc"]
## effect key -> [short label key, divisor, decimals]
const AXIS_ROWS := [
	["damage_raw", "grace.screen.axis.damage", 256.0, 0], ["cooldown_ticks", "grace.screen.axis.interval", 60.0, 2], ["ring_radius_cm", "grace.screen.axis.radius", 100.0, 1],
	["projectiles", "grace.screen.axis.projectiles", 1.0, 0], ["pierce", "grace.screen.axis.pierce", 1.0, 0], ["chain_targets", "grace.screen.axis.targets", 1.0, 0],
	["ring_targets", "grace.screen.axis.targets", 1.0, 0], ["radius_cm", "grace.screen.axis.blast", 100.0, 1], ["branches", "grace.screen.axis.branches", 1.0, 0],
]

static func build(run: RefCounted, app_state: Dictionary = {}) -> Dictionary:
	var offer: Dictionary = run.get_offer()
	var card_list: Array = offer.get("cards", [])
	var view: Dictionary = run.run_spells_view()
	var tools: Dictionary = run.grace_tools()
	var snap: Dictionary = app_state.get("growth", {})
	var describe: Callable = app_state.get("describe", Callable())
	var doc: Dictionary = run.spells if bool(view.get("enabled", false)) else {}
	var witch := _witch_element(run, snap)
	var grades_on: bool = bool(tools.get("grades_enabled", false))
	var cards: Array = []
	var best := "common"
	for card in card_list:
		var one := _card(run, card, view, tools, doc, describe, witch)
		cards.append(one)
		if one.grade == "jackpot": best = "jackpot"
		elif one.grade == "rare" and best != "jackpot": best = "rare"
	var level := int(offer.get("level", 1))
	var kind := "last" if bool(tools.get("final", false)) else ("first" if level <= 2 else "normal")
	var result := {"screen": "growth_choice", "contract_version": CONTRACT_VERSION, "offer_ref": String(offer.get("token", "")), "witch": {"id": witch, "element": witch},
		"giver": _giver(witch, best, kind), "moment": {"kind": kind, "index": clampi(level, 1, 20), "total": 20, "label": Loc.t("grace.screen.moment", {"n": Loc.num(level)})},
		"cards": cards, "owned": _owned(run, view, snap)}
	var left := int(tools.get("rerolls_left", run.rerolls_left()))
	if left > 0 or bool(tools.get("enabled", false)): result.reroll = {"left": left, "left_label": Loc.num(left)}
	if bool(tools.get("enabled", false)):
		result.exclude = {"left": int(tools.get("banishes_left", 0)), "left_label": Loc.num(int(tools.get("banishes_left", 0)))}
		if int(tools.get("holds_left", 0)) > 0: result.keep = {"left_label": Loc.num(int(tools.get("holds_left", 0)))}
	if grades_on:
		var odds: Dictionary = tools.get("odds", {})
		var pity: Dictionary = tools.get("pity", {})
		var to_pity := maxi(0, int(pity.get("hard_after", 0)) - int(pity.get("spins", 0)))
		result.odds = Loc.t("grace.screen.odds", {"jackpot": Loc.num(int(odds.get("jackpot_bps", 0)) / 100), "rare": Loc.num(int(odds.get("rare_bps", 0)) / 100), "n": Loc.num(to_pity)})
	return result

static func _witch_element(run: RefCounted, snap: Dictionary) -> String:
	var primary := String(snap.get("primary", ""))
	if primary == "":
		for id_ in BASE_SKILLS:
			if int(run.effective_skill(id_).get("rank", 0)) > 0:
				primary = id_
				break
	var e: String = Palette.spell_element(primary)
	return e if e != "" else "ember"

static func _giver(witch: String, best: String, kind: String) -> Dictionary:
	if witch == "arc": return {"line": null, "mute": true}   ## the storm demon does not speak (D14 fix 4)
	var tier := "jackpot" if best == "jackpot" else ("first" if kind == "first" and witch == "frost" else ("normal" if best == "common" else ""))
	if tier == "": return {"line": null, "mute": false}
	return {"line": Loc.t("grace.screen.giver.%s.%s" % [witch, tier]), "mute": false}

static func _card(run: RefCounted, card: Dictionary, view: Dictionary, tools: Dictionary, doc: Dictionary, describe: Callable, witch: String) -> Dictionary:
	var id_ := String(card.id)
	var skill_id := String(card.get("skill_id", ""))
	var info: Dictionary = view.get("offer", {}).get(id_, {})
	var kind_core := String(card.get("kind", "unlock"))
	var spell: Dictionary = doc.get("spells", {}).get(skill_id, {})
	var is_ring := String(spell.get("role", "")) == "ring"
	var element := String(spell.get("element", Palette.spell_element(skill_id)))
	if element == "": element = witch
	var grade := String(tools.get("offer_cards", {}).get(id_, {}).get("grade", "common"))
	var text := String(describe.call(card)) if describe.is_valid() else ""
	var lines := text.split("\n", false)
	var headline := String(lines[0]) if lines.size() > 0 else ""
	var kind := "new"
	var kind_label := Loc.t("grace.screen.kind.new")
	match kind_core:
		"unlock":
			kind = "new" if (is_ring or spell.is_empty()) else "trade"
			if not spell.is_empty(): kind_label = Loc.t("hud.spell.kind.ring" if is_ring else "hud.spell.kind.borrow")
		"rank", "axis":
			kind = "upgrade"
			kind_label = Loc.t("hud.spell.kind.%s_%s" % ["ring" if is_ring else "basic", String(card.get("axis", "damage"))]) if (kind_core == "axis" and not spell.is_empty()) else Loc.t("grace.screen.kind.upgrade")
		"passive":
			kind = "prep"
			kind_label = Loc.t("grace.screen.kind.prep")
		"evolve":
			kind = "evolve"
			kind_label = Loc.t("grace.screen.kind.evolve")
	var out := {"id": id_, "element": element, "kind": kind, "kind_label": kind_label,
		"header": Loc.t("grace.screen.header.trade", {"demon": Loc.t("grace.screen.demon." + element)}) if kind == "trade" else Loc.t("grace.screen.header.oath"),
		"name": Loc.t(String(card.get("title_key", ""))), "tier": _tier(card, kind_core), "headline": headline, "delta": null, "meter": null,
		"line": headline, "details": [], "combo": [], "path": null, "terms": [], "emblem": "ring" if is_ring else BASIC_EMBLEM.get(element, "orb"),
		"grade": grade, "grade_name": "" if grade == "common" else Loc.t("grace.screen.grade." + grade)}
	if kind == "new" and is_ring and spell.has("element"): out.headline = Loc.t("hud.spell.ring.role." + element); out.line = out.headline
	var details: Array = []
	for i in range(1, mini(lines.size(), 4)): details.append(String(lines[i]))
	out.details = details
	out.delta = _delta(run, card, skill_id, info)
	if kind_core == "axis" and not doc.is_empty():
		var cap := int(doc.get("axis", {}).get("cap_per_axis", 4))
		var levels: Dictionary = view.get("spells", {}).get(skill_id, {}).get("axis", {"damage": 0, "reach": 0}).duplicate()
		levels[String(card.get("axis", "damage"))] = int(card.get("level", 0))
		var axis_name := String(card.get("axis", "damage"))
		out.meter = {"label": Loc.t("hud.spell.axis.%s_%s" % [axis_name, "ring" if is_ring else "basic"]), "filled": clampi(int(levels.get(axis_name, 0)), 0, 8), "total": clampi(cap, 1, 8)}
	out.combo = _combo(info, doc)
	var evo: Dictionary = view.get("spells", {}).get(skill_id, {}).get("evolve_progress", {})
	if not evo.is_empty() and kind_core in ["axis", "passive"]: out.path = _path(evo)
	return out

static func _tier(card: Dictionary, kind_core: String) -> String:
	var n := int(card.get("level", card.get("rank", 0))) if kind_core in ["axis", "rank"] else 0
	return ROMAN[clampi(n, 0, ROMAN.size() - 1)]

## One changed effect of the card as "label before -> after" (the first row of AXIS_ROWS that moves).
static func _delta(run: RefCounted, card: Dictionary, skill_id: String, info: Dictionary) -> Variant:
	var kind_core := String(card.get("kind", ""))
	if kind_core not in ["axis", "rank"]: return null
	var after: Dictionary = card.get("after", {})
	var before: Dictionary = info.get("before", {})
	if before.is_empty() and skill_id != "":
		var current: Dictionary = run.effective_skill(skill_id)
		before = current.get("effects", {}) if int(current.get("rank", 0)) > 0 else {}
	for row in AXIS_ROWS:
		var key: String = row[0]
		if not before.has(key) or not after.has(key) or int(before[key]) == int(after[key]): continue
		return {"label": Loc.t(String(row[1])), "before": _number(float(before[key]) / float(row[2]), int(row[3])), "after": _number(float(after[key]) / float(row[2]), int(row[3]))}
	return null

static func _number(value: float, decimals: int) -> String:
	return Loc.dec(value, decimals) if decimals > 0 else Loc.num(int(roundf(value)))

static func _combo(info: Dictionary, doc: Dictionary) -> Array:
	var out: Array = []
	for link in info.get("pair_links", []):
		if String(link.kind) == "reaction" or not doc.get("spells", {}).has(String(link.a)) or not doc.get("spells", {}).has(String(link.b)): continue
		var pair := _pair(doc, String(link.id))
		if pair.is_empty(): continue
		var a: Dictionary = doc.spells[String(link.a)]
		var b: Dictionary = doc.spells[String(link.b)]
		out.append({"from": "ring" if String(a.role) == "ring" else BASIC_EMBLEM.get(String(a.element), "orb"), "from_element": String(a.element),
			"to": "ring" if String(b.role) == "ring" else BASIC_EMBLEM.get(String(b.element), "orb"), "to_element": String(b.element), "text": _pair_text(doc, pair)})
		if out.size() >= 4: break
	return out

static func _pair(doc: Dictionary, pair_id: String) -> Dictionary:
	for pair in doc.get("pairs", []):
		if String(pair.id) == pair_id: return pair
	return {}

## "{verb} enemy: {b} +{n}%" for an interlock, "{status} enemy burst +{n}%" for a detonation (the same texts the old spell card showed).
static func _pair_text(doc: Dictionary, pair: Dictionary) -> String:
	var b_name := Loc.t("skill.%s.name" % pair.b)
	if String(pair.kind) == "detonate":
		var ring: Dictionary = doc.spells[pair.b]
		var rule: Dictionary = ring.detonates.get(String(pair.status), {})
		var text := Loc.t("hud.spell.pair.detonate", {"status": Loc.t("hud.spell.status." + String(pair.status)), "n": Loc.num(int(rule.get("bonus_bps", 0)) / 100)})
		if int(rule.get("block_bps", 10000)) != 10000: text += Loc.t("hud.spell.pair.block", {"ctl": Loc.t("hud.spell.ctl." + String(ring.element)), "x": Loc.dec(float(rule.block_bps) / 10000.0, 1)})
		if int(rule.get("block_targets", 0)) > 0: text += Loc.t("hud.spell.pair.block_targets", {"n": Loc.num(int(rule.block_targets))})
		return text
	var table: Dictionary = doc.spells[pair.b].get("vs_cc", {})
	var vias: Array = pair.via.duplicate()
	vias.sort_custom(func(x, y): return int(table.get(String(x), 0)) > int(table.get(String(y), 0)))
	return Loc.t("hud.spell.pair.interlock", {"b": b_name, "verb": Loc.t("hud.spell.verb." + String(vias[0])), "n": Loc.num(int(table.get(String(vias[0]), 0)) / 100)})

static func _path(evo: Dictionary) -> Dictionary:
	var axis: Dictionary = evo.get("axis", {})
	var partner: Dictionary = evo.get("partner", {})
	var need := clampi(int(axis.get("need", 1)), 1, 8)
	var keys: Array = []
	if bool(evo.get("passive", {}).get("need", false)): keys.append({"label": Loc.t("grace.screen.path.passive"), "done": bool(evo.passive.have)})
	keys.append({"label": Loc.t("grace.screen.path.partner"), "done": int(partner.get("have", 0)) >= int(partner.get("need", 1)), "value": "%d/%d" % [int(partner.get("have", 0)), int(partner.get("need", 1))]})
	return {"label": Loc.t("grace.screen.path.label"), "filled": clampi(int(axis.get("have", 0)), 0, need), "total": need, "keys": keys}

## The band along the bottom: the spells owned now (picture, level) and the grace slots.
static func _owned(run: RefCounted, view: Dictionary, snap: Dictionary) -> Dictionary:
	var spells: Array = []
	var ids: Array = BASE_SKILLS.duplicate()
	for id_ in view.get("spells", {}):
		if not id_ in ids: ids.append(id_)
	for id_ in ids:
		var skill: Dictionary = run.effective_skill(String(id_))
		if int(skill.get("rank", 0)) <= 0: continue
		var info: Dictionary = view.get("spells", {}).get(id_, {})
		var element: String = String(info.get("element", Palette.spell_element(String(id_))))
		var key_name := String(skill.get("name_key", "skill.%s.name" % id_))
		spells.append({"name": Loc.t(key_name), "emblem": "ring" if String(info.get("role", "")) == "ring" else BASIC_EMBLEM.get(element, "orb"), "element": element if element != "" else "ember",
			"level": Loc.num(int(skill.get("rank", 1)))})
	var passives: Array = snap.get("passives", [])
	var graces: Array = []
	for p in passives: graces.append({"name": Loc.t("grace.passive.%s.name" % String(p)), "owned": true})
	return {"slots": maxi(3, spells.size()), "spells": spells.slice(0, 6), "grace_slots": maxi(2, graces.size()), "graces": graces.slice(0, 6)}
