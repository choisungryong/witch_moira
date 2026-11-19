extends SceneTree
## Equivalence dump for tools/dev/equiv.py (QA tool, reads presentation state only, writes no game state).
## Records, at fixed ticks of a deterministic pilot run: every enemy actor's transform, model transform, bone poses, animation
## clip and position, material class/colour/transparency, mesh visibility and cast_shadow; the hero rig the same way; and every
## Node3D held in a script variable of view.effects (MultiMesh instances, immediate-mesh vertex hashes). One hash per part,
## so two runs differ exactly where a part hash differs; --eq-full writes the parts themselves for field-level comparison.
##
##   godot --headless --fixed-fps 60 --path <root> --script res://chapter1/tests/equiv_dump.gd -- --chapter1-pilot
##       --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --primary=<skill id>
##       --eq-out=<file.json> [--eq-full=<file.json>] [--eq-ticks=600,2400,...] [--eq-until=<tick>]
##
## What it cannot see (equiv.py prints this list first): MultiMesh instance values in a headless run (the dummy renderer keeps
## only the counts; info.mm_nonidentity_transforms stays 0), ShaderMaterial uniforms and shader code (only the shader path),
## light and environment settings, nodes of view.juice and view.world, the HUD, audio, real pixels.
var view: Node
var primary := "chapter1.skill.ember"
var out_path := ""
var full_path := ""
var ticks: Array[int] = [600,2400,6000,9000,12000,16000,20000]
var next_index := 0
var frame := 0
var end_frames := -1
var started := false
var snapshots: Array = []
var full: Dictionary = {}
var until_tick := 0
var t0 := 0
const DEC := .0001

func _initialize() -> void:
	t0 = Time.get_ticks_msec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--primary="): primary = arg.trim_prefix("--primary=")
		elif arg.begins_with("--eq-out="): out_path = arg.trim_prefix("--eq-out=")
		elif arg.begins_with("--eq-full="): full_path = arg.trim_prefix("--eq-full=")
		elif arg.begins_with("--eq-until="): until_tick = int(arg.trim_prefix("--eq-until="))
		elif arg.begins_with("--eq-ticks="):
			ticks.clear()
			for s in arg.trim_prefix("--eq-ticks=").split(","): ticks.append(int(s))
	var scene: PackedScene = load("res://chapter1/ChapterOne.tscn")
	view = scene.instantiate()
	if view.get_script() == null or view.get("run") == null:
		push_error("ChapterOne failed to load its script")
		print("EQ_DUMP_RESULT ",JSON.stringify({"error":"scene_script_failed"}))
		quit(3)
		return
	root.add_child(view)

func _r(x: float) -> float:
	return snappedf(x,DEC)

func _xf4(t: Transform3D) -> Array:
	return [_r(t.basis.x.x),_r(t.basis.x.y),_r(t.basis.x.z),_r(t.basis.y.x),_r(t.basis.y.y),_r(t.basis.y.z),_r(t.basis.z.x),_r(t.basis.z.y),_r(t.basis.z.z),_r(t.origin.x),_r(t.origin.y),_r(t.origin.z)]

func _h(value: Variant) -> String:
	return var_to_str(value).sha256_text().left(12)

func _bones(skel: Skeleton3D) -> Array:
	var rows: Array = []
	if skel == null: return rows
	for i in skel.get_bone_count():
		var p := skel.get_bone_pose_position(i)
		var q := skel.get_bone_pose_rotation(i)
		var s := skel.get_bone_pose_scale(i)
		rows.append([_r(p.x),_r(p.y),_r(p.z),_r(q.x),_r(q.y),_r(q.z),_r(q.w),_r(s.x),_r(s.y),_r(s.z)])
	return rows

