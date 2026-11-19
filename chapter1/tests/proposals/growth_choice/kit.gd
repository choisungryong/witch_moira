extends RefCounted
## Shared drawing kit of the three growth-choice proposals (tests only; nothing in chapter1/view imports this).
## Reads the shared base (palette.gd, loc.gd) and never writes to it. Colours or sizes the base does not have are
## kept here and listed in REPORT.txt as "common-base candidates" (GAIN, LOSS, the grade materials).
## Every word on screen comes from the fixture (growth_choice.*.json); this file holds no Korean text.
const Palette = preload("res://chapter1/view/hud/palette.gd")
const Loc = preload("res://chapter1/view/loc.gd")

const SIZE := Vector2(1600, 900)
const GAIN := Color("8fd694")  ## common-base candidate: a rising value (green + arrow)
const LOSS := Color("e07a6a")  ## common-base candidate: a falling value
const GRADE_RANK := {"common": 0, "magic": 1, "rare": 2, "legendary": 3, "scarce": 2, "fated": 3}
const GRADE_EXTRA := {"scarce": Color("7aa8ff"), "fated": Color("ffc24d")}
const CHAR_ART := {"ember": "ember_witch_v02.png", "frost": "frost_witch_v02.png", "arc": "storm_witch_v02.png"}
## Crops of the 1024x1536 full-body paintings (pixel rects): the face for the round portrait, the bust for the scene.
const FACE_CROP := {"ember": Rect2i(365, 40, 310, 310), "frost": Rect2i(285, 10, 310, 310), "arc": Rect2i(315, 120, 310, 310)}
const BUST_CROP := {"ember": Rect2i(20, 0, 980, 1000), "frost": Rect2i(100, 0, 860, 940), "arc": Rect2i(20, 40, 980, 1000)}
const WRAP := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE

static var _glow: GradientTexture2D
static var _vig: GradientTexture2D
static var _feather: Shader

# ---- data ----

static func read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

## "_local/..." paths are found by walking up from the project folder (a worktree sits three folders under the main checkout).
static func find_local(rel: String) -> String:
	var dir := ProjectSettings.globalize_path("res://").rstrip("/")
	for i in 6:
		var p := dir.path_join(rel)
		if FileAccess.file_exists(p): return p
		dir = dir.get_base_dir()
	return ""

static func grade_color(grade: String) -> Color:
	if GRADE_EXTRA.has(grade): return GRADE_EXTRA[grade]
	return Palette.QUALITY_COLORS.get(grade, Palette.QUALITY_COMMON)

static func grade_rank(grade: String) -> int:
	return int(GRADE_RANK.get(grade, 0))

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

static func image_texture(abs_path: String, region := Rect2i()) -> Texture2D:
	var image := Image.load_from_file(abs_path)
	if image == null or image.is_empty(): return null
	if region.size.x > 0: image = image.get_region(region)
	return ImageTexture.create_from_image(image)

static func witch_path(witch_id: String) -> String:
	return ProjectSettings.globalize_path("res://chapter1/art/characters/").path_join(String(CHAR_ART.get(witch_id, "frost_witch_v02.png")))

## A crop of the witch's full-body art (source 1024x1536).
static func witch_crop(witch_id: String, region: Rect2i) -> Texture2D:
	return image_texture(witch_path(witch_id), region)

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

## Backdrop: one real combat capture, dimmed, with a vignette. Returns the root control (has "dim" ColorRect child).
static func make_backdrop(parent: Node, rel_path: String, dim: float, vignette: float = 1.0) -> Control:
	var root := Control.new()
	root.name = "Backdrop"
	root.size = SIZE
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.025, 0.03)
	bg.size = SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var abs_path := find_local(rel_path)
	var tex: Texture2D = image_texture(abs_path) if abs_path != "" else null
	if tex != null:
		var pic := TextureRect.new()
		pic.name = "CombatCapture"
		pic.texture = tex
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.size = SIZE
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(pic)
	else:
		push_warning("backdrop not found: " + rel_path)
	var shade := ColorRect.new()
	shade.name = "Dim"
	shade.color = Color(0.008, 0.012, 0.02, dim)
	shade.size = SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var vig := TextureRect.new()
	vig.name = "Vignette"
	vig.texture = vignette_texture()
	vig.size = SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.modulate = Color(1, 1, 1, vignette)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vig)
	return root

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

