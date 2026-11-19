extends "res://chapter1/tests/proposals/growth_choice/base.gd"
## Proposal C "two beats" (the chosen direction). Everyday beat (this file): the combat stays visible on top, only a stone band
## under the cards is dark; three LOW cards (emblem, name, one line), the owned sockets below, a side frame for the focused card,
## a reroll handle, a small round portrait of the witch. Milestone beat (first / evolution / last grace): make() returns the
## scene of a_oath.gd (the mother's seat) with the sealed evolution card.
## Concept: usually a breath taken inside the fight; rarely a scene. What you take is socketed into the row you already carry.

const A = preload("res://chapter1/tests/proposals/growth_choice/a_oath.gd")
const CARD_W := 330.0
const CARD_H := 190.0
const X0 := 300.0
const GAP := 12.0
const Y0 := 560.0

var backdrop: Control
var band: Control
var portrait: Control
var glow: TextureRect
var hcards: Array = []
var rest: Array = []
var side
var owned_row
var handle
var links
var head_group: Control

static func make(c: Dictionary) -> Control:
	if String(c.moment.beat) == "long":
		return A.make(c)
	var s = load("res://chapter1/tests/proposals/growth_choice/c_two_beat.gd").new()
	s.setup(c)
	return s

## The low card. Face from Kit.draw_face (stone, grade frame form), emblem left, name / tag / one line at right.
class HCard extends Control:
	signal clicked(i: int)
	signal hovered(i: int)
	var idx := 0
	var data := {}
	var focus := 0.0:
		set(v):
			focus = v
			queue_redraw()
	var sweep := -1.0:
		set(v):
			sweep = v
			queue_redraw()
	var emblem: Control
	var chip_pos := Vector2.ZERO
	var meter_pos := Vector2.ZERO
	var kit
	func build(card: Dictionary, i: int, w: float, h: float) -> void:
		kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		idx = i
		data = card
		size = Vector2(w, h)
		custom_minimum_size = size
		pivot_offset = size * 0.5
		mouse_filter = Control.MOUSE_FILTER_STOP
		var P = kit.Palette
		emblem = kit.Emblem.new(String(card.emblem), String(card.element), Vector2(112, 112), true)
		emblem.position = Vector2(16, (h - 112.0) * 0.5)
		add_child(emblem)
		var x := 140.0
		var cw := w - x - 14.0
		var y := 12.0
		var hd: Variant = card.get("header", null)
		if hd != null and String(hd) != "":
			kit.lbl(self, String(hd), Vector2(x, y), cw - 28.0, 14, kit.el_text(String(card.element)), "bold", HORIZONTAL_ALIGNMENT_LEFT, false)
		y += 21.0
		kit.lbl(self, String(card.name), Vector2(x, y), cw, 24, P.INK, "heading", HORIZONTAL_ALIGNMENT_LEFT, false)
		y += 39.0
		var tag := String(card.kind_label)
		if String(card.get("tier", "")) != "": tag += "  " + String(card.tier)
		kit.lbl(self, tag, Vector2(x, y), cw, 15, kit.el_text(String(card.element)), "bold", HORIZONTAL_ALIGNMENT_LEFT, false)
		y += 22.0
		chip_pos = Vector2(x + 6.0, y + 11.0)
		kit.lbl(self, String(card.grade_name), Vector2(x + 22.0, y), cw - 22.0, 14, kit.grade_color(String(card.grade)), "bold", HORIZONTAL_ALIGNMENT_LEFT, false)
		y += 24.0
		var d: Variant = card.get("delta", null)
		if d is Dictionary:
			var dtext := "%s → %s ▲" % [d.before, d.after]
			var dsize := 22
			while dsize > 15 and kit.Loc.font("number").get_string_size(dtext, HORIZONTAL_ALIGNMENT_LEFT, -1, dsize).x > cw - 4.0: dsize -= 1
			kit.lbl(self, dtext, Vector2(x, y - 2.0), cw, dsize, kit.GAIN, "number", HORIZONTAL_ALIGNMENT_LEFT, false)
		else:
			kit.lbl(self, String(card.get("line", card.headline)), Vector2(x, y), cw, 15, P.INK, "body")
		var k: Label = kit.lbl(self, str(i + 1), Vector2(w - 34.0, 8.0), 24, 16, P.INK, "number", HORIZONTAL_ALIGNMENT_CENTER, false)
		k.name = "Key"
		gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: clicked.emit(idx))
		mouse_entered.connect(func(): hovered.emit(idx))
	func set_focus_amount(f: float) -> void:
		focus = f
		if emblem != null: emblem.set("tone", 0.3 + 0.7 * f)
		modulate = Color(0.7, 0.7, 0.72, 1.0).lerp(Color.WHITE, f)
		scale = Vector2.ONE * (1.0 + 0.03 * f)
	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		kit.draw_face(self, rect, String(data.grade), focus)
		var rank: int = kit.grade_rank(String(data.grade))
		var gc: Color = kit.grade_color(String(data.grade))
		kit.draw_badge(self, String(data.element), Vector2(size.x - 56.0, 22.0), 8.0, kit.el_color(String(data.element)))
		draw_circle(Vector2(size.x - 22.0, 22.0), 13.0, Color(0.02, 0.025, 0.03, 0.8))
		draw_arc(Vector2(size.x - 22.0, 22.0), 13.0, 0, TAU, 20, kit.Palette.BRASS, 1.5, true)
		kit.diamond(self, chip_pos, 5.0 + float(rank), gc, rank >= 1, 2.0)
		if data.get("meter", null) is Dictionary:
			var m: Dictionary = data.meter
			for q in int(m.total):
				var p := Vector2(150.0 + q * 20.0, size.y - 18.0)
				if q < int(m.filled): draw_circle(p, 5.5, kit.el_color(String(data.element)))
				else: draw_arc(p, 5.5, 0, TAU, 14, kit.Palette.INK_FAINT, 1.5, true)
		if sweep >= 0.0 and sweep <= 1.0:
			var xx := -50.0 + (size.x + 100.0) * sweep
			draw_colored_polygon(PackedVector2Array([Vector2(xx, 0), Vector2(xx + 40, 0), Vector2(xx - 20, size.y), Vector2(xx - 60, size.y)]), Color(1, 1, 1, 0.13))

