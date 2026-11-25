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
const RunSpells = preload("res://chapter1/core/run_spells.gd")
const ElementKit = preload("res://chapter1/core/element_kit.gd")
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
## D23 T9: the account's count of runs to the final boss without a legendary or unique, put in by the app before start() (the core knows no save).
var drop_dry_runs := 0
var _pity_armed := false
var _pity_fired := false
## D23 T8: the luck of this run, taken once at the first tick (worn sum cut at loot.luck_cap_bps()), and what was worn then.
var _luck_taken := false
var _run_luck_bps := 0
var _run_luck_worn := 0
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
## Kills that break each zone's seal: tuning.seal_kills (chapter1/data/combat_tuning.json).
const RITUALS := [
	{"id":"vigil","position":Vector2(8,-7),"zone":0,"kind":"hold"},
	{"id":"reliquary","position":Vector2(40,6),"zone":1,"kind":"kill"}
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
## D-boss-finale (tuning.boss_finale, BF1~BF9). Everything below stays at rest, and out of snapshot(), while the block is absent or not enabled.
## _bf_state: "" (boss not here yet) | "entrance" | "phase" | "break" | "done". The boss is out of play (_shield_id) in an entrance and in a break.
var _bf_on := false
var _bf: Dictionary = {}
var _bf_state := ""
var _bf_phase := 0
var _bf_break := -1
var _bf_until := 0
var _bf_to := Vector2.ZERO
var _bf_land_started := false
var _bf_next_adds := 0
var _bf_next_escort := 0
var _bf_next_storm := 0
var _bf_storms := 0
var _bf_phase_attacks := 0
var _bf_chip := 0
var _bf_break_chip := 0
var _bf_break_kills := 0
var _hazard_sequence := 0
var _potion_sequence := 0
var _zone_entered := false
var _normal_drop_sequence := 0
var _ritual_spawn_tick := 0
## The default tuning document is read once and shared by every run in the process.
static var _shared_tuning: Dictionary = {}
var _secondary_active := false
## In-run spell composition (chapter1/data/run_spells.json). The document is read and validated once per process and shared;
## `spells` (combat_core) is the document only while it says "enabled": true, otherwise empty and every rule stays off.
## set_run_spells() parks a document for the next start() (tests, measurement); a rejected one changes nothing.
static var _shared_spells: Dictionary = {}
static var _shared_spells_loaded := false
var _pending_spells: Dictionary = {}
var _spell_owner_skill: Dictionary = {}
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
## Run rhythm (D11 A). All of it stays at its zero value while tuning.rhythm.enabled is false, and only an enabled
## run puts it into snapshot().
var _rhythm_on := false
## Boon cadence, tools and grades (D13 K3a/K3b-1): tuning.grace.enabled. Off = nothing below exists in the run or its snapshot.
var _grace_on := false
var _grace_waited := 0
var _beat_index := -1
var _beat_tick := 0
var _wave_index := -1
## D22 R1-B threat keys (all optional; absent = the old rules, no extra random draw, no snapshot key).
## The wave whose squad was already placed, the heading of the last wave head, the head-size roll per beat (jitter), and the
## ranged bodies still allowed in the batch being spawned (-1 = no cap in force).
var _squad_wave := -1
var _wave_heading := 0.0
var _crest_jitter: Dictionary = {}
var _threat_on := false
var _ranged_left := -1
var _in_lull := false
var _taste_done := false
var _rest_until := 0
var _spawn_hp_bps := 10000
var _trial_phase := ""
var _trial_until := 0
var _trial_clear_until := 0
var _trial_center := Vector2.ZERO
## D19 C1-e: ordinary kills of the last `window_ticks` that no burst has used yet, as {tick, xp, pts, pos}. Exists only while
## rhythm.kill_burst is present (then the snapshot has rhythm.kill_burst and metrics.kill_burst; without it neither key).
var _kb_on := false
var _kb_list: Array = []
## D19 C1-f: grace.pace. The level the clock was last reset at, the tick of that reset, and the carried remainder (ten-thousandths)
## of the multiplied experience. Present in the snapshot as "pace" only while grace.pace is configured.
var _pace_on := false
var _pace_level := 1
var _pace_since := 0
var _pace_carry := 0
## Run opening (D15 B, rhythm.opening): the first minute of the first beat as steps (look, one, two, pack, around). It exists
## only while rhythm.enabled and rhythm.opening.enabled are both true; otherwise every value below stays at rest and the
## snapshot has no opening key. `opening_first_visit` is set by the app before start() (first_visit_only steps are skipped
## when it is false); the app has no play counter yet, so a normal run is always the long opening.
var opening_first_visit := true
var _opening_on := false
var _op_active := false
var _op_done := false
var _op_list: Array = []
var _op_step := -1
var _op_step_start := 0
var _op_step_kills := 0
var _op_step_spawned := 0
var _op_crest_done := false
var _op_prev_angle := 0.0
var _op_heading := Vector2.ZERO
var _op_total_kills := 0

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

## Park a run_spells document for the next start() (before start()). It is validated like the file; an enabled one
## switches the composition on for the runs that follow, a disabled one switches it off. A rejected one changes nothing.
func set_run_spells(candidate: Dictionary) -> bool:
	var inputs := _spell_inputs()
	if inputs.is_empty():return false
	var loader = RunSpells.new()
	if not loader.replace_document(candidate,SKILL_IDS,inputs.owners,inputs.starts):
		errors.assign(loader.errors);return false
	_pending_spells=loader.snapshot()
	return true

## {owners: {character id: signature skill id}, starts: {skill id: catalog rank-1 effect}} for the validator; {} when unreadable.
func _spell_inputs() -> Dictionary:
	if not _growth_data():errors.assign(["Growth data could not be read"]);return {}
	if _catalog.snapshot().is_empty() and not _catalog.load_file("res://chapter1/data/growth_quality36.json"):
		errors.assign(_catalog.errors);return {}
	var owners := {}
	for entry in _shared_progression.characters:owners[String(entry.id)]=String(entry.signature_skill_id)
	var starts := {}
	for skill in _catalog.snapshot().skills:starts[String(skill.id)]=skill.ranks[0].duplicate(true)
	return {"owners":owners,"starts":starts}

## Decide whether this run has the spell composition: the parked document, else the shipped file (read once; a missing file
## means off). Everything the composition adds hangs on `spells` being non-empty.
func _prepare_spells() -> bool:
	spells={};_skill_ids=SKILL_IDS.duplicate();_spell_owner_skill={}
	var document: Dictionary=_pending_spells
	if document.is_empty():
		if not _shared_spells_loaded:
			if FileAccess.file_exists(RunSpells.DEFAULT_PATH):
				var inputs := _spell_inputs()
				var loader = RunSpells.new()
				if inputs.is_empty() or not loader.load_file(RunSpells.DEFAULT_PATH,SKILL_IDS,inputs.owners,inputs.starts):
					if not inputs.is_empty():errors.assign(loader.errors)
					push_error("Run spells failed to load: "+str(errors));return false
				_shared_spells=loader.snapshot()
			_shared_spells_loaded=true
		document=_shared_spells
	if document.is_empty() or not bool(document.enabled):return true
	if not _growth_data():return false
	spells=document.duplicate(true)
	for entry in _shared_progression.characters:_spell_owner_skill[String(entry.id)]=String(entry.signature_skill_id)
	for id_ in spells.spells:
		if not id_ in _skill_ids:_skill_ids.append(id_)
	return true

func start(seed_: int=1, primary: String="chapter1.skill.ember") -> bool:
	# A build belongs to one witch and her signature skill; any other start is refused before anything changes.
	if not _pending_build.is_empty() and _build_signature(_pending_build)!=primary:
		errors.assign(["Build witch and starting skill differ"]);return false
	if tuning.is_empty():
		if _shared_tuning.is_empty():
			var loader = Tuning.new()
			if not loader.load_file(Tuning.DEFAULT_PATH,SKILL_IDS,MAX_ALIVE,MAX_PROJECTILES-MAX_HOSTILE_PROJECTILES):
				errors.assign(loader.errors);push_error("Combat tuning failed to load: "+str(loader.errors));return false
			_shared_tuning=loader.snapshot()
		_install_tuning(_shared_tuning)
	if not _prepare_spells():return false
	if not _prepare_kit(primary):return false
	if not _prepare_descent():return false
	if not _prepare_elites():return false
	if not _prepare_loot_flow():return false
	_activate_build()
	_world_uniques36.clear()
	zone=0;zone_kills=0;potions=int(tuning.potion.start);_next_potion=0;_champion_id=-1;_boss_phase=0;_next_ward=0
	_hazard_sequence=0;_potion_sequence=0;_zone_entered=true;_normal_drop_sequence=0;_ritual_spawn_tick=0
	seals.clear();history.clear();potion_pickups.clear();pending_rewards.clear();chapter_hazards.clear();rituals.clear()
	if _build_potions>0:potions=mini(int(tuning.potion.carry_max),potions+_build_potions)
	_rhythm_on=tuning.has("rhythm") and bool(tuning.rhythm.enabled)
	_bf_on=tuning.has("boss_finale") and bool(tuning.boss_finale.enabled);_bf=tuning.boss_finale if _bf_on else {};_bf_reset()
	_beat_index=-1;_beat_tick=0;_wave_index=-1;_in_lull=false;_taste_done=false;_rest_until=0;_spawn_hp_bps=10000
	_squad_wave=-1;_wave_heading=0.0;_crest_jitter={};_threat_on=false;_ranged_left=-1
	if _rhythm_on:
		for beat in tuning.rhythm.beats:
			if beat.wave is Dictionary and (beat.wave.has("squad") or int(beat.wave.crest.get("count_jitter_bps",0))>0):_threat_on=true
	_kb_on=_rhythm_on and tuning.rhythm.has("kill_burst");_kb_list.clear()
	_trial_phase="";_trial_until=0;_trial_clear_until=0;_trial_center=Vector2.ZERO
	_opening_on=_rhythm_on and tuning.rhythm.has("opening") and bool(tuning.rhythm.opening.enabled)
	_op_active=false;_op_done=false;_op_list.clear();_op_step=-1;_op_step_start=0;_op_step_kills=0;_op_step_spawned=0;_op_crest_done=false
	_op_prev_angle=0.0;_op_heading=Vector2.ZERO;_op_total_kills=0;_spawn_tags={}
	_elites_reset(seed_)
	_d_seed=seed_ ^ DESCENT_SEED_MASK
	for i in 3:seals.append({"kills":0,"champion_spawned":false,"cleared":false})
	for def in RITUALS:rituals[def.id]={"state":"ready","progress":0,"started_tick":-1,"completed_tick":-1}
	if not super.start(seed_,primary):return false
	_descent_reset()
	_elites_metrics()
	_mark_owners.clear()
	_last_ward_burst=-100000
	for id_ in SKILL_IDS:
		if id_!=primary and _mark_owners.size()<MARK_KEYS.size():_mark_owners.append(id_)
	var doc: Dictionary=_catalog.snapshot();doc.xp_thresholds=tuning.xp_thresholds.duplicate()
	if not growth.configure(doc,primary,seed_ ^ 0x47524f57):errors.assign(growth.errors);return false
	# D19 C1-a: a run with the rhythm on may have a level table of its own (its length is the level cap).
	if _rhythm_on and tuning.rhythm.has("xp_thresholds") and not growth.set_thresholds(tuning.rhythm.xp_thresholds):errors.assign(growth.errors);return false
	# The spell composition (if on) comes before the build's growth options: it takes the start rank out of play.
	if not spells.is_empty():
		if not growth.set_spells(spells,_spell_owner_skill):errors.assign(growth.errors);return false
		metrics.detonate={"count":0,"extra_raw":0,"pairs":{}}
		# What the rings and the aim rules did (G5-3.1): ring casts and hits, ring kills, staggers and the attacks they cut, the
		# ring's freezes and stuns, basic hits that found a controlled enemy (vs_cc) and what that added, detonations that
		# strengthened a ring (i2), and basic casts aimed first at a far shooter (i0) with the kills of that kind they made.
		metrics.ward={"casts":0,"hits":0,"kills":0,"staggers":0,"cuts":0,"freezes":0,"stuns":0,"vs_cc_hits":0,"vs_cc_extra_raw":0,"i2_hits":0,"i2_extra_raw":0,"i0_casts":0,"i0_kills":0}
	if _kit_on and not _kit_install():return false
	if _build_active:
		if _build_max_hp>0:hero.max_hp_raw=120*UNIT+_build_max_hp*UNIT;hero.hp_raw=hero.max_hp_raw
		if not growth.set_options(_build_growth):errors.assign(growth.errors);return false
		if not _field_rule.is_empty():_next_field=int(_field_rule.interval_ticks)
	_grace_on=tuning.has("grace") and bool(tuning.grace.enabled);_grace_waited=0
	_pace_on=_grace_on and tuning.grace.has("pace");_pace_level=1;_pace_since=0;_pace_carry=0
	if _kb_on:metrics.kill_burst={"bursts":0,"kills":0,"xp":0,"descent_points":0}
	if _grace_on and not growth.set_grace(tuning.grace):errors.assign(growth.errors);return false
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
	return String(Progression.character_entry(_kit_tables().doc,String(build.get("character_id",""))).get("signature_skill_id",""))

## A cleaned copy of the build (integers only), or {"error": reason}. The same skill_tree.gd rules the profile
## uses decide whether the ranks are legal. The core does not see the witch's first-kill receipts, so it grants
## the most points she could hold at this level.
func _normalize_build(build: Dictionary) -> Dictionary:
	if build.is_empty():return {"error":"Empty build dictionary; use clear_build()"}
	if not _growth_data():return {"error":"Growth data could not be read"}
	if build.size()!=BUILD_KEYS.size():return {"error":"Build keys do not match"}
	for key in BUILD_KEYS:
		if not build.has(key):return {"error":"Build key missing: "+key}
	var tables := _kit_tables()
	var doc: Dictionary=tables.doc
	var known: Dictionary=Progression.character_entry(doc,build.character_id) if build.character_id is String else {}
	if known.is_empty():return {"error":"Unknown character"}
	if not GrowthCatalog.integer(build.character_xp,0,1000000000) or not GrowthCatalog.integer(build.character_level,1,int(doc.level_cap)):return {"error":"Character level or xp out of range"}
	if Progression.level_for_xp(doc,int(build.character_xp))!=int(build.character_level):return {"error":"Character level does not match xp"}
	if not build.tree_id is String or not build.ranks is Dictionary or not GrowthCatalog.integer(build.tree_revision,0,1000000):return {"error":"Tree format error"}
	var ranks := {}
	for node_id in build.ranks:
		if not node_id is String or not SkillTree.integer_(build.ranks[node_id],1,10):return {"error":"Rank format error"}
		ranks[node_id]=int(build.ranks[node_id])
	var clean := {"character_id":build.character_id,"tree_id":build.tree_id,"tree_revision":int(build.tree_revision),"ranks":ranks,"character_level":int(build.character_level),"character_xp":int(build.character_xp)}
	var has_tree: bool=known.get("tree_id")!=null
	if String(build.tree_id).is_empty():
		if has_tree or int(build.tree_revision)!=0 or not ranks.is_empty():return {"error":"Not a build of a witch without a tree"}
		return clean
	if not has_tree or known.tree_id!=build.tree_id or not tables.trees.has(build.tree_id):return {"error":"Not this witch's tree"}
	var tree: Dictionary=tables.trees[build.tree_id]
	if int(build.tree_revision)!=int(tree.revision):return {"error":"Tree revision differs"}
	var bound := (int(build.character_level)-1)*int(doc.points_per_level)
	for reward in doc.first_rewards:bound+=int(doc.first_rewards[reward])
	var problems: Array[String]=SkillTree.legal_ranks(tree,ranks,int(build.character_level),bound)
	if not problems.is_empty():return {"error":"Tree investment rejected: "+problems[0]}
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
	_field_rule={};_fields.clear();_field_uid=0;_next_field=0;_progress={};_build_max_hp=0;_build_reduction_bps=0;_kit_build_cards=[]
	if _pending_build.is_empty():return
	_build=_pending_build.duplicate(true);_build_active=true
	var compiled := {"skill":{},"hero":{},"rules":{}}
	if not String(_build.tree_id).is_empty():
		var tree: Dictionary=_kit_tables().trees[_build.tree_id]
		if ElementKit.is_element_tree(tree):
			var element_build := ElementKit.compile_tree(tree,_build.ranks)
			compiled.rules=element_build.rules;_kit_build_cards=element_build.cards
		else:compiled=SkillTree.compile(tree,_build.ranks)
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
	var total := _seal_total(zone);var n := zone_kills
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
	var details := {"left":growth.rerolls_left()}
	if _grace_on:details.spin=growth.spins()
	_emit("grace_reroll",hero.position,details)
	_drain_growth_events()
	return true

## D13 K3a: take a card out of this run's pool for good (the slot is refilled), or set one aside for the next offer.
## Both need the choice mode and a live offer token; the counts are in grace_tools().
func banish_offer(token: String,card_id: String) -> bool:
	if mode!="choice" or not growth.banish(token,card_id):return false
	_drain_growth_events();return true

func hold_offer(token: String,card_id: String) -> bool:
	if mode!="choice" or not growth.hold(token,card_id):return false
	_drain_growth_events();return true

## The luck parts that raise the grade chances (D13 4.11.3). Nothing calls this yet: the shrine (W5-a), the reward stage (W5-b)
## and the gear (K6) will. Rejected while the grades are off.
func set_grace_luck(shrine_mul_bps: int,reward_grade: int,gear_bps: int) -> bool:
	if not growth.set_grade_luck(shrine_mul_bps,reward_grade,gear_bps):errors.assign(growth.errors);return false
	return true

## Read only, for the choice screen (D13 4.4 (7), 4.11.5). {"enabled":false,...} while grace is off. Draws nothing.
## {enabled, grades_enabled, rerolls_left, banishes_left, holds_left, held_card_id, banished:[id], banish_would_refill:{id:bool},
##  banishable:{id:bool}, final (the standing offer is the last, big one), waiting_until (tick, 0 = not waiting), held_dropped,
##  and with the grades on: spin, has_jackpot, forced_by_pity, odds:{jackpot_bps,rare_bps,shrine_mul_bps,parts,capped},
##  pity:{spins,hard_after,soft_step_bps}, near_bps, luck, offer_cards:{card id: grade fields, same as run_spells_view().offer[id]}}
func grace_tools() -> Dictionary:
	var view: Dictionary=growth.grace_view()
	if not _grace_on:return view
	var wait_until := 0
	if _choice_tick>=0 and int(tuning.grace.min_gap_ticks)>0 and not growth.snapshot().pending_levels.is_empty() and not growth.is_final_level(growth.next_pending_level()):
		wait_until=maxi(0,_choice_tick+int(tuning.grace.min_gap_ticks))
		if tick>=wait_until:wait_until=0
	view.waiting_until=wait_until
	return view

## D13 K3a gap: after a pick the next level waits min_gap_ticks (grace.min_gap_ticks, 0 = off); the last level never waits.
func _grace_ready() -> bool:
	if not _grace_on or int(tuning.grace.min_gap_ticks)<=0 or _choice_tick<0:return true
	var level: int=growth.next_pending_level()
	var until: int=_choice_tick+int(tuning.grace.min_gap_ticks)
	if level<=0 or growth.is_final_level(level) or tick>=until:return true
	if _grace_waited!=level:
		_grace_waited=level;_emit("grace_waiting",hero.position,{"level":level,"until_tick":until})
	return false

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
			# A field's control belongs to no spell of the composition: forget who put the earlier one there.
			if e.has("cc_src"):e.cc_src.erase("slowed")
			if tick<int(e.slow_until):
				e.slow_bps=maxi(int(e.slow_bps),int(f.slow_bps));e.slow_until=maxi(int(e.slow_until),tick+8)
			else:
				e.slow_until=tick+8;e.slow_bps=int(f.slow_bps)
			if freeze_due and threshold>0:
				e.freeze_stacks+=1;e.freeze_expires=tick+180
				if int(e.freeze_stacks)>=threshold:
					e.frozen_until=tick+(12 if e.elite else 75);e.freeze_stacks=0
					if e.has("cc_src"):e.cc_src.erase("frozen")
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
	return int(tuning.rhythm.initial_pack) if _rhythm_on else int(tuning.spawn.get("initial_pack",12))

## The trial keeps the hero inside its circle; everything else is the zone's walls.
func _clamp_hero(point: Vector2) -> Vector2:
	var inside := _clamp_point(point)
	if _trial_phase!="hold":return inside
	var offset := inside-_trial_center
	var radius := float(tuning.rhythm.trial.radius_m)
	if offset.length_squared()>radius*radius:inside=_trial_center+offset.normalized()*radius
	return inside

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
		if _rhythm_on:hp=maxi(1,hp*_spawn_hp_bps/10000)
		# With the rhythm on the beat's hp_bps is the only health rise; the clock factor is not used (D11 A4, 2026-11-19).
		var bps := 0 if _rhythm_on else int(tuning.hp_time_bps_per_s)
		if kind=="walker" and tick<int(rules.opening_until_s)*HZ:hp=int(rules.opening_hp)
		elif bps>0 and tick>=int(tuning.hp_time_from_s)*HZ:hp=maxi(1,hp*(10000+bps*(tick/HZ))/10000)
		definition.hp=hp;definition.damage=int(rules.damage[z]);definition.speed=float(rules.speed[z])
	e.definition=definition
	e.hp_raw=int(definition.hp)*UNIT;e.max_hp_raw=e.hp_raw
	return true

func _enemy_definition(e: Dictionary) -> Dictionary:
	return e.get("definition",ENEMY_DEFS[e.kind])

## normal | elite | champion | boss: the final boss is the zone 2 guardian (chapter_boss), the other seal guardians carry a title_key.
func _enemy_role(e: Dictionary) -> String:
	# A strong body made by _spawn_elite (grade "elite", D13 W4-a) is not a seal guardian: e.elite stays false for it.
	if not e.elite:return "elite" if e.get("grade","")=="elite" else "normal"
	if e.get("chapter_boss",false):return "boss"
	return "champion" if e.has("title_key") else "elite"

func _spawn_wave() -> void:
	if not descent.is_empty():_step_descent()
	if _rhythm_on:_rhythm_tick()
	if not _zone_entered:
		if hero.position.distance_squared_to(ZONES[zone])>18.0*18.0:return
		_zone_entered=true;_record("zone_entered");_emit("zone_entered",ZONES[zone],{"zone":zone})
	if not seals[zone].champion_spawned and zone_kills>=_seal_total(zone) and not _trial_holds_boss():
		if _spawn("elite",_spawn_point(8,9)):
			seals[zone].champion_spawned=true;_champion_id=_enemy_sequence
			var e: Dictionary=enemies[_champion_id]
			e.chapter_boss=zone==2;e.title_key="enemy.champion.%d.name"%zone
			var champion: Dictionary=tuning.champions[zone]
			e.definition.hp=int(champion.hp);e.definition.windup=int(champion.windup)
			e.definition.recover=int(champion.recover);e.definition.damage=int(champion.damage)
			e.definition.xp=int(champion.xp);e.hp_raw=int(e.definition.hp)*UNIT;e.max_hp_raw=e.hp_raw
			_boss_phase=1 if zone==2 else 0;_next_ward=tick+3*HZ
			_record("boss_spawned" if zone==2 else "champion_spawned")
			_emit("chapter_champion",e.position,{"zone":zone,"target_id":e.id})
			if zone==2 and _bf_on:_bf_begin(e)
			if zone==2 and tuning.final_level_on_boss_spawn:_seal_grace()
			if zone==2 and _rhythm_on:_spawn_hp_bps=10000;_emit("beat_started",hero.position,{"id":"boss"})
	# The breath after a descent (from its end tick on): nothing ordinary is sent in (a guardian above is not held back).
	# During the sweep the ordinary spawn goes on at after.sweep_spawn_bps of its pace (D24 1st edition 4.7).
	if tick<_d_pause_until:return
	if not _d_sweep.is_empty() and int(descent.after.sweep_spawn_bps)<=0:return
	# With the finale on, the boss's escorts and adds come from its own phases and breaks (_bf_step), never from spawn.boss_phase.
	if _bf_on and zone==2 and _champion_id>0:return
	if _rhythm_on and not (zone==2 and _champion_id>0):_spawn_rhythm_wave();return
	if tick<_next_spawn:return
	# Frequent weak bodies provide sweepable packs, mixed with bounded specialists.
	var wave: Dictionary=tuning.spawn.zones[zone]
	var amount: int=int(wave.amount)
	for step in tuning.spawn.opening:
		if tick<int(step.until_s)*HZ:amount=int(step.amount);break
	if zone==2 and _champion_id>0:wave=tuning.spawn.boss_phase;amount=int(wave.amount)
	_next_spawn=tick+_descent_spawn_interval(int(wave.interval_ticks))
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

# ---------------------------------------------------------------- run rhythm (D11 A)

## Kills that break a zone's seal. D19 C1-b: a run with the rhythm on may carry its own figures (rhythm.seal_kills); else tuning.seal_kills.
func _seal_total(z: int) -> int:
	if _rhythm_on and tuning.rhythm.has("seal_kills"):return int(tuning.rhythm.seal_kills[z])
	return int(tuning.seal_kills[z])

## Progress of the seal of the current zone, in ten-thousandths (10000 once the guardian has been called).
func _zone_bps() -> int:
	if seals[zone].champion_spawned:return 10000
	return clampi(zone_kills*10000/maxi(1,_seal_total(zone)),0,10000)

## D19 C1-d: the face-value multiplier (ten-thousandths) of the orbs that fall now: the trial's, else the current beat's, else 1x
## (the guardian's and boss's own phase has none). Only a run with the rhythm on has any.
func _xp_bps_now() -> int:
	if not _rhythm_on:return 10000
	var rule: Dictionary
	if _trial_phase=="hold":rule=tuning.rhythm.trial
	elif _beat_index<0 or (zone==2 and _champion_id>0):return 10000
	else:rule=tuning.rhythm.beats[_beat_index]
	return int(rule.get("xp_bps",10000))

## The orb's value is the enemy's experience times the beat's multiplier (integer, rounded down, at least 1). 1x leaves it untouched.
func _drop_orb(position: Vector2,amount: int) -> void:
	var bps := _xp_bps_now()
	if bps!=10000 and amount>0:amount=maxi(1,amount*bps/10000)
	super._drop_orb(position,amount)

## D19 C1-e: an ordinary enemy that the witch's own damage killed (not the descent's sweep). The kills of the last window_ticks that no
## burst has used are kept; when there are min_kills of them they pay once: their experience x xp_bonus_bps as one orb at their
## centre, their descent-gauge points x descent_bonus_bps, event kill_burst. The list is emptied then, so no kill is counted twice.
func _kill_burst_note(details: Dictionary,position: Vector2) -> void:
	if String(details.get("role","normal"))!="normal" or String(details.get("skill_id","")).begins_with("descent."):return
	var target: Variant=enemies.get(int(details.get("target_id",0)))
	if not target is Dictionary:return
	var cfg: Dictionary=tuning.rhythm.kill_burst
	var window := int(cfg.window_ticks)
	var bps := _xp_bps_now()
	var face := int(_enemy_definition(target).xp)
	if bps!=10000 and face>0:face=maxi(1,face*bps/10000)
	var gauge := _kb_gauge_open()
	var kept: Array=[]
	for entry in _kb_list:
		if tick-int(entry.tick)<window:kept.append(entry)
	kept.append({"tick":tick,"xp":face,"pts":_descent_kill_points() if gauge else 0,"pos":position})
	_kb_list=kept
	if _kb_list.size()<int(cfg.min_kills):return
	var count := _kb_list.size();var xp_sum := 0;var point_sum := 0;var centre := Vector2.ZERO
	for entry in _kb_list:
		xp_sum+=int(entry.xp);point_sum+=int(entry.pts);centre+=entry.pos
	centre/=float(count)
	_kb_list=[]
	var bonus := xp_sum*int(cfg.xp_bonus_bps)/10000
	if bonus<=0 and xp_sum>0 and int(cfg.xp_bonus_bps)>0:bonus=1
	if bonus>0:super._drop_orb(centre,bonus)
	var extra := point_sum*int(cfg.descent_bonus_bps)/10000
	if extra>0 and gauge:_descent_add(extra)
	var tally: Dictionary=metrics.kill_burst
	tally.bursts=int(tally.bursts)+1;tally.kills=int(tally.kills)+count;tally.xp=int(tally.xp)+bonus;tally.descent_points=int(tally.descent_points)+extra
	_emit("kill_burst",centre,{"count":count,"xp":bonus,"descent_points":extra})

## The same condition under which the gauge counts events (see _emit): a descent that is on and neither called nor sweeping.
func _kb_gauge_open() -> bool:
	return not descent.is_empty() and not _descent_hold and _d_sweep.is_empty() and metrics.has("descent")

## D19 C1-f: grace.pace. After soft_after_ticks without a level-up, experience gained counts ramp_bps_per_s more per second, up to max_bps
## (all in ten-thousandths of 1x). A level-up (any source) puts the clock back to 1x.
func _pace_bps() -> int:
	var cfg: Dictionary=tuning.grace.pace
	var late := tick-_pace_since-int(cfg.soft_after_ticks)
	if late<=0:return 10000
	return mini(int(cfg.max_bps),10000+late*int(cfg.ramp_bps_per_s)/HZ)

func _pace_sync() -> void:
	var level := growth.current_level()
	if level!=_pace_level:_pace_level=level;_pace_since=tick

func _gain_xp(amount: int) -> int:
	if _pace_on:
		var bps := _pace_bps()
		if bps>10000:
			_pace_carry+=amount*bps
			amount=_pace_carry/10000;_pace_carry%=10000
	var gained := super._gain_xp(amount)
	if _pace_on:_pace_sync()
	return gained

## Beat bookkeeping, once per tick before anything spawns: the beat starts at its zone and seal progress (from_bps),
## or when its time limit has run out (the next beat's rules take over; the seal still opens by kills only).
func _rhythm_tick() -> void:
	var beats: Array=tuning.rhythm.beats
	var bps := _zone_bps()
	var candidate := 0
	for i in beats.size():
		var beat: Dictionary=beats[i]
		if int(beat.zone)<zone or (int(beat.zone)==zone and bps>=int(beat.from_bps)):candidate=i
	var target := _beat_index
	if candidate>_beat_index:target=candidate
	# The time limit only hands over to the next beat of the same zone; the last beat of a zone stays (D11 A4, 2026-11-19).
	# While the opening runs the first beat's clock does not (D15 O-1 rule 3): it starts when the opening ends.
	elif _beat_index>=0 and not _op_active and _beat_index+1<beats.size() and int(beats[_beat_index+1].zone)==int(beats[_beat_index].zone) and tick-_beat_tick>=int(beats[_beat_index].max_ticks):target=_beat_index+1
	if target!=_beat_index:
		if _op_active:_opening_end(false)
		_beat_index=target;_beat_tick=tick;_wave_index=-1;_in_lull=false;_taste_done=false;_squad_wave=-1
		_emit("beat_started",hero.position,{"id":String(beats[target].id)})
		if target==0 and _opening_on and not _op_done:_opening_begin()
	if _op_active:_opening_tick()
	_spawn_hp_bps=_beat_hp_bps(beats,bps)

# ---------------------------------------------------------------- run opening (D15 B)

## The steps this run plays: first_visit_only steps drop out for a returning player.
func _opening_steps() -> Array:
	var list: Array=[]
	for step in tuning.rhythm.opening.steps:
		if bool(step.first_visit_only) and not opening_first_visit:continue
		list.append(step)
	return list

func _opening_limit(step: Dictionary) -> int:
	if not opening_first_visit and step.has("returning_max_ticks"):return int(step.returning_max_ticks)
	return int(step.max_ticks)

func _opening_begin() -> void:
	_op_list=_opening_steps()
	if _op_list.is_empty():_op_done=true;return
	_op_active=true
	_opening_begin_step(0)

## One draw from the spawn stream picks the heading of a step with choices; same / opposite of the previous step draw nothing.
func _opening_begin_step(index: int) -> void:
	var step: Dictionary=_op_list[index]
	_op_step=index;_op_step_start=tick;_op_step_kills=0;_op_step_spawned=0;_op_crest_done=false
	var heading: Dictionary=step.heading
	var angle := _op_prev_angle
	if heading.has("choices_deg"):
		var choices: Array=heading.choices_deg
		angle=deg_to_rad(float(choices[_spawn_rng.randi_range(0,choices.size()-1)]))
	elif heading.get("opposite_of_previous",false):angle=_op_prev_angle+PI
	_op_prev_angle=angle
	_op_heading=Vector2(cos(angle),sin(angle)) if float(heading.arc_deg)<360.0 else Vector2.ZERO
	if int(step.amount)>0:_next_spawn=tick
	_emit("opening_step",hero.position,{"id":String(step.id),"index":index,"heading":_op_heading,"ring_m":[float(step.ring_m[0]),float(step.ring_m[1])]})

func _opening_tick() -> void:
	var step: Dictionary=_op_list[_op_step]
	var need := int(step.kills)
	if tick-_op_step_start<_opening_limit(step) and not (need>0 and _op_step_kills>=need):return
	if _op_step+1<_op_list.size():_opening_begin_step(_op_step+1)
	else:_opening_end(true)

## `finished` false = a later beat took over before the last step ended; the opening is dropped either way.
func _opening_end(finished: bool) -> void:
	_op_active=false;_op_done=true
	if finished:_beat_tick=tick
	_emit("opening_end",hero.position,{"finished":finished,"kills":_op_total_kills})

func _opening_step_now() -> Dictionary:
	return _op_list[_op_step] if _op_active and _op_step>=0 else {}

func _acquire_m() -> float:
	var step := _opening_step_now()
	if not step.is_empty() and step.acquire_m!=null:return float(step.acquire_m)
	return super._acquire_m()

func _orb_pull_m(fallback: float) -> float:
	var step := _opening_step_now()
	if not step.is_empty() and step.orb_pull_m!=null:return float(step.orb_pull_m)
	return fallback

## One body of an opening step: inside the step's fan (or anywhere on the ring when the fan is the full circle), at the step's
## distance, walking at the step's share of the zone's speed. Draws only from _spawn_rng.
func _opening_place(step: Dictionary,heading: Vector2,arc_deg: float) -> bool:
	var kind := _rhythm_mix_kind(step)
	var ring_min := float(step.ring_m[0]);var ring_max := float(step.ring_m[1])
	var base := heading.angle()
	var half := deg_to_rad(arc_deg)*.5
	var point := Vector2.ZERO;var found := false
	for attempt in 8:
		var angle := _spawn_rng.randf_range(0,TAU) if arc_deg>=360.0 or heading==Vector2.ZERO else base+_spawn_rng.randf_range(-half,half)
		point=_clamp_point(hero.position+Vector2(cos(angle),sin(angle))*_spawn_rng.randf_range(ring_min,ring_max))
		if point.distance_squared_to(hero.position)>=ring_min*ring_min*.64:found=true;break
	if not found:point=_spawn_point(ring_min,ring_max)
	_spawn_tags={"opening":true}
	if _op_step_spawned==0:_spawn_tags["first_of_step"]=true
	var made := _spawn(kind,point)
	_spawn_tags={}
	if not made:return false
	_op_step_spawned+=1
	var e: Dictionary=enemies[_enemy_sequence]
	e.definition.speed=float(e.definition.speed)*float(step.speed_bps)/10000.0
	return true

func _opening_crest(step: Dictionary,cap: int) -> void:
	var fan: Dictionary=step.crest
	var heading := _op_heading
	# A full-circle step has no heading of its own; its crest takes one angle from the spawn stream, as a taste crest does.
	if heading==Vector2.ZERO:
		var angle := _spawn_rng.randf_range(0,TAU)
		heading=Vector2(cos(angle),sin(angle))
	var count := alive_count();var placed := 0
	for i in int(fan.count):
		if count>=cap:break
		if _opening_place(step,heading,float(fan.arc_deg)):count+=1;placed+=1
	if placed>0:_emit("wave_crest",hero.position,{"beat":String(step.id),"direction":heading,"count":placed})

func _spawn_opening() -> void:
	var step: Dictionary=_op_list[_op_step]
	var cap := mini(int(step.alive_cap),int(tuning.alive_cap))
	if step.crest!=null and not _op_crest_done and tick-_op_step_start>=int(step.crest.at_ticks):
		_op_crest_done=true;_opening_crest(step,cap)
	if int(step.amount)<=0 or tick<_next_spawn:return
	_next_spawn=tick+int(step.interval_ticks)
	var count := alive_count()
	for i in int(step.amount):
		if count>=cap:break
		if _opening_place(step,_op_heading,float(step.heading.arc_deg)):count+=1

## Health factor of what spawns now: the beat's [start,end] rises linearly with seal progress, from the beat's own
## from_bps to the next beat's in the same zone (or the full seal). The trial has one value; the boss's escorts none.
func _beat_hp_bps(beats: Array,bps: int) -> int:
	if _trial_phase=="hold":return int(tuning.rhythm.trial.hp_bps)
	if zone==2 and _champion_id>0:return 10000
	var beat: Dictionary=beats[_beat_index]
	var from_bps := int(beat.from_bps)
	var to_bps := 10000
	if _beat_index+1<beats.size() and int(beats[_beat_index+1].zone)==int(beat.zone):to_bps=int(beats[_beat_index+1].from_bps)
	var along := clampi((bps-from_bps)*10000/maxi(1,to_bps-from_bps),0,10000)
	var ends: Array=beat.hp_bps
	return int(ends[0])+(int(ends[1])-int(ends[0]))*along/10000

## The trial stands between the last seal and the boss. Returns true while it holds the boss back.
func _trial_holds_boss() -> bool:
	if not _rhythm_on or zone!=2 or not bool(tuning.rhythm.trial.enabled):return false
	var trial: Dictionary=tuning.rhythm.trial
	if _trial_phase=="":
		_trial_phase="hold";_trial_until=tick+int(trial.hold_ticks);_trial_center=hero.position
		_record("trial_started")
		_emit("beat_started",hero.position,{"id":"trial"})
		_emit("trial_started",_trial_center,{"until_tick":_trial_until,"radius_m":float(trial.radius_m)})
		return true
	if _trial_phase=="hold":
		if tick<_trial_until:return true
		_trial_phase="clear";_trial_clear_until=tick+int(trial.clear_ticks)
		_record("trial_completed");_emit("trial_completed",hero.position,{})
	if _trial_phase=="clear":
		if tick<_trial_clear_until:return true
		_trial_phase="done"
	return false

func _rhythm_mix_kind(rule: Dictionary,mix_override: Dictionary={}) -> String:
	var mix: Dictionary=mix_override if not mix_override.is_empty() else rule.mix
	var walker := int(mix.get("walker",0));var ranged := int(mix.get("ranged",0));var charger := int(mix.get("charger",0))
	var roll := _spawn_rng.randi_range(0,walker+ranged+charger-1)
	if roll<walker:return "walker"
	if roll<walker+ranged:
		if tick<int(rule.get("ranged_from_ticks",0)):return "walker"
		# D17 4.2: at the cap of living ranged bodies the share of ranged turns into walkers (the draw is the same).
		if _ranged_left==0:return "walker"
		if _ranged_left>0:_ranged_left-=1
		return "ranged"
	return "charger" if tick>=int(rule.get("charger_from_ticks",0)) else "walker"

## Living ranged bodies of this epoch.
func _ranged_alive() -> int:
	var n := 0
	for id_ in enemies:
		var e: Dictionary=enemies[id_]
		if e.hp_raw>0 and e.generation==_epoch and e.kind=="ranged":n+=1
	return n

## The ranged bodies a batch may still add under the beat's ranged_cap (-1 = no cap key).
func _ranged_room(rule: Dictionary) -> int:
	if not rule.has("ranged_cap"):return -1
	return maxi(0,int(rule.ranged_cap)-_ranged_alive())

## D22 R1-B: a guardian of zone 0 or 1 is alive (the final boss does not use the rhythm's spawn).
func _guardian_alive() -> bool:
	return _champion_id>0 and enemies.has(_champion_id) and enemies[_champion_id].hp_raw>0

## A pack that comes in from one direction: one angle from _spawn_rng, then every body inside the fan around it.
func _spawn_crest(rule: Dictionary,fan: Dictionary,cap: int) -> void:
	# count_jitter_bps (D17 4.6): the head's size is rolled once per beat and run from the spawn stream, then kept.
	var bodies := int(fan.count)
	var jitter := int(fan.get("count_jitter_bps",0))
	if jitter>0:
		var beat_id := String(rule.id)
		if not _crest_jitter.has(beat_id):_crest_jitter[beat_id]=_spawn_rng.randi_range(-jitter,jitter)
		bodies=maxi(1,bodies*(10000+int(_crest_jitter[beat_id]))/10000)
	var heading := _spawn_rng.randf_range(0,TAU)
	_wave_heading=heading
	var mix_fan: Variant=fan.get("mix")
	var mix: Dictionary=mix_fan if mix_fan is Dictionary else {}
	var half := deg_to_rad(float(fan.arc_deg))*.5
	var ring_min := float(tuning.spawn.ring_min_m);var ring_max := float(tuning.spawn.ring_max_m)
	var count := alive_count();var placed := 0
	_ranged_left=_ranged_room(rule)
	for i in bodies:
		if count>=cap:break
		var kind := _rhythm_mix_kind(rule,mix)
		var point := Vector2.ZERO;var found := false
		for attempt in 8:
			var angle := heading+_spawn_rng.randf_range(-half,half)
			var radius := _spawn_rng.randf_range(ring_min,ring_max)
			# crest.mix: the chargers stand in the front half of the head (the half nearer the hero).
			if not mix.is_empty() and kind=="charger":radius=ring_min+(radius-ring_min)*.5
			point=_clamp_point(hero.position+Vector2(cos(angle),sin(angle))*radius)
			if point.distance_squared_to(hero.position)>=ring_min*ring_min*.64:found=true;break
		if not found:point=_spawn_point(ring_min,ring_max)
		if _spawn(kind,point):count+=1;placed+=1
	_ranged_left=-1
	if placed>0:_emit("wave_crest",hero.position,{"beat":"trial" if _trial_phase=="hold" else String(rule.id),"direction":Vector2(cos(heading),sin(heading)),"count":placed})

## D22 R1-B squad: once per wave, ranged bodies stand together on the far side from the head (heading +- 90..180 degrees),
## inside ring_m. The patch is as wide as the ring is deep. They are the planned threat: the alive cap holds, the ranged cap does not.
func _spawn_squad(rule: Dictionary,squad: Dictionary,cap: int) -> void:
	var direction := _wave_heading+_spawn_rng.randf_range(PI*.5,PI*1.5)
	var lo := float(squad.ring_m[0]);var hi := float(squad.ring_m[1])
	var half := atan2((hi-lo)*.5,(lo+hi)*.5)
	var count := alive_count();var placed := 0
	for i in int(squad.count):
		if count>=cap:break
		var angle := direction+_spawn_rng.randf_range(-half,half)
		var point := _clamp_point(hero.position+Vector2(cos(angle),sin(angle))*_spawn_rng.randf_range(lo,hi))
		if _spawn("ranged",point):
			count+=1;placed+=1
			if squad.has("volley"):_start_volley(enemies[_enemy_sequence],squad.volley)
	if placed>0:_emit("wave_squad",hero.position,{"beat":String(rule.id),"direction":Vector2(cos(direction),sin(direction)),"count":placed})

## TP2 first volley (optional squad.volley {windup_ticks, damage_bps}): the placed body starts in "windup" at once, aimed at the hero from
## where it stands (position only, no random draw), with the same fan telegraph an ordinary ranged body shows. When the windup ends
## the combat core fires its three shots at damage_bps/10000 of the zone's ranged damage, tags them "volley" and erases `volley`.
func _start_volley(e: Dictionary,volley: Dictionary) -> void:
	var delta: Vector2=hero.position-e.position
	var toward := delta/delta.length() if delta.length()>.001 else Vector2.UP
	e.direction=toward;e.attack_direction=toward;e.attack_kind="fan"
	e.state="windup";e.state_until=tick+int(volley.windup_ticks)
	e.volley={"damage_bps":int(volley.damage_bps)}
	var rays: Array[Vector2]=[]
	for ray in 3:rays.append(toward.rotated((float(ray)-1.0)*.14))
	e.telegraph={"shape":"fan","direction":toward,"radius":14.7+.44,"length":14.7,"width":.88,"rays":rays,"remaining_ticks":int(volley.windup_ticks)}

## Spawning under the beat table (or the trial's rule): amount per interval, a cap per beat, waves and lulls.
func _spawn_rhythm_wave() -> void:
	if tick<_rest_until or _trial_phase=="clear" or _beat_index<0:return
	# During the opening the first beat's own spawn rules (amount, taste crest) rest; the step's rules spawn instead.
	if _op_active:_spawn_opening();return
	var rhythm: Dictionary=tuning.rhythm
	var trial := _trial_phase=="hold"
	var rule: Dictionary=rhythm.trial if trial else rhythm.beats[_beat_index]
	var cap := mini(int(rule.alive_cap),int(tuning.alive_cap))
	var amount := int(rule.amount)
	var wave: Variant=null if trial else rule.wave
	# rhythm.guardian (D17 4.3): while a guardian lives the ordinary inflow runs at steady_bps and, unless crest is true, no head or squad comes.
	var steady := 10000;var heads := true
	var guard: Variant=rhythm.get("guardian")
	if guard is Dictionary and _guardian_alive():steady=int(guard.steady_bps);heads=bool(guard.get("crest",false))
	if wave is Dictionary:
		var relative := tick-_beat_tick
		var period := int(wave.period_ticks)
		var lull: bool=relative%period>=period-int(wave.lull_ticks)
		if lull!=_in_lull:
			_in_lull=lull
			if lull:_emit("lull_started",hero.position,{"beat":String(rule.id)})
		if relative/period>_wave_index:
			_wave_index=relative/period
			if not lull and heads:_spawn_crest(rule,wave.crest,cap)
		var squad: Variant=wave.get("squad")
		if squad is Dictionary and not lull and heads and relative/period>_squad_wave and relative%period>=int(squad.at_ticks):
			_squad_wave=relative/period
			_spawn_squad(rule,squad,cap)
		if lull:
			cap=cap*int(wave.lull_cap_bps)/10000
			if amount>0:amount=maxi(1,amount*int(wave.lull_amount_bps)/10000)
	elif not trial and rule.get("taste_crest")!=null and not _taste_done and tick>=int(rule.taste_crest.at_ticks):
		_taste_done=true
		if heads:_spawn_crest(rule,rule.taste_crest,cap)
	if tick<_next_spawn:return
	_next_spawn=tick+_descent_spawn_interval(int(rule.interval_ticks))
	if steady!=10000:amount=0 if steady<=0 else maxi(1,amount*steady/10000)
	var count := alive_count()
	var ring_min := float(tuning.spawn.ring_min_m);var ring_max := float(tuning.spawn.ring_max_m)
	_ranged_left=_ranged_room(rule)
	for i in amount:
		if count>=cap:break
		var kind := _rhythm_mix_kind(rule)
		if _spawn(kind,_spawn_point(ring_min,ring_max)):count+=1
	_ranged_left=-1

## Read-only picture for the progress bar. Works with the rhythm off too (then from zone and seal progress alone).
## phase: "surge" | "lull" | "rest" (no spawning: gate walk, after a guardian, the trial's clearing) | "trial" | "boss".
func run_progress() -> Dictionary:
	var phase := "surge"
	var beat_id := ""
	var boss_alive := zone==2 and _champion_id>0 and enemies.has(_champion_id)
	if _rhythm_on and _beat_index>=0:beat_id=String(tuning.rhythm.beats[_beat_index].id)
	if boss_alive:phase="boss";beat_id="boss" if _rhythm_on else beat_id
	elif _trial_phase=="hold":phase="trial";beat_id="trial"
	elif _trial_phase=="clear":phase="rest";beat_id="trial"
	elif not _zone_entered or tick<_rest_until:phase="rest"
	elif _in_lull:phase="lull"
	var markers: Array[Dictionary]=[]
	for i in 2:markers.append({"id":"gate%d"%(i+1),"kind":"gate","zone":i,"done":zone>i})
	if _rhythm_on and bool(tuning.rhythm.trial.enabled):markers.append({"id":"trial","kind":"trial","zone":2,"done":_trial_phase=="clear" or _trial_phase=="done"})
	markers.append({"id":"boss","kind":"boss","zone":2,"done":seals[2].cleared})
	return {"beat_id":beat_id,"zone":zone,"zone_bps":_zone_bps(),"phase":phase,"markers":markers}

func _step_enemies() -> void:
	if _extras_on:_guard_step()
	# ward_gap_ticks: a floor strike already telegraphed is never moved (the player has read it). Instead the
	# final boss does not begin a wind-up whose end would fall within the gap of a pending burst; it waits
	# (a one-tick recovery, repeated) until the wind-up would end clear of every pending burst.
	var ward_gap: int=int(tuning.heavy_hit.ward_gap_ticks)
	if ward_gap>0 and zone==2 and _champion_id>0 and enemies.has(_champion_id):
		var warden: Dictionary=enemies[_champion_id]
		var ready: bool=warden.state=="move" or (warden.state=="recover" and tick>=int(warden.state_until))
		if warden.hp_raw>0 and ready and int(warden.id)!=_shield_id and tick>=int(warden.frozen_until) and tick>=int(warden.get("stunned_until",0)):
			var attack_end: int=tick+_bf_next_windup(warden)
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
	if e.attack_kind=="slam":_bf_resolve_slam(e);return
	if e.attack_kind!="frost_cross":super._resolve_elite_attack(e,definition,distance);return
	for direction in [e.attack_direction,e.attack_direction.orthogonal()]:
		if _segment_distance_sq(hero.position,e.position-direction*4.8,e.position+direction*4.8)<=.9*.9:
			_hero_damage(int(definition.damage)*UNIT,e.position,_source_kind_of(e),int(e.id));break

func _emit(type: String,position: Vector2,details: Dictionary={}) -> void:
	super._emit(type,position,details)
	if type=="death" and _op_active and not details.get("elite",false):_op_step_kills+=1;_op_total_kills+=1
	if not descent.is_empty():
		if type=="wave_crest":_d_crest_tick=tick
		elif type=="death" and not _d_sweep.is_empty() and String(details.get("role","normal"))=="normal":_d_sweep.kills_total=int(_d_sweep.kills_total)+1
	# The gauge counts events, and only while no descent is called or sweeping (it never fills itself).
	if not descent.is_empty() and not _descent_hold and _d_sweep.is_empty() and metrics.has("descent"):_descent_score(type,details)
	if _kit_on:_kit_note_event(type,details)
	if type=="death" and _kb_on:_kill_burst_note(details,position)
	if type=="death" and _bf_state=="break" and String(details.get("role","normal"))=="normal":_bf_on_kill()
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
	if _elites_on:_elites_zone_left(zone)
	seals[zone].cleared=true;_record("seal_cleared");_elite_killed=false;_champion_id=-1
	if tuning.orbs.vacuum_on_seal:_vacuum_orbs()
	# D19 C1-c: a guardian (zone 0 or 1) is worth one level when rhythm.guardian_grace is on.
	if _rhythm_on and zone<2 and bool(tuning.rhythm.get("guardian_grace",false)):_seal_grace("guardian")
	if zone==2:
		chapter_hazards.clear();_boss_phase=0
		if _bf_on:_bf_state="done";_shield_id=0
		# D23 T5: with boss_spray on the result waits until the spilled loot has been pulled in (_spray_arrive); the hero cannot be
		# hurt in between (the kill is won).
		if _spray_has_boss():
			_invulnerable_until=maxi(_invulnerable_until,tick+int(_spray_rule().boss_pull_ticks)+int(_spray_rule().arrive_ticks)+1)
			return
		_sweep_ground_items()
		super._on_elite_defeated(e)
		_record("chapter_completed")
	else:
		for i in int(tuning.potion.seal_drops):_drop_potion(e.position+Vector2(.4*i,0))
		zone+=1;zone_kills=0;_zone_entered=false
		if _extras_on:_sites_zone_left(zone-1)
		if _rhythm_on:_rest_until=tick+int(tuning.rhythm.gate_rest_ticks)
		_emit("gate_opened",ZONES[zone]-Vector2(24,0),{"zone":zone})
		_record("gate_opened")
		if not _gate_sweep_qualities.is_empty():_sweep_ground_items_by_gate()

## The last seal's grace (tuning.final_level_on_boss_spawn): when the final boss appears, the orbs still on
## the ground flow to the hero and the collected experience rises to the last level threshold.
## Emits seal_grace {level, amount} (amount = experience added on top of the orbs) only if it granted something.
## D19 C1-c: `cause` "guardian" (a zone 0 / 1 guardian fell, rhythm.guardian_grace) fills up to the NEXT level instead and adds cause:"guardian".
func _seal_grace(cause: String="") -> void:
	_vacuum_orbs()
	var table: Array=growth.xp_thresholds()
	var target: int=int(table[table.size()-1])
	if cause=="guardian":
		# D19 C1-c: up to the next level only; the last level stays the final boss's (it is never filled from here).
		var level := growth.current_level()
		if level+1>=table.size():return
		target=int(table[level])
	var missing: int=target-int(growth.snapshot().xp)
	if missing<=0 or not growth.award_xp(missing):return
	if _pace_on:_pace_sync()
	var details := {"level":growth.current_level(),"amount":missing}
	if cause=="guardian":details.cause="guardian"
	_emit("seal_grace",hero.position,details)

## Developer shortcut to the final boss; the caller allows it ONLY in a run with the profile off (the core knows nothing of saves).
## Nobody calls it in a normal run, so a run that never calls it is byte-for-byte what it was (golden unchanged).
## What it does: the two earlier seals are marked cleared, the last seal's kills are filled, the field is emptied, the hero stands at the last
## zone, the trial (if any) is skipped, and the experience is raised to the last level threshold - the same top-up a normal run gets at the
## boss's appearance (final_level_on_boss_spawn) - with every level's card taken by the QA pilot's order of preference (primary's cards first).
## The boss then appears on the next step (with boss_finale on: from its entrance). NOT filled: gear (the bag stays as it is), potions' count, the
## rank of what a normal run would have chosen by hand. Returns false (and changes nothing) when it is too late or the run is not playing.
func debug_skip_to_boss() -> bool:
	if mode!="playing" or zone>2 or seals[2].champion_spawned or not _terminal_mode.is_empty():return false
	for z in 2:
		seals[z].kills=_seal_total(z);seals[z].champion_spawned=true;seals[z].cleared=true
	zone=2;zone_kills=_seal_total(2);seals[2].kills=zone_kills;_zone_entered=true;_champion_id=-1;_rest_until=0
	_trial_phase="done";_trial_until=0;_trial_clear_until=0
	enemies.clear();_alive=0;chapter_hazards.clear();_d_burn.clear()
	hero.position=ZONES[2]
	hero.hp_raw=hero.max_hp_raw
	_seal_grace()
	_refresh_mode()
	var guard := 0
	while mode=="choice" and guard<64:
		guard+=1
		var offer: Dictionary=get_offer()
		if offer.is_empty() or offer.cards.is_empty():break
		var picked: Dictionary=offer.cards[0]
		var best := -1
		for card in offer.cards:
			var score := 10
			if card.skill_id==growth.snapshot().primary:score=100 if card.kind=="evolve" else (90 if card.kind=="rank" else 80)
			elif card.kind=="unlock":score=65
			elif card.kind=="evolve":score=60
			elif card.kind=="rank":score=50
			if score>best:best=score;picked=card
		if not choose(offer.token,picked.id):break
	_record("debug_skip_to_boss")
	return true

## The seal breaks and every orb still on the ground flows to the hero as one gain.
func _vacuum_orbs(by: String="") -> void:
	var total := 0
	for orb in orbs:total+=int(orb.amount)
	orbs.clear()
	if total<=0:return
	var gained := _gain_xp(total)
	# amount is the XP actually gained (soul bonus included); xp_pickup.amount is the orb's own face value. `by` names the
	# one who called the vacuum when it was not a seal ("descent"); a seal's event stays as it was.
	var details := {"amount":gained}
	if not by.is_empty():details.by=by
	_emit("orb_vacuum",hero.position,details)

func _maybe_drop_item(e: Dictionary) -> void:
	var level: int=ZONE_LEVELS[zone]
	var primary_: String=growth.snapshot().primary
	if e.elite:
		# Champion and boss rewards go straight to the bag: the run may end with this kill.
		var boss: bool=e.get("chapter_boss",false)
		var drops: Array[Dictionary]=[]
		if boss and first_boss_kill:drops.append_array(loot.roll_class(_loot_rng,"boss_first_kill",level,primary_))
		var first_kill_drops := drops.size()
		drops.append_array(loot.roll_class(_loot_rng,"boss" if boss else "champion",level,primary_,_drop_mods(false),"legendary" if boss and _pity_armed else ""))
		var marked := false
		var spray := _spray_enabled()
		var spilled: Array[Dictionary]=[]
		var notable_uid := 0
		for index in drops.size():
			var item: Dictionary=drops[index]
			# The objective slot carries the most notable reward: a unique if any, else the first item.
			var notable: bool=not marked and (item.quality=="unique" or item==drops[drops.size()-1] or not _has_unique(drops))
			if notable:marked=true
			var source_name := "first_kill" if index<first_kill_drops else ("boss" if boss else "champion")
			if spray:
				# D23 T5: on the floor round the kill, never straight into the bag. The place is a function of (index, count): no draw.
				var landing := _spray_point(e.position,index,drops.size())
				_publish_item(item,landing,false,notable,source_name,{"spray":true,"origin":e.position})
				if notable:notable_uid=int(item.uid)
				spilled.append({"id":int(item.uid),"rarity":String(item.quality),"to":landing})
			else:_publish_item(item,e.position,true,notable,source_name)
		if spray and not spilled.is_empty():_spray_begin("boss" if boss else "champion",e.position,spilled,notable_uid,boss)
		# D23 T9: the pity fired when the first guaranteed line of the boss class came out as a legendary.
		if boss and _pity_armed and drops.size()>first_kill_drops and drops[first_kill_drops].quality=="legendary":
			_pity_fired=true;_emit("drop_pity",e.position,{"uid":int(drops[first_kill_drops].uid),"item_id":String(drops[first_kill_drops].get("legendary_id",""))})
		return
	# A strong body (grade "elite", D13 W4-a): the elite table, on the floor like any ordinary drop; a guard opens its site after it.
	if e.get("grade","")=="elite":
		_elite_died(e)
		for item in loot.roll_class(_loot_rng,"elite",level,primary_,_drop_mods(true)):
			if items.size()>=MAX_GROUND_ITEMS or inventory.size()>=MAX_INVENTORY:
				metrics.overflow_items=int(metrics.get("overflow_items",0))+1;continue
			_publish_item(item,e.position,false,false,"elite")
		if e.has("guard_uid"):_guard_unlock(e)
		return
	# Early guaranteed pieces keep the first minute from being empty-handed.
	var forced_slots := ["weapon","body","hands","feet"]
	var thresholds := [6,35,90,160]
	if _guaranteed_drops<thresholds.size() and kills>=thresholds[_guaranteed_drops]:
		if items.size()<MAX_GROUND_ITEMS and inventory.size()<MAX_INVENTORY:
			_publish_item(loot.roll_item(_loot_rng,level,"magic",forced_slots[_guaranteed_drops]),e.position,false,false,"forced")
		_guaranteed_drops+=1
		return
	for item in loot.roll_class(_loot_rng,"normal",level,primary_,_drop_mods(true)):
		if items.size()>=MAX_GROUND_ITEMS or inventory.size()>=MAX_INVENTORY:
			metrics.overflow_items=int(metrics.get("overflow_items",0))+1;continue
		_publish_item(item,e.position,false,false,"normal")

## The run ends with the boss: gear still lying on the ground is gathered, not lost.
func _sweep_ground_items() -> void:
	var left: Array[Dictionary]=[]
	for item in items:
		if inventory.size()<MAX_INVENTORY:
			item.collected=true;inventory.append(item);metrics.picked_items+=1
			_emit("item_pickup",hero.position,{"item":item.duplicate(true),"swept":true})
		else:left.append(item)
	items=left

## D21 N2: when a gate opens, the gear of the zone being left that is of a swept quality goes into the bag.
## The target is "quality at or above the threshold" whether or not the item is veiled; an identify scroll (W6) would be spent or offered at this spot, nothing here assumes it.
## Only qualities from loot_flow.keep_min_quality up stay on the ground past 180 s, so nothing older than the last gate is left there but a full bag's leftovers.
func _sweep_ground_items_by_gate() -> void:
	var left: Array[Dictionary]=[]
	for item in items:
		if item.quality in _gate_sweep_qualities and inventory.size()<MAX_INVENTORY and not _in_spray(int(item.uid)):
			item.collected=true;inventory.append(item);metrics.picked_items+=1
			_emit("item_pickup",hero.position,{"item":item.duplicate(true),"swept":true,"by":"gate"})
		else:left.append(item)
	items=left

# ---------------------------------------------------------------- D23 T5: guardian and boss loot spray (loot_flow.boss_spray)
## The spilled loot of one kill waits as {source, start, arrive, uids, notable, boss, origin}; _spray is empty (and absent from the snapshot) while the switch is off.
var _spray: Array[Dictionary]=[]
var _spray_done_boss := false

func _spray_rule() -> Dictionary:
	return tuning.get("loot_flow",{}).get("boss_spray",{})

func _spray_enabled() -> bool:
	return bool(_spray_rule().get("enabled",false))

func _spray_has_boss() -> bool:
	for group in _spray:
		if group.boss:return true
	return false

func _in_spray(uid: int) -> bool:
	for group in _spray:
		if uid in group.uids:return true
	return false

## Where piece `index` of `count` lands: a ring round the kill, ring_min..ring_max, angle by order, radius by index. No random draw.
func _spray_point(origin: Vector2,index: int,count: int) -> Vector2:
	var rule := _spray_rule()
	var low := float(rule.ring_min_cm)/100.0
	var high := float(rule.ring_max_cm)/100.0
	var angle := TAU*(float(index)+.5)/float(maxi(1,count))
	return _clamp_point(origin+Vector2.from_angle(angle)*(low+(high-low)*float(index%3)/2.0))

## loot_spray {source: "champion"|"boss", origin, items:[{id (item uid), rarity (quality), to (landing point)}], pull_tick, arrive_tick}
## starts the spill (the item_drop events of the same tick carry spray:true and origin).
func _spray_begin(source: String,origin: Vector2,spilled: Array[Dictionary],notable_uid: int,boss: bool) -> void:
	var rule := _spray_rule()
	var start := tick+int(rule.boss_pull_ticks if boss else rule.guardian_pull_ticks)
	var uids: Array[int]=[]
	for entry in spilled:uids.append(int(entry.id))
	_spray.append({"source":source,"start":start,"arrive":start+int(rule.arrive_ticks),"uids":uids,"notable":notable_uid,"boss":boss,"origin":origin})
	_emit("loot_spray",origin,{"source":source,"origin":origin,"items":spilled.duplicate(true),"pull_tick":start,"arrive_tick":start+int(rule.arrive_ticks)})

## At pull_tick: loot_pull {source, items:[uid still on the floor], arrive_tick} (the screen flies them to the hero). At arrive_tick the pieces
## still on the floor go into the bag by the same rules as a direct reward (item_pickup with by:"spray"); the final boss's result follows.
func _spray_step() -> void:
	var waiting: Array[Dictionary]=[]
	for group in _spray:
		if tick==int(group.start):
			var floor_ids: Array[int]=[]
			for item in items:
				if int(item.uid) in group.uids:floor_ids.append(int(item.uid))
			_emit("loot_pull",hero.position,{"source":group.source,"items":floor_ids,"arrive_tick":int(group.arrive)})
		if tick>=int(group.arrive):_spray_arrive(group)
		else:waiting.append(group)
	_spray=waiting
	if _spray_done_boss:
		_spray_done_boss=false
		_sweep_ground_items()
		_victory_now()
		_record("chapter_completed")

func _victory_now() -> void:
	super._on_elite_defeated({})

func _spray_arrive(group: Dictionary) -> void:
	var left: Array[Dictionary]=[]
	for item in items:
		if not int(item.uid) in group.uids:
			left.append(item)
			continue
		var boss_reward: bool=bool(item.get("objective_reward",false))
		item.collected=true
		if inventory.size()<MAX_INVENTORY or (boss_reward and inventory.size()<MAX_INVENTORY+1):
			inventory.append(item);metrics.picked_items+=1
			_emit("item_pickup",hero.position,{"item":item.duplicate(true),"by":"spray"})
		elif pending_rewards.size()<MAX_PENDING_REWARDS:
			pending_rewards.append(item)
			_emit("reward_pending",hero.position,{"item":item.duplicate(true)})
		else:metrics.overflow_items=int(metrics.get("overflow_items",0))+1
	items=left
	if int(group.notable)>0 and _elite_reward_uid==0:
		for item in inventory:
			if int(item.uid)==int(group.notable):_elite_reward_uid=int(item.uid)
	if group.boss:_spray_done_boss=true

func _has_unique(drops: Array[Dictionary]) -> bool:
	for item in drops:
		if item.quality=="unique":return true
	return false

## `source` (D11 D5) only names where the drop came from on the event; it is never written into the item.
func _publish_item(item: Dictionary,point: Vector2,direct: bool,boss_reward: bool=false,source: String="",extra: Dictionary={}) -> void:
	_item_sequence+=1;item.uid=_item_sequence;item.position=point;item.collected=direct;item.drop_tick=tick
	item.objective_reward=boss_reward;metrics.dropped_items+=1
	var drop_details := {"item":item.duplicate(true),"source":source}
	if not extra.is_empty():drop_details.merge(extra)
	_emit("item_drop",point,drop_details)
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
	# ET-A: the kit's cards on the signature arc (one more branch; a big body struck again or rebounded needs room in the hit budget).
	if _kit_on and id_==_primary_id:
		effect.branches=mini(4,int(effect.branches)+growth.kit_val("branches"))
		effect.hit_budget=mini(128,maxi(int(effect.hit_budget),int(effect.branches)*(int(effect.chain_targets)+int(_kit.chain.lone_rebounds)+growth.kit_val("lone_rebounds"))))
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
		# With the spell composition the axis cards replace the stage bonus: primary_bonus is not read.
		if not spells.is_empty():effect.cooldown_ticks=maxi(12,int(effect.cooldown_ticks));return
		if table.is_empty():return
		var bonus: Dictionary=table.get("evo" if value.evolved else "r%d"%int(value.rank),{})
		for stat in bonus.get("add",{}):effect[stat]=_limited(stat,int(effect[stat])+int(bonus.add[stat]))
		for stat in bonus.get("mul_bps",{}):effect[stat]=_limited(stat,int(effect[stat])*int(bonus.mul_bps[stat])/10000)
		if bonus.has("cooldown_bps"):effect.cooldown_ticks=maxi(12,int(effect.cooldown_ticks)*int(bonus.cooldown_bps)/10000)
	elif _secondary_active and not _is_ring(id_):
		# A ring is the witch's own spell and is not damped; only a borrowed basic spell is.
		var s: Dictionary=tuning.secondary
		effect.damage_raw=_limited("damage_raw",int(effect.damage_raw)*int(s.damage_bps)/10000)
		effect.hit_budget=_limited("hit_budget",int(effect.hit_budget)*int(s.hit_budget_bps)/10000)
		effect.cooldown_ticks=maxi(12,int(effect.cooldown_ticks)*int(s.cooldown_bps)/10000)
		effect.chain_targets=mini(int(effect.chain_targets),int(s.max_chain_targets))
		effect.branches=mini(int(effect.branches),int(s.max_branches))
	# Whatever the data says, no role may push a cast under 12 ticks.
	effect.cooldown_ticks=maxi(12,int(effect.cooldown_ticks))

# ---------------------------------------------------------------- statuses and detonation (D12 B0.9, only with `spells`)

## The detonation a direct hit of `skill_id` triggers on this enemy, or {}: the first status the spell detonates that
## other spells put on it. A status the spell applied itself never counts (each status remembers the stacks per spell).
## {status, stacks (put there by others), src (the other spell with most of them), bonus_bps, mult_bps, consume, freeze_bonus}
func _detonation_of(e: Dictionary,spell: Dictionary,skill_id: String) -> Dictionary:
	if spell.detonates.is_empty():return {}
	var table: Dictionary=e.get("status",{})
	for status in spell.detonates:
		var entry: Variant=table.get(status)
		if not entry is Dictionary or int(entry.n)<=0 or tick>=int(entry.until):continue
		var others := int(entry.n)-int(entry.by.get(skill_id,0))
		if others<=0:continue
		var rule: Dictionary=spell.detonates[status]
		var bonus := int(rule.per_stack_bps)*others if rule.has("per_stack_bps") else int(rule.bonus_bps)
		var src := "";var most := 0
		for who in entry.by:
			if who!=skill_id and int(entry.by[who])>most:src=String(who);most=int(entry.by[who])
		# An evolved spell of the pair makes the pair's detonation stronger (evolve.partner_detonate_bps).
		var pair_id := RunSpells.pair_between(spells,skill_id,src)
		if not pair_id.is_empty() and (growth.evolve_partner_of(skill_id)==pair_id or growth.evolve_partner_of(src)==pair_id):
			bonus=bonus*int(spells.evolve.partner_detonate_bps)/10000
		return {"status":String(status),"stacks":others,"src":src,"bonus_bps":bonus,"mult_bps":10000+bonus,"consume":bool(rule.consume),"freeze_bonus":int(rule.get("freeze_bonus",0)),
				"block_bps":int(rule.get("block_bps",10000)),"block_targets":int(rule.get("block_targets",0)),"pair":pair_id}
	return {}

## A direct hit puts the spell's statuses on the enemy (count up to the status maximum, every application renews the
## expiry and the last applier is `src`). The chill status is the freeze counter: it freezes at freeze_at (less the
## detonation's freeze_bonus on that hit; a smaller freeze_stacks in the effect, from gear, wins) and starts over.
func _apply_statuses(e: Dictionary,spell: Dictionary,effect: Dictionary,freeze_bonus: int,skill_id: String) -> void:
	for status in spell.applies:
		var rule: Dictionary=spells.statuses[status]
		if not e.has("status"):e.status={}
		var entry: Dictionary=e.status.get(status,{})
		if entry.is_empty() or tick>=int(entry.until):entry={"n":0,"src":skill_id,"until":0,"by":{}}
		var add := mini(int(spell.applies[status]),maxi(0,int(rule.max)-int(entry.n)))
		if add>0:entry.n=int(entry.n)+add;entry.by[skill_id]=int(entry.by.get(skill_id,0))+add
		entry.src=skill_id;entry.until=tick+int(rule.expire_ticks)
		e.status[status]=entry
		if status=="chill" and rule.has("freeze_at"):
			var threshold := int(rule.freeze_at)-freeze_bonus
			if int(effect.freeze_stacks)>0:threshold=mini(threshold,int(effect.freeze_stacks))
			if int(entry.n)>=maxi(1,threshold):
				e.frozen_until=tick+(12 if e.elite else 75);entry.n=0;entry.by={}
				_set_cc_src(e,"frozen",skill_id)

## Remember which spell put a control on the enemy (cc_src, only in a run with the composition) so that spell's own control
## never counts for its own bonus (vs_cc) or its aim.
func _set_cc_src(e: Dictionary,cls: String,skill_id: String) -> void:
	if not e.has("cc_src"):e.cc_src={}
	e.cc_src[cls]=skill_id

## Share of a ring's damage this enemy takes by its distance to the hero, in ten-thousandths: all of it within near_cm, then
## a straight line down to falloff_floor_bps at the edge of the ring. Integers; no random number. Controls are not scaled.
func _falloff_bps(effect: Dictionary,e: Dictionary) -> int:
	var floor_bps := int(effect.get("falloff_floor_bps",10000))
	var near := int(effect.get("near_cm",0));var radius := int(effect.get("ring_radius_cm",0))
	if floor_bps>=10000 or radius<=near:return 10000
	var d := int(hero.position.distance_to(e.position)*100.0)
	if d<=near:return 10000
	return 10000-(10000-floor_bps)*mini(d-near,radius-near)/(radius-near)

## What a ring hit does besides damage (depth 0, the enemy still alive): freeze, stun, stagger. A detonation (I2) lengthens
## them by its block_bps. Strong enemies keep the old rules: frozen 12 ticks, stunned like a direct arc hit, never staggered.
func _apply_ring_control(e: Dictionary,effect: Dictionary,detonation: Dictionary,skill_id: String) -> void:
	var block := int(detonation.get("block_bps",10000)) if not detonation.is_empty() else 10000
	var freeze := int(effect.get("freeze_ticks",0))
	if freeze>0:
		var until := tick+(12 if e.elite else maxi(1,freeze*block/10000))
		if until>int(e.frozen_until):e.frozen_until=until;_set_cc_src(e,"frozen",skill_id);_ward_add("freezes")
	var stun := int(effect.get("stun_ticks",0))
	if stun>0:
		var duration := 0
		if not e.elite:duration=maxi(1,stun*block/10000)
		elif tick>=int(e.get("shock_ready_tick",0)):
			duration=ARC_ELITE_STUN_TICKS36;e.shock_ready_tick=tick+ARC_ELITE_IMMUNITY36
		if duration>0 and tick+duration>int(e.get("stunned_until",0)):
			e.stunned_until=tick+duration;_set_cc_src(e,"stunned",skill_id);_ward_add("stuns")
			_emit("stun",e.position,{"target_id":int(e.id),"skill_id":skill_id,"until_tick":e.stunned_until,"duration_ticks":duration,"elite":e.elite})
	var stagger := int(effect.get("stagger_ticks",0))
	if stagger>0 and not e.elite:
		var ticks := maxi(1,stagger*block/10000)
		if tick+ticks>int(e.get("staggered_until",0)):e.staggered_until=tick+ticks
		_set_cc_src(e,"staggered",skill_id);_ward_add("staggers")
		# A body in the middle of a wind-up or a dash loses that attack: it recovers for as long as it is staggered.
		var cut: bool=e.state=="windup" or e.state=="dash"
		if cut:
			e.state="recover";e.state_until=tick+ticks;e.telegraph={};_ward_add("cuts")
		_emit("stagger",e.position,{"target_id":int(e.id),"cut":cut})

func _limited(stat: String,amount: int) -> int:
	return clampi(amount,int(GrowthCatalog.LIMITS[stat][0]),int(GrowthCatalog.LIMITS[stat][1]))

## In a run with a build the level an item needs is measured against max(permanent level, grace level).
func can_equip(item: Dictionary) -> bool:
	var level := int(growth.snapshot().level)
	if _build_active:level=maxi(level,int(_build.character_level))
	return int(item.get("required_level",1))<=level

## D21 N1: what the pickup of bag item `uid` should do on screen. Read only: no state, no random draw, no event.
## {react:"quiet"|"auto_equip"|"card"|"open", better, empty_slot, slot, replaces_uid, top_rows:[at most 3 rows of preview_equip().rows]}.
## Order: unknown uid -> {}; worn already or level too low -> quiet; quality at open_min_quality or above -> open; empty slot -> auto_equip
## (card when auto_equip_empty is off); better by loot.is_upgrade -> card; else quiet. {} too when loot.json has no pickup_flow block.
## The thresholds come from loot.json "pickup_flow"; the screen reads its time keys itself.
func pickup_verdict(uid: int) -> Dictionary:
	if loot==null or not loot.data.has("pickup_flow"):return {}
	var item := _owned(uid)
	if item.is_empty():return {}
	var flow: Dictionary=loot.data.pickup_flow
	var slot := target_slot(item)
	var current := _owned(int(equipped.get(slot,-1)))
	var empty_slot := current.is_empty()
	var worn := not equip_slot_of(uid).is_empty()
	# D21 v2: an unappraised item (veiled:true; none exist while identify is off) only counts its base numbers, so "better" is unknown.
	var veiled: bool=bool(item.get("veiled",false))
	var better := "unknown"
	# GM5: with loot.json upgrade_verdict.enabled the answer is loot.upgrade_verdict() over the whole worn set (the same function the tools use);
	# off, it is the old is_upgrade() line, untouched. `note` is "" | "empty_no_effect" | "weak_for_primary" and only the new path sets it.
	var judged: Dictionary={}
	if not veiled and not worn and loot.verdict_on():judged=loot.upgrade_verdict(item,_verdict_worn(),slot,_primary_id,_verdict_shots())
	var note: String=String(judged.get("note",""))
	if not veiled:
		if judged.is_empty():better="yes" if not worn and bool(loot.is_upgrade(item,current,_primary_id)) else "no"
		else:better="yes" if bool(judged.better) else "no"
	var react := "quiet"
	if not worn and can_equip(item):
		var order: Array=loot.data.qualities
		if order.find(item.quality)>=order.find(flow.open_min_quality):react="open"
		elif veiled:
			if empty_slot and bool(flow.auto_equip_veiled):react="auto_equip"
			else:react="card"
		# GM5: an empty slot is filled only when the new item raises V; otherwise a card says it does nothing for this witch and nothing is worn.
		elif empty_slot and not judged.is_empty() and not bool(judged.better):react="card"
		elif empty_slot:react="auto_equip" if bool(flow.auto_equip_empty) else "card"
		elif better=="yes" or String(flow.card_min)=="any":react="card"
	var top: Array[Dictionary]=[]
	if react!="quiet":top=_top_rows(preview_equip(uid,slot).get("rows",[]))
	# Callers read the result by key; keys may be added.
	var result := {"react":react,"veiled":veiled,"better":better,"empty_slot":empty_slot,"slot":slot,"replaces_uid":int(current.get("uid",0)),"top_rows":top}
	if not judged.is_empty():
		result.note=note
		result.verdict_delta=float(judged.delta)
	return result

## GM5: the worn items as {equip slot: item} (the bag's own dictionaries, read only) and the primary's own shot counts without gear: the same
## numbers loot.upgrade_verdict reads. Pure; the second one is {} when the primary is not in the run.
func _verdict_worn() -> Dictionary:
	var result := {}
	for slot in equipped:
		var worn_item := _owned(int(equipped[slot]))
		if not worn_item.is_empty():result[slot]=worn_item
	return result

func _verdict_shots() -> Dictionary:
	var base: Dictionary=_skill_with(_primary_id,{})
	if base.is_empty():return {}
	return {"projectiles":int(base.effects.projectiles),"chain_targets":int(base.effects.chain_targets)}

## VO7: with loot.json upgrade_verdict on, a ring with both ring slots taken goes where the verdict says V rises most (the weaker ring); a free slot
## or a worn item keeps the base answer. Off, this is exactly combat_core's target_slot (ring first, then ring2, else ring).
func target_slot(item: Dictionary) -> String:
	var base: String=super(item)
	if loot==null or not loot.verdict_on() or String(item.get("slot",""))!="ring" or not equip_slot_of(int(item.get("uid",-1))).is_empty():return base
	if not equipped.has("ring") or not equipped.has("ring2"):return base
	return String(loot.upgrade_verdict(item,_verdict_worn(),"",_primary_id,_verdict_shots()).slot)

## GM5: the one place the app asks "is this a better item than the worn one" when it has no pickup_verdict: the verdict v2 when it is on,
## else loot.is_upgrade(). `slot` is where the item would go.
func is_better_gear(candidate: Dictionary,current: Dictionary,slot: String) -> bool:
	if loot==null:return false
	if not loot.verdict_on():return bool(loot.is_upgrade(candidate,current,_primary_id))
	return bool(loot.upgrade_verdict(candidate,_verdict_worn(),slot,_primary_id,_verdict_shots()).better)

## The (at most) three rows that change the most in relative size. Stable on ties; copies the rows.
func _top_rows(rows: Array) -> Array[Dictionary]:
	var ranked: Array[Dictionary]=[]
	for row in rows:
		if row.change=="same":continue
		var scale:=maxf(maxf(absf(float(row.before)),absf(float(row.after))),.000001)
		ranked.append({"key":absf(float(row.delta))/scale,"row":row})
	for i in range(1,ranked.size()):
		var held: Dictionary=ranked[i];var j:=i-1
		while j>=0 and float(ranked[j].key)<float(held.key):ranked[j+1]=ranked[j];j-=1
		ranked[j+1]=held
	var result: Array[Dictionary]=[]
	for i in mini(3,ranked.size()):result.append(ranked[i].row.duplicate(true))
	return result

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
			_emit("ritual_started",def.position,{"id":id_});return true
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
			_publish_item(loot.roll_item(_loot_rng,ZONE_LEVELS[zone],"rare","",{},"rare_boss"),def.position,true,false,"ritual")
			_drop_potion(def.position);_emit("ritual_completed",def.position,{"id":def.id})

func _step_chapter_hazards() -> void:
	if _champion_id<=0 or not enemies.has(_champion_id) or zone!=2:return
	var boss: Dictionary=enemies[_champion_id]
	if boss.hp_raw<=0:return
	if _bf_on:_bf_step(boss)
	else:_boss_ward_legacy(boss)
	var live: Array[Dictionary]=[]
	for hazard in chapter_hazards:
		if tick<hazard.expires:live.append(hazard);continue
		if hero.position.distance_squared_to(hazard.position)<=pow(float(hazard.radius),2):_hero_damage(hazard.damage_raw,hazard.position,"boss_ward",0,String(hazard.get("attack_id","")))
		_last_ward_burst=tick
		if hazard.has("kind"):_emit("chapter_burst",hazard.position,{"radius":hazard.radius,"kind":hazard.kind})
		else:_emit("chapter_burst",hazard.position,{"radius":hazard.radius})
	chapter_hazards=live

## The fight as it was before D-boss-finale: two phases at half health, floor strikes every 4 s (3 s in phase 2).
func _boss_ward_legacy(boss: Dictionary) -> void:
	if _boss_phase==1 and int(boss.hp_raw)*2<=int(boss.max_hp_raw):
		_boss_phase=2;boss.definition.recover=65;_next_ward=mini(_next_ward,tick+HZ)
		# The half-health change leaves a breath without floor strikes (D11 A2, rhythm.boss.phase_break_ticks).
		if _rhythm_on:_next_ward=maxi(_next_ward,tick+int(tuning.rhythm.boss.phase_break_ticks))
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

# ---------------------------------------------------------------- D-boss-finale (tuning.boss_finale): entrance, three phases, two breaks
# BF1 the fight is an entrance, phase 1, break 1, phase 2, break 2 (the storm), phase 3. BF2 a break is a fixed number of ticks in which the
# boss is out of play (_shield_id: not aimed at, not hit, no AI); gear, kills and the descent cannot shorten it. BF3 a phase's health
# threshold holds: damage past it is thrown away (_damage_enemy -> _bf_clamp_damage) and the break begins. All figures are in
# tuning.boss_finale; the code holds none. Random numbers: only the escorts' and adds' kind and place (_spawn_rng), and only here.

func _bf_reset() -> void:
	_bf_state="";_bf_phase=0;_bf_break=-1;_bf_until=0;_bf_to=Vector2.ZERO;_bf_land_started=false
	_bf_next_adds=0;_bf_next_escort=0;_bf_next_storm=0;_bf_storms=0;_bf_phase_attacks=0;_bf_chip=0;_bf_break_chip=0;_bf_break_kills=0

## The final boss has just been made: its health from the block, the entrance begins (out of play for entrance_ticks).
func _bf_begin(e: Dictionary) -> void:
	var hp := int(_bf.hp)
	e.definition.hp=hp;e.hp_raw=hp*UNIT;e.max_hp_raw=e.hp_raw
	e.definition.recover=int(_bf.phases[0].recover)
	_bf_reset()
	_bf_state="entrance";_bf_until=tick+int(_bf.entrance_ticks);_shield_id=int(e.id);_boss_phase=1
	_emit("boss_entrance",e.position,{"ticks":int(_bf.entrance_ticks),"target_id":int(e.id)})

## One tick of the finale, after the combat step (called from _step_chapter_hazards). `boss` is alive.
func _bf_step(boss: Dictionary) -> void:
	match _bf_state:
		"entrance":
			if tick>=_bf_until:_bf_start_phase(boss,0)
		"phase":
			var rule: Dictionary=_bf.phases[_bf_phase]
			var to_bps := int(rule.to_hp_bps)
			if to_bps>0 and int(boss.hp_raw)<=int(boss.max_hp_raw)*to_bps/10000:
				_bf_start_break(boss);return
			_bf_ward_step(boss,rule)
			if rule.adds!=null and tick>=_bf_next_adds:
				_bf_next_adds=tick+int(rule.adds.interval_ticks)
				_bf_spawn_group(int(rule.adds.amount),int(rule.adds.alive_cap),{})
		"break":
			_bf_break_step(boss)

## A phase begins (the first after the entrance, the others when a break ends). The boss is back in play.
func _bf_start_phase(boss: Dictionary,index: int) -> void:
	var rule: Dictionary=_bf.phases[index]
	_bf_state="phase";_bf_phase=index;_bf_phase_attacks=0;_shield_id=0;_boss_phase=index+1
	boss.state="move";boss.state_until=0;boss.telegraph={};boss.definition.recover=int(rule.recover)
	# BF-C: what the descent left on the boss in the break (freeze, stun, stagger) does not carry into the next phase.
	if index>0 and bool(_bf.get("descent_pierces_break",false)):boss.frozen_until=0;boss.stunned_until=0;boss.staggered_until=0
	_next_ward=tick+int(rule.ward.every_ticks)
	_bf_next_adds=tick+(int(rule.adds.interval_ticks) if rule.adds!=null else 0)
	if index>0:_record("boss_phase%d"%(index+1))
	_emit("boss_phase",boss.position,{"phase":index+1,"id":String(rule.id)})

## A phase's health threshold was reached: the boss leaps away (out of play) for the break's fixed ticks.
func _bf_start_break(boss: Dictionary) -> void:
	var rule: Dictionary=_bf.breaks[_bf_phase]
	_bf_state="break";_bf_break=_bf_phase;_bf_until=tick+int(rule.ticks);_shield_id=int(boss.id);_bf_land_started=false
	_bf_break_kills=0;_bf_break_chip=0
	# Whatever it was doing is cut; the next phase starts clean.
	boss.state="move";boss.state_until=0;boss.telegraph={}
	boss.frozen_until=0;boss.stunned_until=0;boss.staggered_until=0;boss.slow_until=0
	_bf_to=_bf_landing_spot(rule)
	boss.position=_bf_to
	_emit("boss_break_started",boss.position,{"index":_bf_break,"ticks":int(rule.ticks),"to":_bf_to,"target_id":int(boss.id)})
	_bf_next_escort=tick+int(rule.escort.interval_ticks)
	_bf_spawn_group(int(rule.escort.first),int(rule.escort.alive_cap),rule.escort.mix)
	if rule.storm!=null:_bf_next_storm=tick+int(rule.storm.every_ticks);_bf_storms=0
	for i in int(rule.potion_drops):
		var spot := _clamp_point(_bf_to+Vector2(.7*i,0))
		_drop_potion(spot);_emit("boss_potion",spot,{"index":_bf_break})

func _bf_break_step(boss: Dictionary) -> void:
	var rule: Dictionary=_bf.breaks[_bf_break]
	# The landing is telegraphed for its wind-up before the break ends, and bursts on the tick the break ends.
	var land: Dictionary=rule.land
	if not _bf_land_started and tick>=_bf_until-int(land.windup_ticks):
		_bf_land_started=true
		_bf_hazard(_bf_to,float(land.radius_m),int(land.windup_ticks),int(land.damage),"land","land",Vector2.ZERO)
	if tick>=_bf_until:
		_emit("boss_break_ended",boss.position,{"index":_bf_break,"target_id":int(boss.id)})
		_bf_start_phase(boss,_bf_break+1)
		return
	if rule.storm!=null and tick>=_bf_next_storm:
		var storm: Dictionary=rule.storm
		_bf_next_storm=tick+int(storm.every_ticks)
		# A storm that would burst after the break is over is not sent.
		if tick+int(storm.windup_ticks)<=_bf_until:_bf_storm(storm)
	if tick>=_bf_next_escort:
		_bf_next_escort=tick+int(rule.escort.interval_ticks)
		_bf_spawn_group(int(rule.escort.amount),int(rule.escort.alive_cap),rule.escort.mix)

## Where the boss lands: ring_m from the hero in the hero's heading (no random number), turned aside when a wall pulls it too close.
func _bf_landing_spot(rule: Dictionary) -> Vector2:
	var low := float(rule.relocate_m[0]);var high := float(rule.relocate_m[1])
	var distance := low+(high-low)*float(tick%7)/6.0
	var heading: Vector2=hero.direction if hero.direction.length_squared()>.01 else Vector2.UP
	var best := _clamp_point(hero.position+heading*distance)
	var best_distance := best.distance_to(hero.position)
	if best_distance<low*.8:
		for turn in [PI*.5,-PI*.5,PI]:
			var candidate := _clamp_point(hero.position+heading.rotated(turn)*distance)
			var d := candidate.distance_to(hero.position)
			if d>best_distance:best=candidate;best_distance=d
			if best_distance>=low*.8:break
	return best

## A telegraphed circle on the floor (burst after windup ticks): the existing hazard list, so the hero's dodge and the ward gap read it too.
func _bf_hazard(center: Vector2,radius: float,windup: int,damage: int,kind: String,attack_id: String,direction: Vector2) -> void:
	_hazard_sequence+=1
	chapter_hazards.append({"uid":_hazard_sequence,"position":center,"radius":radius,"started":tick,"expires":tick+windup,"damage_raw":damage*UNIT,"kind":kind,"attack_id":"" if attack_id=="ward" else attack_id})
	_emit("chapter_warning",center,{"radius":radius,"duration_ticks":windup,"kind":kind})
	if kind!="ward":_emit("boss_telegraph",center,{"attack_id":attack_id,"shape":"circle","position":center,"direction":direction,"length":0.0,"width":0.0,"radius":radius,"windup_ticks":windup})

## The floor strike of a phase (the old one, with the phase's own rhythm and number of circles).
func _bf_ward_step(boss: Dictionary,rule: Dictionary) -> void:
	if tick<_next_ward:return
	# As before: a strike is put off when it would burst within ward_gap_ticks of the end of the boss's own wind-up.
	var gap: int=int(tuning.heavy_hit.ward_gap_ticks)
	if gap>0 and boss.state=="windup" and absi(tick+72-int(boss.state_until))<gap:
		_next_ward=tick+gap;return
	_next_ward=tick+int(rule.ward.every_ticks)
	var centers: Array[Vector2]=[hero.position]
	if int(rule.ward.centers)>=3:
		centers.append(_clamp_point(hero.position+hero.direction.rotated(PI*.5)*3.8))
		centers.append(_clamp_point(hero.position-hero.direction.rotated(PI*.5)*3.8))
	for center in centers:_bf_hazard(center,1.8,72,int(tuning.boss_ward.damage),"ward","ward",Vector2.ZERO)

## The storm of the second break: `centers` circles round the hero between ring_m, placed from the hero's heading and the storm's number only.
func _bf_storm(storm: Dictionary) -> void:
	var count := int(storm.centers)
	var low := float(storm.ring_m[0]);var high := float(storm.ring_m[1])
	var heading: Vector2=hero.direction if hero.direction.length_squared()>.01 else Vector2.UP
	var base_angle := heading.angle()+float(_bf_storms)*.9
	_bf_storms+=1
	for i in count:
		var distance := low+(high-low)*float((i*2)%3)/2.0
		var spot := _clamp_point(hero.position+Vector2.from_angle(base_angle+TAU*float(i)/float(count))*distance)
		_bf_hazard(spot,float(storm.radius_m),int(storm.windup_ticks),int(storm.damage),"storm","storm",Vector2.ZERO)

func _bf_spawn_blocked() -> bool:
	return tick<_d_pause_until or (not _d_sweep.is_empty() and int(descent.after.sweep_spawn_bps)<=0)

## Escorts and adds: `amount` bodies round the hero while fewer than `cap` live. An empty mix means the zone's own mix (spawn.mix).
func _bf_spawn_group(amount: int,cap: int,mix: Dictionary) -> void:
	if _bf_spawn_blocked():return
	var count := alive_count()
	var ring_min := float(tuning.spawn.ring_min_m);var ring_max := float(tuning.spawn.ring_max_m)
	for i in amount:
		if count>=cap:break
		var kind := _bf_pick_kind(mix)
		if _spawn(kind,_spawn_point(ring_min,ring_max)):count+=1

func _bf_pick_kind(mix: Dictionary) -> String:
	if mix.is_empty():
		var rule: Dictionary=tuning.spawn.mix
		var roll := _spawn_rng.randi_range(0,99)
		if tick>=int(rule.charger_from_s)*HZ and roll>=(int(rule.charger_roll)-zone*int(rule.zone_step)):return "charger"
		if tick>=int(rule.ranged_from_s)*HZ and roll>=(int(rule.ranged_roll)-zone*int(rule.zone_step)):return "ranged"
		return "walker"
	var total := 0
	for kind in mix:total+=int(mix[kind])
	var pick := _spawn_rng.randi_range(0,total-1)
	for kind in mix:
		pick-=int(mix[kind])
		if pick<0:return String(kind)
	return "walker"

## An ordinary body died during a break: the chain is cut a little (the boss loses chip_bps_per_kill of its health, chip_cap_bps per break),
## never below the next phase's threshold.
func _bf_on_kill() -> void:
	_bf_break_kills+=1
	var rule: Dictionary=_bf.breaks[_bf_break]
	var bps := mini(int(rule.chip_bps_per_kill),int(rule.chip_cap_bps)-_bf_break_chip)
	if bps<=0 or not enemies.has(_champion_id):return
	var boss: Dictionary=enemies[_champion_id]
	var floor_hp := int(boss.max_hp_raw)*int(_bf.phases[_bf_break+1].to_hp_bps)/10000
	var cut := mini(int(boss.max_hp_raw)*bps/10000,maxi(0,int(boss.hp_raw)-floor_hp-1))
	if cut<=0:return
	boss.hp_raw=int(boss.hp_raw)-cut
	_bf_break_chip+=bps;_bf_chip+=bps
	_emit("boss_chip",boss.position,{"bps":bps,"total_bps":_bf_chip})

## BF-C: in a break (not the entrance), with tuning.boss_finale.descent_pierces_break, the descent's blows reach the out-of-play boss.
## Every other skill is still turned away. The break's length is untouched (nothing here moves _bf_until).
func _bf_descent_pierces(skill_id: String) -> bool:
	return _bf_on and _bf_state=="break" and bool(_bf.get("descent_pierces_break",false)) and skill_id.begins_with("descent.")

## Read-only state of the finale for the screen (changes nothing, draws no random number). A run without the finale: {"on": false} only.
## thresholds_bps: the health lines (ten-thousandths of the boss's life) that end phase 1, 2, ...; break_until_tick: the tick the open break ends (0 outside a break);
## to: where the boss lands (the open break's); shielded: the boss is out of play (entrance or break).
func boss_finale_view() -> Dictionary:
	if not _bf_on:return {"on":false}
	var lines: Array[int]=[]
	for phase in _bf.phases:
		if int(phase.to_hp_bps)>0:lines.append(int(phase.to_hp_bps))
	return {"on":true,"state":_bf_state,"phase_index":_bf_phase,"break_index":_bf_break if _bf_state=="break" else -1,
		"break_until_tick":_bf_until if _bf_state=="break" else 0,"to":_bf_to,"chip_bps":_bf_chip,"thresholds_bps":lines,"shielded":_shield_id>0}

## The descent's area and circles skip the out-of-play body, except the boss in a break when the descent pierces.
func _descent_skips(id_: int) -> bool:
	return id_==_shield_id and not (_bf_on and _bf_state=="break" and bool(_bf.get("descent_pierces_break",false)))

## BF3: while a phase runs, damage cannot take the boss under that phase's threshold (the rest is thrown away). The last phase has none.
func _bf_clamp_damage(e: Dictionary,damage: int) -> int:
	# BF-C: the descent's blow in a break stops one point above the NEXT phase's threshold (the chain's floor), so the next phase starts as a phase.
	if _bf_state=="break":
		var floor_hp := int(e.max_hp_raw)*int(_bf.phases[_bf_break+1].to_hp_bps)/10000
		return mini(damage,maxi(0,int(e.hp_raw)-floor_hp-1))
	if _bf_state!="phase":return damage
	var to_bps := int(_bf.phases[_bf_phase].to_hp_bps)
	if to_bps<=0:return damage
	return mini(damage,maxi(0,int(e.hp_raw)-int(e.max_hp_raw)*to_bps/10000))

## The wind-up the boss would get if it began an attack now (the next one may be the slam): the ward gap reads it.
func _bf_next_windup(warden: Dictionary) -> int:
	if _bf_on and _bf_state=="phase" and warden.get("chapter_boss",false):
		var slam: Variant=_bf.phases[_bf_phase].slam
		if slam!=null and (_bf_phase_attacks+1)%int(slam.every_attacks)==0:return int(slam.windup_ticks)
	return int(warden.definition.windup)

## The boss began a wind-up: count it, and when it is the phase's every_attacks-th, make it the slam (a long line, a long telegraph).
func _on_elite_windup(e: Dictionary) -> void:
	if not _bf_on or _bf_state!="phase" or not e.get("chapter_boss",false):return
	_bf_phase_attacks+=1
	var slam: Variant=_bf.phases[_bf_phase].slam
	if slam==null or _bf_phase_attacks%int(slam.every_attacks)!=0:return
	var windup := int(slam.windup_ticks)
	e.attack_kind="slam";e.state_until=tick+windup
	e.telegraph={"shape":"line","direction":e.attack_direction,"radius":float(slam.length_m),"length":float(slam.length_m),"width":float(slam.width_m),"rays":[],"remaining_ticks":windup}
	_emit("boss_telegraph",e.position,{"attack_id":"slam","shape":"line","position":e.position,"direction":e.attack_direction,"length":float(slam.length_m),"width":float(slam.width_m),"radius":0.0,"windup_ticks":windup})

## The slam lands: the same capsule that was telegraphed (from the boss along its heading, length x width).
func _bf_resolve_slam(e: Dictionary) -> void:
	var slam: Variant=_bf.phases[_bf_phase].slam if _bf_on else null
	if slam==null:return
	var direction: Vector2=e.attack_direction
	var half := float(slam.width_m)*.5+HERO_RADIUS
	if _segment_distance_sq(hero.position,e.position,e.position+direction*float(slam.length_m))<=half*half:
		_hero_damage(int(slam.damage)*UNIT,e.position,_source_kind_of(e),int(e.id),"slam")

func step(move: Vector2=Vector2.ZERO) -> void:
	if mode!="playing":return
	# D23 T8: the luck is taken before anything of the first tick (so before any roll, after import_starting_gear); its event comes after
	# super.step because step() clears the event list first.
	var luck_now := tick==0 and not _luck_taken
	if luck_now:_take_luck()
	super.step(move)
	if luck_now and _run_luck_bps>0:_emit("luck_locked",hero.position,{"luck_bps":_run_luck_bps,"worn_bps":_run_luck_worn,"capped":_run_luck_worn>_run_luck_bps})
	if mode!="playing":return
	if _kit_on:_kit_step()
	if mode!="playing":return
	_step_chapter_hazards()
	if mode!="playing":return
	_step_fields()
	if mode!="playing":return
	_step_rituals()
	if not _spray.is_empty() or _spray_done_boss:_spray_step()
	if mode!="playing":return
	if _elites_on:_step_elites()
	if _extras_on:_step_extras()
	var live: Array[Dictionary]=[]
	for pickup in potion_pickups:
		if potions<int(tuning.potion.carry_max) and hero.position.distance_squared_to(pickup.position)<1.6*1.6:
			potions+=1;_emit("potion_pickup",pickup.position,{"remaining":potions})
		elif tick-pickup.tick<180*HZ:live.append(pickup)
	potion_pickups=live

## Read only, for the card screen (D12 B0.11) and the measurement policies. Changes nothing. {"enabled":false} while off.
## {enabled, slots, spells:{id:{role,element,axis:{damage,reach},pairs_owned:[pair id],evolve_progress:{axis,passive,partner}}},
##  offer:{card id: growth.card_contract(card), keys in run_growth.gd} (the standing offer only), detonate:{count,extra_raw,pairs},
##  ward:{casts,hits,kills,staggers,cuts,freezes,stuns,vs_cc_hits,vs_cc_extra_raw,i2_hits,i2_extra_raw,i0_casts,i0_kills}}
func run_spells_view() -> Dictionary:
	if spells.is_empty():return {"enabled":false}
	var owned := {}
	for id_ in growth.owned_spells():
		var spell: Dictionary=spells.spells[id_]
		owned[id_]={"role":String(spell.role),"element":String(spell.element),"axis":growth.axis_levels(id_),"pairs_owned":growth.pairs_owned(id_),"evolve_progress":growth.evolve_progress(id_)}
	var offer := {}
	# Only an offer that was already drawn (get_offer()); this function never draws one, so it never moves the random stream.
	for card in growth.snapshot().offer.get("cards",[]):offer[String(card.id)]=growth.card_contract(card)
	return {"enabled":true,"slots":int(spells.slots),"spells":owned,"offer":offer,"detonate":metrics.get("detonate",{}).duplicate(true),"ward":metrics.get("ward",{}).duplicate(true)}

## What the screen needs to word the goal. `kind`: "move" (walk to the next room), "seal_kills" (done/total kills around the
## seal) or "champion" (hp/hp_max of the seal guardian, `title_key` names it). No sentence is made here.
func objective() -> Dictionary:
	var seal_kills: int=_seal_total(zone)
	var destination: Vector2=ZONES[zone]
	var result := {"zone":zone,"kind":"seal_kills","done":mini(zone_kills,seal_kills),"total":seal_kills,"hp":0,"hp_max":0,"title_key":"","destination":destination,"boss_phase":_boss_phase,"entered":_zone_entered}
	if not _zone_entered:result.kind="move"
	elif _trial_phase=="hold" or _trial_phase=="clear":
		# done = ticks left of the holding (0 while the arena is being cleared); only an enabled trial gets here.
		result.kind="trial";result.done=maxi(0,_trial_until-tick);result.total=int(tuning.rhythm.trial.hold_ticks)
	elif _champion_id>0 and enemies.has(_champion_id):
		var e: Dictionary=enemies[_champion_id]
		result.kind="boss" if _rhythm_on and zone==2 else "champion";result.hp=ceili(float(e.hp_raw)/UNIT);result.hp_max=ceili(float(e.max_hp_raw)/UNIT);result.title_key=String(e.get("title_key",""))
	return result

# ---------------------------------------------------------------- elite body and guarded sites (D13 W4-a, W5-a)
# tuning.elites.enabled gives the strong body (grade "elite": one ordinary kind made stronger, never a seal guardian) and, per zone,
# elites that walk in with the crowd. tuning.extras.enabled puts a locked shrine or chest into a zone with an elite standing guard;
# the elite's death unlocks it. Both off (the shipped file) = none of this exists in the run, its snapshot or its random streams.
# Positions, kinds and tiers are drawn from _extras_rng (its own stream, seeded in start()); drops come from _loot_rng as always.
# The read functions are extras_view() and the enemy dictionaries (grade, guard_uid, guard_state), all read only for the screen.

const EXTRAS_SEED_MASK := 0x45585452
const KINDS_ORDER := ["walker","ranged","charger"]
var _elites_on := false
var _extras_on := false
var _extras_rng := RandomNumberGenerator.new()
var _elite_made: Array[int] = [0,0,0]
var _elite_skipped := 0
var _sites: Array[Dictionary] = []
var _site_next := 0
var _buffs: Array[Dictionary] = []

var _gate_sweep_qualities: Array[String] = []

## D21 N2: read tuning.loot_flow. Off (or absent) leaves both lists empty and the 180 s rule untouched. The quality names must exist in loot.json.
func _prepare_loot_flow() -> bool:
	_kept_qualities.clear();_gate_sweep_qualities.clear();_spray.clear();_spray_done_boss=false
	# D23 T9: whether this run carries the drop pity is decided once, here, from the number the app put in before start().
	_pity_armed=loot!=null and loot.pity_on() and drop_dry_runs>=loot.pity_runs();_pity_fired=false
	_luck_taken=false;_run_luck_bps=0;_run_luck_worn=0
	if not tuning.has("loot_flow") or not bool(tuning.loot_flow.enabled):return true
	if loot==null:errors.assign(["loot_flow needs the loot tables"]);return false
	var order: Array=loot.data.qualities
	for key in ["keep_min_quality","gate_sweep_min_quality"]:
		if not order.has(tuning.loot_flow[key]):errors.assign(["loot_flow "+key+" is not a quality of loot.json"]);return false
	for i in range(order.find(tuning.loot_flow.keep_min_quality),order.size()):_kept_qualities.append(String(order[i]))
	for i in range(order.find(tuning.loot_flow.gate_sweep_min_quality),order.size()):_gate_sweep_qualities.append(String(order[i]))
	return true

## Read the two switches and check what the data names against the other data files. A guarded site needs the body, so extras
## without elites is refused (start() returns false).
func _prepare_elites() -> bool:
	_elites_on=tuning.has("elites") and bool(tuning.elites.enabled)
	_extras_on=tuning.has("extras") and bool(tuning.extras.enabled)
	if not _extras_on:return true
	if not _elites_on:errors.assign(["extras needs elites.enabled: a guarded site is guarded by an elite"]);return false
	if loot==null:errors.assign(["extras needs the loot tables"]);return false
	var extras: Dictionary=tuning.extras
	var classes: Dictionary=loot.data.treasure_classes
	for tier in extras.guarded.tiers:
		if not classes.has(tier.chest_class):errors.assign(["extras tier "+str(tier.id)+": no treasure class "+str(tier.chest_class)]);return false
	for id_ in extras.shrines.kinds:
		for stat in extras.shrines.kinds[id_].get("stats",{}):
			if not loot.data.limits.has(stat):errors.assign(["extras shrine "+str(id_)+": no gear limit for "+str(stat)]);return false
	# A site must not stand on a ritual spot (6 m clear of it).
	for site in extras.guarded.sites:
		for point in site.points:
			for def in RITUALS:
				if int(def.zone)==int(site.zone) and Vector2(float(point[0]),float(point[1])).distance_to(def.position-ZONES[int(site.zone)])<6.0:
					errors.assign(["extras site "+str(site.id)+": a point is closer than 6 m to the ritual "+str(def.id)]);return false
	return true

func _elites_reset(seed_: int) -> void:
	_extras_rng.seed=seed_ ^ EXTRAS_SEED_MASK
	_elite_made.assign([0,0,0]);_elite_skipped=0;_sites.clear();_site_next=0;_buffs.clear()

## The run's tallies; start() has made `metrics` by now. Only a run with the elite body has them, so a plain run keeps the old metrics.
## ttk_ticks: from the body's birth to its death. fight_ticks: from the first notice (a guard) or birth (a walker-in) to its death.
func _elites_metrics() -> void:
	if not _elites_on:return
	metrics.elites={"spawned":0,"killed":0,"skipped":0,"ttk_ticks":[],"fight_ticks":[]}
	if _extras_on:metrics.sites={"placed":0,"skipped":0,"engaged":0,"unlocked":0,"chests_opened":0,"shrines_taken":0,"shrines_expired":0,"locked_expired":0}

## The strong body of D13 W4-a. Health is the zone's fixed figure (times `opts.hp_bps`), the other numbers are the ordinary kind's
## times the data's bps; the experience is the zone's. `opts` of a guard: guard_uid, anchor, leash. Returns the new id, 0 when refused.
func _spawn_elite(kind: String,point: Vector2,zone_: int,opts: Dictionary={}) -> int:
	var rules: Dictionary=tuning.elites
	_spawn_tags={"grade":"elite"}
	var made := _spawn(kind,point)
	_spawn_tags={}
	if not made:return 0
	var e: Dictionary=enemies[_enemy_sequence]
	var definition: Dictionary=e.definition
	var hp := maxi(1,int(rules.hp[zone_])*int(opts.get("hp_bps",10000))/10000)
	definition.hp=hp;definition.damage=int(definition.damage)*int(rules.damage_bps)/10000
	definition.speed=float(definition.speed)*float(rules.speed_bps)/10000.0;definition.xp=int(rules.xp[zone_])
	e.hp_raw=hp*UNIT;e.max_hp_raw=e.hp_raw
	e.radius=float(e.radius)*float(rules.radius_bps)/10000.0
	e.grade="elite";e.born_tick=tick
	var guard_uid := int(opts.get("guard_uid",0))
	if guard_uid>0:
		e.guard_uid=guard_uid;e.guard_state="guard";e.guard_anchor=opts.anchor;e.guard_leash=float(opts.leash)
		e.guard_hp_seen=int(e.hp_raw);e.guard_far_since=-1;e.guard_alert_until=0;e.engaged_tick=-1
	metrics.elites.spawned=int(metrics.elites.spawned)+1
	_emit("elite_spawned",e.position,{"target_id":int(e.id),"kind":kind,"zone":zone_,"grade":"elite","affixes":[],"radius_bps":int(rules.radius_bps),"radius":float(e.radius),"guard_uid":guard_uid})
	return int(e.id)

## An elite kind by the zone's weights (walker, ranged, charger order), one draw from _extras_rng.
func _elite_kind(zone_: int) -> String:
	var weights: Dictionary=tuning.elites.kinds[zone_]
	var total := 0
	for kind in KINDS_ORDER:total+=int(weights.get(kind,0))
	var draw := _extras_rng.randi_range(1,total)
	for kind in KINDS_ORDER:
		draw-=int(weights.get(kind,0))
		if draw<=0:return kind
	return "walker"

## A point on the ordinary spawn ring, but from _extras_rng, so that switching the elites on never moves the spawn stream.
func _extras_spawn_point(min_radius: float,max_radius: float) -> Vector2:
	for attempt in 16:
		var angle := _extras_rng.randf_range(0,TAU)
		var point := _clamp_point(hero.position+Vector2(cos(angle),sin(angle))*_extras_rng.randf_range(min_radius,max_radius))
		if point.distance_squared_to(hero.position)>=min_radius*min_radius*.64:return point
	var inward: Vector2=(ZONES[zone]-hero.position).normalized()
	if inward.length_squared()<.01:inward=Vector2.LEFT
	return _clamp_point(hero.position+inward*min_radius)

## Elites that walk in (D2 2.1): the n-th of a zone comes when the zone's kills reach seal_kills*at_seal_bps[n]. A full alive cap
## holds it back to a later tick; the run opening and the seal guardian hold it back for good (the guardian: until the zone is left).
func _step_elites() -> void:
	if _op_active or not _zone_entered or seals[zone].champion_spawned:return
	var rules: Dictionary=tuning.elites
	var made := int(_elite_made[zone])
	if made>=int(rules.per_zone[zone]) or zone_kills<_seal_total(zone)*int(rules.at_seal_bps[made])/10000 or alive_count()>=int(tuning.alive_cap):return
	var point := _extras_spawn_point(float(tuning.spawn.ring_min_m),float(tuning.spawn.ring_max_m))
	if _spawn_elite(_elite_kind(zone),point,zone)>0:_elite_made[zone]=made+1

## What was due in a zone and never came is thrown away and counted (D2 2.1 elites_skipped).
func _elites_zone_left(zone_: int) -> void:
	var missing := maxi(0,int(tuning.elites.per_zone[zone_])-int(_elite_made[zone_]))
	_elite_skipped+=missing;metrics.elites.skipped=_elite_skipped

## A strong body died (any kind of kill): the tallies. The guard's fight time starts at its first notice.
func _elite_died(e: Dictionary) -> void:
	metrics.elites.killed=int(metrics.elites.killed)+1
	metrics.elites.ttk_ticks.append(tick-int(e.get("born_tick",tick)))
	var since: int=int(e.get("engaged_tick",-1)) if e.has("guard_uid") else int(e.get("born_tick",tick))
	if since>=0:metrics.elites.fight_ticks.append(tick-since)

# ---- guarded sites

func _step_extras() -> void:
	_place_next_site()
	_step_sites()
	_step_buffs()

## The next site of the list is put down when its zone is the hero's, the zone has been entered, the run opening is over and the seal
## progress has reached at_bps. A site whose zone was left (or whose seal guardian is already out) is dropped and counted.
func _place_next_site() -> void:
	var list: Array=tuning.extras.guarded.sites
	while _site_next<list.size() and int(list[_site_next].zone)<zone:
		_site_next+=1;metrics.sites.skipped=int(metrics.sites.skipped)+1
	if _site_next>=list.size():return
	var def: Dictionary=list[_site_next]
	if int(def.zone)!=zone:return
	if seals[zone].champion_spawned:
		_site_next+=1;metrics.sites.skipped=int(metrics.sites.skipped)+1;return
	if not _zone_entered or _op_active or _zone_bps()<int(def.at_bps):return
	if _place_site(def):_site_next+=1

## One draw order, always the same: the tier (only when there is a choice), the point (only when several fit), the shrine kind, the
## elite's kind. A refused body (entity limit) leaves no site and the same site is tried again next tick.
func _place_site(def: Dictionary) -> bool:
	var g: Dictionary=tuning.extras.guarded
	var tier := _pick_tier(g.tiers)
	var point := _pick_site_point(ZONES[int(def.zone)],def.points,g.distance_m)
	var shrine_kind := ""
	if def.kind=="shrine":
		var pool: Array=tuning.extras.shrines.pool[def.pool]
		shrine_kind=String(pool[_extras_rng.randi_range(0,pool.size()-1)])
	var uid := _sites.size()+1
	var body := _spawn_elite(_elite_kind(int(def.zone)),point,int(def.zone),{"hp_bps":int(tier.elite_hp_bps),"guard_uid":uid,"anchor":point,"leash":float(g.leash_m)})
	if body<=0:return false
	_sites.append({"uid":uid,"id":String(def.id),"kind":String(def.kind),"zone":int(def.zone),"shrine_kind":shrine_kind,"tier":String(tier.id),"position":point,
		"state":"locked","elite_id":body,"placed_tick":tick,"open_until":0,"buff_until":0})
	metrics.sites.placed=int(metrics.sites.placed)+1
	_emit("guard_spawned",point,{"uid":uid,"id":String(def.id),"kind":String(def.kind),"shrine_kind":shrine_kind,"tier":String(tier.id),"zone":int(def.zone),
		"elite_id":body,"radius":float(g.leash_m),"aggro":float(g.aggro_m)})
	return true

func _pick_tier(tiers: Array) -> Dictionary:
	if tiers.size()==1:return tiers[0]
	var total := 0
	for tier in tiers:total+=int(tier.weight)
	var draw := _extras_rng.randi_range(1,total)
	for tier in tiers:
		draw-=int(tier.weight)
		if draw<=0:return tier
	return tiers[tiers.size()-1]

## A candidate point (relative to the zone centre) whose distance to the hero is inside distance_m; one of several is drawn, and when
## none fits the one closest to the range is taken (no draw).
func _pick_site_point(center: Vector2,points: Array,range_m: Array) -> Vector2:
	var low := float(range_m[0]);var high := float(range_m[1])
	var fits: Array[Vector2]=[]
	var best := Vector2.ZERO;var best_gap := INF
	for p in points:
		var at := _clamp_point(center+Vector2(float(p[0]),float(p[1])))
		var d := at.distance_to(hero.position)
		var gap := maxf(0.0,maxf(low-d,d-high))
		if gap<=0.0:fits.append(at)
		elif gap<best_gap:best_gap=gap;best=at
	if fits.is_empty():return best
	if fits.size()==1:return fits[0]
	return fits[_extras_rng.randi_range(0,fits.size()-1)]

## The guard's states: guard (stands) -> alert (the first notice: close enough, or hit; it only turns and waits alert_ticks)
## -> fight (walks at the hero, never beyond its leash from the anchor) -> return (the hero stayed farther than return_far_m for
## return_after_ticks: walks home; noticing again sends it back to alert) -> guard. Runs before the enemies move. A guard whose
## site was dropped with its zone is taken out of the world here, one tick after the zone was left (never in the middle of a hit).
func _guard_step() -> void:
	var g: Dictionary=tuning.extras.guarded
	for site in _sites:
		if site.state=="gone":
			var left: Variant=enemies.get(int(site.elite_id))
			if left is Dictionary and left.hp_raw>0 and left.has("guard_uid"):
				enemies.erase(int(site.elite_id));_alive=maxi(0,_alive-1)
			continue
		if site.state!="locked":continue
		var found: Variant=enemies.get(int(site.elite_id))
		if not found is Dictionary or found.hp_raw<=0:continue
		var e: Dictionary=found
		var hit: bool=int(e.hp_raw)<int(e.guard_hp_seen)
		e.guard_hp_seen=int(e.hp_raw)
		var distance: float=e.position.distance_to(hero.position)
		var noticed: bool=hit or distance<=float(g.aggro_m)
		match String(e.guard_state):
			"guard":
				if noticed:_guard_set(site,e,"alert")
			"alert":
				if tick>=int(e.guard_alert_until):_guard_set(site,e,"fight")
			"fight":
				if distance>float(g.return_far_m):
					if int(e.guard_far_since)<0:e.guard_far_since=tick
					elif tick-int(e.guard_far_since)>=int(g.return_after_ticks):_guard_set(site,e,"return")
				else:e.guard_far_since=-1
			"return":
				if noticed:_guard_set(site,e,"alert")
				elif e.position.distance_to(e.guard_anchor)<=.05:e.position=e.guard_anchor;_guard_set(site,e,"guard")

func _guard_set(site: Dictionary,e: Dictionary,to: String) -> void:
	var from := String(e.guard_state)
	e.guard_state=to
	if to=="alert":
		e.guard_alert_until=tick+int(tuning.extras.guarded.alert_ticks)
		# The first notice is the "engaged" moment (the sound cue); later notices only change the state.
		if int(e.engaged_tick)<0:
			e.engaged_tick=tick;metrics.sites.engaged=int(metrics.sites.engaged)+1
			_emit("guard_engaged",e.position,{"uid":int(site.uid),"elite_id":int(e.id)})
	elif to=="fight" or to=="guard":e.guard_far_since=-1
	_emit("guard_state",e.position,{"uid":int(site.uid),"elite_id":int(e.id),"from":from,"to":to})

## The guard died (called from its drop): the site unlocks. A chest opens on the spot (its tier's treasure class on the floor,
## and the potions); a shrine stays open for shrines.stay_ticks.
func _guard_unlock(e: Dictionary) -> void:
	var site: Dictionary={}
	for candidate in _sites:
		if int(candidate.uid)==int(e.guard_uid):site=candidate
	if site.is_empty() or site.state!="locked":return
	metrics.sites.unlocked=int(metrics.sites.unlocked)+1
	_emit("guard_unlocked",site.position,{"uid":int(site.uid),"kind":site.kind,"shrine_kind":site.shrine_kind,"elite_id":int(e.id)})
	if site.kind=="shrine":
		site.state="open";site.open_until=tick+int(tuning.extras.shrines.stay_ticks)
		return
	site.state="taken"
	var g: Dictionary=tuning.extras.guarded
	var chest_class := ""
	for tier in g.tiers:
		if tier.id==site.tier:chest_class=String(tier.chest_class)
	var drops: Array[Dictionary]=loot.roll_class(_loot_rng,chest_class,ZONE_LEVELS[int(site.zone)],String(growth.snapshot().primary),_drop_mods(false))
	metrics.sites.chests_opened=int(metrics.sites.chests_opened)+1
	_emit("chest_opened",site.position,{"uid":int(site.uid),"guarded":true,"count":drops.size()})
	for index in drops.size():
		var spot: Vector2=site.position
		if drops.size()>1:spot+=Vector2.from_angle(TAU*float(index)/float(drops.size())+.5)*.9
		if items.size()>=MAX_GROUND_ITEMS or inventory.size()>=MAX_INVENTORY:
			metrics.overflow_items=int(metrics.get("overflow_items",0))+1;continue
		_publish_item(drops[index],spot,false,false,"chest",{"site_uid":int(site.uid)})
	for i in int(g.potions):_drop_potion(site.position+Vector2(-.9-.4*i,0))

## An open shrine is taken by walking onto it, and lapses when it has stood open too long.
func _step_sites() -> void:
	var rules: Dictionary=tuning.extras.shrines
	for site in _sites:
		if site.state!="open":continue
		if tick>=int(site.open_until):
			site.state="gone";metrics.sites.shrines_expired=int(metrics.sites.shrines_expired)+1
			_emit("shrine_expired",site.position,{"uid":int(site.uid),"kind":site.shrine_kind});continue
		if hero.position.distance_to(site.position)<=float(rules.touch_radius_m):_take_shrine(site)

func _take_shrine(site: Dictionary) -> void:
	var rules: Dictionary=tuning.extras.shrines
	var kind: Dictionary=rules.kinds[site.shrine_kind]
	var ticks := int(kind.ticks)*int(rules.guarded_ticks_bps)/10000
	site.state="taken";site.buff_until=tick+ticks
	metrics.sites.shrines_taken=int(metrics.sites.shrines_taken)+1
	# The same kind again only fills its time anew; different kinds run side by side.
	var found := false
	for buff in _buffs:
		if buff.kind==site.shrine_kind:buff.until_tick=tick+ticks;found=true
	if not found:_buffs.append({"kind":String(site.shrine_kind),"until_tick":tick+ticks})
	if kind.has("heal_bps"):hero.hp_raw=mini(int(hero.max_hp_raw),int(hero.hp_raw)+int(hero.max_hp_raw)*int(kind.heal_bps)/10000)
	_buffs_changed()
	_emit("shrine_taken",site.position,{"uid":int(site.uid),"kind":String(site.shrine_kind),"until_tick":tick+ticks,"guarded":true})

func _step_buffs() -> void:
	if _buffs.is_empty():return
	var live: Array[Dictionary]=[]
	var ended := false
	for buff in _buffs:
		if tick>=int(buff.until_tick):ended=true;_emit("buff_ended",hero.position,{"kind":String(buff.kind)})
		else:live.append(buff)
	if not ended:return
	_buffs=live
	_buffs_changed()

## The gear numbers and the grade luck take the buffs in (stats only change when a buff starts or ends).
func _buffs_changed() -> void:
	_recompute_gear()
	if _grace_on and growth.grades_on():
		var luck: Dictionary=growth.snapshot().grace.luck
		var mul := int(tuning.grace.grades.luck.shrine_mul_bps) if _buff_kind_active("luck") else 10000
		growth.set_grade_luck(mul,int(luck.reward_grade),int(luck.gear_bps))

func _buff_kind_active(kind: String) -> bool:
	for buff in _buffs:
		if buff.kind==kind:return true
	return false

## Gear totals plus the stats of the running shrine buffs, each touched stat cut to the loot grammar's limit.
func _apply_buff_stats(stats: Dictionary) -> void:
	if _buffs.is_empty():return
	var kinds: Dictionary=tuning.extras.shrines.kinds
	var touched := {}
	for buff in _buffs:
		var add: Dictionary=kinds[buff.kind].get("stats",{})
		for stat in add:
			stats[stat]=int(stats.get(stat,0))+int(add[stat]);touched[stat]=true
	var limits: Dictionary=loot.data.limits
	for stat in touched:stats[stat]=clampi(int(stats[stat]),int(limits[stat][0]),int(limits[stat][1]))

## D23 T8: the drop mods of one roll_class call. `shrine` = ordinary kills and elites, which also take the shrine of luck's mods; the run's luck
## (fixed at the first tick) goes to every call that passes through here. {} when there is neither, which is the plain draw.
func _drop_mods(shrine: bool) -> Dictionary:
	var mods: Dictionary=_luck_mods() if shrine else {}
	if _run_luck_bps>0:
		mods=mods.duplicate(true);mods["luck_bps"]=_run_luck_bps
		metrics.luck.rolls=int(metrics.luck.rolls)+1
	return mods

## D23 T8: the luck of the gear worn at the first tick, cut at the cap, kept for the whole run; and, with the grace grades on, the gear's
## share of the grade luck at the same moment. Worn-gear sums only (no shrine buff).
func _take_luck() -> void:
	_luck_taken=true
	var totals: Dictionary=_gear_totals(equipped)
	_run_luck_worn=int(totals.get("luck_bps",0))
	_run_luck_bps=mini(_run_luck_worn,loot.luck_cap_bps()) if loot!=null and loot.luck_on() else 0
	if _run_luck_bps>0:metrics["luck"]={"rolls":0}
	if _grace_on and growth.grades_on():
		var grace_share := mini(int(totals.get("grace_luck_bps",0)),10000)
		if grace_share>0:
			var luck: Dictionary=growth.snapshot().grace.luck
			set_grace_luck(int(luck.shrine_mul_bps),int(luck.reward_grade),grace_share)

## Read only: {"enabled","worn_bps" (worn now, may change during the run),"cap_bps","run_bps" (fixed at the first tick),"locked"}.
func luck_state() -> Dictionary:
	var on: bool=loot!=null and loot.luck_on()
	return {"enabled":on,"worn_bps":int(_gear_totals(equipped).get("luck_bps",0)),"cap_bps":loot.luck_cap_bps() if loot!=null else 0,"run_bps":_run_luck_bps,"locked":_luck_taken}

## The shrine of luck's drop mods for roll_class (ordinary kills and elites only); {} without it, which is the plain draw.
func _luck_mods() -> Dictionary:
	if _buffs.is_empty():return {}
	var kinds: Dictionary=tuning.extras.shrines.kinds
	for buff in _buffs:
		var rule: Dictionary=kinds[buff.kind]
		if rule.has("drop_bps"):return {"drop_bps":int(rule.drop_bps),"quality_bps":rule.get("quality_bps",{}).duplicate()}
	return {}

## The zone was left: what is still locked disappears with its guard (no death, no drop, no seal kill) and an unused open shrine lapses.
## The elite itself is removed at the start of the next tick (_guard_step).
func _sites_zone_left(left_zone: int) -> void:
	for site in _sites:
		if int(site.zone)!=left_zone:continue
		if site.state=="locked":
			site.state="gone";metrics.sites.locked_expired=int(metrics.sites.locked_expired)+1
			_emit("guard_expired",site.position,{"uid":int(site.uid),"kind":site.kind,"elite_id":int(site.elite_id)})
		elif site.state=="open":
			site.state="gone";metrics.sites.shrines_expired=int(metrics.sites.shrines_expired)+1
			_emit("shrine_expired",site.position,{"uid":int(site.uid),"kind":site.shrine_kind})
		elif site.state=="taken":site.state="gone"

## Read only, for the screen and the sound. Changes nothing, draws nothing. {"enabled":false} while the extras are off.
## {enabled, sites:[{uid, id, kind "shrine"|"chest", zone, shrine_kind ("" for a chest), tier, position, state "locked"|"open"|"taken"|"gone",
##  elite_id, guard_state ("guard"|"alert"|"fight"|"return" while locked and alive, else ""), ticks_left (an open shrine: until it lapses;
##  a taken shrine: until its buff ends; else 0), leash_m, aggro_m}], buffs:[{kind, until_tick, left_ticks}]}
## A chest's content is never in it (the hidden part of the bet). A chest goes locked -> taken on the tick its guard dies.
func extras_view() -> Dictionary:
	if not _extras_on:return {"enabled":false}
	var g: Dictionary=tuning.extras.guarded
	var list: Array[Dictionary]=[]
	for site in _sites:
		var left := 0
		if site.state=="open":left=maxi(0,int(site.open_until)-tick)
		elif site.state=="taken" and site.kind=="shrine":left=maxi(0,int(site.buff_until)-tick)
		var state := ""
		var body: Variant=enemies.get(int(site.elite_id))
		if site.state=="locked" and body is Dictionary and body.hp_raw>0:state=String(body.guard_state)
		list.append({"uid":int(site.uid),"id":String(site.id),"kind":String(site.kind),"zone":int(site.zone),"shrine_kind":String(site.shrine_kind),"tier":String(site.tier),
			"position":site.position,"state":String(site.state),"elite_id":int(site.elite_id),"guard_state":state,"ticks_left":left,"leash_m":float(g.leash_m),"aggro_m":float(g.aggro_m)})
	var running: Array[Dictionary]=[]
	for buff in _buffs:running.append({"kind":String(buff.kind),"until_tick":int(buff.until_tick),"left_ticks":maxi(0,int(buff.until_tick)-tick)})
	return {"enabled":true,"sites":list,"buffs":running}

# ---------------------------------------------------------------- descent (D15 A, chapter1/data/descent.json)
# The ultimate: a gauge that only events fill, a call that holds the core still (mode "descent", no tick), and a sweep (D24:
# fragments of fire / an ice storm that breaks / forty bolts) that kills the ordinary enemies on the screen rectangle. Off (the
# shipped file says enabled:false) = `descent` is empty, request_descent() is false, no state, no random number, no snapshot key.
# Nothing here draws from any random stream: order is distance, then id, and the irregular places come from an integer hash of
# the run's seed (descent_hash). The crown (tree) and the grace ("descent boost") are only named in descent.json, not read.

const Descent = preload("res://chapter1/core/descent.gd")
const DESCENT_STATUSES := ["heat","chill","shock"]
## The document of this run (validated, enabled only); {} = off.
var descent: Dictionary = {}
var _pending_descent: Dictionary = {}
var _shared_descent: Dictionary = {}
var _shared_descent_loaded := false
var _d_element := ""
var _d_gauge := 0
var _d_uses := 0
var _d_ready := false
var _d_wasted := 0
var _d_strong_carry := 0
var _d_combo_tick := -1
var _d_combo_sum := 0
var _d_iframe_until := 0
var _d_pause_until := 0
## Gauge that overflowed while ready (D24 1st edition 8.5): it lifts the strong bodies' share at the next call. Read-only view: hold_bonus_bps.
var _d_hold_bonus := 0
## The tick of the last rhythm wave_crest (for the view's crest flag). Not in the snapshot's contract; a read-only cue.
var _d_crest_tick := -100000
var _d_sweep: Dictionary = {}
## Ground that stays after a sweep (ember fire spots, the frost ground): [{kind, pos, radius, until, next}]. Empty while off.
var _d_burn: Array = []
## Seed of the descent's integer hash. Derived from the run's seed in start(); not part of the snapshot.
var _d_seed := 0
var _d_right := Vector2.RIGHT
var _d_up := Vector2.UP
const DESCENT_SEED_MASK := 0x44455343
## What the sweep hit in the tick being processed (flushed as one descent_strike event). Not in the snapshot.
var _d_strike_ids: Array = []
var _d_strike_pos: Array = []
var _d_strike_marks: Array = []

## Park a descent document for the next start() (before start()). It is validated like the file; a rejected one changes nothing.
func set_descent(candidate: Dictionary) -> bool:
	var loader = Descent.new()
	if not loader.replace_document(candidate):
		errors.assign(loader.errors);return false
	_pending_descent=loader.snapshot()
	return true

## The parked document, else the shipped file (read once; a missing file means off). Only an enabled one switches the descent on.
func _prepare_descent() -> bool:
	descent={}
	var document: Dictionary=_pending_descent
	if document.is_empty():
		if not _shared_descent_loaded:
			if FileAccess.file_exists(Descent.DEFAULT_PATH):
				var loader = Descent.new()
				if not loader.load_file(Descent.DEFAULT_PATH):
					errors.assign(loader.errors);push_error("Descent failed to load: "+str(errors));return false
				_shared_descent=loader.snapshot()
			_shared_descent_loaded=true
		document=_shared_descent
	if document.is_empty() or not bool(document.enabled):return true
	descent=document.duplicate(true)
	return true

func _descent_reset() -> void:
	_d_gauge=0;_d_uses=0;_d_ready=false;_d_wasted=0;_d_strong_carry=0;_d_combo_tick=-1;_d_combo_sum=0;_d_iframe_until=0;_d_pause_until=0;_d_hold_bonus=0;_d_crest_tick=-100000
	_d_sweep={};_d_burn=[];_d_element="";_d_strike_ids=[];_d_strike_pos=[];_d_strike_marks=[]
	if descent.is_empty():return
	_d_element=String(_primary_id).trim_prefix("chapter1.skill.")
	if not _d_element in Descent.ELEMENTS:descent={};return
	var angle := deg_to_rad(float(descent.area.right_deg))
	_d_right=Vector2(cos(angle),sin(angle));_d_up=Vector2(_d_right.y,-_d_right.x)
	metrics.descent={"uses":0,"gauge_in":0,"wasted":0,"kills":0,"strong_hits":0,"strong_damage_raw":0,"marks_taken":0,"refunded":0,"ready_ticks":[],"call_ticks":[]}

## The share lift of the overflowed gauge: step_bps for every per_points, at most max_bps.
func _descent_bonus_bps() -> int:
	var rule: Dictionary=descent.hold_bonus
	return mini(int(rule.max_bps),_d_hold_bonus/int(rule.per_points)*int(rule.step_bps))

## Ordinary bodies on the screen rectangle around the hero (read only).
func _descent_screen_normals() -> int:
	var n := 0
	for id_ in enemies:
		var e: Dictionary=enemies[id_]
		if e.hp_raw>0 and e.generation==_epoch and _enemy_role(e)=="normal" and _descent_inside(e.position,hero.position):n+=1
	return n

## The ordinary spawn's interval during a sweep: after.sweep_spawn_bps of its pace (10000 = as it is).
func _descent_spawn_interval(ticks: int) -> int:
	if descent.is_empty() or _d_sweep.is_empty():return ticks
	var bps := int(descent.after.sweep_spawn_bps)
	if bps==10000 or bps<=0:return ticks
	return maxi(1,ticks*10000/bps)

func _descent_cost() -> int:
	var costs: Array=descent.cost
	return int(costs[mini(_d_uses,costs.size()-1)])

func _descent_area_view() -> Dictionary:
	return {"right_deg":float(descent.area.right_deg),"half_w_m":float(descent.area.half_w_m),"half_h_m":float(descent.area.half_h_m)}

# ---- the integer hash (D24 4.6): no random stream is drawn
static func _lowbias32(v: int) -> int:
	var x := v & 0xffffffff
	x ^= x >> 16
	x = (x*0x7feb352d) & 0xffffffff
	x ^= x >> 15
	x = (x*0x846ca68b) & 0xffffffff
	x ^= x >> 16
	return x

## h(use, k, salt) of a seed: the seed, then each of the three mixed in turn. A 32-bit value.
static func descent_hash(seed_: int,use: int,k: int,salt: int) -> int:
	var x := _lowbias32(seed_)
	x = _lowbias32(x ^ (use & 0xffffffff))
	x = _lowbias32(x ^ (k & 0xffffffff))
	return _lowbias32(x ^ (salt & 0xffffffff))

func _dhash(use: int,k: int,salt: int) -> int:
	return descent_hash(_d_seed,use,k,salt)

## [0,1)
func _dunit(use: int,k: int,salt: int) -> float:
	return float(_dhash(use,k,salt))/4294967296.0

## The screen rectangle around a centre (the hero): |u| <= half_w+edge and |v| <= half_h+edge along the data's right/up axes.
func _descent_inside(p: Vector2,center: Vector2) -> bool:
	var d := p-center
	var a: Dictionary=descent.area
	var edge := float(a.edge_m)
	return absf(d.dot(_d_right))<=float(a.half_w_m)+edge and absf(d.dot(_d_up))<=float(a.half_h_m)+edge

func _descent_boss_alive() -> bool:
	return zone==2 and _champion_id>0 and enemies.has(_champion_id)

## Read only, for the screens and the sound (D15 A6.4). Changes nothing. {"enabled":false} while off.
## {enabled, element, gauge, cost_now, ratio_bps (0..10000), ready, state "charging"|"ready"|"hold"|"sweep", uses,
##  first (is this the run's first descent: the one being called or swept, else the one to come), sweep_left_ticks, iframe_until_tick,
##  area {right_deg, half_w_m, half_h_m} (D24: the screen rectangle), sweep_ticks (this element's length),
##  hold_bonus_bps (what the overflowed gauge adds to a strong body's share at the next call), screen_normals (ordinary bodies on the
##  screen rectangle), crest (ready and the screen is full: screen_normals >= cue.normals_min, or a rhythm wave_crest within cue.crest_ticks)}
func descent_view() -> Dictionary:
	if descent.is_empty():return {"enabled":false}
	var state := "charging"
	if not _d_sweep.is_empty():state="sweep"
	elif _descent_hold:state="hold"
	elif _d_ready:state="ready"
	var cost := _descent_cost()
	var first := (_d_uses==1) if state=="sweep" else (_d_uses==0)
	var screen_normals := _descent_screen_normals()
	var crest := _d_ready and state=="ready" and (screen_normals>=int(descent.cue.normals_min) or tick-_d_crest_tick<=int(descent.cue.crest_ticks))
	return {"enabled":true,"element":_d_element,"gauge":_d_gauge,"cost_now":cost,"ratio_bps":clampi(_d_gauge*10000/maxi(1,cost),0,10000),"ready":_d_ready,"state":state,
		"uses":_d_uses,"first":first,"sweep_left_ticks":maxi(0,int(_d_sweep.until_tick)-tick) if state=="sweep" else 0,"iframe_until_tick":_d_iframe_until,
		"area":_descent_area_view(),"sweep_ticks":int(descent.ultimates[_d_element].sweep_ticks),
		"hold_bonus_bps":_descent_bonus_bps(),"screen_normals":screen_normals,"crest":crest}

## Call the descent. Accepted only while playing with a ready gauge and no sweep running; then the core stands still
## (mode "descent") until release_descent(). The screen shows its cut-in in between; nothing changes meanwhile.
func request_descent() -> bool:
	if descent.is_empty() or mode!="playing" or not _d_ready or _descent_hold or not _d_sweep.is_empty():return false
	var blocked: Array=descent.blocked_phases
	if "trial" in blocked and _trial_phase=="hold":return false
	if "boss" in blocked and _descent_boss_alive():return false
	var normals := 0;var strongs := 0;var marks := 0
	for id_ in _descent_in_area(hero.position):
		var e: Dictionary=enemies[id_]
		if _enemy_role(e)=="normal":normals+=1
		else:strongs+=1
		marks+=_descent_marks_of(e)
	_descent_hold=true
	_refresh_mode()
	metrics.descent.call_ticks.append(tick)
	_emit("descent_called",hero.position,{"element":_d_element,"index":_d_uses+1,"variant":"long" if _d_uses==0 else "short","center":hero.position,"area":_descent_area_view(),
		"normals_in_reach":normals,"strongs_in_reach":strongs,"marks_in_reach":marks,"hold_bonus_bps":_descent_bonus_bps(),"in_trial":_trial_phase=="hold","boss_alive":_descent_boss_alive()})
	return true

## The cut-in is over: the gauge is spent and the sweep starts with the next tick. Only in mode "descent".
func release_descent() -> bool:
	if not _descent_hold or mode!="descent":return false
	var cfg: Dictionary=descent.ultimates[_d_element]
	var ticks := int(cfg.sweep_ticks)
	_descent_hold=false
	_d_gauge=0;_d_ready=false;_d_uses+=1
	metrics.descent.uses=_d_uses
	_d_sweep={"element":_d_element,"start_tick":tick,"until_tick":tick+ticks,"hit_ids":[],"strong_paid":{},"strong_total":{},"frozen":[],"booked":[],"next_k":0,
		"next_step":int(cfg.first_step) if _d_element=="arc" else 0,"last_bolt_step":-1,"recent":[],
		"kills":0,"strong_hits":0,"strong_damage_raw":0,"marks_taken":0,"trial_kills":0,"boss_raw":0,"boss_max_raw":0,
		"kills_total":0,"normals_at_call":0,"entered":0,"capped":0,"seen":{},"bonus_bps":_descent_bonus_bps()}
	_d_hold_bonus=0
	for id_ in enemies:
		var e: Dictionary=enemies[id_]
		if e.hp_raw>0 and e.generation==_epoch and _enemy_role(e)=="normal" and _descent_inside(e.position,hero.position):
			_d_sweep.seen[id_]=true;_d_sweep.normals_at_call=int(_d_sweep.normals_at_call)+1
	# No blow lands from the tick after the release until the sweep is over and for after.iframe_ticks beyond it.
	_d_iframe_until=tick+ticks+int(descent.after.iframe_ticks)
	_invulnerable_until=maxi(_invulnerable_until,_d_iframe_until)
	_refresh_mode()
	return true

## What overflows the gauge is kept as the hold bonus up to hold_bonus.cap_points; only what is over that is thrown away (wasted).
func _descent_overflow(points: int) -> void:
	var room := maxi(0,int(descent.hold_bonus.cap_points)-_d_hold_bonus)
	var kept := mini(points,room)
	_d_hold_bonus+=kept
	if points>kept:_d_wasted+=points-kept;metrics.descent.wasted=_d_wasted

## Points into the gauge. A full gauge takes nothing more: the points go to the hold bonus.
func _descent_add(points: int) -> void:
	if points<=0:return
	var tally: Dictionary=metrics.descent
	if _d_ready:
		_descent_overflow(points);return
	var cost := _descent_cost()
	var taken := mini(points,cost-_d_gauge)
	_d_gauge+=taken;tally.gauge_in=int(tally.gauge_in)+taken
	if points>taken:_descent_overflow(points-taken)
	if _d_gauge>=cost:
		_d_ready=true
		tally.ready_ticks.append(tick)
		_emit("descent_ready",hero.position,{"uses":_d_uses,"cost":cost})

## Combination points (a basic hit on a controlled enemy, a detonation) count at most combo_cap_per_tick per tick.
func _descent_combo(points: int) -> void:
	if _d_combo_tick!=tick:_d_combo_tick=tick;_d_combo_sum=0
	var room := maxi(0,int(descent.points.combo_cap_per_tick)-_d_combo_sum)
	var counted := mini(points,room)
	_d_combo_sum+=counted
	_descent_add(counted)

func _descent_kill_points() -> int:
	var by_beat: Dictionary=descent.points.kill_by_beat
	var id_ := ""
	if _rhythm_on:
		if _descent_boss_alive():id_="boss"
		elif _trial_phase=="hold":id_="trial"
		elif _beat_index>=0:id_=String(tuning.rhythm.beats[_beat_index].id)
	return int(by_beat.get(id_,descent.points.kill_default))

func _descent_score(type: String,details: Dictionary) -> void:
	var points: Dictionary=descent.points
	match type:
		"death":
			match String(details.get("role","normal")):
				"normal":_descent_add(_descent_kill_points())
				"elite":_descent_add(int(points.elite_kill))
				"champion":_descent_add(int(points.champion_kill))
		"hit":
			if details.has("vs_cc"):_descent_combo(int(points.vs_cc_hit))
			var target: Variant=enemies.get(int(details.get("target_id",0)))
			if target is Dictionary and target.elite and int(target.max_hp_raw)>0:
				# One percent of the guardian's life is worth strong_damage_per_pct; the rest is carried to the next hit.
				_d_strong_carry+=int(details.dealt_raw)*10000/int(target.max_hp_raw)
				var pct := _d_strong_carry/100
				if pct>0:_d_strong_carry-=pct*100;_descent_add(pct*int(points.strong_damage_per_pct))
		"detonate":_descent_combo(int(points.detonate))

## Nearest first (equal distance: the smaller id).
func _descent_sort(found: Array[int],center: Vector2) -> Array[int]:
	found.sort_custom(func(a: int,b: int) -> bool:
		var da: float=enemies[a].position.distance_squared_to(center)
		var db: float=enemies[b].position.distance_squared_to(center)
		return a<b if is_equal_approx(da,db) else da<db)
	return found

## Alive enemies on the screen rectangle around a centre, nearest first.
func _descent_in_area(center: Vector2) -> Array[int]:
	var found: Array[int]=[]
	for id_ in enemies:
		var e: Dictionary=enemies[id_]
		if e.hp_raw>0 and e.generation==_epoch and not _descent_skips(int(id_)) and _descent_inside(e.position,center):found.append(int(id_))
	return _descent_sort(found,center)

## Alive enemies within a circle of the world, nearest first.
func _descent_near(center: Vector2,radius: float) -> Array[int]:
	var limit := radius*radius
	var found: Array[int]=[]
	for id_ in enemies:
		var e: Dictionary=enemies[id_]
		if e.hp_raw>0 and e.generation==_epoch and not _descent_skips(int(id_)) and e.position.distance_squared_to(center)<=limit:found.append(int(id_))
	return _descent_sort(found,center)

## Stacks of heat, chill and shock still running on an enemy (only a run with the spell composition has any).
func _descent_marks_of(e: Dictionary) -> int:
	var table: Dictionary=e.get("status",{})
	var n := 0
	for key in DESCENT_STATUSES:
		var entry: Variant=table.get(key)
		if entry is Dictionary and int(entry.n)>0 and tick<int(entry.until):n+=int(entry.n)
	return n

func _descent_take_marks(e: Dictionary) -> int:
	var n := _descent_marks_of(e)
	if e.has("status"):
		for key in DESCENT_STATUSES:e.status.erase(key)
	return n

## An enemy's windup is cut: the attack does not come, the body recovers.
func _descent_cut_windup(e: Dictionary) -> void:
	if e.state=="windup":
		e.state="recover";e.state_until=tick+int(descent.strong.cut_windup_ticks);e.telegraph={}

## What the element leaves on an ordinary body past the trial's cap (it is not killed).
func _descent_cap_control(e: Dictionary) -> void:
	var cfg: Dictionary=descent.ultimates[_d_element]
	if _d_element=="frost":
		e.frozen_until=maxi(int(e.frozen_until),tick+int(cfg.after_freeze_ticks))
	elif _d_element=="arc":
		e.stunned_until=maxi(int(e.get("stunned_until",0)),tick+int(cfg.normal_stun_ticks))

## A strong body that the sweep touched (the first time, and again when its share is complete: final).
func _descent_strong_control(e: Dictionary,role: String,final: bool) -> void:
	var rule: Dictionary=descent.strong
	var cfg: Dictionary=descent.ultimates[_d_element]
	if role=="champion":e.stunned_until=maxi(int(e.get("stunned_until",0)),tick+int(rule.champion_stun_ticks))
	elif role=="boss":e.staggered_until=maxi(int(e.get("staggered_until",0)),tick+int(rule.boss_stagger_ticks))
	if _d_element=="arc":e.stunned_until=maxi(int(e.get("stunned_until",0)),tick+int(cfg.strong_stun_ticks))
	elif _d_element=="frost" and final:e.frozen_until=maxi(int(e.frozen_until),tick+int(cfg.after_freeze_ticks))

## One blow through the normal damage path: skill_id "descent.<element>", no children, no burst, no shatter, no status.
func _descent_blow(id_: int,amount: int) -> void:
	_cast_sequence+=1
	var effects := {"damage_raw":amount,"proc_depth":0,"death_burst":0,"shatter_count":0,"radius_cm":0,"slow_bps":0,"freeze_stacks":0,"pierce":0,"hit_budget":512,"cooldown_ticks":0,"projectiles":0,"chain_targets":0,"branches":0}
	var context := {"uid":_cast_sequence,"skill_id":"descent."+_d_element,"effects":effects,"remaining_hits":512,"hit_ids":[],"evolved":false}
	var before := kills
	_damage_enemy(id_,context,0)
	if kills>before:
		_d_sweep.kills=int(_d_sweep.kills)+1;metrics.descent.kills=int(metrics.descent.kills)+1

## The sweep reaches one enemy. An ordinary body loses all it has left (once; past the trial's cap it only takes the element's
## control). A strong one is paid a part of its share (frac, in bps of the share; -1 = all that is left): the share is
## max life x (the role's bps + marks) and is never exceeded (4.3, 4.4). final = the closing blow of the sweep.
func _descent_touch(id_: int,frac: int,final: bool=false) -> void:
	var sw: Dictionary=_d_sweep
	if not enemies.has(id_):return
	var e: Dictionary=enemies[id_]
	if e.hp_raw<=0:return
	var first: bool=not id_ in sw.hit_ids
	var role := _enemy_role(e)
	if role=="normal" and not first:return
	var marks := 0
	if first:
		sw.hit_ids.append(id_)
		marks=_descent_take_marks(e)
		if marks>0:
			sw.marks_taken=int(sw.marks_taken)+marks;_d_strike_marks.append(e.position)
			metrics.descent.marks_taken=int(metrics.descent.marks_taken)+marks
	if not id_ in _d_strike_ids:
		_d_strike_ids.append(id_);_d_strike_pos.append(e.position)
	if role=="normal":
		if _trial_phase=="hold":
			if int(sw.trial_kills)>=int(descent.normal.trial_kill_cap):sw.capped=int(sw.capped)+1;_descent_cap_control(e);return
			sw.trial_kills=int(sw.trial_kills)+1
		_descent_blow(id_,int(e.hp_raw))
		return
	var rule: Dictionary=descent.strong
	if first:
		var total := (int(rule[role+"_bps"])+mini(marks*int(rule.per_mark_bps),int(rule.marks_cap_bps)))*(10000+int(sw.bonus_bps))/10000
		if role=="boss":total=mini(total,int(rule.boss_cap_bps))
		sw.strong_total[id_]=total
		sw.strong_paid[id_]=0
		sw.strong_hits=int(sw.strong_hits)+1;metrics.descent.strong_hits=int(metrics.descent.strong_hits)+1
		_descent_cut_windup(e)
	var paid := int(sw.strong_paid[id_])
	var part := 10000-paid if frac<0 else mini(frac,10000-paid)
	var full := maxi(1,int(e.max_hp_raw)*int(sw.strong_total[id_])/10000)
	var owed := full*(paid+part)/10000-full*paid/10000
	sw.strong_paid[id_]=paid+part
	if owed>0:
		var before := int(e.hp_raw)
		_descent_blow(id_,owed)
		var dealt := before-maxi(0,int(e.hp_raw))
		sw.strong_damage_raw=int(sw.strong_damage_raw)+dealt;metrics.descent.strong_damage_raw=int(metrics.descent.strong_damage_raw)+dealt
		if role=="boss":sw.boss_raw=int(sw.boss_raw)+dealt;sw.boss_max_raw=int(e.max_hp_raw)
		# BF-C: the blow landed on the boss while it was out of play in a break (the screen reads it; `damage` is raw, after the threshold's hold).
		if role=="boss" and id_==_shield_id and _bf_state=="break":_emit("boss_break_struck",e.position,{"index":_bf_break,"target_id":id_,"skill_id":"descent."+_d_element,"element":_d_element,"damage":dealt,"position":e.position})
	elif role=="boss":sw.boss_max_raw=int(e.max_hp_raw)
	if e.hp_raw>0 and (first or final):_descent_strong_control(e,role,final)

## One descent_strike per phase and tick: what was touched since the last flush. More than 64 bodies are split into events of 64
## (so that every kill is named in the event of its tick). force = the event is sent even when nobody was touched.
func _descent_flush(phase: String,step: int,extra: Dictionary={},force: bool=false) -> void:
	if _d_strike_ids.is_empty() and not force:return
	var center: Vector2=hero.position
	var parts := maxi(1,ceili(float(_d_strike_ids.size())/64.0))
	for i in parts:
		var details := {"element":_d_element,"phase":phase,"step":step,"center":center,"positions":_d_strike_pos.slice(i*64,i*64+64),
			"target_ids":_d_strike_ids.slice(i*64,i*64+64),"marks_at":_d_strike_marks.slice(i*32,i*32+32)}
		details.merge(extra)
		_emit("descent_strike",center,details)
	_d_strike_ids=[];_d_strike_pos=[];_d_strike_marks=[]

## Every enemy shot in flight is removed (and forgotten by _hostile_src). Floor strikes of the boss are not shots and stay.
func _descent_clear_shots() -> Dictionary:
	var kept: Array[Dictionary]=[]
	var count := 0
	var positions: Array=[]
	for p in projectiles:
		if p.hostile:
			count+=1
			if positions.size()<64:positions.append(p.position)
			_hostile_src.erase(int(p.uid))
		else:kept.append(p)
	if count>0:projectiles=kept
	return {"count":count,"positions":positions}

## Once per tick before anything moves: the sweep's step (tick - start_tick, 1 on the tick after the release).
func _step_descent() -> void:
	if not _d_burn.is_empty():_descent_burn_tick()
	if _d_sweep.is_empty():return
	var sw: Dictionary=_d_sweep
	var s := tick-int(sw.start_tick)
	if s<1:return
	var cfg: Dictionary=descent.ultimates[_d_element]
	# Ordinary bodies that come onto the screen during the sweep (counted once each).
	for id_ in enemies:
		var e: Dictionary=enemies[id_]
		if e.hp_raw>0 and e.generation==_epoch and not sw.seen.has(id_) and _enemy_role(e)=="normal" and _descent_inside(e.position,hero.position):
			sw.seen[id_]=true;sw.entered=int(sw.entered)+1
	var cleared := _descent_clear_shots()
	if s==1:
		_emit("descent_released",hero.position,{"element":_d_element,"center":hero.position,"area":_descent_area_view(),"sweep_ticks":int(cfg.sweep_ticks),
			"cleared_shots":int(cleared.count),"cleared_positions":cleared.positions})
	match _d_element:
		"ember":_descent_ember(s,cfg)
		"frost":_descent_frost(s,cfg)
		"arc":_descent_arc(s,cfg)
	if s>=int(cfg.sweep_ticks):_descent_finish(s)

## EMBER (5.2). s=1: fourteen fragments are booked at world places (the grid's cells, each with a hash-placed spot, plus the aimed
## ones on the strong bodies); each falls on its land_step and strikes the circle it lands in; the last tick takes the screen.
func _descent_ember(s: int,cfg: Dictionary) -> void:
	var sw: Dictionary=_d_sweep
	if s==1:_descent_book(cfg)
	var booked: Array=sw.booked
	while int(sw.next_k)<booked.size() and int(booked[int(sw.next_k)].land_step)<=s:
		var piece: Dictionary=booked[int(sw.next_k)]
		sw.next_k=int(sw.next_k)+1
		for id_ in _descent_near(piece.pos,float(piece.radius)):
			_descent_touch(id_,int(cfg.next_hit_share_bps) if id_ in sw.hit_ids else int(cfg.first_hit_share_bps))
		_descent_flush("impact",s,{"k":int(piece.k),"pos":piece.pos,"radius_m":float(piece.radius),"big":bool(piece.big)},true)
		if not spells.is_empty() and int(cfg.burn_heat)>0 and spells.statuses.has("heat"):
			_d_burn.append({"kind":"ember","pos":piece.pos,"radius":float(piece.radius),"until":tick+int(cfg.burn_ticks),"next":tick+int(cfg.burn_every_ticks)})
	if s>=int(cfg.sweep_ticks):
		for id_ in _descent_in_area(hero.position):_descent_touch(id_,-1,true)
		_descent_flush("firestorm",s,{},true)

## Book the fragments (once, on s=1). k is the order of landing. Cells: grid cols x rows over the rectangle, a hash-placed spot in each.
func _descent_book(cfg: Dictionary) -> void:
	var sw: Dictionary=_d_sweep
	var use := _d_uses
	var area: Dictionary=descent.area
	var center: Vector2=hero.position
	var hw := float(area.half_w_m)
	var hh := float(area.half_h_m)
	var cols := int(cfg.grid[0])
	var rows := int(cfg.grid[1])
	var cells := cols*rows
	var cell_w := 2.0*hw/float(cols)
	var cell_h := 2.0*hh/float(rows)
	var spots: Array[Vector2]=[]
	for i in cells:
		var u := -hw+(float(i%cols)+_dunit(use,i,1))*cell_w
		var v := -hh+(float(i/cols)+_dunit(use,i,2))*cell_h
		spots.append(center+_d_right*u+_d_up*v)
	# The aimed ones: boss, then guardian, then elite; the same rank by the smaller id. Without a strong body: the fullest cells.
	var strong_ids: Array[int]=[]
	var normal_sum: Array[Vector2]=[]
	var normal_n: Array[int]=[]
	for i in cells:
		normal_sum.append(Vector2.ZERO);normal_n.append(0)
	for id_ in _descent_in_area(center):
		var e: Dictionary=enemies[id_]
		if _enemy_role(e)=="normal":
			var d: Vector2=e.position-center
			var cx := clampi(int(floorf((d.dot(_d_right)+hw)/cell_w)),0,cols-1)
			var cy := clampi(int(floorf((d.dot(_d_up)+hh)/cell_h)),0,rows-1)
			normal_sum[cy*cols+cx]+=e.position;normal_n[cy*cols+cx]+=1
		else:strong_ids.append(id_)
	var rank := {"boss":0,"champion":1,"elite":2}
	strong_ids.sort_custom(func(a: int,b: int) -> bool:
		var ra: int=rank[_enemy_role(enemies[a])]
		var rb: int=rank[_enemy_role(enemies[b])]
		return a<b if ra==rb else ra<rb)
	var fullest: Array[int]=[]
	for i in cells:fullest.append(i)
	fullest.sort_custom(func(a: int,b: int) -> bool:
		return a<b if normal_n[a]==normal_n[b] else normal_n[a]>normal_n[b])
	var aimed := int(cfg.aimed)
	var aim_pos: Array[Vector2]=[]
	var aim_id: Array[int]=[]
	for j in aimed:
		if j<strong_ids.size():
			aim_pos.append(enemies[strong_ids[j]].position);aim_id.append(strong_ids[j])
		else:
			var cell: int=fullest[(j-strong_ids.size())%cells]
			aim_pos.append(normal_sum[cell]/float(normal_n[cell]) if normal_n[cell]>0 else spots[cell]);aim_id.append(0)
	# Which grid pieces are big: the smallest hashes (salt 3). The landing order of the grid pieces: salt 4, aimed ones at 0, 6, 12...
	var by_big: Array=[]
	var by_order: Array=[]
	for i in cells:
		by_big.append([_dhash(use,i,3),i]);by_order.append([_dhash(use,i,4),i])
	by_big.sort()
	by_order.sort()
	var big_cells := {}
	for n in mini(int(cfg.big_count)-aimed,cells):big_cells[int(by_big[n][1])]=true
	var order: Array=[]
	for pair in by_order:order.append(int(pair[1]))
	for j in aimed:order.insert(mini(j*6,order.size()),-1-j)
	var gap: Array=cfg.gap_ticks
	var step := int(cfg.first_land_step)
	var booked: Array=[]
	for k in order.size():
		if k>0:step=mini(int(cfg.last_land_step),step+int(gap[0])+_dhash(use,k,5)%(int(gap[1])-int(gap[0])+1))
		var piece: int=order[k]
		var big := true
		var pos: Vector2
		var target := 0
		if piece<0:
			pos=aim_pos[-1-piece];target=aim_id[-1-piece]
		else:
			pos=spots[piece];big=big_cells.has(piece)
		booked.append({"k":k,"pos":pos,"land_step":step,"radius":float(cfg.big_radius_m) if big else float(cfg.small_radius_m),"big":big,"aimed_id":target})
	sw.booked=booked
	var fragments: Array=[]
	for piece in booked:
		fragments.append({"k":int(piece.k),"pos":piece.pos,"land_step":int(piece.land_step),"radius_m":float(piece.radius),"big":bool(piece.big),"aimed_id":int(piece.aimed_id)})
	_emit("descent_book",center,{"element":"ember","fragments":fragments})

## FROST (6.2). onset_step: everything on the screen freezes (an ordinary body until the break, a strong one briefly); a body that
## comes in later freezes on the tick it is there; pulses pay the strong ones a sixteenth; the last tick breaks them all at once.
func _descent_frost(s: int,cfg: Dictionary) -> void:
	var sw: Dictionary=_d_sweep
	var sweep := int(cfg.sweep_ticks)
	var onset := int(cfg.onset_step)
	if s>=onset and s<sweep:
		for id_ in _descent_in_area(hero.position):
			if id_ in sw.frozen:continue
			sw.frozen.append(id_)
			var e: Dictionary=enemies[id_]
			if _enemy_role(e)=="normal":e.frozen_until=maxi(int(e.frozen_until),int(sw.start_tick)+sweep+1)
			else:
				e.frozen_until=maxi(int(e.frozen_until),tick+int(cfg.strong_freeze_ticks));_descent_cut_windup(e)
			_d_strike_ids.append(id_);_d_strike_pos.append(e.position)
		_descent_flush("onset" if s==onset else "freeze",s,{},s==onset)
	var from := int(cfg.pulse_from_step)
	if s>=from and (s-from)%int(cfg.pulse_every_ticks)==0 and (s-from)/int(cfg.pulse_every_ticks)<int(cfg.pulse_count):
		var alive_frozen := 0
		for id_ in sw.frozen:
			if enemies.has(int(id_)) and enemies[int(id_)].hp_raw>0:
				alive_frozen+=1
				if _enemy_role(enemies[int(id_)])!="normal":_descent_touch(int(id_),int(cfg.pulse_share_bps))
		_descent_flush("pulse",s,{"n":(s-from)/int(cfg.pulse_every_ticks)+1,"frozen_count":alive_frozen},true)
	if s>=sweep:
		for id_ in sw.frozen.duplicate():_descent_touch(int(id_),-1,true)
		for id_ in _descent_in_area(hero.position):_descent_touch(id_,-1,true)
		_descent_flush("break",s,{},true)

## ARC (7.2). bolts fall at hash-spaced steps (a gap of 0 means the same tick) on hash-chosen points of the screen, at least
## min_apart_m from the last three; one near a body not yet struck is pulled onto it; each strikes a small circle and forks to the
## nearest bodies not yet struck. The last tick takes the screen.
func _descent_arc(s: int,cfg: Dictionary) -> void:
	var sw: Dictionary=_d_sweep
	var gap: Array=cfg.gap_ticks
	while int(sw.next_k)<int(cfg.bolts) and int(sw.next_step)<=s:
		var k := int(sw.next_k)
		var step := int(sw.next_step)
		sw.next_k=k+1
		if k+1<int(cfg.bolts):
			sw.next_step=mini(int(cfg.last_step),step+int(gap[0])+_dhash(_d_uses,k+1,6)%(int(gap[1])-int(gap[0])+1))
		var burst: bool=int(sw.last_bolt_step)==step or (k+1<int(cfg.bolts) and int(sw.next_step)==step)
		sw.last_bolt_step=step
		_descent_bolt(k,s,cfg,burst)
	if s>=int(cfg.sweep_ticks):
		for id_ in _descent_in_area(hero.position):_descent_touch(id_,-1,true)
		_descent_flush("finale",s,{},true)

func _descent_bolt(k: int,s: int,cfg: Dictionary,burst: bool) -> void:
	var sw: Dictionary=_d_sweep
	var center: Vector2=hero.position
	var hw := float(descent.area.half_w_m)
	var hh := float(descent.area.half_h_m)
	var pos := center
	for attempt in int(cfg.retries)+1:
		pos=center+_d_right*((_dunit(_d_uses,k,10+attempt*2)*2.0-1.0)*hw)+_d_up*((_dunit(_d_uses,k,11+attempt*2)*2.0-1.0)*hh)
		var apart := true
		for other in sw.recent:
			if pos.distance_to(other)<=float(cfg.min_apart_m):apart=false;break
		if apart:break
	# Pulled onto the nearest body not struck yet within snap_m.
	var best := 0
	var best_d := INF
	var snap := float(cfg.snap_m)
	for id_ in enemies:
		var e: Dictionary=enemies[id_]
		if e.hp_raw<=0 or e.generation!=_epoch or id_ in sw.hit_ids:continue
		var d: float=e.position.distance_to(pos)
		if d<=snap and (d<best_d-0.000001 or (absf(d-best_d)<=0.000001 and int(id_)<best)):best=int(id_);best_d=d
	if best>0:pos=enemies[best].position
	sw.recent.append(pos)
	if sw.recent.size()>3:sw.recent.pop_front()
	for id_ in _descent_near(pos,float(cfg.splash_m)):_descent_touch(id_,int(cfg.touch_share_bps))
	var forks: Array=[]
	if int(cfg.forks)>0:
		var reach: Array[int]=[]
		var limit := float(cfg.fork_m)*float(cfg.fork_m)
		for id_ in enemies:
			var e: Dictionary=enemies[id_]
			if e.hp_raw>0 and e.generation==_epoch and not id_ in sw.hit_ids and e.position.distance_squared_to(pos)<=limit:reach.append(int(id_))
		_descent_sort(reach,pos)
		var targets: Array[int]=[]
		for n in mini(int(cfg.forks),reach.size()):
			targets.append(reach[n]);forks.append([pos,enemies[reach[n]].position])
		for id_ in targets:_descent_touch(id_,int(cfg.touch_share_bps))
	_descent_flush("bolt",s,{"k":k,"pos":pos,"forks":forks,"burst":burst},true)

## The end tick: orbs and ground items on the screen come to the hero, the report event, the frost ground, and the marks it took
## give part of the gauge back for the next one.
func _descent_finish(s: int) -> void:
	var sw: Dictionary=_d_sweep
	var cfg: Dictionary=descent.ultimates[_d_element]
	_vacuum_orbs("descent")
	var center: Vector2=hero.position
	var left: Array[Dictionary]=[]
	for item in items:
		if inventory.size()<MAX_INVENTORY and _descent_inside(item.position,center):
			item.collected=true;inventory.append(item);metrics.picked_items+=1
			_emit("item_pickup",hero.position,{"item":item.duplicate(true),"swept":true,"by":"descent"})
		else:left.append(item)
	items=left
	var refund := mini(int(sw.marks_taken)*int(descent.points.marks_refund_per_stack),int(descent.points.marks_refund_cap))
	var boss_share := int(sw.boss_raw)*10000/maxi(1,int(sw.boss_max_raw)) if int(sw.boss_max_raw)>0 else 0
	# Cleared ratio: the ordinary bodies seen on the screen (at the call and entering) that are dead by now, whoever killed them,
	# over those seen minus the ones the trial's cap left standing.
	var dead := 0
	for id_ in sw.seen:
		if not enemies.has(id_) or int(enemies[id_].hp_raw)<=0:dead+=1
	var seen_n: int=int(sw.normals_at_call)+int(sw.entered)
	var clear_ratio := clampi(dead*10000/maxi(1,seen_n-int(sw.capped)),0,10000)
	_emit("descent_end",center,{"element":_d_element,"kills":int(sw.kills),"strong_hits":int(sw.strong_hits),"strong_damage_raw":int(sw.strong_damage_raw),
		"marks_taken":int(sw.marks_taken),"refund":refund,"duration_ticks":s,"boss_share_bps":boss_share,
		"kills_total":int(sw.kills_total),"normals_at_call":int(sw.normals_at_call),"entered":int(sw.entered),"clear_ratio_bps":clear_ratio})
	# The breath starts here: nothing ordinary is sent in for spawn_pause_ticks after the end tick.
	_d_pause_until=tick+int(descent.after.spawn_pause_ticks)
	# The frost ground stays over the screen the break covered (the slow is a plain field; the chill needs the spell composition).
	if _d_element=="frost":
		_d_burn.append({"kind":"frost","pos":center,"radius":0.0,"until":tick+int(cfg.ground_ticks),"next":tick+int(cfg.pulse_every_ticks)})
	_d_sweep={}
	metrics.descent.refunded=int(metrics.descent.refunded)+refund
	_descent_add(refund)

## The ground that stays: ember fire spots add heat in their circle, the frost ground slows and chills the screen it covered.
func _descent_burn_tick() -> void:
	var keep: Array=[]
	for spot in _d_burn:
		if tick>=int(spot.until):continue
		keep.append(spot)
		var cfg: Dictionary=descent.ultimates[String(spot.kind)]
		var chill_due := false
		var heat_due := false
		if spot.kind=="ember":
			heat_due=tick>=int(spot.next)
			if heat_due:spot.next=int(spot.next)+int(cfg.burn_every_ticks)
		else:
			chill_due=tick>=int(spot.next)
			if chill_due:spot.next=int(spot.next)+int(cfg.pulse_every_ticks)
		var ids: Array[int]=[]
		if spot.kind=="ember":
			if heat_due:ids=_descent_near(spot.pos,float(spot.radius))
		else:ids=_descent_in_area(spot.pos)
		for id_ in ids:
			var e: Dictionary=enemies[id_]
			if spot.kind=="frost":
				if tick<int(e.slow_until):e.slow_bps=maxi(int(e.slow_bps),int(cfg.ground_slow_bps));e.slow_until=maxi(int(e.slow_until),tick+8)
				else:e.slow_until=tick+8;e.slow_bps=int(cfg.ground_slow_bps)
				if chill_due and not spells.is_empty() and spells.statuses.has("chill"):_descent_status_add(e,"chill",int(cfg.ground_chill),"descent.frost")
			elif not spells.is_empty() and spells.statuses.has("heat"):_descent_status_add(e,"heat",int(cfg.burn_heat),"descent.ember")
	if keep.size()!=_d_burn.size():_d_burn=keep

func _descent_status_add(e: Dictionary,key: String,amount: int,src: String) -> void:
	var rule: Dictionary=spells.statuses[key]
	if not e.has("status"):e.status={}
	var entry: Dictionary=e.status.get(key,{})
	if entry.is_empty() or tick>=int(entry.until):entry={"n":0,"src":src,"until":0,"by":{}}
	var add := mini(amount,maxi(0,int(rule.max)-int(entry.n)))
	if add>0:entry.n=int(entry.n)+add;entry.by[src]=int(entry.by.get(src,0))+add
	entry.src=src;entry.until=tick+int(rule.expire_ticks)
	e.status[key]=entry

func snapshot() -> Dictionary:
	var result: Dictionary=super.snapshot()
	result.chapter={"zone":zone,"zone_kills":zone_kills,"seals":seals.duplicate(true),"potions":potions,"pending_rewards":pending_rewards.duplicate(true),"rituals":rituals.duplicate(true),"history":history.duplicate(true),"boss_phase":_boss_phase,"hazards":chapter_hazards.duplicate(true)}
	result.world_uniques36=_world_uniques36.keys()
	result.world_uniques36.sort()
	# Rhythm state exists in the snapshot only while the rhythm is on; a run without it keeps the old snapshot.
	if _rhythm_on:
		result.rhythm={"beat":_beat_index,"beat_tick":_beat_tick,"wave_index":_wave_index,"in_lull":_in_lull,"taste_done":_taste_done,"rest_until":_rest_until,
			"hp_bps":_spawn_hp_bps,"trial":_trial_phase,"trial_until":_trial_until,"trial_clear_until":_trial_clear_until,"trial_center":_trial_center}
		if _threat_on:result.rhythm.threat={"squad_wave":_squad_wave,"heading":_wave_heading,"jitter":_crest_jitter.duplicate()}
		if _kb_on:
			var window_list: Array=[]
			for entry in _kb_list:window_list.append([int(entry.tick),int(entry.xp),int(entry.pts),entry.pos])
			result.rhythm.kill_burst=window_list
		if _opening_on:result.rhythm.opening={"step":_op_step if _op_active else -1,"step_tick":(tick-_op_step_start) if _op_active else 0,"step_kills":_op_step_kills if _op_active else 0,"heading":_op_heading if _op_active else Vector2.ZERO,"done":_op_done}
	# The elite body's and the guarded sites' state exist only while their switches are on; otherwise there is no key.
	if _pity_armed:result.chapter.pity={"armed":true,"fired":_pity_fired}
	# The finale's state exists only in a run with boss_finale on (the golden case "boss-finale"); otherwise there is no key.
	if _bf_on:
		result.boss_finale={"state":_bf_state,"phase_index":_bf_phase,"break_index":_bf_break,"break_until":_bf_until if _bf_state=="break" else 0,"until":_bf_until,"chip_bps":_bf_chip,
			"break_chip_bps":_bf_break_chip,"break_kills":_bf_break_kills,"to":_bf_to,"land_started":_bf_land_started,"next_adds":_bf_next_adds,"next_escort":_bf_next_escort,
			"next_storm":_bf_next_storm,"storms":_bf_storms,"phase_attacks":_bf_phase_attacks,"shield_id":_shield_id}
	if _run_luck_bps>0:result.chapter.luck={"run_bps":_run_luck_bps,"worn_bps":_run_luck_worn}
	if not _spray.is_empty():
		var groups: Array=[]
		for group in _spray:groups.append({"source":group.source,"start":group.start,"arrive":group.arrive,"uids":group.uids.duplicate(),"notable":group.notable,"boss":group.boss})
		result.chapter.spray=groups
	if _elites_on:result.chapter.elites={"made":_elite_made.duplicate(),"skipped":_elite_skipped}
	if _extras_on:result.chapter.extras={"sites":_sites.duplicate(true),"buffs":_buffs.duplicate(true),"next_site_index":_site_next}
	# The descent's state exists only in a run whose descent.json is on (D15 A6.2); a run without it keeps the old snapshot.
	if not descent.is_empty():
		result.descent={"gauge":_d_gauge,"uses":_d_uses,"cost_now":_descent_cost(),"ready":_d_ready,"hold":_descent_hold,"sweep":_d_sweep.duplicate(true),
			"wasted":_d_wasted,"hold_bonus":_d_hold_bonus,"strong_carry":_d_strong_carry,"pause_until":_d_pause_until,"burn":_d_burn.duplicate(true)}
	# The composition's own state (ring pulses still to come) exists only while it is on; axes and evolution partners are in growth.
	if not spells.is_empty():result.spells={"pulses":_ring_pending.duplicate(true)}
	# ET-A: the kit's core state exists only in a run whose element is on (the cards are in growth.kit); otherwise there is no key.
	if _kit_on:result.kit_core=_kit_state()
	# D19 C1-f: the pace clock exists only while grace.pace is configured.
	if _pace_on:result.pace={"level":_pace_level,"since":_pace_since,"carry":_pace_carry}
	# The grace gap's own clock exists only while the grace block is on.
	if _grace_on:result.grace_gap={"last_choice":_choice_tick}
	# Build keys exist only in a run that was given a build; without one the snapshot is the old one.
	if _build_active:
		var pairs: Array=[];var ids: Array=_build.ranks.keys();ids.sort()
		for id_ in ids:pairs.append([id_,int(_build.ranks[id_])])
		result.build={"character_id":_build.character_id,"tree_id":_build.tree_id,"tree_revision":int(_build.tree_revision),"ranks":pairs,"character_level":int(_build.character_level),"character_xp":int(_build.character_xp)}
		result.progress=_progress.duplicate(true)
		if not _field_rule.is_empty():result.fields=_fields.duplicate(true)
	return result


## D23 T1-B: the sum of the worn gear's condition damage lines that hold for this enemy right now (0 without such gear).
func _condition_bps(e: Dictionary,frozen: bool) -> int:
	var total := 0
	if int(_gear_stats.get("vs_elite_bps",0))>0 and _enemy_role(e)!="normal":total+=int(_gear_stats.vs_elite_bps)
	if int(_gear_stats.get("vs_frozen_bps",0))>0 and frozen:total+=int(_gear_stats.vs_frozen_bps)
	if int(_gear_stats.get("vs_marked_bps",0))>0:
		for slot in _mark_owners.size():
			if tick<int(e.get(MARK_KEYS[slot],0)):total+=int(_gear_stats.vs_marked_bps);break
	if int(_gear_stats.get("after_dash_bps",0))>0 and _after_dash_active():total+=int(_gear_stats.after_dash_bps)
	if int(_gear_stats.get("moving_damage_bps",0))>0 and _moving_active():total+=int(_gear_stats.moving_damage_bps)
	var cap := int(tuning.get("stat_caps",{}).get("condition_damage_bps",0))
	return mini(total,cap) if cap>0 else total

func _damage_enemy(id_: int,context: Dictionary,depth: int) -> void:
	if not _terminal_mode.is_empty() or not enemies.has(id_) or int(context.remaining_hits)<=0:return
	var e: Dictionary=enemies[id_]
	if e.hp_raw<=0 or e.generation!=_epoch:return
	# The boss out of play (finale entrance or break) turns every blow away: nothing is spent, nothing is dealt.
	if id_==_shield_id and not _bf_descent_pierces(String(context.skill_id)):_shield_block_event(String(context.skill_id));return
	if context.skill_id=="chapter1.skill.arc":
		if id_ in context.hit_ids and int(context.get("rehit",-1))!=id_:return
		if not id_ in context.hit_ids:context.hit_ids.append(id_)
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
	# D23 T1-B: the worn gear's condition lines (elite, frozen, marked, after a dash, on the move) add up to ONE multiplier, cut at
	# stat_caps.condition_damage_bps. It sits before the spell composition and the mark resonance, so the mark credit stays exact.
	var condition_bps := 0 if bool(context.get("reflect",false)) else _condition_bps(e,was_frozen)
	if condition_bps>0:damage=damage*(10000+condition_bps)/10000
	# Spell composition: a direct hit that finds a status another spell put on the enemy is multiplied (detonation), then a
	# spell with vs_strong_bps deals that share to guardians. Both come before the mark so the mark credit stays exact.
	var spell: Dictionary={}
	var detonation: Dictionary={}
	var detonation_extra := 0
	var is_ring := false
	var cc_class := ""
	var cc_extra := 0
	if not spells.is_empty():
		spell=spells.spells.get(context.skill_id,{})
		if not spell.is_empty():
			is_ring=String(spell.role)=="ring"
			# A ring hits harder the closer the enemy stands (falloff_floor_bps 10000: not at all).
			if is_ring:damage=maxi(1,damage*_falloff_bps(effect,e)/10000)
			if depth==0:
				detonation=_detonation_of(e,spell,String(context.skill_id))
				if not detonation.is_empty():
					var before_detonation := damage
					damage=maxi(1,damage*int(detonation.mult_bps)/10000)
					detonation_extra=damage-before_detonation
					# I2: the detonation may let the ring strike more targets (block_targets).
					if int(detonation.block_targets)>0:context.ring_extra=int(context.get("ring_extra",0))+int(detonation.block_targets)
				# I1: a basic spell's hit on an enemy another spell controls deals the biggest matching vs_cc bonus (one, not stacked).
				if not is_ring and spell.has("vs_cc"):
					var best_bps := 0
					for cls in spell.vs_cc:
						if int(spell.vs_cc[cls])>best_bps and _cc_active(e,String(cls),String(context.skill_id)):best_bps=int(spell.vs_cc[cls]);cc_class=String(cls)
					if best_bps>0:
						var before_cc := damage
						damage=maxi(1,damage*(10000+best_bps)/10000)
						cc_extra=damage-before_cc
			if e.elite and spell.has("vs_strong_bps"):damage=maxi(1,damage*int(spell.vs_strong_bps)/10000)
			# A ring's proportional hit on a strong enemy: a share of its current life, never taking that share below the floor.
			if is_ring and e.elite and int(effect.get("strong_pct_bps",0))>0:
				var floor_hp := int(e.max_hp_raw)*int(effect.get("strong_floor_bps",0))/10000
				var share := mini(int(e.hp_raw)*int(effect.strong_pct_bps)/10000,int(e.hp_raw)-damage-floor_hp)
				if share>0:damage+=share
	# Mark resonance: a primary hit on an enemy that a secondary skill marked deals mark_bps more per live mark.
	# The composition switches it off (its own aim bonus replaces it) unless the document says marks_resonance.
	var mark_bps := int(tuning.marks.mark_bps)
	if not spells.is_empty() and not bool(spells.get("marks_resonance",false)):mark_bps=0
	var assisting: Array[int]=[]
	var unmarked := damage
	var hp_before := int(e.hp_raw)
	if mark_bps>0 and context.skill_id==_primary_id:
		for slot in _mark_owners.size():
			if tick<int(e.get(MARK_KEYS[slot],0)):assisting.append(slot)
		if not assisting.is_empty():damage=damage*(10000+mark_bps*assisting.size())/10000
	# BF3: a phase's health threshold holds (this line is the only one that makes the finale's damage differ; off, it never runs).
	if _bf_on and e.get("chapter_boss",false):damage=_bf_clamp_damage(e,damage)
	var result: Dictionary=Resolver.damage(damage,int(e.hp_raw))
	e.hp_raw=int(result.hp_after_raw);metrics.damage_raw+=int(result.total_raw)
	metrics.hits[context.skill_id]=int(metrics.hits.get(context.skill_id,0))+1
	if context.skill_id=="chapter1.skill.frost" or (not spell.is_empty() and spell.element=="frost" and int(effect.slow_bps)>0):
		e.slow_until=tick+(int(spell.get("slow_ticks",100)) if not spell.is_empty() else 100);e.slow_bps=int(effect.slow_bps)
		if not spell.is_empty():_set_cc_src(e,"slowed",String(context.skill_id))
		# With the composition the chill status is the freeze counter (see _apply_statuses); without it the old stacks.
		if spell.is_empty() and int(effect.freeze_stacks)>0:
			e.freeze_stacks+=1;e.freeze_expires=tick+180
			if int(e.freeze_stacks)>=int(effect.freeze_stacks):
				e.frozen_until=tick+(12 if e.elite else 75);e.freeze_stacks=0
	if not spell.is_empty():
		if not detonation.is_empty() and bool(detonation.consume):e.status.erase(detonation.status)
		if depth==0 and e.hp_raw>0:
			_apply_statuses(e,spell,effect,int(detonation.get("freeze_bonus",0)),String(context.skill_id))
			if is_ring:_apply_ring_control(e,effect,detonation,String(context.skill_id))
		if is_ring and depth==0:_ward_add("hits")
		if cc_extra>0:_ward_add("vs_cc_hits");_ward_add("vs_cc_extra_raw",cc_extra)
	var cold_death: bool=evolved_cold and e.hp_raw<=0 and depth==0 and int(effect.proc_depth)>0
	var shatter: bool=int(effect.shatter_count)>0 and (was_frozen or cold_death)
	# dealt_raw is the life really taken off (the overflow past death is not in it); damage_raw stays the full figure.
	var hit_details := {"target_id":id_,"skill_id":context.skill_id,"damage_raw":int(result.total_raw),"dealt_raw":int(result.hp_before_raw)-int(result.hp_after_raw),"frozen":tick<int(e.frozen_until),"shatter":shatter,
		"radius_cm":int(effect.radius_cm),"blast_radius_cm":int(effect.radius_cm)if context.skill_id=="chapter1.skill.ember"else 0,"cast_uid":context.uid,"evolved":context.evolved}
	if not detonation.is_empty():hit_details.detonate=true
	if cc_extra>0:hit_details.vs_cc=cc_class
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
	if not detonation.is_empty():
		_emit("detonate",e.position,{"target_id":id_,"by_skill":context.skill_id,"status":detonation.status,"src_skill":detonation.src,"stacks":int(detonation.stacks),"cast_uid":context.uid,"extra_raw":detonation_extra,"pair":String(detonation.pair)})
		var pair_id := String(detonation.pair)
		if is_ring:_ward_add("i2_hits");_ward_add("i2_extra_raw",detonation_extra)
		var tally: Dictionary=metrics.detonate
		tally.count=int(tally.count)+1;tally.extra_raw=int(tally.extra_raw)+detonation_extra
		var row: Dictionary=tally.pairs.get(pair_id,{"count":0,"extra_raw":0})
		row.count=int(row.count)+1;row.extra_raw=int(row.extra_raw)+detonation_extra
		tally.pairs[pair_id]=row
	if mark_bps>0 and context.skill_id!=_primary_id and e.hp_raw>0:
		var owner_slot: int=_mark_owners.find(context.skill_id)
		if owner_slot>=0:e[MARK_KEYS[owner_slot]]=tick+int(tuning.marks.mark_ticks)
	# ET-A: with the kit on, a hit of the signature arc leaves the shock status (a stack on a big body) on a body that is still alive.
	if _kit_on and e.hp_raw>0 and depth==0 and context.skill_id==_primary_id:_kit_shock(e,1)
	# Shock is separate from cold: no freeze stacks, cold tint or shatter credit.
	# Primary chain contacts only; secondary death explosions cannot restun.
	if e.hp_raw>0 and context.skill_id=="chapter1.skill.arc" and depth==0 and tick>=int(e.get("shock_ready_tick",0)):
		var duration: int=ARC_ELITE_STUN_TICKS36 if e.elite else ARC_STUN_TICKS36
		e.stunned_until=tick+duration
		if not spells.is_empty():_set_cc_src(e,"stunned",String(context.skill_id))
		e.shock_ready_tick=tick+(ARC_ELITE_IMMUNITY36 if e.elite else ARC_STUN_IMMUNITY36)
		_emit("stun",e.position,{"target_id":id_,"skill_id":context.skill_id,"until_tick":e.stunned_until,"duration_ticks":duration,"elite":e.elite})
	if e.hp_raw>0:return
	e.state="dead";_alive-=1;e.dead_tick=tick;e.telegraph={};kills+=1
	_emit("death",e.position,{"target_id":id_,"kind":e.kind,"elite":e.elite,"skill_id":context.skill_id,"role":_enemy_role(e)})
	if _kit_on:_kit_on_death(e)
	if is_ring:_ward_add("kills")
	if context.get("aim","")=="kind" and e.kind in spell.get("prefer_kinds",[]):_ward_add("i0_kills")
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

# ---------------------------------------------------------------- element kit (ET-A, D-element-trees: stack, lay, burst)
# Switch: element_kit.json "enabled" + "enabled_elements" (or set_element_kit() for a tool). With it off (the shipped value) nothing below runs, draws
# a random number or reaches the snapshot. The kit replaces the old growth of its element (growth.set_kit) and uses no other element's skills.
# Every number is in the document (element_kit.json); the code only knows the roles: the signature skill stacks `shock` (a stack count on a big
# body), the lay skill plants rods on a big body, the burst skill sends one bolt from every shocked body to the rod (or, with none, the big body's own
# stacks). Targets are chosen by distance, health and id only.

const KIT_STORM_ID := "chapter1.skill.arc_storm"
var _pending_kit: Dictionary = {}
var _pending_kit_set := false
var _kit_open_mode: Variant = ""
var _kit_doc: Dictionary = {}
var _kit_build_cards: Array = []
var _kit_rods: Array[int] = []
var _kit_next_rod := 0
var _kit_next_overload := 0
var _kit_next_storm := 0
var _kit_next_discharge := 0
var _kit_next_stride := 0
var _kit_shell_next := 0
var _kit_bolt_count := 0
var _kit_ev_tick := -1
var _kit_ev_stacked := 0
var _kit_ev_bolts := 0
var _kit_merged_n := 0
var _kit_merged_raw := 0
var _kit_crest_tick := -1000000
var _kit_zone_seen := 0
var _kit_zone_start := 0
var _kit_evo_events := 0

## Park a kit document for the next start() (before start(); validated like the file). `{}` removes the parked one (the shipped file decides again).
## A rejected document changes nothing. The element kit and run_spells (or grace) never run together: start() refuses that pair.
func set_element_kit(candidate: Variant) -> bool:
	if candidate is Dictionary and candidate.is_empty():
		_pending_kit={};_pending_kit_set=false;return true
	var loader = ElementKit.new()
	if not loader.replace_document(candidate):errors.assign(loader.errors);return false
	_pending_kit=loader.snapshot();_pending_kit_set=true
	return true

## Which kit-opened cards this run may draw, when no permanent build decides: "none", "all" (every card a tree node opens) or a list of card ids.
## "" (the default) lets the build's tree decide. For tools that do not play a profile (measurement, tests).
func set_kit_open(mode: Variant) -> bool:
	if mode is String and mode in ["","none","all"]:_kit_open_mode=mode;return true
	if mode is Array:
		for id_ in mode:
			if not id_ is String:errors.assign(["Kit open list needs card ids"]);return false
		_kit_open_mode=mode.duplicate();return true
	errors.assign(["Unknown kit tree mode"]);return false

## The progression document and the skill trees with the element trees of the kit's enabled elements added (a copy). Without an element on, the shared ones.
func _kit_tables() -> Dictionary:
	var doc: Dictionary=_pending_kit if _pending_kit_set else ElementKit.current()
	var extra := ElementKit.trees_for(doc,_shared_progression)
	if extra.has("error"):
		push_error(String(extra.error));extra={}
	if extra.is_empty():return {"doc":_shared_progression,"trees":_shared_trees}
	var trees: Dictionary=_shared_trees.duplicate()
	trees.merge(extra)
	return {"doc":ElementKit.patch_progression(_shared_progression,extra),"trees":trees}

func _prepare_kit(primary: String) -> bool:
	_kit_on=false;_kit={};_kit_doc={};_kit_hp=0;_kit_move_bps=0;_kit_shell_until=0;_kit_shell_reduce=0
	_kit_rods=[];_kit_next_rod=0;_kit_next_overload=0;_kit_next_storm=0;_kit_next_discharge=0;_kit_next_stride=0;_kit_shell_next=0;_kit_bolt_count=0
	_kit_ev_tick=-1;_kit_ev_stacked=0;_kit_ev_bolts=0;_kit_merged_n=0;_kit_merged_raw=0
	_kit_v16=false;_kit_crest_tick=-1000000;_kit_zone_seen=0;_kit_zone_start=0;_kit_evo_events=0
	var doc: Dictionary=_pending_kit if _pending_kit_set else ElementKit.current()
	if doc.is_empty() or not ElementKit.is_on_for(primary,doc):return true
	if not spells.is_empty():errors.assign(["The element kit cannot run together with run_spells"]);return false
	if tuning.has("grace") and bool(tuning.grace.enabled):errors.assign(["The element kit cannot run together with grace"]);return false
	_kit_on=true;_kit_doc=doc
	_kit=doc.elements[ElementKit.element_of_skill(primary)].duplicate(true)
	_kit_v16=doc.offer.has("floor") or doc.offer.has("evolve_floor") or doc.offer.has("spine_share") or _kit.chain.has("prefer_unshocked")
	for id_ in _kit.skills:
		if _kit.skills[id_].has("bolt_rule") or _kit.skills[id_].has("zone"):_kit_v16=true
	return true

## After the run's growth is configured: hand the kit to growth (cards, offer rules, the cards the tree opened) and open the counters.
func _kit_install() -> bool:
	if not growth.set_kit(_kit_doc.offer,_kit,_kit_doc.fillers,_kit_open_list()):errors.assign(growth.errors);return false
	metrics.kit={"overloads":[],"bolts":0,"self_bolts":0,"sparks":0,"storms":0,"rods":0,"rebounds":0,"heals":0,"shells":0,"strides":0,"discharges":0,"pops":0,"merged_bolts":0}
	return true

## D-element-trees 16.1: the crises of this tick (the lag is the growth's own to read). Only a document with a floor or a late floor asks.
func _kit_offer_prepare() -> void:
	var offer: Dictionary=_kit_doc.offer
	var rule: Variant=offer.get("floor")
	var crisis := {"rhythm":_rhythm_on,"survival":false,"big":false,"crowd":false}
	if rule is Dictionary and bool(rule.enabled):
		crisis.survival=int(hero.hp_raw)*10000<int(rule.survival.hp_bps)*int(hero.max_hp_raw)
		var guard_near := false
		for id_ in enemies:
			if enemies[id_].elite and int(enemies[id_].hp_raw)>0:guard_near=true;break
		if not guard_near and not seals[zone].champion_spawned and zone_kills>0:
			# The guardian is near when the seal's kills still to come fit in `within_ticks` at the pace of this zone so far.
			var left := _seal_total(zone)-zone_kills
			guard_near=left*maxi(1,tick-_kit_zone_start)<=zone_kills*int(rule.big.within_ticks)
		crisis.big=guard_near
		crisis.crowd=alive_count()*10000>=_kit_alive_cap()*int(rule.crowd.alive_bps) or tick-_kit_crest_tick<=int(rule.crowd.crest_ticks)
	if rule is Dictionary or offer.get("evolve_floor") is Dictionary:growth.set_kit_crisis(crisis)

## The ceiling of ordinary bodies of the beat that is running (the rhythm's, the opening step's or the trial's), else the tuning's.
func _kit_alive_cap() -> int:
	var cap := int(tuning.alive_cap)
	if not _rhythm_on:return cap
	if _op_active and _op_step>=0 and _op_step<_op_list.size():return mini(cap,int(_op_list[_op_step].alive_cap))
	if _trial_phase=="hold" and tuning.rhythm.has("trial"):return mini(cap,int(tuning.rhythm.trial.alive_cap))
	if _beat_index>=0 and _beat_index<tuning.rhythm.beats.size():return mini(cap,int(tuning.rhythm.beats[_beat_index].alive_cap))
	return cap

## After a hand is made: the floor's counts into the measurement.
func _kit_offer_done() -> void:
	var stats := growth.kit_floor_stats()
	if not stats.is_empty() and metrics.has("kit"):metrics.kit.floor=stats

## An event the kit reads: the crest of a wave (the crowd crisis), the one the late floor of the evolution waits for, and the late floor's own.
func _kit_note_event(type: String,details: Dictionary) -> void:
	if type=="wave_crest":_kit_crest_tick=tick
	if type=="evolve_floor_opened" and metrics.has("kit"):metrics.kit.evolve_floor_tick=tick
	var rule: Variant=_kit_doc.offer.get("evolve_floor")
	if not rule is Dictionary or not bool(rule.enabled) or type!=String(rule.after.event):return
	if rule.after.has("beat") and String(details.get("beat",""))!=String(rule.after.beat):return
	if rule.after.has("zone") and int(details.get("zone",-1))!=int(rule.after.zone):return
	_kit_evo_events+=1
	if _kit_evo_events>=int(rule.after.n):growth.kit_arm_evolve_floor()

func _kit_open_list() -> Array:
	var out: Array=[]
	if _kit_open_mode is Array:return _kit_open_mode.duplicate()
	if String(_kit_open_mode)=="all":
		for card in _kit.cards:
			if String(card.open)!="base":out.append(String(card.id))
		return out
	if String(_kit_open_mode)=="none":return out
	return _kit_build_cards.duplicate()

## What the kit's skill `id_` is now: its base values, then the rank entries up to the rank growth gave it. {} while it is not unlocked.
func _kit_skill(id_: String) -> Dictionary:
	var rank := growth.kit_rank(id_)
	if rank<=0 or not _kit.skills.has(id_):return {}
	var definition: Dictionary=_kit.skills[id_]
	var out := {}
	for key in definition:
		if key!="role" and key!="ranks":out[key]=definition[key] if definition[key] is String else int(definition[key])
	for r in mini(rank,definition.ranks.size()):
		for key in definition.ranks[r]:out[key]=int(definition.ranks[r][key])
	return out

func _kit_skill_id(role: String) -> String:
	for id_ in _kit.skills:
		if String(_kit.skills[id_].role)==role:return String(id_)
	return ""

func _kit_arc_bps() -> int:
	return int(_gear_stats.get("arc_damage_bps",0))

func _kit_context(skill_id: String,damage: int) -> Dictionary:
	_cast_sequence+=1
	return {"uid":_cast_sequence,"skill_id":skill_id,"evolved":false,"remaining_hits":100000,"hit_ids":[],
		"effects":{"damage_raw":damage,"cooldown_ticks":0,"projectiles":0,"chain_targets":0,"branches":1,"pierce":0,"radius_cm":0,"slow_bps":0,"freeze_stacks":0,
			"shatter_count":0,"death_burst":0,"proc_depth":0,"hit_budget":1}}

# ---- the status

func _kit_shock_n(e: Dictionary) -> int:
	var st: Variant=e.get("kst")
	if st is Dictionary and tick<int(st.until):return int(st.n)
	return 0

func _kit_cap(e: Dictionary) -> int:
	var rule: Dictionary=_kit.status
	return (int(rule.max_big)+growth.kit_val("max_big")) if e.elite else int(rule.max)

## Put `add` stacks of the shock status on a body (bounded by its cap; renews the expiry). One status_stacked event per body per 15 ticks
## (a big body every time), at most 32 a tick; status_full when a big body reaches its cap.
func _kit_shock(e: Dictionary,add: int) -> void:
	var before := _kit_shock_n(e)
	var cap := _kit_cap(e)
	var n := mini(cap,before+add)
	var previous: Variant=e.get("kst")
	var last_emit := int(previous.emit) if previous is Dictionary else -1000
	e.kst={"n":n,"until":tick+int(_kit.status.expire_ticks),"emit":last_emit}
	if n==before and not e.elite:return
	if e.elite or tick-last_emit>=15:
		if _kit_ev_tick!=tick:_kit_ev_tick=tick;_kit_ev_stacked=0;_kit_ev_bolts=0
		if _kit_ev_stacked<32:
			_kit_ev_stacked+=1;e.kst.emit=tick
			_emit("status_stacked",e.position,{"target_id":int(e.id),"element":ElementKit.element_of_skill(_primary_id),"stacks":n,"max":cap,"big":bool(e.elite)})
	if e.elite and n>=cap and before<cap:
		_emit("status_full",e.position,{"target_id":int(e.id),"element":ElementKit.element_of_skill(_primary_id),"kind":"big_full"})

# ---- the tick

func _kit_step() -> void:
	if _kit_ev_tick!=tick:_kit_ev_tick=tick;_kit_ev_stacked=0;_kit_ev_bolts=0
	if zone!=_kit_zone_seen:_kit_zone_seen=zone;_kit_zone_start=tick
	# ET16: a body out of play (the boss in its entrance or break) keeps its stacks: its status clock stands still.
	if _shield_id>0 and enemies.has(_shield_id):
		var held: Variant=enemies[_shield_id].get("kst")
		if held is Dictionary:held.until=int(held.until)+1
	_kit_rod_upkeep()
	if growth.kit_rank(_kit_skill_id("lay"))>0:_kit_cast_rod()
	if growth.kit_rank(_kit_skill_id("burst"))>0:_kit_cast_overload()
	_kit_storm()
	_kit_passives()
	if _kit_merged_n>0:
		_emit("bolt_returned",hero.position,{"from_id":0,"to_id":0,"damage_raw":_kit_merged_raw,"self":false,"merged":_kit_merged_n})
		metrics.kit.merged_bolts=int(metrics.kit.merged_bolts)+_kit_merged_n
		_kit_merged_n=0;_kit_merged_raw=0

func _kit_rod_upkeep() -> void:
	if _kit_rods.is_empty():return
	var keep: Array[int]=[]
	for id_ in _kit_rods:
		var e: Variant=enemies.get(id_)
		var reason := ""
		if not e is Dictionary or int(e.hp_raw)<=0:reason="dead"
		elif id_==_shield_id:reason="break"
		elif tick>=int(e.get("rod_until",0)):reason="time"
		if not reason.is_empty():
			if e is Dictionary:e.rod_until=0
			_emit("rod_dropped",e.position if e is Dictionary else hero.position,{"target_id":id_,"reason":reason})
			continue
		keep.append(id_)
		# A body with a rod keeps its shock alive while the rod stands.
		var st: Variant=e.get("kst")
		if st is Dictionary and int(st.n)>0 and tick<int(st.until):st.until=tick+int(_kit.status.expire_ticks)
	_kit_rods=keep

func _kit_rod_target(range_m: float,include_bearers: bool) -> int:
	var best := -1;var best_big := false;var best_hp := -1
	for id_ in _near(hero.position,range_m):
		if id_ in _kit_rods and not include_bearers:continue
		var e: Dictionary=enemies[id_]
		var big: bool=e.elite
		var hp := int(e.hp_raw)
		if best<0 or (big and not best_big) or (big==best_big and (hp>best_hp or (hp==best_hp and id_<best))):
			best=id_;best_big=big;best_hp=hp
	return best

func _kit_cast_rod() -> void:
	var s := _kit_skill(_kit_skill_id("lay"))
	if s.is_empty() or tick<_kit_next_rod:return
	var count: int=int(_kit.rod.count)+growth.kit_val("rod_count")
	# With every rod standing, the best body is picked among all (a standing rod is renewed); with a free slot, among those without one.
	var full := _kit_rods.size()>=count
	var target := _kit_rod_target(float(int(_kit.rod.range_cm))/100.0,full)
	if target<0:return
	var e: Dictionary=enemies[target]
	_kit_next_rod=tick+maxi(12,int(s.cooldown_ticks))
	if full and not target in _kit_rods:
		var old: int=_kit_rods.pop_front()
		if enemies.has(old):enemies[old].rod_until=0;_emit("rod_dropped",enemies[old].position,{"target_id":old,"reason":"replaced"})
	var until := tick+int(s.get("rod_ticks",int(_kit.rod.ticks)))
	var ctx := _kit_context(_kit_skill_id("lay"),int(s.damage_raw)*(10000+_kit_arc_bps())/10000)
	metrics.casts[_kit_skill_id("lay")]=int(metrics.casts.get(_kit_skill_id("lay"),0))+1
	_damage_enemy(target,ctx,0)
	if int(e.hp_raw)<=0:return
	e.rod_until=until
	if not target in _kit_rods:_kit_rods.append(target)
	metrics.kit.rods=int(metrics.kit.rods)+1
	_emit("rod_planted",e.position,{"target_id":target,"until":until})

## One bolt from `from_id` to `to_id`: the event (at most 16 a tick, the rest folded into one) and the blow through the normal damage path.
func _kit_bolt(from_id: int,to_id: int,ctx: Dictionary,raw: int,self_: bool,spark: bool=false) -> bool:
	if not enemies.has(to_id) or int(enemies[to_id].hp_raw)<=0:return false
	ctx.effects.damage_raw=raw
	var at: Vector2=enemies[to_id].position
	if _kit_ev_bolts<16:
		_kit_ev_bolts+=1
		var details := {"from_id":from_id,"to_id":to_id,"damage_raw":raw,"self":self_}
		if spark:details.spark=true
		_emit("bolt_returned",at,details)
	else:
		_kit_merged_n+=1;_kit_merged_raw+=raw
	if spark:metrics.kit.sparks=int(metrics.kit.sparks)+1
	elif self_:metrics.kit.self_bolts=int(metrics.kit.self_bolts)+1
	metrics.kit.bolts=int(metrics.kit.bolts)+1
	_damage_enemy(to_id,ctx,0)
	return enemies.has(to_id) and int(enemies[to_id].hp_raw)>0

func _kit_cast_overload() -> void:
	var skill_id := _kit_skill_id("burst")
	var s := _kit_skill(skill_id)
	if s.is_empty() or tick<_kit_next_overload:return
	var reach := float(int(s.reach_cm))/100.0
	var targets: Array[int]=[]
	for id_ in _kit_rods:
		if enemies.has(id_) and int(enemies[id_].hp_raw)>0:targets.append(id_)
	if targets.is_empty():
		var best := -1;var best_hp := -1
		for id_ in _near(hero.position,reach):
			if _kit_shock_n(enemies[id_])<=0:continue
			var hp := int(enemies[id_].hp_raw)
			if hp>best_hp or (hp==best_hp and id_<best):best=id_;best_hp=hp
		if best>=0:targets.append(best)
	if targets.is_empty():return
	var center: Vector2=enemies[targets[0]].position
	var conductors: Array[int]=[]
	for id_ in _near(center,reach):
		if id_ in targets or _kit_shock_n(enemies[id_])<=0:continue
		conductors.append(id_)
	# 16.2 zone "target_or_hero": a shocked body within reach of the hero conducts too (one that is in both circles counts once).
	var near_target := conductors.size()
	var near_hero := 0
	var wide := String(s.get("zone","target"))=="target_or_hero"
	if wide or _kit_v16:
		for id_ in _near(hero.position,reach):
			if id_ in targets or _kit_shock_n(enemies[id_])<=0:continue
			near_hero+=1
			if wide and not id_ in conductors:conductors.append(id_)
	var max_bolts := maxi(1,int(s.max_bolts)+growth.kit_val("overload_max_bolts"))
	var count := mini(conductors.size(),max_bolts)
	var self_n := 0
	var spent := 0
	var first: Dictionary=enemies[targets[0]]
	if String(s.get("bolt_rule","conductors"))=="max":
		# 16.2: the bolts are the larger of the conductors' and the big body's own; only the stacks the own bolts used are spent.
		var per := int(s.self_bolt_bps)+growth.kit_val("self_bolt_bps")
		var from_conductors := (conductors.size()+growth.kit_val("bolts_add")) if not conductors.is_empty() else 0
		var own := (_kit_shock_n(first)*per/10000) if first.elite else 0
		count=mini(max_bolts,maxi(from_conductors,own))
		if count<=0:return
		self_n=maxi(0,count-from_conductors)
		if self_n>0:
			spent=mini(_kit_shock_n(first),(self_n*10000+per-1)/per)
			first.kst.n=_kit_shock_n(first)-spent
	elif conductors.is_empty():
		# No conductor: a big body's own stacks make the bolts (and are spent).
		if not first.elite:return
		count=mini(max_bolts,_kit_shock_n(first)*(int(s.self_bolt_bps)+growth.kit_val("self_bolt_bps"))/10000)
		if count<=0:return
		self_n=count
		first.kst.n=0
	else:count+=growth.kit_val("bolts_add")
	var conductor_bolts := count-self_n
	_kit_next_overload=tick+maxi(12,int(s.cooldown_ticks)*(10000+growth.kit_val("overload_cd_bps"))/10000)
	metrics.casts[skill_id]=int(metrics.casts.get(skill_id,0))+1
	var base := int(s.bolt_raw)*(int(s.bolt_bps)+growth.kit_val("overload_bolt_bps"))/10000*(10000+_kit_arc_bps())/10000
	var ctx := _kit_context(skill_id,base)
	var per: Dictionary={}
	var sent: Array[int]=[]
	var points: Array[Vector2]=[]
	for i in count:
		var to: int=targets[i%targets.size()]
		if not enemies.has(to) or int(enemies[to].hp_raw)<=0:
			to=-1
			for id_ in _near(center,reach):
				if not id_ in conductors:to=id_;break
			if to<0:break
		var from: int=to if i>=conductor_bolts else conductors[mini(i,conductors.size()-1)]
		var raw := base
		if int(enemies[to].get("rod_until",0))>tick:raw=raw*(10000+growth.kit_val("rod_target_bps"))/10000
		if i<conductor_bolts and i<conductors.size():
			sent.append(from)
			if enemies.has(from):
				points.append(enemies[from].position)
				if enemies[from].get("kst") is Dictionary:enemies[from].kst.n=0
		var row: Dictionary=per.get(to,{"n":0,"raw":0})
		row.n=int(row.n)+1;row.raw=int(row.raw)+raw;per[to]=row
		_kit_bolt(from,to,ctx,raw,i>=conductor_bolts)
	var logged: Array=metrics.kit.overloads
	if logged.size()<600:
		var entry := {"tick":tick,"bolts":count,"conductors":conductors.size(),"self":self_n>0,"big":bool(first.elite),"targets":targets.size()}
		if _kit_v16:entry.merge({"topup":self_n,"spent":spent,"hero_dist_cm":int(hero.position.distance_to(first.position)*100.0),"near_hero":near_hero,"near_target":near_target})
		logged.append(entry)
	for id_ in per:
		var alive := enemies.has(id_) and int(enemies[id_].hp_raw)>0
		_emit("detonated",enemies[id_].position if enemies.has(id_) else hero.position,{"skill_id":skill_id,"target_id":id_,"element":ElementKit.element_of_skill(_primary_id),"stacks":int(per[id_].n),"damage_raw":int(per[id_].raw),"big":bool(enemies[id_].elite) if enemies.has(id_) else false,"kill":not alive})
	if growth.kit_flag("conductor_pop") and not points.is_empty():
		var pop: Dictionary=_kit.params.pop
		var pop_ctx := _kit_context(skill_id,int(pop.raw)*(10000+_kit_arc_bps())/10000)
		for p in points:
			for id_ in _near(p,float(int(pop.radius_cm))/100.0):
				if not id_ in targets:_damage_enemy(id_,pop_ctx,0)
		metrics.kit.pops=int(metrics.kit.pops)+points.size()
	if growth.kit_flag("bolt_heal"):
		var heal: Dictionary=_kit.params.bolt_heal
		_kit_bolt_count+=count
		while _kit_bolt_count>=int(heal.bolts):
			_kit_bolt_count-=int(heal.bolts)
			hero.hp_raw=mini(int(hero.max_hp_raw),int(hero.hp_raw)+int(heal.heal)*UNIT)
			metrics.kit.heals=int(metrics.kit.heals)+1

func _kit_storm() -> void:
	if tick<_kit_next_storm:return
	var arc: Dictionary=growth.effective_skill(_primary_id)
	if arc.is_empty() or not bool(arc.evolved):return
	var storm: Dictionary=_kit.evolution.storm
	var want_rods := 0
	if not _kit_rods.is_empty():want_rods=ceili(float(int(storm.targets))/2.0) if growth.kit_flag("storm_rod") else 1
	var picks: Array[int]=[]
	for id_ in _kit_rods:
		if picks.size()<want_rods and enemies.has(id_) and int(enemies[id_].hp_raw)>0:picks.append(id_)
	for id_ in _near(hero.position,_acquire_m()):
		if picks.size()>=int(storm.targets):break
		if not id_ in picks and _kit_shock_n(enemies[id_])>0:picks.append(id_)
	if picks.is_empty():return
	_kit_next_storm=tick+int(storm.every_ticks)
	metrics.kit.storms=int(metrics.kit.storms)+1
	var ctx := _kit_context(KIT_STORM_ID,int(arc.effects.damage_raw)*int(storm.damage_bps)/10000)
	metrics.casts[KIT_STORM_ID]=int(metrics.casts.get(KIT_STORM_ID,0))+1
	_emit("kit_storm",hero.position,{"targets":picks.duplicate(),"skill_id":KIT_STORM_ID})
	for id_ in picks:_damage_enemy(id_,ctx,0)

## The survival cards that act over time: the discharge ring round a rod, the stride, the shell.
func _kit_passives() -> void:
	if growth.kit_flag("discharge_ring") and tick>=_kit_next_discharge and not _kit_rods.is_empty():
		var rule: Dictionary=_kit.params.discharge
		_kit_next_discharge=tick+int(rule.every_ticks)
		var seen := 0
		for rod in _kit_rods:
			if not enemies.has(rod):continue
			for id_ in _near(enemies[rod].position,float(int(rule.radius_cm))/100.0):
				if id_==rod or seen>=12:continue
				_kit_shock(enemies[id_],1);seen+=1
		metrics.kit.discharges=int(metrics.kit.discharges)+1
	if growth.kit_flag("stride_shock") and tick>=_kit_next_stride:
		var rule: Dictionary=_kit.params.stride
		var near := _near(hero.position,float(int(rule.reach_cm))/100.0)
		if not near.is_empty():
			_kit_next_stride=tick+int(rule.every_ticks)
			_kit_shock(enemies[near[0]],1)
			metrics.kit.strides=int(metrics.kit.strides)+1
	if growth.kit_flag("static_shell") and tick>=_kit_shell_next:
		var rule: Dictionary=_kit.params.shell
		if int(hero.hp_raw)*10000<int(hero.max_hp_raw)*int(rule.hp_bps):
			_kit_shell_next=tick+int(rule.cooldown_ticks)
			_kit_shell_until=tick+int(rule.ticks);_kit_shell_reduce=int(rule.reduce_bps)
			for id_ in _near(hero.position,float(int(rule.radius_cm))/100.0):
				var e: Dictionary=enemies[id_]
				_kit_shock(e,1)
				if not e.elite:e.position=_clamp_point(e.position+(e.position-hero.position).normalized()*1.0)
			metrics.kit.shells=int(metrics.kit.shells)+1
			_emit("kit_shell",hero.position,{"until":_kit_shell_until,"reduce_bps":_kit_shell_reduce})

## A shocked body died (called from the damage path; `e` is dead): a rod within its keep radius draws a small bolt from it, and the card
## "chain on death" shocks the nearest body.
func _kit_on_death(e: Dictionary) -> void:
	if _kit_shock_n(e)<=0:return
	if not _kit_rods.is_empty():
		var s := _kit_skill(_kit_skill_id("lay"))
		var radius := float(int(s.get("keep_radius_cm",int(_kit.rod.keep_radius_cm))))/100.0
		var spark_raw: int=int(_kit.rod.death_spark_raw)*(10000+_kit_arc_bps())/10000
		var ctx := _kit_context(_kit_skill_id("lay"),spark_raw)
		for rod in _kit_rods.duplicate():
			if rod==int(e.id) or not enemies.has(rod) or int(enemies[rod].hp_raw)<=0:continue
			if enemies[rod].position.distance_to(e.position)<=radius:_kit_bolt(int(e.id),rod,ctx,spark_raw,false,true)
	if growth.kit_flag("chain_on_death"):
		for id_ in _near(e.position,float(int(_kit.params.death_chain.reach_cm))/100.0):
			if id_!=int(e.id):_kit_shock(enemies[id_],1);break

## What a kit card does the moment it is taken (called by choose() after growth took it): the hero body, a filler's one-off effect, the events.
func _kit_took(card_id: String) -> void:
	var taken: Dictionary=growth.kit_last()
	if taken.is_empty():return
	var before_max := int(hero.max_hp_raw)
	_kit_hp=growth.kit_val("hp_max");_kit_move_bps=growth.kit_val("move_bps")
	_recompute_gear()
	if int(hero.max_hp_raw)>before_max:hero.hp_raw=mini(int(hero.max_hp_raw),int(hero.hp_raw)+int(hero.max_hp_raw)-before_max)
	if String(taken.kind)=="filler":
		var effect: Dictionary=taken.effect
		if effect.has("heal_bps"):hero.hp_raw=mini(int(hero.max_hp_raw),int(hero.hp_raw)+int(hero.max_hp_raw)*int(effect.heal_bps)/10000)
		if effect.has("potion"):
			if potions<int(tuning.potion.carry_max):potions+=int(effect.potion)
			else:hero.hp_raw=mini(int(hero.max_hp_raw),int(hero.hp_raw)+int(hero.max_hp_raw)*int(effect.get("heal_bps_if_full",0))/10000)
	_emit("kit_card_taken",hero.position,{"card_id":card_id,"kind":String(taken.kind),"element":ElementKit.element_of_skill(_primary_id)})
	if String(taken.kind)=="unlock":_emit("skill_gate_opened",hero.position,{"id":String(taken.skill),"card_id":card_id,"gate":String(taken.get("gate",""))})

func _kit_state() -> Dictionary:
	var state := {"rods":_kit_rods.duplicate(),"next_rod":_kit_next_rod,"next_overload":_kit_next_overload,"next_storm":_kit_next_storm,"next_discharge":_kit_next_discharge,
		"next_stride":_kit_next_stride,"shell_next":_kit_shell_next,"shell_until":_kit_shell_until,"bolts":_kit_bolt_count,"hp":_kit_hp,"move_bps":_kit_move_bps}
	if _kit_v16:state.merge({"crest_tick":_kit_crest_tick,"zone_start":_kit_zone_start,"evo_events":_kit_evo_events})
	return state

## Read only, for the screen and the tools: the kit's state in one dictionary. {"on": false} while off. Changes nothing, draws nothing.
func kit_view() -> Dictionary:
	if not _kit_on:return {"on":false}
	var skills := {}
	for id_ in _kit.skills:skills[id_]={"rank":growth.kit_rank(id_),"role":String(_kit.skills[id_].role)}
	return {"on":true,"element":ElementKit.element_of_skill(_primary_id),"skills":skills,"rods":_kit_rods.duplicate(),"taken":growth.kit_taken(),
		"shell_until":_kit_shell_until,"next_overload":_kit_next_overload,"next_rod":_kit_next_rod}
