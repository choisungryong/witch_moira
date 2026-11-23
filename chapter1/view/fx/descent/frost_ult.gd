extends RefCounted
## D24 6 Absolute Zero (frost): an ice storm sweeps in from the upper right, everything on the screen freezes, eight wind-surges crack the
## ice, then the demon closes a fist and the whole screen breaks at once. Reads descent_strike {onset, freeze, pulse, break}.
## Layers:
##   storm     screen shader (value `storm`, `gust`): two layers of slanted streaks + a drifting snow veil + a cold edge. NOT a second full-screen layer.
##   wind      GPU particles of ice, 300, long streaks along the wind, following the hero (35 % on the low spec)
##   floor     the crystal floor (descent_ground.gdshader mode 1) clipped to the screen rectangle; grows at `onset`, breaks at `break`, thin frost stays 3 s
##   ice skin  one MultiMesh of up to 64 crystal shells over the frozen bodies (descent_ice.gdshader); a crack level per pulse, all go at the break
##   rim       the shader's frozen crystal rim (`freeze`), shattering cell by cell at the break
##   break     2 frames of white, a 0.08 s presenter hit-stop (host.hitstop: the core never stops), 300 shards from the frozen spots, kick 1.0, a light
## Budget: particles 300 + 300 = 600 (35 % on the low spec), lights through the host, MultiMesh 64.

const GROUND_SHADER := preload("res://chapter1/view/fx/descent_ground.gdshader")
const ICE_SHADER := preload("res://chapter1/view/fx/descent_ice.gdshader")

const MAX_ICE := 64
const STORM_AMOUNT := 300
const SHARD_AMOUNT := 300
const COLD := Color(0.62, 0.86, 1.0)
## A11 5.2: the break's white flash 1.0 -> 0.45 (held 2 frames, gone in 0.12 s)
const WHITE_PEAK := 0.45
## A11 5.2 (extra, measured): the floor was a pale wash (0.07 cap); it is now a dark blue floor (FLOOR_DARK) with cold veins, under the bodies
const GROUND_ALPHA := 0.8
const FLOOR_DARK := 0.88

var host: RefCounted
var _ground: MeshInstance3D
var _ground_mat: ShaderMaterial
var _ice: MultiMeshInstance3D
var _storm: GPUParticles3D
var _storm_mat: ParticleProcessMaterial
var _shards: GPUParticles3D
var _shard_mat: ParticleProcessMaterial
var _items: Array[Dictionary] = []
var _frozen := PackedVector2Array()
var _onset := -1.0
var _broke := false
var _bt := 0.0
var _cracks := 0.0
var _gust := 0.0
var _white := 0.0
var _white_frames := 0
var _freeze := 0.0
var _shatter := 0.0
var _wind := Vector2(-0.12, 0.99)
var _particles := 0

