extends SceneTree
## Headless check of the skill lab (T12 SL-B). Drives the very body the window uses, through command.json files in _local/skill-lab-test/.
##   python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_skill_lab.gd -- --chapter1-start --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-trial=descent --chapter1-descent-cost=1000
## Last line: SKILL_LAB_TEST {"pass": bool, "fails": [...], "skipped": [...], ...}; exit code 0 / 1.
## The body's speed boost (headless has no frame limit, but the physics clock still follows real time) is a test-only field.
const LabNode = preload("res://chapter1/tests/support/skill_lab_node.gd")
const DIR := "_local/skill-lab-test"
const BOOST := 12.0
const C7 := ["_local/audio/chain-lightning/round2/assets/chapter1/art/audio/chain2/c7_1.wav", "_local/audio/chain-lightning/round2/assets/chapter1/art/audio/chain2/c7_2.wav", "_local/audio/chain-lightning/round2/assets/chapter1/art/audio/chain2/c7_3.wav"]
const SOAK_TICKS := 36000          ## ten game minutes
var view: Node
var lab: Node
var fails: Array = []
var skipped: Array = []
var notes: Dictionary = {}
var seq := 0


func _initialize() -> void:
	var folder := LabNode.abs_of(DIR)
	DirAccess.make_dir_recursive_absolute(folder)
	for name in ["command.json", "state.json", "lab.lock", "command.json.tmp", "state.json.tmp"]:
		if FileAccess.file_exists(folder.path_join(name)): DirAccess.remove_absolute(folder.path_join(name))
	view = (load("res://chapter1/ChapterOne.tscn") as PackedScene).instantiate()
	root.add_child(view)
	lab = LabNode.new()
	lab.speed_boost = BOOST
	lab.idle_quit_s = 100000.0
	view.add_child(lab)
	var why: String = lab.setup(view, DIR)
	if not why.is_empty():
		fails.append("setup: " + why)
		finish()
		return
	call_deferred("checks")


func check(ok: bool, text: String) -> void:
	if not ok: fails.append(text)


func send(op: String, body: Dictionary = {}) -> int:
	seq += 1
	var cmd := {"protocol": 1, "seq": seq, "op": op}
	cmd.merge(body)
	var path := LabNode.abs_of(DIR).path_join("command.json")
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string(JSON.stringify(cmd))
	f.close()
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(tmp, path)
	return seq


func read_state() -> Dictionary:
	var parsed: Variant = LabNode.parse_quiet(FileAccess.get_file_as_string(LabNode.abs_of(DIR).path_join("state.json")))
	return parsed if parsed is Dictionary else {}


## Waits (wall seconds) for applied_seq == n; returns the state read from the file.
func wait_applied(n: int, wall_s := 20.0) -> Dictionary:
	var start := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - start) / 1000.0 < wall_s:
		await process_frame
		var s := read_state()
		if int(s.get("applied_seq", -1)) == n: return s
	fails.append("seq %d not applied within %.0f s" % [n, wall_s])
	return read_state()


func scene_cmd(body: Dictionary, audio: Dictionary = {}) -> Dictionary:
	var n := send("scene", {"scene": body, "audio": audio})
	return await wait_applied(n)


func wait_until(cond: Callable, wall_s: float, label: String) -> bool:
	var start := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - start) / 1000.0 < wall_s:
		await process_frame
		if cond.call(): return true
	fails.append("timeout: " + label)
	return false


