extends SceneTree
## Power bench ("short proving ground", D12 P3 / P9): measures what a FIXED in-run spell build really does on the real core.
## No run is played to its end and no card is chosen: the build (spells, axis levels, crystal, evolution) is set in memory,
## the composition document is switched on in memory (the data file's "enabled" is never touched), the hero cannot die,
## experience is thrown away (no level-up, no choice screen), gear is hidden from the pilot (baseline, "--no-equip" state),
## and the pilot's MOVEMENT is exactly chapter_pilot.gd's. Nothing of the core is edited. Bot numbers are a stability and
## balance reference only; fun is NOT evaluated here.
##   crowd test   a fixed number of living ordinary enemies, refilled every tick from the beat's health and mix; the sum of
##                hit.dealt_raw over `--secs` (default 60) after a warm-up, divided by the seconds = P_crowd (HP/s).
##   single test  one huge-health guardian plus `n` ordinary enemies kept alive (n = 0, 10, 30), 30 s: P_single, how often the
##                nearest-first aim picks the guardian, how often a ring reaches it. Pilot movement, and a "stand" variant
##                (hero stays put, the guardian walks up to it) that shows the ceiling when a player fights at close range.
## Builds: --builds=name,name (presets, see --list) or --build=<spec or JSON> (one custom build). Spec = tokens joined by "+":
##   A:d2r1   own basic spell, damage axis 2, reach axis 1      R:d1r1  own ring      X:d1  borrowed basic (--borrow=, default
##   per witch)   AP / DT  the applier / the detonator of the witch's own pair      crystal  owns the basic's crystal      evo  A evolved
##   with its pair partner.   JSON: {"spells":{"A":{"d":2,"r":1},"R":{}}, "crystal":true, "evolve":true}
## --pretag=status:n (counterfactual) gives every ordinary enemy that status, n stacks, by the pair applier, before every step.
## --set=a/b/c=value overrides one value of the run_spells document in memory (path with "/", spell ids keep their dots), repeatable.
## Args: --witches=ember,frost,arc --beat=gi|seung1|seung2|jeon_a --hp=lo|mid|hi --density=15,35,60,85 --secs=60 --warmup=6
##   --seeds=11,12 --single-mobs=0,10,30 --single-secs=30 --single-modes=pilot,stand --no-crowd --no-single --out=_local/...json
## Last line: CHAPTER1_SIM_POWER_RESULT {...}. Writes only under _local/ (and only through --out); never reads or writes the user folder.
const Chapter = preload("res://chapter1/core/chapter_core.gd")
const Pilot = preload("res://chapter1/core/chapter_pilot.gd")
const RunSpells = preload("res://chapter1/core/run_spells.gd")
const SPELLS := "res://chapter1/data/run_spells.json"
const TUNING := "res://chapter1/data/combat_tuning.json"
const SK := "chapter1.skill."
const UNIT := 256
const FAR := 1 << 30
const HERO_HP := 2000000000
const ELITE_HP := 1 << 40
const WITCHES := ["ember", "frost", "arc"]
## The borrowed basic spell of each witch (D12 B0.10 "A": the first one of the other two, same as tools/dev/balance_sim.py).
const BORROW := {"ember": "frost", "frost": "ember", "arc": "ember"}
const BEATS := ["gi", "seung1", "seung2", "jeon_a"]
## Preset builds, in print order. Axis points are counted without the cards that unlock a spell or the crystal.
const PRESETS := [
	["base", "A"],
	["A_d4", "A:d4"], ["A_r4", "A:r4"], ["A_d2r2", "A:d2r2"],
	["AX_4", "A:d2r1+X:d1"], ["AR_4", "A:d1r1+R:d1r1"], ["AR_4fit", "AP:r2+DT:d2"], ["ARX_4", "A:d1r1+R:d1+X:d1"],
	["A_d3r3", "A:d3r3"], ["A_d4r2", "A:d4r2"], ["A_d2r4", "A:d2r4"],
	["AX_6", "A:d3r1+X:d1r1"], ["AR_6", "A:d2r1+R:d2r1"], ["AR_6fit", "AP:r3+DT:d2r1"], ["ARX_6", "A:d2r1+R:d1r1+X:d1"],
	["A_cap6c", "A:d4r2+crystal"], ["A_cap6X1", "A:d4r2+X:d1+crystal"], ["AR_evo7", "A:d3r2+R:d1r1+crystal+evo"],
	["R_d2r2", "R:d2r2"], ["R_d3r3", "R:d3r3"], ["AR_7", "A:d3r2+R:d1r1"],
]
var checks_failed: Array[String] = []
var doc_overrides: Array = []
var borrow_override := ""
var tuning_doc: Dictionary = {}
var started_ms := 0
## --pretag=heat:3 : before every step each ordinary enemy is given that status (count n) by the witch's pair applier. A counterfactual
## ("what if every enemy always carried the status"): it separates "the status is rarely there" from "the multiplier is small".
var pretag := {}

