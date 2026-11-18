extends RefCounted
## The one place that builds frames, plates, buttons, labels, bars and focus marks for the HUD (A4 US).
## Screens ask for a kind (window, plate, button state, notice, ...) and never assemble a StyleBox themselves.
## Colours come from palette.gd tokens only. Decorative pieces for custom-drawn controls come from one atlas
## (hud_atlas.png, drawn with `blit`), nine-slice frames from the 1x textures next to it.
const Palette = preload("res://chapter1/view/hud/palette.gd")

const LEGACY := 0
const BOUND_CODEX := 1
## The switch. LEGACY builds exactly the flat frames the HUD had before US; BOUND_CODEX builds the leather and brass kit.
const THEME := BOUND_CODEX

const KIT := "res://chapter1/art/ui/kit/"
## Pieces of hud_atlas.png: [x, y, w, h] in texture pixels (2x of code size). Written by chapter1/art/ui/kit/build_kit.py.
const ATLAS := {"orb_frame":[8,8,448,448],
	"orb_empty":[464,8,300,300],
	"glass_highlight":[772,8,300,300],
	"liquid_life":[1080,8,300,300],
	"liquid_ember":[1388,8,300,300],
	"liquid_frost":[1696,8,300,300],
	"liquid_arc":[8,464,300,300],
	"notice_card":[316,464,640,247],
	"slot_normal":[964,464,192,192],
	"slot_selected":[1164,464,192,192],
	"slot_cooldown":[1364,464,192,192],
	"medal_cross":[1564,464,184,184],
	"zone_tag":[8,772,800,169],
	"boss_frame":[8,949,1320,141],
	"cooldown_shade":[1336,949,132,132],
	"icon_dash":[1476,949,132,132],
	"icon_ultimate":[1616,949,132,132],
	"icon_fire":[1756,949,132,131],
	"icon_frost":[1896,949,132,131],
	"icon_potion":[8,1098,132,131],
	"icon_arc":[148,1098,132,130],
	"strip_left":[288,1098,300,124],
	"strip_right":[596,1098,300,124],
	"strip_tile":[904,1098,560,124],
	"btn_bag":[1472,1098,108,110],
	"btn_book":[1588,1098,108,110],
	"btn_speaker":[1704,1098,108,110],
	"boss_name":[8,1237,500,107],
	"level_badge":[516,1237,84,88],
	"key_tag":[608,1237,148,45],
	"surface_life":[764,1237,300,36],
	"surface_ember":[1072,1237,300,36],
	"surface_frost":[1380,1237,300,36],
	"surface_arc":[1688,1237,300,36],
	"bead_brass":[1996,1237,30,30],
	"bead_gold":[8,1352,30,30],
	"bead_empty":[46,1352,30,30]}
## Kit pixels to code units: the kit is authored at 2 px per 1080p px and 1080p is 1.2 x the 1600x900 code size.
const CODE := 1.0/2.4
const AtlasBox = preload("res://chapter1/view/hud/atlas_box.gd")

static var _atlas: Texture2D
static var _textures: Dictionary = {}
const Loc = preload("res://chapter1/view/loc.gd")

static func bound() -> bool:
	return THEME == BOUND_CODEX

static func atlas() -> Texture2D:
	if _atlas == null: _atlas = load(KIT + "hud_atlas.png")
	return _atlas

static func texture(file: String) -> Texture2D:
	if not _textures.has(file): _textures[file] = load(KIT + file)
	return _textures[file]

## Draws one atlas piece into `rect` of a custom-drawn control. The control should use LINEAR_WITH_MIPMAPS filtering.
static func blit(item: CanvasItem, piece: String, rect: Rect2, tint: Color = Color.WHITE) -> void:
	var r: Array = ATLAS[piece]
	item.draw_texture_rect_region(atlas(), rect, Rect2(r[0], r[1], r[2], r[3]), tint)

## Size of a piece in code units.
static func piece_size(piece: String) -> Vector2:
	var r: Array = ATLAS[piece]
	return Vector2(r[2], r[3]) * CODE

## A piece centred on a point, at its own code size times `scale_`.
static func blit_centered(item: CanvasItem, piece: String, centre: Vector2, scale_: float = 1.0, tint: Color = Color.WHITE) -> void:
	var size := piece_size(piece) * scale_
	blit(item, piece, Rect2(centre - size * .5, size), tint)

