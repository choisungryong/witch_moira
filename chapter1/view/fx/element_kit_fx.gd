extends RefCounted
## A-element-kit-screen A1 (vfx-feel): what the shock element kit (D-element-trees 3.3, tuning element_kit) adds to the battle picture.
## Reads core events and read-only core state (`run.kit_view()`, `run.enemies[*].kst / rod_until / elite / position`, `run.boss_finale_view()`);
## writes nothing into the core. With the kit off `kit_view().on` is false, no node is made and nothing is drawn.
##   shocked body   an ordinary body carrying the shock: short zig-zag arcs on the floor under it (it is a conductor).
##   big body       the stacks as a ring of pieces over its head (cap = pieces); a new piece lights; at the cap the whole ring brightens and a thin
##                  second ring stays ("about to go off"). The ring is state, drawn every frame; events only time the flashes.
##   rod            a standing nail over the body (its length is the time left), twelve ticks on the floor at the rod's reach.
##   conductor bolt bolt_returned{self:false}: a kinked line from the conductor into the big body, a bead where it lands. A cast's bolts arrive
##                  one after the other, 12 ms apart. Direction is what tells it from the chain (the chain leaves the hero).
##   vein           bolt_returned{self:true}: a short bolt from a piece of the big body's own ring down into the body, bead at the ring end;
##                  the ring empties piece by piece as they strike.
##   burst          detonated{big}: bent rays out of the chest when the last bolt of the cast lands, count by stacks. A small body gets a small one.
##   rebound        chain_rebound: a hook round the body.   storm  kit_storm: a bolt from the sky to each target (a rod's tip if it has one).
##   shell          kit_shell: a thin zig-zag circle round the hero.
## Two MultiMeshes (floor: render priority 8 under the finale's marks; head: 9, under the telegraphs 10 to 12), element_kit_mark.gdshader.
## No fills, no screen flash, no new colour: ARC only, brightened toward white at the hot ends.

const Palette := preload("res://chapter1/view/hud/palette.gd")
const MARK_SHADER := preload("res://chapter1/view/fx/element_kit_mark.gdshader")

const FLOOR_CAP := 72
const HEAD_CAP := 168
## The budgets of A-element-kit-screen 2.1.
const TOOTH_MAX := 48
const RING_MAX := 6
const NAIL_MAX := 2
const BOLT_MAX := 32
const SMALL_BURSTS_PER_CONSUME := 8
const BIG_BURST_MAX := 4
const STORM_MAX := 6

const S_TOOTH := 0.0
const S_PIECES := 1.0
const S_PIECE := 2.0
const S_RING := 3.0
const S_TICKS := 4.0
const S_NAIL := 5.0
const S_BURST := 6.0
const S_HOOK := 7.0
const S_SHELL := 8.0
const S_BOLT := 9.0
const S_VEIN := 10.0
## Must equal NAIL_HALF_WIDTH_M and bolt_side() of the shader.
const NAIL_SIDE := 0.2

const FLOOR_Y := .11
const TOOTH_LINE := .03
## Body heights of chapter_actors.gd (placeholder figures there: elite 2.75, charger 1.35, the rest 1.7).
const BODY_NORMAL := 1.7
const BODY_CHARGER := 1.35
const BODY_ELITE := 2.75
const RING_RISE := .4
const RING_RADIUS := .55
const NEAR_HERO_SQ := 1.5 * 1.5
const NEAR_HERO_ALPHA := .3
const BOLT_STAGGER := .012

const K_BOLT := 0
const K_VEIN := 1
const K_SPARK := 2
const K_STORM := 3
const K_BURST := 4
const K_HOOK := 5
const K_GHOST := 6

const WHITE := Color(1,1,1)