func _initialize() -> void:
	call_deferred("execute")

# ------------------------------------------------------------------ args

func arg_string(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with(name + "="): return String(arg).trim_prefix(name + "=")
	return fallback

func arg_flag(name: String) -> bool:
	return OS.get_cmdline_user_args().has(name)

func arg_ints(name: String, fallback: Array) -> Array:
	var raw := arg_string(name, "")
	if raw.is_empty(): return fallback
	var out: Array = []
	for part in raw.split(",", false): out.append(int(part))
	return out

func arg_names(name: String, fallback: Array) -> Array:
	var raw := arg_string(name, "")
	if raw.is_empty(): return fallback
	var out: Array = []
	for part in raw.split(",", false): out.append(String(part))
	return out

# ------------------------------------------------------------------ document and builds

func shipped_doc() -> Dictionary:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SPELLS))
	doc.enabled = true
	for entry in doc_overrides:
		if not set_path(doc, String(entry.path), entry.value): checks_failed.append("override path not found: " + String(entry.path))
	return doc

func set_path(doc: Variant, path: String, value: Variant) -> bool:
	var tokens: PackedStringArray = path.split("/", false)
	var cur: Variant = doc
	for i in tokens.size():
		var key: String = tokens[i]
		var last := i == tokens.size() - 1
		if cur is Dictionary:
			if not cur.has(key): return false
			if last: cur[key] = value
			else: cur = cur[key]
		elif cur is Array:
			if not key.is_valid_int() or int(key) < 0 or int(key) >= cur.size(): return false
			if last: cur[int(key)] = value
			else: cur = cur[int(key)]
		else: return false
	return true

func parse_axes(text: String) -> Dictionary:
	var d := 0
	var r := 0
	var i := 0
	while i < text.length():
		var c := text.substr(i, 1)
		if (c == "d" or c == "r") and i + 1 < text.length() and text.substr(i + 1, 1).is_valid_int():
			if c == "d": d = int(text.substr(i + 1, 1))
			else: r = int(text.substr(i + 1, 1))
			i += 2
		else: i += 1
	return {"damage": d, "reach": r}

## {spells: {key: {damage, reach}}, crystal, evolve, spec}. Keys are A, R, X, AP, DT, resolved per witch later.
func parse_spec(spec: String) -> Dictionary:
	var out := {"spells": {}, "crystal": false, "evolve": false, "spec": spec}
	if spec.begins_with("{"):
		var parsed: Variant = JSON.parse_string(spec)
		if not parsed is Dictionary: return {}
		for key in parsed.get("spells", {}):
			var axes: Dictionary = parsed.spells[key]
			out.spells[String(key)] = {"damage": int(axes.get("d", axes.get("damage", 0))), "reach": int(axes.get("r", axes.get("reach", 0)))}
		out.crystal = bool(parsed.get("crystal", false))
		out.evolve = bool(parsed.get("evolve", false))
		return out
	for token in spec.split("+", false):
		var tok := String(token).strip_edges()
		if tok == "crystal": out.crystal = true
		elif tok == "evo": out.evolve = true
		else:
			var key := tok.get_slice(":", 0)
			out.spells[key] = parse_axes(tok.get_slice(":", 1) if ":" in tok else "")
	return out

func spec_of_name(name: String) -> String:
	for entry in PRESETS:
		if entry[0] == name: return String(entry[1])
	return ""

## The witch's own pair: {applier, detonator, pair id} (pair "a" applies the status, "b" detonates it).
func own_pair(doc: Dictionary, witch: String) -> Dictionary:
	for pair in doc.pairs:
		if pair.kind == "detonate" and (String(pair.a) == SK + witch or String(pair.b) == SK + witch or String(pair.a) == SK + witch + "_ring" or String(pair.b) == SK + witch + "_ring"):
			return {"applier": String(pair.a), "detonator": String(pair.b), "id": String(pair.id)}
	return {}

func resolve_key(doc: Dictionary, witch: String, key: String) -> String:
	var borrow := borrow_override if not borrow_override.is_empty() else String(BORROW[witch])
	match key:
		"A": return SK + witch
		"R": return SK + witch + "_ring"
		"X": return SK + borrow
		"AP": return String(own_pair(doc, witch).applier)
		"DT": return String(own_pair(doc, witch).detonator)
	return ""

