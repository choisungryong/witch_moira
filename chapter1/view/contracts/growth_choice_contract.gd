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
const ElementKit = preload("res://chapter1/core/element_kit.gd")
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
	var kit: Dictionary = app_state.get("kit", {})
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
		"cards": cards, "owned": _owned(run, view, snap, kit)}
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
		"passive", "rune":
			kind = "prep"
			kind_label = Loc.t("grace.screen.kind.prep")
		"evolve":
			kind = "evolve"
			kind_label = Loc.t("grace.screen.kind.evolve")
		"variant", "survival", "filler":
			# The element kit's cards (A-element-kit-screen 2, group A): the face is still the "new" one, the tag word tells the kind. The faces of group B come later.
			kind_label = Loc.t("grace.screen.kind." + kind_core)
	var is_kit := String(card.get("title_key", "")).begins_with("kit.card.")
	var out := {"id": id_, "element": element, "kind": kind, "kind_label": kind_label,
		"header": Loc.t("grace.screen.header.trade", {"demon": Loc.t("grace.screen.demon." + element)}) if kind == "trade" else Loc.t("grace.screen.header.oath"),
		"name": _card_name(card, kind_label), "tier": _tier(card, kind_core), "headline": headline, "delta": null, "meter": null,
		"line": headline, "details": [], "combo": [], "path": null, "terms": [], "emblem": "ring" if is_ring else BASIC_EMBLEM.get(element, "orb"),
		"grade": grade, "grade_name": "" if grade == "common" else Loc.t("grace.screen.grade." + grade)}
	if kind == "new" and is_ring and spell.has("element"): out.headline = Loc.t("hud.spell.ring.role." + element); out.line = out.headline
	var details: Array = []
	for i in range(1, mini(lines.size(), 4)): details.append(String(lines[i]))
	out.details = details
	if not is_kit: out.delta = _delta(run, card, skill_id, info)
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

## The card's name from its title key. A key without a text (a card the writers have not named) never reaches the screen as letters: the skill's name for a
## skill card, else the kind word.
static func _card_name(card: Dictionary, kind_label: String) -> String:
	var key := String(card.get("title_key", ""))
	var text := Loc.t(key)
	if text != key: return text
	var skill_key := "skill.%s.name" % String(card.get("skill_id", ""))
	var skill_name := Loc.t(skill_key)
	return kind_label if (String(card.get("skill_id", "")).is_empty() or skill_name == skill_key) else skill_name

# ---------------------------------------------------------------- the element kit's card text (A-element-kit-screen 2, group A)

static var _growth_arc_ranks: Array = []

## The one line of a kit card (`kit.card.<id>.line`), its numbers read from the kit document and the growth table. "" when the text does not exist yet:
## the old description function ("base damage 0") is never asked for these cards.
static func kit_line(card: Dictionary) -> String:
	var id_ := String(card.get("id", ""))
	var key := "kit.card.%s.line" % id_
	var text := Loc.t(key, _kit_args(card))
	return "" if text == key else text

static func _fmt(v: float) -> String:
	return Loc.num(int(roundf(v))) if absf(v - roundf(v)) < 0.001 else Loc.dec(v, 1)

static func _by_role(element: Dictionary, role: String) -> Dictionary:
	for id_ in element.get("skills", {}):
		if String(element.skills[id_].get("role", "")) == role: return element.skills[id_]
	return {}

## Rank rows of the signature skill from the growth table (the kit document has only the lay and burst skills' ranks).
static func _primary_ranks(primary: String) -> Array:
	if _growth_arc_ranks.is_empty():
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://chapter1/data/growth_quality36.json"))
		if doc is Dictionary:
			for s in doc.get("skills", []):
				if String(s.get("id", "")) == primary: _growth_arc_ranks = s.get("ranks", [])
	return _growth_arc_ranks

