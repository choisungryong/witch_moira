extends VBoxContainer
## Battle record screen body (W7 / A6-11, D11 F1 and F3). Presentation only: it reads the finished run's record
## (`run_record_view` of the app) and draws it. It changes nothing in the core and keeps no state of its own.
## The HUD puts this inside a FlowDialog ("record"), so the close button, Esc and focus return are the dialog's.
##
## Rules this screen keeps:
##  - A zone with no data is not drawn (pairs, beats, picks, the loss box on a win).
##  - The damage share bars are rounded by largest remainder to 0.1 percent, so the shown shares add up to 100.0.
##  - A defeat box reads the keys of `loss.by_source` as they come; a kind this file does not know is drawn under its own id.
##    What the recorder could not attribute is shown as "unknown" and never folded into another kind.
##  - No meaning rests on colour alone: icons differ in form, the unknown row is outlined and marked "?", the evolved mark is a diamond.
const Palette=preload("res://chapter1/view/hud/palette.gd")
const UiStyle=preload("res://chapter1/view/hud/ui_style.gd")
const Loc=preload("res://chapter1/view/loc.gd")

const HZ := 60
const MAX_PICKS := 32
const MAX_PAIRS := 6
const MAX_BEATS := 8
const SOURCE_UNKNOWN := "unattributed"
const ICON_PIECES := {"ember":"icon_fire","frost":"icon_frost","arc":"icon_arc"}
const SMALL := 15
const BODY := 17

## Skill icon: the atlas piece of the element, in a ring. A skill without a piece gets a diamond.
class SkillIcon extends Control:
	var piece := ""
	var tint := Palette.BRASS
	func _init(piece_: String,tint_: Color) -> void:
		piece=piece_;tint=tint_
		custom_minimum_size=Vector2(38,38);mouse_filter=Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal=Control.SIZE_SHRINK_BEGIN;size_flags_vertical=Control.SIZE_SHRINK_CENTER
		texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	func _draw() -> void:
		var c := size*.5
		draw_arc(c,minf(size.x,size.y)*.5-1.0,0.0,TAU,40,tint,2.0,true)
		if piece.is_empty():
			var r := minf(size.x,size.y)*.26
			draw_colored_polygon(PackedVector2Array([c+Vector2(0,-r),c+Vector2(r,0),c+Vector2(0,r),c+Vector2(-r,0)]),tint)
		else:
			UiStyle.blit(self,piece,Rect2(Vector2(5,5),size-Vector2(10,10)))

## The living-enemy count (solid line over a light area) and the hero life (dotted line) over the last seconds before the end.
class Trend extends Control:
	var samples: Array=[]
	var window_ticks := 1800
	var peak := 1
	func _init(samples_: Array,window_: int,peak_: int) -> void:
		samples=samples_;window_ticks=maxi(1,window_);peak=maxi(1,peak_)
		custom_minimum_size=Vector2(300,84);mouse_filter=Control.MOUSE_FILTER_IGNORE
	func _point(sample: Dictionary,value: float) -> Vector2:
		var x := (1.0-float(sample.ticks_before_end)/float(window_ticks))*size.x
		return Vector2(clampf(x,0.0,size.x),size.y-1.0-clampf(value,0.0,1.0)*(size.y-4.0))
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,size),Color(0,0,0,.28))
		draw_rect(Rect2(Vector2.ZERO,size),Palette.BRASS_DIM,false,1.0)
		if samples.size()<2:return
		var line := PackedVector2Array();var area := PackedVector2Array()
		for sample in samples:
			line.append(_point(sample,float(sample.alive)/float(peak)))
		area.append(Vector2(line[0].x,size.y-1.0))
		area.append_array(line)
		area.append(Vector2(line[line.size()-1].x,size.y-1.0))
		draw_colored_polygon(area,Color(Palette.THREAT,.22))
		draw_polyline(line,Palette.THREAT,2.0,true)
		for i in range(samples.size()-1):
			var a := _point(samples[i],float(samples[i].hp_bps)/10000.0)
			var b := _point(samples[i+1],float(samples[i+1].hp_bps)/10000.0)
			if i%2==0:draw_line(a,b,Palette.LINEN,2.0,true)

