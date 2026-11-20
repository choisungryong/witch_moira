extends RefCounted
## Flattened by tools/dev/flatten_chain.py from chapter1/view/chapter_world_quality51.gd.
## Methods named x__tag are the earlier layers of x; calls between them were super calls.

# ---- chapter1/view/cloister_world_quality03.gd ----
## A ruined cloister composition. All props are decorative 2.5D art, not collision.
## ArrayMesh follows the documented 4.5 array/UV/color surface pattern:
## https://docs.godotengine.org/en/4.5/classes/class_arraymesh.html
const CAMERA_OFFSET := Vector3(11,19,14)
## The hero is the centre of the light (BENCHMARK-TRAILERS 2-5). Ground, grass and props share one falloff
## (hero_light.gdshaderinc): HERO_LIGHT_NEAR times brightness inside INNER metres, HERO_LIGHT_FAR times beyond OUTER.
## Lit models (enemies, hero, masonry) get the same shape from one OmniLight3D at the hero. Tune the look here.
const HERO_LIGHT_INNER := 3.5
const HERO_LIGHT_OUTER := 15.0
const HERO_LIGHT_NEAR := 1.4
const HERO_LIGHT_FAR := .82
const HERO_OMNI_ENERGY := 1.15
const HERO_OMNI_RANGE := 10.0
const HERO_OMNI_COLOR := Color("ffe3bd")
const ART_BASE := "res://chapter1/art/quality03/"
var root: Node3D
var camera: Camera3D
var art_status: Dictionary={"ground":[],"props":0,"raw_texture_fallbacks":[]}
var _rng := RandomNumberGenerator.new()
var _prop_defs: Dictionary={}
var _prop_texture: Texture2D
var _prop_textures: Dictionary={}
var _prop_entries: Array[Dictionary]=[]
var _prop_materials: Array[ShaderMaterial]=[]
var _light_materials: Array[ShaderMaterial]=[]
var _hero_omni: OmniLight3D
var _warm_lights: Array[OmniLight3D]=[]
var _warm_base: Array[float]=[]
var _age := 0.0
var _camera_trauma := 0.0
var _reduced_motion := false
var _camera_base := CAMERA_OFFSET

func material(color: Color, emission: float=0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color=color;mat.roughness=.96
	if emission>0:
		mat.emission_enabled=true;mat.emission=color;mat.emission_energy_multiplier=emission
	return mat

func setup__q03(view: Node3D) -> void:
	_rng.seed=730113
	root=Node3D.new();root.name="CloisterWorldQuality03";view.add_child(root)
	var environment := Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color("0e141a")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("8594a6")
	# Look 2 (2026-11-18, BENCHMARK-TRAILERS 3): a dark floor, so that spells and torches carry the light.
	environment.ambient_light_energy=.11
	environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled=true;environment.glow_intensity=.45;environment.glow_bloom=.13
	environment.fog_enabled=true;environment.fog_light_color=Color("162027");environment.fog_density=.0025
	var environment_node := WorldEnvironment.new();environment_node.environment=environment;view.add_child(environment_node)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees=Vector3(-54,-34,0);moon.light_color=Color("b7c5d7");moon.light_energy=.46
	# There are no solid 3D casters in this decorative impostor scene. Actors use
	# their bounded contact-shadow batch; props retain their authored shading.
	moon.shadow_enabled=false;view.add_child(moon)
	var floor_mesh := PlaneMesh.new();floor_mesh.size=Vector2(82,82)
	var floor_node := MeshInstance3D.new();floor_node.mesh=floor_mesh;floor_node.position.y=-.05
	floor_node.material_override=_ground_material();floor_node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(floor_node)
	_load_props()
	_compose_cloister()
	_bake_props()
	_bake_contact_shadows()
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=24.0
	view.add_child(camera);camera.position=CAMERA_OFFSET;camera.look_at(Vector3.ZERO);camera.current=true
	print("CHAPTER1_WORLD_ART ",JSON.stringify(art_status))

func _texture(path: String) -> Texture2D:
	var result: Texture2D
	if ResourceLoader.exists(path,"Texture2D"):result=ResourceLoader.load(path,"Texture2D") as Texture2D
	if result==null and FileAccess.file_exists(path):
		var source := Image.load_from_file(ProjectSettings.globalize_path(path))
		if source:
			result=ImageTexture.create_from_image(source)
			art_status.raw_texture_fallbacks.append(path)
	if result:
		var image := result.get_image()
		if image and not image.has_mipmaps():
			if image.is_compressed():image.decompress()
			image.generate_mipmaps();result=ImageTexture.create_from_image(image)
	return result


func _load_props() -> void:
	_load_prop_doc(ART_BASE+"cloister_props_v01.json")
	_load_prop_doc(ART_BASE+"cloister_foliage_v01.json")

func _load_prop_doc(path: String) -> void:
	if not FileAccess.file_exists(path):return
	var doc: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not doc is Dictionary:return
	var texture_path := String(doc.get("texture",ART_BASE+"cloister_props_v01.png"))
	var texture := _texture(texture_path)
	if texture==null:return
	if _prop_texture==null:_prop_texture=texture
	_prop_textures[texture_path]=texture
	for prop in doc.get("props",[]):
		if prop is Dictionary and prop.has("id") and prop.has("region") and prop.has("feet"):
			prop._atlas=texture_path;_prop_defs[String(prop.id)]=prop

func _prop__q03(id_: String, at: Vector3, height: float=0.0, tint: Color=Color.WHITE, mirror: bool=false) -> void:
	if not _prop_defs.has(id_):return
	var record: Dictionary=_prop_defs[id_]
	_prop_entries.append({"id":id_,"at":at,"height":height if height>0 else float(record.get("height_m",1.0)),"tint":tint,"mirror":mirror})


func _paving_distance(at: Vector2) -> float:
	# Match the three authored ground regions; keep the central paths open.
	var court := maxf(absf(at.x)-6.5,absf(at.y+1.0)-8.0)
	var nave := absf(at.x+sin(at.y*.16)*.45)-3.45
	var crossing := absf(at.y+2.0+sin(at.x*.14)*.3)-2.95
	return minf(court,minf(nave,crossing))


func _brazier(at: Vector3) -> void:
	_prop("brazier",at,2.0,Color(.88,.8,.67))
	var light := OmniLight3D.new();light.position=at+Vector3.UP*1.5
	light.light_color=Color("ffad66");light.light_energy=4.5;light.omni_range=7.0;light.shadow_enabled=false
	root.add_child(light);_warm_lights.append(light);_warm_base.append(2.8)

func _bake_props() -> void:
	if _prop_texture==null or _prop_entries.is_empty():return
	var surfaces := 0
	for path in _prop_textures:
		var group: Array[Dictionary]=[]
		for entry in _prop_entries:
			if _prop_defs[entry.id]._atlas==path:group.append(entry)
		if group.is_empty():continue
		_bake_prop_surface(group,_prop_textures[path],"AuthoredCloisterProps" if surfaces==0 else "AuthoredCloisterFoliage")
		surfaces+=1
	art_status.props=_prop_entries.size();art_status.prop_surfaces=surfaces;art_status.prop_types=_prop_defs.keys()

func _bake_prop_surface__q03(entries: Array[Dictionary], texture: Texture2D, label: String) -> void:
	var verts := PackedVector3Array();var uvs := PackedVector2Array();var colors := PackedColorArray()
	var forward := CAMERA_OFFSET.normalized()
	var right := Vector3.UP.cross(forward).normalized()
	var up := forward.cross(right).normalized()
	var texture_size := Vector2(texture.get_width(),texture.get_height())
	for entry in entries:
		var record: Dictionary=_prop_defs[entry.id]
		var region: Array=record.region;var feet: Array=record.feet
		var scale_: float=float(entry.height)/float(region[3])
		var width: float=float(region[2])*scale_
		var left: float=-float(feet[0])*scale_;var bottom: float=-(float(region[3])-float(feet[1]))*scale_
		if entry.mirror:left=-width-left
		var corners := [entry.at+right*left+up*bottom,entry.at+right*(left+width)+up*bottom,entry.at+right*(left+width)+up*(bottom+float(entry.height)),entry.at+right*left+up*(bottom+float(entry.height))]
		var uv_min := (Vector2(region[0],region[1])+Vector2.ONE*.5)/texture_size
		var uv_max := (Vector2(region[0]+region[2],region[1]+region[3])-Vector2.ONE*.5)/texture_size
		var u0: float=uv_max.x if entry.mirror else uv_min.x
		var u1: float=uv_min.x if entry.mirror else uv_max.x
		var texcoords := [Vector2(u0,uv_max.y),Vector2(u1,uv_max.y),Vector2(u1,uv_min.y),Vector2(u0,uv_min.y)]
		for index in [0,1,2,0,2,3]:
			var tint: Color=entry.tint
			tint.a=1.0 if float(entry.height)>1.0 and not entry.get("solid",false) else 0.0
			verts.append(corners[index]);uvs.append(texcoords[index]);colors.append(tint)
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=verts;arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_COLOR]=colors
	var shape := ArrayMesh.new();shape.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var mat := ShaderMaterial.new();mat.shader=load("res://chapter1/view/cloister_props_quality03.gdshader");mat.set_shader_parameter("atlas_texture",texture)
	_prop_materials.append(mat);_register_light_material(mat)
	var node := MeshInstance3D.new();node.name=label;node.mesh=shape;node.material_override=mat
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(node)

