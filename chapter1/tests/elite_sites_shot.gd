extends SceneTree
## Look study for guarded elites and the shrine/chest they guard (docs/reviews/ELITE-AND-GUARDED-SITES-LOOK-20261120.ko.md).
## NOT product code and NOT a core feature: the core has no elite grade or guarded site yet. This script runs the real game
## scene (the real camera, light, ground, crowd of a pilot run), freezes the core, and stands made-up nodes next to the crowd.
## Everything made here is built from the existing skeleton model, the existing prop atlas and code shapes/light.
##
##   python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/elite_sites_shot.gd -- \
##       --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --mode=crowd --shots=_local/art/elite-sites/shots
##
## --mode=crowd   one elite (recommended look, guard state) at a locked shrine, a locked chest, a crowd around (tick --tick=, default 3000)
## --mode=bare    the same moment without anything added (reference)
## --mode=lineup  every variant and state side by side on the early, empty field (hero hidden)
## --mode=alert / --mode=charge   the crowd shot with the elite in its second / third state
## One window per process. Captures go under _local/ only.
const OUTLAW := preload("res://chapter1/art/skeleton_outlaw/v02/skeleton_outlaw_merged.glb")
const MARK := Color("4fe08a")      ## guard mark: green; nothing else on screen is green (threat crimson, element orange/cyan/periwinkle, grades blue/yellow/orange/gold, rings gold)
const MARK2 := Color("c35ad8")     ## alternative mark (magenta-violet)
const GRADE_MAGIC := Color("91bbd4")
const GRADE_RARE := Color("e0c47e")
const RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 color : source_color = vec4(1.0);
uniform float r_in = 0.9;
uniform float r_out = 1.0;
uniform float soft = 0.02;
uniform float dashes = 0.0;
uniform float fill = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float a = smoothstep(r_in - soft, r_in, d) * (1.0 - smoothstep(r_out, r_out + soft, d));
	if (dashes > 0.0) { float m = fract(atan(p.y, p.x) / 6.28318 * dashes); a *= step(m, 0.55); }
	a += fill * (1.0 - smoothstep(r_out, r_out + soft, d));
	ALBEDO = color.rgb;
	ALPHA = clamp(a, 0.0, 1.0) * color.a;
}
"""
const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 color : source_color = vec4(1.0);
uniform float height = 4.0;
uniform float power = 1.4;
varying float ly;
void vertex() { ly = VERTEX.y; }
void fragment() {
	float t = clamp(ly / height + 0.5, 0.0, 1.0);
	float f = abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = color.rgb;
	ALPHA = pow(1.0 - t, power) * f * color.a;
}
"""
var view: Node
var mode := "crowd"
var shots_dir := ""
var target_tick := 3000
var primary := "chapter1.skill.frost"
var variant_arg := 0
var leash_on := true
var tag := ""
var mark_arg := "green"
var frame := 0
var stage := 0
var wait_until := 0
var holder: Node3D
var follows: Array = []        ## [node, skeleton, bone index, offset(world), yaw follow]
var started_msec := 0
var ring_shader: Shader
var beam_shader: Shader

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--shots="): shots_dir = arg.trim_prefix("--shots=")
		elif arg.begins_with("--tick="): target_tick = int(arg.trim_prefix("--tick="))
		elif arg.begins_with("--primary="): primary = arg.trim_prefix("--primary=")
		elif arg.begins_with("--variant="): variant_arg = int(arg.trim_prefix("--variant="))
		elif arg.begins_with("--leash="): leash_on = arg.trim_prefix("--leash=") == "on"
		elif arg.begins_with("--mark="): mark_arg = arg.trim_prefix("--mark=")
		elif arg.begins_with("--tag="): tag = arg.trim_prefix("--tag=")
	if shots_dir.is_empty() or not shots_dir.begins_with("_local/"):
		push_error("elite_sites_shot: --shots=_local/... is required")
		quit(2)
		return
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.godot/imported")):
		push_error("elite_sites_shot: project not imported (python tools/dev/run_dev.py --import-only)")
		quit(3)
		return
	started_msec = Time.get_ticks_msec()
	ring_shader = Shader.new(); ring_shader.code = RING_SHADER
	beam_shader = Shader.new(); beam_shader.code = BEAM_SHADER
	var scene: PackedScene = load("res://chapter1/ChapterOne.tscn")
	view = scene.instantiate()
	root.add_child(view)
	if mode == "lineup": target_tick = 150

