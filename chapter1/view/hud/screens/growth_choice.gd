extends Control
## The grace screen (growth choice), proposal E "the demon's hand" as the product (A8 G6). One public entry, apply(contract), and four signals (T8 3).
## The demon who gives the grace stands in the middle of the screen, taller than it; the three cards float in a fan in front of her; the owned band lies along the
## bottom, the three knobs (reroll / exclude / keep) stand at the right, the side note (parchment) at the left, the title plaque and two candles at the top.
## It reads only the contract (chapter1/view/contracts/growth_choice_contract.gd makes it from the core) and says what was chosen through the signals; the host
## (chapter_hud.gd) hands them to the core. Every piece of motion is a pure function of a time, so a key press during the intro lands on the same end screen.
## The figures are TEMPORARY pictures (the demon is not chosen yet); the slots `ui.grace.demon.*` hold them.
const CONTRACT_VERSION := 1
const Grace = preload("res://chapter1/view/hud/grace_parts.gd")
const Kit = preload("res://chapter1/view/hud/grace_draw.gd")
const Parts = preload("res://chapter1/view/hud/ui_parts.gd")
const Motion = preload("res://chapter1/view/hud/ui_motion.gd")
const Palette = preload("res://chapter1/view/hud/palette.gd")
const Loc = preload("res://chapter1/view/loc.gd")

signal chosen(card_ref: String)
signal reroll
signal exclude(card_ref: String)
signal keep(card_ref: String)
signal ready_for_pick   ## the cards settled (the host ignores it; the capture tool waits for it)

const LOCK := Motion.PICK_LOCK        ## a pick is refused for this long after the cards settle (Input48; Space is never a confirm key)
const DEMON_BOB := 22.0   ## body bob, peak to peak, in 1600 x 900 code px
const DEMON_PERIOD := 2.7
const TRAIL_LAG := 0.2
const FLIP_NORMAL := Vector3(0.0, 0.15, 0.15)   ## first flip start, step between cards, flip length (three cards inside 0.45 s)
const FLIP_LONG := Vector3(1.1, 0.2, 0.25)
const J_SLOW_END := 0.95
const J_REVEAL := 1.07
## The right eye of each temporary figure as a fraction of its picture (read with a pixel grid; an estimate until the final figure).
const EYE := {"ember": Vector2(0.510, 0.104), "frost": Vector2(0.505, 0.106), "arc": Vector2(0.507, 0.062)}
const BODY_SH := "shader_type canvas_item;\nuniform float fx = 0.2;\nuniform float fb = 0.05;\nuniform float ft = 0.05;\nuniform vec3 tint = vec3(1.0);\nuniform float amt = 1.0;\nvoid fragment(){ vec4 c = texture(TEXTURE, UV); float ax = smoothstep(0.0, fx, UV.x) * smoothstep(0.0, fx, 1.0 - UV.x); float ab = smoothstep(0.0, max(fb, 0.001), 1.0 - UV.y); float at = ft > 0.0 ? smoothstep(0.0, ft, UV.y) : 1.0; COLOR = vec4(c.rgb * tint, c.a * ax * ab * at * amt); }\n"
const AURA_SH := "shader_type canvas_item;\nrender_mode blend_add;\nuniform float fx = 0.2;\nuniform float fb = 0.05;\nuniform float ft = 0.05;\nuniform vec3 tint = vec3(1.0);\nuniform float amt = 0.2;\nvoid fragment(){ vec4 c = texture(TEXTURE, UV); float ax = smoothstep(0.0, fx, UV.x) * smoothstep(0.0, fx, 1.0 - UV.x); float ab = smoothstep(0.0, max(fb, 0.001), 1.0 - UV.y); float at = ft > 0.0 ? smoothstep(0.0, ft, UV.y) : 1.0; COLOR = vec4(c.rgb * tint * amt, c.a * ax * ab * at); }\n"

var contract := {}
var ui := {}
var cards: Array = []
var focus_index := -1
var state := "idle"        ## idle, intro, ready, done
var clock := 0.0
var unlock_abs := 0.0
var unlock_t := 0.0
var intro_start := 0.0
var events: Array = []
var reduce_motion := false
var capture_mode := false   ## a still capture: the idle motion stays off
var confirm_len := Motion.SCENE_OUT
var el := "frost"
var jackpot_index := -1
var card_nodes: Array = []
var cards_root: Control
var ui_root: Control
var stage: Control
var note_node
var band_node
var knob_nodes: Array = []
var plaque_node
var candle_nodes: Array = []
var demon_rect := Rect2()
var demon: Control
var demon_trail: Control
var demon_rim: Control
var hand_glow: Control
var shaft_nodes: Array = []
var motes: Control
var blackout: ColorRect
var jackpot_parts := {}
var _tweens: Array = []
var _flame: Color
var _motes_t := 0.0
var _pose_t := 0.0
var _shaft_gain := 1.0
var _card_base: Array = []
var _kind := "normal"
var _intro_len := 0.45
var _dim := 0.0
var _dim_now := -1.0
var _body_mat: ShaderMaterial
var _aura_mat: ShaderMaterial
var _speech_node: Control
var _sigil_bg: Control
var _eye_base := Vector2.ZERO
var _fly: Control
var _trail_layer: Control
var _sock_layer: Control
var _burst: Control
var _burst_gold: Control
var _fly_from := Vector2.ZERO
var _fly_to := Vector2.ZERO
var _fly_s0 := 1.0
var _fly_s1 := 0.7
var _fly_t := 0.0
var _sock_a := 0.0

