extends Node3D
## Flattened by tools/dev/flatten_chain.py from chapter1/chapter_one_input48.gd.
## Methods named x__tag are the earlier layers of x; calls between them were super calls.

# ---- chapter1/chapter_view.gd ----
## C2 scene glue. Fixed-tick core owns all gameplay; UI/actors/VFX only present it.
const Audio=preload("res://chapter1/presentation/combat_audio.gd")
const FrameProbe=preload("res://chapter1/presentation/frame_probe.gd")
const AudioRoutes=preload("res://chapter1/presentation/audio_routes.gd")
## Assigned in _init (chapter_core, chapter_world, chapter_actors, chapter_effects, chapter_hud).
var run
var world
var actors
var effects
const CombatJuice=preload("res://chapter1/view/fx/combat_juice.gd")
## Hit feedback, spell lights and the overall look. Off with --chapter1-no-juice.
var juice: RefCounted
## The descent's screen (D15 U-2): edge aura, cut-in, sweep. Makes no node until a run with the descent on asks for one.
const DescentFx=preload("res://chapter1/view/fx/descent_fx.gd")
var descent_fx=DescentFx.new()
## The cut-in hold in wall seconds (the core stands still in mode "descent"): the app lets go after descent_fx.hold_limit() even if the picture never does
## (2.5 s; with the demon's video the video's length more: A11 12.3.2).
var _descent_wait := 0.0
## Gamepad: no pad input exists in this app yet (D15 A2.3, recommended Y); the button is named here for when it does.
const DESCENT_PAD_BUTTON := JOY_BUTTON_Y
## The pad's view button opens and closes the gear window (D21 3.1), also from the pause window.
const EQUIPMENT_PAD_BUTTON := JOY_BUTTON_BACK
var hud
var audio=Audio.new()
## Core event -> sound request (the same mapping the request recorder uses). Its only state is the ring pulse habituation.
var audio_routes=AudioRoutes.new()
var _frame_probe=FrameProbe.new()
var _probe_quit_after_complete := false
## Verification arguments and the F1 diagnostics screen only work in debug builds and builds with the "qa" feature tag.
## Store builds ignore them, because a player can put arguments on the Steam launch line.
var qa_allowed := OS.is_debug_build() or OS.has_feature("qa")
var primary := "chapter1.skill.ember"
var seed_ := 90131
var _wall_age := 0.0
var _quit_after := -1.0
var _pilot := false
var _capture_dir := ""
var _captured: Dictionary={}
var _last_audio_event := -1
var _last_result := ""
var _frame_ms: Array[float]=[]
var _qa_quit_sent := false
var _qa_ignore_focus := false
var _has_move_target := false
var _move_target := Vector2.ZERO
var _qa_input_file: FileAccess
var _qa_run_sequence := 0
var _qa_state_sequence := 0
var _qa_last_capture_mode := ""
var _qa_pending_capture_mode := ""
var _audio_previous := Vector2.ZERO
var _audio_step_distance := 0.0

func _exit_tree() -> void:
	_frame_probe.finish("scene_exit")
	# RefCounted presenters must release their scene owner before shutdown.
	if _qa_input_file:_qa_input_file.close();_qa_input_file=null
	actors.view=null;effects.view=null;world.root=null
	for voice in audio.voices:
		if is_instance_valid(voice):voice.stop();voice.stream=null
	audio.voices.clear();audio.streams.clear();audio.ambience=null

func _user_args() -> PackedStringArray:
	return OS.get_cmdline_user_args() if qa_allowed else PackedStringArray()
