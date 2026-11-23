extends SceneTree
## QA tool (never product code): the skill lab window (docs/specs/T12-skill-lab-20261123.ko.md, SL-B).
## The real ChapterOne scene with the real core, effects and sound; a child node sets the stage and listens to
## <lab-dir>/command.json, writing <lab-dir>/state.json (the manager server's side is tools/manager/skill_lab.py).
##
##   python tools/dev/godot.py --timeout-s=14400 --resolution 1600x900 --path . --script res://chapter1/tests/skill_lab.gd -- \
##       --chapter1-start --chapter1-profile-off --chapter1-qa-ignore-focus --chapter1-trial=descent --chapter1-descent-cost=1000 \
##       --chapter1-seed=11 --chapter1-primary=chapter1.skill.arc --lab-dir=_local/skill-lab
##
## Own arguments (after "--"; the game's own arguments are read by the scene):
##   --lab-dir=<folder under _local/>          default _local/skill-lab
##   --lab-clip=<scene json under _local/>     one scene: stage, one cast, then quit after --lab-clip-seconds (default 4). Use with
##                                             --fixed-fps 60 --write-movie <file>.avi (window run) to get a movie with the engine's own sound.
##   --lab-clip-seconds=<s>
##   --lab-record=<folder under _local/>       same as a clip, and saves frames/fNNNNN.jpg + events.json (core events and sound requests per frame)
##   --lab-idle-quit-s=<s>                     quit after this long without a new command (default 3600)
## Exit codes: 0 normal, 3 the lab cannot start (folder refused, another window holds it).
const LabNode = preload("res://chapter1/tests/support/skill_lab_node.gd")
var view: Node
var lab: Node


func _initialize() -> void:
	var lab_dir := "_local/skill-lab"
	var clip := ""
	var seconds := 4.0
	var record := ""
	var idle := 3600.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lab-dir="): lab_dir = arg.trim_prefix("--lab-dir=")
		elif arg.begins_with("--lab-clip-seconds="): seconds = float(arg.trim_prefix("--lab-clip-seconds="))
		elif arg.begins_with("--lab-clip="): clip = arg.trim_prefix("--lab-clip=")
		elif arg.begins_with("--lab-record="): record = arg.trim_prefix("--lab-record=")
		elif arg.begins_with("--lab-idle-quit-s="): idle = float(arg.trim_prefix("--lab-idle-quit-s="))
	if not "--chapter1-profile-off" in OS.get_cmdline_user_args():
		printerr("SKILL_LAB_REFUSED --chapter1-profile-off is required (the lab never touches the player's save)")
		quit(3)
		return
	view = (load("res://chapter1/ChapterOne.tscn") as PackedScene).instantiate()
	root.add_child(view)
	lab = LabNode.new()
	lab.clip_file = clip
	lab.clip_seconds = seconds
	lab.record_rel = record
	lab.idle_quit_s = idle
	view.add_child(lab)
	var why: String = lab.setup(view, lab_dir)
	if not why.is_empty():
		printerr("SKILL_LAB_REFUSED ", why)
		quit(3)
		return
	print("SKILL_LAB_START ", JSON.stringify({"lab_dir": lab.lab_rel, "pid": OS.get_process_id(), "clip": clip, "record": record}))
