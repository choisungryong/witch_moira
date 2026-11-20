extends "res://chapter1/tests/proposals/title/base.gd"
## Proposal C "one person's stage" (docs/screens/title/BRIEF-20261120.ko.md 3.3). Title and choice are two states of ONE stage.
## The witch's world is the whole screen and she stands head to shin, taller than the screen. The title state shows the logo and a five-word
## menu (no panel); "start" slides a narrow leather strip in from the left (medals, title, one line, traits, start skill, level, three
## actions, one button). Changing the witch sweeps a band of her element colour across the screen and the world is replaced; the
## new figure plays the portrait entrance. Start: strip and text leave, camera 1.00 -> 1.08 on face and chest, the element bursts, a flash,
## the witch's confirm line (optional, fixture) hangs at the bottom for 0.7 s, darkness rises from the bottom. 1.30 s. Motion 0: 0.40 s fade.
## The contract demon (BRIEF 3.5.4) stands behind the witch on the right in every select state (devil_mode face | shade | none), brighter in the confirm.
## Layout numbers are 1080p pixels (BRIEF) converted with Parts.px. Placeholders (NEW ART NEEDED): demon pictures (drafts read from _local),
## the word-mark, the leather strip face (ui_style window piece), the medals (cut from the L4_head layer).

const SCALE := [0.864, 0.864, 0.816]
const AXIS_X := [1212.0, 1212.0, 1248.0]
const TOP_Y := -19.0
const BAND := Rect2(48, 72, 640, 928)
const BAND_PAD := 16.0
const SWEEP := 0.35
const AUTO_SWAP := 12.0
const DEVIL_AREA := [Rect2(1300, 0, 620, 620), Rect2(1400, -440, 520, 620), Rect2(1300, 0, 620, 620)]
const MENU_X := 250.0
const MENU_Y := 470.0
const MENU_STEP := 68.0
const MEDAL_D := 112.0
const Dress = preload("res://chapter1/tests/proposals/title/dress.gd")
const BLOCK := {"width": 440.0, "plaque": 300.0, "note_h": 150.0, "hint": true}

var worlds: Array = []
var world_stage: Control
var strip: Control
var medals: Array = []
var menu_items: Array = []
var menu_focus := 0
var stage_name := "title"       ## title | select
var stage_t0 := -100.0
var stage_target := "title"
var last_input := 0.0
var autoswap := true
var sweep_band: Control
var flash: ColorRect
var dim: ColorRect
var rise: Control
var logo: Label
var logo_font: FontVariation
var hint: Control
var confirm_line: Label
var burst: Control
var _intro_stamp := -12345.0
var _last_rect: Array = [Rect2(), Rect2(), Rect2()]
var _pm: Array = [-1.0, -1.0, -1.0]
var _pfx: Array = [false, false, false]
var _pi: Array = [-1.0, -1.0, -1.0]

static func make(c: Dictionary) -> Control:
	var s = load("res://chapter1/tests/proposals/title/c.gd").new()
	s.setup(c)
	return s

func _base_intro_len() -> float:
	return 1.1

func _base_confirm_len() -> float:
	return 1.3

# ---------------------------------------------------------------- inner controls

class Ring extends Control:
	var color := Color.WHITE
	var width := 2.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_arc(size * 0.5, size.x * 0.5 - width * 0.5, 0, TAU, 56, color, width, true)

