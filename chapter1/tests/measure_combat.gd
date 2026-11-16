extends SceneTree
## Plays whole pilot runs on the real core and measures the combat-pressure targets of
## docs/specs/M2-combat-pressure-spec.ko.md (section 4) and of its round 2
## (M2-combat-pressure-spec-round2.ko.md, sections 3 and 5).
##
##   godot --headless --path . --script res://chapter1/tests/measure_combat.gd -- [options]
##     --seeds=11,12,13             seeds (default 11,12,13)
##     --primaries=ember,frost,arc  primary skills (default all three)
##     --core=res://chapter1/core/chapter_core.gd
##     --tuning=<json path>         combat tuning for the run instead of chapter1/data/combat_tuning.json
##     --out=<new file>             write the COMBAT_MEASURE document; an existing path is refused
##     --xp-curve                   add the collected XP every 60 ticks to each row
##     --arc-combined               judge the arc projectile target on projectiles + visible arc segments
##     --secondary-off              also replay every case with the secondary skills never cast
##                                  (run.debug_secondary_off) and print COMBAT_COUNTERFACTUAL
## Output: one COMBAT_RUN line per run, a table, one COMBAT_MEASURE line (and COMBAT_COUNTERFACTUAL).
## Exit 0 only when every target passes in every run, 2 on bad arguments, 1 otherwise. The counterfactual
## is reported, it does not change the exit code. The pilot is the measuring tool and is never tuned.
##
## Definitions (round 2):
##   hero projectiles = friendly projectiles that are not child sparks, plus the visible arc segments
##                      (a segment stays visible tuning.presentation.arc_stripe_ticks ticks).
##   hero_share_pre_evo / post_evo = hero / (friendly projectiles + arc segments), summed over the ticks before /
##                      from the primary skill's evolution (the pilot's evolve: card). null where there is no such span.
##   burst60 / burst30 = most hero damage taken inside any 60 s / 30 s window, as a share of the maximum life then.
##   threat = lowest life < 0.40 OR burst60 >= 0.60. Both numbers are always printed.
##   secondary_contribution = (damage of the secondary skills + damage added by marks) / all damage.
##   heavy hit = a hit of at least 20 % of the maximum life before reduction (hero_hit.incoming_raw).
const DEFAULT_CORE := "res://chapter1/core/chapter_core.gd"
const PILOT := "res://chapter1/core/chapter_pilot.gd"
const ARC := "chapter1.skill.arc"
const MAX_TICKS := 12*60*60+500
## Targets are fixed; they are not adjusted to fit a result.
const TARGETS := {"friendly_peak_1s":60.0,"primary_hit_share":.55,"attacks_per_min":60.0,"min_hp_ratio":.40,"cap_fraction":.85,
	"seconds":[300,360],"hero_share_pre_evo":1.0,"hero_share_post_evo":.70,"secondary_contribution":[.12,.30],"burst60":.60}
## Counterfactual: the median run must get at least this much longer without the secondary skills.
const COUNTERFACTUAL_GAIN := .08
## A hit of this share of the maximum life (basis points) counts as a heavy hit in the measurement.
## Used when the run's tuning has heavy_hit.heavy_bps 0 (rule off); the gap then is DEFAULT_HEAVY_GAP.
const HEAVY_BPS := 2000
const DEFAULT_HEAVY_GAP := 120
const DEFAULT_STRIPE_TICKS := 12
const JUDGED := ["projectiles","primary_hit_share","attacks_per_min","threat","cap_fraction","seconds","hero_share","secondary_contribution","heavy_gap"]

func _initialize() -> void:
	call_deferred("execute")

func percentile(sorted: Array,q: float) -> Variant:
	if sorted.is_empty():return 0
	return sorted[mini(sorted.size()-1,int(float(sorted.size())*q))]

func median(values: Array) -> float:
	if values.is_empty():return 0.0
	var sorted := values.duplicate();sorted.sort()
	var middle: int=sorted.size()/2
	return float(sorted[middle]) if sorted.size()%2==1 else (float(sorted[middle-1])+float(sorted[middle]))*.5

