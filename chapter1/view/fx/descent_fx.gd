extends RefCounted
## The descent's screen (D15 A, D14 4.3-4.4, D24 4.8 / 5-7 / 12.2, A11): the gauge's edge aura, the band and the cut-scene (A11: the demon's own art; the
## parts are view/hud/descent_band.gd and descent_cutscene.gd, this file keeps their timetable), the demon in the sky layer, and the sweep of each element
## (ember_ult.gd / frost_ult.gd / arc_ult.gd in fx/descent/). Nobody speaks on this screen (U-102): the words are the demon's name and the skill's name.
## It only READS the core: descent_view() and the events descent_ready / descent_called / descent_released / descent_book /
## descent_strike / descent_end / orb_vacuum, plus the orbs and the hero's place. It never writes to the core. The two calls that do
## (request_descent, release_descent) are the app's: this file only says "the cut-in is over" through take_release().
##
## A run whose descent is off has no node from this file at all: sync() returns on {"enabled":false} before _build() ever runs.
##
## Budget (D24 10.2): ordinary alpha on the single full-screen control (no additive full-screen layer; storm, flame and flash are
## values of descent_screen.gdshader), no effect light during the cut-in, at most 3 lights in a sweep, at most 800 particles of this
## file in a run (one element's pool is built). Low spec (--chapter1-descent-fx=low): particles 35 %, no light, one streak layer,
## bolts 24. Colours are the element's own; the crimson of an enemy's attack is never used. No speed lines.
##
## The sweep's clock: seconds, advanced by the render delta while the core plays, pulled to the event's `step` when it drifts more
## than 3 frames. A hit-stop (frost break, 0.08 s) pauses only this clock and the particles of this file: never the core's ticks.
##
## Events read (D24 9.4): released {center, area{right_deg,half_w_m,half_h_m}, sweep_ticks, cleared_positions}, book {fragments}, strike
## {phase: impact | firestorm | onset | freeze | pulse | break | bolt | finale, step, center, positions, k, pos, radius_m, big, n, forks, burst},
## end {kills}. The old reach_m / heading of descent_released and the old phases wall / sweep_end are NOT read any more.
## Without an `area` (a core older than D24) the screen rectangle falls back to the data's default numbers.
##
## Settings (variables here; a settings screen and settings.cfg do not exist yet, so the app sets them from launch arguments):
##   cutin_short    the 0.5 s band every time ("짧게만"; no cut-scene)
##   cutscene_mode  "first" (the run's first descent plays the demon's 3 s video: default) / "always" / "off" (--chapter1-descent-cutscene=)
##   reduced_motion no slide, no shake, no flash, no gust (the picture only fades)
##   flash_scale    0 off, 0.5 weak, 1 full: the flash of the gesture, the tint washes, the aura swell, the white flashes, the lights
##   shake_scale    0 off .. 1: the camera impulses
##   numbers_on     the one merged kill number after a sweep
##   low            --chapter1-descent-fx=low
const Palette = preload("res://chapter1/view/hud/palette.gd")
const Loc = preload("res://chapter1/view/loc.gd")
const AssetSlots = preload("res://chapter1/view/assets/asset_slots.gd")
const EmberUlt = preload("res://chapter1/view/fx/descent/ember_ult.gd")
const FrostUlt = preload("res://chapter1/view/fx/descent/frost_ult.gd")
const ArcUlt = preload("res://chapter1/view/fx/descent/arc_ult.gd")
const SCREEN_SHADER = preload("res://chapter1/view/fx/descent_screen.gdshader")
const SIGIL_SHADER = preload("res://chapter1/view/fx/descent_sigil.gdshader")
const DescentBand = preload("res://chapter1/view/hud/descent_band.gd")
const DescentCutscene = preload("res://chapter1/view/hud/descent_cutscene.gd")

const CUTIN_SLOT_PREFIX := "illustration.cutin.descent."
const SKY_SLOT_PREFIX := "illustration.sky.descent."
## The sky layer's demon: illustration.sky.descent.<el>, then the band's own picture (illustration.cutin.descent.<el>, a waist-up 3:2 picture), then the grace screen's
## demon (a full-length figure on a dark ground, the same one per element, upper body only), then the code silhouette.
const GRACE_SLOT_PREFIX := "ui.grace.demon."
const ELEMENT_ID := {"ember": 0.0, "frost": 1.0, "arc": 2.0}
## Where the demon stands in the sky layer (uv x): away from where the effect comes in (rocks from the upper left, wind from the upper right).
const SKY_X := {"ember": 0.72, "frost": 0.28, "arc": 0.5}
## The sweep's tail after its last tick (the scorch of the rocks stays 3 s).
const TAIL := {"ember": 3.2, "frost": 3.0, "arc": 1.3}
const DEFAULT_AREA := {"right_deg": -38.2, "half_w_m": 17.3, "half_h_m": 13.4}

## The band's own clock, in wall seconds while the core stands still (A11 4.2, 12.3.3 as cut to 3 s by U-101). Three shapes:
##   cut-scene (the run's first descent, with the demon's video): dark 0..0.12, the strip opens 0.12..0.30 round the first frame, the video runs from 0.30 for its
##       own length V, then the strip narrows to the band's height (0.18 s), the skill's name stands (0.12 s), the core lets go 0.55 s after the narrowing began
##       (about 3.85 s in all). A key press after the first 0.5 s skips the rest of the video (it goes dark in 0.10 s, then the same narrowing).
##   long band (no video, or the video's first frame did not come in 0.5 s): 0.9 s as before: the release at 0.70
##   short band (every later descent): 0.5 s, the release at 0.389
## The band leaves on the SWEEP's clock after the release (A11 4.2): ember s12..s24, frost s6..s15, lightning s4..s15 (no slide).
const LONG_SECONDS := 0.9
const SHORT_SECONDS := 0.5
const T_RELEASE := 0.70
const T_END := 0.90
const LONG_BAND := {"dark": [0.0, 0.10], "band": [0.06, 0.24], "demon": [0.24, 0.44], "name": [0.38, 0.50], "line": [0.46, 0.56]}
const SHORT_BAND := {"dark": [0.0, 0.06], "band": [0.04, 0.16], "demon": [0.08, 0.22], "name": [0.16, 0.26], "line": [0.22, 0.30]}
const CUT_DARK_END := 0.12
const CUT_OPEN_END := 0.30
const CUT_CLOSE_SECONDS := 0.18
const CUT_NAME_SECONDS := 0.12
const CUT_RELEASE_AFTER := 0.55          ## from the narrowing's start to the release
const CUT_SKIP_LOCK := 0.5               ## no input counts in the first 0.5 s after the call
const CUT_SKIP_FADE := 0.10
const CUT_FRAME_WAIT := 0.5              ## the video's first frame must be on hand by then, else the long band
const BAND_OUT := {"ember": [12.0, 24.0], "frost": [6.0, 15.0], "arc": [4.0, 15.0]}
## The app's hold limit is this much past the video's length (none: this much alone); the picture's own watchdog sits 0.5 s under it.
const HOLD_PAD := 2.5
const WATCHDOG_SECONDS := 2.0

