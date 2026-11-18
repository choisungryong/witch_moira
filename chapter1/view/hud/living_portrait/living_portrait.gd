extends Node2D
## Living portrait: a witch drawn as stacked layers with a small 2D rig, for still screens (character select, the
## blessing screen, the title). Not for combat. The feet never move; the pelvis shifts weight and rises with the breath,
## the legs tilt about the feet, the knees give, the chest, arms and head follow from the pelvis upward, cloth and hair
## swing last and the most. Faces are never deformed. The background is still.
##
## Use (for a screen: character select, blessing, title). These five calls are all a screen needs:
##   var p := preload("res://chapter1/view/hud/living_portrait/living_portrait.gd").new()
##   add_child(p)
##   p.set_rect(Rect2(x, y, w, h))      # fit: the portrait is fitted to the height of this rectangle and centred in it
##                                      #      (call again whenever the screen is resized; optional zoom, zoom_center args)
##   p.set_motion_scale(1.0)            # motion: 1.0 is the chosen amount (json "motion_gain" is baked in);
##                                      #         0.0 is the still picture (reduce-motion setting), 0.5 is half the amplitude.
##                                      #         Speed does not change. Needs no reload; may be called at any time.
##   p.select_witch("frost")            # pick: "ember" | "frost" | "storm" (WITCHES); replaces the one shown. Returns false if unknown.
##                                      #       Rect, motion scale and seed set before stay.
##   p.play_intro()                     # entrance: darkness lifts from the bottom, the element light comes on first
##   p.set_active(false)                # stop all work while the screen is hidden; true to resume
## Also: p.set_seed(n) (blink and event schedule; set it before select_witch for a repeatable picture), p.witch_id (current id).
## Eyes blink on their own: every 3 to 6 s, 0.12 to 0.18 s each, sometimes twice in a row; blinking stops at motion scale 0.
## Do not call setup(path) from a screen; it is what select_witch uses (the demo scene and tests may use it).
## Nothing is drawn outside of this node's children and nothing is read from or written to the game state.

const BODY := preload("res://chapter1/view/hud/living_portrait/rig_body.gdshader")
const CLOTH := preload("res://chapter1/view/hud/living_portrait/rig_cloth.gdshader")
const GLOW := preload("res://chapter1/view/hud/living_portrait/rig_glow.gdshader")
const DARK := preload("res://chapter1/view/hud/living_portrait/rig_dark.gdshader")
const SnowLayer := preload("res://chapter1/view/hud/living_portrait/snow_layer.gd")
const FxLayers := preload("res://chapter1/view/hud/living_portrait/fx_layers.gd")
const SnowflakeFx := preload("res://chapter1/view/hud/living_portrait/snowflake_fx.gd")
const EmberFx := preload("res://chapter1/view/hud/living_portrait/ember_fx.gd")
const RibbonFx := preload("res://chapter1/view/hud/living_portrait/ribbon_fx.gd")
const ArcFx := preload("res://chapter1/view/hud/living_portrait/arc_fx.gd")
const BoltFx := preload("res://chapter1/view/hud/living_portrait/bolt_fx.gd")

const INTRO_TIME := 1.1
const WITCHES := ["ember", "frost", "storm"]
const CONFIG_DIR := "res://chapter1/view/hud/living_portrait/"
const GLOW_PRESETS := {
	"ice": {"w": [-1.0, 0.0, 1.0], "bias": 0.0, "gain": 2.2, "rgb": [0.4, 0.8, 1.0], "mul": 0.10, "pulse": 0.14, "period": 2.5, "band": 0.5},
	"ember": {"w": [1.0, 0.0, -1.2], "bias": 0.45, "gain": 3.0, "rgb": [1.0, 0.55, 0.2], "mul": 0.12, "pulse": 0.35, "period": 1.8, "band": 0.0},
	"ember_hem": {"w": [1.0, 0.0, -1.2], "bias": 0.45, "gain": 3.0, "rgb": [1.0, 0.55, 0.2], "mul": 0.10, "pulse": 0.28, "period": 2.3, "band": 0.0},
	"ember_lamp": {"w": [1.0, 0.0, -1.2], "bias": 0.45, "gain": 3.0, "rgb": [1.0, 0.6, 0.2], "mul": 0.15, "pulse": 0.35, "period": 2.0, "band": 0.0},
	"storm": {"w": [-0.3, -0.5, 1.0], "bias": 0.3, "gain": 5.0, "rgb": [0.75, 0.65, 1.0], "mul": 0.10, "pulse": 0.25, "period": 2.9, "band": 0.0},
}

