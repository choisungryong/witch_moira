extends RefCounted
## More parts of the growth-choice proposals: the side frame (the only place with explanation text), the wax-seal cover,
## the link lines from the owned sockets to the focused card, the progress pips.
const Kit = preload("res://chapter1/tests/proposals/growth_choice/kit.gd")
const Palette = preload("res://chapter1/view/hud/palette.gd")

class SidePanel extends Control:
	var ui := {}
	var used := 0.0
	var _holder: Control
	func setup(w: float, h: float, strings: Dictionary) -> void:
		ui = strings
		size = Vector2(w, h)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		_holder = Control.new()
		_holder.size = size
		_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_holder)
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		Kit.quad(self, r, Color(0.1, 0.105, 0.115, 0.96), Color(0.045, 0.05, 0.056, 0.96))
		draw_rect(r, Color(0.5, 0.45, 0.34, 0.9), false, 2.0)
		draw_rect(r.grow(-5), Kit.with_alpha(Palette.BRASS_DIM, 0.9), false, 1.0)
		draw_line(Vector2(2, 2), Vector2(size.x - 2, 2), Color(1, 1, 1, 0.14), 1.0)
	func show_card(card: Dictionary, fade := true) -> void:
		for ch in _holder.get_children():
			_holder.remove_child(ch)
			ch.queue_free()
		var pad := 16.0
		var w := size.x - pad * 2.0
		var y := 14.0
		var el := String(card.element)
		var title: Label = Kit.lbl(_holder, String(card.name), Vector2(pad, y), w, 22, Palette.INK, "heading", HORIZONTAL_ALIGNMENT_LEFT, false)
		y += title.size.y + 2.0
		var head: Label = Kit.lbl(_holder, String(card.headline), Vector2(pad, y), w, 15, Palette.INK, "body")
		y += head.size.y + 8.0
		if card.get("resonance", null) is Dictionary:
			var rs: Label = Kit.lbl(_holder, String(card.resonance.text), Vector2(pad, y), w, 15, Kit.grade_color("fated"), "bold")
			y += rs.size.y + 8.0
		for line in card.details:
			var dl: Label = Kit.lbl(_holder, String(line), Vector2(pad, y), w, 14, Palette.INK_DIM, "body")
			y += dl.size.y + 2.0
		if card.combo.size() > 0:
			y += 8.0
			Kit.lbl(_holder, String(ui.combo), Vector2(pad, y), w, 14, Kit.el_text(el), "bold", HORIZONTAL_ALIGNMENT_LEFT, false)
			y += 22.0
			for cb in card.combo:
				var a := Kit.Emblem.new(String(cb["from"]), String(cb.from_element), Vector2(30, 30))
				a.position = Vector2(pad, y)
				_holder.add_child(a)
				Kit.lbl(_holder, "→", Vector2(pad + 34.0, y + 2.0), 24, 18, Palette.LINEN, "bold", HORIZONTAL_ALIGNMENT_CENTER, false)
				var b := Kit.Emblem.new(String(cb["to"]), String(cb.to_element), Vector2(30, 30))
				b.position = Vector2(pad + 62.0, y)
				_holder.add_child(b)
				y += 34.0
				var tl: Label = Kit.lbl(_holder, String(cb.text), Vector2(pad, y), w, 14, Palette.INK_DIM, "body")
				y += tl.size.y + 6.0
		if card.path is Dictionary:
			y += 6.0
			Kit.lbl(_holder, String(card.path.label), Vector2(pad, y), w, 14, Palette.GROWTH, "bold", HORIZONTAL_ALIGNMENT_LEFT, false)
			y += 22.0
			var pb := PathBar.new()
			pb.info = card.path
			pb.position = Vector2(pad, y)
			pb.size = Vector2(w, 22)
			_holder.add_child(pb)
			y += 28.0
			var keys: Array = []
			for k in card.path.keys: keys.append(String(k.label) + (" ✓" if bool(k.done) else (" " + String(k.get("value", "×")))))
			var kl: Label = Kit.lbl(_holder, " · ".join(keys), Vector2(pad, y), w, 14, Palette.INK_DIM, "body")
			y += kl.size.y + 4.0
		for t in card.terms.slice(0, 2):
			y += 6.0
			var tw: Label = Kit.lbl(_holder, "%s  %s" % [t.word, t.gloss], Vector2(pad, y), w, 14, Palette.INK_FAINT, "body")
			y += tw.size.y
		used = y + 12.0
		if fade:
			_holder.modulate.a = 0.0
			create_tween().tween_property(_holder, "modulate:a", 1.0, 0.12)

class PathBar extends Control:
	var info := {}
	func _draw() -> void:
		var n := int(info.get("total", 5))
		var f := int(info.get("filled", 0))
		var gap := (size.x - 20.0) / float(n - 1)
		for i in n - 1:
			var c := Vector2(10.0 + gap * i, 11.0)
			draw_line(c, c + Vector2(gap, 0), Kit.with_alpha(Palette.GROWTH, 0.9) if i < f - 1 else Kit.with_alpha(Palette.BRASS_DIM, 0.9), 3.0)
		for i in n:
			var c2 := Vector2(10.0 + gap * i, 11.0)
			Kit.diamond(self, c2, 8.0, Palette.GROWTH if i < f else Color(0.05, 0.05, 0.06), true)
			if i >= f: Kit.diamond(self, c2, 8.0, Kit.with_alpha(Palette.BRASS, 0.8), false, 1.5)

