extends RefCounted
## Drawing helpers of the grace screen (A8 G6): colours and text labels, soft lights, the code shapes the picture parts fall back to.
## Moved from the old proposal kit into the product; the proposal tools now read this file.
## Reads palette.gd and loc.gd, writes to neither. Names are kept so grace_parts.gd reads the same as the proposals did.
const Palette = preload("res://chapter1/view/hud/palette.gd")
const Loc = preload("res://chapter1/view/loc.gd")
const SELF_PATH := "res://chapter1/view/hud/grace_draw.gd"

const SIZE := Vector2(1600, 900)
const GAIN := Color("8fd694")  ## a rising value (green + arrow)
const LOSS := Color("e07a6a")  ## a falling value
const WRAP := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE

static var _glow: GradientTexture2D
static var _vig: GradientTexture2D
static var _feather: Shader

static func el_color(element: String) -> Color:
	return Palette.element_color(element, Palette.BRASS)

static func el_text(element: String) -> Color:
	return Palette.element_text_color(element, Palette.INK_DIM)

static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)

# ---- textures ----

static func glow() -> GradientTexture2D:
	if _glow == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
		g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		_glow = GradientTexture2D.new()
		_glow.gradient = g
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1.0, 0.5)
		_glow.width = 256
		_glow.height = 256
	return _glow

static func vignette_texture() -> GradientTexture2D:
	if _vig == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.0), Color(0.01, 0.012, 0.02, 0.92)])
		g.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
		_vig = GradientTexture2D.new()
		_vig.gradient = g
		_vig.fill = GradientTexture2D.FILL_RADIAL
		_vig.fill_from = Vector2(0.5, 0.5)
		_vig.fill_to = Vector2(1.05, 0.5)
		_vig.width = 256
		_vig.height = 256
	return _vig

static func feather_material(fx: float, fb: float, ft: float = 0.0) -> ShaderMaterial:
	if _feather == null:
		_feather = Shader.new()
		_feather.code = "shader_type canvas_item;\nuniform float fx = 0.15;\nuniform float fb = 0.3;\nuniform float ft = 0.0;\nvoid fragment(){ vec4 c = texture(TEXTURE, UV); float ax = smoothstep(0.0, fx, UV.x) * smoothstep(0.0, fx, 1.0 - UV.x); float ab = smoothstep(0.0, max(fb, 0.001), 1.0 - UV.y); float at = ft > 0.0 ? smoothstep(0.0, ft, UV.y) : 1.0; COLOR = vec4(c.rgb, c.a * ax * ab * at); }\n"
	var m := ShaderMaterial.new()
	m.shader = _feather
	m.set_shader_parameter("fx", fx)
	m.set_shader_parameter("fb", fb)
	m.set_shader_parameter("ft", ft)
	return m

static func add_glow(parent: Node, centre: Vector2, radius: float, color: Color, additive := true) -> TextureRect:
	var t := TextureRect.new()
	t.texture = glow()
	t.position = centre - Vector2(radius, radius)
	t.size = Vector2(radius, radius) * 2.0
	t.modulate = color
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	if additive:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		t.material = m
	parent.add_child(t)
	return t

# ---- text ----

static func measure(text: String, size: int, width: float, role := "body") -> Vector2:
	return Loc.font(role).get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, size, -1, WRAP)

static func lines_of(text: String, size: int, width: float, role := "body") -> int:
	var h := Loc.font(role).get_height(size)
	return maxi(1, int(round(measure(text, size, width, role).y / h)))

## A fixed-size Label sized from the font's own measure (so the layout check sees a box that fits).
static func lbl(parent: Node, text: String, pos: Vector2, width: float, size: int, color: Color, role := "body",
		align := HORIZONTAL_ALIGNMENT_LEFT, wrap := true, shadow := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Loc.font(role))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if shadow:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("shadow_offset_x", 1)
		l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := 1
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n = lines_of(text, size, width, role)
	l.position = pos
	l.size = Vector2(width, ceil(Loc.font(role).get_height(size) * n) + 3.0 * (n - 1) + 4.0)
	parent.add_child(l)
	return l

