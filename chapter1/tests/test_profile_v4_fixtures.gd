extends SceneTree
## T6-S0 check against the frozen schema-4 files (chapter1/tests/fixtures/profile_v4/, never regenerated). Two parts:
##  1. the frozen bytes are unchanged (sha256 listed in expected_v4.json; the existing profile_v4_compat.json too),
##  2. the chapter_profile.gd of the day (schema 5) carries each scenario over as expected_v4.json says the schema-4 code
##     read it. The scenarios are handed over as the schema-4 SOURCE of a schema-5 profile (run_scenario_as_source).
## The whole description is compared (state, witches, kits, wardrobe, resume candidate), with the screen words (`name`,
## `description`) left out of that comparison; the screen names are compared on their own so a rename is told apart.
## The only differences allowed (T6 V5-4), applied to the recorded values by _as_v5: `schema_version` 5, `town` at its defaults,
## `origin` the empty record (the source is in `origin_hint`), the three new cells (`quests`, `records`, `grace`) at their
## defaults in every witch and in the set-aside witch's `raw`, the file name, and for v4_journals_main_only (T6 V5-6) the
## refusal kind `legacy` with the resume candidate kind `v4_journal`.
## Reading writes nothing and leaves every staged file as it was. Never change this file's expectations, expected_v4.json or
## the frozen files to pass.
## Only res://_local/ is written. Marker: CHAPTER1_PROFILE_V4_FIXTURES_RESULT.
const Profile=preload("res://chapter1/core/chapter_profile.gd")
const Snap=preload("res://chapter1/tests/profile_v4_snapshot.gd")
const FIXTURES := "res://chapter1/tests/fixtures/profile_v4"
var checks := 0
var failures: Array[String]=[]

func _initialize() -> void:call_deferred("execute")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)

func execute() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains("/_local/appdata/"):
		print("CHAPTER1_PROFILE_V4_FIXTURES_RESULT ",JSON.stringify({"checks":0,"failures":["user data dir is not isolated: refusing to run"]}))
		quit(1);return
	var work := "res://_local/profile-v4-fixtures-check"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--work-dir="):work=argument.trim_prefix("--work-dir=")
	if not work.begins_with("res://_local/") or ".." in work:
		print("CHAPTER1_PROFILE_V4_FIXTURES_RESULT ",JSON.stringify({"checks":0,"failures":["work dir must be under res://_local/"]}))
		quit(1);return
	var expected_text := FileAccess.get_file_as_string(FIXTURES+"/expected_v4.json")
	var parser := JSON.new()
	check(not expected_text.is_empty() and parser.parse(expected_text)==OK and parser.data is Dictionary,"expected_v4.json is readable")
	if not failures.is_empty():_finish();return
	var expected: Dictionary=parser.data
	# 1. the frozen bytes
	for rel in expected.sha256:
		check(FileAccess.file_exists(FIXTURES+"/"+rel) and FileAccess.get_sha256(FIXTURES+"/"+rel)==String(expected.sha256[rel]),"fixture bytes unchanged: "+String(rel))
	for rel in expected.external_sha256:
		check(FileAccess.get_sha256(Snap.COMPAT_ROOT+"/"+rel)==String(expected.external_sha256[rel]),"existing fixture bytes unchanged: "+String(rel))
	var present: Array[String]=[]
	for rel in Snap.list_files(FIXTURES):
		if rel!="expected_v4.json" and rel!="README.ko.md":present.append(rel)
	var listed: Array[String]=[]
	for rel in expected.sha256:listed.append(String(rel))
	listed.sort()
	check(present==listed and present.size()==8,"the fixture folder holds exactly the 8 listed files (%d found)"%present.size())
	# 2. each scenario read as recorded
	var then_by_name: Dictionary=expected.scenarios
	for name in Snap.SCENARIOS:
		var then: Variant=then_by_name.get(name)
		check(then is Dictionary,"expected has scenario "+name)
		if not then is Dictionary:continue
		var now: Dictionary=Snap.run_scenario_as_source(name,FIXTURES,work+"/"+name)
		check(now.read_left_files_untouched and not now.read_wrote_new_files,"reading writes nothing and leaves the files as they were: "+name)
		check(_same(_without_text(now),_without_text(_as_v5(then,name))),name+": carried over as the schema-4 code read it, apart from the schema-5 differences (everything but screen words)")
		check(_same(now.item_names,then.item_names),name+": the screen names are the same as recorded")
	# 3. the S0 pass criteria, stated on the recorded values and on what was read now
	var now_full: Dictionary=Snap.run_scenario_as_source("v4_full",FIXTURES,work+"/v4_full")
	var now_compat: Dictionary=Snap.run_scenario_as_source("v4_compat",FIXTURES,work+"/v4_compat")
	var now_main: Dictionary=Snap.run_scenario_as_source("v4_journals_main_only",FIXTURES,work+"/v4_journals_main_only")
	var now_pointer: Dictionary=Snap.run_scenario_as_source("v4_journals_with_pointer",FIXTURES,work+"/v4_journals_with_pointer")
	for name in ["v4_full","v4_compat","v4_journals_with_pointer"]:
		check(then_by_name[name].configure==true and then_by_name[name].available==true and String(then_by_name[name].reject_kind).is_empty(),name+" was accepted by the schema-4 code")
	check(now_full.configure and now_compat.configure and now_pointer.configure,"v4_full, v4_compat and v4_journals_with_pointer are accepted now")
	check(then_by_name.v4_journals_main_only.configure==false and then_by_name.v4_journals_main_only.reject_kind=="incompatible","v4_journals_main_only was refused as incompatible by the schema-4 code")
	check(not now_main.configure and now_main.reject_kind=="legacy" and now_main.reject_reason==then_by_name.v4_journals_main_only.reject_reason,"v4_journals_main_only is refused now as a broken schema-4 original (legacy), for the reason the schema-4 code gave (V5-6)")
	check(int(then_by_name.v4_journals_main_only.resume.revision)==4 and int(now_main.resume.revision)==4 and now_main.resume.kind=="v4_journal","the resume candidate is schema-4 journal revision 4 (kind v4_journal)")
	check(String(now_pointer.origin_hint.from_file).begins_with("chapter-one-profile-v4-r") and String(then_by_name.v4_journals_with_pointer.file).begins_with("chapter-one-profile-v4-r"),"the pointer led to the r-file (recorded file name; carried-over origin hint)")
	check(int(now_full.state.schema_version)==5 and int(now_compat.state.schema_version)==5,"the memory state is schema 5")
	# v4_full holds every cell with a value other than the default
	var state: Dictionary=now_full.state
	var frost: Dictionary=now_full.characters["chapter1.character.frost"]
	check(frost.wardrobe.worn=="chapter1.outfit.frost.swim_1" and now_full.characters["chapter1.character.ember"].wardrobe.worn=="chapter1.outfit.ember.swim_2","frost and ember wear an outfit")
	check(frost.story.seen.size()==2 and frost.story.found.size()==1 and state.shared_story.seen.size()==1,"story seen / found and shared story seen are filled")
	check(frost.tree_reset.granted==["d1"] and _same(frost.depth_cleared,{"d1":1}),"tree_reset has an id and depth_cleared is {d1:1}")
	check(not state.codex.uniques.is_empty() and not state.codex.legendaries.is_empty(),"codex is filled")
	var locked := 0;var fresh := 0
	for record in state.items:
		if record.get("locked",false):locked+=1
		if record.get("new",false):fresh+=1
	check(locked==1 and fresh==1,"one locked and one new item")
	var kinds := []
	for entry in state.quarantine:kinds.append(String(entry.kind))
	kinds.sort()
	check(kinds==["character","item"] and state.quarantine.filter(func(e): return e.kind=="character")[0].id=="chapter1.character.ghost","one set-aside item and the set-aside ghost witch")
	var loadouts := []
	for witch in Snap.WITCHES:loadouts.append(JSON.stringify(_stable(now_full.witches[witch].loadout)))
	check(loadouts[0]!=loadouts[1] and loadouts[1]!=loadouts[2] and loadouts[0]!=loadouts[2],"each witch wears a different kit")
	check(int(then_by_name.v4_full.state.origin.from_schema)==3 and int(state.origin.from_schema)==0 and int(now_full.origin_hint.from_schema)==4 and int(now_full.origin_hint.from_revision)==int(then_by_name.v4_full.state.revision),"the recorded file says it came from schema 3; the carried-over memory has the empty origin and the hint names schema 4 and its revision (5.3)")
	_finish()

