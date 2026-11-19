extends "res://chapter1/tests/proposals/growth_choice/base.gd"
## Proposal A "oath seat" = the SCENE of the milestone screens (first grace, evolution, last grace) in the chosen direction
## ("two beats", docs/reviews/BENCHMARK-GROWTH-SCREEN 4): the mother's shadow at the left, the receiving witch in front of her,
## a name plate on top, three tall cards with a side frame, the owned sockets below. The evolution card is sealed and is opened last.
## Concept: the giver and the receiver stand in one place; what you take is socketed into what you already carry.
## Placeholders (NEW ART NEEDED): the mother is a code-drawn silhouette on a cloth-weave panel (Kit.Mother), card emblems are code-drawn.

const CARD_W := 250.0
const CARD_H := 480.0
const X0 := 462.0
const GAP := 16.0
const Y0 := 188.0

var backdrop: Control
var mother: Control
var witch_pic: TextureRect
var witch_glow: TextureRect
var thread: Control
var vcards: Array = []
var seals := {}
var side
var owned_row
var handle
var links
var title_group: Control
var particles: CPUParticles2D
var rest: Array = []

static func make(c: Dictionary) -> Control:
	var s = load("res://chapter1/tests/proposals/growth_choice/a_oath.gd").new()
	s.setup(c)
	return s

class ThreadLine extends Control:
	var progress := 0.0:
		set(v):
			progress = v
			queue_redraw()
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var kit
	func _init() -> void:
		size = Vector2(1600, 900)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
	func _draw() -> void:
		if progress <= 0.0: return
		var ctrl := Vector2((a.x + b.x) * 0.5 - 20.0, maxf(a.y, b.y) + 150.0)
		var pts := PackedVector2Array()
		for i in 41:
			var t := float(i) / 40.0 * progress
			pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
		draw_polyline(pts, Color(0, 0, 0, 0.5), 5.0, true)
		draw_polyline(pts, kit.with_alpha(kit.Palette.LINEN, 0.92), 2.5, true)

