extends RefCounted
## Puts a trial glb in the hero model's place without touching a product file (Resource.take_over_path on the path the game
## loads and on its imported path). Used by rig_game_probe.gd (pilot capture) and play_with_model.gd (the user plays).
## The caller must keep the returned array alive: the resource cache holds no reference, so a dropped array undoes the swap.
const MODEL_PATH := "res://chapter1/art/rigged_mage/v01/mage_animated.glb"

static func swap(model_glb: String, model_texture: String = "") -> Array:
	var held: Array = []
	var state := GLTFState.new()
	var doc := GLTFDocument.new()
	var err := doc.append_from_file(model_glb, state)
	if err != OK:
		push_error("model_swap: glb read failed %d" % err)
		return held
	var node: Node = doc.generate_scene(state)
	if not model_texture.is_empty():
		var image := Image.load_from_file(model_texture)
		_retexture(node, ImageTexture.create_from_image(image))
	_own(node, node)
	var packed := PackedScene.new()
	packed.pack(node)
	packed.take_over_path(MODEL_PATH)
	held.append(packed)
	var import_text := FileAccess.get_file_as_string(MODEL_PATH + ".import")
	for line in import_text.split("\n"):
		if line.begins_with("path="):
			var imported := line.trim_prefix("path=").strip_edges().trim_prefix("\"").trim_suffix("\"")
			var packed2 := packed.duplicate()
			packed2.take_over_path(imported)
			held.append(packed2)
	print("PROBE_MODEL ", JSON.stringify({"glb": model_glb, "texture": model_texture}))
	return held

## Scales the game's hero material boost (albedo x1.35 and the albedo-textured emission, tuned for the dark mage).
## 0 = the model's own colours, 1 = the game as is. `actors` is the view's actors object.
static func apply_boost(actors: Object, boost: float) -> void:
	if actors == null: return
	var mats = actors.get("_hero_materials")
	if mats == null: return
	for m in mats:
		var mat := m as StandardMaterial3D
		if mat == null: continue
		mat.albedo_color = Color(1, 1, 1).lerp(Color(1.35, 1.25, 1.18), boost)
		mat.emission_energy_multiplier = 0.45 * boost

static func _own(root_node: Node, node: Node) -> void:
	for child in node.get_children():
		if child.owner == null: child.owner = root_node
		_own(root_node, child)

static func _retexture(node: Node, tex: Texture2D) -> void:
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as StandardMaterial3D
			if mat != null:
				mat = mat.duplicate()
				mat.albedo_texture = tex
				mesh.surface_set_material(i, mat)
	for child in node.get_children(): _retexture(child, tex)
