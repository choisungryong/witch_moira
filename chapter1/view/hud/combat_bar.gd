extends Control
## Bottom-centre combat bar (layout A): life orb, skill slots, the ultimate slot, dash and potion, soul orb, and the
## strip of effects on the hero. It only reads run state. One control, one _draw(): every piece comes from the atlas
## in ui_style.gd, no node is added for it (A4 3.2.5).
const ElementSeal = preload("res://chapter1/view/ui38/element_seal.gd")
const Palette = preload("res://chapter1/view/hud/palette.gd")
const UiStyle = preload("res://chapter1/view/hud/ui_style.gd")
const Loc = preload("res://chapter1/view/loc.gd")
const SKILLS := [["chapter1.skill.ember","ember",Palette.FIRE],["chapter1.skill.frost","frost",Palette.FROST],["chapter1.skill.arc","arc",Palette.ARC]]
const BRASS := Palette.BRASS
const BRASS_DIM := Palette.BRASS_DIM
const BRASS_HI := Palette.BRASS_HI
const PLATE := Palette.PLATE
const SLOT := Palette.SLOT
const INK := Palette.INK
const INK_DIM := Palette.INK_DIM
## Level badge on the soul orb's lower rim (A2 3.5): centre = SOUL_CENTER + (0, ORB_RADIUS-2).
const BADGE_RADIUS := 16.0
const BAR_SIZE := Vector2(860,160)
const LIFE_CENTER := Vector2(66,90)
const SOUL_CENTER := Vector2(794,90)
const ORB_RADIUS := 54.0
const SLOT_Y := 92.0
const SLOT_SIZES := [60,60,60,74,60,60]
const SLOT_GAP := 14.0
const LOW_LIFE := .30
## Effect strip: ends left of the life orb's ring, below y 720 (code), so it stays out of the central 60 percent.
const EFFECT_SIZE := 30.0

var _seals: Array[Control] = []
var _rects: Array[Rect2] = []
var _life := 1.0
var _life_text := ""
var _soul := 0.0
const SOUL_DEFAULT := Palette.FROST
var _soul_color := SOUL_DEFAULT
var _level := 1
var _skill_state: Array[Dictionary] = []
var _dash_left := 0.0
var _dash_total := 3.0
var _potions := 0
var _potion_left := 0.0
var _clock := 0.0
var _playing := false
var _invulnerable := false
var _in_ward := false
var _pill := UiStyle.pill()
var _strip_node: Control
var _liquids: Array[ShaderMaterial] = []
var _primary_index := -1
var _soul_key := "frost"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = BAR_SIZE
	anchor_left = .5; anchor_right = .5; anchor_top = 1.0; anchor_bottom = 1.0
	offset_left = -BAR_SIZE.x*.5; offset_right = BAR_SIZE.x*.5
	offset_top = -BAR_SIZE.y-10; offset_bottom = -10
	if UiStyle.bound(): texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var total := 0.0
	for size_ in SLOT_SIZES: total += float(size_)
	total += SLOT_GAP*float(SLOT_SIZES.size()-1)
	var x := BAR_SIZE.x*.5-total*.5
	for size_ in SLOT_SIZES:
		_rects.append(Rect2(x,SLOT_Y-float(size_)*.5,float(size_),float(size_)))
		x += float(size_)+SLOT_GAP
	if UiStyle.bound(): _make_bound_nodes()
	for index in SKILLS.size():
		_skill_state.append({"rank":0,"evolved":false,"wait":0.0,"seconds":0.0})
		# The bound look draws the glyphs itself; the old look keeps its seal nodes.
		if UiStyle.bound(): continue
		var seal = ElementSeal.new()
		seal.element = SKILLS[index][1]; seal.tint = SKILLS[index][2]
		seal.size = Vector2(70,70)
		seal.position = _rects[index].get_center()-Vector2(35,35)
		add_child(seal)
		_seals.append(seal)

