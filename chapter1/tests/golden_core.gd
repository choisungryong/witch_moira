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
##   ... -- --both [--update]                                    ONE play of each case, hashed both ways, compared with both files
##                                                               (prints GOLDEN_RESULT for the default file and GOLDEN_TEXTLESS_RESULT)
##   ... -- --text-check                                         also run the core-text observer on the three plain cases (no build
##                                                               fixture) during the same play; prints CORE_TEXT_PART
##   ... -- --list-cases                                         print the case keys (GOLDEN_CASE_LIST) and stop; run_all.py splits on them
##   ... -- --golden=<res/abs path> --golden-textless=<path>     read these baselines instead (a negative test points at a copy)
##   ... -- --dump-at=<tick> --dump-out=<path under _local/>     write snapshot() at that tick as sorted JSON and stop that case
##                                                               there (no comparison). More than one case: the case key is added to the name.
## The hash is JSON.stringify(snapshot()).sha256_text() at every 600th tick and at the end, unchanged.
const DEFAULT_CORE := "res://chapter1/core/chapter_core.gd"
const PILOT := "res://chapter1/core/chapter_pilot.gd"
const PROBE := "res://chapter1/tests/core_text_probe.gd"
const GOLDEN_DEFAULT := "res://chapter1/tests/golden/core_runtime.json"
const GOLDEN_TEXTLESS := "res://chapter1/tests/golden/core_runtime_textless.json"
## Fields removed (recursively, at any depth) before hashing in --textless mode.
const TEXT_FIELDS := ["name","title","description","rare_words","legacy_name","title_key"]
var GOLDEN := GOLDEN_DEFAULT
var golden_default_path := GOLDEN_DEFAULT
var golden_textless_path := GOLDEN_TEXTLESS
var textless := false
var both := false
var text_check := false
var dump_at := -1
var dump_out := ""
## [seed, primary] or [seed, primary, label, build fixture] or [seed, primary, label, build fixture, setup]. The fourth case is a fixed Lv 20
## lance build. The fifth is the D19 C1 path: rhythm + opening + spell composition + the first growth-pace values (setup "rhythm-c1"), the
## parked-off systems turned on in memory by TrialDocs (the data files stay off, so the four cases above keep their hashes). The sixth is the
## D23 T1 path: the affix_rolls equipment roll on (setup "affix-on", this run's own loot tables; the data file stays off). The seventh (pity-armed) is the D23 T9 pity at its line; the eighth (gear-t17) wears tests/fixtures/golden_gear.json kit.golden.t17 (thorns body, streak boots) right after start(); the ninth (luck-on) turns the D23 T8 luck on in this run's loot tables and wears kit.golden.t8 (luck lines over the cap, grace_luck_4 on the head).
const TrialDocs := preload("res://chapter1/tests/support/trial_docs.gd")
const CASES := [[11,"chapter1.skill.frost"],[11,"chapter1.skill.ember"],[11,"chapter1.skill.arc"],[11,"chapter1.skill.frost","L20-lance","res://chapter1/tests/fixtures/build_l20_lance.json"],[11,"chapter1.skill.ember","rhythm-c1","","rhythm-c1"],[11,"chapter1.skill.frost","affix-on","","affix-on"],[11,"chapter1.skill.frost","pity-armed","","pity-armed"],[11,"chapter1.skill.frost","gear-t17","","gear-t17"],[11,"chapter1.skill.frost","luck-on","","luck-on"]]
const CHECKPOINT_TICKS := 600
const MAX_TICKS := 12*60*60
var probe: RefCounted = null

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

func digest(run: RefCounted,strip: bool=false) -> String:
	var snap: Variant=run.snapshot()
	if strip:snap=strip_text(snap)
	return JSON.stringify(snap).sha256_text()

