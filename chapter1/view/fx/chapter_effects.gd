extends RefCounted
## Flattened by tools/dev/flatten_chain.py from chapter1/view/chapter_elements_quality44.gd.
## Methods named x__tag are the earlier layers of x; calls between them were super calls.
const Palette=preload("res://chapter1/view/hud/palette.gd")
const Loc=preload("res://chapter1/view/loc.gd")

# ---- chapter1/view/cloister_effects.gd ----
## Bounded event-driven mesh/shard presentation; never owns damage.
var view: Node3D
var projectiles: MultiMeshInstance3D
var gems: MultiMeshInstance3D
var shards: MultiMeshInstance3D
var impacts: MultiMeshInstance3D
var plumes: MultiMeshInstance3D
var shadows: MultiMeshInstance3D
var telegraph: MultiMeshInstance3D
var telegraph_fill: MultiMeshInstance3D
var beams: MeshInstance3D
## Debris particles as parallel arrays (was one Dictionary per particle). life/size stay 64-bit like the old
## Dictionary floats; p/v/color are the same 32-bit types, so every number matches the old per-particle values.
var _d_p := PackedVector3Array()
var _d_v := PackedVector3Array()
var _d_life := PackedFloat64Array()
var _d_size := PackedFloat64Array()
var _d_color := PackedColorArray()
var item_nodes: Dictionary={}
var strokes: Array[Dictionary]=[]
var _last_event := -1
var _rng := RandomNumberGenerator.new()
var _beam_mesh := ImmediateMesh.new()
var _last_camera_tick := -100
## A6-2: debris cap 960 -> 400 (A6 4.5), paying for the new ground ring and ember marks.
const MAX_PARTICLES := 400
const MAX_STROKES := 96
const MAX_IMPACTS := 48
const MAX_HIT_ACCENTS_PER_CONSUME := 12
## U-57: fire projectile quad scale (ball about .58 m across; evolved about .8 m).
const FIREBALL_SCALE := 1.45
const FIREBALL_SCALE_EVOLVED := 2.0
const COLORS={"chapter1.skill.ember":Color("ff943d"),"chapter1.skill.frost":Color("9ce7ef"),"chapter1.skill.arc":Color("b9caff")}
## Enemy threat colour (art plan 2.1): every enemy telegraph and floor hazard uses it, never the fire orange.
const THREAT_COLOR := Color(1.0,.18,.31)
## Spell-child projectile scale relative to a normal bolt (brief: 50-60%).
const CHILD_SIZE := .58
const HOSTILE_BOLT_COLOR := Color("ff2f4f")
const ORB_COLOR := Color("508c78")
var _cam_basis := Basis.IDENTITY
var _cam_z := Vector3.BACK
var _enemies_frame: Array=[]
var _key_cache: Dictionary={}
## Frost instances written to the replacement batches this frame (the originals keep a zero-scaled twin).
var _routed_p := 0
var _routed_i := 0
var _routed_c := 0
## A6-5: the telegraph quads (one MultiMesh, drawn by `telegraph_fill` and `telegraph`).
const TELE_MAX := 96
var _tele_mm: MultiMesh
## U-62: the floor telegraph (line, capsule, fill) is only drawn for bodies of at least this rank. 0 = every enemy (the old
## look, U-56), 1 = elite and above (elite, champion, boss; their floor hazards always draw). Lower it to go back.
const TELE_FLOOR_MIN_RANK := 1
## Normal ranged / charging enemies draw a small body cue instead (one MultiMesh of billboards, see telegraph_cue.gdshader).
const TELE_CUE_MAX := 64
const TELE_CUE_HEIGHT := {"ranged":2.3,"charger":1.6}
var telegraph_cue: MultiMeshInstance3D
var _cue_mm: MultiMesh
## A6-RS RS1: the ring spell's own presenter (composition) and the run's spell document (read-only, set every sync).
const RingSpellFx := preload("res://chapter1/view/fx/ring_spell_fx.gd")
var _ring_fx := RingSpellFx.new()
var _spells_doc: Dictionary={}
var _flash_blank := false
var _flash_blank_color: Variant=null
var _arc_blank := false
var _loot26_blank := false

func setup__cloister(owner_view: Node3D) -> void:
	view=owner_view
	_rng.seed=97631
	var bolt := QuadMesh.new()
	bolt.size=Vector2(2.3,.82)
	projectiles=_batch(bolt,384)
	var comet := ShaderMaterial.new()
	comet.shader=preload("res://chapter1/view/comet.gdshader")
	projectiles.material_override=comet
	var gem := PrismMesh.new()
	gem.size=Vector3(.10,.16,.10)
	gems=_batch(gem,400)
	var gem_mat := _glow(Color.WHITE,0)
	gems.material_override=gem_mat
	var fragment := PrismMesh.new()
	fragment.size=Vector3(.06,.16,.035)
	shards=_batch(fragment,MAX_PARTICLES)
	var particle_mat := ShaderMaterial.new();particle_mat.shader=preload("res://chapter1/view/element_particle.gdshader")
	shards.material_override=particle_mat
	var impact := PlaneMesh.new();impact.size=Vector2(2,2)
	impacts=_batch(impact,MAX_IMPACTS)
	var impact_material := ShaderMaterial.new();impact_material.shader=preload("res://chapter1/view/impact.gdshader")
	impacts.material_override=impact_material
	var bloom := QuadMesh.new();bloom.size=Vector2(2,2.3)
	plumes=_batch(bloom,MAX_IMPACTS)
	var bloom_mat := ShaderMaterial.new();bloom_mat.shader=preload("res://chapter1/view/flame_bloom.gdshader")
	plumes.material_override=bloom_mat
	var shadow_plane := PlaneMesh.new();shadow_plane.size=Vector2(1.1,.75)
	shadows=_batch(shadow_plane,513)
	var shadow_material := ShaderMaterial.new();shadow_material.shader=preload("res://chapter1/view/foot_shadow.gdshader")
	shadows.material_override=shadow_material
	# A6-5: every telegraph is a quad in one MultiMesh that two nodes draw (fill pass, then edge pass). Both are
	# alpha-blended and drawn after (above) the additive effects, so bursts cannot hide them (D3, A6 L2).
	var tele_quad := PlaneMesh.new();tele_quad.size=Vector2(2,2)
	_tele_mm=MultiMesh.new()
	_tele_mm.transform_format=MultiMesh.TRANSFORM_3D
	_tele_mm.use_colors=true;_tele_mm.use_custom_data=true
	_tele_mm.mesh=tele_quad
	_tele_mm.instance_count=TELE_MAX
	_tele_mm.visible_instance_count=0
	var fill_mat := ShaderMaterial.new();fill_mat.shader=preload("res://chapter1/view/fx/telegraph_fill.gdshader");fill_mat.render_priority=10
	var edge_mat := ShaderMaterial.new();edge_mat.shader=preload("res://chapter1/view/fx/telegraph_edge.gdshader");edge_mat.render_priority=11
	telegraph_fill=MultiMeshInstance3D.new();telegraph_fill.multimesh=_tele_mm;telegraph_fill.material_override=fill_mat
	telegraph=MultiMeshInstance3D.new();telegraph.multimesh=_tele_mm;telegraph.material_override=edge_mat
	for tele_node in [telegraph_fill,telegraph]:
		tele_node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		view.add_child(tele_node)
	var cue_quad := QuadMesh.new();cue_quad.size=Vector2(2,2)
	_cue_mm=MultiMesh.new()
	_cue_mm.transform_format=MultiMesh.TRANSFORM_3D
	_cue_mm.use_colors=true;_cue_mm.use_custom_data=true
	_cue_mm.mesh=cue_quad
	_cue_mm.instance_count=TELE_CUE_MAX
	_cue_mm.visible_instance_count=0
	var cue_mat := ShaderMaterial.new();cue_mat.shader=preload("res://chapter1/view/fx/telegraph_cue.gdshader");cue_mat.render_priority=12
	telegraph_cue=MultiMeshInstance3D.new();telegraph_cue.multimesh=_cue_mm;telegraph_cue.material_override=cue_mat
	telegraph_cue.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.add_child(telegraph_cue)
	beams=MeshInstance3D.new()
	beams.material_override=particle_mat
	view.add_child(beams)

func _glow(color: Color, emission: float=1) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color=color
	mat.emission_enabled=emission>0
	mat.emission=color
	mat.emission_energy_multiplier=emission
	mat.vertex_color_use_as_albedo=true
	return mat

