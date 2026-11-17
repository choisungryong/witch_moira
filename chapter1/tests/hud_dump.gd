extends SceneTree
## Records the HUD's Control tree at fixed moments of a deterministic pilot run.
## Two HUD implementations are equivalent when their dumps are identical.
## Run inside the dev stage (imports are needed), headless with a fixed frame rate:
##
##   godot --headless --fixed-fps 60 --path <stage> --script res://chapter1/tests/hud_dump.gd -- \
##       --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --dump=<file.json>
##
## Optional: --scene=<file.json> also records every 3D node (transforms, meshes, multimesh
## instances, animation state) so world, actor and effect presenters can be compared too.
## G1 P4 additions (they never change the earlier moments or their order):
##   --profile-fixture=empty|l8   run on an isolated profile under res://_local/ (needs --chapter1-profile-off so the
##                                user's own save is never opened; the dump reconfigures view.profile on its own path).
##                                l8 = frost witch at Lv 8 with 6 points invested and 2 free.
##   --profile-tag=<name>         file name of that isolated profile (default "dump")
##   --tree-shots                 menu -> skill tree flow only (no run): menu, menu-frost, tree-open, tree-staged,
##                                tree-committed, menu-after, tree-reopened. Prints TREE_FLOW lines.
##   --result-mock                skip the long run: start a run, grant some progress, force "victory" and save,
##                                then dump the result window (for quick layout work; the real run is the reference).
## A2 addition (opt-in, so the default moment list is untouched):
##   --notice-shots               also dump "discovery-notice" the first time the first-gear notice is on screen
## D4-U / D5-U additions (opt-in; the default moment list is untouched):
##   --flow-shots=abandon|defeat|quit   run-flow screens. abandon: menu, flow-paused, flow-abandon-confirm,
##                                flow-end-abandon-result, flow-menu-returned, flow-playing-after-return-120.
##                                defeat (with --defeat-at=<tick>, default 1200): flow-defeat-0.5s, flow-defeat-r-blocked,
##                                flow-defeat-result. quit: press the menu's quit button (process ends with code 0).
##                                Each moment also prints a FLOW line {mode, primary, seed, abandoned, tick}.
##   --profile-fixture=rejected   an isolated profile file whose gear fails validation (a stat is changed by hand), plus journal
##                                copies, under res://_local/shots/ui-g1p4/profiles/<tag>/. The app is put on its refused-save path.
##                                Moments: profile-rejected-menu, profile-rejected-fresh, profile-rejected-notice-closed,
##                                profile-rejected-after-play, profile-rejected-nosave-playing-120 (or profile-rejected-result
##                                with --result-mock). Prints HUD_DUMP_REJECT lines and HUD_DUMP_FILES (sha256 of every file).
##   --reject-choice=play|fresh   which way the rejected flow ends (fresh = continue from the newest readable journal copy).
## Normal runs now add an "end-<mode>-result" moment after the existing end moment.
## Optional: --until=<tick> stops early; --primary=<skill id>; --shots=<dir> also saves a
## screenshot per moment (needs a real renderer, so run without --headless).
var view: Node
var dumps: Dictionary = {}
var order: Array[String] = []
var out_path := ""
var primary := "chapter1.skill.frost"
var until_tick := 0
var shots_dir := ""
var scene_path := ""
var scenes: Dictionary = {}
var frame := 0
var step := 0
var choice_dumps := 0
var done_marks: Dictionary = {}
var unworn_since: Dictionary = {}
var end_frames := -1
var profile_fixture := ""
var profile_tag := "dump"
var tree_shots := false
var result_mock := false
var choice_wait := -1
var notice_shots := false
var flow_log: Array = []
var flow_shots := ""
var defeat_at := 1200
var reject_choice := "play"
var rj_stage := 0
var rj_next := 0
var rj_tabs := 0
var rj_files_before: Dictionary = {}
var rj_folder := ""
var fl_stage := 0
var fl_next := 0
var fl_frame0 := 0
var fl_before: Dictionary = {}
const ProfileScript := preload("res://chapter1/core/chapter_profile.gd")
const FROST_ID := "chapter1.character.frost"
const FIXTURE_RANKS := {"witch.frost.needle":3,"witch.frost.volley":1,"witch.frost.rime":2}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dump="): out_path = arg.trim_prefix("--dump=")
		elif arg.begins_with("--primary="): primary = arg.trim_prefix("--primary=")
		elif arg.begins_with("--until="): until_tick = int(arg.trim_prefix("--until="))
		elif arg.begins_with("--shots="): shots_dir = arg.trim_prefix("--shots=")
		elif arg.begins_with("--scene="): scene_path = arg.trim_prefix("--scene=")
		elif arg.begins_with("--profile-fixture="): profile_fixture = arg.trim_prefix("--profile-fixture=")
		elif arg.begins_with("--profile-tag="): profile_tag = arg.trim_prefix("--profile-tag=")
		elif arg == "--tree-shots": tree_shots = true
		elif arg == "--result-mock": result_mock = true
		elif arg == "--notice-shots": notice_shots = true
		elif arg.begins_with("--flow-shots="): flow_shots = arg.trim_prefix("--flow-shots=")
		elif arg.begins_with("--defeat-at="): defeat_at = int(arg.trim_prefix("--defeat-at="))
		elif arg.begins_with("--reject-choice="): reject_choice = arg.trim_prefix("--reject-choice=")
	var scene: PackedScene = load("res://chapter1/ChapterOne.tscn")
	view = scene.instantiate()
	# A script that failed to compile leaves a bare node: stop instead of spinning.
	if view.get_script() == null or view.get("run") == null:
		push_error("ChapterOne failed to load its script; see the errors above")
		print("HUD_DUMP_RESULT ",JSON.stringify({"error":"scene_script_failed"}))
		quit(3)
		return
	root.add_child(view)
	_setup_profile()

