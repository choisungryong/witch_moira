extends RefCounted
## Battle record of one run (D11 F1, W7). It sits on the app side of the line: it only READS core events and core state
## and keeps its own numbers. It never writes into the core, so a run with the recorder attached and one without it
## have the same snapshot hash (checked by test_run_record.gd).
##
## Use:  begin(run, depth) -> consume(run.events) after every place events are read -> observe(run) once per step
##       -> finish(run) when the run ends -> to_last_record() / summary().
## consume() ignores an event it already saw (by `seq`), so reading the same list twice is harmless. The pilot's card
## choices and potions happen inside decide(), before step() clears the list; the app calls consume() right after decide().
##
## to_last_record() is exactly the shape of docs/specs/T6-save-schema5-directives-20261119.ko.md 4.3 (`records.last`).
## summary() is the loose shape for the result screen: it adds what 4.3 does not hold (shares, per-second damage, the pair
## table, the beat table, the "why did I lose" material). The pair and beat tables just group the keys the events carry,
## so a change in the spell structure only changes what is grouped, not this code.

const SKILL_ROWS_MAX := 16
const ITEM_SOURCES_MAX := 16
const LIMIT := 1000000000
const SKILL_DAMAGE_LIMIT := 1000000000000
const CHAMPION_KILLS_MAX := 16
const ID_PATTERN := "^[a-z0-9][a-z0-9_.:-]{0,79}\\z"
const DEPTH_PATTERN := "^d[0-9]{1,2}\\z"
## How far back a hit may be matched to the attack that caused it (seconds; the core's attack events come before the hit).
const ATTRIBUTE_BACK_SECONDS := 3
const ATTRIBUTE_DISTANCE_SQ := 0.05
## The "recent damage per second" of summary() looks this many seconds back from the end of the run.
const RECENT_SECONDS := 60

var depth := "d1"
var _begun := false
var _finished := false
var _unit := 256
var _hz := 60
var _window_ticks := 1800
var _last_seq := -1
var _now := 0
var _level := 1
var _primary := ""
## Life really taken off enemies per second of play ({second index: dealt_raw}); only the last RECENT_SECONDS are kept.
var _dealt_by_second: Dictionary = {}
var _max_hp_raw := 1
var _final_level := 1

var _damage_raw: Dictionary = {}
var _kills_by_skill: Dictionary = {}
var _skill_meta: Dictionary = {}
var _kills := 0
var _elite_kills := 0
var _champion_kills := 0
var _boss_kill := false
var _champions: Dictionary = {}
var _potions := 0
var _taken_raw := 0
var _items: Dictionary = {}
var _grade := 0
var _victory := false
var _abandoned := false
var _ticks := 0
var _xp := 0
var _events_dropped := 0
var _hit_events := 0
var _detonate: Dictionary = {}
var _beats: Array[Dictionary] = []
## The card picks in order: {tick, level, card} (the screen's "what I chose" list; not part of records.last).
var _picks: Array[Dictionary] = []
## [tick, damage_raw, from] of recent hero hits; [tick, position, kind] of recent enemy attacks and hazard bursts; [tick, alive, hp_bps].
var _hero_hits: Array = []
var _attacks: Array = []
var _samples: Array = []
var _last_sample_tick := -1
var _summary: Dictionary = {}

## Starts a record for a run that has just been started. `loss_window_seconds` is D11's "30 seconds before the fall".
func begin(run: Object, depth_key: String = "d1", loss_window_seconds: int = 30) -> void:
	depth = depth_key
	_begun = true
	_finished = false
	_unit = maxi(1, int(run.UNIT))
	_hz = maxi(1, int(run.HZ))
	_window_ticks = loss_window_seconds * _hz
	_last_seq = -1
	_now = int(run.tick)
	var growth: Dictionary = run.growth.snapshot()
	_level = int(growth.level)
	_primary = String(growth.primary)
	_dealt_by_second = {}
	_max_hp_raw = maxi(1, int(run.hero.get("max_hp_raw", 1)))
	_final_level = _level
	_damage_raw = {}
	_kills_by_skill = {}
	_skill_meta = {}
	_kills = 0
	_elite_kills = 0
	_champion_kills = 0
	_boss_kill = false
	_champions = {}
	_potions = 0
	_taken_raw = 0
	_items = {}
	_grade = 0
	_victory = false
	_abandoned = false
	_ticks = 0
	_xp = 0
	_events_dropped = 0
	_hit_events = 0
	_detonate = {}
	_beats = []
	_picks = []
	_hero_hits = []
	_attacks = []
	_samples = []
	_last_sample_tick = -1
	_summary = {}
	for id_ in growth.ranks:
		_skill_meta[String(id_)] = {"got_tick": 0, "got_level": 1, "rank": int(growth.ranks[id_]), "evolved": false}
	if not _primary.is_empty() and not _skill_meta.has(_primary):
		_skill_meta[_primary] = {"got_tick": 0, "got_level": 1, "rank": 1, "evolved": false}

