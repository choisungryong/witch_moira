extends SceneTree
## Bakes the walker (skeleton outlaw) into vertex animation textures and verifies the result.
##   python tools/dev/godot.py --headless --path . --script res://chapter1/tests/bake_vat.gd -- --out=_local/vat/ [--save] [--cpu] [--no-verify]
## Without --save nothing is written (bake + verify only). Output is only allowed under _local/vat/.
## Writes <out>/walker/{pos.res,nrm.res,mesh.res,table.json} and <out>/walker-report.json with --save.

const Baker := preload("res://chapter1/view/actors/vat/vat_baker.gd")
const Spec := preload("res://chapter1/view/actors/vat/walker_vat_spec.gd")

func _initialize() -> void:
	# The root is not inside the tree yet during _initialize; AnimationPlayer and global transforms need it.
	await process_frame
	_main()

func _main() -> void:
	var out := "_local/vat/"
	var save := false
	var cpu := false
	var verify := true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
		elif arg == "--save":
			save = true
		elif arg == "--cpu":
			cpu = true
		elif arg == "--no-verify":
			verify = false
	out = out.replace("\\", "/")
	if not out.begins_with("_local/vat"):
		push_error("bake_vat: --out must be under _local/vat/ (got %s)" % out)
		quit(2)
		return
	if not out.ends_with("/"):
		out += "/"
	print("engine has bake_mesh_from_current_skeleton_pose: ", Baker.engine_supports_bake(), "  version ", Engine.get_version_info().string)
	var baker := Baker.new()
	baker.host = root
	# Headless uses the dummy renderer, where skeleton RIDs are not valid and the engine bake refuses to run
	# ("source mesh must have its skin registered with a valid skeleton"), so headless always bakes on the CPU.
	print("display server: ", DisplayServer.get_name())
	baker.use_engine_bake = Baker.engine_supports_bake() and not cpu and DisplayServer.get_name() != "headless"
	var scene: PackedScene = load(Spec.MODEL_PATH)
	var clips := Spec.clips()
	var t0 := Time.get_ticks_usec()
	var data := baker.bake(scene, clips, Spec.FPS, Spec.apply_overrides, Spec.TRACKED_BONES, Spec.HIT_BONES, Spec.HIT_EXCLUDE_BONES)
	var bake_sec := float(Time.get_ticks_usec() - t0) / 1e6
	var st: Dictionary = data.stats
	print("bake path: ", "engine bake_mesh_from_current_skeleton_pose" if baker.use_engine_bake else "CPU skinning")
	print("vertices ", data.vertex_count, "  rows ", data.total_rows, "  surfaces ", data.surface_counts)
	print("bake seconds %.3f  (rows %.3f, post %.3f, mesh %.3f)" % [bake_sec, st.rows_usec / 1e6, st.post_usec / 1e6, st.mesh_usec / 1e6])
	print("center ", data.center, "  aabb ", data.aabb)
	for clip_name in data.table:
		var c: Dictionary = data.table[clip_name]
		print("  clip %-12s start %3d rows %3d  %.3f s  rate %.2f rows/s  loop %s  anim length %.3f" % [clip_name, c.start, c.rows, c.duration, c.rate, c.loop, c.anim_length])
	print("pos image ", data.pos_image.get_width(), "x", data.pos_image.get_height(), " format ", data.pos_image.get_format(), " bytes ", data.pos_image.get_data().size())
	print("nrm image ", data.nrm_image.get_width(), "x", data.nrm_image.get_height(), " format ", data.nrm_image.get_format(), " bytes ", data.nrm_image.get_data().size())
	var report := {
		"engine_version": Engine.get_version_info().string, "bake_path": "engine" if baker.use_engine_bake else "cpu",
		"vertex_count": data.vertex_count, "total_rows": data.total_rows, "bake_seconds": bake_sec,
		"stats_seconds": {"rows": st.rows_usec / 1e6, "post": st.post_usec / 1e6, "mesh": st.mesh_usec / 1e6},
		"pos_bytes": data.pos_image.get_data().size(), "nrm_bytes": data.nrm_image.get_data().size(),
		"aabb": [data.aabb.position.x, data.aabb.position.y, data.aabb.position.z, data.aabb.size.x, data.aabb.size.y, data.aabb.size.z],
		"center": [data.center.x, data.center.y, data.center.z], "table": data.table,
	}
	if verify:
		var t1 := Time.get_ticks_usec()
		var v := baker.verify(scene, clips, Spec.apply_overrides, data, Spec.TRACKED_BONES)
		report["verify"] = v
		report["verify_seconds"] = float(Time.get_ticks_usec() - t1) / 1e6
		print("verify: ", v)
		print("verify seconds %.3f" % report.verify_seconds)
	if save:
		var dir := "res://" + out + "walker"
		var t2 := Time.get_ticks_usec()
		var sizes := baker.save(data, dir)
		report["save_seconds"] = float(Time.get_ticks_usec() - t2) / 1e6
		report["file_bytes"] = sizes
		print("saved to ", dir, " in %.3f s: " % report.save_seconds, sizes)
		var t3 := Time.get_ticks_usec()
		var loaded := Baker.load_baked(dir, scene)
		report["load_seconds"] = float(Time.get_ticks_usec() - t3) / 1e6
		report["load_ok"] = not loaded.is_empty() and loaded.pos_tex != null and loaded.mesh != null
		print("load back %.3f s ok=%s" % [report.load_seconds, report.load_ok])
		var f := FileAccess.open("res://" + out + "walker-report.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	for e in baker.errors:
		push_error(e)
	quit(1 if not baker.errors.is_empty() else 0)
