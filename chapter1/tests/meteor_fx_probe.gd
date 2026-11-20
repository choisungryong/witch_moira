extends SceneTree
## QA tool (never product code): drives the meteor presentation (view/fx/meteor_fx.gd) with synthetic core events in the real
## ChapterOne scene and prints what the view holds after each case. Real renderer, no --fixed-fps:
##
##   python tools/dev/godot.py --path . --resolution 1920x1080 --script res://chapter1/tests/meteor_fx_probe.gd -- \
##       --chapter1-start --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 \
##       --primary=chapter1.skill.ember [--probe-shots=_local/shots/meteor_cases]
## Prints one METEOR_CASE line per case and METEOR_PROBE {pass, fails}. The events are fed straight to effects/juice.consume
## (the core is never touched; the pilot keeps playing underneath). "pass" only means the counts below matched.
var view: Node
var seq := 90000000
var frame := 0
var started := false
var case_index := -1
var case_frame := 0
var fails: Array[String] = []
var shots_dir := ""
var state := {}
const CASES := ["single","volley8","volley16","pause","reduced_flash","reduced_motion","reset","scorch_time"]

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-shots="): shots_dir = arg.trim_prefix("--probe-shots=")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60   # the cases count frames; 60 keeps a frame close to a tick
	view = (load("res://chapter1/ChapterOne.tscn") as PackedScene).instantiate()
	root.add_child(view)

func _fx() -> RefCounted: return view.effects._meteor_fx

func _cast(count: int, fall_ticks := 24) -> void:
	var run: RefCounted = view.run
	var uid := seq
	var c: Vector2 = run.hero.position+Vector2(3.0,-4.0)
	var batch: Array = []
	for i in count:
		seq += 1
		var a := float(i)*2.4
		batch.append({"type":"meteor_cast","seq":seq,"tick":run.tick,"position":c+Vector2(cos(a),sin(a))*1.5*sqrt(float(i)),"id":seq,
			"land_tick":run.tick+fall_ticks,"radius_cm":260,"cast_uid":uid,"origin":run.hero.position,"skill_id":"chapter1.skill.ember"})
	state.batch = batch
	state.cast_uid = uid
	view.effects.consume(batch)

func _land(tick_offset := 0) -> void:
	var run: RefCounted = view.run
	var events: Array = []
	for cast in state.batch:
		seq += 1
		events.append({"type":"explosion","seq":seq,"tick":run.tick+tick_offset,"position":cast.position,"skill_id":"chapter1.skill.ember",
			"radius_cm":260,"cast_uid":state.cast_uid,"evolved":true,"meteor":cast.id})
	view.effects.consume(events)
	if view.juice != null: view.juice.consume(events)

func _counts() -> Dictionary:
	var fx := _fx()
	var balls := 0
	var marks := 0
	if fx._balls != null:
		balls = fx._balls.multimesh.visible_instance_count
		marks = fx._marks.multimesh.visible_instance_count
	return {"falls":fx._falls.size(),"balls":balls,"marks":marks,"launches":fx._launches.size()}

func _expect(ok: bool, what: String) -> void:
	if not ok: fails.append("%s: %s" % [CASES[case_index],what])

func _say(extra := {}) -> void:
	var line := _counts()
	line.merge(extra)
	print("METEOR_CASE ",CASES[case_index]," f",case_frame," ",JSON.stringify(line))

func _shot(tag: String) -> void:
	if shots_dir == "": return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://")+shots_dir)
	view.get_viewport().get_texture().get_image().save_png("%s/%s-%s.png" % [shots_dir,CASES[case_index],tag])

func _process(_delta: float) -> bool:
	var run: RefCounted = view.run
	if not started:
		if run.mode != "playing" or run.hero.is_empty() or run.tick < 120: return false
		started = true
	if frame > 3000:
		print("METEOR_PROBE ",JSON.stringify({"pass":false,"fails":["probe ran 3000 frames without finishing"]}))
		quit(1); return true
	if _fx()._balls == null:
		push_error("meteor_fx has no draw nodes (run with the dev switch --chapter1-no-meteor-fx?)")
		quit(2); return true
	frame += 1
	if case_index < 0 or case_frame > _case_length():
		case_index += 1; case_frame = 0; state = {}
		if case_index >= CASES.size():
			print("METEOR_PROBE ",JSON.stringify({"pass":fails.is_empty(),"fails":fails}))
			view.queue_free(); quit(0 if fails.is_empty() else 1); return true
	case_frame += 1
	_step_case(run)
	return false

