extends RefCounted
## Product profile. The file on disk is schema 3 (user://chapter-one-profile-v3.json): the schema-2
## fields plus a per-witch "characters" table (xp, tree ranks, first-kill receipts).
## Schema-2 and schema-1 files are only ever read; they are carried into the v3 file on the first save
## and are never modified or deleted.
## In memory, `state` keeps the schema-2 shape (items, equipment, receipts...) and `characters` holds the
## v3 table, so equipment code is unchanged. Level and points are computed from xp, never stored.
const Loot=preload("res://chapter1/core/loot.gd")
const Catalog=preload("res://chapter1/core/growth_catalog.gd")
const Progression=preload("res://chapter1/core/character_progression.gd")
const SkillTree=preload("res://chapter1/core/skill_tree.gd")
const CAPACITY := 256
const MAX_ITEMS := 325 # One final69-item recovery batch; start blocked above256.
const PATH_V3 := "user://chapter-one-profile-v3.json"
const PATH_V2 := "user://chapter-one-profile-v2.json"
const PATH_V1 := "user://chapter-one-profile-v1.json"
const POINTER_PATH := "user://chapter-one-profile-active.json"
const FRESH_NAME_PATTERN := "^chapter-one-profile-v3-r[0-9-]+\\.json\\z"
## At most this many journal copies are read when looking for one to continue from (newest first).
const MAX_JOURNAL_SCAN := 64
const EQUIP_SLOTS := ["weapon","head","body","hands","feet","charm","ring","ring2"]
const TOP_KEYS := ["schema_version","revision","next_id","items","equipped","completed_runs","best_ticks","essence","receipts"]
const CHAR_KEYS := ["xp","tree_revision","ranks","first_rewards","respecs"]
const ITEM_KEYS := ["base_id","name","slot","stats","quality","item_level","affixes","description"]
const ITEM_KEYS_V2 := ["grammar","required_level","legendary_id"]
const ESSENCE := {"common":1,"magic":3,"rare":8,"legendary":15,"unique":25}
static var _loot: RefCounted
static var _progression: Dictionary={}
static var _trees: Dictionary={}
var state: Dictionary={}
## {character_id: {xp, tree_revision, ranks, first_rewards, respecs}}; a witch appears after her first run.
var characters: Dictionary={}
## {character_id: true} when a tree revision change returned the ranks on read. Cleared by acknowledge_notice.
var notices: Dictionary={}
## Dev sentence of the last refusal. The screen words a refusal from `error_code` and `error_args` (keys profile.error.<code>);
## assigning `error` directly clears the code, so only _err() sets both.
var error := "":
	set(value):
		error=value;error_code="";error_args={}
var error_code := ""
var error_args: Dictionary={}
var path := ""
var _loaded_text := ""
var available := false
## Why the last configure() refused a file: "" when it did not. Kinds: "damaged" (JSON or size),
## "incompatible" (well-formed but failed validation), "legacy" (a schema-2/1 file was refused).
var reject_kind := ""
var reject_reason := ""
## The file that was actually refused (the schema-3 path, or the old-format file for "legacy"). Read-only for callers.
var reject_source := ""
## Where the pointer file lives ("" = none). The product uses POINTER_PATH; QA passes an isolated path.
var pointer_path := ""
## The newest readable journal copy, computed once when a v3 file is refused (see _reject).
var _resume := {}
## Test hook: when set (digits and dashes only), replaces the time stamp in a new save's file name.
var stamp_override := ""
## True until the first save after reading a schema-1 / schema-2 file.
var imported_from_v1 := false
var imported_from_v2 := false
## Test hook: when >= 0 replaces respec.essence_per_point from the data.
var respec_cost_override := -1

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
		if tables.load_file():_loot=tables
		else:push_error("Loot tables failed to load: "+str(tables.errors))
	return _loot

static func fresh() -> Dictionary:
	return {"schema_version":2,"revision":0,"next_id":1,"items":[],"equipped":{},"completed_runs":0,"best_ticks":0,"essence":0,"receipts":[]}

