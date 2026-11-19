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
## D12 rev.3 / B0.16 (phase 0) switches: --crowd-modes=pilot,stand (T-1; the crowd cell also in stand), --tally (T-2/T-3: the hero keeps its REAL max life (--hero-hp=N to change), zone damage/speed
##   for the enemies; per cell taken_pct_total / hero_hits / dead_np_s / dead_p_s, contact_share_pct = share of ticks with an ordinary enemy within 1.15 m, preps_close = windups that START within
##   1.15 m, preps_close_hit = how many of those hit), --mix=walker:ranged:charger (T-4), --elite-hp=HP|g1 (T-5; g1 = champion 0 hp x the beat's mean hp multiplier; the single cell ends when it dies:
##   kill_s). --set may create a missing last key (listed in meta.created_keys) and arrays take whole JSON values (reach=[...]) or indexes (reach/1/ring_radius_cm=200).
## CONTACT MODES (D12 rev. 3, "the ring is a wall, not a pair part"): --mode=melee,hold,strong (default: none = the crowd + single tests above, unchanged).
##   Here the hero keeps its REAL maximum life (the baseline hero: 120, no gear, no level) and is topped up every tick, so it cannot die, but every
##   hero_hit is counted and a shadow life is run beside it: shadow life without potions and with the 3 starting potions (drunk under 68 %, 35 %, 240 tick
##   cooldown, like the pilot) -> the second the shadow life would have hit 0 ("dead_np_s" / "dead_p_s", -1 = survived). Enemy damage and speed are those of the
##   beat's zone (the crowd test leaves them at zone 0). Counted per measured second: taken damage (% of max life), hits, mean number of ordinary enemies within
##   1.5 / 3 / 5 m (sampled at 10 Hz), the share of samples with at least one enemy within 1.5 m, enemy-seconds within 1.5 m, and how many of those are not frozen/stunned.
##   melee   density N alive ordinary enemies (--m-density, default 35,70), --m-secs 45. Variants (--melee-variants): stand = hero does not move; pilot = pilot
##           movement; rush = pilot movement, enemy speed x --rush-mult (2.5) and enemies (re)spawn at --rush-ring-min/max (3-5 m) instead of 7.5-10.5 m (they appear close, so the hero is boxed in).  (default stand,rush)
##   hold    the hero is kept inside a 12 m circle around its start (the D11 "버티기"), density --hold-density 70,100, --hold-secs 45, trial rule (zone 2 life/damage, trial
##           mix). Variants --hold-variants (default stand,pilot).
##   strong  one champion of the beat's zone (--champion=N overrides; real hp/damage/windup from combat_tuning champions) placed next to the hero, plus --strong-mobs (0,10,30)
##           ordinary enemies; ends when it dies or after --strong-secs (90): time to kill and damage taken. Variants --strong-variants (default stand,pilot).
##   --hero-hp=N sets the hero's maximum life in HP (default: the real baseline 120; a stand-in for levels/gear, which the bench does not have).
##   Ring knobs, applied in memory to the witch's OWN ring spell (all optional, any mode): --ring-radius=M (flat radius, all reach levels), --ring-cd=SECONDS, --ring-dmg=MULT,
##   --ring-vs-strong=MULT (0.5 = shipped), --ring-pulses=N (24-tick pulses), --ring-targets=N, --ring-budget=N, --ring-slow=BPS[,TICKS] (the core applies slow only to frost-element
##   spells, only the frost witch's ring takes it; on the other two it is reported in meta.knobs_not_applied and NOT applied), --ring-freeze=N (ring applies N chill stacks; freeze_at is 4: 4 = freezes on the first hit).
##   NOT in the core (so NOT here): knockback / push, distance falloff of the ring damage, a stun on any spell other than the arc basic's chain contact. See REPORT "needs of the core".
##   Contact builds (--builds=): n_base n_A n_AR n_AR22 n_AX n_A6 n_R22 (see MELEE_PRESETS; they are not in the default list of the crowd test).
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
## Builds of the contact modes ("ring present or not" at equal other spells, plus a ring with axis points). Not part of PRESETS (the crowd test's default list).
const MELEE_PRESETS := [
	["n_base", "A"], ["n_A", "A:d2r1"], ["n_AR", "A:d2r1+R"], ["n_AR22", "A:d2r1+R:d2r2"], ["n_AX", "A:d2r1+X:d1"], ["n_A6", "A:d4r2"], ["n_R22", "R:d2r2"],
]
const HOLD_RADIUS := 12.0
const POTION_START := 3
var ring_knobs := {}
var tally_on := false
var elite_hp_arg := 0
var created_keys: Array = []
var unsupported: Array = []
var speed_mult := 1.0
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

