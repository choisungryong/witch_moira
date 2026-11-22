extends SceneTree
## T6-S1 checks V5-1 .. V5-21 for the schema-5 profile (docs/specs/T6-save-schema5-directives-20261119.ko.md, 9.2).
## Everything runs on isolated paths under res://_local/. The frozen schema-4/3/2/1 files are only copied from.
## V5-4 (the S0 schema-4 set read as a source) is carried by test_profile_v4_fixtures.gd and V5-5 (schema 3/2/1) by
## test_profile_legacy_fixtures.gd; this file adds the cross-check V5-13 over all of them.
## Every message starts with its V5 number, and the result line counts the checks per number.
## Marker: CHAPTER1_PROFILE_V5_RESULT. `--write-compat` writes fixtures/profile_v5_compat.json once (refuses when it exists).
const Profile=preload("res://chapter1/core/chapter_profile.gd")
const Snap4=preload("res://chapter1/tests/profile_v4_snapshot.gd")
const Snap3=preload("res://chapter1/tests/profile_legacy_snapshot.gd")
const F4 := "res://chapter1/tests/fixtures/profile_v4"
const F3 := "res://chapter1/tests/fixtures/profile_legacy"
const COMPAT4 := "res://chapter1/tests/fixtures/profile_v4_compat.json"
const COMPAT5 := "res://chapter1/tests/fixtures/profile_v5_compat.json"
const FROST := "chapter1.character.frost"
const EMBER := "chapter1.character.ember"
const ARC := "chapter1.character.arc"
const SWIM_1 := "chapter1.outfit.frost.swim_1"
## Ids the quest, place, purchase and card lists may hold while the data files do not exist yet (the test hook).
const KNOWN := {"quests":["q.one","q.two","q.three"],"places":["place.hall"],"purchases":["buy.potion"],"cards":["card.a","card.b"]}
var checks := 0
var failures: Array[String]=[]
var by_id := {}
## `--list` prints every check with its result (V5_CHECK lines) for the report.
var verbose := "--list" in OS.get_cmdline_user_args()
var work := "res://_local/profile-v5-check"
var strict_docs: Array=[]
var good_files: Array[String]=[]
## The V5 number the messages of fixed_case start with.
var case_tag := "V5-8"
var static_note: Array[String]=[]

func _initialize() -> void:call_deferred("execute")

func check(ok: bool,message: String) -> void:
	checks+=1
	if verbose:print("V5_CHECK ",("ok   " if ok else "FAIL ")+message)
	var tag := message.get_slice(" ",0)
	by_id[tag]=int(by_id.get(tag,0))+1
	if not ok:failures.append(message);push_error(message)

func write_text(file_path: String,text: String) -> void:
	DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())
	var f := FileAccess.open(file_path,FileAccess.WRITE);f.store_string(text);f.close()

func hashes(folder: String) -> Dictionary:
	var out := {}
	for rel in Snap4.list_files(folder):out[rel]=FileAccess.get_sha256(folder+"/"+rel)
	return out

## sha256 of every file of a v3/v4-era name below `folder` (they must never change).
func old_hashes(folder: String) -> Dictionary:
	var out := {}
	for rel in Snap4.list_files(folder):
		var name := String(rel).get_file()
		if not name.begins_with("chapter-one-profile-v5"):out[rel]=FileAccess.get_sha256(folder+"/"+rel)
	return out

func same_hashes(before: Dictionary,folder: String) -> bool:
	for rel in before:
		if not FileAccess.file_exists(folder+"/"+rel) or FileAccess.get_sha256(folder+"/"+rel)!=before[rel]:return false
	return true

func same(a: Variant,b: Variant) -> bool:
	return JSON.stringify(JSON.parse_string(JSON.stringify(a)))==JSON.stringify(JSON.parse_string(JSON.stringify(b)))

func paths_in(folder: String) -> Dictionary:
	return {"folder":folder,"v4":folder+"/"+Snap4.MAIN,"v4ptr":folder+"/"+Snap4.POINTER,"v5":folder+"/chapter-one-profile-v5.json","v5ptr":folder+"/chapter-one-profile-v5-active.json","v3":folder+"/"+Snap3.MAIN}

func stage_full(folder: String) -> Dictionary:
	Snap4.wipe_tree(folder)
	Snap4.copy_bytes(F4+"/v4_full.json",folder+"/"+Snap4.MAIN)
	return paths_in(folder)

func stage_compat(folder: String) -> Dictionary:
	Snap4.wipe_tree(folder)
	Snap4.copy_bytes(COMPAT4,folder+"/"+Snap4.MAIN)
	return paths_in(folder)

func stage_journals(folder: String,all: bool) -> Dictionary:
	Snap4.wipe_tree(folder)
	for rel in Snap4.list_files(F4+"/"+Snap4.JOURNAL_DIR):
		if all or rel==Snap4.MAIN or rel.begins_with("revisions/"):Snap4.copy_bytes(F4+"/"+Snap4.JOURNAL_DIR+"/"+rel,folder+"/"+rel)
	return paths_in(folder)

func open_v4(paths: Dictionary,with_pointer: bool=false,with_v3: bool=false) -> RefCounted:
	var profile=Profile.new()
	profile.configure(paths.v5,true,"","",paths.v5ptr,paths.v3 if with_v3 else "","",paths.v4,paths.v4ptr if with_pointer else "")
	return profile

func open_v5(target: String,pointer: String="") -> RefCounted:
	var profile=Profile.new()
	profile.configure(target,true,"","",pointer)
	return profile

## A healthy schema-5 file made by carrying v4_full over and saving twice. Returns {paths, text, profile}.
func make_base(folder: String) -> Dictionary:
	var paths := stage_full(folder)
	var profile=open_v4(paths)
	profile.wear_outfit(FROST,"")
	profile.wear_outfit(FROST,SWIM_1)
	return {"paths":paths,"text":FileAccess.get_file_as_string(paths.v5),"profile":profile}

func mutated(text: String,mutate: Callable) -> Dictionary:
	var doc: Dictionary=JSON.parse_string(text);mutate.call(doc)
	return doc

func core_last(ticks: int=18000,kills: int=120,victory: bool=true,grade: int=2,depth: String="d1") -> Dictionary:
	return {"depth":depth,"victory":victory,"ticks":ticks,"kills":kills,"elite_kills":6,"champion_kills":3,"boss_kill":victory,"grade":grade,"potions_used":4,"damage_taken":900,"xp_gained":600,"essence_gained":40,
		"items":{"drop":12,"chest":3},"skills":[{"id":"chapter1.skill.frost","got_tick":0,"got_level":1,"rank":3,"evolved":false,"damage":50000,"kills":80}]}

func open_last() -> Dictionary:
	var last := core_last()
	last["death_cause"]="swarm";last["ultimate_casts"]=3;last["reactions"]={"steam":1200};last.skills[0]["detonations"]=5
	return last

func stock_item(which: int=0) -> Dictionary:
	var tables=Profile.loot()
	var item: Dictionary
	if which==0:item=tables.make_unique("winter_heart",12)
	else:
		var rng := RandomNumberGenerator.new();rng.seed=70+which
		item=tables.roll_item(rng,6,"magic","weapon")
	item.erase("name");item.erase("description")
	return item

func rich_town() -> Dictionary:
	return {"unlocked":["place.hall"],"bought":["buy.potion"],"shop":{"seed":12345,"refreshed_run":3,"stock":[stock_item(0),stock_item(1)]},"luck":{"gamble_since_legendary":39,"forge_fails_in_row":2}}

func rich_quests() -> Dictionary:
	return {"active":["q.one"],"progress":{"q.one":4},"done":["q.two"],"claimed":["q.three"],"bounty_offer":[],"bounty_seed":777,"bounty_run":2,"repeat_claims":5}

## Schema-4 file carried over, then saved once with every new cell filled by hand (the S2 write functions do not exist yet).
func rich_profile(folder: String,from_compat: bool=false) -> RefCounted:
	var paths := stage_compat(folder) if from_compat else stage_full(folder)
	var profile=open_v4(paths)
	var candidate: Dictionary=profile.state.duplicate(true)
	candidate.town=rich_town()
	var table: Dictionary=profile.characters.duplicate(true)
	table[FROST].quests=rich_quests()
	table[FROST].records={"runs":6,"wins":2,"last":open_last(),"best":{"d1":{"ticks":17000,"grade":3,"kills":150}}}
	table[FROST].grace={"banned":["card.a"]}
	table[EMBER].records={"runs":1,"wins":0,"last":{},"best":{}}
	for record in candidate.items:
		if record.item.get("quality")=="magic":
			record.item["forge"]=3;record.item["rerolls"]=7;break
	check(profile._persist(candidate,table),"V5-14 the hand-filled profile passes the strict write rule and is saved (%s)"%profile.error)
	return profile

func hangul(text: String) -> bool:
	for i in text.length():
		var code := text.unicode_at(i)
		if (code>=0xAC00 and code<=0xD7A3) or (code>=0x3131 and code<=0x318E):return true
	return false

func text_problems(value: Variant,path_: String,out: Array) -> void:
	if value is Dictionary:
		for key in value:
			if hangul(str(key)) or str(key) in ["name","description","title","text"]:out.append(path_+"/"+str(key))
			if str(key)=="legacy_name" or str(key)=="raw":continue
			text_problems(value[key],path_+"/"+str(key),out)
	elif value is Array:
		for entry in value:text_problems(entry,path_+"[]",out)
	elif value is String and hangul(value):out.append(path_)