# ---- building ----

## `view` is the app's run_record_view; `level` the run's level (the record does not carry it; 0 hides the cell).
func setup(view: Dictionary,level: int,width: float) -> void:
	name="CombatRecordView"
	add_theme_constant_override("separation",14)
	custom_minimum_size.x=width
	var record: Dictionary=view.get("record",{})
	add_child(_summary(view,record,level))
	var loss: Dictionary=view.get("loss",{})
	var body := HBoxContainer.new();body.name="RecordBody";body.add_theme_constant_override("separation",18);add_child(body)
	var skills := _skills(view)
	skills.size_flags_horizontal=Control.SIZE_EXPAND_FILL;skills.size_flags_vertical=Control.SIZE_SHRINK_BEGIN;body.add_child(skills)
	if not loss.is_empty():
		var box := _loss(loss);box.size_flags_vertical=Control.SIZE_SHRINK_BEGIN;body.add_child(box)
	var pairs: Array=view.get("pairs",[]);var beats: Array=view.get("beats",[])
	if not pairs.is_empty() or not beats.is_empty():
		var extra := HBoxContainer.new();extra.name="RecordExtra";extra.add_theme_constant_override("separation",18);add_child(extra)
		if not pairs.is_empty():
			var column := _pairs(pairs);column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;extra.add_child(column)
		if not beats.is_empty():
			var column := _beats(beats);column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;extra.add_child(column)
	var picks: Array=view.get("picks",[])
	if not picks.is_empty():add_child(_picks(picks))

func _label(text: String,size: int=BODY,color: Color=Palette.INK) -> Label:
	return UiStyle.label(text,size,color)

## One line that is cut with an ellipsis when it does not fit (the full text stays in the tooltip).
func _line(text: String,size: int=BODY,color: Color=Palette.INK) -> Label:
	var l := _label(text,size,color)
	l.autowrap_mode=TextServer.AUTOWRAP_OFF;l.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text=true;l.tooltip_text=text;l.custom_minimum_size.x=24
	return l

## A name that may be long: it wraps (anywhere, an id has no spaces) instead of being cut.
func _wrap(text: String,size: int=BODY,color: Color=Palette.INK) -> Label:
	var l := _label(text,size,color)
	l.autowrap_mode=TextServer.AUTOWRAP_ARBITRARY;l.custom_minimum_size.x=24
	return l

func _num_label(text: String,size: int=BODY,color: Color=Palette.INK) -> Label:
	var l := _label(text,size,color)
	l.autowrap_mode=TextServer.AUTOWRAP_OFF;l.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	return l

func _card(border: Color=Palette.BRASS_DIM,margin: int=10) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := UiStyle.flat(Palette.SURFACE_RAISED,border)
	style.set_content_margin_all(margin);style.shadow_size=0
	panel.add_theme_stylebox_override("panel",style)
	return panel

func _section_title(text: String) -> Label:
	return _label(text,20,Palette.GROWTH)

static func clock(ticks: int) -> String:
	var seconds := maxi(0,ticks)/HZ
	return "%02d:%02d"%[seconds/60,seconds%60]

static func percent(permille: int) -> String:
	return Loc.dec(float(permille)/10.0,1)+"%"

## Names: a skill by its id, a pick by its card id. Anything this file does not know is shown as its own id, never hidden.
static func skill_name(id_: String,evolved: bool=false) -> String:
	var key := "skill.%s.%s"%[id_,"evolved_name" if evolved else "name"]
	var text := Loc.t(key)
	return id_.get_slice(".",id_.get_slice_count(".")-1) if text==key else text

## The element kit's skills carry their element in the id's first word ("arc_rod"); the other ids end in the element itself ("arc").
const KIT_SKILL_ELEMENT := {"arc_rod":"arc","arc_overload":"arc","arc_storm":"arc"}
static func element_of(id_: String) -> String:
	var last := id_.get_slice(".",id_.get_slice_count(".")-1)
	return String(KIT_SKILL_ELEMENT.get(last,last))

