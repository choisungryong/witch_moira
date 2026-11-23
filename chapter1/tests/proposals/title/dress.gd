extends RefCounted
## The shared dress of the two first-screen proposals (A10 W3): the parts of the grace screen's hand (leather band, brass plaque, candles,
## parchment note) put around ONE witch. Both proposals call build_block(); only the stage around it differs (a: three doors, c: one stage).
## Sizes are code units (1600 x 900); text uses the seven roles of UiStyle.text(); colours are Palette tokens only. Tests only, no core access.
## NEW ART NEEDED (falls back to the leather strip pieces of the HUD atlas, which the grace screen already uses): the button faces ui.kit.button.primary
## / secondary (K2); the three knob pictures for tree / stash / costume (the grace knob art draws reroll / exclude / keep, so these knobs are code).

const Parts = preload("res://chapter1/tests/proposals/title/parts.gd")
const UiParts = preload("res://chapter1/view/hud/ui_parts.gd")
const UiStyle = preload("res://chapter1/view/hud/ui_style.gd")
const Palette = preload("res://chapter1/view/hud/palette.gd")
const Motion = preload("res://chapter1/view/hud/ui_motion.gd")
const Kit = preload("res://chapter1/tests/proposals/growth_choice/kit.gd")
const Loc = preload("res://chapter1/view/loc.gd")

const KNOB_W := 118.0
const KNOB_H := 132.0
const KNOB_GAP_MIN := 24.0

# ---------------------------------------------------------------- the one main button

## The "primary" button: the picture ui.kit.button.primary when it exists (UiStyle.button_kind), otherwise the leather strip of the combat HUD
## (the same piece the grace screen's owned-spells band is made of). A diamond of the witch's colour on both sides of the word (shape first, colour second).
class LeatherButton extends Control:
	signal pressed
	var text := ""
	var accent := Palette.BRASS_HI
	var hot := false
	var flash := 0.0:
		set(v):
			flash = v
			queue_redraw()

	func setup(label_text: String, s: Vector2, accent_color: Color) -> void:
		text = label_text
		size = s
		custom_minimum_size = s
		accent = accent_color
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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
		var rect := Rect2(Vector2.ZERO, size)
		if UiParts.tex("button_primary") != null:
			draw_style_box(UiStyle.button_kind("primary", "hover" if hot else "normal"), rect)
		else:
			UiParts.Band.paint(self, size.x, size.y)
			if hot:
				draw_rect(rect.grow(-4.0), Color(Palette.BRASS_HI.r, Palette.BRASS_HI.g, Palette.BRASS_HI.b, 0.12))
		var t := UiStyle.text("t4", "heading")
		var f: Font = Loc.font("heading")
		var px := int(t.size)
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var base := Vector2((size.x - w) * 0.5, size.y * 0.5 + (f.get_ascent(px) - f.get_descent(px)) * 0.5 - 1.0)
		draw_string_outline(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 3, Color(0, 0, 0, 0.8))
		draw_string(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Palette.INK)
		var dm := float(px) * 0.28
		Kit.diamond(self, Vector2(base.x - float(px) * 0.9, size.y * 0.5), dm, accent)
		Kit.diamond(self, Vector2(base.x + w + float(px) * 0.9, size.y * 0.5), dm, accent)
		if flash > 0.0:
			draw_rect(rect.grow(-3.0), Color(1, 1, 1, 0.4 * flash))

# ---------------------------------------------------------------- level band

