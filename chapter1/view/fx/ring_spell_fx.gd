extends RefCounted
## A6-RS RS1: the ring spell (the close-in block) on screen. One thing has to read: "come inside this ring and you are hit".
## Reads core events and read-only run state only; never writes the run. Owned by ChapterEffects (composition, no inheritance).
##   layer 1 (ready)  a flat ring at the hero's feet, radius = the ring's own radius, always on, alpha rises smoothly with the cooldown.
##   layer 2 (pulse)  cast.shape == "ring": a short band from near_cm to radius_cm (.08 s out, .12 s away), radius from the event.
##   layer 3 (hit)    ember: two orange arcs over a staggered head, and shards where a wind-up was cut; arc: bolts hero -> each target.
##                    frost: the existing ice marks are the reaction, nothing is added.
##   layer 4 (trace)  none on purpose (a mark every .5 s would paint the floor).
## Budget: one MeshInstance3D + one ShaderMaterial (no light), particles 0, strokes only from the shared pool (cap kept by the caller).
const Palette = preload("res://chapter1/view/hud/palette.gd")
const RING_SHADER = preload("res://chapter1/view/ring_spell.gdshader")
const GROUND_Y := .07
const REFRESH_FRAMES := 15
const BOLT_START := .6
const ARCS_PER_CONSUME := 6
const SHARDS_PER_CONSUME := 3
const STYLE := {"ember":0,"frost":1,"arc":2}
const SHADER_MAX_ALPHA := .3

var fx: RefCounted
var enabled := true
## Settings hook (flash strength). 1 = normal; the pulse and the arcs scale with it. No settings screen sets it yet.
var intensity := 1.0
var _view: Node3D
var _mesh: MeshInstance3D
var _material: ShaderMaterial
var _seq := -1
var _frame := 0
var ring_id := ""
var element := ""
var radius := 0.0
var cooldown_ticks := 60
var _pulse_age := -1.0
var _pulse_near := 1.2
var _pulse_floor := 1.0
var _pulse_width := 1.0
var _dull_age := -1.0
var _dull_angle := 0.0
var _hero := Vector2.ZERO
var _run: RefCounted

func setup(owner_view: Node3D) -> void:
	_view = owner_view

## Built on the first frame a run with the spell composition on is seen, so a run without it has no extra node at all.
func _build() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(2,2)
	_mesh = MeshInstance3D.new()
	_mesh.name = "RingSpell"
	_mesh.mesh = plane
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = RING_SHADER
	_mesh.material_override = _material
	_mesh.visible = false
	_view.add_child(_mesh)

func reset() -> void:
	_seq = -1; _frame = 0
	ring_id = ""; element = ""; radius = 0.0
	_pulse_age = -1.0; _dull_age = -1.0
	_run = null
	if is_instance_valid(_mesh): _mesh.visible = false

func _push_stroke(stroke: Dictionary) -> void:
	if fx.strokes.size() < fx.MAX_STROKES: fx.strokes.append(stroke)

## `effects` is the owner (strokes pool, MAX_STROKES, _spells_doc). It is held only for the length of this call: the owner holds
## this object, so a standing reference back would be a reference cycle (leaked at exit).
func consume(events: Array, effects: RefCounted) -> void:
	fx = effects
	_consume(events)
	fx = null

func _consume(events: Array) -> void:
	var arcs := ARCS_PER_CONSUME
	var shards := SHARDS_PER_CONSUME
	for event in events:
		if int(event.seq) <= _seq: continue
		_seq = int(event.seq)
		match String(event.type):
			"cast":
				if String(event.get("shape","")) == "ring": _on_cast(event)
			"hit":
				if Palette.is_ring_spell(String(event.get("skill_id",""))): _on_hit(event)
			"stagger":
				# Only the ember ring staggers (stagger_ticks is in no other spell). Arcs in its own colour, over the head.
				if arcs > 0:
					arcs -= 1
					_push_stroke({"type":"ring_arc","at":event.position,"life":.3,"duration":.3,"color":Palette.FIRE,"count":2})
				if bool(event.get("cut",false)) and shards > 0:
					# "Blocked": the wind-up the red telegraph was showing breaks into three pieces that fade to linen.
					shards -= 1
					_push_stroke({"type":"ring_shard","at":event.position,"life":.15,"duration":.15,"color":Palette.LINEN,"seed":int(event.seq)})

