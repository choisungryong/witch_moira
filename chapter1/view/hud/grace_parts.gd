extends RefCounted
## The picture parts of the grace screen (A8 G6; moved from the proposal folder; the proposal tools now read it from here).
## Parts here: GraceCard (a grade card), OwnedBand (owned spells strip), JackpotPlaque. The shared parts (Knob + handles(), SideNote, TitlePlaque, Candle, GradeFrame, Band, tex / art_rect / layer ...) live in ui_parts.gd (A10 W0).
## Material rule: the hand of the combat HUD (black leather, gold stitching, brass). Pictures come from the asset slots `ui.grace.*` (chapter1/art/asset_slots.json,
## T7): this file never names a picture file (ui_parts.gd reads the slots). A part whose picture is missing falls back to a piece of the HUD atlas, then to the code shapes of grace_draw.gd.
## Presentation only: nothing here reads or writes the core.
const Kit = preload("res://chapter1/view/hud/grace_draw.gd")
const AssetSlots = preload("res://chapter1/view/assets/asset_slots.gd")
const Palette = preload("res://chapter1/view/hud/palette.gd")
const UiStyle = preload("res://chapter1/view/hud/ui_style.gd")
const AtlasBox = preload("res://chapter1/view/hud/atlas_box.gd")
const Parts = preload("res://chapter1/view/hud/ui_parts.gd")
const Motion = preload("res://chapter1/view/hud/ui_motion.gd")
const Loc = preload("res://chapter1/view/loc.gd")
const PARTS_PATH := "res://chapter1/view/hud/grace_parts.gd"

# ============================================================ intro lengths (the one table is ui_motion.gd)
static func intro_seconds(kind: String) -> float:
	match kind:
		"long": return Motion.SCENE_IN_LONG
		"jackpot": return Motion.SCENE_IN_JACKPOT_MAX
	return Motion.SCENE_IN

## "jackpot" when any card is of the top grade, "long" for the first grace of a run (moment.kind "first"), else "normal".
static func intro_kind(contract: Dictionary) -> String:
	for c in contract.get("cards", []):
		if grade_key(String(c.get("grade", "common"))) == "jackpot": return "jackpot"
	if String(contract.get("moment", {}).get("kind", "normal")) == "first": return "long"
	return "normal"

# ============================================================ grades (spec 5.6)
## Fixture words (common / scarce / fated) and core words (common / rare / jackpot) both map to the three keys.
static func grade_key(g: String) -> String:
	match g:
		"rare", "scarce", "magic": return "rare"
		"jackpot", "fated", "legendary": return "jackpot"
	return "common"

static func grade_rank(key: String) -> int:
	return {"common": 0, "rare": 1, "jackpot": 2}.get(key, 0)

## common = INK, rare = QUALITY_RARE (the same colour as the rare gear), jackpot = gold.
static func name_color(key: String) -> Color:
	match key:
		"rare": return Palette.QUALITY_RARE
		"jackpot": return Palette.GRACE_JACKPOT
	return Palette.INK

## The word kit.gd's code face knows (used only by the code fallback).
static func _kit_grade(key: String) -> String:
	return {"common": "common", "rare": "scarce", "jackpot": "fated"}.get(key, "common")

# ============================================================ frame band of the grace pictures
## Frame band (the part text must stay inside) as fractions of the frame picture: Vector2(left / width, top / height). Measured on the three pictures.
const FRAME_BAND := {"common": Vector2(0.1055, 0.0807), "rare": Vector2(0.1016, 0.0781), "jackpot": Vector2(0.1299, 0.1107)}

static func frame_band(key: String) -> Vector2:
	return FRAME_BAND.get(key, Vector2(0.115, 0.082))

