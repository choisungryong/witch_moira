extends RefCounted
## D24 5 Armageddon (ember): the sky tears red, shadows spread on the floor, big rock fragments come down one after another, the
## floor burns, and at the end the flame covers the screen from its edges. Reads descent_book / descent_strike {impact, firestorm}.
## Layers, in the order the player meets them (one hit: flash -> form -> debris -> trace -> reaction):
##   sky       screen shader: a cracked red-brown cloud ceiling in the top 42 % (value `sky`)
##   shadow    one MultiMesh of floor marks (meteor_mark.gdshader, the evolved Meteor's grammar): darkens for 30 ticks, its edge IS radius_m
##   rock      one MultiMesh of camera-facing quads (descent_rock.gdshader): basalt with glowing cracks and a 6-10 m flame tail, 60-70 degrees
##             from the upper left like the evolved Meteor but 2.3x its size (big 3.6 m across, small 2.2 m; the Meteor ball is 1.6 m)
##   impact    flat flash + open shock ring + soot crater (cooling lava cracks, 3 s) and a rising fire dome that turns to smoke (descent_blast)
##   debris    GPU particles: 6 additive spark emitters + 6 dark chunk emitters taken in turn, and an ambient ember rain
##   shake     0.6 for a big fragment, 0.3 for a small one, merged inside 0.1 s (host.kick_merged); one light per impact (pool of 3)
##   finale    the flame creeps in from the screen edges in 0.3 s and ebbs (screen value fire_cover / fire_alpha), kick, one wide light
## Budget: fragments <= 32 (14 in the shipped data), particles 6x85 + 6x30 + 80 = 770 (35 % on the low spec), lights through the host (3).

const ROCK_SHADER := preload("res://chapter1/view/fx/descent_rock.gdshader")
const MARK_SHADER := preload("res://chapter1/view/fx/meteor_mark.gdshader")
const BLAST_SHADER := preload("res://chapter1/view/fx/descent_blast.gdshader")

const MAX_FRAGS := 32
const SHADOW_TICKS := 30.0
const FALL_TICKS := 24.0
const START_DIST := 28.0
const ROCK_R_BIG := 2.0
const ROCK_R_SMALL := 1.2
const SCORCH_SECONDS := 3.0
const DOME_SECONDS := 0.8
const EMITTERS := 6
const SPARKS_EACH := 85
const CHUNKS_EACH := 30
const RAIN := 80
const FIRE := Color(1.0, 0.58, 0.22)

var host: RefCounted
var _rocks: MultiMeshInstance3D
var _marks: MultiMeshInstance3D
var _flat: MultiMeshInstance3D
var _dome: MultiMeshInstance3D
var _rock_mat: ShaderMaterial
var _sparks: Array[GPUParticles3D] = []
var _chunks: Array[GPUParticles3D] = []
var _rain: GPUParticles3D
var _frags: Array[Dictionary] = []
var _next_emit := 0
var _gest := 0.0
var _fire_t := -1.0
var _particles := 0

func build(host_: RefCounted) -> void:
	host = host_
	var holder: Node3D = host.holder
	_rock_mat = ShaderMaterial.new(); _rock_mat.shader = ROCK_SHADER
	_rock_mat.render_priority = 6
	var rock_quad := QuadMesh.new(); rock_quad.size = Vector2(16.0, 7.2)
	_rocks = _multimesh("DescentRocks", rock_quad, _rock_mat, false)
	var mark_mat := ShaderMaterial.new(); mark_mat.shader = MARK_SHADER
	var plane := PlaneMesh.new(); plane.size = Vector2(2, 2)
	_marks = _multimesh("DescentShadows", plane, mark_mat, false)
	var flat_mat := ShaderMaterial.new(); flat_mat.shader = BLAST_SHADER
	flat_mat.set_shader_parameter("layer", 0)
	flat_mat.render_priority = -3
	_flat = _multimesh("DescentCraters", plane, flat_mat, false)
	var dome_mat := ShaderMaterial.new(); dome_mat.shader = BLAST_SHADER
	dome_mat.set_shader_parameter("layer", 1)
	dome_mat.render_priority = 5
	var quad := QuadMesh.new(); quad.size = Vector2(2, 2)
	_dome = _multimesh("DescentDomes", quad, dome_mat, true)
	_build_particles(holder)

