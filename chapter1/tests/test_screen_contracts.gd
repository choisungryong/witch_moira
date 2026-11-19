extends SceneTree
## Screen contracts, from inside the engine (docs/specs/T8 5 S0-b, docs/SCREEN-DESIGN-HARNESS.ko.md 3.5 / 3.7 / 6 T-2).
## Headless. Writes only under _local/ (--out). tools/dev/screen_contract_check.py reads what this writes (--dumps=<out>, --layout-dump=<out>/layout).
##
##   python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_screen_contracts.gd -- --out=_local/t8/s0b
##
## What it does, in this order:
##   (a) every fixture (chapter1/tests/fixtures/contracts/<id>.<variant>.json; the drafts in fixtures/ui/ that carry a "screen" key
##       count too, the contracts/ one wins on the same variant) follows its schema (chapter1/tests/contracts/<id>.contract.json):
##       one check each. A fixture whose screen has no schema is counted in "unchecked" and not passed.
##   (b) when the screen file chapter1/view/hud/screens/<id>.gd exists: every fixture of the same contract_version is built into the
##       screen (apply), two frames are waited, the signals the schema names must exist on the screen, and the layout rows are written
##       to <out>/layout/<id>.<variant>.json (text colour "fc" and background "bg" for the contrast check). A fixture of another
##       version is skipped and listed ("skipped"): the draft fixtures wait for the screen of their own version.
##   (c) when the adapter chapter1/view/contracts/<id>_contract.gd exists: the contract is built from the real core for the cases below,
##       written to <out>/<id>.<case>.json, followed against the schema (requested fields may be missing), and the core must not have
##       moved (tick, mode and the growth snapshot are the same before and after build). growth_choice: the first offer of a run
##       (seed 11, three starting skills) with the spell composition off ("off_<skill>") and on ("on_<skill>"; the shipped
##       run_spells.json copied with enabled = true, chapter1/tests/support/trial_docs.gd). title: the menu with no profile
##       ("no_profile"; app_state is {}, the empty value of the shape T8 S2 will fix). A screen without an adapter is skipped and listed.
## Last line: CHAPTER1_SCREEN_CONTRACTS_RESULT {"checks":N,"failures":[...],"unchecked":N,"skipped":[...],"dumps":[...]}. Exit 1 on a failure.
## `--adapter-dir=res://...` and `--screen-dir=res://...` read stand-ins from another folder (the self test of this tool uses them).
const Schema := preload("res://chapter1/tests/support/contract_schema.gd")
const TrialDocs := preload("res://chapter1/tests/support/trial_docs.gd")
const LayoutDump := preload("res://chapter1/tests/layout_dump.gd")
const Core := preload("res://chapter1/core/chapter_core.gd")
const Pilot := preload("res://chapter1/core/chapter_pilot.gd")
const SCHEMA_DIR := "res://chapter1/tests/contracts/"
const FIXTURE_DIRS := ["res://chapter1/tests/fixtures/contracts/", "res://chapter1/tests/fixtures/ui/"]
const SKILLS := {"ember": "chapter1.skill.ember", "frost": "chapter1.skill.frost", "arc": "chapter1.skill.arc"}
const SEED := 11
const GUARD_TICKS := 30000

var adapter_dir := "res://chapter1/view/contracts/"
var screen_dir := "res://chapter1/view/hud/screens/"
var out_dir := ""
var checks := 0
var unchecked := 0
var failures: Array[String] = []
var skipped: Array[String] = []
var dumps: Array[String] = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--adapter-dir="): adapter_dir = arg.trim_prefix("--adapter-dir=")
		elif arg.begins_with("--screen-dir="): screen_dir = arg.trim_prefix("--screen-dir=")
	if not out_dir.is_empty():
		var absolute := out_dir if out_dir.is_absolute_path() else ProjectSettings.globalize_path("res://" + out_dir)
		if not ("/_local/" in absolute.replace("\\", "/") + "/"):
			print("CHAPTER1_SCREEN_CONTRACTS_ARGS ", JSON.stringify({"error": "--out must be a folder under _local/ (got %s)" % out_dir}))
			quit(2)
			return
		out_dir = absolute
		DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

func _fail(message: String) -> void:
	failures.append(message)
	push_error("test_screen_contracts: " + message)

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _frames(count: int) -> void:
	for i in count: await process_frame

