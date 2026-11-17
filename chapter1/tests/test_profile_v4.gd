extends SceneTree
## T5 S1 checks V-1 .. V-17 for the schema-4 profile. Everything runs on isolated paths under res://_local/.
## The frozen schema-3/2/1 files (chapter1/tests/fixtures/profile_legacy) are only copied from; the copies are what get opened.
## Marker: CHAPTER1_PROFILE_V4_RESULT. `--write-compat` writes fixtures/profile_v4_compat.json once (refuses when it exists).
const Profile=preload("res://chapter1/core/chapter_profile.gd")
const Snap=preload("res://chapter1/tests/profile_legacy_snapshot.gd")
const FIXTURES := "res://chapter1/tests/fixtures/profile_legacy"
const COMPAT := "res://chapter1/tests/fixtures/profile_v4_compat.json"
const FROST := "chapter1.character.frost"
const EMBER := "chapter1.character.ember"
const ARC := "chapter1.character.arc"
const SWIM_1 := "chapter1.outfit.frost.swim_1"
const SWIM_ARC := "chapter1.outfit.arc.swim_2"
var checks := 0
var failures: Array[String]=[]
var work := "res://_local/profile-v4-check"

func _initialize() -> void:call_deferred("execute")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)

func write_text(file_path: String,text: String) -> void:
	DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())
	var f := FileAccess.open(file_path,FileAccess.WRITE);f.store_string(text);f.close()

func hashes(folder: String) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(folder)
	if dir==null:return out
	for file_name in dir.get_files():out[file_name]=FileAccess.get_sha256(folder+"/"+file_name)
	for sub in dir.get_directories():
		for inner in hashes(folder+"/"+sub):out[sub+"/"+inner]=hashes(folder+"/"+sub)[inner]
	return out

func hangul(text: String) -> bool:
	for i in text.length():
		var code := text.unicode_at(i)
		if (code>=0xAC00 and code<=0xD7A3) or (code>=0x3131 and code<=0x318E):return true
	return false

## Hangul string values or name/description/title/text keys anywhere outside legacy_name, v1 items and quarantine raw.
func text_problems(value: Variant,path_: String,out: Array) -> void:
	if value is Dictionary:
		for key in value:
			if hangul(str(key)) or str(key) in ["name","description","title","text"]:
				if not (path_.ends_with("items[]") and false):out.append(path_+"/"+str(key))
			if str(key)=="legacy_name" or str(key)=="raw":continue
			text_problems(value[key],path_+"/"+str(key),out)
	elif value is Array:
		for entry in value:text_problems(entry,path_+"[]",out)
	elif value is String and hangul(value):out.append(path_)

func stage_v3(folder: String,source_name: String="v3_full.json") -> Dictionary:
	Snap.wipe_files(folder)
	var legacy := folder+"/chapter-one-profile-v3.json"
	Snap.copy_bytes(FIXTURES+"/"+source_name,legacy)
	return {"v3":legacy,"v4":folder+"/chapter-one-profile-v4.json","pointer":folder+"/chapter-one-profile-v4-active.json"}

func open_v3(paths: Dictionary) -> RefCounted:
	var profile=Profile.new()
	profile.configure(paths.v4,true,"","",paths.pointer,paths.v3)
	return profile

func v4_profile(path_: String) -> RefCounted:
	var profile=Profile.new()
	profile.configure(path_,true)
	return profile

## Strip names and descriptions (memory items carry them again) to compare states across data copies.
func bare(state: Dictionary) -> String:
	var copy: Dictionary=JSON.parse_string(JSON.stringify(state))
	for record in copy.items:
		record.item.erase("name");record.item.erase("description")
	return JSON.stringify(copy)