## Leather strip with the level, the bar to the next level and the free skill points (diamond + number).
class LevelBand extends Control:
	func setup(w: float, h: float, ui: Dictionary, growth: Dictionary, accent: Color) -> void:
		size = Vector2(w, h)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		UiParts.layer(self, func(c: Control): UiParts.Band.paint(c, w, h))
		var t := UiStyle.text("t4", "number")
		var inset := h * 1.55
		var ltxt := "%s %d" % [String(ui.get("level", "Lv")), int(growth.level)]
		var lw: float = Loc.font("number").get_string_size(ltxt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(t.size)).x
		var lh := Kit.line_height(int(t.size), "number")
		Kit.lbl(self, ltxt, Vector2(inset, (h - lh) * 0.5 - 1.0), ceilf(lw) + 2.0, int(t.size), Palette.INK, "number", HORIZONTAL_ALIGNMENT_LEFT, false)
		var right := w - inset
		var pts := int(growth.points_free)
		if pts > 0:
			var tag := Parts.PointsTag.new()
			tag.setup(pts, Palette.GROWTH, int(t.size))
			tag.position = Vector2(right - tag.size.x, (h - tag.size.y) * 0.5 - 1.0)
			add_child(tag)
			right -= tag.size.x + 10.0
		var bx := inset + lw + 14.0
		var bw := maxf(right - bx, 30.0)
		var span := maxf(float(growth.xp_for_next) - float(growth.xp_level_start), 1.0)
		var frac := clampf((float(growth.xp) - float(growth.xp_level_start)) / span, 0.0, 1.0)
		var by := h * 0.5 - 3.0 - 1.0
		Parts.rect_node(self, Rect2(bx, by, bw, 6.0), Color(1, 1, 1, 0.16))
		Parts.rect_node(self, Rect2(bx, by, bw * frac, 6.0), accent)

# ---------------------------------------------------------------- the round side buttons (tree, stash, costume)

## Same make as the grace screen's Knob (brass ring slot_normal, dark disc, count on a level_badge, word under it), with its own three glyphs.
## The glyph is the shape that tells the three apart (a branching tree, a chest, a hanger), the count is the number on the badge.
class TitleKnob extends Control:
	signal pressed(id: String)
	var id := ""
	var glyph := "tree"
	var disc := Vector2(KNOB_W * 0.5, 46.0)
	var hot := 0.0:
		set(v):
			hot = v
			queue_redraw()
	var down := false

	func build(spec: Dictionary) -> void:
		id = String(spec.id)
		glyph = String(spec.glyph)
		size = Vector2(KNOB_W, KNOB_H)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var cnt := Kit.lbl(self, String(spec.get("count", "")), disc + Vector2(32.0, -30.0) - Vector2(16.0, 12.0), 32.0, 18, Palette.INK, "number", HORIZONTAL_ALIGNMENT_CENTER, false, true)
		cnt.name = "Count"
		var wl := Kit.lbl(self, String(spec.get("label", "")), Vector2(0.0, 94.0), size.x, 15, Palette.INK, "bold", HORIZONTAL_ALIGNMENT_CENTER, false, true)
		wl.name = "Label"
		gui_input.connect(func(e):
			if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
				down = e.pressed
				if e.pressed:
					pressed.emit(id)
				queue_redraw())
		mouse_entered.connect(func(): hot = 1.0)
		mouse_exited.connect(func(): hot = 0.0)

	func _draw() -> void:
		var dc := disc + (Vector2(0, 2) if down else Vector2.ZERO)
		draw_circle(disc + Vector2(0, 3), 40.0, Color(0, 0, 0, 0.5))
		draw_circle(disc, 36.0, Palette.SLOT)
		draw_circle(disc, 30.0, Palette.SURFACE)
		UiStyle.blit_centered(self, "slot_normal", dc, 84.0 / 80.0)
		_glyph(dc, 21.0)
		if hot > 0.0:
			draw_arc(dc, 44.0, 0, TAU, 40, Color(Palette.BRASS_HI.r, Palette.BRASS_HI.g, Palette.BRASS_HI.b, 0.9 * hot), 3.0, true)
		UiStyle.blit_centered(self, "level_badge", disc + Vector2(32.0, -30.0), 1.2)

	func _glyph(ctr: Vector2, r: float) -> void:
		var col := Palette.BRASS_HI
		match glyph:
			"tree":
				draw_line(ctr + Vector2(0, r * 0.9), ctr + Vector2(0, -r * 0.1), col, 3.0, true)
				draw_line(ctr + Vector2(0, r * 0.2), ctr + Vector2(-r * 0.8, -r * 0.5), col, 3.0, true)
				draw_line(ctr + Vector2(0, r * 0.2), ctr + Vector2(r * 0.8, -r * 0.5), col, 3.0, true)
				for p in [Vector2(0, -r * 0.4), Vector2(-r * 0.8, -r * 0.6), Vector2(r * 0.8, -r * 0.6)]:
					draw_circle(ctr + (p as Vector2), 4.2, col)
					draw_circle(ctr + (p as Vector2), 2.0, Palette.SURFACE)
			"chest":
				draw_rect(Rect2(ctr + Vector2(-r * 0.85, -r * 0.05), Vector2(r * 1.7, r * 0.85)), col)
				draw_arc(ctr + Vector2(0, -r * 0.05), r * 0.85, PI, TAU, 18, col, 3.0, true)
				draw_line(ctr + Vector2(-r * 0.85, -r * 0.05), ctr + Vector2(r * 0.85, -r * 0.05), Palette.SURFACE, 1.6)
				draw_rect(Rect2(ctr + Vector2(-r * 0.16, -r * 0.18), Vector2(r * 0.32, r * 0.42)), Palette.SURFACE)
			_:
				draw_arc(ctr + Vector2(0, -r * 0.55), r * 0.26, PI * 0.1, PI * 1.65, 12, col, 3.0, true)
				draw_line(ctr + Vector2(0, -r * 0.28), ctr + Vector2(0, -r * 0.02), col, 3.0, true)
				draw_line(ctr + Vector2(0, -r * 0.02), ctr + Vector2(-r * 0.95, r * 0.75), col, 3.0, true)
				draw_line(ctr + Vector2(0, -r * 0.02), ctr + Vector2(r * 0.95, r * 0.75), col, 3.0, true)
				draw_line(ctr + Vector2(-r * 0.95, r * 0.75), ctr + Vector2(r * 0.95, r * 0.75), col, 3.0, true)

