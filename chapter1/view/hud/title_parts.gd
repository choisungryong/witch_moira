extends RefCounted
## Parts of the first screen (screens/title.gd, "three doors"): far backdrop, door-edge cover shader, the closers (Iris, Rise), the placeholder burst,
## the focus brackets, the points tag, the skill mark, and the portrait factory. Moved from the proposal parts (git f3fbd3c / 4c76e72) into the product.
## Reads palette.gd, loc.gd, grace_draw.gd and the public calls of living_portrait.gd; writes to none of them. Holds no Korean text.
## Units: the screen is laid out in 1080p PIXELS (the numbers of docs/screens/title/BRIEF-20261120.ko.md) and converted to the 1600x900 code canvas
## with K = 1/1.2 (px()), so a number in the brief is the number here.
## Not here on purpose: the contract demon of the proposal (director decision, T13: nothing of it on the confirm beat this time).
const Kit = preload("res://chapter1/view/hud/grace_draw.gd")
const Palette = preload("res://chapter1/view/hud/palette.gd")
const Loc = preload("res://chapter1/view/loc.gd")
const Portrait = preload("res://chapter1/view/hud/living_portrait/living_portrait.gd")

const K := 1.0 / 1.2
const IDS := ["ember", "frost", "storm"]
const ELEM := ["ember", "frost", "arc"]
## Anchor points in the 1024x1536 paintings the portrait layers came from (BRIEF 0.2). SYMBOL = where the element's emblem effect sits.
const FACE := [Vector2(559, 130), Vector2(478, 120), Vector2(525, 150)]  ## from the L4_head layers' drawn boxes
const PELVIS := [Vector2(540, 560), Vector2(470, 620), Vector2(540, 600)]
const SYMBOL := [Vector2(150, 450), Vector2(800, 120), Vector2(535, 385)]
const FOOT_Y := 1500.0
const CANVAS := Vector2(1024, 1536)

const BACKDROP := Color(0.01, 0.012, 0.016, 1.0)   ## the black under the doors
const DOOR_GRAY := Color(0.2, 0.21, 0.23, 1.0)     ## the cool grey laid over a door that is not in focus (alpha is set by the caller)

static var _far := {}
static var _glow_add: CanvasItemMaterial

# ---------------------------------------------------------------- colours (the screen file holds no colour literal)

static func grey(v: float, a := 1.0) -> Color:
	return Color(v, v, v, a)

static func black(a: float) -> Color:
	return Color(0.0, 0.0, 0.0, a)

## The colour with its red, green and blue multiplied by k and alpha 1 (for an additive layer: k is its strength).
static func scaled(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, 1.0)

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
## The picture comes from the portrait's public static background_image(), so no file path is named here.
static func far_texture(witch: int, small_w: int, sat: float) -> ImageTexture:
	var key := "%d_%d_%.2f" % [witch, small_w, sat]
	if _far.has(key):
		return _far[key]
	var img: Image = Portrait.background_image(String(IDS[witch]))
	if img == null or img.is_empty():
		img = Image.create(8, 12, false, Image.FORMAT_RGB8)
		img.fill(Color(0.1, 0.1, 0.12))
		push_warning("title: no far background for " + String(IDS[witch]))
	if img.is_compressed():
		img.decompress()
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

## A soft-edged picture that keeps its node's modulate (fx: feather at the left and right ends, fb: at the bottom, ft: at the top; all as fractions of the size).
static func feather_tinted(fx: float, fb: float, ft: float) -> ShaderMaterial:
	if _feather_t == null:
		_feather_t = Shader.new()
		_feather_t.code = "shader_type canvas_item;
uniform float fx = 0.15;
uniform float fb = 0.3;
uniform float ft = 0.0;
void fragment(){ vec4 c = texture(TEXTURE, UV) * COLOR; float ax = smoothstep(0.0, fx, UV.x) * smoothstep(0.0, fx, 1.0 - UV.x); float ab = smoothstep(0.0, max(fb, 0.001), 1.0 - UV.y); float at = ft > 0.0 ? smoothstep(0.0, ft, UV.y) : 1.0; COLOR = vec4(c.rgb, c.a * ax * ab * at); }
"
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

## The scale-to-cover rectangle: the picture is scaled to cover `area` and centred; the caller clips.
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

## Horizontal band that is transparent at both ends and `c` in the middle (the seam shade between doors).
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

