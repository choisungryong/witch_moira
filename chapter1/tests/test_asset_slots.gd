extends SceneTree
## Asset slot check (T7-1). Loads every slot of the table through the resolver and checks the contract the table states:
## files exist, models have the bones and clips named, sprite-sheet frames lie inside their textures, texture sizes match.
## Also checks the resolver itself: placeholders for missing slots (and that they are recorded), fallback files, and that a
## malformed table is rejected.
##
##   python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_asset_slots.gd -- [--strict] [--strict-planned] [--slots=<table>] [--pins]
##
## --slots=      another table (res://_local/... or _local/...); default is chapter1/art/asset_slots.json
## --strict      a placeholder or fallback served for a slot that is not planned is a failure (release builds)
## --strict-planned  a planned slot (no art yet) is a failure too
## --pins        also pin the transcribed numbers to the literals still in the code (valid until the code reads the table)
## Last line: CHAPTER1_ASSET_SLOTS_RESULT {...}; exit code 1 on any failure.
const Slots := preload("res://chapter1/view/assets/asset_slots.gd")
const Core := preload("res://chapter1/core/combat_core.gd")
const WORK_DIR := "res://_local/t7/test_asset_slots"
const REPORT_CAP := 5

var checks := 0
var failures: Array[String] = []
var strict := false
var strict_planned := false
var pins := false
var table_arg := ""
var size_cache: Dictionary = {}

func _initialize() -> void:
	call_deferred("execute")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func execute() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--strict":
			strict = true
		elif arg == "--strict-planned":
			strict_planned = true
		elif arg == "--pins":
			pins = true
		elif arg.begins_with("--slots="):
			table_arg = arg.substr(8).replace("\\", "/")
			if table_arg.begins_with("_local/"):
				table_arg = "res://" + table_arg
	resolver_checks()
	var summary := table_checks()
	summary["checks"] = checks
	summary["failures"] = failures
	summary["strict"] = strict
	print("CHAPTER1_ASSET_SLOTS_RESULT ", JSON.stringify(summary))
	quit(1 if not failures.is_empty() else 0)

# ---- the resolver itself (synthetic tables, independent of the real one) ----