func play(core_path: String,seed_: int,primary: String,build_path: String="",observe: bool=false,dump_path: String="",setup: String="") -> Dictionary:
	var run: RefCounted=load(core_path).new()
	var pilot: RefCounted=load(PILOT).new()
	pilot.run=run
	if setup=="rhythm-c1":
		var problem := TrialDocs.enable_rhythm_problem(run,false,true)
		if problem.is_empty():problem=TrialDocs.enable_spells_problem(run)
		if not problem.is_empty():return {"error":"setup rejected: "+problem}
	elif setup=="affix-on":
		var affix_problem := TrialDocs.enable_affix_rolls_problem(run)
		if not affix_problem.is_empty():return {"error":"setup rejected: "+affix_problem}
	elif setup=="pity-armed":
		var pity_problem := TrialDocs.enable_pity_problem(run)
		if not pity_problem.is_empty():return {"error":"setup rejected: "+pity_problem}
	elif setup=="luck-on":
		var luck_problem := TrialDocs.enable_luck_problem(run)
		if not luck_problem.is_empty():return {"error":"setup rejected: "+luck_problem}
	if not build_path.is_empty():
		var build: Variant=JSON.parse_string(FileAccess.get_file_as_string(build_path))
		if not build is Dictionary or not run.configure_build(build):
			return {"error":"build rejected: "+str(run.errors)}
	if not run.start(seed_,primary):
		if observe:probe.finish(primary,run,"start rejected: "+str(run.errors))
		return {"error":"start rejected: "+str(run.errors)}
	# D23 T17: the gear kit goes on right after start() succeeded and before the first step (the town-to-run path).
	if setup=="gear-t17":
		var gear_problem := TrialDocs.wear_fixture_kit_problem(run,"kit.golden.t17")
		if not gear_problem.is_empty():return {"error":"setup rejected: "+gear_problem}
	# D23 T8: the luck kit (four luck lines, sum over the cap; grace_luck_4 on the head, dead while the grace grades are off) goes on the same way.
	if setup=="luck-on":
		var luck_gear_problem := TrialDocs.wear_fixture_kit_problem(run,"kit.golden.t8")
		if not luck_gear_problem.is_empty():return {"error":"setup rejected: "+luck_gear_problem}
	if observe:probe.begin()
	var checkpoints: Array[String]=[]
	var checkpoints_textless: Array[String]=[]
	var iterations := 0
	while run.mode not in ["victory","defeat"] and run.tick<MAX_TICKS and iterations<MAX_TICKS+500:
		run.step(pilot.decide())
		iterations+=1
		if observe:probe.observe(run)
		if dump_at>=0 and run.tick==dump_at:
			write_dump(run,dump_path)
			return {"seed":seed_,"primary":primary,"mode":run.mode,"tick":run.tick,"kills":run.kills,"dumped":dump_path}
		if run.tick%CHECKPOINT_TICKS==0:
			checkpoints.append("%d:%s" % [run.tick,digest(run,textless)])
			if both:checkpoints_textless.append("%d:%s" % [run.tick,digest(run,true)])
	if observe:probe.finish(primary,run)
	var result := {"seed":seed_,"primary":primary,"mode":run.mode,"tick":run.tick,"kills":run.kills,"hp_raw":run.hero.hp_raw,"level":run.growth.snapshot().level,"final":digest(run,textless),"checkpoints":checkpoints}
	if both:
		result["final_textless"]=digest(run,true)
		result["checkpoints_textless"]=checkpoints_textless
	return result

func write_dump(run: RefCounted,path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null:
		push_error("dump: cannot write "+path);return
	file.store_string(JSON.stringify(run.snapshot(),"  ",true))
	file.close()

func dump_path_for(key: String,several: bool) -> String:
	var path := dump_out
	if several:
		var safe := key.replace(":","_").replace(".","_")
		path=path.get_basename()+"."+safe+"."+path.get_extension()
	return path

## Mismatch lines of `results` against the baseline file. `field` picks the digest set: "" or "_textless".
func compare(results: Dictionary,golden_path: String,suffix: String) -> Array[String]:
	var mismatches: Array[String]=[]
	if not FileAccess.file_exists(golden_path):
		push_error("Golden file missing: "+golden_path+"; run with -- --update");return ["golden file missing: "+golden_path]
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(golden_path)).cases
	for key in results:
		var got: Dictionary=results[key]
		if not expected.has(key):mismatches.append(key+": no golden entry");continue
		var want: Dictionary=expected[key]
		if got.has("error"):mismatches.append(key+": "+str(got.error));continue
		var got_checkpoints: Array=got["checkpoints"+suffix]
		var got_final: String=got["final"+suffix]
		var first := ""
		for i in mini(got_checkpoints.size(),want.checkpoints.size()):
			if got_checkpoints[i]!=want.checkpoints[i]:first=String(got_checkpoints[i]).get_slice(":",0);break
		if not first.is_empty():mismatches.append(key+": first divergence at tick "+first)
		elif got_final!=want.final or int(got.tick)!=int(want.tick) or got.mode!=want.mode:
			mismatches.append("%s: end state differs (tick %d vs %d, %s vs %s)" % [key,got.tick,want.tick,got.mode,want.mode])
	return mismatches

## A result set seen through one digest set, shaped like a single-mode run.
func view(results: Dictionary,suffix: String) -> Dictionary:
	var out := {}
	for key in results:
		var r: Dictionary=results[key]
		if r.has("error"):out[key]=r;continue
		var copy := r.duplicate()
		if not suffix.is_empty():
			copy["final"]=r["final"+suffix]
			copy["checkpoints"]=r["checkpoints"+suffix]
		copy.erase("final_textless")
		copy.erase("checkpoints_textless")
		out[key]=copy
	return out

