extends RefCounted
## QA support (never product code): FAKE descent events in the shape of D24 9.4 (and of the core patch that implements it), so the
## presenter (view/fx/descent_fx.gd) can be drawn and tested without a run. Nothing here touches a core. The schedule follows the spec
## (5.2 / 6.2 / 7.2): 14 fragments with land steps 30..126, frost onset 18 / pulses 30+15n x8 / break 150, 40 bolts steps 4..114 / finale 120.
## The numbers come from a small integer hash (D24 4.6's lowbias32), not from the engine's random, so a picture can be taken again.
## Usage: var fake := Fake.new(element, seed, enemy_positions); events = fake.release(center, tick); then events += fake.step(s) for s = 1..N.

const SWEEP_TICKS := {"ember": 132, "frost": 150, "arc": 120}
const AREA := {"right_deg": -38.2, "half_w_m": 17.3, "half_h_m": 13.4}
const EDGE := 1.0

var element := "ember"
var seed_ := 11
var enemies := PackedVector2Array()
var center := Vector2.ZERO
var tick0 := 0
var seq := 100000
var _dead := {}
var _frags: Array[Dictionary] = []
var _bolts: Array[Dictionary] = []
var _frozen: Array[int] = []

func _init(element_: String, seed__: int, enemy_positions: PackedVector2Array) -> void:
	element = element_
	seed_ = seed__
	enemies = enemy_positions

static func mix32(x: int) -> int:
	x &= 0xffffffff
	x ^= x >> 16
	x = (x * 0x7feb352d) & 0xffffffff
	x ^= x >> 15
	x = (x * 0x846ca68b) & 0xffffffff
	x ^= x >> 16
	return x

func h(use: int, k: int, salt: int) -> float:
	var x := mix32(seed_ ^ 0x5bd1e995)
	x = mix32(x ^ (use * 0x9e3779b1 & 0xffffffff))
	x = mix32(x ^ (k * 0x85ebca6b & 0xffffffff))
	x = mix32(x ^ (salt * 0xc2b2ae35 & 0xffffffff))
	return float(x) / 4294967296.0

func in_area(point: Vector2, c: Vector2, margin: float = EDGE) -> bool:
	var rad := deg_to_rad(float(AREA.right_deg))
	var right := Vector2(cos(rad), sin(rad))
	var down := right.rotated(PI * 0.5)
	var d := point - c
	return absf(d.dot(right)) <= float(AREA.half_w_m) + margin and absf(d.dot(down)) <= float(AREA.half_h_m) + margin

func _event(type_: String, at: Vector2, tick_: int, fields: Dictionary) -> Dictionary:
	seq += 1
	var e := fields.duplicate(true)
	e["type"] = type_
	e["position"] = at
	e["tick"] = tick_
	e["seq"] = seq
	return e

func _inside() -> Array[int]:
	var out: Array[int] = []
	for i in enemies.size():
		if in_area(enemies[i], center): out.append(i)
	return out

## descent_released (+ descent_book for ember). The sweep's first tick is s = 1.
func release(center_: Vector2, tick_: int) -> Array:
	center = center_
	tick0 = tick_
	_dead.clear()
	var events: Array = []
	events.append(_event("descent_released", center, tick_, {"element": element, "center": center, "area": AREA.duplicate(), "sweep_ticks": int(SWEEP_TICKS[element]),
		"cleared_shots": 0, "cleared_positions": []}))
	if element == "ember": events.append(_event("descent_book", center, tick_, {"element": "ember", "fragments": _book()}))
	if element == "arc": _plan_bolts()
	return events

func _cell_center(cx: int, cy: int) -> Vector2:
	var rad := deg_to_rad(float(AREA.right_deg))
	var right := Vector2(cos(rad), sin(rad))
	var down := right.rotated(PI * 0.5)
	var w := (float(AREA.half_w_m) * 2.0) / 4.0
	var hh := (float(AREA.half_h_m) * 2.0) / 3.0
	var u := -float(AREA.half_w_m) + (float(cx) + 0.2 + 0.6 * h(1, cx + cy * 4, 1)) * w
	var v := -float(AREA.half_h_m) + (float(cy) + 0.2 + 0.6 * h(1, cx + cy * 4, 2)) * hh
	return center + right * u + down * v

func _book() -> Array:
	_frags.clear()
	var spots: Array[Vector2] = []
	for cy in 3:
		for cx in 4: spots.append(_cell_center(cx, cy))
	# two aimed at the strongest bodies (here: the two enemies farthest to the screen's lower right, a stand-in for "boss, guardian")
	var inside := _inside()
	var aimed: Array[int] = []
	for n in 2:
		if inside.size() > n: aimed.append(inside[(n * 7) % inside.size()])
	for n in aimed.size(): spots.append(enemies[aimed[n]])
	while spots.size() < 14: spots.append(center)
	# order: shuffled by the hash, the two aimed ones first and seventh
	var order: Array[int] = []
	for i in 14: order.append(i)
	order.sort_custom(func(a, b): return h(2, a, 0) < h(2, b, 0))
	var out: Array = []
	var step := 30
	var big_picked := 0
	var plan: Array[int] = []
	for i in 14:
		if i == 0: plan.append(12)
		elif i == 6: plan.append(13)
		else:
			for o in order:
				if o < 12 and not plan.has(o):
					plan.append(o)
					break
	for k in 14:
		var spot_index := plan[k]
		var big := spot_index >= 12 or (big_picked < 3 and h(3, k, 0) > 0.7 and k > 0)
		if big and spot_index < 12: big_picked += 1
		var f := {"k": k, "pos": spots[spot_index], "land_step": mini(step, 126), "radius_m": 4.5 if big else 3.0, "big": big, "aimed_id": aimed[spot_index - 12] if spot_index >= 12 and aimed.size() > spot_index - 12 else 0}
		out.append(f)
		_frags.append(f)
		step += 4 + int(h(4, k, 0) * 5.0)
	return out