func _run() -> void:
	var schemas := _load_schemas()
	var fixtures := _load_fixtures(schemas)
	for id_ in schemas:
		await _screen_part(id_, schemas[id_], fixtures.get(id_, {}))
		_adapter_part(id_, schemas[id_])
	print("CHAPTER1_SCREEN_CONTRACTS_RESULT ", JSON.stringify({"checks": checks, "failures": failures, "unchecked": unchecked, "skipped": skipped, "dumps": dumps}))
	quit(1 if not failures.is_empty() else 0)

func _load_schemas() -> Dictionary:
	var out := {}
	if not DirAccess.dir_exists_absolute(SCHEMA_DIR): return out
	for file_name in DirAccess.get_files_at(SCHEMA_DIR):
		if not file_name.ends_with(".contract.json"): continue
		var doc: Variant = _read_json(SCHEMA_DIR + file_name)
		if not doc is Dictionary or not doc.get("fields") is Dictionary or not doc.has("screen"):
			_fail("%s: not a readable schema" % file_name)
			continue
		out[String(doc.screen)] = doc
	return out

## {screen id: {variant: {"doc": contract, "path": file}}}. The contracts/ folder is read first and wins; a ui/ file counts only with a "screen" key.
func _load_fixtures(schemas: Dictionary) -> Dictionary:
	var out := {}
	for folder in FIXTURE_DIRS:
		if not DirAccess.dir_exists_absolute(folder): continue
		for file_name in DirAccess.get_files_at(folder):
			var parts := file_name.trim_suffix(".json").split(".")
			if not file_name.ends_with(".json") or parts.size() != 2: continue
			var doc: Variant = _read_json(folder + file_name)
			if not doc is Dictionary:
				if folder.ends_with("/contracts/"): _fail("%s: not a readable JSON object" % file_name)
				continue
			var in_ui: bool = folder.ends_with("/ui/")
			if in_ui and not doc.has("screen"): continue  # an older core-state seed, not a contract
			var id_: String = String(doc.screen) if in_ui else parts[0]
			if out.has(id_) and out[id_].has(parts[1]): continue  # the contracts/ one counts
			if not schemas.has(id_):
				unchecked += 1
				continue
			if not out.has(id_): out[id_] = {}
			out[id_][parts[1]] = {"doc": doc, "path": folder + file_name}
	return out

# ---- (a) and (b): fixtures, the screen ----

func _screen_part(id_: String, schema: Dictionary, fixtures: Dictionary) -> void:
	for variant in fixtures:
		checks += 1
		failures.append_array(Schema.check_document(fixtures[variant].doc, schema, "%s.%s" % [id_, variant], true))
	var screen_path := "%s%s.gd" % [screen_dir, id_]
	if not FileAccess.file_exists(screen_path):
		skipped.append("%s: no screen file yet (%s)" % [id_, screen_path.trim_prefix("res://")])
		return
	var script: GDScript = load(screen_path)
	if script == null or not script.can_instantiate():
		_fail("%s: the screen file does not load" % id_)
		return
	var version: Variant = script.get_script_constant_map().get("CONTRACT_VERSION", null)
	checks += 1
	if not _same(version, schema.get("contract_version")): _fail("%s: the screen's CONTRACT_VERSION is %s, the schema has %s" % [id_, str(version), str(schema.get("contract_version"))])
	for variant in fixtures:
		var item: Dictionary = fixtures[variant]
		var label := "%s.%s" % [id_, variant]
		if not _same(item.doc.get("contract_version"), version):
			skipped.append("%s: contract_version %s, the screen takes %s" % [label, str(item.doc.get("contract_version")), str(version)])
			continue
		var node = script.new()
		if not node is Control:
			_fail("%s: the screen is not a Control" % label)
			continue
		checks += 1
		if not node.has_method("apply"): _fail("%s: the screen has no apply(contract)" % label)
		for signal_text in schema.get("signals", []):
			checks += 1
			var signal_name := String(signal_text).get_slice("(", 0).strip_edges()
			if not node.has_signal(signal_name): _fail("%s: the screen does not declare the signal %s" % [label, signal_name])
		root.add_child(node)
		if node.has_method("apply"): node.call("apply", item.doc.duplicate(true))
		await _frames(2)
		_write_layout(id_, variant, node)
		node.queue_free()
		await _frames(1)

