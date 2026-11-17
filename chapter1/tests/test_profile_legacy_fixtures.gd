extends SceneTree
## T5-V4 / S1 check against the frozen schema-3/2/1 files (S0, never regenerated). Two parts:
##  1. the frozen bytes are unchanged (sha256 listed in expected_v3.json),
##  2. the schema-4 profile carries each file over exactly as expected_v3.json says the schema-3 code read it:
##     same items with the same screen names, same numbers, same first-run kit for each witch (names and descriptions
##     left out of the kit comparison, then the names compared on their own), same blocked pieces, and the one worn set
##     copied to all three witches (T5-U1). Reading writes nothing and leaves every staged file as it was.
## Expected differences, all asserted below instead of compared:
##  - `error` sentences: expected_v3.json holds the schema-3 Korean sentence. The profile now records `error_code` (the screen
##    words it from the code), so the check maps that one sentence to its code (ERROR_CODE_OF) and compares codes.
##  - `v3_journals_main_only`: the schema-3 code refused its main file (a changed stat). Schema 4 sets that one item aside in
##    `quarantine` and accepts the file (T5-D1), so there is no refusal and no resume candidate to compare.
##  - the schema-3 `equipped` table is now each witch's `loadout`; `starting_gear_without_witch` has no meaning any more.
## It reads the fixture folder only; every file it stages lives under res://_local/. Marker: CHAPTER1_PROFILE_LEGACY_RESULT.
const Snap=preload("res://chapter1/tests/profile_legacy_snapshot.gd")
const Profile=preload("res://chapter1/core/chapter_profile.gd")
const FIXTURES := "res://chapter1/tests/fixtures/profile_legacy"
## The schema-3 refusal sentence recorded in expected_v3.json and the code that sentence stands for.
const ERROR_CODE_OF := {"저장 파일 검증 실패 · 원본 보존":"file_rejected"}
var checks := 0
var failures: Array[String]=[]

func _initialize() -> void:call_deferred("execute")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)

func execute() -> void:
	# Safety: the checks may only run on the isolated user folder.
	if not OS.get_user_data_dir().replace("\\","/").contains("/_local/appdata/"):
		print("CHAPTER1_PROFILE_LEGACY_RESULT ",JSON.stringify({"checks":0,"failures":["user data dir is not isolated: refusing to run"]}))
		quit(1);return
	var work := "res://_local/profile-legacy-check"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--work-dir="):work=argument.trim_prefix("--work-dir=")
	if not work.begins_with("res://_local/"):
		print("CHAPTER1_PROFILE_LEGACY_RESULT ",JSON.stringify({"checks":0,"failures":["work dir must be under res://_local/"]}))
		quit(1);return
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
	# 2. the schema-4 profile carries each scenario over as recorded
	var then_by_name: Dictionary=expected.scenarios
	for name in Snap.SCENARIOS:
		var now: Dictionary=Snap.run_scenario(name,FIXTURES,work+"/"+name)
		var then: Variant=then_by_name.get(name)
		check(then is Dictionary,"expected has scenario "+name)
		if not then is Dictionary:continue
		check(now.read_left_files_untouched and not now.read_wrote_new_files,"reading writes nothing and leaves the files as they were: "+name)
		if name=="v3_journals_main_only":
			_journals_main_only(now,then)
			continue
		compare(name,now,then)
	# 3. the S0 pass criteria, stated directly
	for name in ["v3_full","v3_rare_oldword","v3_rare_threeword"]:
		check(then_by_name[name].configure==true and then_by_name[name].available==true,name+" was accepted by the schema-3 code")
	check(then_by_name.v3_journals_main_only.configure==false and then_by_name.v3_journals_main_only.reject_kind=="incompatible","v3_with_journals main file was refused as incompatible by the schema-3 code")
	check(then_by_name.v3_journals_main_only.resume.revision==4,"the schema-3 resume candidate was revision 4")
	check(String(then_by_name.v3_journals_with_pointer.file).begins_with("chapter-one-profile-v3-r"),"the schema-3 pointer led to the r-file")
	# 4. a structurally broken schema-3 file is still refused (read only), and the refusal is a code
	_broken_v3(work+"/broken")
	_finish()

## The refusal sentences the old code recorded map to a code; both sentences in the expected file are known.
func _error_code_for(sentence: String) -> String:
	return "" if sentence.is_empty() else String(ERROR_CODE_OF.get(sentence,"?"))