## Isolated profile for the growth screens. Only ever a file under res://_local/; the user's own save is not opened
## because the caller keeps --chapter1-profile-off (the view's own configure() is skipped then).
func _setup_profile() -> void:
	if profile_fixture.is_empty(): return
	if profile_fixture == "rejected":
		_setup_rejected()
		return
	var folder := "res://_local/shots/ui-g1p4/profiles"
	DirAccess.make_dir_recursive_absolute(folder)
	var listing := DirAccess.open(folder)
	if listing != null:
		for file_name in listing.get_files():
			if file_name.begins_with(profile_tag+".") and file_name.ends_with(".json"): listing.remove(file_name)
	var profile = view.profile
	if not profile.configure(folder.path_join(profile_tag+".json"),true):
		push_error("isolated profile failed: "+String(profile.error))
		return
	if profile_fixture == "l8":
		for i in 4:
			var progress := {"character_id":FROST_ID,"xp_gained":1000,"first_kills":["champion:0"] if i == 0 else []}
			if not profile.record_run("fixture-%d" % i,[],[],false,0,progress): push_error("fixture run failed: "+String(profile.error))
		if not profile.commit_tree(FROST_ID,FIXTURE_RANKS): push_error("fixture tree failed: "+String(profile.error))
	view._sync_profile("저장 준비")
	print("HUD_DUMP_PROFILE ",JSON.stringify({"fixture":profile_fixture,"path":profile.path,"view":profile.character_view(FROST_ID)}))

func _wipe_folder(folder: String) -> void:
	var listing := DirAccess.open(folder)
	if listing == null: return
	for file_name in listing.get_files(): listing.remove(file_name)

## sha256 of every file in a folder (file name -> first 16 hex characters).
func _file_hashes(folder: String) -> Dictionary:
	var out := {}
	var listing := DirAccess.open(folder)
	if listing == null: return out
	for file_name in listing.get_files(): out[file_name] = FileAccess.get_sha256(folder.path_join(file_name)).left(16)
	return out

