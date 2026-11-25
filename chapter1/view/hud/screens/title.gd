extends Control
## The first screen and the witch choice in one: "three doors" (docs/screens/title/BRIEF-20261120.ko.md 3.2, user pick U-69). One public entry, apply(contract),
## and six signals (T8 3). Three witches stand full length side by side, each in a door of her own world; the focused door is 960 px wide, the other two 480.
## Moving the focus slides the door widths (0.30 s), the figure steps 0.66 -> 0.74 and lights up, her text bundle comes in. Start: the other doors go black,
## the chosen door opens to the whole screen, the camera moves 1.00 -> 1.08 on face and chest, the element bursts (placeholder: Parts.Burst; the real ones
## belong to vfx-feel), a flash, an iris closes. 1.20 s. Motion off: no flash, no zoom, 0.40 s fade.
## It reads only the contract (chapter1/view/contracts/title_contract.gd makes it from the app's state) and says what happened through the signals; the host
## (chapter_hud.gd) hands them on. Every animation is a pure function of `clock` and a few start stamps, so a captured frame at a time t is the same picture
## every time (advance_to). Layout numbers are 1080p pixels (BRIEF), converted with Parts.px.
## Time: _process adds the frame delta; it stands still while the screen is not interactive (a window lies over it) or not visible, except during the intro, which plays on under a window.
## Input (Input48 kept): during the intro any key skips (the picture opens in 0.15 s) and picking is locked 0.25 s after it; Space is never a confirm key; a
## second key during the confirm jumps to its 1.0 s point. Keys the screen uses end with set_input_as_handled (the app's Q = potion, E = rite never see them).
## Not on this screen on purpose: settings and quit (the Esc window has them), the contract demon (director decision, T13), a costume knob (no costume screen).
const CONTRACT_VERSION := 1
const Parts = preload("res://chapter1/view/hud/title_parts.gd")
const Block = preload("res://chapter1/view/hud/title_block.gd")
const Kit = preload("res://chapter1/view/hud/grace_draw.gd")
const Palette = preload("res://chapter1/view/hud/palette.gd")
const Motion = preload("res://chapter1/view/hud/ui_motion.gd")
const Loc = preload("res://chapter1/view/loc.gd")

signal start(skill_ref: String)
signal witch_focused(index: int)
signal stash
signal skill_tree(character_ref: String)
signal menu
signal ready_for_pick   ## the intro settled (the host ignores it; the capture tool waits for it)

const LOCK := Motion.PICK_LOCK
const HOVER_DWELL := 0.12
const FOCUS_ANIM := 0.30
const AXIS := [0.36, 0.70, 0.68]            ## where the figure's vertical axis stands inside the focused door (BRIEF 3.2.1)
const TEXT_X := [470.0, 520.0, 1000.0]      ## x of the text column when witch j has the focus (px)
const TEXT_W := 420.0                       ## the column's width (code units)
const S_FOCUS := 0.74
const S_DIM := 0.66
const FOOT_FOCUS := 1060.0
const FOOT_DIM := 1050.0
const BOTTOM := 1024.0
## The name plaque: 360 wide, its words fitted into 58 % of that (the clasps at both ends take the rest; at 290 / 76 % the words ran into them).
const BLOCK := {"width": TEXT_W, "plaque": 360.0, "plaque_fit": 0.58, "note_h": 150.0, "hint": true}
const MENU_BUTTON := Vector2(44.0, 44.0)

var contract := {}
var cards: Array = []     ## the three witches of the contract
var focus_index := -1
var state := "idle"       ## idle, intro, ready, confirm, done
var clock := 0.0
var events: Array = []
var reduce_motion := false
var capture_mode := false  ## set by the capture tool: the real mouse pointer must not move the focus while a picture is taken
var motion := 1.0
var manual := false
var intro_len := 2.5
var confirm_len := 1.2
var unlock_t := 0.0
var unlock_abs := 0.0
var intro_t0 := 0.0
var intro_skipped := false
var focus_t0 := -100.0
var prev_focus := -1
var confirm_t0 := -100.0
var ui_focus := 0         ## 0 start, 1 tree, 2 stash
var hover_idx := -1
var hover_t0 := 0.0
var shift_bonus := 0.0
var portraits: Array = []
var blocks: Array = []    ## per witch {root, start, tree, stash, tree_on, height}
var marker: Control
var menu_button: Control
var stage: Control
var chrome: Control
var doors: Array = []
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
var save_word: Label
var save_note: Label
var _marks := {}
var _built := false
var _interactive := true
var _initial_focus := 0
var _last_motion_on := true
var _dx: Array = [0.0, 0.0, 0.0]
var _dw: Array = [640.0, 640.0, 640.0]
var _portrait_started := false
var _last_rect: Array = [Rect2(), Rect2(), Rect2()]
var _pm: Array = [-1.0, -1.0, -1.0]
var _pfx: Array = [false, false, false]
var _pi: Array = [-1.0, -1.0, -1.0]   ## portrait-clock time at which each portrait's entrance began

