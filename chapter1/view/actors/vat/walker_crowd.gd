extends RefCounted
## Walker crowd (T2b B-b): every skeleton outlaw ("walker") of the run drawn as one MultiMesh of baked vertex animation.
## Only built when the game is started with --chapter1-vat-walker. The bone-animated walker presenters of chapter_actors.gd
## are then not used for walkers; ranged, charger, elite and boss presenters are unchanged.
##
## Presentation only. Reads core enemy dictionaries (never writes them) and the presenter's own event tables
## (hit/recoil/paid attacks/cold corpses, shared by reference). The per-enemy rules below are the ones of
## chapter_actors.gd (_present_position, _update_pose, sync__chapterx colour, _overlaps_hero, _sync_hero_rim fade,
## sync__q20 victory fade) without the T2-2' pose schedule: the GPU poses every walker every frame.
##
## Per frame, in this order (called by chapter_actors.gd):
##   begin_frame(...)   once, from sync__cloister before the enemy loop
##   track(e, key)      per walker, inside the enemy loop; returns true when a living walker overlaps the owner
##   end_frame(...)     once, after the whole sync chain: fade, colour, one buffer write
##   capture(run)       per core tick (consume), same rule as _capture_motion

const Baker := preload("res://chapter1/view/actors/vat/vat_baker.gd")
const Spec := preload("res://chapter1/view/actors/vat/walker_vat_spec.gd")

const STRIDE := 20                      ## floats per instance: transform 12, colour 4, custom data 4
const MIN_CAPACITY := 256
const WALK := 56.0 / 60.0               ## WALK34
const SWING := 68.0 / 60.0              ## SWING34
const STRIKE := 25.0 / 60.0             ## STRIKE34
const IDLE_LENGTH := 128.0 / 60.0
const CORPSE_FINAL_AGE := 1.60
const OVERLAP_CULL_SQ := 30.25
const OVERLAP_CULL_MIN_SIN := .70
const ICE := Color(.48, .86, 1.16)
const FLASH := Color(1.3, 1.2, 1.05)
const NON_TICKING_MODES := ["paused", "choice", "inventory", "equipment"]
const MIN_ALPHA := .002                 ## an instance fainter than this is not drawn at all

class Walker:
	var key := ""
	var ck := 0
	var seen := -1
	# motion sample (_present_position)
	var has_sample := false
	var s_tick := 0
	var s_prev := Vector2.ZERO
	var s_cur := Vector2.ZERO
	var s_phase := 0.0
	# presentation
	var pos := Vector3.ZERO
	var yaw := 0.0
	var scale_ := .62
	var fade := 1.0
	var death_age := 0.0
	var has_pose := false
	var row := 0.0
	var hit_row := -1.0
	var hit_weight := 0.0
	var cold: Variant = null
	# per frame
	var dead := false
	var overlap := false
	var icy := false
	var flash := false
	var xf := Transform3D.IDENTITY

var view: Node3D
var baked: Dictionary = {}
var bake_usec := 0
var instances_shown := 0
var instances_peak := 0
var tracked_total := 0

var _node: MultiMeshInstance3D
var _mm: MultiMesh
var _rid := RID()
var _buf := PackedFloat32Array()
var _capacity := 0
var _table: Dictionary = {}
var _spine := PackedVector3Array()
var _head := PackedVector3Array()
var _bone_last := 0
var _by_key: Dictionary = {}
var _by_ck: Dictionary = {}
var _active: Array[Walker] = []
var _hit_until: Dictionary
var _recoil: Dictionary
var _attacks: Dictionary
var _cold: Dictionary
# frame state
var _frame := 0
var _open := false
var _run: RefCounted
var _delta := 0.0
var _tick := 0
var _mode_playing := false
var _mode_ticking := true
var _fraction := 1.0
var _camera: Camera3D
var _view_xf := Transform3D.IDENTITY
var _hero_world := Vector3.ZERO
var _cam_z := Vector3.BACK
var _steep_ortho := false
var _hero_ready := false
var _hero_a := Vector2.ZERO
var _hero_b := Vector2.ZERO
var _hero_radius := 0.0

