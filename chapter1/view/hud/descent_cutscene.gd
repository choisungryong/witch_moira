extends Control
## The descent's cut-scene (A11 12.3, U-100): the demon's 3-second video (the length comes from the file, see video_seconds()), drawn full screen. This part DRAWS: the unfolding band (a slanted strip of the
## element's colour that opens from the band's own height to the whole screen and closes back to it), the video seen through that strip, the name tag
## (the demon's name and, big, the skill's name: U-102 took every spoken line away) and the skip hint. It keeps no timetable and takes no input: the presenter
## (view/fx/descent_fx.gd) pushes the values on its schedule and decides about skipping (A11 12.3.4). Presentation only: nothing here reads or writes the core.
##
##   var cut := DescentCutscene.attach(host)          # a CanvasLayer above the HUD's (layer 2), the HUD is hidden while the cut-scene runs
##   if cut.open_stream("ember"):                     # false: no file / not a Theora file -> the presenter falls back to the long band (A11 12.3.3)
##       ... on descent_ready: open_stream() already holds the first frame paused ...
##   cut.first_frame_ready()                          # true once a frame is on hand (the presenter waits at most 0.5 s for it, else the band)
##   cut.start()                                      # video runs (sound is the game's, the file has none)
##   cut.apply({"open": 0..1, "plate": 0..1, "skip_hint": 0..1, "reduced_motion": false, "fade": 1.0, "closed_cy": px, "closed_h": px})
##   cut.close()
## Video: Ogg Theora (.ogv) only; the slot is video.cutscene.descent.<element> (a video slot, planned until the file exists). 16:9 fills the screen;
## a portrait video (aspect < 1.2) stands in a window 0.92 H high at x 0.58 W with a brass frame, the band's colour filling the sides (12.3.5).
## The first frame is held by playing until a frame exists and then pausing (one or two frames are spent). The band's demon window does NOT use the video
## any more (a video frame there showed its brightness key as a box): it is the still picture.
const Palette = preload("res://chapter1/view/hud/palette.gd")
const Loc = preload("res://chapter1/view/loc.gd")
const AssetSlots = preload("res://chapter1/view/assets/asset_slots.gd")
const DescentBand = preload("res://chapter1/view/hud/descent_band.gd")
const MASK_SHADER = preload("res://chapter1/view/hud/descent_cutscene_mask.gdshader")
const NAME_SHADER = preload("res://chapter1/view/hud/descent_band_name.gdshader")
const SLOT_PREFIX := "video.cutscene.descent."
const TILT := 0.13962634
const BAND_H := 216.0
const BAND_CENTER_Y := 180.0
const FULL_H := 1300.0           ## the strip's full height: enough to cover the screen from the middle line at any tilt (about 1120 needed)
const BAND_LENGTH := 3400.0
const WINDOW_H := 0.92           ## a portrait video's window, as a share of the screen's height
const WINDOW_X := 0.58           ## and its middle, as a share of the screen's width
const PORTRAIT_BELOW := 1.2      ## aspect under this is a portrait video
const TAG_NAME_SIZE := 72        ## the skill name on the tag (the band has 84; the tag shares the screen with the picture)
const TAG_NAME_MAX_W := 640.0

var element := "ember"
var open_t := 0.0
var plate := 0.0
var skip_hint := 0.0
var reduced_motion := false
var fade := 1.0
var closed_cy := -1.0     ## where the narrowed strip stands (px, the band's own layout); < 0: the default band place
var closed_h := -1.0

var _player: VideoStreamPlayer
var _body: Control
var _edge: Control
var _text: Control
var _name_fill: Control
var _name_material: ShaderMaterial
var _contract: Dictionary = {}
var _has := false
var _first_ready := false
var _pending_pause := false
var _body_material: ShaderMaterial
var _mask_material: ShaderMaterial
var _window := Rect2()
var _portrait := false
var _lay_key: Array = []

## A canvas layer above the HUD's (layer 1): layer 2. Returns the cut-scene part.
static func attach(host: Node) -> Control:
	var layer := CanvasLayer.new()
	layer.name = "DescentCutscene"
	layer.layer = 2
	host.add_child(layer)
	var cut: Control = load("res://chapter1/view/hud/descent_cutscene.gd").new()
	layer.add_child(cut)
	return cut