## The capture tools build the screen this way (a script path alone is not enough: the contract has to be applied).
static func make(c: Dictionary) -> Control:
	var s: Control = load("res://chapter1/view/hud/screens/title.gd").new()
	s.apply(c)
	return s

# ============================================================ the one entry

## First call: builds the screen (the focus comes from the contract). Later calls: only the text bundles, the name tags and the corner text are built again;
## the focus, the state, the clock and the portraits stay as they are.
func apply(c: Dictionary) -> void:
	if int(c.get("contract_version", -1)) != CONTRACT_VERSION:
		push_error("title: contract_version %s, the screen takes %d" % [str(c.get("contract_version")), CONTRACT_VERSION])
		return
	contract = c.duplicate(true)
	cards = contract.get("witches", [])
	var motion_on := bool(contract.get("motion_on", true))
	if not _built or motion_on != _last_motion_on:
		reduce_motion = not motion_on
	_last_motion_on = motion_on
	if not _built:
		name = "TitleScreen"
		size = Kit.SIZE
		position = Vector2.ZERO
		mouse_filter = Control.MOUSE_FILTER_PASS
		_initial_focus = clampi(int(contract.get("focus_index", 0)), 0, maxi(cards.size() - 1, 0))
		focus_index = _initial_focus
		_build_fixed()
		_build_texts()
		_built = true
		_sync_process()
		_update()
		_drive_portraits()
	else:
		_build_texts()
		_update()

# ============================================================ public calls

func play_intro() -> void:
	state = "intro"
	intro_t0 = clock
	intro_skipped = false
	events.clear()
	_marks.clear()
	_portrait_started = false
	_pi = [-1.0, -1.0, -1.0]
	intro_len = 0.12 if reduce_motion else 2.5
	unlock_t = intro_len + LOCK
	unlock_abs = intro_t0 + unlock_t
	prev_focus = -1
	focus_t0 = clock - 100.0
	ui_focus = 0
	mark("title_intro")
	mark("focus_%d" % focus_index)

## The settled picture at once (no intro): the state `ready` with the focus as it is. From confirm or done it opens the doors again (the app refused the start).
func show_settled() -> void:
	state = "ready"
	intro_skipped = true
	_portrait_started = true
	_marks.clear()
	confirm_t0 = -100.0
	prev_focus = -1
	focus_t0 = clock - 100.0
	unlock_abs = clock + LOCK
	ui_focus = 0
	_update()

func set_interactive(on: bool) -> void:
	_interactive = on
	mouse_filter = Control.MOUSE_FILTER_PASS if on else Control.MOUSE_FILTER_IGNORE
	if not on:
		hover_idx = -1
		if marker != null:
			marker.visible = false
	_sync_process()

func is_settled() -> bool:
	return state == "ready"

func focused_index() -> int:
	return focus_index

func set_motion(scale_: float) -> void:
	motion = maxf(scale_, 0.0)
	reduce_motion = motion <= 0.0

func skip_intro() -> void:
	if state != "intro":
		return
	var e := clock - intro_t0
	var target := intro_len - 0.15
	var d := 0.0
	if e < target:
		d = target - e
		intro_t0 -= d
	intro_skipped = true
	shift_bonus += d
	unlock_abs = clock + LOCK
	mark("intro_skipped")

func skip() -> void:
	if state == "intro":
		skip_intro()
	elif state == "confirm":
		var ce := clock - confirm_t0
		var jump := 1.0 if confirm_len > 1.0 else confirm_len * 0.8
		if ce < jump:
			confirm_t0 -= jump - ce
			mark("confirm_skipped")

