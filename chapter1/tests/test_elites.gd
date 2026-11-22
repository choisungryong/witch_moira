extends SceneTree
## W4-a / W5-a check: the strong elite body (D13 5.1, D2 2) and the guarded shrine and chest (D13 5.2). The shipped
## combat_tuning.json is read and `elites` / `extras` are switched on IN MEMORY only; no data file is edited. Parts:
##   A  off: nothing exists (no key in the snapshot, no metrics, no enemy field), a document with the blocks off equals one without them
##   B  the validator (every range, one bad value per case), start() refusing extras without elites / a bad chest class / a site on a ritual
##   C  the body: numbers, role, events, kills count toward the seal but never open it, drops from the elite table on the floor
##   D  elites that walk in: the n-th at its seal share, held by the alive cap / the guardian / the opening, skipped at the gate
##   E  the guard: guard -> alert -> fight -> return -> guard, the leash (also for a dashing kind), no relocation, hit from afar
##   F  unlocking: chest (treasure class, potions, drop events), shrine (open for stay_ticks, taken by touch, lapses), tiers
##   G  buffs: stats on top of gear, the limit cut, same kind refills, different kinds side by side, preview_equip without them, luck
##   H  leaving the zone (nothing dies, nothing drops), a site never placed when its zone was left
##   I  random streams: _spawn_rng and _loot_rng are untouched by placing and walking in; same ordinary spawns with the blocks on or off
##   J  together with the rhythm opening, the descent (strong enemy rule) and the grace grades (luck of the shrine)
##   K  determinism (same seed and inputs: same snapshot hash)
## Marker: CHAPTER1_ELITES_TEST_RESULT. Writes nothing.
const Chapter = preload("res://chapter1/core/chapter_core.gd")
const Pilot = preload("res://chapter1/core/chapter_pilot.gd")
const Tuning = preload("res://chapter1/core/combat_tuning.gd")
const Loot = preload("res://chapter1/core/loot.gd")
const TUNING := "res://chapter1/data/combat_tuning.json"
const DESCENT := "res://chapter1/data/descent.json"
const UNIT := 256
const EMBER := "chapter1.skill.ember"
var checks := 0
var failures: Array[String] = []
var _tuning_text := ""

func _initialize() -> void:
	call_deferred("execute")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func shipped() -> Dictionary:
	if _tuning_text.is_empty(): _tuning_text = FileAccess.get_file_as_string(TUNING)
	return JSON.parse_string(_tuning_text)

func issues(doc: Dictionary) -> Array[String]:
	return Tuning.validate(doc, Chapter.SKILL_IDS, Chapter.MAX_ALIVE, Chapter.MAX_PROJECTILES - Chapter.MAX_HOSTILE_PROJECTILES)

## The shipped document with the elites and the extras on; `mutate` gets it last. The experience thresholds are far away so that no
## card screen opens in the middle of a scene.
func doc_on(mutate: Callable = Callable(), far_xp: bool = true) -> Dictionary:
	var doc := shipped()
	doc.elites.enabled = true
	doc.extras.enabled = true
	if far_xp:
		var far: Array = []
		for i in 12: far.append(i * 90000)
		doc.xp_thresholds = far
	if mutate.is_valid(): mutate.call(doc)
	return doc

## Three sites for the scenes: two shrines in the first zone (at once, then at one kill) and a chest in the second.
func sites_doc(d: Dictionary) -> void:
	d.extras.guarded.sites = [
		{"id": "t.a", "zone": 0, "at_bps": 0, "kind": "shrine", "pool": "p_power", "points": [[12, 10]]},
		{"id": "t.b", "zone": 0, "at_bps": 1, "kind": "shrine", "pool": "p_swift", "points": [[-12, 10]]},
		{"id": "t.c", "zone": 1, "at_bps": 0, "kind": "chest", "pool": "", "points": [[10, 12]]}]
	d.extras.shrines.pool["p_power"] = ["power"]
	d.extras.shrines.pool["p_swift"] = ["swift"]
	d.extras.shrines.pool["p_luck"] = ["luck"]
	d.extras.shrines.pool["p_harvest"] = ["harvest"]
	d.extras.shrines.pool["p_ward"] = ["ward"]

func make_run(doc: Dictionary, seed_: int = 11, primary: String = EMBER, quiet: bool = true) -> RefCounted:
	var run = Chapter.new()
	if not run.set_tuning(doc):
		check(false, "document accepted: " + str(run.errors))
		return null
	if not run.start(seed_, primary):
		check(false, "run starts: " + str(run.errors))
		return null
	run.first_boss_kill = true
	if quiet:
		# Nothing spawns and nothing is cast: only what a scene puts in the world is there.
		run.enemies.clear()
		run._alive = 0
		run._next_spawn = 1 << 30
		for id_ in run._skill_ids: run._next_cast[id_] = 1 << 30
	return run

func put(run: RefCounted, position: Vector2, kind: String = "walker") -> int:
	check(run._spawn(kind, position), "put: spawned")
	var id_: int = run._enemy_sequence
	run.enemies[id_].definition.speed = 0.0
	return id_

## n ticks with the hero topped up; the events of every tick in order.
func tick_run(run: RefCounted, n: int) -> Array:
	var out: Array = []
	for i in n:
		if run.mode != "playing": break
		run.hero.hp_raw = run.hero.max_hp_raw
		run.step(Vector2.ZERO)
		out.append_array(run.events.duplicate(true))
	return out

func of_type(events: Array, type: String) -> Array:
	return events.filter(func(e): return e.type == type)

## One blow through the normal damage path (a made-up skill id: no children, no marks, no status).
func hit(run: RefCounted, id_: int, amount: int) -> void:
	run._cast_sequence += 1
	var effects := {"damage_raw": amount, "proc_depth": 0, "death_burst": 0, "shatter_count": 0, "radius_cm": 0, "slow_bps": 0, "freeze_stacks": 0, "pierce": 0,
		"hit_budget": 512, "cooldown_ticks": 0, "projectiles": 0, "chain_targets": 0, "branches": 0}
	var context := {"uid": run._cast_sequence, "skill_id": "test.blow", "effects": effects, "remaining_hits": 512, "hit_ids": [], "evolved": false}
	run._damage_enemy(id_, context, 0)

func kill(run: RefCounted, id_: int) -> Array:
	var before: int = run.events.size()
	run.events.clear()
	hit(run, id_, int(run.enemies[id_].hp_raw) + 1)
	return run.events.duplicate(true)

func digest(run: RefCounted) -> String:
	return JSON.stringify(run.snapshot()).sha256_text()

func guard_of(run: RefCounted, uid: int) -> Dictionary:
	for site in run.extras_view().sites:
		if int(site.uid) == uid: return site
	return {}

func body_of(run: RefCounted, uid: int) -> Dictionary:
	var site := guard_of(run, uid)
	if site.is_empty() or not run.enemies.has(int(site.elite_id)): return {}
	return run.enemies[int(site.elite_id)]

# ------------------------------------------------------------------ A

func off_checks() -> void:
	var d := shipped()
	check(d.elites.enabled == false and d.extras.enabled == false, "A shipped elites and extras are OFF")
	check(String(d.elites.balance_status).contains("가설") and String(d.extras.balance_status).contains("가설"), "A both blocks say their numbers are hypotheses")
	check(issues(d).is_empty(), "A the shipped document is valid: " + str(issues(d)))
	var plain := shipped()
	plain.erase("elites")
	plain.erase("extras")
	check(issues(plain).is_empty(), "A a document without the blocks is valid")
	var run := make_run(shipped(), 11, EMBER, false)
	var snap: Dictionary = run.snapshot()
	check(not snap.chapter.has("elites") and not snap.chapter.has("extras"), "A off: no elites / extras key in snapshot().chapter")
	check(not snap.metrics.has("elites") and not snap.metrics.has("sites"), "A off: no elites / sites tallies in the metrics")
	check(run.extras_view() == {"enabled": false}, "A off: extras_view() is {enabled:false}")
	var graded := 0
	for id_ in run.enemies:
		if run.enemies[id_].has("grade") or run.enemies[id_].has("guard_uid"): graded += 1
	check(graded == 0, "A off: no enemy carries grade / guard_uid")
	# Off, with the blocks present, equals no blocks at all (the golden relies on this).
	var a := play(shipped(), 11, 1500)
	var b := play(plain, 11, 1500)
	check(a.hash == b.hash, "A off: 1500 pilot ticks with the blocks off equal the same run without them")
	# Switching the elites on but not the extras gives the body only: no site, no guard.
	var elites_only := make_run(doc_on(func(x): x.extras.enabled = false), 11, EMBER, false)
	check(elites_only.snapshot().chapter.has("elites") and not elites_only.snapshot().chapter.has("extras"), "A elites on alone: only the elites key")
	# Extras without elites is refused at start().
	var lone := Chapter.new()
	var lone_doc := doc_on(func(x): x.elites.enabled = false)
	check(lone.set_tuning(lone_doc) and not lone.start(11, EMBER), "A extras without elites: start() refuses")