# ============================================================ the one entry
func apply(c: Dictionary) -> void:
	if int(c.get("contract_version", -1)) != CONTRACT_VERSION:
		push_error("growth_choice: contract_version %s, the screen takes %d" % [str(c.get("contract_version")), CONTRACT_VERSION])
		return
	contract = c.duplicate(true)
	cards = contract.get("cards", [])
	ui = {"title": Loc.t("grace.screen.title"), "title_last": Loc.t("grace.screen.title_last"), "owned": Loc.t("grace.screen.owned"), "graces": Loc.t("grace.screen.graces"),
		"combo": Loc.t("grace.screen.combo"), "reroll": Loc.t("grace.screen.reroll"), "exclude": Loc.t("grace.screen.exclude"), "keep": Loc.t("grace.screen.keep"),
		"key_reroll": "R", "key_exclude": "X", "fated_banner": Loc.t("grace.screen.banner")}
	contract["strings"] = ui   ## the parts read their fixed words from here
	size = Kit.SIZE
	position = Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()

func _build() -> void:
	el = String(contract.get("witch", {}).get("element", "frost"))
	_flame = Kit.el_color(el).lerp(Palette.FLAME_WARM, 0.55)
	for i in cards.size():
		if Grace.grade_key(String(cards[i].get("grade", "common"))) == "jackpot": jackpot_index = i
	stage = Control.new()
	stage.size = Kit.SIZE
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	_ground()
	_layout()
	_post_layout()
	_apply_tones()
	if jackpot_index >= 0: jackpot_state(1.0)
	set_process(true)

## The fan: the demon behind, the three cards in front of her where an open hand would be, then the rest of the furniture.
func _layout() -> void:
	_shafts(Vector2(420, 0))
	_demon(Rect2(366, 40, 868, 1300))
	_motes(Rect2(300, 60, 700, 700))
	hand_glow = Parts.glow_rect(stage, Vector2.ZERO, 1.0, Kit.with_alpha(Kit.el_color(el), 0.34))
	hand_glow.size = Vector2(900, 340)
	hand_glow.position = Vector2(800, 670) - hand_glow.size * 0.5
	var centres := [Vector2(538, 622), Vector2(800, 592), Vector2(1062, 622)]
	var sizes := [Vector2(250, 390), Vector2(270, 420), Vector2(250, 390)]
	var tilts := [-0.14, 0.0, 0.14]
	var rects: Array = []
	for i in mini(cards.size(), 3): rects.append(Rect2(centres[i] - sizes[i] * 0.5, sizes[i]))
	_cards_into(rects, tilts)
	if jackpot_index >= 0 and jackpot_index < card_nodes.size(): card_nodes[jackpot_index].z_index = 3
	_title_block(800.0, 8.0, 360.0, 740.0, 170.0, 40.0)
	_note(Rect2(24, 170, 330, 440))
	_speech(Vector2(30, 630), 320.0)
	_knobs(Vector2(1232, 300), 0.0)
	_band(Vector2(365, 832), 870.0)
	if jackpot_index >= 0 and jackpot_index < rects.size():
		var r: Rect2 = rects[jackpot_index]
		_jackpot_fx(r, r, Vector2(r.get_center().x, r.position.y - 34.0), float(tilts[jackpot_index]))

func _post_layout() -> void:
	# everything but the stage rides on ui_root (the long intro brings it in after the stage); a blackout lies over all
	var kids: Array = []
	for k in get_children():
		if k != stage: kids.append(k)
	ui_root = Control.new()
	ui_root.size = Kit.SIZE
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui_root)
	for k in kids:
		remove_child(k)
		ui_root.add_child(k)
	blackout = ColorRect.new()
	blackout.color = Kit.with_alpha(Color.BLACK, 0.0)
	blackout.size = Kit.SIZE
	blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blackout.z_index = 20
	add_child(blackout)
	for cd in card_nodes: _card_base.append(cd.position)
	_speech_node = ui_root.find_child("DemonLine", true, false)
	if demon != null:
		var sh := Shader.new()
		sh.code = BODY_SH
		_body_mat = ShaderMaterial.new()
		_body_mat.shader = sh
		demon.material = _body_mat
		var sa := Shader.new()
		sa.code = AURA_SH
		_aura_mat = ShaderMaterial.new()
		_aura_mat.shader = sa
		var ec := Kit.el_color(el)
		_aura_mat.set_shader_parameter("tint", Vector3(ec.r, ec.g, ec.b))
		_aura_mat.set_shader_parameter("amt", 0.30)
		demon_trail.material = _aura_mat
		demon_trail.modulate = Color.WHITE
	if jackpot_index >= 0 and Parts.tex("sigil") != null:
		var r: Rect2 = jackpot_parts.rect
		var d := r.size.x * 1.15
		_sigil_bg = Parts.art_rect(cards_root, "sigil", Rect2(r.get_center() - Vector2(d, d) * 0.5, Vector2(d, d)), {"add": true, "tint": Kit.with_alpha(Color.WHITE, 0.6)})
		cards_root.move_child(_sigil_bg, card_nodes[jackpot_index].get_index())
		_sigil_bg.modulate.a = 0.0
		_sigil_bg.rotation = card_nodes[jackpot_index].rotation
	if jackpot_parts.has("eye"):
		var eye: Control = jackpot_parts.eye
		eye.size = Vector2(46, 46)
		_eye_base = demon_rect.position + demon_rect.size * EYE.get(el, Vector2(0.5, 0.11)) - eye.size * 0.5
		eye.position = _eye_base
	_intro_t(INF)   ## the settled screen until play_intro begins

