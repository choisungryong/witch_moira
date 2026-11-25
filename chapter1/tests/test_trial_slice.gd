extends SceneTree
## S1-A (docs/specs/T14-slice-s1-20261125.ko.md 4): the "one run" trial is ONE definition that the app, the checks and the measurement read.
## (a) three witches start under it, (b) only the arc has the kit, (c) the equipment switches are all on in ONE set of tables, (d) the rhythm values are the data
## file's own and the old `pace` path gives the same ones, (e) the sustain trial and the grace block stay off, (f) a wrong document is refused,
## (g) the profile reads the arc's element tree under use_for_profile(), plus the read-only values the kit screen asked for (A-element-kit-screen 9),
## the kit's detonation points for the descent (C5), the verdict's kit weights (C6) and the boss shortcut with the kit (9.3).
## Needs no user save; writes only under _local/. Marker: CHAPTER1_TRIAL_SLICE_RESULT.
const Chapter = preload("res://chapter1/core/chapter_core.gd")
const TrialSlice = preload("res://chapter1/app/trial_slice.gd")
const TrialPace = preload("res://chapter1/app/trial_pace.gd")
const SliceDocs = preload("res://chapter1/tests/support/slice_docs.gd")
const TrialDocs = preload("res://chapter1/tests/support/trial_docs.gd")
const Kit = preload("res://chapter1/core/element_kit.gd")
const Profile = preload("res://chapter1/core/chapter_profile.gd")
const Progression = preload("res://chapter1/core/character_progression.gd")
const Tuning = preload("res://chapter1/core/combat_tuning.gd")
const PILOT := "res://chapter1/core/chapter_pilot.gd"
const EMBER := "chapter1.skill.ember"
const FROST := "chapter1.skill.frost"
const ARC := "chapter1.skill.arc"
const ROD := "chapter1.skill.arc_rod"
const OVERLOAD := "chapter1.skill.arc_overload"
const TEMP_DIR := "res://_local/test_trial_slice"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("execute")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

## A value as JSON text after one round trip, so 4 and 4.0 read the same (the data file's numbers are floats until a validator makes them whole).
func canon(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

func shipped_slice() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(TrialSlice.DOC_PATH))

func started(primary: String, seed_: int = 11) -> RefCounted:
	var run = Chapter.new()
	var problem := SliceDocs.enable_slice_problem(run)
	check(problem.is_empty(), "the trial hands itself to a %s run: %s" % [primary, problem])
	if not problem.is_empty(): return null
	check(run.start(seed_, primary), "start() under the trial for %s: %s" % [primary, str(run.errors)])
	return run