func execute() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains("/_local/appdata/"):
		print("CHAPTER1_PROFILE_V5_RESULT ",JSON.stringify({"checks":0,"failures":["user data dir is not isolated: refusing to run"]}));quit(1);return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--work-dir="):work=argument.trim_prefix("--work-dir=")
	if not work.begins_with("res://_local/") or ".." in work:
		print("CHAPTER1_PROFILE_V5_RESULT ",JSON.stringify({"checks":0,"failures":["work dir must be under res://_local/"]}));quit(1);return
	Snap4.wipe_tree(work) # a rerun starts from nothing: no file of an earlier run may change what is read
	var frozen_before := hashes(ProjectSettings.globalize_path(F4))
	var frozen3_before := hashes(ProjectSettings.globalize_path(F3))
	var compat4_before := FileAccess.get_sha256(COMPAT4)
	Profile.use_ids_for_test(KNOWN)
	v1_checks()
	v2_v3_checks()
	v6_checks()
	var base := make_base(work+"/base")
	v7_reject_checks(base)
	v8_fix_checks(base)
	v10_record_checks()
	v11_restore_check(base)
	v12_text_checks()
	v14_compat_checks()
	v15_newer_checks(base)
	v17_journal_checks()
	v18_forge_checks(base)
	v19_luck_checks()
	t9_pity_checks(base)
	v20_grace_checks(base)
	v21_last_checks(base)
	v9_strict_checks()
	v16_static_checks()
	v13_invariant_checks()
	check(hashes(ProjectSettings.globalize_path(F4))==frozen_before and hashes(ProjectSettings.globalize_path(F3))==frozen3_before and FileAccess.get_sha256(COMPAT4)==compat4_before,"V5-1 the frozen schema-4, 3, 2 and 1 files and the v4 compatibility file are byte for byte what they were")
	Profile.use_ids_for_test({})
	if "--negative" in OS.get_cmdline_user_args():check(false,"V5-0 Intentional checker failure")
	print("CHAPTER1_PROFILE_V5_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"by_id":by_id,"static_note":static_note}))
	quit(0 if failures.is_empty() else 1)

# V5-1 and V5-3: carrying a schema-4 file over reads only, the first save writes the v5 file, v4 files never change.
func v1_checks() -> void:
	var paths := stage_full(work+"/v1")
	var before := old_hashes(paths.folder);var all_before := hashes(paths.folder)
	var profile=open_v4(paths)
	check(profile.available and profile.imported_from_v4 and profile.path==paths.v5 and int(profile.state.schema_version)==5,"V5-1 schema 4 is read into memory as schema 5")
	check(not FileAccess.file_exists(paths.v5) and hashes(paths.folder)==all_before,"V5-1 reading creates no file and changes none")
	check(profile.state.town.luck.gamble_since_legendary==0 and profile.state.town.shop.stock.is_empty() and profile.characters[FROST].records.runs==0 and profile.characters[FROST].quests.active.is_empty() and profile.characters[FROST].grace.banned.is_empty(),"V5-1 the new cells start at their defaults")
	check(profile.wear_outfit(FROST,"") and FileAccess.file_exists(paths.v5) and not profile.imported_from_v4,"V5-1 the first save writes the v5 file")
	check(same_hashes(before,paths.folder),"V5-1 every schema-4 file is byte for byte as before the first save")
	var doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(paths.v5))
	check(int(doc.schema_version)==5 and int(doc.revision)==33 and doc.origin.from_schema==4 and doc.origin.from_file==Snap4.MAIN and int(doc.origin.from_revision)==32 and int(doc.origin.at_unix)>0,"V5-1 the carry-over record names the schema-4 file and its revision; the revision continues")
	check(DirAccess.dir_exists_absolute(paths.folder+"/revisions") and not FileAccess.file_exists(paths.folder+"/chapter-one-profile-v5-r20261119-120000.json"),"V5-1 journal copies of the v5 file go to revisions/")
	var again := open_v5(paths.v5)
	check(again.available and not again.imported_from_v4 and same(again.state,profile.state) and same(again.characters,profile.characters),"V5-1 the v5 file reads back identically")
	good_files.append(paths.v5)
	var one := open_v4(stage_full(work+"/v1b"))
	var two := open_v4(stage_full(work+"/v1c"))
	check(one.state==two.state and one.characters==two.characters and one._origin_hint==two._origin_hint,"V5-1 carrying the same file over twice gives the same memory state")
	# V5-3: the schema-4 pointer leads to its r-file; a v4 name in the v5 pointer is ignored
	var pointed := stage_journals(work+"/v3",true)
	var pointer_before := FileAccess.get_sha256(pointed.v4ptr);var pointed_before := old_hashes(pointed.folder)
	var via=open_v4(pointed,true)
	check(via.available and via.imported_from_v4 and via.path==pointed.v5 and via._origin_hint.from_file=="chapter-one-profile-v4-r20261119-120000.json" and int(via._origin_hint.from_revision)==5 and via.state.items.size()==8,"V5-3 the schema-4 pointer leads to its r-file")
	check(FileAccess.get_sha256(pointed.v4ptr)==pointer_before and same_hashes(pointed_before,pointed.folder) and not FileAccess.file_exists(pointed.v5),"V5-3 the schema-4 pointer and every schema-4 file are unchanged")
	write_text(pointed.v5ptr,JSON.stringify({"schema":1,"file":"chapter-one-profile-v4-r20261119-120000.json"}))
	var ptr_text := FileAccess.get_file_as_string(pointed.v5ptr)
	var ignored=open_v4(pointed,true)
	check(ignored.available and ignored.path==pointed.v5 and ignored.imported_from_v4 and ignored._origin_hint.from_file=="chapter-one-profile-v4-r20261119-120000.json","V5-3 a schema-4 name in the v5 pointer is ignored (the v5 main path is used, the schema-4 pointer still leads the carry-over)")
	check(FileAccess.get_file_as_string(pointed.v5ptr)==ptr_text,"V5-3 the v5 pointer is not rewritten by a read")
	# QA paths holding .. are refused, also for the new arguments; the product path guard refuses a foreign path
	var sneaky=Profile.new()
	check(not sneaky.configure(work+"/ok-v5.json",true,"","","","","","res://_local/../x.json") and sneaky.error_code=="isolated_path_invalid" and not sneaky.configure(work+"/ok-v5.json",true,"","","","","","","res://_local/a/../b.json"),"V5-3 QA paths holding .. in the new arguments are refused")
	var product=Profile.new()
	check(not product.configure(Profile.PATH_V4,false) and product.error_code=="preview_only","V5-3 the product guard accepts only the v5 path")

# V5-2: once the v5 file exists the v4 and v3 files do not matter any more
func v2_v3_checks() -> void:
	var paths := stage_full(work+"/v2")
	var first=open_v4(paths)
	first.wear_outfit(FROST,"")
	write_text(paths.v4,"{ this is no longer a profile")
	Snap4.copy_bytes(F3+"/v3_full.json",paths.v3)
	write_text(paths.v3,"also broken")
	var second=open_v4(paths,false,true)
	check(second.available and not second.imported_from_v4 and not second.imported_from_v3 and same(second.state,first.state),"V5-2 once the v5 file exists broken v4 and v3 files are not looked at")
	# the schema-3 chain still works when there is no v4 and no v5, and it ends in a v5 document
	var legacy := stage_full(work+"/v2b")
	DirAccess.remove_absolute(legacy.v4)
	Snap4.copy_bytes(F3+"/v3_full.json",legacy.v3)
	var carried=open_v4(legacy,false,true)
	check(carried.available and carried.imported_from_v3 and not carried.imported_from_v4 and int(carried.state.schema_version)==5 and carried._origin_hint.from_schema==3,"V5-2 with no v4 file a schema-3 file is carried over to v5")
	check(carried.wear_outfit(FROST,SWIM_1) and int(JSON.parse_string(FileAccess.get_file_as_string(legacy.v5)).origin.from_schema)==3,"V5-2 and its first save records schema 3 as the source")
	good_files.append(legacy.v5)

# V5-6: a schema-4 original whose structure is broken
func v6_checks() -> void:
	var paths := stage_journals(work+"/v6",false)
	var before := hashes(paths.folder)
	var profile=open_v4(paths)
	check(not profile.available and profile.reject_kind=="legacy" and profile.reject_source==paths.v4,"V5-6 a broken schema-4 original is refused as legacy")
	check(hashes(paths.folder)==before and not FileAccess.file_exists(paths.v5),"V5-6 the refusal writes nothing and leaves every file as it was")
	check(profile.resume_info().get("kind")=="v4_journal" and int(profile.resume_info().get("revision",0))==4,"V5-6 the resume candidate is the newest readable schema-4 journal copy (revision 4)")
	check(profile.start_fresh_after_reject(true) and FileAccess.file_exists(paths.v5) and not FileAccess.file_exists(paths.v5ptr) and profile.path==paths.v5 and int(profile.state.revision)==5,"V5-6 a new save starts at the normal v5 path from that copy; no pointer")
	check(same_hashes(before,paths.folder),"V5-6 the schema-4 folder is byte for byte as before the new save")
	good_files.append(paths.v5)
	# every schema-4 journal copy broken: no candidate; a schema-3 file beside it is not used (T6-D10: the chain stops at the refused v4 original)
	var broken := stage_journals(work+"/v6b",false)
	for rel in Snap4.list_files(broken.folder+"/revisions"):write_text(broken.folder+"/revisions/"+rel,"{ nope")
	Snap4.copy_bytes(F3+"/v3_full.json",broken.v3)
	var none=open_v4(broken,false,true)
	check(not none.available and none.reject_kind=="legacy" and none.resume_info().is_empty(),"V5-6 with every schema-4 journal copy broken there is no candidate, and a schema-3 file does not stand in for it")
	check(none.start_fresh_after_reject(true) and none.state.items.is_empty() and int(none.state.revision)==1,"V5-6 starting fresh then gives an empty v5 save")
	# damaged JSON in the v4 original is legacy too
	var damaged := stage_full(work+"/v6c")
	write_text(damaged.v4,"{ not json")
	var dmg=open_v4(damaged)
	check(not dmg.available and dmg.reject_kind=="legacy" and dmg.reject_reason=="json" and not FileAccess.file_exists(damaged.v5),"V5-6 a schema-4 original that is not JSON is legacy with the reason json")