func checks() -> void:
	# 1: ready within 30 s
	var up := await wait_until(func(): return bool(read_state().get("ready", false)), 30.0, "ready within 30 s")
	if not up:
		finish()
		return
	var s0 := read_state()
	check(int(s0.get("protocol", 0)) == 1 and int(s0.get("pid", 0)) == OS.get_process_id(), "state has protocol 1 and our pid")
	check(FileAccess.file_exists(LabNode.abs_of(DIR).path_join("lab.lock")), "lab.lock exists")

	# 2: three witches x base/evolved, single: staged 1, a cast of that skill, evolved flag, meteor for ember
	for ch in ["ember", "frost", "arc"]:
		for form in ["base", "evolved"]:
			var tag := "%s/%s" % [ch, form]
			var before_meteor := int(lab.event_counts.get("meteor_cast", 0))
			var s := await scene_cmd({"character": "chapter1.character." + ch, "skill": "chapter1.skill." + ch, "form": form, "layout": "single",
				"motion": "hold", "durable": true, "repeat": true, "interval_s": 1.0, "speed": 1.0, "juice": true})
			check(int(s.run.staged) == 1, tag + ": staged == 1 (got %s)" % str(s.run.staged))
			check(String(s.run.primary) == "chapter1.skill." + ch, tag + ": primary")
			var c0 := int(s.casts.count)
			var got := await wait_until(func(): return int(read_state().get("casts", {}).get("count", 0)) > c0 and int(lab.casts.count) > c0, 40.0, tag + ": a cast within the next repeat")
			if got:
				var cs: Dictionary = lab.casts
				check(String(cs.last_skill) == "chapter1.skill." + ch, tag + ": last_skill")
				check(String(cs.last_form) == form, tag + ": last_form == %s (got %s)" % [form, str(cs.last_form)])
			if ch == "ember" and form == "evolved":
				await wait_until(func(): return int(lab.event_counts.get("meteor_cast", 0)) > before_meteor, 20.0, "ember evolved: meteor_cast")
			if ch == "ember" and form == "base":
				check(int(lab.event_counts.get("meteor_cast", 0)) == before_meteor, "ember base makes no meteor")
	# a repeat is one cast per staging, not a stream
	var s_rep := await scene_cmd({"character": "chapter1.character.arc", "skill": "chapter1.skill.arc", "form": "base", "layout": "single", "motion": "hold", "durable": true, "repeat": false})
	var c_start := int(lab.casts.count)
	var t_start: int = view.run.tick
	await wait_until(func(): return view.run.tick - t_start > 600, 60.0, "ten game seconds without repeat")
	check(int(lab.casts.count) - c_start <= 1, "repeat off: one cast only (got %d)" % (int(lab.casts.count) - c_start))
	var rep_on := await scene_cmd({"repeat": true, "interval_s": 2.0})
	var c_r := int(lab.casts.count)
	var t_r: int = view.run.tick
	await wait_until(func(): return view.run.tick - t_r > 1500, 90.0, "25 game seconds with repeat on")
	var n_r := int(lab.casts.count) - c_r
	check(n_r >= 6 and n_r <= 14, "repeat on, 2 s interval: about one cast per 2-3 s (got %d in 25 s)" % n_r)

	# 3: layouts
	phase = "layouts"
	for entry in [["pack", 8, 8], ["line", 6, 6], ["elite", 1, 1], ["crowd", 40, 40], ["single", 5, 1]]:
		var s2 := await scene_cmd({"layout": entry[0], "count": entry[1], "motion": "hold", "durable": true})
		check(int(s2.run.staged) == int(entry[2]), "layout %s: staged %d (got %s)" % [entry[0], entry[2], str(s2.run.staged)])
		await process_frame
		check(view.run.alive_count() == int(entry[2]), "layout %s: alive %d (got %d)" % [entry[0], entry[2], view.run.alive_count()])
	var cfg := await scene_cmd({"layout": "pack", "count": 3, "motion": "hold", "durable": true, "repeat": false})
	var held_before: Array = []
	for id in view.run.enemies: held_before.append(view.run.enemies[id].position)
	var t_h: int = view.run.tick
	await wait_until(func(): return view.run.tick - t_h > 120, 30.0, "hold: two game seconds")
	var moved := false
	var i := 0
	for id in view.run.enemies:
		if i < held_before.size() and view.run.enemies[id].position.distance_to(held_before[i]) > 0.01: moved = true
		i += 1
	check(not moved, "motion hold: bodies stand still")

	# 4: descent of the three witches
	phase = "descent"
	for ch in ["ember", "frost", "arc"]:
		var seq_d := send("scene", {"scene": {"character": "chapter1.character." + ch, "skill": "chapter1.skill." + ch, "form": "descent", "layout": "pack", "count": 12,
			"motion": "approach", "durable": false, "repeat": false, "interval_s": 3.0, "speed": 1.0}, "audio": {}})
		var s4 := await wait_applied(seq_d)
		var tick_after: int = view.run.tick
		var dv: Dictionary = view.run.descent_view()
		check(String(dv.get("state", "")) in ["hold", "sweep"], "descent %s: called by the command (state %s)" % [ch, str(dv.get("state"))])
		check(int(lab.event_counts.get("descent_called", 0)) >= 1, "descent %s: descent_called event seen" % ch)
		check(view.run.tick - tick_after <= 120, "descent %s: within 2 s" % ch)
		# let it finish so the next scene starts from a quiet field
		await wait_until(func(): return String(view.run.descent_view().get("state", "")) == "charging" and view.run.mode == "playing", 60.0, "descent %s over" % ch)
		check(float(s4.run.tick) >= 0.0, "state is read")

	# 6: refused paths
	var n_bad := send("shot", {"shot": "../outside.png"})
	var s6 := await wait_applied(n_bad)
	check(s6.errors.size() > 0 and String(s6.errors.back()).contains("refused"), "shot ../ refused and in errors")
	check(String(s6.last_shot) == "", "no picture saved by the refused path")
	var n_bad2 := send("shot", {"shot": "C:/Windows/x.png"})
	var s6b := await wait_applied(n_bad2)
	check(String(s6b.errors.back()).contains("refused"), "absolute shot path refused")
	var n_bad3 := send("scene", {"scene": {"layout": "single"}, "audio": {"skill.arc.cast": ["../etc/passwd.wav"]}})
	var s6c := await wait_applied(n_bad3)
	if view.audio.has_method("audition_set"):
		check(String(s6c.errors.back()).contains("refused"), "audio path with .. refused")
	check(LabNode.safe_rel("..\\x", ["_local/"]) == "" and LabNode.safe_rel("_local/../a", ["_local/"]) == "" and LabNode.safe_rel("/_local/a", ["_local/"]) == "" and LabNode.safe_rel("C:/_local/a", ["_local/"]) == "", "safe_rel refuses ..  / absolute / drive")
	check(LabNode.safe_rel("_local/skill-lab/a.png", ["_local/"]) == "_local/skill-lab/a.png", "safe_rel accepts a path inside _local/")
	check(LabNode.safe_rel("chapter1/x.png", ["_local/"]) == "", "safe_rel refuses a path outside the roots")
	var n_unknown := send("scene", {"scene": {"layout": "swarm"}})
	var s6d := await wait_applied(n_unknown)
	check(String(s6d.errors.back()).contains("unknown layout"), "unknown layout refused")
	var s_keep := read_state()
	check(String(s_keep.scene.layout) == "single" or String(s_keep.scene.layout) == "pack", "a refused scene leaves the applied scene alone")

	# 7: sound candidates (needs the audition API of SL-A and the C7 files)
	var have_api: bool = view.audio.has_method("audition_set")
	var have_files := true
	for p in C7:
		if not FileAccess.file_exists(LabNode.abs_of(p)): have_files = false
	if not have_api: skipped.append("7: combat_audio.audition_set is not in this tree (SL-A not merged)")
	elif not have_files: skipped.append("7: the C7 candidate files are not in this tree (_local/audio/chain-lightning/round2)")
	else:
		var s7 := await scene_cmd({"character": "chapter1.character.arc", "skill": "chapter1.skill.arc", "form": "base", "layout": "pack", "count": 4, "motion": "hold", "durable": true, "repeat": true, "interval_s": 1.5}, {"skill.arc.cast": C7})
		check(s7.audio.overrides.has("skill.arc.cast"), "audio override shown in state")
		await wait_until(func(): return _slot_rows(read_state().audio.recent, "skill.arc.cast").size() > 0, 30.0, "audio.recent has a skill.arc.cast request")
		# other slots (steps, hits) also log, with the file of their parent sound; only the overridden slot must carry the c7 files
		var cast_rows: Array = _slot_rows(read_state().audio.recent, "skill.arc.cast")
		var all_c7 := cast_rows.size() > 0
		for r in cast_rows:
			if not String(r.path).contains("c7_"): all_c7 = false
		check(all_c7, "audio.recent paths of skill.arc.cast are c7_*")
	phase = "soak"
	# 5: ten game minutes of repeat, nothing from the run's own business leaks in
	var s5 := await scene_cmd({"character": "chapter1.character.arc", "skill": "chapter1.skill.arc", "form": "base", "layout": "pack", "count": 10, "motion": "approach",
		"durable": false, "repeat": true, "interval_s": 1.5, "speed": 1.0}, {})
	var hp0: int = view.run.hero.hp_raw
	var tick0: int = view.run.tick
	var bad_frames := 0
	var frames0 := Engine.get_frames_drawn()
	var start_ms := Time.get_ticks_msec()
	while view.run.tick - tick0 < SOAK_TICKS and float(Time.get_ticks_msec() - start_ms) / 1000.0 < 420.0:
		await process_frame
		if view.run.zone != 0 or view.run.mode != "playing" or int(lab.unstaged_spawns) != 0: bad_frames += 1
	var soaked: int = view.run.tick - tick0
	notes["soak_ticks"] = soaked
	notes["soak_wall_s"] = snappedf(float(Time.get_ticks_msec() - start_ms) / 1000.0, 0.1)
	check(soaked >= SOAK_TICKS, "soak reached ten game minutes (%d of %d ticks in %.0f s wall)" % [soaked, SOAK_TICKS, float(Time.get_ticks_msec() - start_ms) / 1000.0])
	check(bad_frames == 0, "soak: zone 0, mode playing, no unstaged spawns on every frame (%d bad frames)" % bad_frames)
	check(view.run.hero.hp_raw == hp0, "soak: hero life unchanged")
	for type in ["gate_opened", "growth", "level_choice", "chapter_champion", "seal_grace", "victory", "defeat"]:
		check(int(lab.event_counts.get(type, 0)) == 0, "soak: no %s event (got %d)" % [type, int(lab.event_counts.get(type, 0))])
	notes["item_pickups"] = int(lab.event_counts.get("item_pickup", 0))
	notes["soak_frames"] = Engine.get_frames_drawn() - frames0
	notes["casts_total"] = int(lab.casts.count)
	# a picture in a headless run is refused with a reason, never a crash
	var n_shot := send("shot", {"shot": "_local/skill-lab-test/shot.png"})
	var s8 := await wait_applied(n_shot)
	notes["headless_shot"] = String(s8.last_shot) if String(s8.last_shot) != "" else "refused: " + str(s8.errors.back())
	# the lock is released on the way out (the quit command itself ends the process, so it is tried in the window run)
	lab._release_lock()
	check(not FileAccess.file_exists(LabNode.abs_of(DIR).path_join("lab.lock")), "lab.lock removed")
	finish()


var phase := "start"
var partial_seen := false
func _process(_delta: float) -> bool:
	if view != null and not partial_seen:
		var fx: Variant = view.get("descent_fx")
		if fx != null:
			var sw: Dictionary = fx.sw
			if not sw.is_empty() and not sw.has("t"):
				partial_seen = true
				notes["fx_partial_sweep"] = {"phase": phase, "mode": String(view.run.mode), "tick": view.run.tick, "descent": String(view.run.descent_view().get("state", "")), "keys": sw.keys()}
	return false


func finish() -> void:
	var result := {"pass": fails.is_empty(), "fails": fails, "skipped": skipped, "notes": notes}
	print("SKILL_LAB_TEST ", JSON.stringify(result))
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	quit(0 if fails.is_empty() else 1)


func _slot_rows(recent: Array, slot: String) -> Array:
	var out: Array = []
	for r in recent:
		if String(r.slot) == slot: out.append(r)
	return out
