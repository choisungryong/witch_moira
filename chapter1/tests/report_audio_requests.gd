extends SceneTree
## Audio request recorder (check script, not product code). Plays one pilot run on the real core with no view
## and no audio device, and writes every sound request the game would make today, with its tick.
## The mapping repeats chapter1/app/chapter_one.gd (_consume_events__chapter, then _consume_events, then the
## step-distance cue) and the pilot's growth choice (the app plays "equip" from choose(); the pilot calls the core
## directly, so the request is added here at the choice tick as a model of a human choosing).
## The core is only read: nothing here writes core state, the profile, or the user folder.
## Rules (cooldown, voices, pitch, variants) are NOT applied here; tools/dev/audio_mix_offline.py applies them.
##   python tools/dev/godot.py --headless --path . --script res://chapter1/tests/report_audio_requests.gd -- --seed=11 --primary=chapter1.skill.ember --out=_local/audio/requests/req_ember.json
const Core = preload("res://chapter1/core/chapter_core.gd")
const Pilot = preload("res://chapter1/core/chapter_pilot.gd")
const SKILL_CUE := {"chapter1.skill.ember":"fire","chapter1.skill.frost":"cold","chapter1.skill.arc":"lightning"}

var requests: Array = []                 # [tick, cue, ui(0/1), playing(0/1), source]
var by_source: Dictionary = {}           # source -> {cue -> n}
var event_counts: Dictionary = {}

func _initialize() -> void:
	call_deferred("execute")

func _request(cue: String, tick: int, ui: bool, playing: bool, source: String) -> void:
	requests.append([tick, cue, 1 if ui else 0, 1 if playing else 0, source])
	if not by_source.has(source): by_source[source] = {}
	by_source[source][cue] = int(by_source[source].get(cue, 0)) + 1

func execute() -> void:
	var seed_ := 11
	var primary := "chapter1.skill.ember"
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_ = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--primary="): primary = arg.trim_prefix("--primary=")
		elif arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	if out != "" and not out.begins_with("_local/"):
		push_error("--out must be under _local/"); quit(2); return
	var run = Core.new()
	var pilot = Pilot.new()
	pilot.run = run
	if not run.start(seed_, primary):
		push_error(str(run.errors)); quit(2); return
	var guard := 0
	var last_seq := -1
	var prev: Vector2 = run.hero.position
	var step_dist := 0.0
	var windup_prev: Dictionary = {}
	var windup_starts := 0
	var low_hp_cross := 0
	var was_low := false
	while run.mode not in ["victory", "defeat"] and guard < 12 * 60 * 60 + 500:
		var picks_before: int = pilot.selections.size()
		var movement: Vector2 = pilot.decide()
		if pilot.selections.size() > picks_before:
			_request("equip", run.tick, true, false, "choose")
		run.step(movement)
		guard += 1
		var playing: bool = run.mode == "playing"
		var tick: int = run.tick
		var fresh: Array = []
		for event in run.events:
			if int(event.seq) <= last_seq: continue
			last_seq = int(event.seq)
			fresh.append(event)
			var t := String(event.type)
			event_counts[t] = int(event_counts.get(t, 0)) + 1
		# pass 1: _consume_events__chapter
		for event in fresh:
			var t := String(event.type)
			match t:
				"cast": _request(SKILL_CUE.get(event.skill_id, "fire"), tick, false, playing, t)
				"hit": _request("impact", tick, false, playing, t)
				"death": _request("death", tick, false, playing, t)
				"explosion": _request("explosion", tick, false, playing, t)
				"shatter": _request("cold", tick, false, playing, t)
				"hero_hit": _request("hurt", tick, false, playing, t)
				"item_drop": _request("drop", tick, false, playing, t)
				"item_pickup": _request("pickup", tick, false, playing, t)
				"growth": _request("equip", tick, true, playing, t)
		# pass 2: _consume_events
		for event in fresh:
			var t := String(event.type)
			match t:
				"item_drop":
					if event.item.slot in ["ring", "charm"]: _request("jewel", tick, false, playing, "item_drop(ring/charm)")
					if event.item.quality in ["legendary", "unique"]: _request("legend", tick, false, playing, "item_drop(legendary/unique)")
				"gate_opened": _request("equip", tick, true, playing, t)
				"chapter_burst": _request("explosion", tick, false, playing, t)
				"potion_used": _request("pickup", tick, false, playing, t)
				"ritual_completed": _request("equip", tick, true, playing, t)
		if playing:
			step_dist += run.hero.position.distance_to(prev)
			if step_dist > 1.15:
				_request("step", tick, false, playing, "step_distance")
				step_dist = 0.0
		prev = run.hero.position
		for e in run.enemies.values():
			var w: bool = String(e.get("state", "")) == "windup" and int(e.hp_raw) > 0
			if w and not windup_prev.get(e.id, false): windup_starts += 1
			windup_prev[e.id] = w
		var hp_ratio: float = float(run.hero.hp_raw) / maxf(1.0, float(run.hero.max_hp_raw))
		if hp_ratio < .3 and not was_low: low_hp_cross += 1; was_low = true
		elif hp_ratio > .5: was_low = false
	var report := {
		"seed": seed_, "primary": primary, "mode": run.mode, "ticks": run.tick, "seconds": run.tick / 60.0,
		"kills": run.kills, "events": event_counts, "requests_by_source": by_source,
		"request_count": requests.size(), "windup_starts": windup_starts, "low_hp_30_crossings": low_hp_cross,
		"note": "playing=0 requests are dropped by the player unless ui=1; tick is run.tick (does not advance in choice screens)",
		"requests": requests,
	}
	var summary := report.duplicate()
	summary.erase("requests")
	print("AUDIO_REQUEST_LOG ", JSON.stringify(summary))
	if out != "":
		var path := ProjectSettings.globalize_path("res://" + out)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(report))
		f.close()
	quit(0)
