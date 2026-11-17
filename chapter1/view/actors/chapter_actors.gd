extends RefCounted
## Flattened by tools/dev/flatten_chain.py from chapter1/view/chapter_actors_quality42.gd.
## Methods named x__tag are the earlier layers of x; calls between them were super calls.

# ---- chapter1/view/cloister_actors.gd ----
## New actor presentation. Geometric actors are temporary until authored sheets/models arrive.
## AnimatedSprite3D/SpriteFrames/AtlasTexture: official Godot4.5 class references.
var view: Node3D
var hero: Node3D
var actors: Dictionary = {}
var sprite_definitions: Dictionary = {}
var temporary_art := true
var _body_materials: Dictionary = {}
var _hero_previous := Vector2.INF
var _hero_move_until := -1
var _cast_until := -1
var _hit_until := -1
var _textures: Dictionary={}
var _enemy_hit_until: Dictionary={}
var raw_texture_fallbacks: Array[String]=[]
var _cast_moving_until := -1
var _cast_direction := Vector2.DOWN
var _enemy_recoil: Dictionary={}
var _last_event := -1
var _cast_tick := -100
var _hero_rim: MeshInstance3D
var _hero_rim_material: ShaderMaterial
var _hero_rim_frame: Texture2D
var _hero_overlapped := false
const HERO_STRIDE := 2.15

func setup__cloister(owner_view: Node3D) -> void:
	view=owner_view
	for kind in ["hero","walker","ranged","charger","elite"]: _load_sprite(kind)
	_load_directional_casts()
	hero=_create("hero")
	view.add_child(hero)
	var marker := MeshInstance3D.new()
	var disc := TorusMesh.new();disc.inner_radius=.32;disc.outer_radius=.36;disc.rings=48;disc.ring_segments=6
	marker.mesh=disc;marker.position.y=.025;marker.scale.y=.15
	var marker_material := StandardMaterial3D.new();marker_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;marker_material.albedo_color=Color(.72,.56,.31,.48);marker_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	marker.material_override=marker_material;hero.add_child(marker)
	_setup_hero_rim()
	temporary_art=not sprite_definitions.has("hero")

func _setup_hero_rim() -> void:
	if not hero.has_meta("sprite"):return
	_hero_rim=MeshInstance3D.new();_hero_rim.name="HeroOcclusionRim"
	_hero_rim.mesh=QuadMesh.new()
	_hero_rim.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hero_rim_material=ShaderMaterial.new()
	_hero_rim_material.shader=preload("res://chapter1/view/hero_occlusion_rim.gdshader")
	_hero_rim.material_override=_hero_rim_material
	_hero_rim.visible=false;hero.add_child(_hero_rim)

func _load_directional_casts() -> void:
	var path := "res://chapter1/art/quality03/hero_cast_v01.json"
	if not sprite_definitions.has("hero") or not FileAccess.file_exists(path):return
	var doc: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not doc is Dictionary or not doc.get("frames") is Array:return
	var def: Dictionary=sprite_definitions.hero
	for direction in ["south","east","north","west"]:
		var indices: Array=doc.get("states",{}).get("cast_"+direction,doc.get("frames_by_direction",{}).get(direction,[]))
		if indices.is_empty():continue
		_add_frames(def.frames,"cast_"+direction,indices,doc,def.anchors,def.scales)
	def.directional_cast=def.frames.has_animation("cast_south") and def.frames.has_animation("cast_east") and def.frames.has_animation("cast_north") and def.frames.has_animation("cast_west")

func _load_sprite__cloister(kind: String) -> void:
	var path := "res://chapter1/art/actors/"+kind
	if not FileAccess.file_exists(path+".json"):return
	if not ResourceLoader.exists(path+".png","Texture2D") and not FileAccess.file_exists(path+".png"):return
	var doc: Variant=JSON.parse_string(FileAccess.get_file_as_string(path+".json"))
	if not doc is Dictionary: return
	var texture: Texture2D=_texture(doc.get("texture",path+".png"))
	if texture==null:return
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	if doc.get("frames") is Array and doc.get("frames_by_direction") is Dictionary:
		var anchors: Dictionary={}
		var scales: Dictionary={}
		for direction in doc.frames_by_direction:
			_add_frames(frames,"move_"+direction,doc.frames_by_direction[direction],doc,anchors,scales)
		for action in ["cast","hit","death"]:
			if not doc.get("states",{}).get(action,[]).is_empty():_add_frames(frames,action,doc.states[action],doc,anchors,scales)
		var ppm := float(doc.get("pixels_per_meter",doc.frames[0].get("pixels_per_meter",150)))
		sprite_definitions[kind]={"frames":frames,"pixel_size":1.0/ppm,"height":0.0,"anchors":anchors,"scales":scales,"directional":true}
		return
	if not doc.get("states") is Dictionary:return
	var columns := maxi(1,int(doc.get("columns",1)))
	var rows := maxi(1,int(doc.get("rows",1)))
	var cell := Vector2(float(texture.get_width())/columns,float(texture.get_height())/rows)
	for state in doc.states:
		frames.add_animation(state)
		frames.set_animation_loop(state,state!="death")
		frames.set_animation_speed(state,float(doc.get("fps",8)))
		for index in doc.states[state]:
			var atlas := AtlasTexture.new()
			atlas.atlas=texture
			atlas.region=Rect2(Vector2(int(index)%columns,int(index)/columns)*cell,cell)
			atlas.filter_clip=true
			frames.add_frame(state,atlas)
	sprite_definitions[kind]={"frames":frames,"pixel_size":1.0/float(doc.get("pixels_per_meter",250)),"height":float(doc.get("height",1.0))}

func _texture(path: String) -> Texture2D:
	if _textures.has(path):return _textures[path]
	var texture: Texture2D
	if ResourceLoader.exists(path,"Texture2D"):texture=ResourceLoader.load(path,"Texture2D") as Texture2D
	if texture==null and FileAccess.file_exists(path):
		# Unimported source-tree preview only; packaged builds must import these PNGs.
		var source := Image.load_from_file(ProjectSettings.globalize_path(path))
		if source:texture=ImageTexture.create_from_image(source);raw_texture_fallbacks.append(path)
	_textures[path]=texture
	return texture

func _add_frames(frames: SpriteFrames, animation: String, indices: Array, doc: Dictionary, anchors: Dictionary, scales: Dictionary) -> void:
	frames.add_animation(animation);frames.set_animation_loop(animation,animation.begins_with("move_"));frames.set_animation_speed(animation,8.0)
	anchors[animation]=[];scales[animation]=[]
	for index in indices:
		var record: Dictionary=doc.frames[int(index)]
		var r: Array=record.region
		var atlas := AtlasTexture.new()
		atlas.atlas=_texture(record.get("texture",doc.texture));atlas.region=Rect2(r[0],r[1],r[2],r[3]);atlas.filter_clip=true
		frames.add_frame(animation,atlas,float(record.get("duration",.125))/.125)
		var feet: Array=record.feet
		# Sprite3D offset Y points upward; feet must sit at the actor origin.
		anchors[animation].append(Vector2(float(r[2])*.5-float(feet[0]),float(feet[1])-float(r[3])*.5))
		scales[animation].append(1.0/float(record.get("pixels_per_meter",doc.pixels_per_meter)))

func consume__cloister(events: Array) -> void:
	# The owner invokes consume immediately after each fixed core step. Capture
	# both endpoints here, including ticks with no events, rather than sampling
	# only render frames (which can skip multiple ticks on a slower renderer).
	var run: Variant=view.get("run")
	if run!=null and not run.hero.is_empty():_capture_motion(run)
	for event in events:
		# Runtime events are retained across modal callbacks. Replaying a seq must
		# not restart recovery/recoil. Seq-less synthetic fixtures remain supported.
		if event.has("seq"):
			if int(event.seq)<=_last_event:continue
			_last_event=int(event.seq)
		if event.type=="cast":
			_cast_tick=int(event.tick);_cast_until=int(event.tick)+12;_cast_moving_until=int(event.tick)+5
			_cast_direction=event.get("direction",Vector2.DOWN)
		elif event.type=="hero_hit":_hit_until=int(event.tick)+6
		elif event.type=="hit":
			_enemy_hit_until[event.target_id]=int(event.tick)+12
			# Cosmetic recoil is < .08m, substantially smaller than the .30m
			# smallest core radius; physics positions and hitboxes are never changed.
			var away: Vector2=event.position-Vector2(hero.position.x,hero.position.z)
			_enemy_recoil[event.target_id]={"until":int(event.tick)+7,"direction":away.normalized()}

func _capture_motion(run: RefCounted) -> void:
	_present_position(hero,run.hero.position,run.tick,run.mode=="playing",1.0)
	for e in run.enemies.values():
		var key: String="%d:%d" % [e.generation,e.id]
		if actors.has(key):_present_position(actors[key],e.position,run.tick,run.mode=="playing",1.0)

func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _body_materials.has(key): return _body_materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color=color
	mat.roughness=.8
	_body_materials[key]=mat
	return mat