func _ready__chapter() -> void:
	DisplayServer.window_set_title("Catena · Chapter 1")
	world.setup(self)
	actors.vat_walker_enabled="--chapter1-vat-walker" in _user_args()
	actors.hero_models_enabled="--chapter1-hero-models" in _user_args()
	actors.setup(self)
	effects.setup(self)
	if not "--chapter1-no-juice" in _user_args():
		juice=CombatJuice.new();juice.setup(self);juice.apply_look(world)
	descent_fx.setup(self)
	for arg in _user_args():
		if arg=="--chapter1-descent-cutin=short":descent_fx.cutin_short=true
		elif arg=="--chapter1-descent-motion=reduced":descent_fx.reduced_motion=true
		elif arg=="--chapter1-descent-flash=off":descent_fx.flash_scale=0.0
		elif arg=="--chapter1-descent-flash=weak":descent_fx.flash_scale=0.5
		elif arg=="--chapter1-descent-shake=off":descent_fx.shake_scale=0.0
		elif arg=="--chapter1-descent-shake=weak":descent_fx.shake_scale=0.5
		elif arg=="--chapter1-descent-numbers=off":descent_fx.numbers_on=false
		elif arg in ["--chapter1-descent-cutscene=always","--chapter1-descent-cutscene=first","--chapter1-descent-cutscene=off"]:descent_fx.cutscene_mode=arg.trim_prefix("--chapter1-descent-cutscene=")
	hud.temporary_art=actors.temporary_art
	hud.setup(self)
	hud.start.connect(start_run)
	hud.choice.connect(choose)
	hud.grace_reroll.connect(grace_reroll)
	hud.grace_banish.connect(grace_banish)
	hud.grace_hold.connect(grace_hold)
	hud.equipment.connect(open_equipment)
	hud.close_equipment.connect(close_equipment)
	hud.equip_item.connect(equip_item)
	hud.pause_toggle.connect(toggle_pause)
	hud.retry.connect(retry)
	hud.menu_return.connect(return_to_menu)
	hud.abandon_request.connect(abandon_run)
	hud.quit_request.connect(quit_game)
	hud.profile_open_folder.connect(open_profile_folder)
	hud.profile_play_without_save.connect(play_without_save)
	hud.profile_start_fresh.connect(start_fresh_profile)
	hud.mute_toggle.connect(toggle_mute)
	hud.motion_toggle.connect(func(enabled: bool):world.set_reduced_motion(not enabled);descent_fx.reduced_motion=not enabled)
	audio.setup(self)
	audio.set_master_volume(.80)
	audio.set_paused(true)
	get_window().focus_exited.connect(func():
		if not _qa_ignore_focus and run.mode not in ["menu","victory","defeat"]:run.set_paused(true))
	var autostart := false
	var input_log_path := ""
	var frame_probe_dir := ""
	var probe_arg_count := 0
	for arg in _user_args():
		if arg=="--chapter1-start":autostart=true
		elif arg=="--chapter1-pilot":_pilot=true
		elif arg=="--chapter1-qa-ignore-focus":_qa_ignore_focus=true
		elif arg.begins_with("--chapter1-frame-probe-dir="):
			probe_arg_count+=1;frame_probe_dir=arg.trim_prefix("--chapter1-frame-probe-dir=")
		elif arg=="--chapter1-frame-probe-quit":_probe_quit_after_complete=true
		elif arg.begins_with("--chapter1-qa-input-log="):input_log_path=arg.trim_prefix("--chapter1-qa-input-log=")
		elif arg.begins_with("--chapter1-primary="):primary=arg.trim_prefix("--chapter1-primary=")
		elif arg.begins_with("--chapter1-quit-after="):_quit_after=float(arg.trim_prefix("--chapter1-quit-after="))
		elif arg.begins_with("--chapter1-capture-dir="):_capture_dir=arg.trim_prefix("--chapter1-capture-dir=")
		elif arg.begins_with("--chapter1-seed="):seed_=int(arg.trim_prefix("--chapter1-seed="))
	if not input_log_path.is_empty():
		var allowed := ProjectSettings.globalize_path("res://_local/").replace("\\","/")
		var quality_allowed := ProjectSettings.globalize_path("res://_local/").replace("\\","/")
		var path := input_log_path.replace("\\","/").simplify_path()
		if (path.begins_with(allowed) or path.begins_with(quality_allowed)) and not FileAccess.file_exists(path):
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			_qa_input_file=FileAccess.open(path,FileAccess.WRITE)
		else:push_error("QA input log must be a new file inside the new C2 evidence directory")
	if probe_arg_count>1 or (probe_arg_count==1 and frame_probe_dir.is_empty()) or (_probe_quit_after_complete and probe_arg_count!=1):
		push_error("Frame probe requires exactly one nonempty output flag");get_tree().quit(1);return
	if not frame_probe_dir.is_empty():
		if not _frame_probe.configure(frame_probe_dir,self,{"pilot":_pilot,"qa_ignore_focus":_qa_ignore_focus,"captures_enabled":not _capture_dir.is_empty(),"input_log_enabled":not input_log_path.is_empty(),"wall_quit_enabled":_quit_after>0,"seed":seed_,"primary":primary}):
			get_tree().quit(1);return
	if autostart:start_run(primary)
	hud.sync(run,0)
	var actor_states: Dictionary={}
	for kind in actors.sprite_definitions:actor_states[kind]=Array(actors.sprite_definitions[kind].frames.get_animation_names())
	print("CHAPTER1_READY ",JSON.stringify({"scene":"chapter1/Chapter1.tscn","temporary_actor_art":actors.temporary_art,"actor_states":actor_states,"raw_texture_fallbacks":actors.raw_texture_fallbacks,"scope":"representative encounter, not completed chapter","pilot":_pilot,"qa_ignore_focus":_qa_ignore_focus}))

func start_run__chapter(id_: String) -> void:
	primary=id_
	if not run.start(seed_,primary):
		push_error(str(run.errors));get_tree().quit(1);return
	_qa_run_sequence+=1
	actors.reset();effects.reset();hud.reset();audio.reset();audio_routes.reset()
	if juice!=null:juice.reset()
	descent_fx.reset();_descent_wait=0.0
	_last_audio_event=-1;_last_result="";_captured.clear();_frame_ms.clear()
	_has_move_target=false
	_audio_previous=run.hero.position;_audio_step_distance=0
	audio.set_paused(false)
	hud.notify("경험치와 장비를 회수하며 "+Loc.t("enemy.champion.2.name")+"을 준비하세요")

func retry() -> void:
	seed_+=1
	start_run(primary)

func choose(token: String, card_id: String) -> void:
	if run.choose(token,card_id):
		hud.invalidate();audio.play_ui("equip",run.tick)
	_consume_events()

## The grace screen's tools (D13 K3a), asked of the core exactly as the pick is: the core decides, the screen is rebuilt from what it now says.
func grace_reroll(token: String) -> void:
	if run.reroll_offer(token):hud.invalidate()
	_consume_events()

func grace_banish(token: String, card_id: String) -> void:
	if run.banish_offer(token,card_id):hud.invalidate()
	_consume_events()

func grace_hold(token: String, card_id: String) -> void:
	if run.hold_offer(token,card_id):hud.invalidate()
	_consume_events()

func open_equipment() -> void:
	if run.open_inventory():
		# From the pause window (A10 W2, D21 3.1): the pause lifts and the gear window takes its place; closing the window goes back to the run.
		if run.mode=="paused":run.set_paused(false)
		hud.invalidate()

func close_equipment() -> void:
	run.close_inventory();hud.invalidate()

func equip_item(uid: int) -> void:
	if run.equip(uid):
		hud.notify("장비 효과를 적용했습니다");hud.invalidate();audio.play_ui("equip",run.tick)
	_consume_events()

func toggle_pause() -> void:
	if run.mode=="menu" or run.mode in ["victory","defeat"]:return
	run.set_paused(run.mode!="paused")
	hud.invalidate()

func toggle_mute() -> void:
	audio.set_muted(not audio.muted)
	hud.notify("소리 꺼짐" if audio.muted else "소리 켜짐")

func _input__chapter(event: InputEvent) -> void:
	_qa_log_key(event,"input")

func _qa_log_key(event: InputEvent, phase: String) -> void:
	if _qa_input_file==null or not event is InputEventKey:return
	_qa_input_file.store_string(JSON.stringify({"phase":phase,"mode":run.mode,"tick":run.tick,"keycode":event.keycode,"physical_keycode":event.physical_keycode,"pressed":event.pressed,"echo":event.echo})+"\n")
	_qa_input_file.flush()

