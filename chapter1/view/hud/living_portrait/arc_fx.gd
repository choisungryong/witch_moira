extends Node2D
## Lightning that runs from one open hand to the other across the torso (storm witch): a thick bright core whose width
## changes from moment to moment, several thin branches (with twigs), a violet bloom around it, and sparks at the hands.
## The path is redrawn about eight times a second; now and then the arc breaks in the middle for a moment and joins
## again. The brightness stays nearly constant (no flashing of the whole picture).
## Definition: {"type": "arc", "follow": left hand layer id, "follow2": right hand layer id,
##              "from": [x, y] in the left layer, "to": [x, y] in the right layer, "sag": pixels}
## The node is placed at the origin of the figure space, points are in that space.

const STEP := 1.0 / 8.0

var _from := Vector2(150.0, 410.0)
var _to := Vector2(895.0, 415.0)
var _sag := 18.0
var _a := Vector2.ZERO
var _b := Vector2.ZERO
var _t := 0.0
var _strength := 1.0
var _seed := 11


func setup(def: Dictionary, seed_value: int = 11) -> void:
	_seed = seed_value
	var f: Array = def.get("from", [150, 410])
	var g: Array = def.get("to", [895, 415])
	_from = Vector2(f[0], f[1])
	_to = Vector2(g[0], g[1])
	_sag = float(def.get("sag", 18.0))
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


func update(t: float, xf: Transform2D, strength: float, xf2: Transform2D = Transform2D.IDENTITY) -> void:
	_t = t
	_strength = strength
	_a = xf * _from
	_b = xf2 * _to
	queue_redraw()


## 0 normally; rises to 1 for about 0.34 s every 3.4 s (the arc is broken in the middle).
func _gap(t: float) -> float:
	var cycle := 3.4
	var u := fposmod(t, cycle)
	if u > cycle - 0.34:
		return sin(PI * (u - (cycle - 0.34)) / 0.34)
	return 0.0


func _draw() -> void:
	var step := int(floor(_t / STEP))
	var gap := _gap(_t)
	var core := _path(step, 0, 1.0)
	# violet bloom first, then the second strand, then the thick core
	_bloom(core, gap)
	_strand(_path(int(floor((_t + 0.05) / STEP)), 1, 0.7), gap, 0.5, 0.6)
	_strand(core, gap, 1.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed * 131 + step
	var main := core
	# branches with twigs
	for k in 8:
		var at := rng.randi_range(3, main.size() - 4)
		var dir := (Vector2.UP if rng.randf() < 0.5 else Vector2.DOWN).rotated(rng.randf_range(-0.9, 0.9))
		var length := rng.randf_range(34.0, 105.0)
		var pts := PackedVector2Array([main[at]])
		var cur := main[at]
		var segs := rng.randi_range(3, 5)
		for j in segs:
			cur += dir * length / segs + dir.orthogonal() * rng.randf_range(-11.0, 11.0)
			pts.append(cur)
			if j == 1 and rng.randf() < 0.7:
				var tw := PackedVector2Array([cur])
				var tdir := dir.rotated(rng.randf_range(0.6, 1.1) * (1.0 if rng.randf() < 0.5 else -1.0))
				var tc := cur
				for q in 2:
					tc += tdir * rng.randf_range(10.0, 18.0) + tdir.orthogonal() * rng.randf_range(-5.0, 5.0)
					tw.append(tc)
				_thin(tw, 0.55)
		_thin(pts, 0.8)
	# sparks at the two hands
	for h in 2:
		var origin := _a if h == 0 else _b
		for k in 7:
			var life := fposmod(_t * 3.0 + k * 0.143 + h * 0.31, 1.0)
			var ang := rng.randf_range(0.0, TAU)
			var pos := origin + Vector2.from_angle(ang) * (6.0 + 36.0 * life)
			draw_circle(pos, 2.6 * (1.0 - life) + 0.8, Color(0.9, 0.85, 1.0, 0.8 * (1.0 - life) * _strength))


func _path(step: int, variant: int, amp: float) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed * 977 + step * 31 + variant * 7
	var n := 34
	var pts := PackedVector2Array()
	var dir := _b - _a
	var perp := dir.orthogonal().normalized()
	for i in n + 1:
		var f := float(i) / n
		var envelope := sin(PI * f)
		var jitter := rng.randf_range(-1.0, 1.0) * (5.0 + 26.0 * envelope) * amp
		var sag := _sag * envelope * (1.0 if variant == 0 else -0.6)
		pts.append(_a + dir * f + perp * (jitter + sag))
	return pts


func _fade(f: float, gap: float) -> float:
	var d := absf(f - 0.5)
	return 1.0 - gap * clampf(1.0 - d / 0.14, 0.0, 1.0)


func _bloom(pts: PackedVector2Array, gap: float) -> void:
	var n := pts.size()
	for i in n - 1:
		var a := _strength * 0.5 * _fade(float(i) / (n - 1), gap)
		if a > 0.01:
			draw_line(pts[i], pts[i + 1], Color(0.45, 0.3, 1.0, 0.10 * a), 40.0, true)
			draw_line(pts[i], pts[i + 1], Color(0.5, 0.35, 1.0, 0.16 * a), 22.0, true)


## A strand whose thickness changes along its length and from step to step.
func _strand(pts: PackedVector2Array, gap: float, k: float, thick: float) -> void:
	var n := pts.size()
	for i in n - 1:
		var f := float(i) / (n - 1)
		var a := _strength * k * _fade(f, gap)
		if a <= 0.01:
			continue
		var wob := 0.65 + 0.55 * sin(float(i) * 1.9 + floor(_t / STEP) * 2.3) * sin(float(i) * 0.7 + _t * 7.0)
		var w := (3.0 + 8.0 * wob) * thick
		draw_line(pts[i], pts[i + 1], Color(0.5, 0.35, 1.0, 0.30 * a), w * 2.6, true)
		draw_line(pts[i], pts[i + 1], Color(0.72, 0.62, 1.0, 0.6 * a), w * 1.3, true)
		draw_line(pts[i], pts[i + 1], Color(0.98, 0.96, 1.0, 0.95 * a), maxf(w * 0.5, 1.6), true)


func _thin(pts: PackedVector2Array, k: float) -> void:
	var a := _strength * k
	draw_polyline(pts, Color(0.55, 0.4, 1.0, 0.35 * a), 6.0, true)
	draw_polyline(pts, Color(0.95, 0.93, 1.0, 0.9 * a), 1.7, true)
