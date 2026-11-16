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
var error := ""
var path := ""
var _loaded_text := ""
var available := false
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
func configure(destination: String=PATH_V3,qa: bool=false,legacy_v2: String="",legacy_v1: String="") -> bool:
	available=false;error="";state=fresh();characters={};notices={};path=destination;_loaded_text="";imported_from_v1=false;imported_from_v2=false
	if qa:
		var base := "res://_local/"
		for candidate_path in [path,legacy_v2,legacy_v1]:
			if String(candidate_path).is_empty():continue
			if not String(candidate_path).begins_with(base) or not String(candidate_path).ends_with(".json"):error="Invalid isolated QA profile path";return false
	else:
		if destination!=PATH_V3 or not ProjectSettings.get_setting("application/config/use_custom_user_dir",false) or not String(ProjectSettings.get_setting("application/config/custom_user_dir_name","")).begins_with("WitchMoira"):
			error="전용 저장 경로가 없는 미리보기입니다";return false
		legacy_v2=PATH_V2;legacy_v1=PATH_V1
	if FileAccess.file_exists(path):
		_loaded_text=FileAccess.get_file_as_string(path)
		if _loaded_text.length()>2000000:error="Profile exceeds bound";return false
		var parser := JSON.new()
		if parser.parse(_loaded_text)!=OK:error="저장 파일 검증 실패 · 원본 보존";return false
		var seen := {}
		var normalized := normalize_v3(parser.data,false,seen)
		if normalized.is_empty():error="저장 파일 검증 실패 · 원본 보존";return false
		_adopt(normalized);notices=seen
	elif not legacy_v2.is_empty() and FileAccess.file_exists(legacy_v2):
		if not import_v2_text(FileAccess.get_file_as_string(legacy_v2)):return false
	elif not legacy_v1.is_empty() and FileAccess.file_exists(legacy_v1):
		if not import_v1_text(FileAccess.get_file_as_string(legacy_v1)):return false
	available=true;return true

func _adopt(v3: Dictionary) -> void:
	state=v3.duplicate(true);state.erase("characters");state.schema_version=2
	characters=v3.characters.duplicate(true)

## Read a schema-2 profile into memory. Nothing is written until the next save,
## and that save goes to this profile's own (schema-3) path.
func import_v2_text(text: String) -> bool:
	if text.length()>2000000:error="이전 저장 파일이 너무 큽니다 · 원본 보존";return false
	var parser := JSON.new()
	if parser.parse(text)!=OK:error="이전 저장 파일 검증 실패 · 원본 보존";return false
	var upgraded := normalize(parser.data)
	if upgraded.is_empty():error="이전 저장 파일 검증 실패 · 원본 보존";return false
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
	if text.length()>2000000:error="이전 저장 파일이 너무 큽니다 · 원본 보존";return false
	var parser := JSON.new()
	if parser.parse(text)!=OK:error="이전 저장 파일 검증 실패 · 원본 보존";return false
	var upgraded := upgrade_v1(parser.data)
	if upgraded.is_empty():error="이전 저장 파일 검증 실패 · 원본 보존";return false
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

static func normalize(value: Variant) -> Dictionary:
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
		if not tables.validate(item).is_empty():return {}
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
static func normalize_v3(value: Variant,strict: bool=true,notices_out: Dictionary={}) -> Dictionary:
	if not value is Dictionary or not Catalog.keys_match(value,TOP_KEYS+["characters"]):return {}
	if not Catalog.integer(value.schema_version,3,3) or not value.characters is Dictionary or value.characters.size()>3:return {}
	var view: Dictionary=value.duplicate(true);var raw: Dictionary=view.characters
	view.erase("characters");view.schema_version=2
	var result := normalize(view)
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
	if doc.is_empty() or table.is_empty():return {"error":"성장 데이터를 읽지 못했습니다"}
	var id_: Variant=progress.get("character_id")
	var known: Dictionary=Progression.character_entry(doc,id_) if id_ is String else {}
	if known.is_empty():return {"error":"알 수 없는 캐릭터"}
	if not Catalog.integer(progress.get("xp_gained"),0,int(Progression.xp_bounds(doc).run_xp_max)):return {"error":"경험치 범위 밖"}
	if not progress.get("first_kills",[]) is Array:return {"error":"첫 처치 형식 오류"}
	for reward in progress.get("first_kills",[]):
		if not reward is String or not doc.first_rewards.has(reward):return {"error":"알 수 없는 첫 처치 id"}
	var result: Dictionary=current.duplicate(true)
	var entry: Dictionary=result.get(id_,{"xp":0,"tree_revision":int(table[known.tree_id].revision) if known.get("tree_id")!=null and table.has(known.tree_id) else 0,"ranks":{},"first_rewards":[],"respecs":0})
	entry.xp=mini(1000000000,int(entry.xp)+int(progress.xp_gained))
	for reward in progress.get("first_kills",[]):
		if not reward in entry.first_rewards:entry.first_rewards.append(reward)
	result[id_]=entry
	return result