## `snapshot` is the growth snapshot the HUD took this frame (one deep copy shared by its pieces); without it the bar takes its own.
func sync(run: RefCounted, delta: float, snapshot: Dictionary = {}) -> void:
	_playing = run.mode == "playing"
	if _playing: _clock += delta
	if run.hero.is_empty():
		visible = false; return
	visible = true
	_life = clampf(float(run.hero.hp_raw)/maxf(1.0,float(run.hero.max_hp_raw)),0,1)
	_life_text = "%d / %d" % [ceili(float(run.hero.hp_raw)/256.0),ceili(float(run.hero.max_hp_raw)/256.0)]
	var growth: Dictionary = snapshot if not snapshot.is_empty() else run.growth.snapshot()
	_level = int(growth.level)
	var thresholds: Array = run.growth.xp_thresholds()
	var index := _level-1
	if index >= 0 and index < thresholds.size()-1:
		var span := float(thresholds[index+1])-float(thresholds[index])
		_soul = clampf((float(growth.xp)-float(thresholds[index]))/maxf(1.0,span),0,1)
	else: _soul = 1.0
	# The in-run growth orb carries the primary element's colour (ART-PLAN 2.1).
	_soul_color = SOUL_DEFAULT
	_primary_index = -1
	for k in SKILLS.size():
		if SKILLS[k][0] == String(growth.get("primary","")): _soul_color = SKILLS[k][2]; _primary_index = k; _soul_key = SKILLS[k][1]
	var ranks: Dictionary = growth.get("ranks",{})
	var evolved: Array = growth.get("evolved",[])
	for i in SKILLS.size():
		var id_: String = SKILLS[i][0]
		var rank := int(ranks.get(id_,0))
		var wait := 0.0
		var seconds := 0.0
		if rank > 0:
			var next_cast: Dictionary = run.get("_next_cast")
			var skill: Dictionary = run.effective_skill(id_)
			var cooldown := maxf(1.0,float(skill.get("effects",{}).get("cooldown_ticks",60)))
			wait = clampf(float(int(next_cast.get(id_,0))-int(run.tick))/cooldown,0,1)
			seconds = wait*cooldown/60.0
		_skill_state[i] = {"rank":rank,"evolved":id_ in evolved,"wait":wait,"seconds":seconds}
		if not _seals.is_empty(): _seals[i].modulate = Color(1,1,1,1) if rank > 0 else Color(1,1,1,.22)
	_dash_left = maxf(0.0,float(int(run.get_next_dash_tick())-int(run.tick))/60.0)
	_dash_total = maxf(_dash_total if _dash_left > 0 else 1.0,_dash_left)
	_potions = int(run.get("potions"))
	_potion_left = maxf(0.0,float(int(run.get("_next_potion"))-int(run.tick))/60.0)
	# Read-only hero state for the effect strip: the dodge's invulnerable frames, and standing in a boss ward.
	_invulnerable = int(run.tick) < int(run.get("_invulnerable_until"))
	_in_ward = false
	for hazard in run.get("chapter_hazards"):
		if run.hero.position.distance_to(hazard.position) <= float(hazard.radius): _in_ward = true; break
	# The descent's gauge rides the medal (D15 U-2). It reads descent_view() only; a run without the descent has {"enabled":false}
	# and nothing below changes: no redraw reason, no extra piece.
	var descent_view: Dictionary = run.descent_view()
	_descent_on = bool(descent_view.get("enabled",false))
	if _descent_on:
		_descent_ratio = float(int(descent_view.ratio_bps))/10000.0
		_descent_state = String(descent_view.state)
		_descent_color = Palette.element_color(String(descent_view.element),BRASS_HI)
		_descent_element = String(descent_view.element)
		_descent_left = clampf(float(int(descent_view.get("sweep_left_ticks",0)))/maxf(1.0,float(int(descent_view.get("sweep_ticks",1)))),0,1)
		_descent_crest = bool(descent_view.get("crest",false))
		_descent_bonus = clampf(float(int(descent_view.get("hold_bonus_bps",0)))/10000.0,0,.3)
		_update_descent_cue(run,descent_view,delta)
	else:
		_descent_ratio = 0.0; _descent_state = ""; _descent_left = 0.0; _descent_crest = false; _descent_bonus = 0.0; _cue_left = 0.0
	# Redraw only when something the picture is made of changed (see _draw_key). A low life pulses with time, so it redraws
	# every frame, and so does the old look, which the key does not cover. A full descent gauge breathes, so it redraws too.
	var key := _draw_key()
	if _life < LOW_LIFE or not UiStyle.bound() or key != _drawn_key or (_descent_on and _descent_state == "ready"):
		_drawn_key = key
		queue_redraw()

