extends RefCounted
## Shared parts of the two title / character-select proposals (tests only; nothing in chapter1/view imports this).
## Reads the shared base (palette.gd, loc.gd, ui_style.gd, living_portrait.gd public calls) and never writes to it.
## Every word on screen comes from the fixture (title_v0.*.json); this file holds no Korean text.
## Units: the screens are laid out in 1080p PIXELS (the numbers of docs/screens/title/BRIEF-20261120.ko.md) and converted to the
## 1600x900 code canvas with K = 1/1.2 (px()), so a number in the brief is the number here.
## Common-base candidates found while building (listed in REPORT.txt): far_texture (blurred far backdrop from a layer image),
## the iris / rise closers, Burst (a placeholder for the vfx-feel bursts), StartButton, Marker (focus brackets).
const Kit = preload("res://chapter1/tests/proposals/growth_choice/kit.gd")
const Palette = preload("res://chapter1/view/hud/palette.gd")
const Loc = preload("res://chapter1/view/loc.gd")
const UiStyle = preload("res://chapter1/view/hud/ui_style.gd")
const Portrait = preload("res://chapter1/view/hud/living_portrait/living_portrait.gd")

const K := 1.0 / 1.2
const IDS := ["ember", "frost", "storm"]
const ELEM := ["ember", "frost", "arc"]
## Anchor points in the 1024x1536 paintings the game's layers came from (BRIEF 0.2). SYMBOL = where the element's emblem effect sits.
const FACE := [Vector2(559, 130), Vector2(478, 120), Vector2(525, 150)]  ## from the L4_head layers' drawn boxes (the brief's eyeballed values were 160/140/255 high)
const PELVIS := [Vector2(540, 560), Vector2(470, 620), Vector2(540, 600)]
const SYMBOL := [Vector2(150, 450), Vector2(800, 120), Vector2(535, 385)]
const FOOT_Y := 1500.0
const CANVAS := Vector2(1024, 1536)

static var _far := {}
static var _glow_add: CanvasItemMaterial

# ---------------------------------------------------------------- numbers

static func px(v: float) -> float:
	return v * K

static func fs(px_size: float) -> int:
	return maxi(1, int(round(px_size * K)))