func resolver_checks() -> void:
	# The numbers in the table are JSON text; they must parse to the same doubles the GDScript literals give.
	var parsed: Array = JSON.parse_string("[0.72,1.32,0.157,0.15,2.25,0.9,0.6,0.8,0.44,0.58,0.015,1.15,1.2]")
	var literals: Array = [.72, 1.32, .157, .15, 2.25, .9, .6, .8, .44, .58, .015, 1.15, 1.2]
	check(parsed == literals, "JSON numbers parse to the same doubles as the GDScript literals")
	check(float(56) / float(60) == 56.0 / 60.0 and float(96) / float(60) == 1.60 and float(25) / float(60) == 25.0 / 60.0, "float(ticks)/hz equals the code literal")

	# Unknown id: placeholder, recorded.
	var errors := Slots.use_table_doc({"schema": 1, "slots": {"world.test.good": {"kind": "texture", "file": "nowhere/none.png"}}}, "synthetic")
	check(errors.is_empty(), "a minimal table is accepted: %s" % str(errors))
	var tex := Slots.texture("actor.nothing.here")
	check(tex != null and tex.get_width() == 64 and tex.get_height() == 64, "placeholder texture is 64x64")
	var img := tex.get_image()
	check(img.get_pixel(0, 0) == Color(1, 0, 1) and img.get_pixel(8, 0) == Color.BLACK and img.get_pixel(8, 8) == Color(1, 0, 1), "placeholder is a magenta/black checkerboard")
	check("actor.nothing.here" in Slots.missing(), "an unknown id is recorded in missing()")
	check(Slots.path("actor.nothing.here") == "" and Slots.bone("actor.nothing.here", "head") == "" and Slots.clip("actor.nothing.here", "idle") == "idle", "unknown id: path '' / bone '' / clip passes the logical name through")
	# A slot whose file is missing.
	check(Slots.texture("world.test.good") == tex and "world.test.good" in Slots.missing() and Slots.path("world.test.good") == "", "a missing file gives the placeholder and is recorded")
	var capsule: Node = Slots.scene("world.test.good").instantiate()
	check(capsule is Node3D and capsule.get_child_count() == 1 and capsule.get_child(0) is MeshInstance3D, "placeholder scene is a Node3D with a capsule mesh")
	capsule.free()

	# Fallback file for a model.
	var walker := "skeleton_outlaw/v02/skeleton_outlaw_merged.glb"
	errors = Slots.use_table_doc({"schema": 1, "slots": {
		"actor.test.with_fb": {"kind": "model", "file": "nowhere/none.glb", "fallback": walker},
		"actor.test.no_fb": {"kind": "model", "file": "nowhere/none.glb"}}}, "synthetic")
	check(errors.is_empty(), "fallback table accepted: %s" % str(errors))
	var fb_scene := Slots.scene("actor.test.with_fb")
	var fb_node: Node = fb_scene.instantiate()
	check(Slots.path("actor.test.with_fb") == "res://chapter1/art/" + walker and fb_node.find_child("Skeleton3D", true, false) != null, "the fallback file is served when the main file is missing")
	fb_node.free()
	check("actor.test.with_fb" in Slots.fallbacks() and "actor.test.with_fb" in Slots.missing(), "a fallback use is recorded in fallbacks() and missing()")
	var pl_node: Node = Slots.scene("actor.test.no_fb").instantiate()
	check(pl_node.name == "AssetPlaceholder" and "actor.test.no_fb" in Slots.missing() and not "actor.test.no_fb" in Slots.fallbacks(), "no file and no fallback gives the capsule and is recorded as missing only")
	pl_node.free()

	# inherit, scale3, timing, bone_group, clip.
	errors = Slots.use_table_doc({"schema": 1, "slots": {
		"actor.test.base": {"kind": "model", "file": walker, "contract": {"scale": 0.5, "bones": {"head": "ORG-head", "spine": "ORG-spine"},
			"bone_groups": {"tracked": ["spine", "head"], "upper_prefixes": ["spine_"]}, "clips": {"attack": "attack_slam"},
			"tick_hz": 60, "timing_ticks": {"walk": 56}, "timing_s": {"release": 0.157}}},
		"actor.test.child": {"kind": "model", "inherit": "actor.test.base", "contract": {"scale": [0.44, 0.58, 0.44]}}}}, "synthetic")
	check(errors.is_empty(), "inherit table accepted: %s" % str(errors))
	check(Slots.path("actor.test.child") == Slots.path("actor.test.base") and Slots.bone("actor.test.child", "head") == "ORG-head", "inherit: file and bones come from the target")
	check(Slots.scale3("actor.test.child") == Vector3(.44, .58, .44) and Slots.scale3("actor.test.base") == Vector3.ONE * .5, "inherit: the child's own scale wins; uniform scale3 is a number times ONE")
	check(Slots.timing("actor.test.child", "walk") == 56.0 / 60.0 and Slots.timing("actor.test.child", "release") == .157 and Slots.timing("actor.test.child", "nothing") == -1.0, "timing(): ticks over hz, seconds, -1 when absent")
	check(Slots.bone_group("actor.test.child", "tracked") == ["ORG-spine", "ORG-head"] and Slots.bone_group("actor.test.child", "upper_prefixes") == ["spine_"], "bone_group(): logical names to real ones, pattern groups unchanged")
	check(Slots.clip("actor.test.child", "attack") == "attack_slam" and Slots.clip("actor.test.child", "idle") == "idle", "clip(): mapped, else the logical name")

	# A malformed table is rejected, by name; a rejected table leaves nothing behind.
	var good := {"kind": "model", "file": walker, "contract": {"bones": {"head": "ORG-head"}}}
	var bad_cases: Array = [
		["table: schema", {"schema": 2, "slots": {"actor.a.b": good}}],
		["table: slots", {"schema": 1, "slots": []}],
		["table: the top level", []],
		["actor.a.b: kind", {"schema": 1, "slots": {"actor.a.b": {"kind": "mesh", "file": "x.glb"}}}],
		["actor.a.b: file must be a string", {"schema": 1, "slots": {"actor.a.b": {"kind": "model", "file": 5}}}],
		["actor.a.b: file is empty", {"schema": 1, "slots": {"actor.a.b": {"kind": "model", "file": ""}}}],
		["actor.a.b: planned", {"schema": 1, "slots": {"actor.a.b": {"kind": "texture", "file": "", "planned": "yes"}}}],
		["actor.a.b: file 'chapter1/../x.png'", {"schema": 1, "slots": {"actor.a.b": {"kind": "texture", "file": "chapter1/../x.png"}}}],
		["actor.a.b: contract must be an object", {"schema": 1, "slots": {"actor.a.b": {"kind": "model", "file": "x.glb", "contract": []}}}],
		["actor.a.b: contract.bones.head", {"schema": 1, "slots": {"actor.a.b": {"kind": "model", "file": "x.glb", "contract": {"bones": {"head": 3}}}}}],
		["which is not in contract.bones", {"schema": 1, "slots": {"actor.a.b": {"kind": "model", "file": "x.glb", "contract": {"bones": {"head": "H"}, "bone_groups": {"hit": ["head", "tail"]}}}}}],
		["actor.a.b: contract.scale", {"schema": 1, "slots": {"actor.a.b": {"kind": "model", "file": "x.glb", "contract": {"scale": -1}}}}],
		["actor.a.b: contract.clips.idle", {"schema": 1, "slots": {"actor.a.b": {"kind": "model", "file": "x.glb", "contract": {"clips": {"idle": ""}}}}}],
		["actor.a.b: inherit target", {"schema": 1, "slots": {"actor.a.b": {"kind": "model", "inherit": "actor.no.such"}}}],
		["cyclic", {"schema": 1, "slots": {"actor.a.b": {"kind": "model", "inherit": "actor.c.d"}, "actor.c.d": {"kind": "model", "inherit": "actor.a.b"}}}],
		["thing: id must be", {"schema": 1, "slots": {"actor.a": good, "thing": good}}],
		["bad.id.x: id must be", {"schema": 1, "slots": {"bad.id.x": good}}],
		["actor.a.b: used", {"schema": 1, "slots": {"actor.a.b": {"kind": "model", "file": "x.glb", "used": "maybe"}}}],
	]
	for case in bad_cases:
		var found := false
		for message in Slots.validate_table(case[1]).errors:
			found = found or String(message).contains(case[0])
		check(found, "a malformed table is rejected with a message naming '%s'" % case[0])
	var rejected := Slots.use_table_doc({"schema": 1, "slots": {"actor.a.b": {"kind": "mesh", "file": "x.glb"}}}, "synthetic")
	check(not rejected.is_empty() and Slots.slot_ids().is_empty() and Slots.path("actor.a.b") == "", "a rejected table is not used: no slots, every id falls to the placeholder")
	var warned := Slots.validate_table({"schema": 1, "slots": {"actor.a.b": {"kind": "model", "file": "x.glb", "contract": {"dream": 1}, "extra": 2}}})
	check(warned.errors.is_empty() and warned.warnings.size() == 2, "an unknown slot key or contract key is a warning, not an error")
	# Files.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORK_DIR))
	var not_json := WORK_DIR + "/not_json.json"
	var f := FileAccess.open(not_json, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	check(not Slots.use_table(not_json) and not Slots.table_errors().is_empty() and Slots.slot_ids().is_empty(), "a table file that is not JSON is rejected")
	check(not Slots.use_table(WORK_DIR + "/no_such_table.json"), "a missing table file is rejected")

# ---- the real (or --slots=) table ----

func table_checks() -> Dictionary:
	var ok := Slots.use_table(table_arg)
	check(ok, "table is accepted: %s" % str(Slots.table_errors()))
	for message in Slots.table_errors():
		failures.append("table: " + message)
	var summary := {"table": Slots.table_path(), "slots": Slots.slot_ids().size(), "planned": [], "contracts": 0, "contract_values": 0, "fallbacks": [], "missing": [], "warnings": Slots.table_warnings()}
	var planned: Array = []
	var with_contract := 0
	var values := 0
	var swept := 0
	for id in Slots.slot_ids():
		var s := Slots.slot(id)
		if Slots.is_planned(id):
			planned.append(id)
			continue
		swept += 1
		var c: Dictionary = s.get("contract", {})
		if not c.is_empty():
			with_contract += 1
			values += leaf_count(c)
		slot_checks(id, s, c)
	summary.planned = planned
	summary.contracts = with_contract
	summary.contract_values = values
	summary.swept = swept
	summary.fallbacks = Slots.fallbacks()
	var missing: Array[String] = []
	for id in Slots.missing():
		if not Slots.is_planned(id):
			missing.append(id)
	summary.missing = missing
	if strict:
		check(missing.is_empty(), "strict: placeholders served for %s" % str(missing))
		check(Slots.fallbacks().is_empty(), "strict: fallback files served for %s" % str(Slots.fallbacks()))
	if strict_planned:
		check(planned.is_empty(), "strict-planned: slots with no art yet: %s" % str(planned))
	coverage_checks(summary)
	hero_checks(summary)
	if pins:
		pin_checks()
	return summary

func leaf_count(v: Variant) -> int:
	if v is Dictionary:
		var n := 0
		for k in v:
			n += leaf_count(v[k])
		return n
	if v is Array:
		var n := 0
		for e in v:
			n += leaf_count(e)
		return n
	return 1

## Collects up to REPORT_CAP messages of one slot so a wrong table does not flood the output.
func report(id: String, what: String, problems: Array) -> void:
	if problems.is_empty():
		check(true, "")
		return
	var shown := problems.slice(0, REPORT_CAP)
	var more := "" if problems.size() <= REPORT_CAP else " (+%d more)" % (problems.size() - REPORT_CAP)
	check(false, "%s: %s: %s%s" % [id, what, "; ".join(shown), more])

func slot_checks(id: String, s: Dictionary, c: Dictionary) -> void:
	var file := String(s.get("file", ""))
	var path := Slots.path(id)
	if path == "" and Slots.is_optional(id):
		print("NOTE %s: optional file is not in this checkout (%s), not checked" % [id, file])
		return
	if path == "":
		check(false, "%s: file missing: %s%s" % [id, file, " (and fallback missing: %s)" % s.fallback if s.has("fallback") else ""])
		return
	if path != Slots._abs(file):
		print("NOTE %s: main file missing (%s), the fallback %s is used" % [id, file, path])
	# Files the slot names besides the main one.
	var absent: Array = []
	for key in ["meta"]:
		if s.has(key) and not Slots._exists(Slots._abs(String(s[key]))):
			absent.append("%s %s" % [key, s[key]])
	for extra in s.get("extra_files", []):
		if not Slots._exists(Slots._abs(String(extra))):
			absent.append("extra file " + String(extra))
	report(id, "named files exist", absent)
	if not absent.is_empty():
		return
	match String(s.kind):
		"model":
			model_checks(id, c)
		"sprite_sheet":
			sheet_checks(id, c)
		"texture", "atlas", "nine_slice":
			texture_checks(id, c)
		"prop_atlas":
			texture_checks(id, c)
			prop_atlas_checks(id, c)
		"layout":
			layout_checks(id)
		"video":
			check(Slots.video(id) != null, "%s: the video does not load as a Theora stream" % id)
		"font":
			var font := Slots.font(id)
			check(font != null, "%s: font does not load" % id)
		_:
			pass

func model_checks(id: String, c: Dictionary) -> void:
	var packed := Slots.scene(id)
	var root: Node = packed.instantiate()
	var skeleton := root.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var problems: Array = []
	var bones: Dictionary = c.get("bones", {})
	if not bones.is_empty() and skeleton == null:
		problems.append("the model has no Skeleton3D")
	elif skeleton != null:
		for logical in bones:
			if skeleton.find_bone(String(bones[logical])) < 0:
				problems.append("bone '%s' -> '%s' is not in the skeleton" % [logical, bones[logical]])
		for prefix in c.get("bone_groups", {}).get("upper_prefixes", []):
			var hits := 0
			for i in skeleton.get_bone_count():
				hits += 1 if skeleton.get_bone_name(i).begins_with(String(prefix)) else 0
			if hits == 0:
				problems.append("upper_prefixes '%s' matches no bone" % prefix)
	report(id, "bones", problems)
	problems = []
	var clips: Dictionary = c.get("clips", {})
	if not clips.is_empty() and player == null:
		problems.append("the model has no AnimationPlayer")
	elif player != null:
		for logical in clips:
			if not player.has_animation(String(clips[logical])):
				problems.append("clip '%s' -> '%s' is not in the model (has: %s)" % [logical, clips[logical], ", ".join(Array(player.get_animation_list()))])
			elif player.get_animation(String(clips[logical])).length <= 0.0:
				problems.append("clip '%s' -> '%s' has no length" % [logical, clips[logical]])
	report(id, "clips", problems)
	root.free()

func texture_size(path: String) -> Vector2i:
	if size_cache.has(path):
		return size_cache[path]
	var out := Vector2i.ZERO
	if ResourceLoader.exists(path):
		var res: Resource = ResourceLoader.load(path)
		if res is Texture2D:
			out = Vector2i(res.get_width(), res.get_height())
	size_cache[path] = out
	return out

func texture_checks(id: String, c: Dictionary) -> void:
	var tex := Slots.texture(id)
	var path := Slots.path(id)
	if path == "":
		check(false, "%s: texture does not load" % id)
		return
	var size := Vector2i(tex.get_width(), tex.get_height())
	var problems: Array = []
	if c.has("size") and Vector2i(int(c.size[0]), int(c.size[1])) != size:
		problems.append("size is %dx%d, the contract says %dx%d" % [size.x, size.y, int(c.size[0]), int(c.size[1])])
	if bool(c.get("square", false)) and size.x != size.y:
		problems.append("not square: %dx%d" % [size.x, size.y])
	var crops: Dictionary = c.get("crops", {})
	for name in crops:
		var r: Array = crops[name]
		if r[0] < 0 or r[1] < 0 or r[2] <= 0 or r[3] <= 0 or r[0] + r[2] > size.x or r[1] + r[3] > size.y:
			problems.append("crop '%s' %s is outside the %dx%d texture" % [name, str(r), size.x, size.y])
	report(id, "texture", problems)

## A prop sheet's side JSON must hold every id the contract asks for (the ids the placement file and the map edge use).
func prop_atlas_checks(id: String, c: Dictionary) -> void:
	var have: Array = []
	for prop in Slots.meta(id).get("props", []):
		if prop is Dictionary:
			have.append(String(prop.get("id", "")))
	var problems: Array = []
	for need in c.get("ids_required", []):
		if not String(need) in have:
			problems.append("id '%s' is not in the side JSON" % need)
	report(id, "prop sheet ids", problems)

## The placement file (A12-0): every sprite prop id it places is one the prop sheet slot promises, zones are 0..2, and the sections the world presenter reads exist.
func layout_checks(id: String) -> void:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(Slots.path(id)))
	if not doc is Dictionary:
		check(false, "%s: the placement file is not a JSON object" % id)
		return
	var problems: Array = []
	for section in ["props", "foundation_stones", "rear_blocks", "rear_arches", "grass", "edge"]:
		if not doc.has(section):
			problems.append("section '%s' is missing" % section)
	var sheet_ids: Array = Slots.contract("world.common.props.cloister").get("ids_required", [])
	for record in doc.get("props", []):
		if not String(record.get("id", "")) in sheet_ids:
			problems.append("prop id '%s' is not in the ids of slot world.common.props.cloister" % record.get("id", ""))
		if not record.get("at") is Array or (record.at as Array).size() != 3 or not record.has("height"):
			problems.append("a prop record has no at [x,y,z] or no height: %s" % JSON.stringify(record))
	for section in ["foundation_stones", "rear_blocks", "rear_arches"]:
		for record in doc.get(section, []):
			if int(record.get("zone", -1)) < 0 or int(record.get("zone", -1)) > 2:
				problems.append("%s: zone outside 0..2: %s" % [section, JSON.stringify(record)])
	report(id, "placement file", problems)

