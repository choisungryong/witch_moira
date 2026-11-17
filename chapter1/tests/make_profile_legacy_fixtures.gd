extends SceneTree
## One-shot generator (T5-S0). Run it ONCE with the schema-3 code, before schema 4 lands:
##   python tools/dev/godot.py --headless --path . --script res://chapter1/tests/make_profile_legacy_fixtures.gd
## It makes every profile with the real chapter_profile.gd under res://_local/profile-legacy-make/, copies the
## results byte for byte into chapter1/tests/fixtures/profile_legacy/ and writes expected_v3.json.
## It refuses to run when the fixtures already exist (they are never regenerated; pass --force only with the director's approval).
## It never touches the user folder: every path is res://_local/ or the fixture folder.
const Profile=preload("res://chapter1/core/chapter_profile.gd")
const Items=preload("res://chapter1/core/chapter_items.gd")
const Snap=preload("res://chapter1/tests/profile_legacy_snapshot.gd")
const OUT := "res://chapter1/tests/fixtures/profile_legacy"
const WORK := "res://_local/profile-legacy-make"
const FROST := "chapter1.character.frost"
const EMBER := "chapter1.character.ember"
var failures: Array[String]=[]

func _initialize() -> void:call_deferred("execute")

func need(ok: bool,message: String) -> void:
	if not ok:failures.append(message);push_error(message)

func write_text(target: String,text: String) -> void:
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	var handle := FileAccess.open(target,FileAccess.WRITE)
	handle.store_string(text);handle.close()

func progress(who: String,xp: int,kills: Array=[]) -> Dictionary:
	return {"character_id":who,"xp_gained":xp,"first_kills":kills,"sources":{},"level_before":1,"level_after":1}

func find_item(profile: RefCounted,slot: String,quality: String,v1: bool,skip: Array) -> int:
	for record in profile.state.items:
		var item: Dictionary=record.item
		if item.slot==slot and (quality.is_empty() or item.quality==quality) and item.has("grammar")!=v1 and not int(record.storage_id) in skip:return int(record.storage_id)
	return 0

