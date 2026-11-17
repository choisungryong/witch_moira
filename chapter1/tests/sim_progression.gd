extends SceneTree
## G1 progression simulation (docs/specs/G1-permanent-growth-spec.ko.md, section 10.1). Plays whole pilot runs of the
## frost witch on the real core and measures how fast the permanent level grows (progression mode) and how strong a
## given level of the tree is (fixed mode). Nothing is written except the optional --out file under _local/sim/.
## The player's save folder is never touched: the profile is an in-memory object with no path.
##
##   godot --headless --path . --script res://chapter1/tests/sim_progression.gd -- [options]
##   Progression: --runs=25 --policy=lance[,field,shatter,balanced] --seed-base=1000 [--carry-gear] [--paired] [--no-stop]
##   Fixed:       --fixed=L1,L6,L12,L20 --policy=lance,field,shatter,balanced --seeds=11,12,...
##   Other:       --timing           add core_tick_p95_ms (wall clock; leave off when comparing two runs for determinism)
##                --character=frost|ember|arc   which witch plays (default frost). A witch without a tree in the real data plays
##                                   the empty build only; policies are then "none" and fixed mode runs only L1.
##                --trees=<file>     link the trees of a draft file IN MEMORY (docs/specs/D7 6.2 W0-b/W0-c; only chapter1/tests/fixtures/ or
##                                   _local/). Nothing is written; chapter1/data/ stays as it is. Policies are the tree's branch ids
##                                   (frost: lance,field,shatter; ember: blast,fan,cinder; arc: focus,web,shock) or "balanced".
##                --diag             extra row keys and DIAG / D7 CHECK lines (first_hit_to_death_s, hook counters, secondary_contribution ...).
##                                   Without --diag and --trees the output of a frost run is byte for byte what it was before D7.
##                --out=<new file>   write the PROGRESSION_SIM document (_local/sim/ only, an existing path is refused)
##                --summarize=a.log,b.log   read PROGRESSION_RUN lines of earlier runs and only print the summary
## Output: one PROGRESSION_RUN line per run, tables, one PROGRESSION_SIM line. Exit 0 when the simulation ran
## (the targets are reported as pass / fail / unrated, they do not change the exit code), 2 on bad arguments.
##
## Policies are simulation constants, not data. They spend a point on the first plan entry that can_invest allows
## and whose wanted rank is not reached yet (so a locked entry falls through to the next one). Every plan ends with
## the oath branch and then tier-1 filler nodes of the other branches, so no point is left unspent while a node is open.
## The bot is the pilot of chapter_pilot.gd and is never tuned. A bot win rate is a stability reference, not a fun score.
const CORE := "res://chapter1/core/chapter_core.gd"
const PILOT := "res://chapter1/core/chapter_pilot.gd"
const Profile = preload("res://chapter1/core/chapter_profile.gd")
const SkillTree = preload("res://chapter1/core/skill_tree.gd")
const Progression = preload("res://chapter1/core/character_progression.gd")
const WITCHES := {"frost":["chapter1.character.frost","chapter1.skill.frost"],"ember":["chapter1.character.ember","chapter1.skill.ember"],"arc":["chapter1.character.arc","chapter1.skill.arc"]}
const DRAFT_DIRS := ["res://chapter1/tests/fixtures/","res://_local/"]
const COMMON_PREFIX := "witch.common."
const MAX_TICKS := 12*60*60+500
## First-kill receipts a witch holds once she has cleared every guardian (champion:0, champion:1, boss).
const FIRST_KILL_POINTS := 3
const ITEM_KEYS := ["grammar","base_id","name","slot","stats","quality","item_level","affixes","description","required_level","legendary_id"]
const PLAIN_SLOTS := ["weapon","head","body","hands","feet","charm"]
const LEVEL_MILESTONES := [2,4,6,12,18,20]
## Section 10.2 targets. Fixed numbers, never moved to fit a result.
const TARGET_RUNS_TO_LEVEL := {"6":[2,4],"12":[7,10],"20":[22,30]}
const TARGET_BRANCH_RUNS := [8,12]
## Internal criteria of D7 7.2 (fixed by the director before the first measurement; never moved to fit a result).
const D7_GAP_MAX := 1.6
const D7_WITCH_SPREAD := .10
const D7_FIELD_PER_MIN := 15.0
const D7_ARC_SECONDARY_FLOOR := .08

var _tree: Dictionary = {}
var _doc: Dictionary = {}
var _timing := false
var _diag := false
var _character := "chapter1.character.frost"
var _primary := "chapter1.skill.frost"
var _tree_id := "witch.frost"
## Derived from the tree data: non-common branch ids in file order, {branch: {node id: max rank}}, draft coverage per node.
var _branch_ids: Array=[]
var _branch_nodes := {}
var _draft_meta := {}
var _draft_path := ""

func _initialize() -> void:
	call_deferred("execute")

# ---------------------------------------------------------------- small helpers

func med(values: Array) -> float:
	if values.is_empty():return 0.0
	var sorted := values.duplicate();sorted.sort()
	var middle: int=sorted.size()/2
	return float(sorted[middle]) if sorted.size()%2==1 else (float(sorted[middle-1])+float(sorted[middle]))*.5

func percentile(sorted: Array,q: float) -> float:
	if sorted.is_empty():return 0.0
	return float(sorted[mini(sorted.size()-1,int(float(sorted.size())*q))])

func window_peak(hits: Array,span: int) -> float:
	var best := 0.0;var sum := 0.0;var start := 0
	for i in hits.size():
		sum+=float(hits[i][1])
		while int(hits[i][0])-int(hits[start][0])>=span:
			sum-=float(hits[start][1]);start+=1
		best=maxf(best,sum)
	return best

func fail(message: String) -> void:
	push_error(message);quit(2)

# ---------------------------------------------------------------- policies

