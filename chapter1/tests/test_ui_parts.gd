extends SceneTree
## Shared screen parts check (A10 W0): the parts of ui_parts.gd build without a picture (the fall-back path never fails), the A10 tokens and text
## roles read as the spec says, and the opt-in UiStyle functions leave the old ones as they were.
##
##   python tools/dev/godot.py --headless --path . --script res://chapter1/tests/test_ui_parts.gd
## Last line: CHAPTER1_UI_PARTS_RESULT {...}; exit code 1 on any failure.
const Parts = preload("res://chapter1/view/hud/ui_parts.gd")
const Motion = preload("res://chapter1/view/hud/ui_motion.gd")
const Palette = preload("res://chapter1/view/hud/palette.gd")
const UiStyle = preload("res://chapter1/view/hud/ui_style.gd")
const Grace = preload("res://chapter1/view/hud/grace_parts.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("execute")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func execute() -> void:
	# tokens: the grace values moved without changing
	check(Palette.GRACE_JACKPOT == Color("ffc24d"), "GRACE_JACKPOT value")
	check(Palette.GAIN == Color("8fd694") and Palette.LOSS == Color("e07a6a"), "GAIN / LOSS value")
	check(Palette.FLAME_WARM == Color("ffb25a"), "FLAME_WARM value")
	check(Palette.SCRIM_SCENE.a > 0.0 and Palette.SCRIM_SCENE_VIGNETTE > 0.0, "scene scrim")
	check(Grace.name_color("jackpot") == Palette.GRACE_JACKPOT and Grace.name_color("rare") == Palette.QUALITY_RARE, "grace name colours")
	# motion table
	check(Motion.SCENE_IN == 0.45 and Motion.SCENE_IN_LONG == 1.8 and Motion.PICK_LOCK == 0.25 and Motion.SCENE_OUT == 0.46, "motion lengths of the grace screen")
	check(Grace.intro_seconds("normal") == 0.45 and Grace.intro_seconds("long") == 1.8 and Grace.intro_seconds("jackpot") == 2.0, "grace intro seconds")
	# text roles: the seven sizes
	var sizes := []
	for r in ["t1", "t2", "t3", "t4", "t5", "t6", "t7"]: sizes.append(UiStyle.text(r).size)
	check(sizes == [36, 30, 26, 20, 17, 15, 14], "seven text sizes: %s" % str(sizes))
	check(UiStyle.text("t1", "bold").font == "bold", "text font override")
	var lbl := UiStyle.text_label("x", "t3")
	check(lbl.get_theme_font_size("font_size") == 26, "text_label size")
	lbl.free()
	# opt-in style functions: without art they are the old ones (the planned kit pictures do not exist yet)
	check(Parts.tex("board") == null or Parts.tex("board") is Texture2D, "board picture lookup does not fail")
	check(UiStyle.window("board") != null and UiStyle.window() != null, "window kinds")
	for kind in ["primary", "secondary", "danger"]:
		for state in ["normal", "hover", "pressed", "disabled"]:
			check(UiStyle.button_kind(kind, state) != null, "button %s %s" % [kind, state])
	for kind in ["box", "button", "row"]:
		check(UiStyle.focus_mark(kind) != null, "focus mark " + kind)
	check(UiStyle.focus_mark() is StyleBoxFlat, "default focus mark stays the box")
	var scrim_w := UiStyle.scrim("window")
	var scrim_s := UiStyle.scrim("scene")
	check(scrim_w.color == Palette.SCRIM and scrim_s.color == Palette.SCRIM_SCENE and scrim_s.get_child_count() == 1, "scrims")
	scrim_w.free()
	scrim_s.free()
	# parts build (no picture needed)
	var host := Control.new()
	host.size = Vector2(1600, 900)
	root.add_child(host)
	check(Parts.title(host, "Title", 740.0, "sub") != null, "title plaque")
	check(Parts.candle(host, Vector2(100, 100), 160.0) != null, "candle")
	var contract := {"strings": {"reroll": "r", "key_reroll": "R"}, "reroll": {"left_label": "1"}}
	check(Parts.handles(host, contract, Vector2(10, 10)).size() == 1, "knob handles")
	var note := Parts.note(host, Rect2(0, 0, 400, 500), {"strings": {}})
	note.show_card({"name": "N", "headline": "h", "details": ["a"]})
	check(note != null, "side note")
	for key in ["common", "rare", "jackpot", "magic", "legendary", "unique"]:
		var gf := Parts.GradeFrame.new()
		gf.build(key, Vector2(120, 120))
		host.add_child(gf)
		check(gf.get_child_count() > 0, "grade frame " + key)
	var band := Parts.Band.new()
	band.build(600.0, 66.0)
	host.add_child(band)
	var board := Parts.Board.new()
	board.build(Vector2(500, 300))
	host.add_child(board)
	await process_frame
	await process_frame
	check(band.get_child_count() == 1 and board.get_child_count() == 1, "band and board")
	host.queue_free()
	await process_frame
	print("CHAPTER1_UI_PARTS_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(1 if not failures.is_empty() else 0)
