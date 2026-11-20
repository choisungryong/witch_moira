extends "res://chapter1/tests/proposals/growth_choice/base.gd"
## Proposal "slot machine / fated" (user direction 2026-11-20, overrides the earlier "two beats" order).
## REVISION (D14 3, GRACE-GRADES 0): the big figure is the DEMON who gives the grace (draft paintings from _local/art/drafts, read at run
## time, NOT copied into the repository; the ember / storm ones are the ORIGINAL demons' paintings = stand-ins only, the frost one is a code
## silhouette). The witch is not on this screen. The storm demon does not speak.
## Level-up is a BIG EVENT, not a low band: the whole screen is the scene. Left 30%: the demon, full height,
## breathing on a 2.7 s period (the Sacrata method: the whole body bobs). Right: a heavy brass reel machine with
## three windows. The three cards are not on the table at the start: the reels spin and stop one by one from the left, each stop is a beat.
## On an ordinary pull all three stop in about 1.1 s (pickable at 1.35 s). On a LUCKY pull the last reel crawls, its frame heats up, the
## screen goes dark once, and the FATED card bursts in gold (white flash, light pillar, rotating rays, sparks, the word on top, the card
## bigger and brighter than the others, the witch and the mother flare). It must read without sound.
## Re-pull = the lever. The chosen card is socketed into the owned row; a fated card does one more, larger flash there.
## Placeholders (NEW ART NEEDED): the mother (code silhouette), reel/lever/housing metal (code-drawn; wants a material kit),
## card art (code emblems), sounds (reel whir, per-stop thunk, rising tension, burst, socket).

const REEL_W := 240.0
const REEL_H := 520.0
const REEL_GAP := 14.0
const RX0 := 520.0
const RY0 := 160.0
const N_SYM := 14
const BOB := 9.0
const SYM_KINDS := ["ring", "lance", "orb", "bolt", "crystal", "nova"]
const ELS := ["ember", "frost", "arc"]

static func make(c: Dictionary) -> Control:
	var s = load("res://chapter1/tests/proposals/growth_choice/slot_fated.gd").new()
	s.setup(c)
	return s

# ---------------- parts ----------------

## One passing symbol of a reel: the face of a card of some grade with a big emblem (the real card text appears when the reel stops).
class Symbol extends Control:
	var grade := "common"
	var kind := "ring"
	var element := "frost"
	var kit
	func _init(g := "common", k := "ring", e := "frost") -> void:
		grade = g
		kind = k
		element = e
		size = Vector2(240, 520)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
	func _draw() -> void:
		kit.draw_face(self, Rect2(Vector2.ZERO, size), grade, 0.0)
		var emb_h := size.y * 0.46
		kit.draw_emblem(self, kind, element, Vector2(size.x * 0.5, emb_h * 0.5 + 9.0), (emb_h - 34.0) * 0.5, 1.0 if grade != "common" else 0.7, 0.0, 1.0 if grade != "common" else 0.55)
		kit.draw_badge(self, element, Vector2(30, 32), 10.0, kit.el_color(element))

## Speed streaks and the window shading over a spinning reel (drawn above the strip, hidden when it stops).
class Streak extends Control:
	var amount := 0.0:
		set(v):
			amount = v
			visible = v > 0.01
			queue_redraw()
	func _init() -> void:
		size = Vector2(240, 520)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false
	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(Time.get_ticks_msec() / 40.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.30 * amount))
		for i in 26:
			var x := rng.randf() * size.x
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 0.95, 0.8, rng.randf_range(0.03, 0.14) * amount), rng.randf_range(1.0, 4.0))
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		kit.quad(self, Rect2(0, 0, size.x, 110), Color(0, 0, 0, 0.8 * amount), Color(0, 0, 0, 0))
		kit.quad(self, Rect2(0, size.y - 110, size.x, 110), Color(0, 0, 0, 0), Color(0, 0, 0, 0.8 * amount))

## A reel window: clipped strip of symbols; the last symbol is the real card's face.
class Reel extends Control:
	var strip: Control
	var streak
	var total := 0.0
	var last_y := 0.0
	func build(grade: String, kind: String, element: String, seed_: int, fated_glint: bool) -> void:
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		size = Vector2(240, 520)
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip = Control.new()
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(strip)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_
		var n := 14
		for i in n:
			var g := "common"
			var k: String = ["ring", "lance", "orb", "bolt", "crystal", "nova"][rng.randi() % 6]
			var e: String = ["ember", "frost", "arc"][rng.randi() % 3]
			var r := rng.randf()
			if r > 0.78: g = "scarce"
			if i == 5 and fated_glint: g = "fated"
			if i == 9: g = "scarce"
			if i == n - 1:
				g = grade
				k = kind
				e = element
			var s := Symbol.new(g, k, e)
			s.position = Vector2(0, 520.0 * i)
			strip.add_child(s)
		total = 520.0 * (n - 1)
		streak = Streak.new()
		add_child(streak)
	func _process(_d: float) -> void:
		var v: float = absf(strip.position.y - last_y)
		last_y = strip.position.y
		streak.amount = clampf(v / 45.0, 0.0, 1.0) * 0.9
	func reset_strip() -> void:
		strip.position.y = 0.0
		last_y = 0.0