## Policies are read from the tree data: the capstone first, then the policy branch to its maximum in tier order (or, for
## "balanced", tier by tier over every branch), then the shared nodes, then the tier-1 nodes of every branch as filler.
## For the frost tree of revision 1 this is exactly the plan the hand-written tables used to give.
func plan_for(policy: String) -> Array:
	var plan: Array=[]
	if _tree.is_empty():return plan
	var nodes: Array=_tree.nodes
	var top: int=_tree.tiers.size()
	for node in nodes:
		if int(node.tier)==top:plan.append([node.id,int(node.max_rank)])
	if policy=="balanced":
		for tier in range(1,top):
			var tier_nodes: Array=[]
			for branch in _branch_ids:
				for node in nodes:
					if node.branch==branch and int(node.tier)==tier:tier_nodes.append([node.id,int(node.max_rank)])
			for k in range(1,6):
				for node in tier_nodes:
					if k<=int(node[1]):plan.append([node[0],k])
	elif policy in _branch_ids:
		var members: Array=[]
		for node in nodes:
			if node.branch==policy:members.append(node)
		members.sort_custom(func(a: Dictionary,b: Dictionary): return int(a.tier)<int(b.tier))
		for node in members:plan.append([node.id,int(node.max_rank)])
	for node in nodes:
		if String(node.id).begins_with(COMMON_PREFIX):plan.append([node.id,int(node.max_rank)])
	for branch in _branch_ids:
		for node in nodes:
			if node.branch==branch and int(node.tier)==1:plan.append([node.id,int(node.max_rank)])
	return plan

## Reads _branch_ids and _branch_nodes from _tree (the shared branch is the one that holds the witch.common.* nodes).
func derive_branches() -> void:
	_branch_ids=[];_branch_nodes={}
	if _tree.is_empty():return
	var common := ""
	for node in _tree.nodes:
		if String(node.id).begins_with(COMMON_PREFIX):common=String(node.branch);break
	for branch in _tree.branches:
		if branch.id!=common:_branch_ids.append(branch.id)
	for branch in _branch_ids:
		var members := {}
		for node in _tree.nodes:
			if node.branch==branch:members[node.id]=int(node.max_rank)
		_branch_nodes[branch]=members

func invest(ranks: Dictionary,level: int,free: int,plan: Array) -> Dictionary:
	var result: Dictionary=ranks.duplicate()
	while free>0:
		var placed := false
		for step in plan:
			var id_: String=step[0]
			if int(result.get(id_,0))>=int(step[1]):continue
			if bool(SkillTree.can_invest(_tree,result,id_,level,free).ok):
				result[id_]=int(result.get(id_,0))+1;free-=1;placed=true;break
		if not placed:break
	return result

func branch_complete(policy: String,ranks: Dictionary) -> bool:
	if not _branch_nodes.has(policy):return false
	for id_ in _branch_nodes[policy]:
		if int(ranks.get(id_,0))<int(_branch_nodes[policy][id_]):return false
	return true

# ---------------------------------------------------------------- one run

## Plays a started run to its end and measures it.
func play(run: RefCounted,pilot: RefCounted) -> Dictionary:
	pilot.run=run
	var spawn_tick := {}
	var ttk: Array[float]=[]
	var step_usec: Array[int]=[]
	var friendly_window: Array[int]=[]
	var friendly_sum := 0
	var hero_peak := 0.0
	var damage_taken: Array=[]
	var taken_total := 0.0
	var min_hp := 1.0;var min_hp_zone := 0
	var champion_ticks := 0
	var boss_tick := -1
	var guard := 0
	# Diagnostics (only with --diag): engagement times and hook counters. They read events and change nothing.
	var first_hit := {}
	var approach: Array[float]=[]
	var engaged: Array[float]=[]
	var damage_by_skill := {}
	var counters := {"frost_field":0,"stun":0,"explosion_proc":0,"shatter":0,"death":0,"death_primary":0}
	while run.mode not in ["victory","defeat"] and guard<MAX_TICKS:
		var move: Vector2=pilot.decide()
		var started := Time.get_ticks_usec()
		run.step(move)
		if _timing:step_usec.append(Time.get_ticks_usec()-started)
		guard+=1
		var friendly := 0
		for p in run.projectiles:
			if not p.hostile and not p.get("child",false):friendly+=1
		friendly_window.append(friendly);friendly_sum+=friendly
		if friendly_window.size()>60:friendly_sum-=friendly_window.pop_front()
		if friendly_window.size()==60:hero_peak=maxf(hero_peak,float(friendly_sum)/60.0)
		for event in run.events:
			match event.type:
				"spawn":spawn_tick[int(event.target_id)]=run.tick
				"death":
					if not event.elite and spawn_tick.has(int(event.target_id)):
						ttk.append(float(run.tick-int(spawn_tick[int(event.target_id)]))/60.0)
					if _diag:
						counters.death+=1
						if event.skill_id==_primary:counters.death_primary+=1
						if not event.elite and first_hit.has(int(event.target_id)):engaged.append(float(run.tick-int(first_hit[int(event.target_id)]))/60.0)
				"hit":
					if _diag:
						damage_by_skill[event.skill_id]=int(damage_by_skill.get(event.skill_id,0))+int(event.damage_raw)
						if event.skill_id==_primary and not first_hit.has(int(event.target_id)):
							first_hit[int(event.target_id)]=run.tick
							if spawn_tick.has(int(event.target_id)):approach.append(float(run.tick-int(spawn_tick[int(event.target_id)]))/60.0)
				"frost_field":
					if _diag:counters.frost_field+=1
				"stun":
					if _diag and event.skill_id==_primary:counters.stun+=1
				"explosion":
					if _diag and event.skill_id==_primary and bool(event.get("proc",false)):counters.explosion_proc+=1
				"shatter":
					if _diag and event.skill_id==_primary:counters.shatter+=1
				"hero_hit":
					var fraction: float=float(event.damage_raw)/float(run.hero.max_hp_raw)
					damage_taken.append([run.tick,fraction]);taken_total+=fraction
				"chapter_champion":
					if int(event.zone)==2:boss_tick=run.tick
		var ratio := float(run.hero.hp_raw)/float(run.hero.max_hp_raw)
		if ratio<min_hp:min_hp=ratio;min_hp_zone=int(run.zone)
		if int(run._champion_id)>0:champion_ticks+=1
	var final_tick: int=run.tick
	step_usec.sort()
	var summary: Dictionary=run.progress_summary()
	var row := {"result":"timeout" if run.mode not in ["victory","defeat"] else String(run.mode),"ticks":final_tick,"seconds":snappedf(float(final_tick)/60.0,.1),
		"end_zone":int(run.zone),"min_hp_zone":min_hp_zone,"kills":int(run.kills),
		"enemy_ttk_median_s":snappedf(med(ttk),.01),"enemy_ttk_n":ttk.size(),"champion_fight_s":snappedf(float(champion_ticks)/60.0,.1),
		"damage_taken_over_max":snappedf(taken_total,.001),"min_hp":snappedf(min_hp,.001),"burst60":snappedf(window_peak(damage_taken,3600),.001),
		"potions_used":int(pilot.potion_uses),"hero_peak_1s":snappedf(hero_peak,.1),
		"boss_spawn_fraction":snappedf(float(boss_tick)/float(final_tick),.001) if boss_tick>=0 and final_tick>0 else null,
		"core_tick_p95_ms":snappedf(percentile(step_usec,.95)/1000.0,.001) if _timing else null,
		"xp_gained":int(summary.get("xp_gained",0)),"first_kills":summary.get("first_kills",[]),
		"level_before":int(summary.get("level_before",1)),"level_after":int(summary.get("level_after",1))}
	if not _character.ends_with(".frost"):row["character"]=_character
	if not _draft_path.is_empty():row["trees"]=_draft_path.get_file()
	if _diag:
		var minutes := maxf(.0001,float(final_tick)/3600.0)
		var total := 0;var secondary := 0
		for skill in damage_by_skill:
			total+=int(damage_by_skill[skill])
			if skill!=_primary:secondary+=int(damage_by_skill[skill])
		var assist := 0
		var assist_by: Dictionary=run.metrics.get("assist_raw",{})
		for skill in assist_by:assist+=int(assist_by[skill])
		row["first_hit_to_death_s"]=snappedf(med(engaged),.01);row["first_hit_to_death_n"]=engaged.size()
		row["spawn_to_first_hit_s"]=snappedf(med(approach),.01)
		row["primary_damage_share"]=snappedf(float(damage_by_skill.get(_primary,0))/maxf(1.0,float(total)),.001)
		row["secondary_contribution"]=snappedf(float(secondary+assist)/maxf(1.0,float(total)),.001)
		row["primary_kill_share"]=snappedf(float(counters.death_primary)/maxf(1.0,float(counters.death)),.001)
		row["fields_per_min"]=snappedf(float(counters.frost_field)/minutes,.01);row["stuns_per_min"]=snappedf(float(counters.stun)/minutes,.01)
		row["proc_explosions_per_min"]=snappedf(float(counters.explosion_proc)/minutes,.01);row["shatters_per_min"]=snappedf(float(counters.shatter)/minutes,.01)
	return row