func _process(delta: float) -> void:
	clock += delta
	if capture_mode and not _live(): return
	_pose_t += delta
	_motes_t += delta
	_flicker(_pose_t)
	if reduce_motion: return   ## reduced motion: brightness only, no position change
	demon_pose(_pose_t)
	motes_time(_motes_t)

func _live() -> bool:
	return state == "intro" or state == "done"

## Irregular light-shaft strength (about 1.2 s beats, a different depth every time).
func _flicker(t: float) -> void:
	for i in shaft_nodes.size():
		var f := float(i) * 1.9
		var v := 0.62 + 0.28 * sin(t * TAU / 1.2 + f) * (0.6 + 0.4 * sin(t * 0.83 + f)) + 0.10 * sin(t * 3.7 + f * 1.3)
		shafts_level(i, clampf(v, 0.25, 1.0))

# ============================================================ stage parts
func _ground() -> void:
	var tex: Texture2D = Parts.tex("demon_" + el)
	var base: Color = Palette.PLATE
	if tex != null: base = tex.get_image().get_pixel(10, 10)   ## the figure's own ground colour: the picture melts into the stage
	var g := ColorRect.new()
	g.color = Kit.with_alpha(base, 0.82)   ## the combat scene shows through, dark
	g.size = Kit.SIZE
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(g)
	Parts.glow_rect(stage, Vector2(300, 260), 560.0, Kit.with_alpha(Kit.el_color(el), 0.16))
	var vig := Parts.ArtLayer.new()
	vig.texture = Kit.vignette_texture()
	vig.size = Kit.SIZE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.modulate = Kit.with_alpha(Color.WHITE, Palette.SCRIM_SCENE_VIGNETTE)
	stage.add_child(vig)

func _shafts(origin: Vector2, count := 2) -> void:
	for i in count:
		var g := Parts.glow_rect(stage, origin + Vector2(float(i) * 130.0, 400.0), 1.0, Kit.with_alpha(Kit.el_color(el), 0.10))
		g.size = Vector2(300.0 + 80.0 * i, 1500.0)
		g.position = origin + Vector2(float(i) * 150.0 - g.size.x * 0.5, 380.0 - g.size.y * 0.5)
		g.pivot_offset = g.size * 0.5
		g.rotation = -0.38 + 0.06 * i
		shaft_nodes.append(g)

func _demon(rect: Rect2) -> void:
	demon_rect = rect
	var tex: Texture2D = Parts.tex("demon_" + el)
	if tex == null: return
	demon_trail = Parts.ArtLayer.new()
	demon_trail.texture = tex
	demon_trail.position = rect.position
	demon_trail.size = rect.size
	demon_trail.modulate = Kit.with_alpha(Color.WHITE, 0.0)
	demon_trail.material = Kit.feather_material(0.2, 0.05, 0.05)
	demon_trail.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	demon_trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(demon_trail)
	demon = Parts.ArtLayer.new()
	demon.texture = tex
	demon.position = rect.position
	demon.size = rect.size
	demon.material = Kit.feather_material(0.2, 0.05, 0.05)
	demon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	demon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(demon)
	demon_rim = Parts.glow_rect(stage, rect.position + rect.size * Vector2(0.62, 0.42), rect.size.x * 0.55, Kit.with_alpha(Kit.el_color(el), 0.10))

## Small things of the element around the figure (embers / ice shards / current dots), one layer, placed once and drifted by motes_time(t).
func _motes(zone: Rect2, count := 26) -> void:
	motes = Parts.layer(stage, Callable(self, "_paint_motes"), Rect2(Vector2.ZERO, Kit.SIZE))
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	motes.material = m
	var rng := RandomNumberGenerator.new()
	rng.seed = 5 + el.hash() % 97
	var pts: Array = []
	for i in count:
		pts.append({"p": zone.position + Vector2(rng.randf() * zone.size.x, rng.randf() * zone.size.y), "s": rng.randf_range(2.0, 5.5), "ph": rng.randf() * TAU,
			"per": rng.randf_range(3.1, 4.3), "a": rng.randf_range(0.35, 0.9)})
	motes.set_meta("pts", pts)

