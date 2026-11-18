extends RefCounted
## Vertex animation texture baker (headless, inside Godot).
##
## Plays every clip of a skinned model with the same AnimationPlayer.seek the game uses, applies the code-side
## overrides (e.g. head bone scale) and records the deformed vertex positions and normals of every frame:
##   position texture  RGBAH   width = vertex count (all surfaces, in surface order), height = rows (all clips)
##   normal texture    RGBA8   n*.5+.5
## Positions are stored relative to table.center (half floats keep their precision near zero) and are in the model
## root's space (the node the PackedScene instantiates), so the instance transform is the only thing the game adds.
##
## bake() returns a Dictionary:
##   pos_image, nrm_image : Image
##   mesh        : ArrayMesh (static, one surface per source surface; UV2 = (column, hit weight); custom_aabb set)
##   table       : Dictionary  clip name -> {start, rows, intervals, rate, duration, loop, anim_length}
##   total_rows, vertex_count, center (Vector3), aabb (AABB)
##   bones       : Dictionary  bone name -> PackedVector3Array (one model-space position per row)
##   albedo      : Array[Texture2D] (per surface; from the source materials) + material_info per surface
##   stats       : timings and the engine path used
## Row arrays are not stored in the dictionary beyond the images; call save() / load_baked() for files.

const SPEC := preload("res://chapter1/view/actors/vat/walker_vat_spec.gd")
const SHADER_PATH := "res://chapter1/view/actors/vat/walker_vat.gdshader"

var host: Node = null            ## must be inside a SceneTree (AnimationPlayer needs it)
var use_engine_bake := true      ## MeshInstance3D.bake_mesh_from_current_skeleton_pose; false = CPU skinning
var progress: Callable = Callable()
var errors: Array[String] = []

class Target:
	var mi: MeshInstance3D
	var surface := 0
	var count := 0
	var offset := 0
	var bind_bone: PackedInt32Array = PackedInt32Array()
	var bind_matrix_base: Array[Transform3D] = []
	var arrays: Array = []

static func engine_supports_bake() -> bool:
	return ClassDB.class_has_method("MeshInstance3D", "bake_mesh_from_current_skeleton_pose")

static func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.mesh != null:
		out.append(node)
	for child in node.get_children():
		_collect(child, out)