func _bake_contact_shadows__q03() -> void:
	if _prop_entries.is_empty():return
	var verts := PackedVector3Array();var uvs := PackedVector2Array();var colors := PackedColorArray()
	for entry in _prop_entries:
		var record: Dictionary=_prop_defs[entry.id]
		var width: float=float(record.region[2])/float(record.region[3])*float(entry.height)
		var sx := clampf(width*.42,.16,1.4)
		var sz := clampf(float(entry.height)*.12,.12,.66)
		var at: Vector3=entry.at;at.y=.001
		var corners := [at+Vector3(-sx,0,-sz),at+Vector3(sx,0,-sz),at+Vector3(sx,0,sz),at+Vector3(-sx,0,sz)]
		var coordinates := [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]
		for index in [0,1,2,0,2,3]:
			verts.append(corners[index]);uvs.append(coordinates[index]);colors.append(Color(1,1,1,.38 if entry.height>1 else .2))
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=verts;arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_COLOR]=colors
	var shape := ArrayMesh.new();shape.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node := MeshInstance3D.new();node.name="CloisterPropContactShadows";node.mesh=shape
	var mat := ShaderMaterial.new();mat.shader=load("res://chapter1/view/cloister_contact_quality03.gdshader");node.material_override=mat
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(node)
	art_status.contact_shadows=_prop_entries.size()

func kick_camera(strength: float) -> void:
	if not _reduced_motion:_camera_trauma=minf(.9,_camera_trauma+clampf(strength,0,1)*.35)

func set_reduced_motion(value: bool) -> void:
	_reduced_motion=value
	if value:_camera_trauma=0

func update_camera__q03(hero: Vector2, delta: float) -> void:
	_age+=delta
	_camera_trauma=maxf(0,_camera_trauma-delta*5)
	var target := Vector3(hero.x,0,hero.y)
	for mat in _prop_materials:mat.set_shader_parameter("hero_position",Vector2(hero.x,hero.y))
	_move_hero_light(hero)
	var desired := target+CAMERA_OFFSET
	# Derive an unshaken base from the target; feedback never accumulates drift.
	_camera_base=_camera_base.lerp(desired,1.0-exp(-delta*8.0))
	var base: Vector3=_camera_base
	var displacement := Vector3(sin(_age*79.0),0,cos(_age*67.0))*.045*_camera_trauma
	camera.position=base+displacement;camera.look_at(base-CAMERA_OFFSET+displacement)
	for i in _warm_lights.size():
		_warm_lights[i].light_energy=_warm_base[i]*(.96+sin(_age*4.7+float(i)*2.1)*.025)

# ---- chapter1/view/chapter_world.gd ----
## Three authored connected spaces. Decorative walls never occupy walkable cells.
var gates: Array[Node3D]=[]
var seals: Array[MeshInstance3D]=[]
var ritual_labels: Dictionary={}
var route: MeshInstance3D

func setup__chapter(view: Node3D) -> void:
	setup__q03(view)
	var floor_: MeshInstance3D=root.get_child(0)
	(floor_.mesh as PlaneMesh).size=Vector2(160,70);floor_.position.x=48
	for i in 3:
		var ring := _ring(Vector3(i*48,.035,0),4.0,4.08,Color("d8b46a"));seals.append(ring)
		_ring(Vector3(i*48,.035,0),3.5,3.53,Color("6e5c3a"))
		for side in [-1,1]:
			for step in 6:
				var marker := MeshInstance3D.new();var box := BoxMesh.new();box.size=Vector3(.12,.025,.35);marker.mesh=box
				marker.material_override=material(Color("927a52"),.15);marker.position=Vector3(i*48+side*3.9,.03,-2.0+step*.8);root.add_child(marker)
	for i in 2:
		var gate := Node3D.new();gate.position=Vector3(19+i*48,0,0);root.add_child(gate);gates.append(gate)
		for z in 7:
			var bar := MeshInstance3D.new();var mesh := BoxMesh.new();mesh.size=Vector3(.10,2.6,.045);bar.mesh=mesh;bar.material_override=material(Color("ae8750"),.7);bar.position=Vector3(0,1.3,-3+z);gate.add_child(bar)
		var text := Label3D.new();text.text="봉인을 해제하면 열립니다";text.position=Vector3(0,3.0,0);text.pixel_size=.009;text.font_size=32;text.billboard=BaseMaterial3D.BILLBOARD_ENABLED;gate.add_child(text)
	for def in view.run.RITUALS:
		_ring(Vector3(def.position.x,.04,def.position.y),2.2,2.28,Color("79604f"))
		var label := Label3D.new();label.position=Vector3(def.position.x,1.3,def.position.y);label.pixel_size=.008;label.font_size=30;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		label.text=Loc.t("ritual.%s.name"%def.id)+"\n[E] 의식 시작";root.add_child(label);ritual_labels[def.id]=label
	route=MeshInstance3D.new();var arrow := PrismMesh.new();arrow.size=Vector3(.45,.035,.7);route.mesh=arrow;route.material_override=material(Color("c5a367"),.3);root.add_child(route)


func _compose_cloister() -> void:
	art_status.composition_revision="full-chapter-three-courtyards-01"
	# Graveyard, broken nave, circular sanctuary use different silhouettes/layouts.
	_prop("arch",Vector3(0,0,-21),6.5,Color(.74,.80,.87))
	for side in [-1.0,1.0]:
		for x in [-16,-8,0,8,16]:
			_prop("grave_cross" if x<0 else "grave_slab",Vector3(x,0,side*20.2),1.35,Color(.75,.8,.83))
			_prop("wall",Vector3(x,0,side*22),2.0,Color(.61,.68,.73))
		_prop("tree",Vector3(-22,0,side*18),5.7,Color(.64,.72,.76),side>0)
		_prop("pillar_broken",Vector3(19.8,0,side*5.2),3.2)
		for x in [31,40,48,56,65]:
			_prop("pillar_whole" if x in [31,65] else "pillar_broken",Vector3(x,0,side*20.7),4.4,Color(.78,.75,.76))
			_prop("wall",Vector3(x,0,side*23),3.0,Color(.69,.67,.7))
		for x in [21,26,69,74]:_prop("pillar_broken",Vector3(x,0,side*4.6),2.5,Color(.75,.72,.72))
		for x in [48,60,84,108]:_brazier(Vector3(x,0,side*19.8))
	_prop("arch",Vector3(48,0,-23),8.2,Color(.73,.70,.75))
	for i in 14:
		var a := TAU*i/14.0;var at := Vector3(96+cos(a)*21.5,0,sin(a)*21.5)
		# Leave the west corridor visibly open.
		if at.x<77 and absf(at.z)<6:continue
		_prop("pillar_whole" if i%3 else "pillar_broken",at,5.2,Color(.69,.73,.81))
	_prop("arch",Vector3(96,0,-24),9.0,Color(.65,.71,.81))
	for at in [Vector3(33,0,-16),Vector3(63,0,15),Vector3(88,0,-17),Vector3(109,0,14),Vector3(-12,0,16)]:
		_prop("rubble",at,.65,Color(.77,.75,.72));_prop("roots",at+Vector3(1,0,.5),.50,Color(.59,.65,.61))
	_compose_verges()
	# Sparse growth in the nave; sanctuary leaves broad ash paving visible.
	for i in 100:
		var side := -1 if i%2 else 1
		_prop("grass_bent" if i%3 else "fern_moss",Vector3(_rng.randf_range(30,65),.005,side*_rng.randf_range(14,21)),_rng.randf_range(.28,.5),Color(.7,.68,.6),i%2==0)
	_compose_edges()

