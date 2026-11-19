extends SceneTree
## Screen scene renderer: one named screen on fixed data, shot at the window size the process was started with, plus a
## Control dump for tools/dev/hud_layout_check.py. Generalises skill_tree_preview.gd to every window the game has.
##
## THE SCREENS ARE BUILT FROM FIXTURES (chapter1/tests/fixtures/ui/<scene>.<variant>.json), NOT FROM A REAL RUN.
## They can differ from what the core really produces. The final check is a real-run capture (hud_dump.gd --shots).
##
## Needs a real renderer (no --headless) and --chapter1-profile-off (the user's own save is never opened; the fixtures
## never touch any profile file). Captures go under _local/shots/ only. One resolution per process:
##
##   python tools/dev/godot.py --fixed-fps 60 --resolution 1280x720  --path . --script res://chapter1/tests/scene_shot.gd -- \
##       --chapter1-profile-off --scenes=all --shots=_local/shots/<name>
##   python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/scene_shot.gd -- \
##       --chapter1-profile-off --scenes=title,boon --variants=long --shots=_local/shots/<name>
##
## Arguments: --scenes=<a,b|all>  --variants=<normal,long|all> (default all; a scene without that variant is skipped and
## printed)  --shots=<dir>  --list  (prints the scene names and exits).
## Output per scene and variant: <dir>/<scene>.<variant>.<W>x<H>.png and .json (hud_dump's {"order","dumps"} format plus a
## "meta" entry), and SCENE_SHOT lines. Exit code 2 for bad arguments, 1 if a scene could not be set up.
##
## The scenes: title, skill_tree (over the title), boon (growth choice), boon_spells (growth choice of a run with the spell
## composition on, RS0 of docs/specs/A6-run-spells-screen: how the screen draws the cards of the composition NOW; the fixture
## names the state to give the run and the card ids to show, and the cards are the ones the core builds for that state), equipment (in-run compare), stash, result
## (victory window with the permanent-growth box), pause, abandon_confirm, combat_record (the battle record over the result
## window: normal = a won run, defeat = a lost run, long = a lost run with every zone and the longest rows; scrolled = the same scrolled to its end; the "defeat" and "scrolled" variants exist for this scene only); boon_spells has two more, "arc" and "ember" (RS3: the other two witches' ring cards and a borrowed spell). The skill tree draws itself (no child Controls),
## so its dump holds the panel only; judge it on the picture.
##
## HOW TO ADD A SCENE (a screen that exists in the game):
##   1. Put "<scene>" in SCENES and write `func _scene_<scene>(fx: Dictionary) -> bool` below. It receives the fixture,
##      sets the screen up through the HUD's own public/state entry points (start_run, set mode, hud.* data, hud.invalidate),
##      awaits a few frames (`await _frames(n)`) and returns true when the screen is on, false (after _fail) when not.
##   2. Add fixtures/ui/<scene>.normal.json and <scene>.long.json; "long" holds the longest names and descriptions the
##      screen can meet (the longest real strings, not a made-up wall of text).
##   3. A screen that does not exist yet (town hub, card with an interlock line) is NOT added here: add it
##      together with the screen.
const LayoutDump := preload("res://chapter1/tests/layout_dump.gd")
const SkillTree := preload("res://chapter1/core/skill_tree.gd")
const FIXTURE_DIR := "res://chapter1/tests/fixtures/ui/"
const NOTE := "픽스처로 띄운 화면. 최종 확인은 실제 판 캡처(hud_dump)"
const SCENES := ["title","skill_tree","boon","boon_spells","equipment","stash","result","pause","abandon_confirm","combat_record"]
const VARIANTS := ["normal","long","defeat","scrolled","arc","ember"]
const START_SKILLS := ["chapter1.skill.ember","chapter1.skill.frost","chapter1.skill.arc"]

## The core with the two answers a fixture needs to control. Everything else is the real core.
class FixtureRun extends "res://chapter1/core/chapter_core.gd":
	var fx_offer := {}
	var fx_level := 0
	func get_offer() -> Dictionary:
		if mode == "choice" and not fx_offer.is_empty(): return fx_offer
		return super.get_offer()
	func can_equip(item: Dictionary) -> bool:
		if fx_level > 0: return int(item.get("required_level",1)) <= fx_level
		return super.can_equip(item)

var shots := ""
var scene_list: Array[String] = []
var variant_list: Array[String] = []
var view: Node
var run: FixtureRun
var hud
var failures: Array[String] = []
var written: Array[String] = []

