extends RefCounted
## The "one run" trial (S1, docs/specs/T14-slice-s1-20261125.ko.md 2.2): the ONE place that says which parked-off systems a trial of the whole
## run turns on, and with which values. The values live in chapter1/data/trial_slice.json (laid over the shipped data files, in memory only);
## this file holds structure and the check of that file, no number. The app (`--chapter1-trial=slice`), the checks, the golden cases and the
## measurement (measure_rhythm.gd --slice) all call apply(), so the run a player plays, the run a golden pins and the run a tool measures
## are the same run. The shipped data files keep their "enabled" values; nothing here writes a file.
##
## What it turns on: the rhythm and its opening (the data file's own level table, seal kills, kill burst and guardian grace, no D19 first values),
## the final boss's finale, the taste crest, the descent (the ultimate), the arc's element kit with the whole permanent tree open, and one set of
## equipment tables with the affix roll, the pity, the verdict v2 and the luck switched on together. What it keeps off: the grace block, elites,
## extras, loot_flow, the spell composition and the sustain trial (the rhythm's own trial block).
const Tuning := preload("res://chapter1/core/combat_tuning.gd")
const DescentDoc := preload("res://chapter1/core/descent.gd")
const RunSpellsDoc := preload("res://chapter1/core/run_spells.gd")
const LootTables := preload("res://chapter1/core/loot.gd")
const Kit := preload("res://chapter1/core/element_kit.gd")
const ChapterProfile := preload("res://chapter1/core/chapter_profile.gd")

const NAME := "slice"
const DOC_PATH := "res://chapter1/data/trial_slice.json"
const ROOT_KEYS := ["schema_version", "status", "tuning", "descent", "element_kit", "loot", "run_spells"]
const TUNING_KEYS := ["rhythm", "boss_finale", "taste_crest", "off"]
const RHYTHM_KEYS := ["enabled", "opening", "trial"]
const CREST_KEYS := ["beat", "at_ticks", "count", "arc_deg"]
const LOOT_KEYS := ["affix_rolls", "pity", "upgrade_verdict", "luck"]
## Blocks of combat_tuning.json that `off` may name (each has an "enabled" switch).
const OFF_BLOCKS := ["grace", "elites", "extras", "loot_flow"]

static func _keys_exact(value: Variant, names: Array) -> bool:
	if not value is Dictionary or value.size() != names.size(): return false
	for name in names:
		if not value.has(name): return false
	return true

static func _whole(value: Variant) -> bool:
	return (value is int) or (value is float and is_finite(value) and value == floor(value))

static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

## Every problem found in a trial_slice document as ONE sentence; "" when it is usable. Unknown, missing and out-of-range values are refused.
static func validate(doc: Variant) -> String:
	if not _keys_exact(doc, ROOT_KEYS): return "trial_slice: the root keys are not exactly " + ", ".join(ROOT_KEYS)
	if not _whole(doc.schema_version) or int(doc.schema_version) != 1: return "trial_slice: schema_version must be 1"
	if not doc.status is String or String(doc.status).is_empty(): return "trial_slice: status must be a sentence"
	var tuning: Variant = doc.tuning
	if not _keys_exact(tuning, TUNING_KEYS): return "trial_slice: tuning keys are not exactly " + ", ".join(TUNING_KEYS)
	if not _keys_exact(tuning.rhythm, RHYTHM_KEYS): return "trial_slice: tuning.rhythm keys are not exactly " + ", ".join(RHYTHM_KEYS)
	for key in RHYTHM_KEYS:
		if not tuning.rhythm[key] is bool: return "trial_slice: tuning.rhythm." + key + " must be true or false"
	if not tuning.boss_finale is bool: return "trial_slice: tuning.boss_finale must be true or false"
	if not tuning.rhythm.enabled and tuning.boss_finale: return "trial_slice: the finale needs the rhythm"
	var crest: Variant = tuning.taste_crest
	if not _keys_exact(crest, CREST_KEYS): return "trial_slice: tuning.taste_crest keys are not exactly " + ", ".join(CREST_KEYS)
	if not crest.beat is String or String(crest.beat).is_empty(): return "trial_slice: tuning.taste_crest.beat must name a beat"
	for key in ["at_ticks", "count", "arc_deg"]:
		if not _whole(crest[key]) or int(crest[key]) < 0: return "trial_slice: tuning.taste_crest." + key + " must be a whole number from 0"
	if not tuning.off is Array: return "trial_slice: tuning.off must be a list"
	for name in tuning.off:
		if not name is String or not name in OFF_BLOCKS: return "trial_slice: tuning.off names a block that is not one of " + ", ".join(OFF_BLOCKS)
	var descent: Variant = doc.descent
	if not _keys_exact(descent, ["enabled", "cost"]) or not descent.enabled is bool or not descent.cost is Array or descent.cost.is_empty(): return "trial_slice: descent needs enabled and a cost list"
	for amount in descent.cost:
		if not _whole(amount): return "trial_slice: descent.cost must be whole numbers"
	var kit: Variant = doc.element_kit
	if not _keys_exact(kit, ["enabled_elements", "tree"]) or not kit.enabled_elements is Array or kit.enabled_elements.is_empty(): return "trial_slice: element_kit needs enabled_elements and tree"
	for element in kit.enabled_elements:
		if not element is String or not element in ["ember", "frost", "arc"]: return "trial_slice: element_kit.enabled_elements names an unknown element"
	if not kit.tree is String or not kit.tree in ["none", "all"]: return "trial_slice: element_kit.tree must be none or all"
	if not _keys_exact(doc.loot, LOOT_KEYS): return "trial_slice: loot keys are not exactly " + ", ".join(LOOT_KEYS)
	for key in LOOT_KEYS:
		if not doc.loot[key] is bool: return "trial_slice: loot." + key + " must be true or false"
	if not doc.run_spells is bool or doc.run_spells: return "trial_slice: run_spells must be false (the kit and the composition never run together)"
	return ""

