extends SceneTree
## One-shot generator (T6-S0). Run it ONCE with the schema-4 code, before schema 5 lands:
##   python tools/dev/godot.py --headless --path . --script res://chapter1/tests/make_profile_v4_fixtures.gd
## It makes every profile with the real chapter_profile.gd under res://_local/profile-v4-make/, copies the results
## byte for byte into chapter1/tests/fixtures/profile_v4/ and writes expected_v4.json.
## It refuses to run (exit 1) when expected_v4.json already exists: the fixtures are never regenerated.
## It never touches the user folder: every path is res://_local/ or the fixture folder.
const Profile=preload("res://chapter1/core/chapter_profile.gd")
const Snap=preload("res://chapter1/tests/profile_v4_snapshot.gd")
const OUT := "res://chapter1/tests/fixtures/profile_v4"
const WORK := "res://_local/profile-v4-make"
const LEGACY_V3 := "res://chapter1/tests/fixtures/profile_legacy/v3_full.json"
const FROST := "chapter1.character.frost"
const EMBER := "chapter1.character.ember"
const ARC := "chapter1.character.arc"
const GHOST := "chapter1.character.ghost"
const STAMP_DAY := "20261119"
var failures: Array[String]=[]

func _initialize() -> void:call_deferred("execute")

func need(ok: bool,message: String) -> void:
	if not ok:failures.append(message);push_error(message)

func write_text(target: String,text: String) -> void:
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	var handle := FileAccess.open(target,FileAccess.WRITE)
	handle.store_string(text);handle.close()

func progress(who: String,xp: int,collectibles: Array=[]) -> Dictionary:
	return {"character_id":who,"xp_gained":xp,"first_kills":[],"sources":{},"level_before":1,"level_after":1,"collectibles_found":collectibles}

func worn_ids(profile: RefCounted) -> Dictionary:
	var worn := {}
	for witch in Snap.WITCHES:
		for slot in profile.loadout(witch):worn[int(profile.loadout(witch)[slot])]=true
	return worn

## Indices (in state.items) of grammar-2 items no witch wears.
func spare_indices(profile: RefCounted) -> Array[int]:
	var worn := worn_ids(profile)
	var result: Array[int]=[]
	for index in range(profile.state.items.size()-1,-1,-1):
		var record: Dictionary=profile.state.items[index]
		if record.item.has("grammar") and not worn.has(int(record.storage_id)):result.append(index)
	return result

