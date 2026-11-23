extends RefCounted
## Asset slot resolver (T7-1). Code asks for an asset by meaning id (`actor.walker.model`); the table
## `res://chapter1/art/asset_slots.json` says which file that is and what shape it must have (bones, clips, scale, ...).
## Static functions only; the table is read once on the first call and cached. Presentation only: no core state is touched.
##
## A slot whose file is missing is not fatal: texture() gives a 64 px magenta/black checkerboard, scene() gives the
## `fallback` file or else a magenta capsule, and the id is recorded (missing(), fallbacks()) and warned about once.
## A release build must have none (chapter1/tests/test_asset_slots.gd --strict).
##
## Development override: `--chapter1-asset-slots=<path>` (a path under res://_local/ or _local/ only) reads another table, so a
## replacement can be tried without touching the repository. Nothing else reads user arguments here.

const DEFAULT_TABLE := "res://chapter1/art/asset_slots.json"
const ART_ROOT := "res://chapter1/art/"
const ARG_PREFIX := "--chapter1-asset-slots="
const SCHEMA := 1
const CHECKER_SIZE := 64
const CHECKER_CELL := 8
const KINDS: Array[String] = ["model", "sprite_sheet", "texture", "atlas", "nine_slice", "portrait_rig", "prop_atlas", "font", "video", "layout"]
const ID_PREFIXES: Array[String] = ["actor", "portrait", "illustration", "ui", "icon", "world", "fx", "font", "video"]
const USED_VALUES: Array[String] = ["unverified", "yes", "no"]
const SLOT_KEYS: Array[String] = ["kind", "file", "meta", "fallback", "extra_files", "contract", "planned", "inherit", "used", "source", "optional"]
## Contract keys each kind knows. An unknown key is a warning in validate_table() (a column nobody reads rots).
const CONTRACT_KEYS := {
	"model": ["scale", "bones", "bone_groups", "clips", "tick_hz", "timing_ticks", "timing_s", "pose", "budget_profile", "import"],
	"sprite_sheet": ["states", "directions", "import"],
	"texture": ["size", "square", "crops", "alpha", "import"],
	"atlas": ["px_per_code", "pieces_required", "import"],
	"nine_slice": ["margin", "content", "import"],
	"portrait_rig": ["canvas", "eyes"],
	"prop_atlas": ["group", "ids_required", "import"],
	"font": ["axes", "features", "import"],
	"video": ["size", "seconds", "loop_in", "loop_out", "aspect"],
	# A placement file (where things stand; chapter1/art/world/layout_chapter1.json): read as JSON by the presenter, nothing to check but that it is there.
	"layout": [],
}
## Bone-group names whose entries are name prefixes or fragments, not logical bone names.
const PATTERN_GROUPS: Array[String] = ["upper_prefixes", "upper_contains"]

static var _loaded := false
static var _table_path := ""
static var _slots: Dictionary = {}
static var _errors: Array[String] = []
static var _warnings: Array[String] = []
static var _missing: Array[String] = []
static var _fallbacks: Array[String] = []
static var _warned: Dictionary = {}
static var _status_cache: Dictionary = {}
static var _cache: Dictionary = {}
static var _meta_cache: Dictionary = {}
static var _checker: ImageTexture = null
static var _placeholder_scene: PackedScene = null

# ---- table ----

## Reads the table at `path` ("" = the default, or the command-line override). False when the file is unreadable or the
## table is malformed; the table is then empty, so every id falls to its placeholder.
static func use_table(path: String = "") -> bool:
	_reset()
	_loaded = true
	_table_path = path if path != "" else DEFAULT_TABLE
	if not FileAccess.file_exists(_table_path):
		_errors.append("table file not found: " + _table_path)
		return false
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(_table_path)) != OK:
		_errors.append("table is not valid JSON (line %d): %s" % [parser.get_error_line(), _table_path])
		return false
	return _accept(parser.data).is_empty()

## Same for a table already parsed (tests, tools). Returns the error list; empty = accepted.
static func use_table_doc(doc: Variant, label: String = "<memory>") -> Array[String]:
	_reset()
	_loaded = true
	_table_path = label
	return _accept(doc)