## D5-U fixture: a real saved profile (so its journal copies are real), then the newest file gets one gear stat changed by
## hand. The reader refuses it; the journal copies stay readable. Only ever under res://_local/.
func _setup_rejected() -> void:
	rj_folder = "res://_local/shots/ui-g1p4/profiles/"+profile_tag
	DirAccess.make_dir_recursive_absolute(rj_folder)
	_wipe_folder(rj_folder)
	var main := rj_folder+"/profile.json"
	var pointer := rj_folder+"/active.json"
	var tables: RefCounted = ProfileScript.loot()
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var maker = ProfileScript.new()
	var ok: bool = maker.configure(main,true,"","",pointer)
	var unique: Dictionary = tables.make_unique("winter_heart",12)
	var magic: Dictionary = tables.roll_item(rng,12,"magic","weapon")
	var rare: Dictionary = tables.roll_item(rng,12,"rare","head")
	ok = ok and maker.record_run("fixture-a",[unique,magic,rare],[],false,10) and maker.select_item(1)
	ok = ok and maker.record_run("fixture-b",[],[],false,20)
	if not ok: push_error("rejected fixture could not be written: "+String(maker.error))
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(main))
	var stats: Dictionary = doc.items[1].item.stats
	var key: String = stats.keys()[0]
	stats[key] = int(stats[key])+777
	var handle := FileAccess.open(main,FileAccess.WRITE)
	handle.store_string(JSON.stringify(doc,"  ")); handle.close()
	var profile = view.profile
	var loaded: bool = profile.configure(main,true,"","",pointer)
	# The app skips its own profile on --chapter1-profile-off; here the refused path is the thing under test.
	view._profile_off = false
	view._sync_profile(String(profile.error))
	rj_files_before = _file_hashes(rj_folder)
	print("HUD_DUMP_REJECT ",JSON.stringify({"phase":"fixture","configure":loaded,"available":profile.available,"kind":profile.reject_kind,"reason":profile.reject_reason,"resume":profile.resume_info(),"files":rj_files_before}))

func _describe(node: Node, depth: int, rows: Array) -> void:
	if node is Control:
		var c: Control = node
		var row := {"d":depth,"class":c.get_class(),"name":String(c.name),"visible":c.is_visible_in_tree(),
			"x":snappedf(c.global_position.x,.01),"y":snappedf(c.global_position.y,.01),"w":snappedf(c.size.x,.01),"h":snappedf(c.size.y,.01),
			"modulate":c.modulate.to_html(),"tooltip":c.tooltip_text}
		if c is Label or c is Button or c is RichTextLabel or c is LineEdit: row.text = String(c.get("text"))
		if c is BaseButton: row.disabled = c.disabled
		if c is Range: row.value = snappedf(c.value,.001); row.max = snappedf(c.max_value,.001)
		if c is TextureRect: row.texture = c.texture.resource_path if c.texture != null else ""
		rows.append(row)
	for child in node.get_children():
		_describe(child,depth+1,rows)

func _vec(v: Vector3) -> Array:
	return [snappedf(v.x,.001),snappedf(v.y,.001),snappedf(v.z,.001)]

func _xform(t: Transform3D) -> Array:
	return [_vec(t.origin),_vec(t.basis.x),_vec(t.basis.y),_vec(t.basis.z)]

func _describe3d(node: Node, depth: int, rows: Array) -> void:
	if node is Node3D:
		var n: Node3D = node
		var row := {"d":depth,"class":n.get_class(),"name":String(n.name),"visible":n.is_visible_in_tree(),"t":_xform(n.global_transform)}
		if n is MultiMeshInstance3D and n.multimesh != null:
			var mm: MultiMesh = n.multimesh
			var shown := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			row.instances = mm.instance_count; row.shown = shown
			var sample: Array = []
			for i in mini(shown,24):
				var entry: Array = [_xform(mm.get_instance_transform(i))]
				if mm.use_colors: entry.append(mm.get_instance_color(i).to_html())
				if mm.use_custom_data: entry.append(mm.get_instance_custom_data(i).to_html())
				sample.append(entry)
			row.sample = sample
		if n is GeometryInstance3D:
			var material: Material = n.material_override
			row.material = "" if material == null else material.get_class()
			if material is ShaderMaterial and material.shader != null: row.shader = material.shader.resource_path
		if n is MeshInstance3D and n.mesh != null:
			row.mesh = n.mesh.get_class(); row.surfaces = n.mesh.get_surface_count()
		if n is Label3D: row.text = n.text; row.modulate = n.modulate.to_html()
		if n is Light3D: row.energy = snappedf(n.light_energy,.001); row.color = n.light_color.to_html()
		if n is Camera3D: row.fov = snappedf(n.fov,.01); row.size = snappedf(n.size,.01)
		rows.append(row)
	elif node is AnimationPlayer:
		rows.append({"d":depth,"class":"AnimationPlayer","name":String(node.name),"clip":String(node.current_animation),"at":snappedf(node.current_animation_position,.001) if node.current_animation != "" else 0.0})
	for child in node.get_children():
		_describe3d(child,depth+1,rows)

