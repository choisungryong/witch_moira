extends RefCounted
## A6-RS RS1 + RS2: the ring spell (the close-in block) and the moments its pairing with the basic spell fires, on screen.
## Reads core events and read-only run state only; never writes the run. Owned by ChapterEffects (composition, no inheritance).
##   layer 1 (ready)  a flat ring at the hero's feet, radius = the ring's own radius, always on, alpha rises smoothly with the cooldown.
##   layer 2 (pulse)  cast.shape == "ring": a short band from near_cm to radius_cm (.08 s out, .12 s away), radius from the event.
##   layer 3 (hit)    ember: two orange arcs over a staggered head, and shards where a wind-up was cut; arc: bolts hero -> each target
##                    and a zig mark on a stunned body. frost: the existing ice marks are the reaction, nothing is added.
##   layer 4 (trace)  none on purpose (a mark every .5 s would paint the floor).
## RS2, "the pairing worked" (the colour stays the basic spell's own, only a shape is borrowed from the one that held the enemy):
##   I1  hit.vs_cc      a basic spell hit an enemy the ring (or a borrowed spell) had held: 1.3x flash (in combat_juice) + a small mark
##                      on that enemy: frozen = ring with six spikes, stunned = two zigs, staggered = two short arcs, slowed = thin ring.
##   I2  detonate       the ring blew the basic spell's mark: that slice of the ring (30 degrees) swells for .24 s (shader; .15 s in the brief, longer so it outlasts the pulse it starts with) and the
##                      enemy gets the mark's own shape (heat = three embers, chill = spiked ring, shock = zigs), .2 s.
##   I0  cast.prefer    the basic spell aimed at a far ranged enemy first: a small linen tick in front of the staff (.1 s); the arc
##                      chain gets a thin linen ring at its first target (.2 s). No crimson: it is the hero's aim, not a threat.
## Budget: one MeshInstance3D + one ShaderMaterial (no light), particles 0, strokes only from the shared pool (cap kept by the caller).
const Palette = preload("res://chapter1/view/hud/palette.gd")
const RING_SHADER = preload("res://chapter1/view/ring_spell.gdshader")
const GROUND_Y := .07
const REFRESH_FRAMES := 15
const BOLT_START := 1.1 ## was .6: the thicker bolt started inside the hero's box and raised its white saturation (arc ring cast +4 points)
const ARCS_PER_CONSUME := 4
const SHARDS_PER_CONSUME := 3
const CC_PER_CONSUME := 4
const STUN_MARKS_PER_CONSUME := 3
const THICK_SLOTS := 3
const STYLE := {"ember":0,"frost":1,"arc":2}
const SHADER_MAX_ALPHA := .3
const STROKE_TYPES := ["ring_arc","ring_shard","ring_bolt","rs_cc","rs_aim"]
## status a detonation consumed -> the mark shape it leaves on the enemy, and the colour of that spell
const STATUS_SHAPE := {"heat":"embers","chill":"frozen","shock":"stunned"}
const STATUS_ELEMENT := {"heat":"ember","chill":"frost","shock":"arc"}