static func smooth(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func ease_out(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)

static func ramp(t: float, a: float, b: float) -> float:
	return clampf((t - a) / maxf(b - a, 0.0001), 0.0, 1.0)

static func read_json(path: String) -> Dictionary:
	return Kit.read_json(path)

static func el_color(i: int) -> Color:
	return Kit.el_color(ELEM[i])

static func el_text(i: int) -> Color:
	return Kit.el_text(ELEM[i])

static func additive() -> CanvasItemMaterial:
	if _glow_add == null:
		_glow_add = CanvasItemMaterial.new()
		_glow_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _glow_add

# ---------------------------------------------------------------- backdrops

## The witch's own L0 background layer (figure painted out), shrunk to a few dozen pixels and stretched back = a soft far backdrop.
## `sat` pulls colour toward grey. A small picture scaled up with linear filtering is the cheap blur (BRIEF 3.1).
static func far_texture(witch: int, small_w: int, sat: float) -> ImageTexture:
	var key := "%d_%d_%.2f" % [witch, small_w, sat]
	if _far.has(key):
		return _far[key]
	var path := ProjectSettings.globalize_path("res://chapter1/art/portraits/%s/layers/L0_background.png" % String(IDS[witch]))
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		img = Image.create(8, 12, false, Image.FORMAT_RGB8)
		img.fill(Color(0.1, 0.1, 0.12))
		push_warning("title proposal: no L0_background for " + String(IDS[witch]))
	img.convert(Image.FORMAT_RGB8)
	img.resize(256, 384, Image.INTERPOLATE_LANCZOS)
	img.resize(small_w, int(round(small_w * 1.5)), Image.INTERPOLATE_BILINEAR)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var l := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
			img.set_pixel(x, y, Color(l, l, l).lerp(c, sat))
	var tex := ImageTexture.create_from_image(img)
	_far[key] = tex
	return tex

static var _edge_shader: Shader

## The far picture drawn AGAIN over the near (sharp) layer, transparent inside [x0, x1] and fading out over `f` pixels at both
## ends: the sharp layer melts into the soft one without a seam. All numbers are in this control's own code units.
static func edge_cover_material(x0: float, x1: float, f: float, w: float) -> ShaderMaterial:
	if _edge_shader == null:
		_edge_shader = Shader.new()
		_edge_shader.code = "shader_type canvas_item;\nuniform float x0 = 0.0;\nuniform float x1 = 100.0;\nuniform float f = 10.0;\nuniform float w = 100.0;\nvoid fragment(){ vec4 c = texture(TEXTURE, UV); float u = UV.x * w; float inside = smoothstep(x0, x0 + f, u) * (1.0 - smoothstep(x1 - f, x1, u)); COLOR = vec4(c.rgb, c.a * (1.0 - inside)); }\n"
	var m := ShaderMaterial.new()
	m.shader = _edge_shader
	set_edge(m, x0, x1, f, w)
	return m

static var _feather_t: Shader

## Like Kit.feather_material but keeps the node's modulate (the kit one overwrites COLOR, so modulate and alpha had no effect).
static func feather_tinted(fx: float, fb: float, ft: float) -> ShaderMaterial:
	if _feather_t == null:
		_feather_t = Shader.new()
		_feather_t.code = "shader_type canvas_item;\nuniform float fx = 0.15;\nuniform float fb = 0.3;\nuniform float ft = 0.0;\nvoid fragment(){ vec4 c = texture(TEXTURE, UV) * COLOR; float ax = smoothstep(0.0, fx, UV.x) * smoothstep(0.0, fx, 1.0 - UV.x); float ab = smoothstep(0.0, max(fb, 0.001), 1.0 - UV.y); float at = ft > 0.0 ? smoothstep(0.0, ft, UV.y) : 1.0; COLOR = vec4(c.rgb, c.a * ax * ab * at); }\n"
	var m := ShaderMaterial.new()
	m.shader = _feather_t
	m.set_shader_parameter("fx", fx)
	m.set_shader_parameter("fb", fb)
	m.set_shader_parameter("ft", ft)
	return m

static func set_edge(m: ShaderMaterial, x0: float, x1: float, f: float, w: float) -> void:
	m.set_shader_parameter("x0", x0)
	m.set_shader_parameter("x1", x1)
	m.set_shader_parameter("f", f)
	m.set_shader_parameter("w", maxf(w, 1.0))

## A TextureRect stretched over exactly `rect` (cover: the picture is scaled to cover and centred; the caller clips).
static func cover_rect(tex_size: Vector2, area: Vector2) -> Rect2:
	var s := maxf(area.x / tex_size.x, area.y / tex_size.y)
	var sz := tex_size * s
	return Rect2((area - sz) * 0.5, sz)

static func hgrad(parent: Node, rect: Rect2, c0: Color, c1: Color) -> TextureRect:
	var g := Gradient.new()
	g.colors = PackedColorArray([c0, c1])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	gt.width = 128
	gt.height = 4
	var t := TextureRect.new()
	t.texture = gt
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.position = rect.position
	t.size = rect.size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t

static func vgrad(parent: Node, rect: Rect2, c0: Color, c1: Color) -> TextureRect:
	var t := hgrad(parent, rect, c0, c1)
	(t.texture as GradientTexture2D).fill_to = Vector2(0, 1)
	(t.texture as GradientTexture2D).width = 4
	(t.texture as GradientTexture2D).height = 128
	return t

## Horizontal band that is transparent at both ends and `c` in the middle (the seam shade between doors, the light sweep).
static func hband(parent: Node, rect: Rect2, c: Color, add := false) -> TextureRect:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(c.r, c.g, c.b, 0.0), c, Color(c.r, c.g, c.b, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	gt.width = 128
	gt.height = 4
	var t := TextureRect.new()
	t.texture = gt
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.position = rect.position
	t.size = rect.size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if add:
		t.material = additive()
	parent.add_child(t)
	return t

static func rect_node(parent: Node, rect: Rect2, c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = rect.position
	r.size = rect.size
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r

# ---------------------------------------------------------------- text

static func fit_px(text: String, role: String, width_px: float, max_px: float, min_px: float) -> float:
	var p := max_px
	while p > min_px and Loc.font(role).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs(p)).x > px(width_px):
		p -= 2.0
	return p

static func text_w(text: String, role: String, px_size: float) -> float:
	return Loc.font(role).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs(px_size)).x

static func fmt(template: String, vars: Dictionary) -> String:
	var out := template
	for k in vars:
		out = out.replace("{%s}" % String(k), str(vars[k]))
	return out

# ---------------------------------------------------------------- small controls

class SkillIcon extends Control:
	var element := "frost"
	func setup(el: String, s: float) -> void:
		element = el
		size = Vector2(s, s)
		custom_minimum_size = size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		kit.draw_badge(self, element, size * 0.5, size.x * 0.33, kit.el_color(element))

## Diamond + number: the points the witch can still spend. Shape first, colour second.
class PointsTag extends Control:
	var amount := 0
	var color := Color.WHITE
	var px_size := 22
	var label: Label
	func setup(n: int, c: Color, font_px: int) -> void:
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		amount = n
		color = c
		px_size = font_px
		var h: float = kit.line_height(font_px, "number")
		var d := float(font_px) * 0.72
		label = kit.lbl(self, str(n), Vector2(d + 4.0, 0), 80.0, font_px, c, "number", HORIZONTAL_ALIGNMENT_LEFT, false)
		var wlab: float = kit.Loc.font("number").get_string_size(str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
		label.size.x = ceilf(wlab) + 2.0
		size = Vector2(d + 4.0 + ceilf(wlab) + 2.0, h)
		custom_minimum_size = size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		var d := float(px_size) * 0.36
		kit.diamond(self, Vector2(d, size.y * 0.52), d, color)

## Brass brackets around whatever has the keyboard focus (BRASS_HI is for this and nothing else).
class Marker extends Control:
	var target: Control
	var pad := 4.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = 20
	func follow(t: Control) -> void:
		target = t
		visible = t != null and t.is_inside_tree()
		if visible:
			var r := t.get_global_rect()
			position = r.position - Vector2(pad, pad)
			size = r.size + Vector2(pad, pad) * 2.0
			queue_redraw()
	func _draw() -> void:
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		var c: Color = kit.Palette.BRASS_HI
		var l := minf(size.y * 0.45, 12.0)
		for corner in [[Vector2(0, 0), 1.0, 1.0], [Vector2(size.x, 0), -1.0, 1.0], [Vector2(0, size.y), 1.0, -1.0], [Vector2(size.x, size.y), -1.0, -1.0]]:
			var p: Vector2 = corner[0]
			draw_line(p, p + Vector2(l * float(corner[1]), 0), c, 2.0)
			draw_line(p, p + Vector2(0, l * float(corner[2])), c, 2.0)

# ---------------------------------------------------------------- effects

## Placeholder burst (vfx-feel owns the real ones). One class draws all three; t = seconds since the burst began, c = centre (code units).
class Burst extends Control:
	var element := "ember"
	var t := -1.0:
		set(v):
			t = v
			visible = v >= 0.0 and v < 1.1
			queue_redraw()
	var center := Vector2.ZERO
	var unit := 1.0   ## scale of the effect
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false
		z_index = 12
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = add
	func _draw() -> void:
		if t < 0.0:
			return
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		var col: Color = kit.el_color(element)
		var u := unit
		var life := clampf(t / 0.8, 0.0, 1.0)
		var fade := 1.0 - life
		match element:
			"ember":
				for k in 3:
					var r := (60.0 + 70.0 * float(k)) * u * (1.0 - pow(1.0 - clampf(t / (0.45 + 0.1 * k), 0.0, 1.0), 3.0))
					draw_arc(center, r, 0, TAU, 64, Color(col.r, col.g, col.b, 0.9 * fade), 10.0 - 2.5 * float(k), true)
				for k in 16:
					var a := float(k) * TAU / 16.0 + 0.2 * float(k % 3)
					var len_ := (80.0 + 50.0 * float(k % 4)) * u * (1.0 - pow(1.0 - clampf(t / 0.5, 0.0, 1.0), 2.0))
					var d := Vector2.from_angle(a)
					var n := Vector2(-d.y, d.x)
					draw_colored_polygon(PackedVector2Array([center + d * 20.0 * u + n * 9.0 * u, center + d * (20.0 * u + len_), center + d * 20.0 * u - n * 9.0 * u]),
						Color(1.0, 0.55 + 0.04 * float(k % 5), 0.2, 0.85 * fade))
			"frost":
				var grow := clampf(t / 0.25, 0.0, 1.0)
				if t < 0.28:
					var rr := (30.0 + 90.0 * grow) * u
					draw_circle(center, rr, Color(col.r, col.g, col.b, 0.55))
					for k in 6:
						var a2 := float(k) * PI / 3.0
						draw_line(center - Vector2.from_angle(a2) * rr * 1.25, center + Vector2.from_angle(a2) * rr * 1.25, Color(1, 1, 1, 0.9), 4.0, true)
				else:
					var sp := clampf((t - 0.28) / 0.6, 0.0, 1.0)
					for k in 22:
						var a3 := float(k) * TAU / 22.0 + 0.3 * float(k % 5)
						var d3 := Vector2.from_angle(a3)
						var dist := (50.0 + 260.0 * (0.5 + 0.5 * float(k % 4) / 3.0)) * u * (1.0 - pow(1.0 - sp, 3.0))
						var c3 := center + d3 * dist
						var n3 := Vector2(-d3.y, d3.x)
						draw_colored_polygon(PackedVector2Array([c3 + d3 * 22.0 * u, c3 + n3 * 7.0 * u, c3 - d3 * 10.0 * u, c3 - n3 * 7.0 * u]), Color(col.r, col.g, col.b, 0.9 * (1.0 - sp)))
					draw_arc(center, 150.0 * u * sp + 20.0, 0, TAU, 64, Color(col.r, col.g, col.b, 0.7 * (1.0 - sp)), 6.0, true)
			_:
				var rng := RandomNumberGenerator.new()
				rng.seed = 11
				var grow2 := clampf(t / 0.25, 0.0, 1.0)
				var offs := [-2.2, -1.0, 1.0, 2.2]
				for k in 4:
					var x0 := center.x + float(offs[k]) * 60.0 * u   ## strikes land beside the face, never across it
					var pts := PackedVector2Array()
					var steps := 9
					for s in steps + 1:
						var f := float(s) / float(steps)
						var yy := lerpf(-20.0, center.y, f * grow2)
						var jig := rng.randf_range(-12.0, 12.0) * u * (1.0 - f * 0.3)
						pts.append(Vector2(x0 + jig, yy))
					draw_polyline(pts, Color(col.r, col.g, col.b, 0.9 * fade), (6.0 - 1.0 * float(k % 2)) * u, true)
					draw_polyline(pts, Color(1, 1, 1, 0.9 * fade), 1.6 * u, true)
				draw_arc(center, 220.0 * u * ease_out_s(t / 0.5), 0, TAU, 64, Color(col.r, col.g, col.b, 0.8 * fade), 4.0, true)
	static func ease_out_s(x: float) -> float:
		var tt := clampf(x, 0.0, 1.0)
		return 1.0 - pow(1.0 - tt, 3.0)

## The closing iris of the A proposal: black from the edges inwards (amount 0 open .. 1 shut).
class Iris extends Control:
	var amount := 0.0:
		set(v):
			amount = v
			visible = v > 0.0
			queue_redraw()
	var tex: GradientTexture2D
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false
		z_index = 30
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 1)])
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		tex = GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 256
		tex.height = 256
	func _draw() -> void:
		var c := size * 0.5
		var s := lerpf(2.6, 0.05, amount * amount) * maxf(size.x, size.y)
		var r := Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s))
		draw_texture_rect(tex, r, false)
		var black := Color(0, 0, 0, 1)
		draw_rect(Rect2(0, 0, size.x, maxf(r.position.y, 0.0)), black)
		draw_rect(Rect2(0, minf(r.end.y, size.y), size.x, maxf(size.y - r.end.y, 0.0)), black)
		draw_rect(Rect2(0, maxf(r.position.y, 0.0), maxf(r.position.x, 0.0), minf(r.end.y, size.y) - maxf(r.position.y, 0.0)), black)
		draw_rect(Rect2(minf(r.end.x, size.x), maxf(r.position.y, 0.0), maxf(size.x - r.end.x, 0.0), minf(r.end.y, size.y) - maxf(r.position.y, 0.0)), black)
		if amount > 0.85:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, clampf((amount - 0.85) / 0.15, 0.0, 1.0)))

