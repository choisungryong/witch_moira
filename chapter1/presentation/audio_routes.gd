extends RefCounted
## Core event -> sound request. One mapping for the game (chapter1/app/chapter_one.gd) and for the request recorder
## (chapter1/tests/report_audio_requests.gd); nothing is copied. Read-only on the core: it gets the events of one tick and
## `run.spells` (the in-run spell document, {} while run_spells is off) and returns requests
##   [{cue, gain_db, source, ui, skill_id?, long?}]
## gain_db is the call's own trim in dB on top of GAINS[cue]. skill_id (cast, hit, shatter) lets a check see which skill a
## request came from. `slot` (T12 SL-A) names the sound slot of the moment ("skill.frost.shatter", "descent.arc.call"; "" = none,
## chapter1/data/audio_map.json `slots`), `targets` (arc cast only) the contacts of the chain; see SKILL_SLOTS and slot_of(). `long` marks the long detonation variant. The order of the result is the order of the events.
## The only state is the pulse habituation (docs/specs/AU-run-spells-sound-20261119.ko.md 3.1): when the previous ring pulse is
## near and had no pay-off (a kill by the ring, a cut, a detonation) the pulse is 1.5 dB quieter, up to 4.5 dB; a pay-off
## or a pause longer than 1.5 s puts it back to 0. No core random numbers are used.
## While run_spells is off the result is exactly what chapter_one.gd played before AU-RS1 (cast -> fire/cold/lightning,
## hit -> impact, ...), with gain_db 0.
## The new cue names (ring_body, ring_tail_<element>, ward_cut, detonate_<status>, interlock_<class>) have no files yet, so
## the player (combat_audio.gd) keeps them silent: no stream is loaded for a name that is not in COUNTS.
const SKILL_CUE := {"chapter1.skill.ember":"fire","chapter1.skill.frost":"cold","chapter1.skill.arc":"lightning"}
const DECAY_STEP_DB := 1.5
const DECAY_MAX_DB := 4.5
const STACK_WITHIN_TICKS := 72     # 1.2 s
const RESET_AFTER_TICKS := 90      # 1.5 s
const WEIGHT_MAX_DB := 3.0         # +1 dB per doubling of the targets (or of the detonations in one tick), at most +3
const CUT_PAIR_DB := 2.0           # two or more cuts in one tick
const LONG_DETONATION_AT := 4
const INTERLOCK_CLASSES := ["frozen","stunned","staggered"]    # "slowed" makes no sound (3.7)
## T12 SL-A: the slot of an event, from tables (no text is built while playing). Slot names are <group>.<target>.<moment>; the base skill
## and its evolution have a group each (ember/meteor, frost/blizzard, arc/thunderstorm). This table and slot_of() are the one place that
## says which event is which slot; audio_map.json `slots` says what each slot falls back to (its `parent`, today's sound name) and what
## was adopted. A request keeps its `cue` exactly as before: a slot only lets the player pick another file for it (combat_audio.gd:
## audition, then adopted, then the parent). Only the cold skill shatters. A table row is [base skill, evolved skill].
const SKILL_SLOTS := {
	"chapter1.skill.ember":{"cast":["skill.ember.cast","skill.meteor.cast"],"hit":["skill.ember.hit","skill.meteor.hit"]},
	"chapter1.skill.frost":{"cast":["skill.frost.cast","skill.blizzard.cast"],"hit":["skill.frost.hit","skill.blizzard.hit"],"shatter":["skill.frost.shatter","skill.blizzard.shatter"]},
	"chapter1.skill.arc":{"cast":["skill.arc.cast","skill.thunderstorm.cast"],"hit":["skill.arc.hit","skill.thunderstorm.hit"]}}
const DESCENT_SLOTS := {"descent_called":{"ember":"descent.ember.call","frost":"descent.frost.call","arc":"descent.arc.call"},
	"descent_released":{"ember":"descent.ember.sweep","frost":"descent.frost.sweep","arc":"descent.arc.sweep"},
	"descent_end":{"ember":"descent.ember.end","frost":"descent.frost.end","arc":"descent.arc.end"}}

## Slot handoff. chapter_one.gd plays a request as audio.play(request.cue,tick,request.gain_db) and does not pass the slot, so route()
## and late() keep the requests they just made (the same dictionaries, no copy) in the order they were made, and combat_audio.play()
## takes the next one when its cue is the cue of that request (take_handoff). route() starts the list over each tick. An explicit
## `slot` argument of play() wins, so a caller that passes it needs no handoff. Nothing here touches a core.
static var _pending: Array = []
static var _cursor := 0