## The document at `path`, validated: {"doc": Dictionary, "error": ""} or {"doc": {}, "error": one sentence}.
static func read_document(path: String = DOC_PATH) -> Dictionary:
	var parsed: Variant = _read_json(path)
	if parsed == null: return {"doc": {}, "error": "trial_slice could not be read: " + path}
	var problem := validate(parsed)
	if not problem.is_empty(): return {"doc": {}, "error": problem}
	return {"doc": parsed, "error": ""}

## sha256 of a trial_slice file (a measurement writes it into its result so the values it ran on can be found again).
static func document_sha256(path: String = DOC_PATH) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""

## combat_tuning.json with the trial's values laid over it (the rhythm's own level table, seal kills, kill burst and guardian grace stay the data file's).
## {"doc": ..., "error": ""} or {"doc": {}, "error": one sentence}.
static func tuning_doc(slice: Dictionary = {}) -> Dictionary:
	if slice.is_empty():
		var read := read_document()
		if not String(read.error).is_empty(): return {"doc": {}, "error": read.error}
		slice = read.doc
	var base: Variant = _read_json(Tuning.DEFAULT_PATH)
	if not base is Dictionary or not base.get("rhythm") is Dictionary or not base.get("boss_finale") is Dictionary: return {"doc": {}, "error": "combat_tuning.json has no rhythm or boss_finale block"}
	var rhythm: Dictionary = base.rhythm
	if not rhythm.get("opening") is Dictionary or not rhythm.get("trial") is Dictionary or not rhythm.get("beats") is Array: return {"doc": {}, "error": "combat_tuning.json rhythm has no opening, trial or beats"}
	var rules: Dictionary = slice.tuning
	rhythm.enabled = bool(rules.rhythm.enabled)
	rhythm.opening.enabled = bool(rules.rhythm.opening)
	rhythm.trial.enabled = bool(rules.rhythm.trial)
	base.boss_finale.enabled = bool(rules.boss_finale)
	var crest: Dictionary = rules.taste_crest
	var found := false
	for beat in rhythm.beats:
		if beat is Dictionary and String(beat.get("id", "")) == String(crest.beat):
			beat["taste_crest"] = {"at_ticks": int(crest.at_ticks), "count": int(crest.count), "arc_deg": int(crest.arc_deg)}
			found = true
	if not found: return {"doc": {}, "error": "trial_slice: no beat named " + String(crest.beat)}
	for name in rules.off:
		if base.get(name) is Dictionary: base[name]["enabled"] = false
	return {"doc": base, "error": ""}

static func descent_doc(slice: Dictionary = {}) -> Dictionary:
	if slice.is_empty():
		var read := read_document()
		if not String(read.error).is_empty(): return {"doc": {}, "error": read.error}
		slice = read.doc
	var base: Variant = _read_json(DescentDoc.DEFAULT_PATH)
	if not base is Dictionary: return {"doc": {}, "error": "descent.json could not be read"}
	base.enabled = bool(slice.descent.enabled)
	base.cost = slice.descent.cost.duplicate()
	return {"doc": base, "error": ""}