## The brass machine body: plate, window recesses, rivets, the lamp row, and the heat glow around a window.
class Housing extends Control:
	var lamp_mode := 0
	var phase := 0.0
	var heat := 0.0:
		set(v):
			heat = v
	var heat_window := 2
	var all_gold := 0.0
	func _init() -> void:
		size = Vector2(800, 640)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(delta: float) -> void:
		phase += delta * (6.0 if lamp_mode == 1 else (14.0 if lamp_mode == 2 else 1.0))
		queue_redraw()
	func _draw() -> void:
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r.grow(8), Color(0, 0, 0, 0.5))
		kit.quad(self, r, Color(0.33, 0.265, 0.17), Color(0.13, 0.1, 0.065))
		draw_rect(r, Color(0.62, 0.5, 0.3), false, 3.0)
		draw_rect(r.grow(-8), Color(0.05, 0.04, 0.03), false, 2.0)
		draw_line(Vector2(3, 3), Vector2(size.x - 3, 3), Color(1, 0.93, 0.7, 0.4), 2.0)
		for k in 20:
			var p := Vector2(24.0 + k * 40.0, 16.0)
			draw_circle(p, 5.0, Color(0.5, 0.42, 0.28))
			draw_circle(p + Vector2(-1, -1), 2.0, Color(1, 0.95, 0.8, 0.6))
			draw_circle(Vector2(p.x, size.y - 16.0), 5.0, Color(0.5, 0.42, 0.28))
		for i in 3:
			var w := Rect2(20.0 + i * 254.0, 28.0, 252.0, 532.0)
			draw_rect(w, Color(0.015, 0.014, 0.014))
			draw_rect(w, Color(0.72, 0.58, 0.34), false, 3.0)
			draw_rect(w.grow(-3), Color(0, 0, 0, 0.8), false, 2.0)
			if i == heat_window and heat > 0.0:
				var pulse := 0.65 + 0.35 * sin(phase * 3.0)
				for j in 9:
					draw_rect(w.grow(float(j) * 3.0 + 1.0), Color(1.0, 0.76, 0.3, 0.34 * heat * pulse * (1.0 - float(j) / 9.0)), false, 3.0)
				draw_rect(w, Color(1.0, 0.8, 0.35, 0.9 * heat * pulse), false, 3.0)
		# lamp row
		draw_rect(Rect2(30, 578, 740, 40), Color(0.04, 0.03, 0.02), true)
		draw_rect(Rect2(30, 578, 740, 40), Color(0.6, 0.48, 0.28), false, 2.0)
		for k in 19:
			var c := Vector2(54.0 + k * 38.5, 598.0)
			var on := 0.12
			match lamp_mode:
				0: on = 0.12 + 0.1 * (0.5 + 0.5 * sin(phase + k * 0.3))
				1: on = 1.0 if int(phase + k) % 4 == 0 else 0.1
				2: on = 1.0 if int(phase + k) % 2 == 0 else 0.35
				3: on = 1.0
			draw_circle(c, 9.0, Color(0.1, 0.06, 0.02))
			var col := Color(1.0, 0.78, 0.35) if lamp_mode >= 2 else Color(1.0, 0.62, 0.22)
			draw_circle(c, 7.0, Color(col.r, col.g, col.b, on))
			if on > 0.6: draw_circle(c, 14.0, Color(col.r, col.g, col.b, 0.14 * on))

