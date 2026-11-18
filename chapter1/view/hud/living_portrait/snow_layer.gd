extends Node2D
## Two layers of drifting snow in front of the portrait (CPUParticles2D). Far flakes are small and dim, near flakes
## are larger, faster and drift sideways more.

var _far: CPUParticles2D
var _near: CPUParticles2D


func _init() -> void:
	z_index = 10
	var tex := _flake_texture()
	_far = _make(tex, 70, 9.0, 0.10, 0.22, 26.0, 44.0, 0.5)
	_near = _make(tex, 26, 6.0, 0.30, 0.62, 70.0, 120.0, 0.8)
	add_child(_far)
	add_child(_near)


func _make(tex: Texture2D, count: int, life: float, smin: float, smax: float, vmin: float, vmax: float, alpha: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex
	p.amount = count
	p.lifetime = life
	p.preprocess = life
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(600.0, 4.0)
	p.direction = Vector2(0.18, 1.0)
	p.spread = 14.0
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = Vector2.ZERO
	p.scale_amount_min = smin
	p.scale_amount_max = smax
	p.angular_velocity_min = -30.0
	p.angular_velocity_max = 30.0
	p.color = Color(0.86, 0.94, 1.0, alpha)
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.1, 0.9, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	p.color_ramp = ramp
	return p


func _flake_texture() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	return t


## size: viewport size in pixels. Particle units are window pixels at a 960 px high window.
func layout(size: Vector2, intensity: float) -> void:
	var k := size.y / 960.0
	scale = Vector2(k, k)
	for p: CPUParticles2D in [_far, _near]:
		p.position = Vector2(size.x * 0.5 / k, -20.0)
		p.emission_rect_extents = Vector2(size.x * 0.6 / k, 4.0)
		p.speed_scale = maxf(intensity, 0.3)