func _batch(shape: Mesh, capacity: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format=MultiMesh.TRANSFORM_3D
	mm.use_colors=true
	mm.use_custom_data=true
	mm.mesh=shape
	mm.instance_count=capacity
	mm.visible_instance_count=0
	var node := MultiMeshInstance3D.new()
	node.multimesh=mm
	node.material_override=_glow(Color.WHITE,1.1)
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.add_child(node)
	return node

## One-call MultiMesh writes (A-2). Each batch keeps a float buffer in the engine's own layout
## (12 transform floats, then 4 colour floats if use_colors, then 4 custom floats if use_custom_data)
## and hands it over with one multimesh_set_buffer call instead of 3 calls per instance.
## Channels an effect never writes keep the engine's initial values (the buffer starts from multimesh.buffer).
const MM_STRIDE := 20
const MM_COLOR := 12
const MM_CUSTOM := 16
var _mm_bufs: Dictionary={}
var _mm_last: Dictionary={}
## Dev switches for the two A-2 experiments (default off; see the user args below).
##   --chapter1-fx-hide-empty : MultiMeshInstance3D batches with nothing to draw are set invisible.
var fx_hide_empty := false

func _read_fx_switches() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--chapter1-fx-hide-empty":fx_hide_empty=true

func _mmbuf(mm: MultiMesh) -> PackedFloat32Array:
	var id := mm.get_instance_id()
	var stride := 12+(4 if mm.use_colors else 0)+(4 if mm.use_custom_data else 0)
	var need := mm.instance_count*stride
	var b: PackedFloat32Array=_mm_bufs.get(id,PackedFloat32Array())
	if b.size()!=need:
		b=mm.buffer
		if b.size()!=need:b.resize(need)
		_mm_bufs[id]=b
	return b

## Upload the filled buffer. An empty batch that was already empty is not uploaded again.
func _mmflush(mm: MultiMesh,b: PackedFloat32Array,visible_count: int) -> void:
	mm.visible_instance_count=visible_count
	var id := mm.get_instance_id()
	if visible_count==0 and int(_mm_last.get(id,-1))==0:return
	_mm_last[id]=visible_count
	RenderingServer.multimesh_set_buffer(mm.get_rid(),b)

## Experiment: hide a batch node while it has nothing to draw. Off unless fx_hide_empty.
func _mm_show(node: MultiMeshInstance3D,count: int) -> void:
	if not fx_hide_empty:return
	var show_ := count>0
	if node.visible!=show_:node.visible=show_

static func _wx(b: PackedFloat32Array,o: int,t: Transform3D) -> void:
	var bs := t.basis;var org := t.origin
	b[o]=bs.x.x;b[o+1]=bs.y.x;b[o+2]=bs.z.x;b[o+3]=org.x
	b[o+4]=bs.x.y;b[o+5]=bs.y.y;b[o+6]=bs.z.y;b[o+7]=org.y
	b[o+8]=bs.x.z;b[o+9]=bs.y.z;b[o+10]=bs.z.z;b[o+11]=org.z

static func _wc(b: PackedFloat32Array,o: int,c: Color) -> void:
	b[o]=c.r;b[o+1]=c.g;b[o+2]=c.b;b[o+3]=c.a

func _shadow_key(e: Dictionary) -> String:
	var ck: int=(int(e.generation)<<32)|int(e.id)
	var s: Variant=_key_cache.get(ck)
	if s==null:
		if _key_cache.size()>4096:_key_cache.clear()
		s="%d:%d" % [e.generation,e.id]
		_key_cache[ck]=s
	return s

func burst__cloister(at: Vector2, color: Color, count: int, force: float=1) -> void:
	for i in mini(count,MAX_PARTICLES-_d_life.size()):
		var direction := Vector3(_rng.randf_range(-1,1),_rng.randf_range(.2,1.3),_rng.randf_range(-1,1)).normalized()
		_debris_add(Vector3(at.x,.6,at.y),direction*_rng.randf_range(1.5,4)*force,_rng.randf_range(.16,.45),color,_rng.randf_range(.65,1.4))

func _debris_add(p: Vector3, v: Vector3, life: float, color: Color, size_: float) -> void:
	_d_p.append(p);_d_v.append(v);_d_life.append(life);_d_color.append(color);_d_size.append(size_)

func move_marker(at: Vector2) -> void:
	if strokes.size()<96:strokes.append({"type":"ring","at":at,"radius":.32,"life":.35,"color":Color("9bbcb0")})

func consume__cloister(events: Array) -> void:
	var impact_budget := 8
	var hit_budget := MAX_HIT_ACCENTS_PER_CONSUME
	for event in events:
		if int(event.seq)<=_last_event: continue
		_last_event=int(event.seq)
		# A6-RS RS1: a ring spell takes its element's colour (never the gold fallback, which means growth and reward).
		var color: Color=Palette.spell_color(String(event.get("skill_id","")),_spells_doc,Color("e0c69d"))
		match String(event.type):
			"hit":
				burst(event.position,color,3 if not event.get("shatter",false) else 14)
				if hit_budget>0 and strokes.size()<MAX_STROKES and not event.has("vs_cc"):
					hit_budget-=1
					# A small .1s accent at the paid hit, never a screen-wide flash.
					strokes.append({"type":"hit","at":event.position,"life":.10,"duration":.10,"element":_element(event.get("skill_id","")),"color":color})
			"explosion","shatter":
				burst(event.position,color,16 if event.type=="explosion" else 30,1.35)
				if impact_budget>0 and strokes.size()<MAX_STROKES:
					impact_budget-=1
					strokes.append({"type":"impact","at":event.position,"radius":float(event.radius_cm)/100.0,"life":.48,"duration":.48,"element":_element(event.skill_id),"color":color})
					if float(strokes.back().element)<.25:strokes.back().life=.30;strokes.back().duration=.30 # U-57: the fireball burst is quick
				if event.get("evolved",false):_kick(.15,int(event.tick))
			"death": burst(event.position,color,7,1.2)
			"hero_hit":
				# graze = a big hit the core softened (rapid-fire guard): a weaker reaction.
				var grazed: bool=bool(event.get("graze",false))
				burst(event.position,Color("b94b26"),5 if grazed else 12,.8)
				_kick(.20 if grazed else .50,int(event.tick))
			"growth","seal_grace": burst(event.position,Color("d4bd7a"),38,1.5)
			"item_pickup": burst(event.position,Color("e2c17e"),12)
			"cast":
				if event.skill_id=="chapter1.skill.arc":
					var from: Vector2=event.position
					for target in event.targets:
						if strokes.size()<MAX_STROKES:strokes.append({"type":"arc","from":from,"to":target,"life":.18,"duration":.18,"color":color,"width":.065 if event.get("evolved",false) else .04})
						for i in 7:
							var at: Vector2=from.lerp(target,float(i)/7.0)
							if _d_life.size()<MAX_PARTICLES:_debris_add(Vector3(at.x,.8,at.y),Vector3.ZERO,.13,color,1.5)
						from=target
				elif event.get("shape","")!="ring": burst(event.position,color,5,.6)

## Shader element number: 0 fire, .5 frost, 1 arc. A ring spell takes its own element (A6-RS RS1), not fire.
func _element(id_: String) -> float:
	match Palette.spell_element(id_,_spells_doc):
		"frost": return .5
		"arc": return 1.0
	return 0.0

const TELE_Y := .12
## Write one telegraph quad. custom = (kind, progress, half segment length, radius or half width); tint = (style, line weight, flash).
func _tele_put(buf: PackedFloat32Array,n: int,at: Vector2,dir: Vector2,half_x: float,half_z: float,custom: Color,tint: Color) -> void:
	var o := n*MM_STRIDE
	_wx(buf,o,Transform3D(Basis(Vector3(dir.x,0,dir.y)*half_x,Vector3.UP,Vector3(-dir.y,0,dir.x)*half_z),Vector3(at.x,TELE_Y,at.y)))
	_wc(buf,o+MM_COLOR,tint);_wc(buf,o+MM_CUSTOM,custom)

## A6-5: enemy telegraphs and the boss floor strikes. Reads the core's telegraph record only (shape, direction, rays,
## length, width/radius, remaining_ticks) and the enemy's own windup length: progress = 1 - remaining / windup.
## The picture uses exactly the radii and lengths the core resolves the hit with.
## Rank of a body for the floor telegraph: 0 normal, 1 elite / champion / boss (read-only core state, same reading as the core's _enemy_role).
static func _tele_rank(e: Dictionary) -> int:
	return 1 if (bool(e.get("elite",false)) or String(e.get("grade",""))=="elite") else 0

func _sync_telegraphs(run: RefCounted) -> void:
	var buf := _mmbuf(_tele_mm)
	var cue := _mmbuf(_cue_mm)
	var n := 0
	var c := 0
	for e in _enemies_frame:
		if e.telegraph.is_empty() or e.hp_raw<=0: continue
		var t: Dictionary=e.telegraph
		var win := float(maxi(1,int(e.get("definition",run.ENEMY_DEFS[e.kind]).get("windup",48))))
		var rem := float(t.get("remaining_ticks",win))
		var p := clampf(1.0-rem/win,0,1)
		if _tele_rank(e)<TELE_FLOOR_MIN_RANK:
			# a normal body: only the small cue at the body (ranged and charging bodies; the cue never covers the floor)
			var cue_h: float=float(TELE_CUE_HEIGHT.get(String(e.kind),0.0))
			if cue_h>0.0 and c<TELE_CUE_MAX:
				var cat: Vector2=e.position
				var o := c*MM_STRIDE
				_wx(cue,o,Transform3D(Basis.IDENTITY,Vector3(cat.x,cue_h,cat.y)))
				_wc(cue,o+MM_COLOR,Color(1.0 if rem<=3.0 else 0.0,0,0,1));_wc(cue,o+MM_CUSTOM,Color(0.24,p,0,0))
				c+=1
			continue
		if n>=TELE_MAX: break
		var heavy: bool=e.elite
		var tint := Color(1.0 if heavy else 0.0,1.6 if heavy else 1.0,1.0 if rem<=3.0 else 0.0,1)
		var at: Vector2=e.position
		var shape: String=t.shape
		if shape=="fan":
			# One thin ray per projectile; the faint band is the real bolt corridor (bolt .16 + hero .28 = width/2).
			var length := float(t.length)
			var half := float(t.width)*.5
			for ray in t.rays:
				if n>=TELE_MAX: break
				_tele_put(buf,n,at+ray*length*.5,ray,length*.5+.25,half+.25,Color(2,p,length*.5,half),tint);n+=1
		elif shape=="line":
			var length := float(t.length)
			var half := float(t.width)*.5
			# The charger's record carries an empty ray list (it is one bar along `direction`), the guardian's cross four.
			var rays: Array=t.get("rays",[])
			if rays.is_empty(): rays=[t.direction]
			# A cross arm has no back cap: the middle is a shared square (the core's two straight capsules).
			var kind := 3.0 if rays.size()>1 else 1.0
			for ray in rays:
				if n>=TELE_MAX: break
				_tele_put(buf,n,at+ray*length*.5,ray,length*.5+half+.25,half+.25,Color(kind,p,length*.5,half),tint);n+=1
		else:
			var radius := float(t.radius)
			var ext := radius*(1.5 if heavy else 1.0)+.25
			_tele_put(buf,n,at,Vector2.RIGHT,ext,ext,Color(0,p,0,radius),tint);n+=1
	var hazards: Variant=run.get("chapter_hazards")
	if hazards!=null:
		for h in hazards:
			if n>=TELE_MAX: break
			var span := float(maxi(1,int(h.expires)-int(h.started)))
			var left := float(int(h.expires)-int(run.tick))
			var radius := float(h.radius)
			_tele_put(buf,n,h.position,Vector2.RIGHT,radius+.25,radius+.25,Color(0,clampf(1.0-left/span,0,1),0,radius),Color(2,1.5,1.0 if left<=3.0 else 0.0,1));n+=1
	_mmflush(_tele_mm,buf,n)
	_mmflush(_cue_mm,cue,c)

func _kick(strength: float, tick: int) -> void:
	if tick-_last_camera_tick<14:return
	_last_camera_tick=tick
	var camera_world: Variant=view.get("world")
	if camera_world!=null and camera_world.has_method("kick_camera"):camera_world.kick_camera(strength)

func sync__cloister(run: RefCounted, delta: float) -> void:
	# Actor interpolation must carry its contact shadow with it. Gameplay and
	# telegraphs still read paid core coordinates; only contact shading follows
	# the visual transform produced immediately before this presenter is synced.
	var actor_view: Variant=view.get("actors")
	var hero_at := Vector3(run.hero.position.x,.006,run.hero.position.y)
	if actor_view!=null:hero_at=actor_view.hero.position;hero_at.y=.006
	var msh: MultiMesh=shadows.multimesh
	var sbuf := _mmbuf(msh)
	_wx(sbuf,0,Transform3D(Basis.IDENTITY,hero_at))
	var shadow_count := 1
	_enemies_frame=run.enemies.values()
	var actor_map: Dictionary={}
	if actor_view!=null:actor_map=actor_view.actors
	for e in _enemies_frame:
		if e.hp_raw<=0 or shadow_count>=513:continue
		var size_ := 1.5 if e.elite else 1.0
		var at := Vector3(e.position.x,.005,e.position.y)
		var key: String=_shadow_key(e)
		if actor_view!=null and actor_map.has(key):at=actor_map[key].position;at.y=.005
		elif actor_view!=null and actor_view.vat_crowd!=null:
			var baked_at: Variant=actor_view.presented_position(key)
			if baked_at!=null:at=baked_at;at.y=.005
		_wx(sbuf,shadow_count*MM_STRIDE,Transform3D(Basis.IDENTITY.scaled(Vector3(size_,1,size_)),at))
		shadow_count+=1
	_mmflush(msh,sbuf,shadow_count)
	var mm: MultiMesh=projectiles.multimesh
	var mfp: MultiMesh=_frost39_projectiles.multimesh
	var pbuf := _mmbuf(mm)
	var fpbuf := _mmbuf(mfp)
	var index := 0
	_routed_p=0
	var right := Vector2(_cam_basis.x.x,_cam_basis.x.z).normalized()
	var forward := Vector2(-_cam_basis.z.x,-_cam_basis.z.z).normalized()
	var proj_cap := mm.instance_count
	var glow_mm: MultiMesh=_fire_glow.multimesh if _fire_glow!=null else null
	var glow_buf := _mmbuf(glow_mm) if glow_mm!=null else PackedFloat32Array()
	var glow_n := 0
	for p in run.projectiles:
		if index>=proj_cap: break
		var color: Color=HOSTILE_BOLT_COLOR if p.hostile else COLORS.get(p.skill_id,Color.WHITE)
		var angle := atan2(p.direction.dot(forward),p.direction.dot(right))
		# Radius is immutable paid projectile data; current rank/gear is never reread.
		var evolved: bool=not p.hostile and float(p.radius)>.20
		# Spell children (core flag child:true) are drawn as small dark shards by the projectile shaders:
		# custom.z<0 marks a child, custom.y .15 is arc (arc has no regular bolts, so only its children use it).
		var child: bool=not p.hostile and bool(p.get("child",false))
		var size_ := .68 if p.hostile else (CHILD_SIZE if child else (1.28 if evolved else 1.0))
		var element_code := .5 if p.skill_id=="chapter1.skill.frost" else (1.0 if p.hostile else (.15 if p.skill_id=="chapter1.skill.arc" else 0.0))
		# U-57: the fireball is a ball, not a pin. Presentation scale only (the core's radius is untouched).
		if element_code==0.0 and not p.hostile and not child:size_=FIREBALL_SCALE_EVOLVED if evolved else FIREBALL_SCALE
		var xf := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*size_),Vector3(p.position.x,.75,p.position.y))
		var custom := Color((angle+PI)/TAU,element_code,-1.0 if child else (1.0 if evolved else .20),float(int(p.uid)%17)/17.0)
		# Frost bolts (element code .5) go to the replacement batch; their original keeps a zero-scaled twin.
		if element_code>.3 and element_code<.8:
			var fo := _routed_p*MM_STRIDE
			_wx(fpbuf,fo,xf);_wc(fpbuf,fo+MM_CUSTOM,custom);_wc(fpbuf,fo+MM_COLOR,color)
			_routed_p+=1
			xf.basis=xf.basis.scaled(Vector3.ZERO)
		var po := index*MM_STRIDE
		_wx(pbuf,po,xf);_wc(pbuf,po+MM_COLOR,color);_wc(pbuf,po+MM_CUSTOM,custom)
		if glow_mm!=null and element_code==0.0 and not p.hostile and not child:
			# U-57: an orange light patch on the floor under the ball (no real light, one quad per fireball).
			var gs := 2.6 if evolved else 1.7
			_wx(glow_buf,glow_n*MM_STRIDE,Transform3D(Basis.IDENTITY.scaled(Vector3(gs,1,gs)),Vector3(p.position.x,.07,p.position.y)))
			glow_n+=1
		index+=1
	_mmflush(mm,pbuf,index)
	if glow_mm!=null:_mmflush(glow_mm,glow_buf,glow_n)
	_mmflush(mfp,fpbuf,_routed_p)
	_mm_show(projectiles,index)
	_mm_show(_frost39_projectiles,_routed_p)
	mm=gems.multimesh
	var gbuf := _mmbuf(mm)
	index=0
	var orb_basis := Basis(Vector3.UP,float(run.tick)*.03)
	for orb in run.orbs:
		if index>=mm.instance_count: break
		var go := index*MM_STRIDE
		_wx(gbuf,go,Transform3D(orb_basis,Vector3(orb.position.x,.18,orb.position.y)))
		_wc(gbuf,go+MM_COLOR,ORB_COLOR)
		index+=1
	_mmflush(mm,gbuf,index)
	_mm_show(gems,index)
	_sync_telegraphs(run)
	var flash := _beam_mesh
	var flash_open := false
	var stroke_live: Array[Dictionary]=[]
	var stroke_vertices := 0
	var impact_count := 0
	var plume_count := 0
	var mi: MultiMesh=impacts.multimesh
	var mfi: MultiMesh=_frost39_impacts.multimesh
	var mpl: MultiMesh=plumes.multimesh
	var ibuf := _mmbuf(mi)
	var fibuf := _mmbuf(mfi)
	var plbuf := _mmbuf(mpl)
	var cam_basis := _cam_basis
	var last_color: Variant=null
	_routed_i=0
	for stroke in strokes:
		if run.mode=="playing":stroke.life-=delta
		if stroke.life<=0:continue
		last_color=stroke.color
		if stroke.type!="impact":
			if not flash_open:
				flash_open=true
				flash.clear_surfaces();flash.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			flash.surface_set_color(stroke.color)
		if stroke.type=="ring":
			stroke_vertices+=_ribbon_circle(flash,Vector3(stroke.at.x,.09,stroke.at.y),stroke.radius,24,.012)
		elif stroke.type=="hit":
			var center := Vector3(stroke.at.x,.80,stroke.at.y)
			var fade := clampf(float(stroke.life)/float(stroke.duration),0,1)
			var cold: bool=float(stroke.element)>.3 and float(stroke.element)<.8
			var extent := .24 if cold else .18
			var accents := 3 if cold else 2
			var accent_color: Color=stroke.color;accent_color.a=fade*.80
			flash.surface_set_color(accent_color)
			for i in accents:
				var angle := PI*float(i)/float(accents)+.45
				var axis := cam_basis.x*cos(angle)+cam_basis.y*sin(angle)
				stroke_vertices+=_ribbon(flash,center-axis*extent,center+axis*extent,.016*fade)
		elif _ring_fx.handles(String(stroke.type)):
			# A6-RS RS1/RS2: ring-spell arcs, shards, bolts and pairing marks are drawn by ring_spell_fx (same shared ribbon mesh).
			stroke_vertices+=_ring_fx.draw(stroke,flash,cam_basis,self)
		elif stroke.type=="impact":
			if impact_count<MAX_IMPACTS:
				var ixf := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*float(stroke.radius)),Vector3(stroke.at.x,.10,stroke.at.y))
				var age := 1.0-float(stroke.life)/float(stroke.duration)
				var is_ring: bool=stroke.get("ring",false)
				var icustom := Color(age,stroke.element,1.0 if is_ring else 0.0,1)
				if float(stroke.element)>.3 and float(stroke.element)<.8:
					var fio := _routed_i*MM_STRIDE
					_wx(fibuf,fio,ixf);_wc(fibuf,fio+MM_CUSTOM,icustom);_wc(fibuf,fio+MM_COLOR,stroke.color)
					_routed_i+=1
					ixf.basis=ixf.basis.scaled(Vector3.ZERO)
				var io := impact_count*MM_STRIDE
				_wx(ibuf,io,ixf);_wc(ibuf,io+MM_COLOR,stroke.color);_wc(ibuf,io+MM_CUSTOM,icustom)
				if float(stroke.element)<.25 and not is_ring and plume_count<MAX_IMPACTS:
					var scale_ := float(stroke.radius)*.70
					# The fire-bloom squash (.85/.52/.85, origin.y*.52) is applied here, in the one write.
					var plume_basis := Basis.IDENTITY.scaled(Vector3.ONE*scale_)
					plume_basis=plume_basis.scaled(Vector3(.85,.52,.85))
					var plume_at := Vector3(stroke.at.x,scale_*.65,stroke.at.y)
					plume_at.y*=.52
					var plo := plume_count*MM_STRIDE
					_wx(plbuf,plo,Transform3D(plume_basis,plume_at))
					_wc(plbuf,plo+MM_CUSTOM,Color(age,0,0,float(impact_count%7)/7.0))
					plume_count+=1
				impact_count+=1
		else:
			var from: Vector2=stroke.from
			var to: Vector2=stroke.to
			var side := Vector2(-(to-from).y,(to-from).x).normalized()
			for i in 9:
				var a: Vector2=from.lerp(to,float(i)/9.0)+side*sin(float(i)*2.7)*.18*sin(float(i)*PI/9.0)
				var b: Vector2=from.lerp(to,float(i+1)/9.0)+side*sin(float(i+1)*2.7)*.18*sin(float(i+1)*PI/9.0)
				stroke_vertices+=_ribbon(flash,Vector3(a.x,.85,a.y),Vector3(b.x,.85,b.y),float(stroke.width))
				if i in [2,5]:
					var branch := a+side*.50+Vector2(.15,-.15)
					stroke_vertices+=_ribbon(flash,Vector3(a.x,.85,a.y),Vector3(branch.x,.8,branch.y),float(stroke.width)*.42)
		stroke_live.append(stroke)
	if flash_open:
		if stroke_vertices==0:
			for i in 3:flash.surface_add_vertex(Vector3(0,-20,0))
		flash.surface_end();beams.mesh=flash;_flash_blank=false
	elif not _flash_blank or _flash_blank_color!=last_color:
		# The placeholder vertices carry the colour of the last live stroke (impact strokes set it too).
		flash.clear_surfaces();flash.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		if last_color!=null:flash.surface_set_color(last_color)
		for i in 3:flash.surface_add_vertex(Vector3(0,-20,0))
		flash.surface_end();beams.mesh=flash;_flash_blank=true;_flash_blank_color=last_color
	strokes=stroke_live
	_mmflush(mi,ibuf,impact_count)
	_mmflush(mfi,fibuf,_routed_i)
	_mmflush(mpl,plbuf,plume_count)
	_mm_show(impacts,impact_count)
	_mm_show(_frost39_impacts,_routed_i)
	_mm_show(plumes,plume_count)
	var wanted: Dictionary={}
	for item in run.items:
		wanted[item.uid]=true
		if not item_nodes.has(item.uid):
			var root := Node3D.new()
			var beam := CylinderMesh.new()
			beam.top_radius=.012;beam.bottom_radius=.05;beam.height=1.3
			var loot_color: Color=Palette.quality_color(item.quality)
			var node := MeshInstance3D.new()
			node.mesh=beam;node.position.y=.65;node.material_override=_glow(loot_color,.4)
			root.add_child(node)
			var label := Label3D.new()
			label.text=item.name;label.font_size=26;label.pixel_size=.0075;label.position.y=1.5
			label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.modulate=loot_color
			root.add_child(label);view.add_child(root);item_nodes[item.uid]=root
		item_nodes[item.uid].position=Vector3(item.position.x,0,item.position.y)
		item_nodes[item.uid].get_child(1).visible=item.position.distance_squared_to(run.hero.position)<64.0
	for uid in item_nodes.keys():
		if not wanted.has(uid): item_nodes[uid].queue_free();item_nodes.erase(uid)
	mm=shards.multimesh
	var shbuf := _mmbuf(mm)
	index=0
	var playing: bool=run.mode=="playing"
	var kept := 0
	for i in _d_life.size():
		var life: float=_d_life[i]
		var pos: Vector3=_d_p[i]
		var vel: Vector3=_d_v[i]
		if playing:
			life-=delta
			pos+=vel*delta
			vel.y-=delta*5
		if life<=0 or index>=MAX_PARTICLES: continue
		var size_: float=_d_size[i]
		var basis := Basis(Vector3.UP,life*15).scaled(Vector3.ONE*size_)
		var sho := index*MM_STRIDE
		_wx(shbuf,sho,Transform3D(basis,pos))
		var faded: Color=_d_color[i];faded.a=clampf(life/.12,0,1)
		_wc(shbuf,sho+MM_COLOR,faded)
		index+=1
		# compact the survivors in place
		_d_life[kept]=life;_d_p[kept]=pos;_d_v[kept]=vel;_d_size[kept]=size_;_d_color[kept]=_d_color[i];kept+=1
	_d_life.resize(kept);_d_p.resize(kept);_d_v.resize(kept);_d_size.resize(kept);_d_color.resize(kept)
	_mmflush(mm,shbuf,index)
	_mm_show(shards,index)