func sheet_checks(id: String, c: Dictionary) -> void:
	var meta := Slots.meta(id)
	var problems: Array = []
	var frames: Variant = meta.get("frames")
	if not frames is Array or (frames as Array).is_empty():
		report(id, "sheet", ["the side JSON has no frames"])
		return
	var main_path := Slots.path(id)
	if texture_size(main_path) == Vector2i.ZERO:
		problems.append("the sheet texture does not load: " + main_path)
	for i in frames.size():
		var frame: Variant = frames[i]
		if not frame is Dictionary or not frame.get("region") is Array or (frame.region as Array).size() != 4:
			problems.append("frame %d has no region [x, y, w, h]" % i)
			continue
		var texture_path := String(frame.get("texture", meta.get("texture", main_path)))
		var size := texture_size(texture_path)
		if size == Vector2i.ZERO:
			problems.append("frame %d: texture %s does not load" % [i, texture_path])
			continue
		var r: Array = frame.region
		if r[0] < 0 or r[1] < 0 or r[2] <= 0 or r[3] <= 0 or r[0] + r[2] > size.x or r[1] + r[3] > size.y:
			problems.append("frame %d region %s is outside %s (%dx%d)" % [i, str(r), texture_path.get_file(), size.x, size.y])
	report(id, "frames inside their textures", problems)
	problems = []
	var states: Dictionary = meta.get("states", {}) if meta.get("states") is Dictionary else {}
	for state in c.get("states", []):
		if not states.has(state):
			problems.append("state '%s' is not in the side JSON" % state)
		else:
			for index in states[state]:
				if int(index) < 0 or int(index) >= frames.size():
					problems.append("state '%s' points at frame %d of %d" % [state, int(index), frames.size()])
					break
	var by_direction: Dictionary = meta.get("frames_by_direction", {}) if meta.get("frames_by_direction") is Dictionary else {}
	for direction in c.get("directions", []):
		if not by_direction.has(direction):
			problems.append("direction '%s' is not in frames_by_direction" % direction)
	report(id, "states and directions", problems)

