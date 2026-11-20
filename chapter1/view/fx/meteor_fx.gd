extends RefCounted
## D20 Meteor presenter: the evolved ember books a fall instead of shooting. Reads core events only (meteor_cast, explosion
## with "meteor"); never writes core state. Layers:
##   book    meteor_cast {id, land_tick, radius_cm, cast_uid, origin} + position (the spot): a soot/ember mark on the floor that
##           darkens for the fall time (its edge IS radius_cm, no larger), and a short spark streak up from the hero's hand.
##   fall    a big fire ball (the fireball's parts at 2.75x, a tail of 3.5 ball widths) comes down the screen at 60..70 degrees
##           from the upper left, slow at first and fast at the end; the floor glow under it grows as it nears.
##   land    explosion {meteor:id}: the ball goes, a ring band and upward sparks join the common burst, camera kick (the
##           world's own kick_camera, which honours the reduced-motion setting), scorch + cinders stay on the floor 1.4 s.
## Draw cost: one MultiMesh of floor marks, one of balls. Pools follow the core's own cap (combat_core MAX_METEORS 64 falls booked
## at once; a cast books at most 16): 64 balls + 8 launch streaks, 64 waiting marks + 64 scorches.

const BALL_SHADER := preload("res://chapter1/view/fx/meteor_ball.gdshader")
const MARK_SHADER := preload("res://chapter1/view/fx/meteor_mark.gdshader")
const FALL_CAP := 64
const LAUNCH_CAP := 8
const MARK_CAP := 128
const SCORCH_SECONDS := 1.4
const START_DIST := 15.0       ## metres along the fall line at the start of the fall (off the top of the 1080p view)
const BALL_SCALE := 1.0        ## quad is 8 x 3.4 m, ball radius .8 m (2.75 x the fireball's .29 m)
const FIRE := Color("ff943d")

var _balls: MultiMeshInstance3D
var _marks: MultiMeshInstance3D
var _falls: Array[Dictionary] = []
var _launches: Array[Dictionary] = []
var _last_seq := -1
var _last_launch_uid := -1
var _clock := 0.0

func setup(fx: RefCounted) -> void:
	if "--chapter1-no-meteor-fx" in OS.get_cmdline_user_args(): return   # A/B switch for frame-time checks: the fall is then not drawn
	var quad := QuadMesh.new()
	quad.size = Vector2(8.0,3.4)
	_balls = fx._batch(quad,FALL_CAP+LAUNCH_CAP)
	_balls.name = "MeteorBalls"
	var ball_mat := ShaderMaterial.new()
	ball_mat.shader = BALL_SHADER
	_balls.material_override = ball_mat
	var plane := PlaneMesh.new()
	plane.size = Vector2(2,2)
	_marks = fx._batch(plane,MARK_CAP)
	_marks.name = "MeteorMarks"
	var mark_mat := ShaderMaterial.new()
	mark_mat.shader = MARK_SHADER
	_marks.material_override = mark_mat

func reset() -> void:
	_falls.clear();_launches.clear()
	_last_seq = -1;_last_launch_uid = -1
	for node in [_balls,_marks]:
		if is_instance_valid(node): node.multimesh.visible_instance_count = 0

func consume(events: Array, fx: RefCounted) -> void:
	for event in events:
		var seq := int(event.get("seq",0))
		if seq <= _last_seq: continue
		_last_seq = seq
		var kind := String(event.type)
		if kind == "meteor_cast":
			if _falls.size() >= FALL_CAP: continue
			var id := int(event.id)
			var fall_seconds := float(int(event.land_tick)-int(event.tick))/60.0
			if fall_seconds <= 0.0: fall_seconds = .4
			# Every fall has its own angle (60..70 degrees below the horizontal), so a volley does not read as one lump.
			var angle := 60.0+float((id*37)%11)
			_falls.append({"id":id,"pos":event.position,"radius":float(int(event.radius_cm))/100.0,"age":0.0,"dur":fall_seconds,
				"angle":angle,"seed":float(id%23)/23.0,"cast":int(event.cast_uid),"landed":false,"scorch":0.0})
			var uid := int(event.cast_uid)
			if uid != _last_launch_uid:
				_last_launch_uid = uid
				_launch(event.origin,fx)
		elif kind == "explosion" and event.has("meteor"):
			_land(int(event.meteor),event,fx)

## The hand flick: a short streak up the screen and a few sparks thrown up from the hero.
func _launch(origin: Vector2, fx: RefCounted) -> void:
	if _launches.size() < LAUNCH_CAP:
		_launches.append({"pos":origin,"age":0.0,"seed":fx._rng.randf()})
	var room: int = fx.MAX_PARTICLES-fx._d_life.size()
	for i in mini(7,room):
		fx._debris_add(Vector3(origin.x,1.0,origin.y),Vector3(fx._rng.randf_range(-.7,.7),fx._rng.randf_range(3.0,5.5),fx._rng.randf_range(-.7,.7)),
			fx._rng.randf_range(.18,.38),FIRE,fx._rng.randf_range(.7,1.2))