const GROUND_Y := 0.045
const KILL_NUMBER_SIZE := 60      ## A11 6 D2: the end-of-sweep number (code units, 1600 x 900)
const KILL_RISE := 60.0           ## the number's foot stands this far above the hood's top
## A11 5.1: the sign under the hero. Slot fx.descent.sigil.<element> (a picture, when one is chosen) else the shader's own sign.
const SIGIL_SLOT_PREFIX := "fx.descent.sigil."
const SIGIL_SIZE_M := 6.0
const SIGIL_DRAW_SECONDS := 0.30
const SIGIL_FADE_SECONDS := 0.40
const SIGIL_ALPHA_DRAW := 0.55
const SIGIL_ALPHA_SWEEP := 0.45
const SIGIL_SPIN_DEG := 20.0
const FLIGHT_ORBS := 64
const FLIGHT_PUFFS := 32
const ORB_COLOR := Color("8fe3c0")
const MAX_LIGHTS := 3
const MAX_PARTICLES := 800
const HITSTOP_SECONDS := 0.08
const DEMON_IN := 0.35
const DEMON_OUT := 0.4

var cutin_short := false
var cutscene_mode := "first"
## QA only (descent_fx_shots.gd --fx-off): everything this file draws is hidden, so the same frame can be taken with and without the descent.
var qa_hidden := false
var reduced_motion := false
var flash_scale := 1.0
var shake_scale := 1.0
var numbers_on := true
var low := false

var view: Node3D
var stats := {"cutins": 0, "sweeps": 0, "bolts": 0, "bolts_dropped": 0, "peak_bolts": 0, "flights": 0, "lights_peak": 0, "particles": 0,
	"rocks": 0, "impacts": 0, "pulses": 0, "breaks": 0, "kicks": 0, "peak_alpha_layers": 0, "bolts_recycled": 0, "sigils": 0, "cutscenes": 0, "skips": 0, "bands": 0}

## Values the element's module sets each frame for the one screen shader (read by _push_screen).
var scr := {"sky": 0.0, "sky_flash": 0.0, "storm": 0.0, "gust": 0.0, "fire_cover": 0.0, "fire_alpha": 0.0, "whiteout": 0.0, "demon_pose": 0.0}
var holder: Node3D
var tint := Color.WHITE
var hero := Vector2.ZERO
var sw: Dictionary = {}
## The render frame's delta (capped), also while a hit-stop holds the sweep's own clock: flashes decay on this one, so a freeze frame never holds a white screen.
var wall_dt := 0.0

var _built := false
var _shown := false
var _element := ""
var _last_seq := -1
var _clock := 0.0
var _release_due := false
var _layer: CanvasLayer
var _screen: ColorRect
var _screen_mat: ShaderMaterial
var _kill_label: Label
var _kill_tail: Label
var _kill_total := 0
var _band: Control
var _band_layer: CanvasLayer
var _cutscene: Control
var _cutscene_layer: CanvasLayer
var _calls := 0                 ## descents called in this run (the first one is the cut-scene's)
var _scene_failed := false      ## the video could not be used in this run: no second try (A11 12.3.3)
var _preopen_done := false
var _bonus := 0.0
var _hud_hidden := false
var _band_flag := false
var _sigil: MeshInstance3D
var _sigil_mat: ShaderMaterial
var _sigil_age := -1.0
var _sigil_alpha := 0.0
var _sigil_art_checked := false
var _flight: MultiMeshInstance3D
var _lights: Array[OmniLight3D] = []
var _light_life := PackedFloat32Array([0.0, 0.0, 0.0])
var _light_total := PackedFloat32Array([0.1, 0.1, 0.1])
var _light_energy := PackedFloat32Array([0.0, 0.0, 0.0])
var _light_next := 0
var _ult: RefCounted = null
var _sky_art_checked := false

var _aura := 0.0
var _aura_pulse := 0.0
var _pulse := 0.0
var _freeze := 0.0
var _shatter := 0.0
var _scrim_hold := 0.0
var _demon := 0.0
var _hitstop := 0.0
var _cut: Dictionary = {}
var _orb_cache := PackedVector2Array()
var _kill_cache := PackedVector2Array()
var _flights := PackedFloat32Array()      ## per flight: x, z, delay, age, kind(0 orb, 1 puff), unused
var _flight_target := Vector3.ZERO
var _kill_label_age := -1.0
var _last_kick_t := -1.0
var _kick_hold := 0.0
## Frames left in which every material of this file is drawn once, invisibly small, right after it is built (so a sweep never meets a shader compile: D24 10.3).
var _warm := 0

func setup(owner_view: Node3D) -> void:
	view = owner_view
	for arg in OS.get_cmdline_user_args():
		if arg == "--chapter1-descent-fx=low": low = true
		elif arg == "--chapter1-descent-fx=full": low = false

## A new run: everything this file shows is dropped. No node is made here.
func reset() -> void:
	_last_seq = -1
	_clock = 0.0
	_release_due = false
	_cut = {}
	if _cutscene != null: _cutscene.close()
	if _band != null: _band.close()
	_calls = 0
	_scene_failed = false
	_preopen_done = false
	_bonus = 0.0
	sw = {}
	_aura = 0.0
	_aura_pulse = 0.0
	_pulse = 0.0
	_freeze = 0.0
	_shatter = 0.0
	_scrim_hold = 0.0
	_demon = 0.0
	_hitstop = 0.0
	_kick_hold = 0.0
	_last_kick_t = -1.0
	_orb_cache = PackedVector2Array()
	_kill_cache = PackedVector2Array()
	_flights = PackedFloat32Array()
	_kill_label_age = -1.0
	_element = ""
	_kill_total = 0
	_sky_art_checked = false
	_sigil_age = -1.0
	_sigil_alpha = 0.0
	_sigil_art_checked = false
	_reset_scr()
	_set_hud_hidden(false)
	_set_band_flag(false)
	if _built:
		_hide_all()
		if _flight != null: _flight.multimesh.visible_instance_count = 0
		for light in _lights:
			light.visible = false
			light.light_energy = 0.0
		_light_life.fill(0.0)
		_free_built()

## true once, when the cut-in has run to the moment the sweep should start. The app then calls release_descent().
func take_release() -> bool:
	var due := _release_due
	_release_due = false
	return due

## A read-only digest for tools and tests.
func status() -> Dictionary:
	return {"built": _built, "element": _element, "cutin": not _cut.is_empty(), "cut_t": float(_cut.get("t", 0.0)), "cut_dur": float(_cut.get("dur", 0.0)), "cut_kind": String(_cut.get("kind", "")),
		"video_s": float(_cut.get("video_s", 0.0)), "skipped": float(_cut.get("skip_at", -1.0)) >= 0.0, "hud_hidden": _hud_hidden, "band_up": _band != null and _band.visible,
		"hold_limit": hold_limit(),
		"sweep": not sw.is_empty(), "sweep_t": float(sw.get("t", 0.0)), "aura": _aura, "bolts": int(_ult.live_bolts()) if _ult != null and _element == "arc" else 0,
		"release_due": _release_due, "demon": _demon, "low": low, "stats": stats.duplicate(),
		"sigil": _sigil_age >= 0.0, "sigil_alpha": _sigil_alpha, "sigil_age": _sigil_age}

