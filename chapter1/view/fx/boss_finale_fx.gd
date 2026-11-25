extends RefCounted
## A-boss-finale-screen (vfx-feel): what the final boss's fight (D-boss-finale, tuning.boss_finale) adds to the floor. Reads core events and
## read-only core state (`_bf_on`, `_bf_state`, `_bf_to`, `_bf_until`, `_bf_break`, `_bf`, `chapter_hazards`, `enemies`); writes nothing into the core.
## With the finale off none of the events come and `_bf_on` is false, so nothing here draws.
##   entrance  a linen ring closes round the boss's feet while it is out of play (`_bf_state == "entrance"`).
##   leaving   boss_break_started: dust ring and a short dust column where the body stood, camera .45.
##   waiting   while `_bf_state == "break"` a dashed ring (threat line colour, faint, no fill) marks where it comes down; it gives way to the
##             landing's own telegraph (a hazard with kind "land"), whose shadow disc grows under the spot.
##   landing   chapter_burst{kind: land}: a dust ring the size of the landing, camera .6.
##   storm     chapter_burst{kind: storm}: a short soft flash on each spot, camera .15 (the shake rate limit makes it one per volley).
##   blocked   boss_hit_blocked: one small linen ring on the body, never two at once, no number, no red, no camera.
##   potion    boss_potion: a small ring of the potion's colour.
##   struck    boss_break_struck: camera .5 (the body is drawn by chapter_actors.gd).
## One MultiMesh (boss_finale_mark.gdshader), 40 quads at most, drawn under the telegraphs (render priority 9; the telegraphs are 10 to 12).

const Palette := preload("res://chapter1/view/hud/palette.gd")
const MARK_SHADER := preload("res://chapter1/view/fx/boss_finale_mark.gdshader")
const CAP := 40
const MARK_Y := .10
const SHAPE_DASHED := 0.0
const SHAPE_DISC := 1.0
const SHAPE_RING := 2.0
const SHAPE_COLUMN := 3.0
## The threat line colour of telegraph_look.gdshaderinc (TELE_LINE_RGB); the dashed ring is that line, only fainter.
const THREAT_LINE := Color(.80,.18,.17)
const DUST := Color(.62,.60,.55)
const SHADOW := Color(.02,.015,.02)
const FLASH := Color(.96,.80,.62)
const POTION := Color("c1494e")
const BLOCK_SECONDS := .25
const DASH_ALPHA := .30

var _marks: MultiMeshInstance3D
var _items: Array[Dictionary] = []
var _last_seq := -1
## The slam's wind-up in ticks, from the last boss_telegraph{attack_id: slam} (chapter_effects.gd and the body read it; 0 until one came).
var slam_windup := 0
var _last_boss_pos := Vector2.ZERO
var _have_boss_pos := false
var _block_age := 99.0
var _boss_pos_id := -1

## The mark batch is made on the first frame the finale is on, not here: with the finale off no node is added to the scene at all.
func setup(_fx: RefCounted) -> void:
	pass

func _create(fx: RefCounted) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(2,2)
	_marks = fx._batch(plane,CAP)
	_marks.name = "BossFinaleMarks"
	var mat := ShaderMaterial.new()
	mat.shader = MARK_SHADER
	mat.render_priority = 9
	_marks.material_override = mat

func reset() -> void:
	_items.clear()
	_last_seq = -1;slam_windup = 0;_have_boss_pos = false;_block_age = 99.0;_boss_pos_id = -1
	if is_instance_valid(_marks): _marks.multimesh.visible_instance_count = 0

func consume(events: Array, fx: RefCounted) -> void:
	for event in events:
		var seq := int(event.get("seq",0))
		if seq <= _last_seq: continue
		_last_seq = seq
		match String(event.type):
			"boss_telegraph":
				if String(event.get("attack_id","")) == "slam": slam_windup = int(event.get("windup_ticks",0))
			"boss_break_started":
				# The core has already moved the body to the landing spot; the last spot the picture drew is where it stood.
				if _have_boss_pos:
					_items.append({"shape":SHAPE_RING,"at":_last_boss_pos,"age":0.0,"dur":.30,"r0":.4,"r1":2.2,"color":DUST,"alpha":.40,"line":.06})
					_items.append({"shape":SHAPE_COLUMN,"at":_last_boss_pos,"age":0.0,"dur":.30,"r0":3.4,"r1":3.4,"color":DUST,"alpha":.38,"line":0.0})
				fx._kick(.45,int(event.tick))
			"chapter_burst":
				var kind := String(event.get("kind",""))
				if kind == "land":
					var radius := float(event.get("radius",3.0))
					_items.append({"shape":SHAPE_RING,"at":event.position,"age":0.0,"dur":.35,"r0":radius*.25,"r1":radius,"color":DUST,"alpha":.45,"line":.09})
					fx._kick(.6,int(event.tick))
				elif kind == "storm":
					var radius := float(event.get("radius",1.8))
					_items.append({"shape":SHAPE_DISC,"at":event.position,"age":0.0,"dur":.12,"r0":radius*.8,"r1":radius*.9,"color":FLASH,"alpha":.45,"line":0.0})
					fx._kick(.15,int(event.tick))
			"boss_hit_blocked":
				# Linen ring on the body for a quarter second; a new one never starts while one is alive.
				if _block_age >= BLOCK_SECONDS:
					_block_age = 0.0
					_items.append({"shape":SHAPE_RING,"at":event.position,"age":0.0,"dur":BLOCK_SECONDS,"r0":.7,"r1":1.0,"color":Palette.LINEN,"alpha":.75,"line":.04,"block":true})
			"boss_potion":
				_items.append({"shape":SHAPE_RING,"at":event.position,"age":0.0,"dur":.30,"r0":.25,"r1":.9,"color":POTION,"alpha":.80,"line":.05})
			"boss_break_struck":
				fx._kick(.5,int(event.tick))