func execute() -> void:
	part_start()
	part_values()
	part_refused()
	part_profile()
	part_kit_view()
	part_card_open()
	part_descent_points()
	part_verdict()
	part_skip()
	check_sources_unchanged()
	print("CHAPTER1_TRIAL_SLICE_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

## (a)(b)(c)(e)
func part_start() -> void:
	var views := {}
	for primary in [EMBER, FROST, ARC]:
		var run = started(primary)
		if run == null: continue
		views[primary] = run.kit_view()
		check(run.loot.affix_rolls_on() and run.loot.pity_on() and run.loot.verdict_on() and run.loot.luck_on(), "(c) %s: affix rolls, pity, verdict v2 and luck are all on in the one loot table" % primary)
		check(not bool(run.tuning.rhythm.trial.enabled) and not bool(run.tuning.grace.enabled), "(e) %s: the sustain trial and the grace block are off" % primary)
		check(bool(run.tuning.rhythm.enabled) and bool(run.tuning.rhythm.opening.enabled) and bool(run.tuning.boss_finale.enabled), "%s: the rhythm, its opening and the finale are on" % primary)
		check(run.spells.is_empty(), "(e) %s: no spell composition" % primary)
		check(not bool(run.tuning.elites.enabled) and not bool(run.tuning.extras.enabled) and not bool(run.tuning.loot_flow.enabled), "(e) %s: elites, extras and loot_flow are off" % primary)
		check(not run.descent.is_empty() and int(run.descent.cost[0]) == 3000 and int(run.descent.cost[2]) == 10000, "%s: the descent is on with the data cost" % primary)
		var crest: Dictionary = run.tuning.rhythm.beats[0].get("taste_crest", {})
		check(String(run.tuning.rhythm.beats[0].id) == "gi" and int(crest.get("at_ticks", -1)) == 6000 and int(crest.get("count", -1)) == 14 and int(crest.get("arc_deg", -1)) == 70, "%s: the gi beat carries the taste crest {6000, 14, 70}" % primary)
	check(bool(views.get(ARC, {}).get("on", false)), "(b) the arc has the kit on")
	check(not bool(views.get(EMBER, {}).get("on", true)) and not bool(views.get(FROST, {}).get("on", true)), "(b) ember and frost have it off, by the kit's own rule")
	var arc = started(ARC)
	if arc != null:
		check(arc.growth.kit_active() and arc.kit_view().taken.is_empty(), "the arc's growth runs the kit")
		check(arc.growth.snapshot().kit.open.size() > 0, "the whole permanent tree is open (kit.open has the tree's cards)")
	# Same seed, same trial, twice: the same state after some steps (the trial adds no hidden randomness).
	var a = started(ARC, 12)
	var b = started(ARC, 12)
	var pa: RefCounted = load(PILOT).new()
	var pb: RefCounted = load(PILOT).new()
	pa.run = a
	pb.run = b
	for i in 900:
		a.step(pa.decide())
		b.step(pb.decide())
	check(JSON.stringify(a.snapshot()).sha256_text() == JSON.stringify(b.snapshot()).sha256_text(), "the same seed under the trial twice: the same snapshot after 900 ticks")

## (d) plus the old `pace` path
func part_values() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Tuning.DEFAULT_PATH))
	var run = started(ARC)
	var rhythm: Dictionary = run.tuning.rhythm
	check(canon(rhythm.seal_kills) == canon(data.rhythm.seal_kills) and canon(rhythm.xp_thresholds) == canon(data.rhythm.xp_thresholds), "(d) the trial's seal_kills and xp_thresholds are the data file's")
	check(canon(rhythm.guardian_grace) == canon(data.rhythm.guardian_grace) and canon(rhythm.kill_burst) == canon(data.rhythm.kill_burst), "(d) guardian_grace and kill_burst are the data file's")
	check(canon(rhythm.xp_thresholds) != canon(TrialPace.FIRST_VALUES.xp_thresholds) and canon(rhythm.seal_kills) != canon(TrialPace.FIRST_VALUES.seal_kills), "(d) the trial does not read the old D19 first values")
	# The `pace` path of the checks and the app (with_pace / boss_finale) must give the very same rhythm values as the trial.
	for variant in ["pace", "boss_finale"]:
		var other = Chapter.new()
		var problem := TrialDocs.enable_rhythm_problem(other, false, true) if variant == "pace" else TrialDocs.enable_boss_finale_problem(other)
		check(problem.is_empty(), "the %s path starts: %s" % [variant, problem])
		var o: Dictionary = other.tuning.rhythm
		var same := true
		for key in ["xp_thresholds", "seal_kills", "guardian_grace", "kill_burst"]:
			if canon(o[key]) != canon(rhythm[key]): same = false
		check(same, "(d) the %s path and the trial give the same rhythm values (xp_thresholds, seal_kills, guardian_grace, kill_burst)" % variant)
	var apply_doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Tuning.DEFAULT_PATH))
	var before := JSON.stringify(apply_doc)
	TrialPace.apply(apply_doc)
	check(JSON.stringify(apply_doc) == before, "TrialPace.apply leaves the document as it is")
	# The taste crest of the data file's own gi beat stays untouched (the trial lays it on a copy).
	check(not data.rhythm.beats[0].has("taste_crest"), "the shipped combat_tuning.json has no taste crest (the trial lays it on in memory)")
	check(SliceDocs.enable_slice_problem(Chapter.new()).is_empty() and TrialSlice.document_sha256().length() == 64, "the trial document has a sha256 the measurement can write down")