func set_focus(i: int) -> void:
	if i == focus_index or i < 0 or i >= cards.size():
		return
	if state == "confirm" or state == "done":
		return
	prev_focus = focus_index
	focus_index = i
	focus_t0 = clock
	mark("focus_%d" % i)
	events.append({"t": snappedf(clock - intro_t0, 0.001), "e": "witch_focus(%s)" % String(Parts.ELEM[i])})
	_pm = [-1.0, -1.0, -1.0]
	_apply_names()
	witch_focused.emit(i)

func move_focus(step: int) -> void:
	set_focus(posmod(maxi(focus_index, 0) + step, cards.size()))

## The witch the contract started on (a capture tool moves the focus away and back to this one).
func best_index() -> int:
	return _initial_focus

func try_pick(i: int) -> bool:
	if state != "ready" or clock < unlock_abs or i != focus_index or i < 0:
		mark("pick_rejected")
		return false
	state = "confirm"
	confirm_t0 = clock
	confirm_len = 0.4 if reduce_motion else 1.2
	_marks.clear()
	mark("pick_%d" % i)
	events.append({"t": snappedf(clock - intro_t0, 0.001), "e": "witch_confirm(%s)" % String(Parts.ELEM[i])})
	return true

func send(action: String) -> void:
	match action:
		"focus_next": move_focus(1)
		"focus_prev": move_focus(-1)
		"confirm": try_pick(focus_index)
		"skip": skip()
		_: pass

func advance_to(t: float) -> void:
	manual = true
	clock = t
	_tick()

func prepare_still(_stage: String) -> void:
	pass

func mark(name_: String) -> void:
	events.append({"t": snappedf(clock - intro_t0, 0.001), "e": name_})

func mark_once(name_: String) -> void:
	if _marks.has(name_):
		return
	_marks[name_] = true
	mark(name_)

func pretty_events() -> Array:
	return events

# ============================================================ time

func _process(delta: float) -> void:
	if manual or not _runs():
		return
	clock += delta
	_tick()

## The clock runs while the screen takes input, and also while the intro plays under a window (a refused-save notice opens in the very first frame): a frozen
## intro would leave the screen black behind the notice. A window never has to wait for the doors: the intro is short and only the input is shut out.
func _runs() -> bool:
	return _interactive or state == "intro" or state == "idle"

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_ENTER_TREE:
		_sync_process()

func _sync_process() -> void:
	set_process(is_visible_in_tree())   # _process itself stands still when the clock is not to run (_runs)

func _tick() -> void:
	match state:
		"intro":
			if clock - intro_t0 >= intro_len:
				state = "ready"
				mark("settled")
				ready_for_pick.emit()
		"confirm":
			if clock - confirm_t0 >= confirm_len:
				state = "done"
				mark("confirm_done")
				if focus_index >= 0 and focus_index < cards.size():
					start.emit(String(cards[focus_index].start_ref))
	if hover_idx >= 0 and hover_idx != focus_index and state == "ready" and clock - hover_t0 >= HOVER_DWELL:
		set_focus(hover_idx)
	_fix_ui_focus()
	_update()
	_drive_portraits()
	if marker != null:
		var target: Control = _ui_control(ui_focus)
		if state == "ready" and _interactive and target != null and target.is_visible_in_tree():
			marker.call("follow", target)
		else:
			marker.visible = false

func _drive_portraits() -> void:
	for p in portraits:
		(p as Node2D).call("advance_to", clock + shift_bonus)

func _e() -> float:
	match state:
		"idle": return 0.0
		"intro": return clock - intro_t0
	return 1000.0

func _ce() -> float:
	return clock - confirm_t0 if state == "confirm" or state == "done" else -1.0

func block_alpha(i: int) -> float:
	var fe := clock - focus_t0
	if i == focus_index:
		return Parts.ramp(fe, 0.20, 0.40)
	if i == prev_focus:
		return 1.0 - Parts.ramp(fe, 0.0, 0.08)
	return 0.0

## 0..1 how much witch i is "the focus" right now (eased over FOCUS_ANIM); the old one goes the other way.
func focus_amount(i: int) -> float:
	var p := Parts.ease_out((clock - focus_t0) / FOCUS_ANIM)
	if i == focus_index:
		return p
	if i == prev_focus:
		return 1.0 - p
	return 0.0

# ============================================================ build