var _drawn_key: Array = []
var _descent_on := false
var _descent_ratio := 0.0
var _descent_state := ""
var _descent_color := Palette.BRASS_HI
var _descent_element := ""
var _descent_left := 0.0       ## share of the sweep that is left (0..1), from sweep_left_ticks
var _descent_crest := false    ## the tide signal: the medal beats
var _descent_bonus := 0.0      ## hold_bonus_bps / 10000, at most .30: the rim gets thicker
var _cue_left := 0.0           ## seconds left of the first-ready line (ember, frost) or of the double beat (arc)
var _cue_done := false
var _cue_tick := 0
const DESCENT_CUE_SECONDS := 2.0

## D24 12.4: the cue of the first time the descent is ready in a run: a line beside the medal for 2 s (ember, frost), or two beats of
## the medal without words (arc). It runs on the frame time while playing, and starts again with a new run (the tick goes back).
func _update_descent_cue(run: RefCounted, view: Dictionary, delta: float) -> void:
	if int(run.tick) < _cue_tick: _cue_done = false; _cue_left = 0.0
	_cue_tick = int(run.tick)
	if String(view.state) == "ready" and int(view.get("uses",0)) == 0 and not _cue_done:
		_cue_done = true; _cue_left = DESCENT_CUE_SECONDS
	elif _cue_left > 0.0 and _playing:
		_cue_left = maxf(0.0,_cue_left-delta)

## The gauge ring around the medal slot: a dim ring, the filled arc in the element's colour from the top, and once full a
## breathing double ring (the same breath as the screen's edge aura). `c` is the medal's centre, `r` its ring radius.
func _draw_descent(c: Vector2, r: float) -> void:
	if not _descent_on: return
	var rim := 3.6+4.0*_descent_bonus/.3
	draw_arc(c,r,0,TAU,48,Color(0.02,.02,.025,.75),5.0,true)
	draw_arc(c,r,0,TAU,48,Color(BRASS_DIM,.55),2.0,true)
	var breathe := .5+.5*sin(_clock*5.0)
	if _descent_state == "ready" or _descent_state == "hold" or _descent_state == "sweep":
		var glow := .55+.45*breathe if _descent_state == "ready" else .9
		if _descent_state == "sweep":
			# The ring empties clockwise from the top as the sweep runs out (sweep_left_ticks).
			draw_arc(c,r,-PI*.5,-PI*.5+TAU*_descent_left,maxi(4,int(48.0*_descent_left)),Color(_descent_color.lerp(Color.WHITE,.25*breathe),.95),rim,true)
			draw_circle(c,r-5.0,Color(_descent_color,.08+.12*_descent_left))
		else:
			var beat := 0.0
			if _descent_crest: beat = .5+.5*sin(_clock*11.0)   # the tide: a faster beat than the breath, the ring swells with it
			draw_arc(c,r+4.0+3.0*beat,0,TAU,48,Color(_descent_color,.28*glow+.3*beat),5.0+3.0*beat,true)
			draw_arc(c,r,0,TAU,48,Color(_descent_color.lerp(Color.WHITE,.25*breathe+.3*beat),.95),rim,true)
			draw_circle(c,r-5.0,Color(_descent_color,.12+.16*glow+.12*beat))
			if _cue_left > 0.0 and _descent_element == "arc":
				# Lightning says nothing: the medal beats twice (0.2 s and 0.6 s into the cue).
				var t := DESCENT_CUE_SECONDS-_cue_left
				for start in [.2,.6]:
					var k := (t-float(start))/.3
					if k >= 0.0 and k <= 1.0: draw_arc(c,r+4.0+16.0*k,0,TAU,48,Color(_descent_color,.7*(1.0-k)),4.0,true)
	elif _descent_ratio > 0.0:
		draw_arc(c,r,-PI*.5,-PI*.5+TAU*_descent_ratio,maxi(4,int(48.0*_descent_ratio)),Color(_descent_color,.9),3.6,true)
	# Beside the medal, when it is ready: the descent's name (descent.name.<element>) and, once per run, the cue line.
	if _descent_state == "ready" and _descent_element != "":
		_text(c+Vector2(0,-r-14.0),Loc.t("descent.name."+_descent_element),17,INK,170)
		if _cue_left > 0.0 and _descent_element != "arc":
			var fade := clampf(_cue_left/.5,0,1)
			_text(c+Vector2(0,-r-38.0),Loc.t("descent.cue."+_descent_element),15,Color(INK,fade),340)
	# The key tag under the medal, like Space and Q (the letter is the key itself, not a word).
	if UiStyle.bound():
		var kc := c+Vector2(0,47.0)
		UiStyle.blit_centered(self,"key_tag",kc)
		_text(kc+Vector2(0,5),"R",14,INK if _descent_state == "ready" else INK_DIM,70,3)
	else:
		_text(c+Vector2(0,54),"R",14,INK if _descent_state == "ready" else INK_DIM,70)

