extends RefCounted
## Combat feel layer: hit flashes, damage numbers, kill bursts, ground marks, spell
## lights and the overall look (glow, contrast, camera distance).
## Presentation only. It reads core events and never writes game state, so the
## golden replay is unaffected. Everything is pooled and bounded.
const Loc = preload("res://chapter1/view/loc.gd")
const COLORS := {"chapter1.skill.ember":Color("ff943d"),"chapter1.skill.frost":Color("9ce7ef"),"chapter1.skill.arc":Color("b9caff")}
const ARC_LIGHT_COLOR := Color("6f88ff")
const ARC_PULSE_COLOR := Color("86a0ff")
const NUMBER_POOL := 40
const HEAVY_POOL := 16
const SPARK_POOL := 128
## A6-2: pool 64 -> 32 (visible marks are about 16 at the densest, spec 4.5); sparks per frame 20 -> 8.
const MARK_POOL := 32
const BURST_POOL := 16
const LIGHT_POOL := 6
## Look 2: effect lights reach further into the darker floor.
const LIGHT_GAIN := 1.6
const NUMBERS_PER_FRAME := 5
const SPARKS_PER_FRAME := 8
const BURSTS_PER_FRAME := 5
const LIGHTS_PER_FRAME := 2
const MINOR_LIGHT_LIMIT := 3
const MARK_SECONDS := 3.0
const MARK_FADE := 1.0
## One bright layer per event: a second flash or light within FLASH_RADIUS metres of a recent one
## is skipped for FLASH_HOLD seconds (explosion / shatter only).
const FLASH_RADIUS := 2.0
const FLASH_HOLD := .15
const FLASH_SLOTS := 4
## Damage numbers: hits on one target within NUMBER_MERGE seconds share one label; at most
## NUMBER_CELL_LIMIT (heavy: HEAVY_CELL_LIMIT) labels of a size live in one NUMBER_CELL metre ground cell.
const NUMBER_MERGE := .25
const NUMBER_CELL := 2.0
const NUMBER_CELL_LIMIT := 2
const HEAVY_CELL_LIMIT := 1
const NUMBER_FADE := .22
const NUMBER_FONT := 32
const HEAVY_FONT := 58
## Ground marks fade in a shader from a per-instance end time and one clock uniform, so a mark
## costs nothing per frame after it is placed.
const MARK_SHADER := "shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;
uniform sampler2D soft : source_color, filter_linear;
uniform float clock = 0.0;
uniform float fade_seconds = 2.5;
uniform float life_seconds = 3.0;
varying vec4 tint;
varying float fade;
varying float ember_seed;
varying float spawn;
void vertex() {
	tint = COLOR;
	fade = clamp((INSTANCE_CUSTOM.x - clock) / fade_seconds, 0.0, 1.0);
	ember_seed = INSTANCE_CUSTOM.y;
	spawn = INSTANCE_CUSTOM.x - life_seconds;
}
float ember_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
// Instance colours are authored as on-screen sRGB; ALBEDO is linear, so convert here.
vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}
void fragment() {
	vec4 t = texture(soft, UV);
	vec3 albedo = srgb_to_linear(tint.rgb) * t.rgb;
	float alpha = tint.a * t.a * fade;
	// A6-2 fire, layer 4 (trace): 3 to 6 ember dots on a charcoal mark go out one by one inside about 1.5 s.
	// Seed 0 (every other mark) skips this entirely. No per-frame work: the clock uniform drives it.
	if (ember_seed > 0.0) {
		float count = 3.0 + floor(ember_hash(vec2(ember_seed, 1.0)) * 4.0);
		float glow = 0.0;
		for (int i = 0; i < 6; i++) {
			float fi = float(i);
			if (fi >= count) break;
			float a = ember_hash(vec2(ember_seed, fi + 2.0)) * 6.2832;
			float rad = sqrt(ember_hash(vec2(ember_seed, fi + 9.0))) * 0.34;
			vec2 c = vec2(0.5) + vec2(cos(a), sin(a)) * rad;
			float die = 0.35 + (fi + ember_hash(vec2(ember_seed, fi + 17.0))) / count * 1.15;
			float on = 1.0 - smoothstep(die - 0.25, die, clock - spawn);
			glow = max(glow, (1.0 - smoothstep(0.04, 0.07, distance(UV, c))) * on);
		}
		albedo = mix(albedo, srgb_to_linear(vec3(0.95, 0.50, 0.16)) * 0.8, glow);
		alpha = max(alpha, glow * 0.9);
	}
	ALBEDO = albedo;
	ALPHA = alpha;
}
"