# ---- the grade face of a card ----

## Grade = frame FORM (plain / line / double with studs / double with rays) + a low colour glow, so it reads in black and white.
## Restraint rule: the grade colour is strong only on the focused card (focus 0..1); the others sink to a muted edge.
## Material: stone-grey face with speckle, a bevel (light top-left, dark bottom-right) and a metal inner line.
static func draw_face(ci: CanvasItem, rect: Rect2, grade: String, focus: float, leak: float = 0.0) -> void:
	var gc := grade_color(grade)
	var rank := grade_rank(grade)
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

static func draw_back(ci: CanvasItem, rect: Rect2, element: String, grade: String, leak: float) -> void:
	var col := el_color(element)
	var gc := grade_color(grade)
	quad(ci, rect, Color(0.07, 0.08, 0.1, 1), Color(0.03, 0.035, 0.045, 1))
	ci.draw_rect(rect, Palette.BRASS_DIM, false, 3.0)
	ci.draw_rect(rect.grow(-10), with_alpha(Palette.BRASS, 0.5), false, 1.5)
	var c := rect.get_center()
	var r := minf(rect.size.x, rect.size.y) * 0.3
	for i in 5: ci.draw_arc(c, r * (0.35 + 0.2 * i), 0, TAU, 48, with_alpha(col, 0.35 - 0.05 * i), 1.5, true)
	for i in 8:
		var a := float(i) * TAU / 8.0 + 0.2
		ci.draw_line(c + Vector2.from_angle(a) * r * 0.35, c + Vector2.from_angle(a) * r * 1.15, with_alpha(col, 0.35), 1.5, true)
	diamond(ci, c, r * 0.18, with_alpha(Palette.BRASS, 0.9))
	if leak > 0.0:
		for i in 9:
			ci.draw_rect(rect.grow(float(i) * 3.0), with_alpha(gc, 0.42 * leak * (1.0 - float(i) / 9.0)), false, 3.0)
		add_leak_seam(ci, rect, gc, leak)

static func add_leak_seam(ci: CanvasItem, rect: Rect2, gc: Color, leak: float) -> void:
	var cx := rect.get_center().x
	ci.draw_line(Vector2(cx, rect.position.y + 6), Vector2(cx, rect.end.y - 6), with_alpha(gc, 0.65 * leak), 3.0, true)
	ci.draw_line(Vector2(cx, rect.position.y + 6), Vector2(cx, rect.end.y - 6), with_alpha(Color.WHITE, 0.4 * leak), 1.0, true)

# ---- controls ----

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
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		kit.draw_emblem(ci, kind, element, size * 0.5, r, energy, phase, tone)