func _plan_bolts() -> void:
	_bolts.clear()
	var s := 4
	var rad := deg_to_rad(float(AREA.right_deg))
	var right := Vector2(cos(rad), sin(rad))
	var down := right.rotated(PI * 0.5)
	var placed: Array[Vector2] = []
	for k in 40:
		var at := center
		for attempt in 5:
			var u := (h(5, k, attempt * 2) * 2.0 - 1.0) * float(AREA.half_w_m)
			var v := (h(5, k, attempt * 2 + 1) * 2.0 - 1.0) * float(AREA.half_h_m)
			at = center + right * u + down * v
			var ok := true
			for q in placed.slice(maxi(0, placed.size() - 3)):
				if q.distance_to(at) < 5.0: ok = false
			if ok: break
		placed.append(at)
		_bolts.append({"k": k, "step": mini(s, 114), "pos": at, "burst": false})
		s += int(h(6, k, 0) * 6.0)
	# the ones that share a tick with their neighbour are the burst
	for i in _bolts.size():
		if (i > 0 and _bolts[i].step == _bolts[i - 1].step) or (i + 1 < _bolts.size() and _bolts[i].step == _bolts[i + 1].step): _bolts[i].burst = true

func _near(at: Vector2, limit: float, skip_dead: bool) -> int:
	var best := -1
	var best_d := limit
	for i in enemies.size():
		if skip_dead and _dead.has(i): continue
		var d := enemies[i].distance_to(at)
		if d <= best_d:
			best_d = d
			best = i
	return best

func _within(at: Vector2, radius: float) -> Array[int]:
	var out: Array[int] = []
	for i in enemies.size():
		if not _dead.has(i) and enemies[i].distance_to(at) <= radius: out.append(i)
	return out

func _common(phase: String, s: int, ids: Array, extra: Dictionary) -> Dictionary:
	var positions: Array = []
	var targets: Array = []
	for i in ids:
		_dead[i] = true
		if positions.size() < 64:
			positions.append(enemies[i])
			targets.append(1000 + int(i))
	var fields := {"element": element, "phase": phase, "step": s, "center": center, "positions": positions, "target_ids": targets, "marks_at": []}
	fields.merge(extra)
	return fields

## The events of sweep step s (call for s = 1 .. sweep_ticks, in order).
func step(s: int) -> Array:
	var tick_ := tick0 + s
	var events: Array = []
	match element:
		"ember":
			for f in _frags:
				if int(f.land_step) == s:
					events.append(_event("descent_strike", f.pos, tick_, _common("impact", s, _within(f.pos, float(f.radius_m)), {"k": f.k, "pos": f.pos, "radius_m": f.radius_m, "big": f.big})))
			if s == 132:
				events.append(_event("descent_strike", center, tick_, _common("firestorm", s, _inside(), {})))
		"frost":
			if s == 18:
				var ids: Array = _inside()
				_frozen.assign(ids)
				var fields := _common("onset", s, ids, {})
				_dead.clear()
				events.append(_event("descent_strike", center, tick_, fields))
			if s >= 30 and (s - 30) % 15 == 0 and (s - 30) / 15 < 8:
				var n := (s - 30) / 15 + 1
				events.append(_event("descent_strike", center, tick_, {"element": element, "phase": "pulse", "step": s, "center": center, "positions": [], "target_ids": [], "marks_at": [], "n": n, "frozen_count": _frozen.size()}))
			if s == 150:
				events.append(_event("descent_strike", center, tick_, _common("break", s, _frozen, {})))
		"arc":
			for b in _bolts:
				if int(b.step) != s: continue
				var at: Vector2 = b.pos
				var snap := _near(at, 3.5, true)
				if snap >= 0: at = enemies[snap]
				var hit := _within(at, 1.6)
				var forks: Array = []
				for i in _within(at, 5.0):
					if forks.size() >= 3: break
					if not hit.has(i): forks.append([at, enemies[i]])
				events.append(_event("descent_strike", at, tick_, _common("bolt", s, hit, {"k": b.k, "pos": at, "forks": forks, "burst": b.burst})))
			if s == 120:
				events.append(_event("descent_strike", center, tick_, _common("finale", s, _inside(), {})))
	if s == int(SWEEP_TICKS[element]):
		events.append(_event("descent_end", center, tick_, {"element": element, "kills": _dead.size(), "strong_hits": 0, "strong_damage_raw": 0, "boss_share_bps": 0, "duration_ticks": s}))
	return events