## Every value _draw_bound reads. Exact values, not rounded ones: the cooldown sweeps and the seconds follow the tick, so
## the bar redraws while anything is cooling down and stands still when nothing moves.
func _draw_key() -> Array:
	var parts: Array = [_life_text,_life,_soul,_soul_color,_soul_key,_level,_primary_index,_dash_left,_dash_total,_potions,_potion_left,_in_ward,_invulnerable,_descent_on,_descent_ratio,_descent_state,_descent_left,_descent_crest,_descent_bonus,_cue_left,_descent_element]
	for state in _skill_state:
		parts.append(state.rank); parts.append(state.evolved); parts.append(state.wait); parts.append(state.seconds)
	return parts

func _text(at: Vector2, text: String, size_: int, color: Color, width: float = 120.0, outline: int = 4) -> void:
	var font := Loc.font("number")
	draw_string_outline(font,at-Vector2(width*.5,0),text,HORIZONTAL_ALIGNMENT_CENTER,width,size_,outline,Color(0,0,0,.85))
	draw_string(font,at-Vector2(width*.5,0),text,HORIZONTAL_ALIGNMENT_CENTER,width,size_,color)

func _draw() -> void:
	if UiStyle.bound(): _draw_bound()
	else: _draw_legacy()

# ======================================================================================
# Bound look (kit C): brass-ringed glass orbs on a leather strip that spans only orb to orb, round slots, key tags.
# Sizes in code units: kit pixels * UiStyle.CODE (the kit is authored at 2 px per 1080p px, 1080p is 1.2 x code).
# ======================================================================================
const STRIP_FROM := -150.0
const STRIP_TO := 980.0
const CY := 76.0
const BOUND_LIFE := Vector2(63.3,CY)
const BOUND_SOUL := Vector2(796.7,CY)
const BOUND_SLOT_X := [238.3,313.3,388.3,467.5,546.7,621.7]
const GLASS := 125.0
const ICON := 55.0

func _make_bound_nodes() -> void:
	var shader := UiStyle.liquid_shader()
	_strip_node = Control.new(); _strip_node.name = "Strip"
	_strip_node.mouse_filter = Control.MOUSE_FILTER_IGNORE; _strip_node.show_behind_parent = true
	_strip_node.size = BAR_SIZE
	_strip_node.draw.connect(_draw_strip)
	add_child(_strip_node)
	for centre in [BOUND_LIFE,BOUND_SOUL]:
		var rect := ColorRect.new(); rect.name = "Liquid"
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE; rect.show_behind_parent = true
		rect.size = Vector2(GLASS,GLASS); rect.position = centre-Vector2(GLASS,GLASS)*.5
		var material := ShaderMaterial.new(); material.shader = shader
		rect.material = material
		add_child(rect)
		_liquids.append(material)

