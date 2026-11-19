extends Control
## Harness base of the growth-choice proposals (tests only). One contract in, one signal out: the screen only reads the
## contract and says "chosen(index)" / "reroll_requested". The input rules follow D9 6.2: during the intro only "skip" is
## accepted, picking is locked for 0.25 s after the cards settle, Space is NOT a confirm key.
signal ready_for_pick
signal chosen(index: int)
signal reroll_requested

const Kit = preload("res://chapter1/tests/proposals/growth_choice/kit.gd")
const Parts = preload("res://chapter1/tests/proposals/growth_choice/parts.gd")
const Palette = preload("res://chapter1/view/hud/palette.gd")
const LOCK := 0.25

var contract := {}
var ui := {}
var cards: Array = []
var focus_index := -1
var state := "idle"  ## idle, intro, ready, done
var clock := 0.0
var unlock_abs := 0.0  ## clock value from which a pick is accepted
var unlock_t := 0.0    ## the same, counted from play_intro (the "held time" t_u of D9 6.1)
var intro_start := 0.0
var events: Array = []
var reduce_motion := false
var _tweens: Array = []

func _process(delta: float) -> void:
	clock += delta

func mark(name_: String) -> void:
	events.append({"t": snappedf(clock - intro_start, 0.001), "e": name_})

func track(tw: Tween) -> Tween:
	_tweens.append(tw)
	return tw

func setup(c: Dictionary) -> void:
	contract = c
	ui = c.strings
	cards = c.cards
	size = Kit.SIZE
	position = Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build()

## --- to override ---
func _build() -> void:
	pass

## Builds the intro tweens; returns the time (s) at which the cards are settled (t_c). unlock = t_c + LOCK.
func _intro() -> float:
	return 0.12

func _focus_changed(_old: int, _new: int) -> void:
	pass

## Plays the confirm; returns its duration.
func _confirm_anim(_index: int) -> float:
	return 0.3

func _settle_all() -> void:
	pass

## --- public ---
func play_intro() -> void:
	state = "intro"
	intro_start = clock
	events.clear()
	var t_c := _intro()
	if reduce_motion:
		skip_intro()
		t_c = 0.12
		modulate.a = 0.0
		track(create_tween()).tween_property(self, "modulate:a", 1.0, 0.12)
	unlock_t = t_c + LOCK
	unlock_abs = intro_start + unlock_t
	mark("intro_start")
	var tw := create_tween()
	tw.tween_interval(t_c)
	tw.tween_callback(func():
		if state == "intro":
			state = "ready"
			mark("cards_settled")
			ready_for_pick.emit())

func skip_intro() -> void:
	if state != "intro": return
	for tw in _tweens:
		if tw != null and tw.is_valid():
			tw.pause()
			tw.custom_step(100.0)
	_tweens.clear()
	_settle_all()
	state = "ready"
	unlock_abs = clock + LOCK
	mark("intro_skipped")
	ready_for_pick.emit()

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
		chosen.emit(i))
	return true

func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo): return
	if state == "intro":
		if e.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_1, KEY_2, KEY_3, KEY_SPACE]: skip_intro()
		return
	match e.keycode:
		KEY_1: try_pick(0)
		KEY_2: try_pick(1)
		KEY_3: try_pick(2)
		KEY_LEFT, KEY_A: move_focus(-1)
		KEY_RIGHT, KEY_D: move_focus(1)
		KEY_ENTER, KEY_KP_ENTER: try_pick(maxi(focus_index, 0))
		KEY_R: reroll_requested.emit()
		_: pass  ## Space and everything else: nothing (D9 6.2)

func best_index() -> int:
	var best := 0
	for i in cards.size():
		if Kit.grade_rank(String(cards[i].grade)) > Kit.grade_rank(String(cards[best].grade)): best = i
	return best

func pretty_events() -> Array:
	return events