static func take_handoff(cue: String) -> Dictionary:
	if _cursor < _pending.size():
		var request: Dictionary = _pending[_cursor]
		if String(request.cue) == cue:
			_cursor += 1
			return request
	return {}

## The slot of one event ("" when the event has none): skill moments by skill and evolution, the meteor landing, the three descent moments.
static func slot_of(event: Dictionary) -> String:
	match String(event.type):
		"cast","hit","shatter":
			var row: Array = SKILL_SLOTS.get(String(event.get("skill_id","")),{}).get(String(event.type),[])
			if row.is_empty(): return ""
			return row[1 if bool(event.get("evolved",false)) else 0]
		"explosion":
			return "skill.meteor.land" if event.has("meteor") else ""
		"descent_called","descent_released","descent_end":
			return DESCENT_SLOTS[String(event.type)].get(String(event.get("element","")),"")
	return ""

## Optional audition of the resolved contacts. No core state or random draws.
static func chain_bank() -> String:
	for bank in ["A", "B"]:
		if OS.get_cmdline_user_args().has("--chapter1-chain-audio=" + bank):
			return bank
	return ""

var _chain_preview := not chain_bank().is_empty()
var _last_pulse_tick := -100000
var _last_pulse_calm := false
var _decay_db := 0.0

func reset() -> void:
	_last_pulse_tick = -100000
	_last_pulse_calm = false
	_decay_db = 0.0

static func _request(cue: String,source: String,ui: bool=false,gain_db: float=0.0,slot: String="") -> Dictionary:
	return {"cue":cue,"gain_db":gain_db,"source":source,"ui":ui,"slot":slot}

static func _weight_db(n: int) -> float:
	if n < 2: return 0.0
	return snappedf(minf(WEIGHT_MAX_DB,log(float(n))/log(2.0)),.01)

## {ring spell id: element} from the spell document; {} while it is off.
static func ring_elements(spells: Dictionary) -> Dictionary:
	var rings := {}
	var all: Dictionary = spells.get("spells",{})
	for id_ in all:
		if String(all[id_].get("role","")) == "ring": rings[String(id_)] = String(all[id_].get("element",""))
	return rings

## Requests of the first pass (what chapter_one._consume_events__chapter played). `events` are the new events of this tick.
func route(events: Array,spells: Dictionary,tick: int) -> Array:
	var out := _route(events,spells,tick)
	_pending = out
	_cursor = 0
	return out

func _route(events: Array,spells: Dictionary,tick: int) -> Array:
	var out: Array = []
	var rings := ring_elements(spells)
	var on := not rings.is_empty()
	var facts: Dictionary = _facts(events,rings) if on else {}
	var seen := {}
	for event in events:
		match String(event.type):
			"cast":
				var id_ := String(event.skill_id)
				if on and rings.has(id_):
					_pulse(out,event,String(rings[id_]),facts,tick)
				else:
					var cue := String(SKILL_CUE.get(id_, "fire"))
					if _chain_preview and id_ == "chapter1.skill.arc":
						var contacts := mini(3, event.get("targets", []).size())
						if contacts > 0:
							cue = "arc_path_%d" % contacts
					var cast := _request(cue,"cast",false,0.0,slot_of(event))
					cast.skill_id = id_
					if id_ == "chapter1.skill.arc": cast.targets = event.get("targets", []).size()
					out.append(cast)
			"hit":
				var id_ := String(event.skill_id)
				if on and rings.has(id_): continue    # the ring pulse stands for its hits
				var hit := _request("impact","hit",false,0.0,slot_of(event))
				hit.skill_id = id_
				out.append(hit)
				var cls := String(event.get("vs_cc",""))
				if on and cls in INTERLOCK_CLASSES and not seen.has("i1:"+cls):
					seen["i1:"+cls] = true
					var over := _request("interlock_"+cls,"hit(vs_cc:%s)" % cls)
					over.skill_id = id_
					out.append(over)
			"stagger":
				if on and bool(event.get("cut",false)) and not seen.has("cut"):
					seen["cut"] = true
					out.append(_request("ward_cut","stagger(cut)",false,CUT_PAIR_DB if int(facts.cut) >= 2 else 0.0))
			"detonate":
				var status := String(event.status)
				if on and not seen.has("det:"+status):
					seen["det:"+status] = true
					var n: int = int(facts.det.get(status,1))
					var blast := _request("detonate_"+status,"detonate(%s)" % status,false,_weight_db(n))
					if n >= LONG_DETONATION_AT: blast.long = true
					out.append(blast)
			"death": out.append(_request("death","death"))
			"explosion": out.append(_request("explosion","explosion",false,0.0,slot_of(event)))
			"descent_called","descent_released","descent_end":
				# A slot with no sound of its own yet: cue "" makes no sound until a file is adopted for the slot.
				var moment := slot_of(event)
				if moment != "": out.append(_request("","descent",false,0.0,moment))
			"shatter":
				var shard := _request("cold","shatter",false,0.0,slot_of(event))
				shard.skill_id = String(event.skill_id)
				out.append(shard)
			"hero_hit": out.append(_request("hurt","hero_hit"))
			"item_drop": out.append(_request("drop","item_drop"))
			"item_pickup": out.append(_request("pickup","item_pickup"))
			"growth": out.append(_request("equip","growth",true))
	return out

