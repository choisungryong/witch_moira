extends SceneTree
const Chapter=preload("res://chapter1/core/chapter_core.gd")
const Items=preload("res://chapter1/core/chapter_items.gd")
var failures: Array[String]=[]
var checks := 0
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func _initialize() -> void:
	call_deferred("execute")
func context(run: RefCounted,amount: int) -> Dictionary:
	var effects: Dictionary=run.effective_skill("chapter1.skill.ember").effects.duplicate(true)
	effects.damage_raw=amount;effects.death_burst=0;effects.shatter_count=0
	return {"uid":123,"skill_id":"chapter1.skill.ember","effects":effects,"remaining_hits":128,"hit_ids":[],"evolved":false}
## The neutral (pre-M2) tuning fixture with some top-level keys replaced. The rule tests need a fixed baseline, so they do not read the shipped numbers.
func tuning_with(mod: Dictionary) -> Dictionary:
	var doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://chapter1/tests/fixtures/combat_tuning_neutral.json"))
	for key in mod:doc[key]=mod[key]
	return doc
func tuned_run(mod: Dictionary,primary: String="chapter1.skill.ember",seed_: int=17) -> RefCounted:
	var r := Chapter.new()
	check(r.set_tuning(tuning_with(mod)),"Tuning accepted "+str(mod.keys()))
	check(r.start(seed_,primary),"Tuned run starts "+str(mod.keys()))
	return r
## A run that has taken the unlock card of a second skill at level 2.
func tuned_run_owning(mod: Dictionary,second: String) -> RefCounted:
	var r := tuned_run(mod)
	r.growth.award_xp(12);r._refresh_mode()
	var offer: Dictionary=r.get_offer()
	for card in offer.cards:
		if card.id=="unlock:"+second:r.choose(offer.token,card.id)
	return r
func clear_field(r: RefCounted) -> void:
	r.enemies.clear();r._alive=0;r.events.clear();r._next_spawn=1000000;r._rebuild_grid()

func pressure_checks() -> void:
	# Data file and loader.
	var on_disk := Chapter.new()
	check(on_disk.start(5),"The shipped combat_tuning.json passes the validator and starts a run")
	var shipped := Chapter.new()
	check(shipped.set_tuning(tuning_with({})) and shipped.start(5) and shipped.tuning.potion.drop_one_in==90 and shipped.tuning.xp_thresholds[11]==1640,"Neutral fixture loads the pre-M2 values")
	var broken := tuning_with({"alive_cap":0})
	check(not shipped.set_tuning(broken) and shipped.tuning.alive_cap==178,"Out-of-range tuning is rejected and the old one stays")
	var no_key := tuning_with({});no_key.erase("secondary")
	check(not shipped.set_tuning(no_key),"Tuning with a missing root key is rejected")
	var bad_stage := tuning_with({"primary_bonus":{"chapter1.skill.ember":{"r9":{"add":{"projectiles":1}}}}})
	check(not shipped.set_tuning(bad_stage),"Unknown primary bonus stage is rejected")
	var bad_stat := tuning_with({"primary_bonus":{"chapter1.skill.ember":{"r1":{"add":{"mana":1}}}}})
	check(not shipped.set_tuning(bad_stat),"Primary bonus outside the catalog limits is rejected")
	var cd_add := tuning_with({"primary_bonus":{"chapter1.skill.ember":{"r1":{"add":{"cooldown_ticks":-100000}}}}})
	var cd_mul := tuning_with({"primary_bonus":{"chapter1.skill.ember":{"r1":{"mul_bps":{"cooldown_ticks":1}}}}})
	check(not shipped.set_tuning(cd_add) and not shipped.set_tuning(cd_mul),"cooldown_ticks is not a legal add/mul_bps target")
	check(not shipped.set_tuning(tuning_with({"friendly_projectile_cap":193})) and shipped.set_tuning(tuning_with({"friendly_projectile_cap":192})),"friendly_projectile_cap is limited to 192")
	shipped.start(5)
	var locked := Chapter.new();locked.start(5)
	check(locked.tuning.is_read_only() and locked.tuning.spawn.zones[0].is_read_only() and locked.tuning.xp_thresholds.is_read_only(),"Tuning document is read-only, nested parts included")
	var floor_sec := tuned_run_owning({"secondary":{"damage_bps":10000,"hit_budget_bps":10000,"cooldown_bps":1,"max_chain_targets":32,"max_branches":4}},"chapter1.skill.arc")
	check(floor_sec.effective_skill("chapter1.skill.arc").effects.cooldown_ticks==12,"Secondary cooldown never goes under 12 ticks")
	# Health grows with time; the opening walker does not.
	var timed := tuned_run({"hp_time_bps_per_s":160});clear_field(timed)
	timed.tick=29*60;timed._spawn("walker",Vector2(6,0))
	check(timed.enemies[timed._enemy_sequence].max_hp_raw==9*256,"Opening walker keeps 9 HP and gets no time bonus")
	timed.tick=31*60;timed._spawn("walker",Vector2(6,0))
	check(timed.enemies[timed._enemy_sequence].max_hp_raw==12*(10000+160*31)/10000*256,"Walker HP follows hp*(10000+bps*seconds)/10000 at 31 s")
	timed.tick=100*60;timed._spawn("ranged",Vector2(6,0))
	check(timed.enemies[timed._enemy_sequence].max_hp_raw==18*(10000+160*100)/10000*256,"Ranged HP follows the same formula at 100 s")
	check(shipped.tuning.hp_time_bps_per_s==0,"Neutral tuning has no time growth")
	var late := tuned_run({"hp_time_bps_per_s":160,"hp_time_from_s":40});clear_field(late)
	late.tick=40*60-1;late._spawn("walker",Vector2(6,0))
	check(late.enemies[late._enemy_sequence].max_hp_raw==12*256,"No time growth before hp_time_from_s")
	late.tick=40*60;late._spawn("walker",Vector2(6,0))
	check(late.enemies[late._enemy_sequence].max_hp_raw==12*(10000+160*40)/10000*256,"Time growth starts at hp_time_from_s")
	# The alive cap stops spawning exactly at the cap.
	var capped := tuned_run({"alive_cap":20});capped.tick=40*60
	for i in 10:capped._next_spawn=0;capped._spawn_wave()
	check(capped.alive_count()==20,"Spawning stops at alive_cap")
	# Orb overflow: nearest orb takes the amount, ties go to the smaller uid.
	var orbs_run := tuned_run({"orbs":{"overflow":"nearest","vacuum_on_seal":false}})
	orbs_run.orbs.clear()
	for i in Chapter.MAX_ORBS:orbs_run.orbs.append({"uid":i+1,"position":Vector2(float(i)*.1,0),"amount":1})
	orbs_run._drop_orb(Vector2(1.04,0),5)
	check(orbs_run.orbs.size()==Chapter.MAX_ORBS and orbs_run.orbs[10].amount==6 and orbs_run.orbs[399].amount==1,"Overflow orb merges into the nearest orb")
	orbs_run.orbs.clear()
	for i in Chapter.MAX_ORBS:orbs_run.orbs.append({"uid":100+i,"position":Vector2(50,50),"amount":1})
	orbs_run.orbs[7].position=Vector2(-1,0);orbs_run.orbs[7].uid=9
	orbs_run.orbs[8].position=Vector2(1,0);orbs_run.orbs[8].uid=4
	orbs_run._drop_orb(Vector2.ZERO,3)
	check(orbs_run.orbs[8].amount==4 and orbs_run.orbs[7].amount==1,"Equal distance merges into the smaller uid")
	var last_run := tuned_run({})
	last_run.orbs.clear()
	for i in Chapter.MAX_ORBS:last_run.orbs.append({"uid":i+1,"position":Vector2(float(i)*.1,0),"amount":1})
	last_run._drop_orb(Vector2(1.04,0),5)
	check(last_run.orbs[399].amount==6 and last_run.orbs[10].amount==1,"Neutral overflow still merges into the last orb")
	# Seal break absorbs the remaining orbs.
	var vac := tuned_run({"orbs":{"overflow":"last","vacuum_on_seal":true}});clear_field(vac)
	vac.hero.position=Chapter.ZONES[0];vac._zone_entered=true;vac.zone_kills=vac.tuning.seal_kills[0];vac._spawn_wave()
	var vac_champion: int=vac._champion_id
	vac.orbs.clear()
	for i in 5:vac.orbs.append({"uid":900+i,"position":Vector2(8+i,8),"amount":7+i})
	var orb_sum := 0
	for orb in vac.orbs:orb_sum+=int(orb.amount)
	var xp_before: int=vac.growth.snapshot().xp;var collected_before: int=vac.metrics.collected_xp
	vac._damage_enemy(vac_champion,context(vac,100000000),0)
	var vacuum_event := {}
	for event in vac.events:
		if event.type=="orb_vacuum":vacuum_event=event
	var champion_xp := int(vac.tuning.champions[0].xp)
	check(vac.orbs.is_empty() and vac.growth.snapshot().xp-xp_before==orb_sum+champion_xp,"Seal break absorbs every orb, the champion's own included")
	check(vac.metrics.collected_xp-collected_before==orb_sum+champion_xp and vacuum_event.get("amount",-1)==orb_sum+champion_xp,"Absorbed XP is counted and announced as orb_vacuum")
	var multi := tuned_run({"orbs":{"overflow":"last","vacuum_on_seal":true}});clear_field(multi)
	multi.hero.position=Chapter.ZONES[0];multi._zone_entered=true;multi.zone_kills=multi.tuning.seal_kills[0];multi._spawn_wave()
	multi.orbs.clear();multi.orbs.append({"uid":1,"position":Vector2(9,9),"amount":3000})
	multi._damage_enemy(multi._champion_id,context(multi,100000000),0)
	check(multi.growth.snapshot().pending_levels.size()>=5 and multi.growth.snapshot().level==12,"A seal absorb can stack several level-ups at once")
	var crowded := tuned_run({"alive_cap":1})
	crowded.hero.position=Chapter.ZONES[0];crowded._zone_entered=true;crowded.zone_kills=crowded.tuning.seal_kills[0];crowded._spawn_wave()
	check(crowded.alive_count()>1 and crowded._champion_id>0,"The champion spawns even when alive_cap is already full")
	var kept := tuned_run({});clear_field(kept);kept.hero.position=Chapter.ZONES[0];kept._zone_entered=true;kept.zone_kills=kept.tuning.seal_kills[0];kept._spawn_wave()
	kept.orbs.clear();kept.orbs.append({"uid":1,"position":Vector2(9,9),"amount":3})
	kept._damage_enemy(kept._champion_id,context(kept,100000000),0)
	check(kept.orbs.size()==2,"Neutral tuning leaves orbs on the ground at a seal break")
	# Primary bonus and secondary damping.
	var neutral_ember: Dictionary= tuned_run({}).effective_skill("chapter1.skill.ember").effects
	var boosted: Dictionary= tuned_run({"primary_bonus":{"chapter1.skill.ember":{"r1":{"add":{"projectiles":100,"hit_budget":-100},"mul_bps":{"damage_raw":15000},"cooldown_bps":5000}}}}).effective_skill("chapter1.skill.ember").effects
	check(boosted.projectiles==16 and boosted.hit_budget==1 and boosted.damage_raw==neutral_ember.damage_raw*15000/10000 and boosted.cooldown_ticks==neutral_ember.cooldown_ticks*5000/10000,"Primary bonus adds, multiplies and clamps to the catalog limits")
	var floor_cd: Dictionary= tuned_run({"primary_bonus":{"chapter1.skill.ember":{"r1":{"cooldown_bps":1}}}}).effective_skill("chapter1.skill.ember").effects
	check(floor_cd.cooldown_ticks==12,"Primary cooldown never goes under 12 ticks")
	var base_arc: Dictionary= tuned_run_owning({},"chapter1.skill.arc").effective_skill("chapter1.skill.arc").effects
	var damped_run := tuned_run_owning({"secondary":{"damage_bps":6000,"hit_budget_bps":5000,"cooldown_bps":13000,"max_chain_targets":3,"max_branches":1}},"chapter1.skill.arc")
	var damped: Dictionary=damped_run.effective_skill("chapter1.skill.arc").effects
	check(damped.damage_raw==base_arc.damage_raw*6000/10000 and damped.hit_budget==maxi(1,base_arc.hit_budget*5000/10000) and damped.cooldown_ticks==maxi(12,base_arc.cooldown_ticks*13000/10000),"Secondary skill: damage, budget and cooldown follow the data")
	check(damped.chain_targets==mini(base_arc.chain_targets,3) and damped.branches==mini(base_arc.branches,1),"Secondary skill: chain and branch caps")
	check(damped_run.effective_skill("chapter1.skill.ember").effects.damage_raw==neutral_ember.damage_raw,"The primary skill is not damped")
	# Child projectiles.
	var child_rule := {"chapter1.skill.ember":{"count":3,"life_ticks":28,"speed":9.0,"per_cast":4,"evolved_only":false}}
	var kid := tuned_run({"children":child_rule});clear_field(kid)
	var kid_context := context(kid,100000000)
	var ids: Array[int]=[]
	for i in 3:
		kid._spawn("walker",Vector2(5+i,0));ids.append(kid._enemy_sequence)
	kid._damage_enemy(ids[0],kid_context,0)
	check(kid._pending_children.size()==3,"One kill queues count children")
	kid._damage_enemy(ids[1],kid_context,0)
	check(kid._pending_children.size()==4,"Second kill is cut at per_cast")
	kid._damage_enemy(ids[2],kid_context,0)
	check(kid._pending_children.size()==4,"No children after per_cast is used up")
	var angle_a: float=kid._pending_children[0].p.direction.angle();var angle_b: float=kid._pending_children[1].p.direction.angle()
	check(is_equal_approx(wrapf(angle_b-angle_a,-PI,PI),TAU/3.0) and is_equal_approx(angle_a,wrapf(deg_to_rad(float((ids[0]*37)%360)),-PI,PI)),"Children fan out evenly from (id*37) mod 360 degrees")
	var spark: Dictionary=kid._pending_children[0].p
	check(not spark.hostile and spark.child and spark.pierce_left==0 and spark.cast_id==kid_context.uid and spark.hit_ids==[ids[0]],"Child projectile fields")
	kid.projectiles.clear();kid._step_projectiles()
	check(kid.projectiles.size()==4 and kid._pending_children.is_empty() and kid._contexts.has(kid_context.uid),"Children join after the step and keep the parent's context alive")
	var target_spawn: bool= kid._spawn("walker",Vector2(0,0))
	var victim: Dictionary=kid.enemies[kid._enemy_sequence];var shot: Dictionary=kid.projectiles[0]
	victim.position=shot.position+shot.direction*.1;victim.hp_raw=1000000*256;victim.max_hp_raw=victim.hp_raw
	kid._rebuild_grid();var hits_before: int=kid_context.remaining_hits
	kid.events.clear();kid.tick+=1;kid._step_projectiles()
	check(target_spawn and kid_context.remaining_hits<hits_before and victim.hp_raw<1000000*256,"A child's hit uses the parent's remaining_hits and damage")
	var kid_events := 0
	for event in kid.events:
		if event.type=="child_projectiles":kid_events+=1
	check(kid_events==0,"Hit that does not kill spawns no children")
	# Not primary, spent budget and final boss: no children.
	var rules2 := {"chapter1.skill.ember":child_rule["chapter1.skill.ember"],"chapter1.skill.arc":{"count":2,"life_ticks":24,"speed":7.0,"per_cast":12,"evolved_only":false}}
	var other := tuned_run({"children":rules2});clear_field(other);other._spawn("walker",Vector2(5,0))
	var other_context: Dictionary=context(other,100000000);other_context.skill_id="chapter1.skill.arc"
	other._damage_enemy(other._enemy_sequence,other_context,0)
	check(other._pending_children.is_empty(),"A kill by a non-primary skill makes no children")
	var spent := tuned_run({"children":child_rule});clear_field(spent);spent._spawn("walker",Vector2(5,0))
	var spent_context: Dictionary=context(spent,100000000);spent_context.remaining_hits=1
	spent._damage_enemy(spent._enemy_sequence,spent_context,0)
	check(spent._pending_children.is_empty() and spent.kills==1,"A cast whose hit budget is spent makes no children")
	var finale := tuned_run({"children":child_rule});clear_field(finale);finale.zone=2
	finale.hero.position=Chapter.ZONES[2];finale._zone_entered=true;finale.zone_kills=finale.tuning.seal_kills[2];finale._spawn_wave()
	finale._damage_enemy(finale._champion_id,context(finale,100000000),0)
	check(finale.mode=="victory" and finale._pending_children.is_empty(),"The final boss's death makes no children")
	# Friendly projectile cap.
	var cap_run := tuned_run({"children":child_rule,"friendly_projectile_cap":2});clear_field(cap_run)
	cap_run._spawn("walker",Vector2(5,0))
	cap_run._damage_enemy(cap_run._enemy_sequence,context(cap_run,100000000),0)
	check(cap_run._pending_children.size()==2 and cap_run.metrics.get("children_dropped",0)==1,"friendly_projectile_cap stops children and counts the dropped one")
	# Neutral tuning makes no children at all.
	var plain := tuned_run({});clear_field(plain);plain._spawn("walker",Vector2(5,0))
	plain._damage_enemy(plain._enemy_sequence,context(plain,100000000),0)
	check(plain._pending_children.is_empty() and not plain.metrics.has("children_dropped"),"Neutral tuning spawns no children and adds no metric key")
	# Arc leaves its context behind only when a chain kill made children.
	var arc_rule := {"chapter1.skill.arc":{"count":2,"life_ticks":24,"speed":7.0,"per_cast":12,"evolved_only":false}}
	var arc := tuned_run({"children":arc_rule},"chapter1.skill.arc");clear_field(arc)
	arc._spawn("walker",Vector2(3,0));arc.enemies[arc._enemy_sequence].hp_raw=1;arc._rebuild_grid()
	arc._auto_casts()
	check(arc._pending_children.size()==2 and arc._contexts.size()==1,"A chain kill keeps the arc context for its children")
	arc._step_projectiles()
	check(arc.projectiles.size()==2 and arc._contexts.size()==1,"Arc children are in flight with their context")
	var arc_plain := tuned_run({},"chapter1.skill.arc");clear_field(arc_plain)
	arc_plain._spawn("walker",Vector2(3,0));arc_plain.enemies[arc_plain._enemy_sequence].hp_raw=1;arc_plain._rebuild_grid()
	arc_plain._auto_casts()
	check(arc_plain._contexts.is_empty(),"Neutral arc still erases its context right after the cast")
	# Potion drop odds change without touching the loot random stream.
	var odds_a := tuned_run({});var odds_b := tuned_run({"potion":{"drop_one_in":360,"seal_drops":2,"start":3,"carry_max":5,"heal_bps":3500,"cooldown_ticks":240}})
	var odds_c := tuned_run({"potion":{"drop_one_in":1,"seal_drops":2,"start":3,"carry_max":5,"heal_bps":3500,"cooldown_ticks":240}})
	for r in [odds_a,odds_b,odds_c]:
		for i in 7:r._emit("death",Vector2(3,3),{"elite":false})
	check(odds_a._loot_rng.state==odds_b._loot_rng.state and odds_a._loot_rng.state==odds_c._loot_rng.state,"drop_one_in does not change the number of loot random draws per kill")
	check(odds_c.potion_pickups.size()==7,"drop_one_in 1 drops a potion at every kill")
	# alive counter agrees with a full count.
	var counted := Chapter.new();counted.start(11,"chapter1.skill.frost")
	var pilot_for_count: RefCounted=load("res://chapter1/core/chapter_pilot.gd").new();pilot_for_count.run=counted
	var counter_ok := true
	var fx: Dictionary=counted.effective_skill("chapter1.skill.frost").effects.duplicate(true)
	fx.damage_raw=100000000;fx.death_burst=0;fx.shatter_count=0
	for i in 1500:
		counted.step(pilot_for_count.decide())
		if i%50==49:
			# Kill one ordinary enemy right now, before _cleanup recounts.
			for e in counted.enemies.values():
				if e.hp_raw>0 and not e.elite:
					counted._damage_enemy(e.id,{"uid":999,"skill_id":"chapter1.skill.frost","effects":fx,"remaining_hits":128,"hit_ids":[],"evolved":false},0);break
		var real := 0
		for e in counted.enemies.values():
			if e.hp_raw>0:real+=1
		counter_ok=counter_ok and real==counted.alive_count()
	check(counter_ok,"alive_count counter equals a full count at every tick")

func event_of(r: RefCounted,type: String) -> Dictionary:
	var found := {}
	for event in r.events:
		if event.type==type:found=event
	return found
func heavy_rule(ward_gap: int=0) -> Dictionary:
	return {"heavy_bps":2000,"gap_ticks":120,"iframe_ticks":45,"graze_bps":1000,"ward_gap_ticks":ward_gap}

