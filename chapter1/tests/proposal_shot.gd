extends SceneTree
## Proposal renderer for the screen design harness (step 3): one proposal scene fed by contract fixtures
## (chapter1/tests/fixtures/ui/<screen>.<variant>.json), shot at the window size the process was started with.
## Like scene_shot.gd it needs a real renderer and --chapter1-profile-off, writes under _local/shots/ only, one resolution per process.
## The proposal is a script under chapter1/tests/proposals/<screen>/<name>.gd whose static make(contract) returns the screen Control.
##
##   python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/proposal_shot.gd -- \
##       --chapter1-profile-off --proposal=growth_choice/c_two_beat --fixtures=normal,long,rare --shots=_local/shots/growth-proposals/c
##
## Arguments: --proposal=<screen>/<name>  --fixtures=<a,b|all> (default all of <screen>.*.json)  --shots=<dir>
##   --strip           also (instead of the still) shoot the intro -> focus move -> confirm as a contact sheet, one frame per 0.1 s
##   --input-test      press keys on the screen (synthetic key events) and print what was accepted
##   --reduce-motion   play the intro the reduced way (one 0.12 s fade)
##   --fixture-prefix=<p>  fixture files are <p>.<name>.json (default: the screen name; the title proposals use title_v0)
##   --stage=select|title  (screens with a title state: which state the still shows; default select)
##   --strip-kind=intro|focus|confirm|title|reduced  one contact sheet of that move at --strip-step engine frames (3 = 0.05 s, 6 = 0.1 s)
## Output: <shots>/<fixture>.<W>x<H>.png and .json (scene_shot's dump format, for tools/dev/hud_layout_check.py), strip sheets
## <shots>/strip-<fixture>.<W>x<H>.png, and PROPOSAL_SHOT lines (events with times, the held time t_u).
const Kit = preload("res://chapter1/tests/proposals/growth_choice/kit.gd")
const LayoutDump = preload("res://chapter1/tests/layout_dump.gd")
const TrialDocs = preload("res://chapter1/tests/support/trial_docs.gd")
const FIXTURE_DIR := "res://chapter1/tests/fixtures/ui/"
const STRIP_COLS := 8
const STRIP_W := 400
const STRIP_H := 225

var proposal := ""
var screen := ""
var shots := ""
var fixtures: Array[String] = []
var strip := false
var strip_kind := ""
var prefix := ""
var stage := "select"
var input_test := false
var reduce := false
var step := 6
var failures: Array[String] = []
var written: Array[String] = []

func _initialize() -> void:
	var wanted := "all"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--proposal="): proposal = arg.trim_prefix("--proposal=")
		elif arg.begins_with("--fixtures="): wanted = arg.trim_prefix("--fixtures=")
		elif arg.begins_with("--shots="): shots = arg.trim_prefix("--shots=")
		elif arg == "--strip": strip = true
		elif arg == "--input-test": input_test = true
		elif arg == "--reduce-motion": reduce = true
		elif arg.begins_with("--strip-step="): step = int(arg.trim_prefix("--strip-step="))
		elif arg.begins_with("--fixture-prefix="): prefix = arg.trim_prefix("--fixture-prefix=")
		elif arg.begins_with("--stage="): stage = arg.trim_prefix("--stage=")
		elif arg.begins_with("--strip-kind="): strip_kind = arg.trim_prefix("--strip-kind=")
	var problem := _check(wanted)
	if not problem.is_empty():
		push_error("proposal_shot: " + problem)
		print("PROPOSAL_SHOT_ARGS ", JSON.stringify({"error": problem}))
		quit(2)
		return
	if not TrialDocs.tag(OS.get_cmdline_user_args()).is_empty(): print("PROPOSAL_SHOT_TRIAL ", JSON.stringify(TrialDocs.switches(OS.get_cmdline_user_args())))
	_run.call_deferred()

func _check(wanted: String) -> String:
	if not "--chapter1-profile-off" in OS.get_cmdline_user_args(): return "--chapter1-profile-off is required"
	if DisplayServer.get_name() == "headless": return "needs a real renderer: run without --headless"
	if proposal.is_empty() or not "/" in proposal: return "--proposal=<screen>/<name> is required"
	screen = proposal.get_slice("/", 0)
	if prefix.is_empty(): prefix = screen
	if not FileAccess.file_exists("res://chapter1/tests/proposals/%s.gd" % proposal): return "no such proposal: " + proposal
	if not stage in ["select", "title"]: return "--stage=%s is unknown (select, title)" % stage
	if not strip_kind.is_empty() and not strip_kind in ["intro", "focus", "confirm", "title", "reduced"]: return "--strip-kind=%s is unknown" % strip_kind
	if shots.is_empty(): return "--shots=<dir under _local/shots> is required"
	var folder := shots if shots.begins_with("res://") or shots.is_absolute_path() else "res://" + shots
	if not ("/_local/shots/" in ProjectSettings.globalize_path(folder).replace("\\", "/") + "/"): return "--shots must be under _local/shots/"
	shots = folder
	if wanted == "all":
		for f in DirAccess.get_files_at(FIXTURE_DIR):
			if f.begins_with(prefix + ".") and f.ends_with(".json"): fixtures.append(f.trim_prefix(prefix + ".").trim_suffix(".json"))
		fixtures.sort()
	else:
		for f in wanted.split(","): fixtures.append(f)
	if fixtures.is_empty(): return "no fixtures"
	return ""

