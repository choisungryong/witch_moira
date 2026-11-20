extends "res://chapter1/tests/proposals/growth_choice/base.gd"
## A8 G3: the shared stage of the two grace proposals D "the demon's table" (d_table.gd) and E "the demon's hand" (e_hand.gd). Tests only.
## Both lay the same parts (grace_parts.gd) on the same stage: ground -> light shafts -> demon -> motes -> board / reliquary / cards -> band, knobs, note ->
## title plaque + candles -> demon's line -> dev tag. The still shows the END state (the settled screen, and for a jackpot the held jackpot screen of spec 5.7 at t = 1.30 s):
## the stamped plate, the heated window, the two other cards at 60 %, light kept within 115 % of the jackpot card's width, <= 60 gold motes.
## Motion belongs to G4 (vfx-feel). The places it attaches to are the functions in the "G4 HOOKS" block below; each takes a plain amount / time and draws that state.
##   demon_pose(t)            body bob (2.7 s, small) + the trailing layer (bigger, later)       -> spec 5.2 item 4
##   shafts_level(i, v)       one light shaft's strength 0..1 (irregular flicker is G4's)           -> 5.2 item 3
##   motes_time(t)            the drifting things of the element (3.1 .. 4.3 s periods)           -> 5.2 item 5
##   jackpot_state(a)         the held jackpot screen at amount 0..1 (heat, dimming, plate, sparks, halo, eye)
##   jackpot_parts            {"heat", "dim", "stamp", "sparks", "halo", "eye"}: set each with its own function below for the 5.7 order
##   heat_window(a) / dim_others(a) / stamp(a) / sparks(a) / halo(a) / eye_glow(a)
##   confirm_press(i) / confirm_fly(i, t) / confirm_burst(a) / confirm_drop_others(i, t)           -> 5.8 order
##   reveal(i, a)             card i from its back (a = 0) to its face (a = 1)                    -> E's flip
## The demon pictures are the TEMPORARY figures from _local/art/queue (the user has not chosen yet): the file is named in the dev tag.
const Grace = preload("res://chapter1/tests/proposals/growth_choice/grace_parts.gd")
const DEMON_BOB := 12.0
const DEMON_PERIOD := 2.7
## Face of the figure as a fraction of its picture (ESTIMATE read from the thumbnails; G4 / character-artist fix it with the final figure).
const EYE := {"ember": Vector2(0.43, 0.125), "frost": Vector2(0.47, 0.13), "arc": Vector2(0.48, 0.125)}
const TRAIL_LAG := 0.2

var el := "frost"
var jackpot_index := -1
var capture_mode := false
var card_nodes: Array = []
var cards_root: Control
var note_node
var band_node
var knob_nodes: Array = []
var plaque_node
var candle_nodes: Array = []
var demon_rect := Rect2()
var demon: Control
var demon_trail: Control
var shaft_nodes: Array = []
var motes: Control
var jackpot_parts := {}
var confirm_len := 0.46
var _motes_t := 0.0
var _pose_t := 0.0
var _demon_file := ""
var _fly: Control
var _flame: Color
var demon_rim: Control
var fx_motion := false   ## G4 motion pack (E only): light flicker runs in _process
var _live := false       ## a continuous capture (--strip*): motion runs although capture_mode is on
var _shaft_gain := 1.0
var stage: Control   ## clipped to the screen: ground, light, demon and motes that run past the edge live here

# ============================================================ build
func _build() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--strip"): _live = true
	el = String(contract.get("witch", {}).get("element", "frost"))
	_flame = Kit.el_color(el).lerp(Grace.FLAME_WARM, 0.55)
	for i in cards.size():
		if Grace.grade_key(String(cards[i].get("grade", "common"))) == "jackpot": jackpot_index = i
	stage = Control.new()
	stage.size = Kit.SIZE
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	_ground()
	_layout()
	_dev_tag()
	_apply_tones()
	if jackpot_index >= 0: jackpot_state(1.0)
	set_process(true)