func compare(name: String,now: Dictionary,then: Dictionary) -> void:
	check(now.configure==then.configure and now.available==then.available and now.reject_kind==then.reject_kind,name+": accepted as before")
	check(now.error_code==_error_code_for(String(then.error)),name+": error_code stands for the recorded error sentence ("+String(now.error_code)+")")
	check(now.imported_from_v1==then.imported_from_v1 and now.imported_from_v2==then.imported_from_v2,name+": imported_from_v1/v2 as before")
	check(now.imported_from_v3==(name.begins_with("v3_")),name+": imported_from_v3 only for the schema-3 files")
	var old_state: Dictionary=then.state
	var state: Dictionary=now.state
	for key in ["next_id","completed_runs","best_ticks","essence","receipts","revision"]:
		check(_same(state[key],old_state[key]),name+": "+key+" carried over")
	check(int(state.schema_version)==4,name+": the memory state is schema 4")
	check(not state.has("equipped"),name+": the shared worn table is gone from the state")
	# the items, with their screen names and descriptions as the schema-3 code showed them
	check(state.items.size()==old_state.items.size(),name+": same number of items")
	var same_items: bool=state.items.size()==old_state.items.size()
	for index in mini(state.items.size(),old_state.items.size()):
		if JSON.stringify(_stable(state.items[index]))!=JSON.stringify(_stable(old_state.items[index])):
			same_items=false;push_error("item differs at "+str(index)+": "+JSON.stringify(state.items[index])+" vs "+JSON.stringify(old_state.items[index]))
	check(same_items,name+": every item is the schema-3 item with the same name and description")
	check(_same(now.item_names,then.item_names),name+": the screen names are the same as before")
	check(now.state.quarantine.is_empty() and now.read_report.is_empty(),name+": nothing set aside and nothing fixed while carrying over")
	# the witches' experience and first-kill records
	for witch in then.characters:
		var old_entry: Dictionary=then.characters[witch]
		var entry: Dictionary=now.characters.get(witch,{})
		for key in ["xp","tree_revision","ranks","first_rewards","respecs"]:
			check(_same(entry.get(key),old_entry[key]),name+": "+String(witch)+" "+key+" carried over")
	for witch in Snap.WITCHES:
		check(now.characters.has(witch),name+": "+String(witch)+" has an entry (the worn set needs a place)")
	# the worn set is copied to every witch (T5-U1)
	for witch in Snap.WITCHES:
		check(_same(now.witches[witch].loadout,old_state.equipped),name+": "+String(witch)+" starts with the old worn set")
	# V-4: the first-run kit of each witch is the schema-3 kit (no name or description in the comparison), the kept slots are the blocked slots
	for witch in Snap.WITCHES:
		var old_witch: Dictionary=then.witches[witch]
		var new_witch: Dictionary=now.witches[witch]
		check(int(new_witch.level)==int(old_witch.level),name+": "+String(witch)+" level")
		check(_same(_bare_list(new_witch.starting_gear),_bare_list(old_witch.starting_gear)),name+": "+String(witch)+" starting kit is the schema-3 kit")
		check(_same(new_witch.blocked_gear,old_witch.blocked_gear),name+": "+String(witch)+" blocked pieces")
		var blocked_slots: Array=[]
		for piece in old_witch.blocked_gear:blocked_slots.append(piece.slot)
		check(JSON.stringify(new_witch.kept_slots)==JSON.stringify(blocked_slots),name+": "+String(witch)+" kept slots are the blocked slots")
	check(now.origin_hint.from_schema==(3 if name.begins_with("v3_") else (2 if name.begins_with("v2_") else 1)),name+": the carry-over record names the source schema")

## The main file of v3_with_journals: the schema-3 code refused it for a changed stat; schema 4 accepts it and sets that item aside.
func _journals_main_only(now: Dictionary,then: Dictionary) -> void:
	var name := "v3_journals_main_only"
	check(now.configure and now.available and now.imported_from_v3,name+": accepted by schema 4 (T5-D1: one item set aside instead of a refusal)")
	check(now.state.quarantine.size()==1 and now.state.quarantine[0].kind=="item" and int(now.read_report.get("quarantined_items",0))==1,name+": exactly one item set aside")
	check(now.state.quarantine.size()==1 and String(now.state.quarantine[0].reason).length()>0 and String(now.state.quarantine[0].reason).length()<=120,name+": the reason is a short sentence")
	check(now.state.items.size()>=1,name+": the other items are in the state")
	check(_error_code_for(String(then.error))=="file_rejected",name+": the recorded refusal sentence stands for file_rejected")
	# the set-aside item is still the schema-3 record, byte for byte in value
	if now.state.quarantine.size()==1:
		var raw: Dictionary=now.state.quarantine[0].raw
		check(raw.has("storage_id") and raw.has("item") and raw.item.has("stats"),name+": the original record is kept as it was")

## Schema-3 structure broken -> refused as legacy, nothing written, the refusal is a code (C1).
func _broken_v3(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	var source: Variant=JSON.parse_string(FileAccess.get_file_as_string(FIXTURES+"/v3_full.json"))
	source.erase("receipts")
	var main := folder+"/chapter-one-profile-v3.json"
	var handle := FileAccess.open(main,FileAccess.WRITE)
	handle.store_string(JSON.stringify(source,"  "));handle.close()
	var before := FileAccess.get_sha256(main)
	var profile=Profile.new()
	var accepted: bool=profile.configure(folder+"/chapter-one-profile-v4.json",true,"","","",main)
	check(not accepted and profile.reject_kind=="legacy" and profile.error_code=="old_rejected","a broken schema-3 file is refused as legacy with the code old_rejected")
	check(FileAccess.get_sha256(main)==before and not FileAccess.file_exists(folder+"/chapter-one-profile-v4.json"),"the refused schema-3 file is untouched and no v4 file appears")
	check(not _has_hangul(profile.error),"the dev sentence in `error` has no Korean text")

func _has_hangul(text: String) -> bool:
	for i in text.length():
		var code := text.unicode_at(i)
		if (code>=0xAC00 and code<=0xD7A3) or (code>=0x3131 and code<=0x318E):return true
	return false

## True when both are equal after a text round trip (numbers read from a file are floats, numbers in memory are ints).
func _same(a: Variant,b: Variant) -> bool:
	return JSON.stringify(_stable(a))==JSON.stringify(_stable(b))

## Numbers read back as floats compare equal after a text round trip.
func _stable(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))

func _bare_list(pieces: Array) -> Array:
	var result: Array=[]
	for piece in pieces:
		var copy: Dictionary=_stable(piece)
		copy.erase("name");copy.erase("description")
		result.append(copy)
	return result

func _finish() -> void:
	if "--negative" in OS.get_cmdline_user_args():check(false,"Intentional checker failure")
	print("CHAPTER1_PROFILE_LEGACY_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