func build(host_: RefCounted) -> void:
	host = host_
	var holder: Node3D = host.holder
	_ground = MeshInstance3D.new(); _ground.name = "DescentFrostFloor"
	var plane := PlaneMesh.new(); plane.size = Vector2(44, 36)
	_ground.mesh = plane
	_ground_mat = ShaderMaterial.new(); _ground_mat.shader = GROUND_SHADER
	_ground_mat.render_priority = -5
	_ground_mat.set_shader_parameter("mode", 1)
	_ground_mat.set_shader_parameter("tint", host.tint)
	_ground_mat.set_shader_parameter("reach", 26.0)
	_ground_mat.set_shader_parameter("max_alpha", GROUND_ALPHA)
	_ground_mat.set_shader_parameter("floor_dark", FLOOR_DARK)
	_ground.material_override = _ground_mat
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ground.visible = false
	holder.add_child(_ground)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new(); quad.size = Vector2(1.4, 1.7)   # A11 5.2: the size of a body, so shells overlap less
	mm.mesh = quad
	mm.instance_count = MAX_ICE
	mm.visible_instance_count = 0
	_ice = MultiMeshInstance3D.new(); _ice.name = "DescentIce"
	_ice.multimesh = mm
	var ice_mat := ShaderMaterial.new(); ice_mat.shader = ICE_SHADER
	ice_mat.render_priority = 5
	_ice.material_override = ice_mat
	_ice.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ice.extra_cull_margin = 80.0
	holder.add_child(_ice)
	var aabb := AABB(Vector3(-70, -2, -70), Vector3(140, 30, 140))
	_storm_mat = ParticleProcessMaterial.new()
	_storm_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_storm_mat.emission_box_extents = Vector3(17.0, 5.0, 17.0)
	_storm_mat.direction = Vector3(-0.12, -0.35, 0.99).normalized()
	_storm_mat.spread = 5.0
	_storm_mat.initial_velocity_min = 30.0; _storm_mat.initial_velocity_max = 55.0
	_storm_mat.gravity = Vector3.ZERO
	_storm_mat.scale_min = 0.5; _storm_mat.scale_max = 2.6
	_storm_mat.color_ramp = host.ramp([[0.0, Color(0.9, 0.97, 1.0, 0.0)], [0.15, Color(0.8, 0.94, 1.0, 0.55)], [0.8, Color(0.65, 0.88, 1.0, 0.45)], [1.0, Color(0.6, 0.85, 1.0, 0.0)]])
	_storm = GPUParticles3D.new(); _storm.name = "DescentWind"
	_storm.amount = host.count(STORM_AMOUNT); _storm.lifetime = 1.1
	_storm.emitting = false; _storm.local_coords = false
	_storm.visibility_aabb = aabb
	_storm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_storm.process_material = _storm_mat
	_storm.draw_pass_1 = host.particle_quad(false, Vector2(0.2, 0.2))
	holder.add_child(_storm)
	_particles += _storm.amount
	_shard_mat = ParticleProcessMaterial.new()
	_shard_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	_shard_mat.emission_point_count = 1
	_shard_mat.direction = Vector3(0, 0.6, 0); _shard_mat.spread = 110.0
	_shard_mat.initial_velocity_min = 7.0; _shard_mat.initial_velocity_max = 20.0
	_shard_mat.gravity = Vector3(0, -16, 0)
	_shard_mat.scale_min = 0.6; _shard_mat.scale_max = 2.0
	_shard_mat.color_ramp = host.ramp([[0.0, Color(0.97, 1.0, 1.0, 0.95)], [0.5, Color(0.62, 0.9, 0.97, 0.7)], [1.0, Color(0.4, 0.75, 0.9, 0.0)]])
	_shards = GPUParticles3D.new(); _shards.name = "DescentShards"
	_shards.amount = host.count(SHARD_AMOUNT); _shards.lifetime = 0.95
	_shards.one_shot = true; _shards.explosiveness = 1.0; _shards.emitting = false; _shards.local_coords = false
	_shards.visibility_aabb = aabb
	_shards.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shards.process_material = _shard_mat
	_shards.draw_pass_1 = host.particle_quad(false, Vector2(0.3, 0.3))
	holder.add_child(_shards)
	_particles += _shards.amount

func particle_total() -> int:
	return _particles

func freeze_value() -> float: return _freeze
func shatter_value() -> float: return _shatter
func scrim_value() -> float: return 0.0

func begin(event: Dictionary) -> void:
	_items.clear()
	_frozen = PackedVector2Array()
	_onset = -1.0
	_broke = false
	_bt = 0.0
	_cracks = 0.0
	_gust = 0.0
	_white = 0.0
	_freeze = 0.0
	_shatter = 0.0
	var area: Dictionary = host.sw.area
	var rad := deg_to_rad(float(area.right_deg))
	var right := Vector2(cos(rad), sin(rad))
	var down := right.rotated(PI * 0.5)
	# the floor: aligned with the screen rectangle (local x = the screen's right, local z = its down)
	_ground.rotation = Vector3(0.0, -rad, 0.0)
	var hw := float(area.half_w_m) + 1.0
	var hh := float(area.half_h_m) + 1.0
	(_ground.mesh as PlaneMesh).size = Vector2(hw * 2.0 + 6.0, hh * 2.0 + 6.0)
	_ground.position = Vector3(host.sw.center.x, 0.045, host.sw.center.y)
	_ground_mat.set_shader_parameter("rect", Vector2(hw, hh))
	_ground_mat.set_shader_parameter("progress", 0.0)
	_ground_mat.set_shader_parameter("shatter", 0.0)
	_ground_mat.set_shader_parameter("fade", 1.0)
	_ground.visible = false
	# the wind runs from the upper right to the lower left of the screen
	_wind = (down - right).normalized()
	_storm_mat.direction = Vector3(_wind.x, -0.35, _wind.y).normalized()
	_storm.emitting = true

