extends "res://chapter1/tests/proposals/growth_choice/grace_scene.gd"
## A8 G3 proposal E "the demon's hand" (spec 5.4): the demon is the owner of the screen (head to thigh, taller than the screen, centred), the three cards float
## in a fan (+-8 degrees) in front of her where an open hand would be, the leather band lies along the bottom, the title plaque is at the top centre and the
## candles stand at the two screen edges.
## No hand picture exists yet (N11 not drawn): the hand's place is an element-coloured light under the fan. D14 3 / fix 1 ("no object held out") has to be
## judged by narrative-lead: the cards float, they are not held. Unchosen demon figures are listed in the dev tag.
## Deviation: the side note is always shown (left), knobs in a column at the right.

static func make(c: Dictionary) -> Control:
	var s = load("res://chapter1/tests/proposals/growth_choice/e_hand.gd").new()
	s.setup(c)
	return s

func _layout() -> void:
	_shafts(Vector2(420, 0))
	_demon(Rect2(366, 40, 868, 1300))
	_motes(Rect2(300, 60, 700, 700))
	var hand := Grace.glow_rect(stage, Vector2.ZERO, 1.0, Kit.with_alpha(Kit.el_color(el), 0.34))
	hand.size = Vector2(900, 340)
	hand.position = Vector2(800, 670) - hand.size * 0.5
	var centres := [Vector2(538, 622), Vector2(800, 592), Vector2(1062, 622)]
	var sizes := [Vector2(250, 390), Vector2(270, 420), Vector2(250, 390)]
	var tilts := [-0.14, 0.0, 0.14]
	var rects: Array = []
	for i in 3: rects.append(Rect2(centres[i] - sizes[i] * 0.5, sizes[i]))
	_cards_into(rects, tilts)
	if jackpot_index >= 0:
		card_nodes[jackpot_index].z_index = 3
	_title_block(800.0, 8.0, 360.0, 740.0, 170.0, 40.0)
	_note(Rect2(24, 170, 330, 440))
	_speech(Vector2(30, 630), 320.0)
	_knobs(Vector2(1232, 300), 0.0)
	_band(Vector2(365, 832), 870.0)
	_tag_label(Vector2(150, 6), 430.0)
	if jackpot_index >= 0:
		var r: Rect2 = rects[jackpot_index]
		_jackpot_fx(r, r, Vector2(r.get_center().x, r.position.y - 34.0), float(tilts[jackpot_index]))
