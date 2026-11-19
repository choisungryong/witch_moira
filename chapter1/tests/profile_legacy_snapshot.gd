extends RefCounted
## Shared by make_profile_legacy_fixtures.gd (once) and test_profile_legacy_fixtures.gd (every run).
## Reads the frozen schema-3/2/1 files with the CURRENT (schema 5) chapter_profile.gd and describes what comes out.
## Only isolated res://_local/ paths are written; the fixture folder itself is only read.
const Profile=preload("res://chapter1/core/chapter_profile.gd")
const WITCHES := ["chapter1.character.frost","chapter1.character.ember","chapter1.character.arc"]
const MAIN := "chapter-one-profile-v3.json"
const POINTER := "chapter-one-profile-active.json"
## name -> {files: [fixture-relative path -> target file name], mode}
## mode "v3" reads MAIN, "v3pointer" also passes the pointer file, "v2" / "v1" read a legacy file next to a missing MAIN.
const SCENARIOS := {
	"v3_full":{"mode":"v3","files":{"v3_full.json":MAIN}},
	"v3_rare_oldword":{"mode":"v3","files":{"v3_rare_oldword.json":MAIN}},
	"v3_rare_threeword":{"mode":"v3","files":{"v3_rare_threeword.json":MAIN}},
	"v3_journals_main_only":{"mode":"v3","journals":true,"files":{}},
	"v3_journals_with_pointer":{"mode":"v3pointer","journals":true,"files":{}},
	"v2_sample":{"mode":"v2","files":{"v2_sample.json":"chapter-one-profile-v2.json"}},
	"v1_sample":{"mode":"v1","files":{"v1_sample.json":"chapter-one-profile-v1.json"}},
}
const JOURNAL_DIR := "v3_with_journals"

static func copy_bytes(from: String,to: String) -> bool:
	DirAccess.make_dir_recursive_absolute(to.get_base_dir())
	var bytes := FileAccess.get_file_as_bytes(from)
	var handle := FileAccess.open(to,FileAccess.WRITE)
	if handle==null:return false
	handle.store_buffer(bytes);handle.close()
	return FileAccess.get_file_as_bytes(to)==bytes

static func wipe_files(folder: String) -> void:
	var dir := DirAccess.open(folder)
	if dir==null:return
	dir.list_dir_begin()
	var entry := dir.get_next()
	var doomed: Array[String]=[]
	while not entry.is_empty():
		if not dir.current_is_dir():doomed.append(entry)
		entry=dir.get_next()
	dir.list_dir_end()
	for file_name in doomed:dir.remove(file_name)

static func journal_names(fixture_dir: String) -> Array[String]:
	var result: Array[String]=[]
	var dir := DirAccess.open(fixture_dir+"/"+JOURNAL_DIR)
	if dir==null:return result
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if not dir.current_is_dir():result.append(entry)
		entry=dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result

## Stage the scenario's files into `work` (wiped first), read them, and return a plain-data description.
## `hashes_out` receives {file name: sha256} of the staged files after the read (they must not change).
static func run_scenario(name: String,fixture_dir: String,work: String) -> Dictionary:
	var spec: Dictionary=SCENARIOS[name]
	wipe_files(work)
	var staged: Array[String]=[]
	for source in spec.files:
		copy_bytes(fixture_dir+"/"+source,work+"/"+String(spec.files[source]));staged.append(String(spec.files[source]))
	if spec.get("journals",false):
		for file_name in journal_names(fixture_dir):
			var wanted: bool=spec.mode=="v3pointer" or file_name==MAIN or ".revision-" in file_name
			if wanted:
				copy_bytes(fixture_dir+"/"+JOURNAL_DIR+"/"+file_name,work+"/"+file_name);staged.append(file_name)
	var before := {}
	for file_name in staged:before[file_name]=FileAccess.get_sha256(work+"/"+file_name)
	var profile=Profile.new()
	var legacy_main := work+"/"+MAIN
	var main := work+"/chapter-one-profile-v5.json"
	var ok := false
	match String(spec.mode):
		"v3":ok=profile.configure(main,true,"","","",legacy_main)
		"v3pointer":ok=profile.configure(main,true,"","","",legacy_main,work+"/"+POINTER)
		"v2":ok=profile.configure(main,true,work+"/chapter-one-profile-v2.json")
		"v1":ok=profile.configure(main,true,"",work+"/chapter-one-profile-v1.json")
	var untouched := true
	for file_name in before:
		if not FileAccess.file_exists(work+"/"+file_name) or FileAccess.get_sha256(work+"/"+file_name)!=before[file_name]:untouched=false
	var written_extra := false
	var dir := DirAccess.open(work)
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if not dir.current_is_dir() and not before.has(entry):written_extra=true
		entry=dir.get_next()
	dir.list_dir_end()
	var description := describe(profile,ok)
	description["read_left_files_untouched"]=untouched
	description["read_wrote_new_files"]=written_extra
	return description

## What a schema-5 read of a frozen file looks like: the memory state, the witches' kits and the carry-over record.
static func describe(profile: RefCounted,ok: bool) -> Dictionary:
	var result := {"configure":ok,"available":profile.available,"reject_kind":profile.reject_kind,"reject_reason":profile.reject_reason,"error_code":profile.error_code,
		"imported_from_v1":profile.imported_from_v1,"imported_from_v2":profile.imported_from_v2,"imported_from_v3":profile.imported_from_v3,"file":profile.path.get_file(),
		"state":profile.state.duplicate(true),"characters":profile.characters.duplicate(true),"notices":profile.notices.duplicate(true),"read_report":profile.read_report.duplicate(true),
		"origin_hint":profile._origin_hint.duplicate(true)}
	var names := {}
	for record in profile.state.get("items",[]):names[str(int(record.storage_id))]=String(record.item.name)
	result["item_names"]=names
	var witches := {}
	for witch in WITCHES:
		var kit: Array=[]
		for piece in profile.starting_gear(witch):kit.append(piece)
		var blocked: Array=[]
		for piece in profile.blocked_gear(witch):blocked.append(piece)
		witches[witch]={"level":profile.character_level(witch),"loadout":profile.loadout(witch),"starting_gear":kit,"kept_slots":profile.starting_kit(witch).kept_slots,"blocked_gear":blocked}
	result["witches"]=witches
	var resume: Dictionary=profile.resume_info()
	result["resume"]={} if resume.is_empty() else {"file":resume.file,"revision":int(resume.revision),"kind":resume.kind}
	return result
