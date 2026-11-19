extends "res://chapter1/tests/proposals/title/base.gd"
## Proposal A "three doors" (docs/screens/title/BRIEF-20261120.ko.md 3.2). Title and choice are ONE screen.
## Three witches stand full length side by side, each in a door of her own world; the focused door is 960 px wide, the other two 480.
## Moving the focus slides the door widths (0.30 s), the figure steps 0.66 -> 0.74 and lights up, her text bundle comes in.
## Start: the other doors go black, the chosen door opens to the whole screen, the camera moves 1.00 -> 1.08 on face and chest,
## the element bursts (placeholder: Parts.Burst; the real ones belong to vfx-feel), a flash, the contract demon shows 0.5 s (D14 /
## BRIEF 3.5.3), an iris closes. 1.20 s. Motion 0: no flash, no zoom, 0.40 s fade.
## Layout numbers are 1080p pixels (BRIEF), converted with Parts.px. Placeholders (NEW ART NEEDED): the demon pictures (drafts read from
## _local at run time), the word-mark (a title-font text), the front layer of the door seams (a dark gradient here).

const AXIS := [0.36, 0.70, 0.68]            ## where the figure's vertical axis stands inside the focused door (BRIEF 3.2.1)
const TEXT_X := [556.0, 544.0, 1024.0]      ## x of the text bundle when witch j has the focus (px)
const TEXT_SIDE := [1, -1, -1]              ## +1: the text is on the right of the door (shade comes from its right edge)
const S_FOCUS := 0.74
const S_DIM := 0.66
const FOOT_FOCUS := 1060.0
const FOOT_DIM := 1050.0
const BOTTOM := 1024.0
const DEVIL_AREA := [Rect2(900, -40, 800, 680), Rect2(0, -200, 740, 620), Rect2(300, -40, 800, 680)]
const BLOCK := {"width": 360, "title": 60, "title_min": 60, "line": 24, "traits": 20, "skill": 22, "skill_icon": 48, "level": 22,
	"button": 30, "button_h": 68, "action": 20, "gaps": [10, 12, 14, 16, 18, 22], "button_first": true, "summary": false, "actions": "row"}

var stage: Control
var doors: Array = []
var devils: Array = []
var seams: Array = []
var shades: Array = []
var tags: Array = []
var burst: Control
var flash: ColorRect
var dim: ColorRect
var iris: Control
var logo: Label
var logo_font: FontVariation
var top_shade: Control
var hint: Label
var saved: Label
var _dx: Array = [0.0, 0.0, 0.0]
var _dw: Array = [640.0, 640.0, 640.0]
var _portrait_started := false
var _last_rect: Array = [Rect2(), Rect2(), Rect2()]
var _pm: Array = [-1.0, -1.0, -1.0]
var _pfx: Array = [false, false, false]

static func make(c: Dictionary) -> Control:
	var s = load("res://chapter1/tests/proposals/title/a.gd").new()
	s.setup(c)
	return s

func _base_intro_len() -> float:
	return 2.5

func _base_confirm_len() -> float:
	return 1.2

# ---------------------------------------------------------------- build