func _ribbon(mesh: ImmediateMesh, a: Vector3, b: Vector3, width: float) -> int:
	var side := (b-a).cross(_cam_z).normalized()*width
	mesh.surface_add_vertex(a-side);mesh.surface_add_vertex(a+side);mesh.surface_add_vertex(b+side)
	mesh.surface_add_vertex(a-side);mesh.surface_add_vertex(b+side);mesh.surface_add_vertex(b-side)
	return 6

func _ribbon_circle(mesh: ImmediateMesh, at: Vector3, radius: float, count: int, width: float) -> int:
	for i in count:
		var a := at+Vector3(cos(float(i)*TAU/count),0,sin(float(i)*TAU/count))*radius
		var b := at+Vector3(cos(float(i+1)*TAU/count),0,sin(float(i+1)*TAU/count))*radius
		_ribbon(mesh,a,b,width)
	return count*6

func reset__cloister() -> void:
	_last_event=-1
	_d_p.clear();_d_v.clear();_d_life.clear();_d_size.clear();_d_color.clear()
	strokes.clear()
	_last_camera_tick=-100
	for node in item_nodes.values(): node.queue_free()
	item_nodes.clear()

# ---- chapter1/view/chapter_effects.gd ----
## Full chapter hazards use the same paid positions/radii as damage checks. They are drawn by the telegraph batch.
var potions: Dictionary={}
func setup__chapter(owner_view: Node3D) -> void:
	setup__cloister(owner_view)
