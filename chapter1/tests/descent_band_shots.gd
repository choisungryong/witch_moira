extends SceneTree
## QA tool (never product code): the descent's band part (chapter1/view/hud/descent_band.gd) drawn ALONE, plus the numbers that part promises (A11 4.1, 4.5).
## It does not run the game or the core. The backdrop is a picture file (a real capture, --backdrop=) or a plain stand-in, with a flat dark layer on it
## in place of the field's darkening (which is descent_fx.gd's, a later step). The values are pushed from a TEST-ONLY timetable (A11 4.2, the long cut-in);
## the real timetable is the presenter's.
##
## Needs a real renderer for pictures (no --headless); the checks alone run headless. One resolution per process:
##   python tools/dev/godot.py --fixed-fps 60 --resolution 1920x1080 --path . --script res://chapter1/tests/descent_band_shots.gd -- \
##       --chapter1-profile-off --shots=_local/shots/a11-band --backdrop=_local/shots/descent-real/ember-01-s024.png --hero=817,350
##   python tools/dev/godot.py --headless --path . --script res://chapter1/tests/descent_band_shots.gd -- --checks-only
## Arguments: --shots=<dir under _local/>  --elements=ember,frost,arc  --progress=0.5,1.0 (fractions of the long cut-in's 0.9 s)  --locales=ko,en
##   --backdrop=<png>  --hero=<x,y> (the hood's top, code units; default 800,342)  --checks-only  --sheet (also write sheet.png, 1920x1080 process only)
## Prints DESCENT_BAND_SHOT lines and, last, CHAPTER1_DESCENT_BAND_RESULT {...}; exit code 1 on any failed check.
const DescentBand := preload("res://chapter1/view/hud/descent_band.gd")
const DescentCutscene := preload("res://chapter1/view/hud/descent_cutscene.gd")
const DescentCall := preload("res://chapter1/view/hud/descent_call.gd")
const Loc := preload("res://chapter1/view/loc.gd")
const ELEMENTS := ["ember", "frost", "arc"]
const LONG_SECONDS := 0.9