var view: Node3D
var holder: Node3D
var show_numbers := true
var reduced_flash := false
var _last_seq := -1
var _rng := RandomNumberGenerator.new()
var _soft: GradientTexture2D
var _clock := 0.0
var _was_playing := true
var _numbers: Array[Label3D] = []
var _number_life := PackedFloat32Array()
var _number_total := PackedFloat32Array()
var _number_rise := PackedFloat32Array()
var _number_drift := PackedFloat32Array()
var _number_pos := PackedVector3Array()
var _number_active := PackedInt32Array()
var _number_target := PackedInt32Array()
var _number_amount := PackedInt32Array()
var _number_cell := PackedInt32Array()
var _number_next := 0
var _heavy_next := 0
var _sparks: MultiMeshInstance3D
## Spark pool written through one float buffer (transform 12 + colour 4 floats per instance), uploaded once
## per frame while any spark is alive or just died. Same values as the per-instance calls it replaced.
const SPARK_STRIDE := 16
var _spark_buf := PackedFloat32Array()
var _spark_dirty := false
## Experiment (off by default): --chapter1-fx-fade-transparency fades damage numbers with
## GeometryInstance3D.transparency instead of re-tinting modulate/outline_modulate every frame.
var fade_by_transparency := false
var _spark_life := PackedFloat32Array()
var _spark_total := PackedFloat32Array()
var _spark_size := PackedFloat32Array()
var _spark_at := PackedVector3Array()
var _spark_color := PackedColorArray()
var _spark_active := PackedInt32Array()
var _spark_next := 0
var _marks: MultiMeshInstance3D
var _mark_material: ShaderMaterial
var _mark_next := 0
var _mark_expiry := PackedFloat32Array()
var _bursts: Array[GPUParticles3D] = []
var _burst_next := 0
var _lights: Array[OmniLight3D] = []
var _light_life := PackedFloat32Array()
var _light_total := PackedFloat32Array()
var _light_energy := PackedFloat32Array()
## The same lights, as the "darkness lifted here" field read by the ground, grass and prop shaders:
## per slot (x, z, reach in metres, strength 0..1). Handed to the world only when a slot changed.
const SPELL_LIFT_REACH := 1.1
const SPELL_LIFT_PER_ENERGY := .22
var _lift := PackedVector4Array()
var _lift_dirty := false
var _lift_world: RefCounted
var _light_active := PackedInt32Array()
var _light_next := 0
var _flash_at := PackedVector2Array()
var _flash_time := PackedFloat32Array()
var _flash_next := 0
## Counters for checks and tuning.
var stats := {"numbers":0,"sparks":0,"marks":0,"bursts":0,"lights":0,"numbers_merged":0,"numbers_dropped":0,"flashes_skipped":0,"marks_live_peak":0}

func setup(owner_view: Node3D) -> void:
	view = owner_view
	_rng.seed = 51607
	holder = Node3D.new(); holder.name = "CombatJuice"
	view.add_child(holder)
	var gradient := Gradient.new()
	gradient.set_color(0,Color(1,1,1,1)); gradient.set_color(1,Color(1,1,1,0))
	_soft = GradientTexture2D.new()
	_soft.gradient = gradient; _soft.fill = GradientTexture2D.FILL_RADIAL
	_soft.fill_from = Vector2(.5,.5); _soft.fill_to = Vector2(1,.5); _soft.width = 64; _soft.height = 64
	_flash_at.resize(FLASH_SLOTS); _flash_time.resize(FLASH_SLOTS)
	_flash_time.fill(-10.0)
	_mark_expiry.resize(MARK_POOL)
	for arg in OS.get_cmdline_user_args():
		if arg == "--chapter1-fx-fade-transparency": fade_by_transparency = true
	_build_numbers(); _build_sparks(); _build_marks(); _build_bursts(); _build_lights()

func _additive(billboard: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = _soft
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	if billboard:
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.billboard_keep_scale = true
	return material

func _pool(mesh: Mesh, capacity: int, material: Material, name_: String, custom := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = capacity
	var node := MultiMeshInstance3D.new()
	node.name = name_; node.multimesh = mm; node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in capacity:
		mm.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),Vector3(0,-50,0)))
		mm.set_instance_color(i,Color(0,0,0,0))
	holder.add_child(node)
	return node