func _init() -> void:
	name = "Cutscene"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_body = _child("Body",0)
	_player = VideoStreamPlayer.new()
	_player.name = "Video"
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player.expand = true
	_player.volume_db = -80.0
	_player.z_index = 1
	_mask_material = ShaderMaterial.new(); _mask_material.shader = MASK_SHADER
	_player.material = _mask_material
	add_child(_player)
	_edge = _child("Edge",2)
	_text = _child("Text",3)
	_name_fill = _child("NameFill",4)
	_name_material = ShaderMaterial.new(); _name_material.shader = NAME_SHADER
	_name_material.set_shader_parameter("top",Palette.BRASS_HI.lerp(Palette.INK,.8))
	_name_material.set_shader_parameter("bottom",Palette.BRASS.lerp(Palette.BRASS_HI,.75))
	_name_fill.material = _name_material
	_body.draw.connect(_draw_body)
	_edge.draw.connect(_draw_edge)
	_text.draw.connect(_draw_text)
	_name_fill.draw.connect(_draw_name_fill)
	resized.connect(func(): _lay_key = [])

func _child(label: String, z: int) -> Control:
	var node := Control.new()
	node.name = label
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.size = Vector2.ZERO
	node.z_index = z
	add_child(node)
	return node

# ---- the video ----

## Opens the stream of video.cutscene.descent.<el> and holds its first frame paused. False when the slot is planned, its file is missing or it is not
## a Theora file: the presenter then shows the long band (no cut-scene), and does not try again in this run.
func open_stream(el: String) -> bool:
	close()
	element = el
	var id := SLOT_PREFIX+el
	if not (AssetSlots.has_slot(id) and not AssetSlots.is_planned(id) and AssetSlots.available(id)): return false
	var stream := AssetSlots.video(id)
	if stream == null: return false
	_contract = AssetSlots.contract(id)
	_player.stream = stream
	_player.play()
	_pending_pause = true
	_first_ready = false
	_has = true
	_lay_key = []
	return true

func has_video() -> bool:
	return _has

## A frame is on hand (the first one, held paused after open_stream, or any later one).
func first_frame_ready() -> bool:
	return _has and (_first_ready or frame_size().x > 0.0)

func frame_texture() -> Texture2D:
	return _player.get_video_texture() if _has else null

func frame_size() -> Vector2:
	var tex := frame_texture()
	return Vector2(tex.get_size()) if tex != null else Vector2.ZERO

## The video's aspect: the frame's when there is one, else the contract's ("16:9"), else 16:9.
func video_aspect() -> float:
	var s := frame_size()
	if s.x > 0.0 and s.y > 0.0: return s.x/s.y
	var parts := String(_contract.get("aspect","16:9")).split(":")
	if parts.size() == 2 and float(parts[1]) > 0.0: return float(parts[0])/float(parts[1])
	return 16.0/9.0

## The video's length in seconds: the stream's own when the engine knows it, else the slot's contract.seconds (3.0). The presenter schedules from this, not from a literal.
func video_seconds() -> float:
	if not _has: return 0.0
	var own := _player.get_stream_length()
	return own if own > 0.05 else float(_contract.get("seconds",3.0))

func start() -> void:
	if not _has: return
	_pending_pause = false
	if not _player.is_playing(): _player.play()
	_player.paused = false

func set_paused(paused_: bool) -> void:
	if _has and not _pending_pause: _player.paused = paused_

func video_position() -> float:
	return _player.stream_position if _has else 0.0

func is_playing() -> bool:
	return _has and _player.is_playing() and not _player.paused

func _process(_delta: float) -> void:
	if not _has: return
	if _pending_pause and frame_size().x > 0.0:
		_player.paused = true
		_pending_pause = false
		_first_ready = true

func close() -> void:
	_has = false
	_first_ready = false
	_pending_pause = false
	if _player != null:
		_player.stop()
		_player.stream = null
	visible = false

# ---- the picture ----

