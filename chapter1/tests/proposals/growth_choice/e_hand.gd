extends RefCounted
## A8 G3 proposal E "the demon's hand" -- chosen by the user and now the product screen (A8 G6): this file only builds the product screen on a fixture
## so tools/dev/proposal_batch.py and chapter1/tests/proposal_shot.gd can still shoot it. The pieces are chapter1/view/hud/screens/growth_choice.gd and grace_parts.gd.
const Screen = preload("res://chapter1/view/hud/screens/growth_choice.gd")

static func make(c: Dictionary) -> Control:
	var s: Control = Screen.new()
	s.apply(c)
	return s