func _persist(candidate: Dictionary,next_characters: Variant=null) -> bool:
	if not available:error="저장 경로 검증이 필요합니다";return false
	candidate=candidate.duplicate(true);candidate.revision=int(state.revision)+1
	var normalized := normalize(candidate)
	if normalized.is_empty():error="저장 후보 검증 실패";return false
	var document := normalized.duplicate(true);document.schema_version=3
	document.characters=(characters if next_characters==null else next_characters).duplicate(true)
	var v3 := normalize_v3(document,true)
	if v3.is_empty():error="저장 후보 검증 실패";return false
	if FileAccess.file_exists(path):
		if FileAccess.get_file_as_string(path)!=_loaded_text:error="다른 실행에서 저장이 변경됐습니다 · 기존 파일 보존";return false
	elif not _loaded_text.is_empty():error="저장 파일이 외부에서 이동됐습니다";return false
	var text := JSON.stringify(v3,"  ")
	var stamp := "%06d-%d-%d"%[normalized.revision,OS.get_process_id(),Time.get_ticks_usec()]
	var journal := path.get_basename()+".revision-"+stamp+".json"
	var temporary := path.get_basename()+".next-"+stamp+".json"
	if FileAccess.file_exists(journal) or FileAccess.file_exists(temporary):error="저장 파일 이름 충돌";return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	for target in [journal,temporary]:
		var file := FileAccess.open(target,FileAccess.WRITE)
		if file==null:error="저장 파일 생성 실패";return false
		file.store_string(text);file.flush();var status := file.get_error();file.close()
		if status!=OK or FileAccess.get_file_as_string(target)!=text:error="저장 쓰기 검증 실패";return false
	# The immutable revision remains if replacement fails. No historic backup is deleted.
	var rename := DirAccess.rename_absolute(temporary,path)
	if rename!=OK:error="저장 교체 실패 · 이전 파일과 새 revision 보존";return false
	if FileAccess.get_file_as_string(path)!=text:error="저장 교체 검증 실패";return false
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
		if applied.has("error"):error=String(applied.error);return false
		next_characters=applied
	var candidate: Dictionary=state.duplicate(true)
	for source in inventory+pending:
		if source.has("storage_id"):continue
		var clean := {}
		for key in ITEM_KEYS+ITEM_KEYS_V2:
			if source.has(key):clean[key]=source[key]
		if not loot().validate(clean).is_empty():error="보상 장비 검증 실패";return false
		candidate.items.append({"storage_id":int(candidate.next_id),"item":clean.duplicate(true)});candidate.next_id+=1
	if candidate.items.size()>MAX_ITEMS:error="장비 보관 공간이 부족합니다";return false
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
				error="Lv %d 필요"%required_level_of(record.item);return false
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
	if known.is_empty() or known.get("tree_id")==null or not trees().has(known.tree_id):error="이 마녀의 스킬 트리는 아직 열리지 않았습니다";return false
	var tree: Dictionary=trees()[known.tree_id];var entry := character_entry(character_id)
	var next := {}
	for node_id in ranks:
		if not node_id is String or not Catalog.integer(ranks[node_id],1,10):error="트리 투자 검증 실패";return false
		next[node_id]=int(ranks[node_id])
	for node_id in entry.ranks:
		if int(next.get(node_id,0))<int(entry.ranks[node_id]):error="확정한 투자는 전체 초기화로만 되돌립니다";return false
	var xp := int(entry.xp)
	var problems := SkillTree.legal_ranks(tree,next,Progression.level_for_xp(doc,xp),Progression.points_earned(doc,xp,entry.first_rewards))
	if not problems.is_empty():error="트리 투자 검증 실패 · "+problems[0];return false
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
	if known.is_empty() or known.get("tree_id")==null:error="이 마녀의 스킬 트리는 아직 열리지 않았습니다";return false
	var entry := character_entry(character_id)
	if entry.ranks.is_empty():error="되돌릴 투자가 없습니다";return false
	var cost := respec_cost(character_id)
	if int(state.essence)<cost:error="재가 모자랍니다";return false
	var candidate: Dictionary=state.duplicate(true);candidate.essence=int(state.essence)-cost
	entry.ranks={};entry.respecs=int(entry.respecs)+1;entry.tree_revision=int(trees()[known.tree_id].revision)
	var table: Dictionary=characters.duplicate(true);table[character_id]=entry
	return _persist(candidate,table)