class Band extends Control:
	func _init() -> void:
		size = Vector2(1600, 900)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		kit.quad(self, Rect2(0, 440, 1600, 100), Color(0.015, 0.018, 0.024, 0.0), Color(0.015, 0.018, 0.024, 0.9))
		draw_rect(Rect2(0, 540, 1600, 360), Color(0.02, 0.022, 0.028, 0.93))
		# metal rail with studs, the top edge of the stone band
		draw_rect(Rect2(0, 536, 1600, 6), Color(0.42, 0.36, 0.26, 0.95))
		draw_rect(Rect2(0, 536, 1600, 1), Color(1, 0.95, 0.8, 0.35))
		draw_rect(Rect2(0, 542, 1600, 3), Color(0, 0, 0, 0.6))
		for k in 13: kit.diamond(self, Vector2(40.0 + k * 128.0, 539), 5.0, Color(0.55, 0.47, 0.33))

const ROUND := "shader_type canvas_item;\nvoid fragment(){ vec4 c = texture(TEXTURE, UV); float d = distance(UV, vec2(0.5)); COLOR = vec4(c.rgb, c.a * (1.0 - smoothstep(0.47, 0.5, d))); }\n"

func _build() -> void:
	var m: Dictionary = contract.moment
	var el := String(contract.witch.element)
	backdrop = Kit.make_backdrop(self, String(contract.backdrop), 0.08, 0.35)
	band = Band.new()
	add_child(band)
	# round portrait: the witch's face from her own painting, in a metal ring tinted by the focused element
	var wid := String(contract.witch.id)
	glow = Kit.add_glow(self, Vector2(150, 655), 150, Kit.with_alpha(Kit.el_color(el), 0.0))
	portrait = Control.new()
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(portrait)
	var pic := TextureRect.new()
	pic.texture = Kit.witch_crop(wid, Kit.FACE_CROP[wid])
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.size = Vector2(168, 168)
	pic.position = Vector2(66, 571)
	var sh := Shader.new()
	sh.code = ROUND
	var mat := ShaderMaterial.new()
	mat.shader = sh
	pic.material = mat
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.add_child(pic)
	var ring := Ring.new()
	ring.element = el
	ring.position = Vector2(66, 571)
	ring.size = Vector2(168, 168)
	portrait.add_child(ring)
	# head line: title, pips
	head_group = Control.new()
	head_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head_group)
	Kit.lbl(head_group, String(ui.title), Vector2(X0, 506), 120, 24, Palette.INK, "heading", HORIZONTAL_ALIGNMENT_LEFT, false, true)
	# the title sits above the rail: keep it on the stone band instead
	var tl: Label = head_group.get_child(0)
	tl.position = Vector2(66, 752)
	tl.size = Vector2(168, 34)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var pips := Parts.Pips.new(int(m.total), int(m.index))
	pips.position = Vector2(150.0 - pips.size.x * 0.5, 792)
	head_group.add_child(pips)
	Kit.lbl(head_group, String(m.label), Vector2(66, 812), 168, 14, Palette.INK_DIM, "number", HORIZONTAL_ALIGNMENT_CENTER, false)
	# cards
	for i in cards.size():
		var c := HCard.new()
		c.build(cards[i], i, CARD_W, CARD_H)
		var p := Vector2(X0 + float(i) * (CARD_W + GAP), Y0)
		c.position = p
		rest.append(p)
		c.set_focus_amount(0.0)
		c.clicked.connect(func(k): try_pick(k))
		c.hovered.connect(func(k): set_focus(k))
		add_child(c)
		hcards.append(c)
	var sx := X0 + 3.0 * (CARD_W + GAP) - GAP + 14.0
	side = Parts.SidePanel.new()
	side.position = Vector2(sx, 250)
	side.setup(1580.0 - sx, Y0 + CARD_H - 250.0, ui)
	add_child(side)
	side.show_card(cards[0], false)
	side.modulate.a = 0.0
	owned_row = Kit.OwnedRow.new()
	owned_row.build(contract.owned, ui, 50.0)
	owned_row.position = Vector2(X0, 790)
	add_child(owned_row)
	handle = Kit.Handle.new()
	handle.build(String(ui.key_reroll), String(ui.reroll), String(contract.reroll.left_label), 240.0, 46.0)
	handle.position = Vector2(1580.0 - 240.0, 788)
	handle.pressed.connect(func(): reroll_requested.emit())
	add_child(handle)
	Kit.lbl(self, String(ui.hint), Vector2(X0 + 480.0, 806), 400, 14, Palette.INK_FAINT, "body", HORIZONTAL_ALIGNMENT_LEFT, false)
	links = Parts.LinkLayer.new()
	add_child(links)

