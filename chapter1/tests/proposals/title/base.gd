extends Control
## Harness base of the two title / character-select proposals (tests only). One contract in (title_v0.*.json), signals out:
## chosen(index) = start the run with that witch, request(action, index) = open tree / stash / costume / settings / quit.
## The screen only reads the contract and never decides anything.
##
## Time: every animation is a pure function of `clock` and a few start stamps (intro_t0, focus_t0, confirm_t0). _process adds the frame
## delta, advance_to(t) sets the clock by hand (captures, tests). The living portraits are driven the same way (advance_to), so a frame
## at a given t is the same picture every run.
## Calls for the capture tool (BRIEF 4.2): setup(fixture), advance_to(t), send(action), set_motion(scale). The older harness calls
## (play_intro, set_focus, best_index, try_pick, cards, events, unlock_t, reduce_motion, state, ready_for_pick) are kept so that
## chapter1/tests/proposal_shot.gd and proposal_smoke.gd drive this screen without a second tool.
## Input (D9 6.2 / Input48 kept): during the intro any key skips (the picture opens in 0.15 s) and picking is locked 0.25 s after
## it; Space is never a confirm key; a second key during the confirm jumps to its 1.0 s point.
signal ready_for_pick
signal chosen(index: int)
signal request(action: String, index: int)

const Parts = preload("res://chapter1/tests/proposals/title/parts.gd")
const Kit = preload("res://chapter1/tests/proposals/growth_choice/kit.gd")
const Palette = preload("res://chapter1/view/hud/palette.gd")
const Motion = preload("res://chapter1/view/hud/ui_motion.gd")
const LOCK := Motion.PICK_LOCK
const HOVER_DWELL := 0.12
const FOCUS_ANIM := 0.30

var contract := {}
var ui := {}
var cards: Array = []     ## the three witches of the contract (the harness calls them cards)
var profile := {}
var settings := {}
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
var ui_focus := 0         ## 0 start, 1 tree, 2 stash, 3 costume, 4 settings, 5 quit
var hover_idx := -1
var hover_t0 := 0.0
var shift_bonus := 0.0
var portraits: Array = []
var blocks: Array = []    ## per witch {root, start, tree, stash, costume, height}
var marker: Control
var corner_settings: Control
var corner_quit: Control
var _marks := {}

func _process(delta: float) -> void:
	if manual:
		return
	clock += delta
	_tick()

func advance_to(t: float) -> void:
	manual = true
	clock = t
	_tick()

func mark(name_: String) -> void:
	events.append({"t": snappedf(clock - intro_t0, 0.001), "e": name_})

func mark_once(name_: String) -> void:
	if _marks.has(name_):
		return
	_marks[name_] = true
	mark(name_)

func setup(c: Dictionary) -> void:
	contract = c
	ui = c.strings
	cards = c.witches
	profile = c.profile
	settings = c.settings
	size = Kit.SIZE
	position = Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_PASS
	if float(settings.get("motion", 1.0)) <= 0.0:
		reduce_motion = true
	_build()

# ---------------------------------------------------------------- to override

func _build() -> void:
	pass

func _base_intro_len() -> float:
	return 2.5

func _base_confirm_len() -> float:
	return 1.2

func _update() -> void:
	pass

func _on_focus(_old: int, _new: int) -> void:
	pass

func _on_confirm(_i: int) -> void:
	pass

func _on_skip_intro(_shift: float) -> void:
	pass

## Geometry of the settled picture when witch j has the focus (1080p pixels): one dictionary per witch, see a.gd / c.gd.
func settled_geometry(_j: int) -> Array:
	return []

func _hover_at(_pos: Vector2) -> int:
	return -1

func _click_at(_pos: Vector2) -> void:
	pass

func _escape() -> void:
	ui_focus = 5

func prepare_still(_stage: String) -> void:
	pass

func _ui_control(code: int) -> Control:
	if focus_index < 0 or focus_index >= blocks.size():
		return null
	var b: Dictionary = blocks[focus_index]
	match code:
		0: return b.start
		1: return b.tree
		2: return b.stash
		3: return b.costume
		4: return corner_settings
		5: return corner_quit
	return null

# ---------------------------------------------------------------- public

func set_motion(scale_: float) -> void:
	motion = maxf(scale_, 0.0)
	reduce_motion = motion <= 0.0