func sync(run: RefCounted, delta: float, fx: RefCounted) -> void:
	var on := bool(run.get("_bf_on"))
	if _marks == null:
		if not on: return
		_create(fx)
	if not on and _items.is_empty():
		if _marks.multimesh.visible_instance_count != 0: fx._mmflush(_marks.multimesh,fx._mmbuf(_marks.multimesh),0)
		return
	var step := delta if run.mode == "playing" else 0.0
	_block_age += step
	var cid := int(run.get("_champion_id"))
	if on and cid > 0 and run.enemies.has(cid):
		_last_boss_pos = run.enemies[cid].position;_have_boss_pos = true
	var mm: MultiMesh = _marks.multimesh
	var buf: PackedFloat32Array = fx._mmbuf(mm)
	var n := 0
	if on:
		var state := String(run.get("_bf_state"))
		if state == "entrance" and _have_boss_pos:
			var total := float(maxi(1,int(run._bf.get("entrance_ticks",120))))
			var progress := clampf(1.0-float(int(run._bf_until)-int(run.tick))/total,0.0,1.0)
			n = _put(fx,buf,n,_last_boss_pos,SHAPE_RING,progress,1.6,.035,Palette.LINEN,.80)
		elif state == "break":
			var land_up := false
			var hazards: Variant = run.get("chapter_hazards")
			if hazards != null:
				for h in hazards:
					if String(h.get("kind","")) != "land": continue
					land_up = true
					# The shadow of the body that is coming down grows under the spot.
					var span := float(maxi(1,int(h.expires)-int(h.started)))
					var k := clampf(1.0-float(int(h.expires)-int(run.tick))/span,0.0,1.0)
					n = _put(fx,buf,n,h.position,SHAPE_DISC,0.0,.3+.9*k,0.0,SHADOW,.50*k)
			if not land_up:
				var rule: Dictionary = run._bf.breaks[int(run._bf_break)]
				n = _put(fx,buf,n,run._bf_to,SHAPE_DASHED,0.0,float(rule.land.radius_m),.03,THREAT_LINE,DASH_ALPHA)
	var live: Array[Dictionary] = []
	for item in _items:
		item.age += step
		if float(item.age) >= float(item.dur) or n >= CAP: continue
		live.append(item)
		var t := clampf(float(item.age)/float(item.dur),0.0,1.0)
		var ease_t := 1.0-(1.0-t)*(1.0-t)
		var alpha := float(item.alpha)*(1.0-t)
		if item.shape == SHAPE_COLUMN:
			n = _put_column(fx,buf,n,item.at,float(item.r0)*(.35+.65*ease_t),item.color,alpha)
		else:
			n = _put(fx,buf,n,item.at,item.shape,1.0,lerpf(float(item.r0),float(item.r1),ease_t),float(item.line),item.color,alpha)
	_items = live
	fx._mmflush(mm,buf,n)

## A flat mark: `radius` metres, `line` metres of half width. dashed: param = dash phase; ring: param = share of the lap drawn.
func _put(fx: RefCounted, buf: PackedFloat32Array, n: int, at: Vector2, shape: float, param: float, radius: float, line: float, color: Color, alpha: float) -> int:
	if n >= CAP: return n
	var half := radius*1.25+.15
	var o: int = n*fx.MM_STRIDE
	fx._wx(buf,o,Transform3D(Basis.IDENTITY.scaled(Vector3(half,1.0,half)),Vector3(at.x,MARK_Y,at.y)))
	fx._wc(buf,o+fx.MM_COLOR,Color(color.r,color.g,color.b,alpha))
	fx._wc(buf,o+fx.MM_CUSTOM,Color(shape,param,line/half,radius/half))
	return n+1

## A dust column standing on the floor, facing the camera: 1.4 m wide, `height` metres tall, foot at `at`.
func _put_column(fx: RefCounted, buf: PackedFloat32Array, n: int, at: Vector2, height: float, color: Color, alpha: float) -> int:
	if n >= CAP: return n
	var o: int = n*fx.MM_STRIDE
	var cam_x: Vector3 = fx._cam_basis.x
	var cam_y: Vector3 = fx._cam_basis.y
	var cam_z: Vector3 = fx._cam_basis.z
	# plane x -> screen right, plane normal -> towards the camera, plane z -> screen down (UV.y 1 is the foot)
	var basis := Basis(cam_x*.7,cam_z,-cam_y*height*.5)
	fx._wx(buf,o,Transform3D(basis,Vector3(at.x,MARK_Y,at.y)+cam_y*height*.5))
	fx._wc(buf,o+fx.MM_COLOR,Color(color.r,color.g,color.b,alpha))
	fx._wc(buf,o+fx.MM_CUSTOM,Color(SHAPE_COLUMN,1.0,0.0,0.0))
	return n+1