## Two label pools (normal and heavy size) so font_size is never changed after setup.
func _build_numbers() -> void:
	for i in NUMBER_POOL+HEAVY_POOL:
		var label := Label3D.new()
		label.font = Loc.font("number")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.pixel_size = .012
		label.font_size = NUMBER_FONT if i < NUMBER_POOL else HEAVY_FONT
		label.outline_size = 12
		label.outline_modulate = Color(0,0,0,.9)
		label.render_priority = 4
		label.visible = false
		holder.add_child(label)
		_numbers.append(label)
	var count := NUMBER_POOL+HEAVY_POOL
	_number_life.resize(count); _number_total.resize(count); _number_rise.resize(count)
	_number_drift.resize(count); _number_pos.resize(count)
	_number_target.resize(count); _number_amount.resize(count); _number_cell.resize(count)

func _build_sparks() -> void:
	var quad := QuadMesh.new(); quad.size = Vector2.ONE
	_sparks = _pool(quad,SPARK_POOL,_additive(true),"HitFlashes")
	_spark_life.resize(SPARK_POOL); _spark_total.resize(SPARK_POOL); _spark_size.resize(SPARK_POOL)
	_spark_at.resize(SPARK_POOL); _spark_color.resize(SPARK_POOL)
	var spark_mm := _sparks.multimesh
	_spark_buf = spark_mm.buffer
	if _spark_buf.size() != SPARK_POOL*SPARK_STRIDE: _spark_buf.resize(SPARK_POOL*SPARK_STRIDE)

func _build_marks() -> void:
	var plane := PlaneMesh.new(); plane.size = Vector2.ONE
	var shader := Shader.new(); shader.code = MARK_SHADER
	_mark_material = ShaderMaterial.new()
	_mark_material.shader = shader
	_mark_material.set_shader_parameter("soft",_soft)
	_mark_material.set_shader_parameter("fade_seconds",MARK_FADE)
	_mark_material.set_shader_parameter("life_seconds",MARK_SECONDS)
	_mark_material.render_priority = -2
	_marks = _pool(plane,MARK_POOL,_mark_material,"GroundMarks",true)

func _build_bursts() -> void:
	var fade := Gradient.new()
	fade.set_color(0,Color(1,1,1,1)); fade.set_color(1,Color(1,1,1,0))
	var ramp := GradientTexture1D.new(); ramp.gradient = fade
	var burst_quad := QuadMesh.new(); burst_quad.size = Vector2(.17,.17)
	burst_quad.material = _additive(true)
	for i in BURST_POOL:
		var particles := GPUParticles3D.new()
		particles.one_shot = true; particles.emitting = false
		particles.amount = 22; particles.lifetime = .55; particles.explosiveness = 1.0
		particles.local_coords = false
		particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process.emission_sphere_radius = .22
		process.direction = Vector3.UP; process.spread = 80.0
		process.initial_velocity_min = 2.2; process.initial_velocity_max = 6.0
		process.gravity = Vector3(0,-10,0)
		process.scale_min = .55; process.scale_max = 1.35
		process.color_ramp = ramp
		particles.process_material = process
		particles.draw_pass_1 = burst_quad
		holder.add_child(particles)
		_bursts.append(particles)

func _build_lights() -> void:
	for i in LIGHT_POOL:
		var light := OmniLight3D.new()
		light.shadow_enabled = false
		light.omni_attenuation = 1.4
		light.light_energy = 0.0
		light.visible = false
		holder.add_child(light)
		_lights.append(light)
	_light_life.resize(LIGHT_POOL); _light_total.resize(LIGHT_POOL); _light_energy.resize(LIGHT_POOL)
	_lift.resize(LIGHT_POOL)

## Glow, contrast and camera distance. Called once after the world exists.
func apply_look(world: RefCounted) -> void:
	_lift_world = world if world != null and world.has_method("set_spell_lights") else null
	var camera: Camera3D = world.get("camera")
	if camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		camera.size = 19.5
	var environment_node := _find_environment(view)
	if environment_node == null or environment_node.environment == null: return
	var environment: Environment = environment_node.environment
	environment.glow_enabled = true
	environment.glow_intensity = .95
	environment.glow_bloom = .12
	environment.glow_strength = 1.0
	environment.glow_hdr_threshold = .9
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.34
	environment.adjustment_saturation = 1.34
	environment.adjustment_brightness = 1.04

