extends RefCounted
## The pieces of the three notices of A10 1.7 (N1 band, N1+ big band, N2 card), built from the kit: the leather band of ui.kit.band.notice, the title plaque and the
## taller band of ui.kit.band.notice_big, the grade frame of an item icon, the key plate. The HUD (chapter_hud.gd) owns when they appear and for how long;
## this file only makes them. Presentation only.
const Parts = preload("res://chapter1/view/hud/ui_parts.gd")
const UiStyle = preload("res://chapter1/view/hud/ui_style.gd")
const Palette = preload("res://chapter1/view/hud/palette.gd")
const Motion = preload("res://chapter1/view/hud/ui_motion.gd")
const Loc = preload("res://chapter1/view/loc.gd")
const PaintedSigil = preload("res://chapter1/view/equipment_sigil_quality35.gd")

const ARROW_UP := "▲"
const ARROW_DOWN := "▼"

## ---- N1: the band ----
## The leather band behind a one-line notice (ui.kit.band.notice, three-sliced), or the HUD's small plate when the picture is missing.
static func band_box() -> StyleBox:
	var s := UiStyle.kit_box("band_notice")
	if s == null: return UiStyle.plate()
	s.content_margin_left = s.texture_margin_left + 6.0
	s.content_margin_right = s.texture_margin_right + 6.0
	s.content_margin_top = 4.0
	s.content_margin_bottom = 4.0
	return s

## The width a band needs for `text` at the band's text size (one line, never wider than `limit`).
static func band_width(text: String, limit := 900.0) -> float:
	var box := band_box()
	var inner := Parts.text_width(text, 20, "body")
	return clampf(inner + box.content_margin_left + box.content_margin_right, 380.0, limit)

## ---- N2: the card ----
## The colour of an item name: the grade colour, except common which reads as plain ink (its grade colour is the dim-ink colour, ΔE 5, A10 1.8).
static func name_color(item: Dictionary) -> Color:
	var q := String(item.get("quality", "common"))
	return Palette.INK if q == "common" else Palette.quality_color(q, Palette.INK)

## The icon box of an item: its grade frame (the kit's when the grade pictures exist, else the code frame whose shape differs by grade) with the slot painting inside.
static func icon(item: Dictionary, edge := 64.0) -> Control:
	var box := Parts.GradeFrame.new()
	box.build(String(item.get("quality", "common")), Vector2(edge, edge))
	var painting: Texture2D = PaintedSigil.PAINTINGS.get(String(item.get("slot", "charm")), PaintedSigil.PAINTINGS["charm"])
	var inset := edge * 0.16
	var view := TextureRect.new()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.texture = painting
	view.position = Vector2(inset, inset)
	view.size = Vector2(edge - inset * 2.0, edge - inset * 2.0)
	box.add_child(view)
	return box

## A key plate with the key drawn on it (the atlas piece key_tag), as a control of its own size.
class KeyChip extends Control:
	var key := ""
	func _init(k := "") -> void:
		key = k
		var piece := UiStyle.piece_size("key_tag")
		custom_minimum_size = Vector2(maxf(piece.x, 40.0), piece.y)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	func _draw() -> void:
		var piece := UiStyle.piece_size("key_tag")
		var at := Vector2(size.x * 0.5, size.y * 0.5)
		UiStyle.blit_centered(self, "key_tag", at)
		var font := UiStyle.heading_font()
		draw_string_outline(font, at + Vector2(-30, 5), key, HORIZONTAL_ALIGNMENT_CENTER, 60, 14, 3, Color(0, 0, 0, 0.85))
		draw_string(font, at + Vector2(-30, 5), key, HORIZONTAL_ALIGNMENT_CENTER, 60, 14, Palette.INK)