func make_full() -> void:
	var main := WORK+"/full/"+Snap.MAIN
	var v3 := WORK+"/full/chapter-one-profile-v3.json"
	need(Snap.copy_bytes(LEGACY_V3,v3),"full: copy the schema-3 fixture")
	var tables: RefCounted=Profile.loot()
	var rng := RandomNumberGenerator.new();rng.seed=20261119
	Profile.use_ids_for_test({"story":["beat.one","beat.two"],"shared":["beat.shared"],"collectibles":["item.coin"]})
	var p=Profile.new()
	need(p.configure(main,true,"","","",v3) and p.imported_from_v3,"full: configure carries v3_full over")
	# runs: equipment (a unique and a legendary fill the codex), experience for all three witches, a collectible found by frost
	var drops: Array=[tables.make_unique("ash_bloom",12),tables.roll_item(rng,10,"legendary","weapon"),tables.roll_item(rng,9,"rare","body"),tables.roll_item(rng,7,"magic","head"),tables.roll_item(rng,6,"common","hands"),tables.roll_item(rng,8,"rare","")]
	need(p.record_run("s0v4-1",drops,[],true,26000,progress(FROST,500,["item.coin"])),"full: run 1 "+p.error)
	need(p.record_run("s0v4-2",[],[],false,4000,progress(EMBER,200)),"full: run 2 "+p.error)
	need(p.record_run("s0v4-3",[],[],true,31000,progress(ARC,100)),"full: run 3 "+p.error)
	# outfits: every outfit in outfits.json is owned from the start, so wearing is what is saved
	need(p.wear_outfit(FROST,"chapter1.outfit.frost.swim_1") and p.wear_outfit(EMBER,"chapter1.outfit.ember.swim_2"),"full: outfits "+p.error)
	need(p.mark_story_seen(FROST,"beat.one") and p.mark_story_seen(FROST,"beat.two") and p.mark_story_seen(EMBER,"beat.one"),"full: story "+p.error)
	need(p.mark_shared_seen("beat.shared"),"full: shared story "+p.error)
	# a different worn kit for each witch
	need(p.unselect("feet",FROST) and p.unselect("head",EMBER) and p.unselect("hands",EMBER) and p.unselect("charm",ARC) and p.unselect("ring2",ARC),"full: loadouts "+p.error)
	need(p.loadout(FROST)!=p.loadout(EMBER) and p.loadout(EMBER)!=p.loadout(ARC) and p.loadout(FROST)!=p.loadout(ARC),"full: three different loadouts")
	# fields no function writes yet are edited in the file text, then read and saved again by the real code
	var spare := spare_indices(p)
	need(spare.size()>=4,"full: four spare items, got %d"%spare.size())
	var doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(main))
	doc.items[spare[0]].locked=true
	doc.items[spare[1]].new=true
	var shown_ids := [int(doc.items[spare[0]].storage_id),int(doc.items[spare[1]].storage_id),int(doc.items[spare[2]].storage_id)]
	doc.items[spare[2]].item.base_id="chapter1.base.vanished_for_the_fixture"
	doc.characters[FROST].depth_cleared={"d1":1}
	doc.characters[FROST].wardrobe.owned=["chapter1.outfit.frost.swim_2"]
	doc.characters[FROST].tree_reset={"granted":["d1"],"used":[]}
	doc.characters[GHOST]=doc.characters[FROST].duplicate(true)
	write_text(main,JSON.stringify(doc,"  "))
	var edited=Profile.new()
	need(edited.configure(main,true),"full: the edited file is read "+edited.error)
	need(int(edited.read_report.get("quarantined_items",0))==1 and int(edited.read_report.get("quarantined_characters",0))==1,"full: one item and one witch set aside "+JSON.stringify(edited.read_report))
	var worn := String(edited.wardrobe_view(FROST).worn)
	need(not worn.is_empty() and edited.wear_outfit(FROST,"") and edited.wear_outfit(FROST,worn),"full: two saves "+edited.error)
	# what the saved file holds
	var final_text := FileAccess.get_file_as_string(main)
	var reader=Profile.new()
	need(reader.configure(main,true) and reader.read_report.is_empty(),"full: the finished file reads with no fix "+JSON.stringify(reader.read_report))
	need(reader.state.quarantine.size()==2,"full: quarantine holds the item and the witch")
	need(reader.characters[FROST].depth_cleared=={"d1":1} and reader.characters[FROST].tree_reset.granted==["d1"],"full: depth_cleared and tree_reset kept")
	need(reader.characters[FROST].story.seen.size()==2 and reader.characters[FROST].story.found==["item.coin"] and reader.state.shared_story.seen==["beat.shared"],"full: story kept")
	need(reader.state.codex.uniques.size()>=1 and reader.state.codex.legendaries.size()>=1,"full: codex filled "+JSON.stringify(reader.state.codex))
	var locked_seen := false;var new_seen := false
	for record in reader.state.items:
		if int(record.storage_id)==shown_ids[0] and record.get("locked",false):locked_seen=true
		if int(record.storage_id)==shown_ids[1] and record.get("new",false):new_seen=true
	need(locked_seen and new_seen,"full: locked and new flags kept")
	need(reader.wardrobe_view(FROST).worn==worn and reader.wardrobe_view(EMBER).worn=="chapter1.outfit.ember.swim_2" and reader.characters[FROST].wardrobe.owned==["chapter1.outfit.frost.swim_2"],"full: outfits worn "+JSON.stringify(reader.wardrobe_view(FROST)))
	need(reader.state.origin.from_schema==3,"full: origin names schema 3")
	print("PROFILE_V4_MAKE full revision=%d items=%d quarantine=%d codex=%s"%[int(reader.state.revision),reader.state.items.size(),reader.state.quarantine.size(),JSON.stringify(reader.state.codex)])
	write_text(OUT+"/v4_full.json",final_text)
	Profile.use_ids_for_test({})

