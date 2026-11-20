extends RefCounted
## The descent's screen (D15 A, D14 4.3-4.4, U-2): the gauge's edge aura, the cut-in, and the sweep of each element.
## It only READS the core: descent_view() and the events descent_ready / descent_called / descent_released / descent_strike /
## descent_end / orb_vacuum, plus the orbs and the hero's place. It never writes to the core. The two calls that do
## (request_descent, release_descent) are the app's: this file only says "the cut-in is over" through take_release().
##
## A run whose descent is off has no node from this file at all: sync() returns on {"enabled":false} before _build() ever runs.
##
## Budget (RS2 notes, D14): ordinary alpha on the single full-screen control (no additive full-screen layer), no effect light during
## the cut-in, two lights during the sweep, and at most ~200 particles of this file in a run (one element's pool is built).
## Colours are the element's own; the crimson of an enemy's attack is never used. No speed lines.
##
## Settings (variables here; a settings screen and settings.cfg do not exist yet, so the app sets them from launch arguments):
##   cutin_short    the 0.5 s cut-in every time ("짧게만")
##   reduced_motion no slide, no shake, no flash (the picture only fades)
##   flash_scale    0 off, 0.5 weak, 1 full: the flash of the gesture, the tint washes, the aura swell
##   shake_scale    0 off .. 1: the camera impulses
##   numbers_on     the one merged kill number after a sweep
const Palette = preload("res://chapter1/view/hud/palette.gd")
const Loc = preload("res://chapter1/view/loc.gd")
const AssetSlots = preload("res://chapter1/view/assets/asset_slots.gd")
const SCREEN_SHADER = preload("res://chapter1/view/fx/descent_screen.gdshader")
const WALL_SHADER = preload("res://chapter1/view/fx/descent_wall.gdshader")
const GROUND_SHADER = preload("res://chapter1/view/fx/descent_ground.gdshader")

const SLOT_PREFIX := "illustration.cutin.descent."
const ELEMENT_ID := {"ember": 0.0, "frost": 1.0, "arc": 2.0}
## Where the bust sits and which way it comes in from, per element (the art decides the final look).
const SLIDE_DIR := {"ember": Vector2(1, 0), "frost": Vector2(-1, 0), "arc": Vector2(0, 0.6)}
const ART_FOCUS_Y := {"ember": 0.44, "frost": 0.42, "arc": 0.40}

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

const SCREEN_TILT := 0.7314          ## sin of the camera's look-down angle (46.9 degrees): ground depth -> screen height
const GROUND_Y := 0.045
const FLIGHT_ORBS := 64
const FLIGHT_PUFFS := 32
const BOLT_LIFE := 0.22
const MAX_BOLTS := 40
const ORB_COLOR := Color("8fe3c0")

var cutin_short := false
var reduced_motion := false
var flash_scale := 1.0
var shake_scale := 1.0
var numbers_on := true

var view: Node3D
var stats := {"cutins": 0, "sweeps": 0, "bolts": 0, "bolts_dropped": 0, "peak_bolts": 0, "flights": 0, "lights_peak": 0, "particles": 0}

var _built := false
var _shown := false
var _element := ""
var _tint := Color.WHITE
var _last_seq := -1
var _clock := 0.0
var _release_due := false
var _holder: Node3D
var _layer: CanvasLayer
var _screen: ColorRect
var _screen_mat: ShaderMaterial
var _kill_label: Label
var _ground: MeshInstance3D
var _ground_mat: ShaderMaterial
var _wall: MeshInstance3D
var _wall_mat: ShaderMaterial
var _bolt_mesh: ImmediateMesh
var _bolt_node: MeshInstance3D
var _flight: MultiMeshInstance3D
var _lights: Array[OmniLight3D] = []
var _light_life := PackedFloat32Array([0.0, 0.0])
var _light_total := PackedFloat32Array([0.1, 0.1])
var _light_energy := PackedFloat32Array([0.0, 0.0])
var _light_next := 0
var _wall_particles: GPUParticles3D
var _burst_particles: GPUParticles3D
var _burst_material: ParticleProcessMaterial
var _art: Texture2D = null
var _art_checked := false

