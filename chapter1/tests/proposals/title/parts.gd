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
const FACE := [Vector2(565, 160), Vector2(440, 140), Vector2(505, 255)]
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

## Clickable text (action row, corners). `focus_key` is what the keyboard row calls it.
class ActionItem extends Control:
	signal pressed
	var label: Label
	var tag: Control
	var hot := false
	var base_color := Color.WHITE
	func setup(text: String, font_px: int, color: Color, points: int, points_color: Color, role := "body") -> void:
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		base_color = color
		label = kit.lbl(self, text, Vector2.ZERO, 400.0, font_px, color, role, HORIZONTAL_ALIGNMENT_LEFT, false)
		var wt: float = kit.Loc.font(role).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
		label.size.x = ceilf(wt) + 2.0
		var w := ceilf(wt) + 2.0
		if points > 0:
			tag = load("res://chapter1/tests/proposals/title/parts.gd").PointsTag.new()
			tag.setup(points, points_color, font_px)
			tag.position = Vector2(w + 6.0, 0)
			add_child(tag)
			w += 6.0 + tag.size.x
		size = Vector2(w, label.size.y)
		custom_minimum_size = size
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func(): _set_hot(true))
		mouse_exited.connect(func(): _set_hot(false))
		gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				pressed.emit())
	func _set_hot(v: bool) -> void:
		hot = v
		label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82) if v else base_color)
		queue_redraw()
	func _draw() -> void:
		if hot:
			draw_line(Vector2(0, size.y - 1.0), Vector2(size.x, size.y - 1.0), Color(1.0, 0.82, 0.48, 0.8), 1.5)

## The one main button. Face from ui_style (button_face), a thin element line at the foot, brass brackets only when focused.
class StartButton extends Control:
	signal pressed
	var text := ""
	var px_size := 30
	var element := "frost"
	var hot := false
	var flash := 0.0:
		set(v):
			flash = v
			queue_redraw()
	func setup(label_text: String, s: Vector2, font_px: int, el: String) -> void:
		text = label_text
		size = s
		custom_minimum_size = s
		px_size = font_px
		element = el
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
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		var style_lib = load("res://chapter1/view/hud/ui_style.gd")
		var face: StyleBox = style_lib.button_face("hover" if hot else "normal")
		draw_style_box(face, Rect2(Vector2.ZERO, size))
		var col: Color = kit.el_color(element)
		draw_rect(Rect2(8, size.y - 7.0, size.x - 16.0, 2.0), Color(col.r, col.g, col.b, 0.85))
		var f: Font = kit.Loc.font("heading")
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px_size).x
		var base := Vector2((size.x - w) * 0.5, size.y * 0.5 + (f.get_ascent(px_size) - f.get_descent(px_size)) * 0.5)
		draw_string_outline(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px_size, 3, Color(0, 0, 0, 0.8))
		draw_string(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px_size, kit.Palette.INK)
		var dm := float(px_size) * 0.28
		kit.diamond(self, Vector2(base.x - float(px_size) * 0.8, size.y * 0.5), dm, col)
		kit.diamond(self, Vector2(base.x + w + float(px_size) * 0.8, size.y * 0.5), dm, col)
		if flash > 0.0:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.4 * flash))

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

# ---------------------------------------------------------------- the text block of one witch

