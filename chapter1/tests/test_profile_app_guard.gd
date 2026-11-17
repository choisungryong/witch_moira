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
	print("CHAPTER1_APP_GUARD_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
