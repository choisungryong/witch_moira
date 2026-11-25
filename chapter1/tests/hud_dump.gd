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
##   --profile-fixture=rejected   an isolated profile file whose structure is broken (two items share a storage id), plus journal
##                                copies, under res://_local/shots/ui-g1p4/profiles/<tag>/. The app is put on its refused-save path.
##                                Moments: profile-rejected-menu, profile-rejected-fresh, profile-rejected-notice-closed,
##                                profile-rejected-after-play, profile-rejected-nosave-playing-120 (or profile-rejected-result
##                                with --result-mock). Prints HUD_DUMP_REJECT lines and HUD_DUMP_FILES (sha256 of every file).
##   --reject-choice=play|fresh   which way the rejected flow ends (fresh = continue from the newest readable journal copy).
## Normal runs now add an "end-<mode>-result" moment after the existing end moment.
## Time limit: --wall-limit=<seconds> (default 1500, 0 = none) ends a stuck flow with HUD_DUMP_RESULT {"error":"wall_limit"} and exit code 4.
## Optional: --until=<tick> stops early; --primary=<skill id>; --shots=<dir> also saves a
## screenshot per moment (needs a real renderer, so run without --headless).
## Tooling additions (never change the default dump):
##   --dump-extra                 add layout fields to every Control row (font size "fs", effective alpha "alpha", clipping
##                                ancestors "clip", combined minimum size "min", text metrics "tw"/"th"/"lines"/"vis_lines"/"pad")
##                                and a "meta" entry (canvas size, window size, scale). Read by tools/dev/hud_layout_check.py.
##                                Without the flag the dump is byte-for-byte what it always was.
## T7-0 / A6-0 additions (opt-in; without them the dump is byte-for-byte what it was):
##   --asset-usage=<file under _local/>   which files under chapter1/art/ were loaded and which were really drawn or played
##                                during this run (see chapter1/tests/asset_usage_probe.gd). Works with every mode above.
##                                tools/dev/asset_usage_report.py merges several of these files into the table.
##   --burst=<name,...>           after the first core event of each name, save --burst-frames (default 8) screenshots, one
##                                every 6 ticks (0.1 s), into --shots. Name = event type, or type:value, or type:key=value
##                                (growth, seal_grace, chapter_champion, victory, item_drop:legendary, beat_started, ...).
##                                Names never met are listed on the last line (HUD_BURST_SUMMARY). See burst_capture.gd.
##   --menu-tour                  (T7-0, needs --asset-usage and --profile-fixture=l8) no run: for each of the three witches select it on
##                                the menu and open and close its skill tree, so the usage table sees every menu portrait and
##                                every skill tree painting. Prints MENU_TOUR lines.
## RS0 (A6-RS, opt-in; without these two the run and the dump are byte-for-byte what they were):
##   --run-spells=on              run with the in-run spell composition ON, by this tool only: chapter1/data/run_spells.json is read,
##                                copied with "enabled": true and handed to the core with run.set_run_spells() before the run starts.
##                                The data file and the app are not touched. Prints one HUD_SPELLS line at the end (what the run owned).
##   --spells-pick=synergy        (needs --run-spells=on) the tool, not the built-in pilot, picks the growth cards in mode "choice":
##                                the witch's ring unlock > the main skill's damage axis > a ring's reach axis > the pilot's own
##                                scoring for everything else. Each pick prints a HUD_SPELLS_PICK line (tick, level, card, score).
##                                The choice-1 / choice-2 moments are dumped before the tool picks, as before.
## T13 R2: the first screen is chapter1/view/hud/screens/title.gd. This tool reaches it only through the host's public calls (menu_select_skill, menu_witch_index,
##   title_settle, title_screen, title_app_state) and the node names TitleStart / TitleTree / TitleStash / Door0..2 / TitleMenuButton, with real mouse and key events.
##   A host without title_settle (the base commit of tools/dev/equiv.py, which gets a copy of this file) takes the old path: the default moments are the same ones.
##   After a press on TitleStart the screen needs its confirm beat (1.2 s); the flows below wait for what that press leads to instead of 4 frames.
##   --title-input=keys|pad       (T13 R2, needs --profile-fixture=l8; no run before the end) the first screen by the keyboard only / by the pad only, no mouse:
##                                the witch keys (or d-pad), the handles, the skill tree, the stash window, the Esc window, M (the notice band over the screen) and the start.
##                                One TITLE_INPUT line per step (witch, tree_open, stash_open, esc_window, mode, toast); moments title-input-tree / -stash / -esc-window / -muted.
## T8 S0-b (opt-in; without them the dump and the run are byte-for-byte what they were):
##   --dump-contracts=<folder under _local/>   at the moments below, also write what the screen ADAPTER makes from this very run
##                                (chapter1/view/contracts/<id>_contract.gd, build(run, app_state)) as <folder>/<id>.<moment>.json, for
##                                tools/dev/screen_contract_check.py --dumps. Moments: "menu" -> title, "choice-1" and "choice-2" -> growth_choice.
##                                A screen whose adapter does not exist yet is skipped and printed (HUD_CONTRACT_SKIP). The default dump is untouched.
##   The test switches that are on (--chapter1-trial=..., --run-spells=on, ...) are named in the dump ("trial" next to "order"/"dumps") and on one
##   HUD_TRIAL line, and only when one is on (chapter1/tests/support/trial_docs.gd).
##   Missing or contradicting arguments end at once with one HUD_DUMP_ARGS line and exit code 2 (a flow that needs a
##   fixture never starts and waits for a window that does not come): --tree-shots needs --profile-fixture=l8,
##   every --profile-fixture needs --chapter1-profile-off, --shots needs a real renderer, unknown values are refused.
var view: Node
var dumps: Dictionary = {}
var order: Array[String] = []
var out_path := ""
var primary := "chapter1.skill.frost"
var until_tick := 0
var wall_limit_s := 1500
var started_msec := 0
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
var choice_frames := 8   ## frames between the choice window opening and its dump; --choice-frames=<n> (the grace screen's intro is 0.45 s, the long one 1.8 s)
var notice_shots := false
var flow_log: Array = []
var flow_shots := ""
var defeat_at := 1200
var reject_choice := "play"
var dump_extra := false
var asset_usage_path := ""
var usage: RefCounted = null
var burst_arg := ""
var burst_frames := 8
var burst_step := 6
var burst_frames_given := false
var run_spells_arg := ""
var spells_pick := ""
## --descent=now|hold|panic (D15 U-2, opt-in): the tool presses R by the same rule as chapter1/tests/descent_policy.gd. Needs
## --chapter1-trial=descent[,..] and --chapter1-profile-off (the descent is off in the shipped data). Without it nothing changes.
var descent_arg := ""
var spells_picks: Array = []
var burst: RefCounted = null
var menu_tour := false
var mt_stage := 0
var mt_index := 0
var mt_next := 0
var mt_log: Array = []
const TOUR_SKILLS := ["chapter1.skill.ember","chapter1.skill.frost","chapter1.skill.arc"]
var rj_stage := 0
var rj_next := 0
var rj_tabs := 0
var rj_until := 0
var rj_files_before: Dictionary = {}
var rj_folder := ""
var fl_stage := 0
var fl_next := 0
var fl_frame0 := 0
var fl_before: Dictionary = {}
var ti_log: Array = []
const ProfileScript := preload("res://chapter1/core/chapter_profile.gd")
const LayoutDump := preload("res://chapter1/tests/layout_dump.gd")
const UsageProbe := preload("res://chapter1/tests/asset_usage_probe.gd")
const BurstCapture := preload("res://chapter1/tests/burst_capture.gd")
const SpellsPick := preload("res://chapter1/tests/spells_pick.gd")
const TrialDocs := preload("res://chapter1/tests/support/trial_docs.gd")
const CONTRACT_MOMENTS := {"menu": "title", "choice-1": "growth_choice", "choice-2": "growth_choice"}
var contract_dir := ""
var title_input := ""
var ti_steps: Array = []
var ti_step := 0
var ti_next := 0
var ti_pending := ""
var ti_deadline := 0
const DescentPolicy := preload("res://chapter1/tests/descent_policy.gd")
const FROST_ID := "chapter1.character.frost"
const FIXTURE_RANKS := {"witch.frost.needle":3,"witch.frost.volley":1,"witch.frost.rime":2}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dump="): out_path = arg.trim_prefix("--dump=")
		elif arg.begins_with("--primary="): primary = arg.trim_prefix("--primary=")
		elif arg.begins_with("--choice-frames="): choice_frames = int(arg.trim_prefix("--choice-frames="))
		elif arg.begins_with("--until="): until_tick = int(arg.trim_prefix("--until="))
		elif arg.begins_with("--wall-limit="): wall_limit_s = int(arg.trim_prefix("--wall-limit="))
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
		elif arg == "--dump-extra": dump_extra = true
		elif arg == "--menu-tour": menu_tour = true
		elif arg.begins_with("--asset-usage="): asset_usage_path = arg.trim_prefix("--asset-usage=")
		# "--burst=<tick>,<frames>" (two integers) is the hero capture of rig_game_probe.gd, not an event-name burst.
		elif arg.begins_with("--burst=") and not _is_tick_burst(arg.trim_prefix("--burst=")): burst_arg = arg.trim_prefix("--burst=")
		elif arg.begins_with("--burst-step="): burst_step = maxi(1,int(arg.trim_prefix("--burst-step=")))
		elif arg.begins_with("--burst-frames="): burst_frames = int(arg.trim_prefix("--burst-frames=")); burst_frames_given = true
		elif arg.begins_with("--run-spells="): run_spells_arg = arg.trim_prefix("--run-spells=")
		elif arg.begins_with("--spells-pick="): spells_pick = arg.trim_prefix("--spells-pick=")
		elif arg.begins_with("--dump-contracts="): contract_dir = arg.trim_prefix("--dump-contracts=")
		elif arg.begins_with("--title-input="): title_input = arg.trim_prefix("--title-input=")
		elif arg.begins_with("--descent="): descent_arg = arg.trim_prefix("--descent=")
	var args_error := _check_args()
	if not args_error.is_empty():
		push_error("hud_dump: "+args_error)
		print("HUD_DUMP_ARGS ",JSON.stringify({"error":args_error}))
		quit(2)
		return
	started_msec = Time.get_ticks_msec()
	if not TrialDocs.tag(OS.get_cmdline_user_args()).is_empty(): print("HUD_TRIAL ",JSON.stringify(TrialDocs.switches(OS.get_cmdline_user_args())))
	# A project without its import cache (a fresh worktree) loads the scene with errors and then spins forever: refuse at once.
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.godot/imported")):
		push_error("hud_dump: res://.godot/imported is missing, the project is not imported here (python tools/dev/run_dev.py --import-only)")
		print("HUD_DUMP_ARGS ",JSON.stringify({"error":"project_not_imported"}))
		quit(3)
		return
	var scene: PackedScene = load("res://chapter1/ChapterOne.tscn")
	view = scene.instantiate()
	# A script that failed to compile leaves a bare node: stop instead of spinning.
	if view.get_script() == null or view.get("run") == null:
		push_error("ChapterOne failed to load its script; see the errors above")
		print("HUD_DUMP_RESULT ",JSON.stringify({"error":"scene_script_failed"}))
		quit(3)
		return
	root.add_child(view)
	if run_spells_arg == "on":
		var spells_problem := _enable_run_spells()
		if not spells_problem.is_empty():
			push_error("hud_dump: "+spells_problem)
			print("HUD_DUMP_ARGS ",JSON.stringify({"error":spells_problem}))
			quit(2)
			return
	_setup_profile()
	if not asset_usage_path.is_empty():
		usage = UsageProbe.new()
		usage.holders = [view.get("actors"),view.get("world"),view.get("audio"),view.get("effects"),view.get("juice")]
	if not burst_arg.is_empty():
		var wanted: Array[String] = []
		for part in burst_arg.split(",",false): wanted.append(part.strip_edges())
		burst = BurstCapture.new()
		burst.setup(wanted,burst_frames,shots_dir)
		burst.step_ticks = burst_step
		# Events live one tick in run.events: read them at every physics frame (before the view steps the core again).
		burst.spells_on = run_spells_arg == "on"
	if burst != null or not spells_pick.is_empty():
		physics_frame.connect(_on_physics_frame)