class Ring extends Control:
	var element := "frost"
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		var c := size * 0.5
		draw_arc(c, 84.0, 0, TAU, 48, Color(0.42, 0.36, 0.26), 6.0, true)
		draw_arc(c, 88.0, 0, TAU, 48, Color(0, 0, 0, 0.7), 2.0, true)
		draw_arc(c, 81.0, 0, TAU, 48, kit.with_alpha(kit.el_color(element), 0.8), 1.5, true)
		for k in 4: kit.diamond(self, c + Vector2.from_angle(float(k) * PI * 0.5) * 86.0, 5.0, Color(0.6, 0.52, 0.36))

func _intro() -> float:
	# short beat: the band rises and the cards fade in together (E 0.12 s, t_c 0.12)
	band.modulate.a = 0.0
	track(create_tween()).tween_property(band, "modulate:a", 1.0, 0.12)
	for n in [portrait, head_group, side, owned_row, handle]:
		n.modulate.a = 0.0
		track(create_tween()).tween_property(n, "modulate:a", 1.0, 0.12)
	for i in hcards.size():
		var c: Control = hcards[i]
		c.modulate.a = 0.0
		c.position.y = float(rest[i].y) + 14.0
		var tw := track(create_tween()).set_parallel(true)
		tw.tween_property(c, "modulate:a", 1.0, 0.12)
		tw.tween_property(c, "position:y", rest[i].y, 0.12).set_ease(Tween.EASE_OUT)
	var tf := track(create_tween())
	tf.tween_interval(0.12)
	tf.tween_callback(func(): if focus_index < 0: set_focus(0))
	return 0.12