## Resolve a parsed build for one witch: {name, spells {id: {damage, reach}}, crystal_id, evolved, partner, legal, notes}.
func resolve_build(doc: Dictionary, witch: String, parsed: Dictionary, name: String) -> Dictionary:
	var out := {"name": name, "witch": witch, "spec": String(parsed.spec), "spells": {}, "crystal": bool(parsed.crystal), "evolved": "", "partner": "", "legal": true, "notes": []}
	out.spells[SK + witch] = {"damage": 0, "reach": 0}
	var cap_axis := int(doc.axis.cap_per_axis)
	var cap_spell := int(doc.axis.cap_per_spell)
	for key in parsed.spells:
		var id_ := resolve_key(doc, witch, String(key))
		if id_.is_empty():
			out.legal = false
			out.notes.append("unknown key " + String(key))
			continue
		var axes: Dictionary = parsed.spells[key]
		var d := int(axes.damage)
		var r := int(axes.reach)
		if d > cap_axis or r > cap_axis:
			out.legal = false
			out.notes.append("axis above cap_per_axis on " + id_)
			d = mini(d, cap_axis)
			r = mini(r, cap_axis)
		if d + r > cap_spell:
			out.legal = false
			out.notes.append("axis sum above cap_per_spell on " + id_)
		out.spells[id_] = {"damage": d, "reach": r}
	if out.spells.size() > int(doc.slots):
		out.legal = false
		out.notes.append("more spells than slots")
	if bool(parsed.evolve):
		var basic := SK + witch
		out.evolved = basic
		var partner := ""
		var ring := basic + "_ring"
		if out.spells.has(ring): partner = RunSpells.pair_between(doc, basic, ring)
		if partner.is_empty():
			for id_ in out.spells:
				if id_ != basic and partner.is_empty(): partner = RunSpells.pair_between(doc, basic, String(id_))
		out.partner = partner
		if partner.is_empty():
			out.legal = false
			out.notes.append("evo without a partner")
	return out

func axis_points(build: Dictionary) -> int:
	var sum := 0
	for id_ in build.spells: sum += int(build.spells[id_].damage) + int(build.spells[id_].reach)
	return sum

func apply_build(run: RefCounted, build: Dictionary) -> void:
	var g = run.growth
	for id_ in build.spells:
		g._ranks[id_] = 1
		g._axes[id_] = {"damage": int(build.spells[id_].damage), "reach": int(build.spells[id_].reach)}
	var basic: String = SK + String(build.witch)
	if bool(build.crystal) or not String(build.evolved).is_empty():
		var passive_id := String(g._skills[basic].passive_id)
		if not passive_id in g._owned_passives: g._owned_passives.append(passive_id)
	if not String(build.evolved).is_empty():
		build.evolve_legal = g._can_evolve(basic)
		g._evolved.append(basic)
		g._evolve_partner[basic] = String(build.partner)

# ------------------------------------------------------------------ arena

func beat_spec(id_: String) -> Dictionary:
	for beat in tuning_doc.rhythm.beats:
		if String(beat.id) == id_: return beat
	return {}

func hp_of(kind: String, beat: Dictionary, hp_mode: String) -> int:
	var ends: Array = beat.hp_bps
	var bps := int(ends[0]) if hp_mode == "lo" else (int(ends[1]) if hp_mode == "hi" else (int(ends[0]) + int(ends[1])) / 2)
	return maxi(1, int(tuning_doc.enemies[kind].hp[int(beat.zone)]) * bps / 10000)

func pick_kind(rng: RandomNumberGenerator, beat: Dictionary) -> String:
	var mix: Dictionary = beat.mix
	var roll := rng.randi_range(0, int(mix.walker) + int(mix.ranged) + int(mix.charger) - 1)
	if roll < int(mix.walker): return "walker"
	if roll < int(mix.walker) + int(mix.ranged): return "ranged"
	return "charger"

func make_run(seed_: int, primary: String, doc: Dictionary) -> RefCounted:
	var run = Chapter.new()
	if not run.set_run_spells(doc):
		push_error("sim_power: document refused: " + str(run.errors))
		checks_failed.append("document refused: " + str(run.errors))
		return null
	if not run.start(seed_, primary):
		push_error("sim_power: run did not start: " + str(run.errors))
		checks_failed.append("run did not start")
		return null
	run.first_boss_kill = true
	return run

## Keep exactly `target` ordinary enemies alive. Placement uses a private random stream, not the core's.
func fill(run: RefCounted, rng: RandomNumberGenerator, beat: Dictionary, hp_mode: String, target: int, has_elite: bool, initial: bool) -> void:
	var count: int = run.alive_count() - (1 if has_elite else 0)
	while count < target:
		var kind := pick_kind(rng, beat)
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(float(run.tuning.spawn.ring_min_m), float(run.tuning.spawn.ring_max_m))
		if initial: dist = sqrt(rng.randf_range(2.0 * 2.0, 10.5 * 10.5))
		var point: Vector2 = run._clamp_point(run.hero.position + Vector2(cos(angle), sin(angle)) * dist)
		if not run._spawn(kind, point): break
		var e: Dictionary = run.enemies[run._enemy_sequence]
		var hp := hp_of(kind, beat, hp_mode)
		e.hp_raw = hp * UNIT
		e.max_hp_raw = e.hp_raw
		e.definition.hp = hp
		count += 1

func place_elite(run: RefCounted) -> int:
	var angle := 0.8
	var point: Vector2 = run._clamp_point(run.hero.position + Vector2(cos(angle), sin(angle)) * 8.0)
	run._spawn("elite", point)
	var id_: int = run._enemy_sequence
	var e: Dictionary = run.enemies[id_]
	e.hp_raw = ELITE_HP * UNIT
	e.max_hp_raw = e.hp_raw
	return id_

