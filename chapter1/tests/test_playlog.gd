extends SceneTree
## Play log (chapter1/view/hud/play_recorder.gd): where it may write, what the file holds, that it matches the automatic
## measurement's bin keys, and that it only reads. Headless; writes only under _local/ and removes its own files.
##   python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_playlog.gd
const Recorder := preload("res://chapter1/view/hud/play_recorder.gd")
const Core := preload("res://chapter1/core/chapter_core.gd")
const Pilot := preload("res://chapter1/core/chapter_pilot.gd")
const DIR := "res://_local/playtests-unit"
## The keys measure_rhythm.gd gives every bin (chapter1/tests/measure_rhythm.gd, finalize()); the log must carry them all.
const BIN_KEYS := ["label","from_s","to_s","secs","kills","kpm","alive_avg","alive_p90","alive_max","hits","hits_pm","dmg","dmg30","attacks","prim_hits","prim_hits_per_kill","grace","grace_times","drops","wave_crests"]
var failures: Array[String] = []

func _initialize() -> void:
	_check_args()
	_check_run()
	_cleanup()
	if failures.is_empty():
		print("TEST_PLAYLOG pass")
		quit(0)
	else:
		for f in failures: push_error("TEST_PLAYLOG "+f)
		print("TEST_PLAYLOG fail ",JSON.stringify(failures))
		quit(1)

func _expect(ok: bool, what: String) -> void:
	if not ok: failures.append(what)

func _dir(args: Array) -> Dictionary:
	return Recorder.resolve_dir(PackedStringArray(args))

func _check_args() -> void:
	_expect(_dir([]).dir == "","off by default")
	_expect(_dir(["--chapter1-pilot"]).dir == "","other arguments leave it off")
	_expect(_dir(["--chapter1-playlog"]).dir == "user://playlogs","bare flag writes to user://playlogs")
	_expect(_dir(["--chapter1-playlog","--chapter1-profile-off"]).dir == "res://_local/playtests","bare flag with the profile off goes to _local/playtests")
	_expect(_dir(["--chapter1-playlog=_local/playtests"]).dir == "res://_local/playtests","a path under _local is taken")
	_expect(_dir(["--chapter1-playlog=./_local/x/y/"]).dir == "res://_local/x/y","./ and a trailing slash are removed")
	for bad in ["chapter1/data","..","_local/../chapter1","user://playlogs","C:/Windows/Temp","/tmp/x","_local2/x","_localx"]:
		var got := _dir(["--chapter1-playlog="+bad])
		_expect(got.dir == "" and not String(got.error).is_empty(),"refused: "+bad)
	# The user's profile folder is never a target: nothing here points at the profile file name.
	_expect(not String(_dir(["--chapter1-playlog"]).dir).contains("chapter-one-profile"),"never next to the profile file")