func shipped_doc(witch: String = "") -> Dictionary:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SPELLS))
	doc.enabled = true
	for entry in doc_overrides:
		if not set_path(doc, String(entry.path), entry.value): checks_failed.append("override path not found: " + String(entry.path))
	if not witch.is_empty() and not ring_knobs.is_empty(): apply_ring_knobs(doc, witch)
	return doc

## Ring knobs (see the header): written into the witch's own ring spell in the in-memory document only.
func apply_ring_knobs(doc: Dictionary, witch: String) -> void:
	var id_ := SK + witch + "_ring"
	if not doc.spells.has(id_):
		checks_failed.append("no ring spell " + id_)
		return
	var s: Dictionary = doc.spells[id_]
	var base: Dictionary = s.base
	var reach: Array = s.reach
	if ring_knobs.has("radius_m"):
		var cm := int(round(float(ring_knobs.radius_m) * 100.0))
		base.ring_radius_cm = cm
		for r in reach:
			if r.has("ring_radius_cm"): r.ring_radius_cm = cm
	if ring_knobs.has("cd_s"): base.cooldown_ticks = maxi(12, int(round(float(ring_knobs.cd_s) * 60.0)))
	if ring_knobs.has("dmg"): base.damage_raw = maxi(1, int(round(float(base.damage_raw) * float(ring_knobs.dmg))))
	if ring_knobs.has("vs_strong"): s.vs_strong_bps = int(round(float(ring_knobs.vs_strong) * 10000.0))
	if ring_knobs.has("pulses"): base.ring_pulses = int(ring_knobs.pulses)
	if ring_knobs.has("targets"):
		base.ring_targets = int(ring_knobs.targets)
		for r in reach:
			if r.has("ring_targets"): r.ring_targets = int(ring_knobs.targets)
	if ring_knobs.has("budget"):
		base.hit_budget = int(ring_knobs.budget)
		for r in reach:
			if r.has("hit_budget"): r.hit_budget = int(ring_knobs.budget)
	if ring_knobs.has("slow_bps"):
		if String(s.element) == "frost":
			base.slow_bps = int(ring_knobs.slow_bps)
			s.slow_ticks = int(ring_knobs.get("slow_ticks", 90))
		elif not unsupported.has("slow on non-frost ring (core: slow only from frost-element spells; the document check ties a ring's element to its witch)"):
			unsupported.append("slow on non-frost ring (core: slow only from frost-element spells; the document check ties a ring's element to its witch)")
	if ring_knobs.has("freeze"):
		var applies: Dictionary = s.applies
		applies["chill"] = int(ring_knobs.freeze)
		s["applies"] = applies

## JSON.parse_string yields floats for every number; the document check wants integers where the value is whole.
func normalize_value(v: Variant) -> Variant:
	if v is float and is_equal_approx(v, round(v)): return int(round(v))
	if v is Array:
		var out: Array = []
		for x in v: out.append(normalize_value(x))
		return out
	if v is Dictionary:
		var d := {}
		for k in v: d[k] = normalize_value(v[k])
		return d
	return v