func refuse_case(label: String,base_text: String,mutate: Callable,folder: String) -> void:
	var target := folder+"/chapter-one-profile-v5.json"
	var doc: Dictionary=JSON.parse_string(base_text);mutate.call(doc)
	write_text(target,JSON.stringify(doc,"  "))
	var before := hashes(folder)
	var loader=open_v5(target)
	check(not loader.available and loader.reject_kind=="incompatible" and hashes(folder)==before,"V5-7 refused as incompatible with the folder unchanged: "+label)

func ids(count: int,prefix: String="x") -> Array:
	var list: Array=[]
	for i in count:list.append("%s.%d"%[prefix,i])
	return list

func v7_reject_checks(base: Dictionary) -> void:
	var text: String=base.text
	var folder := work+"/v7"
	Snap4.wipe_tree(folder)
	var cases := {
		"town missing":func(d): d.erase("town"),
		"town extra key":func(d): d.town["extra"]=1,
		"town not an object":func(d): d.town=[],
		"unlocked 17":func(d): d.town.unlocked=ids(17),
		"unlocked bad id":func(d): d.town.unlocked=["Bad Id"],
		"bought 33":func(d): d.town.bought=ids(33),
		"stock 9":func(d): d.town.shop.stock=[{},{},{},{},{},{},{},{},{}],
		"shop key missing":func(d): d.town.shop.erase("seed"),
		"shop seed too big":func(d): d.town.shop.seed=2147483648,
		"shop refreshed_run negative":func(d): d.town.shop.refreshed_run=-1,
		"luck key missing":func(d): d.town.luck.erase("forge_fails_in_row"),
		"luck extra key":func(d): d.town.luck["x"]=0,
		"luck forge_fails_in_row 11":func(d): d.town.luck.forge_fails_in_row=11,
		"luck negative":func(d): d.town.luck.gamble_since_legendary=-1,
		"luck string":func(d): d.town.luck.gamble_since_legendary="3",
		"quests key missing":func(d): d.characters[FROST].quests.erase("claimed"),
		"quests extra key":func(d): d.characters[FROST].quests["x"]=[],
		"active 9":func(d): d.characters[FROST].quests.active=ids(9,"q"),
		"done 9":func(d): d.characters[FROST].quests.done=ids(9,"q"),
		"claimed 257":func(d): d.characters[FROST].quests.claimed=ids(257,"q"),
		"bounty_offer 4":func(d): d.characters[FROST].quests.bounty_offer=ids(4,"q"),
		"active not a list":func(d): d.characters[FROST].quests.active={},
		"progress value -1":func(d): d.characters[FROST].quests.active=["q.a"];d.characters[FROST].quests.progress={"q.a":-1},
		"progress 9 keys":func(d): d.characters[FROST].quests.progress={"a":1,"b":1,"c":1,"d":1,"e":1,"f":1,"g":1,"h":1,"i":1},
		"bounty_seed too big":func(d): d.characters[FROST].quests.bounty_seed=2147483648,
		"repeat_claims negative":func(d): d.characters[FROST].quests.repeat_claims=-1,
		"grace missing":func(d): d.characters[FROST].erase("grace"),
		"grace extra key":func(d): d.characters[FROST].grace["x"]=[],
		"banned 9":func(d): d.characters[FROST].grace.banned=ids(9,"c"),
		"banned not a list":func(d): d.characters[FROST].grace.banned="card.a",
		"banned bad id":func(d): d.characters[FROST].grace.banned=["Bad Id"],
		"records missing":func(d): d.characters[FROST].erase("records"),
		"records key missing":func(d): d.characters[FROST].records.erase("best"),
		"records runs string":func(d): d.characters[FROST].records.runs="3",
		"records wins negative":func(d): d.characters[FROST].records.wins=-1,
		"best not an object":func(d): d.characters[FROST].records.best=[],
		"best 17":func(d): d.characters[FROST].records.best=_best_many(17),
		"witch in the schema-4 shape":func(d): d.characters[FROST].erase("quests");d.characters[FROST].erase("records");d.characters[FROST].erase("grace"),
		"schema 4":func(d): d.schema_version=4,
		"schema 6":func(d): d.schema_version=6,
		"schema 99":func(d): d.schema_version=99,
		"origin from_schema 6":func(d): d.origin.from_schema=6,
	}
	for label in cases:refuse_case(String(label),text,cases[label],folder)
	# the resume candidates, in order: a v5 journal copy, the v4 original carried over again, the v3 original, an empty save
	var a := make_base(work+"/v7a")
	var a_doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(a.paths.v5));a_doc.schema_version=6
	write_text(a.paths.v5,JSON.stringify(a_doc,"  "))
	var a_before := hashes(a.paths.folder)
	var ra=open_v4(a.paths)
	check(not ra.available and ra.reject_kind=="incompatible" and ra.resume_info().get("kind")=="journal" and int(ra.resume_info().get("revision",0))==34,"V5-7 the first candidate is the newest readable v5 journal copy")
	check(ra.start_fresh_after_reject(true) and ra.path!=a.paths.v5 and ra.path.get_file().begins_with("chapter-one-profile-v5-r") and FileAccess.file_exists(a.paths.v5ptr) and int(ra.state.revision)==35,"V5-7 the new save is a -v5-r file named by the v5 pointer and continues from the copy")
	var pointer_doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(a.paths.v5ptr))
	check(pointer_doc.file==ra.path.get_file() and pointer_doc.replaces=="chapter-one-profile-v5.json" and pointer_doc.kind=="incompatible","V5-7 the v5 pointer names the new file and the refused one")
	check(same_hashes(a_before,a.paths.folder),"V5-7 the refused file and every journal copy are byte for byte the same")
	good_files.append(ra.path)
	var b := make_base(work+"/v7b")
	var b_doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(b.paths.v5));b_doc.schema_version=6
	write_text(b.paths.v5,JSON.stringify(b_doc,"  "))
	for rel in Snap4.list_files(b.paths.folder+"/revisions"):
		if String(rel).begins_with("chapter-one-profile-v5"):DirAccess.remove_absolute(b.paths.folder+"/revisions/"+rel)
	var rb=open_v4(b.paths)
	check(not rb.available and rb.resume_info().get("kind")=="v4_source" and int(rb.resume_info().get("revision",0))==32,"V5-7 with no v5 journal copy the candidate is the v4 original carried over again")
	check(rb.start_fresh_after_reject(true) and rb.state.items.size()>=30 and rb._origin_hint.from_schema==4,"V5-7 starting from it keeps the schema-4 file as it was")
	good_files.append(rb.path)
	var c := make_base(work+"/v7c")
	var c_doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(c.paths.v5));c_doc.schema_version=6
	write_text(c.paths.v5,JSON.stringify(c_doc,"  "))
	for rel in Snap4.list_files(c.paths.folder+"/revisions"):
		if String(rel).begins_with("chapter-one-profile-v5"):DirAccess.remove_absolute(c.paths.folder+"/revisions/"+rel)
	DirAccess.remove_absolute(c.paths.v4)
	for rel in Snap4.list_files(c.paths.folder+"/revisions"):DirAccess.remove_absolute(c.paths.folder+"/revisions/"+rel)
	Snap4.copy_bytes(F3+"/v3_full.json",c.paths.v3)
	var rc=open_v4(c.paths,false,true)
	check(not rc.available and rc.resume_info().get("kind")=="v3_source","V5-7 with no v4 original the candidate is the v3 original carried over again")
	check(rc.start_fresh_after_reject(true) and rc._origin_hint.from_schema==3,"V5-7 starting from it works and names schema 3")
	good_files.append(rc.path)
	var d := make_base(work+"/v7d")
	var d_doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(d.paths.v5));d_doc.schema_version=6
	write_text(d.paths.v5,JSON.stringify(d_doc,"  "))
	for rel in Snap4.list_files(d.paths.folder+"/revisions"):DirAccess.remove_absolute(d.paths.folder+"/revisions/"+rel)
	DirAccess.remove_absolute(d.paths.v4)
	var rd=open_v4(d.paths)
	check(not rd.available and rd.resume_info().is_empty() and rd.start_fresh_after_reject(true) and rd.state.items.is_empty() and int(rd.state.revision)==1,"V5-7 with nothing to continue from the new save is empty")
	good_files.append(rd.path)

