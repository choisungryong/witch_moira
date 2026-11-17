extends RefCounted
## Product profile, schema 4 (user://chapter-one-profile-v4.json).
## What the file holds: ids, numbers and flags, no sentences. Equipment name and description are not stored; a rare
## item keeps two word ids (`rare_words`) or, when an old name could not be matched, its old text (`legacy_name`).
## Each witch has her own worn kit (`loadout`), outfits (`wardrobe`), story record (`story`), cleared depths
## (`depth_cleared`) and the reserved `tree_reset` slot. An item that no longer matches the data is moved to
## `quarantine` with its original text instead of refusing the whole file.
## Schema 3, 2 and 1 files are only ever read (never opened for writing, renamed or deleted); the first save writes
## the v4 file. Journal copies of v4 saves go to the `revisions/` folder beside the file.
## In memory `state` holds the file's top level without `characters` and with every equipment item dressed again
## (name and description rebuilt from the data) so the core and the screens see the shape they always saw;
## `characters` holds the per-witch table. Level and points are computed from xp, never stored.
const Loot=preload("res://chapter1/core/loot.gd")
const Catalog=preload("res://chapter1/core/growth_catalog.gd")
const Progression=preload("res://chapter1/core/character_progression.gd")
const SkillTree=preload("res://chapter1/core/skill_tree.gd")
const CAPACITY := 256
const MAX_ITEMS := 325 # One final69-item recovery batch; start blocked above256.
const PATH_V4 := "user://chapter-one-profile-v4.json"
const PATH_V3 := "user://chapter-one-profile-v3.json"
const PATH_V2 := "user://chapter-one-profile-v2.json"
const PATH_V1 := "user://chapter-one-profile-v1.json"
const POINTER_PATH := "user://chapter-one-profile-v4-active.json"
const POINTER_PATH_V3 := "user://chapter-one-profile-active.json"
const REVISIONS_DIR := "revisions"
const OUTFITS_PATH := "res://chapter1/data/outfits.json"
const FRESH_NAME_PATTERN := "^chapter-one-profile-v4-r[0-9-]+\\.json\\z"
const FRESH_NAME_PATTERN_V3 := "^chapter-one-profile-v3-r[0-9-]+\\.json\\z"
## At most this many journal copies are read when looking for one to continue from (newest first).
const MAX_JOURNAL_SCAN := 64
const MAX_TEXT := 2000000
const MAX_RAW := 8000
const EQUIP_SLOTS := ["weapon","head","body","hands","feet","charm","ring","ring2"]
const TOP_KEYS := ["schema_version","revision","next_id","items","completed_runs","best_ticks","essence","receipts","characters","codex","gambles","shared_story","quarantine","origin"]
const TOP_KEYS_V3 := ["schema_version","revision","next_id","items","equipped","completed_runs","best_ticks","essence","receipts","characters"]
const TOP_KEYS_V2 := ["schema_version","revision","next_id","items","equipped","completed_runs","best_ticks","essence","receipts"]
const CHAR_KEYS := ["xp","tree_revision","ranks","first_rewards","respecs","loadout","depth_cleared","wardrobe","story","tree_reset"]
const CHAR_KEYS_V3 := ["xp","tree_revision","ranks","first_rewards","respecs"]
## Schema 1/3 equipment and the v1 item: eight keys with the text in the file.
const ITEM_KEYS := ["base_id","name","slot","stats","quality","item_level","affixes","description"]
const ITEM_KEYS_V2 := ["grammar","required_level","legendary_id"]
## Schema 4 grammar-2 item: required keys, then the optional ones.
const ITEM_KEYS_V4 := ["grammar","base_id","slot","stats","quality","item_level","affixes","required_level"]
const ITEM_KEYS_V4_OPTIONAL := ["legendary_id","rare_words","legacy_name","veiled"]
const ESSENCE := {"common":1,"magic":3,"rare":8,"legendary":15,"unique":25}
const UNIQUE_ID_PREFIX := "chapter1.full.unique."
const ID_PATTERN := "^[a-z0-9][a-z0-9_.:-]{0,79}\\z"
const WORD_ID_PATTERN := "^[a-z][a-z0-9]{0,7}\\z"
const RESET_ID_PATTERN := "^[a-z][a-z0-9_]{0,15}\\z"
const DEPTH_KEY_PATTERN := "^d[0-9]{1,2}\\z"
static var _loot: RefCounted
static var _loot_path := ""
static var _progression: Dictionary={}
static var _trees: Dictionary={}
static var _outfits: Dictionary={}
static var _test_ids: Dictionary={}
var state: Dictionary={}
## {character_id: {xp, tree_revision, ranks, first_rewards, respecs, loadout, depth_cleared, wardrobe, story, tree_reset}}.
var characters: Dictionary={}
## {character_id: true} when a tree revision change or a broken investment returned the ranks on read. Cleared by acknowledge_notice.
var notices: Dictionary={}
## What the last read fixed or kept aside, {key: count}. Empty when the file was read as it stood.
var read_report: Dictionary={}
## Dev sentence of the last refusal (English). The screen words a refusal from `error_code` and `error_args` (keys
## profile.error.<code>); assigning `error` directly clears the code, so only _err() sets both.
var error := "":
	set(value):
		error=value;error_code="";error_args={}
var error_code := ""
var error_args: Dictionary={}
var path := ""
var _loaded_text := ""
var available := false
## Why the last configure() refused a file: "" when it did not. Kinds: "damaged" (JSON or size),
## "incompatible" (well-formed but failed validation), "legacy" (a schema-3/2/1 file was refused).
var reject_kind := ""
var reject_reason := ""
## The file that was actually refused (the v4 path, or the old-format file for "legacy"). Read-only for callers.
var reject_source := ""
## Where the pointer file lives ("" = none). The product uses POINTER_PATH; QA passes an isolated path.
var pointer_path := ""
## The newest readable journal copy (or the re-migrated v3 source), computed once when a file is refused (see _reject).
var _resume := {}
## Test hook: when set (digits and dashes only), replaces the time stamp in a new save's file name.
var stamp_override := ""
## True until the first save after reading a schema-1 / schema-2 / schema-3 file.
var imported_from_v1 := false
var imported_from_v2 := false
var imported_from_v3 := false
## Test hook: when >= 0 replaces respec.essence_per_point from the data.
var respec_cost_override := -1
## Set by record_run to "kit_not_saved" when the run's worn set could not be validated and only the rewards were saved
## (the witch's kit stays as it was); "" otherwise. A code, not a sentence: the screen words it.
var carry_note := ""
var _words := {}
var _origin_hint := {"from_schema":0,"from_file":"","from_revision":0}
var _v3_path := ""
var _v3_pointer := ""

static func progression_doc() -> Dictionary:
	if _progression.is_empty():
		var doc := Progression.load_document()
		if not doc.has("error") and Progression.validate_document(doc).is_empty():_progression=doc
		else:push_error("Character progression failed to load: "+str(doc.get("error",Progression.validate_document(doc))))
	return _progression

static func trees() -> Dictionary:
	if _trees.is_empty():
		var loaded := SkillTree.load_trees(SkillTree.DEFAULT_PATH,progression_doc())
		if not loaded.has("error"):_trees=loaded
		else:push_error("Skill trees failed to load: "+str(loaded.error))
	return _trees

static func loot() -> RefCounted:
	if _loot==null:
		var tables=Loot.new()
		var ok: bool=tables.load_file(_loot_path) if not _loot_path.is_empty() else tables.load_file()
		if ok:_loot=tables
		else:push_error("Loot tables failed to load: "+str(tables.errors))
	return _loot

## Test hook (T5 section 7): read equipment data from another file, or from the product file again when `loot_path` is "".
static func use_data_for_test(loot_path: String="") -> void:
	_loot=null;_loot_path=loot_path

## Test hook: ids the story and collectible functions accept, {"story": [...], "collectibles": [...], "shared": [...]}.
## The data files (story_beats.json, collectibles.json) do not exist yet, so without this hook no id is known.
static func use_ids_for_test(ids: Dictionary) -> void:
	_test_ids=ids.duplicate(true)

static func _known_ids(kind: String) -> Array:
	return _test_ids.get(kind,[])

## {outfit id: {character_id, default_owned}} from outfits.json; {} when the file is missing or malformed.
static func outfits() -> Dictionary:
	if _outfits.is_empty():
		var parser := JSON.new()
		if not FileAccess.file_exists(OUTFITS_PATH) or parser.parse(FileAccess.get_file_as_string(OUTFITS_PATH))!=OK or not parser.data is Dictionary:
			push_error("Outfit data failed to load");return {}
		var doc: Dictionary=parser.data;var table := {};var rule := RegEx.create_from_string(ID_PATTERN)
		if not Catalog.integer(doc.get("schema_version"),1,1) or not doc.get("outfits") is Array:push_error("Outfit data shape");return {}
		for row in doc.outfits:
			if not row is Dictionary or not Catalog.keys_match(row,["id","character_id","default_owned","art"]) or not row.id is String or rule.search(row.id)==null or table.has(row.id):push_error("Outfit row");return {}
			if not row.character_id is String or Progression.character_entry(progression_doc(),row.character_id).is_empty() or not row.default_owned is bool or not row.art is Dictionary:push_error("Outfit row fields");return {}
			table[row.id]={"character_id":row.character_id,"default_owned":row.default_owned}
		_outfits=table
	return _outfits

static func fresh() -> Dictionary:
	return {"schema_version":4,"revision":0,"next_id":1,"items":[],"completed_runs":0,"best_ticks":0,"essence":0,"receipts":[],
		"codex":{"uniques":[],"legendaries":[],"set_pieces":[]},"gambles":0,"shared_story":{"seen":[],"true_ending":false},
		"quarantine":[],"origin":{"from_schema":0,"from_file":"","from_revision":0,"at_unix":0}}

## The record of a witch with no saved entry yet.
static func default_entry(character_id: String) -> Dictionary:
	var known := Progression.character_entry(progression_doc(),character_id)
	var revision := 0
	if not known.is_empty() and known.get("tree_id")!=null and trees().has(known.tree_id):revision=int(trees()[known.tree_id].revision)
	return {"xp":0,"tree_revision":revision,"ranks":{},"first_rewards":[],"respecs":0,"loadout":{},"depth_cleared":{},
		"wardrobe":{"owned":[],"worn":""},"story":{"found":[],"seen":[],"duel_cleared":false,"final_cleared":false},"tree_reset":{"granted":[],"used":[]}}

# ---------------------------------------------------------------- opening a profile