func execute() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains("/_local/appdata/"):
		print("CHAPTER1_PROFILE_V4_RESULT ",JSON.stringify({"checks":0,"failures":["user data dir is not isolated: refusing to run"]}));quit(1);return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--work-dir="):work=argument.trim_prefix("--work-dir=")
	if not work.begins_with("res://_local/"):
		print("CHAPTER1_PROFILE_V4_RESULT ",JSON.stringify({"checks":0,"failures":["work dir must be under res://_local/"]}));quit(1);return
	var frozen_before := hashes(ProjectSettings.globalize_path(FIXTURES))
	v1_checks()
	v5_text_checks()
	v7_rename_checks()
	v8_quarantine_checks()
	v9_reject_checks()
	v11_carry_checks()
	v12_kit_checks()
	v13_outfit_checks()
	v14_story_checks()
	v15_invariant_checks()
	v17_compat_checks()
	reset_checks()
	loot_checks()
	check(hashes(ProjectSettings.globalize_path(FIXTURES))==frozen_before,"the frozen schema-3/2/1 fixtures are byte for byte what they were")
	if "--negative" in OS.get_cmdline_user_args():check(false,"Intentional checker failure")
	print("CHAPTER1_PROFILE_V4_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)

# V-1, V-2, V-16: carrying schema 3 over reads only; the first save writes the v4 file; v3 files are never changed.
func v1_checks() -> void:
	var folder := work+"/v1"
	var paths := stage_v3(folder)
	var before := hashes(folder)
	var profile := open_v3(paths)
	check(profile.available and profile.imported_from_v3 and profile.path==paths.v4,"V-1 schema 3 is read in memory")
	check(not FileAccess.file_exists(paths.v4) and hashes(folder)==before,"V-1 reading creates no file and changes none")
	check(profile.wear_outfit(FROST,SWIM_1) and FileAccess.file_exists(paths.v4) and not profile.imported_from_v3,"V-1 the first save writes the v4 file")
	var after := hashes(folder)
	var v3_same := true
	for key in before:
		if not after.has(key) or after[key]!=before[key]:v3_same=false
	check(v3_same,"V-1 every schema-3 file is byte for byte as before the first save")
	var doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(paths.v4))
	check(int(doc.schema_version)==4 and doc.origin.from_schema==3 and doc.origin.from_file=="chapter-one-profile-v3.json" and int(doc.origin.at_unix)>0,"V-1 the carry-over record names the schema-3 file")
	check(not FileAccess.file_exists(folder+"/chapter-one-profile-v3-r20261117-120000.json") and DirAccess.dir_exists_absolute(folder+"/revisions"),"V-1 journal copies of the v4 file go to revisions/")
	# V-2: with a v4 file present, the v3 file is not looked at any more.
	var v3_bytes := FileAccess.get_file_as_string(paths.v3)
	write_text(paths.v3,"{ this is no longer a profile")
	var again := open_v3(paths)
	check(again.available and not again.imported_from_v3 and again.state==profile.state and again.characters==profile.characters,"V-2 once the v4 file exists a changed v3 file does not matter")
	write_text(paths.v3,v3_bytes)
	# Carrying over twice gives the same state and no doubled copies (the second read starts from the same file).
	var one := open_v3(stage_v3(work+"/v1b"))
	var two := open_v3(stage_v3(work+"/v1c"))
	check(one.state==two.state and one.characters==two.characters,"V-1 carrying the same file over twice gives the same memory state")
	# V-16: the v3 pointer is read only; the v4 pointer ignores a v3 name.
	var jf := work+"/v16"
	Snap.wipe_files(jf)
	for file_name in Snap.journal_names(FIXTURES):Snap.copy_bytes(FIXTURES+"/"+Snap.JOURNAL_DIR+"/"+file_name,jf+"/"+file_name)
	var pointer_before := FileAccess.get_sha256(jf+"/"+Snap.POINTER)
	var viaptr=Profile.new()
	check(viaptr.configure(jf+"/chapter-one-profile-v4.json",true,"","",jf+"/chapter-one-profile-v4-active.json",jf+"/"+Snap.MAIN,jf+"/"+Snap.POINTER) and viaptr.imported_from_v3 and viaptr._origin_hint.from_file.begins_with("chapter-one-profile-v3-r"),"V-16 the schema-3 pointer leads to its r-file")
	write_text(jf+"/chapter-one-profile-v4-active.json",JSON.stringify({"schema":1,"file":"chapter-one-profile-v3-r20261117-120000.json"}))
	var ignored=Profile.new()
	check(ignored.configure(jf+"/chapter-one-profile-v4.json",true,"","",jf+"/chapter-one-profile-v4-active.json",jf+"/"+Snap.MAIN) and ignored.path==jf+"/chapter-one-profile-v4.json" and FileAccess.get_sha256(jf+"/"+Snap.POINTER)==pointer_before,"V-16 a v3 name in the v4 pointer is ignored; the v3 pointer is unchanged")

# V-5 / V-6
func v5_text_checks() -> void:
	for name in ["v3_full.json","v3_rare_oldword.json","v3_rare_threeword.json"]:
		var paths := stage_v3(work+"/v5-"+name.get_basename(),name)
		var profile := open_v3(paths)
		check(profile.wear_outfit(FROST,SWIM_1),"V-5 saved "+name)
		var doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(paths.v4))
		var problems: Array=[]
		var shell: Dictionary=doc.duplicate(true)
		shell.items=[]
		for record in doc.items:
			if record.item.has("grammar"):shell.items.append(record)
		text_problems(shell,"",problems)
		check(problems.is_empty(),"V-5 the v4 file made from %s holds no sentence outside legacy_name, v1 items and quarantine (%s)"%[name,str(problems.slice(0,3))])
		var rare_words := 0;var legacy := 0
		for record in doc.items:
			if record.item.get("quality")=="rare":
				if record.item.has("rare_words"):rare_words+=1
				if record.item.has("legacy_name"):legacy+=1
		if name=="v3_full.json":check(rare_words>=5 and legacy==0,"V-6 every rare of v3_full is two word ids (%d)"%rare_words)
		else:check(legacy==1 and rare_words>=5,"V-6 %s: exactly one rare keeps its old text as legacy_name"%name)