## Values (all optional): open (0 closed band height .. 1 whole screen), plate (the name tag), skip_hint (0..1), reduced_motion, fade (1 normal, 0 black),
## closed_cy / closed_h (px: where and how high the narrowed strip stands, the band's own layout, so the hand-over to the band has no step), element.
func apply(values: Dictionary) -> void:
	for key in values:
		match String(key):
			"open": open_t = clampf(float(values[key]),0,1)
			"plate": plate = clampf(float(values[key]),0,1)
			"skip_hint": skip_hint = clampf(float(values[key]),0,1)
			"reduced_motion": reduced_motion = bool(values[key])
			"fade": fade = clampf(float(values[key]),0,1)
			"closed_cy": closed_cy = float(values[key])
			"closed_h": closed_h = float(values[key])
			"element": element = String(values[key])
	_refresh()

static func _ease_out(t: float) -> float:
	return smoothstep(0.0,1.0,clampf(t,0,1))   # an even unfold: the strip is half-open at open 0.5

func _refresh() -> void:
	if _body == null: return
	visible = _has and open_t > 0.0
	if not visible: return
	var k := size.y/900.0
	var e := 1.0 if reduced_motion else _ease_out(open_t)
	var h := lerpf(closed_h if closed_h > 0.0 else BAND_H*k,FULL_H*k,e)
	var centre := Vector2(size.x*.5,lerpf(closed_cy if closed_cy >= 0.0 else BAND_CENTER_Y*k,size.y*.5,e))
	modulate = Color(1,1,1,open_t if reduced_motion else 1.0)
	_body_material = DescentBand.body_material(element)
	_body_material.set_shader_parameter("band_size",Vector2(BAND_LENGTH*k,h))
	_body_material.set_shader_parameter("clock",Time.get_ticks_msec()/1000.0)
	for node in [_body,_edge]:
		node.position = centre
		node.rotation = -TILT
	_edge.set_meta("half_h",h*.5)
	_body.set_meta("half_h",h*.5)
	# The video's rectangle.
	var aspect := video_aspect()
	_portrait = aspect < PORTRAIT_BELOW
	if _portrait:
		var wh := size.y*WINDOW_H
		_window = Rect2(Vector2(size.x*WINDOW_X-wh*aspect*.5,(size.y-wh)*.5),Vector2(wh*aspect,wh))
	else:
		var cover := maxf(size.x/aspect,size.y)
		var vw := cover*aspect
		_window = Rect2(Vector2((size.x-vw)*.5,(size.y-cover)*.5),Vector2(vw,cover))
	_player.position = _window.position
	_player.size = _window.size
	_mask_material.set_shader_parameter("centre",centre)
	_mask_material.set_shader_parameter("angle",-TILT)
	_mask_material.set_shader_parameter("half_h",h*.5)
	_mask_material.set_shader_parameter("fade",fade)
	_player.visible = true
	for node in [_body,_edge,_text,_name_fill]:
		node.queue_redraw()

func _draw_body() -> void:
	var h := float(_body.get_meta("half_h",108.0))*2.0
	var k := size.y/900.0
	_body.material = _body_material
	_body.draw_rect(Rect2(-BAND_LENGTH*k*.5,-h*.5,BAND_LENGTH*k,h),Color.WHITE)

## Brass and the element's line along both edges of the strip while it is narrow enough to have edges on the screen; a portrait video's window gets a frame.
func _draw_edge() -> void:
	var half := float(_edge.get_meta("half_h",108.0))
	var k := size.y/900.0
	var length := BAND_LENGTH*k
	var ec := Palette.element_color(element)
	for side: float in [-1.0,1.0]:
		var edge := side*half
		_edge.draw_rect(Rect2(-length*.5,minf(edge,edge-side*4.0),length,4.0),Palette.BRASS)
		_edge.draw_rect(Rect2(-length*.5,minf(edge-side*6.0,edge-side*7.5),length,1.5),Palette.BRASS_DIM)
		_edge.draw_rect(Rect2(-length*.5,minf(edge-side*7.5,edge-side*11.5),length,4.0),ec)