func sync__chapter(run: RefCounted,delta: float) -> void:
	sync__cloister(run,delta)
	_sync_potions(run)
func _sync_potions(run: RefCounted) -> void:
	var wanted := {}
	for pickup in run.potion_pickups:
		wanted[pickup.uid]=true
		if not potions.has(pickup.uid):
			var node := Node3D.new();var vial := MeshInstance3D.new();var mesh := CapsuleMesh.new();mesh.radius=.10;mesh.height=.32
			vial.mesh=mesh;vial.position.y=.28;vial.material_override=_glow(Color("c1494e"),.25);node.add_child(vial)
			var label := Label3D.new();label.text="+";label.font_size=28;label.pixel_size=.007;label.position.y=.62;label.modulate=Color("e8bdbc");label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;node.add_child(label)
			view.add_child(node);potions[pickup.uid]=node
		potions[pickup.uid].position=Vector3(pickup.position.x,0,pickup.position.y)
	for uid in potions.keys():
		if not wanted.has(uid):potions[uid].queue_free();potions.erase(uid)
func reset__chapter() -> void:
	reset__cloister()
	for node in potions.values():node.queue_free()
	potions.clear()

# ---- chapter1/view/chapter_effects_quality10.gd ----
## Short white contact strokes at actual paid hits. Cosmetic and bounded.
const CONTACT_CAP := 96
var contacts: Array[Dictionary]=[]
var contact_batch: MultiMeshInstance3D
var _contact_last_seq := -1

func setup__q10(owner_view: Node3D) -> void:
	setup__chapter(owner_view)
	var quad := QuadMesh.new();quad.size=Vector2(2.2,2.2)
	contact_batch=_batch(quad,CONTACT_CAP)
	var mat := ShaderMaterial.new();mat.shader=preload("res://chapter1/view/contact_quality10.gdshader")
	contact_batch.material_override=mat

func consume__q10(events: Array) -> void:
	var budget := 8
	for event in events:
		if int(event.seq)<=_contact_last_seq:continue
		_contact_last_seq=int(event.seq)
		if event.type!="hit" or budget<=0 or contacts.size()>=CONTACT_CAP:continue
		budget-=1
		var element := _element(event.get("skill_id",""))
		contacts.append({"at":event.position,"age":0.0,"duration":.13,"element":element,"angle":float((int(event.target_id)*37+int(event.tick)*13)%180)/180.0})
	consume__cloister(events)