func bake(model_scene: PackedScene, clips: Array, fps: float, overrides: Callable, tracked_bones: Array = [], hit_bones: Array = [], hit_exclude_bones: Array = []) -> Dictionary:
	var stats := {}
	var t_start := Time.get_ticks_usec()
	var model: Node3D = model_scene.instantiate()
	host.add_child(model)
	var rig: Skeleton3D = model.find_child("Skeleton3D", true, false)
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var meshes: Array[MeshInstance3D] = []
	_collect(model, meshes)
	var targets: Array[Target] = []
	var column := 0
	var hit_set := {}
	for bone_name in hit_bones:
		var bi := rig.find_bone(bone_name)
		if bi >= 0:
			hit_set[bi] = true
	# Bones whose vertices never take part in the hit blend (head and neck: a straight vertex blend of a rotating head
	# deforms it). The weight of a vertex is scaled down by its share on these bones.
	var exclude_set := {}
	for bone_name in hit_exclude_bones:
		var xi := rig.find_bone(bone_name)
		if xi >= 0:
			exclude_set[xi] = true
			hit_set.erase(xi)
	var albedo: Array = []
	var material_info: Array = []
	for mi in meshes:
		for s in mi.mesh.get_surface_count():
			var t := Target.new()
			t.mi = mi
			t.surface = s
			t.arrays = mi.mesh.surface_get_arrays(s)
			t.count = (t.arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			t.offset = column
			column += t.count
			_prepare_skin(t, rig)
			targets.append(t)
			var mat := mi.get_active_material(s)
			var info := {"roughness": .79, "metallic": 0.0, "cull_mode": 0}
			var tex: Texture2D = null
			if mat is BaseMaterial3D:
				tex = mat.albedo_texture
				info.roughness = mat.roughness
				info.metallic = mat.metallic
				info.cull_mode = int(mat.cull_mode)
			albedo.append(tex)
			material_info.append(info)
	var vertex_count := column
	# Row table.
	var table := {}
	var total_rows := 0
	for clip in clips:
		var intervals: int = int(clip.get("intervals", int(round(float(clip.duration) * fps))))
		var rows := intervals + 1
		var anim: Animation = player.get_animation(String(clip.anim))
		table[String(clip.name)] = {
			"start": total_rows, "rows": rows, "intervals": intervals,
			"rate": float(intervals) / float(clip.duration), "duration": float(clip.duration),
			"loop": bool(clip.loop), "anim_length": anim.length if anim != null else -1.0,
		}
		total_rows += rows
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	positions.resize(0)
	var bones := {}
	for bone_name in tracked_bones:
		bones[bone_name] = PackedVector3Array()
	var tracked_index := {}
	for bone_name in tracked_bones:
		tracked_index[bone_name] = rig.find_bone(bone_name)
	var rel_skel: Transform3D = model.global_transform.affine_inverse() * rig.global_transform
	var rel_basis := {}
	var rel := {}
	for t in targets:
		if not rel.has(t.mi):
			rel[t.mi] = model.global_transform.affine_inverse() * t.mi.global_transform
			rel_basis[t.mi] = Transform3D((rel[t.mi] as Transform3D).basis.orthonormalized(), Vector3.ZERO)
	var aabb := AABB()
	var aabb_started := false
	var t_rows := Time.get_ticks_usec()
	var done_rows := 0
	for clip in clips:
		var entry: Dictionary = table[String(clip.name)]
		for i in int(entry.rows):
			var time_ := float(clip.duration) * float(i) / float(entry.intervals)
			player.play(String(clip.anim), 0)
			player.seek(time_, true)
			if overrides.is_valid():
				overrides.call(rig)
			for t in targets:
				var pn := _skin_target(t, rig, use_engine_bake)
				var p: PackedVector3Array = pn[0]
				var n: PackedVector3Array = pn[1]
				positions.append_array((rel[t.mi] as Transform3D) * p)
				normals.append_array((rel_basis[t.mi] as Transform3D) * n)
			for bone_name in tracked_bones:
				var bi: int = tracked_index[bone_name]
				var list: PackedVector3Array = bones[bone_name]
				list.append(rel_skel * rig.get_bone_global_pose(bi).origin)
				bones[bone_name] = list
			done_rows += 1
	stats["rows_usec"] = Time.get_ticks_usec() - t_rows
	# Bounds over all rows (native loop: the baked arrays are read once).
	var t_post := Time.get_ticks_usec()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	# AABB over the big array without a GDScript per-vertex loop: use per-row-per-target meshes' aabb via ArrayMesh.
	for r in total_rows:
		var row_slice := positions.slice(r * vertex_count, (r + 1) * vertex_count)
		var m := ArrayMesh.new()
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = row_slice
		m.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arr)
		var b := m.get_aabb()
		lo = lo.min(b.position)
		hi = hi.max(b.end)
	aabb = AABB(lo, hi - lo)
	var center := aabb.get_center()
	positions = Transform3D(Basis.IDENTITY, -center) * positions
	var pos_image := Image.create_from_data(vertex_count, total_rows, false, Image.FORMAT_RGBF, positions.to_byte_array())
	pos_image.convert(Image.FORMAT_RGBAH)
	normals = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * .5), Vector3(.5, .5, .5)) * normals
	var nrm_image := Image.create_from_data(vertex_count, total_rows, false, Image.FORMAT_RGBF, normals.to_byte_array())
	nrm_image.convert(Image.FORMAT_RGBA8)
	stats["post_usec"] = Time.get_ticks_usec() - t_post
	# Static mesh: rest positions from row 0, normals, uv, uv2 = (column, hit weight), indices.
	var t_mesh := Time.get_ticks_usec()
	var mesh := ArrayMesh.new()
	for t in targets:
		var src: Array = t.arrays
		var uv2 := PackedVector2Array()
		uv2.resize(t.count)
		var weights_per_vertex := _hit_weights(t, hit_set, exclude_set)
		for v in t.count:
			uv2[v] = Vector2(float(t.offset + v), weights_per_vertex[v])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = positions.slice(t.offset, t.offset + t.count)
		arr[Mesh.ARRAY_NORMAL] = (rel_basis[t.mi] as Transform3D) * (src[Mesh.ARRAY_NORMAL] as PackedVector3Array)
		arr[Mesh.ARRAY_TEX_UV] = src[Mesh.ARRAY_TEX_UV]
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_INDEX] = src[Mesh.ARRAY_INDEX]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var margin := aabb.size * .02 + Vector3.ONE * .001
	mesh.custom_aabb = AABB(aabb.position - margin, aabb.size + margin * 2.0)
	stats["mesh_usec"] = Time.get_ticks_usec() - t_mesh
	host.remove_child(model)
	model.free()
	stats["total_usec"] = Time.get_ticks_usec() - t_start
	stats["engine_bake"] = use_engine_bake
	return {
		"pos_image": pos_image, "nrm_image": nrm_image, "mesh": mesh, "table": table,
		"total_rows": total_rows, "vertex_count": vertex_count, "center": center, "aabb": aabb,
		"bones": bones, "albedo": albedo, "material_info": material_info, "stats": stats,
		"surface_counts": targets.map(func(x): return x.count),
	}