## The parts that never change after the first apply: doors with their far backdrops, portraits and seams, the burst and the closers, the logo.
func _build_fixed() -> void:
	var backdrop := Parts.rect_node(self, Rect2(Vector2.ZERO, size), Parts.BACKDROP)
	backdrop.name = "Backdrop"
	stage = Control.new()
	stage.name = "Stage"
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
		far.modulate = Parts.grey(0.45)
		far.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(far)
		var p := Parts.make_portrait(i)
		content.add_child(p)
		portraits.append(p)
		var edge := TextureRect.new()
		edge.texture = tex
		edge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		edge.stretch_mode = TextureRect.STRETCH_SCALE
		edge.modulate = Parts.grey(0.45)
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		edge.z_index = 9  ## above the portrait entrance (z 7), so the darkness never shows a hard-edged box
		edge.material = Parts.edge_cover_material(0.0, 100.0, 10.0, 100.0)
		content.add_child(edge)
		var glow := TextureRect.new()
		glow.texture = Kit.glow()
		glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glow.stretch_mode = TextureRect.STRETCH_SCALE
		glow.material = Parts.additive()
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(glow)
		var ground := Parts.vgrad(content, Rect2(0, size.y * 0.45, 4.0, size.y * 0.55), Parts.black(0.0), Parts.black(0.62))
		ground.name = "Ground"
		var gray := ColorRect.new()
		gray.color = Kit.with_alpha(Parts.DOOR_GRAY, 0.0)
		gray.mouse_filter = Control.MOUSE_FILTER_IGNORE
		door.add_child(gray)
		var rise := Parts.Rise.new()  ## the entrance darkness over the whole door
		rise.z_index = 9
		content.add_child(rise)
		doors.append({"door": door, "content": content, "far": far, "edge": edge, "glow": glow, "gray": gray, "ground": ground, "rise": rise})
	for k in 2:
		seams.append(Parts.hband(stage, Rect2(0, 0, Parts.px(48.0), size.y), Parts.black(0.85)))
	burst = Parts.Burst.new()
	burst.size = size
	burst.unit = 1.7
	stage.add_child(burst)
	# a soft shade behind each text column (the leather and the parchment carry the rest; the figure behind stays readable)
	for i in 3:
		var sh := TextureRect.new()
		sh.texture = Kit.glow()
		sh.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sh.stretch_mode = TextureRect.STRETCH_SCALE
		sh.self_modulate = Kit.with_alpha(Palette.SURFACE, 0.78)
		sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sh.size = Vector2(Parts.px(TEXT_W * 1.2 + 360.0), Parts.px(1000.0))
		sh.position = Vector2(Parts.px(float(TEXT_X[i]) + TEXT_W * 0.6) - sh.size.x * 0.5, Parts.px(40.0))
		sh.modulate.a = 0.0
		add_child(sh)
		shades.append(sh)
	chrome = Control.new()
	chrome.name = "TitleChrome"
	chrome.size = size
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(chrome)
	## the dark under the logo and the corner text: wider than the screen on the left, so its feathered ends are the right one only (the proposal's cut off at x = 700)
	top_shade = Parts.vgrad(self, Rect2(-Parts.px(300.0), 0, Parts.px(1000.0), Parts.px(190.0)), Parts.black(0.74), Parts.black(0.0))
	top_shade.material = Parts.feather_tinted(0.3, 0.0, 0.0)
	logo_font = FontVariation.new()
	logo_font.base_font = Loc.font("heading")
	logo = Label.new()
	logo.name = "Logo"
	logo.add_theme_font_override("font", logo_font)
	logo.add_theme_color_override("font_color", Palette.BRASS)
	logo.add_theme_color_override("font_shadow_color", Parts.black(0.8))
	logo.add_theme_constant_override("shadow_offset_y", 2)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	marker = Parts.Marker.new()
	add_child(marker)
	flash = ColorRect.new()
	flash.size = size
	flash.color = Color.TRANSPARENT
	flash.material = Parts.additive()
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 25
	add_child(flash)
	dim = ColorRect.new()
	dim.size = size
	dim.color = Color.TRANSPARENT
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.z_index = 28
	add_child(dim)
	iris = Parts.Iris.new()
	iris.size = size
	add_child(iris)
	for ch in get_children():  ## everything above the stage sits over the edge covers (z 9)
		if ch != backdrop and ch != stage and ch is CanvasItem and (ch as CanvasItem).z_index == 0:
			(ch as CanvasItem).z_index = 10

