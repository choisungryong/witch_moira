extends RefCounted
## D24 7 Judgment Bolt (arc): a held silence under dark cloud, then up to 40 bolts come down at irregular intervals all over the screen,
## each with side branches and forks between bodies; the last tick the whole sky flashes. Reads descent_strike {bolt, finale}.
## Layers:
##   sky       screen shader: thunder cloud in the top 42 %, lit from inside by every bolt (value `sky_flash`, smoothed: it never strobes)
##   bolt      one pooled MeshInstance3D per live bolt (descent_bolt.gdshader, additive): a thick jagged trunk from above the screen's top
##             edge to the spot, 2-4 thin side branches, the forks between bodies (event `forks` = [from, to] world points). Built once
##             when struck; only a shader value changes afterwards. Cap 8 live (5 on the low spec; A11 5.3: the oldest gives its place)
##   foot      one MultiMesh of floor decals (descent_blast layer 0 kind 1): a star flash and a scorch for 1 s
##   sparks    6 additive GPU emitters x 40 taken in turn (35 % on the low spec)
##   light     one light per bolt from the host's pool of 3 (none on the low spec); a burst (several on one tick) kicks the camera
##   finale    the sky flashes white for ~0.12 s (flash_scale / reduced_motion applied by the host), kick 0.8, one wide light
## Without a `k` (a core older than D24) every position of the event is a bolt of its own and there are no forks.

const BOLT_SHADER := preload("res://chapter1/view/fx/descent_bolt.gdshader")
const BLAST_SHADER := preload("res://chapter1/view/fx/descent_blast.gdshader")

const MAX_BOLTS := 8
const MAX_BOLTS_LOW := 5
const POOL_FEET := 64
## A11 5.3: a bolt lives 0.26 s (was 0.42); at most 8 are drawn at once (5 on the low spec); the glow of a bolt is a violet-blue at 0.40, not 0.24
const BOLT_LIFE := 0.26
const GLOW_A := 0.40
const SKY_FLASH_BOLT := 0.24
const SKY_FLASH_BURST := 0.44
const WHITE_PEAK := 0.20   # spec 0.35; lowered so the finale is not a 4th swing in a second (measured, see report)
const FINALE_SKY := 0.35   # was 1.0 (A11 5.3 extra, measured: the finale was a 0.17 jump of the play area's mean luma)
const FOOT_LIFE := 1.0
const TRUNK_HEIGHT := 34.0
const SPARK_EMITTERS := 6
const SPARKS_EACH := 40

var host: RefCounted
var _nodes: Array[MeshInstance3D] = []
var _mats: Array[ShaderMaterial] = []
var _ages: Array[float] = []
var _flicker: Array[float] = []
var _flat: MultiMeshInstance3D
var _feet: Array[Dictionary] = []
var _sparks: Array[GPUParticles3D] = []
var _next_spark := 0
var _sky_flash := 0.0
var _white := 0.0
var _gest := 0.0
var _scrim := 0.0
var _bolt_count := 0
var _particles := 0

func build(host_: RefCounted) -> void:
	host = host_
	var holder: Node3D = host.holder
	var plane := PlaneMesh.new(); plane.size = Vector2(2, 2)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = plane
	mm.instance_count = POOL_FEET
	mm.visible_instance_count = 0
	_flat = MultiMeshInstance3D.new(); _flat.name = "DescentScorch"
	_flat.multimesh = mm
	var flat_mat := ShaderMaterial.new(); flat_mat.shader = BLAST_SHADER
	flat_mat.set_shader_parameter("layer", 0)
	flat_mat.render_priority = -3
	_flat.material_override = flat_mat
	_flat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flat.extra_cull_margin = 80.0
	holder.add_child(_flat)
	var aabb := AABB(Vector3(-60, -2, -60), Vector3(120, 30, 120))
	for i in SPARK_EMITTERS:
		var sp := GPUParticles3D.new(); sp.name = "DescentArcSparks%d" % i
		sp.amount = host.count(SPARKS_EACH); sp.lifetime = 0.38
		sp.one_shot = true; sp.explosiveness = 1.0; sp.emitting = false; sp.local_coords = false
		sp.visibility_aabb = aabb
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 0.35, 0); pm.spread = 100.0
		pm.initial_velocity_min = 3.0; pm.initial_velocity_max = 10.0
		pm.gravity = Vector3(0, -8, 0)
		pm.scale_min = 0.3; pm.scale_max = 0.9
		pm.color_ramp = host.ramp([[0.0, Color(1, 1, 1, 1)], [0.4, Color(0.72, 0.8, 1.0, 0.85)], [1.0, Color(0.42, 0.5, 1.0, 0.0)]])
		sp.process_material = pm
		sp.draw_pass_1 = host.particle_quad(true, Vector2(0.3, 0.3))
		holder.add_child(sp)
		_sparks.append(sp)
		_particles += sp.amount