func set_path(doc: Variant, path: String, value: Variant) -> bool:
	var tokens: PackedStringArray = path.split("/", false)
	var cur: Variant = doc
	for i in tokens.size():
		var key: String = tokens[i]
		var last := i == tokens.size() - 1
		if cur is Dictionary:
			if not cur.has(key):
				if not last: return false
				created_keys.append(path)
			if last: cur[key] = normalize_value(value)
			else: cur = cur[key]
		elif cur is Array:
			if not key.is_valid_int() or int(key) < 0 or int(key) >= cur.size(): return false
			if last: cur[int(key)] = normalize_value(value)
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
	for entry in MELEE_PRESETS:
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
func neutralize(run: RefCounted, real_max: int = 0) -> void:
	## real_max > 0 (contact modes): the hero keeps its real maximum life (so the heavy-hit rule works) and is refilled every tick.
	run.hero.max_hp_raw = real_max if real_max > 0 else HERO_HP
	run.hero.hp_raw = run.hero.max_hp_raw
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
	var run := make_run(seed_, primary, shipped_doc(witch))
	if run == null: return {}
	apply_build(run, build)
	run.enemies.clear()
	run._alive = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_ * 7919 + 13
	var pilot = Pilot.new()
	pilot.run = run
	var real_max := int(run.hero.max_hp_raw) if tally_on else 0
	var hero_hp_arg := arg_string("--hero-hp", "")
	if tally_on and not hero_hp_arg.is_empty(): real_max = int(float(hero_hp_arg)) * UNIT
	neutralize(run, real_max)
	fill_any(run, rng, beat, hp_mode, mobs, false, true)
	var elite_id := place_elite(run) if elite else -1
	if elite and elite_hp_arg > 0:
		run.enemies[elite_id].hp_raw = elite_hp_arg * UNIT
		run.enemies[elite_id].max_hp_raw = elite_hp_arg * UNIT
		if tally_on:
			var champ: Dictionary = tuning_doc.champions[0]
			run.enemies[elite_id].definition.damage = int(champ.damage)
			run.enemies[elite_id].definition.windup = int(champ.windup)
			run.enemies[elite_id].definition.recover = int(champ.recover)
	var m := new_m(real_max, run.tick + int(warmup_s * 60.0))
	var t3 := {"ticks": 0, "contact": 0, "preps": 0, "preps_hit": 0, "windup_ids": {}, "close_ids": {}}
	var ticks_done := 0
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
		neutralize(run, real_max)
		if run.mode != "playing":
			aborted = true
			break
		fill_any(run, rng, beat, hp_mode, mobs, elite, false)
		if not pretag.is_empty(): apply_pretag(run, own_pair(run.spells, witch))
		var pre := ring_snapshots(run, rings) if i >= warm else {}
		var move := Vector2.ZERO if stand else pilot.decide()
		run.step(move)
		if i >= warm:
			collect(run, acc, pre, elite_id, ring_radius)
			ticks_done += 1
			if tally_on:
				collect_m(run, m, elite_id, SK + witch + "_ring")
				track_contact(run, t3)
				if ticks_done == 2400: m["dealt40"] = int(m.dealt)
		if elite and elite_hp_arg > 0 and (not run.enemies.has(elite_id) or run.enemies[elite_id].hp_raw <= 0): break
	var out := finish(acc, float(ticks_done) / 60.0 if elite_hp_arg > 0 and elite else secs, run, build, label)
	if tally_on:
		out.merge(finish_m(m, ticks_done, elite_id, run, label), false)
		out.merge(finish_t3(t3), true)
		if m.has("dealt40"): out.power_40_60_hp_s = r2(float(int(m.dealt) - int(m.dealt40)) / UNIT / maxf(1.0, float(ticks_done - 2400) / 60.0))
		if elite and elite_hp_arg > 0:
			out.elite_killed = not run.enemies.has(elite_id) or run.enemies[elite_id].hp_raw <= 0
			out.kill_s = r2(float(ticks_done) / 60.0) if out.elite_killed else -1.0
	out.aborted = aborted
	out.events_dropped = int(run.metrics.get("events_dropped", 0))
	return out

# ------------------------------------------------------------------ contact modes (melee / hold / strong)

## Like fill(), but with the zone's damage and speed (the crowd test leaves them at zone 0) and a speed multiplier.
func fill_contact(run: RefCounted, rng: RandomNumberGenerator, beat: Dictionary, hp_mode: String, target: int, has_elite: bool, initial: bool, speed_m: float, ring: Vector2 = Vector2.ZERO) -> void:
	var count: int = run.alive_count() - (1 if has_elite else 0)
	var z := clampi(int(beat.zone), 0, 2)
	while count < target:
		var kind := pick_kind(rng, beat)
		var angle := rng.randf_range(0.0, TAU)
		var rmin := float(run.tuning.spawn.ring_min_m) if ring == Vector2.ZERO else ring.x
		var rmax := float(run.tuning.spawn.ring_max_m) if ring == Vector2.ZERO else ring.y
		var dist := rng.randf_range(rmin, rmax)
		if initial: dist = sqrt(rng.randf_range(2.0 * 2.0, (10.5 if ring == Vector2.ZERO else ring.y) * (10.5 if ring == Vector2.ZERO else ring.y)))
		var point: Vector2 = run._clamp_point(run.hero.position + Vector2(cos(angle), sin(angle)) * dist)
		if not run._spawn(kind, point): break
		var e: Dictionary = run.enemies[run._enemy_sequence]
		var hp := hp_of(kind, beat, hp_mode)
		e.hp_raw = hp * UNIT
		e.max_hp_raw = e.hp_raw
		e.definition.hp = hp
		e.definition.damage = int(tuning_doc.enemies[kind].damage[z])
		e.definition.speed = float(tuning_doc.enemies[kind].speed[z]) * speed_m
		count += 1

