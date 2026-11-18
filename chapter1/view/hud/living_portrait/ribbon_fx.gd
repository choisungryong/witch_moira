extends Node2D
## Flame ribbons that curl off the coal arm (fire witch). Each ribbon follows a smooth curve through control points given
## in the coordinates of the layer it follows. The width changes along the ribbon and over time (noise), the outline
## wobbles, tongues of flame lick off the sides and lean along the flow, bright lumps run along the ribbon from the
## hand outward, the tail thins out and breaks into sparks that fall away.
## Definition: {"type": "ribbon", "follow": layer id, "ribbons": [{"pts": [[x, y], ...], "width": 22.0, "speed": 0.7}]}

const SAMPLES := 56

var _defs: Array = []
var _xf := Transform2D.IDENTITY
var _t := 0.0
var _strength := 1.0


## draw_polygon fails ("Invalid polygon data, triangulation failed") for a polygon with no area, with a NaN corner or whose
## edges cross (a twisted quad where the ribbon's normal flips); such a polygon draws nothing, so skipping it changes
## nothing on screen and keeps the error out of the log.
static func _drawable(poly: PackedVector2Array) -> bool:
	var n := poly.size()
	var area2 := 0.0
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		area2 += a.x * b.y - b.x * a.y
	if not (absf(area2) > 0.02):
		return false
	if n == 4:
		if Geometry2D.segment_intersects_segment(poly[0], poly[1], poly[2], poly[3]) != null:
			return false
		if Geometry2D.segment_intersects_segment(poly[1], poly[2], poly[3], poly[0]) != null:
			return false
	return true


func setup(def: Dictionary) -> void:
	_defs = def.get("ribbons", [])
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


func update(t: float, xf: Transform2D, strength: float, _xf2: Transform2D = Transform2D.IDENTITY) -> void:
	_t = t
	_xf = xf
	_strength = strength
	queue_redraw()


func _noise(x: float) -> float:
	return 0.55 * sin(x) + 0.3 * sin(2.3 * x + 1.7) + 0.15 * sin(4.9 * x + 4.1)


func _hash(i: int) -> float:
	return fposmod(sin(float(i) * 12.9898 + 4.1414) * 43758.5453, 1.0)


func _curve(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	var per := int(ceil(float(SAMPLES) / (n - 1)))
	for i in n - 1:
		var p0: Vector2 = pts[maxi(i - 1, 0)]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var p3: Vector2 = pts[mini(i + 2, n - 1)]
		for k in per:
			var u := float(k) / per
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u))
	out.append(pts[n - 1])
	return out