## Round medal: the face is cut from the witch's own L4_head layer (nothing generated); ring + brightness show the focus (shape: thicker ring).
class Medal extends Control:
	signal pressed
	var face: TextureRect
	var ring: Control
	var amount := 0.0:
		set(v):
			amount = v
			if face != null:
				var b := lerpf(0.55, 1.0, v)
				face.modulate = Color(b, b, b, 1.0)
				var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
				ring.set("color", Color(kit.Palette.BRASS_DIM).lerp(kit.Palette.BRASS_HI, v))
				ring.set("width", lerpf(2.0, 4.0, v))
				ring.queue_redraw()
	func setup(tex: Texture2D, d: float) -> void:
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		size = Vector2(d, d)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		face = TextureRect.new()
		face.texture = tex
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_SCALE
		face.size = size
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nvoid fragment(){ vec4 c = texture(TEXTURE, UV); float d = length(UV - vec2(0.5)); COLOR = vec4(c.rgb, c.a * (1.0 - smoothstep(0.46, 0.5, d))); }\n"
		var m := ShaderMaterial.new()
		m.shader = sh
		face.material = m
		add_child(face)
		ring = Ring.new()
		ring.size = size
		add_child(ring)
		amount = 0.0
		gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				pressed.emit())
	func _draw() -> void:
		draw_circle(size * 0.5, size.x * 0.5, Color(0.03, 0.035, 0.04, 1.0))

class MenuItem extends Control:
	signal pressed
	signal hovered
	var label: Label
	var on := false:
		set(v):
			on = v
			if label != null:
				var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
				label.add_theme_color_override("font_color", kit.Palette.INK if v else kit.Palette.INK_DIM)
			queue_redraw()
	func setup(text: String, font_px: int, w: float) -> void:
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		label = kit.lbl(self, text, Vector2(float(font_px) * 0.9, 0), w, font_px, kit.Palette.INK_DIM, "heading", HORIZONTAL_ALIGNMENT_LEFT, false, true)
		size = Vector2(w + float(font_px) * 0.9, label.size.y)
		label.position.y = 0
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func(): hovered.emit())
		gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				pressed.emit())
	func _draw() -> void:
		if not on:
			return
		var kit = load("res://chapter1/tests/proposals/growth_choice/kit.gd")
		var parts = load("res://chapter1/view/hud/ui_parts.gd")  ## the leather strip of the grace screen's bands, as the highlighted row's plate
		var pad := 10.0
		var ph := size.y + pad * 0.8
		var cap := 125.0 * (ph / 51.7)  ## the left cap of the strip is ~2.4 x its height wide; the word starts after the buckle
		var plate := Rect2(-cap * 0.78, -pad * 0.4, size.x + cap * 0.78 + 90.0, ph)
		draw_set_transform(plate.position)
		parts.Band.paint(self, plate.size.x, plate.size.y)
		draw_set_transform(Vector2.ZERO)
		kit.diamond(self, Vector2(float(label.get_theme_font_size("font_size")) * 0.3, size.y * 0.5), 5.0, kit.Palette.BRASS_HI)

## The container the text column slides in with. It paints nothing itself: a soft shade of the panel colour lies behind the column (added in _build),
## the leather, brass and parchment are the column's own parts (dress.gd). It never takes the mouse.
class Strip extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

# ---------------------------------------------------------------- build