## The pull lever (= re-roll). th: angle from straight up; rest leaning, pulled = down.
class Lever extends Control:
	signal pressed
	var th := 0.28:
		set(v):
			th = v
			queue_redraw()
	func _init() -> void:
		size = Vector2(70, 380)
		mouse_filter = Control.MOUSE_FILTER_STOP
		gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: pressed.emit())
	func _draw() -> void:
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		var base := Vector2(30, 250)
		kit.quad(self, Rect2(8, 150, 44, 190), Color(0.38, 0.3, 0.19), Color(0.15, 0.12, 0.08))
		draw_rect(Rect2(8, 150, 44, 190), Color(0.65, 0.52, 0.3), false, 2.0)
		draw_rect(Rect2(26, 170, 8, 140), Color(0, 0, 0, 0.9))
		var dir := Vector2(sin(th), -cos(th))
		var tip := base + dir * 165.0
		draw_line(base, tip, Color(0, 0, 0, 0.6), 14.0, true)
		draw_line(base, tip, Color(0.62, 0.55, 0.45), 10.0, true)
		draw_line(base + Vector2(-2, -2), tip + Vector2(-2, -2), Color(1, 0.96, 0.85, 0.5), 2.0, true)
		draw_circle(tip, 25.0, Color(0.45, 0.07, 0.06))
		draw_circle(tip, 25.0, Color(0.8, 0.62, 0.3), false, 3.0)
		draw_circle(tip + Vector2(-8, -8), 8.0, Color(1, 0.8, 0.7, 0.55))
		draw_circle(base, 13.0, Color(0.55, 0.45, 0.28))
		draw_circle(base, 6.0, Color(0.15, 0.12, 0.08))

## Name plate on top with two braziers (Sacrata has torches; ours are metal bowls with a low flame).
class Plate extends Control:
	func _init() -> void:
		size = Vector2(520, 96)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		var pts := PackedVector2Array([Vector2(70, 8), Vector2(450, 8), Vector2(480, 56), Vector2(450, 88), Vector2(70, 88), Vector2(40, 56)])
		draw_colored_polygon(pts, Color(0.2, 0.16, 0.1))
		var rim := PackedVector2Array(pts)
		rim.append(pts[0])
		draw_polyline(rim, Color(0.72, 0.58, 0.34), 3.0, true)
		draw_polyline(PackedVector2Array([Vector2(82, 16), Vector2(438, 16), Vector2(462, 56), Vector2(438, 80), Vector2(82, 80), Vector2(58, 56)]), Color(0.05, 0.04, 0.03), 2.0, true)
		kit.diamond(self, Vector2(260, 8), 10.0, Color(0.95, 0.82, 0.5))
		for s in [0.0, 1.0]:
			var x: float = 16.0 + s * 488.0
			draw_colored_polygon(PackedVector2Array([Vector2(x - 16, 62), Vector2(x + 16, 62), Vector2(x + 10, 84), Vector2(x - 10, 84)]), Color(0.28, 0.22, 0.14))
			draw_rect(Rect2(x - 4, 84, 8, 10), Color(0.28, 0.22, 0.14))

class Rays extends Control:
	var amount := 0.0:
		set(v):
			amount = v
			queue_redraw()
	var spin := 0.0
	var centre := Vector2.ZERO
	func _init() -> void:
		size = Vector2(1600, 900)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m
		set_process(true)
	func _process(d: float) -> void:
		spin += d * 0.35
		if amount > 0.0: queue_redraw()
	func _draw() -> void:
		if amount <= 0.0: return
		for i in 18:
			var a := spin + float(i) * TAU / 18.0
			var w := 0.07
			var p0 := centre
			var p1 := centre + Vector2.from_angle(a - w) * 900.0
			var p2 := centre + Vector2.from_angle(a + w) * 900.0
			draw_colored_polygon(PackedVector2Array([p0, p1, p2]), Color(1.0, 0.8, 0.4, 0.13 * amount))

# ---------------- scene ----------------

var backdrop: Control
var figure: Control
var mother: Control
var witch_pic: TextureRect
var witch_glow: TextureRect
var pillar: TextureRect
var housing
var plate: Control
var reels: Array = []
var cards_v: Array = []
var rest: Array = []
var lever
var side
var owned_row
var handle
var links
var flash: ColorRect
var rays
var spark: CPUParticles2D
var banner: Label
var title_group: Control
var torches: Array = []
var fate_index := -1
var eye_glows: Array = []
var demon_hand := Vector2.ZERO
var demon_line: Label
var stop_order: Array = []
var fortune := "none"
var _shake := 0.0

func _pillar_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_LINEAR
	t.fill_from = Vector2(0, 0.5)
	t.fill_to = Vector2(1, 0.5)
	t.width = 128
	t.height = 8
	return t

func _additive(n: CanvasItem) -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	n.material = m