# ============================================================ GraceCard
## The shape of one card (spec 5.2) on a 300 x 470 reference; every size scales with min(w/300, h/470) but no text goes below 14.
##   top row: element badge + header .......... grade diamonds + grade name   (rare / jackpot only; the common card has no grade word)
##   emblem (46% of the height)  ->  name 26  ->  tag 15  ->  number 30 "before -> after ^" (or the one-line text of a new card)  ->  combo row
## Grade reads by FORM first (steel straight / bronze with spikes / gold with crown spikes), then the ground brightness, then the name colour.
class GraceCard extends Control:
	signal clicked(i: int)
	signal hovered(i: int)
	var P = load(PARTS_PATH)
	var idx := 0
	var data := {}
	var gkey := "common"
	var art_face := false
	var focus := 0.0:
		set(v):
			focus = v
			if _fx != null: _fx.queue_redraw()
			if _under != null and not art_face: _under.queue_redraw()
	var leak := 0.0:
		set(v):
			leak = v
			if _fx != null: _fx.queue_redraw()
	var rim := -1.0:   ## G4: a light running once round the frame (0..1); a rare card's reveal
		set(v):
			rim = v
			if _fx != null: _fx.queue_redraw()
	var sweep := -1.0:
		set(v):
			sweep = v
			if _fx != null: _fx.queue_redraw()
	var face_up := true:
		set(v):
			face_up = v
			for n in _front: n.visible = v
			if _back != null: _back.visible = not v
			if _fx != null: _fx.queue_redraw()
	var animated := true
	var emblem_box := Rect2()   ## the medallion, in card coordinates (a flying mark starts here)
	var row_y := 0.0
	var grade_text_w := 0.0
	var _under: Control
	var _fx: Control
	var _back: Control
	var _sigil: Control
	var _front: Array = []
	var _art_nodes: Array = []   ## the picture layers (dimmed by set_focus_amount); the TEXT keeps its full colour so it stays readable on a dimmed card

	func build(card: Dictionary, i: int, sz: Vector2, ui: Dictionary) -> void:
		idx = i
		data = card
		size = sz
		custom_minimum_size = sz
		pivot_offset = sz * 0.5
		mouse_filter = Control.MOUSE_FILTER_STOP
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		gkey = P.grade_key(String(card.get("grade", "common")))
		var el := String(card.get("element", "frost"))
		var w := sz.x
		var h := sz.y
		var s := minf(w / 300.0, h / 470.0)
		var band: Vector2 = P.frame_band(gkey) if Parts.tex("frame_" + gkey) != null else Vector2(0.115, 0.082)
		var inset := w * band.x + 8.0
		var inner := w - inset * 2.0
		var rank: int = P.grade_rank(gkey)
		art_face = Parts.tex("frame_" + gkey) != null and Parts.tex("bg_" + gkey) != null
		_under = Parts.layer(self, Callable(self, "_paint_under"))
		if art_face:
			var bg: Control = Parts.GradeFrame.ground(self, gkey, Rect2(Vector2.ZERO, sz))
			_front.append(bg)
			_art_nodes.append(bg)
			Parts.note_source("card ground", Parts.source_of("bg_" + gkey))
			var shade: Control = Parts.layer(self, Callable(self, "_paint_shade"))
			_front.append(shade)
			_art_nodes.append(shade)
		else:
			Parts.note_source("card ground", "code")
		_front.append(_under)
		_art_nodes.append(_under)
		# medallion: behind it the grade light (rare: a thin warm rim; jackpot: the turning sigil, additive)
		var emb := minf(w * 0.70, h * 0.44)
		emblem_box = Rect2(Vector2((w - emb) * 0.5, h * 0.145), Vector2(emb, emb))
		var ec := emblem_box.get_center()
		if rank >= 1:
			var halo: Control = Parts.glow_rect(self, ec, emb * (0.62 if rank == 1 else 0.78), Color(Palette.BRASS_HI.r, Palette.BRASS_HI.g, Palette.BRASS_HI.b, 0.22 if rank == 1 else 0.40))
			_front.append(halo)
		if rank >= 2:
			_sigil = Parts.art_rect(self, "sigil", Rect2(ec - Vector2(emb, emb) * 0.62, Vector2(emb, emb) * 1.24), {"add": true, "tint": Color(1, 1, 1, 0.55)})
			if _sigil != null:
				_front.append(_sigil)
				_art_nodes.append(_sigil)
				Parts.note_source("jackpot sigil", Parts.source_of("sigil"))
			else:
				Parts.note_source("jackpot sigil", "code")
		var en: String = Parts.emblem_name(el, String(card.get("kind", "new")))
		var sat: float = [0.8, 1.0, 1.1][rank]
		var emb_art: Control = Parts.art_rect(self, en, emblem_box, {"sat": sat, "bright": [0.92, 1.0, 1.06][rank]})
		if emb_art != null:
			_front.append(emb_art)
			_art_nodes.append(emb_art)
			Parts.note_source("card emblems", Parts.source_of(en))
		else:
			var ce = Kit.Emblem.new(String(card.get("emblem", "ring")), el, emblem_box.size, false)
			ce.position = emblem_box.position
			ce.tone = [0.6, 1.0, 1.0][rank]
			add_child(ce)
			_front.append(ce)
			_art_nodes.append(ce)
			Parts.note_source("card emblems (missing ones)", "code")
		if art_face:
			var fr: Control = Parts.GradeFrame.frame(self, gkey, Rect2(Vector2.ZERO, sz))
			_front.append(fr)
			_art_nodes.append(fr)
			Parts.note_source("card frames", Parts.source_of("frame_" + gkey))
		else:
			Parts.note_source("card frames", "code")
		# text
		row_y = h * 0.115
		var small := maxi(14, int(round(15.0 * s)))
		var grade_name := String(card.get("grade_name", ""))
		var gw := 0.0
		if rank >= 1 and grade_name != "":
			gw = Kit.measure(grade_name, small, 9999.0, "bold").x
			var gl: Label = Kit.lbl(self, grade_name, Vector2(w - inset - gw - 2.0, row_y), gw + 4.0, small, P.name_color(gkey), "bold", HORIZONTAL_ALIGNMENT_RIGHT, false, true)
			_front.append(gl)
		grade_text_w = gw
		var head_x := inset + 24.0 * s
		var head_w := inner - 24.0 * s - (gw + 14.0 + 12.0 * rank if gw > 0.0 else 0.0)
		var header := String(card.get("header", ""))
		if header != "":
			var hf: Dictionary = Parts.fit_text(header, maxi(14, int(round(14.0 * s))), head_w, "bold", 14)
			var hl: Label = Kit.lbl(self, String(hf.text), Vector2(head_x, row_y), head_w, int(hf.size), Palette.INK_DIM, "bold", HORIZONTAL_ALIGNMENT_LEFT, false, true)
			_front.append(hl)
		var y := emblem_box.end.y + h * 0.006
		var nf: Dictionary = Parts.fit_text(String(card.get("name", "")), maxi(16, int(round(26.0 * s))), inner, "heading", 16)
		var nl: Label = Kit.lbl(self, String(nf.text), Vector2(inset, y), inner, int(nf.size), P.name_color(gkey), "heading", HORIZONTAL_ALIGNMENT_CENTER, false, true)
		_front.append(nl)
		y += nl.size.y - 2.0
		var tag := String(card.get("kind_label", ""))
		if String(card.get("tier", "")) != "" and String(card.tier) != grade_name: tag += "  " + String(card.tier)
		var tf: Dictionary = Parts.fit_text(tag, small, inner, "bold", 14)
		var tl: Label = Kit.lbl(self, String(tf.text), Vector2(inset, y), inner, int(tf.size), Kit.el_text(el), "bold", HORIZONTAL_ALIGNMENT_CENTER, false, true)
		_front.append(tl)
		y += tl.size.y + 2.0
		var d: Variant = card.get("delta", null)
		if d is Dictionary:
			var num := "%s → %s ▲" % [d.before, d.after]
			var xf: Dictionary = Parts.fit_text(num, maxi(18, int(round(30.0 * s))), inner, "number", 18)
			var vl: Label = Kit.lbl(self, String(xf.text), Vector2(inset, y), inner, int(xf.size), Kit.GAIN, "number", HORIZONTAL_ALIGNMENT_CENTER, false, true)
			_front.append(vl)
			y += vl.size.y + 2.0
		else:
			var line := String(card.get("line", card.get("headline", "")))
			# a one-line summary of a new card; when it does not fit the room left (a small card) it is left to the side note, never cut
			var need: float = Kit.measure(line, small, inner, "body").y + 4.0
			if need <= h * 0.885 - y - (24.0 if card.get("combo", []).size() > 0 else 0.0):
				var ll: Label = Kit.lbl(self, line, Vector2(inset, y), inner, small, Palette.INK, "body", HORIZONTAL_ALIGNMENT_CENTER, true, true)
				_front.append(ll)
				y += ll.size.y + 2.0
		var combo: Array = card.get("combo", [])
		y += 10.0   ## a clear step above the combo row (a tilted card's text boxes must not touch in the layout check)
		var room := h * 0.885 - y
		if combo.size() > 0 and room >= 22.0 * s:
			var cw := Kit.measure(String(ui.get("combo", "")), small, 9999.0, "bold").x
			var ic := minf(24.0 * s + 2.0, 26.0)
			var total := cw + 8.0 + ic * 2.0 + 14.0
			var x0 := (w - total) * 0.5
			var cl: Label = Kit.lbl(self, String(ui.get("combo", "")), Vector2(x0, y + 1.0), cw + 4.0, small, Kit.el_text(el), "bold", HORIZONTAL_ALIGNMENT_LEFT, false, true)
			_front.append(cl)
			var c0: Dictionary = combo[0]
			var a: Control = Parts.spell_icon(self, String(c0["from"]), String(c0.from_element), Rect2(Vector2(x0 + cw + 8.0, y), Vector2(ic, ic)))
			var arrow: Label = Kit.lbl(self, "→", Vector2(x0 + cw + 8.0 + ic, y), 14.0, 14, Palette.LINEN, "bold", HORIZONTAL_ALIGNMENT_CENTER, false, true)
			var b: Control = Parts.spell_icon(self, String(c0["to"]), String(c0.to_element), Rect2(Vector2(x0 + cw + 8.0 + ic + 14.0, y), Vector2(ic, ic)))
			_front.append_array([cl, a, arrow, b])
		_back = _make_back()
		_back.visible = false
		_fx = Parts.layer(self, Callable(self, "_paint_fx"))
		_fx.name = "Fx"
		gui_input.connect(_on_gui_input)
		mouse_entered.connect(func(): hovered.emit(idx))
		set_process(_sigil != null)

	func _process(delta: float) -> void:
		if _sigil != null and animated: _sigil.rotation += delta * 0.18

	## The card's back: the HUD's leather plate with the brass cross medal (the seal), tinted by the element. (Used by the fan proposal.)
	func _make_back() -> Control:
		var back := Control.new()
		back.size = size
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var plate := Panel.new()
		plate.size = size
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := AtlasBox.new()
		box.piece = "notice_card"
		box.margins_px = Vector4(70, 70, 70, 70)
		box.line_color = Palette.BRASS_DIM
		plate.add_theme_stylebox_override("panel", box)
		back.add_child(plate)
		Parts.layer(back, Callable(self, "_paint_back"))
		add_child(back)
		return back

	func _paint_back(c: Control) -> void:
		var el := String(data.get("element", "frost"))
		UiStyle.blit_centered(c, "medal_cross", c.size * 0.5, minf(c.size.x / 184.0, c.size.y / 300.0) * 1.6)
		c.draw_arc(c.size * 0.5, minf(c.size.x, c.size.y) * 0.3, 0, TAU, 48, Kit.with_alpha(Kit.el_color(el), 0.55), 2.0, true)

	func _paint_under(c: Control) -> void:
		if art_face: return
		Kit.draw_face(c, Rect2(Vector2.ZERO, size), P._kit_grade(gkey), focus, 0.0)

	## A dark reading ground under the lower text so 4.5:1 holds on every grade ground.
	func _paint_shade(c: Control) -> void:
		var r := Rect2(Vector2(0, size.y * 0.5), Vector2(size.x, size.y * 0.5))
		Kit.quad(c, r, Color(0.02, 0.015, 0.01, 0.0), Color(0.02, 0.015, 0.01, 0.62))
		Kit.quad(c, Rect2(Vector2.ZERO, Vector2(size.x, size.y * 0.14)), Color(0.02, 0.015, 0.01, 0.45), Color(0.02, 0.015, 0.01, 0.0))

	## Top row marks (element badge, grade diamonds), the focus ring, the seeping grade light, the sweep.
	func _paint_fx(c: Control) -> void:
		if not face_up:
			_paint_back_fx(c)
			return
		var el := String(data.get("element", "frost"))
		var s := minf(size.x / 300.0, size.y / 470.0)
		var fb: Vector2 = P.frame_band(gkey) if art_face else Vector2(0.115, 0.082)
		var inset := size.x * fb.x + 8.0
		var rank: int = P.grade_rank(gkey)
		Kit.draw_badge(c, el, Vector2(inset + 9.0 * s, row_y + 10.0), 7.0 * s + 1.0, Kit.el_color(el))
		var gc: Color = P.name_color(gkey)
		for k in rank:
			Kit.diamond(c, Vector2(size.x - inset - grade_text_w - 12.0 - float(k) * 13.0, row_y + 10.0), 5.0, gc, true)
		if leak > 0.0:
			for k in 7:
				c.draw_rect(Rect2(Vector2.ZERO, size).grow(float(k) * 3.0), Kit.with_alpha(gc, 0.30 * leak * (1.0 - float(k) / 7.0)), false, 3.0)
		if focus > 0.0:
			for k in 6:
				c.draw_rect(Rect2(Vector2.ZERO, size).grow(float(k) * 3.0 + 1.0), Kit.with_alpha(Palette.BRASS_HI, 0.26 * focus * (1.0 - float(k) / 6.0)), false, 3.0)
			c.draw_rect(Rect2(Vector2.ZERO, size), Kit.with_alpha(Palette.BRASS_HI, focus), false, 3.0)
		if rim >= 0.0 and rim <= 1.0:
			var per := 2.0 * (size.x + size.y)
			var tail := per * 0.16
			var pts := PackedVector2Array()
			for k in 13:
				pts.append(_perim(c, fposmod(rim * per - tail * float(k) / 12.0, per)))
			for k in 12:
				c.draw_line(pts[k], pts[k + 1], Kit.with_alpha(gc.lightened(0.25), 0.9 * (1.0 - float(k) / 12.0)), 5.0 - 3.0 * float(k) / 12.0)
		if sweep >= 0.0 and sweep <= 1.0:
			var x := -50.0 + (size.x + 100.0) * sweep
			var band := PackedVector2Array([Vector2(x, 0), Vector2(x + 34, 0), Vector2(x - 20, size.y), Vector2(x - 54, size.y)])
			c.draw_colored_polygon(band, Kit.with_alpha(gc.lightened(0.3), 0.20))

	func _perim(_c: Control, s: float) -> Vector2:
		var w := size.x
		var h := size.y
		if s < w: return Vector2(s, 0)
		s -= w
		if s < h: return Vector2(w, s)
		s -= h
		if s < w: return Vector2(w - s, h)
		s -= w
		return Vector2(0, h - s)

	func _paint_back_fx(c: Control) -> void:
		if leak > 0.0:
			for k in 7:
				c.draw_rect(Rect2(Vector2.ZERO, size).grow(float(k) * 3.0), Kit.with_alpha(P.name_color(gkey), 0.36 * leak * (1.0 - float(k) / 7.0)), false, 3.0)

	## One call sets the whole reaction of a card: focus 0..1 -> ring, brightness, a small lift (scale <= 1.03).
	func set_focus_amount(f: float, mult := 1.0) -> void:
		focus = f
		var tone := lerpf(0.68, 1.0, f) * mult
		for n in _art_nodes: n.modulate = Color(tone, tone, tone * 1.03, 1.0)
		scale = Vector2.ONE * (1.0 + 0.03 * f)

	## Where the mark of this card starts a flight (global coordinates).
	func emblem_center() -> Vector2:
		return get_global_transform() * emblem_box.get_center()

	func _on_gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: clicked.emit(idx)