# V-7: names changed everywhere in the data do not change what a saved file reads as.
func v7_rename_checks() -> void:
	var paths := stage_v3(work+"/v7")
	var profile := open_v3(paths)
	profile.wear_outfit(FROST,SWIM_1)
	var original_bytes := FileAccess.get_file_as_string(paths.v4)
	var parser := JSON.new();parser.parse(FileAccess.get_file_as_string("res://chapter1/data/loot.json"))
	var data: Dictionary=parser.data
	var renamed: Dictionary=data.duplicate(true)
	for table in ["bases","affixes","legendaries","uniques"]:
		for row in renamed[table]:
			row.name="X-"+String(row.name)
			if row.has("description"):row.description="X-"+String(row.description)
	for part in ["first","second"]:
		for row in renamed.rare_names[part]:row.name="X"+String(row.name)
	var data_path := work+"/v7-loot.json"
	write_text(data_path,JSON.stringify(renamed,"  "))
	Profile.use_data_for_test(data_path)
	var swapped=Profile.new()
	var ok: bool=swapped.configure(paths.v4,true)
	var rare_count := 0
	for record in swapped.state.items:
		if record.item.get("quality")=="rare" and String(record.item.name).begins_with("X"):rare_count+=1
	Profile.use_data_for_test("")
	var plain=Profile.new();plain.configure(paths.v4,true)
	check(ok and swapped.available and swapped.read_report.is_empty() and bare(swapped.state)==bare(plain.state) and JSON.stringify(swapped.characters)==JSON.stringify(plain.characters),"V-7 a data copy with every name changed reads the same v4 file: no fixes, same state")
	check(rare_count>=5 and swapped.state.items[0].item.name!=plain.state.items[0].item.name,"V-7 the screen names follow the data copy")
	check(FileAccess.get_file_as_string(paths.v4)==original_bytes,"V-7 the read changed no byte")
	# one rare word renamed: the same words, the new name
	var one_word: Dictionary=data.duplicate(true)
	one_word.rare_names.first[0].name="Renamed"
	write_text(data_path,JSON.stringify(one_word,"  "))
	Profile.use_data_for_test(data_path)
	var word=Profile.new();word.configure(paths.v4,true)
	Profile.use_data_for_test("")
	var words_same := true;var shown := 0
	for i in word.state.items.size():
		var a: Dictionary=word.state.items[i].item;var b: Dictionary=plain.state.items[i].item
		if a.quality=="rare" and word._words.get(int(word.state.items[i].storage_id))!=plain._words.get(int(plain.state.items[i].storage_id)):words_same=false
		if a.quality=="rare" and String(a.name).begins_with("Renamed"):shown+=1
	check(words_same and word.read_report.is_empty(),"V-7 renaming one rare word leaves every rare_words as saved")
	var expected_shown := 0
	for key in plain._words:
		if plain._words[key].has("rare_words") and plain._words[key].rare_words[0]=="f01":expected_shown+=1
	check(shown==expected_shown,"V-7 the renamed word shows in the rares that use it (%d)"%shown)
	# a word id the data does not know: kept, counted, shown by its id
	var doc: Dictionary=JSON.parse_string(original_bytes)
	for record in doc.items:
		if record.item.get("quality")=="rare" and record.item.has("rare_words"):
			record.item.rare_words=["f99","s01"];break
	write_text(work+"/v7-unknown.json",JSON.stringify(doc,"  "))
	var unnamed=Profile.new()
	check(unnamed.configure(work+"/v7-unknown.json",true) and int(unnamed.read_report.get("unnamed_rare",0))==1 and unnamed.state.quarantine.is_empty(),"V-7 an unknown word id does not set the item aside; it is counted")

# V-8
func v8_quarantine_checks() -> void:
	var paths := stage_v3(work+"/v8")
	var profile := open_v3(paths)
	profile.wear_outfit(FROST,SWIM_1)
	var doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(paths.v4))
	var worn_id := int(doc.characters[FROST].loadout.values()[0])
	var victim := -1;var other := -1
	for index in doc.items.size():
		var record: Dictionary=doc.items[index]
		if record.item.has("grammar") and record.item.quality in ["magic","rare"] and int(record.storage_id)!=worn_id:
			if victim<0:victim=index
			elif other<0:other=index
	doc.items[victim].item.base_id="chapter1.full.no_such_base"
	var stats: Dictionary=doc.items[other].item.stats;var key: String=stats.keys()[0];stats[key]=int(stats[key])+777
	# one worn piece with an unknown affix id
	var worn_index := -1
	for index in doc.items.size():
		if int(doc.items[index].storage_id)==worn_id:worn_index=index
	var worn_original: Dictionary=doc.items[worn_index].duplicate(true)
	if doc.items[worn_index].item.affixes.size()>0:doc.items[worn_index].item.affixes[0].id="no_such_affix"
	else:doc.items[worn_index].item.base_id="chapter1.full.no_such_base"
	var path_ := work+"/v8/quarantine-v4.json"
	write_text(path_,JSON.stringify(doc,"  "))
	var bytes := FileAccess.get_file_as_string(path_);var folder_before := hashes(work+"/v8")
	var reader=Profile.new();var ok: bool=reader.configure(path_,true)
	check(ok and reader.available and reader.state.quarantine.size()==3 and int(reader.read_report.get("quarantined_items",0))==3,"V-8 three items that do not match the data are set aside; the file is accepted")
	check(reader.state.items.size()==doc.items.size()-3,"V-8 the other items stay")
	check(FileAccess.get_file_as_string(path_)==bytes and hashes(work+"/v8")==folder_before,"V-8 the read leaves the file and the folder as they were")
	check(reader.loadout(FROST).values().has(worn_id) and not reader.starting_kit(FROST).gear.any(func(p): return int(p.storage_id)==worn_id) and reader.starting_kit(FROST).kept_slots.has(reader.equip_slot_of(worn_id,FROST)),"V-8 the kit slot that points at a set-aside piece stays but does not go to the start")
	check(int(reader.read_report.get("inactive_loadout",0))>=1,"V-8 the report counts the kit slot pointing at a set-aside item")
	var raws_before: Array=[]
	for entry in reader.state.quarantine:raws_before.append(JSON.stringify(JSON.parse_string(JSON.stringify(entry.raw))))
	check(reader.wear_outfit(FROST,""),"V-8 a save with set-aside items goes through")
	var after: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path_))
	var raws_after: Array=[]
	for entry in after.quarantine:raws_after.append(JSON.stringify(JSON.parse_string(JSON.stringify(entry.raw))))
	raws_before.sort();raws_after.sort()
	check(raws_before==raws_after and after.quarantine.size()==3 and after.characters[FROST].loadout.values().map(func(v): return int(v)).has(worn_id),"V-8 the next save keeps the original records as JSON and the kit slot")
	# restore: put the saved original of the worn piece back into the quarantine list, with the data valid again
	var restore_doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(paths.v4))
	var removed: Dictionary={}
	for index in restore_doc.items.size():
		if int(restore_doc.items[index].storage_id)==worn_id:removed=restore_doc.items[index];restore_doc.items.remove_at(index);break
	restore_doc.quarantine.append({"kind":"item","storage_id":worn_id,"reason":"unknown base","since_revision":1,"raw":removed})
	write_text(work+"/v8/restore-v4.json",JSON.stringify(restore_doc,"  "))
	var restored=Profile.new()
	check(restored.configure(work+"/v8/restore-v4.json",true) and int(restored.read_report.get("restored_items",0))==1 and restored.state.quarantine.is_empty() and restored.starting_kit(FROST).gear.size()==restored.loadout(FROST).size()-restored.starting_kit(FROST).kept_slots.size(),"V-8 when the data matches again the set-aside item comes back under the same storage id and its kit slot is live")
	check(worn_original.storage_id==worn_id and restored.state.items.any(func(r): return int(r.storage_id)==worn_id),"V-8 the restored item has its old storage id")
	# unknown character: set aside, kept across a save
	var ghost: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(paths.v4))
	ghost.characters["chapter1.character.ghost"]=ghost.characters[FROST].duplicate(true)
	write_text(work+"/v8/ghost-v4.json",JSON.stringify(ghost,"  "))
	var haunted=Profile.new()
	check(haunted.configure(work+"/v8/ghost-v4.json",true) and haunted.state.quarantine.size()==1 and haunted.state.quarantine[0].kind=="character" and not haunted.characters.has("chapter1.character.ghost"),"V-8 an unknown witch is set aside, not refused")
	check(haunted.wear_outfit(FROST,"") and JSON.parse_string(FileAccess.get_file_as_string(work+"/v8/ghost-v4.json")).quarantine.size()==1,"V-8 the set-aside witch survives a save")