func _ring(at: Vector3,inner: float,outer: float,color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new();var mesh := TorusMesh.new();mesh.inner_radius=inner;mesh.outer_radius=outer;mesh.rings=64;mesh.ring_segments=6
	node.mesh=mesh;node.scale.y=.12;node.position=at;node.material_override=material(color,.14);root.add_child(node);return node

func sync__chapter(run: RefCounted,_delta: float) -> void:
	if run.hero.is_empty():return
	for i in gates.size():gates[i].visible=run.zone<=i
	for i in seals.size():
		var mat: StandardMaterial3D=seals[i].material_override
		mat.albedo_color=Color("9c8352") if run.seals[i].cleared else (Color("d8b46a") if i==run.zone else Color("4a4538"))
	for def in run.RITUALS:
		var state: Dictionary=run.rituals[def.id];var label: Label3D=ritual_labels[def.id]
		var text: String=Loc.t("ritual.%s.name"%def.id)
		if state.state=="ready":text+="\n[E] 의식 시작"
		elif state.state=="active":text+="\n%d / %d"%[state.progress/60 if def.kind=="hold" else state.progress,25 if def.kind=="hold" else 60]
		elif state.state=="completed":text+="\n의식 완료"
		else:text+="\n의식 종료"
		label.text=text;label.visible=run.hero.position.distance_squared_to(def.position)<12*12
	var objective: Dictionary=run.objective();route.visible=not objective.entered and run.mode=="playing"
	if route.visible:
		var direction: Vector2=(objective.destination-run.hero.position).normalized()
		route.position=Vector3(run.hero.position.x+direction.x*2.1,.08,run.hero.position.y+direction.y*2.1);route.rotation.y=atan2(direction.x,direction.y)

# ---- chapter1/view/chapter_world_quality10.gd ----
## Independent geometric grasses: narrow tapered blades, open paving and quiet values.
## Decorative only; all Chapter09 collision and objectives stay in the core.
var _grass_material: ShaderMaterial
var _grass_vertices := PackedVector3Array()
var _grass_normals := PackedVector3Array()
var _grass_colors := PackedColorArray()
var _grass_uv := PackedVector2Array()
var _grass_blades := 0

## Ground, grass and props use the shared hero light field. Written once here; the hero position every frame.
func _register_light_material(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("hero_lit",Vector4(0,0,HERO_LIGHT_INNER,HERO_LIGHT_OUTER))
	mat.set_shader_parameter("hero_lit_level",Vector2(HERO_LIGHT_NEAR,HERO_LIGHT_FAR))
	_light_materials.append(mat)

func _move_hero_light(hero: Vector2) -> void:
	var lit := Vector4(hero.x,hero.y,HERO_LIGHT_INNER,HERO_LIGHT_OUTER)
	for mat in _light_materials:mat.set_shader_parameter("hero_lit",lit)
	if _hero_omni!=null:_hero_omni.position=Vector3(hero.x,2.6,hero.y)

## Effect lights (combat_juice) lift the darkness where they reach: 6 x (x, z, reach, strength). Called only when it changed.
func set_spell_lights(data: PackedVector4Array) -> void:
	for mat in _light_materials:mat.set_shader_parameter("spell_lit",data)

func setup__q10(view: Node3D) -> void:
	setup__chapter(view)
	_bake_grass()
	_hero_omni=OmniLight3D.new();_hero_omni.name="HeroLight";_hero_omni.light_color=HERO_OMNI_COLOR
	_hero_omni.light_energy=HERO_OMNI_ENERGY;_hero_omni.omni_range=HERO_OMNI_RANGE;_hero_omni.omni_attenuation=1.3;_hero_omni.shadow_enabled=false
	root.add_child(_hero_omni)
	for child in view.get_children():
		if child is DirectionalLight3D:child.shadow_enabled=true;child.light_cull_mask=3

func _ground_material() -> Material:
	var mat := ShaderMaterial.new();mat.shader=preload("res://chapter1/view/chapter_ground_quality10.gdshader")
	for pair in [["flagstone","ground_flagstone_v01.png"],["soil","ground_soil_v01.png"]]:
		var texture := _texture(ART_BASE+pair[1])
		if texture:mat.set_shader_parameter(pair[0],texture);mat.set_shader_parameter("has_"+pair[0],true);art_status.ground.append(pair[1])
	_register_light_material(mat);_edge_apply(mat)
	return mat

func _prop__q10(id_: String,at: Vector3,height: float=0.0,tint: Color=Color.WHITE,mirror: bool=false) -> void:
	if _prop_defs.has(id_) and String(_prop_defs[id_]._atlas).ends_with("cloister_foliage_v01.png"):return
	_prop__q03(id_,at,height,tint,mirror)

func _compose_verges() -> void:
	var patches := 0
	for zone in 3:
		var candidates: Array[Dictionary]=[]
		for gx in range(-24,25):
			for gz in range(-24,25):
				var local := Vector2(gx*.93+_rng.randf_range(-.27,.27),gz*.93+_rng.randf_range(-.27,.27))
				var distance_ := _paving_distance(local)
				if zone==1:distance_=maxf(absf(local.x)-12.8,absf(local.y)-15.0)
				elif zone==2:distance_=local.length()-17.8
				if distance_<.45 or distance_>4.2:continue
				# Keep both horizontal passages and the breathing gaps between beds.
				if absf(local.y)<4.0 or sin(local.x*.47+local.y*.15)+cos(local.y*.51-local.x*.13)<-.75:continue
				candidates.append({"at":local+Vector2(zone*48,0),"priority":_rng.randf()+distance_*.08})
		candidates.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a.priority<b.priority)
		var limit := mini([330,125,90][zone],candidates.size())
		for i in limit:
			var center: Vector2=candidates[i].at
			var patch_height := _rng.randf_range(.50,.95) if zone==0 else _rng.randf_range(.32,.67)
			var tint := Color("5c6544") if zone==0 else (Color("615e43") if zone==1 else Color("515858"))
			for blade in _rng.randi_range(16,26):
				var angle := _rng.randf_range(0,TAU)
				var spread := sqrt(_rng.randf())*.38
				var foot := Vector3(center.x+cos(angle)*spread,.0,center.y+sin(angle)*spread*.72)
				_blade(foot,patch_height*_rng.randf_range(.48,1.14),_rng.randf_range(.022,.046),_rng.randf_range(0,TAU),tint*_rng.randf_range(.68,1.12))
			patches+=1
	art_status.foliage_quads=0;art_status.grass_patches=patches;art_status.grass_blades=_grass_blades
	art_status.composition_revision="full-chapter-tapered-grass-10"

func _blade(foot: Vector3,height: float,width: float,angle: float,tint: Color) -> void:
	var right := Vector3(cos(angle),0,sin(angle))
	var bend := Vector3(-sin(angle),0,cos(angle))*_rng.randf_range(.11,.32)
	for step in 3:
		var a := float(step)/3.0;var b := float(step+1)/3.0
		var p0 := foot+Vector3.UP*height*a+bend*a*a
		var p1 := foot+Vector3.UP*height*b+bend*b*b
		var wa := width*(1.0-a)*(.8+.4*sin(a*PI))
		var wb := width*(1.0-b)*(.8+.4*sin(b*PI))
		var corners := [p0-right*wa,p0+right*wa,p1+right*wb,p1-right*wb]
		var normal := right.cross((p1-p0).normalized()).normalized()
		for k in [0,1,2,0,2,3]:
			var t := a if k<2 else b
			_grass_vertices.append(corners[k]);_grass_normals.append(normal)
			_grass_colors.append((tint*lerpf(.48,1.06,t)).srgb_to_linear());_grass_uv.append(Vector2(0,t))
	_grass_blades+=1

func _bake_grass() -> void:
	if _grass_vertices.is_empty():return
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=_grass_vertices;arrays[Mesh.ARRAY_NORMAL]=_grass_normals;arrays[Mesh.ARRAY_COLOR]=_grass_colors;arrays[Mesh.ARRAY_TEX_UV]=_grass_uv
	var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_grass_material=ShaderMaterial.new();_grass_material.shader=preload("res://chapter1/view/chapter_grass_quality10.gdshader");_register_light_material(_grass_material);_edge_apply(_grass_material)
	var node := MeshInstance3D.new();node.name="TaperedGrass";node.mesh=mesh;node.material_override=_grass_material;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(node)
	_grass_vertices.clear();_grass_normals.clear();_grass_colors.clear();_grass_uv.clear()
	print("CHAPTER1_GRASS_ART ",JSON.stringify({"patches":art_status.grass_patches,"blades":_grass_blades,"surfaces":1,"collision":false,"source":"independent code geometry"}))

func update_camera__q10(hero: Vector2,delta: float) -> void:
	update_camera__q03(hero,delta)
	if _grass_material:_grass_material.set_shader_parameter("age",_age)

# ---- chapter1/view/chapter_world_quality17.gd ----
## Solid foundations and broken piers outside the central combat lanes.
## Presentation only: no colliders, no changes to walkable cells or core RNG.
var depth_stones := 0
var _stones: Array[Dictionary]=[]
func setup__q17(view: Node3D) -> void:
	setup__q10(view)
	for zone in 3:
		for side in [-1,1]:
			for x in [-12,-4,5,13]:
				var at := Vector3(zone*48+x,0,side*21.4)
				_stone(at+Vector3(0,.14,0),Vector3(2.1,.28,1.7),Color("42484a"))
				_stone(at+Vector3(0,.38,0),Vector3(1.6,.22,1.3),Color("626762"))
				var height_ := .65+float(posmod(x+zone*3,4))*.26
				_stone(at+Vector3(0,.49+height_*.5,0),Vector3(.68,height_,.68),Color("585e59"))
				_stone(at+Vector3(.10,height_+.57,-.04),Vector3(.94,.16,.86),Color("72756a"))
			for x in [-9,0,9]:
				_stone(Vector3(zone*48+x,.18,side*22.8),Vector3(5.5,.36,1.1),Color("41484b"))
	art_status.depth_stones=depth_stones
	var column_shape := CylinderMesh.new();column_shape.top_radius=.43;column_shape.bottom_radius=.5;column_shape.height=1;column_shape.radial_segments=8;column_shape.rings=1
	var wall_shape := BoxMesh.new();wall_shape.size=Vector3.ONE
	var mat := StandardMaterial3D.new();mat.albedo_texture=_texture(ART_BASE+"ground_flagstone_v01.png")
	mat.vertex_color_use_as_albedo=true;mat.roughness=.96;mat.uv1_triplanar=true;mat.uv1_world_triplanar=true;mat.uv1_scale=Vector3.ONE*.7
	# Two bounded static batches per zone rather than a draw per stone.
	for zone in 3:
		for wall in [false,true]:
			var records: Array[Dictionary]=[]
			for i in 38:
				var record: Dictionary=_stones[zone*38+i]
				if record.wall==wall:records.append(record)
			var mm := MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.use_colors=true;mm.mesh=wall_shape if wall else column_shape;mm.instance_count=records.size()
			for i in records.size():mm.set_instance_transform(i,records[i].transform);mm.set_instance_color(i,records[i].tint)
			var node := MultiMeshInstance3D.new();node.multimesh=mm;node.material_override=mat;root.add_child(node)
func _stone(at: Vector3,dimensions: Vector3,tint: Color) -> void:
	var angle := sin(float(depth_stones)*1.7)*.065
	_stones.append({"transform":Transform3D(Basis(Vector3.UP,angle).scaled(dimensions),at),"tint":Color(tint.r*1.65,tint.g*1.65,tint.b*1.65,1),"wall":dimensions.x>3});depth_stones+=1

# ---- chapter1/view/chapter_world_quality18.gd ----
## Cover every legal camera target and the current viewport's ground footprint.
## Reuses the existing single plane and world-space terrain shader. No collision.
const GROUND_MARGIN := 3.0
var ground_coverage: Dictionary={}
var _coverage_viewport := Vector2.ZERO
var _coverage_camera_size := -1.0
var _coverage_floor: MeshInstance3D
func setup__q18(view: Node3D) -> void:
	setup__q17(view)
	_coverage_floor=root.get_child(0) as MeshInstance3D
	_ensure_ground_coverage()
func update_camera(hero: Vector2,delta: float) -> void:
	update_camera__q10(hero,delta)
	_ensure_ground_coverage()
func _ensure_ground_coverage() -> void:
	if not is_instance_valid(_coverage_floor) or camera==null:return
	var viewport_size := camera.get_viewport().get_visible_rect().size
	if viewport_size.x<=0 or viewport_size.y<=0:return
	if viewport_size==_coverage_viewport and is_equal_approx(camera.size,_coverage_camera_size):return
	var center := camera.position-CAMERA_OFFSET
	var minimum := Vector2(INF,INF);var maximum := Vector2(-INF,-INF)
	var plane := Plane(Vector3.UP,_coverage_floor.position.y)
	for x in [0.0,viewport_size.x]:
		for y in [0.0,viewport_size.y]:
			var hit: Variant=plane.intersects_ray(camera.project_ray_origin(Vector2(x,y)),camera.project_ray_normal(Vector2(x,y)))
			if not hit is Vector3:return
			var offset := Vector2(hit.x-center.x,hit.z-center.z)
			minimum=minimum.min(offset);maximum=maximum.max(offset)
	# Core bounds: three zone squares of half-size19, centers0/48/96.
	# Camera smoothing stays inside their outer convex rectangle. Margin also
	# covers the bounded camera shake without regenerating a mesh every frame.
	var lower := Vector2(-19,-19)+minimum-Vector2.ONE*GROUND_MARGIN
	var upper := Vector2(115,19)+maximum+Vector2.ONE*GROUND_MARGIN
	var mesh := _coverage_floor.mesh as PlaneMesh
	mesh.size=upper-lower
	_coverage_floor.position.x=(lower.x+upper.x)*.5;_coverage_floor.position.z=(lower.y+upper.y)*.5
	_coverage_viewport=viewport_size;_coverage_camera_size=camera.size
	ground_coverage={"viewport":viewport_size,"minimum":lower,"maximum":upper,"plane_size":mesh.size,"margin":GROUND_MARGIN,"draw_surfaces":mesh.get_surface_count()}

# ---- chapter1/view/chapter_world_quality22.gd ----
## Rear cloister masonry has real thickness, openings and cast shadows.
## Every new stone stays north of the legal arena; no collision/core changes.
var masonry22: Array[Dictionary]=[]
func _prop__q22(id_: String,at: Vector3,height: float=0.0,tint: Color=Color.WHITE,mirror: bool=false) -> void:
	if id_=="arch":return
	_prop__q10(id_,at,height,tint,mirror)
func setup__q22(view: Node3D) -> void:
	setup__q18(view)
	# The inherited foundation batch contains both sides. Retain the south
	# foundations; the authored rear colonnade replaces its northern stones.
	for child in root.get_children():
		if not child is MultiMeshInstance3D:continue
		var old: MultiMesh=child.multimesh
		var keep: Array[int]=[]
		for i in old.instance_count:
			if old.get_instance_transform(i).origin.z>0:keep.append(i)
		for i in keep.size():
			old.set_instance_transform(i,old.get_instance_transform(keep[i]))
			old.set_instance_color(i,old.get_instance_color(keep[i]))
		old.visible_instance_count=keep.size()
	var blocks: Array[Dictionary]=[]
	var wedges: Array[Dictionary]=[]
	for zone in 3:
		var center := Vector3(zone*48,3.1,-22.8)
		var tint := Color("7b8279") if zone==0 else (Color("817a76") if zone==1 else Color("78818a"))
		for side in [-1,1]:
			for row in 6:
				var at := center+Vector3(side*3.7,-2.85+row*.5,0)
				_add22(blocks,at,Vector3(.83,.47,1.10),0,tint,zone)
			_add22(blocks,center+Vector3(side*3.7,-3.0,0),Vector3(1.2,.20,1.4),0,tint*.78,zone)
			_add22(blocks,center+Vector3(side*3.7,-.08,0),Vector3(1.12,.25,1.35),0,tint*1.12,zone)
		for segment in 15:
			# Missing voussoirs distinguish a collapsed garden from the nave
			# and the intact sanctuary, instead of repeating one sprite.
			if zone==0 and segment in [6,7,8]:continue
			if zone==1 and segment in [3,4]:continue
			var angle := (float(segment)+.5)*PI/15.0
			var record := {"transform":Transform3D(Basis(Vector3.BACK,angle),center),"tint":tint*(.90+.14*sin(segment*2.3)),"zone":zone}
			wedges.append(record)
		for side in [-1,1]:
			for index in 3:
				var x: float=side*(7.3+index*4.2)
				var height_ := 1.15+float(posmod(zone+index*2,4))*.48
				for row in int(ceil(height_/.46)):
					_add22(blocks,Vector3(zone*48+x,.23+row*.46,-22.5),Vector3(.85,.43,.95),sin(index+row)*.035,tint*.85,zone)
				_add22(blocks,Vector3(zone*48+x,.12,-22.5),Vector3(1.3,.24,1.5),0,tint*.73,zone)
			# Fallen stones lie behind the broken piers, outside walkable ground.
			for index in 4:
				_add22(blocks,Vector3(zone*48+side*(1.8+index*.9),.18,-24.1-index*.30),Vector3(.7,.34,.92),side*(.2+index*.31),tint*.86,zone)
	var box := BoxMesh.new();box.size=Vector3.ONE
	_batch22(blocks,box,"RearMasonry22")
	_batch22(wedges,_voussoir22(),"RearArches22")
	masonry22.append_array(blocks);masonry22.append_array(wedges)
	art_status.rear_masonry22=masonry22.size();art_status.rear_masonry_batches22=2
func _add22(records: Array[Dictionary],at: Vector3,size_: Vector3,angle: float,tint: Color,zone: int) -> void:
	records.append({"transform":Transform3D(Basis(Vector3.UP,angle).scaled(size_),at),"tint":tint,"zone":zone})
func _batch22__q22(records: Array[Dictionary],shape: Mesh,label: String) -> void:
	var mm := MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.use_colors=true;mm.mesh=shape;mm.instance_count=records.size()
	for i in records.size():
		mm.set_instance_transform(i,records[i].transform);mm.set_instance_color(i,records[i].tint*1.85)
	var material_ := StandardMaterial3D.new();material_.albedo_texture=_texture(ART_BASE+"ground_flagstone_v01.png")
	material_.vertex_color_use_as_albedo=true;material_.roughness=.97;material_.uv1_triplanar=true;material_.uv1_world_triplanar=true;material_.uv1_scale=Vector3.ONE*.7
	var node := MultiMeshInstance3D.new();node.name=label;node.multimesh=mm;node.material_override=material_;root.add_child(node)

# ---- chapter1/view/chapter_world_quality31.gd ----
## Unconnected volumetric column study. No core/colliders/lighting additions.
var columns31: Array[Dictionary]=[]
var _old_columns31: Array[Node3D]=[]
var _solid_columns31: Array[Node3D]=[]
var clearance31: Array[Dictionary]=[]
func _prop(id_: String,at: Vector3,height: float=0.0,tint: Color=Color.WHITE,mirror: bool=false) -> void:
	if id_ in ["pillar_whole","pillar_broken"]:columns31.append({"id":id_,"at":at,"height":height,"tint":tint})
	_prop__q22(id_,at,height,tint,mirror)
func _bake_prop_surface(entries: Array[Dictionary],texture: Texture2D,label: String) -> void:
	var pillars: Array[Dictionary]=[];var others: Array[Dictionary]=[]
	for entry in entries:
		if entry.id in ["pillar_whole","pillar_broken"]:pillars.append(entry)
		else:others.append(entry)
	if not others.is_empty():_bake_prop_surface__q03(others,texture,label)
	if not pillars.is_empty():
		_bake_prop_surface__q03(pillars,texture,"OriginalColumnImpostors31")
		_old_columns31.append(root.get_child(root.get_child_count()-1))
func _bake_contact_shadows() -> void:
	var all: Array[Dictionary]=_prop_entries
	var pillars: Array[Dictionary]=[];var others: Array[Dictionary]=[]
	for entry in all:
		if entry.id in ["pillar_whole","pillar_broken"]:pillars.append(entry)
		else:others.append(entry)
	_prop_entries=others
	if not others.is_empty():_bake_contact_shadows__q03()
	_prop_entries=pillars
	if not pillars.is_empty():
		_bake_contact_shadows__q03();_old_columns31.append(root.get_child(root.get_child_count()-1))
	_prop_entries=all;art_status.contact_shadows=all.size()
func setup__q31(owner: Node3D) -> void:
	setup__q22(owner)
	var whole: Array[Dictionary]=[];var broken: Array[Dictionary]=[]
	for i in columns31.size():
		var column: Dictionary=columns31[i];var definition: Dictionary=_prop_defs[column.id]
		var width: float=float(definition.region[2])/float(definition.region[3])*float(column.height)
		var radius := width*.5
		var at: Vector3=column.at
		var safe := _safe31(Vector2(at.x,at.z),radius)
		var adjusted := Vector3(safe.x,at.y,safe.y)
		clearance31.append({"original":Vector2(at.x,at.z),"at":safe,"radius":radius,"clearance":safe.distance_to(_nearest_legal31(safe)),"moved":safe.distance_to(Vector2(at.x,at.z))>.0001})
		var record := {"transform":Transform3D(Basis(Vector3.UP,float(i)*1.71).scaled(Vector3(radius,float(column.height)*1.30,radius)),adjusted),"tint":column.tint*Color(.86,.86,.80),"zone":roundi(at.x/48)}
		if column.id=="pillar_whole":whole.append(record)
		else:broken.append(record)
	for pair in [[whole,false,"SolidWholeColumns31"],[broken,true,"SolidBrokenColumns31"]]:
		if pair[0].is_empty():continue
		_batch22(pair[0],_column_mesh31(pair[1]),pair[2]);_solid_columns31.append(root.get_child(root.get_child_count()-1))
	art_status.solid_columns31=columns31.size();art_status.column_batches31=_solid_columns31.size()
	set_columns31(false)
func _nearest_legal31(point: Vector2) -> Vector2:
	var best := Vector2.ZERO;var distance := INF
	for zone in 3:
		var center := Vector2(zone*48,0)
		var candidate := point.clamp(center-Vector2.ONE*19,center+Vector2.ONE*19)
		var d := point.distance_squared_to(candidate)
		if d<distance:best=candidate;distance=d
		if zone>0:
			candidate=point.clamp(Vector2(center.x-29,-3.6),Vector2(center.x-19,3.6));d=point.distance_squared_to(candidate)
			if d<distance:best=candidate;distance=d
	return best
func _safe31(point: Vector2,radius: float) -> Vector2:
	for attempt in 24:
		var legal := _nearest_legal31(point);var delta := point-legal
		if delta.length()>=radius+.25:return point
		if delta.length_squared()>.0001:point+=delta.normalized()*(radius+.26-delta.length())
		else:
			var center := Vector2(clampi(roundi(point.x/48),0,2)*48,0)
			var direction := (point-center).normalized()
			if direction.length_squared()<.0001:direction=Vector2.UP
			point=center+direction*((19+radius+.35)/maxf(absf(direction.x),absf(direction.y)))
	return point
func _column_mesh31(broken: bool) -> ArrayMesh:
	var profile := [Vector2(0,1),Vector2(.035,1),Vector2(.055,.85),Vector2(.08,.85),Vector2(.105,.57),Vector2(.85,.51),Vector2(.88,.73),Vector2(.91,.73),Vector2(.935,1),Vector2(1,.92)]
	if broken:profile=[Vector2(0,1),Vector2(.06,1),Vector2(.10,.85),Vector2(.15,.57),Vector2(.92,.53),Vector2(1,.53)]
	var st := SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);st.set_smooth_group(0)
	var segments := 32
	for ring in profile.size()-1:
		for segment in segments:
			var points: Array[Vector3]=[]
			for corner in [[ring,segment],[ring,segment+1],[ring+1,segment+1],[ring+1,segment]]:
				var p: Vector2=profile[corner[0]];var angle: float=TAU*float(corner[1])/segments
				var radius: float=p.y*(1+.025*cos(angle*8)) if p.y<.7 else p.y
				var y: float=p.x
				if broken and corner[0]==profile.size()-1:y=.94+.055*sin(angle*3)+.018*cos(angle*7)
				points.append(Vector3(cos(angle)*radius,y,sin(angle)*radius))
			var normal := (points[2]-points[0]).cross(points[1]-points[0]).normalized()
			for index in [0,1,2,0,2,3]:
				st.set_normal(normal)
				st.set_color(Color.WHITE*(.94+.05*cos(float(segment)*.7+float(ring))))
				st.add_vertex(points[index])
	# Darker broken fracture cap, closed with upward-facing triangles.
	var top: float=profile[-1].x
	for segment in segments:
		var a := TAU*float(segment)/segments;var b := TAU*float(segment+1)/segments
		var ya := .94+.055*sin(a*3)+.018*cos(a*7) if broken else top
		var yb := .94+.055*sin(b*3)+.018*cos(b*7) if broken else top
		for point in [Vector3(0,.92 if broken else top,0),Vector3(cos(a)*profile[-1].y,ya,sin(a)*profile[-1].y),Vector3(cos(b)*profile[-1].y,yb,sin(b)*profile[-1].y)]:
			st.set_normal(Vector3.UP);st.set_color(Color.WHITE*(.72 if broken else 1.05));st.add_vertex(point)
	return st.commit()

