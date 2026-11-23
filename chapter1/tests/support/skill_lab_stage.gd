extends RefCounted
## QA tool (never product code): the stage of the skill lab (docs/specs/T12-skill-lab-20261123.ko.md, SL-B).
##
## EVERY line that reaches into the core's private state lives in this one file, each with what it touches and why. The core
## is not changed by the lab; if a core change breaks the lab it breaks here, and the headless test (test_skill_lab.gd) says so.
## Public entry points of the core used elsewhere: run.start (through view.start_run), run.growth.set_thresholds,
## run.request_descent (through view.call_descent), run.descent_view, run.events, run.hero, run.enemies, run.tick, run.mode.
##
## What the stage does NOT touch: damage, hit rules, cooldown lengths, projectile flight, the descent's own numbers.

const HUGE := 1 << 40                       ## "never" in ticks / raw hp
const XP_TABLE := [0, 100000, 200000, 300000, 400000, 500000, 600000, 700000, 800000, 900000, 950000, 1000000]
const DURABLE_HP_RAW := 1 << 40             ## a body that does not die (the hits and their numbers still happen)
const AIM_DEG := -38.2                      ## the screen's "right" on the ground (same axis as descent_fx_shots.gd rect_point)
const PACK_KINDS := ["walker", "walker", "ranged", "charger"]
const CROWD_KINDS := ["walker", "walker", "walker", "ranged", "charger"]
const LAYOUTS := ["single", "pack", "line", "elite", "crowd"]
const CROWD_HALF_W := 17.3                  ## the descent's screen rectangle, as in descent_fx_shots.gd
const CROWD_HALF_H := 13.4
const MAX_COUNT := 40

var staged_ids: Dictionary = {}             ## enemy id -> true, every body this stage placed (to tell a foreign spawn)
var staged_count := 0                       ## bodies placed by the last place()
var _cycle := 0


func aim_dir() -> Vector2:
	return Vector2.from_angle(deg_to_rad(AIM_DEG))


## The core is "stage ready" when it runs the plain ordinary mode: no rhythm waves, no opening, descent switchable.
## Returns problems (empty = fine). Reads private flags only.
func check_core(run: RefCounted) -> Array:
	var problems: Array = []
	if bool(run._rhythm_on): problems.append("rhythm is on (--chapter1-trial=rhythm): the ordinary spawn is not stopped by the lab")
	if bool(run._elites_on) or bool(run._extras_on): problems.append("elites/extras are on: sites and guards are not part of the lab")
	return problems


## Right after view.start_run (a freshly configured growth, xp 0): level-ups are made unreachable.
func prepare_run(run: RefCounted) -> void:
	# growth: a table of twelve far-apart levels, so the experience orbs the kills drop never open a card choice (public function).
	run.growth.set_thresholds(XP_TABLE)
	clear_field(run)
	keep(run)


## What must hold on every tick (after the core's step): the lab's rules against the run's own events.
func keep(run: RefCounted) -> void:
	# _next_spawn: the ordinary spawn clock (compared with tick in _spawn_wave); far in the future = no natural spawn.
	run._next_spawn = HUGE
	# zone_kills / seals[0].kills: the seal breaks at a kill count and sends the zone guardian, the gate and the next zone.
	run.zone_kills = 0
	run.seals[0].kills = 0
	# _invulnerable_until: the hero cannot be hurt (a blocked hit makes no event, so no "hurt" sound either).
	run._invulnerable_until = HUGE


## Everything of a staging, removed. Called when a scene is set up again (never while a cast is in the air, see is_quiet).
func clear_field(run: RefCounted) -> void:
	run.enemies.clear()              # the bodies (the screen drops the pictures of ids that are gone)
	run._alive = 0                   # the live count (recounted each tick in _cleanup, kept consistent here)
	run.projectiles.clear()          # friendly and hostile shots
	run._meteors.clear()             # booked meteor falls
	run._pending_children.clear()    # chain / split children waiting to fly
	run._ring_pending.clear()        # ring pulses waiting
	run._contexts.clear()            # the casts' bookkeeping (nothing is in flight when this is called)
	run.orbs.clear()                 # experience orbs on the ground
	run.items.clear()                # gear on the ground
	run.inventory.clear()            # gear that was picked up
	run.potion_pickups.clear()       # potion drops
	run.chapter_hazards.clear()      # floor strikes
	run._fields.clear()              # the permanent build's fields (none without a profile; cleared for safety)
	run._grid.clear()                # the neighbour grid is rebuilt by the next step
	staged_ids.clear()
	staged_count = 0


