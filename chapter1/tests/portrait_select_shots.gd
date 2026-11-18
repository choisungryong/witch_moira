extends SceneTree
## Captures the title menu's living portrait with the real input path (focus on a start button picks the witch).
## Needs a real renderer (no --headless). Writes only under the directory given by --shots.
##   python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/portrait_select_shots.gd -- --chapter1-profile-off --chapter1-qa-ignore-focus --shots=_local/shots/portrait-select --tag=1080
##   --mode=video  saves every 2nd frame of a 12 s run (witch changes every 4 s) as PNG to --shots/frames; make the video with ffmpeg.
## Prints PORTRAIT_STATE lines (is the portrait node in the tree, processing) at the menu and after the run starts.

var view: Node
var frame := 0
var shots_dir := ""
var tag := "1080"
var mode := "shots"
var primary := "chapter1.skill.ember"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="): shots_dir = arg.trim_prefix("--shots=")
		elif arg.begins_with("--tag="): tag = arg.trim_prefix("--tag=")
		elif arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
	var scene: PackedScene = load("res://chapter1/ChapterOne.tscn")
	view = scene.instantiate()
	root.add_child(view)
	DirAccess.make_dir_recursive_absolute(shots_dir)

func _shot(name_: String) -> void:
	var image := root.get_viewport().get_texture().get_image()
	if image != null: image.save_png(shots_dir.path_join("%s-%s.png" % [name_, tag]))

func _pick(index: int) -> void:
	view.hud._menu_starts[index].grab_focus()

func _find(node: Node, out: Array) -> void:
	var script: Script = node.get_script()
	if script != null and String(script.resource_path).ends_with("/living_portrait.gd"): out.append(node)
	for child in node.get_children(): _find(child, out)

func _state(label: String) -> void:
	var found: Array = []
	_find(root, found)
	var rows: Array = []
	for n in found:
		rows.append({"in_tree": n.is_inside_tree(), "active": n.active, "processing": n.can_process(), "is_processing": n.is_processing(), "witch": n.witch_id, "visible_in_tree": n.is_visible_in_tree(), "children": n.get_child_count()})
	print("PORTRAIT_STATE ", JSON.stringify({"label": label, "mode": view.run.mode, "portrait_nodes": found.size(), "rows": rows, "hud_ref": view.hud._living_portrait != null and is_instance_valid(view.hud._living_portrait)}))

func _process(_delta: float) -> bool:
	if view == null or not view.is_inside_tree(): return false
	frame += 1
	if mode == "soak":
		# one witch for a long time, to look for log errors (the ribbon polygon warning came and went with the noise)
		if frame == 2: _pick(int(tag))
		return frame > 5400
	if mode == "video":
		if frame == 240: _pick(1)
		elif frame == 480: _pick(2)
		if frame % 2 == 0 and frame <= 720:
			var image := root.get_viewport().get_texture().get_image()
			DirAccess.make_dir_recursive_absolute(shots_dir.path_join("frames"))
			image.save_png(shots_dir.path_join("frames/f%04d.png" % (frame / 2)))
		return frame > 720
	match frame:
		4: _state("menu-open")
		150: _shot("select-ember"); _state("menu-ember")
		151: _pick(1)
		170: _shot("select-frost-intro")
		290: _shot("select-frost"); _state("menu-frost")
		291: _pick(2)
		310: _shot("select-storm-intro")
		430: _shot("select-storm"); _state("menu-storm")
		431: _pick(0)
		432: view.start_run(primary)
		440: _shot("run-start")
		441: _state("run-start-8f")
		700: _state("run-after-4s")
		701: return true
	return false
