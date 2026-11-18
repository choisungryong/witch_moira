extends Node2D
## The snowflake above the raised hand. The painted snowflake and its rings are cut out of the original (additive
## pieces, see tools/dev/make_living_portrait_flake.py); the engine adds a soft glow, a slow turn of the flake
## (one turn in 20 s), a pulse of light, and tiny specks. Origin is the flake centre.

const GLOW_RADIUS := 100.0
const DISC := preload("res://chapter1/view/hud/living_portrait/flake_disc.png")
const RINGS := preload("res://chapter1/view/hud/living_portrait/flake_rings.png")

var strength := 1.0
var _glow: Sprite2D
var _disc: Sprite2D
var _rings: Sprite2D
var _specks: CPUParticles2D


func _init() -> void:
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(0.5, 0.85, 1.0, 0.7), Color(0.2, 0.55, 1.0, 0.28), Color(0.1, 0.3, 0.8, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	_glow = Sprite2D.new()
	_glow.texture = tex
	_glow.scale = Vector2.ONE * (GLOW_RADIUS * 2.0 / 128.0)
	_glow.material = add
	add_child(_glow)
	_rings = Sprite2D.new()
	_rings.texture = RINGS
	_rings.centered = false
	_rings.position = Vector2(690.0, 10.0) - Vector2(808.0, 112.0)
	_rings.material = add
	add_child(_rings)
	_disc = Sprite2D.new()
	_disc.texture = DISC
	_disc.material = add
	add_child(_disc)
	var dot := Gradient.new()
	dot.offsets = PackedFloat32Array([0.0, 1.0])
	dot.colors = PackedColorArray([Color(0.8, 0.95, 1.0, 1.0), Color(0.5, 0.8, 1.0, 0.0)])
	var dtex := GradientTexture2D.new()
	dtex.gradient = dot
	dtex.fill = GradientTexture2D.FILL_RADIAL
	dtex.fill_from = Vector2(0.5, 0.5)
	dtex.fill_to = Vector2(1.0, 0.5)
	dtex.width = 16
	dtex.height = 16
	_specks = CPUParticles2D.new()
	_specks.texture = dtex
	_specks.amount = 16
	_specks.lifetime = 3.0
	_specks.preprocess = 3.0
	_specks.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_specks.emission_sphere_radius = 55.0
	_specks.direction = Vector2(0.2, -1.0)
	_specks.spread = 25.0
	_specks.initial_velocity_min = 8.0
	_specks.initial_velocity_max = 20.0
	_specks.gravity = Vector2.ZERO
	_specks.scale_amount_min = 0.25
	_specks.scale_amount_max = 0.6
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	_specks.color_ramp = ramp
	add_child(_specks)


var _pos := Vector2(808.0, 112.0)


func setup(def: Dictionary) -> void:
	var p: Array = def.get("pos", [808, 112])
	_pos = Vector2(p[0], p[1])


## xf: transform of the layer the flake belongs to (the raised hand).
func update(t: float, xf: Transform2D, light: float, _xf2: Transform2D = Transform2D.IDENTITY) -> void:
	position = xf * _pos
	strength = light
	set_time(t)


func set_time(t: float) -> void:
	var pulse := (0.88 + 0.12 * sin(TAU * t / 2.5)) * strength
	_glow.modulate.a = pulse
	_disc.modulate = Color(1, 1, 1, clampf(pulse * 1.05, 0.0, 1.0))
	_rings.modulate = Color(1, 1, 1, clampf(0.92 * strength + 0.08 * sin(TAU * t / 3.9), 0.0, 1.0))
	_disc.rotation = TAU * t / 20.0
	_specks.modulate.a = strength