# V-9
func v9_reject_checks() -> void:
	var paths := stage_v3(work+"/v9")
	var profile := open_v3(paths)
	profile.wear_outfit(FROST,SWIM_1);profile.wear_outfit(FROST,"")
	var base_text := FileAccess.get_file_as_string(paths.v4)
	var cases := {
		"top key removed":func(d): d.erase("gambles"),
		"extra top key":func(d): d["equipped"]={},
		"schema 3 number":func(d): d.schema_version=3,
		"duplicate storage id":func(d): d.items[1].storage_id=d.items[0].storage_id,
		"id not below next_id":func(d): d.next_id=1,
		"item record not an object":func(d): d.items[0]=5,
		"witch keys changed":func(d): d.characters[FROST].erase("wardrobe"),
		"witch loadout wrong type":func(d): d.characters[FROST].loadout=[],
		"quarantine kind unknown":func(d): d.quarantine.append({"kind":"mystery","storage_id":9999,"reason":"x","since_revision":1,"raw":{}}),
		"quarantine raw too large":func(d): d.quarantine.append({"kind":"item","storage_id":99999,"reason":"x","since_revision":1,"raw":"x".repeat(9000)}),
		"quarantine id repeats an item":func(d): d.quarantine.append({"kind":"item","storage_id":d.items[0].storage_id,"reason":"x","since_revision":1,"raw":{}}),
		"origin keys":func(d): d.origin.erase("at_unix"),
		"codex shape":func(d): d.codex=[],
	}
	for label in cases:
		var doc: Dictionary=JSON.parse_string(base_text);cases[label].call(doc)
		var target: String=work+"/v9/refused-v4.json"
		write_text(target,JSON.stringify(doc,"  "))
		var before := hashes(work+"/v9")
		var loader=Profile.new()
		check(not loader.configure(target,true) and loader.reject_kind=="incompatible" and hashes(work+"/v9")==before,"V-9 refused as incompatible with the folder unchanged: "+label)
	var many: Dictionary=JSON.parse_string(base_text)
	for i in 326:many.quarantine.append({"kind":"item","storage_id":100000+i,"reason":"x","since_revision":1,"raw":{}})
	many.next_id=200000
	write_text(work+"/v9/many-v4.json",JSON.stringify(many,"  "))
	check(not Profile.new().configure(work+"/v9/many-v4.json",true),"V-9 more than 325 set-aside items are refused (never silently dropped)")
	# a refused v4 file with no readable journal copy: the v3 source is carried over again (T5-D6)
	var d6 := stage_v3(work+"/v9-d6")
	var d6_profile := open_v3(d6)
	d6_profile.wear_outfit(FROST,SWIM_1)
	var broken: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(d6.v4));broken.schema_version=9
	write_text(d6.v4,JSON.stringify(broken,"  "))
	for row in d6_profile.journal_files():write_text(d6_profile.journal_path(String(row.file)),"{ nope")
	var again=Profile.new()
	check(not again.configure(d6.v4,true,"","",d6.pointer,d6.v3) and again.resume_info().get("kind")=="v3_source","V-9 with no readable v4 copy the resume candidate is the schema-3 source carried over again")
	var v3_before := FileAccess.get_sha256(d6.v3)
	check(again.start_fresh_after_reject(true) and again.state.items.size()>=30 and FileAccess.get_sha256(d6.v3)==v3_before,"V-9 starting fresh from it keeps the schema-3 file as it was")

