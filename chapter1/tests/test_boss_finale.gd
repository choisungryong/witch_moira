extends SceneTree
## D-boss-finale (BF1~BF9) check of the core's share, chapter1/data/combat_tuning.json `boss_finale` (parked off in the shipped file).
## Every document is switched on IN MEMORY (set_tuning); the shipped file stays off. Parts: validator (BF5 and the shape), off (the old fight),
## entrance, phase threshold (BF3), break (BF2: fixed length, out of play, escorts, chip, storm, landing), the descent against the finale
## (the 18% cap and the threshold hold together, a break is not shortened), the slam, determinism and the snapshot key.
## Needs no save, writes nothing. Marker: CHAPTER1_BOSS_FINALE_RESULT.
const Chapter = preload("res://chapter1/core/chapter_core.gd")
const TUNING := "res://chapter1/data/combat_tuning.json"
const DESCENT := "res://chapter1/data/descent.json"
const EMBER := "chapter1.skill.ember"
const UNIT := 256
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("execute")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

# ---------------------------------------------------------------- helpers

func shipped() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(TUNING))

## The shipped tuning with the finale switched `on`; far-off level thresholds (no card screen in the middle) and no final-level grace.
func doc(on: bool, mutate: Callable = Callable()) -> Dictionary:
	var d := shipped()
	d.boss_finale.enabled = on
	var far: Array = []
	for i in 12: far.append(i * 90000)
	d.xp_thresholds = far
	d.final_level_on_boss_spawn = false
	if mutate.is_valid(): mutate.call(d)
	return d

## A quiet stage at the final zone: no ordinary spawn, the hero casts nothing (only the blows of the test hurt), the boss just appeared.
func boss_run(on: bool, mutate: Callable = Callable(), descent_on: bool = false, seed_: int = 11, primary: String = EMBER) -> RefCounted:
	var r = Chapter.new()
	check(r.set_tuning(doc(on, mutate)), "stage: the tuning is accepted " + str(r.errors))
	if descent_on:
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DESCENT))
		d.enabled = true
		check(r.set_descent(d), "stage: the descent document is accepted " + str(r.errors))
	check(r.start(seed_, primary), "stage: the run starts " + str(r.errors))
	r.enemies.clear()
	r._alive = 0
	r._next_spawn = 1 << 30
	for id_ in r._skill_ids: r._next_cast[id_] = 1 << 30
	r.hero.max_hp_raw = 100000 * UNIT
	r.hero.hp_raw = r.hero.max_hp_raw
	r.zone = 2
	r.hero.position = Chapter.ZONES[2]
	r._zone_entered = true
	r.zone_kills = int(r.tuning.seal_kills[2])
	r._spawn_wave()
	return r

func ctx(r: RefCounted, amount: int) -> Dictionary:
	var effects: Dictionary = r.effective_skill(r._primary_id).effects.duplicate(true)
	effects.damage_raw = amount
	effects.death_burst = 0
	effects.shatter_count = 0
	effects.radius_cm = 0
	return {"uid": 900 + r.tick, "skill_id": r._primary_id, "effects": effects, "remaining_hits": 128, "hit_ids": [], "evolved": false}

func blow(r: RefCounted, id_: int, amount: int) -> void:
	r._damage_enemy(id_, ctx(r, amount), 0)

## n ticks (hero topped up each tick); the events of every tick, in order. Stops when the run leaves "playing".
func steps(r: RefCounted, n: int, move: Vector2 = Vector2.ZERO) -> Array:
	var out: Array = []
	for i in n:
		if r.mode != "playing": break
		r.hero.hp_raw = r.hero.max_hp_raw
		r.step(move)
		out.append_array(r.events.duplicate(true))
	return out

func of_type(events: Array, type: String) -> Array:
	return events.filter(func(e): return e.type == type)

func boss_of(r: RefCounted) -> Dictionary:
	return r.enemies[r._champion_id]

## Steps until `type` has been seen (or `limit` ticks passed); returns that event, {} when it did not come.
func until(r: RefCounted, type: String, limit: int = 3000, extra: Array = []) -> Dictionary:
	for i in limit:
		var seen := steps(r, 1)
		extra.append_array(seen)
		for e in seen:
			if e.type == type: return e
		if r.mode != "playing": break
	return {}

