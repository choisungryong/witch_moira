extends RefCounted
## C2 representative encounter, independent design. Fixed 60 Hz, no profile I/O.
## Existing CombatResolver integer damage pattern is reused; presentation cannot deal damage.
## Auto casts reserve a per-skill cooldown (no mana in this encounter), then retain an immutable
## release snapshot. Changing gear/rank while a projectile exists cannot change that shot.
const GrowthCatalog = preload("res://chapter1/core/growth_catalog.gd")
const Growth = preload("res://chapter1/core/run_growth.gd")
const Resolver = preload("res://combat/combat_resolver.gd")
const HZ := 60
const UNIT := 256
const STEP := 1.0 / HZ
const BOUND := 19.0
const MAX_ALIVE := 180
const MAX_ENTITIES := 512
const MAX_PROJECTILES := 384
const MAX_HOSTILE_PROJECTILES := 192
const MAX_ORBS := 400
const MAX_GROUND_ITEMS := 32
const MAX_INVENTORY := 64
const MAX_OBJECTIVE_REWARDS := 1 # Reserved owned slot; never replaces ordinary gear.
const EQUIP_SLOTS := ["weapon","head","body","hands","feet","charm","ring","ring2"]
const BASE_SPEED := 5.8
const MAX_EVENTS := 1024
# Local approach steering is an independent crowd rule, not cosmetic displacement.
# At most32 bodies from the current/adjacent2m cells can influence an approach.
const MAX_CROWD_NEIGHBORS := 32
const CROWD_RADIUS := 1.85
const CROWD_GAP := .08
const CROWD_PUSH_PER_STEP := .045
const HERO_RADIUS := .28
const HERO_APPROACH_GAP := .12
const ELITE_TICK := 70 * HZ
const SKILL_IDS := ["chapter1.skill.ember","chapter1.skill.frost","chapter1.skill.arc"]
const ENEMY_DEFS := {
	"walker":{"hp":12,"speed":1.60,"radius":.30,"damage":5,"windup":25,"recover":58,"xp":1},
	"ranged":{"hp":18,"speed":1.45,"radius":.32,"damage":5,"windup":40,"recover":125,"xp":2},
	"charger":{"hp":32,"speed":1.95,"radius":.43,"damage":8,"windup":48,"recover":90,"xp":3},
	"elite":{"hp":720,"speed":1.75,"radius":.85,"damage":12,"windup":48,"recover":100,"xp":12}
}
const ITEM_TEMPLATES := [
	{"base_id":"chapter1.item.cinder_branch","name":"균열의 불티 가지","slot":"weapon","stats":{"damage_bps":1000,"projectiles":1},"description":"피해 증가 · 발사체 +1. 연쇄 기술은 연쇄 대상 +1."},
	{"base_id":"chapter1.item.guard_robe","name":"수호의 재옷","slot":"body","stats":{"max_hp_raw":7680,"damage_reduction_bps":700},"description":"최대 생명력 +30 · 받는 피해 감소. 장착은 현재 생명력을 회복하지 않습니다."},
	{"base_id":"chapter1.item.harvest_crystal","name":"회수의 재결정","slot":"charm","stats":{"pickup_radius_cm":100,"cooldown_bps":800},"description":"회수 반경 +1m · 기술 주기 단축."},
	{"base_id":"chapter1.item.conductor_ring","name":"갈래 도체 반지","slot":"ring","stats":{"damage_bps":500,"chain_targets":1,"shatter_count":1},"description":"피해 증가 · 연쇄 +1 · 파쇄 파편 +1."}
]
var mode := "menu"
var tick := 0
var kills := 0
var hero: Dictionary = {}
var enemies: Dictionary = {}
var projectiles: Array[Dictionary] = []
var orbs: Array[Dictionary] = []
var items: Array[Dictionary] = []
var inventory: Array[Dictionary] = []
var equipped: Dictionary = {}
var events: Array[Dictionary] = []
var growth = Growth.new()
var errors: Array[String] = []
var metrics: Dictionary = {}
var _catalog = GrowthCatalog.new()
var _spawn_rng := RandomNumberGenerator.new()
var _loot_rng := RandomNumberGenerator.new()
var _next_cast: Dictionary = {}
var _contexts: Dictionary = {}
var _grid: Dictionary = {}
var _enemy_sequence := 0
var _projectile_sequence := 0
var _orb_sequence := 0
var _item_sequence := 0
var _cast_sequence := 0
var _event_sequence := 0
var _epoch := 0
var _next_spawn := 0
var _elite_spawned := false
var _elite_killed := false
var _paused := false
var _inventory_open := false
var _terminal_mode := ""
var _dash_direction := Vector2.ZERO
var _dash_until := 0
## D23 T1-B: the last tick the hero moved on foot (not in a dash), for the moving-damage condition. -1 = not yet.
var _last_move_tick := -1
var _next_dash := 0
var _invulnerable_until := 0
var _gear_stats: Dictionary = {}
var _guaranteed_drops := 0
var _elite_reward_uid := 0
var _soul_carry := 0
## Number-of-enemies counter (alive_count). Kept by _spawn, death and a recount in _cleanup.
var _alive := 0
var _primary_id := ""
## Role and pressure numbers (chapter1/data/combat_tuning.json). Empty means every rule that
## reads it is off, which is how this base core runs on its own.
var tuning: Dictionary = {}
## D21 N2: qualities that never leave the ground by age (filled by the chapter core when tuning.loot_flow is on; empty = the 180 s rule for all).
var _kept_qualities: Array[String] = []
## Child projectiles born during a projectile step; they join the list once the step ends.
var _pending_children: Array[Dictionary] = []
## D20: falls of the evolved ember (Meteor) that are booked and have not landed yet: {id, position, land_tick, cast_id}. Empty (and absent
## from snapshot()) while no such fall is in the air; a run whose tuning has no "meteor" block never books one.
var _meteors: Array[Dictionary] = []
var _meteor_sequence := 0
## Safety cap on booked falls at once (a cast books at most 16; the cooldown is long). Not a balance number.
const MAX_METEORS := 64
var _friendly_count := 0
var _friendly_tick := -1
## Tick of the last full-strength heavy hit on the hero (-1 = none); see tuning.heavy_hit. Not part of the snapshot.
var _last_heavy_tick := -1
## Measurement only: the run casts its primary skill alone. No tuning document and no game path sets this.
var debug_secondary_off := false
## Permanent-build hero values (whole health points, hero damage reduction in ten-thousandths). Set by the chapter
## core's start() from the compiled skill tree; 0 without a build, which leaves every number as it was.
var _build_max_hp := 0
var _build_reduction_bps := 0
## In-run spell composition (chapter1/data/run_spells.json). Empty means off: nothing below reads it and every rule
## stays as it was. The chapter core installs the validated document (enabled only) before start().
var spells: Dictionary = {}
## The spells the run may cast: SKILL_IDS, plus the ring spells while the composition is on.
var _skill_ids: Array = SKILL_IDS.duplicate()
## Ring pulses still to come: {due, skill_id, effects, evolved, pulse}. Empty (and never filled) while the composition is off.
var _ring_pending: Array[Dictionary] = []
## Who fired each enemy projectile in flight: {projectile uid: {"id": enemy id, "kind": source kind}}. The projectile
## dictionary itself is in the snapshot and gets no new key, so this lives beside it (not in the snapshot, cleared by start()).
var _hostile_src: Dictionary = {}
## The descent (D15 A) holds the core still between request_descent() and release_descent(): mode "descent", no tick.
## Always false in a run whose descent.json is off.
var _descent_hold := false
## D23 T17: thorns owed for the hit of this tick ({id, amount, kind}); written by _hero_damage, paid by _resolve_thorns() after the
## projectile step. Never in the snapshot (empty at the end of every step).
var _thorns_pending: Array[Dictionary] = []
## D23 T17: kill ticks inside the streak window, and the projectiles the next primary cast gets (0 = not armed).
var _streak_kills: Array[int] = []
var _streak_charge := 0

func start(seed_: int = 1, primary: String = "chapter1.skill.ember") -> bool:
	if not _catalog.load_file("res://chapter1/data/growth_quality36.json"):
		errors.assign(_catalog.errors)
		return false
	if not growth.configure(_catalog.snapshot(),primary,seed_ ^ 0x47524f57):
		errors.assign(growth.errors)
		return false
	_epoch += 1
	tick = 0
	_choice_tick = -1
	kills = 0
	mode = "playing"
	hero = {"position":Vector2.ZERO,"hp_raw":120*UNIT,"max_hp_raw":120*UNIT,"speed":5.8,"direction":Vector2.UP}
	enemies.clear()
	projectiles.clear()
	orbs.clear()
	items.clear()
	inventory.clear()
	equipped.clear()
	events.clear()
	_next_cast.clear()
	_contexts.clear()
	_grid.clear()
	_enemy_sequence = 0
	_projectile_sequence = 0
	_orb_sequence = 0
	_item_sequence = 0
	_cast_sequence = 0
	_event_sequence = 0
	_next_spawn = 30
	_elite_spawned = false
	_elite_killed = false
	_paused = false
	_inventory_open = false
	_descent_hold = false
	_terminal_mode = ""
	_dash_direction = Vector2.ZERO
	_dash_until = 0
	_last_move_tick = -1
	_next_dash = 0
	_invulnerable_until = 0
	_gear_stats.clear()
	_soul_carry = 0
	_alive = 0
	_primary_id = primary
	_pending_children.clear()
	_meteors.clear()
	_meteor_sequence = 0
	_ring_pending.clear()
	_hostile_src.clear()
	_thorns_pending.clear()
	_streak_kills.clear()
	_streak_charge = 0
	_friendly_tick = -1
	_last_heavy_tick = -1
	_guaranteed_drops = 0
	_elite_reward_uid = 0
	_spawn_rng.seed = seed_ ^ 0x53504157
	_loot_rng.seed = seed_ ^ 0x4c4f4f54
	metrics = {"casts":{},"hits":{},"max_alive":0,"peak_projectiles":0,"enemy_attacks":0,"collected_xp":0,"dropped_items":0,"picked_items":0,"events_dropped":0,"orbs_merged":0,"damage_raw":0,"crowd_neighbor_checks":0,"crowd_peak_neighbors":0,"crowd_adjustments":0}
	var opening_count := _initial_pack_count()
	for i in opening_count:
		var angle := TAU*float(i)/float(opening_count)
		_spawn("walker",hero.position+Vector2(cos(angle),sin(angle))*_spawn_rng.randf_range(5.5,8.0))
	_rebuild_grid()
	_update_metrics()
	errors.clear()
	return true

func _initial_pack_count() -> int:
	return 24

func elapsed() -> float:
	return float(tick)/HZ

func get_next_dash_tick() -> int:
	return _next_dash

func alive_count() -> int:
	return _alive

func set_paused(value: bool) -> void:
	_paused = value
	_refresh_mode()

