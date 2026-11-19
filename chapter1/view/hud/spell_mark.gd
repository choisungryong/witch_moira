extends Control
## Small spell mark for text lines (A6-RS RS3): one shape per element (flame / snowflake / bolt), a dashed rim for a ring spell,
## a solid rim for a basic one. Colour is never the only cue: the shape and the rim differ.
## A slot of the asset table (icon.spell.<short>) takes over the day it has a file; until then (planned) this draws the placeholder.
## Reads nothing of the run: the caller passes the element and the role.
const Palette=preload("res://chapter1/view/hud/palette.gd")
const AssetSlots=preload("res://chapter1/view/assets/asset_slots.gd")
const SLOT_PREFIX := "icon.spell."
var element := "ember"
var ring := false
var slot_id := ""

static func slot_for(skill_id: String) -> String:
	return SLOT_PREFIX+skill_id.trim_prefix("chapter1.skill.")

## Dashed circle used by the mark and by the big crest of a ring card.
static func draw_dashes(canvas: CanvasItem,center: Vector2,radius: float,color: Color,width: float,count: int=12) -> void:
	var step := TAU/count
	for i in count:
		canvas.draw_arc(center,radius,i*step,i*step+step*.58,6,color,width,true)

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	if custom_minimum_size==Vector2.ZERO:custom_minimum_size=Vector2(26,26)

func _draw() -> void:
	var tint := Palette.element_text_color(element)
	if slot_id!="" and AssetSlots.has_slot(slot_id) and not AssetSlots.is_planned(slot_id):
		var texture := AssetSlots.texture(slot_id)
		if texture!=null:
			draw_texture_rect(texture,Rect2(Vector2.ZERO,size),false)
			return
	var k := minf(size.x,size.y)/60.0
	draw_set_transform(size/2,0,Vector2(k,k))
	var c := Vector2.ZERO
	draw_circle(c,28,Palette.SURFACE)
	if ring:draw_dashes(self,c,27,tint,4.0)
	else:draw_arc(c,27,0,TAU,48,tint,3.0,true)
	match element:
		"frost":
			for i in 6:
				var v := Vector2.from_angle(i*TAU/6.)
				draw_line(c-v*3,c+v*17,tint,3.2,true)
				for sign_ in [-1,1]:draw_line(c+v*10,c+v.rotated(sign_*.5)*15,tint,2.4,true)
		"arc":
			draw_polyline(PackedVector2Array([c+Vector2(8,-18),c+Vector2(-9,1),c+Vector2(3,1),c+Vector2(-8,19)]),tint,4.6,true)
		_:
			draw_colored_polygon(PackedVector2Array([c+Vector2(-11,11),c+Vector2(-14,0),c+Vector2(-3,-8),c+Vector2(2,-19),c+Vector2(13,-1),c+Vector2(10,13),c+Vector2(0,18)]),tint)
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE)