## Second-round rules (M2 round 2): every one is data-driven and off at the neutral values.
func round2_checks() -> void:
	# Data and loader: shipped values equal today's behaviour, bad documents are rejected.
	var disk := Chapter.new();disk.start(5)
	check(disk.tuning.seal_kills==[1000,1350,1350] and disk.tuning.presentation.arc_stripe_ticks==24 and disk.tuning.marks.mark_bps==9000 and disk.tuning.heavy_hit.heavy_bps==2000 and disk.tuning.heavy_hit.ward_gap_ticks==60 and disk.tuning.final_level_on_boss_spawn and disk.tuning.hero_shot.spread_mrad==160,"Shipped round-2 keys hold the 2026-11-16 confirmed values")
	var ember_children: Dictionary=disk.tuning.children["chapter1.skill.ember"]
	check(ember_children.evolved_only and disk.tuning.spawn.mix.charger_roll==94 and disk.tuning.spawn.mix.ranged_roll==82,"Shipped children are evolved-only and the specialist mix is today's")
	check(disk.tuning.heavy_hit.is_read_only() and disk.tuning.spawn.mix.is_read_only() and disk.tuning.presentation.is_read_only() and disk.tuning.marks.is_read_only() and disk.tuning.seal_kills.is_read_only() and ember_children.is_read_only(),"Round-2 tuning parts are read-only")
	var bad := Chapter.new()
	var no_mix := tuning_with({});no_mix.spawn.mix.erase("zone_step")
	var no_flag := tuning_with({"children":{"chapter1.skill.ember":{"count":3,"life_ticks":28,"speed":9.0,"per_cast":4}}})
	var bad_docs := [tuning_with({"seal_kills":[1,2]}),tuning_with({"seal_kills":[1,2,0]}),tuning_with({"presentation":{"arc_stripe_ticks":0}}),
		tuning_with({"marks":{"mark_bps":-1,"mark_ticks":180}}),tuning_with({"marks":{"mark_bps":100,"mark_ticks":0}}),
		tuning_with({"heavy_hit":{"heavy_bps":20000,"gap_ticks":120,"iframe_ticks":45,"graze_bps":1000,"ward_gap_ticks":0}}),
		tuning_with({"heavy_hit":{"heavy_bps":2000,"gap_ticks":120,"iframe_ticks":0,"graze_bps":1000,"ward_gap_ticks":0}}),
		tuning_with({"heavy_hit":{"heavy_bps":2000,"gap_ticks":120,"iframe_ticks":45,"graze_bps":1000}}),
		tuning_with({"heavy_hit":{"heavy_bps":2000,"gap_ticks":120,"iframe_ticks":23,"graze_bps":1000,"ward_gap_ticks":0}}),
		tuning_with({"heavy_hit":{"heavy_bps":1,"gap_ticks":3600,"iframe_ticks":600,"graze_bps":0,"ward_gap_ticks":0}}),
		tuning_with({"heavy_hit":{"heavy_bps":999,"gap_ticks":120,"iframe_ticks":45,"graze_bps":1000,"ward_gap_ticks":0}}),
		tuning_with({"heavy_hit":{"heavy_bps":2000,"gap_ticks":44,"iframe_ticks":45,"graze_bps":1000,"ward_gap_ticks":0}}),
		tuning_with({"heavy_hit":{"heavy_bps":2000,"gap_ticks":601,"iframe_ticks":45,"graze_bps":1000,"ward_gap_ticks":0}}),
		tuning_with({"heavy_hit":{"heavy_bps":2000,"gap_ticks":120,"iframe_ticks":121,"graze_bps":1000,"ward_gap_ticks":0}}),
		tuning_with({"heavy_hit":{"heavy_bps":2000,"gap_ticks":120,"iframe_ticks":45,"graze_bps":499,"ward_gap_ticks":0}}),
		tuning_with({"final_level_on_boss_spawn":"yes"}),tuning_with({"hero_shot":{"spread_mrad":-5}}),no_mix,no_flag]
	var rejected := 0
	for doc in bad_docs:
		if not bad.set_tuning(doc):rejected+=1
	check(rejected==bad_docs.size(),"Every malformed round-2 document is rejected (%d of %d)"%[rejected,bad_docs.size()])
	# Seal kills come from the data.
	var sk := tuned_run({"seal_kills":[3,5,7]});clear_field(sk)
	sk.hero.position=Chapter.ZONES[0];sk._zone_entered=true;sk.zone_kills=2;sk._spawn_wave()
	check(sk._champion_id==-1 and sk.objective().kind=="seal_kills" and sk.objective().done==2 and sk.objective().total==3 and sk.objective().title_key.is_empty(),"Below seal_kills[0] there is no champion and the objective shows the data value")
	sk.zone_kills=3;sk._spawn_wave()
	check(sk._champion_id>0,"The champion comes at seal_kills[0]")
	sk.zone=2;sk._champion_id=-1;sk.hero.position=Chapter.ZONES[2];sk.zone_kills=6;sk._spawn_wave()
	check(sk._champion_id==-1,"Zone 2 reads seal_kills[2]")
	sk.zone_kills=7;sk._spawn_wave()
	check(sk._champion_id>0 and sk.seals[2].champion_spawned,"Zone 2 champion at seal_kills[2]")
	# Specialist mix.
	var all_chargers: Dictionary=tuning_with({}).spawn;all_chargers.mix={"charger_from_s":0,"charger_roll":0,"ranged_from_s":0,"ranged_roll":0,"zone_step":3}
	var mixed := tuned_run({"spawn":all_chargers});clear_field(mixed);mixed.tick=40*60;mixed._next_spawn=0;mixed._spawn_wave()
	var kinds := {}
	for e in mixed.enemies.values():kinds[e.kind]=true
	check(mixed.alive_count()>=6 and kinds.size()==1 and kinds.has("charger"),"Mix with roll 0 makes only chargers")
	var all_ranged: Dictionary=tuning_with({}).spawn;all_ranged.mix={"charger_from_s":0,"charger_roll":100,"ranged_from_s":0,"ranged_roll":0,"zone_step":3}
	var shooters := tuned_run({"spawn":all_ranged});clear_field(shooters);shooters.tick=40*60;shooters._next_spawn=0;shooters._spawn_wave()
	kinds={}
	for e in shooters.enemies.values():kinds[e.kind]=true
	check(shooters.alive_count()>=6 and kinds.size()==1 and kinds.has("ranged"),"A charger roll above 99 never spawns a charger")
	var from_s: Dictionary=tuning_with({}).spawn;from_s.mix={"charger_from_s":50,"charger_roll":0,"ranged_from_s":60,"ranged_roll":0,"zone_step":3}
	var late := tuned_run({"spawn":from_s});clear_field(late);late.tick=40*60;late._next_spawn=0;late._spawn_wave()
	kinds={}
	for e in late.enemies.values():kinds[e.kind]=true
	check(kinds.size()==1 and kinds.has("walker"),"The specialist minutes (charger_from_s, ranged_from_s) are read from the data")
	# Children only from the evolved primary.
	var evo_rule := {"chapter1.skill.ember":{"count":3,"life_ticks":28,"speed":9.0,"per_cast":12,"evolved_only":true}}
	var eo := tuned_run({"children":evo_rule});clear_field(eo);eo._spawn("walker",Vector2(5,0))
	eo._damage_enemy(eo._enemy_sequence,context(eo,100000000),0)
	check(eo.kills==1 and eo._pending_children.is_empty() and event_of(eo,"child_projectiles").is_empty(),"Before evolution a primary kill makes no children")
	eo._spawn("walker",Vector2(6,0));var evo_context := context(eo,100000000);evo_context.evolved=true
	eo._damage_enemy(eo._enemy_sequence,evo_context,0)
	check(eo._pending_children.size()==3 and eo._pending_children[0].p.child and event_of(eo,"child_projectiles").get("count",0)==3,"After evolution a kill makes count children and the child_projectiles event")
	var cap_evo := tuned_run({"children":evo_rule,"friendly_projectile_cap":1});clear_field(cap_evo);cap_evo._spawn("walker",Vector2(5,0))
	cap_evo._damage_enemy(cap_evo._enemy_sequence,context(cap_evo,100000000),0)
	check(not cap_evo.metrics.has("children_dropped"),"A suppressed pre-evolution child is not counted as dropped")
	# Mark resonance.
	var mk := tuned_run({"marks":{"mark_bps":4000,"mark_ticks":180}});clear_field(mk)
	mk._spawn("walker",Vector2(5,0));var mark_id: int=mk._enemy_sequence;var marked: Dictionary=mk.enemies[mark_id]
	marked.hp_raw=1000000*256;marked.max_hp_raw=marked.hp_raw
	var arc_hit := context(mk,100);arc_hit.skill_id="chapter1.skill.arc"
	mk._damage_enemy(mark_id,arc_hit,0)
	check(marked.get("mark_until_b",0)==mk.tick+180 and not marked.has("mark_until_a"),"A secondary hit marks the enemy for mark_ticks in the skill's own slot")
	mk.events.clear();var hp_one: int=marked.hp_raw
	mk._damage_enemy(mark_id,context(mk,1000),0)
	var marked_hit := event_of(mk,"hit")
	check(hp_one-marked.hp_raw==1400 and marked_hit.get("assist_raw",-1)==400 and marked_hit.get("assist_skill_ids",[])==["chapter1.skill.arc"],"One live mark: +mark_bps damage, credited to the marking skill on the hit event")
	check(mk.metrics.get("assist_raw",{}).get("chapter1.skill.arc",0)==400,"metrics.assist_raw keeps the marking skill's share")
	var frost_hit := context(mk,100);frost_hit.skill_id="chapter1.skill.frost"
	mk._damage_enemy(mark_id,frost_hit,0)
	mk.events.clear();var hp_two: int=marked.hp_raw
	mk._damage_enemy(mark_id,context(mk,1000),0)
	marked_hit=event_of(mk,"hit")
	check(hp_two-marked.hp_raw==1800 and marked_hit.get("assist_raw",-1)==800 and marked_hit.get("assist_skill_ids",[])==["chapter1.skill.frost","chapter1.skill.arc"],"Two live marks add mark_bps each")
	check(mk.metrics.assist_raw["chapter1.skill.frost"]==400 and mk.metrics.assist_raw["chapter1.skill.arc"]==800,"The extra damage is split between the marking skills without loss")
	mk.tick+=181;mk.events.clear();var hp_three: int=marked.hp_raw
	mk._damage_enemy(mark_id,context(mk,1000),0)
	check(hp_three-marked.hp_raw==1000 and not event_of(mk,"hit").has("assist_raw"),"Expired marks add nothing")
	# Credit counts real HP removed: a nearly dead enemy gives no extra share.
	mk._spawn("walker",Vector2(6,0));var weak_id: int=mk._enemy_sequence;var weak: Dictionary=mk.enemies[weak_id]
	mk._damage_enemy(weak_id,arc_hit.duplicate(true),0)
	weak.hp_raw=1000;mk.events.clear();var assist_before: int=mk.metrics.assist_raw["chapter1.skill.arc"]
	mk._damage_enemy(weak_id,context(mk,1000),0)
	check(mk.metrics.assist_raw["chapter1.skill.arc"]==assist_before and event_of(mk,"hit").get("assist_raw",-1)==0,"A killing blow no stronger than its unmarked self earns the mark nothing")
	var unmarked := tuned_run({});clear_field(unmarked);unmarked._spawn("walker",Vector2(5,0));var plain_id: int=unmarked._enemy_sequence
	unmarked._damage_enemy(plain_id,arc_hit.duplicate(true),0)
	check(not unmarked.enemies[plain_id].has("mark_until_a") and not unmarked.enemies[plain_id].has("mark_until_b") and not unmarked.metrics.has("assist_raw"),"mark_bps 0 leaves no mark keys and no metric key")
	# Heavy hits.
	var hv := tuned_run({"heavy_hit":heavy_rule()})
	hv.tick=100;hv.events.clear();var hp_start: int=hv.hero.hp_raw
	hv._hero_damage(10000,Vector2.ZERO)
	var first_hit := event_of(hv,"hero_hit")
	check(hv.hero.hp_raw==hp_start-10000 and hv._invulnerable_until==145 and first_hit.incoming_raw==10000 and not first_hit.has("graze"),"A heavy hit lands in full and grants iframe_ticks of invulnerability")
	hv.tick=144;hv._hero_damage(10000,Vector2.ZERO)
	check(hv.hero.hp_raw==hp_start-10000,"No damage while the heavy hit's invulnerability lasts")
	hv.tick=150;hv.events.clear();var hp_mid: int=hv.hero.hp_raw
	hv._hero_damage(10000,Vector2.ZERO)
	var graze_hit := event_of(hv,"hero_hit")
	check(hp_mid-hv.hero.hp_raw==1000 and graze_hit.get("graze",false) and graze_hit.incoming_raw==10000 and hv._invulnerable_until==195,"A second heavy hit within gap_ticks only grazes (graze_bps) and is flagged")
	hv.tick=219;hv._hero_damage(10000,Vector2.ZERO);var hp_after_graze: int=hv.hero.hp_raw
	check(hp_after_graze==hp_mid-1000-1000 and hv._last_heavy_tick==100,"A graze does not restart the gap")
	hv.tick=265;hv.events.clear();var hp_late: int=hv.hero.hp_raw
	hv._hero_damage(10000,Vector2.ZERO)
	check(hp_late-hv.hero.hp_raw==10000 and not event_of(hv,"hero_hit").has("graze") and hv._last_heavy_tick==265,"After the gap the next heavy hit lands in full again")
	var light := tuned_run({"heavy_hit":heavy_rule()});light.tick=10
	light._hero_damage(1000,Vector2.ZERO)
	check(light._invulnerable_until==34 and light._last_heavy_tick==-1,"A light hit keeps 24 ticks and records no heavy hit")
	var heavy_off := tuned_run({});heavy_off.tick=100;var hp_off: int=heavy_off.hero.hp_raw
	heavy_off._hero_damage(10000,Vector2.ZERO);heavy_off.tick=125;heavy_off._hero_damage(10000,Vector2.ZERO)
	check(hp_off-heavy_off.hero.hp_raw==20000 and heavy_off._invulnerable_until==149,"heavy_bps 0: two big hits both land and the invulnerability stays 24 ticks")
	var heavy_armor := tuned_run({"heavy_hit":heavy_rule()});heavy_armor._gear_stats.damage_reduction_bps=5000
	heavy_armor._hero_damage(7000,Vector2.ZERO)
	check(heavy_armor._last_heavy_tick==heavy_armor.tick,"Heavy is judged on the damage before reduction")
	# Boss floor strike versus the boss's own wind-up.
	for gap in [60,0]:
		var ward := tuned_run({"heavy_hit":heavy_rule(gap)});clear_field(ward);ward.zone=2
		ward.hero.position=Chapter.ZONES[2];ward._zone_entered=true;ward.zone_kills=ward.tuning.seal_kills[2];ward._spawn_wave()
		var warden: Dictionary=ward.enemies[ward._champion_id]
		ward.tick=1000;warden.state="windup";warden.state_until=1000+72+10;ward._next_ward=1000
		ward._step_chapter_hazards()
		if gap>0:
			check(ward.chapter_hazards.is_empty() and ward._next_ward==1060,"A floor strike that would burst within the gap of the boss attack is put off by the gap")
			ward.tick=1060;warden.state_until=1060+72+60;ward._step_chapter_hazards()
			check(ward.chapter_hazards.size()==1 and absi(int(ward.chapter_hazards[0].expires)-int(warden.state_until))>=60,"The floor strike that is scheduled bursts at least the gap away from the boss attack")
			ward.tick=2000;warden.state="move";ward._next_ward=2000;ward._step_chapter_hazards()
			check(ward.chapter_hazards.size()==1 and ward.chapter_hazards[0].started==2000,"A boss that is not winding up never delays the floor strike")
		else:
			check(ward.chapter_hazards.size()==1,"ward_gap_ticks 0 keeps the floor strike schedule")
	# Final level at the boss's arrival.
	var xp12 := [0,5,21,47,104,265,525,840,1257,1781,2959,12000]
	var gr := tuned_run({"final_level_on_boss_spawn":true,"xp_thresholds":xp12});clear_field(gr);gr.zone=2
	gr.hero.position=Chapter.ZONES[2];gr._zone_entered=true;gr.zone_kills=gr.tuning.seal_kills[2];gr.orbs.append({"uid":1,"position":Vector2(9,9),"amount":50})
	gr._spawn_wave()
	var grace := event_of(gr,"seal_grace")
	check(gr.orbs.is_empty() and gr.growth.snapshot().level==12 and gr.growth.snapshot().xp==12000 and grace.get("level",0)==12 and grace.get("amount",0)==12000-50,"The final boss's arrival absorbs the orbs and lifts the run to the last level")
	var no_grace := tuned_run({"xp_thresholds":xp12});clear_field(no_grace);no_grace.zone=2
	no_grace.hero.position=Chapter.ZONES[2];no_grace._zone_entered=true;no_grace.zone_kills=no_grace.tuning.seal_kills[2];no_grace._spawn_wave()
	check(no_grace.growth.snapshot().level==1 and event_of(no_grace,"seal_grace").is_empty(),"The grace is off with final_level_on_boss_spawn false")
	var early_grace := tuned_run({"final_level_on_boss_spawn":true,"xp_thresholds":xp12});clear_field(early_grace)
	early_grace.hero.position=Chapter.ZONES[0];early_grace._zone_entered=true;early_grace.zone_kills=early_grace.tuning.seal_kills[0];early_grace._spawn_wave()
	check(early_grace._champion_id>0 and early_grace.growth.snapshot().level==1 and event_of(early_grace,"seal_grace").is_empty(),"The first two guardians grant no grace")
	var maxed := tuned_run({"final_level_on_boss_spawn":true,"xp_thresholds":xp12});clear_field(maxed);maxed.zone=2;maxed.growth.award_xp(20000)
	maxed.hero.position=Chapter.ZONES[2];maxed._zone_entered=true;maxed.zone_kills=maxed.tuning.seal_kills[2];maxed._spawn_wave()
	check(event_of(maxed,"seal_grace").is_empty() and maxed.growth.snapshot().xp==20000,"A run already at the last level gets no grace event")
	# The strike is already telegraphed when the boss would start its wind-up: the boss waits instead.
	var held := tuned_run({"heavy_hit":heavy_rule(60)});clear_field(held);held.zone=2
	held.hero.position=Chapter.ZONES[2];held._zone_entered=true;held.zone_kills=held.tuning.seal_kills[2];held._spawn_wave()
	var held_boss: Dictionary=held.enemies[held._champion_id]
	held.tick=500;held._next_ward=500;held._step_chapter_hazards()
	check(held.chapter_hazards.size()==1 and held.chapter_hazards[0].expires==572,"A floor strike is scheduled with the boss idle")
	held.tick=510;held_boss.state="move";held._step_enemies()
	check(held_boss.state=="recover" and held_boss.state_until==511,"A wind-up that would end within the gap of the burst is not started")
	held.tick=578;held_boss.state="move";held._step_enemies()
	check(held_boss.state!="recover","A wind-up ending exactly the gap after the burst is allowed")
	held_boss.state="move";held.tick=500;held.chapter_hazards.clear();held._step_enemies()
	check(held_boss.state!="recover","With no strike pending the boss is never held")
	var trace := tuned_run({"heavy_hit":heavy_rule(60)});clear_field(trace);trace.zone=2
	trace.hero.position=Chapter.ZONES[2];trace._zone_entered=true;trace.zone_kills=trace.tuning.seal_kills[2];trace._spawn_wave()
	trace.hero.max_hp_raw=1000000*256;trace.hero.hp_raw=trace.hero.max_hp_raw
	var trace_boss: Dictionary=trace.enemies[trace._champion_id];trace_boss.position=trace.hero.position+Vector2(2,0)
	var bursts: Array[int]=[]
	var swings: Array[int]=[]
	for i in 1500:
		trace.step()
		for event in trace.events:
			if event.type=="chapter_burst":bursts.append(trace.tick)
			elif event.type=="enemy_attack" and event.kind=="elite":swings.append(trace.tick)
		if trace.mode!="playing":break
	var closest := 100000
	for b in bursts:
		for s in swings:closest=mini(closest,absi(b-s))
	check(bursts.size()>=3 and swings.size()>=3 and closest>=60,"Real steps: floor bursts and boss attacks stay %d ticks apart (bursts %d, attacks %d)"%[closest,bursts.size(),swings.size()])
	# The grace goes through step() into the choice mode and every level is chosen in turn.
	var gs := tuned_run({"final_level_on_boss_spawn":true,"xp_thresholds":xp12});clear_field(gs);gs.zone=2
	gs.hero.position=Chapter.ZONES[2];gs._zone_entered=true;gs.zone_kills=gs.tuning.seal_kills[2];gs.hero.max_hp_raw=1000000*256;gs.hero.hp_raw=gs.hero.max_hp_raw
	gs.step()
	check(gs.mode=="choice" and gs.growth.snapshot().pending_levels.size()==11 and gs.growth.snapshot().level==12,"The grace opens the choice mode with every level pending")
	var picked := 0
	while gs.mode=="choice" and picked<20:
		var offer: Dictionary=gs.get_offer()
		if offer.is_empty() or not gs.choose(offer.token,offer.cards[0].id):break
		picked+=1
	check(picked==11 and gs.mode=="playing" and gs.growth.snapshot().pending_levels.is_empty(),"Eleven grace levels are chosen one after another")
	# A chain's hits each take the mark bonus once.
	var chain_bonus := {"chapter1.skill.arc":{"r1":{"add":{"chain_targets":3}}}}
	var cm := tuned_run({"marks":{"mark_bps":4000,"mark_ticks":180},"primary_bonus":chain_bonus},"chapter1.skill.arc");clear_field(cm)
	var chain_ids: Array[int]=[]
	for i in 3:
		cm._spawn("walker",Vector2(3+i,0));chain_ids.append(cm._enemy_sequence)
		var chain_target: Dictionary=cm.enemies[cm._enemy_sequence];chain_target.hp_raw=1000000*256;chain_target.max_hp_raw=chain_target.hp_raw
		var mark_effects: Dictionary=cm.effective_skill("chapter1.skill.arc").effects.duplicate(true)
		mark_effects.damage_raw=100;mark_effects.death_burst=0;mark_effects.shatter_count=0
		cm._damage_enemy(cm._enemy_sequence,{"uid":900+i,"skill_id":"chapter1.skill.ember","effects":mark_effects,"remaining_hits":128,"hit_ids":[],"evolved":false},0)
	cm._rebuild_grid();cm.events.clear()
	var arc_base: int=cm.effective_skill("chapter1.skill.arc").effects.damage_raw
	cm._auto_casts()
	var chain_hits: Array[Dictionary]=[]
	for event in cm.events:
		if event.type=="hit" and event.skill_id=="chapter1.skill.arc":chain_hits.append(event)
	var once_ok := chain_hits.size()>=2
	var assist_sum := 0
	for hit in chain_hits:
		once_ok=once_ok and hit.damage_raw==arc_base*14000/10000 and hit.get("assist_raw",-1)==arc_base*4000/10000 and hit.get("assist_skill_ids",[]).size()==1
		assist_sum+=int(hit.get("assist_raw",0))
	check(once_ok and cm.metrics.assist_raw["chapter1.skill.ember"]==assist_sum,"Each hit of one chain cast takes the mark bonus once (%d hits)"%chain_hits.size())
	# Hero shot spread.
	var bonus := {"chapter1.skill.ember":{"r1":{"add":{"projectiles":2}}}}
	for step in [[160,.16],[300,.3]]:
		var shot := tuned_run({"hero_shot":{"spread_mrad":step[0]},"primary_bonus":bonus});clear_field(shot);shot._spawn("walker",Vector2(5,0));shot._rebuild_grid();shot._auto_casts()
		check(shot.projectiles.size()>=3 and is_equal_approx(wrapf(shot.projectiles[1].direction.angle()-shot.projectiles[0].direction.angle(),-PI,PI),float(step[1])),"Neighbouring shots are spread_mrad apart: %d"%int(step[0]))
	# Measurement-only switch.
	for off in [true,false]:
		var solo := tuned_run_owning({},"chapter1.skill.arc");clear_field(solo);solo.debug_secondary_off=off;solo._spawn("walker",Vector2(4,0));solo._rebuild_grid();solo._auto_casts()
		check(int(solo.metrics.casts.get("chapter1.skill.ember",0))==1 and int(solo.metrics.casts.get("chapter1.skill.arc",0))==(0 if off else 1),"debug_secondary_off casts the primary alone: %s"%str(off))

