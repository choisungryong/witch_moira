extends RefCounted
## The shared picture parts of every screen (A10 2.3), lifted out of the grace screen (grace_parts.gd) without changing a pixel.
## Parts: TitlePlaque (+ title()), Candle (+ candle()), Knob (+ handles()), SideNote (+ note(); parchment), GradeFrame (grade ground + frame),
## Band (leather strip), Board (contract board, nine-sliced). Helpers: tex() / art_rect() / art_material() / glow_rect() / layer() / fit_size().
## Material rule: the hand of the combat HUD (black leather, gold stitching, brass). Pictures come from the asset slots (chapter1/art/asset_slots.json,
## T7): this file never names a picture file. The shared kit lives under `ui.kit.*` (the old `ui.grace.*` ids stay as the fall-back), the grade
## ids under `ui.grade.*`. A part whose picture is missing falls back to a piece of the HUD atlas, then to the code shapes of grace_draw.gd, and never fails.
## Presentation only: nothing here reads or writes the core.
##
## Who may use what (one line each, A10 W0):
##   TitlePlaque  every scene and window title                     Parts.title(parent, text, width, sub)
##   Candle       scene screens only (not windows or notices)      Parts.candle(parent, pos, height, flame_colour)
##   Knob         a round side action (reroll, filter, sort, log)  Parts.handles(parent, contract, pos)
##   SideNote     parchment reading panel (compare, node text)     Parts.note(parent, rect, contract), then .show_card(dict)
##   GradeFrame   anything with a grade (card, gear slot, notice)  Parts.GradeFrame.ground() / .frame(), or .new().build(key, size)
##   Band         leather strip (owned-spells band, band notice)   Parts.Band.paint(canvas_item, size, height)
##   Board        the window board (confirm, pause, record)        Parts.Board.new().build(size)
const Kit = preload("res://chapter1/view/hud/grace_draw.gd")
const AssetSlots = preload("res://chapter1/view/assets/asset_slots.gd")
const Palette = preload("res://chapter1/view/hud/palette.gd")
const UiStyle = preload("res://chapter1/view/hud/ui_style.gd")
const AtlasBox = preload("res://chapter1/view/hud/atlas_box.gd")
const Loc = preload("res://chapter1/view/loc.gd")
const PARTS_PATH := "res://chapter1/view/hud/ui_parts.gd"

# ============================================================ picture loading (asset slots)
static var _tex := {}        ## name -> Texture2D or null (looked up once)
static var _sh_normal: Shader
static var _sh_add: Shader

## The meaning ids a part name may come from, best first. The first one with a file wins.
##   "frame_rare" -> ui.grace.frame.rare, then ui.grade.frame.rare   (the grace screen's own picture first; the gear grades come after)
##   "title_plaque" -> ui.kit.title_plaque, then ui.grace.title_plaque
static func slot_ids(name_: String) -> Array:
	if name_.begins_with("frame_"): return ["ui.grace.frame." + name_.trim_prefix("frame_"), "ui.grade.frame." + name_.trim_prefix("frame_")]
	if name_.begins_with("bg_"): return ["ui.grace.ground." + name_.trim_prefix("bg_"), "ui.grade.ground." + name_.trim_prefix("bg_")]
	if name_.begins_with("emblem_"):
		var q := name_.trim_prefix("emblem_").split("_")
		return ["ui.grace.emblem.%s.%s" % [q[0], q[1]]] if q.size() == 2 else []
	if name_.begins_with("spell_"):
		var r := name_.trim_prefix("spell_").trim_suffix("_v2")
		return ["ui.grace.spell.%s.ring" % r.trim_suffix("_ring")] if r.ends_with("_ring") else ["ui.grace.spell." + r]
	if name_.begins_with("demon_"): return ["ui.grace.demon." + name_.trim_prefix("demon_")]
	if name_ in ["title_plaque", "candle", "knobs", "parchment"]: return ["ui.kit." + name_, "ui.grace." + name_]
	if name_ in ["sigil", "jackpot_plaque"]: return ["ui.grace." + name_]
	if name_ in ["board", "toggle"]: return ["ui.kit." + name_]
	if name_ in ["button_primary", "button_primary_wide", "button_secondary"]: return ["ui.kit.button." + name_.trim_prefix("button_")]
	if name_ == "mark_danger": return ["ui.kit.mark.danger"]
	if name_ in ["band_notice", "band_notice_big"]: return ["ui.kit.band." + name_.trim_prefix("band_")]
	return []

## The first meaning id of a part name ("" for a name that has no slot).
static func slot_of(name_: String) -> String:
	var ids := slot_ids(name_)
	return String(ids[0]) if not ids.is_empty() else ""

## The picture of a part with mipmaps (cards are drawn much smaller than the pictures), or null when no slot of it has a file (planned = no file).
static func tex(name_: String) -> Texture2D:
	if _tex.has(name_): return _tex[name_]
	var t: Texture2D = null
	var image := image_of(name_)
	if image != null:
		image.generate_mipmaps()
		t = ImageTexture.create_from_image(image)
	_tex[name_] = t
	return t

## The picture of a part as a fresh RGBA8 image without mipmaps, or null (no slot of it has a file).
static func image_of(name_: String) -> Image:
	for id in slot_ids(name_):
		if AssetSlots.has_slot(id) and not AssetSlots.is_planned(id) and AssetSlots.path(id) != "":
			var src: Texture2D = AssetSlots.texture(id)
			var image: Image = src.get_image() if src != null else null
			if image != null and not image.is_empty():
				if image.is_compressed(): image.decompress()
				if image.get_format() != Image.FORMAT_RGBA8: image.convert(Image.FORMAT_RGBA8)
				return image
	return null