## Bakes the walker on the CPU (headless-safe, about one second) and builds the MultiMesh under owner_view.
## The four dictionaries are the presenter's event tables, shared by reference (they are only cleared, never replaced).
func setup(owner_view: Node3D, hit_until: Dictionary, recoil: Dictionary, attacks: Dictionary, cold: Dictionary) -> void:
	view = owner_view
	_hit_until = hit_until
	_recoil = recoil
	_attacks = attacks
	_cold = cold
	var started := Time.get_ticks_usec()
	var baker := Baker.new()
	baker.host = view
	baker.use_engine_bake = false   # the engine bake does not work headless and returns stale poses in a window
	var scene: PackedScene = load(Spec.MODEL_PATH)
	baked = baker.bake(scene, Spec.clips(), Spec.FPS, Spec.apply_overrides, Spec.TRACKED_BONES, Spec.HIT_BONES, Spec.HIT_EXCLUDE_BONES)
	for message in baker.errors:
		push_error(message)
	bake_usec = Time.get_ticks_usec() - started
	_table = baked.table
	_spine = baked.bones["ORG-spine"]
	_head = baked.bones["ORG-head"]
	_bone_last = _spine.size() - 1
	var materials := Baker.make_materials(baked)
	var mesh: ArrayMesh = baked.mesh
	for s in materials.size():
		mesh.surface_set_material(s, materials[s])
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = mesh
	_grow(MIN_CAPACITY)
	_mm.visible_instance_count = 0
	_node = MultiMeshInstance3D.new()
	_node.name = "WalkerCrowd"
	_node.multimesh = _mm
	_node.layers = 2   # same render layer as the bone-animated walker (_materials34), lit by the layer-2 sun
	_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	view.add_child(_node)
	# The baked arrays are in the MultiMesh now; the images stay referenced by the shader materials.
	baked.erase("pos_image")
	baked.erase("nrm_image")

func _grow(count: int) -> void:
	_capacity = count
	_mm.instance_count = count
	_buf = PackedFloat32Array()
	_buf.resize(count * STRIDE)
	_rid = _mm.get_rid()

func reset() -> void:
	_by_key.clear()
	_by_ck.clear()
	_active.clear()
	_open = false
	if _mm != null:
		_mm.visible_instance_count = 0

func has_key(key: String) -> bool:
	return _by_key.has(key)

## Interpolated world-space (view-local) position the presenter shows, or null when this key is not a crowd walker.
func presented_position(key: String) -> Variant:
	var w: Walker = _by_key.get(key)
	if w == null:
		return null
	return w.pos

# ---- per tick ------------------------------------------------------------------------------------------------------

## Same rule as _capture_motion: both endpoints of every core tick enter the motion sample.
func capture(run: RefCounted) -> void:
	if _by_ck.is_empty():
		return
	var playing: bool = run.mode == "playing"
	var tick: int = run.tick
	for e in run.enemies.values():
		if e.kind != "walker":
			continue
		var w: Walker = _by_ck.get((int(e.generation) << 32) | int(e.id))
		if w != null:
			_present(w, e.position, tick, playing, 1.0)

# ---- per frame -----------------------------------------------------------------------------------------------------

func begin_frame(run: RefCounted, delta: float, camera: Camera3D, hero_world: Vector3, view_xf: Transform3D, playing: bool) -> void:
	_frame += 1
	_open = true
	_active.clear()
	_run = run
	_delta = delta
	_tick = run.tick
	_mode_playing = playing
	_mode_ticking = not (run.mode in NON_TICKING_MODES)
	_fraction = clampf(Engine.get_physics_interpolation_fraction(), 0, 1)
	_camera = camera
	_view_xf = view_xf
	_hero_world = hero_world
	_hero_ready = false
	if camera != null:
		_cam_z = camera.global_basis.z
		_steep_ortho = camera.projection == Camera3D.PROJECTION_ORTHOGONAL and _cam_z.y >= OVERLAP_CULL_MIN_SIN

## One walker. Returns true when it is alive and overlaps the owner on screen (the caller sets _hero_overlapped).
func track(e: Dictionary, key: String) -> bool:
	var tick := _tick
	var w: Walker = _by_key.get(key)
	if w == null:
		w = Walker.new()
		w.key = key
		w.ck = (int(e.generation) << 32) | int(e.id)
		_by_key[key] = w
		_by_ck[w.ck] = w
		tracked_total += 1
	w.seen = _frame
	_active.append(w)
	var id: int = e.id
	var cold: Variant = _cold.get(key)
	if cold != null:
		# chapter_actors' own cold-corpse table drops keys it has no actor for; the crowd keeps its walkers' records.
		w.cold = cold
		_cold.erase(key)
	var dead: bool = e.hp_raw <= 0
	w.dead = dead
	var pos := _present(w, e.position, tick, _mode_playing, -1.0)
	if not dead and _recoil.has(id):
		var recoil: Dictionary = _recoil[id]
		var remaining := clampf(float(int(recoil.until) - tick) / 7.0, 0, 1)
		pos += Vector3(recoil.direction.x, 0, recoil.direction.y) * (.075 * sin(remaining * PI))
	w.pos = pos
	var frozen := tick < int(e.frozen_until)
	var playing: bool = _mode_playing and not frozen
	var hit := tick < int(_hit_until.get(id, -1))
	var direction: Vector2 = e.attack_direction if e.state in ["windup", "dash"] else e.direction
	_pose(w, e, direction, e.state == "move", dead, tick, playing, hit)
	# Tint decision (sync__chapterx): cold corpse or frozen = ice, else the hit flash of the first three ticks.
	w.icy = w.cold != null or (not dead and frozen)
	w.flash = (not w.icy) and tick < int(_hit_until.get(id, -1)) - 9
	w.xf = Transform3D(Basis(Vector3.UP, w.yaw).scaled(Vector3.ONE * w.scale_), pos)
	w.overlap = false
	if not dead and _overlaps(w):
		w.overlap = true
		return true
	return false