## (f)
func part_refused() -> void:
	var good := shipped_slice()
	check(TrialSlice.validate(good).is_empty(), "the shipped trial_slice.json is accepted")
	check(good.loot.luck == true, "the director's ruling: luck is in the trial")
	var cases := {
		"an unknown root key": func(d): d["extra"] = 1,
		"a missing root key": func(d): d.erase("descent"),
		"an unknown key inside tuning": func(d): d.tuning["more"] = true,
		"a missing key inside loot": func(d): d.loot.erase("pity"),
		"loot.luck as a number": func(d): d.loot.luck = 1,
		"run_spells true": func(d): d.run_spells = true,
		"the finale without the rhythm": func(d): d.tuning.rhythm.enabled = false,
		"an off name that is no block": func(d): d.tuning.off = ["grace", "nothing"],
		"an element that does not exist": func(d): d.element_kit.enabled_elements = ["arcs"],
		"a tree mode that does not exist": func(d): d.element_kit.tree = "some",
		"schema_version 2": func(d): d.schema_version = 2,
	}
	for name_ in cases:
		var copy := shipped_slice()
		cases[name_].call(copy)
		check(not TrialSlice.validate(copy).is_empty(), "(f) refused: " + String(name_))
		var run = Chapter.new()
		check(not SliceDocs.enable_slice_problem(run, copy).is_empty(), "(f) apply() says a sentence for: " + String(name_))
	# Values the core's own validators refuse come back as a sentence too, and nothing is started.
	var bad_crest := shipped_slice()
	bad_crest.tuning.taste_crest.count = 9999
	check(not SliceDocs.enable_slice_problem(Chapter.new(), bad_crest).is_empty(), "(f) a taste crest the combat tuning validator refuses is refused")
	var no_beat := shipped_slice()
	no_beat.tuning.taste_crest.beat = "nowhere"
	check(not SliceDocs.enable_slice_problem(Chapter.new(), no_beat).is_empty(), "(f) a taste crest on a beat that does not exist is refused")
	var bad_cost := shipped_slice()
	bad_cost.descent.cost = [10]
	check(not SliceDocs.enable_slice_problem(Chapter.new(), bad_cost).is_empty(), "(f) a descent cost the descent validator refuses is refused")
	# A copy read from a file under _local/ (what measure_rhythm --slice-doc does) goes through the same check.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEMP_DIR))
	var path := TEMP_DIR + "/good.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(shipped_slice()))
	file.close()
	check(TrialSlice.read_document(path).error == "" and not TrialSlice.read_document(path).doc.is_empty(), "a good copy under _local/ reads")
	var bad_path := TEMP_DIR + "/unknown_key.json"
	var unknown := shipped_slice()
	unknown["surprise"] = 1
	var file_bad := FileAccess.open(bad_path, FileAccess.WRITE)
	file_bad.store_string(JSON.stringify(unknown))
	file_bad.close()
	check(TrialSlice.read_document(bad_path).error != "" and TrialSlice.read_document(TEMP_DIR + "/missing.json").error != "", "a copy with an unknown key and a missing copy are refused")
	# The shipped switches are not touched by any of this.
	var shipped_loot: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://chapter1/data/loot.json"))
	check(shipped_loot.upgrade_verdict.enabled == false and shipped_loot.affix_rolls.enabled == false and shipped_loot.pity.enabled == false and shipped_loot.luck.enabled == false, "the shipped loot.json switches are all still off")
	check(JSON.parse_string(FileAccess.get_file_as_string("res://chapter1/data/descent.json")).enabled == false and JSON.parse_string(FileAccess.get_file_as_string(Kit.DEFAULT_PATH)).enabled == false, "the shipped descent.json and element_kit.json are still off")

## (g)
func part_profile() -> void:
	Kit.use_override({})
	Profile.refresh_element_kit()
	var off_entry: Dictionary = Progression.character_entry(Profile.progression_doc(), "chapter1.character.arc")
	check(off_entry.get("tree_id") == null, "(g) before: the arc witch has no element tree")
	var old_tree_id: Variant = off_entry.get("tree_id")
	check(TrialSlice.use_for_profile(), "(g) use_for_profile() parks the kit's document")
	var on_entry: Dictionary = Progression.character_entry(Profile.progression_doc(), "chapter1.character.arc")
	check(String(on_entry.get("tree_id", "")) == "witch.arc", "(g) after: the arc witch's tree is the element tree (%s)" % str(on_entry.get("tree_id")))
	check(Profile.trees().has("witch.arc"), "(g) the element tree is among the trees")
	Kit.use_override({})
	Profile.refresh_element_kit()
	var back: Dictionary = Progression.character_entry(Profile.progression_doc(), "chapter1.character.arc")
	check(back.get("tree_id") == old_tree_id and not Profile.trees().has("witch.arc"), "(g) back: the old tree again")