func execute() -> void:
	var seeds: Array=[11,12,13]
	var primaries: Array=["ember","frost","arc"]
	var core_path := DEFAULT_CORE
	var tuning_path := ""
	var out_path := ""
	var want_curve := false
	var arc_combined := false
	var counterfactual := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seeds=[]
			for part in arg.trim_prefix("--seeds=").split(","):seeds.append(int(part))
		elif arg.begins_with("--primaries="):primaries=Array(arg.trim_prefix("--primaries=").split(","))
		elif arg.begins_with("--core="):core_path=arg.trim_prefix("--core=")
		elif arg.begins_with("--tuning="):tuning_path=arg.trim_prefix("--tuning=")
		elif arg.begins_with("--out="):out_path=arg.trim_prefix("--out=")
		elif arg=="--xp-curve":want_curve=true
		elif arg=="--arc-combined":arc_combined=true
		elif arg=="--secondary-off":counterfactual=true
		else:push_error("Unknown argument "+arg);quit(2);return
	if not out_path.is_empty() and (FileAccess.file_exists(out_path) or DirAccess.dir_exists_absolute(out_path)):
		push_error("--out refuses an existing path: "+out_path);quit(2);return
	var rows: Array[Dictionary]=[]
	var off_rows: Array[Dictionary]=[]
	for name in primaries:
		var primary: String="chapter1.skill."+String(name)
		for seed_ in seeds:
			var row := play(core_path,tuning_path,int(seed_),primary,want_curve,false)
			if row.has("error"):push_error(row.error);quit(2);return
			rows.append(row)
			print("COMBAT_RUN ",JSON.stringify(row))
			if counterfactual:
				var off := play(core_path,tuning_path,int(seed_),primary,false,true)
				if off.has("error"):push_error(off.error);quit(2);return
				off_rows.append(off)
				print("COMBAT_RUN_SECONDARY_OFF ",JSON.stringify({"primary":off.primary,"seed":off.seed,"seconds":off.seconds,"defeat":off.defeat,"min_hp_ratio":off.min_hp_ratio,"attacks_per_min":off.attacks_per_min,"burst60":off.burst60}))
	var passes := {}
	for key in JUDGED:passes[key]=[0,0]
	var informational := {"min_hp_only":[0,0],"burst60_only":[0,0]}
	var mismatches: Array[String]=[]
	var lines: Array[String]=["run          sec  lvl12  proj1s(+arc)  hero1s   primary   att/min  minHP  burst60  hero pre/post  contrib  heavy(gap)  defeat"]
	for row in rows:
		var verdict := judge(row,arc_combined)
		for key in passes:
			passes[key][1]+=1
			if verdict[key]:passes[key][0]+=1
			else:mismatches.append("%s/%d: %s %s" % [String(row.primary).trim_prefix("chapter1.skill."),row.seed,key,describe(row,key,arc_combined)])
		informational.min_hp_only[1]+=1;informational.burst60_only[1]+=1
		if float(row.min_hp_ratio)<TARGETS.min_hp_ratio:informational.min_hp_only[0]+=1
		if float(row.burst60)>=TARGETS.burst60:informational.burst60_only[0]+=1
		lines.append("%-10s %5d  %6s  %5.1f(%5.1f)%s %6.1f  %6.2f%s  %7.1f%s  %5.2f  %6.2f%s  %5s/%-5s  %5.3f%s  %3d(%5s)  %s" % [
			"%s/%d" % [String(row.primary).trim_prefix("chapter1.skill."),row.seed],int(row.seconds),
			("-" if row.cap_fraction==null else "%.2f" % float(row.cap_fraction))+("" if verdict.cap_fraction else "*"),
			float(row.friendly_peak_1s),float(row.combined_peak_1s),"" if verdict.projectiles else "*",float(row.hero_peak_1s),
			float(row.primary_hit_share),"" if verdict.primary_hit_share else "*",
			float(row.attacks_per_min),"" if verdict.attacks_per_min else "*",
			float(row.min_hp_ratio),float(row.burst60),"" if verdict.threat else "*",
			"-" if row.hero_share_pre_evo==null else "%.2f" % float(row.hero_share_pre_evo),"-" if row.hero_share_post_evo==null else "%.2f" % float(row.hero_share_post_evo),
			float(row.secondary_contribution),"" if verdict.secondary_contribution else "*",
			int(row.heavy_hits),"-" if row.heavy_min_gap_ticks==null else str(int(row.heavy_min_gap_ticks)),
			"DEFEAT" if row.defeat else "win"])
	for line in lines:print(line)
	var all_pass := true
	for key in passes:all_pass=all_pass and passes[key][0]==passes[key][1]
	var doc := {"cases":rows.size(),"rows":rows,"targets":TARGETS,"pass":passes,"informational":informational,"mismatches":mismatches,"arc_combined":arc_combined,"tuning":tuning_path if not tuning_path.is_empty() else "default"}
	print("COMBAT_MEASURE ",JSON.stringify(doc))
	if counterfactual:
		var seconds_on: Array=[]
		var seconds_off: Array=[]
		var cases: Array=[]
		for i in rows.size():
			# Only cases won both with and without the secondary skills enter the median: a defeat ends a run early.
			if not rows[i].defeat and not off_rows[i].defeat:
				seconds_on.append(float(rows[i].seconds));seconds_off.append(float(off_rows[i].seconds))
			cases.append({"primary":rows[i].primary,"seed":rows[i].seed,"seconds_on":rows[i].seconds,"seconds_off":off_rows[i].seconds,"defeat_on":rows[i].defeat,"defeat_off":off_rows[i].defeat})
		var median_on := median(seconds_on)
		var median_off := median(seconds_off)
		var gain := (median_off-median_on)/maxf(1.0,median_on)
		# A defeat ends a run early and shortens it; the counts are printed so the median is read with them.
		var defeats_on := 0
		var defeats_off := 0
		for i in rows.size():
			if rows[i].defeat:defeats_on+=1
			if off_rows[i].defeat:defeats_off+=1
		var verdict_cf := {"cases":cases,"defeats_on":defeats_on,"defeats_off":defeats_off,"median_seconds_on":snappedf(median_on,.1),"median_seconds_off":snappedf(median_off,.1),"median_gain":snappedf(gain,.001),"median_cases":seconds_on.size(),"target_gain":COUNTERFACTUAL_GAIN,
			"definition":"pass = more defeats without the secondary skills than with them (they are needed), or the median length of the cases won both ways grows by target_gain or more",
			"pass":defeats_off>defeats_on or (not seconds_on.is_empty() and gain>=COUNTERFACTUAL_GAIN)}
		doc["counterfactual"]=verdict_cf
		print("COMBAT_COUNTERFACTUAL ",JSON.stringify(verdict_cf))
	if not out_path.is_empty():
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var file := FileAccess.open(out_path,FileAccess.WRITE)
		if file==null:push_error("Cannot write "+out_path);quit(2);return
		file.store_string(JSON.stringify(doc,"  "));file.close()
	quit(0 if all_pass else 1)