## The parts that carry words: the text bundle of each witch, the name tags under the doors, the small texts in the corners. Built again by every later apply.
func _build_texts() -> void:
	for ch in chrome.get_children():
		chrome.remove_child(ch)
		ch.queue_free()
	blocks.clear()
	tags.clear()
	for i in 3:
		var b: Dictionary = Block.build_block(i, cards[i], contract, BLOCK)
		(b.root as Control).name = "Block%d" % i
		chrome.add_child(b.root)
		blocks.append(b)
		tags.append(_make_tag(i))
	_wire_blocks()
	_apply_names()
	_build_corner()
	logo.text = Loc.t("title.logo")

## The small name tag under a door that is not in focus: title and level (+ points), centred on x = 0 of its own container.
func _make_tag(i: int) -> Control:
	var w: Dictionary = cards[i]
	var root := Control.new()
	root.name = "Tag%d" % i
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var width := Parts.px(440.0)
	var t: Label = Kit.lbl(root, String(w.title), Vector2(-width * 0.5, 0), width, Parts.fs(26.0), Palette.INK_DIM, "heading", HORIZONTAL_ALIGNMENT_CENTER, false, true)
	var y := t.size.y + Parts.px(4.0)
	var lvl: Variant = w.get("level", null)
	if lvl is Dictionary:
		var lpx := Parts.fs(20.0)
		var txt := "%s %d" % [Loc.t("title.level"), int(lvl.value)]
		var lw: float = Loc.font("number").get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, lpx).x
		var total := ceilf(lw) + 2.0
		var pts := int(lvl.points)
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
	chrome.add_child(root)
	return root

## Top left under the logo: the save word and the status text (K9, K14). Top right: the small menu button (the mouse way to Esc).
func _build_corner() -> void:
	var save_key := "title.save." + String(contract.get("save", "off"))
	var word_px := Parts.fs(22.0)
	var note_px := Parts.fs(20.0)
	var x := Parts.px(44.0)
	var y := Parts.px(86.0)
	save_word = Kit.lbl(chrome, Loc.t(save_key), Vector2(x, y), Parts.px(560.0), word_px, Palette.BRASS if contract.get("save", "off") != "on" else Palette.INK_DIM, "bold", HORIZONTAL_ALIGNMENT_LEFT, false, true)
	save_word.name = "SaveWord"
	var note_text := String(contract.get("note", ""))
	var word_text := Loc.t(save_key)
	if note_text.begins_with(word_text):   # "검증 실행 · 저장 비활성" under the word "검증 실행" said it twice
		note_text = note_text.trim_prefix(word_text).lstrip(" ·").strip_edges()
	save_note = null
	if note_text != "":
		save_note = Kit.lbl(chrome, note_text, Vector2(x, y + save_word.size.y + Parts.px(2.0)), Parts.px(560.0), note_px, Palette.INK_DIM, "body", HORIZONTAL_ALIGNMENT_LEFT, true, true)
		save_note.name = "SaveNote"
	var mb := Parts.CornerMenuButton.new()
	mb.name = "TitleMenuButton"
	mb.setup(Loc.t("title.menu_button"), MENU_BUTTON)
	mb.position = Vector2(size.x - MENU_BUTTON.x - Parts.px(32.0), Parts.px(28.0))
	mb.connect("pressed", func(): if _interactive and state == "ready": menu.emit())
	chrome.add_child(mb)
	menu_button = mb

## The nodes the capture and check tools look for by name belong to the witch in focus: her three controls are TitleStart, TitleTree and TitleStash, the other
## witches' carry the element as a suffix (so a search by name finds the one that is on show).
func _apply_names() -> void:
	for i in blocks.size():
		var suffix := "" if i == focus_index else "_" + String(Parts.ELEM[i])
		for pair in [["start", "TitleStart"], ["tree", "TitleTree"], ["stash", "TitleStash"]]:
			var n: Variant = (blocks[i] as Dictionary).get(pair[0], null)
			if n != null:
				(n as Control).name = String(pair[1]) + suffix