## G1 permanent build (spec 9, "P2 unit checks"). The rule tests read the neutral (pre-M2) tuning so that the
## numbers are fixed; the shipped numbers are covered by the golden replay.
const FROST := "chapter1.skill.frost"
const EMBER := "chapter1.skill.ember"
const FROST_WITCH := "chapter1.character.frost"
const EMBER_WITCH := "chapter1.character.ember"
## Experience that puts a witch on exactly this level (the thresholds of character_progression.json).
const LEVEL_XP := {1:0,6:2100,12:8000,18:19500,20:25000}

func build_of(ranks: Dictionary,level: int=20,character: String=FROST_WITCH) -> Dictionary:
	var is_frost := character==FROST_WITCH
	return {"character_id":character,"tree_id":"witch.frost" if is_frost else "","tree_revision":1 if is_frost else 0,"ranks":ranks,"character_level":level,"character_xp":int(LEVEL_XP[level])}
func built_run(ranks: Dictionary,level: int=20,mod: Dictionary={},primary: String=FROST,seed_: int=17,character: String=FROST_WITCH) -> RefCounted:
	var r := Chapter.new()
	check(r.set_tuning(tuning_with(mod)),"Build run tuning accepted")
	check(r.configure_build(build_of(ranks,level,character)),"Build accepted "+str(ranks.keys())+" "+str(r.errors))
	check(r.start(seed_,primary),"Build run starts "+str(r.errors))
	return r
## A frost context with a fixed damage; `effects` come from the run so the build is part of it.
func frost_context(r: RefCounted,amount: int,uid: int=500) -> Dictionary:
	var effects: Dictionary=r.effective_skill(FROST).effects.duplicate(true)
	effects.damage_raw=amount;effects.death_burst=0
	return {"uid":uid,"skill_id":FROST,"effects":effects,"remaining_hits":128,"hit_ids":[],"evolved":false}
func tough(r: RefCounted,kind: String,point: Vector2) -> Dictionary:
	r._spawn(kind,point);var e: Dictionary=r.enemies[r._enemy_sequence];e.hp_raw=1000000*256;e.max_hp_raw=e.hp_raw
	return e
func hash_without(r: RefCounted,drop: Array) -> String:
	var snap: Dictionary=r.snapshot()
	for key in drop:snap.erase(key)
	return JSON.stringify(snap).sha256_text()
func event_count(r: RefCounted,type: String) -> int:
	var n := 0
	for event in r.events:
		if event.type==type:n+=1
	return n

func build_checks() -> void:
	# 1. A build with no ranks (Lv 1) plays the very same run as no build, snapshot for snapshot.
	for setup in [[FROST,FROST_WITCH],[EMBER,EMBER_WITCH]]:
		var plain := Chapter.new();plain.start(11,setup[0])
		var empty := Chapter.new()
		check(empty.configure_build(build_of({},1,setup[1])) and empty.start(11,setup[0]),"Empty build starts "+setup[1])
		var same := true;var pilot_a: RefCounted=load("res://chapter1/core/chapter_pilot.gd").new();pilot_a.run=plain
		var pilot_b: RefCounted=load("res://chapter1/core/chapter_pilot.gd").new();pilot_b.run=empty
		for i in 2400:
			plain.step(pilot_a.decide());empty.step(pilot_b.decide())
			if i%300==299 and hash_without(plain,[])!=hash_without(empty,["build","progress"]):same=false;break
		check(same,"Empty build: snapshot without build/progress equals the no-build run at every checkpoint ("+setup[1]+")")
		check(not plain.snapshot().has("build") and not plain.snapshot().has("progress") and not plain.snapshot().has("fields") and plain.progress_summary().is_empty(),"No build: no build/progress/fields keys and no summary")
		var shown: Dictionary=empty.snapshot()
		check(shown.has("build") and shown.has("progress") and not shown.has("fields") and shown.build.ranks==[] and shown.build.character_level==1,"Empty build: build and progress keys only, no fields")
		check(not empty.growth.snapshot().has("options"),"Empty build adds no growth option key")
	# Rejections leave the standing build alone.
	var gate := Chapter.new()
	var bad_ranks := build_of({"witch.frost.volley":1},20)
	var bad_level := build_of({"witch.frost.needle":1},20);bad_level.character_level=19
	var missing_key := build_of({},1);missing_key.erase("character_xp")
	var late_tier := build_of({"witch.frost.volley":2,"witch.frost.needle":2},1)
	var stale := build_of({},1);stale.tree_revision=7
	var overspent := build_of({"witch.frost.needle":5,"witch.frost.volley":3,"witch.frost.oath_lance":3,"witch.common.vigor":5,"witch.common.ward":3,"witch.common.favor":2,"witch.frost.deep_oath":1,"witch.frost.rime":5},20)
	var ember_tree := build_of({"witch.frost.needle":1},20,EMBER_WITCH);ember_tree.tree_id="witch.frost";ember_tree.tree_revision=1
	check(gate.configure_build(build_of({"witch.frost.needle":2},1)),"A legal build is accepted")
	var rejected := 0
	for candidate in [{},bad_ranks,bad_level,missing_key,late_tier,stale,overspent,ember_tree]:
		if not gate.configure_build(candidate):rejected+=1
	check(rejected==8,"Eight malformed builds are rejected (%d of 8)"%rejected)
	check(gate.start(5,FROST) and gate.snapshot().build.ranks==[["witch.frost.needle",2]],"A rejected build leaves the earlier one in place")
	gate.clear_build();gate.start(5,FROST)
	check(not gate.snapshot().has("build"),"clear_build() returns to the run without a build")
	# 10. A build belongs to one witch's skill.
	var wrong := Chapter.new();wrong.configure_build(build_of({"witch.frost.needle":1},6))
	check(not wrong.start(5,EMBER) and wrong.mode=="menu" and not wrong.errors.is_empty(),"A frost build refuses to start an ember run and changes nothing")
	var wrong_ember := Chapter.new();wrong_ember.configure_build(build_of({},1,EMBER_WITCH))
	check(not wrong_ember.start(5,FROST) and wrong_ember.start(5,EMBER),"An ember witch's build starts ember only")
	# 2. Needle 5 on rank 1: pierce 2 -> 5 and the line of enemies really takes more hits.
	var base := tuned_run({},FROST)
	var needle := built_run({"witch.frost.needle":5},20)
	var base_fx: Dictionary=base.effective_skill(FROST).effects;var needle_fx: Dictionary=needle.effective_skill(FROST).effects
	check(base_fx.pierce==2 and needle_fx.pierce==5 and needle_fx.hit_budget==base_fx.hit_budget+12,"Needle 5: pierce 2 -> 5 and the budget grows with it")
	check(needle_fx.damage_raw==base_fx.damage_raw*11000/10000 and needle_fx.cooldown_ticks==base_fx.cooldown_ticks,"Needle 5: damage x1.10 (floor), nothing else")
	var struck: Array=[]
	for r in [base,needle]:
		clear_field(r);var line: Array=[]
		for i in 8:
			var e := tough(r,"walker",Vector2(2.0+float(i),0));line.append(int(e.id))
		r._rebuild_grid();r._auto_casts()
		for i in 60:
			r.tick+=1;r._step_projectiles()
		var count := 0
		for id_ in line:
			if r.enemies[id_].hp_raw<r.enemies[id_].max_hp_raw:count+=1
		struck.append(count)
	check(struck[0]==3 and struck[1]==6,"Needle 5: one rank-1 lance hits 3 enemies in a line, with the build 6 (%s)"%str(struck))
	# 3. Chill 1: rank 1 freezes on the 4th hit (it never froze before).
	var chill := built_run({"witch.frost.chill":1},1)
	var chill_target := tough(chill,"walker",Vector2(4,0));var chill_ctx := frost_context(chill,100)
	check(base_fx.freeze_stacks==0 and chill_ctx.effects.freeze_stacks==4,"Chill 1 switches freezing on at 4 hits (before: off)")
	var frozen_at := 0
	for i in 4:
		chill._damage_enemy(chill_target.id,chill_ctx,0)
		if chill.tick<int(chill_target.frozen_until) and frozen_at==0:frozen_at=i+1
	check(frozen_at==4,"The fourth hit freezes the target (frozen on hit %d)"%frozen_at)
	var chill3 := built_run({"witch.frost.chill":3},1)
	check(frost_context(chill3,1).effects.freeze_stacks==2,"Chill 3: freeze after 2 hits")
	# 4. Frost field: create, slow, 6-tick judgement, freeze stacks, pulse, cap, end.
	var field_run := built_run({"witch.frost.rime":2,"witch.frost.field":1,"witch.frost.chill":1},6)
	clear_field(field_run);field_run.hero.position=Vector2.ZERO
	var victim := tough(field_run,"walker",Vector2(5,0));field_run._rebuild_grid()
	check(field_run._field_rule.interval_ticks==180 and field_run._field_rule.radius_cm==300 and field_run._field_rule.duration_ticks==120 and field_run._field_rule.slow_bps==4500 and field_run._field_rule.max_fields==1,"Field rank 1 values come from the tree data")
	field_run.tick=179;field_run._step_fields()
	check(field_run._fields.is_empty() and event_count(field_run,"frost_field")==0,"No field before its interval")
	field_run.tick=180;field_run._step_fields()
	var created := event_of(field_run,"frost_field")
	check(field_run._fields.size()==1 and created.get("radius_cm",0)==300 and created.get("until_tick",0)==300 and created.get("uid",0)==1 and created.position==Vector2(5,0),"The field appears at the nearest enemy with radius and end tick in its event")
	check(victim.slow_bps==4500 and victim.slow_until==188,"The enemy inside is slowed 45% for 8 ticks")
	victim.slow_until=0;field_run.tick=185;field_run._step_fields()
	check(victim.slow_until==0,"Between judgements (age 5) nothing is judged")
	field_run.tick=186;field_run._step_fields()
	check(victim.slow_until==194,"Every 6 ticks of age the field judges again")
	victim.position=Vector2(5,3.2);field_run.tick=192;field_run._step_fields()
	check(victim.slow_until==194,"An enemy outside the radius is left alone")
	victim.position=Vector2(5,0);field_run.tick=204;field_run._step_fields()
	check(victim.freeze_stacks==0,"No freeze stack before freeze_every_ticks")
	field_run.tick=210;field_run._step_fields()
	check(victim.freeze_stacks==1 and victim.freeze_expires==390,"One freeze stack every 30 ticks (threshold from the lance: 4)")
	field_run.tick=299;field_run._step_fields();check(field_run._fields.size()==1,"The field lasts until its end tick")
	field_run.tick=300;field_run._step_fields()
	check(field_run._fields.is_empty() and event_of(field_run,"frost_field_end").get("uid",0)==1,"The field ends at until_tick with an end event")
	check(field_run._next_field==360,"The next field waits a full interval after the last was made (180 + 180)")
	var field_off := tuned_run({},FROST);clear_field(field_off);tough(field_off,"walker",Vector2(5,0));field_off._rebuild_grid();field_off.tick=180;field_off._step_fields()
	check(field_off._fields.is_empty() and not field_off.snapshot().has("fields"),"Without the field node nothing is created and no fields key appears")
	var pulse_run := built_run({"witch.frost.rime":2,"witch.frost.field":2,"witch.frost.dominion":1},12)
	clear_field(pulse_run);var pulse_target := tough(pulse_run,"walker",Vector2(5,0));pulse_run._rebuild_grid()
	check(pulse_run._field_rule.radius_cm==350+50+40 and pulse_run._field_rule.slow_bps==6500 and pulse_run._field_rule.pulse_damage_bps==2500 and pulse_run._field_rule.pulse_every_ticks==30 and pulse_run._field_rule.max_fields==1,"Dominion 1: radius +0.5 m +0.2 m per rime rank, slow 65%, pulse 25% every 30 ticks")
	pulse_run.tick=180;pulse_run._step_fields()
	var before := int(pulse_target.hp_raw)
	pulse_run.tick=209;pulse_run._step_fields();check(pulse_target.hp_raw==before,"No pulse before its time")
	pulse_run.tick=210;pulse_run.events.clear();pulse_run._step_fields()
	var pulse_damage: int=pulse_run.effective_skill(FROST).effects.damage_raw*2500/10000
	var pulse_hit := event_of(pulse_run,"hit")
	check(before-pulse_target.hp_raw==pulse_damage and pulse_hit.get("skill_id","")==FROST and pulse_hit.get("shatter",true)==false,"The pulse deals 25%% of the lance damage as a frost hit, never a shatter (%d)"%(before-pulse_target.hp_raw))
	check(pulse_run.metrics.hits.get(FROST,0)==1 and pulse_run._pending_children.is_empty(),"A pulse is one frost hit and leaves no sparks")
	var many := built_run({"witch.frost.rime":2,"witch.frost.field":2,"witch.frost.dominion":2},12);clear_field(many);tough(many,"walker",Vector2(4,0));many._rebuild_grid()
	for t in [180,181,182]:
		many.tick=t;many._next_field=0;many._step_fields()
	check(many._field_rule.max_fields==2 and many._fields.size()==2 and many._fields[0].uid==2 and many._fields[1].uid==3,"Fields beyond max_fields remove the oldest")
	var wide := built_run({"witch.frost.rime":5,"witch.frost.field":3,"witch.frost.dominion":3},12)
	check(wide._field_rule.radius_cm==600,"A summed field radius over 600 cm is cut to 600")
	# 5. Piercing oath: guardian damage only on the signature skill's hits, never on ordinary enemies.
	var oath := built_run({"witch.frost.needle":2,"witch.frost.volley":2,"witch.frost.oath_lance":1},12)
	var plain_run := tuned_run({},FROST)
	check(oath._elite_bps==1500+300*2,"Oath 1 with needle 2: +15% and +3%p per needle rank")
	var damage_taken: Array=[]
	for r in [plain_run,oath]:
		clear_field(r);var guard := tough(r,"elite",Vector2(6,0));var common := tough(r,"walker",Vector2(0,6))
		var h0: int=guard.hp_raw;var c0: int=common.hp_raw
		r._damage_enemy(guard.id,frost_context(r,10000),0);r._damage_enemy(common.id,frost_context(r,10000),0)
		damage_taken.append(h0-guard.hp_raw);damage_taken.append(c0-common.hp_raw)
	check(damage_taken==[10000,10000,12100,10000],"Guardian takes +21%% from the tree, a walker takes nothing extra (%s)"%str(damage_taken))
	var borrowed := tough(oath,"elite",Vector2(-6,0));var b0: int=borrowed.hp_raw
	var arc_ctx := frost_context(oath,10000);arc_ctx.skill_id="chapter1.skill.arc"
	oath._damage_enemy(borrowed.id,arc_ctx,0)
	check(b0-borrowed.hp_raw==10000,"A hit of another skill gets no guardian bonus")
	# 6. Re-draw (favor): count, same seed -> same new offer, none left -> refused.
	var offers: Array=[]
	for i in 2:
		var r := built_run({"witch.common.favor":2},6)
		r.growth.award_xp(12);r._refresh_mode()
		var first: Dictionary=r.get_offer();var first_ids: Array=[]
		for card in first.cards:first_ids.append(card.id)
		check(r.mode=="choice" and r.rerolls_left()==2 and not r.reroll_offer("stale:token"),"Choice mode with two re-draws; a stale token is refused")
		check(r.reroll_offer(first.token) and r.rerolls_left()==1 and event_of(r,"grace_reroll").get("left",-1)==1,"Re-draw: one used, announced with grace_reroll")
		var second: Dictionary=r.get_offer();var second_ids: Array=[]
		for card in second.cards:second_ids.append(card.id)
		check(second.token!=first.token and not r.choose(first.token,first.cards[0].id) and second.cards.size()==3,"The old token is dead and the new offer has three cards")
		offers.append(second_ids)
		check(r.reroll_offer(second.token) and r.rerolls_left()==0 and not r.reroll_offer(r.get_offer().token),"The second re-draw works, then none is left")
		check(r.mode=="choice" and r.choose(r.get_offer().token,r.get_offer().cards[0].id) and r.mode=="playing","The final offer can still be chosen")
	check(offers[0]==offers[1],"Same seed, same re-drawn offer")
	var none := tuned_run({},FROST);none.growth.award_xp(12);none._refresh_mode()
	check(not none.reroll_offer(none.get_offer().token) and none.rerolls_left()==0,"Without the favor node a re-draw is refused")
	var paused := built_run({"witch.common.favor":1},6);paused.growth.award_xp(12)
	check(not paused.reroll_offer("1:1"),"A re-draw outside the choice mode is refused")
	# 7. Deep oath: rank 2 start, no crystal card, evolution at rank 4 without one.
	var deep_ranks := {"witch.frost.needle":5,"witch.frost.volley":3,"witch.frost.oath_lance":3,"witch.common.vigor":5,"witch.frost.deep_oath":1}
	var deep := built_run(deep_ranks,18)
	check(deep.growth.snapshot().ranks[FROST]==2 and deep.effective_skill(FROST).rank==2,"Deep oath: the lance starts at rank 2")
	var saw_crystal := false;var saw_rank3 := false
	for level_up in 3:
		deep.growth.award_xp(int(deep.tuning.xp_thresholds[level_up+1])-int(deep.growth.snapshot().xp));deep._refresh_mode()
		var offer: Dictionary=deep.get_offer()
		for card in offer.cards:
			if card.kind=="passive" and card.skill_id==FROST:saw_crystal=true
			if card.id=="rank:%s:3"%FROST:saw_rank3=true
		deep.choose(offer.token,offer.cards[0].id)
	check(not saw_crystal and saw_rank3,"Deep oath: the frost crystal card is never offered; the next rank is")
	for r in [deep,tuned_run({},FROST)]:
		r.growth._ranks[FROST]=4;r.growth._evolved.clear();r.growth.award_xp(int(r.tuning.xp_thresholds[6])-int(r.growth.snapshot().xp));r._refresh_mode()
		var evolve_offered := false
		for card in r.get_offer().cards:
			if card.id=="evolve:"+FROST:evolve_offered=true
		check(evolve_offered==(r==deep),"Evolution card at rank 4 without a crystal only with deep oath (%s)"%("deep" if r==deep else "plain"))
	# Options need a fresh run and sane values.
	var fresh_run := Chapter.new();fresh_run.start(3,FROST)
	check(not fresh_run.growth.set_options({"start_rank":3}) and not fresh_run.growth.set_options({"grace_rerolls":4}) and not fresh_run.growth.set_options({"mystery":1}) and fresh_run.growth.snapshot().ranks[FROST]==1 and not fresh_run.growth.snapshot().has("options"),"Bad growth options are refused and change nothing")
	# 8/9. Permanent experience.
	var shares: Array=[]
	for kills in [[30,40,50],[7,9,11]]:
		var r := built_run({},1,{"seal_kills":kills});clear_field(r)
		var gained_before := 0
		for z in 3:
			r.hero.position=Chapter.ZONES[z];r._zone_entered=true
			for i in int(kills[z]):r._emit("death",Chapter.ZONES[z]+Vector2(2,0),{"elite":false})
			check(r.progress_summary().sources.seal[z]==[150,220,280][z],"Zone %d pays exactly its seal share whatever seal_kills is (%s)"%[z,str(kills)])
			r._spawn_wave();var guard_id: int=r._champion_id
			var xp_at_seal: int=r.progress_summary().xp_gained
			r._emit("death",Chapter.ZONES[z]+Vector2(2,0),{"elite":false})
			check(r.progress_summary().xp_gained==xp_at_seal,"A kill after the seal is full pays nothing")
			if z==2:check(r.progress_summary().xp_gained==xp_at_seal and r.mode=="playing","Nothing is paid before the boss falls")
			r._damage_enemy(guard_id,frost_context(r,100000000),0)
		var summary: Dictionary=r.progress_summary()
		shares.append([summary.sources.seal,summary.sources.champion,summary.sources.boss,summary.sources.victory,summary.xp_gained])
		check(r.mode=="victory" and summary.xp_gained==1000 and summary.sources.champion==[50,80] and summary.sources.boss==120 and summary.sources.victory==100,"A won run pays 1000 in total (%s)"%str(summary))
		check(summary.first_kills==["champion:0","champion:1","boss"] and summary.level_before==1 and summary.level_after==4 and summary.character_id==FROST_WITCH,"First kills, levels and witch in the summary")
	check(shares[0]==shares[1],"Different seal thresholds, the same experience")
	var level_events: Array=[]
	var rising_run := Chapter.new();rising_run.set_tuning(tuning_with({"seal_kills":[3,5,7]}))
	var near_level := build_of({},1);near_level.character_xp=240
	check(rising_run.configure_build(near_level) and rising_run.start(17,FROST),"A build just below a level starts")
	for i in 3:
		rising_run._emit("death",Chapter.ZONES[0]+Vector2(2,0),{"elite":false})
		for event in rising_run.events:
			if event.type=="character_level_up":level_events.append(event)
		rising_run.events.clear()
	var ups: Array=[]
	for event in level_events:ups.append(event.level)
	check(ups==[2] and level_events[0].points_total==1 and rising_run.progress_summary().level_before==1 and rising_run.progress_summary().level_after==2,"Crossing a threshold announces character_level_up {level, points_total} once")
	check(rising_run.progress_summary().xp_gained==150,"Three kills of a 150-point seal pay 50 each")
	# 11. A borrowed skill gets no tree block.
	var with_tree := built_run({"witch.frost.needle":5,"witch.frost.volley":3},12)
	var without_tree := tuned_run({},FROST)
	for r in [with_tree,without_tree]:r.growth._ranks[EMBER]=1
	check(with_tree.effective_skill(EMBER).effects==without_tree.effective_skill(EMBER).effects,"The ember skill, borrowed or not, takes no block of the frost tree")
	check(with_tree.effective_skill(FROST).effects!=without_tree.effective_skill(FROST).effects,"The signature skill does")
	# Hero values: health, damage reduction, start potions.
	var tank := built_run({"witch.common.vigor":2,"witch.common.ward":3},6)
	check(tank.hero.max_hp_raw==136*256 and tank.hero.hp_raw==tank.hero.max_hp_raw and tank.potions==4,"Vigor 2 and ward 3: +16 health at full health, 4 potions to start")
	tank.tick=100;var hp_tank: int=tank.hero.hp_raw;tank._hero_damage(10000,Vector2.ZERO)
	check(hp_tank-tank.hero.hp_raw==9100,"Ward 3: 9% off an incoming hit")
	tank.hero.hp_raw=10*256;tank._recompute_gear()
	check(tank.hero.max_hp_raw==136*256 and tank.hero.hp_raw==10*256,"Re-wearing gear keeps the build's health and heals nothing")
	var capped := built_run({"witch.common.vigor":2,"witch.common.ward":3},6,{"potion":{"drop_one_in":90,"seal_drops":2,"start":5,"carry_max":5,"heal_bps":3500,"cooldown_ticks":240}})
	check(capped.potions==5,"Start potions never pass carry_max")
	# R3: shatter radius.
	var shatter_a := built_run({"witch.frost.chill":2,"witch.frost.shatter":2},12)
	var shatter_b := built_run({"witch.frost.chill":2,"witch.frost.shatter":2,"witch.frost.cascade":1},12)
	var reach: Array=[]
	var radii: Array=[]
	for r in [shatter_a,shatter_b]:
		clear_field(r);var source := tough(r,"walker",Vector2(6,0));var neighbour := tough(r,"walker",Vector2(9.8,0))
		source.hp_raw=1;source.frozen_until=r.tick+500;r._rebuild_grid();r.events.clear()
		r._damage_enemy(source.id,frost_context(r,100),0)
		reach.append(neighbour.hp_raw<neighbour.max_hp_raw);radii.append(int(event_of(r,"shatter").get("radius_cm",0)))
	check(reach==[false,true] and radii==[350,400],"Cascade 1 widens the shatter from 3.5 m to 4.0 m (%s %s)"%[str(reach),str(radii)])
	# Determinism: the same build and seed give the same run.
	var twins: Array=[]
	for i in 2:
		var r := built_run({"witch.frost.needle":3,"witch.frost.rime":2,"witch.frost.field":1,"witch.common.vigor":2},12,{},FROST,23)
		var pilot: RefCounted=load("res://chapter1/core/chapter_pilot.gd").new();pilot.run=r
		for t in 1500:r.step(pilot.decide())
		twins.append(hash_without(r,[]))
	check(twins[0]==twins[1],"Same build, same seed: same snapshot hash after 1500 ticks")
	# Required level inside a run: max(permanent level, grace level).
	var gear_gate := built_run({"witch.frost.needle":1},12)
	check(gear_gate.can_equip({"required_level":12}) and not gear_gate.can_equip({"required_level":13}) and not tuned_run({},FROST).can_equip({"required_level":2}),"Wearing needs max(permanent level, grace level); no build keeps the grace level")