func _meshes(node: Node, rows: Array, base: Node) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		var mats: Array = []
		var list: Array = [mi.material_override]
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count(): list.append(mi.get_surface_override_material(s))
		for m in list:
			if m == null:
				mats.append(null)
			elif m is BaseMaterial3D:
				mats.append([m.get_class(),m.albedo_color.to_html(),int(m.transparency)])
			elif m is ShaderMaterial:
				mats.append([m.get_class(),m.shader.resource_path if m.shader != null else ""])
			else:
				mats.append([m.get_class()])
		rows.append({"p":String(base.get_path_to(mi)),"vis":mi.visible,"shadow":int(mi.cast_shadow),"surf":mi.mesh.get_surface_count() if mi.mesh != null else 0,"mats":mats,"t":_xf4(mi.global_transform)})
	for c in node.get_children(): _meshes(c,rows,base)

func _anim(player: AnimationPlayer) -> Array:
	if player == null or not is_instance_valid(player): return []
	return [String(player.current_animation),_r(player.current_animation_position) if player.current_animation != "" else 0.0]

func _scalars(state: Variant) -> Dictionary:
	var out := {}
	if state is Dictionary:
		for k in state:
			var v = state[k]
			if v is float: out[str(k)] = _r(v)
			elif v is int or v is bool or v is String: out[str(k)] = v
	return out