func _process(_delta: float) -> bool:
	frame += 1
	if (Time.get_ticks_msec() - started_msec) > 240000:
		push_error("elite_sites_shot: wall limit")
		quit(4)
		return true
	var run: RefCounted = view.run
	match stage:
		0:
			if frame == 11:
				view.start_run(primary)
				stage = 1
		1:
			if run.mode == "playing" and run.tick >= target_tick and not run.hero.is_empty():
				view.set_physics_process(false)   # freeze the core; the view keeps drawing
				_stage_scene(run)
				wait_until = frame + 14
				stage = 2
		2:
			_update_follows()
			if frame >= wait_until:
				_capture()
				stage = 3
				quit(0)
	if stage == 2: _update_follows()
	return false

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(shots_dir)
	var image := root.get_viewport().get_texture().get_image()
	var path := shots_dir.path_join("%s%s-%dx%d.png" % [mode, tag, image.get_width(), image.get_height()])
	image.save_png(path)
	print("ELITE_SITES_SHOT ", JSON.stringify({"mode": mode, "path": path, "tick": view.run.tick, "enemies": view.run.enemies.size(), "size": [image.get_width(), image.get_height()]}))

# ------------------------------------------------------------------------------------------------ staging

func _stage_scene(run: RefCounted) -> void:
	holder = Node3D.new(); holder.name = "EliteSitesStudy"
	view.add_child(holder)
	var cam: Camera3D = view.world.camera
	var hero_at := Vector3(run.hero.position.x, 0, run.hero.position.y)
	var right := Vector3(cam.global_basis.x.x, 0, cam.global_basis.x.z).normalized()
	var fwd := Vector3(-cam.global_basis.z.x, 0, -cam.global_basis.z.z).normalized()
	print("ELITE_SITES_STAGE ", JSON.stringify({"mode": mode, "tick": run.tick, "enemies": run.enemies.size(), "hero": [hero_at.x, hero_at.z]}))
	if mode == "bare": return
	if mode.begins_with("lineup"):
		view.actors.hero.visible = false
		_stage_lineup(hero_at, right, fwd)
		return
	# crowd shot: shrine up-right of the hero, its elite three metres from the shrine toward the hero, a chest down-left
	var shrine_at := hero_at + right * 9.0 + fwd * 5.0
	var elite_at := shrine_at - right * 2.6 - fwd * 1.8
	var chest_at := hero_at - right * 10.0 - fwd * 3.0
	var state: String = {"crowd": "guard", "alert": "alert", "charge": "charge"}.get(mode, "guard")
	if leash_on: _leash(shrine_at, 6.0, state)
	_shrine(shrine_at, 2, "locked", MARK, hero_at)
	_chest(chest_at, 0, "locked", GRADE_MAGIC)
	_elite(elite_at, variant_arg, state, MARK2 if mark_arg == "magenta" else MARK, hero_at, true)

func _stage_lineup(hero_at: Vector3, right: Vector3, fwd: Vector3) -> void:
	var colors := [MARK, MARK2, Color("f2ebd8")]
	var states := ["guard", "alert", "charge"]
	var site_states := ["locked", "open", "used"]
	var shrine_colors := [Color("f0c05a"), Color("b58cff"), Color("7de0c8")]
	for v in 3:
		for s in 3:
			var at := hero_at + right * ((v * 3 + s - 4) * 4.4) + fwd * 1.0
			if mode == "lineup-elite":
				_elite(at, v, states[s], colors[v], at - fwd * 3.0, true)
			elif mode == "lineup-shrine":
				_shrine(at, v, site_states[s], shrine_colors[v], hero_at)
			else:
				_chest(at, 0 if v == 0 else 1, site_states[s], GRADE_MAGIC if v != 2 else GRADE_RARE)

# ------------------------------------------------------------------------------------------------ pieces

