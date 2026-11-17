extends SceneTree
## Golden replay of the runtime core. Same seed + same input policy must give the
## same state at every checkpoint. Used as the equivalence gate for refactoring:
## a restructured core must reproduce these hashes exactly.
##
##   --script res://chapter1/tests/golden_core.gd                compare with golden file
##   ... -- --update                                             rewrite the golden file
##   ... -- --core=res://chapter1/core/other.gd                  compare another core script
##   ... -- --case=11:chapter1.skill.frost                       run one case only
##   ... -- --textless [--update]                                hash with text fields removed; uses core_runtime_textless.json
const DEFAULT_CORE := "res://chapter1/core/chapter_core.gd"
const PILOT := "res://chapter1/core/chapter_pilot.gd"
const GOLDEN_DEFAULT := "res://chapter1/tests/golden/core_runtime.json"
const GOLDEN_TEXTLESS := "res://chapter1/tests/golden/core_runtime_textless.json"
## Fields removed (recursively, at any depth) before hashing in --textless mode.
const TEXT_FIELDS := ["name","title","description","rare_words","legacy_name","title_key"]
var GOLDEN := GOLDEN_DEFAULT
var textless := false
## [seed, primary] or [seed, primary, label, build fixture]. The fourth case is a fixed Lv 20 lance build.
const CASES := [[11,"chapter1.skill.frost"],[11,"chapter1.skill.ember"],[11,"chapter1.skill.arc"],[11,"chapter1.skill.frost","L20-lance","res://chapter1/tests/fixtures/build_l20_lance.json"]]
const CHECKPOINT_TICKS := 600
const MAX_TICKS := 12*60*60

func _initialize() -> void:
	call_deferred("execute")

func strip_text(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key in value:
			if TEXT_FIELDS.has(str(key)):continue
			out[key]=strip_text(value[key])
		return out
	if value is Array:
		var out_array := []
		for item in value:out_array.append(strip_text(item))
		return out_array
	return value

func digest(run: RefCounted) -> String:
	var snap: Variant=run.snapshot()
	if textless:snap=strip_text(snap)
	return JSON.stringify(snap).sha256_text()

func play(core_path: String,seed_: int,primary: String,build_path: String="") -> Dictionary:
	var run: RefCounted=load(core_path).new()
	var pilot: RefCounted=load(PILOT).new()
	pilot.run=run
	if not build_path.is_empty():
		var build: Variant=JSON.parse_string(FileAccess.get_file_as_string(build_path))
		if not build is Dictionary or not run.configure_build(build):
			return {"error":"build rejected: "+str(run.errors)}
	if not run.start(seed_,primary):
		return {"error":"start rejected: "+str(run.errors)}
	var checkpoints: Array[String]=[]
	var iterations := 0
	while run.mode not in ["victory","defeat"] and run.tick<MAX_TICKS and iterations<MAX_TICKS+500:
		run.step(pilot.decide())
		iterations+=1
		if run.tick%CHECKPOINT_TICKS==0:checkpoints.append("%d:%s" % [run.tick,digest(run)])
	return {"seed":seed_,"primary":primary,"mode":run.mode,"tick":run.tick,"kills":run.kills,"hp_raw":run.hero.hp_raw,"level":run.growth.snapshot().level,"final":digest(run),"checkpoints":checkpoints}

func execute() -> void:
	var core_path := DEFAULT_CORE
	var update := false
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg=="--update":update=true
		elif arg=="--textless":textless=true;GOLDEN=GOLDEN_TEXTLESS
		elif arg.begins_with("--core="):core_path=arg.trim_prefix("--core=")
		elif arg.begins_with("--case="):only=arg.trim_prefix("--case=")
	var results: Dictionary={}
	for entry in CASES:
		var key := "%d:%s" % [entry[0],entry[1]]
		if entry.size()>2:key+=":"+String(entry[2])
		if not only.is_empty() and only!=key:continue
		results[key]=play(core_path,entry[0],entry[1],String(entry[3]) if entry.size()>3 else "")
		var r: Dictionary=results[key]
		print("GOLDEN_CASE ",JSON.stringify({"case":key,"mode":r.get("mode",""),"tick":r.get("tick",0),"kills":r.get("kills",0),"final":r.get("final",""),"error":r.get("error","")}))
	if update:
		if core_path!=DEFAULT_CORE or not only.is_empty():
			push_error("--update needs the default core and all cases");quit(2);return
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GOLDEN.get_base_dir()))
		var file := FileAccess.open(GOLDEN,FileAccess.WRITE)
		file.store_string(JSON.stringify({"core":core_path,"checkpoint_ticks":CHECKPOINT_TICKS,"cases":results},"  "))
		file.close()
		print("GOLDEN_RESULT ",JSON.stringify({"updated":true,"cases":results.size()}))
		quit(0);return
	if not FileAccess.file_exists(GOLDEN):
		push_error("Golden file missing; run with -- --update");quit(2);return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(GOLDEN)).cases
	var mismatches: Array[String]=[]
	for key in results:
		var got: Dictionary=results[key]
		if not expected.has(key):mismatches.append(key+": no golden entry");continue
		var want: Dictionary=expected[key]
		if got.has("error"):mismatches.append(key+": "+str(got.error));continue
		var first := ""
		for i in mini(got.checkpoints.size(),want.checkpoints.size()):
			if got.checkpoints[i]!=want.checkpoints[i]:first=String(got.checkpoints[i]).get_slice(":",0);break
		if not first.is_empty():mismatches.append(key+": first divergence at tick "+first)
		elif got.final!=want.final or int(got.tick)!=int(want.tick) or got.mode!=want.mode:
			mismatches.append("%s: end state differs (tick %d vs %d, %s vs %s)" % [key,got.tick,want.tick,got.mode,want.mode])
	print("GOLDEN_RESULT ",JSON.stringify({"core":core_path,"cases":results.size(),"mismatches":mismatches}))
	quit(0 if mismatches.is_empty() else 1)