func new_run(build: Dictionary,first_boss: bool,seed_: int) -> RefCounted:
	var run: RefCounted=load(CORE).new()
	if not build.is_empty() and not run.configure_build(build):
		fail("configure_build rejected: "+str(run.errors));return null
	run.first_boss_kill=first_boss
	if not run.start(seed_,_primary):
		fail("start rejected: "+str(run.errors));return null
	return run

# ---------------------------------------------------------------- gear carried between runs (--carry-gear)

func remember_gear(library: Array,run: RefCounted) -> void:
	for source in run.inventory+run.pending_rewards:
		var clean := {}
		for key in ITEM_KEYS:
			if source.has(key):clean[key]=source[key]
		if not Profile.loot().validate(clean).is_empty():continue
		var signature := JSON.stringify(clean)
		var known := false
		for entry in library:
			if entry.signature==signature:known=true;break
		if not known:library.append({"signature":signature,"item":clean})

## Per slot the best piece by the pilot's own equipment_score that this witch's level allows (spec 2.4 B).
func pick_gear(library: Array,level: int,pilot: RefCounted) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var storage := 0
	var rings: Array[Dictionary]=[]
	for slot in PLAIN_SLOTS+["ring"]:
		var best: Dictionary={};var best_score := -1.0e9
		var ranked: Array[Dictionary]=[]
		for entry in library:
			var item: Dictionary=entry.item
			if item.slot!=slot or Profile.required_level_of(item)>level:continue
			ranked.append(item)
		for item in ranked:
			var score: float=pilot.equipment_score(item)
			if score>best_score+.01 or best.is_empty():best=item;best_score=score
		if slot=="ring":
			ranked.sort_custom(func(a: Dictionary,b: Dictionary): return pilot.equipment_score(a)>pilot.equipment_score(b))
			for i in mini(2,ranked.size()):
				storage+=1;var ring: Dictionary=ranked[i].duplicate(true);ring.storage_id=storage;ring.equip_slot="ring" if i==0 else "ring2";result.append(ring)
		elif not best.is_empty():
			storage+=1;var piece: Dictionary=best.duplicate(true);piece.storage_id=storage;piece.equip_slot=slot;result.append(piece)
	return result

# ---------------------------------------------------------------- modes

func label(row: Dictionary) -> String:
	return "PROGRESSION_RUN "+JSON.stringify(row)

