extends "res://chapter1/tests/proposals/growth_choice/grace_scene.gd"
## A8 G3 proposal D "the demon's table" (spec 5.3): the demon stands at the left (about 27 % of the width, 90 % of the height, partly behind the board),
## the three cards lie in the three windows of the leather-and-brass reliquary, the title plaque with its two candles sits on the reliquary's top band,
## the side note (parchment) and the three knobs stand to its right, the owned band and the demon's line under it.
## Deviation from 5.3: the side note is always shown on the right (not slid out on focus) and the demon is 27 % of the width, because the reliquary must be wide
## enough for readable cards (a window is 178 x 274 code px at this size). The still is the END state; motion hooks are in grace_scene.gd.

static func make(c: Dictionary) -> Control:
	var s = load("res://chapter1/tests/proposals/growth_choice/d_table.gd").new()
	s.setup(c)
	return s

func _layout() -> void:
	_shafts(Vector2(120, 0))
	_demon(Rect2(-80, 90, 540, 810))
	_motes(Rect2(-40, 150, 520, 650))
	var rel: Dictionary = Grace.reliquary(self, Vector2(330, 150), 860.0)
	var rects: Array = []
	for w in rel.windows: rects.append((w as Rect2).grow(-5.0))
	_cards_into(rects, [0.0, 0.0, 0.0])
	_title_block(760.0, 14.0, 420.0, 250.0, 140.0, 30.0)
	_note(Rect2(1215, 20, 375, 500))
	_knobs(Vector2(1232, 540), 0.0)
	_band(Vector2(330, 733), 870.0)
	_speech(Vector2(340, 808), 640.0)
	_tag_label(Vector2(330, 840), 1250.0)
	if jackpot_index >= 0:
		var r: Rect2 = rects[jackpot_index]
		_jackpot_fx(r, r.grow(3.0), Vector2(r.get_center().x, r.position.y - 30.0))