## True when nothing of the last cast is still moving: a new staging can start without cutting an effect off.
func is_quiet(run: RefCounted, fx_status: Dictionary) -> bool:
	if run.mode != "playing": return false
	for p in run.projectiles:
		if not bool(p.get("hostile", false)): return false
	if not run._meteors.is_empty() or not run._pending_children.is_empty() or not run._ring_pending.is_empty(): return false
	var view: Dictionary = run.descent_view()
	if bool(view.get("enabled", false)) and String(view.get("state", "")) in ["hold", "sweep"]: return false
	if bool(fx_status.get("sweep", false)) or bool(fx_status.get("cutin", false)): return false
	return true


## The skill form of the run: "base" (rank 1 of the primary) or "evolved" (its evolution; ember's is the meteor).
func set_form(run: RefCounted, primary: String, form: String) -> void:
	# growth._evolved: the list of evolved skills; effective_skill() reads it to pick the evolution's effect. There is no public
	# way to evolve without playing the card choices, and the lab must not play them.
	var list: Array = run.growth._evolved
	if form == "evolved":
		if not primary in list: list.append(primary)
	else:
		list.erase(primary)


## Allow the next cast of this skill on the next tick (the cast needs a live body within the acquire range).
func arm_cast(run: RefCounted, primary: String) -> void:
	# _next_cast: tick of the skill's next allowed cast; 0 = now.
	run._next_cast[primary] = 0


## One cast is enough: no second cast until the next staging.
func disarm_cast(run: RefCounted, primary: String) -> void:
	run._next_cast[primary] = HUGE


## Fill the descent's gauge so the descent can be called (the same function the kills use to fill it).
func fill_gauge(run: RefCounted) -> bool:
	var view: Dictionary = run.descent_view()
	if not bool(view.get("enabled", false)): return false
	if bool(view.get("ready", false)): return true
	run._descent_add(int(view.cost_now))
	return bool(run.descent_view().get("ready", false))


## Places the bodies of a layout. Returns how many were placed. Deterministic for the same (seed, cycle).
func place(run: RefCounted, layout: String, count: int, motion: String, durable: bool, seed_: int) -> int:
	_cycle += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_ * 7919 + _cycle
	var origin: Vector2 = run.hero.position
	var right := aim_dir()
	var down := right.rotated(PI * 0.5)
	var n := clampi(count, 1, MAX_COUNT)
	var placed := 0
	var points: Array = []      # [kind, position]
	match layout:
		"single":
			points.append(["walker", origin + right * 6.0])
		"elite":
			points.append(["elite", origin + right * 7.0])
		"pack":
			var center := origin + right * 7.0
			var tries := 0
			var spots: Array[Vector2] = []
			while spots.size() < n and tries < n * 30:
				tries += 1
				var a := rng.randf() * TAU
				var r := 2.5 * sqrt(rng.randf())
				var at := center + Vector2.from_angle(a) * r
				var apart := true
				if tries < n * 20:       # keep bodies apart while there is room; late tries may overlap rather than miss the count
					for other in spots:
						if other.distance_to(at) < 0.8: apart = false; break
				if apart: spots.append(at)
			for i in spots.size(): points.append([PACK_KINDS[i % PACK_KINDS.size()], spots[i]])
		"line":
			for i in n:
				var d := 5.0 if n == 1 else 5.0 + 7.0 * float(i) / float(n - 1)
				points.append(["walker", origin + right * d])
		"crowd":
			var tries2 := 0
			while points.size() < n and tries2 < n * 8:
				tries2 += 1
				var u := rng.randf_range(-CROWD_HALF_W + 1.5, CROWD_HALF_W - 1.5)
				var v := rng.randf_range(-CROWD_HALF_H + 1.5, CROWD_HALF_H - 1.5)
				var at2 := origin + right * u + down * v
				if at2.distance_to(origin) < 2.5: continue
				points.append([CROWD_KINDS[points.size() % CROWD_KINDS.size()], at2])
		_:
			return 0
	for entry in points:
		var kind: String = entry[0]
		# _spawn: the core's own body maker (the same hp / speed rules as the game's spawn, "zone 0, time 0" numbers).
		if not run._spawn(kind, entry[1]): continue
		var e: Dictionary = run.enemies[run._enemy_sequence]       # _enemy_sequence: the id of the body just made
		staged_ids[int(e.id)] = true
		if kind == "elite":
			# An "elite" body must not be a seal guardian (its death would open the gate and move the zone): it is made the way the
			# game makes a strong ordinary body (grade "elite", elite false; see _spawn_elite / _enemy_role).
			e.elite = false
			e.grade = "elite"
		if durable:
			e.hp_raw = DURABLE_HP_RAW
			e.max_hp_raw = DURABLE_HP_RAW
		if motion == "hold":
			e.staggered_until = HUGE         # the ring spell's stagger: the body neither moves nor attacks (read in _step_enemies)
		placed += 1
	staged_count = placed
	return placed