## Reads `destination` (schema 3). When it does not exist, reads the schema-2 file, then the schema-1 file, into
## memory only. In QA mode the legacy paths are optional arguments and must be isolated QA paths too.
func configure(destination: String=PATH_V3,qa: bool=false,legacy_v2: String="",legacy_v1: String="",pointer: String="") -> bool:
	reject_source="";available=false;error="";reject_kind="";reject_reason="";_resume={};state=fresh();characters={};notices={};path=destination;_loaded_text="";imported_from_v1=false;imported_from_v2=false;pointer_path=""
	if qa:
		var base := "res://_local/"
		for candidate_path in [path,legacy_v2,legacy_v1,pointer]:
			if String(candidate_path).is_empty():continue
			if not String(candidate_path).begins_with(base) or not String(candidate_path).ends_with(".json"):_err("isolated_path_invalid","Invalid isolated QA profile path");return false
		pointer_path=pointer
	else:
		if destination!=PATH_V3 or not ProjectSettings.get_setting("application/config/use_custom_user_dir",false) or not String(ProjectSettings.get_setting("application/config/custom_user_dir_name","")).begins_with("WitchMoira"):
			_err("preview_only","전용 저장 경로가 없는 미리보기입니다");return false
		legacy_v2=PATH_V2;legacy_v1=PATH_V1;pointer_path=POINTER_PATH
	path=_pointed(destination)
	if FileAccess.file_exists(path):
		_loaded_text=FileAccess.get_file_as_string(path)
		if _loaded_text.length()>2000000:_err("profile_too_large","Profile exceeds bound");return _reject("damaged","size",path)
		var parser := JSON.new()
		if parser.parse(_loaded_text)!=OK:_err("file_rejected","저장 파일 검증 실패 · 원본 보존");return _reject("damaged","json",path)
		var seen := {}
		var why := []
		var normalized := normalize_v3(parser.data,false,seen,why)
		if normalized.is_empty():_err("file_rejected","저장 파일 검증 실패 · 원본 보존");return _reject("incompatible",String(why[0]) if not why.is_empty() else "schema 3 document",path)
		_adopt(normalized);notices=seen
	elif not legacy_v2.is_empty() and FileAccess.file_exists(legacy_v2):
		if not import_v2_text(FileAccess.get_file_as_string(legacy_v2)):return _reject("legacy",reject_reason,legacy_v2)
	elif not legacy_v1.is_empty() and FileAccess.file_exists(legacy_v1):
		if not import_v1_text(FileAccess.get_file_as_string(legacy_v1)):return _reject("legacy",reject_reason,legacy_v1)
	available=true;return true

## The file the pointer names, when the pointer is well formed and names an existing file directly beside
## `destination` with the fresh-save naming rule. Anything else (a path, "..", another pattern, a missing file)
## is ignored and `destination` is used. The pointer is only read here.
func _pointed(destination: String) -> String:
	if pointer_path.is_empty() or not FileAccess.file_exists(pointer_path):return destination
	var text := FileAccess.get_file_as_string(pointer_path)
	if text.length()>4096:return destination
	var parser := JSON.new()
	if parser.parse(text)!=OK or not parser.data is Dictionary or not parser.data.get("file") is String:return destination
	var file: String=parser.data.file
	if RegEx.create_from_string(FRESH_NAME_PATTERN).search(file)==null:return destination
	var target := _sibling(destination,file)
	return target if FileAccess.file_exists(target) else destination

static func _sibling(file_path: String,file_name: String) -> String:
	var folder := file_path.get_base_dir()
	return folder+file_name if folder.ends_with("/") else folder+"/"+file_name

