extends RefCounted
## Growth cards of a run with the spell composition on (A6-RS RS3). Called once per card by the HUD after the ordinary card is
## built, and only when run.run_spells_view().enabled is true: a run without the composition never gets here, so its cards stay
## exactly as they were. Reads the card fields, run_spells_view(), run.spells (the validated document) and
## run.growth.effective_skill(); it requests nothing and changes nothing of the core.
##
## What a card says: what the spell does, what changes from what to what (axis cards), how far the evolution is, and which
## pairs the card forms with the spells already owned. All text is Loc.t(key); all numbers come from the card / the document.
## The child order of the card column is not touched: 0 crest, 1 title, 2 kind line, 3 CardText scroll (its content is replaced
## by one box), 4 spacer, last the pick button.
const Palette=preload("res://chapter1/view/hud/palette.gd")
const Loc=preload("res://chapter1/view/loc.gd")
const SpellMark=preload("res://chapter1/view/hud/spell_mark.gd")
const BODY_SIZE := 17
const SMALL_SIZE := 15
const DOT_ON := "●"
const DOT_OFF := "○"
const UP := "▲"
const ARROW := "▶"
const DOWN := "▼"
## effect key -> [Loc key of the row, divisor, decimals, higher is better]
const AXIS_ROWS := [
	["damage_raw","hud.spell.axis.damage",256.0,0,true],
	["cooldown_ticks","hud.spell.axis.interval",60.0,2,false],
	["ring_radius_cm","hud.spell.axis.radius",100.0,1,true],
	["projectiles","hud.spell.axis.projectiles",1.0,0,true],
	["pierce","hud.spell.axis.pierce",1.0,0,true],
	["chain_targets","hud.spell.axis.targets",1.0,0,true],
	["ring_targets","hud.spell.axis.targets",1.0,0,true],
	["radius_cm","hud.spell.axis.blast",100.0,1,true],
	["branches","hud.spell.axis.branches",1.0,0,true],
]

static func dress(hud: Object,panel: Control,card: Dictionary,run: RefCounted,view: Dictionary) -> void:
	var doc: Dictionary=run.spells
	var skill_id := String(card.get("skill_id",""))
	if skill_id=="" or not doc.get("spells",{}).has(skill_id):return
	var spell: Dictionary=doc.spells[skill_id]
	var element := String(spell.element)
	var is_ring := String(spell.role)=="ring"
	var tint := Palette.element_text_color(element)
	var column := panel.get_child(0) as VBoxContainer
	var kind := String(card.get("kind",""))
	# Frame, crest and the kind line follow the spell's element (the ordinary card cuts the element out of the id).
	var frame: StyleBoxFlat=hud._style(Palette.SURFACE_RAISED,tint.darkened(.35));frame.border_width_top=4
	panel.add_theme_stylebox_override("panel",frame)
	var crest := column.get_child(0)
	crest.element=element;crest.tint=tint;crest.queue_redraw()
	# A little less crest and gap, so the lines of a spell card have room (the pick button stays where it was).
	crest.custom_minimum_size=Vector2(58,58)
	column.add_theme_constant_override("separation",6)
	if is_ring:
		var halo := Control.new();halo.mouse_filter=Control.MOUSE_FILTER_IGNORE;halo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		halo.draw.connect(func():SpellMark.draw_dashes(halo,halo.size/2,34.0,tint,2.5,16))
		crest.add_child(halo)
	(column.get_child(1) as Label).text=Loc.t(String(card.title_key))
	var kind_label := column.get_child(2) as Label
	var kind_key := _kind_key(kind,card,spell)
	if kind_key!="":kind_label.text=Loc.t(kind_key)
	kind_label.add_theme_color_override("font_color",tint)
	# The body: the ordinary description label is kept (rewritten) and the rows go under it in one box.
	var scroll := column.get_child(3) as ScrollContainer
	var description := scroll.get_child(0) as Label
	scroll.remove_child(description)
	var body := VBoxContainer.new();body.name="SpellCardBody";body.add_theme_constant_override("separation",5)
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var current: Dictionary=run.growth.effective_skill(skill_id).get("effects",{})
	var after: Dictionary=card.get("after",{})
	var info: Dictionary=view.get("spells",{}).get(skill_id,{})
	var evo: Dictionary=info.get("evolve_progress",{})
	match kind:
		"unlock":
			if is_ring:
				description.text=Loc.t("hud.spell.ring.role."+element)
				body.add_child(description)
				_ring_rows(hud,body,after,tint)
			else:
				body.add_child(description)
		"axis":
			description.queue_free()
			_axis_rows(hud,body,card,current,after,doc,info,is_ring)
			if not evo.is_empty():body.add_child(_evolve_line(hud,evo,card,doc))
		"passive":
			var evolve: Dictionary=doc.evolve
			description.text=Loc.t("hud.spell.passive.body",{"axis":Loc.num(int(evolve.axis_sum)),"partner":Loc.num(int(evolve.partner_axis_sum))})
			body.add_child(description)
			if not evo.is_empty():body.add_child(_evolve_line(hud,evo,card,doc))
		"evolve":
			# The ordinary text opens with the old rule (rank and prerequisite passive); the effect lines after it stay.
			var lines: PackedStringArray=description.text.split("\n")
			if lines.size()>1:lines.remove_at(0)
			description.text="\n".join(lines)
			_partner_rows(hud,body,card,doc)
			body.add_child(description)
		_:
			body.add_child(description)
	# An evolution card names its partner above; the other links of the spell are on its earlier cards.
	if kind!="evolve":_pair_rows(hud,body,card,doc,view,kind=="unlock")

