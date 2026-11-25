extends RefCounted
## Check tool, not product code. Turns the element kit (D-element-trees) on for a tool's own process, the way trial_docs.gd does for the
## older parked-off systems: the shipped data files stay "enabled": false; an enabled copy is handed to the core of this process.
const Tuning := preload("res://chapter1/core/combat_tuning.gd")
const TrialDocs := preload("res://chapter1/tests/support/trial_docs.gd")
const Kit := preload("res://chapter1/core/element_kit.gd")

static func kit_document(elements: Array = ["arc"]) -> Dictionary:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Kit.DEFAULT_PATH))
	doc["enabled"] = true
	doc["enabled_elements"] = elements
	return doc

## The element kit on (arc), the whole permanent tree open (`tree`: "none", "all" or a list of card ids), "" when it worked, else one sentence.
static func enable_kit_problem(run: RefCounted, tree: Variant = "all", elements: Array = ["arc"]) -> String:
	if not run.set_element_kit(kit_document(elements)): return "element kit refused: " + str(run.errors)
	if not run.set_kit_open(tree): return "kit tree mode refused: " + str(run.errors)
	return ""

## The rhythm-c1 path (rhythm, opening, growth pace) with the kit on: the golden case "element-arc" and the measurement's kit arm.
static func enable_kit_rhythm_problem(run: RefCounted, tree: Variant = "all", with_boss_finale := false) -> String:
	var problem := TrialDocs.enable_boss_finale_problem(run) if with_boss_finale else TrialDocs.enable_rhythm_problem(run, false, true)
	if not problem.is_empty(): return problem
	return enable_kit_problem(run, tree)

## A tuning with far-off level thresholds (no card screen in the middle of a stage) and no final-level grace.
static func far_levels_problem(run: RefCounted) -> String:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Tuning.DEFAULT_PATH))
	var far: Array = []
	for i in 12: far.append(i * 90000)
	doc.xp_thresholds = far
	doc.final_level_on_boss_spawn = false
	if not run.set_tuning(doc): return "tuning refused: " + str(run.errors)
	return ""