func _is_tick_burst(value: String) -> bool:
	var parts := value.split(",")
	return parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int()

## One sentence for the first argument problem, or "". Runs before anything is loaded.
func _check_args() -> String:
	var user_args := OS.get_cmdline_user_args()
	if not contract_dir.is_empty():
		var absolute := contract_dir if contract_dir.is_absolute_path() else ProjectSettings.globalize_path("res://" + contract_dir)
		if not ("/_local/" in absolute.replace("\\", "/") + "/"): return "--dump-contracts=%s must be a folder under _local/" % contract_dir
		contract_dir = absolute
		if DirAccess.make_dir_recursive_absolute(contract_dir) != OK: return "--dump-contracts folder cannot be created: " + contract_dir
	if not run_spells_arg.is_empty() and run_spells_arg != "on":
		return "--run-spells=%s is unknown (on)" % run_spells_arg
	if not descent_arg.is_empty():
		if not DescentPolicy.valid(descent_arg) or descent_arg == "off": return "--descent=%s is unknown (now, hold, panic)" % descent_arg
		var trial := ""
		for arg in user_args:
			if arg.begins_with("--chapter1-trial="): trial = arg
		if not trial.contains("descent") or not "--chapter1-profile-off" in user_args:
			return "--descent needs --chapter1-trial=descent,.. and --chapter1-profile-off"
	if not spells_pick.is_empty():
		if spells_pick != "synergy": return "--spells-pick=%s is unknown (synergy)" % spells_pick
		if run_spells_arg != "on": return "--spells-pick needs --run-spells=on"
	if not title_input.is_empty():
		if not title_input in ["keys","pad"]: return "--title-input=%s is unknown (keys or pad)" % title_input
		if profile_fixture != "l8": return "--title-input needs --profile-fixture=l8 (the skill tree and the stash handle are part of the path)"
		if tree_shots or result_mock or not flow_shots.is_empty() or menu_tour or notice_shots or not burst_arg.is_empty():
			return "--title-input cannot be combined with --tree-shots, --result-mock, --flow-shots, --menu-tour, --notice-shots or --burst"
	if not profile_fixture.is_empty() and not profile_fixture in ["empty","l8","rejected"]:
		return "--profile-fixture=%s is unknown (empty, l8 or rejected)" % profile_fixture
	if not profile_fixture.is_empty() and not "--chapter1-profile-off" in user_args:
		return "--profile-fixture needs --chapter1-profile-off (the user's own save must never be opened)"
	if tree_shots and profile_fixture != "l8":
		return "--tree-shots needs --profile-fixture=l8 (without it the skill tree has nothing to open and the flow would wait forever)"
	if tree_shots and (not flow_shots.is_empty() or result_mock or notice_shots):
		return "--tree-shots cannot be combined with --flow-shots, --result-mock or --notice-shots"
	if not flow_shots.is_empty() and not flow_shots in ["abandon","defeat","quit"]:
		return "--flow-shots=%s is unknown (abandon, defeat or quit)" % flow_shots
	if flow_shots == "abandon" and profile_fixture.is_empty():
		# Without a profile the abandon flow reads view.profile.state (empty under --chapter1-profile-off) at its fourth stage,
		# raises a script error in every frame from then on and never ends (seen 2026-11-20): the fixture is part of the flow.
		return "--flow-shots=abandon needs --profile-fixture=empty (or l8) and --chapter1-profile-off; without a profile it never finishes"
	if not flow_shots.is_empty() and profile_fixture == "rejected":
		return "--flow-shots cannot be combined with --profile-fixture=rejected"
	if not reject_choice in ["play","fresh"]:
		return "--reject-choice=%s is unknown (play or fresh)" % reject_choice
	if "--reject-choice=fresh" in user_args and profile_fixture != "rejected":
		return "--reject-choice only applies to --profile-fixture=rejected"
	if not shots_dir.is_empty() and DisplayServer.get_name() == "headless":
		return "--shots needs a real renderer: run without --headless"
	if not asset_usage_path.is_empty():
		if not (asset_usage_path.begins_with("_local/") or asset_usage_path.begins_with("res://_local/")):
			return "--asset-usage=%s must be a path under _local/" % asset_usage_path
		var usage_folder := asset_usage_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(usage_folder) and DirAccess.make_dir_recursive_absolute(usage_folder) != OK:
			return "--asset-usage folder cannot be created: "+usage_folder
	if menu_tour:
		if asset_usage_path.is_empty(): return "--menu-tour needs --asset-usage"
		if profile_fixture != "l8": return "--menu-tour needs --profile-fixture=l8"
		if tree_shots or result_mock or not flow_shots.is_empty() or notice_shots or not burst_arg.is_empty():
			return "--menu-tour cannot be combined with --tree-shots, --result-mock, --flow-shots, --notice-shots or --burst"
	if burst_frames_given and burst_arg.is_empty():
		return "--burst-frames needs --burst"
	if not burst_arg.is_empty():
		if shots_dir.is_empty(): return "--burst needs --shots=<dir> (the frames are screenshots)"
		if burst_frames < 1 or burst_frames > 60: return "--burst-frames=%d is out of range (1 to 60)" % burst_frames
		if tree_shots or result_mock or not flow_shots.is_empty() or profile_fixture == "rejected":
			return "--burst follows the normal pilot run; it cannot be combined with --tree-shots, --result-mock, --flow-shots or --profile-fixture=rejected"
	if not out_path.is_empty():
		var folder := out_path.get_base_dir()
		if not folder.is_empty() and not DirAccess.dir_exists_absolute(folder) and DirAccess.make_dir_recursive_absolute(folder) != OK:
			return "--dump folder cannot be created: "+folder
	return ""

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
	# Schema 4 keeps its journal copies in a sub-folder.
	var copies := DirAccess.open(folder.path_join("revisions"))
	if copies != null:
		for file_name in copies.get_files(): out["revisions/"+file_name] = FileAccess.get_sha256(folder.path_join("revisions").path_join(file_name)).left(16)
	return out