func _build() -> void:
	autoswap = bool(contract.get("title_autoswap", true))
	Parts.rect_node(self, Rect2(Vector2.ZERO, size), Color(0.01, 0.012, 0.016, 1.0))
	world_stage = Control.new()
	world_stage.size = size
	world_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world_stage)
	var devil_mode := String(contract.get("devil_mode", "face"))
	for i in 3:
		var reveal := Control.new()
		reveal.clip_contents = true
		reveal.size = size
		reveal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		reveal.name = "World%d" % i
		world_stage.add_child(reveal)
		var content := Control.new()
		content.size = size
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		reveal.add_child(content)
		var tex := Parts.far_texture(i, 56, 0.6)
		var cover := Parts.cover_rect(Parts.CANVAS, size)
		var far := TextureRect.new()
		far.texture = tex
		far.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		far.stretch_mode = TextureRect.STRETCH_SCALE
		far.position = cover.position
		far.size = cover.size
		far.modulate = Color(0.45, 0.45, 0.45, 1.0)
		far.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(far)
		var p := Parts.make_portrait(i)
		content.add_child(p)
		portraits.append(p)
		var edge := TextureRect.new()
		edge.texture = tex
		edge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		edge.stretch_mode = TextureRect.STRETCH_SCALE
		edge.position = cover.position
		edge.size = cover.size
		edge.modulate = Color(0.45, 0.45, 0.45, 1.0)
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var half := 512.0 * float(SCALE[i]) * Parts.K
		var xc := Parts.px(float(AXIS_X[i]))
		edge.z_index = 9  ## above the portrait entrance veil (z 7), so the veil never shows a hard-edged box
		edge.material = Parts.edge_cover_material(xc - half - cover.position.x, xc + half - cover.position.x, Parts.px(120.0), cover.size.x)
		content.add_child(edge)
		# rim light: it cannot sit BEHIND the figure (the portrait draws background and figure in one node), so it lies over both, low
		var rim := TextureRect.new()
		rim.texture = Kit.glow()
		rim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rim.stretch_mode = TextureRect.STRETCH_SCALE
		rim.material = Parts.additive()
		rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ec := Parts.el_color(i)
		rim.modulate = Color(ec.r, ec.g, ec.b, 0.22)
		rim.size = Vector2(Parts.px(760.0), Parts.px(620.0))
		rim.position = Vector2(xc - rim.size.x * 0.5, Parts.px(450.0) - rim.size.y * 0.5)
		content.add_child(rim)
		Parts.hgrad(content, Rect2(0, 0, Parts.px(760.0), size.y), Color(Palette.SURFACE.r, Palette.SURFACE.g, Palette.SURFACE.b, 0.75), Color(Palette.SURFACE.r, Palette.SURFACE.g, Palette.SURFACE.b, 0.0))
		Parts.vgrad(content, Rect2(0, size.y * 0.5, size.x, size.y * 0.5), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.55))
		var d := Parts.Devil.new()
		var area: Rect2 = DEVIL_AREA[i]
		var def: Dictionary = cards[i].get("devil", {})
		d.build(def, String(Parts.ELEM[i]), Vector2(Parts.px(area.size.x), Parts.px(area.size.y)), devil_mode == "shade", String(ui.placeholder_art), def.get("eyes", []))
		d.position = Vector2(Parts.px(area.position.x), Parts.px(area.position.y))
		d.pivot_offset = d.size * 0.5
		content.add_child(d)
		var rise := Parts.Rise.new()  ## entrance darkness over the whole world (the portrait's own veil only covers its picture box)
		rise.z_index = 9
		rise.size = size
		content.add_child(rise)
		worlds.append({"reveal": reveal, "content": content, "devil": d, "rise": rise})
	sweep_band = Parts.hband(world_stage, Rect2(0, 0, Parts.px(240.0), size.y), Color(1, 1, 1, 1), true)
	sweep_band.visible = false
	sweep_band.z_index = 6
	burst = Parts.Burst.new()
	burst.size = size
	burst.unit = 1.7
	world_stage.add_child(burst)
	# the leather strip
	strip = Strip.new()
	strip.size = Vector2(Parts.px(BAND.size.x), Parts.px(BAND.size.y))
	add_child(strip)
	Parts.hgrad(strip, Rect2(-Parts.px(BAND.position.x), -Parts.px(BAND.position.y), Parts.px(BAND.size.x + 320.0), size.y), Color(Palette.SURFACE.r, Palette.SURFACE.g, Palette.SURFACE.b, 0.90), Color(Palette.SURFACE.r, Palette.SURFACE.g, Palette.SURFACE.b, 0.0))
	var ui_names := ["ember", "frost", "storm"]
	var medal_total := MEDAL_D * 3.0 + 20.0 * 2.0
	var medal_x0 := (BAND.size.x - medal_total) * 0.5
	for i in 3:
		var m := Medal.new()
		m.setup(_medal_texture(i, String(ui_names[i])), Parts.px(MEDAL_D))
		m.position = Vector2(Parts.px(medal_x0 + (MEDAL_D + 20.0) * float(i)), Parts.px(16.0))
		var idx := i
		m.pressed.connect(func(): if state == "ready": set_focus(idx))
		strip.add_child(m)
		medals.append(m)
	for i in 3:
		var b: Dictionary = Dress.build_block(i, cards[i], ui, profile, BLOCK)
		strip.add_child(b.root)
		blocks.append(b)
	_wire_blocks()
	# title state: the menu
	var menu_keys := ["menu_start", "menu_costume", "menu_settings", "menu_credits", "menu_quit"]
	var menu_actions := ["title_start", "open_costume", "open_settings", "open_credits", "quit_request"]
	for k in menu_keys.size():
		var mi := MenuItem.new()
		mi.setup(String(ui[menu_keys[k]]), Parts.fs(34.0), Parts.px(420.0))
		mi.position = Vector2(Parts.px(MENU_X - 34.0 * 0.9), Parts.px(MENU_Y + MENU_STEP * float(k)))
		var kk := k
		mi.hovered.connect(func(): if state == "ready" and stage_target == "title": menu_focus = kk)
		mi.pressed.connect(func(): if state == "ready" and stage_target == "title": _menu_activate(kk))
		add_child(mi)
		menu_items.append(mi)
	_menu_actions = menu_actions
	logo_font = FontVariation.new()
	logo_font.base_font = Kit.Loc.font("heading")
	logo = Label.new()
	logo.text = String(ui.logo)
	logo.add_theme_font_override("font", logo_font)
	logo.add_theme_color_override("font_color", Palette.BRASS)
	logo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	logo.add_theme_constant_override("shadow_offset_y", 2)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	hint = Dress.HintRow.new()  ## the title state's key line (the select state's one lives in the column)
	hint.setup([["↑↓", String(ui.get("hint_pick", "고르기"))], ["Enter", String(ui.get("hint_ok", "확인"))], ["Esc", String(ui.get("hint_menu", "메뉴"))]], Parts.px(460.0))
	hint.position = Vector2(Parts.px(MENU_X - 34.0), Parts.px(MENU_Y + MENU_STEP * 5.0 + 24.0))
	add_child(hint)
	confirm_line = Label.new()
	confirm_line.add_theme_font_override("font", Kit.Loc.font("heading"))
	confirm_line.add_theme_font_size_override("font_size", Parts.fs(36.0))
	confirm_line.add_theme_color_override("font_color", Palette.INK)
	confirm_line.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	confirm_line.add_theme_constant_override("shadow_offset_y", 2)
	confirm_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_line.size = Vector2(size.x, Parts.px(60.0))
	confirm_line.position = Vector2(0, Parts.px(900.0))
	confirm_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	confirm_line.modulate.a = 0.0
	add_child(confirm_line)
	marker = Parts.Marker.new()
	add_child(marker)
	flash = ColorRect.new()
	flash.size = size
	flash.color = Color(0, 0, 0, 0)
	flash.material = Parts.additive()
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 25
	add_child(flash)
	dim = ColorRect.new()
	dim.size = size
	dim.color = Color(0, 0, 0, 0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.z_index = 28
	add_child(dim)
	rise = Parts.Rise.new()
	rise.size = size
	add_child(rise)
	for k in range(1, get_child_count()):  ## everything above the stage sits over the edge covers (z 9)
		var ch := get_child(k)
		if ch != world_stage and ch is CanvasItem and (ch as CanvasItem).z_index == 0:
			(ch as CanvasItem).z_index = 10
	_update()

var _menu_actions: Array = []

func _medal_texture(i: int, id: String) -> Texture2D:
	var path := ProjectSettings.globalize_path("res://chapter1/art/portraits/%s/layers/L4_head.png" % id)
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	var used := img.get_used_rect()  ## the head layer is only the head (about 200 px tall): a square around exactly what is drawn
	var side := int(maxi(used.size.x, used.size.y)) + 8
	var region := Rect2i(used.position.x + used.size.x / 2 - side / 2, used.position.y - 4, side, side)
	region = region.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	return ImageTexture.create_from_image(img.get_region(region))

# ---------------------------------------------------------------- time

func _e() -> float:
	match state:
		"idle": return 0.0
		"intro": return clock - intro_t0
	return 1000.0

func _ce() -> float:
	return clock - confirm_t0 if state == "confirm" or state == "done" else -1.0

func _stage_f() -> float:
	var t := clock - stage_t0
	return Parts.ramp(t, 0.0, 0.30) if stage_target == "select" else 1.0 - Parts.ramp(t, 0.0, 0.30)

func prepare_still(stage: String) -> void:
	if stage == "select":
		_title_start()
	elif stage == "title":
		_back_to_title()

func _title_start() -> void:
	if stage_target == "select" or state != "ready":
		return
	stage_target = "select"
	stage_name = "select"
	stage_t0 = clock
	mark("title_start")
	ui_focus = 0

func _back_to_title() -> void:
	if stage_target == "title":
		return
	stage_target = "title"
	stage_name = "title"
	stage_t0 = clock
	mark("back_to_title")

func _menu_activate(k: int) -> void:
	match String(_menu_actions[k]):
		"title_start": _title_start()
		var other: request.emit(other, focus_index)

func _escape() -> void:
	if stage_target == "select":
		_back_to_title()
	else:
		menu_focus = 4

func _ui_control(code: int) -> Control:
	if stage_target == "title":
		return menu_items[menu_focus]
	return super._ui_control(code)

func _on_key(code: int) -> void:
	last_input = clock
	if stage_target == "title":
		match code:
			KEY_UP: menu_focus = posmod(menu_focus - 1, menu_items.size())
			KEY_DOWN, KEY_TAB: menu_focus = posmod(menu_focus + 1, menu_items.size())
			KEY_ENTER, KEY_KP_ENTER: _menu_activate(menu_focus)
			KEY_Q, KEY_LEFT: set_focus(posmod(focus_index - 1, cards.size()))
			KEY_E, KEY_RIGHT: set_focus(posmod(focus_index + 1, cards.size()))
			KEY_ESCAPE: _escape()
			_: pass
		return
	super._on_key(code)

func _gui_input(e: InputEvent) -> void:
	last_input = clock
	super._gui_input(e)

func _on_focus(_old: int, new_: int) -> void:
	last_input = clock
	events.append({"t": snappedf(clock - intro_t0, 0.001), "e": "witch_focus(%s)" % String(Parts.ELEM[new_])})
	_pm = [-1.0, -1.0, -1.0]

func _on_confirm(i: int) -> void:
	events.append({"t": snappedf(clock - intro_t0, 0.001), "e": "witch_confirm(%s)" % String(Parts.ELEM[i])})
	if stage_target != "select":
		stage_target = "select"
		stage_name = "select"
		stage_t0 = clock - 1.0

func _on_skip_intro(_shift: float) -> void:
	pass

func _drive_portraits() -> void:
	for i in portraits.size():
		if (worlds[i].reveal as Control).visible:
			(portraits[i] as Node2D).call("advance_to", clock + shift_bonus)

# ---------------------------------------------------------------- geometry

## C: the figure of witch i, same in every state (the world replaces, nothing slides): returns px values.
func _geom(i: int) -> Dictionary:
	var s := float(SCALE[i])
	var x := float(AXIS_X[i])
	var face: Vector2 = Parts.FACE[i]
	var pelvis: Vector2 = Parts.PELVIS[i]
	return {"axis_x": x, "scale": s, "top": TOP_Y, "face": Vector2(x + (face.x - 512.0) * s, TOP_Y + face.y * s),
		"pelvis_x": x + (pelvis.x - 512.0) * s, "cut_frac": ((1080.0 - TOP_Y) / s) / Parts.CANVAS.y}

func settled_geometry(_j: int) -> Array:
	var out: Array = []
	for i in 3:
		out.append(_geom(i))
	return out

func _hover_at(_pos: Vector2) -> int:
	return -1  ## C changes the witch by medal click or key only (BRIEF 1.7), never by hovering

# ---------------------------------------------------------------- the picture

func _update() -> void:
	if worlds.is_empty():
		return
	var e := _e()
	var ce := _ce()
	var in_confirm := ce >= 0.0
	var motion_on := not reduce_motion
	var sf := _stage_f()
	var fe := clock - focus_t0
	# auto swap of the title stage (BRIEF 3.3.4: the director decides whether to keep it)
	if autoswap and state == "ready" and stage_target == "title" and clock - maxf(last_input, maxf(focus_t0, 0.0)) >= AUTO_SWAP:
		last_input = clock
		mark("auto_swap")
		move_focus(1)
	# portrait entrance: the first one at the start, later ones 0.20 s into the sweep
	if state != "idle" and focus_index >= 0 and _intro_stamp != focus_t0:
		var due := true if prev_focus < 0 else fe >= 0.2
		if due:
			_intro_stamp = focus_t0
			if not intro_skipped and not reduce_motion:
				(portraits[focus_index] as Node2D).call("advance_to", clock + shift_bonus)
				(portraits[focus_index] as Node2D).call("play_intro")
				var veil: Variant = (portraits[focus_index] as Node2D).get("_veil")
				if veil != null:
					(veil as CanvasItem).modulate.a = 0.0
				_pi[focus_index] = clock + shift_bonus
				mark_once("portrait_intro_%d" % focus_index)
	if state == "idle":
		_intro_stamp = -12345.0
	# which worlds are shown, and how the new one is revealed
	var sweeping := prev_focus >= 0 and fe < (SWEEP if motion_on else 0.1) and state != "idle" and focus_index >= 0
	var band_x := 0.0
	for i in 3:
		var w: Dictionary = worlds[i]
		var reveal: Control = w.reveal
		var content: Control = w.content
		var shown := state != "idle" and (i == focus_index or (sweeping and i == prev_focus))
		reveal.visible = shown
		reveal.z_index = 0
		reveal.position = Vector2.ZERO
		reveal.size = size
		content.position = Vector2.ZERO
		content.modulate = Color(1, 1, 1, 1)
		if not shown:
			continue
		if sweeping:
			var p := Parts.ease_out(fe / (SWEEP if motion_on else 0.1))
			if i == focus_index:
				reveal.z_index = 1
				band_x = lerpf(Parts.px(608.0 - 120.0), size.x + Parts.px(120.0), p)
				reveal.size = Vector2(clampf(band_x, 0.0, size.x), size.y)
			else:
				content.position.x = Parts.px(60.0) * p if motion_on else 0.0
				content.modulate.a = 1.0 - p
		var ra := 0.0
		if float(_pi[i]) >= 0.0:
			ra = (1.0 if prev_focus < 0 else 0.7) * (1.0 - Parts.smooth(Parts.ramp(clock + shift_bonus - float(_pi[i]), 0.0, 1.1 if prev_focus < 0 else 0.8)))
		w.rise.set("amount", ra)
		var g := _geom(i)
		var s_code := float(g.scale) * Parts.K
		var rect := Parts.portrait_rect(s_code, Vector2(512, 0), Vector2(Parts.px(float(g.axis_x)), Parts.px(TOP_Y)))
		if rect != _last_rect[i]:
			_last_rect[i] = rect
			(portraits[i] as Node2D).call("set_rect", rect, 1.0, Vector2(512, 0))
	sweep_band.visible = sweeping and motion_on and focus_index >= 0
	if sweep_band.visible:
		var bc := Parts.el_color(focus_index)
		sweep_band.modulate = Color(bc.r, bc.g, bc.b, 0.55 * (1.0 - Parts.ramp(fe, SWEEP * 0.7, SWEEP)))
		sweep_band.position.x = band_x - sweep_band.size.x * 0.5
	# portrait motion and effects: only the world in front moves
	for i in 3:
		var want := 0.0
		if i == focus_index and state != "idle":
			want = motion if motion_on else 0.0
			if in_confirm and motion_on:
				want = motion * (1.0 + 0.4 * Parts.ramp(ce, 0.25, 0.4))
		if absf(float(_pm[i]) - want) > 0.001:
			_pm[i] = want
			(portraits[i] as Node2D).call("set_motion_scale", want)
		var fx_on := i == focus_index and state != "idle" and (prev_focus < 0 or fe >= 0.2)
		if fx_on != bool(_pfx[i]):
			_pfx[i] = fx_on
			(portraits[i] as Node2D).call("set_flags", {"fx": fx_on, "glow": fx_on})
	# chrome alpha
	var chrome := 1.0
	if in_confirm:
		chrome = 1.0 - Parts.ramp(ce, 0.0, 0.15)
	# title state vs select state
	var tk := Parts.ease_out(sf)
	var strip_x := lerpf(Parts.px(-BAND.size.x - 16.0), Parts.px(BAND.position.x), tk)
	if in_confirm and motion_on:
		strip_x = lerpf(Parts.px(BAND.position.x), Parts.px(-BAND.size.x - 16.0), Parts.ramp(ce, 0.0, 0.2))
	strip.position = Vector2(strip_x, Parts.px(BAND.position.y))
	strip.visible = strip_x > -Parts.px(BAND.size.x)
	var menu_a := (1.0 - Parts.ramp(sf, 0.0, 0.6)) * chrome * (Parts.ramp(e, 0.6, 1.1) if state == "intro" else 1.0)
	for k in menu_items.size():
		var mi: Control = menu_items[k]
		mi.visible = menu_a > 0.01 and state != "idle"
		mi.modulate.a = menu_a
		mi.position.x = Parts.px(MENU_X - 34.0 * 0.9) - Parts.px(40.0) * Parts.ramp(sf, 0.0, 0.6)
		mi.set("on", k == menu_focus and stage_target == "title")
	# text bundles inside the strip: one per witch, the same appear / vanish as A
	for i in 3:
		var b: Dictionary = blocks[i]
		var a := block_alpha(i) * (Parts.ramp(sf, 0.5, 1.0) if prev_focus < 0 and state != "idle" else 1.0)
		if state == "intro":
			a = 0.0
		var root: Control = b.root
		var top_px := minf(150.0, BAND.size.y - 8.0 - float(b.height) / Parts.K)
		root.position = Vector2(Parts.px(BAND_PAD), Parts.px(top_px) + Parts.px(8.0) * (1.0 - a))
		root.visible = a > 0.01
		root.modulate.a = a
	for i in 3:
		(medals[i] as Control).set("amount", Parts.ease_out(focus_amount(i)) if state != "idle" else 0.0)
	# logo: big on the title, small on the select state
	_logo(sf, chrome, e)
	hint.modulate.a = chrome * (1.0 - Parts.ramp(sf, 0.0, 0.5)) * (1.0 if state != "idle" else 0.0)
	# the start button flash and the confirm
	if focus_index >= 0:
		var sb: Control = blocks[focus_index].start
		sb.set("flash", (1.0 - Parts.ramp(ce, 0.0, 0.06)) if in_confirm else 0.0)
	flash.color = Color(0, 0, 0, 0)
	burst.set("t", -1.0)
	world_stage.scale = Vector2.ONE
	world_stage.position = Vector2.ZERO
	dim.color = Color(0, 0, 0, 0)
	rise.set("amount", 0.0)
	confirm_line.modulate.a = 0.0
	# the contract demon behind the witch: shown a little after the world arrives, never on the title state
	var devil_mode := String(contract.get("devil_mode", "face"))
	for i in 3:
		var dv: Control = worlds[i].devil
		var amt := 0.0
		if i == focus_index and devil_mode != "none" and state != "idle":
			var wt := clock - (focus_t0 if prev_focus >= 0 else intro_t0)
			amt = 0.55 * Parts.ramp(wt, 1.5, 2.1) * Parts.ramp(sf, 0.6, 1.0)
		dv.set("amount", amt)
		dv.scale = Vector2.ONE
		dv.set("hand_drop", 0.0)
	if in_confirm and focus_index >= 0:
		var g2 := _geom(focus_index)
		var dev: Control = worlds[focus_index].devil
		if motion_on:
			var z := 1.0 + 0.08 * Parts.smooth(Parts.ramp(ce, 0.10, 0.50))
			world_stage.pivot_offset = Vector2(Parts.px(float(g2.axis_x)), Parts.px(float(g2.face.y) + 140.0))
			world_stage.scale = Vector2(z, z)
			if bool(settings.get("shake", false)) and ce >= 0.30 and ce < 0.50:
				world_stage.position = Vector2(sin(ce * 130.0) * 5.0, cos(ce * 110.0) * 5.0)
			var sym: Vector2 = Parts.SYMBOL[focus_index]
			burst.set("element", String(Parts.ELEM[focus_index]))
			burst.set("center", Vector2(Parts.px(float(g2.axis_x) + (sym.x - 512.0) * float(g2.scale)), Parts.px(float(g2.top) + sym.y * float(g2.scale))))
			burst.set("t", ce - 0.30 if ce >= 0.30 else -1.0)
			if ce >= 0.30:
				mark_once("burst_start")
				var fa := 0.34 * Parts.ramp(ce, 0.30, 0.36) if ce < 0.36 else 0.34 * (1.0 - Parts.ramp(ce, 0.36, 0.56))
				var fc := Parts.el_color(focus_index)
				flash.color = Color(fc.r * fa, fc.g * fa, fc.b * fa, 1.0)
			if devil_mode != "none":
				var base_amt: float = float(dev.get("amount"))
				var up := 0.6 * Parts.ramp(ce, 0.30, 0.40)
				dev.set("amount", maxf(base_amt, up))
				var dsc := 1.0 + 0.04 * Parts.ramp(ce, 0.30, 0.90)
				dev.scale = Vector2(dsc, dsc)
				dev.set("hand_drop", Parts.px(240.0) * Parts.ramp(ce, 0.30, 0.80))
				if ce >= 0.30:
					mark_once("devil_bright")
			rise.set("amount", Parts.ramp(ce, 0.60, 1.30))
			var line_on := bool(contract.get("confirm_line_on", true)) and String(cards[focus_index].get("confirm_line", "")) != ""
			if line_on:
				confirm_line.text = String(cards[focus_index].confirm_line)
				confirm_line.modulate.a = Parts.ramp(ce, 0.40, 0.50) * (1.0 - Parts.ramp(ce, 1.0, 1.10))
		else:
			dim.color = Color(0, 0, 0, Parts.ramp(ce, 0.0, 0.4))

func _logo(sf: float, chrome: float, e: float) -> void:
	var k := Parts.ease_out(sf)
	var big_px := 110.0
	var small_px := 34.0
	var fpx := lerpf(big_px, small_px, k)
	var code_px := Parts.fs(fpx)
	logo_font.spacing_glyph = int(round(fpx * 0.08 * Parts.K))
	logo.add_theme_font_size_override("font_size", code_px)
	var wpx: float = Kit.Loc.font("heading").get_string_size(String(ui.logo), HORIZONTAL_ALIGNMENT_LEFT, -1, code_px).x + float(String(ui.logo).length()) * float(logo_font.spacing_glyph)
	var h := Kit.line_height(code_px, "heading")
	logo.position = Vector2(Parts.px(120.0), Parts.px(150.0)).lerp(Vector2(Parts.px(48.0), Parts.px(32.0)), k)
	logo.size = Vector2(wpx + 8.0, h + 4.0)
	var a := Parts.ramp(e, 0.3, 0.8) if state == "intro" else (1.0 if state != "idle" else 0.0)
	logo.modulate.a = a * chrome