func open_inventory() -> bool:
	if mode == "menu" or _terminal_mode == "defeat" or _descent_hold: return false
	_inventory_open = true
	_refresh_mode()
	return true

func close_inventory() -> void:
	_inventory_open = false
	_refresh_mode()

## The player gives up. Same terminal path as a defeat: the app saves the run as a defeat.
## Only from a live run; never from the menu or after the end. Not used by the golden replay.
func abandon() -> bool:
	if mode == "menu" or not _terminal_mode.is_empty(): return false
	_inventory_open = false
	_terminal_mode = "defeat"
	_refresh_mode()
	_emit("defeat", hero.position, {"abandoned": true})
	return true

func _refresh_mode() -> void:
	if mode == "menu": return
	if not _terminal_mode.is_empty():
		mode = "inventory" if _inventory_open and _terminal_mode == "victory" else _terminal_mode
	elif _paused: mode = "paused"
	elif _inventory_open: mode = "inventory"
	elif _descent_hold: mode = "descent"
	elif not growth.snapshot().pending_levels.is_empty() and _grace_ready(): mode = "choice"
	else: mode = "playing"

## D13 K3a: may the next pending level open its choice now? Always, here; the chapter core overrides this for the grace gap.
func _grace_ready() -> bool:
	return true

## Tick of the latest card pick (-1 before the first); the grace gap counts from it. Reaches the snapshot only through the chapter core's grace key.
var _choice_tick := -1

## Events the grace rules queued in the growth (grades pulled, jackpot, banish, hold, last offer) become core events.
func _drain_growth_events() -> void:
	for event in growth.take_events(): _emit(String(event.type),hero.position,event.data)

func get_offer() -> Dictionary:
	if mode != "choice": return {}
	var offer: Dictionary = growth.next_offer()
	_drain_growth_events()
	return offer

func choose(token: String, card_id: String) -> bool:
	if mode != "choice": return false
	# The picked card's identity for the record and the screen, read from the standing offer before choose() clears it (no card is drawn here).
	var picked := {}
	for card in growth.snapshot().offer.get("cards",[]):
		if card.id == card_id: picked = {"kind":String(card.kind),"skill_id":String(card.get("skill_id","")),"title_key":String(card.title_key),"rank":int(card.get("rank",0)),"axis":String(card.get("axis","")),"level":int(card.get("level",0))}
	if not growth.choose(token,card_id): return false
	_emit("growth",hero.position,{"card_id":card_id,"card":picked,"growth":growth.snapshot()})
	_drain_growth_events()
	_choice_tick = tick
	_refresh_mode()
	return true

func request_dash(direction: Vector2) -> bool:
	if mode != "playing" or tick < _next_dash or not direction.is_finite(): return false
	_dash_direction = direction.normalized() if direction.length_squared() > .001 else hero.direction
	_dash_until = tick+12
	_next_dash = tick+maxi(60,180*10000/(10000+int(_gear_stats.get("dash_cooldown_bps",0))))
	# step() increments first: protect the next18 simulation steps, including step18.
	_invulnerable_until = maxi(_invulnerable_until,tick+19)
	_emit("dash",hero.position,{"direction":_dash_direction})
	return true

## Which equip slot currently holds this item, or "" when it is not worn.
func equip_slot_of(uid: int) -> String:
	for slot in equipped:
		if int(equipped[slot]) == uid: return slot
	return ""

## The slot an item would go into. A ring fills the first free ring slot and
## otherwise replaces the first ring.
func target_slot(item: Dictionary) -> String:
	var worn := equip_slot_of(int(item.get("uid",-1)))
	if not worn.is_empty(): return worn
	if item.slot != "ring": return item.slot
	if not equipped.has("ring"): return "ring"
	if not equipped.has("ring2"): return "ring2"
	return "ring"

func can_equip(item: Dictionary) -> bool:
	return int(item.get("required_level",1)) <= int(growth.snapshot().level)

func _owned(uid: int) -> Dictionary:
	for item in inventory:
		if item.uid == uid: return item
	return {}

func _equip_now(found: Dictionary, slot: String) -> bool:
	if found.is_empty() or not can_equip(found): return false
	if slot.is_empty() or not slot in EQUIP_SLOTS: slot = target_slot(found)
	if (found.slot == "ring") != (slot in ["ring","ring2"]) or (found.slot != "ring" and slot != found.slot): return false
	var previous := equip_slot_of(int(found.uid))
	if not previous.is_empty() and previous != slot: equipped.erase(previous)
	equipped[slot] = found.uid
	_recompute_gear()
	_emit("equip",hero.position,{"item":found.duplicate(true),"slot":slot,"stats":_gear_stats.duplicate(true)})
	return true

func equip(uid: int, slot: String = "") -> bool:
	if mode != "inventory": return false
	return _equip_now(_owned(uid),slot)

## Wear a picked-up item without opening the inventory. Combat keeps running.
func quick_equip(uid: int) -> bool:
	if mode != "playing": return false
	return _equip_now(_owned(uid),"")

func unequip(slot: String) -> bool:
	if mode != "inventory" or not equipped.has(slot): return false
	equipped.erase(slot)
	_recompute_gear()
	_emit("equip",hero.position,{"slot":slot,"unequipped":true,"stats":_gear_stats.duplicate(true)})
	return true

func _recompute_gear() -> void:
	var totals := _gear_totals(equipped)
	_gear_stats.clear()
	_gear_stats.merge(totals)
	_apply_buff_stats(_gear_stats)
	var body := _hero_body(_gear_stats)
	hero.max_hp_raw = body.max_hp_raw
	hero.hp_raw = mini(int(hero.hp_raw),int(hero.max_hp_raw))
	hero.speed = body.speed

## Timed stats on top of the worn gear (D13 5.2 shrines). The chapter core adds them to `stats`; here there are none, so the
## gear totals are the stats. preview_equip and compare_item never see them (they read _gear_totals).
func _apply_buff_stats(_stats: Dictionary) -> void:
	pass

## Pure: summed gear stats for an equip map {slot: uid} over the bag. No state change.
func _gear_totals(equip_map: Dictionary) -> Dictionary:
	var totals := {}
	for slot in EQUIP_SLOTS:
		if not equip_map.has(slot): continue
		var item := _owned(int(equip_map[slot]))
		if item.is_empty(): continue
		for stat in item.stats:
			totals[stat] = int(totals.get(stat,0))+int(item.stats[stat])
	return totals

## Pure: the hero's gear-and-build body values for the given gear totals.
func _hero_body(gear: Dictionary) -> Dictionary:
	var max_hp := 120*UNIT+int(gear.get("max_hp_raw",0))+_build_max_hp*UNIT
	# D23 T1-B: max_hp_bps multiplies the whole sum (base + gear numbers + tree).
	if int(gear.get("max_hp_bps",0)) != 0: max_hp = max_hp*(10000+int(gear.get("max_hp_bps",0)))/10000
	return {"max_hp_raw":max_hp,
		"speed":BASE_SPEED*float(10000+int(gear.get("move_speed_bps",0)))/10000.0}

func effective_skill(id_: String) -> Dictionary:
	return _skill_with(id_,_gear_with_conditions())

## D23 T1-B: the worn gear totals, with the low-health cooldown bonus (lowhp_cooldown_bps) added to cooldown_bps while the hero's
## life is at or under gear_conditions.lowhp_bps of the maximum. Without the key it is the very dictionary of _gear_stats.
func _gear_with_conditions() -> Dictionary:
	var bonus := int(_gear_stats.get("lowhp_cooldown_bps",0))
	var limit := int(tuning.get("gear_conditions",{}).get("lowhp_bps",0))
	if bonus <= 0 or limit <= 0 or int(hero.hp_raw)*10000 > limit*int(hero.max_hp_raw): return _gear_stats
	var gear: Dictionary = _gear_stats.duplicate()
	gear.cooldown_bps = int(gear.get("cooldown_bps",0))+bonus
	return gear

## D23 T1-B: true from the tick after a dash ends for gear_conditions.after_dash_ticks ticks.
func _after_dash_active() -> bool:
	var ticks := int(tuning.get("gear_conditions",{}).get("after_dash_ticks",0))
	return ticks > 0 and _dash_until > 0 and tick > _dash_until and tick <= _dash_until+ticks

## D23 T1-B: true when the hero moved on foot within the last gear_conditions.moving_ticks ticks and is not dashing now.
func _moving_active() -> bool:
	var ticks := int(tuning.get("gear_conditions",{}).get("moving_ticks",0))
	return ticks > 0 and _last_move_tick >= 0 and tick > _dash_until and tick-_last_move_tick < ticks

## D23 T1-B: the hero's damage reduction in ten-thousandths: gear + tree + (with `live`) the guard that follows a dash, cut at
## stat_caps.damage_reduction_bps when the document has one. The hit and the stat sheet both read this one function. Shrine
## buffs are already inside `gear` (_apply_buff_stats), the dash guard is not (it is a state of the tick, not of the gear).
func _reduction_bps(gear: Dictionary, live: bool = false) -> int:
	var total := int(gear.get("damage_reduction_bps",0))+_build_reduction_bps
	if live and int(gear.get("after_dash_guard_bps",0)) > 0 and _after_dash_active(): total += int(gear.after_dash_guard_bps)
	var cap := int(tuning.get("stat_caps",{}).get("damage_reduction_bps",0))
	return mini(total,cap) if cap > 0 else total

## Pure: the skill's final effect for the given gear totals.
func _skill_with(id_: String, gear: Dictionary) -> Dictionary:
	var value: Dictionary = growth.effective_skill(id_)
	if value.is_empty(): return {}
	var effect: Dictionary = value.effects
	var additional := int(gear.get("projectiles",0))
	if effect.projectiles > 0: effect.projectiles = mini(16,int(effect.projectiles)+additional)
	else: effect.chain_targets = mini(32,int(effect.chain_targets)+additional)
	effect.chain_targets = mini(32,int(effect.chain_targets)+int(gear.get("chain_targets",0)))
	if int(effect.shatter_count) > 0: effect.shatter_count = mini(16,int(effect.shatter_count)+int(gear.get("shatter_count",0)))
	effect.damage_raw = int(effect.damage_raw)*(10000+int(gear.get("damage_bps",0)))/10000
	effect.cooldown_ticks = maxi(12,int(effect.cooldown_ticks)*10000/(10000+int(gear.get("cooldown_bps",0))))
	# Equipment augments attack shape, but cannot escape a cast's global damage budget.
	effect.hit_budget = mini(128,int(effect.hit_budget)+additional*8+int(gear.get("chain_targets",0))*2)
	return value

# ---------------------------------------------------------------- stat sheet (read only)

