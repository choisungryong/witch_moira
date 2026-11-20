extends RefCounted
## A9 (replaces the A6-RS RS1 boundary ring and its pulse): the ring spell ("fence") is things of its own element ORBITING on the
## spell's real radius. There is no closed line. The eye joins the orbit into the radius; a light dot on the floor under each head
## says where the radius is exactly. Reads core events and read-only run state only; never writes the run. Owned by ChapterEffects.
##   heads   ember = ember comet (hot core, three flickering tongues), frost = rolling ice shard, arc = jittering light orb.
##   tails   an arc of the orbit behind each head (ember 45 deg cooling, frost 20 deg mist, arc 50 deg of crooked current).
##   drips   a third layer: falling sparks / frost dust / short side flashes (at most MAX_DRIPS at once, plain arrays).
##   floor   a soft light disc under each head (depth tested; the heads and tails are not, so they read inside a crowd).
##   cast    heads flash 1.3x for .1 s, tails whip to 2x and come back in .12 s, then the heads go dark (45%) and refill with the
##           cooldown. Every enemy hit gets a beam from the NEAREST head (at most BEAMS_PER_CAST): ember tongue, frost shard, arc bolt.
##   I2      detonate: the head nearest to that enemy swells 1.6x for .24 s and its beam is twice as thick.
##   strong  V-7: that beam is grey and the head is knocked outward .15 m for .15 s ("it does not fly back").
## Counts, radius, speed and size come from `effective_skill(id).effects` (and the cast event), never from a level counter.
## RS2 marks (I1 hit.vs_cc, I0 cast.prefer) and the staggered/stunned marks on enemies are unchanged (strokes below).
## Budget: two ImmediateMesh nodes (air + floor), no light, strokes only from the shared pool.
const Palette = preload("res://chapter1/view/hud/palette.gd")
const ORBIT_SHADER = preload("res://chapter1/view/fx/ring_orbit.gdshader")
const GROUND_Y := .07
const REFRESH_FRAMES := 15
const BOLT_START := 1.1 ## kept for old callers; arc bolts now start at the nearest head
const ARCS_PER_CONSUME := 4
const SHARDS_PER_CONSUME := 3
const CC_PER_CONSUME := 4
const STUN_MARKS_PER_CONSUME := 3
const STROKE_TYPES := ["ring_arc","ring_shard","ring_bolt","ring_flame","ring_icicle","rs_cc","rs_aim"]
## status a detonation consumed -> the mark shape it leaves on the enemy, and the colour of that spell
const STATUS_SHAPE := {"heat":"embers","chill":"frozen","shock":"stunned"}
const STATUS_ELEMENT := {"heat":"ember","chill":"frost","shock":"arc"}
const STYLE := {"ember":0,"frost":1,"arc":2}