func _wire_blocks() -> void:
	for i in blocks.size():
		var b: Dictionary = blocks[i]
		(b.start as Control).connect("pressed", func(_a = null): if _interactive and i == focus_index: try_pick(i))
		if b.tree != null and bool(b.tree_on):
			(b.tree as Control).connect("pressed", func(_a = null): if _interactive and state == "ready" and i == focus_index: skill_tree.emit(String(cards[i].character_ref)))
		if b.stash != null:
			(b.stash as Control).connect("pressed", func(_a = null): if _interactive and state == "ready" and i == focus_index: stash.emit())

# ============================================================ geometry

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

## Checks of BRIEF 1.8 lines 3 and 4 on the settled geometry of every focus; returns {ok, rows[]} (the smoke test prints it).
func layout_report() -> Dictionary:
	var rows: Array = []
	var ok := true
	for j in 3:
		var g: Array = settled_geometry(j)
		if g.is_empty():
			continue
		var f: Dictionary = g[j]
		var face_ok := float(f.face.y) < 324.0
		var pelvis_ok: bool = float(f.pelvis_x) < 840.0 or float(f.pelvis_x) > 1080.0
		var full_face: bool = float(f.face.y) > 0.0
		var cut_ok: bool = float(f.get("cut_frac", 1.0)) >= 0.80 or float(f.get("cut_frac", 1.0)) <= 0.0 or float(f.get("cut_frac", 1.0)) > 1.0
		rows.append({"focus": j, "face": [snappedf(f.face.x, 0.1), snappedf(f.face.y, 0.1)], "pelvis_x": snappedf(f.pelvis_x, 0.1), "face_y_lt_324": face_ok,
			"pelvis_outside_840_1080": pelvis_ok, "face_on_screen": full_face, "cut_ok": cut_ok, "scale_px": f.scale})
		ok = ok and face_ok and pelvis_ok and full_face and cut_ok
	return {"ok": ok, "rows": rows}

func _hover_at(pos: Vector2) -> int:
	var x := pos.x / Parts.K
	for i in 3:
		if x >= float(_dx[i]) and x < float(_dx[i]) + float(_dw[i]):
			return i
	return -1

# ============================================================ the picture