## The row carries ids only: the screen words it with stat.<id>.label and unit.<unit_id> ("" none, "s", "m", "pct", "count", "m_per_s").
static func _row(id_: String, raw: int, value: float, unit_id: String, better: String, decimals: int, detail: bool = false, kind: String = "number") -> Dictionary:
	return {"id":id_,"raw":raw,"value":value,"unit_id":unit_id,"better":better,"decimals":decimals,"detail":detail,"kind":kind}

## Rows of one skill's final effect. Primary shows the shape numbers that are nonzero; a secondary shows damage and interval.
func _skill_rows(effect: Dictionary, primary: bool) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	rows.append(_row("damage",int(effect.damage_raw),float(effect.damage_raw)/UNIT,"","higher",1))
	rows.append(_row("interval",int(effect.cooldown_ticks),float(effect.cooldown_ticks)/HZ,"s","lower",2))
	if not primary: return rows
	for count_id in ["projectiles","chain_targets","branches","pierce"]:
		var n := int(effect.get(count_id,0))
		if n > 0: rows.append(_row(count_id,n,float(n),"","higher",0))
	if int(effect.get("radius_cm",0)) > 0: rows.append(_row("radius",int(effect.radius_cm),float(effect.radius_cm)/100.0,"m","higher",1))
	if int(effect.get("slow_bps",0)) > 0: rows.append(_row("slow",int(effect.slow_bps),float(effect.slow_bps)/100.0,"pct","higher",0))
	if int(effect.get("freeze_stacks",0)) > 0: rows.append(_row("freeze_stacks",int(effect.freeze_stacks),float(effect.freeze_stacks),"count","lower",0))
	if int(effect.get("shatter_count",0)) > 0: rows.append(_row("shatter_count",int(effect.shatter_count),float(effect.shatter_count),"","higher",0))
	if int(effect.get("death_burst",0)) > 0: rows.append(_row("death_burst",1,1.0,"","higher",0,false,"flag"))
	rows.append(_row("hit_budget",int(effect.get("hit_budget",0)),float(effect.get("hit_budget",0)),"","higher",0,true))
	return rows

func _skill_block(id_: String, gear: Dictionary, primary: bool) -> Dictionary:
	var skill := _skill_with(id_,gear)
	if skill.is_empty(): return {}
	return {"id":id_,"name_key":skill.name_key,"rank":int(skill.rank),"evolved":bool(skill.evolved),"rows":_skill_rows(skill.effects,primary)}

func _hero_rows(gear: Dictionary) -> Array[Dictionary]:
	var body := _hero_body(gear)
	var reduction := _reduction_bps(gear)
	var dash := maxi(60,180*10000/(10000+int(gear.get("dash_cooldown_bps",0))))
	var pickup := int(gear.get("pickup_radius_cm",0))
	var soul := int(gear.get("soul_gain_bps",0))
	var speed_bps := 10000+int(gear.get("move_speed_bps",0))
	var rows: Array[Dictionary] = []
	rows.append(_row("max_hp",int(body.max_hp_raw),float(body.max_hp_raw)/UNIT,"","higher",0))
	var reduction_row := _row("damage_reduction",reduction,float(reduction)/100.0,"pct","higher",1)
	# D23 T1-B: the sheet says when the cap cut the figure (the screen words it).
	if int(gear.get("damage_reduction_bps",0))+_build_reduction_bps > reduction: reduction_row["capped"] = true
	rows.append(reduction_row)
	rows.append(_row("speed",speed_bps,float(body.speed),"m_per_s","higher",2))
	rows.append(_row("dash_cooldown",dash,float(dash)/HZ,"s","lower",2))
	rows.append(_row("pickup_radius",pickup,1.3+float(pickup)/100.0,"m","higher",1))
	rows.append(_row("soul_gain",soul,float(soul)/100.0,"pct","higher",0))
	return rows