## The left `part` (0..1) of a piece into `rect` (for the last, shorter tile of a strip).
static func blit_part(item: CanvasItem, piece: String, rect: Rect2, part: float) -> void:
	var r: Array = ATLAS[piece]
	item.draw_texture_rect_region(atlas(), rect, Rect2(r[0], r[1], r[2] * part, r[3]))

static var _liquid_shader: Shader
## Orb liquid, from kit pieces only. Layers: empty glass (tinted by the liquid colour), the full liquid picture cut at the
## surface (the cut is the front edge of the surface ellipse), the surface band, a small crescent reflection.
## The kit's highlight and the frame are drawn by the bar over this. The surface only bobs by about a pixel.
static func liquid_shader() -> Shader:
	if _liquid_shader == null:
		_liquid_shader = Shader.new()
		_liquid_shader.code = """shader_type canvas_item;
uniform sampler2D atlas : filter_linear_mipmap;
uniform vec2 atlas_size = vec2(2048.0, 1392.0);
uniform vec4 r_empty;
uniform vec4 r_liquid;
uniform vec4 r_surface;
uniform vec4 tint = vec4(0.8, 0.3, 0.35, 1.0);
uniform float fill = 0.5;
vec4 piece(vec4 r, vec2 q) {
	return texture(atlas, (r.xy + clamp(q, vec2(0.003), vec2(0.997)) * r.zw) / atlas_size);
}
void fragment() {
	vec2 q = UV;
	float rr = length(q - 0.5) / 0.5;
	vec4 e = piece(r_empty, q);
	vec3 col = mix(vec3(0.03, 0.035, 0.04), e.rgb, e.a) * 0.35 + tint.rgb * 0.25;
	float f = fill * 0.88;
	vec4 liq = piece(r_liquid, q);
	float ys = 1.0 - f + 0.0033 * sin(TIME * 1.8);
	float a = sqrt(max(0.25 - (ys - 0.5) * (ys - 0.5), 0.000001));
	float b = 0.06 * a / 0.5;
	float dx = (q.x - 0.5) / a;
	float cut_y = abs(q.x - 0.5) <= a ? ys + b * sqrt(clamp(1.0 - dx * dx, 0.0, 1.0)) : ys;
	float seen = clamp((q.y - cut_y) * 214.0 + 0.5, 0.0, 1.0) * step(0.005, f);
	float shade = (1.0 - 0.60 * pow(clamp((rr - 0.30) / 0.70, 0.0, 1.0), 1.3)) * (1.0 - 0.10 * clamp((q.y - 0.5) * 2.0, 0.0, 1.0));
	col = mix(col, liq.rgb * 0.95 * shade, seen * liq.a);
	vec2 sq = vec2((q.x - (0.5 - a)) / (2.0 * a), (q.y - (ys - b)) / (2.0 * b));
	vec4 band = piece(r_surface, sq);
	float inside = step(0.0, sq.x) * step(sq.x, 1.0) * step(0.0, sq.y) * step(sq.y, 1.0) * step(0.005, f) * (1.0 - step(0.985, f)) * step(0.02, a);
	col = mix(col, band.rgb, band.a * inside);
	float cres = clamp(1.0 - length(q - 0.5 + vec2(0.26, 0.27)) / 0.09, 0.0, 1.0) * step(0.085, length(q - 0.5 + vec2(0.22, 0.23)));
	col = mix(col, vec3(1.0), clamp(cres * 2.5, 0.0, 1.0) * 0.8);
	COLOR = vec4(min(col, vec3(1.0)), 1.0 - smoothstep(0.985, 1.0, rr));
}"""
	return _liquid_shader

## Sets one orb's material: which colour pieces, fill 0..1 and the tint of the empty glass.
static func set_liquid(material: ShaderMaterial, key: String, fill: float, tint: Color) -> void:
	if material.get_meta("kit_key", "") != key:
		material.set_meta("kit_key", key)
		material.set_shader_parameter("atlas", atlas())
		material.set_shader_parameter("atlas_size", atlas().get_size())
		var e: Array = ATLAS["orb_empty"]
		material.set_shader_parameter("r_empty", Vector4(e[0], e[1], e[2], e[3]))
		var l: Array = ATLAS["liquid_" + key]
		material.set_shader_parameter("r_liquid", Vector4(l[0], l[1], l[2], l[3]))
		var sf: Array = ATLAS["surface_" + key]
		material.set_shader_parameter("r_surface", Vector4(sf[0], sf[1], sf[2], sf[3]))
	material.set_shader_parameter("fill", fill)
	material.set_shader_parameter("tint", tint)