var _aura := 0.0
var _aura_pulse := 0.0
var _pulse := 0.0
var _freeze := 0.0
var _shatter := 0.0
var _scrim_hold := 0.0
var _cut: Dictionary = {}
var _sw: Dictionary = {}
var _bolts: Array[Dictionary] = []
var _orb_cache := PackedVector2Array()
var _kill_cache := PackedVector2Array()
var _flights := PackedFloat32Array()      ## per flight: x, z, delay, age, kind(0 orb, 1 puff), unused
var _flight_target := Vector3.ZERO
var _kill_label_age := -1.0
var _kick_clock := 0.0
var _hero := Vector2.ZERO

func setup(owner_view: Node3D) -> void:
	view = owner_view

## A new run: everything this file shows is dropped. No node is made here.
func reset() -> void:
	_last_seq = -1
	_clock = 0.0
	_release_due = false
	_cut = {}
	_sw = {}
	_aura = 0.0
	_aura_pulse = 0.0
	_pulse = 0.0
	_freeze = 0.0
	_shatter = 0.0
	_scrim_hold = 0.0
	_bolts.clear()
	_orb_cache = PackedVector2Array()
	_kill_cache = PackedVector2Array()
	_flights = PackedFloat32Array()
	_kill_label_age = -1.0
	_element = ""
	_art = null
	_art_checked = false
	if _built:
		_hide_all()
		if _flight != null: _flight.multimesh.visible_instance_count = 0
		for light in _lights:
			light.visible = false
			light.light_energy = 0.0
		_light_life.fill(0.0)
		if _wall_particles != null: _wall_particles.emitting = false
		_free_built()

## true once, when the cut-in has run to the moment the sweep should start. The app then calls release_descent().
func take_release() -> bool:
	var due := _release_due
	_release_due = false
	return due

## A read-only digest for tools and tests.
func status() -> Dictionary:
	return {"built": _built, "element": _element, "cutin": not _cut.is_empty(), "cut_t": float(_cut.get("t", 0.0)), "cut_dur": float(_cut.get("dur", 0.0)),
		"sweep": not _sw.is_empty(), "sweep_t": float(_sw.get("t", 0.0)), "aura": _aura, "bolts": _bolts.size(), "release_due": _release_due, "stats": stats.duplicate()}

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
	if not _built: return
	var el := String(event.element)
	var center: Vector2 = event.center
	var heading: Vector2 = event.get("heading", Vector2.ZERO)
	if heading.length_squared() < 0.0001: heading = Vector2(0.786, -0.618)
	var ticks := int(event.sweep_ticks)
	var tail := 2.6 if el == "ember" else (0.7 if el == "frost" else 0.35)
	_sw = {"element": el, "center": center, "reach": float(event.reach_m), "heading": heading.normalized(), "dur": float(ticks) / 60.0, "t": 0.0, "tail": tail,
		"broke": false, "bt": 0.0, "rounds": 0, "kick": 0.0, "kills": 0}
	_kill_cache = PackedVector2Array()
	stats.sweeps += 1
	_ground.position = Vector3(center.x, GROUND_Y, center.y)
	var reach := float(event.reach_m)
	(_ground.mesh as PlaneMesh).size = Vector2(reach * 2.0 + 4.0, reach * 2.0 + 4.0)
	_ground_mat.set_shader_parameter("reach", reach)
	_ground_mat.set_shader_parameter("heading", heading.normalized())
	_ground_mat.set_shader_parameter("mode", 0 if el == "ember" else (1 if el == "frost" else 0))
	_ground_mat.set_shader_parameter("progress", 0.0)
	_ground_mat.set_shader_parameter("shatter", 0.0)
	_ground_mat.set_shader_parameter("fade", 1.0)
	_ground.visible = el != "arc"
	_wall.visible = el == "ember"
	# the shots that were wiped: small flashes where they were
	var cleared: Array = event.get("cleared_positions", [])
	var count := mini(cleared.size(), FLIGHT_PUFFS)
	for i in count:
		var at: Vector2 = cleared[i]
		_flights.append(at.x); _flights.append(at.y); _flights.append(0.0); _flights.append(0.0); _flights.append(1.0); _flights.append(0.0)
	if el == "ember" and _wall_particles != null:
		_wall_particles.emitting = true
	if el == "arc": _scrim_hold = 0.28

func _on_strike(event: Dictionary) -> void:
	if _sw.is_empty() or not _built: return
	var phase := String(event.phase)
	var positions: Array = event.get("positions", [])
	for pos in positions:
		if _kill_cache.size() < 48: _kill_cache.append(pos)
	match phase:
		"break": _do_break(positions)
		"bolt": _do_bolts(positions)
		"sweep_end": pass

