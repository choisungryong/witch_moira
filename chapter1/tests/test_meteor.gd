extends SceneTree
## D20 check: the evolved ember (Meteor) books falls instead of shooting (combat_core.gd _book_meteors / _step_meteors, data: combat_tuning.json "meteor").
## The shipped tuning is read; copies with other meteor values are made in memory only. Parts:
##   A  the validator and the shipped block
##   B  a cast books one fall per projectile: no flying ember, event meteor_cast, land tick, place, lead, scatter
##   C  the landing: explosion event with the fall's id, everything inside the radius is hit, outside is not, the chain still goes on
##   D  what does not change: the plain ember, other spells, a document without the block
##   E  the context lives until the last fall has landed; the snapshot carries the booked falls only while some are in the air
##   F  determinism (a pilot run with the evolved ember twice)
## Marker: CHAPTER1_METEOR_RESULT. Writes nothing.
const Chapter = preload("res://chapter1/core/chapter_core.gd")
const Pilot = preload("res://chapter1/core/chapter_pilot.gd")
const TUNING := "res://chapter1/data/combat_tuning.json"
const EMBER := "chapter1.skill.ember"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("execute")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func shipped() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(TUNING))

func make_run(mutate: Callable = Callable(), primary: String = EMBER, evolve := true) -> RefCounted:
	var doc := shipped()
	if mutate.is_valid(): mutate.call(doc)
	var run = Chapter.new()
	if not run.set_tuning(doc):
		check(false, "document accepted: " + str(run.errors))
		return null
	if not run.start(11, primary):
		check(false, "run starts: " + str(run.errors))
		return null
	if evolve: run.growth._evolved.append(primary)
	return run

## A walker standing still at `where` (hp kept low so one hit kills when `weak`).
func place(run: RefCounted, where: Vector2, weak := false, toward := Vector2.ZERO) -> Dictionary:
	check(run._spawn("walker", where), "a body can be placed")
	var e: Dictionary = run.enemies[run._enemy_sequence]
	if weak:
		e.hp_raw = 1
		e.max_hp_raw = 1
	if toward != Vector2.ZERO: e.direction = toward
	return e

func cast_now(run: RefCounted) -> void:
	run.events.clear()
	run._next_cast[EMBER] = 0
	run._rebuild_grid()
	run._auto_casts()

func events_of(run: RefCounted, type: String) -> Array:
	return run.events.filter(func(e): return e.type == type)

func accepted(mutate: Callable) -> bool:
	var doc := shipped()
	mutate.call(doc)
	var run = Chapter.new()
	return run.set_tuning(doc)

# ------------------------------------------------------------------ A

func validator_checks() -> void:
	var m: Dictionary = shipped().meteor
	check(accepted(func(d): pass), "A the shipped document is accepted")
	check(m.fall_ticks == 24 and m.lead_bps == 5000, "A the shipped first values (fall 24 ticks, lead 0.5)")
	check(accepted(func(d): d.erase("meteor")), "A a document without the block is accepted (the ember flies as before)")
	for pair in [["fall_ticks", 5], ["fall_ticks", 121], ["lead_bps", -1], ["lead_bps", 10001], ["scatter_cm", 601], ["scatter_cm", -1], ["radius_bps", 2999], ["radius_bps", 30001], ["damage_bps", 2999], ["damage_bps", 30001]]:
		var key: String = pair[0]
		var value: int = pair[1]
		check(not accepted(func(d): d.meteor[key] = value), "A %s %d is refused" % [key, value])
	for pair in [["fall_ticks", 6], ["fall_ticks", 120], ["lead_bps", 0], ["lead_bps", 10000], ["scatter_cm", 0], ["scatter_cm", 600], ["radius_bps", 3000], ["damage_bps", 30000]]:
		var key: String = pair[0]
		var value: int = pair[1]
		check(accepted(func(d): d.meteor[key] = value), "A %s %d is accepted" % [key, value])
	check(not accepted(func(d): d.meteor.fall_ticks = 24.5), "A a fractional fall_ticks is refused")
	check(not accepted(func(d): d.meteor.x = 1), "A an unknown key is refused")
	check(not accepted(func(d): d.meteor.erase("lead_bps")), "A a missing key is refused")
	check(not accepted(func(d): d.meteor = []), "A a block that is not an object is refused")

# ------------------------------------------------------------------ B