# V-11
func v11_carry_checks() -> void:
	var tables=Profile.loot()
	var rng := RandomNumberGenerator.new();rng.seed=5
	var folder := work+"/v11";Snap.wipe_files(folder)
	var profile=Profile.new();profile.configure(folder+"/p.json",true)
	profile.record_run("lvl-a",[],[],false,1,{"character_id":FROST,"xp_gained":1000,"first_kills":[],"sources":{}})
	profile.record_run("lvl-b",[],[],false,1,{"character_id":FROST,"xp_gained":1000,"first_kills":[],"sources":{}})
	profile.record_run("lvl-c",[],[],false,1,{"character_id":EMBER,"xp_gained":1000,"first_kills":[],"sources":{}})
	var weapon: Dictionary=tables.roll_item(rng,6,"magic","weapon");weapon.uid=11
	var head: Dictionary=tables.roll_item(rng,6,"magic","head");head.uid=12
	var carry := {"character_id":FROST,"equipped":{"weapon":11,"head":12},"kept_slots":[]}
	check(profile.record_run("c-1",[weapon,head],[],false,1,{"character_id":FROST,"xp_gained":0,"first_kills":[],"sources":{}},carry),"V-11 a run that wore new pieces saves")
	var kit: Dictionary=profile.loadout(FROST)
	check(kit.size()==2 and kit.weapon!=kit.head and int(kit.weapon)>=1,"V-11 the new pieces are in her kit under their new storage ids")
	check(profile.loadout(EMBER).is_empty() and profile.loadout(ARC).is_empty(),"V-11 other witches' kits are not touched")
	var stored_weapon: int=kit.weapon
	# next run: she starts with both (storage ids carried), takes the head off and finds a body piece
	var body: Dictionary=tables.roll_item(rng,6,"magic","body");body.uid=23
	var started_weapon: Dictionary=profile.starting_kit(FROST).gear[0].duplicate(true);started_weapon.uid=21
	var started_head: Dictionary=profile.starting_kit(FROST).gear[1].duplicate(true);started_head.uid=22
	check(started_weapon.storage_id==stored_weapon or started_head.storage_id==stored_weapon,"V-11 the starting pieces keep their storage ids")
	var items_before: int=profile.state.items.size()
	check(profile.record_run("c-2",[started_weapon,started_head,body],[],false,1,{},{"character_id":FROST,"equipped":{"weapon":21,"body":23},"kept_slots":[]}),"V-11 second run saves")
	var next_kit: Dictionary=profile.loadout(FROST)
	check(profile.state.items.size()==items_before+1 and next_kit.size()==2 and next_kit.weapon==stored_weapon and next_kit.has("body") and not next_kit.has("head"),"V-11 starting pieces are not stored twice, the removed slot is empty, the new piece is in")
	# kept slots and an empty carry
	var before_text := FileAccess.get_file_as_string(profile.path)
	check(profile.record_run("c-3",[],[],false,1,{},{}) and JSON.stringify(profile.loadout(FROST))==JSON.stringify(next_kit),"V-11 without a carry the kit is unchanged")
	check(profile.record_run("c-4",[],[],false,1,{},{"character_id":FROST,"equipped":{},"kept_slots":["weapon","body"]}) and JSON.stringify(profile.loadout(FROST))==JSON.stringify(next_kit),"V-11 kept slots keep their old value")
	var after_c4 := FileAccess.get_file_as_string(profile.path)
	check(profile.record_run("c-4",[],[],false,1,{},{"character_id":FROST,"equipped":{"weapon":999},"kept_slots":[]}) and FileAccess.get_file_as_string(profile.path)==after_c4,"V-11 the same receipt a second time changes nothing (not even with another carry)")
	# An overlap is not an error: a slot left behind at the start and filled in the run takes what she wore (the run wins).
	var strong: Dictionary=tables.roll_item(rng,12,"rare","ring");strong.uid=41
	check(profile.record_run("k-1",[strong],[],false,1,{},{"character_id":FROST,"equipped":{"ring":41},"kept_slots":[]}),"V-11 a piece above her level is worn in a run and goes into the kit")
	check(profile.starting_kit(FROST).kept_slots.has("ring"),"V-11 that ring slot is left behind at the start")
	var ring_run: Dictionary=tables.roll_item(rng,6,"magic","ring");ring_run.uid=42
	var xp_before: int=int(profile.characters[FROST].xp)
	var overlap_ok: bool=profile.record_run("k-2",[ring_run],[],false,1,{"character_id":FROST,"xp_gained":10,"first_kills":[],"sources":{}},{"character_id":FROST,"equipped":{"ring":42},"kept_slots":["ring"]})
	var ring_sid := -1
	for record in profile.state.items:
		if record.item.slot=="ring" and int(record.storage_id)!=int(next_kit_ring(profile,strong)):ring_sid=int(record.storage_id)
	check(overlap_ok and profile.carry_note=="" and int(profile.characters[FROST].xp)==xp_before+10 and int(profile.loadout(FROST).get("ring",-1))==ring_sid,"V-11 B1: a kept slot filled in the run takes the run's piece, no error, reward saved")
	# A worn set that cannot be validated: the rewards are saved without it, a note code says so, the kit stays as it was.
	var legs: Dictionary=tables.roll_item(rng,6,"magic","feet");legs.uid=31
	var bad_carries := {"unknown uid":{"character_id":FROST,"equipped":{"feet":77},"kept_slots":[]},"slot does not fit":{"character_id":FROST,"equipped":{"head":31},"kept_slots":[]},
		"unknown witch":{"character_id":"chapter1.character.ghost","equipped":{"feet":31},"kept_slots":[]},"other witch than the run":{"character_id":EMBER,"equipped":{"feet":31},"kept_slots":[]},
		"bad slot name":{"character_id":FROST,"equipped":{"tail":31},"kept_slots":[]},"bad kept slot":{"character_id":FROST,"equipped":{},"kept_slots":["tail"]}}
	var count := 0
	for label in bad_carries:
		count+=1
		var kit_text := JSON.stringify(profile.loadout(FROST));var items_n: int=profile.state.items.size();var xp_now: int=int(profile.characters[FROST].xp)
		var receipt := "bad-%d"%count
		var done: bool=profile.record_run(receipt,[legs],[],false,1,{"character_id":FROST,"xp_gained":10,"first_kills":[],"sources":{}},bad_carries[label])
		check(done and profile.carry_note=="kit_not_saved" and receipt in profile.state.receipts and profile.state.items.size()==items_n+1 and int(profile.characters[FROST].xp)==xp_now+10 and JSON.stringify(profile.loadout(FROST))==kit_text,"V-11 B1 invalid carry: rewards saved, kit unchanged, note set: "+label)
		var same_text := FileAccess.get_file_as_string(profile.path)
		check(profile.record_run(receipt,[legs],[],false,1,{"character_id":FROST,"xp_gained":10,"first_kills":[],"sources":{}},bad_carries[label]) and FileAccess.get_file_as_string(profile.path)==same_text and profile.state.receipts.count(receipt)==1,"V-11 B1 the same receipt again pays nothing twice: "+label)
	# the pending list cannot be worn: same rule
	var kit_pending := JSON.stringify(profile.loadout(FROST))
	check(profile.record_run("bad-pending",[],[legs],false,1,{},{"character_id":FROST,"equipped":{"feet":31},"kept_slots":[]}) and profile.carry_note=="kit_not_saved" and JSON.stringify(profile.loadout(FROST))==kit_pending and "bad-pending" in profile.state.receipts,"V-11 an item still in the pending list cannot be in the kit; the rewards are saved")
	# QA paths with ".." are refused
	var sneaky=Profile.new()
	check(not sneaky.configure("res://_local/../outside.json",true) and sneaky.error_code=="isolated_path_invalid" and not sneaky.configure("res://_local/a/../../x.json",true,"res://_local/ok.json"),"QA paths holding .. are refused")