func _multimesh(node_name: String, mesh: Mesh, material: Material, _unused: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = MAX_FRAGS
	mm.visible_instance_count = 0
	var node := MultiMeshInstance3D.new(); node.name = node_name
	node.multimesh = mm
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 80.0
	host.holder.add_child(node)
	return node

func _build_particles(holder: Node3D) -> void:
	var aabb := AABB(Vector3(-60, -2, -60), Vector3(120, 30, 120))
	for i in EMITTERS:
		var sp := GPUParticles3D.new(); sp.name = "DescentSparks%d" % i
		sp.amount = host.count(SPARKS_EACH); sp.lifetime = 0.8
		sp.one_shot = true; sp.explosiveness = 1.0; sp.emitting = false; sp.local_coords = false
		sp.visibility_aabb = aabb
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 1, 0); pm.spread = 70.0
		pm.initial_velocity_min = 6.0; pm.initial_velocity_max = 15.0
		pm.gravity = Vector3(0, -14, 0)
		pm.scale_min = 0.35; pm.scale_max = 1.0
		pm.color_ramp = host.ramp([[0.0, Color(1.0, 0.92, 0.6, 1.0)], [0.35, Color(1.0, 0.5, 0.14, 0.85)], [0.8, Color(0.6, 0.18, 0.05, 0.25)], [1.0, Color(0.2, 0.06, 0.03, 0.0)]])
		sp.process_material = pm
		sp.draw_pass_1 = host.particle_quad(true, Vector2(0.28, 0.28))
		holder.add_child(sp)
		_sparks.append(sp)
		_particles += sp.amount
		var ch := GPUParticles3D.new(); ch.name = "DescentChunks%d" % i
		ch.amount = host.count(CHUNKS_EACH); ch.lifetime = 1.0
		ch.one_shot = true; ch.explosiveness = 1.0; ch.emitting = false; ch.local_coords = false
		ch.visibility_aabb = aabb
		ch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var cm := ParticleProcessMaterial.new()
		cm.direction = Vector3(0, 1, 0); cm.spread = 60.0
		cm.initial_velocity_min = 4.0; cm.initial_velocity_max = 11.0
		cm.gravity = Vector3(0, -18, 0)
		cm.scale_min = 0.7; cm.scale_max = 1.8
		cm.color_ramp = host.ramp([[0.0, Color(1.0, 0.62, 0.22, 1.0)], [0.25, Color(0.22, 0.13, 0.09, 1.0)], [0.7, Color(0.12, 0.09, 0.08, 0.8)], [1.0, Color(0.1, 0.08, 0.07, 0.0)]])
		ch.process_material = cm
		ch.draw_pass_1 = host.particle_quad(false, Vector2(0.3, 0.3))
		holder.add_child(ch)
		_chunks.append(ch)
		_particles += ch.amount
	# ambient embers falling through the whole screen
	_rain = GPUParticles3D.new(); _rain.name = "DescentEmberRain"
	_rain.amount = host.count(RAIN); _rain.lifetime = 2.6
	_rain.emitting = false; _rain.local_coords = false
	_rain.visibility_aabb = aabb
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rm := ParticleProcessMaterial.new()
	rm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	rm.emission_box_extents = Vector3(22.0, 0.5, 17.0)
	rm.direction = Vector3(0.2, -1, 0.1); rm.spread = 12.0
	rm.initial_velocity_min = 1.5; rm.initial_velocity_max = 4.5
	rm.gravity = Vector3(0, -1.0, 0)
	rm.scale_min = 0.25; rm.scale_max = 0.6
	rm.color_ramp = host.ramp([[0.0, Color(1.0, 0.7, 0.3, 0.0)], [0.15, Color(1.0, 0.6, 0.2, 0.9)], [0.8, Color(0.9, 0.35, 0.1, 0.6)], [1.0, Color(0.3, 0.1, 0.05, 0.0)]])
	_rain.process_material = rm
	_rain.draw_pass_1 = host.particle_quad(true, Vector2(0.2, 0.2))
	holder.add_child(_rain)
	_particles += _rain.amount

func particle_total() -> int:
	return _particles

func freeze_value() -> float: return 0.0
func shatter_value() -> float: return 0.0
func scrim_value() -> float: return 0.0