func _build() -> void:
	var m: Dictionary = contract.moment
	var el := String(contract.witch.element)
	backdrop = Kit.make_backdrop(self, String(contract.backdrop), 0.84, 1.0)
	mother = Kit.Mother.new(el)
	mother.position = Vector2(70, 30)
	add_child(mother)
	_particles(el)
	thread = ThreadLine.new()
	add_child(thread)
	var wid := String(contract.witch.id)
	var crop: Rect2i = Kit.BUST_CROP[wid]
	witch_glow = Kit.add_glow(self, Vector2(215, 520), 300, Kit.with_alpha(Kit.el_color(el), 0.0))
	var tex := Kit.witch_crop(wid, crop)
	witch_pic = TextureRect.new()
	witch_pic.texture = tex
	witch_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	witch_pic.stretch_mode = TextureRect.STRETCH_SCALE
	var h := 520.0
	witch_pic.size = Vector2(h * float(crop.size.x) / float(crop.size.y), h)
	witch_pic.position = Vector2(-60, 900.0 - h + 20.0)
	witch_pic.material = Kit.feather_material(0.18, 0.34, 0.06)
	witch_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(witch_pic)
	# name plate
	title_group = Control.new()
	title_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_group)
	var title_text := String(ui.title_last) if String(m.kind) == "last" else String(ui.title)
	var cx := X0 + (1580.0 - X0) * 0.5
	for s in [-1.0, 1.0]:
		var rule := ColorRect.new()
		rule.color = Kit.with_alpha(Palette.BRASS, 0.7)
		rule.size = Vector2(150, 2)
		rule.position = Vector2(cx + s * 190.0 - (150.0 if s < 0.0 else 0.0), 66)
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_group.add_child(rule)
		var dia := Parts.Pips.new(1, 1)
		dia.position = Vector2(cx + s * 170.0 - 8.0, 59)
		title_group.add_child(dia)
	Kit.lbl(title_group, title_text, Vector2(cx - 170.0, 36), 340, 46, Palette.INK, "heading", HORIZONTAL_ALIGNMENT_CENTER, false, true)
	var pips := Parts.Pips.new(int(m.total), int(m.index))
	pips.position = Vector2(cx - pips.size.x * 0.5 - 20.0, 106)
	title_group.add_child(pips)
	Kit.lbl(title_group, String(m.label), Vector2(cx + pips.size.x * 0.5 - 8.0, 103), 70, 16, Palette.INK_DIM, "number", HORIZONTAL_ALIGNMENT_LEFT, false)
	if contract.giver.line != null:
		var rl := ColorRect.new()
		rl.color = Kit.with_alpha(Palette.LINEN, 0.7)
		rl.size = Vector2(44, 2)
		rl.position = Vector2(40, 58)
		rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_group.add_child(rl)
		Kit.lbl(title_group, String(contract.giver.line), Vector2(40, 68), 380, 20, Palette.INK_DIM, "heading", HORIZONTAL_ALIGNMENT_LEFT, true, true)
	# cards
	var knot_set := false
	for i in cards.size():
		var c := Kit.VCard.new()
		c.build(cards[i], i, CARD_W, CARD_H, 0.5, ui, false, false)
		var p := Vector2(X0 + float(i) * (CARD_W + GAP), Y0)
		c.position = p
		rest.append(p)
		if bool(contract.giver.thread) and not knot_set and String(cards[i].header) == "서약":
			c.knot = true
			knot_set = true
			thread.a = Vector2(330, 500)
			thread.b = p + Vector2(0, CARD_H * 0.5 + 10.0)
		c.set_focus_amount(0.0)
		c.clicked.connect(func(k): try_pick(k))
		c.hovered.connect(func(k): set_focus(k))
		add_child(c)
		vcards.append(c)
		if String(cards[i].kind) == "evolve" and String(m.beat) == "long":
			var sl := Parts.Seal.new(String(cards[i].element), String(cards[i].grade), Vector2(CARD_W, CARD_H))
			sl.position = p
			add_child(sl)
			seals[i] = sl
	side = Parts.SidePanel.new()
	side.position = Vector2(X0+ 3.0 * (CARD_W + GAP) - 2.0, Y0)
	side.setup(1580.0 - side.position.x, CARD_H, ui)
	add_child(side)
	side.show_card(cards[0], false)
	side.modulate.a = 0.0
	owned_row = Kit.OwnedRow.new()
	owned_row.build(contract.owned, ui, 50.0)
	owned_row.position = Vector2(X0, 735)
	add_child(owned_row)
	handle = Kit.Handle.new()
	handle.build(String(ui.key_reroll), String(ui.reroll), String(contract.reroll.left_label), 240.0, 46.0)
	handle.position = Vector2(1580.0 - 240.0, 733)
	handle.pressed.connect(func(): reroll_requested.emit())
	add_child(handle)
	Kit.lbl(self, String(ui.hint), Vector2(X0 + 270.0, 812), 600, 14, Palette.INK_FAINT, "body", HORIZONTAL_ALIGNMENT_LEFT, false)
	links = Parts.LinkLayer.new()
	add_child(links)

func _particles(el: String) -> void:
	if el == "arc": return
	particles = CPUParticles2D.new()
	particles.position = Vector2(200, 520 if el == "ember" else 120)
	particles.amount = 26
	particles.lifetime = 4.0
	particles.preprocess = 3.0
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(180, 8 if el == "ember" else 6)
	particles.direction = Vector2(0, -1 if el == "ember" else 1)
	particles.spread = 18.0
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = 14.0
	particles.initial_velocity_max = 36.0
	particles.scale_amount_min = 1.6
	particles.scale_amount_max = 3.4
	particles.color = Kit.with_alpha(Kit.el_color(el), 0.7)
	add_child(particles)
	if el == "ember": particles.position = Vector2(200, 780)
	else: particles.position = Vector2(200, 90)

func _fade(n: CanvasItem, delay: float, dur: float) -> void:
	n.modulate.a = 0.0
	var tw := track(create_tween())
	tw.tween_interval(delay)
	tw.tween_property(n, "modulate:a", 1.0, dur)