## Overridden by D and E: places demon, shafts, motes, cards, band, knobs, note, title, candles and calls _jackpot_fx.
func _layout() -> void:
	pass

func _process(delta: float) -> void:
	super._process(delta)
	if capture_mode and not _live: return
	_pose_t += delta
	_motes_t += delta
	if fx_motion: _flicker(_pose_t)
	if reduce_motion: return   ## reduced motion: brightness only, no position change
	demon_pose(_pose_t)
	motes_time(_motes_t)

## Irregular light-shaft strength (about 1.2 s beats, a different depth every time): sums of unrelated sines, never in step with the 2.7 s figure.
func _flicker(t: float) -> void:
	for i in shaft_nodes.size():
		var f := float(i) * 1.9
		var v := 0.62 + 0.28 * sin(t * TAU / 1.2 + f) * (0.6 + 0.4 * sin(t * 0.83 + f)) + 0.10 * sin(t * 3.7 + f * 1.3)
		shafts_level(i, clampf(v, 0.25, 1.0))

func _ground() -> void:
	var tex: Texture2D = Grace.tex("demon_" + el)
	var base := Color(0.025, 0.027, 0.034)
	if tex != null: base = tex.get_image().get_pixel(10, 10).lightened(0.0)   ## the figure's own ground colour: the picture melts into the stage
	var g := ColorRect.new()
	g.color = base
	g.size = Kit.SIZE
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(g)
	# the combat scene, dimmed to 35 % at most, as an image (a drawn layer, not a node the layout check counts)
	var abs_path := Kit.find_local(String(contract.get("backdrop", "")))
	var cap: Texture2D = Kit.image_texture(abs_path) if abs_path != "" else null
	if cap != null:
		var pic := Grace.ArtLayer.new()
		pic.texture = cap
		pic.size = Kit.SIZE
		pic.modulate = Color(1, 1, 1, 0.07)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(pic)
	Grace.glow_rect(stage, Vector2(300, 260), 560.0, Kit.with_alpha(Kit.el_color(el), 0.16))   ## the element's colour behind the figure
	var vig := Grace.ArtLayer.new()
	vig.texture = Kit.vignette_texture()
	vig.size = Kit.SIZE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.modulate = Color(1, 1, 1, 0.8)
	stage.add_child(vig)

# ============================================================ stage parts (used by D and E)
## Soft element-coloured light shafts (an elongated radial gradient turned about 20 degrees, additive; never a hard wedge).
func _shafts(origin: Vector2, count := 2) -> void:
	for i in count:
		var g := Grace.glow_rect(stage, origin + Vector2(float(i) * 130.0, 400.0), 1.0, Kit.with_alpha(Kit.el_color(el), 0.10))
		g.size = Vector2(300.0 + 80.0 * i, 1500.0)
		g.position = origin + Vector2(float(i) * 150.0 - g.size.x * 0.5, 380.0 - g.size.y * 0.5)
		g.pivot_offset = g.size * 0.5
		g.rotation = -0.38 + 0.06 * i
		shaft_nodes.append(g)

func _demon(rect: Rect2) -> void:
	demon_rect = rect
	var name_ := "demon_" + el
	var tex: Texture2D = Grace.tex(name_)
	if tex == null:
		Grace.note_source("demon (stand-in)", "code")
		return
	_demon_file = String(Grace.path_of(name_)[0]).get_file()
	demon_trail = Grace.ArtLayer.new()
	demon_trail.texture = tex
	demon_trail.position = rect.position
	demon_trail.size = rect.size
	demon_trail.modulate = Color(1, 1, 1, 0.0)   ## the trailing layer: invisible until G4 pose(t) shows it
	demon_trail.material = Kit.feather_material(0.2, 0.05, 0.05)
	demon_trail.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	demon_trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(demon_trail)
	demon = Grace.ArtLayer.new()
	demon.texture = tex
	demon.position = rect.position
	demon.size = rect.size
	demon.material = Kit.feather_material(0.2, 0.05, 0.05)
	demon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	demon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(demon)
	Grace.note_source("demon (temporary figure)", Grace.source_of(name_))
	# rim light of the element along the figure's lit side (additive, soft)
	demon_rim = Grace.glow_rect(stage, rect.position + rect.size * Vector2(0.62, 0.42), rect.size.x * 0.55, Kit.with_alpha(Kit.el_color(el), 0.10))