# ---------------------------------------------------------------- small controls

## The skill's element mark: a different SHAPE per element (flame / snow-star / bolt).
class SkillIcon extends Control:
	var element := "frost"
	func setup(el: String, s: float) -> void:
		element = el
		size = Vector2(s, s)
		custom_minimum_size = size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		Kit.draw_badge(self, element, size * 0.5, size.x * 0.33, Kit.el_color(element))

## Diamond + number: the points the witch can still spend. Shape first, colour second.
class PointsTag extends Control:
	var amount := 0
	var color := Color.WHITE
	var px_size := 22
	var label: Label
	func setup(n: int, c: Color, font_px: int) -> void:
		amount = n
		color = c
		px_size = font_px
		var h: float = Kit.line_height(font_px, "number")
		var d := float(font_px) * 0.72
		label = Kit.lbl(self, str(n), Vector2(d + 4.0, 0), 80.0, font_px, c, "number", HORIZONTAL_ALIGNMENT_LEFT, false)
		var wlab: float = Loc.font("number").get_string_size(str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
		label.size.x = ceilf(wlab) + 2.0
		size = Vector2(d + 4.0 + ceilf(wlab) + 2.0, h)
		custom_minimum_size = size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var d := float(px_size) * 0.36
		Kit.diamond(self, Vector2(d, size.y * 0.52), d, color)

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
		var c: Color = Palette.BRASS_HI
		var l := minf(size.y * 0.45, 12.0)
		for corner in [[Vector2(0, 0), 1.0, 1.0], [Vector2(size.x, 0), -1.0, 1.0], [Vector2(0, size.y), 1.0, -1.0], [Vector2(size.x, size.y), -1.0, -1.0]]:
			var p: Vector2 = corner[0]
			draw_line(p, p + Vector2(l * float(corner[1]), 0), c, 2.0)
			draw_line(p, p + Vector2(0, l * float(corner[2])), c, 2.0)

## The small "menu" button at the top right (the mouse way to Esc). A plate with the word; the brass edge lights up under the pointer.
class CornerMenuButton extends Control:
	signal pressed
	var text := ""
	var hot := false
	func setup(label_text: String, s: Vector2) -> void:
		text = label_text
		size = s
		custom_minimum_size = s
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func():
			hot = true
			queue_redraw())
		mouse_exited.connect(func():
			hot = false
			queue_redraw())
		gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				pressed.emit())
	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(Palette.SURFACE.r, Palette.SURFACE.g, Palette.SURFACE.b, 0.86)
		box.border_color = Palette.BRASS_HI if hot else Palette.BRASS_DIM
		box.set_border_width_all(2)
		box.set_corner_radius_all(6)
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		var f: Font = Loc.font("bold")
		var fsz := 15
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
		var base := Vector2((size.x - w) * 0.5, size.y * 0.5 + (f.get_ascent(fsz) - f.get_descent(fsz)) * 0.5)
		draw_string(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Palette.INK)

# ---------------------------------------------------------------- effects

## Placeholder burst (vfx-feel owns the real ones: "the element's own burst"). One class draws all three; t = seconds since the burst began, c = centre (code units).
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
		var col: Color = Kit.el_color(element)
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

## The closing iris: black from the edges inwards (amount 0 open .. 1 shut).
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

## The entrance darkness over a whole door: darkness rising from the bottom (the portrait's own intro, played backwards). amount 1 = all dark .. 0 = lifted.
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

## Portrait factory: one living portrait per witch (seed 7 + n, set before select_witch), still until it is given motion. Its own entrance veil is off:
## the screen darkens the whole door itself (Rise), so the veil never shows a hard-edged box.
static func make_portrait(i: int) -> Node2D:
	var p: Node2D = Portrait.new()
	p.call("set_seed", 7 + i)
	p.call("set_veil", false)
	p.call("select_witch", String(IDS[i]))
	p.call("set_motion_scale", 0.0)
	p.call("set_flags", {"fx": false})
	return p

## Rectangle (code units) that puts original pixel (anchor) of the painting at `at`, at `s` code units per original pixel.
static func portrait_rect(s: float, _anchor: Vector2, at: Vector2) -> Rect2:
	var size := CANVAS * s
	# set_rect centres on zoom_center: origin = rect.centre - anchor * s, so rect.centre = at puts `anchor` at `at`
	return Rect2(at - size * 0.5, size)