func _check_run() -> void:
	var rec: Node = Recorder.new()
	rec.enabled = true
	rec.dir_path = DIR
	var core: RefCounted = Core.new()
	var pilot = Pilot.new()
	pilot.run = core
	_expect(core.start(5,"chapter1.skill.frost"),"core starts")
	rec.begin_run(core)
	rec._primary = "chapter1.skill.frost"
	rec._primary_short = "frost"
	rec._seed = 5
	_expect(rec.active,"recorder is active after begin_run")
	var snapshot_before := JSON.stringify(core.snapshot())
	var steps := 0
	var tick_hash := 0
	while core.mode not in ["victory","defeat"] and steps < 5400:
		var move: Vector2 = pilot.decide()
		core.step(move)
		rec.observe(core,core.growth.snapshot())
		steps += 1
	_expect(steps > 0 and rec.active,"run went on while recording (mode %s)" % core.mode)
	# A read-only recorder leaves the core exactly as an unrecorded run would: replay the same run without it.
	var twin: RefCounted = Core.new()
	var twin_pilot = Pilot.new()
	twin_pilot.run = twin
	twin.start(5,"chapter1.skill.frost")
	for i in steps: twin.step(twin_pilot.decide())
	_expect(JSON.stringify(twin.snapshot()) == JSON.stringify(core.snapshot()),"recording does not change the core (snapshot equals the unrecorded twin)")
	_expect(snapshot_before != "","snapshot taken")
	rec.finish("quit","test")
	_expect(not rec.active,"inactive after finish")
	_expect(rec.written_paths.size() == 1,"one file written")
	rec.finish("quit","again")
	_expect(rec.written_paths.size() == 1,"a second finish writes nothing")
	if rec.written_paths.is_empty(): return
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(rec.written_paths[0]))
	_expect(document is Dictionary,"file is a JSON object")
	if not document is Dictionary: return
	for key in ["played_at","witch","result","minutes","answers","primary","seed","mode","secs","kills","summary","boons","bins","build","marks","bin_s"]:
		_expect(document.has(key),"key present: "+key)
	_expect(String(document.played_at).length() == 16,"played_at looks like 2026-11-19 17:53")
	_expect(document.witch == "frost" and document.result == "quit" and document.answers is Dictionary and document.answers.is_empty(),"witch/result/answers in the shape the manager reads")
	_expect(int(document.kills) == int(core.kills),"kills match the core (%d vs %d)" % [int(document.kills),int(core.kills)])
	var bin_kills := 0
	var bin_hits := 0
	for bin in document.bins:
		for key in BIN_KEYS: _expect(bin.has(key),"bin key: "+key)
		bin_kills += int(bin.kills)
		bin_hits += int(bin.hits)
	_expect(bin_kills == int(core.kills),"bins add up to the core's kills (%d vs %d)" % [bin_kills,int(core.kills)])
	_expect(bin_hits == int(document.summary.hits_total),"summary hits match the bins")
	_expect(document.boons.size() == pilot.selections.size(),"one boon entry per pick (%d vs %d)" % [document.boons.size(),pilot.selections.size()])
	for i in document.boons.size():
		_expect(int(document.boons[i].tick) >= 0 and String(document.boons[i].kind) != "","boon %d has a tick and a kind" % i)
	# A defeat carries the last 30 seconds; a quit does not.
	_expect(not document.has("last30"),"no last30 on a quit")
	var down: Node = Recorder.new()
	down.enabled = true
	down.dir_path = DIR
	var core2: RefCounted = Core.new()
	core2.start(6,"chapter1.skill.ember")
	var pilot2 = Pilot.new()
	pilot2.run = core2
	down.begin_run(core2)
	for i in 600:
		core2.step(pilot2.decide())
		down.observe(core2,core2.growth.snapshot())
	core2.abandon()
	down.observe(core2,core2.growth.snapshot())
	_expect(down.written_paths.size() == 1,"an abandon writes the file")
	if down.written_paths.size() == 1:
		var doc2: Variant = JSON.parse_string(FileAccess.get_file_as_string(down.written_paths[0]))
		_expect(doc2 is Dictionary and doc2.result == "quit" and doc2.mode == "abandoned","abandon is recorded as quit/abandoned")
	# The same name is never overwritten.
	var again: Node = Recorder.new()
	again.enabled = true
	again.dir_path = DIR
	var core3: RefCounted = Core.new()
	core3.start(5,"chapter1.skill.frost")
	again.begin_run(core3)
	for i in 120:
		core3.step(Vector2.ZERO)
		again.observe(core3,core3.growth.snapshot())
	again._seed = 5
	again._primary_short = "frost"
	again.finish("quit","test")
	for path in again.written_paths: _expect(not rec.written_paths.has(path),"a new file, not an overwrite: "+path)
	rec.free()
	down.free()
	again.free()

func _cleanup() -> void:
	var folder := ProjectSettings.globalize_path(DIR)
	var listing := DirAccess.open(folder)
	if listing == null: return
	for name_ in listing.get_files():
		if name_.ends_with(".json"): listing.remove(name_)
	DirAccess.remove_absolute(folder)