func is_finished() -> bool:
	return _finished

## Reads core events. Only events with a `seq` above the last one seen count.
func consume(events: Array) -> void:
	if not _begun or _finished:
		return
	for event in events:
		var seq := int(event.get("seq", -1))
		if seq <= _last_seq:
			continue
		_last_seq = seq
		var tick := int(event.get("tick", _now))
		_now = maxi(_now, tick)
		match String(event.get("type", "")):
			"hit":
				var skill := String(event.get("skill_id", ""))
				# dealt_raw is the life really taken off (overflow past death excluded); an older core only has damage_raw.
				var dealt := int(event.get("dealt_raw", event.get("damage_raw", 0)))
				_damage_raw[skill] = int(_damage_raw.get(skill, 0)) + dealt
				_hit_events += 1
				_dealt_by_second[tick / _hz] = int(_dealt_by_second.get(tick / _hz, 0)) + dealt
				_touch_skill(skill, tick)
				_beat_add("damage_raw", dealt)
			"death":
				_kills += 1
				var skill := String(event.get("skill_id", ""))
				_kills_by_skill[skill] = int(_kills_by_skill.get(skill, 0)) + 1
				_touch_skill(skill, tick)
				_beat_add("kills", 1)
				var target := int(event.get("target_id", -1))
				if _champions.has(target):
					if int(_champions[target]) >= 2:
						_boss_kill = true
					else:
						_champion_kills += 1
				elif bool(event.get("elite", false)):
					_elite_kills += 1
			"chapter_champion":
				_champions[int(event.get("target_id", -1))] = int(event.get("zone", 0))
			"hero_hit":
				var raw := int(event.get("damage_raw", 0))
				_taken_raw += raw
				_beat_add("taken_raw", raw)
				_hero_hits.append([tick, raw, event.get("from", Vector2.ZERO), String(event.get("source_kind", "")), int(event.get("hp_after_raw", -1))])
			"enemy_attack":
				_attacks.append([tick, event.get("position", Vector2.ZERO), String(event.get("kind", "unknown"))])
			"chapter_burst":
				_attacks.append([tick, event.get("position", Vector2.ZERO), "hazard"])
			"potion_used":
				_potions += 1
			"item_drop":
				var source := String(event.get("source", ""))
				if not source.is_empty():
					_items[source] = int(_items.get(source, 0)) + 1
			"level_choice":
				_level = maxi(_level, int(event.get("level", _level)))
			"growth":
				_on_growth(event, tick)
			"reward_grade_up":
				_grade = maxi(_grade, int(event.get("grade", 0)))
			"detonate":
				# Grouped by the keys the event carries; nothing is derived from the spell structure.
				var key := "%s>%s" % [String(event.get("src_skill", "")), String(event.get("by_skill", ""))]
				var row: Dictionary = _detonate.get(key, {"src_skill": String(event.get("src_skill", "")), "by_skill": String(event.get("by_skill", "")), "statuses": [], "count": 0, "extra_raw": 0})
				row.count = int(row.count) + 1
				row.extra_raw = int(row.extra_raw) + int(event.get("extra_raw", 0))
				var status := String(event.get("status", ""))
				if not status.is_empty() and not status in row.statuses:
					row.statuses.append(status)
				_detonate[key] = row
			"beat_started":
				_beats.append({"id": String(event.get("id", "")), "tick": tick, "kills": 0, "taken_raw": 0, "damage_raw": 0})
			"defeat":
				_victory = false
				_abandoned = bool(event.get("abandoned", false))
			"victory":
				_victory = true
	_trim()

## Reads core state, never writes: once per second of play a sample of the number of living enemies and the hero's life.
func observe(run: Object) -> void:
	if not _begun or _finished:
		return
	var tick := int(run.tick)
	_now = maxi(_now, tick)
	if tick - _last_sample_tick >= _hz or _last_sample_tick < 0:
		_sample(run)
		_trim()