# ---- chapter1/view/chapter_world_quality31b.gd ----
## Keep authored ornate column sprites; reuse hidden solids as shadow-only proxies.
## No relocation of visible props, added light, collider or core state.
func setup__q31b(owner: Node3D) -> void:
	setup__q31(owner)
	for node in _solid_columns31:
		var broken: bool=String(node.name).contains("Broken")
		var index := 0
		for column in columns31:
			if (column.id=="pillar_broken")!=broken:continue
			var transform: Transform3D=node.multimesh.get_instance_transform(index)
			transform.origin=column.at;node.multimesh.set_instance_transform(index,transform);index+=1
		assert(index==node.multimesh.instance_count)
		# Visible ornament and its existing near-foot contact are unchanged.
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	clearance31.clear()
	art_status.column_shadow_only31b=true
	set_columns31(false)
func set_columns31(enabled: bool) -> void:
	for node in _old_columns31:node.visible=true
	for node in _solid_columns31:node.visible=enabled

# ---- chapter1/view/chapter_world_quality31c.gd ----
## Narrower shadow silhouettes, retaining the original visible art and anchors.
func setup__q31c(owner: Node3D) -> void:
	setup__q31b(owner)
	for node in _solid_columns31:
		for index in node.multimesh.instance_count:
			var transform: Transform3D=node.multimesh.get_instance_transform(index)
			transform.basis=transform.basis.scaled(Vector3(.78,.88,.78))
			node.multimesh.set_instance_transform(index,transform)
	art_status.column_shadow_scale31c=Vector3(.78,.88,.78)

