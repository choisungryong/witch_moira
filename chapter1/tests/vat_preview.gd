extends Node3D
## Side by side: the bone-animated skeleton outlaw (left) and the baked MultiMesh instance (right), same clip, same time.
##   python tools/dev/godot.py --resolution 1280x720 --path . res://chapter1/tests/vat_preview.tscn -- --chapter1-profile-off --shots=_local/shots/vat-walker [--vat=_local/vat/walker] [--crowd=300]
## Reads the baked files written by bake_vat.gd --save. Shots are only allowed under _local/.

const Baker := preload("res://chapter1/view/actors/vat/vat_baker.gd")
const Spec := preload("res://chapter1/view/actors/vat/walker_vat_spec.gd")

var shots_dir := ""
var vat_dir := "_local/vat/walker"
var crowd_count := 300
var model_scene: PackedScene
var baked: Dictionary
var materials: Array[ShaderMaterial] = []
var camera: Camera3D
var hit_frames: Array = []       # 13 x [Transform3D x 10]
var hit_indices: Array[int] = []
var crowd_mm: MultiMesh
var crowd_state: Array = []
var crowd_time := 0.0
var crowd_active := false

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots_dir = arg.substr(8).replace("\\", "/")
		elif arg.begins_with("--vat="):
			vat_dir = arg.substr(6).replace("\\", "/")
		elif arg.begins_with("--crowd="):
			crowd_count = int(arg.substr(8))
	if shots_dir != "" and not shots_dir.begins_with("_local/"):
		push_error("vat_preview: --shots must be under _local/")
		get_tree().quit(2)
		return
	model_scene = load(Spec.MODEL_PATH)
	baked = Baker.load_baked("res://" + vat_dir, model_scene)
	if baked.is_empty():
		push_error("vat_preview: no baked data at %s (run bake_vat.gd --save first)" % vat_dir)
		get_tree().quit(2)
		return
	materials = Baker.make_materials(baked)
	var mesh: ArrayMesh = baked.mesh
	for s in materials.size():
		mesh.surface_set_material(s, materials[s])
	_build_environment()
	_sample_hit_frames()
	_run.call_deferred()

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.16, .17, .2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(.55, .55, .6)
	env.ambient_light_energy = .7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(.3, .27, .24)
	floor_mesh.material_override = fm
	add_child(floor_mesh)
	camera = Camera3D.new()
	camera.fov = 40
	add_child(camera)
	camera.current = true

func _make_original() -> Dictionary:
	var model: Node3D = load(Spec.MODEL_PATH).instantiate()
	var rig: Skeleton3D = model.find_child("Skeleton3D", true, false)
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_materials34(model)
	return {"model": model, "rig": rig, "player": player}

# Same material the game builds in _materials34.
func _materials34(node: Node) -> void:
	if node is MeshInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for surface in node.mesh.get_surface_count():
			var material: StandardMaterial3D = node.get_active_material(surface).duplicate()
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			material.albedo_color = Spec.TINT
			material.rim_enabled = true
			material.rim = Spec.RIM
			material.rim_tint = Spec.RIM_TINT
			node.set_surface_override_material(surface, material)
	for child in node.get_children():
		_materials34(child)

func _sample_hit_frames() -> void:
	var o := _make_original()
	add_child(o.model)
	for name_ in Spec.HIT_BONES:
		hit_indices.append(o.rig.find_bone(name_))
	for sample in 13:
		o.player.play("hit", 0)
		o.player.seek(float(sample) / 12.0 * Spec.HIT_DURATION, true)
		o.player.advance(0)
		var poses: Array[Transform3D] = []
		for index in hit_indices:
			poses.append(o.rig.get_bone_pose(index))
		hit_frames.append(poses)
	o.model.queue_free()

## Pose the bone-animated model the way _update_pose does.
func _pose_original(o: Dictionary, clip: String, time_: float, hit_age: float) -> void:
	o.player.play(clip, 0)
	o.player.seek(time_, true)
	if hit_age >= 0.0:
		var weight := .85 * sin(PI * hit_age)
		var sample_ := hit_age * 12.0
		var a := mini(int(sample_), 12)
		var b := mini(a + 1, 12)
		for i in hit_indices.size():
			var pose: Transform3D = (hit_frames[a][i] as Transform3D).interpolate_with(hit_frames[b][i], sample_ - float(a))
			o.rig.set_bone_pose(hit_indices[i], o.rig.get_bone_pose(hit_indices[i]).interpolate_with(pose, weight))
	Spec.apply_overrides(o.rig)