## D5-U fixture: a real saved profile (so its journal copies are real), then the newest file is broken in structure by hand
## (two items get the same storage id; schema 4 sets a changed item aside instead of refusing, so a changed stat no longer refuses).
## The reader refuses it; the journal copies stay readable. Only ever under res://_local/.
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
	ok = ok and maker.record_run("fixture-a",[unique,magic,rare],[],false,10) and maker.wear_outfit(FROST_ID,"chapter1.outfit.frost.swim_1")
	ok = ok and maker.record_run("fixture-b",[],[],false,20)
	if not ok: push_error("rejected fixture could not be written: "+String(maker.error))
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(main))
	doc.items[1].storage_id = doc.items[0].storage_id
	var handle := FileAccess.open(main,FileAccess.WRITE)
	handle.store_string(JSON.stringify(doc,"  ")); handle.close()
	var profile = view.profile
	var loaded: bool = profile.configure(main,true,"","",pointer)
	# The app skips its own profile on --chapter1-profile-off; here the refused path is the thing under test.
	view._profile_off = false
	view._sync_profile(view._profile_error_text())
	rj_files_before = _file_hashes(rj_folder)
	print("HUD_DUMP_REJECT ",JSON.stringify({"phase":"fixture","configure":loaded,"available":profile.available,"kind":profile.reject_kind,"reason":profile.reject_reason,"resume":profile.resume_info(),"files":rj_files_before}))