func store(path: String,core_path: String,results: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"core":core_path,"checkpoint_ticks":CHECKPOINT_TICKS,"cases":results},"  "))
	file.close()

func execute() -> void:
	var core_path := DEFAULT_CORE
	var update := false
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg=="--update":update=true
		elif arg=="--textless":textless=true
		elif arg=="--both":both=true
		elif arg=="--text-check":text_check=true
		elif arg.begins_with("--core="):core_path=arg.trim_prefix("--core=")
		elif arg.begins_with("--case="):only=arg.trim_prefix("--case=")
		elif arg.begins_with("--golden="):golden_default_path=arg.trim_prefix("--golden=")
		elif arg.begins_with("--golden-textless="):golden_textless_path=arg.trim_prefix("--golden-textless=")
		elif arg.begins_with("--dump-at="):dump_at=int(arg.trim_prefix("--dump-at="))
		elif arg.begins_with("--dump-out="):dump_out=arg.trim_prefix("--dump-out=")
	if OS.get_cmdline_user_args().has("--list-cases"):
		var keys: Array=[]
		for entry in CASES:keys.append("%d:%s" % [entry[0],entry[1]]+(":"+String(entry[2]) if entry.size()>2 else ""))
		print("GOLDEN_CASE_LIST ",JSON.stringify(keys))
		quit(0);return
	if textless and both:
		push_error("--textless and --both exclude each other");quit(2);return
	GOLDEN=golden_textless_path if textless else golden_default_path
	if dump_at>=0:
		if not dump_out.is_empty() and not dump_out.begins_with("res://") and not dump_out.is_absolute_path():dump_out="res://"+dump_out
		var normal := (ProjectSettings.globalize_path(dump_out) if dump_out.begins_with("res://") else dump_out).replace("\\","/")
		if dump_out.is_empty() or dump_out.contains("..") or not normal.begins_with(ProjectSettings.globalize_path("res://_local/").replace("\\","/")):
			push_error("--dump-at needs --dump-out under _local/");quit(2);return
	if text_check:probe=load(PROBE).new()
	var selected: Array=[]
	for entry in CASES:
		var key := "%d:%s" % [entry[0],entry[1]]
		if entry.size()>2:key+=":"+String(entry[2])
		if only.is_empty() or only==key:selected.append([key,entry])
	var results: Dictionary={}
	for pair in selected:
		var key: String=pair[0]
		var entry: Array=pair[1]
		# Only the three plain cases were ever text-checked (test_core_text.gd has no build fixture case).
		var observe := text_check and entry.size()==2
		results[key]=play(core_path,entry[0],entry[1],String(entry[3]) if entry.size()>3 else "",observe,dump_path_for(key,selected.size()>1) if dump_at>=0 else "",String(entry[4]) if entry.size()>4 else "")
		var r: Dictionary=results[key]
		var line := {"case":key,"mode":r.get("mode",""),"tick":r.get("tick",0),"kills":r.get("kills",0),"final":r.get("final",""),"error":r.get("error","")}
		if both:line["final_textless"]=r.get("final_textless","")
		if dump_at>=0:line["dumped"]=r.get("dumped","")
		print("GOLDEN_CASE ",JSON.stringify(line))
	if text_check:print("CORE_TEXT_PART ",JSON.stringify(probe.part_report()))
	if dump_at>=0:
		print("GOLDEN_DUMP ",JSON.stringify({"tick":dump_at,"cases":results.size()}))
		quit(0);return
	if update:
		if core_path!=DEFAULT_CORE or not only.is_empty():
			push_error("--update needs the default core and all cases");quit(2);return
		if both:
			store(golden_default_path,core_path,view(results,""))
			store(golden_textless_path,core_path,view(results,"_textless"))
		else:
			store(GOLDEN,core_path,results)
		print("GOLDEN_RESULT ",JSON.stringify({"updated":true,"cases":results.size()}))
		quit(0);return
	if both:
		var plain := compare(results,golden_default_path,"")
		var bare := compare(results,golden_textless_path,"_textless")
		print("GOLDEN_RESULT ",JSON.stringify({"core":core_path,"cases":results.size(),"mismatches":plain}))
		print("GOLDEN_TEXTLESS_RESULT ",JSON.stringify({"core":core_path,"cases":results.size(),"mismatches":bare}))
		quit(0 if plain.is_empty() and bare.is_empty() else 1);return
	if not FileAccess.file_exists(GOLDEN):
		push_error("Golden file missing; run with -- --update");quit(2);return
	var mismatches := compare(results,GOLDEN,"")
	print("GOLDEN_RESULT ",JSON.stringify({"core":core_path,"cases":results.size(),"mismatches":mismatches}))
	quit(0 if mismatches.is_empty() else 1)