func _on_end(event: Dictionary) -> void:
	if not _built: return
	_sw["kills"] = int(event.get("kills", 0))
	_sw["ended"] = true
	_kick(0.25)
	if numbers_on and int(event.get("kills", 0)) > 0 and _kill_label != null:
		_kill_label.text = Loc.tn("descent.kills", int(event.kills))
		_kill_label_age = 0.0
		_kill_label.visible = true

# ---------------------------------------------------------------- build (lazy)

func _ensure_built(element: String) -> void:
	if _built or view == null: return
	_element = element
	_tint = Palette.element_color(element, Palette.BRASS)
	_build()

func _free_built() -> void:
	# The nodes stay for the next run; only the element-specific pieces are reset (the element can differ in a new run).
	if _built:
		if _holder != null: _holder.queue_free()
		if _layer != null: _layer.queue_free()
		_holder = null; _layer = null; _screen = null; _screen_mat = null; _kill_label = null
		_ground = null; _wall = null; _bolt_node = null; _flight = null; _wall_particles = null; _burst_particles = null
		_lights.clear()
		_built = false
		_shown = false

func _build() -> void:
	_holder = Node3D.new(); _holder.name = "DescentFx"
	view.add_child(_holder)
	# Floor trace (ember soot, frost crystals): under the enemies' warnings.
	_ground = MeshInstance3D.new(); _ground.name = "DescentGround"
	var plane := PlaneMesh.new(); plane.size = Vector2(30, 30)
	_ground.mesh = plane
	_ground_mat = ShaderMaterial.new(); _ground_mat.shader = GROUND_SHADER
	_ground_mat.render_priority = -5
	_ground.material_override = _ground_mat
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ground.visible = false
	_holder.add_child(_ground)
	# The wall of fire: a camera-facing quad.
	_wall = MeshInstance3D.new(); _wall.name = "DescentWall"
	var quad := QuadMesh.new(); quad.size = Vector2(7, 24)
	_wall.mesh = quad
	_wall_mat = ShaderMaterial.new(); _wall_mat.shader = WALL_SHADER
	_wall_mat.render_priority = 6
	_wall.material_override = _wall_mat
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wall.extra_cull_margin = 40.0
	_wall.visible = false
	_holder.add_child(_wall)
	# Bolts.
	_bolt_mesh = ImmediateMesh.new()
	_bolt_node = MeshInstance3D.new(); _bolt_node.name = "DescentBolts"
	_bolt_node.mesh = _bolt_mesh
	var bolt_material := StandardMaterial3D.new()
	bolt_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bolt_material.vertex_color_use_as_albedo = true
	bolt_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bolt_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bolt_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	bolt_material.render_priority = 7
	_bolt_node.material_override = bolt_material
	_bolt_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt_node.extra_cull_margin = 60.0
	_bolt_node.visible = false
	_holder.add_child(_bolt_node)
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
	_holder.add_child(_flight)
	# Two lights for the whole sweep (the cut-in uses none).
	for i in 2:
		var light := OmniLight3D.new(); light.name = "DescentLight%d" % i
		light.shadow_enabled = false
		light.omni_range = 8.0
		light.light_color = _tint
		light.light_energy = 0.0
		light.visible = false
		_holder.add_child(light)
		_lights.append(light)
	_build_particles()
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
	_kill_label.add_theme_color_override("font_color", _tint.lerp(Color.WHITE, .35))
	_kill_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, .9))
	_kill_label.add_theme_constant_override("outline_size", 8)
	_kill_label.visible = false
	_layer.add_child(_kill_label)
	_screen_mat.set_shader_parameter("tint", _tint)
	_screen_mat.set_shader_parameter("element_id", float(ELEMENT_ID.get(_element, 0.0)))
	_screen_mat.set_shader_parameter("slide_dir", SLIDE_DIR.get(_element, Vector2(1, 0)))
	_screen_mat.set_shader_parameter("art_focus_y", float(ART_FOCUS_Y.get(_element, 0.44)))
	_ground_mat.set_shader_parameter("tint", _tint)
	_built = true

func _particle_quad(additive: bool) -> QuadMesh:
	var mesh := QuadMesh.new(); mesh.size = Vector2(0.3, 0.3)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive: material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_keep_scale = true
	mesh.material = material
	return mesh