func _unhandled_key_input__chapter(event: InputEvent) -> void:
	_qa_log_key(event,"unhandled_key_input")
	if not event is InputEventKey or not event.pressed or event.echo:return
	# A confirm window or the refused-save notice answers Esc itself; nothing behind it reacts.
	if hud.flow_dialog_open():return
	# Menu shortcuts use logical keys. Native QA proved injected input carries
	# correct keycode but a constant unrelated physical scan code; WASD stays physical.
	var shortcut: int=event.keycode if event.keycode!=0 else event.physical_keycode
	match shortcut:
		KEY_ESCAPE:
			if run.mode=="inventory":close_equipment()
			else:toggle_pause()
		KEY_I:
			if run.mode=="inventory":close_equipment()
			else:open_equipment()
		KEY_SPACE:
			_has_move_target=false
			run.request_dash(_move_input())
		KEY_M:toggle_mute()
		KEY_F1:
			if qa_allowed:hud.debug.visible=not hud.debug.visible
		KEY_R:
			# Only once the result window is on screen (D4 F10); unsaved rewards are asked about first (F8).
			if run.mode in ["victory","defeat"] and hud.result_revealed():hud.request_leave("retry")


func _move_input() -> Vector2:
	var x := float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A))
	var y := float(Input.is_physical_key_pressed(KEY_W))-float(Input.is_physical_key_pressed(KEY_S))
	var right := Vector2(world.camera.global_basis.x.x,world.camera.global_basis.x.z).normalized()
	var forward := Vector2(-world.camera.global_basis.z.x,-world.camera.global_basis.z.z).normalized()
	if x!=0 or y!=0:_has_move_target=false
	elif _has_move_target and not run.hero.is_empty():
		var delta: Vector2=_move_target-run.hero.position
		if delta.length()>.12:return delta.normalized()
		_has_move_target=false
	return (right*x+forward*y).limit_length(1.0)

func _physics_process(_delta: float) -> void:
	if _qa_quit_sent or run.mode=="menu":return
	var movement := _pilot_input() if _pilot else _move_input()
	run.step(movement)
	_consume_events()
	if run.mode=="playing":
		_audio_step_distance+=run.hero.position.distance_to(_audio_previous)
		if _audio_step_distance>1.15:
			audio.play("step",run.tick);_audio_step_distance=0
	_audio_previous=run.hero.position


func _consume_events__chapter() -> void:
	effects.consume(run.events)
	if juice!=null:juice.consume(run.events)
	descent_fx.consume(run.events)
	actors.consume(run.events)
	var fresh: Array=[]
	for event in run.events:
		if int(event.seq)<=_last_audio_event:continue
		_last_audio_event=int(event.seq)
		fresh.append(event)
	_play_routes(audio_routes.route(fresh,run.spells,run.tick))

## Plays what audio_routes.gd made of the events: one request each, UI cues through play_ui.
func _play_routes(list: Array) -> void:
	for request in list:
		if request.ui:audio.play_ui(request.cue,run.tick)
		else:audio.play(request.cue,run.tick,request.gain_db)

func _process__chapter(delta: float) -> void:
	if _qa_quit_sent:return
	_frame_probe.observe(self,run)
	_wall_age+=delta
	if run.mode=="playing" and _frame_ms.size()<15000:_frame_ms.append(delta*1000)
	if not run.hero.is_empty():
		world.update_camera(run.hero.position,delta)
		actors.sync(run,delta)
		effects.sync(run,delta)
		if juice!=null:juice.sync(run,delta)
	descent_fx.sync(run,delta)
	hud.sync(run,delta)
	audio.set_paused(run.mode!="playing" or _qa_quit_sent)
	if not _capture_dir.is_empty():
		# Wait one stable render frame so the saved image contains the new modal.
		if run.mode!=_qa_last_capture_mode:
			_qa_last_capture_mode=run.mode;_qa_pending_capture_mode=run.mode
		elif not _qa_pending_capture_mode.is_empty():
			_qa_state_sequence+=1
			_capture_file("state-%04d-run-%03d-%s.png" % [_qa_state_sequence,_qa_run_sequence,_qa_pending_capture_mode])
			_qa_pending_capture_mode=""
	if run.mode in ["victory","defeat"] and _last_result!=run.mode:
		_last_result=run.mode
		_print_result()
	if not _capture_dir.is_empty():
		for at in [5,20,40,60,75,90]:
			if run.elapsed()>=at and not _captured.has(at):
				_captured[at]=true
				_capture(at)
	if ((_quit_after>0 and _wall_age>=_quit_after) or (_probe_quit_after_complete and _frame_probe.done)) and not _qa_quit_sent:
		_qa_quit_sent=true
		_print_result()
		audio.reset()
		# Fixed-fps offline QA advances simulated timers faster than the audio
		# mixing thread. Stop simulation, then give audio actual wall-clock time.
		var audio_release_at := Time.get_ticks_usec()+150000
		while Time.get_ticks_usec()<audio_release_at:await get_tree().process_frame
		get_tree().quit()

func _capture(at: int) -> void:
	_capture_file("run-%03d-frame-%03d.png" % [_qa_run_sequence,at])

func _capture_file__chapter(filename: String) -> void:
	var base := ProjectSettings.globalize_path("res://_local/").replace("\\","/")
	var quality_base := ProjectSettings.globalize_path("res://_local/").replace("\\","/")
	var export_base := OS.get_executable_path().get_base_dir().replace("\\","/")+"/qa-captures/"
	var dest := _capture_dir.replace("\\","/").simplify_path()
	if not dest.begins_with(base) and not dest.begins_with(quality_base) and not dest.begins_with(export_base):push_error("Capture directory must be inside a C2/quality evidence directory or executable qa-captures directory");return
	DirAccess.make_dir_recursive_absolute(dest)
	var path := dest.path_join(filename)
	if FileAccess.file_exists(path):push_error("Refusing to overwrite capture: "+path);return
	var image := get_viewport().get_texture().get_image()
	if image:print("CHAPTER1_CAPTURE ",path," ",image.save_png(path))