static func _accept(doc: Variant) -> Array[String]:
	var report := validate_table(doc)
	_errors.assign(report.errors)
	_warnings.assign(report.warnings)
	if not _errors.is_empty():
		push_error("asset_slots: table rejected (%d errors), first: %s" % [_errors.size(), _errors[0]])
		return _errors.duplicate()
	var raw: Dictionary = doc.slots
	for id in raw:
		var scratch: Array[String] = []
		_slots[id] = _merged(raw, id, scratch)
	return []

static func _reset() -> void:
	_loaded = false
	_table_path = ""
	_slots = {}
	_errors = []
	_warnings = []
	_missing = []
	_fallbacks = []
	_warned = {}
	_status_cache = {}
	_cache = {}
	_meta_cache = {}

static func _ensure() -> void:
	if _loaded:
		return
	var path := _cmdline_table()
	use_table(path)
	# Files the table names but the disk lacks are known now, before anyone asks for them.
	for id in _slots:
		if not bool(_slots[id].get("planned", false)):
			_status(id)
	print("CHAPTER1_ASSETS ", JSON.stringify({"table": _table_path, "slots": _slots.size(), "missing": _missing, "fallbacks": _fallbacks, "errors": _errors}))

static func _cmdline_table() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(ARG_PREFIX):
			var path := arg.substr(ARG_PREFIX.length()).replace("\\", "/")
			if path.begins_with("_local/"):
				path = "res://" + path
			if path.begins_with("res://_local/") and not path.contains(".."):
				return path
			push_error("asset_slots: %s ignored, only a path under res://_local/ is allowed" % arg)
	return ""

# ---- lookups ----

static func table_path() -> String:
	_ensure()
	return _table_path

static func table_errors() -> Array[String]:
	_ensure()
	return _errors.duplicate()

static func table_warnings() -> Array[String]:
	_ensure()
	return _warnings.duplicate()

static func has_slot(id: String) -> bool:
	_ensure()
	return _slots.has(id)

static func slot_ids() -> Array[String]:
	_ensure()
	var out: Array[String] = []
	for id in _slots:
		out.append(id)
	out.sort()
	return out

## The slot with `inherit` already applied (a copy).
static func slot(id: String) -> Dictionary:
	_ensure()
	if not _slots.has(id):
		return {}
	return (_slots[id] as Dictionary).duplicate(true)

static func kind(id: String) -> String:
	_ensure()
	return String(_slots.get(id, {}).get("kind", ""))

static func is_planned(id: String) -> bool:
	_ensure()
	return bool(_slots.get(id, {}).get("planned", false))

## Ids that were served by a placeholder (file missing, not loadable, unknown id, or a planned slot that was asked for).
static func missing() -> Array[String]:
	_ensure()
	return _missing.duplicate()

## Ids that were served by their `fallback` file.
static func fallbacks() -> Array[String]:
	_ensure()
	return _fallbacks.duplicate()

static func contract(id: String) -> Dictionary:
	_ensure()
	var c: Variant = _slots.get(id, {}).get("contract", {})
	return (c as Dictionary).duplicate(true) if c is Dictionary else {}

## The real resource path ("" when the slot is unknown or only a placeholder can be given).
static func path(id: String) -> String:
	return String(_status(id).path)

## True when the slot is in the table, not planned, and its own file (or fallback) is really there.
static func available(id: String) -> bool:
	_ensure()
	return _slots.has(id) and not is_planned(id) and String(_status(id).path) != ""

## A slot whose file may be absent (see "optional").
static func is_optional(id: String) -> bool:
	_ensure()
	return bool(_slots.get(id, {}).get("optional", false))

## The side JSON's parse result (cached; do not change it). {} when there is none or it cannot be read.
static func meta(id: String) -> Dictionary:
	_ensure()
	if _meta_cache.has(id):
		return _meta_cache[id]
	var out: Dictionary = {}
	var file := String(_slots.get(id, {}).get("meta", ""))
	if file != "":
		var p := _abs(file)
		if FileAccess.file_exists(p):
			var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
			if doc is Dictionary:
				out = doc
			else:
				_warn_once("meta:" + id, "asset_slots: %s: meta %s is not a JSON object" % [id, p])
		else:
			_warn_once("meta:" + id, "asset_slots: %s: meta %s not found" % [id, p])
	_meta_cache[id] = out
	return out