func booking_checks() -> void:
	var run := make_run()
	var m: Dictionary = run.tuning.meteor
	var target := place(run, Vector2(5, 0), false, Vector2(-1, 0))
	var count := int(run.effective_skill(EMBER).effects.projectiles)
	check(run.effective_skill(EMBER).evolved and count >= 2, "B the evolved ember has several shots (%d)" % count)
	cast_now(run)
	var flying: Array = run.projectiles.filter(func(p): return p.skill_id == EMBER)
	check(flying.is_empty(), "B no ember projectile flies")
	check(run._meteors.size() == count, "B one fall is booked per shot (%d of %d)" % [run._meteors.size(), count])
	var booked := events_of(run, "meteor_cast")
	check(booked.size() == count and int(booked[0].land_tick) == run.tick + int(m.fall_ticks) and int(booked[0].radius_cm) > 0 and booked[0].has("id") and booked[0].has("position"), "B meteor_cast {id, position, land_tick, radius_cm} for each fall, land tick = now + fall_ticks")
	var expected: Vector2 = target.position + Vector2(-1, 0) * float(run.ENEMY_DEFS.walker.speed) * float(m.fall_ticks) / 60.0 * float(m.lead_bps) / 10000.0
	check(run._meteors[0].position.distance_to(expected) < 0.001, "B the first fall is on the aimed enemy's place, led by half its walk (%s vs %s)" % [str(run._meteors[0].position), str(expected)])
	var within := true
	var distinct := {}
	for item in run._meteors:
		distinct[str(item.position)] = true
		if item.position.distance_to(run._meteors[0].position) > float(m.scatter_cm) / 100.0 + 0.001: within = false
	check(within, "B the other falls stay within scatter_cm of the first")
	check(distinct.size() == count, "B the scattered falls are all in different places")
	check(events_of(run, "cast").size() == 1, "B the cast event is still sent once")
	var id_before: int = run._meteors[0].id
	var spot_before: Vector2 = run._meteors[0].position
	target.position += Vector2(3, 3)
	check(run._meteors[0].position == spot_before and run._meteors[0].id == id_before, "B the target moving afterwards does not move a booked fall")
	check(run._next_cast[EMBER] > run.tick, "B the cooldown starts at the cast")
	# lead 0 and lead 1; scatter 0.
	var flat := make_run(func(d):
		d.meteor.lead_bps = 0
		d.meteor.scatter_cm = 0)
	var t0 := place(flat, Vector2(5, 0), false, Vector2(-1, 0))
	cast_now(flat)
	var same := true
	for item in flat._meteors:
		if item.position != t0.position: same = false
	check(same and flat._meteors.size() > 1, "B lead 0 and scatter 0: every fall lands on the target's own place")
	var full := make_run(func(d):
		d.meteor.lead_bps = 10000
		d.meteor.scatter_cm = 0)
	var t1 := place(full, Vector2(5, 0), false, Vector2(-1, 0))
	cast_now(full)
	var walk: float = float(full.ENEMY_DEFS.walker.speed) * float(full.tuning.meteor.fall_ticks) / 60.0
	check(absf(full._meteors[0].position.x - (5.0 - walk)) < 0.001, "B lead 1 books the whole walk ahead (x %.3f)" % full._meteors[0].position.x)
	var still := make_run(func(d): d.meteor.lead_bps = 10000)
	var t2 := place(still, Vector2(5, 0), false, Vector2(-1, 0))
	t2.state = "windup"
	cast_now(still)
	check(still._meteors[0].position == t2.position, "B an enemy that is not walking is not led")
	var slow := make_run(func(d): d.meteor.lead_bps = 10000)
	var t3 := place(slow, Vector2(5, 0), false, Vector2(-1, 0))
	t3.frozen_until = 100000
	cast_now(slow)
	check(slow._meteors[0].position == t3.position, "B a frozen enemy is not led")
	# Falls to the edge stay inside the field.
	var edge := make_run()
	place(edge, Vector2(5, 0))
	edge.hero.position = Vector2(0, 0)
	cast_now(edge)
	for item in edge._meteors:
		check(item.position == edge._clamp_point(item.position), "B a fall is inside the field")
	# The fall of two casts get different ids.
	var ids := {}
	for item in run._meteors: ids[item.id] = true
	run._next_cast[EMBER] = 0
	run.events.clear()
	run._auto_casts()
	for item in run._meteors: ids[item.id] = true
	check(ids.size() == run._meteors.size(), "B every fall has its own id")