func run_progression(policy: String,count: int,seed_base: int,carry: bool,paired: bool,stop_at_cap: bool) -> Array[Dictionary]:
	var rows: Array[Dictionary]=[]
	var profile := Profile.new()
	profile.state=Profile.fresh();profile.available=true;profile.characters={}
	var plan := plan_for(policy)
	var cap: int=int(_doc.level_cap)
	var library: Array=[]
	var pilot_probe: RefCounted=load(PILOT).new()
	for i in count:
		var seed_ := seed_base+i
		var build := profile.build_for(_character)
		var entry := profile.character_entry(_character)
		var view_before := profile.character_view(_character)
		var first_boss: bool=not "boss" in entry.first_rewards
		var gear: Array[Dictionary]=[]
		if carry:gear=pick_gear(library,int(build.character_level),pilot_probe)
		var run := new_run(build,first_boss,seed_)
		if run==null:return rows
		if carry and not run.import_starting_gear(gear):fail("import_starting_gear rejected");return rows
		var pilot: RefCounted=load(PILOT).new()
		var row := play(run,pilot)
		row["run"]=i+1;row["policy"]=policy;row["mode"]="progression";row["seed"]=seed_
		row["points_total"]=int(view_before.points_earned);row["points_spent"]=int(view_before.points_spent);row["ranks"]=build.ranks.duplicate(true)
		row["gear_pieces"]=gear.size()
		var progress: Dictionary=run.progress_summary()
		var applied := Profile.apply_progress(profile.characters,progress)
		if applied.has("error"):fail("apply_progress: "+String(applied.error));return rows
		profile.characters=applied
		# Invest what the new level and receipts allow (a stand-in for the town screen), then confirm like commit_tree.
		var view := profile.character_view(_character)
		var ranks := invest(view.ranks,int(view.level),int(view.points_free),plan)
		var problems := SkillTree.legal_ranks(_tree,ranks,int(view.level),int(view.points_earned))
		if not problems.is_empty():fail("illegal ranks after invest: "+str(problems));return rows
		profile.characters[_character].ranks=ranks
		row["level_end"]=int(view.level);row["ranks_after"]=ranks.duplicate(true)
		row["branch_complete"]=branch_complete(policy,ranks)
		if carry:remember_gear(library,run)
		print(label(row));rows.append(row)
		if paired:
			var empty := new_run({},first_boss,seed_)
			if empty==null:return rows
			if carry and not empty.import_starting_gear(pick_gear(library,int(build.character_level),pilot_probe)):pass
			var twin := play(empty,load(PILOT).new())
			twin["run"]=i+1;twin["policy"]=policy;twin["mode"]="paired_empty";twin["seed"]=seed_
			print(label(twin));rows.append(twin)
		if stop_at_cap and int(view.level)>=cap and branch_complete(policy,ranks):break
	return rows

func run_fixed(levels: Array,policies: Array,seeds: Array) -> Array[Dictionary]:
	var rows: Array[Dictionary]=[]
	var curve: Array=_doc.xp_thresholds
	for level_name in levels:
		var level := int(String(level_name).trim_prefix("L"))
		# Without a tree the build is the same at every level, so only L1 is worth the time.
		if _tree.is_empty() and level>1:continue
		var xp := int(curve[level-1])
		var points := (level-1)+(FIRST_KILL_POINTS if level>1 else 0)
		# Level 1 has no points to spend, so it is the same build for every policy ("none").
		var names: Array=["none"] if level==1 or _tree.is_empty() else policies
		for policy in names:
			var ranks := {} if level==1 else invest({},level,points,plan_for(policy))
			var build := {"character_id":_character,"tree_id":_tree_id,"tree_revision":int(_tree.revision) if not _tree.is_empty() else 0,"ranks":ranks,"character_level":level,"character_xp":xp}
			for seed_ in seeds:
				var run := new_run(build,true,int(seed_))
				if run==null:return rows
				var row := play(run,load(PILOT).new())
				row["mode"]="fixed";row["policy"]=policy;row["level"]=level;row["seed"]=int(seed_);row["points_total"]=points;row["points_spent"]=SkillTree.points_spent(ranks);row["ranks"]=ranks
				print(label(row));rows.append(row)
	return rows

# ---------------------------------------------------------------- summaries

func rows_of(rows: Array,mode: String) -> Array:
	var out: Array=[]
	for row in rows:
		if row.mode==mode:out.append(row)
	return out

func verdict(ok: Variant) -> String:
	if ok==null:return "unrated"
	return "pass" if bool(ok) else "FAIL"

func summarize_progression(rows: Array) -> Dictionary:
	var result := {}
	var by_policy := {}
	for row in rows_of(rows,"progression"):
		if not by_policy.has(row.policy):by_policy[row.policy]=[]
		by_policy[row.policy].append(row)
	var lines: Array[String]=["policy     runs  firstLv  Lv6  Lv12  Lv20  branch  plateau  wins  levels by run"]
	for policy in by_policy:
		var list: Array=by_policy[policy]
		var levels: Array=[];var to_level := {};var branch: Variant=null;var plateau := 0;var streak := 0;var wins := 0
		for row in list:
			levels.append(int(row.level_after))
			if row.result=="victory":wins+=1
			for target in LEVEL_MILESTONES:
				if not to_level.has(str(target)) and int(row.level_after)>=target:to_level[str(target)]=int(row.run)
			if branch==null and bool(row.get("branch_complete",false)):branch=int(row.run)
			if int(row.level_before)<=19 and int(row.level_after)==int(row.level_before):streak+=1;plateau=maxi(plateau,streak)
			else:streak=0
		for target in LEVEL_MILESTONES:
			if not to_level.has(str(target)):to_level[str(target)]=null
		var first: Dictionary=list[0]
		var first_ok: Variant=(int(first.level_after)>=3) if first.result=="victory" else null
		var checks := {"first_run_level_after":{"value":int(first.level_after),"first_result":first.result,"target":">=3 on a win","verdict":verdict(first_ok)}}
		for key in TARGET_RUNS_TO_LEVEL:
			var range_: Array=TARGET_RUNS_TO_LEVEL[key]
			var value: Variant=to_level.get(key)
			checks["runs_to_level_"+key]={"value":value,"target":range_,"verdict":verdict(null if value==null else (int(value)>=int(range_[0]) and int(value)<=int(range_[1])))}
		if _branch_nodes.has(policy):
			checks["runs_to_branch_complete"]={"value":branch,"target":TARGET_BRANCH_RUNS,"verdict":verdict(null if branch==null else (int(branch)>=TARGET_BRANCH_RUNS[0] and int(branch)<=TARGET_BRANCH_RUNS[1]))}
		checks["longest_plateau_below_Lv20"]={"value":plateau,"target":"<=3","verdict":verdict(plateau<=3)}
		result[policy]={"runs":list.size(),"wins":wins,"runs_to_level":to_level,"runs_to_branch_complete":branch,"levels_by_run":levels,"longest_plateau":plateau,"checks":checks}
		lines.append("%-10s %4d  %7d  %3s  %4s  %4s  %6s  %7d  %4d  %s" % [policy,list.size(),int(first.level_after),str(to_level["6"]),str(to_level["12"]),str(to_level["20"]),str(branch),plateau,wins,str(levels)])
	if by_policy.is_empty():return {}
	for line in lines:print(line)
	var twins: Dictionary={}
	for row in rows_of(rows,"paired_empty"):
		if not twins.has(row.policy):twins[row.policy]=[]
		twins[row.policy].append(row)
	for policy in twins:
		var seconds_build: Array=[];var seconds_empty: Array=[];var ttk_build: Array=[];var ttk_empty: Array=[]
		for row in twins[policy]:
			seconds_empty.append(float(row.seconds));ttk_empty.append(float(row.enemy_ttk_median_s))
			for mine in by_policy.get(policy,[]):
				if int(mine.run)==int(row.run):seconds_build.append(float(mine.seconds));ttk_build.append(float(mine.enemy_ttk_median_s))
		result[policy]["paired"]={"median_seconds_build":snappedf(med(seconds_build),.1),"median_seconds_empty":snappedf(med(seconds_empty),.1),"median_ttk_build":snappedf(med(ttk_build),.01),"median_ttk_empty":snappedf(med(ttk_empty),.01)}
		print("paired %s: seconds build %.1f vs empty %.1f, normal-enemy ttk %.2f vs %.2f" % [policy,med(seconds_build),med(seconds_empty),med(ttk_build),med(ttk_empty)])
	return result