func _best_many(count: int) -> Dictionary:
	var table := {}
	for i in count:table["d%d"%(i+1)]={"ticks":0,"grade":0,"kills":0}
	return table

# V5-8: what is fixed on read, and V5-9 later checks that the same documents are refused by the write rule
func fixed_case(label: String,base_text: String,mutate: Callable,folder: String,verify: Callable,strict_refuses: bool=true) -> void:
	var target := folder+"/chapter-one-profile-v5.json"
	var doc: Dictionary=JSON.parse_string(base_text);mutate.call(doc)
	var written := JSON.stringify(doc,"  ")
	write_text(target,written)
	if strict_refuses:strict_docs.append({"label":label,"doc":JSON.parse_string(written)})
	var loader=open_v5(target)
	check(loader.available and FileAccess.get_file_as_string(target)==written,case_tag+" read and the file bytes stay: "+label)
	if loader.available:
		check(verify.call(loader),case_tag+" "+label)
		var document: Dictionary=loader._document(loader.state,loader.characters,loader._words)
		check(not Profile.read_document(document,true).is_empty(),"V5-13 what was read passes the strict write rule: "+label)

func v8_fix_checks(base: Dictionary) -> void:
	var text: String=base.text
	var folder := work+"/v8"
	Snap4.wipe_tree(folder)
	fixed_case("overlapping quest lists keep the furthest stage",text,func(d): var q: Dictionary=d.characters[FROST].quests;q.active=["q.one","q.two"];q.done=["q.one"];q.claimed=["q.two"];q.progress={"q.one":3},folder,
		func(l): var q: Dictionary=l.characters[FROST].quests;return q.active==[] and q.done==["q.one"] and q.claimed==["q.two"] and q.progress=={} and int(l.read_report.get("quest_fixed",0))==3)
	fixed_case("progress without an active quest is dropped",text,func(d): var q: Dictionary=d.characters[FROST].quests;q.active=["q.one"];q.progress={"q.one":2,"q.three":9},folder,
		func(l): var q: Dictionary=l.characters[FROST].quests;return q.progress=={"q.one":2} and int(l.read_report.get("quest_fixed",0))==1)
	fixed_case("duplicates inside the lists",text,func(d): d.characters[FROST].quests.claimed=["q.one","q.one"];d.town.unlocked=["place.hall","place.hall"],folder,
		func(l): return l.characters[FROST].quests.claimed==["q.one"] and l.state.town.unlocked==["place.hall"] and int(l.read_report.get("deduped",0))==2)
	fixed_case("unknown quest, place, purchase and card ids are kept and counted",text,func(d): d.characters[FROST].quests.active=["quest.future"];d.town.unlocked=["place.future"];d.town.bought=["buy.future"];d.characters[FROST].grace.banned=["card.future1","card.future2"],folder,
		func(l): return int(l.read_report.get("unknown_ids",0))==5 and l.characters[FROST].quests.active==["quest.future"] and l.characters[FROST].grace.banned.size()==2,false)
	var future_path := folder+"/chapter-one-profile-v5.json"
	var kept=open_v5(future_path)
	check(kept.wear_outfit(FROST,"") or kept.wear_outfit(FROST,SWIM_1),"V5-8 a save goes through with unknown ids in it")
	var after: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(future_path))
	check(after.characters[FROST].quests.active==["quest.future"] and after.town.unlocked==["place.future"] and after.town.bought==["buy.future"] and after.characters[FROST].grace.banned==["card.future1","card.future2"],"V5-8 the unknown ids survive a save")
	fixed_case("a last record that is not an object becomes {}",text,func(d): d.characters[FROST].records.last=[],folder,
		func(l): return l.records_view(FROST).last.is_empty() and int(l.read_report.get("dropped_record",0))==1)
	fixed_case("wins above runs",text,func(d): d.characters[FROST].records.runs=2;d.characters[FROST].records.wins=5,folder,
		func(l): return int(l.characters[FROST].records.wins)==2 and int(l.read_report.get("record_fixed",0))==1)
	fixed_case("a last record without its core keys becomes {}",text,func(d): d.characters[FROST].records.last={"depth":"d1"},folder,
		func(l): return l.characters[FROST].records.last.is_empty() and int(l.read_report.get("dropped_record",0))==1)
	fixed_case("one broken best entry is dropped, the other stays",text,func(d): d.characters[FROST].records.best={"d1":{"ticks":9,"grade":1,"kills":2},"d2":{"ticks":-1,"grade":1,"kills":2}},folder,
		func(l): var b: Dictionary=l.characters[FROST].records.best;return b.keys()==["d1"] and int(l.read_report.get("dropped_record",0))==1)
	fixed_case("a best key that is not a depth key is dropped",text,func(d): d.characters[FROST].records.best={"deep":{"ticks":9,"grade":1,"kills":2}},folder,
		func(l): return l.characters[FROST].records.best.is_empty() and int(l.read_report.get("dropped_record",0))==1)
	var good_item := stock_item(0)
	var forged := stock_item(1);forged.base_id="chapter1.full.no_such_base"
	var veiled := stock_item(1);veiled["veiled"]=true
	var forged_plus := stock_item(1);forged_plus["forge"]=2
	fixed_case("shop stock: only the broken pieces are dropped",text,func(d): d.town.shop.stock=[good_item,forged,veiled,forged_plus,stock_item(2)],folder,
		func(l): var s: Array=l.state.town.shop.stock;return s.size()==2 and not s[0].has("name") and not s[1].has("description") and int(l.read_report.get("dropped_stock",0))==3)
	fixed_case("shop stock: a v1 piece and a piece with text are handled",text,func(d): var old_piece := {"base_id":"x","name":"old","slot":"weapon","stats":{},"quality":"common","item_level":1,"affixes":[],"description":"old"};var texty := stock_item(1);texty["name"]="Named";d.town.shop.stock=[old_piece,texty],folder,
		func(l): var s: Array=l.state.town.shop.stock;return s.size()==1 and not s[0].has("name") and int(l.read_report.get("dropped_stock",0))==1 and int(l.read_report.get("stripped_text",0))==1)
	# the fixes are written out clean by the next save
	var clean=open_v5(folder+"/chapter-one-profile-v5.json")
	check(clean.available and (clean.wear_outfit(FROST,"") or clean.wear_outfit(FROST,SWIM_1)) and open_v5(clean.path).read_report.is_empty(),"V5-8 the next save writes the fixed stock clean: a reload needs no fix")

# V5-10: record_run
func progress_of(who: String=FROST,xp: int=10) -> Dictionary:
	return {"character_id":who,"xp_gained":xp,"first_kills":[],"sources":{}}

