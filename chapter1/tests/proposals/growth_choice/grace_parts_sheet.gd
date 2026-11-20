extends "res://chapter1/tests/proposals/growth_choice/base.gd"
## A8 G2 parts sample sheet (tests only): the parts of grace_parts.gd laid out, nothing else. One page per fixture:
##   slot_ember_normal / slot_frost_normal / slot_arc_normal  the three grades (common / rare / jackpot) of that element, at the real card size 300 x 470
##   slot_long                                                 the same on the longest-text fixture (a "new" card: no number row, long combo text)
## Each page also shows the title plaque with two candles, the contract board, the side note of the focused card, the owned band, the three knobs and
## the jackpot plate. The focused card is the jackpot one (set_focus(best_index())). The dev tag at the bottom names which parts used the kit
## pictures, the queue originals, the HUD atlas or code shapes. Run: tools/dev/proposal_batch.py --only growth_choice/grace_parts_sheet
## (add --game-args "--grace-kit=<folder>" to read another kit folder).
const Grace = preload("res://chapter1/tests/proposals/growth_choice/grace_parts.gd")
const FIXTURE_DIR := "res://chapter1/tests/fixtures/ui/"
const CARD := Vector2(300, 470)
const CARD_GAP := 30.0

var card_nodes: Array = []
var note_node
var band_node
var capture_mode := false

static func make(c: Dictionary) -> Control:
	var s = load("res://chapter1/tests/proposals/growth_choice/grace_parts_sheet.gd").new()
	s.setup(c)
	return s

## grade words of the fixtures ("희귀" / "기연" come from the files, this script holds no Korean)
func _grade_names() -> Dictionary:
	var out := {"scarce": "", "fated": ""}
	for f in ["slot_ember_scarce", "slot_ember_fated"]:
		var d := Kit.read_json("%sgrowth_choice.%s.json" % [FIXTURE_DIR, f])
		for c in d.get("cards", []):
			var g := String(c.get("grade", ""))
			if out.has(g) and String(c.get("grade_name", "")) != "": out[g] = String(c.grade_name)
	return out

func _variant(src: Dictionary, grade: String, names: Dictionary) -> Dictionary:
	var c: Dictionary = src.duplicate(true)
	c.grade = grade
	c.grade_name = String(names.get(grade, ""))
	return c

func _build() -> void:
	var variant := String(contract.get("variant", ""))
	var names := _grade_names()
	var src: Dictionary = cards[0]
	if variant != "slot_long" and cards.size() > 1 and cards[1].get("delta", null) is Dictionary: src = cards[1]
	cards = [_variant(src, "common", names), _variant(src, "scarce", names), _variant(src, "fated", names)]
	contract.cards = cards
	var el := String(src.get("element", "frost"))
	var flame: Color = Kit.el_color(el).lerp(Grace.FLAME_WARM, 0.55)
	# ground
	var ground := ColorRect.new()
	ground.color = Color(0.028, 0.03, 0.036)
	ground.size = Kit.SIZE
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ground)
	var vig := Grace.ArtLayer.new()
	vig.texture = Kit.vignette_texture()
	vig.size = Kit.SIZE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vig)
	# board, title with two candles
	Grace.board(self, Rect2(70, 168, 1460, 540))
	var plaque = Grace.title(self, String(ui.get("title", "")), 520.0, String(contract.get("moment", {}).get("label", "")))
	plaque.position = Vector2((Kit.SIZE.x - plaque.size.x) * 0.5, 18)
	var c1 = Grace.candle(self, Vector2(plaque.position.x - 130.0, 34.0), 176.0, flame)
	var c2 = Grace.candle(self, Vector2(plaque.position.x + plaque.size.x + 34.0, 34.0), 176.0, flame)
	c1.animated = not reduce_motion
	c2.animated = not reduce_motion
	# the three grade cards
	var x0 := 120.0
	for i in 3:
		var cd = Grace.card(self, cards[i], i, CARD, ui)
		cd.position = Vector2(x0 + float(i) * (CARD.x + CARD_GAP), 196.0)
		cd.animated = not reduce_motion
		cd.clicked.connect(func(k): set_focus(k))
		cd.hovered.connect(func(k): set_focus(k))
		card_nodes.append(cd)
	note_node = Grace.note(self, Rect2(1130, 196, 340, 470), contract)
	# below: owned band, knobs, the jackpot plate, the dev tag
	band_node = Grace.band(self, Vector2(70, 716), 1000.0, contract)
	Grace.handles(self, contract, Vector2(1130, 716), 28.0)
	var jp = Grace.jackpot(self, String(ui.get("fated_banner", "")), Vector2(260, 92))
	jp.position = Vector2(120, 802)
	var tag := "parts sheet (A8 G2) · %s · kit folder: %s · %s" % [variant, Grace.kit_folder() if Grace.kit_folder() != "" else "none", Grace.report_line()]
	var dn := Grace.dev_notes(contract)
	if dn != "": tag += " · dev text kept off the screen: " + dn
	Kit.lbl(self, tag, Vector2(420, 806), 680, 14, Palette.INK_FAINT, "body", HORIZONTAL_ALIGNMENT_LEFT, true)

func _intro() -> float:
	modulate.a = 0.0
	var t: float = Grace.intro_seconds("normal")
	track(create_tween()).tween_property(self, "modulate:a", 1.0, minf(0.3, t))
	return t

func _settle_all() -> void:
	modulate.a = 1.0

func _focus_changed(_old: int, new: int) -> void:
	for i in card_nodes.size():
		card_nodes[i].set_focus_amount(1.0 if i == new else 0.35)
	note_node.show_card(cards[new])
	band_node.lit = band_node.link_slots(cards[new])
	band_node.lit_amount = 1.0 if not band_node.lit.is_empty() else 0.0

func _confirm_anim(index: int) -> float:
	card_nodes[index].leak = 1.0
	return 0.3