# ---- chapter1/view/chapter_world_quality31d.gd ----
## Product default for the reviewed narrower shadow-only proxies.
func setup__q31d(owner: Node3D) -> void:
	setup__q31c(owner)
	set_columns31(true)

# ---- chapter1/view/chapter_world_quality37c.gd ----
## Unconnected study:37b geometry, rear-only weathered material; proxies unchanged.
const Geometry37b=preload("res://chapter1/view/chapter_world_quality37b.gd")
var _stone_geometry37=Geometry37b.new()
func _voussoir22() -> ArrayMesh:
	return _stone_geometry37._voussoir22()
func _batch22(records: Array[Dictionary],shape: Mesh,label: String) -> void:
	var rear: bool=label in ["RearMasonry22","RearArches22"]
	if label=="RearMasonry22":
		var points: Array[Vector3]=[]
		for z in [-.5,.5]:
			for x in [-.5,.5]:
				for y in [-.5,.5]:points.append(Vector3(x,y,z))
		shape=_stone_geometry37._chamfer37(points,.07)
	_batch22__q22(records,shape,label)
	if not rear:return
	var material := ShaderMaterial.new()
	material.shader=preload("res://chapter1/view/chapter_masonry_quality37c.gdshader")
	material.set_shader_parameter("flagstone",_texture(ART_BASE+"ground_flagstone_v01.png"))
	material.set_shader_parameter("soil",_texture(ART_BASE+"ground_soil_v01.png"))
	var node: MultiMeshInstance3D=root.get_node(NodePath(label))
	node.material_override=material