func floor_hp(boss: Dictionary, bps: int) -> int:
	return int(boss.max_hp_raw) * bps / 10000

func kill_ordinary(r: RefCounted) -> int:
	var n := 0
	for id_ in r.enemies.keys().duplicate():
		var e: Dictionary = r.enemies[id_]
		if e.hp_raw > 0 and id_ != r._champion_id:
			blow(r, int(id_), 100000000)
			n += 1
	return n

func ordinary_alive(r: RefCounted) -> int:
	var n := 0
	for id_ in r.enemies:
		if r.enemies[id_].hp_raw > 0 and id_ != r._champion_id: n += 1
	return n

# ---------------------------------------------------------------- parts

func validator_checks() -> void:
	var s := Chapter.new()
	check(s.start(5) and not bool(s.tuning.boss_finale.enabled), "shipped: the block is there and off")
	check(s.set_tuning(doc(true)), "validator: the shipped block, switched on, is accepted")
	var rejected := {
		"slam wind-up 53 ticks for a 70 hit": func(d): d.boss_finale.phases[1].slam.windup_ticks = 53,
		"landing wind-up 53 ticks for a 55 hit": func(d): d.boss_finale.breaks[0].land.windup_ticks = 53,
		"storm wind-up 53 ticks for a 40 hit": func(d): d.boss_finale.breaks[1].storm.windup_ticks = 53,
		"champion (the boss) wind-up 53 ticks for an 85 hit": func(d): d.champions[2].windup = 53,
		"a phase threshold that rises": func(d): d.boss_finale.phases[1].to_hp_bps = 7000,
		"a last phase that does not end at 0": func(d): d.boss_finale.phases[2].to_hp_bps = 100,
		"a break after the wrong phase": func(d): d.boss_finale.breaks[0].after = "p2",
		"one break too few": func(d): d.boss_finale.breaks.pop_back(),
		"an escort kind that does not exist": func(d): d.boss_finale.breaks[0].escort.mix = {"dragon": 100},
		"a missing key": func(d): d.boss_finale.erase("entrance_ticks"),
		"a break shorter than its landing wind-up": func(d): d.boss_finale.breaks[0].ticks = 60,
		"an even number of floor circles": func(d): d.boss_finale.phases[0].ward.centers = 2,
		"enabled that is not a bool": func(d): d.boss_finale.enabled = 1,
	}
	for label in rejected:
		var d := doc(true)
		rejected[label].call(d)
		var probe := Chapter.new()
		check(not probe.set_tuning(d), "validator: rejected: " + label)
	# A small hit needs no long wind-up (BF5 is about the big ones).
	var small := doc(true, func(d): d.boss_finale.breaks[1].storm.damage = 20; d.boss_finale.breaks[1].storm.windup_ticks = 10)
	check(Chapter.new().set_tuning(small), "validator: a 20 hit may have a 10 tick wind-up")
	# BF5 holds for the shipped numbers themselves.
	for entry in [["slam", shipped().boss_finale.phases[1].slam.damage, shipped().boss_finale.phases[1].slam.windup_ticks], ["land", shipped().boss_finale.breaks[0].land.damage, shipped().boss_finale.breaks[0].land.windup_ticks], ["storm", shipped().boss_finale.breaks[1].storm.damage, shipped().boss_finale.breaks[1].storm.windup_ticks]]:
		check(int(entry[1]) * 10000 < 2000 * 120 or int(entry[2]) >= 54, "BF5: the shipped %s has a wind-up of at least 0.9 s" % entry[0])