func _part(parent: Node3D, mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh=mesh
	n.material_override=_material(color)
	n.position=at
	parent.add_child(n)
	return n

func _create__cloister(kind: String) -> Node3D:
	var actor := Node3D.new()
	actor.set_meta("kind",kind)
	if sprite_definitions.has(kind):
		var def: Dictionary=sprite_definitions[kind]
		var sprite := AnimatedSprite3D.new()
		sprite.sprite_frames=def.frames
		sprite.pixel_size=def.pixel_size
		sprite.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		sprite.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sprite.position.y=def.height
		actor.add_child(sprite)
		actor.set_meta("sprite",sprite)
		return actor
	var color: Color={"hero":Color("527f85"),"walker":Color("737466"),"ranged":Color("855b43"),"charger":Color("564f47"),"elite":Color("9f7545")}[kind]
	var height := 1.9 if kind=="hero" else (2.75 if kind=="elite" else (1.35 if kind=="charger" else 1.7))
	var pivot := Node3D.new()
	actor.add_child(pivot)
	actor.set_meta("pivot",pivot)
	var torso := CapsuleMesh.new()
	torso.radius=.24 if kind=="hero" else .28
	torso.height=height*.63
	_part(pivot,torso,Vector3(0,height*.48,0),color)
	var head := SphereMesh.new()
	head.radius=height*.095
	head.height=height*.19
	head.radial_segments=8
	head.rings=4
	_part(pivot,head,Vector3(0,height*.91,0),Color("b9afa0") if kind=="hero" else Color("8a8d7c"))
	var shoulder := BoxMesh.new()
	shoulder.size=Vector3(.65 if kind!="elite" else .9,.17,.28)
	_part(pivot,shoulder,Vector3(0,height*.71,0),color.lightened(.1))
	if kind=="hero" or kind=="ranged":
		var staff := CylinderMesh.new()
		staff.top_radius=.035
		staff.bottom_radius=.04
		staff.height=height*.9
		_part(pivot,staff,Vector3(.38,height*.5,.1),Color("6f5840"))
		var jewel := SphereMesh.new()
		jewel.radius=.10
		jewel.height=.20
		_part(pivot,jewel,Vector3(.38,height*.98,.1),Color("80cad5") if kind=="hero" else Color("cb7750"))
	elif kind=="charger" or kind=="elite":
		var horns := PrismMesh.new()
		horns.size=Vector3(.7,height*.38,.3)
		_part(pivot,horns,Vector3(0,height*.92,.02),Color("b3aa89"))
	return actor

func sync__cloister(run: RefCounted, delta: float) -> void:
	if run.hero.is_empty(): return
	var active: bool=run.mode=="playing"
	hero.position=_present_position(hero,run.hero.position,run.tick,active)
	if _hero_previous!=run.hero.position:
		_hero_move_until=run.tick+2
		_hero_previous=run.hero.position
	var briefly_casting: bool=run.tick<_cast_moving_until and sprite_definitions.get("hero",{}).get("directional_cast",false)
	var hero_moving: bool=run.tick<_hero_move_until
	var cast_facing: bool=run.tick<_cast_until and sprite_definitions.get("hero",{}).get("directional_cast",false) and (not hero_moving or briefly_casting)
	_update_pose(hero,_cast_direction if cast_facing else run.hero.direction,hero_moving,run.tick<_cast_until,run.hero.hp_raw<=0,run.tick,run.mode in ["playing","defeat"],run.tick<_hit_until,briefly_casting)
	if hero.has_meta("sprite"):
		var hero_sprite: AnimatedSprite3D=hero.get_meta("sprite")
		hero_sprite.scale=Vector3.ONE*1.10
	_hero_overlapped=false
	var camera := view.get_viewport().get_camera_3d()
	for id_ in _enemy_hit_until.keys():
		if run.tick>=int(_enemy_hit_until[id_]):_enemy_hit_until.erase(id_)
	for id_ in _enemy_recoil.keys():
		if run.tick>=int(_enemy_recoil[id_].until):_enemy_recoil.erase(id_)
	var wanted: Dictionary={}
	for e in run.enemies.values():
		var key: String=frame_keys[e.id]
		wanted[key]=true
		if not actors.has(key):
			actors[key]=_create(e.kind)
			view.add_child(actors[key])
		var actor: Node3D=actors[key]
		actor.position=_present_position(actor,e.position,run.tick,active)
		var dead: bool=e.hp_raw<=0
		if not dead and _enemy_recoil.has(e.id):
			var recoil: Dictionary=_enemy_recoil[e.id]
			var remaining: float=clampf(float(int(recoil.until)-run.tick)/7.0,0,1)
			actor.position+=Vector3(recoil.direction.x,0,recoil.direction.y)*(.075*sin(remaining*PI))
		var frozen: bool=run.tick<int(e.frozen_until)
		_cur_actor=actor;_cur_entity=e
		_update_pose(actor,e.attack_direction if e.state in ["windup","dash"] else e.direction,e.state=="move",e.state=="windup",dead,run.tick,run.mode=="playing" and not frozen,run.tick<int(_enemy_hit_until.get(e.id,-1)))
		_cur_actor=null
		if not dead and _overlaps_hero(actor,camera):_hero_overlapped=true
		if actor.has_meta("sprite"):
			var sprite: AnimatedSprite3D=actor.get_meta("sprite")
			var hit_left: int=int(_enemy_hit_until.get(e.id,-1))-run.tick
			sprite.modulate=Color(.55,.88,1.05) if frozen else (Color(1.25,1.13,.97) if hit_left>9 else Color.WHITE)
		if dead:
			# Keep the body its authored size. A corpse fades after its collapse,
			# rather than shrinking into a toy-sized upright actor.
			if actor.scale!=Vector3.ONE:actor.scale=Vector3.ONE
			if actor.has_meta("sprite"):
				var corpse: AnimatedSprite3D=actor.get_meta("sprite")
				corpse.modulate.a=1.0-clampf(float(run.tick-int(e.dead_tick)-36)/39.0,0,1)
		elif actor.scale!=Vector3.ONE:actor.scale=Vector3.ONE
	for key in actors.keys():
		if not wanted.has(key):
			actors[key].queue_free()
			actors.erase(key)
	_sync_hero_rim(camera,_hero_overlapped and run.hero.hp_raw>0)

func _present_position(actor: Node3D, at: Vector2, tick: int, playing: bool, fraction_override: float=-1.0) -> Vector3:
	# One fixed-tick interval of visual interpolation. Never extrapolate a hitbox.
	# https://docs.godotengine.org/en/4.5/classes/class_engine.html#class-engine-method-get-physics-interpolation-fraction
	var sample: Dictionary=actor.get_meta("motion_sample",{})
	var created := sample.is_empty()
	if created:sample={"tick":tick,"previous":at,"current":at,"phase":0.0}
	elif int(sample.tick)!=tick:
		var distance: float=at.distance_to(sample.current)
		var continuous: bool=tick-int(sample.tick)==1 and distance<.85
		sample.previous=sample.current if continuous else at
		sample.current=at;sample.tick=tick
		if continuous and playing:
			var stride: float=HERO_STRIDE if actor==hero else (1.45 if actor.get_meta("kind")=="elite" else 1.0)
			sample.phase=fposmod(float(sample.phase)+distance/stride,1.0)
	elif sample.current!=at:
		# Same-tick fixture changes and retry/teleports snap, not slide.
		sample.previous=at;sample.current=at
	if not playing:sample.previous=at
	if created:actor.set_meta("motion_sample",sample)
	var fraction := clampf(Engine.get_physics_interpolation_fraction() if fraction_override<0 else fraction_override,0,1)
	var shown: Vector2=sample.previous.lerp(sample.current,fraction) if playing else at
	return Vector3(shown.x,0,shown.y)

func _overlaps_hero__cloister(actor: Node3D, camera: Camera3D) -> bool:
	# Conservative projected current-frame bounds, not a world-distance trigger.
	# Both sprites remain normal depth-tested. Only a nearer living enemy whose
	# actual displayed frame intersects the hero frame enables the separate rim.
	if camera==null or not actor.has_meta("sprite") or not hero.has_meta("sprite"):return false
	if (actor.global_position-hero.global_position).dot(camera.global_basis.z)<=.04:return false
	return _projected_frame(actor,camera).intersects(_projected_frame(hero,camera))

func _projected_frame(actor: Node3D, camera: Camera3D) -> Rect2:
	# https://docs.godotengine.org/en/4.5/classes/class_camera3d.html#class-camera3d-method-unproject-position
	var sprite: AnimatedSprite3D=actor.get_meta("sprite")
	var texture: Texture2D=sprite.sprite_frames.get_frame_texture(sprite.animation,sprite.frame)
	var extent := texture.get_size()*.5
	var unit := sprite.pixel_size*sprite.scale.x
	var center := sprite.global_position+camera.global_basis.x*sprite.offset.x*unit+camera.global_basis.y*sprite.offset.y*unit
	var a := camera.unproject_position(center-camera.global_basis.x*extent.x*unit-camera.global_basis.y*extent.y*unit)
	var b := camera.unproject_position(center+camera.global_basis.x*extent.x*unit+camera.global_basis.y*extent.y*unit)
	return Rect2(a,Vector2.ZERO).expand(b).abs()

func _sync_hero_rim__cloister(camera: Camera3D, overlapping: bool) -> void:
	if _hero_rim==null:return
	_hero_rim.visible=overlapping
	if not overlapping:return
	var sprite: AnimatedSprite3D=hero.get_meta("sprite")
	var frame: Texture2D=sprite.sprite_frames.get_frame_texture(sprite.animation,sprite.frame)
	if frame!=_hero_rim_frame:
		_hero_rim_frame=frame
		var atlas := frame as AtlasTexture
		if atlas:
			var dimensions := Vector2(atlas.atlas.get_width(),atlas.atlas.get_height())
			_hero_rim_material.set_shader_parameter("source_tex",atlas.atlas)
			_hero_rim_material.set_shader_parameter("uv_min",atlas.region.position/dimensions)
			_hero_rim_material.set_shader_parameter("uv_size",atlas.region.size/dimensions)
			_hero_rim_material.set_shader_parameter("local_texel",Vector2.ONE/atlas.region.size)
			(_hero_rim.mesh as QuadMesh).size=atlas.region.size*sprite.pixel_size*1.10
	_hero_rim.position=sprite.position+camera.global_basis.x*sprite.offset.x*sprite.pixel_size*1.10+camera.global_basis.y*sprite.offset.y*sprite.pixel_size*1.10
	_hero_rim_material.set_shader_parameter("strength",1.0)

func _update_pose__cloister(actor: Node3D, direction: Vector2, moving: bool, casting: bool, dead: bool, tick: int, playing: bool, hit: bool=false, brief_cast: bool=false) -> void:
	if actor.has_meta("sprite"):
		var sprite: AnimatedSprite3D=actor.get_meta("sprite")
		var def: Dictionary=sprite_definitions[actor.get_meta("kind")]
		var state := "death" if dead else ("cast" if casting else ("move" if moving else "idle"))
		if def.get("directional",false):
			var camera := view.get_viewport().get_camera_3d()
			var right := Vector2(camera.global_basis.x.x,camera.global_basis.x.z).normalized()
			var forward := Vector2(-camera.global_basis.z.x,-camera.global_basis.z.z).normalized()
			var screen := Vector2(direction.dot(right),-direction.dot(forward))
			var facing := ("east" if screen.x>0 else "west") if absf(screen.x)>absf(screen.y) else ("south" if screen.y>0 else "north")
			state="move_"+facing
			# Authored action sheet currently faces south. Use it while planted;
			# moving retains directional gait rather than snapping orientation.
			if dead and sprite.sprite_frames.has_animation("death"):state="death"
			# Legacy hurt/attack strips face south. Preserve a north/east/west
			# silhouette instead of snapping every struck traveler toward camera.
			# Flash/recoil still conveys those hits; authored directional casts win.
			elif hit and facing=="south" and sprite.sprite_frames.has_animation("hit"):state="hit"
			elif casting and (not moving or brief_cast):
				if def.get("directional_cast",false) and sprite.sprite_frames.has_animation("cast_"+facing):state="cast_"+facing
				elif not moving and facing=="south" and sprite.sprite_frames.has_animation("cast"):state="cast"
		if not sprite.sprite_frames.has_animation(state): state="idle"
		if sprite.sprite_frames.has_animation(state) and sprite.animation!=state: sprite.play(state)
		sprite.speed_scale=1.0 if playing and (moving or state in ["cast","hit","death"] or state.begins_with("cast_")) else 0.0
		if actor==hero and state.begins_with("cast_"):
			# A cast event is a release, not a future windup. Show release now,
			# then recovery; don't animate anticipation after the shot has left.
			sprite.frame=mini(2 if tick-_cast_tick<5 else 3,sprite.sprite_frames.get_frame_count(state)-1);sprite.speed_scale=0.0
		elif state.begins_with("move_") and moving:
			# Preserve the existing four-frame gait through heading changes and
			# short casts. No new leg contacts or interpolated art are invented.
			# https://docs.godotengine.org/en/4.5/classes/class_animatedsprite3d.html#class-animatedsprite3d-method-set-frame-and-progress
			var phase: float=float(actor.get_meta("motion_sample",{}).get("phase",0.0))*sprite.sprite_frames.get_frame_count(state)
			sprite.set_frame_and_progress(int(phase)%sprite.sprite_frames.get_frame_count(state),fposmod(phase,1.0));sprite.speed_scale=0.0
		if def.get("directional",false):
			if not moving and state.begins_with("move_"):sprite.frame=0
			sprite.offset=def.anchors[state][sprite.frame]
			sprite.pixel_size=def.scales[state][sprite.frame]
		else:sprite.flip_h=direction.x<-.1
	else:
		var pivot: Node3D=actor.get_meta("pivot")
		actor.rotation.y=atan2(direction.x,direction.y)
		pivot.rotation.x=PI*.47 if dead else (sin(float(tick)*.24)*.045 if moving else -.06 if casting else 0.0)
		pivot.position.y=absf(sin(float(tick)*.22))*.045 if moving and not dead else 0.0

func reset__cloister() -> void:
	for actor in actors.values(): actor.queue_free()
	actors.clear()
	_hero_previous=Vector2.INF;_hero_move_until=-1
	_cast_until=-1;_hit_until=-1
	_enemy_hit_until.clear()
	_cast_moving_until=-1;_cast_direction=Vector2.DOWN;_enemy_recoil.clear()
	_last_event=-1;_cast_tick=-100;_hero_overlapped=false;_hero_rim_frame=null
	if hero.has_meta("motion_sample"):hero.remove_meta("motion_sample")
	if _hero_rim:_hero_rim.visible=false

# ---- chapter1/view/chapter_actors.gd ----
## Tiny owner chevron stays above crowds; actor depth/physics remain unchanged.
## Label3D no_depth_test / render_priority: official Godot4.5 class reference.
var owner_mark: Label3D
func setup__chapter(owner_view: Node3D) -> void:
	setup__cloister(owner_view)
	owner_mark=Label3D.new();owner_mark.text="◇";owner_mark.font_size=32;owner_mark.pixel_size=.009
	owner_mark.outline_size=12;owner_mark.outline_modulate=Color(.025,.035,.045,.96)
	owner_mark.modulate=Color("efcd84");owner_mark.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	owner_mark.no_depth_test=true;owner_mark.render_priority=110;owner_mark.outline_render_priority=109
	owner_mark.position=Vector3(0,2.5,0);hero.add_child(owner_mark)
func sync__chapter(run: RefCounted,delta: float) -> void:
	sync__cloister(run,delta)
	owner_mark.visible=not run.hero.is_empty() and run.hero.hp_raw>0

# ---- chapter1/view/rigged_hero_actors.gd ----
## Research presenter: actual skeleton, distance gait and upper-body release.
## No physics/hitbox/skill/loot changes. Source09 sprite presenter is preserved.
const MODEL := "res://chapter1/art/rigged_mage/v01/mage_animated.glb"
const Staff=preload("res://chapter1/view/ember_staff_visual.gd")
var rig_model: Node3D
const HERO_MODEL_SCALE := 1.32
const HERO_ELEMENT_COLORS := {"chapter1.skill.ember":Color("ff943d"),"chapter1.skill.frost":Color("9ce7ef"),"chapter1.skill.arc":Color("8fa6ff")}
var _hero_materials: Array[StandardMaterial3D]=[]
var _hero_disc_material: StandardMaterial3D
var _hero_ring_material: StandardMaterial3D
var _hero_element_key := ""
var rig_player: AnimationPlayer
var rig_skeleton: Skeleton3D
var _upper: Dictionary={}
var _render_delta := 0.0
var _render_playing := false
var _phase := 0.0
var _idle_age := 0.0
var _death_age := 0.0
var _was_dead := false
var _hero_rect := Rect2()
var _bounds_frame := -1
var _pose_samples := 0
var _staff: Node3D
var _hand := -1
var _finger := -1
var _grip_basis := Basis.IDENTITY
var _grip_ready := false

func _load_sprite(kind: String) -> void:
	if kind!="hero":_load_sprite__cloister(kind)

func setup__rigged(owner_view: Node3D) -> void:
	setup__chapter(owner_view)
	_setup_artist_lights()
	_staff=Staff.new();hero.add_child(_staff)
	_setup_hero_ground_ring()
	_hand=rig_skeleton.find_bone("hand_cr_r");_finger=rig_skeleton.find_bone("finger_middle.01.r")
	_sample("idle",0)
	temporary_art=false
	print("RIGGED_HERO_READY ",JSON.stringify({"source":MODEL,"bones":rig_skeleton.get_bone_count(),"clips":Array(rig_player.get_animation_list()),"upper_body_bones":_upper.size(),"scope":"Research comparison, not final motion/art approval"}))

func _setup_artist_lights() -> void:
	# Sprite art carries baked light. Give the live mesh a matched key/fill on
	# a separate visual layer, without adding a moving light patch to terrain.
	for pair in [[Vector3(-42,-35,0),Color("eddbc4"),1.6],[Vector3(-28,145,0),Color("7faad8"),.85]]:
		var light := DirectionalLight3D.new();light.rotation_degrees=pair[0];light.light_color=pair[1];light.light_energy=pair[2];light.light_cull_mask=2;light.shadow_enabled=false
		view.add_child(light)

func _create__rigged(kind: String) -> Node3D:
	if kind!="hero":
		var enemy := _create__cloister(kind)
		if enemy.has_meta("sprite"):
			var sprite: AnimatedSprite3D=enemy.get_meta("sprite")
			# Hidden hero fragments need the enemy's opaque pixels in scene depth.
			# Preserve smooth fractional-alpha edges, unlike a hard cutout.
			sprite.alpha_cut=SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		return enemy
	var actor := Node3D.new();actor.set_meta("kind","hero")
	var scene := load(MODEL) as PackedScene
	if scene==null:push_error("Rigged hero import missing");return actor
	rig_model=scene.instantiate();rig_model.scale=Vector3.ONE*HERO_MODEL_SCALE;actor.add_child(rig_model)
	rig_player=rig_model.find_child("AnimationPlayer",true,false)
	rig_skeleton=rig_model.find_child("Skeleton3D",true,false)
	if rig_player==null or rig_skeleton==null:push_error("Rigged hero skeleton/animations missing");return actor
	rig_player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for i in rig_skeleton.get_bone_count():
		var name_: String=rig_skeleton.get_bone_name(i)
		if name_.begins_with("spine_") or name_.begins_with("neck_") or name_.begins_with("head_") or name_.contains("arm_") or name_.begins_with("shoulder_") or name_.begins_with("hand_") or name_.begins_with("finger_") or name_.begins_with("thumb."):_upper[i]=true
	_setup_materials(rig_model)
	return actor

func _setup_materials(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var original: MeshInstance3D=child
			original.layers=2
			for surface in original.mesh.get_surface_count():
				var source := original.get_active_material(surface) as StandardMaterial3D
				if source:
					var material := source.duplicate() as StandardMaterial3D
					material.albedo_color=Color(1.35,1.25,1.18);material.rim_enabled=true;material.rim=.28;material.rim_tint=.25
					material.emission_enabled=true;material.emission_texture=source.albedo_texture
					material.emission=Color(.20,.23,.26);material.emission_energy_multiplier=.45
					original.set_surface_override_material(surface,material);_hero_materials.append(material)
		else:_setup_materials(child)

# Hero identity: element-coloured body tint, rim and ground disc. Presentation only.
func _setup_hero_ground_ring() -> void:
	var disc := MeshInstance3D.new();disc.name="HeroElementDisc"
	var cyl := CylinderMesh.new();cyl.top_radius=.68;cyl.bottom_radius=.68;cyl.height=.01;cyl.radial_segments=48;cyl.rings=1
	disc.mesh=cyl;disc.position.y=.035;disc.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hero_disc_material=StandardMaterial3D.new();_hero_disc_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;_hero_disc_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	_hero_disc_material.albedo_color=Color(.6,.9,1,.3);disc.material_override=_hero_disc_material;hero.add_child(disc)
	var ring := MeshInstance3D.new();ring.name="HeroElementRing"
	var torus := TorusMesh.new();torus.inner_radius=.55;torus.outer_radius=.62;torus.rings=48;torus.ring_segments=6
	ring.mesh=torus;ring.scale.y=.1;ring.position.y=.04;ring.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hero_ring_material=StandardMaterial3D.new();_hero_ring_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;_hero_ring_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	# Thin ring stays readable when a nearer enemy sprite stands on the hero (crowd case).
	_hero_ring_material.no_depth_test=true;_hero_ring_material.render_priority=20
	_hero_ring_material.albedo_color=Color(.6,.9,1,.8);ring.material_override=_hero_ring_material;hero.add_child(ring)

func _apply_hero_element(primary: String) -> void:
	if primary==_hero_element_key or _hero_disc_material==null:return
	_hero_element_key=primary
	var element: Color=HERO_ELEMENT_COLORS.get(primary,HERO_ELEMENT_COLORS["chapter1.skill.frost"])
	# The robe texture stays as the dark base; the element colour leans into albedo,
	# emission and a rim that follows the albedo tint (rim_tint=1).
	# Art review 20261116 (order 2): the body is NOT tinted by the element any more (it camouflaged
	# the hero inside its own effects). Same dark base for all three; element colour stays in the rim.
	# rim_tint=1 takes the rim colour from albedo, so a small lean (.22) is what lets the rim carry the element.
	var lean := Color(1.15,1.12,1.08).lerp(element*1.3,.3)
	for material in _hero_materials:
		material.albedo_color=lean;material.rim_enabled=true;material.rim=1.0;material.rim_tint=1.0
		material.emission=element*.15;material.emission_energy_multiplier=.6
	# Disc: dark backing slightly wider than the ring (acts as the thin dark outline of the ring).
	_hero_disc_material.albedo_color=Color(element.r*.12,element.g*.12,element.b*.12,.5)
	_hero_ring_material.albedo_color=Color(element.r,element.g,element.b,.85)

func sync__rigged(run: RefCounted,delta: float) -> void:
	_render_delta=delta;_render_playing=run.mode=="playing"
	sync__chapter(run,delta)
	if _staff!=null and _hand>=0 and _finger>=0:
		var hand := rig_skeleton.global_transform*rig_skeleton.get_bone_global_pose(_hand)
		var finger := rig_skeleton.global_transform*rig_skeleton.get_bone_global_pose(_finger)
		_staff.global_position=hand.origin.lerp(finger.origin,.5)
		if not _grip_ready:_grip_basis=hand.basis.orthonormalized().inverse()*hero.global_basis;_grip_ready=true
		if run.hero.hp_raw<=0:_staff.global_basis=(hand.basis.orthonormalized()*_grip_basis).orthonormalized()
		else:_staff.basis=Basis.from_euler(Vector3(deg_to_rad(-3+sin(_phase*TAU)*4),0,deg_to_rad(5)))
		var bottom: Vector3=_staff.global_transform*Vector3(0,-1.05,0)
		if bottom.y<.025:_staff.global_position.y+=.025-bottom.y
		var primary: Variant=run.growth.snapshot().get("primary","")
		var color: Color={"chapter1.skill.ember":Color("ed913e"),"chapter1.skill.frost":Color("89dbe6"),"chapter1.skill.arc":Color("a3b8ef")}.get(primary,Color("89dbe6"))
		_apply_hero_element(String(primary))
		_staff.set_element(color,clampf(1.0-float(run.tick-_cast_tick)/8.0,0,1))

func _sample(clip: String,time_: float) -> Array[Transform3D]:
	rig_player.play(clip,0.0)
	rig_player.seek(time_,true)
	rig_player.advance(0)
	var values: Array[Transform3D]=[]
	for i in rig_skeleton.get_bone_count():values.append(rig_skeleton.get_bone_pose(i))
	_pose_samples+=1
	return values

func _write_pose(values: Array[Transform3D]) -> void:
	for i in values.size():rig_skeleton.set_bone_pose(i,values[i])

func _update_pose__rigged(actor: Node3D,direction: Vector2,moving: bool,casting: bool,dead: bool,tick: int,playing: bool,hit: bool=false,brief_cast: bool=false) -> void:
	if actor!=hero:_update_pose__cloister(actor,direction,moving,casting,dead,tick,playing,hit,brief_cast);return
	if rig_player==null:return
	if dead:
		if not _was_dead:_death_age=0
		_was_dead=true;_death_age=minf(.9,_death_age+_render_delta)
		_sample("death",_death_age);return
	_was_dead=false
	if _render_playing:
		_idle_age+=_render_delta
		var facing := direction
		if not moving and casting:facing=_cast_direction
		if facing.length_squared()>.001:actor.rotation.y=lerp_angle(actor.rotation.y,atan2(facing.x,facing.y),1.0-exp(-_render_delta*20))
		if moving:
			var sample: Dictionary=actor.get_meta("motion_sample",{})
			var fraction := clampf(Engine.get_physics_interpolation_fraction(),0,1)
			var stride_step: float=Vector2(sample.get("previous",Vector2.ZERO)).distance_to(sample.get("current",Vector2.ZERO))/HERO_STRIDE
			_phase=fposmod(float(sample.get("phase",0.0))-(1.0-fraction)*stride_step,1)
	var poses := _sample("run" if moving else "idle",_phase*.6 if moving else fposmod(_idle_age,1.2))
	if casting:
		var age := clampf(float(tick-_cast_tick)/60.0,0,.2)
		var released := _sample("cast",.15+age*2.25)
		var weight := 1.0-smoothstep(.04,.2,age)
		for i in poses.size():
			if _upper.has(i):poses[i]=poses[i].interpolate_with(released[i],weight)
	if hit:
		var age := clampf(float(tick-(_hit_until-6))/60.0,0,.1)
		var struck := _sample("hit",age*3)
		for i in poses.size():
			if _upper.has(i):poses[i]=poses[i].interpolate_with(struck[i],.55*sin(PI*age/.1))
	_write_pose(poses)

func _overlaps_hero__rigged(actor: Node3D,camera: Camera3D) -> bool:
	if camera==null or not actor.has_meta("sprite"):return false
	if (actor.global_position-hero.global_position).dot(camera.global_basis.z)<=.04:return false
	if _bounds_frame!=Engine.get_process_frames():
		_bounds_frame=Engine.get_process_frames()
		var first := true
		for x in [-.85,.85]:
			for y in [0.0,2.35]:
				for z in [-.7,.7]:
					var screen := camera.unproject_position(hero.global_transform*Vector3(x,y,z))
					if first:_hero_rect=Rect2(screen,Vector2.ZERO);first=false
					else:_hero_rect=_hero_rect.expand(screen)
	return _hero_rect.intersects(_projected_frame(actor,camera))

func reset__rigged() -> void:
	reset__cloister();_phase=0;_idle_age=0;_death_age=0;_was_dead=false;_bounds_frame=-1;_grip_ready=false

# ---- chapter1/view/chapter_actors_quality12.gd ----
## Research integration: actual final-boss rig. Chapter11 remains archived.
## Source timing is explicitly mapped onto paid windup/release; never changes AI.
const WARDEN := "res://chapter1/art/chained_warden/v01/chained_demon_animated.glb"
const RELEASE_TICKS := 8
# Authored release t=.22,25 keys starting at Blender frame1,40FPS.
# The exported clip includes the leading first-frame hold: (1+24*.22)/40.
const RELEASE_TIME := .157
var _entities: Dictionary={}
var _paid_attacks: Dictionary={}
var _warden_event := -1
var _warden_phase := 1

func _create__q12(kind: String) -> Node3D:
	if kind!="elite" or view.run.zone!=2:return _create__rigged(kind)
	var actor := Node3D.new();actor.set_meta("kind",kind)
	var model=load(WARDEN).instantiate();model.scale=Vector3.ONE*1.15;actor.add_child(model)
	var player: AnimationPlayer=model.find_child("AnimationPlayer",true,false)
	var skeleton: Skeleton3D=model.find_child("Skeleton3D",true,false)
	player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var materials: Array[StandardMaterial3D]=[]
	_warden_materials(model,materials)
	actor.set_meta("enemy_rig",{"model":model,"player":player,"skeleton":skeleton,"materials":materials,"owner_fade":1.0})
	player.play("idle",0);player.seek(0,true);player.advance(0)
	print("CHAPTER1_WARDEN_RIG ",JSON.stringify({"bones":skeleton.get_bone_count(),"clips":Array(player.get_animation_list()),"source":WARDEN,"scope":"Own animations on Mophs CC-BY3.0 model; quality comparison candidate"}))
	return actor

func _warden_materials(node: Node,materials: Array[StandardMaterial3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			child.layers=2
			for surface in child.mesh.get_surface_count():
				var original=child.get_active_material(surface) as StandardMaterial3D
				if original:
					var material=original.duplicate() as StandardMaterial3D
					material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
					var tint := Color(.52,.55,.51)
					if original.resource_name.begins_with("WardenMask"):tint=Color(.74,.78,.81)
					elif original.resource_name.begins_with("WardenChain"):tint=Color(.56,.60,.63)
					material.albedo_color=tint;material.set_meta("warden_tint",tint)
					material.rim_enabled=true;material.rim=.24;material.rim_tint=.18
					child.set_surface_override_material(surface,material);materials.append(material)
		else:_warden_materials(child,materials)

func consume__q12(events: Array) -> void:
	for event in events:
		if int(event.seq)<=_warden_event:continue
		_warden_event=int(event.seq)
		if event.type=="enemy_attack" and event.kind=="elite":
			var entity: Dictionary=view.run.enemies.get(event.target_id,{})
			_paid_attacks[event.target_id]={"tick":int(event.tick),"kind":event.attack_kind,"recover_end":int(entity.get("state_until",event.tick))}
		elif event.type=="boss_phase":_warden_phase=int(event.phase)
	consume__cloister(events)

func sync__q12(run: RefCounted,delta: float) -> void:
	sync__rigged(run,delta)

# Per-frame enemy table, filled once at the top of sync(): enemy id -> "generation:id".
# Presentation-owned; nothing is written into the core dictionaries.
var frame_keys: Dictionary={}
# Enemy whose pose is being updated by sync__cloister (same dictionary as _entities[key]).
var _cur_actor: Node3D=null
var _cur_entity: Dictionary={}

func _entity(actor: Node3D) -> Dictionary:
	if actor==_cur_actor:return _cur_entity
	if actor==hero:return {}
	var key: String=actor.get_meta("entity_key","")
	if key.is_empty():
		for candidate in actors:
			if actors[candidate]==actor:key=candidate;actor.set_meta("entity_key",key);break
	return _entities.get(key,{})

func _update_pose__q12(actor: Node3D,direction: Vector2,moving: bool,casting: bool,dead: bool,tick: int,playing: bool,hit: bool=false,brief_cast: bool=false) -> void:
	if not actor.has_meta("enemy_rig"):_update_pose__rigged(actor,direction,moving,casting,dead,tick,playing,hit,brief_cast);return
	var state: Dictionary=actor.get_meta("enemy_rig");var entity := _entity(actor)
	if entity.is_empty():return
	if actor.get_meta("warden_pose_ready",false) and not playing and not dead:return
	var player: AnimationPlayer=state.player
	var clip := "idle";var time_ := 0.0
	var fraction := clampf(Engine.get_physics_interpolation_fraction(),0,1) if playing else 0.0
	if playing and direction.length_squared()>.001:actor.rotation.y=lerp_angle(actor.rotation.y,atan2(direction.x,direction.y),1-exp(-_render_delta*18))
	if dead:
		clip="death"
		var age: float=actor.get_meta("warden_death_age",maxf(0,float(tick-int(entity.dead_tick))/60.0))
		if view.run.mode not in ["paused","choice","equipment"]:age+=_render_delta
		actor.set_meta("warden_death_age",age);time_=age
		if age>=player.get_animation(clip).length and not actor.get_meta("warden_death_reported",false):
			actor.set_meta("warden_death_reported",true)
			print("CHAPTER1_WARDEN_DEATH_POSE ",JSON.stringify({"mode":view.run.mode,"core_tick":tick,"dead_tick":entity.dead_tick,"visual_age":age,"clip_length":player.get_animation(clip).length,"scope":"Actual model animation progressed after death; not art approval"}))
	elif entity.state=="windup":
		var kind := "fan" if entity.attack_kind=="fan" else "slam"
		var left := maxf(0,float(int(entity.state_until)-tick)-fraction)
		if left>RELEASE_TICKS:
			clip="windup_"+kind
			var progress := clampf(1.0-(left-RELEASE_TICKS)/float(maxi(1,int(entity.definition.windup)-RELEASE_TICKS)),0,1)
			time_=progress*player.get_animation(clip).length
		else:clip=kind;time_=RELEASE_TIME*(1-left/RELEASE_TICKS)
	elif entity.state=="recover" and _paid_attacks.has(entity.id):
		var paid: Dictionary=_paid_attacks[entity.id]
		clip="fan" if paid.kind=="fan" else "slam"
		# The core extends recovery's end on each frozen tick. Remove that
		# extension so thaw resumes the held pose instead of skipping recovery.
		var frozen_ticks := maxi(0,int(entity.state_until)-int(paid.recover_end))
		time_=RELEASE_TIME+maxf(0,float(tick-int(paid.tick)-frozen_ticks)+fraction)/60.0
		if time_>=player.get_animation(clip).length:clip="idle";time_=fposmod(float(tick)/60.0,player.get_animation(clip).length)
	elif moving:
		clip="walk"
		var sample: Dictionary=actor.get_meta("motion_sample",{})
		var stride_step: float=Vector2(sample.get("previous",Vector2.ZERO)).distance_to(sample.get("current",Vector2.ZERO))/1.45
		var phase := fposmod(float(sample.get("phase",0.0))-(1-fraction)*stride_step,1)
		time_=phase*player.get_animation(clip).length
	else:time_=fposmod(float(tick)/60.0,player.get_animation("idle").length)
	if not dead and actor.has_meta("warden_death_age"):
		actor.remove_meta("warden_death_age");actor.remove_meta("warden_death_reported")
	player.play(clip,0);player.seek(minf(time_,player.get_animation(clip).length),true);player.advance(0)
	if hit:
		var hit_age := float(tick-(int(_enemy_hit_until.get(entity.id,-100))-12))
		if hit_age>=0 and hit_age<6:
			var rig: Skeleton3D=state.skeleton
			for name_ in ["Spine2","Head"]:
				var bone := rig.find_bone(name_)
				if bone>=0:rig.set_bone_pose_rotation(bone,rig.get_bone_pose_rotation(bone)*Quaternion(Vector3.RIGHT,-.06*sin(PI*hit_age/6)))
	actor.set_meta("warden_pose",{"clip":clip,"time":time_,"tick":tick,"state":entity.state})
	actor.set_meta("warden_pose_ready",true)

func _overlaps_hero__q12(actor: Node3D,camera: Camera3D) -> bool:
	if not actor.has_meta("enemy_rig"):return _overlaps_hero__rigged(actor,camera)
	if camera==null or (actor.global_position-hero.global_position).dot(camera.global_basis.z)<=.04:return false
	# A large static box faded the whole boss even when the empty corner alone
	# touched the owner. Use current posed body/arm capsules in screen space.
	var rig: Skeleton3D=actor.get_meta("enemy_rig").skeleton
	var body := [_bone_point(rig,"Spine1"),_bone_point(rig,"Spine3")]
	var head := _bone_point(rig,"Head")
	var capsules: Array=[{"a":body[0],"b":body[1]+Vector3.UP*.22,"r":.52},{"a":head+Vector3.UP*.12,"b":head+Vector3.UP*.82,"r":.34}]
	for side in ["L","R"]:
		var upper := _bone_point(rig,"Arm."+side);var elbow := _bone_point(rig,"Forearm."+side)
		var palm := _bone_point(rig,"RingFinger."+side);var claw := _bone_point(rig,"MiddleFinger."+side+".003")
		capsules.append({"a":upper,"b":elbow,"r":.23});capsules.append({"a":elbow,"b":palm,"r":.22});capsules.append({"a":palm,"b":claw,"r":.22})
	var hero_a := camera.unproject_position(hero.global_position+Vector3.UP*.32)
	var hero_b := camera.unproject_position(hero.global_position+Vector3.UP*1.95)
	var hero_radius := _screen_radius(camera,hero.global_position+Vector3.UP, .32)
	for capsule in capsules:
		var a := camera.unproject_position(capsule.a);var b := camera.unproject_position(capsule.b)
		var nearest := Geometry2D.get_closest_points_between_segments(hero_a,hero_b,a,b)
		var radius := _screen_radius(camera,capsule.a,capsule.r)+hero_radius
		if nearest[0].distance_squared_to(nearest[1])<radius*radius:return true
	return false

func _bone_point(rig: Skeleton3D,name_: String) -> Vector3:
	return (rig.global_transform*rig.get_bone_global_pose(rig.find_bone(name_))).origin

func _screen_radius(camera: Camera3D,at: Vector3,radius: float) -> float:
	return camera.unproject_position(at).distance_to(camera.unproject_position(at+camera.global_basis.x*radius))

func reset__q12() -> void:
	reset__rigged();_entities.clear();_paid_attacks.clear();_warden_event=-1;_warden_phase=1

# ---- chapter1/view/chapter_actors_quality16.gd ----
## Presentation only: cold-killed ordinary bodies yield to the .48s ice shards.
const COLD_CORPSE_SECONDS := .22
var _cold_corpses: Dictionary={}
var _cold_event := -1

func consume__q16(events: Array) -> void:
	for event in events:
		if int(event.get("seq",-1))<=_cold_event:continue
		_cold_event=int(event.seq)
		if event.type!="death" or event.get("skill_id","")!="chapter1.skill.frost":continue
		var entity: Dictionary=view.run.enemies.get(event.target_id,{})
		if entity.is_empty() or entity.hp_raw>0 or entity.elite or entity.kind=="elite":continue
		var key := "%d:%d"%[entity.generation,entity.id]
		_cold_corpses[key]={"age":0.0,"tick":int(entity.dead_tick)}
	consume__q12(events)

func sync__q16(run: RefCounted,delta: float) -> void:
	# Parent recomputes sprite tint/owner fade from source every sync. Apply once
	# afterwards, never multiply the preceding frame's cold tint.
	sync__q12(run,delta)
	for key in _cold_corpses.keys():
		if not actors.has(key):_cold_corpses.erase(key);continue
		var actor: Node3D=actors[key]
		if not actor.has_meta("sprite"):continue
		var record: Dictionary=_cold_corpses[key]
		if run.mode not in ["paused","choice","inventory","equipment"]:
			record.age=maxf(float(record.age)+maxf(0,delta),float(run.tick-int(record.tick))/60.0)
		var sprite: AnimatedSprite3D=actor.get_meta("sprite")
		var tint := Color(.48,.86,1.16)
		tint.a=sprite.modulate.a*(1.0-smoothstep(.025,COLD_CORPSE_SECONDS,float(record.age)))
		sprite.modulate=tint

func reset__q16() -> void:
	reset__q12();_cold_corpses.clear();_cold_event=-1

# ---- chapter1/view/chapter_actors_quality17.gd ----
## Reuse authored frames with distinct distance phases and actual windup timing.
## Sprite lean is bounded; root positions, hurtboxes, and the Warden rig stay intact.
func _update_pose__q17(actor: Node3D,direction: Vector2,moving: bool,casting: bool,dead: bool,tick: int,playing: bool,hit: bool=false,brief_cast: bool=false) -> void:
	if actor==hero or actor.has_meta("enemy_rig") or not actor.has_meta("sprite"):
		_update_pose__q12(actor,direction,moving,casting,dead,tick,playing,hit,brief_cast);return
	var entity := _entity(actor)
	var sample: Dictionary=actor.get_meta("motion_sample",{})
	var original_phase := float(sample.get("phase",0.0))
	if not entity.is_empty():
		sample.phase=fposmod(original_phase+float((int(entity.id)*37)%101)/101.0,1.0);actor.set_meta("motion_sample",sample)
	_update_pose__q12(actor,direction,moving,casting,dead,tick,playing,hit,brief_cast)
	if not sample.is_empty():sample.phase=original_phase;actor.set_meta("motion_sample",sample)
	var sprite: AnimatedSprite3D=actor.get_meta("sprite")
	if dead:sprite.rotation.z=0;return
	if not playing or entity.is_empty():return
	var camera := view.get_viewport().get_camera_3d()
	var side := direction.dot(Vector2(camera.global_basis.x.x,camera.global_basis.x.z).normalized())
	var lean := 0.0
	if entity.state=="windup":
		var length_: int=entity.get("definition",{}).get("windup",36)
		var progress := 1.0-clampf(float(int(entity.state_until)-tick)/maxf(1,length_),0,1)
		lean=-side*.085*sin(progress*PI*.5)
	elif entity.state=="dash":lean=side*.10
	elif moving:lean=side*.025*sin(original_phase*TAU)
	sprite.rotation.z=lerpf(sprite.rotation.z,lean,1.0-exp(-_render_delta*22))

# ---- chapter1/view/chapter_actors_demon19.gd ----
## Independent creature-family study on the already licensed Mophs model.
## Ordinary bodies omit chain geometry; boss keeps its original mesh/presenter.
var _body_cache: Dictionary={}
var _demon19_attacks: Dictionary={}
var _demon19_event := -1
var motion19_samples := 0
func _create__chapterx(kind: String) -> Node3D:
	if kind not in ["walker","elite"] or (kind=="elite" and view.run.zone==2):return _create__q12(kind)
	var actor := Node3D.new();actor.set_meta("kind",kind)
	var model: Node3D=load(WARDEN).instantiate();model.scale=Vector3.ONE*(.80 if kind=="elite" else .52);actor.add_child(model)
	var player: AnimationPlayer=model.find_child("AnimationPlayer",true,false)
	var rig: Skeleton3D=model.find_child("Skeleton3D",true,false)
	player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var materials: Array[StandardMaterial3D]=[]
	_demon19_materials(model,materials,kind)
	actor.set_meta("minion19",{"model":model,"player":player,"skeleton":rig,"materials":materials,"fade":1.0,"death_age":0.0,"clip":"","bucket":-1})
	player.play("idle",0);player.seek(0,true);player.advance(0)
	return actor
func _demon19_materials__chapterx(node: Node,materials: Array[StandardMaterial3D],kind: String) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			child.layers=2
			var signature: int=child.mesh.get_instance_id()
			if not _body_cache.has(signature):
				var body := ArrayMesh.new()
				for surface in child.mesh.get_surface_count():
					var source=child.get_active_material(surface) as StandardMaterial3D
					if source and source.resource_name.begins_with("WardenChain"):continue
					body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,child.mesh.surface_get_arrays(surface))
					body.surface_set_material(body.get_surface_count()-1,source)
				_body_cache[signature]=body
			child.mesh=_body_cache[signature]
			for surface in child.mesh.get_surface_count():
				var source=child.mesh.surface_get_material(surface) as StandardMaterial3D
				if source==null:continue
				var mat := source.duplicate() as StandardMaterial3D
				var tint := Color(.36,.42,.39) if kind=="walker" else Color(.48,.32,.24)
				if source.resource_name.begins_with("WardenMask"):tint=Color(.42,.46,.42) if kind=="walker" else Color(.72,.54,.38)
				mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS;mat.roughness=.9;mat.metallic=0
				mat.albedo_color=tint;mat.set_meta("demon19_tint",tint);child.set_surface_override_material(surface,mat);materials.append(mat)
		else:_demon19_materials(child,materials,kind)
func consume(events: Array) -> void:
	for event in events:
		if int(event.seq)<=_demon19_event:continue
		_demon19_event=int(event.seq)
		if event.type=="enemy_attack":
			var e: Dictionary=view.run.enemies.get(event.target_id,{})
			_demon19_attacks[event.target_id]={"tick":int(event.tick),"end":int(e.get("state_until",event.tick)),"kind":event.get("attack_kind","")}
	consume__q16(events)
func _update_pose__chapterx(actor: Node3D,direction: Vector2,moving: bool,casting: bool,dead: bool,tick: int,playing: bool,hit: bool=false,brief_cast: bool=false) -> void:
	if not actor.has_meta("minion19"):
		_update_pose__q17(actor,direction,moving,casting,dead,tick,playing,hit,brief_cast);return
	var e := _entity(actor)
	if e.is_empty():return
	var state: Dictionary=actor.get_meta("minion19")
	if not playing and not dead and not String(state.clip).is_empty():return
	var player: AnimationPlayer=state.player
	var fraction := clampf(Engine.get_physics_interpolation_fraction(),0,1) if playing else 0.0
	if playing and direction.length_squared()>.001:actor.rotation.y=lerp_angle(actor.rotation.y,atan2(direction.x,direction.y),1-exp(-_render_delta*18))
	var clip := "idle";var time_ := 0.0
	if dead:
		clip="death"
		if view.run.mode not in ["paused","choice","inventory","equipment"]:state.death_age=maxf(float(state.death_age)+_render_delta,float(tick-int(e.dead_tick))/60.0)
		time_=state.death_age
	elif e.state=="windup":
		var kind_ := "fan" if e.attack_kind in ["fan","frost_cross"] else "slam"
		var left := maxf(0,float(int(e.state_until)-tick)-fraction)
		var duration: int=e.get("definition",{}).get("windup",view.run.ENEMY_DEFS[e.kind].windup)
		if left>6:
			clip="windup_"+kind_;time_=clampf(1-(left-6)/float(maxi(1,duration-6)),0,1)*player.get_animation(clip).length
		else:clip=kind_;time_=RELEASE_TIME*(1-left/6.0)
	elif e.state=="recover" and _demon19_attacks.has(e.id):
		var paid: Dictionary=_demon19_attacks[e.id]
		clip="fan" if paid.kind in ["fan","frost_cross"] else "slam"
		var frozen_extension := maxi(0,int(e.state_until)-int(paid.end))
		time_=RELEASE_TIME+maxf(0,float(tick-int(paid.tick)-frozen_extension)+fraction)/60.0
		if time_>=player.get_animation(clip).length:clip="idle";time_=0
	elif moving:
		clip="walk"
		var sample: Dictionary=actor.get_meta("motion_sample",{})
		var phase: float=float(sample.get("phase",0.0))+float((int(e.id)*37)%101)/101.0
		time_=fposmod(phase,1)*player.get_animation(clip).length
	else:time_=fposmod(float(tick)/60.0+float(e.id)*.113,player.get_animation(clip).length)
	var near_: bool=e.position.distance_squared_to(view.run.hero.position)<30.25
	var bucket: int=tick/3
	if moving and not near_ and state.clip==clip and int(state.bucket)==bucket:return
	state.clip=clip;state.bucket=bucket
	# A dashing or recovering charger is sampled again by _update_pose__q21 later in
	# this same call chain, over the same 28 tracks (every clip keys the same tracks),
	# so this first sample would be fully overwritten. Skip it, keep everything else.
	if not (playing and not dead and e.state in ["dash","recover"] and actor.get_meta("role21","")=="charger"):_sample_actor42(player,clip,minf(time_,player.get_animation(clip).length))
	actor.set_meta("minion19_pose",{"clip":clip,"time":time_,"dead":dead,"tick":tick});motion19_samples+=1
func sync__chapterx(run: RefCounted,delta: float) -> void:
	sync__q16(run,delta)
	for id_ in _demon19_attacks.keys():
		if not run.enemies.has(id_):_demon19_attacks.erase(id_)
	for key in actors:
		var actor: Node3D=actors[key]
		if not actor.has_meta("minion19"):continue
		var e: Dictionary=_entities.get(key,{})
		if e.is_empty():continue
		var state: Dictionary=actor.get_meta("minion19")
		var alpha := 1.0
		if e.hp_raw<=0:alpha=1-clampf((float(state.death_age)-.6)/.65,0,1)
		var cold := _cold_corpses.has(key)
		if cold:
			var record: Dictionary=_cold_corpses[key]
			if run.mode not in ["paused","choice","inventory","equipment"]:record.age=maxf(float(record.age)+maxf(0,delta),float(run.tick-int(record.tick))/60.0)
			alpha*=1-smoothstep(.025,.22,float(record.age))
		# The tint choice does not depend on the material; decide it once per actor.
		var icy: bool=cold or (e.hp_raw>0 and run.tick<int(e.frozen_until))
		var flash: bool=(not icy) and run.tick<int(_enemy_hit_until.get(e.id,-1))-9
		var shown_alpha: float=alpha*float(state.fade)
		for mat in state.materials:
			var color: Color=mat.get_meta("demon19_tint")
			if icy:color*=Color(.48,.86,1.16)
			elif flash:color*=Color(1.3,1.2,1.05)
			color.a=shown_alpha;_set_color42(mat,color)
func _overlaps_hero__chapterx(actor: Node3D,camera: Camera3D) -> bool:
	if not actor.has_meta("minion19"):return _overlaps_hero__q12(actor,camera)
	if camera==null or (actor.global_position-hero.global_position).dot(camera.global_basis.z)<=.04:return false
	var rig: Skeleton3D=actor.get_meta("minion19").skeleton
	var a := camera.unproject_position(_bone_point(rig,"Spine1"));var b := camera.unproject_position(_bone_point(rig,"Head"))
	var ha := camera.unproject_position(hero.global_position+Vector3.UP*.32);var hb := camera.unproject_position(hero.global_position+Vector3.UP*1.95)
	var nearest := Geometry2D.get_closest_points_between_segments(a,b,ha,hb)
	var radius := _screen_radius(camera,actor.global_position+Vector3.UP,.42)+_screen_radius(camera,hero.global_position+Vector3.UP,.32)
	return nearest[0].distance_squared_to(nearest[1])<radius*radius
func _sync_hero_rim(camera: Camera3D,overlapping: bool) -> void:
	# One pass over the actors. Sprite, Warden rig and minion presenters are disjoint
	# and independent of each other, so the three former passes are one loop with the
	# same per-actor bodies in the same order (sprite, rig, minion).
	var blend := 1-exp(-_render_delta*18)
	for actor in actors.values():
		if actor.has_meta("sprite"):
			# Fade only nearer enemy sprites that cover the owner. A duplicate mesh
			# depth tint also revealed the robe's internally occluded surfaces, so it
			# is deliberately unused. Preserve enemy RGB hit/freeze modulation.
			var sprite: AnimatedSprite3D=actor.get_meta("sprite")
			var target := .32 if overlapping and _overlaps_hero(actor,camera) else 1.0
			var alpha := lerpf(float(actor.get_meta("owner_fade",1.0)),target,blend)
			if alpha>.995:alpha=1.0
			actor.set_meta("owner_fade",alpha);sprite.modulate.a*=alpha
		if actor.has_meta("enemy_rig"):
			var state: Dictionary=actor.get_meta("enemy_rig");var entity := _entity(actor)
			var target := .56 if overlapping and _overlaps_hero(actor,camera) else 1.0
			state.owner_fade=lerpf(state.owner_fade,target,blend)
			if state.owner_fade>.995:state.owner_fade=1.0
			var corpse_alpha := 1.0
			if not entity.is_empty() and entity.hp_raw<=0:corpse_alpha=1.0-clampf(float(view.run.tick-int(entity.dead_tick)-36)/39.0,0,1)
			for material in state.materials:
				var color: Color=material.get_meta("warden_tint",Color(.52,.55,.51))
				if not entity.is_empty() and entity.hp_raw>0 and view.run.tick<int(entity.frozen_until):color*=Color(.60,.90,1.16)
				elif _warden_phase>=2:color*=Color(1.03,.89,.88)
				color.a=state.owner_fade*corpse_alpha;material.albedo_color=color
		if actor.has_meta("minion19"):
			var state: Dictionary=actor.get_meta("minion19")
			state.fade=lerpf(float(state.fade),.4 if overlapping and _overlaps_hero(actor,camera) else 1.0,blend)
func reset__chapterx() -> void:
	reset__q16();_demon19_event=-1;_demon19_attacks.clear();motion19_samples=0

## Default hook preserves legacy sampling exactly; only Actor42 overrides it.
func _sample_actor42__chapterx(player: AnimationPlayer,clip: String,time_: float) -> void:
	player.play(clip,0);player.seek(time_,true);player.advance(0)

func _set_color42__chapterx(material: StandardMaterial3D,color: Color) -> void:
	material.albedo_color=color

# ---- chapter1/view/chapter_actors_readable19.gd ----
## Material and silhouette refinement; all combat remains owned by the core.
func _create__chapterxx(kind: String) -> Node3D:
	var actor := _create__chapterx(kind)
	if not actor.has_meta("minion19"):return actor
	var state: Dictionary=actor.get_meta("minion19")
	for mat in state.materials:
		var mask: bool=String(mat.resource_name).begins_with("WardenMask")
		var tint := Color(.47,.46,.40) if kind=="walker" else Color(.39,.25,.20)
		if mask:tint=Color(.64,.60,.49) if kind=="walker" else Color(.84,.65,.40)
		mat.albedo_color=tint;mat.set_meta("demon19_tint",tint)
		mat.rim_enabled=true;mat.rim=.22;mat.rim_tint=.15
	if kind=="elite":_shoulders(state)
	return actor
func _shoulders(state: Dictionary) -> void:
	var rig: Skeleton3D=state.skeleton
	var bone := rig.find_bone("Spine1")
	assert(bone>=0)
	var attachment := BoneAttachment3D.new();attachment.bone_name="Spine1";rig.add_child(attachment)
	var armor := Node3D.new();armor.basis=rig.get_bone_global_rest(bone).basis.inverse();attachment.add_child(armor)
	var mat := StandardMaterial3D.new();mat.albedo_color=Color(.26,.23,.19);mat.roughness=.7;mat.metallic=.45
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS;mat.set_meta("demon19_tint",mat.albedo_color);state.materials.append(mat)
	for side in [-1,1]:
		var plate := MeshInstance3D.new();var sphere := SphereMesh.new();sphere.radius=.35;sphere.height=.7;sphere.radial_segments=8;sphere.rings=4
		plate.mesh=sphere;plate.scale=Vector3(1,.38,.86);plate.position=Vector3(side*.66,.54,0);plate.material_override=mat;plate.layers=2;armor.add_child(plate)
		var horn := MeshInstance3D.new();var cone := CylinderMesh.new();cone.top_radius=0;cone.bottom_radius=.13;cone.height=.54;cone.radial_segments=6
		horn.mesh=cone;horn.position=Vector3(side*.86,.80,0);horn.rotation.z=-side*.5;horn.material_override=mat;horn.layers=2;armor.add_child(horn)

# ---- chapter1/view/chapter_actors_batched19.gd ----
## Same authored skin/UV/bone data; one surface with baked body/mask tint.
## The original three materials all reference the same embedded diffuse image.
var _batch19_cache: Dictionary={}
func _create__chapterxxx(kind: String) -> Node3D:
	var actor := _create__chapterxx(kind)
	if actor.has_meta("minion19"):
		for mat in actor.get_meta("minion19").materials:
			if mat.resource_name=="Minion19Batched":
				mat.albedo_color=Color.WHITE;mat.set_meta("demon19_tint",Color.WHITE)
	return actor
func _demon19_materials__chapterxxx(node: Node,materials: Array[StandardMaterial3D],kind: String) -> void:
	for child in node.get_children():
		if not child is MeshInstance3D:
			_demon19_materials(child,materials,kind);continue
		child.layers=2
		# Ordinary sprites never cast directional shadows either. Keep the final
		# Warden and hero on their existing independently shadowed presenters.
		child.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var signature := str(child.mesh.get_instance_id())+":"+kind
		if not _batch19_cache.has(signature):
			var combined: Array=[]
			var base: StandardMaterial3D
			for surface in child.mesh.get_surface_count():
				var source := child.get_active_material(surface) as StandardMaterial3D
				assert(source!=null)
				if source.resource_name.begins_with("WardenChain"):continue
				if base==null:base=source
				else:assert(base.albedo_texture.get_image().get_data()==source.albedo_texture.get_image().get_data())
				var arrays: Array=child.mesh.surface_get_arrays(surface).duplicate(true)
				var mask: bool=source.resource_name.begins_with("WardenMask")
				var tint := Color(.47,.46,.40) if kind=="walker" else Color(.39,.25,.20)
				if mask:tint=Color(.64,.60,.49) if kind=="walker" else Color(.84,.65,.40)
				var colors := PackedColorArray();colors.resize(arrays[Mesh.ARRAY_VERTEX].size());colors.fill(tint);arrays[Mesh.ARRAY_COLOR]=colors
				if combined.is_empty():combined=arrays;continue
				var offset: int=combined[Mesh.ARRAY_VERTEX].size()
				for slot in Mesh.ARRAY_MAX:
					if slot==Mesh.ARRAY_INDEX:
						for index in arrays[slot]:combined[slot].append(index+offset)
					elif arrays[slot]!=null:combined[slot].append_array(arrays[slot])
			var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,combined)
			var mat := base.duplicate() as StandardMaterial3D
			mat.resource_name="Minion19Batched";mat.vertex_color_use_as_albedo=true;mat.vertex_color_is_srgb=true
			mat.albedo_color=Color.WHITE;mat.roughness=.9;mat.metallic=0;mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			mesh.surface_set_material(0,mat);_batch19_cache[signature]=mesh
		child.mesh=_batch19_cache[signature]
		var mat := child.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
		mat.set_meta("demon19_tint",Color.WHITE);child.set_surface_override_material(0,mat);materials.append(mat)

# ---- chapter1/view/chapter_actors_quality20.gd ----
var _victory20_age := 0.0
var _victory20_active := false
## Make the paid final-boss death settle onto the ground before reward UI.
## Local visual transform only; entity position/hurtbox/reward remain untouched.
func _update_pose__q20(actor: Node3D,direction: Vector2,moving: bool,casting: bool,dead: bool,tick: int,playing: bool,hit: bool=false,brief_cast: bool=false) -> void:
	var saved_delta := _render_delta
	if dead and actor.has_meta("enemy_rig") and view.run.mode=="inventory":_render_delta=0
	_update_pose__chapterx(actor,direction,moving,casting,dead,tick,playing,hit,brief_cast)
	_render_delta=saved_delta
	if not actor.has_meta("enemy_rig"):return
	var model: Node3D=actor.get_meta("enemy_rig").model
	if not dead:
		model.rotation.z=0;model.position.y=0;return
	var age: float=actor.get_meta("warden_death_age",0.0)
	var collapse := smoothstep(.18,1.08,age)
	model.rotation.z=collapse*1.47
	model.position.y=lerpf(0,-.10,collapse)
	actor.set_meta("warden20_collapse",collapse)
func sync__q20(run: RefCounted,delta: float) -> void:
	if run.mode=="victory":_victory20_active=true
	if _victory20_active and run.mode=="victory":_victory20_age+=maxf(0,delta)
	sync__chapterx(run,delta)
	if not _victory20_active:return
	var alpha := 1-smoothstep(.12,.62,_victory20_age)
	for actor in actors.values():
		var e := _entity(actor)
		if e.is_empty() or actor.has_meta("enemy_rig"):continue
		if actor.has_meta("minion19"):
			for mat in actor.get_meta("minion19").materials:mat.albedo_color.a*=alpha
		elif actor.has_meta("sprite"):actor.get_meta("sprite").modulate.a*=alpha
func reset__q20() -> void:
	reset__chapterx();_victory20_age=0;_victory20_active=false

# ---- chapter1/view/chapter_actors_quality21.gd ----
var _staff21_mesh: ArrayMesh
var _staff21_material: StandardMaterial3D
## Two further roles share the proven skin batch, retaining their actual AI.
func _create__q21(kind: String) -> Node3D:
	if kind not in ["ranged","charger"]:return _create__chapterxxx(kind)
	var actor := _create__chapterxxx("walker");actor.set_meta("kind",kind)
	var state: Dictionary=actor.get_meta("minion19")
	state.model.scale=Vector3(.44,.58,.44) if kind=="ranged" else Vector3(.72,.48,.72)
	for mat in state.materials:
		var tint := Color(.72,.94,1.10) if kind=="ranged" else Color(.86,.60,.43)
		mat.albedo_color=tint;mat.set_meta("demon19_tint",tint)
	if kind=="ranged":_staff21(state)
	actor.set_meta("role21",kind)
	return actor
func _staff21(state: Dictionary) -> void:
	var rig: Skeleton3D=state.skeleton
	var index := rig.find_bone("Hand.R");assert(index>=0)
	# Hand translation follows the actual pose, while the held shaft remains
	# upright instead of inheriting the wrist's near-camera pointing rotation.
	var staff := Node3D.new();staff.name="CasterStaff21";staff.scale=state.model.scale;state.model.get_parent().add_child(staff);state.staff21=staff
	if _staff21_mesh==null:_build_staff21()
	var mesh := MeshInstance3D.new();mesh.name="StaffMesh";mesh.mesh=_staff21_mesh;mesh.layers=2;mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# D3: surface 0 (haft) uses the shared dark template as is; surface 1 (head) gets the per-actor clone with the crimson glow.
	var mat := _staff21_material.duplicate() as StandardMaterial3D;mat.set_meta("demon19_tint",Color.WHITE)
	mat.emission_enabled=true;mat.emission=Color("ff2f4f");mat.emission_energy_multiplier=.9
	mesh.set_surface_override_material(0,_staff21_material);mesh.set_surface_override_material(1,mat);state.materials.append(mat);staff.add_child(mesh)
func _build_staff21() -> void:
	# A0-2: dark haft (2.0 long, was 3.2) + small crimson head (enemy threat color, ART-PLAN 2.1).
	var cylinder := CylinderMesh.new();cylinder.top_radius=.06;cylinder.bottom_radius=.075;cylinder.height=2.0;cylinder.radial_segments=6
	var prism := PrismMesh.new();prism.size=Vector3(.52,.80,.52)
	_staff21_mesh=ArrayMesh.new()
	for part in [{"mesh":cylinder,"y":.35,"color":Color(.16,.14,.12),"uv":Vector2(.25,.5)},{"mesh":prism,"y":1.75,"color":Color(.60,.10,.18),"uv":Vector2(.75,.5)}]:
		var arrays: Array=part.mesh.surface_get_arrays(0).duplicate(true)
		for i in arrays[Mesh.ARRAY_VERTEX].size():arrays[Mesh.ARRAY_VERTEX][i]+=Vector3(0,part.y,0)
		var colors := PackedColorArray();colors.resize(arrays[Mesh.ARRAY_VERTEX].size());colors.fill(part.color);arrays[Mesh.ARRAY_COLOR]=colors
		var uv := PackedVector2Array();uv.resize(colors.size());uv.fill(part.uv);arrays[Mesh.ARRAY_TEX_UV]=uv
		_staff21_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	# Cause of the white staff: the old 2x1 emission texture (black haft / teal head) did not gate the
	# emission (red/blue test texels also rendered pure white), so emission = WHITE*.35 lit the whole mesh
	# as a flat gray veil over the dark vertex colors. No emission now; color comes from vertex colors only.
	_staff21_material=StandardMaterial3D.new();_staff21_material.vertex_color_use_as_albedo=true;_staff21_material.vertex_color_is_srgb=true;_staff21_material.albedo_color=Color.WHITE;_staff21_material.roughness=.85
	_staff21_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
func _update_pose__q21(actor: Node3D,direction: Vector2,moving: bool,casting: bool,dead: bool,tick: int,playing: bool,hit: bool=false,brief_cast: bool=false) -> void:
	if actor.has_meta("role21") and playing and moving and not dead:
		var entity := _entity(actor)
		if not entity.is_empty() and entity.position.distance_squared_to(view.run.hero.position)>9:
			var bucket: int=tick/3
			if int(actor.get_meta("role21_bucket",-1))==bucket:
				if direction.length_squared()>.001:actor.rotation.y=lerp_angle(actor.rotation.y,atan2(direction.x,direction.y),1-exp(-_render_delta*18))
				return
			actor.set_meta("role21_bucket",bucket)
	_update_pose__q20(actor,direction,moving,casting,dead,tick,playing,hit,brief_cast)
	if not actor.has_meta("role21"):return
	var e := _entity(actor)
	if e.is_empty():return
	var state: Dictionary=actor.get_meta("minion19")
	if actor.get_meta("role21")=="ranged":
		var pose: Dictionary=actor.get_meta("minion19_pose",{})
		if state.get("staff21_time",-1.0)!=pose.get("time",0.0) or state.get("staff21_clip","")!=pose.get("clip",""):
			if _staff30_actor!=actor:
				_flush_lazy30()
				state.staff21.position=actor.to_local(_bone_point(state.skeleton,"Hand.R"))
			state.staff21_time=pose.get("time",0.0);state.staff21_clip=pose.get("clip","")
		return
	if not playing or dead:return
	if actor.get_meta("role21")=="charger":
		var lean := .48 if e.state=="dash" else (-.14 if e.state=="windup" else 0.0)
		state.model.rotation.x=lerpf(state.model.rotation.x,lean,1-exp(-_render_delta*20))
		if e.state=="dash":
			var player: AnimationPlayer=state.player
			var phase := fposmod(float(tick-int(e.state_until)+32)/60.0*2.4,1)
			_sample_actor42(player,"walk",phase*player.get_animation("walk").length)
			actor.set_meta("minion19_pose",{"clip":"walk","time":phase*player.get_animation("walk").length,"dead":false,"tick":tick})
			actor.set_meta("role21_dash",{"tick":tick,"phase":phase,"paid_direction":e.attack_direction})
		elif e.state=="recover":
			var player: AnimationPlayer=state.player
			var definition: Dictionary=view.run._enemy_definition(e)
			var time_ := maxf(0,float(tick-int(e.state_until)+int(definition.recover)))/60.0
			_sample_actor42(player,"idle",minf(time_,player.get_animation("idle").length))
			actor.set_meta("minion19_pose",{"clip":"idle","time":time_,"dead":false,"tick":tick})

# ---- chapter1/view/chapter_actors_quality24.gd ----
## Frozen imported mesh path identifies immutable geometry across scene instances.
## Keep per-actor material overrides, skeletons and poses independent.
var _shared_skin24: Dictionary={}
var skin24_builds := 0
var skin24_hits := 0
func _demon19_materials(node: Node,materials: Array[StandardMaterial3D],kind: String) -> void:
	var aliases: Array[Dictionary]=[]
	for child in node.get_children():
		if not child is MeshInstance3D:continue
		var path: String=child.mesh.resource_path
		if kind not in ["walker","elite"] or not path.begins_with(WARDEN+"::"):continue
		var key := path+":"+kind
		var transient := str(child.mesh.get_instance_id())+":"+kind
		if _shared_skin24.has(key):
			_batch19_cache[transient]=_shared_skin24[key];skin24_hits+=1
		aliases.append({"key":key,"transient":transient})
	_demon19_materials__chapterxxx(node,materials,kind)
	for alias in aliases:
		if not _shared_skin24.has(alias.key):
			_shared_skin24[alias.key]=_batch19_cache[alias.transient];skin24_builds+=1
		_batch19_cache.erase(alias.transient)

# ---- chapter1/view/chapter_actors_quality25b.gd ----
## Recycle only ordinary role presenters after their core entity is gone.
## Boss/elite ownership and all retained corpses keep their original lifetime.
const POOL25_CAP := 224
var _pool25: Dictionary={}
var _pool25_root: Node3D
var pool25_hits := 0
var pool25_created := 0
func setup__q25b(owner_view: Node3D) -> void:
	setup__rigged(owner_view)
	_pool25_root=Node3D.new();_pool25_root.name="DormantActors25"
	_pool25_root.visible=false;_pool25_root.process_mode=Node.PROCESS_MODE_DISABLED
	owner_view.add_child(_pool25_root)
	# Allocate ordinary presenters before the menu; no invisible core entities.
	for entry in [{"kind":"walker","count":144},{"kind":"ranged","count":40},{"kind":"charger","count":40}]:
		for i in int(entry.count):
			var actor := _create__q21(entry.kind)
			pool25_created+=1
			var stored := _stash25(actor)
			assert(stored)
			if not stored:actor.queue_free()
func _pool25_size() -> int:
	var count := 0
	for entries in _pool25.values():count+=entries.size()
	return count
func _stash25(actor: Node3D) -> bool:
	var kind: String=actor.get_meta("kind","")
	if kind not in ["walker","ranged","charger"] or not actor.has_meta("minion19") or _pool25_size()>=POOL25_CAP:return false
	if actor.get_parent()!=null:actor.get_parent().remove_child(actor)
	_pool25_root.add_child(actor)
	var entries: Array=_pool25.get(kind,[]);entries.append(actor);_pool25[kind]=entries
	return true
func _create__q25b(kind: String) -> Node3D:
	var entries: Array=_pool25.get(kind,[])
	if kind in ["walker","ranged","charger"] and not entries.is_empty():
		var actor: Node3D=entries.pop_back();_pool25_root.remove_child(actor)
		for name_ in actor.get_meta_list():
			if name_ not in ["kind","minion19","role21"]:actor.remove_meta(name_)
		actor.transform=Transform3D.IDENTITY;actor.visible=true
		var state: Dictionary=actor.get_meta("minion19")
		state.fade=1.0;state.death_age=0.0;state.clip="";state.bucket=-1
		state.model.position=Vector3.ZERO;state.model.rotation=Vector3.ZERO
		state.erase("staff21_time");state.erase("staff21_clip")
		state.skeleton.reset_bone_poses()
		state.player.stop();state.player.play("idle",0);state.player.seek(0,true);state.player.advance(0)
		if state.has("staff21"):state.staff21.position=Vector3.ZERO
		for material_ in state.materials:material_.albedo_color=material_.get_meta("demon19_tint")
		pool25_hits+=1
		return actor
	var actor := _create__q21(kind)
	if kind in ["walker","ranged","charger"]:pool25_created+=1
	return actor
func sync__q25b(run: RefCounted,delta: float) -> void:
	var wanted: Dictionary={}
	for entity in run.enemies.values():wanted[frame_keys[entity.id]]=true
	for key in actors.keys():
		if not wanted.has(key) and _stash25(actors[key]):actors.erase(key)
	sync__q20(run,delta)
func reset__q25b() -> void:
	for key in actors.keys():
		if _stash25(actors[key]):actors.erase(key)
	reset__q20()

# ---- chapter1/view/chapter_actors_quality28.gd ----
## Authored upper-body hit poses, sampled once before the menu.
## No new combat state; planted attacks, frozen poses and death retain priority.
const HIT28_BONES := ["Spine1","Spine2","Spine3","Shoulder.L","Shoulder.R","Arm.L","Arm.R","Neck.001","Head"]
const HIT28_SAMPLES := 13
var _hit28_indices: Array[int]=[]
var _hit28_frames: Array=[]
var hit28_blends := 0
func setup__q28(owner_view: Node3D) -> void:
	setup__q25b(owner_view)
	var actor: Node3D=_pool25.walker[0]
	var state: Dictionary=actor.get_meta("minion19")
	var rig: Skeleton3D=state.skeleton
	var player: AnimationPlayer=state.player
	for name_ in HIT28_BONES:
		var index := rig.find_bone(name_)
		assert(index>=0)
		_hit28_indices.append(index)
	var length_: float=player.get_animation("hit").length
	for sample in HIT28_SAMPLES:
		player.play("hit",0);player.seek(float(sample)/float(HIT28_SAMPLES-1)*length_,true);player.advance(0)
		var poses: Array[Transform3D]=[]
		for index in _hit28_indices:poses.append(rig.get_bone_pose(index))
		_hit28_frames.append(poses)
	player.play("idle",0);player.seek(0,true);player.advance(0)
func _restore28(actor: Node3D) -> void:
	if not actor.has_meta("hit28_base"):return
	_flush_lazy30()
	var rig: Skeleton3D=actor.get_meta("minion19").skeleton
	var poses: Array=actor.get_meta("hit28_base")
	for i in _hit28_indices.size():rig.set_bone_pose(_hit28_indices[i],poses[i])
	actor.remove_meta("hit28_base");actor.remove_meta("hit28_weight")
	_staff28(actor)
func _staff28(actor: Node3D) -> void:
	var state: Dictionary=actor.get_meta("minion19")
	if state.has("staff21"):state.staff21.position=actor.to_local(_bone_point(state.skeleton,"Hand.R"))
func _update_pose__q28(actor: Node3D,direction: Vector2,moving: bool,casting: bool,dead: bool,tick: int,playing: bool,hit: bool=false,brief_cast: bool=false) -> void:
	if not actor.has_meta("minion19"):
		_update_pose__q21(actor,direction,moving,casting,dead,tick,playing,hit,brief_cast);return
	# Recover retains the direction of the paid attack instead of stale travel.
	var facing_entity := _entity(actor)
	if playing and not dead and not facing_entity.is_empty() and facing_entity.state=="recover":
		direction=facing_entity.attack_direction
	# A modal or cold freeze holds the complete currently displayed pose.
	if playing or dead:_restore28(actor)
	_update_pose__q21(actor,direction,moving,casting,dead,tick,playing,hit,brief_cast)
	if not playing or dead or not hit or _hit28_frames.is_empty():return
	var entity := _entity(actor)
	if entity.is_empty() or entity.state not in ["move","idle"]:return
	var age := clampf(float(tick-int(_enemy_hit_until.get(entity.id,tick))+12)/12.0,0,1)
	var weight := .85*sin(PI*age)
	if weight<.001:return
	var sample_ := age*float(HIT28_SAMPLES-1)
	var a := mini(int(sample_),HIT28_SAMPLES-1);var b := mini(a+1,HIT28_SAMPLES-1)
	_flush_lazy30()
	var rig: Skeleton3D=actor.get_meta("minion19").skeleton
	var base: Array[Transform3D]=[]
	for i in _hit28_indices.size():
		var index: int=_hit28_indices[i]
		var original := rig.get_bone_pose(index);base.append(original)
		var pose: Transform3D=_hit28_frames[a][i].interpolate_with(_hit28_frames[b][i],sample_-float(a))
		var blended := original.interpolate_with(pose,weight)
		if HIT28_BONES[i]=="Spine1":
			var recoil_axis := (rig.get_bone_global_rest(index).basis.inverse()*Vector3.RIGHT).normalized()
			blended.basis=blended.basis*Basis(recoil_axis,-.28*weight)
		rig.set_bone_pose(index,blended)
	_staff28(actor)
	actor.set_meta("hit28_base",base);actor.set_meta("hit28_weight",weight);hit28_blends+=1

# ---- chapter1/view/chapter_actors_quality29.gd ----
## Unconnected study: existing moon casts ordinary-body silhouettes on ground.
## No extra light, mesh, actor, collision or simulation state.
func setup__q29(owner_view: Node3D) -> void:
	setup__q28(owner_view)
	for actor in _pool25_root.get_children():_enable_actor29(actor)
	for actor in actors.values():_enable_actor29(actor)
func _create__q29(kind: String) -> Node3D:
	var actor := _create__q25b(kind)
	_enable_actor29(actor)
	return actor
func _enable_actor29(actor: Node3D) -> void:
	if actor.has_meta("minion19"):_enable_meshes29(actor.get_meta("minion19").model)
func _enable_meshes29(node: Node) -> void:
	if node is MeshInstance3D:node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for child in node.get_children():_enable_meshes29(child)

# ---- chapter1/view/chapter_actors_quality30c.gd ----
## Unconnected crowd silhouette study. Stable entity identity, no simulation RNG.
## Preserve each role's height/width hierarchy, paid poses and shared mesh batch.
var variants30_enabled := true
const BONES30 := ["Head","Shoulder.L","Shoulder.R","Arm.L","Arm.R"]
const HEAD30 := [Vector3(.82,.94,.88),Vector3(1.15,1.06,1.12),Vector3.ONE,Vector3(.93,1.12,.94)]
const SHOULDER30 := [Vector3(.92,1.03,.92),Vector3(1.09,1.13,1.09),Vector3.ONE,Vector3(.94,.91,.94)]
const ARM30 := [Vector3(.91,1.10,.91),Vector3(1.13,.94,1.13),Vector3.ONE,Vector3(.97,1.04,.97)]
const WALKER30 := [Vector3(.49,.56,.49),Vector3(.57,.50,.55),Vector3(.52,.52,.52),Vector3(.49,.51,.57)]
const RANGED30 := [Vector3(.42,.60,.42),Vector3(.46,.56,.45),Vector3(.44,.58,.44),Vector3(.43,.59,.46)]
const CHARGER30 := [Vector3(.75,.46,.73),Vector3(.69,.50,.70),Vector3(.72,.48,.72),Vector3(.74,.47,.69)]
func _apply_variant30(actor: Node3D) -> void:
	if not actor.has_meta("minion19"):return
	var kind: String=actor.get_meta("kind","")
	if kind not in ["walker","ranged","charger"]:return
	var entity := _entity(actor)
	if entity.is_empty():return
	var state: Dictionary=actor.get_meta("minion19")
	var identity: String=frame_keys[entity.id]+(":true" if variants30_enabled else ":false")
	if actor.get_meta("variant30_identity","")==identity:return
	_flush_lazy30()
	var variant := posmod(int(entity.id)*17+int(entity.generation)*7,4)
	var scale_ := Vector3.ONE*.52
	if kind=="ranged":scale_=Vector3(.44,.58,.44)
	elif kind=="charger":scale_=Vector3(.72,.48,.72)
	if variants30_enabled:
		match kind:
			"walker":scale_=WALKER30[variant]
			"ranged":scale_=RANGED30[variant]
			"charger":scale_=CHARGER30[variant]
	state.model.scale=scale_
	if state.has("staff21"):
		state.staff21.scale=scale_
		state.staff21.position=actor.to_local(_bone_point(state.skeleton,"Hand.R"))
	actor.set_meta("variant30_identity",identity)
	actor.set_meta("variant30_index",variant if variants30_enabled else -1)
var _bones30: Array[int]=[]
func setup__q30c(owner_view: Node3D) -> void:
	setup__q29(owner_view)
	var rig: Skeleton3D=_pool25.walker[0].get_meta("minion19").skeleton
	for name_ in BONES30:
		var index := rig.find_bone(name_)
		assert(index>=0)
		_bones30.append(index)
# The per-frame "restore the shaped bone scales, then shape them again" is deferred:
# the restore is written (by _flush_lazy30) only when something later in the same
# frame touches the bones (a new sample, the hit pose blend or its restore, a variant
# change). When nothing does, the restore and the identical re-shape cancel out and
# neither is written, so the skeleton is not marked changed for no reason.
var _lazy30_actor: Node3D=null
# Actor whose staff position is rewritten at the end of _update_pose__q30c anyway.
var _staff30_actor: Node3D=null
func _flush_lazy30() -> void:
	var actor := _lazy30_actor
	if actor==null:return
	_lazy30_actor=null
	var rig: Skeleton3D=actor.get_meta("minion19").skeleton
	var base: Array=actor.get_meta("shape30_base")
	for i in _bones30.size():rig.set_bone_pose_scale(_bones30[i],base[i])
	actor.set_meta("shape30_active",false)
func _update_pose__q30c(actor: Node3D,direction: Vector2,moving: bool,casting: bool,dead: bool,tick: int,playing: bool,hit: bool=false,brief_cast: bool=false) -> void:
	var shaped := actor.has_meta("shape30_base")
	var state: Dictionary=actor.get_meta("minion19",{})
	var deferred := false
	if shaped and actor.get_meta("shape30_active",false) and (playing or dead):
		_lazy30_actor=actor;deferred=true
	_apply_variant30(actor)
	# True when the staff position written below is the last write of this frame.
	if state.has("staff21") and actor.has_meta("variant30_index") and int(actor.get_meta("variant30_index"))>=0 and (deferred or not actor.get_meta("shape30_active",false)):_staff30_actor=actor
	_update_pose__q28(actor,direction,moving,casting,dead,tick,playing,hit,brief_cast)
	_staff30_actor=null
	var pending := deferred and _lazy30_actor==actor
	if not actor.has_meta("variant30_index") or (actor.get_meta("shape30_active",false) and not pending):
		_flush_lazy30();return
	var variant: int=actor.get_meta("variant30_index")
	if variant<0:
		_flush_lazy30();return
	var rig: Skeleton3D=state.skeleton
	if pending:_lazy30_actor=null
	else:
		var base: Array
		if shaped:base=actor.get_meta("shape30_base")
		else:
			base.resize(_bones30.size())
			actor.set_meta("shape30_base",base)
		for i in _bones30.size():
			base[i]=rig.get_bone_pose_scale(_bones30[i])
			var shape: Vector3=HEAD30[variant] if i==0 else (SHOULDER30[variant] if i<3 else ARM30[variant])
			rig.set_bone_pose_scale(_bones30[i],base[i]*shape)
		actor.set_meta("shape30_active",true)
	if state.has("staff21"):state.staff21.position=actor.to_local(_bone_point(rig,"Hand.R"))

# ---- chapter1/view/chapter_actors_quality32b.gd ----
## Role-specific anticipation/recovery accents; original paid clip remains owner.
var motion32_enabled := true
const BONES32 := ["Spine1","Spine3","Shoulder.L","Shoulder.R","Arm.L","Arm.R","Head"]
var _indices32: Array[int]=[]
var _axes32: Array[Array]=[]
var motion32_samples := 0
func setup__q32b(owner_view: Node3D) -> void:
	setup__q30c(owner_view)
	var rig: Skeleton3D=_pool25.walker[0].get_meta("minion19").skeleton
	for name_ in BONES32:
		var index := rig.find_bone(name_)
		assert(index>=0)
		_indices32.append(index)
		var inverse := rig.get_bone_global_rest(index).basis.inverse()
		_axes32.append([(inverse*Vector3.RIGHT).normalized(),(inverse*Vector3.UP).normalized(),(inverse*Vector3.BACK).normalized()])
func _restore32(actor: Node3D) -> void:
	if not actor.has_meta("motion32_base"):return
	var rig: Skeleton3D=actor.get_meta("minion19").skeleton
	var base: Array=actor.get_meta("motion32_base")
	for i in _indices32.size():rig.set_bone_pose_rotation(_indices32[i],base[i])
	actor.remove_meta("motion32_base")
func _update_pose__q32b(actor: Node3D,direction: Vector2,moving: bool,casting: bool,dead: bool,tick: int,playing: bool,hit: bool=false,brief_cast: bool=false) -> void:
	if actor.has_meta("minion19") and (playing or dead):_restore32(actor)
	_update_pose__q30c(actor,direction,moving,casting,dead,tick,playing,hit,brief_cast)
	if not motion32_enabled or not playing or dead or not actor.has_meta("minion19"):return
	var entity := _entity(actor)
	if entity.is_empty() or entity.state not in ["windup","recover"]:return
	var weight := 0.0
	if entity.state=="windup":
		var duration: int=entity.get("definition",{}).get("windup",view.run.ENEMY_DEFS[entity.kind].windup)
		var left := float(int(entity.state_until)-tick)
		var progress := clampf(1.0-left/float(maxi(1,duration)),0,1)
		weight=smoothstep(.05,.65,progress)*(1.0-smoothstep(.82,1.0,progress))
	elif _demon19_attacks.has(entity.id):
		var paid: Dictionary=_demon19_attacks[entity.id]
		var extension := maxi(0,int(entity.state_until)-int(paid.end))
		var age := maxf(0,float(tick-int(paid.tick)-extension))/60.0
		var duration := float(entity.get("definition",{}).get("recover",view.run.ENEMY_DEFS[entity.kind].recover))/60.0
		weight=-.65*sin(PI*clampf(age/maxf(.05,duration),0,1))
	if absf(weight)<.001:return
	var angles: Array[Vector3]
	match String(entity.kind):
		"walker":angles=[Vector3(.10,.24,0),Vector3(0,.18,0),Vector3(.10,0,-.15),Vector3(-.24,0,.35),Vector3(.10,0,-.12),Vector3(-.64,0,.20),Vector3(-.06,-.16,0)]
		"charger":angles=[Vector3(.32,0,0),Vector3(.12,0,0),Vector3(.08,0,-.32),Vector3(.08,0,.32),Vector3(-.24,0,-.22),Vector3(-.24,0,.22),Vector3(-.20,0,0)]
		"ranged":angles=[Vector3(-.16,-.16,0),Vector3(-.12,-.12,0),Vector3(-.16,0,-.12),Vector3(-.40,0,.24),Vector3(-.30,0,-.14),Vector3(-.60,0,.08),Vector3(.10,.14,0)]
		"elite":angles=[Vector3(-.14,0,0),Vector3(-.18,0,0),Vector3(-.30,0,-.28),Vector3(-.30,0,.28),Vector3(-.48,0,-.18),Vector3(-.48,0,.18),Vector3(.16,0,0)]
		_:return
	var rig: Skeleton3D=actor.get_meta("minion19").skeleton
	var base: Array=[]
	for i in _indices32.size():
		var rotation := rig.get_bone_pose_rotation(_indices32[i]);base.append(rotation)
		var a: Vector3=angles[i]*weight*1.55
		rotation=rotation*Quaternion(_axes32[i][0],a.x)*Quaternion(_axes32[i][1],a.y)*Quaternion(_axes32[i][2],a.z)
		rig.set_bone_pose_rotation(_indices32[i],rotation.normalized())
	actor.set_meta("motion32_base",base);motion32_samples+=1
	_staff28(actor)

# ---- chapter1/view/chapter_actors_quality34b.gd ----
## Unconnected walker-family study. Original actor roots, core, pool and paid events.
const OUTLAW34=preload("res://chapter1/art/skeleton_outlaw/v02/skeleton_outlaw_merged.glb")
const WALK34 := 56.0/60.0
const SWING34 := 68.0/60.0
const STRIKE34 := 25.0/60.0
const HIT34 := ["ORG-spine","ORG-chest","ORG-neck","ORG-head","ORG-shoulder_L","ORG-upper_arm_L","ORG-forearm_L","ORG-shoulder_R","ORG-upper_arm_R","ORG-forearm_R"]
var _hit34_indices: Array[int]=[]
var _hit34_frames: Array=[]
var _head34 := -1
var hit34_blends := 0
var motion34_samples := 0
var replacements34 := 0
func _is34(actor: Node3D) -> bool:
	return actor.has_meta("minion19") and bool(actor.get_meta("minion19").get("family34",false))
func setup(owner_view: Node3D) -> void:
	# Existing Mophs pose caches are built before replacing only the walker models.
	setup__q32b(owner_view)
	for actor in _pool25.walker:_replace34(actor)
	var state: Dictionary=_pool25.walker[0].get_meta("minion19")
	var rig: Skeleton3D=state.skeleton
	_head34=rig.find_bone("ORG-head")
	assert(_head34>=0)
	for name_ in HIT34:
		var index := rig.find_bone(name_);assert(index>=0);_hit34_indices.append(index)
	for sample in 13:
		state.player.play("hit",0);state.player.seek(float(sample)/12.0*(46.0/60.0),true);state.player.advance(0)
		var poses: Array[Transform3D]=[]
		for index in _hit34_indices:poses.append(rig.get_bone_pose(index))
		_hit34_frames.append(poses)
	state.player.play("idle",0);state.player.seek(0,true);state.player.advance(0)
func _replace34(actor: Node3D) -> void:
	if _is34(actor):return
	var old: Dictionary=actor.get_meta("minion19")
	var model: Node3D=OUTLAW34.instantiate();actor.add_child(model);model.scale=Vector3.ONE*.62
	var rig: Skeleton3D=model.find_child("Skeleton3D",true,false)
	var player: AnimationPlayer=model.find_child("AnimationPlayer",true,false)
	player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var materials: Array[StandardMaterial3D]=[];_materials34(model,materials)
	var state := {"family34":true,"model":model,"player":player,"skeleton":rig,"materials":materials,"fade":1.0,"death_age":0.0,"clip":"","bucket":-1}
	actor.set_meta("minion19",state)
	_disarm34(old.model);old.model.get_parent().remove_child(old.model);old.model.queue_free()
	player.play("idle",0);player.seek(0,true);player.advance(0);replacements34+=1
func _materials34(node: Node,materials: Array[StandardMaterial3D]) -> void:
	if node is MeshInstance3D:
		node.layers=2;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for surface in node.mesh.get_surface_count():
			var material: StandardMaterial3D=node.get_active_material(surface).duplicate()
			material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			var tint := Color(.58,.54,.46)
			material.albedo_color=tint;material.set_meta("demon19_tint",tint)
			material.rim_enabled=true;material.rim=.18;material.rim_tint=.12
			node.set_surface_override_material(surface,material);materials.append(material)
	for child in node.get_children():_materials34(child,materials)
func _create(kind: String) -> Node3D:
	var actor := _create__q29(kind)
	if kind=="walker" and actor.has_meta("minion19"):_replace34(actor)
	return actor
func _update_pose__q34b(actor: Node3D,direction: Vector2,moving: bool,casting: bool,dead: bool,tick: int,playing: bool,hit: bool=false,brief_cast: bool=false) -> void:
	if not _is34(actor):
		_update_pose__q32b(actor,direction,moving,casting,dead,tick,playing,hit,brief_cast);return
	var e := _entity(actor)
	if e.is_empty():return
	var state: Dictionary=actor.get_meta("minion19")
	if not playing and not dead and not String(state.clip).is_empty():return
	if e.state=="recover":direction=e.attack_direction
	if playing and direction.length_squared()>.001:actor.rotation.y=lerp_angle(actor.rotation.y,atan2(direction.x,direction.y),1-exp(-_render_delta*18))
	var fraction := clampf(Engine.get_physics_interpolation_fraction(),0,1) if playing else 0.0
	var clip := "idle";var time_ := 0.0
	if dead:
		clip="death"
		if view.run.mode not in ["paused","choice","inventory","equipment"]:state.death_age=maxf(float(state.death_age)+_render_delta,float(tick-int(e.dead_tick))/60.0)
		time_=minf(float(state.death_age),1.60)
	elif e.state=="windup":
		var duration: int=e.get("definition",{}).get("windup",view.run.ENEMY_DEFS[e.kind].windup)
		var left := maxf(0,float(int(e.state_until)-tick)-fraction)
		clip="attack_slam";time_=clampf(1-left/float(maxi(1,duration)),0,1)*STRIKE34
	elif e.state=="recover" and _demon19_attacks.has(e.id):
		var paid: Dictionary=_demon19_attacks[e.id]
		var extension := maxi(0,int(e.state_until)-int(paid.end))
		var duration: int=e.get("definition",{}).get("recover",view.run.ENEMY_DEFS[e.kind].recover)
		var progress := clampf((float(tick-int(paid.tick)-extension)+fraction)/float(maxi(1,duration)),0,1)
		clip="attack_slam";time_=STRIKE34+progress*(SWING34-STRIKE34)
	elif moving:
		clip="walk"
		var sample: Dictionary=actor.get_meta("motion_sample",{})
		time_=fposmod(float(sample.get("phase",0.0))+float((int(e.id)*37)%101)/101.0,1)*WALK34
	else:time_=fposmod(float(tick)/60.0+float(e.id)*.113,128.0/60.0)
	var near_: bool=e.position.distance_squared_to(view.run.hero.position)<30.25
	var bucket: int=tick/3
	if moving and not hit and not near_ and state.clip==clip and int(state.bucket)==bucket:return
	state.clip=clip;state.bucket=bucket
	state.model.scale=Vector3.ONE*(.60+float(posmod(int(e.id)*17+int(e.generation)*7,4))*.015)
	state.player.play(clip,0);state.player.seek(time_,true);state.player.advance(0)
	if playing and not dead and hit and e.state in ["move","idle"] and not _hit34_frames.is_empty():
		var age := clampf(float(tick-int(_enemy_hit_until.get(e.id,tick))+12)/12.0,0,1)
		var weight := .85*sin(PI*age);var sample_ := age*12.0;var a := mini(int(sample_),12);var b := mini(a+1,12)
		for i in _hit34_indices.size():
			var index: int=_hit34_indices[i]
			var pose: Transform3D=_hit34_frames[a][i].interpolate_with(_hit34_frames[b][i],sample_-float(a))
			state.skeleton.set_bone_pose(index,state.skeleton.get_bone_pose(index).interpolate_with(pose,weight))
		hit34_blends+=1
	if _head34>=0:state.skeleton.set_bone_pose_scale(_head34,Vector3.ONE*.72)
	actor.set_meta("minion19_pose",{"clip":clip,"time":time_,"dead":dead,"tick":tick,"family34":true});motion34_samples+=1
func _overlaps_hero__q34b(actor: Node3D,camera: Camera3D) -> bool:
	if not _is34(actor):return _overlaps_hero__chapterx(actor,camera)
	if camera==null or (actor.global_position-hero.global_position).dot(camera.global_basis.z)<=.04:return false
	var rig: Skeleton3D=actor.get_meta("minion19").skeleton
	var a := camera.unproject_position(_bone_point(rig,"ORG-spine"));var b := camera.unproject_position(_bone_point(rig,"ORG-head"))
	var ha := camera.unproject_position(hero.global_position+Vector3.UP*.32);var hb := camera.unproject_position(hero.global_position+Vector3.UP*1.95)
	var nearest := Geometry2D.get_closest_points_between_segments(a,b,ha,hb)
	var radius := _screen_radius(camera,actor.global_position+Vector3.UP,.36)+_screen_radius(camera,hero.global_position+Vector3.UP,.32)
	return nearest[0].distance_squared_to(nearest[1])<radius*radius

func _disarm34(node: Node) -> void:
	# Remove the render instance base before freeing its material overrides.
	if node is MeshInstance3D:node.mesh=null
	for child in node.get_children():_disarm34(child)

# ---- chapter1/view/chapter_actors_quality36.gd ----
## Shock holds the currently displayed paid pose; cold/death keep their own rules.
var stun36_pose_holds := 0
func _update_pose__q36(actor: Node3D,direction: Vector2,moving: bool,casting: bool,dead: bool,tick: int,playing: bool,hit: bool=false,brief_cast: bool=false) -> void:
	if not dead:
		var entity := _entity(actor)
		if not entity.is_empty() and entity.hp_raw>0 and tick<int(entity.get("stunned_until",0)):
			stun36_pose_holds+=1
			return
	_update_pose__q34b(actor,direction,moving,casting,dead,tick,playing,hit,brief_cast)

# ---- chapter1/view/chapter_actors_quality42.gd ----
## Unconnected successor: preserve Actor36 sampling; avoid identical walker commands.
## Engine equivalence/performance gate must pass before product assembly adoption.
func _update_pose(actor: Node3D,direction: Vector2,moving: bool,casting: bool,dead: bool,tick: int,playing: bool,hit: bool=false,brief_cast: bool=false) -> void:
	if not _is34(actor):
		_update_pose__q36(actor,direction,moving,casting,dead,tick,playing,hit,brief_cast);return
	if not dead:
		var entity := _entity(actor)
		if not entity.is_empty() and entity.hp_raw>0 and tick<int(entity.get("stunned_until",0)):
			stun36_pose_holds+=1
			return
	var e := _entity(actor)
	if e.is_empty():return
	var state: Dictionary=actor.get_meta("minion19")
	if not playing and not dead and not String(state.clip).is_empty():return
	if e.state=="recover":direction=e.attack_direction
	if playing and direction.length_squared()>.001:actor.rotation.y=lerp_angle(actor.rotation.y,atan2(direction.x,direction.y),1-exp(-_render_delta*18))
	var fraction := clampf(Engine.get_physics_interpolation_fraction(),0,1) if playing else 0.0
	var clip := "idle";var time_ := 0.0
	if dead:
		clip="death"
		if view.run.mode not in ["paused","choice","inventory","equipment"]:state.death_age=maxf(float(state.death_age)+_render_delta,float(tick-int(e.dead_tick))/60.0)
		time_=minf(float(state.death_age),1.60)
	elif e.state=="windup":
		var duration: int=e.get("definition",{}).get("windup",view.run.ENEMY_DEFS[e.kind].windup)
		var left := maxf(0,float(int(e.state_until)-tick)-fraction)
		clip="attack_slam";time_=clampf(1-left/float(maxi(1,duration)),0,1)*STRIKE34
	elif e.state=="recover" and _demon19_attacks.has(e.id):
		var paid: Dictionary=_demon19_attacks[e.id]
		var extension := maxi(0,int(e.state_until)-int(paid.end))
		var duration: int=e.get("definition",{}).get("recover",view.run.ENEMY_DEFS[e.kind].recover)
		var progress := clampf((float(tick-int(paid.tick)-extension)+fraction)/float(maxi(1,duration)),0,1)
		clip="attack_slam";time_=STRIKE34+progress*(SWING34-STRIKE34)
	elif moving:
		clip="walk"
		var sample: Dictionary=actor.get_meta("motion_sample",{})
		time_=fposmod(float(sample.get("phase",0.0))+float((int(e.id)*37)%101)/101.0,1)*WALK34
	else:time_=fposmod(float(tick)/60.0+float(e.id)*.113,128.0/60.0)
	var near_: bool=e.position.distance_squared_to(view.run.hero.position)<30.25
	var bucket: int=tick/3
	if moving and not hit and not near_ and state.clip==clip and int(state.bucket)==bucket:return
	state.clip=clip;state.bucket=bucket
	var target_scale := Vector3.ONE*(.60+float(posmod(int(e.id)*17+int(e.generation)*7,4))*.015)
	if state.model.scale!=target_scale:state.model.scale=target_scale
	# Read actual player state: setup/pool reuse can leave state.clip stale.
	# seek(update=true) evaluates every paid sample, including hit restoration.
	if state.player.current_animation!=clip or not state.player.is_playing():state.player.play(clip,0)
	state.player.seek(time_,true)
	if playing and not dead and hit and e.state in ["move","idle"] and not _hit34_frames.is_empty():
		var age := clampf(float(tick-int(_enemy_hit_until.get(e.id,tick))+12)/12.0,0,1)
		var weight := .85*sin(PI*age);var sample_ := age*12.0;var a := mini(int(sample_),12);var b := mini(a+1,12)
		for i in _hit34_indices.size():
			var index: int=_hit34_indices[i]
			var pose: Transform3D=_hit34_frames[a][i].interpolate_with(_hit34_frames[b][i],sample_-float(a))
			state.skeleton.set_bone_pose(index,state.skeleton.get_bone_pose(index).interpolate_with(pose,weight))
		hit34_blends+=1
	if _head34>=0:state.skeleton.set_bone_pose_scale(_head34,Vector3.ONE*.72)
	actor.set_meta("minion19_pose",{"clip":clip,"time":time_,"dead":dead,"tick":tick,"family34":true});motion34_samples+=1

## This override becomes active for Demon19/Role21 only after explicit parent
## candidate adoption. Legacy parents never call this hook.
func _sample_actor42(player: AnimationPlayer,clip: String,time_: float) -> void:
	_flush_lazy30()
	if player.current_animation!=clip or not player.is_playing():player.play(clip,0)
	player.seek(time_,true)

var _overlap42_active := false
var _overlap42_ready := false
var _overlap42_camera_id := 0
var _overlap42_hero_a := Vector2.ZERO
var _overlap42_hero_b := Vector2.ZERO
var _overlap42_hero_radius := 0.0
func sync(run: RefCounted,delta: float) -> void:
	# Lazy fill occurs after Cloister.sync writes the interpolated hero position.
	_overlap42_ready=false
	_overlap42_camera_id=0
	_overlap42_active=true
	frame_keys.clear();_entities.clear()
	for e in run.enemies.values():
		var key: String="%d:%d"%[e.generation,e.id]
		frame_keys[e.id]=key;_entities[key]=e
	sync__q25b(run,delta)
	_overlap42_active=false
	_overlap42_ready=false
	_overlap42_camera_id=0
const OVERLAP_CULL_SQ := 30.25
const OVERLAP_CULL_MIN_SIN := .70
func _overlaps_hero(actor: Node3D,camera: Camera3D) -> bool:
	# Preserve all boss/sprite paths and out-of-sync calls verbatim.
	if not _overlap42_active or not actor.has_meta("minion19"):return _overlaps_hero__q34b(actor,camera)
	if camera==null:return false
	var offset := actor.global_position-hero.global_position
	if offset.dot(camera.global_basis.z)<=.04:return false
	# Cheap reject before any bone is read. With the steep orthographic camera a body
	# whose root is farther than OVERLAP_CULL_SQ (horizontal) from the owner cannot
	# reach the owner's screen capsule: the owner's capsule is 1.95m tall and a point
	# d metres nearer the camera shifts down the screen by d*sin(pitch).
	if camera.projection==Camera3D.PROJECTION_ORTHOGONAL and camera.global_basis.z.y>=OVERLAP_CULL_MIN_SIN and offset.x*offset.x+offset.z*offset.z>OVERLAP_CULL_SQ:return false
	if _overlap42_ready and _overlap42_camera_id!=camera.get_instance_id():return _overlaps_hero__q34b(actor,camera)
	var state: Dictionary=actor.get_meta("minion19")
	var rig: Skeleton3D=state.skeleton
	var walker := _is34(actor)
	var a := camera.unproject_position(_bone_point(rig,"ORG-spine" if walker else "Spine1"))
	var b := camera.unproject_position(_bone_point(rig,"ORG-head" if walker else "Head"))
	if not _overlap42_ready:
		_overlap42_hero_a=camera.unproject_position(hero.global_position+Vector3.UP*.32)
		_overlap42_hero_b=camera.unproject_position(hero.global_position+Vector3.UP*1.95)
		_overlap42_hero_radius=_screen_radius(camera,hero.global_position+Vector3.UP,.32)
		_overlap42_camera_id=camera.get_instance_id()
		_overlap42_ready=true
	var nearest := Geometry2D.get_closest_points_between_segments(a,b,_overlap42_hero_a,_overlap42_hero_b)
	var radius := _screen_radius(camera,actor.global_position+Vector3.UP,.36 if walker else .42)+_overlap42_hero_radius
	return nearest[0].distance_squared_to(nearest[1])<radius*radius

func reset() -> void:
	_overlap42_active=false
	_overlap42_ready=false
	_overlap42_camera_id=0
	reset__q25b()

func _set_color42(material: StandardMaterial3D,color: Color) -> void:
	if material.albedo_color!=color:material.albedo_color=color