## A-element-kit-screen 9.1
func part_kit_view() -> void:
	var run = started(ARC)
	var v: Dictionary = run.kit_view()
	for key in ["next_storm", "cap_big", "rod_radius_cm", "reach_cm", "next_rod", "next_overload"]:
		check(v.has(key), "kit_view has " + key)
	check(int(v.skills[ROD].cooldown_ticks) == 300 and int(v.skills[OVERLOAD].cooldown_ticks) == 180, "kit_view: the rod recharges in 300, the overload in 180 ticks (%s)" % str(v.skills))
	check(int(v.cap_big) == 10 and int(v.rod_radius_cm) == 600 and int(v.reach_cm) == 1000 and int(v.next_storm) == 0, "kit_view: base cap_big 10, rod radius 600, reach 1000, next_storm 0 (%s)" % str(v))
	var before := JSON.stringify(run.snapshot())
	run.kit_view()
	check(JSON.stringify(run.snapshot()) == before, "kit_view changes nothing")
	# The cards that move these numbers (set into the growth's own tables the way a taken card does).
	run.growth._kit_vals["overload_cd_bps"] = -3000
	run.growth._kit_vals["max_big"] = 5
	run.growth._kit_ranks[ROD] = 3
	run.growth._kit_ranks[OVERLOAD] = 3
	var w: Dictionary = run.kit_view()
	check(int(w.skills[OVERLOAD].cooldown_ticks) == 126, "kit_view: A21's -30%% brings the overload to 126 ticks (%d)" % int(w.skills[OVERLOAD].cooldown_ticks))
	check(int(w.cap_big) == 15, "kit_view: A18 gives cap_big 15 (%d)" % int(w.cap_big))
	check(int(w.rod_radius_cm) == 800, "kit_view: rod rank 3 gives rod_radius_cm 800 (%d)" % int(w.rod_radius_cm))
	run.growth._kit_vals["overload_cd_bps"] = 5000
	check(int(run.kit_view().skills[OVERLOAD].cooldown_ticks) == 270, "kit_view: A22's +50%% brings the overload to 270 ticks")
	var off = started(FROST)
	check(off.kit_view() == {"on": false}, "kit_view off is {on:false}")

## A-element-kit-screen 9.2
func part_card_open() -> void:
	var run = started(ARC)
	var pilot: RefCounted = load(PILOT).new()
	pilot.run = run
	var guard := 0
	while run.mode != "choice" and guard < 20000:
		run.step(pilot.decide())
		guard += 1
	check(run.mode == "choice", "a hand is made within 20000 ticks")
	var kit_doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Kit.DEFAULT_PATH))
	var opens := {}
	for card in kit_doc.elements.arc.cards: opens[String(card.id)] = String(card.open)
	var offer: Dictionary = run.get_offer()
	var seen := 0
	for card in offer.cards:
		check(card.has("open") and card.open is String and not String(card.open).is_empty(), "every offered card has an open field (%s)" % str(card.get("id")))
		var expected: String = String(opens.get(String(card.id), "base"))
		check(String(card.open) == expected, "card %s: open is %s (the document says %s)" % [str(card.id), str(card.open), expected])
		seen += 1
	check(seen > 0, "the hand has cards")

## C5
func part_descent_points() -> void:
	var run = started(ARC)
	var base := int(run.metrics.descent.gauge_in)
	run._emit("detonated", Vector2.ZERO, {"skill_id": OVERLOAD, "target_id": 0, "stacks": 1, "damage_raw": 1})
	check(int(run.metrics.descent.gauge_in) - base == int(run.descent.points.kit_detonate) and int(run.descent.points.kit_detonate) > 0, "C5: one detonated event adds the kit_detonate points to the gauge")
	var base2 := int(run.metrics.descent.gauge_in)
	for i in 20: run._emit("detonated", Vector2.ZERO, {"skill_id": OVERLOAD, "target_id": 0, "stacks": 1, "damage_raw": 1})
	check(int(run.metrics.descent.gauge_in) - base2 <= int(run.descent.points.combo_cap_per_tick), "C5: the points are combination points, bounded by combo_cap_per_tick in one tick")
	# The same road as the spell composition's `detonate`.
	var other = started(ARC)
	var b3 := int(other.metrics.descent.gauge_in)
	other._emit("detonate", Vector2.ZERO, {"target_id": 0})
	check(int(other.metrics.descent.gauge_in) - b3 == int(other.descent.points.detonate), "C5: `detonate` still adds its own points")
	# In a real play the overload feeds the gauge (the kit's detonations are counted in the descent's tally).
	var real = started(ARC, 11)
	var pilot: RefCounted = load(PILOT).new()
	pilot.run = real
	var detonations := 0
	var steps := 0
	while real.mode != "victory" and real.mode != "defeat" and steps < 60 * 400 and detonations < 3:
		real.step(pilot.decide())
		steps += 1
		for event in real.events:
			if String(event.type) == "detonated": detonations += 1
	check(detonations > 0, "a real arc run under the trial makes the kit detonate within 400 s (%d detonated events, %d steps)" % [detonations, steps])

