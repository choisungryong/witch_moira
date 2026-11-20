extends "res://chapter1/tests/hud_dump.gd"
## 시험용 glb를 게임의 주인공 모델 자리에 끼워 한 판 앞부분을 돌리고, 지정한 동작(회피·사망 등)을 강제로 틀어 캡처한다.
## 제품 파일은 하나도 바뀌지 않는다. 모델 끼우기와 겉모습 덮기는 chapter1/tests/model_swap.gd가 한다(play_with_model.gd와 같은 코드).
## 모델 호출부가 자리표(asset_slots)로 옮겨지면 인수 하나로 끝난다.
##
##   python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/rig_game_probe.gd -- \
##       --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --primary=chapter1.skill.frost \
##       --model-glb=<절대경로.glb> [--model-texture=<절대경로.png>] --shots=<폴더> --until=<틱> \
##       [--force-clip=dodge|death|run|cast|hit --force-times=0.1,0.2,0.3 --force-start=240 --force-shots=<폴더>]
##
## --shots / --until / --primary 등은 hud_dump.gd 그대로(기본 순간 캡처). --force-clip을 주면 hero.tick이 --force-start를 넘긴 뒤
## 그 클립의 지정한 시각마다 자세를 강제하고 한 장씩 저장한 다음 끝낸다.
##
## A7-0 시험 인수(없으면 위의 동작 그대로. 모두 이 파일과 model_swap.gd 안에서만 일한다):
##   --hero-boost=<0..1>         게임의 주인공 재질 보정(albedo x1.35, albedo 발광)을 얼마나 남길지. 0 = 모델 본래 색.
##   --hero-look=<json>          2.3 표의 겉모습 값(림, 림 색조, 발광 가면, 전용 조명 둘의 세기, albedo 배율, 원소 섞음)을 매 프레임 덮는다
##                               (칸 설명은 model_swap.gd apply_look). 없는 칸은 게임 값 그대로. --hero-boost 뒤에 적용된다.
##   --hero-mask                 주인공 층(2)만 그리는 보조 뷰포트를 같은 세계·같은 카메라로 두고, --shots의 순간 캡처마다 NN-<이름>.mask.png를
##                               함께 저장한다(알파 = 주인공이 덮는 화소, 가림은 무시). 창 실행 필요.
##   --hero-crop-ticks=a,b,c     틱 a, b, c(처음 playing 프레임)에 주인공 둘레 240x240 원 크기 자르기 crop_tNNNN.png, 같은 틱의 전체 화면
##                               full_tNNNN.png, --hero-mask가 있으면 crop_tNNNN.mask.png를 --shots에 저장한다.
##   --burst=<틱>,<프레임 수>    그 틱부터 렌더 프레임마다 자르기를 연속 저장: burst_NN_tTTTT.png(+.mask.png). --burst-full을 더하면 전체 화면도.
##                               (hud_dump의 --burst=<이벤트 이름>과 겹치지 않게, 정수 둘이면 이쪽이다.) --until은 틱+프레임 수보다 15 이상 커야 한다.
##   --foot-log=<json>           렌더 프레임마다 두 발(발목 tarsal·발끝 toe) 월드 위치, 주인공 속도, 다리·골반과 위쪽 뼈의 프레임 간 회전 변화를 적고,
##                               구간 표지(line·start·stop·turn·dash)와 디딤 미끄러짐·걸음 박자·튐 요약을 끝에 쓴다(3.3절의 재는 법).
##   --hero-cast-overlay=0|1     0이면 시전 상체 덮기를 매 프레임 뒤에서 지우고 달리기·서기 자세로 되돌린다(3.1 순 3). 기본 1(게임 그대로).
const ModelSwap := preload("res://chapter1/tests/model_swap.gd")
var model_glb := ""
var model_texture := ""
var force_clip := ""
var force_times: Array = []
var force_start := 240
var force_dir := ""
var _fi := -1
var _armed := false
var _waiting_shot := false
var _held: Array = []
## --hero-boost=<0..1>: scales the game's hero material boost (albedo x1.35 and the albedo-textured emission, tuned for the dark mage).
## 0 = the model's own colours, 1 = the game as is. Presentation of the probe only; the product file is untouched. -1 = leave alone.
var hero_boost := -1.0
var look: Dictionary = {}
var look_path := ""
var hero_mask := false
var crop_ticks: Array[int] = []
var _crop_next := 0
var burst_tick := -1
var burst_count := 0
var burst_full := false
var _burst_done := 0
var _burst_started := false
var foot_log_path := ""
var cast_overlay := true
const CROP_SIZE := 240
const MASK_LAYER_BIT := 1 << 19
var _mask_tagged := false
var _mask_vp: SubViewport
var _mask_cam: Camera3D
var _captures: Array = []
var _post_connected := false
## --hero-emit: one frame after each crop, the hero is drawn with black albedo, no rim, no hero lights (the look's own cells otherwise), and the
## hero-only view is saved as crop_tNNNN.emit.png: the lit pixels are the emission mask on screen. Needs --hero-look and --hero-mask.
var hero_emit := false
## --vp-exp=key=value,...: sharpness experiments on the game's own render settings, for the probe only (a product file is never touched).
##   glow=0|1 (bloom off/on)  mip_bias=<-2..2> (texture mipmap bias of the whole viewport)  aniso=0..4 (anisotropic level: 0 off, 1 2x, 2 4x, 3 8x, 4 16x)
##   hud=0|1 (hide the whole HUD, so the owner chevron does not sit on the hero's pixels)  msaa=0..3 (0 off, 1 2x, 2 4x, 3 8x)  contrast=<float> saturation=<float> (the game's colour adjustment)  cam=<ortho size> (the game: 19.5, smaller = bigger hero)
var vp_exp: Dictionary = {}
var _exp_done := false
var _emit_arm := false
var _emit_active := false
var _emit_tick := 0

