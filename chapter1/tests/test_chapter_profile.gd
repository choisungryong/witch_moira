extends SceneTree
## Profile checks (schema 4). Every check of the schema-3 file is here again, moved to schema 4; where the rule changed
## (an item that does not match the data is set aside instead of refusing the file, a broken investment is returned
## instead of refusing, the worn set is per witch) the check says what it asserts now. The mapping from each old check to
## its schema-4 form is in the S1 report. Only isolated paths under res://_local/ are used.
const Profile=preload("res://chapter1/core/chapter_profile.gd")
const Items=preload("res://chapter1/core/chapter_items.gd")
const Chapter=preload("res://chapter1/core/chapter_core.gd")
var checks := 0
var failures: Array[String]=[]
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
const FROST := "chapter1.character.frost"
const EMBER := "chapter1.character.ember"
const NEEDLE := "witch.frost.needle"
const SWIM_1 := "chapter1.outfit.frost.swim_1"
func _initialize() -> void:call_deferred("execute")
func write_text(file_path: String,text: String) -> void:
	DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())
	var f := FileAccess.open(file_path,FileAccess.WRITE);f.store_string(text);f.close()
func progress(xp: int,kills: Array=[],who: String=FROST) -> Dictionary:
	return {"character_id":who,"xp_gained":xp,"first_kills":kills,"sources":{},"level_before":1,"level_after":1}
## A schema-2 document (the old shape) from a v4 memory state and one witch's worn set.
func as_v2(source: Dictionary,worn: Dictionary) -> Dictionary:
	return {"schema_version":2,"revision":source.revision,"next_id":source.next_id,"items":source.items.duplicate(true),"equipped":worn.duplicate(true),
		"completed_runs":source.completed_runs,"best_ticks":source.best_ticks,"essence":source.essence,"receipts":source.receipts.duplicate()}
func v2_fresh() -> Dictionary:
	return {"schema_version":2,"revision":0,"next_id":1,"items":[],"equipped":{},"completed_runs":0,"best_ticks":0,"essence":0,"receipts":[]}
## A v4 file made from a real saved profile with `mutate` applied to its parsed document; the file must be refused and stay as written.
func refused(base_text: String,target: String,mutate: Callable,label: String) -> void:
	var doc: Dictionary=JSON.parse_string(base_text);mutate.call(doc)
	var text := JSON.stringify(doc,"  ");write_text(target,text)
	var loader=Profile.new()
	check(not loader.configure(target,true) and FileAccess.get_file_as_string(target)==text and not loader.available,label)
## The same, but the file is accepted with the investment returned (T5-D2): ranks empty, the notice on, nothing written by the read.
func returned(base_text: String,target: String,mutate: Callable,label: String) -> void:
	var doc: Dictionary=JSON.parse_string(base_text);mutate.call(doc)
	var text := JSON.stringify(doc,"  ");write_text(target,text)
	var loader=Profile.new()
	var ok: bool=loader.configure(target,true)
	check(ok and loader.available and loader.characters[FROST].ranks.is_empty() and loader.notices.has(FROST) and int(loader.read_report.get("refunded_trees",0))==1 and FileAccess.get_file_as_string(target)==text,label)
