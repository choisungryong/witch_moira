extends RefCounted
## The descent's screen (D15 A, D14 4.3-4.4, D24 4.8 / 5-7 / 12.2): the gauge's edge aura, the cut-in, the demon in the sky layer,
## and the sweep of each element (ember_ult.gd / frost_ult.gd / arc_ult.gd in fx/descent/).
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
##   cutin_short    the 0.5 s cut-in every time ("짧게만")
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

const SLOT_PREFIX := "illustration.cutin.descent."
const SKY_SLOT_PREFIX := "illustration.sky.descent."
## Until the sky pictures exist the grace screen's demon (a full-length figure on a dark ground, the same one per element) is used, upper body only.
const GRACE_SLOT_PREFIX := "ui.grace.demon."
const ELEMENT_ID := {"ember": 0.0, "frost": 1.0, "arc": 2.0}
## Where the bust sits and which way it comes in from, per element (the art decides the final look).
const SLIDE_DIR := {"ember": Vector2(1, 0), "frost": Vector2(-1, 0), "arc": Vector2(0, 0.6)}
const ART_FOCUS_Y := {"ember": 0.44, "frost": 0.42, "arc": 0.40}
## Where the demon stands in the sky layer (uv x): away from where the effect comes in (rocks from the upper left, wind from the upper right).
const SKY_X := {"ember": 0.72, "frost": 0.28, "arc": 0.5}
## The sweep's tail after its last tick (the scorch of the rocks stays 3 s).
const TAIL := {"ember": 3.2, "frost": 3.0, "arc": 1.3}
const DEFAULT_AREA := {"right_deg": -38.2, "half_w_m": 17.3, "half_h_m": 13.4}

## The cut-in's own clock, in the seconds of the long one (D14 4.4); the short one scales all of it by SHORT_SECONDS / LONG_SECONDS.
const LONG_SECONDS := 0.9
const SHORT_SECONDS := 0.5
const T_DARK_END := 0.10
const T_SLIT_END := 0.20
const T_OPEN_END := 0.36
const T_SLIDE_END := 0.50
const T_FLASH_PEAK := 0.52
const T_FLASH_END := 0.62
const T_RELEASE := 0.70
const T_END := 0.90
## The app's own watchdog is longer than this; the picture never holds the core for more than this wall time.
const WATCHDOG_SECONDS := 2.0

const GROUND_Y := 0.045
const FLIGHT_ORBS := 64
const FLIGHT_PUFFS := 32
const ORB_COLOR := Color("8fe3c0")
const MAX_LIGHTS := 3
const MAX_PARTICLES := 800
const HITSTOP_SECONDS := 0.08
const DEMON_IN := 0.35
const DEMON_OUT := 0.4

var cutin_short := false
var reduced_motion := false
var flash_scale := 1.0
var shake_scale := 1.0
var numbers_on := true
var low := false

var view: Node3D
var stats := {"cutins": 0, "sweeps": 0, "bolts": 0, "bolts_dropped": 0, "peak_bolts": 0, "flights": 0, "lights_peak": 0, "particles": 0,
	"rocks": 0, "impacts": 0, "pulses": 0, "breaks": 0, "kicks": 0, "peak_alpha_layers": 0}

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
var _flight: MultiMeshInstance3D
var _lights: Array[OmniLight3D] = []
var _light_life := PackedFloat32Array([0.0, 0.0, 0.0])
var _light_total := PackedFloat32Array([0.1, 0.1, 0.1])
var _light_energy := PackedFloat32Array([0.0, 0.0, 0.0])
var _light_next := 0
var _ult: RefCounted = null
var _art: Texture2D = null
var _art_checked := false
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
	_art = null
	_art_checked = false
	_sky_art_checked = false
	_reset_scr()
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
	return {"built": _built, "element": _element, "cutin": not _cut.is_empty(), "cut_t": float(_cut.get("t", 0.0)), "cut_dur": float(_cut.get("dur", 0.0)),
		"sweep": not sw.is_empty(), "sweep_t": float(sw.get("t", 0.0)), "aura": _aura, "bolts": int(_ult.live_bolts()) if _ult != null and _element == "arc" else 0,
		"release_due": _release_due, "demon": _demon, "low": low, "stats": stats.duplicate()}

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

