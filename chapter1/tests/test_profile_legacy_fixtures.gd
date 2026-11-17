extends SceneTree
## T5-S0 check: the frozen schema-3/2/1 files are unchanged, and the CURRENT chapter_profile.gd still reads each of
## them exactly as expected_v3.json says (configure result, state, characters, starting/blocked gear per witch, item names).
## It reads the fixture folder only; every file it stages lives under res://_local/. Marker: CHAPTER1_PROFILE_LEGACY_RESULT.
## After schema 4 lands this check is replaced by S1's migration check (V-4 compares the migrated result to expected_v3.json).
const Snap=preload("res://chapter1/tests/profile_legacy_snapshot.gd")
const FIXTURES := "res://chapter1/tests/fixtures/profile_legacy"
var checks := 0
var failures: Array[String]=[]

func _initialize() -> void:call_deferred("execute")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)

func execute() -> void:
	var work := "res://_local/profile-legacy-check"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--work-dir="):work=argument.trim_prefix("--work-dir=")
	var expected_text := FileAccess.get_file_as_string(FIXTURES+"/expected_v3.json")
	var parser := JSON.new()
	check(not expected_text.is_empty() and parser.parse(expected_text)==OK and parser.data is Dictionary,"expected_v3.json is readable")
	if not failures.is_empty():_finish();return
	var expected: Dictionary=parser.data
	# 1. the frozen bytes
	for file_name in expected.sha256:
		check(FileAccess.file_exists(FIXTURES+"/"+file_name) and FileAccess.get_sha256(FIXTURES+"/"+file_name)==String(expected.sha256[file_name]),"fixture bytes unchanged: "+String(file_name))
	var journal_files := Snap.journal_names(FIXTURES)
	var listed := 0
	for file_name in journal_files:
		if expected.sha256.has(Snap.JOURNAL_DIR+"/"+file_name):listed+=1
	check(listed==journal_files.size() and journal_files.size()==7,"journal folder holds exactly the 7 listed files")
	# 2. the current code reads each scenario as recorded
	for name in Snap.SCENARIOS:
		var now: Dictionary=Snap.run_scenario(name,FIXTURES,work+"/"+name)
		var then: Variant=expected.scenarios.get(name)
		check(then is Dictionary,"expected has scenario "+name)
		if not then is Dictionary:continue
		check(now.read_left_files_untouched and not now.read_wrote_new_files,"reading writes nothing and leaves the files as they were: "+name)
		check(_norm(now)==_norm(then),"scenario reads as recorded: "+name+_first_difference(now,then))
	# 3. S0 pass criterion (2), stated directly
	var by_name := {}
	for name in ["v3_full","v3_rare_oldword","v3_rare_threeword","v3_journals_main_only","v3_journals_with_pointer"]:by_name[name]=expected.scenarios[name]
	for name in ["v3_full","v3_rare_oldword","v3_rare_threeword"]:check(by_name[name].configure==true and by_name[name].available==true,name+" is accepted")
	check(by_name.v3_journals_main_only.configure==false and by_name.v3_journals_main_only.reject_kind=="incompatible","v3_with_journals main file is refused as incompatible")
	check(not by_name.v3_journals_main_only.resume.is_empty() and by_name.v3_journals_main_only.resume.revision==4,"the newest readable journal copy (revision 4) is the resume candidate")
	check(by_name.v3_journals_with_pointer.configure==true and String(by_name.v3_journals_with_pointer.file).begins_with("chapter-one-profile-v3-r"),"the pointer file leads to the r-file")
	_finish()

## Round-trip through text so integers read back from the file (floats) compare equal to the live ones.
func _norm(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)),"  ")

func _first_difference(now: Dictionary,then: Dictionary) -> String:
	for key in then:
		if _norm(now.get(key))!=_norm(then[key]):return " (first differing key: "+String(key)+")"
	for key in now:
		if not then.has(key):return " (new key: "+String(key)+")"
	return ""

func _finish() -> void:
	if "--negative" in OS.get_cmdline_user_args():check(false,"Intentional checker failure")
	print("CHAPTER1_PROFILE_LEGACY_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
