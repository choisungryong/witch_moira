extends Node
## QA tool (never product code): the body of the skill lab (docs/specs/T12-skill-lab-20261123.ko.md, SL-B).
##
## It is a child of the real ChapterOne scene. The real core runs, the real presenters draw and sound it; the lab only
## sets the stage (support/skill_lab_stage.gd holds every line that reaches into the core's private state).
## It talks to the manager server through two files in the lab folder (spec 2.2, the shape is not changed here):
##   command.json  <- the server: {"protocol":1,"seq":n,"op":"scene|cast|reload_audio|shot|quit","scene":{...},"audio":{slot:[paths]},"shot":"_local/..png"}
##   state.json    -> the server: heartbeat, what was applied, run digest, cast counts, sound requests, errors
## The folder, the clock and the speed boost come from outside, so a test can drive the very same body.
## Two more ways to run: --lab-clip (one scene, one cast, a fixed number of frames, then quit; for Movie Maker) and
## --lab-record (the same, plus one JPG per frame and the core events with the sound requests of each frame).

const Stage = preload("res://chapter1/tests/support/skill_lab_stage.gd")
const PROTOCOL := 1
const POLL_FRAMES := 6
const STATE_EVERY_MS := 500
const QUIET_TICKS := 36                    ## the effects' tail after a cast before the next staging
const MIN_CYCLE_TICKS := 30
const CHARACTERS := {
	"chapter1.character.ember": "chapter1.skill.ember",
	"chapter1.character.frost": "chapter1.skill.frost",
	"chapter1.character.arc": "chapter1.skill.arc",
}
const FORMS := ["base", "evolved", "descent"]
const MOTIONS := ["approach", "hold"]
const SCENE_KEYS := ["character", "skill", "form", "layout", "count", "motion", "durable", "repeat", "interval_s", "speed", "juice"]
const RESTAGE_KEYS := ["character", "skill", "form", "layout", "count", "motion", "durable"]
const AUDIO_ROOTS := ["_local/", "chapter1/art/"]
const SHOT_ROOTS := ["_local/"]
const LAB_ROOTS := ["_local/"]
const EVENT_ROW_KEYS := ["skill_id", "kind", "amount", "count", "element", "evolved", "target_id", "id", "elite", "role", "damage_raw", "variant", "index"]

var view: Node
var stage = Stage.new()
var lab_rel := "_local/skill-lab"
var lab_dir := ""                           ## absolute
var speed_boost := 1.0                      ## test only: multiplies the scene's speed (a headless test cannot wait for real time)
var idle_quit_s := 3600.0                   ## quit when no new command came for this long (wall seconds)
var clip_file := ""                         ## --lab-clip: a scene file (rel, under _local/)
var clip_seconds := 4.0
var record_rel := ""                        ## --lab-record: a folder (rel, under _local/)
var failed := ""                            ## set when the body cannot start (lock held, bad folder); the entry script quits with 3

var scene: Dictionary = {}                  ## the applied scene (normalised)
var applied_seq := 0
var ready_flag := false
var errors: Array = []
var last_shot := ""
var casts := {"count": 0, "last_tick": -1, "last_skill": "", "last_form": ""}
var event_counts: Dictionary = {}           ## type -> number seen since the body started (tests read this)
var unstaged_spawns := 0
var staged := 0
var audio_overrides: Dictionary = {}
var audio_load_errors: Array = []
var clip_info: Dictionary = {}

var _seen_seq := -1
var _frame := 0
var _last_state_ms := -1000
var _last_command_ms := 0
var _last_event_seq := -1
var _cycle_start_tick := 0
var _cycle_open := false
var _want_stage := false
var _force := false
var _cast_seen := false
var _quiet_ticks := 0
var _busy := false
var _saved_juice: RefCounted = null
var _started := false
var _primary := "chapter1.skill.ember"
var _default_primary := "chapter1.skill.ember"
var _clip_scene: Dictionary = {}
var _clip_audio: Dictionary = {}
var _clip_start_frame := -1
var _clip_start_proc := -1
var _clip_rows: Array = []
var _record_routes: RefCounted
var _record_saved := 0
var _quit_sent := false
var _api_missing_noted := false


# ------------------------------------------------------------------ paths

## Parses without the engine's own error print (a file may be missing or half written; the caller just tries again). null on failure.
static func parse_quiet(text: String) -> Variant:
	if text.strip_edges().is_empty(): return null
	var parser := JSON.new()
	if parser.parse(text) != OK: return null
	return parser.data