# --foot-log state
const FOOT_BONES := ["tarsal_cr_l", "toe_cr_l", "tarsal_cr_r", "toe_cr_r"]
const LEG_PREFIXES := ["pelvis_", "thigh_", "shin_", "tarsal_", "toe_"]
const STANCE_BAND := .03
const STANCE_VY := .2
const DASH_SPEED := 9.0
var _fl_bone_idx: Dictionary = {}
var _fl_leg: Array[int] = []
var _fl_up: Array[int] = []
var _fl_prev_rot: Dictionary = {}
var _fl_frames: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--model-glb="): model_glb = arg.trim_prefix("--model-glb=")
		elif arg.begins_with("--model-texture="): model_texture = arg.trim_prefix("--model-texture=")
		elif arg.begins_with("--force-clip="): force_clip = arg.trim_prefix("--force-clip=")
		elif arg.begins_with("--force-times="):
			for part in arg.trim_prefix("--force-times=").split(",", false): force_times.append(float(part))
		elif arg.begins_with("--force-start="): force_start = int(arg.trim_prefix("--force-start="))
		elif arg.begins_with("--force-shots="): force_dir = arg.trim_prefix("--force-shots=")
		elif arg.begins_with("--hero-boost="): hero_boost = float(arg.trim_prefix("--hero-boost="))
		elif arg.begins_with("--shots="): shots_dir = arg.trim_prefix("--shots=")   # hud_dump reads these again; the A7-0 check below needs them first
		elif arg.begins_with("--until="): until_tick = int(arg.trim_prefix("--until="))
		elif arg.begins_with("--hero-look="): look_path = arg.trim_prefix("--hero-look=")
		elif arg == "--hero-mask": hero_mask = true
		elif arg == "--hero-emit": hero_emit = true
		elif arg.begins_with("--vp-exp="):
			for part in arg.trim_prefix("--vp-exp=").split(",", false):
				var kv := part.split("=")
				if kv.size() == 2: vp_exp[kv[0]] = float(kv[1])
		elif arg.begins_with("--hero-crop-ticks="):
			for part in arg.trim_prefix("--hero-crop-ticks=").split(",", false): crop_ticks.append(int(part))
			crop_ticks.sort()
		elif arg.begins_with("--burst=") and _is_tick_burst(arg.trim_prefix("--burst=")):
			var parts := arg.trim_prefix("--burst=").split(",")
			burst_tick = int(parts[0]); burst_count = int(parts[1])
		elif arg == "--burst-full": burst_full = true
		elif arg.begins_with("--foot-log="): foot_log_path = arg.trim_prefix("--foot-log=")
		elif arg.begins_with("--hero-cast-overlay="): cast_overlay = arg.trim_prefix("--hero-cast-overlay=") != "0"
	var problem := _probe_args_problem()
	if not problem.is_empty():
		push_error("rig_game_probe: " + problem)
		print("PROBE_ARGS ", JSON.stringify({"error": problem}))
		quit(2); return
	if not look_path.is_empty():
		look = ModelSwap.load_look(look_path)
		if look.is_empty():
			quit(2); return
		print("PROBE_LOOK ", JSON.stringify({"file": look_path, "look": look}))
	if not model_glb.is_empty():
		_held = ModelSwap.swap(model_glb, model_texture)
		if _held.is_empty():
			quit(5); return
	super._initialize()
	if hero_mask or not crop_ticks.is_empty() or burst_tick >= 0: _make_mask_view()
	var pre := hero_boost >= 0.0 or not vp_exp.is_empty() or not look.is_empty() or not cast_overlay or hero_mask or not foot_log_path.is_empty()
	if pre: RenderingServer.frame_pre_draw.connect(_probe_pre_draw)
	if not crop_ticks.is_empty() or burst_tick >= 0:
		RenderingServer.frame_post_draw.connect(_probe_post_draw)
		_post_connected = true
	if not force_clip.is_empty():
		RenderingServer.frame_pre_draw.connect(_force_pose)
		RenderingServer.frame_post_draw.connect(_force_shot)