static func _kind_key(kind: String,card: Dictionary,spell: Dictionary) -> String:
	var ring := String(spell.role)=="ring"
	match kind:
		"unlock":return "hud.spell.kind.ring" if ring else "hud.spell.kind.borrow"
		"axis":return "hud.spell.kind.%s_%s"%["ring" if ring else "basic",String(card.get("axis","damage"))]
	return ""

# ---------------------------------------------------------------- ring unlock

static func _ring_rows(hud: Object,body: Control,e: Dictionary,tint: Color) -> void:
	body.add_child(hud._label(Loc.t("hud.spell.ring.stats",{"r":Loc.dec(float(e.get("ring_radius_cm",0))/100.0,1),
		"t":Loc.dec(float(e.get("cooldown_ticks",0))/60.0,2),"d":Loc.num(int(e.get("damage_raw",0))/256)}),BODY_SIZE,Palette.INK))
	var parts: Array[String]=[]
	if int(e.get("stagger_ticks",0))>0:
		parts.append(Loc.t("hud.spell.ring.stagger",{"t":Loc.dec(float(e.stagger_ticks)/60.0,1)}))
		parts.append(Loc.t("hud.spell.ring.cut"))
	if int(e.get("freeze_ticks",0))>0:
		parts.append(Loc.t("hud.spell.ring.freeze",{"t":Loc.dec(float(e.freeze_ticks)/60.0,1)}))
		if int(e.get("slow_bps",0))>0:parts.append(Loc.t("hud.spell.ring.slow",{"p":Loc.num(int(e.slow_bps)/100)}))
	if int(e.get("stun_ticks",0))>0:
		parts.append(Loc.t("hud.spell.ring.stun",{"t":Loc.dec(float(e.stun_ticks)/60.0,1)}))
		if int(e.get("ring_targets",0))>0:parts.append(Loc.t("hud.spell.ring.targets",{"n":Loc.num(int(e.ring_targets))}))
	if not parts.is_empty():body.add_child(hud._label(" · ".join(parts),BODY_SIZE,tint))
	if int(e.get("strong_pct_bps",0))>0:
		body.add_child(hud._label(Loc.t("hud.spell.ring.strong",{"p":Loc.num(int(e.strong_pct_bps)/100)}),BODY_SIZE,Palette.INK))
	body.add_child(hud._label(Loc.t("hud.spell.ring.limit"),SMALL_SIZE,Palette.INK_DIM))

# ---------------------------------------------------------------- axis