# ---- chapter1/chapter_one_view.gd ----
const Loc=preload("res://chapter1/view/loc.gd")
const ChapterRun=preload("res://chapter1/core/chapter_core.gd")
const ChapterWorld=preload("res://chapter1/view/world/chapter_world.gd")
const ChapterHUD=preload("res://chapter1/view/hud/chapter_hud.gd")
const ChapterEffects=preload("res://chapter1/view/fx/chapter_effects.gd")
const ChapterPilot=preload("res://chapter1/core/chapter_pilot.gd")
const ChapterProfile=preload("res://chapter1/core/chapter_profile.gd")
const ChapterActors=preload("res://chapter1/view/actors/chapter_actors.gd")
var full_pilot=ChapterPilot.new()
var profile=ChapterProfile.new()
var _receipt := ""
var _saved_receipt := ""
var _profile_off := false
## True after the player chose "play without saving" for a refused save file. Lasts until the process ends.
var _profile_session_off := false
## A sentence the app wrote itself for the profile line (profile off, play without saving); the profile only supplies codes.
var _app_error := ""
## The worn set of this run goes back to the witch's kit only when the run started with her kit in (a kit that could not
## be imported leaves the saved selection alone). `_run_kept_slots` are slots of her kit that were left behind at the start.
var _run_carry_ok := false
var _run_kept_slots: Array=[]
## Permanent growth, for the screen to read (set by start_run and _save_terminal):
## the witch of this run ("" when profile is off), the core's progress_summary() at save time, and the
## profile's character_view() before the run and after a successful save ({} until then).
var run_character_id := ""
var run_progress: Dictionary={}
var view_before: Dictionary={}
var view_after: Dictionary={}
var _chapter_last_event := -1
## Battle record (W7, D11 F1): reads core events only. `run_record_view` is the read-only state for the result screen:
## {} during a run, recorder.summary() once the run has ended (record in the T6 4.3 shape, skill table
## with shares and damage per second, pair and beat tables, and the "why did I lose" material of a lost run).
const RunRecord=preload("res://chapter1/app/run_record.gd")
var recorder=RunRecord.new()
var run_record_view: Dictionary={}
## Dev trial: `--chapter1-trial=spells,rhythm` switches the systems that are parked off in the data files on, for this
## process only (the files stay off). Only together with --chapter1-profile-off, so a trial never writes to the player's save.
## Which trial switches this process runs with (F-1: a capture, a recording or a window title can say it; empty = the default game).
var trial_switches:PackedStringArray=PackedStringArray()
const TrialPace=preload("res://chapter1/app/trial_pace.gd")
func _apply_trial() -> void:
	trial_switches=PackedStringArray()
	var wanted:=""
	for arg in _user_args():
		if arg.begins_with("--chapter1-trial="):wanted=arg.trim_prefix("--chapter1-trial=")
	if wanted.is_empty():return
	if not "--chapter1-profile-off" in _user_args():
		push_warning("--chapter1-trial needs --chapter1-profile-off; ignored");return
	var parts:=wanted.split(",",false)
	for part in parts:
		if part in ["spells","rhythm","descent","pace","grace","elites"]:trial_switches.append(part)
		else:push_warning("--chapter1-trial: unknown name '%s' (spells, rhythm, descent, pace, grace, elites), ignored"%part)
	if not trial_switches.is_empty():print("CHAPTER1_TRIAL ",JSON.stringify(Array(trial_switches)))
	# The run opening (D15 B): "first-time visitor" is decided per run in start_run() (opening_first_visit_for), where the profile is known.
	# rhythm and elites both change the one tuning document, so it is read once and handed over once.
	# "pace" (D19 C1) is the rhythm with the first growth-pace values in the in-memory copy (level table, seal kills, guardian level, sweep bonus).
	if "rhythm" in parts or "elites" in parts or "pace" in parts or "grace" in parts:
		var tuning_doc: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://chapter1/data/combat_tuning.json"))
		if tuning_doc is Dictionary:
			if ("rhythm" in parts or "pace" in parts) and tuning_doc.get("rhythm") is Dictionary:
				tuning_doc["rhythm"]["enabled"]=true
				if tuning_doc["rhythm"].get("opening") is Dictionary:tuning_doc["rhythm"]["opening"]["enabled"]=true
				if "pace" in parts:TrialPace.apply(tuning_doc)
			# The strong elites (D13 W4-a) and the shrine / chest they guard (W5-a) go on together: a site is guarded by an elite.
			if "elites" in parts and tuning_doc.get("elites") is Dictionary and tuning_doc.get("extras") is Dictionary:
				tuning_doc["elites"]["enabled"]=true;tuning_doc["extras"]["enabled"]=true
			# "grace" (A8 G6): the grace block and its grades on, so the grade faces and the jackpot order of the grace screen can be seen (the data file stays off).
			if "grace" in parts and tuning_doc.get("grace") is Dictionary:
				tuning_doc["grace"]["enabled"]=true
				if tuning_doc["grace"].get("grades") is Dictionary:tuning_doc["grace"]["grades"]["enabled"]=true
			if not run.set_tuning(tuning_doc):push_warning("trial tuning refused: "+str(run.errors))
	if "spells" in parts:
		var spells_doc: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://chapter1/data/run_spells.json"))
		if spells_doc is Dictionary:
			spells_doc["enabled"]=true
			if not run.set_run_spells(spells_doc):push_warning("trial spells refused: "+str(run.errors))
	# The descent has no key and no screen yet (D15 U-2): this only lets a measuring tool or a later screen find it on.
	if "descent" in parts:
		var descent_doc: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://chapter1/data/descent.json"))
		if descent_doc is Dictionary:
			descent_doc["enabled"]=true
			# QA only: a cheaper first gauge (>= 1000, the validator's floor) so a short capture run reaches a descent.
			for arg in _user_args():
				if arg.begins_with("--chapter1-descent-cost="):descent_doc["cost"]=[int(arg.trim_prefix("--chapter1-descent-cost="))]
			if not run.set_descent(descent_doc):push_warning("trial descent refused: "+str(run.errors))
## D22 R0-B: the run opening's "first-time visitor". With the profile on: the runs of all witches together (records.runs, read only) are
## fewer than 2. Profile off (or not available): true, as before. `--chapter1-opening=returning` makes it false in every case.
static func opening_first_visit_for(profile_on:bool,total_runs:int,args:PackedStringArray) -> bool:
	if "--chapter1-opening=returning" in args:return false
	if not profile_on:return true
	return total_runs<2
func _init() -> void:
	run=ChapterRun.new();world=ChapterWorld.new();hud=ChapterHUD.new();effects=ChapterEffects.new();actors=ChapterActors.new()
	_apply_trial()
	full_pilot.run=run
