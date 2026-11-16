extends Control
## Bottom-centre combat bar (layout A): life orb, skill slots, the reserved
## ultimate slot, dash and potion, soul orb. It only reads run state.
const ElementSeal = preload("res://chapter1/view/ui38/element_seal.gd")
const SKILLS := [["chapter1.skill.ember","ember",Color("ff943d")],["chapter1.skill.frost","frost",Color("9ce7ef")],["chapter1.skill.arc","arc",Color("b9caff")]]
const BRASS := Color("aa8d58")
const BRASS_DIM := Color("665343")
const PLATE := Color(.035,.045,.05,.92)
const SLOT := Color(.075,.095,.105,1)
const INK := Color("f2ebd8")
const BAR_SIZE := Vector2(860,160)
const LIFE_CENTER := Vector2(66,90)
const SOUL_CENTER := Vector2(794,90)
const ORB_RADIUS := 54.0
const SLOT_Y := 92.0
const SLOT_SIZES := [60,60,60,74,60,60]
const SLOT_GAP := 14.0
const LOW_LIFE := .30

var _seals: Array[Control] = []
var _rects: Array[Rect2] = []
var _life := 1.0
var _life_text := ""
var _soul := 0.0
const SOUL_DEFAULT := Color("9ce7ef")
var _soul_color := SOUL_DEFAULT
var _level := 1
var _skill_state: Array[Dictionary] = []
var _dash_left := 0.0
var _dash_total := 3.0
var _potions := 0
var _potion_left := 0.0
var _clock := 0.0
var _playing := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = BAR_SIZE
	anchor_left = .5; anchor_right = .5; anchor_top = 1.0; anchor_bottom = 1.0
	offset_left = -BAR_SIZE.x*.5; offset_right = BAR_SIZE.x*.5
	offset_top = -BAR_SIZE.y-10; offset_bottom = -10
	var total := 0.0
	for size_ in SLOT_SIZES: total += float(size_)
	total += SLOT_GAP*float(SLOT_SIZES.size()-1)
	var x := BAR_SIZE.x*.5-total*.5
	for size_ in SLOT_SIZES:
		_rects.append(Rect2(x,SLOT_Y-float(size_)*.5,float(size_),float(size_)))
		x += float(size_)+SLOT_GAP
	for index in SKILLS.size():
		var seal = ElementSeal.new()
		seal.element = SKILLS[index][1]; seal.tint = SKILLS[index][2]
		seal.size = Vector2(70,70)
		seal.position = _rects[index].get_center()-Vector2(35,35)
		add_child(seal)
		_seals.append(seal)
		_skill_state.append({"rank":0,"evolved":false,"wait":0.0})

func sync(run: RefCounted, delta: float) -> void:
	_playing = run.mode == "playing"
	if _playing: _clock += delta
	if run.hero.is_empty():
		visible = false; return
	visible = true
	_life = clampf(float(run.hero.hp_raw)/maxf(1.0,float(run.hero.max_hp_raw)),0,1)
	_life_text = "%d / %d" % [ceili(float(run.hero.hp_raw)/256.0),ceili(float(run.hero.max_hp_raw)/256.0)]
	var growth: Dictionary = run.growth.snapshot()
	_level = int(growth.level)
	var thresholds: Array = run.growth.xp_thresholds()
	var index := _level-1
	if index >= 0 and index < thresholds.size()-1:
		var span := float(thresholds[index+1])-float(thresholds[index])
		_soul = clampf((float(growth.xp)-float(thresholds[index]))/maxf(1.0,span),0,1)
	else: _soul = 1.0
	# The in-run growth orb carries the primary element's colour (ART-PLAN 2.1).
	_soul_color = SOUL_DEFAULT
	for skill in SKILLS:
		if skill[0] == String(growth.get("primary","")): _soul_color = skill[2]
	var ranks: Dictionary = growth.get("ranks",{})
	var evolved: Array = growth.get("evolved",[])
	for i in SKILLS.size():
		var id_: String = SKILLS[i][0]
		var rank := int(ranks.get(id_,0))
		var wait := 0.0
		if rank > 0:
			var next_cast: Dictionary = run.get("_next_cast")
			var skill: Dictionary = run.effective_skill(id_)
			var cooldown := maxf(1.0,float(skill.get("effects",{}).get("cooldown_ticks",60)))
			wait = clampf(float(int(next_cast.get(id_,0))-int(run.tick))/cooldown,0,1)
		_skill_state[i] = {"rank":rank,"evolved":id_ in evolved,"wait":wait}
		_seals[i].modulate = Color(1,1,1,1) if rank > 0 else Color(1,1,1,.22)
	_dash_left = maxf(0.0,float(int(run.get_next_dash_tick())-int(run.tick))/60.0)
	_dash_total = maxf(_dash_total if _dash_left > 0 else 1.0,_dash_left)
	_potions = int(run.get("potions"))
	_potion_left = maxf(0.0,float(int(run.get("_next_potion"))-int(run.tick))/60.0)
	queue_redraw()