static func _axis_rows(hud: Object,body: Control,card: Dictionary,before: Dictionary,after: Dictionary,doc: Dictionary,info: Dictionary,is_ring: bool) -> void:
	var shown := 0
	for row in AXIS_ROWS:
		var key: String=row[0]
		if not before.has(key) or not after.has(key) or int(before[key])==int(after[key]):continue
		var higher_is_better: bool=row[4]
		var better := (int(after[key])>int(before[key]))==higher_is_better
		var text := Loc.t(String(row[1]),{"a":_number(float(before[key])/float(row[2]),int(row[3])),"b":_number(float(after[key])/float(row[2]),int(row[3]))})
		body.add_child(hud._label(text+" "+(UP if better else DOWN),BODY_SIZE,Palette.INK))
		shown+=1
	if shown==0:body.add_child(hud._label(Loc.t("hud.spell.axis.nothing"),BODY_SIZE,Palette.INK_DIM))
	var levels: Dictionary=info.get("axis",{"damage":0,"reach":0}).duplicate()
	levels[String(card.get("axis","damage"))]=int(card.get("level",0))
	var cap := int(doc.axis.cap_per_axis)
	var suffix := "ring" if is_ring else "basic"
	body.add_child(hud._label(Loc.t("hud.spell.axis.dots",{"d":Loc.t("hud.spell.axis.damage_"+suffix),"dd":_dots(int(levels.damage),cap),
		"r":Loc.t("hud.spell.axis.reach_"+suffix),"rd":_dots(int(levels.reach),cap)}),SMALL_SIZE,Palette.INK_DIM))

static func _dots(level: int,cap: int) -> String:
	var out := ""
	for i in cap:out+=DOT_ON if i<level else DOT_OFF
	return out

static func _number(value: float,decimals: int) -> String:
	return Loc.dec(value,decimals) if decimals>0 else Loc.num(int(roundf(value)))

# ---------------------------------------------------------------- evolution

## "Evolution in: axis 3 -> 4/5 - passive - partner 1/2". A card changes the part it gives; the others are shown as they stand.
static func _evolve_line(hud: Object,evo: Dictionary,card: Dictionary,doc: Dictionary) -> Label:
	var parts: Array[String]=[]
	var have := int(evo.axis.have);var need := int(evo.axis.need)
	if String(card.kind)=="axis" and have<need:
		parts.append(Loc.t("hud.spell.evo.axis_to",{"have":Loc.num(have),"next":Loc.num(have+1),"need":Loc.num(need)}))
	else:
		parts.append(Loc.t("hud.spell.evo.axis",{"have":Loc.num(have),"need":Loc.num(need)}))
	if bool(evo.passive.need):
		var owned := bool(evo.passive.have)
		if String(card.kind)=="passive" and not owned:parts.append(Loc.t("hud.spell.evo.passive_to"))
		else:parts.append(Loc.t("hud.spell.evo.passive",{"mark":"✓" if owned else "✗"}))
	parts.append(Loc.t("hud.spell.evo.partner",{"have":Loc.num(int(evo.partner.have)),"need":Loc.num(int(evo.partner.need))}))
	return hud._label(Loc.t("hud.spell.evo.line",{"parts":" · ".join(parts)}),SMALL_SIZE,Palette.LINEN)

static func _partner_rows(hud: Object,body: Control,card: Dictionary,doc: Dictionary) -> void:
	var partner := String(card.get("partner_skill",""))
	if partner=="" or not doc.spells.has(partner):return
	var row := HBoxContainer.new();row.add_theme_constant_override("separation",8)
	row.add_child(_mark(doc,partner))
	var text: Label = hud._label(Loc.t("hud.spell.evolve.partner",{"name":Loc.t("skill.%s.name"%partner)}),BODY_SIZE,Palette.INK)
	text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(text)
	body.add_child(row)
	var pair := _pair(doc,String(card.get("partner_pair","")))
	if String(pair.get("kind",""))=="detonate":
		body.add_child(hud._label(Loc.t("hud.spell.evolve.boost",{"x":Loc.dec(float(doc.evolve.partner_detonate_bps)/10000.0,1)}),SMALL_SIZE,Palette.LINEN))

# ---------------------------------------------------------------- pairs

static func _pair(doc: Dictionary,pair_id: String) -> Dictionary:
	for pair in doc.pairs:
		if String(pair.id)==pair_id:return pair
	return {}

static func _mark(doc: Dictionary,skill_id: String) -> Control:
	var mark := SpellMark.new()
	mark.element=String(doc.spells[skill_id].element);mark.ring=String(doc.spells[skill_id].role)=="ring"
	mark.slot_id=SpellMark.slot_for(skill_id)
	return mark

