extends "res://chapter1/core/combat_core.gd"
## Chapter simulation: zones, seals, champions, rituals, loot, arc stun and cold evolution.
const Items=preload("res://chapter1/core/chapter_items.gd")
const RunGrowth = preload("res://chapter1/core/run_growth_quality37.gd")
const ARC_STUN_TICKS36 := 18
const ARC_ELITE_STUN_TICKS36 := 6
const ARC_STUN_IMMUNITY36 := 120
const ARC_ELITE_IMMUNITY36 := 180
const Loot = preload("res://chapter1/core/loot.gd")
const Tuning = preload("res://chapter1/core/combat_tuning.gd")
const SkillTree = preload("res://chapter1/core/skill_tree.gd")
const Progression = preload("res://chapter1/core/character_progression.gd")
## Exact keys of a build dictionary (profile.build_for).
const BUILD_KEYS := ["character_id","tree_id","tree_revision","ranks","character_level","character_xp"]
## Frost field limits (spec 3.4 R2). The summed radius is cut to the upper bound (director decision).
const FIELD_LIMITS := {"interval_ticks":[120,600],"radius_cm":[200,600],"duration_ticks":[60,300],"slow_bps":[0,8500],"max_fields":[1,3],"pulse_damage_bps":[0,6000]}
const FIELD_JUDGE_TICKS := 6
const FIELD_PULSE_DEFAULT := 30
## Item level of each zone's drops. Champions and the boss add their class bonus.
const ZONE_LEVELS := [4,8,12]
const MAX_PENDING_REWARDS := 4
var _world_uniques36: Dictionary={}
## The loot tables are read once and shared by every run in the process.
static var _shared_loot: RefCounted
var loot: RefCounted
## Set by the caller before start(): the boss grants the signature unique only once.
var first_boss_kill := true

func _init() -> void:
	growth = RunGrowth.new()
	if _shared_loot == null:
		var tables = Loot.new()
		if tables.load_file(): _shared_loot = tables
		else: push_error("Loot tables failed to load: "+str(tables.errors))
	loot = _shared_loot

const ZONES := [Vector2(0,0),Vector2(48,0),Vector2(96,0)]
const ZONE_NAMES := ["잿빛 앞뜰","무너진 성가대","재의 성소"]
## Kills that break each zone's seal: tuning.seal_kills (chapter1/data/combat_tuning.json).
const RITUALS := [
	{"id":"vigil","name":"꺼지지 않는 불씨","position":Vector2(8,-7),"zone":0,"kind":"hold"},
	{"id":"reliquary","name":"봉인된 성유물","position":Vector2(40,6),"zone":1,"kind":"kill"}
]
var zone := 0
var zone_kills := 0
var seals: Array[Dictionary]=[]
var potions := 3
var potion_pickups: Array[Dictionary]=[]
var pending_rewards: Array[Dictionary]=[]
var chapter_hazards: Array[Dictionary]=[]
var rituals: Dictionary={}
var history: Array[Dictionary]=[]
var _next_potion := 0
var _champion_id := -1
var _boss_phase := 0
var _next_ward := 0
var _hazard_sequence := 0
var _potion_sequence := 0
var _zone_entered := false
var _normal_drop_sequence := 0
var _ritual_spawn_tick := 0
## The default tuning document is read once and shared by every run in the process.
static var _shared_tuning: Dictionary = {}
var _secondary_active := false
## Permanent build (G1). configure_build() validates and parks it in _pending_build, which survives start() like a
## tuning document; start() copies it into the run (_build) and compiles the tree once into the fields below.
## Everything here stays at its zero value without a build, so a run without one is the run it always was.
static var _shared_progression: Dictionary = {}
static var _shared_trees: Dictionary = {}
var _pending_build: Dictionary = {}
var _build: Dictionary = {}
var _build_active := false
var _build_skill: Dictionary = {}
var _build_potions := 0
var _build_growth: Dictionary = {}
var _elite_bps := 0
var _shatter_extra_cm := 0
var _field_rule: Dictionary = {}
var _fields: Array[Dictionary] = []
var _field_uid := 0
var _next_field := 0
var _progress: Dictionary = {}
## The two non-primary skills in catalog order; the index is the mark slot (enemy keys mark_until_a / mark_until_b,
## created only when a mark is first set). Rebuilt by start().
var _mark_owners: Array[String] = []
## Tick of the latest floor-strike burst (ward_gap_ticks keeps the boss's next wind-up end clear of it). Not in the snapshot.
var _last_ward_burst := -100000
const MARK_KEYS := ["mark_until_a","mark_until_b"]

## Replace the tuning of this run (before start()). A rejected document changes nothing.
func set_tuning(candidate: Dictionary) -> bool:
	var loader = Tuning.new()
	if not loader.replace_document(candidate,SKILL_IDS,MAX_ALIVE,MAX_PROJECTILES-MAX_HOSTILE_PROJECTILES):
		errors.assign(loader.errors);return false
	_install_tuning(loader.snapshot())
	return true

func load_tuning(path: String) -> bool:
	var loader = Tuning.new()
	if not loader.load_file(path,SKILL_IDS,MAX_ALIVE,MAX_PROJECTILES-MAX_HOSTILE_PROJECTILES):
		errors.assign(loader.errors);return false
	_install_tuning(loader.snapshot())
	return true

func _install_tuning(document: Dictionary) -> void:
	Tuning.lock(document)
	tuning=document
	var s: Dictionary=document.secondary
	_secondary_active=not s.is_empty() and not (int(s.damage_bps)==10000 and int(s.hit_budget_bps)==10000 and int(s.cooldown_bps)==10000 and int(s.max_chain_targets)>=32 and int(s.max_branches)>=4)

func start(seed_: int=1, primary: String="chapter1.skill.ember") -> bool:
	# A build belongs to one witch and her signature skill; any other start is refused before anything changes.
	if not _pending_build.is_empty() and _build_signature(_pending_build)!=primary:
		errors.assign(["빌드의 마녀와 시작 기술이 다릅니다"]);return false
	if tuning.is_empty():
		if _shared_tuning.is_empty():
			var loader = Tuning.new()
			if not loader.load_file(Tuning.DEFAULT_PATH,SKILL_IDS,MAX_ALIVE,MAX_PROJECTILES-MAX_HOSTILE_PROJECTILES):
				errors.assign(loader.errors);push_error("Combat tuning failed to load: "+str(loader.errors));return false
			_shared_tuning=loader.snapshot()
		_install_tuning(_shared_tuning)
	_activate_build()
	_world_uniques36.clear()
	zone=0;zone_kills=0;potions=int(tuning.potion.start);_next_potion=0;_champion_id=-1;_boss_phase=0;_next_ward=0
	_hazard_sequence=0;_potion_sequence=0;_zone_entered=true;_normal_drop_sequence=0;_ritual_spawn_tick=0
	seals.clear();history.clear();potion_pickups.clear();pending_rewards.clear();chapter_hazards.clear();rituals.clear()
	if _build_potions>0:potions=mini(int(tuning.potion.carry_max),potions+_build_potions)
	for i in 3:seals.append({"kills":0,"champion_spawned":false,"cleared":false})
	for def in RITUALS:rituals[def.id]={"state":"ready","progress":0,"started_tick":-1,"completed_tick":-1}
	if not super.start(seed_,primary):return false
	_mark_owners.clear()
	_last_ward_burst=-100000
	for id_ in SKILL_IDS:
		if id_!=primary and _mark_owners.size()<MARK_KEYS.size():_mark_owners.append(id_)
	var doc: Dictionary=_catalog.snapshot();doc.xp_thresholds=tuning.xp_thresholds.duplicate()
	if not growth.configure(doc,primary,seed_ ^ 0x47524f57):errors.assign(growth.errors);return false
	if _build_active:
		if _build_max_hp>0:hero.max_hp_raw=120*UNIT+_build_max_hp*UNIT;hero.hp_raw=hero.max_hp_raw
		if not growth.set_options(_build_growth):errors.assign(growth.errors);return false
		if not _field_rule.is_empty():_next_field=int(_field_rule.interval_ticks)
	_record("chapter_started")
	return true