## The real bone name for a logical one ("" when the contract has none, so the caller can skip that decoration).
static func bone(id: String, logical: String) -> String:
	var bones: Variant = contract(id).get("bones", {})
	return String(bones.get(logical, "")) if bones is Dictionary else ""

## The real clip name for a logical one (the logical name itself when the contract has no entry).
static func clip(id: String, logical: String) -> String:
	var clips: Variant = contract(id).get("clips", {})
	return String(clips.get(logical, logical)) if clips is Dictionary else logical

## A bone group as real bone names. Pattern groups (upper_prefixes, upper_contains) come back unchanged.
static func bone_group(id: String, group: String) -> Array[String]:
	var c := contract(id)
	var bones: Variant = c.get("bone_groups", {})
	var out: Array[String] = []
	if not bones is Dictionary or not (bones as Dictionary).get(group) is Array:
		return out
	var names: Variant = c.get("bones", {})
	for entry in bones[group]:
		if group in PATTERN_GROUPS or not names is Dictionary:
			out.append(String(entry))
		else:
			out.append(String(names.get(entry, "")))
	return out

## Model scale from the contract: a number is uniform, an array of three is per axis. Vector3.ONE when absent.
static func scale3(id: String) -> Vector3:
	var s: Variant = contract(id).get("scale")
	if s is Array and (s as Array).size() == 3:
		return Vector3(float(s[0]), float(s[1]), float(s[2]))
	if typeof(s) == TYPE_INT or typeof(s) == TYPE_FLOAT:
		return Vector3.ONE * float(s)
	return Vector3.ONE

## A duration in seconds. `timing_ticks` entries are float(ticks)/tick_hz (bit-equal to a code literal like 56.0/60.0);
## otherwise `timing_s`. -1.0 when the key is in neither.
static func timing(id: String, key: String) -> float:
	var c := contract(id)
	var ticks: Variant = c.get("timing_ticks", {})
	if ticks is Dictionary and (ticks as Dictionary).has(key):
		return float(ticks[key]) / float(c.get("tick_hz", 60))
	var seconds: Variant = c.get("timing_s", {})
	if seconds is Dictionary and (seconds as Dictionary).has(key):
		return float(seconds[key])
	return -1.0

# ---- loading with placeholders ----

static func texture(id: String) -> Texture2D:
	var st := _status(id)
	if st.placeholder:
		return placeholder_texture()
	var key := "tex:" + String(st.path)
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = null
	if ResourceLoader.exists(st.path):
		var res: Resource = ResourceLoader.load(st.path)
		if res is Texture2D:
			tex = res
	if tex == null and FileAccess.file_exists(st.path):
		var image := Image.load_from_file(st.path)
		if image != null and not image.is_empty():
			tex = ImageTexture.create_from_image(image)
	if tex == null:
		_demote(id, st, "is not loadable as a texture")
		return placeholder_texture()
	_cache[key] = tex
	return tex

static func scene(id: String) -> PackedScene:
	var st := _status(id)
	if not st.placeholder:
		var key := "scene:" + String(st.path)
		if _cache.has(key):
			return _cache[key]
		var res: Resource = ResourceLoader.load(st.path) if ResourceLoader.exists(st.path) else null
		if res is PackedScene:
			_cache[key] = res
			return res
		_demote(id, st, "is not loadable as a scene")
	return placeholder_scene()

## A video slot as a stream (Ogg Theora, .ogv: the only video format this engine build reads). null when the slot is planned, its file is missing or
## it is not a Theora file. Callers fall back (the cut-scene to the band). The stream is not cached: each call gives a fresh one, a player owns it.
static func video(id: String) -> VideoStream:
	var st := _status(id)
	if st.placeholder or String(st.path) == "":
		return null
	var stream := VideoStreamTheora.new()
	stream.file = String(st.path)
	return stream