## Small things of the element around the figure (embers / ice shards / current dots), drawn in one layer; placed once, drifted by motes_time(t).
func _motes(zone: Rect2, count := 26) -> void:
	motes = Grace.layer(stage, Callable(self, "_paint_motes"), Rect2(Vector2.ZERO, Kit.SIZE))
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
	var ui_title := String(ui.get("title_last", ui.get("title", ""))) if String(contract.get("moment", {}).get("kind", "")) == "last" else String(ui.get("title", ""))
	plaque_node = Grace.title(self, ui_title, width, String(contract.get("moment", {}).get("label", "")))
	plaque_node.position = Vector2(center_x - plaque_node.size.x * 0.5, y)
	for sgn in [-1.0, 1.0]:
		var c = Grace.candle(self, Vector2(center_x + sgn * candle_dx - candle_h * 0.25, candle_y), candle_h, _flame)
		c.animated = not (reduce_motion or capture_mode)
		candle_nodes.append(c)

func _band(pos: Vector2, width: float) -> void:
	band_node = Grace.band(self, pos, width, contract)

func _knobs(pos: Vector2, gap: float) -> void:
	knob_nodes = Grace.handles(self, contract, pos, gap)
	for k in knob_nodes:
		k.pressed.connect(func(id): if id == "reroll": reroll_requested.emit())

func _note(rect: Rect2) -> void:
	note_node = Grace.note(self, rect, contract)

## The demon's line (none when the demon does not speak: giver.mute).
func _speech(pos: Vector2, width: float) -> void:
	var giver: Dictionary = contract.get("giver", {})
	var line: Variant = giver.get("line", null)
	if bool(giver.get("mute", false)) or line == null or str(line) == "": return
	var l: Label = Kit.lbl(self, str(line), pos, width, 19, Palette.INK, "body", HORIZONTAL_ALIGNMENT_LEFT, true, true)
	l.name = "DemonLine"

func _dev_tag_text() -> String:
	var t := "%s · demon figure (temporary, not chosen yet): %s · eye position is an estimate · kit: %s · %s" % [String(get_script().resource_path).get_file(), _demon_file,
		Grace.kit_folder().get_file() if Grace.kit_folder() != "" else "none", Grace.report_line()]
	var dn := Grace.dev_notes(contract)
	if dn != "": t += " · dev text kept off the screen: " + dn
	return t

func _dev_tag() -> void:
	pass

func _tag_label(pos: Vector2, width: float) -> void:
	Kit.lbl(self, _dev_tag_text(), pos, width, 14, Palette.INK_FAINT, "body", HORIZONTAL_ALIGNMENT_LEFT, true).name = "DevTag"

## One card per slot: `rects[i]` is where card i sits (D: a reliquary window, E: a fan place). Returns the nodes.
func _cards_into(rects: Array, tilts: Array) -> void:
	cards_root = Control.new()
	cards_root.size = Kit.SIZE
	cards_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cards_root)
	for i in cards.size():
		var r: Rect2 = rects[i]
		var cd = Grace.card(cards_root, cards[i], i, r.size, ui)
		cd.position = r.position
		cd.rotation = float(tilts[i])
		cd.animated = not (reduce_motion or capture_mode)
		cd.clicked.connect(func(k): set_focus(k); try_pick(k))
		cd.hovered.connect(func(k): set_focus(k))
		card_nodes.append(cd)