## One sentence for the first argument problem of the A7-0 options, or "".
func _probe_args_problem() -> String:
	var needs_shots := hero_mask or not crop_ticks.is_empty() or burst_tick >= 0
	if hero_emit and (not hero_mask or look_path.is_empty() or crop_ticks.is_empty()): return "--hero-emit needs --hero-look, --hero-mask and --hero-crop-ticks"
	if needs_shots and shots_dir.is_empty(): return "--hero-mask, --hero-crop-ticks and --burst save pictures: they need --shots=<dir>"
	if needs_shots and DisplayServer.get_name() == "headless": return "--hero-mask, --hero-crop-ticks and --burst need a real renderer (no --headless)"
	if burst_tick >= 0:
		if burst_count < 1 or burst_count > 600: return "--burst=<tick>,<frames>: frames must be 1 to 600"
		if until_tick > 0 and burst_tick + burst_count + 15 > until_tick: return "--burst would be cut by --until (needs --until >= %d)" % (burst_tick + burst_count + 15)
	for t in crop_ticks:
		if t < 1: return "--hero-crop-ticks needs ticks of 1 or more"
	if not look_path.is_empty() and not FileAccess.file_exists(look_path): return "--hero-look file not found: " + look_path
	if not foot_log_path.is_empty():
		var folder := foot_log_path.get_base_dir()
		if not folder.is_empty() and not DirAccess.dir_exists_absolute(folder) and DirAccess.make_dir_recursive_absolute(folder) != OK:
			return "--foot-log folder cannot be created: " + folder
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hero-cast-overlay=") and not arg.trim_prefix("--hero-cast-overlay=") in ["0", "1"]: return "--hero-cast-overlay must be 0 or 1"
	return ""

func _actors() -> Object:
	return view.get("actors") if view != null else null

func _make_mask_view() -> void:
	_mask_vp = SubViewport.new()
	_mask_vp.world_3d = root.world_3d
	_mask_vp.transparent_bg = true
	_mask_vp.size = Vector2i(root.size)
	_mask_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_mask_cam = Camera3D.new()
	# Layer 2 is shared with other actors (enemy rigs), so the hero's meshes get one more bit, layer 20, that nothing else has (_tag_hero_layers).
	# The bit is added, never removed: the game's cameras and the two hero-only lights (cull mask 2) see the hero exactly as before.
	_mask_cam.cull_mask = MASK_LAYER_BIT
	_mask_cam.environment = Environment.new()   # clear colour, so the transparent background stays transparent
	_mask_vp.add_child(_mask_cam)
	root.add_child(_mask_vp)
	_mask_cam.current = true

func _tag_hero_layers(actors: Object) -> void:
	if actors == null: return
	# the staff (its gem glows by design) is not part of the body that the look is measured on
	for top in [actors.get("rig_model")]:
		if top != null: _tag_meshes(top)

func _tag_meshes(node: Node) -> void:
	if node is VisualInstance3D and (node.layers & MASK_LAYER_BIT) == 0: node.layers |= MASK_LAYER_BIT
	for child in node.get_children(): _tag_meshes(child)

func _sync_mask_cam() -> void:
	var cam := root.get_camera_3d()
	if cam == null or _mask_cam == null: return
	# The window is resized after _initialize (--resolution): follow the main viewport's real size every frame.
	var main_size := Vector2i(root.get_viewport().get_texture().get_size())
	if main_size.x > 0 and _mask_vp.size != main_size: _mask_vp.size = main_size
	if Engine.get_process_frames() % 20 == 0 or not _mask_tagged:
		_tag_hero_layers(_actors())
		_mask_tagged = _actors() != null and _actors().get("rig_model") != null
	_mask_cam.global_transform = cam.global_transform
	_mask_cam.projection = cam.projection
	_mask_cam.fov = cam.fov
	_mask_cam.size = cam.size
	_mask_cam.near = cam.near
	_mask_cam.far = cam.far
	_mask_cam.keep_aspect = cam.keep_aspect
	_mask_cam.h_offset = cam.h_offset
	_mask_cam.v_offset = cam.v_offset
	_mask_cam.frustum_offset = cam.frustum_offset

## Everything that has to be in place before a frame is drawn, in this order: boost, look, cast overlay off, mask camera, foot log.
func _probe_pre_draw() -> void:
	if view == null or view.get("run") == null: return
	var actors := _actors()
	if not vp_exp.is_empty() and not _exp_done and int(view.run.tick) > 5: _apply_exp()
	if hero_boost >= 0.0: ModelSwap.apply_boost(actors, hero_boost)
	if not look.is_empty(): ModelSwap.apply_look(actors, look)
	if _emit_arm:
		_emit_arm = false; _emit_active = true
		var emit_look := look.duplicate()
		emit_look["albedo_mul"] = 0.0; emit_look["rim"] = 0.0; emit_look["light_key"] = 0.0; emit_look["light_fill"] = 0.0; emit_look["element_lean"] = 0.0
		ModelSwap.apply_look(actors, emit_look)
	if not cast_overlay: _cast_off_repose(actors)
	if _mask_cam != null: _sync_mask_cam()
	if not foot_log_path.is_empty(): _foot_frame(actors)