func _same(a: Variant, b: Variant) -> bool:
	return (a is float or a is int) and (b is float or b is int) and float(a) == float(b)

func _write_layout(id_: String, variant: String, node: Node) -> void:
	if out_dir.is_empty(): return
	var rows: Array = []
	LayoutDump.describe(node, 0, rows, true)
	var label := "%s.%s" % [id_, variant]
	var folder := out_dir.path_join("layout")
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder.path_join(label + ".json"), FileAccess.WRITE)
	if file == null:
		_fail("%s: cannot write the layout dump" % label)
		return
	file.store_string(JSON.stringify({"order": [label], "dumps": {label: rows}, "meta": {"extra": true, "note": "screen on a contract fixture, headless", "scene": id_, "variant": variant, "combat": false,
		"canvas": [root.get_visible_rect().size.x, root.get_visible_rect().size.y]}}))
	file.close()

# ---- (c): the adapter, the real core ----

func _adapter_part(id_: String, schema: Dictionary) -> void:
	var adapter_path := "%s%s_contract.gd" % [adapter_dir, id_]
	if not FileAccess.file_exists(adapter_path):
		skipped.append("%s: no adapter yet (%s)" % [id_, adapter_path.trim_prefix("res://")])
		return
	var adapter: GDScript = load(adapter_path)
	if adapter == null or not adapter.can_instantiate():
		_fail("%s: the adapter does not load" % id_)
		return
	checks += 1
	var version: Variant = adapter.get_script_constant_map().get("CONTRACT_VERSION", null)
	if not _same(version, schema.get("contract_version")): _fail("%s: the adapter's CONTRACT_VERSION is %s, the schema has %s" % [id_, str(version), str(schema.get("contract_version"))])
	match id_:
		"growth_choice":
			for skill in SKILLS:
				for spells in [false, true]:
					var run := _run_at_first_offer(SKILLS[skill], spells)
					var case_name := "%s_%s" % ["on" if spells else "off", skill]
					if run == null:
						_fail("%s.%s: the run did not reach its first growth choice" % [id_, case_name])
						continue
					_build_case(id_, case_name, adapter, schema, run, {})
		"title":
			_build_case(id_, "no_profile", adapter, schema, Core.new(), {})
		_:
			skipped.append("%s: the adapter exists but this test has no case for it" % id_)

## A run played by the built-in pilot until the core asks for the first growth choice. null when it never does.
func _run_at_first_offer(skill_id: String, spells: bool) -> RefCounted:
	var run = Core.new()
	if spells and not TrialDocs.enable_spells(run):
		_fail("the spell document was refused")
		return null
	if not run.start(SEED, skill_id): return null
	var pilot = Pilot.new()
	pilot.run = run
	var guard := 0
	while run.mode != "choice" and run.mode != "defeat" and run.mode != "victory" and guard < GUARD_TICKS:
		run.step(pilot.decide())
		guard += 1
	return run if run.mode == "choice" else null

func _build_case(id_: String, case_name: String, adapter: GDScript, schema: Dictionary, run: RefCounted, app_state: Dictionary) -> void:
	var label := "%s.%s" % [id_, case_name]
	var before := _core_state(run)
	var contract: Variant = adapter.call("build", run, app_state)
	var after := _core_state(run)
	checks += 1
	if before != after: _fail("%s: build() changed the core (tick, mode or growth state differ before and after)" % label)
	checks += 1
	failures.append_array(Schema.check_document(contract, schema, "dump " + label, false))
	if out_dir.is_empty() or not contract is Dictionary: return
	var file := FileAccess.open(out_dir.path_join(label + ".json"), FileAccess.WRITE)
	if file == null:
		_fail("%s: cannot write the contract" % label)
		return
	file.store_string(JSON.stringify(contract, " "))
	file.close()
	dumps.append(label)

## tick, mode and the growth state WITHOUT the standing offer and the draw state: run.get_offer() still draws the offer when none is
## standing (T8 3, S0-c will make it a read), which is the one change an adapter is allowed to cause until then.
func _core_state(run: RefCounted) -> String:
	var growth: Dictionary = run.growth.snapshot()
	growth.erase("offer")
	growth.erase("rng_state")
	return JSON.stringify([run.tick, run.mode, growth])