func _initialize() -> void:
	var wanted_scenes := "all"
	var wanted_variants := "all"
	var list_only := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenes="): wanted_scenes = arg.trim_prefix("--scenes=")
		elif arg.begins_with("--variants="): wanted_variants = arg.trim_prefix("--variants=")
		elif arg.begins_with("--shots="): shots = arg.trim_prefix("--shots=")
		elif arg == "--list": list_only = true
	if list_only:
		print("SCENE_SHOT_SCENES ",JSON.stringify({"scenes":SCENES,"variants":VARIANTS}))
		quit(0)
		return
	var problem := _check_args(wanted_scenes,wanted_variants)
	if not problem.is_empty():
		push_error("scene_shot: "+problem)
		print("SCENE_SHOT_ARGS ",JSON.stringify({"error":problem}))
		quit(2)
		return
	print(NOTE)
	_run_all.call_deferred()

func _check_args(wanted_scenes: String, wanted_variants: String) -> String:
	if not "--chapter1-profile-off" in OS.get_cmdline_user_args():
		return "--chapter1-profile-off is required (the user's own save is never opened)"
	if DisplayServer.get_name() == "headless":
		return "needs a real renderer: run without --headless"
	if shots.is_empty():
		return "--shots=<dir under _local/shots> is required"
	var folder := shots if shots.begins_with("res://") or shots.is_absolute_path() else "res://"+shots
	if not ("/_local/shots/" in ProjectSettings.globalize_path(folder).replace("\\","/")+"/"):
		return "--shots must be a folder under _local/shots/ (got %s)" % shots
	shots = folder
	for name_ in (SCENES if wanted_scenes == "all" else wanted_scenes.split(",")):
		if not name_ in SCENES: return "unknown scene '%s' (have: %s)" % [name_,", ".join(SCENES)]
		scene_list.append(name_)
	for name_ in (VARIANTS if wanted_variants == "all" else wanted_variants.split(",")):
		if not name_ in VARIANTS: return "unknown variant '%s' (have: %s)" % [name_,", ".join(VARIANTS)]
		variant_list.append(name_)
	return ""

func _frames(count: int) -> void:
	for i in count: await process_frame

func _fail(scene: String, why: String) -> void:
	failures.append(scene+": "+why)
	push_error("scene_shot %s: %s" % [scene,why])

func _load_fixture(scene: String, variant: String) -> Dictionary:
	var path := FIXTURE_DIR+scene+"."+variant+".json"
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		_fail(scene,"fixture is not a JSON object: "+path)
		return {}
	parsed["__path"] = path
	return parsed

func _run_all() -> void:
	DirAccess.make_dir_recursive_absolute(shots)
	for scene in scene_list:
		for variant in variant_list:
			var fx := _load_fixture(scene,variant)
			if fx.is_empty():
				print("SCENE_SHOT_SKIP ",JSON.stringify({"scene":scene,"variant":variant,"why":"no fixture (or unreadable)"}))
				continue
			await _open_view()
			if view == null: return
			var ok: bool = await call("_scene_"+scene,fx)
			if ok:
				await _frames(6)
				await RenderingServer.frame_post_draw
				_capture(scene,variant,fx)
			await _close_view()
	print("SCENE_SHOT_RESULT ",JSON.stringify({"written":written.size(),"failures":failures,"note":NOTE}))
	quit(1 if not failures.is_empty() else 0)

func _open_view() -> void:
	view = (load("res://chapter1/ChapterOne.tscn") as PackedScene).instantiate()
	if view.get_script() == null or view.get("run") == null:
		push_error("ChapterOne failed to load its script; see the errors above")
		failures.append("ChapterOne failed to load")
		quit(3)
		view = null
		return
	run = FixtureRun.new()
	view.run = run
	view.full_pilot.run = run
	root.add_child(view)
	hud = view.hud
	await _frames(4)

func _close_view() -> void:
	if view != null:
		view.queue_free()
		view = null
		hud = null
	await _frames(3)

func _capture(scene: String, variant: String, fx: Dictionary) -> void:
	var stem := "%s.%s.%dx%d" % [scene,variant,root.size.x,root.size.y]
	var image := root.get_viewport().get_texture().get_image()
	if image == null:
		_fail(scene,"no image from the viewport")
		return
	image.save_png(shots.path_join(stem+".png"))
	var rows: Array = []
	LayoutDump.describe(root,0,rows,true)
	var label := scene+"."+variant
	var document := {"order":[label],"dumps":{label:rows},
		"meta":{"extra":true,"note":NOTE,"scene":scene,"variant":variant,"fixture":String(fx.get("__path","")),"combat":false,
			"canvas":[root.get_visible_rect().size.x,root.get_visible_rect().size.y],"window":[root.size.x,root.size.y]}}
	var file := FileAccess.open(shots.path_join(stem+".json"),FileAccess.WRITE)
	if file == null:
		_fail(scene,"cannot write the dump")
		return
	file.store_string(JSON.stringify(document))
	file.close()
	written.append(stem)
	var visible := 0
	for row in rows:
		if row.visible: visible += 1
	print("SCENE_SHOT ",JSON.stringify({"scene":scene,"variant":variant,"window":[root.size.x,root.size.y],"controls":rows.size(),"visible":visible,"png":shots.path_join(stem+".png"),"note":NOTE}))

