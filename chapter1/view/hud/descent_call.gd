extends Control
## The sorceress's call (DESCENT-TEXT 0, DS6): the moment the descent is pressed, a short line stands over the hero's head. The band does not carry her, so
## this is where she speaks. This part DRAWS one line; the presenter (vfx-feel B) says when and which. Presentation only.
##   var call := DescentCall.attach(host)
##   call.say("ember", DescentCall.call_key("ember", false, index))   # then
##   call.apply({"t": 0..1 (the line's life), "hero_top": Vector2 (the hood's top, code units)})
## Life: in over the first 15 percent (rises 14 units), stays, out over the last 25 percent. The line is a Label-free draw (no node per line).
const Palette = preload("res://chapter1/view/hud/palette.gd")
const Loc = preload("res://chapter1/view/loc.gd")
const DescentBand = preload("res://chapter1/view/hud/descent_band.gd")
const TEXT_SIZE := 26            ## A10 T3
const ABOVE := 46.0              ## from the hood's top to the baseline

var element := "ember"
var text := ""
var t := 0.0
var hero_top := Vector2(800,342)

## The po key of the sorceress's line: Tessa and Eileen say one line (a deeper one from character level 12); Veronica rotates three (`index`) and has a deeper one too.
static func call_key(el: String, deep: bool, index: int = 0) -> String:
	if el == "arc": return "descent.call.arc.deep" if deep else "descent.call.arc.%d" % (1+posmod(index,3))
	return "descent.call.%s.deep" % el if deep else "descent.call.%s" % el

static func attach(host: Node) -> Control:
	var layer := CanvasLayer.new()
	layer.name = "DescentCall"
	layer.layer = 1
	host.add_child(layer)
	var call: Control = load("res://chapter1/view/hud/descent_call.gd").new()
	layer.add_child(call)
	return call

func _init() -> void:
	name = "Call"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

func say(el: String, key: String) -> void:
	element = el
	text = Loc.t(key)
	if text == key: text = ""
	t = 0.0
	queue_redraw()

func apply(values: Dictionary) -> void:
	if values.has("t"): t = clampf(float(values.t),0,1)
	if values.has("hero_top"): hero_top = values.hero_top
	visible = text != "" and t > 0.0 and t < 1.0
	queue_redraw()

func _draw() -> void:
	if text == "": return
	var a := minf(clampf(t/.15,0,1),clampf((1.0-t)/.25,0,1))
	var rise := (1.0-clampf(t/.15,0,1))*14.0
	var font := Loc.font("heading")
	var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,TEXT_SIZE).x
	var at := Vector2(hero_top.x-width*.5,hero_top.y-ABOVE+rise)
	DescentBand.iron_plate(self,Rect2(at.x-18.0,at.y-TEXT_SIZE-4.0,width+36.0,TEXT_SIZE+18.0),a)
	draw_string_outline(font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,TEXT_SIZE,5,Color(0,0,0,.9*a))
	draw_string(font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,TEXT_SIZE,Color(Palette.INK,a))