## Port of the walker branch of _update_pose (without the pose schedule): which clip and time, hit blend, heading, scale.
func _pose(w: Walker, e: Dictionary, direction: Vector2, moving: bool, dead: bool, tick: int, playing: bool, hit: bool) -> void:
	if not dead and tick < int(e.get("stunned_until", 0)):
		return   # shock holds the displayed pose (stun36)
	if not playing and not dead and w.has_pose:
		return
	if e.state == "recover":
		direction = e.attack_direction
	if playing and direction.length_squared() > .001:
		w.yaw = lerp_angle(w.yaw, atan2(direction.x, direction.y), 1 - exp(-_delta * 18))
	var fraction := _fraction if playing else 0.0
	var clip := "idle"
	var time_ := 0.0
	var id: int = e.id
	if dead:
		clip = "death"
		if _mode_ticking:
			w.death_age = maxf(w.death_age + _delta, float(tick - int(e.dead_tick)) / 60.0)
		time_ = minf(w.death_age, CORPSE_FINAL_AGE)
	elif e.state == "windup":
		var duration: int = e.get("definition", {}).get("windup", _run.ENEMY_DEFS[e.kind].windup)
		var left := maxf(0, float(int(e.state_until) - tick) - fraction)
		clip = "attack_slam"
		time_ = clampf(1 - left / float(maxi(1, duration)), 0, 1) * STRIKE
	elif e.state == "recover" and _attacks.has(id):
		var paid: Dictionary = _attacks[id]
		var extension := maxi(0, int(e.state_until) - int(paid.end))
		var duration: int = e.get("definition", {}).get("recover", _run.ENEMY_DEFS[e.kind].recover)
		var progress := clampf((float(tick - int(paid.tick) - extension) + fraction) / float(maxi(1, duration)), 0, 1)
		clip = "attack_slam"
		time_ = STRIKE + progress * (SWING - STRIKE)
	elif moving:
		clip = "walk"
		time_ = fposmod(w.s_phase + float((id * 37) % 101) / 101.0, 1) * WALK
	else:
		time_ = fposmod(float(tick) / 60.0 + float(id) * .113, IDLE_LENGTH)
	w.has_pose = true
	w.scale_ = .60 + float(posmod(id * 17 + int(e.generation) * 7, 4)) * .015
	w.row = Baker.clip_row(_table, clip, time_)
	w.hit_row = -1.0
	w.hit_weight = 0.0
	if playing and not dead and hit and e.state in ["move", "idle"]:
		var age := clampf(float(tick - int(_hit_until.get(id, tick)) + 12) / 12.0, 0, 1)
		w.hit_weight = .85 * sin(PI * age)
		w.hit_row = Baker.clip_row(_table, "hit", age * Spec.HIT_DURATION)

## Port of _present_position for a walker (stride 1.0). One fixed-tick interval of interpolation, never extrapolated.
func _present(w: Walker, at: Vector2, tick: int, playing: bool, fraction_override: float) -> Vector3:
	if not w.has_sample:
		w.has_sample = true
		w.s_tick = tick
		w.s_prev = at
		w.s_cur = at
		w.s_phase = 0.0
	elif w.s_tick != tick:
		var distance := at.distance_to(w.s_cur)
		var continuous := tick - w.s_tick == 1 and distance < .85
		w.s_prev = w.s_cur if continuous else at
		w.s_cur = at
		w.s_tick = tick
		if continuous and playing:
			w.s_phase = fposmod(w.s_phase + distance, 1.0)
	elif w.s_cur != at:
		w.s_prev = at
		w.s_cur = at
	if not playing:
		w.s_prev = at
	var fraction := clampf(_fraction if fraction_override < 0 else fraction_override, 0, 1)
	var shown: Vector2 = w.s_prev.lerp(w.s_cur, fraction) if playing else at
	return Vector3(shown.x, 0, shown.y)

# ---- owner overlap (port of _overlaps_hero for walkers, bones read from the baked table) -------------------------------