func _update() -> void:
	if doors.is_empty():
		return
	var e := _e()
	var ce := _ce()
	var in_confirm := ce >= 0.0
	var moving := not reduce_motion
	var o := 1.0
	if state == "idle" or state == "intro":
		o = Parts.smooth(Parts.ramp(e, 1.3, 1.6))
	# the chosen portrait's own entrance (the light comes up, 1.1 s) starts when the door has begun to open; the door's Rise does the darkness
	if state != "idle" and not _portrait_started and focus_index >= 0 and (e >= 1.3 or intro_skipped or reduce_motion):
		_portrait_started = true
		if not intro_skipped and not reduce_motion:
			(portraits[focus_index] as Node2D).call("advance_to", clock + shift_bonus)
			(portraits[focus_index] as Node2D).call("play_intro")
			_pi[focus_index] = clock + shift_bonus
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
	if in_confirm and moving:
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
		var far_k := 1.0 - 0.5 * c if i == focus_index else 1.0  ## the opened door darkens its far layer so the burst carries it
		far.modulate = Parts.grey(0.45 * far_k)
		edge.modulate = far.modulate
		var br := lerpf(0.30, 1.0, float(fv[i]))
		(d.content as Control).modulate = Parts.grey(br)
		var ra := 0.0
		if float(_pi[i]) >= 0.0 and state != "idle":
			ra = 1.0 - Parts.smooth(Parts.ramp(clock + shift_bonus - float(_pi[i]), 0.0, 1.1))
		(d.rise as Control).size = door.size
		(d.rise as Control).set("amount", ra)
		(d.gray as ColorRect).size = door.size
		(d.ground as Control).size.x = door.size.x
		(d.gray as ColorRect).color = Kit.with_alpha(Parts.DOOR_GRAY, 0.55 * (1.0 - float(fv[i])))
		var glow_a := 0.0
		var fe := clock - focus_t0
		if i == focus_index:
			glow_a = Parts.ramp(fe, 0.12, 0.40) * o
		elif i == prev_focus:
			glow_a = 1.0 - Parts.ramp(fe, 0.0, 0.2)
		var glow: TextureRect = d.glow
		glow.modulate = Kit.with_alpha(Parts.el_color(i), 0.6 * glow_a)
		glow.size = Vector2(Parts.px(900.0), Parts.px(300.0))
		glow.position = Vector2(Parts.px(local_x) - glow.size.x * 0.5, Parts.px(float(g.foot)) - glow.size.y * 0.5)
		# door appearance (intro) and the black of the doors that were not chosen (confirm)
		var appear := Parts.ramp(e, 1.0 + 0.08 * float(i), 1.2 + 0.08 * float(i))
		var k := 1.0
		if in_confirm and i != focus_index and moving:
			k = 1.0 - Parts.ramp(ce, 0.0, 0.12)
		door.modulate = Parts.grey(k, appear)
		# portrait motion and element effects: only the figure in focus moves
		var want := 0.0
		if i == focus_index and state != "idle":
			want = motion if moving else 0.0
			if in_confirm and moving:
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
	# chrome (text column) alpha
	var chrome_a := 1.0
	if state == "idle" or state == "intro":
		chrome_a = Parts.ramp(e, 2.2, 2.5)
	if in_confirm:
		chrome_a = 1.0 - Parts.ramp(ce, 0.0, 0.15)
	for i in blocks.size():
		var b: Dictionary = blocks[i]
		var a := block_alpha(i) * chrome_a if state != "idle" else 0.0
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
	if menu_button != null:
		menu_button.visible = chrome_a > 0.01 and state != "idle"
		menu_button.modulate.a = chrome_a
	if save_word != null:
		save_word.modulate.a = Parts.ramp(e, 1.8, 2.3) if (state == "idle" or state == "intro") else chrome_a
		if save_note != null:
			save_note.modulate.a = save_word.modulate.a
	if focus_index >= 0 and focus_index < blocks.size():
		var sb: Control = blocks[focus_index].start
		sb.set("flash", (1.0 - Parts.ramp(ce, 0.0, 0.06)) if in_confirm else 0.0)
	_logo(e, ce)
	(top_shade as Control).modulate.a = chrome_a
	# effects of the confirm
	flash.color = Color.TRANSPARENT
	burst.set("t", -1.0)
	stage.scale = Vector2.ONE
	stage.position = Vector2.ZERO
	dim.color = Color.TRANSPARENT
	iris.set("amount", 0.0)
	if in_confirm and focus_index >= 0:
		var g2: Dictionary = focus_geo
		if moving:
			var z := 1.0 + 0.08 * Parts.smooth(Parts.ramp(ce, 0.10, 0.50))
			stage.pivot_offset = Vector2(Parts.px(float(g2.axis_x)), Parts.px(float(g2.face.y) + 140.0))
			stage.scale = Vector2(z, z)
			if bool(contract.get("motion_on", true)) and ce >= 0.30 and ce < 0.50:
				stage.position = Vector2(sin(ce * 130.0) * 5.0, cos(ce * 110.0) * 5.0)
			var sym: Vector2 = Parts.SYMBOL[focus_index]
			burst.set("element", String(Parts.ELEM[focus_index]))
			burst.set("center", Vector2(Parts.px(float(g2.axis_x) + (sym.x - 512.0) * float(g2.scale)), Parts.px(float(g2.foot) - (Parts.FOOT_Y - sym.y) * float(g2.scale))))
			burst.set("t", ce - 0.30 if ce >= 0.30 else -1.0)
			if ce >= 0.30:
				mark_once("burst_start")
				var fa := 0.0
				if ce < 0.36:
					fa = 0.34 * Parts.ramp(ce, 0.30, 0.36)
				else:
					fa = 0.34 * (1.0 - Parts.ramp(ce, 0.36, 0.56))
				flash.color = Parts.scaled(Parts.el_color(focus_index), fa)
			iris.set("amount", Parts.ramp(ce, 0.60, 1.20))
		else:
			dim.color = Parts.black(Parts.ramp(ce, 0.0, 0.4))

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
	var wpx: float = Loc.font("heading").get_string_size(logo.text, HORIZONTAL_ALIGNMENT_LEFT, -1, code_px).x + float(logo.text.length()) * float(logo_font.spacing_glyph)
	var h := Kit.line_height(code_px, "heading")
	var big_pos := Vector2(size.x * 0.5 - wpx * 0.5, Parts.px(470.0) - h * 0.5)
	var small_pos := Vector2(Parts.px(40.0), Parts.px(24.0))
	logo.position = big_pos.lerp(small_pos, k)
	logo.size = Vector2(wpx + 8.0, h + 4.0)
	logo.modulate.a = a