# ---------------------------------------------------------------- permanent build (G1)

## The progression document and the skill trees are read once and shared by every run in the process.
static func _growth_data() -> bool:
	if _shared_progression.is_empty() or _shared_trees.is_empty():
		var doc := Progression.load_document()
		var problems: Array[String]=[]
		if not doc.has("error"):problems=Progression.validate_document(doc)
		if doc.has("error") or not problems.is_empty():
			push_error("Character progression failed to load: "+str(doc.get("error",problems)));return false
		var loaded := SkillTree.load_trees(SkillTree.DEFAULT_PATH,doc)
		if loaded.has("error"):push_error("Skill trees failed to load: "+str(loaded.error));return false
		_shared_progression=doc;_shared_trees=loaded
	return true

## The skill id of the witch a build belongs to ("" when the build or the witch is unknown).
func _build_signature(build: Dictionary) -> String:
	if not _growth_data():return ""
	return String(Progression.character_entry(_shared_progression,String(build.get("character_id",""))).get("signature_skill_id",""))

## A cleaned copy of the build (integers only), or {"error": reason}. The same skill_tree.gd rules the profile
## uses decide whether the ranks are legal. The core does not see the witch's first-kill receipts, so it grants
## the most points she could hold at this level.
func _normalize_build(build: Dictionary) -> Dictionary:
	if build.is_empty():return {"error":"빈 빌드 사전입니다 · clear_build()를 쓰세요"}
	if not _growth_data():return {"error":"성장 데이터를 읽지 못했습니다"}
	if build.size()!=BUILD_KEYS.size():return {"error":"빌드 키가 맞지 않습니다"}
	for key in BUILD_KEYS:
		if not build.has(key):return {"error":"빌드 키 없음: "+key}
	var doc: Dictionary=_shared_progression
	var known: Dictionary=Progression.character_entry(doc,build.character_id) if build.character_id is String else {}
	if known.is_empty():return {"error":"알 수 없는 캐릭터"}
	if not GrowthCatalog.integer(build.character_xp,0,1000000000) or not GrowthCatalog.integer(build.character_level,1,int(doc.level_cap)):return {"error":"캐릭터 레벨·경험치 범위 밖"}
	if Progression.level_for_xp(doc,int(build.character_xp))!=int(build.character_level):return {"error":"캐릭터 레벨이 경험치와 맞지 않습니다"}
	if not build.tree_id is String or not build.ranks is Dictionary or not GrowthCatalog.integer(build.tree_revision,0,1000000):return {"error":"트리 형식 오류"}
	var ranks := {}
	for node_id in build.ranks:
		if not node_id is String or not SkillTree.integer_(build.ranks[node_id],1,10):return {"error":"랭크 형식 오류"}
		ranks[node_id]=int(build.ranks[node_id])
	var clean := {"character_id":build.character_id,"tree_id":build.tree_id,"tree_revision":int(build.tree_revision),"ranks":ranks,"character_level":int(build.character_level),"character_xp":int(build.character_xp)}
	var has_tree: bool=known.get("tree_id")!=null
	if String(build.tree_id).is_empty():
		if has_tree or int(build.tree_revision)!=0 or not ranks.is_empty():return {"error":"트리가 없는 마녀의 빌드가 아닙니다"}
		return clean
	if not has_tree or known.tree_id!=build.tree_id or not _shared_trees.has(build.tree_id):return {"error":"이 마녀의 트리가 아닙니다"}
	var tree: Dictionary=_shared_trees[build.tree_id]
	if int(build.tree_revision)!=int(tree.revision):return {"error":"트리 리비전이 다릅니다"}
	var bound := (int(build.character_level)-1)*int(doc.points_per_level)
	for reward in doc.first_rewards:bound+=int(doc.first_rewards[reward])
	var problems: Array[String]=SkillTree.legal_ranks(tree,ranks,int(build.character_level),bound)
	if not problems.is_empty():return {"error":"트리 투자 검증 실패 · "+problems[0]}
	return clean

## Take a build for the next start(). Call it before start(); a rejected build changes nothing. The build lives
## like a tuning document: start() does not clear it, so a retry keeps it (call it again after a save to refresh).
func configure_build(build: Dictionary) -> bool:
	var normalized := _normalize_build(build)
	if normalized.has("error"):errors.assign([String(normalized.error)]);return false
	_pending_build=normalized
	return true

func clear_build() -> void:
	_pending_build={}

## Compile the parked build for this run (tree once, in the data's node order) and derive every rule value.
func _activate_build() -> void:
	_build={};_build_active=false;_build_skill={};_build_potions=0;_build_growth={};_elite_bps=0;_shatter_extra_cm=0
	_field_rule={};_fields.clear();_field_uid=0;_next_field=0;_progress={};_build_max_hp=0;_build_reduction_bps=0
	if _pending_build.is_empty():return
	_build=_pending_build.duplicate(true);_build_active=true
	var compiled := {"skill":{},"hero":{},"rules":{}}
	if not String(_build.tree_id).is_empty():compiled=SkillTree.compile(_shared_trees[_build.tree_id],_build.ranks)
	var hero_block: Dictionary=compiled.hero;var rules: Dictionary=compiled.rules
	_build_skill=compiled.skill
	_build_max_hp=clampi(int(hero_block.get("max_hp",0)),0,60)
	_build_reduction_bps=clampi(int(hero_block.get("damage_reduction_bps",0)),0,1500)
	_build_potions=clampi(int(hero_block.get("potion_start",0)),0,2)
	_elite_bps=clampi(int(rules.get("elite_damage_bps",0)),0,6000)
	_shatter_extra_cm=clampi(int(rules.get("shatter_radius_cm",0)),0,200)
	_build_growth={"start_rank":clampi(int(rules.get("start_rank",1)),1,2),"grace_rerolls":clampi(int(rules.get("grace_rerolls",0)),0,3),"evolve_without_passive":bool(rules.get("evolve_without_passive",false))}
	if rules.has("frost_field"):
		var field: Dictionary=rules.frost_field;var add: Dictionary=rules.get("frost_field_add",{})
		var rule := {"interval_ticks":int(field.interval_ticks),"radius_cm":int(field.radius_cm)+int(add.get("radius_cm",0)),
			"duration_ticks":int(field.duration_ticks),"slow_bps":maxi(int(field.slow_bps),int(add.get("slow_bps_at_least",0))),
			"max_fields":int(field.max_fields)+int(add.get("max_fields",0)),"pulse_damage_bps":int(field.pulse_damage_bps)+int(add.get("pulse_damage_bps",0))}
		for key in FIELD_LIMITS:rule[key]=clampi(int(rule[key]),int(FIELD_LIMITS[key][0]),int(FIELD_LIMITS[key][1]))
		rule.freeze_every_ticks=int(field.freeze_every_ticks)
		rule.pulse_every_ticks=int(field.pulse_every_ticks) if int(field.pulse_every_ticks)>0 else FIELD_PULSE_DEFAULT
		_field_rule=rule
	_progress={"xp":0,"seal":[0,0,0],"champion":[0,0],"boss":0,"victory":0,"first_kills":[],"level":Progression.level_for_xp(_shared_progression,int(_build.character_xp))}