func _on_called(event: Dictionary) -> void:
	_ensure_built(String(event.element))
	if not _built: return
	var short := cutin_short or String(event.get("variant", "long")) == "short"
	var dur := SHORT_SECONDS if short else LONG_SECONDS
	_cut = {"t": 0.0, "dur": dur, "release_at": dur * T_RELEASE / T_END, "released": false, "wall": 0.0, "short": short}
	_release_due = false
	stats.cutins += 1
	_load_art()

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
		_kill_label.text = Loc.tn("descent.kills", shown)
		_kill_label_age = 0.0
		_kill_label.visible = true

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
		holder = null; _layer = null; _screen = null; _screen_mat = null; _kill_label = null; _flight = null; _ult = null
		_lights.clear()
		_built = false
		_shown = false

func _build() -> void:
	holder = Node3D.new(); holder.name = "DescentFx"
	view.add_child(holder)
	# Orb flights and the puffs of wiped shots: one MultiMesh.
	var spark := QuadMesh.new(); spark.size = Vector2(0.34, 0.34)
	var spark_material := StandardMaterial3D.new()
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
	_kill_label = Label.new(); _kill_label.name = "Kills"
	_kill_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kill_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_kill_label.position = Vector2(-300, 150)
	_kill_label.size = Vector2(600, 90)
	_kill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kill_label.add_theme_font_override("font", Loc.font("heading"))
	_kill_label.add_theme_font_size_override("font_size", 54)
	_kill_label.add_theme_color_override("font_color", tint.lerp(Color.WHITE, .35))
	_kill_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, .9))
	_kill_label.add_theme_constant_override("outline_size", 8)
	_kill_label.visible = false
	_layer.add_child(_kill_label)
	_screen_mat.set_shader_parameter("tint", tint)
	_screen_mat.set_shader_parameter("element_id", float(ELEMENT_ID.get(_element, 0.0)))
	_screen_mat.set_shader_parameter("slide_dir", SLIDE_DIR.get(_element, Vector2(1, 0)))
	_screen_mat.set_shader_parameter("art_focus_y", float(ART_FOCUS_Y.get(_element, 0.44)))
	_screen_mat.set_shader_parameter("demon_x", float(SKY_X.get(_element, 0.7)))
	_screen_mat.set_shader_parameter("low", 1.0 if low else 0.0)
	_built = true
	_warm = 5

func _load_art() -> void:
	if _art_checked: return
	_art_checked = true
	var slot := SLOT_PREFIX + _element
	if AssetSlots.has_slot(slot) and not AssetSlots.is_planned(slot):
		_art = AssetSlots.texture(slot)
		# A placeholder checkerboard is never shown: it means the file was missing.
		if slot in AssetSlots.missing(): _art = null
	_screen_mat.set_shader_parameter("art", _art)
	_screen_mat.set_shader_parameter("has_art", 1.0 if _art != null else 0.0)

## The demon of the sky layer: the picture of the slot illustration.sky.descent.<element> when there is one, else the code silhouette.
func _load_sky_art() -> void:
	if _sky_art_checked or _screen_mat == null: return
	_sky_art_checked = true
	var slot := SKY_SLOT_PREFIX + _element
	var tex: Texture2D = null
	if AssetSlots.has_slot(slot) and not AssetSlots.is_planned(slot):
		tex = AssetSlots.texture(slot)
		if slot in AssetSlots.missing(): tex = null
	if tex == null and not ("--chapter1-descent-sky=silhouette" in OS.get_cmdline_user_args()):
		var grace := GRACE_SLOT_PREFIX + _element
		if AssetSlots.has_slot(grace) and not AssetSlots.is_planned(grace):
			tex = AssetSlots.texture(grace)
			if grace in AssetSlots.missing(): tex = null
	_screen_mat.set_shader_parameter("sky_art", tex)
	_screen_mat.set_shader_parameter("has_sky_art", 1.0 if tex != null else 0.0)

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
	_update_cutin(run, mode, state, dt, delta)
	_update_warm()
	_update_sweep(run, mode, dt)
	_update_flights(run, dt)
	_update_lights(dt)
	_update_label(dt)
	_push_screen()

func _hide_all() -> void:
	_shown = false
	if _screen != null: _screen.visible = false
	if _kill_label != null: _kill_label.visible = false
	if _ult != null: _ult.hide_all()

func _update_cutin(run: RefCounted, mode: String, state: String, dt: float, wall_dt: float) -> void:
	if _cut.is_empty(): return
	# the cut-in is shown only while the core holds (or just after it let go, for the picture's leaving)
	if mode == "descent" or (bool(_cut.released) and mode == "playing"):
		_cut["t"] = float(_cut.t) + dt
		_cut["wall"] = float(_cut.wall) + wall_dt
	if mode == "descent" and not bool(_cut.released) and (float(_cut.t) >= float(_cut.release_at) or float(_cut.wall) >= WATCHDOG_SECONDS):
		_cut["released"] = true
		_release_due = true
	if state != "hold" and not bool(_cut.released) and mode == "playing":
		# the core is no longer holding (someone else released it): end the picture
		_cut["released"] = true
	if float(_cut.t) >= float(_cut.dur):
		_cut = {}
		return

