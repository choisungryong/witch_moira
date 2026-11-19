extends SceneTree
## Prints what the app's `--chapter1-trial=` handling (chapter_one.gd `_apply_trial`) did to the core, for the arguments this process got.
## Used by test_profile_app_guard.gd, which starts it four times with different arguments (TECH-REVIEW-20261120 F-4). The app script is built
## without entering the tree (no _ready), so it never reads a real save.
##   --probe-qa-off   after the first report: qa_allowed = false, a fresh core, `_apply_trial()` again (the app ignores test arguments then)
##   --probe-fresh    after the first report: a fresh core and `_apply_trial()` again (what return_to_menu() does, line for line)
const App = preload("res://chapter1/app/chapter_one.gd")

func _initialize() -> void:
	call_deferred("go")

func _state(app) -> Dictionary:
	app.run.start(7)
	return {"spells": not app.run.spells.is_empty(), "rhythm": bool(app.run.tuning.get("rhythm", {}).get("enabled", false)), "descent": not app.run.descent.is_empty()}

func go() -> void:
	var app = App.new()
	var out := {"first": _state(app)}
	var args := OS.get_cmdline_user_args()
	if "--probe-qa-off" in args or "--probe-fresh" in args:
		if "--probe-qa-off" in args: app.qa_allowed = false
		app.run = app.run.get_script().new()
		app._apply_trial()
		out["again"] = _state(app)
	print("TRIAL_STATE ", JSON.stringify(out))
	app.free()
	quit(0)