func make_journals() -> void:
	var tables: RefCounted=Profile.loot()
	var rng := RandomNumberGenerator.new();rng.seed=20261120
	var jmain := WORK+"/journals/"+Snap.MAIN
	var pointer := WORK+"/journals/"+Snap.POINTER
	var jp=Profile.new()
	need(jp.configure(jmain,true),"journals: configure")
	for n in 4:
		var drops: Array=[tables.roll_item(rng,6+n,"rare",""),tables.roll_item(rng,6+n,"magic","")]
		need(jp.record_run("s0v4-j-%d"%(n+1),drops,[],n%2==0,20000+n*100,progress(FROST,300 if n==0 else 0)),"journals: run %d %s"%[n+1,jp.error])
	var rows: Array=jp.journal_files()
	need(rows.size()==4,"journals: four copies, got %d"%rows.size())
	for row in rows:
		var normalised := "chapter-one-profile-v4.revision-%06d-%s-0-0.json"%[int(row.number),STAMP_DAY]
		need(DirAccess.rename_absolute(WORK+"/journals/revisions/"+String(row.file),WORK+"/journals/revisions/"+normalised)==OK,"journals: rename")
	# the main file is damaged in the text (two items share one storage id) so that it is refused as incompatible
	var text := FileAccess.get_file_as_string(jmain)
	var finder := RegEx.create_from_string('"storage_id": ([0-9]+)')
	var hits := finder.search_all(text)
	need(hits.size()>=2,"journals: two items to collide")
	var tampered := text
	if hits.size()>=2:
		tampered=text.substr(0,hits[1].get_start(1))+hits[0].get_string(1)+text.substr(hits[1].get_end(1))
	write_text(jmain,tampered)
	var refused=Profile.new()
	need(not refused.configure(jmain,true,"","",pointer) and refused.reject_kind=="incompatible","journals: main refused as incompatible (kind %s)"%refused.reject_kind)
	need(refused.resume_info().get("revision",0)==4,"journals: resume candidate is revision 4")
	refused.stamp_override=STAMP_DAY+"-120000"
	need(refused.start_fresh_after_reject(true),"journals: fresh save "+refused.error)
	# copy out: the main file, the pointer, the r-file and the four journal copies of the main file (not the r-file's own copy, no temporary file)
	var copied: Array[String]=[]
	for rel in Snap.list_files(WORK+"/journals"):
		var keep: bool=rel==Snap.MAIN or rel==Snap.POINTER or rel=="chapter-one-profile-v4-r"+STAMP_DAY+"-120000.json" or rel.begins_with(Snap.REVISIONS+"/chapter-one-profile-v4.revision-")
		if keep and not ".next-" in rel:
			need(Snap.copy_bytes(WORK+"/journals/"+rel,OUT+"/"+Snap.JOURNAL_DIR+"/"+rel),"copy "+rel);copied.append(rel)
	print("PROFILE_V4_MAKE journal folder: ",copied)

func execute() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains("/_local/appdata/"):
		print("PROFILE_V4_MAKE refused: user data dir is not isolated");quit(1);return
	if FileAccess.file_exists(OUT+"/expected_v4.json"):
		print("PROFILE_V4_MAKE refused: fixtures already exist (they are never regenerated)");quit(1);return
	for part in ["full","journals","scen"]:Snap.wipe_tree(WORK+"/"+part)
	make_full()
	make_journals()
	if not failures.is_empty():
		print("PROFILE_V4_MAKE ",JSON.stringify({"failures":failures,"files":0}),"  (expected_v4.json not written; fix and run again)");quit(1);return
	var scenarios := {}
	for name in Snap.SCENARIOS:scenarios[name]=Snap.run_scenario(name,OUT,WORK+"/scen/"+name)
	var hashes := {}
	for rel in Snap.list_files(OUT):
		if rel!="expected_v4.json" and rel!="README.ko.md":hashes[rel]=FileAccess.get_sha256(OUT+"/"+rel)
	var external := {"profile_v4_compat.json":FileAccess.get_sha256(Snap.COMPAT_ROOT+"/profile_v4_compat.json")}
	var expected := {"format":1,"note":"Produced by the schema-4 code before schema 5. Never regenerate.","sha256":hashes,"external_sha256":external,"scenarios":scenarios}
	write_text(OUT+"/expected_v4.json",JSON.stringify(expected,"  "))
	print("PROFILE_V4_MAKE ",JSON.stringify({"failures":failures,"files":hashes.size()}))
	quit(0 if failures.is_empty() else 1)