## D4-K: abandon() takes the defeat path and leaves the snapshot layout alone.
func abandon_checks() -> void:
	var menu=Chapter.new()
	var keys_menu: Array=menu.snapshot().keys()
	check(not menu.abandon() and menu.mode=="menu","K-3 abandon() from the menu does nothing")
	var live=Chapter.new();live.start(21)
	for i in 50:live.step(Vector2.ZERO)
	var keys_before: Array=live.snapshot().keys()
	var before_events: int=live.events.size()
	check(live.abandon() and live.mode=="defeat","K-1 abandon() in a live run returns true and the mode is defeat")
	var last: Dictionary=live.events[live.events.size()-1]
	check(live.events.size()==before_events+1 and last.type=="defeat" and last.get("abandoned",false)==true,"K-1 the last event is defeat with abandoned")
	check(live.snapshot().keys()==keys_before and keys_before==keys_menu,"K-6 snapshot keys are the same before and after (and as a fresh object)")
	var tick_then: int=live.tick
	for i in 30:live.step(Vector2.ZERO)
	check(live.tick==tick_then and live.mode=="defeat","K-4 no tick passes after abandon()")
	var again_state: String=JSON.stringify(live.snapshot())
	check(not live.abandon() and JSON.stringify(live.snapshot())==again_state,"K-3 abandon() after the end does nothing")
	var paused=Chapter.new();paused.start(22)
	for i in 10:paused.step(Vector2.ZERO)
	paused.set_paused(true)
	check(paused.mode=="paused" and paused.abandon() and paused.mode=="defeat","K-2 abandon() works from a paused run")
	var opened=Chapter.new();opened.start(23)
	for i in 10:opened.step(Vector2.ZERO)
	check(opened.open_inventory() and opened.mode=="inventory" and opened.abandon() and opened.mode=="defeat","K-2 abandon() works with the inventory open and closes it")
	var choosing=Chapter.new();choosing.start(25)
	choosing.growth.award_xp(12);choosing._refresh_mode()
	check(choosing.mode=="choice" and choosing.abandon() and choosing.mode=="defeat","K-2 abandon() works while a level-up choice is pending")
	var won=Chapter.new();won.start(24)
	won._terminal_mode="victory";won._refresh_mode()
	check(won.mode=="victory" and not won.abandon() and won.mode=="victory","K-3 abandon() after a victory does nothing")
	var a=Chapter.new();var b=Chapter.new()
	a.start(21);b.start(21)
	for i in 50:
		a.step(Vector2.ZERO);b.step(Vector2.ZERO)
	a.abandon()
	check(a.start(31) and b.start(31),"K-5 both objects restart")
	for i in 600:
		a.step(Vector2.RIGHT);b.step(Vector2.RIGHT)
	check(JSON.stringify(a.snapshot()).sha256_text()==JSON.stringify(b.snapshot()).sha256_text() and a.tick==600,"K-5 a run started after abandon() matches one started without it (600 ticks)")
## Row value of an id in a block's rows (null when absent).
func row_of(rows: Array,id_: String) -> Variant:
	for r in rows:
		if r.id==id_:return r
	return null

## The sheet must repeat the numbers the core really uses: effective_skill and hero.
func sheet_matches(r: RefCounted,label: String) -> bool:
	var sheet: Dictionary=r.stat_sheet()
	var ok := true
	var primary: Dictionary=r.effective_skill(r._primary_id)
	ok=ok and sheet.primary.id==r._primary_id and row_of(sheet.primary.rows,"damage").raw==int(primary.effects.damage_raw) and row_of(sheet.primary.rows,"interval").raw==int(primary.effects.cooldown_ticks)
	ok=ok and row_of(sheet.primary.rows,"hit_budget").raw==int(primary.effects.hit_budget)
	for key in ["projectiles","chain_targets","branches","pierce","shatter_count","slow_bps"]:
		var row: Variant=row_of(sheet.primary.rows,{"slow_bps":"slow"}.get(key,key))
		ok=ok and (int(primary.effects.get(key,0))==0 if row==null else row.raw==int(primary.effects[key]))
	ok=ok and sheet.secondaries.size()==2
	for block in sheet.secondaries:
		var skill: Dictionary=r.effective_skill(block.id)
		ok=ok and not skill.is_empty() and row_of(block.rows,"damage").raw==int(skill.effects.damage_raw) and row_of(block.rows,"interval").raw==int(skill.effects.cooldown_ticks)
	ok=ok and row_of(sheet.hero.rows,"max_hp").raw==int(r.hero.max_hp_raw) and is_equal_approx(float(row_of(sheet.hero.rows,"speed").value),float(r.hero.speed))
	ok=ok and row_of(sheet.hero.rows,"soul_gain").raw==int(r._gear_stats.get("soul_gain_bps",0)) and row_of(sheet.hero.rows,"pickup_radius").raw==int(r._gear_stats.get("pickup_radius_cm",0))
	ok=ok and row_of(sheet.hero.rows,"damage_reduction").raw==int(r._gear_stats.get("damage_reduction_bps",0))+r._build_reduction_bps
	check(ok,"A1 "+label+": stat_sheet() equals effective_skill and hero")
	return ok

func fingerprint(r: RefCounted) -> String:
	return JSON.stringify([r.equipped,r.hero,r._gear_stats,r.snapshot()])

## D6 A1: stat_sheet, preview_equip, sheet_for. Stats are set by hand so every number is known.
func sheet_checks() -> void:
	var run=Chapter.new();check(run.start(41,FROST),"A1 run starts")
	# The fixture hands the run all three skills at rank 1 so the sheet has two secondaries.
	for id_ in run.SKILL_IDS:
		if not run.growth._ranks.has(id_):run.growth._ranks[id_]=1
	check(run.effective_skill("chapter1.skill.ember").size()>0 and run.effective_skill("chapter1.skill.arc").size()>0,"A1 fixture owns all three skills")
	sheet_matches(run,"empty gear")
	var before_empty: Dictionary=run.stat_sheet()
	check(row_of(before_empty.hero.rows,"max_hp").raw==120*256 and before_empty.sets.is_empty() and before_empty.effects.is_empty(),"A1 empty gear sheet: base health, no sets, no effects")
	var staff_rows: Variant=row_of(before_empty.primary.rows,"damage")
	check(staff_rows.better=="higher" and row_of(before_empty.primary.rows,"interval").better=="lower" and row_of(before_empty.hero.rows,"dash_cooldown").better=="lower","A1 rows carry the player-friendly direction")
	# Hand-made bag: weapon, two rings, one ring needing a high level, a legendary body.
	var mk := func(uid: int,slot_: String,stats: Dictionary,quality: String="magic",req: int=1,desc: String="") -> Dictionary:
		return {"uid":uid,"name":"item%d"%uid,"slot":slot_,"stats":stats,"quality":quality,"item_level":1,"affixes":[],"description":desc,"required_level":req}
	run.inventory.clear();run.equipped.clear();run._recompute_gear()
	run.inventory.append(mk.call(901,"weapon",{"damage_bps":2000,"cooldown_bps":1000,"projectiles":1,"pierce":1}))
	run.inventory.append(mk.call(902,"ring",{"max_hp_raw":2560,"move_speed_bps":500}))
	run.inventory.append(mk.call(903,"ring",{"damage_reduction_bps":400,"dash_cooldown_bps":2000,"soul_gain_bps":300}))
	run.inventory.append(mk.call(904,"ring",{"damage_bps":9000},"rare",99))
	run.inventory.append(mk.call(905,"body",{"max_hp_raw":-1280,"frost_threshold":1},"legendary",1,"Test effect text"))
	run.inventory.append(mk.call(906,"charm",{"pickup_radius_cm":100,"slow_bps":500}))
	var fp_before := fingerprint(run)
	var pv: Dictionary=run.preview_equip(901)
	check(fingerprint(run)==fp_before,"A1 preview_equip leaves equipped, hero, _gear_stats and snapshot byte-identical")
	check(pv.slot=="weapon" and pv.can_equip and not pv.veiled and pv.replaces_uid==0 and pv.sets_before.is_empty() and pv.sets_after.is_empty(),"A1 empty slot preview: slot, can_equip, replaces_uid 0")
	var dmg: Dictionary={}
	for row in pv.rows:
		if row.group=="primary" and row.id=="damage":dmg=row
	check(dmg.change=="better" and dmg.after>dmg.before,"A1 preview marks a damage gain as better")
	var cd: Dictionary={}
	for row in pv.rows:
		if row.group=="primary" and row.id=="interval":cd=row
	check(cd.change=="better" and cd.after<cd.before and cd.delta<0.0,"A1 a shorter interval is better although the number falls")
	# Preview equals a real equip.
	check(run.open_inventory() and run.equip(901),"A1 real equip")
	var after_real: Dictionary=run.stat_sheet()
	check(JSON.stringify(after_real)==JSON.stringify(pv.after),"A1 preview after equals the sheet after a real equip")
	sheet_matches(run,"weapon worn")
	# Rings: each slot previews separately; both preview calls change nothing.
	check(run.equip(902,"ring"),"A1 ring 1 worn")
	var fp_ring := fingerprint(run)
	var p_ring: Dictionary=run.preview_equip(903,"ring")
	var p_ring2: Dictionary=run.preview_equip(903,"ring2")
	var p_auto: Dictionary=run.preview_equip(903)
	check(fingerprint(run)==fp_ring,"A1 ring previews change nothing")
	check(p_ring.slot=="ring" and p_ring.replaces_uid==902 and p_ring2.slot=="ring2" and p_ring2.replaces_uid==0 and p_auto.slot=="ring2","A1 ring previews: ring replaces 902, ring2 is empty, auto picks the free ring2")
	check(row_of(p_ring.after.hero.rows,"max_hp").raw==120*256 and row_of(p_ring2.after.hero.rows,"max_hp").raw==120*256+2560,"A1 the replaced ring loses its health, the free slot keeps it")
	check(p_ring.rows.size()==p_ring2.rows.size() and p_ring2.can_equip and p_ring.can_equip,"A1 both ring previews can be worn")
	var hp_row: Dictionary={}
	for row in p_ring.rows:
		if row.group=="hero" and row.id=="max_hp":hp_row=row
	check(hp_row.change=="worse" and hp_row.delta<0.0,"A1 losing health is worse")
	var dash_row: Dictionary={}
	for row in p_ring2.rows:
		if row.group=="hero" and row.id=="dash_cooldown":dash_row=row
	check(dash_row.change=="better" and dash_row.delta<0.0,"A1 a shorter dash recharge is better")
	check(run.equip(903,"ring2"),"A1 ring 2 worn")
	check(run.preview_equip(902,"ring2").slot=="ring2" and run.preview_equip(902,"ring2").replaces_uid==903,"A1 with both rings worn, a worn ring previews against the other slot")
	sheet_matches(run,"two rings")
	# Wrong slot and level gate.
	var wrong: Dictionary=run.preview_equip(901,"head")
	check(not wrong.slot_ok and not wrong.can_equip and JSON.stringify(wrong.after)==JSON.stringify(wrong.before),"A1 a slot the item cannot go into: not wearable, no change")
	var gated: Dictionary=run.preview_equip(904)
	check(not gated.can_equip and not gated.level_ok and gated.slot_ok and gated.required_level==99 and run.can_equip(run._owned(904))==gated.level_ok,"A1 required-level gate: preview shows numbers, can_equip false, same answer as can_equip")
	check(not run.equip(904,"ring") and not run.equipped.values().has(904),"A1 the gated item really cannot be worn")
	check(run.preview_equip(99999).is_empty(),"A1 unknown uid returns an empty dictionary")
	# Effects: legendary description appears and disappears.
	var p_leg: Dictionary=run.preview_equip(905)
	check(p_leg.effects_gained.size()==1 and p_leg.effects_gained[0].source_uid==905 and p_leg.effects_gained[0].kind=="legendary" and p_leg.effects_gained[0].has("id") and not p_leg.effects_gained[0].has("text") and p_leg.effects_lost.is_empty(),"A1 legendary effect is gained")
	check(run.equip(905) and run.stat_sheet().effects.size()==1,"A1 worn legendary shows in the sheet effects")
	var frost_before: Variant=row_of(before_empty.primary.rows,"freeze_stacks")
	sheet_matches(run,"legendary body")
	var p_off: Dictionary=run.preview_equip(905)
	check(p_off.effects_gained.is_empty() and p_off.slot=="body","A1 re-previewing the worn item gains nothing")
	run.equipped.erase("body");run._recompute_gear()
	check(run.equip(906) and run.equipped.has("charm"),"A1 charm slot can be worn")
	sheet_matches(run,"charm worn")
	check(frost_before==null or frost_before.better=="lower","A1 freeze threshold is a lower-is-better row")
	# sheet_for: off-run, no tick passes; time one call.
	var started := Time.get_ticks_usec()
	var off: Dictionary=Chapter.sheet_for(FROST,{},[] as Array[Dictionary])
	var elapsed_ms := float(Time.get_ticks_usec()-started)/1000.0
	check(not off.has("error") and row_of(off.hero.rows,"max_hp").raw==120*256 and off.primary.id==FROST,"A1 sheet_for without build or gear")
	var timing := 0.0
	for i in 20:
		var t := Time.get_ticks_usec()
		Chapter.sheet_for(FROST,build_of({}),[] as Array[Dictionary])
		timing+=float(Time.get_ticks_usec()-t)/1000.0
	print("SHEET_FOR_MS first=",snappedf(elapsed_ms,.01)," mean_of_20_with_build=",snappedf(timing/20.0,.01))
	check(Chapter.sheet_for("chapter1.skill.ember",build_of({}),[] as Array[Dictionary]).has("error"),"A1 sheet_for refuses a build of another witch")
	var bad: Array[Dictionary]=[{"name":"x"}]
	check(Chapter.sheet_for(FROST,{},bad).has("error"),"A1 sheet_for refuses invalid gear")

## D23 T1-B: the eight gear stat keys and the two totals caps. Each key: 0 changes nothing, > 0 changes the result only while its condition holds.
func t1b_caps() -> Dictionary:
	return {"stat_caps":{"damage_reduction_bps":7500,"condition_damage_bps":10000},"gear_conditions":{"after_dash_ticks":120,"moving_ticks":6,"lowhp_bps":3500}}

## The life one hit of `amount` takes off enemy `id_` (the damage line of _damage_enemy for the primary skill).
func t1b_dealt(r: RefCounted,id_: int,amount: int=1000) -> int:
	var before: int=r.enemies[id_].hp_raw
	r._damage_enemy(id_,context(r,amount),0)
	return before-int(r.enemies[id_].hp_raw)

func t1b_run(extra: Dictionary={},mod: Dictionary={}) -> RefCounted:
	var doc: Dictionary=t1b_caps() if mod.is_empty() else mod
	var r := tuned_run(doc)
	clear_field(r);r._spawn("walker",Vector2(5,0));r._spawn("elite",Vector2(-5,0))
	for id_ in r.enemies:
		r.enemies[id_].hp_raw=10000000;r.enemies[id_].max_hp_raw=10000000
	r.tick=100
	for key in extra:r._gear_stats[key]=extra[key]
	return r

