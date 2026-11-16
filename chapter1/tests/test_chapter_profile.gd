extends SceneTree
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
func _initialize() -> void:call_deferred("execute")
func write_text(file_path: String,text: String) -> void:
	DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())
	var f := FileAccess.open(file_path,FileAccess.WRITE);f.store_string(text);f.close()
func progress(xp: int,kills: Array=[],who: String=FROST) -> Dictionary:
	return {"character_id":who,"xp_gained":xp,"first_kills":kills,"sources":{},"level_before":1,"level_after":1}
## A v3 file made from a real saved profile with `mutate` applied to its parsed document.
func refused(base_text: String,target: String,mutate: Callable,label: String) -> void:
	var doc: Dictionary=JSON.parse_string(base_text);mutate.call(doc)
	var text := JSON.stringify(doc,"  ");write_text(target,text)
	var loader=Profile.new()
	check(not loader.configure(target,true) and FileAccess.get_file_as_string(target)==text and not loader.available,label)
func g1_checks(directory: String,tables: RefCounted,rng: RandomNumberGenerator,v2_state: Dictionary) -> void:
	var root := directory+"/g1"
	# 1. v2 file -> v3 file; the v2 bytes never change.
	var old_v2: Dictionary=v2_state.duplicate(true);old_v2.completed_runs=7;old_v2.revision=4
	var v2_path := root+"/legacy/profile-v2.json";write_text(v2_path,JSON.stringify(old_v2,"  "))
	var v2_bytes := FileAccess.get_file_as_string(v2_path)
	var up=Profile.new();var v3_path := root+"/up/profile-v3.json"
	check(up.configure(v3_path,true,v2_path) and up.imported_from_v2 and up.characters.has(FROST) and int(up.characters[FROST].xp)==5000 and not FileAccess.file_exists(v3_path),"v2 profile is read into memory: 7 runs migrate as 5 runs of xp, nothing written yet")
	check(up.unselect("weapon") and FileAccess.file_exists(v3_path) and not up.imported_from_v2 and FileAccess.get_file_as_string(v2_path)==v2_bytes,"First save writes the v3 file and leaves the v2 bytes untouched")
	var v3_doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(v3_path))
	check(int(v3_doc.schema_version)==3 and int(v3_doc.revision)==5 and v3_doc.characters.has(FROST) and not v3_doc.characters[FROST].has("level"),"v3 file: schema 3, revision continues, level is not stored")
	var up_again=Profile.new();check(up_again.configure(v3_path,true,v2_path) and up_again.state==up.state and up_again.characters==up.characters and not up_again.imported_from_v2,"v3 file reads back identically and wins over the v2 file")
	check(Profile.normalize(v3_doc).is_empty(),"A schema-3 document is not accepted by the schema-2 normalizer")
	# 2. v1 only
	var v1_path := root+"/legacy/profile-v1.json"
	write_text(v1_path,JSON.stringify({"schema_version":1,"revision":3,"next_id":2,"items":[{"storage_id":1,"item":Items.roll(rng,8,"rare","weapon")}],"equipped":{"weapon":1},"completed_runs":2,"best_ticks":20000,"essence":5,"receipts":["old"]}))
	var v1_bytes := FileAccess.get_file_as_string(v1_path)
	var from_v1=Profile.new();var v1_target := root+"/from-v1/profile-v3.json"
	check(from_v1.configure(v1_target,true,"",v1_path) and from_v1.imported_from_v1 and int(from_v1.characters[FROST].xp)==2000,"v1 only: read into memory with 2 runs of xp")
	check(from_v1.unselect("weapon") and FileAccess.file_exists(v1_target) and FileAccess.get_file_as_string(v1_path)==v1_bytes,"v1 is carried into the v3 file and its bytes stay")
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
	# 5-7. forged files are refused, original preserved
	refused(base_text,root+"/bad/overspent.json",func(d): d.characters[FROST].ranks={NEEDLE:5},"Spent points above earned points rejected")
	refused(base_text,root+"/bad/orphan.json",func(d): d.characters[FROST].xp=25000;d.characters[FROST].ranks={"witch.frost.volley":1},"Broken prerequisite rejected (volley 1 without needle)")
	refused(base_text,root+"/bad/level.json",func(d): d.characters[FROST].xp=1280;d.characters[FROST].ranks={NEEDLE:2,"witch.frost.volley":1},"Node above the character level rejected")
	# 12. a witch without a tree cannot hold ranks
	refused(base_text,root+"/bad/ember.json",func(d): d.characters[EMBER]={"xp":2000,"tree_revision":0,"ranks":{NEEDLE:1},"first_rewards":[],"respecs":0},"Ember entry with ranks rejected")
	refused(base_text,root+"/bad/duplicate-reward.json",func(d): d.characters[FROST].first_rewards=["boss","boss"],"Duplicate first-kill receipt rejected")
	refused(base_text,root+"/bad/extra-key.json",func(d): d.characters[FROST]["level"]=4,"Stored level key rejected")
	# 8. tree_revision mismatch: ranks come back on read, the next save writes them empty
	var stale_path := root+"/stale/profile.json"
	var stale_doc: Dictionary=JSON.parse_string(base_text);stale_doc.characters[FROST].xp=2000;stale_doc.characters[FROST].ranks={NEEDLE:2};stale_doc.characters[FROST].tree_revision=9
	write_text(stale_path,JSON.stringify(stale_doc,"  "))
	check(Profile.normalize_v3(stale_doc,true).is_empty(),"Write rule: stale tree_revision rejected strictly")
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
	check(tree.respec_cost(FROST)==12 and not tree.respec(FROST) and tree.error.contains("재") and int(tree.state.essence)==8 and int(tree.character_view(FROST).points_spent)==4,"Respec refused when essence is short, nothing changes")
	tree.respec_cost_override=2
	check(tree.respec(FROST) and int(tree.state.essence)==0 and tree.characters[FROST].ranks.is_empty() and int(tree.characters[FROST].respecs)==1,"Respec costs essence per point and clears the ranks")
	tree.respec_cost_override=-1
	check(not tree.respec(FROST),"Respec with nothing invested is refused")
	check(tree.commit_tree(FROST,{NEEDLE:4}) and tree.respec(FROST) and int(tree.state.essence)==0,"Verification-period cost is 0")
	# 11. another run saved first
	var race_path := root+"/race/profile.json";var one=Profile.new();one.configure(race_path,true);one.record_run("g1-r",[],[],true,1,progress(1000));one.record_run("g1-r2",[],[],true,1,progress(1000))
	var two=Profile.new();two.configure(race_path,true)
	check(one.commit_tree(FROST,{NEEDLE:1}) and not two.commit_tree(FROST,{NEEDLE:2}) and two.error.contains("다른 실행"),"commit_tree is refused after another run saved first")
	# level-gated gear
	var gate=Profile.new();gate.configure(root+"/gate/profile.json",true)
	var strong: Dictionary=tables.roll_item(rng,12,"rare","weapon");strong.uid=901
	check(gate.record_run("g1-gate",[strong],[],false,1,progress(0)) and int(gate.state.items[0].item.required_level)>1,"A high-level piece is stored")
	var need := int(gate.state.items[0].item.required_level)
	check(not gate.select_item(int(gate.state.items[0].storage_id),FROST) and gate.error.contains("Lv") and gate.select_item(int(gate.state.items[0].storage_id)),"select_item with a witch refuses a piece above her level; without one it selects")
	check(gate.starting_gear(FROST).is_empty() and gate.blocked_gear(FROST).size()==1 and int(gate.blocked_gear(FROST)[0].required_level)==need and gate.starting_gear().size()==1,"A selected piece above the level stays selected but is left behind and reported")
	var pure := Profile.apply_progress({},progress(100,["boss"],EMBER))
	check(int(pure[EMBER].xp)==100 and int(pure[EMBER].tree_revision)==0 and pure[EMBER].first_rewards==["boss"],"apply_progress is pure and works for a witch without a tree")
