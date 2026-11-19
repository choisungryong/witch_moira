extends Node
## Play log: one JSON file per finished run (win, defeat, give-up or window closed), in the same table as the automatic
## measurement (chapter1/tests/measure_rhythm.gd: the per-30-second "bins" use the same keys), so a person's run and the
## pilot's run can be laid side by side.
##
## OFF by default. It is turned on by a run argument:
##   --chapter1-playlog            files go to user://playlogs/  (a NEW sub-folder of the user folder, never next to the
##                                 profile; with --chapter1-profile-off they go to _local/playtests/ instead)
##   --chapter1-playlog=<path>     files go to <path>, which must be under _local/ (e.g. _local/playtests)
## The profile (user://chapter-one-profile-v3.json and its journal) is never opened, read or written here. A file is only
## ever created, under a fresh name; an existing file is never changed or deleted.
##
## READ ONLY. It reads the core's events (run.events, once per physics tick, so no event is missed even when a frame spans two
## steps) and its state (run.tick, kills, hero, growth snapshot). It calls nothing on the core and draws no random number.
## It is a child node of the HUD root, so it runs right after the core's own step in the same physics tick.
##
## TO MERGE WITH THE BATTLE RECORDER (chapter1/app/run_record.gd, per-skill damage, written by another hand): when that
## recorder exists, add its table to the document in `_document()` under a "skills" key (one line there) and delete the
## counters here that it also keeps. The "bins" keys must stay the same as measure_rhythm.gd.
##
## Written per second (not per event) so a defeat can show the last 30 seconds: see `_window()`.
const BIN_S := 30
const SCHEMA := 1
const WITCH_OF := {"ember": "ember", "frost": "frost", "arc": "storm"}

var run: RefCounted
var view_ref: WeakRef
var dir_path := ""
var enabled := false
var active := false
var last_error := ""
var written_paths: Array[String] = []

var _seed := 0
var _primary := ""
var _primary_short := ""
var _last_tick := 0
var _last_seq := -1
var _seconds: Dictionary = {}
var _boons: Array[Dictionary] = []
var _picks: Dictionary = {}
var _marks: Array = []
var _hp_frac := 1.0
var _cache := {}
var _started_unix := 0.0
var _dropped_start := 0

## The folder for a given argument list; "" when the log is off or the argument is refused. `error` is set on refusal.
static func resolve_dir(args: PackedStringArray) -> Dictionary:
	var bare := false
	var path := ""
	var has_path := false
	for arg in args:
		if arg == "--chapter1-playlog":
			bare = true
		elif arg.begins_with("--chapter1-playlog="):
			has_path = true
			path = arg.trim_prefix("--chapter1-playlog=")
	if has_path:
		var fixed := path.replace("\\","/")
		if fixed.begins_with("res://"): fixed = fixed.trim_prefix("res://")
		elif fixed.is_absolute_path():
			var project := ProjectSettings.globalize_path("res://").replace("\\","/")
			if not fixed.begins_with(project): return {"dir":"","error":"--chapter1-playlog must be under the project's _local/ folder"}
			fixed = fixed.trim_prefix(project)
		fixed = fixed.trim_prefix("./")
		if fixed.contains("..") or fixed.contains(":") or not (fixed == "_local" or fixed.begins_with("_local/")):
			return {"dir":"","error":"--chapter1-playlog must be a path under _local/ (got %s)" % path}
		return {"dir":"res://"+fixed.trim_suffix("/"),"error":""}
	if bare:
		if "--chapter1-profile-off" in args: return {"dir":"res://_local/playtests","error":""}
		return {"dir":"user://playlogs","error":""}
	return {"dir":"","error":""}

