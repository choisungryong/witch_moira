extends Control
## The descent's band (A11, U-98): one slanted leather strip across the upper field with the sorceress in front, the demon behind and
## larger, the skill's name in big letters and one small line under it. This part DRAWS one band from the values it is given; it keeps
## no timetable. The cut-in's presenter (view/fx/descent_fx.gd, a later step) pushes the values on its own schedule:
## in the paused seconds on the wall clock, after the release on the sweep's step (A11 4.2). Presentation only: no core state is read.
##
## U-99: the descent is the DEMON's own art. The demon is the band's owner (biggest, first in, may overflow when transparent); the sorceress is an optional small guest
## that is drawn only when apply() gives witch > 0 (the default timetable leaves her at 0).
## Use:
##   var band := DescentBand.new(); layer.add_child(band)       # the layer: CanvasLayer 0, added AFTER the screen layer, see attach()
##   band.open("ember")                                         # picks the pictures and the words once
##   band.apply({"band_in": e, "witch": e, "demon": e, "name": e, "line": e, "bonus": 0.12, "hero_top": Vector2(x, y)})
##   band.close()
## Values (all 0..1 unless said): band_in, band_out, witch, demon, name, line, trim_flash, bonus (0..0.3, the hold bonus: the
## brass edge brightens in proportion), hero_top (the hood's top on screen, code units 1600x900), clock (seconds, drives the pattern;
## the part counts it itself unless "clock" is pushed), reduced_motion (bool: no slide, no scale, alpha only), slide_out (bool, false for lightning).
## Pictures (A11 4.6, by slot id only): sorceress portrait.<element>.cutin_ultimate (none: the demon alone); demon illustration.cutin.descent.<element>
## then ui.grace.demon.<element>; body ui.descent.band.<element> then descent_band.gdshader. A slot with contract.alpha true may overflow the
## band's top; one without is cut inside the band. contract.crops.focus [x, y, w, h] (source pixels) is the window of the picture shown.
const Palette = preload("res://chapter1/view/hud/palette.gd")
const Loc = preload("res://chapter1/view/loc.gd")
const AssetSlots = preload("res://chapter1/view/assets/asset_slots.gd")
const BODY_SHADER = preload("res://chapter1/view/hud/descent_band.gdshader")
const FIGURE_SHADER = preload("res://chapter1/view/hud/descent_band_figure.gdshader")
const NAME_SHADER = preload("res://chapter1/view/hud/descent_band_name.gdshader")