## Bind index -> skeleton bone, and the bind pose.
func _prepare_skin(t: Target, rig: Skeleton3D) -> void:
	var skin: Skin = t.mi.skin
	if skin == null:
		return
	for i in skin.get_bind_count():
		var bone := skin.get_bind_bone(i)
		var bname := skin.get_bind_name(i)
		if bname != "":
			bone = rig.find_bone(bname)
		t.bind_bone.append(bone)
		t.bind_matrix_base.append(skin.get_bind_pose(i))

func _hit_weights(t: Target, hit_set: Dictionary, exclude_set: Dictionary = {}) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(t.count)
	var bones: PackedInt32Array = t.arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = t.arrays[Mesh.ARRAY_WEIGHTS]
	if bones.is_empty() or hit_set.is_empty():
		return out
	var stride := bones.size() / t.count
	for v in t.count:
		var sum := 0.0
		var excluded := 0.0
		for k in stride:
			var w := weights[v * stride + k]
			if w > 0.0:
				var bind := bones[v * stride + k]
				var bone: int = t.bind_bone[bind] if bind < t.bind_bone.size() else bind
				if hit_set.has(bone):
					sum += w
				elif exclude_set.has(bone):
					excluded += w
		out[v] = clampf(sum, 0.0, 1.0) * (1.0 - clampf(excluded, 0.0, 1.0))
	return out

## Returns [positions, normals] of one surface in the mesh instance's local space (as drawn).
func _skin_target(t: Target, rig: Skeleton3D, engine: bool) -> Array:
	if engine:
		var baked: ArrayMesh = t.mi.bake_mesh_from_current_skeleton_pose()
		var arrays := baked.surface_get_arrays(t.surface)
		return [arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_NORMAL]]
	return cpu_skin(t, rig)