# element switches (all on by default); the demo sets them from its arguments
var breath_on := true
var legs_on := true
var sway_on := true
var head_on := true
var blink_on := true
var snow_on := true
var fx_on := true
var glow_on := true
var motion_scale := 1.0
## Optional overrides of the config's motion block (the demo uses them for the knee stages).
var motion_override := {}

var cfg := {}
var witch_id := ""
var active := true
var manual_time := false

var _canvas := Vector2(1024.0, 1536.0)
var _rect := Rect2(0.0, 0.0, 640.0, 960.0)
var _zoom := 1.0
var _zoom_center := Vector2(-1.0, -1.0)
var _bg_rig: Node2D
var _fig: Node2D
var _fx_root: Node2D
var _back_fx: Node2D
var _front_fx: Node2D
var _snow: Node2D
var _veil: ColorRect
var _dark_mat: ShaderMaterial
var _layers := {}          # id -> {"def", "sprite", "mat"}
var _order: Array[String] = []
var _head_sprite: Sprite2D
var _half: Sprite2D
var _closed: Sprite2D
var _effects: Array = []   # {"node", "follow", "kind"}
var _springs := {}         # id -> {"a", "v"}
var _blinks: Array[float] = []
var _blink_len: Array[float] = []
var _events: Array[float] = []
var _fixes: Array[float] = []
var _deep: Array[int] = []   # breath cycle numbers that are deeper than the others
var _seed := 7
var _t := 0.0
var _sim_t := 0.0
var _intro_t0 := -1.0
var _head_xf := Transform2D.IDENTITY
var _csv: FileAccess
var _tips := {}   # spring layer id -> far end point (for the measurement table)
var last_pose := {}


## Pick a witch by id ("ember", "frost", "storm"); the previous one, if any, is removed. The rectangle, the motion scale
## and the seed that were set before stay. Returns false for an unknown id. Call play_intro() after it for the entrance.
func select_witch(id: String) -> bool:
	if not WITCHES.has(id):
		push_error("living_portrait: unknown witch " + id)
		return false
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_bg_rig = null
	_fig = null
	_fx_root = null
	_back_fx = null
	_front_fx = null
	_snow = null
	_veil = null
	_dark_mat = null
	_head_sprite = null
	_half = null
	_closed = null
	_layers.clear()
	_order.clear()
	_effects.clear()
	_springs.clear()
	_tips.clear()
	_intro_t0 = -1.0
	_t = 0.0
	_sim_t = 0.0
	witch_id = id
	return setup(CONFIG_DIR + id + ".json")


func setup(config_path: String) -> bool:
	var f := FileAccess.open(config_path, FileAccess.READ)
	if f == null:
		push_error("living_portrait: cannot read " + config_path)
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("living_portrait: bad config " + config_path)
		return false
	cfg = parsed
	var c: Array = cfg.get("canvas", [1024, 1536])
	_canvas = Vector2(c[0], c[1])
	_bg_rig = Node2D.new()
	add_child(_bg_rig)
	_back_fx = FxLayers.new("back", String(cfg.get("theme", "frost")))
	add_child(_back_fx)
	_fig = Node2D.new()
	add_child(_fig)
	_fx_root = Node2D.new()
	_fx_root.z_index = 8
	add_child(_fx_root)
	_front_fx = FxLayers.new("front", String(cfg.get("theme", "frost")))
	add_child(_front_fx)
	if bool(cfg.get("snow", false)):
		_snow = SnowLayer.new()
		add_child(_snow)
	_build_layers()
	_build_eyes()
	_build_effects()
	_make_schedule()
	_apply_switches()
	_layout()
	_advance(0.0)
	return true