func _dump(label: String) -> void:
	if not scene_path.is_empty():
		var nodes: Array = []
		_describe3d(root,0,nodes)
		scenes[label] = nodes
		print("SCENE_DUMP ",JSON.stringify({"label":label,"nodes":nodes.size(),"tick":view.run.tick,"hash":JSON.stringify(nodes).sha256_text().left(16)}))
	var rows: Array = []
	_describe(root,0,rows)
	dumps[label] = rows
	order.append(label)
	if not shots_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(shots_dir)
		var image := root.get_viewport().get_texture().get_image()
		if image != null: image.save_png(shots_dir.path_join("%02d-%s.png" % [order.size(),label]))
	var visible := 0
	for row in rows:
		if row.visible: visible += 1
	print("HUD_DUMP ",JSON.stringify({"label":label,"controls":rows.size(),"visible":visible,"tick":view.run.tick,"mode":view.run.mode,"hash":JSON.stringify(rows).sha256_text().left(16)}))

func _mark(key: String) -> bool:
	if done_marks.has(key): return false
	done_marks[key] = true
	return true

func _process(_delta: float) -> bool:
	if view == null or not view.is_inside_tree(): return true
	frame += 1
	var run: RefCounted = view.run
	if tree_shots:
		return _tree_flow()
	if profile_fixture == "rejected":
		return _reject_flow()
	if flow_shots != "":
		return _run_flow()
	if result_mock and step < 90:
		return _mock_result()
	if notice_shots and step >= 1 and run.mode == "playing" and view.hud._discovery.visible and view.hud._discovery.modulate.a > .95 and _mark("discovery-notice"): _dump("discovery-notice")
	match step:
		0:
			if frame == 5:
				_dump("menu")
				view.hud.stash_open = true; view.hud.invalidate()
			elif frame == 8:
				_dump("stash")
				view.hud.stash_open = false; view.hud.invalidate()
			elif frame == 11:
				view.start_run(primary); step = 1
		1:
			_choice_moment(run)
			if run.tick >= 120 and _mark("p120"): _dump("playing-120")
			if run.tick >= 900 and run.mode == "playing" and _mark("inv"):
				view.open_equipment(); step = 2; frame = 0
		2:
			if frame == 3: _dump("inventory")
			elif frame == 4: view.close_equipment(); step = 3
		3:
			_choice_moment(run)
			if run.tick >= 1500 and run.mode == "playing" and _mark("pause"):
				view.toggle_pause(); step = 4; frame = 0
		4:
			if frame == 3: _dump("paused")
			elif frame == 4: view.toggle_pause(); step = 5; frame = 0
		5:
			step = 6
		6:
			# Show the better-item prompt once a bag item is not worn (presentation only).
			if not done_marks.has("offer") and run.mode == "playing":
				for item in run.inventory:
					if not run.equip_slot_of(int(item.uid)).is_empty() or not run.can_equip(item): continue
					# The pilot wears a better pickup on the next tick; wait for one it leaves in the bag.
					if not unworn_since.has(item.uid): unworn_since[item.uid] = frame
					if frame-int(unworn_since[item.uid]) >= 30:
						var data: Dictionary = run.compare_item(int(item.uid))
						view.hud.offer_upgrade(data.candidate,data.equipped,data.slot)
						done_marks["offer"] = frame
						print("HUD_DUMP_OFFER ",JSON.stringify({"tick":run.tick,"uid":item.uid,"name":item.name,"prompt_uid":view.hud.upgrade_uid})); break
			elif done_marks.has("offer") and frame == int(done_marks["offer"])+4 and _mark("offer-shot"):
				print("HUD_DUMP_OFFER_CHECK ",JSON.stringify({"tick":run.tick,"prompt_uid":view.hud.upgrade_uid}))
				if view.hud.upgrade_uid >= 0: _dump("upgrade-prompt")
				view.hud.clear_upgrade()
			if run.tick >= 2400 and _mark("p2400"): _dump("playing-2400")
			if run.tick >= 9000 and _mark("p9000"): _dump("playing-9000")
			if run.tick >= 16000 and _mark("p16000"): _dump("playing-16000")
			if run.mode in ["victory","defeat"] and end_frames < 0: end_frames = 0
			if until_tick > 0 and run.tick >= until_tick and end_frames < 0: end_frames = 20
	if end_frames >= 0:
		end_frames += 1
		if end_frames == 30:
			_dump("end-"+String(run.mode))
			if run.mode in ["victory","defeat"]: return false
			_finish()
			return true
		# The HUD shows the victory window 1.3 s (78 frames) after the win, and the gold bar needs 1.2 s more.
		if end_frames == 200 and run.mode in ["victory","defeat"]:
			_dump("end-"+String(run.mode)+"-result")
			_finish()
			return true
	if frame > 400000:
		push_error("hud_dump timed out"); _finish(); return true
	return false