func g1_checks(directory: String,tables: RefCounted,rng: RandomNumberGenerator,v2_state: Dictionary) -> void:
	var root := directory+"/g1"
	# 1. v2 file -> v4 file; the v2 bytes never change.
	var old_v2: Dictionary=v2_state.duplicate(true);old_v2.completed_runs=7;old_v2.revision=4
	var v2_path := root+"/legacy/profile-v2.json";write_text(v2_path,JSON.stringify(old_v2,"  "))
	var v2_bytes := FileAccess.get_file_as_string(v2_path)
	var up=Profile.new();var v4_path := root+"/up/profile-v4.json"
	check(up.configure(v4_path,true,v2_path) and up.imported_from_v2 and up.characters.has(FROST) and int(up.characters[FROST].xp)==5000 and not FileAccess.file_exists(v4_path),"v2 profile is read into memory: 7 runs migrate as 5 runs of xp, nothing written yet")
	check(up.unselect("weapon",FROST) and FileAccess.file_exists(v4_path) and not up.imported_from_v2 and FileAccess.get_file_as_string(v2_path)==v2_bytes,"First save writes the v4 file and leaves the v2 bytes untouched")
	var v4_doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(v4_path))
	check(int(v4_doc.schema_version)==4 and int(v4_doc.revision)==5 and v4_doc.characters.has(FROST) and not v4_doc.characters[FROST].has("level"),"v4 file: schema 4, revision continues, level is not stored")
	var up_again=Profile.new();check(up_again.configure(v4_path,true,v2_path) and up_again.state==up.state and up_again.characters==up.characters and not up_again.imported_from_v2,"v4 file reads back identically and wins over the v2 file")
	check(Profile.normalize(v4_doc).is_empty(),"A schema-4 document is not accepted by the schema-2 normalizer")
	# 2. v1 only
	var v1_path := root+"/legacy/profile-v1.json"
	write_text(v1_path,JSON.stringify({"schema_version":1,"revision":3,"next_id":2,"items":[{"storage_id":1,"item":Items.roll(rng,8,"rare","weapon")}],"equipped":{"weapon":1},"completed_runs":2,"best_ticks":20000,"essence":5,"receipts":["old"]}))
	var v1_bytes := FileAccess.get_file_as_string(v1_path)
	var from_v1=Profile.new();var v1_target := root+"/from-v1/profile-v4.json"
	check(from_v1.configure(v1_target,true,"",v1_path) and from_v1.imported_from_v1 and int(from_v1.characters[FROST].xp)==2000,"v1 only: read into memory with 2 runs of xp")
	check(from_v1.unselect("weapon",FROST) and FileAccess.file_exists(v1_target) and FileAccess.get_file_as_string(v1_path)==v1_bytes,"v1 is carried into the v4 file and its bytes stay")
	# 3/4. Experience pays once per receipt, a first kill pays once per witch
	var run_path := root+"/runs/profile.json";var runs=Profile.new();runs.configure(run_path,true)
	check(runs.record_run("g1-a",[],[],true,100,progress(640,["champion:0"])) and int(runs.characters[FROST].xp)==640,"record_run stores experience with the run's receipt in one write")
	var after_first := FileAccess.get_file_as_string(run_path)
	check(runs.record_run("g1-a",[],[],true,100,progress(640,["champion:0"])) and FileAccess.get_file_as_string(run_path)==after_first and int(runs.characters[FROST].xp)==640,"Same receipt twice pays experience once")
	check(runs.record_run("g1-b",[],[],true,100,progress(640,["champion:0"])) and int(runs.characters[FROST].xp)==1280,"A second run adds its own experience")
	var view: Dictionary=runs.character_view(FROST)
	check(runs.characters[FROST].first_rewards==["champion:0"] and int(view.level)==4 and int(view.points_earned)==4 and int(view.points_free)==4,"Same first kill in two runs earns one point (Lv 4 = 3 + 1)")
	check(int(view.xp_level_start)==1000 and int(view.xp_for_next)==1500 and int(view.xp_to_next)==220,"character_view reports the level's xp window")
	check(not runs.record_run("g1-bad",[],[],true,100,progress(1001)) and not runs.record_run("g1-bad",[],[],true,100,progress(5,["nope"])) and not runs.record_run("g1-bad",[],[],true,100,progress(5,[],"chapter1.character.ghost")) and int(runs.characters[FROST].xp)==1280,"Out-of-range or unknown progress is refused and changes nothing")
	var base_text := FileAccess.get_file_as_string(run_path)
	# 5-7. forged investment: the file is read and the points are returned (T5-D2); the file itself is not touched by the read
	returned(base_text,root+"/bad/overspent.json",func(d): d.characters[FROST].ranks={NEEDLE:5},"Spent points above earned points: accepted, investment returned, notice on")
	returned(base_text,root+"/bad/orphan.json",func(d): d.characters[FROST].xp=25000;d.characters[FROST].ranks={"witch.frost.volley":1},"Broken prerequisite (volley 1 without needle): investment returned")
	returned(base_text,root+"/bad/level.json",func(d): d.characters[FROST].xp=1280;d.characters[FROST].ranks={NEEDLE:2,"witch.frost.volley":1},"Node above the character level: investment returned")
	# the same documents are refused by the strict write rule
	var strict_doc: Dictionary=JSON.parse_string(base_text);strict_doc.characters[FROST].ranks={NEEDLE:5}
	check(Profile.read_document(strict_doc,true).is_empty(),"Write rule: an overspent investment is refused strictly")
	# 12. a witch without a tree cannot hold ranks
	returned_ember(base_text,root+"/bad/ember.json")
	var dup_text := JSON.stringify(_mutated(base_text,func(d): d.characters[FROST].first_rewards=["boss","boss"]),"  ");write_text(root+"/bad/duplicate-reward.json",dup_text)
	var dup_loader=Profile.new()
	check(dup_loader.configure(root+"/bad/duplicate-reward.json",true) and dup_loader.characters[FROST].first_rewards==["boss"] and int(dup_loader.read_report.get("deduped",0))==1,"Duplicate first-kill receipt: read as one (deduped, counted)")
	check(Profile.read_document(_mutated(base_text,func(d): d.characters[FROST].first_rewards=["boss","boss"]),true).is_empty(),"Write rule: a duplicate first-kill receipt is refused strictly")
	refused(base_text,root+"/bad/extra-key.json",func(d): d.characters[FROST]["level"]=4,"Stored level key rejected")
	var unknown_text := JSON.stringify(_mutated(base_text,func(d): d.characters[FROST].first_rewards=["boss","future_reward"]),"  ");write_text(root+"/bad/unknown-reward.json",unknown_text)
	var unknown_loader=Profile.new()
	check(unknown_loader.configure(root+"/bad/unknown-reward.json",true) and "future_reward" in unknown_loader.characters[FROST].first_rewards and int(unknown_loader.read_report.get("unknown_ids",0))==1,"An unknown first-kill id is kept (T5 principle 5) and counted")
	# 8. tree_revision mismatch: ranks come back on read, the next save writes them empty
	var stale_path := root+"/stale/profile.json"
	var stale_doc: Dictionary=JSON.parse_string(base_text);stale_doc.characters[FROST].xp=2000;stale_doc.characters[FROST].ranks={NEEDLE:2};stale_doc.characters[FROST].tree_revision=9
	write_text(stale_path,JSON.stringify(stale_doc,"  "))
	check(Profile.read_document(stale_doc,true).is_empty(),"Write rule: stale tree_revision rejected strictly")
	var stale=Profile.new();var stale_view: Dictionary={}
	check(stale.configure(stale_path,true),"Read rule: stale tree_revision file is accepted")
	stale_view=stale.character_view(FROST)
	check(stale_view.ranks.is_empty() and stale_view.refunded_notice and int(stale_view.points_free)==int(stale_view.points_earned),"Stale tree ranks are returned and the notice is on")
	check(stale.record_run("g1-stale",[],[],false,1) and JSON.parse_string(FileAccess.get_file_as_string(stale_path)).characters[FROST].ranks.is_empty() and int(JSON.parse_string(FileAccess.get_file_as_string(stale_path)).characters[FROST].tree_revision)==1,"Next save writes the emptied ranks with the current revision")
	# 9. commit_tree
	var tree_path := root+"/tree/profile.json";var tree=Profile.new();tree.configure(tree_path,true)
	check(tree.record_run("g1-t",[],[],true,1,progress(1000)) and tree.record_run("g1-t2",[],[],true,1,progress(1000)) and tree.commit_tree(FROST,{NEEDLE:3,"witch.frost.rime":1}),"commit_tree stores a legal staged tree")
	var tree_again=Profile.new();tree_again.configure(tree_path,true)
	check(tree_again.characters==tree.characters and int(tree_again.character_view(FROST).points_spent)==4 and int(tree_again.build_for(FROST).ranks[NEEDLE])==3,"Committed tree survives a fresh instance")
	var before_bad := FileAccess.get_file_as_string(tree_path)
	check(not tree.commit_tree(FROST,{NEEDLE:5}) and not tree.commit_tree(FROST,{NEEDLE:2}) and not tree.commit_tree(EMBER,{NEEDLE:1}) and FileAccess.get_file_as_string(tree_path)==before_bad,"Over-spending, lowering a committed rank and a tree-less witch are refused without a write")
	var build: Dictionary=tree.build_for(FROST)
	check(build.tree_id=="witch.frost" and int(build.tree_revision)==1 and int(build.character_level)==5 and int(build.character_xp)==2000 and build.character_id==FROST,"build_for matches the core's build format (spec 7.1)")
	check(tree.build_for(EMBER).tree_id=="" and tree.build_for(EMBER).ranks.is_empty(),"A witch without a tree gets an empty build")
	# 10. respec
	var item: Dictionary=tables.roll_item(rng,8,"rare","weapon");item.uid=900
	check(tree.record_run("g1-loot",[item],[],false,1) and tree.salvage(int(tree.state.items[0].storage_id)) and int(tree.state.essence)==8,"Essence for the respec checks")
	tree.respec_cost_override=3
	check(tree.respec_cost(FROST)==12 and not tree.respec(FROST) and tree.error_code=="essence_short" and int(tree.state.essence)==8 and int(tree.character_view(FROST).points_spent)==4,"Respec refused when essence is short, nothing changes")
	tree.respec_cost_override=2
	check(tree.respec(FROST) and int(tree.state.essence)==0 and tree.characters[FROST].ranks.is_empty() and int(tree.characters[FROST].respecs)==1,"Respec costs essence per point and clears the ranks")
	tree.respec_cost_override=-1
	check(not tree.respec(FROST),"Respec with nothing invested is refused")
	check(tree.commit_tree(FROST,{NEEDLE:4}) and tree.respec(FROST) and int(tree.state.essence)==0,"Verification-period cost is 0")
	# 11. another run saved first
	var race_path := root+"/race/profile.json";var one=Profile.new();one.configure(race_path,true);one.record_run("g1-r",[],[],true,1,progress(1000));one.record_run("g1-r2",[],[],true,1,progress(1000))
	var two=Profile.new();two.configure(race_path,true)
	check(one.commit_tree(FROST,{NEEDLE:1}) and not two.commit_tree(FROST,{NEEDLE:2}) and two.error_code=="save_changed_elsewhere" and two.error_args.is_empty(),"commit_tree is refused after another run saved first")
	# level-gated gear: a piece worn in a run above her level goes into her kit (T5 8.2) and stays behind at the start
	var gate=Profile.new();gate.configure(root+"/gate/profile.json",true)
	var strong: Dictionary=tables.roll_item(rng,12,"rare","weapon");strong.uid=901
	check(gate.record_run("g1-gate",[strong],[],false,1,progress(0),{"character_id":FROST,"equipped":{"weapon":901},"kept_slots":[]}) and int(gate.state.items[0].item.required_level)>1,"A high-level piece is stored and goes into the witch's kit")
	var need := int(gate.state.items[0].item.required_level)
	check(not gate.select_item(int(gate.state.items[0].storage_id),"") and gate.error_code=="unknown_character","select_item without a witch is refused")
	gate.unselect("weapon",FROST)
	check(not gate.select_item(int(gate.state.items[0].storage_id),FROST) and gate.error_code=="level_required" and int(gate.error_args.n)>1,"select_item refuses a piece above the witch's level")
	check(gate.record_run("g1-gate-2",[],[],false,1,progress(0),{"character_id":FROST,"equipped":{},"kept_slots":[]}),"A save with an empty worn set is allowed")
	var kit_gate=Profile.new();kit_gate.configure(root+"/gate2/profile.json",true)
	var strong_b: Dictionary=tables.roll_item(rng,12,"rare","weapon");strong_b.uid=902
	kit_gate.record_run("g1-gate-b",[strong_b],[],false,1,progress(0),{"character_id":FROST,"equipped":{"weapon":902},"kept_slots":[]})
	check(kit_gate.starting_gear(FROST).is_empty() and kit_gate.blocked_gear(FROST).size()==1 and int(kit_gate.blocked_gear(FROST)[0].required_level)==need and kit_gate.starting_kit(FROST).kept_slots==["weapon"],"A selected piece above the level stays selected but is left behind and reported")
	var pure := Profile.apply_progress({},progress(100,["boss"],EMBER))
	check(int(pure[EMBER].xp)==100 and int(pure[EMBER].tree_revision)==0 and pure[EMBER].first_rewards==["boss"],"apply_progress is pure and works for a witch without a tree")
