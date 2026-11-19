extends RefCounted
## The text checks of test_core_text.gd as an observer. One object can watch a run that something else is stepping
## (golden_core.gd --text-check), so the same pilot run serves the golden replay and the text check.
## It only reads: snapshot(), objective(), stat_sheet(), get_offer() (cached while the choice is open), events.
const CORE := "res://chapter1/core/chapter_core.gd"
const PILOT := "res://chapter1/core/chapter_pilot.gd"
const MAX_TICKS := 12 * 60 * 60
## Equipment dictionary text (T3-S removes it). Matched on the path with array indices dropped.
const ALLOWED := ["inventory[].name", "inventory[].description", "items[].name", "items[].description", "pending_rewards[].name",
	"pending_rewards[].description", "events[].item.name", "events[].item.description", "equipped_items[].name", "equipped_items[].description"]
var checks := 0
var failures: Array[String] = []
var found := {}      # path -> true, equipment text allowed
var offending := {}  # path -> sample, not allowed
var seen_types := {}
var named_events := 0
var last_offer_token := ""
var card_titles_seen := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func hangul(text: String) -> bool:
	for i in text.length():
		var code := text.unicode_at(i)
		if (code >= 0xAC00 and code <= 0xD7A3) or (code >= 0x3131 and code <= 0x318E):
			return true
	return false

func walk(value: Variant, path: String) -> void:
	if value is Dictionary:
		for key in value:
			# Keys of a dictionary are ids or names of fields; a Hangul key is text too.
			if hangul(str(key)):
				offending[path + "{key}"] = str(key)
			walk(value[key], (path + "." + str(key)) if not path.is_empty() else str(key))
	elif value is Array:
		for item in value:
			walk(item, path + "[]")
	elif value is String and hangul(value):
		if ALLOWED.has(path):
			found[path] = true
		else:
			offending[path] = String(value).left(30)

## Call before the first step of one run.
func begin() -> void:
	seen_types = {}
	named_events = 0
	last_offer_token = ""
	card_titles_seen = 0

## Call after every run.step().
func observe(run: RefCounted) -> void:
	for event in run.events:
		walk(event, "events[]")
		seen_types[String(event.type)] = true
		if event.type in ["gate_opened", "chapter_champion", "ritual_started", "ritual_completed"] and event.has("name"):
			named_events += 1
	# The grace offer exists only once get_offer() is called while mode is "choice" (the pilot calls it on its next decide(),
	# and the same offer is cached, so asking here changes nothing). Walk it, the snapshot and the whole card pool once per offer.
	if run.mode == "choice":
		var offer: Dictionary = run.get_offer()
		var token := String(offer.get("token", ""))
		if token != "" and token != last_offer_token:
			last_offer_token = token
			walk(offer, "growth_offer")
			walk(run.snapshot(), "")
			for card in run.growth._eligible_cards():
				walk(card, "growth_card")
			for card in offer.get("cards", []):
				if String(card.get("title_key", "")) != "":
					card_titles_seen += 1
	if run.tick % 600 == 0:
		walk(run.snapshot(), "")
		walk(run.objective(), "objective")
		walk(run.stat_sheet(), "stat_sheet")

## Call once after the run ended (or after start() was rejected: pass error).
func finish(primary: String, run: RefCounted, error: String = "") -> void:
	check(error.is_empty(), "%s plays: %s" % [primary, error])
	if not error.is_empty():
		return
	walk(run.snapshot(), "")
	walk(run.objective(), "objective")
	check(card_titles_seen > 0, "%s: saw at least one grace card title (%d)" % [primary, card_titles_seen])
	check(run.mode == "victory", "%s reaches victory (%s at tick %d)" % [primary, run.mode, int(run.tick)])
	for type_ in ["gate_opened", "chapter_champion"]:
		check(seen_types.has(type_), "%s emitted %s" % [primary, type_])
	check(named_events == 0, "%s: zone, ritual and guardian events carry no name field" % primary)
	print("CORE_TEXT_RUN ", JSON.stringify({"primary": primary, "tick": run.tick, "mode": run.mode}))

## The whole pilot run on its own (test_core_text.gd).
func play(primary: String) -> void:
	var run: RefCounted = load(CORE).new()
	var pilot: RefCounted = load(PILOT).new()
	pilot.run = run
	if not run.start(11, primary):
		finish(primary, run, "start rejected: " + str(run.errors))
		return
	begin()
	while run.mode not in ["victory", "defeat"] and run.tick < MAX_TICKS:
		run.step(pilot.decide())
		observe(run)
	finish(primary, run)

## Checks that need no pilot run: the two ritual events made by hand and the objective() keys.
func tail() -> void:
	# The pilot never starts a ritual, so the two ritual events are made by hand: start, then finish on the next tick.
	var ritual_run: RefCounted = load(CORE).new()
	ritual_run.start(11, "chapter1.skill.frost")
	var vigil: Dictionary = ritual_run.RITUALS[0]
	ritual_run.hero.position = vigil.position
	check(ritual_run.activate_ritual(String(vigil.id)), "the vigil ritual starts next to its ring")
	var ritual_types := {}
	for event in ritual_run.events:
		walk(event, "events[]")
		ritual_types[String(event.type)] = event
	ritual_run.rituals[String(vigil.id)].progress = 25 * 60 - 1
	ritual_run.step(Vector2.ZERO)
	for event in ritual_run.events:
		walk(event, "events[]")
		ritual_types[String(event.type)] = event
	check(ritual_types.has("ritual_started") and ritual_types.has("ritual_completed"), "ritual_started and ritual_completed were emitted")
	for type_ in ["ritual_started", "ritual_completed"]:
		if ritual_types.has(type_):
			check(ritual_types[type_].has("id") and not ritual_types[type_].has("name"), "%s carries the ritual id and no name" % type_)
	var objective_keys := ["zone", "kind", "done", "total", "hp", "hp_max", "title_key", "destination", "boss_phase", "entered"]
	var probe: RefCounted = load(CORE).new()
	probe.start(11, "chapter1.skill.frost")
	var keys: Array = probe.objective().keys()
	keys.sort()
	objective_keys.sort()
	check(keys == objective_keys, "objective() has the agreed keys and no text: " + str(keys))

## The one check that spans every run: nothing outside the equipment text. Counts as one check.
func offending_check() -> void:
	check(offending.is_empty(), "no Hangul outside the equipment text: " + JSON.stringify(offending, "", false))

## What a part (one process) found, for a caller that merges several parts. Prefixed line CORE_TEXT_PART.
func part_report() -> Dictionary:
	var allowed_found: Array = found.keys()
	allowed_found.sort()
	return {"checks": checks, "failures": failures, "offending": offending, "found": allowed_found}