func fill_any(run: RefCounted, rng: RandomNumberGenerator, beat: Dictionary, hp_mode: String, target: int, has_elite: bool, initial: bool) -> void:
	if tally_on: fill_contact(run, rng, beat, hp_mode, target, has_elite, initial, speed_mult)
	else: fill(run, rng, beat, hp_mode, target, has_elite, initial)

## T-3: per tick, the share of ticks with a living ordinary enemy within 1.15 m (the melee reach), and windups that START within 1.15 m and how many of those hit.
func track_contact(run: RefCounted, t3: Dictionary) -> void:
	t3.ticks += 1
	var any := false
	var seen := {}
	for e in run.enemies.values():
		if e.hp_raw <= 0 or bool(e.elite): continue
		var d: float = e.position.distance_to(run.hero.position)
		if d <= 1.15: any = true
		if String(e.state) == "windup":
			var id_ := int(e.id)
			seen[id_] = true
			if not t3.windup_ids.has(id_):
				t3.windup_ids[id_] = true
				if d <= 1.15:
					t3.preps += 1
					t3.close_ids[id_] = true
	if any: t3.contact += 1
	for ev in run.events:
		if String(ev.type) != "hero_hit": continue
		var from_pos: Vector2 = ev.get("from", Vector2(1e9, 1e9))
		for id_ in t3.close_ids.keys():
			if run.enemies.has(id_) and run.enemies[id_].position.distance_to(from_pos) < 0.05:
				t3.preps_hit += 1
				t3.close_ids.erase(id_)
				break
	for id_ in t3.windup_ids.keys():
		if not seen.has(id_):
			t3.windup_ids.erase(id_)
			t3.close_ids.erase(id_)

func finish_t3(t3: Dictionary) -> Dictionary:
	return {"contact_share_pct": r1(100.0 * float(t3.contact) / maxf(1.0, float(t3.ticks))), "preps_close": t3.preps, "preps_close_hit": t3.preps_hit}

## The champion of the beat's zone (real hp / damage / windup / recover from combat_tuning champions), next to the hero.
func place_champion(run: RefCounted, zone_index: int, dist_m: float) -> int:
	var point: Vector2 = run._clamp_point(run.hero.position + Vector2(cos(0.8), sin(0.8)) * dist_m)
	run._spawn("elite", point)
	var id_: int = run._enemy_sequence
	var e: Dictionary = run.enemies[id_]
	var champ: Dictionary = tuning_doc.champions[clampi(zone_index, 0, 2)]
	e.definition.hp = int(champ.hp)
	e.definition.windup = int(champ.windup)
	e.definition.recover = int(champ.recover)
	e.definition.damage = int(champ.damage)
	e.hp_raw = int(champ.hp) * UNIT
	e.max_hp_raw = e.hp_raw
	return id_

func new_m(real_max: int, t0: int) -> Dictionary:
	return {"max": real_max, "t0": t0, "hits": 0, "dmg": 0, "graze": 0, "first_hit": -1, "sh_np": real_max, "sh_p": real_max, "potions": POTION_START, "next_potion": 0, "pot_used": 0,
		"dead_np": -1, "dead_p": -1, "samples": 0, "alive": 0, "n15": 0, "n30": 0, "n50": 0, "a15": 0, "c15": 0, "c30": 0, "kills": 0, "dealt": 0, "elite_dealt": 0,
		"ring_casts": 0, "ring_hits": 0, "ring_dealt": 0, "elite_samples": 0, "elite_d": 0.0, "elite_in3": 0, "elite_alive_ticks": 0, "frozen_samples": 0}