## Journal copies (`<file>.revision-*.json`) beside the current file, newest revision first: [{file, number}].
func journal_files() -> Array:
	var rows := []
	var dir := DirAccess.open(path.get_base_dir())
	if dir==null:return rows
	var prefix := path.get_file().get_basename()+".revision-"
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if not dir.current_is_dir() and entry.begins_with(prefix) and entry.ends_with(".json"):
			rows.append({"file":entry,"number":int(entry.trim_prefix(prefix).get_slice("-",0))})
		entry=dir.get_next()
	dir.list_dir_end()
	rows.sort_custom(func(a,b):return int(a.number)>int(b.number) or (int(a.number)==int(b.number) and String(a.file)>String(b.file)))
	return rows

## The newest journal copy the current rules can read: {file, revision, unix, state} or {}. Reads only.
func latest_readable_revision() -> Dictionary:
	var scanned := 0
	for row in journal_files():
		scanned+=1
		if scanned>MAX_JOURNAL_SCAN:break
		var full := _sibling(path,String(row.file))
		var text := FileAccess.get_file_as_string(full)
		if text.length()>2000000:continue
		var parser := JSON.new()
		if parser.parse(text)!=OK:continue
		var read := normalize_v3(parser.data,false)
		if not read.is_empty():return {"file":row.file,"revision":int(read.revision),"unix":int(FileAccess.get_modified_time(full)),"state":read}
	return {}

## After a refusal: begin a new save without touching the refused file or its journal copies.
## - v3 file refused: a new file `chapter-one-profile-v3-r<YYYYMMDD-HHMMSS>[-n].json` beside it (never an existing
##   name), from the newest readable journal copy when use_revision, else empty; then the pointer file names it.
## - only a schema-2/1 file refused (no v3 file exists): an empty v3 at the normal path; no pointer.
## Returns false and leaves the refused state as it was when anything fails.
## {file, revision, unix} of the journal copy a new save would continue from, or {}. Cached; no disk access.
func resume_info() -> Dictionary:
	if _resume.is_empty():return {}
	return {"file":_resume.file,"revision":_resume.revision,"unix":_resume.unix}

func _err(code: String,text: String,args: Dictionary={}) -> void:
	error=text;error_code=code;error_args=args

func start_fresh_after_reject(use_revision: bool=true) -> bool:
	if available or reject_kind.is_empty():_err("fresh_unavailable","새 저장을 시작할 수 없는 상태입니다");return false
	var refused_path := path;var refused_kind := reject_kind;var refused_reason := reject_reason;var refused_error := error;var refused_code := error_code;var refused_args := error_args
	var target := path;var from_revision := "";var next_state := fresh();var next_characters := {}
	if refused_kind=="legacy":
		if FileAccess.file_exists(target):_err("fresh_name_taken","새 저장 파일 이름이 이미 있습니다");return false
	else:
		if pointer_path.is_empty():_err("pointer_path_missing","가리키는 파일 경로가 없습니다");return false
		var stamp_time := Time.get_datetime_dict_from_system()
		var stamp := "%04d%02d%02d-%02d%02d%02d"%[stamp_time.year,stamp_time.month,stamp_time.day,stamp_time.hour,stamp_time.minute,stamp_time.second]
		if not stamp_override.is_empty():stamp=stamp_override
		var number := 1
		target=_sibling(refused_path,"chapter-one-profile-v3-r"+stamp+".json")
		while FileAccess.file_exists(target):
			number+=1;target=_sibling(refused_path,"chapter-one-profile-v3-r"+stamp+"-"+str(number)+".json")
		if use_revision:
			var latest: Dictionary=_resume
			if not latest.is_empty():
				next_state=latest.state.duplicate(true);next_state.erase("characters");next_state.schema_version=2
				next_characters=latest.state.characters.duplicate(true);from_revision=String(latest.file)
	state=next_state;characters=next_characters;path=target;_loaded_text="";available=true;error=""
	var written := _persist(state.duplicate(true))
	if written and refused_kind!="legacy":written=_write_pointer(target.get_file(),refused_path.get_file(),refused_kind,refused_reason,from_revision)
	if not written:
		var why := error;var why_code := error_code;var why_args := error_args
		available=false;state=fresh();characters={};path=refused_path;_loaded_text="";error=why if not why.is_empty() else refused_error
		error_code=why_code if not why.is_empty() else refused_code;error_args=why_args if not why.is_empty() else refused_args
		return false
	reject_kind="";reject_reason=""
	return true

