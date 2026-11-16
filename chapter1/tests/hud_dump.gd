extends SceneTree
## Records the HUD's Control tree at fixed moments of a deterministic pilot run.
## Two HUD implementations are equivalent when their dumps are identical.
## Run inside the dev stage (imports are needed), headless with a fixed frame rate:
##
##   godot --headless --fixed-fps 60 --path <stage> --script res://chapter1/tests/hud_dump.gd -- \
##       --chapter1-pilot --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --dump=<file.json>
##
## Optional: --scene=<file.json> also records every 3D node (transforms, meshes, multimesh
## instances, animation state) so world, actor and effect presenters can be compared too.
## Optional: --until=<tick> stops early; --primary=<skill id>; --shots=<dir> also saves a
## screenshot per moment (needs a real renderer, so run without --headless).
var view: Node
var dumps: Dictionary = {}
var order: Array[String] = []
var out_path := ""
var primary := "chapter1.skill.frost"
var until_tick := 0
var shots_dir := ""
var scene_path := ""
var scenes: Dictionary = {}
var frame := 0
var step := 0
var choice_dumps := 0
var done_marks: Dictionary = {}
var unworn_since: Dictionary = {}
var end_frames := -1

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dump="): out_path = arg.trim_prefix("--dump=")
		elif arg.begins_with("--primary="): primary = arg.trim_prefix("--primary=")
		elif arg.begins_with("--until="): until_tick = int(arg.trim_prefix("--until="))
		elif arg.begins_with("--shots="): shots_dir = arg.trim_prefix("--shots=")
		elif arg.begins_with("--scene="): scene_path = arg.trim_prefix("--scene=")
	var scene: PackedScene = load("res://chapter1/ChapterOne.tscn")
	view = scene.instantiate()
	# A script that failed to compile leaves a bare node: stop instead of spinning.
	if view.get_script() == null or view.get("run") == null:
		push_error("ChapterOne failed to load its script; see the errors above")
		print("HUD_DUMP_RESULT ",JSON.stringify({"error":"scene_script_failed"}))
		quit(3)
		return
	root.add_child(view)

func _describe(node: Node, depth: int, rows: Array) -> void:
	if node is Control:
		var c: Control = node
		var row := {"d":depth,"class":c.get_class(),"name":String(c.name),"visible":c.is_visible_in_tree(),
			"x":snappedf(c.global_position.x,.01),"y":snappedf(c.global_position.y,.01),"w":snappedf(c.size.x,.01),"h":snappedf(c.size.y,.01),
			"modulate":c.modulate.to_html(),"tooltip":c.tooltip_text}
		if c is Label or c is Button or c is RichTextLabel or c is LineEdit: row.text = String(c.get("text"))
		if c is BaseButton: row.disabled = c.disabled
		if c is Range: row.value = snappedf(c.value,.001); row.max = snappedf(c.max_value,.001)
		if c is TextureRect: row.texture = c.texture.resource_path if c.texture != null else ""
		rows.append(row)
	for child in node.get_children():
		_describe(child,depth+1,rows)

func _vec(v: Vector3) -> Array:
	return [snappedf(v.x,.001),snappedf(v.y,.001),snappedf(v.z,.001)]

func _xform(t: Transform3D) -> Array:
	return [_vec(t.origin),_vec(t.basis.x),_vec(t.basis.y),_vec(t.basis.z)]

func _describe3d(node: Node, depth: int, rows: Array) -> void:
	if node is Node3D:
		var n: Node3D = node
		var row := {"d":depth,"class":n.get_class(),"name":String(n.name),"visible":n.is_visible_in_tree(),"t":_xform(n.global_transform)}
		if n is MultiMeshInstance3D and n.multimesh != null:
			var mm: MultiMesh = n.multimesh
			var shown := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			row.instances = mm.instance_count; row.shown = shown
			var sample: Array = []
			for i in mini(shown,24):
				var entry: Array = [_xform(mm.get_instance_transform(i))]
				if mm.use_colors: entry.append(mm.get_instance_color(i).to_html())
				if mm.use_custom_data: entry.append(mm.get_instance_custom_data(i).to_html())
				sample.append(entry)
			row.sample = sample
		if n is GeometryInstance3D:
			var material: Material = n.material_override
			row.material = "" if material == null else material.get_class()
			if material is ShaderMaterial and material.shader != null: row.shader = material.shader.resource_path
		if n is MeshInstance3D and n.mesh != null:
			row.mesh = n.mesh.get_class(); row.surfaces = n.mesh.get_surface_count()
		if n is Label3D: row.text = n.text; row.modulate = n.modulate.to_html()
		if n is Light3D: row.energy = snappedf(n.light_energy,.001); row.color = n.light_color.to_html()
		if n is Camera3D: row.fov = snappedf(n.fov,.01); row.size = snappedf(n.size,.01)
		rows.append(row)
	elif node is AnimationPlayer:
		rows.append({"d":depth,"class":"AnimationPlayer","name":String(node.name),"clip":String(node.current_animation),"at":snappedf(node.current_animation_position,.001) if node.current_animation != "" else 0.0})
	for child in node.get_children():
		_describe3d(child,depth+1,rows)