# ============================================================ jackpot parts (spec 5.7, the held screen)
## Builds the jackpot nodes around card `i` (its global-in-scene rect `r`, `tilt` radians). All start at amount 0; jackpot_state(1) shows the held screen.
func _jackpot_fx(r: Rect2, heat_rect: Rect2, stamp_pos: Vector2, tilt := 0.0) -> void:
	if jackpot_index < 0: return
	var c := r.get_center()
	var halo := Grace.glow_rect(cards_root, c, r.size.x * 0.62, Kit.with_alpha(Palette.BRASS_HI, 0.0))
	card_nodes[jackpot_index].get_parent().move_child(halo, card_nodes[jackpot_index].get_index())   ## under the card, over the board
	var heat := Grace.layer(self, Callable(self, "_paint_heat"), Rect2(Vector2.ZERO, Kit.SIZE))
	heat.set_meta("rect", heat_rect)
	heat.set_meta("tilt", tilt)
	heat.modulate.a = 0.0
	var stamp = Grace.jackpot(self, String(ui.get("fated_banner", "")), Vector2(230, 84))
	stamp.position = stamp_pos - stamp.size * 0.5
	stamp.modulate.a = 0.0
	var sp := Grace.layer(self, Callable(self, "_paint_sparks"), Rect2(Vector2.ZERO, Kit.SIZE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var pts: Array = []
	var outer := Rect2(Vector2.ZERO, r.size).grow(r.size.x * 0.13)   ## the light and the motes stay within 115 % of the card's width (13 % beyond each edge)
	var inner_r := Rect2(Vector2.ZERO, r.size).grow(3.0)
	while pts.size() < 56:
		var q := outer.position + Vector2(rng.randf() * outer.size.x, rng.randf() * outer.size.y)
		if inner_r.has_point(q): continue          ## none on the card itself: its text stays clear
		pts.append(c + (q - r.size * 0.5).rotated(tilt) + Vector2.ZERO)
	sp.set_meta("pts", pts)
	sp.set_meta("center", c)
	sp.set_meta("burst", 1.0)
	sp.modulate.a = 0.0
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sp.material = m
	var eye_f: Vector2 = EYE.get(el, Vector2(0.47, 0.13))
	var eye: Control = Grace.glow_rect(self, demon_rect.position + demon_rect.size * eye_f, 34.0, Kit.with_alpha(Kit.el_color(el), 0.0))
	jackpot_parts = {"halo": halo, "heat": heat, "stamp": stamp, "sparks": sp, "eye": eye, "rect": r}

func _paint_heat(c: Control) -> void:
	var r: Rect2 = c.get_meta("rect")
	c.draw_set_transform(r.get_center(), float(c.get_meta("tilt", 0.0)))
	var h := Rect2(-r.size * 0.5, r.size)
	for k in 6:
		c.draw_rect(h.grow(float(k) * 2.5), Kit.with_alpha(Grace.JACKPOT_GOLD, 0.5 * (1.0 - float(k) / 6.0)), false, 3.0)

func _paint_sparks(c: Control) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 78
	var ctr: Vector2 = c.get_meta("center", Vector2.ZERO)
	var b: float = 1.0 - pow(1.0 - float(c.get_meta("burst", 1.0)), 3.0)
	for p0 in c.get_meta("pts", []):
		var p: Vector2 = ctr.lerp(p0, b)
		var s := rng.randf_range(1.4, 3.6)
		c.draw_circle(p, s, Kit.with_alpha(Grace.JACKPOT_GOLD, 0.9))
		c.draw_circle(p, s * 2.6, Kit.with_alpha(Grace.JACKPOT_GOLD, 0.16))

# ============================================================ G4 HOOKS
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

var _dim := 0.0

func stamp(a: float) -> void:
	if jackpot_parts.has("stamp"):
		var s = jackpot_parts.stamp
		s.modulate.a = clampf(a * 1.5, 0.0, 1.0)
		s.scale = Vector2.ONE * lerpf(1.4, 1.0, clampf(a, 0.0, 1.0))

func sparks(a: float) -> void:
	if jackpot_parts.has("sparks"): jackpot_parts.sparks.modulate.a = a

## Light within 115 % of the card's width: the halo is a round light of radius 0.62 * width (12 % beyond each edge).
func halo(a: float) -> void:
	if jackpot_parts.has("halo"): jackpot_parts.halo.modulate = Kit.with_alpha(Palette.BRASS_HI, 0.5 * a)

func eye_glow(a: float) -> void:
	if jackpot_parts.has("eye"): jackpot_parts.eye.modulate = Kit.with_alpha(Kit.el_color(el), 0.85 * a)

func demon_pose(t: float) -> void:
	if demon == null: return
	var amp := DEMON_BOB
	demon.position.y = demon_rect.position.y + sin(t * TAU / DEMON_PERIOD) * amp * 0.5
	if demon_trail != null:
		demon_trail.position.y = demon_rect.position.y + sin((t - TRAIL_LAG) * TAU / DEMON_PERIOD) * amp * 0.75
		demon_trail.position.x = demon_rect.position.x + sin((t - TRAIL_LAG) * TAU / DEMON_PERIOD + 0.6) * 4.0

func shafts_level(i: int, v: float) -> void:
	if i < shaft_nodes.size(): shaft_nodes[i].modulate = Kit.with_alpha(Kit.el_color(el), 0.16 * v * _shaft_gain)

func motes_time(t: float) -> void:
	_motes_t = t
	if motes != null: motes.queue_redraw()

func reveal(i: int, a: float) -> void:
	card_nodes[i].face_up = a >= 0.5

# 5.8: the order of picking. press 0.06 -> mark flies 0.3 -> socket flash, burst -> others fall 0.15 -> 0.46 s
func confirm_press(i: int) -> void:
	var cd = card_nodes[i]
	cd.scale = Vector2.ONE * 0.97

func confirm_fly(i: int, t: float) -> void:
	var cd = card_nodes[i]
	if _fly == null:
		var en: String = Grace.emblem_name(String(cards[i].get("element", el)), String(cards[i].get("kind", "new")))
		_fly = Grace.art_rect(self, en, Rect2(Vector2.ZERO, Vector2(64, 64)))
		if _fly == null: return
	var from: Vector2 = cd.emblem_center()
	var to: Vector2 = band_node.target_for(cards[i])
	var arc := Vector2(0, -90.0 * sin(PI * clampf(t, 0.0, 1.0)))
	_fly.position = from.lerp(to, t) + arc - _fly.size * 0.5
	_fly.scale = Vector2.ONE * lerpf(1.0, 0.55, t)

func confirm_burst(a: float) -> void:
	if band_node != null: band_node.pulse = a

func confirm_drop_others(i: int, t: float) -> void:
	for k in card_nodes.size():
		if k == i: continue
		card_nodes[k].position.y += 0.0
		card_nodes[k].modulate.a = 1.0 - t

# ============================================================ base.gd interface
func _intro() -> float:
	var secs: float = Grace.intro_seconds(Grace.intro_kind(contract))
	if cards_root != null:
		cards_root.modulate.a = 0.0
		track(create_tween()).tween_property(cards_root, "modulate:a", 1.0, minf(0.3, secs))
	return secs

func _settle_all() -> void:
	if cards_root != null: cards_root.modulate.a = 1.0
	_apply_tones()

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

func _confirm_anim(index: int) -> float:
	var cd = card_nodes[index]
	confirm_press(index)
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(v): confirm_fly(index, v), 0.0, 1.0, 0.3).set_delay(0.06)
	tw.tween_method(func(v): confirm_drop_others(index, v), 0.0, 1.0, 0.15).set_delay(0.36)
	tw.tween_method(func(v): confirm_burst(v), 1.0, 0.0, 0.1).set_delay(0.36)
	cd.leak = 1.0
	return confirm_len