## Code units (1600 x 900). 1080p pixels are x1.2, 720p pixels x0.8.
const TILT := 0.13962634          ## 8 degrees; the right end is the higher one
const BAND_H := 216.0             ## 0.24 H
const BAND_H_MIN := 180.0         ## the lowest the band may be squeezed to keep the gap above the hero
const BAND_CENTER_Y := 180.0      ## the centre line's y at x 800
const BAND_LENGTH := 2100.0       ## longer than the screen's diagonal reach so both ends stay off screen
const HERO_GAP := 40.0            ## hero's hood top to the band's lower edge, at least
const HERO_SPAN := 80.0           ## the gap is measured over hero x +- this
const MAX_RAISE := 40.0           ## the band may rise this much before it is squeezed
const LOW_LIMIT := 405.0          ## 0.45 H: the band never goes below this (the combat bar starts at 0.83 H)
const DEFAULT_HERO_TOP := Vector2(800.0, 342.0)
## hero_uv() is the body's middle; the hood's top is about this much of H above it. [hypothesis from the s100 capture: hood 0.38 H, feet 0.49 H]
const HERO_TOP_ABOVE_UV := 0.055
const NAME_SIZE := 84             ## D1 (A11 12.2: 84, was 72), at the heaviest weight (loc role heading_black)
const NAME_SIZE_MIN := 56
const NAME_MAX_W := 720.0
const NAME_CENTER_X := 860.0      ## screen x (was 780: the demon grew toward the middle)
const NAME_SPACING := 5.0         ## letter spacing in the font's units: an engraved inscription is a little open (U-101: no brush, medieval dark fantasy)
const NAME_Y := -20.0             ## the name's middle, from the band's centre line (band-local y)
const LINE_SIZE := 20             ## T4
const LINE_DY := 56.0             ## below the name's middle
const WITCH_LEFT := 1330.0        ## screen x of the small sorceress's left edge (U-99: the demon owns the band; she is an optional guest, drawn only when "witch" > 0)
const WITCH_HEIGHT := 0.8         ## her height against the band when her picture has its scene painted in (cut inside the band)
const WITCH_HEIGHT_ALPHA := 1.1   ## the same for a transparent picture (it may overflow the top)
const DEMON_HEIGHT := 2.2         ## the demon's picture height against the band: the biggest thing on it; a painted-ground picture is cut at the band's edges, a transparent one may overflow the top (U-99)
const DEMON_LEFT := 20.0          ## screen x of the demon picture's left edge
const DEMON_OVERFLOW := 0.6        ## a keyed picture may stand this many band heights above the band (A11 12.2; 0.8 for a dedicated picture)
const HEAD_MIN_Y := 12.0          ## and its head stays this far below the screen's top edge
const EDGE_FADE := 48.0           ## a picture with its ground painted in melts into the leather over this many units (left edge)
const EDGE_FADE_RIGHT := 80.0     ## the right edge borders the name, and the painted grounds are lighter there: a longer melt
const PARALLAX := 1.3             ## the sorceress comes in 1.3 times as far as the band
## Per element trims so the three bands sit at the same level (A11 12.2 target: area brightness 0.20..0.30, saturation >= 0.45). Tuned on captures.
const BODY_GAIN := {"ember":0.93,"frost":0.82,"arc":0.95}
const BODY_SAT := {"ember":1.0,"frost":1.7,"arc":2.4}
const ELEMENT_IDS := {"ember": 0.0, "frost": 1.0, "arc": 2.0}

var element := "ember"
var band_in := 0.0
var band_out := 0.0
var witch := 0.0
var demon := 0.0
var name_t := 0.0
var line := 0.0
var trim_flash := 0.0
var sweep := -1.0               ## the light sweep across the band when the name stands: 0..1 while it runs, -1 off
var bonus := 0.0
var hero_top := DEFAULT_HERO_TOP
var clock := 0.0
var reduced_motion := false
var slide_out := true
var auto_clock := true

var _opened := false
var _lay: Dictionary = {}
var _k := 1.0
var _body: Control
var _demon_node: Control
var _witch_node: Control
var _trim: Control
var _text: Control
var _name_node: Control      ## the metal fill, with the gradient and the inset shading shader
var _name_back: Control      ## everything behind the fill: plate, ornaments, light, dark edge, the highlight
var _name_font: FontVariation
var _name_material: ShaderMaterial
var _body_material: ShaderMaterial
var _demon_material: ShaderMaterial
var _witch_tex: Texture2D
var _witch_focus := Rect2()
var _witch_alpha := false
var _demon_tex: Texture2D
var _demon_focus := Rect2()
var _demon_alpha := false
var _body_tex: Texture2D
var _key: Array = []

## A canvas layer for the band: layer 0 (above the 3D world and the screen layer of descent_fx.gd, below the HUD's layer 1). Layers with the same
## number draw in tree order, so add this AFTER the screen layer. Returns the band; its parent is the new layer, which is a child of `host`.
static func attach(host: Node) -> Control:
	var layer := CanvasLayer.new()
	layer.name = "DescentBand"
	layer.layer = 0
	host.add_child(layer)
	var band: Control = load("res://chapter1/view/hud/descent_band.gd").new()
	layer.add_child(band)
	return band