func _bone_world(table: PackedVector3Array, row: float, xf: Transform3D) -> Vector3:
	var r0 := clampi(int(floor(row)), 0, _bone_last)
	var r1 := mini(r0 + 1, _bone_last)
	var p: Vector3 = table[r0].lerp(table[r1], row - floorf(row))
	return _view_xf * (xf * p)

func _screen_radius(at: Vector3, radius: float) -> float:
	return _camera.unproject_position(at).distance_to(_camera.unproject_position(at + _camera.global_basis.x * radius))

func _overlaps(w: Walker) -> bool:
	if _camera == null:
		return false
	var world := _view_xf * w.pos
	var offset := world - _hero_world
	if offset.dot(_cam_z) <= .04:
		return false
	if _steep_ortho and offset.x * offset.x + offset.z * offset.z > OVERLAP_CULL_SQ:
		return false
	var a := _camera.unproject_position(_bone_world(_spine, w.row, w.xf))
	var b := _camera.unproject_position(_bone_world(_head, w.row, w.xf))
	if not _hero_ready:
		_hero_a = _camera.unproject_position(_hero_world + Vector3.UP * .32)
		_hero_b = _camera.unproject_position(_hero_world + Vector3.UP * 1.95)
		_hero_radius = _screen_radius(_hero_world + Vector3.UP, .32)
		_hero_ready = true
	var nearest := Geometry2D.get_closest_points_between_segments(a, b, _hero_a, _hero_b)
	var radius := _screen_radius(world + Vector3.UP, .36) + _hero_radius
	return nearest[0].distance_squared_to(nearest[1]) < radius * radius

# ---- end of frame ----------------------------------------------------------------------------------------------------

## overlapping = the owner is covered by a living enemy (_hero_overlapped and hp > 0); victory_alpha = the fade of sync__q20.
func end_frame(overlapping: bool, victory_alpha: float) -> void:
	if not _open:
		return
	_open = false
	var tick := _tick
	var blend := 1 - exp(-_delta * 18)
	var count := _active.size()
	if count > _capacity:
		_grow(maxi(count, _capacity * 2))
	var buf := _buf
	var n := 0
	for w in _active:
		# Owner cover fade (_sync_hero_rim): towards .4 while this body covers the owner, else back to 1.
		var target := 1.0
		if overlapping:
			if (w.overlap if not w.dead else _overlaps(w)):
				target = .4
		w.fade = lerpf(w.fade, target, blend)
		var alpha := 1.0
		if w.dead:
			alpha = 1 - clampf((w.death_age - .6) / .65, 0, 1)
		if w.cold != null:
			var record: Dictionary = w.cold
			if _mode_ticking:
				record.age = maxf(float(record.age) + maxf(0, _delta), float(tick - int(record.tick)) / 60.0)
			alpha *= 1 - smoothstep(.025, .22, float(record.age))
		var shown := alpha * w.fade * victory_alpha
		if shown < MIN_ALPHA:
			continue
		var r := Spec.TINT.r
		var g := Spec.TINT.g
		var bl := Spec.TINT.b
		if w.icy:
			r *= ICE.r
			g *= ICE.g
			bl *= ICE.b
		elif w.flash:
			r *= FLASH.r
			g *= FLASH.g
			bl *= FLASH.b
		var o := n * STRIDE
		var bs := w.xf.basis
		var org := w.xf.origin
		buf[o] = bs.x.x
		buf[o + 1] = bs.y.x
		buf[o + 2] = bs.z.x
		buf[o + 3] = org.x
		buf[o + 4] = bs.x.y
		buf[o + 5] = bs.y.y
		buf[o + 6] = bs.z.y
		buf[o + 7] = org.y
		buf[o + 8] = bs.x.z
		buf[o + 9] = bs.y.z
		buf[o + 10] = bs.z.z
		buf[o + 11] = org.z
		buf[o + 12] = r
		buf[o + 13] = g
		buf[o + 14] = bl
		buf[o + 15] = shown
		buf[o + 16] = w.row
		buf[o + 17] = w.hit_row
		buf[o + 18] = w.hit_weight
		buf[o + 19] = 0.0
		n += 1
	_buf = buf
	_mm.visible_instance_count = n
	instances_shown = n
	instances_peak = maxi(instances_peak, n)
	RenderingServer.multimesh_set_buffer(_rid, buf)
	# Walkers the core no longer lists leave the crowd (the presenter pool did the same with its actors).
	if _by_key.size() != count:
		for key in _by_key.keys():
			var gone: Walker = _by_key[key]
			if gone.seen != _frame:
				_by_key.erase(key)
				_by_ck.erase(gone.ck)
	_run = null
	_camera = null