func begin(_event: Dictionary) -> void:
	_frags.clear()
	_next_emit = 0
	_gest = 0.0
	_fire_t = -1.0
	_rain.emitting = true

## descent_book: every fragment of the sweep, with its spot fixed in world coordinates (D24 5.2).
func book(event: Dictionary) -> void:
	var list: Array = event.get("fragments", [])
	for item in list:
		if _frags.size() >= MAX_FRAGS: break
		var k := int(item.k)
		_frags.append({"k": k, "pos": item.pos as Vector2, "land": int(item.land_step), "radius": float(item.radius_m), "big": bool(item.big),
			"seed": float(k % 23) / 23.0, "angle": 60.0 + float((k * 37) % 11), "landed": false, "age": 0.0, "gest": false})
	host.stats.rocks += _frags.size()

func strike(event: Dictionary) -> void:
	match String(event.get("phase", "")):
		"impact":
			var k := int(event.get("k", -1))
			for f in _frags:
				if int(f.k) == k and not bool(f.landed):
					_land(f, float(host.sw.t))
					break
		"firestorm":
			_fire_t = 0.0
			host.kick(0.7)
			host.pool_light(Vector3(host.sw.center.x, 3.0, host.sw.center.y), Color(1.0, 0.55, 0.2), 5.0, 24.0, 0.45)

func _land(f: Dictionary, t: float) -> void:
	f.landed = true
	f.age = 0.0
	host.stats.impacts += 1
	var big: bool = f.big
	var at: Vector2 = f.pos
	host.kick_merged(0.6 if big else 0.3, t)
	host.pool_light(Vector3(at.x, 2.0, at.y), FIRE, 7.0 if big else 4.0, 13.0 if big else 9.0, 0.25)
	var index := _next_emit % EMITTERS
	_next_emit += 1
	var ratio := 1.0 if big else 0.55
	for e in [_sparks[index], _chunks[index]]:
		var node: GPUParticles3D = e
		node.global_position = Vector3(at.x, 0.3, at.y)
		node.amount_ratio = ratio
		node.restart()
		node.emitting = true