func _snapshot(label: String) -> void:
	var parts := {}
	var info := {}
	var dump_full := not full_path.is_empty()
	var fulls := {}
	var actors = view.actors
	# 1. enemy actors, in key order
	var keys: Array = actors.actors.keys()
	keys.sort_custom(func(a, b): return str(a) < str(b))
	var alive := 0
	var bones_total := 0
	for key in keys:
		var node = actors.actors[key]
		if not is_instance_valid(node): continue
		var kind := "plain"
		var state: Variant = null
		if node.has_meta("minion19"):
			kind = "minion19"; state = node.get_meta("minion19")
		elif node.has_meta("enemy_rig"):
			kind = "enemy_rig"; state = node.get_meta("enemy_rig")
		var skel: Skeleton3D = state.skeleton if state is Dictionary and state.has("skeleton") else null
		var player: AnimationPlayer = state.player if state is Dictionary and state.has("player") else null
		var meshes: Array = []
		_meshes(node,meshes,node)
		var bones := _bones(skel)
		bones_total += bones.size()
		var model_t: Array = []
		if state is Dictionary and state.has("model") and is_instance_valid(state.model): model_t = _xf4(state.model.global_transform)
		var row := {"kind":kind,"actor_kind":String(node.get_meta("kind","")),"t":_xf4(node.global_transform),"vis":node.visible,"model_t":model_t,"anim":_anim(player),"state":_scalars(state)}
		var k := "a:"+str(key)
		parts[k+":base"] = _h(row)
		parts[k+":bones"] = _h(bones)
		parts[k+":meshes"] = _h(meshes)
		if dump_full: fulls[k] = {"base":row,"bones":bones,"meshes":meshes}
		alive += 1
	info["actors"] = alive
	info["bones"] = bones_total
	# 2. hero
	if is_instance_valid(actors.hero):
		var hmeshes: Array = []
		_meshes(actors.hero,hmeshes,actors.hero)
		var hb := _bones(actors.rig_skeleton)
		var staff_t: Array = []
		if actors._staff != null and is_instance_valid(actors._staff): staff_t = _xf4(actors._staff.global_transform)
		var hero_rows := {"t":_xf4(actors.hero.global_transform),"bones":hb,"meshes":hmeshes,"staff":staff_t,"anim":_anim(actors.rig_player),"fade":_r(float(actors.hero.get_meta("owner_fade",1.0)))}
		parts["hero:base"] = _h([hero_rows.t,hero_rows.staff,hero_rows.anim,hero_rows.fade])
		parts["hero:bones"] = _h(hb)
		parts["hero:meshes"] = _h(hmeshes)
		info["hero_bones"] = hb.size()
		if dump_full: fulls["hero"] = hero_rows
	# 3. effects: every Node3D held in a script variable of view.effects (also dictionary values)
	var fx = view.effects
	var mm_visible := 0
	var mm_nonidentity := 0
	var mm_nodes := 0
	var im_surfaces := 0
	var im_nonempty_surfaces := 0
	for prop in fx.get_property_list():
		if (int(prop.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0: continue
		var v = fx.get(prop.name)
		var nodes: Array = []
		if v is Node3D:
			nodes.append([String(prop.name),v])
		elif v is Dictionary:
			var ks: Array = v.keys()
			ks.sort_custom(func(a, b): return str(a) < str(b))
			for kk in ks:
				if v[kk] is Node3D: nodes.append([str(prop.name)+"["+str(kk)+"]",v[kk]])
		for pair in nodes:
			var n: Node3D = pair[1]
			if not is_instance_valid(n): continue
			var name: String = pair[0]
			var entry := {"vis":n.visible,"t":_xf4(n.global_transform) if n.is_inside_tree() else []}
			if n is MultiMeshInstance3D and n.multimesh != null:
				var mm: MultiMesh = n.multimesh
				var shown := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
				var inst: Array = []
				for i in shown:
					var t := mm.get_instance_transform(i)
					var e: Array = [[t.basis.x,t.basis.y,t.basis.z,t.origin]]
					if mm.use_colors: e.append(mm.get_instance_color(i))
					if mm.use_custom_data: e.append(mm.get_instance_custom_data(i))
					inst.append(e)
					if t != Transform3D.IDENTITY: mm_nonidentity += 1
				entry["raw_visible"] = mm.visible_instance_count
				entry["count"] = mm.instance_count
				entry["shown"] = shown
				entry["inst"] = inst
				mm_nodes += 1
				mm_visible += shown
			elif n is MeshInstance3D and n.mesh != null:
				var surfs: Array = []
				var mesh: Mesh = n.mesh
				for s in mesh.get_surface_count():
					var arrays: Array = mesh.surface_get_arrays(s)
					im_surfaces += 1
					var verts = arrays[Mesh.ARRAY_VERTEX] if arrays.size() > Mesh.ARRAY_VERTEX else null
					if verts != null and verts.size() > 0: im_nonempty_surfaces += 1
					surfs.append(_h(arrays))
				entry["surfaces"] = surfs
				entry["shadow"] = int(n.cast_shadow)
			parts["fx:"+name] = _h(entry)
			if dump_full: fulls["fx:"+name] = entry
	info["mm_nodes"] = mm_nodes
	info["mm_visible_instances"] = mm_visible
	info["mm_nonidentity_transforms"] = mm_nonidentity
	info["im_surfaces"] = im_surfaces
	info["im_nonempty_surfaces"] = im_nonempty_surfaces
	var total := _h(parts)
	var tick := int(view.run.tick)
	snapshots.append({"label":label,"tick":tick,"mode":String(view.run.mode),"hash":total,"parts":parts,"info":info})
	if dump_full: full[label] = fulls
	print("EQ_DUMP ",JSON.stringify({"tick":tick,"label":label,"hash":total,"info":info}))

func _process(_delta: float) -> bool:
	if view == null or not view.is_inside_tree(): return true
	frame += 1
	var run: RefCounted = view.run
	if not started:
		if frame == 11:
			view.start_run(primary)
			started = true
		return false
	if next_index < ticks.size() and run.tick >= ticks[next_index]:
		_snapshot("t%d" % ticks[next_index])
		next_index += 1
	if run.mode in ["victory","defeat"] and end_frames < 0: end_frames = 0
	if until_tick > 0 and run.tick >= until_tick and end_frames < 0: end_frames = 20
	if end_frames >= 0:
		end_frames += 1
		if end_frames == 30:
			_snapshot("end-"+String(run.mode))
			_finish()
			return true
	if frame > 600000:
		push_error("eq_dump timed out")
		_finish()
		return true
	return false

func _finish() -> void:
	if not out_path.is_empty():
		var f := FileAccess.open(out_path,FileAccess.WRITE)
		f.store_string(JSON.stringify({"primary":primary,"snapshots":snapshots}))
		f.close()
	if not full_path.is_empty():
		var f2 := FileAccess.open(full_path,FileAccess.WRITE)
		f2.store_string(JSON.stringify(full))
		f2.close()
	print("EQ_DUMP_RESULT ",JSON.stringify({"labels":snapshots.map(func(s): return s.label),"final_tick":view.run.tick,"mode":view.run.mode,"kills":view.run.kills,"wall_ms":Time.get_ticks_msec()-t0}))