func _write_pointer(file: String,replaces: String,kind: String,reason: String,from_revision: String) -> bool:
	var doc := {"schema":1,"file":file,"replaces":replaces,"kind":kind,"reason":reason,"created_unix":int(Time.get_unix_time_from_system()),"from_revision":from_revision}
	var text := JSON.stringify(doc,"  ")
	var temporary := pointer_path.get_basename()+".next-%d.json"%Time.get_ticks_usec()
	var handle := FileAccess.open(temporary,FileAccess.WRITE)
	if handle==null:_err("pointer_create_failed","가리키는 파일 생성 실패");return false
	handle.store_string(text);handle.flush();var status := handle.get_error();handle.close()
	if status!=OK or FileAccess.get_file_as_string(temporary)!=text:_err("pointer_write_failed","가리키는 파일 쓰기 검증 실패");return false
	if DirAccess.rename_absolute(temporary,pointer_path)!=OK:_err("pointer_replace_failed","가리키는 파일 교체 실패");return false
	return true

## Records why a file was refused and writes one log line. Writes no file and changes nothing on disk.
## The line holds the file name only (no user path) and no item names.
func _reject(kind: String,reason: String,source: String) -> bool:
	reject_kind=kind;reject_reason=reason;reject_source=source
	_resume=latest_readable_revision() if kind!="legacy" else {}
	var text := FileAccess.get_file_as_string(source) if FileAccess.file_exists(source) else ""
	print("CHAPTER1_PROFILE_REJECTED ",JSON.stringify({"file":source.get_file(),"kind":kind,"reason":reason,"bytes":text.to_utf8_buffer().size(),"sha256_16":text.sha256_text().substr(0,16)}))
	return false

func _adopt(v3: Dictionary) -> void:
	state=v3.duplicate(true);state.erase("characters");state.schema_version=2
	characters=v3.characters.duplicate(true)

## Read a schema-2 profile into memory. Nothing is written until the next save,
## and that save goes to this profile's own (schema-3) path.
func import_v2_text(text: String) -> bool:
	if text.length()>2000000:_err("old_too_large","이전 저장 파일이 너무 큽니다 · 원본 보존");reject_reason="size";return false
	var parser := JSON.new()
	if parser.parse(text)!=OK:_err("old_rejected","이전 저장 파일 검증 실패 · 원본 보존");reject_reason="json";return false
	var why := []
	var upgraded := normalize(parser.data,why)
	if upgraded.is_empty():_err("old_rejected","이전 저장 파일 검증 실패 · 원본 보존");reject_reason=String(why[0]);return false
	state=upgraded;characters=migrated_characters(state);imported_from_v2=true
	return true

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

## Read a schema-1 profile into memory. Nothing is written until the next save,
## and that save goes to this profile's own path.
func import_v1_text(text: String) -> bool:
	if text.length()>2000000:_err("old_too_large","이전 저장 파일이 너무 큽니다 · 원본 보존");reject_reason="size";return false
	var parser := JSON.new()
	if parser.parse(text)!=OK:_err("old_rejected","이전 저장 파일 검증 실패 · 원본 보존");reject_reason="json";return false
	var upgraded := upgrade_v1(parser.data)
	if upgraded.is_empty():_err("old_rejected","이전 저장 파일 검증 실패 · 원본 보존");reject_reason="schema 1 document";return false
	state=upgraded;characters=migrated_characters(state);imported_from_v1=true
	return true

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

## `reasons_out` (optional) receives a short reason when the document is rejected; the return value is unchanged.
static func normalize(value: Variant,reasons_out: Array=[]) -> Dictionary:
	var rejected := _normalize_body(value,reasons_out)
	if rejected.is_empty() and reasons_out.is_empty():reasons_out.append("profile fields")
	return rejected