func _init() -> void:
	name = "Band"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_body = _node("Body", 0)
	_demon_node = _node("Demon", 4)   # above the brass: a keyed picture overflows the band's top edge
	_witch_node = _node("Witch", 4)
	_trim = _node("Trim", 3)
	_text = _node("Text", 5)
	_name_back = _node("NameBack", 5)
	_name_node = _node("Name", 6)
	_body_material = ShaderMaterial.new(); _body_material.shader = BODY_SHADER
	_demon_material = ShaderMaterial.new(); _demon_material.shader = FIGURE_SHADER
	_demon_node.material = _demon_material
	_name_material = ShaderMaterial.new(); _name_material.shader = NAME_SHADER
	_name_node.material = _name_material
	_body.draw.connect(_draw_body)
	_demon_node.draw.connect(_draw_demon)
	_witch_node.draw.connect(_draw_witch)
	_trim.draw.connect(_draw_trim)
	_text.draw.connect(_draw_text)
	_name_back.draw.connect(_draw_name_back)
	_name_node.draw.connect(_draw_name)

func _node(label: String, z: int) -> Control:
	var node := Control.new()
	node.name = label
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.size = Vector2.ZERO
	node.z_index = z
	add_child(node)
	return node

func _process(delta: float) -> void:
	if visible and auto_clock:
		clock += delta
		_push_clock()

# ---- geometry (static, so a check can ask without a node) ----

## Where the band stands for a hero whose hood top is at `hero_top`: {centre, height, angle, raised, squeezed, gap, low_y}. The band keeps the
## gap above the hero (hero x +- HERO_SPAN, measured at the lower edge), first by rising up to MAX_RAISE, then by getting lower in height down to BAND_H_MIN.
static func layout(hero: Vector2 = DEFAULT_HERO_TOP, canvas: Vector2 = Vector2(1600.0, 900.0)) -> Dictionary:
	var k := canvas.y/900.0
	var slope := tan(TILT)
	var cos_t := cos(TILT)
	var cx := canvas.x*.5
	var h := BAND_H*k
	var cy := BAND_CENTER_Y*k
	var left_x := hero.x-HERO_SPAN*k
	var bottom := cy-slope*(left_x-cx)+h*.5/cos_t
	var gap := hero.y-bottom
	var raised := 0.0
	var squeezed := false
	if gap < HERO_GAP*k:
		var need := HERO_GAP*k-gap
		raised = minf(need,MAX_RAISE*k)
		cy -= raised
		need -= raised
		if need > 0.0:
			h = maxf(BAND_H_MIN*k,h-2.0*cos_t*need)
			squeezed = true
		bottom = cy-slope*(left_x-cx)+h*.5/cos_t
		gap = hero.y-bottom
	var low_y := cy+slope*cx+h*.5/cos_t
	return {"centre":Vector2(cx,cy),"height":h,"angle":-TILT,"raised":raised,"squeezed":squeezed,"gap":gap,"low_y":low_y,"k":k}

## The hood's top on screen (code units) from descent_fx.hero_uv() (0..1 of the screen).
static func hero_top_from_uv(uv: Vector2, canvas: Vector2 = Vector2(1600.0, 900.0)) -> Vector2:
	return Vector2(uv.x*canvas.x,(uv.y-HERO_TOP_ABOVE_UV)*canvas.y)

## The name's face: the heaviest weight of the heading font, the letters a little apart (no new font file).
static var _spaced: FontVariation = null
static func name_font() -> Font:
	if _spaced == null:
		_spaced = (Loc.font("heading_black") as FontVariation).duplicate()   # keeps the weight 900 and the fallback chain
		_spaced.spacing_glyph = int(NAME_SPACING)
	return _spaced

## The name's size and width: 72, down by 2 to 52 until it fits NAME_MAX_W.
static func fit_name(title: String) -> Dictionary:
	var font := name_font()
	var size_ := NAME_SIZE
	var width := font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,size_).x
	while size_ > NAME_SIZE_MIN and width > NAME_MAX_W:
		size_ -= 2
		width = font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,size_).x
	return {"size":size_,"width":width}

## The two texts of the band for an element: {name, line}. U-102: nobody speaks on the descent's screen; the skill's name and one small line are all the words.
static func texts(el: String) -> Dictionary:
	return {"name":Loc.t("descent.name."+el),
		"line":Loc.t("descent.band.line",{"demon":Loc.t("demon."+el+".name"),"witch":Loc.t("character."+el+".name")})}

static func _slot_ready(id: String) -> bool:
	return AssetSlots.has_slot(id) and not AssetSlots.is_planned(id) and AssetSlots.available(id)