# ------------------------------------------------------------------ C

func landing_checks() -> void:
	var run := make_run(func(d):
		d.meteor.lead_bps = 0
		d.meteor.scatter_cm = 0)
	var radius_m: float = float(run.effective_skill(EMBER).effects.radius_cm) * float(run.tuning.meteor.radius_bps) / 10000.0 / 100.0
	var target := place(run, Vector2(5, 0), true)
	var inside := place(run, Vector2(5 + radius_m * 0.6, 0), true)
	var outside := place(run, Vector2(5 + radius_m * 2.0 + 4.0, 0), true)
	var tough := place(run, Vector2(5, radius_m * 0.5))
	tough.hp_raw = 100000 * 1024
	tough.max_hp_raw = tough.hp_raw
	cast_now(run)
	var land: int = run._meteors[0].land_tick
	run.tick = land - 1
	run.events.clear()
	run._step_meteors()
	check(not run._meteors.is_empty() and events_of(run, "explosion").is_empty() and target.hp_raw == 1, "C one tick before the land tick nothing falls")
	run.tick = land
	run._rebuild_grid()
	run._step_meteors()
	var blasts := events_of(run, "explosion").filter(func(e): return e.has("meteor"))
	check(not blasts.is_empty() and int(blasts[0].radius_cm) > 0 and blasts[0].skill_id == EMBER and blasts[0].evolved, "C the landing sends the explosion event with the fall's id")
	check(target.hp_raw <= 0 and inside.hp_raw <= 0, "C everything inside the radius is hit (target and a neighbour)")
	check(outside.hp_raw == 1, "C an enemy outside the radius is not hit")
	check(tough.hp_raw < 100000 * 1024, "C a tougher body inside the radius takes the damage too")
	check(run._meteors.is_empty(), "C every fall of the cast landed together")
	check(run.kills >= 2, "C the kills are counted by the normal path (%d)" % run.kills)
	# The chain: a killed body bursts again (death_burst) and takes a body outside the first radius with it.
	var chain := make_run(func(d):
		d.meteor.lead_bps = 0
		d.meteor.scatter_cm = 0)
	var rm: float = float(chain.effective_skill(EMBER).effects.radius_cm) / 100.0
	place(chain, Vector2(5, 0), true)
	var rim := place(chain, Vector2(5 + rm * 0.9, 0), true)
	var far := place(chain, Vector2(5 + rm * 0.9 + rm * 0.9, 0), true)
	cast_now(chain)
	chain.tick = int(chain._meteors[0].land_tick)
	chain.events.clear()
	chain._rebuild_grid()
	chain._step_meteors()
	var procs := events_of(chain, "explosion").filter(func(e): return e.get("proc", false))
	check(rim.hp_raw <= 0 and not procs.is_empty() and procs[0].position.distance_to(chain._meteors.front().position if not chain._meteors.is_empty() else procs[0].position) < 0.001 and far.hp_raw > 0, "C the death burst (one level, as before) goes off at the killed body (%d bursts) and does not reach past its radius" % procs.size())
	# The hit budget is the cast's: with a budget of 1 only one body is hit in all.
	var thin := make_run(func(d):
		d.meteor.lead_bps = 0
		d.meteor.scatter_cm = 0)
	var a := place(thin, Vector2(5, 0), true)
	var b := place(thin, Vector2(5.5, 0), true)
	cast_now(thin)
	for key in thin._contexts:
		thin._contexts[key].remaining_hits = 1
	thin.tick = int(thin._meteors[0].land_tick)
	thin._rebuild_grid()
	thin._step_meteors()
	check((a.hp_raw <= 0) != (b.hp_raw <= 0) or (a.hp_raw <= 0 and b.hp_raw > 0) or (b.hp_raw <= 0 and a.hp_raw > 0), "C the cast's hit budget caps the damage (one body of two with a budget of 1)")
	# A radius multiplier widens the landing.
	var wide := make_run(func(d):
		d.meteor.radius_bps = 20000
		d.meteor.lead_bps = 0
		d.meteor.scatter_cm = 0)
	place(wide, Vector2(5, 0), true)
	cast_now(wide)
	var booked := events_of(wide, "meteor_cast")
	var normal := make_run()
	place(normal, Vector2(5, 0), true)
	cast_now(normal)
	check(int(booked[0].radius_cm) == int(events_of(normal, "meteor_cast")[0].radius_cm) * 2, "C radius_bps 20000 doubles the radius of the fall")