## Pilot ticks (the pilot takes the card screens); the hash at the end.
func play(doc: Dictionary, seed_: int, ticks: int, primary: String = EMBER) -> Dictionary:
	var run := make_run(doc, seed_, primary, false)
	var pilot = Pilot.new()
	pilot.run = run
	var events: Array = []
	for i in ticks:
		var move: Vector2 = pilot.decide()
		if run.mode == "playing":
			run.hero.hp_raw = run.hero.max_hp_raw
			run.step(move)
			events.append_array(run.events.duplicate(true))
		elif run.mode != "choice": break
	return {"hash": digest(run), "run": run, "events": events}

# ------------------------------------------------------------------ B

func validator_checks() -> void:
	check(issues(doc_on()).is_empty(), "B the shipped blocks switched on are valid: " + str(issues(doc_on())))
	var bad := {
		"elites extra key": func(d): d.elites.surprise = 1,
		"elites missing hp": func(d): d.elites.erase("hp"),
		"elites enabled not bool": func(d): d.elites.enabled = 1,
		"per_zone 5": func(d): d.elites.per_zone = [5, 0, 0],
		"per_zone size": func(d): d.elites.per_zone = [2, 2],
		"per_zone above the at_seal_bps entries": func(d): d.elites.at_seal_bps = [3000],
		"at_seal_bps not rising": func(d): d.elites.at_seal_bps = [6500, 3000],
		"at_seal_bps 10000": func(d): d.elites.at_seal_bps = [3000, 10000],
		"hp 0": func(d): d.elites.hp = [0, 310, 520],
		"hp 5001": func(d): d.elites.hp = [190, 310, 5001],
		"damage_bps 4999": func(d): d.elites.damage_bps = 4999,
		"speed_bps 30001": func(d): d.elites.speed_bps = 30001,
		"radius_bps 4999": func(d): d.elites.radius_bps = 4999,
		"kinds size": func(d): d.elites.kinds = [{"walker": 100}],
		"kinds unknown kind": func(d): d.elites.kinds[0] = {"boss": 1},
		"kinds all zero": func(d): d.elites.kinds[1] = {"walker": 0},
		"xp -1": func(d): d.elites.xp = [-1, 10, 12],
		"affixes_per_zone 1": func(d): d.elites.affixes_per_zone = [1, 0, 0],
		"affixes not empty": func(d): d.elites.affixes = {"swift": {}},
		"extras extra key": func(d): d.extras.surprise = 1,
		"extras missing chests": func(d): d.extras.erase("chests"),
		"extras enabled not bool": func(d): d.extras.enabled = "yes",
		"later key not an object": func(d): d.extras["grade"] = 3,
		"site order": func(d): d.extras.guarded.sites.reverse(),
		"site zone 2": func(d): d.extras.guarded.sites[1].zone = 2,
		"site kind": func(d): d.extras.guarded.sites[0].kind = "door",
		"site pool unknown": func(d): d.extras.guarded.sites[0].pool = "nope",
		"chest with a pool": func(d): d.extras.guarded.sites[1].pool = "seung1",
		"site duplicate id": func(d): d.extras.guarded.sites[1].id = "guard.z0",
		"site point out of range": func(d): d.extras.guarded.sites[0].points = [[18, 0]],
		"site points empty": func(d): d.extras.guarded.sites[0].points = [],
		"site extra key": func(d): d.extras.guarded.sites[0]["x"] = 1,
		"sites empty": func(d): d.extras.guarded.sites = [],
		"distance_m reversed": func(d): d.extras.guarded.distance_m = [16.0, 12.0],
		"leash_m 1": func(d): d.extras.guarded.leash_m = 1.0,
		"aggro above leash": func(d): d.extras.guarded.aggro_m = 7.0,
		"alert_ticks 121": func(d): d.extras.guarded.alert_ticks = 121,
		"return_far_m 5": func(d): d.extras.guarded.return_far_m = 5.0,
		"return_after_ticks 59": func(d): d.extras.guarded.return_after_ticks = 59,
		"potions 4": func(d): d.extras.guarded.potions = 4,
		"tiers empty": func(d): d.extras.guarded.tiers = [],
		"tier hp 4999": func(d): d.extras.guarded.tiers[0].elite_hp_bps = 4999,
		"tier duplicate id": func(d): d.extras.guarded.tiers = [d.extras.guarded.tiers[0], d.extras.guarded.tiers[0].duplicate()],
		"touch_radius_m 5": func(d): d.extras.shrines.touch_radius_m = 5.0,
		"stay_ticks 59": func(d): d.extras.shrines.stay_ticks = 59,
		"guarded_ticks_bps 4999": func(d): d.extras.shrines.guarded_ticks_bps = 4999,
		"shrine kind without an effect": func(d): d.extras.shrines.kinds.luck = {"ticks": 1800},
		"shrine kind max_hp_raw": func(d): d.extras.shrines.kinds.power.stats = {"max_hp_raw": 10},
		"shrine kind drop_bps 9999": func(d): d.extras.shrines.kinds.luck.drop_bps = 9999,
		"shrine kind unknown quality": func(d): d.extras.shrines.kinds.luck.quality_bps = {"common": 20000},
		"shrine kind unknown key": func(d): d.extras.shrines.kinds.power["x"] = 1,
		"pool names an unknown kind": func(d): d.extras.shrines.pool.seung1 = ["nope"],
		"pool empty": func(d): d.extras.shrines.pool.seung1 = [],
		"chests class empty": func(d): d.extras.chests["class"] = ""}
	for name in bad:
		var d := doc_on()
		bad[name].call(d)
		check(not issues(d).is_empty(), "B rejected: " + String(name))
	var later := doc_on()
	later.extras["unguarded"] = {}
	later.extras["rituals"] = {}
	later.extras["grade"] = {}
	check(issues(later).is_empty(), "B the W5-b/c keys may be present as objects")
	# start() looks across the files: a chest class the loot tables do not have, a site on a ritual.
	var unknown := Chapter.new()
	check(unknown.set_tuning(doc_on(func(d): d.extras.guarded.tiers[0].chest_class = "no_such_table")) and not unknown.start(11, EMBER), "B start() refuses a chest class the loot tables lack")
	var onritual := Chapter.new()
	check(onritual.set_tuning(doc_on(func(d): d.extras.guarded.sites[0].points = [[8, -7]])) and not onritual.start(11, EMBER), "B start() refuses a site point on the ritual spot")
	var near := Chapter.new()
	check(near.set_tuning(doc_on(func(d): d.extras.guarded.sites[0].points = [[8, -2]])) and not near.start(11, EMBER), "B start() refuses a site point within 6 m of a ritual")
	var rejected := Chapter.new()
	check(not rejected.set_tuning(doc_on(func(d): d.elites.hp = [0, 1, 1])), "B set_tuning() rejects a bad block and changes nothing")
	# The shipped points all keep 6 m from the rituals, zone by zone (the same rule start() applies).
	var ok_run := make_run(doc_on())
	check(ok_run != null, "B the shipped sites pass start()'s cross checks")
	# The loot tables carry the new classes and nothing else changed for the old ones.
	var tables := Loot.new()
	check(tables.load_file(), "B loot.json loads")
	for id_ in ["chest", "guarded_chest", "ritual_chest", "boss_g1", "boss_g2", "boss_g3", "boss_g4"]:
		check(tables.data.treasure_classes.has(id_), "B loot.json has the class " + id_)
	check(int(tables.data.treasure_classes.guarded_chest.quality.rare) == 2 * int(tables.data.treasure_classes.chest.rare if tables.data.treasure_classes.chest.has("rare") else tables.data.treasure_classes.chest.quality.rare), "B guarded_chest has twice the rare weight of chest")
	check(int(tables.data.treasure_classes.boss_g3.guaranteed.size()) == 2 and int(tables.data.treasure_classes.boss_g1.picks) == 3 and int(tables.data.treasure_classes.boss_g4.picks) == 6, "B boss_g1..g4 picks and guaranteed rares")