func _mutated(base_text: String,mutate: Callable) -> Dictionary:
	var doc: Dictionary=JSON.parse_string(base_text);mutate.call(doc)
	return doc
func returned_ember(base_text: String,target: String) -> void:
	var doc: Dictionary=JSON.parse_string(base_text)
	var entry: Dictionary=Profile.default_entry(EMBER);entry.xp=2000;entry.ranks={NEEDLE:1}
	doc.characters[EMBER]=entry
	write_text(target,JSON.stringify(doc,"  "))
	var loader=Profile.new()
	check(loader.configure(target,true) and loader.characters[EMBER].ranks.is_empty() and loader.notices.has(EMBER),"Ember entry with ranks: accepted, ranks returned (she has no tree)")
## D5: equipment text is not identity, and a refused file is never touched.
func file_hashes(dir_path: String) -> Dictionary:
	var result := {}
	var dir := DirAccess.open(dir_path)
	if dir==null:return result
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if not dir.current_is_dir():result[entry]=FileAccess.get_sha256(dir_path+"/"+entry)
		elif entry=="revisions":
			for inner in file_hashes(dir_path+"/revisions"):result["revisions/"+inner]=file_hashes(dir_path+"/revisions")[inner]
		entry=dir.get_next()
	dir.list_dir_end()
	return result