func set_active(on: bool) -> void:
	active = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func play_intro() -> void:
	_intro_t0 = _t
	_make_schedule()
	if _veil == null:
		_veil = ColorRect.new()
		_veil.z_index = 7
		_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dark_mat = ShaderMaterial.new()
		_dark_mat.shader = DARK
		_veil.material = _dark_mat
		add_child(_veil)
		_layout()


func set_motion_scale(x: float) -> void:
	motion_scale = maxf(x, 0.0)
	_apply_switches()


func set_seed(n: int) -> void:
	_seed = n
	_make_schedule()
	for e in _effects:
		if e["kind"] == "bolts" or e["kind"] == "arc":
			e["node"].call("setup", e["def"], _seed)


func set_rect(rect: Rect2, zoom: float = 1.0, zoom_center: Vector2 = Vector2(-1.0, -1.0)) -> void:
	_rect = rect
	_zoom = zoom
	_zoom_center = zoom_center
	_layout()


## For captures and tests: drive the clock by hand.
func advance_to(t: float) -> void:
	manual_time = true
	_t = t
	_advance(t)


func set_flags(flags: Dictionary) -> void:
	breath_on = flags.get("breath", breath_on)
	legs_on = flags.get("legs", legs_on)
	sway_on = flags.get("sway", sway_on)
	head_on = flags.get("head", head_on)
	blink_on = flags.get("blink", blink_on)
	snow_on = flags.get("snow", snow_on)
	fx_on = flags.get("fx", fx_on)
	glow_on = flags.get("glow", glow_on)
	_apply_switches()


## For tests: blink start times and lengths (seconds) of the current schedule.
func blink_schedule() -> Array:
	return [_blinks.duplicate(), _blink_len.duplicate()]


func open_table(path: String) -> void:
	_csv = FileAccess.open(path, FileAccess.WRITE)
	var head := "t,pelvis_dx,pelvis_dy,chest_dy,knee_l_dx,knee_r_dx,knee_l_dy,knee_r_dy,head_deg,head_dx,head_dy"
	_tips.clear()
	for id in _springs:
		if _layers[id]["def"].get("kind") != "spring":
			continue
		var img: Image = (_layers[id]["sprite"] as Sprite2D).texture.get_image()
		var r := img.get_used_rect()
		var root := Vector2(_layers[id]["def"]["root"][0], _layers[id]["def"]["root"][1])
		var best := Vector2.ZERO
		var best_d := -1.0
		for c in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
			if root.distance_to(c) > best_d:
				best_d = root.distance_to(c)
				best = c
		_tips[id] = best
		head += ",%s_tip_dx,%s_tip_dy" % [id, id]
	_csv.store_line(head)


func close_table() -> void:
	if _csv != null:
		_csv.close()
		_csv = null


# ------------------------------------------------------------------ build

