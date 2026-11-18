extends Node2D
## Rising embers around chosen points of a layer (fire witch). Additive CPUParticles2D, one emitter per point.
## The portrait script calls update() every frame with the transform of the layer the points belong to.

var _emitters: Array[CPUParticles2D] = []
var _points: Array[Vector2] = []


func setup(def: Dictionary) -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var tn: Array = def.get("tint", [1.0, 0.5, 0.1])
	var tc := Color(tn[0], tn[1], tn[2])
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([tc.lerp(Color.WHITE, 0.6), Color(tc, 0.55), Color(tc.darkened(0.5), 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 24
	tex.height = 24
	for e in def.get("emitters", []):
		var p := CPUParticles2D.new()
		p.texture = tex
		p.material = mat
		p.amount = int(e[3])
		p.lifetime = 2.6
		p.preprocess = 2.6
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = float(e[2])
		p.direction = Vector2(0.15, -1.0)
		p.spread = 22.0
		p.initial_velocity_min = 22.0
		p.initial_velocity_max = 55.0
		p.gravity = Vector2(6.0, -10.0)
		p.scale_amount_min = 0.15
		p.scale_amount_max = 0.42
		var ramp := Gradient.new()
		ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.7, 1.0])
		ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
		p.color_ramp = ramp
		add_child(p)
		_emitters.append(p)
		_points.append(Vector2(e[0], e[1]))


func update(_t: float, xf: Transform2D, strength: float, _xf2: Transform2D = Transform2D.IDENTITY) -> void:
	for i in _emitters.size():
		_emitters[i].position = xf * _points[i]
		_emitters[i].modulate.a = strength