func sync__q10(run: RefCounted,delta: float) -> void:
	sync__chapter(run,delta)
	var live: Array[Dictionary]=[]
	var index := 0
	var mc: MultiMesh=contact_batch.multimesh
	var mfc: MultiMesh=_frost39_contacts.multimesh
	var cbuf := _mmbuf(mc)
	var fcbuf := _mmbuf(mfc)
	var cb := _cam_basis
	_routed_c=0
	for hit in contacts:
		hit.age+=delta if run.mode=="playing" else 0.0
		if hit.age>=hit.duration:continue
		live.append(hit)
		var at := Vector3(hit.at.x,.95,hit.at.y)
		# Offset toward the camera just enough to sit on the struck silhouette.
		at+=cb.z*.18
		var element := float(hit.element)
		var cbasis := cb
		# Cold/arc contacts are drawn smaller (the former q14 rescale, now applied in the one write).
		if element>=.3:cbasis=cbasis.scaled(Vector3.ONE*(.68 if element<.8 else .55))
		var cxf := Transform3D(cbasis,at)
		var ccustom := Color(hit.age/hit.duration,hit.element,hit.angle,1)
		if element>.3 and element<.8:
			var fco := _routed_c*MM_STRIDE
			_wx(fcbuf,fco,cxf);_wc(fcbuf,fco+MM_CUSTOM,ccustom);_wc(fcbuf,fco+MM_COLOR,Color(0,0,0,0))
			_routed_c+=1
			cxf.basis=cxf.basis.scaled(Vector3.ZERO)
		var co := index*MM_STRIDE
		_wx(cbuf,co,cxf);_wc(cbuf,co+MM_CUSTOM,ccustom)
		index+=1
	contacts=live
	_mmflush(mc,cbuf,index)
	_mmflush(mfc,fcbuf,_routed_c)
	_mm_show(contact_batch,index)
	_mm_show(_frost39_contacts,_routed_c)

func reset__q10() -> void:
	reset__chapter();contacts.clear();_contact_last_seq=-1
	if contact_batch:contact_batch.multimesh.visible_instance_count=0

# ---- chapter1/view/chapter_elements_quality14.gd ----
## Cosmetic only: paid cast paths, actual frozen_until, actual shatter events.
const ARC_CAP := 64
## Hero-to-first-target joint width multiplier, and how long a stripe stays (seconds, read from
## run.tuning.presentation.arc_stripe_ticks in sync so the picture and the measurement agree).
const ARC_FIRST_WIDTH := 1.3
## The first joint starts this far from the hero (staff tip) so it no longer crosses the body.
const ARC_FIRST_OFFSET := .6
var _arc_duration := .20
const ICE_TARGET_CAP := 24
const ICE_STATE_CAP := 48
const ICE_SHARD_CAP := 128
var arc_links: Array[Dictionary]=[]
var ice_targets: Dictionary={}
var ice_fragments: Array[Dictionary]=[]
var arc_surface: MeshInstance3D
var ice_batch: MultiMeshInstance3D
var ice_fragment_batch: MultiMeshInstance3D
var _arc_mesh := ImmediateMesh.new()
var _element_seq := -1

func setup__q14(owner_view: Node3D) -> void:
	setup__q10(owner_view)
	var comet := ShaderMaterial.new();comet.shader=preload("res://chapter1/view/comet_quality14.gdshader");projectiles.material_override=comet
	var impact := ShaderMaterial.new();impact.shader=preload("res://chapter1/view/impact_quality14.gdshader");impacts.material_override=impact
	arc_surface=MeshInstance3D.new();arc_surface.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ribbon := ShaderMaterial.new();ribbon.shader=preload("res://chapter1/view/arc_quality14.gdshader");arc_surface.material_override=ribbon;view.add_child(arc_surface)
	var crystal := _crystal_mesh()
	ice_batch=_batch(crystal,ICE_TARGET_CAP*4);ice_fragment_batch=_batch(crystal,ICE_SHARD_CAP)
	var ice := StandardMaterial3D.new();ice.vertex_color_use_as_albedo=true;ice.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	ice.albedo_color=Color(.84,.98,1,.70);ice.metallic=.12;ice.roughness=.24;ice.emission_enabled=true;ice.emission=Color(.10,.37,.50);ice.emission_energy_multiplier=.70
	ice_batch.material_override=ice;ice_fragment_batch.material_override=ice
	print("CHAPTER1_ELEMENTS14 ",JSON.stringify({"arc_links_cap":ARC_CAP,"ice_targets_cap":ICE_TARGET_CAP,"crystals_per_target":4,"ice_shards_cap":ICE_SHARD_CAP,"damage_owner":false,"scope":"Own code geometry/shaders; quality comparison"}))

func consume__q14(events: Array) -> void:
	var old_contact_count := contacts.size()
	var shard_budget := 8
	for event in events:
		if int(event.seq)<=_element_seq:continue
		_element_seq=int(event.seq)
		if event.type=="cast" and event.skill_id=="chapter1.skill.arc":
			var from: Vector2=event.position
			for target in event.targets:
				if arc_links.size()<ARC_CAP:arc_links.append({"from":from,"to":target,"age":0.0,"duration":.20,"evolved":bool(event.get("evolved",false)),"seed":int(event.seq)*17+arc_links.size()*13})
				from=target
		elif event.type=="shatter" and shard_budget>0:
			shard_budget-=1
			for i in mini(6,ICE_SHARD_CAP-ice_fragments.size()):
				var angle := float((int(event.seq)*19+i*61)%360)*PI/180.0
				var at: Vector2=event.position
				ice_fragments.append({"position":Vector3(at.x,.62,at.y),"velocity":Vector3(cos(angle)*3.0,2.0+float(i%3)*.6,sin(angle)*3.0),"age":0.0,"duration":.42,"angle":angle,"size":.20+float(i%3)*.06})
	consume__q10(events)
	# Frost/arc already carry a white release/impact center. Keep a few smaller
	# contact accents so dense chains do not become a screen-covering star pile.
	var contact_keep: Array[Dictionary]=[];var cold_budget := 3
	for i in contacts.size():
		if i>=old_contact_count and float(contacts[i].element)>=.3:
			if cold_budget<=0:continue
			cold_budget-=1
		contact_keep.append(contacts[i])
	contacts=contact_keep
	# Replace only the old arc ribbons; retain paid impacts, fire, loot/debris.
	var keep: Array[Dictionary]=[]
	for stroke in strokes:
		if stroke.type!="arc":keep.append(stroke)
	strokes=keep

func sync__q14(run: RefCounted,delta: float) -> void:
	sync__q10(run,delta)
	_sync_arcs(run,delta);_sync_ice(run,delta);_sync_fragments(run,delta)

func _sync_arcs(run: RefCounted,delta: float) -> void:
	if arc_links.is_empty():
		# Nothing to draw: leave the off-screen placeholder surface in place (built once).
		if not _arc_blank:
			_arc_mesh.clear_surfaces();_arc_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			for i in 3:_arc_mesh.surface_add_vertex(Vector3(0,-20,0))
			_arc_mesh.surface_end();arc_surface.mesh=_arc_mesh;_arc_blank=true
		return
	_arc_blank=false
	_arc_mesh.clear_surfaces();_arc_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var live: Array[Dictionary]=[];var vertices := 0
	for link in arc_links:
		if run.mode=="playing":link.age+=delta
		if link.age>=link.duration:continue
		live.append(link)
		var progress: float=link.age/link.duration
		var fade := pow(1.0-progress,1.1)
		var from: Vector2=link.from;var to: Vector2=link.to
		var side := Vector2(-(to-from).y,(to-from).x).normalized()
		var amplitude := minf(.28,from.distance_to(to)*.10)
		var width := (.15 if link.evolved else .11)*(ARC_FIRST_WIDTH if link.get("first",false) else 1.0)
		var points: Array[Vector3]=[]
		for i in 10:
			var ratio := float(i)/9.0
			var offset := sin(float(i)*2.73+float(link.seed))*amplitude*sin(ratio*PI)
			var at := from.lerp(to,ratio)+side*offset
			points.append(Vector3(at.x,.90,at.y))
		_arc_mesh.surface_set_color(Color(.40,.65,1,fade))
		for i in 9:vertices+=_arc_quad(points[i],points[i+1],width)
		_arc_mesh.surface_set_color(Color(.28,.45,.82,fade*.45))
		for i in [3,6]:
			var branch := points[i]+Vector3(side.x,.10,side.y)*(.42 if i==3 else -.56)
			vertices+=_arc_quad(points[i],branch,width*.45)
	if vertices==0:
		for i in 3:_arc_mesh.surface_add_vertex(Vector3(0,-20,0))
	_arc_mesh.surface_end();arc_surface.mesh=_arc_mesh;arc_links=live

func _arc_quad(a: Vector3,b: Vector3,width: float) -> int:
	var side := (b-a).cross(_cam_z).normalized()*width
	var c0 := a-side;var c1 := a+side;var c2 := b+side;var c3 := b-side
	_arc_mesh.surface_set_uv(Vector2(0,0));_arc_mesh.surface_add_vertex(c0)
	_arc_mesh.surface_set_uv(Vector2(0,1));_arc_mesh.surface_add_vertex(c1)
	_arc_mesh.surface_set_uv(Vector2(1,1));_arc_mesh.surface_add_vertex(c2)
	_arc_mesh.surface_set_uv(Vector2(0,0));_arc_mesh.surface_add_vertex(c0)
	_arc_mesh.surface_set_uv(Vector2(1,1));_arc_mesh.surface_add_vertex(c2)
	_arc_mesh.surface_set_uv(Vector2(1,0));_arc_mesh.surface_add_vertex(c3)
	return 6