func _ready() -> void:
	_profile_off="--chapter1-profile-off" in _user_args()
	if _profile_off:_app_error="검증 실행 · 저장 비활성"
	else:profile.configure()
	_sync_profile("저장 준비" if profile.available else _profile_error_text())
	hud.stash_show.connect(func():hud.stash_open=true;_sync_profile(hud.profile_note))
	hud.stash_equip.connect(_equip_from_stash)
	hud.stash_salvage.connect(func(id_: int):_sync_profile("장비 해체 저장 완료" if profile.salvage(id_) else _profile_error_text()))
	hud.save_retry.connect(_save_terminal)
	hud.skill_tree_open.connect(_open_skill_tree)
	hud.skill_tree_commit.connect(_commit_skill_tree)
	hud.skill_tree_respec.connect(_respec_skill_tree)
	_ready__chapter()
	DisplayServer.window_set_title(Loc.t("app.window.title")+(Loc.t("app.window.trial_tag",{"list":",".join(trial_switches)}) if not trial_switches.is_empty() else ""))
	print("FULL_CHAPTER_READY ",JSON.stringify({"scene":"chapter1/ChapterOne.tscn","three_connected_zones":true,"scope":"Full chapter implementation candidate; quality/pacing/manual/audio gates open"}))
## The stash window's "equip for the next run": onto the witch the title menu shows.
func _equip_from_stash(id_: int) -> void:
	_sync_profile("다음 도전 장비 저장 완료" if profile.select_item(id_,menu_character_id()) else _profile_error_text())
func start_run(id_: String) -> void:
	if profile.available and profile.state.items.size()>256:
		hud.stash_open=true;_sync_profile("회수 장비를 해체해 256개 이하로 정리하면 출발할 수 있습니다");return
	if not profile.available and not _profile_off and not _profile_session_off and profile.error_code!="preview_only":
		# A refused save file opens the notice again instead of a silent block (D5).
		if profile_rejected():hud.show_profile_notice()
		else:hud.notify(_profile_error_text())
		return
	run.opening_first_visit=opening_first_visit_for(profile.available,profile.total_runs(),_user_args())
	_chapter_last_event=-1
	_receipt="%d-%d-%d"%[OS.get_process_id(),Time.get_unix_time_from_system(),Time.get_ticks_usec()];_saved_receipt=""
	hud.stash_open=false
	# The starting skill picks the witch (no character choice yet). Her permanent build goes to the core before
	# start(); with the profile off or unavailable the run has no build and plays exactly as before.
	run_character_id="";run_progress={};view_before={};view_after={}
	_run_carry_ok=false;_run_kept_slots=[]
	run.clear_build()
	if profile.available:
		run_character_id=_character_for(id_)
		var build: Dictionary=profile.build_for(run_character_id) if not run_character_id.is_empty() else {}
		if not build.is_empty() and not run.configure_build(build):
			hud.notify("성장 빌드 오류 · "+str(run.errors));push_error("Build rejected: "+str(run.errors));return
		view_before=profile.character_view(run_character_id) if not run_character_id.is_empty() else {}
	hud.set_growth_result("",{},{},{})
	# The signature unique is a first-clear reward, once per witch (her "boss" first-kill receipt); without a
	# witch record it stays tied to the first completed run.
	if profile.available and not run_character_id.is_empty():run.first_boss_kill=not "boss" in profile.character_entry(run_character_id).first_rewards
	elif _profile_session_off:run.first_boss_kill=false # Nothing is saved this session; a first-kill unique would only mislead.
	else:run.first_boss_kill=not profile.available or int(profile.state.completed_runs)==0
	# D23 T9: the drop pity's count goes in only with a real save and the pity switched on; everywhere else the core gets 0.
	run.drop_dry_runs=int(profile.town_view().get("luck",{}).get("drop_runs_since_legendary",0)) if profile.available and not _profile_session_off and run.loot.pity_on() else 0
	start_run__chapter(id_)
	run_record_view={};recorder.begin(run,"d1")
	var gear_failed := false
	if profile.available:
		gear_failed=not _import_profile_kit()
		hud.invalidate()
	hud.notify("출발 장비를 불러오지 못했습니다 · 장비 없이 출발합니다" if gear_failed else Loc.t("hud.notice.start",{"zone":Loc.t("zone.%d.name"%run.zone)}))

## The witch's saved kit goes into the fresh run. A kit that cannot be imported never ends the game: the run starts bare,
## the saved selection is untouched and the run's worn set is not carried back (`_run_carry_ok` stays false).
func _import_profile_kit() -> bool:
	var kit: Dictionary=profile.starting_kit(run_character_id)
	var imported: bool=run.import_starting_gear(kit.gear)
	_run_kept_slots=kit.kept_slots.duplicate()
	_run_carry_ok=imported and not run_character_id.is_empty()
	if not imported:push_error("Starting gear import rejected · starting without gear")
	return imported

## The witch whose signature skill is this starting skill ("" if none).
func _character_for(skill_id: String) -> String:
	for entry in ChapterProfile.progression_doc().get("characters",[]):
		if entry.signature_skill_id==skill_id:return String(entry.id)
	return ""

# Refused-save entry points (D5). The screen only reads profile_reject_info() and calls these; nothing here
# deletes, edits, moves or renames a save file.
const SESSION_NO_SAVE_NOTE := "이번 실행은 저장하지 않습니다 · 저장 파일을 읽지 못했습니다"

## True when a save file was found and refused and the player has not yet chosen a way forward.
func profile_rejected() -> bool:
	return not profile.available and not _profile_off and not _profile_session_off and not profile.reject_kind.is_empty()

## Read-only facts for the notice: {kind, reason, file, path (full), folder (full), resume: {file, revision, unix} or {}}.
func profile_reject_info() -> Dictionary:
	if profile.reject_kind.is_empty():return {}
	var resume: Dictionary=profile.resume_info() # Computed once when the file was refused; cheap to call every frame.
	var shown: String=profile.reject_source if not profile.reject_source.is_empty() else profile.path
	return {"kind":profile.reject_kind,"reason":profile.reject_reason,"file":shown.get_file(),
		"path":ProjectSettings.globalize_path(shown),"folder":ProjectSettings.globalize_path(shown.get_base_dir()),"resume":resume}