var fx: RefCounted
var enabled := true
## Settings hook (flash strength). 1 = normal; the pulse, the marks and the arcs scale with it. 0 draws none of the strokes.
## No settings screen sets it yet.
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
var _thick_angle := PackedFloat32Array([0.0,0.0,0.0])
var _thick_age := PackedFloat32Array([-1.0,-1.0,-1.0])
var _thick_next := 0
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
	_thick_age = PackedFloat32Array([-1.0,-1.0,-1.0]); _thick_next = 0
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
	var marks := CC_PER_CONSUME
	var stuns := STUN_MARKS_PER_CONSUME
	var swells := THICK_SLOTS
	for event in events:
		if int(event.seq) <= _seq: continue
		_seq = int(event.seq)
		match String(event.type):
			"cast":
				if String(event.get("shape","")) == "ring": _on_cast(event)
				elif String(event.get("prefer","")) == "kind": _on_aim(event)
			"hit":
				var skill_id := String(event.get("skill_id",""))
				if Palette.is_ring_spell(skill_id): _on_hit(event)
				elif event.has("vs_cc") and marks > 0:
					# I1: the colour is the spell that hit, the shape is the one that held the enemy.
					marks -= 1
					_push_stroke({"type":"rs_cc","kind":String(event.vs_cc),"at":event.position,"life":.15,"duration":.15,
						"color":Palette.spell_color(skill_id,fx._spells_doc,Palette.LINEN),"scale":1.0,"seed":int(event.seq)})
			"detonate":
				# I2: the slice of the ring toward the enemy swells, the enemy shows the shape of the mark that went off.
				var status := String(event.get("status",""))
				if swells > 0 and _hero != event.position:
					swells -= 1
					var away: Vector2 = event.position-_hero
					_thick_angle[_thick_next] = atan2(away.y,away.x)
					_thick_age[_thick_next] = 0.0
					_thick_next = (_thick_next+1)%THICK_SLOTS
				if STATUS_SHAPE.has(status):
					_push_stroke({"type":"rs_cc","kind":STATUS_SHAPE[status],"at":event.position,"life":.2,"duration":.2,
						"color":Palette.element_color(STATUS_ELEMENT[status],Palette.LINEN),"scale":.8,"seed":int(event.seq)})
			"stun":
				# The ring's own stun (arc): a zig in the arc colour on the stunned body. The old yellow stays for other stuns.
				if stuns > 0 and Palette.is_ring_spell(String(event.get("skill_id",""))):
					stuns -= 1
					_push_stroke({"type":"rs_cc","kind":"stunned","at":event.position,"life":.15,"duration":.15,"color":Palette.ARC,"scale":.9,"seed":int(event.seq)})
			"stagger":
				# Only the ember ring staggers (stagger_ticks is in no other spell). Arcs in its own colour, over the head.
				if arcs > 0:
					arcs -= 1
					_push_stroke({"type":"ring_arc","at":event.position,"life":.35,"duration":.35,"color":Palette.FIRE,"count":2})
				if bool(event.get("cut",false)) and shards > 0:
					# "Blocked": the wind-up the red telegraph was showing breaks into three pieces that fade to linen.
					shards -= 1
					_push_stroke({"type":"ring_shard","at":event.position,"life":.18,"duration":.18,"color":Palette.LINEN,"seed":int(event.seq)})

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
		var color: Color = Palette.ARC
		for target in event.get("targets",[]):
			var span: Vector2 = target-_hero
			if span.length() < .01: continue
			_push_stroke({"type":"ring_bolt","from":_hero+span.normalized()*minf(BOLT_START,span.length()*.5),"to":target,"life":.14,"duration":.14,"color":color,"width":.05})

## I0: the basic spell took a far ranged enemy first. Small on purpose (V-9). Fire and frost carry no target position in the cast
## (D-2 is not decided), so they get a tick along the aim; the arc chain knows its first target and rings it.
func _on_aim(event: Dictionary) -> void:
	var targets: Array = event.get("targets",[])
	if targets.size() > 0:
		_push_stroke({"type":"rs_aim","kind":"ring","at":targets[0],"dir":Vector2.RIGHT,"life":.2,"duration":.2,"color":Palette.LINEN})
	else:
		var dir: Vector2 = event.get("direction",Vector2.RIGHT)
		_push_stroke({"type":"rs_aim","kind":"tick","at":event.position,"dir":dir.normalized() if dir.length() > .01 else Vector2.RIGHT,"life":.1,"duration":.1,"color":Palette.LINEN})

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
		for i in THICK_SLOTS:
			if _thick_age[i] >= 0.0:
				_thick_age[i] += delta
				if _thick_age[i] > .24: _thick_age[i] = -1.0
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
	# The pale arc and frost colours bloom white where the swell crosses the hero's box (the ring passes behind the hero): weaker for them.
	m.set_shader_parameter("swell_gain",.62*intensity*(.5 if element == "arc" else (.75 if element == "frost" else 1.0)))
	m.set_shader_parameter("thick_a",Vector2(_thick_angle[0],_thick_age[0]))
	m.set_shader_parameter("thick_b",Vector2(_thick_angle[1],_thick_age[1]))
	m.set_shader_parameter("thick_c",Vector2(_thick_angle[2],_thick_age[2]))

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