## Reads `destination` (schema 4). When it does not exist, reads the schema-3 file (through its pointer when there
## is one), then the schema-2 file, then the schema-1 file, into memory only; nothing is written until the next save.
## In QA mode every path is an optional argument and must be an isolated QA path.
func configure(destination: String=PATH_V4,qa: bool=false,legacy_v2: String="",legacy_v1: String="",pointer: String="",legacy_v3: String="",legacy_v3_pointer: String="") -> bool:
	reject_source="";available=false;error="";reject_kind="";reject_reason="";_resume={};state=fresh();characters={};notices={};path=destination;_loaded_text=""
	imported_from_v1=false;imported_from_v2=false;imported_from_v3=false;pointer_path="";read_report={};_words={};_origin_hint={"from_schema":0,"from_file":"","from_revision":0};_v3_path="";_v3_pointer=""
	if qa:
		var base := "res://_local/"
		for candidate_path in [path,legacy_v2,legacy_v1,pointer,legacy_v3,legacy_v3_pointer]:
			if String(candidate_path).is_empty():continue
			if not String(candidate_path).begins_with(base) or not String(candidate_path).ends_with(".json") or ".." in String(candidate_path):_err("isolated_path_invalid","Invalid isolated QA profile path");return false
		pointer_path=pointer
	else:
		if destination!=PATH_V4 or not ProjectSettings.get_setting("application/config/use_custom_user_dir",false) or not String(ProjectSettings.get_setting("application/config/custom_user_dir_name","")).begins_with("WitchMoira"):
			_err("preview_only","Preview build without a dedicated save path");return false
		legacy_v3=PATH_V3;legacy_v3_pointer=POINTER_PATH_V3;legacy_v2=PATH_V2;legacy_v1=PATH_V1;pointer_path=POINTER_PATH
	_v3_path=legacy_v3;_v3_pointer=legacy_v3_pointer
	path=_pointed(destination)
	if FileAccess.file_exists(path):
		_loaded_text=FileAccess.get_file_as_string(path)
		if _loaded_text.length()>MAX_TEXT:_err("profile_too_large","Profile exceeds bound");return _reject("damaged","size",path)
		var parser := JSON.new()
		if parser.parse(_loaded_text)!=OK:_err("file_rejected","Save file failed validation; original kept");return _reject("damaged","json",path)
		var report := {};var seen := {};var why := []
		var read := read_document(parser.data,false,report,seen,why)
		if read.is_empty():_err("file_rejected","Save file failed validation; original kept");return _reject("incompatible",String(why[0]) if not why.is_empty() else "schema 4 document",path)
		_adopt(read);notices=seen;read_report=report;_log_fixes(path.get_file())
	else:
		var source := _v3_source()
		if not source.is_empty():
			var text := FileAccess.get_file_as_string(source)
			if not import_v3_text(text,source.get_file()):return _reject("legacy",reject_reason,source,true)
		elif not legacy_v2.is_empty() and FileAccess.file_exists(legacy_v2):
			if not import_v2_text(FileAccess.get_file_as_string(legacy_v2)):return _reject("legacy",reject_reason,legacy_v2)
		elif not legacy_v1.is_empty() and FileAccess.file_exists(legacy_v1):
			if not import_v1_text(FileAccess.get_file_as_string(legacy_v1)):return _reject("legacy",reject_reason,legacy_v1)
	available=true;return true

## The file the pointer names, when the pointer is well formed and names an existing file directly beside
## `destination` with the fresh-save naming rule. Anything else (a path, "..", another pattern, a missing file,
## a name of another schema) is ignored and `destination` is used. The pointer is only read here.
func _pointed(destination: String) -> String:
	var named := _pointer_target(pointer_path,destination,FRESH_NAME_PATTERN)
	return named if not named.is_empty() else destination

static func _pointer_target(pointer_file: String,destination: String,pattern: String) -> String:
	if pointer_file.is_empty() or not FileAccess.file_exists(pointer_file):return ""
	var text := FileAccess.get_file_as_string(pointer_file)
	if text.length()>4096:return ""
	var parser := JSON.new()
	if parser.parse(text)!=OK or not parser.data is Dictionary or not parser.data.get("file") is String:return ""
	var file: String=parser.data.file
	if RegEx.create_from_string(pattern).search(file)==null:return ""
	var target := _sibling(destination,file)
	return target if FileAccess.file_exists(target) else ""

## The schema-3 file to carry over: the one its pointer names, else the plain v3 file. "" when there is none.
func _v3_source() -> String:
	if _v3_path.is_empty():return ""
	var named := _pointer_target(_v3_pointer,_v3_path,FRESH_NAME_PATTERN_V3)
	if not named.is_empty():return named
	return _v3_path if FileAccess.file_exists(_v3_path) else ""

static func _sibling(file_path: String,file_name: String) -> String:
	var folder := file_path.get_base_dir()
	return folder+file_name if folder.ends_with("/") else folder+"/"+file_name

func _log_fixes(file_name: String) -> void:
	if read_report.is_empty():return
	var line := {"file":file_name}
	line.merge(read_report)
	print("CHAPTER1_PROFILE_READ_FIXES ",JSON.stringify(line))

func _adopt(read: Dictionary) -> void:
	state=read.state.duplicate(true);characters=read.characters.duplicate(true);_words=read.words.duplicate(true)

# ---------------------------------------------------------------- journal copies and the refusal flow

func journal_dir() -> String:
	var folder := path.get_base_dir()
	return (folder if not folder.ends_with("/") else folder.left(folder.length()-1))+"/"+REVISIONS_DIR

func journal_path(file_name: String) -> String:
	return journal_dir()+"/"+file_name

## Journal copies (`revisions/<file>.revision-*.json`) of the current file, newest revision first: [{file, number}].
func journal_files() -> Array:
	return _journal_rows(journal_dir(),path.get_file().get_basename()+".revision-")

static func _journal_rows(folder: String,prefix: String) -> Array:
	var rows := []
	var dir := DirAccess.open(folder)
	if dir==null:return rows
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if not dir.current_is_dir() and entry.begins_with(prefix) and entry.ends_with(".json"):
			rows.append({"file":entry,"number":int(entry.trim_prefix(prefix).get_slice("-",0))})
		entry=dir.get_next()
	dir.list_dir_end()
	rows.sort_custom(func(a,b):return int(a.number)>int(b.number) or (int(a.number)==int(b.number) and String(a.file)>String(b.file)))
	return rows

## The newest journal copy the current rules can read: {file, revision, unix, kind, read} or {}. Reads only.
func latest_readable_revision() -> Dictionary:
	var scanned := 0
	for row in journal_files():
		scanned+=1
		if scanned>MAX_JOURNAL_SCAN:break
		var full := journal_path(String(row.file))
		var text := FileAccess.get_file_as_string(full)
		if text.length()>MAX_TEXT:continue
		var parser := JSON.new()
		if parser.parse(text)!=OK:continue
		var read := read_document(parser.data,false)
		if not read.is_empty():return {"kind":"journal","file":row.file,"revision":int(read.state.revision),"unix":int(FileAccess.get_modified_time(full)),"read":read}
	return {}

## The newest schema-3 journal copy beside the refused v3 file that the v4 rules can carry over. Reads only.
func _v3_journal_resume(source: String) -> Dictionary:
	var scanned := 0
	for row in _journal_rows(source.get_base_dir(),_v3_base(source)+".revision-"):
		scanned+=1
		if scanned>MAX_JOURNAL_SCAN:break
		var full := _sibling(source,String(row.file))
		var carried := _carry_v3_text(FileAccess.get_file_as_string(full))
		if not carried.is_empty():return {"kind":"v3_journal","file":row.file,"revision":int(carried.read.state.revision),"unix":int(FileAccess.get_modified_time(full)),"read":carried.read,"origin":{"from_schema":3,"from_file":String(row.file),"from_revision":int(carried.read.state.revision)}}
	return {}

## After a refusal of the v4 file: the v3 source carried over again, when it can be. Reads only.
func _v3_source_resume() -> Dictionary:
	var source := _v3_source()
	if source.is_empty():return {}
	var carried := _carry_v3_text(FileAccess.get_file_as_string(source))
	if carried.is_empty():return {}
	return {"kind":"v3_source","file":source.get_file(),"revision":int(carried.read.state.revision),"unix":int(FileAccess.get_modified_time(source)),"read":carried.read,"origin":{"from_schema":3,"from_file":source.get_file(),"from_revision":int(carried.read.state.revision)}}

static func _v3_base(file_path: String) -> String:
	var file := file_path.get_file().get_basename()
	return file if not file.contains(".revision-") else file.get_slice(".revision-",0)

## {read, report, notices} for schema-3 text read with the v4 rules, or {} when it is not a readable schema-3 document.
func _carry_v3_text(text: String) -> Dictionary:
	if text.length()>MAX_TEXT:return {}
	var parser := JSON.new()
	if parser.parse(text)!=OK:return {}
	var upgraded := upgrade_v3(parser.data)
	if upgraded.is_empty():return {}
	var report := {};var seen := {}
	var read := read_document(upgraded,false,report,seen)
	if read.is_empty():return {}
	return {"read":read,"report":report,"notices":seen}

## {file, revision, unix, kind} of the copy a new save would continue from, or {}. Cached; no disk access.
## kind: "journal" (a v4 copy), "v3_source" (the schema-3 file carried over again), "v3_journal" (a schema-3 copy).
func resume_info() -> Dictionary:
	if _resume.is_empty():return {}
	return {"kind":_resume.kind,"file":_resume.file,"revision":_resume.revision,"unix":_resume.unix}

func _err(code: String,text: String,args: Dictionary={}) -> void:
	error=text;error_code=code;error_args=args