func _sync_ice__q14(run: RefCounted,delta: float) -> void:
	var mm: MultiMesh=ice_batch.multimesh
	var eligible: Array[Dictionary]=[]
	for e in _enemies_frame:
		if e.hp_raw>0 and run.tick<int(e.frozen_until):eligible.append(e)
	if eligible.is_empty() and ice_targets.is_empty():
		mm.visible_instance_count=0;_mm_show(ice_batch,0);return
	if eligible.size()>1:
		eligible.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
			if bool(a.elite)!=bool(b.elite):return bool(a.elite)
			return a.position.distance_squared_to(run.hero.position)<b.position.distance_squared_to(run.hero.position))
	var wanted := {}
	var ordered: Array=[]
	for i in mini(ICE_TARGET_CAP,eligible.size()):
		var e: Dictionary=eligible[i];var key := "%d:%d"%[e.generation,e.id];wanted[key]=true;ordered.append(key)
		if not ice_targets.has(key):ice_targets[key]={"age":0.0,"strength":0.0,"at":e.position,"elite":bool(e.elite)}
		var record: Dictionary=ice_targets[key];record.at=e.position
		if run.mode=="playing":record.age+=delta
		var remaining := float(int(e.frozen_until)-run.tick)/60.0
		record.strength=minf(clampf(record.age/.10,0,1),clampf(remaining/.10,0,1))
	for key in ice_targets.keys():
		if not wanted.has(key):
			if run.mode=="playing":ice_targets[key].strength=maxf(0,ice_targets[key].strength-delta*10)
			if ice_targets[key].strength<=0:ice_targets.erase(key)
	# During rapid target turnover, keep the batch strictly bounded, with live
	# frozen elites first. Fading stale records never displace a live target.
	for key in ice_targets:
		if not wanted.has(key):ordered.append(key)
	if ice_targets.size()>ICE_STATE_CAP:
		for key in ordered.duplicate():
			if ice_targets.size()<=ICE_STATE_CAP:break
			if not wanted.has(key):ice_targets.erase(key);ordered.erase(key)
	var index := 0
	var icebuf := _mmbuf(mm)
	for key in ordered:
		if index>=ICE_TARGET_CAP*4:break
		var record: Dictionary=ice_targets[key];var strength: float=record.strength
		var big: bool=record.elite
		var size_ := 1.65 if big else 1.0
		var key_phase := float(key.hash()%31)*.1
		for i in 4:
			var angle := float(i)*TAU/4.0+key_phase
			var spread := .38*size_
			var at := Vector3(record.at.x+cos(angle)*spread,.02,record.at.y+sin(angle)*spread)
			var basis := Basis.from_euler(Vector3(sin(angle)*.18,angle,-cos(angle)*.18)).scaled(Vector3(.20,.80+float(i%3)*.23,.20)*size_*maxf(.01,strength))
			# Narrow asymmetric blades, not an opaque shell over the whole actor (applied in the one write).
			basis=basis.scaled(Vector3(.80,.88 if index%2==0 else .68,.52))
			var ico := index*MM_STRIDE
			_wx(icebuf,ico,Transform3D(basis,at))
			_wc(icebuf,ico+MM_COLOR,Color(.72,.92,1,strength*.60));index+=1
	_mmflush(mm,icebuf,index)
	_mm_show(ice_batch,index)

func _sync_fragments__q14(run: RefCounted,delta: float) -> void:
	var live: Array[Dictionary]=[];var index := 0
	var mm: MultiMesh=ice_fragment_batch.multimesh
	var fgbuf := _mmbuf(mm)
	for shard in ice_fragments:
		if run.mode=="playing":shard.age+=delta;shard.position+=shard.velocity*delta;shard.velocity.y-=delta*8
		if shard.age>=shard.duration:continue
		live.append(shard)
		var fade := clampf((float(shard.duration)-float(shard.age))/.16,0,1)
		var basis := Basis.from_euler(Vector3(shard.age*7,shard.angle,shard.age*4)).scaled(Vector3(.55,1,.55)*float(shard.size))
		# Broad splinters contrast with the upright frozen state (applied in the one write).
		basis=basis.scaled(Vector3(1.45,.68,.42))
		var fgo := index*MM_STRIDE
		_wx(fgbuf,fgo,Transform3D(basis,shard.position))
		_wc(fgbuf,fgo+MM_COLOR,Color(.58,.88,1,fade));index+=1
	ice_fragments=live
	_mmflush(mm,fgbuf,index)
	_mm_show(ice_fragment_batch,index)

func _crystal_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array();var normals := PackedVector3Array();var colors := PackedColorArray()
	for face in 6:
		var a := Vector3(cos(float(face)*TAU/6.0),.16,sin(float(face)*TAU/6.0))
		var b := Vector3(cos(float(face+1)*TAU/6.0),.16,sin(float(face+1)*TAU/6.0))
		var top := Vector3(.10,1.0,-.08);var base := Vector3(0,0,0)
		for triangle in [[a,b,top],[b,a,base]]:
			var normal: Vector3=(triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).normalized()
			if normal.dot(Vector3((a+b).x,0,(a+b).z))<0:normal=-normal
			for point in triangle:vertices.append(point);normals.append(normal);colors.append(Color(.56+float(face%3)*.16,.80+float(face%2)*.12,1))
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colors
	var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);return mesh

func reset__q14() -> void:
	reset__q10();arc_links.clear();ice_targets.clear();ice_fragments.clear();_element_seq=-1
	if arc_surface:arc_surface.mesh=null
	if ice_batch:ice_batch.multimesh.visible_instance_count=0
	if ice_fragment_batch:ice_fragment_batch.multimesh.visible_instance_count=0

# ---- chapter1/view/chapter_elements_quality16.gd ----
## Larger cold fragments now follow actual paid shatter events, including16's
## evolved direct-kill proc. No additional visual death proc or damage owner.
func setup__q16(owner_view: Node3D) -> void:
	setup__q14(owner_view)
	print("CHAPTER1_ELEMENTS16 ",JSON.stringify({"trigger":"actual shatter only","duration":.48,"damage_owner":false,"scope":"Own code geometry, not final art approval"}))
func consume__q16(events: Array) -> void:
	var before := ice_fragments.size()
	consume__q14(events)
	for i in range(before,ice_fragments.size()):
		ice_fragments[i].size*=1.35;ice_fragments[i].duration=.48
		ice_fragments[i].velocity*=1.12

# ---- chapter1/view/chapter_elements_quality20.gd ----
## After actual victory, expire only the combat presentation, retaining loot.
var _ending20_age := 0.0
var _ending20_active := false
const ENDING20_NODES := ["projectiles","shards","impacts","plumes","telegraph","telegraph_fill","telegraph_cue","beams","arc_surface","ice_batch","ice_fragment_batch","contact_batch"]
func sync__q20(run: RefCounted,delta: float) -> void:
	sync__q14(run,delta)
	if run.mode=="victory":_ending20_active=true
	if not _ending20_active:return
	if run.mode=="victory":_ending20_age+=maxf(0,delta)
	var fade := smoothstep(.08,.55,_ending20_age)
	for name_ in ENDING20_NODES:
		var node: GeometryInstance3D=get(name_)
		node.transparency=fade
		if fade>=1:node.visible=false
	if fade>=1:shadows.multimesh.visible_instance_count=1
func reset__q20() -> void:
	reset__q14();_ending20_age=0;_ending20_active=false
	for name_ in ENDING20_NODES:
		var node: GeometryInstance3D=get(name_)
		if is_instance_valid(node):node.transparency=0;node.visible=true

# ---- chapter1/view/chapter_elements_quality22.gd ----
## Existing single projectile batch; paid positions, size and damage unchanged.
func setup__q22(owner_view: Node3D) -> void:
	setup__q16(owner_view)
	var material := ShaderMaterial.new()
	material.shader=preload("res://chapter1/view/comet_hostile22.gdshader")
	projectiles.material_override=material

# ---- chapter1/view/chapter_elements_quality26.gd ----
## Nearby ground names retain their drop beams and original 8m visibility rule.
## Size and separation are presentation only; collection stays in the core.
const LOOT26_PRIORITY := {"unique":0,"legendary":0,"rare":1,"magic":2,"common":3}
const LOOT26_FONT := 36
const LOOT26_NOMINAL_PIXELS := 15.0
var _loot26_font: Font
var _loot26_mesh := ImmediateMesh.new()
var _loot26_leaders: MeshInstance3D
var layout26_records: Array[Dictionary]=[]
func setup__q26(owner_view: Node3D) -> void:
	setup__q22(owner_view)
	_loot26_font=Loc.font("body")
	_loot26_leaders=MeshInstance3D.new();_loot26_leaders.name="GroundNameLeaders26";_loot26_leaders.mesh=_loot26_mesh
	var material := _glow(Color(.72,.69,.59,.65),0)
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.no_depth_test=true
	_loot26_leaders.material_override=material;_loot26_leaders.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.add_child(_loot26_leaders)
