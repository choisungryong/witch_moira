extends RefCounted
## T7-0: which files under chapter1/art/ (and the living-portrait flake pictures) a play-through really loads and draws.
## Used by hud_dump.gd (--asset-usage=<file under _local/>). Read-only: it never changes the view, the core or any resource.
##
## Two questions per file, answered by sampling the live scene tree (every few frames, plus at every dump moment):
##   cached    ResourceLoader.has_cached(path) at any sample (a resource that was loaded and dropped again between two
##             samples is missed; a raw Image.load_from_file fallback never shows up here, see "raw_fallbacks").
##   visible   a node that is visible in the tree holds the file: TextureRect / Sprite2D / NinePatchRect / TextureButton /
##             Sprite3D / AnimatedSprite3D / Decal textures, StyleBoxTexture, material textures (BaseMaterial3D and
##             ShaderMaterial uniforms), a mesh or MultiMesh that comes from a .glb, a texture kept in a script variable of a
##             visible node (custom _draw code), the font of a visible text node. Sound: a player that is playing it.
## Limits (written into the output as "limits"): textures drawn through UiStyle.blit or RenderingServer calls are seen only
## through the AtlasBox style boxes and script variables; a pathless AudioStreamWAV (the duplicated ambience) is matched by
## its data size; a visible node is not necessarily inside the camera frustum or the window.
const ART_ROOTS := ["res://chapter1/art","res://chapter1/view/hud/living_portrait"]
const EXTENSIONS := ["png","svg","glb","wav","ttf"]
const STYLE_NAMES := ["normal","hover","pressed","disabled","focus","panel","fill","background","grabber","grabber_highlight","slider","bar"]

var files: Array[String] = []
var imported: Dictionary = {}        # res:// path inside .godot/imported -> source path
var cached_ever: Dictionary = {}     # source path -> first tick
var attached: Dictionary = {}        # source path -> {kind: true}
var visible: Dictionary = {}         # source path -> {"kinds": {kind: true}, "first_tick": n, "max_nodes": n}
var played: Dictionary = {}          # source path -> {"first_tick": n, "frames": n}
var unidentified: Dictionary = {}    # kind -> count of visible textures without a file path (ImageTexture etc.)
var samples := 0
var holders: Array = []              # presenters (actors, world, audio, ...) whose own variables may hold loaded resources
var stage_log: Array = []
var sprite_report: Dictionary = {}   # label -> report of visible Sprite3D / AnimatedSprite3D
var _audio_nodes: Array = []
var _wav_sizes: Dictionary = {}
var _png_dims: Dictionary = {}
var _thumbs: Dictionary = {}
var _tex_match: Dictionary = {}
var image_matched: Dictionary = {}   # source path -> true when a pathless ImageTexture was matched to it by picture content
const THUMB := 16
const MATCH_TOLERANCE := 10.0        # mean absolute byte difference (0..255) between 16x16 thumbnails
var _script_vars: Dictionary = {}
var _res_cache: Dictionary = {}
var _font_cache: Dictionary = {}
var _theme_cache: Dictionary = {}
var _tick := 0
var _mode := ""
var _round_visible: Dictionary = {}

func _init() -> void:
	for root in ART_ROOTS: _scan(root)
	files.sort()
	for path in files:
		var cfg := ConfigFile.new()
		if cfg.load(path+".import") != OK: continue
		for key in cfg.get_section_keys("remap"):
			if key == "path" or key.begins_with("path."):
				imported[String(cfg.get_value("remap",key))] = path

func _scan(folder: String) -> void:
	var dir := DirAccess.open(folder)
	if dir == null: return
	for sub in dir.get_directories(): _scan(folder.path_join(sub))
	for file_name in dir.get_files():
		if file_name.get_extension().to_lower() in EXTENSIONS: files.append(folder.path_join(file_name))

## Source file of a resource ("" for resources that do not come from a file we track).
func _src(res: Resource) -> String:
	if res == null: return ""
	var path := res.resource_path
	if path.is_empty(): return ""
	var base := path.get_slice("::",0)
	if imported.has(base): return String(imported[base])
	return base

