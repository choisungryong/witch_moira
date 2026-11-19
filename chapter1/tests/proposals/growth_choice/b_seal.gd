extends "res://chapter1/tests/proposals/growth_choice/a_oath.gd"
## Proposal B "tear the seal" (kept as the evolution-card piece of the chosen direction, and as a stand-alone comparison).
## No figure: three cards lie under wax-sealed covers; the covers crack open in grade order, the highest grade last, and before
## it opens its colour leaks through the seam as a LOW light. Focus lifts a card slightly (<= 1.03) and lights its frame. The chosen
## card is socketed into the owned row, the others sink.
## Concept: the moment before knowing. Built on the A scene's parts so the two share every control; only the intro differs.

static func make(c: Dictionary) -> Control:
	var s = load("res://chapter1/tests/proposals/growth_choice/b_seal.gd").new()
	s.setup(c)
	return s

func _build() -> void:
	super._build()
	for n in [mother, witch_pic, thread, witch_glow]: n.visible = false
	if particles != null: particles.visible = false
	for i in vcards.size():
		if seals.has(i): continue
		var sl := Parts.Seal.new(String(cards[i].element), String(cards[i].grade), Vector2(CARD_W, CARD_H))
		sl.position = rest[i]
		add_child(sl)
		seals[i] = sl
	# the seals sit above their cards but below the side frame and the link layer
	for k in seals: move_child(seals[k], vcards.back().get_index() + 1)

func _intro() -> float:
	var dim: ColorRect = backdrop.get_node("Dim")
	dim.color.a = 0.4
	track(create_tween()).tween_property(dim, "color:a", 0.84, 0.25)
	_fade(title_group, 0.1, 0.25)
	for n in [side, owned_row, handle]: _fade(n, 0.45, 0.25)
	var order: Array = range(cards.size())
	order.sort_custom(func(a, b): return Kit.grade_rank(String(cards[a].grade)) < Kit.grade_rank(String(cards[b].grade)))
	var t := 0.3
	for k in order.size():
		var i: int = order[k]
		var c: Control = vcards[i]
		c.modulate.a = 0.0
		var sl = seals[i]
		sl.crack = 0.0
		sl.leak = 0.0
		var rank := Kit.grade_rank(String(cards[i].grade))
		track(create_tween()).tween_property(c, "modulate:a", 1.0, 0.2).set_delay(0.1 + 0.05 * k)
		var tl := track(create_tween())
		tl.tween_interval(maxf(0.1, t - 0.22))
		tl.tween_property(sl, "leak", 1.0 if rank >= 2 else 0.35, 0.22)
		var tc := track(create_tween())
		tc.tween_interval(t)
		tc.tween_callback(func(): mark("seal_%d_cracks" % i))
		tc.tween_property(sl, "crack", 1.0, 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		t += 0.12 + (0.2 if k == order.size() - 2 else 0.0)
	var t_c := t - 0.12 + 0.2
	var tf := track(create_tween())
	tf.tween_interval(t_c)
	tf.tween_callback(func(): if focus_index < 0: set_focus(best_index()))
	return t_c