func _build() -> void:
	var m: Dictionary = contract.moment
	fortune = String(m.get("fortune", "none"))
	var el := String(contract.witch.element)
	var wid := String(contract.witch.id)
	for i in cards.size():
		if String(cards[i].grade) == "fated": fate_index = i
	stop_order = []
	for i in cards.size():
		if i != fate_index: stop_order.append(i)
	if fate_index >= 0: stop_order.append(fate_index)
	backdrop = Kit.make_backdrop(self, String(contract.backdrop), 0.9, 1.0)
	# pillar of light (entry) behind the figure
	pillar = TextureRect.new()
	pillar.texture = _pillar_texture()
	pillar.size = Vector2(260, 900)
	pillar.position = Vector2(110, 0)
	pillar.stretch_mode = TextureRect.STRETCH_SCALE
	pillar.modulate = Kit.with_alpha(Kit.el_color(el).lightened(0.25), 0.0)
	pillar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_additive(pillar)
	add_child(pillar)
	# figure: mother behind, receiving witch in front; the whole group breathes
	figure = Control.new()
	figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(figure)
	witch_glow = Kit.add_glow(figure, Vector2(250, 480), 380, Kit.with_alpha(Kit.el_color(el), 0.35))
	# THE DEMON (D14 3): the one who made the contract with this witch gives the grace. Draft paintings are read at run time from
	# _local/art/drafts/ (not copied into the repository). The witch is not on this screen.
	var fig: Dictionary = contract.giver.figure
	var crop := Rect2i(40, 0, 944, 1536)
	var fig_path := Kit.find_local(String(fig.file)) if String(fig.file) != "" else ""
	var sc := 830.0 / 1536.0
	witch_pic = TextureRect.new()
	witch_pic.texture = Kit.image_texture(fig_path, crop) if fig_path != "" else null
	witch_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	witch_pic.stretch_mode = TextureRect.STRETCH_SCALE
	witch_pic.size = Vector2(944.0 * sc, 830.0)
	witch_pic.position = Vector2(-20, 50)
	witch_pic.material = Kit.feather_material(0.12, 0.2, 0.03)
	witch_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	figure.add_child(witch_pic)
	if fig_path == "":
		# NEW ART NEEDED: no standing figure yet. A code silhouette holds the place and the size (standing, full height, horns).
		witch_pic.visible = false
		var sil := Kit.Mother.new(el)
		sil.scale = Vector2(1.0, 0.97)
		sil.position = Vector2(60, 40)
		figure.add_child(sil)
	for dx in ([-32.0, 32.0] if fig_path != "" else []):
		var ep: Vector2 = witch_pic.position + (Vector2(float(fig.eye[0]) + dx, float(fig.eye[1])) - Vector2(crop.position)) * sc
		eye_glows.append(Kit.add_glow(figure, ep, 22.0, Kit.with_alpha(Kit.el_color(el).lightened(0.4), 0.0)))
	demon_hand = witch_pic.position + (Vector2(520, 520) - Vector2(crop.position)) * sc
	# housing + reels
	housing = Housing.new()
	housing.position = Vector2(494, 126)
	add_child(housing)
	for k in 3:
		var rl := Reel.new()
		var c: Dictionary = cards[k]
		rl.build(String(c.grade), String(c.emblem), String(c.element), 31 + k * 7 + int(m.index), k != fate_index and true)
		rl.position = Vector2(RX0 + k * (REEL_W + REEL_GAP), RY0)
		add_child(rl)
		reels.append(rl)
	for k in 3:
		var vc := Kit.VCard.new()
		vc.build(cards[k], k, REEL_W, REEL_H, 0.46, ui, false, false)
		var p := Vector2(RX0 + k * (REEL_W + REEL_GAP), RY0)
		vc.position = p
		rest.append(p)
		vc.set_focus_amount(0.0)
		vc.visible = false
		vc.clicked.connect(func(i): try_pick(i))
		vc.hovered.connect(func(i): if state == "ready": set_focus(i))
		add_child(vc)
		cards_v.append(vc)
	# title plate with braziers
	title_group = Control.new()
	title_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_group)
	plate = Plate.new()
	plate.position = Vector2(634, 22)
	title_group.add_child(plate)
	var tt := String(ui.title_last) if String(m.kind) == "last" else String(ui.title)
	Kit.lbl(title_group, tt, Vector2(634 + 110, 36), 300, 42, Palette.INK, "heading", HORIZONTAL_ALIGNMENT_CENTER, false, true)
	var pips := Parts.Pips.new(int(m.total), int(m.index))
	pips.position = Vector2(420, 56)
	title_group.add_child(pips)
	Kit.lbl(title_group, String(m.label), Vector2(604, 53), 70, 16, Palette.INK_DIM, "number", HORIZONTAL_ALIGNMENT_LEFT, false)
	for sx in [650.0, 1138.0]:
		var tp := CPUParticles2D.new()
		tp.position = Vector2(sx, 98)
		tp.amount = 16
		tp.lifetime = 1.1
		tp.preprocess = 1.0
		tp.direction = Vector2(0, -1)
		tp.spread = 14.0
		tp.gravity = Vector2.ZERO
		tp.initial_velocity_min = 22.0
		tp.initial_velocity_max = 50.0
		tp.scale_amount_min = 2.0
		tp.scale_amount_max = 4.5
		tp.color = Color(1.0, 0.62, 0.25, 0.85)
		_additive(tp)
		title_group.add_child(tp)
		torches.append(tp)
	if contract.giver.line != null:
		demon_line = Kit.lbl(self, String(contract.giver.line), Vector2(36, 800), 440, 22, Color(1.0, 0.9, 0.7), "heading", HORIZONTAL_ALIGNMENT_LEFT, true, true)
		demon_line.modulate.a = 0.0
	lever = Lever.new()
	lever.position = Vector2(1300, 190)
	lever.pressed.connect(func(): reroll_requested.emit())
	add_child(lever)
	reroll_requested.connect(_on_lever)
	side = Parts.SidePanel.new()
	side.position = Vector2(1376, 150)
	side.setup(1580.0 - 1376.0, 560.0, ui)
	add_child(side)
	side.show_card(cards[0], false)
	side.modulate.a = 0.0
	owned_row = Kit.OwnedRow.new()
	owned_row.build(contract.owned, ui, 50.0)
	owned_row.position = Vector2(RX0, 800)
	add_child(owned_row)
	handle = Kit.Handle.new()
	handle.build(String(ui.key_reroll), String(ui.reroll), String(contract.reroll.left_label), 240.0, 46.0)
	handle.position = Vector2(1340, 800)
	handle.size.x = 240.0
	handle.pressed.connect(func(): reroll_requested.emit())
	add_child(handle)
	Kit.lbl(self, String(ui.hint), Vector2(RX0 + 350.0, 862), 400, 14, Palette.INK_FAINT, "body", HORIZONTAL_ALIGNMENT_LEFT, false)
	if String(contract.get("odds", "")) != "":
		Kit.lbl(self, String(contract.odds), Vector2(RX0, 862), 330, 14, Palette.INK_DIM, "body", HORIZONTAL_ALIGNMENT_LEFT, false)
	var remove_h := Kit.Handle.new()
	remove_h.build(String(ui.key_exclude), String(ui.exclude), String(contract.exclude.left_label), 190.0, 46.0)
	remove_h.position = Vector2(944, 800)
	add_child(remove_h)
	var keep_h := Kit.Handle.new()
	keep_h.build("V", String(ui.keep), String(contract.keep.left_label), 190.0, 46.0)
	keep_h.position = Vector2(1144, 800)
	add_child(keep_h)
	if String(fig.get("caption", "")) != "":
		Kit.lbl(self, String(fig.caption), Vector2(24, 862), 420, 14, Palette.INK_FAINT, "body", HORIZONTAL_ALIGNMENT_LEFT, false)
	links = Parts.LinkLayer.new()
	add_child(links)
	# effects on top
	rays = Rays.new()
	add_child(rays)
	spark = CPUParticles2D.new()
	spark.emitting = false
	spark.one_shot = true
	spark.explosiveness = 1.0
	spark.amount = 90
	spark.lifetime = 1.2
	spark.direction = Vector2(0, -1)
	spark.spread = 180.0
	spark.gravity = Vector2(0, 260)
	spark.initial_velocity_min = 180.0
	spark.initial_velocity_max = 520.0
	spark.scale_amount_min = 2.5
	spark.scale_amount_max = 6.0
	spark.color = Color(1.0, 0.82, 0.4, 1.0)
	_additive(spark)
	add_child(spark)
	banner = Label.new()
	banner.text = String(ui.get("fated_banner", ""))
	banner.add_theme_font_override("font", Kit.Loc.font("heading"))
	banner.add_theme_font_size_override("font_size", 64)
	banner.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5))
	banner.add_theme_color_override("font_outline_color", Color(0.35, 0.14, 0.02))
	banner.add_theme_constant_override("outline_size", 8)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.size = Vector2(240, 90)
	banner.pivot_offset = banner.size * 0.5
	banner.modulate.a = 0.0
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)
	flash = ColorRect.new()
	flash.color = Color(1, 0.97, 0.88, 0.0)
	flash.size = Kit.SIZE
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_additive(flash)
	add_child(flash)