func _finish() -> void:
	if not scene_path.is_empty():
		var scene_file := FileAccess.open(scene_path,FileAccess.WRITE)
		scene_file.store_string(JSON.stringify({"order":order,"scenes":scenes}))
		scene_file.close()
	if not out_path.is_empty():
		var file := FileAccess.open(out_path,FileAccess.WRITE)
		file.store_string(JSON.stringify({"order":order,"dumps":dumps}))
		file.close()
	print("HUD_DUMP_RESULT ",JSON.stringify({"labels":order,"final_tick":view.run.tick,"mode":view.run.mode,"kills":view.run.kills}))

## The growth offer is on screen for a single frame in a pilot run (the pilot picks on the next physics step), and the
## dump used to fire before the HUD had built the cards. Park the pilot while the offer is dumped, then let it go on.
func _choice_moment(run: RefCounted) -> void:
	if choice_dumps >= 2: return
	if run.mode == "choice" and choice_wait < 0:
		choice_wait = frame+8
		view._pilot = false
	elif choice_wait >= 0 and frame >= choice_wait:
		choice_dumps += 1; _dump("choice-%d" % choice_dumps)
		choice_wait = -1
		view._pilot = true

func _wait(frames: int) -> int:
	return frame+frames

var flow_next := 0
var flow_stage := 0

func _press(button: Button) -> void:
	# Real GUI routing: a left click at the button centre, in window pixels.
	var centre: Vector2 = view.get_window().get_final_transform()*button.get_global_rect().get_center()
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = centre; event.global_position = centre; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
		view.get_window().push_input(event)

func _hover(button: Button) -> void:
	var centre: Vector2 = view.get_window().get_final_transform()*button.get_global_rect().get_center()
	var event := InputEventMouseMotion.new()
	event.position = centre; event.global_position = centre
	view.get_window().push_input(event)

func _key(code: int) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code as Key; event.pressed = pressed
		view.get_window().push_input(event)

func _tree_flow() -> bool:
	var hud = view.hud
	var panel: Control = hud.skill_panel
	if frame < flow_next: return false
	match flow_stage:
		0:
			if frame < 5: return false
			_dump("menu")
			# Mouse-over and keyboard focus are one state in the menu: hover the third start button, check where the focus went.
			_hover(hud._menu_starts[2]); flow_next = frame+4; flow_stage = 10
		10:
			var focused = hud.root.get_viewport().gui_get_focus_owner()
			flow_log.append({"hover_takes_focus":focused == hud._menu_starts[2],"witch_after_hover":hud._menu_witch})
			hud.menu_select_skill("chapter1.skill.frost")
			# The focus moves with the portrait too (the capture tool used to leave it on the first button).
			if hud._menu_starts.size() > 1 and is_instance_valid(hud._menu_starts[1]): hud._menu_starts[1].grab_focus()
			flow_next = frame+4; flow_stage = 1
		1:
			_dump("menu-frost"); _press(hud._menu_tree_button); flow_next = frame+10; flow_stage = 2
		2:
			flow_log.append({"mouse_opens_tree":panel != null and panel.visible})
			OS.delay_msec(300)
			_dump("tree-open")
			# Stage two ranks with real mouse clicks on the tiles (volley, chill), then Esc to see the discard question.
			flow_next = frame+3; flow_stage = 3
		3:
			for id in ["witch.frost.volley","witch.frost.chill"]:
				panel._layout()
				var centre: Vector2 = view.get_window().get_final_transform()*panel._u(panel._tiles[id].get_center())
				var event := InputEventMouseButton.new()
				event.position = centre; event.global_position = centre; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = true
				view.get_window().push_input(event)
			flow_next = frame+4; flow_stage = 4
		4:
			flow_log.append({"staged_by_mouse":panel.staged_delta()})
			panel.select_node("witch.frost.volley")
			_dump("tree-staged")
			_key(KEY_ESCAPE); flow_next = frame+4; flow_stage = 5
		5:
			flow_log.append({"esc_asks_confirm":panel.confirm})
			_dump("tree-discard-question")
			_key(KEY_ESCAPE)   # Esc inside the question = keep editing
			flow_next = frame+3; flow_stage = 6
		6:
			flow_log.append({"after_second_esc_confirm":panel.confirm,"staged":panel.staged_delta()})
			_key(KEY_F)        # confirm
			flow_next = frame+5; flow_stage = 7
		7:
			_dump("tree-committed")
			flow_log.append({"committed_ranks":panel.committed.duplicate(),"points_free":panel.points_free,"message":panel.message})
			_key(KEY_ESCAPE)   # nothing staged any more: closes
			flow_next = frame+6; flow_stage = 8
		8:
			flow_log.append({"closed_visible":panel.visible})
			_dump("menu-after"); _press(hud._menu_tree_button); flow_next = frame+10; flow_stage = 9
		9:
			OS.delay_msec(300)
			_dump("tree-reopened")
			var reread = load("res://chapter1/core/chapter_profile.gd").new()
			var ok: bool = profile_fixture != "" and reread.configure(view.profile.path,true)
			flow_log.append({"reopened_visible":panel.visible,"reopened_ranks":panel.committed.duplicate(),"reread_from_disk":reread.character_view(FROST_ID).get("ranks",{}) if ok else {}})
			print("TREE_FLOW ",JSON.stringify(flow_log))
			_finish()
			return true
	return false