## Leather strip: end pieces with the buckle and corner irons, tiles between, brass studs, and the shade below it.
const STRIP_SCALE := 1.45
func _draw_strip() -> void:
	var fade_top := CY-20.0
	var xs := [STRIP_FROM-60.0,STRIP_FROM+60.0,STRIP_TO-60.0,STRIP_TO+60.0]
	var alphas := [0.0,.5,.5,0.0]
	for i in 3:
		_strip_node.draw_polygon(PackedVector2Array([Vector2(xs[i],fade_top),Vector2(xs[i+1],fade_top),Vector2(xs[i+1],BAR_SIZE.y+14.0),Vector2(xs[i],BAR_SIZE.y+14.0)]),
			PackedColorArray([Color(0,0,0,0),Color(0,0,0,0),Color(0,0,0,alphas[i+1]),Color(0,0,0,alphas[i])]))
	var tile := UiStyle.piece_size("strip_tile")*STRIP_SCALE
	var end_size := UiStyle.piece_size("strip_left")*STRIP_SCALE
	var top := CY-tile.y*.5
	var x := STRIP_FROM+end_size.x-1.0
	var stop := STRIP_TO-end_size.x+1.0
	while x < stop:
		var width := minf(tile.x,stop-x)
		UiStyle.blit_part(_strip_node,"strip_tile",Rect2(x,top,width,tile.y),width/tile.x)
		x += tile.x-1.0
	UiStyle.blit(_strip_node,"strip_left",Rect2(Vector2(STRIP_FROM,top),end_size))
	UiStyle.blit(_strip_node,"strip_right",Rect2(Vector2(STRIP_TO-end_size.x,top),end_size))
	# Brass studs on the strip, one outside each orb.
	for stud_x in [BOUND_LIFE.x-104.0,BOUND_SOUL.x+104.0]:
		var stud := Vector2(stud_x,CY)
		_strip_node.draw_circle(stud+Vector2(0,1.5),6.5,Color(0,0,0,.5))
		_strip_node.draw_circle(stud,6.0,BRASS_DIM)
		_strip_node.draw_circle(stud,4.6,BRASS)
		_strip_node.draw_circle(stud+Vector2(-1.5,-1.5),1.8,Color(Palette.LINEN,.8))

func _sweep(centre: Vector2, wait: float, radius: float) -> void:
	if wait <= 0.0: return
	var points := PackedVector2Array([centre])
	var steps := maxi(3,int(ceil(wait*20.0)))
	for i in steps+1:
		var angle := -PI*.5+TAU*wait*float(i)/float(steps)
		points.append(centre+Vector2.from_angle(angle)*radius)
	draw_colored_polygon(points,Color(0,0,0,.3))

func _effect_badge(center: Vector2, kind: String) -> void:
	var r := EFFECT_SIZE*.5
	draw_circle(center,r,Color(0.055,.07,.075,.92))
	draw_arc(center,r,0,TAU,24,BRASS_HI if kind == "ward" else BRASS,2.0,true)
	match kind:
		"ward":
			draw_colored_polygon(PackedVector2Array([center+Vector2(0,-9),center+Vector2(9,7),center+Vector2(-9,7)]),Palette.THREAT)
			draw_line(center+Vector2(0,-3),center+Vector2(0,2),INK,2.0,true)
			draw_circle(center+Vector2(0,5),1.2,INK)
		_:
			draw_colored_polygon(PackedVector2Array([center+Vector2(-8,-8),center+Vector2(8,-8),center+Vector2(8,1),center+Vector2(0,10),center+Vector2(-8,1)]),Color(Palette.FROST,.9))
			draw_line(center+Vector2(0,-6),center+Vector2(0,6),Color("0e1316"),2.0,true)

func _active_effects() -> Array[String]:
	var list: Array[String] = []
	if _in_ward: list.append("ward")
	if _invulnerable: list.append("dodge")
	return list