# ---- A10 W4: the visible edge of the walkable ground (U-64) ----
## The core stops the hero at zone centre +-19 m (chapter_core.gd _clamp_point, read only; this file never writes it). EDGE_ROWS is the
## one place the picture is told where that edge is: the wall line, the dimmed ground outside it and the wall's mix all come from
## these rows. To extend to zone 1 or 2, add a row (centre, half, style, passages) and a style entry; nothing else holds a number.
## Pieces are the existing prop atlas (slot world.edge.props) scaled to 0.7-1.2 m, a footing course (slot world.edge.stone) and a
## few iron railing pieces drawn from boxes. Decorative only: no collision, no core state.
const EDGE_ROWS := [
	{"zone":0,"center":Vector2(0,0),"half":19.0,"offset":0.3,"style":"graveyard","window_x":Vector2(-200,29),
	 "passages":[{"side":"east","half_width":3.6,"reach":10.0,"opening":3.0}]},
]
## window_x: where this row owns the dimming of the ground (past it the next row's ground is left alone; 29 = where zone 1's walk area starts).
## passages: a walkable strip leaving the square. opening = half width kept free of wall (the sealed gate stands there); half_width and reach are the core's strip.
const EDGE_STYLES := {
	"graveyard":{"seed":640064,"gap_chance":.15,"rail_chance":.12,"slab_chance":.15,"cross_chance":.12,
		"height_near":Vector2(.72,.95),"height_far":Vector2(.9,1.2),"gap_len":Vector2(2.2,3.4),"rail_len":Vector2(2.4,3.6)},
}
## sunk = brightness left outside the walk area; reach = metres over which it falls; fog = amount of the cool fog mixed in.
const EDGE_LOOK := {"sunk":.34,"reach":1.8,"fog":.20,"fog_color":Color("1b2124")}
## out = away from the walk area, along = direction of the line, near = faces the camera (lower pieces so the hero's legs stay seen),
## mirror_wall = the wall sprite's diagonal must be flipped to run along this line on screen.
const EDGE_SIDES := {
	"north":{"out":Vector2(0,-1),"along":Vector2(1,0),"near":false,"mirror_wall":true},
	"south":{"out":Vector2(0,1),"along":Vector2(1,0),"near":true,"mirror_wall":true},
	"west":{"out":Vector2(-1,0),"along":Vector2(0,1),"near":false,"mirror_wall":false},
	"east":{"out":Vector2(1,0),"along":Vector2(0,1),"near":true,"mirror_wall":false},
}
const EDGE_SLOT_PROPS := "world.edge.props"
const EDGE_SLOT_STONE := "world.edge.stone"
const EdgeSlots=preload("res://chapter1/view/assets/asset_slots.gd")
var _edge_anchors: Array[Vector2]=[]
var _edge_blocks: Array[Dictionary]=[]
var _edge_iron: Array[Dictionary]=[]
var edge_stats: Dictionary={}