func v10_record_checks() -> void:
	var profile=Profile.new()
	check(profile.configure(work+"/v10/p-v5.json",true),"V5-10 new QA profile")
	var ember_before: Dictionary=profile.characters.get(EMBER,Profile.default_entry(EMBER)).duplicate(true)
	var town_before: Dictionary=profile.state.town.duplicate(true)
	check(profile.record_run("r1",[],[],false,100,progress_of()) and profile.records_view(FROST).runs==1 and profile.records_view(FROST).wins==0,"V5-10 a lost run counts as a run without a record")
	check(profile.record_run("r2",[],[],true,500,progress_of()) and profile.records_view(FROST).runs==2 and profile.records_view(FROST).wins==1 and profile.outcome_note=="","V5-10 a won run counts as a run and a win even with no outcome")
	var saved_text := FileAccess.get_file_as_string(profile.path)
	check(profile.record_run("r2",[],[],true,500,progress_of()) and FileAccess.get_file_as_string(profile.path)==saved_text and profile.records_view(FROST).runs==2,"V5-10 the same receipt twice counts once")
	var rec := core_last(900,50,true,2)
	check(profile.record_run("r3",[],[],true,900,progress_of(),{},{"record":rec}) and same(profile.records_view(FROST).last,rec) and same(profile.records_view(FROST).best,{"d1":{"ticks":900,"grade":2,"kills":50}}) and profile.outcome_note=="","V5-10 a good record becomes `last` and starts `best`")
	check(profile.record_run("r4",[],[],false,100,progress_of(),{},{"record":core_last(100,70,false,1)}) and same(profile.records_view(FROST).best,{"d1":{"ticks":900,"grade":2,"kills":70}}),"V5-10 a lost run raises kills but never ticks")
	check(profile.record_run("r5",[],[],true,800,progress_of(),{},{"record":core_last(800,10,true,3)}) and same(profile.records_view(FROST).best,{"d1":{"ticks":800,"grade":3,"kills":70}}),"V5-10 a faster win lowers ticks and a higher grade raises grade")
	check(profile.record_run("r6",[],[],true,1000,progress_of(),{},{"record":core_last(1000,10,true,1)}) and same(profile.records_view(FROST).best,{"d1":{"ticks":800,"grade":3,"kills":70}}) and profile.records_view(FROST).runs==6,"V5-10 a slower win changes nothing in `best`")
	check(profile.record_run("r7",[],[],false,50,progress_of(),{},{"record":core_last(50,5,false,0,"d2")}) and profile.records_view(FROST).best.has("d2") and profile.records_view(FROST).best.d2.ticks==0 and profile.records_view(FROST).runs==7,"V5-10 a new depth gets its own `best` entry")
	var last_before: Dictionary=profile.records_view(FROST).last.duplicate(true)
	var xp_before := int(profile.characters[FROST].xp)
	var broken := core_last();broken.erase("kills")
	check(profile.record_run("r8",[],[],false,10,progress_of(),{},{"record":broken}) and profile.outcome_note=="record_not_saved" and same(profile.records_view(FROST).last,last_before) and int(profile.characters[FROST].xp)==xp_before+10 and profile.records_view(FROST).runs==8,"V5-10 a record with a broken core key is dropped; the reward and the run count are saved")
	var odd := core_last();odd["death_cause"]="swarm";odd["ratio"]=1.5;odd["note"]="한글 글"
	check(profile.record_run("r9",[],[],false,10,progress_of(),{},{"record":odd}) and profile.outcome_note=="" and profile.records_view(FROST).last.has("death_cause") and not profile.records_view(FROST).last.has("ratio") and not profile.records_view(FROST).last.has("note") and "ratio" in profile.outcome_trimmed and "note" in profile.outcome_trimmed,"V5-10 a bad open key is cut off and named (CHAPTER1_PROFILE_RECORD_TRIMMED); the rest is saved")
	var after_r9: Dictionary=profile.records_view(FROST).last.duplicate(true)
	var runs_now := int(profile.records_view(FROST).runs)
	check(profile.record_run("r10",[],[],false,10,progress_of(),{},{"quests":{}}) and profile.outcome_note=="outcome_unknown_key" and profile.records_view(FROST).runs==runs_now+1 and same(profile.records_view(FROST).last,after_r9),"V5-10 an outcome key this step does not take is noted; the run still counts")
	check(profile.record_run("r11",[],[],false,10,progress_of(),{},{"record":core_last(5,5,false,1,"d3"),"quests":{}}) and profile.outcome_note=="outcome_unknown_key" and same(profile.records_view(FROST).last,after_r9) and not profile.records_view(FROST).best.has("d3"),"V5-10 an unknown key beside a record drops the record")
	var runs_before := int(profile.records_view(FROST).runs);var last_now: Dictionary=profile.records_view(FROST).last.duplicate(true)
	check(profile.record_run("r12",[],[],true,10,{},{},{"record":core_last()}) and profile.outcome_note=="record_not_saved" and profile.records_view(FROST).runs==runs_before and same(profile.records_view(FROST).last,last_now),"V5-10 a record with no witch in `progress` is dropped, no `records` changes")
	check(profile.record_run("r13",[],[],true,10) and profile.records_view(FROST).runs==runs_before and profile.records_view(ARC).runs==0,"V5-10 without `progress` no witch's `records` changes")
	check(same(profile.characters.get(EMBER,Profile.default_entry(EMBER)).records,ember_before.records) and profile.records_view(EMBER).runs==0,"V5-10 another witch's `records` stay as they were")
	check(same(profile.state.town,town_before) and profile.grace_view(FROST).banned.is_empty() and profile.quests_view(FROST).active.is_empty(),"V5-10 `town.luck`, `town`, `grace` and `quests` are not touched by record_run")
	check(profile.total_runs()==profile.records_view(FROST).runs+profile.records_view(EMBER).runs+profile.records_view(ARC).runs and profile.total_runs()==int(profile.records_view(FROST).runs),"V5-10 total_runs() is the sum of the witches' runs")
	check(profile.quests_view("chapter1.character.ghost").is_empty() and profile.records_view("").is_empty() and profile.grace_view("nobody").is_empty() and not profile.town_view().is_empty() and profile.town_view().luck.forge_fails_in_row==0,"V5-10 the read functions return {} for an unknown witch and a copy of `town`")
	var copy: Dictionary=profile.town_view();copy.luck.gamble_since_legendary=9
	check(profile.state.town.luck.gamble_since_legendary==0,"V5-10 a read function returns a copy")
	var reread=open_v5(profile.path)
	check(reread.available and same(reread.characters[FROST].records,profile.characters[FROST].records) and reread.read_report.is_empty(),"V5-10 the records survive a reload with no fix")
	good_files.append(profile.path)
	# the equipment reward and the receipt in one save still hold
	var tables=Profile.loot();var rng := RandomNumberGenerator.new();rng.seed=3
	var piece: Dictionary=tables.roll_item(rng,6,"magic","weapon");piece.uid=1
	check(profile.record_run("r14",[piece],[],false,10,progress_of(),{},{"record":core_last()}) and profile.state.items.size()==1 and profile.records_view(FROST).runs==runs_before+1,"V5-10 the reward, the receipt, the run count and the record are one save")

# V5-11
func v11_restore_check(base: Dictionary) -> void:
	var text: String=base.text
	var doc: Dictionary=JSON.parse_string(text)
	var source: Dictionary=(doc.characters[ARC] if doc.characters.has(ARC) else Profile.default_entry(ARC)).duplicate(true)
	for key in ["quests","records","grace"]:source.erase(key)
	doc.characters.erase(ARC)
	doc.quarantine.append({"kind":"character","id":ARC,"reason":"unknown character","since_revision":1,"raw":source})
	var target := work+"/v11/chapter-one-profile-v5.json"
	write_text(target,JSON.stringify(doc,"  "))
	var loader=open_v5(target)
	check(loader.available and int(loader.read_report.get("restored_characters",0))==1 and loader.characters.has(ARC) and loader.characters[ARC].quests.active==[] and loader.characters[ARC].records.runs==0 and loader.characters[ARC].grace.banned==[],"V5-11 a set-aside witch in the schema-4 shape comes back with the new cells at their defaults")
	var ghosts := 0
	for entry in loader.state.quarantine:
		if entry.kind=="character":ghosts+=1
	check(ghosts==1,"V5-11 only the unknown witch stays set aside (%d)"%ghosts)
	check(loader.record_run("restored",[],[],false,1,progress_of(ARC,5)) and loader.records_view(ARC).runs==1,"V5-11 the restored witch saves and counts a run")

# V5-12
func v12_text_checks() -> void:
	var profile=rich_profile(work+"/v12")
	var doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(profile.path))
	var shell: Dictionary=doc.duplicate(true)
	shell.items=[]
	for record in doc.items:
		if record.item.has("grammar"):shell.items.append(record)
	shell.erase("quarantine")
	var problems: Array=[]
	text_problems(shell,"",problems)
	check(problems.is_empty(),"V5-12 the v5 file holds no sentence outside legacy_name, v1 items and quarantine (%s)"%str(problems.slice(0,3)))
	check(doc.town.shop.stock.size()==2 and doc.characters[FROST].records.last.has("death_cause") and doc.characters[FROST].quests.claimed==["q.three"],"V5-12 the file checked really holds the shop, the last record with open keys and the quests")
	for piece in doc.town.shop.stock:check(not piece.has("name") and not piece.has("description") and not piece.has("veiled") and not piece.has("forge"),"V5-12 a shop piece has no text and none of veiled, forge, rerolls")
	good_files.append(profile.path)

# V5-14
func v14_compat_checks() -> void:
	var paths := stage_compat(work+"/v14")
	var before := old_hashes(paths.folder)
	var reader=open_v4(paths)
	check(reader.available and reader.imported_from_v4 and reader.read_report.is_empty() and reader.state.quarantine.is_empty() and reader.state.items.size()>=30 and same_hashes(before,paths.folder),"V5-14 the v4 compatibility file is carried over with no fix at all")
	if "--write-compat" in OS.get_cmdline_user_args():
		if FileAccess.file_exists(COMPAT5):
			check(false,"V5-14 refusing to overwrite the v5 compatibility file")
		else:
			var made=rich_profile(work+"/v14-make",true)
			var out := FileAccess.open(COMPAT5,FileAccess.WRITE);out.store_string(FileAccess.get_file_as_string(made.path));out.close()
	check(FileAccess.file_exists(COMPAT5),"V5-14 the v5 compatibility file exists")
	if not FileAccess.file_exists(COMPAT5):return
	var target := work+"/v14-read/chapter-one-profile-v5.json"
	write_text(target,FileAccess.get_file_as_string(COMPAT5))
	var v5=open_v5(target)
	check(v5.available and v5.read_report.is_empty() and v5.state.items.size()>=30,"V5-14 the v5 compatibility file reads with no fix at all")
	var doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(COMPAT5))
	var frost: Dictionary=doc.characters[FROST]
	var forged := 0
	for record in doc.items:
		if record.item.has("forge") and record.item.has("rerolls"):forged+=1
	check(int(doc.schema_version)==5 and doc.town.luck.gamble_since_legendary==39 and not doc.town.shop.stock.is_empty() and not doc.town.unlocked.is_empty() and not doc.town.bought.is_empty() and not frost.quests.active.is_empty() and not frost.quests.claimed.is_empty() and frost.records.runs>0 and frost.records.last.has("death_cause") and not frost.grace.banned.is_empty() and forged>=1,"V5-14 the v5 compatibility file holds every new cell with a value other than the default")
	good_files.append(target)