func _draw_bound() -> void:
	var low := _life < LOW_LIFE
	var pulse := .5+.5*sin(_clock*9.0)
	# Liquids (shader nodes under this draw): fill, colour pieces and glass tint.
	var life_tint := Palette.LIFE if not low else Palette.LIFE_LOW.lerp(Palette.LIFE,pulse)
	UiStyle.set_liquid(_liquids[0],"life",_life,life_tint)
	UiStyle.set_liquid(_liquids[1],_soul_key,_soul,_soul_color)
	var ring_tint := Color.WHITE if not low else Color.WHITE.lerp(Palette.LIFE_LOW.darkened(.35),.2+.8*pulse)
	for orb in [[BOUND_LIFE,ring_tint],[BOUND_SOUL,Color.WHITE]]:
		UiStyle.blit_centered(self,"glass_highlight",orb[0],1.0,Color(1,1,1,.45))
		UiStyle.blit_centered(self,"orb_frame",orb[0],1.0,orb[1])
	# The life number sits in the liquid, no plate behind it.
	var number_font := UiStyle.number_font()
	draw_string(number_font,BOUND_LIFE+Vector2(-50.0,8.5),_life_text,HORIZONTAL_ALIGNMENT_CENTER,100,20,Color(0.12,0.0,0.03,.6))
	draw_string(number_font,BOUND_LIFE+Vector2(-50.0,7.0),_life_text,HORIZONTAL_ALIGNMENT_CENTER,100,20,Color("f0e4c4"))
	# Slots: round gem frames. The primary skill has the gold frame; a cooling slot shows its icon small above the seconds.
	var icons := ["icon_fire","icon_frost","icon_arc","","icon_dash","icon_potion"]
	for i in 6:
		var c := Vector2(BOUND_SLOT_X[i],CY)
		if i == 3:
			UiStyle.blit_centered(self,"medal_cross",c)
			_draw_descent(c,36.0)
			continue
		var learned := true
		var wait := 0.0
		var seconds := 0.0
		var frame := "slot_normal"
		if i < 3:
			var state: Dictionary = _skill_state[i]
			learned = int(state.rank) > 0
			wait = float(state.wait); seconds = float(state.seconds)
			if i == _primary_index: frame = "slot_selected"
		elif i == 4:
			wait = clampf(_dash_left/maxf(.1,_dash_total),0,1); seconds = _dash_left
		else:
			wait = clampf(_potion_left/4.0,0,1); seconds = _potion_left
		# Short gaps between casts (under half a second) are not shown as a cooldown.
		var counting := wait > 0.0 and seconds >= 0.5
		draw_circle(c,ICON*.5,Color(0.03,.035,.04,1))
		var icon_tint := Color.WHITE if (learned and (i != 5 or _potions > 0)) else Color(1,1,1,.4)
		if counting:
			UiStyle.blit_centered(self,icons[i],c+Vector2(0,-9),.6,Color(icon_tint,.6))
			_sweep(c,wait,ICON*.5)
			if frame != "slot_selected": frame = "slot_cooldown"
		else:
			UiStyle.blit_centered(self,icons[i],c,1.0,icon_tint)
		UiStyle.blit_centered(self,frame,c)
		if counting: _text(c+Vector2(0,19),"%.1f" % seconds,17,INK,56,4)
		if i < 3:
			# Rank beads under a skill slot: one brass bead per rank, a gold ring once evolved.
			var state2: Dictionary = _skill_state[i]
			var base := c+Vector2(0,CY*0.0+39.0)
			if bool(state2.evolved):
				draw_arc(base,4.5,0,TAU,20,BRASS_HI,2.0,true)
			else:
				for pip in 4:
					var bead := base+Vector2((float(pip)-1.5)*9.0,0)
					if pip < int(state2.rank): draw_circle(bead,3.0,SKILLS[i][2]); draw_arc(bead,3.2,0,TAU,12,BRASS,1.0,true)
					else: draw_arc(bead,2.6,0,TAU,12,Color(BRASS_DIM,.8),1.0,true)
	var p := Vector2(BOUND_SLOT_X[5],CY)
	var count_at := p+Vector2(24,24)
	draw_circle(count_at,9.5,Color(0.04,.045,.05,1))
	draw_arc(count_at,9.5,0,TAU,20,BRASS,1.5,true)
	_text(count_at+Vector2(0,5),str(_potions),14,INK,20,2)
	if low and _potions > 0 and _potion_left <= 0.0:
		draw_arc(p,ICON*.5+5.0,0,TAU,40,Color(Palette.LIFE_LOW,pulse),3.0,true)
	# Key tags (text 14 code units: 11.2 px at 720p).
	for key in [[4,"Space"],[5,"Q"]]:
		var kc := Vector2(BOUND_SLOT_X[key[0]],CY+47.0)
		UiStyle.blit_centered(self,"key_tag",kc)
		_text(kc+Vector2(0,5),key[1],14,INK,70,3)
	# Level plate: a brass disc hanging on the soul orb's lower rim.
	var badge := BOUND_SOUL+Vector2(0,66.0)
	UiStyle.blit_centered(self,"level_badge",badge,1.25)
	_text(badge+Vector2(0,7),str(_level),20,INK,40,3)
	var x_end := BOUND_LIFE.x-96.0
	for kind in _active_effects():
		_effect_badge(Vector2(x_end-EFFECT_SIZE*.5,CY),kind)
		x_end -= EFFECT_SIZE+6.0