func _sample(run: Object) -> void:
	_last_sample_tick = int(run.tick)
	var max_hp := maxi(1, int(run.hero.get("max_hp_raw", 1)))
	_max_hp_raw = max_hp
	_samples.append([int(run.tick), int(run.alive_count()), int(run.hero.get("hp_raw", 0)) * 10000 / max_hp])

## Ends the record. Reads the final state once; a second call changes nothing.
func finish(run: Object) -> void:
	if not _begun or _finished:
		return
	consume(run.events)
	_sample(run)
	_ticks = int(run.tick)
	_now = maxi(_now, _ticks)
	_final_level = maxi(_level, int(run.growth.snapshot().level))
	# The victory event is what the core emits; the mode is "inventory" while the bag is open after the win.
	_victory = _victory or String(run.mode) == "victory"
	var progress: Dictionary = run.progress_summary()
	_xp = int(progress.get("xp_gained", 0))
	_events_dropped = int(run.metrics.get("events_dropped", 0))
	var growth: Dictionary = run.growth.snapshot()
	for id_ in growth.ranks:
		var meta: Dictionary = _skill_meta.get(String(id_), {"got_tick": _ticks, "got_level": int(growth.level), "rank": 0, "evolved": false})
		meta.rank = int(growth.ranks[id_])
		_skill_meta[String(id_)] = meta
	for id_ in growth.evolved:
		if _skill_meta.has(String(id_)):
			_skill_meta[String(id_)].evolved = true
	_finished = true
	_summary = _build_summary()

func _touch_skill(skill: String, tick: int) -> void:
	if skill.is_empty() or _skill_meta.has(skill):
		return
	_skill_meta[skill] = {"got_tick": tick, "got_level": _level, "rank": 0, "evolved": false}

func _on_growth(event: Dictionary, tick: int) -> void:
	var growth: Dictionary = event.get("growth", {})
	_level = maxi(_level, int(growth.get("level", _level)))
	_picks.append(_pick_row(event, tick, int(growth.get("level", _level))))
	var ranks: Dictionary = growth.get("ranks", {})
	for id_ in ranks:
		var key := String(id_)
		if not _skill_meta.has(key):
			_skill_meta[key] = {"got_tick": tick, "got_level": int(growth.get("level", _level)), "rank": 0, "evolved": false}
		_skill_meta[key].rank = int(ranks[id_])
	for id_ in growth.get("evolved", []):
		if _skill_meta.has(String(id_)):
			_skill_meta[String(id_)].evolved = true

## One pick of the card list. `card` stays the id; the rest comes from the core's growth event (`card`), and from the id itself
## ("kind:skill:axis|rank") for an event that has none, so the screen never has to take the id apart.
func _pick_row(event: Dictionary, tick: int, level: int) -> Dictionary:
	var id_ := String(event.get("card_id", ""))
	var named: Dictionary = event.get("card", {})
	var parts := id_.split(":")
	var kind := String(named.get("kind", parts[0] if parts.size() > 0 else ""))
	var skill := String(named.get("skill_id", ""))
	var axis := String(named.get("axis", ""))
	var rank := int(named.get("rank", 0))
	if named.is_empty():
		match kind:
			"unlock", "evolve":
				skill = parts[1] if parts.size() > 1 else ""
			"axis":
				skill = parts[1] if parts.size() > 1 else ""
				axis = parts[2] if parts.size() > 2 else ""
			"rank":
				skill = parts[1] if parts.size() > 1 else ""
				rank = int(parts[2]) if parts.size() > 2 else 0
	var title := String(named.get("title_key", ""))
	if title.is_empty():
		match kind:
			"unlock", "rank", "axis":
				title = "skill.%s.name" % skill
			"evolve":
				title = "skill.%s.evolved_name" % skill
			"passive":
				title = "grace.passive.%s.name" % (parts[1] if parts.size() > 1 else "")
	return {"tick": tick, "level": level, "card": id_, "kind": kind, "skill_id": skill, "title_key": title, "rank": rank, "axis": axis, "axis_level": int(named.get("level", 0))}

func _beat_add(key: String, amount: int) -> void:
	if _beats.is_empty():
		return
	_beats[_beats.size() - 1][key] = int(_beats[_beats.size() - 1][key]) + amount

