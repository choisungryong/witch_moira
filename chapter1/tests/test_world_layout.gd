extends SceneTree
## World placement check (A12-0). The world presenter builds the ruined cloister from a layout file
## (chapter1/art/world/layout_chapter1.json). This check builds the world on its own and compares what was placed
## (sprite props, braziers, columns, every stone batch, the prop and contact-shadow surfaces, the grass geometry)
## with a snapshot taken from the code that held the same placement as literals, bit for bit (float32 bits, mesh faces).
##
##   python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_world_layout.gd [-- --dump=<file under _local/>] [-- --record]
##
## --dump=<file>   write the readable rows of every category (diff two dumps to see which record moved)
## --record        write the snapshot (chapter1/tests/fixtures/world_layout_before.json). Only for the one-time capture from the old code;
##                 later the snapshot is the reference, so a changed layout is a failed check until the snapshot is re-recorded on purpose.
## Last line: CHAPTER1_WORLD_LAYOUT_RESULT {...}; exit code 1 on a mismatch.
const World := preload("res://chapter1/view/world/chapter_world.gd")
const Core := preload("res://chapter1/core/chapter_core.gd")
const SNAPSHOT := "res://chapter1/tests/fixtures/world_layout_before.json"

class StubView extends Node3D:
	var run: RefCounted

var rows: Dictionary = {}
var hashes: Dictionary = {}

func _initialize() -> void:
	call_deferred("execute")

func _f32(value: Variant) -> PackedByteArray:
	var out := PackedFloat32Array()
	match typeof(value):
		TYPE_VECTOR2:
			out.append_array([value.x, value.y])
		TYPE_VECTOR3:
			out.append_array([value.x, value.y, value.z])
		TYPE_COLOR:
			out.append_array([value.r, value.g, value.b, value.a])
		TYPE_TRANSFORM3D:
			var t: Transform3D = value
			out.append_array([t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z, t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z])
		_:
			out.append(float(value))
	return out.to_byte_array()

func _text(value: Variant) -> String:
	match typeof(value):
		TYPE_VECTOR3:
			return "(%.6f,%.6f,%.6f)" % [value.x, value.y, value.z]
		TYPE_COLOR:
			return "(%.6f,%.6f,%.6f,%.6f)" % [value.r, value.g, value.b, value.a]
		TYPE_TRANSFORM3D:
			var t: Transform3D = value
			return "[%s %s %s | %s]" % [_text(t.basis.x), _text(t.basis.y), _text(t.basis.z), _text(t.origin)]
		TYPE_FLOAT:
			return "%.8f" % value
	return str(value)

## One record: a list of (value) parts; the digest takes the exact bits (double for plain floats), the row is for reading.
func add(category: String, parts: Array) -> void:
	var bytes := PackedByteArray()
	var text := PackedStringArray()
	for part in parts:
		match typeof(part):
			TYPE_STRING, TYPE_STRING_NAME:
				bytes.append_array(String(part).to_utf8_buffer())
			TYPE_BOOL:
				bytes.append(1 if part else 0)
			TYPE_INT:
				bytes.append_array(PackedInt64Array([part]).to_byte_array())
			TYPE_FLOAT:
				bytes.append_array(PackedFloat64Array([part]).to_byte_array())
			TYPE_PACKED_FLOAT32_ARRAY:
				bytes.append_array(part.to_byte_array())
			_:
				bytes.append_array(_f32(part))
		text.append(_text(part) if typeof(part) != TYPE_PACKED_FLOAT32_ARRAY else "faces:%d" % (part.size() / 9))
		bytes.append(0xFF)
	if not rows.has(category):
		rows[category] = []
		hashes[category] = HashingContext.new()
		hashes[category].start(HashingContext.HASH_SHA256)
	rows[category].append(" ".join(text))
	hashes[category].update(bytes)

func faces_of(mesh: Mesh) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for v in mesh.get_faces():
		out.append_array([v.x, v.y, v.z])
	return out

func surface_of(mesh: Mesh) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if mesh == null or mesh.get_surface_count() == 0:
		return out
	var arrays := mesh.surface_get_arrays(0)
	for v in arrays[Mesh.ARRAY_VERTEX]:
		out.append_array([v.x, v.y, v.z])
	if arrays[Mesh.ARRAY_TEX_UV] != null:
		for v in arrays[Mesh.ARRAY_TEX_UV]:
			out.append_array([v.x, v.y])
	if arrays[Mesh.ARRAY_COLOR] != null:
		for c in arrays[Mesh.ARRAY_COLOR]:
			out.append_array([c.r, c.g, c.b, c.a])
	return out