static func kit_doc(slice: Dictionary = {}) -> Dictionary:
	if slice.is_empty():
		var read := read_document()
		if not String(read.error).is_empty(): return {"doc": {}, "error": read.error}
		slice = read.doc
	var base: Variant = _read_json(Kit.DEFAULT_PATH)
	if not base is Dictionary: return {"doc": {}, "error": "element_kit.json could not be read"}
	base.enabled = true
	base.enabled_elements = slice.element_kit.enabled_elements.duplicate()
	return {"doc": base, "error": ""}

## The run_spells document with "enabled": false, so a shipped file that is switched on later does not shake the trial (the kit refuses to start next to it).
static func spells_off_doc() -> Dictionary:
	var base: Variant = _read_json(RunSpellsDoc.DEFAULT_PATH)
	if not base is Dictionary: return {"doc": {}, "error": "run_spells.json could not be read"}
	base.enabled = false
	return {"doc": base, "error": ""}

## ONE set of equipment tables with the affix roll, pity, verdict v2 and luck switched on as the trial says. {"tables": RefCounted, "error": ""}.
static func loot_result(slice: Dictionary = {}) -> Dictionary:
	if slice.is_empty():
		var read := read_document()
		if not String(read.error).is_empty(): return {"tables": null, "error": read.error}
		slice = read.doc
	var tables = LootTables.new()
	if not tables.load_file(): return {"tables": null, "error": "loot.json could not be loaded: " + str(tables.errors)}
	var rules: Dictionary = slice.loot
	if not tables.set_affix_rolls(bool(rules.affix_rolls)): return {"tables": null, "error": "affix_rolls block refused"}
	if not tables.set_pity(bool(rules.pity)): return {"tables": null, "error": "pity block refused"}
	if not tables.set_verdict(bool(rules.upgrade_verdict)): return {"tables": null, "error": "upgrade_verdict block refused"}
	if not tables.set_luck(bool(rules.luck)): return {"tables": null, "error": "luck block refused"}
	return {"tables": tables, "error": ""}

static func loot_tables(slice: Dictionary = {}) -> RefCounted:
	return loot_result(slice).tables

## Hand the whole trial to a run (call before start()). "" when it worked, else one sentence; a refused piece leaves the run's earlier pieces parked
## but the caller must not start it. `slice` = a validated document ({} = the shipped trial_slice.json). A witch whose element the kit does not
## serve (the kit lists the arc only) gets the rest of the trial with the kit switched off by the core itself.
static func apply(run: RefCounted, slice: Dictionary = {}) -> String:
	if slice.is_empty():
		var read := read_document()
		if not String(read.error).is_empty(): return String(read.error)
		slice = read.doc
	else:
		var problem := validate(slice)
		if not problem.is_empty(): return problem
	var tuned := tuning_doc(slice)
	if not String(tuned.error).is_empty(): return String(tuned.error)
	if not run.set_tuning(tuned.doc): return "slice tuning refused: " + str(run.errors)
	var descent := descent_doc(slice)
	if not String(descent.error).is_empty(): return String(descent.error)
	if not run.set_descent(descent.doc): return "slice descent refused: " + str(run.errors)
	var kit := kit_doc(slice)
	if not String(kit.error).is_empty(): return String(kit.error)
	if not run.set_element_kit(kit.doc): return "slice element kit refused: " + str(run.errors)
	if not run.set_kit_open(String(slice.element_kit.tree)): return "slice kit tree refused: " + str(run.errors)
	var spells := spells_off_doc()
	if not String(spells.error).is_empty(): return String(spells.error)
	if not run.set_run_spells(spells.doc): return "slice run_spells refused: " + str(run.errors)
	var gear := loot_result(slice)
	if not String(gear.error).is_empty(): return String(gear.error)
	run.loot = gear.tables
	return ""

## Tell the profile which element trees the kit turns on, for a trial played with a save (the trial account, S1-C). Call before configure().
## This is a setting of the whole process: a check that calls it ends with ElementKit.use_override({}) and ChapterProfile.refresh_element_kit().
static func use_for_profile(slice: Dictionary = {}) -> bool:
	var kit := kit_doc(slice)
	if not String(kit.error).is_empty(): return false
	if not Kit.use_override(kit.doc): return false
	ChapterProfile.refresh_element_kit()
	return true