var _floor: MultiMeshInstance3D
var _head: MultiMeshInstance3D
var _run: RefCounted
var _items: Array[Dictionary] = []
var _rings: Dictionary = {}
var _tooth_seen: Dictionary = {}
var _rods: Dictionary = {}
var _full_pending: Dictionary = {}
## Where bodies that died in the events being consumed stood (a spark's origin: the body is gone from `enemies` by then).
var _death_pos: Dictionary = {}
var _last_seq := -1
var _bolt_tick := -1
var _bolt_i := 0
var _small_this_consume := 0
var _last_big: Dictionary = {}
var _cap_seen := 0
var _bolt_live := 0
var _uid := 0
var _was_on := false
## Settings hooks (the app can pass the player's choices): 0 takes the bursts and brightening out, 0 takes the camera impulse out.
var flash_scale := 1.0
var shake_scale := 1.0
## Values of kit_view() a tool may stand in for while the core does not give them yet (`rod_radius_cm`, `cap_big`, ...). Empty in the game.
var kit_view_extra: Dictionary = {}
## What was drawn in the last sync (the dump and the budget check read it).
var stats := {"tooth":0,"rings":0,"pieces":0,"nails":0,"lines":0,"bursts":0,"floor":0,"head":0}

func setup(_fx: RefCounted) -> void:
	pass

## The batches are made on the first frame the kit is on, not here: with the kit off no node is added to the scene at all.
func _create(fx: RefCounted) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(2,2)
	_floor = fx._batch(plane,FLOOR_CAP)
	_floor.name = "ElementKitFloor"
	_floor.material_override = _material(8)
	_head = fx._batch(plane,HEAD_CAP)
	_head.name = "ElementKitHead"
	_head.material_override = _material(9)
	# The marks stand within a few tens of metres of the hero; a fixed box keeps the engine from deriving one out of unwritten instances.
	var box := AABB(Vector3(-400,-10,-400),Vector3(800,40,800))
	_floor.custom_aabb = box
	_head.custom_aabb = box

