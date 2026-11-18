extends Node2D
## Thin demo scene for the living portrait part (living_portrait.gd). Not connected to the game.
##
## User arguments (after "--"):
##   --lp-witch=frost|ember|storm|all    all shows ember, frost and storm side by side (default frost)
##   --lp-motion=off                     the still picture (motion scale 0)
##   --lp-scale=X                        motion scale (default 1; the reduce-motion setting would use less)
##   --lp-breath=0|1 --lp-legs=0|1 --lp-sway=0|1 --lp-head=0|1 --lp-blink=0|1 --lp-snow=0|1 --lp-fx=0|1 --lp-glow=0|1
##   --lp-intro                          entrance (darkness lifts), --lp-seed=N
##   --lp-zoom=2 (upper body) | -2 (lower body)
##   --lp-capture=DIR --lp-frames=N --lp-fps=N   (DIR under _local/; the engine also needs --fixed-fps N)
##   --lp-perf=SECONDS                   frame time report
##   --lp-knee=X --lp-pelvis-x=X --lp-pelvis-y=X --lp-chest=X --lp-tilt=X   motion overrides (image pixels, degrees)

const LivingPortrait := preload("res://chapter1/view/hud/living_portrait/living_portrait.gd")
const CONFIG_DIR := "res://chapter1/view/hud/living_portrait/"
const ZOOM_CENTERS := {"frost": Vector2(500.0, 330.0), "ember": Vector2(540.0, 330.0), "storm": Vector2(525.0, 340.0)}
const LOWER_CENTERS := {"frost": Vector2(500.0, 1150.0), "ember": Vector2(520.0, 1150.0), "storm": Vector2(520.0, 1000.0)}
const LOWER_SCALE := {"frost": 1.25, "ember": 1.25, "storm": 0.85}

var witch := "frost"
var flags := {}
var motion_scale := 1.0
var intro_on := false
var seed_value := 7
var zoom := 1.0
var overrides := {}
var capture_dir := ""
var capture_frames := 300
var capture_fps := 30
var perf_seconds := 0.0
var repick := ""   # --lp-repick=ID: at frame 20 of a capture the first portrait switches to this witch (select_witch test)
var steps: Array = []   # --lp-steps=a,b,c: the same witch side by side, one motion scale per panel (same seed)

var _portraits: Array = []
var _names: Array[String] = []
var _perf: Array[float] = []
var _perf_t := 0.0
var _t := 0.0


func _ready() -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_parse_args()
	_names.assign(["ember", "frost", "storm"] if witch == "all" else [witch])
	if not steps.is_empty():
		_names.clear()
		for _s in steps:
			_names.append(witch)
	for i in _names.size():
		var p := LivingPortrait.new()
		add_child(p)
		p.motion_override = overrides
		p.set_flags(flags)
		p.set_seed(seed_value + i * 11 if witch == "all" else seed_value)
		p.set_motion_scale(float(steps[i]) if not steps.is_empty() else motion_scale)
		p.select_witch(_names[i])
		if intro_on:
			p.play_intro()
		_portraits.append(p)
	get_viewport().size_changed.connect(_layout)
	_layout()
	if perf_seconds > 0.0:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if capture_dir != "":
		_capture_loop()


