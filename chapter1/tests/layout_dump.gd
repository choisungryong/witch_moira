extends RefCounted
## Control-tree dump shared by hud_dump.gd (--dump-extra) and scene_shot.gd, read by tools/dev/hud_layout_check.py.
## Every Control becomes a row {d, class, name, visible, x, y, w, h, modulate, tooltip, text?, ...} in tree order
## (d = depth, so a row's parent is the nearest earlier row with a smaller d). Coordinates are canvas units (the
## project's 1600x900 virtual screen), not window pixels. `extra` adds the layout fields:
##   alpha  effective opacity (own and ancestors' modulate/self_modulate)
##   clip   rect [x,y,w,h] that clips the row (clipping ancestors: ScrollContainer, clip_contents), absent when none
##   min    combined minimum size [w,h]
##   fs     font size   tw/th  text width / height as the font measures it   lines/vis_lines  text lines / lines drawn
##   ha/va  horizontal / vertical text alignment (Label, Button)   wrap   Label autowrap mode   pad  button horizontal padding   overrun  button overrun mode
##   fc     text colour as hex rrggbb[aa] (theme / label settings colour times the ancestors' modulate; the row's own opacity stays in "alpha")
##   bg     colour under the text as hex rrggbb, only when it can be known from the node tree (see "bg" below); bg_src "theme" | "pixels" | "unknown"
## "bg" (S0-b, read by tools/dev/screen_contract_check.py contrast): headless nothing is drawn, so the colour under a text is COMPUTED, not
## sampled. The nodes painted before the text (tree order) that cover the text's centre point are composited over the clear colour:
## ColorRect colour, StyleBoxFlat bg_color of Panel / PanelContainer / Button / Label / RichTextLabel (own opacity included). A picture
## (TextureRect, NinePatchRect, TextureButton, StyleBoxTexture) or a node with its own _draw() makes the colour unknown until a later opaque
## fill covers it; with no 3D camera in the tree the clear colour is the base, otherwise (the real game) the world behind the HUD is unknown
## too. Unknown = no "bg" field = the contrast check skips the row and counts it as skipped. Window runs can fill the gap from the picture:
## fill_bg_from_image(rows, image, canvas) (bg_src "pixels", the commonest colour in the text's extent that is not the text colour).
## Not seen: CanvasLayer and z_index order, shaders, glow, text outlines and shadows, a hovered or pressed button.
## What it cannot see: Label3D, shader-clipped pictures and anything a control draws itself in _draw (the skill tree).

