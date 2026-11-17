extends StyleBox
## A nine-slice frame cut from the HUD atlas, drawn at code size (kit pixels * UiStyle.CODE). Made by ui_style.gd only.
## `margins_px` are the cut distances in kit pixels (left, top, right, bottom). `line_color` repaints the baked top line of the
## notice card (its colour is the item's grade colour, set in code).
const UiStyle = preload("res://chapter1/view/hud/ui_style.gd")
var piece := ""
var margins_px := Vector4(40,40,40,40)
var tint := Color.WHITE
var line_color := Color(0,0,0,0)

func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var r: Array = UiStyle.ATLAS[piece]
	var texture := UiStyle.atlas().get_rid()
	var k := UiStyle.CODE
	var sw := float(r[2]); var sh := float(r[3])
	var l := margins_px.x; var t := margins_px.y; var rr := margins_px.z; var b := margins_px.w
	var left := minf(l*k,rect.size.x*.5); var right := minf(rr*k,rect.size.x*.5)
	var top := minf(t*k,rect.size.y*.5); var bottom := minf(b*k,rect.size.y*.5)
	var xs := [0.0,l,sw-rr,sw]
	var ys := [0.0,t,sh-b,sh]
	var xd := [0.0,left,rect.size.x-right,rect.size.x]
	var yd := [0.0,top,rect.size.y-bottom,rect.size.y]
	for j in 3:
		for i in 3:
			var dw: float = xd[i+1]-xd[i]
			var dh: float = yd[j+1]-yd[j]
			if dw <= 0.0 or dh <= 0.0: continue
			RenderingServer.canvas_item_add_texture_rect_region(to_canvas_item,Rect2(rect.position+Vector2(xd[i],yd[j]),Vector2(dw,dh)),texture,
				Rect2(float(r[0])+xs[i],float(r[1])+ys[j],xs[i+1]-xs[i],ys[j+1]-ys[j]),tint)
	if line_color.a > 0.0:
		RenderingServer.canvas_item_add_rect(to_canvas_item,Rect2(rect.position+Vector2(54.0*k,17.0*k),Vector2(rect.size.x-(54.0+52.0)*k,10.0*k)),line_color)