# ============================================================ input

func _ui_control(code: int) -> Control:
	if focus_index < 0 or focus_index >= blocks.size():
		return null
	var b: Dictionary = blocks[focus_index]
	match code:
		0: return b.start
		1: return b.tree
		2: return b.stash
	return null

## The controls the Tab chain walks for the witch in focus: start, then the tree (when she has one to open), then the gear.
func _focus_order() -> Array:
	var order: Array = [0]
	if focus_index < 0 or focus_index >= blocks.size():
		return order
	var b: Dictionary = blocks[focus_index]
	if b.tree != null and bool(b.tree_on):
		order.append(1)
	if b.stash != null:
		order.append(2)
	return order

func _fix_ui_focus() -> void:
	if not _focus_order().has(ui_focus):
		ui_focus = 0

func _ui_cycle(step: int) -> void:
	var order := _focus_order()
	var at := order.find(ui_focus)
	ui_focus = int(order[posmod((at if at >= 0 else 0) + step, order.size())])

func _activate() -> void:
	match ui_focus:
		0: try_pick(focus_index)
		1:
			if focus_index >= 0 and focus_index < cards.size():
				skill_tree.emit(String(cards[focus_index].character_ref))
		2: stash.emit()

## The keys the screen takes in the `ready` state. true = the key was used (the caller ends it with set_input_as_handled).
func _on_key(code: int, shift: bool) -> bool:
	match code:
		KEY_Q, KEY_LEFT: set_focus(posmod(focus_index - 1, cards.size()))
		KEY_E, KEY_RIGHT: set_focus(posmod(focus_index + 1, cards.size()))
		KEY_1: set_focus(0)
		KEY_2: set_focus(1)
		KEY_3: set_focus(2)
		KEY_TAB: _ui_cycle(-1 if shift else 1)
		KEY_DOWN: _ui_cycle(1)
		KEY_UP: _ui_cycle(-1)
		KEY_ESCAPE: menu.emit()
		KEY_ENTER, KEY_KP_ENTER: _activate()
		_: return false  ## Space and everything else: nothing (Input48)
	return true

const SKIP_KEYS := [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_Q, KEY_E, KEY_LEFT, KEY_RIGHT, KEY_TAB, KEY_1, KEY_2, KEY_3]

## A pressed key or pad button. Returns true when the screen used it.
func _press(code: int, shift: bool) -> bool:
	if state == "intro":
		skip_intro()  ## any key skips the intro; only the keys of the list are taken away from the app
		return code in SKIP_KEYS
	if state == "confirm":
		skip()
		return true
	if state != "ready":
		return false
	return _on_key(code, shift)

func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	if not _interactive or not is_visible_in_tree():
		return
	if _press(e.keycode, e.shift_pressed):
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()

## Pad and other non-key events: the same UI actions the keys have (ui_left / ui_right / ui_up / ui_down / ui_accept / ui_cancel). A key is never read here
## (Space is bound to ui_accept by default; the key path above is the only one for the keyboard).
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey or not _interactive or not is_visible_in_tree():
		return
	if not (e is InputEventJoypadButton or e is InputEventJoypadMotion):
		return
	var code := -1
	if e.is_action_pressed("ui_left"): code = KEY_LEFT
	elif e.is_action_pressed("ui_right"): code = KEY_RIGHT
	elif e.is_action_pressed("ui_up"): code = KEY_UP
	elif e.is_action_pressed("ui_down"): code = KEY_DOWN
	elif e.is_action_pressed("ui_accept"): code = KEY_ENTER
	elif e.is_action_pressed("ui_cancel"): code = KEY_ESCAPE
	if code < 0:
		return
	if _press(code, false):
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()

func _gui_input(e: InputEvent) -> void:
	if not _interactive:
		return
	if e is InputEventMouseMotion:
		if capture_mode:
			return
		var idx := _hover_at((e as InputEventMouseMotion).position)
		if idx != hover_idx:
			hover_idx = idx
			hover_t0 = clock
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if state == "intro":
			skip_intro()
		elif state == "confirm":
			skip()
		elif state == "ready":
			var i := _hover_at((e as InputEventMouseButton).position)
			if i >= 0 and i != focus_index:
				set_focus(i)