func t1b_checks() -> void:
	var probe := t1b_run()
	var walker: int=probe.enemies.keys()[0];var elite: int=probe.enemies.keys()[1]
	# Zero keys: nothing changes, whatever holds.
	var plain := t1b_run()
	plain.enemies[walker].frozen_until=1000;plain.enemies[walker].mark_until_a=1000;plain._dash_until=50;plain._last_move_tick=99
	check(t1b_dealt(plain,walker)==1000 and t1b_dealt(plain,elite)==1000,"T1-B no condition key: the hit is exactly the skill damage even when every condition holds")
	# vs_elite: strong bodies only (an elite and a D13 elite body count, a walker does not).
	var vs_elite := t1b_run({"vs_elite_bps":2000})
	check(t1b_dealt(vs_elite,walker)==1000 and t1b_dealt(vs_elite,elite)==1200,"T1-B vs_elite_bps: +20% on an elite, nothing on a walker")
	var body := t1b_run({"vs_elite_bps":2000});body.enemies[walker].grade="elite"
	check(t1b_dealt(body,walker)==1200,"T1-B vs_elite_bps counts a D13 elite body (grade elite) although its elite flag is false")
	# vs_frozen
	var vs_frozen := t1b_run({"vs_frozen_bps":5000})
	check(t1b_dealt(vs_frozen,walker)==1000,"T1-B vs_frozen_bps: no change on an enemy that is not frozen")
	vs_frozen.enemies[walker].frozen_until=vs_frozen.tick+30
	var frozen_hit: int=t1b_dealt(vs_frozen,walker)
	check(frozen_hit==1500,"T1-B vs_frozen_bps: +50%% on a frozen enemy (got %d)"%frozen_hit)
	# vs_marked
	var vs_marked := t1b_run({"vs_marked_bps":4000})
	check(t1b_dealt(vs_marked,walker)==1000,"T1-B vs_marked_bps: no change on an unmarked enemy")
	vs_marked.enemies[walker].mark_until_a=vs_marked.tick+30
	check(t1b_dealt(vs_marked,walker)==1400,"T1-B vs_marked_bps: +40% on a marked enemy (a live mark of either owner)")
	vs_marked.tick=vs_marked.tick+31
	check(t1b_dealt(vs_marked,walker)==1000,"T1-B vs_marked_bps: the mark has lapsed")
	# after_dash_bps: from the tick after the dash ends, for after_dash_ticks ticks.
	var after := t1b_run({"after_dash_bps":5000})
	after._dash_until=50
	var in_window: int=t1b_dealt(after,walker)
	after.tick=170;var last_tick: int=t1b_dealt(after,walker)
	after.tick=171;var past: int=t1b_dealt(after,walker)
	after.tick=50;var during: int=t1b_dealt(after,walker)
	check(in_window==1500 and last_tick==1500 and past==1000 and during==1000,"T1-B after_dash_bps: +50% from the tick after the dash for 120 ticks, not during the dash and not after")
	var never_dashed := t1b_run({"after_dash_bps":5000})
	check(t1b_dealt(never_dashed,walker)==1000,"T1-B after_dash_bps: a run that never dashed gets nothing")
	# moving_damage_bps: moved on foot within the last 6 ticks, never while dashing.
	var moving := t1b_run({"moving_damage_bps":3000})
	moving._last_move_tick=95
	check(t1b_dealt(moving,walker)==1300,"T1-B moving_damage_bps: +30% when the hero moved 5 ticks ago")
	moving._last_move_tick=94
	check(t1b_dealt(moving,walker)==1000,"T1-B moving_damage_bps: nothing when the last step was 6 ticks ago")
	moving._last_move_tick=99;moving._dash_until=110
	check(t1b_dealt(moving,walker)==1000,"T1-B moving_damage_bps: nothing while a dash is running")
	# The clock is really kept by step(): a step with input sets it, a step without does not.
	var walking := tuned_run(t1b_caps());clear_field(walking)
	walking.step(Vector2.RIGHT);var moved_at: int=walking._last_move_tick
	walking.step(Vector2.ZERO)
	check(moved_at==walking.tick-1 and walking._last_move_tick==moved_at,"T1-B step() keeps the tick of the last step on foot")
	# Sum, not product; the cap cuts the sum.
	var both := t1b_run({"vs_elite_bps":2000,"vs_frozen_bps":3000});both.enemies[elite].frozen_until=1000
	check(t1b_dealt(both,elite)==1500,"T1-B condition lines add up to one multiplier (20% + 30% = +50%, not 56%)")
	var huge := t1b_run({"vs_elite_bps":6000,"vs_frozen_bps":6000});huge.enemies[elite].frozen_until=1000
	check(t1b_dealt(huge,elite)==2000,"T1-B condition_damage_bps cuts the sum at 10000 (12000 -> +100%)")
	var uncapped := t1b_run({"vs_elite_bps":6000,"vs_frozen_bps":6000},tuning_with({}));uncapped.enemies[elite].frozen_until=1000
	check(t1b_dealt(uncapped,elite)==2200,"T1-B without a stat_caps block there is no cap")
	# lowhp_cooldown_bps: the cooldown shortens at or under lowhp_bps of the maximum life.
	var low := t1b_run({"lowhp_cooldown_bps":5000})
	var base_ticks: int=tuned_run(t1b_caps()).effective_skill("chapter1.skill.ember").effects.cooldown_ticks
	var full_ticks: int=low.effective_skill("chapter1.skill.ember").effects.cooldown_ticks
	low.hero.hp_raw=int(low.hero.max_hp_raw)*3500/10000
	var low_ticks: int=low.effective_skill("chapter1.skill.ember").effects.cooldown_ticks
	low.hero.hp_raw=int(low.hero.max_hp_raw)*3501/10000+1
	var above_ticks: int=low.effective_skill("chapter1.skill.ember").effects.cooldown_ticks
	check(full_ticks==base_ticks and above_ticks==base_ticks and low_ticks==maxi(12,base_ticks*10000/15000) and low_ticks<base_ticks,"T1-B lowhp_cooldown_bps: shorter interval at 35%% life or less, none above (base %d, full %d, low %d)"%[base_ticks,full_ticks,low_ticks])
	var low_zero := t1b_run({});low_zero.hero.hp_raw=1
	check(low_zero.effective_skill("chapter1.skill.ember").effects.cooldown_ticks==base_ticks,"T1-B lowhp_cooldown_bps 0: low life changes nothing")
	# max_hp_bps multiplies base + gear numbers + tree.
	var hp_run := tuned_run(t1b_caps())
	var hp_plain: int=hp_run._hero_body({"max_hp_raw":2560}).max_hp_raw
	var hp_bps: int=hp_run._hero_body({"max_hp_raw":2560,"max_hp_bps":1500}).max_hp_raw
	check(hp_plain==120*256+2560 and hp_bps==hp_plain*11500/10000 and hp_run._hero_body({"max_hp_bps":0}).max_hp_raw==120*256,"T1-B max_hp_bps: (base + max_hp_raw + tree) x (10000 + bps) / 10000, 0 changes nothing")
	# Damage reduction: one function, cut at 7500; the dash guard counts while it lasts.
	var shield := t1b_run({"damage_reduction_bps":9000});var hp_a: int=shield.hero.hp_raw
	shield._hero_damage(10000,Vector2.ZERO)
	check(hp_a-int(shield.hero.hp_raw)==2500,"T1-B damage_reduction_bps 9000 is cut at 7500: a 10000 hit deals 2500")
	var shield_free := t1b_run({"damage_reduction_bps":9000},tuning_with({}));var hp_b: int=shield_free.hero.hp_raw
	shield_free._hero_damage(10000,Vector2.ZERO)
	check(hp_b-int(shield_free.hero.hp_raw)==1000,"T1-B without a stat_caps block the same gear takes 10000 x (1 - 90%) = 1000")
	var guard := t1b_run({"damage_reduction_bps":5000,"after_dash_guard_bps":1000});guard._dash_until=50;var hp_c: int=guard.hero.hp_raw
	guard._hero_damage(10000,Vector2.ZERO)
	check(hp_c-int(guard.hero.hp_raw)==4000,"T1-B after_dash_guard_bps adds to the reduction in the window after a dash (5000 + 1000 -> 4000 taken)")
	var guard_off := t1b_run({"damage_reduction_bps":5000,"after_dash_guard_bps":1000});var hp_d: int=guard_off.hero.hp_raw
	guard_off._hero_damage(10000,Vector2.ZERO)
	check(hp_d-int(guard_off.hero.hp_raw)==5000,"T1-B after_dash_guard_bps: nothing when no dash happened")
	var guard_cap := t1b_run({"damage_reduction_bps":7000,"after_dash_guard_bps":3000});guard_cap._dash_until=50;var hp_e: int=guard_cap.hero.hp_raw
	guard_cap._hero_damage(10000,Vector2.ZERO)
	check(hp_e-int(guard_cap.hero.hp_raw)==2500,"T1-B the guard is inside the cap (7000 + 3000 -> 7500)")
	# The stat sheet shows the cut figure and says so.
	var sheet_run := t1b_run({"damage_reduction_bps":9000})
	var capped_row: Variant=row_of(sheet_run.stat_sheet().hero.rows,"damage_reduction")
	check(capped_row.raw==7500 and capped_row.get("capped",false),"T1-B the stat sheet shows 7500 and capped:true for 9000 of gear")
	var open_run := t1b_run({"damage_reduction_bps":3000})
	var open_row: Variant=row_of(open_run.stat_sheet().hero.rows,"damage_reduction")
	check(open_row.raw==3000 and not open_row.has("capped"),"T1-B under the cap the sheet row has no capped key")
	# Snapshot: the two clocks exist only while gear that reads them is worn.
	check(not t1b_run().snapshot().has("gear_clock") and t1b_run({"after_dash_bps":100}).snapshot().has("gear_clock") and t1b_run({"moving_damage_bps":100}).snapshot().has("gear_clock") and t1b_run({"after_dash_guard_bps":100}).snapshot().has("gear_clock"),"T1-B the snapshot carries gear_clock only with a dash or movement key worn")
	# The document: both blocks are validated, a wrong one refuses the start, no block = the old behaviour.
	var bad_caps=Chapter.new()
	check(not bad_caps.set_tuning(tuning_with({"stat_caps":{"damage_reduction_bps":0,"condition_damage_bps":10000}})) and not bad_caps.set_tuning(tuning_with({"stat_caps":{"damage_reduction_bps":7500}})) and not bad_caps.set_tuning(tuning_with({"gear_conditions":{"after_dash_ticks":120,"moving_ticks":6}})),"T1-B stat_caps and gear_conditions: a zero cap or a missing key is refused")
	var no_block := t1b_run({"after_dash_bps":5000,"moving_damage_bps":3000},tuning_with({}));no_block._dash_until=50;no_block._last_move_tick=99
	check(t1b_dealt(no_block,walker)==1000,"T1-B without gear_conditions the dash and movement lines never hold")

## D23 T5: loot_flow.boss_spray. Guardian and boss loot lies on the floor round the kill and is pulled to the hero 120 / 150 ticks later.
func t5_flow(on: bool) -> Dictionary:
	return {"enabled":false,"keep_min_quality":"rare","gate_sweep_min_quality":"rare","boss_spray":{"enabled":on,"guardian_pull_ticks":120,"boss_pull_ticks":150,"arrive_ticks":30,"ring_min_cm":200,"ring_max_cm":350}}

func t5_run(on: bool,zone_: int,filler: int=0) -> RefCounted:
	var r := tuned_run({"loot_flow":t5_flow(on)})
	clear_field(r)
	r.zone=zone_;r.hero.position=Chapter.ZONES[zone_];r._zone_entered=true;r.zone_kills=r.tuning.seal_kills[zone_];r._spawn_wave()
	for i in filler:r.inventory.append({"uid":9000+i,"slot":"weapon","quality":"common","stats":{},"name":"filler"})
	return r

func t5_kill(r: RefCounted) -> void:
	r.events.clear()
	r._damage_enemy(r._champion_id,context(r,100000000),0)

## Step until the run's tick reaches `target` (stops early when the run left "playing", so a failed check cannot hang).
func t5_to(r: RefCounted,target: int) -> void:
	var guard := 0
	while r.tick<target and guard<1000:
		if r.mode=="choice":
			var offer: Dictionary=r.get_offer()
			r.choose(offer.token,offer.cards[0].id)
		if r.mode!="playing":break
		r.step(Vector2.ZERO);guard+=1

func t5_events(r: RefCounted,type_: String) -> Array:
	var list: Array=[]
	for event in r.events:
		if event.type==type_:list.append(event)
	return list

## The bag's pieces as comparable text (identity of the rolled gear, not of the uid).
func t5_names(list: Array) -> Array:
	var out: Array=[]
	for item in list:out.append(JSON.stringify([item.get("base_id",""),item.get("quality",""),item.get("stats",{}),item.get("affixes",[])]))
	return out

func t5_checks() -> void:
	# Off: straight into the bag, no spray event, no state.
	var off := t5_run(false,0)
	t5_kill(off)
	var kept: Array=t5_names(off.inventory)
	check(kept.size()==3 and off.items.is_empty() and t5_events(off,"loot_spray").is_empty() and not off.snapshot().chapter.has("spray"),"T5 off: guardian loot goes straight into the bag, no loot_spray, no spray state")
	# On, guardian.
	var on := t5_run(true,0)
	t5_kill(on)
	var spray_events := t5_events(on,"loot_spray")
	check(on.inventory.is_empty() and on.items.size()==3 and spray_events.size()==1 and spray_events[0].items.size()==3,"T5 on: nothing goes to the bag, three pieces lie on the floor, one loot_spray lists them")
	var ring_ok := true
	var spray_origin: Vector2=spray_events[0].origin
	for entry in spray_events[0].items:
		var distance := spray_origin.distance_to(entry.to)
		if distance<1.99 or distance>3.51:ring_ok=false
	check(ring_ok,"T5 the landing places lie 2 to 3.5 m from the kill")
	var drops_on := t5_events(on,"item_drop")
	check(drops_on.size()==3 and drops_on[0].get("spray",false) and t5_names(on.items)==kept,"T5 on: the same gear as off was rolled (same draws), item_drop carries spray:true")
	check(spray_events[0].pull_tick==on.tick+120 and spray_events[0].arrive_tick==on.tick+150 and on.snapshot().chapter.has("spray"),"T5 the spray announces its pull (+120) and arrival (+150) ticks; its state is in the snapshot while it waits")
	var kill_tick: int=on.tick
	t5_to(on,kill_tick+119)
	check(on.inventory.is_empty() and on.items.size()==3 and t5_events(on,"loot_pull").is_empty(),"T5 before 120 ticks the loot is still on the floor")
	on.step(Vector2.ZERO)
	var pulls := t5_events(on,"loot_pull")
	check(pulls.size()==1 and pulls[0].items.size()==3 and on.inventory.is_empty(),"T5 at 120 ticks loot_pull starts the pull of the three pieces still on the floor")
	t5_to(on,kill_tick+149)
	on.step(Vector2.ZERO)
	var arrived := t5_events(on,"item_pickup")
	check(on.inventory.size()==3 and on.items.is_empty() and arrived.size()==3 and arrived[0].get("by","")=="spray" and t5_names(on.inventory)==kept and not on.snapshot().chapter.has("spray"),"T5 at 150 ticks the pieces are in the bag (item_pickup by:spray), the same gear as off, the spray state is gone")
	# Walking over a piece first.
	var walk := t5_run(true,0)
	t5_kill(walk)
	var first_uid: int=int(walk.items[0].uid)
	walk.hero.position=walk.items[0].position
	walk.step(Vector2.ZERO)
	check(walk.inventory.size()==1 and int(walk.inventory[0].uid)==first_uid and walk.items.size()==2,"T5 a piece picked up on foot before the pull enters the bag at once")
	var walk_start: int=walk.tick
	t5_to(walk,walk_start+160)
	var walk_uids := {}
	for item in walk.inventory:walk_uids[int(item.uid)]=true
	check(walk.inventory.size()==3 and walk_uids.size()==3 and walk.items.is_empty(),"T5 the pull brings only what is left, nothing twice (bag %d, distinct %d, floor %d, mode %s)"%[walk.inventory.size(),walk_uids.size(),walk.items.size(),walk.mode])
	# A full bag: the same rule as a direct reward (up to four pending, the rest counted).
	var full_off := t5_run(false,0,64)
	t5_kill(full_off)
	var full_on := t5_run(true,0,64)
	t5_kill(full_on)
	var full_start: int=full_on.tick
	t5_to(full_on,full_start+150)
	check(full_on.inventory.size()==full_off.inventory.size() and full_on.pending_rewards.size()==full_off.pending_rewards.size() and int(full_on.metrics.get("overflow_items",0))==int(full_off.metrics.get("overflow_items",0)) and t5_names(full_on.pending_rewards)==t5_names(full_off.pending_rewards),"T5 with a full bag the pull keeps the direct rule: same bag, same pending rewards, same overflow count as off")
	# The final boss: the result waits for the pull.
	var boss_off := t5_run(false,2)
	t5_kill(boss_off)
	var boss_kept: Array=t5_names(boss_off.inventory)
	check(boss_off.mode=="victory" and boss_kept.size()>=5,"T5 off: the final boss ends the run at once with the loot in the bag")
	var boss := t5_run(true,2)
	t5_kill(boss)
	var boss_start: int=boss.tick
	check(boss.mode=="playing" and boss.inventory.is_empty() and boss.items.size()==boss_kept.size() and t5_events(boss,"victory").is_empty(),"T5 on: the final boss's loot lies on the floor and the run goes on")
	t5_to(boss,boss_start+179)
	check(boss.mode=="playing" and boss.inventory.size()==0,"T5 on: 179 ticks after the boss fell the result has not come")
	boss.step(Vector2.ZERO)
	check(boss.mode=="victory" and t5_names(boss.inventory)==boss_kept and boss._elite_reward_uid!=0 and boss.history.size()>0,"T5 on: at 180 ticks (150 pull + 30 arrival) the loot is in the bag, then the result; the same gear as off")
	var bad=Chapter.new()
	var broken := t5_flow(true);broken.boss_spray.ring_max_cm=100
	check(not bad.set_tuning(tuning_with({"loot_flow":broken})),"T5 a ring whose maximum is under its minimum is refused")
	var missing := t5_flow(true);missing.boss_spray.erase("arrive_ticks")
	check(not bad.set_tuning(tuning_with({"loot_flow":missing})),"T5 a boss_spray block without a key is refused")

## D23 T15b: hero_hit carries source_key and attack_id (read from the enemy table, no state).
func t15b_checks() -> void:
	var r := t5_run(false,0)
	var guardian: Dictionary=r.enemies[r._champion_id]
	guardian.attack_kind="circle"
	r.events.clear();r._hero_damage(1000,guardian.position,"champion",int(guardian.id))
	var hit: Dictionary=t5_events(r,"hero_hit")[0]
	check(hit.source_key=="enemy.champion.0.name" and hit.attack_id=="circle" and hit.source_kind=="champion" and hit.source_id==guardian.id,"T15b hero_hit of a seal guardian: source_key is its title key, attack_id its attack")
	r.tick+=100;r._spawn("walker",Vector2(30,0));var walker: Dictionary=r.enemies[r._enemy_sequence];walker.attack_kind="circle"
	r.events.clear();r._hero_damage(1000,walker.position,"walker",int(walker.id))
	hit=t5_events(r,"hero_hit")[0]
	check(hit.source_key=="" and hit.attack_id=="circle","T15b hero_hit of a walker: no text key, attack circle")
	r.tick+=100;r.events.clear();r._hero_damage(1000,Vector2.ZERO,"boss_ward",0)
	hit=t5_events(r,"hero_hit")[0]
	check(hit.source_key=="" and hit.attack_id=="floor_strike","T15b hero_hit of the boss's floor strike: attack floor_strike")
	r.tick+=100;r.events.clear();r._hero_damage(1000,Vector2.ZERO)
	hit=t5_events(r,"hero_hit")[0]
	check(hit.source_key=="" and hit.attack_id=="" and hit.source_kind=="hazard","T15b hero_hit of a plain hazard: both empty")
	r.tick+=100;r.events.clear();r._hero_damage(1000,Vector2.ZERO,"ranged",987654)
	hit=t5_events(r,"hero_hit")[0]
	check(hit.source_key=="" and hit.attack_id=="","T15b hero_hit whose body is already gone: both empty")

## D23 T9: the drop pity in the core. The run gets its own loot tables (the shared ones stay as the data file says: off).
func t9_run(pity_on: bool,dry_runs: int,seed_: int=17) -> RefCounted:
	var r := Chapter.new()
	var tables = load("res://chapter1/core/loot.gd").new()
	check(tables.load_file() and tables.set_pity(pity_on),"T9 run: own loot tables")
	r.loot=tables;r.drop_dry_runs=dry_runs
	check(r.set_tuning(tuning_with({})) and r.start(seed_,EMBER),"T9 run starts")
	clear_field(r)
	r.zone=2;r.hero.position=Chapter.ZONES[2];r._zone_entered=true;r.zone_kills=r.tuning.seal_kills[2];r._spawn_wave()
	return r

func t9_core_checks() -> void:
	# The decision: at the line (5) armed, under it (4) not; off with a big count not.
	check(t9_run(true,5)._pity_armed and not t9_run(true,4)._pity_armed and not t9_run(false,9)._pity_armed and not t9_run(true,0)._pity_armed,"T9 armed at 5 dry runs with the pity on; not at 4; not with the pity off even at 9")
	# Before the boss falls the two runs are the same (only the pity key of the snapshot differs).
	var armed := t9_run(true,5)
	var plain := t9_run(true,4)
	var snap_armed: Dictionary=armed.snapshot()
	var snap_plain: Dictionary=plain.snapshot()
	check(snap_armed.chapter.has("pity") and snap_armed.chapter.pity=={"armed":true,"fired":false} and not snap_plain.chapter.has("pity"),"T9 the snapshot has chapter.pity only in an armed run")
	snap_armed.chapter.erase("pity")
	check(JSON.stringify(snap_armed)==JSON.stringify(snap_plain),"T9 up to the boss's fall an armed run and a not armed run of the same seed are identical")
	# The boss falls.
	t5_kill(armed);t5_kill(plain)
	var names_plain: Array=[]
	for item in plain.inventory:names_plain.append(item.quality)
	var names_armed: Array=[]
	for item in armed.inventory:names_armed.append(item.quality)
	check(armed.inventory.size()==plain.inventory.size() and armed.inventory.size()==6 and names_armed[0]==names_plain[0],"T9 six pieces either way (the first-kill unique, then five), the first-kill unique is the same")
	check(names_armed[1]=="legendary" and armed.inventory[1].has("legendary_id") and true and names_armed[1]=="legendary" and armed.inventory[1].has("legendary_id"),"T9 armed: the first guaranteed line of the boss class is a legendary")
	var pity_events := t5_events(armed,"drop_pity")
	check(pity_events.size()==1 and pity_events[0].uid==armed.inventory[1].uid and pity_events[0].item_id==armed.inventory[1].legendary_id and t5_events(plain,"drop_pity").is_empty(),"T9 armed: one drop_pity {uid, item_id}; not armed: none")
	check(armed.snapshot().chapter.pity=={"armed":true,"fired":true} and not plain.snapshot().chapter.has("pity"),"T9 the snapshot says fired")
	# A guardian is never touched (the zone 0 champion rolls the same with and without the pity).
	var kept_off: Array=[]
	var kept_on: Array=[]
	for armed_state in [false,true]:
		var g := t9_run(true,5 if armed_state else 0)
		clear_field(g)
		g.zone=0;g.hero.position=Chapter.ZONES[0];g._zone_entered=true;g.zone_kills=g.tuning.seal_kills[0];g._spawn_wave()
		t5_kill(g)
		for item in g.inventory:(kept_on if armed_state else kept_off).append(JSON.stringify([item.base_id,item.quality,item.stats]))
	check(kept_on==kept_off and kept_on.size()==3,"T9 a seal guardian's three pieces are the same with the pity armed")