func _find_environment(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment: return node
	for child in node.get_children():
		var found := _find_environment(child)
		if found != null: return found
	return null

func _color(skill_id: String) -> Color:
	return COLORS.get(skill_id,Color("e0c69d"))

func consume(events: Array) -> void:
	var numbers := NUMBERS_PER_FRAME
	var sparks := SPARKS_PER_FRAME
	var bursts := BURSTS_PER_FRAME
	var lights := LIGHTS_PER_FRAME
	for event in events:
		if int(event.seq) <= _last_seq: continue
		_last_seq = int(event.seq)
		var at: Vector2 = event.position
		var color := _color(String(event.get("skill_id","")))
		match String(event.type):
			"hit":
				if sparks > 0:
					sparks -= 1
					_spark(at,color,.42 if not event.get("shatter",false) else .8,.10)
				if show_numbers and numbers > 0 and event.has("damage_raw"):
					if _number(at,int(round(float(event.damage_raw)/256.0)),color,event.get("shatter",false),int(event.get("target_id",-1))):
						numbers -= 1
				if lights > 0 and event.get("shatter",false) and _light_active.size() < MINOR_LIGHT_LIMIT:
					lights -= 1; _light(at,color,2.6,4.5,.16)
			"death":
				if bursts > 0:
					bursts -= 1
					_burst(at,color,3 if event.get("elite",false) else 1)
				# Ground marks only for elites (and explosions below): a mark per kill painted the floor.
				if event.get("elite",false): _mark(at,String(event.get("skill_id","")),1.9)
				if sparks > 0:
					sparks -= 1; _spark(at,color,1.0,.14)
			"explosion":
				var radius := float(event.get("radius_cm",150))/100.0
				# Arc's residual pulse (3 m) went near-white and covered the hero in a crowd:
				# keep it blue and a bit smaller. Other elements are unchanged.
				var pulse_color := color
				var pulse_scale := 1.1
				if color.is_equal_approx(COLORS["chapter1.skill.arc"]): pulse_color = ARC_PULSE_COLOR; pulse_scale = 1.0
				var ember_boom: bool = String(event.get("skill_id","")) == "chapter1.skill.ember"
				if _flash_free(at):
					# A6-2: the disc shader owns the hot centre, so the soft flash is a smaller, deeper orange
					# and the light is weaker; one bright layer per spot (A6 3.3 L3), three lights at most.
					if ember_boom: pulse_color = Color("e8801f"); pulse_scale = .65
					_spark(at,pulse_color,radius*pulse_scale,.2)
					if lights > 0 and _light_active.size() < MINOR_LIGHT_LIMIT:
						lights -= 1; _light(at,color,1.8 if ember_boom else 2.5,maxf(5.0,radius*2.6),.26)
					_mark(at,String(event.get("skill_id","")),radius*.6,ember_boom and radius >= 2.2)
			"shatter":
				if _flash_free(at):
					_spark(at,Color(.85,.97,1.0),1.3,.14)
					if lights > 0:
						lights -= 1; _light(at,Color("c8f2ff"),3.0,6.0,.28)
					_mark(at,"chapter1.skill.frost",1.6)
				if bursts > 0:
					bursts -= 1; _burst(at,Color("d9f6ff"),2)
				_kick(.22)
			"cast":
				# A6-2: the cast light is gone (A6 4.5: the "ready" mark has no light). The ground ring in chapter_effects replaces it.
				pass
			"stun":
				if sparks > 0:
					sparks -= 1; _spark(at,Color("ffe08a"),.8,.14)
			"hero_hit":
				if event.get("graze",false):
					# Softened big hit (core rule): small grey-red flash, no light.
					_spark(at,Color("b5a8a2"),.9,.12)
				else:
					_spark(at,Color("ff5236"),1.5,.2)
					if lights > 0:
						lights -= 1; _light(at,Color("ff4a30"),3.2,5.0,.22)
			"child_projectiles":
				# A kill that sprays child shards: a short burst of the spell's own colour where the
				# enemy died, so the shards read as the hero's spell tearing the body apart, not as
				# shots from the monster. One pooled spark (no new draw call), ~.2 s.
				if sparks > 0:
					sparks -= 1
					var burst_color := ARC_PULSE_COLOR if color.is_equal_approx(COLORS["chapter1.skill.arc"]) else color
					_spark(at,burst_color,1.05,.2)
			"growth","seal_grace":
				_spark(at,Color("ffe6a8"),3.2,.4)
				_light(at,Color("ffdf9a"),4.5,8.0,.5)
				_burst(at,Color("ffe6a8"),2)
			"item_drop":
				var item: Dictionary = event.get("item",{})
				if item.get("quality","") in ["legendary","unique"] or item.get("slot","") in ["ring","charm"]:
					_spark(at,Color("ffd27a"),2.2,.35)
					_light(at,Color("ffca6b"),3.6,6.0,.45)

func _kick(strength: float) -> void:
	var world: Variant = view.get("world")
	if world != null and world.has_method("kick_camera"): world.kick_camera(strength)

## Returns true when a new label was taken from the pool (false: merged into a live one or dropped).
func _number(at: Vector2, amount: int, color: Color, heavy: bool, target: int) -> bool:
	if amount <= 0: return false
	var first := NUMBER_POOL if heavy else 0
	var last := NUMBER_POOL+HEAVY_POOL if heavy else NUMBER_POOL
	var cell := (int(floor(at.x/NUMBER_CELL))+512)*1024+(int(floor(at.y/NUMBER_CELL))+512)
	var in_cell := 0
	for live in _number_active:
		if live < first or live >= last: continue
		if target >= 0 and _number_target[live] == target and _number_total[live]-_number_life[live] < NUMBER_MERGE:
			# Same target hit again within a quarter second: rewrite the live label with the sum.
			_number_amount[live] += amount
			_numbers[live].text = str(_number_amount[live])
			stats.numbers_merged += 1
			return false
		if _number_cell[live] == cell: in_cell += 1
	if in_cell >= (HEAVY_CELL_LIMIT if heavy else NUMBER_CELL_LIMIT):
		stats.numbers_dropped += 1
		return false
	var index: int
	if heavy:
		index = NUMBER_POOL+_heavy_next
		_heavy_next = (_heavy_next+1)%HEAVY_POOL
	else:
		index = _number_next
		_number_next = (_number_next+1)%NUMBER_POOL
	var label := _numbers[index]
	var text := str(amount)
	if label.text != text: label.text = text
	label.modulate = Color.WHITE.lerp(color,.20) if not heavy else Color("ffffff")
	label.outline_modulate = Color(0,0,0,.9)
	if fade_by_transparency and label.transparency != 0.0: label.transparency = 0.0
	var offset := Vector3(_rng.randf_range(-.35,.35),1.5+_rng.randf_range(0,.25),_rng.randf_range(-.2,.2))
	var position_ := Vector3(at.x,0,at.y)+offset
	label.position = position_
	label.visible = true
	if _number_life[index] <= 0: _number_active.append(index)
	_number_life[index] = .62; _number_total[index] = .62
	_number_rise[index] = 1.25 if heavy else .95
	_number_drift[index] = _rng.randf_range(-.35,.35)
	_number_pos[index] = position_
	_number_target[index] = target; _number_amount[index] = amount; _number_cell[index] = cell
	stats.numbers += 1
	return true

## True when no explosion/shatter flash happened within FLASH_RADIUS in the last FLASH_HOLD seconds;
## records this one. Four ring slots, position and clock compare only.
func _flash_free(at: Vector2) -> bool:
	for slot in FLASH_SLOTS:
		if _clock-_flash_time[slot] < FLASH_HOLD and _flash_at[slot].distance_squared_to(at) < FLASH_RADIUS*FLASH_RADIUS:
			stats.flashes_skipped += 1
			return false
	_flash_at[_flash_next] = at; _flash_time[_flash_next] = _clock
	_flash_next = (_flash_next+1)%FLASH_SLOTS
	return true

func _spark(at: Vector2, color: Color, size: float, seconds: float) -> void:
	if reduced_flash: size *= .6
	var index := _spark_next
	_spark_next = (_spark_next+1)%SPARK_POOL
	if _spark_life[index] <= 0: _spark_active.append(index)
	_spark_life[index] = seconds; _spark_total[index] = seconds
	_spark_at[index] = Vector3(at.x,.95,at.y); _spark_size[index] = size; _spark_color[index] = color
	stats.sparks += 1

func _mark(at: Vector2, skill_id: String, size: float, embers := false) -> void:
	# Colours are on-screen sRGB (the mark shader linearises them) and darker than the floor (~54,60,66).
	var tint := Color8(20,20,22,150)
	if skill_id == "chapter1.skill.frost": tint = Color8(30,40,50,90)
	elif skill_id == "chapter1.skill.ember": tint = Color8(24,15,10,190 if embers else 170)
	elif skill_id == "chapter1.skill.arc": tint = Color8(14,16,26,150)
	var index := _mark_next
	_mark_next = (_mark_next+1)%MARK_POOL
	var scale := size*_rng.randf_range(.75,1.1)
	var basis := Basis(Vector3.UP,_rng.randf_range(0,TAU)).scaled(Vector3(scale,1,scale*_rng.randf_range(.7,1.0)))
	var mm := _marks.multimesh
	mm.set_instance_transform(index,Transform3D(basis,Vector3(at.x,.028+float(index%8)*.0006,at.y)))
	mm.set_instance_color(index,tint)
	# custom.y > 0 asks the mark shader for ember dots (a seed in 1..51); 0 keeps a plain mark.
	mm.set_instance_custom_data(index,Color(_clock+MARK_SECONDS,1.0+_rng.randf()*50.0 if embers else 0.0,0,0))
	_mark_expiry[index] = _clock+MARK_SECONDS
	var live := 0
	for expiry in _mark_expiry:
		if expiry > _clock: live += 1
	stats.marks_live_peak = maxi(int(stats.marks_live_peak),live)
	stats.marks += 1

func _burst(at: Vector2, color: Color, count: int) -> void:
	for i in count:
		var particles := _bursts[_burst_next]
		_burst_next = (_burst_next+1)%BURST_POOL
		particles.position = Vector3(at.x,.8+float(i)*.25,at.y)
		(particles.process_material as ParticleProcessMaterial).color = color
		particles.restart(); particles.emitting = true
		stats.bursts += 1

func _light(at: Vector2, color: Color, energy: float, range_: float, seconds: float) -> void:
	energy *= LIGHT_GAIN
	if reduced_flash: energy *= .5
	# Arc's pale #b9caff lights read as a white wash on the stone floor; light with the saturated arc blue.
	if color.is_equal_approx(COLORS["chapter1.skill.arc"]): color = ARC_LIGHT_COLOR; energy *= .8
	var index := _light_next
	_light_next = (_light_next+1)%LIGHT_POOL
	var light := _lights[index]
	light.position = Vector3(at.x,1.3,at.y)
	light.light_color = color; light.omni_range = range_; light.light_energy = energy; light.visible = true
	if _light_life[index] <= 0: _light_active.append(index)
	_light_life[index] = seconds; _light_total[index] = seconds; _light_energy[index] = energy
	_lift[index] = Vector4(at.x,at.y,range_*SPELL_LIFT_REACH,clampf(energy*SPELL_LIFT_PER_ENERGY,0,1)); _lift_dirty = true
	stats.lights += 1

## Only live entries are visited. Nothing is rewritten for a paused frame, and the pool
## state lives in packed arrays instead of per-entry dictionaries.
func sync(run: RefCounted, delta: float) -> void:
	var playing: bool = run.mode == "playing"
	if playing != _was_playing:
		_was_playing = playing
		var speed := 1.0 if playing else 0.0
		for particles in _bursts: particles.speed_scale = speed
	if not playing or delta <= 0.0: return
	_clock += delta
	_mark_material.set_shader_parameter("clock",_clock)
	var at := 0
	while at < _number_active.size():
		var index := _number_active[at]
		var life := _number_life[index]-delta
		_number_life[index] = life
		var label := _numbers[index]
		if life <= 0:
			label.visible = false
			if fade_by_transparency: label.transparency = 0.0
			_number_active[at] = _number_active[_number_active.size()-1]; _number_active.resize(_number_active.size()-1)
			continue
		var age := 1.0-life/_number_total[index]
		var position_ := _number_pos[index]
		position_.y += _number_rise[index]*delta*(1.0-age*.6)
		position_.x += _number_drift[index]*delta
		_number_pos[index] = position_
		label.position = position_
		if life < NUMBER_FADE:
			var alpha := clampf(life/NUMBER_FADE,0,1)
			if fade_by_transparency:
				# modulate.a stays 1 and outline_modulate.a stays .9 (set when the label is taken); the
				# instance transparency multiplies both by the same alpha.
				label.transparency = 1.0-alpha
			else:
				var tint := label.modulate; tint.a = alpha; label.modulate = tint
				var outline := label.outline_modulate; outline.a = alpha*.9; label.outline_modulate = outline
		at += 1
	var buf := _spark_buf
	at = 0
	while at < _spark_active.size():
		var index := _spark_active[at]
		var life := _spark_life[index]-delta
		_spark_life[index] = life
		if life <= 0:
			var dead := index*SPARK_STRIDE+12
			buf[dead] = 0.0; buf[dead+1] = 0.0; buf[dead+2] = 0.0; buf[dead+3] = 0.0
			_spark_dirty = true
			_spark_active[at] = _spark_active[_spark_active.size()-1]; _spark_active.resize(_spark_active.size()-1)
			continue
		var age := 1.0-life/_spark_total[index]
		var size := _spark_size[index]*(.45+age*.9)
		var o := index*SPARK_STRIDE
		var org := _spark_at[index]
		# Basis.scaled(ONE*size) of the identity is a diagonal matrix; the transform floats are row-major.
		buf[o] = size; buf[o+1] = 0.0; buf[o+2] = 0.0; buf[o+3] = org.x
		buf[o+4] = 0.0; buf[o+5] = size; buf[o+6] = 0.0; buf[o+7] = org.y
		buf[o+8] = 0.0; buf[o+9] = 0.0; buf[o+10] = size; buf[o+11] = org.z
		var color := _spark_color[index]
		color.a = (1.0-age)*(1.0-age)*.7
		buf[o+12] = color.r; buf[o+13] = color.g; buf[o+14] = color.b; buf[o+15] = color.a
		_spark_dirty = true
		at += 1
	if _spark_dirty:
		_spark_dirty = false
		RenderingServer.multimesh_set_buffer(_sparks.multimesh.get_rid(),buf)
	at = 0
	while at < _light_active.size():
		var index := _light_active[at]
		var life := _light_life[index]-delta
		_light_life[index] = life
		var light := _lights[index]
		if life <= 0:
			light.visible = false; light.light_energy = 0
			_lift[index] = Vector4.ZERO; _lift_dirty = true
			_light_active[at] = _light_active[_light_active.size()-1]; _light_active.resize(_light_active.size()-1)
			continue
		var fade := pow(life/_light_total[index],1.6)
		light.light_energy = _light_energy[index]*fade
		var lift := _lift[index]; lift.w = clampf(_light_energy[index]*fade*SPELL_LIFT_PER_ENERGY,0,1); _lift[index] = lift; _lift_dirty = true
		at += 1
	if _lift_dirty and _lift_world != null:
		_lift_dirty = false
		_lift_world.set_spell_lights(_lift)

func reset() -> void:
	_last_seq = -1
	_clock = 0.0
	_mark_material.set_shader_parameter("clock",0.0)
	_number_active.clear(); _spark_active.clear(); _light_active.clear()
	_flash_time.fill(-10.0); _flash_next = 0; _mark_expiry.fill(0.0)
	for index in _numbers.size():
		_number_life[index] = 0.0; _numbers[index].visible = false
		if fade_by_transparency: _numbers[index].transparency = 0.0
	for index in SPARK_POOL:
		_spark_life[index] = 0.0
		var o := index*SPARK_STRIDE+12
		_spark_buf[o] = 0.0; _spark_buf[o+1] = 0.0; _spark_buf[o+2] = 0.0; _spark_buf[o+3] = 0.0
	RenderingServer.multimesh_set_buffer(_sparks.multimesh.get_rid(),_spark_buf)
	_spark_dirty = false
	for index in MARK_POOL:
		_marks.multimesh.set_instance_color(index,Color(0,0,0,0)); _marks.multimesh.set_instance_custom_data(index,Color(0,0,0,0))
	for index in LIGHT_POOL:
		_light_life[index] = 0.0; _lights[index].visible = false; _lift[index] = Vector4.ZERO
	if _lift_world != null: _lift_world.set_spell_lights(_lift)
	_lift_dirty = false
	for particles in _bursts: particles.emitting = false
	for key in stats: stats[key] = 0