func _make_multimesh(count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = baked.mesh
	mm.instance_count = count
	return mm

func _set_instance(mm: MultiMesh, i: int, xf: Transform3D, clip: String, time_: float, hit_age: float, color: Variant = null) -> void:
	mm.set_instance_transform(i, xf)
	mm.set_instance_color(i, Color(Spec.TINT.r, Spec.TINT.g, Spec.TINT.b, 1.0) if color == null else color)
	var row := Baker.clip_row(baked.table, clip, time_)
	var hit_row := -1.0
	var hit_w := 0.0
	if hit_age >= 0.0:
		hit_row = Baker.clip_row(baked.table, "hit", hit_age * Spec.HIT_DURATION)
		hit_w = .85 * sin(PI * hit_age)
	mm.set_instance_custom_data(i, Color(row, hit_row, hit_w, 0.0))

func _xf(pos: Vector3, yaw: float, scale_: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_), pos)

func _capture(path: String) -> Image:
	for k in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if path != "":
		img.save_png(ProjectSettings.globalize_path("res://" + path))
	return img

func _run() -> void:
	if shots_dir == "":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + shots_dir))
	var yaw := 0.55
	var scale_ := .6
	var left := _make_original()
	left.model.scale = Vector3.ONE * scale_
	left.model.position = Vector3(-.9, 0, 0)
	left.model.rotation.y = yaw
	add_child(left.model)
	var mm := _make_multimesh(1)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	# clip, [times], hit base clip
	var plan := [
		["walk", [0.0, .23, .46], -1],
		["attack_slam", [.2, .42, .9], -1],
		["hit", [.15, .45, .8], 0],
		["death", [.3, .8, 1.6], -1],
		["idle", [0.0, .8, 1.5], -1],
	]
	var near_cells: Array = []
	var far_cells: Array = []
	for item in plan:
		for k in 3:
			var t_: float = item[1][k]
			var clip_name: String = item[0]
			var base_clip := clip_name
			var base_time := t_
			var hit_age := -1.0
			if clip_name == "hit":
				base_clip = "idle"
				base_time = .5
				hit_age = t_
			_pose_original(left, base_clip, base_time, hit_age)
			# Same viewpoint for both: the bone-animated one alone at the origin, then the baked one alone at the origin.
			left.model.position = Vector3.ZERO
			left.model.visible = true
			mmi.visible = false
			camera.look_at_from_position(Vector3(0, 1.5, 4.3), Vector3(0, .8, 0))
			var near_a := await _capture("%s/near_%s_%d_bone.png" % [shots_dir, clip_name, k])
			camera.look_at_from_position(Vector3(0, 3.2, 12.0), Vector3(0, .7, 0))
			var far_a := await _capture("%s/far_%s_%d_bone.png" % [shots_dir, clip_name, k])
			left.model.visible = false
			mmi.visible = true
			_set_instance(mm, 0, _xf(Vector3.ZERO, yaw, scale_), base_clip, base_time, hit_age)
			camera.look_at_from_position(Vector3(0, 1.5, 4.3), Vector3(0, .8, 0))
			var near_b := await _capture("%s/near_%s_%d_baked.png" % [shots_dir, clip_name, k])
			camera.look_at_from_position(Vector3(0, 3.2, 12.0), Vector3(0, .7, 0))
			var far_b := await _capture("%s/far_%s_%d_baked.png" % [shots_dir, clip_name, k])
			near_cells.append(_pair(near_a.get_region(Rect2i(440, 90, 400, 540)), near_b.get_region(Rect2i(440, 90, 400, 540)), 1))
			far_cells.append(_pair(far_a.get_region(Rect2i(540, 285, 200, 150)), far_b.get_region(Rect2i(540, 285, 200, 150)), 3))
	_sheet(near_cells, 800, 540, 3, "%s/compare-near.png" % shots_dir)
	_sheet(far_cells, 1200, 450, 2, "%s/compare-far.png" % shots_dir)
	left.model.queue_free()
	mmi.queue_free()
	await _crowd()
	get_tree().quit(0)