func _describe(node: Node, depth: int, rows: Array, alpha := 1.0, clip := Rect2(), has_clip := false, tint := Color.WHITE, paints = null) -> void:
	# --dump-extra only: the text colour "fc" and the colour under it "bg" (layout_dump.gd) need the tint and the paints of the whole tree.
	var top := dump_extra and paints == null
	if top: paints = []
	var child_alpha := alpha
	var child_clip := clip
	var child_has_clip := has_clip
	var child_tint := tint
	if node is CanvasItem:
		child_alpha = alpha*node.modulate.a*node.self_modulate.a
		var own_tint: Color = node.modulate*node.self_modulate
		child_tint = Color(tint.r*own_tint.r,tint.g*own_tint.g,tint.b*own_tint.b,1.0)
	if node is Control:
		var c: Control = node
		var row := {"d":depth,"class":c.get_class(),"name":String(c.name),"visible":c.is_visible_in_tree(),
			"x":snappedf(c.global_position.x,.01),"y":snappedf(c.global_position.y,.01),"w":snappedf(c.size.x,.01),"h":snappedf(c.size.y,.01),
			"modulate":c.modulate.to_html(),"tooltip":c.tooltip_text}
		if c is Label or c is Button or c is RichTextLabel or c is LineEdit: row.text = String(c.get("text"))
		if c is BaseButton: row.disabled = c.disabled
		if c is Range: row.value = snappedf(c.value,.001); row.max = snappedf(c.max_value,.001)
		if c is TextureRect: row.texture = c.texture.resource_path if c.texture != null else ""
		if dump_extra: LayoutDump.extra(c,row,child_alpha,clip,has_clip,child_tint)
		rows.append(row)
		if paints != null:
			var paint: Dictionary = LayoutDump.paint_of(c,child_alpha)
			if not paint.is_empty():
				paint["i"] = rows.size()-1
				paints.append(paint)
		if c.clip_contents or c is ScrollContainer:
			var own := Rect2(c.global_position,c.size)
			child_clip = clip.intersection(own) if has_clip else own
			child_has_clip = true
	for child in node.get_children():
		_describe(child,depth+1,rows,child_alpha,child_clip,child_has_clip,child_tint,paints)
	if top: LayoutDump.fill_bg(rows,paints,node.get_viewport() != null and node.get_viewport().get_camera_3d() == null)