static func extra(c: Control, row: Dictionary, alpha: float, clip: Rect2, has_clip: bool, tint := Color.WHITE) -> void:
	row.alpha = snappedf(alpha,.001)
	if has_clip: row.clip = [snappedf(clip.position.x,.01),snappedf(clip.position.y,.01),snappedf(clip.size.x,.01),snappedf(clip.size.y,.01)]
	var minimum := c.get_combined_minimum_size()
	row.min = [snappedf(minimum.x,.01),snappedf(minimum.y,.01)]
	if c is Label:
		var label: Label = c
		var font := label.get_theme_font("font")
		var size := label.get_theme_font_size("font_size")
		row.fs = size
		row.wrap = int(label.autowrap_mode)
		row.ha = int(label.horizontal_alignment)
		row.va = int(label.vertical_alignment)
		row.lines = label.get_line_count()
		row.vis_lines = label.get_visible_line_count()
		row.th = snappedf(label.get_line_count()*label.get_line_height()+maxi(0,label.get_line_count()-1)*label.get_theme_constant("line_spacing"),.01)
		row.fc = _hex(text_color(label,tint))
		var widest := 0.0
		for line in label.text.split("
"):
			widest = maxf(widest,font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x)
		row.tw = snappedf(widest,.01)
	elif c is Button:
		var button: Button = c
		var font := button.get_theme_font("font")
		var size := button.get_theme_font_size("font_size")
		row.fs = size
		var widest := 0.0
		for line in button.text.split("
"):
			widest = maxf(widest,font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x)
		row.tw = snappedf(widest,.01)
		var box := button.get_theme_stylebox("normal")
		row.pad = snappedf(box.get_minimum_size().x if box != null else 0.0,.01)
		if button.icon != null: row.pad = snappedf(float(row.pad)+button.icon.get_width(),.01)
		row.overrun = int(button.text_overrun_behavior)
		row.ha = int(button.alignment)
		row.fc = _hex(text_color(button,tint))
	elif c is RichTextLabel:
		var rich: RichTextLabel = c
		row.fs = rich.get_theme_font_size("normal_font_size")
		row.th = snappedf(rich.get_content_height(),.01)
		row.tw = snappedf(rich.get_content_width(),.01)
		row.fc = _hex(text_color(rich,tint))

## The base row without the extra fields (identical to hud_dump.gd's own rows), with the recursion that carries alpha and clip.
static func describe(node: Node, depth: int, rows: Array, with_extra := true, alpha := 1.0, clip := Rect2(), has_clip := false, tint := Color.WHITE, paints = null) -> void:
	# The top call of an extra dump keeps the paint list of the whole tree and fills "bg" once the rows are all there.
	var top := with_extra and paints == null
	if top: paints = []
	var child_alpha := alpha
	var child_clip := clip
	var child_has_clip := has_clip
	var child_tint := tint
	if node is CanvasItem:
		child_alpha = alpha*node.modulate.a*node.self_modulate.a
		var own: Color = node.modulate*node.self_modulate
		child_tint = Color(tint.r*own.r,tint.g*own.g,tint.b*own.b,1.0)
	if node is Control:
		var c: Control = node
		var row := {"d":depth,"class":c.get_class(),"name":String(c.name),"visible":c.is_visible_in_tree(),
			"x":snappedf(c.global_position.x,.01),"y":snappedf(c.global_position.y,.01),"w":snappedf(c.size.x,.01),"h":snappedf(c.size.y,.01),
			"modulate":c.modulate.to_html(),"tooltip":c.tooltip_text}
		if c is Label or c is Button or c is RichTextLabel or c is LineEdit: row.text = String(c.get("text"))
		if c is BaseButton: row.disabled = c.disabled
		if c is Range: row.value = snappedf(c.value,.001); row.max = snappedf(c.max_value,.001)
		if c is TextureRect: row.texture = c.texture.resource_path if c.texture != null else ""
		if with_extra: extra(c,row,child_alpha,clip,has_clip,child_tint)
		rows.append(row)
		if paints != null:
			var paint := paint_of(c,child_alpha)
			if not paint.is_empty():
				paint["i"] = rows.size()-1
				paints.append(paint)
		if c.clip_contents or c is ScrollContainer:
			var own := Rect2(c.global_position,c.size)
			child_clip = clip.intersection(own) if has_clip else own
			child_has_clip = true
	for child in node.get_children():
		describe(child,depth+1,rows,with_extra,child_alpha,child_clip,child_has_clip,child_tint,paints)
	if top: fill_bg(rows,paints,node.get_viewport() != null and node.get_viewport().get_camera_3d() == null)

# ---- colour under the text (S0-b) ----

static func _hex(color: Color) -> String:
	return color.to_html(color.a < 0.999)

## The text colour a control draws with in its normal state, times the ancestors' modulate (RGB only; opacity is the row's "alpha").
static func text_color(c: Control, tint: Color) -> Color:
	var base := Color.WHITE
	if c is Label:
		var settings: LabelSettings = c.label_settings
		base = settings.font_color if settings != null else c.get_theme_color("font_color")
	elif c is Button: base = c.get_theme_color("font_disabled_color" if c.disabled else "font_color")
	elif c is RichTextLabel: base = c.get_theme_color("default_color")
	elif c is LineEdit: base = c.get_theme_color("font_color")
	return Color(base.r*tint.r,base.g*tint.g,base.b*tint.b,base.a)

static func _draws_itself(c: Control) -> bool:
	var script: Script = c.get_script()
	while script != null:
		if script.has_method("_draw"): return true
		script = script.get_base_script()
	return false

## What a control paints under its own children, as {r: Rect2, a: opacity, kind: "fill" | "picture", color} or {} when nothing known.
## "picture" also stands for a node with its own _draw(): its pixels are not in the tree.
static func paint_of(c: Control, alpha: float) -> Dictionary:
	if not c.is_visible_in_tree(): return {}
	var out := {"r": Rect2(c.global_position,c.size), "a": alpha}
	if _draws_itself(c):
		out.kind = "picture"
		return out
	if c is ColorRect:
		out.kind = "fill"
		out.color = c.color
		return out
	if c is TextureRect or c is NinePatchRect or c is TextureButton:
		if c.texture != null or (c is TextureButton and c.texture_normal != null):
			out.kind = "picture"
			return out
		return {}
	var box: StyleBox = null
	if c is Panel or c is PanelContainer: box = c.get_theme_stylebox("panel")
	elif c is BaseButton: box = c.get_theme_stylebox("disabled" if c.disabled else "normal")
	elif c is Label or c is RichTextLabel or c is LineEdit: box = c.get_theme_stylebox("normal")
	if box is StyleBoxFlat:
		if not box.draw_center: return {}
		out.kind = "fill"
		out.color = box.bg_color
		return out
	if box is StyleBoxTexture:
		out.kind = "picture"
		return out
	return {}

## Where the text of a row sits (its centre point in canvas units), from the row's own numbers.
static func text_point(row: Dictionary) -> Vector2:
	var x := float(row.x)
	var y := float(row.y)
	var w := float(row.w)
	var h := float(row.h)
	var tw := minf(float(row.get("tw",w)),w)
	var th := minf(float(row.get("th",h)),h)
	var cx := x+w*0.5
	match int(row.get("ha",1)):
		0: cx = x+tw*0.5
		2: cx = x+w-tw*0.5
	var cy := y+h*0.5
	if row["class"] == "Label" or row["class"] == "RichTextLabel":
		var va := int(row.get("va",0)) if row["class"] == "Label" else 0
		if va == 0: cy = y+th*0.5
		elif va == 2: cy = y+h-th*0.5
	return Vector2(cx,cy)

## Sets row.bg / row.bg_src for every visible row with text and a text colour. `base_known`: the clear colour is what is behind the
## tree (false when a 3D world is behind the HUD).
static func fill_bg(rows: Array, paints: Array, base_known: bool) -> void:
	var clear: Color = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color",Color(0.3,0.3,0.3))
	for index in rows.size():
		var row: Dictionary = rows[index]
		if not row.has("fc") or not row.visible or String(row.get("text","")).strip_edges().is_empty(): continue
		var point := text_point(row)
		var known := base_known
		var under := Color(clear.r,clear.g,clear.b,1.0)
		for paint in paints:
			if int(paint.i) > index: break
			if not Rect2(paint.r).has_point(point): continue
			if paint.kind == "picture":
				known = false
				continue
			var color: Color = paint.color
			var opacity := clampf(color.a*float(paint.a),0.0,1.0)
			if known:
				under = Color(under.r*(1.0-opacity)+color.r*opacity,under.g*(1.0-opacity)+color.g*opacity,under.b*(1.0-opacity)+color.b*opacity,1.0)
			elif opacity >= 0.995:
				known = true
				under = Color(color.r,color.g,color.b,1.0)
		if known:
			row.bg = under.to_html(false)
			row.bg_src = "theme"
		else:
			row.bg_src = "unknown"

## Window runs: fills the rows whose colour is unknown from a captured image. `canvas` = the canvas size the rows are in; the image may
## be larger (window pixels). Rows already known are left alone. Returns how many rows it filled.
static func fill_bg_from_image(rows: Array, image: Image, canvas: Vector2) -> int:
	if image == null or canvas.x <= 0.0 or canvas.y <= 0.0: return 0
	var scale := Vector2(image.get_width()/canvas.x,image.get_height()/canvas.y)
	var filled := 0
	for row in rows:
		if String(row.get("bg_src","")) != "unknown" or not row.has("fc"): continue
		var point := text_point(row)
		var half_w := minf(float(row.get("tw",row.w)),float(row.w))*0.5
		var half_h := minf(float(row.get("th",row.h)),float(row.h))*0.5
		var rect := Rect2((point.x-half_w)*scale.x,(point.y-half_h)*scale.y,half_w*2.0*scale.x,half_h*2.0*scale.y)
		var picked := sample_bg(image,rect,Color.html(String(row.fc)))
		if picked.a < 0.0: continue
		row.bg = picked.to_html(false)
		row.bg_src = "pixels"
		filled += 1
	return filled

## Commonest quantised colour in `rect` (image pixels), skipping colours near `fc`; all pixels when nothing else is left. Alpha -1 = no pixels.
static func sample_bg(image: Image, rect: Rect2, fc: Color) -> Color:
	var box := Rect2i(int(rect.position.x),int(rect.position.y),maxi(1,int(rect.size.x)),maxi(1,int(rect.size.y))).intersection(Rect2i(0,0,image.get_width(),image.get_height()))
	if box.size.x <= 0 or box.size.y <= 0: return Color(0,0,0,-1)
	var counts := {}
	var counts_all := {}
	var step_x := maxi(1,box.size.x/24)
	var step_y := maxi(1,box.size.y/12)
	for y in range(box.position.y,box.end.y,step_y):
		for x in range(box.position.x,box.end.x,step_x):
			var pixel := image.get_pixel(x,y)
			var key := Vector3i(int(pixel.r*255.0)>>4,int(pixel.g*255.0)>>4,int(pixel.b*255.0)>>4)
			counts_all[key] = int(counts_all.get(key,0))+1
			var near := absf(pixel.r-fc.r)+absf(pixel.g-fc.g)+absf(pixel.b-fc.b) < 0.15
			if not near: counts[key] = int(counts.get(key,0))+1
	var pool := counts if not counts.is_empty() else counts_all
	var best := Vector3i.ZERO
	var best_n := -1
	for key in pool:
		if int(pool[key]) > best_n:
			best_n = int(pool[key])
			best = key
	return Color((best.x*16+8)/255.0,(best.y*16+8)/255.0,(best.z*16+8)/255.0,1.0)