## D23 T17: gear thorns_bps and streak_projectiles. The pieces are called directly where one rule is meant (_hero_damage then
## _resolve_thorns is what step() does in one tick), and through step() where the ordering or the real hit is the point.
func t17_caps(streak: bool=true) -> Dictionary:
	var rule := {"after_dash_ticks":120,"moving_ticks":6,"lowhp_bps":3500}
	if streak:
		rule.streak_kills=20;rule.streak_window_ticks=180
	return {"stat_caps":{"damage_reduction_bps":7500,"condition_damage_bps":10000},"gear_conditions":rule}

## A quiet field: no spawns, the hero's own spells held back (their next cast is far away), gear keys set after the start.
func t17_run(gear: Dictionary,mod: Dictionary={},primary: String=EMBER) -> RefCounted:
	var r := tuned_run(t17_caps() if mod.is_empty() else mod,primary)
	clear_field(r)
	for id_ in r._skill_ids:r._next_cast[id_]=10000000
	for key in gear:r._gear_stats[key]=gear[key]
	r.tick=100
	return r

func t17_thorns(r: RefCounted) -> Array:
	var found: Array=[]
	for event in r.events:
		if event.type=="thorns":found.append(event)
	return found

## One hit on the hero the way a body does it, paid in the same call: returns the life the giver lost.
func t17_hit(r: RefCounted,giver: int,raw: int=10000,kind: String="walker") -> int:
	var before: int=r.enemies[giver].hp_raw if r.enemies.has(giver) else 0
	r._hero_damage(raw,Vector2.ZERO,kind,giver)
	r._resolve_thorns()
	return before-int(r.enemies[giver].hp_raw) if r.enemies.has(giver) else 0

## Deaths of one kind at consecutive ticks (the streak counts death events).
func t17_death(r: RefCounted,skill_id: String="chapter1.skill.ember") -> void:
	r._emit("death",Vector2(5,0),{"target_id":0,"kind":"walker","elite":false,"skill_id":skill_id,"role":"normal"})

func t17_checks() -> void:
	# K1: no thorns gear. A real walker hit changes nothing about the walker and leaves no trace.
	var none := t17_run({})
	var w0: Dictionary=tough(none,"walker",Vector2(.5,0))
	var seen_hit := false;var any_thorns := false
	for i in 400:
		none.step(Vector2.ZERO)
		if event_count(none,"hero_hit")>0:seen_hit=true
		if event_count(none,"thorns")>0:any_thorns=true
		if seen_hit:break
	check(seen_hit and not any_thorns and w0.hp_raw==1000000*256 and not none.metrics.has("thorns") and not none.metrics.has("streak") and not none.snapshot().has("streak"),"T17 K1 no thorns/streak gear: the walker's hit leaves its life, events, metrics and snapshot as they were")
	# K2: through step(): the same tick has hero_hit, thorns and a hit with skill_id gear.thorns; the giver loses exactly the amount.
	var real := t17_run({"thorns_bps":3000})
	var w1: Dictionary=tough(real,"walker",Vector2(.5,0))
	var done := false;var k2_ok := false
	for i in 400:
		real.step(Vector2.ZERO)
		if event_count(real,"hero_hit")>0:
			var hit_event: Dictionary=event_of(real,"hero_hit");var thorn: Dictionary=event_of(real,"thorns")
			var reflected: Dictionary={}
			for event in real.events:
				if event.type=="hit" and event.skill_id=="gear.thorns":reflected=event
			var amount: int=int(hit_event.incoming_raw)*3000/10000
			k2_ok=not thorn.is_empty() and int(thorn.amount_raw)==amount and not reflected.is_empty() and int(reflected.damage_raw)==amount and int(thorn.tick)==int(hit_event.tick) and int(thorn.target_id)==int(w1.id) and w1.hp_raw==1000000*256-amount
			done=true
		if done:break
	check(done and k2_ok,"T17 K2 a walker's real hit: hero_hit, thorns and a gear.thorns hit in one tick, the giver loses 30%% of the hit")
	check(real.metrics.has("thorns") and real.metrics.thorns.hits==1 and real.metrics.thorns.kills==0 and real.metrics.hits.get("gear.thorns",0)==1,"T17 G10 metrics.thorns exists once thorns fired (hits 1, kills 0)")
	# K2 with the plain numbers: raw 10000, 3000 bps -> exactly 3000.
	var plain := t17_run({"thorns_bps":3000});var giver: int=tough(plain,"walker",Vector2(.5,0)).id
	var lost: int=t17_hit(plain,giver)
	var thorn_event: Dictionary=event_of(plain,"thorns")
	var hit_skill := ""
	for event in plain.events:
		if event.type=="hit":hit_skill=String(event.skill_id)
	check(lost==3000 and int(thorn_event.amount_raw)==3000 and hit_skill=="gear.thorns" and thorn_event.source_kind=="walker" and thorn_event.from==plain.hero.position,"T17 K2 raw 10000 at 3000 bps: the giver loses exactly 3000, the event says so")
	var small := t17_run({"thorns_bps":300});var s_giver: int=tough(small,"walker",Vector2(.5,0)).id
	check(t17_hit(small,s_giver,1)==1,"T17 G1 a tiny hit still gives back 1 (max 1)")
	# K3: reduction does not shrink it.
	var reduced := t17_run({"thorns_bps":3000,"damage_reduction_bps":7500});var r_giver: int=tough(reduced,"walker",Vector2(.5,0)).id
	var hp_r: int=reduced.hero.hp_raw
	var lost_r: int=t17_hit(reduced,r_giver)
	check(lost_r==3000 and hp_r-int(reduced.hero.hp_raw)==2500,"T17 K3 reduction 7500: the hero takes 2500, the giver still loses 3000 (the hit before the reduction)")
	# K4: a graze gives back the share of the grazed hit.
	var graze := t17_run({"thorns_bps":3000},tuning_with({"heavy_hit":{"heavy_bps":2000,"gap_ticks":120,"iframe_ticks":45,"graze_bps":5000,"ward_gap_ticks":0}}))
	clear_field(graze);for id_ in graze._skill_ids:graze._next_cast[id_]=10000000
	graze._gear_stats.thorns_bps=3000;graze.tick=100
	var g_giver: int=tough(graze,"walker",Vector2(.5,0)).id
	var first_lost: int=t17_hit(graze,g_giver)
	graze.tick=146;graze.events.clear()
	var second_lost: int=t17_hit(graze,g_giver)
	check(first_lost==3000 and bool(event_of(graze,"hero_hit").get("graze",false)) and second_lost==1500,"T17 K4 a grazed hit (50%% of 10000) gives back 30%% of 5000 = 1500 (first %d, second %d)"%[first_lost,second_lost])
	# K5: no condition multiplier on the way back.
	var cond := t17_run({"thorns_bps":3000,"vs_elite_bps":5000});var elite_giver: int=tough(cond,"elite",Vector2(2,0)).id
	check(t17_hit(cond,elite_giver,10000,"elite")==3000,"T17 K5 vs_elite_bps 5000 worn: an elite's thorns are still exactly 3000 (reflect takes no condition line)")
	check(t1b_dealt(cond,elite_giver,1000)==1500,"T17 K5 the same gear still raises an ordinary hit on the elite by 50%")
	# K6: no one to pay, blocked hit, lethal hit.
	var floor_hit := t17_run({"thorns_bps":3000})
	floor_hit._hero_damage(10000,Vector2.ZERO,"hazard",0);floor_hit._resolve_thorns()
	check(t17_thorns(floor_hit).is_empty() and not floor_hit.metrics.has("thorns"),"T17 K6 source_id 0 (a floor danger) pays nothing")
	var blocked := t17_run({"thorns_bps":3000});var b_giver: int=tough(blocked,"walker",Vector2(.5,0)).id
	t17_hit(blocked,b_giver);blocked.events.clear()
	var hp_b: int=blocked.hero.hp_raw
	blocked._hero_damage(10000,Vector2.ZERO,"walker",b_giver);blocked._resolve_thorns()
	check(hp_b==blocked.hero.hp_raw and t17_thorns(blocked).is_empty() and event_count(blocked,"hero_hit")==0,"T17 K6 a hit blocked by invulnerability pays nothing and makes no event")
	var lethal := t17_run({"thorns_bps":3000});var l_giver: int=tough(lethal,"walker",Vector2(.5,0)).id
	lethal.hero.hp_raw=100
	var hp_g: int=lethal.enemies[l_giver].hp_raw
	lethal._hero_damage(10000,Vector2.ZERO,"walker",l_giver);lethal._resolve_thorns()
	check(lethal.mode=="defeat" and t17_thorns(lethal).is_empty() and lethal.enemies[l_giver].hp_raw==hp_g,"T17 K6 the hit that ends the hero pays nothing")
	# G3: a giver that is gone or dead gets nothing; a giver from an older run (generation) gets nothing.
	var gone := t17_run({"thorns_bps":3000});var gone_id: int=tough(gone,"walker",Vector2(.5,0)).id
	gone.enemies[gone_id].hp_raw=0;gone.enemies[gone_id].state="dead"
	gone._hero_damage(10000,Vector2.ZERO,"walker",gone_id);gone._resolve_thorns()
	check(t17_thorns(gone).is_empty(),"T17 G3 a dead giver is not paid")
	var old_gen := t17_run({"thorns_bps":3000});var old_id: int=tough(old_gen,"walker",Vector2(.5,0)).id
	old_gen.enemies[old_id].generation=old_gen._epoch-1
	old_gen._hero_damage(10000,Vector2.ZERO,"walker",old_id);old_gen._resolve_thorns()
	check(t17_thorns(old_gen).is_empty(),"T17 G3 a body of an older run is not paid")
	# G5: step() drops what was written but not paid (a hit made outside step) so nothing leaks into the next tick.
	var leak := t17_run({"thorns_bps":3000});var leak_id: int=tough(leak,"walker",Vector2(20,0)).id
	leak._hero_damage(10000,Vector2.ZERO,"walker",leak_id)
	leak.step(Vector2.ZERO)
	check(t17_thorns(leak).is_empty() and leak._thorns_pending.is_empty(),"T17 G5 step() starts with no owed thorns")
	# K7: an enemy shot pays at any distance; a shooter that died first pays nothing.
	var shot := t17_run({"thorns_bps":3000});var shooter: int=tough(shot,"ranged",Vector2(28,0)).id
	shot._projectile_sequence+=1
	shot.projectiles.append({"uid":shot._projectile_sequence,"position":shot.hero.position,"previous":shot.hero.position,"direction":Vector2.RIGHT,"speed":0.0,"radius":.16,"skill_id":"hostile.ranged","hostile":true,"damage_raw":10000,"expires":shot.tick+100,"cast_id":0,"pierce_left":0,"hit_ids":[]})
	shot._hostile_src[shot._projectile_sequence]={"id":shooter,"kind":"ranged"}
	var shooter_before: int=shot.enemies[shooter].hp_raw
	shot.step(Vector2.ZERO)
	var shot_thorns := t17_thorns(shot)
	check(shot_thorns.size()==1 and int(shot_thorns[0].amount_raw)==3000 and shooter_before-int(shot.enemies[shooter].hp_raw)==3000 and shot.enemies[shooter].position.distance_to(shot.hero.position)>15.0,"T17 K7 an enemy shot pays the shooter 3000 from 15+ m away (far outside the 1.15 m body reach)")
	var dead_shot := t17_run({"thorns_bps":3000});var dead_shooter: int=tough(dead_shot,"ranged",Vector2(28,0)).id
	dead_shot._projectile_sequence+=1
	dead_shot.projectiles.append({"uid":dead_shot._projectile_sequence,"position":dead_shot.hero.position,"previous":dead_shot.hero.position,"direction":Vector2.RIGHT,"speed":0.0,"radius":.16,"skill_id":"hostile.ranged","hostile":true,"damage_raw":10000,"expires":dead_shot.tick+100,"cast_id":0,"pierce_left":0,"hit_ids":[]})
	dead_shot._hostile_src[dead_shot._projectile_sequence]={"id":dead_shooter,"kind":"ranged"}
	dead_shot.enemies[dead_shooter].hp_raw=0;dead_shot.enemies[dead_shooter].state="dead"
	dead_shot.step(Vector2.ZERO)
	check(event_count(dead_shot,"hero_hit")==1 and t17_thorns(dead_shot).is_empty(),"T17 K7 a shooter that died before its shot landed pays nothing (the hit still lands)")
	# K8: a kill by thorns is the witch's kill.
	var kill := t17_run({"thorns_bps":3000});var victim_ok: bool=kill._spawn("walker",Vector2(.5,0))
	var victim_id: int=kill._enemy_sequence
	kill.enemies[victim_id].hp_raw=100;kill._zone_entered=true;kill.orbs.clear()
	var kills_before: int=kill.kills;var zone_before: int=kill.zone_kills
	t17_hit(kill,victim_id)
	var death: Dictionary=event_of(kill,"death")
	check(victim_ok and death.get("skill_id","")=="gear.thorns" and kill.kills==kills_before+1 and kill.zone_kills==zone_before+1 and kill.orbs.size()==1 and kill.metrics.thorns.kills==1,"T17 K8 a kill by thorns: death skill_id gear.thorns, kills +1, seal kill +1, one experience orb")
	# K9: the last life of the final boss, taken by thorns in a real step, closes the run in that tick.
	var boss := t17_run({"thorns_bps":3000})
	boss.hero.position=Chapter.ZONES[2];boss._zone_entered=true;boss.zone=2;boss.zone_kills=boss.tuning.seal_kills[2]
	boss._spawn_wave()
	var boss_id: int=boss._champion_id
	boss.events.clear()
	boss.enemies[boss_id].hp_raw=100;boss.enemies[boss_id].position=boss.hero.position+Vector2(30,0)
	boss._projectile_sequence+=1
	boss.projectiles.append({"uid":boss._projectile_sequence,"position":boss.hero.position,"previous":boss.hero.position,"direction":Vector2.RIGHT,"speed":0.0,"radius":.16,"skill_id":"hostile.ranged","hostile":true,"damage_raw":10000,"expires":boss.tick+100,"cast_id":0,"pierce_left":0,"hit_ids":[]})
	boss._hostile_src[boss._projectile_sequence]={"id":boss_id,"kind":"boss"}
	for id_ in boss._skill_ids:boss._next_cast[id_]=10000000
	boss.step(Vector2.ZERO)
	check(boss_id>0 and boss.mode=="victory" and event_count(boss,"victory")==1 and event_of(boss,"death").get("skill_id","")=="gear.thorns","T17 K9 thorns took the boss's last life: victory in the same tick")
	# K10: no streak gear: 30 kills arm nothing and the snapshot has no streak key.
	var idle := t17_run({})
	for i in 30:idle.tick+=1;t17_death(idle)
	check(event_count(idle,"streak_ready")==0 and not idle.snapshot().has("streak") and not idle.metrics.has("streak"),"T17 K10 without streak gear 30 kills arm nothing, no snapshot key")
	# K11: window 180 ticks, threshold 20.
	var late := t17_run({"streak_projectiles":2})
	for i in 19:late.tick=100+i*9;t17_death(late)
	late.tick=100+179;late.events.clear()
	check(event_count(late,"streak_ready")==0 and late._streak_charge==0 and late.snapshot().streak.kills.size()==19,"T17 K11 19 kills in the window: not armed")
	t17_death(late)
	var ready: Dictionary=event_of(late,"streak_ready")
	check(int(ready.get("charge",0))==2 and int(ready.get("kills",0))==20 and late._streak_charge==2 and late.snapshot().streak.kills.is_empty() and late.snapshot().streak.charge==2,"T17 K11 the 20th kill within 179 ticks arms it: streak_ready{charge 2, kills 20}")
	check(late.metrics.streak.armed==1 and late.metrics.streak.casts==0,"T17 S8 metrics.streak appears when first armed")
	late.events.clear();late.tick+=1
	for i in 25:t17_death(late)
	check(event_count(late,"streak_ready")==0 and late.snapshot().streak.kills.is_empty(),"T17 S4 while armed nothing is counted")
	var old := t17_run({"streak_projectiles":2})
	for i in 19:old.tick=100+i*9;t17_death(old)
	old.tick=100+180;old.events.clear();t17_death(old)
	check(event_count(old,"streak_ready")==0 and old.snapshot().streak.kills.size()==19,"T17 K11 a kill 180 ticks old has left the window (19 left, not armed)")
	# K13: a descent's kill is not counted, thorns' kill is.
	var cnt := t17_run({"streak_projectiles":2})
	for i in 25:cnt.tick+=1;t17_death(cnt,"descent.frost")
	var after_descent: int=cnt.snapshot().streak.kills.size()
	for i in 20:cnt.tick+=1;t17_death(cnt,"gear.thorns")
	check(after_descent==0 and event_count(cnt,"streak_ready")==1,"T17 K13 descent.* kills are not counted, gear.thorns kills are")
	# K12: the next primary cast only. frost / ember: projectiles +2; the cast event says streak 2; the one after is as before.
	for primary in [FROST,EMBER]:
		var base := t17_run({"streak_projectiles":2},{},primary);var armed := t17_run({"streak_projectiles":2},{},primary)
		for pair in [base,armed]:
			tough(pair,"walker",Vector2(4,0));pair._rebuild_grid();pair._next_cast[primary]=0
		armed._streak_charge=2
		base.step(Vector2.ZERO);armed.step(Vector2.ZERO)
		var base_cast: Dictionary={};var armed_cast: Dictionary={}
		for event in base.events:
			if event.type=="cast" and event.skill_id==primary:base_cast=event
		for event in armed.events:
			if event.type=="cast" and event.skill_id==primary:armed_cast=event
		check(not base_cast.is_empty() and not armed_cast.is_empty() and int(armed_cast.effects.projectiles)==int(base_cast.effects.projectiles)+2 and int(armed_cast.get("streak",0))==2 and not base_cast.has("streak") and armed._streak_charge==0,"T17 K12 %s: the armed cast has +2 projectiles and streak 2, the unarmed one is the plain cast"%primary)
		armed._next_cast[primary]=0;armed.events.clear();armed.step(Vector2.ZERO)
		var again: Dictionary=event_of(armed,"cast")
		check(not again.is_empty() and int(again.effects.projectiles)==int(base_cast.effects.projectiles) and not again.has("streak") and armed.metrics.streak.casts==1 and armed.metrics.streak.extra==2,"T17 K12 %s: the cast after it is the plain one again; metrics.streak counts one cast, 2 extra"%primary)
	var arc_base := t17_run({"streak_projectiles":2},{},"chapter1.skill.arc");var arc_run := t17_run({"streak_projectiles":2},{},"chapter1.skill.arc")
	for pair in [arc_base,arc_run]:
		for i in 6:tough(pair,"walker",Vector2(3+i,0))
		pair._rebuild_grid();pair._next_cast["chapter1.skill.arc"]=0
	arc_run._streak_charge=2
	arc_base.step(Vector2.ZERO);arc_run.step(Vector2.ZERO)
	var arc_plain: Dictionary=event_of(arc_base,"cast");var arc_streak: Dictionary=event_of(arc_run,"cast")
	check(int(arc_streak.effects.chain_targets)==int(arc_plain.effects.chain_targets)+2 and int(arc_streak.get("streak",0))==2,"T17 K12 arc: chain_targets +2 (%d vs %d) and streak 2"%[int(arc_streak.effects.chain_targets),int(arc_plain.effects.chain_targets)])
	# K12: a secondary spell of the same tick does not get it.
	var duo := tuned_run_owning(t17_caps(),"chapter1.skill.arc");clear_field(duo)
	duo._gear_stats.streak_projectiles=2;duo.tick=100
	for i in 4:tough(duo,"walker",Vector2(3+i,0))
	duo._rebuild_grid();for id_ in duo._skill_ids:duo._next_cast[id_]=0
	duo._streak_charge=2
	var duo_twin := tuned_run_owning(t17_caps(),"chapter1.skill.arc");clear_field(duo_twin)
	duo_twin._gear_stats.streak_projectiles=2;duo_twin.tick=100
	for i in 4:tough(duo_twin,"walker",Vector2(3+i,0))
	duo_twin._rebuild_grid();for id_ in duo_twin._skill_ids:duo_twin._next_cast[id_]=0
	duo.step(Vector2.ZERO);duo_twin.step(Vector2.ZERO)
	var duo_arc: Dictionary={};var twin_arc: Dictionary={}
	for event in duo.events:
		if event.type=="cast" and event.skill_id=="chapter1.skill.arc":duo_arc=event
	for event in duo_twin.events:
		if event.type=="cast" and event.skill_id=="chapter1.skill.arc":twin_arc=event
	check(not duo_arc.is_empty() and not twin_arc.is_empty() and not duo_arc.has("streak") and int(duo_arc.effects.chain_targets)==int(twin_arc.effects.chain_targets),"T17 K12 the secondary spell cast in the same tick is not boosted")
	# Not cast = not spent: with no enemy in reach the charge stays.
	var hold := t17_run({"streak_projectiles":2});hold._streak_charge=2;hold._next_cast[EMBER]=0
	hold.step(Vector2.ZERO)
	check(hold._streak_charge==2 and event_count(hold,"cast")==0,"T17 S5 no target, no cast: the charge is kept")
	# K14: the 16 cap.
	var cap16 := t17_run({"streak_projectiles":4,"projectiles":15},{},FROST);tough(cap16,"walker",Vector2(4,0));cap16._rebuild_grid();cap16._next_cast[FROST]=0;cap16._streak_charge=4
	cap16.step(Vector2.ZERO)
	check(int(event_of(cap16,"cast").effects.projectiles)==16,"T17 K14 projectiles stay at 16 (15 gear + 4 streak)")
	# S6: the reading functions do not include the charge.
	var read := t17_run({"streak_projectiles":2},{},FROST);var plain_projectiles: int=read.effective_skill(FROST).effects.projectiles
	read._streak_charge=2
	check(read.effective_skill(FROST).effects.projectiles==plain_projectiles,"T17 S6 effective_skill does not include the streak charge")
	# S4: the charge is kept when the gear comes off; a core start clears it.
	read._gear_stats.erase("streak_projectiles")
	check(read._streak_charge==2 and read.snapshot().has("streak"),"T17 S4 an armed charge survives taking the gear off (and shows in the snapshot)")
	read.start(17,EMBER)
	check(read._streak_charge==0 and read._streak_kills.is_empty() and read._thorns_pending.is_empty() and not read.snapshot().has("streak"),"T17 start() clears the streak and the owed thorns")
	# K15: the document.
	var doc_run := Chapter.new()
	var half := t17_caps(false);half.gear_conditions.streak_kills=20
	var half_window := t17_caps(false);half_window.gear_conditions.streak_window_ticks=180
	check(not doc_run.set_tuning(tuning_with(half)) and not doc_run.set_tuning(tuning_with(half_window)),"T17 K15 gear_conditions with only one of streak_kills / streak_window_ticks is refused")
	var zero_kills := t17_caps();zero_kills.gear_conditions.streak_kills=0
	var long_window := t17_caps();long_window.gear_conditions.streak_window_ticks=3601
	var stray := t17_caps();stray.gear_conditions.streak_extra=1
	check(not doc_run.set_tuning(tuning_with(zero_kills)) and not doc_run.set_tuning(tuning_with(long_window)) and not doc_run.set_tuning(tuning_with(stray)),"T17 K15 streak_kills 0, window 3601 and an unknown extra key are refused")
	check(doc_run.set_tuning(tuning_with(t17_caps(false))) and doc_run.set_tuning(tuning_with(t17_caps())),"T17 K15 neither key and both keys are accepted")
	var absent := t17_run({"streak_projectiles":2},tuning_with(t17_caps(false)))
	for i in 30:absent.tick+=1;t17_death(absent)
	check(event_count(absent,"streak_ready")==0 and absent._streak_charge==0,"T17 K15 without the two keys nothing arms")
	var shipped := Chapter.new()
	check(shipped.start(5) and int(shipped.tuning.gear_conditions.streak_kills)==20 and int(shipped.tuning.gear_conditions.streak_window_ticks)==180,"T17 the shipped combat_tuning.json carries streak_kills 20 and streak_window_ticks 180")

