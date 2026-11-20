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
	hand_glow = hand
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
	_post_layout()

# ============================================================ G4 motion (A8, only proposal E). Everything is a pure function of the time t, so a key press
# (skip_intro -> tween custom_step) lands on the same end screen. Tests only: no core state is read or written.
const BOB_P2P := 22.0        ## body bob, peak to peak, in 1600 x 900 code px (26 px at 1080p, 2.4 % of the height; Sacrata measured 20 px / 1.9 %)
const FLIP_NORMAL := Vector3(0.0, 0.15, 0.15)   ## first flip start, step between cards, flip length (7.3: three cards within 0.45 s)
const FLIP_LONG := Vector3(1.1, 0.2, 0.25)
const J_SLOW_END := 0.95     ## jackpot: the last card creeps until here, the screen goes out 0.95 .. 1.07 (5.7)
const J_REVEAL := 1.07
const BODY_SH := "shader_type canvas_item;\nuniform float fx = 0.2;\nuniform float fb = 0.05;\nuniform float ft = 0.05;\nuniform vec3 tint = vec3(1.0);\nuniform float amt = 1.0;\nvoid fragment(){ vec4 c = texture(TEXTURE, UV); float ax = smoothstep(0.0, fx, UV.x) * smoothstep(0.0, fx, 1.0 - UV.x); float ab = smoothstep(0.0, max(fb, 0.001), 1.0 - UV.y); float at = ft > 0.0 ? smoothstep(0.0, ft, UV.y) : 1.0; COLOR = vec4(c.rgb * tint, c.a * ax * ab * at * amt); }\n"
const AURA_SH := "shader_type canvas_item;\nrender_mode blend_add;\nuniform float fx = 0.2;\nuniform float fb = 0.05;\nuniform float ft = 0.05;\nuniform vec3 tint = vec3(1.0);\nuniform float amt = 0.2;\nvoid fragment(){ vec4 c = texture(TEXTURE, UV); float ax = smoothstep(0.0, fx, UV.x) * smoothstep(0.0, fx, 1.0 - UV.x); float ab = smoothstep(0.0, max(fb, 0.001), 1.0 - UV.y); float at = ft > 0.0 ? smoothstep(0.0, ft, UV.y) : 1.0; COLOR = vec4(c.rgb * tint * amt, c.a * ax * ab * at); }\n"

var hand_glow: Control
var ui_root: Control
var blackout: ColorRect
var _body_mat: ShaderMaterial
var _aura_mat: ShaderMaterial
var _card_base: Array = []
var _sigil_bg: Control
var _kind := "normal"
var _intro_len := 0.45
var _dim_now := -1.0
var _speech_node: Control
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
var _eye_base := Vector2.ZERO
## The right eye of each temporary figure as a fraction of its picture, read with a pixel grid from the 1080p frames (the G3 estimates sat on the cheek / neck). Still an estimate: final figure -> re-read.
const EYE_E := {"ember": Vector2(0.510, 0.104), "frost": Vector2(0.505, 0.106), "arc": Vector2(0.507, 0.062)}

func _post_layout() -> void:
	fx_motion = true
	# the whole screen but the stage rides on ui_root (so the long intro can bring it in after the stage); a blackout lies over everything
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
	blackout.color = Color(0.0, 0.0, 0.0, 0.0)
	blackout.size = Kit.SIZE
	blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blackout.z_index = 20   ## over the jackpot card too (its z_index is 3)
	add_child(blackout)
	for cd in card_nodes: _card_base.append(cd.position)
	_speech_node = ui_root.find_child("DemonLine", true, false)
	# the figure: own shaders (tint / amount for the silhouette -> colour step; an additive aura for the trailing layer)
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
	if jackpot_index >= 0 and Grace.tex("sigil") != null:
		var r: Rect2 = jackpot_parts.rect
		var d := r.size.x * 1.15
		_sigil_bg = Grace.art_rect(cards_root, "sigil", Rect2(r.get_center() - Vector2(d, d) * 0.5, Vector2(d, d)), {"add": true, "tint": Color(1, 1, 1, 0.6)})
		cards_root.move_child(_sigil_bg, card_nodes[jackpot_index].get_index())
		_sigil_bg.modulate.a = 0.0
		_sigil_bg.rotation = card_nodes[jackpot_index].rotation
	if jackpot_parts.has("eye"):
		var eye: Control = jackpot_parts.eye
		eye.size = Vector2(46, 46)
		_eye_base = demon_rect.position + demon_rect.size * EYE_E.get(el, Vector2(0.5, 0.11)) - eye.size * 0.5
		eye.position = _eye_base
	_intro_t(INF)   ## the settled screen until play_intro begins