## The mother, as a code-drawn placeholder: a standing silhouette on a cloth-weave panel, head bent, brow in shadow, short horns,
## rim light on the side facing the cards. NEW ART NEEDED (the three mother paintings); this only holds the place and the pose rules.
class Mother extends Control:
	var element := "frost"
	var rim := 1.0:
		set(v):
			rim = v
			queue_redraw()
	func _init(e := "frost") -> void:
		element = e
		size = Vector2(430, 860)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		var col: Color = kit.el_color(element)
		var body := Color(0.115, 0.125, 0.155, 1)
		# cloth panel: soft columns, fades at both sides
		for i in 5:
			var x0 := size.x * float(i) / 5.0
			var a := 0.5 - absf(float(i) - 2.0) * 0.2
			draw_rect(Rect2(x0, 0, size.x / 5.0, size.y), Color(0.05, 0.055, 0.07, a * 0.8))
		for x in range(0, int(size.x), 8): draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.022), 1.0)
		for y in range(0, int(size.y), 8): draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.018), 1.0)
		var left_edge := [Vector2(206, 232), Vector2(150, 252), Vector2(126, 306), Vector2(136, 440), Vector2(112, 560), Vector2(70, 860)]
		var right_edge := [Vector2(226, 232), Vector2(282, 252), Vector2(304, 306), Vector2(294, 440), Vector2(318, 560), Vector2(362, 860)]
		var outline := PackedVector2Array()
		for p in left_edge: outline.append(p)
		for i in range(right_edge.size() - 1, -1, -1): outline.append(right_edge[i])
		draw_colored_polygon(outline, body)
		# head bent down toward the lower left, horns, brow in shadow (R4): eyes never visible
		draw_colored_polygon(PackedVector2Array([Vector2(186, 160), Vector2(168, 112), Vector2(202, 146)]), body)
		draw_colored_polygon(PackedVector2Array([Vector2(238, 154), Vector2(262, 108), Vector2(222, 146)]), body)
		var head := PackedVector2Array()
		for i in 28:
			var a := float(i) * TAU / 28.0
			head.append(Vector2(214, 188) + Vector2(cos(a) * 31, sin(a) * 40).rotated(-0.14))
		draw_colored_polygon(head, body)
		var jaw := PackedVector2Array([Vector2(194, 206), Vector2(204, 226), Vector2(226, 224), Vector2(236, 203), Vector2(216, 210)])
		draw_colored_polygon(jaw, Color(0.2, 0.18, 0.18, 0.82))
		draw_rect(Rect2(203, 228, 22, 12), body)
		match element:
			"ember":
				for y in [336, 372]:
					draw_colored_polygon(PackedVector2Array([Vector2(140, y), Vector2(288, y + 8), Vector2(288, y + 30), Vector2(140, y + 22)]), Color(0.06, 0.06, 0.075))
					for k in 5: draw_line(Vector2(160 + k * 24, y + 6 + (k % 2) * 6), Vector2(170 + k * 24, y + 20), with_alpha(col, 0.8), 2.0, true)
			"frost":
				draw_colored_polygon(PackedVector2Array([Vector2(206, 232), Vector2(152, 262), Vector2(132, 430), Vector2(296, 430), Vector2(280, 262), Vector2(226, 232)]), Color(0.07, 0.085, 0.105))
				for k in 12: draw_line(Vector2(134 + k * 14, 430), Vector2(134 + k * 14, 446 + (k % 3) * 8), Color(0.07, 0.085, 0.105), 4.0)
				for k in 14: draw_line(Vector2(96 + k * 17, 858), Vector2(100 + k * 17, 836 - (k % 4) * 6), with_alpha(col, 0.55), 2.0, true)
			_:
				for k in 5: draw_line(Vector2(206 + (k % 2) * 6 - 3, 232 - k * 0 + k * 0), Vector2(206 + (k % 2) * 6 - 3, 232), col, 0.0)
				var zig := PackedVector2Array([Vector2(204, 240), Vector2(212, 252), Vector2(204, 262), Vector2(214, 274), Vector2(208, 284)])
				draw_polyline(zig, with_alpha(col, 0.95), 2.5, true)
				for k in 26:
					var p := Vector2(60 + fmod(float(k) * 97.0, 320.0), 120 + fmod(float(k) * 61.0, 600.0))
					draw_circle(p, 2.0, with_alpha(col, 0.35))
		# rim light on the side facing the cards (right)
		var rim_line := PackedVector2Array()
		for p in right_edge: rim_line.append(p)
		draw_polyline(rim_line, with_alpha(col, 0.18 * rim), 12.0, true)
		draw_polyline(rim_line, with_alpha(col, 0.62 * rim), 3.0, true)
		draw_arc(Vector2(214, 188), 40.0, -0.9, 0.9, 12, with_alpha(col, 0.5 * rim), 2.0, true)
		# mist at the foot
		for i in 6:
			draw_circle(Vector2(60 + i * 62, 850), 90.0 - i * 4.0, Color(0.1, 0.12, 0.15, 0.10))
	func with_alpha(c: Color, a: float) -> Color:
		return Color(c.r, c.g, c.b, a)

# ---- shared card: vertical, big emblem ----