static func line_height(size: int, role := "body") -> float:
	return ceil(Loc.font(role).get_height(size))

# ---- drawing helpers (call from a CanvasItem's _draw) ----

static func quad(ci: CanvasItem, r: Rect2, top: Color, bottom: Color) -> void:
	ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))

static func tf(pts: Array, c: Vector2, r: float, rot: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts: out.append(c + (Vector2(p[0], p[1]) * r).rotated(rot))
	return out

static func dashed_arc(ci: CanvasItem, c: Vector2, rad: float, start: float, count: int, fill: float, col: Color, w: float) -> void:
	for i in count:
		var a0 := start + float(i) * TAU / float(count)
		ci.draw_arc(c, rad, a0, a0 + TAU / float(count) * fill, 6, col, w, true)

static func diamond(ci: CanvasItem, c: Vector2, r: float, col: Color, filled := true, w := 1.5) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	if filled: ci.draw_colored_polygon(pts, col)
	else:
		pts.append(pts[0])
		ci.draw_polyline(pts, col, w, true)

## The element mark: a different SHAPE per element (flame / snow-star / bolt), so colour is never the only signal.
static func draw_badge(ci: CanvasItem, element: String, c: Vector2, s: float, col: Color) -> void:
	ci.draw_circle(c, s * 1.45, Color(0.02, 0.025, 0.03, 0.78))
	ci.draw_arc(c, s * 1.45, 0, TAU, 28, with_alpha(col, 0.9), 1.5, true)
	match element:
		"ember":
			ci.draw_colored_polygon(tf([[0, -1.0], [0.55, -0.15], [0.6, 0.45], [0.0, 1.0], [-0.6, 0.45], [-0.5, -0.1], [-0.12, 0.15]], c, s, 0.0), col)
		"frost":
			for i in 3:
				var a := float(i) * PI / 3.0
				ci.draw_line(c + Vector2.from_angle(a) * s, c - Vector2.from_angle(a) * s, col, 2.0, true)
			for i in 6:
				var a2 := float(i) * PI / 3.0
				var tip := c + Vector2.from_angle(a2) * s * 0.62
				ci.draw_line(tip, tip + Vector2.from_angle(a2 + 0.9) * s * 0.3, col, 1.4, true)
				ci.draw_line(tip, tip + Vector2.from_angle(a2 - 0.9) * s * 0.3, col, 1.4, true)
		_:
			ci.draw_colored_polygon(tf([[0.25, -1.0], [-0.55, 0.1], [-0.05, 0.1], [-0.3, 1.0], [0.6, -0.2], [0.05, -0.2]], c, s, 0.0), col)

## The big per-kind emblem. Draws inside radius r around c. `phase` turns the dashed parts (idle motion).
static func draw_emblem(ci: CanvasItem, kind: String, element: String, c: Vector2, r: float, energy: float, phase: float, tone: float = 1.0) -> void:
	var col := Color(0.6, 0.6, 0.58).lerp(el_color(element), tone)
	var lit := col.lightened(0.45)
	var deep := col.darkened(0.55)
	var e := clampf(energy, 0.0, 1.5)
	ci.draw_circle(c, r * 0.97, Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, 0.55))
	ci.draw_arc(c, r * 0.97, 0, TAU, 56, with_alpha(col, 0.35 + 0.25 * e), 2.0, true)
	match kind:
		"ring":
			dashed_arc(ci, c, r * 0.9, phase, 20, 0.55, with_alpha(lit, 0.9), 3.5)
			ci.draw_arc(c, r * 0.70, 0, TAU, 64, with_alpha(col, 1.0), 5.0, true)
			ci.draw_arc(c, r * 0.56, 0, TAU, 64, with_alpha(col, 0.5), 1.8, true)
			for i in 14:
				var a := -phase * 0.5 + float(i) * TAU / 14.0
				ci.draw_line(c + Vector2.from_angle(a) * r * 0.70, c + Vector2.from_angle(a) * r * 0.48, with_alpha(lit, 0.95), 4.5, true)
			diamond(ci, c, r * 0.16, Color(1, 1, 1, 0.92))
			diamond(ci, c, r * 0.26, with_alpha(lit, 0.8), false, 2.0)
		"lance":
			var rot := 0.62
			for s in [-1.0, 1.0]:
				ci.draw_colored_polygon(tf([[0.52 * s, -0.22], [0.64 * s, 0.05], [0.52 * s, 0.34], [0.42 * s, 0.05]], c, r, rot), with_alpha(lit, 0.85))
				ci.draw_colored_polygon(tf([[0.72 * s, 0.38], [0.8 * s, 0.56], [0.72 * s, 0.74], [0.64 * s, 0.56]], c, r, rot), with_alpha(col, 0.8))
			ci.draw_colored_polygon(tf([[0, -0.95], [0.17, -0.30], [0.06, 0.56], [0, 0.62], [-0.06, 0.56], [-0.17, -0.30]], c, r, rot), col)
			ci.draw_colored_polygon(tf([[0, -0.95], [-0.17, -0.30], [-0.06, 0.56], [0, 0.62]], c, r, rot), lit)
			for i in 3:
				var x := (float(i) - 1.0) * 0.1
				ci.draw_line(c + Vector2(x, 0.7).rotated(rot) * r, c + Vector2(x, 0.95 + 0.04 * i).rotated(rot) * r, with_alpha(lit, 0.6 - 0.15 * i), 2.5, true)
		"orb":
			var head := c + Vector2(0.14, -0.12) * r
			for k in 4:
				var a := 2.5 + float(k - 1.5) * 0.3
				var tip := head + Vector2.from_angle(a) * r * (0.95 - 0.08 * k)
				ci.draw_colored_polygon(PackedVector2Array([head + Vector2.from_angle(a + 1.35) * r * 0.36, tip, head + Vector2.from_angle(a - 1.35) * r * 0.36]),
					with_alpha(col.lerp(Color.WHITE, 0.1 * k), 0.75))
			ci.draw_circle(head, r * 0.42, col)
			ci.draw_circle(head + Vector2(-0.04, -0.04) * r, r * 0.27, lit)
			ci.draw_circle(head + Vector2(-0.06, -0.06) * r, r * 0.12, Color(1, 1, 1, 0.9))
			for i in 5:
				var sp := head + Vector2.from_angle(3.3 + 0.5 * i + phase * 0.3) * r * (0.62 + 0.1 * (i % 3))
				ci.draw_circle(sp, r * 0.04, with_alpha(lit, 0.85))
		"bolt":
			ci.draw_arc(c, r * 0.8, 3.6, 4.8, 12, with_alpha(lit, 0.7), 2.5, true)
			ci.draw_arc(c, r * 0.8, 0.45, 1.65, 12, with_alpha(lit, 0.7), 2.5, true)
			for a in [3.6, 4.8, 0.45, 1.65]: ci.draw_circle(c + Vector2.from_angle(a) * r * 0.8, r * 0.06, lit)
			ci.draw_colored_polygon(tf([[0.18, -0.95], [-0.42, 0.06], [-0.03, 0.06], [-0.24, 0.95], [0.46, -0.18], [0.06, -0.18]], c, r, 0.0), col)
			ci.draw_colored_polygon(tf([[0.18, -0.95], [-0.42, 0.06], [-0.2, 0.06], [0.04, -0.5]], c, r, 0.0), lit)
		"crystal":
			var pts := [[0, -0.92], [0.52, -0.46], [0.52, 0.46], [0, 0.92], [-0.52, 0.46], [-0.52, -0.46]]
			ci.draw_colored_polygon(tf(pts, c, r, 0.0), with_alpha(col, 0.9))
			ci.draw_colored_polygon(tf([[0, -0.92], [0.52, -0.46], [0, 0.0]], c, r, 0.0), lit)
			ci.draw_colored_polygon(tf([[0, -0.92], [-0.52, -0.46], [0, 0.0]], c, r, 0.0), with_alpha(Color.WHITE, 0.55))
			ci.draw_colored_polygon(tf([[0, 0.92], [0.52, 0.46], [0, 0.0]], c, r, 0.0), deep)
			ci.draw_colored_polygon(tf([[-0.52, -0.46], [-0.52, 0.46], [0, 0.0]], c, r, 0.0), with_alpha(col, 0.6))
			var edge := tf(pts, c, r, 0.0)
			edge.append(edge[0])
			ci.draw_polyline(edge, Color(1, 1, 1, 0.85), 2.0, true)
			for s2 in [-1.0, 1.0]: ci.draw_colored_polygon(tf([[0.78 * s2, -0.1], [0.86 * s2, 0.14], [0.78 * s2, 0.38], [0.7 * s2, 0.14]], c, r, 0.0), with_alpha(lit, 0.8))
		"nova":
			var star := []
			for i in 24:
				var rr := 0.98 if i % 2 == 0 else 0.5
				if i % 6 == 0: rr = 1.0
				elif i % 2 == 0: rr = 0.8
				star.append([cos(float(i) * TAU / 24.0 + phase * 0.1) * rr, sin(float(i) * TAU / 24.0 + phase * 0.1) * rr])
			ci.draw_colored_polygon(tf(star, c, r, 0.0), with_alpha(col, 0.95))
			ci.draw_colored_polygon(tf(star.map(func(p): return [p[0] * 0.55, p[1] * 0.55]), c, r, 0.0), lit)
			ci.draw_circle(c, r * 0.22, Color(1, 1, 1, 0.95))
			dashed_arc(ci, c, r * 0.95, -phase, 12, 0.4, Color(1, 1, 1, 0.55), 2.0)
		_:
			diamond(ci, c, r * 0.5, col)

