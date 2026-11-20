extends RefCounted
## A6-0: burst screenshots after core events. Used by hud_dump.gd (--burst=<name,...> --burst-frames=<n>, needs --shots=<dir>).
##
## A name is a core event `type`, optionally narrowed: `item_drop:legendary` matches the first item_drop event that carries the
## value "legendary" in any field (nested fields included, so item.quality counts); `cast:shape=ring` matches only when the
## field called `shape` holds "ring". The first matching event starts the burst: frame 0 is taken at the render frame that
## follows the event's tick, then one frame every STEP_TICKS (6 = 0.1 s at 60 Hz) up to N frames. Each name bursts once.
## Names that never matched are listed at the end (summary()). The events are read from run.events at every physics frame and
## deduplicated by (tick, seq), so no tick is missed even when the view clears the list on the next step.
const STEP_TICKS := 6
const SLACK_FRAMES := 30   # a frame is also taken after STEP_TICKS*k + SLACK frames when the tick does not move (end screens)
## Events the default run does not produce (switches in data/combat_tuning.json are off), so a miss is expected there.
const OFF_BY_DEFAULT := ["beat_started","wave_crest","trial_started","detonate","cast:shape=ring","cast:ring"]
## RS0: events only a run with the spell composition produces (run_spells.json enabled). A miss is expected while it is off;
## with hud_dump --run-spells=on (spells_on) a miss is a real miss and is not listed as expected. Names are matched by prefix.
const SPELLS_ONLY := ["detonate","cast:shape=ring","cast:ring","cast:prefer=","stagger","hit:vs_cc=","hit:detonate"]
var spells_on := false
var step_ticks := STEP_TICKS   # --burst-step=<ticks> in hud_dump (default 6)

var names: Array[String] = []
var frames_wanted := 8
var folder := ""
var active: Array = []
var done: Array = []
var started: Dictionary = {}
var shot_log: Array = []
var _queue: Array = []
var _grab: Callable
var _last_tick := -1
var _last_seq := -1
var _total_emitted := 0     # core._event_sequence at the previous poll
var _prev_mode := ""
var lost_events := 0        # emitted but cleared before any poll could see them (see poll())
var lost_log: Array = []

func setup(names_: Array[String], frames_: int, folder_: String) -> void:
	names = names_
	frames_wanted = maxi(1,frames_)
	folder = folder_

## Look at the core's events of the last tick. Call from the physics_frame signal and from _process.
func poll(run: RefCounted, frame: int) -> void:
	var seen := 0
	for event in run.events:
		var tick := int(event.get("tick",0)); var seq := int(event.get("seq",0))
		if tick == _last_tick and seq <= _last_seq: continue
		if tick < _last_tick: _last_seq = -1   # a new run restarted the clock
		_last_tick = tick; _last_seq = seq
		seen += 1
		for name in names:
			if started.has(name) or not _matches(event,name): continue
			_start(name,event,tick,run,frame)
	# Events no poll can see: the pilot picks a growth card inside _pilot_input(), and the very next run.step() clears
	# run.events in the same physics call. The core's own counter still moved, so the loss is counted, and a pick
	# (mode choice -> not choice) is turned into a "growth" event marked synthetic.
	var emitted := int(run.get("_event_sequence"))
	var delta := emitted-_total_emitted
	if delta < 0: delta = emitted   # a new run
	_total_emitted = emitted
	var lost := delta-seen
	if lost > 0:
		lost_events += lost
		lost_log.append({"tick":int(run.tick),"lost":lost,"mode_before":_prev_mode,"mode":String(run.mode)})
		if lost_log.size() > 40: lost_log.pop_front()
		if _prev_mode == "choice" and String(run.mode) != "choice" and "growth" in names and not started.has("growth"):
			_start("growth",{"type":"growth","tick":int(run.tick),"synthetic":"mode choice->playing; the pick's own event was cleared before any poll"},int(run.tick),run,frame)
	_prev_mode = String(run.mode)

func _start(name: String, event: Dictionary, tick: int, run: RefCounted, frame: int) -> void:
	started[name] = true
	var entry := {"name":name,"event":_summary(event),"tick0":tick,"frame0":frame,"next":0,"shots":[]}
	active.append(entry)
	print("HUD_BURST_EVENT ",JSON.stringify({"name":name,"tick":tick,"mode":run.mode,"event":entry.event}))

func _matches(event: Dictionary, spec: String) -> bool:
	var parts := spec.split(":",false,1)
	if String(event.get("type","")) != parts[0]: return false
	if parts.size() == 1: return true
	var want := String(parts[1])
	if "=" in want:
		var kv := want.split("=",false,1)
		return _find(event,String(kv[0]),String(kv[1]),4)
	return _find(event,"",want,4)

