extends RefCounted
## Shared by make_profile_v4_fixtures.gd (once) and test_profile_v4_fixtures.gd (every run).
## Reads the frozen schema-4 files with the chapter_profile.gd of the day and describes what comes out
## (run_scenario: the schema-4 way; run_scenario_as_source: as the source a schema-5 profile carries over).
## Only isolated res://_local/ paths are written; the fixture folders themselves are only read.
const Profile=preload("res://chapter1/core/chapter_profile.gd")
const WITCHES := ["chapter1.character.frost","chapter1.character.ember","chapter1.character.arc"]
const MAIN := "chapter-one-profile-v4.json"
const POINTER := "chapter-one-profile-v4-active.json"
const REVISIONS := "revisions"
const JOURNAL_DIR := "v4_with_journals"
const COMPAT_ROOT := "res://chapter1/tests/fixtures"
## name -> {mode, files: {source relative to `root` (default: the fixture folder) -> file name in the staged folder}, journals: "" | "main" | "all"}
## mode "main" reads MAIN, "pointer" also passes the pointer file.
## journals "main" stages MAIN and revisions/*, "all" stages every file of v4_with_journals/ (the pointer and the r-file too).
const SCENARIOS := {
	"v4_full":{"mode":"main","files":{"v4_full.json":MAIN}},
	"v4_compat":{"mode":"main","root":COMPAT_ROOT,"files":{"profile_v4_compat.json":MAIN}},
	"v4_journals_main_only":{"mode":"main","journals":"main","files":{}},
	"v4_journals_with_pointer":{"mode":"pointer","journals":"all","files":{}},
}

static func copy_bytes(from: String,to: String) -> bool:
	DirAccess.make_dir_recursive_absolute(to.get_base_dir())
	var bytes := FileAccess.get_file_as_bytes(from)
	var handle := FileAccess.open(to,FileAccess.WRITE)
	if handle==null:return false
	handle.store_buffer(bytes);handle.close()
	return FileAccess.get_file_as_bytes(to)==bytes

## Every file below `root` as a path relative to `root` ("revisions/x.json"), sorted.
static func list_files(root: String,rel: String="") -> Array[String]:
	var result: Array[String]=[]
	var dir := DirAccess.open(root if rel.is_empty() else root+"/"+rel)
	if dir==null:return result
	var folders: Array[String]=[]
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var shown := entry if rel.is_empty() else rel+"/"+entry
		if dir.current_is_dir():folders.append(shown)
		else:result.append(shown)
		entry=dir.get_next()
	dir.list_dir_end()
	for folder in folders:result.append_array(list_files(root,folder))
	result.sort()
	return result

static func wipe_tree(folder: String) -> void:
	for rel in list_files(folder):DirAccess.remove_absolute(folder+"/"+rel)

## Stage the scenario's files into `work` (wiped first), read them, and return a plain-data description.
## This reads the frozen schema-4 file as the MAIN file, which is what the schema-4 code did (make_profile_v4_fixtures.gd
## uses it). The schema-5 code would call that file incompatible; test_profile_v4_fixtures.gd uses run_scenario_as_source.
static func run_scenario(name: String,fixture_dir: String,work: String) -> Dictionary:
	return _run(name,fixture_dir,work,false)

## The same staging, but the frozen files are handed to a schema-5 profile as the schema-4 SOURCE to carry over (the way the
## product finds them): the v5 paths are new and empty, `legacy_v4` is the staged file, `legacy_v4_pointer` the staged pointer.
static func run_scenario_as_source(name: String,fixture_dir: String,work: String) -> Dictionary:
	return _run(name,fixture_dir,work,true)

static func _run(name: String,fixture_dir: String,work: String,as_source: bool) -> Dictionary:
	var spec: Dictionary=SCENARIOS[name]
	wipe_tree(work)
	var staged: Array[String]=[]
	var root := String(spec.get("root",fixture_dir))
	for source in spec.files:
		copy_bytes(root+"/"+source,work+"/"+String(spec.files[source]));staged.append(String(spec.files[source]))
	var journals := String(spec.get("journals",""))
	if not journals.is_empty():
		for rel in list_files(fixture_dir+"/"+JOURNAL_DIR):
			if journals=="all" or rel==MAIN or rel.begins_with(REVISIONS+"/"):
				copy_bytes(fixture_dir+"/"+JOURNAL_DIR+"/"+rel,work+"/"+rel);staged.append(rel)
	var before := {}
	for rel in staged:before[rel]=FileAccess.get_sha256(work+"/"+rel)
	var profile=Profile.new()
	var pointed := String(spec.mode)=="pointer"
	var ok: bool
	if as_source:ok=profile.configure(work+"/chapter-one-profile-v5.json",true,"","",work+"/chapter-one-profile-v5-active.json","","",work+"/"+MAIN,work+"/"+POINTER if pointed else "")
	else:ok=profile.configure(work+"/"+MAIN,true,"","",work+"/"+POINTER if pointed else "")
	var untouched := true
	for rel in before:
		if not FileAccess.file_exists(work+"/"+rel) or FileAccess.get_sha256(work+"/"+rel)!=before[rel]:untouched=false
	var written_extra := false
	for rel in list_files(work):
		if not before.has(rel):written_extra=true
	var description := describe(profile,ok)
	description["read_left_files_untouched"]=untouched
	description["read_wrote_new_files"]=written_extra
	return description

## What a read of a frozen file looks like: the memory state, the witches' kits, outfits and the resume candidate.
static func describe(profile: RefCounted,ok: bool) -> Dictionary:
	var result := {"configure":ok,"available":profile.available,"reject_kind":profile.reject_kind,"reject_reason":profile.reject_reason,"error_code":profile.error_code,
		"imported_from_v1":profile.imported_from_v1,"imported_from_v2":profile.imported_from_v2,"imported_from_v3":profile.imported_from_v3,"file":profile.path.get_file(),
		"reject_source":profile.reject_source.get_file(),
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
		witches[witch]={"level":profile.character_level(witch),"loadout":profile.loadout(witch),"starting_gear":kit,"kept_slots":profile.starting_kit(witch).kept_slots,
			"blocked_gear":blocked,"wardrobe":profile.wardrobe_view(witch)}
	result["witches"]=witches
	var resume: Dictionary=profile.resume_info()
	result["resume"]={} if resume.is_empty() else {"file":resume.file,"revision":int(resume.revision),"kind":resume.kind}
	return result
