extends RefCounted
## Check tool, not product code. The ONE place where a tool turns a parked-off system on for its own process, and where it
## names which test switches a capture or dump was made with (TECH-REVIEW-20261120 F-1 and F-5, docs/specs/T8 S0-b).
## Nothing here changes a data file: the shipped documents stay "enabled": false; an enabled copy is handed to the core of this
## process (set_run_spells / set_tuning / set_descent) before the run starts. The app does the same for `--chapter1-trial=...`
## (chapter1/app/chapter_one.gd `_apply_trial`); a tool that has the app should pass that argument instead of calling this.
## Do not write "the document with enabled = true" a second time anywhere else: call these.
const Tuning := preload("res://chapter1/core/combat_tuning.gd")
const RunSpellsDoc := preload("res://chapter1/core/run_spells.gd")
const DescentDoc := preload("res://chapter1/core/descent.gd")
const TrialPace := preload("res://chapter1/app/trial_pace.gd")

## The names `--chapter1-trial=` knows (chapter_one.gd `_apply_trial`). Anything else is a typo that the app drops without a word.
const TRIAL_NAMES := ["spells", "rhythm", "descent", "pace"]
## Other arguments that change what a capture shows, listed in the switch list so a capture says it (name -> what it does).
const SWITCH_ARGS := {"--run-spells=on": "spells (tool)", "--chapter1-opening=returning": "opening=returning", "--chapter1-no-juice": "no-juice"}

static func _read(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

## The shipped run_spells.json with "enabled": true, handed to the core. "" when it worked, else one sentence.
static func enable_spells_problem(run: RefCounted) -> String:
	var doc: Variant = _read(RunSpellsDoc.DEFAULT_PATH)
	if not doc is Dictionary: return "run_spells.json could not be read"
	doc["enabled"] = true
	if not run.set_run_spells(doc): return "run_spells document refused: " + str(run.errors)
	return ""

static func enable_spells(run: RefCounted) -> bool:
	return enable_spells_problem(run).is_empty()

## combat_tuning.json with the rhythm and its opening on (what `--chapter1-trial=rhythm` does). `with_trial_arena` also turns the
## rhythm's own trial block on (measure_rhythm.gd does; the app does not). `with_pace` adds the first growth-pace values of D19 C1 (what
## `--chapter1-trial=pace` does). "" when it worked, else one sentence.
static func enable_rhythm_problem(run: RefCounted, with_trial_arena := false, with_pace := false) -> String:
	var doc: Variant = _read(Tuning.DEFAULT_PATH)
	if not doc is Dictionary or not doc.get("rhythm") is Dictionary: return "combat_tuning.json has no rhythm block"
	doc["rhythm"]["enabled"] = true
	if with_trial_arena and doc["rhythm"].get("trial") is Dictionary: doc["rhythm"]["trial"]["enabled"] = true
	if doc["rhythm"].get("opening") is Dictionary: doc["rhythm"]["opening"]["enabled"] = true
	if with_pace: TrialPace.apply(doc)
	if not run.set_tuning(doc): return "rhythm document refused: " + str(run.errors)
	return ""

static func enable_descent_problem(run: RefCounted) -> String:
	var doc: Variant = _read(DescentDoc.DEFAULT_PATH)
	if not doc is Dictionary: return "descent.json could not be read"
	doc["enabled"] = true
	if not run.set_descent(doc): return "descent document refused: " + str(run.errors)
	return ""

## The `--chapter1-trial=` parts of an argument list, in the order given. Empty when the argument is absent.
static func trial_parts(args: PackedStringArray) -> Array[String]:
	var parts: Array[String] = []
	for arg in args:
		if arg.begins_with("--chapter1-trial="):
			parts.clear()
			for part in arg.trim_prefix("--chapter1-trial=").split(",", false): parts.append(part.strip_edges())
	return parts

## Which test switches are on in this process, as the list a capture, dump or recording must carry: "trial:spells", "trial:rhythm",
## "trial:?spel" (a name the app does not know: it would have been dropped silently), "spells (tool)", "no-juice", ...
## `--chapter1-trial=` counts only together with `--chapter1-profile-off`, as in the app (without it the app ignores the argument,
## which the list says as "trial-ignored").
static func switches(args: PackedStringArray) -> Array[String]:
	var out: Array[String] = []
	var parts := trial_parts(args)
	var armed := "--chapter1-profile-off" in args
	for part in parts:
		if not armed: out.append("trial-ignored:" + part)
		elif part in TRIAL_NAMES: out.append("trial:" + part)
		else: out.append("trial:?" + part)
	for key in SWITCH_ARGS:
		if key in args: out.append(String(SWITCH_ARGS[key]))
	return out

## A one-line tag for a capture header or a console line: "" when no switch is on (so a default run prints nothing new).
static func tag(args: PackedStringArray) -> String:
	var list := switches(args)
	return "" if list.is_empty() else "[" + ", ".join(list) + "]"