# ------------------------------------------------------------------ C

func body_checks() -> void:
	var run := make_run(doc_on())
	var rules: Dictionary = run.tuning.elites
	var kinds := ["walker", "ranged", "charger"]
	for kind in kinds:
		var id_: int = run._spawn_elite(kind, Vector2(5, 5), 0)
		check(id_ > 0, "C %s: the body is made" % kind)
		var e: Dictionary = run.enemies[id_]
		var plain_id := put(run, Vector2(6, 6), kind)
		var plain: Dictionary = run.enemies[plain_id]
		check(e.grade == "elite" and not e.elite and run._enemy_role(e) == "elite" and run._enemy_role(plain) == "normal", "C %s: grade elite, e.elite false, role elite (an ordinary body stays normal)" % kind)
		check(int(e.hp_raw) == int(rules.hp[0]) * UNIT and int(e.max_hp_raw) == int(e.hp_raw), "C %s: health is the zone's fixed figure" % kind)
		check(int(e.definition.damage) == int(plain.definition.damage) * int(rules.damage_bps) / 10000, "C %s: damage is the ordinary kind's times damage_bps" % kind)
		check(int(e.definition.xp) == int(rules.xp[0]), "C %s: experience is the zone's figure" % kind)
		check(is_equal_approx(float(e.radius), float(plain.radius) * float(rules.radius_bps) / 10000.0), "C %s: radius times radius_bps" % kind)
		check(not e.has("guard_uid"), "C %s: a walker-in has no guard keys" % kind)
	# Speed against a fresh ordinary body of the same kind, before put() zeroes it.
	var run2 := make_run(doc_on())
	var pre: int = run2._spawn_elite("walker", Vector2(5, 5), 0)
	run2._spawn("walker", Vector2(6, 6))
	var ordinary: Dictionary = run2.enemies[run2._enemy_sequence]
	check(is_equal_approx(float(run2.enemies[pre].definition.speed), float(ordinary.definition.speed) * float(rules.speed_bps) / 10000.0), "C speed is the ordinary kind's times speed_bps")
	var found_spawn := false
	var found_elite := false
	var run3 := make_run(doc_on())
	run3.events.clear()
	var id3: int = run3._spawn_elite("charger", Vector2(5, 5), 1)
	for ev in run3.events:
		if ev.type == "spawn" and int(ev.target_id) == id3 and ev.get("grade", "") == "elite" and not ev.elite: found_spawn = true
		if ev.type == "elite_spawned" and int(ev.target_id) == id3 and ev.kind == "charger" and int(ev.zone) == 1 and ev.grade == "elite" and ev.affixes == [] and int(ev.radius_bps) == int(rules.radius_bps) and is_equal_approx(float(ev.radius), float(run3.enemies[id3].radius)) and int(ev.guard_uid) == 0: found_elite = true
	check(found_spawn and found_elite, "C events: spawn carries grade, elite_spawned has target_id, kind, zone, grade, affixes, radius_bps, radius, guard_uid")
	check(int(run3.enemies[id3].hp_raw) == int(rules.hp[1]) * UNIT, "C a second-zone body takes hp[1]")
	# A kill: counts toward the seal, never opens it, drops from the elite table on the floor (source elite), experience orb.
	var run4 := make_run(doc_on(), 21)
	var seal_before: int = run4.zone_kills
	var id4: int = run4._spawn_elite("walker", Vector2(4, 4), 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = run4._loot_rng.seed
	rng.state = run4._loot_rng.state
	var odds := int(run4.tuning.potion.drop_one_in)
	rng.randi_range(0, odds - 1)
	var expected: Array[Dictionary] = run4.loot.roll_class(rng, "elite", Chapter.ZONE_LEVELS[0], EMBER)
	var events := kill(run4, id4)
	check(run4.zone_kills == seal_before + 1 and not run4.seals[0].cleared and int(run4.zone) == 0 and run4.mode == "playing", "C the kill counts as one seal kill and opens nothing")
	var drops := of_type(events, "item_drop")
	check(drops.size() == expected.size() and drops.all(func(ev): return ev.source == "elite" and not bool(ev.item.collected)), "C the drops come from the elite table, on the floor, source elite (%d of %d)" % [drops.size(), expected.size()])
	for index in mini(drops.size(), expected.size()):
		check(drops[index].item.name == expected[index].name and drops[index].item.quality == expected[index].quality, "C the dropped item is the one the elite table rolls with this stream")
	var death := of_type(events, "death")
	check(death.size() == 1 and death[0].role == "elite" and not death[0].elite, "C death: role elite, elite false")
	check(run4.orbs.size() == 1 and int(run4.orbs[0].amount) == int(rules.xp[0]), "C the kill leaves the zone's experience orb")
	check(int(run4.metrics.elites.killed) == 1 and int(run4.metrics.elites.spawned) == 1 and run4.metrics.elites.ttk_ticks.size() == 1, "C metrics.elites counts the spawn and the kill")

# ------------------------------------------------------------------ D

func walk_in_checks() -> void:
	# The body only (no guarded sites: a guard is put down whatever the alive cap says).
	var run := make_run(doc_on(func(d): d.extras.enabled = false))
	var need1: int = int(run.tuning.seal_kills[0]) * int(run.tuning.elites.at_seal_bps[0]) / 10000
	var need2: int = int(run.tuning.seal_kills[0]) * int(run.tuning.elites.at_seal_bps[1]) / 10000
	run.zone_kills = need1 - 1
	tick_run(run, 3)
	check(int(run._elite_made[0]) == 0, "D none before the first share (%d kills)" % run.zone_kills)
	run.zone_kills = need1
	var events := tick_run(run, 2)
	var made := of_type(events, "elite_spawned")
	check(made.size() == 1 and int(made[0].guard_uid) == 0 and int(run._elite_made[0]) == 1, "D the first one comes at its share")
	check(int(made[0].zone) == 0 and made[0].kind == "walker", "D the first zone only makes walkers")
	var body: Dictionary = run.enemies[int(made[0].target_id)]
	var d: float = body.position.distance_to(run.hero.position)
	check(d >= float(run.tuning.spawn.ring_min_m) * 0.8 - 0.01 and d <= float(run.tuning.spawn.ring_max_m) + 0.01, "D it stands on the ordinary spawn ring (%.1f m)" % d)
	tick_run(run, 3)
	check(int(run._elite_made[0]) == 1, "D one share, one elite")
	# The second, held back by a full alive cap until a place frees up.
	run.zone_kills = need2
	var cap: int = int(run.tuning.alive_cap)
	var fill: Array = []
	while run.alive_count() < cap:
		fill.append(put(run, Vector2(14, -14) + Vector2(fill.size() % 10, fill.size() / 10) * .8))
		if fill.size() > cap: break
	# The ticks recount the living; the filled field stays full.
	var held := tick_run(run, 3)
	check(of_type(held, "elite_spawned").is_empty() and int(run._elite_made[0]) == 1, "D a full alive cap holds the second back (alive %d / %d)" % [run.alive_count(), cap])
	run.enemies.erase(fill[0])
	var freed := tick_run(run, 2)
	check(of_type(freed, "elite_spawned").size() == 1 and int(run._elite_made[0]) == 2, "D it comes on the next tick with room")
	# After the guardian is out nothing more is made; what was due is counted when the zone is left.
	var late := make_run(doc_on(func(d): d.extras.enabled = false))
	late.seals[0].champion_spawned = true
	late.zone_kills = need2 + 5
	tick_run(late, 3)
	check(int(late._elite_made[0]) == 0, "D the guardian out: no elite is made")
	var gid := put(late, Vector2(8, 8), "elite")
	late.enemies[gid].title_key = "enemy.champion.0.name"
	late._champion_id = gid
	var gate := kill(late, gid)
	check(int(late.zone) == 1 and int(late.metrics.elites.skipped) == 2 and of_type(gate, "gate_opened").size() == 1, "D leaving the zone counts what never came: elites_skipped %d" % int(late.metrics.elites.skipped))
	# Zone one makes the weighted mix (a few draws, all valid kinds), zone two likewise.
	var mix := make_run(doc_on(func(x): x.elites.per_zone = [4, 4, 4]; x.elites.at_seal_bps = [100, 200, 300, 400]))
	mix.zone = 1
	mix._zone_entered = true
	mix.hero.position = Vector2(48, 0)
	var kinds := {}
	for i in 60: kinds[mix._elite_kind(1)] = true
	check(kinds.has("walker") and kinds.has("charger") and kinds.has("ranged"), "D zone two draws all three kinds from the weights")

# ------------------------------------------------------------------ E

## A stage with the first guard placed and the hero standing at the origin; returns {run, uid, body_id, anchor}.
func guard_stage(mutate: Callable = Callable(), seed_: int = 11) -> Dictionary:
	var run := make_run(doc_on(func(d):
		sites_doc(d)
		if mutate.is_valid(): mutate.call(d)), seed_)
	tick_run(run, 1)
	var site := guard_of(run, 1)
	check(not site.is_empty() and site.state == "locked", "stage: the first site is placed and locked")
	var body_id := int(site.elite_id)
	return {"run": run, "uid": 1, "body_id": body_id, "anchor": site.position}

func guard_checks() -> void:
	var s := guard_stage()
	var run: RefCounted = s.run
	var g: Dictionary = run.tuning.extras.guarded
	var e: Dictionary = run.enemies[s.body_id]
	# Placement.
	check(e.grade == "elite" and int(e.guard_uid) == 1 and e.guard_state == "guard" and e.position == s.anchor and e.guard_anchor == s.anchor, "E the guard stands on its anchor in state guard")
	var d0: float = e.position.distance_to(run.hero.position)
	check(d0 >= float(g.distance_m[0]) and d0 <= float(g.distance_m[1]), "E it is put 12..16 m from the hero (%.1f)" % d0)
	check(is_equal_approx(float(e.guard_leash), float(g.leash_m)), "E the leash comes from the data")
	var view: Dictionary = run.extras_view()
	check(view.enabled and view.sites.size() == 1 and view.sites[0].kind == "shrine" and view.sites[0].shrine_kind == "power" and view.sites[0].tier == "plain" and view.sites[0].guard_state == "guard", "E extras_view: kind, shrine_kind, tier, guard_state")
	check(not view.sites[0].has("chest_class") and not view.sites[0].has("items") and not JSON.stringify(view).contains("guarded_chest"), "E extras_view never names a chest's content")
	run.events.clear()
	# guard_spawned event (read from the tick the site was put).
	var fresh := make_run(doc_on(sites_doc))
	var ev := tick_run(fresh, 1)
	var gs := of_type(ev, "guard_spawned")
	check(gs.size() == 1 and int(gs[0].uid) == 1 and gs[0].kind == "shrine" and gs[0].shrine_kind == "power" and gs[0].tier == "plain" and is_equal_approx(float(gs[0].radius), 6.0) and is_equal_approx(float(gs[0].aggro), 4.0) and int(gs[0].elite_id) > 0 and gs[0].position == fresh.extras_view().sites[0].position, "E guard_spawned: uid, kind, shrine_kind, tier, radius 6, aggro 4, elite_id, position")
	var es := of_type(ev, "elite_spawned")
	check(es.size() == 1 and int(es[0].guard_uid) == 1 and es[0].grade == "elite", "E the paired elite_spawned carries guard_uid")
	# A hero standing 15 m away is not noticed; guard keeps the state however long.
	var quiet := tick_run(run, 200)
	check(e.guard_state == "guard" and of_type(quiet, "guard_state").is_empty() and e.position == s.anchor, "E a far hero changes nothing")
	# Notice: inside aggro_m. guard -> alert (guard_engaged once), then fight after alert_ticks.
	run.hero.position = e.position + Vector2(3.5, 0)
	var noticed := tick_run(run, 1)
	check(e.guard_state == "alert" and of_type(noticed, "guard_engaged").size() == 1 and int(of_type(noticed, "guard_engaged")[0].elite_id) == s.body_id, "E closer than aggro_m: alert, guard_engaged once")
	var states := of_type(noticed, "guard_state")
	check(states.size() == 1 and states[0].from == "guard" and states[0].to == "alert", "E guard_state event guard -> alert")
	var no_attack := tick_run(run, int(g.alert_ticks) - 3)
	check(e.guard_state == "alert" and e.state == "move" and of_type(no_attack, "enemy_attack").is_empty() and e.position == s.anchor, "E alert only turns and waits: no move, no attack")
	var to_fight := tick_run(run, 6)
	check(e.guard_state == "fight" and of_type(to_fight, "guard_state").size() == 1, "E after alert_ticks: fight")
	check(of_type(to_fight, "guard_engaged").is_empty(), "E guard_engaged is not repeated")
	# Fight: the leash holds while the hero stays beyond it; the elite ends at the leash end.
	run.hero.position = s.anchor + Vector2(-1, 1).normalized() * 11.0
	run.hero.position = run._clamp_hero(run.hero.position)
	var worst := 0.0
	for i in 500:
		tick_run(run, 1)
		worst = maxf(worst, e.position.distance_to(s.anchor))
	check(worst <= float(g.leash_m) + 0.001, "E in the fight the guard never stands beyond its leash (%.3f)" % worst)
	check(worst >= float(g.leash_m) - 0.35, "E the guard does walk out to the leash end (%.2f)" % worst)
	# Return: the hero stays beyond return_far_m for return_after_ticks.
	run.hero.position = run._clamp_hero(s.anchor + Vector2(-30, -30))
	var far_tick: int = run.tick
	var back := tick_run(run, int(g.return_after_ticks) + 5)
	check(e.guard_state == "return" or e.guard_state == "guard", "E a hero that stays away sends it home")
	var turned := of_type(back, "guard_state").filter(func(x): return x.to == "return")
	check(turned.size() == 1 and int(turned[0].tick) - far_tick >= int(g.return_after_ticks) and int(turned[0].tick) - far_tick <= int(g.return_after_ticks) + 2, "E the return starts return_after_ticks after the hero left (%d)" % (int(turned[0].tick) - far_tick if turned.size() == 1 else -1))
	tick_run(run, 360)
	check(e.guard_state == "guard" and e.position == s.anchor, "E it walks home and stands on the anchor again in guard")
	# Hit from far while guarding: notice by being hit (hp drop).
	run.hero.position = run._clamp_hero(s.anchor + Vector2(-25, -25))
	tick_run(run, 2)
	e.hp_raw = int(e.hp_raw) - UNIT
	var hurt := tick_run(run, 1)
	check(e.guard_state == "alert" and of_type(hurt, "guard_engaged").is_empty(), "E being hit from afar is noticing (alert); engaged only the first time")
	tick_run(run, int(g.alert_ticks) + 2)
	check(e.guard_state == "fight", "E hit from afar: alert then fight")
	# A noticing during the walk home sends it back to alert.
	run.hero.position = run._clamp_hero(s.anchor + Vector2(-30, -30))
	tick_run(run, int(g.return_after_ticks) + 5)
	check(e.guard_state == "return", "E return again")
	e.position = s.anchor + Vector2(3, 0)
	run.hero.position = e.position + Vector2(2, 0)
	tick_run(run, 1)
	check(e.guard_state == "alert", "E noticing on the way home: alert again")
	# Not relocated by the 25 m rule, even when the hero is far and the body is walking.
	var rec := guard_stage()
	var rrun: RefCounted = rec.run
	var re: Dictionary = rrun.enemies[rec.body_id]
	re.guard_state = "return"
	re.position = rec.anchor + Vector2(2, 0)
	rrun.hero.position = rrun._clamp_hero(rec.anchor + Vector2(-30, -30))
	var before: Vector2 = re.position
	rrun.hero.position = Vector2(-18, -18)
	tick_run(rrun, 3)
	check(re.position.distance_to(rec.anchor) < before.distance_to(rec.anchor) + .001 and re.position.distance_to(rrun.hero.position) > 25.0, "E the 25 m relocation does not take a guard (it walks home)")
	# A charger guard never dashes out of its leash.
	var ch := guard_stage(func(d): d.elites.kinds = [{"charger": 100}, {"charger": 100}, {"charger": 100}])
	var crun: RefCounted = ch.run
	var cbody: Dictionary = crun.enemies[ch.body_id]
	check(cbody.kind == "charger", "E the leash scene uses a charger guard")
	crun.hero.position = crun._clamp_hero(ch.anchor + Vector2(1, 1).normalized() * 10.0)
	cbody.hp_raw = int(cbody.hp_raw) - UNIT
	var most := 0.0
	var dashes := 0
	for i in 900:
		var evs := tick_run(crun, 1)
		dashes += of_type(evs, "enemy_attack").size()
		most = maxf(most, cbody.position.distance_to(ch.anchor))
	check(most <= float(crun.tuning.extras.guarded.leash_m) + .001 and dashes >= 1, "E a charging guard is held to its leash too (%.3f, %d attacks)" % [most, dashes])
	# Ordinary enemies are untouched by the leash rules: a plain walker follows the hero out of any radius.
	var free := put(crun, ch.anchor + Vector2(1, 0))
	crun.enemies[free].definition.speed = 3.0
	var free_far := 0.0
	for i in 300:
		tick_run(crun, 1)
		free_far = maxf(free_far, crun.enemies[free].position.distance_to(ch.anchor))
	check(free_far > float(crun.tuning.extras.guarded.leash_m) + 1.0, "E an ordinary body walks past the leash radius (%.1f m)" % free_far)

# ------------------------------------------------------------------ F

func unlock_checks() -> void:
	# A shrine: locked while the guard lives (touch does nothing), open for stay_ticks after its death, taken by touch.
	var s := guard_stage()
	var run: RefCounted = s.run
	var rules: Dictionary = run.tuning.extras.shrines
	run.hero.position = run._clamp_hero(s.anchor + Vector2(.5, 0))
	tick_run(run, 5)
	check(guard_of(run, 1).state == "locked" and run.extras_view().buffs.is_empty(), "F while the guard lives the shrine is locked: touching it does nothing")
	run.enemies[s.body_id].guard_state = "guard"
	run.hero.position = Vector2.ZERO
	tick_run(run, 2)
	var events := kill(run, s.body_id)
	var unlocked := of_type(events, "guard_unlocked")
	check(unlocked.size() == 1 and int(unlocked[0].uid) == 1 and unlocked[0].kind == "shrine" and unlocked[0].shrine_kind == "power" and int(unlocked[0].elite_id) == s.body_id, "F guard_unlocked on the death tick: uid, kind, shrine_kind, elite_id")
	var open_site := guard_of(run, 1)
	check(open_site.state == "open" and int(open_site.ticks_left) == int(rules.stay_ticks) and open_site.guard_state == "", "F the shrine is open for stay_ticks (%d)" % int(open_site.ticks_left))
	check(of_type(events, "chest_opened").is_empty() and run.items.size() == of_type(events, "item_drop").size(), "F a shrine opens no chest; only the guard's own drop lies on the floor")
	tick_run(run, 600)
	check(guard_of(run, 1).state == "open" and int(guard_of(run, 1).ticks_left) == int(rules.stay_ticks) - 600, "F ticks_left counts down")
	run.hero.position = run._clamp_hero(s.anchor + Vector2(1.2, 0))
	var taken := tick_run(run, 1)
	var t := of_type(taken, "shrine_taken")
	var expect_ticks: int = int(rules.kinds.power.ticks) * int(rules.guarded_ticks_bps) / 10000
	check(t.size() == 1 and t[0].kind == "power" and bool(t[0].guarded) and int(t[0].until_tick) == run.tick + expect_ticks - 0 and int(t[0].uid) == 1, "F touching it takes it: shrine_taken kind power, guarded, until_tick = now + ticks x guarded_ticks_bps")
	check(guard_of(run, 1).state == "taken" and int(guard_of(run, 1).ticks_left) == expect_ticks - 0, "F state taken, ticks_left is the buff's time")
	check(expect_ticks == 2700, "F the guarded time is 45 s (%d ticks)" % expect_ticks)
	# A shrine nobody takes lapses after stay_ticks.
	var lapse := guard_stage()
	var lrun: RefCounted = lapse.run
	lrun.hero.position = Vector2.ZERO
	kill(lrun, lapse.body_id)
	var gone := tick_run(lrun, int(lrun.tuning.extras.shrines.stay_ticks) + 3)
	var expired := of_type(gone, "shrine_expired")
	check(expired.size() == 1 and int(expired[0].uid) == 1 and guard_of(lrun, 1).state == "gone" and int(lrun.metrics.sites.shrines_expired) == 1, "F an unused shrine lapses: shrine_expired, state gone")
	lrun.hero.position = lapse.anchor
	tick_run(lrun, 3)
	check(lrun.extras_view().buffs.is_empty(), "F a lapsed shrine gives nothing")
	# A chest in the second zone: opens on the spot at the guard's death.
	var cs := chest_stage()
	var crun: RefCounted = cs.run
	var cid: int = cs.body_id
	var rng := RandomNumberGenerator.new()
	rng.seed = crun._loot_rng.seed
	rng.state = crun._loot_rng.state
	rng.randi_range(0, int(crun.tuning.potion.drop_one_in) - 1)
	var elite_roll: Array[Dictionary] = crun.loot.roll_class(rng, "elite", Chapter.ZONE_LEVELS[1], EMBER)
	var chest_roll: Array[Dictionary] = crun.loot.roll_class(rng, "guarded_chest", Chapter.ZONE_LEVELS[1], EMBER)
	var potions_before: int = crun.potion_pickups.size()
	var chest_events := kill(crun, cid)
	var opened := of_type(chest_events, "chest_opened")
	check(opened.size() == 1 and bool(opened[0].guarded) and int(opened[0].count) == chest_roll.size() and chest_roll.size() == 2, "F chest_opened: guarded, count = the guarded_chest picks (%d)" % chest_roll.size())
	var chest_drops := of_type(chest_events, "item_drop").filter(func(x): return x.source == "chest")
	check(chest_drops.size() == chest_roll.size(), "F the chest items fall on the floor with source chest")
	for index in mini(chest_drops.size(), chest_roll.size()):
		check(chest_drops[index].item.name == chest_roll[index].name and chest_drops[index].item.quality == chest_roll[index].quality and int(chest_drops[index].site_uid) == 1, "F chest item %d is the guarded_chest roll of this stream, with the site_uid" % index)
	var elite_drops := of_type(chest_events, "item_drop").filter(func(x): return x.source == "elite")
	check(elite_drops.size() == elite_roll.size(), "F the guard's own elite drop is still there on top of the chest")
	check(crun.potion_pickups.size() >= potions_before + int(crun.tuning.extras.guarded.potions), "F the chest leaves its potion")
	var site := guard_of(crun, 1)
	check(site.state == "taken" and site.kind == "chest" and site.shrine_kind == "" and int(site.ticks_left) == 0, "F a chest goes locked -> taken on the death tick")
	check(of_type(chest_events, "guard_unlocked").size() == 1 and of_type(chest_events, "guard_unlocked")[0].kind == "chest", "F guard_unlocked for the chest")
	check(int(crun.metrics.sites.chests_opened) == 1 and int(crun.metrics.sites.unlocked) == 1, "F the tallies count the opening")
	# Tiers: a second tier makes the elite stronger and picks the chest class of that tier.
	var tiered := guard_stage(func(d): d.extras.guarded.tiers = [{"id": "fine", "weight": 100, "elite_hp_bps": 15000, "chest_class": "ritual_chest"}])
	var te: Dictionary = tiered.run.enemies[tiered.body_id]
	check(int(te.max_hp_raw) == int(tiered.run.tuning.elites.hp[0]) * 15000 / 10000 * UNIT and guard_of(tiered.run, 1).tier == "fine", "F a tier raises the guard's health (bps) and is shown on the site")
	# Tier draw: with two tiers the weights decide, from the extras stream only.
	var two := make_run(doc_on(func(d):
		sites_doc(d)
		d.extras.guarded.tiers = [{"id": "plain", "weight": 50, "elite_hp_bps": 10000, "chest_class": "guarded_chest"}, {"id": "fine", "weight": 50, "elite_hp_bps": 15000, "chest_class": "ritual_chest"}]))
	var seen := {}
	for i in 40: seen[String(two._pick_tier(two.tuning.extras.guarded.tiers).id)] = true
	check(seen.has("plain") and seen.has("fine"), "F both tiers are drawn by weight")

func chest_stage() -> Dictionary:
	var run := make_run(doc_on(sites_doc))
	run.zone = 1
	run._zone_entered = false
	run.hero.position = Vector2(48, 0)
	run._site_next = 2
	tick_run(run, 1)
	var site := guard_of(run, 1)
	check(not site.is_empty() and site.kind == "chest" and site.state == "locked", "stage: the second zone's chest is placed")
	return {"run": run, "body_id": int(site.elite_id), "anchor": site.position}

# ------------------------------------------------------------------ G

func take_kind(run: RefCounted, uid: int) -> void:
	var site := guard_of(run, uid)
	var body_id := int(site.elite_id)
	run.hero.position = Vector2.ZERO
	run.enemies[body_id].guard_state = "guard"
	kill(run, body_id)
	run.hero.position = run._clamp_hero(site.position + Vector2(.5, 0))
	tick_run(run, 1)

## Both zone-one sites placed (the second is due at one seal kill).
func shrine_run(mutate: Callable = Callable(), seed_: int = 11, primary: String = EMBER) -> RefCounted:
	var run := make_run(doc_on(func(d):
		sites_doc(d)
		if mutate.is_valid(): mutate.call(d)), seed_, primary)
	run.zone_kills = 1
	tick_run(run, 2)
	check(run.extras_view().sites.size() == 2, "stage: both zone-one sites are placed")
	return run

func buff_checks() -> void:
	var run := shrine_run()
	var plain0 := make_run(doc_on(sites_doc))
	var base_stats: Dictionary = run._gear_stats.duplicate()
	var base_speed: float = run.hero.speed
	take_kind(run, 1)
	check(int(run._gear_stats.get("cooldown_bps", 0)) == 4300 and run.extras_view().buffs.size() == 1 and run.extras_view().buffs[0].kind == "power", "G power: cooldown_bps +4300 on top of the gear")
	check(int(run.effective_skill(EMBER).effects.cooldown_ticks) < int(plain0.effective_skill(EMBER).effects.cooldown_ticks), "G the primary's interval reads the buff")
	# A different kind runs beside it.
	take_kind(run, 2)
	check(int(run._gear_stats.get("cooldown_bps", 0)) == 4300 and int(run._gear_stats.get("move_speed_bps", 0)) == 2500 and int(run._gear_stats.get("dash_cooldown_bps", 0)) == 4000, "G swift runs beside power")
	check(is_equal_approx(float(run.hero.speed), base_speed * 1.25), "G the hero's speed follows move_speed_bps at once")
	check(run.extras_view().buffs.size() == 2, "G two buffs are listed")
	# preview_equip / compare_item see gear only.
	var tables = run.loot
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var item: Dictionary = tables.roll_item(rng, 8, "rare", "feet")
	item.uid = 900
	item.position = Vector2.ZERO
	item.collected = true
	item.drop_tick = 0
	run.inventory.append(item)
	var plain := make_run(doc_on(sites_doc))
	var plain_item: Dictionary = item.duplicate(true)
	plain.inventory.append(plain_item)
	var with_buffs: Dictionary = run.preview_equip(900)
	var without: Dictionary = plain.preview_equip(900)
	check(JSON.stringify(with_buffs.before) == JSON.stringify(without.before) and JSON.stringify(with_buffs.after) == JSON.stringify(without.after) and JSON.stringify(with_buffs.rows) == JSON.stringify(without.rows), "G preview_equip with buffs running equals the preview without them (gear only)")
	check(JSON.stringify(run.compare_item(900)) == JSON.stringify(plain.compare_item(900)), "G compare_item is the same with and without the buffs")
	check(run.stat_sheet().hero.rows.any(func(r): return r.id == "speed" and is_equal_approx(float(r.value), base_speed * 1.25)), "G stat_sheet() (what the core uses now) does include the buff")
	# Wearing gear while a buff runs keeps the buff (the totals are gear plus buffs every time).
	run.equipped["feet"] = 900
	run._recompute_gear()
	check(int(run._gear_stats.get("cooldown_bps", 0)) >= 4300 and int(run._gear_stats.get("move_speed_bps", 0)) >= 2500, "G the buffs survive a gear change")
	# Same kind again refills the time, never doubles the stat.
	var second := shrine_run(func(d): d.extras.guarded.sites[1].pool = "p_power")
	take_kind(second, 1)
	var first_until: int = int(second.extras_view().buffs[0].until_tick)
	tick_run(second, 300)
	take_kind(second, 2)
	check(second.extras_view().buffs.size() == 1 and int(second.extras_view().buffs[0].until_tick) == int(second.tick) + 2700 and int(second._gear_stats.cooldown_bps) == 4300, "G the same kind again: one buff, time filled anew, the stat not doubled")
	check(int(second.extras_view().buffs[0].until_tick) > first_until, "G the refilled buff ends later than the first one would have")
	# Expiry: the stat goes away, buff_ended is announced.
	var run_b := shrine_run()
	take_kind(run_b, 1)
	var until: int = int(run_b.extras_view().buffs[0].until_tick)
	var after := tick_run(run_b, until - run_b.tick + 1)
	check(of_type(after, "buff_ended").size() == 1 and run_b.extras_view().buffs.is_empty() and int(run_b._gear_stats.get("cooldown_bps", 0)) == 0, "G on expiry the stat is gone and buff_ended names the kind")
	check(of_type(after, "buff_ended")[0].kind == "power", "G buff_ended carries the kind")
	check(run_b._gear_stats == base_stats, "G with every buff over the gear stats equal the stats before (no residue)")
	# The limit cut: a buff on top of gear is cut to the grammar's limit.
	var cut := shrine_run(func(d): d.extras.shrines.kinds.power.stats = {"cooldown_bps": 9000})
	cut.inventory.append({"uid": 801, "slot": "charm", "stats": {"cooldown_bps": 8000}, "quality": "rare", "item_level": 1, "required_level": 1, "name": "x", "grammar": 2})
	cut.equipped["charm"] = 801
	cut._recompute_gear()
	take_kind(cut, 1)
	check(int(cut._gear_stats.cooldown_bps) == int(cut.loot.data.limits.cooldown_bps[1]), "G gear plus buff is cut to the loot limit (%d)" % int(cut._gear_stats.cooldown_bps))
	# Harvest and ward.
	var hw := shrine_run(func(d):
		d.extras.guarded.sites[0].pool = "p_harvest"
		d.extras.guarded.sites[1].pool = "p_ward")
	take_kind(hw, 1)
	check(int(hw._gear_stats.soul_gain_bps) == 5000 and int(hw._gear_stats.pickup_radius_cm) == 300, "G harvest: soul_gain_bps and pickup_radius_cm")
	# take_kind tops the hero up on its way; read the heal on the taking tick itself.
	var site_b := guard_of(hw, 2)
	hw.hero.position = Vector2.ZERO
	hw.enemies[int(site_b.elite_id)].guard_state = "guard"
	kill(hw, int(site_b.elite_id))
	hw.hero.position = hw._clamp_hero(site_b.position + Vector2(.5, 0))
	hw.hero.hp_raw = int(hw.hero.max_hp_raw) / 2
	hw.step(Vector2.ZERO)
	check(int(hw._gear_stats.damage_reduction_bps) == 3000 and int(hw.hero.hp_raw) == int(hw.hero.max_hp_raw) / 2 + int(hw.hero.max_hp_raw) * 2500 / 10000, "G ward: damage reduction and a quarter of the life back on the taking tick")
	# Luck: loot.roll_class mods. No mods = the old draw and the same stream use; the drop weight and the quality weights follow the mods.
	var tables2 := Loot.new()
	tables2.load_file()
	var r1 := RandomNumberGenerator.new()
	var r2 := RandomNumberGenerator.new()
	r1.seed = 99
	r2.seed = 99
	var same := true
	for i in 3000:
		var x := tables2.roll_class(r1, "elite", 8, EMBER)
		var y := tables2.roll_class(r2, "elite", 8, EMBER, {})
		if JSON.stringify(x) != JSON.stringify(y): same = false
	check(same and r1.state == r2.state, "G roll_class without mods (or with {}) makes the same items and uses the stream the same way")
	var plain_count := 0
	var lucky_count := 0
	var plain_rare := 0
	var lucky_rare := 0
	var ra := RandomNumberGenerator.new()
	var rb := RandomNumberGenerator.new()
	ra.seed = 7
	rb.seed = 7
	var mods := {"drop_bps": 20000, "quality_bps": {"rare": 20000, "legendary": 15000, "unique": 15000}}
	for i in 30000:
		for item_ in tables2.roll_class(ra, "normal", 4, EMBER):
			plain_count += 1
			if item_.quality == "rare": plain_rare += 1
		for item_ in tables2.roll_class(rb, "normal", 4, EMBER, mods):
			lucky_count += 1
			if item_.quality == "rare": lucky_rare += 1
	check(lucky_count > plain_count * 1.6 and lucky_count < plain_count * 2.4, "G luck doubles the drop chance (%d -> %d in 30000 kills)" % [plain_count, lucky_count])
	check(float(lucky_rare) / maxf(1.0, float(lucky_count)) > float(plain_rare) / maxf(1.0, float(plain_count)) * 1.3, "G luck raises the share of rare drops (%d/%d -> %d/%d)" % [plain_rare, plain_count, lucky_rare, lucky_count])
	# The luck buff reaches the core's drops: while it runs the ordinary kill rolls with the mods, afterwards without.
	var lk := shrine_run(func(d): d.extras.guarded.sites[0].pool = "p_luck")
	check(lk._luck_mods().is_empty(), "G no luck mods before the shrine")
	take_kind(lk, 1)
	check(lk._luck_mods().drop_bps == 20000 and lk._luck_mods().quality_bps.rare == 20000, "G the luck shrine puts its mods on the core's drops")
	lk._buffs.clear()
	lk._buffs_changed()
	check(lk._luck_mods().is_empty(), "G the mods end with the buff")

# ------------------------------------------------------------------ H

func zone_left_checks() -> void:
	var run := shrine_run()
	# At the gate: site 1 taken, site 2 still locked.
	take_kind(run, 1)
	var b_id: int = int(guard_of(run, 2).elite_id)
	var kills_before: int = run.kills
	var seal_kills_before: int = run.seals[0].kills
	var cid := put(run, Vector2(8, 8), "elite")
	run.enemies[cid].title_key = "enemy.champion.0.name"
	run._champion_id = cid
	run.seals[0].champion_spawned = true
	var gate := kill(run, cid)
	check(int(run.zone) == 1, "H the guardian's death opens the gate")
	var expired := of_type(gate, "guard_expired")
	check(expired.size() == 1 and int(expired[0].uid) == 2 and int(expired[0].elite_id) == b_id, "H guard_expired for the locked site only")
	check(guard_of(run, 2).state == "gone" and guard_of(run, 1).state == "gone", "H both zone-one sites are gone (a taken one silently)")
	check(run.kills == kills_before + 1 and run.seals[0].kills == seal_kills_before + 1, "H the guard's disappearance is no kill and no seal kill (only the guardian's own)")
	check(of_type(gate, "death").size() == 1 and of_type(gate, "item_drop").size() == of_type(gate, "item_drop").filter(func(x): return x.source in ["champion", "boss", "first_kill"]).size(), "H no death and no drop but the guardian's")
	check(run.enemies.has(b_id), "H the guard body is still there in the tick of the gate (it is taken out at the start of the next tick)")
	var next := tick_run(run, 1)
	check(not run.enemies.has(b_id) and of_type(next, "death").is_empty(), "H the next tick takes the guard out of the world without a death")
	check(run.extras_view().buffs.size() == 1, "H a running buff goes on in the next zone")
	# The next zone puts its chest down once the hero is in it.
	run.hero.position = Vector2(48, 0)
	var entered := tick_run(run, 2)
	check(of_type(entered, "guard_spawned").size() == 1 and of_type(entered, "guard_spawned")[0].kind == "chest" and int(of_type(entered, "guard_spawned")[0].zone) == 1, "H the second zone's chest is put down when the zone is entered")
	# A shrine left open lapses at the gate (shrine_expired).
	var open := make_run(doc_on(sites_doc))
	tick_run(open, 2)
	var oid: int = int(guard_of(open, 1).elite_id)
	open.hero.position = Vector2.ZERO
	kill(open, oid)
	check(guard_of(open, 1).state == "open", "H a shrine is open")
	var gid := put(open, Vector2(8, 8), "elite")
	open.enemies[gid].title_key = "enemy.champion.0.name"
	open._champion_id = gid
	open.seals[0].champion_spawned = true
	var lapsed := kill(open, gid)
	check(of_type(lapsed, "shrine_expired").size() == 1 and guard_of(open, 1).state == "gone", "H a shrine left open lapses at the gate")
	# A site whose zone was left before it was due is dropped and counted (here: due at 90 percent, guardian first).
	var skip := make_run(doc_on(func(d):
		sites_doc(d)
		d.extras.guarded.sites[0].at_bps = 9000
		d.extras.guarded.sites[1].at_bps = 9500))
	skip.seals[0].champion_spawned = true
	var sid := put(skip, Vector2(8, 8), "elite")
	skip.enemies[sid].title_key = "enemy.champion.0.name"
	skip._champion_id = sid
	tick_run(skip, 2)
	check(skip.extras_view().sites.is_empty() and int(skip.metrics.sites.skipped) >= 1, "H with the guardian already out a due site is dropped and counted (skipped %d)" % int(skip.metrics.sites.skipped))
	kill(skip, sid)
	tick_run(skip, 2)
	check(int(skip.metrics.sites.skipped) == 2 and int(skip.metrics.sites.placed) == 0, "H both zone-one sites skipped, none placed")

# ------------------------------------------------------------------ I

func stream_checks() -> void:
	# A quiet world: the blocks on or off, the ordinary streams stand where they stood.
	var off := make_run(shipped_far())
	var on := make_run(doc_on(sites_doc))
	on.zone_kills = 1
	tick_run(off, 900)
	tick_run(on, 900)
	check(on.extras_view().sites.size() == 2, "I sites were placed in the run being compared")
	check(on._spawn_rng.state == off._spawn_rng.state, "I _spawn_rng is where it would be without the blocks")
	check(on._loot_rng.state == off._loot_rng.state, "I _loot_rng is where it would be without the blocks (no kill, no draw)")
	var consumed := RandomNumberGenerator.new()
	consumed.seed = 11 ^ Chapter.EXTRAS_SEED_MASK
	check(on._extras_rng.state != consumed.state, "I the extras stream is the one that moved")
	# Walking in elites draw from the extras stream too.
	var walk := make_run(doc_on(func(d): d.elites.at_seal_bps = [1, 2]))
	var walk_off := make_run(shipped_far())
	walk.zone_kills = 5
	walk_off.zone_kills = 5
	tick_run(walk, 20)
	tick_run(walk_off, 20)
	check(walk._elite_made[0] == 2 and walk._spawn_rng.state == walk_off._spawn_rng.state and walk._loot_rng.state == walk_off._loot_rng.state, "I walking-in elites leave the spawn and loot streams alone")
	# Live: a stationary hero that casts. The ordinary spawns (kind and place) are the same with the blocks on or off.
	var a := live_spawns(shipped_far(), 1500)
	var b := live_spawns(doc_on(sites_doc), 1500)
	var same := a.size() == b.size() and a.size() > 20
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			same = false
			break
	check(same, "I the ordinary spawns (%d of them) are the same with the blocks on or off, tick for tick" % a.size())

func shipped_far() -> Dictionary:
	var d := shipped()
	var far: Array = []
	for i in 12: far.append(i * 90000)
	d.xp_thresholds = far
	return d

## The non-elite spawn events (kind, position, tick) of a hero who stands still and casts.
func live_spawns(doc: Dictionary, ticks: int) -> Array:
	var run := make_run(doc, 11, EMBER, false)
	var out: Array = []
	for i in ticks:
		if run.mode != "playing": break
		run.hero.hp_raw = run.hero.max_hp_raw
		run.step(Vector2.ZERO)
		for ev in run.events:
			if ev.type == "spawn" and ev.get("grade", "") != "elite": out.append([ev.kind, ev.position, int(ev.tick)])
	return out

# ------------------------------------------------------------------ J

func combo_checks() -> void:
	# The run opening (rhythm on): no guard and no walking-in elite while an opening step runs.
	var doc := doc_on(func(d):
		sites_doc(d)
		d.elites.at_seal_bps = [1, 2]
		d.rhythm.enabled = true
		d.rhythm.opening.enabled = true)
	var run := make_run(doc, 11, EMBER, false)
	check(run != null and run._op_active == false and run._opening_on, "J the opening is on in this run")
	var pilot = Pilot.new()
	pilot.run = run
	var first_guard := -1
	var first_elite := -1
	var op_end := -1
	var during_opening := 0
	for i in 5200:
		var move: Vector2 = pilot.decide()
		if run.mode == "playing":
			run.hero.hp_raw = run.hero.max_hp_raw
			run.step(move)
			for ev in run.events:
				if ev.type == "guard_spawned" and first_guard < 0: first_guard = int(ev.tick)
				if ev.type == "elite_spawned" and first_elite < 0: first_elite = int(ev.tick)
				if ev.type == "opening_end" and op_end < 0: op_end = int(ev.tick)
				if (ev.type == "guard_spawned" or ev.type == "elite_spawned") and run._op_active: during_opening += 1
		elif run.mode != "choice": break
	check(op_end > 0, "J the opening ended (tick %d)" % op_end)
	check(during_opening == 0, "J no guard and no walking-in elite appeared while an opening step ran")
	check(first_guard >= op_end and first_elite >= op_end, "J the first guard (%d) and the first elite (%d) come after the opening ended (%d)" % [first_guard, first_elite, op_end])
	# The descent: a guard in reach is a strong enemy (strong.elite_bps of its life), is not killed by one sweep, and is then fighting.
	for element in ["ember", "frost", "arc"]:
		var prim: String = "chapter1.skill." + String(element)
		var descent: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DESCENT))
		descent.enabled = true
		var base := Chapter.new()
		check(base.set_tuning(doc_on(sites_doc)) and base.set_descent(descent) and base.start(11, prim), "J %s: the descent starts with the guards" % element)
		base.first_boss_kill = true
		base.enemies.clear()
		base._alive = 0
		base._next_spawn = 1 << 30
		for id_ in base._skill_ids: base._next_cast[id_] = 1 << 30
		tick_run(base, 1)
		var site := guard_of(base, 1)
		var body: Dictionary = base.enemies[int(site.elite_id)]
		# Bring the guard into the descent's reach (13 m) and let it be a stranger to the hero: it stays a guard.
		body.position = Vector2(9, 0)
		body.guard_anchor = Vector2(9, 0)
		body.guard_state = "guard"
		var max_life: int = int(body.max_hp_raw)
		base._descent_add(int(base.descent.cost[0]))
		check(base.request_descent(), "J %s: the call is accepted" % element)
		var called := of_type(base.events, "descent_called")
		check(called.size() == 1 and int(called[0].strongs_in_reach) >= 1, "J %s: the guard counts among the strong enemies in reach" % element)
		check(base.release_descent(), "J %s: released" % element)
		var sweep := tick_run(base, int(base.descent.ultimates[element].sweep_ticks) + 2)
		var strikes := of_type(sweep, "descent_strike").filter(func(x): return int(site.elite_id) in x.target_ids)
		check(not strikes.is_empty(), "J %s: the sweep struck the guard" % element)
		var taken: int = max_life - int(body.hp_raw)
		var share: int = max_life * int(base.descent.strong.elite_bps) / 10000
		check(body.hp_raw > 0 and body.state != "dead" and taken >= share - UNIT and taken <= share + max_life * int(base.descent.strong.marks_cap_bps) / 10000, "J %s: it lost about the strong share (%d of %d, share %d) and lives" % [element, taken, max_life, share])
		check(String(body.guard_state) in ["alert", "fight"], "J %s: being hit by the descent is being noticed (%s)" % [element, String(body.guard_state)])
		check(guard_of(base, 1).state == "locked", "J %s: the site stays locked" % element)
		# And a descent that does kill it opens the site: strong share plus the rest.
		var end := of_type(sweep, "descent_end")
		check(end.size() == 1, "J %s: the sweep ended" % element)
		check(base.descent_view().enabled and base.descent_view().element == element, "J %s: descent_view still reads with the guards in the run" % element)
	# The grace grades: the luck shrine raises the grade luck, and gives it back when it ends.
	var graded := doc_on(func(d):
		sites_doc(d)
		d.extras.guarded.sites[0].pool = "p_luck"
		d.grace.enabled = true
		d.grace.grades.enabled = true)
	var gr := make_run(graded, 11, EMBER, true)
	check(gr != null and gr.growth.grades_on(), "J grades are on in the run with the shrines")
	gr.zone_kills = 1
	tick_run(gr, 2)
	check(int(gr.growth.snapshot().grace.luck.shrine_mul_bps) == 10000, "J before the shrine the grade luck is 1.0x")
	take_kind(gr, 1)
	check(int(gr.growth.snapshot().grace.luck.shrine_mul_bps) == int(gr.tuning.grace.grades.luck.shrine_mul_bps), "J the luck shrine puts the shrine multiplier on the grades (%d)" % int(gr.growth.snapshot().grace.luck.shrine_mul_bps))
	var until: int = int(gr.extras_view().buffs[0].until_tick)
	tick_run(gr, until - gr.tick + 1)
	check(int(gr.growth.snapshot().grace.luck.shrine_mul_bps) == 10000, "J the multiplier goes back to 1.0x when the buff ends")
	# A shrine of another kind leaves the grade luck alone.
	var gp := shrine_run(func(d):
		d.grace.enabled = true
		d.grace.grades.enabled = true)
	take_kind(gp, 1)
	check(int(gp.growth.snapshot().grace.luck.shrine_mul_bps) == 10000, "J a power shrine does not touch the grade luck")
	# Grace off: the shrine still works (no growth call is made).
	var go := shrine_run(func(d): d.extras.guarded.sites[0].pool = "p_luck")
	take_kind(go, 1)
	check(go.extras_view().buffs.size() == 1 and not go.growth.grades_on(), "J the luck shrine works with the grace off")