# ---- the figure (5.2 item 4): the body 2.7 s, the trailing layer 1.5x and 0.2 s later; no sideways move, no face change
func demon_pose(t: float) -> void:
	if demon == null: return
	var ph := t * TAU / DEMON_PERIOD
	demon.position.y = demon_rect.position.y + sin(ph) * BOB_P2P * 0.5
	var late := sin((t - TRAIL_LAG) * TAU / DEMON_PERIOD) * BOB_P2P * 0.75
	if demon_trail != null: demon_trail.position.y = demon_rect.position.y + late
	if jackpot_parts.has("eye"): jackpot_parts.eye.position.y = _eye_base.y + sin(ph) * BOB_P2P * 0.5
	if demon_rim != null: demon_rim.position.y = demon_rect.position.y + demon_rect.size.y * 0.42 - demon_rim.size.y * 0.5 + late

func eye_glow(a: float) -> void:   ## quieter than the G3 value: an eye-sized point, never a white smear
	if jackpot_parts.has("eye"): jackpot_parts.eye.modulate = Kit.with_alpha(Kit.el_color(el), 0.6 * a)

# ---- the intro / jackpot sequence
func _flip_plan() -> Vector3:
	return FLIP_LONG if _kind == "long" else FLIP_NORMAL

func _intro() -> float:
	_kind = Grace.intro_kind(contract)
	_intro_len = Grace.intro_seconds(_kind)
	var tw := track(create_tween())
	tw.tween_method(_intro_t, 0.0, _intro_len, _intro_len)
	return _intro_len

func _settle_all() -> void:
	_intro_t(INF)
	super._settle_all()

func _tint_demon(sil: float, amt: float) -> void:
	if _body_mat == null: return
	var c := Kit.el_color(el)
	var dark := Vector3(c.r, c.g, c.b) * 0.30
	_body_mat.set_shader_parameter("tint", dark.lerp(Vector3.ONE, sil))
	_body_mat.set_shader_parameter("amt", amt)
	if demon_trail != null: _aura_mat.set_shader_parameter("amt", 0.30 * amt * sil)
	if demon_rim != null: demon_rim.visible = amt * sil > 0.01

func _intro_t(t: float) -> void:
	var final := is_inf(t) or t >= _intro_len
	var long := _kind == "long"
	var jp := _kind == "jackpot" and jackpot_index >= 0
	# stage: ground -> shafts -> silhouette -> colour -> (long: the hand's flash)
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
		if long and not final: fl = sin(PI * clampf((t - 1.2) / 0.4, 0.0, 1.0))   ## 1.2 .. 1.6, element colour, never white
		hand_glow.modulate = Kit.with_alpha(Kit.el_color(el).lerp(Grace.FLAME_WARM, 0.25 * fl), 0.34 + 0.40 * fl)
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
			if _sigil_bg != null:
				_sigil_bg.modulate.a = 0.0   ## the held screen of G3 has no separate sigil behind the card (the card's own sigil turns)
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

## One card turning over from its back: a turn about the vertical axis (width |cos|), a small lift; a rare card's frame light runs once after it lands.
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

## 5.7 in order (t = seconds from the start): the last card creeps (heat climbs) -> the eye lights -> the screen is out 0.12 s -> the card arrives with
## sigil, gold grains and the plate -> the two others sink to 60 % -> the demon's line.
func _jackpot_t(t: float) -> void:
	var i := jackpot_index
	var cd = card_nodes[i]
	var heat := smoothstep(0.0, 0.8, t)
	heat_window(heat)
	cd.leak = heat * (1.0 - smoothstep(J_REVEAL, 1.3, t)) * 0.9
	var revealed := t >= J_SLOW_END
	if cd.face_up != revealed: cd.face_up = revealed
	if t < J_SLOW_END:
		var th := PI - 0.18 * PI * smoothstep(0.0, J_SLOW_END, t)   ## the turn slows, the back stays
		cd.scale = Vector2(absf(cos(th)), 1.0)
		cd.position = _card_base[i] + Vector2(0.0, -8.0 * sin(PI * smoothstep(0.0, J_SLOW_END, t)))
	else:
		var pop := 1.0 - smoothstep(J_REVEAL, J_REVEAL + 0.14, t)
		cd.scale = Vector2.ONE * (1.0 + 0.08 * pop)
		cd.position = _card_base[i]
	eye_glow(0.8 * smoothstep(0.8, 0.95, t) + 0.25 * sin(PI * clampf((t - J_REVEAL) / 0.3, 0.0, 1.0)))
	# the screen goes out (0.95 .. 1.07: 90 % black) and comes back with the card
	var out := smoothstep(0.93, 0.97, t) * (1.0 - smoothstep(J_REVEAL, J_REVEAL + 0.05, t))
	blackout.color.a = 0.9 * out
	# sigil 1.4 -> 1.0 turning (0.25 s), halo, grains, plate
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
	# the two others sink to 60 % by 1.30
	var dim := smoothstep(1.1, 1.3, t)
	if absf(dim - _dim_now) > 0.002:
		_dim_now = dim
		dim_others(dim)
		cd.scale = cd.scale   ## _apply_tones resets scales; the lines below put this card's back
		if t < J_SLOW_END: pass
		else: cd.scale = Vector2.ONE * (1.0 + 0.08 * (1.0 - smoothstep(J_REVEAL, J_REVEAL + 0.14, t)))
	if _speech_node != null: _speech_node.modulate.a = smoothstep(1.6, 1.75, t)