func _build() -> void:
	Parts.rect_node(self, Rect2(Vector2.ZERO, size), Color(0.01, 0.012, 0.016, 1.0))
	stage = Control.new()
	stage.size = size
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	for i in 3:
		var door := Control.new()
		door.clip_contents = true
		door.mouse_filter = Control.MOUSE_FILTER_IGNORE
		door.name = "Door%d" % i
		stage.add_child(door)
		var content := Control.new()
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		door.add_child(content)
		var tex := Parts.far_texture(i, 72, 0.6)
		var far := TextureRect.new()
		far.texture = tex
		far.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		far.stretch_mode = TextureRect.STRETCH_SCALE
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
		edge.modulate = Color(0.45, 0.45, 0.45, 1.0)
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		edge.material = Parts.edge_cover_material(0.0, 100.0, 10.0, 100.0)
		content.add_child(edge)
		var glow := TextureRect.new()
		glow.texture = Kit.glow()
		glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glow.stretch_mode = TextureRect.STRETCH_SCALE
		glow.material = Parts.additive()
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(glow)
		var gray := ColorRect.new()
		gray.color = Color(0.2, 0.21, 0.23, 0.0)
		gray.mouse_filter = Control.MOUSE_FILTER_IGNORE
		door.add_child(gray)
		doors.append({"door": door, "content": content, "far": far, "edge": edge, "glow": glow, "gray": gray})
	for k in 2:
		seams.append(Parts.hband(stage, Rect2(0, 0, Parts.px(48.0), size.y), Color(0.0, 0.0, 0.0, 0.85)))
	var devil_mode := String(contract.get("devil_mode", "face"))
	for i in 3:
		var d := Parts.Devil.new()
		var area: Rect2 = DEVIL_AREA[i]
		var def: Dictionary = cards[i].get("devil", {})
		d.build(def, String(Parts.ELEM[i]), Vector2(Parts.px(area.size.x), Parts.px(area.size.y)), devil_mode == "shade", String(ui.placeholder_art), def.get("eyes", []))
		d.position = Vector2(Parts.px(area.position.x), Parts.px(area.position.y))
		d.pivot_offset = d.size * 0.5
		d.name = "Devil%d" % i
		d.visible = false
		stage.add_child(d)
		devils.append(d)
	burst = Parts.Burst.new()
	burst.size = size
	stage.add_child(burst)
	# text side shade, one per witch (BRIEF 3.2.1: 520 px wide, SURFACE .78 -> 0)
	for i in 3:
		var side := int(TEXT_SIDE[i])
		var edge_x := 960.0 if i == 0 else (480.0 if i == 1 else 960.0)
		var x0 := edge_x - 520.0 if side > 0 else edge_x
		var c0 := Color(Palette.SURFACE.r, Palette.SURFACE.g, Palette.SURFACE.b, 0.0 if side > 0 else 0.78)
		var c1 := Color(Palette.SURFACE.r, Palette.SURFACE.g, Palette.SURFACE.b, 0.78 if side > 0 else 0.0)
		var sh := Parts.hgrad(self, Rect2(Parts.px(x0), 0, Parts.px(520.0), size.y), c0, c1)
		sh.modulate.a = 0.0
		shades.append(sh)
	for i in 3:
		var b: Dictionary = Parts.build_block(i, cards[i], ui, profile, BLOCK)
		add_child(b.root)
		blocks.append(b)
		tags.append(_make_tag(i))
	_wire_blocks()
	top_shade = Parts.vgrad(self, Rect2(0, 0, Parts.px(700.0), Parts.px(150.0)), Color(0, 0, 0, 0.6), Color(0, 0, 0, 0.0))
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
	saved = Kit.lbl(self, _saved_text(), Vector2(Parts.px(40.0), Parts.px(84.0)), Parts.px(600.0), Parts.fs(17.0), Palette.INK_FAINT, "body", HORIZONTAL_ALIGNMENT_LEFT, false)
	var quit_item: Control = Parts.ActionItem.new()
	quit_item.setup(String(ui.quit), Parts.fs(20.0), Palette.INK_DIM, 0, Palette.GROWTH)
	quit_item.position = Vector2(Parts.px(1896.0) - quit_item.size.x, Parts.px(26.0))
	quit_item.connect("pressed", func(): request.emit("quit_request", focus_index))
	add_child(quit_item)
	corner_quit = quit_item
	var set_item: Control = Parts.ActionItem.new()
	set_item.setup(String(ui.settings), Parts.fs(20.0), Palette.INK_DIM, 0, Palette.GROWTH)
	set_item.position = Vector2(quit_item.position.x - Parts.px(28.0) - set_item.size.x, Parts.px(26.0))
	set_item.connect("pressed", func(): request.emit("open_settings", focus_index))
	add_child(set_item)
	corner_settings = set_item
	var hint_w := Parts.px(560.0)
	hint = Kit.lbl(self, String(ui.keys), Vector2(set_item.position.x - Parts.px(32.0) - hint_w, Parts.px(30.0)), hint_w, Parts.fs(17.0), Palette.INK_FAINT, "body", HORIZONTAL_ALIGNMENT_RIGHT, false)
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
	iris = Parts.Iris.new()
	iris.size = size
	add_child(iris)
	_update()