# ------------------------------------------------------------------ K

func determinism_checks() -> void:
	for primary in [EMBER, "chapter1.skill.frost", "chapter1.skill.arc"]:
		var a := play(doc_on(sites_doc, false), 11, 2400, primary)
		var b := play(doc_on(sites_doc, false), 11, 2400, primary)
		check(a.hash == b.hash, "K %s: the same seed and the same pilot, with the blocks on, give the same snapshot" % primary)
		var made := of_type(a.events, "elite_spawned").size()
		check(made >= 1, "K %s: the run made elites (%d)" % [primary, made])
		var other := play(doc_on(sites_doc, false), 12, 2400, primary)
		check(other.hash != a.hash, "K %s: another seed gives another snapshot" % primary)
	var snap: Dictionary = play(doc_on(sites_doc, false), 11, 600).run.snapshot()
	check(snap.chapter.has("elites") and snap.chapter.has("extras") and snap.chapter.extras.sites.size() >= 1 and snap.chapter.extras.has("next_site_index") and snap.chapter.extras.has("buffs"), "K the snapshot carries elites and extras (sites, buffs, next_site_index) when on")

func execute() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/_local/appdata/"):
		print("CHAPTER1_ELITES_TEST_RESULT ", JSON.stringify({"checks": 0, "failures": ["user data dir is not isolated: refusing to run"]}))
		quit(1)
		return
	off_checks()
	validator_checks()
	body_checks()
	walk_in_checks()
	guard_checks()
	unlock_checks()
	buff_checks()
	zone_left_checks()
	stream_checks()
	combo_checks()
	determinism_checks()
	print("CHAPTER1_ELITES_TEST_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