func off_checks() -> void:
	var r := boss_run(false)
	var boss := boss_of(r)
	check(int(boss.max_hp_raw) == 4500 * UNIT and r._shield_id == 0 and not r.snapshot().has("boss_finale"), "off: the old boss (4500 life), nobody out of play, no snapshot key")
	check(of_type(r.events, "boss_entrance").is_empty(), "off: no boss_entrance")
	r._rebuild_grid()
	check(r._near(r.hero.position, 30.0).has(r._champion_id), "off: the boss is aimed at")
	boss.hp_raw = int(boss.max_hp_raw) / 2 - 1
	var seen := steps(r, 2)
	var phase := of_type(seen, "boss_phase")
	check(phase.size() == 1 and int(phase[0].phase) == 2 and not phase[0].has("id"), "off: the old half-health phase 2, event without an id")
	check(not r.snapshot().has("boss_finale") and r._shield_id == 0, "off: still no key, still nobody out of play")
	var spawned := 0
	r._next_spawn = 0
	for i in 150:
		steps(r, 1)
	spawned = ordinary_alive(r)
	check(spawned > 0, "off: spawn.boss_phase still sends the old escorts (%d alive)" % spawned)

func entrance_checks() -> void:
	var r := boss_run(true)
	var boss := boss_of(r)
	var id_: int = r._champion_id
	check(int(boss.max_hp_raw) == 15000 * UNIT and int(boss.hp_raw) == int(boss.max_hp_raw), "entrance: the boss has the block's 15000 life")
	var started := of_type(r.events, "boss_entrance")
	check(started.size() == 1 and int(started[0].ticks) == 120, "entrance: boss_entrance {ticks 120}")
	r._rebuild_grid()
	check(r._shield_id == id_ and not r._near(r.hero.position, 40.0).has(id_), "entrance: out of play, no aim finds it")
	var before := Vector2(boss.position)
	var hp_before := int(boss.hp_raw)
	r.events.clear()
	blow(r, id_, 5000000)
	var blocked := of_type(r.events, "boss_hit_blocked")
	check(int(boss.hp_raw) == hp_before and blocked.size() == 1 and String(blocked[0].skill_id) == EMBER, "entrance: a blow is turned away (boss_hit_blocked, no damage)")
	r.events.clear()
	blow(r, id_, 5000000)
	check(of_type(r.events, "boss_hit_blocked").is_empty(), "entrance: the blocked event is not sent again at once")
	var seen := steps(r, 118)
	check(boss.position == before and boss.state == "move" and r._shield_id == id_, "entrance: for its ticks the boss does not move or attack (tick %d)" % r.tick)
	check(of_type(seen, "boss_phase").is_empty(), "entrance: no phase before the ticks are over")
	seen = steps(r, 2)
	var phase := of_type(seen, "boss_phase")
	check(phase.size() == 1 and int(phase[0].phase) == 1 and String(phase[0].id) == "p1" and int(phase[0].tick) == 120, "entrance: boss_phase {1, p1} on tick 120")
	check(r._shield_id == 0 and r._near(r.hero.position, 40.0).has(id_), "entrance: then the boss is in play (the aim finds it)")
	check(int(r.snapshot().boss_finale.phase_index) == 0 and String(r.snapshot().boss_finale.state) == "phase", "entrance: the snapshot key reads phase 0")