func group_stat(list: Array,key: String) -> float:
	var values: Array=[]
	for row in list:
		if row.get(key)!=null:values.append(float(row[key]))
	return med(values)

func summarize_fixed(rows: Array) -> Dictionary:
	var fixed := rows_of(rows,"fixed")
	if fixed.is_empty():return {}
	var groups := {}
	for row in fixed:
		var key := "%s|%d"%[row.policy,int(row.level)]
		if not groups.has(key):groups[key]=[]
		groups[key].append(row)
	var base: Array=groups.get("none|1",[])
	var base_stat := {}
	for key in ["seconds","enemy_ttk_median_s","champion_fight_s","damage_taken_over_max","core_tick_p95_ms"]:
		base_stat[key]=group_stat(base,key) if not base.is_empty() else 0.0
	var out := {"groups":{},"checks":{}}
	var lines: Array[String]=["policy    Lv   n  lost  sec(x)         ttk s(x)       guardian s(x)  taken(x)       minHP  threat  burst60  hero1s  zone-of-lowest-hp"]
	var keys := groups.keys();keys.sort_custom(func(a: String,b: String):
		var pa: PackedStringArray=a.split("|");var pb: PackedStringArray=b.split("|")
		return (int(pa[1])<int(pb[1])) or (int(pa[1])==int(pb[1]) and pa[0]<pb[0]))
	for key in keys:
		var list: Array=groups[key]
		var lost := 0;var threat := 0;var zones := [0,0,0]
		for row in list:
			if row.result!="victory":lost+=1
			if float(row.min_hp)<.40 or float(row.burst60)>=.60:threat+=1
			zones[clampi(int(row.min_hp_zone),0,2)]+=1
		var stats := {"n":list.size(),"defeats":lost,"threat_runs":threat,"min_hp_zone_counts":zones}
		for stat in ["seconds","enemy_ttk_median_s","champion_fight_s","damage_taken_over_max","min_hp","burst60","hero_peak_1s","core_tick_p95_ms"]:
			stats[stat]=snappedf(group_stat(list,stat),.001)
		if _diag:
			for stat in DIAG_STATS:stats[stat]=snappedf(group_stat(list,stat),.001)
		for stat in ["seconds","enemy_ttk_median_s","champion_fight_s","damage_taken_over_max"]:
			stats[stat+"_ratio"]=snappedf(float(stats[stat])/maxf(.0001,float(base_stat[stat])),.001) if not base.is_empty() else null
		out.groups[key]=stats
		var level_text: String=key.split("|")[1];var ratio := func(stat: String) -> String: return "-" if stats[stat+"_ratio"]==null else "%.2f"%float(stats[stat+"_ratio"])
		lines.append("%-9s %2s %3d  %4d  %6.1f(%s)  %6.2f(%s)  %6.1f(%s)  %6.2f(%s)  %5.2f  %3d/%-2d  %7.2f  %6.1f  %s" % [key.split("|")[0],level_text,list.size(),lost,
			float(stats.seconds),ratio.call("seconds"),float(stats.enemy_ttk_median_s),ratio.call("enemy_ttk_median_s"),float(stats.champion_fight_s),ratio.call("champion_fight_s"),
			float(stats.damage_taken_over_max),ratio.call("damage_taken_over_max"),float(stats.min_hp),threat,list.size(),float(stats.burst60),float(stats.hero_peak_1s),str(zones)])
	for line in lines:print(line)
	# Targets of 10.2 (fixed rows).
	var checks := {}
	var policies: Array=[]
	for row in fixed:
		if row.policy!="none" and not row.policy in policies:policies.append(row.policy)
	for policy in policies:
		for level in [12,20]:
			var g: Variant=out.groups.get("%s|%d"%[policy,level])
			if g==null or g.enemy_ttk_median_s_ratio==null:continue
			var limit := .85 if level==12 else .75
			checks["kill_time_%s_L%d"%[policy,level]]={"ratio":g.enemy_ttk_median_s_ratio,"target":"<= %.2f"%limit,"verdict":verdict(float(g.enemy_ttk_median_s_ratio)<=limit)}
		var g20: Variant=out.groups.get("%s|20"%policy)
		if g20!=null and g20.champion_fight_s_ratio!=null:
			checks["guardian_L20_"+policy]={"ratio":g20.champion_fight_s_ratio,"target":"<= 0.75","verdict":verdict(float(g20.champion_fight_s_ratio)<=.75)}
		if g20!=null and g20.seconds_ratio!=null:
			checks["run_length_L20_"+policy]={"ratio":g20.seconds_ratio,"target":"0.70..1.00","verdict":verdict(float(g20.seconds_ratio)>=.70 and float(g20.seconds_ratio)<=1.0)}
		var g12: Variant=out.groups.get("%s|12"%policy)
		if g12!=null:
			var need := int(ceil(float(g12.n)*5.0/9.0))
			checks["threat_L12_"+policy]={"value":"%d/%d"%[g12.threat_runs,g12.n],"target":">= 5 of 9","verdict":verdict(int(g12.threat_runs)>=need)}
	var lost_worst := 0;var cases := 0
	for key in out.groups:
		lost_worst=maxi(lost_worst,int(out.groups[key].defeats));cases=maxi(cases,int(out.groups[key].n))
	checks["defeats"]={"value":"worst build %d of %d"%[lost_worst,cases],"target":"<= 1 of 9","verdict":verdict(lost_worst<=1)}
	# Branch difference at Lv 12: three branches only.
	var wins := {}
	for policy in _branch_ids:wins[policy]=[]
	var ttks: Array=[]
	var present := _branch_ids.size()==3
	for policy in _branch_ids:
		if not out.groups.has("%s|12"%policy):present=false
	if present:
		for stat in ["enemy_ttk_median_s","champion_fight_s","damage_taken_over_max"]:
			var best_policy := "";var best_value := 1.0e18
			for policy in _branch_ids:
				var value: float=float(out.groups["%s|12"%policy][stat])
				if value<best_value:best_value=value;best_policy=policy
			wins[best_policy].append(stat)
		for policy in _branch_ids:ttks.append(float(out.groups["%s|12"%policy].enemy_ttk_median_s))
		var spread: float=float(ttks.max())/maxf(.0001,float(ttks.min()))
		var everyone := true
		for policy in wins:
			if wins[policy].is_empty():everyone=false
		checks["branch_difference_L12"]={"wins":wins,"ttk_spread_max_over_min":snappedf(spread,.001),"target":"each branch first in >= 1 of {ttk, guardian, taken}; ttk max/min <= 1.25","verdict":verdict(everyone and spread<=1.25)}
	# Core cost (only when --timing was used).
	for policy in policies:
		var g20: Variant=out.groups.get("%s|20"%policy)
		if g20!=null and not base.is_empty() and base_stat.core_tick_p95_ms>0.0 and float(g20.core_tick_p95_ms)>0.0:
			var gap := float(g20.core_tick_p95_ms)-float(base_stat.core_tick_p95_ms)
			checks["core_cost_L20_"+policy]={"gap_ms":snappedf(gap,.001),"target":"<= 0.5 ms (headless, other Godots running: indicative only)","verdict":verdict(gap<=.5)}
	if _diag:
		out["d7"]=d7_checks(out,checks)
	for key in checks:print("CHECK %-34s %-6s %s"%[key,checks[key].verdict,JSON.stringify(checks[key])])
	out.checks=checks
	return out