static func card(parent: Control, data: Dictionary, idx: int, size: Vector2, ui: Dictionary) -> GraceCard:
	var c := GraceCard.new()
	c.build(data, idx, size, ui)
	parent.add_child(c)
	return c
# ============================================================ OwnedBand (owned spells strip)
## HUD leather strip (strip_left + tiled strip_tile + strip_right) with brass ring slots (slot_normal). Slots: the run's spells (picture + level),
## empty slots ("+"), the grace slots (smaller rings, a diamond when owned), the odds line at the right end. Same helpers as kit.gd's OwnedRow
## (slot_centre / target_for / link_slots / lit / lit_amount / pulse) so a chosen mark can fly to its slot.
class OwnedBand extends Control:
	const H := 66.0
	var P = load(PARTS_PATH)
	var owned := {}
	var ui := {}
	var chip := 52.0
	var centres := {"spell": [], "grace": []}
	var lit: Array = []
	var lit_amount := 0.0:
		set(v):
			lit_amount = v
			if _over != null: _over.queue_redraw()
	var pulse := 0.0:
		set(v):
			pulse = v
			if _over != null: _over.queue_redraw()
	var _over: Control
	var _under: Control

	func build(o: Dictionary, strings: Dictionary, odds: String, w: float) -> void:
		owned = o
		ui = strings
		size = Vector2(w, H)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_under = Parts.layer(self, Callable(self, "_paint_strip"))
		var x := 118.0
		var lb := Kit.lbl(self, String(ui.get("owned", "")), Vector2(x, H * 0.5 - 11.0), 100.0, 15, Palette.INK, "bold", HORIZONTAL_ALIGNMENT_LEFT, false, true)
		x += Kit.measure(String(ui.get("owned", "")), 15, 9999.0, "bold").x + 14.0
		centres.spell = []
		var spells: Array = o.get("spells", [])
		for i in int(o.get("slots", 3)):
			var c := Vector2(x + chip * 0.5, H * 0.5)
			centres.spell.append(c)
			if i < spells.size():
				Parts.spell_icon(self, String(spells[i].emblem), String(spells[i].element), Rect2(c - Vector2(chip, chip) * 0.43, Vector2(chip, chip) * 0.86))
				var lv := Kit.lbl(self, String(spells[i].level), c + Vector2(chip * 0.18, chip * 0.14), 22.0, 14, Palette.INK, "number", HORIZONTAL_ALIGNMENT_CENTER, false, true)
				lv.name = "Level%d" % i
			x += chip + 8.0
		x += 14.0
		var gtext := String(ui.get("graces", ""))
		Kit.lbl(self, gtext, Vector2(x, H * 0.5 - 11.0), 70.0, 15, Palette.INK, "bold", HORIZONTAL_ALIGNMENT_LEFT, false, true)
		x += Kit.measure(gtext, 15, 9999.0, "bold").x + 12.0
		centres.grace = []
		for i in int(o.get("grace_slots", 2)):
			centres.grace.append(Vector2(x + chip * 0.3, H * 0.5))
			x += chip * 0.6 + 8.0
		if odds != "":
			var ow := Kit.measure(odds, 15, 9999.0, "body").x + 6.0
			var ox := maxf(x + 12.0, w - 96.0 - ow)
			Kit.lbl(self, odds, Vector2(ox, H * 0.5 - 11.0), ow, 15, Palette.INK_DIM, "body", HORIZONTAL_ALIGNMENT_RIGHT, false, true).name = "Odds"
		_over = Parts.layer(self, Callable(self, "_paint_rings"))
		Parts.note_source("owned band", "atlas")

	func _paint_strip(c: Control) -> void:
		Parts.Band.paint(c, size.x, H)
		var spells: Array = owned.get("spells", [])
		for i in centres.spell.size():
			var ctr: Vector2 = centres.spell[i]
			c.draw_circle(ctr, chip * 0.44, Color(0.015, 0.018, 0.02, 0.95))
			if i >= spells.size():
				c.draw_string(Loc.font("number"), ctr + Vector2(-5.0, 7.0), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Kit.with_alpha(Palette.BRASS, 0.8))
		for i in centres.grace.size():
			c.draw_circle(centres.grace[i], chip * 0.27, Color(0.015, 0.018, 0.02, 0.95))

	func _paint_rings(c: Control) -> void:
		for i in centres.spell.size():
			UiStyle.blit_centered(c, "slot_normal", centres.spell[i], chip / 80.0)
			if i in lit and lit_amount > 0.0:
				UiStyle.blit_centered(c, "slot_selected", centres.spell[i], chip / 80.0 * 1.12, Color(1, 1, 1, lit_amount))
		var graces: Array = owned.get("graces", [])
		for i in centres.grace.size():
			UiStyle.blit_centered(c, "slot_normal", centres.grace[i], chip * 0.6 / 80.0)
			if i < graces.size() and bool(graces[i].owned): Kit.diamond(c, centres.grace[i], chip * 0.16, Palette.GROWTH)
		if pulse > 0.0 and not centres.spell.is_empty():
			var tgt: Vector2 = centres.spell[mini((owned.get("spells", []) as Array).size(), centres.spell.size() - 1)]
			c.draw_arc(tgt, chip * (0.5 + 0.6 * (1.0 - pulse)), 0, TAU, 32, Kit.with_alpha(Palette.BRASS_HI, pulse), 3.0, true)

	func link_slots(card: Dictionary) -> Array:
		var out: Array = []
		for cb in card.get("combo", []):
			for end in ["from", "to"]:
				var k := String(cb[end])
				var e := String(cb[end + "_element"])
				if k == String(card.get("emblem", "")) and e == String(card.get("element", "")): continue
				for i in (owned.get("spells", []) as Array).size():
					var sp: Dictionary = owned.spells[i]
					if String(sp.emblem) == k and String(sp.element) == e and not i in out: out.append(i)
		return out

	func slot_centre(kind: String, index: int) -> Vector2:
		var arr: Array = centres[kind]
		if arr.is_empty(): return size * 0.5
		return arr[clampi(index, 0, arr.size() - 1)]

	## Where a chosen card lands (global): a new spell takes the first free slot, an upgrade its own chip, a grace the grace row.
	func target_for(card: Dictionary) -> Vector2:
		var spells: Array = owned.get("spells", [])
		if String(card.get("kind", "")) == "prep":
			var gi := 0
			for g in owned.get("graces", []):
				if bool(g.owned): gi += 1
			return global_position + slot_centre("grace", gi)
		if String(card.get("kind", "")) in ["new", "trade"]:
			return global_position + slot_centre("spell", spells.size())
		var si := 0
		for i in spells.size():
			if String(spells[i].name) == String(card.get("name", "")): si = i
		return global_position + slot_centre("spell", si)