func collect_m(run: RefCounted, m: Dictionary, elite_id: int, ring_id: String) -> void:
	for ev in run.events:
		match String(ev.type):
			"hero_hit":
				var dmg := int(ev.damage_raw)
				m.hits += 1
				m.dmg += dmg
				if bool(ev.get("graze", false)): m.graze += 1
				if int(m.first_hit) < 0: m.first_hit = run.tick - int(m.t0)
				m.sh_np -= dmg
				m.sh_p -= dmg
			"hit":
				var dealt := int(ev.dealt_raw)
				m.dealt += dealt
				if int(ev.target_id) == elite_id: m.elite_dealt += dealt
				if String(ev.skill_id) == ring_id:
					m.ring_hits += 1
					m.ring_dealt += dealt
			"cast":
				if String(ev.get("shape", "")) == "ring" and String(ev.skill_id) == ring_id: m.ring_casts += 1
			"death":
				m.kills += 1
	if int(m.dead_np) < 0 and int(m.sh_np) <= 0: m.dead_np = run.tick - int(m.t0)
	if int(m.dead_p) < 0 and int(m.sh_p) <= 0: m.dead_p = run.tick - int(m.t0)
	if int(m.sh_p) * 100 < int(m.max) * 68 and int(m.potions) > 0 and run.tick >= int(m.next_potion) and int(m.sh_p) > 0:
		m.potions -= 1
		m.pot_used += 1
		m.next_potion = run.tick + int(run.tuning.potion.cooldown_ticks)
		m.sh_p = mini(int(m.max), int(m.sh_p) + int(m.max) * int(run.tuning.potion.heal_bps) / 10000)
	if elite_id >= 0 and run.enemies.has(elite_id) and run.enemies[elite_id].hp_raw > 0: m.elite_alive_ticks += 1
	if run.tick % 6 == 0:
		m.samples += 1
		var n15 := 0
		var n30 := 0
		var n50 := 0
		var a15 := 0
		var alive := 0
		for e in run.enemies.values():
			if e.hp_raw <= 0: continue
			var d2: float = e.position.distance_squared_to(run.hero.position)
			if bool(e.elite):
				m.elite_samples += 1
				m.elite_d += sqrt(d2)
				if d2 <= 3.0 * 3.0: m.elite_in3 += 1
				continue
			alive += 1
			if d2 <= 5.0 * 5.0:
				n50 += 1
				if d2 <= 3.0 * 3.0:
					n30 += 1
					if d2 <= 1.5 * 1.5:
						n15 += 1
						if run.tick >= int(e.frozen_until) and run.tick >= int(e.get("stunned_until", 0)): a15 += 1
		m.alive += alive
		m.n15 += n15
		m.n30 += n30
		m.n50 += n50
		m.a15 += a15
		if n15 > 0: m.c15 += 1
		if n30 > 0: m.c30 += 1
		if n15 > a15: m.frozen_samples += 1

func finish_m(m: Dictionary, dur_ticks: int, elite_id: int, run: RefCounted, label: String) -> Dictionary:
	var secs := maxf(1.0 / 60.0, float(dur_ticks) / 60.0)
	var samples := maxf(1.0, float(m.samples))
	var max_hp := float(m.max)
	var out := {"kind": label, "secs": r2(secs), "taken_pct_s": r2(100.0 * float(m.dmg) / max_hp / secs), "taken_hp_s": r2(float(m.dmg) / UNIT / secs), "hero_hits": m.hits, "hero_hits_per_s": r2(float(m.hits) / secs), "taken_pct_total": r2(100.0 * float(m.dmg) / max_hp),
		"graze": m.graze, "first_hit_s": r2(float(m.first_hit) / 60.0) if int(m.first_hit) >= 0 else -1.0, "alive_mean": r1(float(m.alive) / samples),
		"n1_5": r2(float(m.n15) / samples), "n3": r2(float(m.n30) / samples), "n5": r2(float(m.n50) / samples), "active_1_5": r2(float(m.a15) / samples),
		"contact_1_5_pct": r1(100.0 * float(m.c15) / samples), "contact_3_pct": r1(100.0 * float(m.c30) / samples), "enemy_s_1_5": r1(float(m.n15) / samples * secs),
		"frozen_contact_pct": r1(100.0 * float(m.frozen_samples) / samples), "dead_np_s": r2(float(m.dead_np) / 60.0) if int(m.dead_np) >= 0 else -1.0, "dead_p_s": r2(float(m.dead_p) / 60.0) if int(m.dead_p) >= 0 else -1.0,
		"sh_p_left_pct": r1(100.0 * maxf(0.0, float(m.sh_p)) / max_hp), "pot_used": m.pot_used, "kills": m.kills, "kills_per_s": r2(float(m.kills) / secs), "power_hp_s": r2(float(m.dealt) / UNIT / secs),
		"ring_casts": m.ring_casts, "ring_casts_per_s": r2(float(m.ring_casts) / secs), "ring_hits_per_cast": r2(float(m.ring_hits) / maxf(1.0, float(m.ring_casts))),
		"ring_share_pct": r1(100.0 * float(m.ring_dealt) / maxf(1.0, float(m.dealt))), "hero_max_hp": int(m.max) / UNIT}
	if elite_id >= 0:
		var e: Dictionary = run.enemies.get(elite_id, {})
		var dead: bool = e.is_empty() or int(e.hp_raw) <= 0
		out.elite_killed = dead
		out.ttk_s = r2(float(dur_ticks) / 60.0) if dead else -1.0
		out.elite_hp_left_pct = 0.0 if dead else r1(100.0 * float(e.hp_raw) / maxf(1.0, float(e.max_hp_raw)))
		out.elite_dps_hp = r2(float(m.elite_dealt) / UNIT / secs)
		out.elite_hp_total = int(e.get("max_hp_raw", 0)) / UNIT if not e.is_empty() else 0
		out.ttk_est_s = r1(float(out.elite_hp_total) / maxf(0.001, float(m.elite_dealt) / UNIT / secs))
		out.elite_d_mean = r2(float(m.elite_d) / maxf(1.0, float(m.elite_samples)))
		out.elite_in3_pct = r1(100.0 * float(m.elite_in3) / maxf(1.0, float(m.elite_samples)))
	return out