func _draw() -> void:
	var seed_i := 0
	for r in _defs:
		seed_i += 1
		var raw: Array = []
		for p in r["pts"]:
			raw.append(Vector2(p[0], p[1]))
		var base := _curve(raw)
		var n := base.size()
		var w0 := float(r.get("width", 20.0))
		var speed := float(r.get("speed", 0.7))
		var centre := PackedVector2Array()
		var norm := PackedVector2Array()
		var tang := PackedVector2Array()
		var width := PackedFloat32Array()
		var heat := PackedFloat32Array()
		for i in n:
			var s := float(i) / (n - 1)
			var a := base[maxi(i - 1, 0)]
			var b := base[mini(i + 1, n - 1)]
			var tg := (b - a).normalized()
			var nm := tg.orthogonal()
			var off := nm * (5.0 + 16.0 * s) * _noise(s * 6.5 - _t * 1.5 + seed_i * 2.0)
			off += tg * 6.0 * _noise(s * 4.0 - _t * 0.8)
			centre.append(_xf * (base[i] + off))
			norm.append(_xf.basis_xform(nm))
			tang.append(_xf.basis_xform(tg))
			var thick := 0.75 + 0.55 * _noise(s * 5.0 - _t * 1.2 + seed_i)
			width.append(w0 * maxf(thick, 0.25) * pow(1.0 - s, 0.85) * clampf(s * 10.0 + 0.5, 0.0, 1.0))
			var lump := 0.5 + 0.5 * sin(TAU * (s * 2.6 - _t * speed) + seed_i)
			heat.append((0.35 + 0.65 * lump) * (1.0 - s * 0.8) * _strength)
		# body of the ribbon: three nested strips, wide and red, medium and orange, thin and yellow-white
		var layers := [[2.0, Color(0.85, 0.15, 0.04), 0.5], [1.1, Color(1.0, 0.45, 0.08), 0.95], [0.45, Color(1.0, 0.92, 0.6), 1.0]]
		for L in layers:
			for i in n - 1:
				var h := heat[i]
				var w1: float = width[i] * float(L[0]) * 0.5
				var w2: float = width[i + 1] * float(L[0]) * 0.5
				if w1 < 0.8 or w2 < 0.8 or centre[i].distance_to(centre[i + 1]) < 0.2:
					continue
				var quad := PackedVector2Array([centre[i] + norm[i] * w1, centre[i + 1] + norm[i + 1] * w2, centre[i + 1] - norm[i + 1] * w2, centre[i] - norm[i] * w1])
				var c: Color = L[1]
				var col := Color(c, float(L[2]) * h)
				if _drawable(quad):
					draw_polygon(quad, PackedColorArray([col, col, col, col]))
		# tongues of flame along both edges
		for k in 22:
			var s_k := fposmod(_hash(k + seed_i * 31) * 0.85 + 0.08 * sin(_t * 0.6 + k), 0.9)
			var i0 := int(s_k * (n - 1))
			var side := 1.0 if k % 2 == 0 else -1.0
			var life := fposmod(_t * (0.9 + 0.5 * _hash(k + 77)) + _hash(k + 5), 1.0)
			var len_px := (16.0 + 26.0 * _hash(k + 9)) * sin(PI * life) * (1.0 - s_k * 0.5)
			var root: Vector2 = centre[i0] + norm[i0] * side * width[i0] * 0.45
			var dir: Vector2 = (tang[i0] * 0.55 + norm[i0] * side * 0.75).normalized()
			var tip := root + dir * len_px
			var half := maxf(width[i0] * 0.28, 1.5)
			var tri := PackedVector2Array([root + norm[i0] * half, tip + tang[i0] * 3.0 * sin(_t * 9.0 + k), root - norm[i0] * half])
			if len_px < 3.0:
				continue
			var a_c := 0.55 * heat[i0] * sin(PI * life)
			if not _drawable(tri):
				continue
			draw_polygon(tri, PackedColorArray([Color(1.0, 0.5, 0.1, a_c), Color(1.0, 0.85, 0.4, a_c * 0.2), Color(1.0, 0.5, 0.1, a_c)]))
		# sparks leaving the ribbon, drifting back along the flow and falling
		for k in 26:
			var age := fposmod(_t * 0.45 + _hash(k * 3 + 1), 1.0)
			var s_k := 0.05 + 0.9 * _hash(k * 7 + 3)
			var i0 := int(s_k * (n - 1))
			var side := -1.0 if _hash(k + 40) < 0.5 else 1.0
			var drift: Vector2 = tang[i0] * (30.0 + 40.0 * _hash(k + 13)) * age + norm[i0] * side * 28.0 * age * _hash(k + 21) + Vector2(0.0, 60.0 * age * age)
			var pos: Vector2 = centre[i0] + drift
			var size := (3.2 - 2.2 * age) * (0.6 + 0.8 * _hash(k + 55))
			var al := (1.0 - age) * _strength * (1.0 - s_k * 0.5)
			draw_circle(pos, size * 2.2, Color(1.0, 0.45, 0.1, 0.25 * al))
			draw_circle(pos, size, Color(1.0, 0.85, 0.5, 0.9 * al))