## Before every step: the hero cannot die, gear is hidden, experience is thrown away, the seal stays shut, nothing spawns by itself.
func neutralize(run: RefCounted) -> void:
	run.hero.max_hp_raw = HERO_HP
	run.hero.hp_raw = HERO_HP
	run.inventory.clear()
	run.zone_kills = 0
	run.seals[0].kills = 0
	run._next_spawn = FAR
	if not run.growth._pending.is_empty():
		run.growth._pending.clear()
		run._refresh_mode()

func short(id_: Variant) -> String:
	return String(id_).trim_prefix(SK)

func new_acc() -> Dictionary:
	return {"spell": {}, "ring": {}, "kills": 0, "kills_by": {}, "hits": 0, "dealt": 0, "dmg": 0, "det_extra": 0, "det_extra_dealt": 0.0, "det_count": 0, "det_stacks": 0,
		"assist": 0, "elite_dealt": 0, "elite_hits": 0, "samples": 0, "alive": 0.0, "near25": 0.0, "near45": 0.0, "near90": 0.0, "status": {}, "aim": {}, "elite_dist": 0.0, "elite_ticks": 0,
		"elite_in_ring": {}, "ticks": 0}

func sp(acc: Dictionary, id_: String) -> Dictionary:
	if not acc.spell.has(id_): acc.spell[id_] = {"hits": 0, "dealt": 0, "dmg": 0, "casts": 0, "det_hits": 0, "kills": 0, "elite_hits": 0, "elite_dealt": 0, "assist": 0}
	return acc.spell[id_]

func ring_row(acc: Dictionary, id_: String) -> Dictionary:
	if not acc.ring.has(id_): acc.ring[id_] = {"casts": 0, "inside_pre": 0, "status_pre": 0, "others_pre": 0, "targets": 0, "hits": 0, "det_hits": 0, "ready_casts": 0}
	return acc.ring[id_]

## State of each ring that is ready to cast on the coming step: ordinary enemies inside, and how many of them carry the status
## the ring detonates (counted the way the core counts it: stacks put there by other spells, unexpired).
func ring_snapshots(run: RefCounted, ring_ids: Array) -> Dictionary:
	var out := {}
	for id_ in ring_ids:
		if int(run._next_cast.get(id_, 0)) > run.tick + 1: continue
		var effect: Dictionary = run.effective_skill(id_).effects
		var radius := float(effect.ring_radius_cm) / 100.0
		var statuses: Array = run.spells.spells[id_].detonates.keys()
		var row := {"inside": 0, "with_status": 0, "others": 0}
		for e in run.enemies.values():
			if e.hp_raw <= 0 or e.position.distance_squared_to(run.hero.position) > radius * radius: continue
			row.inside += 1
			for status in statuses:
				var entry: Variant = e.get("status", {}).get(status)
				if not entry is Dictionary or int(entry.n) <= 0 or run.tick + 1 >= int(entry.until): continue
				var others := int(entry.n) - int(entry.by.get(id_, 0))
				if others > 0:
					row.with_status += 1
					row.others += others
					break
		out[id_] = row
	return out