# ---- the code face of a card (used only when the frame / ground pictures are missing) ----

const GRADE_RANK := {"common": 0, "scarce": 1, "fated": 2}
const GRADE_EXTRA := {"scarce": Color("e0c47e"), "fated": Color("ffc24d")}

static func grade_color(grade: String) -> Color:
	return GRADE_EXTRA.get(grade, Palette.QUALITY_COMMON)

## Grade = frame FORM (plain / line / double with studs / double with rays) + a low colour glow, so it reads in black and white.
## Restraint rule: the grade colour is strong only on the focused card (focus 0..1); the others sink to a muted edge.
## Material: stone-grey face with speckle, a bevel (light top-left, dark bottom-right) and a metal inner line.
static func draw_face(ci: CanvasItem, rect: Rect2, grade: String, focus: float, leak: float = 0.0) -> void:
	var gc := grade_color(grade)
	var rank: int = GRADE_RANK.get(grade, 0)
	var muted := Color(0.5, 0.5, 0.48).lerp(gc, 0.35 + 0.65 * focus)
	var top := Color(0.145 + gc.r * 0.07 * (0.4 + focus), 0.15 + gc.g * 0.07 * (0.4 + focus), 0.158 + gc.b * 0.07 * (0.4 + focus), 0.98)
	var bottom := Color(0.065, 0.07, 0.078, 0.98)
	quad(ci, rect, top, bottom)
	if grade == "fated": quad(ci, rect, with_alpha(gc, 0.30), with_alpha(gc, 0.05))
	elif grade == "scarce": quad(ci, rect, with_alpha(gc, 0.12), with_alpha(gc, 0.02))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + int(rect.size.x)
	for i in int(rect.size.x * rect.size.y / 900.0):
		var p := rect.position + Vector2(rng.randf() * rect.size.x, rng.randf() * rect.size.y)
		ci.draw_rect(Rect2(p, Vector2(rng.randf_range(1.0, 2.5), 1.0)), Color(1, 1, 1, rng.randf_range(0.02, 0.07)))
	quad(ci, Rect2(rect.position, Vector2(rect.size.x, 7)), with_alpha(muted, 0.55 + 0.4 * focus), with_alpha(muted, 0.35 + 0.35 * focus))
	ci.draw_line(rect.position + Vector2(2, 2), Vector2(rect.end.x - 2, rect.position.y + 2), Color(1, 1, 1, 0.16), 1.0)
	ci.draw_line(rect.position + Vector2(2, 2), Vector2(rect.position.x + 2, rect.end.y - 2), Color(1, 1, 1, 0.10), 1.0)
	ci.draw_line(Vector2(rect.position.x + 2, rect.end.y - 2), rect.end - Vector2(2, 2), Color(0, 0, 0, 0.5), 2.0)
	ci.draw_line(Vector2(rect.end.x - 2, rect.position.y + 2), rect.end - Vector2(2, 2), Color(0, 0, 0, 0.45), 2.0)
	var edge := with_alpha(muted, 0.95) if rank > 0 else Color(0.55, 0.54, 0.5)
	ci.draw_rect(rect, edge, false, 2.0 + float(rank))
	ci.draw_rect(rect.grow(-5), Color(Palette.BRASS_DIM.r, Palette.BRASS_DIM.g, Palette.BRASS_DIM.b, 0.9), false, 1.0)
	if rank >= 2:
		ci.draw_rect(rect.grow(-9), with_alpha(muted, 0.55), false, 1.5)
		for p in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
			diamond(ci, p, 8.0, muted)
			diamond(ci, p, 3.5, Color(0.05, 0.05, 0.06), true)
	if rank >= 3:
		var mid := Vector2(rect.get_center().x, rect.position.y + 7)
		for i in 9:
			var a := PI * (0.12 + 0.76 * float(i) / 8.0)
			ci.draw_line(mid, mid + Vector2.from_angle(a) * rect.size.y * 0.45, with_alpha(gc, 0.07 + 0.12 * focus), 2.0, true)
		diamond(ci, mid, 9.0, Color(0.95, 0.88, 0.75))
	if leak > 0.0:
		for i in 7:
			ci.draw_rect(rect.grow(float(i) * 3.0), with_alpha(gc, 0.30 * leak * (1.0 - float(i) / 7.0)), false, 3.0)
	if focus > 0.0:
		for i in 6:
			ci.draw_rect(rect.grow(float(i) * 3.0 + 1.0), with_alpha(Palette.BRASS_HI, 0.26 * focus * (1.0 - float(i) / 6.0)), false, 3.0)
		ci.draw_rect(rect, with_alpha(Palette.BRASS_HI, focus), false, 3.0)

# ---- the code mark of a card kind (fallback of the emblem pictures) ----

class Emblem extends Control:
	var kind := "ring"
	var element := "frost"
	var energy := 1.0:
		set(v):
			energy = v
			queue_redraw()
	var phase := 0.0
	var idle := false
	var tone := 1.0:
		set(v):
			tone = v
			queue_redraw()
	func _init(k := "ring", e := "frost", s := Vector2(64, 64), animated := false) -> void:
		kind = k
		element = e
		size = s
		custom_minimum_size = s
		pivot_offset = s * 0.5
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		idle = animated
		set_process(animated)
	func _process(delta: float) -> void:
		phase += delta * 0.35
		queue_redraw()
	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		var ci: CanvasItem = self
		var kit = load(SELF_PATH)
		kit.draw_emblem(ci, kind, element, size * 0.5, r, energy, phase, tone)

