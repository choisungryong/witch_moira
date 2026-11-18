extends Node2D
## Thin lightning that now and then jumps from the raised hand (storm witch). A bolt lasts 0.12 s and bolts come
## 0.8 to 2.4 s apart (never more than two a second); there is no screen flash. The schedule is a pure function of the
## seed and the clock, so captures repeat exactly. Origin is the hand.

const BOLT_LIFE := 0.12

var _times: Array[float] = []
var _seeds: Array[int] = []
var _t := 0.0
var _strength := 1.0
var _glow: Sprite2D
var _pos := Vector2.ZERO


func setup(def: Dictionary, seed_value: int) -> void:
	var p: Array = def.get("pos", [0, 0])
	_pos = Vector2(p[0], p[1])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 13
	var t := rng.randf_range(0.6, 1.4)
	while t < 120.0:
		_times.append(t)
		_seeds.append(rng.randi())
		t += rng.randf_range(0.8, 2.4)
	print("LP_BOLTS first=", _times.slice(0, 5))
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([Color(0.75, 0.65, 1.0, 0.5), Color(0.45, 0.3, 0.9, 0.18), Color(0.3, 0.2, 0.8, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	_glow = Sprite2D.new()
	_glow.texture = tex
	_glow.scale = Vector2.ONE * 1.0
	_glow.material = mat
	add_child(_glow)


func update(t: float, xf: Transform2D, strength: float, _xf2: Transform2D = Transform2D.IDENTITY) -> void:
	_t = t
	_strength = strength
	position = xf * _pos
	_glow.modulate.a = strength * (0.55 + 0.25 * sin(TAU * t / 3.1) + 0.2 * sin(TAU * t / 1.9 + 1.0))
	queue_redraw()


func _draw() -> void:
	for i in _times.size():
		var d := _t - _times[i]
		if d < 0.0:
			return
		if d < BOLT_LIFE:
			_bolt(_seeds[i], 1.0 - d / BOLT_LIFE)
			return


func _bolt(seed_value: int, life: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var dir := Vector2.UP.rotated(rng.randf_range(-1.3, 1.3))
	var length := rng.randf_range(80.0, 170.0)
	var pts := PackedVector2Array([Vector2.ZERO])
	var n := 7
	var perp := dir.orthogonal()
	for i in range(1, n + 1):
		var f := float(i) / n
		pts.append(dir * length * f + perp * rng.randf_range(-14.0, 14.0) * (1.0 - 0.3 * f))
	var a := _strength * (0.55 + 0.45 * life)
	draw_polyline(pts, Color(0.55, 0.4, 1.0, 0.4 * a), 6.0, true)
	draw_polyline(pts, Color(0.95, 0.93, 1.0, a), 2.0, true)
	var k := rng.randi_range(2, 4)
	var bpts := PackedVector2Array([pts[k]])
	var bdir := dir.rotated(rng.randf_range(0.5, 1.0) * (1.0 if rng.randf() < 0.5 else -1.0))
	for j in range(1, 4):
		bpts.append(pts[k] + bdir * length * 0.14 * j + bdir.orthogonal() * rng.randf_range(-6.0, 6.0))
	draw_polyline(bpts, Color(0.9, 0.88, 1.0, 0.8 * a), 1.4, true)