func _apply_exp() -> void:
	_exp_done = true
	var env_node: WorldEnvironment = null
	for child in view.get_children():
		if child is WorldEnvironment: env_node = child
	var env: Environment = env_node.environment if env_node != null else null
	if vp_exp.has("glow") and env != null: env.glow_enabled = vp_exp.glow > 0.5
	if vp_exp.has("contrast") and env != null: env.adjustment_contrast = vp_exp.contrast
	if vp_exp.has("saturation") and env != null: env.adjustment_saturation = vp_exp.saturation
	if vp_exp.has("hud"):
		var hud_node = view.get("hud")
		if hud_node != null and hud_node.get("root") != null: hud_node.root.visible = vp_exp.hud > .5   # the owner chevron over the head is drawn by the HUD
	if vp_exp.has("mip_bias"): root.texture_mipmap_bias = vp_exp.mip_bias
	if vp_exp.has("aniso"): root.anisotropic_filtering_level = int(vp_exp.aniso) as Viewport.AnisotropicFiltering
	if vp_exp.has("msaa"): root.msaa_3d = int(vp_exp.msaa) as Viewport.MSAA
	if vp_exp.has("cam"):
		var world = view.get("world")
		if world != null and world.get("camera") != null: world.camera.size = vp_exp.cam
	print("PROBE_EXP ", JSON.stringify({"applied": vp_exp, "env_found": env != null}))

## --hero-cast-overlay=0: the product writes the cast upper-body overlay while it poses the hero (chapter_actors.gd _update_pose__rigged).
## It cannot be switched off from outside, so after the product pose the same run/idle pose (and the hit overlay) is sampled again without it
## and the staff is put back on the hand. The hero still turns toward the cast direction (rotation is not touched).
func _cast_off_repose(actors: Object) -> void:
	if actors == null or actors.get("rig_player") == null or actors.get("_upper") == null: return
	if String(view.run.mode) != "playing" or view.run.hero.is_empty(): return
	var tick := int(view.run.tick)
	if tick >= int(actors.get("_cast_until")) or view.run.hero.hp_raw <= 0: return
	var moving: bool = tick < int(actors.get("_hero_move_until"))
	var phase := float(actors.get("_phase"))
	var poses = actors.call("_sample", "run" if moving else "idle", phase * .6 if moving else fposmod(float(actors.get("_idle_age")), 1.2))
	var hit_until := int(actors.get("_hit_until"))
	if tick < hit_until:
		var age := clampf(float(tick - (hit_until - 6)) / 60.0, 0, .1)
		var struck = actors.call("_sample", "hit", age * 3)
		var upper: Dictionary = actors.get("_upper")
		for i in poses.size():
			if upper.has(i): poses[i] = poses[i].interpolate_with(struck[i], .55 * sin(PI * age / .1))
	actors.call("_write_pose", poses)
	var staff: Node3D = actors.get("_staff")
	var hand := int(actors.get("_hand"))
	var finger := int(actors.get("_finger"))
	if staff != null and hand >= 0 and finger >= 0:
		var skeleton: Skeleton3D = actors.get("rig_skeleton")
		var h := skeleton.global_transform * skeleton.get_bone_global_pose(hand)
		var f := skeleton.global_transform * skeleton.get_bone_global_pose(finger)
		staff.global_position = h.origin.lerp(f.origin, .5)
		staff.basis = Basis.from_euler(Vector3(deg_to_rad(-3 + sin(phase * TAU) * 4), 0, deg_to_rad(5)))
		var bottom: Vector3 = staff.global_transform * Vector3(0, -1.05, 0)
		if bottom.y < .025: staff.global_position.y += .025 - bottom.y

# ---------------------------------------------------------------- moments, crops, bursts

## hud_dump saves NN-<moment>.png; the hero mask of the same frame goes next to it.
func _dump(label: String) -> void:
	super._dump(label)
	if hero_mask and _mask_vp != null and not shots_dir.is_empty():
		var main_image := root.get_viewport().get_texture().get_image()
		if main_image != null: _mask_image(main_image.get_size()).save_png(shots_dir.path_join("%02d-%s.mask.png" % [order.size(), label]))

func _mask_image(want: Vector2i) -> Image:
	var image := _mask_vp.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	if image.get_size() != want: image.resize(want.x, want.y, Image.INTERPOLATE_NEAREST)
	return image