# V5-15
func v15_newer_checks(base: Dictionary) -> void:
	var future := mutated(base.text,func(d): d.schema_version=6)
	var folder := work+"/v15"
	Snap4.wipe_tree(folder)
	write_text(folder+"/chapter-one-profile-v5.json",JSON.stringify(future,"  "))
	var refused=open_v5(folder+"/chapter-one-profile-v5.json")
	check(not refused.available and refused.reject_kind=="incompatible" and refused.newer_save_file.is_empty(),"V5-15 a schema-6 document at the v5 path is refused as incompatible")
	var next := work+"/v15b"
	Snap4.wipe_tree(next)
	write_text(next+"/chapter-one-profile-v5.json",base.text)
	write_text(next+"/chapter-one-profile-v6.json","{ not read, never opened }")
	write_text(next+"/chapter-one-profile-v5-r20261120-010101.json","{}")
	write_text(next+"/chapter-one-profile-v5-active.json","{}")
	write_text(next+"/chapter-one-profile-v4.json","{}")
	var v6_before := FileAccess.get_sha256(next+"/chapter-one-profile-v6.json")
	var present=open_v5(next+"/chapter-one-profile-v5.json")
	check(present.available and present.newer_save_file=="chapter-one-profile-v6.json" and present.wear_outfit(FROST,"") and FileAccess.get_sha256(next+"/chapter-one-profile-v6.json")==v6_before,"V5-15 a v6 file beside the v5 file is named in `newer_save_file`; the save still works and the v6 bytes are unchanged")
	write_text(next+"/chapter-one-profile-v12-r20261120-010101.json","{}")
	DirAccess.remove_absolute(next+"/chapter-one-profile-v6.json")
	check(open_v5(next+"/chapter-one-profile-v5.json").newer_save_file=="chapter-one-profile-v12-r20261120-010101.json","V5-15 a later schema number and a -r name are found too")
	DirAccess.remove_absolute(next+"/chapter-one-profile-v12-r20261120-010101.json")
	check(open_v5(next+"/chapter-one-profile-v5.json").newer_save_file.is_empty(),"V5-15 the v5, v5-r, v5-active and v4 names are not newer")

# V5-17
func v17_journal_checks() -> void:
	var paths := stage_journals(work+"/v17",true)
	var profile=open_v4(paths,true)
	profile.record_run("j1",[],[],false,1);profile.record_run("j2",[],[],false,1)
	var v4_in_folder := 0
	for rel in Snap4.list_files(paths.folder+"/revisions"):
		if String(rel).begins_with("chapter-one-profile-v4"):v4_in_folder+=1
	var rows: Array=profile.journal_files()
	var all_v5 := true
	for row in rows:
		if not String(row.file).begins_with("chapter-one-profile-v5.revision-"):all_v5=false
	check(v4_in_folder==4 and rows.size()==2 and all_v5,"V5-17 v5 saves go to revisions/chapter-one-profile-v5.revision-*, and journal_files() leaves the 4 schema-4 copies out (%d, %d)"%[rows.size(),v4_in_folder])
	good_files.append(profile.path)

# V5-18: forge and rerolls on a piece
func v18_forge_checks(base: Dictionary) -> void:
	var profile=rich_profile(work+"/v18")
	var forged_id := -1
	for record in profile.state.items:
		if record.item.has("forge"):forged_id=int(record.storage_id)
	check(forged_id>0,"V5-18 the hand-filled profile has a piece with forge and rerolls")
	var reread=open_v5(profile.path)
	var found := false
	for record in reread.state.items:
		if int(record.storage_id)==forged_id:
			found=typeof(record.item.forge)==TYPE_INT and typeof(record.item.rerolls)==TYPE_INT and record.item.forge==3 and record.item.rerolls==7
			var plain: Dictionary=record.item.duplicate(true);plain.erase("forge");plain.erase("rerolls")
			check(String(Profile.loot().dress(plain).name)==String(record.item.name),"V5-18 the screen name is the same with and without the two keys")
	check(found and reread.read_report.is_empty(),"V5-18 forge 3 and rerolls 7 survive read, save and read again as ints")
	reread.wear_outfit(FROST,"");reread.wear_outfit(FROST,SWIM_1)
	var third=open_v5(reread.path)
	var still := false
	for record in third.state.items:
		if int(record.storage_id)==forged_id:still=record.item.forge==3 and record.item.rerolls==7
	check(still,"V5-18 and they are still there after another save")
	var text := FileAccess.get_file_as_string(profile.path)
	var folder := work+"/v18-cases"
	Snap4.wipe_tree(folder)
	var item_index := -1
	var doc0: Dictionary=JSON.parse_string(text)
	for index in doc0.items.size():
		if int(doc0.items[index].storage_id)==forged_id:item_index=index
	var cases := {"forge 6":["forge",6],"forge -1":["forge",-1],"forge string":["forge","3"],"forge 2.5":["forge",2.5],"rerolls 21":["rerolls",21],"rerolls string":["rerolls","x"],"forge null":["forge",null]}
	var items_total: int=doc0.items.size()
	for label in cases:
		var doc: Dictionary=JSON.parse_string(text)
		doc.items[item_index].item[cases[label][0]]=cases[label][1]
		var original: Dictionary=JSON.parse_string(JSON.stringify(doc.items[item_index]))
		var target := folder+"/"+String(label).replace(" ","-")+"-v5.json"
		write_text(target,JSON.stringify(doc,"  "))
		var loader=open_v5(target)
		var quarantined: Array=[]
		if loader.available:
			for entry in loader.state.quarantine:
				if entry.kind=="item" and int(entry.storage_id)==forged_id:quarantined.append(entry)
		check(loader.available and quarantined.size()==1 and String(quarantined[0].reason).contains(String(cases[label][0])) and loader.state.items.size()==items_total-1+0 and same(quarantined[0].raw,original),"V5-18 %s: that piece alone is set aside with its original record, the rest stay"%label)
		check(Profile.read_document(JSON.parse_string(JSON.stringify(doc)),true).is_empty(),"V5-18 %s: the write rule refuses it"%label)
	for key in ["forge","rerolls"]:
		var doc: Dictionary=JSON.parse_string(text)
		doc.items[item_index].item[key]=0
		var target: String=folder+"/zero-"+String(key)+"-v5.json"
		write_text(target,JSON.stringify(doc,"  "))
		var loader=open_v5(target)
		var record_item := {}
		if loader.available:
			for record in loader.state.items:
				if int(record.storage_id)==forged_id:record_item=record.item
		check(loader.available and not record_item.is_empty() and not record_item.has(key) and int(loader.read_report.get("dropped_flags",0))==1 and loader.state.quarantine.size()==_ghost_count(text),"V5-18 %s 0: the key is removed and counted as dropped_flags"%key)
		strict_docs.append({"label":key+" 0","doc":JSON.parse_string(JSON.stringify(doc))})
	# a schema-4 original that has forge on a piece: set aside while carrying over (the v4 code's verdict)
	var v4_doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(F4+"/v4_full.json"))
	var grammar_index := -1
	for index in v4_doc.items.size():
		if v4_doc.items[index].item.has("grammar") and grammar_index<0:grammar_index=index
	var v4_sid := int(v4_doc.items[grammar_index].storage_id)
	v4_doc.items[grammar_index].item["forge"]=3
	var paths := paths_in(work+"/v18-v4")
	Snap4.wipe_tree(paths.folder)
	write_text(paths.v4,JSON.stringify(v4_doc,"  "))
	var carried=open_v4(paths)
	var set_aside := 0
	for entry in carried.state.quarantine:
		if entry.kind=="item" and int(entry.storage_id)==v4_sid:set_aside+=1
	check(carried.available and set_aside==1 and int(carried.read_report.get("quarantined_items",0))==1,"V5-18 a piece with forge in a schema-4 original is set aside when carried over")
	good_files.append(profile.path)

func _ghost_count(text: String) -> int:
	return (JSON.parse_string(text) as Dictionary).quarantine.size()

# V5-19
func v19_luck_checks() -> void:
	var fresh=Profile.new()
	fresh.configure(work+"/v19/chapter-one-profile-v5.json",true)
	check(fresh.state.town.luck=={"gamble_since_legendary":0,"forge_fails_in_row":0},"V5-19 `town.luck` starts at 0 and 0")
	var candidate: Dictionary=fresh.state.duplicate(true)
	candidate.town.luck={"gamble_since_legendary":39,"forge_fails_in_row":2}
	check(fresh._persist(candidate),"V5-19 a luck value is saved")
	var again=open_v5(fresh.path)
	check(again.available and again.state.town.luck.gamble_since_legendary==39 and again.state.town.luck.forge_fails_in_row==2 and typeof(again.state.town.luck.forge_fails_in_row)==TYPE_INT and again.read_report.is_empty(),"V5-19 {39, 2} is read back as it was")
	again.wear_outfit(FROST,SWIM_1)
	check(open_v5(fresh.path).state.town.luck.gamble_since_legendary==39,"V5-19 and it stays through another save")
	good_files.append(fresh.path)
	var text := FileAccess.get_file_as_string(fresh.path)
	var folder := work+"/v19-cases"
	Snap4.wipe_tree(folder)
	var cases := {"key missing":func(d): d.town.luck.erase("gamble_since_legendary"),"key added":func(d): d.town.luck["more"]=1,"negative":func(d): d.town.luck.forge_fails_in_row=-1,
		"forge_fails_in_row 11":func(d): d.town.luck.forge_fails_in_row=11,"string":func(d): d.town.luck.gamble_since_legendary="39","float":func(d): d.town.luck.gamble_since_legendary=1.5,"too big":func(d): d.town.luck.gamble_since_legendary=1000000001}
	for label in cases:refuse_case("luck "+String(label),text,cases[label],folder)