static func _kit_args(card: Dictionary) -> Dictionary:
	var id_ := String(card.get("id", ""))
	var doc: Dictionary = ElementKit.current()
	var element: Dictionary = {}
	var kit_card: Dictionary = {}
	for name_ in doc.get("elements", {}):
		for candidate in doc.elements[name_].get("cards", []):
			if String(candidate.id) == id_:
				element = doc.elements[name_]
				kit_card = candidate
	var args := {}
	if element.is_empty():
		var filler: Dictionary = doc.get("fillers", {}).get(id_, {}).get("effect", {})
		if filler.has("heal_bps_if_full"): args.p = _fmt(float(filler.heal_bps_if_full) / 100.0)
		elif filler.has("heal_bps"): args.p = _fmt(float(filler.heal_bps) / 100.0)
		return args
	var params: Dictionary = element.get("params", {})
	var lay := _by_role(element, "lay")
	var burst := _by_role(element, "burst")
	var vals: Dictionary = kit_card.get("change", {}).get("vals", {})
	var lay_ranks: Array = lay.get("ranks", [])
	var burst_ranks: Array = burst.get("ranks", [])
	match id_:
		"A01": args.t = _fmt(float(lay.get("cooldown_ticks", 0)) / 60.0)
		"A02": args.t = _fmt(float(burst.get("cooldown_ticks", 0)) / 60.0)
		"A03", "A04", "A05":
			var ranks := _primary_ranks(String(element.get("primary", "")))
			var at := int(card.get("rank", 0)) - 1
			if at >= 1 and at < ranks.size():
				var now: Dictionary = ranks[at]
				var before: Dictionary = ranks[at - 1]
				if id_ == "A03": args.n = _fmt(float(int(now.chain_targets) - int(before.chain_targets)))
				elif id_ == "A04": args.n = _fmt(float(now.branches))
				else:
					args.p = _fmt(roundf(float(int(now.damage_raw)) * 100.0 / maxf(1.0, float(int(before.damage_raw))) - 100.0))
					args.q = _fmt(roundf((1.0 - float(int(now.cooldown_ticks)) / maxf(1.0, float(int(before.cooldown_ticks)))) * 100.0))
		"A06":
			args.a = _fmt(float(element.get("rod", {}).get("ticks", 0)) / 60.0)
			if lay_ranks.size() > 1: args.b = _fmt(float(lay_ranks[1].get("rod_ticks", 0)) / 60.0)
		"A07":
			args.a = _fmt(float(element.get("rod", {}).get("keep_radius_cm", 0)) / 100.0)
			if lay_ranks.size() > 2: args.b = _fmt(float(lay_ranks[2].get("keep_radius_cm", 0)) / 100.0)
		"A08":
			args.a = _fmt(float(burst.get("max_bolts", 0)))
			if burst_ranks.size() > 1: args.b = _fmt(float(burst_ranks[1].get("max_bolts", 0)))
		"A09":
			if burst_ranks.size() > 2: args.p = _fmt(float(int(burst_ranks[2].get("bolt_bps", 0)) - int(burst.get("bolt_bps", 0))) / 100.0)
		"A11":
			var storm: Dictionary = element.get("evolution", {}).get("storm", {})
			args.t = _fmt(float(storm.get("every_ticks", 0)) / 60.0)
			args.n = _fmt(float(storm.get("targets", 0)))
		"A12": args.n = _fmt(float(vals.get("bolts_add", 0)))
		"A13": args.m = _fmt(float(params.get("death_chain", {}).get("reach_cm", 0)) / 100.0)
		"A14": args.n = _fmt(float(vals.get("lone_rebounds", 0)))
		"A15": args.n = _fmt(float(vals.get("branches", 0)))
		"A16":
			args.m = _fmt(float(params.get("discharge", {}).get("radius_cm", 0)) / 100.0)
			args.t = _fmt(float(params.get("discharge", {}).get("every_ticks", 0)) / 60.0)
		"A17":
			args.m = _fmt(float(params.get("pop", {}).get("radius_cm", 0)) / 100.0)
			args.d = _fmt(float(params.get("pop", {}).get("raw", 0)) / 256.0)
		"A18":
			args.a = _fmt(float(element.get("status", {}).get("max_big", 0)))
			args.b = _fmt(float(element.get("status", {}).get("max_big", 0)) + float(vals.get("max_big", 0)))
		"A19": args.n = _fmt(float(element.get("rod", {}).get("count", 1)) + float(vals.get("rod_count", 0)))
		"A20": args.p = _fmt(float(vals.get("rod_target_bps", 0)) / 100.0)
		"A21":
			args.p = _fmt(absf(float(vals.get("overload_cd_bps", 0))) / 100.0)
			args.n = _fmt(absf(float(vals.get("overload_max_bolts", 0))))
		"A22":
			args.p = _fmt(absf(float(vals.get("overload_cd_bps", 0))) / 100.0)
			args.q = _fmt(float(vals.get("overload_bolt_bps", 0)) / 100.0)
		"A23":
			args.a = _fmt(float(burst.get("self_bolt_bps", 0)) / 1000.0)
			args.b = _fmt((float(burst.get("self_bolt_bps", 0)) + float(vals.get("self_bolt_bps", 0))) / 1000.0)
		"A25": args.n = _fmt(float(vals.get("hp_max", 0)))
		"A26":
			var shell: Dictionary = params.get("shell", {})
			args.p = _fmt(float(shell.get("hp_bps", 0)) / 100.0)
			args.t = _fmt(float(shell.get("ticks", 0)) / 60.0)
			args.q = _fmt(float(shell.get("reduce_bps", 0)) / 100.0)
			args.m = _fmt(float(shell.get("radius_cm", 0)) / 100.0)
			args.c = _fmt(float(shell.get("cooldown_ticks", 0)) / 60.0)
		"A27":
			args.n = _fmt(float(params.get("bolt_heal", {}).get("bolts", 0)))
			args.h = _fmt(float(params.get("bolt_heal", {}).get("heal", 0)))
		"A28":
			args.p = _fmt(float(vals.get("move_bps", 0)) / 100.0)
			args.t = _fmt(float(params.get("stride", {}).get("every_ticks", 0)) / 60.0)
			args.m = _fmt(float(params.get("stride", {}).get("reach_cm", 0)) / 100.0)
	return args

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
static func _owned(run: RefCounted, view: Dictionary, snap: Dictionary, kit: Dictionary = {}) -> Dictionary:
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
	# The element kit's own skills (lay, burst): ranked ones join the band after the signature skill. The HUD hands over the frame's one kit_view().
	for id_ in kit.get("skills", {}):
		var rank := int(kit.skills[id_].get("rank", 0))
		if rank <= 0: continue
		spells.append({"name": Loc.t("skill.%s.name" % String(id_)), "emblem": "bolt", "element": String(kit.get("element", "arc")), "level": Loc.num(rank)})
	var passives: Array = snap.get("passives", [])
	var graces: Array = []
	for p in passives: graces.append({"name": Loc.t("grace.passive.%s.name" % String(p)), "owned": true})
	return {"slots": maxi(3, spells.size()), "spells": spells.slice(0, 6), "grace_slots": maxi(2, graces.size()), "graces": graces.slice(0, 6)}