static func pick_text(card: String) -> String:
	var kind := card.get_slice(":",0)
	match kind:
		"unlock":return Loc.t("record.pick.unlock",{"skill":skill_name(card.get_slice(":",1))})
		"rank":return Loc.t("record.pick.rank",{"skill":skill_name(card.get_slice(":",1)),"n":Loc.num(int(card.get_slice(":",2)))})
		"axis":
			var axis := card.get_slice(":",2)
			return Loc.t("record.pick.axis_reach" if axis=="reach" else "record.pick.axis_damage",{"skill":skill_name(card.get_slice(":",1))})
		"evolve":return Loc.t("record.pick.evolve",{"skill":skill_name(card.get_slice(":",1),true)})
		"passive":
			var key := "grace.passive.%s.name"%card.get_slice(":",1)
			var text := Loc.t(key)
			return card if text==key else text
	# An element kit card is picked by its own id ("A12"): its name is `kit.card.<id>`; an id without a text is shown as the id (never hidden).
	var kit_key := "kit.card."+card
	var kit_text := Loc.t(kit_key)
	return card if kit_text==kit_key else kit_text

static func source_name(kind: String) -> String:
	var key := "record.source."+kind
	var text := Loc.t(key)
	return kind if text==key else text

## Largest-remainder rounding of the damage shares to 0.1 percent: the shown numbers add up to exactly 100.0.
static func permilles(damages: Array) -> Array[int]:
	var total := 0
	for value in damages:total+=int(value)
	var out: Array[int]=[]
	if total<=0:
		for _i in damages.size():out.append(0)
		return out
	var rest: Array=[];var used := 0
	for i in damages.size():
		var exact := int(damages[i])*1000
		out.append(exact/total);used+=exact/total
		rest.append([exact%total,i])
	rest.sort_custom(func(a,b): return a[0]>b[0] or (a[0]==b[0] and a[1]<b[1]))
	for k in range(1000-used):out[int(rest[k%rest.size()][1])]+=1
	return out

func _summary(view: Dictionary,record: Dictionary,level: int) -> Control:
	var row := HBoxContainer.new();row.name="RecordSummary";row.add_theme_constant_override("separation",10)
	var outcome_key := "record.outcome.abandoned" if bool(view.get("abandoned",false)) else ("record.outcome.victory" if bool(record.get("victory",false)) else "record.outcome.defeat")
	var champions := int(record.get("champion_kills",0))+(1 if bool(record.get("boss_kill",false)) else 0)
	var cells: Array=[
		["record.stat.result",Loc.t(outcome_key)],
		["record.stat.time",clock(int(record.get("ticks",0)))],
		["record.stat.kills",Loc.num(int(record.get("kills",0)))],
		["record.stat.champions",Loc.num(champions)],
		["record.stat.damage",Loc.num(int(view.get("total_damage",0)))],
		["record.stat.taken",Loc.num(int(record.get("damage_taken",0)))],
		["record.stat.potions",Loc.num(int(record.get("potions_used",0)))]]
	if level>0:cells.append(["record.stat.level",Loc.num(level)])
	for cell in cells:
		var card := _card();card.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(card)
		var column := VBoxContainer.new();column.add_theme_constant_override("separation",2);card.add_child(column)
		var value := _label(String(cell[1]),26,Palette.INK);value.autowrap_mode=TextServer.AUTOWRAP_OFF;value.add_theme_font_override("font",Loc.font("heading"));column.add_child(value)
		column.add_child(_line(Loc.t(String(cell[0])),SMALL,Palette.INK_DIM))
	return row