## The recorded schema-4 reading turned into what the schema-5 code must give for the same file: only the differences the
## specification names are applied (T6 V5-4 and V5-6).
func _as_v5(then: Dictionary,name: String) -> Dictionary:
	var want: Dictionary=_stable(then)
	want.state.schema_version=5
	want.state.town=Profile.default_town()
	want.state.origin={"from_schema":0,"from_file":"","from_revision":0,"at_unix":0}
	var additions := Profile.default_additions()
	for id_ in want.characters:
		if Profile.CHAR_KEYS_V4.size()==want.characters[id_].size():want.characters[id_].merge(additions.duplicate(true))
	for entry in want.state.quarantine:
		if entry.kind=="character" and entry.raw is Dictionary and entry.raw.size()==Profile.CHAR_KEYS_V4.size():entry.raw.merge(additions.duplicate(true))
	want.file="chapter-one-profile-v5.json"
	if bool(then.configure):
		want.origin_hint={"from_schema":4,"from_file":then.file,"from_revision":int(then.state.revision)}
	else:
		want.reject_kind="legacy"
		want.error_code="old_rejected"
		want.resume.kind="v4_journal"
	return want

## Everything of a description except the screen words: item and kit names and descriptions, and the name table.
func _without_text(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value:
			if (key=="name" or key=="description" or key=="item_names") and not value[key] is Dictionary:continue
			if key=="item_names":continue
			result[key]=_without_text(value[key])
		return result
	if value is Array:
		var list: Array=[]
		for entry in value:list.append(_without_text(entry))
		return list
	return value

## True when both are equal after a text round trip (numbers read from a file are floats, numbers in memory are ints).
func _same(a: Variant,b: Variant) -> bool:
	return JSON.stringify(_stable(a))==JSON.stringify(_stable(b))

func _stable(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))

func _finish() -> void:
	if "--negative" in OS.get_cmdline_user_args():check(false,"Intentional checker failure")
	print("CHAPTER1_PROFILE_V4_FIXTURES_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
