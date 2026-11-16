extends SceneTree
## Stand-alone preview of the skill-tree panel (G1 spec section 8) on fixture data. No core, no profile.
## Needs a real renderer. Run inside the dev stage:
##
##   godot --fixed-fps 60 --resolution 1280x720 --path <stage> --script res://chapter1/tests/skill_tree_preview.gd -- --shots=<dir>
##
## Saves one PNG per state and prints SKILL_TREE_PREVIEW lines, then an input-flow check
## (SKILL_TREE_INPUT) that drives the panel with synthetic key and mouse events and counts its signals.
const PanelScript = preload("res://chapter1/view/hud/skill_tree_panel.gd")
const FIXTURE := "res://chapter1/tests/fixtures/skill_tree_fixture.json"
const REAL_DATA := "res://chapter1/data/skill_trees.json"
const XP_CURVE := [0,250,600,1000,1500,2100,2800,3600,4500,5500,6700,8000,9500,11100,12900,14900,17100,19500,22100,25000]

var panel: Control
var tree: Dictionary = {}
var shots_dir := ""
var use_real := true
var portrait := "frost"   # --portrait=ember|storm shows another witch's face crop in the header
var frame := 0
var step := 0
var wait_until := 0
var captured: Array[String] = []
var signal_log: Array = []
var checks: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="): shots_dir = arg.trim_prefix("--shots=")
		elif arg == "--fixture": use_real = false
		elif arg.begins_with("--portrait="): portrait = arg.trim_prefix("--portrait=")
	var path := REAL_DATA if use_real and FileAccess.file_exists(REAL_DATA) else FIXTURE
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(doc) != TYPE_DICTIONARY or doc.get("trees",[]).is_empty():
		push_error("skill tree document missing or empty: "+path)
		quit(2); return
	tree = doc.trees[0]
	if path == REAL_DATA:
		# The real module validates the real document; the panel then uses exactly what it returns.
		var loaded: Dictionary = load("res://chapter1/core/skill_tree.gd").load_trees()
		if loaded.has("error"):
			push_error("load_trees failed: "+String(loaded.error)); quit(2); return
		tree = loaded["witch.frost"]
	# Stand-in for the game behind the panel, so the dim backdrop is judged against something.
	var backdrop := ColorRect.new()
	backdrop.color = Color("1d2a2e")
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)
	panel = PanelScript.new()
	root.add_child(panel)
	panel.commit_requested.connect(func(ranks: Dictionary): signal_log.append("commit:%d" % _sum(ranks)))
	panel.respec_requested.connect(func(): signal_log.append("respec"))
	panel.closed.connect(func(lost: int): signal_log.append("closed:%d" % lost))
	print("SKILL_TREE_PREVIEW ",JSON.stringify({"data":path,"window":[root.size.x,root.size.y]}))

func _sum(ranks: Dictionary) -> int:
	var total := 0
	for id in ranks: total += int(ranks[id])
	return total

func _info(level: int, xp: int) -> Dictionary:
	var floor_xp: int = XP_CURVE[level-1]
	var next_xp: int = XP_CURVE[level] if level < XP_CURVE.size() else -1
	return {"name":"서리의 마녀","xp":xp,"xp_floor":floor_xp,"xp_next":next_xp,"essence":31,"respec_cost":0,"portrait":portrait}

func _show(level: int, xp: int, free: int, ranks: Dictionary, selected: String) -> void:
	panel.set_data(tree,ranks,level,free,_info(level,xp))
	panel.select_node(selected)