func _ramp(stops: Array) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(stops.map(func(s): return float(s[0])))
	gradient.colors = PackedColorArray(stops.map(func(s): return s[1]))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture

func _build_particles() -> void:
	var aabb := AABB(Vector3(-40, -2, -40), Vector3(80, 16, 80))
	_burst_material = ParticleProcessMaterial.new()
	_burst_particles = GPUParticles3D.new(); _burst_particles.name = "DescentBurst"
	_burst_particles.one_shot = true
	_burst_particles.explosiveness = 1.0
	_burst_particles.emitting = false
	_burst_particles.local_coords = false
	_burst_particles.visibility_aabb = aabb
	_burst_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match _element:
		"frost":
			_burst_particles.amount = 192; _burst_particles.lifetime = 0.95
			_burst_material.direction = Vector3(0, 1, 0); _burst_material.spread = 75.0
			_burst_material.initial_velocity_min = 3.0; _burst_material.initial_velocity_max = 9.0
			_burst_material.gravity = Vector3(0, -16, 0)
			_burst_material.scale_min = 0.5; _burst_material.scale_max = 1.5
			_burst_material.color_ramp = _ramp([[0.0, Color(0.95, 1.0, 1.0, 0.95)], [0.5, Color(0.62, 0.9, 0.95, 0.7)], [1.0, Color(0.4, 0.75, 0.9, 0.0)]])
			_burst_particles.draw_pass_1 = _particle_quad(false)
		"arc":
			_burst_particles.amount = 96; _burst_particles.lifetime = 0.38
			_burst_material.direction = Vector3(0, 0.35, 0); _burst_material.spread = 100.0
			_burst_material.initial_velocity_min = 3.0; _burst_material.initial_velocity_max = 10.0
			_burst_material.gravity = Vector3(0, -8, 0)
			_burst_material.scale_min = 0.3; _burst_material.scale_max = 0.9
			_burst_material.color_ramp = _ramp([[0.0, Color(1, 1, 1, 1)], [0.4, Color(0.72, 0.8, 1.0, 0.85)], [1.0, Color(0.42, 0.5, 1.0, 0.0)]])
			_burst_particles.draw_pass_1 = _particle_quad(true)
		_:
			_burst_particles.amount = 48; _burst_particles.lifetime = 0.8
			_burst_material.direction = Vector3(0, 1, 0); _burst_material.spread = 60.0
			_burst_material.initial_velocity_min = 2.0; _burst_material.initial_velocity_max = 6.0
			_burst_material.gravity = Vector3(0, -3, 0)
			_burst_material.scale_min = 0.4; _burst_material.scale_max = 1.0
			_burst_material.color_ramp = _ramp([[0.0, Color(1, 0.85, 0.5, 1)], [0.5, Color(1, 0.45, 0.12, 0.8)], [1.0, Color(0.2, 0.08, 0.04, 0)]])
			_burst_particles.draw_pass_1 = _particle_quad(true)
	_burst_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	_burst_material.emission_point_count = 1
	_burst_particles.process_material = _burst_material
	_holder.add_child(_burst_particles)
	stats.particles = _burst_particles.amount
	if _element == "ember":
		var wall_material := ParticleProcessMaterial.new()
		wall_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		wall_material.emission_box_extents = Vector3(0.45, 0.1, 9.0)
		wall_material.direction = Vector3(0, 1, 0); wall_material.spread = 35.0
		wall_material.initial_velocity_min = 1.5; wall_material.initial_velocity_max = 5.0
		wall_material.gravity = Vector3(0, 1.2, 0)
		wall_material.damping_min = 0.3; wall_material.damping_max = 1.0
		wall_material.scale_min = 0.3; wall_material.scale_max = 0.8
		wall_material.color_ramp = _ramp([[0.0, Color(1, 0.9, 0.55, 1)], [0.45, Color(1, 0.5, 0.14, 0.8)], [1.0, Color(0.25, 0.08, 0.03, 0)]])
		_wall_particles = GPUParticles3D.new(); _wall_particles.name = "DescentEmbers"
		_wall_particles.amount = 140; _wall_particles.lifetime = 1.1
		_wall_particles.local_coords = false
		_wall_particles.emitting = false
		_wall_particles.visibility_aabb = aabb
		_wall_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_wall_particles.process_material = wall_material
		_wall_particles.draw_pass_1 = _particle_quad(true)
		_holder.add_child(_wall_particles)
		stats.particles += 140

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
	_clock += delta
	var mode := String(run.mode)
	_hero = run.hero.position if not run.hero.is_empty() else Vector2.ZERO
	var state := String(v.state)
	# The edge aura: only while the gauge is full and nothing else is going on.
	var aura_target := 1.0 if state == "ready" and mode == "playing" else 0.0
	_aura = move_toward(_aura, aura_target, dt * 2.0)
	_aura_pulse = maxf(0.0, _aura_pulse - dt * 1.2)
	_pulse = maxf(0.0, _pulse - dt * 4.5)
	_update_cutin(run, mode, state, dt, delta)
	_update_sweep(run, mode, dt)
	_update_bolts(dt)
	_update_flights(run, dt)
	_update_lights(dt)
	_update_label(dt)
	_push_screen()