func _process(delta: float) -> void:
	super._process(delta)
	if figure != null:
		figure.position.y = BOB * sin(clock * TAU / 2.7)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 60.0)
		position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
	elif position != Vector2.ZERO:
		position = Vector2.ZERO

func _fade(n: CanvasItem, delay: float, dur: float) -> void:
	n.modulate.a = 0.0
	var tw := track(create_tween())
	tw.tween_interval(delay)
	tw.tween_property(n, "modulate:a", 1.0, dur)

func _reset_visuals() -> void:
	for k in 3:
		reels[k].reset_strip()
		reels[k].visible = true
		cards_v[k].visible = false
		cards_v[k].modulate = Color(1, 1, 1, 1)
		cards_v[k].scale = Vector2.ONE
		cards_v[k].position = rest[k]
		cards_v[k].set_focus_amount(0.0)
		cards_v[k].modulate.a = 1.0
	focus_index = -1
	housing.heat = 0.0
	housing.lamp_mode = 1
	side.modulate.a = 0.0
	links.amount = 0.0
	owned_row.lit_amount = 0.0
	banner.modulate.a = 0.0
	flash.color.a = 0.0
	rays.amount = 0.0
	lever.th = 0.28
	if demon_line != null: demon_line.modulate.a = 0.0
	for g in eye_glows: g.modulate.a = 0.0