static func font(id: String) -> FontFile:
	var st := _status(id)
	if not st.placeholder:
		var key := "font:" + String(st.path)
		if _cache.has(key):
			return _cache[key]
		var res: Resource = ResourceLoader.load(st.path) if ResourceLoader.exists(st.path) else null
		if res is FontFile:
			_cache[key] = res
			return res
		_demote(id, st, "is not loadable as a font")
	# The other bundled face, so text is still drawn; null (and an error) when there is none.
	var other := "font.heading" if id == "font.body" else ("font.body" if id == "font.heading" else "")
	if other != "" and other != id and _slots.has(other):
		var other_st := _status(other)
		if not other_st.placeholder and ResourceLoader.exists(other_st.path):
			var res2: Resource = ResourceLoader.load(other_st.path)
			if res2 is FontFile:
				return res2
	push_error("asset_slots: no font for " + id)
	return null

static func placeholder_texture() -> Texture2D:
	if _checker == null:
		var image := Image.create_empty(CHECKER_SIZE, CHECKER_SIZE, false, Image.FORMAT_RGBA8)
		for y in CHECKER_SIZE:
			for x in CHECKER_SIZE:
				var odd := ((x / CHECKER_CELL) + (y / CHECKER_CELL)) % 2 == 1
				image.set_pixel(x, y, Color.BLACK if odd else Color(1, 0, 1))
		_checker = ImageTexture.create_from_image(image)
	return _checker

## A magenta capsule under a Node3D named AssetPlaceholder. No rig: callers must skip bone work when bone() is "".
static func placeholder_scene() -> PackedScene:
	if _placeholder_scene == null:
		var root := Node3D.new()
		root.name = "AssetPlaceholder"
		var mesh := MeshInstance3D.new()
		mesh.name = "Capsule"
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.3
		capsule.height = 1.6
		mesh.mesh = capsule
		mesh.position = Vector3(0, 0.8, 0)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(1, 0, 1)
		mesh.material_override = material
		root.add_child(mesh)
		mesh.owner = root
		var packed := PackedScene.new()
		packed.pack(root)
		root.free()
		_placeholder_scene = packed
	return _placeholder_scene

# ---- internals ----

static func _abs(file: String) -> String:
	return file if file.begins_with("res://") else ART_ROOT + file

static func _exists(path: String) -> bool:
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)

static func _status(id: String) -> Dictionary:
	_ensure()
	if _status_cache.has(id):
		return _status_cache[id]
	var st := {"path": "", "placeholder": false, "fallback": false}
	if not _slots.has(id):
		st.placeholder = true
		_note_missing(id, "is not in the table")
	else:
		var s: Dictionary = _slots[id]
		var file := String(s.get("file", ""))
		if file != "" and _exists(_abs(file)):
			st.path = _abs(file)
		else:
			var fb := String(s.get("fallback", ""))
			if fb != "" and _exists(_abs(fb)):
				st.path = _abs(fb)
				st.fallback = true
				if not _fallbacks.has(id):
					_fallbacks.append(id)
				if not _missing.has(id):
					_missing.append(id)
				_warn_once("fb:" + id, "asset_slots: %s: %s not found, using fallback %s" % [id, file, fb])
			else:
				st.placeholder = true
				# optional = a body that is not kept in the repository: absent is a normal state, not a missing asset.
				if not bool(s.get("optional", false)):
					_note_missing(id, "has no file (%s)" % (file if file != "" else "planned, no art yet"))
	_status_cache[id] = st
	return st

static func _demote(id: String, st: Dictionary, why: String) -> void:
	st.placeholder = true
	st.path = ""
	_note_missing(id, why)

static func _note_missing(id: String, why: String) -> void:
	if not _missing.has(id):
		_missing.append(id)
	_warn_once("miss:" + id, "asset_slots: %s %s, using the placeholder" % [id, why])

static func _warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(message)

