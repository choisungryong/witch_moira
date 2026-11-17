extends SceneTree
## T3-L1: the core gives ids, keys and numbers, not sentences. Runs the built-in pilot (seed 11, three signature
## skills) to the end and looks at snapshot() every 600 ticks, every event of every tick, objective() and stat_sheet().
## A Hangul string anywhere outside the equipment dictionary's name and description fails. The equipment text stays
## until the schema-4 step (T3-S); the allowed paths are listed here and reported.
##   --script res://chapter1/tests/test_core_text.gd            all three
##   ... -- --primary=chapter1.skill.frost                       one only
const CORE := "res://chapter1/core/chapter_core.gd"
const PILOT := "res://chapter1/core/chapter_pilot.gd"
const PRIMARIES := ["chapter1.skill.frost", "chapter1.skill.ember", "chapter1.skill.arc"]
const MAX_TICKS := 12 * 60 * 60
## Equipment dictionary text (T3-S removes it). Matched on the path with array indices dropped.
const ALLOWED := ["inventory[].name", "inventory[].description", "items[].name", "items[].description", "pending_rewards[].name",
	"pending_rewards[].description", "events[].item.name", "events[].item.description", "equipped_items[].name", "equipped_items[].description"]
var checks := 0
var failures: Array[String] = []
var found := {}      # path -> true, equipment text allowed
var offending := {}  # path -> sample, not allowed

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func _initialize() -> void:
	call_deferred("execute")

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

func play(primary: String) -> Dictionary:
	var run: RefCounted = load(CORE).new()
	var pilot: RefCounted = load(PILOT).new()
	pilot.run = run
	if not run.start(11, primary):
		return {"error": "start rejected: " + str(run.errors)}
	var seen_types := {}
	var named_events := 0
	while run.mode not in ["victory", "defeat"] and run.tick < MAX_TICKS:
		run.step(pilot.decide())
		for event in run.events:
			walk(event, "events[]")
			seen_types[String(event.type)] = true
			if event.type in ["gate_opened", "chapter_champion", "ritual_started", "ritual_completed"] and event.has("name"):
				named_events += 1
		if run.tick % 600 == 0:
			walk(run.snapshot(), "")
			walk(run.objective(), "objective")
			walk(run.stat_sheet(), "stat_sheet")
	walk(run.snapshot(), "")
	walk(run.objective(), "objective")
	var objective: Dictionary = run.objective()
	return {"tick": run.tick, "mode": run.mode, "types": seen_types, "named_events": named_events, "objective_keys": objective.keys()}

func execute() -> void:
	var primaries: Array = PRIMARIES
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--primary="):
			primaries = [arg.trim_prefix("--primary=")]
	for primary in primaries:
		var result := play(String(primary))
		check(not result.has("error"), "%s plays: %s" % [primary, str(result.get("error", ""))])
		if result.has("error"):
			continue
		check(result.mode == "victory", "%s reaches victory (%s at tick %d)" % [primary, result.mode, int(result.tick)])
		for type_ in ["gate_opened", "chapter_champion"]:
			check(result.types.has(type_), "%s emitted %s" % [primary, type_])
		check(int(result.named_events) == 0, "%s: zone, ritual and guardian events carry no name field" % primary)
		print("CORE_TEXT_RUN ", JSON.stringify({"primary": primary, "tick": result.tick, "mode": result.mode}))
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
	check(offending.is_empty(), "no Hangul outside the equipment text: " + JSON.stringify(offending, "", false))
	var objective_keys := ["zone", "kind", "done", "total", "hp", "hp_max", "title_key", "destination", "boss_phase", "entered"]
	var probe: RefCounted = load(CORE).new()
	probe.start(11, "chapter1.skill.frost")
	var keys: Array = probe.objective().keys()
	keys.sort()
	objective_keys.sort()
	check(keys == objective_keys, "objective() has the agreed keys and no text: " + str(keys))
	var allowed_found: Array = found.keys()
	allowed_found.sort()
	print("CORE_TEXT_ALLOWED_PATHS ", JSON.stringify(allowed_found))
	print("CHAPTER1_CORE_TEXT_RESULT ", JSON.stringify({"checks": checks, "failures": failures, "equipment_text_paths": allowed_found}))
	quit(0 if failures.is_empty() else 1)
