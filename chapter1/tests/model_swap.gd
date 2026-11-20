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

## Hero look override (A7-0): the cells of docs/specs/A7-hero-look-and-motion-20261120.ko.md 2.3, read from a json file.
## A cell that is absent leaves what the game set; so a look can lower only the rim, only the two hero lights, or everything.
##   albedo_mul [r,g,b]|number   albedo multiplier (base of the body colour)     element_lean 0..1   share of element colour x1.3 mixed into albedo
##   emission_mode none|albedo|mask   albedo = the game's (albedo texture x element x .15)     emission_texture <png path>   (mask mode: element places only)
##   emission_energy number      rim number     rim_tint number     light_key, light_fill   energy of the two hero-only directional lights (game: 1.6, .85)
##   rim_color: StandardMaterial3D has no rim colour (rim_tint only mixes albedo into white), so it is reported and not applied.
## The game's own values for the old mage (a look that equals today's picture): albedo_mul [1.15,1.12,1.08], element_lean .3, emission_mode albedo,
## emission_energy .6, rim 1.0, rim_tint 1.0, light_key 1.6, light_fill .85   (file: _local/art/a7/A7-0/looks/game_default.json).
const ELEMENT_FALLBACK := {"chapter1.skill.ember":Color("ff943d"),"chapter1.skill.frost":Color("9ce7ef"),"chapter1.skill.arc":Color("8fa6ff")}
static var _tex_cache: Dictionary = {}
static var _lights: Array = []
static var _warned: Dictionary = {}

static func load_look(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("model_swap: look file empty or missing: " + path)
		return {}
	var doc: Variant = JSON.parse_string(text)
	if not doc is Dictionary:
		push_error("model_swap: look file is not a json object: " + path)
		return {}
	return doc

static func _color(v: Variant, fallback: Color) -> Color:
	if v is Array and v.size() >= 3: return Color(float(v[0]), float(v[1]), float(v[2]))
	if v is float or v is int: return Color(float(v), float(v), float(v))
	if v is String: return Color(v)
	return fallback

static func _mask_texture(path: String) -> Texture2D:
	if _tex_cache.has(path): return _tex_cache[path]
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		push_error("model_swap: emission texture unreadable: " + path)
		return null
	image.generate_mipmaps()
	var tex := ImageTexture.create_from_image(image)
	_tex_cache[path] = tex
	return tex

static func _hero_lights(actors: Object) -> Array:
	var alive := _lights.size() == 2
	for l in _lights:
		if not is_instance_valid(l): alive = false
	if alive: return _lights
	_lights = []
	var owner_view: Node = actors.get("view")
	if owner_view == null: return _lights
	for child in owner_view.get_children():
		if child is DirectionalLight3D and child.light_cull_mask == 2: _lights.append(child)
	return _lights

## Call every frame after the game's own hero element pass (the game applies it once, when the primary skill is set).
static func apply_look(actors: Object, look: Dictionary) -> void:
	if actors == null or look.is_empty(): return
	var key := String(actors.get("_hero_element_key"))
	var mats = actors.get("_hero_materials")
	if key.is_empty() or mats == null: return
	var element: Color = ELEMENT_FALLBACK.get(key, ELEMENT_FALLBACK["chapter1.skill.frost"])
	var mode := String(look.get("emission_mode", ""))
	var mask_tex: Texture2D = _mask_texture(String(look.emission_texture)) if look.has("emission_texture") else null
	if look.has("rim_color") and not _warned.has("rim_color"):
		_warned["rim_color"] = true
		print("PROBE_LOOK_WARN ", JSON.stringify({"rim_color":"not applied: StandardMaterial3D has no rim colour; use rim and rim_tint"}))
	for m in mats:
		var mat := m as StandardMaterial3D
		if mat == null: continue
		if look.has("albedo_mul") or look.has("element_lean"):
			mat.albedo_color = _color(look.get("albedo_mul", 1.0), Color.WHITE).lerp(element * 1.3, float(look.get("element_lean", 0.0)))
		if mode == "none":
			mat.emission_enabled = false
		elif mode == "albedo":
			mat.emission_enabled = true
			mat.emission_texture = mat.albedo_texture
			mat.emission = element * .15
		elif mode == "mask":
			mat.emission_enabled = true
			mat.emission_texture = mask_tex
			mat.emission = Color.WHITE
		if look.has("emission_energy"): mat.emission_energy_multiplier = float(look.emission_energy)
		if look.has("rim"):
			mat.rim_enabled = float(look.rim) > 0.0
			mat.rim = float(look.rim)
		if look.has("rim_tint"): mat.rim_tint = float(look.rim_tint)
	var lights := _hero_lights(actors)
	if lights.size() == 2:
		if look.has("light_key"): lights[0].light_energy = float(look.light_key)
		if look.has("light_fill"): lights[1].light_energy = float(look.light_fill)

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