## After a refusal: begin a new save without touching the refused file or its journal copies.
## - v4 file refused: a new file `chapter-one-profile-v4-r<YYYYMMDD-HHMMSS>[-n].json` beside it (never an existing
##   name), from the newest readable journal copy (or the carried-over v3 source) when use_revision, else empty; the pointer names it.
## - only an older schema refused (no v4 file exists): an empty v4 at the normal path (or from a readable v3 copy); no pointer.
## Returns false and leaves the refused state as it was when anything fails.
func start_fresh_after_reject(use_revision: bool=true) -> bool:
	if available or reject_kind.is_empty():_err("fresh_unavailable","A new save cannot be started in this state");return false
	var refused_path := path;var refused_kind := reject_kind;var refused_reason := reject_reason;var refused_error := error;var refused_code := error_code;var refused_args := error_args
	var target := path;var from_revision := "";var next_state := fresh();var next_characters := {};var next_words := {};var next_hint := {"from_schema":0,"from_file":"","from_revision":0}
	if refused_kind=="legacy":
		if FileAccess.file_exists(target):_err("fresh_name_taken","New save file name already exists");return false
	else:
		if pointer_path.is_empty():_err("pointer_path_missing","Pointer file path missing");return false
		var stamp_time := Time.get_datetime_dict_from_system()
		var stamp := "%04d%02d%02d-%02d%02d%02d"%[stamp_time.year,stamp_time.month,stamp_time.day,stamp_time.hour,stamp_time.minute,stamp_time.second]
		if not stamp_override.is_empty():stamp=stamp_override
		var number := 1
		target=_sibling(refused_path,"chapter-one-profile-v4-r"+stamp+".json")
		while FileAccess.file_exists(target):
			number+=1;target=_sibling(refused_path,"chapter-one-profile-v4-r"+stamp+"-"+str(number)+".json")
	if use_revision and not _resume.is_empty():
		var latest: Dictionary=_resume
		next_state=latest.read.state.duplicate(true);next_characters=latest.read.characters.duplicate(true);next_words=latest.read.words.duplicate(true)
		from_revision=String(latest.file)
		if latest.has("origin"):next_hint=latest.origin
	state=next_state;characters=next_characters;_words=next_words;_origin_hint=next_hint;path=target;_loaded_text="";available=true;error="";read_report={}
	var written := _persist(state.duplicate(true))
	if written and refused_kind!="legacy":written=_write_pointer(target.get_file(),refused_path.get_file(),refused_kind,refused_reason,from_revision)
	if not written:
		var why := error;var why_code := error_code;var why_args := error_args
		available=false;state=fresh();characters={};_words={};path=refused_path;_loaded_text="";error=why if not why.is_empty() else refused_error
		error_code=why_code if not why.is_empty() else refused_code;error_args=why_args if not why.is_empty() else refused_args
		return false
	reject_kind="";reject_reason=""
	return true

func _write_pointer(file: String,replaces: String,kind: String,reason: String,from_revision: String) -> bool:
	var doc := {"schema":1,"file":file,"replaces":replaces,"kind":kind,"reason":reason,"created_unix":int(Time.get_unix_time_from_system()),"from_revision":from_revision}
	var text := JSON.stringify(doc,"  ")
	var temporary := pointer_path+".next-%d.tmp"%Time.get_ticks_usec()
	var handle := FileAccess.open(temporary,FileAccess.WRITE)
	if handle==null:_err("pointer_create_failed","Pointer file creation failed");return false
	handle.store_string(text);handle.flush();var status := handle.get_error();handle.close()
	if status!=OK or FileAccess.get_file_as_string(temporary)!=text:_err("pointer_write_failed","Pointer file write verification failed");return false
	if DirAccess.rename_absolute(temporary,pointer_path)!=OK:_err("pointer_replace_failed","Pointer file replacement failed");return false
	return true

## Records why a file was refused and writes one log line. Writes no file and changes nothing on disk.
## The line holds the file name only (no user path) and no item names.
func _reject(kind: String,reason: String,source: String,is_v3_file: bool=false) -> bool:
	reject_kind=kind;reject_reason=reason;reject_source=source
	if kind=="legacy":
		_resume=_v3_journal_resume(source) if is_v3_file else {}
	else:
		_resume=latest_readable_revision()
		if _resume.is_empty():_resume=_v3_source_resume()
	var text := FileAccess.get_file_as_string(source) if FileAccess.file_exists(source) else ""
	print("CHAPTER1_PROFILE_REJECTED ",JSON.stringify({"file":source.get_file(),"kind":kind,"reason":reason,"bytes":text.to_utf8_buffer().size(),"sha256_16":text.sha256_text().substr(0,16)}))
	return false

# ---------------------------------------------------------------- carrying older files over (memory only)

## A schema-3 file's text into memory. Nothing is written until the next save, and that save goes to the v4 path.
func import_v3_text(text: String,file_name: String="") -> bool:
	if text.length()>MAX_TEXT:_err("old_too_large","Old save file too large; original kept");reject_reason="size";return false
	var parser := JSON.new()
	if parser.parse(text)!=OK:_err("old_rejected","Old save file failed validation; original kept");reject_reason="json";return false
	var why := []
	var upgraded := upgrade_v3(parser.data,why)
	if upgraded.is_empty():_err("old_rejected","Old save file failed validation; original kept");reject_reason=String(why[0]) if not why.is_empty() else "schema 3 document";return false
	if not _take_document(upgraded,3,file_name):return false
	imported_from_v3=true
	return true

## Read a schema-2 profile into memory (same rule as before: xp from completed runs, the equipment kept).
func import_v2_text(text: String) -> bool:
	if text.length()>MAX_TEXT:_err("old_too_large","Old save file too large; original kept");reject_reason="size";return false
	var parser := JSON.new()
	if parser.parse(text)!=OK:_err("old_rejected","Old save file failed validation; original kept");reject_reason="json";return false
	var why := []
	var upgraded := normalize(parser.data,why)
	if upgraded.is_empty():_err("old_rejected","Old save file failed validation; original kept");reject_reason=String(why[0]);return false
	var document := upgrade_v3(_as_v3_document(upgraded),why)
	if document.is_empty() or not _take_document(document,2,""):
		if error.is_empty():_err("old_rejected","Old save file failed validation; original kept");reject_reason="carry over"
		return false
	imported_from_v2=true
	return true

## Read a schema-1 profile into memory.
func import_v1_text(text: String) -> bool:
	if text.length()>MAX_TEXT:_err("old_too_large","Old save file too large; original kept");reject_reason="size";return false
	var parser := JSON.new()
	if parser.parse(text)!=OK:_err("old_rejected","Old save file failed validation; original kept");reject_reason="json";return false
	var upgraded := upgrade_v1(parser.data)
	if upgraded.is_empty():_err("old_rejected","Old save file failed validation; original kept");reject_reason="schema 1 document";return false
	var why := []
	var document := upgrade_v3(_as_v3_document(upgraded),why)
	if document.is_empty() or not _take_document(document,1,""):
		if error.is_empty():_err("old_rejected","Old save file failed validation; original kept");reject_reason="carry over"
		return false
	imported_from_v1=true
	return true

## A schema-4 document made from an older file: read with the v4 rules and adopted in memory.
func _take_document(document: Dictionary,from_schema: int,source_name: String) -> bool:
	var report := {};var seen := {};var why := []
	var read := read_document(document,false,report,seen,why)
	if read.is_empty():_err("old_rejected","Old save file failed validation; original kept");reject_reason=String(why[0]) if not why.is_empty() else "carry over";return false
	_adopt(read);notices=seen;read_report=report
	_origin_hint={"from_schema":from_schema,"from_file":source_name,"from_revision":int(read.state.revision)}
	_loaded_text="";_log_fixes(source_name if not source_name.is_empty() else "schema-%d"%from_schema)
	return true

## A schema-2 memory state as a schema-3 shaped document (the carried-over xp in `characters`).
static func _as_v3_document(old_state: Dictionary) -> Dictionary:
	var doc: Dictionary=old_state.duplicate(true)
	doc.schema_version=3
	doc.characters=migrated_characters(old_state)
	return doc

## Experience carried over from a schema-1/2 profile: min(completed_runs, max_runs) * xp_per_completed_run
## for the witch that owns a tree. First-kill receipts are not migrated.
static func migrated_characters(old_state: Dictionary) -> Dictionary:
	var doc := progression_doc();var table := trees()
	if doc.is_empty() or table.is_empty():return {}
	var xp := mini(int(old_state.get("completed_runs",0)),int(doc.migration.max_runs))*int(doc.migration.xp_per_completed_run)
	if xp<=0:return {}
	for entry in doc.characters:
		if entry.get("tree_id")!=null and table.has(entry.tree_id):
			return {entry.id:{"xp":mini(xp,int(doc.xp_thresholds[doc.xp_thresholds.size()-1])),"tree_revision":int(table[entry.tree_id].revision),"ranks":{},"first_rewards":[],"respecs":0}}
	return {}