# ---------------------------------------------------------------- services for the element modules

func camera() -> Camera3D:
	var world: Variant = view.get("world") if view != null else null
	if world == null: return null
	return world.get("camera") as Camera3D

func kick(strength: float) -> void:
	if reduced_motion or shake_scale <= 0.0: return
	stats.kicks += 1
	var world: Variant = view.get("world")
	if world != null and world.has_method("kick_camera"): world.kick_camera(strength * shake_scale)

## Camera impulses that come within 0.1 s of each other are one: the strongest of them goes out when the gap has passed.
func kick_merged(strength: float, t: float) -> void:
	if t - _last_kick_t >= 0.1:
		_last_kick_t = t
		kick(maxf(strength, _kick_hold))
		_kick_hold = 0.0
	else:
		_kick_hold = maxf(_kick_hold, strength)

func hitstop(seconds: float = HITSTOP_SECONDS) -> void:
	if reduced_motion: return
	_hitstop = maxf(_hitstop, seconds)

## A pooled light (3 for the whole sweep, none on the low spec). Round robin.
func pool_light(at: Vector3, color: Color, energy: float, range_: float, seconds: float) -> void:
	if low or _lights.is_empty(): return
	var index := _light_next
	_light_next = (_light_next + 1) % _lights.size()
	_set_light(index, at, color, energy, range_, seconds)

func hero_uv() -> Vector2:
	var cam := camera()
	if cam == null or not cam.is_inside_tree(): return Vector2(-1, -1)
	var size_ := view.get_viewport().get_visible_rect().size
	if size_.x < 1.0 or size_.y < 1.0: return Vector2(-1, -1)
	return cam.unproject_position(Vector3(hero.x, 1.0, hero.y)) / size_

func screen_aspect() -> float:
	if _screen != null and _screen.size.y > 1.0: return _screen.size.x / _screen.size.y
	return 16.0 / 9.0

## Rounds an amount to the low spec's share.
func count(amount: int) -> int:
	return maxi(4, int(round(float(amount) * (0.35 if low else 1.0))))

## One soft round dot shared by every particle of this file (untextured quads read as square confetti).
static var _soft_dot: GradientTexture2D = null

func soft_dot() -> GradientTexture2D:
	if _soft_dot == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		_soft_dot = GradientTexture2D.new()
		_soft_dot.gradient = gradient
		_soft_dot.fill = GradientTexture2D.FILL_RADIAL
		_soft_dot.fill_from = Vector2(0.5, 0.5)
		_soft_dot.fill_to = Vector2(1.0, 0.5)
		_soft_dot.width = 64
		_soft_dot.height = 64
	return _soft_dot

func particle_quad(additive: bool, stretch: Vector2 = Vector2(0.3, 0.3), align_velocity: bool = false) -> QuadMesh:
	var mesh := QuadMesh.new(); mesh.size = stretch
	var material := StandardMaterial3D.new()
	material.albedo_texture = soft_dot()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive: material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_keep_scale = true
	mesh.material = material
	return mesh

func ramp(stops: Array) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(stops.map(func(s): return float(s[0])))
	gradient.colors = PackedColorArray(stops.map(func(s): return s[1]))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture

func ease_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)

func ramp_t(t: float, a: float, b: float) -> float:
	return clampf((t - a) / maxf(0.0001, b - a), 0.0, 1.0)

## The same integer-ish hash everywhere in the presenter: deterministic, no engine random.
func hash1(a: float) -> float:
	return fposmod(sin(a * 12.9898) * 43758.5453, 1.0)

## A world point on the sweep's screen rectangle? (D24 4.1) u along the screen's right, v along its down.
func in_area(point: Vector2, margin: float = 0.0) -> bool:
	var a: Dictionary = sw.get("area", DEFAULT_AREA)
	var d := point - (sw.center as Vector2)
	var rad := deg_to_rad(float(a.right_deg))
	var right := Vector2(cos(rad), sin(rad))
	var down := right.rotated(-PI * 0.5)
	return absf(d.dot(right)) <= float(a.half_w_m) + margin and absf(d.dot(down)) <= float(a.half_h_m) + margin

# ---------------------------------------------------------------- events

func consume(events: Array) -> void:
	for event in events:
		var seq := int(event.seq)
		if seq <= _last_seq: continue
		_last_seq = seq
		var type_ := String(event.type)
		if not type_.begins_with("descent_") and type_ != "orb_vacuum": continue
		match type_:
			"descent_ready": _aura_pulse = 1.0
			"descent_called": _on_called(event)
			"descent_released": _on_released(event)
			"descent_book": _on_book(event)
			"descent_strike": _on_strike(event)
			"descent_end": _on_end(event)
			"orb_vacuum":
				if String(event.get("by", "")) == "descent": _start_flights()

## true when this call should play the demon's cut-scene (A11 12.3.1: the run's first descent, or every one with "always"; never with the 0.5 s setting).
func _wants_scene(variant: String) -> bool:
	if cutin_short or cutscene_mode == "off" or _scene_failed: return false
	return cutscene_mode == "always" or variant == "long"

## The gauge is full: open the video now, held on its first frame, so the call meets no loading (A11 12.3.6).
func _preopen() -> void:
	if view == null or not _wants_scene("long" if _calls == 0 else "short") or _element == "": return
	_ensure_cutscene()
	if _cutscene != null and not _cutscene.has_video():
		if not _cutscene.open_stream(_element): _scene_failed = true

func _ensure_cutscene() -> void:
	if _cutscene != null or view == null: return
	_cutscene = DescentCutscene.attach(view)
	_cutscene_layer = _cutscene.get_parent()

func _on_called(event: Dictionary) -> void:
	_ensure_built(String(event.element))
	if not _built: return
	var variant := String(event.get("variant", "long"))
	var scene := _wants_scene(variant)
	var video_s := 0.0
	if scene:
		_ensure_cutscene()
		if not _cutscene.has_video() and not _cutscene.open_stream(_element):
			_scene_failed = true
			scene = false
		else:
			video_s = _cutscene.video_seconds()
	var short := not scene and (cutin_short or variant == "short")
	_calls += 1
	if scene:
		var close_at := CUT_OPEN_END + video_s
		_cut = {"t": 0.0, "wall": 0.0, "kind": "video", "short": false, "released": false, "video_s": video_s, "skip_at": -1.0, "close_at": close_at,
			"release_at": close_at + CUT_RELEASE_AFTER, "dur": close_at + CUT_RELEASE_AFTER + 0.3, "started": false}
		stats.cutscenes += 1
	else:
		var dur := SHORT_SECONDS if short else LONG_SECONDS
		_cut = {"t": 0.0, "wall": 0.0, "kind": "band", "short": short, "released": false, "video_s": 0.0, "skip_at": -1.0, "release_at": dur * T_RELEASE / T_END, "dur": dur}
	_release_due = false
	_preopen_done = false
	_bonus = clampf(float(int(event.get("hold_bonus_bps", 0))) / 10000.0, 0.0, 0.3)
	stats.cutins += 1
	_sigil_age = 0.0
	stats.sigils += 1
	_open_band()