## Layout fields for tools/dev/hud_layout_check.py. Only with --dump-extra (shared with scene_shot.gd).
func _describe_extra(c: Control, row: Dictionary, alpha: float, clip: Rect2, has_clip: bool) -> void:
	LayoutDump.extra(c,row,alpha,clip,has_clip)

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
	if usage != null: usage.sample(root,int(view.run.tick),String(view.run.mode),label)
	if not shots_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(shots_dir)
		var image := root.get_viewport().get_texture().get_image()
		if image != null: image.save_png(shots_dir.path_join("%02d-%s.png" % [order.size(),label]))
	var visible := 0
	for row in rows:
		if row.visible: visible += 1
	print("HUD_DUMP ",JSON.stringify({"label":label,"controls":rows.size(),"visible":visible,"tick":view.run.tick,"mode":view.run.mode,"hash":JSON.stringify(rows).sha256_text().left(16)}))
	if not contract_dir.is_empty(): _dump_contract(label)

## --dump-contracts: what the adapter of the screen at this moment makes from the live run. Reads only; a missing adapter is skipped.
func _dump_contract(label: String) -> void:
	if not CONTRACT_MOMENTS.has(label): return
	var id_: String = CONTRACT_MOMENTS[label]
	var path := "res://chapter1/view/contracts/%s_contract.gd" % id_
	if not FileAccess.file_exists(path):
		print("HUD_CONTRACT_SKIP ",JSON.stringify({"moment":label,"screen":id_,"why":"no adapter yet"}))
		return
	var adapter: GDScript = load(path)
	var app_state := {}
	if id_ == "title":
		# The host's own state, the shape title_contract.gd takes (read only).
		app_state = view.hud.title_app_state()
	var contract: Variant = adapter.call("build",view.run,app_state)
	var file := FileAccess.open(contract_dir.path_join("%s.%s.json" % [id_,label]),FileAccess.WRITE)
	if file == null or not contract is Dictionary:
		push_error("hud_dump: cannot write the contract of "+label)
		return
	file.store_string(JSON.stringify(contract," "))
	file.close()
	print("HUD_CONTRACT ",JSON.stringify({"moment":label,"screen":id_,"keys":contract.size()}))

func _mark(key: String) -> bool:
	if done_marks.has(key): return false
	done_marks[key] = true
	return true

func _process(_delta: float) -> bool:
	if view == null or not view.is_inside_tree(): return true
	frame += 1
	# Every flow below returns early, and a script error in a frame aborts it before the old "frame > 400000" check at the end:
	# a stuck flow (a screen that never comes, a core that is gone) used to leave this window open for hours. Wall clock, not frames.
	if wall_limit_s > 0 and (Time.get_ticks_msec()-started_msec) > wall_limit_s*1000:
		push_error("hud_dump: wall-clock limit of %d s passed (--wall-limit=S, 0 = none); stopped at frame %d step %d" % [wall_limit_s,frame,step])
		print("HUD_DUMP_RESULT ",JSON.stringify({"error":"wall_limit","frame":frame,"step":step}))
		quit(4)
		return true
	if view.get("run") == null:
		push_error("hud_dump: the core is gone (view.run is null); stopped at frame %d" % frame)
		print("HUD_DUMP_RESULT ",JSON.stringify({"error":"run_missing","frame":frame}))
		quit(3)
		return true
	var run: RefCounted = view.run
	# R by the policy, through the app's own door (the key does the same): the cut-in, the release and the sweep are the app's.
	if not descent_arg.is_empty() and DescentPolicy.wants(run,descent_arg): view.call_descent()
	if usage != null: _usage_step(run)
	if burst != null:
		burst.poll(run,frame)
		burst.process(run,frame,func(): return root.get_viewport().get_texture().get_image())
	if not title_input.is_empty():
		return _title_input_flow()
	if menu_tour:
		return _menu_tour()
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
			if frame == 3:
				_title_settle()
			elif frame == 5:
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
	if burst != null and burst.complete() and end_frames < 0: end_frames = 20
	if end_frames >= 0:
		end_frames += 1
		# Let a burst that is still taking its frames finish before the end moment is dumped.
		if burst != null and (end_frames == 30 or end_frames == 200) and burst.busy():
			end_frames -= 1
			return false
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

func _on_physics_frame() -> void:
	if burst != null and view != null: burst.poll(view.run,frame)
	# Runs before the app's own physics step, so the built-in pilot never sees the offer. Where _choice_moment() owns the
	# offer (dump first, then pick) this stays out of the way.
	if not spells_pick.is_empty() and view != null and view.run.mode == "choice" and choice_wait < 0 and not (choice_dumps < 2 and step in [1,3]):
		_spells_pick(view.run)

## RS0: the shipped run_spells.json with "enabled": true, parked in the core of this process before start().
func _enable_run_spells() -> String:
	var problem := SpellsPick.enable(view.run)
	if not problem.is_empty(): return problem
	print("HUD_SPELLS_ON ",JSON.stringify({"pick":spells_pick}))
	return ""