# ---- strokes (drawn by ChapterEffects into its shared ribbon mesh; widths are HALF widths, as in its _ribbon) ----

func handles(stroke_type: String) -> bool:
	return STROKE_TYPES.has(stroke_type)

## One stroke into `flash` (an ImmediateMesh with a triangle surface already open); returns the vertex count.
## `owner_fx` supplies _ribbon (camera-facing quad). It is used for this call only.
func draw(stroke: Dictionary, flash: ImmediateMesh, cam_basis: Basis, owner_fx: RefCounted) -> int:
	if intensity <= 0.0: return 0
	var life := clampf(float(stroke.life)/float(stroke.duration),0.0,1.0)
	var age := 1.0-life
	var color: Color = stroke.color
	var n := 0
	match String(stroke.type):
		"ring_arc":
			# Two arcs over a staggered head, camera-facing, .35 s. Bigger and wider than the first cut, which was a thin hairline.
			var c := Vector3(stroke.at.x,1.65,stroke.at.y)
			color.a = life*.95*intensity
			flash.surface_set_color(color)
			for k in int(stroke.count):
				var start := PI*.12+PI*float(k)
				var previous := c+(cam_basis.x*cos(start)+cam_basis.y*sin(start))*.42
				for j in range(1,7):
					var a := start+PI*.66*float(j)/6.0
					var point := c+(cam_basis.x*cos(a)+cam_basis.y*sin(a))*.42
					n += owner_fx._ribbon(flash,previous,point,.05*(.5+.5*life))
					previous = point
		"ring_shard":
			# Pieces of a cut wind-up, flying out and fading to linen. Three, longer and thicker than the first cut.
			color.a = (1.0-age*.8)*.95*intensity
			flash.surface_set_color(color)
			for k in 3:
				var a := float(int(stroke.seed)%7)*.9+TAU*float(k)/3.0
				var dir := cam_basis.x*cos(a)+cam_basis.y*sin(a)
				var from := Vector3(stroke.at.x,.95,stroke.at.y)+dir*(.15+age*.65)
				n += owner_fx._ribbon(flash,from,from+dir*.34,.045)
		"ring_bolt":
			n += _draw_bolt(stroke,flash,owner_fx,color,life)
		"rs_cc":
			n += _draw_cc(stroke,flash,cam_basis,owner_fx,color,age,life)
		"rs_aim":
			n += _draw_aim(stroke,flash,cam_basis,owner_fx,color,life)
	return n

## Lightning from the hero to a target: two passes (a wide dim one, a narrow bright one) over the same crooked path, so it is
## readable inside the particles. Branch every third joint.
func _draw_bolt(stroke: Dictionary, flash: ImmediateMesh, owner_fx: RefCounted, color: Color, life: float) -> int:
	var from: Vector2 = stroke.from
	var to: Vector2 = stroke.to
	var side := Vector2(-(to-from).y,(to-from).x).normalized()
	var width := float(stroke.width)
	var n := 0
	for pass_index in 2:
		var c := color
		c.a = (.45 if pass_index == 0 else .95)*life*intensity
		flash.surface_set_color(c)
		var w := width*(1.8 if pass_index == 0 else .8)
		for i in 8:
			var t0 := float(i)/8.0
			var t1 := float(i+1)/8.0
			var a := from.lerp(to,t0)+side*sin(float(i)*2.7)*.2*sin(t0*PI)
			var b := from.lerp(to,t1)+side*sin(float(i+1)*2.7)*.2*sin(t1*PI)
			n += owner_fx._ribbon(flash,Vector3(a.x,.9,a.y),Vector3(b.x,.9,b.y),w)
			if pass_index == 1 and i in [2,5]:
				var branch := a+side*.4+(to-from).normalized()*.15
				n += owner_fx._ribbon(flash,Vector3(a.x,.9,a.y),Vector3(branch.x,.85,branch.y),w*.6)
	return n