func _on_released(event: Dictionary) -> void:
	_ensure_built(String(event.element))
	if not _built or _ult == null: return
	var el := String(event.element)
	var area: Dictionary = event.get("area", DEFAULT_AREA)
	var ticks := int(event.sweep_ticks)
	sw = {"element": el, "center": event.center as Vector2, "area": area, "dur": float(ticks) / 60.0, "t": 0.0, "tail": float(TAIL.get(el, 1.0)),
		"ended_at": -1.0, "kills": 0, "legacy": not event.has("area")}
	_kill_cache = PackedVector2Array()
	_hitstop = 0.0
	_last_kick_t = -1.0
	_kick_hold = 0.0
	_reset_scr()
	stats.sweeps += 1
	if not _cut.is_empty(): _cut["sweep"] = true   # the band leaves on THIS sweep's clock (an earlier sweep's tail may still be running)
	_load_sky_art()
	_ult.begin(event)
	# the shots that were wiped: small flashes where they were
	var cleared: Array = event.get("cleared_positions", [])
	var made := 0
	for at in cleared:
		if made >= FLIGHT_PUFFS: break
		_flights.append(at.x); _flights.append(at.y); _flights.append(0.0); _flights.append(0.0); _flights.append(1.0); _flights.append(0.0)
		made += 1

func _on_book(event: Dictionary) -> void:
	if sw.is_empty() or _ult == null: return
	_ult.book(event)

func _on_strike(event: Dictionary) -> void:
	if sw.is_empty() or not _built or _ult == null: return
	if event.has("center"): sw["center"] = event.center
	var step := int(event.get("step", -1))
	if step >= 0 and absf(float(sw.t) - float(step) / 60.0) > 0.05: sw["t"] = float(step) / 60.0
	var positions: Array = event.get("positions", [])
	for pos in positions:
		if _kill_cache.size() < 48: _kill_cache.append(pos)
	_ult.strike(event)

func _on_end(event: Dictionary) -> void:
	if not _built: return
	# kills_total (the core's later field: the whole sweep, entrants included) when it is there, else kills
	var shown := int(event.get("kills_total", event.get("kills", 0)))
	sw["kills"] = shown
	if not sw.is_empty(): sw["ended_at"] = float(sw.t)
	kick(0.25)
	if numbers_on and shown > 0 and _kill_label != null:
		_kill_total = shown
		_kill_label.text = str(shown)
		_kill_tail.text = Loc.t("descent.kills.tail")
		_kill_label_age = 0.0
		_kill_label.visible = true
		_kill_tail.visible = true

# ---------------------------------------------------------------- build (lazy)

func _ensure_built(element: String) -> void:
	if _built or view == null: return
	_element = element
	tint = Palette.element_color(element, Palette.BRASS)
	_build()

func _free_built() -> void:
	# The nodes are dropped with the run; the element can differ in a new run.
	if _built:
		if _ult != null: _ult.reset()
		if holder != null: holder.queue_free()
		if _layer != null: _layer.queue_free()
		if _band_layer != null: _band_layer.queue_free()
		if _cutscene != null: _cutscene.close()
		if _cutscene_layer != null: _cutscene_layer.queue_free()
		holder = null; _layer = null; _screen = null; _screen_mat = null; _kill_label = null; _kill_tail = null; _flight = null; _ult = null; _sigil = null; _sigil_mat = null
		_band = null; _band_layer = null; _cutscene = null; _cutscene_layer = null
		_lights.clear()
		_built = false
		_shown = false

func _build() -> void:
	holder = Node3D.new(); holder.name = "DescentFx"
	view.add_child(holder)
	# Orb flights and the puffs of wiped shots: one MultiMesh.
	var spark := QuadMesh.new(); spark.size = Vector2(0.34, 0.34)
	var spark_material := StandardMaterial3D.new()
	spark_material.albedo_texture = soft_dot()   # untextured these read as white squares (the orbs' flight after the sweep)
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	spark_material.vertex_color_use_as_albedo = true
	spark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark_material.render_priority = 7
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = spark
	mm.instance_count = FLIGHT_ORBS + FLIGHT_PUFFS
	mm.visible_instance_count = 0
	_flight = MultiMeshInstance3D.new(); _flight.name = "DescentFlights"
	_flight.multimesh = mm
	_flight.material_override = spark_material
	_flight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flight.extra_cull_margin = 60.0
	holder.add_child(_flight)
	# Three lights for the whole sweep (the cut-in uses none; the low spec uses none).
	if not low:
		for i in MAX_LIGHTS:
			var light := OmniLight3D.new(); light.name = "DescentLight%d" % i
			light.shadow_enabled = false
			light.omni_range = 8.0
			light.light_color = tint
			light.light_energy = 0.0
			light.visible = false
			holder.add_child(light)
			_lights.append(light)
	# The sign under the hero (A11 5.1): one flat quad, plain alpha, under every enemy telegraph.
	_sigil = MeshInstance3D.new(); _sigil.name = "DescentSigil"
	var sigil_plane := PlaneMesh.new(); sigil_plane.size = Vector2(SIGIL_SIZE_M, SIGIL_SIZE_M)
	_sigil.mesh = sigil_plane
	_sigil_mat = ShaderMaterial.new(); _sigil_mat.shader = SIGIL_SHADER
	_sigil_mat.render_priority = -4   # above the frost floor (-5), far under every telegraph (10..12)
	_sigil_mat.set_shader_parameter("tint", tint)
	_sigil_mat.set_shader_parameter("brass", Palette.BRASS)
	_sigil_mat.set_shader_parameter("brass_dim", Palette.BRASS_DIM)
	_sigil_mat.set_shader_parameter("element_id", float(ELEMENT_ID.get(_element, 0.0)))
	_sigil_mat.set_shader_parameter("low", 1.0 if low else 0.0)
	_sigil.material_override = _sigil_mat
	_sigil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sigil.visible = false
	holder.add_child(_sigil)
	# The element's own layers.
	match _element:
		"ember": _ult = EmberUlt.new()
		"frost": _ult = FrostUlt.new()
		_: _ult = ArcUlt.new()
	_ult.build(self)
	stats.particles = int(_ult.particle_total())
	# The screen layer.
	_layer = CanvasLayer.new(); _layer.name = "DescentScreen"
	_layer.layer = 0
	view.add_child(_layer)
	_screen = ColorRect.new(); _screen.name = "Screen"
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen_mat = ShaderMaterial.new(); _screen_mat.shader = SCREEN_SHADER
	_screen.material = _screen_mat
	_screen.visible = false
	_layer.add_child(_screen)
	# The band goes above the screen layer (same canvas layer number, later in the tree), under the HUD's.
	_band = DescentBand.attach(view)
	_band_layer = _band.get_parent()
	# The kill number over the hero's head at the sweep's end (A11 6): the big number and a small word under it.
	_kill_label = Label.new(); _kill_label.name = "Kills"
	_kill_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kill_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_kill_label.size = Vector2(320, 90)
	_kill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kill_label.add_theme_font_override("font", Loc.font("heading_black"))
	_kill_label.add_theme_font_size_override("font_size", KILL_NUMBER_SIZE)
	_kill_label.add_theme_color_override("font_color", Palette.INK)
	_kill_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03, .95))
	_kill_label.add_theme_constant_override("outline_size", 10)
	_kill_label.add_theme_color_override("font_shadow_color", Color(tint, .55))
	_kill_label.add_theme_constant_override("shadow_outline_size", 22)
	_kill_label.visible = false
	_layer.add_child(_kill_label)
	_kill_tail = Label.new(); _kill_tail.name = "KillsTail"
	_kill_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kill_tail.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_kill_tail.size = Vector2(320, 28)
	_kill_tail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kill_tail.add_theme_font_override("font", Loc.font("heading"))
	_kill_tail.add_theme_font_size_override("font_size", 17)
	_kill_tail.add_theme_color_override("font_color", Palette.INK_DIM)
	_kill_tail.add_theme_color_override("font_outline_color", Color(0, 0, 0, .9))
	_kill_tail.add_theme_constant_override("outline_size", 5)
	_kill_tail.visible = false
	_layer.add_child(_kill_tail)
	_screen_mat.set_shader_parameter("tint", tint)
	_screen_mat.set_shader_parameter("element_id", float(ELEMENT_ID.get(_element, 0.0)))
	_screen_mat.set_shader_parameter("demon_x", float(SKY_X.get(_element, 0.7)))
	_screen_mat.set_shader_parameter("low", 1.0 if low else 0.0)
	_built = true
	_warm = 5