func collect(run: RefCounted, acc: Dictionary, pre: Dictionary, elite_id: int, ring_radius: Dictionary) -> void:
	var current_ring := ""
	var last_hit: Dictionary = {}
	for ev in run.events:
		match String(ev.type):
			"cast":
				var id_ := short(ev.skill_id)
				var row := sp(acc, id_)
				row.casts += 1
				if String(ev.get("shape", "")) == "ring":
					current_ring = String(ev.skill_id)
					var r := ring_row(acc, id_)
					r.casts += 1
					r.targets += (ev.targets as Array).size()
					if pre.has(ev.skill_id):
						r.ready_casts += 1
						r.inside_pre += int(pre[ev.skill_id].inside)
						r.status_pre += int(pre[ev.skill_id].with_status)
						r.others_pre += int(pre[ev.skill_id].others)
				else:
					current_ring = ""
					if elite_id >= 0 and run.enemies.has(elite_id):
						var best := 13.0 * 13.0
						var nearest := -1
						for e in run.enemies.values():
							if e.hp_raw <= 0: continue
							var d2: float = e.position.distance_squared_to(run.hero.position)
							if d2 < best: best = d2; nearest = int(e.id)
						var aim: Dictionary = acc.aim.get(id_, {"casts": 0, "elite_nearest": 0, "none_in_range": 0})
						aim.casts += 1
						if nearest == elite_id: aim.elite_nearest += 1
						if nearest < 0: aim.none_in_range += 1
						acc.aim[id_] = aim
			"hit":
				var id_ := short(ev.skill_id)
				var row := sp(acc, id_)
				var dealt := int(ev.dealt_raw)
				var dmg := int(ev.damage_raw)
				row.hits += 1
				row.dealt += dealt
				row.dmg += dmg
				acc.hits += 1
				acc.dealt += dealt
				acc.dmg += dmg
				var assist := int(ev.get("assist_raw", 0))
				row.assist += assist
				acc.assist += assist
				last_hit = {"dealt": dealt, "dmg": dmg}
				if bool(ev.get("detonate", false)): row.det_hits += 1
				if int(ev.target_id) == elite_id:
					row.elite_hits += 1
					row.elite_dealt += dealt
					acc.elite_hits += 1
					acc.elite_dealt += dealt
				if not current_ring.is_empty() and current_ring == String(ev.skill_id):
					var r := ring_row(acc, id_)
					r.hits += 1
					if bool(ev.get("detonate", false)): r.det_hits += 1
			"detonate":
				acc.det_count += 1
				acc.det_extra += int(ev.extra_raw)
				acc.det_stacks += int(ev.stacks)
				if not last_hit.is_empty() and int(last_hit.dmg) > 0: acc.det_extra_dealt += float(last_hit.dealt) * float(ev.extra_raw) / float(last_hit.dmg)
			"death":
				acc.kills += 1
				var id_ := short(ev.skill_id)
				acc.kills_by[id_] = int(acc.kills_by.get(id_, 0)) + 1
				sp(acc, id_).kills += 1
	acc.ticks += 1
	if elite_id >= 0 and run.enemies.has(elite_id):
		var d: float = run.enemies[elite_id].position.distance_to(run.hero.position)
		acc.elite_dist += d
		acc.elite_ticks += 1
		for id_ in ring_radius:
			if d <= float(ring_radius[id_]): acc.elite_in_ring[id_] = int(acc.elite_in_ring.get(id_, 0)) + 1
	if run.tick % 6 == 0:
		acc.samples += 1
		var alive := 0
		var n25 := 0
		var n45 := 0
		var n90 := 0
		var holders := {}
		var stacks := {}
		for e in run.enemies.values():
			if e.hp_raw <= 0 or bool(e.elite): continue
			alive += 1
			var d2: float = e.position.distance_squared_to(run.hero.position)
			if d2 <= 2.5 * 2.5: n25 += 1
			if d2 <= 4.5 * 4.5: n45 += 1
			if d2 <= 9.0 * 9.0: n90 += 1
			for status in e.get("status", {}):
				var entry: Dictionary = e.status[status]
				if int(entry.n) > 0 and run.tick < int(entry.until):
					holders[status] = int(holders.get(status, 0)) + 1
					stacks[status] = int(stacks.get(status, 0)) + int(entry.n)
		acc.alive += alive
		acc.near25 += n25
		acc.near45 += n45
		acc.near90 += n90
		for status in holders:
			var row: Dictionary = acc.status.get(status, {"holders": 0, "stacks": 0})
			row.holders += holders[status]
			row.stacks += stacks[status]
			acc.status[status] = row

func r2(x: float) -> float:
	return snappedf(x, 0.01)

func r1(x: float) -> float:
	return snappedf(x, 0.1)