func _cut_uniforms() -> Dictionary:
	var u := {"scrim": 0.0, "rift": 0.0, "slide": 0.0, "retract": 0.0, "flash": 0.0}
	if _cut.is_empty(): return u
	var tt := float(_cut.t) / float(_cut.dur) * T_END
	u.scrim = ramp_t(tt, 0.0, T_DARK_END) * (1.0 - ramp_t(tt, T_RELEASE, T_END - 0.03))
	if tt < T_SLIT_END: u.rift = ramp_t(tt, T_DARK_END, T_SLIT_END) * 0.2
	else: u.rift = 0.2 + 0.8 * ease_out(ramp_t(tt, T_SLIT_END, T_OPEN_END))
	u.slide = ramp_t(tt, T_SLIT_END, T_SLIDE_END)
	u.retract = ease_out(ramp_t(tt, T_RELEASE, T_END))
	if not reduced_motion and flash_scale > 0.0:
		var up := ramp_t(tt, T_SLIDE_END, T_FLASH_PEAK)
		var down := 1.0 - ramp_t(tt, T_FLASH_PEAK, T_FLASH_END)
		u.flash = minf(up, down) * flash_scale
	if reduced_motion: u.slide = 1.0
	return u

func _push_screen() -> void:
	var cu := _cut_uniforms()
	var cut_on := not _cut.is_empty()
	var scrim := maxf(float(cu.scrim), _scrim_hold)
	var sweeping := not sw.is_empty()
	var any := _aura > 0.005 or _aura_pulse > 0.005 or cut_on or _freeze > 0.005 or _pulse > 0.005 or scrim > 0.005 or sweeping or _warm > 0 or float(scr.whiteout) > 0.005
	_shown = _shown or any
	_screen.visible = any
	if not any: return
	var size_ := _screen.size
	_screen_mat.set_shader_parameter("aspect", size_.x / maxf(1.0, size_.y))
	_screen_mat.set_shader_parameter("time", _clock)
	_screen_mat.set_shader_parameter("aura", _aura * (1.0 if flash_scale > 0.0 else 0.6))
	_screen_mat.set_shader_parameter("aura_pulse", _aura_pulse * flash_scale)
	_screen_mat.set_shader_parameter("scrim", scrim)
	_screen_mat.set_shader_parameter("rift", cu.rift)
	_screen_mat.set_shader_parameter("slide", cu.slide)
	_screen_mat.set_shader_parameter("retract", cu.retract)
	_screen_mat.set_shader_parameter("flash", cu.flash)
	_screen_mat.set_shader_parameter("slide_dir", Vector2.ZERO if reduced_motion else SLIDE_DIR.get(_element, Vector2(1, 0)))
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

func _update_warm() -> void:
	if _ult == null: return
	if _warm > 0 and sw.is_empty() and _cut.is_empty():
		_warm -= 1
		_ult.warm(true)
		# the merged kill number's glyphs (a CJK heading font with an outline) are rasterised on first use: a 400 ms hitch at the sweep's last tick
		if _kill_label != null and _kill_label_age < 0.0:
			_kill_label.text = Loc.tn("descent.kills", 8888)
			_kill_label.modulate = Color(1, 1, 1, 0.01)
			_kill_label.visible = true
		if _warm == 0:
			_ult.warm(false)
			if _kill_label != null and _kill_label_age < 0.0: _kill_label.visible = false
	elif _warm > 0:
		_warm = 0
		_ult.warm(false)
		if _kill_label != null and _kill_label_age < 0.0: _kill_label.visible = false

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

func _update_label(dt: float) -> void:
	if _kill_label == null or _kill_label_age < 0.0: return
	_kill_label_age += dt
	var a := _kill_label_age
	var pop := 1.0 + 0.35 * (1.0 - ramp_t(a, 0.0, 0.18))
	var alpha := ramp_t(a, 0.0, 0.08) * (1.0 - ramp_t(a, 1.1, 1.6))
	_kill_label.pivot_offset = _kill_label.size * 0.5
	_kill_label.scale = Vector2.ONE * (1.0 if reduced_motion else pop)
	_kill_label.modulate = Color(1, 1, 1, alpha)
	if a >= 1.6:
		_kill_label.visible = false
		_kill_label_age = -1.0