## CPU linear blend skinning (fallback and cross-check). Result in the mesh instance's local space.
func cpu_skin(t: Target, rig: Skeleton3D) -> Array:
	var count := t.count
	var verts: PackedVector3Array = t.arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = t.arrays[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = t.arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = t.arrays[Mesh.ARRAY_WEIGHTS]
	var stride := bones.size() / count
	var to_local: Transform3D = t.mi.global_transform.affine_inverse() * rig.global_transform
	var mats: Array[Transform3D] = []
	for i in t.bind_bone.size():
		mats.append(to_local * rig.get_bone_global_pose(t.bind_bone[i]) * t.bind_matrix_base[i])
	var out_p := PackedVector3Array()
	var out_n := PackedVector3Array()
	out_p.resize(count)
	out_n.resize(count)
	for v in count:
		var p := Vector3.ZERO
		var n := Vector3.ZERO
		var base := v * stride
		var wsum := 0.0
		for k in stride:
			var w := weights[base + k]
			if w <= 0.0:
				continue
			var m: Transform3D = mats[bones[base + k]]
			p += (m * verts[v]) * w
			n += (m.basis * norms[v]) * w
			wsum += w
		out_p[v] = p
		out_n[v] = n.normalized()
	return [out_p, out_n]

## Independent check of a bake(): fresh model, rows visited in reverse order.
##  bones   : tracked bone positions against the table (model units; multiply by the instance scale for meters)
##  vertex  : every `row_step`-th row, texture texel (half float + center) against a fresh skinning pass
##  engine_vs_cpu : engine bake against CPU skinning on the same rows (only when the engine path exists)
##  normal  : largest angle between texel normal and fresh normal, degrees
func verify(model_scene: PackedScene, clips: Array, overrides: Callable, data: Dictionary, tracked_bones: Array, row_step: int = 8) -> Dictionary:
	var model: Node3D = model_scene.instantiate()
	host.add_child(model)
	var rig: Skeleton3D = model.find_child("Skeleton3D", true, false)
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var meshes: Array[MeshInstance3D] = []
	_collect(model, meshes)
	var targets: Array[Target] = []
	var column := 0
	for mi in meshes:
		for s in mi.mesh.get_surface_count():
			var t := Target.new()
			t.mi = mi
			t.surface = s
			t.arrays = mi.mesh.surface_get_arrays(s)
			t.count = (t.arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			t.offset = column
			column += t.count
			_prepare_skin(t, rig)
			targets.append(t)
	var rel_skel: Transform3D = model.global_transform.affine_inverse() * rig.global_transform
	var rel := {}
	var rel_basis := {}
	for t in targets:
		if not rel.has(t.mi):
			rel[t.mi] = model.global_transform.affine_inverse() * t.mi.global_transform
			rel_basis[t.mi] = Transform3D((rel[t.mi] as Transform3D).basis.orthonormalized(), Vector3.ZERO)
	var result := {"bone_max_err": 0.0, "bone_checked": 0, "vertex_max_err": 0.0, "vertex_mean_err": 0.0, "vertex_checked": 0,
		"engine_vs_cpu_max": -1.0, "normal_max_deg": 0.0, "normal_texel_vs_engine_deg": 0.0, "per_clip_bone_max": {}}
	var sum_err := 0.0
	var step_index := clips.size()
	while step_index > 0:
		step_index -= 1
		var clip: Dictionary = clips[step_index]
		var entry: Dictionary = data.table[String(clip.name)]
		var clip_max := 0.0
		for k in int(entry.rows):
			var i: int = int(entry.rows) - 1 - k
			var time_ := float(clip.duration) * float(i) / float(entry.intervals)
			var row: int = int(entry.start) + i
			player.play(String(clip.anim), 0)
			player.seek(time_, true)
			if overrides.is_valid():
				overrides.call(rig)
			for bone_name in tracked_bones:
				var p: Vector3 = rel_skel * rig.get_bone_global_pose(rig.find_bone(bone_name)).origin
				var e := p.distance_to((data.bones[bone_name] as PackedVector3Array)[row])
				clip_max = maxf(clip_max, e)
				result.bone_checked += 1
			if row % row_step != 0 and i != 0:
				continue
			for t in targets:
				var fresh := _skin_target(t, rig, use_engine_bake)
				var fp: PackedVector3Array = (rel[t.mi] as Transform3D) * (fresh[0] as PackedVector3Array)
				var fn: PackedVector3Array = (rel_basis[t.mi] as Transform3D) * (fresh[1] as PackedVector3Array)
				if use_engine_bake:
					var cpu := cpu_skin(t, rig)
					var cp: PackedVector3Array = (rel[t.mi] as Transform3D) * (cpu[0] as PackedVector3Array)
					var worst := 0.0
					for v in t.count:
						worst = maxf(worst, fp[v].distance_to(cp[v]))
					result.engine_vs_cpu_max = maxf(result.engine_vs_cpu_max, worst)
					var key := "surface%d" % t.surface
					result[key] = maxf(float(result.get(key, 0.0)), worst)
				for v in t.count:
					var px: Color = data.pos_image.get_pixel(t.offset + v, row)
					var tp: Vector3 = Vector3(px.r, px.g, px.b) + (data.center as Vector3)
					var err: float = tp.distance_to(fp[v])
					sum_err += err
					result.vertex_max_err = maxf(result.vertex_max_err, err)
					result.vertex_checked += 1
					var nx: Color = data.nrm_image.get_pixel(t.offset + v, row)
					var tn := (Vector3(nx.r, nx.g, nx.b) * 2.0 - Vector3.ONE).normalized()
					var fnv := fn[v].normalized()
					var ang := rad_to_deg(acos(clampf(tn.dot(fnv), -1.0, 1.0)))
					result.normal_texel_vs_engine_deg = maxf(result.normal_texel_vs_engine_deg, ang)
		result.per_clip_bone_max[String(clip.name)] = clip_max
		result.bone_max_err = maxf(result.bone_max_err, clip_max)
	result.vertex_mean_err = sum_err / maxf(1.0, float(result.vertex_checked))
	host.remove_child(model)
	model.free()
	return result

## Row (float) of a clip for a time in seconds: integer part = row, fraction = blend toward the next row.
static func clip_row(table: Dictionary, clip: String, time_: float) -> float:
	var c: Dictionary = table[clip]
	var u: float
	if c.loop:
		u = fposmod(time_, c.duration) * c.rate
	else:
		u = clampf(time_, 0.0, c.duration) * c.rate
	return float(c.start) + minf(u, float(c.intervals))

# ---- files -----------------------------------------------------------------------------------------------------

## Writes <dir>/pos.res, nrm.res, mesh.res, table.json. dir is a res:// path under res://_local/vat/. Returns file sizes.
func save(data: Dictionary, dir: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var sizes := {}
	var pos_tex := ImageTexture.create_from_image(data.pos_image)
	var nrm_tex := ImageTexture.create_from_image(data.nrm_image)
	var files := {
		"pos.res": pos_tex, "nrm.res": nrm_tex, "mesh.res": data.mesh,
	}
	for fname in files:
		var err := ResourceSaver.save(files[fname], dir.path_join(fname))
		if err != OK:
			errors.append("save %s failed (%d)" % [fname, err])
		sizes[fname] = _file_size(dir.path_join(fname))
	var meta := {
		"table": data.table, "total_rows": data.total_rows, "vertex_count": data.vertex_count,
		"center": [data.center.x, data.center.y, data.center.z],
		"aabb": [data.aabb.position.x, data.aabb.position.y, data.aabb.position.z, data.aabb.size.x, data.aabb.size.y, data.aabb.size.z],
		"material_info": data.material_info,
		"bones": {},
	}
	for bone_name in data.bones:
		var flat := []
		for p in (data.bones[bone_name] as PackedVector3Array):
			flat.append_array([p.x, p.y, p.z])
		meta.bones[bone_name] = flat
	var f := FileAccess.open(dir.path_join("table.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta))
	f.close()
	sizes["table.json"] = _file_size(dir.path_join("table.json"))
	return sizes

static func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var n := f.get_length()
	f.close()
	return n

## Loads what save() wrote. Returns {} if missing. model_scene supplies the albedo textures (from its materials).
static func load_baked(dir: String, model_scene: PackedScene) -> Dictionary:
	var f := FileAccess.open(dir.path_join("table.json"), FileAccess.READ)
	if f == null:
		return {}
	var meta: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var out := {
		"pos_tex": load(dir.path_join("pos.res")), "nrm_tex": load(dir.path_join("nrm.res")),
		"mesh": load(dir.path_join("mesh.res")), "table": meta.table, "total_rows": int(meta.total_rows),
		"vertex_count": int(meta.vertex_count), "material_info": meta.material_info,
		"center": Vector3(meta.center[0], meta.center[1], meta.center[2]),
	}
	var bones := {}
	for bone_name in meta.bones:
		var arr := PackedVector3Array()
		var flat: Array = meta.bones[bone_name]
		for i in range(0, flat.size(), 3):
			arr.append(Vector3(flat[i], flat[i + 1], flat[i + 2]))
		bones[bone_name] = arr
	out["bones"] = bones
	var tmp: Node = model_scene.instantiate()
	var meshes: Array[MeshInstance3D] = []
	_collect(tmp, meshes)
	var albedo := []
	for mi in meshes:
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			albedo.append(mat.albedo_texture if mat is BaseMaterial3D else null)
	tmp.free()
	out["albedo"] = albedo
	return out

## One ShaderMaterial per surface (same shader, own albedo texture). source = bake() result or load_baked() result.
static func make_materials(source: Dictionary) -> Array[ShaderMaterial]:
	var shader: Shader = load(SHADER_PATH)
	var pos_tex: Texture2D = source.get("pos_tex") if source.has("pos_tex") else ImageTexture.create_from_image(source.pos_image)
	var nrm_tex: Texture2D = source.get("nrm_tex") if source.has("nrm_tex") else ImageTexture.create_from_image(source.nrm_image)
	var mats: Array[ShaderMaterial] = []
	for s in (source.albedo as Array).size():
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("albedo_tex", source.albedo[s])
		m.set_shader_parameter("pos_tex", pos_tex)
		m.set_shader_parameter("nrm_tex", nrm_tex)
		m.set_shader_parameter("pos_center", source.center)
		var info: Dictionary = source.material_info[s]
		m.set_shader_parameter("roughness_value", float(info.roughness))
		m.set_shader_parameter("metallic_value", float(info.metallic))
		m.set_shader_parameter("rim_amount", SPEC.RIM)
		m.set_shader_parameter("rim_tint_amount", SPEC.RIM_TINT)
		mats.append(m)
	return mats