func _build_layers() -> void:
	var dir: String = cfg.get("layer_dir", "")
	var rig: Dictionary = cfg.get("rig", {})
	for d in cfg.get("layers", []):
		var def: Dictionary = d
		var id: String = def["id"]
		var s := Sprite2D.new()
		s.texture = load(dir + id + ".png")
		s.centered = false
		var kind: String = def.get("kind", "static")
		(_bg_rig if kind == "static" else _fig).add_child(s)
		var mat: ShaderMaterial = null
		if kind == "field" or kind == "cloth":
			mat = ShaderMaterial.new()
			mat.shader = BODY if kind == "field" else CLOTH
			mat.set_shader_parameter("y_hip", float(rig.get("y_hip", 470)))
			mat.set_shader_parameter("y_chest", float(rig.get("y_chest", 300)))
			mat.set_shader_parameter("split_x", float(rig.get("split_x", 470)))
			mat.set_shader_parameter("y_ankle", float(def.get("y_ankle", 1380)))
			mat.set_shader_parameter("y_knee", float(def.get("y_knee", 870)))
			mat.set_shader_parameter("side_force", float(def.get("side", -1)))
			if kind == "cloth":
				mat.set_shader_parameter("y0", float(def.get("y0", 250)))
				mat.set_shader_parameter("y1", float(def.get("y1", 1500)))
				mat.set_shader_parameter("lag", float(def.get("lag", 0.5)))
				mat.set_shader_parameter("phase", float(def.get("phase", 0.0)))
				mat.set_shader_parameter("period", float(def.get("period", 3.7)))
				mat.set_shader_parameter("period2", float(def.get("period2", 6.1)))
		elif def.has("glow"):
			mat = ShaderMaterial.new()
			mat.shader = GLOW
		if mat != null:
			if def.has("glow"):
				_apply_preset(mat, String(def["glow"]))
			s.material = mat
		_layers[id] = {"def": def, "sprite": s, "mat": mat}
		_order.append(id)
		if kind == "head":
			_head_sprite = s
		if kind == "spring" or kind == "pendulum":
			_springs[id] = {"a": 0.0, "v": 0.0}


func _apply_preset(mat: ShaderMaterial, name_: String) -> void:
	var p: Dictionary = GLOW_PRESETS[name_]
	mat.set_shader_parameter("g_w", Vector3(p["w"][0], p["w"][1], p["w"][2]))
	mat.set_shader_parameter("g_bias", float(p["bias"]))
	mat.set_shader_parameter("g_gain", float(p["gain"]))
	mat.set_shader_parameter("g_rgb", Vector3(p["rgb"][0], p["rgb"][1], p["rgb"][2]))
	mat.set_shader_parameter("g_mul", float(p["mul"]))
	mat.set_shader_parameter("g_pulse", float(p["pulse"]))
	mat.set_shader_parameter("g_period", float(p["period"]))
	mat.set_shader_parameter("g_band", float(p["band"]))


func _build_eyes() -> void:
	var e: Dictionary = cfg.get("eyes", {})
	if e.is_empty() or _head_sprite == null:
		return
	var pos: Array = e["pos"]
	for pair in [["half", "_half"], ["closed", "_closed"]]:
		var s := Sprite2D.new()
		s.texture = load(String(e[pair[0]]))
		s.centered = false
		s.position = Vector2(pos[0], pos[1])
		s.visible = false
		_head_sprite.add_child(s)
		if pair[1] == "_half":
			_half = s
		else:
			_closed = s


func _build_effects() -> void:
	for d in cfg.get("effects", []):
		var def: Dictionary = d
		var kind: String = def["type"]
		var node: Node2D
		if kind == "snowflake":
			node = SnowflakeFx.new()
			node.call("setup", def)
		elif kind == "embers":
			node = EmberFx.new()
			node.call("setup", def)
		elif kind == "bolts":
			node = BoltFx.new()
			node.call("setup", def, _seed)
		elif kind == "ribbon":
			node = RibbonFx.new()
			node.call("setup", def)
		elif kind == "arc":
			node = ArcFx.new()
			node.call("setup", def, _seed)
		else:
			continue
		_fx_root.add_child(node)
		_effects.append({"node": node, "follow": String(def.get("follow", "")), "follow2": String(def.get("follow2", "")), "kind": kind, "def": def})


