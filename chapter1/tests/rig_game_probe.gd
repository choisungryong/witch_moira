extends "res://chapter1/tests/hud_dump.gd"
## 시험용 glb를 게임의 주인공 모델 자리에 끼워 한 판 앞부분을 돌리고, 지정한 동작(회피·사망 등)을 강제로 틀어 캡처한다.
## 제품 파일은 하나도 바뀌지 않는다. 게임이 `load(MODEL)`로 부르는 경로와 임포트 변환 경로 두 곳에 Resource.take_over_path로 시험 glb를 올린다
## (임포트 변환 경로까지 올려야 바뀐다: 증명 문서 5절). 모델 호출부가 자리표(asset_slots)로 옮겨지면 인수 하나로 끝난다.
##
##   python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/rig_game_probe.gd -- \
##       --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --primary=chapter1.skill.frost \
##       --model-glb=<절대경로.glb> [--model-texture=<절대경로.png>] --shots=<폴더> --until=<틱> \
##       [--force-clip=dodge|death|run|cast|hit --force-times=0.1,0.2,0.3 --force-start=240 --force-shots=<폴더>]
##
## --shots / --until / --primary 등은 hud_dump.gd 그대로(기본 순간 캡처). --force-clip을 주면 hero.tick이 --force-start를 넘긴 뒤
## 그 클립의 지정한 시각마다 자세를 강제하고 한 장씩 저장한 다음 끝낸다.
const MODEL_PATH := "res://chapter1/art/rigged_mage/v01/mage_animated.glb"
const IMPORTED_GLOB_DIR := "res://.godot/imported/"
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

func _apply_boost() -> void:
	var actors := _actors()
	if actors == null: return
	var mats = actors.get("_hero_materials")
	if mats == null: return
	for m in mats:
		var mat := m as StandardMaterial3D
		if mat == null: continue
		mat.albedo_color = Color(1, 1, 1).lerp(Color(1.35, 1.25, 1.18), hero_boost)
		mat.emission_energy_multiplier = 0.45 * hero_boost

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
	if not model_glb.is_empty(): _swap_model()
	super._initialize()
	if hero_boost >= 0.0: RenderingServer.frame_pre_draw.connect(_apply_boost)
	if not force_clip.is_empty():
		RenderingServer.frame_pre_draw.connect(_force_pose)
		RenderingServer.frame_post_draw.connect(_force_shot)

func _swap_model() -> void:
	var state := GLTFState.new()
	var doc := GLTFDocument.new()
	var err := doc.append_from_file(model_glb, state)
	if err != OK:
		push_error("probe: glb read failed %d" % err); quit(5); return
	var node: Node = doc.generate_scene(state)
	if not model_texture.is_empty():
		var image := Image.load_from_file(model_texture)
		var tex := ImageTexture.create_from_image(image)
		_retexture(node, tex)
	_own(node, node)
	var packed := PackedScene.new()
	packed.pack(node)
	packed.take_over_path(MODEL_PATH)
	_held.append(packed)  # the cache holds no reference: without this the swap is dropped when this function returns
	# 임포트 변환 경로: .import 파일의 path= 값
	var import_text := FileAccess.get_file_as_string(MODEL_PATH + ".import")
	for line in import_text.split("\n"):
		if line.begins_with("path="):
			var imported := line.trim_prefix("path=").strip_edges().trim_prefix("\"").trim_suffix("\"")
			var packed2 := packed.duplicate()
			packed2.take_over_path(imported)
			_held.append(packed2)
	print("PROBE_MODEL ", JSON.stringify({"glb": model_glb, "texture": model_texture}))

func _own(root_node: Node, node: Node) -> void:
	for child in node.get_children():
		if child.owner == null: child.owner = root_node
		_own(root_node, child)

func _retexture(node: Node, tex: Texture2D) -> void:
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as StandardMaterial3D
			if mat != null:
				mat = mat.duplicate()
				mat.albedo_texture = tex
				mesh.surface_set_material(i, mat)
	for child in node.get_children(): _retexture(child, tex)

func _actors() -> Object:
	return view.get("actors") if view != null else null

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
