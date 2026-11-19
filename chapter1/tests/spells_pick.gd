extends RefCounted
## Check tool, not product code. How a tool turns the in-run spell composition ON and how it picks growth cards for it
## (RS0 of A6-RS, moved here from hud_dump.gd by AU-RS0 so report_audio_requests.gd and sfx_capture.gd use the same rule).
## Nothing here changes a data file: chapter1/data/run_spells.json stays "enabled": false; the copy is parked in the core
## of this process with run.set_run_spells() before the run starts.
const RunSpellsDoc := preload("res://chapter1/core/run_spells.gd")

## The shipped document with "enabled": true, handed to the core. "" when it worked, else one sentence.
static func enable(run: RefCounted) -> String:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(RunSpellsDoc.DEFAULT_PATH))
	if not doc is Dictionary: return "run_spells.json could not be read"
	doc["enabled"] = true
	if not run.set_run_spells(doc): return "run_spells document refused: "+str(run.errors)
	return ""

## RS0 pick rule. Same order the built-in pilot uses (chapter_pilot.decide) for everything the new rules do not name.
static func score(run: RefCounted, card: Dictionary, primary_id: String) -> int:
	var spell: Dictionary = run.spells.get("spells",{}).get(String(card.skill_id),{})
	var is_ring := String(spell.get("role","")) == "ring"
	if card.kind == "unlock" and is_ring: return 300
	if card.kind == "axis" and card.skill_id == primary_id and card.axis == "damage": return 200
	if card.kind == "axis" and is_ring and card.axis == "reach": return 150
	if card.skill_id == primary_id: return 100 if card.kind == "evolve" else (90 if card.kind == "rank" else 80)
	if card.kind == "unlock": return 65
	if card.kind == "evolve": return 60
	if card.kind == "rank": return 50
	return 10

## Picks the best card of the standing offer and takes it. Returns the row {tick, level, id, kind, score, offered}, or {}
## when there is no offer or the core refused the pick (then one error line is written, starting with `tag`).
## The caller prints HUD_SPELLS_PICK and hands the pick events to a recorder, as it always did.
static func pick(run: RefCounted, tag: String = "spells_pick") -> Dictionary:
	var offer: Dictionary = run.get_offer()
	if offer.is_empty() or offer.cards.is_empty(): return {}
	var primary_id := String(run.growth.snapshot().primary)
	var picked: Dictionary = offer.cards[0]
	var best := -1
	for card in offer.cards:
		var value := score(run,card,primary_id)
		if value > best: best = value; picked = card
	var row := {"tick":int(run.tick),"level":int(offer.level),"id":String(picked.id),"kind":String(picked.kind),"score":best,"offered":offer.cards.map(func(c): return String(c.id))}
	if not run.choose(offer.token,picked.id):
		push_error(tag+": the synergy pick was rejected: "+str(run.errors))
		return {}
	return row