func _make_schedule() -> void:
	_blinks.clear()
	_events.clear()
	_fixes.clear()
	_deep.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var t := rng.randf_range(1.6 if _intro_t0 >= 0.0 else 1.0, 2.8)
	_blink_len.clear()
	while t < 120.0:
		# one blink takes 0.12 to 0.18 s (half, closed, half); now and then a second one follows right behind
		var dur := rng.randf_range(0.12, 0.18)
		_blinks.append(t)
		_blink_len.append(dur)
		if rng.randf() < 0.25:
			var t2 := t + dur + rng.randf_range(0.10, 0.20)
			var dur2 := rng.randf_range(0.12, 0.18)
			_blinks.append(t2)
			_blink_len.append(dur2)
			t = t2
		t += rng.randf_range(3.0, 6.0)
	var e := rng.randf_range(3.0, 5.0)
	while e < 120.0:
		_events.append(e)
		e += rng.randf_range(6.0, 12.0)
	var f := rng.randf_range(6.0, 8.0)
	while f < 120.0:
		_fixes.append(f)
		f += rng.randf_range(20.0, 30.0)
	var d := rng.randf_range(4.0, 7.0)
	while d < 120.0:
		_deep.append(int(floor(d / _m("body_period", 3.4))))
		d += rng.randf_range(15.0, 25.0)


func _apply_switches() -> void:
	var moving := motion_scale > 0.0
	if _back_fx != null:
		_back_fx.visible = fx_on and moving
		_front_fx.visible = fx_on and moving
	if _snow != null:
		_snow.visible = snow_on and moving
	for id in _layers:
		var m: ShaderMaterial = _layers[id]["mat"]
		if m != null:
			m.set_shader_parameter("glow_amount", 1.0 if (glow_on and moving and _layers[id]["def"].has("glow")) else 0.0)
	for e in _effects:
		if e["kind"] != "snowflake":
			e["node"].visible = fx_on and moving


# ------------------------------------------------------------------ layout

func _layout() -> void:
	if _bg_rig == null:
		return
	var s := minf(_rect.size.x / _canvas.x, _rect.size.y / _canvas.y) * _zoom
	var center_pt := _zoom_center if _zoom_center.x >= 0.0 else _canvas * 0.5
	var origin := _rect.position + _rect.size * 0.5 - center_pt * s
	for n in [_bg_rig, _fig, _fx_root]:
		n.scale = Vector2.ONE * s
		n.position = origin
	_back_fx.position = _rect.position
	_front_fx.position = _rect.position
	_back_fx.call("layout", _rect.size)
	_front_fx.call("layout", _rect.size)
	if _snow != null:
		_snow.position = _rect.position
		_snow.call("layout", _rect.size, 1.0)
	if _veil != null:
		_veil.position = _rect.position
		_veil.size = _rect.size


# ------------------------------------------------------------------ motion model

## Slow rise and fall in 0..1, the rise a little shorter than the fall; a slower second wave keeps the loop from showing.
func _wave(t: float) -> float:
	var period := _m("body_period", 3.4)
	var cyc := int(floor(t / period))
	var u := fposmod(t / period, 1.0)
	# in-breath is the shorter part (4 : 6), an occasional deep breath is 1.25 times as high
	var f := 0.5 - 0.5 * cos(PI * u / 0.4) if u < 0.4 else 0.5 + 0.5 * cos(PI * (u - 0.4) / 0.6)
	if _deep.has(cyc):
		f *= 1.25
	return 0.9 * f + 0.1 * (0.5 + 0.5 * sin(TAU * t / 11.3))


func _bump(list: Array[float], t: float, length: float) -> float:
	for e in list:
		var d := t - e
		if d >= 0.0 and d < length:
			var u := sin(PI * d / length)
			return u * u
	return 0.0


func _blink_state(t: float) -> int:
	for i in _blinks.size():
		var d := t - _blinks[i]
		if d < 0.0:
			return 0
		var dur := _blink_len[i]
		var half := dur * 0.3
		if d < half:
			return 1
		if d < dur - half:
			return 2
		if d < dur:
			return 1
	return 0