## Quick layout path for the result window: real start, some real progress grants, then a forced victory and save.
func _mock_result() -> bool:
	var run = view.run
	if frame == 6 and step == 0:
		view.start_run(primary)
		step = 1
	elif step == 1 and frame >= 10:
		# Without an isolated profile (profile off) the core keeps no progress record: skip the grants, show the save-off window.
		if profile_fixture != "":
			run._grant_progress("seal",150,0)
			run._grant_progress("seal",220,1)
			run._grant_progress("champion",50,0)
			run._progress_first_kill("champion:0")
		run.mode = "victory"
		view._save_terminal()
		step = 2; frame = 11
	elif step == 2 and frame >= 11+210:
		_dump("end-victory-result"); _finish(); return true
	return false

func _focus_name() -> String:
	var owner: Control = view.hud.root.get_viewport().gui_get_focus_owner()
	if owner == null: return ""
	return String(owner.name)+"|"+(String(owner.text) if owner is Button else "")

func _find_button(button_name: String) -> Button:
	return view.hud.root.find_child(button_name,true,false) as Button

func _flow_line(label: String) -> void:
	var run = view.run
	print("FLOW ",JSON.stringify({"label":label,"mode":run.mode,"primary":view.primary,"seed":view.seed_,"abandoned":view.hud._result_reason == "abandoned","tick":run.tick,"dialog":view.hud._flow_kind}))