func same_files(before: Dictionary,dir_path: String) -> bool:
	var now := file_hashes(dir_path)
	for key in before:
		if not now.has(key) or now[key]!=before[key]:return false
	return true
func d5_base(root: String,tables: RefCounted,rng: RandomNumberGenerator,history: bool) -> Dictionary:
	var main := root+"/profile.json";var pointer := root+"/active.json"
	var maker=Profile.new();var ok: bool=maker.configure(main,true,"","",pointer)
	var unique: Dictionary=tables.make_unique("winter_heart",12);unique.uid=1
	var magic: Dictionary=tables.roll_item(rng,2,"magic","weapon");magic.uid=2
	var rare: Dictionary=tables.roll_item(rng,12,"rare","head");rare.uid=3
	ok=ok and maker.record_run("d5-a",[unique,magic,rare],[],false,10,{},{"character_id":FROST,"equipped":{"weapon":2},"kept_slots":[]})
	if history:
		ok=ok and maker.unselect("weapon",FROST) and maker.wear_outfit(FROST,SWIM_1) and maker.wear_outfit(FROST,"")
	return {"main":main,"pointer":pointer,"ok":ok,"unique":unique,"magic":magic,"rare":rare,"root":root}
func mutate_file(target: String,mutate: Callable) -> void:
	var doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(target));mutate.call(doc)
	write_text(target,JSON.stringify(doc,"  "))
func tamper_stats(doc: Dictionary) -> void:
	var stats: Dictionary=doc.items[1].item.stats
	var key: String=stats.keys()[0];stats[key]=int(stats[key])+777
## Breaks the structure of a v4 file (two items with one storage id), which still refuses the whole file.
func break_ids(doc: Dictionary) -> void:
	doc.items[1].storage_id=doc.items[0].storage_id
func rename_items(doc: Dictionary) -> void:
	doc.items[0].item["name"]="old name";doc.items[0].item["description"]="old description"
	doc.items[1].item["name"]="changed magic name"
	doc.items[2].item.erase("rare_words");doc.items[2].item["legacy_name"]="three word rare name"