## The core's ids must each have a slot: every enemy kind, the hero, the final boss.
func coverage_checks(summary: Dictionary) -> void:
	var wanted: Array[String] = ["actor.hero.model", "actor.hero.sheet", "actor.boss.model"]
	# What chapter_world.gd asks for (A12-0).
	wanted.append_array(["world.common.ground.flagstone", "world.common.ground.soil", "world.common.trim.stone", "world.common.props.cloister", "world.common.layout", "world.edge.props", "world.edge.stone"])
	for kind in Core.ENEMY_DEFS:
		wanted.append("actor.%s.model" % kind)
		wanted.append("actor.%s.sheet" % kind)
	var absent: Array = []
	for id in wanted:
		if not Slots.has_slot(id) or Slots.is_planned(id):
			absent.append(id)
	check(absent.is_empty(), "core ids without a slot: %s" % str(absent))
	summary["coverage_checked"] = wanted.size()
	summary["coverage_pending"] = ["icon.equip.<slot> (T7-4)", "portrait.<witch>.rig and illustration.<witch> (T7-4/5)", "font.* (T7-4)"]

## Hero bodies (T2-H): every actor.hero*.model slot that has a contract. The old mage always; a per-witch body only when its file is in
## this checkout (those files are not kept in the repository). Clip lengths are read from the imported glb, not from the code.
func hero_checks(summary: Dictionary) -> void:
	var base := Slots.contract("actor.hero.model")
	var checked: Array = []
	var skipped: Array = []
	for id in Slots.slot_ids():
		if not (id.begins_with("actor.hero.") and id.ends_with(".model")) or Slots.is_planned(id):
			continue
		if not Slots.available(id):
			skipped.append(id)
			continue
		checked.append(id)
		var c := Slots.contract(id)
		var pose: Dictionary = c.get("pose", {})
		var problems: Array = []
		if id != "actor.hero.model":
			# Same logical bones and groups as the old mage (the real names differ per rig).
			for group in ["bones", "bone_groups", "clips"]:
				var mine: Array = (c.get(group, {}) as Dictionary).keys()
				var theirs: Array = (base.get(group, {}) as Dictionary).keys()
				mine.sort()
				theirs.sort()
				if mine != theirs:
					problems.append("%s keys %s differ from actor.hero.model %s" % [group, str(mine), str(theirs)])
			for key in base.get("pose", {}):
				if not pose.has(key):
					problems.append("pose.%s is missing" % key)
		var packed := Slots.scene(id)
		var root: Node = packed.instantiate()
		var player := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player == null:
			problems.append("no AnimationPlayer")
		else:
			var tol := 1e-3
			var rows := [
				["run", float(pose.get("run_time_scale", 0.0))],
				["idle", float(pose.get("idle_loop_s", 0.0))],
				["cast", float(pose.get("cast_start_s", 0.0)) + .2 * float(pose.get("cast_time_scale", 0.0))],
				["hit", float(pose.get("hit_start_s", 0.0)) + .1 * float(pose.get("hit_time_scale", 0.0))],
				["death", float(pose.get("death_max_age_s", 0.0))],
			]
			for row in rows:
				var clip_name := Slots.clip(id, String(row[0]))
				if not player.has_animation(clip_name):
					problems.append("clip %s is missing" % clip_name)
				elif float(row[1]) > player.get_animation(clip_name).length + tol:
					problems.append("%s needs %.4f s but the clip is %.4f s" % [clip_name, float(row[1]), player.get_animation(clip_name).length])
		if id != "actor.hero.model":
			var meta := Slots.meta(id)
			var look: Variant = meta.get("look")
			if not look is Dictionary:
				problems.append("hero.json has no look")
			else:
				for cell in ["albedo_mul", "element_lean", "emission_mode", "emission_energy", "rim", "rim_tint", "light_key", "light_fill", "mask_rule"]:
					if not (look as Dictionary).has(cell):
						problems.append("look.%s is missing" % cell)
				if String(look.get("emission_mode", "")) == "mask":
					var emission_id := id.replace(".model", ".emission")
					if not Slots.has_slot(emission_id):
						problems.append("emission_mode mask but no slot " + emission_id)
					else:
						var size := Slots.texture(emission_id).get_size()
						var same := false
						for node in root.find_children("*", "MeshInstance3D", true, false):
							var mesh := (node as MeshInstance3D).mesh
							for surface in mesh.get_surface_count():
								var material := mesh.surface_get_material(surface) as StandardMaterial3D
								if material != null and material.albedo_texture != null and material.albedo_texture.get_size() == size:
									same = true
						if not same:
							problems.append("no body albedo texture is %dx%d like the emission mask" % [size.x, size.y])
			var staff: Variant = meta.get("staff", {})
			if not staff is Dictionary or not String((staff as Dictionary).get("mode", "upright")) in ["upright", "hand"]:
				problems.append("staff.mode must be upright or hand")
		root.free()
		report(id, "hero body", problems)
	# The key rule: the last segment of a character's signature skill is the last segment of the character id.
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://chapter1/data/character_progression.json"))
	var mismatched: Array = []
	for character in (data as Dictionary).get("characters", []):
		var cid := String((character as Dictionary).get("id", ""))
		var sid := String((character as Dictionary).get("signature_skill_id", ""))
		if cid.get_slice(".", cid.get_slice_count(".") - 1) != sid.get_slice(".", sid.get_slice_count(".") - 1):
			mismatched.append(cid)
	check(mismatched.is_empty(), "character id and signature skill end differently: %s" % str(mismatched))
	summary["hero_bodies_checked"] = checked
	summary["hero_bodies_absent"] = skipped