func threshold_and_break_checks() -> void:
	var r := boss_run(true)
	var boss := boss_of(r)
	var id_: int = r._champion_id
	steps(r, 121)
	var line: int = floor_hp(boss, 6500)
	blow(r, id_, 100000000)
	check(int(boss.hp_raw) == line, "BF3: a huge blow stops at 65%% (%d of %d)" % [int(boss.hp_raw), line])
	r.events.clear()
	blow(r, id_, 100000000)
	check(int(boss.hp_raw) == line, "BF3: a second blow in the same tick takes nothing more")
	var seen: Array = []
	var start := until(r, "boss_break_started", 5, seen)
	check(not start.is_empty() and int(start.index) == 0 and int(start.ticks) == 600, "break 1: boss_break_started {0, 600}")
	var started_tick: int = int(start.tick)
	check(r._shield_id == id_ and boss.position == start.to and boss.state == "move" and boss.telegraph.is_empty(), "break 1: out of play, at the place it leapt to")
	var hero_distance: float = boss.position.distance_to(r.hero.position)
	check(hero_distance >= 6.5 and hero_distance <= 12.5, "break 1: it leapt 9 to 12 m away (clamped at a wall): %.1f m" % hero_distance)
	check(int(r.snapshot().boss_finale.break_until) == started_tick + 600 and int(r.snapshot().boss_finale.break_index) == 0, "break 1: the snapshot key names the end tick")
	var spawned_kinds := {}
	for e in of_type(seen, "spawn"): spawned_kinds[String(e.kind)] = true
	var spawn_count := of_type(seen, "spawn").size()
	check(spawn_count == 16 and spawned_kinds.keys().all(func(k): return k in ["walker", "charger"]), "break 1: the first 16 escorts, walkers and chargers only (%d, %s)" % [spawn_count, str(spawned_kinds.keys())])
	r._rebuild_grid()
	check(r._near(boss.position, 5.0).has(id_) == false, "break 1: no aim finds the boss (not even standing on it)")
	# a blow, a chain and an area each find nobody to hurt
	var hp_in_break := int(boss.hp_raw)
	r.events.clear()
	blow(r, id_, 100000000)
	# (one raw point to everything round it: nobody dies here, so no escort is chipped)
	r._area_hit(boss.position, 5.0, ctx(r, 1), -1, 0)
	check(int(boss.hp_raw) == hp_in_break, "break 1: neither a blow nor an area hit costs the boss life")
	# a friendly shot that meets the body is stopped and says so (the event is spaced, so let the last one age first)
	steps(r, 31)
	r.events.clear()
	r.projectiles.append({"uid": 77, "position": boss.position - Vector2(1.0, 0), "previous": boss.position - Vector2(1.0, 0), "direction": Vector2.RIGHT, "speed": 14.0, "radius": .16, "skill_id": EMBER, "hostile": false, "damage_raw": 1, "expires": r.tick + 100, "cast_id": 4242, "pierce_left": 3, "hit_ids": []})
	r._contexts[4242] = ctx(r, 1)
	var step_events := steps(r, 6)
	check(int(boss.hp_raw) == hp_in_break and of_type(step_events, "boss_hit_blocked").size() >= 1, "break 1: a shot that meets the body is stopped (boss_hit_blocked)")
	# the landing is telegraphed for its wind-up, the break ends on its tick
	var land := until(r, "boss_telegraph", 700, seen)
	check(String(land.get("attack_id", "")) == "land" and int(land.tick) == started_tick + 600 - 72 and int(land.windup_ticks) == 72 and is_equal_approx(float(land.radius), 3.0) and land.position == boss.position, "break 1: boss_telegraph land, 72 ticks before the end, 3 m, on the boss")
	var ended := until(r, "boss_break_ended", 700, seen)
	check(not ended.is_empty() and int(ended.tick) - started_tick == 600 and int(ended.index) == 0, "break 1: boss_break_ended exactly 600 ticks after it began (%d)" % (int(ended.get("tick", 0)) - started_tick))
	check(of_type(seen, "boss_telegraph").filter(func(e): return String(e.attack_id) == "storm").is_empty(), "break 1: no storm in the first break")
	check(r._shield_id == 0 and String(r.snapshot().boss_finale.state) == "phase" and int(r.snapshot().boss_finale.phase_index) == 1, "break 1: the boss is back in play, phase 2")
	check(int(boss.hp_raw) == hp_in_break, "break 1: its life is where the break found it (no kill, no chip)")
	var phase := of_type(seen, "boss_phase")
	check(phase.size() == 1 and int(phase[0].phase) == 2 and String(phase[0].id) == "p2", "break 1: boss_phase {2, p2} follows the break")
	check(int(boss.definition.recover) == 65, "phase 2: the boss recovers in 65 ticks")