## The run's permanent progress so far (spec 7.1); {} without a build. Safe to read at any time, also mid-run.
## Level up events carry points from levels only; the first-kill points are the profile's business.
func progress_summary() -> Dictionary:
	if not _build_active:return {}
	var gained := int(_progress.xp)
	return {"character_id":_build.character_id,"xp_gained":gained,
		"sources":{"seal":_progress.seal.duplicate(),"champion":_progress.champion.duplicate(),"boss":int(_progress.boss),"victory":int(_progress.victory)},
		"first_kills":_progress.first_kills.duplicate(),
		"level_before":Progression.level_for_xp(_shared_progression,int(_build.character_xp)),
		"level_after":Progression.level_for_xp(_shared_progression,int(_build.character_xp)+gained)}

func _grant_progress(source: String,amount: int,index: int=-1) -> void:
	if amount<=0:return
	_progress.xp=int(_progress.xp)+amount
	match source:
		"seal":_progress.seal[index]=int(_progress.seal[index])+amount
		"champion":_progress.champion[index]=int(_progress.champion[index])+amount
		"boss":_progress.boss=int(_progress.boss)+amount
		"victory":_progress.victory=int(_progress.victory)+amount
	_emit("progress_xp",hero.position,{"source":source,"zone":index,"amount":amount,"xp_gained":int(_progress.xp)})
	var level := Progression.level_for_xp(_shared_progression,int(_build.character_xp)+int(_progress.xp))
	while int(_progress.level)<level:
		_progress.level=int(_progress.level)+1
		_emit("character_level_up",hero.position,{"level":int(_progress.level),"points_total":(int(_progress.level)-1)*int(_shared_progression.points_per_level)})

## A kill that counts toward the zone's seal pays its share of seal_xp[zone]. The share is cumulative
## (xp*n/total), so the zone always pays exactly its figure whatever seal_kills is, and kills after the seal is
## full (the guardian has appeared) pay nothing.
func _progress_seal() -> void:
	var total := int(tuning.seal_kills[zone]);var n := zone_kills
	if n<1 or n>total:return
	var list: Array=_shared_progression.sources.seal_xp
	var xp := int(list[mini(zone,list.size()-1)])
	_grant_progress("seal",xp*n/total-xp*(n-1)/total,zone)

func _progress_first_kill(id_: String) -> void:
	if _shared_progression.first_rewards.has(id_) and not id_ in _progress.first_kills:_progress.first_kills.append(id_)

func _progress_guardian() -> void:
	var sources: Dictionary=_shared_progression.sources
	if zone<2:
		var list: Array=sources.champion_xp
		_grant_progress("champion",int(list[mini(zone,list.size()-1)]),zone);_progress_first_kill("champion:%d"%zone)
	else:
		_grant_progress("boss",int(sources.boss_xp));_progress_first_kill("boss");_grant_progress("victory",int(sources.victory_xp))

## R5: throw the standing grace offer away for a new one. Only in the choice mode, only while re-draws are left.
func reroll_offer(token: String) -> bool:
	if mode!="choice" or not growth.reroll(token):return false
	_emit("grace_reroll",hero.position,{"left":growth.rerolls_left()})
	return true

func rerolls_left() -> int:
	return growth.rerolls_left()

## The build's block on the signature skill: add, at_least, at_most (0 = off is switched on), mul_bps, cooldown,
## then the catalog limits and the gear rule for pierce (spec 3.3).
func _apply_build_skill(effect: Dictionary) -> void:
	var block: Dictionary=_build_skill
	for stat in block.get("add",{}):effect[stat]=int(effect[stat])+int(block.add[stat])
	for stat in block.get("at_least",{}):effect[stat]=maxi(int(effect[stat]),int(block.at_least[stat]))
	for stat in block.get("at_most",{}):effect[stat]=int(block.at_most[stat]) if int(effect[stat])==0 else mini(int(effect[stat]),int(block.at_most[stat]))
	for stat in block.get("mul_bps",{}):effect[stat]=int(effect[stat])*int(block.mul_bps[stat])/10000
	if block.has("cooldown_bps"):effect.cooldown_ticks=maxi(12,int(effect.cooldown_ticks)*int(block.cooldown_bps)/10000)
	for stat in GrowthCatalog.LIMITS:effect[stat]=_limited(stat,int(effect[stat]))
	effect.pierce=mini(8,int(effect.pierce))

# ---------------------------------------------------------------- frost field (R2)

## Fields live after the hero acts: expire, create when due (nearest enemy within 13 m), then judge every
## FIELD_JUDGE_TICKS ticks of a field's age: slow, freeze stack, pulse damage.
func _step_fields() -> void:
	if _field_rule.is_empty():return
	var live: Array[Dictionary]=[]
	for f in _fields:
		if tick>=int(f.until_tick):_emit("frost_field_end",f.position,{"uid":f.uid})
		else:live.append(f)
	_fields=live
	var judging := false
	for f in _fields:
		if (tick-int(f.created))%FIELD_JUDGE_TICKS==0:judging=true
	if tick>=_next_field or judging:_rebuild_grid()
	if tick>=_next_field:
		var near := _near(hero.position,13.0)
		if not near.is_empty():
			var spot: Vector2=enemies[near[0]].position
			_field_uid+=1
			var rule: Dictionary=_field_rule
			var field := {"uid":_field_uid,"position":spot,"radius_cm":int(rule.radius_cm),"created":tick,"until_tick":tick+int(rule.duration_ticks),
				"slow_bps":int(rule.slow_bps),"next_freeze":tick+int(rule.freeze_every_ticks),"next_pulse":tick+int(rule.pulse_every_ticks)}
			_fields.append(field)
			while _fields.size()>int(rule.max_fields):
				var oldest: Dictionary=_fields.pop_front();_emit("frost_field_end",oldest.position,{"uid":oldest.uid})
			_emit("frost_field",spot,{"uid":field.uid,"radius_cm":field.radius_cm,"until_tick":field.until_tick})
			_next_field=tick+int(rule.interval_ticks)
			judging=true
	if not judging:return
	var skill := effective_skill(_primary_id)
	if skill.is_empty():return
	for f in _fields.duplicate():
		if (tick-int(f.created))%FIELD_JUDGE_TICKS!=0:continue
		var inside := _near(f.position,float(f.radius_cm)/100.0)
		var freeze_due: bool=int(_field_rule.freeze_every_ticks)>0 and tick>=int(f.next_freeze)
		var threshold := int(skill.effects.freeze_stacks)
		for id_ in inside:
			var e: Dictionary=enemies[id_]
			if tick<int(e.slow_until):
				e.slow_bps=maxi(int(e.slow_bps),int(f.slow_bps));e.slow_until=maxi(int(e.slow_until),tick+8)
			else:
				e.slow_until=tick+8;e.slow_bps=int(f.slow_bps)
			if freeze_due and threshold>0:
				e.freeze_stacks+=1;e.freeze_expires=tick+180
				if int(e.freeze_stacks)>=threshold:e.frozen_until=tick+(12 if e.elite else 75);e.freeze_stacks=0
		if freeze_due:f.next_freeze=tick+int(_field_rule.freeze_every_ticks)
		var bps := int(_field_rule.pulse_damage_bps)
		if bps>0 and tick>=int(f.next_pulse):
			f.next_pulse=tick+int(_field_rule.pulse_every_ticks)
			var effects: Dictionary=skill.effects.duplicate(true)
			effects.damage_raw=maxi(1,int(effects.damage_raw)*bps/10000)
			effects.freeze_stacks=0;effects.shatter_count=0;effects.proc_depth=0;effects.death_burst=0
			effects.slow_bps=maxi(int(effects.slow_bps),int(f.slow_bps))
			# One pulse is one cast of its own: it never shares the lance's hit budget, never recurses, never shatters.
			_cast_sequence+=1
			var context := {"uid":_cast_sequence,"skill_id":_primary_id,"effects":effects,"remaining_hits":128,"hit_ids":[],"evolved":false,"field":true}
			for id_ in inside:_damage_enemy(id_,context,0)
			if mode!="playing":return