## The transcribed numbers against the literals still in chapter_actors.gd / walker_vat_spec.gd (T7-1 changes no code).
func pin_checks() -> void:
	var w := "actor.walker.model"
	var h := "actor.hero.model"
	var e := "actor.elite.model"
	check(Slots.scale3(w) == Vector3.ONE * .62 and Slots.scale3(h) == Vector3.ONE * 1.32, "pin: walker 0.62 and hero 1.32 scale")
	check(Slots.scale3("actor.boss.model") == Vector3.ONE * 1.15 and Slots.scale3(e) == Vector3.ONE * .80, "pin: boss 1.15 and elite 0.80 scale")
	check(Slots.scale3("actor.ranged.model") == Vector3(.44, .58, .44) and Slots.scale3("actor.charger.model") == Vector3(.72, .48, .72), "pin: ranged and charger scale")
	check(Slots.timing(w, "walk_cycle") == 56.0 / 60.0 and Slots.timing(w, "swing") == 68.0 / 60.0 and Slots.timing(w, "strike") == 25.0 / 60.0, "pin: WALK34 / SWING34 / STRIKE34")
	check(Slots.timing(w, "hit") == 46.0 / 60.0 and Slots.timing(w, "idle_cycle") == 128.0 / 60.0 and Slots.timing(w, "death") == 1.60, "pin: hit 46/60, idle 128/60, death 1.60")
	check(float(Slots.contract(w).pose.head_scale) == .72 and Slots.timing(e, "release_time") == .157, "pin: head scale 0.72 and RELEASE_TIME 0.157")
	var vat := load("res://chapter1/view/actors/vat/walker_vat_spec.gd")
	var vat_bones: Array[String] = []
	for name in Slots.bone_group(w, "hit"):
		vat_bones.append(name)
	check(vat_bones == vat.HIT_BONES and Slots.bone_group(w, "hit_exclude") == Array(vat.HIT_EXCLUDE_BONES) and Slots.bone_group(w, "tracked") == Array(vat.TRACKED_BONES) and Slots.bone(w, "head") == vat.HEAD_BONE, "pin: bone names equal walker_vat_spec.gd")
	check(Slots.path(w) == vat.MODEL_PATH, "pin: the walker model path equals walker_vat_spec.gd MODEL_PATH")
	check(Slots.bone_group(e, "hit") == ["Spine1", "Spine2", "Spine3", "Shoulder.L", "Shoulder.R", "Arm.L", "Arm.R", "Neck.001", "Head"], "pin: warden HIT28_BONES")
	check(Slots.bone_group(e, "pose32") == ["Spine1", "Spine3", "Shoulder.L", "Shoulder.R", "Arm.L", "Arm.R", "Head"] and Slots.bone_group(e, "pose30") == ["Head", "Shoulder.L", "Shoulder.R", "Arm.L", "Arm.R"], "pin: warden BONES32 / BONES30")