func _paint_motes(c: Control) -> void:
	var col := Kit.el_color(el)
	for m in c.get_meta("pts", []):
		var ph: float = float(m.ph) + _motes_t * TAU / float(m.per)
		var p: Vector2 = m.p + Vector2(sin(ph) * 7.0, -fposmod(_motes_t * 9.0 + float(m.ph) * 20.0, 60.0))
		var s: float = m.s
		var a: float = float(m.a) * (0.65 + 0.35 * sin(ph * 1.3))
		match el:
			"frost":
				c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s * 1.8), p + Vector2(s, 0), p + Vector2(0, s * 1.8), p + Vector2(-s, 0)]), Kit.with_alpha(col, a))
			"arc":
				c.draw_line(p, p + Vector2(s * 1.6, -s * 1.2), Kit.with_alpha(col, a), 1.6)
				c.draw_circle(p, s * 0.6, Kit.with_alpha(Color.WHITE.lerp(col, 0.4), a))
			_:
				c.draw_circle(p, s * 0.8, Kit.with_alpha(col, a))
				c.draw_circle(p, s * 1.8, Kit.with_alpha(col, a * 0.25))

func _title_block(center_x: float, y: float, width: float, candle_dx: float, candle_h: float, candle_y: float) -> void:
	var last := String(contract.get("moment", {}).get("kind", "")) == "last"
	plaque_node = Parts.title(self, String(ui.title_last if last else ui.title), width, String(contract.get("moment", {}).get("label", "")))
	plaque_node.position = Vector2(center_x - plaque_node.size.x * 0.5, y)
	for sgn in [-1.0, 1.0]:
		var c = Parts.candle(self, Vector2(center_x + sgn * candle_dx - candle_h * 0.25, candle_y), candle_h, _flame)
		c.animated = not reduce_motion
		candle_nodes.append(c)

func _band(pos: Vector2, width: float) -> void:
	band_node = Grace.band(self, pos, width, contract)

func _knobs(pos: Vector2, gap: float) -> void:
	knob_nodes = Parts.handles(self, contract, pos, gap)
	for k in knob_nodes:
		k.pressed.connect(_knob_pressed)

func _knob_pressed(id: String) -> void:
	if state != "ready" or clock < unlock_abs: return
	var at := maxi(focus_index, 0)
	match id:
		"reroll": reroll.emit()
		"exclude": exclude.emit(String(cards[at].id))
		"keep": keep.emit(String(cards[at].id))

func _note(rect: Rect2) -> void:
	note_node = Parts.note(self, rect, contract)

## The demon's line (none when she does not speak).
func _speech(pos: Vector2, width: float) -> void:
	var giver: Dictionary = contract.get("giver", {})
	var line: Variant = giver.get("line", null)
	if bool(giver.get("mute", false)) or line == null or str(line) == "": return
	var l: Label = Kit.lbl(self, str(line), pos, width, 19, Palette.INK, "body", HORIZONTAL_ALIGNMENT_LEFT, true, true)
	l.name = "DemonLine"

func _cards_into(rects: Array, tilts: Array) -> void:
	cards_root = Control.new()
	cards_root.size = Kit.SIZE
	cards_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cards_root)
	for i in rects.size():
		var r: Rect2 = rects[i]
		var cd = Grace.card(cards_root, cards[i], i, r.size, ui)
		cd.position = r.position
		cd.rotation = float(tilts[i])
		cd.animated = not reduce_motion
		cd.name = "GraceCard%d" % i
		cd.clicked.connect(func(k): set_focus(k); try_pick(k))
		cd.hovered.connect(func(k): set_focus(k))
		card_nodes.append(cd)