func execute() -> void:
	var directory := "res://_local/profile-fixtures-01"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture-dir="):directory=arg.trim_prefix("--fixture-dir=")
	check(not DirAccess.dir_exists_absolute(directory),"Fresh isolated fixture directory")
	if DirAccess.dir_exists_absolute(directory):quit(1);return
	DirAccess.make_dir_recursive_absolute(directory)
	var profile=Profile.new()
	check(Profile.PATH_V3.begins_with("user://"),"Product profile lives in the user directory; tests only use isolated fixture paths")
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
	check(reopened.select_item(id_),"Select persistent gear")
	var gear: Array[Dictionary]=reopened.starting_gear();check(gear.size()==1 and gear[0].storage_id==id_,"Selected gear carries persistent identity")
	var run=Chapter.new();run.start(4)
	check(run.import_starting_gear(gear) and run.inventory.size()==1,"Fresh run imports selected gear")
	check(run.hero.hp_raw==run.hero.max_hp_raw and run.tick==0,"Fresh-boundary full health")
	run.tick=1;check(not run.import_starting_gear(gear),"Mid-run gear import forbidden")
	check(reopened.record_run("run-two",run.inventory,[],false,100),"Defeat saves without duplicating existing gear")
	check(reopened.state.items.size()==1 and reopened.state.completed_runs==1,"Starter gear not duplicated and defeat not completed")
	check(not profile.select_item(id_) and profile.error.contains("다른 실행"),"Stale writer refused and external save preserved")
	check(reopened.salvage(id_) and reopened.state.items.is_empty() and reopened.state.equipped.is_empty() and reopened.state.essence==8,"Explicit salvage clears equipped reference and records reward")
	var broken := Profile.fresh();broken.items=[{"storage_id":1,"item":Items.unique(0,5)}];broken.next_id=2;broken.equipped={"body":1}
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
	var revision_count := 0;var dir := DirAccess.open(directory)
	for name in dir.get_files():
		if name.contains(".revision-"):revision_count+=1
	check(revision_count>=6,"Prior immutable revisions remain")
	# Schema 2: grammar-v2 items, eight equip slots, two rings, and the one-way v1 import.
	var tables=Profile.loot()
	var v2=Profile.new();check(v2.configure(directory+"/v2.json",true),"v2 profile configured")
	var haul: Array=[]
	for slot in ["weapon","head","body","hands","feet","charm","ring","ring"]:
		var piece: Dictionary=tables.roll_item(rng,8,"rare",slot);piece.uid=100+haul.size();piece.position=Vector2.ZERO;piece.collected=true;haul.append(piece)
	var legend: Dictionary=tables.roll_item(rng,8,"legendary","weapon");legend.uid=200;haul.append(legend)
	check(v2.record_run("run-v2",haul,[],false,100) and v2.state.items.size()==9,"Grammar-v2 items of every slot and a legendary are stored")
	for record in v2.state.items.duplicate(true):
		if record.item.quality!="legendary":v2.select_item(int(record.storage_id))
	check(v2.state.equipped.size()==8 and v2.state.equipped.has("ring2") and v2.state.equipped.ring!=v2.state.equipped.ring2,"Eight slots filled, two different rings")
	var v2_again=Profile.new();check(v2_again.configure(v2.path,true) and v2_again.state==v2.state,"v2 profile reloads identically")
	var kit: Array[Dictionary]=v2_again.starting_gear()
	var run8=Chapter.new();run8.start(5)
	check(kit.size()==8 and run8.import_starting_gear(kit) and run8.equipped.size()==8,"A run starts wearing all eight pieces")
	check(run8.hero.speed>run8.BASE_SPEED,"Boots raise move speed")
	var twice: Dictionary=v2_again.state.duplicate(true);twice.equipped.ring2=twice.equipped.ring
	check(Profile.normalize(twice).is_empty(),"One ring cannot fill both ring slots")
	var misplaced: Dictionary=v2_again.state.duplicate(true);misplaced.equipped.head=misplaced.equipped.feet
	check(Profile.normalize(misplaced).is_empty(),"Boots cannot be worn on the head")
	var forged_v2: Dictionary=v2_again.state.duplicate(true);forged_v2.items[0].item.stats.damage_bps=29000
	check(Profile.normalize(forged_v2).is_empty(),"Forged v2 stat rejected")
	var ring_id: int=v2_again.state.equipped.ring2
	check(v2_again.salvage(ring_id) and not v2_again.state.equipped.has("ring2") and v2_again.state.equipped.has("ring"),"Salvaging the second ring frees only that slot")
	var old_text := JSON.stringify({"schema_version":1,"revision":3,"next_id":3,"items":[{"storage_id":1,"item":Items.roll(rng,8,"rare","weapon")},{"storage_id":2,"item":Items.unique(1,9)}],"equipped":{"weapon":1,"charm":2},"completed_runs":2,"best_ticks":20000,"essence":5,"receipts":["old"]})
	var carried=Profile.new();check(carried.configure(directory+"/carried.json",true) and carried.import_v1_text(old_text),"Schema-1 profile is read")
	check(carried.imported_from_v1 and carried.state.schema_version==2 and carried.state.items.size()==2 and carried.state.equipped.size()==2 and carried.state.completed_runs==2,"Imported state keeps items, selection and progress")
	check(not FileAccess.file_exists(carried.path),"Import alone writes nothing")
	check(carried.select_item(1) and carried.salvage(2) and FileAccess.file_exists(carried.path) and not carried.imported_from_v1,"First change after import saves a schema-2 file")
	var carried_again=Profile.new();check(carried_again.configure(carried.path,true) and carried_again.state.items.size()==1 and carried_again.state.essence==30,"Carried profile reloads from its own file")
	var refuse=Profile.new();refuse.configure(directory+"/refuse.json",true)
	check(not refuse.import_v1_text('{"schema_version":2}') and not refuse.import_v1_text("not json") and not refuse.imported_from_v1,"Non-v1 or broken text is refused as an import")
	check(Profile.normalize(JSON.parse_string(old_text)).is_empty(),"A schema-1 document is not accepted as schema 2 without the import step")
	g1_checks(directory,tables,rng,v2.state)
	if "--negative" in OS.get_cmdline_user_args():check(false,"Intentional checker failure")
	print("CHAPTER_PROFILE_TEST ",JSON.stringify({"checks":checks,"failures":failures,"fixtures":directory,"scope":"New isolated profile fixture files only; old equipment/progress not read or written"}))
	quit(0 if failures.is_empty() else 1)