func _draw_cc(stroke: Dictionary, flash: ImmediateMesh, cb: Basis, owner_fx: RefCounted, color: Color, age: float, life: float) -> int:
	var at := Vector3(stroke.at.x,.95,stroke.at.y)
	var scale := float(stroke.scale)*1.25*(.85+age*.45)
	var seed_angle := float(int(stroke.seed)%11)*.57
	# Keep the hero's own box clear (L1): a mark on an enemy that stands against the hero fades to 30% within 1.5 m of the hero.
	var near_hero := clampf((Vector2(stroke.at).distance_to(_hero)-.5)/1.0,0.0,1.0)
	color.a = (.55+.45*life)*intensity*lerpf(.3,1.0,near_hero)
	flash.surface_set_color(color)
	var n := 0
	match String(stroke.kind):
		"frozen":
			# A small ring with six spikes standing out of it.
			n += _circle(flash,owner_fx,cb,at,.4*scale,14,.05)
			for k in 6:
				var a := seed_angle+TAU*float(k)/6.0
				var dir := cb.x*cos(a)+cb.y*sin(a)
				n += owner_fx._ribbon(flash,at+dir*.4*scale,at+dir*(.4*scale+.3),.06*(.4+.6*life))
		"slowed":
			n += _circle(flash,owner_fx,cb,at,.4*scale,16,.04)
		"stunned":
			# Two crooked lines crossing over the body.
			for k in 2:
				var a := seed_angle+PI*float(k)*.5+.3
				var dir := cb.x*cos(a)+cb.y*sin(a)
				var perp := cb.x*-sin(a)+cb.y*cos(a)
				var previous := at-dir*.5
				for j in range(1,6):
					var t := float(j)/5.0
					var point := at-dir*.5+dir*1.0*t+perp*(.15 if j%2 == 1 else -.15)*(1.0 if j < 5 else 0.0)
					n += owner_fx._ribbon(flash,previous,point,.055)
					previous = point
		"staggered":
			# Two short arcs over the head (the ember ring's own mark, borrowed).
			for k in 2:
				var start := PI*.12+PI*float(k)
				var previous := at+(cb.x*cos(start)+cb.y*sin(start))*.32*scale
				for j in range(1,5):
					var a := start+PI*.62*float(j)/4.0
					var point := at+(cb.x*cos(a)+cb.y*sin(a))*.32*scale
					n += owner_fx._ribbon(flash,previous,point,.055)
					previous = point
		"embers":
			# Three embers around the body (a heat mark going off): short crossed ticks.
			for k in 3:
				var a := seed_angle+TAU*float(k)/3.0
				var dir := cb.x*cos(a)+cb.y*sin(a)
				var p := at+dir*(.3+age*.25)
				var cross := cb.x*-sin(a)+cb.y*cos(a)
				n += owner_fx._ribbon(flash,p-dir*.14,p+dir*.14,.07*(.4+.6*life))
				n += owner_fx._ribbon(flash,p-cross*.14,p+cross*.14,.07*(.4+.6*life))
	return n

func _draw_aim(stroke: Dictionary, flash: ImmediateMesh, cb: Basis, owner_fx: RefCounted, color: Color, life: float) -> int:
	color.a = .85*life*intensity
	flash.surface_set_color(color)
	var at: Vector2 = stroke.at
	if String(stroke.kind) == "ring":
		return _circle(flash,owner_fx,cb,Vector3(at.x,.95,at.y),.4,20,.025)
	# A short tick along the aim, in front of the staff, with a small crossbar at its far end.
	var dir: Vector2 = stroke.dir
	var near := at+dir*.5
	var far := at+dir*.82
	var perp := Vector2(-dir.y,dir.x)*.11
	var n: int = owner_fx._ribbon(flash,Vector3(near.x,.95,near.y),Vector3(far.x,.95,far.y),.03)
	n += owner_fx._ribbon(flash,Vector3(far.x-perp.x,.95,far.y-perp.y),Vector3(far.x+perp.x,.95,far.y+perp.y),.03)
	return n

func _circle(flash: ImmediateMesh, owner_fx: RefCounted, cb: Basis, at: Vector3, r: float, segs: int, half_width: float) -> int:
	var n := 0
	for i in segs:
		var a0 := TAU*float(i)/float(segs)
		var a1 := TAU*float(i+1)/float(segs)
		var p0 := at+(cb.x*cos(a0)+cb.y*sin(a0))*r
		var p1 := at+(cb.x*cos(a1)+cb.y*sin(a1))*r
		n += owner_fx._ribbon(flash,p0,p1,half_width)
	return n