## Two crops side by side (bone-animated left, baked right), optionally enlarged with nearest-neighbour.
func _pair(a: Image, b: Image, zoom: int) -> Image:
	a.convert(Image.FORMAT_RGBA8)
	b.convert(Image.FORMAT_RGBA8)
	if zoom > 1:
		a.resize(a.get_width() * zoom, a.get_height() * zoom, Image.INTERPOLATE_NEAREST)
		b.resize(b.get_width() * zoom, b.get_height() * zoom, Image.INTERPOLATE_NEAREST)
	var out := Image.create(a.get_width() * 2, a.get_height(), false, Image.FORMAT_RGBA8)
	out.blit_rect(a, Rect2i(0, 0, a.get_width(), a.get_height()), Vector2i(0, 0))
	out.blit_rect(b, Rect2i(0, 0, b.get_width(), b.get_height()), Vector2i(a.get_width(), 0))
	return out

func _sheet(cells: Array, w: int, h: int, cols: int, path: String) -> void:
	var rows := int(ceil(float(cells.size()) / float(cols)))
	var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGBA8)
	for i in cells.size():
		(cells[i] as Image).convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(cells[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_png(ProjectSettings.globalize_path("res://" + path))

# ---- crowd: hundreds of baked walkers in one MultiMesh, with a front row of bone-animated ones for comparison -------------------

func _crowd() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	crowd_mm = _make_multimesh(crowd_count)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = crowd_mm
	add_child(mmi)
	var states := ["walk", "walk", "walk", "idle", "attack_slam", "death"]
	for i in crowd_count:
		var st: String = states[rng.randi() % states.size()]
		crowd_state.append({
			"pos": Vector3(rng.randf_range(-11, 11), 0, rng.randf_range(-12, -1.5)),
			"yaw": rng.randf_range(-PI, PI), "scale": .60 + .015 * float(rng.randi() % 4),
			"clip": st, "phase": rng.randf(), "color": Color(Spec.TINT.r, Spec.TINT.g, Spec.TINT.b, 1.0),
		})
	crowd_active = true
	# front row: alternating bone-animated (even) and baked (odd), same clips
	var originals: Array = []
	var front_clips := ["walk", "idle", "attack_slam", "walk", "death", "idle"]
	for k in front_clips.size():
		if k % 2 == 0:
			var o := _make_original()
			o.model.scale = Vector3.ONE * .6
			o.model.position = Vector3(-3.0 + float(k) * 1.2, 0, 2.0)
			o.model.rotation.y = .3
			add_child(o.model)
			originals.append([o, front_clips[k], k])
	var front_mm := _make_multimesh(front_clips.size())
	var front_mmi := MultiMeshInstance3D.new()
	front_mmi.multimesh = front_mm
	add_child(front_mmi)
	var shots := [["near", Vector3(0, 5.0, 8.5), Vector3(0, .5, -4.0)], ["far", Vector3(0, 11.0, 14.0), Vector3(0, 0, -5.0)]]
	for shot in shots:
		camera.look_at_from_position(shot[1], shot[2])
		for frame in 12:
			await get_tree().process_frame
		_front(originals, front_mm, front_clips)
		await _capture("%s/crowd-%s.png" % [shots_dir, shot[0]])
	crowd_active = false
	# Timing of the baked path on this machine (script side only, per frame update of every instance).
	var t0 := Time.get_ticks_usec()
	for f in 60:
		_update_crowd(float(f) / 60.0)
	print("crowd ", crowd_count, " instances: script update %.3f ms/frame" % [float(Time.get_ticks_usec() - t0) / 60.0 / 1000.0])

func _front(originals: Array, front_mm: MultiMesh, clips: Array) -> void:
	var t_ := crowd_time
	for item in originals:
		var o: Dictionary = item[0]
		_pose_original(o, item[1], _clip_time(item[1], t_), -1.0)
	for k in clips.size():
		if k % 2 == 1:
			_set_instance(front_mm, k, _xf(Vector3(-3.0 + float(k) * 1.2, 0, 2.0), .3, .6), clips[k], _clip_time(clips[k], t_), -1.0)
		else:
			front_mm.set_instance_transform(k, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0, -50, 0)))

func _clip_time(clip: String, t_: float) -> float:
	var c: Dictionary = baked.table[clip]
	return fposmod(t_, c.duration) if c.loop else minf(t_, c.duration)

func _update_crowd(t_: float) -> void:
	for i in crowd_state.size():
		var s: Dictionary = crowd_state[i]
		var c: Dictionary = baked.table[s.clip]
		var time_: float = (t_ + s.phase * c.duration) if c.loop else minf(t_ * .5 + s.phase * .0, c.duration)
		_set_instance(crowd_mm, i, _xf(s.pos, s.yaw, s.scale), s.clip, time_, -1.0, s.color)

func _process(delta: float) -> void:
	crowd_time += delta
	if crowd_active:
		_update_crowd(crowd_time)