## Adds the recorder to the HUD root when the run arguments ask for it. Returns the node or null.
static func attach(parent: Node, view: Node) -> Node:
	var found := resolve_dir(OS.get_cmdline_user_args())
	if not String(found.error).is_empty():
		push_error("playlog: "+String(found.error))
		return null
	if String(found.dir).is_empty(): return null
	var recorder: Node = (load("res://chapter1/view/hud/play_recorder.gd") as GDScript).new()
	recorder.name = "PlayRecorder"
	recorder.dir_path = String(found.dir)
	recorder.enabled = true
	recorder.view_ref = weakref(view)
	parent.add_child(recorder)
	return recorder

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## Called by the HUD when a run is (re)started: closes a run still open, then opens the new one.
func begin_run(core: RefCounted) -> void:
	if not enabled: return
	if active: finish("quit","restarted")
	run = core
	if core == null or String(core.mode) != "playing": return
	var view: Object = view_ref.get_ref() if view_ref != null else null
	_seed = int(view.get("seed_")) if view != null and view.get("seed_") != null else 0
	_primary = String(view.get("primary")) if view != null and view.get("primary") != null else ""
	_primary_short = _primary.trim_prefix("chapter1.skill.")
	_last_tick = int(core.tick)
	_last_seq = int(core._event_sequence) if core.get("_event_sequence") != null else -1
	_seconds = {}
	_boons = []
	_picks = {}
	_marks = []
	_hp_frac = 1.0
	_cache = {}
	_started_unix = Time.get_unix_time_from_system()
	_dropped_start = int(core.metrics.get("events_dropped",0))
	active = true

## Once per rendered frame, from the HUD's sync: the growth snapshot is the HUD's own per-frame copy.
func observe(core: RefCounted, growth: Dictionary) -> void:
	if not enabled: return
	run = core
	if not active:
		# The very first run of a session can start before the HUD was reset.
		if String(core.mode) == "playing" and int(core.tick) <= 1: begin_run(core)
		return
	_poll()
	_watch_picks(growth)
	if String(core.mode) in ["victory","defeat"] and active:
		var abandoned := false
		for ev in core.events:
			if String(ev.type) == "defeat" and bool(ev.get("abandoned",false)): abandoned = true
		if String(core.mode) == "victory": finish("win","victory")
		elif abandoned: finish("quit","abandoned")
		else: finish("down","defeat")
	elif String(core.mode) == "menu" and active:
		finish("quit","menu")

func _physics_process(_delta: float) -> void:
	if enabled and active and run != null: _poll()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if enabled and active and not _cache.is_empty(): finish("quit","closed")

func _exit_tree() -> void:
	if enabled and active and not _cache.is_empty(): finish("quit","closed")

func _second(index: int) -> Dictionary:
	if not _seconds.has(index):
		_seconds[index] = {"ticks":0,"kills":0,"hits":0,"dmg":0.0,"attacks":0,"prim_hits":0,"drops":0,"waves":0,"alive":[],"alive_max":0,"hp":1.0,"kinds":{}}
	return _seconds[index]

## New events by sequence number, plus the per-tick accounting. Safe to call from both the physics tick and the frame.
func _poll() -> void:
	var core := run
	var max_hp := maxf(1.0,float(core.hero.get("max_hp_raw",1))) if not core.hero.is_empty() else 1.0
	for ev in core.events:
		var seq := int(ev.seq)
		if seq <= _last_seq: continue
		_last_seq = seq
		var s := _second(int(ev.tick)/60)
		match String(ev.type):
			"death": s.kills += 1
			"hero_hit":
				s.hits += 1
				s.dmg += float(ev.get("damage_raw",0))/max_hp
			"enemy_attack":
				s.attacks += 1
				var kind := String(ev.get("kind","?"))
				s.kinds[kind] = int(s.kinds.get(kind,0))+1
			"hit":
				if String(ev.get("skill_id","")) == _primary: s.prim_hits += 1
			"item_drop": s.drops += 1
			"wave_crest": s.waves += 1
			"zone_entered": _marks.append("%.0fs enter%d" % [float(ev.tick)/60.0,int(ev.get("zone",0))])
			"gate_opened": _marks.append("%.0fs gate%d" % [float(ev.tick)/60.0,int(ev.get("zone",0))])
			"chapter_champion": _marks.append("%.0fs champ%d" % [float(ev.tick)/60.0,int(ev.get("zone",0))])
	var tick := int(core.tick)
	if tick > _last_tick:
		var sec := _second(maxi(tick-1,0)/60)
		sec.ticks += tick-_last_tick
		if tick % 6 == 0: sec.alive.append(core.alive_count())
		sec.alive_max = maxi(int(sec.alive_max),core.alive_count())
		if not core.hero.is_empty(): _hp_frac = float(core.hero.hp_raw)/max_hp
		sec.hp = _hp_frac
		_last_tick = tick
	_cache = {"tick":tick,"kills":int(core.kills),"level":int(core.growth.snapshot().level) if core.growth != null else 0,"mode":String(core.mode),"zone":int(core.get("zone")) if core.get("zone") != null else 0,
		"events_dropped":int(core.metrics.get("events_dropped",0))-_dropped_start}