## The "why did I lose" material only ever needs the last window (and 3 seconds before it to match attacks to hits).
func _trim() -> void:
	var cut := _now - _window_ticks - ATTRIBUTE_BACK_SECONDS * _hz
	while not _hero_hits.is_empty() and int(_hero_hits[0][0]) < cut:
		_hero_hits.pop_front()
	while not _attacks.is_empty() and int(_attacks[0][0]) < cut:
		_attacks.pop_front()
	while not _samples.is_empty() and int(_samples[0][0]) < cut:
		_samples.pop_front()
	var recent_from := (_now - RECENT_SECONDS * _hz) / _hz - 1
	for second in _dealt_by_second.keys():
		if int(second) < recent_from:
			_dealt_by_second.erase(second)

# ---------------------------------------------------------------- results

func _skill_rows() -> Array:
	var ids: Array = []
	for id_ in _skill_meta:
		ids.append(String(id_))
	for id_ in _damage_raw:
		if not _skill_meta.has(String(id_)):
			ids.append(String(id_))
	var regex := RegEx.create_from_string(ID_PATTERN)
	var rows: Array = []
	for id_ in ids:
		if regex.search(id_) == null:
			continue
		var meta: Dictionary = _skill_meta.get(id_, {"got_tick": 0, "got_level": 1, "rank": 0, "evolved": false})
		rows.append({"id": id_, "got_tick": clampi(int(meta.got_tick), 0, LIMIT), "got_level": clampi(int(meta.got_level), 0, 99),
			"rank": clampi(int(meta.rank), 0, 99), "evolved": bool(meta.evolved),
			"damage": clampi(int(_damage_raw.get(id_, 0)) / _unit, 0, SKILL_DAMAGE_LIMIT), "kills": clampi(int(_kills_by_skill.get(id_, 0)), 0, LIMIT)})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.damage) != int(b.damage):
			return int(a.damage) > int(b.damage)
		return String(a.id) < String(b.id))
	if rows.size() > SKILL_ROWS_MAX:
		rows.resize(SKILL_ROWS_MAX)
	return rows

func _item_sources() -> Dictionary:
	var regex := RegEx.create_from_string(ID_PATTERN)
	var keys: Array = _items.keys()
	keys.sort()
	var result := {}
	for key in keys:
		if result.size() >= ITEM_SOURCES_MAX:
			break
		if regex.search(String(key)) != null:
			result[String(key)] = clampi(int(_items[key]), 0, LIMIT)
	return result

## The shape of `records.last` (T6 4.3), nothing more. Only valid after finish().
func to_last_record() -> Dictionary:
	var depth_ok := RegEx.create_from_string(DEPTH_PATTERN).search(depth) != null
	return {
		"depth": depth if depth_ok else "d1",
		"victory": _victory,
		"ticks": clampi(_ticks, 0, LIMIT),
		"kills": clampi(_kills, 0, LIMIT),
		"elite_kills": clampi(_elite_kills, 0, LIMIT),
		"champion_kills": clampi(_champion_kills, 0, CHAMPION_KILLS_MAX),
		"boss_kill": _boss_kill,
		"grade": clampi(_grade, 0, 4),
		"potions_used": clampi(_potions, 0, LIMIT),
		"damage_taken": clampi(_taken_raw / _unit, 0, LIMIT),
		"xp_gained": clampi(_xp, 0, LIMIT),
		# The core has no essence: it comes from salvaging gear in the stash, after the run. Always 0 here.
		"essence_gained": 0,
		"items": _item_sources(),
		"skills": _skill_rows(),
	}

## The read-only state for the result screen ({} until finish()). A copy: the caller cannot change the record through it.
func summary() -> Dictionary:
	return _summary.duplicate(true)