func edge_rows() -> Array:
	return EDGE_ROWS
## Foot points of everything placed on an edge line (for the capture tool's gap measure).
func edge_anchors() -> Array[Vector2]:
	var all: Array[Vector2]=_edge_anchors.duplicate()
	for gate in gates:
		for z in 7:all.append(Vector2(gate.position.x,gate.position.z-3.0+z))
	return all

func _edge_apply(mat: ShaderMaterial) -> void:
	var rects := PackedVector4Array();var wins := PackedVector4Array()
	for row in EDGE_ROWS:
		var c: Vector2=row.center;var h: float=row.half;var win: Vector2=row.window_x
		rects.append(Vector4(c.x-h,c.y-h,c.x+h,c.y+h));wins.append(Vector4(win.x,win.y,0,0))
		for passage in row.get("passages",[]):
			var side: Dictionary=EDGE_SIDES[passage.side];var out_: Vector2=side.out;var along: Vector2=side.along
			var a := c+out_*h-along*float(passage.half_width);var b := c+out_*(h+float(passage.reach))+along*float(passage.half_width)
			rects.append(Vector4(minf(a.x,b.x),minf(a.y,b.y),maxf(a.x,b.x),maxf(a.y,b.y)));wins.append(Vector4(win.x,win.y,0,0))
	assert(rects.size()<=8)
	var count := mini(rects.size(),8)
	while rects.size()<8:
		rects.append(Vector4.ZERO);wins.append(Vector4.ZERO)
	mat.set_shader_parameter("edge_count",count);mat.set_shader_parameter("edge_rect",rects);mat.set_shader_parameter("edge_win",wins)
	var fog: Color=(EDGE_LOOK.fog_color as Color).srgb_to_linear()
	mat.set_shader_parameter("edge_look",Vector4(EDGE_LOOK.sunk,EDGE_LOOK.reach,EDGE_LOOK.fog,0));mat.set_shader_parameter("edge_fog",Vector4(fog.r,fog.g,fog.b,1))

func _edge_at(row: Dictionary,side: Dictionary,t: float,extra: float=0.0) -> Vector2:
	var c: Vector2=row.center;var out_: Vector2=side.out;var along: Vector2=side.along
	return c+along*t+out_*(float(row.half)+float(row.offset)+extra)

## Screen width covered by one metre of the line (the camera sees a line along x or z foreshortened).
func _edge_screen_k(side: Dictionary) -> float:
	var right := Vector3.UP.cross(CAMERA_OFFSET.normalized()).normalized();var along: Vector2=side.along
	return maxf(.3,absf(right.x*along.x+right.z*along.y))

func _edge_sprite(id_: String,at: Vector2,height: float,mirror: bool,tint: Color) -> void:
	if not _prop_defs.has(id_):return
	_prop(id_,Vector3(at.x,0,at.y),height,tint,mirror)
	if not _prop_entries.is_empty() and _prop_entries[-1].id==id_:_prop_entries[-1]["solid"]=true
	_edge_anchors.append(at)

func _edge_sprite_width(id_: String,height: float) -> float:
	if not _prop_defs.has(id_):return height
	var region: Array=_prop_defs[id_].region
	return float(region[2])/float(region[3])*height

func _edge_block(side: Dictionary,t0: float,t1: float,row: Dictionary,height: float,depth: float,rng: RandomNumberGenerator) -> void:
	var along: Vector2=side.along
	var mid := (t0+t1)*.5
	var at := _edge_at(row,side,mid,depth*.5-.15)
	var angle := atan2(-along.y,along.x)+rng.randf_range(-.04,.04)
	var shade := rng.randf_range(.86,1.1)
	_edge_blocks.append({"transform":Transform3D(Basis(Vector3.UP,angle)*Basis.from_scale(Vector3(absf(t1-t0)+.08,height,depth)),Vector3(at.x,height*.5,at.y)),"tint":Color(.5*shade,.52*shade,.5*shade,1)*1.85})
	_edge_anchors.append(at)

func _edge_footing(side: Dictionary,t0: float,t1: float,row: Dictionary,low: bool,rng: RandomNumberGenerator) -> void:
	var t := t0
	while t<t1-.05:
		var len_ := minf(rng.randf_range(1.2,1.9),t1-t)
		var height := rng.randf_range(.10,.16) if low else rng.randf_range(.22,.42)
		_edge_block(side,t,t+len_,row,height,rng.randf_range(.5,.7),rng)
		t+=len_

func _edge_rail(side: Dictionary,t0: float,t1: float,row: Dictionary,rng: RandomNumberGenerator) -> void:
	var along: Vector2=side.along
	var angle := atan2(-along.y,along.x)
	var length_ := t1-t0
	var posts := int(ceil(length_/1.2))+1
	var step := length_/float(posts-1)
	var base := _edge_at(row,side,0.0,.25)
	var ink := Color(.16,.15,.14,1)
	for i in posts:
		var at := base+along*(t0+step*i)
		var lean := rng.randf_range(-.06,.06)
		_edge_iron.append({"transform":Transform3D(Basis(Vector3.UP,angle)*Basis(Vector3.BACK,lean)*Basis.from_scale(Vector3(.09,rng.randf_range(.95,1.1),.09)),Vector3(at.x,.5,at.y)),"tint":ink})
		_edge_iron.append({"transform":Transform3D(Basis(Vector3.UP,angle)*Basis.from_scale(Vector3(.16,.12,.16)),Vector3(at.x,1.06,at.y)),"tint":ink*1.3})
	var mid := base+along*((t0+t1)*.5)
	for height in [.38,.86]:
		_edge_iron.append({"transform":Transform3D(Basis(Vector3.UP,angle)*Basis.from_scale(Vector3(length_,.05,.05)),Vector3(mid.x,height,mid.y)),"tint":ink})
	var pickets := int(length_/.32)
	for i in pickets:
		if rng.randf()<.18:continue
		var at := base+along*(t0+(float(i)+.5)*length_/float(pickets))
		var tall := rng.randf_range(.6,.9)
		_edge_iron.append({"transform":Transform3D(Basis(Vector3.UP,angle)*Basis(Vector3.BACK,rng.randf_range(-.1,.1))*Basis.from_scale(Vector3(.035,tall,.035)),Vector3(at.x,tall*.5+.1,at.y)),"tint":ink*1.15})
	_edge_footing(side,t0,t1,row,true,rng)
	_edge_anchors.append(mid)