## 240x240 around the hero's body centre, in the saved picture's own pixels (no scaling).
func _hero_rect(image_size: Vector2i) -> Rect2i:
	var actors := _actors()
	var cam := root.get_camera_3d()
	if actors == null or cam == null or actors.get("hero") == null: return Rect2i(Vector2i.ZERO, Vector2i(CROP_SIZE, CROP_SIZE))
	var point: Vector2 = cam.unproject_position(actors.hero.global_position + Vector3(0, 1.3, 0))
	var centre := Vector2i(point * Vector2(image_size) / root.get_visible_rect().size)
	var top_left := Vector2i(clampi(centre.x - CROP_SIZE / 2, 0, maxi(0, image_size.x - CROP_SIZE)), clampi(centre.y - CROP_SIZE / 2, 0, maxi(0, image_size.y - CROP_SIZE)))
	return Rect2i(top_left, Vector2i(CROP_SIZE, CROP_SIZE))

func _save_crop(base: String, image: Image, rect: Rect2i) -> void:
	image.get_region(rect).save_png(base + ".png")
	if hero_mask and _mask_vp != null: _mask_image(image.get_size()).get_region(rect).save_png(base + ".mask.png")

func _probe_post_draw() -> void:
	if view == null or view.get("run") == null or String(view.run.mode) != "playing": return
	var tick := int(view.run.tick)
	if _emit_active:
		# the frame drawn with black albedo, no rim, no hero lights: what is left in the hero-only view is the emission mask itself
		_emit_active = false
		var main_size := Vector2i(root.get_viewport().get_texture().get_size())
		var emit_rect := _hero_rect(main_size)
		_mask_image(main_size).get_region(emit_rect).save_png(shots_dir.path_join("crop_t%04d.emit.png" % _emit_tick))
		print("PROBE_EMIT ", JSON.stringify({"tick": tick, "for": _emit_tick}))
	var want_crop := _crop_next < crop_ticks.size() and tick >= crop_ticks[_crop_next]
	var want_burst := burst_tick >= 0 and (tick >= burst_tick or _burst_started) and _burst_done < burst_count
	if not want_crop and not want_burst: return
	var image := root.get_viewport().get_texture().get_image()
	if image == null: return
	DirAccess.make_dir_recursive_absolute(shots_dir)
	var rect := _hero_rect(image.get_size())
	if want_crop:
		var t := crop_ticks[_crop_next]
		_save_crop(shots_dir.path_join("crop_t%04d" % t), image, rect)
		image.save_png(shots_dir.path_join("full_t%04d.png" % t))
		_captures.append({"kind": "crop", "wanted_tick": t, "tick": tick, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "image": [image.get_width(), image.get_height()]})
		print("PROBE_CROP ", JSON.stringify(_captures[-1]))
		_crop_next += 1
		if hero_emit:
			_emit_arm = true; _emit_tick = t
	if want_burst:
		_burst_started = true
		_save_crop(shots_dir.path_join("burst_%02d_t%04d" % [_burst_done, tick]), image, rect)
		if burst_full: image.save_png(shots_dir.path_join("burst_%02d_t%04d_full.png" % [_burst_done, tick]))
		_captures.append({"kind": "burst", "i": _burst_done, "tick": tick, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]})
		_burst_done += 1

# ---------------------------------------------------------------- foot log (3.3)

func _foot_setup(actors: Object) -> bool:
	var skeleton: Skeleton3D = actors.get("rig_skeleton")
	if skeleton == null: return false
	var missing: Array = []
	for bone_name in FOOT_BONES:
		var idx := skeleton.find_bone(bone_name)
		if idx < 0: missing.append(bone_name)
		else: _fl_bone_idx[bone_name] = idx
	var upper: Dictionary = actors.get("_upper") if actors.get("_upper") != null else {}
	var all_names: Array = []
	for i in skeleton.get_bone_count():
		var n := skeleton.get_bone_name(i)
		all_names.append(n)
		for prefix in LEG_PREFIXES:
			if n.begins_with(prefix): _fl_leg.append(i)
		if upper.has(i): _fl_up.append(i)
	print("PROBE_FOOT_BONES ", JSON.stringify({"found": _fl_bone_idx.keys(), "missing": missing, "leg_pelvis_bones": _fl_leg.size(), "upper_bones": _fl_up.size(), "all": all_names}))
	return missing.is_empty()

var _fl_ready := 0   # 0 not tried, 1 ready, -1 failed