## C6
func part_verdict() -> void:
	var mk := func(uid: int, slot_: String, stats: Dictionary) -> Dictionary:
		return {"uid": uid, "name": "item%d" % uid, "slot": slot_, "stats": stats, "quality": "magic", "item_level": 1, "affixes": [], "description": "", "required_level": 1}
	var run = started(ARC)
	check(run.loot.verdict_on() and run._kit_on, "the arc run under the trial has the verdict v2 and the kit on")
	run.inventory.clear()
	run.equipped.clear()
	run.inventory.append(mk.call(981, "weapon", {"arc_damage_bps": 3000}))
	run.inventory.append(mk.call(982, "weapon", {"damage_bps": 4000}))
	run.inventory.append(mk.call(983, "weapon", {"arc_damage_bps": 4000}))
	run.equipped.weapon = 981
	run._recompute_gear()
	var kit_primary: Dictionary = run.pickup_verdict(982)
	var kit_kit: Dictionary = run.pickup_verdict(983)
	check(kit_primary.better == "no" and kit_kit.better == "yes", "C6 core, kit on: +40%% damage_bps does not beat a worn +30%% arc_damage_bps weapon, +40%% arc_damage_bps does (%s, %s)" % [kit_primary.better, kit_kit.better])
	check(not run.is_better_gear(run.inventory[1], run.inventory[0], "weapon") and run.is_better_gear(run.inventory[2], run.inventory[0], "weapon"), "C6 core: is_better_gear (the pilot's road) gives the same two answers")
	# The same two items with the kit flag of the run off: the old verdict (both keys weigh the same).
	run._kit_on = false
	check(run.pickup_verdict(982).better == "yes" and run.pickup_verdict(983).better == "yes", "C6 core, kit flag off: the old verdict calls both better")
	run._kit_on = true
	# The pilot wears by the same function: with the shipped three-way test above, the QA pilot's wear step reads is_better_gear.
	var src := FileAccess.get_file_as_string("res://chapter1/core/chapter_pilot.gd")
	check(src.contains("run.is_better_gear(") and src.contains("run.loot.verdict_on()"), "C6 the QA pilot judges by run.is_better_gear when the verdict is on (the same function)")

## A-element-kit-screen 9.3
func part_skip() -> void:
	var run = started(ARC)
	var pilot: RefCounted = load(PILOT).new()
	pilot.run = run
	for i in 120: run.step(pilot.decide())
	check(run.debug_skip_to_boss(), "debug_skip_to_boss works in a kit run")
	var v: Dictionary = run.kit_view()
	check(int(v.skills[ROD].rank) >= 1 and int(v.skills[OVERLOAD].rank) >= 1, "after the shortcut the rod and the overload are unlocked (%s)" % str(v.skills))
	check("A01" in v.taken and "A02" in v.taken, "after the shortcut A01 and A02 are taken (%s)" % str(v.taken))
	# A run that is not a kit run is unchanged by the new order: the order of preference still puts the primary's cards first.
	var plain = Chapter.new()
	check(plain.start(11, ARC), "a plain arc run starts")
	var plain_pilot: RefCounted = load(PILOT).new()
	plain_pilot.run = plain
	for i in 120: plain.step(plain_pilot.decide())
	check(plain.debug_skip_to_boss() and not plain.kit_view().on, "a plain run (no kit) still takes the shortcut, and has no kit view")

func check_sources_unchanged() -> void:
	# The shipped data files this trial reads are not written by the trial.
	var before := FileAccess.get_sha256("res://chapter1/data/combat_tuning.json")
	var run = started(ARC)
	check(run != null and FileAccess.get_sha256("res://chapter1/data/combat_tuning.json") == before, "combat_tuning.json is byte-identical after a trial run")