func _rot_about(pivot: Vector2, ang: float) -> Transform2D:
	return Transform2D(0.0, pivot) * Transform2D(ang, Vector2.ZERO) * Transform2D(0.0, -pivot)


func _m(key: String, default_value: float) -> float:
	if motion_override.has(key):
		return float(motion_override[key])
	return float(cfg.get("motion", {}).get(key, default_value))


## Model values at time t. Image pixels, up is negative.
func _pose(t: float) -> Dictionary:
	var k := motion_scale * float(cfg.get("motion_gain", 1.0))
	var shift := 0.0
	var pelvis := Vector2.ZERO
	var chest := Vector2.ZERO
	var arm_extra := 0.0
	var knee_l := 0.0
	var knee_r := 0.0
	var knee_l_dy := 0.0
	var knee_r_dy := 0.0
	var hip_l_dy := 0.0
	var hip_r_dy := 0.0
	if breath_on:
		pelvis.y = -_m("pelvis_y", 3.5) * _wave(t) * k
		chest.y = -_m("chest_rise", 5.0) * _wave(t - 0.1) * k
		arm_extra = -_m("arm_extra", 1.0) * _wave(t - 0.2) * k
	if legs_on:
		shift = clampf(0.8 * sin(TAU * t / _m("shift_period", 8.3)) + 0.2 * sin(TAU * t / 13.7 + 1.0) + 0.35 * _bump(_fixes, t, 3.0), -1.0, 1.0)
		pelvis.x = _m("pelvis_x", 6.0) * shift * k
		chest.x = pelvis.x * 0.35
		var knee_t := _m("knee", 6.0)
		# the unloaded side bends: knee outward and forward (down on the screen), hip drops
		var bend_l := 0.75 * (0.5 + 0.5 * shift) + 0.25 * _wave(t)
		var bend_r := 0.75 * (0.5 - 0.5 * shift) + 0.25 * _wave(t)
		knee_l = -knee_t * bend_l * k
		knee_r = knee_t * bend_r * k
		knee_l_dy = 0.5 * knee_t * bend_l * k
		knee_r_dy = 0.5 * knee_t * bend_r * k
		var tilt_px := _m("tilt_deg", 1.2) * 0.0175 * 100.0 * k
		hip_l_dy = tilt_px * shift
		hip_r_dy = -tilt_px * shift
	var head_deg := 0.0
	var head_dx := 0.0
	var head_dy := 0.0
	var open_px := 0.0
	var arm_deg := 0.0
	if breath_on:
		open_px = _m("shoulder_open", 3.0) * _wave(t - 0.15) * k
		arm_deg = _m("arm_breath_deg", 1.5) * _wave(t - 0.2) * k
	if head_on:
		# the head rides on the chest, follows a little later and nods a little
		head_dy = -_m("head_extra", 4.0) * _wave(t - 0.3) * k
		head_deg = _m("head_nod_deg", 0.8) * (_wave(t - 0.3) - 0.3) * k
		head_deg += (_m("head_deg", 0.7) * sin(TAU * t / 5.53) + 0.5 * _m("head_deg", 0.7) * sin(TAU * t / 8.9 + 0.6) + _m("tilt_event_deg", 0.9) * _bump(_events, t, 2.2)) * k
		head_dx = _m("head_dx", 1.2) * sin(TAU * t / 6.53) * k
		head_dy += _m("head_dy", 0.8) * sin(TAU * t / 3.53 + 0.5) * k
	return {"pelvis": pelvis, "chest": chest, "arm_extra": arm_extra, "knee_l": knee_l, "knee_r": knee_r,
		"knee_l_dy": knee_l_dy, "knee_r_dy": knee_r_dy, "hip_l_dy": hip_l_dy, "hip_r_dy": hip_r_dy,
		"head_deg": head_deg, "head_dx": head_dx, "head_dy": head_dy, "open": open_px, "arm_deg": arm_deg}