## `inherit` applied: the target's keys, then the slot's own on top (contract: per top-level key). Errors go to `errors`.
static func _merged(slots: Dictionary, id: String, errors: Array, depth: int = 0) -> Dictionary:
	var own: Variant = slots.get(id)
	if not own is Dictionary:
		return {}
	var out: Dictionary = (own as Dictionary).duplicate(true)
	if not out.has("inherit"):
		return out
	var base_id: Variant = out.inherit
	if not base_id is String or not slots.has(base_id):
		errors.append("%s: inherit target %s does not exist" % [id, str(base_id)])
		return out
	if depth >= 4:
		errors.append("%s: inherit chain is cyclic or deeper than 4" % id)
		return out
	var merged: Dictionary = _merged(slots, base_id, errors, depth + 1)
	for key in out:
		if key == "contract" and out.contract is Dictionary and merged.get("contract") is Dictionary:
			for ck in out.contract:
				merged.contract[ck] = out.contract[ck]
		elif key != "inherit":
			merged[key] = out[key]
	merged["inherit"] = base_id
	return merged

static func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT

static func _is_string_array(v: Variant) -> bool:
	if not v is Array:
		return false
	for e in v:
		if not e is String:
			return false
	return true

## Shape check of a parsed table. {"errors": [...], "warnings": [...]}. Does not look at the disk (the Godot check does).
static func validate_table(doc: Variant) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var report := {"errors": errors, "warnings": warnings}
	if not doc is Dictionary:
		errors.append("table: the top level is not an object")
		return report
	if not _is_num(doc.get("schema")) or int(doc.get("schema")) != SCHEMA:
		errors.append("table: schema must be %d" % SCHEMA)
	var slots: Variant = doc.get("slots")
	if not slots is Dictionary or (slots as Dictionary).is_empty():
		errors.append("table: slots must be a non-empty object")
		return report
	var id_pattern := RegEx.create_from_string("^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)+$")
	for id in slots:
		if not id is String or id_pattern.search(id) == null or not id.split(".")[0] in ID_PREFIXES:
			errors.append("%s: id must be <kind>.<target>[.<part>] with kind one of %s" % [str(id), ", ".join(ID_PREFIXES)])
			continue
		if not slots[id] is Dictionary:
			errors.append("%s: slot is not an object" % id)
			continue
		_validate_slot(slots, id, errors, warnings)
	return report

static func _validate_slot(slots: Dictionary, id: String, errors: Array[String], warnings: Array[String]) -> void:
	var raw: Dictionary = slots[id]
	for key in raw:
		if not key in SLOT_KEYS:
			warnings.append("%s: unknown slot key '%s'" % [id, key])
	var chain_errors: Array[String] = []
	var s: Dictionary = _merged(slots, id, chain_errors)
	errors.append_array(chain_errors)
	var kind_value: Variant = s.get("kind")
	if not kind_value is String or not kind_value in KINDS:
		errors.append("%s: kind must be one of %s" % [id, ", ".join(KINDS)])
		return
	var planned: Variant = s.get("planned", false)
	if not planned is bool:
		errors.append("%s: planned must be true or false" % id)
	if s.has("optional") and not s.optional is bool:
		errors.append("%s: optional must be true or false" % id)
	var file: Variant = s.get("file")
	if not file is String:
		errors.append("%s: file must be a string" % id)
	elif file == "":
		if not planned is bool or not planned:
			errors.append("%s: file is empty but the slot is not planned" % id)
	else:
		_validate_path(id, "file", file, errors)
	for key in ["meta", "fallback"]:
		if s.has(key):
			if not s[key] is String or s[key] == "":
				errors.append("%s: %s must be a non-empty string" % [id, key])
			else:
				_validate_path(id, key, s[key], errors)
	if s.has("extra_files"):
		if not _is_string_array(s.extra_files):
			errors.append("%s: extra_files must be an array of strings" % id)
		else:
			for f in s.extra_files:
				_validate_path(id, "extra_files", f, errors)
	if s.has("used") and not (s.used is String and s.used in USED_VALUES):
		errors.append("%s: used must be one of %s" % [id, ", ".join(USED_VALUES)])
	if s.has("source") and not s.source is String:
		errors.append("%s: source must be a string" % id)
	var c: Variant = s.get("contract", {})
	if not c is Dictionary:
		errors.append("%s: contract must be an object" % id)
		return
	_validate_contract(id, kind_value, c, errors, warnings)

static func _validate_path(id: String, key: String, value: String, errors: Array[String]) -> void:
	if value.contains("..") or value.begins_with("/") or value.contains("\\") or (value.contains("://") and not value.begins_with("res://")):
		errors.append("%s: %s '%s' is not a clean relative path (or res:// path)" % [id, key, value])