# ============================================================ jackpot parts (spec 5.7, the held screen)
func _jackpot_fx(r: Rect2, heat_rect: Rect2, stamp_pos: Vector2, tilt := 0.0) -> void:
	if jackpot_index < 0: return
	var c := r.get_center()
	var halo := Parts.glow_rect(cards_root, c, r.size.x * 0.62, Kit.with_alpha(Palette.BRASS_HI, 0.0))
	cards_root.move_child(halo, card_nodes[jackpot_index].get_index())
	var heat := Parts.layer(self, Callable(self, "_paint_heat"), Rect2(Vector2.ZERO, Kit.SIZE))
	heat.set_meta("rect", heat_rect)
	heat.set_meta("tilt", tilt)
	heat.modulate.a = 0.0
	var stamp_node = Grace.jackpot(self, String(ui.fated_banner), Vector2(230, 84))
	stamp_node.position = stamp_pos - stamp_node.size * 0.5
	stamp_node.modulate.a = 0.0
	var sp := Parts.layer(self, Callable(self, "_paint_sparks"), Rect2(Vector2.ZERO, Kit.SIZE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var pts: Array = []
	var outer := Rect2(Vector2.ZERO, r.size).grow(r.size.x * 0.13)   ## light and grains stay within 115 % of the card's width
	var inner_r := Rect2(Vector2.ZERO, r.size).grow(3.0)
	while pts.size() < 56:
		var q := outer.position + Vector2(rng.randf() * outer.size.x, rng.randf() * outer.size.y)
		if inner_r.has_point(q): continue
		pts.append(c + (q - r.size * 0.5).rotated(tilt))
	sp.set_meta("pts", pts)
	sp.set_meta("center", c)
	sp.set_meta("burst", 1.0)
	sp.modulate.a = 0.0
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sp.material = m
	var eye: Control = Parts.glow_rect(self, Vector2.ZERO, 23.0, Kit.with_alpha(Kit.el_color(el), 0.0))
	jackpot_parts = {"halo": halo, "heat": heat, "stamp": stamp_node, "sparks": sp, "eye": eye, "rect": r}

func _paint_heat(c: Control) -> void:
	var r: Rect2 = c.get_meta("rect")
	c.draw_set_transform(r.get_center(), float(c.get_meta("tilt", 0.0)))
	var h := Rect2(-r.size * 0.5, r.size)
	for k in 6:
		c.draw_rect(h.grow(float(k) * 2.5), Kit.with_alpha(Palette.GRACE_JACKPOT, 0.5 * (1.0 - float(k) / 6.0)), false, 3.0)

func _paint_sparks(c: Control) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 78
	var ctr: Vector2 = c.get_meta("center", Vector2.ZERO)
	var b: float = 1.0 - pow(1.0 - float(c.get_meta("burst", 1.0)), 3.0)
	for p0 in c.get_meta("pts", []):
		var p: Vector2 = ctr.lerp(p0, b)
		var s := rng.randf_range(1.4, 3.6)
		c.draw_circle(p, s, Kit.with_alpha(Palette.GRACE_JACKPOT, 0.9))
		c.draw_circle(p, s * 2.6, Kit.with_alpha(Palette.GRACE_JACKPOT, 0.16))

# ============================================================ motion hooks (pure functions of an amount or a time)
func jackpot_state(a: float) -> void:
	heat_window(a)
	dim_others(a)
	stamp(a)
	sparks(a)
	halo(a)
	eye_glow(a * 0.8)

func heat_window(a: float) -> void:
	if jackpot_parts.has("heat"): jackpot_parts.heat.modulate.a = a

func dim_others(a: float) -> void:
	_dim = a
	_apply_tones()

func stamp(a: float) -> void:
	if jackpot_parts.has("stamp"):
		var s = jackpot_parts.stamp
		s.modulate.a = clampf(a * 1.5, 0.0, 1.0)
		s.scale = Vector2.ONE * lerpf(1.4, 1.0, clampf(a, 0.0, 1.0))

func sparks(a: float) -> void:
	if jackpot_parts.has("sparks"): jackpot_parts.sparks.modulate.a = a

## Light within 115 % of the card's width: a round light of radius 0.62 * width.
func halo(a: float) -> void:
	if jackpot_parts.has("halo"): jackpot_parts.halo.modulate = Kit.with_alpha(Palette.BRASS_HI, 0.5 * a)

func eye_glow(a: float) -> void:
	if jackpot_parts.has("eye"): jackpot_parts.eye.modulate = Kit.with_alpha(Kit.el_color(el), 0.6 * a)

func demon_pose(t: float) -> void:
	if demon == null: return
	var ph := t * TAU / DEMON_PERIOD
	demon.position.y = demon_rect.position.y + sin(ph) * DEMON_BOB * 0.5
	var late := sin((t - TRAIL_LAG) * TAU / DEMON_PERIOD) * DEMON_BOB * 0.75
	if demon_trail != null: demon_trail.position.y = demon_rect.position.y + late
	if jackpot_parts.has("eye"): jackpot_parts.eye.position.y = _eye_base.y + sin(ph) * DEMON_BOB * 0.5
	if demon_rim != null: demon_rim.position.y = demon_rect.position.y + demon_rect.size.y * 0.42 - demon_rim.size.y * 0.5 + late

func shafts_level(i: int, v: float) -> void:
	if i < shaft_nodes.size(): shaft_nodes[i].modulate = Kit.with_alpha(Kit.el_color(el), 0.16 * v * _shaft_gain)

func motes_time(t: float) -> void:
	_motes_t = t
	if motes != null: motes.queue_redraw()

func _tint_demon(sil: float, amt: float) -> void:
	if _body_mat == null: return
	var c := Kit.el_color(el)
	var dark := Vector3(c.r, c.g, c.b) * 0.30
	_body_mat.set_shader_parameter("tint", dark.lerp(Vector3.ONE, sil))
	_body_mat.set_shader_parameter("amt", amt)
	if demon_trail != null: _aura_mat.set_shader_parameter("amt", 0.30 * amt * sil)
	if demon_rim != null: demon_rim.visible = amt * sil > 0.01

# ---- the intro: ground -> shafts -> silhouette -> colour -> (long: the hand's flash); a jackpot has its own order (5.7)
func _flip_plan() -> Vector3:
	return FLIP_LONG if _kind == "long" else FLIP_NORMAL

func _intro_t(t: float) -> void:
	var final := is_inf(t) or t >= _intro_len
	var long := _kind == "long"
	var jp := _kind == "jackpot" and jackpot_index >= 0
	var bg := smoothstep(0.0, 0.25 if long else 0.1, t)
	var sh := smoothstep(0.15, 0.7, t) if long else smoothstep(0.0, 0.25, t)
	var dm := smoothstep(0.45, 0.85, t) if long else smoothstep(0.0, 0.12, t)
	var col := smoothstep(0.85, 1.25, t) if long else smoothstep(0.05, 0.3, t)
	var ui_a := smoothstep(0.95, 1.2, t) if long else smoothstep(0.0, 0.12, t)
	stage.modulate.a = 1.0 if final else bg
	_shaft_gain = 1.0 if final else sh
	_tint_demon(1.0 if final else col, 1.0 if final else dm)
	ui_root.modulate.a = 1.0 if final else ui_a
	cards_root.modulate.a = 1.0
	if hand_glow != null:
		var fl := 0.0
		if long and not final: fl = sin(PI * clampf((t - 1.2) / 0.4, 0.0, 1.0))
		hand_glow.modulate = Kit.with_alpha(Kit.el_color(el).lerp(Palette.FLAME_WARM, 0.25 * fl), 0.34 + 0.40 * fl)
	_flicker(_pose_t)
	if final:
		for i in card_nodes.size():
			card_nodes[i].position = _card_base[i]
			card_nodes[i].rim = -1.0
			card_nodes[i].leak = 0.0
			card_nodes[i].face_up = true
		blackout.color.a = 0.0
		if jackpot_index >= 0:
			var hn: Control = jackpot_parts.halo
			hn.scale = Vector2.ONE
			if _sigil_bg != null: _sigil_bg.modulate.a = 0.0
			jackpot_parts.sparks.set_meta("burst", 1.0)
			jackpot_state(1.0)
			if _speech_node != null: _speech_node.modulate.a = 1.0
		_dim_now = -1.0
		_apply_tones()
		return
	var plan := _flip_plan()
	var n := 0
	for i in card_nodes.size():
		if jp and i == jackpot_index: continue
		_turn(i, t, plan.x + plan.y * float(n), plan.z)
		n += 1
	if jp: _jackpot_t(t)

## One card turning over from its back: a turn about the vertical axis, a small lift; a rare card's frame light runs once after it lands.
func _turn(i: int, t: float, start: float, dur: float) -> void:
	var cd = card_nodes[i]
	var u := clampf((t - start) / dur, 0.0, 1.0)
	var e := smoothstep(0.0, 1.0, u)
	var th := PI * (1.0 - e)
	var up := cos(th) > 0.0
	if cd.face_up != up: cd.face_up = up
	cd.modulate.a = 1.0 if (_kind != "long" or t >= start - 0.1) else 0.0
	var lift := sin(PI * u)
	cd.scale = Vector2(maxf(absf(cos(th)), 0.02), 1.0 + 0.05 * lift)
	cd.position = _card_base[i] + Vector2(0.0, -16.0 * lift)
	var land := (t - (start + dur)) / 0.3
	cd.rim = land if (cd.gkey == "rare" and land >= 0.0 and land <= 1.0 and not reduce_motion) else -1.0

## Spec 5.7 in order: the last card creeps (heat climbs) -> the eye lights -> the screen is out 0.12 s -> the card arrives with sigil, grains and the plate
## -> the two others sink to 60 % -> the demon's line.
func _jackpot_t(t: float) -> void:
	var i := jackpot_index
	var cd = card_nodes[i]
	var heat := smoothstep(0.0, 0.8, t)
	heat_window(heat)
	cd.leak = heat * (1.0 - smoothstep(J_REVEAL, 1.3, t)) * 0.9
	var revealed := t >= J_SLOW_END
	if cd.face_up != revealed: cd.face_up = revealed
	if t < J_SLOW_END:
		var th := PI - 0.18 * PI * smoothstep(0.0, J_SLOW_END, t)
		cd.scale = Vector2(absf(cos(th)), 1.0)
		cd.position = _card_base[i] + Vector2(0.0, -8.0 * sin(PI * smoothstep(0.0, J_SLOW_END, t)))
	else:
		var pop := 1.0 - smoothstep(J_REVEAL, J_REVEAL + 0.14, t)
		cd.scale = Vector2.ONE * (1.0 + 0.08 * pop)
		cd.position = _card_base[i]
	eye_glow(0.8 * smoothstep(0.8, 0.95, t) + 0.25 * sin(PI * clampf((t - J_REVEAL) / 0.3, 0.0, 1.0)))
	var out := smoothstep(0.93, 0.97, t) * (1.0 - smoothstep(J_REVEAL, J_REVEAL + 0.05, t))
	blackout.color.a = 0.9 * out
	var su := clampf((t - J_REVEAL) / 0.25, 0.0, 1.0)
	if _sigil_bg != null:
		_sigil_bg.modulate.a = 0.0 if t < J_REVEAL else 1.0
		_sigil_bg.scale = Vector2.ONE * lerpf(1.4, 1.0, 1.0 - pow(1.0 - su, 3.0))
		_sigil_bg.rotation = cd.rotation + (1.0 - su) * 1.2
	var hu := clampf((t - J_REVEAL) / 0.23, 0.0, 1.0)
	var halo_node: Control = jackpot_parts.halo
	halo_node.pivot_offset = halo_node.size * 0.5
	halo_node.scale = Vector2.ONE * lerpf(1.7, 1.0, 1.0 - pow(1.0 - hu, 2.0))
	halo(0.0 if t < J_REVEAL else lerpf(1.7, 1.0, smoothstep(J_REVEAL, 1.5, t)))
	var bu := clampf((t - J_REVEAL) / 0.33, 0.0, 1.0)
	jackpot_parts.sparks.set_meta("burst", bu)
	jackpot_parts.sparks.modulate.a = 0.0 if t < J_REVEAL else 1.0
	jackpot_parts.sparks.queue_redraw()
	stamp(0.0 if t < J_REVEAL else clampf((t - J_REVEAL) / 0.2, 0.0, 1.0))
	if t < J_REVEAL: jackpot_parts.stamp.modulate.a = 0.0
	var dim := smoothstep(1.1, 1.3, t)
	if absf(dim - _dim_now) > 0.002:
		_dim_now = dim
		dim_others(dim)
		if t >= J_SLOW_END: cd.scale = Vector2.ONE * (1.0 + 0.08 * (1.0 - smoothstep(J_REVEAL, J_REVEAL + 0.14, t)))
	if _speech_node != null: _speech_node.modulate.a = smoothstep(1.6, 1.75, t)

# ---- the pick (5.8): press 0.06 -> the mark flies 0.3 -> the socket flares, the demon bursts, the others fall 0.15 -> 0.46 s
func _paint_trail(c: Control) -> void:
	if _fly_t <= 0.0 or _fly_t >= 1.0: return
	var col := Kit.el_color(el)
	for k in 12:
		var u := _fly_t - float(k) * 0.03
		if u <= 0.0: break
		var e := _fly_ease(u)
		var p := _fly_from.lerp(_fly_to, e) + Vector2(0, -110.0 * sin(PI * e))
		var f := 1.0 - float(k) / 12.0
		c.draw_circle(p, 5.0 + 17.0 * f, Kit.with_alpha(col, 0.55 * f))
		c.draw_circle(p, 2.0 + 7.0 * f, Kit.with_alpha(Palette.GRACE_JACKPOT, 0.6 * f))

func _paint_socket(c: Control) -> void:
	if _sock_a <= 0.0: return
	var chip: float = band_node.chip
	c.draw_circle(_fly_to, chip * 0.9, Kit.with_alpha(Palette.BRASS_HI, 0.45 * _sock_a))
	c.draw_arc(_fly_to, chip * (0.5 + 0.5 * (1.0 - _sock_a)), 0.0, TAU, 40, Kit.with_alpha(Palette.BRASS_HI, _sock_a), 4.0, true)

func _fly_ease(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return 4.0 * u * u * u if u < 0.5 else 1.0 - pow(-2.0 * u + 2.0, 3.0) / 2.0

func _prepare_confirm(i: int) -> void:
	var cd = card_nodes[i]
	var en: String = Parts.emblem_name(String(cards[i].get("element", el)), String(cards[i].get("kind", "new")))
	if Parts.tex(en) != null: _fly = Parts.art_rect(self, en, Rect2(Vector2.ZERO, Vector2(64, 64)))
	_fly_from = cd.emblem_center()
	_fly_to = band_node.target_for(cards[i])
	_fly_s0 = cd.emblem_box.size.x * cd.scale.x / 64.0
	_fly_s1 = band_node.chip * 0.86 / 64.0
	if _fly != null: _fly.visible = false
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_trail_layer = Parts.layer(self, Callable(self, "_paint_trail"), Rect2(Vector2.ZERO, Kit.SIZE))
	_trail_layer.material = add
	_sock_layer = Parts.layer(self, Callable(self, "_paint_socket"), Rect2(Vector2.ZERO, Kit.SIZE))
	var centre := demon_rect.position + demon_rect.size * Vector2(0.5, 0.3)
	_burst = Parts.glow_rect(stage, centre, 460.0, Kit.with_alpha(Kit.el_color(el), 0.0))
	_burst_gold = Parts.glow_rect(stage, centre, 240.0, Kit.with_alpha(Palette.GRACE_JACKPOT, 0.0))
	cd.set_meta("emblem_node", cd.find_child(en, false, false))

func _confirm_anim(index: int) -> float:
	if focus_index != index: set_focus(index)
	_prepare_confirm(index)
	card_nodes[index].leak = 1.0
	var tw := create_tween()
	tw.tween_method(func(t): _confirm_t(index, t), 0.0, confirm_len, confirm_len)
	return confirm_len

func _confirm_t(i: int, t: float) -> void:
	var cd = card_nodes[i]
	var moving := not reduce_motion
	var pu := clampf(t / 0.06, 0.0, 1.0)
	if moving:
		cd.scale = Vector2.ONE * lerpf(1.03, 0.97, pu)
		cd.position = _card_base[i] + Vector2(0.0, 6.0 * pu)
	_fly_t = clampf((t - 0.06) / 0.3, 0.0, 1.0)
	var emb = cd.get_meta("emblem_node", null)
	if emb != null: emb.modulate.a = 1.0 if t < 0.06 else lerpf(1.0, 0.22, smoothstep(0.06, 0.16, t))
	if _fly != null:
		_fly.visible = t >= 0.06
		var e := _fly_ease(_fly_t)
		if moving:
			_fly.position = _fly_from.lerp(_fly_to, e) + Vector2(0, -110.0 * sin(PI * e)) - _fly.size * 0.5
			_fly.scale = Vector2.ONE * lerpf(_fly_s0, _fly_s1, e)
		else:
			_fly.position = _fly_to - _fly.size * 0.5
			_fly.scale = Vector2.ONE * _fly_s1
			_fly.modulate.a = smoothstep(0.06, 0.3, t)
	_trail_layer.queue_redraw()
	_sock_a = 0.0 if t < 0.36 else clampf(1.0 - (t - 0.36) / 0.1, 0.0, 1.0)
	_sock_layer.queue_redraw()
	var bu := 0.0 if t < 0.36 else smoothstep(0.36, 0.4, t) * (1.0 - 0.6 * smoothstep(0.4, 0.46, t))
	_burst.modulate = Kit.with_alpha(Kit.el_color(el), 0.55 * bu)
	_burst_gold.modulate = Kit.with_alpha(Palette.GRACE_JACKPOT, 0.45 * bu)
	var du := clampf((t - 0.36) / 0.15, 0.0, 1.0)
	for k in card_nodes.size():
		if k == i: continue
		card_nodes[k].modulate.a = 1.0 - du
		if moving: card_nodes[k].position = _card_base[k] + Vector2(0.0, 70.0 * du * du)

# ============================================================ focus and tones
func _focus_changed(_old: int, new: int) -> void:
	_apply_tones()
	if note_node != null: note_node.show_card(cards[new])
	if band_node != null:
		band_node.lit = band_node.link_slots(cards[new])
		band_node.lit_amount = 1.0 if not band_node.lit.is_empty() else 0.0

func _apply_tones() -> void:
	for i in card_nodes.size():
		var cd = card_nodes[i]
		var mult := 1.0
		if jackpot_index >= 0 and i != jackpot_index: mult = lerpf(1.0, 0.75, _dim)   ## the two other cards sink to about 60 % while the jackpot is held
		cd.set_focus_amount(1.0 if i == focus_index else 0.35, mult)

# ============================================================ state, input (D9 6.2 / Input48)
func mark(name_: String) -> void:
	events.append({"t": snappedf(clock - intro_start, 0.001), "e": name_})

func track(tw: Tween) -> Tween:
	_tweens.append(tw)
	return tw

## Begins the intro: nothing is accepted but "skip" until the cards settle; a pick is then refused for LOCK seconds.
func play_intro() -> void:
	state = "intro"
	intro_start = clock
	events.clear()
	_kind = Grace.intro_kind(contract)
	_intro_len = Grace.intro_seconds(_kind)
	var tw := track(create_tween())
	tw.tween_method(_intro_t, 0.0, _intro_len, _intro_len)
	var t_c := _intro_len
	if reduce_motion:
		skip_intro()
		t_c = 0.12
		modulate.a = 0.0
		track(create_tween()).tween_property(self, "modulate:a", 1.0, 0.12)
	unlock_t = t_c + LOCK
	unlock_abs = intro_start + unlock_t
	mark("intro_start")
	var done := create_tween()
	done.tween_interval(t_c)
	done.tween_callback(func():
		if state == "intro":
			state = "ready"
			mark("cards_settled")
			_settle_focus()
			ready_for_pick.emit())

func skip_intro() -> void:
	if state != "intro": return
	for tw in _tweens:
		if tw != null and tw.is_valid():
			tw.pause()
			tw.custom_step(100.0)
	_tweens.clear()
	_intro_t(INF)
	state = "ready"
	unlock_abs = clock + LOCK
	mark("intro_skipped")
	_settle_focus()
	ready_for_pick.emit()

## The screen shown again for an offer already seen (after a pause): the settled screen at once.
func show_settled() -> void:
	state = "ready"
	_intro_t(INF)
	unlock_abs = clock + LOCK
	_settle_focus()
	ready_for_pick.emit()

## When the cards settle one of them is already lit (the best grade, else the first) so the side note is never empty.
func _settle_focus() -> void:
	if focus_index < 0 and not cards.is_empty(): set_focus(best_index())

func set_focus(i: int) -> void:
	if i == focus_index or i < 0 or i >= cards.size(): return
	var old := focus_index
	focus_index = i
	mark("focus_%d" % i)
	_focus_changed(old, i)

func move_focus(step: int) -> void:
	set_focus(posmod(maxi(focus_index, 0) + step, cards.size()) if focus_index >= 0 else 0)

func try_pick(i: int) -> bool:
	if state != "ready" or clock < unlock_abs or i < 0 or i >= cards.size():
		mark("pick_rejected")
		return false
	state = "done"
	mark("pick_%d" % i)
	var d := _confirm_anim(i)
	var tw := create_tween()
	tw.tween_interval(d)
	tw.tween_callback(func():
		mark("confirm_done")
		chosen.emit(String(cards[i].id)))
	return true

func _unhandled_key_input(e: InputEvent) -> void:
	if state == "idle" or state == "done" or not (e is InputEventKey and e.pressed and not e.echo): return
	if state == "intro":
		if e.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_1, KEY_2, KEY_3, KEY_SPACE]:
			skip_intro()
			get_viewport().set_input_as_handled()
		return
	match e.keycode:
		KEY_1: try_pick(0)
		KEY_2: try_pick(1)
		KEY_3: try_pick(2)
		KEY_LEFT, KEY_A: move_focus(-1)
		KEY_RIGHT, KEY_D: move_focus(1)
		KEY_ENTER, KEY_KP_ENTER: try_pick(maxi(focus_index, 0))
		KEY_R: _knob_pressed("reroll")
		KEY_X: _knob_pressed("exclude")
		_: return   ## Space and everything else: nothing (D9 6.2)
	get_viewport().set_input_as_handled()

func best_index() -> int:
	var best := 0
	for i in cards.size():
		if Grace.grade_rank(Grace.grade_key(String(cards[i].grade))) > Grace.grade_rank(Grace.grade_key(String(cards[best].grade))): best = i
	return best

func pretty_events() -> Array:
	return events