## D23 T17 "no empty golden": the golden case gear-t17 (seed 11, frost, kit.golden.t17, the QA pilot) must really show thorns, streak_ready and a
## cast with streak. The run stops when all three were seen and at least 3000 ticks passed (or at the end of the run); the tick is written in the message.
func t17_golden_checks() -> void:
	var TrialDocs := preload("res://chapter1/tests/support/trial_docs.gd")
	var Pilot := preload("res://chapter1/core/chapter_pilot.gd")
	var run := Chapter.new();var pilot: RefCounted=Pilot.new();pilot.run=run
	check(run.start(11,FROST),"T17 golden fixture: the run starts")
	var problem: String=TrialDocs.wear_fixture_kit_problem(run,"kit.golden.t17")
	check(problem.is_empty(),"T17 golden fixture: the kit is worn through import_starting_gear ("+problem+")")
	var thorns := 0;var ready := 0;var streak_casts := 0;var first := {}
	var stats_ok: bool=int(run._gear_stats.get("thorns_bps",0))==3000 and int(run._gear_stats.get("streak_projectiles",0))==2
	check(stats_ok,"T17 golden fixture: the worn gear reads thorns_bps 3000 and streak_projectiles 2 (%s)"%str([run._gear_stats.get("thorns_bps",0),run._gear_stats.get("streak_projectiles",0)]))
	while run.mode not in ["victory","defeat"] and run.tick<12*60*60:
		run.step(pilot.decide())
		for event in run.events:
			if event.type=="thorns":thorns+=1;first["thorns"]=first.get("thorns",run.tick)
			elif event.type=="streak_ready":ready+=1;first["streak_ready"]=first.get("streak_ready",run.tick)
			elif event.type=="cast" and event.has("streak"):streak_casts+=1;first["cast_streak"]=first.get("cast_streak",run.tick)
		if thorns>0 and ready>0 and streak_casts>0 and run.tick>=3000:break
	var worn_uids: Array=[]
	for slot in ["body","feet"]:worn_uids.append(int(run.equipped.get(slot,-1)))
	var worn_kit := true
	for uid in worn_uids:
		var item: Dictionary=run._owned(uid)
		worn_kit=worn_kit and not item.is_empty() and (int(item.stats.get("thorns_bps",0))>0 or int(item.stats.get("streak_projectiles",0))>0)
	check(thorns>0 and ready>0 and streak_casts>0,"T17 golden fixture: the pilot's run shows thorns (%d), streak_ready (%d) and a cast with streak (%d) by tick %d; first seen %s"%[thorns,ready,streak_casts,run.tick,str(first)])
	check(worn_kit,"T17 golden fixture: the pilot still wears the thorns body and the streak boots at tick %d"%run.tick)
	print("T17_GOLDEN_FIXTURE ",JSON.stringify({"tick":run.tick,"mode":run.mode,"thorns":thorns,"streak_ready":ready,"streak_casts":streak_casts,"first":first,"worn_kit":worn_kit}))

## D23 T8 helpers. The shipped tuning (the shrines' luck buff and the grace block live there), the grace grades switched in memory only.
func t8_tuning(grace: bool,grades: bool) -> Dictionary:
	var doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://chapter1/data/combat_tuning.json"))
	if grace:doc.grace.enabled=true
	if grades:doc.grace.grades.enabled=true
	return doc

## A started run (tick 0, nothing worn yet) with its own loot tables, the luck switch as asked. The field is quiet.
func t8_run(luck_on: bool,grace: bool=false,grades: bool=false,seed_: int=11) -> RefCounted:
	var r := Chapter.new()
	var tables = load("res://chapter1/core/loot.gd").new()
	check(tables.load_file() and tables.set_luck(luck_on),"T8 run: own loot tables, luck "+str(luck_on))
	r.loot=tables
	check(r.set_tuning(t8_tuning(grace,grades)) and r.start(seed_,FROST),"T8 run starts ("+str(r.errors)+")")
	clear_field(r)
	for id_ in r._skill_ids:r._next_cast[id_]=10000000
	return r

## Items by spec ({"equip","slot","quality","base","item_level","affixes"}) through import_starting_gear, the town-to-run path.
func t8_wear(r: RefCounted,specs: Array) -> bool:
	var GearKits := preload("res://chapter1/tests/support/gear_kits.gd")
	var gear: Array[Dictionary]=[]
	for i in specs.size():
		var built: Dictionary=GearKits.build_item(r.loot,specs[i])
		check(not built.has("error"),"T8 fixture item built "+str(built.get("error","")))
		var item: Dictionary=built.item.duplicate(true)
		item["uid"]=9000+i;item["storage_id"]=9000+i;item["equip_slot"]=String(specs[i].equip)
		gear.append(item)
	return r.import_starting_gear(gear)

func t8_spec(equip: String,slot: String,base: String,affixes: Array) -> Dictionary:
	return {"equip":equip,"slot":slot,"quality":"rare","base":base,"item_level":16,"affixes":affixes}

func t8_two_luck(r: RefCounted) -> bool:
	return t8_wear(r,[t8_spec("head","head","iron_circlet",[["luck_5",1800],["haste5",3800],["vigor5",28000]]),t8_spec("ring","ring","quick_loop",[["wrath5",5700],["luck_5",1800],["vigor5",28000]])])

func t8_events(r: RefCounted,type_: String) -> Array:
	var found: Array=[]
	for event in r.events:
		if event.type==type_:found.append(event)
	return found

func t8_checks() -> void:
	# R1: no luck gear: nothing is taken, nothing is said, no key anywhere.
	var none := t8_run(true)
	check(none.luck_state().run_bps==0 and not none.luck_state().locked and none.luck_state().enabled and none.luck_state().cap_bps==3000,"T8 R1 before the first step: luck_state is run_bps 0, not locked, enabled, cap 3000")
	none.step(Vector2.ZERO)
	check(none.luck_state().run_bps==0 and none.luck_state().locked and t8_events(none,"luck_locked").is_empty() and not none.metrics.has("luck") and not none.snapshot().chapter.has("luck"),"T8 R1 no luck gear: run_bps 0, locked after the first step, no luck_locked, no metrics.luck, no chapter.luck")
	# R2: two lines of 1800: 3600 worn, 3000 taken at the first step, announced once, not before.
	var two := t8_run(true)
	check(t8_two_luck(two),"T8 R2 the two luck items are worn through import_starting_gear")
	var before: Dictionary=two.luck_state()
	check(before.run_bps==0 and not before.locked and before.worn_bps==3600,"T8 R2 right after start and the import (no step yet): locked false, run_bps 0, worn_bps 3600")
	two.step(Vector2.ZERO)
	var locked_events := t8_events(two,"luck_locked")
	check(two.luck_state().run_bps==3000 and two.luck_state().locked and two.luck_state().worn_bps==3600,"T8 R2 after the first step run_bps is 3000 (worn 3600)")
	check(locked_events.size()==1 and locked_events[0].luck_bps==3000 and locked_events[0].worn_bps==3600 and locked_events[0].capped==true,"T8 R2 luck_locked once with luck_bps 3000, worn_bps 3600, capped true")
	check(two.metrics.has("luck") and two.metrics.luck.rolls==0 and two.snapshot().chapter.luck.run_bps==3000,"T8 R2 metrics.luck exists (rolls 0) and the snapshot says run_bps 3000")
	two.step(Vector2.ZERO)
	check(t8_events(two,"luck_locked").is_empty(),"T8 R2 luck_locked is not said again on the next tick")
	# A luck below the cap is taken as it is, capped false.
	var one := t8_run(true)
	check(t8_wear(one,[t8_spec("head","head","iron_circlet",[["luck_5",1500],["haste5",3800],["vigor5",28000]])]),"T8 R2 one luck item worn")
	one.step(Vector2.ZERO)
	var one_event := t8_events(one,"luck_locked")
	check(one.luck_state().run_bps==1500 and one_event.size()==1 and one_event[0].capped==false,"T8 R2 luck 1500 is taken as 1500, capped false")
	# R3: taking a luck piece off and putting it back during the run changes worn_bps, never run_bps.
	var mid := t8_run(true)
	check(t8_two_luck(mid),"T8 R3 worn")
	mid.step(Vector2.ZERO)
	check(mid.open_inventory() and mid.unequip("head") and mid.luck_state().worn_bps==1800 and mid.luck_state().run_bps==3000,"T8 R3 head taken off: worn_bps 1800, run_bps still 3000")
	check(mid.unequip("ring") and mid.luck_state().worn_bps==0 and mid.luck_state().run_bps==3000,"T8 R3 ring taken off: worn_bps 0, run_bps still 3000")
	var head_uid := -1
	for item in mid.inventory:
		if item.slot=="head":head_uid=int(item.uid)
	# (equip() would refuse the level-16 item at run level 1, so the worn map is set the way import_starting_gear does.)
	if head_uid>0:mid.equipped["head"]=head_uid;mid._recompute_gear()
	check(head_uid>0 and mid.luck_state().worn_bps==1800 and mid.luck_state().run_bps==3000,"T8 R3 put back on during the run: worn_bps 1800 again, run_bps still 3000")
	mid.close_inventory();mid.step(Vector2.ZERO)
	check(mid.luck_state().run_bps==3000 and t8_events(mid,"luck_locked").is_empty() and mid.snapshot().chapter.luck.run_bps==3000,"T8 R3 stepping on keeps run_bps and says nothing new")
	# R4: the luck switch off: gear or not, nothing is taken.
	var off := t8_run(false)
	check(t8_two_luck(off),"T8 R4 worn with the luck off")
	off.step(Vector2.ZERO)
	check(off.luck_state().run_bps==0 and not off.luck_state().enabled and off.luck_state().worn_bps==3600 and t8_events(off,"luck_locked").is_empty() and not off.metrics.has("luck") and not off.snapshot().chapter.has("luck"),"T8 R4 luck off: run_bps 0 although 3600 is worn, no event, no metrics.luck, no chapter.luck")
	var flipped := t8_run(true)
	check(flipped.loot.set_luck(false) and t8_two_luck(flipped),"T8 R4 set_luck(false) after the run was built")
	flipped.step(Vector2.ZERO)
	check(flipped.luck_state().run_bps==0,"T8 R4 set_luck(false): run_bps 0")
	# R5: _drop_mods. Shrine of luck on: its two keys plus luck_bps; off: only luck_bps; the guard/boss/chest call (false) never takes the shrine.
	var mods := t8_run(true)
	check(t8_two_luck(mods),"T8 R5 worn")
	mods.step(Vector2.ZERO)
	check(JSON.stringify(mods._drop_mods(true))==JSON.stringify({"luck_bps":3000}) and JSON.stringify(mods._drop_mods(false))==JSON.stringify({"luck_bps":3000}),"T8 R5 no shrine: _drop_mods(true) and (false) are {luck_bps: 3000}")
	mods._buffs.append({"kind":"luck","until_tick":mods.tick+1800})
	var shrine_mods: Dictionary=mods._drop_mods(true)
	var plain_shrine: Dictionary=mods._luck_mods()
	check(shrine_mods.has("drop_bps") and shrine_mods.has("quality_bps") and shrine_mods.luck_bps==3000 and int(shrine_mods.drop_bps)==int(plain_shrine.drop_bps) and JSON.stringify(shrine_mods.quality_bps)==JSON.stringify(plain_shrine.quality_bps) and shrine_mods.size()==3,"T8 R5 shrine on: _drop_mods(true) is the shrine's drop_bps and quality_bps plus luck_bps")
	check(JSON.stringify(mods._drop_mods(false))==JSON.stringify({"luck_bps":3000}),"T8 R5 shrine on: _drop_mods(false) is still only {luck_bps: 3000}")
	var bare := t8_run(true)
	bare.step(Vector2.ZERO)
	check(bare._drop_mods(true).is_empty() and bare._drop_mods(false).is_empty(),"T8 R5 no luck gear, no shrine: both are {} (the plain draw)")
	bare._buffs.append({"kind":"luck","until_tick":bare.tick+1800})
	check(JSON.stringify(bare._drop_mods(true))==JSON.stringify(bare._luck_mods()) and bare._drop_mods(false).is_empty(),"T8 R5 no luck gear, shrine on: _drop_mods(true) is the shrine's mods exactly, (false) is {}")
	# The rolls are counted where luck goes in (ordinary kill, elite, chest/guard/boss), not in the first-kill unique.
	var counted := t8_run(true)
	check(t8_two_luck(counted),"T8 R5 worn for the roll count")
	counted.step(Vector2.ZERO)
	var rolls_before: int=counted.metrics.luck.rolls
	counted._maybe_drop_item({"elite":false,"position":Vector2.ZERO,"kind":"walker","role":"normal"})
	check(int(counted.metrics.luck.rolls)==rolls_before+1,"T8 R5 an ordinary kill's drop counts one luck roll")
	# R6: grace on but the grades off: the grace luck of the gear is a dead line and says no error.
	var dead := t8_run(true,true,false)
	check(not dead.growth.grades_on() and t8_wear(dead,[t8_spec("head","head","iron_circlet",[["luck_5",1800],["grace_luck_4",2500],["haste5",3800],["vigor5",28000]])]),"T8 R6 grades off, grace_luck_4 on the head")
	check(int(dead._gear_totals(dead.equipped).get("grace_luck_bps",0))==2500,"T8 R6 the head really carries grace_luck_bps 2500")
	dead.step(Vector2.ZERO)
	check(int(dead.growth.snapshot().grace.luck.gear_bps)==0 and dead.errors.is_empty() and dead.growth.errors.is_empty(),"T8 R6 grades off: gear_bps is 0 and there is no error")
	var no_grace := t8_run(true)
	check(t8_wear(no_grace,[t8_spec("head","head","iron_circlet",[["luck_5",1800],["grace_luck_4",2500],["haste5",3800],["vigor5",28000]])]),"T8 R6 grace off too: worn")
	no_grace.step(Vector2.ZERO)
	check(no_grace.errors.is_empty() and not no_grace.snapshot().has("grace_gap") and no_grace.luck_state().run_bps==1800,"T8 R6 grace off: no error and the luck is taken normally")
	# R7: grades on: the gear's share is taken at the same first step, survives taking the head off and the shrine's start and end.
	var graded := t8_run(true,true,true)
	check(graded.growth.grades_on() and t8_wear(graded,[t8_spec("head","head","iron_circlet",[["luck_5",1800],["grace_luck_4",2500],["haste5",3800],["vigor5",28000]])]),"T8 R7 grades on, grace_luck_4 on the head")
	check(int(graded.growth.snapshot().grace.luck.gear_bps)==0,"T8 R7 before the first step gear_bps is 0")
	graded.step(Vector2.ZERO)
	check(int(graded.growth.snapshot().grace.luck.gear_bps)==2500 and graded.luck_state().run_bps==1800,"T8 R7 after the first step gear_bps is the gear's 2500 (and the drop luck 1800)")
	check(graded.open_inventory() and graded.unequip("head") and int(graded.growth.snapshot().grace.luck.gear_bps)==2500,"T8 R7 taking the head off keeps gear_bps 2500")
	graded.close_inventory()
	graded._buffs.append({"kind":"luck","until_tick":graded.tick+1800});graded._buffs_changed()
	var mul_on: int=graded.growth.snapshot().grace.luck.shrine_mul_bps
	check(mul_on==int(graded.tuning.grace.grades.luck.shrine_mul_bps) and mul_on>10000 and int(graded.growth.snapshot().grace.luck.gear_bps)==2500,"T8 R7 the luck shrine starts: the multiplier %d goes in, gear_bps stays 2500"%mul_on)
	graded._buffs.clear();graded._buffs_changed()
	check(int(graded.growth.snapshot().grace.luck.shrine_mul_bps)==10000 and int(graded.growth.snapshot().grace.luck.gear_bps)==2500,"T8 R7 the shrine ends: multiplier 1.0x, gear_bps still 2500")
	var big := t8_run(true,true,true)
	check(t8_wear(big,[t8_spec("head","head","iron_circlet",[["luck_5",1800],["grace_luck_5",4000],["haste5",3800],["vigor5",28000]])]),"T8 R7 grace_luck_5 worn")
	big.step(Vector2.ZERO)
	check(int(big.growth.snapshot().grace.luck.gear_bps)==4000,"T8 R7 a gear share of 4000 is passed on as it is (run_growth cuts it at gear_cap_bps when the offer is read)")

## D23 T8 "no empty golden": the golden case luck-on (seed 11, frost, luck on in the run's own tables, kit.golden.t8, the QA pilot) must show luck_locked
## with 3000 and capped, count luck rolls, and still run on with luck_bps 3000 after the head is taken off. The pilot may play on after that.
func t8_golden_checks() -> void:
	var TrialDocs := preload("res://chapter1/tests/support/trial_docs.gd")
	var Pilot := preload("res://chapter1/core/chapter_pilot.gd")
	var run := Chapter.new();var pilot: RefCounted=Pilot.new();pilot.run=run
	check(TrialDocs.enable_luck_problem(run).is_empty(),"T8 golden fixture: the run's own loot tables take the luck on")
	check(run.start(11,FROST),"T8 golden fixture: the run starts")
	var problem: String=TrialDocs.wear_fixture_kit_problem(run,"kit.golden.t8")
	check(problem.is_empty(),"T8 golden fixture: the kit is worn through import_starting_gear ("+problem+")")
	check(int(run.luck_state().worn_bps)==7200 and not run.luck_state().locked,"T8 golden fixture: 7200 worn (over the 3000 cap), not locked before the first step (%s)"%str(run.luck_state()))
	var locked_events := 0;var capped_ok := false;var luck_bps_ok := false
	var head_uid: int=int(run.equipped.get("head",-1))
	var grace_share_ok := int(run._gear_totals(run.equipped).get("grace_luck_bps",0))==2500
	var stop := 6000
	while run.mode not in ["victory","defeat"] and run.tick<stop:
		run.step(pilot.decide())
		for event in run.events:
			if event.type=="luck_locked":
				locked_events+=1;capped_ok=bool(event.capped);luck_bps_ok=int(event.luck_bps)==3000 and int(event.worn_bps)==7200
	check(locked_events==1 and capped_ok and luck_bps_ok,"T8 golden fixture: luck_locked once with luck_bps 3000, worn_bps 7200 and capped true by tick %d (seen %d)"%[run.tick,locked_events])
	check(run.metrics.has("luck") and int(run.metrics.luck.rolls)>=1,"T8 golden fixture: metrics.luck.rolls >= 1 by tick %d (%s)"%[run.tick,str(run.metrics.get("luck",{}))])
	check(grace_share_ok,"T8 golden fixture: the head carries grace_luck_bps 2500 (a dead line while the grades are off)")
	var worn_before: int=run.luck_state().worn_bps
	var head_luck: int=int(run._owned(head_uid).get("stats",{}).get("luck_bps",0))
	check(run.mode=="playing" and run.open_inventory() and run.unequip("head"),"T8 golden fixture: the head can be taken off mid-run (mode %s)"%run.mode)
	var after: Dictionary=run.luck_state()
	check(after.run_bps==3000 and after.worn_bps==worn_before-head_luck and (head_luck==0 or after.worn_bps<worn_before),"T8 golden fixture: with the head off run_bps is still 3000 and worn_bps fell by the head's %d (%s)"%[head_luck,str(after)])
	print("T8_GOLDEN_FIXTURE ",JSON.stringify({"tick":run.tick,"mode":run.mode,"luck_locked":locked_events,"rolls":run.metrics.get("luck",{}).get("rolls",-1)}))