const DIAG_STATS := ["first_hit_to_death_s","spawn_to_first_hit_s","secondary_contribution","primary_damage_share","primary_kill_share","fields_per_min","stuns_per_min","proc_explosions_per_min","shatters_per_min"]

## D7 7.2 internal criteria and the diagnostic table (only with --diag). Judged on the fixed groups; unrated when a group is missing.
func d7_checks(out: Dictionary,checks: Dictionary) -> Dictionary:
	var lines: Array[String]=["DIAG policy    Lv   first-hit->death s(x)  spawn->first-hit s  secondary  fields/min  stuns/min  proc-expl/min  shatter/min"]
	var keys: Array=out.groups.keys();keys.sort_custom(func(a: String,b: String):
		var pa: PackedStringArray=a.split("|");var pb: PackedStringArray=b.split("|")
		return (int(pa[1])<int(pb[1])) or (int(pa[1])==int(pb[1]) and pa[0]<pb[0]))
	var base: Variant=out.groups.get("none|1")
	for key in keys:
		var g: Dictionary=out.groups[key]
		var ratio_text := "-"
		if base!=null and float(base.first_hit_to_death_s)>0.0:ratio_text="%.2f"%(float(g.first_hit_to_death_s)/float(base.first_hit_to_death_s))
		lines.append("DIAG %-9s %2s   %6.2f(%s)            %6.2f             %.3f      %6.2f      %6.2f     %6.2f         %6.2f" % [key.split("|")[0],key.split("|")[1],float(g.first_hit_to_death_s),ratio_text,float(g.spawn_to_first_hit_s),float(g.secondary_contribution),float(g.fields_per_min),float(g.stuns_per_min),float(g.proc_explosions_per_min),float(g.shatters_per_min)])
	for line in lines:print(line)
	var d7 := {}
	var branches: Array=_branch_ids
	# Gap between branches at L12 (guardian time and damage taken: worst / best).
	for stat in ["champion_fight_s","damage_taken_over_max"]:
		var values: Array=[]
		for policy in branches:
			if out.groups.has("%s|12"%policy):values.append(float(out.groups["%s|12"%policy][stat]))
		if values.size()==branches.size() and values.size()>=2:
			var gap: float=float(values.max())/maxf(.0001,float(values.min()))
			checks["d7_gap_L12_"+stat]={"value":snappedf(gap,.001),"target":"<= %.2f"%D7_GAP_MAX,"verdict":verdict(gap<=D7_GAP_MAX)}
	# L6 floor: no branch at L6 is worse than the empty build on any of the three indicators.
	for policy in branches:
		var g6: Variant=out.groups.get("%s|6"%policy)
		if g6==null or g6.enemy_ttk_median_s_ratio==null:continue
		var worst := maxf(float(g6.enemy_ttk_median_s_ratio),maxf(float(g6.champion_fight_s_ratio),float(g6.damage_taken_over_max_ratio)))
		checks["d7_floor_L6_"+policy]={"value":snappedf(worst,.001),"ratios":{"ttk":g6.enemy_ttk_median_s_ratio,"guardian":g6.champion_fight_s_ratio,"taken":g6.damage_taken_over_max_ratio},"target":"all <= 1.00","verdict":verdict(worst<=1.0)}
	# Run length at L6 / L12 / L20.
	for policy in branches:
		for level in [6,12,20]:
			var g: Variant=out.groups.get("%s|%d"%[policy,level])
			if g==null or g.seconds_ratio==null:continue
			checks["d7_length_L%d_%s"%[level,policy]]={"value":g.seconds_ratio,"target":"0.70..1.00","verdict":verdict(float(g.seconds_ratio)>=.70 and float(g.seconds_ratio)<=1.0)}
	# The hook runs at L12 (only the frost field has a rule in the core today; the others are rates for the report).
	for policy in branches:
		var g12: Variant=out.groups.get("%s|12"%policy)
		if g12==null:continue
		var rate := {"fields_per_min":g12.fields_per_min,"stuns_per_min":g12.stuns_per_min,"proc_explosions_per_min":g12.proc_explosions_per_min}
		var ok: Variant=null
		if _character.ends_with(".frost") and policy=="field":ok=float(g12.fields_per_min)>=D7_FIELD_PER_MIN
		checks["d7_hook_L12_"+policy]={"value":rate,"target":">= %.0f fields/min (frost field only; other hooks have no core rule yet)"%D7_FIELD_PER_MIN,"verdict":verdict(ok)}
	# Secondary contribution (report; arc below the floor goes to the director).
	for policy in branches:
		for level in [12,20]:
			var g: Variant=out.groups.get("%s|%d"%[policy,level])
			if g==null:continue
			var sc: float=float(g.secondary_contribution)
			var ok: Variant=null
			if _character.ends_with(".arc") and level==20:ok=sc>=D7_ARC_SECONDARY_FLOOR
			checks["d7_secondary_L%d_%s"%[level,policy]]={"value":sc,"target":">= %.2f for arc L20, report only otherwise"%D7_ARC_SECONDARY_FLOOR,"verdict":verdict(ok)}
	# For the witch-to-witch comparison (+-0.10) the caller joins the numbers of three runs.
	var ratios: Array=[]
	for policy in branches:
		var g20: Variant=out.groups.get("%s|20"%policy)
		if g20!=null and g20.enemy_ttk_median_s_ratio!=null:ratios.append(float(g20.enemy_ttk_median_s_ratio))
	if ratios.size()==branches.size() and not ratios.is_empty():
		d7["ttk_ratio_L20_median"]=snappedf(med(ratios),.001)
		d7["witch_spread_limit"]=D7_WITCH_SPREAD
	return d7