func particle_total() -> int:
	return _particles

func freeze_value() -> float: return 0.0
func shatter_value() -> float: return 0.0
func scrim_value() -> float: return _scrim

func live_bolts() -> int:
	return _bolt_count

func _cap() -> int:
	return MAX_BOLTS_LOW if host.low else MAX_BOLTS

func begin(_event: Dictionary) -> void:
	for i in _ages.size():
		_ages[i] = -1.0
		_nodes[i].visible = false
	_feet.clear()
	_sky_flash = 0.0
	_white = 0.0
	_gest = 0.0
	_scrim = 0.0
	_bolt_count = 0

func book(_event: Dictionary) -> void:
	pass

func strike(event: Dictionary) -> void:
	match String(event.get("phase", "")):
		"bolt":
			if event.has("k"):
				_spawn(int(event.k), event.pos as Vector2, event.get("forks", []), bool(event.get("burst", false)))
			else:
				var positions: Array = event.get("positions", [])
				var n := 0
				for pos in positions:
					if n >= 12: break
					_spawn(int(host.stats.bolts) + n, pos as Vector2, [], positions.size() > 2)
					n += 1
		"finale":
			_white = WHITE_PEAK
			_sky_flash = FINALE_SKY
			host.kick(0.8)
			host.pool_light(Vector3(host.sw.center.x, 6.0, host.sw.center.y), Color(0.78, 0.85, 1.0), 3.0, 26.0, 0.3)   # 8 -> 4 (A11 5.3 extra, measured)

func _slot() -> int:
	for i in _ages.size():
		if _ages[i] < 0.0: return i
	if _nodes.size() >= _cap():
		# the pool is full: the oldest bolt gives its place to the new one (never more than the cap on screen)
		var oldest := -1
		var oldest_age := -1.0
		for i in _ages.size():
			if _ages[i] > oldest_age:
				oldest_age = _ages[i]
				oldest = i
		if oldest >= 0: host.stats.bolts_recycled = int(host.stats.get("bolts_recycled", 0)) + 1
		return oldest
	var node := MeshInstance3D.new(); node.name = "DescentBolt%d" % _nodes.size()
	node.mesh = ArrayMesh.new()
	var mat := ShaderMaterial.new(); mat.shader = BOLT_SHADER
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 80.0
	node.visible = false
	host.holder.add_child(node)
	_nodes.append(node); _mats.append(mat); _ages.append(-1.0); _flicker.append(0.0)
	return _nodes.size() - 1