## Spin plan of one reel: linear fast part, a decelerating tail that lands on the card with a small overshoot and a clunk back.
func _plan_reel(k: int, stop_t: float, tail: float, t_slow: float) -> void:
	var rl = reels[k]
	var t_fast := maxf(0.05, stop_t - 0.05 - t_slow)
	var tw := track(create_tween())
	tw.tween_interval(0.05)
	tw.tween_property(rl.strip, "position:y", -(rl.total - tail), t_fast)
	tw.tween_property(rl.strip, "position:y", -(rl.total + 14.0), t_slow).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	tw.tween_callback(func(): _thunk(k))
	tw.tween_property(rl.strip, "position:y", -rl.total, 0.07).set_ease(Tween.EASE_IN_OUT)

func _thunk(k: int) -> void:
	mark("reel_%d_stop" % k)
	var c: Dictionary = cards[k]
	var rank := Kit.grade_rank(String(c.grade))
	cards_v[k].visible = true
	reels[k].strip.visible = true
	_shake = 3.0 if rank < 3 else 0.0
	var f := ColorRect.new()
	f.size = Vector2(REEL_W, REEL_H)
	f.position = rest[k]
	f.color = Color(1, 1, 1, 0.34) if rank < 2 else Color(0.6, 0.78, 1.0, 0.55)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_additive(f)
	add_child(f)
	var tw := create_tween()
	tw.tween_property(f, "color:a", 0.0, 0.2)
	tw.tween_callback(f.queue_free)
	_demon_pulse(Kit.el_color(String(contract.witch.element)), 0.5 if rank < 2 else 0.8)
	if rank == 2: _ring(rest[k] + Vector2(REEL_W, REEL_H) * 0.5, Kit.grade_color(String(c.grade)), 0.5)

func _demon_pulse(col: Color, strength: float) -> void:
	var g := Kit.add_glow(figure, demon_hand, 70.0, Kit.with_alpha(col, strength))
	var tw := create_tween()
	tw.tween_property(g, "modulate:a", 0.0, 0.3)
	tw.tween_callback(g.queue_free)

func _ring(centre: Vector2, col: Color, life: float) -> void:
	var g := Kit.add_glow(self, centre, 60.0, Kit.with_alpha(col, 0.8))
	var tw := create_tween().set_parallel(true)
	tw.tween_property(g, "scale", Vector2(3.2, 3.2), life).set_ease(Tween.EASE_OUT)
	g.pivot_offset = g.size * 0.5
	tw.tween_property(g, "modulate:a", 0.0, life)
	tw.chain().tween_callback(g.queue_free)