## The refusal text for the screen: a sentence the app wrote itself (profile off, play without saving) is shown as it is;
## otherwise it is worded from the profile's code and arguments (keys profile.error.<code>).
func _profile_error_text() -> String:
	if not _app_error.is_empty() and (_profile_off or _profile_session_off):return _app_error
	if profile.error_code.is_empty():return profile.error
	return Loc.t("profile.error."+profile.error_code,profile.error_args)

## The witch the title menu is showing. The screen's own answer when it has one; until it gets a public function this
## reads its card index (a temporary read of the screen's private value) and maps it through the start skills.
func menu_character_id() -> String:
	if hud.has_method("menu_character_id"):return String(hud.call("menu_character_id"))
	var raw: Variant=hud.get("_menu_witch")
	if not raw is int:return ""
	var index: int=raw
	var skills: Array=ChapterHUD.START_SKILLS
	if index<0 or index>=skills.size():return ""
	return _character_for(String(skills[index]))

## Opens the save folder in the file manager. Opening only.
func open_profile_folder() -> void:
	OS.shell_open(ProjectSettings.globalize_path(profile.path.get_base_dir()))

## "Play without saving": this process runs with no profile; the file stays as it is.
func play_without_save() -> bool:
	if run.mode!="menu" or profile.available or profile.reject_kind.is_empty():return false
	_profile_session_off=true
	_app_error=SESSION_NO_SAVE_NOTE
	_sync_profile(SESSION_NO_SAVE_NOTE)
	return true

## "Start from a new save": a new file next to the refused one (or an empty v3 when only an old format was refused).
## use_revision=true continues from the newest readable journal copy. Returns false and keeps the refused state on failure.
func start_fresh_profile(use_revision: bool) -> bool:
	if run.mode!="menu" or profile.available or profile.reject_kind.is_empty():return false
	if not profile.start_fresh_after_reject(use_revision):
		hud.notify(_profile_error_text());return false
	_app_error=""
	_sync_profile("새 저장으로 시작했습니다 · 이전 파일은 그대로 남아 있습니다")
	return true

# Run flow (D4): back to the menu, give up, quit. The screen asks through signals; these decide.

## From a result window back to the title menu: a fresh core object is the same state the game starts in.
func return_to_menu() -> void:
	if run.mode not in ["victory","defeat"]:return
	run=ChapterRun.new();_apply_trial();full_pilot.run=run
	actors.reset();actors.rest_for_menu();effects.reset()
	if juice!=null:juice.reset()
	hud.reset();audio.reset();audio_routes.reset();audio.set_paused(true)
	if hud.skill_tree_is_open():hud.skill_panel.visible=false
	hud.stash_open=false
	hud.set_growth_result("",{},{},{})
	_chapter_last_event=-1;_last_audio_event=-1;_last_result="";_has_move_target=false
	_receipt="";_saved_receipt="";run_character_id="";run_progress={};view_before={};view_after={};_run_carry_ok=false;_run_kept_slots=[]
	run_record_view={}
	seed_+=1 # The next run from the menu never repeats the one just played (F3).
	world.update_camera(Vector2.ZERO,10.0)
	_sync_profile(Loc.t("notify.profile.ready") if profile.available else _profile_error_text())

## "Abandon this run": the same end as a fall, saved by the same path.
func abandon_run() -> void:
	if run.mode in ["menu","victory","defeat"]:return
	hud.set_result_reason("abandoned")
	if not run.abandon():
		hud.set_result_reason("");return
	_consume_events()
	hud.invalidate()

## Quit. During a run it is an abandon first, and the game closes only when that save went through (or there is
## nothing to save). In the menu or a result window the screen has already asked about unsaved rewards.
func quit_game() -> void:
	var from_mode: String=run.mode
	if from_mode not in ["menu","victory","defeat"]:
		abandon_run()
		if run.mode!="defeat":return
		if profile.available and _saved_receipt!=_receipt:
			hud.ask_unsaved("quit");return
	print("CHAPTER1_QUIT ",JSON.stringify({"from":"menu" if from_mode=="menu" else ("result" if from_mode in ["victory","defeat"] else "run")}))
	audio.reset()
	get_tree().quit()

func _sync_profile(note: String) -> void:
	hud.profile_state=profile.state.duplicate(true);hud.profile_note=note
	# The screen still reads one worn set: the kit of the witch the menu shows (the stash window equips onto her).
	hud.profile_state["equipped"]=profile.loadout(menu_character_id()) if profile.available else {}
	var views := {}
	for entry in ChapterProfile.progression_doc().get("characters",[]):
		var view: Dictionary=profile.character_view(String(entry.id))
		if not view.is_empty():views[String(entry.id)]=view
	hud.character_views=views
	hud.invalidate()

# Skill-tree screen (G1 P4). The screen only asks; the profile's public functions decide and save.
# [name key, class key, portrait]. The names and class titles live in the .po (character.<ember|frost|arc>.name / .class).
const WITCH_DISPLAY := {"chapter1.character.frost":["character.frost.name","character.frost.class","frost"],"chapter1.character.ember":["character.ember.name","character.ember.class","ember"],"chapter1.character.arc":["character.arc.name","character.arc.class","storm"]}

func _tree_info(character_id: String,view: Dictionary) -> Dictionary:
	var shown: Array=WITCH_DISPLAY.get(character_id,["character.frost.name","character.frost.class","frost"])
	return {"name":Loc.t(shown[0]),"class":Loc.t(shown[1]),"portrait":shown[2],"xp":int(view.xp),"xp_floor":int(view.xp_level_start),
		"xp_next":-1 if int(view.xp_to_next)<=0 else int(view.xp_for_next),
		"essence":int(profile.state.essence),"respec_cost":profile.respec_cost(character_id)}

func _open_skill_tree(character_id: String) -> void:
	if run.mode not in ["menu","victory","defeat"]:return
	var view: Dictionary=profile.character_view(character_id)
	if view.is_empty() or not bool(view.has_tree):hud.notify(Loc.t("profile.error.tree_locked"));return
	var tree: Dictionary=ChapterProfile.trees().get(String(view.tree_id),{})
	if tree.is_empty():hud.notify("스킬 트리 데이터를 읽지 못했습니다");return
	hud.show_skill_tree(character_id,tree,view,_tree_info(character_id,view))
	if bool(view.refunded_notice):
		hud.update_skill_tree(view,_tree_info(character_id,view),"트리가 개정되어 투자한 포인트를 돌려받았습니다.")
		profile.acknowledge_notice(character_id)

