extends SceneTree
## T3-L1: the core gives ids, keys and numbers, not sentences. Runs the built-in pilot (seed 11, three signature
## skills) to the end and looks at snapshot() every 600 ticks, every event of every tick, objective() and stat_sheet().
## A Hangul string anywhere outside the equipment dictionary's name and description fails. The equipment text stays
## until the schema-4 step (T3-S); the allowed paths are listed in core_text_probe.gd and reported.
## The walking itself lives in core_text_probe.gd so golden_core.gd --text-check can run it on the same pilot run as the
## golden replay (the same seed, the same pilot, the same input: no second run of the chapter).
##   --script res://chapter1/tests/test_core_text.gd            all three
##   ... -- --primary=chapter1.skill.frost                       one only
##   ... -- --tail                                               only the checks that need no pilot run; prints CORE_TEXT_PART
const PROBE := "res://chapter1/tests/core_text_probe.gd"
const PRIMARIES := ["chapter1.skill.frost", "chapter1.skill.ember", "chapter1.skill.arc"]

func _initialize() -> void:
	call_deferred("execute")

func execute() -> void:
	var primaries: Array = PRIMARIES
	var tail_only := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--primary="):
			primaries = [arg.trim_prefix("--primary=")]
		elif arg == "--tail":
			tail_only = true
	var probe: RefCounted = load(PROBE).new()
	if tail_only:
		probe.tail()
		print("CORE_TEXT_PART ", JSON.stringify(probe.part_report()))
		quit(0 if probe.failures.is_empty() else 1)
		return
	for primary in primaries:
		probe.play(String(primary))
	probe.tail()
	probe.offending_check()
	var allowed_found: Array = probe.found.keys()
	allowed_found.sort()
	print("CORE_TEXT_ALLOWED_PATHS ", JSON.stringify(allowed_found))
	print("CHAPTER1_CORE_TEXT_RESULT ", JSON.stringify({"checks": probe.checks, "failures": probe.failures, "equipment_text_paths": allowed_found}))
	quit(0 if probe.failures.is_empty() else 1)