## ---- the knobs (A9 section 3; every size is a hypothesis to be tuned on a capture) ----
const HEAD_HEIGHT := .6 ## waist; Q1 (director's start value)
const BASE_COUNT := {"ember":3,"frost":5,"arc":3}
const MAX_HEADS := 7
const BASE_RADIUS_CM := 220.0
const COUNT_STEP_CM := 20.0 ## +1 head per 20 cm of radius over the base
const SPIN_MULT := {"ember":1.0,"frost":1.3,"arc":.8}
const SPIN_SECONDS_MIN := 1.0 ## pulled toward the reference (.8-1.0 s, low confidence); ember basis 1.0-1.6 s
const SPIN_SECONDS_MAX := 1.6
const SPIN_PER_COOLDOWN := 2.5
const TAIL_DEGREES := {"ember":90.0,"frost":35.0,"arc":60.0}
const TAIL_SEGMENTS := 8
const TAIL_WIDTH := {"ember":.2,"frost":.3,"arc":.42} ## full width at the head
const HEAD_HALF := {"ember":.3,"frost":.6,"arc":.56} ## sprite half size in metres (the shader draws the real core inside)
const HEAD_SCALE := 1.5
const FLOOR_HALF := .42
const FLOOR_ALPHA := .28
## The element colours the palette gives are pale (frost 9ce7ef, arc b9caff) and read as white once added up; the orbit leans them
## toward cyan and blue-violet. Gold, brass and crimson stay out.
const ORBIT_TINT := {"frost":Color(.30,.82,.95),"arc":Color(.34,.38,.95)}
const IDLE_GLOW := .7 ## Q3: always orbiting at 70%, 100% while an enemy is within NEAR_FACTOR x radius
const NEAR_FACTOR := 1.5
const DIM_AFTER_CAST := .45
const BACK_GLOW := .7 ## O11: the half behind the hero
const HERO_BOX_HALF := Vector2(55.0,175.0) ## L1 box in 1080p px around the hero's feet (x +-, y up); heads inside are x .3
const FLASH_SECONDS := .1
const WHIP_SECONDS := .12
const SWELL_SECONDS := .24
const BOUNCE_SECONDS := .15
const BOUNCE_METERS := .15
const BEAMS_PER_CAST := 6
const MAX_DRIPS := 24
const DRIP_INTERVAL := {"ember":.07,"frost":.06,"arc":.2} ## ember ~13 and frost ~10 alive at once (reference: 10-14 embers riding the flow)
const DRIP_LIFE := {"ember":.9,"frost":.6,"arc":.06}
const BURST_DRIPS := 8 ## scattered outward at every cast
const FOLLOW_LAG := .15 ## seconds: the orbit's centre trails a moving hero (reference ~.5 s, cut so the seen radius does not drift from the real one)
const BAND_WIDTH := {"ember":.5,"frost":.75,"arc":.36} ## floor swirl band, metres
const BAND_ALPHA := {"ember":.34,"frost":.5,"arc":.8}
const BURST_SWELL_SECONDS := .1 ## band 1.8x wide for this long at a cast, then settles over BURST_SETTLE_SECONDS
const BURST_SETTLE_SECONDS := .25
const HEAD_ALPHA_CAP := .85
const ARC_HOLD_FRAMES := 4

var fx: RefCounted
var enabled := true
## Settings hook (flash strength). 1 = normal; 0 draws none of the beams and marks, but the orbit and floor dots stay at 70% (the radius is information).
var intensity := 1.0
var _view: Node3D
var _air: MeshInstance3D
var _floor: MeshInstance3D
var _air_mesh: ImmediateMesh
var _floor_mesh: ImmediateMesh
var _air_material: ShaderMaterial
var _floor_material: ShaderMaterial
var _seq := -1
var _frame := 0
var ring_id := ""
var element := ""
var radius := 0.0
var cooldown_ticks := 60
var _shown_radius := 0.0
var _count := 3
var _damage_ratio := 1.0
var _angle := 0.0 ## radians, decreasing = counter-clockwise on screen
var _arc_angle := 0.0
var _center := Vector2.ZERO
var _center_ready := false
var _burst_age := -1.0
var _flash_age := -1.0
var _swell_head := -1
var _swell_age := -1.0
var _bounce_head := -1
var _bounce_age := -1.0
var _near := 0.0
var _near_target := 0.0
var _charged := 1.0
var _beams_left := BEAMS_PER_CAST
var _drip_pos := PackedVector3Array()
var _drip_vel := PackedVector3Array()
var _drip_age := PackedFloat32Array()
var _drip_life := PackedFloat32Array()
var _drip_seed := PackedInt32Array()
var _drip_clock := 0.0
var _drip_turn := 0
var _hero := Vector2.ZERO
var _hero_at := Vector3.ZERO
var _run: RefCounted
var _heads := PackedVector2Array() ## world ground positions of the heads this frame (read by the beams)

func setup(owner_view: Node3D) -> void:
	_view = owner_view

