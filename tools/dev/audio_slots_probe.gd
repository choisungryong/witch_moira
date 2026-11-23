extends SceneTree
## Headless probe of the sound slots (T12 SL-A). Check tool, not product code; it only reads and plays, nothing is written.
## tools/dev/test_audio_adopt.py runs it (also inside a temporary copy of the project: --path <root>), and it can be run by hand:
##   python tools/dev/godot.py --headless --path . --script res://tools/dev/audio_slots_probe.gd -- --mode=routes
##   python tools/dev/godot.py --headless --path . --script res://tools/dev/audio_slots_probe.gd -- --mode=play --cue=lightning --slot=skill.arc.cast --targets=3
## Modes (the last line is `AUDIO_SLOTS_PROBE {json}`, exit code 0):
##   routes   every event that has a slot is routed; reports the slots that are not in audio_map.json `slots` and the slots whose
##            `parent` is not the cue of the request (both lists must be empty), and the count of slots with a parent / without
##   play     builds combat_audio.gd on an empty node and plays one request {cue, slot, targets} with audio_map.json as it is:
##            which voice started, whether its stream is the adopted file (index) and the adopted paths of the slot
##   audition play, after audition_set(slot, --paths=a;b;c): the log entry and the result of audition_set
##   bench    microseconds per tick of the audio code only (route() + play() of each request, no core): a tick of 12 events of the mix
##            of a busy fight (casts, hits, deaths, an explosion), --n=20000 ticks, muted voices not involved. Uses only calls the old code
##            has too (route, play), so the same probe runs on the code before SL-A in a copy of the project.
##   run      one pilot run on the real core (--seed=11 --primary=chapter1.skill.ember), the game's own order (route(), late() per event,
##            audio.play(cue, tick, gain_db) for each request): requests per slot, per cue, and the microseconds the audio calls took
##            per tick. Needs the whole project (not the small copy of the other modes).
##   handoff  plays what the game would play for one tick of events (route(), then audio.play(cue, tick, gain_db) with no slot argument,
##            as chapter_one.gd does): a frost cast and a frost shatter (both cue "cold"), a plain explosion and a meteor landing (both
##            cue "explosion"), an arc cast and hit, one tick apart; audition_set was given a file for skill.frost.shatter, skill.meteor.land and skill.arc.cast
##            (--paths=a;b;c, three files, used for each). The log must show each file only at its own slot.
const Audio = preload("res://chapter1/presentation/combat_audio.gd")
const Routes = preload("res://chapter1/presentation/audio_routes.gd")

func _initialize() -> void:
	call_deferred("execute")

func _arg(name: String, fallback: String = "") -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name): return arg.trim_prefix("--%s=" % name)
	return fallback

func execute() -> void:
	var mode := _arg("mode", "routes")
	var result := {}
	match mode:
		"routes": result = _routes()
		"play", "audition": result = _play(mode == "audition")
		"handoff": result = _handoff()
		"bench": result = _bench()
		"run": result = _run()
		_: result = {"error": "unknown mode " + mode}
	print("AUDIO_SLOTS_PROBE ", JSON.stringify(result))
	quit(0)

func _audio() -> Array:
	var view := Node3D.new()
	root.add_child(view)
	var audio = Audio.new()
	audio.setup(view)
	audio.set_paused(false)
	return [audio, view]

func _routes() -> Dictionary:
	var audio = _audio()[0]
	var events: Array = []
	for id_ in Routes.SKILL_SLOTS:
		for evolved in [false, true]:
			for kind in ["cast", "hit", "shatter"]:
				events.append({"type": kind, "skill_id": id_, "evolved": evolved, "targets": [Vector2.ZERO, Vector2.ONE]})
	events.append({"type": "explosion", "meteor": 3})
	events.append({"type": "explosion"})
	for kind in ["descent_called", "descent_released", "descent_end"]:
		for element in ["ember", "frost", "arc"]: events.append({"type": kind, "element": element})
	var routes = Routes.new()
	var requests: Array = routes.route(events, {}, 100)
	var missing := []
	var mismatched := []
	var slots_seen := {}
	for r in requests:
		var slot := String(r.slot)
		if slot.is_empty(): continue
		slots_seen[slot] = true
		if not audio.slot_table.has(slot): missing.append(slot); continue
		if String(audio.slot_table[slot].parent) != String(r.cue): mismatched.append([slot, r.cue, audio.slot_table[slot].parent])
	var unrouted := []
	for slot in audio.slot_table:
		if not slots_seen.has(slot): unrouted.append(slot)
	var with_parent := 0
	for slot in audio.slot_table:
		if not String(audio.slot_table[slot].parent).is_empty(): with_parent += 1
	return {"requests": requests.size(), "slots_in_table": audio.slot_table.size(), "with_parent": with_parent, "routed_slots": slots_seen.size(),
		"missing_in_table": missing, "parent_not_cue": mismatched, "table_slots_no_event": unrouted, "map_errors": audio.map_errors}

func _play(audition: bool) -> Dictionary:
	var built = _audio()
	var audio = built[0]
	var slot := _arg("slot")
	var out := {"slot": slot, "slot_known": audio.slot_table.has(slot), "adopted_paths": audio.adopted_paths.get(slot, []), "map_errors": audio.map_errors}
	if audition:
		var paths: Array = []
		for item in _arg("paths").split(";", false): paths.append(item)
		out["audition_set"] = audio.audition_set(slot, paths)
	var before: int = audio.played
	audio.play(_arg("cue"), int(_arg("tick", "100")), 0.0, slot, int(_arg("targets", "0")))
	out["played"] = int(audio.played) - before
	var started := -1
	var which := -1
	for i in range(1, audio.voices.size()):
		if audio.voices[i].playing and audio.voices[i].stream != null:
			started = i
			var list: Array = audio.adopted.get(slot, [])
			which = list.find(audio.voices[i].stream)
			out["pitch_scale"] = audio.voices[i].pitch_scale
			break
	out["voice"] = started
	out["adopted_index"] = which
	out["log"] = audio.audition_log
	return out