# ======================================================================================
# Old look (THEME = LEGACY), kept so the switch in ui_style.gd really switches.
# ======================================================================================

func _orb(center: Vector2, fraction: float, top: Color, bottom: Color, rim: Color) -> void:
	draw_circle(center,ORB_RADIUS+6,Color("101315"))
	draw_arc(center,ORB_RADIUS+6,0,TAU,96,rim,2.5,true)
	draw_arc(center,ORB_RADIUS,0,TAU,96,BRASS_DIM,3.0,true)
	var inner := ORB_RADIUS-5
	draw_circle(center,inner,Color("1a1416"))
	var liquid_top := int(inner-2.0*inner*fraction)
	for y in range(liquid_top,int(inner)+1):
		var half := sqrt(maxf(0.0,inner*inner-float(y*y)))
		var shade := top.lerp(bottom,float(y+inner)/(2.0*inner))
		draw_line(center+Vector2(-half,y),center+Vector2(half,y),shade,1.3,true)
	# A soft highlight makes the vessel read as glass.
	draw_arc(center+Vector2(-6,-8),inner-9,PI*1.08,PI*1.52,24,Color(1,1,1,.16),4.0,true)
	for i in 8:
		var v := Vector2.from_angle(float(i)*TAU/8.0+PI/8.0)
		draw_line(center+v*(ORB_RADIUS+7),center+v*(ORB_RADIUS+12),rim,2,true)

func _slot(rect: Rect2, border: Color, wait: float) -> void:
	draw_rect(rect,SLOT)
	if wait > 0.0:
		var shade := Rect2(rect.position,Vector2(rect.size.x,rect.size.y*wait))
		draw_rect(shade,Color(0,0,0,.55))
	draw_rect(rect,border,false,2.0)
	draw_rect(rect.grow(-4),Color(border,.25),false,1.0)