func _intro() -> float:
	_reset_visuals()
	var dim: ColorRect = backdrop.get_node("Dim")
	dim.color.a = 0.35
	track(create_tween()).tween_property(dim, "color:a", 0.9, 0.35)
	pillar.position.x = 110
	pillar.modulate = Kit.with_alpha(Kit.el_color(String(contract.witch.element)).lightened(0.25), 0.0)
	var tp := track(create_tween())
	tp.tween_property(pillar, "modulate:a", 0.9, 0.1)
	tp.tween_property(pillar, "modulate:a", 0.18, 0.45)
	_fade(figure, 0.12, 0.38)
	for n in [housing, title_group]: _fade(n, 0.0, 0.3)
	for r in reels: _fade(r, 0.0, 0.25)
	_fade(lever, 0.0, 0.3)
	for n in [owned_row, handle]: _fade(n, 0.55, 0.3)
	var t_c := 1.1
	var lucky := fate_index >= 0
	for k in stop_order.size():
		var idx: int = stop_order[k]
		var stop_t := 0.55 + 0.23 * float(k)
		if lucky and idx == fate_index:
			_plan_reel(idx, 2.4, 1300.0, 1.55)
		else:
			_plan_reel(idx, stop_t, 620.0, 0.28)
	if lucky:
		t_c = 2.5
		var th := track(create_tween())
		th.tween_interval(0.95)
		th.tween_callback(func():
			mark("tension_begins")
			housing.lamp_mode = 2
			housing.heat_window = fate_index
			for g in eye_glows: create_tween().tween_property(g, "modulate:a", 0.9, 0.7))
		th.tween_property(housing, "heat", 1.0, 0.9)
		var td := track(create_tween())
		td.tween_interval(1.65)
		td.tween_callback(func(): mark("screen_dims"))
		td.tween_property(dim, "color:a", 0.985, 0.35)
		var tb := track(create_tween())
		tb.tween_interval(2.4)
		tb.tween_callback(_burst)
	else:
		var tl := track(create_tween())
		tl.tween_interval(1.0)
		tl.tween_callback(func(): housing.lamp_mode = 0)
	if demon_line != null and fate_index < 0:
		demon_line.modulate.a = 0.0
		track(create_tween()).tween_property(demon_line, "modulate:a", 1.0, 0.4).set_delay(0.7)
	var tf := track(create_tween())
	tf.tween_interval(t_c)
	tf.tween_callback(func():
		if focus_index < 0: set_focus(fate_index if fate_index >= 0 else _first_rare())
		housing.lamp_mode = 3 if lucky else 0)
	return t_c

func _first_rare() -> int:
	return best_index()