func update(t: float, dt: float) -> void:
	var dur: float = host.sw.dur
	var s := t * 60.0
	var center: Vector2 = host.sw.center
	# the sky
	host.scr.sky = host.ramp_t(t, 0.0, 0.4) * (1.0 - host.ramp_t(t, dur + 0.3, dur + 1.4))
	_rain.global_position = Vector3(center.x, 13.0, center.y)
	# the demon's gesture: the hand comes down as each big fragment starts to fall
	for f in _frags:
		if bool(f.big) and not bool(f.gest) and s >= float(f.land) - SHADOW_TICKS:
			f.gest = true
			_gest = 1.0
	_gest = maxf(0.0, _gest - dt * 3.0)
	host.scr.demon_pose = _gest
	# the finale
	if _fire_t >= 0.0:
		_fire_t += dt
		host.scr.fire_cover = host.ease_out(host.ramp_t(_fire_t, 0.0, 0.3))
		host.scr.fire_alpha = 1.0 - host.ramp_t(_fire_t, 0.3, 0.8)
		if _fire_t > 1.0:
			_fire_t = -1.0
			host.scr.fire_alpha = 0.0
	var cam: Camera3D = host.camera()
	if cam == null: return
	var cam_x := cam.global_basis.x
	var cam_y := cam.global_basis.y
	_rock_mat.set_shader_parameter("hero_uv", host.hero_uv())
	_rock_mat.set_shader_parameter("aspect", host.screen_aspect())
	for m in [_flat.material_override, _dome.material_override]:
		m.set_shader_parameter("hero_uv", host.hero_uv())
		m.set_shader_parameter("aspect", host.screen_aspect())
	var rock_mm := _rocks.multimesh
	var mark_mm := _marks.multimesh
	var flat_mm := _flat.multimesh
	var dome_mm := _dome.multimesh
	var rn := 0
	var mn := 0
	var fn := 0
	var dn := 0
	for f in _frags:
		var at: Vector2 = f.pos
		var land := float(f.land)
		var radius: float = f.radius
		if not bool(f.landed):
			# a fragment whose impact event did not come lands by its own clock (3 ticks late) so the picture never hangs
			if s >= land + 3.0:
				_land(f, t)
			else:
				var shadow_t := clampf((s - (land - SHADOW_TICKS)) / SHADOW_TICKS, 0.0, 1.0)
				if s >= land - SHADOW_TICKS and mn < MAX_FRAGS:
					mark_mm.set_instance_transform(mn, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * radius * 1.3), Vector3(at.x, 0.04, at.y)))
					mark_mm.set_instance_custom_data(mn, Color(shadow_t, 0.0, f.seed, 0.38 if bool(f.big) else 0.55))
					mn += 1
				var fall := (s - (land - FALL_TICKS)) / FALL_TICKS
				if fall >= 0.0 and rn < MAX_FRAGS:
					var a := deg_to_rad(float(f.angle))
					var dir := Vector2(cos(a), -sin(a))
					var dist := START_DIST * (1.0 - pow(clampf(fall, 0.0, 1.0), 1.6))
					var head := Vector3(at.x, 0.6, at.y) - (cam_x * dir.x + cam_y * dir.y) * dist
					var r_vis := ROCK_R_BIG if bool(f.big) else ROCK_R_SMALL
					var sc := lerpf(0.8, 1.0, clampf(fall, 0.0, 1.0)) * r_vis / 2.0
					rock_mm.set_instance_transform(rn, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * sc), head))
					rock_mm.set_instance_custom_data(rn, Color(atan2(dir.y, dir.x), clampf(fall, 0.0, 1.0), f.seed, 0.0))
					rn += 1
		if bool(f.landed):
			f.age = float(f.age) + dt
			var age: float = f.age
			if age < SCORCH_SECONDS and fn < MAX_FRAGS:
				flat_mm.set_instance_transform(fn, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * radius / 0.8), Vector3(at.x, 0.05, at.y)))
				flat_mm.set_instance_custom_data(fn, Color(age, f.seed, 0.0, SCORCH_SECONDS))
				fn += 1
			if age < DOME_SECONDS and dn < MAX_FRAGS:
				var ds := radius * (0.85 if bool(f.big) else 0.8)
				dome_mm.set_instance_transform(dn, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * ds), Vector3(at.x, radius * (0.45 + 0.7 * age / DOME_SECONDS), at.y)))
				dome_mm.set_instance_custom_data(dn, Color(age, f.seed, 0.0, DOME_SECONDS))
				dn += 1
	rock_mm.visible_instance_count = rn
	mark_mm.visible_instance_count = mn
	flat_mm.visible_instance_count = fn
	dome_mm.visible_instance_count = dn

## One invisible frame of every material (tiny, fully transparent), so the first real sweep has nothing left to compile.
func warm(on: bool) -> void:
	var at: Vector2 = host.hero
	var cam: Camera3D = host.camera()
	if on and cam != null:
		var tiny := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.001), Vector3(at.x, 0.5, at.y))
		for node in [_rocks, _marks, _flat, _dome]:
			var mm: MultiMesh = node.multimesh
			mm.set_instance_transform(0, tiny)
			mm.set_instance_custom_data(0, Color(0, 0, 0, 0))
			mm.visible_instance_count = 1
		_rock_mat.set_shader_parameter("hero_uv", host.hero_uv())
		for e in [_sparks[0], _chunks[0]]:
			var node: GPUParticles3D = e
			node.global_position = Vector3(at.x, 0.3, at.y)
			node.amount_ratio = 0.02
			node.restart()
			node.emitting = true
		_rain.global_position = Vector3(at.x, 13.0, at.y)
		_rain.amount_ratio = 0.02
		_rain.emitting = true
	elif not on:
		hide_all()
		_rain.emitting = false
		_rain.amount_ratio = 1.0

func set_hold(on: bool) -> void:
	var speed := 0.0 if on else 1.0
	for e in _sparks: e.speed_scale = speed
	for e in _chunks: e.speed_scale = speed
	_rain.speed_scale = speed

func hide_all() -> void:
	for node in [_rocks, _marks, _flat, _dome]:
		if is_instance_valid(node): node.multimesh.visible_instance_count = 0

func finish() -> void:
	hide_all()
	if is_instance_valid(_rain): _rain.emitting = false
	_frags.clear()
	_fire_t = -1.0

func reset() -> void:
	_frags.clear()