# ---- scenes ----

func _start_run() -> void:
	view.start_run("chapter1.skill.frost")

func _items(fx: Dictionary) -> Array:
	var out: Array = []
	for item in fx.get("items",[]): out.append(item.duplicate(true))
	return out

func _records(fx: Dictionary) -> Array:
	var out: Array = []
	for record in fx.get("records",[]): out.append(record.duplicate(true))
	return out

func _scene_title(fx: Dictionary) -> bool:
	for key in fx.get("strings",{}): hud.set(key,fx.strings[key])
	hud.profile_note = String(fx.get("note",""))
	var records: Array = []
	for i in int(fx.get("stash_count",0)):
		records.append({"storage_id":i+1,"item":{"slot":"weapon","quality":"common","name":"보관 장비 %d" % (i+1),"stats":{}}})
	hud.profile_state = {"items":records,"equipped":{},"essence":0,"completed_runs":0}
	hud.character_views = fx.get("views",{}).duplicate(true)
	hud.invalidate()
	await _frames(4)
	hud.menu_select_skill(START_SKILLS[int(fx.get("witch",1))])
	await _frames(30)
	return true

func _scene_skill_tree(fx: Dictionary) -> bool:
	var trees: Dictionary = SkillTree.load_trees()
	if trees.has("error") or not trees.has(String(fx.tree_id)):
		_fail("skill_tree","tree document unavailable: "+str(trees.get("error","")))
		return false
	var tree: Dictionary = trees[String(fx.tree_id)].duplicate(true)
	_patch_tree(tree,fx.get("patch",{}))
	hud.character_views = {String(fx.character):fx.view.duplicate(true)}
	hud.invalidate()
	await _frames(4)
	hud.show_skill_tree(String(fx.character),tree,fx.view.duplicate(true),fx.info.duplicate(true))
	await _frames(4)
	hud.skill_panel.select_node(String(fx.selected))
	await _frames(20)
	if not hud.skill_tree_is_open():
		_fail("skill_tree","the panel did not open")
		return false
	return true

func _patch_tree(tree: Dictionary, patch: Dictionary) -> void:
	for node in tree.get("nodes",[]):
		if patch.get("nodes",{}).has(node.id): node.merge(patch.nodes[node.id],true)
	for branch in tree.get("branches",[]):
		if patch.get("branches",{}).has(branch.id): branch.merge(patch.branches[branch.id],true)
	for tier in tree.get("tiers",[]):
		if patch.get("tiers",{}).has(str(int(tier.level))): tier.merge(patch.tiers[str(int(tier.level))],true)

func _scene_boon(fx: Dictionary) -> bool:
	_start_run()
	await _frames(3)
	run.fx_offer = fx.offer.duplicate(true)
	run.mode = "choice"
	hud.invalidate()
	await _frames(10)
	if hud.modal.get_child_count() == 0 or run.get_offer().is_empty():
		_fail("boon","the growth window did not build")
		return false
	return true

## RS0. The composition is switched on in this process only: the shipped run_spells.json is read, copied with "enabled": true and
## parked in the FixtureRun before it starts (data file and app untouched). The state is given the way test_run_spells.gd's give()
## does it; the cards are the real ones from the growth's own pool, picked by id.
func _scene_boon_spells(fx: Dictionary) -> bool:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://chapter1/data/run_spells.json"))
	if not doc is Dictionary:
		_fail("boon_spells","run_spells.json could not be read")
		return false
	doc["enabled"] = true
	if not run.set_run_spells(doc):
		_fail("boon_spells","run_spells document refused: "+str(run.errors))
		return false
	view.start_run(String(fx.primary))
	await _frames(3)
	if not bool(run.run_spells_view().get("enabled",false)):
		_fail("boon_spells","the run did not take the composition")
		return false
	for id_ in fx.get("give",{}):
		run.growth._ranks[id_] = 1
		run.growth._axes[id_] = {"damage":int(fx.give[id_].damage),"reach":int(fx.give[id_].reach)}
	for passive_id in fx.get("passives",[]): run.growth._owned_passives.append(String(passive_id))
	var pool: Array = run.growth._spell_cards()
	var cards: Array = []
	for wanted in fx.cards:
		var found := false
		for card in pool:
			if String(card.id) == String(wanted):
				cards.append(card.duplicate(true))
				found = true
				break
		if not found:
			_fail("boon_spells","card %s is not in the pool of the given state (pool: %s)" % [wanted,", ".join(pool.map(func(c): return String(c.id)))])
			return false
	run.fx_offer = {"token":"fixture-spells","level":int(fx.level),"cards":cards}
	# The offer is also the growth's own drawn offer, so run_spells_view().offer (pairs_if_taken) answers as it does in a real run.
	run.growth._offer = run.fx_offer.duplicate(true)
	run.mode = "choice"
	hud.invalidate()
	await _frames(10)
	if hud.modal.get_child_count() == 0 or run.get_offer().is_empty():
		_fail("boon_spells","the growth window did not build")
		return false
	return true