func in_range(value: float,bounds: Array) -> bool:
	return value>=float(bounds[0]) and value<=float(bounds[1])

func judge(row: Dictionary,arc_combined: bool) -> Dictionary:
	var projectile_value: float=float(row.combined_peak_1s) if (arc_combined and row.primary==ARC) else float(row.friendly_peak_1s)
	var pre_ok: bool=row.hero_share_pre_evo==null or float(row.hero_share_pre_evo)>=TARGETS.hero_share_pre_evo
	var post_ok: bool=row.hero_share_post_evo==null or float(row.hero_share_post_evo)>=TARGETS.hero_share_post_evo
	return {"projectiles":projectile_value>=TARGETS.friendly_peak_1s,
		"primary_hit_share":float(row.primary_hit_share)>=TARGETS.primary_hit_share,
		"attacks_per_min":float(row.attacks_per_min)>=TARGETS.attacks_per_min,
		"threat":float(row.min_hp_ratio)<TARGETS.min_hp_ratio or float(row.burst60)>=TARGETS.burst60,
		"cap_fraction":row.cap_fraction!=null and float(row.cap_fraction)>=TARGETS.cap_fraction,
		"seconds":in_range(float(row.seconds),TARGETS.seconds),
		"hero_share":pre_ok and post_ok,
		"secondary_contribution":in_range(float(row.secondary_contribution),TARGETS.secondary_contribution),
		"heavy_gap":row.heavy_min_gap_ticks==null or int(row.heavy_min_gap_ticks)>=int(row.heavy_gap_needed)}