static func _normalize_body(value: Variant,reasons_out: Array) -> Dictionary:
	if not value is Dictionary or not Catalog.keys_match(value,TOP_KEYS):return {}
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
		if not item.stats is Dictionary or not item.affixes is Array:return {}
		if not item.name is String or item.name.length()>160 or not item.base_id is String or item.base_id.length()>100 or not item.description is String or item.description.length()>300:return {}
		if not item.slot is String or not item.quality is String:return {}
		if not Catalog.integer(item.item_level,1,30):return {}
		item.item_level=int(item.item_level)
		if item.has("grammar"):
			if not Catalog.integer(item.grammar,2,2) or not Catalog.integer(item.required_level,1,30):return {}
			item.grammar=int(item.grammar);item.required_level=int(item.required_level)
			if item.has("legendary_id") and (not item.legendary_id is String or item.legendary_id.length()>60):return {}
		for stat in item.stats:
			if not Catalog.integer(item.stats[stat],-1000000,1000000):return {}
			item.stats[stat]=int(item.stats[stat])
		for affix in item.affixes:
			if not affix is Dictionary or not Catalog.keys_match(affix,["id","group","stat","value"]) or not Catalog.integer(affix.value,0,1000000):return {}
			affix.value=int(affix.value)
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

## Schema-3 document: the schema-2 fields (with schema_version 3) plus `characters`.
## strict=true is the write rule: any violation, including a tree_revision that differs from the data, rejects.
## strict=false is the read rule: only a tree_revision mismatch is tolerated; the ranks are returned (emptied) and
## the witch is listed in `notices`. Every other violation rejects the whole file.
static func normalize_v3(value: Variant,strict: bool=true,notices_out: Dictionary={},reasons_out: Array=[]) -> Dictionary:
	var accepted := _normalize_v3_body(value,strict,notices_out,reasons_out)
	if accepted.is_empty() and reasons_out.is_empty():reasons_out.append("schema 3 document")
	return accepted

static func _normalize_v3_body(value: Variant,strict: bool,notices_out: Dictionary,reasons_out: Array) -> Dictionary:
	if not value is Dictionary or not Catalog.keys_match(value,TOP_KEYS+["characters"]):return {}
	if not Catalog.integer(value.schema_version,3,3) or not value.characters is Dictionary or value.characters.size()>3:return {}
	var view: Dictionary=value.duplicate(true);var raw: Dictionary=view.characters
	view.erase("characters");view.schema_version=2
	var result := normalize(view,reasons_out)
	if result.is_empty():return {}
	var doc := progression_doc();var table := trees()
	if doc.is_empty() or table.is_empty():return {}
	var cleaned := {}
	for id_ in raw:
		var known: Dictionary=Progression.character_entry(doc,String(id_)) if id_ is String else {}
		var entry: Variant=raw[id_]
		if known.is_empty() or not entry is Dictionary or not Catalog.keys_match(entry,CHAR_KEYS):return {}
		if not Catalog.integer(entry.xp,0,1000000000) or not Catalog.integer(entry.tree_revision,0,1000000) or not Catalog.integer(entry.respecs,0,1000000000):return {}
		if not entry.ranks is Dictionary or not entry.first_rewards is Array or entry.first_rewards.size()>32:return {}
		var firsts: Array=[]
		for reward in entry.first_rewards:
			if not reward is String or not doc.first_rewards.has(reward) or reward in firsts:return {}
			firsts.append(reward)
		var ranks := {}
		for node_id in entry.ranks:
			if not node_id is String or not Catalog.integer(entry.ranks[node_id],1,10):return {}
			ranks[node_id]=int(entry.ranks[node_id])
		var xp := int(entry.xp);var revision := int(entry.tree_revision)
		if known.get("tree_id")==null:
			if revision!=0 or not ranks.is_empty():return {}
		else:
			if not table.has(known.tree_id):return {}
			var tree: Dictionary=table[known.tree_id]
			if revision==0 and not ranks.is_empty():return {}
			if revision!=0 and revision!=int(tree.revision):
				if strict:return {}
				if not ranks.is_empty():notices_out[id_]=true
				ranks={};revision=int(tree.revision)
			if not SkillTree.legal_ranks(tree,ranks,Progression.level_for_xp(doc,xp),Progression.points_earned(doc,xp,firsts)).is_empty():return {}
		cleaned[id_]={"xp":xp,"tree_revision":revision,"ranks":ranks,"first_rewards":firsts,"respecs":int(entry.respecs)}
	result.schema_version=3;result.characters=cleaned
	return result