func _settle_all() -> void:
	for n in [band, portrait, head_group, side, owned_row, handle]: n.modulate.a = 1.0
	for i in hcards.size():
		hcards[i].position = rest[i]
		hcards[i].modulate.a = 1.0
	if focus_index < 0: set_focus(0)

func _focus_changed(_old: int, new: int) -> void:
	for i in hcards.size():
		var c = hcards[i]
		var f := 1.0 if i == new else 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_method(c.set_focus_amount, c.focus, f, 0.14)
		tw.tween_property(c, "position:y", float(rest[i].y) - (8.0 if i == new else 0.0), 0.14).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	create_tween().tween_property(hcards[new], "sweep", 1.0, 0.28).from(0.0)
	side.show_card(cards[new])
	side.modulate.a = 1.0
	create_tween().tween_property(glow, "modulate", Kit.with_alpha(Kit.el_color(String(cards[new].element)), 0.45), 0.2)
	var slots: Array = owned_row.link_slots(cards[new])
	owned_row.lit = slots
	links.links = []
	var target := Vector2(float(rest[new].x) + CARD_W * 0.5, float(rest[new].y) + CARD_H)
	for s in slots:
		links.links.append([owned_row.global_position + owned_row.slot_centre("spell", s) + Vector2(0, -26), target])
	links.amount = 0.0
	owned_row.lit_amount = 0.0
	var tl := create_tween().set_parallel(true)
	tl.tween_property(links, "amount", 1.0, 0.22)
	tl.tween_property(owned_row, "lit_amount", 1.0, 0.22)

func _confirm_anim(i: int) -> float:
	var c = hcards[i]
	var tgt: Vector2 = owned_row.target_for(cards[i])
	var tw := create_tween()
	tw.tween_property(c, "position:y", c.position.y - 8.0, 0.06)
	tw.set_parallel(true)
	tw.tween_property(c, "position", tgt - c.size * 0.5, 0.26).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(c, "scale", Vector2(0.14, 0.14), 0.26).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(c, "modulate:a", 0.0, 0.1).set_delay(0.22)
	for k in hcards.size():
		if k == i: continue
		var o = hcards[k]
		var tw2 := create_tween().set_parallel(true)
		tw2.tween_property(o, "modulate:a", 0.0, 0.2)
		tw2.tween_property(o, "position:y", o.position.y + 18.0, 0.2)
	create_tween().tween_property(links, "amount", 0.0, 0.15)
	create_tween().tween_property(side, "modulate:a", 0.0, 0.15)
	var t3 := create_tween()
	t3.tween_interval(0.32)
	t3.tween_callback(func(): _dock(i, tgt))
	return 0.6

func _dock(i: int, tgt: Vector2) -> void:
	var card: Dictionary = cards[i]
	var em := Kit.Emblem.new(String(card.emblem), String(card.element), Vector2(50, 50))
	em.position = owned_row.make_canvas_position_local(tgt) - Vector2(25, 25)
	owned_row.add_child(em)
	em.scale = Vector2(1.5, 1.5)
	em.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(em, "scale", Vector2.ONE, 0.16).set_ease(Tween.EASE_OUT)
	tw.tween_property(em, "modulate:a", 1.0, 0.1)
	owned_row.pulse = 1.0
	create_tween().tween_property(owned_row, "pulse", 0.0, 0.28)
	var gl := Kit.add_glow(owned_row, owned_row.make_canvas_position_local(tgt), 46.0, Kit.with_alpha(Kit.el_color(String(card.element)), 0.7))
	var t4 := create_tween()
	t4.tween_property(gl, "modulate:a", 0.0, 0.3)
	t4.tween_callback(gl.queue_free)
	mark("socketed")