func _foot_frame(actors: Object) -> void:
	if actors == null or actors.get("rig_skeleton") == null or actors.get("hero") == null: return
	if _fl_ready == 0: _fl_ready = 1 if _foot_setup(actors) else -1
	if _fl_ready < 0: return
	var run: RefCounted = view.run
	if String(run.mode) != "playing" or run.hero.is_empty(): return
	var skeleton: Skeleton3D = actors.get("rig_skeleton")
	var gt := skeleton.global_transform
	var hero_node: Node3D = actors.hero
	var tick := int(run.tick)
	var record := {"f": Engine.get_process_frames(), "tick": tick, "dt": snappedf(view.get_process_delta_time(), .00001),
		"hero": _v3(hero_node.global_position), "cast_age": tick - int(actors.get("_cast_tick")) if tick - int(actors.get("_cast_tick")) <= 12 else -1}
	for bone_name in FOOT_BONES: record[bone_name] = _v3(gt * skeleton.get_bone_global_pose(int(_fl_bone_idx[bone_name])).origin)
	var leg_max := 0.0
	var leg_bone := ""
	var up_max := 0.0
	var up_bone := ""
	for i in _fl_leg:
		var q := skeleton.get_bone_pose_rotation(i)
		if _fl_prev_rot.has(i):
			var d := rad_to_deg((_fl_prev_rot[i] as Quaternion).angle_to(q))
			if d > leg_max: leg_max = d; leg_bone = skeleton.get_bone_name(i)
		_fl_prev_rot[i] = q
	for i in _fl_up:
		var q := skeleton.get_bone_pose_rotation(i)
		if _fl_prev_rot.has(i):
			var d := rad_to_deg((_fl_prev_rot[i] as Quaternion).angle_to(q))
			if d > up_max: up_max = d; up_bone = skeleton.get_bone_name(i)
		_fl_prev_rot[i] = q
	record["leg_rot"] = snappedf(leg_max, .01); record["leg_bone"] = leg_bone
	record["up_rot"] = snappedf(up_max, .01); record["up_bone"] = up_bone
	_fl_frames.append(record)

func _v3(v: Vector3) -> Array:
	return [snappedf(v.x, .0001), snappedf(v.y, .0001), snappedf(v.z, .0001)]

static func _percentile(sorted_values: Array, p: float) -> float:
	if sorted_values.is_empty(): return NAN
	return float(sorted_values[clampi(int(ceil(p * sorted_values.size())) - 1, 0, sorted_values.size() - 1)])

static func _stats(values: Array) -> Dictionary:
	var v := values.duplicate()
	v.sort()
	if v.is_empty(): return {"n": 0}
	return {"n": v.size(), "median": snappedf(_percentile(v, .5), .0001), "p95": snappedf(_percentile(v, .95), .0001), "max": snappedf(float(v[v.size() - 1]), .0001)}

## Section label per frame from the hero's own movement (priority dash > turn > start > stop > line; idle when still).
func _foot_labels(frames: Array, speed: Array) -> Array:
	var n := frames.size()
	var labels: Array = []
	labels.resize(n)
	for j in n: labels[j] = "idle" if speed[j] >= 0 and speed[j] < .5 else ("gap" if speed[j] < 0 else "line")
	var heading: Array = []
	heading.resize(n)
	for j in n:
		var prev: Dictionary = frames[j - 1] if j > 0 else frames[j]
		var d := Vector2(frames[j].hero[0] - prev.hero[0], frames[j].hero[2] - prev.hero[2])
		heading[j] = d.normalized() if d.length() > .001 else Vector2.ZERO
	for j in n:
		if labels[j] != "line": continue
		# start: moving again within 18 frames after still frames; stop: still frames come within 12 frames
		for k in range(maxi(0, j - 18), j):
			if labels[k] == "idle": labels[j] = "start"; break
	for j in n:
		if labels[j] != "line": continue
		for k in range(j + 1, mini(n, j + 13)):
			if speed[k] >= 0 and speed[k] < .5: labels[j] = "stop"; break
	for j in range(6, n):
		if speed[j] > 2.0 and speed[j - 6] > 2.0 and heading[j] != Vector2.ZERO and heading[j - 6] != Vector2.ZERO and rad_to_deg(heading[j].angle_to(heading[j - 6])) > 35.0:
			for k in range(j - 6, mini(n, j + 13)):
				if labels[k] in ["line", "start", "stop"]: labels[k] = "turn"
	for j in n:
		if speed[j] > DASH_SPEED: labels[j] = "dash"
	return labels

static func _all_label(labels: Array, from_j: int, to_j: int, label: String) -> bool:
	for j in range(from_j, to_j + 1):
		if labels[j] != label: return false
	return true