func execute() -> void:
	var force := "--force" in OS.get_cmdline_user_args()
	if FileAccess.file_exists(OUT+"/expected_v3.json") and not force:
		print("PROFILE_LEGACY_MAKE refused: fixtures already exist (they are never regenerated)");quit(2);return
	Snap.wipe_files(WORK+"/full");Snap.wipe_files(WORK+"/journals");Snap.wipe_files(WORK+"/fresh")
	var tables: RefCounted=Profile.loot()
	var rng := RandomNumberGenerator.new();rng.seed=20261117
	# ---- v3_full: the real profile, built through its own functions
	var main := WORK+"/full/"+Snap.MAIN
	var full=Profile.new()
	need(full.configure(main,true),"full: configure")
	var inventory: Array=[]
	var index := 0
	for slot in tables.data.slots:
		for quality in ["common","magic","rare","legendary"]:
			inventory.append(tables.roll_item(rng,4+((index*3)%9),quality,slot));index+=1
	for extra in 6:inventory.append(tables.roll_item(rng,8+extra%5,"rare",""))
	for unique_id in ["ash_bloom","winter_heart","forked_covenant"]:inventory.append(tables.make_unique(unique_id,12))
	inventory.append(Items.roll(rng,8,"rare","weapon"))
	inventory.append(Items.unique(1,9))
	need(inventory.size()<=65,"inventory bound")
	need(full.record_run("s0-run-1",inventory,[],true,30000,progress(FROST,1000,["champion:0","champion:1","boss"])),"full: run 1 "+full.error)
	need(full.record_run("s0-run-2",[],[],true,28000,progress(FROST,1000)),"full: run 2")
	need(full.record_run("s0-run-3",[],[],true,29500,progress(FROST,1000)),"full: run 3")
	need(full.record_run("s0-run-4",[],[],false,5000,progress(EMBER,700)),"full: run 4")
	need(full.commit_tree(FROST,{"witch.frost.needle":3,"witch.frost.rime":1}),"full: commit 1 "+full.error)
	need(full.respec(FROST),"full: respec "+full.error)
	need(full.commit_tree(FROST,{"witch.frost.needle":3,"witch.frost.volley":1,"witch.frost.rime":2}),"full: commit 2 "+full.error)
	# one salvage leaves a gap in the storage ids and gives essence
	var spare := find_item(full,"feet","common",false,[])
	need(spare>0 and full.salvage(spare),"full: salvage")
	var used: Array=[]
	var plan := [["weapon","legendary",false],["head","rare",false],["body","magic",false],["hands","rare",false],["feet","",false],["charm","",true],["ring","unique",false],["ring","rare",false]]
	for row in plan:
		var id_ := find_item(full,row[0],row[1],row[2],used)
		if id_==0:id_=find_item(full,row[0],"",row[2],used)
		need(id_>0,"full: pick "+str(row))
		used.append(id_)
		need(full.select_item(id_),"full: select "+str(row)+" "+full.error)
	need(full.state.equipped.size()==8 and full.state.equipped.has("ring2"),"full: eight slots")
	need(full.state.items.size()>=30,"full: item count")
	var rares := 0;var legends := 0;var uniques := 0;var v1_count := 0
	var cells := {}
	for record in full.state.items:
		var item: Dictionary=record.item
		if not item.has("grammar"):v1_count+=1;continue
		cells[item.slot+"/"+item.quality]=true
		match item.quality:
			"rare":rares+=1
			"legendary":legends+=1
			"unique":uniques+=1
	need(rares>=5 and legends>=1 and uniques>=1 and v1_count==2,"full: rare %d legendary %d unique %d v1 %d"%[rares,legends,uniques,v1_count])
	print("PROFILE_LEGACY_MAKE full items=%d rare=%d legendary=%d unique=%d v1=%d slot/quality cells=%d"%[full.state.items.size(),rares,legends,uniques,v1_count,cells.size()])
	var full_text := FileAccess.get_file_as_string(main)
	write_text(OUT+"/v3_full.json",full_text)
	# ---- rare names edited in the text (not re-serialised, so every number stays an integer)
	var rare_names: Array[String]=[]
	for record in full.state.items:
		if record.item.has("grammar") and record.item.quality=="rare":rare_names.append(String(record.item.name))
	var old_name := ""
	var three_name := ""
	for candidate in rare_names:
		if full_text.count('"name": "'+candidate+'"')==1 and candidate.count(" ")==1:
			if old_name.is_empty():old_name=candidate
			elif three_name.is_empty():three_name=candidate
	need(not old_name.is_empty() and not three_name.is_empty(),"two distinct rare names")
	var old_text := full_text.replace('"name": "'+old_name+'"','"name": "'+"새벽녘 "+old_name.get_slice(" ",1)+'"')
	var three_text := full_text.replace('"name": "'+three_name+'"','"name": "'+three_name+" 의식"+'"')
	need(old_text!=full_text and three_text!=full_text,"rare edits applied")
	write_text(OUT+"/v3_rare_oldword.json",old_text)
	write_text(OUT+"/v3_rare_threeword.json",three_text)
	# ---- v2: the schema-2 shape of the same profile (a subset of items, six slots)
	var v2_state: Dictionary=full.state.duplicate(true)
	var keep: Array=[]
	for slot in v2_state.equipped:keep.append(int(v2_state.equipped[slot]))
	var extra := 0
	var kept_items: Array=[]
	for record in v2_state.items:
		if int(record.storage_id) in keep:kept_items.append(record)
		elif extra<6:kept_items.append(record);extra+=1
	v2_state.items=kept_items;v2_state.schema_version=2;v2_state.revision=11;v2_state.completed_runs=7;v2_state.erase("characters")
	write_text(OUT+"/v2_sample.json",JSON.stringify(v2_state,"  "))
	# ---- v1: four slots, v1 items only
	var v1_items: Array=[]
	var v1_slots := {}
	var v1_rolls := [["weapon",8],["body",9],["charm",10],["ring",8]]
	for i in v1_rolls.size():
		v1_items.append({"storage_id":i+1,"item":Items.roll(rng,int(v1_rolls[i][1]),"rare",String(v1_rolls[i][0]))});v1_slots[String(v1_rolls[i][0])]=i+1
	v1_items.append({"storage_id":5,"item":Items.unique(1,9)})
	write_text(OUT+"/v1_sample.json",JSON.stringify({"schema_version":1,"revision":3,"next_id":6,"items":v1_items,"equipped":v1_slots,"completed_runs":2,"best_ticks":20000,"essence":5,"receipts":["old"]},"  "))
	# ---- journals: four real saves, journal names normalised (pid/usec removed), main edited so it is refused
	var jmain := WORK+"/journals/"+Snap.MAIN
	var jp=Profile.new()
	need(jp.configure(jmain,true),"journals: configure")
	for n in 4:
		var drops: Array=[tables.roll_item(rng,6+n,"rare",""),tables.roll_item(rng,6+n,"magic","")]
		need(jp.record_run("s0-j-%d"%(n+1),drops,[],n%2==0,20000+n*100,progress(FROST,300 if n==0 else 0,["champion:0"] if n==0 else [])),"journals: run %d %s"%[n+1,jp.error])
	var journal_rows: Array=jp.journal_files()
	need(journal_rows.size()==4,"journals: four copies, got %d"%journal_rows.size())
	for row in journal_rows:
		var rev_text := "%06d"%int(row.number)
		var normalised := "chapter-one-profile-v3.revision-"+rev_text+"-0-0.json"
		need(DirAccess.rename_absolute(WORK+"/journals/"+String(row.file),WORK+"/journals/"+normalised)==OK,"journals: rename")
	var jtext := FileAccess.get_file_as_string(jmain)
	var tampered := jtext
	var finder := RegEx.create_from_string('"(damage_bps|cooldown_bps|max_hp_raw)": ([0-9]+)')
	var hit := finder.search(jtext)
	need(hit!=null,"journals: a stat to edit")
	if hit!=null:tampered=jtext.substr(0,hit.get_start())+'"'+hit.get_string(1)+'": '+str(int(hit.get_string(2))+777)+jtext.substr(hit.get_end())
	write_text(jmain,tampered)
	var refused=Profile.new()
	var pointer := WORK+"/journals/"+Snap.POINTER
	need(not refused.configure(jmain,true,"","",pointer) and refused.reject_kind=="incompatible","journals: main refused as incompatible (kind %s)"%refused.reject_kind)
	refused.stamp_override="20261117-120000"
	need(refused.start_fresh_after_reject(true),"journals: fresh save "+refused.error)
	# ---- copy the folder out byte for byte (the new file's own journal copy stays in _local)
	var dir := DirAccess.open(WORK+"/journals")
	dir.list_dir_begin()
	var entry := dir.get_next()
	var copied: Array[String]=[]
	while not entry.is_empty():
		if not dir.current_is_dir() and not entry.begins_with("chapter-one-profile-v3-r20261117-120000.revision-") and not ".next-" in entry:
			need(Snap.copy_bytes(WORK+"/journals/"+entry,OUT+"/"+Snap.JOURNAL_DIR+"/"+entry),"copy "+entry);copied.append(entry)
		entry=dir.get_next()
	dir.list_dir_end()
	print("PROFILE_LEGACY_MAKE journal folder: ",copied)
	# ---- expected values and the sha256 list, from the copied fixtures read by the current code
	var scenarios := {}
	for name in Snap.SCENARIOS:scenarios[name]=Snap.run_scenario(name,OUT,WORK+"/fresh/"+name)
	var hashes := {}
	for file_name in ["v3_full.json","v3_rare_oldword.json","v3_rare_threeword.json","v2_sample.json","v1_sample.json"]:hashes[file_name]=FileAccess.get_sha256(OUT+"/"+file_name)
	for file_name in copied:hashes[Snap.JOURNAL_DIR+"/"+file_name]=FileAccess.get_sha256(OUT+"/"+Snap.JOURNAL_DIR+"/"+file_name)
	var expected := {"format":1,"note":"Produced by the schema-3 code before schema 4. Never regenerate.","sha256":hashes,"scenarios":scenarios}
	write_text(OUT+"/expected_v3.json",JSON.stringify(expected,"  "))
	print("PROFILE_LEGACY_MAKE ",JSON.stringify({"failures":failures,"files":hashes.size()}))
	quit(0 if failures.is_empty() else 1)