func _record(type: String) -> void:
	history.append({"type":type,"tick":tick,"zone":zone,"kills":kills,"zone_kills":zone_kills,"hp_raw":hero.get("hp_raw",0)})

func _initial_pack_count() -> int:
	return 12

func _clamp_point(point: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var distance := INF
	for i in range(zone+1):
		var center: Vector2=ZONES[i]
		var candidate := point.clamp(center-Vector2.ONE*19,center+Vector2.ONE*19)
		var d := point.distance_squared_to(candidate)
		if d<distance:best=candidate;distance=d
		if i>0:
			candidate=point.clamp(Vector2(center.x-29,-3.6),Vector2(center.x-19,3.6))
			d=point.distance_squared_to(candidate)
			if d<distance:best=candidate;distance=d
	return best

func _spawn_point(min_radius: float,max_radius: float) -> Vector2:
	for attempt in 16:
		var angle := _spawn_rng.randf_range(0,TAU)
		var point := _clamp_point(hero.position+Vector2(cos(angle),sin(angle))*_spawn_rng.randf_range(min_radius,max_radius))
		if point.distance_squared_to(hero.position)>=min_radius*min_radius*.64:return point
	var inward: Vector2=(ZONES[zone]-hero.position).normalized()
	if inward.length_squared()<.01:inward=Vector2.LEFT
	return _clamp_point(hero.position+inward*min_radius)

func _spawn(kind: String,point: Vector2) -> bool:
	if not super._spawn(kind,point):return false
	var e: Dictionary=enemies[_enemy_sequence]
	var definition: Dictionary=ENEMY_DEFS[kind].duplicate(true)
	# Opening trash must actually die to the first shot from every primary.
	# Distributing rank1 hits across 16HP bodies delayed all growth in pilot01.
	if kind!="elite":
		var rules: Dictionary=tuning.enemies[kind]
		var z := clampi(zone,0,2)
		var hp := int(rules.hp[z])
		var bps := int(tuning.hp_time_bps_per_s)
		if kind=="walker" and tick<int(rules.opening_until_s)*HZ:hp=int(rules.opening_hp)
		elif bps>0 and tick>=int(tuning.hp_time_from_s)*HZ:hp=maxi(1,hp*(10000+bps*(tick/HZ))/10000)
		definition.hp=hp;definition.damage=int(rules.damage[z]);definition.speed=float(rules.speed[z])
	e.definition=definition
	e.hp_raw=int(definition.hp)*UNIT;e.max_hp_raw=e.hp_raw
	return true

func _enemy_definition(e: Dictionary) -> Dictionary:
	return e.get("definition",ENEMY_DEFS[e.kind])

func _spawn_wave() -> void:
	if not _zone_entered:
		if hero.position.distance_squared_to(ZONES[zone])>18.0*18.0:return
		_zone_entered=true;_record("zone_entered");_emit("zone_entered",ZONES[zone],{"zone":zone})
	if not seals[zone].champion_spawned and zone_kills>=int(tuning.seal_kills[zone]):
		if _spawn("elite",_spawn_point(8,9)):
			seals[zone].champion_spawned=true;_champion_id=_enemy_sequence
			var e: Dictionary=enemies[_champion_id]
			e.chapter_boss=zone==2;e.title=["잿불의 문지기","서리의 성가대장","회랑의 파수왕"][zone]
			var champion: Dictionary=tuning.champions[zone]
			e.definition.hp=int(champion.hp);e.definition.windup=int(champion.windup)
			e.definition.recover=int(champion.recover);e.definition.damage=int(champion.damage)
			e.definition.xp=int(champion.xp);e.hp_raw=int(e.definition.hp)*UNIT;e.max_hp_raw=e.hp_raw
			_boss_phase=1 if zone==2 else 0;_next_ward=tick+3*HZ
			_record("boss_spawned" if zone==2 else "champion_spawned")
			_emit("chapter_champion",e.position,{"zone":zone,"target_id":e.id,"name":e.title})
			if zone==2 and tuning.final_level_on_boss_spawn:_seal_grace()
	if tick<_next_spawn:return
	# Frequent weak bodies provide sweepable packs, mixed with bounded specialists.
	var wave: Dictionary=tuning.spawn.zones[zone]
	var amount: int=int(wave.amount)
	for step in tuning.spawn.opening:
		if tick<int(step.until_s)*HZ:amount=int(step.amount);break
	if zone==2 and _champion_id>0:wave=tuning.spawn.boss_phase;amount=int(wave.amount)
	_next_spawn=tick+int(wave.interval_ticks)
	var count := alive_count()
	var alive_cap := int(tuning.alive_cap)
	var ring_min := float(tuning.spawn.ring_min_m);var ring_max := float(tuning.spawn.ring_max_m)
	var mix: Dictionary=tuning.spawn.mix
	for i in amount:
		if count>=alive_cap:break
		var roll := _spawn_rng.randi_range(0,99)
		var kind := "walker"
		if tick>=int(mix.charger_from_s)*HZ and roll>=(int(mix.charger_roll)-zone*int(mix.zone_step)):kind="charger"
		elif tick>=int(mix.ranged_from_s)*HZ and roll>=(int(mix.ranged_roll)-zone*int(mix.zone_step)):kind="ranged"
		if _spawn(kind,_spawn_point(ring_min,ring_max)):count+=1

func _step_enemies() -> void:
	# ward_gap_ticks: a floor strike already telegraphed is never moved (the player has read it). Instead the
	# final boss does not begin a wind-up whose end would fall within the gap of a pending burst; it waits
	# (a one-tick recovery, repeated) until the wind-up would end clear of every pending burst.
	var ward_gap: int=int(tuning.heavy_hit.ward_gap_ticks)
	if ward_gap>0 and zone==2 and _champion_id>0 and enemies.has(_champion_id):
		var warden: Dictionary=enemies[_champion_id]
		var ready: bool=warden.state=="move" or (warden.state=="recover" and tick>=int(warden.state_until))
		if warden.hp_raw>0 and ready and tick>=int(warden.frozen_until) and tick>=int(warden.get("stunned_until",0)):
			var attack_end: int=tick+int(warden.definition.windup)
			var held: bool=attack_end-_last_ward_burst<ward_gap
			for hazard in chapter_hazards:
				if absi(attack_end-int(hazard.expires))<ward_gap:held=true;break
			if held:warden.state="recover";warden.state_until=tick+1
	# The second champion trades the sentinel's close circle for a paid frost
	# cross. The exact same four capsules are used by telegraph and resolution.
	if zone==1 and _champion_id>0 and enemies.has(_champion_id):
		var e: Dictionary=enemies[_champion_id]
		if e.hp_raw>0 and e.state=="move" and tick>=int(e.frozen_until) and tick>=int(e.get("stunned_until",0)) and int(e.attack_index)%2==0 and e.position.distance_squared_to(hero.position)<=36:
			e.attack_direction=(hero.position-e.position).normalized()
			e.attack_kind="frost_cross";e.state="windup";e.state_until=tick+int(e.definition.windup)
			var direction: Vector2=e.attack_direction
			e.telegraph={"shape":"line","direction":direction,"radius":5.7,"length":4.8,"width":1.8,"rays":[direction,-direction,direction.orthogonal(),-direction.orthogonal()],"remaining_ticks":int(e.definition.windup)}
	super._step_enemies()

func _resolve_elite_attack(e: Dictionary,definition: Dictionary,distance: float) -> void:
	if e.attack_kind!="frost_cross":super._resolve_elite_attack(e,definition,distance);return
	for direction in [e.attack_direction,e.attack_direction.orthogonal()]:
		if _segment_distance_sq(hero.position,e.position-direction*4.8,e.position+direction*4.8)<=.9*.9:
			_hero_damage(int(definition.damage)*UNIT,e.position);break

func _emit(type: String,position: Vector2,details: Dictionary={}) -> void:
	super._emit(type,position,details)
	if type=="death" and _zone_entered and position.distance_squared_to(ZONES[zone])<26.0*26.0:
		zone_kills+=1;seals[zone].kills=zone_kills
		if _build_active:_progress_seal()
		for def in RITUALS:
			if rituals.has(def.id) and rituals[def.id].state=="active" and def.kind=="kill" and position.distance_squared_to(def.position)<10.0*10.0:
				rituals[def.id].progress+=1
		if not details.get("elite",false) and _potion_roll():_drop_potion(position)

## One loot draw per ordinary kill whatever the odds (randi_range(0,0) would draw nothing).
func _potion_roll() -> bool:
	var odds := int(tuning.potion.drop_one_in)
	if odds<=1:_loot_rng.randi();return true
	return _loot_rng.randi_range(0,odds-1)==0

func _on_elite_defeated(e: Dictionary) -> void:
	if _build_active:_progress_guardian()
	seals[zone].cleared=true;_record("seal_cleared");_elite_killed=false;_champion_id=-1
	if tuning.orbs.vacuum_on_seal:_vacuum_orbs()
	if zone==2:
		chapter_hazards.clear();_boss_phase=0
		_sweep_ground_items()
		super._on_elite_defeated(e)
		_record("chapter_completed")
	else:
		for i in int(tuning.potion.seal_drops):_drop_potion(e.position+Vector2(.4*i,0))
		zone+=1;zone_kills=0;_zone_entered=false
		_emit("gate_opened",ZONES[zone]-Vector2(24,0),{"zone":zone,"name":ZONE_NAMES[zone]})
		_record("gate_opened")

## The last seal's grace (tuning.final_level_on_boss_spawn): when the final boss appears, the orbs still on
## the ground flow to the hero and the collected experience rises to the last level threshold.
## Emits seal_grace {level, amount} (amount = experience added on top of the orbs) only if it granted something.
func _seal_grace() -> void:
	_vacuum_orbs()
	var last: int=int(tuning.xp_thresholds[tuning.xp_thresholds.size()-1])
	var missing: int=last-int(growth.snapshot().xp)
	if missing<=0 or not growth.award_xp(missing):return
	_emit("seal_grace",hero.position,{"level":int(growth.snapshot().level),"amount":missing})

## The seal breaks and every orb still on the ground flows to the hero as one gain.
func _vacuum_orbs() -> void:
	var total := 0
	for orb in orbs:total+=int(orb.amount)
	orbs.clear()
	if total<=0:return
	var gained := _gain_xp(total)
	# amount is the XP actually gained (soul bonus included); xp_pickup.amount is the orb's own face value.
	_emit("orb_vacuum",hero.position,{"amount":gained})

func _maybe_drop_item(e: Dictionary) -> void:
	var level: int=ZONE_LEVELS[zone]
	var primary_: String=growth.snapshot().primary
	if e.elite:
		# Champion and boss rewards go straight to the bag: the run may end with this kill.
		var boss: bool=e.get("chapter_boss",false)
		var drops: Array[Dictionary]=[]
		if boss and first_boss_kill:drops.append_array(loot.roll_class(_loot_rng,"boss_first_kill",level,primary_))
		drops.append_array(loot.roll_class(_loot_rng,"boss" if boss else "champion",level,primary_))
		var marked := false
		for item in drops:
			# The objective slot carries the most notable reward: a unique if any, else the first item.
			var notable: bool=not marked and (item.quality=="unique" or item==drops[drops.size()-1] or not _has_unique(drops))
			if notable:marked=true
			_publish_item(item,e.position,true,notable)
		return
	# Early guaranteed pieces keep the first minute from being empty-handed.
	var forced_slots := ["weapon","body","hands","feet"]
	var thresholds := [6,35,90,160]
	if _guaranteed_drops<thresholds.size() and kills>=thresholds[_guaranteed_drops]:
		if items.size()<MAX_GROUND_ITEMS and inventory.size()<MAX_INVENTORY:
			_publish_item(loot.roll_item(_loot_rng,level,"magic",forced_slots[_guaranteed_drops]),e.position,false)
		_guaranteed_drops+=1
		return
	for item in loot.roll_class(_loot_rng,"normal",level,primary_):
		if items.size()>=MAX_GROUND_ITEMS or inventory.size()>=MAX_INVENTORY:
			metrics.overflow_items=int(metrics.get("overflow_items",0))+1;continue
		_publish_item(item,e.position,false)

## The run ends with the boss: gear still lying on the ground is gathered, not lost.
func _sweep_ground_items() -> void:
	var left: Array[Dictionary]=[]
	for item in items:
		if inventory.size()<MAX_INVENTORY:
			item.collected=true;inventory.append(item);metrics.picked_items+=1
			_emit("item_pickup",hero.position,{"item":item.duplicate(true),"swept":true})
		else:left.append(item)
	items=left

func _has_unique(drops: Array[Dictionary]) -> bool:
	for item in drops:
		if item.quality=="unique":return true
	return false

func _publish_item(item: Dictionary,point: Vector2,direct: bool,boss_reward: bool=false) -> void:
	_item_sequence+=1;item.uid=_item_sequence;item.position=point;item.collected=direct;item.drop_tick=tick
	item.objective_reward=boss_reward;metrics.dropped_items+=1
	_emit("item_drop",point,{"item":item.duplicate(true)})
	if direct:
		if inventory.size()<MAX_INVENTORY or (boss_reward and inventory.size()<MAX_INVENTORY+1):
			inventory.append(item);metrics.picked_items+=1
			if boss_reward:_elite_reward_uid=item.uid
			_emit("item_pickup",hero.position,{"item":item.duplicate(true)})
		else:
			# A full bag defers up to four rewards to the stash; anything beyond is lost and counted.
			if pending_rewards.size()<MAX_PENDING_REWARDS:
				pending_rewards.append(item)
				_emit("reward_pending",hero.position,{"item":item.duplicate(true)})
			else:metrics.overflow_items=int(metrics.get("overflow_items",0))+1
	else:items.append(item)

func _skill_with(id_: String,gear: Dictionary) -> Dictionary:
	var value: Dictionary=super._skill_with(id_,gear)
	if value.is_empty():return value
	var effect: Dictionary=value.effects
	var extra_pierce := int(gear.get("pierce",0))
	effect.pierce=mini(8,int(effect.pierce)+extra_pierce)
	effect.hit_budget=mini(128,int(effect.hit_budget)+extra_pierce*maxi(1,int(effect.projectiles)))
	if id_ in ["chapter1.skill.ember","chapter1.skill.arc"] and int(effect.radius_cm)>0:effect.radius_cm=mini(1200 if id_=="chapter1.skill.arc" else 650,int(effect.radius_cm)+int(gear.get("radius_cm",0)))
	if id_=="chapter1.skill.ember":
		effect.damage_raw=int(effect.damage_raw)*(10000+int(gear.get("fire_damage_bps",0)))/10000
		if gear.get("fire_burst",0)>0:
			effect.death_burst=1;effect.proc_depth=1;effect.radius_cm=maxi(200,int(effect.radius_cm));effect.hit_budget=maxi(32,int(effect.hit_budget))
	elif id_=="chapter1.skill.frost":
		effect.slow_bps=mini(8500,int(effect.slow_bps)+int(gear.get("slow_bps",0)))
		if gear.get("frost_threshold",0)>0:
			effect.freeze_stacks=maxi(2,int(effect.freeze_stacks)-1) if effect.freeze_stacks>0 else 2
			effect.shatter_count=mini(16,maxi(2,int(effect.shatter_count)))
			effect.hit_budget=maxi(12,int(effect.hit_budget))
	elif id_=="chapter1.skill.arc":
		effect.branches=mini(3,int(effect.branches)+int(gear.get("arc_branches",0)))
		if gear.get("arc_branches",0)>0:effect.hit_budget=mini(128,maxi(int(effect.hit_budget),int(effect.branches)*int(effect.chain_targets)))
		effect.damage_raw=int(effect.damage_raw)*(10000+int(gear.get("arc_damage_bps",0)))/10000
	# The permanent tree acts on the witch's signature skill only, after gear and before the role bonus.
	if _build_active and id_==_primary_id and not _build_skill.is_empty():_apply_build_skill(effect)
	_apply_role_tuning(id_,value)
	return value

## Primary skill: its stage bonus (add, then mul_bps, then cooldown_bps), clamped to the catalog limits.
## Any other skill: the secondary damping. Runs after gear so gear cannot escape it.
func _apply_role_tuning(id_: String,value: Dictionary) -> void:
	var effect: Dictionary=value.effects
	if id_==_primary_id:
		var table: Dictionary=tuning.primary_bonus.get(id_,{})
		if table.is_empty():return
		var bonus: Dictionary=table.get("evo" if value.evolved else "r%d"%int(value.rank),{})
		for stat in bonus.get("add",{}):effect[stat]=_limited(stat,int(effect[stat])+int(bonus.add[stat]))
		for stat in bonus.get("mul_bps",{}):effect[stat]=_limited(stat,int(effect[stat])*int(bonus.mul_bps[stat])/10000)
		if bonus.has("cooldown_bps"):effect.cooldown_ticks=maxi(12,int(effect.cooldown_ticks)*int(bonus.cooldown_bps)/10000)
	elif _secondary_active:
		var s: Dictionary=tuning.secondary
		effect.damage_raw=_limited("damage_raw",int(effect.damage_raw)*int(s.damage_bps)/10000)
		effect.hit_budget=_limited("hit_budget",int(effect.hit_budget)*int(s.hit_budget_bps)/10000)
		effect.cooldown_ticks=maxi(12,int(effect.cooldown_ticks)*int(s.cooldown_bps)/10000)
		effect.chain_targets=mini(int(effect.chain_targets),int(s.max_chain_targets))
		effect.branches=mini(int(effect.branches),int(s.max_branches))
	# Whatever the data says, no role may push a cast under 12 ticks.
	effect.cooldown_ticks=maxi(12,int(effect.cooldown_ticks))

func _limited(stat: String,amount: int) -> int:
	return clampi(amount,int(GrowthCatalog.LIMITS[stat][0]),int(GrowthCatalog.LIMITS[stat][1]))

## In a run with a build the level an item needs is measured against max(permanent level, grace level).
func can_equip(item: Dictionary) -> bool:
	var level := int(growth.snapshot().level)
	if _build_active:level=maxi(level,int(_build.character_level))
	return int(item.get("required_level",1))<=level

func import_starting_gear(gear: Array[Dictionary]) -> bool:
	if mode!="playing" or tick!=0 or not inventory.is_empty() or gear.size()>EQUIP_SLOTS.size():return false
	var slots := {}
	for item in gear:
		if not loot.validate(_bare_item(item)).is_empty() or not item.has("storage_id"):return false
		var slot: String=item.get("equip_slot",item.slot)
		if not slot in EQUIP_SLOTS or slots.has(slot) or (item.slot=="ring")!=(slot in ["ring","ring2"]) or (item.slot!="ring" and slot!=item.slot):return false
		slots[slot]=true
	for source in gear:
		var item: Dictionary=source.duplicate(true);_item_sequence+=1;item.uid=_item_sequence;item.collected=true;item.drop_tick=0;item.position=hero.position
		var slot: String=item.get("equip_slot",item.slot);item.erase("equip_slot")
		# Gear chosen in town is worn even if this run's level is still below its requirement.
		inventory.append(item);equipped[slot]=item.uid
	_recompute_gear()
	# Full health only at a fresh run boundary. Mid-run equipment never heals.
	hero.hp_raw=hero.max_hp_raw
	return true

## Off-run sheet: a throwaway core is started (no tick runs), given the build and the worn gear, and read.
## `gear` items are the profile's storage items (storage_id, optional equip_slot) as import_starting_gear takes them.
## Returns stat_sheet(), or {"error": reason} when the build, start or gear is refused.
static func sheet_for(primary: String,build: Dictionary,gear: Array[Dictionary]) -> Dictionary:
	var core := new()
	if not build.is_empty() and not core.configure_build(build):return {"error":"build: "+str(core.errors)}
	if not core.start(1,primary):return {"error":"start: "+str(core.errors)}
	if not gear.is_empty() and not core.import_starting_gear(gear):return {"error":"gear refused"}
	return core.stat_sheet()

## The item as the loot grammar defines it, without run or storage bookkeeping.
func _bare_item(item: Dictionary) -> Dictionary:
	var clean: Dictionary={}
	for key in ["grammar","base_id","name","slot","stats","quality","item_level","affixes","description","required_level","legendary_id"]:
		if item.has(key):clean[key]=item[key]
	return clean

func _drop_potion(point: Vector2) -> void:
	if potion_pickups.size()>=16:return
	_potion_sequence+=1;potion_pickups.append({"uid":_potion_sequence,"position":point,"tick":tick})
	_emit("potion_drop",point,{})

func drink_potion() -> bool:
	if mode!="playing" or potions<=0 or tick<_next_potion or hero.hp_raw>=hero.max_hp_raw:return false
	potions-=1;_next_potion=tick+int(tuning.potion.cooldown_ticks)
	var amount: int=maxi(1,int(hero.max_hp_raw)*int(tuning.potion.heal_bps)/10000)
	hero.hp_raw=mini(int(hero.max_hp_raw),int(hero.hp_raw)+amount)
	_emit("potion_used",hero.position,{"amount_raw":amount,"remaining":potions})
	return true

func activate_ritual(id_: String) -> bool:
	if mode!="playing" or not rituals.has(id_) or rituals[id_].state!="ready":return false
	for def in RITUALS:
		if def.id==id_ and def.zone==zone and hero.position.distance_squared_to(def.position)<=3.0*3.0:
			rituals[id_].state="active";rituals[id_].started_tick=tick;_record("ritual_started:"+id_)
			_emit("ritual_started",def.position,{"id":id_,"name":def.name});return true
	return false

func _step_rituals() -> void:
	for def in RITUALS:
		var state: Dictionary=rituals[def.id]
		if state.state!="active":continue
		if def.zone!=zone:state.state="abandoned";continue
		var close_: bool=hero.position.distance_squared_to(def.position)<5.0*5.0
		if def.kind=="hold" and close_:state.progress+=1
		if close_ and tick>=_ritual_spawn_tick:
			_ritual_spawn_tick=tick+3*HZ
			for i in 8:
				if alive_count()<int(tuning.alive_cap):_spawn("walker" if i<6 else "charger",_spawn_point(7,9))
		var target := 25*HZ if def.kind=="hold" else 60
		if state.progress>=target:
			state.state="completed";state.completed_tick=tick;_record("ritual_completed:"+def.id)
			_publish_item(loot.roll_item(_loot_rng,ZONE_LEVELS[zone],"rare"),def.position,true)
			_drop_potion(def.position);_emit("ritual_completed",def.position,{"id":def.id,"name":def.name})

func _step_chapter_hazards() -> void:
	if _champion_id<=0 or not enemies.has(_champion_id) or zone!=2:return
	var boss: Dictionary=enemies[_champion_id]
	if boss.hp_raw<=0:return
	if _boss_phase==1 and int(boss.hp_raw)*2<=int(boss.max_hp_raw):
		_boss_phase=2;boss.definition.recover=65;_next_ward=mini(_next_ward,tick+HZ)
		_record("boss_phase2");_emit("boss_phase",boss.position,{"phase":2})
	if tick>=_next_ward:
		# The floor strike must not burst within ward_gap_ticks of the end of the boss's own wind-up
		# (two big hits one after another); if it would, it is put off by that many ticks.
		var gap: int=int(tuning.heavy_hit.ward_gap_ticks)
		if gap>0 and boss.state=="windup" and absi(tick+72-int(boss.state_until))<gap:
			_next_ward=tick+gap
		else:
			_next_ward=tick+(4*HZ if _boss_phase==1 else 3*HZ)
			var centers: Array[Vector2]=[hero.position]
			if _boss_phase==2:
				centers.append(_clamp_point(hero.position+hero.direction.rotated(PI*.5)*3.8))
				centers.append(_clamp_point(hero.position-hero.direction.rotated(PI*.5)*3.8))
			for center in centers:
				_hazard_sequence+=1
				chapter_hazards.append({"uid":_hazard_sequence,"position":center,"radius":1.8,"started":tick,"expires":tick+72,"damage_raw":int(tuning.boss_ward.damage)*UNIT})
				_emit("chapter_warning",center,{"radius":1.8,"duration_ticks":72})
	var live: Array[Dictionary]=[]
	for hazard in chapter_hazards:
		if tick<hazard.expires:live.append(hazard);continue
		if hero.position.distance_squared_to(hazard.position)<=pow(float(hazard.radius),2):_hero_damage(hazard.damage_raw,hazard.position)
		_last_ward_burst=tick
		_emit("chapter_burst",hazard.position,{"radius":hazard.radius})
	chapter_hazards=live

func step(move: Vector2=Vector2.ZERO) -> void:
	if mode!="playing":return
	super.step(move)
	if mode!="playing":return
	_step_chapter_hazards()
	if mode!="playing":return
	_step_fields()
	if mode!="playing":return
	_step_rituals()
	var live: Array[Dictionary]=[]
	for pickup in potion_pickups:
		if potions<int(tuning.potion.carry_max) and hero.position.distance_squared_to(pickup.position)<1.6*1.6:
			potions+=1;_emit("potion_pickup",pickup.position,{"remaining":potions})
		elif tick-pickup.tick<180*HZ:live.append(pickup)
	potion_pickups=live

func objective() -> Dictionary:
	var title: String=ZONE_NAMES[zone]
	var seal_kills: int=int(tuning.seal_kills[zone])
	var text := "봉인 주변 처치 %d / %d"%[mini(zone_kills,seal_kills),seal_kills]
	var destination: Vector2=ZONES[zone]
	if not _zone_entered:text="열린 동쪽 회랑을 따라 다음 마당으로 이동"
	elif _champion_id>0 and enemies.has(_champion_id):
		var e: Dictionary=enemies[_champion_id];title=e.get("title",title);text="%d / %d"%[ceili(float(e.hp_raw)/UNIT),ceili(float(e.max_hp_raw)/UNIT)]
	return {"zone":zone,"title":title,"text":text,"destination":destination,"boss_phase":_boss_phase,"entered":_zone_entered}

func snapshot() -> Dictionary:
	var result: Dictionary=super.snapshot()
	result.chapter={"zone":zone,"zone_kills":zone_kills,"seals":seals.duplicate(true),"potions":potions,"pending_rewards":pending_rewards.duplicate(true),"rituals":rituals.duplicate(true),"history":history.duplicate(true),"boss_phase":_boss_phase,"hazards":chapter_hazards.duplicate(true)}
	result.world_uniques36=_world_uniques36.keys()
	result.world_uniques36.sort()
	# Build keys exist only in a run that was given a build; without one the snapshot is the old one.
	if _build_active:
		var pairs: Array=[];var ids: Array=_build.ranks.keys();ids.sort()
		for id_ in ids:pairs.append([id_,int(_build.ranks[id_])])
		result.build={"character_id":_build.character_id,"tree_id":_build.tree_id,"tree_revision":int(_build.tree_revision),"ranks":pairs,"character_level":int(_build.character_level),"character_xp":int(_build.character_xp)}
		result.progress=_progress.duplicate(true)
		if not _field_rule.is_empty():result.fields=_fields.duplicate(true)
	return result


func _damage_enemy(id_: int,context: Dictionary,depth: int) -> void:
	if not _terminal_mode.is_empty() or not enemies.has(id_) or int(context.remaining_hits)<=0:return
	var e: Dictionary=enemies[id_]
	if e.hp_raw<=0 or e.generation!=_epoch:return
	if context.skill_id=="chapter1.skill.arc":
		if id_ in context.hit_ids:return
		context.hit_ids.append(id_)
	context.remaining_hits-=1
	var effect: Dictionary=context.effects
	var was_frozen: bool=tick<int(e.frozen_until)
	var damage: int=effect.damage_raw
	var evolved_cold: bool=context.skill_id=="chapter1.skill.frost" and bool(context.evolved)
	if evolved_cold and depth>0:
		var divisor := 4 if e.elite else 2
		damage=maxi(1,int((damage+divisor-1)/divisor))
	# R1: the tree's guardian bonus on the signature skill, before mark resonance.
	if _elite_bps>0 and e.elite and context.skill_id==_primary_id:damage=damage*(10000+_elite_bps)/10000
	# Mark resonance: a primary hit on an enemy that a secondary skill marked deals mark_bps more per live mark.
	var mark_bps := int(tuning.marks.mark_bps)
	var assisting: Array[int]=[]
	var unmarked := damage
	var hp_before := int(e.hp_raw)
	if mark_bps>0 and context.skill_id==_primary_id:
		for slot in _mark_owners.size():
			if tick<int(e.get(MARK_KEYS[slot],0)):assisting.append(slot)
		if not assisting.is_empty():damage=damage*(10000+mark_bps*assisting.size())/10000
	var result: Dictionary=Resolver.damage(damage,int(e.hp_raw))
	e.hp_raw=int(result.hp_after_raw);metrics.damage_raw+=int(result.total_raw)
	metrics.hits[context.skill_id]=int(metrics.hits.get(context.skill_id,0))+1
	if context.skill_id=="chapter1.skill.frost":
		e.slow_until=tick+100;e.slow_bps=int(effect.slow_bps)
		if int(effect.freeze_stacks)>0:
			e.freeze_stacks+=1;e.freeze_expires=tick+180
			if int(e.freeze_stacks)>=int(effect.freeze_stacks):
				e.frozen_until=tick+(12 if e.elite else 75);e.freeze_stacks=0
	var cold_death: bool=evolved_cold and e.hp_raw<=0 and depth==0 and int(effect.proc_depth)>0
	var shatter: bool=int(effect.shatter_count)>0 and (was_frozen or cold_death)
	var hit_details := {"target_id":id_,"skill_id":context.skill_id,"damage_raw":int(result.total_raw),"frozen":tick<int(e.frozen_until),"shatter":shatter,
		"radius_cm":int(effect.radius_cm),"blast_radius_cm":int(effect.radius_cm)if context.skill_id=="chapter1.skill.ember"else 0,"cast_uid":context.uid,"evolved":context.evolved}
	if not assisting.is_empty():
		# The extra damage (HP really removed beyond the unmarked hit) is credited to the marking skills, remainder to the first.
		var dealt: int=mini(int(result.total_raw),hp_before)
		var extra: int=maxi(0,dealt-mini(dealt,unmarked))
		var owners: Array[String]=[]
		for slot in assisting:owners.append(_mark_owners[slot])
		if extra>0:
			if not metrics.has("assist_raw"):metrics.assist_raw={}
			for i in owners.size():
				var share: int=extra/owners.size()+(extra%owners.size() if i==0 else 0)
				metrics.assist_raw[owners[i]]=int(metrics.assist_raw.get(owners[i],0))+share
		hit_details.assist_raw=extra;hit_details.assist_skill_ids=owners
	_emit("hit",e.position,hit_details)
	if mark_bps>0 and context.skill_id!=_primary_id and e.hp_raw>0:
		var owner_slot: int=_mark_owners.find(context.skill_id)
		if owner_slot>=0:e[MARK_KEYS[owner_slot]]=tick+int(tuning.marks.mark_ticks)
	# Shock is separate from cold: no freeze stacks, cold tint or shatter credit.
	# Primary chain contacts only; secondary death explosions cannot restun.
	if e.hp_raw>0 and context.skill_id=="chapter1.skill.arc" and depth==0 and tick>=int(e.get("shock_ready_tick",0)):
		var duration: int=ARC_ELITE_STUN_TICKS36 if e.elite else ARC_STUN_TICKS36
		e.stunned_until=tick+duration
		e.shock_ready_tick=tick+(ARC_ELITE_IMMUNITY36 if e.elite else ARC_STUN_IMMUNITY36)
		_emit("stun",e.position,{"target_id":id_,"skill_id":context.skill_id,"until_tick":e.stunned_until,"duration_ticks":duration,"elite":e.elite})
	if e.hp_raw>0:return
	e.state="dead";_alive-=1;e.dead_tick=tick;e.telegraph={};kills+=1
	_emit("death",e.position,{"target_id":id_,"kind":e.kind,"elite":e.elite,"skill_id":context.skill_id})
	_drop_orb(e.position,int(_enemy_definition(e).xp));_maybe_drop_item(e)
	# The run ends with the final boss; sparks over its corpse would only be drawn after the win.
	if not e.get("chapter_boss",false):_queue_children(e,context)
	if depth<int(effect.proc_depth)and int(effect.death_burst)>0:
		var burst_radius := 3.0 if context.skill_id=="chapter1.skill.arc"else maxf(1.5,float(effect.radius_cm)/100.0)
		_emit("explosion",e.position,{"skill_id":context.skill_id,"radius_cm":int(burst_radius*100),"cast_uid":context.uid,"evolved":context.evolved,"proc":true})
		_area_hit(e.position,burst_radius,context,id_,depth+1)
	if shatter and depth==0:
		# R3: the tree widens the shatter of the signature skill (350 cm without it).
		var shatter_cm := 350+(_shatter_extra_cm if context.skill_id==_primary_id else 0)
		_emit("shatter",e.position,{"skill_id":context.skill_id,"radius_cm":shatter_cm,"count":int(effect.shatter_count),"cast_uid":context.uid,"evolved":context.evolved,
			"cause":"cold_death"if cold_death and not was_frozen else"frozen","normal_damage_divisor":2 if evolved_cold else 1,"elite_damage_divisor":4 if evolved_cold else 1})
		var remaining: int=effect.shatter_count
		for other in _near(e.position,float(shatter_cm)/100.0):
			if other==id_ or remaining<=0:continue
			_damage_enemy(other,context,1);remaining-=1
	if e.elite:_on_elite_defeated(e)