func book(_event: Dictionary) -> void:
	pass

func strike(event: Dictionary) -> void:
	var positions: Array = event.get("positions", [])
	match String(event.get("phase", "")):
		"onset":
			_onset = float(host.sw.t)
			_add_ice(positions)
			_gust = 1.0
			host.kick(0.2)
			host.pool_light(Vector3(host.sw.center.x, 3.0, host.sw.center.y), COLD, 3.0, 22.0, 0.3)
		"freeze":
			_add_ice(positions)
		"pulse":
			host.stats.pulses += 1
			var n := int(event.get("n", 1))
			_cracks = clampf(float(n) / 8.0, 0.0, 1.0)
			_gust = 1.0
			host.kick(0.16)
			host.pool_light(Vector3(host.hero.x, 3.0, host.hero.y), COLD, 2.2, 14.0, 0.2)
		"break":
			_do_break(positions)

func _add_ice(positions: Array) -> void:
	var delay_base := 0.0
	for pos in positions:
		if _items.size() >= MAX_ICE: break
		var at: Vector2 = pos
		if _frozen.size() < 64: _frozen.append(at)
		var k := _items.size()
		_items.append({"pos": at, "seed": float(k % 29) / 29.0, "age": -host.hash1(float(k) * 2.3) * 0.25, "br": -1.0})

func _do_break(positions: Array) -> void:
	if _broke: return
	_broke = true
	_bt = 0.0
	host.stats.breaks += 1
	host.hitstop(host.HITSTOP_SECONDS)
	host.kick(1.0)
	_white = WHITE_PEAK
	_white_frames = 2
	var points := PackedVector3Array()
	var from: Array = []
	for at in _frozen: from.append(at)
	for at in positions: from.append(at)
	for at in from:
		if points.size() >= 64: break
		var v: Vector2 = at
		points.append(Vector3(v.x, 0.6, v.y))
	if points.is_empty(): points.append(Vector3(host.sw.center.x, 0.6, host.sw.center.y))
	var image := Image.create_from_data(points.size(), 1, false, Image.FORMAT_RGBF, points.to_byte_array())
	_shard_mat.emission_point_texture = ImageTexture.create_from_image(image)
	_shard_mat.emission_point_count = points.size()
	_shards.restart()
	_shards.emitting = true
	for item in _items: item.br = 0.0
	host.pool_light(Vector3(host.hero.x, 3.5, host.hero.y), Color(0.75, 0.93, 1.0), 6.0, 26.0, 0.25)