func _saved_text() -> String:
	var parts: Array = []
	if bool(profile.get("enabled", true)):
		parts.append(String(ui.saved))
	else:
		parts.append(String(ui.save_off))
	parts.append(String(contract.get("build", "")))
	if bool(contract.get("qa_run", false)):
		parts.append(String(ui.qa))
	return " · ".join(PackedStringArray(parts))

## The small name tag under a door that is not in focus: title and level (+ points), centred on x = 0 of its own container.
func _make_tag(i: int) -> Control:
	var w: Dictionary = cards[i]
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var width := Parts.px(440.0)
	var t: Label = Kit.lbl(root, String(w.title), Vector2(-width * 0.5, 0), width, Parts.fs(26.0), Palette.INK_DIM, "heading", HORIZONTAL_ALIGNMENT_CENTER, false, true)
	var y := t.size.y + Parts.px(4.0)
	var growth: Variant = w.get("growth", null)
	if growth is Dictionary and bool(profile.get("enabled", true)):
		var lpx := Parts.fs(20.0)
		var txt := "%s %d" % [String(ui.level), int(growth.level)]
		var lw: float = Kit.Loc.font("number").get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, lpx).x
		var total := ceilf(lw) + 2.0
		var pts := int(growth.points_free)
		var tag: Control = null
		if pts > 0:
			tag = Parts.PointsTag.new()
			tag.setup(pts, Palette.GROWTH, lpx)
			total += Parts.px(10.0) + tag.size.x
		var x := -total * 0.5
		var lb: Label = Kit.lbl(root, txt, Vector2(x, y), ceilf(lw) + 2.0, lpx, Palette.INK_DIM, "number", HORIZONTAL_ALIGNMENT_LEFT, false)
		if tag != null:
			tag.position = Vector2(x + lb.size.x + Parts.px(10.0), y)
			root.add_child(tag)
	root.position = Vector2(0, Parts.px(984.0))  ## BRIEF says 1000 / 1036; the level row then ends 3 code px below the screen, so the pair sits 16 px higher
	add_child(root)
	return root

# ---------------------------------------------------------------- time

func _e() -> float:
	match state:
		"idle": return 0.0
		"intro": return clock - intro_t0
	return 1000.0

func _ce() -> float:
	return clock - confirm_t0 if state == "confirm" or state == "done" else -1.0

func _on_skip_intro(_shift: float) -> void:
	pass

func _on_focus(old: int, new_: int) -> void:
	if new_ >= 0:
		events.append({"t": snappedf(clock - intro_t0, 0.001), "e": "witch_focus(%s)" % String(Parts.ELEM[new_])})
	_pm = [-1.0, -1.0, -1.0]

func _on_confirm(i: int) -> void:
	events.append({"t": snappedf(clock - intro_t0, 0.001), "e": "witch_confirm(%s)" % String(Parts.ELEM[i])})

# ---------------------------------------------------------------- geometry

## Settled geometry (px) when witch j has the focus, used for the placement checks and by the drawing at f = 1.
func settled_geometry(j: int) -> Array:
	var out: Array = []
	var x := 0.0
	for i in 3:
		var w := door_span(1.0 if i == j else 0.0)
		out.append(_geom(i, 1.0 if i == j else 0.0, x, w))
		x += w
	return out

static func door_span(f: float) -> float:
	return 480.0 + 480.0 * f