## Same displacement as rig_field.gdshaderinc, for rigid pieces that hang from the pelvis (the bells).
func _disp_at(p: Vector2, pose: Dictionary) -> Vector2:
	var rig: Dictionary = cfg.get("rig", {})
	var y_hip := float(rig.get("y_hip", 470))
	var y_chest := float(rig.get("y_chest", 300))
	var pelvis: Vector2 = pose["pelvis"]
	var chest: Vector2 = pose["chest"]
	if p.y < y_hip:
		var u := smoothstep(0.0, 1.0, clampf((y_hip - p.y) / (y_hip - y_chest), 0.0, 1.0))
		return pelvis.lerp(chest, u)
	var tl := clampf((p.y - y_hip) / (1400.0 - y_hip), 0.0, 1.0)
	return pelvis * (1.0 - (3.0 * tl * tl - 2.0 * tl * tl * tl))


func _step_springs(t: float, targets: Dictionary) -> void:
	var w := TAU / 1.6
	var z := 0.45
	while _sim_t < t:
		var dt := 1.0 / 240.0
		for id in _springs:
			var sp: Dictionary = _springs[id]
			sp["v"] += (w * w * (float(targets[id]) - sp["a"]) - 2.0 * z * w * sp["v"]) * dt
			sp["a"] += sp["v"] * dt
		_sim_t += dt


func _process(delta: float) -> void:
	if manual_time:
		return
	_t += delta
	_advance(_t)