## Turn an accumulator into the plain numbers a table reads.
func finish(acc: Dictionary, secs: float, run: RefCounted, build: Dictionary, label: String) -> Dictionary:
	var out := {"kind": label, "secs": secs, "power_hp_s": r2(float(acc.dealt) / UNIT / secs), "dmg_hp_s": r2(float(acc.dmg) / UNIT / secs),
		"kills": acc.kills, "kills_per_s": r2(float(acc.kills) / secs), "hits": acc.hits, "hits_per_kill": r2(float(acc.hits) / maxf(1.0, float(acc.kills))),
		"overkill_pct": r1(100.0 * float(acc.dmg - acc.dealt) / maxf(1.0, float(acc.dmg))),
		"det_count": acc.det_count, "det_per_s": r2(float(acc.det_count) / secs), "det_extra_hp_s": r2(float(acc.det_extra) / UNIT / secs),
		"det_share_dmg_pct": r1(100.0 * float(acc.det_extra) / maxf(1.0, float(acc.dmg))), "det_share_dealt_pct": r1(100.0 * float(acc.det_extra_dealt) / maxf(1.0, float(acc.dealt))),
		"det_mean_stacks": r2(float(acc.det_stacks) / maxf(1.0, float(acc.det_count))), "assist_share_dealt_pct": r1(100.0 * float(acc.assist) / maxf(1.0, float(acc.dealt))),
		"spells": {}, "rings": {}, "status": {}, "effects": {}}
	var samples := maxf(1.0, float(acc.samples))
	out.alive_mean = r1(float(acc.alive) / samples)
	out.within_2_5m = r1(float(acc.near25) / samples)
	out.within_4_5m = r1(float(acc.near45) / samples)
	out.within_9m = r1(float(acc.near90) / samples)
	for id_ in acc.spell:
		var s: Dictionary = acc.spell[id_]
		var casts := maxi(1, int(s.casts))
		out.spells[id_] = {"dps_hp": r2(float(s.dealt) / UNIT / secs), "share_pct": r1(100.0 * float(s.dealt) / maxf(1.0, float(acc.dealt))), "casts": s.casts, "hits": s.hits,
			"hits_per_cast": r2(float(s.hits) / casts), "det_hit_pct": r1(100.0 * float(s.det_hits) / maxf(1.0, float(s.hits))), "kills": s.kills,
			"overkill_pct": r1(100.0 * float(s.dmg - s.dealt) / maxf(1.0, float(s.dmg))), "casts_per_s": r2(float(s.casts) / secs),
			"killing_hit_pct": r1(100.0 * float(s.kills) / maxf(1.0, float(s.hits))),
			"elite_dps_hp": r2(float(s.elite_dealt) / UNIT / secs), "elite_hits": s.elite_hits, "elite_hits_per_cast": r2(float(s.elite_hits) / casts)}
	for id_ in acc.ring:
		var r: Dictionary = acc.ring[id_]
		var c := maxf(1.0, float(r.ready_casts))
		out.rings[id_] = {"casts": r.casts, "inside_mean": r1(float(r.inside_pre) / c), "targets_mean": r1(float(r.targets) / maxf(1.0, float(r.casts))), "hits_mean": r1(float(r.hits) / maxf(1.0, float(r.casts))),
			"with_status_mean": r2(float(r.status_pre) / c), "with_status_pct": r1(100.0 * float(r.status_pre) / maxf(1.0, float(r.inside_pre))),
			"others_stacks_per_carrier": r2(float(r.others_pre) / maxf(1.0, float(r.status_pre))), "detonated_hits_mean": r2(float(r.det_hits) / maxf(1.0, float(r.casts)))}
	for status in acc.status:
		var row: Dictionary = acc.status[status]
		out.status[status] = {"holders_mean": r2(float(row.holders) / samples), "holders_pct_of_alive": r1(100.0 * float(row.holders) / maxf(1.0, float(acc.alive))), "stacks_per_holder": r2(float(row.stacks) / maxf(1.0, float(row.holders)))}
	for id_ in acc.aim:
		var a: Dictionary = acc.aim[id_]
		out.spells[id_].aim_elite_nearest_pct = r1(100.0 * float(a.elite_nearest) / maxf(1.0, float(a.casts)))
	if int(acc.elite_ticks) > 0:
		out.elite_dist_mean = r2(float(acc.elite_dist) / float(acc.elite_ticks))
		out.elite_dps_hp = r2(float(acc.elite_dealt) / UNIT / secs)
		for id_ in acc.elite_in_ring: out.rings[short(id_)].elite_inside_pct = r1(100.0 * float(acc.elite_in_ring[id_]) / float(acc.elite_ticks))
	for id_ in build.spells: out.effects[short(id_)] = run.effective_skill(id_).effects
	return out

func apply_pretag(run: RefCounted, pair: Dictionary) -> void:
	var status := String(pretag.status)
	if pair.is_empty() or not run.spells.statuses.has(status): return
	var src := String(pair.applier)
	var n := mini(int(pretag.n), int(run.spells.statuses[status].max))
	var until: int = run.tick + 1 + int(run.spells.statuses[status].expire_ticks)
	for e in run.enemies.values():
		if e.hp_raw <= 0 or bool(e.elite): continue
		if not e.has("status"): e.status = {}
		e.status[status] = {"n": n, "src": src, "until": until, "by": {src: n}}

## One arena: `mobs` ordinary enemies refilled to a constant number (+ one guardian when `elite`), `secs` measured after a warm-up.
func arena(witch: String, build: Dictionary, mobs: int, elite: bool, stand: bool, secs: float, seed_: int, beat: Dictionary, hp_mode: String, warmup_s: float, label: String) -> Dictionary:
	var primary := SK + witch
	var run := make_run(seed_, primary, shipped_doc())
	if run == null: return {}
	apply_build(run, build)
	run.enemies.clear()
	run._alive = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_ * 7919 + 13
	var pilot = Pilot.new()
	pilot.run = run
	neutralize(run)
	fill(run, rng, beat, hp_mode, mobs, false, true)
	var elite_id := place_elite(run) if elite else -1
	var rings: Array = []
	var ring_radius := {}
	for id_ in build.spells:
		if String(run.spells.spells[id_].role) == "ring":
			rings.append(id_)
			ring_radius[id_] = float(run.effective_skill(id_).effects.ring_radius_cm) / 100.0
	var warm := int(warmup_s * 60.0)
	var total := warm + int(secs * 60.0)
	var acc := new_acc()
	var aborted := false
	for i in total:
		neutralize(run)
		if run.mode != "playing":
			aborted = true
			break
		fill(run, rng, beat, hp_mode, mobs, elite, false)
		if not pretag.is_empty(): apply_pretag(run, own_pair(run.spells, witch))
		var pre := ring_snapshots(run, rings) if i >= warm else {}
		var move := Vector2.ZERO if stand else pilot.decide()
		run.step(move)
		if i >= warm: collect(run, acc, pre, elite_id, ring_radius)
	var out := finish(acc, secs, run, build, label)
	out.aborted = aborted
	out.events_dropped = int(run.metrics.get("events_dropped", 0))
	return out

