extends SceneTree
## Map-edge capture tool (A10 W4, U-64). Starts a run on the real scene, holds the hero at points on the walkable edge of
## zone 0 (and 1 m inside it) and saves one screenshot per point, plus a JSON of how far the hero's feet are from the
## nearest thing that blocks the eye. Presentation only: the only thing written is the hero position of this throw-away process.
##
##   python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/edge_shots.gd -- \
##       --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-seed=11 --shots=_local/shots/<name> [--points=a,b,...] [--combat=south]
##
## Points (zone 0 walk half-size and centre come from the world's edge table, else 19 m / origin):
##   south north west east east-wall corner-sw corner-ne corner-se corner-nw  = on the walkable edge
##   in-south in-north in-west in-east-wall                                    = 1 m inside it
## --at=x,y,name (repeatable) adds any point; with --at and no --points only those are shot (e.g. zone 2 corners: --at=115,19,z2-se).
## --combat=<point> keeps the hero pinned at that point with the built-in pilot fighting until >= 8 enemies are within 12 m, then shoots.
## Needs --chapter1-profile-off and --shots=_local/... Output: <name>/edge-NN-<point>.png and <name>/edges.json.
var view: Node
var frame := 0
var stage := 0
var idx := 0
var hold := 0
var shots_dir := ""
var want: PackedStringArray = []
var combat_point := ""
var custom: Array = []
var results: Array = []
var center := Vector2.ZERO
var half := 19.0
var points: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="): shots_dir = arg.trim_prefix("--shots=")
		elif arg.begins_with("--points="): want = arg.trim_prefix("--points=").split(",", false)
		elif arg.begins_with("--combat="): combat_point = arg.trim_prefix("--combat=")
		elif arg.begins_with("--at="):
			var f := arg.trim_prefix("--at=").split(",", false)
			if f.size() == 3: custom.append([f[2], Vector2(float(f[0]), float(f[1]))])
	if not shots_dir.begins_with("_local/"):
		push_error("edge_shots: --shots=_local/... required")
		quit(2)
		return
	view = load("res://chapter1/ChapterOne.tscn").instantiate()
	root.add_child(view)

func _build_points() -> void:
	if view.world.has_method("edge_rows"):
		var rows: Array = view.world.edge_rows()
		if not rows.is_empty():
			center = rows[0].center
			half = float(rows[0].half)
	if "edge_stats" in view.world:
		print("EDGE_STATS ", JSON.stringify(view.world.edge_stats))
	var h := half
	var c := center
	var all := {
		"south": c + Vector2(0, h), "north": c + Vector2(0, -h), "west": c + Vector2(-h, 0), "east": c + Vector2(h, 0),
		"east-wall": c + Vector2(h, 8), "corner-sw": c + Vector2(-h, h), "corner-ne": c + Vector2(h, -h),
		"corner-se": c + Vector2(h, h), "corner-nw": c + Vector2(-h, -h),
		"in-south": c + Vector2(0, h - 1), "in-north": c + Vector2(0, -h + 1), "in-west": c + Vector2(-h + 1, 0),
		"in-east-wall": c + Vector2(h - 1, 8),
	}
	var order: Array = ["south", "north", "west", "east", "east-wall", "corner-sw", "corner-ne", "corner-se", "corner-nw",
		"in-south", "in-north", "in-west", "in-east-wall"]
	for name in order:
		if (want.is_empty() or name in want) and combat_point == "" and (custom.is_empty() or not want.is_empty()):
			points.append([name, all[name]])
	if combat_point != "":
		points.append([combat_point, all[combat_point]])
	points.append_array(custom)

func _process(_d: float) -> bool:
	frame += 1
	if frame > 40000:
		quit(4)
		return true
	var run: RefCounted = view.run
	match stage:
		0:
			if frame == 11:
				view.start_run("chapter1.skill.frost")
				stage = 1
		1:
			if run.mode == "playing" and run.tick >= 60:
				_build_points()
				stage = 2
				hold = 0
		2:
			if idx >= points.size():
				_finish()
				return true
			run.hero.position = points[idx][1]
			hold += 1
			var ready: bool = hold >= 30 and run.mode == "playing"
			if combat_point != "":
				var near := 0
				var list: Array = run.enemies.values() if run.enemies is Dictionary else run.enemies
				for e in list:
					if e is Dictionary and e.has("position") and (e.position as Vector2).distance_to(run.hero.position) < 12.0:
						near += 1
				ready = ready and near >= 8
			if ready:
				_shoot(run)
				idx += 1
				hold = 0
	return false

func _shoot(run: RefCounted) -> void:
	DirAccess.make_dir_recursive_absolute(shots_dir)
	var img := root.get_viewport().get_texture().get_image()
	var name: String = points[idx][0]
	var p := shots_dir.path_join("edge-%02d-%s.png" % [idx, name])
	img.save_png(p)
	var cam: Camera3D = view.world.camera
	var hero: Vector2 = run.hero.position
	## unproject_position is in canvas units (1600 x 900 stretch); the saved image is in window pixels.
	var size := root.get_viewport().get_visible_rect().size
	var k := float(img.get_width()) / size.x
	var foot := cam.unproject_position(Vector3(hero.x, 0, hero.y)) * k
	var rec := {"point": name, "hero": [hero.x, hero.y], "foot_px": [foot.x, foot.y], "image": [img.get_width(), img.get_height()], "file": p}
	if view.world.has_method("edge_anchors"):
		var best := INF
		var best_at := Vector2.ZERO
		for a in view.world.edge_anchors():
			var px := cam.unproject_position(Vector3(a.x, 0, a.y)) * k
			var d := px.distance_to(foot)
			if d < best:
				best = d
				best_at = a
		rec["nearest_blocker_world"] = [best_at.x, best_at.y]
		rec["nearest_blocker_px"] = best
		rec["nearest_blocker_frac_of_height"] = best / float(img.get_height())
	results.append(rec)
	print("EDGE_SHOT ", JSON.stringify(rec))

func _finish() -> void:
	var f := FileAccess.open(shots_dir.path_join("edges.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	quit(0)