func update(t: float, dt: float) -> void:
	var dur: float = host.sw.dur
	var center: Vector2 = host.sw.center
	if _broke: _bt += dt
	_gust = maxf(0.0, _gust - host.wall_dt * 4.0)
	var onset_t := _onset if _onset >= 0.0 else 0.3
	# storm + sky
	var enter: float = host.ease_out(host.ramp_t(t, 1.0 / 60.0, 0.3))
	var leave: float = 1.0 - host.ramp_t(_bt, 0.1, 0.8) if _broke else 1.0
	host.scr.storm = enter * leave
	host.scr.gust = _gust
	host.scr.sky = host.ramp_t(t, 0.0, 0.4) * (1.0 - host.ramp_t(t, dur + 0.2, dur + 1.2))
	if _white_frames > 0: _white_frames -= 1
	else: _white = maxf(0.0, _white - host.wall_dt * (WHITE_PEAK / 0.12))
	host.scr.whiteout = _white
	# the demon: a long exhale while the storm blows, the fist closes at the break
	var pose: float = 0.35 * host.ramp_t(t, 0.3, 2.0)
	if _broke: pose = lerpf(1.0, 0.0, host.ramp_t(_bt, 0.5, 1.2))
	host.scr.demon_pose = pose
	# the floor and the rim
	if _onset >= 0.0 or t >= 0.3:
		var grow: float = host.ease_out(host.ramp_t(t, onset_t, onset_t + 0.5))
		_ground.visible = true
		_ground_mat.set_shader_parameter("time", t)
		_ground_mat.set_shader_parameter("progress", grow)
		var d: Vector2 = host.hero - center
		var rad := deg_to_rad(float(host.sw.area.right_deg))
		var right := Vector2(cos(rad), sin(rad))
		var down := right.rotated(PI * 0.5)
		_ground_mat.set_shader_parameter("hero_local", Vector2(d.dot(right), d.dot(down)))
		_ground.position = Vector3(center.x, 0.045, center.y)
		if _broke:
			_shatter = host.ramp_t(_bt, 0.0, 0.42)
			_ground_mat.set_shader_parameter("shatter", minf(_shatter, 0.7))
			_ground_mat.set_shader_parameter("fade", 1.0 - 0.65 * host.ramp_t(_bt, 0.3, 0.65) - 0.35 * host.ramp_t(_bt, 0.65, 3.0))
		_freeze = host.ease_out(host.ramp_t(t, onset_t, onset_t + 0.5)) if not _broke else 1.0 - host.ramp_t(_bt, 0.25, 0.6)
	# wind particles follow the hero, upwind
	var hero: Vector2 = host.hero
	_storm.global_position = Vector3(hero.x - _wind.x * 14.0, 8.0, hero.y - _wind.y * 14.0)
	if _broke and _bt > 0.3: _storm.emitting = false
	# the ice skins
	var mm := _ice.multimesh
	var n := 0
	for item in _items:
		item.age = float(item.age) + dt
		if float(item.br) >= 0.0: item.br = float(item.br) + dt
		if float(item.age) < 0.0: continue
		var br := clampf(float(item.br) / 0.45, 0.0, 1.0) if float(item.br) >= 0.0 else 0.0
		if br >= 1.0: continue
		var at: Vector2 = item.pos
		var s := 1.0 + 0.25 * br
		mm.set_instance_transform(n, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), Vector3(at.x, 1.0, at.y)))
		mm.set_instance_custom_data(n, Color(float(item.age), item.seed, _cracks, br))
		n += 1
	mm.visible_instance_count = n

## One invisible frame of every material (tiny, fully transparent), so the first real sweep has nothing left to compile.
func warm(on: bool) -> void:
	var at: Vector2 = host.hero
	if on:
		_ground.visible = true
		_ground.position = Vector3(at.x, 0.045, at.y)
		_ground_mat.set_shader_parameter("fade", 0.0)
		_ground_mat.set_shader_parameter("rect", Vector2(2.0, 2.0))
		var mm := _ice.multimesh
		mm.set_instance_transform(0, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.001), Vector3(at.x, 1.0, at.y)))
		mm.set_instance_custom_data(0, Color(0, 0, 0, 0))
		mm.visible_instance_count = 1
		_storm.global_position = Vector3(at.x, 8.0, at.y)
		_storm.amount_ratio = 0.02
		_storm.emitting = true
		_shards.global_position = Vector3(at.x, 0.6, at.y)
		_shards.amount_ratio = 0.02
		_shards.restart()
		_shards.emitting = true
	else:
		hide_all()
		_storm.emitting = false
		_storm.amount_ratio = 1.0
		_shards.amount_ratio = 1.0

func set_hold(on: bool) -> void:
	var speed := 0.0 if on else 1.0
	_storm.speed_scale = speed
	_shards.speed_scale = speed

func hide_all() -> void:
	if is_instance_valid(_ground): _ground.visible = false
	if is_instance_valid(_ice): _ice.multimesh.visible_instance_count = 0

func finish() -> void:
	hide_all()
	if is_instance_valid(_storm): _storm.emitting = false
	_items.clear()
	_frozen = PackedVector2Array()
	_freeze = 0.0
	_shatter = 0.0

func reset() -> void:
	_items.clear()