func _geom(i: int, f: float, door_x: float, door_w: float) -> Dictionary:
	var s := lerpf(S_DIM, S_FOCUS, f)
	var foot := lerpf(FOOT_DIM, FOOT_FOCUS, f)
	var axis := door_x + lerpf(0.5, float(AXIS[i]), f) * door_w
	var face: Vector2 = Parts.FACE[i]
	return {"door_x": door_x, "door_w": door_w, "axis_x": axis, "foot": foot, "scale": s,
		"face": Vector2(axis + (face.x - 512.0) * s, foot - (Parts.FOOT_Y - face.y) * s),
		"pelvis_x": axis + (Parts.PELVIS[i].x - 512.0) * s, "cut_frac": 2.0}

func _hover_at(pos: Vector2) -> int:
	var x := pos.x / Parts.K
	for i in 3:
		if x >= float(_dx[i]) and x < float(_dx[i]) + float(_dw[i]):
			return i
	return -1

func _click_at(pos: Vector2) -> void:
	var i := _hover_at(pos)
	if i >= 0 and i != focus_index:
		set_focus(i)

# ---------------------------------------------------------------- the picture

func _update() -> void:
	if doors.is_empty():
		return
	var e := _e()
	var ce := _ce()
	var in_confirm := ce >= 0.0
	var motion_on := not reduce_motion
	var o := 1.0
	if state == "idle" or state == "intro":
		o = Parts.smooth(Parts.ramp(e, 1.3, 1.6))
	# the chosen portrait's own entrance (darkness lifts from the bottom, 1.1 s) starts when the door has begun to open
	if state != "idle" and not _portrait_started and focus_index >= 0 and (e >= 1.3 or intro_skipped or reduce_motion):
		_portrait_started = true
		if not intro_skipped and not reduce_motion:
			(portraits[focus_index] as Node2D).call("advance_to", clock + shift_bonus)
			(portraits[focus_index] as Node2D).call("play_intro")
			mark_once("portrait_intro")
	if state == "idle":
		_portrait_started = false
	# base widths (px)
	var base_w: Array = []
	var base_x: Array = []
	var fv: Array = []
	var x := 0.0
	for i in 3:
		var f := focus_amount(i) * o
		fv.append(f)
		var w := lerpf(640.0, door_span(focus_amount(i)), o)
		base_w.append(w)
		base_x.append(x)
		x += w
	# confirm: the chosen door opens to the whole screen, the others close (the figure keeps its screen place)
	var c := 0.0
	if in_confirm and motion_on:
		c = Parts.smooth(Parts.ramp(ce, 0.05, 0.45))
	var dx := 0.0
	var focus_geo := {}
	for i in 3:
		var w2: float = float(base_w[i]) * (1.0 - c) if i != focus_index else lerpf(float(base_w[i]), 1920.0, c)
		_dx[i] = dx
		_dw[i] = w2
		dx += w2
	for i in 3:
		var g := _geom(i, float(fv[i]), float(base_x[i]), float(base_w[i]))
		if i == focus_index:
			focus_geo = g
		var d: Dictionary = doors[i]
		var door: Control = d.door
		door.position = Vector2(Parts.px(float(_dx[i])), 0)
		door.size = Vector2(Parts.px(float(_dw[i])), size.y)
		door.visible = float(_dw[i]) > 0.5
		var local_x := (float(g.axis_x) - float(_dx[i]))
		var s_code := float(g.scale) * Parts.K
		var rect := Parts.portrait_rect(s_code, Vector2(512, Parts.FOOT_Y), Vector2(Parts.px(local_x), Parts.px(float(g.foot))))
		if rect != _last_rect[i]:
			_last_rect[i] = rect
			(portraits[i] as Node2D).call("set_rect", rect, 1.0, Vector2(512, Parts.FOOT_Y))
		var cover := Parts.cover_rect(Parts.CANVAS, door.size)
		var far: TextureRect = d.far
		var edge: TextureRect = d.edge
		far.position = cover.position
		far.size = cover.size
		edge.position = cover.position
		edge.size = cover.size
		var half := 512.0 * float(g.scale) * Parts.K
		Parts.set_edge(edge.material, Parts.px(local_x) - half - cover.position.x, Parts.px(local_x) + half - cover.position.x, Parts.px(120.0), cover.size.x)
		var br := lerpf(0.30, 1.0, float(fv[i]))
		(d.content as Control).modulate = Color(br, br, br, 1.0)
		(d.gray as ColorRect).size = door.size
		(d.gray as ColorRect).color = Color(0.2, 0.21, 0.23, 0.55 * (1.0 - float(fv[i])))
		var glow_a := 0.0
		var fe := clock - focus_t0
		if i == focus_index:
			glow_a = Parts.ramp(fe, 0.12, 0.40) * o
		elif i == prev_focus:
			glow_a = 1.0 - Parts.ramp(fe, 0.0, 0.2)
		var glow: TextureRect = d.glow
		var gcol := Parts.el_color(i)
		glow.modulate = Color(gcol.r, gcol.g, gcol.b, 0.6 * glow_a)
		glow.size = Vector2(Parts.px(900.0), Parts.px(300.0))
		glow.position = Vector2(Parts.px(local_x) - glow.size.x * 0.5, Parts.px(float(g.foot)) - glow.size.y * 0.5)
		# door appearance (intro) and the black of the doors that were not chosen (confirm)
		var appear := Parts.ramp(e, 1.0 + 0.08 * float(i), 1.2 + 0.08 * float(i))
		var k := 1.0
		if in_confirm and i != focus_index and motion_on:
			k = 1.0 - Parts.ramp(ce, 0.0, 0.12)
		door.modulate = Color(k, k, k, appear)
		# portrait motion and element effects: only the figure in focus moves
		var want := 0.0
		if i == focus_index and state != "idle":
			want = motion if motion_on else 0.0
			if in_confirm and motion_on:
				want = motion * (1.0 + 0.4 * Parts.ramp(ce, 0.25, 0.4))
		if absf(float(_pm[i]) - want) > 0.001:
			_pm[i] = want
			(portraits[i] as Node2D).call("set_motion_scale", want)
		var fx_on := (i == focus_index and fe >= FOCUS_ANIM) or (i == prev_focus and fe < 0.2)
		if state == "intro" and i == focus_index:
			fx_on = e >= 1.3
		if fx_on != bool(_pfx[i]):
			_pfx[i] = fx_on
			(portraits[i] as Node2D).call("set_flags", {"fx": fx_on, "glow": fx_on})
	# seams between doors
	for k in 2:
		var sx: float = Parts.px(float(_dx[k]) + float(_dw[k]))
		var seam: Control = seams[k]
		seam.position.x = sx - seam.size.x * 0.5
		seam.modulate.a = 1.0 - c
	# chrome (text, corners) alpha
	var chrome := 1.0
	if state == "idle" or state == "intro":
		chrome = Parts.ramp(e, 2.2, 2.5)
	if in_confirm:
		chrome = 1.0 - Parts.ramp(ce, 0.0, 0.15)
	for i in 3:
		var b: Dictionary = blocks[i]
		var a := block_alpha(i) * chrome if state != "idle" else 0.0
		var root: Control = b.root
		root.visible = a > 0.01
		root.modulate.a = a
		root.position = Vector2(Parts.px(float(TEXT_X[i])), Parts.px(BOTTOM) - float(b.height) + Parts.px(12.0) * (1.0 - a))
		(shades[i] as Control).modulate.a = a
		var tg: Control = tags[i]
		var ta := (1.0 - float(fv[i])) * Parts.ramp(e, 1.5, 1.8)
		if in_confirm:
			ta *= 1.0 - Parts.ramp(ce, 0.0, 0.15)
		tg.visible = ta > 0.01
		tg.modulate.a = ta
		tg.position.x = Parts.px(float(_dx[i]) + float(_dw[i]) * 0.5)
	if focus_index >= 0:
		var sb: Control = blocks[focus_index].start
		sb.set("flash", (1.0 - Parts.ramp(ce, 0.0, 0.06)) if in_confirm else 0.0)
	_logo(e, ce)
	for c2 in [hint, saved, corner_settings, corner_quit, top_shade]:
		(c2 as Control).modulate.a = chrome
	# effects of the confirm
	flash.color = Color(0, 0, 0, 0)
	burst.set("t", -1.0)
	for i in 3:
		(devils[i] as Control).set("amount", 0.0)
	stage.scale = Vector2.ONE
	stage.position = Vector2.ZERO
	dim.color = Color(0, 0, 0, 0)
	iris.set("amount", 0.0)
	if in_confirm and focus_index >= 0:
		var g2: Dictionary = focus_geo
		if motion_on:
			var z := 1.0 + 0.08 * Parts.smooth(Parts.ramp(ce, 0.10, 0.50))
			stage.pivot_offset = Vector2(Parts.px(float(g2.axis_x)), Parts.px(float(g2.face.y) + 140.0))
			stage.scale = Vector2(z, z)
			if bool(settings.get("shake", false)) and ce >= 0.30 and ce < 0.50:
				stage.position = Vector2(sin(ce * 130.0) * 5.0, cos(ce * 110.0) * 5.0)
			var sym: Vector2 = Parts.SYMBOL[focus_index]
			burst.set("element", String(Parts.ELEM[focus_index]))
			burst.set("center", Vector2(Parts.px(float(g2.axis_x) + (sym.x - 512.0) * float(g2.scale)), Parts.px(float(g2.foot) - (Parts.FOOT_Y - sym.y) * float(g2.scale))))
			burst.set("t", ce - 0.30 if ce >= 0.30 else -1.0)
			if ce >= 0.30:
				mark_once("burst_start")
				var fa := 0.0
				if ce < 0.36:
					fa = 0.45 * Parts.ramp(ce, 0.30, 0.36)
				else:
					fa = 0.45 * (1.0 - Parts.ramp(ce, 0.36, 0.60))
				var fc := Parts.el_color(focus_index)
				flash.color = Color(fc.r * fa, fc.g * fa, fc.b * fa, 1.0)
			var dv := String(contract.get("devil_mode", "face"))
			if dv != "none":
				var dev: Control = devils[focus_index]
				var amt := 0.55 * Parts.ramp(ce, 0.30, 0.40) * (1.0 - Parts.ramp(ce, 0.60, 0.80))
				dev.set("amount", amt)
				var dsc := 1.0 + 0.04 * Parts.ramp(ce, 0.40, 0.70)
				dev.scale = Vector2(dsc, dsc)
				dev.set("hand_drop", Parts.px(120.0) * Parts.ramp(ce, 0.40, 0.70))
				if amt > 0.01:
					mark_once("devil_shown")
			iris.set("amount", Parts.ramp(ce, 0.60, 1.20))
		else:
			dim.color = Color(0, 0, 0, Parts.ramp(ce, 0.0, 0.4))