## The demon of the sky layer (A11 4.6): illustration.sky.descent.<element>, else the band's own picture illustration.cutin.descent.<element> (so the sky and the band
## show one demon), else the grace screen's demon, else the code silhouette (also with --chapter1-descent-sky=silhouette). sky_art_kind: 1 a waist-up picture, 0 a full-length one.
func _load_sky_art() -> void:
	if _sky_art_checked or _screen_mat == null: return
	_sky_art_checked = true
	var tex: Texture2D = null
	var kind := 0.0
	if not ("--chapter1-descent-sky=silhouette" in OS.get_cmdline_user_args()):
		for candidate in [[SKY_SLOT_PREFIX, 1.0], [CUTIN_SLOT_PREFIX, 1.0], [GRACE_SLOT_PREFIX, 0.0]]:
			var slot := String(candidate[0]) + _element
			if AssetSlots.has_slot(slot) and not AssetSlots.is_planned(slot) and not (slot in AssetSlots.missing()):
				tex = AssetSlots.texture(slot)
				if tex != null:
					kind = float(candidate[1])
					break
	_screen_mat.set_shader_parameter("sky_art", tex)
	_screen_mat.set_shader_parameter("has_sky_art", 1.0 if tex != null else 0.0)
	_screen_mat.set_shader_parameter("sky_art_kind", kind)

func _reset_scr() -> void:
	for key in scr: scr[key] = 0.0

# ---------------------------------------------------------------- per frame

func sync(run: RefCounted, delta: float) -> void:
	var v: Dictionary = run.descent_view()
	if not bool(v.get("enabled", false)):
		if _built and _shown: _hide_all()
		return
	if not _built:
		_ensure_built(String(v.element))
		if not _built: return
	var dt := minf(delta, 0.1)
	wall_dt = dt
	_clock += delta
	var mode := String(run.mode)
	hero = run.hero.position if not run.hero.is_empty() else Vector2.ZERO
	var state := String(v.state)
	# The edge aura: only while the gauge is full and nothing else is going on.
	var aura_target := 1.0 if state == "ready" and mode == "playing" else 0.0
	_aura = move_toward(_aura, aura_target, dt * 2.0)
	_aura_pulse = maxf(0.0, _aura_pulse - dt * 1.2)
	_pulse = maxf(0.0, _pulse - dt * 4.5)
	if state == "ready" and not _preopen_done:
		_preopen_done = true
		_preopen()
	_update_cutin(run, mode, state, dt, delta)
	_update_parts(mode)
	_update_warm()
	_update_sweep(run, mode, dt)
	_update_sigil(dt)
	_update_flights(run, dt)
	_update_lights(dt)
	_update_label(dt)
	_push_screen()
	if qa_hidden: _qa_hide()

func _qa_hide() -> void:
	if _screen != null: _screen.visible = false
	if holder != null: holder.visible = false
	if _band_layer != null: _band_layer.visible = false
	if _kill_label != null: _kill_label.visible = false
	if _kill_tail != null: _kill_tail.visible = false

func _hide_all() -> void:
	_shown = false
	if _screen != null: _screen.visible = false
	if _kill_label != null: _kill_label.visible = false
	if _kill_tail != null: _kill_tail.visible = false
	if _sigil != null: _sigil.visible = false
	if _ult != null: _ult.hide_all()

## The hold limit the app uses (chapter_one.gd): the video's length plus HOLD_PAD while the cut-scene plays, HOLD_PAD alone otherwise. A floor under a broken
## picture: the core never stands still longer than this.
func hold_limit() -> float:
	var extra := 0.0
	if not _cut.is_empty() and String(_cut.get("kind", "")) == "video": extra = float(_cut.get("video_s", 0.0))
	return HOLD_PAD + extra

## The picture's own watchdog: half a second under the app's limit.
func watchdog_seconds() -> float:
	return hold_limit() - (HOLD_PAD - WATCHDOG_SECONDS)

## true while the cut-scene owns the keys (the video is up and the core has not been let go): the app hands every press to try_skip() and does not pass it on.
func input_guard() -> bool:
	return not _cut.is_empty() and String(_cut.kind) == "video" and not bool(_cut.released)

## A press while the cut-scene plays (A11 12.3.4). Always consumed while input_guard(); it skips the rest of the video only after the first 0.5 s and once.
func try_skip() -> bool:
	if not input_guard(): return false
	if float(_cut.wall) < CUT_SKIP_LOCK or float(_cut.skip_at) >= 0.0: return true
	var t := float(_cut.t)
	if t + CUT_SKIP_FADE >= float(_cut.close_at): return true
	_cut["skip_at"] = t
	_cut["close_at"] = t + CUT_SKIP_FADE
	_cut["release_at"] = float(_cut.close_at) + CUT_RELEASE_AFTER
	stats.skips += 1
	return true