func _on_cast(event: Dictionary) -> void:
	var id := String(event.get("skill_id",""))
	ring_id = id
	element = Palette.spell_element(id,fx._spells_doc)
	radius = float(event.get("radius_cm",0))/100.0
	var effects: Dictionary = event.get("effects",{})
	cooldown_ticks = maxi(1,int(effects.get("cooldown_ticks",cooldown_ticks)))
	_pulse_near = float(effects.get("near_cm",0))/100.0
	_pulse_floor = clampf(float(effects.get("falloff_floor_bps",10000))/10000.0,.1,1.0)
	_pulse_width = .7 if int(event.get("pulse",1)) >= 2 else 1.0
	_pulse_age = 0.0
	_hero = event.position
	if element == "arc":
		var color: Color = Palette.ARC*Color(.8,.8,.8,1.0)
		for target in event.get("targets",[]):
			var span: Vector2 = target-_hero
			if span.length() < .01: continue
			_push_stroke({"type":"ring_bolt","from":_hero+span.normalized()*minf(BOLT_START,span.length()*.5),"to":target,"life":.12,"duration":.12,"color":color,"width":.035})

func _on_hit(event: Dictionary) -> void:
	# A strong enemy (V-7): that slice of the ring dulls to grey for .15 s, "it does not fly back".
	if _run == null: return
	var enemy: Variant = _run.enemies.get(int(event.get("target_id",-1)),null)
	if enemy == null or not bool(enemy.get("elite",false)): return
	var from: Vector2 = event.position-_hero
	if from.length() < .01: return
	_dull_age = 0.0
	_dull_angle = atan2(from.y,from.x)

func sync(run: RefCounted, delta: float, hero_at: Vector3) -> void:
	_run = run
	if run.spells.is_empty():
		if is_instance_valid(_mesh): _mesh.visible = false
		return
	if not is_instance_valid(_mesh): _build()
	if run.mode == "menu" or run.mode == "victory" or run.mode == "defeat":
		_mesh.visible = false
		return
	_frame += 1
	if run.mode == "playing":
		if _pulse_age >= 0.0:
			_pulse_age += delta
			if _pulse_age > .2: _pulse_age = -1.0
		if _dull_age >= 0.0:
			_dull_age += delta
			if _dull_age > .15: _dull_age = -1.0
	if _frame%REFRESH_FRAMES == 1 or ring_id == "": _refresh(run)
	if ring_id == "" or radius <= 0.0:
		_mesh.visible = false
		return
	_mesh.visible = true
	_hero = Vector2(hero_at.x,hero_at.z)
	var half := radius+.6
	_mesh.position = Vector3(hero_at.x,GROUND_Y,hero_at.z)
	_mesh.scale = Vector3(half,1.0,half)
	# Ready: .30 when charged; right after a cast .10, rising with the cooldown (never on/off).
	var next_cast := int(run._next_cast.get(ring_id,0))
	var charged := 1.0
	if next_cast > run.tick: charged = clampf(1.0-float(next_cast-run.tick)/float(cooldown_ticks),0.0,1.0)
	var m := _material
	m.set_shader_parameter("tint",Palette.element_color(element,Palette.BRASS))
	m.set_shader_parameter("radius",radius)
	m.set_shader_parameter("half_size",half)
	m.set_shader_parameter("style",int(STYLE.get(element,0)))
	m.set_shader_parameter("base_alpha",lerpf(.10,.30,charged)*intensity)
	m.set_shader_parameter("pulse_age",_pulse_age)
	m.set_shader_parameter("pulse_near",_pulse_near)
	m.set_shader_parameter("pulse_floor",_pulse_floor)
	m.set_shader_parameter("pulse_width",_pulse_width)
	# The arc colour is already pale: at the same gain it bloomed to white on the lit floor, so its band is weaker.
	m.set_shader_parameter("pulse_gain",SHADER_MAX_ALPHA*intensity*(.62 if element == "arc" else 1.0))
	m.set_shader_parameter("dull_angle",_dull_angle)
	m.set_shader_parameter("dull_age",_dull_age)

## The ring the hero owns and its current radius and cooldown (a reach or power card changes them between casts).
func _refresh(run: RefCounted) -> void:
	var owned: Array = run.growth.owned_spells()
	var found := ""
	for id in owned:
		if Palette.is_ring_spell(String(id)): found = String(id)
	if found == "":
		ring_id = ""
		return
	var skill: Dictionary = run.effective_skill(found)
	if skill.is_empty(): return
	var effects: Dictionary = skill.effects
	ring_id = found
	element = Palette.spell_element(found,run.spells)
	radius = float(effects.get("ring_radius_cm",0))/100.0
	cooldown_ticks = maxi(1,int(effects.get("cooldown_ticks",60)))