func _frames(n: int) -> void:
	for i in n: await process_frame

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(shots)
	var script: GDScript = load("res://chapter1/tests/proposals/%s.gd" % proposal)
	for name_ in fixtures:
		var contract := Kit.read_json("%s%s.%s.json" % [FIXTURE_DIR, prefix, name_])
		if contract.is_empty():
			failures.append("fixture %s unreadable" % name_)
			continue
		var node: Control = script.make(contract)
		node.reduce_motion = reduce
		root.add_child(node)
		await _frames(3)
		if input_test: await _input_test(node, name_)
		elif not strip_kind.is_empty(): await _strip_kind(node, name_)
		elif strip: await _strip(node, name_)
		else: await _still(node, name_, contract)
		node.queue_free()
		await _frames(3)
	print("PROPOSAL_SHOT_RESULT ", JSON.stringify({"proposal": proposal, "written": written, "failures": failures}))
	quit(1 if not failures.is_empty() else 0)

func _stem(name_: String) -> String:
	return "%s.%dx%d" % [name_, root.size.x, root.size.y]

func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_viewport().get_texture().get_image()

func _still(node: Control, name_: String, contract: Dictionary) -> void:
	node.play_intro()
	if node.state != "ready": await node.ready_for_pick
	await _frames(30)
	if node.focus_index < 0: node.set_focus(0)
	node.set_focus(node.best_index())
	if stage == "select" and node.has_method("prepare_still"):
		node.prepare_still("select")
		await _frames(40)
	await _frames(36)
	var image := await _grab()
	var stem := _stem(name_ if stage == "select" else name_ + "." + stage)
	image.save_png(shots.path_join(stem + ".png"))
	var rows: Array = []
	LayoutDump.describe(root, 0, rows, true)
	LayoutDump.fill_bg_from_image(rows, image, root.get_visible_rect().size)  # window run: the colour under a text over a picture, from the shot
	var doc := {"order": [name_], "dumps": {name_: rows}, "meta": {"extra": true, "note": "proposal screen on a contract fixture", "scene": proposal, "variant": name_,
		"fixture": name_, "combat": false, "canvas": [root.get_visible_rect().size.x, root.get_visible_rect().size.y], "window": [root.size.x, root.size.y]}}
	var trial := TrialDocs.switches(OS.get_cmdline_user_args())
	if not trial.is_empty(): doc.meta["trial"] = trial
	var f := FileAccess.open(shots.path_join(stem + ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()
	written.append(stem)
	print("PROPOSAL_SHOT ", JSON.stringify({"proposal": proposal, "fixture": name_, "window": [root.size.x, root.size.y], "t_u": node.unlock_t,
		"events": node.events.slice(0, 8), "controls": rows.size(), "png": shots.path_join(stem + ".png")}))

## intro -> keyboard focus walks -> confirm; one frame every 6 engine frames (0.1 s at --fixed-fps 60), shrunk into a contact sheet.
func _strip(node: Control, name_: String) -> void:
	var mult := int(6 / step)
	var frames: Array[Image] = []
	var grab := func():
		var im := await _grab()
		im.resize(STRIP_W, STRIP_H, Image.INTERPOLATE_BILINEAR)
		frames.append(im)
	node.play_intro()
	var guard := 0
	while node.state == "intro" and guard < 200:
		await grab.call()
		await _frames(step)
		guard += 1
	for k in 3 * mult:
		await grab.call()
		await _frames(step)
	var other := 1 if node.cards.size() > 1 else 0
	node.set_focus(other)
	for k in 4 * mult:
		await grab.call()
		await _frames(step)
	node.set_focus(node.best_index())
	for k in 4 * mult:
		await grab.call()
		await _frames(step)
	await _frames(15)
	node.try_pick(node.best_index())
	for k in 9 * mult:
		await grab.call()
		await _frames(step)
	var rows := int(ceil(float(frames.size()) / STRIP_COLS))
	var sheet := Image.create(STRIP_COLS * STRIP_W, rows * STRIP_H, false, Image.FORMAT_RGB8)
	for i in frames.size():
		sheet.blit_rect(frames[i], Rect2i(0, 0, STRIP_W, STRIP_H), Vector2i((i % STRIP_COLS) * STRIP_W, (i / STRIP_COLS) * STRIP_H))
	var path := shots.path_join("strip-" + _stem(name_) + ".png")
	sheet.save_png(path)
	written.append(path)
	print("PROPOSAL_SHOT_STRIP ", JSON.stringify({"proposal": proposal, "fixture": name_, "frames": frames.size(), "interval_s": float(step) / 60.0, "t_u": node.unlock_t, "events": node.events, "png": path}))

## One move as a contact sheet: intro | focus (next witch, then back) | confirm | title (title -> select) | reduced (confirm with motion 0).
## `step` engine frames between frames (--strip-step=3 at --fixed-fps 60 is 0.05 s). The sheet is shrunk to 400x225 per frame, 8 columns.
func _strip_kind(node: Control, name_: String) -> void:
	var frames: Array[Image] = []
	var grab := func():
		var im := await _grab()
		im.resize(STRIP_W, STRIP_H, Image.INTERPOLATE_BILINEAR)
		frames.append(im)
	var n_for := func(seconds: float) -> int: return int(ceil(seconds * 60.0 / float(step))) + 1
	if strip_kind == "reduced" and node.has_method("set_motion"): node.set_motion(0.0)
	node.play_intro()
	if strip_kind == "intro":
		var guard := 0
		while node.state == "intro" and guard < 400:
			await grab.call()
			await _frames(step)
			guard += 1
		for k in 3:
			await grab.call()
			await _frames(step)
	else:
		if node.state != "ready": await node.ready_for_pick
		await _frames(40)
		if node.has_method("prepare_still") and strip_kind != "title": node.prepare_still("select")
		await _frames(45)
		match strip_kind:
			"focus":
				node.set_focus((node.focus_index + 1) % node.cards.size())
				for k in n_for.call(0.8): 
					await grab.call()
					await _frames(step)
				node.set_focus(node.best_index())
				for k in n_for.call(0.8):
					await grab.call()
					await _frames(step)
			"title":
				node.prepare_still("title")
				await _frames(20)
				node.prepare_still("select")
				for k in n_for.call(0.5):
					await grab.call()
					await _frames(step)
			_:
				await _frames(20)
				node.try_pick(node.best_index())
				var secs: float = float(node.confirm_len) + 0.2
				for k in n_for.call(secs):
					await grab.call()
					await _frames(step)
	var rows := int(ceil(float(frames.size()) / STRIP_COLS))
	var sheet := Image.create(STRIP_COLS * STRIP_W, rows * STRIP_H, false, Image.FORMAT_RGB8)
	for i in frames.size():
		sheet.blit_rect(frames[i], Rect2i(0, 0, STRIP_W, STRIP_H), Vector2i((i % STRIP_COLS) * STRIP_W, (i / STRIP_COLS) * STRIP_H))
	var path := shots.path_join("strip-%s-%s.png" % [strip_kind, _stem(name_)])
	sheet.save_png(path)
	written.append(path)
	print("PROPOSAL_SHOT_STRIP ", JSON.stringify({"proposal": proposal, "fixture": name_, "kind": strip_kind, "frames": frames.size(), "interval_s": float(step) / 60.0, "events": node.events, "png": path}))

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e

## Synthetic key events straight into the screen (not the real keyboard): the lock, the skip and the Space rule.
func _input_test(node: Control, name_: String) -> void:
	var log_: Array = []
	node.play_intro()
	await _frames(4)
	node._unhandled_key_input(_key(KEY_2))
	log_.append({"at": "during intro, key 2", "state_after": node.state, "picked": node.events.any(func(e): return String(e.e).begins_with("pick_"))})
	node._unhandled_key_input(_key(KEY_1))
	log_.append({"at": "right after the skip (lock 0.25 s), key 1", "state": node.state, "rejected": node.events.any(func(e): return e.e == "pick_rejected")})
	await _frames(24)
	node._unhandled_key_input(_key(KEY_SPACE))
	log_.append({"at": "Space after the lock", "state": node.state})
	node._unhandled_key_input(_key(KEY_RIGHT))
	log_.append({"at": "Right arrow", "focus": node.focus_index})
	node._unhandled_key_input(_key(KEY_ENTER))
	log_.append({"at": "Enter", "state": node.state, "events": node.events.map(func(e): return e.e)})
	await _frames(60)
	print("PROPOSAL_SHOT_INPUT ", JSON.stringify({"proposal": proposal, "fixture": name_, "steps": log_}))