## One contact arena. mode: melee | hold | strong. variant: stand | pilot | rush.
func contact_arena(witch: String, build: Dictionary, mode: String, variant: String, mobs: int, secs: float, seed_: int, beat: Dictionary, hp_mode: String, warmup_s: float, champ_zone: int) -> Dictionary:
	var primary := SK + witch
	var run := make_run(seed_, primary, shipped_doc(witch))
	if run == null: return {}
	apply_build(run, build)
	run.enemies.clear()
	run._alive = 0
	var real_max := int(run.hero.max_hp_raw)
	var hero_hp_arg := arg_string("--hero-hp", "")
	if not hero_hp_arg.is_empty(): real_max = int(float(hero_hp_arg)) * UNIT
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_ * 7919 + 13
	var pilot = Pilot.new()
	pilot.run = run
	var stand := variant == "stand"
	var speed_m := speed_mult * (float(arg_string("--rush-mult", "2.5")) if variant == "rush" else 1.0)
	var strong := mode == "strong"
	var ring_m := Vector2.ZERO
	if variant == "rush": ring_m = Vector2(float(arg_string("--rush-ring-min", "3.0")), float(arg_string("--rush-ring-max", "5.0")))
	neutralize(run, real_max)
	fill_contact(run, rng, beat, hp_mode, mobs, false, true, speed_m, ring_m)
	var elite_id := place_champion(run, champ_zone, 2.2) if strong else -1
	var center: Vector2 = run.hero.position
	var warm := 0 if strong else int(warmup_s * 60.0)
	var total := warm + int(secs * 60.0)
	var ring_id := SK + witch + "_ring"
	var m := new_m(real_max, run.tick + warm)
	var aborted := false
	var measured := 0
	for i in total:
		neutralize(run, real_max)
		if run.mode != "playing":
			aborted = true
			break
		fill_contact(run, rng, beat, hp_mode, mobs, strong, false, speed_m, ring_m)
		var move := Vector2.ZERO if stand else pilot.decide()
		run.step(move)
		if mode == "hold":
			var off: Vector2 = run.hero.position - center
			if off.length() > HOLD_RADIUS: run.hero.position = center + off.normalized() * HOLD_RADIUS
		if i >= warm:
			collect_m(run, m, elite_id, ring_id)
			measured += 1
		if strong and not run.enemies.has(elite_id) or (strong and run.enemies[elite_id].hp_raw <= 0): break
	var out := finish_m(m, measured, elite_id, run, mode)
	out.aborted = aborted
	out.variant = variant
	out.events_dropped = int(run.metrics.get("events_dropped", 0))
	out.speed_mult = r2(speed_m)
	return out