## The name tag's layout: the demon's name (small) above the skill's name (big), lower left.
func _tag_layout() -> Dictionary:
	var font := DescentBand.name_font()
	var title := Loc.t("descent.name."+element)
	var size_ := TAG_NAME_SIZE
	var width := font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,size_).x
	while size_ > 44 and width > TAG_NAME_MAX_W:
		size_ -= 2
		width = font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,size_).x
	var k := size.y/900.0
	var slide := (1.0-plate)*-24.0*k
	return {"font":font,"title":title,"size":size_,"width":width,"at":Vector2(64.0*k+slide,size.y-70.0*k),"k":k}

func _draw_text() -> void:
	var k := size.y/900.0
	var e := 1.0 if reduced_motion else _ease_out(open_t)
	if _portrait and _has and e > .9:   # the window's frame shows once the strip has opened round it (it is not under the strip's mask)
		var outer := _window.grow(5.0)
		_text.draw_rect(outer,Palette.BRASS,false,4.0)
		_text.draw_rect(_window.grow(-1.0),Palette.BRASS_DIM,false,1.5)
	if plate > 0.0:
		var lay := _tag_layout()
		var font: Font = lay.font
		var at: Vector2 = lay.at
		var ec := Palette.element_color(element)
		# A dark wash in the lower left so the tag reads on any frame.
		var wash := Color(0,0,0,.62*plate)
		var clear := Color(0,0,0,0)
		_text.draw_polygon(PackedVector2Array([Vector2(0,size.y-300*k),Vector2(980*k,size.y-300*k),Vector2(980*k,size.y),Vector2(0,size.y)]),PackedColorArray([clear,clear,clear,wash]))
		# the demon's name, small, over the skill's name (T3 26)
		var heading := Loc.font("heading")
		var demon_name := Loc.t("demon."+element+".name")
		var demon_at := at+Vector2(0,-float(lay.size)-8.0)
		_text.draw_string_outline(heading,demon_at,demon_name,HORIZONTAL_ALIGNMENT_LEFT,-1,26,5,Color(0,0,0,.9*plate))
		_text.draw_string(heading,demon_at,demon_name,HORIZONTAL_ALIGNMENT_LEFT,-1,26,Color(Palette.INK_DIM,plate))
		# the skill's name: a light of the element's colour, the dark edge, the fill comes from _name_fill (brass to old gold, cut into metal)
		for glow in [[18,.10],[13,.16],[9,.24]]:
			_text.draw_string_outline(font,at,String(lay.title),HORIZONTAL_ALIGNMENT_LEFT,-1,int(lay.size),int(glow[0]),Color(ec,float(glow[1])*plate))
		_text.draw_string_outline(font,at,String(lay.title),HORIZONTAL_ALIGNMENT_LEFT,-1,int(lay.size),8,Color(0.01,0.01,0.015,.95*plate))
		_text.draw_string(font,at+Vector2(0,2.0),String(lay.title),HORIZONTAL_ALIGNMENT_LEFT,-1,int(lay.size),Color(Palette.INK,.55*plate))
	if skip_hint > 0.0:
		# an iron plate with the word, lower right (the key plate of the HUD is too small to read at 720p)
		var hint := Loc.t("descent.cutscene.skip")
		var font_h := Loc.font("heading")
		var hint_w := font_h.get_string_size(hint,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x
		var plate_rect := Rect2(size.x-48.0*k-hint_w-44.0,size.y-58.0*k,hint_w+44.0,36.0)
		DescentBand.iron_plate(_text,plate_rect,skip_hint)
		var at_hint := Vector2(plate_rect.position.x+22.0,plate_rect.position.y+25.0)
		_text.draw_string_outline(font_h,at_hint,hint,HORIZONTAL_ALIGNMENT_LEFT,-1,18,3,Color(0,0,0,.85*skip_hint))
		_text.draw_string(font_h,at_hint,hint,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color(Palette.INK,skip_hint))

func _draw_name_fill() -> void:
	if plate <= 0.0: return
	var lay := _tag_layout()
	_name_material.set_shader_parameter("pivot_y",float(lay.at.y)-float(lay.size)*.35)
	_name_material.set_shader_parameter("height",float(lay.size))
	_name_fill.draw_string(lay.font,lay.at,String(lay.title),HORIZONTAL_ALIGNMENT_LEFT,-1,int(lay.size),Color(1,1,1,plate))