static func _focus_of(id: String, tex: Texture2D) -> Rect2:
	var crops: Variant = AssetSlots.contract(id).get("crops",{})
	if crops is Dictionary and crops.has("focus"):
		var r: Array = crops.focus
		return Rect2(float(r[0]),float(r[1]),float(r[2]),float(r[3]))
	return Rect2(Vector2.ZERO,tex.get_size())

# ---- open, apply, close ----

## The band body's material for an element (the cut-scene's unfolding band uses the same one, so the two read as one thing).
static func body_material(el: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = BODY_SHADER
	var base := Palette.element_color(el)
	material.set_shader_parameter("tint",base)
	material.set_shader_parameter("core",base.lerp(Palette.INK,.35))
	material.set_shader_parameter("glow",base.darkened(.45))
	material.set_shader_parameter("gain",float(BODY_GAIN.get(el,1.0)))
	material.set_shader_parameter("sat",float(BODY_SAT.get(el,1.0)))
	material.set_shader_parameter("element_id",float(ELEMENT_IDS.get(el,0.0)))
	return material

## Chooses the pictures and the colours for `el` (ember, frost, arc). Call once before the cut-in; the values come with apply().
func open(el: String) -> void:
	element = el
	_witch_tex = null; _demon_tex = null; _body_tex = null
	var slot := "portrait.%s.cutin_ultimate" % el
	if _slot_ready(slot):
		_witch_tex = AssetSlots.texture(slot)
		_witch_focus = _focus_of(slot,_witch_tex)
		_witch_alpha = bool(AssetSlots.contract(slot).get("alpha",false))
		_witch_node.z_index = 4 if _witch_alpha else 2   # a transparent picture may overflow the brass edge: it stands over it
	for candidate in ["illustration.cutin.descent.%s" % el,"ui.grace.demon.%s" % el]:
		if _slot_ready(candidate):
			_demon_tex = AssetSlots.texture(candidate)
			_demon_focus = _focus_of(candidate,_demon_tex)
			_demon_alpha = bool(AssetSlots.contract(candidate).get("alpha",false))
			break
	slot = "ui.descent.band.%s" % el
	if _slot_ready(slot): _body_tex = AssetSlots.texture(slot)
	var base := Palette.element_color(el)
	_body_material = body_material(el)
	_name_material.set_shader_parameter("top",Palette.BRASS_HI.lerp(Palette.INK,.8))
	_name_material.set_shader_parameter("bottom",Palette.BRASS.lerp(Palette.BRASS_HI,.75))
	_demon_material.set_shader_parameter("key_hi",0.0 if _demon_alpha else 0.14)
	_opened = true
	_key = []
	_refresh()

func close() -> void:
	band_in = 0.0; band_out = 0.0; witch = 0.0; demon = 0.0; name_t = 0.0; line = 0.0; trim_flash = 0.0; bonus = 0.0
	_opened = false
	visible = false

## Sets the values that are present in `values` (see the head) and redraws what changed.
func apply(values: Dictionary) -> void:
	for key in values:
		match String(key):
			"band_in": band_in = clampf(float(values[key]),0,1)
			"band_out": band_out = clampf(float(values[key]),0,1)
			"witch": witch = clampf(float(values[key]),0,1)
			"demon": demon = clampf(float(values[key]),0,1)
			"name": name_t = clampf(float(values[key]),0,1)
			"line": line = clampf(float(values[key]),0,1)
			"trim_flash": trim_flash = clampf(float(values[key]),0,1)
			"sweep": sweep = float(values[key])
			"bonus": bonus = clampf(float(values[key]),0,.3)
			"hero_top": hero_top = values[key]
			"clock": clock = float(values[key]); auto_clock = false
			"reduced_motion": reduced_motion = bool(values[key])
			"slide_out": slide_out = bool(values[key])
	_refresh()

func is_up() -> bool:
	return _opened and visible

static func _ease_out(t: float) -> float:
	return 1.0-pow(1.0-clampf(t,0,1),3.0)

static func _ease_in(t: float) -> float:
	return pow(clampf(t,0,1),2.0)

func _push_clock() -> void:
	if _body_material != null: _body_material.set_shader_parameter("clock",clock)

func _lx(screen_x: float) -> float:
	return (screen_x*_k-_lay.centre.x)/cos(TILT)

func _refresh() -> void:
	if _body == null: return
	var up := _opened and band_in > 0.0 and band_out < 1.0
	visible = up
	if not up: return
	var key: Array = [element,band_in,band_out,witch,demon,name_t,line,trim_flash,sweep,bonus,hero_top,reduced_motion,slide_out,size,clock if not auto_clock else 0.0]
	_push_clock()
	if key == _key: return
	_key = key
	_lay = layout(hero_top,size if size.x > 0.0 else Vector2(1600.0,900.0))
	_k = float(_lay.k)
	var length := BAND_LENGTH*_k
	var dir := Vector2.from_angle(float(_lay.angle))
	var off := 0.0
	var alpha := 1.0-band_out
	if reduced_motion:
		alpha *= clampf(band_in*3.0,0,1)
	else:
		off = -(1.0-_ease_out(band_in))*length*1.1
		if slide_out: off += _ease_in(band_out)*length*.35
	for node in [_body,_demon_node,_trim,_text,_name_back,_name_node]:
		_place(node,dir*off)
	_place(_witch_node,dir*off*PARALLAX)
	modulate = Color(1,1,1,alpha)
	_body_material.set_shader_parameter("band_size",Vector2(length,float(_lay.height)))
	for node in [_body,_demon_node,_witch_node,_trim,_text,_name_back,_name_node]:
		node.queue_redraw()

func _place(node: Control, shift: Vector2) -> void:
	node.position = Vector2(_lay.centre)+shift
	node.rotation = float(_lay.angle)

# ---- drawing, band-local coordinates: x along the band from the centre line's middle, y across it, both in code units ----

func _band_rect() -> Rect2:
	var length := BAND_LENGTH*_k
	var h := float(_lay.height)
	return Rect2(-length*.5,-h*.5,length,h)

func _draw_body() -> void:
	var r := _band_rect()
	if _body_tex != null:
		_body.material = null
		var tile := r.size.y*float(_body_tex.get_width())/float(_body_tex.get_height())
		var x := r.position.x
		while x < r.end.x:
			var w := minf(tile,r.end.x-x)
			_body.draw_texture_rect_region(_body_tex,Rect2(x,r.position.y,w,r.size.y),Rect2(0,0,float(_body_tex.get_width())*w/tile,float(_body_tex.get_height())))
			x += tile
	else:
		_body.material = _body_material
		_body.draw_rect(r,Color.WHITE)

func _draw_trim() -> void:
	var r := _band_rect()
	var lit := clampf(bonus/.3,0,1)
	var brass := Palette.BRASS.lerp(Palette.BRASS_HI,lit).lerp(Palette.BRASS_HI,trim_flash)
	var dim := Palette.BRASS_DIM.lerp(Palette.BRASS,lit*.6+trim_flash*.4)
	var element_color := Palette.element_color(element)
	var clear := Color(element_color,0.0)
	# A11 12.2: outer brass 4, gap 2, inner brass 1.5, then the element's line 4 at full strength, and a soft light of 14 spreading OUT of the band (alpha 0.45).
	for side: float in [-1.0,1.0]:
		var edge: float = r.position.y if side < 0.0 else r.end.y
		_trim.draw_polygon(PackedVector2Array([Vector2(r.position.x,edge),Vector2(r.end.x,edge),Vector2(r.end.x,edge+side*14.0),Vector2(r.position.x,edge+side*14.0)]),
			PackedColorArray([Color(element_color,.45),Color(element_color,.45),clear,clear]))
		_trim.draw_rect(Rect2(r.position.x,minf(edge,edge-side*4.0),r.size.x,4.0),brass)
		_trim.draw_rect(Rect2(r.position.x,minf(edge-side*6.0,edge-side*7.5),r.size.x,1.5),dim)
		_trim.draw_rect(Rect2(r.position.x,minf(edge-side*7.5,edge-side*11.5),r.size.x,4.0),element_color)
	# The light sweep: a bright slanted stripe (width 120, alpha 0.5) once across the band when the name stands, inside the band only.
	if sweep >= 0.0 and sweep <= 1.0:
		var x := lerpf(r.position.x*.45,r.end.x*.45,sweep)
		var lean := r.size.y*.35
		var c := Color(Palette.INK,.5*sin(PI*sweep))
		_trim.draw_polygon(PackedVector2Array([Vector2(x-60.0+lean,r.position.y),Vector2(x+60.0+lean,r.position.y),Vector2(x+60.0-lean,r.end.y),Vector2(x-60.0-lean,r.end.y)]),
			PackedColorArray([c,c,c,c]))

## A picture quad with soft left/right edges and an optional vertical cut. `box` is the picture's rectangle (band-local), `src` the window of the
## texture in pixels, `cut` the band's y range the picture is cut to (Vector2(top, bottom)) or Vector2.ZERO for none.
func _figure(node: Control, tex: Texture2D, box: Rect2, src: Rect2, cut: Vector2, fade_l: float, fade_r: float, alpha: float) -> void:
	var tsize := Vector2(tex.get_size())
	var v0 := src.position.y/tsize.y
	var v1 := src.end.y/tsize.y
	var u0 := src.position.x/tsize.x
	var u1 := src.end.x/tsize.x
	if cut != Vector2.ZERO:
		var top := maxf(box.position.y,cut.x)
		var bottom := minf(box.end.y,cut.y)
		if bottom <= top: return
		var f0 := (top-box.position.y)/box.size.y
		var f1 := (bottom-box.position.y)/box.size.y
		var nv0 := lerpf(v0,v1,f0)
		var nv1 := lerpf(v0,v1,f1)
		v0 = nv0; v1 = nv1
		box = Rect2(box.position.x,top,box.size.x,bottom-top)
	var w := box.size.x
	var xs := [0.0,minf(fade_l,w*.5),maxf(w-fade_r,w*.5),w]
	var alphas := [0.0 if fade_l > 0.0 else 1.0,1.0,1.0,0.0 if fade_r > 0.0 else 1.0]
	for i in 3:
		if float(xs[i+1])-float(xs[i]) <= 0.001: continue
		var xa: float = box.position.x+float(xs[i])
		var xb: float = box.position.x+float(xs[i+1])
		var ua := lerpf(u0,u1,float(xs[i])/w)
		var ub := lerpf(u0,u1,float(xs[i+1])/w)
		var ca := Color(1,1,1,float(alphas[i])*alpha)
		var cb := Color(1,1,1,float(alphas[i+1])*alpha)
		node.draw_polygon(PackedVector2Array([Vector2(xa,box.position.y),Vector2(xb,box.position.y),Vector2(xb,box.end.y),Vector2(xa,box.end.y)]),
			PackedColorArray([ca,cb,cb,ca]),PackedVector2Array([Vector2(ua,v0),Vector2(ub,v0),Vector2(ub,v1),Vector2(ua,v1)]),tex)

func _draw_witch() -> void:
	if _witch_tex == null or witch <= 0.0: return
	var h := float(_lay.height)
	var hb := h*(WITCH_HEIGHT_ALPHA if _witch_alpha else WITCH_HEIGHT)
	var wb := hb*_witch_focus.size.x/_witch_focus.size.y
	var box := Rect2(_lx(WITCH_LEFT),h*.5-hb,wb,hb)
	# Inside the strip (picture with its scene painted in) the edges melt into the leather; a transparent picture needs no melting.
	_figure(_witch_node,_witch_tex,box,_witch_focus,Vector2.ZERO if _witch_alpha else Vector2(-h*.5,h*.5),0.0 if _witch_alpha else EDGE_FADE_RIGHT,0.0 if _witch_alpha else EDGE_FADE,witch)

func _draw_demon() -> void:
	var frame: Texture2D = _demon_tex   # a still picture: a video frame in this window showed its brightness key as a box (VFX-B 6)
	if frame == null or demon <= 0.0: return
	var focus := _demon_focus
	if focus.size.x <= 0.0 or focus.size.y <= 0.0: focus = Rect2(Vector2.ZERO,frame.get_size())
	var h := float(_lay.height)
	var hd := h*DEMON_HEIGHT
	var wd := hd*focus.size.x/focus.size.y
	var s := 1.0 if reduced_motion else lerpf(1.06,1.0,_ease_out(demon))
	# The head's top stands DEMON_OVERFLOW band heights above the band (a picture with a real alpha or a dark ground that is keyed out), but never nearer to
	# the screen's top edge than HEAD_MIN_Y: the lift is cut to what the screen leaves.
	var overflow := h*DEMON_OVERFLOW
	var x_mid := _lx(DEMON_LEFT)+wd*.5
	var lay_c: Vector2 = _lay.centre
	var ang := float(_lay.angle)
	var screen_y_of_local_top := lay_c.y+sin(ang)*x_mid+cos(ang)*(-h*.5-overflow)
	if screen_y_of_local_top < HEAD_MIN_Y*_k: overflow = maxf(0.0,overflow-(HEAD_MIN_Y*_k-screen_y_of_local_top)/cos(ang))
	var top := -h*.5-overflow
	var box := Rect2(_lx(DEMON_LEFT),top,wd,hd)
	var centre := Vector2(box.get_center().x,box.end.y)   # grows from the bottom, like a figure stepping up
	box = Rect2(centre+(box.position-centre)*s,box.size*s)
	# The picture is cut at the band's lower line (above the brass lines), not at the top.
	_figure(_demon_node,frame,box,focus,Vector2(top*s,h*.5-11.5),EDGE_FADE*.4,EDGE_FADE_RIGHT,demon)

## An iron plate (U-101 replaces the ink slick): a dark steel plate with chamfered corners and a brass hairline on its top and bottom edges.
## `rect` is the plate's rectangle in the item's drawing space, `alpha` fades it. The caller draws the text over it.
static func iron_plate(item: CanvasItem, rect: Rect2, alpha: float = 1.0) -> void:
	var c := minf(10.0,rect.size.y*.3)
	var pts := PackedVector2Array([rect.position+Vector2(c,0),Vector2(rect.end.x-c,rect.position.y),Vector2(rect.end.x,rect.position.y+c),Vector2(rect.end.x,rect.end.y-c),
		Vector2(rect.end.x-c,rect.end.y),Vector2(rect.position.x+c,rect.end.y),Vector2(rect.position.x,rect.end.y-c),Vector2(rect.position.x,rect.position.y+c)])
	item.draw_colored_polygon(pts,Color(0.02,0.022,0.026,.86*alpha))
	item.draw_line(Vector2(rect.position.x+c,rect.position.y),Vector2(rect.end.x-c,rect.position.y),Color(Palette.BRASS,.85*alpha),1.5)
	item.draw_line(Vector2(rect.position.x+c,rect.end.y),Vector2(rect.end.x-c,rect.end.y),Color(Palette.BRASS,.85*alpha),1.5)

func _name_layout() -> Dictionary:
	var words := texts(element)
	var h_scale := float(_lay.height)/(BAND_H*_k)
	var title := String(words.name)
	var fit := fit_name(title)
	return {"words":words,"h_scale":h_scale,"cx":_lx(NAME_CENTER_X),"cy":NAME_Y*_k*h_scale,"title":title,"size":int(fit.size),"width":float(fit.width)}

func _draw_text() -> void:
	var lay := _name_layout()
	var words: Dictionary = lay.words
	var h_scale: float = lay.h_scale
	var cx: float = lay.cx
	var cy: float = lay.cy
	var width: float = lay.width
	var left := cx-width*.5
	if line > 0.0:
		var bold := Loc.font("bold")
		var at_line := Vector2(left,cy+LINE_DY*_k*h_scale+(bold.get_ascent(LINE_SIZE)-bold.get_descent(LINE_SIZE))*.5)
		_text.draw_string_outline(bold,at_line,String(words.line),HORIZONTAL_ALIGNMENT_LEFT,-1,LINE_SIZE,4,Color(0,0,0,.9*line))
		_text.draw_string(bold,at_line,String(words.line),HORIZONTAL_ALIGNMENT_LEFT,-1,LINE_SIZE,Color(Palette.INK,line))

## Behind the fill (A11 12.2 as changed by U-101): a faint light of the element's colour, an iron plate, short brass ornaments left and right of the name, the
## dark edge round the letters, and the highlight line under them (the "cut into metal" look: the top inner edge is shaded by the shader, the bottom edge lit here).
func _draw_name_back() -> void:
	if name_t <= 0.0: return
	var lay := _name_layout()
	var font := name_font()
	var size_: int = lay.size
	var width: float = lay.width
	var cx: float = lay.cx
	var cy: float = lay.cy
	var element_color := Palette.element_color(element)
	var a := clampf(name_t*1.4,0,1)
	var scale_ := 1.0 if reduced_motion else lerpf(1.25,1.0,_ease_out(name_t))
	var plate_w := width+150.0
	var plate_h := float(size_)*.95
	# The light: a soft ellipse of the element's colour behind the plate.
	var fan := PackedVector2Array([Vector2(cx,cy)])
	var cols := PackedColorArray([Color(element_color,.34*a)])
	for i in 25:
		var ang := TAU*float(i)/24.0
		fan.append(Vector2(cx+cos(ang)*plate_w*.62*scale_,cy+sin(ang)*plate_h*.95*scale_))
		cols.append(Color(element_color,0.0))
	_name_back.draw_polygon(fan,cols)
	iron_plate(_name_back,Rect2(cx-plate_w*.5*scale_,cy-plate_h*.5*scale_,plate_w*scale_,plate_h*scale_),a)
	# Brass ornaments: a short line ending in a small diamond, on both sides of the name.
	for side: float in [-1.0,1.0]:
		var x0 := cx+side*(width*.5+22.0)*scale_
		var x1 := cx+side*(width*.5+68.0)*scale_
		_name_back.draw_line(Vector2(x0,cy),Vector2(x1,cy),Color(Palette.BRASS,a),2.0)
		var d := 6.0*scale_
		_name_back.draw_colored_polygon(PackedVector2Array([Vector2(x0,cy-d),Vector2(x0-side*d,cy),Vector2(x0,cy+d),Vector2(x0+side*d,cy)]),Color(Palette.BRASS_HI,a))
	_name_back.draw_set_transform(Vector2(cx,cy),0.0,Vector2(scale_,scale_))
	var base := (font.get_ascent(size_)-font.get_descent(size_))*.5
	var at := Vector2(-width*.5,base)
	var title: String = lay.title
	for glow in [[18,.10],[13,.16],[9,.24]]:
		_name_back.draw_string_outline(font,at,title,HORIZONTAL_ALIGNMENT_LEFT,-1,size_,int(glow[0]),Color(element_color,float(glow[1])*a))
	_name_back.draw_string_outline(font,at,title,HORIZONTAL_ALIGNMENT_LEFT,-1,size_,8,Color(0.01,0.01,0.015,.95*a))
	_name_back.draw_string(font,at+Vector2(0,2.0),title,HORIZONTAL_ALIGNMENT_LEFT,-1,size_,Color(Palette.INK,.55*a))
	_name_back.draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

## The fill: brass at the top running to old gold at the bottom, the top inner edge shaded (shader). Upright, no lean, no rough edge.
func _draw_name() -> void:
	if name_t <= 0.0: return
	var lay := _name_layout()
	var font := name_font()
	var size_: int = lay.size
	var width: float = lay.width
	var scale_ := 1.0 if reduced_motion else lerpf(1.25,1.0,_ease_out(name_t))
	_name_node.draw_set_transform(Vector2(float(lay.cx),float(lay.cy)),0.0,Vector2(scale_,scale_))
	_name_material.set_shader_parameter("pivot_y",0.0)
	_name_material.set_shader_parameter("height",float(size_))
	var base := (font.get_ascent(size_)-font.get_descent(size_))*.5
	_name_node.draw_string(font,Vector2(-width*.5,base),String(lay.title),HORIZONTAL_ALIGNMENT_LEFT,-1,size_,Color(1,1,1,clampf(name_t*1.4,0,1)))
	_name_node.draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