func _find(value: Variant, key: String, want: String, depth: int) -> bool:
	if depth < 0: return false
	if value is Dictionary:
		for k in value:
			var v = value[k]
			if (key.is_empty() or str(k) == key) and not (v is Dictionary or v is Array) and str(v) == want: return true
			if _find(v,key,want,depth-1): return true
	elif value is Array:
		for v in value:
			if key.is_empty() and not (v is Dictionary or v is Array) and str(v) == want: return true
			if _find(v,key,want,depth-1): return true
	return false

## Event without the heavy snapshots, for the log.
func _summary(event: Dictionary) -> Dictionary:
	var out := {}
	for k in event:
		var v = event[k]
		if v is Dictionary or v is Array:
			var text := JSON.stringify(v)
			out[k] = text if text.length() <= 140 else text.left(140)+"..."
		elif v is Vector2: out[k] = [snappedf(v.x,.01),snappedf(v.y,.01)]
		else: out[k] = v
	return out

## Queue the frames that are due. The picture is taken at RenderingServer.frame_post_draw of the same render frame, so it
## shows the state after the tick that made it due (grabbing in _process would give the previous frame). `grab` returns the
## viewport Image (may be null).
func process(run: RefCounted, frame: int, grab: Callable) -> void:
	_grab = grab
	for entry in active:
		while int(entry.next) < frames_wanted:
			var k: int = entry.next
			# While the core holds for the descent's cut-in the tick does not move and the picture is the event: take a frame every
			# STEP_TICKS render frames (0.1 s) from the start instead of waiting out the end-screen slack.
			var slack := 0 if String(run.mode) == "descent" else SLACK_FRAMES
			var due: bool = int(run.tick)-int(entry.tick0) >= k*step_ticks or frame-int(entry.frame0) >= k*step_ticks+slack
			if not due: break
			if _queue.is_empty(): RenderingServer.frame_post_draw.connect(_on_post_draw,CONNECT_ONE_SHOT)
			_queue.append({"entry":entry,"k":k,"tick":int(run.tick),"tick_after_event":int(run.tick)-int(entry.tick0),"mode":String(run.mode)})
			entry.next = k+1

func _on_post_draw() -> void:
	var image: Image = _grab.call() if _grab.is_valid() else null
	var queued := _queue
	_queue = []
	for q in queued:
		var entry: Dictionary = q.entry
		var file := "burst-%s-%d-t%d.png" % [String(entry.name).replace(":","_").replace("=","-"),int(q.k),int(q.tick)]
		var saved := false
		if image != null:
			DirAccess.make_dir_recursive_absolute(folder)
			saved = image.save_png(folder.path_join(file)) == OK
		var row := {"name":entry.name,"k":q.k,"tick":q.tick,"tick_after_event":q.tick_after_event,"mode":q.mode,"file":file,"saved":saved}
		entry.shots.append(row); shot_log.append(row)
		print("HUD_BURST ",JSON.stringify(row))
		if entry.shots.size() >= frames_wanted and active.has(entry):
			active.erase(entry); done.append(entry)

func busy() -> bool:
	return not active.is_empty()

func complete() -> bool:
	return done.size() == names.size()

func missed() -> Array:
	var out: Array = []
	for name in names:
		if not started.has(name): out.append(name)
	return out

func summary() -> Dictionary:
	var incomplete: Array = []
	for entry in active: incomplete.append({"name":entry.name,"shots":entry.shots.size()})
	var missed_names := missed()
	var expected_off: Array = []
	for name in missed_names:
		var spells_event := _is_spells_only(name)
		if (name in OFF_BY_DEFAULT or spells_event) and not (spells_on and spells_event): expected_off.append(name)
	return {"lost_events":lost_events,"requested":names,"frames":frames_wanted,"captured":done.map(func(e): return e.name),"incomplete":incomplete,
		"missed":missed_names,"missed_expected_off_by_default":expected_off}

func _is_spells_only(name: String) -> bool:
	for prefix in SPELLS_ONLY:
		if name.begins_with(prefix): return true
	return false

func write_index(path: String) -> void:
	var handle := FileAccess.open(path,FileAccess.WRITE)
	if handle == null: return
	var events: Array = []
	for entry in done + active: events.append({"name":entry.name,"tick0":entry.tick0,"event":entry.event,"shots":entry.shots})
	handle.store_string(JSON.stringify({"summary":summary(),"events":events},"  "))
	handle.close()