# ------------------------------------------------------------------ output

func mean_of(cells: Array, getter: Callable) -> float:
	if cells.is_empty(): return 0.0
	var sum := 0.0
	for cell in cells: sum += float(getter.call(cell))
	return sum / float(cells.size())

func print_tables(results: Array, witches: Array, build_names: Array, densities: Array, single_mobs: Array, single_modes: Array) -> void:
	for witch in witches:
		print("")
		print("== witch %s : crowd P (HP/s, mean over seeds) by density, detonation share of dealt (%%), and single P (HP/s) ==" % witch)
		var head := "%-10s %3s" % ["build", "pts"]
		for d in densities: head += " %7s" % ("N" + str(d))
		head += " | det%%@N%d" % int(densities[densities.size() - 1]) if not densities.is_empty() else ""
		for mode in single_modes:
			for n in single_mobs: head += " %9s" % ("%s+%d" % [String(mode).substr(0, 2), n])
		print(head)
		for name in build_names:
			var line := ""
			var pts := -1
			for d in densities:
				var cells: Array = results.filter(func(r): return r.witch == witch and r.build == name and r.test == "crowd" and int(r.density) == int(d))
				if pts < 0 and not cells.is_empty(): pts = int(cells[0].points)
				if line.is_empty(): line = "%-10s %3d" % [name, maxi(pts, 0)]
				line += " %7.1f" % mean_of(cells, func(c): return c.power_hp_s) if not cells.is_empty() else " %7s" % "-"
			if line.is_empty(): line = "%-10s %3s" % [name, "?"]
			if not densities.is_empty():
				var last: Array = results.filter(func(r): return r.witch == witch and r.build == name and r.test == "crowd" and int(r.density) == int(densities[densities.size() - 1]))
				line += " | %6.1f" % mean_of(last, func(c): return c.det_share_dealt_pct) if not last.is_empty() else " | %6s" % "-"
			for mode in single_modes:
				for n in single_mobs:
					var cells: Array = results.filter(func(r): return r.witch == witch and r.build == name and r.test == "single" and String(r.mode) == String(mode) and int(r.mobs) == int(n))
					line += " %9.1f" % mean_of(cells, func(c): return c.elite_dps_hp) if not cells.is_empty() else " %9s" % "-"
			print(line)