## The FATED burst: flash, light pillar over the reel, rotating rays, sparks, the word, the card bigger and brighter, the figures flare.
func _burst() -> void:
	mark("fated_burst")
	var k := fate_index
	var centre: Vector2 = rest[k] + Vector2(REEL_W, REEL_H) * 0.5
	var dim: ColorRect = backdrop.get_node("Dim")
	track(create_tween()).tween_property(dim, "color:a", 0.84, 0.4)
	flash.color.a = 0.9
	track(create_tween()).tween_property(flash, "color:a", 0.0, 0.4)
	_shake = 9.0
	housing.heat = 1.4
	housing.lamp_mode = 3
	var gold := Kit.grade_color("fated")
	pillar.position.x = centre.x - 130.0
	pillar.modulate = Color(1.0, 0.82, 0.45, 1.0)
	track(create_tween()).tween_property(pillar, "modulate:a", 0.45, 0.8)
	rays.centre = centre
	rays.amount = 1.0
	track(create_tween()).tween_property(rays, "amount", 0.35, 1.0)
	spark.position = centre
	spark.restart()
	spark.emitting = true
	_ring(centre, gold, 0.7)
	banner.position = Vector2(centre.x - 120.0, rest[k].y - 56.0)
	banner.scale = Vector2(0.4, 0.4)
	var tb := track(create_tween()).set_parallel(true)
	tb.tween_property(banner, "modulate:a", 1.0, 0.12)
	tb.tween_property(banner, "scale", Vector2(1.0, 1.0), 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	for j in 3:
		if j == k: continue
		var tw := create_tween()
		tw.tween_property(cards_v[j], "modulate", Color(0.52, 0.52, 0.56, 1.0), 0.3)
	witch_glow.modulate = Kit.with_alpha(gold, 0.95)
	create_tween().tween_property(witch_glow, "modulate", Kit.with_alpha(gold, 0.5), 1.2)
	for g in eye_glows:
		g.modulate = Kit.with_alpha(Color(1.0, 0.9, 0.55), 1.0)
		create_tween().tween_property(g, "modulate:a", 0.55, 1.2)
	if demon_line != null: create_tween().tween_property(demon_line, "modulate:a", 1.0, 0.4).set_delay(0.3)

func _settle_all() -> void:
	for n in [housing, title_group, figure, lever, owned_row, handle]: n.modulate.a = 1.0
	for k in 3:
		reels[k].modulate.a = 1.0
		reels[k].strip.position.y = -reels[k].total
		cards_v[k].visible = true
	pillar.modulate.a = 0.18
	backdrop.get_node("Dim").color.a = 0.84
	housing.lamp_mode = 0
	if fate_index >= 0:
		banner.modulate.a = 1.0
		banner.scale = Vector2.ONE
		banner.position = Vector2(rest[fate_index].x + REEL_W * 0.5 - 120.0, rest[fate_index].y - 56.0)
		for j in 3:
			if j != fate_index: cards_v[j].modulate = Color(0.52, 0.52, 0.56, 1.0)
		housing.heat = 1.0
	if focus_index < 0: set_focus(fate_index if fate_index >= 0 else _first_rare())

func _apply_focus(v: float, i: int) -> void:
	var c = cards_v[i]
	c.set_focus_amount(v)
	if String(cards[i].grade) == "fated": c.scale = Vector2.ONE * (1.0 + 0.07 * maxf(v, 0.6))
	if fate_index >= 0 and i != fate_index: c.modulate = Color(0.52, 0.52, 0.56).lerp(Color.WHITE, v * 0.45)

func _focus_changed(_old: int, new: int) -> void:
	for i in 3:
		var c = cards_v[i]
		var f := 1.0 if i == new else 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_method(_apply_focus.bind(i), c.focus, f, 0.14)
		tw.tween_property(c, "position:y", float(rest[i].y) - (8.0 if i == new else 0.0), 0.14).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	create_tween().tween_property(cards_v[new], "sweep", 1.0, 0.3).from(0.0)
	side.show_card(cards[new])
	side.modulate.a = 1.0
	var ec := Kit.grade_color("fated") if String(cards[new].grade) == "fated" else Kit.el_color(String(cards[new].element))
	create_tween().tween_property(witch_glow, "modulate", Kit.with_alpha(ec, 0.5), 0.2)
	var slots: Array = owned_row.link_slots(cards[new])
	owned_row.lit = slots
	links.links = []
	var target := Vector2(float(rest[new].x) + REEL_W * 0.5, float(rest[new].y) + REEL_H)
	for s in slots:
		links.links.append([owned_row.global_position + owned_row.slot_centre("spell", s) + Vector2(0, -26), target])
	links.amount = 0.0
	owned_row.lit_amount = 0.0
	var tl := create_tween().set_parallel(true)
	tl.tween_property(links, "amount", 1.0, 0.22)
	tl.tween_property(owned_row, "lit_amount", 1.0, 0.22)

func _confirm_anim(i: int) -> float:
	var c = cards_v[i]
	var tgt: Vector2 = owned_row.target_for(cards[i])
	var fated := String(cards[i].grade) == "fated"
	var tw := create_tween()
	tw.tween_property(c, "position:y", c.position.y - 10.0, 0.07)
	tw.set_parallel(true)
	tw.tween_property(c, "position", tgt - c.size * 0.5, 0.28).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(c, "scale", Vector2(0.16, 0.16), 0.28).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(c, "modulate:a", 0.0, 0.1).set_delay(0.25)
	for k in 3:
		if k == i: continue
		var o = cards_v[k]
		var t2 := create_tween().set_parallel(true)
		t2.tween_property(o, "modulate:a", 0.0, 0.22)
		t2.tween_property(o, "position:y", o.position.y + 24.0, 0.22)
	create_tween().tween_property(links, "amount", 0.0, 0.15)
	create_tween().tween_property(side, "modulate:a", 0.0, 0.15)
	create_tween().tween_property(banner, "modulate:a", 0.0, 0.2)
	create_tween().tween_property(rays, "amount", 0.0, 0.3)
	housing.lamp_mode = 0
	_demon_pulse(Kit.grade_color("fated"), 1.0)
	witch_glow.modulate = Kit.with_alpha(Kit.grade_color("fated"), 0.9)
	create_tween().tween_property(witch_glow, "modulate", Kit.with_alpha(Kit.el_color(String(contract.witch.element)), 0.35), 0.5)
	var t3 := create_tween()
	t3.tween_interval(0.35)
	t3.tween_callback(func(): _dock(i, tgt, fated))
	return 0.75 if fated else 0.62

func _dock(i: int, tgt: Vector2, fated: bool) -> void:
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
	var col := Kit.grade_color("fated") if fated else Kit.el_color(String(card.element))
	var gl := Kit.add_glow(owned_row, owned_row.make_canvas_position_local(tgt), 80.0 if fated else 46.0, Kit.with_alpha(col, 0.9 if fated else 0.7))
	var t4 := create_tween()
	t4.tween_property(gl, "modulate:a", 0.0, 0.45 if fated else 0.3)
	t4.tween_callback(gl.queue_free)
	if fated:
		flash.color.a = 0.35
		create_tween().tween_property(flash, "color:a", 0.0, 0.3)
		_ring(tgt, col, 0.6)
		create_tween().tween_property(witch_glow, "modulate", Kit.with_alpha(col, 0.95), 0.15)
	mark("socketed")

func _on_lever() -> void:
	if state != "ready": return
	mark("lever_pulled")
	var tw := create_tween()
	tw.tween_property(lever, "th", 2.5, 0.22).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): play_intro())
	tw.tween_property(lever, "th", 0.28, 0.4).set_ease(Tween.EASE_OUT)