func sync__q26(run: RefCounted,delta: float) -> void:
	sync__q20(run,delta);layout26_records.clear()
	var camera := view.get_viewport().get_camera_3d()
	if camera==null:
		_loot26_mesh.clear_surfaces();_loot26_leaders.visible=false;_loot26_blank=false;return
	var viewport_size: Vector2=view.get_viewport().get_visible_rect().size
	var candidates: Array=[]
	for item in run.items:
		if item.position.distance_squared_to(run.hero.position)>=64.0:continue
		candidates.append(item)
	if candidates.is_empty():
		# No ground names nearby: keep the off-screen placeholder line (built once).
		if not _loot26_blank:
			_loot26_mesh.clear_surfaces();_loot26_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			_loot26_mesh.surface_add_vertex(Vector3(0,-20,0));_loot26_mesh.surface_add_vertex(Vector3(0,-20,0))
			_loot26_mesh.surface_end();_loot26_leaders.visible=false;_loot26_blank=true
		return
	_loot26_blank=false
	_loot26_mesh.clear_surfaces();_loot26_leaders.visible=false
	candidates.sort_custom(func(a,b):
		var ap: int=LOOT26_PRIORITY.get(a.quality,3);var bp: int=LOOT26_PRIORITY.get(b.quality,3)
		return ap<bp if ap!=bp else int(a.uid)<int(b.uid))
	var occupied: Array[Rect2]=[]
	var line_count := 0
	var grid_origin := INF
	_loot26_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for item in candidates:
		if not item_nodes.has(item.uid):continue
		var node: Node3D=item_nodes[item.uid];var label: Label3D=node.get_child(1)
		if not label.has_meta("loot26_ready"):
			label.font=_loot26_font;label.font_size=LOOT26_FONT;label.outline_size=6;label.outline_modulate=Color(.025,.022,.018,1);label.no_depth_test=true
			label.render_priority=110;label.outline_render_priority=109
			label.set_meta("loot26_metrics",_loot26_font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,LOOT26_FONT))
			label.set_meta("loot26_ready",true)
		var anchor: Vector3=node.to_global(Vector3(0,1.5,0))
		if camera.is_position_behind(anchor):label.visible=false;continue
		var screen := camera.unproject_position(anchor)
		var pixels_per_world := screen.distance_to(camera.unproject_position(anchor+camera.global_basis.y))
		if pixels_per_world<.001:continue
		var pixel_size_ := LOOT26_NOMINAL_PIXELS/(float(LOOT26_FONT)*pixels_per_world)
		if absf(label.pixel_size-pixel_size_)>.000001:label.pixel_size=pixel_size_
		var scale_ := LOOT26_NOMINAL_PIXELS/float(LOOT26_FONT)
		var text_size: Vector2=label.get_meta("loot26_metrics")*scale_
		var size_ := Vector2(text_size.x+8,_loot26_font.get_height(LOOT26_FONT)*scale_+6)
		var center := Vector2(clampf(screen.x,size_.x*.5+8,viewport_size.x-size_.x*.5-8),clampf(screen.y,92+size_.y*.5,viewport_size.y-112-size_.y*.5))
		if is_inf(grid_origin):grid_origin=center.y
		var chosen := center;var rect := Rect2(center-size_*.5,size_)
		var placed := false
		for step in 41:
			var row := (step+1)/2
			var offset := 0.0 if step==0 else float(row)*(size_.y+5)*( -1.0 if step%2==1 else 1.0)
			var test_center := center+Vector2(0,offset)
			if step>0:test_center.y=grid_origin+roundf((center.y-grid_origin)/(size_.y+5))*(size_.y+5)+offset
			if test_center.y-size_.y*.5<92 or test_center.y+size_.y*.5>viewport_size.y-112:continue
			var test_rect := Rect2(test_center-size_*.5,size_)
			var clear := true
			for used in occupied:
				if test_rect.intersects(used.grow(2)):clear=false;break
			if clear:chosen=test_center;rect=test_rect;placed=true;break
		occupied.append(rect)
		var depth := (anchor-camera.global_position).dot(-camera.global_basis.z)
		var target := camera.project_position(chosen,depth)
		label.position=node.to_local(target);label.visible=true
		var shifted: bool=chosen.distance_to(screen)>3
		if shifted:
			_loot26_mesh.surface_add_vertex(node.to_global(Vector3(0,1.3,0)))
			_loot26_mesh.surface_add_vertex(target-camera.global_basis.y*(size_.y*.45/pixels_per_world));line_count+=2
		layout26_records.append({"uid":item.uid,"name":item.name,"rect":rect,"anchor":screen,"center":chosen,"placed":placed,"shifted":shifted,"font_nominal_logical":float(label.font_size)*label.pixel_size*pixels_per_world})
	if line_count==0:
		_loot26_mesh.surface_add_vertex(Vector3(0,-20,0));_loot26_mesh.surface_add_vertex(Vector3(0,-20,0))
	_loot26_mesh.surface_end();_loot26_leaders.visible=line_count>0
func reset__q26() -> void:
	reset__q20();layout26_records.clear();_loot26_mesh.clear_surfaces()
	if is_instance_valid(_loot26_leaders):_loot26_leaders.visible=false

# ---- chapter1/view/chapter_elements_quality33.gd ----
## Preserve paid fire impacts; keep billboard heat below the upper-body silhouette.
func setup__q33(owner_view: Node3D) -> void:
	setup__q26(owner_view)
	var material := ShaderMaterial.new()
	material.shader=preload("res://chapter1/view/flame_bloom_quality33.gdshader")
	plumes.material_override=material
func sync__q33(run: RefCounted,delta: float) -> void:
	# The fire-bloom squash (basis .85/.52/.85, origin.y*.52) is applied where the plume is written (sync__cloister).
	sync__q26(run,delta)

# ---- chapter1/view/chapter_elements_quality33b.gd ----
## Rarity hierarchy on existing ground drops. No generation/collection changes.
const LOOT33_COLORS := Palette.QUALITY_COLORS
var _loot33_ring: TorusMesh
func setup__q33b(owner_view: Node3D) -> void:
	setup__q33(owner_view)
	_loot33_ring=TorusMesh.new();_loot33_ring.inner_radius=.22;_loot33_ring.outer_radius=.255;_loot33_ring.rings=24;_loot33_ring.ring_segments=5
func sync__q33b(run: RefCounted,delta: float) -> void:
	sync__q33(run,delta)
	for item in run.items:
		if not item_nodes.has(item.uid):continue
		var root: Node3D=item_nodes[item.uid]
		if root.has_meta("rarity33_ready"):continue
		var color: Color=LOOT33_COLORS.get(item.quality,LOOT33_COLORS.common)
		var beam: MeshInstance3D=root.get_child(0)
		var shape: CylinderMesh=beam.mesh
		var height := .35;var radius := .018;var energy := .12
		match String(item.quality):
			"magic":height=.85;radius=.035;energy=.35
			"rare":height=1.9;radius=.07;energy=.85
			"legendary":height=2.7;radius=.095;energy=1.25
			"unique":height=3.1;radius=.105;energy=1.4
		# Rings and amulets are rare finds: they always stand a little taller than their grade.
		if item.slot in ["ring","charm"]:height+=.5;energy+=.2
		shape.height=height;shape.bottom_radius=radius;shape.top_radius=radius*.22
		beam.position.y=height*.5;beam.material_override=_glow(color,energy);beam.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var label: Label3D=root.get_child(1);label.modulate=color
		if item.quality in ["rare","legendary","unique"] or item.slot in ["ring","charm"]:
			var ring := MeshInstance3D.new();ring.name="RareDropHalo33";ring.mesh=_loot33_ring;ring.position.y=.035;ring.material_override=_glow(color,.35);ring.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(ring)
		root.set_meta("rarity33_ready",true);root.set_meta("rarity33_quality",String(item.quality))

# ---- chapter1/view/chapter_elements_quality36.gd ----
## Bounded shock cues follow actual living stunned enemies, never a second timer.
const STUN36_VISIBLE_CAP := 48
var _stun36_sparks: MultiMeshInstance3D
var stun36_visible := 0
func setup__q36(owner_view: Node3D) -> void:
	setup__q33b(owner_view)
	_stun36_sparks=MultiMeshInstance3D.new();_stun36_sparks.name="ShockOrbit36"
	var geometry := SphereMesh.new();geometry.radius=.045;geometry.height=.09;geometry.radial_segments=8;geometry.rings=4
	var batch := MultiMesh.new();batch.transform_format=MultiMesh.TRANSFORM_3D;batch.mesh=geometry;batch.instance_count=STUN36_VISIBLE_CAP*3;batch.visible_instance_count=0
	_stun36_sparks.multimesh=batch;_stun36_sparks.material_override=_glow(Color("f5d878"),1.5);_stun36_sparks.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.add_child(_stun36_sparks)
func sync__q36(run: RefCounted,delta: float) -> void:
	sync__q33b(run,delta)
	stun36_visible=0
	# Only stunned enemies are sorted (by id, as before); with none stunned nothing is sorted or written.
	var enemies: Dictionary=run.enemies
	var stunned: Array=[]
	for id_ in enemies:
		var candidate: Dictionary=enemies[id_]
		if candidate.hp_raw<=0 or run.tick>=int(candidate.get("stunned_until",0)):continue
		stunned.append(id_)
	if stunned.is_empty():
		_stun36_sparks.multimesh.visible_instance_count=0
		_mm_show(_stun36_sparks,0)
		return
	stunned.sort()
	var msp: MultiMesh=_stun36_sparks.multimesh
	var spbuf := _mmbuf(msp)
	for id_ in stunned:
		var entity: Dictionary=enemies[id_]
		if stun36_visible>=STUN36_VISIBLE_CAP:break
		var height: float=2.1 if entity.elite else 1.5
		for point in 3:
			var angle: float=float(run.tick)*.22+TAU*float(point)/3.0
			var position := Vector3(entity.position.x+cos(angle)*.28,height+sin(angle*2.0)*.08,entity.position.y+sin(angle)*.28)
			_wx(spbuf,(stun36_visible*3+point)*12,Transform3D(Basis.IDENTITY,position))
		stun36_visible+=1
	_mmflush(msp,spbuf,stun36_visible*3)
	_mm_show(_stun36_sparks,stun36_visible*3)
func reset__q36() -> void:
	reset__q26();stun36_visible=0
	if is_instance_valid(_stun36_sparks):_stun36_sparks.multimesh.visible_instance_count=0

func consume__q36(events: Array) -> void:
	var previous_seq: int=_element_seq
	var previous_links: int=arc_links.size()
	consume__q16(events)
	var casts: Array=[]
	for event in events:
		if int(event.seq)>previous_seq and event.type=="cast" and event.get("skill_id","")=="chapter1.skill.arc":
			if not event.has("segments"):return
			casts.append(event)
	if casts.is_empty():return
	# Remove only the newly appended legacy concatenated paths; keep older fading arcs.
	arc_links.resize(previous_links)
	for event in casts:
		for segment in event.segments:
			if arc_links.size()>=ARC_CAP:break
			# The first joint of a branch starts at the hero: drawn thicker so the bolt reads as the hero's own.
			var from_hero: bool=segment.from.distance_squared_to(event.position)<.0001
			var link_from: Vector2=segment.from
			if from_hero:
				var span: Vector2=segment.to-segment.from
				link_from+=span.normalized()*minf(ARC_FIRST_OFFSET,span.length()*.5)
			arc_links.append({"from":link_from,"to":segment.to,"age":0.0,"duration":_arc_duration,"evolved":bool(event.get("evolved",false)),"first":from_hero,"seed":int(event.seq)*17+arc_links.size()*13})