func next_kit_ring(profile: RefCounted,strong: Dictionary) -> int:
	# storage id of the first ring piece (the strong one stored by record k-1)
	for record in profile.state.items:
		if record.item.slot=="ring" and int(record.item.required_level)>profile.character_level(FROST):return int(record.storage_id)
	return -1

# V-12
func v12_kit_checks() -> void:
	var tables=Profile.loot()
	var rng := RandomNumberGenerator.new();rng.seed=9
	var profile=Profile.new();profile.configure(work+"/v12/p.json",true)
	for who in [FROST,EMBER]:
		profile.record_run("x-"+who,[],[],false,1,{"character_id":who,"xp_gained":1000,"first_kills":[],"sources":{}})
		profile.record_run("y-"+who,[],[],false,1,{"character_id":who,"xp_gained":1000,"first_kills":[],"sources":{}})
	var piece: Dictionary=tables.roll_item(rng,6,"magic","weapon");piece.uid=1
	check(profile.record_run("w",[piece],[],false,1),"V-12 a piece is stored")
	var sid: int=profile.state.items[0].storage_id
	check(profile.select_item(sid,FROST) and profile.loadout(FROST).weapon==sid and profile.loadout(EMBER).is_empty(),"V-12 equipping for frost leaves ember's kit as it was")
	check(profile.select_item(sid,EMBER) and profile.loadout(EMBER).weapon==sid and profile.loadout(FROST).weapon==sid,"V-12 one piece can be in two kits (T5-U2)")
	check(not profile.select_item(sid,"") and not profile.select_item(sid,"chapter1.character.ghost"),"V-12 select_item needs a known witch")
	check(profile.unselect("weapon",FROST) and profile.loadout(EMBER).weapon==sid and profile.loadout(FROST).is_empty(),"V-12 taking it off one witch leaves the other")
	check(profile.select_item(sid,FROST) and profile.salvage(sid) and profile.loadout(FROST).is_empty() and profile.loadout(EMBER).is_empty(),"V-12 salvaging removes the piece from every kit")