## D5-U: the refused-save notice, driven only by key and mouse events like a player. Nothing is pressed that opens the
## file manager. The refused file and its journal copies are hashed before and after.
func _reject_flow() -> bool:
	var hud = view.hud
	if frame == 3:
		# The app's own _ready (profile-off, from the arguments) can run after the fixture was set up: put the refused path back.
		view._profile_off = false
		view._sync_profile(String(view.profile.error))
	if frame < rj_next: return false
	match rj_stage:
		0:
			if frame < 10: return false
			_dump("profile-rejected-menu")
			print("HUD_DUMP_REJECT ",JSON.stringify({"phase":"menu","rejected":view.profile_rejected(),"dialog_open":hud.flow_dialog_open(),"kind":hud._flow_kind,"focus":_focus_name()}))
			_key(KEY_TAB); rj_tabs = 1; rj_next = frame+3; rj_stage = 1
		1:
			print("HUD_DUMP_REJECT ",JSON.stringify({"phase":"tab","n":rj_tabs,"focus":_focus_name()}))
			if rj_tabs < 4:
				_key(KEY_TAB); rj_tabs += 1; rj_next = frame+3
			else:
				var fresh_button := _find_button("Flow_fresh")
				if fresh_button == null:
					push_error("no notice on screen"); _reject_finish(); return true
				fresh_button.grab_focus(); rj_next = frame+2; rj_stage = 2
		2:
			_key(KEY_ENTER); rj_next = frame+4; rj_stage = 3
		3:
			_dump("profile-rejected-fresh")
			print("HUD_DUMP_REJECT ",JSON.stringify({"phase":"fresh","kind":hud._flow_kind,"focus":_focus_name()}))
			if reject_choice == "fresh":
				_key(KEY_RIGHT); rj_next = frame+3; rj_stage = 4
			else:
				_key(KEY_ESCAPE); rj_next = frame+3; rj_stage = 5
		4:
			print("HUD_DUMP_REJECT ",JSON.stringify({"phase":"fresh-focus","focus":_focus_name()}))
			_key(KEY_ENTER); rj_next = frame+8; rj_stage = 9
		5:
			print("HUD_DUMP_REJECT ",JSON.stringify({"phase":"esc-from-fresh","kind":hud._flow_kind,"focus":_focus_name()}))
			_key(KEY_ESCAPE); rj_next = frame+4; rj_stage = 6
		6:
			print("HUD_DUMP_REJECT ",JSON.stringify({"phase":"esc-from-notice","dialog_open":hud.flow_dialog_open(),"mode":view.run.mode,"rejected":view.profile_rejected(),"focus":_focus_name()}))
			_dump("profile-rejected-notice-closed")
			_press(hud._menu_starts[0]); rj_next = frame+4; rj_stage = 7
		7:
			print("HUD_DUMP_REJECT ",JSON.stringify({"phase":"start-pressed","dialog_open":hud.flow_dialog_open(),"kind":hud._flow_kind,"focus":_focus_name(),"mode":view.run.mode}))
			_key(KEY_ENTER); rj_next = frame+5; rj_stage = 8
		8:
			print("HUD_DUMP_REJECT ",JSON.stringify({"phase":"after-play","rejected":view.profile_rejected(),"session_off":view._profile_session_off,"dialog_open":hud.flow_dialog_open(),"available":view.profile.available,"note":hud.profile_note}))
			_dump("profile-rejected-after-play")
			rj_stage = 9
		9:
			print("HUD_DUMP_REJECT ",JSON.stringify({"phase":"before-start","rejected":view.profile_rejected(),"available":view.profile.available,"dialog_open":hud.flow_dialog_open(),"files":_file_hashes(rj_folder)}))
			view.start_run(primary)
			print("HUD_DUMP_REJECT ",JSON.stringify({"phase":"started","mode":view.run.mode,"first_boss_kill":view.run.first_boss_kill,"note":hud.profile_note}))
			if result_mock:
				view.run.mode = "victory"
				view._save_terminal()
				rj_next = frame+210; rj_stage = 11
			else:
				rj_stage = 10
		10:
			if view.run.tick >= 120:
				_dump("profile-rejected-nosave-playing-120")
				_reject_finish()
				return true
		11:
			_dump("profile-rejected-result")
			print("HUD_DUMP_REJECT ",JSON.stringify({"phase":"result","note":hud.profile_note}))
			_reject_finish()
			return true
	if frame > 20000:
		push_error("reject flow timed out"); _reject_finish(); return true
	return false

func _reject_finish() -> void:
	var after := _file_hashes(rj_folder)
	var untouched := true
	for key in rj_files_before:
		if not after.has(key) or after[key] != rj_files_before[key]: untouched = false
	print("HUD_DUMP_FILES ",JSON.stringify({"before":rj_files_before,"after":after,"originals_unchanged":untouched,"new_files":after.keys().filter(func(k): return not rj_files_before.has(k))}))
	_finish()

