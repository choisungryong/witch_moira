extends SceneTree
## Check tool, not product code (raised from the director's scratch script _local/director-scratch/sfx_capture.gd, AU-RS0).
## Plays a pilot run in the real app and, inside a tick window, saves one JPG per rendered frame plus the core events of each
## frame, so candidate sounds can be laid under real footage (tools/dev/audio_scene_audition.py reads events.json).
## Read-only on the core. Needs a real renderer (not --headless) and --fixed-fps 60 (one tick per frame):
##   python tools/dev/godot.py --fixed-fps 60 --resolution 1280x720 --path . --script res://chapter1/tests/sfx_capture.gd -- \
##       --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 \
##       --primary=chapter1.skill.ember --from=5400 --frames=720 --out=_local/sfx/<name> [--run-spells=on --spells-pick=synergy]
## Every event type is kept (none is filtered out). Fields kept per event: skill_id, kind, enemy_kind, elite, amount, crit, count,
## role, source_kind, by_skill, status, pair, prefer, pulse, shape, radius_cm, frozen, shatter, detonate, vs_cc, cut,
## and "targets" as a number (the targets of a cast are positions: only their count is written).
## Each row also carries "routes": what chapter1/presentation/audio_routes.gd makes of that frame's events (the game's own mapping;
## the pulse habituation state runs on every tick of the run, not only inside the window).
## --run-spells=on / --spells-pick=synergy: as in hud_dump.gd (chapter1/tests/spells_pick.gd); the data file stays off.
const SpellsPick := preload("res://chapter1/tests/spells_pick.gd")
const Routes := preload("res://chapter1/presentation/audio_routes.gd")
const KEEP := ["skill_id","kind","enemy_kind","elite","amount","crit","count","role","source_kind","by_skill","status","pair","prefer","pulse","shape","radius_cm","frozen","shatter","detonate","vs_cc","cut"]
var view: Node
var primary := "chapter1.skill.ember"
var from_tick := 5400
var n_frames := 720
var out_dir := ""
var run_spells_arg := ""
var spells_pick := ""
var frame := 0
var started := false
var last_seq := -1
var saved := 0
var rows: Array = []
var routes := Routes.new()
var picks: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--primary="): primary = arg.trim_prefix("--primary=")
		elif arg.begins_with("--from="): from_tick = int(arg.trim_prefix("--from="))
		elif arg.begins_with("--frames="): n_frames = int(arg.trim_prefix("--frames="))
		elif arg.begins_with("--out="): out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--run-spells="): run_spells_arg = arg.trim_prefix("--run-spells=")
		elif arg.begins_with("--spells-pick="): spells_pick = arg.trim_prefix("--spells-pick=")
	if not out_dir.begins_with("_local/"):
		push_error("--out must be under _local/"); quit(2); return
	if not run_spells_arg.is_empty() and run_spells_arg != "on":
		push_error("--run-spells=%s is unknown (on)" % run_spells_arg); quit(2); return
	if not spells_pick.is_empty() and (spells_pick != "synergy" or run_spells_arg != "on"):
		push_error("--spells-pick needs --run-spells=on and the value synergy"); quit(2); return
	out_dir = ProjectSettings.globalize_path("res://"+out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("frames"))
	view = load("res://chapter1/ChapterOne.tscn").instantiate()
	root.add_child(view)
	if run_spells_arg == "on":
		var problem := SpellsPick.enable(view.run)
		if not problem.is_empty():
			push_error("sfx_capture: "+problem); quit(2); return
		if not spells_pick.is_empty(): physics_frame.connect(_on_physics_frame)

## Runs before the app's own physics step, so the built-in pilot never sees the offer (same as hud_dump.gd).
func _on_physics_frame() -> void:
	if view == null or not started or view.run.mode != "choice": return
	var row := SpellsPick.pick(view.run,"sfx_capture")
	if row.is_empty(): return
	picks.append(row)
	view.recorder.consume(view.run.events)

func _process(_delta: float) -> bool:
	if view == null or not view.is_inside_tree(): return true
	frame += 1
	if not started:
		if frame == 11:
			view.start_run(primary); started = true
		return false
	var run: RefCounted = view.run
	var fresh: Array = []
	var kept: Array = []
	for event in run.events:
		if int(event.seq) <= last_seq: continue
		last_seq = int(event.seq)
		fresh.append(event)
		if run.tick < from_tick: continue
		var row := {"type":String(event.type)}
		for key in KEEP:
			if event.has(key): row[key] = event[key]
		if event.has("targets"): row["targets"] = event.targets.size()
		kept.append(row)
	var requests: Array = routes.route(fresh,run.spells,int(run.tick))
	for event in fresh:
		requests.append_array(routes.late(event))
	if run.tick >= from_tick and saved < n_frames:
		var image := root.get_viewport().get_texture().get_image()
		image.save_jpg(out_dir.path_join("frames/f%05d.jpg" % saved), .92)
		var routed: Array = []
		for r in requests:
			var d := {"cue":r.cue,"gain_db":r.gain_db,"source":r.source}
			if r.ui: d["ui"] = true
			routed.append(d)
		rows.append({"f":saved,"tick":run.tick,"mode":String(run.mode),"enemies":run.enemies.size(),"kills":run.kills,"events":kept,"routes":routed})
		saved += 1
	if saved >= n_frames or run.mode in ["victory","defeat"] or frame > 60000:
		var file := FileAccess.open(out_dir.path_join("events.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify({"primary":primary,"from":from_tick,"frames":saved,"run_spells":run_spells_arg == "on","rows":rows,"picks":picks}))
		file.close()
		print("SFX_CAPTURE ",JSON.stringify({"frames":saved,"tick":run.tick,"mode":run.mode,"kills":run.kills,"run_spells":run_spells_arg == "on","picks":picks.size()}))
		return true
	return false