func _after_tree_saved(character_id: String,note: String,notice: String) -> void:
	var view: Dictionary=profile.character_view(character_id)
	_sync_profile(note)
	# The result screen shows this witch's points; keep it in step without replaying its gold-bar animation.
	if character_id==run_character_id and not view_after.is_empty():
		view_after=view
		hud.set_growth_result(run_character_id,view_before,view_after,run_progress,false)
	hud.update_skill_tree(view,_tree_info(character_id,view),notice)

func _commit_skill_tree(character_id: String,ranks: Dictionary) -> void:
	if profile.commit_tree(character_id,ranks):_after_tree_saved(character_id,"스킬 트리 저장 완료","투자를 확정했습니다 · 저장 완료")
	else:hud.skill_tree_error(_profile_error_text()+" · 예정 투자는 화면에 남겨 두었습니다")

func _respec_skill_tree(character_id: String) -> void:
	if profile.respec(character_id):_after_tree_saved(character_id,"스킬 트리 초기화 저장 완료","전체 초기화 · 포인트를 모두 돌려받았습니다")
	else:
		var view: Dictionary=profile.character_view(character_id)
		hud.update_skill_tree(view,_tree_info(character_id,view))
		hud.skill_tree_error(_profile_error_text())

func _save_terminal() -> void:
	if run.mode not in ["victory","defeat"]:return
	if _saved_receipt==_receipt:hud.result_unsaved=false;_sync_profile("이번 도전 보상 저장 완료");return
	if not profile.available:hud.result_unsaved=false;_sync_profile(_profile_error_text());return
	var progress: Dictionary=run.progress_summary()
	run_progress=progress
	var carry := {}
	if _run_carry_ok and not run_character_id.is_empty():carry={"character_id":run_character_id,"equipped":run.equipped.duplicate(true),"kept_slots":_run_kept_slots.duplicate()}
	# Schema 5: pass `outcome={"record":run_record_view.record}` as the last argument here (T6 record_run, 8th parameter) once record_run takes it. Not passed yet.
	if profile.record_run(_receipt,run.inventory,run.pending_rewards,run.mode=="victory",run.tick,progress,carry,{},not _profile_session_off and run.loot.pity_on()):
		_saved_receipt=_receipt;hud.result_unsaved=false
		if not run_character_id.is_empty():view_after=profile.character_view(run_character_id)
		hud.set_growth_result(run_character_id,view_before,view_after,run_progress)
		_sync_profile("이번 도전 보상 저장 완료 · 장비 %d개"%profile.state.items.size())
	else:
		hud.result_unsaved=true
		hud.set_growth_result(run_character_id,view_before,{},run_progress)
		_sync_profile(_profile_error_text()+" · 현재 보상은 이 화면에 유지됩니다")