func execute() -> void:
	var rng := RandomNumberGenerator.new();rng.seed=672384
	var seen := {};var groups_ok := true;var valid := true
	for i in 12000:
		var level := 1+i%12
		var quality: String=["common","magic","rare"][i%3]
		var item: Dictionary=Items.roll(rng,level,quality)
		seen[item.base_id]=true;valid=valid and Items.validate(item).is_empty()
		var groups: Array=[]
		for a in item.affixes:
			groups_ok=groups_ok and not a.group in groups;groups.append(a.group)
	check(valid,"12000 bounded/eligible item rolls")
	check(groups_ok,"Affix group exclusion")
	check(seen.size()==12,"All12 bases reachable")
	for i in 3:check(Items.validate(Items.unique(i,12)).is_empty(),"Unique validates "+str(i))
	var forged := Items.unique(0,5);forged.stats.projectiles=200
	check(not Items.validate(forged).is_empty(),"Forged stat bound rejected")
	var first := Chapter.new();check(first.start(71),"Chapter config")
	check(first._clamp_point(Vector2(30,0)).x==19,"Next zone locked")
	check(first._clamp_point(Vector2(-25,0)).x==-19,"First western bound")
	first.tick=70*60;first.step()
	check(first.mode=="playing" and first._champion_id==-1,"Old70seconds is not full chapter win/spawn")
	check(not first.drink_potion() and first.potions==3,"No potion wasted at full HP")
	first.hero.hp_raw=60*256
	check(first.drink_potion() and first.potions==2 and first.hero.hp_raw==102*256,"Manual35percent potion")
	check(not first.drink_potion() and first.potions==2,"Potion cooldown")
	first.set_paused(true);first.tick+=4*60
	check(not first.drink_potion(),"Potion forbidden while paused")
	first.set_paused(false)
	check(not first.activate_ritual("vigil"),"Ritual proximity required")
	first.hero.position=Vector2(8,-7)
	check(first.activate_ritual("vigil") and not first.activate_ritual("vigil"),"Ritual one start")
	first.rituals.vigil.progress=25*60-1;first._step_rituals()
	check(first.rituals.vigil.state=="completed","Hold ritual completes actual last hold step")
	var reward_count := first.inventory.size();first._step_rituals()
	check(first.inventory.size()==reward_count,"Trial reward one time")
	# Fixture accelerates objectives, not a normal-run duration/skill proof.
	var run := Chapter.new();check(run.start(90131),"Fresh objective fixture")
	for z in 3:
		run.hero.position=Chapter.ZONES[z];run._zone_entered=true;run.zone_kills=run.tuning.seal_kills[z]
		run._spawn_wave()
		var champion: int=run._champion_id
		check(champion>0 and run.enemies.has(champion),"Champion exists zone "+str(z))
		check(run.mode=="playing","Spawn never wins zone "+str(z))
		if z==2:
			var boss: Dictionary=run.enemies[champion]
			run._damage_enemy(champion,context(run,int(boss.max_hp_raw)/2),0)
			run._step_chapter_hazards()
			check(run._boss_phase==2,"Boss phase changes from actual damage")
			run._next_ward=run.tick;run._step_chapter_hazards()
			check(run.chapter_hazards.size()==3,"Phase2 three paid warning circles")
			var h: Dictionary=run.chapter_hazards[0];run.hero.position=h.position
			var hp_before: int=run.hero.hp_raw
			run.tick=h.expires-1;run._step_chapter_hazards()
			check(run.hero.hp_raw==hp_before,"Ward no early damage")
			run._next_ward=run.tick+999;run.tick+=1;run._step_chapter_hazards()
			check(run.hero.hp_raw==hp_before-int(run.tuning.boss_ward.damage)*256,"Ward damage matches1.8m circle at warning expiry")
			check(run.mode=="playing","Nonlethal ward continues")
			run._next_ward=run.tick;run._step_chapter_hazards();run.hero.position=Vector2(100,10)
			hp_before=run.hero.hp_raw;run.tick+=72;run._next_ward=run.tick+999;run._step_chapter_hazards()
			check(run.hero.hp_raw==hp_before,"Outside paid circles receives no ward damage")
		run._damage_enemy(champion,context(run,100000000),0)
		if z<2:
			check(run.zone==z+1 and run.mode=="playing","Actual champion kill opens next zone "+str(z))
			check(run._clamp_point(Chapter.ZONES[z+1])==Chapter.ZONES[z+1],"Unlocked next courtyard")
			check(is_equal_approx(run._clamp_point(Vector2(24+48*z,8)).y,3.6),"Corridor restricts width")
			check(not run._zone_entered,"Next objective requires actual visit")
		else:
			check(run.mode=="victory" and run.seals[2].cleared,"Only actual final boss kill wins")
			check(run.chapter_hazards.is_empty(),"No paid hazards after boss victory")
			var reward: Dictionary={}
			for owned in run.inventory:
				if int(owned.uid)==int(run._elite_reward_uid):reward=owned
			check(not reward.is_empty() and reward.quality=="unique" and reward.get("objective_reward",false),"First boss kill grants an owned unique as the objective reward")
			check(run.inventory.size()>=6,"Boss kill drops its whole treasure class into the bag")
			var owned := run.inventory.size();run._damage_enemy(champion,context(run,1000000),0)
			check(run.inventory.size()==owned,"No duplicate boss reward")
	check(run.start(72) and run.zone==0 and run.potions==3 and run.history.size()==1 and run.pending_rewards.is_empty(),"Retry clears chapter state")
	run.zone=1;run.enemies.clear();run._spawn("elite",Vector2(48,0));var cantor: Dictionary=run.enemies[run._enemy_sequence]
	cantor.attack_kind="frost_cross";cantor.attack_direction=Vector2.RIGHT
	run.hero.position=Vector2(52,0);var hp_before_cross: int=run.hero.hp_raw
	run._resolve_elite_attack(cantor,cantor.definition,4)
	check(run.hero.hp_raw<hp_before_cross,"Cross capsule actual damage")
	run.tick+=100;run.hero.position=Vector2(51,3);hp_before_cross=run.hero.hp_raw
	run._resolve_elite_attack(cantor,cantor.definition,4)
	check(run.hero.hp_raw==hp_before_cross,"Between cross arms safe")
	run.start(13);run.inventory.clear();var staff: Dictionary=Items.BASES[2].duplicate(true)
	# Actual item roll plus intrinsic pierce increases the cast's bounded hit budget.
	var weapon: Dictionary=Items.roll(rng,8,"common","weapon")
	weapon=Items.roll(rng,8,"common","weapon")
	while weapon.base_id!="chapter1.full.piercing_sceptre":weapon=Items.roll(rng,8,"common","weapon")
	weapon.storage_id=1;var original: Dictionary=run.effective_skill("chapter1.skill.ember")
	check(run.import_starting_gear([weapon]),"Valid persistent pierce weapon import")
	var effective: Dictionary=run.effective_skill("chapter1.skill.ember")
	check(effective.effects.pierce==original.effects.pierce+1 and effective.effects.hit_budget>original.effects.hit_budget,"Pierce gear has real hit budget")
	pressure_checks()
	round2_checks()
	t1b_checks()
	t5_checks()
	t15b_checks()
	t9_core_checks()
	t17_checks()
	t17_golden_checks()
	t8_checks()
	t8_golden_checks()
	build_checks()
	abandon_checks()
	sheet_checks()
	pickup_flow_checks()
	verdict_v2_checks()
	if "--negative" in OS.get_cmdline_user_args():check(false,"Intentional checker failure")
	print("CHAPTER_FULL_TEST ",JSON.stringify({"checks":checks,"failures":failures,"scope":"Fixtures and12000 item rolls; not normal-run pacing or visual approval"}))
	quit(0 if failures.is_empty() else 1)

## GM-B: pickup_verdict with loot.json upgrade_verdict on (switched in memory). Items are made by hand. Off, every answer is the one the D21 checks above pin.
func verdict_v2_checks() -> void:
	var mk := func(uid: int,slot_: String,stats: Dictionary,quality: String="magic") -> Dictionary:
		return {"uid":uid,"name":"item%d"%uid,"slot":slot_,"stats":stats,"quality":quality,"item_level":1,"affixes":[],"description":"","required_level":1}
	var run=Chapter.new();check(run.start(43,FROST),"GM-B run starts")
	check(not run.loot.verdict_on() and run.loot.data.upgrade_verdict.enabled==false,"GM-B the shipped switch is off")
	run.inventory.clear();run.equipped.clear();run._recompute_gear()
	run.inventory.append(mk.call(961,"ring",{"chain_targets":3,"arc_damage_bps":-1000},"legendary"))
	run.inventory.append(mk.call(962,"weapon",{"projectiles":2,"damage_bps":-1500},"legendary"))
	run.inventory.append(mk.call(963,"weapon",{"damage_bps":1000}))
	run.inventory.append(mk.call(964,"hands",{"damage_bps":3000},"rare"))
	run.inventory.append(mk.call(965,"charm",{"fire_damage_bps":1500}))
	var off_ring: Dictionary=run.pickup_verdict(961)
	check(off_ring.react=="open" and off_ring.better=="yes" and not off_ring.has("note"),"GM-B off: a legendary ring in an empty slot is open and better yes, no note key")
	var off_charm: Dictionary=run.pickup_verdict(965)
	check(off_charm.react=="auto_equip" and off_charm.better=="yes" and not off_charm.has("verdict_delta"),"GM-B off: an item the witch does not read still auto-equips into an empty slot")
	var before := fingerprint(run)
	check(run.loot.set_verdict(true),"GM-B switch on in memory")
	# Case 3 (core): frost, empty ring, a galvanic ring: nothing is worn, the card says it does nothing.
	var on_ring: Dictionary=run.pickup_verdict(961)
	check(on_ring.react=="open" and on_ring.better=="no" and on_ring.note=="empty_no_effect","GM-B on: frost, empty ring, galvanic: open (the cue stays), better no, note empty_no_effect")
	var on_charm: Dictionary=run.pickup_verdict(965)
	check(on_charm.react=="card" and on_charm.better=="no" and on_charm.note=="empty_no_effect","GM-B on: an empty slot with nothing the witch reads is a card, never auto_equip")
	var on_hands: Dictionary=run.pickup_verdict(964)
	check(on_hands.react=="auto_equip" and on_hands.better=="yes" and on_hands.note=="" and float(on_hands.verdict_delta)>0.0,"GM-B on: an empty slot that raises V still auto-equips")
	check(fingerprint(run)==before,"GM-B on: pickup_verdict leaves the state byte-identical")
	# Case 4 (core): another witch's legendary: the opening stays, better is not.
	run.equipped.weapon=963;run._recompute_gear()
	run.inventory.append(mk.call(966,"weapon",{"chain_targets":3,"arc_damage_bps":-1000},"legendary"))
	var worn_state := fingerprint(run)
	var other: Dictionary=run.pickup_verdict(966)
	check(other.react=="open" and other.better=="no" and other.note=="weak_for_primary","GM-B on: an arc legendary weapon for frost: open true, better no, weak_for_primary")
	# Case 1 / 2 (core): a splitting weapon over +10%: the core's own shots are read (frost r1 = 2).
	var split: Dictionary=run.pickup_verdict(962)
	check(split.react=="open" and split.better in ["yes","no"],"GM-B on: splitting weapon over a +10% weapon is open")
	var rare_hands: Dictionary=run.pickup_verdict(964)
	check(rare_hands.better=="yes","GM-B on: +30% hands with a weapon worn is better")
	check(fingerprint(run)==worn_state,"GM-B on: with gear worn the state is byte-identical")
	check(run.is_better_gear(run.inventory[3],{},"hands") and not run.is_better_gear(run.inventory[4],{},"charm"),"GM-B on: is_better_gear follows the verdict (the app's fallback path)")
	# VO7: both rings worn, a stronger ring: with the switch on target_slot names the weaker ring; off it stays "ring".
	run.inventory.append(mk.call(971,"ring",{"damage_bps":4000},"rare"));run.inventory.append(mk.call(972,"ring",{"damage_bps":300}));run.inventory.append(mk.call(973,"ring",{"damage_bps":2500}))
	run.equipped.ring=973;run.equipped.ring2=972;run._recompute_gear()
	check(run.target_slot(run.inventory[inventory_index(run,971)])=="ring2","VO7 on: both rings worn, the stronger ring goes where the weaker one is (ring2)")
	check(run.pickup_verdict(971).slot=="ring2" and run.pickup_verdict(971).better=="yes","VO7 on: pickup_verdict judges the same slot")
	check(run.quick_equip(971) and int(run.equipped.ring2)==971 and int(run.equipped.ring)==973,"VO7 on: quick_equip wears it in the weaker ring's slot")
	run.loot.set_verdict(false)
	run.equipped.ring=973;run.equipped.ring2=972
	check(run.target_slot(run.inventory[inventory_index(run,971)])=="ring","VO7 off: both rings worn, target_slot stays ring")
	check(run.is_better_gear(run.inventory[4],{},"charm") and run.pickup_verdict(965).react=="auto_equip" and not run.pickup_verdict(965).has("note"),"GM-B off again: the old answers return")

func inventory_index(run, uid: int) -> int:
	for i in run.inventory.size():
		if int(run.inventory[i].uid)==uid:return i
	return -1

## D21 W1: pickup_verdict (N1), pickup_flow (N3), loot_flow (N2). Items and stats are made by hand so every verdict is known.
func pickup_flow_checks() -> void:
	var run=Chapter.new();check(run.start(43,FROST),"D21 run starts")
	check(run.loot.data.has("pickup_flow") and run.loot.data.pickup_flow.open_min_quality=="legendary","D21 loot.json carries the pickup_flow block and the loader accepts it")
	var mk := func(uid: int,slot_: String,stats: Dictionary,quality: String="magic",req: int=1) -> Dictionary:
		return {"uid":uid,"name":"item%d"%uid,"slot":slot_,"stats":stats,"quality":quality,"item_level":1,"affixes":[],"description":"","required_level":req}
	run.inventory.clear();run.equipped.clear();run._recompute_gear()
	run.inventory.append(mk.call(921,"weapon",{"damage_bps":500}))
	run.inventory.append(mk.call(922,"weapon",{"damage_bps":5000}))
	run.inventory.append(mk.call(923,"weapon",{"damage_bps":100}))
	run.inventory.append(mk.call(924,"body",{"max_hp_raw":2560},"legendary"))
	run.inventory.append(mk.call(925,"ring",{"damage_bps":9000},"rare",99))
	run.inventory.append(mk.call(926,"head",{"max_hp_raw":2560},"unique"))
	var before := fingerprint(run)
	var v1: Dictionary=run.pickup_verdict(921)
	check(v1.react=="auto_equip" and v1.empty_slot and v1.better=="yes" and not v1.veiled and v1.slot=="weapon" and v1.replaces_uid==0,"D21 an empty slot the level allows gives auto_equip")
	check(v1.top_rows.size()>=1 and v1.top_rows.size()<=3,"D21 the verdict carries one to three rows of preview_equip")
	check(run.pickup_verdict(924).react=="open" and run.pickup_verdict(926).react=="open","D21 legendary and unique give open, also on an empty slot")
	check(run.pickup_verdict(925).react=="quiet" and run.pickup_verdict(925).top_rows.is_empty(),"D21 a required level above the hero's gives quiet")
	check(run.pickup_verdict(99999).is_empty(),"D21 an unknown uid gives {}")
	check(fingerprint(run)==before,"D21 pickup_verdict leaves equipped, hero, _gear_stats and snapshot byte-identical")
	run.equipped.weapon=921;run._recompute_gear()
	var worn_before := fingerprint(run)
	var v2: Dictionary=run.pickup_verdict(922)
	check(v2.react=="card" and v2.better=="yes" and not v2.empty_slot and v2.replaces_uid==921,"D21 a clearly better item for a filled slot gives card")
	check(run.pickup_verdict(923).react=="quiet" and run.pickup_verdict(923).better=="no","D21 a worse item gives quiet")
	check(run.pickup_verdict(921).react=="quiet","D21 an item already worn gives quiet")
	check(fingerprint(run)==worn_before,"D21 pickup_verdict with gear worn leaves the state byte-identical")
	# Veiled gear (marked by hand; nothing marks it while identify is off): better is unknown, the branch is auto_equip / open / card.
	run.inventory.append(mk.call(941,"weapon",{"damage_bps":100}))
	run.inventory.append(mk.call(942,"body",{"max_hp_raw":2560},"legendary"))
	run.inventory.append(mk.call(943,"feet",{"max_hp_raw":2560},"rare"))
	run.inventory.append(mk.call(944,"head",{"max_hp_raw":2560},"rare"))
	for veiled_uid in [941,942,943,944]:
		for it in run.inventory:
			if it.uid==veiled_uid:it.veiled=true
	run.equipped.head=944
	var vv: Dictionary=run.pickup_verdict(943)
	check(vv.veiled and vv.better=="unknown" and vv.react=="auto_equip","D21 veiled item for an empty slot gives auto_equip with better unknown")
	check(run.pickup_verdict(942).react=="open" and run.pickup_verdict(942).veiled,"D21 veiled legendary gives open")
	check(run.pickup_verdict(941).react=="card" and run.pickup_verdict(941).better=="unknown" and run.pickup_verdict(921).veiled==false,"D21 veiled item for a filled slot gives card, an unmarked item stays veiled false")
	run.loot.data.pickup_flow.auto_equip_veiled=false
	check(run.pickup_verdict(943).react=="card","D21 auto_equip_veiled false: a veiled item for an empty slot gives card")
	run.loot.data.pickup_flow.auto_equip_veiled=true
	run.equipped.erase("head")
	for it in run.inventory:it.erase("veiled")
	# The thresholds are data: one value turns the rule.
	var flow: Dictionary=run.loot.data.pickup_flow
	flow.open_min_quality="common"
	check(run.pickup_verdict(923).react=="open" and run.pickup_verdict(922).react=="open","D21 open_min_quality common: every pickup gives open")
	flow.open_min_quality="legendary";flow.card_min="any"
	check(run.pickup_verdict(923).react=="card","D21 card_min any: a worse item gives card")
	flow.card_min="better";run.equipped.erase("weapon");run._recompute_gear();flow.auto_equip_empty=false
	check(run.pickup_verdict(921).react=="card","D21 auto_equip_empty false: an empty slot gives card")
	flow.auto_equip_empty=true
	# Loader: a bad block is refused, a missing one is allowed.
	var doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://chapter1/data/loot.json"))
	doc.pickup_flow.open_min_quality="mythic"
	var bad_path := "user://d21_bad_loot.json"
	var f := FileAccess.open(bad_path,FileAccess.WRITE);f.store_string(JSON.stringify(doc));f.close()
	var probe=run.loot.get_script().new()
	check(not probe.load_file(bad_path),"D21 loot.gd refuses an unknown open_min_quality")
	doc.erase("pickup_flow")
	f=FileAccess.open(bad_path,FileAccess.WRITE);f.store_string(JSON.stringify(doc));f.close()
	var probe2=run.loot.get_script().new()
	check(probe2.load_file(bad_path),"D21 loot.gd allows a document without pickup_flow")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bad_path))
	# N2: loot_flow.
	var default_run=Chapter.new();default_run.start(17,EMBER)
	check(default_run._kept_qualities.is_empty() and default_run._gate_sweep_qualities.is_empty(),"D21 loot_flow off by default: no kept quality")
	var flow_run := tuned_run({"loot_flow":{"enabled":true,"keep_min_quality":"rare","gate_sweep_min_quality":"rare"}})
	var plain_run := tuned_run({})
	for r in [flow_run,plain_run]:
		r.items.clear();r.inventory.clear()
		var spot: Vector2=r.hero.position+Vector2(30,0)
		for pair in [[931,"rare"],[932,"magic"],[933,"legendary"],[934,"common"]]:
			var it: Dictionary=mk.call(int(pair[0]),"head",{"max_hp_raw":256},String(pair[1]))
			it.position=spot;it.drop_tick=0;it.collected=false;r.items.append(it)
		r.tick=181*60;r._collect_pickups()
	var kept: Array[int]=[]
	for it in flow_run.items:kept.append(int(it.uid))
	check(kept==[931,933] and plain_run.items.is_empty(),"D21 loot_flow on: rare and legendary stay past 180 s, magic and common go; off: all go")
	flow_run.events.clear()
	flow_run._on_elite_defeated({"position":Vector2(8,8)})
	var swept: Array[int]=[]
	for ev in flow_run.events:
		if ev.type=="item_pickup" and ev.get("swept",false) and ev.get("by","")=="gate":swept.append(int(ev.item.uid))
	var in_bag: Array[int]=[]
	for it in flow_run.inventory:in_bag.append(int(it.uid))
	check(int(flow_run.zone)==1 and swept==[931,933] and in_bag==[931,933] and flow_run.items.is_empty(),"D21 loot_flow on: the gate gathers the kept gear into the bag with by:gate")
	var bad_flow=Chapter.new();bad_flow.set_tuning(tuning_with({"loot_flow":{"enabled":true,"keep_min_quality":"mythic","gate_sweep_min_quality":"rare"}}))
	check(not bad_flow.start(17,EMBER),"D21 loot_flow with an unknown quality name refuses the start")