func _build_summary() -> Dictionary:
	var record := to_last_record()
	var total := 0
	for row in record.skills:
		total += int(row.damage)
	var rows: Array = []
	for row in record.skills:
		var span := maxi(1, _ticks - int(row.got_tick))
		var line: Dictionary = row.duplicate()
		line.share_bps = int(row.damage) * 10000 / maxi(1, total)
		# damage per second since the skill was got, in tenths (so the numbers stay integers)
		line.dps_tenths = int(row.damage) * _hz * 10 / span
		rows.append(line)
	var pairs: Array = []
	var keys: Array = _detonate.keys()
	keys.sort()
	for key in keys:
		var pair: Dictionary = _detonate[key].duplicate(true)
		pair.extra = int(pair.extra_raw) / _unit
		pair.erase("extra_raw")
		pairs.append(pair)
	var beats: Array = []
	for beat in _beats:
		beats.append({"id": beat.id, "tick": beat.tick, "kills": beat.kills, "taken": int(beat.taken_raw) / _unit, "damage": int(beat.damage_raw) / _unit})
	var recent_ticks := mini(_ticks, RECENT_SECONDS * _hz)
	var recent_raw := 0
	for second in _dealt_by_second:
		if int(second) * _hz >= _ticks - RECENT_SECONDS * _hz:
			recent_raw += int(_dealt_by_second[second])
	var result := {"ready": true, "record": record, "level": _final_level, "primary_id": _primary,
		"recent_window_ticks": recent_ticks, "recent_dps_tenths": recent_raw * _hz * 10 / _unit / maxi(1, recent_ticks), "total_damage": total, "dps_tenths": total * _hz * 10 / maxi(1, _ticks),
		"skills": rows, "pairs": pairs, "beats": beats, "picks": _picks.duplicate(true), "abandoned": _abandoned, "events_dropped": _events_dropped, "hit_events": _hit_events}
	result.loss = {} if _victory else _loss_material()
	return result

## What the last window before the fall can say: damage taken by kind, the number of living enemies, the last blow.
## A hit is matched to an attack event by position (hero_hit has no source field); what cannot be matched is "unattributed".
func _loss_material() -> Dictionary:
	var from_tick := _ticks - _window_ticks
	var by_kind := {}
	var attributed := 0
	var window_taken := 0
	var last_hit := {}
	var hp_low_bps := -1
	for hit in _hero_hits:
		if int(hit[0]) < from_tick:
			continue
		# hero_hit.hp_after_raw is the hero's real life right after the blow (-1 for an older event without it).
		if hit.size() > 4 and int(hit[4]) >= 0:
			var after_bps := int(hit[4]) * 10000 / _max_hp_raw
			hp_low_bps = after_bps if hp_low_bps < 0 else mini(hp_low_bps, after_bps)
		# The core names the source on the event since KS-3; the position match is only for events without it.
		var kind := String(hit[3]) if hit.size() > 3 and not String(hit[3]).is_empty() else _kind_of(int(hit[0]), hit[2])
		var row: Dictionary = by_kind.get(kind, {"hits": 0, "life": 0, "raw": 0})
		row.hits = int(row.hits) + 1
		row.raw = int(row.raw) + int(hit[1])
		by_kind[kind] = row
		window_taken += int(hit[1])
		if kind != "unattributed":
			attributed += 1
		last_hit = {"ticks_before_end": _ticks - int(hit[0]), "life": int(hit[1]) / _unit, "source": kind}
	var window_hits := 0
	for kind in by_kind:
		by_kind[kind].life = int(by_kind[kind].raw) / _unit
		by_kind[kind].erase("raw")
		window_hits += int(by_kind[kind].hits)
	var trend: Array = []
	var alive_peak := 0
	for sample in _samples:
		if int(sample[0]) >= from_tick:
			trend.append({"ticks_before_end": _ticks - int(sample[0]), "alive": int(sample[1]), "hp_bps": int(sample[2])})
			alive_peak = maxi(alive_peak, int(sample[1]))
	return {"window_ticks": _window_ticks, "taken": window_taken / _unit, "hits": window_hits, "by_source": by_kind,
		"attributed_bps": attributed * 10000 / maxi(1, window_hits), "alive_trend": trend, "alive_peak": alive_peak, "last_hit": last_hit, "hp_low_bps": hp_low_bps}

func _kind_of(tick: int, from: Variant) -> String:
	if not from is Vector2:
		return "unattributed"
	var best := "unattributed"
	var best_tick := -1
	for index in range(_attacks.size() - 1, -1, -1):
		var attack: Array = _attacks[index]
		if int(attack[0]) > tick or int(attack[0]) < tick - ATTRIBUTE_BACK_SECONDS * _hz:
			if int(attack[0]) < tick - ATTRIBUTE_BACK_SECONDS * _hz:
				break
			continue
		if (attack[1] as Vector2).distance_squared_to(from) <= ATTRIBUTE_DISTANCE_SQ and int(attack[0]) > best_tick:
			best = String(attack[2])
			best_tick = int(attack[0])
	return best