## Static estimate of section 10.2's power_table rows for the Lv 20 build of each policy.
func power_rows(policies: Array) -> Dictionary:
	var growth: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://chapter1/data/growth_quality37.json"))
	var tuning: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://chapter1/data/combat_tuning.json"))
	if not growth is Dictionary or not tuning is Dictionary:return {}
	var out := {}
	if _tree.is_empty():return {}
	var empty := SkillTree.power_table(_tree,{},growth,tuning)
	if empty.has("error"):return {}
	for policy in policies:
		if policy=="none":continue
		var ranks := invest({},20,22,plan_for(policy))
		var table := SkillTree.power_table(_tree,ranks,growth,tuning)
		if table.has("error"):continue
		var row := {"grace_ratio_r1_to_r4_build":snappedf(float(table.grace_ratio_build),.001),"tree_ratio_r4_vs_empty":snappedf(float(table.tree_ratio_r4),.001)}
		row["verdict_grace"]=verdict(float(table.grace_ratio_build)>=4.0);row["verdict_tree"]=verdict(float(table.tree_ratio_r4)>=1.3 and float(table.tree_ratio_r4)<=3.0)
		if _diag:row["tree_ratio_r1_vs_empty"]=snappedf(float(table.stages.r1.ratio),.001)
		if not _character.ends_with(".frost"):
			# The static formula counts shots x (pierce+1) only: no explosion, chain or pulse term yet (D7 4.1, W0-a). Not a judgement.
			row["verdict_grace"]="unrated";row["verdict_tree"]="unrated";row["note"]="power_table has no explosion/chain term until W0-a"
		out[policy]=row
		print("POWER_TABLE %s %s"%[policy,JSON.stringify(row)])
	return out

# ---------------------------------------------------------------- draft trees (D7 6.2 W0-b / W0-c)

## Links the trees of a draft file in memory: the progression document gets their tree ids, every tree is checked by the real
## validator (SkillTree.validate_tree), and the shared documents of the profile and the core are replaced for this process.
## Nothing is written and chapter1/data/ is not touched. A node's own "draft" object (hook, coverage, pending effects) is
## ignored by the validator and the core; it only feeds the DRAFT_* lines.
func link_draft(path: String) -> bool:
	var full := path if path.begins_with("res://") else "res://"+path
	var allowed := false
	for dir in DRAFT_DIRS:allowed=allowed or full.begins_with(dir)
	if not allowed or ".." in full:fail("--trees must be under chapter1/tests/fixtures/ or _local/: "+path);return false
	if not FileAccess.file_exists(full):fail("No such draft file "+full);return false
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(full))
	if not parsed is Dictionary or not parsed.get("trees") is Array or parsed.trees.is_empty():fail("Malformed draft file "+full);return false
	var progression: Dictionary=Profile.progression_doc().duplicate(true)
	var trees: Dictionary=Profile.trees().duplicate(true)
	if progression.is_empty() or trees.is_empty():fail("real progression data failed to load");return false
	for tree in parsed.trees:
		if not tree is Dictionary or not tree.get("tree_id") is String:fail("draft tree without tree_id");return false
		var linked := false
		for entry in progression.characters:
			if entry.signature_skill_id==tree.get("signature_skill_id"):entry["tree_id"]=tree.tree_id;linked=true
		if not linked:fail("no witch owns the signature skill of "+String(tree.tree_id));return false
	var problems := Progression.validate_document(progression)
	if not problems.is_empty():fail("progression document with the draft links: "+problems[0]);return false
	for tree in parsed.trees:
		var errors := SkillTree.validate_tree(tree,progression)
		if not errors.is_empty():fail("%s rejected by the validator: %s"%[tree.tree_id,", ".join(PackedStringArray(errors))]);return false
		trees[tree.tree_id]=tree
		var coverage := {}
		for node in tree.nodes:
			var draft: Dictionary=node.get("draft",{})
			_draft_meta[node.id]=draft
			var key := "%s|%s|%s"%[node.branch,String(draft.get("hook","now")),String(draft.get("coverage","full"))]
			coverage[key]=int(coverage.get(key,0))+1
		print("DRAFT_LINK ",JSON.stringify({"tree_id":tree.tree_id,"revision":tree.revision,"nodes":tree.nodes.size(),"branch|hook|coverage":coverage}))
	# The statics are shared on purpose: the profile and the core read them instead of the files.
	Profile._progression=progression
	Profile._trees=trees
	var core_script: GDScript=load(CORE)
	core_script._shared_progression=progression
	core_script._shared_trees=trees
	_draft_path=full
	return true