## D4-U: pause -> abandon -> result -> menu -> another witch, the defeat hold, and the quit button.
func _run_flow() -> bool:
	var hud = view.hud
	var run = view.run
	if frame < fl_next: return false
	if flow_shots == "quit":
		if frame == 6:
			_press(_find_button("QuitGame"))
			fl_next = frame+60
		elif frame > 200:
			push_error("quit did not end the process"); _finish(); return true
		return false
	if flow_shots == "defeat":
		if frame > 40000:
			push_error("defeat flow timed out"); _finish(); return true
		match fl_stage:
			0:
				if frame < 6: return false
				view.start_run(primary); fl_stage = 1
			1:
				if run.tick >= defeat_at and run.mode == "playing":
					# The pilot would dodge forever: park the hero and keep one hit point until something lands.
					view._pilot = false
					run.hero.hp_raw = 1
					fl_stage = 2
			2:
				if run.mode == "playing" and run.hero.hp_raw > 1: run.hero.hp_raw = 1
				if run.mode == "defeat":
					fl_frame0 = frame; fl_before = {"tick": run.tick}
					_flow_line("defeat-start")
					fl_stage = 3
			3:
				var since := frame-fl_frame0
				if since == 18:
					_key(KEY_R)
				elif since == 30:
					_dump("flow-defeat-0.5s"); _flow_line("flow-defeat-0.5s")
					print("FLOW_CHECK ",JSON.stringify({"overlay_visible":hud.overlay.visible,"revealed":hud.result_revealed()}))
				elif since == 48:
					_dump("flow-defeat-r-blocked"); _flow_line("flow-defeat-r-blocked")
					print("FLOW_CHECK ",JSON.stringify({"tick_at_fall":fl_before.tick,"tick_now":run.tick,"mode":run.mode,"overlay_visible":hud.overlay.visible}))
				elif since == 120:
					_dump("flow-defeat-result"); _flow_line("flow-defeat-result")
					print("FLOW_CHECK ",JSON.stringify({"overlay_visible":hud.overlay.visible,"revealed":hud.result_revealed()}))
					_finish(); return true
		return false
	match fl_stage:
		0:
			if frame < 5: return false
			_dump("menu"); _flow_line("menu")
			view.start_run(primary); fl_stage = 1
		1:
			if run.tick >= 600 and run.mode == "playing":
				view.toggle_pause(); fl_next = frame+4; fl_stage = 2
		2:
			_dump("flow-paused"); _flow_line("flow-paused")
			print("FLOW_CHECK ",JSON.stringify({"focus":_focus_name(),"abandon_button":_find_button("AbandonRun") != null}))
			_press(_find_button("AbandonRun")); fl_next = frame+4; fl_stage = 3
		3:
			_dump("flow-abandon-confirm"); _flow_line("flow-abandon-confirm")
			print("FLOW_CHECK ",JSON.stringify({"focus":_focus_name(),"kind":hud._flow_kind}))
			_key(KEY_ESCAPE); fl_next = frame+4; fl_stage = 30
		30:
			print("FLOW_CHECK ",JSON.stringify({"esc_cancels":not hud.flow_dialog_open(),"mode":run.mode,"focus":_focus_name()}))
			_press(_find_button("AbandonRun")); fl_next = frame+4; fl_stage = 31
		31:
			# Keyboard: the default is Cancel; Left/Right reaches the abandon button, Enter presses it.
			_key(KEY_LEFT); fl_next = frame+3; fl_stage = 32
		32:
			print("FLOW_CHECK ",JSON.stringify({"focus_after_left":_focus_name()}))
			_key(KEY_ENTER); fl_next = frame+10; fl_stage = 4
		4:
			print("HUD_DUMP_PROFILE_AFTER ",JSON.stringify({"mode":run.mode,"completed_runs":view.profile.state.completed_runs,"items":view.profile.state.items.size(),"receipts":view.profile.state.receipts.size(),"xp_gained":view.run_progress.get("xp_gained",-1),"bag":run.inventory.size(),"unsaved":hud.result_unsaved}))
			fl_next = frame+130; fl_stage = 5
		5:
			_dump("flow-end-abandon-result"); _flow_line("flow-end-abandon-result")
			print("FLOW_CHECK ",JSON.stringify({"revealed":hud.result_revealed(),"title":hud.modal.get_child(0).get_child(0).text if hud.modal.get_child_count() > 0 else ""}))
			_press(_find_button("ReturnToMenu")); fl_next = frame+10; fl_stage = 6
		6:
			_dump("flow-menu-returned"); _flow_line("flow-menu-returned")
			print("FLOW_CHECK ",JSON.stringify({"focus":_focus_name(),"hero_empty":view.run.hero.is_empty(),"mode":view.run.mode}))
			var other: int = 1 if primary == "chapter1.skill.ember" else 0
			_press(hud._menu_starts[other]); fl_next = frame+4; fl_stage = 7
		7:
			if view.run.tick >= 120 and view.run.mode == "playing":
				_dump("flow-playing-after-return-120"); _flow_line("flow-playing-after-return-120")
				_finish(); return true
	if frame > 30000:
		push_error("run flow timed out"); _finish(); return true
	return false