## RS0 pick rule: chapter1/tests/spells_pick.gd (shared with report_audio_requests.gd and sfx_capture.gd since AU-RS0).
func _spells_pick(run: RefCounted) -> void:
	var row := SpellsPick.pick(run,"hud_dump")
	if row.is_empty(): return
	spells_picks.append(row)
	print("HUD_SPELLS_PICK ",JSON.stringify(row))
	# The built-in pilot hands its pick events to the recorder the same way (chapter_one._pilot_input).
	view.recorder.consume(run.events)

func _usage_step(run: RefCounted) -> void:
	var interval := 10 if (tree_shots or menu_tour or result_mock or not flow_shots.is_empty() or profile_fixture == "rejected") else 30
	if frame < 40 or frame%interval == 0:
		var sprite_label := "tick2400" if int(run.tick) >= 2400 and _mark("usage-2400") else ""
		usage.sample(root,int(run.tick),String(run.mode),"",sprite_label)
	else:
		usage.sample_audio(int(run.tick))

func _finish() -> void:
	if usage != null:
		usage.sample(root,int(view.run.tick),String(view.run.mode),"finish","end")
		var usage_file := FileAccess.open(asset_usage_path,FileAccess.WRITE)
		if usage_file == null: push_error("cannot write the asset usage: "+asset_usage_path)
		else:
			usage_file.store_string(JSON.stringify(usage.report(view,{"primary":primary,"seed":view.seed_,"until":until_tick,"final_tick":int(view.run.tick),"mode":String(view.run.mode),
				"flags":{"tree_shots":tree_shots,"result_mock":result_mock,"flow_shots":flow_shots,"profile_fixture":profile_fixture,"notice_shots":notice_shots}}),"  "))
			usage_file.close()
			print("HUD_ASSET_USAGE ",JSON.stringify({"path":asset_usage_path,"samples":usage.samples,"files":usage.files.size()}))
	if burst != null and not shots_dir.is_empty(): burst.write_index(shots_dir.path_join("burst.json"))
	if not scene_path.is_empty():
		var scene_file := FileAccess.open(scene_path,FileAccess.WRITE)
		scene_file.store_string(JSON.stringify({"order":order,"scenes":scenes}))
		scene_file.close()
	if not out_path.is_empty():
		var file := FileAccess.open(out_path,FileAccess.WRITE)
		var document := {"order":order,"dumps":dumps}
		var trial := TrialDocs.switches(OS.get_cmdline_user_args())
		if not trial.is_empty(): document["trial"] = trial
		if dump_extra:
			document["meta"] = {"canvas":[root.get_visible_rect().size.x,root.get_visible_rect().size.y],"window":[root.size.x,root.size.y],"extra":true}
		if file == null:
			push_error("cannot write the dump: "+out_path)
			quit(1)
			return
		file.store_string(JSON.stringify(document))
		file.close()
	if run_spells_arg == "on":
		var owned := {}
		var spells_view: Dictionary = view.run.run_spells_view()
		for id_ in spells_view.get("spells",{}): owned[id_] = spells_view.spells[id_].axis
		var ring_pick := {}
		for row in spells_picks:
			if row.id.begins_with("unlock:") and row.id.ends_with("_ring"): ring_pick = {"level":row.level,"tick":row.tick,"id":row.id}; break
		print("HUD_SPELLS ",JSON.stringify({"enabled":spells_view.get("enabled",false),"pick":spells_pick,"picks":spells_picks.size(),"ring":ring_pick,"owned_axes":owned,"builtin_pilot_selections":view.full_pilot.selections.size()}))
	print("HUD_DUMP_RESULT ",JSON.stringify({"labels":order,"final_tick":view.run.tick,"mode":view.run.mode,"kills":view.run.kills}))
	if "title_contract_builds" in view.hud: print("HUD_TITLE_CONTRACTS ",JSON.stringify({"builds":view.hud.title_contract_builds,"frames":frame}))
	if burst != null: print("HUD_BURST_SUMMARY ",JSON.stringify(burst.summary()))

## The growth offer is on screen for a single frame in a pilot run (the pilot picks on the next physics step), and the
## dump used to fire before the HUD had built the cards. Park the pilot while the offer is dumped, then let it go on.
func _choice_moment(run: RefCounted) -> void:
	if choice_dumps >= 2: return
	if run.mode == "choice" and choice_wait < 0:
		choice_wait = frame+choice_frames
		view._pilot = false
	elif choice_wait >= 0 and frame >= choice_wait:
		choice_dumps += 1; _dump("choice-%d" % choice_dumps)
		choice_wait = -1
		if not spells_pick.is_empty(): _spells_pick(run)
		view._pilot = true

func _wait(frames: int) -> int:
	return frame+frames

var flow_next := 0
var flow_stage := 0

func _press(button: Control) -> void:
	# Real GUI routing: a left click at the button centre, in window pixels.
	if button == null:
		push_error("hud_dump: nothing to press (the control is not on screen)")
		return
	var centre: Vector2 = view.get_window().get_final_transform()*button.get_global_rect().get_center()
	# A player's pointer arrives before the click (the first screen reads the pointer for its hover and its handles).
	var motion := InputEventMouseMotion.new()
	motion.position = centre; motion.global_position = centre
	view.get_window().push_input(motion)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = centre; event.global_position = centre; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
		view.get_window().push_input(event)

func _hover(button: Control) -> void:
	if button == null: return
	var centre: Vector2 = view.get_window().get_final_transform()*button.get_global_rect().get_center()
	var event := InputEventMouseMotion.new()
	event.position = centre; event.global_position = centre
	view.get_window().push_input(event)