func _draw_legacy() -> void:
	var first: Rect2 = _rects[0]
	var last: Rect2 = _rects[_rects.size()-1]
	var plate := Rect2(first.position.x-22,SLOT_Y-52,last.end.x-first.position.x+44,104)
	draw_rect(plate,PLATE)
	draw_rect(plate,BRASS_DIM,false,1.5)
	draw_line(plate.position+Vector2(8,0),Vector2(plate.end.x-8,plate.position.y),BRASS,2.0)
	# Life: the rim pulses once life is low, so the state is readable without the number.
	var low := _life < LOW_LIFE
	var pulse := .5+.5*sin(_clock*9.0)
	var life_rim := BRASS if not low else BRASS.lerp(Palette.LIFE_LOW,pulse)
	_orb(LIFE_CENTER,_life,Palette.LIFE if not low else Palette.LIFE_LOW.lerp(Palette.LIFE,pulse),Palette.LIFE_DEEP,life_rim)
	# The life number sits on a translucent pill so it reads on any liquid level (contrast target 4.5:1).
	var life_font := Loc.font("number")
	var life_width := life_font.get_string_size(_life_text,HORIZONTAL_ALIGNMENT_LEFT,-1,19).x+18.0
	draw_style_box(_pill,Rect2(LIFE_CENTER+Vector2(-life_width*.5,-12),Vector2(life_width,28)))
	_text(LIFE_CENTER+Vector2(0,7),_life_text,19,INK,130,5)
	_orb(SOUL_CENTER,_soul,_soul_color,_soul_color.darkened(.72),BRASS)
	# Level: a small plate over the lower rim, number only. Nothing is written inside the orb.
	var badge := SOUL_CENTER+Vector2(0,ORB_RADIUS-2)
	draw_circle(badge,BADGE_RADIUS,Palette.SURFACE)
	draw_arc(badge,BADGE_RADIUS,0,TAU,48,BRASS,1.5,true)
	_text(badge+Vector2(0,7),str(_level),20,INK,40,3)
	for i in SKILLS.size():
		var state: Dictionary = _skill_state[i]
		var color: Color = SKILLS[i][2]
		var learned: bool = int(state.rank) > 0
		_slot(_rects[i],color if learned else BRASS_DIM,float(state.wait))
		var base: Vector2 = _rects[i].position+Vector2(0,_rects[i].size.y+7)
		if bool(state.evolved):
			draw_rect(Rect2(base+Vector2(6,0),Vector2(_rects[i].size.x-12,4)),BRASS_HI)
		else:
			for pip in 4:
				var lit: bool = pip < int(state.rank)
				draw_rect(Rect2(base+Vector2(7+float(pip)*12.5,0),Vector2(9,4)),color if lit else Color(1,1,1,.12))
	# Ultimate: reserved slot, shown locked until the ultimate system is connected.
	var ultimate: Rect2 = _rects[3]
	_slot(ultimate,BRASS_DIM,0.0)
	var c := ultimate.get_center()
	var diamond := PackedVector2Array([c+Vector2(0,-20),c+Vector2(20,0),c+Vector2(0,20),c+Vector2(-20,0),c+Vector2(0,-20)])
	draw_polyline(diamond,Color(BRASS,.45),2.0,true)
	draw_circle(c,5,Color(BRASS,.35))
	_draw_descent(c,36.0)
	# Dash.
	var dash: Rect2 = _rects[4]
	var dash_ready := _dash_left <= 0.0
	_slot(dash,BRASS if dash_ready else BRASS_DIM,clampf(_dash_left/maxf(.1,_dash_total),0,1))
	var d := dash.get_center()
	for step in 3:
		var x := d.x-14+float(step)*11
		draw_polyline(PackedVector2Array([Vector2(x,d.y-11),Vector2(x+9,d.y),Vector2(x,d.y+11)]),Color(INK,1.0 if dash_ready else .25),2.5,true)
	if not dash_ready: _text(Vector2(d.x,dash.end.y-14),"%.1f" % _dash_left,17,INK,60)
	_text(Vector2(d.x,dash.end.y+17),"Space",14,INK_DIM,70)
	# Potion.
	var potion: Rect2 = _rects[5]
	var urgent := low and _potions > 0 and _potion_left <= 0.0
	_slot(potion,Palette.LIFE_LOW.lerp(BRASS,1.0-pulse) if urgent else (BRASS if _potions > 0 else BRASS_DIM),clampf(_potion_left/4.0,0,1))
	var p := potion.get_center()
	var flask := PackedVector2Array([p+Vector2(-5,-18),p+Vector2(5,-18),p+Vector2(5,-8),p+Vector2(14,10),p+Vector2(9,18),p+Vector2(-9,18),p+Vector2(-14,10),p+Vector2(-5,-8)])
	draw_colored_polygon(flask,Color("b83f51") if _potions > 0 else Color(1,1,1,.12))
	draw_polyline(flask+PackedVector2Array([flask[0]]),Color(INK,.8),1.5,true)
	_text(Vector2(potion.end.x-11,potion.end.y-6),str(_potions),17,INK,30)
	_text(Vector2(p.x,potion.end.y+17),"Q",14,INK_DIM,70)