func execute() -> void:
	var dump_path := ""
	var record := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dump="):
			dump_path = arg.trim_prefix("--dump=")
		elif arg == "--record":
			record = true
	var view := StubView.new()
	view.run = Core.new()
	root.add_child(view)
	var world: RefCounted = World.new()
	world.setup(view)
	collect(world)
	var result := {}
	for category in rows:
		result[category] = {"count": rows[category].size(), "sha256": hashes[category].finish().hex_encode()}
	if not dump_path.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dump_path).get_base_dir())
		var file := FileAccess.open(dump_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(rows, "\t"))
		file.close()
	if record:
		var out := FileAccess.open(SNAPSHOT, FileAccess.WRITE)
		out.store_string(JSON.stringify({"about": "Placement of the world presenter as built by the code that held it as literals (A12-0 baseline, commit 3417a2e). test_world_layout.gd compares bit for bit.", "categories": result}, "\t"))
		out.close()
		print("CHAPTER1_WORLD_LAYOUT_RESULT ", JSON.stringify({"recorded": result}))
		quit(0)
		return
	var failures: Array[String] = []
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(SNAPSHOT)) if FileAccess.file_exists(SNAPSHOT) else null
	if not expected is Dictionary or not expected.get("categories") is Dictionary:
		failures.append("snapshot missing or unreadable: " + SNAPSHOT)
	else:
		var want: Dictionary = expected.categories
		for category in want:
			if not result.has(category):
				failures.append("%s: nothing was placed (snapshot has %d)" % [category, int(want[category].count)])
			elif int(result[category].count) != int(want[category].count):
				failures.append("%s: %d records, snapshot has %d" % [category, result[category].count, int(want[category].count)])
			elif result[category].sha256 != want[category].sha256:
				failures.append("%s: %d records differ from the snapshot in value (run with --dump= on both and diff)" % [category, result[category].count])
		for category in result:
			if not want.has(category):
				failures.append("%s: not in the snapshot" % category)
	for message in failures:
		push_error(message)
	print("CHAPTER1_WORLD_LAYOUT_RESULT ", JSON.stringify({"categories": result.size(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func collect(world: RefCounted) -> void:
	for entry in world._prop_entries:
		add("props", [entry.id, entry.at, float(entry.height), entry.tint, bool(entry.mirror), bool(entry.get("solid", false))])
	for column in world.columns31:
		add("columns", [column.id, column.at, float(column.height), column.tint])
	# The records the batches are built from. South stones only: the north foundation stones were built and then hidden by the old code,
	# so they are not placements (z <= 0 is left out of the comparison on both sides).
	for record in world._stones:
		if record.transform.origin.z > 0:
			add("stones", [record.transform, record.tint, bool(record.wall)])
	for record in world.masonry22:
		add("masonry", [record.transform, record.tint, int(record.zone)])
	for record in world._edge_blocks:
		add("edge_blocks", [record.transform, record.tint])
	for record in world._edge_iron:
		add("edge_iron", [record.transform, record.tint])
	for at in world._edge_anchors:
		add("edge_anchors", [at])
	var base: Array = world._warm_base
	var lamp := 0
	for child in world.root.get_children():
		if child is OmniLight3D and String(child.name) != "HeroLight":
			add("lights", [child.position, child.light_color, float(child.light_energy), float(child.omni_range), bool(child.shadow_enabled), float(base[lamp])])
			lamp += 1
		elif child is MultiMeshInstance3D and not String(child.name).begins_with("Seal"):
			# Instance values cannot be read back in a headless run (the dummy renderer keeps counts only), so a batch is checked by what it
			# draws and how; where its instances stand is checked on the records below (stones, masonry, edge).
			var mm: MultiMesh = child.multimesh
			add("batches", [mm.mesh.get_class(), faces_of(mm.mesh), int(child.cast_shadow), mm.use_colors])
		elif child is MeshInstance3D and (String(child.name).begins_with("Authored") or String(child.name).begins_with("Original") or String(child.name).begins_with("CloisterPropContact")):
			add("surfaces", [String(child.name).rstrip("0123456789"), surface_of(child.mesh), int(child.cast_shadow)])
	# Grass: vertices, uvs and colours of every grass node in child order (one mesh or several, the geometry is the same).
	var verts := PackedFloat32Array()
	var uvs := PackedFloat32Array()
	var colors := PackedFloat32Array()
	for child in world.root.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("TaperedGrass"):
			var arrays: Array = child.mesh.surface_get_arrays(0)
			for v in arrays[Mesh.ARRAY_VERTEX]:
				verts.append_array([v.x, v.y, v.z])
			for v in arrays[Mesh.ARRAY_TEX_UV]:
				uvs.append_array([v.x, v.y])
			for c in arrays[Mesh.ARRAY_COLOR]:
				colors.append_array([c.r, c.g, c.b, c.a])
	add("grass", [verts, uvs, colors])
	add("grass_stats", [int(world.art_status.grass_patches), int(world.art_status.grass_blades)])