func play_intro() -> void:
	state = "intro"
	intro_t0 = clock
	intro_skipped = false
	events.clear()
	_marks.clear()
	intro_len = 0.12 if reduce_motion else _base_intro_len()
	unlock_t = intro_len + LOCK
	unlock_abs = intro_t0 + unlock_t
	focus_index = clampi(int(contract.get("focus_index", 0)), 0, cards.size() - 1)
	prev_focus = -1
	focus_t0 = clock - 100.0
	ui_focus = 0
	mark("intro_start")
	mark("focus_%d" % focus_index)

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
	_on_skip_intro(d)
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
	_on_focus(prev_focus, i)

func move_focus(step: int) -> void:
	set_focus(posmod(maxi(focus_index, 0) + step, cards.size()))

func best_index() -> int:
	return clampi(int(contract.get("focus_index", 0)), 0, cards.size() - 1)

func try_pick(i: int) -> bool:
	if state != "ready" or clock < unlock_abs or i != focus_index or i < 0:
		mark("pick_rejected")
		return false
	state = "confirm"
	confirm_t0 = clock
	confirm_len = 0.4 if reduce_motion else _base_confirm_len()
	_marks.clear()
	mark("pick_%d" % i)
	_on_confirm(i)
	return true

func send(action: String) -> void:
	match action:
		"focus_next": move_focus(1)
		"focus_prev": move_focus(-1)
		"confirm": try_pick(focus_index)
		"skip": skip()
		"title_start": _title_start()
		_: pass

func _title_start() -> void:
	pass

# ---------------------------------------------------------------- tick

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
				chosen.emit(focus_index)
	if hover_idx >= 0 and hover_idx != focus_index and state == "ready" and clock - hover_t0 >= HOVER_DWELL:
		set_focus(hover_idx)
	_update()
	_drive_portraits()
	if marker != null:
		var target: Control = _ui_control(ui_focus)
		if state == "ready" and target != null and target.is_visible_in_tree():
			marker.call("follow", target)
		else:
			marker.visible = false

func _drive_portraits() -> void:
	for p in portraits:
		(p as Node2D).call("advance_to", clock + shift_bonus)

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

# ---------------------------------------------------------------- input

func _wire_blocks() -> void:
	for i in blocks.size():
		var b: Dictionary = blocks[i]
		(b.start as Control).connect("pressed", func(_a = null): if i == focus_index: try_pick(i))
		if b.tree != null:
			(b.tree as Control).connect("pressed", func(_a = null): if i == focus_index: request.emit("open_tree", i))
		if b.stash != null:
			(b.stash as Control).connect("pressed", func(_a = null): if i == focus_index: request.emit("open_stash", i))
		if b.costume != null:
			(b.costume as Control).connect("pressed", func(_a = null): if i == focus_index: request.emit("open_costume", i))

func _focus_order() -> Array:
	var order: Array = [0]
	if focus_index < 0:
		return order
	var b: Dictionary = blocks[focus_index]
	for k in [["tree", 1], ["stash", 2], ["costume", 3]]:
		if b[k[0]] != null:
			order.append(k[1])
	return order

func _ui_cycle(step: int) -> void:
	var order := _focus_order()
	var at := order.find(ui_focus)
	ui_focus = int(order[posmod((at if at >= 0 else 0) + step, order.size())])

func _activate() -> void:
	match ui_focus:
		0: try_pick(focus_index)
		1: request.emit("open_tree", focus_index)
		2: request.emit("open_stash", focus_index)
		3: request.emit("open_costume", focus_index)
		4: request.emit("open_settings", focus_index)
		5: request.emit("quit_request", focus_index)

func _on_key(code: int) -> void:
	match code:
		KEY_Q, KEY_LEFT: set_focus(posmod(focus_index - 1, cards.size()))
		KEY_E, KEY_RIGHT: set_focus(posmod(focus_index + 1, cards.size()))
		KEY_1: set_focus(0)
		KEY_2: set_focus(1)
		KEY_3: set_focus(2)
		KEY_TAB, KEY_DOWN: _ui_cycle(1)
		KEY_UP: _ui_cycle(-1)
		KEY_ESCAPE: _escape()
		KEY_ENTER, KEY_KP_ENTER: _activate()
		_: pass  ## Space and everything else: nothing (Input48)

func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	if state == "intro":
		if e.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_Q, KEY_E, KEY_LEFT, KEY_RIGHT, KEY_TAB, KEY_1, KEY_2, KEY_3]:
			skip_intro()
		return
	if state == "confirm":
		skip()
		return
	if state != "ready":
		return
	_on_key(e.keycode)

func _gui_input(e: InputEvent) -> void:
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
			_click_at((e as InputEventMouseButton).position)

func pretty_events() -> Array:
	return events

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