func _update_cutin(run: RefCounted, mode: String, state: String, dt: float, wall_dt: float) -> void:
	if _cut.is_empty(): return
	# the picture runs only while the core holds (or just after it let go, for the band's leaving)
	if mode == "descent" or (bool(_cut.released) and mode == "playing"):
		_cut["wall"] = float(_cut.wall) + wall_dt
		var step := dt
		if String(_cut.kind) == "video" and not bool(_cut.started) and float(_cut.t) + dt > CUT_DARK_END and not _cutscene.first_frame_ready():
			# the strip opens round the video's first frame: the clock waits for it, but not longer than CUT_FRAME_WAIT (then the long band, A11 12.3.3)
			if float(_cut.wall) >= CUT_FRAME_WAIT:
				_scene_failed = true
				_fall_back_to_band()
				step = 0.0
			else:
				step = maxf(0.0, CUT_DARK_END - float(_cut.t))
		_cut["t"] = float(_cut.t) + step
	if String(_cut.kind) == "video" and not bool(_cut.started) and float(_cut.t) >= CUT_OPEN_END:
		_cut["started"] = true
		_cutscene.start()
	if String(_cut.kind) == "video" and bool(_cut.started) and not bool(_cut.released):
		_cutscene.set_paused(mode != "descent")
	if mode == "descent" and not bool(_cut.released) and (float(_cut.t) >= float(_cut.release_at) or float(_cut.wall) >= watchdog_seconds()):
		_cut["released"] = true
		_release_due = true
	if state != "hold" and not bool(_cut.released) and mode == "playing":
		# the core is no longer holding (someone else released it): end the picture
		_cut["released"] = true
	if bool(_cut.released) and (_band_out_value() >= 1.0 or float(_cut.t) >= float(_cut.release_at) + 2.0):
		_cut = {}
		if _cutscene != null: _cutscene.close()

## The video did not give a frame in time: the long band, from where its dark phase ends.
func _fall_back_to_band() -> void:
	if _cutscene != null: _cutscene.close()
	_cut = {"t": LONG_BAND.dark[1], "wall": float(_cut.wall), "kind": "band", "short": false, "released": false, "video_s": 0.0, "skip_at": -1.0,
		"release_at": LONG_SECONDS * T_RELEASE / T_END, "dur": LONG_SECONDS}

## 0..1 how far the band has left: on the sweep's clock after the release (ember s12..s24, frost s6..s15, lightning s4..s15), on the picture's own clock if no sweep is running.
func _band_out_value() -> float:
	if _cut.is_empty() or not bool(_cut.released): return 0.0
	var window: Array = BAND_OUT.get(_element, [12.0, 24.0])
	if not sw.is_empty() and bool(_cut.get("sweep", false)): return ramp_t(float(sw.t) * 60.0, float(window[0]), float(window[1]))
	return ramp_t(float(_cut.t) - float(_cut.release_at), 0.0, 0.4)

func _cut_uniforms() -> Dictionary:
	var u := {"scrim": 0.0}
	if _cut.is_empty(): return u
	var dark_end: float = CUT_DARK_END if String(_cut.kind) == "video" else float((SHORT_BAND if bool(_cut.short) else LONG_BAND).dark[1])
	u.scrim = ramp_t(float(_cut.t), 0.0, dark_end) * (1.0 - _band_out_value())
	return u

# ---- the band and the cut-scene (A11): this file pushes the values on its timetable, the parts only draw

func _open_band() -> void:
	if _band == null: return
	_band.reduced_motion = reduced_motion
	_band.open(_element)
	stats.bands += 1

func _set_hud_hidden(hidden: bool) -> void:
	if hidden == _hud_hidden: return
	_hud_hidden = hidden
	var hud: Variant = view.get("hud") if view != null else null
	if hud != null and hud.has_method("set_hud_hidden"): hud.set_hud_hidden(hidden)

func _set_band_flag(up: bool) -> void:
	if up == _band_flag: return
	_band_flag = up
	var hud: Variant = view.get("hud") if view != null else null
	if hud == null: return
	var bar: Variant = hud.get("combat_bar")
	if bar != null and is_instance_valid(bar) and bar.has_method("set_descent_band"): bar.set_descent_band(up)

func _update_parts(mode: String) -> void:
	if _band == null: return
	if _cut.is_empty():
		if _band.visible or _band.band_in > 0.0: _band.close()
		_set_band_flag(false)
		_set_hud_hidden(false)
		return
	var t := float(_cut.t)
	var kind := String(_cut.kind)
	var out := _band_out_value()
	var hu := hero_uv()
	var screen_size: Vector2 = _band.size if _band.size.x > 1.0 else Vector2(1600.0, 900.0)
	var hero_top: Vector2 = DescentBand.hero_top_from_uv(hu, screen_size) if hu.x >= 0.0 else DescentBand.DEFAULT_HERO_TOP
	var flashy := 0.0 if reduced_motion else flash_scale
	var values := {"band_out": out, "hero_top": hero_top, "reduced_motion": reduced_motion, "slide_out": _element != "arc", "bonus": _bonus}
	var name_start := 0.0
	var scene_on := false
	if kind == "video":
		var cs := float(_cut.close_at)
		var bs := cs + CUT_CLOSE_SECONDS
		var skipped := float(_cut.skip_at) >= 0.0
		if t < bs:
			scene_on = true
			var open := ramp_t(t, CUT_DARK_END, CUT_OPEN_END)
			if t >= cs: open = 1.0 - ramp_t(t, cs, bs)
			var tag_off := 1.0 - ramp_t(t, cs - 0.06, cs)
			var lay := DescentBand.layout(hero_top, screen_size)
			_cutscene.apply({"element": _element, "open": open, "plate": ramp_t(t, 0.50, 0.70) * tag_off, "skip_hint": (0.0 if skipped else ramp_t(t, 1.0, 1.2)) * tag_off,
				"fade": (1.0 - ramp_t(t, float(_cut.skip_at), float(_cut.skip_at) + CUT_SKIP_FADE)) if skipped else 1.0, "reduced_motion": reduced_motion,
				"closed_cy": float(lay.centre.y), "closed_h": float(lay.height)})
			values["band_in"] = 0.0
		else:
			if _cutscene.has_video():
				_cutscene.apply({"open": 0.0})
				_cutscene.close()
			var bt := t - bs
			name_start = bs
			values["band_in"] = 1.0
			values["demon"] = ramp_t(bt, 0.0, 0.10)
			values["name"] = ramp_t(bt, 0.0, CUT_NAME_SECONDS)
			values["line"] = ramp_t(bt, 0.06, 0.18)
	else:
		var tab: Dictionary = SHORT_BAND if bool(_cut.short) else LONG_BAND
		values["band_in"] = ramp_t(t, tab.band[0], tab.band[1])
		values["demon"] = ramp_t(t, tab.demon[0], tab.demon[1])
		values["name"] = ramp_t(t, tab.name[0], tab.name[1])
		values["line"] = ramp_t(t, tab.line[0], tab.line[1])
		name_start = float(tab.name[0])
	if not scene_on:
		var since := t - name_start
		var pulse := sin(PI * ramp_t(since, 0.0, 0.10)) if since > 0.0 and since < 0.10 else 0.0
		var sweep_v := ramp_t(since, 0.08, 0.58)
		values["trim_flash"] = pulse * flashy
		values["sweep"] = sweep_v if flashy > 0.0 and sweep_v > 0.0 and sweep_v < 1.0 else -1.0
	_band.apply(values)
	_set_band_flag(_band.visible)
	_set_hud_hidden(kind == "video" and t >= CUT_DARK_END and not bool(_cut.released))