# D23 T9: the drop pity's counter `town.luck.drop_runs_since_legendary` (optional third key, schema 5 unchanged).
func t9_piece(tables: RefCounted,kind: String,uid: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900+uid
	var piece: Dictionary=tables.make_unique("winter_heart",12) if kind=="unique" else tables.roll_item(rng,12,kind,"weapon")
	piece.uid=uid;piece.position=Vector2.ZERO;piece.collected=true
	return piece

func t9_counter(profile: RefCounted) -> Variant:
	return profile.state.town.luck.get("drop_runs_since_legendary",-1)

func t9_pity_checks(base: Dictionary) -> void:
	var tables=Profile.loot()
	var folder := work+"/t9"
	Snap4.wipe_tree(folder)
	var KEY := "drop_runs_since_legendary"
	# (a) A file with the two old luck keys reads and is written back with exactly those two (and the same town bytes).
	var old=Profile.new()
	check(old.configure(folder+"/old/chapter-one-profile-v5.json",true) and old.record_run("t9-a",[],[],true,100),"T9 a profile with the two old luck keys saves a run (drop_pity left false)")
	var old_doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(old.path))
	var town_before := JSON.stringify(old_doc.town)
	check(old_doc.town.luck.keys().size()==2 and not old_doc.town.luck.has(KEY),"T9 drop_pity=false never creates the key")
	var old_again=open_v5(old.path)
	check(old_again.available and old_again.record_run("t9-b",[],[],true,100) and JSON.stringify(JSON.parse_string(FileAccess.get_file_as_string(old.path)).town)==town_before,"T9 reading and saving again leaves the town text of a two-key file unchanged")
	# (b) A file with the third key reads; it is kept through a save that does not count.
	var text := FileAccess.get_file_as_string(old.path)
	var three := mutated(text,func(d): d.town.luck[KEY]=3)
	write_text(folder+"/three/chapter-one-profile-v5.json",JSON.stringify(three,"  "))
	var opened=open_v5(folder+"/three/chapter-one-profile-v5.json")
	check(opened.available and t9_counter(opened)==3 and typeof(t9_counter(opened))==TYPE_INT,"T9 a file with the third key (3) is read")
	check(opened.record_run("t9-c",[],[],true,100) and open_v5(opened.path).state.town.luck[KEY]==3,"T9 the third key stays through a save that does not count")
	good_files.append(opened.path)
	# (c) Wrong third keys are refused like any wrong luck.
	var cases := {"negative":func(d): d.town.luck[KEY]=-1,"too big":func(d): d.town.luck[KEY]=1000001,"string":func(d): d.town.luck[KEY]="3","float":func(d): d.town.luck[KEY]=1.5,"fourth key":func(d): d.town.luck[KEY]=1;d.town.luck["more"]=1,"other name":func(d): d.town.luck["drop_runs"]=1}
	for label in cases:refuse_case("T9 luck "+String(label),text,cases[label],folder+"/refused")
	# (d) drop_pity=true: win without a legendary +1, again +1, defeat unchanged, defeat with a unique 0, win with a legendary 0.
	var counter=Profile.new()
	check(counter.configure(folder+"/count/chapter-one-profile-v5.json",true),"T9 counting profile")
	check(counter.record_run("w1",[],[],true,100,{},{},{},true) and t9_counter(counter)==1,"T9 a win without a legendary or unique counts 1 (the key appears)")
	check(counter.record_run("w2",[],[],true,100,{},{},{},true) and t9_counter(counter)==2,"T9 and 2")
	check(counter.record_run("l1",[],[],false,100,{},{},{},true) and t9_counter(counter)==2,"T9 a defeat without one leaves it at 2")
	check(counter.record_run("l2",[t9_piece(tables,"unique",1)],[],false,100,{},{},{},true) and t9_counter(counter)==0,"T9 a defeat that brought a unique sets it to 0")
	check(counter.record_run("w3",[],[],true,100,{},{},{},true) and t9_counter(counter)==1,"T9 counting starts again from 0")
	check(counter.record_run("w4",[t9_piece(tables,"legendary",2)],[],true,100,{},{},{},true) and t9_counter(counter)==0,"T9 a win with a legendary sets it to 0")
	check(counter.record_run("w5",[],[],true,100,{},{},{},true) and t9_counter(counter)==1,"T9 +1 after the reset")
	# A pending piece (bag full) counts as seen too.
	check(counter.record_run("w6",[],[t9_piece(tables,"legendary",3)],true,100,{},{},{},true) and t9_counter(counter)==0,"T9 a legendary among the pending rewards counts as seen")
	# Only a NEW piece is seen: a piece already stored does not reset it.
	counter.record_run("w7",[],[],true,100,{},{},{},true)
	var stored_id := 0
	for record in counter.state.items:
		if record.item.quality=="legendary":stored_id=int(record.storage_id)
	check(stored_id>0 and counter.record_run("w8",[{"storage_id":stored_id}],[],true,100,{},{},{},true) and t9_counter(counter)==2,"T9 a legendary that was already in the stash does not reset it (+1)")
	var before_text := FileAccess.get_file_as_string(counter.path)
	check(counter.record_run("w8",[],[],true,100,{},{},{},true) and t9_counter(counter)==2 and FileAccess.get_file_as_string(counter.path)==before_text,"T9 the same receipt twice counts once and writes nothing")
	# The count stops at 1,000,000.
	var capped: Dictionary=counter.state.duplicate(true)
	capped.town.luck[KEY]=1000000
	check(counter._persist(capped) and counter.record_run("w9",[],[],true,100,{},{},{},true) and t9_counter(counter)==1000000,"T9 the count stops at 1,000,000")
	# A defeat on a profile that never had the key does not create it.
	var plain=Profile.new()
	check(plain.configure(folder+"/plain/chapter-one-profile-v5.json",true) and plain.record_run("p1",[],[],false,100,{},{},{},true) and not plain.state.town.luck.has(KEY),"T9 a defeat with nothing seen creates no key")
	# A refused save changes nothing.
	var full=Profile.new()
	full.configure(folder+"/full/chapter-one-profile-v5.json",true)
	var too_many: Array=[]
	for i in 66:too_many.append(t9_piece(tables,"legendary",10+i))
	var full_text := FileAccess.get_file_as_string(full.path) if FileAccess.file_exists(full.path) else ""
	check(not full.record_run("big",too_many,[],true,100,{},{},{},true) and not full.state.town.luck.has(KEY),"T9 a refused record_run leaves the counter as it was")
	# A profile carried over from schema 4 (make_base) has no key.
	check(not String(base.text).contains(KEY) and not base.profile.state.town.luck.has(KEY),"T9 a profile carried over from schema 4 has no key")

# V5-20
func v20_grace_checks(base: Dictionary) -> void:
	check(Profile.default_entry(FROST).grace=={"banned":[]},"V5-20 `grace.banned` starts empty")
	var folder := work+"/v20"
	Snap4.wipe_tree(folder)
	var target := folder+"/chapter-one-profile-v5.json"
	var doc := mutated(base.text,func(d): d.characters[FROST].grace.banned=["card.gone1","card.gone2"])
	write_text(target,JSON.stringify(doc,"  "))
	var loader=open_v5(target)
	check(loader.available and int(loader.read_report.get("unknown_ids",0))==2 and loader.grace_view(FROST).banned==["card.gone1","card.gone2"],"V5-20 two unknown card ids are kept and counted")
	loader.wear_outfit(FROST,"");loader.wear_outfit(FROST,SWIM_1)
	check(JSON.parse_string(FileAccess.get_file_as_string(target)).characters[FROST].grace.banned==["card.gone1","card.gone2"],"V5-20 they survive a save")
	good_files.append(target)
	var dup := mutated(base.text,func(d): d.characters[FROST].grace.banned=["card.a","card.a"])
	write_text(folder+"/dup-v5.json",JSON.stringify(dup,"  "))
	var dl=open_v5(folder+"/dup-v5.json")
	check(dl.available and dl.grace_view(FROST).banned==["card.a"] and int(dl.read_report.get("deduped",0))==1,"V5-20 a repeated id is read as one (deduped)")
	strict_docs.append({"label":"banned duplicate","doc":dup})
	var eight := mutated(base.text,func(d): d.characters[FROST].grace.banned=ids(8,"c"))
	write_text(folder+"/eight-v5.json",JSON.stringify(eight,"  "))
	check(open_v5(folder+"/eight-v5.json").available and not Profile.read_document(eight,true).is_empty(),"V5-20 eight ids are accepted by the read and the write rule")
	refuse_case("banned 9 ids",base.text,func(d): d.characters[FROST].grace.banned=ids(9,"c"),folder+"/nine")