## Requests of the second pass (chapter_one._consume_events), one event at a time.
func late(event: Dictionary) -> Array:
	var out := _late(event)
	if _cursor >= _pending.size():
		_pending = out
		_cursor = 0
	else: _pending.append_array(out)
	return out

func _late(event: Dictionary) -> Array:
	var out: Array = []
	match String(event.type):
		"item_drop":
			if event.item.slot in ["ring","charm"]: out.append(_request("jewel","item_drop(ring/charm)"))
			if event.item.quality in ["legendary","unique"]: out.append(_request("legend","item_drop(legendary/unique)"))
		"gate_opened": out.append(_request("equip","gate_opened",true))
		"chapter_burst": out.append(_request("explosion","chapter_burst"))
		"potion_used": out.append(_request("pickup","potion_used"))
		"ritual_completed": out.append(_request("equip","ritual_completed",true))
	return out

## What this tick's events say about the ring (read once, before the requests are made).
func _facts(events: Array,rings: Dictionary) -> Dictionary:
	var facts := {"cut":0,"stagger":0,"det":{},"det_total":0,"ring_kills":0,"frozen_hits":0,"ring_stuns":0}
	for event in events:
		match String(event.type):
			"stagger":
				facts.stagger += 1
				if bool(event.get("cut",false)): facts.cut += 1
			"detonate":
				var status := String(event.status)
				facts.det[status] = int(facts.det.get(status,0))+1
				facts.det_total += 1
			"death":
				if rings.has(String(event.get("skill_id",""))): facts.ring_kills += 1
			"hit":
				# The hit carries no "elite" flag, so a frozen ring hit on a strong enemy counts like any other (3.1 asks for !elite).
				if rings.has(String(event.get("skill_id",""))) and bool(event.get("frozen",false)): facts.frozen_hits += 1
			"stun":
				if rings.has(String(event.get("skill_id",""))) and not bool(event.get("elite",false)): facts.ring_stuns += 1
	return facts

func _pulse(out: Array,event: Dictionary,element: String,facts: Dictionary,tick: int) -> void:
	var payoff: bool = int(facts.ring_kills) > 0 or int(facts.cut) > 0 or int(facts.det_total) > 0
	var gap := tick-_last_pulse_tick
	if gap > RESET_AFTER_TICKS or not _last_pulse_calm: _decay_db = 0.0
	elif gap <= STACK_WITHIN_TICKS: _decay_db = minf(DECAY_MAX_DB,_decay_db+DECAY_STEP_DB)
	if payoff: _decay_db = 0.0
	_last_pulse_tick = tick
	_last_pulse_calm = not payoff
	var gain := snappedf(_weight_db(int(event.get("targets",[]).size()))-_decay_db,.01)
	var id_ := String(event.skill_id)
	var body := _request("ring_body","cast(ring)",false,gain)
	body.skill_id = id_
	out.append(body)
	var controlled := false
	match element:
		"ember": controlled = int(facts.stagger) > 0
		"frost": controlled = int(facts.frozen_hits) > 0
		"arc": controlled = int(facts.ring_stuns) > 0
	if controlled:
		var tail := _request("ring_tail_"+element,"cast(ring):tail",false,gain)
		tail.skill_id = id_
		out.append(tail)