## The first screen's own control by node name (the visible witch's handle has the plain name, the others carry a tail). null when it is not there.
func _title_node(node_name: String) -> Control:
	return view.hud.root.find_child(node_name, true, false) as Control

## The first screen opens settled (no intro). A host without the call (the base commit of equiv.py) does nothing here.
func _title_settle() -> void:
	if view.hud.has_method("title_settle"): view.hud.title_settle()

func _key(code: int) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code as Key; event.pressed = pressed
		view.get_window().push_input(event)

func _joy(button: int) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button as JoyButton; event.pressed = pressed
		view.get_window().push_input(event)

## [label, action, frames to wait]. The first screen by the keyboard (keys) or by the pad (pad) alone.
func _title_input_steps() -> Array:
	var out: Array = []
	if title_input == "keys":
		for item in [["E", KEY_E, 6], ["E", KEY_E, 6], ["E-wrap", KEY_E, 6], ["Q-wrap", KEY_Q, 6], ["2", KEY_2, 6], ["Tab", KEY_TAB, 4], ["Enter-tree", KEY_ENTER, 24], ["tree", -1, 2],
				["Q-over-tree", KEY_Q, 4], ["Esc-closes-tree", KEY_ESCAPE, 24], ["Tab", KEY_TAB, 4], ["Enter-stash", KEY_ENTER, 10], ["stash", -1, 2], ["Esc-closes-stash", KEY_ESCAPE, 10],
				["Esc-window", KEY_ESCAPE, 40], ["esc-window", -1, 2], ["M", KEY_M, 8], ["muted", -1, 2], ["Esc-closes-window", KEY_ESCAPE, 40], ["Tab", KEY_TAB, 4], ["Enter-start", KEY_ENTER, 10]]:
			out.append([item[0], item[1], item[2]])
	else:
		# The d-pad is ui_left/right/up/down. Button A / B are ui_accept / ui_cancel only where the InputMap binds them (TITLE_INPUT_MAP says whether it does here):
		# the A steps are tried either way, and the start is then given by the Enter key when A did nothing (code -3).
		for item in [["pad-right", JOY_BUTTON_DPAD_RIGHT, 6], ["pad-right", JOY_BUTTON_DPAD_RIGHT, 6], ["pad-left", JOY_BUTTON_DPAD_LEFT, 6], ["pad-down", JOY_BUTTON_DPAD_DOWN, 4],
				["pad-down", JOY_BUTTON_DPAD_DOWN, 4], ["pad-up", JOY_BUTTON_DPAD_UP, 4], ["pad-up", JOY_BUTTON_DPAD_UP, 4], ["pad-A", JOY_BUTTON_A, 10], ["Enter-start-if-A-did-nothing", -3, 10]]:
			out.append([item[0], item[1], item[2]])
	return out

func _ti_snapshot(label: String) -> void:
	var hud = view.hud
	var resume := _title_node("TitleResume")
	var screen: Control = hud.title_screen()
	var row := {"after": label, "frame": frame, "witch": hud.menu_witch_index(), "tree_open": hud.skill_tree_is_open(), "stash_open": hud.stash_open,
		"esc_window": resume != null and resume.is_visible_in_tree(), "mode": view.run.mode, "settled": screen != null and screen.is_settled(), "state": screen.state if screen != null else "", "ui_focus": screen.ui_focus if screen != null else -1, "toast": String(hud.toast.text) if hud.toast.visible else ""}
	ti_log.append(row)
	print("TITLE_INPUT ", JSON.stringify(row))
	if label in ["tree", "stash", "esc-window", "muted"]: _dump("title-input-"+label)

func _title_input_flow() -> bool:
	if frame > 3000:
		push_error("title input flow did not finish (step %d)" % ti_step)
		quit(1)
		return true
	if frame < ti_next: return false
	if ti_steps.is_empty():
		if frame < 5: return false
		_title_settle()
		var pad_bound := []
		for action in ["ui_accept", "ui_cancel"]:
			var has_pad := false
			for event in InputMap.action_get_events(action):
				if event is InputEventJoypadButton: has_pad = true
			pad_bound.append([action, has_pad])
		print("TITLE_INPUT_MAP ", JSON.stringify(pad_bound))
		ti_steps = _title_input_steps()
		ti_next = frame+25   # settled + the pick lock
		return false
	if ti_pending != "":
		_ti_snapshot(ti_pending); ti_pending = ""
	if ti_step < ti_steps.size():
		var entry: Array = ti_steps[ti_step]
		ti_step += 1
		var code := int(entry[1])
		if code == -2: _key(KEY_ESCAPE)
		elif code == -3:
			if view.hud.title_screen() != null and view.hud.title_screen().state == "ready": _key(KEY_ENTER)
		elif code >= 0:
			if title_input == "keys": _key(code)
			else: _joy(code)
		ti_pending = String(entry[0])
		ti_next = frame+int(entry[2])
		if ti_step == ti_steps.size(): ti_deadline = frame+300
		return false
	if (view.run.mode == "playing" and view.run.tick >= 30) or frame > ti_deadline:
		_ti_snapshot("started")
		_finish()
		return true
	return false