## True when every node of the branch is fully expressed by the current grammar and core (coverage "full").
func branch_coverage(branch: String) -> String:
	var missing: Array=[]
	for node in _tree.nodes:
		if node.branch!=branch:continue
		var draft: Dictionary=_draft_meta.get(node.id,{})
		if String(draft.get("coverage","full"))!="full":missing.append("%s(%s,%s)"%[node.id.get_slice(".",2),String(draft.get("hook","?")),String(draft.get("coverage","?"))])
	return "full" if missing.is_empty() else "PARTIAL: "+", ".join(PackedStringArray(missing))

# ---------------------------------------------------------------- entry

func execute() -> void:
	var runs := 25;var seed_base := 1000;var policies: Array=["lance"];var carry := false;var paired := false;var stop_at_cap := true
	var fixed: Array=[];var seeds: Array=[11,12,13,14,15,16,17,18,19];var out_path := "";var summarize: Array=[]
	var policy_given := false;var witch := "frost";var draft := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--runs="):runs=int(arg.trim_prefix("--runs="))
		elif arg.begins_with("--seed-base="):seed_base=int(arg.trim_prefix("--seed-base="))
		elif arg.begins_with("--policy="):policies=Array(arg.trim_prefix("--policy=").split(","));policy_given=true
		elif arg.begins_with("--character="):witch=arg.trim_prefix("--character=")
		elif arg.begins_with("--trees="):draft=arg.trim_prefix("--trees=")
		elif arg=="--diag":_diag=true
		elif arg=="--carry-gear":carry=true
		elif arg=="--paired":paired=true
		elif arg=="--no-stop":stop_at_cap=false
		elif arg=="--timing":_timing=true
		elif arg.begins_with("--fixed="):fixed=Array(arg.trim_prefix("--fixed=").split(","))
		elif arg.begins_with("--seeds="):
			seeds=[]
			for part in arg.trim_prefix("--seeds=").split(","):seeds.append(int(part))
		elif arg.begins_with("--out="):out_path=arg.trim_prefix("--out=")
		elif arg.begins_with("--summarize="):summarize=Array(arg.trim_prefix("--summarize=").split(","))
		else:fail("Unknown argument "+arg);return
	if not WITCHES.has(witch):fail("--character must be frost, ember or arc");return
	_character=WITCHES[witch][0];_primary=WITCHES[witch][1]
	if runs<1 or runs>200:fail("--runs must be 1..200");return
	if not out_path.is_empty():
		if out_path.begins_with("_local/"):out_path="res://"+out_path
		if not out_path.begins_with("res://_local/sim/"):fail("--out must be under _local/sim/");return
		if FileAccess.file_exists(out_path):fail("--out refuses an existing path: "+out_path);return
	_doc=Profile.progression_doc()
	if _doc.is_empty():fail("progression data failed to load");return
	if not draft.is_empty():
		if not link_draft(draft):return
		_doc=Profile.progression_doc()
	var trees := Profile.trees()
	var entry: Dictionary=Progression.character_entry(_doc,_character)
	if entry.get("tree_id")!=null:
		_tree_id=String(entry.tree_id)
		if not trees.has(_tree_id):fail("the tree of %s failed to load"%witch);return
		_tree=trees[_tree_id]
	else:
		_tree_id="";_tree={}
		print("NO_TREE %s has no tree in the data (and none linked): she plays the empty build only (policy none, fixed L1)"%witch)
	derive_branches()
	if _tree.is_empty():
		if not policy_given:policies=["none"]
	elif not policy_given:policies=[_branch_ids[0]]
	if summarize.is_empty():
		for policy in policies:
			var known: bool=policy in _branch_ids or (policy=="balanced" and not _tree.is_empty()) or (policy=="none" and _tree.is_empty())
			if not known:fail("Unknown policy %s (this witch: %s)"%[String(policy),("none" if _tree.is_empty() else ", ".join(PackedStringArray(_branch_ids))+", balanced")]);return
		if not draft.is_empty() and not _tree.is_empty():
			for branch in _branch_ids:print("DRAFT_COVERAGE %s %s %s"%[witch,branch,branch_coverage(branch)])
	var rows: Array=[]
	if not summarize.is_empty():
		for path in summarize:
			if not FileAccess.file_exists(String(path)):fail("No such file "+String(path));return
			for line in FileAccess.get_file_as_string(String(path)).split("\n"):
				if line.begins_with("PROGRESSION_RUN "):
					var parsed: Variant=JSON.parse_string(line.trim_prefix("PROGRESSION_RUN "))
					if parsed is Dictionary:rows.append(parsed)
	elif not fixed.is_empty():
		for level_name in fixed:
			var text := String(level_name)
			if not text.begins_with("L") or not text.trim_prefix("L").is_valid_int() or int(text.trim_prefix("L"))<1 or int(text.trim_prefix("L"))>int(_doc.level_cap):fail("Bad level "+text);return
		var all_rows := run_fixed(fixed,policies,seeds)
		rows.append_array(all_rows)
	else:
		for policy in policies:
			rows.append_array(run_progression(String(policy),runs,seed_base,carry,paired,stop_at_cap))
	var seen_policies: Array=[]
	for row in rows:
		if not row.policy in seen_policies:seen_policies.append(row.policy)
	var document := {"progression":summarize_progression(rows),"fixed":summarize_fixed(rows),"power":power_rows(seen_policies),
		"conditions":{"runs":runs,"seed_base":seed_base,"policies":policies,"carry_gear":carry,"paired":paired,"fixed":fixed,"seeds":seeds,"rows":rows.size(),"summarized_files":summarize}}
	if witch!="frost" or not draft.is_empty() or _diag:
		document.conditions["character"]=witch;document.conditions["trees"]=_draft_path;document.conditions["diag"]=_diag
	print("PROGRESSION_SIM ",JSON.stringify(document))
	if not out_path.is_empty():
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var file := FileAccess.open(out_path,FileAccess.WRITE)
		if file==null:fail("Cannot write "+out_path);return
		file.store_string(JSON.stringify(document,"  "));file.close()
	quit(0)