func _skills(view: Dictionary) -> Control:
	var column := VBoxContainer.new();column.name="RecordSkills";column.add_theme_constant_override("separation",8)
	column.add_child(_section_title(Loc.t("record.skills.title")))
	var rows: Array=view.get("skills",[]).duplicate(true)
	rows.sort_custom(func(a,b): return int(a.damage)>int(b.damage))
	if rows.is_empty():
		column.add_child(_label(Loc.t("record.skills.empty"),BODY,Palette.INK_DIM));return column
	var grid := GridContainer.new();grid.columns=6;grid.add_theme_constant_override("h_separation",12);grid.add_theme_constant_override("v_separation",6);column.add_child(grid)
	var heads := ["record.skills.name","record.skills.got","record.skills.share","record.skills.damage","record.skills.dps","record.skills.kills"]
	for i in heads.size():
		var head := _label(Loc.t(String(heads[i])),SMALL,Palette.INK_DIM);head.autowrap_mode=TextServer.AUTOWRAP_OFF
		if i>=3:head.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
		if i==0:head.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if i==2:head.custom_minimum_size.x=200;head.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		grid.add_child(head)
	var damages: Array=[]
	for row in rows:damages.append(int(row.damage))
	var shares := permilles(damages)
	var total_damage := 0;var total_kills := 0;var total_dps := 0
	for i in rows.size():
		var row: Dictionary=rows[i]
		var id_ := String(row.id);var element := element_of(id_)
		var evolved := bool(row.get("evolved",false))
		var tint := Palette.element_text_color(element,Palette.BRASS)
		var name_box := HBoxContainer.new();name_box.add_theme_constant_override("separation",10);name_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;name_box.custom_minimum_size.x=150
		name_box.add_child(SkillIcon.new(String(ICON_PIECES.get(element,"")),Palette.element_color(element,Palette.BRASS)))
		var texts := VBoxContainer.new();texts.add_theme_constant_override("separation",0);texts.size_flags_horizontal=Control.SIZE_EXPAND_FILL;texts.size_flags_vertical=Control.SIZE_SHRINK_CENTER;name_box.add_child(texts)
		texts.add_child(_wrap(skill_name(id_,evolved),BODY+1,tint))
		var sub := HBoxContainer.new();sub.add_theme_constant_override("separation",10);texts.add_child(sub)
		if int(row.get("rank",0))>0:
			var rank := _label(Loc.t("record.skills.rank",{"n":Loc.num(int(row.rank))}),SMALL,Palette.INK_DIM);rank.autowrap_mode=TextServer.AUTOWRAP_OFF;sub.add_child(rank)
		if evolved:
			var mark := _label(Loc.t("record.skills.evolved"),SMALL,Palette.GROWTH);mark.autowrap_mode=TextServer.AUTOWRAP_OFF;sub.add_child(mark)
		if sub.get_child_count()==0:sub.add_child(_label(" ",SMALL))
		grid.add_child(name_box)
		grid.add_child(_num_label(Loc.t("record.skills.got_at",{"time":clock(int(row.got_tick)),"level":Loc.num(int(row.got_level))}),SMALL,Palette.INK_DIM))
		var share_box := HBoxContainer.new();share_box.add_theme_constant_override("separation",8);share_box.custom_minimum_size.x=200;share_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var bar := UiStyle.bar(Palette.element_color(element,Palette.BRASS),16);bar.max_value=1000;bar.value=shares[i]
		bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL;bar.size_flags_vertical=Control.SIZE_SHRINK_CENTER;bar.custom_minimum_size.x=110
		bar.tooltip_text=percent(shares[i]);share_box.add_child(bar)
		var pct := _num_label(percent(shares[i]),BODY,Palette.INK);pct.custom_minimum_size.x=64;share_box.add_child(pct)
		grid.add_child(share_box)
		grid.add_child(_num_label(Loc.num(int(row.damage))))
		var dps := int(row.get("dps_tenths",0))
		grid.add_child(_num_label(Loc.dec(float(dps)/10.0,1)))
		grid.add_child(_num_label(Loc.num(int(row.kills))))
		total_damage+=int(row.damage);total_kills+=int(row.kills);total_dps+=dps
	for i in grid.columns:
		grid.add_child(HSeparator.new())
	grid.add_child(_line(Loc.t("record.skills.total"),BODY,Palette.INK_DIM))
	grid.add_child(Control.new())
	grid.add_child(_num_label(percent(1000 if total_damage>0 else 0),BODY,Palette.INK_DIM))
	grid.add_child(_num_label(Loc.num(total_damage)))
	grid.add_child(_num_label(Loc.dec(float(total_dps)/10.0,1)))
	grid.add_child(_num_label(Loc.num(total_kills)))
	return column