func _unhandled_key_input__chapterx(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int=event.keycode if event.keycode!=0 else event.physical_keycode
		if key==KEY_ESCAPE and hud.stash_open:
			hud.stash_open=false;hud.invalidate();get_viewport().set_input_as_handled();return
		if key==KEY_Q:
			if run.drink_potion():_consume_events();hud.invalidate()
			get_viewport().set_input_as_handled();return
		if key==KEY_F and hud.upgrade_uid>=0:
			var worn_uid: int=hud.upgrade_uid
			if run.quick_equip(worn_uid):
				_consume_events();hud.clear_upgrade();hud.invalidate();hud.notify("장비 효과를 적용했습니다");audio.play_ui("equip",run.tick)
			get_viewport().set_input_as_handled();return
		if key==KEY_E:
			for def in run.RITUALS:
				if run.activate_ritual(def.id):_consume_events();hud.invalidate();break
			get_viewport().set_input_as_handled();return
	_unhandled_key_input__chapter(event)
func _pilot_input() -> Vector2:
	var move: Vector2=full_pilot.decide()
	# The pilot picks cards and drinks potions inside decide(); step() clears those events before the app reads them.
	recorder.consume(run.events)
	return move
## A pickup is announced only when the core says so: pickup_verdict(uid).react is card, open or auto_equip (D21 W1). Anything else goes into the bag quietly and
## can be compared from the inventory. The card shows the verdict's own changed rows, gains and losses together. Without a verdict (the pickup flow data is off)
## the older rule stays: announce a pickup that beats what is worn.
func _offer_if_better(item: Dictionary) -> void:
	if run.mode!="playing" or run.loot==null:return
	var data: Dictionary=run.compare_item(int(item.uid))
	if data.is_empty() or not data.can_equip or not run.equip_slot_of(int(item.uid)).is_empty():return
	var verdict: Dictionary=run.pickup_verdict(int(item.uid))
	if verdict.is_empty():
		if run.loot.is_upgrade(data.candidate,data.equipped,primary):hud.offer_upgrade(data.candidate,data.equipped,data.slot)
		return
	if String(verdict.react) in ["card","open","auto_equip"]:hud.offer_upgrade(data.candidate,data.equipped,data.slot,verdict)
func _consume_events() -> void:
	_consume_events__chapter()
	recorder.consume(run.events);recorder.observe(run)
	for event in run.events:
		if int(event.seq)<=_chapter_last_event:continue
		_chapter_last_event=event.seq
		match String(event.type):
			"victory","defeat":
				recorder.finish(run);run_record_view=recorder.summary();hud.set_run_record(run_record_view)
				_save_terminal()
			"item_pickup":_offer_if_better(event.item)
			"item_drop":
				# A ring or amulet has its own bright cue; a legendary or unique adds a chime (audio_routes.late).
				_play_routes(audio_routes.late(event))
			"gate_opened":hud.announce("gate",Loc.t("hud.band.gate_title"),Loc.t("hud.band.gate_line",{"zone":Loc.t("zone.%d.name"%int(event.zone))}));_play_routes(audio_routes.late(event))
			"zone_entered":hud.notify(Loc.t("zone.%d.name"%run.zone)+" · 새로운 봉인을 돌파하세요")
			"chapter_champion":hud.announce("boss",Loc.t("enemy.champion.%d.name"%int(event.zone)),Loc.t("hud.band.appears"));world.kick_camera(.45)
			"boss_phase":hud.announce("boss",Loc.t("enemy.champion.2.name"),Loc.t("hud.band.enraged"));world.kick_camera(.6)
			"chapter_burst":_play_routes(audio_routes.late(event))
			"potion_used":hud.notify("회복약 사용 · %d개 남음"%run.potions);_play_routes(audio_routes.late(event))
			"ritual_completed":hud.notify(Loc.t("ritual.%s.name"%String(event.id))+" 완료 · 보상 획득");_play_routes(audio_routes.late(event))
			"reward_pending":hud.notify("가방이 가득 찼습니다 · 의식 보상을 보관 대기합니다")
func _process(delta: float) -> void:
	_process__chapter(delta)
	_descent_hold_check(delta)
	world.sync(run,delta)
	if not _capture_dir.is_empty():
		for at in [150,210,270,330,390,450,510]:
			if run.elapsed()>=at and not _captured.has(at):_captured[at]=true;_capture(at)
## Call the descent (R, or the pad button). The core decides: false when it is off, not ready, or not playing. Accepted: the core
## stands still (mode "descent") until the cut-in is over and _descent_hold_check() lets it go (D15 A4.3, A7 item 9).
func call_descent() -> bool:
	if not run.request_descent():return false
	_consume_events()
	return true

## The cut-in ends in descent_fx (take_release); the hold limit is a floor under it, so a missing or broken picture can never
## leave the core standing still. Wall time, and only while the mode really is "descent" (a pause does not count).
func _descent_hold_check(delta: float) -> void:
	if run.mode!="descent":_descent_wait=0.0;return
	_descent_wait+=delta
	if descent_fx.take_release() or _descent_wait>=descent_fx.hold_limit():
		_descent_wait=0.0
		if run.release_descent():_consume_events()
func _capture_file(filename: String) -> void:
	var base := ProjectSettings.globalize_path("res://_local/").replace("\\","/")
	var dest := _capture_dir.replace("\\","/").simplify_path()
	if not dest.begins_with(base):_capture_file__chapter(filename);return
	DirAccess.make_dir_recursive_absolute(dest)
	var path := dest.path_join(filename)
	if FileAccess.file_exists(path):push_error("Refusing to overwrite full chapter capture");return
	var image := get_viewport().get_texture().get_image()
	if image:print("FULL_CHAPTER_CAPTURE ",path," ",image.save_png(path))
func _print_result() -> void:
	var summary: Dictionary=run.snapshot();summary.erase("enemies");summary.erase("projectiles");summary.erase("orbs");summary.erase("items")
	summary.scope="Full chapter candidate, normal QA driver when enabled; visual/manual/audio/performance approval separate"
	summary.pilot=_pilot;summary.qa_ignore_focus=_qa_ignore_focus
	summary.profile_available=profile.available;summary.profile_off=_profile_off;summary.profile_note=hud.profile_note
	print("FULL_CHAPTER_RUNTIME_RESULT ",JSON.stringify(summary))

# ---- chapter1/chapter_one_input21.gd ----
## Full-chapter click targets use the same unlocked walkable bounds as movement.
## The archived representative scene keeps its original first-arena controller.
func _unhandled_input(event: InputEvent) -> void:
	if run.mode!="playing" or not event is InputEventMouseButton:return
	if event.button_index!=MOUSE_BUTTON_LEFT or not event.pressed:return
	var origin: Vector3=world.camera.project_ray_origin(event.position)
	var direction: Vector3=world.camera.project_ray_normal(event.position)
	var ground: Variant=Plane(Vector3.UP,0).intersects_ray(origin,direction)
	if ground is Vector3:
		_move_target=run._clamp_point(Vector2(ground.x,ground.z))
		_has_move_target=true;effects.move_marker(_move_target)
		get_viewport().set_input_as_handled()

# ---- chapter1/chapter_one_input45.gd ----
## A mouse destination survives a dodge. Keyboard movement still takes priority
## through the existing _move_input; damage, speed and cooldown remain core-owned.
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and run.mode=="playing":
		var shortcut: int=event.keycode if event.keycode!=0 else event.physical_keycode
		if shortcut==KEY_SPACE:
			run.request_dash(_move_input())
			get_viewport().set_input_as_handled()
			return
		# R in a run is the descent (the result window's R "retry" is another mode). A run without the descent: false, nothing happens.
		if shortcut==KEY_R and call_descent():
			get_viewport().set_input_as_handled()
			return
	_unhandled_key_input__chapterx(event)

# ---- chapter1/chapter_one_input48.gd ----
func _is_press(event: InputEvent) -> bool:
	if event is InputEventKey:return event.pressed and not event.echo
	if event is InputEventMouseButton or event is InputEventJoypadButton:return event.pressed
	return false

## Space is a combat dodge, never an implicit modal confirmation.
## Keep explicit click/Enter choices and the existing R retry shortcut.
func _input(event: InputEvent) -> void:
	# The descent's cut-scene owns the keys while it plays (A11 12.3.4): a press is the skip (after the first 0.5 s) and is not passed on, so it cannot
	# pause the game (Esc) or move the hero when the core lets go.
	if run.mode=="descent" and descent_fx.input_guard() and _is_press(event):
		descent_fx.try_skip();get_viewport().set_input_as_handled();return
	_input__chapter(event)
	if event is InputEventJoypadButton and event.pressed and event.button_index==DESCENT_PAD_BUTTON and run.mode=="playing":
		call_descent()
	if event is InputEventJoypadButton and event.pressed and event.button_index==EQUIPMENT_PAD_BUTTON and not hud.flow_dialog_open() and run.mode in ["playing","paused","inventory"]:
		if run.mode=="inventory":close_equipment()
		else:open_equipment()
	if not event is InputEventKey:return
	var shortcut: int=event.keycode if event.keycode!=0 else event.physical_keycode
	if shortcut==KEY_SPACE and run.mode in ["choice","victory","defeat"]:
		get_viewport().set_input_as_handled()