## Fixed-width digits (Pretendard, tnum). Was an italic system serif; no italic file is bundled, so upright.
static func number_font() -> Font:
	return Loc.font("number")

# ---- Flat frames (also the base of every legacy look) ----

## Plain bordered surface: list rows, rarity cards, bar parts. Warm inherited surfaces are normalised to the panel colour.
static func flat(color: Color, border: Color = Palette.BRASS) -> StyleBoxFlat:
	var surface := color
	if color.r > color.b * 1.12 and color.r < 0.34: surface = Palette.SURFACE
	var s := StyleBoxFlat.new()
	s.bg_color = surface; s.border_color = border; s.set_border_width_all(1)
	s.set_content_margin_all(20)
	s.border_width_top = 2
	s.shadow_color = Color(0, 0, 0, .45); s.shadow_size = 8; s.shadow_offset = Vector2(0, 4)
	return s

static func _nine(file: String, margin: int, content: Array) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = texture(file)
	s.texture_margin_left = margin; s.texture_margin_right = margin; s.texture_margin_top = margin; s.texture_margin_bottom = margin
	s.content_margin_left = content[0]; s.content_margin_top = content[1]; s.content_margin_right = content[2]; s.content_margin_bottom = content[3]
	s.draw_center = true
	return s

# ---- Kinds ----

## Big window: menu, modals, confirm windows (K1).
static func window() -> StyleBox:
	if bound(): return _nine("window_96.png", 40, [44, 44, 44, 44])
	return flat(Palette.SURFACE, Palette.BRASS)

## Small plate: place and time, route, vital texts (K2s).
static func plate() -> StyleBox:
	if bound(): return _nine("panel_small_48.png", 16, [14, 10, 14, 10])
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(.025, .038, .045, .88)
	frame.border_color = Color(.44, .40, .30, .8); frame.border_width_bottom = 1
	frame.content_margin_left = 12; frame.content_margin_right = 12
	frame.content_margin_top = 9; frame.content_margin_bottom = 9
	return frame

## Plate that carries a brass edge in the combat chrome (goal and route plates).
static func chrome_plate(base: StyleBox) -> StyleBox:
	if bound(): return base
	var brass_frame: StyleBoxFlat = base.duplicate()
	brass_frame.border_color = Palette.BRASS; brass_frame.set_border_width_all(1); brass_frame.border_width_top = 2
	return brass_frame

## Notice card (first-gear and better-gear notices). `edge` is the grade colour.
static func notice(edge: Color) -> StyleBox:
	if bound():
		var s := AtlasBox.new()
		s.piece = "notice_card"; s.margins_px = Vector4(70, 70, 70, 70); s.line_color = edge
		s.content_margin_left = 30; s.content_margin_right = 26; s.content_margin_top = 24; s.content_margin_bottom = 20
		return s
	var frame := flat(Color(.055, .06, .065, .97), edge); frame.set_content_margin_all(14)
	return frame

## Zone and time tag in the top left corner (belt buckle at its left end). Content margins leave the buckle free.
static func zone_plate(base: StyleBox) -> StyleBox:
	if not bound(): return chrome_plate(base)
	var s := AtlasBox.new()
	s.piece = "zone_tag"; s.margins_px = Vector4(300, 40, 160, 40)
	s.content_margin_left = 84; s.content_margin_right = 44; s.content_margin_top = 16; s.content_margin_bottom = 16
	return s

## Dark leather backing behind the route text (top right), so the names read on any ground.
static func route_back() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.036, 0.034, .62)
	s.set_corner_radius_all(10)
	s.border_color = Color(Palette.BRASS_DIM, .55); s.set_border_width_all(1)
	s.content_margin_top = 22.0; s.content_margin_bottom = 8.0; s.content_margin_left = 12.0; s.content_margin_right = 12.0
	return s

## Round icon button of the top right row: the icon is baked into the piece.
static func icon_button(b: Button, piece: String, label: String) -> void:
	var key := label.get_slice("[", 1).get_slice("]", 0)
	b.text = ""; b.tooltip_text = label; b.icon = null
	if not key.is_empty(): b.draw.connect(draw_key_tag.bind(b, key))
	b.custom_minimum_size = piece_size(piece)
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	for state in ["normal", "hover", "pressed", "disabled"]:
		var s := AtlasBox.new()
		s.piece = piece; s.margins_px = Vector4(54, 55, 54, 55)
		s.tint = Color.WHITE if state == "normal" else (Color(1.18, 1.1, .9) if state == "hover" else Color(.7, .7, .7))
		b.add_theme_stylebox_override(state, s)