func describe(row: Dictionary,key: String,arc_combined: bool) -> String:
	match key:
		"projectiles":
			if arc_combined and row.primary==ARC:return "combined_peak_1s %.1f < 60" % float(row.combined_peak_1s)
			return "friendly_peak_1s %.1f < 60 (combined %.1f)" % [float(row.friendly_peak_1s),float(row.combined_peak_1s)]
		"primary_hit_share":return "%.3f < 0.55" % float(row.primary_hit_share)
		"attacks_per_min":return "%.1f < 60" % float(row.attacks_per_min)
		"threat":return "min_hp_ratio %.3f >= 0.40 and burst60 %.3f < 0.60" % [float(row.min_hp_ratio),float(row.burst60)]
		"seconds":return "%.1f s outside 300..360" % float(row.seconds)
		"hero_share":return "pre %s post %s (need 1.00 / >= 0.70)" % [str(row.hero_share_pre_evo),str(row.hero_share_post_evo)]
		"secondary_contribution":return "%.3f outside 0.12..0.30" % float(row.secondary_contribution)
		"heavy_gap":return "heavy hits %d ticks apart < %d" % [int(row.heavy_min_gap_ticks),int(row.heavy_gap_needed)]
	return "%s (need >= 0.85)" % ("null" if row.cap_fraction==null else "%.3f" % float(row.cap_fraction))

## The largest sum of fractions inside any window of span ticks. hits is [[tick, fraction], ...] in tick order.
func window_peak(hits: Array,span: int) -> float:
	var best := 0.0
	var sum := 0.0
	var start := 0
	for i in hits.size():
		sum+=float(hits[i][1])
		while int(hits[i][0])-int(hits[start][0])>=span:
			sum-=float(hits[start][1]);start+=1
		best=maxf(best,sum)
	return best

