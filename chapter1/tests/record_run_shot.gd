extends SceneTree
## The battle record on a REAL run: the app plays a whole run with the built-in pilot (the core is stepped by calling the
## app's own _physics_process in a loop, so the recorder reads the real events), the result window comes up, the record
## is opened with its button and shot. Not a fixture: `run_record_view` is whatever the recorder made.
##
##   python tools/dev/godot.py --fixed-fps 60 --resolution 1280x720 --path . --script res://chapter1/tests/record_run_shot.gd -- \
##       --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --end=victory --shots=_local/shots/<dir>
##   --end=defeat [--defeat-at=<tick>]   park the hero at one hit point after that tick (default 3000) until something lands
##   --primary=chapter1.skill.ember|frost|arc   (default ember)
## Output: <shots>/real_<end>_<seed>.<W>x<H>.png, the record as JSON beside it, and RECORD_RUN_SHOT lines. Exit 1 on a failure.
var view: Node
var shots := ""
var end_kind := "victory"
var defeat_at := 3000
var primary := "chapter1.skill.ember"
var seed_value := 11

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not "--chapter1-profile-off" in args or DisplayServer.get_name() == "headless":
		print("RECORD_RUN_SHOT_ARGS ",JSON.stringify({"error":"needs --chapter1-profile-off and a real renderer"}))
		quit(2)
		return
	for arg in args:
		if arg.begins_with("--shots="): shots = arg.trim_prefix("--shots=")
		elif arg.begins_with("--end="): end_kind = arg.trim_prefix("--end=")
		elif arg.begins_with("--defeat-at="): defeat_at = int(arg.trim_prefix("--defeat-at="))
		elif arg.begins_with("--primary="): primary = arg.trim_prefix("--primary=")
		elif arg.begins_with("--chapter1-seed="): seed_value = int(arg.trim_prefix("--chapter1-seed="))
	var folder := shots if shots.begins_with("res://") else "res://"+shots
	if shots.is_empty() or not ("/_local/shots/" in ProjectSettings.globalize_path(folder).replace("\\","/")+"/") or not end_kind in ["victory","defeat"]:
		print("RECORD_RUN_SHOT_ARGS ",JSON.stringify({"error":"--shots=<dir under _local/shots> and --end=victory|defeat are required"}))
		quit(2)
		return
	shots = folder
	view = (load("res://chapter1/ChapterOne.tscn") as PackedScene).instantiate()
	if view.get_script() == null or view.get("run") == null:
		push_error("ChapterOne failed to load its script; see the errors above")
		quit(3)
		return
	root.add_child(view)
	_run.call_deferred()

func _frames(count: int) -> void:
	for i in count: await process_frame

func _find_button(node: Node, name_: String) -> Button:
	if node is Button and node.name == name_: return node
	for child in node.get_children():
		var found := _find_button(child,name_)
		if found != null: return found
	return null

func _run() -> void:
	await _frames(5)
	DirAccess.make_dir_recursive_absolute(shots)
	var hud = view.hud
	view.start_run(primary)
	var run: RefCounted = view.run
	var parked := false
	var guard := 0
	# The same call the engine makes every physics frame; the app steps the core and hands the events to the recorder.
	while run.mode not in ["victory","defeat"] and guard < 60000:
		guard += 1
		if end_kind == "defeat" and run.tick >= defeat_at:
			view._pilot = false
			parked = true
		if parked and run.mode == "playing" and run.hero.hp_raw > 1: run.hero.hp_raw = 1
		view._physics_process(1.0/60.0)
	print("RECORD_RUN_SHOT ",JSON.stringify({"phase":"ended","mode":run.mode,"tick":run.tick,"kills":run.kills,"record_ready":bool(view.run_record_view.get("ready",false)),"hud_has_record":hud.has_run_record()}))
	for i in 600:
		await process_frame
		if hud.overlay.visible: break
	await _frames(20)
	var ok: bool = hud.overlay.visible and hud.has_run_record()
	var button := _find_button(hud.modal,"CombatRecord")
	if ok and button != null:
		button.emit_signal("pressed")
		await _frames(15)
	ok = ok and hud.combat_record_open()
	var size := root.size
	var stem := "real_%s_%d.%dx%d" % [end_kind,seed_value,size.x,size.y]
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(shots.path_join(stem+".png"))
	var file := FileAccess.open(shots.path_join(stem+".record.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(view.run_record_view,"  "))
	file.close()
	var layout := preload("res://chapter1/tests/layout_dump.gd")
	var rows: Array = []
	layout.describe(root,0,rows,true)
	var label := "real_"+end_kind
	var dump := FileAccess.open(shots.path_join(stem+".json"),FileAccess.WRITE)
	dump.store_string(JSON.stringify({"order":[label],"dumps":{label:rows},"meta":{"extra":true,"note":"real run","scene":"combat_record","variant":end_kind,"combat":false,
		"canvas":[root.get_visible_rect().size.x,root.get_visible_rect().size.y],"window":[root.size.x,root.size.y]}}))
	dump.close()
	print("RECORD_RUN_SHOT ",JSON.stringify({"phase":"shot","ok":ok,"png":shots.path_join(stem+".png"),"skills":view.run_record_view.get("skills",[]).size(),"picks":view.run_record_view.get("picks",[]).size()}))
	quit(0 if ok else 1)