func _text(at: Vector2, text: String, size_: int, color: Color, width: float = 120.0) -> void:
	var font := get_theme_default_font()
	draw_string_outline(font,at-Vector2(width*.5,0),text,HORIZONTAL_ALIGNMENT_CENTER,width,size_,4,Color(0,0,0,.85))
	draw_string(font,at-Vector2(width*.5,0),text,HORIZONTAL_ALIGNMENT_CENTER,width,size_,color)

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

func _draw() -> void:
	var first: Rect2 = _rects[0]
	var last: Rect2 = _rects[_rects.size()-1]
	var plate := Rect2(first.position.x-22,SLOT_Y-52,last.end.x-first.position.x+44,104)
	draw_rect(plate,PLATE)
	draw_rect(plate,BRASS_DIM,false,1.5)
	draw_line(plate.position+Vector2(8,0),Vector2(plate.end.x-8,plate.position.y),BRASS,2.0)
	# Life: the rim pulses once life is low, so the state is readable without the number.
	var low := _life < LOW_LIFE
	var pulse := .5+.5*sin(_clock*9.0)
	var life_rim := BRASS if not low else BRASS.lerp(Color("ff5a48"),pulse)
	_orb(LIFE_CENTER,_life,Color("d04a5c") if not low else Color("ff5a48").lerp(Color("d04a5c"),pulse),Color("571c2b"),life_rim)
	_text(LIFE_CENTER+Vector2(0,7),_life_text,19,INK,130)
	_orb(SOUL_CENTER,_soul,_soul_color,_soul_color.darkened(.72),BRASS)
	_text(SOUL_CENTER+Vector2(0,-4),"레벨",14,Color("d4cdbb"))
	_text(SOUL_CENTER+Vector2(0,18),str(_level),24,INK)
	for i in SKILLS.size():
		var state: Dictionary = _skill_state[i]
		var color: Color = SKILLS[i][2]
		var learned: bool = int(state.rank) > 0
		_slot(_rects[i],color if learned else BRASS_DIM,float(state.wait))
		var base: Vector2 = _rects[i].position+Vector2(0,_rects[i].size.y+7)
		if bool(state.evolved):
			draw_rect(Rect2(base+Vector2(6,0),Vector2(_rects[i].size.x-12,4)),Color("ffd27a"))
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
	# Dash.
	var dash: Rect2 = _rects[4]
	var dash_ready := _dash_left <= 0.0
	_slot(dash,BRASS if dash_ready else BRASS_DIM,clampf(_dash_left/maxf(.1,_dash_total),0,1))
	var d := dash.get_center()
	for step in 3:
		var x := d.x-14+float(step)*11
		draw_polyline(PackedVector2Array([Vector2(x,d.y-11),Vector2(x+9,d.y),Vector2(x,d.y+11)]),Color(INK,1.0 if dash_ready else .35),2.5,true)
	if not dash_ready: _text(d+Vector2(0,7),"%.1f" % _dash_left,17,INK,60)
	_text(Vector2(d.x,dash.end.y+17),"Space",13,Color("b9b2a1"),70)
	# Potion.
	var potion: Rect2 = _rects[5]
	var urgent := low and _potions > 0 and _potion_left <= 0.0
	_slot(potion,Color("ff5a48").lerp(BRASS,1.0-pulse) if urgent else (BRASS if _potions > 0 else BRASS_DIM),clampf(_potion_left/4.0,0,1))
	var p := potion.get_center()
	var flask := PackedVector2Array([p+Vector2(-5,-18),p+Vector2(5,-18),p+Vector2(5,-8),p+Vector2(14,10),p+Vector2(9,18),p+Vector2(-9,18),p+Vector2(-14,10),p+Vector2(-5,-8)])
	draw_colored_polygon(flask,Color("b83f51") if _potions > 0 else Color(1,1,1,.12))
	draw_polyline(flask+PackedVector2Array([flask[0]]),Color(INK,.8),1.5,true)
	_text(Vector2(potion.end.x-11,potion.end.y-6),str(_potions),17,INK,30)
	_text(Vector2(p.x,potion.end.y+17),"Q",13,Color("b9b2a1"),70)