class VCard extends Control:
	signal clicked(i: int)
	signal hovered(i: int)
	var idx := 0
	var data := {}
	var style := "bound"  ## bound (A) or ornate (B)
	var focus := 0.0:
		set(v):
			focus = v
			queue_redraw()
	var leak := 0.0:
		set(v):
			leak = v
			queue_redraw()
	var sweep := -1.0:
		set(v):
			sweep = v
			queue_redraw()
	var face_up := true:
		set(v):
			face_up = v
			for ch in _front: ch.visible = v
			queue_redraw()
	var emblem: Control
	var knot := false
	var meter_rect := Rect2()
	var chip_rect := Rect2()
	var _front: Array = []
	var _emb_h := 0.0
	var show_stats := true
	var key_label := ""

	func build(card: Dictionary, i: int, w: float, h: float, emb_frac: float, ui: Dictionary, stats := false, ornate := false) -> void:
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		var Palette_ = kit.Palette
		idx = i
		data = card
		show_stats = stats
		style = "ornate" if ornate else "bound"
		size = Vector2(w, h)
		custom_minimum_size = size
		pivot_offset = size * 0.5
		mouse_filter = Control.MOUSE_FILTER_STOP
		_emb_h = h * emb_frac
		var pad := 18.0
		var inner := w - pad * 2.0
		var el: String = card.element
		var gc: Color = kit.grade_color(String(card.grade))
		emblem = kit.Emblem.new(String(card.emblem), el, Vector2(_emb_h - 34.0, _emb_h - 34.0), true)
		emblem.position = Vector2((w - emblem.size.x) * 0.5, 26.0)
		add_child(emblem)
		_front.append(emblem)
		var y := _emb_h + 4.0
		var header: Variant = card.get("header", null)
		if header != null and String(header) != "":
			var hl: Label = kit.lbl(self, String(header), Vector2(pad, y), inner, 14, kit.el_text(el), "bold", HORIZONTAL_ALIGNMENT_LEFT, false)
			_front.append(hl)
		y += 22.0
		var nl: Label = kit.lbl(self, String(card.name), Vector2(pad, y), inner, 28, Palette_.INK, "heading", HORIZONTAL_ALIGNMENT_LEFT, false)
		_front.append(nl)
		y += 46.0
		var kind_text := String(card.kind_label)
		if String(card.get("tier", "")) != "": kind_text += "  " + String(card.tier)
		var kl: Label = kit.lbl(self, kind_text, Vector2(pad, y), inner - 70.0, 15, kit.el_text(el), "bold", HORIZONTAL_ALIGNMENT_LEFT, false)
		_front.append(kl)
		chip_rect = Rect2(w - pad - 66.0, y + 2.0, 66.0, 20.0)
		var gl: Label = kit.lbl(self, String(card.grade_name), Vector2(chip_rect.position.x + 18.0 - 40.0, y), 88.0, 14, gc, "bold", HORIZONTAL_ALIGNMENT_RIGHT, false)
		_front.append(gl)
		y += 28.0
		var d: Variant = card.get("delta", null)
		if d is Dictionary:
			var dl: Label = kit.lbl(self, String(d.label), Vector2(pad, y), inner, 14, Palette_.INK_DIM, "body", HORIZONTAL_ALIGNMENT_LEFT, false)
			_front.append(dl)
			y += 20.0
			var vl: Label = kit.lbl(self, "%s → %s ▲" % [d.before, d.after], Vector2(pad, y), inner, 30, kit.GAIN, "number", HORIZONTAL_ALIGNMENT_LEFT, false)
			_front.append(vl)
			y += 42.0
			var m: Variant = card.get("meter", null)
			if m is Dictionary:
				meter_rect = Rect2(pad, y + 2.0, inner, 16.0)
				y += 22.0
		else:
			var hl2: Label = kit.lbl(self, String(card.get("line", card.headline)), Vector2(pad, y), inner, 16, Palette_.INK, "body")
			_front.append(hl2)
			y += hl2.size.y + 6.0
		if show_stats and card.stats.size() > 0:
			var room := h - 54.0 - y
			var txt := String(card.stats[0])
			var need: float = kit.measure(txt, 15, inner).y
			if need <= room:
				var sl: Label = kit.lbl(self, txt, Vector2(pad, y), inner, 15, Palette_.INK_DIM, "body")
				_front.append(sl)
		var al: Label = kit.lbl(self, String(card.action), Vector2(pad, h - 40.0), inner, 15, Palette_.INK_DIM, "bold", HORIZONTAL_ALIGNMENT_CENTER, false)
		al.name = "Action"
		_front.append(al)
		if key_label != "":
			pass
		var kl2: Label = kit.lbl(self, str(i + 1), Vector2(w - 40.0, 16.0), 24, 16, Palette_.INK, "number", HORIZONTAL_ALIGNMENT_CENTER, false)
		kl2.name = "Key"
		_front.append(kl2)
		gui_input.connect(_on_gui_input)
		mouse_entered.connect(func(): hovered.emit(idx))

	## One call sets the whole reaction of a card: focus 0..1 -> frame light, colour of the emblem, a small lift (no scale above 1.03).
	func set_focus_amount(f: float) -> void:
		focus = f
		if emblem != null: emblem.set("tone", 0.3 + 0.7 * f)
		modulate = Color(0.7, 0.7, 0.72, 1.0).lerp(Color.WHITE, f)
		scale = Vector2.ONE * (1.0 + 0.03 * f)

	func _on_gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: clicked.emit(idx)

	func _draw() -> void:
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		var rect := Rect2(Vector2.ZERO, size)
		if not face_up:
			kit.draw_back(self, rect, String(data.element), String(data.grade), leak)
			return
		kit.draw_face(self, rect, String(data.grade), focus, leak)
		var gc: Color = kit.grade_color(String(data.grade))
		var rank: int = kit.grade_rank(String(data.grade))
		# glow behind the emblem: the grade colour fills the wide area
		# element badge (shape) + number tag
		kit.draw_badge(self, String(data.element), Vector2(30, 32), 10.0, kit.el_color(String(data.element)))
		draw_circle(Vector2(size.x - 28.0, 28.0), 15.0, Color(0.02, 0.025, 0.03, 0.8))
		draw_arc(Vector2(size.x - 28.0, 28.0), 15.0, 0, TAU, 24, kit.Palette.BRASS, 1.5, true)
		# grade chip: a small diamond count = rank (shape, not just colour)
		kit.diamond(self, Vector2(chip_rect.position.x + 6.0, chip_rect.position.y + 10.0), 5.0 + float(rank), gc, rank >= 1, 2.0)
		if meter_rect.size.x > 0.0:
			var m: Dictionary = data.meter
			var f := int(m.filled)
			var t := int(m.total)
			var font: Font = kit.Loc.font("body")
			draw_string(font, meter_rect.position + Vector2(0, 13), String(m.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, kit.Palette.INK_DIM)
			for k in t:
				var p := meter_rect.position + Vector2(60.0 + k * 22.0, 8.0)
				if k < f: draw_circle(p, 6.0, kit.el_color(String(data.element)))
				else: draw_arc(p, 6.0, 0, TAU, 14, kit.Palette.INK_FAINT, 1.5, true)
		if knot:
			var kc := Vector2(0, _emb_h + 10.0)
			draw_circle(kc, 9.0, kit.Palette.LINEN)
			draw_arc(kc, 9.0, 0, TAU, 16, Color(0.1, 0.09, 0.07), 2.0, true)
			draw_line(kc + Vector2(-5, -5), kc + Vector2(5, 5), Color(0.1, 0.09, 0.07), 2.0)
			draw_line(kc + Vector2(-5, 5), kc + Vector2(5, -5), Color(0.1, 0.09, 0.07), 2.0)
		if sweep >= 0.0 and sweep <= 1.0:
			var x := -60.0 + (size.x + 120.0) * sweep
			draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + 46, 0), Vector2(x - 24, size.y), Vector2(x - 70, size.y)]), Color(1, 1, 1, 0.16))