## The interlock pair between the same two spells as a detonation pair (a ring and the basic spell of its element form both).
static func _twin(doc: Dictionary,pair: Dictionary) -> Dictionary:
	if String(pair.kind)!="detonate":return {}
	for other in doc.pairs:
		if String(other.kind)=="interlock" and ((other.a==pair.a and other.b==pair.b) or (other.a==pair.b and other.b==pair.a)):return other
	return {}

static func _pair_rows(hud: Object,body: Control,card: Dictionary,doc: Dictionary,view: Dictionary,opens: bool) -> void:
	var offered: Dictionary=view.get("offer",{}).get(String(card.id),{})
	if offered.is_empty():return
	var shown: Array[Dictionary]=[]
	for pair_id in offered.get("pairs_if_taken",[]):
		var pair := _pair(doc,String(pair_id))
		if pair.is_empty() or String(pair.kind)=="reaction":continue
		shown.append(pair)
		var twin := _twin(doc,pair)
		if not twin.is_empty():shown.append(twin)
	body.add_child(hud._label(Loc.t("hud.spell.pair.title_new" if opens else "hud.spell.pair.title"),SMALL_SIZE,Palette.LINEN))
	if shown.is_empty():
		body.add_child(hud._label(Loc.t("hud.spell.pair.none"),SMALL_SIZE,Palette.INK_FAINT))
		return
	for pair in shown.slice(0,3):
		var row := HBoxContainer.new();row.add_theme_constant_override("separation",6)
		row.add_child(_mark(doc,String(pair.a)))
		var arrow: Label = hud._label(ARROW,SMALL_SIZE,Palette.LINEN);arrow.autowrap_mode=TextServer.AUTOWRAP_OFF;row.add_child(arrow)
		row.add_child(_mark(doc,String(pair.b)))
		var text: Label = hud._label(_pair_text(doc,pair),SMALL_SIZE+1,Palette.INK)
		text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;text.custom_minimum_size.x=120
		row.add_child(text)
		body.add_child(row)
	if shown.size()>3:body.add_child(hud._label(Loc.t("hud.spell.pair.more",{"n":Loc.num(shown.size()-3)}),SMALL_SIZE,Palette.INK_FAINT))

static func _short(doc: Dictionary,skill_id: String) -> String:
	if String(doc.spells[skill_id].role)=="ring":return Loc.t("hud.spell.pair.ring_short")
	return Loc.t("skill.%s.name"%skill_id)

static func _pair_text(doc: Dictionary,pair: Dictionary) -> String:
	var b := Loc.t("skill.%s.name"%pair.b)
	if String(pair.kind)=="detonate":
		var ring: Dictionary=doc.spells[pair.b]
		var rule: Dictionary=ring.detonates.get(String(pair.status),{})
		var text := Loc.t("hud.spell.pair.detonate",{"status":Loc.t("hud.spell.status."+String(pair.status)),"n":Loc.num(int(rule.get("bonus_bps",0))/100)})
		if int(rule.get("block_bps",10000))!=10000:
			text+=Loc.t("hud.spell.pair.block",{"ctl":Loc.t("hud.spell.ctl."+String(ring.element)),"x":Loc.dec(float(rule.block_bps)/10000.0,1)})
		if int(rule.get("block_targets",0))>0:text+=Loc.t("hud.spell.pair.block_targets",{"n":Loc.num(int(rule.block_targets))})
		return text
	# interlock: a controls, b hits the controlled enemy harder; every control of the pair is told, the larger bonus first
	var table: Dictionary=doc.spells[pair.b].get("vs_cc",{})
	var vias: Array=pair.via.duplicate()
	vias.sort_custom(func(x,y): return int(table.get(String(x),0))>int(table.get(String(y),0)))
	var text := Loc.t("hud.spell.pair.interlock",{"a":_short(doc,String(pair.a)),"b":b,"verb":Loc.t("hud.spell.verb."+String(vias[0])),"n":Loc.num(int(table.get(String(vias[0]),0))/100)})
	for i in range(1,vias.size()):
		text+=Loc.t("hud.spell.pair.second",{"verb":Loc.t("hud.spell.verb."+String(vias[i])),"n":Loc.num(int(table.get(String(vias[i]),0))/100)})
	return text