func _mark_attached(path: String, kind: String) -> void:
	if path.is_empty(): return
	if not attached.has(path): attached[path] = {}
	attached[path][kind] = true

func _mark_visible(path: String, kind: String) -> void:
	if path.is_empty(): return
	_mark_attached(path,kind)
	if not visible.has(path): visible[path] = {"kinds":{},"first_tick":_tick,"first_mode":_mode,"max_nodes":0}
	visible[path].kinds[kind] = true
	_round_visible[path] = int(_round_visible.get(path,0))+1

func _tex_paths(t: Texture2D, out: Dictionary) -> void:
	if t == null: return
	if t is AtlasTexture:
		_tex_paths(t.atlas,out); return
	if t is CanvasTexture:
		_tex_paths(t.diffuse_texture,out); _tex_paths(t.normal_texture,out); _tex_paths(t.specular_texture,out); return
	var s := _src(t)
	if s.is_empty() and t is ImageTexture:
		# The world builds mipmapped ImageTexture copies of the PNGs it loads: no path left. Match by picture content.
		s = _match_image(t)
	if s.is_empty(): out["?"+t.get_class()] = true
	else: out[s] = true

func _png_size(path: String) -> Vector2i:
	if _png_dims.has(path): return _png_dims[path]
	var size := Vector2i.ZERO
	var handle := FileAccess.open(path,FileAccess.READ)
	if handle != null and handle.get_length() >= 24:
		handle.big_endian = true
		handle.seek(16); var w := handle.get_32(); var h := handle.get_32()
		size = Vector2i(w,h)
	_png_dims[path] = size
	return size

func _thumb_of(image: Image) -> PackedByteArray:
	var copy: Image = image.duplicate()
	if copy.is_compressed(): copy.decompress()
	copy.clear_mipmaps()
	copy.convert(Image.FORMAT_RGBA8)
	copy.resize(THUMB,THUMB,Image.INTERPOLATE_BILINEAR)
	return copy.get_data()

func _match_image(tex: ImageTexture) -> String:
	var key := tex.get_instance_id()
	if _tex_match.has(key): return _tex_match[key]
	var result := ""
	var size := Vector2i(tex.get_width(),tex.get_height())
	var candidates: Array = []
	for path in files:
		if path.get_extension().to_lower() == "png" and _png_size(path) == size: candidates.append(path)
	if not candidates.is_empty():
		var image := tex.get_image()
		if image != null:
			var mine := _thumb_of(image)
			var best := 1e9
			for path in candidates:
				if not _thumbs.has(path):
					var raw := Image.load_from_file(ProjectSettings.globalize_path(path))
					_thumbs[path] = _thumb_of(raw) if raw != null else PackedByteArray()
				var theirs: PackedByteArray = _thumbs[path]
				if theirs.size() != mine.size(): continue
				var total := 0.0
				for i in mine.size(): total += absf(float(mine[i])-float(theirs[i]))
				var diff := total/float(mine.size())
				if diff < best:
					best = diff
					result = path if diff <= MATCH_TOLERANCE else ""
	if not result.is_empty(): image_matched[result] = true
	_tex_match[key] = result
	return result

func _material_paths(m: Material, out: Dictionary) -> void:
	if m == null: return
	var key := m.get_instance_id()
	if _res_cache.has(key):
		for p in _res_cache[key]: out[p] = true
		return
	var found: Dictionary = {}
	if m is BaseMaterial3D:
		for prop in m.get_property_list():
			var n: String = prop.name
			if n.ends_with("_texture") and prop.type == TYPE_OBJECT:
				var t = m.get(n)
				if t is Texture2D: _tex_paths(t,found)
	elif m is ShaderMaterial and m.shader != null:
		for u in m.shader.get_shader_uniform_list():
			if int(u.type) == TYPE_OBJECT:
				var t = m.get_shader_parameter(String(u.name))
				if t is Texture2D: _tex_paths(t,found)
	if m.next_pass != null: _material_paths(m.next_pass,found)
	_res_cache[key] = found.keys()
	for p in found: out[p] = true