static var _scaled := {}
## The picture of a part resampled to `factor` of its size (a nine-sliced kit picture is drawn at code size; the source is several times bigger, so the
## corners would be huge). Lanczos, mipmapped, cached by name and factor. Null when the part has no picture.
static func tex_scaled(name_: String, factor: float) -> Texture2D:
	var key := "%s@%.3f" % [name_, factor]
	if _scaled.has(key): return _scaled[key]
	var t: Texture2D = null
	var image := image_of(name_)
	if image != null:
		image.resize(maxi(2, roundi(image.get_width() * factor)), maxi(2, roundi(image.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
		image.generate_mipmaps()
		t = ImageTexture.create_from_image(image)
	_scaled[key] = t
	return t

## A part picture cut to `region` (source pixels) and resampled by `factor` (the two toggle states are two slots of one picture).
static func tex_region(name_: String, region: Rect2i, factor: float) -> Texture2D:
	var key := "%s@%s@%.3f" % [name_, str(region), factor]
	if _scaled.has(key): return _scaled[key]
	var t: Texture2D = null
	var image := image_of(name_)
	if image != null:
		var part := image.get_region(region)
		part.resize(maxi(2, roundi(part.get_width() * factor)), maxi(2, roundi(part.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
		part.generate_mipmaps()
		t = ImageTexture.create_from_image(part)
	_scaled[key] = t
	return t

static func source_of(_name: String) -> String:
	return "slot"

static func note_source(_part: String, _how: String) -> void:
	pass

## Keys magenta (#FF00FF) to transparent (soft edge + despill), and sets saturation / brightness / tint. `add` = additive blending.
static func art_material(sat := 1.0, bright := 1.0, add := false, tint := Color.WHITE) -> ShaderMaterial:
	if _sh_normal == null:
		var body := "uniform float sat = 1.0;\nuniform float bright = 1.0;\nuniform vec4 tint : source_color = vec4(1.0);\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tfloat mn = min(c.r, c.b);\n\tfloat k = smoothstep(0.62, 0.82, mn) * (1.0 - smoothstep(0.22, 0.45, c.g));\n\tfloat spill = max(0.0, mn - c.g) * smoothstep(0.35, 0.7, mn);\n\tvec3 rgb = c.rgb - vec3(spill * 0.85, 0.0, spill * 0.85);\n\tfloat l = dot(rgb, vec3(0.299, 0.587, 0.114));\n\trgb = mix(vec3(l), rgb, sat) * bright;\n\tCOLOR = vec4(rgb, c.a * (1.0 - k)) * tint;\n}\n"
		_sh_normal = Shader.new()
		_sh_normal.code = "shader_type canvas_item;\n" + body
		_sh_add = Shader.new()
		_sh_add.code = "shader_type canvas_item;\nrender_mode blend_add;\n" + body
	var m := ShaderMaterial.new()
	m.shader = _sh_add if add else _sh_normal
	m.set_shader_parameter("sat", sat)
	m.set_shader_parameter("bright", bright)
	m.set_shader_parameter("tint", tint)
	m.set_meta("tint_base", tint)
	return m

## Fades the pictures drawn with art_material() under `node` to `alpha` of their own tint. The material's shader writes COLOR itself, so the node's modulate does
## not reach these pictures: a screen that fades in or out calls this next to its own modulate.
static func set_art_alpha(node: Node, alpha: float) -> void:
	if node is CanvasItem and node.material is ShaderMaterial and node.material.has_meta("tint_base"):
		var base: Color = node.material.get_meta("tint_base")
		node.material.set_shader_parameter("tint", Color(base.r, base.g, base.b, base.a * alpha))
	for child in node.get_children(): set_art_alpha(child, alpha)

## A picture child filling `rect` (null when the picture does not exist: the caller falls back). The picture is painted in the child's own
## _draw (not a TextureRect node), so layered art over text is not an "overlap" for tools/dev/hud_layout_check.py (it only sees content nodes).
class ArtLayer extends Control:
	var texture: Texture2D:
		set(v):
			texture = v
			queue_redraw()
	func _draw() -> void:
		if texture != null: draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)

class GlowLayer extends Control:
	func _draw() -> void:
		draw_texture_rect(Kit.glow(), Rect2(Vector2.ZERO, size), false)

static func art_rect(parent: Node, name_: String, rect: Rect2, o := {}) -> Control:
	var t := tex(name_)
	if t == null: return null
	var r := ArtLayer.new()
	r.name = name_
	r.texture = t
	r.position = rect.position
	r.size = rect.size
	r.pivot_offset = rect.size * 0.5
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.material = art_material(float(o.get("sat", 1.0)), float(o.get("bright", 1.0)), bool(o.get("add", false)), o.get("tint", Color.WHITE))
	parent.add_child(r)
	return r

## A soft round light (additive by default) painted in _draw; `color` carries its alpha.
static func glow_rect(parent: Node, centre: Vector2, radius: float, color: Color, additive := true) -> Control:
	var g := GlowLayer.new()
	g.position = centre - Vector2(radius, radius)
	g.size = Vector2(radius, radius) * 2.0
	g.modulate = color
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if additive:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		g.material = m
	parent.add_child(g)
	return g

# ============================================================ small helpers
## A child Control that is painted by `fn(control)` (drawn during the control's own draw signal).
static func layer(parent: Control, fn: Callable, rect := Rect2()) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.position = rect.position
	c.size = rect.size if rect.size != Vector2.ZERO else parent.size
	c.draw.connect(fn.bind(c))
	parent.add_child(c)
	return c

## The biggest font size (>= min_size) at which `text` fits `width` on one line. Never below min_size.
static func fit_size(text: String, size: int, width: float, role: String, min_size: int) -> int:
	var s := size
	while s > min_size and Kit.measure(text, s, 99999.0, role).x > width: s -= 1
	return s

## The width of `text` on one line at `size`.
static func text_width(text: String, size: int, role: String) -> float:
	return Kit.measure(text, size, 99999.0, role).x

## Text that has to fit one line: shrink first; if it still does not fit, cut at the first " · " (a whole word group, never mid-word).
static func fit_text(text: String, size: int, width: float, role: String, min_size: int) -> Dictionary:
	var s := fit_size(text, size, width, role, min_size)
	var t := text
	if Kit.measure(t, s, 99999.0, role).x > width and " · " in t:
		t = t.get_slice(" · ", 0)
		s = fit_size(t, size, width, role, min_size)
	return {"text": t, "size": s}

## The medallion picture of a card kind, or null. kind: new / upgrade / evolve / trade|prep -> deal.
static func emblem_name(element: String, kind: String) -> String:
	var k: String = {"new": "new", "upgrade": "upgrade", "evolve": "evolve", "trade": "deal", "prep": "deal", "deal": "deal"}.get(kind, "new")
	return "emblem_%s_%s" % [element, k]

## A round spell mark: the spell picture (basic or ring) when it exists, else the code emblem of kit.gd.
static func spell_icon(parent: Control, emblem: String, element: String, box: Rect2) -> Control:
	var name_ := "spell_%s%s" % [element, "_ring" if emblem == "ring" else ""]
	if emblem == "ring" and tex(name_ + "_v2") != null: name_ += "_v2"   ## the redrawn orbiting ring (kit); the old walled ring stays as the fallback
	var a := art_rect(parent, name_, box)
	if a != null:
		note_source("spell icons", source_of(name_))
		return a
	var e = Kit.Emblem.new(emblem, element, box.size)
	e.position = box.position
	parent.add_child(e)
	note_source("spell icons", "code")
	return e

# ============================================================ Knob (the three hand-wheels: reroll / exclude / keep)
## A round brass button: the HUD's ring (slot_normal), a dark disc, a drawn glyph, the count on a small brass badge (level_badge, top right),
## the key on a leather plate (key_tag) under it, the word under that. Shape = glyph, so the three differ without colour.
## glyph: swirl (reroll) / slash (exclude) / latch (keep). The kit may give a picture per knob (name "knob_<id>") or one strip "knobs" (thirds).
class Knob extends Control:
	signal pressed(id: String)
	var P = load(PARTS_PATH)
	var id := ""
	var glyph := "swirl"
	var enabled := true
	var disc := Vector2(0, 0)
	var hot := 0.0:
		set(v):
			hot = v
			if _over != null: _over.queue_redraw()
	var down := false
	var _over: Control
	var _art: Control

	## spec: {id, glyph, key, label, count}. Width is fixed (118); height 150.
	func build(spec: Dictionary, order: int) -> void:
		id = String(spec.id)
		glyph = String(spec.glyph)
		enabled = String(spec.get("count", "1")) != "0"
		size = Vector2(118.0, 150.0)
		mouse_filter = Control.MOUSE_FILTER_STOP
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		disc = Vector2(size.x * 0.5, 50.0)
		var d := 84.0
		var drect := Rect2(disc - Vector2(d, d) * 0.5, Vector2(d, d))
		var how := "code"
		var per: String = "knob_" + id
		if P.tex(per) != null:
			_art = P.art_rect(self, per, drect.grow(6.0))
			how = P.source_of(per)
		elif P.tex("knobs") != null:
			_art = P.art_rect(self, "knobs", drect.grow(6.0))
			var t: Texture2D = P.tex("knobs")
			var at := AtlasTexture.new()
			at.atlas = t
			at.region = Rect2(t.get_width() * order / 3.0, 0, t.get_width() / 3.0, t.get_height())
			_art.texture = at
			how = P.source_of("knobs")
		P.note_source("knobs", how if how != "code" else "atlas")
		var base: Control = P.layer(self, Callable(self, "_paint_base"))
		move_child(base, 0)
		_over = P.layer(self, Callable(self, "_paint_over"))
		var badge_c := disc + Vector2(32.0, -30.0)
		var cnt := Kit.lbl(self, String(spec.get("count", "")), badge_c - Vector2(16.0, 12.0), 32.0, 18, Palette.INK, "number", HORIZONTAL_ALIGNMENT_CENTER, false, true)
		cnt.name = "Count"
		var key := String(spec.get("key", ""))
		if key != "":
			var kl := Kit.lbl(self, key, Vector2(size.x * 0.5 - 30.0, 98.0), 60.0, 15, Palette.INK, "number", HORIZONTAL_ALIGNMENT_CENTER, false, true)
			kl.name = "Key"
		var wl := Kit.lbl(self, String(spec.get("label", "")), Vector2(0.0, 124.0), size.x, 15, Palette.INK if enabled else Palette.INK_FAINT, "bold", HORIZONTAL_ALIGNMENT_CENTER, false, true)
		wl.name = "Label"
		modulate = Color.WHITE if enabled else Color(1, 1, 1, 0.55)
		gui_input.connect(func(e):
			if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
				down = e.pressed
				if e.pressed and enabled: pressed.emit(id)
				_over.queue_redraw())
		mouse_entered.connect(func(): hot = 1.0)
		mouse_exited.connect(func(): hot = 0.0)

	func _paint_base(c: Control) -> void:
		if _art != null: return
		c.draw_circle(disc + Vector2(0, 3), 40.0, Color(0, 0, 0, 0.5))
		c.draw_circle(disc, 36.0, Palette.SLOT)
		c.draw_circle(disc, 30.0, Color(0.035, 0.04, 0.045))

	func _paint_over(c: Control) -> void:
		var dc := disc + (Vector2(0, 2) if down else Vector2.ZERO)
		if _art == null:
			UiStyle.blit_centered(c, "slot_normal", dc, 84.0 / 80.0)
			_glyph(c, dc, 21.0)
		if hot > 0.0 and enabled:
			c.draw_arc(dc, 44.0, 0, TAU, 40, Kit.with_alpha(Palette.BRASS_HI, 0.9 * hot), 3.0, true)
		UiStyle.blit_centered(c, "level_badge", disc + Vector2(32.0, -30.0), 1.2)
		if _has_key():
			UiStyle.blit_centered(c, "key_tag", Vector2(size.x * 0.5, 108.0), 1.45)

	func _has_key() -> bool:
		return get_node_or_null("Key") != null

	## The three glyphs, drawn in brass-light: a spiral that winds back (reroll), crossed cuts (exclude), a clasp (keep).
	func _glyph(c: Control, ctr: Vector2, r: float) -> void:
		var col := Palette.BRASS_HI if enabled else Palette.BRASS_DIM
		match glyph:
			"swirl":
				var pts := PackedVector2Array()
				for k in 30:
					var t := float(k) / 29.0
					pts.append(ctr + Vector2.from_angle(-1.2 + t * 4.6 * PI * 0.62) * r * (1.0 - 0.78 * t))
				c.draw_polyline(pts, col, 3.0, true)
				var tip := pts[pts.size() - 1]
				var back := (pts[pts.size() - 2] - tip).normalized()
				c.draw_colored_polygon(PackedVector2Array([tip + back.rotated(0.7) * 8.0, tip, tip + back.rotated(-0.7) * 8.0 + back * 2.0]), col)
			"slash":
				for sgn in [-1.0, 1.0]:
					var a := ctr + Vector2(-r * 0.8, -r * 0.8 * sgn)
					var b := ctr + Vector2(r * 0.8, r * 0.8 * sgn)
					c.draw_line(a, b, col, 4.0, true)
					c.draw_line(a, b, Palette.INK, 1.2, true)
			_:
				c.draw_arc(ctr + Vector2(0, -4), r * 0.5, PI, TAU, 16, col, 3.5, true)
				c.draw_line(ctr + Vector2(-r * 0.5, -4), ctr + Vector2(-r * 0.5, 4), col, 3.5)
				c.draw_line(ctr + Vector2(r * 0.5, -4), ctr + Vector2(r * 0.5, 4), col, 3.5)
				c.draw_rect(Rect2(ctr + Vector2(-r * 0.72, 4), Vector2(r * 1.44, r * 0.9)), col)
				c.draw_circle(ctr + Vector2(0, 4 + r * 0.45), 2.6, Color(0.05, 0.05, 0.06))

## The knobs the contract names (reroll / exclude / keep; the counts are reroll.left_label, exclude.left_label, keep.left_label). A knob the core does not
## give is not in the contract and is not built. `gap` is the clear space between two knobs (>= 24 required; a knob is 118 wide).
static func handles(parent: Control, contract: Dictionary, pos: Vector2, gap := 28.0) -> Array:
	var ui: Dictionary = contract.get("strings", {})
	var specs: Array = []
	for id in ["reroll", "exclude", "keep"]:
		if not contract.get(id, null) is Dictionary: continue
		specs.append({"id": id, "glyph": {"reroll": "swirl", "exclude": "slash", "keep": "latch"}[id], "key": String(ui.get("key_" + id, "")), "label": String(ui.get(id, "")),
			"count": String(contract[id].get("left_label", ""))})
	var out: Array = []
	for i in specs.size():
		var k := Knob.new()
		k.build(specs[i], ["reroll", "exclude", "keep"].find(specs[i].id))
		k.position = pos + Vector2(float(i) * (118.0 + gap), 0.0)
		parent.add_child(k)
		out.append(k)
	return out

# ============================================================ SideNote (parchment, dark ink)
## The only place with explanation: name, headline, combo rows (marks + text), the path to evolution (beads), term glosses. Nothing is written
## twice (a line equal to an earlier one is dropped) and dev lines are left out. A block that does not fit is dropped whole, never cut.
class SideNote extends Control:
	const INK_PAPER := Palette.PARCHMENT_INK
	const INK_PAPER_DIM := Palette.PARCHMENT_INK_DIM
	var P = load(PARTS_PATH)
	var ui := {}
	var _holder: Control
	var _paper_art: Control

	func build(w: float, h: float, strings: Dictionary) -> void:
		ui = strings
		size = Vector2(w, h)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		# the paper's mean colour as a plain node under the picture: the layout dump reads it as the colour under the ink (the picture itself is invisible to it)
		var base := ColorRect.new()
		base.color = Palette.PARCHMENT
		base.size = size
		base.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(base)
		_paper_art = P.art_rect(self, "parchment", Rect2(Vector2.ZERO, size))
		if _paper_art != null: P.note_source("side note", P.source_of("parchment"))
		else:
			P.layer(self, Callable(self, "_paint_paper"))
			P.note_source("side note", "code")
		_holder = Control.new()
		_holder.size = size
		_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_holder)

	func _paint_paper(c: Control) -> void:
		var r := Rect2(Vector2.ZERO, size)
		c.draw_rect(r.grow(5.0), Color(0, 0, 0, 0.42))
		Kit.quad(c, r, Color(0.80, 0.70, 0.52), Color(0.70, 0.58, 0.40))
		var rng := RandomNumberGenerator.new()
		rng.seed = 41
		for i in int(size.x * size.y / 320.0):
			var p := Vector2(rng.randf() * size.x, rng.randf() * size.y)
			c.draw_rect(Rect2(p, Vector2(rng.randf_range(1.0, 3.0), 1.0)), Color(0.35, 0.25, 0.12, rng.randf_range(0.04, 0.12)))
		for k in 10:
			var a := 0.34 * (1.0 - float(k) / 10.0)
			c.draw_rect(r.grow(-float(k) * 1.8), Color(0.18, 0.10, 0.04, a), false, 2.0)
		for sx in [0.3, 0.7]:
			var stud := Vector2(size.x * sx, 14.0)
			c.draw_circle(stud + Vector2(0, 1.5), 7.0, Color(0, 0, 0, 0.4))
			c.draw_circle(stud, 6.5, Palette.BRASS_DIM)
			c.draw_circle(stud, 5.0, Palette.BRASS)
			c.draw_circle(stud + Vector2(-1.5, -1.5), 1.8, Color(Palette.LINEN, 0.85))

	func show_card(card: Dictionary) -> void:
		for ch in _holder.get_children():
			_holder.remove_child(ch)
			ch.queue_free()
		var art := _paper_art != null
		var pad := (size.x * 0.098 + 12.0) if art else 26.0
		var w := size.x - pad * 2.0
		var bottom := size.y - (size.y * 0.09 + 6.0 if art else 22.0)
		var y := (size.y * 0.11) if art else 34.0
		var seen: Array = []
		var el := String(card.get("element", "frost"))
		var nl: Label = Kit.lbl(_holder, String(card.get("name", "")), Vector2(pad, y), w, 22, INK_PAPER, "heading", HORIZONTAL_ALIGNMENT_LEFT, false)
		seen.append(String(card.get("name", "")))
		y += nl.size.y + 4.0
		var headline := String(card.get("headline", ""))
		if headline != "":
			var hl: Label = Kit.lbl(_holder, headline, Vector2(pad, y), w, 15, INK_PAPER, "body")
			seen.append(headline)
			y += hl.size.y + 8.0
		var lines: Array = []
		for line in card.get("details", []):
			var t := String(line)
			if t in seen: continue
			seen.append(t)
			lines.append(t)
		for t in lines:
			var need: float = Kit.measure(String(t), 14, w).y + 4.0
			if y + need > bottom: break
			var dl: Label = Kit.lbl(_holder, String(t), Vector2(pad, y), w, 14, INK_PAPER_DIM, "body")
			y += dl.size.y + 2.0
		var combo: Array = card.get("combo", [])
		if combo.size() > 0:
			var need0 := 24.0 + 30.0 + Kit.measure(String(combo[0].text), 14, w).y
			if y + 8.0 + need0 <= bottom:
				y += 8.0
				Kit.lbl(_holder, String(ui.get("combo", "")), Vector2(pad, y), w, 14, INK_PAPER, "bold", HORIZONTAL_ALIGNMENT_LEFT, false)
				y += 22.0
				for cb in combo:
					var tl: float = Kit.measure(String(cb.text), 14, w).y
					if y + 30.0 + tl + 4.0 > bottom: break
					P.spell_icon(_holder, String(cb["from"]), String(cb.from_element), Rect2(Vector2(pad, y), Vector2(28, 28)))
					Kit.lbl(_holder, "→", Vector2(pad + 30.0, y + 3.0), 22.0, 18, INK_PAPER, "bold", HORIZONTAL_ALIGNMENT_CENTER, false)
					P.spell_icon(_holder, String(cb["to"]), String(cb.to_element), Rect2(Vector2(pad + 54.0, y), Vector2(28, 28)))
					y += 31.0
					var ct: Label = Kit.lbl(_holder, String(cb.text), Vector2(pad, y), w, 14, INK_PAPER_DIM, "body")
					y += ct.size.y + 5.0
		var path: Variant = card.get("path", null)
		if path is Dictionary and y + 62.0 <= bottom:
			y += 6.0
			Kit.lbl(_holder, String(path.label), Vector2(pad, y), w, 14, INK_PAPER, "bold", HORIZONTAL_ALIGNMENT_LEFT, false)
			y += 22.0
			var pips := Control.new()
			pips.position = Vector2(pad, y)
			pips.size = Vector2(w, 20.0)
			pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pips.draw.connect(func():
				for k in int(path.total):
					var p := Vector2(10.0 + float(k) * 24.0, 10.0)
					if k < int(path.filled): UiStyle.blit_centered(pips, "bead_gold", p, 0.85)
					else: UiStyle.blit_centered(pips, "bead_empty", p, 0.85))
			_holder.add_child(pips)
			y += 24.0
		var terms: Array = card.get("terms", [])
		for tm in terms:
			var gtxt := "%s  %s" % [tm.word, tm.gloss]
			var gn: float = Kit.measure(gtxt, 14, w).y + 4.0
			if y + gn > bottom: break
			if gtxt in seen: continue
			seen.append(gtxt)
			var tl2: Label = Kit.lbl(_holder, gtxt, Vector2(pad, y), w, 14, INK_PAPER, "body")
			y += tl2.size.y + 2.0

static func note(parent: Control, rect: Rect2, contract: Dictionary) -> SideNote:
	var n := SideNote.new()
	n.build(rect.size.x, rect.size.y, contract.get("strings", {}))
	n.position = rect.position
	parent.add_child(n)
	return n

# ============================================================ TitlePlaque / JackpotPlaque
## Brass name plate on leather. The art (N2) is used when it is in the kit; otherwise the HUD's name plate (boss_name) nine-sliced.
class TitlePlaque extends Control:
	var P = load(PARTS_PATH)
	func build(text: String, w: float, sub: String, text_size := 36, fit := 0.76) -> void:
		var art: Texture2D = P.tex("title_plaque")
		var h := w / 3.0 if art != null else maxf(96.0, w * 0.19)
		size = Vector2(w, h)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if art != null:
			P.art_rect(self, "title_plaque", Rect2(Vector2.ZERO, size))
			P.note_source("title plaque", P.source_of("title_plaque"))
		else:
			var panel := Panel.new()
			panel.size = size
			panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var box := AtlasBox.new()
			box.piece = "boss_name"
			box.margins_px = Vector4(80, 34, 80, 34)
			panel.add_theme_stylebox_override("panel", box)
			add_child(panel)
			P.layer(self, Callable(self, "_paint_rim"))
			P.note_source("title plaque", "atlas")
		var ty := h * (0.20 if sub == "" else 0.14)
		var tl: Label = Kit.lbl(self, text, Vector2(w * 0.12, ty), w * 0.76, P.fit_size(text, text_size, w * fit, "heading", 20), Palette.INK, "heading", HORIZONTAL_ALIGNMENT_CENTER, false, true)
		tl.name = "Title"
		if sub != "":
			var sl: Label = Kit.lbl(self, sub, Vector2(w * 0.12, ty + tl.size.y), w * 0.76, 15, Palette.INK_DIM, "body", HORIZONTAL_ALIGNMENT_CENTER, false, true)
			sl.name = "Sub"

	func _paint_rim(c: Control) -> void:
		c.draw_rect(Rect2(Vector2(7, 7), size - Vector2(14, 14)), Kit.with_alpha(Palette.BRASS, 0.55), false, 1.5)

static func title(parent: Control, text: String, width: float, sub := "", text_size := 36, fit := 0.76) -> TitlePlaque:
	var p := TitlePlaque.new()
	p.build(text, width, sub, text_size, fit)
	parent.add_child(p)
	return p

# ============================================================ Candle (iron stand + wax from art or code; the flame is code)
## `lit_amount` 0..1 scales the flame and its light (a jackpot can raise it). `animated` false = a still flame (reduced motion). The flame is built
## from three layers (a wide additive light, the body, the hot core) and flickers with two sines of unrelated periods plus a slow random drift,
## so it never repeats in step with the other candle (each has its own phase).
class Candle extends Control:
	var P = load(PARTS_PATH)
	var flame_color := Palette.FLAME_WARM
	var lit_amount := 1.0
	var animated := true
	var wick := Vector2(0.5, 0.2)  ## where the flame sits, as a fraction of the candle's size
	var _t := 0.0
	var _phase := 0.0
	var _art: Control
	var _flame: Control
	var _light: Control

	func build(sz: Vector2, color: Color, phase := 0.0) -> void:
		size = sz
		flame_color = color
		_phase = phase
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if P.tex("candle") != null:
			# the kit candle has no flame: the control grows upward by `room` so the code flame has space above the wick
			var room := sz.y * 0.22
			size = Vector2(sz.x, sz.y + room)
			_art = P.art_rect(self, "candle", Rect2(Vector2(0, room), sz))
			wick = Vector2(0.5, (room + sz.y * 0.035) / size.y)
			P.note_source("candle", P.source_of("candle"))
		else:
			P.layer(self, Callable(self, "_paint_stand"))
			P.note_source("candle", "code")
		_light = P.glow_rect(self, wick * sz, sz.y * 0.34, Kit.with_alpha(color, 0.30))
		_flame = P.layer(self, Callable(self, "_paint_flame"))
		set_process(true)

	func _process(delta: float) -> void:
		if animated: _t += delta
		_flame.queue_redraw()
		var f := _flick()
		_light.modulate = Kit.with_alpha(flame_color, (0.22 + 0.16 * f) * lit_amount)

	func _flick() -> float:
		var t := _t + _phase
		return clampf(0.62 + 0.20 * sin(t * 7.3) + 0.12 * sin(t * 12.9 + 1.7) + 0.08 * sin(t * 3.1 + 0.4), 0.0, 1.0)

	## Iron stand and wax in code: a dish on a foot, a stem, a drip-edged candle.
	func _paint_stand(c: Control) -> void:
		var w := size.x
		var h := size.y
		var iron := Color(0.10, 0.10, 0.115)
		var iron_hi := Color(0.30, 0.28, 0.26)
		var wick_y := h * wick.y
		var wx := w * 0.5
		c.draw_colored_polygon(PackedVector2Array([Vector2(wx - w * 0.07, h * 0.52), Vector2(wx + w * 0.07, h * 0.52), Vector2(wx + w * 0.16, h * 0.93), Vector2(wx - w * 0.16, h * 0.93)]), iron)
		c.draw_rect(Rect2(wx - w * 0.36, h * 0.93, w * 0.72, h * 0.04), iron)
		c.draw_rect(Rect2(wx - w * 0.36, h * 0.93, w * 0.72, 2.0), iron_hi)
		c.draw_rect(Rect2(wx - w * 0.30, h * 0.49, w * 0.60, h * 0.035), iron)
		c.draw_rect(Rect2(wx - w * 0.30, h * 0.49, w * 0.60, 2.0), iron_hi)
		var wax_top := wick_y + h * 0.06
		var wax := Rect2(wx - w * 0.17, wax_top, w * 0.34, h * 0.49 - wax_top)
		Kit.quad(c, wax, Color(0.86, 0.80, 0.66), Color(0.62, 0.55, 0.42))
		c.draw_rect(Rect2(wax.position.x, wax.position.y, wax.size.x * 0.22, wax.size.y), Color(1, 1, 1, 0.10))
		for k in 3:
			var dx := wax.position.x + wax.size.x * (0.2 + 0.3 * float(k))
			c.draw_rect(Rect2(dx, wax.position.y, w * 0.045, h * (0.07 + 0.04 * float((k * 2) % 3))), Color(0.9, 0.84, 0.70, 0.9))
		c.draw_line(Vector2(wx, wick_y + h * 0.015), Vector2(wx, wick_y + h * 0.06), Color(0.08, 0.06, 0.05), 2.0)

	func _paint_flame(c: Control) -> void:
		var f := _flick() * lit_amount
		var base := Vector2(size.x * wick.x, size.y * wick.y + size.y * 0.015)
		var sway := sin((_t + _phase) * 2.3) * 2.0 * f
		var ht := size.y * (0.21 + 0.06 * f)
		var wd := size.x * (0.13 + 0.014 * f)
		var tip := base + Vector2(sway, -ht)
		var body := PackedVector2Array([base + Vector2(-wd, 0), base + Vector2(-wd * 0.9, -ht * 0.35), tip + Vector2(-wd * 0.2, ht * 0.2), tip, tip + Vector2(wd * 0.2, ht * 0.2), base + Vector2(wd * 0.9, -ht * 0.35), base + Vector2(wd, 0)])
		c.draw_colored_polygon(body, Kit.with_alpha(flame_color.darkened(0.15), 0.92))
		var s2 := PackedVector2Array([base + Vector2(-wd * 0.55, 0), base + Vector2(-wd * 0.5, -ht * 0.3), tip.lerp(base, 0.45) + Vector2(sway * 0.3, 0), base + Vector2(wd * 0.5, -ht * 0.3), base + Vector2(wd * 0.55, 0)])
		c.draw_colored_polygon(s2, Kit.with_alpha(flame_color.lightened(0.35), 0.95))
		c.draw_circle(base + Vector2(0, -ht * 0.12), wd * 0.32, Color(1.0, 0.93, 0.78, 0.95))

static func candle(parent: Control, pos: Vector2, height: float, color := Palette.FLAME_WARM) -> Candle:
	var c := Candle.new()
	c.build(Vector2(height * 0.5, height), color, fmod(absf(pos.x) * 0.0137, 6.0))  ## own phase per position, deterministic
	c.position = pos
	parent.add_child(c)
	return c

# ============================================================ GradeFrame (the ground and frame of anything that has a grade)
## The two pictures a grade card is made of, split out of the grace card (A10 2.3). They are separate layers because the medallion sits between them:
## ground (under) -> emblem -> frame (over). A grace card calls ground() and frame(); gear (slot, card, loot notice) calls the same, or builds a whole
## GradeFrame control with build(key, size). Grade keys: the grace three (common / rare / jackpot) and the gear five (common / magic / rare / legendary / unique);
## a key without a picture draws a code frame in the grade colour (the shape differs by rank, so grades part without colour: steel straight, bronze with spikes, gold with crown spikes).
class GradeFrame extends Control:
	var P = load(PARTS_PATH)
	var gkey := "common"
	## The ground look of a grace grade (bright, tint): the card does not get brighter by luck, the ground does.
	const GROUND_LOOK := {"common": [0.92, Color.WHITE], "rare": [1.28, Color(1.1, 1.0, 0.84)], "jackpot": [1.08, Color.WHITE]}

	static func ground(parent: Node, key: String, rect: Rect2, opts := {}) -> Control:
		var Q = load(PARTS_PATH)
		var look: Array = GROUND_LOOK.get(key, [1.0, Color.WHITE])
		var o := {"bright": look[0], "tint": look[1]}
		o.merge(opts, true)
		return Q.art_rect(parent, "bg_" + key, rect, o)

	static func frame(parent: Node, key: String, rect: Rect2, opts := {}) -> Control:
		var Q = load(PARTS_PATH)
		return Q.art_rect(parent, "frame_" + key, rect, opts)

	static func has_art(key: String) -> bool:
		var Q = load(PARTS_PATH)
		return Q.tex("frame_" + key) != null and Q.tex("bg_" + key) != null

	## A whole grade face of `sz` (ground and frame, nothing between): a gear slot or a loot notice's icon box.
	func build(key: String, sz: Vector2) -> void:
		gkey = key
		size = sz
		custom_minimum_size = sz
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if has_art(key):
			ground(self, key, Rect2(Vector2.ZERO, sz))
			frame(self, key, Rect2(Vector2.ZERO, sz))
		else:
			P.layer(self, Callable(self, "_paint_code"))

	func _paint_code(c: Control) -> void:
		var col: Color = Palette.quality_color(gkey, Palette.BRASS) if gkey != "jackpot" else Palette.GRACE_JACKPOT
		var r := Rect2(Vector2.ZERO, size)
		c.draw_rect(r, Palette.SLOT)
		c.draw_rect(r.grow(-1.0), col, false, 2.0)
		if gkey in ["rare", "legendary", "unique", "jackpot"]:
			c.draw_rect(r.grow(-6.0), Kit.with_alpha(col, 0.7), false, 1.0)
			Kit.diamond(c, Vector2(size.x * 0.5, 1.0), 4.0, col, true)

# ============================================================ Band (leather strip)
## HUD leather strip (strip_left + tiled strip_tile + strip_right). paint() draws it on any canvas item (the owned-spells band does); a Band control is the
## same strip as a node of `w` x `h` (a band notice), or the picture `ui.kit.band.notice` when it exists.
class Band extends Control:
	var P = load(PARTS_PATH)

	func build(w: float, h: float) -> void:
		size = Vector2(w, h)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if P.tex("band_notice") != null:
			P.art_rect(self, "band_notice", Rect2(Vector2.ZERO, size))
		else:
			P.layer(self, Callable(self, "_paint_me"))

	func _paint_me(c: Control) -> void:
		paint(c, size.x, size.y)

	static func paint(c: CanvasItem, w: float, h: float) -> void:
		var tile := UiStyle.piece_size("strip_tile") * (h / UiStyle.piece_size("strip_tile").y)
		var cap_l := UiStyle.piece_size("strip_left") * (h / UiStyle.piece_size("strip_left").y)
		var cap_r := UiStyle.piece_size("strip_right") * (h / UiStyle.piece_size("strip_right").y)
		c.draw_rect(Rect2(Vector2(0, 6), Vector2(w, h - 8.0)), Color(0, 0, 0, 0.35))
		var x := cap_l.x - 2.0
		while x < w - cap_r.x + 2.0:
			var wdt := minf(tile.x, w - cap_r.x + 2.0 - x)
			UiStyle.blit_part(c, "strip_tile", Rect2(x, 0, wdt, h), wdt / tile.x)
			x += tile.x
		UiStyle.blit(c, "strip_left", Rect2(Vector2.ZERO, cap_l))
		UiStyle.blit(c, "strip_right", Rect2(Vector2(w - cap_r.x, 0), cap_r))

# ============================================================ Board (the window board)
## The contract board of a window (A8 6.2 N1, nine-sliced). Without the picture `ui.kit.board` it is the flat window of UiStyle (the fall-back path).
## The slice margins and the draw scale are UiStyle.KIT_SLICES.
class Board extends Control:
	var P = load(PARTS_PATH)

	func build(sz: Vector2) -> void:
		size = sz
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var panel := Panel.new()
		panel.size = sz
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_theme_stylebox_override("panel", UiStyle.window("board"))
		add_child(panel)

# ============================================================ BrassToggle (the brass switch of a setting row)
## A setting row: its words on the left, the brass switch of ui.kit.toggle on the right (on = the knob at the right end, the slot a little warmer). A Button in toggle
## mode, so Space or Enter flips it when it has the focus and a click flips it too; `changed(on)` is the only thing it says. Without the picture it draws a plain
## pill (the shape differs on and off, so it parts without colour). The focus is the list-row mark (a brass bar on the left edge).
class BrassToggle extends Button:
	signal changed(on: bool)
	var P = load(PARTS_PATH)

	func build(label: String, on: bool, width: float) -> void:
		toggle_mode = true
		button_pressed = on
		text = label
		alignment = HORIZONTAL_ALIGNMENT_LEFT
		var role := UiStyle.text("t5", "body")
		add_theme_font_override("font", Loc.font(String(role.font)))
		add_theme_font_size_override("font_size", int(role.size))
		for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			add_theme_color_override(color_name, Palette.INK)
		var none := StyleBoxEmpty.new()
		none.content_margin_left = 16
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			add_theme_stylebox_override(state, none)
		add_theme_stylebox_override("focus", UiStyle.focus_mark("row"))
		custom_minimum_size = Vector2(width, 48)
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		toggled.connect(func(v: bool): queue_redraw(); changed.emit(v))

	func _draw() -> void:
		var slot: Texture2D = P.tex_region("toggle", UiStyle.TOGGLE_REGIONS["on" if button_pressed else "off"], UiStyle.TOGGLE_SCALE)
		if slot != null:
			draw_texture(slot, Vector2(size.x - slot.get_width() - 14.0, (size.y - slot.get_height()) * 0.5))
			return
		var r := Rect2(Vector2(size.x - 70.0, size.y * 0.5 - 14.0), Vector2(56.0, 28.0))
		draw_rect(r, Palette.SLOT)
		draw_rect(r, Palette.BRASS, false, 2.0)
		var knob_x := r.end.x - 14.0 if button_pressed else r.position.x + 14.0
		draw_circle(Vector2(knob_x, r.get_center().y), 9.0, Palette.BRASS_HI if button_pressed else Palette.BRASS_DIM)

static func toggle(parent: Control, label: String, on: bool, width := 360.0) -> BrassToggle:
	var t := BrassToggle.new()
	t.build(label, on, width)
	parent.add_child(t)
	return t