# V-13
func v13_outfit_checks() -> void:
	var profile=Profile.new();profile.configure(work+"/v13/p.json",true)
	var view: Dictionary=profile.wardrobe_view(FROST)
	check(view.owned==[SWIM_1,"chapter1.outfit.frost.swim_2"] and view.worn=="","V-13 the first collection is owned from the start, the plain outfit is worn")
	check(profile.wear_outfit(FROST,SWIM_1) and profile.wardrobe_view(FROST).worn==SWIM_1 and profile.wardrobe_view(ARC).worn=="","V-13 an outfit is worn per witch")
	var saved := FileAccess.get_file_as_string(profile.path)
	check(profile.wear_outfit(FROST,SWIM_1) and FileAccess.get_file_as_string(profile.path)==saved,"V-13 wearing what is already worn writes nothing")
	check(not profile.wear_outfit(FROST,"chapter1.outfit.nothing.swim_9") and not profile.wear_outfit(FROST,SWIM_ARC) and not profile.wear_outfit("chapter1.character.ghost",SWIM_1) and FileAccess.get_file_as_string(profile.path)==saved,"V-13 an unknown outfit, another witch's outfit and an unknown witch are refused, file unchanged")
	check(profile.wear_outfit(FROST,"") and profile.wardrobe_view(FROST).worn=="","V-13 the plain outfit again")
	check(not profile.grant_outfit(FROST,SWIM_ARC) and profile.grant_outfit(FROST,SWIM_1),"V-13 grant_outfit knows the witch's outfits only; an owned one is a no-op")
	# an id the data does not know is kept through a read and a save, the screen ignores it
	var doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(profile.path))
	doc.characters[FROST].wardrobe.owned=["chapter1.outfit.frost.future_1"];doc.characters[FROST].wardrobe.worn="chapter1.outfit.frost.future_1"
	write_text(work+"/v13/future-v4.json",JSON.stringify(doc,"  "))
	var future=Profile.new()
	check(future.configure(work+"/v13/future-v4.json",true) and int(future.read_report.get("unknown_ids",0))==2 and future.wardrobe_view(FROST).worn=="" and not "chapter1.outfit.frost.future_1" in future.wardrobe_view(FROST).owned,"V-13 an unknown outfit id is counted and not shown")
	check(future.wear_outfit(FROST,"") and JSON.parse_string(FileAccess.get_file_as_string(work+"/v13/future-v4.json")).characters[FROST].wardrobe.owned==["chapter1.outfit.frost.future_1"],"V-13 the unknown id survives a save")

# V-14
func v14_story_checks() -> void:
	var profile=Profile.new();profile.configure(work+"/v14/p.json",true)
	check(not profile.mark_story_seen(FROST,"beat.one") and not profile.mark_shared_seen("beat.shared"),"V-14 without data ids nothing is known: refused")
	Profile.use_ids_for_test({"story":["beat.one"],"shared":["beat.shared"],"collectibles":["item.coin"]})
	check(profile.mark_story_seen(FROST,"beat.one") and profile.mark_shared_seen("beat.shared"),"V-14 a known beat is recorded")
	var journals: int=profile.journal_files().size();var text := FileAccess.get_file_as_string(profile.path)
	check(profile.mark_story_seen(FROST,"beat.one") and profile.mark_shared_seen("beat.shared") and profile.journal_files().size()==journals and FileAccess.get_file_as_string(profile.path)==text,"V-14 a second time writes nothing (journal count unchanged)")
	check(not profile.mark_story_seen(FROST,"beat.two") and not profile.mark_story_seen("chapter1.character.ghost","beat.one"),"V-14 unknown ids are refused")
	var progress := {"character_id":FROST,"xp_gained":10,"first_kills":[],"sources":{},"collectibles_found":["item.coin","item.coin"]}
	check(profile.record_run("s-1",[],[],false,1,progress) and profile.characters[FROST].story.found==["item.coin"],"V-14 a known collectible is recorded once")
	var refused_progress := {"character_id":FROST,"xp_gained":10,"first_kills":[],"sources":{},"collectibles_found":["item.unknown"]}
	var before := FileAccess.get_file_as_string(profile.path)
	check(not profile.record_run("s-2",[],[],false,1,refused_progress) and FileAccess.get_file_as_string(profile.path)==before,"V-14 an unknown collectible refuses the save")
	var doc: Dictionary=JSON.parse_string(before)
	doc.characters[FROST].story.seen.append("beat.from_the_future")
	write_text(work+"/v14/future-v4.json",JSON.stringify(doc,"  "))
	Profile.use_ids_for_test({})
	var future=Profile.new()
	check(future.configure(work+"/v14/future-v4.json",true) and "beat.from_the_future" in future.characters[FROST].story.seen and future.wear_outfit(FROST,SWIM_1) and "beat.from_the_future" in JSON.parse_string(FileAccess.get_file_as_string(work+"/v14/future-v4.json")).characters[FROST].story.seen,"V-14 a stored id the data no longer knows is kept through a save")