var shots_dir := ""
var elements: Array = ["ember", "frost", "arc"]
var progresses: Array = [0.5, 1.0]
var locales: Array = ["ko"]
var backdrop_path := ""
var hero_top := Vector2(800, 342)
var checks_only := false
var want_sheet := false
var want_cutscene := false   ## --cutscene: also the cut-scene part (needs --chapter1-asset-slots=<table with the video slots>)
var want_metrics := false    ## --metrics: band-area brightness/saturation/coverage table, name contrast
var base_image: Image = null
var metric_rows: Array[String] = []
var witch_element := ""   ## --witch=<element>: one extra picture per progress with the small sorceress guest on that element
var checks := 0
var failures: Array[String] = []
var notes: Array[String] = []
var written: Array[String] = []
var captured: Dictionary = {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="): shots_dir = arg.trim_prefix("--shots=")
		elif arg.begins_with("--elements="): elements = Array(arg.trim_prefix("--elements=").split(",", false))
		elif arg.begins_with("--progress="):
			progresses = []
			for part in arg.trim_prefix("--progress=").split(",", false): progresses.append(float(part))
		elif arg.begins_with("--locales="): locales = Array(arg.trim_prefix("--locales=").split(",", false))
		elif arg.begins_with("--backdrop="): backdrop_path = arg.trim_prefix("--backdrop=")
		elif arg.begins_with("--hero="):
			var parts := arg.trim_prefix("--hero=").split(",")
			if parts.size() == 2: hero_top = Vector2(float(parts[0]), float(parts[1]))
		elif arg == "--checks-only": checks_only = true
		elif arg == "--sheet": want_sheet = true
		elif arg == "--cutscene": want_cutscene = true
		elif arg == "--metrics": want_metrics = true
		elif arg.begins_with("--witch="): witch_element = arg.trim_prefix("--witch=")
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	geometry_checks()
	text_checks()
	if not checks_only and shots_dir != "":
		await _shoot()
	var result := {"checks": checks, "failures": failures, "notes": notes, "metrics": metric_rows, "written": written}
	print("CHAPTER1_DESCENT_BAND_RESULT ", JSON.stringify(result))
	quit(1 if not failures.is_empty() else 0)

# ---- numbers ----

func geometry_checks() -> void:
	# 4.1: the band's place, for the default hero and for a hero standing higher (the camera arrives late) or to the side.
	var cases := {"default": Vector2(800, 342), "high": Vector2(800, 320), "higher": Vector2(800, 296), "highest": Vector2(800, 250), "left": Vector2(300, 342), "right": Vector2(1400, 330), "capture": hero_top}
	for label in cases:
		var lay: Dictionary = DescentBand.layout(cases[label])
		check(float(lay.gap) >= 40.0 - 0.01 or bool(lay.squeezed), "%s: the gap above the hero is %.1f (needs 40) or the band is squeezed" % [label, float(lay.gap)])
		check(float(lay.low_y) <= 405.0 + 0.01, "%s: the band's lowest point y %.1f stays above 0.45 H (405)" % [label, float(lay.low_y)])
		check(float(lay.height) >= 180.0 - 0.01 and float(lay.height) <= 216.0 + 0.01, "%s: band height %.1f in 180..216" % [label, float(lay.height)])
		notes.append("layout %s: hero %s -> centre y %.1f, height %.1f, raised %.1f, squeezed %s, gap %.1f, lowest y %.1f" % [label, str(cases[label]), float(lay.centre.y), float(lay.height), float(lay.raised), str(lay.squeezed), float(lay.gap), float(lay.low_y)])
	var base: Dictionary = DescentBand.layout(Vector2(800, 342))
	check(absf(float(base.angle) + deg_to_rad(8.0)) < 0.0001, "the angle is -8 degrees")
	check(absf(float(base.centre.y) - 180.0) < 0.001 and absf(float(base.height) - 216.0) < 0.001, "default centre line y 180 at x 800, height 216")
	# The same in the other canvas scale (1.0 only: the project stretches 1600 x 900 to every window), and the 1080p/720p pixel sizes.
	check(absf(216.0 * 1.2 - 259.2) < 0.01 and absf(216.0 * 0.8 - 172.8) < 0.01, "216 code units is 259 px at 1080p and 173 px at 720p")
	check(float(DescentBand.hero_top_from_uv(Vector2(.5, .43)).y) < 400.0, "hero_top_from_uv answers in code units")

func text_checks() -> void:
	for code in ["ko", "en"]:
		Loc.set_locale(code)
		for el in ELEMENTS:
			var words: Dictionary = DescentBand.texts(el)
			var fit: Dictionary = DescentBand.fit_name(String(words.name))
			check(float(fit.width) <= DescentBand.NAME_MAX_W + 0.5, "%s %s: the name '%s' is %.0f wide at size %d (max %.0f)" % [code, el, words.name, float(fit.width), int(fit.size), DescentBand.NAME_MAX_W])
			check(int(fit.size) >= DescentBand.NAME_SIZE_MIN, "%s %s: the name's size %d is not below %d" % [code, el, int(fit.size), DescentBand.NAME_SIZE_MIN])
			check(String(words.name) != "descent.name." + el and String(words.line) != "descent.band.line", "%s %s: the name and the line are translated" % [code, el])
			check(not String(words.line).contains("{"), "%s %s: the line has no unfilled hole: %s" % [code, el, words.line])
			var bold := Loc.font("bold")
			var line_w := bold.get_string_size(String(words.line), HORIZONTAL_ALIGNMENT_LEFT, -1, DescentBand.LINE_SIZE).x
			check(line_w <= DescentBand.NAME_MAX_W, "%s %s: the small line is %.0f wide (max %.0f)" % [code, el, line_w, DescentBand.NAME_MAX_W])
			var said := String(words.demon_line)
			check((el == "arc") == (said == ""), "%s %s: only lightning's demon is silent (line '%s')" % [code, el, said])
			if said != "":
				var body := Loc.font("body")
				var said_w := body.get_string_size(said, HORIZONTAL_ALIGNMENT_LEFT, -1, DescentBand.DEMON_LINE_SIZE).x
				check(said_w <= 400.0, "%s %s: the demon's line is %.0f wide (box 400)" % [code, el, said_w])
			notes.append("text %s %s: name '%s' size %d width %.0f | line '%s' | demon line '%s'" % [code, el, words.name, int(fit.size), float(fit.width), words.line, said])
	Loc.set_locale("ko")

# ---- pictures ----

## The long cut-in's values at `t` seconds (A11 4.2). Test-only.
func timetable(t: float) -> Dictionary:
	return {"band_in": _span(t, .06, .24), "witch": 0.0, "demon": _span(t, .24, .44), "name": _span(t, .38, .50),
		"line": _span(t, .46, .56), "demon_line": _span(t, .50, .62), "trim_flash": sin(PI * _span(t, .38, .48)) if t >= .38 and t <= .48 else 0.0}

func _span(t: float, a: float, b: float) -> float:
	return clampf((t - a) / (b - a), 0.0, 1.0)

func _shoot() -> void:
	var win := root.get_window()
	var size_px := Vector2i(win.size)
	var dir := shots_dir.replace("\\", "/")
	var abs_dir := dir if dir.is_absolute_path() else ProjectSettings.globalize_path("res://" + dir)
	if not abs_dir.contains("/_local/"):
		failures.append("--shots must be a folder under _local/")
		return
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var back_layer := CanvasLayer.new(); back_layer.layer = -1
	root.add_child(back_layer)
	var back := Control.new()
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back_layer.add_child(back)
	var image: Image = null
	if backdrop_path != "":
		var p := backdrop_path.replace("\\", "/")
		image = Image.load_from_file(p if p.is_absolute_path() else ProjectSettings.globalize_path("res://" + p))
	if image != null and not image.is_empty():
		var rect := TextureRect.new()
		rect.texture = ImageTexture.create_from_image(image)
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		back.add_child(rect)
	else:
		notes.append("no backdrop picture: a plain stand-in (dark ground, a marker for the hero's hood, the combat bar's band)")
		var ground := ColorRect.new(); ground.color = Color(.10, .105, .11)
		ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		back.add_child(ground)
		var marker := ColorRect.new(); marker.color = Color(.45, .3, .6)
		marker.position = hero_top + Vector2(-14, 0); marker.size = Vector2(28, 70)
		back.add_child(marker)
		var bar := ColorRect.new(); bar.color = Color(.2, .16, .12)
		bar.position = Vector2(300, 750); bar.size = Vector2(1000, 150)
		back.add_child(bar)
	var scrim := ColorRect.new(); scrim.color = Color(0, 0, 0, .5)   # stand-in for A11 4.3's darkening
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.add_child(scrim)
	var band: Control = DescentBand.attach(root)
	band.auto_clock = false
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	base_image = root.get_texture().get_image()
	for code in locales:
		Loc.set_locale(String(code))
		for el in elements:
			for p in progresses:
				for guest in ([false, true] if String(el) == witch_element else [false]):
					band.open(String(el))
					var values := timetable(float(p) * LONG_SECONDS)
					if guest: values["witch"] = _span(float(p) * LONG_SECONDS, .12, .30)
					values["hero_top"] = hero_top
					values["clock"] = 1.0 + float(p)
					values["bonus"] = .15 if String(el) == "ember" and float(p) >= 1.0 else 0.0
					values["slide_out"] = String(el) != "arc"
					band.apply(values)
					for i in 3: await process_frame
					await RenderingServer.frame_post_draw
					var shot := root.get_texture().get_image()
					if want_metrics and not guest and float(p) >= 1.0 and String(code) == String(locales[0]):
						await _metrics_for(band, String(el), shot, values)
					var file := "%s/band-%s-%s%s-p%03d-%dx%d.png" % [abs_dir, code, el, "-witch" if guest else "", int(round(float(p) * 100.0)), size_px.x, size_px.y]
					if shot.save_png(file) == OK:
						written.append(file)
						if not guest: captured["%s|%s|%s" % [code, el, str(p)]] = shot
						print("DESCENT_BAND_SHOT ", file)
					else:
						failures.append("could not write " + file)
	if want_cutscene:
		await _shoot_cutscene(band, abs_dir, size_px)
	if want_sheet and size_px == Vector2i(1920, 1080):
		_write_sheet(abs_dir)

## A contact sheet: rows are the elements, columns the progress values, the first locale, each cell half size.
func _write_sheet(abs_dir: String) -> void:
	var code := String(locales[0])
	var cell := Vector2i(960, 540)
	var sheet := Image.create(cell.x * progresses.size(), cell.y * elements.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color.BLACK)
	for r in elements.size():
		for c in progresses.size():
			var key := "%s|%s|%s" % [code, elements[r], str(progresses[c])]
			if not captured.has(key): continue
			var small: Image = (captured[key] as Image).duplicate()
			small.convert(Image.FORMAT_RGBA8)
			small.resize(cell.x, cell.y, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(small, Rect2i(Vector2i.ZERO, cell), Vector2i(cell.x * c, cell.y * r))
	var file := abs_dir + "/sheet.png"
	if sheet.save_png(file) == OK:
		written.append(file)
		print("DESCENT_BAND_SHOT ", file)

# ---- metrics ----

func _small(img: Image) -> Image:
	var s: Image = img.duplicate()
	s.convert(Image.FORMAT_RGBA8)
	s.resize(480, 270, Image.INTERPOLATE_BILINEAR)
	return s

## Area figures of the band: the pixels that differ from the same frame without the band. Body-only (no demon, no name, no lines) gives the brightness and the
## saturation of the band's own surface; the full band gives the share of the screen it covers (body + overflow). Also the contrast round the name.
func _metrics_for(band: Control, el: String, full: Image, values: Dictionary) -> void:
	var body_values := values.duplicate()
	for key in ["demon", "name", "line", "demon_line", "witch"]: body_values[key] = 0.0
	band.apply(body_values)
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var body := _small(root.get_texture().get_image())
	var base := _small(base_image)
	var fullimg := _small(full)
	var n_body := 0
	var lum := 0.0
	var sat := 0.0
	var n_full := 0
	for y in 270:
		for x in 480:
			var b := base.get_pixel(x, y)
			var c := body.get_pixel(x, y)
			if absf(c.r - b.r) + absf(c.g - b.g) + absf(c.b - b.b) > .12:
				n_body += 1
				lum += .299 * c.r + .587 * c.g + .114 * c.b
				var mx := maxf(c.r, maxf(c.g, c.b))
				var mn := minf(c.r, minf(c.g, c.b))
				sat += (mx - mn) / maxf(mx, .001)
			var f := fullimg.get_pixel(x, y)
			if absf(f.r - b.r) + absf(f.g - b.g) + absf(f.b - b.b) > .12: n_full += 1
	var total := 480.0 * 270.0
	# Contrast round the name: the text's pixels against the plate's, in a box on the name's line (screen units to this 480 x 270 picture).
	var lay := DescentBand.layout(hero_top)
	var words := DescentBand.texts(el)
	var fit := DescentBand.fit_name(String(words.name))
	var cx := DescentBand.NAME_CENTER_X
	var cy: float = float(lay.centre.y) - tan(DescentBand.TILT) * (cx - 800.0) + DescentBand.NAME_Y
	var half_w: float = float(fit.width) * .5 + 20.0
	var dark_sum := 0.0
	var dark_n := 0
	var light_sum := 0.0
	var light_n := 0
	var sx := 480.0 / 1600.0
	for y in range(int((cy - 45.0) * sx), int((cy + 45.0) * sx)):
		for x in range(int((cx - half_w) * sx), int((cx + half_w) * sx)):
			var c2 := fullimg.get_pixel(x, y)
			var l2 := .299 * c2.r + .587 * c2.g + .114 * c2.b
			if l2 < .45:
				dark_sum += l2; dark_n += 1
			elif l2 > .62:
				light_sum += l2; light_n += 1
	var l_bg := dark_sum / maxf(1.0, float(dark_n))
	var l_fg := light_sum / maxf(1.0, float(light_n))
	var ratio := (l_fg + .05) / (l_bg + .05)
	metric_rows.append("%s | band area mean brightness %.3f | mean saturation %.3f | band+overflow share of the screen %.1f %% | body-only share %.1f %% | name contrast (box +20) %.1f:1 (text %.2f over %.2f)" % [el, lum / maxf(1.0, float(n_body)), sat / maxf(1.0, float(n_body)), 100.0 * float(n_full) / total, 100.0 * float(n_body) / total, ratio, l_fg, l_bg])
	band.apply(values)
	for i in 2: await process_frame

# ---- the cut-scene part ----

func _grab(abs_dir: String, label: String, size_px: Vector2i) -> void:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	var file := "%s/%s-%dx%d.png" % [abs_dir, label, size_px.x, size_px.y]
	if shot.save_png(file) == OK:
		written.append(file)
		print("DESCENT_BAND_SHOT ", file)
	else:
		failures.append("could not write " + file)

func _shoot_cutscene(band: Control, abs_dir: String, size_px: Vector2i) -> void:
	Loc.set_locale(String(locales[0]))
	var cut: Control = DescentCutscene.attach(root)
	var call: Control = DescentCall.attach(root)
	for el in elements:
		var ok: bool = cut.open_stream(String(el))
		check(ok, "%s: the cut-scene's video slot opens (a table with the video slots must be given with --chapter1-asset-slots=)" % el)
		if not ok: continue
		band.close()
		# The first frame is held paused until the cut-scene starts.
		var waited := 0
		while not cut.first_frame_ready() and waited < 60:
			await process_frame
			waited += 1
		check(cut.first_frame_ready(), "%s: a first frame is on hand within 60 frames (waited %d)" % [el, waited])
		notes.append("cutscene %s: first frame after %d frames, aspect %.3f, length %.2f s, seek works: %s" % [el, waited, cut.video_aspect(), cut.video_seconds(), str(cut.can_seek())])
		cut.apply({"element": String(el), "open": 0.0})
		cut.start()
		var e := String(el)
		cut.apply({"open": 0.45, "plate": 0.0})
		await _grab(abs_dir, "cut-%s-open045" % e, size_px)
		for i in 20: await process_frame
		cut.apply({"open": 1.0, "plate": 1.0, "subtitle": 1.0, "skip_hint": 1.0, "subtitle_key": DescentCutscene.say_key(e, true)})
		await _grab(abs_dir, "cut-%s-run" % e, size_px)
		var pos_a: float = cut.video_position()
		for i in 15: await process_frame
		check(cut.video_position() > pos_a, "%s: the video keeps running (%.2f -> %.2f s)" % [e, pos_a, cut.video_position()])
		cut.apply({"open": 0.3, "plate": 0.0, "subtitle": 0.0, "skip_hint": 0.0})
		await _grab(abs_dir, "cut-%s-close030" % e, size_px)
		# The band over it with the video in the demon window (from the second descent on).
		band.open(e)
		band.set_demon_video(cut.frame_texture(), Rect2(Vector2.ZERO, cut.frame_size()) if cut.frame_size().x > 0.0 else Rect2())
		var v := timetable(.9)
		v["hero_top"] = hero_top
		v["clock"] = 2.0
		cut.apply({"open": 0.0})
		band.apply(v)
		await _grab(abs_dir, "cut-%s-bandvideo" % e, size_px)
		band.set_demon_video(null)
		band.close()
		cut.close()
	var key := DescentCall.call_key("ember", false)
	call.say("ember", key)
	check(Loc.t(key) != key, "the sorceress's call key exists: " + key)
	call.apply({"t": .5, "hero_top": hero_top})
	await _grab(abs_dir, "call-ember", size_px)