static func _validate_contract(id: String, kind_name: String, c: Dictionary, errors: Array[String], warnings: Array[String]) -> void:
	var known: Array = CONTRACT_KEYS[kind_name]
	for key in c:
		if not key in known:
			warnings.append("%s: contract key '%s' is not known for kind %s" % [id, key, kind_name])
	if c.has("scale"):
		var s: Variant = c.scale
		var ok := false
		if _is_num(s):
			ok = float(s) > 0.0
		elif s is Array and (s as Array).size() == 3:
			ok = true
			for e in s:
				ok = ok and _is_num(e) and float(e) > 0.0
		if not ok:
			errors.append("%s: contract.scale must be a positive number or three positive numbers" % id)
	var bones: Dictionary = {}
	if c.has("bones"):
		if not c.bones is Dictionary:
			errors.append("%s: contract.bones must be an object" % id)
		else:
			bones = c.bones
			for logical in bones:
				if not bones[logical] is String or bones[logical] == "":
					errors.append("%s: contract.bones.%s must be a non-empty string" % [id, logical])
	if c.has("bone_groups"):
		if not c.bone_groups is Dictionary:
			errors.append("%s: contract.bone_groups must be an object" % id)
		else:
			for group in c.bone_groups:
				if not _is_string_array(c.bone_groups[group]):
					errors.append("%s: contract.bone_groups.%s must be an array of strings" % [id, group])
				elif not group in PATTERN_GROUPS:
					for logical in c.bone_groups[group]:
						if not bones.has(logical):
							errors.append("%s: contract.bone_groups.%s names '%s', which is not in contract.bones" % [id, group, logical])
	if c.has("clips"):
		if not c.clips is Dictionary:
			errors.append("%s: contract.clips must be an object" % id)
		else:
			for logical in c.clips:
				if not c.clips[logical] is String or c.clips[logical] == "":
					errors.append("%s: contract.clips.%s must be a non-empty string" % [id, logical])
	if c.has("tick_hz") and not (_is_num(c.tick_hz) and float(c.tick_hz) > 0.0):
		errors.append("%s: contract.tick_hz must be a positive number" % id)
	for key in ["timing_ticks", "timing_s", "pose"]:
		if c.has(key):
			if not c[key] is Dictionary:
				errors.append("%s: contract.%s must be an object" % [id, key])
			else:
				for name in c[key]:
					if not _is_num(c[key][name]) or float(c[key][name]) < 0.0:
						errors.append("%s: contract.%s.%s must be a number >= 0" % [id, key, name])
	for key in ["states", "directions", "pieces_required", "ids_required", "axes", "features"]:
		if c.has(key) and not _is_string_array(c[key]):
			errors.append("%s: contract.%s must be an array of strings" % [id, key])
	for key in ["seconds", "loop_in", "loop_out"]:
		if c.has(key) and not (_is_num(c[key]) and float(c[key]) >= 0.0):
			errors.append("%s: contract.%s must be a number >= 0" % [id, key])
	if c.has("loop_in") and c.has("loop_out") and _is_num(c.loop_in) and _is_num(c.loop_out) and float(c.loop_out) <= float(c.loop_in):
		errors.append("%s: contract.loop_out must be after loop_in" % id)
	if c.has("aspect") and not c.aspect is String:
		errors.append("%s: contract.aspect must be a string like 16:9" % id)
	if c.has("size") and not (c.size is Array and (c.size as Array).size() == 2 and _is_num(c.size[0]) and _is_num(c.size[1])):
		errors.append("%s: contract.size must be [width, height]" % id)
	if c.has("crops"):
		if not c.crops is Dictionary:
			errors.append("%s: contract.crops must be an object" % id)
		else:
			for name in c.crops:
				var r: Variant = c.crops[name]
				if not (r is Array and (r as Array).size() == 4 and _is_num(r[0]) and _is_num(r[1]) and _is_num(r[2]) and _is_num(r[3])):
					errors.append("%s: contract.crops.%s must be [x, y, w, h]" % [id, name])