func _hide_all() -> void:
	_shown = false
	if _screen != null: _screen.visible = false
	if _ground != null: _ground.visible = false
	if _wall != null: _wall.visible = false
	if _bolt_node != null: _bolt_node.visible = false
	if _kill_label != null: _kill_label.visible = false

func _kick(strength: float) -> void:
	if reduced_motion or shake_scale <= 0.0: return
	var world: Variant = view.get("world")
	if world != null and world.has_method("kick_camera"): world.kick_camera(strength * shake_scale)

func _ease_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)

func _ramp_t(t: float, a: float, b: float) -> float:
	return clampf((t - a) / maxf(0.0001, b - a), 0.0, 1.0)

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
	u.scrim = _ramp_t(tt, 0.0, T_DARK_END) * (1.0 - _ramp_t(tt, T_RELEASE, T_END - 0.03))
	if tt < T_SLIT_END: u.rift = _ramp_t(tt, T_DARK_END, T_SLIT_END) * 0.2
	else: u.rift = 0.2 + 0.8 * _ease_out(_ramp_t(tt, T_SLIT_END, T_OPEN_END))
	u.slide = _ramp_t(tt, T_SLIT_END, T_SLIDE_END)
	u.retract = _ease_out(_ramp_t(tt, T_RELEASE, T_END))
	if not reduced_motion and flash_scale > 0.0:
		var up := _ramp_t(tt, T_SLIDE_END, T_FLASH_PEAK)
		var down := 1.0 - _ramp_t(tt, T_FLASH_PEAK, T_FLASH_END)
		u.flash = minf(up, down) * flash_scale
	if reduced_motion: u.slide = 1.0
	return u

func _push_screen() -> void:
	var cu := _cut_uniforms()
	var cut_on := not _cut.is_empty()
	var scrim := maxf(float(cu.scrim), _scrim_hold)
	var any := _aura > 0.005 or _aura_pulse > 0.005 or cut_on or _freeze > 0.005 or _pulse > 0.005 or scrim > 0.005
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

func _update_sweep(run: RefCounted, mode: String, dt: float) -> void:
	if _sw.is_empty():
		_ground.visible = false
		_wall.visible = false
		_freeze = 0.0
		_shatter = 0.0
		_scrim_hold = maxf(0.0, _scrim_hold - dt * 2.0)
		return
	if mode == "playing" or mode == "choice":
		_sw["t"] = float(_sw.t) + dt
	var t := float(_sw.t)
	var dur := float(_sw.dur)
	var tail := float(_sw.tail)
	var el := String(_sw.element)
	var reach := float(_sw.reach)
	var center: Vector2 = _sw.center
	_ground_mat.set_shader_parameter("time", _clock)
	_ground_mat.set_shader_parameter("hero_local", _hero - center)
	match el:
		"ember": _sweep_ember(t, dur, tail, reach, center, dt)
		"frost": _sweep_frost(t, dur, tail, dt)
		"arc": _sweep_arc(t, dur, tail, dt)
	if t >= dur + tail:
		_sw = {}
		_ground.visible = false
		_wall.visible = false
		_freeze = 0.0
		_shatter = 0.0
		if _wall_particles != null: _wall_particles.emitting = false