# ---------------------------------------------------------------- the key line (the only place the controls are written)

class HintRow extends Control:
	var segs: Array = []

	func setup(list: Array, w: float) -> void:
		segs = list
		size = Vector2(w, 22.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	func _draw() -> void:
		var kf: Font = UiStyle.heading_font()
		var bf: Font = Loc.font("body")
		var widths: Array = []
		var total := 0.0
		for s in segs:
			var kw := maxf(UiStyle.piece_size("key_tag").x, kf.get_string_size(String(s[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 16.0)
			var ww := bf.get_string_size(String(s[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			widths.append([kw, ww])
			total += kw + 6.0 + ww
		total += 18.0 * float(maxi(segs.size() - 1, 0))
		var x := (size.x - total) * 0.5
		for k in segs.size():
			var kw: float = widths[k][0]
			var plate_h := UiStyle.piece_size("key_tag").y
			var y := (size.y - plate_h) * 0.5
			UiStyle.blit(self, "key_tag", Rect2(x, y, kw, plate_h))
			draw_string_outline(kf, Vector2(x, y + plate_h * 0.5 + 5.0), String(segs[k][0]), HORIZONTAL_ALIGNMENT_CENTER, kw, 14, 3, Color(0, 0, 0, 0.85))
			draw_string(kf, Vector2(x, y + plate_h * 0.5 + 5.0), String(segs[k][0]), HORIZONTAL_ALIGNMENT_CENTER, kw, 14, Palette.INK)
			draw_string(bf, Vector2(x + kw + 6.0, y + plate_h * 0.5 + 5.0), String(segs[k][1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Palette.INK_DIM)
			x += kw + 6.0 + float(widths[k][1]) + 18.0

## The little brass pill that says whose skill the parchment is ("first skill").
class Tab extends Control:
	var text := ""
	func setup(t: String) -> void:
		text = t
		var w := Loc.font("bold").get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 22.0
		size = Vector2(ceilf(w), 22.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = Palette.SURFACE
		box.border_color = Palette.BRASS
		box.set_border_width_all(2)
		box.set_corner_radius_all(11)
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		var f: Font = Loc.font("bold")
		draw_string(f, Vector2(0, size.y * 0.5 + 5.0), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Palette.INK)

# ---------------------------------------------------------------- the block of one witch

## spec: width (the column, code units), plaque (the brass plate's width), note_h, hint (bool). Returns the same dictionary the harness
## expects: {root, start, tree, stash, costume, height}. The order, top to bottom: plaque with a candle each side (the witch is the subject),
## her line, the parchment of her first skill (it hangs on her), level band, the start button, the round buttons, the key line.
static func build_block(i: int, w: Dictionary, ui: Dictionary, profile: Dictionary, spec: Dictionary) -> Dictionary:
	var width: float = float(spec.width)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var el := String(w.element)
	var accent: Color = Parts.el_color(i)
	var out := {"root": root, "start": null, "tree": null, "stash": null, "costume": null}
	var y := 0.0
	# 1. plaque + two candles (the flame takes the witch's colour)
	var pw: float = float(spec.plaque)
	var candle_h := 86.0
	var plaque := UiParts.title(root, String(w.title), pw, "")
	plaque.position = Vector2((width - pw) * 0.5, 22.0)
	for side in [0, 1]:
		var cd := UiParts.candle(root, Vector2.ZERO, candle_h, accent.lerp(Palette.FLAME_WARM, 0.3))
		var cx := (width - pw) * 0.5 - cd.size.x - 2.0 if side == 0 else (width + pw) * 0.5 + 2.0
		cd.position = Vector2(cx, 22.0 + plaque.size.y - cd.size.y + 6.0)
	y = 22.0 + plaque.size.y + 12.0
	# 2. her line
	var line := String(w.get("line", ""))
	if line.strip_edges() == "":
		line = String(ui.get("line_pending", ""))
	var t4 := UiStyle.text("t4")
	var ll := Kit.lbl(root, line, Vector2(0, y), width, int(t4.size), Palette.INK, "body", HORIZONTAL_ALIGNMENT_CENTER, true, true)
	ll.name = "Line"
	y += ll.size.y + 14.0
	# 3. the parchment of her first skill
	var nh: float = float(spec.note_h)
	var note := UiParts.note(root, Rect2(0, y, width, nh), {"strings": {}})
	note.name = "SkillNote"
	note.show_card({"element": el, "name": String(w.skill_name), "headline": String(w.skill_summary), "details": [" · ".join(PackedStringArray(w.traits))]})
	var tab := Tab.new()
	tab.setup(String(ui.get("first_skill", "첫 기술")))
	tab.position = Vector2(width * 0.098 + 4.0, -11.0)
	note.add_child(tab)
	var icon := Parts.SkillIcon.new()
	icon.setup(el, 40.0)
	icon.position = Vector2(width - width * 0.098 - 52.0, nh * 0.11 + 2.0)
	note.add_child(icon)
	y += nh + 10.0
	# 4. level band, 5. start, 6. round buttons (only with a profile)
	var growth: Variant = w.get("growth", null)
	var profile_on := bool(profile.get("enabled", true))
	if growth is Dictionary and profile_on:
		var lb := LevelBand.new()
		lb.name = "LevelBand"
		lb.setup(width, 38.0, ui, growth, accent)
		lb.position = Vector2(0, y)
		root.add_child(lb)
		y += 38.0 + 10.0
	var button := LeatherButton.new()
	button.name = "Start"
	button.setup(String(ui.get("start", "")), Vector2(width, 54.0), accent)
	button.position = Vector2(0, y)
	root.add_child(button)
	out["start"] = button
	y += 54.0 + 10.0
	if profile_on:
		var specs: Array = []
		if growth is Dictionary:
			specs.append({"id": "tree", "glyph": "tree", "label": String(ui.get("tree", "")), "count": str(int(growth.points_free)), "slot": "tree"})
		specs.append({"id": "stash", "glyph": "chest", "label": String(ui.get("stash", "장비")), "count": str(int(profile.get("stash_count", 0))), "slot": "stash"})
		var costume: Variant = w.get("costume", null)
		if costume is Dictionary:
			specs.append({"id": "costume", "glyph": "hanger", "label": String(ui.get("costume", "의상")), "count": str(int(costume.owned)), "slot": "costume"})
		var gap := minf(28.0, (width - KNOB_W * float(specs.size())) / maxf(float(specs.size() - 1), 1.0))
		var row_w := KNOB_W * float(specs.size()) + gap * float(specs.size() - 1)
		var x := (width - row_w) * 0.5
		for sp in specs:
			var k := TitleKnob.new()
			k.build(sp)
			k.position = Vector2(x, y)
			root.add_child(k)
			out[String(sp.slot)] = k
			x += KNOB_W + gap
		y += KNOB_H + 6.0
	# 7. the key line (the only one on the screen)
	if bool(spec.get("hint", true)):
		var hr := HintRow.new()
		hr.name = "Keys"
		hr.setup([["Q/E", String(ui.get("hint_witch", "소서리스"))], ["Enter", String(ui.get("hint_start", "시작"))], ["Esc", String(ui.get("hint_menu", "메뉴"))]], width)
		hr.position = Vector2(0, y)
		root.add_child(hr)
		y += hr.size.y
	root.size = Vector2(width, y)
	out["height"] = y
	return out