func _spawn(k: int, pos: Vector2, forks: Array, burst: bool) -> void:
	var cam: Camera3D = host.camera()
	if cam == null: return
	var slot := _slot()
	if slot < 0:
		host.stats.bolts_dropped += 1
		return
	host.stats.bolts += 1
	var right: Vector3 = cam.global_basis.x
	var up: Vector3 = cam.global_basis.y
	var seed_ := float(k) * 13.7 + 3.1
	var foot := Vector3(pos.x, 0.06, pos.y)
	var side := Vector3(right.x, 0.0, right.z).normalized()
	var top: Vector3 = foot + side * (host.hash1(seed_) - 0.5) * 9.0 + Vector3(0, TRUNK_HEIGHT, 0)
	var scale := 1.25 if burst else 1.0
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	# the trunk
	var trunk := _jagged(top, foot, 14, 1.0, seed_, right, up, false)
	_ribbon(verts, colors, indices, trunk, 0.28 * scale, Color(host.tint.r, host.tint.g, host.tint.b, GLOW_A), right, up, true)
	_ribbon(verts, colors, indices, trunk, 0.07 * scale, Color(1, 1, 1, 0.95), right, up, true)
	# 2-4 thin side branches off the trunk, leaning out and down
	var branches := 2 + int(host.hash1(seed_ + 5.0) * 3.0)
	for b in branches:
		var f: float = 0.25 + 0.6 * host.hash1(seed_ + float(b) * 7.3)
		var start: Vector3 = trunk[int(f * float(trunk.size() - 1))]
		var sign_ := 1.0 if host.hash1(seed_ + float(b) * 3.1) > 0.5 else -1.0
		var reach: float = 3.0 + 4.0 * host.hash1(seed_ + float(b) * 11.9)
		var tip: Vector3 = start + side * sign_ * reach + Vector3(0, -2.0 - 3.0 * host.hash1(seed_ + float(b) * 5.5), 0)
		var path := _jagged(start, tip, 6, 0.5, seed_ + float(b) * 17.0, right, up, false)
		_ribbon(verts, colors, indices, path, 0.16, Color(host.tint.r, host.tint.g, host.tint.b, GLOW_A * 0.85), right, up, false)
		_ribbon(verts, colors, indices, path, 0.04, Color(1, 1, 1, 0.8), right, up, false)
	# forks between bodies (world points)
	for fork in forks:
		if not (fork is Array) or fork.size() < 2: continue
		var a: Vector2 = fork[0]
		var c: Vector2 = fork[1]
		var path2 := _jagged(Vector3(a.x, 0.9, a.y), Vector3(c.x, 0.9, c.y), 9, 0.4, seed_ + a.x + c.y, right, up, true)
		_ribbon(verts, colors, indices, path2, 0.14, Color(host.tint.r, host.tint.g, host.tint.b, GLOW_A), right, up, false)
		_ribbon(verts, colors, indices, path2, 0.04, Color(1, 1, 1, 0.85), right, up, false)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := _nodes[slot].mesh as ArrayMesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_nodes[slot].visible = true
	_ages[slot] = 0.0
	_flicker[slot] = host.hash1(seed_ + 1.0)
	_bolt_count = mini(_bolt_count + 1, _cap())
	host.stats.peak_bolts = maxi(int(host.stats.peak_bolts), _bolt_count)
	# the foot: a decal, a light, sparks, the cloud lit up
	if _feet.size() >= POOL_FEET: _feet.pop_front()
	_feet.append({"pos": pos, "seed": float(k % 31) / 31.0, "age": 0.0})
	host.pool_light(Vector3(pos.x, 2.0, pos.y), Color(0.72, 0.8, 1.0), 4.0 if burst else 3.8, 9.0, 0.12)   # A11 5.3 (extra, measured): 8 / 6 -> 5 / 3.8, the floor lit by a bolt was most of the luma swing
	var sp := _sparks[_next_spark % _sparks.size()]
	_next_spark += 1
	sp.global_position = Vector3(pos.x, 0.3, pos.y)
	sp.restart()
	sp.emitting = true
	_sky_flash = minf(1.0, maxf(_sky_flash, SKY_FLASH_BURST if burst else SKY_FLASH_BOLT))
	if burst:
		_gest = 1.0
		host.kick_merged(0.4, float(host.sw.t))
	else:
		host.kick_merged(0.1, float(host.sw.t))

## A jagged polyline from `from` to `to` (screen-space jitter so the zig-zag reads from the camera).
func _jagged(from: Vector3, to: Vector3, segments: int, amp_scale: float, seed_: float, right: Vector3, up: Vector3, link: bool) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var dir := to - from
	var t_screen := Vector2(dir.dot(right), dir.dot(up)).normalized()
	var perp := (right * -t_screen.y + up * t_screen.x).normalized()
	var amp := 0.9 * amp_scale if not link else 0.38
	for i in segments + 1:
		var f := float(i) / float(segments)
		var base := from.lerp(to, f)
		var env := sin(f * PI) if link else (1.0 - f * 0.55)
		var jitter: float = (host.hash1(seed_ + float(i) * 3.7) - 0.5) * 2.0 * amp * env
		pts.append(base + perp * jitter)
	return pts

