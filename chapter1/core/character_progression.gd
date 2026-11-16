extends RefCounted
## Stateless permanent-level rules. The document is data/character_progression.json.
## Level and points are always computed from xp and first-kill receipts, never stored.
const DEFAULT_PATH := "res://chapter1/data/character_progression.json"
const SOURCE_KEYS := ["seal_xp", "champion_xp", "boss_xp", "victory_xp"]

static func integer_(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= low and float(value) <= high

## Returns the parsed document, or {"error": reason}. Does not validate the content.
static func load_document(path := DEFAULT_PATH) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "cannot open " + path}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {"error": "not a JSON object: " + path}
	return parsed

## Empty array means the document is acceptable.
static func validate_document(doc: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not integer_(doc.get("schema_version"), 1, 1):
		errors.append("schema_version")
	if not integer_(doc.get("level_cap"), 2, 100):
		errors.append("level_cap")
		return errors
	var cap := int(doc.level_cap)
	var curve: Variant = doc.get("xp_thresholds")
	if not curve is Array or curve.size() != cap:
		errors.append("xp_thresholds length != level_cap")
	else:
		for i in curve.size():
			if not integer_(curve[i], 0, 1000000000):
				errors.append("xp_thresholds[%d] not an integer in range" % i)
			elif i == 0 and int(curve[i]) != 0:
				errors.append("xp_thresholds[0] must be 0")
			elif i > 0 and integer_(curve[i - 1], 0, 1000000000) and int(curve[i]) <= int(curve[i - 1]):
				errors.append("xp_thresholds not strictly increasing at %d" % i)
	if not integer_(doc.get("points_per_level"), 0, 10):
		errors.append("points_per_level")
	var sources: Variant = doc.get("sources")
	if not sources is Dictionary or sources.size() != SOURCE_KEYS.size():
		errors.append("sources keys")
	else:
		for key in SOURCE_KEYS:
			if not sources.has(key):
				errors.append("sources." + key + " missing")
		for key in ["seal_xp", "champion_xp"]:
			var list: Variant = sources.get(key)
			if not list is Array or list.is_empty():
				errors.append("sources." + key + " must be a non-empty array")
			else:
				for value in list:
					if not integer_(value, 0, 100000):
						errors.append("sources." + key + " value out of range")
		for key in ["boss_xp", "victory_xp"]:
			if sources.has(key) and not integer_(sources[key], 0, 100000):
				errors.append("sources." + key + " out of range")
	var rewards: Variant = doc.get("first_rewards")
	if not rewards is Dictionary or rewards.size() > 32:
		errors.append("first_rewards")
	else:
		var champions: int = sources.get("champion_xp", []).size() if sources is Dictionary and sources.get("champion_xp") is Array else 0
		for id_ in rewards:
			if not id_ is String or not integer_(rewards[id_], 1, 10):
				errors.append("first_rewards value for " + str(id_))
			elif id_ != "boss" and not (id_.begins_with("champion:") and id_.substr(9).is_valid_int() and int(id_.substr(9)) >= 0 and int(id_.substr(9)) < champions):
				errors.append("first_rewards unknown id " + id_)
	var respec: Variant = doc.get("respec")
	if not respec is Dictionary or not respec.has("essence_per_point") or not integer_(respec.essence_per_point, 0, 1000):
		errors.append("respec.essence_per_point")
	var migration: Variant = doc.get("migration")
	if not migration is Dictionary or not integer_(migration.get("xp_per_completed_run"), 0, 100000) or not integer_(migration.get("max_runs"), 0, 1000):
		errors.append("migration")
	var characters: Variant = doc.get("characters")
	if not characters is Array or characters.is_empty() or characters.size() > 3:
		errors.append("characters")
	else:
		var seen := {}
		for entry in characters:
			if not entry is Dictionary or not entry.get("id") is String or String(entry.id).is_empty() or seen.has(entry.id):
				errors.append("characters entry")
				continue
			seen[entry.id] = true
			if not entry.get("signature_skill_id") is String or String(entry.signature_skill_id).is_empty():
				errors.append("characters signature_skill_id " + String(entry.id))
			if entry.get("tree_id") != null and (not entry.tree_id is String or String(entry.tree_id).is_empty()):
				errors.append("characters tree_id " + String(entry.id))
	return errors

static func character_entry(doc: Dictionary, character_id: String) -> Dictionary:
	for entry in doc.get("characters", []):
		if entry is Dictionary and entry.get("id") == character_id:
			return entry
	return {}

## Level 1..level_cap: the last threshold that xp has reached.
static func level_for_xp(doc: Dictionary, xp: int) -> int:
	var level := 1
	var curve: Array = doc.get("xp_thresholds", [0])
	for i in curve.size():
		if xp >= int(curve[i]):
			level = i + 1
		else:
			break
	return level

## Experience needed to reach the next level from `xp`; 0 at the cap.
static func xp_for_next(doc: Dictionary, xp: int) -> int:
	var level := level_for_xp(doc, xp)
	var curve: Array = doc.get("xp_thresholds", [0])
	if level >= curve.size():
		return 0
	return int(curve[level]) - xp

## (level - 1) * points_per_level plus every distinct, known first-kill receipt.
static func points_earned(doc: Dictionary, xp: int, first_rewards: Array) -> int:
	var total := (level_for_xp(doc, xp) - 1) * int(doc.get("points_per_level", 1))
	var table: Dictionary = doc.get("first_rewards", {})
	var counted := {}
	for id_ in first_rewards:
		if id_ is String and table.has(id_) and not counted.has(id_):
			counted[id_] = true
			total += int(table[id_])
	return total

## Totals that bound one run, used by profile validation and simulations.
static func xp_bounds(doc: Dictionary) -> Dictionary:
	var sources: Dictionary = doc.get("sources", {})
	var seal := 0
	for value in sources.get("seal_xp", []):
		seal += int(value)
	var champion := 0
	for value in sources.get("champion_xp", []):
		champion += int(value)
	var boss := int(sources.get("boss_xp", 0))
	var victory := int(sources.get("victory_xp", 0))
	var curve: Array = doc.get("xp_thresholds", [0])
	var first_points := 0
	for id_ in doc.get("first_rewards", {}):
		first_points += int(doc.first_rewards[id_])
	return {
		"seal_total": seal, "champion_total": champion, "boss": boss, "victory": victory,
		"run_xp_max": seal + champion + boss + victory,
		"level_cap": int(doc.get("level_cap", 1)),
		"xp_cap": int(curve[curve.size() - 1]),
		"points_cap": (int(doc.get("level_cap", 1)) - 1) * int(doc.get("points_per_level", 1)) + first_points,
		"migration_xp_max": int(doc.get("migration", {}).get("xp_per_completed_run", 0)) * int(doc.get("migration", {}).get("max_runs", 0)),
	}