## "[key plate] word" in one row.
static func key_hint(key: String, word: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(KeyChip.new(key))
	var l := UiStyle.text_label(word, "t7", "body", Palette.INK_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(l)
	return row

## Up to three changed rows of a preview (core pickup_verdict().top_rows), one line each: "label  before → after ▲" in GAIN, or ▼ in LOSS. The arrow comes with every
## line, so gain and loss part without colour. Returns null when there is nothing to show.
static func change_rows(rows: Array, width: float) -> Control:
	var shown := 0
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 1)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for row in rows:
		var change := String(row.get("change", "same"))
		if change == "same": continue
		var better := change == "better"
		var unit := Loc.t("unit." + String(row.unit_id)) if String(row.get("unit_id", "")) != "" else ""
		var label := Loc.t("stat.%s.label" % String(row.id))
		var line := "%s  %s → %s%s %s" % [label, Loc.dec(float(row.before), int(row.decimals)), Loc.dec(float(row.after), int(row.decimals)), unit, ARROW_UP if better else ARROW_DOWN]
		if String(row.get("kind", "number")) == "flag": line = "%s %s" % [label, ARROW_UP if better else ARROW_DOWN]
		var l := UiStyle.text_label(line, "t7", "body", Palette.GAIN if better else Palette.LOSS)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.custom_minimum_size.x = width
		l.tooltip_text = line
		column.add_child(l)
		shown += 1
	if shown == 0:
		column.queue_free()
		return null
	return column

## ---- N1+: the big band ----
## The champion's entrance and other turns of the run (A10 1.7): the title plaque with the name, and under it the taller leather band with one line. It lands from above
## over Motion.BIG_BAND_IN with a two pixel tremble, stays Motion.BIG_BAND_HOLD, leaves over Motion.BIG_BAND_OUT. `danger` lights the plaque once in the threat colour.
## Reduced motion: no fall and no tremble, only the fade.
class BigBand extends Control:
	const PLAQUE_W := 400.0
	const BAND_W := 560.0
	const BAND_H := 68.0
	var holder: Control
	var finished := false
	signal done

	func build(title: String, sub: String, danger: bool) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		holder = Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(holder)
		var plaque_h := PLAQUE_W / 3.0
		size = Vector2(BAND_W, plaque_h + BAND_H - 22.0)
		custom_minimum_size = size
		holder.size = size
		if sub != "":
			var band := Panel.new()
			band.mouse_filter = Control.MOUSE_FILTER_IGNORE
			band.position = Vector2(0, plaque_h - 24.0)
			band.size = Vector2(BAND_W, BAND_H)
			var box := UiStyle.kit_box("band_notice_big")
			band.add_theme_stylebox_override("panel", box if box != null else UiStyle.plate())
			holder.add_child(band)
			var line := UiStyle.text_label(sub, "t4", "body", Palette.INK)
			line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			line.autowrap_mode = TextServer.AUTOWRAP_OFF
			line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			line.position = Vector2(110.0, plaque_h - 24.0 + 22.0)
			line.size = Vector2(BAND_W - 220.0, BAND_H - 36.0)
			holder.add_child(line)
		if danger:
			var glow := Parts.glow_rect(holder, Vector2(BAND_W * 0.5, plaque_h * 0.5), 150.0, Color(Palette.THREAT.r, Palette.THREAT.g, Palette.THREAT.b, 0.0))
			glow.name = "ThreatGlow"
			var pulse := create_tween()
			pulse.tween_property(glow, "modulate:a", 0.55, 0.25)
			pulse.tween_property(glow, "modulate:a", 0.0, 0.9)
		var plaque := Parts.title(holder, title, PLAQUE_W, "", 30)
		plaque.position = Vector2((BAND_W - PLAQUE_W) * 0.5, 0.0)

	## 0..1 like WindowFrame.fade: modulate plus the pictures of the art shader.
	var fade := 1.0:
		set(value):
			fade = value
			modulate.a = value
			Parts.set_art_alpha(self, value)

	func play(reduce: bool) -> void:
		fade = 0.0
		var tween := create_tween()
		if reduce:
			tween.tween_property(self, "fade", 1.0, Motion.WINDOW_OUT)
		else:
			holder.position.y = -56.0
			tween.set_parallel(true)
			tween.tween_property(holder, "position:y", 0.0, Motion.BIG_BAND_IN).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(self, "fade", 1.0, Motion.BIG_BAND_IN * 0.6)
			tween.chain().tween_method(_tremble, 0.0, 1.0, 0.22)
		tween.chain().tween_interval(Motion.BIG_BAND_HOLD)
		tween.chain().tween_property(self, "fade", 0.0, Motion.BIG_BAND_OUT)
		tween.chain().tween_callback(func(): finished = true; done.emit(); queue_free())

	func _tremble(t: float) -> void:
		holder.position.x = sin(t * 38.0) * 2.0 * (1.0 - t)

	## Takes the band away at once (a newer announcement is coming): a 0.12 s fade.
	func dismiss() -> void:
		if finished: return
		finished = true
		var tween := create_tween()
		tween.tween_property(self, "fade", 0.0, Motion.WINDOW_OUT)
		tween.tween_callback(queue_free)
