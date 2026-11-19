extends RefCounted
## Check tool, not product code. Follows one contract document (a fixture or an adapter output) against a screen contract schema
## (chapter1/tests/contracts/<id>.contract.json, docs/specs/T8 2.2). The same rules as tools/dev/screen_contract_check.py (which stays
## the judge of record: it also reads the schema files themselves, the screen and adapter sources, and the layout dumps); this copy
## lets test_screen_contracts.gd say "the fixture follows the schema" from inside the engine, and check an adapter output right where
## it is made. JSON read by the engine has only floats: an "int" accepts a float without a fraction.

static func check_document(doc: Variant, schema: Dictionary, label: String, fixture: bool) -> Array[String]:
	var out: Array[String] = []
	if not doc is Dictionary:
		out.append("%s: the document must be an object" % label)
		return out
	if String(doc.get("screen", "")) != String(schema.get("screen", "")):
		out.append("%s: \"screen\" is %s, the schema is %s" % [label, str(doc.get("screen")), str(schema.get("screen"))])
	if not _same_number(doc.get("contract_version", null), schema.get("contract_version", null)):
		out.append("%s: contract_version %s, the schema has %s" % [label, str(doc.get("contract_version")), str(schema.get("contract_version"))])
	var body := {}
	for key in doc:
		if key != "screen" and key != "contract_version": body[key] = doc[key]
	_object(body, schema.get("fields", {}), label, out, fixture)
	return out

static func _same_number(a: Variant, b: Variant) -> bool:
	return (a is float or a is int) and (b is float or b is int) and float(a) == float(b)

static func _object(value: Variant, fields: Dictionary, path: String, out: Array[String], fixture: bool) -> void:
	if not value is Dictionary:
		out.append("%s: expected an object" % path)
		return
	for name in value:
		if not fields.has(name): out.append("%s.%s: unknown key" % [path, name])
	for name in fields:
		var spec: Dictionary = fields[name]
		var here := "%s.%s" % [path, name]
		if not value.has(name):
			if fixture and spec.has("requested"): out.append("%s: a requested field must be in the fixture (with a stand-in value)" % here)
			elif not bool(spec.get("optional", false)) and not spec.has("requested"): out.append("%s: required field is missing" % here)
			continue
		_value(value[name], spec, here, out, fixture)

static func _value(value: Variant, spec: Dictionary, path: String, out: Array[String], fixture: bool) -> void:
	if value == null:
		if not bool(spec.get("nullable", false)): out.append("%s: null is not allowed" % path)
		return
	var kind := String(spec.get("type", ""))
	match kind:
		"string":
			if not value is String: out.append("%s: expected a string" % path)
			elif spec.has("max_len") and String(value).length() > int(spec.max_len):
				out.append("%s: %d characters, the schema allows %d" % [path, String(value).length(), int(spec.max_len)])
		"int":
			if not (value is int or (value is float and is_equal_approx(value, roundf(value)))): out.append("%s: expected an integer" % path)
			else: _range(float(value), spec, path, out)
		"float":
			if not (value is int or value is float): out.append("%s: expected a number" % path)
			else: _range(float(value), spec, path, out)
		"bool":
			if not value is bool: out.append("%s: expected true or false" % path)
		"enum":
			if not (value is String and value in spec.get("values", [])): out.append("%s: %s is not one of %s" % [path, str(value), str(spec.get("values"))])
		"array":
			if not value is Array:
				out.append("%s: expected an array" % path)
				return
			if spec.has("min") and value.size() < int(spec.min): out.append("%s: %d items, at least %s" % [path, value.size(), str(spec.min)])
			if spec.has("max") and value.size() > int(spec.max): out.append("%s: %d items, at most %s" % [path, value.size(), str(spec.max)])
			for index in value.size(): _value(value[index], spec.item, "%s[%d]" % [path, index], out, fixture)
		"object":
			_object(value, spec.get("fields", {}), path, out, fixture)
		_:
			out.append("%s: the schema has an unknown type %s" % [path, kind])

static func _range(value: float, spec: Dictionary, path: String, out: Array[String]) -> void:
	if spec.has("min") and value < float(spec.min): out.append("%s: %s is below the minimum %s" % [path, str(value), str(spec.min)])
	if spec.has("max") and value > float(spec.max): out.append("%s: %s is above the maximum %s" % [path, str(value), str(spec.max)])

## The contract fixture of a screen and variant: fixtures/contracts/<id>.<variant>.json first, else a draft in fixtures/ui/ whose "screen" is <id>
## (its file name may carry a prefix: title_v0.normal.json). {} when there is none. "__path" names the file.
static func load_fixture(id_: String, variant: String) -> Dictionary:
	var first := "res://chapter1/tests/fixtures/contracts/%s.%s.json" % [id_, variant]
	var paths: Array[String] = [first]
	for file_name in DirAccess.get_files_at("res://chapter1/tests/fixtures/ui/"):
		if file_name.ends_with(".%s.json" % variant): paths.append("res://chapter1/tests/fixtures/ui/" + file_name)
	for path in paths:
		if not FileAccess.file_exists(path): continue
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if doc is Dictionary and String(doc.get("screen", "")) == id_:
			doc["__path"] = path
			return doc
	return {}