## The closing of the C proposal: darkness rising from the bottom (the intro of the portrait, played backwards).
class Rise extends Control:
	var amount := 0.0:
		set(v):
			amount = v
			visible = v > 0.0
			queue_redraw()
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false
		z_index = 30
	func _draw() -> void:
		var soft := size.y * 0.35
		var y0 := lerpf(size.y, -soft, amount)
		var steps := 96
		for k in steps:
			var f0 := float(k) / float(steps)
			var f1 := float(k + 1) / float(steps)
			draw_rect(Rect2(0, y0 + soft * f0, size.x, soft * (f1 - f0) + 1.0), Color(0, 0, 0, f1))
		if y0 + soft < size.y:
			draw_rect(Rect2(0, y0 + soft, size.x, size.y - y0 - soft), Color(0, 0, 0, 1))

# ---------------------------------------------------------------- the contract demon (placeholder only)

## Placeholder of the contract demon. figure: a crop of a draft painting read from _local/art/drafts at run time (NOT copied into the
## repository; head to waist; feathered; dark; only the eyes get a colour). hand: a code-drawn bony hand coming down (the frost one:
## the draft has no figure). Caption: strings.placeholder_art. `amount` = brightness 0..1 of the whole thing.
class Devil extends Control:
	var kind := "figure"
	var element := "ember"
	var shade := false
	var pic: TextureRect
	var glows: Array = []
	var caption: Label
	var amount := 0.0:
		set(v):
			amount = v
			modulate = Color(1, 1, 1, v)
			visible = v > 0.003
	var hand_drop := 0.0:
		set(v):
			hand_drop = v
			queue_redraw()
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false
	func build(def: Dictionary, el: String, area: Vector2, face_shade: bool, note: String, eyes: Array) -> void:
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		element = el
		kind = String(def.get("kind", "figure"))
		shade = face_shade
		size = area
		if kind == "figure":
			var path: String = kit.find_local(String(def.get("image", "")))
			var tex: Texture2D = null
			if path != "":
				tex = kit.image_texture(path, Rect2i(0, 0, 1024, int(1024.0 * area.y / area.x)))
			if tex != null:
				pic = TextureRect.new()
				pic.texture = tex
				pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				pic.stretch_mode = TextureRect.STRETCH_SCALE
				pic.size = area
				pic.modulate = Color(0.4, 0.4, 0.44, 1.0)
				pic.material = load("res://chapter1/tests/proposals/title/parts.gd").feather_tinted(0.22, 0.38, 0.12)
				pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
				add_child(pic)
			if shade:
				var sh: Control = load("res://chapter1/tests/proposals/title/parts.gd").vgrad(self, Rect2(0, 0, area.x, area.y * 0.62), Color(0.01, 0.012, 0.02, 0.97), Color(0.01, 0.012, 0.02, 0.0))
				sh.name = "FaceShade"
			for e in eyes:
				var g: TextureRect = kit.add_glow(self, Vector2(float(e[0]), float(e[1])) * (area.x / 1024.0), area.x * 0.022, kit.el_color(el), true)
				glows.append(g)
		caption = kit.lbl(self, note, Vector2(area.x * 0.5 - 60.0, area.y - 26.0), 120.0, 14, kit.Palette.INK_FAINT, "body", HORIZONTAL_ALIGNMENT_CENTER, false)
	func _draw() -> void:
		if kind != "hand":
			return
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		var col: Color = kit.el_color(element)
		var dark := Color(0.30, 0.34, 0.40, 1.0)
		var top := -size.y * 0.1 + hand_drop
		var palm := Vector2(size.x * 0.55, top)
		for f in 5:
			var a := PI * (0.56 + 0.035 * float(f))
			var dir := Vector2(cos(a), sin(a))
			var side := Vector2(-dir.y, dir.x)
			var len_ := size.y * (0.95 + 0.07 * (2.0 - absf(float(f) - 2.0)))
			var p := palm + side * (float(f) - 2.0) * 22.0
			var pts := PackedVector2Array()
			var joints := 4
			for j in joints + 1:
				var fr := float(j) / float(joints)
				pts.append(p + dir * len_ * fr + side * sin(fr * 3.0 + float(f)) * 6.0)
			draw_polyline(pts, dark, 14.0 - 2.0 * float(f % 2), true)
			draw_polyline(pts, Color(0.5, 0.56, 0.62, 0.6), 2.0, true)
			var tip: Vector2 = pts[pts.size() - 1]
			draw_circle(tip, 5.0, Color(col.r, col.g, col.b, 0.9))
			for k in 3:
				draw_line(tip + Vector2((float(k) - 1.0) * 5.0, 0), Vector2(tip.x + (float(k) - 1.0) * 5.0, size.y * 1.2), Color(col.r, col.g, col.b, 0.18), 1.0)

## Portrait factory: one living portrait per witch (seed 7 + n, set before select_witch), still until it is given motion.
static func make_portrait(i: int) -> Node2D:
	var p: Node2D = Portrait.new()
	p.call("set_seed", 7 + i)
	p.call("select_witch", String(IDS[i]))
	p.call("set_motion_scale", 0.0)
	p.call("set_flags", {"fx": false})
	return p

## Rectangle (code units) that puts original pixel (anchor) of the painting at `at`, at `s` code units per original pixel.
static func portrait_rect(s: float, anchor: Vector2, at: Vector2) -> Rect2:
	var size := CANVAS * s
	# set_rect centres on zoom_center: origin = rect.centre - anchor * s, so rect.centre = at puts `anchor` at `at`
	return Rect2(at - size * 0.5, size)