# V5-21
func v21_last_checks(base: Dictionary) -> void:
	case_tag="V5-21"
	var folder := work+"/v21"
	Snap4.wipe_tree(folder)
	var wanted := open_last()
	var doc := mutated(base.text,func(d): d.characters[FROST].records.last=wanted)
	var target := folder+"/chapter-one-profile-v5.json"
	write_text(target,JSON.stringify(doc,"  "))
	var loader=open_v5(target)
	check(loader.available and loader.read_report.is_empty() and same(loader.records_view(FROST).last,wanted),"V5-21 core keys and open keys (death_cause, ultimate_casts, reactions, skills[0].detonations) are read as they are")
	check(typeof(loader.records_view(FROST).last.ultimate_casts)==TYPE_INT and typeof(loader.records_view(FROST).last.skills[0].detonations)==TYPE_INT,"V5-21 whole numbers read from the file are ints")
	loader.wear_outfit(FROST,"");loader.wear_outfit(FROST,SWIM_1)
	check(same(open_v5(target).records_view(FROST).last,wanted) and Profile.read_document(JSON.parse_string(FileAccess.get_file_as_string(target)),true).size()>0,"V5-21 and they stay through a save; the written file passes the write rule")
	good_files.append(target)
	var trimmed := open_last()
	trimmed["ratio"]=1.5;trimmed["note"]="한글 글";trimmed["deep"]=[[[1]]];trimmed["Bad-Key"]=1;trimmed.skills[0]["frac"]=0.5;trimmed["longname_"+"x".repeat(40)]=1
	fixed_case("open keys that break the rules are cut off one by one",base.text,func(d): d.characters[FROST].records.last=trimmed,folder+"/trim",
		func(l): var last: Dictionary=l.records_view(FROST).last;return same(last,wanted) and int(l.read_report.get("dropped_record",0))==6)
	var too_many := core_last()
	for i in 35:too_many["k%02d"%i]=i
	fixed_case("49 keys make `last` empty",base.text,func(d): d.characters[FROST].records.last=too_many,folder+"/many",
		func(l): return l.records_view(FROST).last.is_empty() and int(l.read_report.get("dropped_record",0))==1)
	var too_long := core_last()
	for i in 8:
		var row: Array=[]
		for j in 32:row.append("x".repeat(80))
		too_long["a%d"%i]=row
	check(JSON.stringify(too_long).length()>16000,"V5-21 (the long record really is over 16,000 characters)")
	fixed_case("over 16,000 characters make `last` empty",base.text,func(d): d.characters[FROST].records.last=too_long,folder+"/long",
		func(l): return l.records_view(FROST).last.is_empty() and int(l.read_report.get("dropped_record",0))==1)
	var no_kills := core_last();no_kills.erase("kills")
	fixed_case("a missing core key makes `last` empty",base.text,func(d): d.characters[FROST].records.last=no_kills,folder+"/core",
		func(l): return l.records_view(FROST).last.is_empty() and int(l.read_report.get("dropped_record",0))==1)
	var bad_range := core_last();bad_range.champion_kills=17
	fixed_case("a core key out of range makes `last` empty",base.text,func(d): d.characters[FROST].records.last=bad_range,folder+"/range",
		func(l): return l.records_view(FROST).last.is_empty())
	var bad_skill := core_last();bad_skill.skills[0].erase("rank")
	fixed_case("a skill row without a core key makes `last` empty",base.text,func(d): d.characters[FROST].records.last=bad_skill,folder+"/skill",
		func(l): return l.records_view(FROST).last.is_empty())
	var skills17 := core_last();skills17.skills=[]
	for i in 17:skills17.skills.append(core_last().skills[0])
	fixed_case("17 skill rows make `last` empty",base.text,func(d): d.characters[FROST].records.last=skills17,folder+"/skills17",
		func(l): return l.records_view(FROST).last.is_empty())
	var depth3 := core_last();depth3["bag"]={"a":{"b":1}}
	var depth4 := core_last();depth4["bag"]={"a":{"b":{"c":1}}}
	fixed_case("a nested open value of depth 2 is kept",base.text,func(d): d.characters[FROST].records.last=depth3,folder+"/depth2",
		func(l): return same(l.records_view(FROST).last,depth3) and l.read_report.is_empty(),false)
	fixed_case("a nested open value of depth 3 is cut off",base.text,func(d): d.characters[FROST].records.last=depth4,folder+"/depth3",
		func(l): return same(l.records_view(FROST).last,core_last()) and int(l.read_report.get("dropped_record",0))==1)

# V5-9: the pre-fix documents of V5-8 and V5-18 to V5-21 are refused by the write rule
func v9_strict_checks() -> void:
	var refused := 0
	for entry in strict_docs:
		var rejected := Profile.read_document(entry.doc,true).is_empty()
		if rejected:refused+=1
		check(rejected,"V5-9 the write rule refuses the document before the fix: "+String(entry.label))
	check(refused==strict_docs.size() and strict_docs.size()>=20,"V5-9 every one of the %d pre-fix documents was refused"%strict_docs.size())

# V5-16: the files that make the golden hashes and the measurements do not touch the profile
func v16_static_checks() -> void:
	var tools := ["golden_core.gd","test_core_text.gd","measure_combat.gd","measure_rhythm.gd","sim_loot.gd","sim_builds.gd","report_run_loot.gd"]
	for file_name in tools:
		var full: String="res://chapter1/tests/"+String(file_name)
		if not FileAccess.file_exists(full):static_note.append(file_name+": not found");check(true,"V5-16 "+file_name+" does not exist (noted, not a failure)");continue
		var source := _code_only(FileAccess.get_file_as_string(full))
		check(not source.contains("chapter_profile") and not source.contains("import_starting_gear"),"V5-16 "+file_name+" has no chapter_profile or import_starting_gear reference in its code")
	# The core's own files never load the profile. chapter_core.gd defines import_starting_gear itself, so only its callers are the question there.
	var core_files := ["chapter_core.gd","combat_core.gd","combat_run.gd","run_growth.gd","run_growth_quality37.gd","loot.gd","chapter_pilot.gd","skill_tree.gd"]
	for file_name in core_files:
		var full: String="res://chapter1/core/"+String(file_name)
		if not FileAccess.file_exists(full):static_note.append(file_name+": not found");check(true,"V5-16 "+file_name+" does not exist (noted, not a failure)");continue
		check(not _code_only(FileAccess.get_file_as_string(full)).contains("chapter_profile"),"V5-16 "+file_name+" does not load chapter_profile")

## The lines of a script that are not whole-line comments (a comment may say that the file never touches the profile).
func _code_only(source: String) -> String:
	var lines: Array[String]=[]
	for line in source.split(char(10)):
		if not line.strip_edges().begins_with("#"):lines.append(line)
	return char(10).join(lines)

# V5-13: whatever was read passes the strict write rule
func v13_invariant_checks() -> void:
	var accepted := 0;var refused := 0
	for name in Snap3.SCENARIOS:
		var spec: Dictionary=Snap3.SCENARIOS[name]
		var folder: String=work+"/v13-"+String(name);Snap3.wipe_files(folder)
		for source in spec.files:Snap3.copy_bytes(F3+"/"+source,folder+"/"+String(spec.files[source]))
		if spec.get("journals",false):
			for file_name in Snap3.journal_names(F3):Snap3.copy_bytes(F3+"/"+Snap3.JOURNAL_DIR+"/"+file_name,folder+"/"+file_name)
		var profile=Profile.new()
		var ok := false
		var main := folder+"/chapter-one-profile-v5.json"
		match String(spec.mode):
			"v3":ok=profile.configure(main,true,"","","",folder+"/"+Snap3.MAIN)
			"v3pointer":ok=profile.configure(main,true,"","","",folder+"/"+Snap3.MAIN,folder+"/"+Snap3.POINTER)
			"v2":ok=profile.configure(main,true,folder+"/chapter-one-profile-v2.json")
			"v1":ok=profile.configure(main,true,"",folder+"/chapter-one-profile-v1.json")
		if not ok:refused+=1;continue
		check(not Profile.read_document(profile._document(profile.state,profile.characters,profile._words),true).is_empty(),"V5-13 what was read from %s passes the strict write rule"%name)
		accepted+=1
	check(accepted==7 and refused==0,"V5-13 all seven frozen schema-3/2/1 scenarios were read (%d, refused %d)"%[accepted,refused])
	accepted=0;refused=0
	for name in Snap4.SCENARIOS:
		var spec: Dictionary=Snap4.SCENARIOS[name]
		var folder: String=work+"/v13-"+String(name);Snap4.wipe_tree(folder)
		var root := String(spec.get("root",F4))
		for source in spec.files:Snap4.copy_bytes(root+"/"+source,folder+"/"+String(spec.files[source]))
		var journals := String(spec.get("journals",""))
		if not journals.is_empty():
			for rel in Snap4.list_files(F4+"/"+Snap4.JOURNAL_DIR):
				if journals=="all" or rel==Snap4.MAIN or rel.begins_with("revisions/"):Snap4.copy_bytes(F4+"/"+Snap4.JOURNAL_DIR+"/"+rel,folder+"/"+rel)
		var paths := paths_in(folder)
		var profile=open_v4(paths,String(spec.mode)=="pointer")
		if not profile.available:refused+=1;continue
		check(not Profile.read_document(profile._document(profile.state,profile.characters,profile._words),true).is_empty(),"V5-13 what was read from %s passes the strict write rule"%name)
		accepted+=1
	check(accepted==3 and refused==1,"V5-13 three of the four frozen schema-4 scenarios are read and the broken one is refused (%d, %d)"%[accepted,refused])
	for file_path in good_files:
		var loader=Profile.new()
		var ok: bool=loader.configure(file_path,true)
		if not ok:check(false,"V5-13 a file made by this check can be read: "+file_path.get_file());continue
		check(not Profile.read_document(loader._document(loader.state,loader.characters,loader._words),true).is_empty(),"V5-13 what was read from "+file_path.get_file()+" passes the strict write rule")