# ---- the row of what the witch already owns ----

class OwnedRow extends Control:
	var owned := {}
	var ui := {}
	var chip := 46.0
	var centres := {"spell": [], "grace": []}
	var lit: Array = []
	var lit_amount := 0.0:
		set(v):
			lit_amount = v
			queue_redraw()
	var pulse := 0.0:
		set(v):
			pulse = v
			queue_redraw()
	func build(o: Dictionary, strings: Dictionary, chip_size := 46.0) -> void:
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		owned = o
		ui = strings
		chip = chip_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var x := 0.0
		var lb: Label = kit.lbl(self, String(ui.owned), Vector2(x, chip * 0.5 - 11.0), 110.0, 15, kit.Palette.INK_DIM, "bold", HORIZONTAL_ALIGNMENT_LEFT, false)
		x += lb.size.x
		x = 112.0
		centres.spell = []
		var spells: Array = o.spells
		for i in int(o.slots):
			var c := Vector2(x + chip * 0.5, chip * 0.5)
			centres.spell.append(c)
			if i < spells.size():
				var em: Control = kit.Emblem.new(String(spells[i].emblem), String(spells[i].element), Vector2(chip, chip))
				em.position = Vector2(x, 0)
				add_child(em)
				var lv: Label = kit.lbl(self, String(spells[i].level), Vector2(x + chip - 10.0, chip - 18.0), 20, 14, kit.Palette.INK, "number", HORIZONTAL_ALIGNMENT_CENTER, false)
				lv.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
				lv.add_theme_constant_override("shadow_offset_x", 1)
				lv.add_theme_constant_override("shadow_offset_y", 1)
			x += chip + 10.0
		x += 18.0
		var gl: Label = kit.lbl(self, String(ui.graces), Vector2(x, chip * 0.5 - 11.0), 52.0, 15, kit.Palette.INK_DIM, "bold", HORIZONTAL_ALIGNMENT_LEFT, false)
		x += 56.0
		centres.grace = []
		for i in int(o.grace_slots):
			centres.grace.append(Vector2(x + chip * 0.35, chip * 0.5))
			x += chip * 0.7 + 8.0
		size = Vector2(x, chip)
		queue_redraw()
	## Spell slots that pair with a card: the combo's other end (not the card's own emblem) when the witch already owns it.
	func link_slots(card: Dictionary) -> Array:
		var out: Array = []
		for cb in card.combo:
			for end in ["from", "to"]:
				var k := String(cb[end])
				var e := String(cb[end + "_element"])
				if k == String(card.emblem) and e == String(card.element): continue
				for i in owned.spells.size():
					if String(owned.spells[i].emblem) == k and String(owned.spells[i].element) == e and not i in out: out.append(i)
		return out
	func slot_centre(kind: String, index: int) -> Vector2:
		var arr: Array = centres[kind]
		if arr.is_empty(): return size * 0.5
		return arr[clampi(index, 0, arr.size() - 1)]
	## Where a chosen card lands: a new spell takes the first free slot, an upgrade goes to its own chip, a grace to the grace row.
	func target_for(card: Dictionary) -> Vector2:
		if String(card.kind) == "prep":
			var gi := 0
			for g in owned.graces:
				if bool(g.owned): gi += 1
			return global_position + slot_centre("grace", gi)
		if String(card.kind) in ["new", "trade"]:
			return global_position + slot_centre("spell", owned.spells.size())
		var si := 0
		for i in owned.spells.size():
			if String(owned.spells[i].name) == String(card.name) or String(owned.spells[i].element) == String(card.element) and i == 0: si = i
		return global_position + slot_centre("spell", si)
	func _draw() -> void:
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		var spells: Array = owned.get("spells", [])
		for i in centres.spell.size():
			var c: Vector2 = centres.spell[i]
			draw_circle(c, chip * 0.54, Color(0.02, 0.022, 0.026, 0.95))
			draw_arc(c, chip * 0.54, 0, TAU, 32, Color(0.45, 0.4, 0.3, 0.95), 3.0, true)
			draw_arc(c, chip * 0.54 - 3.0, PI * 0.9, PI * 1.9, 16, Color(0, 0, 0, 0.7), 2.0, true)
			draw_arc(c, chip * 0.54 + 1.5, -PI * 0.1, PI * 0.9, 16, Color(1, 1, 1, 0.12), 1.5, true)
			if i >= spells.size():
				draw_string(kit.Loc.font("number"), c + Vector2(-5, 6), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, kit.with_alpha(kit.Palette.BRASS, 0.5))
			if i in lit and lit_amount > 0.0:
				draw_arc(c, chip * 0.64, 0, TAU, 32, kit.with_alpha(kit.Palette.BRASS_HI, 0.9 * lit_amount), 2.5, true)
		var graces: Array = owned.get("graces", [])
		for i in centres.grace.size():
			var c2: Vector2 = centres.grace[i]
			var have: bool = i < graces.size() and bool(graces[i].owned)
			draw_circle(c2, chip * 0.3, Color(0.02, 0.022, 0.026, 0.95))
			draw_arc(c2, chip * 0.3, 0, TAU, 20, Color(0.45, 0.4, 0.3, 0.95), 2.0, true)
			if have: kit.diamond(self, c2, chip * 0.2, kit.Palette.GROWTH)
		if pulse > 0.0:
			var tgt: Vector2 = centres.spell[mini(spells.size(), centres.spell.size() - 1)] if not centres.spell.is_empty() else Vector2.ZERO
			draw_arc(tgt, chip * (0.5 + 0.6 * (1.0 - pulse)), 0, TAU, 32, kit.with_alpha(kit.Palette.BRASS_HI, pulse), 3.0, true)