func _case_length() -> int:
	return 260 if CASES[case_index] == "scorch_time" else 150

func _step_case(run: RefCounted) -> void:
	var fx := _fx()
	match CASES[case_index]:
		"single":
			if case_frame == 1: _cast(1)
			if case_frame == 8: _say(); _expect(_counts().falls == 1 and _counts().balls >= 1,"one fall, one ball"); _shot("fall")
			if case_frame == 20: _land()
			if case_frame == 26: _say(); _expect(_counts().marks >= 1,"scorch mark after landing"); _shot("land")
			if case_frame == 140: _say(); _expect(_counts().falls == 0,"fall list empty after the scorch")
		"volley8", "volley16":
			var n := 8 if CASES[case_index] == "volley8" else 16
			if case_frame == 1: _cast(n)
			if case_frame == 10:
				_say(); _expect(_counts().falls == n and _counts().marks == n,"%d falls, %d marks" % [n,n])
				var cast_balls: int = _counts().balls-_counts().launches
				_expect(cast_balls == 1,"one big ball for the whole cast (got %d)" % cast_balls); _shot("fall")
			if case_frame == 20: _land()
			if case_frame == 24: _say(); _shot("land")
			if case_frame == 140: _say(); _expect(_counts().falls == 0,"fall list empty")
		"pause":
			if case_frame == 1: _cast(3,120)
			if case_frame == 10: state.age = float(fx._falls[0].age)
			if case_frame == 11: run.mode = "paused"
			if case_frame == 40:
				var held: float = float(fx._falls[0].age)
				_say({"age_before":state.age,"age_paused":held}); _expect(is_equal_approx(held,state.age) or absf(held-state.age) < .03,"age frozen while paused")
				run.mode = "playing"
			if case_frame == 60:
				var moved: float = float(fx._falls[0].age)
				_say({"age_resumed":moved}); _expect(moved > state.age+.1,"age runs again after resume")
				_land()
		"reduced_flash":
			if case_frame == 1:
				if view.juice != null: view.juice.reduced_flash = true
				_cast(4)
			if case_frame == 20: _land()
			if case_frame == 24:
				var glow := -1.0
				if view.juice != null and view.juice._look_env != null: glow = view.juice._look_env.glow_intensity
				_say({"glow":glow}); _shot("land")
			if case_frame == 149 and view.juice != null: view.juice.reduced_flash = false
		"reduced_motion":
			var world: Variant = view.get("world")
			# The trauma decays within two frames, so it is read in the same step as the landing.
			if case_frame == 1: world.set_reduced_motion(true); world._camera_trauma = 0.0; _cast(2)
			if case_frame == 20:
				_land(100000)
				_say({"trauma_reduced":world._camera_trauma}); _expect(world._camera_trauma <= 0.001,"no camera trauma when motion is reduced")
				world.set_reduced_motion(false); world._camera_trauma = 0.0
			if case_frame == 23: _cast(2)
			if case_frame == 43:
				_land(200000)
				_say({"trauma_normal":world._camera_trauma}); _expect(world._camera_trauma > 0.0,"camera trauma when motion is on")
		"reset":
			if case_frame == 1: _cast(5)
			if case_frame == 5: _expect(_counts().falls == 5,"five falls before reset")
			if case_frame == 6: view.effects.reset()
			if case_frame == 8: _say(); _expect(_counts().falls == 0 and _counts().balls == 0 and _counts().marks == 0,"nothing held after reset")
		"scorch_time":
			if case_frame == 1: _cast(2)
			if case_frame == 20: _land()
			if case_frame == 21: _say()
			if case_frame == 120: _say({"note":"1.4 s after landing at 60 fps is about 84 frames"}); _expect(_counts().marks == 0,"scorch gone")