func _loss(loss: Dictionary) -> Control:
	var box := _card(Palette.THREAT_DEEP,12);box.name="RecordLoss";box.custom_minimum_size.x=440
	var column := VBoxContainer.new();column.add_theme_constant_override("separation",7);box.add_child(column)
	var window_ticks := int(loss.get("window_ticks",1800))
	column.add_child(_label(Loc.t("record.loss.title",{"n":Loc.num(window_ticks/HZ)}),20,Palette.WARN))
	var hits := int(loss.get("hits",0));var taken := int(loss.get("taken",0))
	if hits<=0:
		column.add_child(_label(Loc.t("record.loss.none"),BODY,Palette.INK_DIM))
	else:
		column.add_child(_label(Loc.t("record.loss.taken",{"life":Loc.num(taken),"hits":Loc.num(hits)}),BODY,Palette.INK))
		var by_source: Dictionary=loss.get("by_source",{})
		var kinds: Array=by_source.keys()
		kinds.sort_custom(func(a,b):
			if a==SOURCE_UNKNOWN or b==SOURCE_UNKNOWN:return b==SOURCE_UNKNOWN and a!=SOURCE_UNKNOWN
			return int(by_source[a].life)>int(by_source[b].life) or (int(by_source[a].life)==int(by_source[b].life) and String(a)<String(b)))
		var lives: Array=[]
		for kind in kinds:lives.append(int(by_source[kind].life))
		var shares := permilles(lives)
		var grid := GridContainer.new();grid.columns=3;grid.add_theme_constant_override("h_separation",10);grid.add_theme_constant_override("v_separation",5);column.add_child(grid)
		var unknown_hits := 0
		for i in kinds.size():
			var kind := String(kinds[i]);var entry: Dictionary=by_source[kind];var unknown := kind==SOURCE_UNKNOWN
			if unknown:unknown_hits=int(entry.hits)
			var label := _wrap(("? " if unknown else "")+(Loc.t("record.loss.unknown") if unknown else source_name(kind)),BODY,Palette.INK_FAINT if unknown else Palette.INK)
			label.custom_minimum_size.x=130;grid.add_child(label)
			var bar := UiStyle.bar(Palette.INK_FAINT if unknown else Palette.THREAT,14);bar.max_value=1000;bar.value=shares[i]
			bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL;bar.size_flags_vertical=Control.SIZE_SHRINK_CENTER;bar.custom_minimum_size.x=90
			if unknown:
				# The unknown share is outlined, so it cannot be read as one more kind of attacker.
				var fill := UiStyle.flat(Color(Palette.INK_FAINT,.35),Palette.INK_FAINT);fill.set_content_margin_all(0);fill.shadow_size=0
				bar.add_theme_stylebox_override("fill",fill)
			bar.tooltip_text=percent(shares[i]);grid.add_child(bar)
			grid.add_child(_num_label(Loc.t("record.loss.row",{"life":Loc.num(int(entry.life)),"hits":Loc.num(int(entry.hits))}),SMALL,Palette.INK_DIM))
		var known := hits-unknown_hits
		column.add_child(_label(Loc.t("record.loss.known",{"known":Loc.num(known),"hits":Loc.num(hits)}),SMALL,Palette.INK_DIM))
	var trend: Array=loss.get("alive_trend",[])
	if trend.size()>=2:
		var ordered: Array=trend.duplicate();ordered.sort_custom(func(a,b): return int(a.ticks_before_end)>int(b.ticks_before_end))
		var peak := int(loss.get("alive_peak",0))
		column.add_child(_label(Loc.t("record.loss.alive",{"peak":Loc.num(peak)}),BODY,Palette.INK))
		column.add_child(Trend.new(ordered,window_ticks,peak))
		var axis := HBoxContainer.new();column.add_child(axis)
		var left := _label(Loc.t("record.loss.axis_start",{"n":Loc.num(window_ticks/HZ)}),SMALL,Palette.INK_DIM);left.autowrap_mode=TextServer.AUTOWRAP_OFF;left.size_flags_horizontal=Control.SIZE_EXPAND_FILL;axis.add_child(left)
		var right := _label(Loc.t("record.loss.axis_end"),SMALL,Palette.INK_DIM);right.autowrap_mode=TextServer.AUTOWRAP_OFF;axis.add_child(right)
		var first: Dictionary=ordered[0];var last: Dictionary=ordered[ordered.size()-1]
		column.add_child(_label(Loc.t("record.loss.legend",{"from":Loc.num(int(first.hp_bps)/100),"to":Loc.num(int(last.hp_bps)/100)}),SMALL,Palette.INK_DIM))
	var last_hit: Dictionary=loss.get("last_hit",{})
	if not last_hit.is_empty():
		column.add_child(_label(Loc.t("record.loss.last",{"source":_loss_name(last_hit),"life":Loc.num(int(last_hit.get("life",0))),"sec":Loc.dec(float(last_hit.get("ticks_before_end",0))/float(HZ),1)}),BODY,Palette.INK))
	for line in death_lines(loss).slice(1):column.add_child(_wrap(line,BODY,Palette.INK))
	return box