func _handoff() -> Dictionary:
	var audio = _audio()[0]
	var paths: Array = []
	for item in _arg("paths").split(";", false): paths.append(item)
	var sets := {}
	for slot in ["skill.frost.shatter", "skill.meteor.land", "skill.arc.cast"]: sets[slot] = audio.audition_set(slot, paths).ok
	var routes = Routes.new()
	var events := [
		{"type": "cast", "skill_id": "chapter1.skill.frost", "evolved": false, "targets": []},
		{"type": "shatter", "skill_id": "chapter1.skill.frost", "evolved": false},
		{"type": "explosion"},
		{"type": "explosion", "meteor": 4},
		{"type": "cast", "skill_id": "chapter1.skill.arc", "evolved": false, "targets": [Vector2.ZERO, Vector2.ONE]},
		{"type": "hit", "skill_id": "chapter1.skill.arc", "evolved": false}]
	var played := []
	var tick := 500
	for event in events:    # one tick each, so that the cooldown of a shared cue ("cold", "explosion") does not hide the second sound
		var requests: Array = routes.route([event], {}, tick)
		for r in requests:
			if r.ui: audio.play_ui(r.cue, tick)
			else: audio.play(r.cue, tick, r.gain_db)
			played.append([r.cue, r.slot])
		tick += 30
	return {"audition_sets": sets, "requests": played, "log": audio.audition_log}

func _bench() -> Dictionary:
	var audio = _audio()[0]
	var routes = Routes.new()
	var n := int(_arg("n", "20000"))
	var ticks := []
	for k in 8:
		ticks.append([
			{"type": "cast", "skill_id": "chapter1.skill.arc", "targets": [Vector2.ZERO, Vector2.ONE]}, {"type": "hit", "skill_id": "chapter1.skill.arc"},
			{"type": "hit", "skill_id": "chapter1.skill.arc"}, {"type": "hit", "skill_id": "chapter1.skill.ember"}, {"type": "hit", "skill_id": "chapter1.skill.frost"},
			{"type": "death"}, {"type": "death"}, {"type": "death"}, {"type": "explosion"}, {"type": "shatter", "skill_id": "chapter1.skill.frost"},
			{"type": "cast", "skill_id": "chapter1.skill.ember"}, {"type": "hero_hit"}])
	var requests := 0
	var start := Time.get_ticks_usec()
	for i in n:
		var tick := 1000 + i * 3
		for r in routes.route(ticks[i % 8], {}, tick):
			requests += 1
			audio.play(r.cue, tick, r.gain_db)
	var elapsed := Time.get_ticks_usec() - start
	return {"ticks": n, "requests": requests, "usec_per_tick": snappedf(float(elapsed) / float(n), 0.01), "voices_started": audio.played}

func _run() -> Dictionary:
	var audio = _audio()[0]
	var run = load("res://chapter1/core/chapter_core.gd").new()    # loaded here: the small project copies of the other modes have no core
	var pilot = load("res://chapter1/core/chapter_pilot.gd").new()
	pilot.run = run
	var routes = Routes.new()
	if not run.start(int(_arg("seed", "11")), _arg("primary", "chapter1.skill.ember")): return {"error": str(run.errors)}
	var by_slot := {}
	var by_cue := {}
	var last_seq := -1
	var ticks := 0
	var usec := 0
	while run.mode not in ["victory", "defeat"] and ticks < 12 * 60 * 60 + 500:
		var movement: Vector2 = pilot.decide()
		run.step(movement)
		ticks += 1
		var tick: int = run.tick
		audio.set_paused(run.mode != "playing")
		var fresh: Array = []
		for event in run.events:
			if int(event.seq) <= last_seq: continue
			last_seq = int(event.seq)
			fresh.append(event)
		var requests: Array = []
		var t0 := Time.get_ticks_usec()
		requests.append_array(routes.route(fresh, run.spells, tick))
		usec += Time.get_ticks_usec() - t0
		for r in requests:
			t0 = Time.get_ticks_usec()
			if r.ui: audio.play_ui(r.cue, tick)
			else: audio.play(r.cue, tick, r.gain_db)
			usec += Time.get_ticks_usec() - t0
			by_cue[r.cue] = int(by_cue.get(r.cue, 0)) + 1
			if not String(r.slot).is_empty(): by_slot[r.slot] = int(by_slot.get(r.slot, 0)) + 1
		for event in fresh:
			t0 = Time.get_ticks_usec()
			var late: Array = routes.late(event)
			for r in late:
				if r.ui: audio.play_ui(r.cue, tick)
				else: audio.play(r.cue, tick, r.gain_db)
				by_cue[r.cue] = int(by_cue.get(r.cue, 0)) + 1
			usec += Time.get_ticks_usec() - t0
	return {"ticks": ticks, "kills": run.kills if "kills" in run else -1, "mode": run.mode, "requests_by_slot": by_slot, "requests_by_cue": by_cue,
		"audio_usec_per_tick": snappedf(float(usec) / float(maxi(ticks, 1)), 0.001), "voices_started": audio.played, "voices_dropped": audio.dropped}