func _mat(color: Color, emission := 0.0, rough := 0.92, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color; m.roughness = rough; m.metallic = metal
	if emission > 0.0:
		m.emission_enabled = true; m.emission = color; m.emission_energy_multiplier = emission
	return m

func _add(parent: Node, mesh: Mesh, material: Material, at: Vector3, rot := Vector3.ZERO, scale_ := Vector3.ONE) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh; node.material_override = material
	node.position = at; node.rotation = rot; node.scale = scale_
	parent.add_child(node)
	return node

func _ring_flat(parent: Node, at: Vector3, radius: float, r_in: float, color: Color, alpha: float, dashes := 0.0, fill := 0.0, width_m := 0.10) -> MeshInstance3D:
	var plane := PlaneMesh.new(); plane.size = Vector2(radius * 2.0, radius * 2.0)
	var m := ShaderMaterial.new(); m.shader = ring_shader
	m.set_shader_parameter("color", Color(color.r, color.g, color.b, alpha))
	m.set_shader_parameter("r_in", r_in); m.set_shader_parameter("r_out", minf(r_in + width_m / radius, 0.995)); m.set_shader_parameter("dashes", dashes); m.set_shader_parameter("fill", fill)
	var node := _add(parent, plane, m, at + Vector3.UP * 0.04)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

func _beam(parent: Node, at: Vector3, height: float, radius: float, color: Color, alpha: float) -> MeshInstance3D:
	var cyl := CylinderMesh.new(); cyl.top_radius = radius; cyl.bottom_radius = radius * 1.25; cyl.height = height
	cyl.cap_top = false; cyl.cap_bottom = false; cyl.radial_segments = 14; cyl.rings = 1
	var m := ShaderMaterial.new(); m.shader = beam_shader
	m.set_shader_parameter("color", Color(color.r, color.g, color.b, alpha)); m.set_shader_parameter("height", height)
	var node := _add(parent, cyl, m, at + Vector3.UP * height * 0.5)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

func _light(parent: Node, at: Vector3, color: Color, energy: float, range_: float) -> OmniLight3D:
	var l := OmniLight3D.new(); l.position = at; l.light_color = color; l.light_energy = energy; l.omni_range = range_; l.shadow_enabled = false
	parent.add_child(l)
	return l

func _leash(center: Vector3, radius: float, state: String) -> void:
	# the 6 m leash around the guarded spot: dashed and faint while the elite stands guard, solid once it fights
	var alpha: float = {"guard": 0.10, "alert": 0.18, "charge": 0.26}.get(state, 0.2)
	_ring_flat(holder, center, radius, 0.985 - 0.02, MARK, alpha, 0.0 if state != "guard" else 36.0)

func _bone_index(rig: Skeleton3D, bone: String) -> int:
	return rig.find_bone(bone)

func _follow(node: Node3D, rig: Skeleton3D, bone: String, offset: Vector3) -> void:
	follows.append([node, rig, _bone_index(rig, bone), offset])

func _update_follows() -> void:
	for f in follows:
		var node: Node3D = f[0]; var rig: Skeleton3D = f[1]
		if not is_instance_valid(node) or not is_instance_valid(rig) or f[2] < 0: continue
		var p: Vector3 = rig.global_transform * rig.get_bone_global_pose(f[2]).origin
		node.global_position = p + f[3]

func _elite(at: Vector3, variant_in: int, state: String, mark: Color, face_to: Vector3, with_ring: bool) -> void:
	var variant := 0 if variant_in == 3 else variant_in   # 3 = look 1 plus a thin beam while it has not charged yet
	var actor := Node3D.new(); holder.add_child(actor)
	actor.position = Vector3(at.x, 0, at.z)
	var dir := Vector3(face_to.x - at.x, 0, face_to.z - at.z)
	var yaw := atan2(dir.x, dir.z) if state != "guard" else atan2(dir.x, dir.z) + 0.9   # on guard it looks out, not at the hero
	actor.rotation.y = yaw
	var size_mul: float = [1.75, 1.45, 1.6][variant]
	var model: Node3D = OUTLAW.instantiate(); actor.add_child(model)
	model.scale = Vector3.ONE * 0.62 * size_mul
	var rig: Skeleton3D = model.find_child("Skeleton3D", true, false)
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var tint: Color = [Color(.30, .28, .27), Color(.50, .46, .40), Color(.42, .39, .35)][variant]
	_tint_model(model, tint, mark)
	var clip: String = {"guard": "idle", "alert": "idle_alert", "charge": "attack_slam"}[state]
	var seek: float = {"guard": 0.7, "alert": 0.5, "charge": 0.42}[state]
	if not player.has_animation(clip): clip = "idle"
	player.play(clip, 0); player.seek(seek, true); player.advance(0)
		# marks
	if variant == 0:
		for side in [-1.0, 1.0]:
			var pad := _add(holder, SphereMesh.new(), _mat(Color(.17, .15, .14), 0.0, .5, .6), Vector3.ZERO, Vector3.ZERO, Vector3(.40, .24, .36) * size_mul)
			_follow(pad, rig, "ORG-shoulder_L" if side < 0 else "ORG-shoulder_R", Vector3(0, .02, 0))
			var cone := CylinderMesh.new(); cone.top_radius = 0.0; cone.bottom_radius = .09 * size_mul; cone.height = .52 * size_mul
			var spike := _add(holder, cone, _mat(mark, 0.9, .4), Vector3.ZERO, Vector3(0, 0, -side * 0.35))
			_follow(spike, rig, "ORG-shoulder_L" if side < 0 else "ORG-shoulder_R", Vector3(0, .34 * size_mul, 0))
		var crown := CylinderMesh.new(); crown.top_radius = 0.0; crown.bottom_radius = .08 * size_mul; crown.height = .46 * size_mul
		var c := _add(holder, crown, _mat(mark, 1.1, .4), Vector3.ZERO)
		_follow(c, rig, "ORG-head", Vector3(0, .44 * size_mul, 0))
		if with_ring: _ring_flat(actor, Vector3.ZERO, 1.5, 0.90, mark, 0.40)
	elif variant == 1:
		var halo := _ring_flat(holder, Vector3.ZERO, .75 * size_mul, 0.72, mark, 1.0)
		_follow(halo, rig, "ORG-head", Vector3(0, .62 * size_mul, 0))
		var halo2 := _ring_flat(holder, Vector3.ZERO, .75 * size_mul, 0.82, mark, 0.7)
		_follow(halo2, rig, "ORG-head", Vector3(0, .70 * size_mul, 0))
		if with_ring: _ring_flat(actor, Vector3.ZERO, 1.4, 0.90, mark, 0.30, 18.0)
	else:
		_beam(actor, Vector3.ZERO, 7.0, .20, mark, 0.55)
		if with_ring:
			_ring_flat(actor, Vector3.ZERO, 1.5, 0.90, mark, 0.40)
	if variant_in == 3 and state != "charge": _beam(actor, Vector3.ZERO, 7.0, .11, mark, 0.40)
	# state: alert and charge get a small light and a brighter ground ring
	var energy: float = {"guard": 0.25, "alert": 0.6, "charge": 0.9}[state]
	_light(actor, Vector3(0, 1.4, 0), mark, energy, 3.5)
	if state != "guard" and with_ring and variant != 1:
		_ring_flat(actor, Vector3.ZERO, 2.2, 0.94, mark, 0.55 if state == "charge" else 0.32)

func _tint_model(node: Node, tint: Color, mark: Color) -> void:
	if node is MeshInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for surface in node.mesh.get_surface_count():
			var material: StandardMaterial3D = node.get_active_material(surface).duplicate()
			material.albedo_color = tint
			material.rim_enabled = true; material.rim = .35; material.rim_tint = .5
			node.set_surface_override_material(surface, material)
	for child in node.get_children(): _tint_model(child, tint, mark)

func _prop_quad(at: Vector3, id_: String, height: float, tint: Color) -> void:
	var world = view.world
	if not world._prop_defs.has(id_): return
	var record: Dictionary = world._prop_defs[id_]
	var entry := {"id": id_, "at": at, "height": height, "tint": tint, "mirror": false}
	var entries: Array[Dictionary] = [entry]
	var node_count: int = world.root.get_child_count()
	world._bake_prop_surface__q03(entries, world._prop_textures[record._atlas], "Study_" + id_)
	if world.root.get_child_count() > node_count:
		var baked: Node = world.root.get_child(world.root.get_child_count() - 1)
		world.root.remove_child(baked); holder.add_child(baked)

func _shrine(at: Vector3, variant: int, state: String, color: Color, hero_at: Vector3) -> void:
	var node := Node3D.new(); node.position = at; holder.add_child(node)
	var lit := state == "open"
	var ember := state == "used"
	var dark := Color(.36, .36, .38)
	if variant == 0:
		# brazier altar (existing atlas prop, enlarged)
		_prop_quad(at, "brazier", 2.9, dark if state == "locked" else Color(.86, .8, .7))
		if state == "locked":
			for k in 2:
				_add(node, _torus(.62, .045), _mat(Color(.2, .2, .22), 0, .5, .8), Vector3(0, .55 + k * .55, 0), Vector3(0, 0, 0), Vector3(1, 1, 1))
			_ring_flat(node, Vector3.ZERO, 1.3, 0.90, Color(.5, .5, .55), 0.14)
		elif lit:
			_light(node, Vector3(0, 1.8, 0), color, 2.0, 5.0)
			_beam(node, Vector3(0, 1.6, 0), 3.2, .26, color, 0.5)
			_ring_flat(node, Vector3.ZERO, 1.7, 0.90, color, 0.55, 0.0, 0.06)
		else:
			_light(node, Vector3(0, 1.0, 0), color, 0.4, 3.0)
			_ring_flat(node, Vector3.ZERO, 1.2, 0.88, color, 0.18)
	elif variant == 1:
		# slab and floating ring
		_add(node, BoxMesh.new(), _mat(Color(.30, .31, .33), 0, .96), Vector3(0, .17, 0), Vector3.ZERO, Vector3(2.3, .34, 1.5))
		_add(node, BoxMesh.new(), _mat(Color(.24, .25, .27), 0, .96), Vector3(0, .42, 0), Vector3.ZERO, Vector3(1.7, .16, 1.0))
		if state == "locked":
			for k in 3:
				_add(node, BoxMesh.new(), _mat(Color(.12, .12, .13), 0, .5, .8), Vector3(-.6 + k * .6, .62, 0), Vector3(0, 0, 0), Vector3(.12, .24, 1.15))
			_add(node, _torus(.5, .05), _mat(Color(.2, .2, .22), 0, .5, .8), Vector3(0, .60, 0), Vector3.ZERO)
			_ring_flat(node, Vector3.ZERO, 1.3, 0.90, Color(.5, .5, .55), 0.14)
		elif lit:
			_add(node, _torus(.62, .06), _mat(color, 1.8, .4), Vector3(0, 1.55, 0), Vector3(PI / 2, 0, 0))
			_add(node, _torus(.40, .04), _mat(color, 1.6, .4), Vector3(0, 1.55, 0), Vector3(PI / 2, 0, 0))
			_light(node, Vector3(0, 1.6, 0), color, 2.0, 5.0)
			_beam(node, Vector3(0, .5, 0), 3.0, .2, color, 0.4)
			_ring_flat(node, Vector3.ZERO, 1.7, 0.90, color, 0.55, 0.0, 0.06)
		else:
			_add(node, _torus(.62, .06), _mat(color.darkened(.6), 0.3, .6), Vector3(0, .62, 0), Vector3(0, 0, 0))
			_light(node, Vector3(0, .8, 0), color, 0.4, 3.0)
			_ring_flat(node, Vector3.ZERO, 1.3, 0.88, color, 0.16)
	else:
		# broken pillar and a floating stone
		_prop_quad(at, "pillar_broken", 2.4, dark if state == "locked" else Color(.8, .78, .78))
		var gem := SphereMesh.new(); gem.radial_segments = 6; gem.rings = 3
		if state == "locked":
			_add(node, gem, _mat(Color(.16, .16, .18), 0, .4, .6), Vector3(0, 2.7, 0), Vector3.ZERO, Vector3(.28, .36, .28))
			for k in 3:
				_add(node, BoxMesh.new(), _mat(Color(.13, .13, .14), 0, .5, .8), Vector3(0, 2.7, 0), Vector3(0, k * PI / 3, 0), Vector3(.04, .85, .04))
			_ring_flat(node, Vector3.ZERO, 1.3, 0.90, Color(.5, .5, .55), 0.14)
		elif lit:
			_add(node, gem, _mat(color, 2.4, .3), Vector3(0, 2.7, 0), Vector3.ZERO, Vector3(.30, .40, .30))
			_light(node, Vector3(0, 2.4, 0), color, 2.0, 5.0)
			_beam(node, Vector3(0, 0, 0), 3.0, .16, color, 0.45)
			_ring_flat(node, Vector3.ZERO, 1.7, 0.90, color, 0.55, 0.0, 0.06)
		else:
			_ring_flat(node, Vector3.ZERO, 1.2, 0.88, color, 0.16)
			_add(node, gem, _mat(color.darkened(.5), 0.2, .5), Vector3(0, .25, 0.6), Vector3.ZERO, Vector3(.12, .15, .12))

func _torus(radius: float, tube: float) -> TorusMesh:
	var t := TorusMesh.new(); t.inner_radius = radius - tube; t.outer_radius = radius + tube; t.rings = 24; t.ring_segments = 8
	return t

func _chest(at: Vector3, variant: int, state: String, rim: Color) -> void:
	var node := Node3D.new(); node.position = at; holder.add_child(node)
	var body_color := Color(.23, .16, .11) if variant == 0 else Color(.27, .28, .30)
	var band_color := Color(.11, .11, .12)
	var open := state != "locked"
	_add(node, BoxMesh.new(), _mat(body_color, 0, .85), Vector3(0, .30, 0), Vector3.ZERO, Vector3(1.15, .6, .72))
	for sx in [-.38, .38]:
		_add(node, BoxMesh.new(), _mat(band_color, 0, .45, .8), Vector3(sx, .30, 0), Vector3.ZERO, Vector3(.10, .62, .76))
	var lid := Node3D.new(); lid.position = Vector3(0, .60, -.36); node.add_child(lid)
	lid.rotation.x = -1.15 if open else 0.0
	var lid_mesh: Mesh = BoxMesh.new()
	_add(lid, lid_mesh, _mat(body_color.lightened(.04), 0, .85), Vector3(0, .12, .36), Vector3.ZERO, Vector3(1.19, .24, .76))
	for sx in [-.38, .38]:
		_add(lid, BoxMesh.new(), _mat(band_color, 0, .45, .8), Vector3(sx, .12, .36), Vector3.ZERO, Vector3(.11, .26, .80))
	# rim: the lowest grade the chest can give, as an edge line on the lid and the body
	var rim_energy := 0.55 if state == "locked" else (1.0 if state == "open" else 0.0)
	if state != "used":
		_add(lid, BoxMesh.new(), _mat(rim, rim_energy, .4), Vector3(0, .245, .36), Vector3.ZERO, Vector3(1.21, .03, .78))
		_add(node, BoxMesh.new(), _mat(rim, rim_energy * .8, .4), Vector3(0, .015, 0), Vector3.ZERO, Vector3(1.19, .03, .76))
	if state == "locked":
		_add(node, _torus(.62, .035), _mat(Color(.2, .2, .22), 0, .5, .8), Vector3(0, .34, 0), Vector3(0, PI / 2, 0), Vector3(1, 1, 1.4))
		_add(node, BoxMesh.new(), _mat(Color(.62, .5, .3), 0, .4, .8), Vector3(0, .42, .38), Vector3.ZERO, Vector3(.2, .22, .08))
		_ring_flat(node, Vector3.ZERO, 1.3, 0.90, Color(.5, .5, .55), 0.14)
		_light(node, Vector3(0, .9, 0), rim, 0.25, 2.6)
	elif state == "open":
		_beam(node, Vector3(0, .5, 0), 3.6, .3, rim, 0.6)
		_light(node, Vector3(0, 1.0, 0), rim, 1.4, 4.5)
		_ring_flat(node, Vector3.ZERO, 1.7, 0.90, rim, 0.55, 0.0, 0.06)
		for k in 4:
			var spark := SphereMesh.new(); spark.radial_segments = 6; spark.rings = 3
			var a := TAU * k / 4.0 + .4
			_add(node, spark, _mat(Color(1, .97, .85), 1.0, .3), Vector3(cos(a) * .9, .08, sin(a) * .9 + .3), Vector3.ZERO, Vector3(.14, .10, .14))
	else:
		for k in 3:
			_add(node, _torus(.12, .03), _mat(Color(.2, .2, .22), 0, .5, .8), Vector3(-.9 + k * .22, .04, .85), Vector3(PI / 2, 0, k * .6))
		_ring_flat(node, Vector3.ZERO, 1.1, 0.88, rim.darkened(.3), 0.12)