# V-15: whatever was read passes the strict write rule
func v15_invariant_checks() -> void:
	var accepted := 0;var refused := 0
	for name in Snap.SCENARIOS:
		var spec: Dictionary=Snap.SCENARIOS[name]
		var folder: String=work+"/v15-"+String(name);Snap.wipe_files(folder)
		for source in spec.files:Snap.copy_bytes(FIXTURES+"/"+source,folder+"/"+String(spec.files[source]))
		if spec.get("journals",false):
			for file_name in Snap.journal_names(FIXTURES):Snap.copy_bytes(FIXTURES+"/"+Snap.JOURNAL_DIR+"/"+file_name,folder+"/"+file_name)
		var profile=Profile.new()
		var ok := false
		match String(spec.mode):
			"v3":ok=profile.configure(folder+"/chapter-one-profile-v4.json",true,"","","",folder+"/"+Snap.MAIN)
			"v3pointer":ok=profile.configure(folder+"/chapter-one-profile-v4.json",true,"","","",folder+"/"+Snap.MAIN,folder+"/"+Snap.POINTER)
			"v2":ok=profile.configure(folder+"/chapter-one-profile-v4.json",true,folder+"/chapter-one-profile-v2.json")
			"v1":ok=profile.configure(folder+"/chapter-one-profile-v4.json",true,"",folder+"/chapter-one-profile-v1.json")
		if not ok:refused+=1;continue
		var document: Dictionary=profile._document(profile.state,profile.characters,profile._words)
		check(not Profile.read_document(document,true).is_empty(),"V-15 what was read from %s passes the strict write rule"%name)
		accepted+=1
	check(accepted==7 and refused==0,"V-15 all seven frozen scenarios were read (%d, refused %d)"%[accepted,refused])
	var compat := FileAccess.get_file_as_string(COMPAT)
	if not compat.is_empty():
		var parsed: Variant=JSON.parse_string(compat)
		var read := Profile.read_document(parsed,false)
		check(not read.is_empty() and not Profile.read_document(Profile.new()._document(read.state,read.characters,read.words),true).is_empty(),"V-15 the v4 compatibility file passes the strict write rule after being read")

# V-17: the compatibility file is made once and every later build must read it without a single fix
func v17_compat_checks() -> void:
	if "--write-compat" in OS.get_cmdline_user_args():
		if FileAccess.file_exists(COMPAT):
			check(false,"V-17 refusing to overwrite the compatibility file");return
		var paths := stage_v3(work+"/v17")
		var profile := open_v3(paths)
		profile.wear_outfit(FROST,SWIM_1)
		profile.wear_outfit(EMBER,"chapter1.outfit.ember.swim_2")
		var out := FileAccess.open(COMPAT,FileAccess.WRITE);out.store_string(FileAccess.get_file_as_string(paths.v4));out.close()
	check(FileAccess.file_exists(COMPAT),"V-17 the compatibility file exists")
	if not FileAccess.file_exists(COMPAT):return
	var target := work+"/v17-read/profile.json"
	write_text(target,FileAccess.get_file_as_string(COMPAT))
	var reader=Profile.new()
	check(reader.configure(target,true) and reader.read_report.is_empty() and reader.state.quarantine.is_empty() and reader.state.items.size()>=30,"V-17 the compatibility file reads with no fix at all")
	var doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(COMPAT))
	check(int(doc.schema_version)==4 and doc.origin.from_schema==3 and doc.characters[FROST].wardrobe.worn==SWIM_1 and doc.characters[EMBER].wardrobe.worn=="chapter1.outfit.ember.swim_2" and doc.characters[FROST].loadout.size()==8,"V-17 the compatibility file has the carried-over kit and the worn outfits")

# The reserved tree_reset slot
func reset_checks() -> void:
	var profile=Profile.new();profile.configure(work+"/reset/p.json",true)
	profile.wear_outfit(FROST,SWIM_1)
	var doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(profile.path))
	check(doc.characters[FROST].tree_reset.granted==[] and doc.characters[FROST].tree_reset.used==[],"tree_reset: two empty lists in a fresh entry")
	doc.characters[FROST].tree_reset={"granted":["d1","d1"],"used":["d1","d2"]}
	write_text(work+"/reset/odd-v4.json",JSON.stringify(doc,"  "))
	var odd=Profile.new()
	check(odd.configure(work+"/reset/odd-v4.json",true) and odd.characters[FROST].tree_reset.granted==["d1","d2"] and odd.characters[FROST].tree_reset.used==["d1","d2"] and int(odd.read_report.get("tree_reset_fixed",0))==1 and int(odd.read_report.get("deduped",0))==1,"tree_reset: duplicates become one, an id only in `used` is added to `granted`")
	check(Profile.read_document(doc,true).is_empty(),"tree_reset: used without granted and duplicates are refused by the write rule")
	doc.characters[FROST].tree_reset={"granted":["Bad Id"],"used":[]}
	write_text(work+"/reset/bad-v4.json",JSON.stringify(doc,"  "))
	check(not Profile.new().configure(work+"/reset/bad-v4.json",true),"tree_reset: an id of a wrong shape refuses the file")

# loot.gd's new word helpers
func loot_checks() -> void:
	var tables=Profile.loot()
	check(tables.rare_word_ids("서리 맹세")==["f01","s01"] and tables.rare_word_ids("서리")==[] and tables.rare_word_ids("서리 맹세 손길")==[] and tables.rare_word_ids("맹세 서리")==[],"loot: rare_word_ids finds exactly one word from each list")
	check(tables.rare_name_for(["f01","s01"])=="서리 맹세" and tables.rare_name_for(["f01","s99"])=="서리 s99" and tables.rare_words_known(["f01","s01"]) and not tables.rare_words_known(["f01","s99"]),"loot: rare_name_for shows an unknown id as itself")
	var bad: Dictionary=tables.data.duplicate(true)
	bad.rare_names.second[0].id="f01"
	check(not tables._check_rare_names(bad.rare_names).is_empty(),"loot: a repeated rare word id is refused by the data check")
	bad=tables.data.duplicate(true)
	bad.rare_names.first[0].name="two words"
	check(not tables._check_rare_names(bad.rare_names).is_empty(),"loot: a rare word with a space is refused by the data check")