func _sweep_ember(t: float, dur: float, tail: float, reach: float, center: Vector2, dt: float) -> void:
	var cam := _camera()
	var p := clampf(t / dur, 0.0, 1.0)
	var heading: Vector2 = _sw.heading
	var a := -reach + 2.0 * reach * p
	var front := center + heading * a
	var chord := sqrt(maxf(0.0, reach * reach - a * a))
	var half_len := chord * SCREEN_TILT + 1.0
	var gain := minf(_ramp_t(t, 0.0, 0.07), 1.0 - _ramp_t(t, dur - 0.05, dur + 0.05))
	_wall.visible = cam != null and gain > 0.01
	if cam != null:
		var basis := cam.global_basis
		var size := Vector2(7.0, (reach * SCREEN_TILT + 3.0) * 2.0)
		(_wall.mesh as QuadMesh).size = size
		var origin := Vector3(front.x, GROUND_Y + 0.2, front.y)
		_wall.global_transform = Transform3D(basis, origin)
		_wall_mat.set_shader_parameter("quad_size", size)
		_wall_mat.set_shader_parameter("half_len", half_len)
		_wall_mat.set_shader_parameter("gain", gain)
		_wall_mat.set_shader_parameter("time", _clock)
		var rel := Vector3(_hero.x - front.x, 0.0, _hero.y - front.y)
		_wall_mat.set_shader_parameter("hero_xy", Vector2(rel.dot(basis.x), rel.dot(basis.y) + 1.0))
	# the floor: the trace behind the wall, then it fades
	_ground_mat.set_shader_parameter("progress", p)
	var fade := 1.0 - _ramp_t(t, dur + 0.4, dur + tail)
	_ground_mat.set_shader_parameter("fade", fade)
	_ground.visible = true
	if _wall_particles != null:
		_wall_particles.emitting = p < 1.0
		_wall_particles.global_position = Vector3(front.x, 0.4, front.y)
		_wall_particles.rotation = Vector3(0.0, atan2(-heading.y, heading.x), 0.0)
		(_wall_particles.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(0.45, 0.1, maxf(0.5, chord))
	# two lights: one rides the wall, one stays at the centre
	_set_light(0, Vector3(front.x, 2.4, front.y), Color(1.0, 0.55, 0.2), 3.6 * gain * (0.8 + 0.2 * sin(_clock * 31.0)), 9.0)
	_set_light(1, Vector3(center.x, 1.8, center.y), Color(1.0, 0.5, 0.18), 1.6 * minf(1.0, p * 3.0) * (1.0 - _ramp_t(t, dur, dur + 0.5)), 10.0)
	if t < dur:
		_sw["kick"] = float(_sw.kick) + dt
		if float(_sw.kick) >= 0.1:
			_sw["kick"] = 0.0
			_kick(0.3)

func _sweep_frost(t: float, dur: float, tail: float, dt: float) -> void:
	var grow := _ease_out(_ramp_t(t, 0.0, 0.34))
	var broke := bool(_sw.broke)
	if not broke and t >= dur + 0.02: _do_break([])
	if not broke:
		_freeze = _ease_out(_ramp_t(t, 0.0, 0.5))
		_ground_mat.set_shader_parameter("progress", grow)
		_ground_mat.set_shader_parameter("shatter", 0.0)
		_ground_mat.set_shader_parameter("fade", 1.0)
		_set_light(0, Vector3(float((_sw.center as Vector2).x), 3.0, float((_sw.center as Vector2).y)), Color(0.55, 0.85, 1.0), 1.6 * grow, 11.0)
	else:
		_sw["bt"] = float(_sw.bt) + dt
		var bt := float(_sw.bt)
		_shatter = _ramp_t(bt, 0.0, 0.42)
		_freeze = 1.0 - _ramp_t(bt, 0.25, 0.6)
		_ground_mat.set_shader_parameter("progress", 1.0)
		_ground_mat.set_shader_parameter("shatter", _shatter)
		_ground_mat.set_shader_parameter("fade", 1.0 - _ramp_t(bt, 0.3, 0.65))
		_set_light(0, Vector3(float((_sw.center as Vector2).x), 3.0, float((_sw.center as Vector2).y)), Color(0.7, 0.92, 1.0), 6.0 * (1.0 - _ramp_t(bt, 0.0, 0.18)), 13.0)
	_ground.visible = true

func _sweep_arc(t: float, dur: float, tail: float, dt: float) -> void:
	_scrim_hold = 0.30 * (1.0 - _ramp_t(t, dur - 0.1, dur + tail))

func _camera() -> Camera3D:
	var world: Variant = view.get("world")
	if world == null: return null
	var cam: Variant = world.get("camera")
	return cam as Camera3D

func _do_break(positions: Array) -> void:
	if bool(_sw.broke): return
	_sw["broke"] = true
	_sw["bt"] = 0.0
	_pulse = 1.0
	_kick(1.0)
	_emit_burst(positions, _sw.center)

## One GPU burst from up to 64 points (the points are handed over as a texture; the pool is one node of 192 particles).
func _emit_burst(positions: Array, fallback: Vector2) -> void:
	if _burst_particles == null: return
	var points := PackedVector3Array()
	for pos in positions:
		if points.size() >= 64: break
		var at: Vector2 = pos
		points.append(Vector3(at.x, 0.5, at.y))
	if points.is_empty(): points.append(Vector3(fallback.x, 0.5, fallback.y))
	var image := Image.create_from_data(points.size(), 1, false, Image.FORMAT_RGBF, points.to_byte_array())
	_burst_material.emission_point_texture = ImageTexture.create_from_image(image)
	_burst_material.emission_point_count = points.size()
	_burst_particles.restart()
	_burst_particles.emitting = true

# ---- bolts

func _hash(a: float) -> float:
	return fposmod(sin(a * 12.9898) * 43758.5453, 1.0)

func _do_bolts(positions: Array) -> void:
	_sw["rounds"] = int(_sw.rounds) + 1
	_pulse = maxf(_pulse, 0.55)
	_kick(0.4)
	var count := positions.size()
	# the first per_round (12) are the round's own strikes, the rest are where it jumped to (the core's order; no field says which)
	var primaries := mini(12, count)
	for i in count:
		if _bolts.size() >= MAX_BOLTS:
			stats.bolts_dropped += 1
			continue
		var at: Vector2 = positions[i]
		var bolt := {"foot": Vector3(at.x, GROUND_Y + 0.05, at.y), "t": 0.0, "seed": float(int(_sw.rounds) * 97 + i * 13), "parent": Vector3.ZERO, "link": false}
		if i >= primaries and primaries > 0:
			# jump from the nearest primary of this round
			var best := Vector2.ZERO
			var best_d := 1.0e9
			for k in primaries:
				var q: Vector2 = positions[k]
				var d := q.distance_squared_to(at)
				if d < best_d:
					best_d = d
					best = q
			bolt.parent = Vector3(best.x, 0.9, best.y)
			bolt.link = true
		_bolts.append(bolt)
		stats.bolts += 1
	stats.peak_bolts = maxi(int(stats.peak_bolts), _bolts.size())
	if count > 0:
		var first: Vector2 = positions[0]
		_set_light(int(_sw.rounds) % 2, Vector3(first.x, 2.0, first.y), Color(0.72, 0.8, 1.0), 6.5, 8.0, 0.12)
	_emit_burst(positions.slice(0, mini(count, 24)), _sw.center)

func _update_bolts(dt: float) -> void:
	if _bolts.is_empty():
		if _bolt_node != null and _bolt_node.visible:
			_bolt_node.visible = false
			_bolt_mesh.clear_surfaces()
		return
	var cam := _camera()
	if cam == null:
		_bolts.clear()
		return
	var right := cam.global_basis.x
	var up := cam.global_basis.y
	_bolt_mesh.clear_surfaces()
	var kept: Array[Dictionary] = []
	for bolt in _bolts:
		bolt["t"] = float(bolt.t) + dt
		var age := float(bolt.t) / BOLT_LIFE
		if age >= 1.0: continue
		kept.append(bolt)
		var fade := 1.0 - age
		var flick := 1.0 if int(float(bolt.t) * 60.0) % 2 == 0 else 0.7
		if bool(bolt.link):
			_draw_jagged(bolt.parent, bolt.foot + Vector3(0, 0.9, 0), 9, 0.10, 0.38, bolt.seed, fade * flick, right, up, true)
		else:
			var foot: Vector3 = bolt.foot
			_draw_jagged(foot + Vector3(0, 15.0, 0), foot, 12, 0.13, 0.55, bolt.seed, fade * flick, right, up, false)
			_draw_flare(foot, 0.7 + 0.9 * fade, fade, right, up)
	_bolts = kept
	_bolt_node.visible = not _bolts.is_empty()

func _draw_jagged(from: Vector3, to: Vector3, segments: int, width: float, amp: float, seed_: float, fade: float, right: Vector3, up: Vector3, link: bool) -> void:
	var pts := PackedVector3Array()
	var dir := to - from
	var t_screen := Vector2(dir.dot(right), dir.dot(up)).normalized()
	var perp := (right * -t_screen.y + up * t_screen.x).normalized()
	for i in segments + 1:
		var f := float(i) / float(segments)
		var base := from.lerp(to, f)
		var env := sin(f * PI) if link else (1.0 - f * 0.85)
		var jitter := (_hash(seed_ + float(i) * 3.7) - 0.5) * 2.0 * amp * env
		pts.append(base + perp * jitter)
	# wide glow ribbon, then the thin white core
	for pass_ in 2:
		var w := width * (3.2 if pass_ == 0 else 1.0)
		var color := Color(_tint.r, _tint.g, _tint.b, 0.28 * fade) if pass_ == 0 else Color(1.0, 1.0, 1.0, 0.95 * fade)
		_bolt_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in pts.size():
			var f2 := float(i) / float(pts.size() - 1)
			var taper := 1.0 if link else lerpf(0.45, 1.0, f2)
			var tangent := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)])
			var ts := Vector2(tangent.dot(right), tangent.dot(up)).normalized()
			var pp := (right * -ts.y + up * ts.x).normalized()
			_bolt_mesh.surface_set_color(color)
			_bolt_mesh.surface_add_vertex(pts[i] + pp * w * taper)
			_bolt_mesh.surface_set_color(color)
			_bolt_mesh.surface_add_vertex(pts[i] - pp * w * taper)
		_bolt_mesh.surface_end()