func chip_checks() -> void:
	# Kills inside a break cut the boss's life (25 bps each, 500 bps at most), and no number of kills shortens the break.
	var r := boss_run(true)
	var boss := boss_of(r)
	var id_: int = r._champion_id
	steps(r, 121)
	blow(r, id_, 100000000)
	var seen: Array = []
	var start := until(r, "boss_break_started", 5, seen)
	var started_tick: int = int(start.tick)
	var base_hp := int(boss.hp_raw)
	var one := 0
	for e in r.enemies.values():
		if e.hp_raw > 0 and e.id != id_ and one < 10:
			blow(r, int(e.id), 100000000)
			one += 1
	var cut: int = int(boss.max_hp_raw) * 25 / 10000
	check(int(boss.hp_raw) == base_hp - 10 * cut, "chip: ten kills take 10 x 25 bps off the boss (%d)" % (base_hp - int(boss.hp_raw)))
	var chips := of_type(r.events, "boss_chip")
	check(chips.size() == 10 and int(chips[9].total_bps) == 250 and int(chips[0].bps) == 25, "chip: boss_chip {bps 25, total_bps} per kill")
	# the rest of the field, every tick, for the whole break
	for i in 700:
		kill_ordinary(r)
		var s := steps(r, 1)
		seen.append_array(s)
		if not of_type(s, "boss_break_ended").is_empty(): break
	var ended := of_type(seen, "boss_break_ended")
	check(ended.size() == 1 and int(ended[0].tick) - started_tick == 600, "BF2: with every escort killed the break still lasts 600 ticks (%d)" % (int(ended[0].tick) - started_tick if ended.size() == 1 else -1))
	check(int(boss.hp_raw) == base_hp - int(boss.max_hp_raw) * 500 / 10000 and int(r.snapshot().boss_finale.chip_bps) == 500, "chip: capped at 500 bps for a break (%d bps off)" % ((base_hp - int(boss.hp_raw)) * 10000 / int(boss.max_hp_raw)))
	check(int(boss.hp_raw) > floor_hp(boss, 3000), "chip: never reaches the next threshold")

func second_break_checks() -> void:
	var r := boss_run(true)
	var boss := boss_of(r)
	var id_: int = r._champion_id
	steps(r, 121)
	blow(r, id_, 100000000)
	until(r, "boss_break_ended", 800)
	check(int(boss.hp_raw) == floor_hp(boss, 6500), "phase 2: starts at 65% of the life")
	# phase 2's adds: 2 a second up to 10 alive
	kill_ordinary(r)
	steps(r, 300)
	var alive := ordinary_alive(r)
	check(alive > 0 and alive + 1 <= 10, "phase 2: adds come, never past alive_cap 10 (%d alive)" % alive)
	blow(r, id_, 100000000)
	check(int(boss.hp_raw) == floor_hp(boss, 3000), "BF3: phase 2 stops at 30%")
	var seen: Array = []
	var start := until(r, "boss_break_started", 5, seen)
	check(int(start.index) == 1 and int(start.ticks) == 540, "break 2: boss_break_started {1, 540}")
	var started_tick: int = int(start.tick)
	var potions_before: int = r.potion_pickups.size()
	check(of_type(seen, "boss_potion").size() + of_type(r.events, "boss_potion").size() >= 1 or r.potion_pickups.size() > 0, "break 2: a potion falls where the boss stands")
	var ended := until(r, "boss_break_ended", 800, seen)
	var storm := of_type(seen, "boss_telegraph").filter(func(e): return String(e.attack_id) == "storm")
	check(not ended.is_empty() and int(ended.tick) - started_tick == 540, "break 2: 540 ticks (%d)" % (int(ended.get("tick", 0)) - started_tick))
	check(storm.size() == 25, "break 2: five storms of five circles, none that would burst after the break (%d)" % storm.size())
	var ring_ok := true
	for e in storm:
		ring_ok = ring_ok and is_equal_approx(float(e.radius), 1.8) and int(e.windup_ticks) == 60
	check(ring_ok, "break 2: each storm circle is 1.8 m with a 60 tick wind-up")
	var first_storm: int = int(storm[0].tick) if storm.size() > 0 else -1
	check(first_storm == started_tick + 90, "break 2: the first storm comes 90 ticks in (%d)" % (first_storm - started_tick))
	check(of_type(seen, "chapter_burst").filter(func(e): return String(e.get("kind", "")) == "storm").size() >= 20, "break 2: the storms burst (chapter_burst kind storm)")
	check(r.potion_pickups.size() >= 1 or potions_before >= 1, "break 2: the potion lies on the floor")
	# phase 3: no adds, nobody out of play
	kill_ordinary(r)
	var pace := steps(r, 300)
	check(ordinary_alive(r) == 0 and of_type(pace, "spawn").is_empty(), "phase 3: no adds at all (BF6)")
	check(int(r.snapshot().boss_finale.phase_index) == 2 and r._shield_id == 0, "phase 3: the snapshot key reads phase 2")