func _foot_write() -> void:
	var n := _fl_frames.size()
	if n < 3:
		print("PROBE_FOOT_SUMMARY ", JSON.stringify({"error": "too few frames", "frames": n}))
		return
	var speed: Array = []
	speed.resize(n)
	var vel: Array = []   # per frame: dictionary bone -> [horizontal speed, vertical speed] or null
	vel.resize(n)
	for j in n:
		speed[j] = -1.0; vel[j] = null
		if j == 0 or int(_fl_frames[j].f) - int(_fl_frames[j - 1].f) != 1: continue
		var dt := float(_fl_frames[j].dt)
		if dt <= 0: dt = 1.0 / 60.0
		var a: Array = _fl_frames[j].hero
		var b: Array = _fl_frames[j - 1].hero
		speed[j] = Vector2(a[0] - b[0], a[2] - b[2]).length() / dt
		var row := {}
		for bone_name in FOOT_BONES:
			var p: Array = _fl_frames[j][bone_name]
			var q: Array = _fl_frames[j - 1][bone_name]
			row[bone_name] = [Vector2(p[0] - q[0], p[2] - q[2]).length() / dt, (p[1] - q[1]) / dt]
		vel[j] = row
	var labels := _foot_labels(_fl_frames, speed)
	# floor of each bone kind over the whole log: the pose's own lowest point
	var floors := {"tarsal": INF, "toe": INF}
	for r in _fl_frames:
		for bone_name in FOOT_BONES:
			var kind := "tarsal" if bone_name.begins_with("tarsal") else "toe"
			floors[kind] = minf(floors[kind], float(r[bone_name][1]))
	var slip_by_label := {}
	var onsets_by_label := {}
	var frames_by_label := {}
	var last_stance := {"l": -100, "r": -100}
	var step_frames: Array = []
	var stance_slip := {"l": [], "r": []}
	for side in ["l", "r"]:
		stance_slip[side].resize(n)
		stance_slip[side].fill(-1.0)
	for j in n:
		var label: String = labels[j]
		frames_by_label[label] = int(frames_by_label.get(label, 0)) + 1
		var stance_row := {}
		for side in ["l", "r"]:
			var best := INF
			for kind in ["tarsal", "toe"]:
				var bone_name: String = "%s_cr_%s" % [kind, side]
				if vel[j] == null: continue
				var height: float = float(_fl_frames[j][bone_name][1]) - float(floors[kind])
				var v: Array = vel[j][bone_name]
				if height <= STANCE_BAND and absf(float(v[1])) <= STANCE_VY: best = minf(best, float(v[0]))
			if best < INF:
				if not slip_by_label.has(label): slip_by_label[label] = []
				slip_by_label[label].append(best)
				stance_row[side] = best; stance_slip[side][j] = best
				if j - int(last_stance[side]) > 6:   # a foot cannot land twice within 0.1 s (a stance is about 12 frames, a stride 22)
					onsets_by_label[label] = int(onsets_by_label.get(label, 0)) + 1
					step_frames.append({"j": j, "side": side, "label": label})
				last_stance[side] = j
		_fl_frames[j]["label"] = label
		_fl_frames[j]["speed"] = snappedf(maxf(float(speed[j]), 0.0), .001)
		if not stance_row.is_empty(): _fl_frames[j]["slip"] = {"l": snappedf(float(stance_row.get("l", -1.0)), .001), "r": snappedf(float(stance_row.get("r", -1.0)), .001)}
	# "core" stance: the same frames without the first and last 2 of every unbroken stance run of 5+ frames. The 3 cm band also catches the swing foot
	# for a frame or two as it lands and lifts (fast horizontal speed); the core is the planted foot. Both are reported, the spec's rule is "slip".
	var core_by_label := {}
	for side in ["l", "r"]:
		var run_start := -1
		for j in range(n + 1):
			var inside: bool = j < n and float(stance_slip[side][j]) >= 0.0 and (j == 0 or run_start < 0 or int(_fl_frames[j].f) - int(_fl_frames[j - 1].f) == 1)
			if inside:
				if run_start < 0: run_start = j
				continue
			if run_start >= 0 and j - run_start >= 5:
				for k in range(run_start + 2, j - 2):
					var core_label: String = labels[k]
					if not core_by_label.has(core_label): core_by_label[core_label] = []
					core_by_label[core_label].append(float(stance_slip[side][k]))
			run_start = j if (j < n and float(stance_slip[side][j]) >= 0.0) else -1
	var sections := {}
	for label in frames_by_label:
		var count: int = frames_by_label[label]
		var seconds := count / 60.0
		var slips: Array = slip_by_label.get(label, [])
		var row: Dictionary = _stats(slips)
		var over1 := 0
		for s in slips:
			if float(s) > 1.0: over1 += 1
		row["frames"] = count; row["seconds"] = snappedf(seconds, .001)
		row["stance_onsets"] = int(onsets_by_label.get(label, 0))
		row["steps_per_s"] = snappedf(float(onsets_by_label.get(label, 0)) / seconds, .001) if seconds > 0 else 0.0
		row["slip_over_1ms_frames"] = over1
		row["core_slip"] = _stats(core_by_label.get(label, []))
		sections[label] = row
	# rotation jumps (leg+pelvis; upper). The first dash frame is the jump that is allowed (spec 3.3).
	var leg_max := 0.0
	var leg_at := {}
	var leg_max_excl := 0.0
	var leg_at_excl := {}
	var up_max := 0.0
	var up_at := {}
	for j in n:
		var r: Dictionary = _fl_frames[j]
		var dash_start: bool = labels[j] == "dash" and (j == 0 or labels[j - 1] != "dash")
		if float(r.leg_rot) > leg_max: leg_max = float(r.leg_rot); leg_at = {"tick": r.tick, "bone": r.leg_bone, "label": labels[j]}
		if not dash_start and float(r.leg_rot) > leg_max_excl: leg_max_excl = float(r.leg_rot); leg_at_excl = {"tick": r.tick, "bone": r.leg_bone, "label": labels[j]}
		if float(r.up_rot) > up_max: up_max = float(r.up_rot); up_at = {"tick": r.tick, "bone": r.up_bone, "label": labels[j]}
	var run_speeds: Array = []
	for j in n:
		if labels[j] == "line": run_speeds.append(speed[j])
	# Cadence of the straight runs: inside each unbroken "line" stretch, (onsets - 1) / time from the first to the last onset (no edge bias); stretches with fewer than 3 onsets are left out.
	var line_steps := 0
	var line_time := 0.0
	var line_stretches := 0
	var stretch: Array = []
	for k in range(step_frames.size() + 1):
		var j: int = int(step_frames[k].j) if k < step_frames.size() else -1
		var joins: bool = j >= 0 and labels[j] == "line" and not stretch.is_empty() and _all_label(labels, int(stretch[-1]), j, "line")
		if joins:
			stretch.append(j)
			continue
		if stretch.size() >= 3:
			line_steps += stretch.size() - 1
			line_time += float(int(stretch[-1]) - int(stretch[0])) / 60.0
			line_stretches += 1
		stretch = []
		if j >= 0 and labels[j] == "line": stretch.append(j)
	var line_cadence := snappedf(float(line_steps) / line_time, .001) if line_time > 0.0 else 0.0
	var summary := {"frames": n, "floors_m": {"tarsal": snappedf(floors.tarsal, .0001), "toe": snappedf(floors.toe, .0001)},
		"stance_rule": "bone height <= own floor + %.2f m and |vy| <= %.1f m/s; foot slip = smaller horizontal speed of the stance bones (tarsal, toe)" % [STANCE_BAND, STANCE_VY],
		"sections": sections, "line_steps_per_s": line_cadence, "line_cadence_basis": {"stretches": line_stretches, "steps": line_steps, "seconds": snappedf(line_time, .001)}, "line_speed": _stats(run_speeds),
		"rot_deg": {"leg_pelvis_max_all": snappedf(leg_max, .01), "leg_pelvis_max_all_at": leg_at, "leg_pelvis_max_excl_dash_start": snappedf(leg_max_excl, .01), "leg_pelvis_max_excl_at": leg_at_excl,
			"upper_max": snappedf(up_max, .01), "upper_max_at": up_at},
		"cast_overlay": cast_overlay, "look": look_path, "model": model_glb, "primary": primary}
	var file := FileAccess.open(foot_log_path, FileAccess.WRITE)
	if file == null:
		push_error("rig_game_probe: cannot write the foot log: " + foot_log_path)
		return
	var doc := summary.duplicate()
	doc["steps"] = step_frames
	doc["frames_log"] = _fl_frames
	file.store_string(JSON.stringify(doc))
	file.close()
	print("PROBE_FOOT_SUMMARY ", JSON.stringify(summary))