func _edge_gap(side: Dictionary,t0: float,t1: float,row: Dictionary,rng: RandomNumberGenerator) -> void:
	## A collapse: the course is low and a heap of fallen stone fills it, so the gap reads blocked, not open.
	_edge_footing(side,t0,t1,row,true,rng)
	var tint := Color(.52,.51,.5)
	var t := t0+.5
	var k := _edge_screen_k(side)
	while t<t1-.2:
		var h := rng.randf_range(.95,1.2)
		_edge_sprite("rubble",_edge_at(row,side,t,rng.randf_range(0,.25)),h,rng.randf()<.5,tint*rng.randf_range(.9,1.05))
		t+=_edge_sprite_width("rubble",h)/k*.8

func _edge_side(row: Dictionary,side_name: String,style: Dictionary,rng: RandomNumberGenerator) -> void:
	var side: Dictionary=EDGE_SIDES[side_name]
	var k := _edge_screen_k(side)
	var reach := float(row.half)+float(row.offset)+.6
	var opening := Vector2(1,-1)
	for passage in row.get("passages",[]):
		if passage.side==side_name:opening=Vector2(-float(passage.opening),float(passage.opening))
	var height_range: Vector2=style.height_near if side.near else style.height_far
	var t := -reach
	var last_gap := true  ## no collapse at a line's start
	while t<reach:
		if t>=opening.x and t<opening.y:
			## The gate strip stays open. A rubble heap at each end so the wall looks broken there, not cut.
			_edge_sprite("rubble",_edge_at(row,side,opening.y+.3,.1),.9,false,Color(.6,.59,.57))
			t=opening.y
			last_gap=true
			continue
		var roll := rng.randf()
		var kind := "wall"
		var chance_gap := float(style.gap_chance)
		var chance_rail := chance_gap+float(style.rail_chance)
		var chance_slab := chance_rail+float(style.slab_chance)
		var chance_cross := chance_slab+float(style.cross_chance)
		if not last_gap and roll<chance_gap and t<reach-4.0:kind="gap"
		elif roll>=chance_gap and roll<chance_rail and t<reach-4.0:kind="rail"
		elif roll>=chance_rail and roll<chance_slab:kind="slab"
		elif roll>=chance_slab and roll<chance_cross:kind="cross"
		var tint := Color(.75,.8,.83)*rng.randf_range(.92,1.06)
		var stop := minf(reach,opening.x) if opening.x>t else reach
		if kind=="gap" or kind=="rail":
			var span: Vector2=style.gap_len if kind=="gap" else style.rail_len
			var len_ := minf(rng.randf_range(span.x,span.y),stop-t)
			if len_>=1.4:
				if kind=="gap":_edge_gap(side,t,t+len_,row,rng)
				else:_edge_rail(side,t,t+len_,row,rng)
				t+=len_
				last_gap=true
				continue
			kind="wall"
		var h := rng.randf_range(height_range.x,height_range.y)
		var id_ := "wall"
		if kind=="slab":
			id_="grave_slab";h=rng.randf_range(.5,.7)
		elif kind=="cross":
			id_="grave_cross";h=rng.randf_range(.8,.95) if bool(side.near) else rng.randf_range(.95,1.2)
		var width := _edge_sprite_width(id_,h)
		var step := maxf(.8,width/k*.8)
		var mid := t+step*.5
		_edge_footing(side,t,t+step,row,false,rng)
		var mirror := bool(side.mirror_wall) if id_=="wall" else rng.randf()<.5
		_edge_sprite(id_,_edge_at(row,side,mid),h,mirror,tint)
		t+=step
		last_gap=false

func _compose_edges() -> void:
	var meta: String=String(EdgeSlots.slot(EDGE_SLOT_PROPS).get("meta",""))
	if meta!="":_load_prop_doc(EdgeSlots.ART_ROOT+meta)
	_edge_anchors.clear();_edge_blocks.clear();_edge_iron.clear()
	for row in EDGE_ROWS:
		var style: Dictionary=EDGE_STYLES[row.style]
		var rng := RandomNumberGenerator.new();rng.seed=int(style.seed)+int(row.zone)*101
		for side_name in ["north","south","west","east"]:_edge_side(row,side_name,style,rng)
		## Corners are closed with a heap and a block, so no diagonal gap is left between two lines.
		var line := float(row.half)+float(row.offset)
		for sx in [-1.0,1.0]:
			for sz in [-1.0,1.0]:
				var c: Vector2=row.center
				var at := c+Vector2(sx,sz)*(line+.15)
				_edge_sprite("rubble",at,rng.randf_range(1.0,1.25),sx*sz<0,Color(.6,.59,.57))
				_edge_sprite("rubble",at+Vector2(sx,sz)*.7,.75,sx*sz>0,Color(.56,.55,.54))
				_edge_blocks.append({"transform":Transform3D(Basis(Vector3.UP,PI*.25)*Basis.from_scale(Vector3(1.0,.34,1.0)),Vector3(at.x,.17,at.y)),"tint":Color(.5,.52,.5,1)*1.85})
	edge_stats={"anchors":_edge_anchors.size(),"blocks":_edge_blocks.size(),"iron":_edge_iron.size()}

func _build_edge_batches() -> void:
	if not _edge_blocks.is_empty():
		var points: Array[Vector3]=[]
		for z in [-.5,.5]:
			for x in [-.5,.5]:
				for y in [-.5,.5]:points.append(Vector3(x,y,z))
		var mat := StandardMaterial3D.new();mat.albedo_texture=EdgeSlots.texture(EDGE_SLOT_STONE)
		mat.vertex_color_use_as_albedo=true;mat.roughness=.97;mat.uv1_triplanar=true;mat.uv1_world_triplanar=true;mat.uv1_scale=Vector3.ONE*.7
		_edge_batch(_edge_blocks,_stone_geometry37._chamfer37(points,.06),mat,"EdgeFooting")
	if not _edge_iron.is_empty():
		var iron := StandardMaterial3D.new();iron.vertex_color_use_as_albedo=true;iron.roughness=.62;iron.metallic=.35
		var box := BoxMesh.new();box.size=Vector3.ONE
		_edge_batch(_edge_iron,box,iron,"EdgeIron")
	edge_stats["batches"]=int(not _edge_blocks.is_empty())+int(not _edge_iron.is_empty())
	art_status.edge=edge_stats

func _edge_batch(records: Array[Dictionary],shape: Mesh,mat: Material,label: String) -> void:
	var mm := MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.use_colors=true;mm.mesh=shape;mm.instance_count=records.size()
	for i in records.size():
		mm.set_instance_transform(i,records[i].transform);mm.set_instance_color(i,records[i].tint)
	var node := MultiMeshInstance3D.new();node.name=label;node.multimesh=mm;node.material_override=mat
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(node)

# ---- chapter1/view/chapter_world_quality51.gd ----
const Route51=preload("res://chapter1/view/ui51/chapter_route51.gd")
const Loc=preload("res://chapter1/view/loc.gd")
func setup(view: Node3D) -> void:
	setup__q31d(view)
	_build_edge_batches()
	# Flat arrow points along local+Z, matching atan2(direction.x,direction.y).
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(0,0,.9),Vector3(-.45,0,.1),Vector3(.45,0,.1),Vector3(-.13,0,.1),Vector3(.13,0,.1),Vector3(-.13,0,-.6),Vector3(.13,0,-.6)])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,3,5,4,4,5,6])
	var arrow := ArrayMesh.new();arrow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	route.mesh=arrow
func sync(run: RefCounted,delta: float) -> void:
	sync__chapter(run,delta)
	if not route.visible or run.hero.is_empty():return
	var target: Vector2=Route51.waypoint(run).position
	var direction: Vector2=(target-run.hero.position).normalized()
	route.position=Vector3(run.hero.position.x+direction.x*2.1,.08,run.hero.position.y+direction.y*2.1)
	route.rotation.y=atan2(direction.x,direction.y)