func _ribbon(verts: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, pts: PackedVector3Array, width: float, color: Color, right: Vector3, up: Vector3, taper: bool) -> void:
	var base := verts.size()
	var n := pts.size()
	for i in n:
		var tangent := pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]
		var ts := Vector2(tangent.dot(right), tangent.dot(up)).normalized()
		var pp := (right * -ts.y + up * ts.x).normalized()
		var f := float(i) / float(maxi(1, n - 1))
		var w := width * (lerpf(0.55, 1.0, f) if taper else (1.0 - f * 0.7))
		verts.append(pts[i] + pp * w)
		verts.append(pts[i] - pp * w)
		colors.append(color)
		colors.append(color)
	for i in n - 1:
		var o := base + i * 2
		indices.append(o); indices.append(o + 1); indices.append(o + 2)
		indices.append(o + 1); indices.append(o + 3); indices.append(o + 2)

func update(t: float, dt: float) -> void:
	var dur: float = host.sw.dur
	# silence: the sky darkens before the first bolt, and the screen dims a little (never past 0.18)
	host.scr.sky = host.ramp_t(t, 0.0, 0.25) * (1.0 - host.ramp_t(t, dur + 0.2, dur + 1.0))
	_scrim = 0.18 * host.ramp_t(t, 0.0, 0.15) * (1.0 - host.ramp_t(t, dur - 0.1, dur + 0.8))
	_sky_flash = maxf(0.0, _sky_flash - host.wall_dt * 4.0)
	_white = maxf(0.0, _white - host.wall_dt * (WHITE_PEAK / 0.12))
	_gest = maxf(0.0, _gest - dt * 3.0)
	host.scr.sky_flash = _sky_flash
	host.scr.whiteout = _white
	host.scr.demon_pose = _gest
	# bolts: fade and flicker
	var live := 0
	for i in _ages.size():
		if _ages[i] < 0.0: continue
		_ages[i] += dt
		var age := _ages[i] / BOLT_LIFE
		if age >= 1.0:
			_ages[i] = -1.0
			_nodes[i].visible = false
			continue
		live += 1
		var flick := 1.0 if int(_ages[i] * 60.0 + _flicker[i] * 4.0) % 2 == 0 else 0.72
		_mats[i].set_shader_parameter("fade", (1.0 - pow(age, 1.6)) * flick)
	_bolt_count = live
	# the feet
	var mm := _flat.multimesh
	var n := 0
	var kept: Array[Dictionary] = []
	for foot in _feet:
		foot.age = float(foot.age) + dt
		if float(foot.age) >= FOOT_LIFE: continue
		kept.append(foot)
		var at: Vector2 = foot.pos
		mm.set_instance_transform(n, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 2.3), Vector3(at.x, 0.05, at.y)))
		mm.set_instance_custom_data(n, Color(float(foot.age), foot.seed, 1.0, FOOT_LIFE))
		n += 1
	_feet = kept
	mm.visible_instance_count = n

## One invisible frame of every material (tiny, fully transparent), so the first real sweep has nothing left to compile.
func warm(on: bool) -> void:
	var at: Vector2 = host.hero
	if on:
		var slot := _slot()
		if slot >= 0:
			var verts := PackedVector3Array([Vector3(at.x, 0.5, at.y), Vector3(at.x + 0.001, 0.5, at.y), Vector3(at.x, 0.501, at.y)])
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 0)])
			arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
			var mesh := _nodes[slot].mesh as ArrayMesh
			mesh.clear_surfaces()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			_nodes[slot].visible = true
			_mats[slot].set_shader_parameter("fade", 0.0)
		var mm := _flat.multimesh
		mm.set_instance_transform(0, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.001), Vector3(at.x, 0.05, at.y)))
		mm.set_instance_custom_data(0, Color(0, 0, 1, 1))
		mm.visible_instance_count = 1
		var sp: GPUParticles3D = _sparks[0]
		sp.global_position = Vector3(at.x, 0.3, at.y)
		sp.amount_ratio = 0.02
		sp.restart()
		sp.emitting = true
	else:
		hide_all()
		for e in _sparks: e.amount_ratio = 1.0

func set_hold(on: bool) -> void:
	var speed := 0.0 if on else 1.0
	for e in _sparks: e.speed_scale = speed

func hide_all() -> void:
	for node in _nodes: node.visible = false
	if is_instance_valid(_flat): _flat.multimesh.visible_instance_count = 0

func finish() -> void:
	hide_all()
	for i in _ages.size(): _ages[i] = -1.0
	_feet.clear()
	_bolt_count = 0
	_scrim = 0.0

func reset() -> void:
	_nodes.clear(); _mats.clear(); _ages.clear(); _flicker.clear(); _feet.clear()