func _mesh_paths(mesh: Mesh, out: Dictionary) -> void:
	if mesh == null: return
	var s := _src(mesh)
	if not s.is_empty(): out[s] = true
	for i in mesh.get_surface_count(): _material_paths(mesh.surface_get_material(i),out)

func _frames_paths(frames: SpriteFrames) -> Array:
	var key := frames.get_instance_id()
	if _res_cache.has(key): return _res_cache[key]
	var found: Dictionary = {}
	for anim in frames.get_animation_names():
		for i in frames.get_frame_count(anim): _tex_paths(frames.get_frame_texture(anim,i),found)
	_res_cache[key] = found.keys()
	return _res_cache[key]

func _font_paths(font: Font) -> Array:
	if font == null: return []
	var key := font.get_instance_id()
	if _font_cache.has(key): return _font_cache[key]
	var found: Dictionary = {}
	var queue: Array = [font]
	while not queue.is_empty():
		var f: Font = queue.pop_back()
		if f is FontVariation and f.base_font != null: queue.append(f.base_font)
		var s := _src(f)
		if not s.is_empty(): found[s] = true
		for fb in f.fallbacks: queue.append(fb)
	_font_cache[key] = found.keys()
	return _font_cache[key]

func _style_paths(style: StyleBox, out: Dictionary) -> void:
	if style == null: return
	if style is StyleBoxTexture: _tex_paths(style.texture,out)
	elif style.get_script() != null and style.get("piece") != null and not String(style.get("piece")).is_empty():
		# AtlasBox (ui_style.gd): a nine-slice cut from the HUD atlas, drawn with RenderingServer calls.
		out["res://chapter1/art/ui/kit/hud_atlas.png"] = true

func _theme_paths(theme: Theme) -> Dictionary:
	var key := theme.get_instance_id()
	if _theme_cache.has(key): return _theme_cache[key]
	var found: Dictionary = {}
	for type_name in theme.get_stylebox_type_list():
		for style_name in theme.get_stylebox_list(type_name): _style_paths(theme.get_stylebox(style_name,type_name),found)
	_theme_cache[key] = found
	return found