func _scene_equipment(fx: Dictionary) -> bool:
	_start_run()
	await _frames(3)
	run.fx_level = int(fx.get("level",1))
	run.inventory.clear()
	for item in _items(fx): run.inventory.append(item)
	run.equipped = {}
	for slot in fx.get("equipped",{}): run.equipped[slot] = int(fx.equipped[slot])
	if not run.open_inventory():
		_fail("equipment","the core would not open the inventory")
		return false
	hud._selected_item = int(fx.get("selected",-1))
	hud.invalidate()
	await _frames(12)
	if run.mode != "inventory":
		_fail("equipment","mode is %s, not inventory" % run.mode)
		return false
	return true

func _scene_stash(fx: Dictionary) -> bool:
	var equipped := {}
	for slot in fx.get("equipped",{}): equipped[slot] = int(fx.equipped[slot])
	hud.profile_state = {"items":_records(fx),"equipped":equipped,"essence":int(fx.get("essence",0)),"completed_runs":int(fx.get("completed_runs",0))}
	hud.profile_note = String(fx.get("note",""))
	hud._storage_selection = int(fx.get("selected",-1))
	hud.stash_open = true
	hud.invalidate()
	await _frames(12)
	return true

func _scene_result(fx: Dictionary) -> bool:
	_start_run()
	await _frames(3)
	run.inventory.clear()
	for item in _items(fx): run.inventory.append(item)
	run.equipped = {}
	for slot in fx.get("equipped",{}): run.equipped[slot] = int(fx.equipped[slot])
	run._elite_reward_uid = int(fx.get("elite_uid",0))
	run.kills = int(fx.kills)
	run.tick = int(fx.tick)
	hud.motion_enabled = false
	hud.profile_note = String(fx.get("note",""))
	var growth: Dictionary = fx.get("growth",{})
	if not growth.is_empty(): hud.set_growth_result(String(growth.character_id),growth.before.duplicate(true),growth.after.duplicate(true),growth.progress.duplicate(true))
	run._terminal_mode = String(fx.mode)
	run.mode = String(fx.mode)
	hud.invalidate()
	# The window appears 1.3 s after the win (78 frames at 60 fps).
	for i in 300:
		await process_frame
		if hud.overlay.visible: break
	await _frames(12)
	if not hud.overlay.visible:
		_fail("result","the result window never appeared")
		return false
	return true

func _scene_pause(_fx: Dictionary) -> bool:
	_start_run()
	await _frames(40)
	view.toggle_pause()
	await _frames(10)
	if run.mode != "paused":
		_fail("pause","mode is %s, not paused" % run.mode)
		return false
	return true

func _scene_abandon_confirm(fx: Dictionary) -> bool:
	_start_run()
	await _frames(40)
	view.toggle_pause()
	await _frames(6)
	if bool(fx.get("real",true)):
		hud._ask_abandon()
	else:
		var buttons: Array = fx.buttons
		hud._open_dialog("abandon",{"width":720,"title":String(fx.title),"content":hud._dialog_text(String(fx.body)),
			"buttons":[{"id":"go","text":String(buttons[0])},{"id":"cancel","text":String(buttons[1])}],"default_id":"cancel","esc_id":"cancel"})
	await _frames(10)
	if not hud.flow_dialog_open():
		_fail("abandon_confirm","the confirm window did not open")
		return false
	return true

func _scene_combat_record(fx: Dictionary) -> bool:
	_start_run()
	await _frames(3)
	run.kills = int(fx.kills)
	run.tick = int(fx.tick)
	hud.motion_enabled = false
	hud.profile_note = String(fx.get("note",""))
	hud.set_run_record(fx.view.duplicate(true))
	run._terminal_mode = String(fx.mode)
	run.mode = String(fx.mode)
	hud.invalidate()
	for i in 300:
		await process_frame
		if hud.overlay.visible: break
	await _frames(12)
	if not hud.overlay.visible:
		_fail("combat_record","the result window never appeared")
		return false
	hud._record_level = int(fx.get("level",0))
	hud.open_combat_record()
	await _frames(12)
	if not hud.combat_record_open():
		_fail("combat_record","the battle record did not open")
		return false
	if bool(fx.get("scroll_end",false)):
		var scroll: ScrollContainer = hud._flow_dialog.find_child("RecordScroll",true,false)
		scroll.scroll_vertical = 100000
		await _frames(6)
	return true