## Built on the first frame a run with the spell composition on is seen, so a run without it has no extra node at all.
func _build() -> void:
	var floor_shader := ORBIT_SHADER
	var air_shader := Shader.new()
	air_shader.code = ORBIT_SHADER.code.replace("depth_draw_never","depth_draw_never, depth_test_disabled")
	_floor_material = ShaderMaterial.new()
	_floor_material.shader = floor_shader
	_air_material = ShaderMaterial.new()
	_air_material.shader = air_shader
	_floor_mesh = ImmediateMesh.new()
	_air_mesh = ImmediateMesh.new()
	_floor = _node("RingOrbitFloor",_floor_mesh,_floor_material)
	_air = _node("RingOrbitAir",_air_mesh,_air_material)
	_drip_pos.resize(MAX_DRIPS); _drip_vel.resize(MAX_DRIPS); _drip_age.resize(MAX_DRIPS)
	_drip_life.resize(MAX_DRIPS); _drip_seed.resize(MAX_DRIPS)
	_drip_life.fill(0.0)

func _node(node_name: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 16.0
	node.visible = false
	_view.add_child(node)
	return node

func reset() -> void:
	_seq = -1; _frame = 0
	ring_id = ""; element = ""; radius = 0.0; _shown_radius = 0.0
	_flash_age = -1.0; _swell_age = -1.0; _bounce_age = -1.0; _burst_age = -1.0; _center_ready = false
	_swell_head = -1; _bounce_head = -1
	_near = 0.0; _near_target = 0.0; _drip_clock = 0.0
	if _drip_life.size() > 0: _drip_life.fill(0.0)
	_run = null
	_hide()

func _hide() -> void:
	if is_instance_valid(_air): _air.visible = false
	if is_instance_valid(_floor): _floor.visible = false

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
	_beams_left = BEAMS_PER_CAST
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
				# I2: the head nearest to the enemy swells, its beam doubles, the enemy shows the shape of the mark that went off.
				var status := String(event.get("status",""))
				var nearest := _nearest_head(event.position)
				if nearest >= 0:
					_swell_head = nearest
					_swell_age = 0.0
				for stroke in fx.strokes:
					if stroke.has("to") and String(stroke.type).begins_with("ring_") and Vector2(stroke.to).distance_to(event.position) < .05:
						stroke["wmul"] = 2.0
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
	_hero = event.position
	_flash_age = 0.0
	_burst_age = 0.0
	_burst_drips()
	_beams_left = BEAMS_PER_CAST
	if element == "arc":
		for target in event.get("targets",[]):
			_beam(target,false)

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
	var elite := false
	if _run != null:
		var enemy: Variant = _run.enemies.get(int(event.get("target_id",-1)),null)
		elite = enemy != null and bool(enemy.get("elite",false))
	if element == "arc":
		# The bolt was made by the cast; a strong enemy dulls it.
		if elite:
			for stroke in fx.strokes:
				if String(stroke.type) == "ring_bolt" and Vector2(stroke.to).distance_to(event.position) < .05: stroke["color"] = Palette.INK_DIM
	else:
		_beam(event.position,elite)
	if elite:
		var head := _nearest_head(event.position)
		if head >= 0:
			_bounce_head = head
			_bounce_age = 0.0

func _nearest_head(point: Vector2) -> int:
	var best := -1
	var best_d := 1e9
	for i in _heads.size():
		var d := _heads[i].distance_squared_to(point)
		if d < best_d:
			best_d = d
			best = i
	return best

## One beam from the nearest head to a target; at most BEAMS_PER_CAST per cast (the rest only get the marks on the enemies).
func _beam(target: Vector2, elite: bool) -> void:
	if _beams_left <= 0 or _heads.is_empty(): return
	var head := _nearest_head(target)
	if head < 0: return
	var from := _heads[head]
	if from.distance_to(target) < .05: return
	_beams_left -= 1
	var color: Color = Palette.INK_DIM if elite else Palette.element_color(element,Palette.LINEN)
	match element:
		"arc": _push_stroke({"type":"ring_bolt","from":from,"to":target,"life":.14,"duration":.14,"color":color,"width":.05})
		"frost": _push_stroke({"type":"ring_icicle","from":from,"to":target,"life":.1,"duration":.1,"color":color})
		_: _push_stroke({"type":"ring_flame","from":from,"to":target,"life":.12,"duration":.12,"color":color})

func sync(run: RefCounted, delta: float, hero_at: Vector3) -> void:
	_run = run
	if run.spells.is_empty():
		_hide()
		return
	if _air_mesh == null: _build()
	if run.mode == "menu" or run.mode == "victory" or run.mode == "defeat":
		_hide()
		return
	_frame += 1
	if _frame%REFRESH_FRAMES == 1 or ring_id == "": _refresh(run)
	if ring_id == "" or radius <= 0.0:
		_hide()
		return
	_hero = Vector2(hero_at.x,hero_at.z)
	_hero_at = hero_at
	var cam := _view.get_viewport().get_camera_3d()
	if cam == null: return
	if run.mode == "playing": _advance(delta)
	# Ready: refills smoothly with the cooldown (never on/off).
	var next_cast := int(run._next_cast.get(ring_id,0))
	_charged = 1.0
	if next_cast > run.tick: _charged = clampf(1.0-float(next_cast-run.tick)/float(cooldown_ticks),0.0,1.0)
	_draw_orbit(cam,delta if run.mode == "playing" else 0.0)

func _advance(delta: float) -> void:
	_shown_radius = radius if _shown_radius <= 0.0 else lerpf(_shown_radius,radius,1.0-exp(-delta/.1))
	if not _center_ready:
		_center = _hero; _center_ready = true
	_center = _center.lerp(_hero,1.0-exp(-delta/FOLLOW_LAG))
	var seconds := clampf(float(cooldown_ticks)/60.0*SPIN_PER_COOLDOWN,SPIN_SECONDS_MIN,SPIN_SECONDS_MAX)*float(SPIN_MULT.get(element,1.0))
	_angle -= TAU/seconds*delta
	if _frame%ARC_HOLD_FRAMES == 0: _arc_angle = _angle ## arc: three frames held, one frame jump, no in-between
	_near = move_toward(_near,_near_target,delta/.25)
	if _burst_age >= 0.0:
		_burst_age += delta
		if _burst_age > BURST_SWELL_SECONDS+BURST_SETTLE_SECONDS: _burst_age = -1.0
	if _flash_age >= 0.0:
		_flash_age += delta
		if _flash_age > WHIP_SECONDS: _flash_age = -1.0
	if _swell_age >= 0.0:
		_swell_age += delta
		if _swell_age > SWELL_SECONDS: _swell_age = -1.0
	if _bounce_age >= 0.0:
		_bounce_age += delta
		if _bounce_age > BOUNCE_SECONDS: _bounce_age = -1.0
	_step_drips(delta)

## The ring the hero owns and its current radius, count and cooldown (a reach or power card changes them between casts).
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
	var extra := maxi(0,int(floorf((float(effects.get("ring_radius_cm",0))-BASE_RADIUS_CM+COUNT_STEP_CM*.5)/COUNT_STEP_CM)))
	_count = mini(MAX_HEADS,int(BASE_COUNT.get(element,3))+extra)
	var base_damage := 0.0
	var spells: Variant = run.spells.get("spells",null)
	if spells is Dictionary and spells.has(found): base_damage = float(spells[found].get("base",{}).get("damage_raw",0))
	_damage_ratio = float(effects.get("damage_raw",0))/base_damage if base_damage > 0.0 else 1.0
	# Q3: is anything within 1.5 radii (read only)?
	var limit := radius*NEAR_FACTOR
	_near_target = 0.0
	for enemy in run.enemies.values():
		if _hero.distance_squared_to(enemy.position) < limit*limit:
			_near_target = 1.0
			break

# ---- drips: x = angle on the orbit, y = height, z = radial offset from the radius (they ride the flow, so none is a free particle) ----

func _spin_rate() -> float:
	var seconds := clampf(float(cooldown_ticks)/60.0*SPIN_PER_COOLDOWN,SPIN_SECONDS_MIN,SPIN_SECONDS_MAX)*float(SPIN_MULT.get(element,1.0))
	return TAU/seconds

func _step_drips(delta: float) -> void:
	var rate := _spin_rate()
	for i in MAX_DRIPS:
		if _drip_life[i] <= 0.0: continue
		_drip_age[i] += delta
		if _drip_age[i] >= _drip_life[i]:
			_drip_life[i] = 0.0
			continue
		var v := _drip_vel[i] ## x = share of the orbit speed, y = fall speed, z = outward speed
		_drip_pos[i].x -= rate*v.x*delta
		_drip_pos[i].y = maxf(.04,_drip_pos[i].y-v.y*delta)
		_drip_pos[i].z += v.z*delta
	_drip_clock += delta
	var interval := float(DRIP_INTERVAL.get(element,.15))
	if _drip_clock < interval or _heads.is_empty(): return
	_drip_clock = 0.0
	_spawn_drip(false)

func _spawn_drip(burst: bool) -> void:
	for i in MAX_DRIPS:
		if _drip_life[i] > 0.0: continue
		_drip_turn += 1
		var angle := _angle+TAU*_hash(_drip_turn*31+7)
		if element == "arc" and not burst:
			var head := _heads[_drip_turn%_heads.size()]-_center
			angle = atan2(head.y,head.x)
		var off := (_hash(_drip_turn*17+3)-.5)*.9 if element != "arc" else 0.0
		var height := HEAD_HEIGHT*(.2+.8*_hash(_drip_turn*13+1)) if element != "arc" else HEAD_HEIGHT
		_drip_pos[i] = Vector3(angle,height,off)
		_drip_age[i] = 0.0
		_drip_life[i] = float(DRIP_LIFE.get(element,.3))*(.7 if burst else 1.0)
		_drip_seed[i] = _drip_turn*7919
		var outward := 1.6*(_hash(_drip_turn*3+9)-.3) if burst else 0.0
		_drip_vel[i] = Vector3(.6+.5*_hash(_drip_turn*5+2),.25 if element == "ember" else .05,outward)
		if element == "arc": _drip_vel[i] = Vector3.ZERO
		return

## At a cast the band swells and pieces scatter outward from it (reference: the ring bursts into embers).
func _burst_drips() -> void:
	if _drip_life.size() == 0 or _heads.is_empty() or element == "arc": return
	for k in BURST_DRIPS: _spawn_drip(true)

# ---- drawing the orbit ----

func _vert(mesh: ImmediateMesh, p: Vector3, c: Color, uv: Vector2, kind: float, extra: float) -> void:
	mesh.surface_set_color(c)
	mesh.surface_set_uv(uv)
	mesh.surface_set_uv2(Vector2(kind,extra))
	mesh.surface_add_vertex(p)

func _quad(mesh: ImmediateMesh, centre: Vector3, ax: Vector3, ay: Vector3, c: Color, kind: float, extra: float) -> void:
	var p0 := centre-ax-ay
	var p1 := centre+ax-ay
	var p2 := centre+ax+ay
	var p3 := centre-ax+ay
	_vert(mesh,p0,c,Vector2(-1,-1),kind,extra); _vert(mesh,p1,c,Vector2(1,-1),kind,extra); _vert(mesh,p2,c,Vector2(1,1),kind,extra)
	_vert(mesh,p0,c,Vector2(-1,-1),kind,extra); _vert(mesh,p2,c,Vector2(1,1),kind,extra); _vert(mesh,p3,c,Vector2(-1,1),kind,extra)

func _strip(mesh: ImmediateMesh, a: Vector3, b: Vector3, wa: float, wb: float, ca: Color, cb_: Color, ua: float, ub: float, cam_z: Vector3) -> void:
	var side := (b-a).cross(cam_z).normalized()
	var a0 := a-side*wa
	var a1 := a+side*wa
	var b0 := b-side*wb
	var b1 := b+side*wb
	_vert(mesh,a0,ca,Vector2(ua,-1),0.0,0.0); _vert(mesh,a1,ca,Vector2(ua,1),0.0,0.0); _vert(mesh,b1,cb_,Vector2(ub,1),0.0,0.0)
	_vert(mesh,a0,ca,Vector2(ua,-1),0.0,0.0); _vert(mesh,b1,cb_,Vector2(ub,1),0.0,0.0); _vert(mesh,b0,cb_,Vector2(ub,-1),0.0,0.0)

func _hash(n: int) -> float:
	return fposmod(sin(float(n)*12.9898)*43758.5453,1.0)

func _draw_orbit(cam: Camera3D, delta: float) -> void:
	var tint: Color = ORBIT_TINT.get(element,Palette.element_color(element,Palette.LINEN))
	var style := int(STYLE.get(element,0))
	_air_material.set_shader_parameter("style",style)
	_floor_material.set_shader_parameter("style",style)
	var cam_basis := cam.global_basis
	var cam_z := cam_basis.z
	var forward := Vector3(-cam_z.x,0,-cam_z.z).normalized()
	var screen := _view.get_viewport().get_visible_rect().size
	var px := screen.y/1080.0
	var hero_px := cam.unproject_position(_hero_at)
	var setting := lerpf(IDLE_GLOW,1.0,clampf(intensity,0.0,1.0)) ## the setting dims the orbit to 70% at most; never off
	var idle := lerpf(IDLE_GLOW,1.0,_near)
	var charge_glow := lerpf(DIM_AFTER_CAST,1.0,_charged)
	var charge_size := lerpf(.8,1.0,_charged)
	var flash := 1.0
	var whip := 1.0
	if _flash_age >= 0.0:
		if _flash_age < FLASH_SECONDS: flash = 1.3
		whip = lerpf(2.0,1.0,clampf(_flash_age/WHIP_SECONDS,0.0,1.0))
		charge_glow = 1.0
	var damage_size := clampf(sqrt(_damage_ratio),1.0,1.35)
	var damage_tail := clampf(_damage_ratio,1.0,1.4)
	var damage_glow := minf(.05*_damage_ratio/.25*.25,.05) ## +.05 at most, brightness stays under the cap
	var tail_span := deg_to_rad(float(TAIL_DEGREES.get(element,45.0)))*whip*damage_tail
	var base_angle := _arc_angle if element == "arc" else _angle
	var count := _count
	_heads.resize(count)
	_air_mesh.clear_surfaces()
	_floor_mesh.clear_surfaces()
	_air_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_floor_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_draw_band(tint,idle*charge_glow*setting,base_angle,count)
	for i in count:
		var a := base_angle+TAU*float(i)/float(count)
		var r := _shown_radius
		if i == _bounce_head and _bounce_age >= 0.0: r += BOUNCE_METERS*sin(PI*_bounce_age/BOUNCE_SECONDS)
		var dir := Vector2(cos(a),sin(a))
		var ground := _center+dir*r
		_heads[i] = ground
		var pos := Vector3(ground.x,HEAD_HEIGHT,ground.y)
		# O11: the half behind the hero (away from the camera) at 70%; L1: inside the hero's box at 30%.
		var away := Vector3(dir.x,0,dir.y).dot(forward)
		var glow := idle*charge_glow*setting*lerpf(1.0,BACK_GLOW,smoothstep(-.2,.3,away))
		var sp := cam.unproject_position(pos)
		var rel := sp-hero_px
		var in_box := clampf(maxf(absf(rel.x)/(HERO_BOX_HALF.x*px),absf(rel.y+HERO_BOX_HALF.y*.5*px)/(HERO_BOX_HALF.y*.5*px*1.0)),0.0,1.0)
		glow *= lerpf(.3,1.0,smoothstep(.85,1.1,in_box))
		glow = minf(glow+damage_glow,HEAD_ALPHA_CAP)
		var size := float(HEAD_HALF.get(element,.3))*HEAD_SCALE*charge_size*flash*damage_size
		if i == _swell_head and _swell_age >= 0.0: size *= lerpf(1.6,1.0,smoothstep(0.0,1.0,_swell_age/SWELL_SECONDS))
		var jitter := 0.0
		if element == "arc": size *= 1.0+(_hash(_frame*7+i*131)-.5)*.5
		# tail: points along the orbit behind the head (travel is decreasing angle, so behind = larger angle)
		var tail_color := tint
		var cold := Color(.95,.36,.12)
		var width := float(TAIL_WIDTH.get(element,.1))*damage_size
		var tail_alpha := (.6 if element == "frost" else .9)*glow
		var points: Array[Vector3] = []
		for k in TAIL_SEGMENTS+1:
			var t := float(k)/float(TAIL_SEGMENTS)
			var ak := a+tail_span*t
			var rk := r
			var p := Vector3(_center.x+cos(ak)*rk,HEAD_HEIGHT,_center.y+sin(ak)*rk)
			if element == "arc" and k > 0:
				var seed := int(float(_frame)/4.0)*53+i*17+k*5
				var kink := (_hash(seed)-.5)*.32
				p += Vector3(cos(ak),0,sin(ak))*kink
				p.y += (_hash(seed+3)-.5)*.16
			points.append(p)
		for k in TAIL_SEGMENTS:
			var t0 := float(k)/float(TAIL_SEGMENTS)
			var t1 := float(k+1)/float(TAIL_SEGMENTS)
			var c0 := tail_color.lerp(cold,t0) if element == "ember" else tail_color
			var c1 := tail_color.lerp(cold,t1) if element == "ember" else tail_color
			c0.a = tail_alpha*pow(1.0-t0,1.3)
			c1.a = tail_alpha*pow(1.0-t1,1.3)
			var w0 := width*(1.0-t0*.9)
			var w1 := width*(1.0-t1*.9)
			_strip(_air_mesh,points[k],points[k+1],w0*.5,w1*.5,c0,c1,t0,t1,cam_z)
		# head
		var hc := tint
		hc.a = glow
		var tangent := Vector3(-sin(a),0,cos(a))*-1.0 ## direction of travel (decreasing angle)
		match style:
			1:
				var tx := cam_basis.x.dot(tangent)
				var ty := cam_basis.y.dot(tangent)
				var tl := maxf(.001,sqrt(tx*tx+ty*ty))
				var ax := (cam_basis.x*tx+cam_basis.y*ty)/tl*size
				var ay := (cam_basis.x*-ty+cam_basis.y*tx)/tl*size
				var roll := _angle*5.0+float(i)*1.3
				_quad(_air_mesh,pos,ax,ay,hc,1.0,roll)
			_:
				_quad(_air_mesh,pos,cam_basis.x*size,cam_basis.y*size,hc,1.0,float(i)*.9+jitter)
		# floor light under the head
		var fc := tint
		fc.a = FLOOR_ALPHA*glow
		var fh := FLOOR_HALF*(.8 if element == "frost" else 1.0)
		_quad(_floor_mesh,Vector3(ground.x,GROUND_Y,ground.y),Vector3(fh,0,0),Vector3(0,0,fh),fc,2.0,0.0)
	_draw_drips(cam_basis,cam_z,tint,setting,style)
	_air_mesh.surface_end()
	_floor_mesh.surface_end()
	_air.visible = true
	_floor.visible = true

func _draw_band(tint: Color, glow: float, base_angle: float, count: int) -> void:
	## One floor quad under everything: a wide swirl band that flows with the orbit, brightest behind each head, nearly out opposite it.
	## It is never an even line: width and brightness change around the circle (shader kind 3).
	var swell := 1.0
	var gain := 1.0
	if _burst_age >= 0.0:
		var settle := clampf((_burst_age-BURST_SWELL_SECONDS)/BURST_SETTLE_SECONDS,0.0,1.0)
		swell = lerpf(1.8,1.0,settle)
		gain = lerpf(1.3,1.0,settle)
	var width := float(BAND_WIDTH.get(element,.5))*swell
	var half := _shown_radius+width+.6
	var c := tint
	c.a = float(BAND_ALPHA.get(element,.3))*glow*gain
	_floor_material.set_shader_parameter("band_radius",_shown_radius)
	_floor_material.set_shader_parameter("band_width",width)
	_floor_material.set_shader_parameter("band_head",base_angle)
	_floor_material.set_shader_parameter("band_heads",float(count))
	var y := GROUND_Y-.005
	var o := Vector3(_center.x,y,_center.y)
	var p0 := o+Vector3(-half,0,-half)
	var p1 := o+Vector3(half,0,-half)
	var p2 := o+Vector3(half,0,half)
	var p3 := o+Vector3(-half,0,half)
	_vert(_floor_mesh,p0,c,Vector2(-half,-half),3.0,0.0); _vert(_floor_mesh,p1,c,Vector2(half,-half),3.0,0.0); _vert(_floor_mesh,p2,c,Vector2(half,half),3.0,0.0)
	_vert(_floor_mesh,p0,c,Vector2(-half,-half),3.0,0.0); _vert(_floor_mesh,p2,c,Vector2(half,half),3.0,0.0); _vert(_floor_mesh,p3,c,Vector2(-half,half),3.0,0.0)

func _draw_drips(cam_basis: Basis, cam_z: Vector3, tint: Color, setting: float, style: int) -> void:
	for i in MAX_DRIPS:
		if _drip_life[i] <= 0.0: continue
		var life := 1.0-_drip_age[i]/_drip_life[i]
		var c := tint
		c.a = life*.8*setting
		var d := _drip_pos[i]
		var rr := maxf(.1,_shown_radius+d.z)
		var p := Vector3(_center.x+cos(d.x)*rr,d.y,_center.y+sin(d.x)*rr)
		match style:
			0:
				c = c.lerp(Color(.95,.36,.12),1.0-life)
				c.a = life*.8*setting
				_quad(_air_mesh,p,cam_basis.x*.07,cam_basis.y*.07,c,2.0,0.0)
			1:
				var sparkle := .09*(.6+.4*sin(_drip_age[i]*40.0))
				_quad(_air_mesh,p,cam_basis.x*sparkle,cam_basis.y*sparkle,c,1.0,float(_drip_seed[i]))
			_:
				# a short side flash off the head: two crooked joints, .06 s
				var sd := float(_drip_seed[i])
				var out := Vector3(cos(sd),0,sin(sd))
				var mid := p+out*.12+Vector3(0,.07,0)
				var end := p+out*.26-Vector3(0,.03,0)
				_strip(_air_mesh,p,mid,.02,.016,c,c,0.0,.5,cam_z)
				_strip(_air_mesh,mid,end,.016,.005,c,c,.5,1.0,cam_z)

# ---- strokes (drawn by ChapterEffects into its shared ribbon mesh; widths are HALF widths, as in its _ribbon) ----

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
		"ring_flame":
			# A tongue of fire from the nearest head to the enemy: curved, thick at the head, thin and cooler at the tip.
			var from: Vector2 = stroke.from
			var to: Vector2 = stroke.to
			var side := Vector2(-(to-from).y,(to-from).x).normalized()
			var wmul := float(stroke.get("wmul",1.0))
			var previous := Vector3(from.x,.75,from.y)
			for j in range(1,6):
				var t := float(j)/5.0
				var q := from.lerp(to,minf(1.0,age*6.0+.35)*t)+side*sin(t*PI)*.18
				var point := Vector3(q.x,.75+.2*t,q.y)
				var c := color.lerp(Color(.95,.36,.12),t)
				c.a = life*.9*intensity
				flash.surface_set_color(c)
				n += owner_fx._ribbon(flash,previous,point,.09*wmul*(1.0-t*.8))
				previous = point
		"ring_icicle":
			# One shard thrown from the nearest head, a short streak that lands on the enemy.
			var from: Vector2 = stroke.from
			var to: Vector2 = stroke.to
			var wmul := float(stroke.get("wmul",1.0))
			var head := from.lerp(to,clampf(age*1.25,0.0,1.0))
			var tailp := from.lerp(to,clampf(age*1.25-.35,0.0,1.0))
			color.a = (1.0-age*.5)*.95*intensity
			flash.surface_set_color(color)
			n += owner_fx._ribbon(flash,Vector3(tailp.x,.8,tailp.y),Vector3(head.x,.85,head.y),.07*wmul)
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
	var width := float(stroke.width)*float(stroke.get("wmul",1.0))
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