func play(core_path: String,tuning_path: String,seed_: int,primary: String,want_curve: bool,secondary_off: bool) -> Dictionary:
	var run: RefCounted=load(core_path).new()
	var pilot: RefCounted=load(PILOT).new()
	pilot.run=run
	run.first_boss_kill=true
	if secondary_off:run.debug_secondary_off=true
	if not tuning_path.is_empty() and not run.load_tuning(tuning_path):
		return {"error":"tuning rejected: "+str(run.errors)}
	if not run.start(seed_,primary):return {"error":"start rejected: "+str(run.errors)}
	var stripe_ticks: int=int(run.tuning.get("presentation",{}).get("arc_stripe_ticks",DEFAULT_STRIPE_TICKS))
	var level_cap: int=run.growth.xp_thresholds().size()
	var guard := 0
	var friendly_window: Array[int]=[]
	var combined_window: Array[int]=[]
	var hero_window: Array[int]=[]
	var friendly_sum := 0
	var combined_sum := 0
	var hero_sum := 0
	var friendly_peak := 0
	var friendly_peak_1s := 0.0
	var combined_peak_1s := 0.0
	var hero_peak_1s := 0.0
	var arc_peak := 0
	var arc_recent: Array=[]
	var combat_samples: Array[int]=[]
	var alive_samples: Array[int]=[]
	var step_usec: Array[int]=[]
	var damage_by_skill := {}
	var kills_by_skill := {}
	var attacks := 0
	var attacks_by_kind := {}
	var attacks_in_zone: Array[int]=[0,0,0]
	var zone_start: Array[int]=[0,-1,-1]
	var attack_seconds: Array[int]=[]
	var kills_per_zone: Array[int]=[0,0,0]
	var normal_kills_per_zone: Array[int]=[0,0,0]
	var min_hp := 1.0
	var min_hp_tick := 0
	var last_hits: Array=[]
	var cap_tick := -1
	var xp_curve: Array[int]=[]
	var potions_dropped := 0
	var evolve_tick := -1
	var selections_seen := 0
	var hero_pre := 0
	var all_pre := 0
	var hero_post := 0
	var all_post := 0
	var damage_taken: Array=[]
	var taken_total := 0.0
	var heavy_rule: Dictionary=run.tuning.get("heavy_hit",{})
	var heavy_bps: int=int(heavy_rule.get("heavy_bps",0)) if int(heavy_rule.get("heavy_bps",0))>0 else HEAVY_BPS
	var heavy_gap_needed: int=int(heavy_rule.gap_ticks) if int(heavy_rule.get("heavy_bps",0))>0 else DEFAULT_HEAVY_GAP
	var heavy_ticks: Array[int]=[]
	var heavy_grazed := 0
	var boss_tick := -1
	var champion_ticks: Array[int]=[0,0,0]
	var under_half := 0
	var under_half_run := 0
	var under_half_longest := 0
	var potions_seen := 0
	while run.mode not in ["victory","defeat"] and guard<MAX_TICKS:
		var move: Vector2=pilot.decide()
		var zone_before: int=run.zone
		# The pilot may have taken the evolve card this very tick; the step below clears its growth event.
		while selections_seen<pilot.selections.size():
			var chosen: Dictionary=pilot.selections[selections_seen];selections_seen+=1
			if evolve_tick<0 and chosen.id=="evolve:"+primary:evolve_tick=int(chosen.tick)
		var started := Time.get_ticks_usec()
		run.step(move)
		step_usec.append(Time.get_ticks_usec()-started)
		guard+=1
		var friendly := 0
		var sparks := 0
		for p in run.projectiles:
			if not p.hostile:
				friendly+=1
				if p.get("child",false):sparks+=1
		friendly_peak=maxi(friendly_peak,friendly)
		for event in run.events:
			match event.type:
				"cast":
					if event.get("skill_id","")==ARC:arc_recent.append([run.tick,event.get("segments",[]).size()])
				"hit":damage_by_skill[event.skill_id]=int(damage_by_skill.get(event.skill_id,0))+int(event.damage_raw)
				"enemy_attack":
					attacks+=1
					attacks_by_kind[event.kind]=int(attacks_by_kind.get(event.kind,0))+1
					attacks_in_zone[run.zone]+=1
					var second: int=run.tick/60
					while attack_seconds.size()<=second:attack_seconds.append(0)
					attack_seconds[second]+=1
				"death":
					kills_per_zone[zone_before]+=1
					if not event.elite:normal_kills_per_zone[zone_before]+=1
					kills_by_skill[event.skill_id]=int(kills_by_skill.get(event.skill_id,0))+1
				"hero_hit":
					last_hits.append([snappedf(float(run.tick)/60.0,.1),snappedf(float(event.damage_raw)/256.0,.1),snappedf(float(run.hero.hp_raw)/float(run.hero.max_hp_raw),.001)])
					if last_hits.size()>10:last_hits.pop_front()
					var fraction: float=float(event.damage_raw)/float(run.hero.max_hp_raw)
					damage_taken.append([run.tick,fraction]);taken_total+=fraction
					var incoming: int=int(event.get("incoming_raw",event.damage_raw))
					if incoming*10000>=heavy_bps*int(run.hero.max_hp_raw):
						if event.get("graze",false):heavy_grazed+=1
						else:heavy_ticks.append(run.tick)
				"potion_drop":potions_dropped+=1
				"chapter_champion":
					if int(event.zone)==2:boss_tick=run.tick
		if run.zone!=zone_before and run.zone<3 and zone_start[run.zone]<0:zone_start[run.zone]=run.tick
		while not arc_recent.is_empty() and int(arc_recent[0][0])<=run.tick-stripe_ticks:arc_recent.pop_front()
		var segments := 0
		for entry in arc_recent:segments+=int(entry[1])
		arc_peak=maxi(arc_peak,segments)
		var hero_now := friendly-sparks+segments
		if evolve_tick>=0 and run.tick>=evolve_tick:
			hero_post+=hero_now;all_post+=friendly+segments
		else:
			hero_pre+=hero_now;all_pre+=friendly+segments
		friendly_window.append(friendly);friendly_sum+=friendly
		combined_window.append(friendly+segments);combined_sum+=friendly+segments
		hero_window.append(hero_now);hero_sum+=hero_now
		if friendly_window.size()>60:friendly_sum-=friendly_window.pop_front();combined_sum-=combined_window.pop_front();hero_sum-=hero_window.pop_front()
		if friendly_window.size()==60:
			friendly_peak_1s=maxf(friendly_peak_1s,float(friendly_sum)/60.0)
			combined_peak_1s=maxf(combined_peak_1s,float(combined_sum)/60.0)
			hero_peak_1s=maxf(hero_peak_1s,float(hero_sum)/60.0)
		var alive: int=run.alive_count()
		if alive>=20:combat_samples.append(friendly)
		if run.tick%6==0:alive_samples.append(alive)
		var ratio := float(run.hero.hp_raw)/float(run.hero.max_hp_raw)
		if ratio<min_hp:min_hp=ratio;min_hp_tick=run.tick
		if ratio<.5:
			under_half+=1;under_half_run+=1;under_half_longest=maxi(under_half_longest,under_half_run)
		else:under_half_run=0
		if int(run._champion_id)>0:champion_ticks[clampi(run.zone,0,2)]+=1
		if cap_tick<0 and int(run.growth.snapshot().level)>=level_cap:cap_tick=run.tick
		if want_curve and run.tick%60==0:xp_curve.append(int(run.growth.snapshot().xp))
	# potion_used is emitted while the pilot decides, before step() clears the event list, so the pilot's own count is used.
	potions_seen=int(pilot.potion_uses)
	var final_tick: int=run.tick
	var hits: Dictionary=run.metrics.hits
	var total_hits := 0
	for skill in hits:total_hits+=int(hits[skill])
	# secondary_contribution = (secondary_damage + assist_total) / total_damage. total_damage and secondary_damage sum the
	# hit events' damage_raw, which includes overkill (a blow's full damage even when the target had less life left).
	# assist_total (the extra damage marks added) is measured on life really removed, and is already inside the
	# primary's damage_raw, so it is added once on top of the secondaries' own damage.
	var total_damage := 0
	var secondary_damage := 0
	for skill in damage_by_skill:
		total_damage+=int(damage_by_skill[skill])
		if skill!=primary:secondary_damage+=int(damage_by_skill[skill])
	var assist_by_skill: Dictionary=run.metrics.get("assist_raw",{}).duplicate()
	var assist_total := 0
	for skill in assist_by_skill:assist_total+=int(assist_by_skill[skill])
	var minutes := float(final_tick)/3600.0
	# Quiet windows: tumbling 60 s blocks after the first 30 s with fewer than 10 attack attempts.
	var quiet := 0
	var block := 30
	while block+60<=final_tick/60:
		var count := 0
		for second in range(block,block+60):count+=attack_seconds[second] if second<attack_seconds.size() else 0
		if count<10:quiet+=1
		block+=60
	var attacks_per_zone_min: Array=[]
	for z in 3:
		var end_tick: int=zone_start[z+1] if z<2 and zone_start[z+1]>=0 else final_tick
		var span: int=end_tick-zone_start[z] if zone_start[z]>=0 else 0
		attacks_per_zone_min.append(snappedf(float(attacks_in_zone[z])/(float(span)/3600.0),.1) if span>0 else null)
	combat_samples.sort();alive_samples.sort();step_usec.sort()
	# Reaching the level cap in the last second only comes from the boss absorbing every orb.
	var cap_fraction: Variant=null
	if cap_tick>=0 and cap_tick<=final_tick-60:cap_fraction=snappedf(float(cap_tick)/float(final_tick),.001)
	var share_pre: Variant=snappedf(float(hero_pre)/float(all_pre),.001) if all_pre>0 else null
	var share_post: Variant=snappedf(float(hero_post)/float(all_post),.001) if all_post>0 else null
	var heavy_gap: Variant=null
	for i in range(1,heavy_ticks.size()):
		heavy_gap=mini(int(heavy_gap),heavy_ticks[i]-heavy_ticks[i-1]) if heavy_gap!=null else heavy_ticks[i]-heavy_ticks[i-1]
	var seconds := snappedf(float(final_tick)/60.0,.1)
	var champion_total: int=champion_ticks[0]+champion_ticks[1]+champion_ticks[2]
	var row := {"primary":primary,"seed":seed_,"mode":run.mode,"defeat":run.mode=="defeat","ticks":final_tick,"seconds":seconds,"seconds_ok":seconds>=float(TARGETS.seconds[0]) and seconds<=float(TARGETS.seconds[1]),
		"secondary_off":secondary_off,
		"kills":run.kills,"kills_per_zone":kills_per_zone,"normal_kills_per_zone":normal_kills_per_zone,"kills_by_skill":kills_by_skill,
		"friendly_peak":friendly_peak,"friendly_peak_1s":snappedf(friendly_peak_1s,.1),
		"friendly_p50_p90_combat":[percentile(combat_samples,.5),percentile(combat_samples,.9)],
		"arc_segments_peak":arc_peak,"combined_peak_1s":snappedf(combined_peak_1s,.1),"arc_stripe_ticks":stripe_ticks,
		"hero_peak_1s":snappedf(hero_peak_1s,.1),"evolve_tick":evolve_tick if evolve_tick>=0 else null,"hero_share_pre_evo":share_pre,"hero_share_post_evo":share_post,
		"hits":hits.duplicate(),"primary_hit_share":snappedf(float(hits.get(primary,0))/maxf(1.0,float(total_hits)),.001),
		"primary_damage_share":snappedf(float(damage_by_skill.get(primary,0))/maxf(1.0,float(total_damage)),.001),
		"secondary_contribution":snappedf(float(secondary_damage+assist_total)/maxf(1.0,float(total_damage)),.001),"assist_by_skill":assist_by_skill,
		"enemy_attacks":attacks,"attacks_per_min":snappedf(float(attacks)/minutes,.1),"attacks_by_kind":attacks_by_kind,"attacks_per_zone_min":attacks_per_zone_min,
		"quiet_windows":quiet,"min_hp_ratio":snappedf(min_hp,.001),"min_hp_tick":min_hp_tick,"last_hero_hits":last_hits,
		"burst60":snappedf(window_peak(damage_taken,60*60),.001),"burst30":snappedf(window_peak(damage_taken,30*60),.001),"damage_taken_over_max":snappedf(taken_total,.001),
		"heavy_hits":heavy_ticks.size()+heavy_grazed,"heavy_min_gap_ticks":heavy_gap,"heavy_gap_needed":heavy_gap_needed,"heavy_bps_used":heavy_bps,"heavy_grazed":heavy_grazed,
		"under_half_seconds":snappedf(float(under_half)/60.0,.1),"under_half_longest_seconds":snappedf(float(under_half_longest)/60.0,.1),
		"boss_spawn_fraction":snappedf(float(boss_tick)/float(final_tick),.001) if boss_tick>=0 else null,
		"champion_fight_seconds":snappedf(float(champion_total)/60.0,.1),"champion_fight_by_zone":[snappedf(float(champion_ticks[0])/60.0,.1),snappedf(float(champion_ticks[1])/60.0,.1),snappedf(float(champion_ticks[2])/60.0,.1)],
		"cap_tick":cap_tick,"cap_fraction":cap_fraction,
		"alive_p50_p90_max":[percentile(alive_samples,.5),percentile(alive_samples,.9),alive_samples[alive_samples.size()-1] if not alive_samples.is_empty() else 0],
		"potions_used":potions_seen,"potions_dropped":potions_dropped,"children_dropped":int(run.metrics.get("children_dropped",0)),"events_dropped":int(run.metrics.get("events_dropped",0)),
		"step_usec_p50_p95_p99":[percentile(step_usec,.5),percentile(step_usec,.95),percentile(step_usec,.99)]}
	if want_curve:row["xp_curve"]=xp_curve
	return row