func _draw_flare(foot: Vector3, size: float, fade: float, right: Vector3, up: Vector3) -> void:
	# a flat diamond at the foot: the bolt's landing
	var color := Color(0.85, 0.9, 1.0, 0.8 * fade)
	_bolt_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var c := foot + Vector3(0, 0.1, 0)
	for p in [Vector3(-size, 0, 0), Vector3(0, 0, -size * 0.5), Vector3(0, 0, size * 0.5), Vector3(size, 0, 0)]:
		_bolt_mesh.surface_set_color(color)
		_bolt_mesh.surface_add_vertex(c + right * p.x + up * p.z)
	_bolt_mesh.surface_end()

# ---- flights (orbs coming in, puffs of wiped shots)

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
		_flights.append(_hash(float(made) * 1.7) * 0.28)
		_flights.append(0.0); _flights.append(0.0); _flights.append(0.0)
		made += 1
	stats.flights += made
	_kill_cache = PackedVector2Array()

func _update_flights(run: RefCounted, dt: float) -> void:
	# keep the freshest orbs' places while a sweep runs (the vacuum empties the list on the sweep's last tick)
	if not _sw.is_empty() and run.orbs.size() > 0:
		var fresh := PackedVector2Array()
		for orb in run.orbs:
			fresh.append(orb.position)
		_orb_cache = fresh
	var mm := _flight.multimesh
	var n := _flights.size() / 6
	if n == 0:
		if mm.visible_instance_count != 0: mm.visible_instance_count = 0
		return
	_flight_target = Vector3(_hero.x, 1.1, _hero.y)
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
			mm.set_instance_color(slot, Color(_tint.r, _tint.g, _tint.b, 0.55 * (1.0 - f)))
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
	if _sw.is_empty() and _cut.is_empty():
		for i in _lights.size():
			if _light_life[i] <= 0.0 and _lights[i].visible:
				_lights[i].visible = false
				_lights[i].light_energy = 0.0

func _update_label(dt: float) -> void:
	if _kill_label == null or _kill_label_age < 0.0: return
	_kill_label_age += dt
	var a := _kill_label_age
	var pop := 1.0 + 0.35 * (1.0 - _ramp_t(a, 0.0, 0.18))
	var alpha := _ramp_t(a, 0.0, 0.08) * (1.0 - _ramp_t(a, 1.1, 1.6))
	_kill_label.pivot_offset = _kill_label.size * 0.5
	_kill_label.scale = Vector2.ONE * (1.0 if reduced_motion else pop)
	_kill_label.modulate = Color(1, 1, 1, alpha)
	if a >= 1.6:
		_kill_label.visible = false
		_kill_label_age = -1.0