## Files one node holds, with the kind of holder. Visible only matters to the caller.
func _node_files(node: Node) -> Array:
	var out: Array = []   # [kind, Dictionary of paths]
	var found: Dictionary = {}
	if node is TextureRect:
		_tex_paths(node.texture,found); out.append(["TextureRect",found])
	elif node is Sprite2D:
		_tex_paths(node.texture,found); out.append(["Sprite2D",found])
	elif node is NinePatchRect:
		_tex_paths(node.texture,found); out.append(["NinePatchRect",found])
	elif node is TextureButton:
		for t in [node.texture_normal,node.texture_pressed,node.texture_hover,node.texture_disabled,node.texture_focused]: _tex_paths(t,found)
		out.append(["TextureButton",found])
	elif node is AnimatedSprite2D and node.sprite_frames != null:
		for p in _frames_paths(node.sprite_frames): found[p] = true
		out.append(["AnimatedSprite2D",found])
	elif node is Sprite3D:
		_tex_paths(node.texture,found); out.append(["Sprite3D",found])
	elif node is AnimatedSprite3D and node.sprite_frames != null:
		for p in _frames_paths(node.sprite_frames): found[p] = true
		out.append(["AnimatedSprite3D",found])
	elif node is Decal:
		for t in [node.texture_albedo,node.texture_normal,node.texture_orm,node.texture_emission]: _tex_paths(t,found)
		out.append(["Decal",found])
	elif node is MultiMeshInstance3D and node.multimesh != null:
		_mesh_paths(node.multimesh.mesh,found); _material_paths(node.material_override,found)
		out.append(["MultiMesh",found])
	elif node is MeshInstance3D:
		_mesh_paths(node.mesh,found); _material_paths(node.material_override,found); _material_paths(node.material_overlay,found)
		for i in range(node.get_surface_override_material_count()): _material_paths(node.get_surface_override_material(i),found)
		out.append(["MeshInstance3D",found])
	elif node is GPUParticles3D:
		_mesh_paths(node.draw_pass_1,found); _material_paths(node.material_override,found)
		out.append(["GPUParticles3D",found])
	elif node is CPUParticles3D:
		_mesh_paths(node.mesh,found); _material_paths(node.material_override,found)
		out.append(["CPUParticles3D",found])
	elif node is Label3D:
		var fonts: Dictionary = {}
		for p in _font_paths(node.font): fonts[p] = true
		out.append(["Label3D.font",fonts])
	if node is CanvasItem:
		var canvas_material: Dictionary = {}
		_material_paths(node.material,canvas_material)
		if not canvas_material.is_empty(): out.append(["CanvasMaterial",canvas_material])
	if node is Control:
		var styles: Dictionary = {}
		for name in STYLE_NAMES:
			if node.has_theme_stylebox_override(name): _style_paths(node.get_theme_stylebox(name),styles)
		if node.theme != null:
			for p in _theme_paths(node.theme): styles[p] = true
		if not styles.is_empty(): out.append(["Style",styles])
		if node is Label or node is Button or node is LineEdit or node is RichTextLabel:
			var shown: bool = String(node.text) != "" if not node is RichTextLabel else true
			if shown:
				var fonts: Dictionary = {}
				var font: Font = node.get_theme_font("normal_font" if node is RichTextLabel else "font")
				for p in _font_paths(font): fonts[p] = true
				out.append(["Font",fonts])
	if node.get_script() != null:
		var script: Script = node.get_script()
		var script_key := script.get_instance_id()
		# Slot paintings (equipment_sigil_quality35.gd): a constant PAINTINGS table picked by the node's `slot`.
		var constants := script.get_script_constant_map()
		var base_script: Script = script.get_base_script()
		while base_script != null and not constants.has("PAINTINGS"):
			constants = base_script.get_script_constant_map(); base_script = base_script.get_base_script()
		if constants.has("PAINTINGS") and node.get("slot") != null:
			var painting = constants["PAINTINGS"].get(String(node.get("slot")),constants["PAINTINGS"].get("charm"))
			if painting is Texture2D:
				var painted: Dictionary = {}
				_tex_paths(painting,painted)
				out.append(["ScriptConst(slot)",painted])
		if not _script_vars.has(script_key):
			var names: Array = []
			for prop in script.get_script_property_list():
				if prop.type == TYPE_OBJECT: names.append(String(prop.name))
			_script_vars[script_key] = names
		var held: Dictionary = {}
		for var_name in _script_vars[script_key]:
			var value = node.get(var_name)
			if value is Texture2D: _tex_paths(value,held)
			elif value is Material: _material_paths(value,held)
			elif value is Font:
				for p in _font_paths(value): held[p] = true
		if not held.is_empty(): out.append(["ScriptVar",held])
	if node.scene_file_path.get_extension().to_lower() == "glb":
		out.append(["GlbInstance",{node.scene_file_path:true}])
	return out

func _alpha_ok(node: Node) -> bool:
	if node is CanvasItem: return node.modulate.a*node.self_modulate.a > .01
	if node is Sprite3D or node is AnimatedSprite3D: return node.modulate.a > .01
	return true