## Validates a run's progress and returns the new characters table, or {"error": reason}. Pure: used by
## record_run and by simulations that keep the profile in memory.
## progress = {character_id, xp_gained, first_kills: [reward id...]} (other keys of progress_summary are ignored).
static func apply_progress(current: Dictionary,progress: Dictionary) -> Dictionary:
	var doc := progression_doc();var table := trees()
	if doc.is_empty() or table.is_empty():return {"error":"성장 데이터를 읽지 못했습니다","code":"growth_data_missing"}
	var id_: Variant=progress.get("character_id")
	var known: Dictionary=Progression.character_entry(doc,id_) if id_ is String else {}
	if known.is_empty():return {"error":"알 수 없는 캐릭터","code":"unknown_character"}
	if not Catalog.integer(progress.get("xp_gained"),0,int(Progression.xp_bounds(doc).run_xp_max)):return {"error":"경험치 범위 밖","code":"xp_out_of_range"}
	if not progress.get("first_kills",[]) is Array:return {"error":"첫 처치 형식 오류","code":"first_kills_format"}
	for reward in progress.get("first_kills",[]):
		if not reward is String or not doc.first_rewards.has(reward):return {"error":"알 수 없는 첫 처치 id","code":"first_kill_unknown"}
	var result: Dictionary=current.duplicate(true)
	var entry: Dictionary=result.get(id_,{"xp":0,"tree_revision":int(table[known.tree_id].revision) if known.get("tree_id")!=null and table.has(known.tree_id) else 0,"ranks":{},"first_rewards":[],"respecs":0})
	entry.xp=mini(1000000000,int(entry.xp)+int(progress.xp_gained))
	for reward in progress.get("first_kills",[]):
		if not reward in entry.first_rewards:entry.first_rewards.append(reward)
	result[id_]=entry
	return result

func _persist(candidate: Dictionary,next_characters: Variant=null) -> bool:
	if not available:_err("save_path_unverified","저장 경로 검증이 필요합니다");return false
	candidate=candidate.duplicate(true);candidate.revision=int(state.revision)+1
	var normalized := normalize(candidate)
	if normalized.is_empty():_err("save_candidate_rejected","저장 후보 검증 실패");return false
	var document := normalized.duplicate(true);document.schema_version=3
	document.characters=(characters if next_characters==null else next_characters).duplicate(true)
	var v3 := normalize_v3(document,true)
	if v3.is_empty():_err("save_candidate_rejected","저장 후보 검증 실패");return false
	if FileAccess.file_exists(path):
		if FileAccess.get_file_as_string(path)!=_loaded_text:_err("save_changed_elsewhere","다른 실행에서 저장이 변경됐습니다 · 기존 파일 보존");return false
	elif not _loaded_text.is_empty():_err("save_moved","저장 파일이 외부에서 이동됐습니다");return false
	var text := JSON.stringify(v3,"  ")
	var stamp := "%06d-%d-%d"%[normalized.revision,OS.get_process_id(),Time.get_ticks_usec()]
	var journal := path.get_basename()+".revision-"+stamp+".json"
	var temporary := path.get_basename()+".next-"+stamp+".json"
	if FileAccess.file_exists(journal) or FileAccess.file_exists(temporary):_err("save_name_conflict","저장 파일 이름 충돌");return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	for target in [journal,temporary]:
		var file := FileAccess.open(target,FileAccess.WRITE)
		if file==null:_err("save_create_failed","저장 파일 생성 실패");return false
		file.store_string(text);file.flush();var status := file.get_error();file.close()
		if status!=OK or FileAccess.get_file_as_string(target)!=text:_err("save_write_failed","저장 쓰기 검증 실패");return false
	# The immutable revision remains if replacement fails. No historic backup is deleted.
	var rename := DirAccess.rename_absolute(temporary,path)
	if rename!=OK:_err("save_replace_failed","저장 교체 실패 · 이전 파일과 새 revision 보존");return false
	if FileAccess.get_file_as_string(path)!=text:_err("save_replace_verify_failed","저장 교체 검증 실패");return false
	_adopt(v3);_loaded_text=text;error="";imported_from_v1=false;imported_from_v2=false;return true