func _logo(e: float, ce: float) -> void:
	var k := 1.0
	var a := 1.0
	if state == "idle" or state == "intro":
		k = Parts.smooth(Parts.ramp(e, 1.8, 2.3))
		a = Parts.ramp(e, 0.4, 1.0)
	if ce >= 0.0:
		a = 1.0 - Parts.ramp(ce, 0.0, 0.15)
	var px_big := 96.0
	var px_small := 34.0
	var fpx := lerpf(px_big, px_small, k)
	var code_px := Parts.fs(fpx)
	logo_font.spacing_glyph = int(round(fpx * 0.10 * Parts.K))
	logo.add_theme_font_size_override("font_size", code_px)
	var wpx: float = Kit.Loc.font("heading").get_string_size(String(ui.logo), HORIZONTAL_ALIGNMENT_LEFT, -1, code_px).x + float(String(ui.logo).length()) * float(logo_font.spacing_glyph)
	var h := Kit.line_height(code_px, "heading")
	var big_pos := Vector2(size.x * 0.5 - wpx * 0.5, Parts.px(470.0) - h * 0.5)
	var small_pos := Vector2(Parts.px(40.0), Parts.px(24.0))
	logo.position = big_pos.lerp(small_pos, k)
	logo.size = Vector2(wpx + 8.0, h + 4.0)
	logo.modulate.a = a