## Walk the tree once. `label` names the moment in the log; sprite_label (optional) records the visible 3D sprites.
func sample(root: Node, tick: int, mode: String, label := "", sprite_label := "") -> void:
	samples += 1
	_tick = tick; _mode = mode
	_res_cache.clear(); _theme_cache.clear(); _round_visible.clear()
	for path in files:
		if ResourceLoader.has_cached(path) and not cached_ever.has(path): cached_ever[path] = tick
	for holder in holders:
		if holder != null and is_instance_valid(holder): _scan_holder(holder)
	_audio_nodes.clear()
	var sprites: Array = []
	var stack: Array = [root]
	var hidden_sprites := 0
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children(): stack.append(child)
		if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
			_audio_nodes.append(node)
			if node.stream != null:
				var s := _src(node.stream)
				_mark_attached(s,"AudioPlayer.stream")
			continue
		var is_sprite3d: bool = node is Sprite3D or node is AnimatedSprite3D
		var held: Array = _node_files(node)
		if held.is_empty() and not is_sprite3d: continue
		var shown := false
		if node is CanvasItem or node is Node3D:
			shown = node.is_visible_in_tree() and _alpha_ok(node)
			if node is Control and shown and node.size.x <= 0.0 and node.size.y <= 0.0: shown = false
		else:
			shown = true
		if node is Node3D and not node is Sprite3D and not node is AnimatedSprite3D and node.scene_file_path.get_extension().to_lower() == "glb":
			shown = shown and _glb_has_visible_mesh(node)
		for entry in held:
			var kind: String = entry[0]
			for path in entry[1]:
				if String(path).begins_with("?"):
					if shown: unidentified[kind+path] = int(unidentified.get(kind+path,0))+1
					continue
				if shown: _mark_visible(String(path),kind)
				else: _mark_attached(String(path),kind)
		if is_sprite3d:
			if shown:
				var texture_paths: Dictionary = {}
				if node is Sprite3D: _tex_paths(node.texture,texture_paths)
				else:
					if node.sprite_frames != null:
						for p in _frames_paths(node.sprite_frames): texture_paths[p] = true
				sprites.append({"class":node.get_class(),"name":String(node.name),"parent":String(node.get_parent().name),"textures":texture_paths.keys()})
			else:
				hidden_sprites += 1
	for path in _round_visible:
		visible[path].max_nodes = maxi(int(visible[path].max_nodes),int(_round_visible[path]))
	if not sprite_label.is_empty():
		var by_texture: Dictionary = {}
		for s in sprites:
			for t in s.textures: by_texture[t] = int(by_texture.get(t,0))+1
		sprite_report[sprite_label] = {"tick":tick,"visible_sprites":sprites.size(),"hidden_sprites":hidden_sprites,"by_texture":by_texture,"first_nodes":sprites.slice(0,24)}
	if not label.is_empty(): stage_log.append({"label":label,"tick":tick,"mode":mode,"audio_players":_audio_nodes.size()})
	sample_audio(tick)

## Textures and sounds kept in the variables of the presenters (a dictionary of textures, a loaded sheet). Held = loaded; it says
## nothing about drawing, so they are only marked attached.
func _scan_holder(holder: Object) -> void:
	var script: Script = holder.get_script()
	if script == null: return
	var key := script.get_instance_id()
	if not _script_vars.has(key):
		var names: Array = []
		for prop in script.get_script_property_list():
			if prop.type == TYPE_OBJECT or prop.type == TYPE_DICTIONARY or prop.type == TYPE_ARRAY: names.append(String(prop.name))
		_script_vars[key] = names
	for var_name in _script_vars[key]:
		_attach_value(holder.get(var_name),2)

func _attach_value(value: Variant, depth: int) -> void:
	if value is Texture2D:
		var found: Dictionary = {}
		_tex_paths(value,found)
		for p in found:
			if not String(p).begins_with("?"): _mark_attached(String(p),"PresenterVar")
	elif value is AudioStream:
		_mark_attached(_src(value),"PresenterVar")
	elif depth > 0 and value is Dictionary:
		for k in value: _attach_value(value[k],depth-1)
	elif depth > 0 and value is Array:
		for v in value: _attach_value(v,depth-1)

func _glb_has_visible_mesh(node: Node) -> bool:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and n.is_visible_in_tree() and n.mesh != null: return true
		for child in n.get_children(): stack.append(child)
	return false