## A card or list surface inside a window.
static func card(color: Color, edge: Color) -> StyleBox:
	return flat(color, edge)

## Button face for one state: normal, hover, pressed, disabled (K3).
static func button_face(state: String) -> StyleBox:
	if bound():
		return _nine("button_%s_64x40.png" % state, 12, [14, 10, 14, 10])
	var entry: Array = {"normal":[Palette.SURFACE_RAISED, Palette.BRASS_DIM], "hover":[Color("303a3d"), Palette.BRASS],
		"pressed":[Color("111719"), Palette.INK], "disabled":[Color("191d1f"), Color("3e4343")]}[state]
	var s := flat(entry[0], entry[1]); s.set_content_margin_all(12)
	return s

## Selection mark: bright brass edge only (K16). Never a plain frame.
static func focus_mark() -> StyleBoxFlat:
	var focus := StyleBoxFlat.new(); focus.bg_color = Color(0, 0, 0, 0); focus.border_color = Palette.BRASS_HI; focus.set_border_width_all(3)
	return focus

static func button(text: String, action: Callable) -> Button:
	var b := Button.new(); b.text = text; b.custom_minimum_size.y = 48
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", Palette.INK)
	b.add_theme_color_override("font_disabled_color", Color("777a78"))
	for state in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(state, button_face(state))
	b.add_theme_stylebox_override("focus", focus_mark())
	b.pressed.connect(action)
	return b

## Same face with the smaller top and bottom margins of the compact buttons (top-right button row).
static func compact_button_faces(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var compact: StyleBox = b.get_theme_stylebox(state).duplicate()
		compact.content_margin_top = 7; compact.content_margin_bottom = 7
		b.add_theme_stylebox_override(state, compact)

static func heading_font() -> Font:
	return Loc.font("heading")

## Small key plate hung under a control (K "key tag"): drawn from the control's draw signal. `text` is the key name.
static func draw_key_tag(item: Control, text: String) -> void:
	var at := Vector2(item.size.x * .5, item.size.y + 12.0)
	blit_centered(item, "key_tag", at)
	var font := heading_font()
	item.draw_string_outline(font, at + Vector2(-30, 5), text, HORIZONTAL_ALIGNMENT_CENTER, 60, 14, 3, Color(0, 0, 0, .85))
	item.draw_string(font, at + Vector2(-30, 5), text, HORIZONTAL_ALIGNMENT_CENTER, 60, 14, Palette.INK)

static func label(text: String, size: int = 18, color: Color = Color("e0d8c7")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if size >= 25:
		l.add_theme_font_override("font", Loc.font("heading"))
	return l

## Progress bar with a flat fill and back (inherited bars: hp, xp).
static func bar(color: Color, height: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false; b.custom_minimum_size.y = height
	var fill := flat(color, color); fill.set_content_margin_all(0)
	var back := flat(Color("332a20"), Color("332a20")); back.set_content_margin_all(0)
	b.add_theme_stylebox_override("fill", fill)
	b.add_theme_stylebox_override("background", back)
	return b

## Champion bar parts (K10): the end caps are drawn by the HUD decor from the atlas.
static func boss_fill() -> StyleBoxFlat:
	var fill := StyleBoxFlat.new(); fill.bg_color = Palette.THREAT_DEEP
	fill.border_color = Palette.THREAT; fill.border_width_top = 2 if bound() else 1
	if bound():
		fill.border_color = Palette.THREAT.lightened(.35); fill.border_width_bottom = 3
		fill.bg_color = Palette.THREAT_DEEP.lightened(.12)
		fill.shadow_color = Color(0, 0, 0, .35); fill.shadow_size = 0
	return fill

static func boss_back() -> StyleBoxFlat:
	var back := StyleBoxFlat.new(); back.bg_color = Color(.03, .035, .04, .92)
	back.border_color = Palette.BRASS_DIM
	back.set_border_width_all(0 if bound() else 1); back.set_content_margin_all(0 if bound() else 1)
	return back

## Translucent pill behind a number that must read on any background.
static func pill() -> StyleBoxFlat:
	var p := StyleBoxFlat.new()
	p.bg_color = Color(0, 0, 0, .35)
	p.set_corner_radius_all(14)
	return p
