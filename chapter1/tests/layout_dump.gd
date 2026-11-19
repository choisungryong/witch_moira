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
## What it cannot see: Label3D, shader-clipped pictures and anything a control draws itself in _draw (the skill tree).

static func extra(c: Control, row: Dictionary, alpha: float, clip: Rect2, has_clip: bool) -> void:
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
	elif c is RichTextLabel:
		var rich: RichTextLabel = c
		row.fs = rich.get_theme_font_size("normal_font_size")
		row.th = snappedf(rich.get_content_height(),.01)
		row.tw = snappedf(rich.get_content_width(),.01)

## The base row without the extra fields (identical to hud_dump.gd's own rows), with the recursion that carries alpha and clip.
static func describe(node: Node, depth: int, rows: Array, with_extra := true, alpha := 1.0, clip := Rect2(), has_clip := false) -> void:
	var child_alpha := alpha
	var child_clip := clip
	var child_has_clip := has_clip
	if node is CanvasItem:
		child_alpha = alpha*node.modulate.a*node.self_modulate.a
	if node is Control:
		var c: Control = node
		var row := {"d":depth,"class":c.get_class(),"name":String(c.name),"visible":c.is_visible_in_tree(),
			"x":snappedf(c.global_position.x,.01),"y":snappedf(c.global_position.y,.01),"w":snappedf(c.size.x,.01),"h":snappedf(c.size.y,.01),
			"modulate":c.modulate.to_html(),"tooltip":c.tooltip_text}
		if c is Label or c is Button or c is RichTextLabel or c is LineEdit: row.text = String(c.get("text"))
		if c is BaseButton: row.disabled = c.disabled
		if c is Range: row.value = snappedf(c.value,.001); row.max = snappedf(c.max_value,.001)
		if c is TextureRect: row.texture = c.texture.resource_path if c.texture != null else ""
		if with_extra: extra(c,row,child_alpha,clip,has_clip)
		rows.append(row)
		if c.clip_contents or c is ScrollContainer:
			var own := Rect2(c.global_position,c.size)
			child_clip = clip.intersection(own) if has_clip else own
			child_has_clip = true
	for child in node.get_children():
		describe(child,depth+1,rows,with_extra,child_alpha,child_clip,child_has_clip)