func _finish() -> void:
	if not _captures.is_empty() and not shots_dir.is_empty():
		var index := FileAccess.open(shots_dir.path_join("probe_captures.json"), FileAccess.WRITE)
		if index != null:
			index.store_string(JSON.stringify(_captures))
			index.close()
	if not foot_log_path.is_empty(): _foot_write()
	super._finish()

func _force_pose() -> void:
	if force_clip.is_empty() or view == null or view.get("run") == null: return
	var actors := _actors()
	if actors == null or actors.get("rig_player") == null or actors.get("rig_skeleton") == null: return
	if not _armed:
		if int(view.run.tick) >= force_start and String(view.run.mode) == "playing":
			_armed = true; _fi = 0
		else: return
	if _fi < 0 or _fi >= force_times.size(): return
	actors.call("_sample", force_clip, float(force_times[_fi]))
	_waiting_shot = true

func _force_shot() -> void:
	if not _waiting_shot: return
	_waiting_shot = false
	if force_dir.is_empty(): force_dir = shots_dir
	DirAccess.make_dir_recursive_absolute(force_dir)
	var image := root.get_viewport().get_texture().get_image()
	if image != null: image.save_png(force_dir.path_join("%s_%02d_t%03d.png" % [force_clip, _fi, int(round(float(force_times[_fi]) * 100.0))]))
	print("PROBE_SHOT ", JSON.stringify({"clip": force_clip, "i": _fi, "t": force_times[_fi], "tick": view.run.tick}))
	_fi += 1
	if _fi >= force_times.size():
		print("PROBE_DONE")
		quit(0)