## One atomic write holds the equipment, the receipt, the experience and the first kills of the run.
## A receipt already recorded changes nothing (no second payout). `progress` is optional; see apply_progress.
func record_run(receipt: String,inventory: Array,pending: Array,victory: bool,ticks: int,progress: Dictionary={}) -> bool:
	if not available:return false
	if receipt in state.receipts:return true
	if receipt.length()<1 or receipt.length()>120 or inventory.size()>65 or pending.size()>4 or ticks<0:return false
	var next_characters: Variant=null
	if not progress.is_empty():
		var applied := apply_progress(characters,progress)
		if applied.has("error"):_err(String(applied.get("code","progress_rejected")),String(applied.error));return false
		next_characters=applied
	var candidate: Dictionary=state.duplicate(true)
	for source in inventory+pending:
		if source.has("storage_id"):continue
		var clean := {}
		for key in ITEM_KEYS+ITEM_KEYS_V2:
			if source.has(key):clean[key]=source[key]
		if not loot().validate(clean).is_empty():_err("reward_rejected","보상 장비 검증 실패");return false
		candidate.items.append({"storage_id":int(candidate.next_id),"item":clean.duplicate(true)});candidate.next_id+=1
	if candidate.items.size()>MAX_ITEMS:_err("stash_full","장비 보관 공간이 부족합니다");return false
	candidate.receipts.append(receipt)
	if candidate.receipts.size()>64:candidate.receipts.pop_front()
	if victory:
		candidate.completed_runs+=1
		if candidate.best_ticks==0 or ticks<candidate.best_ticks:candidate.best_ticks=ticks
	return _persist(candidate,next_characters)

## Which equip slot holds this stored item, or "" when it is not selected.
func equip_slot_of(storage_id: int) -> String:
	for slot in state.get("equipped",{}):
		if int(state.equipped[slot])==storage_id:return slot
	return ""

## Level an item needs: its own required_level (grammar v2), or item_level - 3 for older items.
static func required_level_of(item: Dictionary) -> int:
	return int(item.get("required_level",maxi(1,int(item.get("item_level",1))-3)))

## Select an item for the starting kit. With a character id, an item above that witch's level is refused.
func select_item(storage_id: int,character_id: String="") -> bool:
	if not equip_slot_of(storage_id).is_empty():return true
	var candidate: Dictionary=state.duplicate(true)
	for record in candidate.items:
		if record.storage_id==storage_id:
			if not character_id.is_empty() and required_level_of(record.item)>character_level(character_id):
				_err("level_required","Lv %d 필요"%required_level_of(record.item),{"n":required_level_of(record.item)});return false
			var slot: String=record.item.slot
			# A ring takes the first free ring slot, otherwise it replaces the first ring.
			if slot=="ring" and candidate.equipped.has("ring") and not candidate.equipped.has("ring2"):slot="ring2"
			candidate.equipped[slot]=storage_id;return _persist(candidate)
	return false

func unselect(slot: String) -> bool:
	if not state.get("equipped",{}).has(slot):return false
	var candidate: Dictionary=state.duplicate(true)
	candidate.equipped.erase(slot)
	return _persist(candidate)