func _key(code: int, echo := false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code as Key; ev.pressed = true; ev.echo = echo
	panel._gui_input(ev)

func _click(point: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = point; ev.button_index = button as MouseButton; ev.pressed = true
	panel._gui_input(ev)

func _tile_point(id: String) -> Vector2:
	panel._layout()
	return panel._u(panel._tiles[id].get_center())

func _button_point(key: String) -> Vector2:
	panel._layout()
	return panel._u(panel._btns[key].get_center())

func _check(label: String, ok: bool) -> void:
	checks.append({"check":label,"ok":ok})

func _shot(label: String) -> void:
	if shots_dir.is_empty(): return
	DirAccess.make_dir_recursive_absolute(shots_dir)
	var image := root.get_viewport().get_texture().get_image()
	var path := shots_dir.path_join("%02d-%s-%dx%d.png" % [captured.size()+1,label,root.size.x,root.size.y])
	image.save_png(path)
	captured.append(path)
	print("SKILL_TREE_SHOT ",path)

func _process(_delta: float) -> bool:
	frame += 1
	if frame < wait_until: return false
	const PARTIAL := {"witch.frost.needle":3,"witch.frost.volley":1,"witch.frost.rime":2,"witch.frost.chill":2}
	match step:
		0:
			_show(4,1000,6,{},"witch.frost.needle"); _next("empty-tree")
		1:
			_show(8,3880,2,PARTIAL,"witch.frost.volley"); _next("partial")
		2:
			# Staged: one rank of volley and one of shatter, both unconfirmed.
			panel.select_node("witch.frost.volley"); panel.invest_selected()
			panel.select_node("witch.frost.shatter"); panel.invest_selected()
			panel.select_node("witch.frost.volley"); _next("staged")
		3:
			_show(8,3880,0,PARTIAL,"witch.frost.needle"); _next("no-points")
		4:
			_show(8,3880,2,PARTIAL,"witch.frost.oath_lance"); _next("locked-level-and-prereq")
		5:
			_show(8,3880,2,PARTIAL,"witch.frost.deep_oath"); _next("locked-deep-oath")
		6:
			var late := {"witch.frost.needle":5,"witch.frost.volley":3,"witch.frost.oath_lance":3,"witch.frost.rime":5,"witch.frost.field":3,"witch.frost.dominion":1,"witch.frost.chill":3,"witch.frost.shatter":3,"witch.common.vigor":5,"witch.common.ward":1}
			_show(20,25000,0,late,"witch.frost.dominion"); _next("level20-late")
		7:
			_show(8,3880,2,PARTIAL,"witch.common.favor")
			panel.invest_selected()
			panel.select_node("witch.frost.volley"); panel.invest_selected()
			panel.request_close(); _next("confirm-discard")
		8:
			panel._resolve_confirm(false)
			panel.show_error("저장하지 못했습니다. 예정 투자는 화면에 남겨 두었습니다. 다시 확정하세요.")
			_next("save-error")
		9:
			_input_flow(); step = 10
		10:
			print("SKILL_TREE_INPUT ",JSON.stringify({"signals":signal_log,"checks":checks}))
			print("SKILL_TREE_RESULT ",JSON.stringify({"shots":captured.size(),"checks_failed":checks.filter(func(c): return not c.ok).size()}))
			quit(0)
			return true
	return false

func _next(label: String) -> void:
	# Two frames let _draw run, then capture on the following one.
	wait_until = frame+4
	_shot_after(label)

func _shot_after(label: String) -> void:
	# Capture happens in the next processed frame: defer through the scene tree timer-free by a signal.
	RenderingServer.frame_post_draw.connect(func(): _shot(label),CONNECT_ONE_SHOT)
	step += 1

func _input_flow() -> void:
	signal_log.clear()
	panel.open()
	panel.set_data(tree,{"witch.frost.needle":3,"witch.frost.volley":1,"witch.frost.rime":2,"witch.frost.chill":2},8,2,_info(8,3880))
	panel.select_node("witch.frost.needle")
	# The guard ignores Enter right after opening (Input48).
	_key(KEY_ENTER)
	_check("enter just after open does not invest",panel.staged_delta() == 0)
	OS.delay_msec(300)
	_key(KEY_SPACE)
	_check("space does nothing",panel.staged_delta() == 0)
	_key(KEY_DOWN)
	_check("down moves from needle to volley",panel.selected == "witch.frost.volley")
	_key(KEY_ENTER,true)
	_check("held enter (echo) does not invest",panel.staged_delta() == 0)
	_key(KEY_ENTER)
	_check("enter invests volley",panel.staged_delta() == 1 and int(panel.staged["witch.frost.volley"]) == 2)
	_key(KEY_BACKSPACE)
	_check("backspace undoes",panel.staged_delta() == 0)
	_key(KEY_BACKSPACE)
	_check("backspace on committed rank does nothing",int(panel.staged["witch.frost.volley"]) == 1)
	_key(KEY_RIGHT)
	_check("right moves to a neighbouring column",panel.selected != "witch.frost.volley")
	_click(_tile_point("witch.frost.rime"))
	_check("left click selects and invests rime",panel.selected == "witch.frost.rime" and int(panel.staged["witch.frost.rime"]) == 3)
	_click(_tile_point("witch.frost.rime"),MOUSE_BUTTON_RIGHT)
	_check("right click undoes rime",int(panel.staged["witch.frost.rime"]) == 2)
	_click(_tile_point("witch.frost.oath_lance"))
	_check("click on locked node selects without investing",panel.selected == "witch.frost.oath_lance" and not panel.staged.has("witch.frost.oath_lance"))
	_click(_tile_point("witch.frost.shatter"))
	_click(_tile_point("witch.frost.volley"))
	_check("two points staged then none left",panel.staged_delta() == 2)
	_click(_tile_point("witch.frost.needle"))
	_check("no free point: invest refused",panel.staged_delta() == 2)
	_key(KEY_F)
	_check("F emits commit_requested once with the full ranks",signal_log.count("commit:%d" % (8+2)) == 1)
	_key(KEY_ESCAPE)
	_check("Esc with staged asks before discarding",panel.confirm == "discard" and not signal_log.has("closed:2"))
	_key(KEY_ENTER)
	_check("modal default is keep editing",panel.confirm == "" and panel.staged_delta() == 2)
	_key(KEY_ESCAPE); _key(KEY_LEFT); _key(KEY_ENTER)
	_check("discard path emits closed with lost points",signal_log.has("closed:2") and panel.staged_delta() == 0)
	_key(KEY_ESCAPE)
	_check("Esc without staged closes",signal_log.count("closed:0") == 1)
	_key(KEY_R); _key(KEY_LEFT); _key(KEY_ENTER)
	_check("R then confirm emits respec_requested",signal_log.has("respec"))
	panel.set_data(tree,{},4,6,_info(4,1000))
	_click(_button_point("respec"))
	_check("respec button disabled with nothing invested",panel.confirm == "")