# ---- the pick (5.8): press 0.06 -> the mark flies 0.3 (arc, element tail) -> the socket flares, the demon bursts, the others fall 0.15 -> 0.46 s
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
		c.draw_circle(p, 2.0 + 7.0 * f, Kit.with_alpha(Grace.JACKPOT_GOLD, 0.6 * f))

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
	var en: String = Grace.emblem_name(String(cards[i].get("element", el)), String(cards[i].get("kind", "new")))
	if _fly == null: _fly = Grace.art_rect(self, en, Rect2(Vector2.ZERO, Vector2(64, 64)))
	_fly_from = cd.emblem_center()
	_fly_to = band_node.target_for(cards[i])
	_fly_s0 = cd.emblem_box.size.x * cd.scale.x / 64.0
	_fly_s1 = band_node.chip * 0.86 / 64.0
	if _fly != null: _fly.visible = false
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_trail_layer = Grace.layer(self, Callable(self, "_paint_trail"), Rect2(Vector2.ZERO, Kit.SIZE))
	_trail_layer.material = add
	_sock_layer = Grace.layer(self, Callable(self, "_paint_socket"), Rect2(Vector2.ZERO, Kit.SIZE))
	var centre := demon_rect.position + demon_rect.size * Vector2(0.5, 0.3)
	_burst = Grace.glow_rect(stage, centre, 460.0, Kit.with_alpha(Kit.el_color(el), 0.0))
	_burst_gold = Grace.glow_rect(stage, centre, 240.0, Kit.with_alpha(Grace.JACKPOT_GOLD, 0.0))
	cd.set_meta("emblem_node", cd.find_child(en, false, false))

func _confirm_anim(index: int) -> float:
	if focus_index != index: set_focus(index)   ## a pick by key also moves the focus (the card is lit while it is taken)
	_prepare_confirm(index)
	card_nodes[index].leak = 1.0
	var tw := create_tween()
	tw.tween_method(func(t): _confirm_t(index, t), 0.0, confirm_len, confirm_len)
	return confirm_len

func _confirm_t(i: int, t: float) -> void:
	var cd = card_nodes[i]
	var moving := not reduce_motion
	# 0.00 press: 6 px down in 0.06 s
	var pu := clampf(t / 0.06, 0.0, 1.0)
	if moving:
		cd.scale = Vector2.ONE * lerpf(1.03, 0.97, pu)
		cd.position = _card_base[i] + Vector2(0.0, 6.0 * pu)
	# 0.06 the mark leaves the card and flies an arc to its socket (0.3 s)
	_fly_t = clampf((t - 0.06) / 0.3, 0.0, 1.0)
	var emb = cd.get_meta("emblem_node", null)
	if emb != null: emb.modulate.a = 1.0 if t < 0.06 else lerpf(1.0, 0.22, smoothstep(0.06, 0.16, t))   ## a copy flies off; the card keeps a faint print
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
	# 0.36 the brass ring flares (0.1 s) and the demon bursts once (element colour, a gold core)
	_sock_a = 0.0 if t < 0.36 else clampf(1.0 - (t - 0.36) / 0.1, 0.0, 1.0)
	_sock_layer.queue_redraw()
	var bu := 0.0 if t < 0.36 else smoothstep(0.36, 0.4, t) * (1.0 - 0.6 * smoothstep(0.4, 0.46, t))
	_burst.modulate = Kit.with_alpha(Kit.el_color(el), 0.55 * bu)
	_burst_gold.modulate = Kit.with_alpha(Grace.JACKPOT_GOLD, 0.45 * bu)
	# 0.36 the others drop and are gone in 0.15 s
	var du := clampf((t - 0.36) / 0.15, 0.0, 1.0)
	for k in card_nodes.size():
		if k == i: continue
		card_nodes[k].modulate.a = 1.0 - du
		if moving: card_nodes[k].position = _card_base[k] + Vector2(0.0, 70.0 * du * du)