func _layout() -> void:
	var size := get_viewport_rect().size
	var n := _portraits.size()
	for i in n:
		var rect := Rect2(size.x / n * i, 0.0, size.x / n, size.y)
		var fit := minf(rect.size.x / 1024.0, rect.size.y / 1536.0)
		if absf(zoom) > 1.0:
			var centers: Dictionary = ZOOM_CENTERS if zoom > 0.0 else LOWER_CENTERS
			var px := 1.25 if zoom > 0.0 else float(LOWER_SCALE[_names[i]])
			_portraits[i].set_rect(rect, px / fit, centers[_names[i]])
		else:
			_portraits[i].set_rect(rect)


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lp-witch="):
			witch = a.get_slice("=", 1)
		elif a == "--lp-motion=off":
			motion_scale = 0.0
		elif a.begins_with("--lp-repick="):
			repick = a.get_slice("=", 1)
		elif a.begins_with("--lp-steps="):
			for s in a.get_slice("=", 1).split(","):
				steps.append(float(s))
		elif a.begins_with("--lp-scale="):
			motion_scale = float(a.get_slice("=", 1))
		elif a.begins_with("--lp-breath=") or a.begins_with("--lp-legs=") or a.begins_with("--lp-sway=") or a.begins_with("--lp-head=") \
				or a.begins_with("--lp-blink=") or a.begins_with("--lp-snow=") or a.begins_with("--lp-fx=") or a.begins_with("--lp-glow="):
			flags[a.get_slice("=", 0).substr(5)] = a.get_slice("=", 1) == "1"
		elif a == "--lp-intro":
			intro_on = true
		elif a.begins_with("--lp-seed="):
			seed_value = int(a.get_slice("=", 1))
		elif a.begins_with("--lp-zoom="):
			zoom = float(a.get_slice("=", 1))
		elif a.begins_with("--lp-knee="):
			overrides["knee"] = float(a.get_slice("=", 1))
		elif a.begins_with("--lp-pelvis-x="):
			overrides["pelvis_x"] = float(a.get_slice("=", 1))
		elif a.begins_with("--lp-pelvis-y="):
			overrides["pelvis_y"] = float(a.get_slice("=", 1))
		elif a.begins_with("--lp-chest="):
			overrides["chest_rise"] = float(a.get_slice("=", 1))
		elif a.begins_with("--lp-tilt="):
			overrides["tilt_deg"] = float(a.get_slice("=", 1))
		elif a.begins_with("--lp-capture="):
			capture_dir = a.get_slice("=", 1)
		elif a.begins_with("--lp-frames="):
			capture_frames = int(a.get_slice("=", 1))
		elif a.begins_with("--lp-fps="):
			capture_fps = int(a.get_slice("=", 1))
		elif a.begins_with("--lp-perf="):
			perf_seconds = float(a.get_slice("=", 1))


func _process(delta: float) -> void:
	if perf_seconds > 0.0:
		_perf_t += delta
		if _perf_t > 1.0:
			_perf.append(delta * 1000.0)
		if _perf_t > 1.0 + perf_seconds:
			_report_perf()


func _capture_loop() -> void:
	if not capture_dir.begins_with("_local/"):
		push_error("capture dir must be under _local/")
		get_tree().quit(2)
		return
	var dir := ProjectSettings.globalize_path("res://").path_join(capture_dir)
	DirAccess.make_dir_recursive_absolute(dir)
	if _portraits.size() == 1:
		_portraits[0].open_table(dir.path_join("table.csv"))
	elif not steps.is_empty():
		for i in _portraits.size():
			_portraits[i].open_table(dir.path_join("table_s%d.csv" % i))
	await get_tree().process_frame
	await get_tree().process_frame
	for i in _portraits.size():
		var sch: Array = _portraits[i].blink_schedule()
		print("LP_BLINKS %s starts=%s lens=%s" % [_names[i], str(sch[0].slice(0, 6)), str(sch[1].slice(0, 6))])
	for i in capture_frames:
		_t = float(i) / float(capture_fps)
		if repick != "" and i == 20:
			_portraits[0].select_witch(repick)   # the character select screen switching to another witch
			_portraits[0].play_intro()
			_layout()
		for p in _portraits:
			p.advance_to(_t)
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(dir.path_join("f%03d.png" % i))
	for p in _portraits:
		p.close_table()
	print("LP_CAPTURE frames=%d dir=%s" % [capture_frames, capture_dir])
	get_tree().quit()


func _report_perf() -> void:
	_perf.sort()
	var n := _perf.size()
	var sum := 0.0
	for v in _perf:
		sum += v
	var vp := get_viewport().get_viewport_rid()
	print("LP_PERF witch=%s window=%s frames=%d avg_ms=%.2f p95_ms=%.2f max_ms=%.2f gpu_render_ms=%.2f" % [
		witch, str(get_viewport_rect().size), n, sum / maxf(n, 1.0), _perf[int(n * 0.95)], _perf[n - 1],
		RenderingServer.viewport_get_measured_render_time_gpu(vp)])
	get_tree().quit()