func d5_checks(directory: String,tables: RefCounted,rng: RandomNumberGenerator) -> void:
	var root := directory+"/d5"
	# P-1 / P-2 / P-5: text found in a file is dropped on read, the file is not touched, the next save writes none.
	var a := d5_base(root+"/a",tables,rng,false)
	check(a.ok,"P-0 d5 fixture profile saved")
	var data_unique: Dictionary=tables.make_unique("winter_heart",12)
	var data_magic: String=a.magic.name
	mutate_file(a.main,rename_items)
	var renamed_bytes := FileAccess.get_file_as_string(a.main);var before_a := file_hashes(root+"/a")
	var reader=Profile.new()
	var read_ok: bool=reader.configure(a.main,true,"","",a.pointer)
	check(read_ok and reader.available and reader.state.items[0].item.name==data_unique.name and reader.state.items[0].item.description==data_unique.description and reader.state.items[1].item.name==data_magic and reader.state.items[2].item.name=="three word rare name" and int(reader.read_report.get("stripped_text",0))==2,"P-1 text in a file is dropped; unique and magic text follow the data, the old rare name is kept as legacy_name")
	check(FileAccess.get_file_as_string(a.main)==renamed_bytes and file_hashes(root+"/a")==before_a,"P-1 reading changes no file")
	var gear: Array[Dictionary]=reader.starting_gear(FROST);var fresh_run=Chapter.new();fresh_run.start(5)
	check(gear.size()==1 and gear[0].name==data_magic and fresh_run.import_starting_gear(gear),"P-5 starting gear carries the current name and imports")
	var journals_before: int=reader.journal_files().size()
	var saved_ok: bool=reader.unselect("weapon",FROST)
	var journals_after: int=reader.journal_files().size()
	var older_same := true
	for key in before_a:
		if String(key).begins_with("revisions/") and (not FileAccess.file_exists(root+"/a/"+String(key)) or FileAccess.get_sha256(root+"/a/"+String(key))!=before_a[key]):older_same=false
	check(saved_ok and journals_after==journals_before+1 and older_same,"P-2 one save adds one journal copy and leaves earlier copies byte for byte")
	var saved_doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(a.main))
	check(not saved_doc.items[0].item.has("name") and not saved_doc.items[1].item.has("name") and not saved_doc.items[1].item.has("description") and saved_doc.items[2].item.legacy_name=="three word rare name","P-2 the saved file holds no name or description; the legacy rare name stays")
	# P-3: a changed number is set aside (T5-D1), the file is read, its bytes stay.
	var b := d5_base(root+"/b",tables,rng,false)
	mutate_file(b.main,tamper_stats)
	var b_bytes := FileAccess.get_file_as_string(b.main);var before_b := file_hashes(root+"/b")
	var bad=Profile.new()
	check(bad.configure(b.main,true,"","",b.pointer) and bad.available and bad.state.quarantine.size()==1 and int(bad.state.quarantine[0].storage_id)==2 and bad.state.items.size()==2 and int(bad.read_report.get("quarantined_items",0))==1,"P-3 forged stats: the file is read, that one item is set aside with its original record")
	check(FileAccess.get_file_as_string(b.main)==b_bytes and file_hashes(root+"/b")==before_b,"P-3 the file and the folder are unchanged by the read")
	check(bad.loadout(FROST).get("weapon")==2 and bad.starting_kit(FROST).gear.is_empty() and bad.starting_kit(FROST).kept_slots==["weapon"],"P-3 the kit still points at the set-aside piece but it does not go along")
	# P-4: damaged, oversize, legacy.
	var c_dir := root+"/c";write_text(c_dir+"/broken.json","{ not json")
	var damaged=Profile.new();var before_c := file_hashes(c_dir)
	check(not damaged.configure(c_dir+"/broken.json",true) and damaged.reject_kind=="damaged" and damaged.reject_reason=="json" and file_hashes(c_dir)==before_c,"P-4 broken JSON is damaged, nothing changes")
	write_text(c_dir+"/huge.json"," ".repeat(2000001));before_c=file_hashes(c_dir)
	var huge=Profile.new()
	check(not huge.configure(c_dir+"/huge.json",true) and huge.reject_kind=="damaged" and huge.reject_reason=="size" and file_hashes(c_dir)==before_c,"P-4 oversize file is damaged, nothing changes")
	write_text(c_dir+"/old-v2.json",'{"schema_version":2}');before_c=file_hashes(c_dir)
	var legacy=Profile.new()
	check(not legacy.configure(c_dir+"/absent-v4.json",true,c_dir+"/old-v2.json") and legacy.reject_kind=="legacy" and file_hashes(c_dir)==before_c and not FileAccess.file_exists(c_dir+"/absent-v4.json"),"P-4 refused schema-2 file is legacy, nothing is created")
	var v2_sha := FileAccess.get_sha256(c_dir+"/old-v2.json")
	check(legacy.reject_source==c_dir+"/old-v2.json" and legacy.path==c_dir+"/absent-v4.json" and FileAccess.get_sha256(c_dir+"/old-v2.json")==v2_sha and file_hashes(c_dir)==before_c,"P-4 reject_source is the refused schema-2 file, not the absent v4 path; file bytes unchanged")
	check(damaged.reject_source==c_dir+"/broken.json" and huge.reject_source==c_dir+"/huge.json","P-4 reject_source of a refused v4 file is that file")
	# P-6 / P-7 / P-8: a fresh save from the newest readable journal copy.
	var d := d5_base(root+"/d",tables,rng,true)
	var scout=Profile.new();scout.configure(d.main,true,"","",d.pointer)
	var d_journals: Array=scout.journal_files()
	check(d.ok and d_journals.size()==4,"P-6 fixture has four journal copies (%d)"%d_journals.size())
	var third: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(scout.journal_path(String(d_journals[1].file))))
	check(int(third.revision)==3 and third.characters[FROST].loadout.is_empty(),"P-6 the second newest copy is revision 3 with nothing selected")
	mutate_file(scout.journal_path(String(d_journals[0].file)),break_ids)
	mutate_file(d.main,break_ids)
	var before_d := file_hashes(root+"/d")
	var refused_d=Profile.new()
	check(not refused_d.configure(d.main,true,"","",d.pointer) and refused_d.reject_kind=="incompatible","P-6 newest copy and main file are both refused")
	var latest: Dictionary=refused_d.latest_readable_revision()
	check(int(latest.get("revision",0))==3 and String(latest.get("file",""))==String(d_journals[1].file),"P-6 latest readable copy is revision 3")
	check(refused_d.start_fresh_after_reject(true) and refused_d.available and refused_d.path!=d.main and refused_d.path.get_file().begins_with("chapter-one-profile-v4-r") and int(refused_d.state.revision)==4 and refused_d.state.items.size()==3 and refused_d.loadout(FROST).is_empty(),"P-6 new save starts from revision 3 and continues at revision 4")
	var after_d := file_hashes(root+"/d")
	var unchanged := true
	for key in before_d:
		if not after_d.has(key) or after_d[key]!=before_d[key]:unchanged=false
	check(unchanged,"P-6 refused file and every journal copy are byte for byte the same")
	var pointer_doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(d.pointer))
	check(pointer_doc.file==refused_d.path.get_file() and pointer_doc.replaces=="profile.json" and pointer_doc.from_revision==String(d_journals[1].file) and pointer_doc.kind=="incompatible","P-6 pointer names the new file, the refused file and the journal copy")
	var reopened_d=Profile.new()
	check(reopened_d.configure(d.main,true,"","",d.pointer) and reopened_d.path==refused_d.path and reopened_d.state==refused_d.state,"P-7 a new reader follows the pointer to the new file")
	var plain_d=Profile.new()
	check(not plain_d.configure(d.main,true) and plain_d.reject_kind=="incompatible" and unchanged,"P-7 without the pointer the original is still refused and unchanged")
	var pointer_bytes := FileAccess.get_file_as_string(d.pointer)
	var ignored := true
	for bad_name in ["../x.json","C:/x.json","/abs.json","other.json","chapter-one-profile-v4-r1/../x.json","chapter-one-profile-v4-r99999999-999999.json","chapter-one-profile-v3-r20261117-120000.json"]:
		write_text(d.pointer,JSON.stringify({"schema":1,"file":bad_name}))
		var text_now := FileAccess.get_file_as_string(d.pointer)
		var trial=Profile.new()
		if trial.configure(d.main,true,"","",d.pointer) or trial.path!=d.main or FileAccess.get_file_as_string(d.pointer)!=text_now:ignored=false
	check(ignored,"P-8 a pointer naming a path, another pattern, another schema or a missing file is ignored; the pointer is not rewritten")
	write_text(d.pointer,pointer_bytes)
	var name_rule := RegEx.create_from_string(Profile.FRESH_NAME_PATTERN)
	check(name_rule.search("chapter-one-profile-v4-r20261117-070000-2.json")!=null and name_rule.search("chapter-one-profile-v4-r1.json\n")==null and name_rule.search("chapter-one-profile-v3-r1.json")==null,"L1 the pointer name rule accepts the fresh-save names and refuses a trailing line break and the v3 name")
	# M1: the resume candidate is found once, when the file is refused, and is not looked for again.
	var resume_before: Dictionary=refused_d.resume_info()
	check(int(resume_before.get("revision",0))==3 and String(resume_before.get("file",""))==String(d_journals[1].file),"M1 the refused profile carries its resume candidate")
	write_text(scout.journal_path(String(d_journals[1].file)),"garbage now")
	check(refused_d.resume_info()==resume_before,"M1 resume_info() is cached: it does not read the journal copies again")
	# M1: only the newest 64 journal copies are scanned.
	var g := d5_base(root+"/g",tables,rng,false)
	var long_maker=Profile.new();long_maker.configure(g.main,true,"","",g.pointer)
	var long_ok := true
	for i in 36:long_ok=long_ok and long_maker.wear_outfit(FROST,SWIM_1) and long_maker.wear_outfit(FROST,"")
	var g_files: Array=long_maker.journal_files()
	check(long_ok and g_files.size()>Profile.MAX_JOURNAL_SCAN+2,"M1 fixture has more journal copies than the scan limit (%d)"%g_files.size())
	for k in g_files.size()-1:mutate_file(long_maker.journal_path(String(g_files[k].file)),break_ids)
	mutate_file(g.main,break_ids)
	var capped=Profile.new()
	check(not capped.configure(g.main,true,"","",g.pointer) and capped.resume_info().is_empty(),"M1 a readable copy older than the newest 64 is not searched for")
	# P-9: no readable copy -> empty save; an existing file is never overwritten.
	var e := d5_base(root+"/e",tables,rng,true)
	var e_scout=Profile.new();e_scout.configure(e.main,true,"","",e.pointer)
	for row in e_scout.journal_files():mutate_file(e_scout.journal_path(String(row.file)),break_ids)
	mutate_file(e.main,break_ids)
	var squatters := {}
	for squat_name in ["chapter-one-profile-v4-r20000101-000000.json","chapter-one-profile-v4-r20000101-000000-2.json"]:
		var squat: String=e.root+"/"+squat_name
		write_text(squat,"keep me "+squat_name);squatters[squat]=FileAccess.get_sha256(squat)
	var before_e := file_hashes(root+"/e")
	var refused_e=Profile.new()
	check(not refused_e.configure(e.main,true,"","",e.pointer) and refused_e.latest_readable_revision().is_empty() and refused_e.resume_info().is_empty(),"P-9 every copy is refused")
	refused_e.stamp_override="20000101-000000"
	check(refused_e.start_fresh_after_reject(true) and refused_e.path.ends_with("r20000101-000000-3.json") and int(refused_e.state.revision)==1 and refused_e.state.items.is_empty(),"P-9 empty save takes the first free name (-3) when the plain and -2 names are taken")
	var squatters_same := true
	for squat in squatters:
		if FileAccess.get_sha256(squat)!=squatters[squat]:squatters_same=false
	check(squatters_same and same_files(before_e,root+"/e"),"P-9 files already there stay byte for byte the same")
	# P-10: only an old format refused -> empty v4 at the normal path, old file untouched, no pointer.
	var f_dir := root+"/f";write_text(f_dir+"/old-v2.json",'{"schema_version":2}')
	var old_bytes := FileAccess.get_file_as_string(f_dir+"/old-v2.json")
	var only_old=Profile.new()
	check(not only_old.configure(f_dir+"/profile-v4.json",true,f_dir+"/old-v2.json","",f_dir+"/active.json") and only_old.reject_kind=="legacy","P-10 refused old format")
	check(only_old.start_fresh_after_reject(false) and FileAccess.file_exists(f_dir+"/profile-v4.json") and FileAccess.get_file_as_string(f_dir+"/old-v2.json")==old_bytes and not FileAccess.file_exists(f_dir+"/active.json"),"P-10 empty v4 created at the normal path, old file unchanged, no pointer")
	var after_old=Profile.new()
	check(after_old.configure(f_dir+"/profile-v4.json",true,f_dir+"/old-v2.json","",f_dir+"/active.json") and after_old.available,"P-10 the new v4 file reads back")
	# A save that was never refused cannot be replaced.
	var healthy=Profile.new();healthy.configure(a.main,true,"","",a.pointer)
	check(not healthy.start_fresh_after_reject(true),"A readable profile refuses start_fresh_after_reject")