## Cheap enough for every frame: which sounds are playing now.
func sample_audio(tick: int) -> void:
	for node in _audio_nodes:
		if not is_instance_valid(node) or not node.playing or node.stream == null: continue
		var path := _src(node.stream)
		if path.is_empty() and node.stream is AudioStreamWAV: path = _match_wav(node.stream)
		if path.is_empty(): continue
		if not played.has(path): played[path] = {"first_tick":tick,"frames":0}
		played[path].frames = int(played[path].frames)+1

## Length in seconds of a RIFF/WAVE file, from its "fmt " and "data" chunks (nothing is loaded as a resource).
func _wav_seconds(path: String) -> float:
	var handle := FileAccess.open(path,FileAccess.READ)
	if handle == null or handle.get_length() < 12: return -1.0
	handle.seek(12)
	var byte_rate := 0
	while handle.get_position()+8 <= handle.get_length():
		var id := handle.get_buffer(4).get_string_from_ascii()
		var length := handle.get_32()
		if id == "fmt ":
			handle.seek(handle.get_position()+8)
			byte_rate = handle.get_32()
			handle.seek(handle.get_position()+length-12)
		elif id == "data":
			return float(length)/float(byte_rate) if byte_rate > 0 else -1.0
		else:
			handle.seek(handle.get_position()+length)
		if length&1: handle.seek(handle.get_position()+1)
	return -1.0

## A pathless AudioStreamWAV (the duplicated ambience): imported as ADPCM, so its data size differs from the file's; the
## length in seconds does not. Matched when exactly one WAV file has the same length (within 5 ms).
func _match_wav(stream: AudioStreamWAV) -> String:
	if _wav_sizes.is_empty():
		for path in files:
			if path.get_extension().to_lower() == "wav": _wav_sizes[path] = _wav_seconds(path)
	var matches: Array = []
	for path in _wav_sizes:
		if absf(float(_wav_sizes[path])-stream.get_length()) < .005: matches.append(path)
	if matches.size() == 1: image_matched[String(matches[0])] = true
	return "" if matches.size() != 1 else String(matches[0])

func report(view: Node, meta: Dictionary) -> Dictionary:
	var rows: Dictionary = {}
	for path in files:
		var row := {"cached_ever":cached_ever.has(path),"cached_now":ResourceLoader.has_cached(path),"attached":attached.has(path),
			"visible":visible.has(path),"played":played.has(path),"identified_by_content":image_matched.has(path)}
		if cached_ever.has(path): row.first_cached_tick = cached_ever[path]
		if attached.has(path): row.attached_kinds = attached[path].keys()
		if visible.has(path): row.visible_kinds = visible[path].kinds.keys(); row.first_visible_tick = visible[path].first_tick; row.first_visible_mode = visible[path].first_mode; row.max_visible_nodes = visible[path].max_nodes
		if played.has(path): row.played_info = played[path]
		rows[path.trim_prefix("res://")] = row
	var raw: Dictionary = {}
	var actors = view.get("actors")
	if actors != null: raw["actors"] = actors.get("raw_texture_fallbacks")
	var audio = view.get("audio")
	if audio != null:
		raw["audio"] = audio.get("raw_fallbacks")
		meta["audio_played_counter"] = audio.get("played")
		meta["audio_dropped_counter"] = audio.get("dropped")
	var world = view.get("world")
	if world != null and world.get("art_status") != null: raw["world"] = world.get("art_status")
	return {"meta":meta,"files":rows,"raw_fallbacks":raw,"unidentified_visible_textures":unidentified,"sprite3d":sprite_report,"stages":stage_log,"samples":samples,
		"limits":["has_cached misses a resource loaded and freed between two samples and raw Image.load_from_file fallbacks",
			"UiStyle.blit and RenderingServer draw calls are seen only through AtlasBox style boxes and script variables of visible nodes",
			"a visible node may be outside the camera frustum or behind another node",
			"pathless AudioStreamWAV (duplicated ambience) is matched by data size to a cached WAV"]}