## Legendary and unique descriptions of what the equip map wears.
func _effects_of(equip_map: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in EQUIP_SLOTS:
		if not equip_map.has(slot): continue
		var item := _owned(int(equip_map[slot]))
		if item.is_empty() or not item.get("quality","") in ["legendary","unique"]: continue
		if String(item.get("description","")).is_empty(): continue
		var kind := String(item.quality)
		var effect_id := String(item.get("legendary_id","")) if kind == "legendary" else String(item.get("base_id",""))
		result.append({"source_uid":int(item.uid),"kind":kind,"id":effect_id})
	return result

func _sheet_of(gear: Dictionary, equip_map: Dictionary) -> Dictionary:
	var secondaries: Array[Dictionary] = []
	for id_ in _skill_ids:
		if id_ == _primary_id: continue
		var block := _skill_block(id_,gear,false)
		if not block.is_empty(): secondaries.append(block)
	var sets: Array[Dictionary] = []
	return {"primary":_skill_block(_primary_id,gear,true),"secondaries":secondaries,"hero":{"rows":_hero_rows(gear)},"sets":sets,"effects":_effects_of(equip_map)}

## Read-only. The numbers the core uses right now.
## {primary:{id,name_key,rank,evolved,rows}, secondaries:[{...}], hero:{rows}, sets:[], effects:[{source_uid,kind,id}]}
## A row is {id,raw,value,unit_id,better:"higher"|"lower",decimals,detail,kind:"number"|"flag"}.
func stat_sheet() -> Dictionary:
	return _sheet_of(_gear_stats,equipped)

## Read-only. stat_sheet() as if bag item `uid` were worn in `slot` ("" = target_slot). Changes nothing.
## {slot, can_equip, slot_ok, level_ok, required_level, replaces_uid, veiled, before, after, sets_before, sets_after,
##  effects_gained, effects_lost, rows:[{group,id,unit_id,decimals,better,detail,kind,before,after,delta,change}]}
## change is "better", "worse" or "same" from the player's side (a smaller interval is better).
## An unknown uid returns {}.
func preview_equip(uid: int, slot: String = "") -> Dictionary:
	var item := _owned(uid)
	if item.is_empty(): return {}
	var chosen := slot
	if chosen.is_empty() or not chosen in EQUIP_SLOTS: chosen = target_slot(item)
	var slot_ok: bool = (item.slot == "ring") == (chosen in ["ring","ring2"]) and (item.slot == "ring" or chosen == item.slot)
	var level_ok := can_equip(item)
	# Gear only: a timed shrine buff is in stat_sheet() but belongs to neither side of "what if I wear this" (D13 5.2).
	var before := _sheet_of(_gear_totals(equipped),equipped)
	var map := equipped.duplicate()
	if slot_ok:
		var previous := equip_slot_of(uid)
		if not previous.is_empty() and previous != chosen: map.erase(previous)
		map[chosen] = uid
	var after := before
	if slot_ok: after = _sheet_of(_gear_totals(map),map)
	var gained: Array[Dictionary] = []
	var lost: Array[Dictionary] = []
	for e in after.effects:
		if not before.effects.has(e): gained.append(e)
	for e in before.effects:
		if not after.effects.has(e): lost.append(e)
	return {"slot":chosen,"can_equip":slot_ok and level_ok,"slot_ok":slot_ok,"level_ok":level_ok,"required_level":int(item.get("required_level",1)),
		"replaces_uid":int(equipped.get(chosen,0)),"veiled":false,"before":before,"after":after,"sets_before":before.sets,"sets_after":after.sets,
		"effects_gained":gained,"effects_lost":lost,"rows":_diff_rows(before,after)}

func _diff_rows(before: Dictionary, after: Dictionary) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	groups.append({"group":"primary","a":before.primary.get("rows",[]),"b":after.primary.get("rows",[])})
	for i in before.secondaries.size():
		groups.append({"group":String(before.secondaries[i].id),"a":before.secondaries[i].rows,"b":after.secondaries[i].rows if i < after.secondaries.size() else []})
	groups.append({"group":"hero","a":before.hero.rows,"b":after.hero.rows})
	var result: Array[Dictionary] = []
	for g in groups:
		var seen := {}
		var order: Array[Dictionary] = []
		for r in g.a:
			seen[r.id] = true
			order.append(r)
		for r in g.b:
			if not seen.has(r.id): order.append(r)
		for r in order:
			var a := {}
			var b := {}
			for x in g.a:
				if x.id == r.id: a = x
			for x in g.b:
				if x.id == r.id: b = x
			var ra := int(a.get("raw",0))
			var rb := int(b.get("raw",0))
			var va := float(a.get("value",0.0))
			var vb := float(b.get("value",0.0))
			var change := "same"
			if rb != ra: change = "better" if (rb > ra) == (r.better == "higher") else "worse"
			result.append({"group":g.group,"id":r.id,"unit_id":r.unit_id,"decimals":r.decimals,"better":r.better,"detail":r.detail,"kind":r.kind,"before":va,"after":vb,"delta":vb-va,"change":change})
	return result

func compare_item(uid: int) -> Dictionary:
	var item := _owned(uid)
	if item.is_empty(): return {}
	var slot := target_slot(item)
	var current := _owned(int(equipped.get(slot,-1)))
	return {"candidate":item.duplicate(true),"equipped":current.duplicate(true),"slot":slot,"can_equip":can_equip(item)}

func step(move: Vector2 = Vector2.ZERO) -> void:
	if mode != "playing": return
	events.clear()
	_thorns_pending.clear()
	tick += 1
	if not move.is_finite(): move = Vector2.ZERO
	var direction := move.limit_length(1.0)
	if direction.length_squared() > .001: hero.direction = direction.normalized()
	if direction.length_squared() > .001 and tick > _dash_until: _last_move_tick = tick
	var displacement: Vector2 = direction*float(hero.speed)*STEP
	if tick <= _dash_until: displacement = _dash_direction*13.5*STEP
	hero.position = _clamp_hero(hero.position+displacement)
	_spawn_wave()
	_step_enemies()
	if _terminal_mode == "defeat": return
	_rebuild_grid()
	_auto_casts()
	_step_projectiles()
	_resolve_thorns()
	if not _terminal_mode.is_empty():
		_update_metrics()
		return
	_collect_pickups()
	_cleanup()
	_refresh_mode()
	_update_metrics()

func _clamp_point(point: Vector2) -> Vector2:
	return Vector2(clampf(point.x,-BOUND,BOUND),clampf(point.y,-BOUND,BOUND))

## Where the hero may stand. The chapter core adds the trial circle here; enemies and hazards keep using _clamp_point.
func _clamp_hero(point: Vector2) -> Vector2:
	return _clamp_point(point)

func _spawn(kind: String, point: Vector2) -> bool:
	if enemies.size() >= MAX_ENTITIES: return false
	var def: Dictionary = ENEMY_DEFS[kind]
	_enemy_sequence += 1
	var hp: int = int(def.hp)*UNIT
	if kind == "walker" and tick > 35*HZ: hp = 18*UNIT
	var entity := {"id":_enemy_sequence,"generation":_epoch,"kind":kind,"position":_clamp_point(point),
		"hp_raw":hp,"max_hp_raw":hp,"radius":def.radius,"state":"move","telegraph":{},"elite":kind=="elite",
		"state_until":0,"frozen_until":0,"slow_until":0,"slow_bps":0,"freeze_stacks":0,"freeze_expires":0,
		"direction":Vector2.UP,"attack_direction":Vector2.UP,"attack_kind":"","attack_index":0,"dash_until":0,"dead_tick":-1,"attacked":false}
	enemies[entity.id] = entity
	_alive += 1
	var spawn_details := {"target_id":entity.id,"kind":kind,"elite":entity.elite}
	if not _spawn_tags.is_empty(): spawn_details.merge(_spawn_tags)
	_emit("spawn",entity.position,spawn_details)
	return true

## Extra fields for the spawn event of the body being placed right now (the opening marks its bodies). Empty in every other run.
var _spawn_tags: Dictionary = {}

## How far the basic spells look for a target (m). The chapter core narrows it during the run opening.
func _acquire_m() -> float:
	return 13.0

## Distance inside which an experience orb is drawn to the hero; `fallback` is the plain radius + 2 m. The chapter core widens it during the opening.
func _orb_pull_m(fallback: float) -> float:
	return fallback

func _spawn_point(min_radius: float, max_radius: float) -> Vector2:
	# Clamping an outside ring point at a corner must not spawn on top of the hero.
	for attempt in 12:
		var angle := _spawn_rng.randf_range(0,TAU)
		var candidate := _clamp_point(hero.position+Vector2(cos(angle),sin(angle))*_spawn_rng.randf_range(min_radius,max_radius))
		if candidate.distance_squared_to(hero.position) >= min_radius*min_radius*.64: return candidate
	var toward_center: Vector2 = -hero.position.normalized() if hero.position.length_squared() > .001 else Vector2.UP
	return _clamp_point(hero.position+toward_center*min_radius)

func _spawn_wave() -> void:
	if not _elite_spawned and tick >= ELITE_TICK:
		_elite_spawned = _spawn("elite",_spawn_point(7.0,8.0))
	if tick < _next_spawn: return
	var interval := 30 if tick < 15*HZ else (22 if tick < 35*HZ else 16)
	var amount := 2 if tick < 15*HZ else (3 if tick < 50*HZ else 4)
	_next_spawn = tick+interval
	var count := alive_count()
	for i in amount:
		if count >= MAX_ALIVE-1: break
		var point := _spawn_point(9.0,12.0)
		var roll := _spawn_rng.randi_range(0,99)
		var kind := "walker"
		if tick >= 12*HZ and roll >= 90: kind = "charger"
		elif tick >= 10*HZ and roll >= 72: kind = "ranged"
		if _spawn(kind,point): count += 1

func _step_enemies() -> void:
	# Explicit UID order makes approach steering independent of Dictionary insertion.
	# Windup/recovery/freeze anchors and active charge trajectories never get pushed.
	_rebuild_grid()
	var ids := enemies.keys()
	ids.sort()
	for id_ in ids:
		var e: Dictionary = enemies[id_]
		if e.hp_raw <= 0: continue
		if (tick < int(e.frozen_until) or tick < int(e.get("stunned_until",0))):
			# Freeze pauses attack/recovery motion time, not just the actor position.
			# Thaw cannot jump past an unseen windup and attack immediately.
			if e.state in ["windup","recover","dash"]: e.state_until += 1
			continue
		# A staggered body (the ring's short stop) neither moves nor starts an attack; unlike a freeze it does not pause the
		# recovery clock. The key exists only in a run with the spell composition.
		if tick < int(e.get("staggered_until",0)): continue
		if tick > int(e.freeze_expires): e.freeze_stacks = 0
		var def: Dictionary = _enemy_definition(e)
		var delta: Vector2 = hero.position-e.position
		var distance := delta.length()
		var toward := delta/distance if distance > .001 else Vector2.UP
		e.direction = toward
		var speed: float = float(def.speed)
		if tick < int(e.slow_until): speed *= 1.0-float(e.slow_bps)/10000.0
		if e.state == "recover":
			if tick >= int(e.state_until): e.state = "move"
			else: continue
		if e.state == "dash":
			e.position = _clamp_point(e.position+e.attack_direction*9.0*STEP)
			if e.has("guard_anchor"): _guard_leash(e)
			if not e.attacked and e.position.distance_to(hero.position) <= float(e.radius)+.28:
				_hero_damage(int(def.damage)*UNIT,e.position,_source_kind_of(e),int(e.id))
				e.attacked = true
			if tick >= int(e.state_until):
				e.state = "recover"
				e.state_until = tick+int(def.recover)
			continue
		if e.state == "windup":
			e.telegraph.remaining_ticks = maxi(0,int(e.state_until)-tick)
			if tick < int(e.state_until): continue
			e.telegraph = {}
			metrics.enemy_attacks += 1
			_emit("enemy_attack",e.position,{"target_id":e.id,"kind":e.kind,"direction":e.attack_direction,"attack_kind":e.attack_kind})
			if e.kind == "ranged": _enemy_projectiles(e)
			elif e.kind == "charger":
				e.state = "dash"
				e.state_until = tick+32
				e.attacked = false
				continue
			elif e.kind == "elite":
				_resolve_elite_attack(e,def,distance)
			else:
				if distance <= 1.15: _hero_damage(int(def.damage)*UNIT,e.position,_source_kind_of(e),int(e.id))
			e.attack_index += 1
			e.state = "recover"
			e.state_until = tick+int(def.recover)
			continue
		# A guarding elite (D13 5.2) only fights in its "fight" state; before that it stands, afterwards it walks back to its anchor.
		if e.has("guard_state") and e.guard_state != "fight":
			if e.guard_state == "return": _guard_walk_back(e,speed)
			continue
		var attack_distance := .85
		if e.kind == "ranged": attack_distance = 6.0
		elif e.kind == "charger": attack_distance = 5.0
		elif e.kind == "elite": attack_distance = 3.0 if int(e.attack_index)%2 == 0 else 6.0
		var approach := _approach_crowd(e,speed,attack_distance)
		e.position = approach.position
		if e.has("guard_anchor"): _guard_leash(e)
		delta = hero.position-e.position
		distance = delta.length()
		toward = delta/distance if distance > .001 else toward
		e.direction = toward
		# The leading movable body claims a stance; queued bodies keep steering.
		# Paid windup/recovery/freeze/dash anchors always retain their attack space.
		if distance <= attack_distance and approach.room and distance >= float(e.radius)+HERO_RADIUS+HERO_APPROACH_GAP-.015:
			e.state = "windup"
			e.state_until = tick+int(def.windup)
			e.attack_direction = toward
			e.attack_kind = "line" if e.kind == "charger" else ("fan" if e.kind == "ranged" else ("circle" if int(e.attack_index)%2 == 0 else "fan") if e.elite else "circle")
			# Telegraphs describe the actual hero-center hazard, not the AI trigger range.
			# A charger is a swept capsule: center travel4.8m, radius .43+.28m.
			var hazard_radius := float(e.radius)+.28 if e.kind == "charger" else (3.4 if e.elite else 1.15)
			var hazard_length := 4.8 if e.kind == "charger" else (17.5 if e.elite else 14.7)
			var rays: Array[Vector2] = []
			if e.attack_kind == "fan":
				var count := 7 if e.elite else 3
				for ray in count: rays.append(toward.rotated((float(ray)-float(count-1)*.5)*(.18 if e.elite else .14)))
				hazard_radius = hazard_length+.44
			e.telegraph = {"shape":e.attack_kind,"direction":toward,"radius":hazard_radius,"length":hazard_length,"width":1.42 if e.kind == "charger" else .88,"rays":rays,"remaining_ticks":int(def.windup)}
		if _terminal_mode == "defeat": return

## A guarding elite (D13 5.2) never stands farther than its leash from its anchor.
func _guard_leash(e: Dictionary) -> void:
	var anchor: Vector2 = e.guard_anchor
	var offset: Vector2 = e.position-anchor
	var leash := float(e.guard_leash)
	if offset.length_squared() > leash*leash: e.position = _clamp_point(anchor+offset.normalized()*leash)

## One step of the walk home (state "return"): straight to the anchor at the body's own speed, no crowd steering.
func _guard_walk_back(e: Dictionary, speed: float) -> void:
	var to_anchor: Vector2 = e.guard_anchor-e.position
	var distance := to_anchor.length()
	if distance <= .0001: return
	e.position = _clamp_point(e.position+to_anchor/distance*minf(distance,speed*STEP))

func _crowd_neighbors(point: Vector2, self_id: int) -> Array[int]:
	var result: Array[int] = []
	var cell := Vector2i(floori(point.x/2.0),floori(point.y/2.0))
	# Central cell first, then cardinal and diagonal cells. Every cell list is UID
	# ordered. The32-body work budget bounds pathological coincident crowds too.
	var offsets := [Vector2i.ZERO,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN,Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(1,1)]
	var examined := 0
	for offset in offsets:
		for other_id in _grid.get(cell+offset,[]):
			if int(other_id) == self_id: continue
			examined += 1
			var other: Dictionary = enemies[other_id]
			if other.hp_raw > 0 and other.position.distance_squared_to(point) < CROWD_RADIUS*CROWD_RADIUS:
				result.append(int(other_id))
			if examined >= MAX_CROWD_NEIGHBORS: break
		if examined >= MAX_CROWD_NEIGHBORS: break
	metrics.crowd_neighbor_checks += examined
	metrics.crowd_peak_neighbors = maxi(int(metrics.crowd_peak_neighbors),examined)
	return result

func _coincident_away(self_id: int, other_id: int) -> Vector2:
	# No gameplay RNG is consumed by steering; a coincident pair gets opposite,
	# stable directions instead of both choosing UP and remaining interpenetrated.
	var key := (mini(self_id,other_id)*73856093) ^ (maxi(self_id,other_id)*19349663)
	var axis := Vector2.from_angle(float(key & 1023)*TAU/1024.0)
	return axis if self_id < other_id else -axis

func _approach_crowd(e: Dictionary, speed: float, attack_distance: float) -> Dictionary:
	var origin: Vector2 = e.position
	var toward_hero: Vector2 = hero.position-origin
	var distance := toward_hero.length()
	var movement := toward_hero/distance*speed*STEP if distance > maxf(attack_distance,.001) else Vector2.ZERO
	var neighbors := _crowd_neighbors(origin,int(e.id))
	var pressure := Vector2.ZERO
	for other_id in neighbors:
		var other: Dictionary = enemies[other_id]
		var away: Vector2 = origin-other.position
		var separation := away.length()
		var desired := float(e.radius)+float(other.radius)+CROWD_GAP
		if separation >= desired: continue
		var direction := away/separation if separation > .0001 else _coincident_away(int(e.id),other_id)
		pressure += direction*(desired-separation)*.5
	var candidate := _clamp_point(origin+movement+pressure.limit_length(CROWD_PUSH_PER_STEP))
	var clearance := float(e.radius)+HERO_RADIUS+HERO_APPROACH_GAP
	var hero_away: Vector2 = candidate-hero.position
	if hero_away.length() < clearance:
		var direction := hero_away.normalized() if hero_away.length_squared() > .000001 else _coincident_away(int(e.id),0)
		var desired := _clamp_point(hero.position+direction*clearance)
		if desired.distance_to(hero.position) < clearance-.015:
			# At a world corner prefer the inward legal arc, never teleport outside.
			direction = -hero.position.normalized() if hero.position.length_squared() > .001 else direction
			desired = _clamp_point(hero.position+direction*clearance)
		candidate = _clamp_point(candidate+(desired-candidate).limit_length(CROWD_PUSH_PER_STEP))
	# Combined peer/hero correction still has one documented displacement bound.
	candidate = _clamp_point(origin+(candidate-origin).limit_length(speed*STEP+CROWD_PUSH_PER_STEP))
	var room := true
	for other_id in neighbors:
		var other: Dictionary = enemies[other_id]
		var minimum := (float(e.radius)+float(other.radius))*.92
		if candidate.distance_squared_to(other.position) < minimum*minimum:
			# Requiring all movable peers to be clear makes a compressed corner
			# queue wait forever. The front body claims the stance and rear bodies
			# yield to its anchored windup. Stable UID resolves equal-distance ties.
			var our_distance := candidate.distance_to(hero.position)
			var their_distance: float = other.position.distance_to(hero.position)
			var anchored: bool = other.state != "move" or (tick < int(other.frozen_until) or tick < int(other.get("stunned_until",0)) or tick < int(other.get("staggered_until",0)))
			if anchored or their_distance < our_distance-.001 or (absf(their_distance-our_distance) <= .001 and int(other.id) < int(e.id)):
				room = false
				break
	if candidate.distance_squared_to(origin+movement) > .000001: metrics.crowd_adjustments += 1
	return {"position":candidate,"room":room}

## raw is the damage before the hero's reduction. With tuning.heavy_hit.heavy_bps > 0 a hit of at least
## that share of the maximum life is "heavy": it grants iframe_ticks of invulnerability, and a heavy hit
## within gap_ticks of the previous full one only grazes (graze_bps of its damage, graze:true). Otherwise 24 ticks.
## `source_kind` / `source_id` say who did it (the event carries them, the snapshot does not): walker | ranged | charger | elite |
## champion | boss for a body, a dash or a shot, boss_ward for the final boss's floor strike, hazard for any other floor danger
## (id 0). A blocked hit (invulnerable) makes no event.
func _hero_damage(raw: int, from: Vector2, source_kind: String = "hazard", source_id: int = 0) -> void:
	if tick < _invulnerable_until or not _terminal_mode.is_empty(): return
	var incoming := raw
	var iframes := 24
	var graze := false
	var heavy_rule: Dictionary = tuning.get("heavy_hit",{})
	var heavy_bps := int(heavy_rule.get("heavy_bps",0))
	if heavy_bps > 0 and raw*10000 >= heavy_bps*int(hero.max_hp_raw):
		iframes = int(heavy_rule.iframe_ticks)
		if _last_heavy_tick >= 0 and tick-_last_heavy_tick < int(heavy_rule.gap_ticks):
			graze = true
			raw = raw*int(heavy_rule.graze_bps)/10000
		else: _last_heavy_tick = tick
	var result: Dictionary = Resolver.damage(raw,int(hero.hp_raw),0,_reduction_bps(_gear_stats,true))
	hero.hp_raw = int(result.hp_after_raw)
	_invulnerable_until = tick+iframes
	var details := {"damage_raw":result.total_raw,"from":from,"incoming_raw":incoming,"source_kind":source_kind,"source_id":source_id,"hp_after_raw":int(hero.hp_raw)}
	# D23 T15b: two read-only name hints for the death screen. source_key = the body's text key (the seal guardians and the final boss
	# carry one, others ""); attack_id = the attack the body was making ("circle" slam or touch, "fan" shot, "line" charge, "frost_cross"),
	# "floor_strike" for the boss's floor hazard, "" for any other hazard or a body already gone. Read from the enemy table: no new state.
	var source_body: Dictionary = enemies.get(source_id,{}) if source_id > 0 else {}
	details.source_key = String(source_body.get("title_key",""))
	details.attack_id = "floor_strike" if source_kind == "boss_ward" else String(source_body.get("attack_kind",""))
	if graze: details.graze = true
	_emit("hero_hit",hero.position,details)
	# D23 T17: thorns give back thorns_bps of the hit as it was after the graze and before the reduction. Only a body that did the hit
	# (source_id > 0) is paid, and not when this hit finished the hero. It is only written down here (see _resolve_thorns).
	var thorns_bps := int(_gear_stats.get("thorns_bps",0))
	if thorns_bps > 0 and source_id > 0 and hero.hp_raw > 0:
		_thorns_pending.append({"id":source_id,"amount":maxi(1,raw*thorns_bps/10000),"kind":source_kind})
	if hero.hp_raw <= 0:
		_terminal_mode = "defeat"
		_refresh_mode()
		_emit("defeat",hero.position)

## D23 T17: pays the thorns written by _hero_damage in this tick: one `thorns` event, then one blow through _damage_enemy with
## skill_id "gear.thorns" and reflect:true (the chapter core leaves the condition lines out of a reflect). The giver must still be
## alive and of this run. Called from step() after the projectile step and before the end check, so a boss that dies of it closes the run.
func _resolve_thorns() -> void:
	if _thorns_pending.is_empty(): return
	var owed: Array[Dictionary] = _thorns_pending.duplicate()
	_thorns_pending.clear()
	for entry in owed:
		var id_ := int(entry.id)
		if not _terminal_mode.is_empty() or not enemies.has(id_): continue
		var e: Dictionary = enemies[id_]
		if e.hp_raw <= 0 or e.generation != _epoch: continue
		var amount := int(entry.amount)
		if not metrics.has("thorns"): metrics.thorns = {"hits":0,"raw":0,"kills":0}
		metrics.thorns.hits = int(metrics.thorns.hits)+1
		metrics.thorns.raw = int(metrics.thorns.raw)+amount
		_emit("thorns",e.position,{"target_id":id_,"amount_raw":amount,"source_kind":String(entry.kind),"from":hero.position})
		_cast_sequence += 1
		var effects := {"damage_raw":amount,"proc_depth":0,"death_burst":0,"shatter_count":0,"radius_cm":0,"slow_bps":0,"freeze_stacks":0,"pierce":0,"hit_budget":1,"cooldown_ticks":0,"projectiles":0,"chain_targets":0,"branches":0}
		var context := {"uid":_cast_sequence,"skill_id":"gear.thorns","effects":effects,"remaining_hits":1,"hit_ids":[],"evolved":false,"reflect":true}
		var before := kills
		_damage_enemy(id_,context,0)
		if kills > before: metrics.thorns.kills = int(metrics.thorns.kills)+(kills-before)

## D23 T17: counts one kill for the streak (gear streak_projectiles, window and threshold from tuning.gear_conditions). A descent's
## kill is not counted. Reaching the threshold arms the next primary cast; while armed nothing is counted.
func _streak_note(details: Dictionary) -> void:
	var gain := int(_gear_stats.get("streak_projectiles",0))
	if gain <= 0 or _streak_charge > 0: return
	var rule: Dictionary = tuning.get("gear_conditions",{})
	var need := int(rule.get("streak_kills",0))
	var window := int(rule.get("streak_window_ticks",0))
	if need <= 0 or window <= 0: return
	if String(details.get("skill_id","")).begins_with("descent."): return
	_streak_kills.append(tick)
	while not _streak_kills.is_empty() and tick-_streak_kills[0] >= window: _streak_kills.pop_front()
	if _streak_kills.size() < need: return
	_streak_charge = mini(4,gain)
	var counted := _streak_kills.size()
	_streak_kills.clear()
	if not metrics.has("streak"): metrics.streak = {"armed":0,"casts":0,"extra":0}
	metrics.streak.armed = int(metrics.streak.armed)+1
	_emit("streak_ready",hero.position,{"charge":_streak_charge,"kills":counted})

func _enemy_projectiles(e: Dictionary) -> void:
	var hostile := 0
	for p in projectiles:
		if p.hostile: hostile += 1
	var count := 7 if e.elite else 3
	for i in count:
		if hostile >= MAX_HOSTILE_PROJECTILES or projectiles.size() >= MAX_PROJECTILES: break
		var spread: float = (float(i)-float(count-1)*.5)*(.18 if e.elite else .14)
		_projectile_sequence += 1
		projectiles.append({"uid":_projectile_sequence,"position":e.position,"previous":e.position,"direction":e.attack_direction.rotated(spread),
			"speed":5.0 if e.elite else 4.2,"radius":.16,"skill_id":"hostile."+e.kind,"hostile":true,"damage_raw":int(_enemy_definition(e).damage)*UNIT,"expires":tick+210,"cast_id":0,"pierce_left":0,"hit_ids":[]})
		_hostile_src[_projectile_sequence] = {"id":int(e.id),"kind":_source_kind_of(e)}
		hostile += 1

## The kind a hero_hit event names for a body: its kind (walker, ranged, charger) or, for the strong ones, its role.
func _source_kind_of(e: Dictionary) -> String:
	var role := _enemy_role(e)
	return String(e.kind) if role == "normal" else role

## normal | elite | champion | boss. The base core knows only normal and elite; the chapter core tells the guardians apart.
func _enemy_role(e: Dictionary) -> String:
	return "elite" if e.elite else "normal"

func _rebuild_grid() -> void:
	_grid.clear()
	var ids := enemies.keys()
	ids.sort()
	for id_ in ids:
		var e: Dictionary = enemies[id_]
		if e.hp_raw <= 0: continue
		var cell := Vector2i(floori(e.position.x/2.0),floori(e.position.y/2.0))
		if not _grid.has(cell): _grid[cell] = []
		_grid[cell].append(int(e.id))

func _near(point: Vector2, radius: float) -> Array[int]:
	var result: Array[int] = []
	var low := Vector2i(floori((point.x-radius)/2.0),floori((point.y-radius)/2.0))
	var high := Vector2i(floori((point.x+radius)/2.0),floori((point.y+radius)/2.0))
	for x in range(low.x,high.x+1):
		for y in range(low.y,high.y+1):
			for id_ in _grid.get(Vector2i(x,y),[]):
				var e: Dictionary = enemies[id_]
				if e.hp_raw > 0 and e.position.distance_squared_to(point) <= radius*radius: result.append(id_)
	result.sort_custom(func(a: int,b: int) -> bool:
		var da: float = enemies[a].position.distance_squared_to(point)
		var db: float = enemies[b].position.distance_squared_to(point)
		return a < b if is_equal_approx(da,db) else da < db)
	return result

func _auto_casts() -> void:
	if not _ring_pending.is_empty(): _step_ring_pulses()
	for id_ in _skill_ids:
		if tick < int(_next_cast.get(id_,0)): continue
		if debug_secondary_off and id_ != _primary_id: continue
		var skill := effective_skill(id_)
		if skill.is_empty(): continue
		if _is_ring(id_):
			_cast_ring(id_,skill)
			continue
		var nearest := _near(hero.position,_acquire_m())
		if nearest.is_empty(): continue
		var target: Dictionary = enemies[nearest[0]]
		# D23 T17: an armed streak adds its projectiles (an arc: chain targets) to this one primary cast only.
		var streak := 0
		if id_ == _primary_id and _streak_charge > 0:
			streak = _streak_charge
			var streak_gear: Dictionary = _gear_with_conditions().duplicate()
			streak_gear.projectiles = int(streak_gear.get("projectiles",0))+streak
			skill = _skill_with(id_,streak_gear)
		# With the spell composition a basic spell may aim at a far shooter or a controlled enemy first (I0, I1); without it
		# this stays the nearest enemy and nothing below changes.
		var aim := ""
		if not spells.is_empty():
			var aimed := _aim(id_,nearest)
			target = enemies[aimed.id]
			aim = String(aimed.how)
		var direction: Vector2 = (target.position-hero.position).normalized()
		var effects: Dictionary = skill.effects.duplicate(true)
		# D20: the evolved ember books falls instead of shooting (tuning.meteor); damage and radius get the block's multipliers.
		var meteor: bool = id_ == "chapter1.skill.ember" and bool(skill.evolved) and tuning.has("meteor")
		if meteor:
			effects.damage_raw = int(effects.damage_raw)*int(tuning.meteor.damage_bps)/10000
			effects.radius_cm = int(effects.radius_cm)*int(tuning.meteor.radius_bps)/10000
		_cast_sequence += 1
		var context := {"uid":_cast_sequence,"skill_id":id_,"effects":effects,"remaining_hits":int(effects.hit_budget),"hit_ids":[],"evolved":skill.evolved}
		if aim == "kind":
			context.aim = "kind"
			_ward_add("i0_casts")
		_contexts[context.uid] = context
		_next_cast[id_] = tick+int(effects.cooldown_ticks)
		metrics.casts[id_] = int(metrics.casts.get(id_,0))+1
		if streak > 0:
			_streak_charge = 0
			if not metrics.has("streak"): metrics.streak = {"armed":0,"casts":0,"extra":0}
			metrics.streak.casts = int(metrics.streak.casts)+1
			metrics.streak.extra = int(metrics.streak.extra)+streak
		if id_ == "chapter1.skill.arc":
			var positions := _chain(target,context)
			var arc_details := {"skill_id":id_,"direction":direction,"effects":effects.duplicate(true),"targets":positions,"segments":context.get("arc_segments",[]),"evolved":skill.evolved}
			if streak > 0: arc_details.streak = streak
			if aim == "kind": arc_details.prefer = "kind"
			_emit("cast",hero.position,arc_details)
			# A chain that left child projectiles behind keeps its context for them.
			if not _children_pending_for(int(context.uid)): _contexts.erase(context.uid)
		else:
			var shot_details := {"skill_id":id_,"direction":direction,"effects":effects.duplicate(true),"targets":[],"evolved":skill.evolved}
			if streak > 0: shot_details.streak = streak
			if aim == "kind": shot_details.prefer = "kind"
			_emit("cast",hero.position,shot_details)
			var count: int = effects.projectiles
			if meteor:
				_book_meteors(target,effects,context)
				continue
			# Angle between neighbouring shots of one cast (tuning.hero_shot.spread_mrad, default 160 = .16 rad).
			var spread_step := float(int(tuning.get("hero_shot",{}).get("spread_mrad",160)))/1000.0
			for i in count:
				if projectiles.size() >= MAX_PROJECTILES: break
				_projectile_sequence += 1
				var spread := (float(i)-float(count-1)*.5)*spread_step
				projectiles.append({"uid":_projectile_sequence,"position":hero.position,"previous":hero.position,"direction":direction.rotated(spread),
					"speed":14.0 if id_ == "chapter1.skill.ember" else 16.0,"radius":.24 if skill.evolved else .16,"skill_id":id_,"hostile":false,
					"damage_raw":int(effects.damage_raw),"expires":tick+100,"cast_id":int(context.uid),"pierce_left":int(effects.pierce),"hit_ids":[]})

## D20: where an enemy will be after `ticks` if it keeps walking (zero when it stands, is frozen, stunned, or in an attack).
func _enemy_velocity(e: Dictionary) -> Vector2:
	if e.state != "move" or tick < int(e.frozen_until) or tick < int(e.get("stunned_until",0)) or tick < int(e.get("staggered_until",0)): return Vector2.ZERO
	var speed := float(ENEMY_DEFS[e.kind].speed)
	if tick < int(e.slow_until): speed *= float(10000-int(e.slow_bps))/10000.0
	return e.direction*speed

## D20: book the falls of one cast. The first lands on the aimed enemy's place (led by tuning.meteor.lead_bps of its walk over
## fall_ticks), the others are scattered round it by a fixed spiral (no random number): angle from the cast uid, radius up to scatter_cm.
func _book_meteors(target: Dictionary, effects: Dictionary, context: Dictionary) -> void:
	var rule: Dictionary = tuning.meteor
	var fall := int(rule.fall_ticks)
	var lead := float(int(rule.lead_bps))/10000.0
	var spot := _clamp_point(target.position+_enemy_velocity(target)*float(fall)*STEP*lead)
	var count := int(effects.projectiles)
	var scatter := float(int(rule.scatter_cm))/100.0
	var start_angle := deg_to_rad(float((int(context.uid)*37)%360))
	for i in count:
		if _meteors.size() >= MAX_METEORS: break
		var offset := Vector2.ZERO
		if i > 0 and scatter > 0.0: offset = Vector2.from_angle(start_angle+float(i)*2.3999632)*scatter*sqrt(float(i)/float(maxi(1,count-1)))
		_meteor_sequence += 1
		var item := {"id":_meteor_sequence,"position":_clamp_point(spot+offset),"land_tick":tick+fall,"cast_id":int(context.uid)}
		_meteors.append(item)
		_emit("meteor_cast",item.position,{"id":item.id,"land_tick":item.land_tick,"radius_cm":int(effects.radius_cm),"cast_uid":int(context.uid),"origin":hero.position})

## D20: the falls that are due land: the explosion event (with the fall's id), then every enemy in the radius takes the cast's damage
## through the normal path (budget, death burst chain and sparks as before).
func _step_meteors() -> void:
	if _meteors.is_empty(): return
	var waiting: Array[Dictionary] = []
	var due: Array[Dictionary] = []
	for m in _meteors:
		if tick >= int(m.land_tick): due.append(m)
		else: waiting.append(m)
	_meteors = waiting
	for m in due:
		if not _terminal_mode.is_empty(): break
		if not _contexts.has(m.cast_id): continue
		var context: Dictionary = _contexts[m.cast_id]
		_emit("explosion",m.position,{"skill_id":context.skill_id,"radius_cm":int(context.effects.radius_cm),"cast_uid":context.uid,"evolved":context.evolved,"meteor":int(m.id)})
		_area_hit(m.position,float(int(context.effects.radius_cm))/100.0,context,-1,0)

func _is_ring(id_: String) -> bool:
	return not spells.is_empty() and String(spells.spells.get(id_,{}).get("role","")) == "ring"

## Adds to a counter of metrics.ward (the ring and aim tally of a run with the composition). Nothing happens without it.
func _ward_add(key: String, amount: int = 1) -> void:
	if metrics.has("ward"): metrics.ward[key] = int(metrics.ward.get(key,0))+amount

## True while the enemy is under the control `cls` (frozen | stunned | staggered | slowed) that `skill_id` did not put there
## itself (a spell never counts the control it caused: the lance's own slow gives the lance no bonus). An empty `skill_id` counts all.
## Slowed means a slow of at least 20%.
func _cc_active(e: Dictionary, cls: String, skill_id: String) -> bool:
	match cls:
		"frozen": if tick >= int(e.frozen_until): return false
		"stunned": if tick >= int(e.get("stunned_until",0)): return false
		"staggered": if tick >= int(e.get("staggered_until",0)): return false
		"slowed": if tick >= int(e.slow_until) or int(e.slow_bps) < 2000: return false
		_: return false
	return skill_id.is_empty() or String(e.get("cc_src",{}).get(cls,"")) != skill_id

## Where a basic spell shoots first: {id, how}. how = "kind" (I0), "cc" (I1) or "" (the nearest enemy, as without the composition).
## `nearest` is the enemies within 13 m, nearest first (the grid search that every cast already does; no random number).
## I0: with no uncontrolled ordinary enemy within prefer_when_clear_cm, the nearest enemy of prefer_kinds within prefer_kind_cm.
## I1: else the nearest enemy within prefer_cc_cm that is frozen, stunned or staggered by another spell.
func _aim(id_: String, nearest: Array[int]) -> Dictionary:
	var spell: Dictionary = spells.spells.get(id_,{})
	var kinds: Array = spell.get("prefer_kinds",[])
	var kind_m := float(int(spell.get("prefer_kind_cm",0)))/100.0
	if not kinds.is_empty() and kind_m > 0.0:
		var clear_m := float(int(spell.get("prefer_when_clear_cm",0)))/100.0
		var clear := true
		for candidate in nearest:
			var c: Dictionary = enemies[candidate]
			if c.position.distance_to(hero.position) > clear_m: break
			if not c.elite and not (_cc_active(c,"frozen","") or _cc_active(c,"stunned","") or _cc_active(c,"staggered","")):
				clear = false
				break
		if clear:
			for candidate in nearest:
				var c: Dictionary = enemies[candidate]
				if c.position.distance_to(hero.position) > kind_m: break
				if c.kind in kinds and not c.elite: return {"id":candidate,"how":"kind"}
	var cc_m := float(int(spell.get("prefer_cc_cm",0)))/100.0
	if cc_m > 0.0 and not spell.get("vs_cc",{}).is_empty():
		for candidate in nearest:
			var c: Dictionary = enemies[candidate]
			if c.position.distance_to(hero.position) > cc_m: break
			if _cc_active(c,"frozen",id_) or _cc_active(c,"stunned",id_) or _cc_active(c,"staggered",id_): return {"id":candidate,"how":"cc"}
	return {"id":nearest[0],"how":""}

## True while the enemy carries this status (count above zero, not expired). Only a run with the composition has any.
func _has_status(e: Dictionary, status: String) -> bool:
	var entry: Variant = e.get("status",{}).get(status)
	return entry is Dictionary and int(entry.n) > 0 and tick < int(entry.until)

## Living enemies inside the ring, nearest first; the spell's preferred status first (still nearest first inside each
## group), cut to ring_targets when the effect has one. The hit budget cuts the rest when the targets are struck.
func _ring_targets(id_: String, effects: Dictionary) -> Array[int]:
	var inside := _near(hero.position,float(effects.ring_radius_cm)/100.0)
	var prefer := String(spells.spells[id_].get("prefer",""))
	var ordered: Array[int] = []
	if prefer.is_empty(): ordered.assign(inside)
	else:
		var rest: Array[int] = []
		for target in inside:
			if _has_status(enemies[target],prefer): ordered.append(target)
			else: rest.append(target)
		ordered.append_array(rest)
	# A detonation with block_targets (I2) may let the strike reach that many more targets, so keep that many in the list;
	# _ring_strike stops at ring_targets plus what the hits earned.
	var limit := int(effects.get("ring_targets",0))
	var spare := 0
	for status in spells.spells[id_].detonates: spare = maxi(spare,int(spells.spells[id_].detonates[status].get("block_targets",0)))
	if limit > 0 and ordered.size() > limit+spare: ordered.resize(limit+spare)
	return ordered

## One ring cast. It is cast only while an enemy stands inside the ring, so the cooldown never runs idle.
func _cast_ring(id_: String, skill: Dictionary) -> void:
	var effects: Dictionary = skill.effects.duplicate(true)
	var targets := _ring_targets(id_,effects)
	if targets.is_empty(): return
	_next_cast[id_] = tick+int(effects.cooldown_ticks)
	metrics.casts[id_] = int(metrics.casts.get(id_,0))+1
	_ward_add("casts")
	_ring_strike(id_,effects,targets,bool(skill.evolved),1)
	for pulse in range(2,int(effects.ring_pulses)+1):
		_ring_pending.append({"due":tick+24*(pulse-1),"skill_id":id_,"effects":effects.duplicate(true),"evolved":bool(skill.evolved),"pulse":pulse})

## A pulse is a cast of its own (fresh hit budget, nothing shared with the first pulse).
func _ring_strike(id_: String, effects: Dictionary, targets: Array[int], evolved: bool, pulse: int) -> void:
	_cast_sequence += 1
	var context := {"uid":_cast_sequence,"skill_id":id_,"effects":effects,"remaining_hits":int(effects.hit_budget),"hit_ids":[],"evolved":evolved}
	var positions: Array[Vector2] = []
	var limit := int(effects.get("ring_targets",0))
	for index in targets.size():
		if limit > 0 and index >= limit: break
		positions.append(enemies[targets[index]].position)
	var details := {"skill_id":id_,"direction":hero.direction,"effects":effects.duplicate(true),"targets":positions,"evolved":evolved,"shape":"ring","radius_cm":int(effects.ring_radius_cm)}
	if pulse > 1: details.pulse = pulse
	_emit("cast",hero.position,details)
	for index in targets.size():
		# Past ring_targets only what the detonations in this strike earned (context.ring_extra, I2) is struck.
		if limit > 0 and index >= limit+int(context.get("ring_extra",0)): break
		if not _terminal_mode.is_empty() or int(context.remaining_hits) <= 0: break
		_damage_enemy(targets[index],context,0)

func _step_ring_pulses() -> void:
	var left: Array[Dictionary] = []
	var due: Array[Dictionary] = []
	for entry in _ring_pending:
		if tick < int(entry.due): left.append(entry)
		else: due.append(entry)
	_ring_pending = left
	for entry in due:
		if not _terminal_mode.is_empty(): break
		var targets := _ring_targets(String(entry.skill_id),entry.effects)
		if not targets.is_empty(): _ring_strike(String(entry.skill_id),entry.effects,targets,bool(entry.evolved),int(entry.pulse))

func _chain(first: Dictionary, context: Dictionary) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	context.arc_segments=[]
	var effects: Dictionary = context.effects
	var origin: Vector2 = hero.position
	var preferred := int(first.id)
	for branch in int(effects.branches):
		var at := origin
		for bounce in int(effects.chain_targets):
			var target_id := -1
			if branch == 0 and bounce == 0: target_id = preferred
			else:
				for id_ in _near(at,float(effects.radius_cm)/100.0):
					if not id_ in context.hit_ids:
						target_id = id_
						break
			if target_id < 0 or int(context.remaining_hits) <= 0: break
			var target: Dictionary = enemies[target_id]
			positions.append(target.position)
			context.arc_segments.append({"from":at,"to":target.position,"branch":branch})
			at = target.position
			_damage_enemy(target_id,context,0)
	return positions

func _segment_distance_sq(point: Vector2, start_: Vector2, end_: Vector2) -> float:
	var line := end_-start_
	var t := clampf((point-start_).dot(line)/maxf(line.length_squared(),.000001),0,1)
	return point.distance_squared_to(start_+line*t)

func _children_pending_for(cast_id: int) -> bool:
	for entry in _pending_children:
		if int(entry.p.cast_id) == cast_id: return true
	return false

## Friendly projectiles in flight, counted once per projectile step (removals during the step are not subtracted).
func _friendly_in_flight() -> int:
	if _friendly_tick != tick:
		_friendly_tick = tick
		_friendly_count = 0
		for p in projectiles:
			if not p.hostile: _friendly_count += 1
	return _friendly_count

## A killed enemy sprays the cast's own spell. Needs tuning.children[skill]; only the primary skill spawns children.
## Children share the parent's damage context, so the cast's hit budget still caps total damage.
## With children[skill].evolved_only only the evolved primary leaves children behind.
func _queue_children(e: Dictionary, context: Dictionary) -> void:
	var rule: Dictionary = tuning.get("children",{}).get(context.skill_id,{})
	if rule.is_empty() or int(rule.count) <= 0 or context.skill_id != _primary_id: return
	# A frost-field pulse is not a cast: it leaves no sparks behind.
	if bool(context.get("field",false)): return
	if bool(rule.get("evolved_only",false)) and not bool(context.get("evolved",false)): return
	# A cast whose hit budget is spent deals no more damage, so it leaves no decorative sparks either.
	if int(context.remaining_hits) <= 0: return
	if not context.has("children_left"): context.children_left = int(rule.per_cast)
	var count := int(rule.count)
	var start_angle := deg_to_rad(float((int(e.id)*37)%360))
	var created := 0
	for i in count:
		if int(context.children_left) <= 0: break
		if _friendly_in_flight()+_pending_children.size() >= int(tuning.friendly_projectile_cap):
			metrics.children_dropped = int(metrics.get("children_dropped",0))+1
			continue
		context.children_left -= 1
		_projectile_sequence += 1
		created += 1
		_pending_children.append({"p":{"uid":_projectile_sequence,"position":e.position,"previous":e.position,"direction":Vector2.from_angle(start_angle+TAU*float(i)/float(count)),
			"speed":float(rule.speed),"radius":.14,"skill_id":context.skill_id,"hostile":false,"damage_raw":int(context.effects.damage_raw),
			"expires":tick+int(rule.life_ticks),"cast_id":int(context.uid),"pierce_left":0,"hit_ids":[int(e.id)],"child":true},"context":context})
	if created > 0: _emit("child_projectiles",e.position,{"target_id":int(e.id),"skill_id":context.skill_id,"count":created,"cast_uid":context.uid})

func _step_projectiles() -> void:
	_friendly_tick = -1
	_step_meteors()
	var remaining: Array[Dictionary] = []
	for p in projectiles:
		if not _terminal_mode.is_empty(): break
		if tick >= int(p.expires):
			if p.hostile and not _hostile_src.is_empty(): _hostile_src.erase(int(p.uid))
			continue
		p.previous = p.position
		p.position += p.direction*float(p.speed)*STEP
		var remove := false
		if p.hostile:
			if _segment_distance_sq(hero.position,p.previous,p.position) <= pow(float(p.radius)+.28,2):
				var shooter: Dictionary = _hostile_src.get(int(p.uid),{})
				_hero_damage(int(p.damage_raw),p.position,String(shooter.get("kind",String(p.skill_id).trim_prefix("hostile."))),int(shooter.get("id",0)))
				_hostile_src.erase(int(p.uid))
				remove = true
		else:
			if not _contexts.has(p.cast_id): continue
			var context: Dictionary = _contexts[p.cast_id]
			var midpoint: Vector2 = (p.previous+p.position)*.5
			var query_radius: float = p.previous.distance_to(p.position)*.5+float(p.radius)+1.0
			for id_ in _near(midpoint,query_radius):
				if id_ in p.hit_ids: continue
				var e: Dictionary = enemies[id_]
				if _segment_distance_sq(e.position,p.previous,p.position) > pow(float(e.radius)+float(p.radius),2): continue
				p.hit_ids.append(id_)
				_damage_enemy(id_,context,0)
				if p.skill_id == "chapter1.skill.ember" and context.effects.radius_cm > 0:
					_emit("explosion",p.position,{"skill_id":p.skill_id,"radius_cm":context.effects.radius_cm,"cast_uid":context.uid,"evolved":context.evolved})
					_area_hit(p.position,float(context.effects.radius_cm)/100.0,context,id_,0)
				if int(p.pierce_left) <= 0 or int(context.remaining_hits) <= 0:
					remove = true
					break
				p.pierce_left -= 1
		if not remove: remaining.append(p)
	projectiles = remaining
	if not _pending_children.is_empty():
		for entry in _pending_children:
			if projectiles.size() >= MAX_PROJECTILES:
				metrics.children_dropped = int(metrics.get("children_dropped",0))+1
				continue
			projectiles.append(entry.p)
			_contexts[int(entry.context.uid)] = entry.context
		_pending_children.clear()
	var active: Dictionary = {}
	for p in projectiles:
		if not p.hostile: active[p.cast_id] = true
	for m in _meteors: active[m.cast_id] = true
	for uid in _contexts.keys():
		if not active.has(uid): _contexts.erase(uid)

func _area_hit(position: Vector2, radius: float, context: Dictionary, exclude: int, depth: int) -> void:
	for id_ in _near(position,radius):
		if id_ == exclude or int(context.remaining_hits) <= 0: continue
		_damage_enemy(id_,context,depth)

func _damage_enemy(id_: int, context: Dictionary, depth: int) -> void:
	if not _terminal_mode.is_empty() or not enemies.has(id_) or int(context.remaining_hits) <= 0: return
	var e: Dictionary = enemies[id_]
	if e.hp_raw <= 0 or e.generation != _epoch: return
	# Arc has one hit per entity across both direct branches and death procs in a cast.
	# Fire/frost may hit an entity with separate projectiles, each with its own hit_ids.
	if context.skill_id == "chapter1.skill.arc":
		if id_ in context.hit_ids: return
		context.hit_ids.append(id_)
	context.remaining_hits -= 1
	var effect: Dictionary = context.effects
	var was_frozen: bool = tick < int(e.frozen_until)
	var result: Dictionary = Resolver.damage(int(effect.damage_raw),int(e.hp_raw))
	e.hp_raw = int(result.hp_after_raw)
	metrics.damage_raw += int(result.total_raw)
	metrics.hits[context.skill_id] = int(metrics.hits.get(context.skill_id,0))+1
	if context.skill_id == "chapter1.skill.frost":
		e.slow_until = tick+100
		e.slow_bps = int(effect.slow_bps)
		if int(effect.freeze_stacks) > 0:
			e.freeze_stacks += 1
			e.freeze_expires = tick+180
			if int(e.freeze_stacks) >= int(effect.freeze_stacks):
				e.frozen_until = tick+(12 if e.elite else 75)
				e.freeze_stacks = 0
	_emit("hit",e.position,{"target_id":id_,"skill_id":context.skill_id,"damage_raw":int(result.total_raw),"frozen":tick<int(e.frozen_until),"shatter":was_frozen and int(effect.shatter_count)>0,
		"radius_cm":int(effect.radius_cm),"blast_radius_cm":int(effect.radius_cm) if context.skill_id == "chapter1.skill.ember" else 0,"cast_uid":context.uid,"evolved":context.evolved})
	if e.hp_raw > 0: return
	e.state = "dead"
	_alive -= 1
	e.dead_tick = tick
	e.telegraph = {}
	kills += 1
	_emit("death",e.position,{"target_id":id_,"kind":e.kind,"elite":e.elite,"skill_id":context.skill_id,"role":_enemy_role(e)})
	_drop_orb(e.position,int(_enemy_definition(e).xp))
	_maybe_drop_item(e)
	if depth < int(effect.proc_depth) and int(effect.death_burst) > 0:
		# Arc radius_cm means chain search reach, never the residual pulse size.
		var burst_radius := 3.0 if context.skill_id == "chapter1.skill.arc" else maxf(1.5,float(effect.radius_cm)/100.0)
		_emit("explosion",e.position,{"skill_id":context.skill_id,"radius_cm":int(burst_radius*100),"cast_uid":context.uid,"evolved":context.evolved,"proc":true})
		_area_hit(e.position,burst_radius,context,id_,depth+1)
	if was_frozen and int(effect.shatter_count) > 0 and depth == 0:
		_emit("shatter",e.position,{"skill_id":context.skill_id,"radius_cm":350,"count":int(effect.shatter_count),"cast_uid":context.uid,"evolved":context.evolved})
		var remaining: int = effect.shatter_count
		for other in _near(e.position,3.5):
			if other == id_ or remaining <= 0: continue
			_damage_enemy(other,context,1)
			remaining -= 1
	if e.elite:
		_on_elite_defeated(e)

func _enemy_definition(e: Dictionary) -> Dictionary:
	return ENEMY_DEFS[e.kind]

func _resolve_elite_attack(e: Dictionary,definition: Dictionary,distance: float) -> void:
	if e.attack_kind == "circle" and distance <= 3.4: _hero_damage(int(definition.damage)*UNIT,e.position,_source_kind_of(e),int(e.id))
	elif e.attack_kind == "fan": _enemy_projectiles(e)

func _on_elite_defeated(_e: Dictionary) -> void:
	# The representative encounter ends here. The full chapter overrides only
	# this objective hook; damage, proc budgets and actual kill still happen above.
	_elite_killed = true
	_terminal_mode = "victory"
	_refresh_mode()
	_emit("victory",hero.position,{"kills":kills,"elapsed":elapsed()})

func _drop_orb(position: Vector2, amount: int) -> void:
	if orbs.size() >= MAX_ORBS:
		var target := orbs.size()-1
		if tuning.get("orbs",{}).get("overflow","last") == "nearest": target = _nearest_orb(position)
		orbs[target].amount += amount
		metrics.orbs_merged += 1
		return
	_orb_sequence += 1
	orbs.append({"uid":_orb_sequence,"position":position,"amount":amount})

## Index of the orb closest to a point; equal distances go to the smaller uid.
func _nearest_orb(point: Vector2) -> int:
	var best := 0
	var best_distance := INF
	for i in orbs.size():
		var distance := point.distance_squared_to(orbs[i].position)
		if distance < best_distance or (distance == best_distance and int(orbs[i].uid) < int(orbs[best].uid)):
			best = i
			best_distance = distance
	return best

## Experience entering the run from any source. The soul bonus is carried in ten-thousandths.
func _gain_xp(amount: int) -> int:
	_soul_carry += amount*int(_gear_stats.get("soul_gain_bps",0))
	var gained := amount+_soul_carry/10000
	_soul_carry %= 10000
	growth.award_xp(gained)
	metrics.collected_xp += gained
	return gained

func _maybe_drop_item(e: Dictionary) -> void:
	var thresholds := [6,24,55,100]
	var forced: bool = _guaranteed_drops < thresholds.size() and kills >= int(thresholds[_guaranteed_drops])
	if not e.elite and not forced and _loot_rng.randi_range(0,99) != 0: return
	if e.elite:
		# Objective reward is directly owned, independent of ground/ordinary capacity.
		# There is only one objective in this run; the reserved slot bounds total65.
		if _elite_reward_uid != 0 or inventory.size() >= MAX_INVENTORY+MAX_OBJECTIVE_REWARDS: return
	elif items.size() >= MAX_GROUND_ITEMS or inventory.size() >= MAX_INVENTORY: return
	var template_index := _guaranteed_drops if forced else _loot_rng.randi_range(0,ITEM_TEMPLATES.size()-1)
	if forced: _guaranteed_drops += 1
	_item_sequence += 1
	var item: Dictionary = ITEM_TEMPLATES[template_index].duplicate(true)
	item.uid = _item_sequence
	item.position = e.position
	item.quality = "rare" if e.elite else ("magic" if template_index != 1 else "common")
	item.collected = false
	if e.elite: item.objective_reward = true
	item.drop_tick = tick
	# Distinct bounded rolls provide a comparison without changing the guaranteed shape effect.
	if item.stats.has("damage_bps"): item.stats.damage_bps += _loot_rng.randi_range(0,5)*100
	if item.stats.has("max_hp_raw"): item.stats.max_hp_raw += _loot_rng.randi_range(0,5)*UNIT
	metrics.dropped_items += 1
	_emit("item_drop",item.position,{"item":item.duplicate(true)})
	if e.elite:
		item.collected = true
		_elite_reward_uid = int(item.uid)
		inventory.append(item)
		metrics.picked_items += 1
		_emit("item_pickup",hero.position,{"item":item.duplicate(true)})
	else: items.append(item)

func _collect_pickups() -> void:
	var radius := 1.3+float(_gear_stats.get("pickup_radius_cm",0))/100.0
	var leftover: Array[Dictionary] = []
	var pull := _orb_pull_m(radius+2.0)
	for orb in orbs:
		var delta: Vector2 = hero.position-orb.position
		var distance := delta.length()
		if distance < pull:
			orb.position += delta.normalized()*minf(distance,9.0*STEP)
		if orb.position.distance_squared_to(hero.position) <= radius*radius:
			# Soul gain is carried in ten-thousandths so small orbs still add up.
			_gain_xp(int(orb.amount))
			# amount is the orb's face value; the XP really gained (soul bonus) is in orb_vacuum.amount / metrics.collected_xp.
			_emit("xp_pickup",orb.position,{"amount":orb.amount})
		else: leftover.append(orb)
	orbs = leftover
	var ground: Array[Dictionary] = []
	for item in items:
		if item.position.distance_squared_to(hero.position) <= pow(radius+.3,2) and inventory.size() < MAX_INVENTORY:
			item.collected = true
			inventory.append(item)
			metrics.picked_items += 1
			_emit("item_pickup",hero.position,{"item":item.duplicate(true)})
		elif tick-int(item.drop_tick) < 180*HZ or item.quality in _kept_qualities: ground.append(item)
	items = ground
	if not growth.snapshot().pending_levels.is_empty():
		_emit("level_choice",hero.position,{"level":growth.snapshot().level})

func _cleanup() -> void:
	var alive := 0
	for id_ in enemies.keys():
		var e: Dictionary = enemies[id_]
		if e.hp_raw > 0: alive += 1
		if e.hp_raw <= 0 and tick-int(e.dead_tick) > 75: enemies.erase(id_)
		elif e.hp_raw > 0 and e.position.distance_squared_to(hero.position) > 25.0*25.0 and not e.elite and not e.has("guard_uid") and e.state == "move" and (tick >= int(e.frozen_until) and tick >= int(e.get("stunned_until",0))):
			# Recycle only a freely approaching survivor. A paid windup, dash,
			# recovery or frozen body keeps its attack/telegraph origin until it
			# returns to movement; relocation never creates another reward identity.
			e.position = _spawn_point(12.0,12.0)
	_alive = alive

func _update_metrics() -> void:
	metrics.max_alive = maxi(int(metrics.max_alive),alive_count())
	metrics.peak_projectiles = maxi(int(metrics.peak_projectiles),projectiles.size())

func _emit(type: String, position: Vector2, details: Dictionary = {}) -> void:
	_event_sequence += 1
	var event := details.duplicate(true)
	event.type = type
	event.position = position
	event.tick = tick
	event.seq = _event_sequence
	if events.size() >= MAX_EVENTS:
		events.pop_front()
		metrics.events_dropped = int(metrics.get("events_dropped",0))+1
	events.append(event)
	if type == "death": _streak_note(details)

func snapshot() -> Dictionary:
	var result := {"mode":mode,"tick":tick,"kills":kills,"hero":hero.duplicate(true),"enemies":enemies.duplicate(true),
		"projectiles":projectiles.duplicate(true),"orbs":orbs.duplicate(true),"items":items.duplicate(true),
		"inventory":inventory.duplicate(true),"equipped":equipped.duplicate(true),"growth":growth.snapshot(),
		"metrics":metrics.duplicate(true),"elite_spawned":_elite_spawned,"elite_killed":_elite_killed,
		"next_dash_tick":_next_dash,"epoch":_epoch,"elite_reward_uid":_elite_reward_uid}
	# D23 T1-B: the two clocks of the dash and movement conditions exist only while gear that reads them is worn (no key otherwise).
	if int(_gear_stats.get("after_dash_bps",0)) > 0 or int(_gear_stats.get("moving_damage_bps",0)) > 0 or int(_gear_stats.get("after_dash_guard_bps",0)) > 0:
		result.gear_clock = {"dash_until":_dash_until,"last_move":_last_move_tick}
	# D23 T17: the streak's kill window and charge exist only while streak gear is worn or a charge is waiting.
	if int(_gear_stats.get("streak_projectiles",0)) > 0 or _streak_charge > 0:
		result.streak = {"kills":_streak_kills.duplicate(),"charge":_streak_charge}
	# D20: the booked falls, only while one is in the air.
	if not _meteors.is_empty(): result.meteors = _meteors.duplicate(true)
	return result