## Schema 1 used four slots and v1 items; both are a subset of schema 2.
static func upgrade_v1(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.has("schema_version") or not Catalog.integer(value.schema_version,1,1):return {}
	if not value.get("equipped") is Dictionary:return {}
	for slot in value.equipped:
		if not slot in ["weapon","body","charm","ring"]:return {}
	if value.get("items") is Array:
		for record in value.items:
			if record is Dictionary and record.get("item") is Dictionary and record.item.has("grammar"):return {}
	var candidate: Dictionary=value.duplicate(true)
	candidate.schema_version=2
	return normalize(candidate)

## A schema-3 document as a schema-4 document (file form), or {} when its structure is not a schema-3 document.
## Only structure is checked here; whether each item still matches the data is decided by read_document, which
## puts an item that does not into `quarantine`. Equipment text is dropped (a rare name becomes `rare_words`, or
## `legacy_name` when it is not one word from each list); the single worn set is copied to all three witches.
static func upgrade_v3(value: Variant,reasons_out: Array=[]) -> Dictionary:
	if not value is Dictionary or not Catalog.keys_match(value,TOP_KEYS_V3):return _bad(reasons_out,"schema 3 keys")
	if not Catalog.integer(value.schema_version,3,3):return _bad(reasons_out,"schema version")
	for key in ["revision","next_id","completed_runs","best_ticks","essence"]:
		if not Catalog.integer(value[key],0,1000000000):return _bad(reasons_out,key)
	if value.next_id<1 or not value.items is Array or value.items.size()>MAX_ITEMS or not value.equipped is Dictionary or value.equipped.size()>EQUIP_SLOTS.size() or not value.receipts is Array or value.receipts.size()>64:return _bad(reasons_out,"schema 3 shape")
	if not value.characters is Dictionary or value.characters.size()>3:return _bad(reasons_out,"characters")
	var tables := loot()
	var doc := progression_doc()
	if tables==null or doc.is_empty():return _bad(reasons_out,"data")
	for receipt in value.receipts:
		if not receipt is String or receipt.length()<1 or receipt.length()>120:return _bad(reasons_out,"receipts")
	var items: Array=[];var ids := {};var uniques: Array=[];var legendaries: Array=[]
	for record in value.items:
		if not record is Dictionary or not Catalog.keys_match(record,["storage_id","item"]) or not Catalog.integer(record.storage_id,1,999999999):return _bad(reasons_out,"item record")
		var sid := int(record.storage_id)
		if ids.has(sid) or sid>=int(value.next_id) or not record.item is Dictionary:return _bad(reasons_out,"item record id")
		ids[sid]=true
		var item: Dictionary=_plain(record.item)
		if item.has("grammar"):
			var shown: Variant=item.get("name")
			item.erase("name");item.erase("description")
			if item.get("quality")=="rare" and shown is String:
				var words: Array=tables.rare_word_ids(shown)
				if not words.is_empty():item["rare_words"]=words
				else:item["legacy_name"]=shown
			if item.get("quality")=="unique" and item.get("base_id") is String and String(item.base_id).begins_with(UNIQUE_ID_PREFIX):_push_unique(uniques,String(item.base_id).trim_prefix(UNIQUE_ID_PREFIX))
			if item.get("quality")=="legendary" and item.get("legendary_id") is String:_push_unique(legendaries,String(item.legendary_id))
		items.append({"storage_id":sid,"item":item})
	var table := {}
	for id_ in value.characters:
		if not id_ is String or not value.characters[id_] is Dictionary or not Catalog.keys_match(value.characters[id_],CHAR_KEYS_V3):return _bad(reasons_out,"character entry")
	for entry in doc.characters:
		var id_: String=entry.id
		var carried: Dictionary=_plain(value.characters[id_]) if value.characters.has(id_) else default_entry(id_)
		var full: Dictionary=default_entry(id_)
		for key in CHAR_KEYS_V3:full[key]=carried[key]
		full.loadout=_plain(value.equipped)
		if full.first_rewards is Array and "boss" in full.first_rewards:full.depth_cleared={"d1":1}
		table[id_]=full
	for id_ in value.characters:
		if not table.has(id_):table[id_]=_plain(value.characters[id_])
	return {"schema_version":4,"revision":int(value.revision),"next_id":int(value.next_id),"items":items,"completed_runs":int(value.completed_runs),"best_ticks":int(value.best_ticks),
		"essence":int(value.essence),"receipts":value.receipts.duplicate(),"characters":table,"codex":{"uniques":uniques.slice(0,64),"legendaries":legendaries.slice(0,64),"set_pieces":[]},
		"gambles":0,"shared_story":{"seen":[],"true_ending":false},"quarantine":[],"origin":{"from_schema":0,"from_file":"","from_revision":0,"at_unix":0}}

static func _push_unique(list: Array,value: String) -> void:
	if not value in list:list.append(value)

static func _bad(reasons_out: Array,text: String) -> Dictionary:
	reasons_out.append(text)
	return {}

## Integral floats back to ints, recursively, on a copy (JSON numbers arrive as floats).
static func _plain(value: Variant) -> Variant:
	if value is float and is_finite(value) and value==floor(value) and absf(value)<9007199254740992.0:return int(value)
	if value is Array:
		var list: Array=[]
		for entry in value:list.append(_plain(entry))
		return list
	if value is Dictionary:
		var table := {}
		for key in value:table[key]=_plain(value[key])
		return table
	return value

## Schema-2 document rule, kept for the old files: `reasons_out` receives a short reason when it is rejected.
static func normalize(value: Variant,reasons_out: Array=[]) -> Dictionary:
	var rejected := _normalize_body(value,reasons_out)
	if rejected.is_empty() and reasons_out.is_empty():reasons_out.append("profile fields")
	return rejected

static func _normalize_body(value: Variant,reasons_out: Array) -> Dictionary:
	if not value is Dictionary or not Catalog.keys_match(value,TOP_KEYS_V2):return {}
	for key in ["schema_version","revision","next_id","completed_runs","best_ticks","essence"]:
		if not Catalog.integer(value[key],0,1000000000):return {}
	if value.schema_version!=2 or value.next_id<1 or not value.items is Array or value.items.size()>MAX_ITEMS or not value.equipped is Dictionary or value.equipped.size()>EQUIP_SLOTS.size() or not value.receipts is Array or value.receipts.size()>64:return {}
	var tables := loot()
	if tables==null:return {}
	var result: Dictionary=value.duplicate(true)
	for key in ["schema_version","revision","next_id","completed_runs","best_ticks","essence"]:result[key]=int(result[key])
	var ids := {};var slots := {}
	for record in result.items:
		if not record is Dictionary or not Catalog.keys_match(record,["storage_id","item"]) or not Catalog.integer(record.storage_id,1,999999999) or ids.has(int(record.storage_id)) or record.storage_id>=result.next_id:return {}
		record.storage_id=int(record.storage_id)
		var item: Variant=record.item
		if not item is Dictionary:return {}
		for key in ITEM_KEYS:
			if not item.has(key):return {}
		for key in item:
			if not key in ITEM_KEYS and not key in ITEM_KEYS_V2:return {}
		if item.has("grammar")!=item.has("required_level") or (item.has("legendary_id") and not item.has("grammar")):return {}
		if _item_shape(item,true)!="":return {}
		var issues: Array[String]=tables.validate(item)
		if not issues.is_empty():
			reasons_out.append("items[%d].item: %s"%[result.items.find(record),issues[0]]);return {}
		# Identity passed; name and description are presentation and follow the current data (memory only).
		if item.has("grammar"):record.item=tables.dress(item)
		ids[record.storage_id]=true;slots[record.storage_id]=item.slot
	var worn := {}
	for slot in result.equipped:
		if not slot in EQUIP_SLOTS or not Catalog.integer(result.equipped[slot],1,999999999):return {}
		var id_ := int(result.equipped[slot])
		if not ids.has(id_) or worn.has(id_):return {}
		# The second ring slot holds a ring; every other slot holds its own kind.
		if slots[id_]!=("ring" if slot=="ring2" else slot):return {}
		worn[id_]=true;result.equipped[slot]=id_
	for receipt in result.receipts:
		if not receipt is String or receipt.length()<1 or receipt.length()>120:return {}
	return result

## Types, lengths and ranges of one item (text keys only when `with_text`), numbers made ints in place. "" when well formed.
static func _item_shape(item: Dictionary,with_text: bool) -> String:
	if not item.get("base_id") is String or item.base_id.length()>100:return "base_id"
	if not item.get("slot") is String or not item.get("quality") is String:return "slot or quality"
	if with_text and (not item.get("name") is String or item.name.length()>160 or not item.get("description") is String or item.description.length()>300):return "text"
	if not item.get("stats") is Dictionary or not item.get("affixes") is Array:return "stats or affixes"
	if not Catalog.integer(item.get("item_level"),1,30):return "item_level"
	item.item_level=int(item.item_level)
	if item.has("grammar"):
		if not Catalog.integer(item.grammar,2,2) or not Catalog.integer(item.get("required_level"),1,30):return "grammar"
		item.grammar=int(item.grammar);item.required_level=int(item.required_level)
		if item.has("legendary_id") and (not item.legendary_id is String or item.legendary_id.length()>60):return "legendary_id"
	for stat in item.stats:
		if not Catalog.integer(item.stats[stat],-1000000,1000000):return "stat value"
		item.stats[stat]=int(item.stats[stat])
	for affix in item.affixes:
		if not affix is Dictionary or not Catalog.keys_match(affix,["id","group","stat","value"]) or not Catalog.integer(affix.value,0,1000000):return "affix"
		affix.value=int(affix.value)
	return ""

# ---------------------------------------------------------------- the schema-4 document

static func _bump(report: Dictionary,key: String,count: int=1) -> void:
	report[key]=int(report.get(key,0))+count

## A list of id-format strings: duplicates are removed (strict: refused). Returns null when it is not such a list.
static func _id_list(value: Variant,limit: int,pattern: String,strict: bool,report: Dictionary) -> Variant:
	if not value is Array or value.size()>limit:return null
	var rule := RegEx.create_from_string(pattern)
	var result: Array=[]
	for entry in value:
		if not entry is String or rule.search(entry)==null:return null
		if entry in result:
			if strict:return null
			_bump(report,"deduped");continue
		result.append(entry)
	return result

## The schema-4 document read with the rules of section 6. strict=true is the write rule: anything that would need a
## fix (text in a file, an item that does not match, a broken investment, a bad slot) refuses. strict=false is the read
## rule: those are fixed in memory (and counted in `report`) or set aside in `quarantine`; only a broken structure refuses.
## Returns {} when refused (a short reason is appended to `reasons_out`), else {state, characters, words}:
## `state` has dressed items, `words` maps storage_id to {"rare_words": [...]} or {"legacy_name": "..."} for the rare ones.
static func read_document(value: Variant,strict: bool=true,report: Dictionary={},notices_out: Dictionary={},reasons_out: Array=[]) -> Dictionary:
	var accepted := _read_body(value,strict,report,notices_out,reasons_out)
	if accepted.is_empty() and reasons_out.is_empty():reasons_out.append("schema 4 document")
	return accepted

static func _read_body(value: Variant,strict: bool,report: Dictionary,notices_out: Dictionary,reasons: Array) -> Dictionary:
	if not value is Dictionary or not Catalog.keys_match(value,TOP_KEYS):return _bad(reasons,"top-level keys")
	if not Catalog.integer(value.schema_version,4,4):return _bad(reasons,"schema version")
	for key in ["revision","next_id","completed_runs","best_ticks","essence","gambles"]:
		if not Catalog.integer(value[key],0,1000000000):return _bad(reasons,key)
	if value.next_id<1:return _bad(reasons,"next_id")
	if not value.items is Array or value.items.size()>MAX_ITEMS or not value.quarantine is Array or value.quarantine.size()>MAX_ITEMS:return _bad(reasons,"items or quarantine size")
	if not value.receipts is Array or value.receipts.size()>64 or not value.characters is Dictionary or not value.codex is Dictionary or not value.shared_story is Dictionary or not value.origin is Dictionary:return _bad(reasons,"shape")
	var tables := loot()
	var doc := progression_doc();var tree_table := trees()
	if tables==null or doc.is_empty() or tree_table.is_empty():return _bad(reasons,"data")
	for receipt in value.receipts:
		if not receipt is String or receipt.length()<1 or receipt.length()>120:return _bad(reasons,"receipts")
	var revision := int(value.revision);var next_id := int(value.next_id)
	# 1. equipment and the quarantine: every storage id is unique over both lists and below next_id.
	var used := {}
	var candidates: Array=[]    # {record, quarantined, reason, since}
	for record in value.items:
		if not record is Dictionary or not record.has("storage_id") or not record.has("item") or not Catalog.integer(record.storage_id,1,999999999):return _bad(reasons,"item record")
		for key in record:
			if not key in ["storage_id","item","locked","new"]:return _bad(reasons,"item record keys")
		var sid := int(record.storage_id)
		if used.has(sid) or sid>=next_id:return _bad(reasons,"storage id")
		used[sid]=true
		candidates.append({"record":record,"quarantined":false,"reason":"","since":revision})
	var kept_quarantine: Array=[]
	for entry in value.quarantine:
		if not entry is Dictionary or not entry.get("kind") is String or not entry.has("raw"):return _bad(reasons,"quarantine entry")
		var kind: String=entry.kind
		if kind=="item":
			if not Catalog.keys_match(entry,["kind","storage_id","reason","since_revision","raw"]) or not Catalog.integer(entry.storage_id,1,999999999):return _bad(reasons,"quarantine entry")
			var qid := int(entry.storage_id)
			if used.has(qid) or qid>=next_id:return _bad(reasons,"storage id")
			used[qid]=true
		elif kind=="character":
			if not Catalog.keys_match(entry,["kind","id","reason","since_revision","raw"]) or not entry.id is String or entry.id.length()>120:return _bad(reasons,"quarantine entry")
		else:
			return _bad(reasons,"quarantine kind")
		if not entry.reason is String or entry.reason.length()<1 or entry.reason.length()>120 or not Catalog.integer(entry.since_revision,0,1000000000):return _bad(reasons,"quarantine reason")
		if JSON.stringify(entry.raw).length()>MAX_RAW:return _bad(reasons,"quarantine raw too large")
		var plain_entry: Dictionary={"kind":kind,"reason":entry.reason,"since_revision":int(entry.since_revision),"raw":_plain(entry.raw)}
		if kind=="item":plain_entry["storage_id"]=int(entry.storage_id)
		else:plain_entry["id"]=entry.id
		if kind=="item" and not strict and plain_entry.raw is Dictionary:
			candidates.append({"record":plain_entry.raw,"quarantined":true,"reason":entry.reason,"since":int(entry.since_revision),"entry":plain_entry,"sid":int(entry.storage_id)})
		else:
			kept_quarantine.append(plain_entry)
	var items: Array=[];var words := {};var item_slots := {};var held := {}
	for candidate in candidates:
		var source: Dictionary=candidate.record
		var result: Dictionary
		if candidate.quarantined:
			# The stored original is a whole record; it must name the same storage id.
			var probe: Dictionary=source.duplicate(true);probe["storage_id"]=int(candidate.sid)
			var probe_report := {}
			result=_evaluate_record(probe,false,tables,probe_report) if source.has("item") else {"ok":false,"reason":"raw is not an item record"}
			if result.ok:
				for key in probe_report:_bump(report,String(key),int(probe_report[key]))
		else:
			result=_evaluate_record(source,strict,tables,report)
		if result.ok:
			var memory: Dictionary=result.record
			items.append(memory);item_slots[int(memory.storage_id)]=memory.item.slot
			if not result.words.is_empty():words[int(memory.storage_id)]=result.words
			if candidate.quarantined:_bump(report,"restored_items")
		else:
			if strict:return _bad(reasons,"items: "+String(result.reason))
			if candidate.quarantined:
				kept_quarantine.append(candidate.entry);held[int(candidate.sid)]=true
			else:
				var original: Variant=_plain(candidate.record)
				var fresh_entry := {"kind":"item","storage_id":int(source.storage_id),"reason":String(result.reason).left(120),"since_revision":revision,"raw":original}
				if JSON.stringify(original).length()>MAX_RAW:return _bad(reasons,"quarantine raw too large")
				kept_quarantine.append(fresh_entry);held[int(source.storage_id)]=true
				_bump(report,"quarantined_items")
	for entry in kept_quarantine:
		if entry.kind=="item":held[int(entry.storage_id)]=true
	items.sort_custom(func(a,b):return int(a.storage_id)<int(b.storage_id))
	# 2. witches
	var cleaned := {}
	var context := {"report":report,"notices":notices_out,"doc":doc,"trees":tree_table,"item_slots":item_slots,"held":held,"strict":strict}
	for id_ in value.characters:
		var known: Dictionary=Progression.character_entry(doc,String(id_)) if id_ is String else {}
		if known.is_empty():
			if strict:return _bad(reasons,"unknown character")
			var raw_entry: Variant=_plain(value.characters[id_])
			var set_aside := {"kind":"character","id":String(id_).left(120),"reason":"unknown character","since_revision":revision,"raw":raw_entry}
			if JSON.stringify(raw_entry).length()>MAX_RAW:return _bad(reasons,"quarantine raw too large")
			kept_quarantine.append(set_aside);_bump(report,"quarantined_characters");continue
		var entry: Variant=_read_character(known,value.characters[id_],context,reasons)
		if entry==null:return {}
		cleaned[String(id_)]=entry
	if not strict:
		# A witch set aside earlier comes back once her id is known and her record reads cleanly.
		var still: Array=[]
		for set_aside in kept_quarantine:
			if set_aside.kind=="character":
				var known_again: Dictionary=Progression.character_entry(doc,String(set_aside.id))
				if not known_again.is_empty() and not cleaned.has(set_aside.id) and set_aside.raw is Dictionary and Catalog.keys_match(set_aside.raw,CHAR_KEYS):
					var probe_reasons := []
					var back: Variant=_read_character(known_again,set_aside.raw,{"report":{},"notices":{},"doc":doc,"trees":tree_table,"item_slots":item_slots,"held":held,"strict":true},probe_reasons)
					if back!=null:
						cleaned[String(set_aside.id)]=_read_character(known_again,set_aside.raw,context,probe_reasons);_bump(report,"restored_characters");continue
			still.append(set_aside)
		kept_quarantine=still
	if kept_quarantine.size()>MAX_ITEMS:return _bad(reasons,"quarantine size")
	# 3. the rest of the top level
	var codex: Dictionary={}
	if not Catalog.keys_match(value.codex,["uniques","legendaries","set_pieces"]):return _bad(reasons,"codex keys")
	for key in ["uniques","legendaries","set_pieces"]:
		var list: Variant=_id_list(value.codex[key],64,ID_PATTERN,strict,report)
		if list==null:return _bad(reasons,"codex")
		codex[key]=list
	var shared: Dictionary=value.shared_story
	if not Catalog.keys_match(shared,["seen","true_ending"]) or not shared.true_ending is bool:return _bad(reasons,"shared_story")
	var shared_seen: Variant=_id_list(shared.seen,64,ID_PATTERN,strict,report)
	if shared_seen==null:return _bad(reasons,"shared_story seen")
	var origin: Dictionary=value.origin
	if not Catalog.keys_match(origin,["from_schema","from_file","from_revision","at_unix"]) or not Catalog.integer(origin.from_schema,0,4) or not Catalog.integer(origin.from_revision,0,1000000000) or not Catalog.integer(origin.at_unix,0,4000000000):return _bad(reasons,"origin")
	if not origin.from_file is String or origin.from_file.length()>120 or origin.from_file.contains("/") or origin.from_file.contains("\\"):return _bad(reasons,"origin file")
	var memory_state := {"schema_version":4,"revision":revision,"next_id":next_id,"items":items,"completed_runs":int(value.completed_runs),"best_ticks":int(value.best_ticks),
		"essence":int(value.essence),"receipts":value.receipts.duplicate(),"codex":codex,"gambles":int(value.gambles),"shared_story":{"seen":shared_seen,"true_ending":shared.true_ending},
		"quarantine":kept_quarantine,"origin":{"from_schema":int(origin.from_schema),"from_file":origin.from_file,"from_revision":int(origin.from_revision),"at_unix":int(origin.at_unix)}}
	return {"state":memory_state,"characters":cleaned,"words":words}

## One stored equipment record -> {"ok": true, "record": memory record, "words": {...}} or {"ok": false, "reason": "..."}.
## The memory item has name and description again (rebuilt from the data; a rare one from its words or old text).
static func _evaluate_record(record: Dictionary,strict: bool,tables: RefCounted,report: Dictionary) -> Dictionary:
	if not record.get("item") is Dictionary:return {"ok":false,"reason":"item is not an object"}
	var work: Dictionary=_plain(record.item)
	var out_record := {"storage_id":int(record.storage_id)}
	var flags := {}
	for flag in ["locked","new"]:
		if record.has(flag):
			if record[flag] is bool and record[flag]==true:flags[flag]=true
			elif strict:return {"ok":false,"reason":"flag value"}
			else:_bump(report,"dropped_flags")
	var words := {}
	if not work.has("grammar"):
		# The old v1 item keeps its text in the file and its own validator.
		for key in ITEM_KEYS:
			if not work.has(key):return {"ok":false,"reason":"missing key"}
		for key in work:
			if not key in ITEM_KEYS:return {"ok":false,"reason":"unknown key"}
		var why := _item_shape(work,true)
		if why!="":return {"ok":false,"reason":why}
		var v1_issues: Array[String]=tables.validate(work)
		if not v1_issues.is_empty():return {"ok":false,"reason":v1_issues[0]}
		out_record["item"]=work
	else:
		for key in work:
			if not key in ITEM_KEYS_V4 and not key in ITEM_KEYS_V4_OPTIONAL and key!="name" and key!="description":return {"ok":false,"reason":"unknown key"}
		for key in ITEM_KEYS_V4:
			if not work.has(key):return {"ok":false,"reason":"missing key"}
		if work.has("name") or work.has("description"):
			if strict:return {"ok":false,"reason":"text in file"}
			work.erase("name");work.erase("description");_bump(report,"stripped_text")
		var why := _item_shape(work,false)
		if why!="":return {"ok":false,"reason":why}
		var is_rare: bool=work.quality=="rare"
		var shown := "x"
		if not is_rare and (work.has("rare_words") or work.has("legacy_name")):return {"ok":false,"reason":"rare text on a non-rare item"}
		if is_rare:
			if work.has("rare_words")==work.has("legacy_name"):return {"ok":false,"reason":"rare item needs rare_words or legacy_name"}
			if work.has("rare_words"):
				var pair: Variant=work.rare_words
				var word_rule := RegEx.create_from_string(WORD_ID_PATTERN)
				if not pair is Array or pair.size()!=2 or not pair[0] is String or not pair[1] is String or word_rule.search(pair[0])==null or word_rule.search(pair[1])==null:return {"ok":false,"reason":"rare_words shape"}
				words={"rare_words":[pair[0],pair[1]]}
				shown=tables.rare_name_for(words.rare_words)
				if not tables.rare_words_known(words.rare_words):_bump(report,"unnamed_rare")
			else:
				if not work.legacy_name is String or not tables._check_text({"name":work.legacy_name,"description":""}).is_empty():return {"ok":false,"reason":"legacy_name text"}
				words={"legacy_name":work.legacy_name};shown=work.legacy_name
		work.erase("rare_words");work.erase("legacy_name")
		if work.has("veiled") and not (work.veiled is bool and work.veiled==true):
			if strict:return {"ok":false,"reason":"veiled flag"}
			work.erase("veiled");_bump(report,"dropped_flags")
		work["name"]=shown;work["description"]=""
		var issues: Array[String]=tables.validate(work)
		if not issues.is_empty():return {"ok":false,"reason":issues[0]}
		out_record["item"]=tables.dress(work)
	for flag in flags:out_record[flag]=true
	return {"ok":true,"record":out_record,"words":words}

## One witch's record. Returns the cleaned entry or null when the structure is broken (a reason is appended).
static func _read_character(known: Dictionary,entry: Variant,context: Dictionary,reasons: Array) -> Variant:
	var strict: bool=context.strict;var report: Dictionary=context.report;var doc: Dictionary=context.doc
	if not entry is Dictionary or not Catalog.keys_match(entry,CHAR_KEYS):_bad(reasons,"character keys");return null
	if not Catalog.integer(entry.xp,0,1000000000) or not Catalog.integer(entry.tree_revision,0,1000000) or not Catalog.integer(entry.respecs,0,1000000000):_bad(reasons,"character numbers");return null
	if not entry.ranks is Dictionary or not entry.first_rewards is Array or entry.first_rewards.size()>32:_bad(reasons,"character shape");return null
	var firsts: Array=[];var known_firsts: Array=[]
	for reward in entry.first_rewards:
		if not reward is String or reward.length()<1 or reward.length()>80:_bad(reasons,"first reward");return null
		if reward in firsts:
			if strict:_bad(reasons,"duplicate first reward");return null
			_bump(report,"deduped");continue
		firsts.append(reward)
		if doc.first_rewards.has(reward):known_firsts.append(reward)
		else:_bump(report,"unknown_ids")
	var ranks := {}
	for node_id in entry.ranks:
		if not node_id is String or not Catalog.integer(entry.ranks[node_id],1,10):_bad(reasons,"rank value");return null
		ranks[node_id]=int(entry.ranks[node_id])
	var xp := int(entry.xp);var revision := int(entry.tree_revision)
	var id_: String=known.id
	var refunded := false
	if known.get("tree_id")==null:
		if revision!=0 or not ranks.is_empty():
			if strict:_bad(reasons,"ranks without a tree");return null
			refunded=not ranks.is_empty();ranks={};revision=0
	else:
		if not context.trees.has(known.tree_id):_bad(reasons,"tree data");return null
		var tree: Dictionary=context.trees[known.tree_id]
		var violation := revision==0 and not ranks.is_empty()
		if revision!=0 and revision!=int(tree.revision):
			if strict:_bad(reasons,"tree revision");return null
			violation=not ranks.is_empty();ranks={};revision=int(tree.revision)
			if violation:context.notices[id_]=true;_bump(report,"refunded_trees")
			violation=false
		if not violation and not SkillTree.legal_ranks(tree,ranks,Progression.level_for_xp(doc,xp),Progression.points_earned(doc,xp,known_firsts)).is_empty():violation=true
		if violation:
			if strict:_bad(reasons,"illegal investment");return null
			ranks={};revision=int(tree.revision);context.notices[id_]=true;_bump(report,"refunded_trees")
	if refunded:context.notices[id_]=true;_bump(report,"refunded_trees")
	# loadout
	if not entry.loadout is Dictionary or entry.loadout.size()>EQUIP_SLOTS.size():_bad(reasons,"loadout");return null
	var loadout := {};var worn := {}
	for slot in EQUIP_SLOTS:
		if not entry.loadout.has(slot):continue
		var wanted: Variant=entry.loadout[slot]
		var good := Catalog.integer(wanted,1,999999999)
		var sid := int(wanted) if good else -1
		var inactive := false
		if good:
			if context.item_slots.has(sid):
				if context.item_slots[sid]!=("ring" if slot=="ring2" else slot) or worn.has(sid):good=false
			elif context.held.has(sid) and not worn.has(sid):inactive=true
			else:good=false
		if not good:
			if strict:_bad(reasons,"loadout entry");return null
			_bump(report,"dropped_loadout");continue
		if inactive:_bump(report,"inactive_loadout")
		worn[sid]=true;loadout[slot]=sid
	for key in entry.loadout:
		if not key in EQUIP_SLOTS:
			if strict:_bad(reasons,"loadout slot");return null
			_bump(report,"dropped_loadout")
	# depth
	if not entry.depth_cleared is Dictionary or entry.depth_cleared.size()>16:_bad(reasons,"depth_cleared");return null
	var depth := {};var depth_rule := RegEx.create_from_string(DEPTH_KEY_PATTERN)
	for key in entry.depth_cleared:
		if not key is String or depth_rule.search(key)==null or not Catalog.integer(entry.depth_cleared[key],0,3):_bad(reasons,"depth_cleared entry");return null
		depth[key]=int(entry.depth_cleared[key])
	# wardrobe
	var wardrobe: Variant=entry.wardrobe
	if not wardrobe is Dictionary or not Catalog.keys_match(wardrobe,["owned","worn"]) or not wardrobe.worn is String:_bad(reasons,"wardrobe");return null
	var owned: Variant=_id_list(wardrobe.owned,64,ID_PATTERN,strict,report)
	var id_rule := RegEx.create_from_string(ID_PATTERN)
	if owned==null or (not wardrobe.worn.is_empty() and id_rule.search(wardrobe.worn)==null):_bad(reasons,"wardrobe ids");return null
	var outfit_table := outfits()
	for outfit_id in owned:
		if not outfit_table.has(outfit_id):_bump(report,"unknown_ids")
	if not wardrobe.worn.is_empty() and (not outfit_table.has(wardrobe.worn) or (outfit_table[wardrobe.worn].character_id!=id_)):_bump(report,"unknown_ids")
	# story
	var story: Variant=entry.story
	if not story is Dictionary or not Catalog.keys_match(story,["found","seen","duel_cleared","final_cleared"]) or not story.duel_cleared is bool or not story.final_cleared is bool:_bad(reasons,"story");return null
	var found: Variant=_id_list(story.found,128,ID_PATTERN,strict,report)
	var seen_list: Variant=_id_list(story.seen,128,ID_PATTERN,strict,report)
	if found==null or seen_list==null:_bad(reasons,"story ids");return null
	# the reserved tree_reset slot (rule switch and grants are not built yet)
	var reset: Variant=entry.tree_reset
	if not reset is Dictionary or not Catalog.keys_match(reset,["granted","used"]):_bad(reasons,"tree_reset");return null
	var granted: Variant=_id_list(reset.granted,16,RESET_ID_PATTERN,strict,report)
	var used_list: Variant=_id_list(reset.used,16,RESET_ID_PATTERN,strict,report)
	if granted==null or used_list==null:_bad(reasons,"tree_reset ids");return null
	for spent in used_list:
		if not spent in granted:
			if strict:_bad(reasons,"tree_reset used without granted");return null
			granted.append(spent);_bump(report,"tree_reset_fixed")
	if granted.size()>16:_bad(reasons,"tree_reset size");return null
	return {"xp":xp,"tree_revision":revision,"ranks":ranks,"first_rewards":firsts,"respecs":int(entry.respecs),"loadout":loadout,"depth_cleared":depth,
		"wardrobe":{"owned":owned,"worn":wardrobe.worn},"story":{"found":found,"seen":seen_list,"duel_cleared":story.duel_cleared,"final_cleared":story.final_cleared},
		"tree_reset":{"granted":granted,"used":used_list}}

## The file form of the memory state: equipment without text, a rare item with its words.
func _document(candidate: Dictionary,table: Dictionary,words: Dictionary) -> Dictionary:
	var items: Array=[]
	var tables := loot()
	for record in candidate.items:
		var item: Dictionary=record.item.duplicate(true)
		if item.has("grammar"):
			var shown := String(item.get("name",""))
			item.erase("name");item.erase("description")
			if item.quality=="rare":
				var stored: Variant=words.get(int(record.storage_id))
				if stored==null:
					var ids: Array=tables.rare_word_ids(shown)
					stored={"rare_words":ids} if not ids.is_empty() else {"legacy_name":shown}
				for key in stored:item[key]=stored[key].duplicate() if stored[key] is Array else stored[key]
		var row := {"storage_id":int(record.storage_id),"item":item}
		for flag in ["locked","new"]:
			if record.has(flag):row[flag]=record[flag]
		items.append(row)
	return {"schema_version":4,"revision":int(candidate.revision),"next_id":int(candidate.next_id),"items":items,"completed_runs":int(candidate.completed_runs),
		"best_ticks":int(candidate.best_ticks),"essence":int(candidate.essence),"receipts":candidate.receipts.duplicate(),"characters":table.duplicate(true),
		"codex":candidate.codex.duplicate(true),"gambles":int(candidate.gambles),"shared_story":candidate.shared_story.duplicate(true),
		"quarantine":candidate.quarantine.duplicate(true),"origin":candidate.origin.duplicate(true)}

## Writes the candidate: a journal copy in revisions/, then a temporary file replaced over the main file.
## The candidate must pass the strict rule (read_document strict) first; nothing is written when it does not.
func _persist(candidate: Dictionary,next_characters: Variant=null,next_words: Variant=null) -> bool:
	if not available:_err("save_path_unverified","Save path not verified");return false
	candidate=candidate.duplicate(true);candidate.revision=int(state.revision)+1
	if int(candidate.origin.at_unix)==0:
		candidate.origin={"from_schema":int(_origin_hint.from_schema),"from_file":String(_origin_hint.from_file),"from_revision":int(_origin_hint.from_revision),"at_unix":maxi(1,int(Time.get_unix_time_from_system()))}
	var table: Dictionary=(characters if next_characters==null else next_characters)
	var words: Dictionary=(_words if next_words==null else next_words)
	var document := _document(candidate,table,words)
	var why := []
	var checked := read_document(document,true,{},{},why)
	if checked.is_empty():_err("save_candidate_rejected","Save candidate failed validation: "+(String(why[0]) if not why.is_empty() else "unknown"));return false
	if FileAccess.file_exists(path):
		if FileAccess.get_file_as_string(path)!=_loaded_text:_err("save_changed_elsewhere","Save was changed by another run; existing file kept");return false
	elif not _loaded_text.is_empty():_err("save_moved","Save file was moved outside the game");return false
	var text := JSON.stringify(document,"  ")
	var date := Time.get_date_dict_from_system()
	var stamp := "%06d-%04d%02d%02d-%d-%d"%[int(candidate.revision),date.year,date.month,date.day,OS.get_process_id(),Time.get_ticks_usec()]
	var journal := journal_dir()+"/"+path.get_file().get_basename()+".revision-"+stamp+".json"
	var temporary := path+".next-"+stamp+".tmp"
	if FileAccess.file_exists(journal) or FileAccess.file_exists(temporary):_err("save_name_conflict","Save file name conflict");return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(journal_dir())
	for target in [journal,temporary]:
		var file := FileAccess.open(target,FileAccess.WRITE)
		if file==null:_err("save_create_failed","Save file creation failed");return false
		file.store_string(text);file.flush();var status := file.get_error();file.close()
		if status!=OK or FileAccess.get_file_as_string(target)!=text:_err("save_write_failed","Save write verification failed");return false
	# The immutable revision remains if replacement fails. No historic backup is deleted.
	var rename := DirAccess.rename_absolute(temporary,path)
	if rename!=OK:_err("save_replace_failed","Save replacement failed; previous file and new revision kept");return false
	if FileAccess.get_file_as_string(path)!=text:_err("save_replace_verify_failed","Save replacement verification failed");return false
	_adopt(checked);_loaded_text=text;error="";imported_from_v1=false;imported_from_v2=false;imported_from_v3=false;read_report={}
	return true

# ---------------------------------------------------------------- progress and receipts

## Validates a run's progress and returns the new characters table, or {"error": reason, "code": code}. Pure: used by
## record_run and by simulations that keep the profile in memory.
## progress = {character_id, xp_gained, first_kills: [reward id...]} (other keys of progress_summary are ignored).
static func apply_progress(current: Dictionary,progress: Dictionary) -> Dictionary:
	var doc := progression_doc();var table := trees()
	if doc.is_empty() or table.is_empty():return {"error":"Growth data could not be read","code":"growth_data_missing"}
	var id_: Variant=progress.get("character_id")
	var known: Dictionary=Progression.character_entry(doc,id_) if id_ is String else {}
	if known.is_empty():return {"error":"Unknown character","code":"unknown_character"}
	if not Catalog.integer(progress.get("xp_gained"),0,int(Progression.xp_bounds(doc).run_xp_max)):return {"error":"Experience out of range","code":"xp_out_of_range"}
	if not progress.get("first_kills",[]) is Array:return {"error":"First-kill list has the wrong shape","code":"first_kills_format"}
	for reward in progress.get("first_kills",[]):
		if not reward is String or not doc.first_rewards.has(reward):return {"error":"Unknown first-kill id","code":"first_kill_unknown"}
	var result: Dictionary=current.duplicate(true)
	var entry: Dictionary=result.get(id_,default_entry(id_))
	entry.xp=mini(1000000000,int(entry.xp)+int(progress.xp_gained))
	for reward in progress.get("first_kills",[]):
		if not reward in entry.first_rewards:entry.first_rewards.append(reward)
	result[id_]=entry
	return result

## One atomic write holds the equipment, the receipt, the experience, the first kills and the worn kit of the run.
## A receipt already recorded changes nothing (no second payout). `progress` is optional; see apply_progress.
## `carry` = {character_id, equipped: {slot: uid}, kept_slots: [slot...]} sets that witch's loadout from what she wore
## at the end of the run (kept_slots keep their earlier value). An empty carry leaves every loadout as it was.
## Any invalid part refuses the whole save.
func record_run(receipt: String,inventory: Array,pending: Array,victory: bool,ticks: int,progress: Dictionary={},carry: Dictionary={}) -> bool:
	if not available:return false
	if receipt in state.receipts:return true
	carry_note=""
	if receipt.length()<1 or receipt.length()>120 or inventory.size()>65 or pending.size()>4 or ticks<0:return false
	var next_characters: Variant=null
	if not progress.is_empty():
		var applied := apply_progress(characters,progress)
		if applied.has("error"):_err(String(applied.get("code","progress_rejected")),String(applied.error));return false
		next_characters=applied
	var collectibles: Array=progress.get("collectibles_found",[]) if progress.get("collectibles_found",[]) is Array else []
	if not collectibles.is_empty():
		var known_collectibles: Array=_known_ids("collectibles");var witch_id := String(progress.get("character_id",""))
		for found_id in collectibles:
			if not found_id is String or not found_id in known_collectibles:_err("save_candidate_rejected","Unknown collectible id");return false
		if next_characters==null:_err("save_candidate_rejected","Collectibles need the run's witch");return false
		var story: Dictionary=next_characters[witch_id].story
		for found_id in collectibles:
			if not found_id in story.found:story.found.append(found_id)
	var candidate: Dictionary=state.duplicate(true)
	var by_uid := {}
	for index in inventory.size()+pending.size():
		var in_inventory: bool=index<inventory.size()
		var source: Dictionary=inventory[index] if in_inventory else pending[index-inventory.size()]
		var is_stored: bool=source.has("storage_id")
		if not is_stored:
			var clean := {}
			for key in ITEM_KEYS+ITEM_KEYS_V2:
				if source.has(key):clean[key]=source[key]
			if not loot().validate(clean).is_empty():_err("reward_rejected","Reward item failed validation");return false
			candidate.items.append({"storage_id":int(candidate.next_id),"item":clean.duplicate(true)})
			if clean.get("quality")=="unique" and String(clean.get("base_id","")).begins_with(UNIQUE_ID_PREFIX):_codex_add(candidate,"uniques",String(clean.base_id).trim_prefix(UNIQUE_ID_PREFIX))
			if clean.get("quality")=="legendary" and clean.has("legendary_id"):_codex_add(candidate,"legendaries",String(clean.legendary_id))
			candidate.next_id+=1
		if in_inventory and source.has("uid"):by_uid[int(source.uid)]=int(source.storage_id) if is_stored else int(candidate.next_id)-1
	if candidate.items.size()>MAX_ITEMS:_err("stash_full","Stash is full");return false
	if not carry.is_empty():
		var table: Dictionary=(next_characters if next_characters!=null else characters).duplicate(true)
		var carried := _apply_carry(carry,progress,by_uid,candidate,table)
		# A worn set that cannot be validated never costs the run's rewards: they are saved without it and the note says so.
		if carried.is_empty():
			next_characters=table
		else:
			carry_note="kit_not_saved"
			print("CHAPTER1_PROFILE_CARRY_DROPPED ",JSON.stringify({"reason":carried}))
	candidate.receipts.append(receipt)
	if candidate.receipts.size()>64:candidate.receipts.pop_front()
	if victory:
		candidate.completed_runs+=1
		if candidate.best_ticks==0 or ticks<candidate.best_ticks:candidate.best_ticks=ticks
	return _persist(candidate,next_characters)

static func _codex_add(candidate: Dictionary,key: String,id_: String) -> void:
	var list: Array=candidate.codex[key]
	if not id_ in list and list.size()<64 and RegEx.create_from_string(ID_PATTERN).search(id_)!=null:list.append(id_)

## Sets the witch's loadout in `table` from the run's worn pieces. Returns "" on success, else the reason.
func _apply_carry(carry: Dictionary,progress: Dictionary,by_uid: Dictionary,candidate: Dictionary,table: Dictionary) -> String:
	var witch_id: Variant=carry.get("character_id")
	if not witch_id is String or Progression.character_entry(progression_doc(),witch_id).is_empty():return "unknown witch"
	if progress.has("character_id") and progress.character_id!=witch_id:return "witch differs from the run's progress"
	var equipped: Variant=carry.get("equipped",{});var kept: Variant=carry.get("kept_slots",[])
	if not equipped is Dictionary or not kept is Array or equipped.size()>EQUIP_SLOTS.size():return "shape"
	var slot_of := {}
	for record in candidate.items:slot_of[int(record.storage_id)]=String(record.item.slot)
	var entry: Dictionary=table.get(witch_id,default_entry(witch_id)).duplicate(true)
	var previous: Dictionary=entry.loadout
	var next := {};var worn := {}
	for slot in equipped:
		if not slot is String or not slot in EQUIP_SLOTS or not Catalog.integer(equipped[slot],0,1000000000):return "slot or uid"
		var uid := int(equipped[slot])
		if not by_uid.has(uid):return "uid is not in the run's inventory"
		var sid: int=by_uid[uid]
		if not slot_of.has(sid) or slot_of[sid]!=("ring" if slot=="ring2" else slot) or worn.has(sid):return "piece does not fit the slot"
		worn[sid]=true;next[slot]=sid
	for slot in kept:
		# What she wore in the run wins: a slot that was left behind at the start and filled in the run takes the run's piece.
		if not slot is String or not slot in EQUIP_SLOTS:return "kept slot"
		if next.has(slot):continue
		if previous.has(slot) and not worn.has(int(previous[slot])):next[slot]=int(previous[slot])
	entry.loadout=next;table[witch_id]=entry
	return ""

# ---------------------------------------------------------------- the worn kit (per witch)

## Level an item needs: its own required_level (grammar v2), or item_level - 3 for older items.
static func required_level_of(item: Dictionary) -> int:
	return int(item.get("required_level",maxi(1,int(item.get("item_level",1))-3)))

## {slot: storage_id} this witch starts with.
func loadout(character_id: String) -> Dictionary:
	return character_entry(character_id).loadout.duplicate(true)

## Which slot of this witch's kit holds this stored item, or "" when it is not selected.
func equip_slot_of(storage_id: int,character_id: String) -> String:
	var worn: Dictionary=character_entry(character_id).loadout
	for slot in EQUIP_SLOTS:
		if worn.has(slot) and int(worn[slot])==storage_id:return slot
	return ""

func _record_of(storage_id: int) -> Dictionary:
	for record in state.items:
		if int(record.storage_id)==storage_id:return record
	return {}

## Select an item for this witch's starting kit. A witch is required; an item above her level is refused.
## The same item may be in several witches' kits.
func select_item(storage_id: int,character_id: String) -> bool:
	if character_id.is_empty() or Progression.character_entry(progression_doc(),character_id).is_empty():_err("unknown_character","Unknown character");return false
	if not equip_slot_of(storage_id,character_id).is_empty():return true
	var record := _record_of(storage_id)
	if record.is_empty():return false
	if required_level_of(record.item)>character_level(character_id):
		_err("level_required","Level %d required"%required_level_of(record.item),{"n":required_level_of(record.item)});return false
	var entry := character_entry(character_id);var worn: Dictionary=entry.loadout
	var slot: String=record.item.slot
	# A ring takes the first free ring slot, otherwise it replaces the first ring.
	if slot=="ring" and worn.has("ring") and not worn.has("ring2"):slot="ring2"
	worn[slot]=storage_id
	var table: Dictionary=characters.duplicate(true);table[character_id]=entry
	return _persist(state.duplicate(true),table)

func unselect(slot: String,character_id: String) -> bool:
	if character_id.is_empty() or not character_entry(character_id).loadout.has(slot):return false
	var entry := character_entry(character_id)
	entry.loadout.erase(slot)
	var table: Dictionary=characters.duplicate(true);table[character_id]=entry
	return _persist(state.duplicate(true),table)

func salvage(storage_id: int) -> bool:
	var candidate: Dictionary=state.duplicate(true);var index := -1
	for i in candidate.items.size():
		if candidate.items[i].storage_id==storage_id:index=i;break
	if index<0:return false
	var item: Dictionary=candidate.items[index].item
	var table: Dictionary=characters.duplicate(true)
	for id_ in table:
		for slot in table[id_].loadout.keys():
			if int(table[id_].loadout[slot])==storage_id:table[id_].loadout.erase(slot)
	candidate.items.remove_at(index);candidate.essence=mini(1000000000,int(candidate.essence)+int(ESSENCE.get(item.quality,1)))
	return _persist(candidate,table)

## {gear, kept_slots}: `gear` is what the core's import_starting_gear takes (each piece with storage_id and equip_slot,
## in slot order); `kept_slots` are slots of the kit that stay selected but do not go along (the witch is below the
## level the piece needs, or the piece is set aside in quarantine).
func starting_kit(character_id: String) -> Dictionary:
	var gear: Array[Dictionary]=[];var kept: Array[String]=[]
	if character_id.is_empty() or Progression.character_entry(progression_doc(),character_id).is_empty():return {"gear":gear,"kept_slots":kept}
	var worn: Dictionary=character_entry(character_id).loadout
	var level := character_level(character_id)
	for slot in EQUIP_SLOTS:
		if not worn.has(slot):continue
		var record := _record_of(int(worn[slot]))
		if not record.is_empty() and required_level_of(record.item)<=level:
			var item: Dictionary=record.item.duplicate(true);item.storage_id=record.storage_id;item.equip_slot=slot;gear.append(item)
		else:kept.append(slot)
	return {"gear":gear,"kept_slots":kept}

func starting_gear(character_id: String) -> Array[Dictionary]:
	return starting_kit(character_id).gear

## Selected pieces this witch is too low-level to take along: [{storage_id, slot, required_level}].
func blocked_gear(character_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if character_id.is_empty():return result
	var level := character_level(character_id)
	var worn: Dictionary=character_entry(character_id).loadout
	for slot in EQUIP_SLOTS:
		if not worn.has(slot):continue
		var record := _record_of(int(worn[slot]))
		if not record.is_empty() and required_level_of(record.item)>level:
			result.append({"storage_id":int(record.storage_id),"slot":slot,"required_level":required_level_of(record.item)})
	return result

# ---------------------------------------------------------------- outfits and the story record

## {owned: [ids], worn: id} for the screen: the data's default-owned outfits plus the saved ones, unknown ids left out.
func wardrobe_view(character_id: String) -> Dictionary:
	var table := outfits();var entry := character_entry(character_id);var owned: Array=[]
	for id_ in table:
		if table[id_].character_id==character_id and (table[id_].default_owned or id_ in entry.wardrobe.owned):owned.append(id_)
	var worn: String=entry.wardrobe.worn
	return {"owned":owned,"worn":worn if worn in owned else ""}

## Put an outfit on ("" = the plain outfit). Only an outfit this witch owns.
func wear_outfit(character_id: String,outfit_id: String) -> bool:
	if Progression.character_entry(progression_doc(),character_id).is_empty():_err("unknown_character","Unknown character");return false
	if not outfit_id.is_empty() and not outfit_id in wardrobe_view(character_id).owned:_err("save_candidate_rejected","Outfit is unknown or not owned");return false
	var entry := character_entry(character_id)
	if entry.wardrobe.worn==outfit_id:return true
	entry.wardrobe.worn=outfit_id
	var table: Dictionary=characters.duplicate(true);table[character_id]=entry
	return _persist(state.duplicate(true),table)

## Give a witch an outfit from outfits.json. Already owned changes nothing.
func grant_outfit(character_id: String,outfit_id: String) -> bool:
	var table_outfits := outfits()
	if Progression.character_entry(progression_doc(),character_id).is_empty() or not table_outfits.has(outfit_id) or table_outfits[outfit_id].character_id!=character_id:_err("save_candidate_rejected","Outfit is unknown or belongs to another witch");return false
	if outfit_id in wardrobe_view(character_id).owned:return true
	var entry := character_entry(character_id)
	entry.wardrobe.owned.append(outfit_id)
	var table: Dictionary=characters.duplicate(true);table[character_id]=entry
	return _persist(state.duplicate(true),table)

## A scene seen by this witch, once. An id already recorded writes nothing and returns true.
func mark_story_seen(character_id: String,beat_id: String) -> bool:
	if Progression.character_entry(progression_doc(),character_id).is_empty() or not beat_id in _known_ids("story"):_err("save_candidate_rejected","Unknown story id");return false
	var entry := character_entry(character_id)
	if beat_id in entry.story.seen:return true
	entry.story.seen.append(beat_id)
	var table: Dictionary=characters.duplicate(true);table[character_id]=entry
	return _persist(state.duplicate(true),table)

## A scene seen by any witch (the shared-scene skip). Once; a repeat writes nothing.
func mark_shared_seen(beat_id: String) -> bool:
	if not beat_id in _known_ids("shared"):_err("save_candidate_rejected","Unknown shared story id");return false
	if beat_id in state.shared_story.seen:return true
	var candidate: Dictionary=state.duplicate(true)
	candidate.shared_story.seen.append(beat_id)
	return _persist(candidate)

# ---------------------------------------------------------------- permanent growth

## The stored entry, or a default one (xp 0, no ranks) for a witch that has not finished a run yet.
func character_entry(character_id: String) -> Dictionary:
	if characters.has(character_id):return characters[character_id].duplicate(true)
	return default_entry(character_id)

func character_level(character_id: String) -> int:
	return Progression.level_for_xp(progression_doc(),int(character_entry(character_id).xp))

## Screen data: {character_id, has_tree, tree_id, level, xp, xp_level_start, xp_for_next (next threshold, the
## "3,880 / 4,500" number; at the cap the last threshold), xp_to_next (remaining, 0 at the cap), points_earned,
## points_spent, points_free, ranks, first_rewards, respecs, refunded_notice}. {} when the profile is not ready.
func character_view(character_id: String) -> Dictionary:
	var doc := progression_doc();var known := Progression.character_entry(doc,character_id)
	if not available or known.is_empty():return {}
	var entry := character_entry(character_id);var xp := int(entry.xp)
	var level := Progression.level_for_xp(doc,xp);var curve: Array=doc.xp_thresholds
	var earned := Progression.points_earned(doc,xp,entry.first_rewards);var spent := SkillTree.points_spent(entry.ranks)
	return {"character_id":character_id,"has_tree":known.get("tree_id")!=null,"tree_id":known.get("tree_id") if known.get("tree_id")!=null else "",
		"level":level,"xp":xp,"xp_level_start":int(curve[level-1]),"xp_for_next":int(curve[mini(level,curve.size()-1)]),"xp_to_next":Progression.xp_for_next(doc,xp),
		"points_earned":earned,"points_spent":spent,"points_free":earned-spent,"ranks":entry.ranks,"first_rewards":entry.first_rewards,
		"respecs":int(entry.respecs),"refunded_notice":notices.has(character_id)}

func acknowledge_notice(character_id: String) -> void:
	notices.erase(character_id)

## The dictionary the combat core receives before start() (spec 7.1):
## {character_id, tree_id, tree_revision, ranks, character_level, character_xp}.
## For a witch without a tree, tree_id is "" and tree_revision 0 with empty ranks (she still earns experience).
## {} when the profile is not ready or the witch is unknown.
func build_for(character_id: String) -> Dictionary:
	var doc := progression_doc();var known := Progression.character_entry(doc,character_id)
	if not available or known.is_empty():return {}
	var entry := character_entry(character_id);var xp := int(entry.xp)
	var has_tree: bool=known.get("tree_id")!=null
	return {"character_id":character_id,"tree_id":known.tree_id if has_tree else "","tree_revision":int(entry.tree_revision) if has_tree else 0,
		"ranks":entry.ranks.duplicate(true) if has_tree else {},"character_level":Progression.level_for_xp(doc,xp),"character_xp":xp}

## Confirm a staged tree. The new ranks must contain the committed ones (only respec lowers them), be reachable,
## and fit the witch's level and earned points.
func commit_tree(character_id: String,ranks: Dictionary) -> bool:
	if not available:return false
	var doc := progression_doc();var known := Progression.character_entry(doc,character_id)
	if known.is_empty() or known.get("tree_id")==null or not trees().has(known.tree_id):_err("tree_locked","This witch's skill tree is not open yet");return false
	var tree: Dictionary=trees()[known.tree_id];var entry := character_entry(character_id)
	var next := {}
	for node_id in ranks:
		if not node_id is String or not Catalog.integer(ranks[node_id],1,10):_err("tree_rejected","Tree investment failed validation");return false
		next[node_id]=int(ranks[node_id])
	for node_id in entry.ranks:
		if int(next.get(node_id,0))<int(entry.ranks[node_id]):_err("tree_confirmed","Confirmed investment can only be undone by a full reset");return false
	var xp := int(entry.xp)
	var known_firsts: Array=[]
	for reward in entry.first_rewards:
		if doc.first_rewards.has(reward):known_firsts.append(reward)
	var problems := SkillTree.legal_ranks(tree,next,Progression.level_for_xp(doc,xp),Progression.points_earned(doc,xp,known_firsts))
	if not problems.is_empty():_err("tree_rejected_detail","Tree investment failed validation: "+problems[0],{"detail":problems[0]});return false
	entry.ranks=next;entry.tree_revision=int(tree.revision)
	var table: Dictionary=characters.duplicate(true);table[character_id]=entry
	return _persist(state.duplicate(true),table)

## Essence cost of resetting this witch's tree now (essence_per_point * points spent).
func respec_cost(character_id: String) -> int:
	var per_point := respec_cost_override if respec_cost_override>=0 else int(progression_doc().get("respec",{}).get("essence_per_point",0))
	return per_point*SkillTree.points_spent(character_entry(character_id).ranks)

## Full reset of the committed tree. Refused when nothing is invested or the essence is short.
func respec(character_id: String) -> bool:
	if not available:return false
	var known := Progression.character_entry(progression_doc(),character_id)
	if known.is_empty() or known.get("tree_id")==null:_err("tree_locked","This witch's skill tree is not open yet");return false
	var entry := character_entry(character_id)
	if entry.ranks.is_empty():_err("tree_nothing_to_undo","Nothing invested to undo");return false
	var cost := respec_cost(character_id)
	if int(state.essence)<cost:_err("essence_short","Not enough essence");return false
	var candidate: Dictionary=state.duplicate(true);candidate.essence=int(state.essence)-cost
	entry.ranks={};entry.respecs=int(entry.respecs)+1;entry.tree_revision=int(trees()[known.tree_id].revision)
	var table: Dictionary=characters.duplicate(true);table[character_id]=entry
	return _persist(candidate,table)