func _dump(label: String) -> void:
	if not scene_path.is_empty():
		var nodes: Array = []
		_describe3d(root,0,nodes)
		scenes[label] = nodes
		print("SCENE_DUMP ",JSON.stringify({"label":label,"nodes":nodes.size(),"tick":view.run.tick,"hash":JSON.stringify(nodes).sha256_text().left(16)}))
	var rows: Array = []
	_describe(root,0,rows)
	dumps[label] = rows
	order.append(label)
	if not shots_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(shots_dir)
		var image := root.get_viewport().get_texture().get_image()
		if image != null: image.save_png(shots_dir.path_join("%02d-%s.png" % [order.size(),label]))
	var visible := 0
	for row in rows:
		if row.visible: visible += 1
	print("HUD_DUMP ",JSON.stringify({"label":label,"controls":rows.size(),"visible":visible,"tick":view.run.tick,"mode":view.run.mode,"hash":JSON.stringify(rows).sha256_text().left(16)}))

func _mark(key: String) -> bool:
	if done_marks.has(key): return false
	done_marks[key] = true
	return true

func _process(_delta: float) -> bool:
	if view == null or not view.is_inside_tree(): return true
	frame += 1
	var run: RefCounted = view.run
	match step:
		0:
			if frame == 5:
				_dump("menu")
				view.hud.stash_open = true; view.hud.invalidate()
			elif frame == 8:
				_dump("stash")
				view.hud.stash_open = false; view.hud.invalidate()
			elif frame == 11:
				view.start_run(primary); step = 1
		1:
			if run.mode == "choice" and choice_dumps < 2:
				choice_dumps += 1; _dump("choice-%d" % choice_dumps)
			if run.tick >= 120 and _mark("p120"): _dump("playing-120")
			if run.tick >= 900 and run.mode == "playing" and _mark("inv"):
				view.open_equipment(); step = 2; frame = 0
		2:
			if frame == 3: _dump("inventory")
			elif frame == 4: view.close_equipment(); step = 3
		3:
			if run.mode == "choice" and choice_dumps < 2:
				choice_dumps += 1; _dump("choice-%d" % choice_dumps)
			if run.tick >= 1500 and run.mode == "playing" and _mark("pause"):
				view.toggle_pause(); step = 4; frame = 0
		4:
			if frame == 3: _dump("paused")
			elif frame == 4: view.toggle_pause(); step = 5; frame = 0
		5:
			step = 6
		6:
			# Show the better-item prompt once a bag item is not worn (presentation only).
			if not done_marks.has("offer") and run.mode == "playing":
				for item in run.inventory:
					if not run.equip_slot_of(int(item.uid)).is_empty() or not run.can_equip(item): continue
					# The pilot wears a better pickup on the next tick; wait for one it leaves in the bag.
					if not unworn_since.has(item.uid): unworn_since[item.uid] = frame
					if frame-int(unworn_since[item.uid]) >= 30:
						var data: Dictionary = run.compare_item(int(item.uid))
						view.hud.offer_upgrade(data.candidate,data.equipped,data.slot)
						done_marks["offer"] = frame
						print("HUD_DUMP_OFFER ",JSON.stringify({"tick":run.tick,"uid":item.uid,"name":item.name,"prompt_uid":view.hud.upgrade_uid})); break
			elif done_marks.has("offer") and frame == int(done_marks["offer"])+4 and _mark("offer-shot"):
				print("HUD_DUMP_OFFER_CHECK ",JSON.stringify({"tick":run.tick,"prompt_uid":view.hud.upgrade_uid}))
				if view.hud.upgrade_uid >= 0: _dump("upgrade-prompt")
				view.hud.clear_upgrade()
			if run.tick >= 2400 and _mark("p2400"): _dump("playing-2400")
			if run.tick >= 9000 and _mark("p9000"): _dump("playing-9000")
			if run.tick >= 16000 and _mark("p16000"): _dump("playing-16000")
			if run.mode in ["victory","defeat"] and end_frames < 0: end_frames = 0
			if until_tick > 0 and run.tick >= until_tick and end_frames < 0: end_frames = 20
	if end_frames >= 0:
		end_frames += 1
		if end_frames == 30:
			_dump("end-"+String(run.mode))
			_finish()
			return true
	if frame > 400000:
		push_error("hud_dump timed out"); _finish(); return true
	return false

func _finish() -> void:
	if not scene_path.is_empty():
		var scene_file := FileAccess.open(scene_path,FileAccess.WRITE)
		scene_file.store_string(JSON.stringify({"order":order,"scenes":scenes}))
		scene_file.close()
	if not out_path.is_empty():
		var file := FileAccess.open(out_path,FileAccess.WRITE)
		file.store_string(JSON.stringify({"order":order,"dumps":dumps}))
		file.close()
	print("HUD_DUMP_RESULT ",JSON.stringify({"labels":order,"final_tick":view.run.tick,"mode":view.run.mode,"kills":view.run.kills}))
