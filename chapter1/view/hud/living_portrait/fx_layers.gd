extends Node2D
## Particles and light that live behind or in front of the figure, each on its own period.
## kind "back" or "front"; theme "frost" (snow, ice shards, light shafts), "ember" (rising sparks and embers),
## "storm" (rain). Everything is in window pixels; layout() scales it for the window height (960 px reference).

var kind := "back"
var theme := "frost"
var _shafts: Array[Polygon2D] = []
var _t := 0.0


func _init(k: String = "back", th: String = "frost") -> void:
	kind = k
	theme = th
	z_index = 5 if k == "front" else -5
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	if theme == "frost":
		_build_frost(add)
	elif theme == "ember":
		_build_ember(add)
	else:
		_build_storm()


func _build_frost(add: Material) -> void:
	if kind == "back":
		add_child(_particles(_soft(32), 60, 12.0, 0.06, 0.14, 8.0, 18.0, Color(0.7, 0.85, 1.0, 0.4), null))
		var orbs := _particles(_soft(64), 7, 14.0, 0.9, 1.8, 4.0, 9.0, Color(0.4, 0.65, 1.0, 0.07), add)
		orbs.direction = Vector2(-0.3, -1.0)
		add_child(orbs)
	else:
		add_child(_particles(_soft(32), 5, 8.0, 0.8, 1.6, 55.0, 105.0, Color(0.85, 0.94, 1.0, 0.16), null))
		var shards := _particles(_shard(), 4, 11.0, 0.3, 0.6, 20.0, 45.0, Color(0.8, 0.95, 1.0, 0.3), null)
		shards.angular_velocity_min = -50.0
		shards.angular_velocity_max = 50.0
		add_child(shards)
		for i in 2:
			var s := Polygon2D.new()
			s.material = add
			add_child(s)
			_shafts.append(s)


func _build_ember(add: Material) -> void:
	if kind == "back":
		var sparks := _particles(_soft(16), 46, 10.0, 0.10, 0.24, 12.0, 28.0, Color(1.0, 0.55, 0.2, 0.85), add)
		_rise(sparks)
		add_child(sparks)
		var haze := _particles(_soft(64), 6, 14.0, 1.0, 2.0, 5.0, 10.0, Color(1.0, 0.4, 0.1, 0.06), add)
		_rise(haze)
		add_child(haze)
	else:
		var big := _particles(_soft(32), 5, 9.0, 0.7, 1.4, 30.0, 60.0, Color(1.0, 0.5, 0.2, 0.2), add)
		_rise(big)
		add_child(big)


func _build_storm() -> void:
	var streak := _streak()
	if kind == "back":
		var rain := _particles(streak, 90, 1.7, 0.8, 1.2, 520.0, 640.0, Color(0.72, 0.76, 0.95, 0.3), null)
		rain.direction = Vector2(0.14, 1.0)
		rain.spread = 3.0
		rain.particle_flag_align_y = true
		add_child(rain)
	else:
		var drops := _particles(streak, 6, 1.3, 1.8, 2.6, 700.0, 860.0, Color(0.8, 0.84, 1.0, 0.12), null)
		drops.direction = Vector2(0.14, 1.0)
		drops.spread = 3.0
		drops.particle_flag_align_y = true
		add_child(drops)


func _rise(p: CPUParticles2D) -> void:
	p.direction = Vector2(0.12, -1.0)
	p.set_meta("rise", true)


func _particles(tex: Texture2D, count: int, life: float, smin: float, smax: float, vmin: float, vmax: float, col: Color, mat: Material) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex
	p.amount = count
	p.lifetime = life
	p.preprocess = life
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(600.0, 4.0)
	p.direction = Vector2(0.12, 1.0)
	p.spread = 12.0
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = Vector2.ZERO
	p.scale_amount_min = smin
	p.scale_amount_max = smax
	p.color = col
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.85, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	p.color_ramp = ramp
	if mat != null:
		p.material = mat
	return p


func _soft(px: int) -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = px
	t.height = px
	return t


func _streak() -> Texture2D:
	var img := Image.create(4, 36, false, Image.FORMAT_RGBA8)
	for y in 36:
		var a := 1.0 - absf(y - 17.5) / 18.0
		for x in 4:
			var xa := 1.0 - absf(x - 1.5) / 2.0
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a * xa, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _shard() -> Texture2D:
	var img := Image.create(24, 40, false, Image.FORMAT_RGBA8)
	for y in 40:
		for x in 24:
			var nx := absf(x - 11.5) / 11.5
			var ny := absf(y - 19.5) / 19.5
			var d := nx + ny
			if d < 1.0:
				var a := clampf((1.0 - d) * 3.0, 0.0, 1.0)
				var shade := 0.75 + 0.25 * (1.0 - nx)
				img.set_pixel(x, y, Color(shade, shade + 0.1, 1.0, a))
	return ImageTexture.create_from_image(img)


func layout(size: Vector2) -> void:
	var k := size.y / 960.0
	scale = Vector2(k, k)
	for c in get_children():
		if c is CPUParticles2D:
			var y := size.y / k + 30.0 if c.get_meta("rise", false) else -30.0
			c.position = Vector2(size.x * 0.5 / k, y)
			c.emission_rect_extents = Vector2(size.x * 0.6 / k, 4.0)
	var w := size.x / k
	var h := size.y / k
	var defs := [[0.58, 0.16, 0.10, -0.26], [0.78, 0.12, 0.07, -0.18]]
	for i in _shafts.size():
		var d: Array = defs[i]
		var x0: float = w * d[0]
		var half: float = w * d[1] * 0.5
		var slant: float = h * d[3] * 1.0
		var top_mid := Vector2(x0, -10.0)
		var bot_mid := Vector2(x0 + slant * 1.5, h * 0.95)
		_shafts[i].polygon = PackedVector2Array([
			top_mid + Vector2(-half, 0), top_mid, top_mid + Vector2(half, 0),
			bot_mid + Vector2(half * 1.6, 0), bot_mid, bot_mid + Vector2(-half * 1.6, 0)])
		_shafts[i].vertex_colors = PackedColorArray([
			Color(0.6, 0.85, 1.0, 0.0), Color(0.6, 0.85, 1.0, d[2]), Color(0.6, 0.85, 1.0, 0.0),
			Color(0.6, 0.85, 1.0, 0.0), Color(0.6, 0.85, 1.0, 0.0), Color(0.6, 0.85, 1.0, 0.0)])


## Light shafts brighten and fade irregularly (sums of unrelated periods).
func set_time(t: float) -> void:
	_t = t
	for i in _shafts.size():
		var ph := 1.7 * i
		var v := 0.5 + 0.28 * sin(TAU * t / 6.3 + ph) + 0.22 * sin(TAU * t / 9.7 + 2.0 * ph + 1.0)
		_shafts[i].modulate.a = clampf(v * v * 1.6, 0.0, 1.0)