func _material(priority: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = MARK_SHADER
	mat.render_priority = priority
	var dim := Palette.BRASS_DIM
	mat.set_shader_parameter("empty_color",Color(dim.r,dim.g,dim.b,.9))
	return mat

func reset() -> void:
	_items.clear();_rings.clear();_tooth_seen.clear();_rods.clear();_full_pending.clear();_death_pos.clear();_last_big = {}
	_last_seq = -1;_bolt_tick = -1;_bolt_i = 0;_cap_seen = 0;_bolt_live = 0;_was_on = false;_run = null
	if is_instance_valid(_floor): _floor.multimesh.visible_instance_count = 0
	if is_instance_valid(_head): _head.multimesh.visible_instance_count = 0

# ---------------------------------------------------------------- events

func consume(events: Array, fx: RefCounted) -> void:
	_small_this_consume = 0
	_death_pos.clear()
	for event in events:
		if event.type == "death": _death_pos[int(event.get("target_id",-1))] = event.position
	for event in events:
		var seq := int(event.get("seq",0))
		if seq <= _last_seq: continue
		_last_seq = seq
		match String(event.type):
			"status_stacked":
				if bool(event.get("big",false)): _cap_seen = maxi(_cap_seen,int(event.get("max",0)))
			"status_full":
				_full_pending[int(event.get("target_id",-1))] = true
			"bolt_returned":
				_on_bolt(event,fx)
			"detonated":
				_on_detonated(event)
			"rod_planted":
				var id_ := int(event.get("target_id",-1))
				var until := int(event.get("until",0))
				_rods[id_] = {"start":int(event.tick),"until":until,"age":0.0,"len":1.0,"bottom":BODY_NORMAL,"top":Vector3.ZERO,"at":Vector2(event.position)}
			"rod_dropped":
				_on_rod_dropped(event)
			"chain_rebound":
				_add({"kind":K_HOOK,"at":Vector3(event.position.x,_chest_of(int(event.get("target_id",-1))),event.position.y),"age":0.0,"dur":.15,"rot":float(_uid % 6)*1.047})
			"kit_storm":
				_on_storm(event)

func _on_bolt(event: Dictionary, fx: RefCounted) -> void:
	var tick := int(event.tick)
	if tick != _bolt_tick:
		_bolt_tick = tick;_bolt_i = 0;_last_big = {}
	if int(event.get("merged",0)) > 0:
		# The overflow of the cast: no more lines, a bigger burst on the last big body.
		if not _last_big.is_empty(): _last_big.stacks = int(_last_big.stacks)+int(event.merged)
		return
	if _bolt_live >= BOLT_MAX: return
	var to_id := int(event.get("to_id",-1))
	var from_id := int(event.get("from_id",-1))
	var delay := float(_bolt_i)*BOLT_STAGGER
	_bolt_i += 1
	var end := Vector3(event.position.x,_chest_of(to_id),event.position.y)
	if bool(event.get("spark",false)):
		var from_at: Variant = _pos_of(from_id)
		if from_at == null: return
		_add({"kind":K_SPARK,"a":Vector3(from_at.x,1.0,from_at.y),"b":end,"age":-delay,"dur":.12,"w":.015,"alpha":.5,"seed":float(_uid)})
	elif bool(event.get("self",false)):
		var origin := end+Vector3(0,.9,0)
		var entry: Variant = _rings.get(to_id)
		if entry != null:
			if int(entry.virt_tick) != tick:
				entry.virt_tick = tick;entry.virt = int(entry.shown)
			var idx := maxi(0,int(entry.virt)-1)
			entry.virt = idx
			entry.drains.append(delay)
			origin = _ring_piece_at(fx,entry,idx)
		_add({"kind":K_VEIN,"a":origin,"b":end,"age":-delay,"dur":.15,"w":.02,"alpha":.9,"seed":float(_uid)})
	else:
		var from_at: Variant = _pos_of(from_id)
		if from_at == null: return
		_add({"kind":K_BOLT,"a":Vector3(from_at.x,1.0,from_at.y),"b":end,"age":-delay,"dur":.18,"w":.025,"alpha":.6,"seed":float(_uid)})

func _on_detonated(event: Dictionary) -> void:
	var target := int(event.get("target_id",-1))
	var stacks := int(event.get("stacks",1))
	var at := Vector3(event.position.x,_chest_of(target),event.position.y)
	if bool(event.get("big",false)):
		var live := 0
		for it in _items:
			if int(it.kind) == K_BURST and bool(it.big): live += 1
		if live >= BIG_BURST_MAX: return
		var item := {"kind":K_BURST,"big":true,"at":at,"age":-float(_bolt_i)*BOLT_STAGGER,"dur":.28,"stacks":stacks,"kicked":false}
		_add(item)
		_last_big = _items.back()
	elif _small_this_consume < SMALL_BURSTS_PER_CONSUME:
		_small_this_consume += 1
		_add({"kind":K_BURST,"big":false,"at":at,"age":0.0,"dur":.12,"stacks":1,"kicked":true})

func _on_rod_dropped(event: Dictionary) -> void:
	var id_ := int(event.get("target_id",-1))
	var rod: Variant = _rods.get(id_)
	if rod == null: return
	var dead := String(event.get("reason","")) == "dead"
	var at: Vector2 = rod.at
	if _run != null and _run.enemies.has(id_): at = _run.enemies[id_].position
	_add({"kind":K_GHOST,"at":at,"bottom":float(rod.bottom),"len":float(rod.len),"age":0.0,"dur":.15 if dead else .3,"tilt":0.0 if dead else .5})
	_rods.erase(id_)

func _on_storm(event: Dictionary) -> void:
	var done := 0
	for id_ in event.get("targets",[]):
		if done >= STORM_MAX or _bolt_live >= BOLT_MAX: break
		var enemy: Variant = _run.enemies.get(int(id_)) if _run != null else null
		if enemy == null: continue
		var rod: Variant = _rods.get(int(id_))
		var end := Vector3(enemy.position.x,_chest_of(int(id_)),enemy.position.y)
		if rod != null: end = rod.top
		_add({"kind":K_STORM,"a":end+Vector3(0,6.0-end.y,0),"b":end,"age":-float(done)*BOLT_STAGGER,"dur":.18,"w":.035,"alpha":.9,"seed":float(_uid)})
		done += 1

func _add(item: Dictionary) -> void:
	_uid += 1
	item.uid = _uid
	var kind := int(item.kind)
	if kind == K_BOLT or kind == K_VEIN or kind == K_SPARK or kind == K_STORM: _bolt_live += 1
	_items.append(item)

func _pos_of(id_: int) -> Variant:
	if _run != null and _run.enemies.has(id_): return _run.enemies[id_].position
	return _death_pos.get(id_)

func _chest_of(id_: int) -> float:
	if _run != null and _run.enemies.has(id_): return _body_h(_run.enemies[id_])*.55
	return BODY_NORMAL*.55

func _body_h(e: Dictionary) -> float:
	if bool(e.get("elite",false)): return BODY_ELITE
	return BODY_CHARGER if String(e.get("kind","")) == "charger" else BODY_NORMAL

## World position of piece `idx` of the ring over a big body (the ring is a screen-facing circle: screen right and up).
func _ring_piece_at(fx: RefCounted, entry: Dictionary, idx: int) -> Vector3:
	var basis: Basis = fx._cam_basis
	var turn := (float(idx)+.5)/float(maxi(1,int(entry.cap)))*TAU
	return Vector3(entry.at.x,float(entry.head),entry.at.y)+basis.x*sin(turn)*RING_RADIUS+basis.y*cos(turn)*RING_RADIUS

# ---------------------------------------------------------------- the frame

func sync(run: RefCounted, delta: float, fx: RefCounted) -> void:
	if not run.has_method("kit_view"): return
	var kv: Dictionary = run.kit_view()
	var on := bool(kv.get("on",false))
	if on and not kit_view_extra.is_empty(): kv.merge(kit_view_extra)
	_run = run
	if _floor == null:
		if not on: return
		_create(fx)
	if not on:
		if _was_on:
			fx._mmflush(_floor.multimesh,fx._mmbuf(_floor.multimesh),0)
			fx._mmflush(_head.multimesh,fx._mmbuf(_head.multimesh),0)
			_items.clear();_rings.clear();_tooth_seen.clear();_rods.clear();_bolt_live = 0;_was_on = false
		return
	_was_on = true
	var step := delta if run.mode == "playing" else 0.0
	var tick := int(run.tick)
	var hero: Vector2 = run.hero.position
	var fbuf: PackedFloat32Array = fx._mmbuf(_floor.multimesh)
	var hbuf: PackedFloat32Array = fx._mmbuf(_head.multimesh)
	var nf := 0
	var nh := 0
	var basis: Basis = fx._cam_basis
	var seconds := float(tick)/60.0
	var broken := false
	if run.has_method("boss_finale_view"):
		var finale: Dictionary = run.boss_finale_view()
		broken = bool(finale.get("on",false)) and String(finale.get("state","")) == "break"

	# One pass over the bodies: where they are, who carries the shock.
	var tooth_e: Array = []
	var tooth_d2 := PackedFloat32Array()
	var big_ids: Array[int] = []
	var big_d2 := PackedFloat32Array()
	for e in fx._enemies_frame:
		var st: Variant = e.get("kst")
		if st == null or int(st.n) < 1 or tick >= int(st.until): continue
		var id_: int = e.id
		var d2: float = e.position.distance_squared_to(hero)
		if e.elite:
			big_ids.append(id_);big_d2.append(d2)
		else:
			tooth_e.append(e);tooth_d2.append(d2)

	# ---- shocked ordinary bodies: arcs on the floor, the nearest TOOTH_MAX
	var cutoff := INF
	if tooth_e.size() > TOOTH_MAX:
		var sorted := tooth_d2.duplicate()
		sorted.sort()
		cutoff = sorted[TOOTH_MAX-1]
	var seen: Dictionary = {}
	var drawn_tooth := 0
	var new_pops := 0
	var phase := TAU*seconds/.6
	var tr := Palette.ARC.r
	var tg := Palette.ARC.g
	var tb := Palette.ARC.b
	for i in tooth_e.size():
		if drawn_tooth >= TOOTH_MAX or nf >= FLOOR_CAP: break
		if tooth_d2[i] > cutoff: continue
		var e: Dictionary = tooth_e[i]
		var id_: int = e.id
		var age := 99.0
		if _tooth_seen.has(id_): age = float(_tooth_seen[id_])+step
		elif new_pops < 6: age = 0.0;new_pops += 1
		seen[id_] = age
		var radius := .45
		if age < .12: radius = lerpf(.3,.45,age/.12)
		var alpha := .45+.15*(.5+.5*sin(phase+float(id_)*.7))
		var left := int(e.kst.until)-tick
		if left < 30: alpha = lerpf(.25,alpha,float(left)/30.0)
		if tooth_d2[i] < NEAR_HERO_SQ: alpha *= NEAR_HERO_ALPHA
		# a flat quad: only the non-zero floats are written (the buffer starts from zeros every frame)
		var half := radius*1.25+.15
		var o := nf*20
		var at: Vector2 = e.position
		fbuf[o] = half;fbuf[o+3] = at.x;fbuf[o+5] = 1.0;fbuf[o+7] = FLOOR_Y;fbuf[o+10] = half;fbuf[o+11] = at.y
		fbuf[o+12] = tr;fbuf[o+13] = tg;fbuf[o+14] = tb;fbuf[o+15] = alpha
		fbuf[o+17] = 0.0;fbuf[o+18] = TOOTH_LINE/half;fbuf[o+19] = radius/half
		nf += 1
		drawn_tooth += 1
	_tooth_seen = seen

	# ---- big bodies: the ring of pieces
	var order: Array[int] = []
	var picked := {}
	# The final boss keeps its ring even when it is the farthest body of the six.
	var champion := int(run.get("_champion_id"))
	for k in mini(RING_MAX,big_ids.size()):
		var best := -1
		var best_d := INF
		for i in big_ids.size():
			if picked.has(i): continue
			var d: float = -1.0 if big_ids[i] == champion else big_d2[i]
			if d < best_d: best_d = d;best = i
		picked[best] = true
		order.append(best)
	var kept: Dictionary = {}
	var pieces := 0
	for oi in order:
		var id_ := big_ids[oi]
		var e: Dictionary = run.enemies[id_]
		var n := int(e.kst.n)
		var cap := int(kv.get("cap_big",0))
		if cap <= 0: cap = _cap_seen
		cap = clampi(maxi(cap,n),1,255)
		var head_h := _body_h(e)
		var entry: Dictionary = _rings.get(id_,{})
		if entry.is_empty():
			entry = {"shown":0,"prev":0,"flash":[],"drains":[],"full_age":99.0,"virt_tick":-1,"virt":0,"cap":cap,"at":e.position,"head":head_h+RING_RISE}
		entry.cap = cap;entry.at = e.position;entry.head = head_h+RING_RISE
		kept[id_] = entry
		# the layers that went out in a cast leave one by one (the state already dropped them)
		var drains: Array = entry.drains
		for di in range(drains.size()-1,-1,-1):
			drains[di] = float(drains[di])-step
			if float(drains[di]) <= 0.0:
				entry.shown = maxi(n,int(entry.shown)-1)
				drains.remove_at(di)
		if n > int(entry.prev):
			for idx in range(int(entry.prev),mini(n,int(entry.prev)+3)): entry.flash.append(Vector2(idx,0.0))
		if drains.is_empty() or n > int(entry.shown): entry.shown = n
		entry.prev = n
		entry.full_age = float(entry.full_age)+step
		if _full_pending.has(id_):
			entry.full_age = 0.0;_full_pending.erase(id_)
		var mult := 1.0
		if broken: mult = .35
		if e.position.distance_squared_to(hero) < NEAR_HERO_SQ: mult *= NEAR_HERO_ALPHA
		var center := Vector3(e.position.x,float(entry.head),e.position.y)
		var color := Palette.ARC
		var glow := clampf(1.0-float(entry.full_age)/.25,0.0,1.0)*flash_scale
		if glow > 0.0: color = Palette.ARC.lerp(WHITE,glow*.55)
		var half := RING_RADIUS*1.25+.1
		var shown := int(entry.shown)
		nh = _put_bb(basis,hbuf,nh,center,half,S_PIECES,float(cap*256+shown),.035/half,RING_RADIUS/half,color,mult)
		pieces += shown
		if n >= cap and cap > 0:
			var r2 := RING_RADIUS+.08
			nh = _put_bb(basis,hbuf,nh,center,half,S_RING,0.0,.018/half,r2/half,Palette.ARC.lerp(WHITE,.3),mult*.8)
		var flashes: Array = entry.flash
		for fi in range(flashes.size()-1,-1,-1):
			var fl: Vector2 = flashes[fi]
			fl.y += step
			if fl.y >= .15 or flash_scale <= 0.0: flashes.remove_at(fi);continue
			flashes[fi] = fl
			nh = _put_bb(basis,hbuf,nh,center,half,S_PIECE,float(cap*256+int(fl.x)),.035/half,RING_RADIUS/half,Palette.ARC.lerp(WHITE,.85),mult*(1.0-fl.y/.15))
	_rings = kept

	# ---- rods: a nail over the body (length = time left) and the reach ticks on the floor
	var radius_m := float(kv.get("rod_radius_cm",0))/100.0
	var drawn_nails := 0
	for id_ in kv.get("rods",[]):
		if drawn_nails >= NAIL_MAX or not run.enemies.has(id_): continue
		var e: Dictionary = run.enemies[id_]
		var until := int(e.get("rod_until",0))
		if until <= tick: continue
		var rod: Dictionary = _rods.get(id_,{})
		if rod.is_empty():
			rod = {"start":tick,"until":until,"age":9.0,"len":1.0,"bottom":BODY_NORMAL,"top":Vector3.ZERO,"at":e.position}
			_rods[id_] = rod
		rod.until = until
		rod.age = float(rod.age)+step
		var total := float(maxi(1,until-int(rod.start)))
		var share := clampf(float(until-tick)/total,0.0,1.0)
		var length := .4+1.0*share
		var bottom := _body_h(e)-.1 if bool(e.get("elite",false)) else _body_h(e)
		rod.len = length;rod.bottom = bottom;rod.at = e.position
		var drop := 0.0
		if float(rod.age) < .12: drop = 3.0*(1.0-float(rod.age)/.12)
		var mult := 1.0
		if e.position.distance_squared_to(hero) < NEAR_HERO_SQ: mult = NEAR_HERO_ALPHA
		rod.top = Vector3(e.position.x,bottom+length,e.position.y)
		nh = _put_nail(basis,hbuf,nh,Vector3(e.position.x,bottom+drop,e.position.y),length,0.0,Palette.ARC.lerp(WHITE,.25),mult)
		drawn_nails += 1
		if radius_m > 0.0:
			var grow := 1.0
			if float(rod.age) < .2: grow = lerpf(.7,1.0,float(rod.age)/.2)
			var tick_half := .22
			nf = _put_floor(fx,fbuf,nf,e.position,S_TICKS,0.0,radius_m*grow,tick_half,Palette.ARC,.22*mult)

	# ---- the shell round the hero
	if int(kv.get("shell_until",0)) > tick:
		var actors: Variant = fx.view.get("actors")
		var hero3 := Vector3(hero.x,0,hero.y)
		if actors != null: hero3 = actors.hero.position
		var shell_r := 1.9*.9*.5
		var shell_half := shell_r*1.25+.1
		nh = _put_bb(basis,hbuf,nh,hero3+Vector3(0,.95,0),shell_half,S_SHELL,seconds*.35,.012/shell_half,shell_r/shell_half,Palette.ARC,.35)

	# ---- the short-lived things: lines, bursts, hooks, ghosts of nails
	var lines := 0
	var bursts := 0
	var live: Array[Dictionary] = []
	for it in _items:
		it.age = float(it.age)+step
		var age := float(it.age)
		var dur := float(it.dur)
		if age >= dur:
			var kind_done := int(it.kind)
			if kind_done == K_BOLT or kind_done == K_VEIN or kind_done == K_SPARK or kind_done == K_STORM: _bolt_live -= 1
			continue
		live.append(it)
		if age < 0.0: continue
		var t := clampf(age/dur,0.0,1.0)
		match int(it.kind):
			K_BOLT,K_VEIN,K_SPARK,K_STORM:
				if nh >= HEAD_CAP: continue
				var fade := 1.0-smoothstep(.5,1.0,t)
				var shape := S_VEIN if int(it.kind) == K_VEIN else S_BOLT
				nh = _put_bolt(basis,hbuf,nh,it.a,it.b,float(it.seed),float(it.w),shape,Palette.ARC,float(it.alpha)*fade)
				lines += 1
			K_BURST:
				if flash_scale <= 0.0: continue
				var big := bool(it.big)
				var stacks := mini(int(it.stacks),8)
				var radius := minf(1.4,.6+float(stacks)*.06) if big else .35
				var rays := (6+(stacks>>1)) if big else 4
				var ease_t := 1.0-(1.0-t)*(1.0-t)
				var r_now := radius*(.55+.45*ease_t)
				var half := r_now*1.1+.05
				nh = _put_bb(basis,hbuf,nh,it.at,half,S_BURST,float(rays)+float(int(it.uid) % 10)/10.0,(.05 if big else .03)/half,r_now/half,Palette.ARC.lerp(WHITE,.35*(1.0-t)),(1.0-t)*(.95 if big else .8)*flash_scale)
				bursts += 1
				if big and not bool(it.kicked) and int(it.stacks) >= 8:
					it.kicked = true
					if shake_scale > 0.0: fx._kick(.25*shake_scale,tick,true)
			K_HOOK:
				var half := .5*1.25+.1
				nh = _put_bb(basis,hbuf,nh,it.at,half,S_HOOK,0.0,.025/half,.5/half,Palette.ARC,(1.0-t)*.9,float(it.rot))
			K_GHOST:
				var tilt := float(it.tilt)*t
				var ghost_at: Vector2 = it.at
				nh = _put_nail(basis,hbuf,nh,Vector3(ghost_at.x,float(it.bottom),ghost_at.y),float(it.len),tilt,Palette.ARC.lerp(WHITE,.25),1.0-t)
	_items = live

	stats.tooth = drawn_tooth;stats.rings = order.size();stats.pieces = pieces;stats.nails = drawn_nails;stats.lines = lines;stats.bursts = bursts
	stats.floor = nf;stats.head = nh
	fx._mmflush(_floor.multimesh,fbuf,nf)
	fx._mmflush(_head.multimesh,hbuf,nh)

# ---------------------------------------------------------------- instance writers

## A flat mark on the floor: `radius` metres, `line` metres of half width (ticks: half length of one tick).
func _put_floor(fx: RefCounted, buf: PackedFloat32Array, n: int, at: Vector2, shape: float, param: float, radius: float, line: float, color: Color, alpha: float) -> int:
	if n >= FLOOR_CAP: return n
	var half := radius*1.25+.15
	var o := n*20
	_write(buf,o,Transform3D(Basis.IDENTITY.scaled(Vector3(half,1.0,half)),Vector3(at.x,FLOOR_Y,at.y)),Color(color.r,color.g,color.b,alpha),Color(shape,param,line/half,radius/half))
	return n+1

## A mark facing the camera, `half` metres to each edge; line and radius in quad units.
func _put_bb(basis: Basis, buf: PackedFloat32Array, n: int, at: Vector3, half: float, shape: float, param: float, line_q: float, radius_q: float, color: Color, alpha: float, rot: float = 0.0) -> int:
	if n >= HEAD_CAP: return n
	var cx := basis.x
	var cy := basis.y
	if rot != 0.0:
		cx = basis.x*cos(rot)+basis.y*sin(rot)
		cy = basis.y*cos(rot)-basis.x*sin(rot)
	var o := n*20
	_write(buf,o,Transform3D(Basis(cx*half,basis.z,-cy*half),at),Color(color.r,color.g,color.b,alpha),Color(shape,param,line_q,radius_q))
	return n+1

## A standing nail, foot at `foot`, `length` metres tall, leaning `tilt` metres at the foot.
func _put_nail(basis: Basis, buf: PackedFloat32Array, n: int, foot: Vector3, length: float, tilt: float, color: Color, alpha: float) -> int:
	if n >= HEAD_CAP: return n
	var h := length*.5
	var o := n*20
	var lean := basis.x*tilt
	_write(buf,o,Transform3D(Basis(basis.x*NAIL_SIDE,basis.z,-basis.y*h+lean),foot+basis.y*h),Color(color.r,color.g,color.b,alpha),Color(S_NAIL,0.0,0.0,h))
	return n+1

## A kinked line from `a` to `b`: the quad's long axis is the line, its short axis is screen-side of it.
func _put_bolt(basis: Basis, buf: PackedFloat32Array, n: int, a: Vector3, b: Vector3, seed: float, half_width_m: float, shape: float, color: Color, alpha: float) -> int:
	if n >= HEAD_CAP: return n
	var along := b-a
	var length := along.length()
	if length < .05: return n
	var side := along.cross(basis.z)
	side = side.normalized() if side.length_squared() > .0001 else basis.x
	var o := n*20
	var wide := _bolt_side(length*.5)
	_write(buf,o,Transform3D(Basis(along*.5,basis.z,side*wide),(a+b)*.5),Color(color.r,color.g,color.b,alpha),Color(shape,seed,half_width_m/wide,length*.5))
	return n+1

## The short half width of a bolt's quad (metres), longer for a longer bolt; the shader's bolt_side() is the same formula.
static func _bolt_side(half_length_m: float) -> float:
	return clampf(.2+.2*half_length_m,.3,.9)

## The buffer layout of chapter_effects.gd (12 transform floats, colour at 12, custom at 16).
static func _write(buf: PackedFloat32Array, o: int, t: Transform3D, color: Color, custom: Color) -> void:
	var bs := t.basis
	var org := t.origin
	buf[o] = bs.x.x;buf[o+1] = bs.y.x;buf[o+2] = bs.z.x;buf[o+3] = org.x
	buf[o+4] = bs.x.y;buf[o+5] = bs.y.y;buf[o+6] = bs.z.y;buf[o+7] = org.y
	buf[o+8] = bs.x.z;buf[o+9] = bs.y.z;buf[o+10] = bs.z.z;buf[o+11] = org.z
	buf[o+12] = color.r;buf[o+13] = color.g;buf[o+14] = color.b;buf[o+15] = color.a
	buf[o+16] = custom.r;buf[o+17] = custom.g;buf[o+18] = custom.b;buf[o+19] = custom.a