func slam_scene(dodge: bool) -> Dictionary:
	var r := boss_run(true)
	var boss := boss_of(r)
	var id_: int = r._champion_id
	steps(r, 121)
	blow(r, id_, 100000000)
	until(r, "boss_break_ended", 800)
	kill_ordinary(r)
	var seen: Array = []
	var telegraph := {}
	for i in 3000:
		kill_ordinary(r)
		var s := steps(r, 1)
		seen.append_array(s)
		for e in of_type(s, "boss_telegraph"):
			if String(e.attack_id) == "slam": telegraph = e
		if not telegraph.is_empty(): break
	if telegraph.is_empty(): return {"telegraph": {}, "hit": false}
	var direction: Vector2 = telegraph.direction
	var side: Vector2 = direction.orthogonal() * 1.0
	var hit := false
	for i in 80:
		kill_ordinary(r)
		var s := steps(r, 1, side if dodge else Vector2.ZERO)
		for e in of_type(s, "hero_hit"):
			if String(e.get("attack_id", "")) == "slam": hit = true
	return {"telegraph": telegraph, "hit": hit, "boss": boss, "hero_hits": seen}

func slam_checks() -> void:
	var stand := slam_scene(false)
	var t: Dictionary = stand.telegraph
	check(not t.is_empty(), "slam: phase 2's third attack is a slam (boss_telegraph)")
	if t.is_empty(): return
	check(String(t.shape) == "line" and int(t.windup_ticks) == 72 and is_equal_approx(float(t.length), 10.0) and is_equal_approx(float(t.width), 2.0), "slam: a line of 10 x 2 m with a 72 tick wind-up (1.2 s)")
	check(bool(stand.hit), "slam: standing in the line takes the hit")
	var dodge := slam_scene(true)
	check(not dodge.telegraph.is_empty() and not bool(dodge.hit), "slam: stepping aside during the wind-up takes no hit")

func descent_checks() -> void:
	# The descent and the threshold: the strong share (boss 12% + marks, 18% at most) is paid, but never past the phase line.
	var r := boss_run(true, Callable(), true)
	var boss := boss_of(r)
	var id_: int = r._champion_id
	steps(r, 121)
	boss.position = r.hero.position + Vector2(3, 0)
	r._descent_add(int(r.descent.cost[0]))
	var full := int(boss.max_hp_raw)
	check(r.request_descent() and r.release_descent(), "descent: the call and the release are accepted in phase 1")
	steps(r, int(r.descent.ultimates[r._d_element].sweep_ticks) + 5)
	var lost := full - int(boss.hp_raw)
	check(lost > 0 and lost <= full * 1800 / 10000 and int(boss.hp_raw) >= floor_hp(boss, 6500), "descent: phase 1: the boss loses at most 18%% of its life (%.1f%%)" % (100.0 * lost / full))
	# right above the line: the same descent is cut at the line (BF3 and the 18% cap stand together)
	var r2 := boss_run(true, Callable(), true)
	var boss2 := boss_of(r2)
	steps(r2, 121)
	boss2.position = r2.hero.position + Vector2(3, 0)
	boss2.hp_raw = floor_hp(boss2, 6500) + int(boss2.max_hp_raw) / 100
	r2._descent_add(int(r2.descent.cost[0]))
	r2.request_descent()
	r2.release_descent()
	var seen: Array = []
	var began := until(r2, "boss_break_started", int(r2.descent.ultimates[r2._d_element].sweep_ticks) + 5, seen)
	check(not began.is_empty() and int(boss2.hp_raw) == floor_hp(boss2, 6500), "descent: one percent above the 65%% line the sweep stops the boss exactly on it when the break begins (%d of %d)" % [int(boss2.hp_raw), floor_hp(boss2, 6500)])
	# inside a break the descent does not touch the boss and does not shorten the break
	var in_break := boss_run(true, Callable(), true)
	var boss3 := boss_of(in_break)
	steps(in_break, 121)
	blow(in_break, in_break._champion_id, 100000000)
	var events: Array = []
	var start := until(in_break, "boss_break_started", 5, events)
	boss3.position = in_break.hero.position + Vector2(3, 0)
	var hp_in := int(boss3.hp_raw)
	in_break._descent_add(int(in_break.descent.cost[0]))
	check(in_break.request_descent() and in_break.release_descent(), "descent: a call inside the break is accepted")
	var after := steps(in_break, 700)
	events.append_array(after)
	var ended := of_type(events, "boss_break_ended")
	check(int(boss3.hp_raw) <= hp_in and int(boss3.hp_raw) >= hp_in - int(boss3.max_hp_raw) * 500 / 10000, "descent: in a break the boss takes no share (only the chip of the escorts it swept: %d bps)" % ((hp_in - int(boss3.hp_raw)) * 10000 / int(boss3.max_hp_raw)))
	check(ended.size() == 1 and int(ended[0].tick) - int(start.tick) == 600, "BF2: a descent does not shorten the break (%d ticks)" % (int(ended[0].tick) - int(start.tick) if ended.size() == 1 else -1))