func _intro() -> float:
	var long_ := String(contract.moment.beat) == "long"
	var dim: ColorRect = backdrop.get_node("Dim")
	var t_c := 0.12
	var scale_t := 1.0 if long_ else 0.12 / 0.85
	if long_:
		dim.color.a = 0.2
		track(create_tween()).tween_property(dim, "color:a", 0.84, 0.3)
		_fade(mother, 0.3, 0.6)
		mother.position.y += 14.0
		track(create_tween()).tween_property(mother, "position:y", 30.0, 0.9).set_delay(0.3).set_ease(Tween.EASE_OUT)
		_fade(witch_pic, 0.2, 0.4)
		_fade(title_group, 0.2, 0.3)
		if particles != null: _fade(particles, 0.3, 0.6)
		for i in vcards.size():
			var c: Control = vcards[i]
			c.modulate.a = 0.0
			c.position.x = rest[i].x + 40.0
			var tw := track(create_tween()).set_parallel(true)
			tw.tween_property(c, "modulate:a", 1.0, 0.3).set_delay(0.3 + 0.1 * i)
			tw.tween_property(c, "position:x", rest[i].x, 0.35).set_delay(0.3 + 0.1 * i).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		for n in [side, owned_row, handle]: _fade(n, 0.6, 0.3)
		thread.progress = 0.0
		track(create_tween()).tween_property(thread, "progress", 1.0, 0.5).set_delay(0.9)
		t_c = 0.85
		for k in seals:
			var sl = seals[k]
			sl.leak = 0.0
			sl.crack = 0.0
			track(create_tween()).tween_property(sl, "leak", 1.0, 0.5).set_delay(0.3)
			var tw2 := track(create_tween())
			tw2.tween_interval(0.85)
			tw2.tween_callback(func(): mark("seal_cracking"))
			tw2.tween_property(sl, "crack", 1.0, 0.24).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			t_c = 0.85 + 0.24
	else:
		thread.progress = 1.0
		for n in [mother, witch_pic, title_group, side, owned_row, handle]: _fade(n, 0.0, 0.12)
		for i in vcards.size(): _fade(vcards[i], 0.0, 0.12)
	var tf := track(create_tween())
	tf.tween_interval(t_c)
	tf.tween_callback(func(): if focus_index < 0: set_focus(0))
	return t_c

func _settle_all() -> void:
	for n in [mother, witch_pic, title_group, side, owned_row, handle, particles]:
		if n != null: n.modulate.a = 1.0
	mother.position.y = 30.0
	for i in vcards.size():
		vcards[i].position = rest[i]
		vcards[i].modulate.a = 1.0
	thread.progress = 1.0
	for k in seals:
		seals[k].crack = 1.0
	backdrop.get_node("Dim").color.a = 0.84
	if focus_index < 0: set_focus(0)

func _focus_changed(_old: int, new: int) -> void:
	for i in vcards.size():
		var c = vcards[i]
		var f := 1.0 if i == new else 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_method(c.set_focus_amount, c.focus, f, 0.14)
		tw.tween_property(c, "position:y", float(rest[i].y) - (8.0 if i == new else 0.0), 0.14).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	var cn = vcards[new]
	var sw := create_tween()
	sw.tween_property(cn, "sweep", 1.0, 0.3).from(0.0)
	side.show_card(cards[new])
	side.modulate.a = 1.0
	var ec := Kit.el_color(String(cards[new].element))
	create_tween().tween_property(witch_glow, "modulate", Kit.with_alpha(ec, 0.5), 0.2)
	_update_links(new)

func _update_links(new: int) -> void:
	var slots: Array = owned_row.link_slots(cards[new])
	owned_row.lit = slots
	links.links = []
	var c = vcards[new]
	var target: Vector2 = Vector2(float(rest[new].x) + CARD_W * 0.5, float(rest[new].y) + CARD_H)
	for s in slots:
		var a: Vector2 = owned_row.global_position + owned_row.slot_centre("spell", s) + Vector2(0, -26)
		links.links.append([a, target])
	links.amount = 0.0
	owned_row.lit_amount = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(links, "amount", 1.0, 0.22)
	tw.tween_property(owned_row, "lit_amount", 1.0, 0.22)

func _confirm_anim(i: int) -> float:
	var c = vcards[i]
	var tgt: Vector2 = owned_row.target_for(cards[i])
	var tw := create_tween()
	tw.tween_property(c, "position:y", c.position.y - 10.0, 0.07)
	tw.set_parallel(true)
	tw.tween_property(c, "position", tgt - c.size * 0.5, 0.27).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(c, "scale", Vector2(0.16, 0.16), 0.27).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(c, "modulate:a", 0.0, 0.1).set_delay(0.24)
	for k in vcards.size():
		if k == i: continue
		var o = vcards[k]
		var tw2 := create_tween().set_parallel(true)
		tw2.tween_property(o, "modulate:a", 0.0, 0.22)
		tw2.tween_property(o, "position:y", o.position.y + 22.0, 0.22)
	create_tween().tween_property(links, "amount", 0.0, 0.15)
	create_tween().tween_property(side, "modulate:a", 0.0, 0.15)
	var tw3 := create_tween()
	tw3.tween_interval(0.34)
	tw3.tween_callback(func(): _dock(i, tgt))
	return 0.62

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
	var tw4 := create_tween()
	tw4.tween_property(gl, "modulate:a", 0.0, 0.3)
	tw4.tween_callback(gl.queue_free)
	mark("socketed")