func _push_screen() -> void:
	var cu := _cut_uniforms()
	var cut_on := not _cut.is_empty()
	var scrim := float(cu.scrim)
	var dim := _scrim_hold
	var sweeping := not sw.is_empty()
	var any := _aura > 0.005 or _aura_pulse > 0.005 or cut_on or _freeze > 0.005 or _pulse > 0.005 or scrim > 0.005 or dim > 0.005 or sweeping or _warm > 0 or float(scr.whiteout) > 0.005
	_shown = _shown or any
	_screen.visible = any
	if not any: return
	var size_ := _screen.size
	_screen_mat.set_shader_parameter("aspect", size_.x / maxf(1.0, size_.y))
	_screen_mat.set_shader_parameter("time", _clock)
	_screen_mat.set_shader_parameter("aura", _aura * (1.0 if flash_scale > 0.0 else 0.6))
	_screen_mat.set_shader_parameter("aura_pulse", _aura_pulse * flash_scale)
	_screen_mat.set_shader_parameter("scrim", scrim)
	_screen_mat.set_shader_parameter("dim", dim)
	var hu := hero_uv()
	var aspect_ := size_.x / maxf(1.0, size_.y)
	_screen_mat.set_shader_parameter("hero_on", 1.0 if hu.x >= 0.0 else 0.0)
	_screen_mat.set_shader_parameter("hero_sc", Vector2((hu.x - 0.5) * aspect_, hu.y - 0.5))
	_screen_mat.set_shader_parameter("freeze", _freeze)
	_screen_mat.set_shader_parameter("shatter", _shatter)
	_screen_mat.set_shader_parameter("pulse", _pulse * flash_scale)
	# the sweep's layers (settings applied here, in one place)
	var flashy := 0.0 if reduced_motion else flash_scale
	_screen_mat.set_shader_parameter("sky", float(scr.sky))
	_screen_mat.set_shader_parameter("sky_flash", float(scr.sky_flash) * flashy)
	_screen_mat.set_shader_parameter("storm", float(scr.storm))
	_screen_mat.set_shader_parameter("gust", float(scr.gust) * (0.0 if reduced_motion else 1.0))
	_screen_mat.set_shader_parameter("fire_cover", float(scr.fire_cover))
	_screen_mat.set_shader_parameter("fire_alpha", float(scr.fire_alpha) * lerpf(0.3, 1.0, flashy))
	_screen_mat.set_shader_parameter("whiteout", float(scr.whiteout) * flashy)
	_screen_mat.set_shader_parameter("demon", _demon)
	_screen_mat.set_shader_parameter("demon_pose", float(scr.demon_pose))

## A11 5.1: the sign under the hero. Drawn over 0.30 s from the call (the clock is the wall's: the core stands still then), stays at 0.45 through
## the sweep turning 20 deg/s, goes out over 0.4 s from the sweep's end. Not shown while nothing of the descent is going on.
func _update_sigil(dt: float) -> void:
	if _sigil == null: return
	var want := not _cut.is_empty() or not sw.is_empty()
	var fade := 1.0
	var ended := not sw.is_empty() and float(sw.ended_at) >= 0.0
	if ended:
		fade = 1.0 - ramp_t(float(sw.t), float(sw.ended_at), float(sw.ended_at) + SIGIL_FADE_SECONDS)
		if fade <= 0.0: want = false
	if not want:
		_sigil_age = -1.0
		_sigil_alpha = 0.0
		_sigil.visible = _warm > 0
		if _warm > 0: _sigil_mat.set_shader_parameter("fade", 0.0)
		return
	if _sigil_age < 0.0: _sigil_age = 0.0
	_sigil_age += dt
	_load_sigil_art()
	var draw := 1.0 if reduced_motion else ease_out(ramp_t(_sigil_age, 0.0, SIGIL_DRAW_SECONDS))
	var cap := lerpf(SIGIL_ALPHA_DRAW, SIGIL_ALPHA_SWEEP, 0.0 if sw.is_empty() else ramp_t(float(sw.t), 0.0, 0.3))
	_sigil_alpha = cap * fade
	_sigil.visible = true
	_sigil.global_position = Vector3(hero.x, 0.04, hero.y)
	_sigil_mat.set_shader_parameter("draw", draw)
	_sigil_mat.set_shader_parameter("fade", fade * (ramp_t(_sigil_age, 0.0, 0.12) if reduced_motion else 1.0))
	_sigil_mat.set_shader_parameter("max_alpha", cap)
	_sigil_mat.set_shader_parameter("spin", 0.0 if reduced_motion else deg_to_rad(SIGIL_SPIN_DEG) * _sigil_age)
	_sigil_mat.set_shader_parameter("low", 1.0 if low else 0.0)

## The picture of the slot fx.descent.sigil.<element> when one is chosen (the slot is `planned` until then: the shader's own sign is drawn).
func _load_sigil_art() -> void:
	if _sigil_art_checked or _sigil_mat == null: return
	_sigil_art_checked = true
	var slot := SIGIL_SLOT_PREFIX + _element
	var tex: Texture2D = null
	if AssetSlots.has_slot(slot) and not AssetSlots.is_planned(slot):
		tex = AssetSlots.texture(slot)
		if slot in AssetSlots.missing(): tex = null
	_sigil_mat.set_shader_parameter("art", tex)
	_sigil_mat.set_shader_parameter("has_art", 1.0 if tex != null else 0.0)

func _update_warm() -> void:
	if _ult == null: return
	if _warm > 0 and sw.is_empty() and _cut.is_empty():
		_warm -= 1
		_ult.warm(true)
		# the merged kill number's glyphs (a CJK heading font with an outline) are rasterised on first use: a 400 ms hitch at the sweep's last tick
		if _kill_label != null and _kill_label_age < 0.0:
			_kill_label.text = "8888"
			_kill_tail.text = Loc.t("descent.kills.tail")
			_kill_label.modulate = Color(1, 1, 1, 0.01)
			_kill_tail.modulate = Color(1, 1, 1, 0.01)
			_kill_label.visible = true
			_kill_tail.visible = true
		if _warm == 0:
			_ult.warm(false)
			_hide_kill_warm()
	elif _warm > 0:
		_warm = 0
		_ult.warm(false)
		_hide_kill_warm()

func _hide_kill_warm() -> void:
	if _kill_label != null and _kill_label_age < 0.0:
		_kill_label.visible = false
		_kill_tail.visible = false

func _update_sweep(run: RefCounted, mode: String, dt: float) -> void:
	if sw.is_empty():
		_freeze = 0.0
		_shatter = 0.0
		_demon = 0.0
		_scrim_hold = maxf(0.0, _scrim_hold - dt * 2.0)
		return
	var step_dt := 0.0
	if mode == "playing" or mode == "choice":
		if _hitstop > 0.0:
			_hitstop = maxf(0.0, _hitstop - dt)
			if _hitstop <= 0.0 and _ult != null: _ult.set_hold(false)
		else:
			step_dt = dt
	if _hitstop > 0.0 and _ult != null: _ult.set_hold(true)
	sw["t"] = float(sw.t) + step_dt
	var t := float(sw.t)
	var dur := float(sw.dur)
	# the demon: in over 0.35 s, out over 0.4 s once the sweep ends (the core does not wait for it)
	var out_from := float(sw.ended_at) if float(sw.ended_at) >= 0.0 else dur
	_demon = ramp_t(t, 0.0, DEMON_IN) * (1.0 - ramp_t(t, out_from, out_from + DEMON_OUT))
	_ult.update(t, step_dt)
	# the freeze rim and the arc's dim are the element module's too: it writes them through these two fields
	_freeze = float(_ult.freeze_value())
	_shatter = float(_ult.shatter_value())
	_scrim_hold = float(_ult.scrim_value())
	if _kick_hold > 0.0 and t - _last_kick_t >= 0.1:
		_last_kick_t = t
		kick(_kick_hold)
		_kick_hold = 0.0
	if t >= dur + float(sw.tail):
		sw = {}
		_ult.finish()
		_reset_scr()
		_freeze = 0.0
		_shatter = 0.0