## A reroll handle: key tag + label + remaining count. A real control (mouse), nothing is decided here.
class Handle extends Control:
	signal pressed
	var enabled := true
	var hot := 0.0:
		set(v):
			hot = v
			queue_redraw()
	func build(key: String, text: String, count: String, w := 220.0, h := 46.0) -> void:
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		size = Vector2(w, h)
		mouse_filter = Control.MOUSE_FILTER_STOP
		kit.lbl(self, key, Vector2(10, h * 0.5 - 11.0), 24, 15, kit.Palette.INK, "number", HORIZONTAL_ALIGNMENT_CENTER, false)
		kit.lbl(self, text, Vector2(46, h * 0.5 - 12.0), w - 46.0 - 56.0, 17, kit.Palette.INK, "bold", HORIZONTAL_ALIGNMENT_LEFT, false)
		kit.lbl(self, count, Vector2(w - 44.0, h * 0.5 - 14.0), 32, 20, kit.Palette.GROWTH, "number", HORIZONTAL_ALIGNMENT_CENTER, false)
		gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: pressed.emit())
		mouse_entered.connect(func(): hot = 1.0)
		mouse_exited.connect(func(): hot = 0.0)
	func _draw() -> void:
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		var r := Rect2(Vector2.ZERO, size)
		kit.quad(self, r, Color(0.12, 0.14, 0.15, 0.92), Color(0.06, 0.07, 0.08, 0.92))
		draw_rect(r, kit.with_alpha(kit.Palette.BRASS, 0.8 + 0.2 * hot), false, 2.0)
		draw_rect(Rect2(8, size.y * 0.5 - 13, 28, 26), kit.with_alpha(kit.Palette.BRASS_DIM, 0.9), false, 1.5)
		draw_circle(Vector2(size.x - 28, size.y * 0.5), 15.0, Color(0.02, 0.025, 0.03, 0.8))
		draw_arc(Vector2(size.x - 28, size.y * 0.5), 15.0, 0, TAU, 20, kit.with_alpha(kit.Palette.GROWTH, 0.8), 1.5, true)

# ---- effects ----

## Ash-like shards flying away from a rect (the cards that were not chosen).
static func shards(host: Control, rect: Rect2, color: Color, count: int, life: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(rect.position.x) + 17
	for i in count:
		var s := ColorRect.new()
		var sz := rng.randf_range(4.0, 11.0)
		s.size = Vector2(sz, sz * rng.randf_range(0.5, 1.2))
		s.color = Color(color.r, color.g, color.b, rng.randf_range(0.6, 1.0))
		s.position = rect.position + Vector2(rng.randf() * rect.size.x, rng.randf() * rect.size.y)
		s.rotation = rng.randf() * TAU
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(s)
		var tw := host.create_tween().set_parallel(true)
		var to := s.position + Vector2(rng.randf_range(-50, 50), rng.randf_range(40, 130))
		tw.tween_property(s, "position", to, life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(s, "modulate:a", 0.0, life)
		tw.tween_property(s, "rotation", s.rotation + rng.randf_range(-2.5, 2.5), life)
		tw.chain().tween_callback(s.queue_free)