func execute() -> void:
	# Safety (S1): the checks only run on the isolated user folder and an isolated fixture folder.
	if not OS.get_user_data_dir().replace("\\","/").contains("/_local/appdata/"):
		print("CHAPTER_PROFILE_TEST ",JSON.stringify({"checks":0,"failures":["user data dir is not isolated: refusing to run"]}));quit(1);return
	var directory := "res://_local/profile-fixtures-01"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture-dir="):directory=arg.trim_prefix("--fixture-dir=")
	if not directory.begins_with("res://_local/"):
		print("CHAPTER_PROFILE_TEST ",JSON.stringify({"checks":0,"failures":["fixture dir must be under res://_local/"]}));quit(1);return
	check(not DirAccess.dir_exists_absolute(directory),"Fresh isolated fixture directory")
	if DirAccess.dir_exists_absolute(directory):quit(1);return
	DirAccess.make_dir_recursive_absolute(directory)
	var profile=Profile.new()
	check(Profile.PATH_V4.begins_with("user://"),"Product profile lives in the user directory; tests only use isolated fixture paths")
	check(profile.configure(directory+"/profile.json",true),"New QA profile configured")
	var rng := RandomNumberGenerator.new();rng.seed=44
	var item: Dictionary=Items.roll(rng,8,"rare","weapon");item.uid=3
	check(profile.record_run("run-one",[item],[],true,21000),"Atomic reward save")
	check(profile.state.items.size()==1 and profile.state.completed_runs==1,"Owned loot and completion saved")
	var first_text := FileAccess.get_file_as_string(profile.path)
	check(profile.record_run("run-one",[item],[],true,21000) and FileAccess.get_file_as_string(profile.path)==first_text,"Receipt repeat is exact no-op")
	var reopened=Profile.new();check(reopened.configure(profile.path,true),"JSON numeric canonicalization reload")
	check(reopened.state==profile.state,"Roundtrip state equality")
	var id_: int=reopened.state.items[0].storage_id
	check(reopened.record_run("run-xp",[],[],false,1,progress(1000)) and reopened.record_run("run-xp2",[],[],false,1,progress(1000)),"Experience for the witch so the piece fits her level")
	check(reopened.select_item(id_,FROST),"Select persistent gear")
	var gear: Array[Dictionary]=reopened.starting_gear(FROST);check(gear.size()==1 and gear[0].storage_id==id_,"Selected gear carries persistent identity")
	var run=Chapter.new();run.start(4)
	check(run.import_starting_gear(gear) and run.inventory.size()==1,"Fresh run imports selected gear")
	check(run.hero.hp_raw==run.hero.max_hp_raw and run.tick==0,"Fresh-boundary full health")
	run.tick=1;check(not run.import_starting_gear(gear),"Mid-run gear import forbidden")
	check(reopened.record_run("run-two",run.inventory,[],false,100),"Defeat saves without duplicating existing gear")
	check(reopened.state.items.size()==1 and reopened.state.completed_runs==1,"Starter gear not duplicated and defeat not completed")
	check(not profile.wear_outfit(FROST,SWIM_1) and profile.error_code=="save_changed_elsewhere","Stale writer refused and external save preserved")
	check(reopened.salvage(id_) and reopened.state.items.is_empty() and reopened.loadout(FROST).is_empty() and reopened.state.essence==8,"Explicit salvage clears the kit reference and records reward")
	var broken := v2_fresh();broken.items=[{"storage_id":1,"item":Items.unique(0,5)}];broken.next_id=2;broken.equipped={"body":1}
	check(Profile.normalize(broken).is_empty(),"Wrong-slot equipped reference rejected")
	broken.equipped={};broken.items[0].item.stats.damage_bps=999999
	check(Profile.normalize(broken).is_empty(),"Forged stat range rejected")
	broken.items[0].item=Items.unique(0,5);broken.items[0].item.stats.damage_bps=1200
	check(Profile.normalize(broken).is_empty(),"Forged valid-range unique identity rejected")
	var corrupt_path := directory+"/corrupt.json";var f := FileAccess.open(corrupt_path,FileAccess.WRITE);f.store_string("{bad profile");f.close()
	var bad=Profile.new();check(not bad.configure(corrupt_path,true),"Corrupt profile refused")
	check(not bad.record_run("attempt",[item],[],true,1) and FileAccess.get_file_as_string(corrupt_path)=="{bad profile","Corrupt bytes not overwritten")
	# Capacity fixture exercises bounded recovery, not normal loot generation.
	var full=Profile.new();full.configure(directory+"/full.json",true)
	var candidate := Profile.fresh()
	for i in 256:candidate.items.append({"storage_id":i+1,"item":Items.unique(i%3,5)})
	candidate.next_id=257
	check(full._persist(candidate),"Nominal256 stash persists")
	var inventory: Array=[];var pending: Array=[]
	for i in 65:inventory.append(Items.unique(i%3,5))
	for i in 4:pending.append(Items.unique(i%3,5))
	check(full.record_run("full-recovery",inventory,pending,true,22000) and full.state.items.size()==325,"All69 final rewards preserved at full stash")
	check(full.state.items.size()>256,"Recovery requires sorting before next run")
	var recovered=Profile.new();check(recovered.configure(full.path,true) and recovered.state.items.size()==325,"Full recovery roundtrip")
	var revision_count := 0;var dir := DirAccess.open(directory+"/revisions")
	for name in dir.get_files():
		if name.contains(".revision-"):revision_count+=1
	check(revision_count>=6,"Prior immutable revisions remain (in the revisions folder)")
	# Schema 2: grammar-v2 items, eight equip slots, two rings, and the one-way v1 import.
	var tables=Profile.loot()
	var v2=Profile.new();check(v2.configure(directory+"/v2.json",true),"v2 profile configured")
	var haul: Array=[]
	for slot in ["weapon","head","body","hands","feet","charm","ring","ring"]:
		var piece: Dictionary=tables.roll_item(rng,8,"rare",slot);piece.uid=100+haul.size();piece.position=Vector2.ZERO;piece.collected=true;haul.append(piece)
	var legend: Dictionary=tables.roll_item(rng,8,"legendary","weapon");legend.uid=200;haul.append(legend)
	check(v2.record_run("run-v2",haul,[],false,100,progress(1000)) and v2.record_run("run-v2b",[],[],false,1,progress(1000)) and v2.state.items.size()==9,"Grammar-v2 items of every slot and a legendary are stored")
	for record in v2.state.items.duplicate(true):
		if record.item.quality!="legendary":v2.select_item(int(record.storage_id),FROST)
	check(v2.loadout(FROST).size()==8 and v2.loadout(FROST).has("ring2") and v2.loadout(FROST).ring!=v2.loadout(FROST).ring2,"Eight slots filled, two different rings")
	var v2_again=Profile.new();check(v2_again.configure(v2.path,true) and v2_again.state==v2.state,"v2 profile reloads identically")
	var kit: Array[Dictionary]=v2_again.starting_gear(FROST)
	var run8=Chapter.new();run8.start(5)
	check(kit.size()==8 and run8.import_starting_gear(kit) and run8.equipped.size()==8,"A run starts wearing all eight pieces")
	check(run8.hero.speed>run8.BASE_SPEED,"Boots raise move speed")
	var twice: Dictionary=as_v2(v2_again.state,v2_again.loadout(FROST));twice.equipped.ring2=twice.equipped.ring
	check(Profile.normalize(twice).is_empty(),"One ring cannot fill both ring slots")
	var misplaced: Dictionary=as_v2(v2_again.state,v2_again.loadout(FROST));misplaced.equipped.head=misplaced.equipped.feet
	check(Profile.normalize(misplaced).is_empty(),"Boots cannot be worn on the head")
	var forged_v2: Dictionary=as_v2(v2_again.state,v2_again.loadout(FROST));forged_v2.items[0].item.stats.damage_bps=29000
	check(Profile.normalize(forged_v2).is_empty(),"Forged v2 stat rejected")
	var ring_id: int=v2_again.loadout(FROST).ring2
	check(v2_again.salvage(ring_id) and not v2_again.loadout(FROST).has("ring2") and v2_again.loadout(FROST).has("ring"),"Salvaging the second ring frees only that slot")
	var old_text := JSON.stringify({"schema_version":1,"revision":3,"next_id":3,"items":[{"storage_id":1,"item":Items.roll(rng,8,"rare","weapon")},{"storage_id":2,"item":Items.unique(1,9)}],"equipped":{"weapon":1,"charm":2},"completed_runs":2,"best_ticks":20000,"essence":5,"receipts":["old"]})
	var carried=Profile.new();check(carried.configure(directory+"/carried.json",true) and carried.import_v1_text(old_text),"Schema-1 profile is read")
	check(carried.imported_from_v1 and carried.state.schema_version==4 and carried.state.items.size()==2 and carried.loadout(FROST).size()==2 and carried.state.completed_runs==2,"Imported state keeps items, selection and progress")
	check(not FileAccess.file_exists(carried.path),"Import alone writes nothing")
	check(carried.select_item(1,FROST) and carried.salvage(2) and FileAccess.file_exists(carried.path) and not carried.imported_from_v1,"First change after import saves a schema-4 file")
	var carried_again=Profile.new();check(carried_again.configure(carried.path,true) and carried_again.state.items.size()==1 and carried_again.state.essence==30,"Carried profile reloads from its own file")
	var refuse=Profile.new();refuse.configure(directory+"/refuse.json",true)
	check(not refuse.import_v1_text('{"schema_version":2}') and not refuse.import_v1_text("not json") and not refuse.imported_from_v1,"Non-v1 or broken text is refused as an import")
	check(Profile.normalize(JSON.parse_string(old_text)).is_empty(),"A schema-1 document is not accepted as schema 2 without the import step")
	g1_checks(directory,tables,rng,as_v2(v2.state,v2.loadout(FROST)))
	d5_checks(directory,tables,rng)
	if "--negative" in OS.get_cmdline_user_args():check(false,"Intentional checker failure")
	print("CHAPTER_PROFILE_TEST ",JSON.stringify({"checks":checks,"failures":failures,"fixtures":directory,"scope":"New isolated profile fixture files only; old equipment/progress not read or written"}))
	quit(0 if failures.is_empty() else 1)