func _start_flights() -> void:
	if _flight == null: return
	var from := PackedVector2Array()
	var cache := _orb_cache
	var stride := maxi(1, cache.size() / 40)
	var i := 0
	while i < cache.size() and from.size() < 40:
		from.append(cache[i]); i += stride
	for at in _kill_cache:
		if from.size() >= FLIGHT_ORBS: break
		from.append(at)
	var made := 0
	for at in from:
		_flights.append(at.x); _flights.append(at.y)
		_flights.append(hash1(float(made) * 1.7) * 0.28)
		_flights.append(0.0); _flights.append(0.0); _flights.append(0.0)
		made += 1
	stats.flights += made
	_kill_cache = PackedVector2Array()

func _update_flights(run: RefCounted, dt: float) -> void:
	# keep the freshest orbs' places while a sweep runs (the vacuum empties the list on the sweep's last tick)
	if not sw.is_empty() and run.orbs.size() > 0:
		var fresh := PackedVector2Array()
		for orb in run.orbs:
			fresh.append(orb.position)
		_orb_cache = fresh
	var mm := _flight.multimesh
	var n := _flights.size() / 6
	if n == 0:
		if mm.visible_instance_count != 0: mm.visible_instance_count = 0
		return
	_flight_target = Vector3(hero.x, 1.1, hero.y)
	var live := 0
	var orb_count := 0
	var puff_count := 0
	var keep := PackedFloat32Array()
	for k in n:
		var o := k * 6
		var kind := int(_flights[o + 4])
		var age := _flights[o + 3] + dt
		var delay := _flights[o + 2]
		_flights[o + 3] = age
		var local := age - delay
		var life := 0.42 if kind == 0 else 0.22
		if local >= life: continue
		var slot := 0
		if kind == 0:
			if orb_count >= FLIGHT_ORBS: continue
			slot = orb_count; orb_count += 1
		else:
			if puff_count >= FLIGHT_PUFFS: continue
			slot = FLIGHT_ORBS + puff_count; puff_count += 1
		for q in 6: keep.append(_flights[o + q])
		if local < 0.0:
			mm.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
			continue
		var f := local / life
		var src := Vector3(_flights[o], 0.5, _flights[o + 1])
		if kind == 0:
			var e := f * f * (3.0 - 2.0 * f)
			var pos := src.lerp(_flight_target, e) + Vector3(0, sin(e * PI) * 1.6, 0)
			var s := lerpf(1.0, 0.5, f)
			mm.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3.ONE * s), pos))
			mm.set_instance_color(slot, Color(ORB_COLOR.r, ORB_COLOR.g, ORB_COLOR.b, 0.95 * (1.0 - f * 0.4)))
		else:
			var s2 := lerpf(0.7, 2.2, f)
			mm.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3.ONE * s2), src + Vector3(0, 0.4 + f * 0.6, 0)))
			mm.set_instance_color(slot, Color(tint.r, tint.g, tint.b, 0.55 * (1.0 - f)))
		live += 1
	_flights = keep
	# unused slots shrink to nothing; draw everything up to the highest used slot
	for slot in range(orb_count, FLIGHT_ORBS):
		mm.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	for slot in range(FLIGHT_ORBS + puff_count, FLIGHT_ORBS + FLIGHT_PUFFS):
		mm.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	mm.visible_instance_count = (FLIGHT_ORBS + FLIGHT_PUFFS) if live > 0 else 0

# ---- lights, label

func _set_light(index: int, at: Vector3, color: Color, energy: float, range_: float, seconds: float = 0.0) -> void:
	if index < 0 or index >= _lights.size(): return
	var light := _lights[index]
	if flash_scale <= 0.0: energy *= 0.4
	light.global_position = at
	light.light_color = color
	light.omni_range = range_
	light.light_energy = energy
	light.visible = energy > 0.02
	if seconds > 0.0:
		_light_life[index] = seconds
		_light_total[index] = seconds
		_light_energy[index] = energy
	else:
		_light_life[index] = 0.0
	var live := 0
	for l in _lights:
		if l.visible: live += 1
	stats.lights_peak = maxi(int(stats.lights_peak), live)

func _update_lights(dt: float) -> void:
	for i in _lights.size():
		if _light_life[i] > 0.0:
			_light_life[i] = maxf(0.0, _light_life[i] - dt)
			var f := _light_life[i] / maxf(0.001, _light_total[i])
			_lights[i].light_energy = _light_energy[i] * f * f
			if _light_life[i] <= 0.0:
				_lights[i].visible = false
	if sw.is_empty() and _cut.is_empty():
		for i in _lights.size():
			if _light_life[i] <= 0.0 and _lights[i].visible:
				_lights[i].visible = false
				_lights[i].light_energy = 0.0

## A11 6: the end-of-sweep number stands over the hero's head (the foot of the number KILL_RISE above the hood's top, the small word under it), follows the hero,
## pops 1.25 -> 1.00 in 0.12 s, stays 1.6 s, sinks a little as it goes out.
func _update_label(dt: float) -> void:
	if _kill_label == null or _kill_label_age < 0.0: return
	_kill_label_age += dt
	var a := _kill_label_age
	var pop := 1.0 + 0.25 * (1.0 - ramp_t(a, 0.0, 0.12))
	var alpha := ramp_t(a, 0.0, 0.06) * (1.0 - ramp_t(a, 1.2, 1.6))
	var size_ := _screen.size if _screen != null and _screen.size.y > 1.0 else Vector2(1600.0, 900.0)
	var k := size_.y / 900.0
	var hu := hero_uv()
	var cx := hu.x * size_.x if hu.x >= 0.0 else size_.x * 0.5
	var top_y := (hu.y - DescentBand.HERO_TOP_ABOVE_UV) * size_.y if hu.x >= 0.0 else size_.y * 0.35
	var sink := 14.0 * k * ramp_t(a, 1.2, 1.6)
	_kill_tail.position = Vector2(cx - _kill_tail.size.x * 0.5, top_y - 44.0 * k + sink)
	_kill_label.position = Vector2(cx - _kill_label.size.x * 0.5, top_y - 44.0 * k - _kill_label.size.y + 6.0 * k + sink)
	_kill_label.pivot_offset = Vector2(_kill_label.size.x * 0.5, _kill_label.size.y)
	_kill_label.scale = Vector2.ONE * (1.0 if reduced_motion else pop)
	_kill_label.modulate = Color(1, 1, 1, alpha)
	_kill_tail.modulate = Color(1, 1, 1, alpha)
	if a >= 1.6:
		_kill_label.visible = false
		_kill_tail.visible = false
		_kill_label_age = -1.0