static func _loss_source(kind: String) -> String:
	return Loc.t("record.loss.unknown") if kind==SOURCE_UNKNOWN else source_name(kind)

## T15c: the name of a source for a line. A guardian or a boss has its own name (the core's source_key); its attack gets a name too.
## An ordinary body keeps its kind name, and its attack is not named (every walker would read "circle").
static func _loss_name(hit: Dictionary) -> String:
	var key := String(hit.get("key",""))
	var kind := String(hit.get("source",SOURCE_UNKNOWN))
	var attack := String(hit.get("attack",""))
	var name := Loc.t(key) if not key.is_empty() else _loss_source(kind)
	if not key.is_empty() or attack=="floor_strike" or attack=="frost_cross":
		var attack_key := "record.attack."+attack
		if not attack.is_empty() and Loc.t(attack_key)!=attack_key:return Loc.t("record.loss.named",{"name":name,"attack":Loc.t(attack_key)})
	return name

## T15: the reasons of a fall as lines, from the loss material of run_record: [last blow, biggest blow (only when it is a different
## blow), damage of the last seconds by source]. A line is left out when its numbers are not in the material (an older record).
## The result window of a defeat shows all of them; the record page shows the same lines under its chart.
static func death_lines(loss: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var last_hit: Dictionary=loss.get("last_hit",{})
	if last_hit.is_empty():return lines
	lines.append(Loc.t("record.loss.last",{"source":_loss_name(last_hit),"life":Loc.num(int(last_hit.get("life",0))),"sec":Loc.dec(float(last_hit.get("ticks_before_end",0))/float(HZ),1)}))
	var big_hit: Dictionary=loss.get("big_hit",{})
	if not big_hit.is_empty() and (int(big_hit.get("ticks_before_end",-1))!=int(last_hit.get("ticks_before_end",-2))):
		lines.append(Loc.t("record.loss.big",{"source":_loss_name(big_hit),"life":Loc.num(int(big_hit.get("life",0))),"sec":Loc.dec(float(big_hit.get("ticks_before_end",0))/float(HZ),1)}))
	var recent: Dictionary=loss.get("recent",{})
	if int(recent.get("taken",0))>0:
		var names: Array=[]
		for part in recent.get("top",[]):names.append(Loc.t("record.loss.recent_part",{"source":_loss_name({"source":part.get("source",SOURCE_UNKNOWN),"key":part.get("key","")}),"life":Loc.num(int(part.get("life",0)))}))
		lines.append(Loc.t("record.loss.recent",{"sec":Loc.num(int(recent.get("seconds",3))),"life":Loc.num(int(recent.taken)),"parts":" · ".join(names)}))
	return lines

func _pairs(pairs: Array) -> Control:
	var column := VBoxContainer.new();column.name="RecordPairs";column.add_theme_constant_override("separation",6)
	column.add_child(_section_title(Loc.t("record.pairs.title")))
	var grid := GridContainer.new();grid.columns=3;grid.add_theme_constant_override("h_separation",14);column.add_child(grid)
	for i in mini(pairs.size(),MAX_PAIRS):
		var pair: Dictionary=pairs[i]
		var names := Loc.t("record.pairs.names",{"src":skill_name(String(pair.get("src_skill",""))),"by":skill_name(String(pair.get("by_skill","")))})
		var label := _wrap(names,BODY);label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;grid.add_child(label)
		grid.add_child(_num_label(Loc.t("record.pairs.count",{"n":Loc.num(int(pair.get("count",0)))}),SMALL,Palette.INK_DIM))
		grid.add_child(_num_label(Loc.t("record.pairs.extra",{"n":Loc.num(int(pair.get("extra",0)))})))
	if pairs.size()>MAX_PAIRS:column.add_child(_label(Loc.t("record.more",{"n":Loc.num(pairs.size()-MAX_PAIRS)}),SMALL,Palette.INK_DIM))
	return column

func _beats(beats: Array) -> Control:
	var column := VBoxContainer.new();column.name="RecordBeats";column.add_theme_constant_override("separation",6)
	column.add_child(_section_title(Loc.t("record.beats.title")))
	var grid := GridContainer.new();grid.columns=4;grid.add_theme_constant_override("h_separation",14);column.add_child(grid)
	for i in mini(beats.size(),MAX_BEATS):
		var beat: Dictionary=beats[i]
		var label := _wrap(String(beat.get("id","")),BODY);label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;grid.add_child(label)
		grid.add_child(_num_label(clock(int(beat.get("tick",0))),SMALL,Palette.INK_DIM))
		grid.add_child(_num_label(Loc.t("record.beats.kills",{"n":Loc.num(int(beat.get("kills",0)))})))
		grid.add_child(_num_label(Loc.t("record.beats.taken",{"n":Loc.num(int(beat.get("taken",0)))}),SMALL,Palette.INK_DIM))
	if beats.size()>MAX_BEATS:column.add_child(_label(Loc.t("record.more",{"n":Loc.num(beats.size()-MAX_BEATS)}),SMALL,Palette.INK_DIM))
	return column

func _picks(picks: Array) -> Control:
	var column := VBoxContainer.new();column.name="RecordPicks";column.add_theme_constant_override("separation",6)
	column.add_child(_section_title(Loc.t("record.picks.title")))
	var grid := GridContainer.new();grid.columns=4;grid.add_theme_constant_override("h_separation",18);grid.add_theme_constant_override("v_separation",4);column.add_child(grid)
	var shown := mini(picks.size(),MAX_PICKS)
	# Down the columns, so the order reads top to bottom, left to right.
	var rows := (shown+3)/4
	for r in rows:
		for c in 4:
			var index := c*rows+r
			var cell := HBoxContainer.new();cell.add_theme_constant_override("separation",8);cell.size_flags_horizontal=Control.SIZE_EXPAND_FILL;cell.custom_minimum_size.x=60
			if index<shown:
				var pick: Dictionary=picks[index]
				var when := _label(Loc.t("record.picks.when",{"time":clock(int(pick.get("tick",0))),"level":Loc.num(int(pick.get("level",0)))}),SMALL,Palette.INK_DIM);when.autowrap_mode=TextServer.AUTOWRAP_OFF;cell.add_child(when)
				var card := _line(pick_text(String(pick.get("card",""))),SMALL+1);card.size_flags_horizontal=Control.SIZE_EXPAND_FILL;cell.add_child(card)
			grid.add_child(cell)
	if picks.size()>MAX_PICKS:column.add_child(_label(Loc.t("record.more",{"n":Loc.num(picks.size()-MAX_PICKS)}),SMALL,Palette.INK_DIM))
	return column