# ---- chapter1/view/chapter_elements_quality39.gd ----
## Frost presentation only. Paid positions, frozen_until and inherited lifetimes
## remain authoritative. Never calls core mutation, damage, time_scale or audio.
var _frost39_projectiles: MultiMeshInstance3D
var _frost39_impacts: MultiMeshInstance3D
var _frost39_contacts: MultiMeshInstance3D
var _frost39_casts: MultiMeshInstance3D
var _frost39_seq := -1
var frost39_projectile_count := 0
var frost39_impact_count := 0
var frost39_contact_count := 0
var frost39_cast_count := 0

func setup__q39(owner_view: Node3D) -> void:
	setup__q36(owner_view)
	# These are replacement draw batches, not additional projectile/impact pools.
	# A routed frost instance is hidden in its original batch every frame.
	_frost39_projectiles=_batch(projectiles.multimesh.mesh,projectiles.multimesh.instance_count)
	_frost39_projectiles.name="FrostCore39"
	var core_material := ShaderMaterial.new()
	core_material.shader=preload("res://chapter1/view/frost_core_quality39.gdshader")
	_frost39_projectiles.material_override=core_material
	_frost39_impacts=_batch(impacts.multimesh.mesh,MAX_IMPACTS)
	_frost39_impacts.name="FrostFracture39"
	var impact_material := ShaderMaterial.new()
	impact_material.shader=preload("res://chapter1/view/frost_fracture_quality39.gdshader")
	_frost39_impacts.material_override=impact_material
	_frost39_contacts=_batch(contact_batch.multimesh.mesh,CONTACT_CAP)
	_frost39_contacts.name="FrostContact39"
	var contact_material := ShaderMaterial.new()
	contact_material.shader=preload("res://chapter1/view/frost_contact_quality39.gdshader")
	_frost39_contacts.material_override=contact_material
	var cast_shape := QuadMesh.new()
	cast_shape.size=Vector2(.60,.60)
	_frost39_casts=_batch(cast_shape,MAX_STROKES)
	_frost39_casts.name="FrostRelease39"
	var cast_material := ShaderMaterial.new()
	cast_material.shader=preload("res://chapter1/view/frost_release_quality39.gdshader")
	_frost39_casts.material_override=cast_material
	# Low-emission, depth-tested facets preserve the enemy silhouette. The four
	# inherited crystals and 128-shard pool retain their original owners/caps.
	var ice_material := StandardMaterial3D.new()
	ice_material.vertex_color_use_as_albedo=true
	ice_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	ice_material.albedo_color=Color(.66,.89,.96,.86)
	ice_material.metallic=.08
	ice_material.roughness=.32
	ice_material.emission_enabled=true
	ice_material.emission=Color(.06,.17,.21)
	ice_material.emission_energy_multiplier=.25
	ice_batch.material_override=ice_material
	ice_fragment_batch.material_override=ice_material
	print("CHAPTER1_FROST39 ",JSON.stringify({"scope":"presentation_only","replaces_frost_draws":true,"projectile_cap":projectiles.multimesh.instance_count,"strokes_cap":MAX_STROKES,"impacts_cap":MAX_IMPACTS,"ice_shards_cap":ICE_SHARD_CAP,"damage_owner":false}))

var _ember_ring_tick := -100
func consume(events: Array) -> void:
	for event in events:
		if int(event.seq)<=_frost39_seq:continue
		_frost39_seq=int(event.seq)
		if event.type=="cast" and event.get("skill_id","")=="chapter1.skill.ember":
			# A6-2 fire layer 1 (prepare): a hollow ground ring at the hero's feet, .15 s, at most one per .4 s.
			# It is an impact stroke with ring=true (same batch, no new draw call); custom.z=1 selects it in the shader.
			if int(event.tick)-_ember_ring_tick>=24 and strokes.size()<MAX_STROKES:
				_ember_ring_tick=int(event.tick)
				strokes.append({"type":"impact","at":event.position,"radius":.9,"life":.15,"duration":.15,"element":0.0,"color":COLORS["chapter1.skill.ember"],"ring":true})
			continue
		if event.type!="cast" or event.get("skill_id","")!="chapter1.skill.frost":continue
		if strokes.size()>=MAX_STROKES:continue
		# Event-relative release cue; not a claimed animated hand/socket attachment.
		var direction: Vector2=event.get("direction",Vector2.RIGHT)
		strokes.append({"type":"frost39_cast","at":event.position+direction*.42,"life":.10,"duration":.10,"color":COLORS["chapter1.skill.frost"]})
	consume__q36(events)
	_ring_fx.consume(events,self)

func burst(at: Vector2,color: Color,count: int,force: float=1) -> void:
	if color.is_equal_approx(COLORS["chapter1.skill.frost"]):
		# Replace the generic five-particle release with the paid cast cue. A
		# shatter already has six physical-looking shards: reduce its dust cloud.
		if count==5:return
		if count==30:count=8
	burst__cloister(at,color,count,force)

func sync(run: RefCounted,delta: float) -> void:
	_spells_doc=run.spells
	# Camera looked up once per frame; the ribbon/arc/contact builders read it from here.
	var cam := view.get_viewport().get_camera_3d()
	if cam!=null:
		_cam_basis=cam.global_basis;_cam_z=_cam_basis.z
	var stripe_ticks: int=int(run.tuning.get("presentation",{}).get("arc_stripe_ticks",12))
	_arc_duration=clampf(float(stripe_ticks)/60.0,.05,2.0)
	# The inherited presenter treats every unknown stroke type as an arc and
	# reads from/to/width. Keep release cues in the same bounded stroke pool,
	# but age them here rather than exposing a new type to that legacy branch.
	var releases: Array[Dictionary]=[]
	var inherited: Array[Dictionary]=[]
	for stroke in strokes:
		if stroke.type=="frost39_cast":
			if run.mode=="playing":stroke.life-=delta
			if stroke.life>0:releases.append(stroke)
		else:inherited.append(stroke)
	strokes=inherited
	sync__q36(run,delta)
	strokes.append_array(releases)
	# The frost replacement batches were filled while the originals were written (same values, no read-back).
	frost39_projectile_count=_routed_p
	frost39_impact_count=_routed_i
	frost39_contact_count=_routed_c
	frost39_cast_count=0
	var mk: MultiMesh=_frost39_casts.multimesh
	var kbuf := _mmbuf(mk)
	var cast_basis := _cam_basis
	for stroke in strokes:
		if stroke.type!="frost39_cast":continue
		if frost39_cast_count>=MAX_STROKES:break
		var at := Vector3(stroke.at.x,1.05,stroke.at.y)
		var ko := frost39_cast_count*MM_STRIDE
		_wx(kbuf,ko,Transform3D(cast_basis,at))
		_wc(kbuf,ko+MM_CUSTOM,Color(1.0-float(stroke.life)/float(stroke.duration),0,0,1))
		frost39_cast_count+=1
	_mmflush(mk,kbuf,frost39_cast_count)
	_mm_show(_frost39_casts,frost39_cast_count)
	var ring_hero := Vector3(run.hero.position.x,0,run.hero.position.y)
	var ring_actors: Variant=view.get("actors")
	if ring_actors!=null:ring_hero=ring_actors.hero.position
	_ring_fx.sync(run,delta,ring_hero)

func _sync_ice(run: RefCounted,delta: float) -> void:
	_sync_ice__q14(run,delta)

func _sync_fragments(run: RefCounted,delta: float) -> void:
	_sync_fragments__q14(run,delta)

func reset() -> void:
	reset__q36()
	_ring_fx.reset()
	_flash_blank=false;_arc_blank=false;_loot26_blank=false
	_key_cache.clear()
	_frost39_seq=-1
	_ember_ring_tick=-100
	frost39_projectile_count=0
	frost39_impact_count=0
	frost39_contact_count=0
	frost39_cast_count=0
	for batch in [_frost39_projectiles,_frost39_impacts,_frost39_contacts,_frost39_casts,_fire_glow]:
		if is_instance_valid(batch):batch.multimesh.visible_instance_count=0

# ---- chapter1/view/chapter_elements_quality43.gd ----
## Unconnected fire presentation candidate. Same paid geometry, pools and ages.
## Shader replacements only: no events, damage, RNG, particles or timing added.
var _fire_glow: MultiMeshInstance3D
func setup__q43(owner_view: Node3D) -> void:
	setup__q39(owner_view)
	var glow_plane := PlaneMesh.new();glow_plane.size=Vector2(1,1)
	_fire_glow=_batch(glow_plane,projectiles.multimesh.instance_count)
	_fire_glow.name="FireballGlow"
	var glow_mat := ShaderMaterial.new()
	glow_mat.shader=preload("res://chapter1/view/fire_glow.gdshader")
	_fire_glow.material_override=glow_mat
	var bolt := ShaderMaterial.new()
	bolt.shader=preload("res://chapter1/view/ember_core_quality43.gdshader")
	projectiles.material_override=bolt
	var plume := ShaderMaterial.new()
	plume.shader=preload("res://chapter1/view/ember_afterglow_quality43.gdshader")
	plumes.material_override=plume
	var contact := ShaderMaterial.new()
	contact.shader=preload("res://chapter1/view/ember_contact_quality43.gdshader")
	contact_batch.material_override=contact

# ---- chapter1/view/chapter_elements_quality44.gd ----
## Unconnected arc candidate: paid segments/widths/ages and stun markers unchanged.
func setup(owner_view: Node3D) -> void:
	setup__q43(owner_view)
	var ribbon := ShaderMaterial.new()
	ribbon.shader=preload("res://chapter1/view/arc_core_quality44.gdshader")
	arc_surface.material_override=ribbon
	var contact := ShaderMaterial.new()
	contact.shader=preload("res://chapter1/view/arc_contact_quality44.gdshader")
	contact_batch.material_override=contact
	_read_fx_switches()
	_ring_fx.setup(view)