## A repo-relative path under one of `roots`, no "..", no drive, no absolute start. Returns the cleaned path or "".
static func safe_rel(path: String, roots: Array) -> String:
	var p := path.replace("\\", "/").strip_edges()
	if p.is_empty() or p.begins_with("/") or p.begins_with("res://") or p.contains(":") or p.contains("\u0000"): return ""
	var parts := p.split("/", false)
	var clean: Array = []
	for part in parts:
		if part == "..": return ""
		if part == ".": continue
		clean.append(part)
	var joined := "/".join(clean)
	for root in roots:
		if (joined + "/").begins_with(String(root)): return joined
	return ""


static func abs_of(rel: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join(rel)


func _fail(text: String) -> void:
	errors.append(text)
	if errors.size() > 40: errors = errors.slice(errors.size() - 40)


# ------------------------------------------------------------------ start

## Returns "" when the body can run, else why not.
func setup(owner_view: Node, folder_rel: String) -> String:
	view = owner_view
	var clean := safe_rel(folder_rel, LAB_ROOTS)
	if clean.is_empty(): return "lab folder must be inside _local/ (no .., no drive): " + folder_rel
	lab_rel = clean
	lab_dir = abs_of(clean)
	DirAccess.make_dir_recursive_absolute(lab_dir)
	var lock_path := lab_dir.path_join("lab.lock")
	if FileAccess.file_exists(lock_path):
		var old := int(FileAccess.get_file_as_string(lock_path).strip_edges())
		if old > 0 and old != OS.get_process_id() and OS.is_process_running(old):
			return "another lab window (pid %d) holds this folder" % old
	var f := FileAccess.open(lock_path, FileAccess.WRITE)
	if f == null: return "cannot write lab.lock"
	f.store_string(str(OS.get_process_id()))
	f.close()
	_last_command_ms = Time.get_ticks_msec()
	_default_primary = String(view.primary)
	if not record_rel.is_empty():
		var rec := safe_rel(record_rel, LAB_ROOTS)
		if rec.is_empty(): return "--lab-record must be inside _local/: " + record_rel
		record_rel = rec
		DirAccess.make_dir_recursive_absolute(abs_of(rec).path_join("frames"))
	if not clip_file.is_empty():
		var rel := safe_rel(clip_file, LAB_ROOTS)
		if rel.is_empty(): return "--lab-clip must be a file inside _local/: " + clip_file
		clip_file = rel
		var parsed: Variant = parse_quiet(FileAccess.get_file_as_string(abs_of(rel)))
		if not parsed is Dictionary: return "--lab-clip file is not a JSON object: " + rel
		var doc: Dictionary = parsed
		_clip_scene = doc.get("scene", doc) if doc.get("scene", doc) is Dictionary else {}
		_clip_audio = doc.get("audio", {}) if doc.get("audio", {}) is Dictionary else {}
	_started = true
	return ""


func _exit_tree() -> void:
	_release_lock()


func _release_lock() -> void:
	if lab_dir.is_empty(): return
	var lock_path := lab_dir.path_join("lab.lock")
	if FileAccess.file_exists(lock_path) and int(FileAccess.get_file_as_string(lock_path).strip_edges()) == OS.get_process_id():
		DirAccess.remove_absolute(lock_path)


# ------------------------------------------------------------------ scene

func default_scene() -> Dictionary:
	var character := ""
	for key in CHARACTERS:
		if CHARACTERS[key] == _default_primary: character = key
	if character.is_empty(): character = "chapter1.character.ember"
	return {"character": character, "skill": CHARACTERS[character], "form": "base", "layout": "single", "count": 8, "motion": "approach",
		"durable": false, "repeat": true, "interval_s": 3.0, "speed": 1.0, "juice": true}


## Fills defaults, checks values. Returns {"scene": Dictionary} or {"error": String}.
func normalise_scene(raw: Variant) -> Dictionary:
	if not raw is Dictionary: return {"error": "scene is not an object"}
	var s: Dictionary = (scene if not scene.is_empty() else default_scene()).duplicate()
	for key in raw:
		if not key in SCENE_KEYS: return {"error": "unknown scene key: " + str(key)}
		s[key] = raw[key]
	var character := String(s.character)
	if not CHARACTERS.has(character): return {"error": "unknown character: " + character}
	if raw.has("character") and not raw.has("skill"): s.skill = CHARACTERS[character]
	if String(s.skill) != String(CHARACTERS[character]): return {"error": "skill %s does not belong to %s (other witches' skills are phase 2)" % [s.skill, character]}
	if not String(s.form) in FORMS: return {"error": "unknown form: " + str(s.form)}
	if not String(s.layout) in Stage.LAYOUTS: return {"error": "unknown layout: " + str(s.layout)}
	if not String(s.motion) in MOTIONS: return {"error": "unknown motion: " + str(s.motion)}
	for key in ["count", "interval_s", "speed"]:
		if not (s[key] is int or s[key] is float): return {"error": key + " is not a number"}
	for key in ["durable", "repeat", "juice"]:
		if not s[key] is bool: return {"error": key + " is not true/false"}
	s.count = clampi(int(s.count), 1, Stage.MAX_COUNT)
	s.interval_s = clampf(float(s.interval_s), 1.0, 30.0)
	s.speed = clampf(float(s.speed), 0.1, 16.0)
	return {"scene": s}


func apply_scene(raw: Variant, audio_raw: Variant = null) -> bool:
	var run: RefCounted = view.run
	var made := normalise_scene(raw)
	if made.has("error"):
		_fail(String(made.error))
		return false
	var next: Dictionary = made.scene
	var first := scene.is_empty()
	var restage := first
	for key in RESTAGE_KEYS:
		if first or scene.get(key) != next.get(key): restage = true
	var new_character := first or String(scene.get("character", "")) != String(next.character)
	if new_character:
		_primary = String(next.skill)
		view.start_run(_primary)               # public: the witch is the starting skill; a fresh run, profile off keeps it away from saves
		var problems := stage.check_core(run)
		for problem in problems: _fail(String(problem))
		stage.prepare_run(run)
		_cycle_open = false
		_cast_seen = false
		_last_event_seq = -1                   # the new run counts its events from 1 again ...
		for event in run.events: _last_event_seq = maxi(_last_event_seq, int(event.seq))   # ... and its opening bodies are not ours to count
		unstaged_spawns = 0
		audio_overrides = {}               # a new run resets the audio; the sound candidates are put in again below
		_clear_audio_applied()
	scene = next
	stage.set_form(run, _primary, "evolved" if String(next.form) == "evolved" else "base")
	_apply_speed()
	_apply_juice(bool(next.juice))
	if audio_raw is Dictionary: _apply_audio(audio_raw)
	elif new_character: _apply_audio(_last_audio_wanted)
	if restage:
		_want_stage = true
		_force = true
		_try_stage()
	return true


## Slow motion / boost. Measured in Godot 4.5.1 (headless): Engine.time_scale only scales the delta handed to _process and the
## animations; the NUMBER of physics ticks per real second stays 60, and the core takes one tick per physics tick. So the core's
## clock is slowed by physics_ticks_per_second, and time_scale is set to the same factor so the pictures that follow delta (the
## descent screen, the effects) keep step with it. Sound pitch does not change (the engine does not scale it).
func _apply_speed() -> void:
	var s := clampf(float(scene.get("speed", 1.0)) * speed_boost, 0.05, 64.0)
	Engine.time_scale = s
	Engine.physics_ticks_per_second = clampi(int(round(60.0 * s)), 3, 3840)
	Engine.max_physics_steps_per_frame = 64 if s > 1.0 else 8


func _apply_juice(on: bool) -> void:
	if on and view.juice == null and _saved_juice != null:
		view.juice = _saved_juice
		_saved_juice = null
	elif not on and view.juice != null:
		_saved_juice = view.juice
		if _saved_juice.has_method("reset"): _saved_juice.reset()
		view.juice = null
	scene.juice = view.juice != null if on else false


# ------------------------------------------------------------------ the cycle

func _interval_ticks() -> int:
	return int(float(scene.get("interval_s", 3.0)) * 60.0)


func _fx_status() -> Dictionary:
	var fx: Variant = view.get("descent_fx")
	if fx != null and fx.has_method("status"): return fx.status()
	return {}


## Starts a staging now if the old one is over. A pending staging waits here until the effects are done.
func _try_stage() -> void:
	var run: RefCounted = view.run
	if not _want_stage or run.mode != "playing": return
	if _cycle_open and _force:
		# the scene was changed by hand: do not wait for the tail of the old cast, only for a running descent to end
		var view_d: Dictionary = run.descent_view()
		if bool(view_d.get("enabled", false)) and String(view_d.get("state", "")) in ["hold", "sweep"]: return
		if bool(_fx_status().get("sweep", false)): return
	elif _cycle_open:
		if run.tick - _cycle_start_tick < MIN_CYCLE_TICKS: return
		if not stage.is_quiet(run, _fx_status()): return
		if _quiet_ticks < QUIET_TICKS: return
	_begin_cycle()


func _begin_cycle() -> void:
	var run: RefCounted = view.run
	_scan_events()                             # what happened before this staging is counted before the old bodies' ids are forgotten
	_want_stage = false
	_force = false
	_quiet_ticks = 0
	_cast_seen = false
	stage.clear_field(run)
	stage.keep(run)
	staged = stage.place(run, String(scene.layout), int(scene.count), String(scene.motion), bool(scene.durable), int(view.seed_))
	if String(scene.form) == "descent":
		stage.disarm_cast(run, _primary)
		if not stage.fill_gauge(run): _fail("descent is off: start with --chapter1-trial=descent --chapter1-descent-cost=1000")
		elif not view.call_descent(): _fail("the core refused the descent call")
		_scan_events()
	else:
		stage.arm_cast(run, _primary)
	_scan_events()                             # the staging's own spawn events are seen (they are ours)
	_cycle_start_tick = run.tick
	_cycle_open = true


func _scan_events() -> void:
	var run: RefCounted = view.run
	for event in run.events:
		var seq := int(event.seq)
		if seq <= _last_event_seq: continue
		_last_event_seq = seq
		var type := String(event.type)
		event_counts[type] = int(event_counts.get(type, 0)) + 1
		if type == "cast" and String(event.get("skill_id", "")) == _primary:
			casts.count = int(casts.count) + 1
			casts.last_tick = int(event.tick)
			casts.last_skill = _primary
			casts.last_form = "evolved" if bool(event.get("evolved", false)) else "base"
			_cast_seen = true
		elif type == "spawn" and not stage.staged_ids.has(int(event.get("target_id", -1))):
			unstaged_spawns += 1


func _physics_process(_delta: float) -> void:
	if not _started or view == null or not ready_flag: return
	var run: RefCounted = view.run
	if run.mode == "menu": return
	_scan_events()
	stage.keep(run)
	if _cast_seen and String(scene.get("form", "base")) != "descent":
		stage.disarm_cast(run, _primary)          # one cast per staging
		_cast_seen = false
	if _cycle_open and stage.is_quiet(run, _fx_status()): _quiet_ticks += 1
	elif _cycle_open: _quiet_ticks = 0
	if bool(scene.get("repeat", false)) and _cycle_open and not _want_stage and run.tick - _cycle_start_tick >= _interval_ticks():
		_want_stage = true
	_try_stage()


# ------------------------------------------------------------------ sound candidates

var _audio_applied: Dictionary = {}
var _last_audio_wanted: Dictionary = {}


func _clear_audio_applied() -> void:
	_audio_applied = {}


func _apply_audio(wanted_raw: Dictionary) -> void:
	var audio: Variant = view.audio
	_last_audio_wanted = wanted_raw.duplicate(true)
	audio_load_errors = []
	if wanted_raw.is_empty() and _audio_applied.is_empty(): return
	if audio == null or not audio.has_method("audition_set"):
		if not _api_missing_noted:
			_api_missing_noted = true
		audio_load_errors.append("audition API 없음")
		return
	var wanted: Dictionary = {}
	for slot in wanted_raw:
		var list: Variant = wanted_raw[slot]
		if not list is Array:
			_fail("audio %s: not a list" % slot); continue
		var paths: Array = []
		var bad := false
		for item in list:
			var rel_clean := safe_rel(String(item), AUDIO_ROOTS)
			if rel_clean.is_empty():
				_fail("audio path refused (inside _local/ or chapter1/art/ only, no ..): " + String(item)); bad = true; break
			paths.append(rel_clean)
		if not bad and not paths.is_empty(): wanted[String(slot)] = paths
	for slot in _audio_applied.keys():
		if not wanted.has(slot):
			audio.audition_clear(slot)
			_audio_applied.erase(slot)
			audio_overrides.erase(slot)
	for slot in wanted:
		if _audio_applied.get(slot) == wanted[slot]: continue
		var engine_paths: Array = []
		for rel_path in wanted[slot]:
			engine_paths.append(("res://" + rel_path) if String(rel_path).begins_with("chapter1/art/") else abs_of(rel_path))
		var result: Variant = audio.audition_set(slot, engine_paths)
		if result is Dictionary:
			for e in result.get("errors", []): audio_load_errors.append(str(slot) + ": " + str(e))
		_audio_applied[slot] = wanted[slot]
		audio_overrides[slot] = wanted[slot]


func _recent_audio() -> Array:
	var audio: Variant = view.audio
	if audio == null: return []
	var log: Variant = audio.get("audition_log")
	if not log is Array: return []
	var out: Array = []
	for row in (log as Array).slice(maxi(0, (log as Array).size() - 20)):
		var d: Dictionary = row
		var path_text := String(d.get("path", ""))
		out.append({"tick": int(d.get("tick", 0)), "slot": String(d.get("slot", "")), "cue": String(d.get("cue", "")), "path": path_text})
	return out


# ------------------------------------------------------------------ files

func _write_json_atomic(path: String, data: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null: return false
	f.store_string(JSON.stringify(data))
	f.close()
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path) == OK


func state_dict() -> Dictionary:
	var run: RefCounted = view.run
	var state := {
		"protocol": PROTOCOL, "pid": OS.get_process_id(), "heartbeat_unix_ms": int(Time.get_unix_time_from_system() * 1000.0),
		"applied_seq": applied_seq, "ready": ready_flag and (run.mode == "playing" or run.mode == "descent"), "scene": scene.duplicate(true),
		"run": {"tick": int(run.tick), "mode": String(run.mode), "primary": _primary, "zone": int(run.zone), "enemies_alive": int(run.alive_count()),
			"staged": staged, "unstaged_spawns": unstaged_spawns},
		"casts": casts.duplicate(true),
		"audio": {"overrides": audio_overrides.duplicate(true), "load_errors": audio_load_errors.duplicate(), "recent": _recent_audio()},
		"errors": errors.duplicate(), "last_shot": last_shot,
	}
	if not clip_file.is_empty() or not record_rel.is_empty(): state["clip"] = clip_info.duplicate(true)
	return state


func write_state() -> void:
	_last_state_ms = Time.get_ticks_msec()
	_write_json_atomic(lab_dir.path_join("state.json"), state_dict())


func _read_command() -> void:
	var path := lab_dir.path_join("command.json")
	if not FileAccess.file_exists(path): return
	var parsed: Variant = parse_quiet(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary: return                  # half written: the next poll tries again
	var cmd: Dictionary = parsed
	if not cmd.has("seq") or not (cmd.seq is int or cmd.seq is float): return
	var seq := int(cmd.seq)
	if seq == _seen_seq: return
	_seen_seq = seq
	_last_command_ms = Time.get_ticks_msec()
	if int(cmd.get("protocol", 0)) != PROTOCOL:
		_fail("seq %d: protocol %s is not %d" % [seq, str(cmd.get("protocol")), PROTOCOL])
		applied_seq = seq
		write_state()
		return
	run_command(cmd)
	applied_seq = seq
	write_state()


## One command (also called by tests with the same shape as the file).
func run_command(cmd: Dictionary) -> void:
	var op := String(cmd.get("op", ""))
	match op:
		"scene":
			var audio_raw: Variant = cmd.get("audio", {})
			apply_scene(cmd.get("scene", {}), audio_raw if audio_raw is Dictionary else {})
		"cast":
			if scene.is_empty(): _fail("cast before any scene"); return
			_want_stage = true
			_force = true
			_try_stage()
		"reload_audio":
			var audio: Variant = view.audio
			if audio != null and audio.has_method("reload_map"): audio.reload_map()
			else: _fail("reload_map is not in combat_audio yet")
		"shot":
			var rel := safe_rel(String(cmd.get("shot", "")), SHOT_ROOTS)
			if rel.is_empty() or not rel.to_lower().ends_with(".png"):
				_fail("shot path refused (a .png inside _local/, no ..): " + String(cmd.get("shot", "")))
			else:
				_shot(rel)
		"quit":
			_quit("command")
		_:
			_fail("unknown op: " + op)


func _shot(rel: String) -> void:
	if _busy: _fail("a picture is already being saved"); return
	_busy = true
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		_fail("no picture (is this a headless run?)")
	else:
		DirAccess.make_dir_recursive_absolute(abs_of(rel).get_base_dir())
		var code := image.save_png(abs_of(rel))
		if code == OK: last_shot = rel
		else: _fail("saving the picture failed: %d" % code)
	_busy = false
	write_state()


func _quit(reason: String) -> void:
	if _quit_sent: return
	_quit_sent = true
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	write_state()
	_release_lock()
	print("SKILL_LAB_QUIT ", JSON.stringify({"reason": reason}))
	get_tree().quit()


# ------------------------------------------------------------------ frame loop

func _process(_delta: float) -> void:
	if not _started or view == null or _quit_sent: return
	_frame += 1
	var run: RefCounted = view.run
	if not ready_flag:
		if run.mode == "playing" and not run.hero.is_empty() and _frame > (30 if not clip_file.is_empty() or not record_rel.is_empty() else 2):
			ready_flag = true
			_first_scene()
		return
	if clip_file.is_empty() and record_rel.is_empty():
		if _frame % POLL_FRAMES == 0: _read_command()
		if float(Time.get_ticks_msec() - _last_command_ms) / 1000.0 > idle_quit_s:
			_quit("idle")
			return
	else:
		_clip_frame()
	if Time.get_ticks_msec() - _last_state_ms >= STATE_EVERY_MS: write_state()


func _first_scene() -> void:
	if not clip_file.is_empty() or not record_rel.is_empty():
		var s := _clip_scene.duplicate()
		s["repeat"] = false                       # a clip is one cast
		if s.is_empty() or not s.has("character"): s = default_scene(); s["repeat"] = false
		apply_scene(s, _clip_audio)
		_clip_start_frame = Engine.get_frames_drawn()
		_clip_start_proc = _frame
		clip_info = {"start_frame": _clip_start_frame, "start_time_s": float(_clip_start_frame) / 60.0, "frames": 0, "seconds": clip_seconds, "done": false}
		if not record_rel.is_empty():
			_record_routes = view.audio_routes.get_script().new()
		write_state()
		return
	var path := lab_dir.path_join("command.json")
	if FileAccess.file_exists(path):
		var parsed: Variant = parse_quiet(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and parsed.has("seq"):
			_read_command()
			if not scene.is_empty():
				write_state()
				return
	apply_scene(default_scene())
	write_state()


func _clip_frame() -> void:
	var run: RefCounted = view.run
	var n := _frame - _clip_start_proc
	if not record_rel.is_empty() and n >= 0:
		var fresh: Array = []
		var rows: Array = []
		for event in run.events:
			if int(event.seq) <= _clip_last_seq: continue
			_clip_last_seq = int(event.seq)
			if String(event.type) in ["spawn"]: continue
			var row := {"type": String(event.type), "tick": int(event.tick)}
			for key in EVENT_ROW_KEYS:
				if event.has(key): row[key] = event[key] if not event[key] is Vector2 else [snappedf(event[key].x, 0.01), snappedf(event[key].y, 0.01)]
			rows.append(row)
			fresh.append(event)
		var requests: Array = []
		if _record_routes != null:
			for request in _record_routes.route(fresh, run.spells, run.tick):
				var q := {"cue": String(request.cue), "gain_db": float(request.gain_db), "ui": bool(request.ui)}
				if request.has("slot"): q["slot"] = String(request.slot)
				requests.append(q)
		var image := get_viewport().get_texture().get_image()
		if image != null and not image.is_empty():
			image.save_jpg(abs_of(record_rel).path_join("frames/f%05d.jpg" % _record_saved), 0.92)
		_clip_rows.append({"f": _record_saved, "tick": int(run.tick), "mode": String(run.mode), "enemies": int(run.alive_count()), "events": rows, "requests": requests})
		_record_saved += 1
	clip_info["frames"] = n
	if float(n) / 60.0 >= clip_seconds:
		clip_info["done"] = true
		if not record_rel.is_empty():
			var f := FileAccess.open(abs_of(record_rel).path_join("events.json"), FileAccess.WRITE)
			if f != null:
				f.store_string(JSON.stringify({"format": 1, "fps": 60, "primary": _primary, "scene": scene, "frames": _record_saved,
					"start_frame": _clip_start_frame, "rows": _clip_rows}))
				f.close()
		_quit("clip done")

var _clip_last_seq := -1