func print_contact_tables(results: Array, witches: Array, build_names: Array) -> void:
	for witch in witches:
		var rows: Array = results.filter(func(r): return r.witch == witch and r.test in ["melee", "hold", "strong"])
		if rows.is_empty(): continue
		print("")
		print("== witch %s : contact (mean over seeds). taken = %% of max life per second; n = ordinary enemies within 1.5/3/5 m; cont = %% of time with one within 1.5 m; dead = shadow life reached 0 (s; -1 none) ==" % witch)
		print("%-8s %-7s %-7s %5s | %7s %6s | %5s %5s %5s | %6s | %7s %7s | %6s %6s" % ["build", "test", "variant", "load", "taken%/s", "hits/s", "n1.5", "n3", "n5", "cont%", "dead_np", "dead_p", "ttk_s", "kills/s"])
		var keys: Array = []
		for r in rows:
			var key := "%s|%s|%d" % [r.test, r.variant, int(r.load)]
			if not key in keys: keys.append(key)
		for key in keys:
			for name in build_names:
				var cells: Array = rows.filter(func(r): return r.build == name and "%s|%s|%d" % [r.test, r.variant, int(r.load)] == key)
				if cells.is_empty(): continue
				var c0: Dictionary = cells[0]
				var ttk := mean_of(cells, func(c): return c.get("ttk_s", -1.0))
				print("%-8s %-7s %-7s %5d | %8.2f %6.2f | %5.2f %5.2f %5.2f | %6.1f | %7.1f %7.1f | %6.1f %6.2f" % [name, c0.test, c0.variant, int(c0.load), mean_of(cells, func(c): return c.taken_pct_s), mean_of(cells, func(c): return c.hero_hits_per_s),
					mean_of(cells, func(c): return c.n1_5), mean_of(cells, func(c): return c.n3), mean_of(cells, func(c): return c.n5), mean_of(cells, func(c): return c.contact_1_5_pct),
					mean_of(cells, func(c): return c.dead_np_s), mean_of(cells, func(c): return c.dead_p_s), ttk, mean_of(cells, func(c): return c.kills_per_s)])

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
	for knob in [["--ring-radius", "radius_m"], ["--ring-cd", "cd_s"], ["--ring-dmg", "dmg"], ["--ring-vs-strong", "vs_strong"], ["--ring-pulses", "pulses"], ["--ring-targets", "targets"], ["--ring-budget", "budget"], ["--ring-freeze", "freeze"]]:
		var v := arg_string(String(knob[0]), "")
		if not v.is_empty(): ring_knobs[String(knob[1])] = float(v)
	var slow_text := arg_string("--ring-slow", "")
	if not slow_text.is_empty():
		ring_knobs.slow_bps = float(slow_text.get_slice(",", 0))
		if "," in slow_text: ring_knobs.slow_ticks = float(slow_text.get_slice(",", 1))
	speed_mult = float(arg_string("--speed-mult", "1.0"))
	var modes := arg_names("--mode", [])
	var legacy := modes.is_empty() or modes.has("crowd") or modes.has("single")
	var do_crowd := (modes.is_empty() or modes.has("crowd")) and not arg_flag("--no-crowd")
	var do_single := (modes.is_empty() or modes.has("single")) and not arg_flag("--no-single")
	tally_on = arg_flag("--tally")
	var crowd_modes := arg_names("--crowd-modes", ["pilot"])
	var elite_text := arg_string("--elite-hp", "")
	var mix_text := arg_string("--mix", "")
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
	if not mix_text.is_empty():
		var parts := mix_text.split(":")
		if parts.size() != 3:
			print("CHAPTER1_SIM_POWER_RESULT ", JSON.stringify({"error": "--mix needs walker:ranged:charger"}))
			quit(1)
			return
		beat = beat.duplicate(true)
		beat.mix = {"walker": int(parts[0]), "ranged": int(parts[1]), "charger": int(parts[2])}
	if elite_text == "g1":
		var bps_pair: Array = beat.hp_bps
		elite_hp_arg = int(tuning_doc.champions[0].hp) * (int(bps_pair[0]) + int(bps_pair[1])) / 20000
	elif not elite_text.is_empty(): elite_hp_arg = int(elite_text)
	var named: Array = []
	var custom := arg_string("--build", "")
	if not custom.is_empty(): named.append(["custom", custom])
	var wanted := arg_names("--builds", [])
	if custom.is_empty() and (wanted.is_empty() or wanted == ["all"]):
		for entry in (PRESETS if legacy else MELEE_PRESETS): named.append([entry[0], entry[1]])
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
				if do_crowd:
					for crowd_mode in crowd_modes:
						for density in densities:
							var t0 := Time.get_ticks_msec()
							var cell := arena(String(witch), build, int(density), false, String(crowd_mode) == "stand", secs, int(seed_), beat, hp_mode, warmup, "crowd")
							if cell.is_empty(): continue
							cell.merge({"crowd_mode": crowd_mode, "test": "crowd", "witch": witch, "build": entry[0], "spec": entry[1], "seed": seed_, "density": density, "beat": beat_id, "points": axis_points(build), "legal": build.legal, "notes": build.notes,
								"evolve_legal": build.get("evolve_legal", null), "wall_s": r1(float(Time.get_ticks_msec() - t0) / 1000.0)})
							results.append(cell)
							cells_done += 1
							print("CELL crowd %-5s %-10s %-5s N=%-3d seed=%d P=%8.1f det=%5.1f%% kills/s=%5.2f hits/kill=%5.2f wall=%.1fs taken=%.1f%% cont=%.1f%%" % [witch, entry[0], crowd_mode, density, seed_, cell.power_hp_s, cell.det_share_dealt_pct, cell.kills_per_s, cell.hits_per_kill, cell.wall_s, cell.get("taken_pct_total", -1.0), cell.get("contact_share_pct", -1.0)])
				if do_single:
					for mode in single_modes:
						for mobs in single_mobs:
							var t0 := Time.get_ticks_msec()
							var cell := arena(String(witch), build, int(mobs), true, String(mode) == "stand", single_secs, int(seed_), beat, hp_mode, 3.0, "single")
							if cell.is_empty(): continue
							cell.merge({"test": "single", "witch": witch, "build": entry[0], "spec": entry[1], "seed": seed_, "mobs": mobs, "mode": mode, "beat": beat_id, "points": axis_points(build), "legal": build.legal, "notes": build.notes,
								"wall_s": r1(float(Time.get_ticks_msec() - t0) / 1000.0)})
							results.append(cell)
							cells_done += 1
							print("CELL single %-5s %-10s mobs=%-2d %-5s seed=%d P_elite=%7.1f elite_dist=%5.2f wall=%.1fs kill_s=%s" % [witch, entry[0], mobs, mode, seed_, cell.get("elite_dps_hp", 0.0), cell.get("elite_dist_mean", 0.0), cell.wall_s, str(cell.get("kill_s", "-"))])
				for test in ["melee", "hold", "strong"]:
					if not modes.has(test): continue
					var variants: Array = arg_names("--%s-variants" % test, ["stand", "pilot"] if test != "melee" else ["stand", "rush"])
					var loads: Array = arg_ints("--m-density", [35, 70]) if test == "melee" else (arg_ints("--hold-density", [70, 100]) if test == "hold" else arg_ints("--strong-mobs", [0, 10, 30]))
					var test_secs := float(arg_string("--strong-secs", "90")) if test == "strong" else float(arg_string("--m-secs" if test == "melee" else "--hold-secs", "45"))
					var test_beat := beat
					if test == "hold":
						var trial: Dictionary = tuning_doc.rhythm.trial
						test_beat = {"id": "trial", "zone": 2, "hp_bps": [int(trial.hp_bps), int(trial.hp_bps)], "mix": trial.mix}
					var champ_zone := int(arg_string("--champion", str(int(beat.zone))))
					for variant in variants:
						for load_ in loads:
							var t0 := Time.get_ticks_msec()
							var cell := contact_arena(String(witch), build, test, String(variant), int(load_), test_secs, int(seed_), test_beat, hp_mode, warmup, champ_zone)
							if cell.is_empty(): continue
							cell.merge({"test": test, "witch": witch, "build": entry[0], "spec": entry[1], "seed": seed_, "load": load_, "beat": String(test_beat.id), "points": axis_points(build), "legal": build.legal, "notes": build.notes,
								"wall_s": r1(float(Time.get_ticks_msec() - t0) / 1000.0)})
							results.append(cell)
							cells_done += 1
							print("CELL %-6s %-5s %-8s %-7s load=%-3d seed=%d taken=%6.2f%%/s hits/s=%5.2f n1.5=%5.2f n3=%5.2f n5=%5.2f dead_np=%6.1f dead_p=%6.1f ttk=%6.1f wall=%.1fs" % [test, witch, entry[0], variant, load_, seed_,
								cell.taken_pct_s, cell.hero_hits_per_s, cell.n1_5, cell.n3, cell.n5, cell.dead_np_s, cell.dead_p_s, cell.get("ttk_s", -1.0), cell.wall_s])
	print_contact_tables(results, witches, build_names)
	if legacy and not tally_on and crowd_modes == ["pilot"]: print_tables(results, witches, build_names, densities if do_crowd else [], single_mobs if do_single else [], single_modes if do_single else [])
	var elapsed := r1(float(Time.get_ticks_msec() - started_ms) / 1000.0)
	var meta := {"beat": beat_id, "hp_mode": hp_mode, "beat_hp_bps": beat.hp_bps, "beat_mix": beat.mix, "beat_zone": beat.zone, "secs": secs, "single_secs": single_secs, "warmup_s": warmup, "seeds": seeds, "witches": witches,
		"densities": densities, "single_mobs": single_mobs, "single_modes": single_modes, "overrides": doc_overrides, "borrow": borrow_override, "pretag": pretag, "elapsed_s": elapsed, "modes": modes, "ring_knobs": ring_knobs, "knobs_not_applied": unsupported, "tally": tally_on, "crowd_modes": crowd_modes, "mix": mix_text, "elite_hp": elite_hp_arg, "created_keys": created_keys, "speed_mult": speed_mult,
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