func whole_fight(seed_: int, primary: String) -> Dictionary:
	var r := boss_run(true, Callable(), false, seed_, primary)
	var id_: int = r._champion_id
	var log: Array = []
	var last_phase := 0
	for i in 6000:
		if r.mode != "playing": break
		kill_ordinary(r)
		if r.mode != "playing": break
		if r.enemies.has(id_) and r.enemies[id_].hp_raw > 0 and r._shield_id == 0:
			blow(r, id_, 100000000)
		if r.mode != "playing": break
		r.hero.hp_raw = r.hero.max_hp_raw
		r.step(Vector2.ZERO)
		for e in r.events:
			if e.type in ["boss_phase", "boss_break_started", "boss_break_ended"]: log.append([String(e.type), int(e.tick)])
	return {"mode": r.mode, "tick": r.tick, "log": log, "hash": JSON.stringify(r.snapshot()).sha256_text(), "state": String(r.snapshot().boss_finale.state)}

func fight_checks() -> void:
	var a := whole_fight(11, EMBER)
	check(a.mode == "victory" and a.state == "done", "fight: a pilotless run with unlimited damage still wins (mode %s, state %s)" % [a.mode, a.state])
	var order: Array = []
	for entry in a.log: order.append(entry[0])
	check(order == ["boss_phase", "boss_break_started", "boss_break_ended", "boss_phase", "boss_break_started", "boss_break_ended", "boss_phase"], "fight: entrance, phase 1, break, phase 2, break, phase 3 in that order: " + str(order))
	var fixed := 120 + 600 + 540
	check(int(a.tick) >= fixed, "BF2: with damage no gear could reach the fight takes at least the fixed %d ticks (%d)" % [fixed, int(a.tick)])
	var b := whole_fight(11, EMBER)
	check(a.hash == b.hash and a.log == b.log, "determinism: the same seed and the same inputs give the same snapshot hash")
	var c := whole_fight(12, "chapter1.skill.arc")
	check(c.mode == "victory" and int(c.tick) >= fixed, "fight: another seed and another witch (arc) end the same way (tick %d)" % int(c.tick))

func execute() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/_local/appdata/"):
		print("CHAPTER1_BOSS_FINALE_RESULT ", JSON.stringify({"checks": 0, "failures": ["user data dir is not isolated: refusing to run"]}))
		quit(1)
		return
	print("BOSS_FINALE_PART validator_checks")
	validator_checks()
	print("BOSS_FINALE_PART off_checks")
	off_checks()
	print("BOSS_FINALE_PART entrance_checks")
	entrance_checks()
	print("BOSS_FINALE_PART threshold_and_break_checks")
	threshold_and_break_checks()
	print("BOSS_FINALE_PART chip_checks")
	chip_checks()
	print("BOSS_FINALE_PART second_break_checks")
	second_break_checks()
	print("BOSS_FINALE_PART slam_checks")
	slam_checks()
	print("BOSS_FINALE_PART descent_checks")
	descent_checks()
	print("BOSS_FINALE_PART fight_checks")
	fight_checks()
	print("CHAPTER1_BOSS_FINALE_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