func execute() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/_local/appdata/"):
		print("CHAPTER1_SIM_POWER_RESULT ", JSON.stringify({"error": "user data dir is not isolated: refusing to run"}))
		quit(1)
		return
	started_ms = Time.get_ticks_msec()
	if arg_flag("--list"):
		for entry in PRESETS: print("%-10s %s" % [entry[0], entry[1]])
		print("CHAPTER1_SIM_POWER_RESULT ", JSON.stringify({"list": PRESETS.size()}))
		quit(0)
		return
	tuning_doc = JSON.parse_string(FileAccess.get_file_as_string(TUNING))
	borrow_override = arg_string("--borrow", "")
	for raw in OS.get_cmdline_user_args():
		if String(raw).begins_with("--set="):
			var text := String(raw).trim_prefix("--set=")
			var path := text.get_slice("=", 0)
			var parsed: Variant = JSON.parse_string(text.substr(path.length() + 1))
			doc_overrides.append({"path": path, "value": parsed if parsed != null else text.substr(path.length() + 1)})
	var pretag_text := arg_string("--pretag", "")
	if not pretag_text.is_empty(): pretag = {"status": pretag_text.get_slice(":", 0), "n": int(pretag_text.get_slice(":", 1))}
	var out_path := arg_string("--out", "")
	if not out_path.is_empty() and (not out_path.begins_with("_local/") or out_path.contains("..") or out_path.contains(":") or out_path.begins_with("/")):
		push_error("sim_power: --out must be a relative path under _local/ (got %s)" % out_path)
		print("CHAPTER1_SIM_POWER_RESULT ", JSON.stringify({"error": "--out outside _local"}))
		quit(1)
		return
	var witches := arg_names("--witches", WITCHES)
	var seeds := arg_ints("--seeds", [11])
	var densities := arg_ints("--density", [15, 35, 60, 85])
	var single_mobs := arg_ints("--single-mobs", [0, 10, 30])
	var single_modes := arg_names("--single-modes", ["pilot", "stand"])
	var secs := float(arg_string("--secs", "60"))
	var single_secs := float(arg_string("--single-secs", "30"))
	var warmup := float(arg_string("--warmup", "6"))
	var hp_mode := arg_string("--hp", "mid")
	var beat_id := arg_string("--beat", "seung2")
	var beat := beat_spec(beat_id)
	if beat.is_empty():
		print("CHAPTER1_SIM_POWER_RESULT ", JSON.stringify({"error": "unknown beat " + beat_id}))
		quit(1)
		return
	var named: Array = []
	var custom := arg_string("--build", "")
	if not custom.is_empty(): named.append(["custom", custom])
	var wanted := arg_names("--builds", [])
	if custom.is_empty() and (wanted.is_empty() or wanted == ["all"]):
		for entry in PRESETS: named.append([entry[0], entry[1]])
	else:
		for name in wanted:
			if name == "all": continue
			var spec := spec_of_name(String(name))
			if spec.is_empty():
				print("CHAPTER1_SIM_POWER_RESULT ", JSON.stringify({"error": "unknown build " + String(name)}))
				quit(1)
				return
			named.append([name, spec])
	var results: Array = []
	var build_names: Array = []
	for entry in named: build_names.append(String(entry[0]))
	var doc := shipped_doc()
	var cells_done := 0
	for witch in witches:
		for entry in named:
			var parsed_spec := parse_spec(String(entry[1]))
			if parsed_spec.is_empty():
				checks_failed.append("bad spec " + String(entry[1]))
				continue
			for seed_ in seeds:
				var build := resolve_build(doc, String(witch), parsed_spec, String(entry[0]))
				if not arg_flag("--no-crowd"):
					for density in densities:
						var t0 := Time.get_ticks_msec()
						var cell := arena(String(witch), build, int(density), false, false, secs, int(seed_), beat, hp_mode, warmup, "crowd")
						if cell.is_empty(): continue
						cell.merge({"test": "crowd", "witch": witch, "build": entry[0], "spec": entry[1], "seed": seed_, "density": density, "beat": beat_id, "points": axis_points(build), "legal": build.legal, "notes": build.notes,
							"evolve_legal": build.get("evolve_legal", null), "wall_s": r1(float(Time.get_ticks_msec() - t0) / 1000.0)})
						results.append(cell)
						cells_done += 1
						print("CELL crowd %-5s %-10s N=%-3d seed=%d P=%8.1f det=%5.1f%% kills/s=%5.2f hits/kill=%5.2f wall=%.1fs" % [witch, entry[0], density, seed_, cell.power_hp_s, cell.det_share_dealt_pct, cell.kills_per_s, cell.hits_per_kill, cell.wall_s])
				if not arg_flag("--no-single"):
					for mode in single_modes:
						for mobs in single_mobs:
							var t0 := Time.get_ticks_msec()
							var cell := arena(String(witch), build, int(mobs), true, String(mode) == "stand", single_secs, int(seed_), beat, hp_mode, 3.0, "single")
							if cell.is_empty(): continue
							cell.merge({"test": "single", "witch": witch, "build": entry[0], "spec": entry[1], "seed": seed_, "mobs": mobs, "mode": mode, "beat": beat_id, "points": axis_points(build), "legal": build.legal, "notes": build.notes,
								"wall_s": r1(float(Time.get_ticks_msec() - t0) / 1000.0)})
							results.append(cell)
							cells_done += 1
							print("CELL single %-5s %-10s mobs=%-2d %-5s seed=%d P_elite=%7.1f elite_dist=%5.2f wall=%.1fs" % [witch, entry[0], mobs, mode, seed_, cell.get("elite_dps_hp", 0.0), cell.get("elite_dist_mean", 0.0), cell.wall_s])
	print_tables(results, witches, build_names, densities if not arg_flag("--no-crowd") else [], single_mobs if not arg_flag("--no-single") else [], single_modes if not arg_flag("--no-single") else [])
	var elapsed := r1(float(Time.get_ticks_msec() - started_ms) / 1000.0)
	var meta := {"beat": beat_id, "hp_mode": hp_mode, "beat_hp_bps": beat.hp_bps, "beat_mix": beat.mix, "beat_zone": beat.zone, "secs": secs, "single_secs": single_secs, "warmup_s": warmup, "seeds": seeds, "witches": witches,
		"densities": densities, "single_mobs": single_mobs, "single_modes": single_modes, "overrides": doc_overrides, "borrow": borrow_override, "pretag": pretag, "elapsed_s": elapsed,
		"setup": "build fixed in memory; document enabled in memory; hero cannot die; xp discarded; gear hidden (no-equip); pilot movement unchanged; bot numbers are a reference only, fun not evaluated"}
	if not out_path.is_empty():
		var abs_path := ProjectSettings.globalize_path("res://" + out_path)
		DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
		var f := FileAccess.open(abs_path, FileAccess.WRITE)
		if f == null:
			push_error("sim_power: cannot write %s" % abs_path)
			print("CHAPTER1_SIM_POWER_RESULT ", JSON.stringify({"error": "cannot write out"}))
			quit(3)
			return
		f.store_string(JSON.stringify({"meta": meta, "cells": results}, "\t"))
		f.close()
	print("CHAPTER1_SIM_POWER_RESULT ", JSON.stringify({"cells": cells_done, "builds": build_names, "witches": witches, "beat": beat_id, "elapsed_s": elapsed, "out": out_path, "problems": checks_failed}))
	quit(0 if checks_failed.is_empty() else 1)