## Builds the text bundle of one witch into a root Control (BRIEF 3.1 order: title, one line, traits, start skill, level row, button,
## action row). spec: width, title/line/traits/skill/level/button/action (px sizes), button_h, title_min, summary (bool), actions
## ("row" | "column"), gaps (6 numbers). Returns {root, start, tree, stash, costume, height, title_px, skill_row}. Heights are code units.
static func build_block(i: int, w: Dictionary, ui: Dictionary, profile: Dictionary, spec: Dictionary) -> Dictionary:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var width: float = px(float(spec.width))
	var el: String = String(w.element)
	var gaps: Array = spec.get("gaps", [10, 12, 14, 16, 18, 22])
	var y := 0.0
	var out := {"root": root, "start": null, "tree": null, "stash": null, "costume": null}
	# title (fits on one line down to title_min px, then wraps)
	var title := String(w.title)
	var tpx := fit_px(title, "heading", float(spec.width), float(spec.title), float(spec.get("title_min", spec.title)))
	var tl: Label = Kit.lbl(root, title, Vector2(0, y), width, fs(tpx), el_text(i), "heading", HORIZONTAL_ALIGNMENT_LEFT, true, true)
	tl.name = "Title"
	y += tl.size.y + px(float(gaps[0]))
	out["title_px"] = tpx
	# the one line (placeholder when empty)
	var line := String(w.get("line", ""))
	if line.strip_edges() == "":
		line = String(ui.line_pending)
	var ll: Label = Kit.lbl(root, line, Vector2(0, y), width, fs(float(spec.line)), Palette.INK, "body")
	ll.name = "Line"
	y += ll.size.y + px(float(gaps[1]))
	# traits
	var tr: Label = Kit.lbl(root, " · ".join(PackedStringArray(w.traits)), Vector2(0, y), width, fs(float(spec.traits)), Palette.INK_DIM, "body")
	tr.name = "Traits"
	y += tr.size.y + px(float(gaps[2]))
	# start skill: icon + name (+ summary)
	var sk := Control.new()
	sk.name = "StartSkill"
	sk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(sk)
	var icon_px := px(float(spec.skill_icon))
	var icon := SkillIcon.new()
	icon.setup(el, icon_px)
	sk.add_child(icon)
	var nm: Label = Kit.lbl(sk, String(w.skill_name), Vector2(icon_px + px(12.0), 0), width - icon_px - px(12.0), fs(float(spec.skill)), el_text(i), "bold", HORIZONTAL_ALIGNMENT_LEFT, true)
	var sk_h := maxf(icon_px, nm.size.y)
	if bool(spec.get("summary", false)):
		var sm: Label = Kit.lbl(sk, String(w.skill_summary), Vector2(icon_px + px(12.0), nm.size.y), width - icon_px - px(12.0), fs(float(spec.get("summary_px", 18))), Palette.INK_DIM, "body")
		sk_h = maxf(icon_px, nm.size.y + sm.size.y)
	icon.position.y = (sk_h - icon_px) * 0.5 if not bool(spec.get("summary", false)) else 0.0
	nm.position.y = (sk_h - nm.size.y) * 0.5 if not bool(spec.get("summary", false)) else 0.0
	sk.position = Vector2(0, y)
	sk.size = Vector2(width, sk_h)
	y += sk_h + px(float(gaps[3]))
	out["skill_row"] = sk
	# level row (only when the profile is on and the witch has growth)
	var growth: Variant = w.get("growth", null)
	if growth is Dictionary and bool(profile.get("enabled", true)):
		var lv := Control.new()
		lv.name = "LevelRow"
		lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(lv)
		var lpx := fs(float(spec.level))
		var ltxt := "%s %d" % [String(ui.level), int(growth.level)]
		var lh := Kit.line_height(lpx, "number")
		var lw := Kit.Loc.font("number").get_string_size(ltxt, HORIZONTAL_ALIGNMENT_LEFT, -1, lpx).x
		var lb: Label = Kit.lbl(lv, ltxt, Vector2.ZERO, ceilf(lw) + 2.0, lpx, Palette.INK, "number", HORIZONTAL_ALIGNMENT_LEFT, false)
		var pts := int(growth.points_free)
		var ptag_w := 0.0
		if pts > 0:
			var pt := PointsTag.new()
			pt.setup(pts, Palette.GROWTH, lpx)
			pt.position = Vector2(width - pt.size.x, 0)
			pt.name = "Points"
			lv.add_child(pt)
			ptag_w = pt.size.x + px(12.0)
		var bx := lb.size.x + px(14.0)
		var bw := maxf(width - bx - ptag_w, px(40.0))
		var span := maxf(float(growth.xp_for_next) - float(growth.xp_level_start), 1.0)
		var frac := clampf((float(growth.xp) - float(growth.xp_level_start)) / span, 0.0, 1.0)
		var by := lh * 0.5 - px(3.0)
		rect_node(lv, Rect2(bx, by, bw, px(6.0)), Color(1, 1, 1, 0.14))
		rect_node(lv, Rect2(bx, by, bw * frac, px(6.0)), el_color(i))
		lv.position = Vector2(0, y)
		lv.size = Vector2(width, lh)
		y += lh + px(float(gaps[4]))
	# start button (A puts it before the actions, C after: spec.button_first)
	var actions_h := 0.0
	var action_root: Control = null
	if bool(profile.get("enabled", true)):
		action_root = Control.new()
		action_root.name = "Actions"
		action_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var apx := fs(float(spec.action))
		var items: Array = []
		var tree_n := 0
		if growth is Dictionary:
			tree_n = int(growth.points_free)
			var it_tree := ActionItem.new()
			it_tree.setup(String(ui.tree), apx, Palette.INK_DIM, tree_n, Palette.GROWTH)
			items.append(it_tree)
			out["tree"] = it_tree
		var it_stash := ActionItem.new()
		it_stash.setup(fmt(String(ui.stash_n), {"n": int(profile.get("stash_count", 0))}), apx, Palette.INK_DIM, 0, Palette.GROWTH)
		items.append(it_stash)
		out["stash"] = it_stash
		var costume: Variant = w.get("costume", null)
		if costume is Dictionary:
			var it_cos := ActionItem.new()
			it_cos.setup(fmt(String(ui.costume_n), {"a": int(costume.owned), "b": int(costume.total)}), apx, Palette.INK_DIM, 0, Palette.GROWTH)
			items.append(it_cos)
			out["costume"] = it_cos
		var column: bool = String(spec.get("actions", "row")) == "column"
		var row_h := Kit.line_height(apx, "body")
		if column:
			var step := px(float(spec.get("action_step", 52)))
			for k in items.size():
				var it: Control = items[k]
				it.position = Vector2(0, step * float(k) + (step - row_h) * 0.5)
				action_root.add_child(it)
			actions_h = step * float(items.size())
		else:
			var sep := px(14.0)
			var total := 0.0
			for it2 in items:
				total += (it2 as Control).size.x
			total += sep * 2.0 * float(maxi(items.size() - 1, 0)) + Kit.Loc.font("body").get_string_size("·", HORIZONTAL_ALIGNMENT_LEFT, -1, apx).x * float(maxi(items.size() - 1, 0))
			var fits := total <= width
			var x := 0.0
			var ry := 0.0
			for k in items.size():
				var it3: Control = items[k]
				if not fits and k == 1:
					x = 0.0
					ry += row_h + px(6.0)
				if k > 0 and (fits or k > 1):
					var dot: Label = Kit.lbl(action_root, "·", Vector2(x + sep * 0.5, ry), 12.0, apx, Palette.INK_FAINT, "body", HORIZONTAL_ALIGNMENT_LEFT, false)
					x += sep + dot.size.x * 0.0 + Kit.Loc.font("body").get_string_size("·", HORIZONTAL_ALIGNMENT_LEFT, -1, apx).x + sep
				it3.position = Vector2(x, ry)
				action_root.add_child(it3)
				x += it3.size.x
			actions_h = ry + row_h
		action_root.size = Vector2(width, actions_h)
	var button := StartButton.new()
	button.name = "Start"
	button.setup(String(ui.start), Vector2(width, px(float(spec.button_h))), fs(float(spec.button)), el)
	out["start"] = button
	var button_first: bool = bool(spec.get("button_first", true))
	if button_first:
		button.position = Vector2(0, y)
		root.add_child(button)
		y += button.size.y + px(float(gaps[5]))
		if action_root != null:
			action_root.position = Vector2(0, y)
			root.add_child(action_root)
			y += actions_h
	else:
		if action_root != null:
			action_root.position = Vector2(0, y)
			root.add_child(action_root)
			y += actions_h + px(float(gaps[5]))
		button.position = Vector2(0, y)
		root.add_child(button)
		y += button.size.y
	root.size = Vector2(width, y)
	out["height"] = y
	return out

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
				for k in 3:
					var x0 := center.x + (float(k) - 1.0) * 70.0 * u
					var pts := PackedVector2Array()
					var steps := 9
					for s in steps + 1:
						var f := float(s) / float(steps)
						var yy := lerpf(-20.0, center.y, f * grow2)
						var jig := rng.randf_range(-26.0, 26.0) * u * (1.0 - f * 0.4)
						pts.append(Vector2(lerpf(center.x + (x0 - center.x) * 2.0, center.x, f) + jig, yy))
					draw_polyline(pts, Color(col.r, col.g, col.b, 0.9 * fade), (14.0 - 3.0 * float(k)) * u, true)
					draw_polyline(pts, Color(1, 1, 1, 0.9 * fade), 3.0 * u, true)
				draw_arc(center, 220.0 * u * ease_out_s(t / 0.5), 0, TAU, 64, Color(col.r, col.g, col.b, 0.8 * fade), 8.0, true)
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
		var steps := 24
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
				pic.modulate = Color(0.34, 0.33, 0.36, 1.0)
				pic.material = kit.feather_material(0.22, 0.38, 0.12)
				pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
				add_child(pic)
			if shade:
				var sh: Control = load("res://chapter1/tests/proposals/title/parts.gd").vgrad(self, Rect2(0, 0, area.x, area.y * 0.62), Color(0.01, 0.012, 0.02, 0.97), Color(0.01, 0.012, 0.02, 0.0))
				sh.name = "FaceShade"
			for e in eyes:
				var g: TextureRect = kit.add_glow(self, Vector2(float(e[0]) * area.x, float(e[1]) * area.y), area.x * 0.04, kit.el_color(el), true)
				glows.append(g)
		caption = kit.lbl(self, note, Vector2(area.x * 0.5 - 60.0, area.y - 26.0), 120.0, 14, kit.Palette.INK_FAINT, "body", HORIZONTAL_ALIGNMENT_CENTER, false)
	func _draw() -> void:
		if kind != "hand":
			return
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		var col: Color = kit.el_color(element)
		var dark := Color(0.2, 0.22, 0.26, 1.0)
		var top := -size.y * 0.1 + hand_drop
		var palm := Vector2(size.x * 0.55, top)
		for f in 5:
			var a := PI * (0.58 + 0.07 * float(f))
			var dir := Vector2(cos(a), sin(a))
			var side := Vector2(-dir.y, dir.x)
			var len_ := size.y * (0.55 + 0.1 * (2.0 - absf(float(f) - 2.0)))
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