## T7-0: menu -> each witch -> her skill tree -> back. Only samples the usage probe; writes nothing else.
func _menu_tour() -> bool:
	var hud = view.hud
	if frame > 3000:
		push_error("menu tour did not finish (stage %d)" % mt_stage)
		quit(1)
		return true
	if frame < mt_next: return false
	var id: String = TOUR_SKILLS[mt_index] if mt_index < TOUR_SKILLS.size() else ""
	match mt_stage:
		0:
			if frame < 5: return false
			_title_settle()
			usage.sample(root,0,String(view.run.mode),"tour-menu-start")
			mt_stage = 1
		1:
			# The pointer of the last click still lies over the previous witch's door and would take the focus back: it moves over this witch's door first.
			_hover(_title_node("Door%d" % mt_index))
			hud.menu_select_skill(id)
			mt_next = frame+26; mt_stage = 2   # the door takes 0.30 s (18 frames) to open and the text bundle comes with it
		2:
			usage.sample(root,0,String(view.run.mode),"tour-menu-"+id)
			_press(_title_node("TitleTree"))
			mt_next = frame+14; mt_stage = 3
		3:
			OS.delay_msec(300)
			usage.sample(root,0,String(view.run.mode),"tour-tree-"+id)
			mt_log.append({"skill":id,"tree_visible":hud.skill_panel != null and hud.skill_panel.visible})
			print("MENU_TOUR ",JSON.stringify(mt_log[mt_log.size()-1]))
			# Esc closes an open tree; with no tree open it would open the first screen's Esc window, so it is sent only to a tree.
			if hud.skill_tree_is_open(): _key(KEY_ESCAPE)
			mt_next = frame+8; mt_stage = 4
		4:
			mt_log[mt_log.size()-1]["tree_closed"] = hud.skill_panel == null or not hud.skill_panel.visible
			mt_index += 1
			mt_stage = 1 if mt_index < TOUR_SKILLS.size() else 5
		5:
			_finish()
			return true
	return false

func _tree_flow() -> bool:
	var hud = view.hud
	var panel: Control = hud.skill_panel
	if frame > 3000:
		push_error("tree flow did not finish (stage %d): the skill tree never opened" % flow_stage)
		quit(1)
		return true
	if frame < flow_next: return false
	match flow_stage:
		0:
			if frame < 5: return false
			_title_settle(); flow_next = frame+3; flow_stage = 20
		20:
			_dump("menu")
			# Mouse-over and focus are one state on the first screen: move the mouse over the third door, wait out its 0.12 s, check which witch the screen looks at.
			_hover(_title_node("Door2")); flow_next = frame+14; flow_stage = 10
		10:
			flow_log.append({"hover_takes_focus":hud.menu_witch_index() == 2,"witch_after_hover":hud.menu_witch_index()})
			# The mouse stays where a player would leave it: over the second door (a pointer left over the third one would take the focus back).
			_hover(_title_node("Door1"))
			hud.menu_select_skill("chapter1.skill.frost")
			flow_next = frame+24; flow_stage = 1
		1:
			_dump("menu-frost"); _press(_title_node("TitleTree")); flow_next = frame+10; flow_stage = 2
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
			_dump("menu-after"); _press(_title_node("TitleTree")); flow_next = frame+10; flow_stage = 9
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

func _find_button(button_name: String) -> Control:
	return view.hud.root.find_child(button_name,true,false) as Control

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
		view._sync_profile(view._profile_error_text())
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
			# The screen waited under the notice (its clock stood still): open it settled, then press the start of the first witch.
			hud.menu_select_skill("chapter1.skill.ember"); _title_settle()
			rj_next = frame+30; rj_stage = 61
		61:
			_press(_title_node("TitleStart")); rj_next = frame+4; rj_until = frame+150; rj_stage = 7
		7:
			# The press starts the 1.2 s confirm beat; the app then refuses (the save file is refused) and the notice comes up again.
			if not hud.flow_dialog_open() and view.run.mode != "playing" and frame < rj_until: return false
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
		# The Esc window of the first screen (T13): the screen opens settled, Esc opens the small window, its quit button ends the process.
		if frame == 4:
			_title_settle()
		elif frame == 40:
			_key(KEY_ESCAPE)
		elif frame == 52:
			_dump("title-menu")
			_finish()   # the process ends on the next press: write the dump now
			_press(_find_button("QuitGame"))
			fl_next = frame+60
		elif frame > 300:
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
			_title_settle(); fl_next = frame+3; fl_stage = 100
		100:
			_dump("menu"); _flow_line("menu")
			# The witch the run starts with is the one the screen looks at (a player picked her there).
			view.hud.menu_select_skill(primary)
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
			print("FLOW_CHECK ",JSON.stringify({"menu_witch_after_return":hud.menu_witch_index(),"title_screen":hud.title_screen() != null}))
			# The doors open again by themselves (the intro); settle them, then start the other witch through the confirm beat.
			hud.menu_select_skill(TOUR_SKILLS[other]); _title_settle()
			fl_next = frame+30; fl_stage = 60
		60:
			_press(_title_node("TitleStart")); fl_next = frame+40; fl_stage = 61
		61:
			# Mid-way of the 1.2 s confirm beat: the other doors shut, the chosen one opens over the whole screen.
			_dump("flow-confirm-beat"); _flow_line("flow-confirm-beat")
			fl_next = frame+4; fl_stage = 7
		7:
			if view.run.tick >= 120 and view.run.mode == "playing":
				_dump("flow-playing-after-return-120"); _flow_line("flow-playing-after-return-120")
				_finish(); return true
	if frame > 30000:
		push_error("run flow timed out"); _finish(); return true
	return false