## A cover with a wax seal over a card. crack 0..1 splits it along a jagged seam and slides the halves away; leak lights the seam
## in the grade colour before it opens (a low light, not a flash).
class Seal extends Control:
	var element := "frost"
	var grade := "legendary"
	var crack := 0.0:
		set(v):
			crack = v
			queue_redraw()
	var leak := 0.0:
		set(v):
			leak = v
			queue_redraw()
	func _init(e := "frost", g := "legendary", s := Vector2(260, 520)) -> void:
		element = e
		grade = g
		size = s
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _seam() -> PackedVector2Array:
		var pts := PackedVector2Array()
		var n := 12
		for i in n + 1:
			var off := (float((i * 37) % 11) - 5.0) * 3.2 if i > 0 and i < n else 0.0
			pts.append(Vector2(size.x * 0.5 + off, size.y * float(i) / float(n)))
		return pts
	func _draw() -> void:
		var seam := _seam()
		var gc := Kit.grade_color(grade)
		var fade := 1.0 - clampf((crack - 0.55) / 0.45, 0.0, 1.0)
		if leak > 0.0 and crack < 0.05:
			for i in 8:
				draw_rect(Rect2(-float(i) * 2.0, -float(i) * 2.0, size.x + float(i) * 4.0, size.y + float(i) * 4.0), Kit.with_alpha(gc, 0.28 * leak * (1.0 - float(i) / 8.0)), false, 3.0)
		if fade <= 0.0: return
		for side in [-1, 1]:
			var shift := float(side) * crack * size.x * 0.62
			var poly := PackedVector2Array()
			if side < 0:
				poly.append(Vector2(0, 0) + Vector2(shift, 0))
				for p in seam: poly.append(p + Vector2(shift, 0))
				poly.append(Vector2(0, size.y) + Vector2(shift, 0))
			else:
				poly.append(Vector2(size.x, 0) + Vector2(shift, 0))
				for p in seam: poly.append(p + Vector2(shift, 0))
				poly.append(Vector2(size.x, size.y) + Vector2(shift, 0))
			draw_colored_polygon(poly, Color(0.1, 0.085, 0.07, fade))
			var rim := PackedVector2Array(poly)
			rim.append(poly[0])
			draw_polyline(rim, Color(0.5, 0.42, 0.3, fade), 2.0, true)
			var rng := RandomNumberGenerator.new()
			rng.seed = 11 + side
			for i in 40:
				var y := rng.randf() * size.y
				var x := size.x * (0.0 if side < 0 else 0.5) + rng.randf() * size.x * 0.5
				draw_line(Vector2(x, y) + Vector2(shift, 0), Vector2(x + rng.randf_range(-14, 14), y + rng.randf_range(10, 40)) + Vector2(shift, 0), Color(1, 1, 1, 0.04 * fade), 1.0)
			var c := Vector2(size.x * 0.5, size.y * 0.46) + Vector2(shift, 0)
			var wax := Kit.el_color(element).darkened(0.62)
			wax.a = fade
			var a0 := (-PI * 0.5) if side > 0 else (PI * 0.5)
			var half := PackedVector2Array()
			for i in 17: half.append(c + Vector2.from_angle(a0 + PI * float(i) / 16.0) * 40.0)
			draw_colored_polygon(half, wax)
			draw_arc(c, 40.0, a0, a0 + PI, 16, Color(0.9, 0.8, 0.6, 0.5 * fade), 2.0, true)
		if crack < 0.6:
			draw_polyline(seam, Kit.with_alpha(gc, (0.35 + 0.65 * leak) * fade), 3.0 + 2.0 * leak, true)
			draw_polyline(seam, Color(1, 1, 1, 0.5 * leak * fade), 1.0, true)

## Lines from the owned row's sockets to the focused card (T5: relations as places and lines).
class LinkLayer extends Control:
	var links: Array = []  ## [from: Vector2, to: Vector2]
	var amount := 0.0:
		set(v):
			amount = v
			queue_redraw()
	func _init() -> void:
		size = Vector2(1600, 900)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		for l in links:
			var a: Vector2 = l[0]
			var b: Vector2 = l[1]
			var mid := (a + b) * 0.5 + Vector2(0, -26)
			var pts := PackedVector2Array()
			for i in 21:
				var t := float(i) / 20.0 * amount
				pts.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
			if pts.size() > 1:
				draw_polyline(pts, Kit.with_alpha(Palette.BRASS_HI, 0.22 * amount), 7.0, true)
				draw_polyline(pts, Kit.with_alpha(Palette.LINEN, 0.95 * amount), 2.0, true)
			draw_circle(a, 4.0, Kit.with_alpha(Palette.BRASS_HI, amount))
			if amount > 0.95: draw_circle(b, 4.0, Kit.with_alpha(Palette.BRASS_HI, amount))

class Pips extends Control:
	var total := 11
	var index := 1
	func _init(t := 11, i := 1) -> void:
		total = t
		index = i
		size = Vector2(t * 16.0, 16)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		for k in total:
			var c := Vector2(8.0 + k * 16.0, 8.0)
			if k < index - 1: Kit.diamond(self, c, 5.0, Kit.with_alpha(Palette.BRASS, 0.9))
			elif k == index - 1: Kit.diamond(self, c, 7.0, Palette.BRASS_HI)
			else: Kit.diamond(self, c, 5.0, Palette.BRASS_DIM, false, 1.2)