func _land(id: int, event: Dictionary, fx: RefCounted) -> void:
	var lump := 0   # falls of this cast: a volley lands on one lump, so its stacked additive rings and sparks share one budget
	var cast_uid := -1
	for fall in _falls:
		if int(fall.id) == id:
			fall.landed = true;fall.scorch = 0.0
			cast_uid = int(fall.cast)
	for fall in _falls:
		if int(fall.cast) == cast_uid: lump += 1
	lump = maxi(1,lump)
	var at: Vector2 = event.position
	var radius := float(int(event.get("radius_cm",150)))/100.0
	# A thin orange band spreads once from the middle (the shared hollow-ring impact; never a red closed circle). Sixteen of them
	# stacked additively clipped the landing to yellow, so each takes its share (the ring branch of the impact shader scales by gain).
	if fx.strokes.size() < fx.MAX_STROKES:
		fx.strokes.append({"type":"impact","at":at,"radius":radius*1.12,"life":.30,"duration":.30,"element":0.0,"color":FIRE,"ring":true,"gain":clampf(1.0/float(lump),.12,1.0)})
	# Sparks thrown up (the common burst already threw the sideways ones).
	var room: int = fx.MAX_PARTICLES-fx._d_life.size()
	for i in mini(maxi(2,12/lump),room):
		fx._debris_add(Vector3(at.x,.3,at.y),Vector3(fx._rng.randf_range(-1.6,1.6),fx._rng.randf_range(4.0,8.0),fx._rng.randf_range(-1.6,1.6)),
			fx._rng.randf_range(.30,.55),FIRE,fx._rng.randf_range(.8,1.5))
	fx._kick(.32,int(event.tick))

func sync(run: RefCounted, delta: float, fx: RefCounted) -> void:
	if _balls == null: return
	if _falls.is_empty() and _launches.is_empty():
		if _balls.multimesh.visible_instance_count != 0 or _marks.multimesh.visible_instance_count != 0:
			fx._mmflush(_balls.multimesh,fx._mmbuf(_balls.multimesh),0)
			fx._mmflush(_marks.multimesh,fx._mmbuf(_marks.multimesh),0)
		return
	var step := delta if run.mode == "playing" else 0.0
	var cam_x: Vector3 = fx._cam_basis.x
	var cam_y: Vector3 = fx._cam_basis.y
	var bm: MultiMesh = _balls.multimesh
	var mm: MultiMesh = _marks.multimesh
	var bbuf: PackedFloat32Array = fx._mmbuf(bm)
	var mbuf: PackedFloat32Array = fx._mmbuf(mm)
	var bn := 0
	var mn := 0
	var live: Array[Dictionary] = []
	# A volley (one cast_id) piles its marks on one spot: each takes its share so the sum does not clip.
	var per_cast := {}
	var drawn_cast := {}
	for counted in _falls: per_cast[counted.cast] = int(per_cast.get(counted.cast,0))+1
	for fall in _falls:
		var share := minf(1.0,1.5/float(per_cast[fall.cast]))
		var spot: Vector2 = fall.pos
		var radius: float = fall.radius
		if fall.landed:
			fall.scorch += step
			if fall.scorch >= SCORCH_SECONDS: continue
			if mn < MARK_CAP:
				var o: int = mn*fx.MM_STRIDE
				fx._wx(mbuf,o,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*radius*1.3),Vector3(spot.x,.045,spot.y)))
				fx._wc(mbuf,o+fx.MM_CUSTOM,Color(float(fall.scorch)/SCORCH_SECONDS,1.0,fall.seed,share))
				mn += 1
		else:
			fall.age += step
			if fall.age > float(fall.dur)*1.6: continue   # never landed (the run ended): let it go
			var t := clampf(float(fall.age)/float(fall.dur),0.0,1.0)
			if mn < MARK_CAP:
				var o2: int = mn*fx.MM_STRIDE
				fx._wx(mbuf,o2,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*radius*1.3),Vector3(spot.x,.04,spot.y)))
				fx._wc(mbuf,o2+fx.MM_CUSTOM,Color(t,0.0,fall.seed,share))
				mn += 1
			# One big ball per cast: the falls of a cast land on the same tick, so they share one head (aimed at the middle of
			# their landing spots, bigger with the count); each fall still lands, marks and bursts on its own spot.
			if t < 1.0 and bn < FALL_CAP and not drawn_cast.has(fall.cast):
				drawn_cast[fall.cast] = true
				var members := 0
				var sum := Vector2.ZERO
				for other in _falls:
					if int(other.cast) == int(fall.cast) and not other.landed:
						members += 1
						sum += other.pos
				var mid := sum/float(maxi(1,members))
				var a := deg_to_rad(float(fall.angle))
				var dir := Vector2(cos(a),-sin(a))                       # on the screen: right and down
				var dist := START_DIST*(1.0-t)*(1.0-t)                  # slow at first, fast at the end
				var head := Vector3(mid.x,.6,mid.y)-(cam_x*dir.x+cam_y*dir.y)*dist
				var big := minf(1.0+.3*sqrt(float(maxi(0,members-1))),1.9)
				var grow := lerpf(.5,1.0,sqrt(t))*BALL_SCALE*big
				var bo: int = bn*fx.MM_STRIDE
				fx._wx(bbuf,bo,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*grow),head))
				fx._wc(bbuf,bo+fx.MM_CUSTOM,Color(atan2(dir.y,dir.x),t,fall.seed,0))
				bn += 1
		live.append(fall)
	_falls = live
	var kept: Array[Dictionary] = []
	for streak in _launches:
		streak.age += step
		if streak.age > .22: continue
		kept.append(streak)
		if bn >= FALL_CAP+LAUNCH_CAP: continue
		var s := float(streak.age)/.22
		var origin: Vector2 = streak.pos
		var up := (cam_x*.12+cam_y*.99)
		var pos := Vector3(origin.x,1.0,origin.y)+up*(s*s*7.0+.3)
		var lo: int = bn*fx.MM_STRIDE
		fx._wx(bbuf,lo,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*.28*(1.0-.5*s)),pos))
		fx._wc(bbuf,lo+fx.MM_CUSTOM,Color(atan2(.99,.12),s,streak.seed,0))
		bn += 1
	_launches = kept
	fx._mmflush(bm,bbuf,bn)
	fx._mmflush(mm,mbuf,mn)