static func band(parent: Control, pos: Vector2, width: float, contract: Dictionary) -> OwnedBand:
	var b := OwnedBand.new()
	b.build(contract.get("owned", {}), contract.get("strings", {}), String(contract.get("odds", "")), width)
	b.position = pos
	parent.add_child(b)
	return b
## The stamped "jackpot" word: a cast plate with amber inlay. Art N3, else the HUD name plate in amber with a crown of spikes drawn in code.
class JackpotPlaque extends Control:
	var P = load(PARTS_PATH)
	func build(text: String, sz: Vector2) -> void:
		size = sz
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		pivot_offset = sz * 0.5
		if Parts.tex("jackpot_plaque") != null:
			Parts.art_rect(self, "jackpot_plaque", Rect2(Vector2.ZERO, sz))
			Parts.note_source("jackpot plaque", Parts.source_of("jackpot_plaque"))
		else:
			var panel := Panel.new()
			panel.size = sz
			panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var box := AtlasBox.new()
			box.piece = "boss_name"
			box.margins_px = Vector4(80, 34, 80, 34)
			box.tint = Color(1.15, 0.78, 0.42)
			panel.add_theme_stylebox_override("panel", box)
			add_child(panel)
			Parts.layer(self, Callable(self, "_paint_crown"))
			Parts.note_source("jackpot plaque", "atlas")
		var fs: int = Parts.fit_size(text, 38, sz.x * 0.8, "heading", 22)
		var tl: Label = Kit.lbl(self, text, Vector2(sz.x * 0.1, sz.y * 0.5 - Kit.line_height(fs, "heading") * 0.5 + 2.0), sz.x * 0.8, fs, Palette.GRACE_JACKPOT, "heading", HORIZONTAL_ALIGNMENT_CENTER, false, true)
		tl.name = "Word"

	func _paint_crown(c: Control) -> void:
		var col: Color = Palette.GRACE_JACKPOT
		c.draw_rect(Rect2(Vector2(6, 6), size - Vector2(12, 12)), Kit.with_alpha(col, 0.8), false, 2.0)
		for k in 5:
			var x := size.x * (0.18 + 0.16 * float(k))
			var hgt := 16.0 if k == 2 else 10.0
			c.draw_colored_polygon(PackedVector2Array([Vector2(x - 9, 7), Vector2(x, 7 - hgt), Vector2(x + 9, 7)]), col)

static func jackpot(parent: Control, text: String, sz: Vector2) -> JackpotPlaque:
	var p := JackpotPlaque.new()
	p.build(text, sz)
	parent.add_child(p)
	return p