func _advance(t: float) -> void:
	var k := motion_scale * float(cfg.get("motion_gain", 1.0))
	var p := _pose(t)
	last_pose = p
	var chest: Vector2 = p["chest"]
	var chest_t := Transform2D(0.0, chest)
	var rig: Dictionary = cfg.get("rig", {})
	var neck := Vector2(rig.get("neck", [492, 178])[0], rig.get("neck", [492, 178])[1])
	_head_xf = chest_t * Transform2D(0.0, Vector2(p["head_dx"], p["head_dy"])) * _rot_about(neck, deg_to_rad(p["head_deg"]))
	var targets := {}
	for id in _springs:
		var def: Dictionary = _layers[id]["def"]
		if def.get("kind") == "spring":
			var tg := deg_to_rad(float(def.get("amp_deg", 2.5))) * (0.8 * sin(TAU * (t - 0.3) / float(def.get("period", 4.3)) + float(def.get("phase", 0.0))) + 0.35 * sin(TAU * t / 7.1 + 1.0 + float(def.get("phase", 0.0)))) * k
			targets[id] = tg if sway_on else 0.0
		else:
			targets[id] = 0.0
	_step_springs(t, targets)
	var cloth_amp_scale := k if sway_on else 0.0
	for id in _order:
		var L: Dictionary = _layers[id]
		var def: Dictionary = L["def"]
		var kind: String = def.get("kind", "static")
		var s: Sprite2D = L["sprite"]
		var mat: ShaderMaterial = L["mat"]
		if mat != null:
			mat.set_shader_parameter("t", t)
		if kind == "field" or kind == "cloth":
			var legs: bool = bool(def.get("legs", false))
			mat.set_shader_parameter("pelvis", p["pelvis"])
			mat.set_shader_parameter("chest", chest)
			mat.set_shader_parameter("knee_l", p["knee_l"] if legs else 0.0)
			mat.set_shader_parameter("knee_r", p["knee_r"] if legs else 0.0)
			mat.set_shader_parameter("knee_l_dy", p["knee_l_dy"] if legs else 0.0)
			mat.set_shader_parameter("knee_r_dy", p["knee_r_dy"] if legs else 0.0)
			mat.set_shader_parameter("hip_l_dy", p["hip_l_dy"])
			mat.set_shader_parameter("hip_r_dy", p["hip_r_dy"])
			mat.set_shader_parameter("arm_extra", p["arm_extra"] if bool(def.get("arm_extra", false)) else 0.0)
			if kind == "cloth":
				# amp_max: a cloth layer that carries a patch of skin (the ember skirt) must not slide off the leg by more than this
				mat.set_shader_parameter("amp", minf(float(def.get("amp", 8.0)) * cloth_amp_scale, float(def.get("amp_max", 1000.0))))
		elif kind == "head":
			s.transform = _head_xf
		elif kind == "spring":
			var base := _head_xf if String(def.get("follow", "")) == "head" else chest_t
			var root := Vector2(def["root"][0], def["root"][1])
			s.transform = base * _rot_about(root, float(_springs[id]["a"]))
		elif kind == "arm":
			var piv := Vector2(def["pivot"][0], def["pivot"][1])
			var sh: Array = def.get("breath_pivot", def["pivot"])
			var shoulder := Vector2(sh[0], sh[1])
			var ang := deg_to_rad(float(def.get("rot_deg", 0.0))) * sin(TAU * t / float(def.get("rot_period", 9.0))) * k
			var lift: float = deg_to_rad(float(def.get("breath_deg", 1.0)) * float(p["arm_deg"]) / maxf(_m("arm_breath_deg", 1.5), 0.001))
			var open_dx: float = float(def.get("open", 0.0)) * float(p["open"])
			s.transform = Transform2D(0.0, chest + Vector2(open_dx, p["arm_extra"])) * _rot_about(shoulder, lift) * _rot_about(piv, ang)
		elif kind == "pendulum":
			var root := Vector2(def["root"][0], def["root"][1])
			var swing := deg_to_rad(float(def.get("amp_deg", 3.0))) * sin(TAU * t / float(def.get("period", 2.4)) + 0.7) * k if sway_on else 0.0
			s.transform = Transform2D(0.0, _disp_at(root, p)) * _rot_about(root, swing)
	if _half != null:
		var st := _blink_state(t) if (blink_on and k > 0.0) else 0
		_half.visible = st == 1
		_closed.visible = st == 2
	var intro_p := 1.0
	if _intro_t0 >= 0.0:
		intro_p = clampf((t - _intro_t0) / INTRO_TIME, 0.0, 1.0)
		if _dark_mat != null:
			_dark_mat.set_shader_parameter("p", intro_p)
			_veil.visible = intro_p < 1.0
	var light := 1.0
	if _intro_t0 >= 0.0:
		light = smoothstep(0.0, 0.45, t - _intro_t0)
	for e in _effects:
		var xf := Transform2D.IDENTITY
		var fid: String = e["follow"]
		if fid != "" and _layers.has(fid):
			xf = _layers[fid]["sprite"].transform
		var et: float = t if (glow_on and k > 0.0) else 0.0
		var xf2 := Transform2D.IDENTITY
		if e["follow2"] != "" and _layers.has(e["follow2"]):
			xf2 = _layers[e["follow2"]]["sprite"].transform
		e["node"].call("update", et, xf, light, xf2)
	if _back_fx != null:
		_back_fx.call("set_time", t)
		_front_fx.call("set_time", t)
	if _csv != null:
		var pv: Vector2 = p["pelvis"]
		var line := "%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f" % [t, pv.x, pv.y, chest.y, p["knee_l"], p["knee_r"], p["knee_l_dy"], p["knee_r_dy"], p["head_deg"], chest.x + float(p["head_dx"]), chest.y + float(p["head_dy"])]
		# where the far end of each hair piece is, relative to its place in the still picture (image pixels)
		for id in _tips:
			var tip: Vector2 = _tips[id]
			var d: Vector2 = (_layers[id]["sprite"] as Sprite2D).transform * tip - tip
			line += ",%.3f,%.3f" % [d.x, d.y]
		_csv.store_line(line)