## Boons the person took: the growth snapshot's ranks, passives, evolutions and axes gain an entry per pick.
func _watch_picks(growth: Dictionary) -> void:
	if growth.is_empty(): return
	var now := {}
	for skill in growth.get("ranks",{}): now["rank:%s=%d" % [skill,int(growth.ranks[skill])]] = true
	for id_ in growth.get("passives",[]): now["passive:%s" % id_] = true
	for id_ in growth.get("evolved",[]): now["evolve:%s" % id_] = true
	for skill in growth.get("axes",{}):
		for axis in growth.axes[skill]: now["axis:%s.%s=%d" % [skill,axis,int(growth.axes[skill][axis])]] = true
	if _picks.is_empty() and _boons.is_empty():
		_picks = now
		# The first look is the starting state (the starting skill's rank), not a pick.
		return
	for key in now:
		if _picks.has(key): continue
		var kind := String(key).get_slice(":",0)
		_boons.append({"order":_boons.size()+1,"tick":int(run.tick),"sec":snappedf(float(run.tick)/60.0,0.1),"level":int(growth.get("level",0)),"kind":kind,"id":String(key).get_slice(":",1)})
	_picks = now

# ---------- document ----------
func _bin(first_s: int, last_s: int, label: String) -> Dictionary:
	var kills := 0
	var hits := 0
	var attacks := 0
	var prim := 0
	var drops := 0
	var waves := 0
	var ticks := 0
	var dmg := 0.0
	var alive: Array = []
	var alive_max := 0
	var hp_start := -1.0
	var hp_end := 1.0
	var kinds := {}
	for index in range(first_s,last_s):
		if not _seconds.has(index): continue
		var s: Dictionary = _seconds[index]
		kills += int(s.kills); hits += int(s.hits); attacks += int(s.attacks); prim += int(s.prim_hits)
		drops += int(s.drops); waves += int(s.waves); ticks += int(s.ticks); dmg += float(s.dmg)
		alive.append_array(s.alive)
		alive_max = maxi(alive_max,int(s.alive_max))
		if hp_start < 0.0: hp_start = float(s.hp)
		hp_end = float(s.hp)
		for kind in s.kinds: kinds[kind] = int(kinds.get(kind,0))+int(s.kinds[kind])
	var secs := float(ticks)/60.0
	var per_min := 60.0/maxf(secs,0.001)
	alive.sort()
	var avg := 0.0
	for v in alive: avg += float(v)
	if alive.size() > 0: avg /= float(alive.size())
	var p90 := 0.0
	if alive.size() > 0: p90 = float(alive[clampi(int(ceil(0.9*alive.size()))-1,0,alive.size()-1)])
	var grace_times: Array = []
	for b in _boons:
		if float(b.sec) >= float(first_s) and float(b.sec) < float(last_s): grace_times.append(b.sec)
	return {"label":label,"from_s":float(first_s),"to_s":float(last_s),"secs":snappedf(secs,0.1),
		"kills":kills,"kpm":snappedf(float(kills)*per_min,0.1),"alive_avg":snappedf(avg,0.1),"alive_p90":p90,"alive_max":alive_max,
		"hits":hits,"hits_pm":snappedf(float(hits)*per_min,0.1),"dmg":snappedf(dmg,0.001),"dmg30":snappedf(dmg/maxf(secs,0.001)*30.0,0.001),
		"attacks":attacks,"prim_hits":prim,"prim_hits_per_kill":snappedf(float(prim)/maxf(1.0,float(kills)),0.01),
		"grace":grace_times.size(),"grace_times":grace_times,"drops":drops,"wave_crests":waves,
		"hp_start":snappedf(maxf(hp_start,0.0),0.01),"hp_end":snappedf(hp_end,0.01),"attackers":kinds}

