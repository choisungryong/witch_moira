extends SceneTree
## M2: the refused-save entry points of the app only act from the menu. The app script is built without
## entering the tree (no _ready), so it never reads a real save; its profile object is set up by hand.
const App = preload("res://chapter1/app/chapter_one.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)
func _initialize() -> void:
	call_deferred("execute")
## One child process of trial_state_probe.gd; its TRIAL_STATE line as a Dictionary ({} when none came).
func _probe(user_args: Array) -> Dictionary:
	var arguments: PackedStringArray = ["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://chapter1/tests/trial_state_probe.gd","--"]
	arguments.append_array(PackedStringArray(user_args))
	var output: Array = []
	OS.execute(OS.get_executable_path(),arguments,output,true)
	for line in String(output[0] if output.size() > 0 else "").split("
"):
		if line.begins_with("TRIAL_STATE "):
			var parsed: Variant = JSON.parse_string(line.trim_prefix("TRIAL_STATE "))
			if parsed is Dictionary: return parsed
	check(false,"F-4 the probe printed no TRIAL_STATE line for "+str(user_args))
	return {}

func execute() -> void:
	var app = App.new()
	app.profile.available = false
	app.profile.reject_kind = "incompatible"
	app.profile.reject_reason = "test"
	check(app.run.mode == "menu" and app.profile_rejected(),"a refused profile is reported while the run is in the menu")
	app.run.start(7)
	check(app.run.mode == "playing","a run is live")
	check(not app.play_without_save() and not app.start_fresh_profile(true) and not app.start_fresh_profile(false),"M2 no entry point acts while a run is live")
	check(not app._profile_session_off and app.profile.reject_kind == "incompatible","M2 a refused call changes nothing")
	var other = App.new()
	other.profile.available = false
	other.profile.reject_kind = "incompatible"
	other.profile.reject_reason = "test"
	check(other.play_without_save() and other._profile_session_off and not other.profile_rejected(),"from the menu play_without_save() works")
	app.free()
	other.free()
	# F-4 (TECH-REVIEW-20261120): the dev trial `--chapter1-trial=` of the app, in child processes with their own arguments
	# (the app reads its arguments from the command line, so each case is a process: trial_state_probe.gd).
	var on := _probe(["--chapter1-trial=spells,rhythm","--chapter1-profile-off"])
	check(on.get("first",{}).get("spells",false) and on.get("first",{}).get("rhythm",false),"F-4 trial with --chapter1-profile-off: spells and rhythm are on in the core")
	check(not on.get("first",{}).get("descent",true),"F-4 trial spells,rhythm leaves the descent off")
	var unsafe := _probe(["--chapter1-trial=spells,rhythm"])
	check(not unsafe.get("first",{}).get("spells",true) and not unsafe.get("first",{}).get("rhythm",true),"F-4 trial WITHOUT --chapter1-profile-off is ignored (a trial never meets the player's save)")
	var back := _probe(["--chapter1-trial=spells,rhythm","--chapter1-profile-off","--probe-fresh"])
	check(back.get("again",{}).get("spells",false) and back.get("again",{}).get("rhythm",false),"F-4 a fresh core built the way return_to_menu() builds it keeps the trial")
	var qa_off := _probe(["--chapter1-trial=spells","--chapter1-profile-off","--probe-qa-off"])
	check(qa_off.get("first",{}).get("spells",false) and not qa_off.get("again",{}).get("spells",true),"F-4 with qa_allowed = false the arguments are ignored")
	var typo := _probe(["--chapter1-trial=spel","--chapter1-profile-off"])
	check(not typo.get("first",{}).get("spells",true),"F-4 an unknown trial name turns nothing on (today it is dropped without a word: F-2)")
	print("CHAPTER1_APP_GUARD_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