# ------------------------------------------------------------------ D

func unchanged_checks() -> void:
	var plain := make_run(Callable(), EMBER, false)
	place(plain, Vector2(5, 0))
	cast_now(plain)
	check(plain._meteors.is_empty() and plain.projectiles.size() > 0 and events_of(plain, "meteor_cast").is_empty(), "D the plain fireball still flies")
	var gone := make_run(func(d): d.erase("meteor"))
	place(gone, Vector2(5, 0))
	cast_now(gone)
	check(gone._meteors.is_empty() and gone.projectiles.size() > 1, "D without the block the evolved ember flies as before")
	var frost := make_run(Callable(), "chapter1.skill.frost")
	place(frost, Vector2(5, 0))
	frost._next_cast["chapter1.skill.frost"] = 0
	frost._rebuild_grid()
	frost._auto_casts()
	check(frost._meteors.is_empty() and frost.projectiles.size() > 0, "D an evolved frost still flies")
	var arc := make_run(Callable(), "chapter1.skill.arc")
	place(arc, Vector2(5, 0))
	arc._next_cast["chapter1.skill.arc"] = 0
	arc._rebuild_grid()
	arc._auto_casts()
	check(arc._meteors.is_empty(), "D an evolved arc books no fall")
	# A secondary ember (another witch's primary) that evolved is not the primary; it follows the same rule of the skill.
	var snap_plain: Dictionary = plain.snapshot()
	check(not snap_plain.has("meteors"), "D a run with no fall in the air has no meteors key in its snapshot")

# ------------------------------------------------------------------ E

func lifetime_checks() -> void:
	var run := make_run()
	place(run, Vector2(5, 0))
	cast_now(run)
	var uid: int = run._meteors[0].cast_id
	run._next_cast[EMBER] = 1 << 30
	run.step(Vector2.ZERO)
	check(run._contexts.has(uid) and not run._meteors.is_empty(), "E the cast's context lives while a fall is in the air")
	var snap: Dictionary = run.snapshot()
	check(snap.has("meteors") and snap.meteors.size() == run._meteors.size() and snap.meteors[0].has("land_tick") and snap.meteors[0].has("position") and snap.meteors[0].has("id"), "E the snapshot lists the booked falls (id, position, land_tick)")
	run.hero.hp_raw = run.hero.max_hp_raw
	var guard := 0
	while not run._meteors.is_empty() and guard < 200:
		run.hero.hp_raw = run.hero.max_hp_raw
		run.step(Vector2.ZERO)
		guard += 1
	check(run._meteors.is_empty() and guard <= int(run.tuning.meteor.fall_ticks) + 1, "E the falls land by themselves within fall_ticks (%d steps)" % guard)
	run.step(Vector2.ZERO)
	check(not run.snapshot().has("meteors"), "E after the landing the snapshot has no meteors key")

# ------------------------------------------------------------------ F

func play(ticks: int) -> RefCounted:
	var run := make_run()
	var pilot = Pilot.new()
	pilot.run = run
	for i in ticks:
		if run.mode in ["victory", "defeat"]: break
		run.hero.hp_raw = run.hero.max_hp_raw
		run.step(pilot.decide())
	return run

func determinism_checks() -> void:
	var a := play(1800)
	var b := play(1800)
	check(JSON.stringify(a.snapshot()).sha256_text() == JSON.stringify(b.snapshot()).sha256_text() and a.kills == b.kills, "F a pilot run with the evolved ember, twice: the same snapshot (tick %d, kills %d)" % [a.tick, a.kills])
	check(a._meteor_sequence > 0 and a.kills > 0, "F the run really used falls (%d booked) and killed (%d)" % [a._meteor_sequence, a.kills])

func execute() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/_local/appdata/"):
		print("CHAPTER1_METEOR_RESULT ", JSON.stringify({"checks": 0, "failures": ["user data dir is not isolated: refusing to run"]}))
		quit(1)
		return
	validator_checks()
	booking_checks()
	landing_checks()
	unchanged_checks()
	lifetime_checks()
	determinism_checks()
	print("CHAPTER1_METEOR_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