func _document(result: String, reason: String) -> Dictionary:
	var ticks := int(_cache.get("tick",_last_tick))
	var total_s := int(ceil(float(ticks)/60.0))
	var bins: Array = []
	var index := 0
	while index*BIN_S < maxi(total_s,1):
		var from_s := index*BIN_S
		var bin := _bin(from_s,from_s+BIN_S,"%d-%ds" % [from_s,from_s+BIN_S])
		if float(bin.secs) >= 0.5: bins.append(bin)
		index += 1
	var worst: Dictionary = {}
	var hit_total := 0
	for b in bins:
		hit_total += int(b.hits)
		if worst.is_empty() or int(b.hits) > int(worst.hits) or (int(b.hits) == int(worst.hits) and float(b.dmg) > float(worst.dmg)): worst = b
	var boon_times: Array = []
	for b in _boons: boon_times.append(b.sec)
	var longest_gap := 0.0
	for i in range(1,boon_times.size()): longest_gap = maxf(longest_gap,float(boon_times[i])-float(boon_times[i-1]))
	var secs := snappedf(float(ticks)/60.0,0.1)
	var mode: String = {"win":"victory","down":"defeat"}.get(result,"abandoned" if reason == "abandoned" else reason)
	var summary := {"secs":secs,"mode":mode,"kills":int(_cache.get("kills",0)),"level":int(_cache.get("level",0)),
		"grace_count":boon_times.size(),"grace_times":boon_times,"grace_first_s":(boon_times[0] if boon_times.size() > 0 else -1.0),
		"grace_longest_gap_s":snappedf(longest_gap,0.1),"grace_last_to_end_s":(snappedf(secs-float(boon_times[boon_times.size()-1]),0.1) if boon_times.size() > 0 else -1.0),
		"worst_bin":String(worst.get("label","")),"worst_bin_hits":int(worst.get("hits",0)),"worst_bin_dmg":worst.get("dmg",0.0),
		"hits_total":hit_total,"events_dropped":int(_cache.get("events_dropped",0))}
	var now := Time.get_datetime_dict_from_system()
	var played := "%04d-%02d-%02d %02d:%02d" % [now.year,now.month,now.day,now.hour,now.minute]
	var document := {
		# The first block is the shape tools/manager/playlog.py reads (played_at, witch, result, minutes, answers).
		"played_at":played,"witch":WITCH_OF.get(_primary_short,""),"result":result,"minutes":clampi(int(round(secs/60.0)),0,600),"answers":{},
		"source":"auto-playlog","schema":SCHEMA,"human":not ("--chapter1-pilot" in OS.get_cmdline_user_args()),
		"primary":_primary_short,"seed":_seed,"mode":mode,"end_reason":reason,"secs":secs,"kills":int(_cache.get("kills",0)),
		"zone_at_end":int(_cache.get("zone",0)),"beat_source":"time table (A2)","marks":_marks,
		"summary":summary,"boons":_boons,"bin_s":BIN_S,"bins":bins,
		"build":_build(),
	}
	if result == "down":
		var last_second := maxi(total_s,1)
		var window := _bin(maxi(0,last_second-30),last_second,"last30")
		document["last30"] = window
	return document

func _build() -> Dictionary:
	var info := Engine.get_version_info()
	var args: Array = []
	for arg in OS.get_cmdline_user_args(): args.append(String(arg))
	var size := DisplayServer.window_get_size() if DisplayServer.get_name() != "headless" else Vector2i.ZERO
	return {"engine":"%d.%d.%d" % [info.major,info.minor,info.patch],"debug":OS.is_debug_build(),"qa_feature":OS.has_feature("qa"),
		"os":OS.get_name(),"window":[size.x,size.y],"args":args,"exe":OS.get_executable_path().get_file(),
		"note":"person's run unless human=false (pilot); fun and feel are unevaluated"}

## Writes the file once per run. Never overwrites: a taken name gets -2, -3 ...
func finish(result: String, reason: String) -> void:
	if not active: return
	active = false
	if _cache.is_empty(): return
	var document := _document(result,reason)
	var absolute := ProjectSettings.globalize_path(dir_path)
	if DirAccess.make_dir_recursive_absolute(absolute) != OK and not DirAccess.dir_exists_absolute(absolute):
		last_error = "cannot create "+dir_path
		push_error("playlog: "+last_error)
		return
	var stamp := String(document.played_at).replace("-","").replace(" ","-").replace(":","")
	var stem := "%s-%s-%d" % [stamp,String(document.primary),_seed]
	var name_ := stem
	var n := 1
	while FileAccess.file_exists(absolute.path_join(name_+".json")):
		n += 1
		name_ = "%s-%d" % [stem,n]
	var path := absolute.path_join(name_+".json")
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null:
		last_error = "cannot write "+path
		push_error("playlog: "+last_error)
		return
	file.store_string(JSON.stringify(document,"\t"))
	file.close()
	written_paths.append(path)
	print("CHAPTER1_PLAYLOG ",JSON.stringify({"path":path,"result":result,"secs":document.secs,"kills":document.kills}))