func salvage(storage_id: int) -> bool:
	var candidate: Dictionary=state.duplicate(true);var index := -1
	for i in candidate.items.size():
		if candidate.items[i].storage_id==storage_id:index=i;break
	if index<0:return false
	var item: Dictionary=candidate.items[index].item
	for slot in candidate.equipped.keys():
		if int(candidate.equipped[slot])==storage_id:candidate.equipped.erase(slot)
	candidate.items.remove_at(index);candidate.essence=mini(1000000000,int(candidate.essence)+int(ESSENCE.get(item.quality,1)))
	return _persist(candidate)

## The selected kit. With a character id, pieces above that witch's level stay selected but are left behind.
func starting_gear(character_id: String="") -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var equipped: Dictionary=state.get("equipped",{})
	var level := character_level(character_id) if not character_id.is_empty() else 1000
	for slot in EQUIP_SLOTS:
		if not equipped.has(slot):continue
		for record in state.get("items",[]):
			if int(record.storage_id)==int(equipped[slot]) and required_level_of(record.item)<=level:
				var item: Dictionary=record.item.duplicate(true);item.storage_id=record.storage_id;item.equip_slot=slot;result.append(item)
	return result

## Selected pieces this witch is too low-level to take along: [{storage_id, slot, required_level}].
func blocked_gear(character_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var level := character_level(character_id)
	var equipped: Dictionary=state.get("equipped",{})
	for slot in EQUIP_SLOTS:
		if not equipped.has(slot):continue
		for record in state.get("items",[]):
			if int(record.storage_id)==int(equipped[slot]) and required_level_of(record.item)>level:
				result.append({"storage_id":int(record.storage_id),"slot":slot,"required_level":required_level_of(record.item)})
	return result

# ---------------------------------------------------------------- permanent growth (schema 3)

## The stored entry, or a default one (xp 0, no ranks) for a witch that has not finished a run yet.
func character_entry(character_id: String) -> Dictionary:
	if characters.has(character_id):return characters[character_id].duplicate(true)
	var doc := progression_doc();var known := Progression.character_entry(doc,character_id)
	var revision := 0
	if not known.is_empty() and known.get("tree_id")!=null and trees().has(known.tree_id):revision=int(trees()[known.tree_id].revision)
	return {"xp":0,"tree_revision":revision,"ranks":{},"first_rewards":[],"respecs":0}

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
	if known.is_empty() or known.get("tree_id")==null or not trees().has(known.tree_id):_err("tree_locked","이 마녀의 스킬 트리는 아직 열리지 않았습니다");return false
	var tree: Dictionary=trees()[known.tree_id];var entry := character_entry(character_id)
	var next := {}
	for node_id in ranks:
		if not node_id is String or not Catalog.integer(ranks[node_id],1,10):_err("tree_rejected","트리 투자 검증 실패");return false
		next[node_id]=int(ranks[node_id])
	for node_id in entry.ranks:
		if int(next.get(node_id,0))<int(entry.ranks[node_id]):_err("tree_confirmed","확정한 투자는 전체 초기화로만 되돌립니다");return false
	var xp := int(entry.xp)
	var problems := SkillTree.legal_ranks(tree,next,Progression.level_for_xp(doc,xp),Progression.points_earned(doc,xp,entry.first_rewards))
	if not problems.is_empty():_err("tree_rejected_detail","트리 투자 검증 실패 · "+problems[0],{"detail":problems[0]});return false
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
	if known.is_empty() or known.get("tree_id")==null:_err("tree_locked","이 마녀의 스킬 트리는 아직 열리지 않았습니다");return false
	var entry := character_entry(character_id)
	if entry.ranks.is_empty():_err("tree_nothing_to_undo","되돌릴 투자가 없습니다");return false
	var cost := respec_cost(character_id)
	if int(state.essence)<cost:_err("essence_short","재가 모자랍니다");return false
	var candidate: Dictionary=state.duplicate(true);candidate.essence=int(state.essence)-cost
	entry.ranks={};entry.respecs=int(entry.respecs)+1;entry.tree_revision=int(trees()[known.tree_id].revision)
	var table: Dictionary=characters.duplicate(true);table[character_id]=entry
	return _persist(candidate,table)
