extends RefCounted
## Flattened by tools/dev/flatten_chain.py from chapter1/view/ui51/chapter_hud_quality51.gd.
## Methods named x__tag are the earlier layers of x; calls between them were super calls.

# ---- chapter1/view/cloister_hud.gd ----
## UI consumes run state; only explicit signals request core transitions.
signal start(primary: String)
signal choice(token: String, card_id: String)
signal equipment
signal close_equipment
signal equip_item(uid: int)
signal pause_toggle
signal retry
signal mute_toggle
signal motion_toggle(enabled: bool)
const Emblem=preload("res://chapter1/view/element_emblem.gd")
var root: Control
var overlay: ColorRect
var modal: PanelContainer
var hp: ProgressBar
var xp: ProgressBar
var status: Label
var skills: Label
var objective: Label
var dash: Label
var debug: Label
var toast: Label
var _last_signature := ""
var _last_hud_tick := -99
var _toast_left := 0.0
var _selected_item := -1
var temporary_art := true
var motion_enabled := true
var skill_labels: Dictionary={}
var menu_title := "잿빛 회랑"
var menu_description := "무리를 휩쓸고, 장비와 기술을 성장시켜 회랑 수호자를 처치하세요."
var menu_scope := "회랑 진입전 · 한 장을 완성하기 위한 첫 전투 구간"
var victory_title := "회랑 수호자를 처치했습니다"
const SKILL_NAMES={"chapter1.skill.ember":"잿불탄","chapter1.skill.frost":"서리창","chapter1.skill.arc":"연쇄 전류"}
const SLOT_NAMES={"weapon":"무기","head":"머리","body":"몸통","hands":"장갑","feet":"신발","charm":"목걸이","ring":"반지","ring2":"반지 2"}
const EQUIP_SLOTS=["weapon","head","body","hands","feet","charm","ring","ring2"]

func setup__cloister(view: Node3D) -> void:
	var layer := CanvasLayer.new()
	view.add_child(layer)
	root=Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names=PackedStringArray(["Malgun Gothic","맑은 고딕","sans-serif"])
	theme.default_font=font
	theme.default_font_size=17
	root.theme=theme
	var top := MarginContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left=28;top.offset_right=-28;top.offset_top=24
	root.add_child(top)
	var row := HBoxContainer.new()
	top.add_child(row)
	objective=_label("잿빛 회랑",20,Color("ded8c4"))
	objective.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(objective)
	var item_button := _button("장비 [I]",func():equipment.emit())
	row.add_child(item_button)
	row.add_child(_button("정지 [Esc]",func():pause_toggle.emit()))
	row.add_child(_button("음소거 [M]",func():mute_toggle.emit()))
	var bottom := PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top=-94;bottom.offset_left=22;bottom.offset_right=-22;bottom.offset_bottom=-18
	var frame := _style(Color(.055,.048,.038,.92),Color("69543b"))
	frame.content_margin_top=12;frame.content_margin_bottom=12;frame.content_margin_left=18;frame.content_margin_right=18
	bottom.add_theme_stylebox_override("panel",frame)
	root.add_child(bottom)
	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation",24)
	bottom.add_child(bottom_row)
	var bars := VBoxContainer.new()
	bars.custom_minimum_size.x=245
	bottom_row.add_child(bars)
	status=_label("생명력",15)
	bars.add_child(status)
	hp=_bar(Color("a93b2d"),13)
	xp=_bar(Color("a68b4d"),5)
	bars.add_child(hp);bars.add_child(xp)
	skills=_label("",17)
	# Retain the text summary for accessibility/QA, while visible skill identities
	# have distinct source-code sigils and colors rather than one long sentence.
	skills.visible=false;root.add_child(skills)
	var sigils := HBoxContainer.new();sigils.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	sigils.add_theme_constant_override("separation",22);bottom_row.add_child(sigils)
	for pair in [["ember",Color("e88b43")],["frost",Color("8ac8de")],["arc",Color("b5bde4")]]:
		var chip := HBoxContainer.new();chip.custom_minimum_size.x=180;chip.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		chip.add_theme_constant_override("separation",10)
		var icon := Emblem.new();icon.element=pair[0];icon.tint=pair[1];chip.add_child(icon)
		var text := _label("미습득",16,pair[1])
		# Word wrapping reports a zero minimum width inside an HBox. Reserve a
		# real text column, then use only the intentional name/rank line break.
		text.custom_minimum_size=Vector2(140,46)
		text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		text.autowrap_mode=TextServer.AUTOWRAP_OFF
		text.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		text.clip_text=true
		text.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;chip.add_child(text)
		skill_labels["chapter1.skill."+pair[0]]=text;sigils.add_child(chip)
	dash=_label("Space 회피",14,Color("b9aa90"))
	dash.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	dash.custom_minimum_size.x=138
	bottom_row.add_child(dash)
	debug=_label("",14)
	debug.position=Vector2(28,92)
	debug.visible=false
	root.add_child(debug)
	toast=_label("",20,Color("f0d68b"))
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast.offset_left=-400;toast.offset_right=400;toast.offset_top=80
	toast.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(toast)
	overlay=ColorRect.new()
	overlay.color=Color(.015,.012,.01,.78)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)
	modal=PanelContainer.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.offset_left=190;modal.offset_right=-190;modal.offset_top=120;modal.offset_bottom=-120
	modal.add_theme_stylebox_override("panel",_style(Color("211c16"),Color("8b6b43")))
	overlay.add_child(modal)

func _style__cloister(color: Color, border: Color=Color("65523c")) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color=color;s.border_color=border;s.set_border_width_all(1);s.set_content_margin_all(22)
	s.corner_radius_top_left=2;s.corner_radius_top_right=2;s.corner_radius_bottom_left=2;s.corner_radius_bottom_right=2
	return s

func _label__cloister(text: String, size: int=18, color: Color=Color("e0d8c7")) -> Label:
	var label := Label.new()
	label.text=text;label.add_theme_font_size_override("font_size",size);label.add_theme_color_override("font_color",color)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	if size>=25:
		var heading := SystemFont.new();heading.font_names=PackedStringArray(["Batang","바탕","Georgia"])
		label.add_theme_font_override("font",heading)
	return label

func _bar(color: Color, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage=false;bar.custom_minimum_size.y=height
	var fill := _style(color,color);fill.set_content_margin_all(0)
	var back := _style(Color("332a20"),Color("332a20"));back.set_content_margin_all(0)
	bar.add_theme_stylebox_override("fill",fill)
	bar.add_theme_stylebox_override("background",back)
	return bar

func _button__cloister(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text=text;b.custom_minimum_size.y=42
	for variant in [["normal",Color("30271d"),Color("70583b")],["hover",Color("493922"),Color("b9955f")],["focus",Color("463823"),Color("d2b27c")]]:
		var style := _style(variant[1],variant[2]);style.content_margin_left=12;style.content_margin_right=12;style.content_margin_top=8;style.content_margin_bottom=8
		b.add_theme_stylebox_override(variant[0],style)
	b.pressed.connect(action)
	return b

func sync__cloister(run: RefCounted, delta: float) -> void:
	_toast_left=maxf(0,_toast_left-delta)
	toast.visible=_toast_left>0
	var signature: String=run.mode
	if run.mode=="choice": signature+=str(run.get_offer().get("token",""))
	if run.mode=="inventory": signature+=str(run.equipped)+str(run.inventory.size())+str(_selected_item)
	var mode_changed := signature!=_last_signature
	if mode_changed:
		_last_signature=signature
		_build_modal(run)
	if run.hero.is_empty(): return
	# Terminal/modal transitions can occur on the same tick as the previous HUD
	# update. Refresh their final values immediately instead of retaining old HP.
	if not mode_changed and run.tick-_last_hud_tick<6 and run.tick>=_last_hud_tick:return
	_last_hud_tick=run.tick
	var g: Dictionary=run.growth.snapshot()
	status.text="생명력 %d / %d   ·   레벨 %d" % [ceili(float(run.hero.hp_raw)/256.0),ceili(float(run.hero.max_hp_raw)/256.0),g.level]
	hp.max_value=run.hero.max_hp_raw;hp.value=run.hero.hp_raw
	var thresholds: Array=run.growth.xp_thresholds()
	var index := mini(int(g.level)-1,thresholds.size()-1)
	xp.max_value=thresholds[index+1]-thresholds[index] if index<thresholds.size()-1 else 1
	xp.value=g.xp-thresholds[index] if index<thresholds.size()-1 else 1
	var texts: Array[String]=[]
	for id_ in skill_labels:skill_labels[id_].text=SKILL_NAMES[id_]+"\n미습득"
	for id_ in g.ranks:
		var d: Dictionary=run.effective_skill(id_)
		texts.append((Loc.t(String(d.name_key)) if d.evolved else SKILL_NAMES.get(id_,id_))+" %d" % d.rank)
		if skill_labels.has(id_):skill_labels[id_].text=(Loc.t(String(d.name_key)) if d.evolved else SKILL_NAMES.get(id_,id_))+"\n"+("진화 · " if d.evolved else "")+"랭크 %d" % d.rank
	skills.text="   /   ".join(texts)
	var elite_alive := false
	for e in run.enemies.values():
		if e.elite and e.hp_raw>0:
			elite_alive=true
			objective.text="회랑 수호자  %d / %d" % [ceili(float(e.hp_raw)/256),ceili(float(e.max_hp_raw)/256)]
	if not elite_alive:
		objective.text="잿빛 회랑  ·  %02d:%02d  ·  %d 처치" % [run.tick/3600,(run.tick/60)%60,run.kills]
	dash.text="Space 회피 준비" if run.tick>=run.get_next_dash_tick() else "회피 %.1f초" % (float(run.get_next_dash_tick()-run.tick)/60)
	debug.text="tick %d · alive %d · projectiles %d · XP %d\nF1 진단 화면" % [run.tick,run.alive_count(),run.projectiles.size(),g.xp]

func notify(text: String) -> void:
	toast.text=text;_toast_left=2.5

func _build_modal__cloister(run: RefCounted) -> void:
	for child in modal.get_children():modal.remove_child(child);child.queue_free()
	overlay.visible=run.mode!="playing"
	if not overlay.visible:return
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",16)
	modal.add_child(box)
	match run.mode:
		"menu":
			box.add_child(_label(menu_title,40,Color("ddc995")))
			box.add_child(_label(menu_description,21))
			box.add_child(_label("WASD / 좌클릭 이동 · Space 회피 · 기술 자동 시전 · I 장비 · Esc 정지",17,Color("aabbaf")))
			var classes := HBoxContainer.new()
			classes.add_theme_constant_override("separation",16)
			box.add_child(classes)
			for pair in [["잿불탄","chapter1.skill.ember"],["서리창","chapter1.skill.frost"],["연쇄 전류","chapter1.skill.arc"]]:
				var id_: String=pair[1]
				var b := _button(pair[0]+"으로 시작",func():start.emit(id_))
				b.size_flags_horizontal=Control.SIZE_EXPAND_FILL;classes.add_child(b)
			var spacer := Control.new();spacer.size_flags_vertical=Control.SIZE_EXPAND_FILL;box.add_child(spacer)
			box.add_child(_motion_control())
			box.add_child(_label(menu_scope,15,Color("a69a86")))
			if temporary_art:box.add_child(_label("캐릭터와 음향 일부는 제작 중입니다.",14,Color("a6a692")))
		"choice":
			var offer: Dictionary=run.get_offer()
			box.add_child(_label("성장 선택",32,Color("e4d09b")))
			box.add_child(_label("강화할 기술을 선택하세요. 선택하는 동안 전투가 멈춥니다.",17))
			var cards := HBoxContainer.new();cards.add_theme_constant_override("separation",18)
			cards.size_flags_vertical=Control.SIZE_EXPAND_FILL;box.add_child(cards)
			for card in offer.get("cards",[]):
				var panel := PanelContainer.new();panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
				panel.add_theme_stylebox_override("panel",_style(Color("2a241c"),Color("8f744b")))
				cards.add_child(panel)
				var column := VBoxContainer.new();column.add_theme_constant_override("separation",14);panel.add_child(column)
				var emblem := Emblem.new()
				emblem.custom_minimum_size=Vector2(42,42)
				emblem.element=String(card.get("skill_id","chapter1.skill.ember")).get_slice(".",2)
				emblem.tint={"ember":Color("e88b43"),"frost":Color("8ac8de"),"arc":Color("b5bde4")}.get(emblem.element,Color("bc9a63"))
				column.add_child(emblem)
				column.add_child(_label(Loc.t(String(card.title_key)),25,Color("e5d19b")))
				column.add_child(_label({"unlock":"새 기술","rank":"기술 강화","passive":"진화 준비","evolve":"기술 진화"}.get(card.kind,""),16,Color("91bca6")))
				column.add_child(_label(_card_description(card,run),17))
				var space := Control.new();space.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(space)
				var token: String=offer.token
				var card_id: String=card.id
				column.add_child(_button("선택",func():choice.emit(token,card_id)))
		"inventory": _inventory(box,run)
		"paused":
			box.add_child(_label("잠시 멈춤",34))
			box.add_child(_label("전투·발사체·경험치 회수가 정지됐습니다.",18))
			box.add_child(_button("계속하기 [Esc]",func():pause_toggle.emit()))
			box.add_child(_motion_control())
		"victory","defeat":
			box.add_child(_label(victory_title if run.mode=="victory" else "회랑에 쓰러졌습니다",32,Color("e5ca94")))
			box.add_child(_label("%d 처치 · 레벨 %d · 획득 장비 %d개" % [run.kills,run.growth.snapshot().level,run.inventory.size()],20))
			box.add_child(_label("다른 기술과 장비 조합으로 다시 도전할 수 있습니다.",18))
			box.add_child(_button("다시 도전",func():retry.emit()))
			if run.mode=="victory":box.add_child(_button("획득 장비 확인",func():equipment.emit()))

func _motion_control() -> CheckButton:
	var toggle := CheckButton.new();toggle.text="화면 흔들림";toggle.button_pressed=motion_enabled
	toggle.toggled.connect(func(value: bool):motion_enabled=value;motion_toggle.emit(value))
	return toggle

func _card_description__cloister(card: Dictionary, run: RefCounted) -> String:
	if card.kind=="passive":return "주력 기술의 진화를 준비합니다.\n최대 랭크와 이 패시브를 갖추면 진화가 선택지에 나타납니다."
	var e: Dictionary=card.get("after",{})
	var rows: Array[String]=[]
	if card.kind=="rank":rows.append("랭크 %d → %d" % [int(card.rank)-1,card.rank])
	if card.kind=="evolve":rows.append("최대 랭크와 선행 패시브 달성")
	rows.append("기술 기본 피해 %d" % (int(e.get("damage_raw",0))/256))
	if e.get("projectiles",0)>0:rows.append("투사체 %d발" % e.projectiles)
	if e.get("chain_targets",0)>0:rows.append("연쇄 %d대상 · %d갈래" % [e.chain_targets,e.branches])
	if e.get("radius_cm",0)>0 and card.skill_id!="chapter1.skill.arc":rows.append("범위 %.1fm" % (float(e.radius_cm)/100))
	if e.get("freeze_stacks",0)>0:rows.append("냉각 누적으로 빙결")
	if e.get("shatter_count",0)>0:rows.append("빙결된 적 처치 시 파쇄")
	if e.get("death_burst",0)>0:rows.append("처치 시 추가 효과")
	return "\n".join(rows)

func _stats__cloister(stats: Dictionary) -> String:
	var result: Array[String]=[]
	for id_ in stats:
		var value := int(stats[id_])
		match String(id_):
			"damage_bps":result.append("피해 +%.1f%%" % (float(value)/100))
			"max_hp_raw":result.append("최대 생명력 +%d" % (value/256))
			"damage_reduction_bps":result.append("받는 피해 -%.1f%%" % (float(value)/100))
			"projectiles":result.append("발사체 +%d (연쇄 기술은 대상 +%d)" % [value,value])
			"chain_targets":result.append("연쇄 전류 대상 +%d" % value)
			"shatter_count":result.append("서리창 랭크4 / 진화의 파쇄 파편 +%d" % value)
			"pickup_radius_cm":result.append("회수 반경 +%.1fm" % (float(value)/100))
			"cooldown_bps":result.append("기술 주기 단축 +%.1f%%" % (float(value)/100))
	return "\n".join(result) if not result.is_empty() else "장착 장비 없음"

func _inventory__cloister(box: VBoxContainer, run: RefCounted) -> void:
	box.add_child(_label("장비와 전투 선택",30,Color("e2d09c")))
	var rows := HBoxContainer.new();rows.add_theme_constant_override("separation",24);rows.size_flags_vertical=Control.SIZE_EXPAND_FILL;box.add_child(rows)
	var scroll := ScrollContainer.new();scroll.custom_minimum_size.x=300;rows.add_child(scroll)
	var list := VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(list)
	if run.inventory.is_empty():list.add_child(_label("장비를 발견하면 가까이 다가가 획득하세요.",18))
	for item in run.inventory:
		var uid: int=item.uid
		var equipped: bool=not run.equip_slot_of(uid).is_empty()
		list.add_child(_button(("✓ " if equipped else "")+item.name,func():_selected_item=uid;_last_signature=""))
	if _selected_item<0 and not run.inventory.is_empty():_selected_item=run.inventory[0].uid
	var comparison := HBoxContainer.new();comparison.add_theme_constant_override("separation",18);comparison.size_flags_horizontal=Control.SIZE_EXPAND_FILL;rows.add_child(comparison)
	var data: Dictionary=run.compare_item(_selected_item)
	if not data.is_empty():
		for pair in [["현재 장비",data.equipped],["선택한 장비",data.candidate]]:
			var column := VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;comparison.add_child(column)
			var item: Dictionary=pair[1]
			column.add_child(_label(pair[0],18,Color("8fada1")))
			column.add_child(_label(item.get("name","장착 장비 없음"),23,Color("dec993")))
			column.add_child(_label(_stats(item.get("stats",{})),17))
			if pair[0]=="선택한 장비":
				var uid: int=item.uid
				column.add_child(_button("장착",func():equip_item.emit(uid)))
	box.add_child(_button("전투로 돌아가기 [I]",func():close_equipment.emit()))

func invalidate() -> void:
	_last_signature="";_last_hud_tick=-99

func reset__cloister() -> void:
	_selected_item=-1;invalidate()

# ---- chapter1/view/chapter_hud.gd ----
var boss_bar: ProgressBar
var boss_name: Label
## Champion bar (A2 3.5): top centre, all of it above y 180 (outside the central 60 percent of the field).
const BOSS_BAR_WIDTH := 560.0
const BOSS_BAR_HEIGHT := 14.0
const BOSS_BAR_TOP := 100.0
signal stash_show
signal stash_equip(storage_id: int)
signal stash_salvage(storage_id: int)
signal save_retry
## Run flow (D4-U) and refused-save notice (D5-U). Every one only asks; chapter_one.gd decides and acts.
signal menu_return
signal abandon_request
signal quit_request
signal profile_open_folder
signal profile_play_without_save
signal profile_start_fresh(use_revision: bool)
var profile_state: Dictionary={}
var profile_note := ""
var stash_open := false
var _storage_selection := -1
func _init() -> void:
	menu_title="잿빛 회랑 · 제1장"
	menu_description="세 봉인을 돌파하고 재의 성소에 도달하세요. 장비와 기술을 성장시켜 회랑의 파수왕을 처치하세요."
	menu_scope="WASD / 좌클릭 이동 · Q 회복약 · E 의식 · 선택 의식은 위험과 추가 보상"
	victory_title="제1장 · 회랑의 파수왕을 처치했습니다"
func setup__chapter(view: Node3D) -> void:
	setup__cloister(view)
	boss_bar=_bar(Palette.THREAT_DEEP,BOSS_BAR_HEIGHT);boss_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_style_boss_bar()
	boss_bar.offset_left=-BOSS_BAR_WIDTH*.5;boss_bar.offset_right=BOSS_BAR_WIDTH*.5;boss_bar.offset_top=BOSS_BAR_TOP;boss_bar.offset_bottom=BOSS_BAR_TOP+BOSS_BAR_HEIGHT;boss_bar.visible=false;root.add_child(boss_bar)
	boss_name=_label("",18,Palette.INK);boss_name.autowrap_mode=TextServer.AUTOWRAP_OFF;boss_name.mouse_filter=Control.MOUSE_FILTER_IGNORE
	boss_name.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;boss_name.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	boss_name.add_theme_constant_override("outline_size",4);boss_name.add_theme_color_override("font_outline_color",Color(0,0,0,.85))
	boss_name.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	boss_name.offset_left=-BOSS_BAR_WIDTH*.5;boss_name.offset_right=BOSS_BAR_WIDTH*.5;boss_name.offset_top=BOSS_BAR_TOP-28;boss_name.offset_bottom=BOSS_BAR_TOP-3
	boss_name.visible=false;root.add_child(boss_name)
func sync__chapter(run: RefCounted,delta: float) -> void:
	sync__cloister(run,delta)
	if run.hero.is_empty():return
	var goal: Dictionary=run.objective()
	objective.text="%s · %02d:%02d\n%s"%[_goal_title(goal),run.tick/3600,(run.tick/60)%60,_goal_text(goal)]
	dash.text=("Space 회피 준비" if run.tick>=run.get_next_dash_tick() else "회피 %.1f초"%(float(run.get_next_dash_tick()-run.tick)/60))+"  ·  Q 회복약 %d / %d"%[run.potions,int(run.tuning.potion.carry_max)]
	for def in run.RITUALS:
		if def.zone==run.zone and run.rituals[def.id].state=="ready" and run.hero.position.distance_squared_to(def.position)<=3*3:
			objective.text+="\n[E] "+Loc.t("ritual.%s.name"%def.id)+" · 선택 보상"
	boss_bar.visible=run._champion_id>0 and run.enemies.has(run._champion_id)
	if boss_bar.visible:
		var e: Dictionary=run.enemies[run._champion_id];boss_bar.max_value=e.max_hp_raw;boss_bar.value=e.hp_raw
	if not run.pending_rewards.is_empty():objective.text+=" · 보관 대기 %d"%run.pending_rewards.size()
func _stats__chapter(stats: Dictionary) -> String:
	var lines: Array[String]=[]
	for pair in [["damage_bps","피해"],["cooldown_bps","시전 속도"],["slow_bps","냉기 감속"],["fire_damage_bps","화염 피해"],["arc_damage_bps","번개 피해"]]:
		if stats.has(pair[0]):lines.append("%s %+.1f%%"%[pair[1],float(stats[pair[0]])/100])
	if stats.has("max_hp_raw"):lines.append("최대 생명력 %+d"%(stats.max_hp_raw/256))
	if stats.has("damage_reduction_bps"):lines.append("받는 피해 -%.1f%%"%(float(stats.damage_reduction_bps)/100))
	if stats.has("pickup_radius_cm"):lines.append("회수 반경 +%.1fm"%(float(stats.pickup_radius_cm)/100))
	for pair in [["move_speed_bps","이동 속도"],["dash_cooldown_bps","회피 재사용 단축"],["soul_gain_bps","영혼 획득"]]:
		if stats.has(pair[0]):lines.append("%s %+.1f%%"%[pair[1],float(stats[pair[0]])/100])
	if stats.has("radius_cm"):lines.append("화염 폭발·번개 연결 거리 +%.1fm"%(float(stats.radius_cm)/100))
	for pair in [["projectiles","발사체 (번개는 대상)"],["chain_targets","연쇄 대상"],["shatter_count","파쇄 파편 (빙결 필요)"],["pierce","투사체 관통"],["fire_burst","화염 처치 폭발"],["frost_threshold","빙결 문턱 감소"],["arc_branches","번개 분기"]]:
		if stats.has(pair[0]):lines.append("%s %+d"%[pair[1],stats[pair[0]]])
	return "\n".join(lines) if not lines.is_empty() else "추가 효과 없음"

func _build_modal__chapter(run: RefCounted) -> void:
	if stash_open:
		_build_stash();return
	_build_modal__cloister(run)
	if run.mode in ["menu","victory","defeat"]:
		var box: VBoxContainer=modal.get_child(0)
		box.add_child(_button("장비 보관함 · %d개"%profile_state.get("items",[]).size(),func():stash_show.emit()))
		if not profile_note.is_empty():box.add_child(_label(profile_note,14,Color("b4b49d")))
		if run.mode in ["victory","defeat"]:box.add_child(_button("보상 저장 다시 확인",func():save_retry.emit()))

func _build_stash__chapter() -> void:
	for child in modal.get_children():modal.remove_child(child);child.queue_free()
	overlay.visible=true
	var box := VBoxContainer.new();box.add_theme_constant_override("separation",12);modal.add_child(box)
	box.add_child(_label("장비 보관함 · %d / 256"%profile_state.get("items",[]).size(),29,Color("e3cd9d")))
	box.add_child(_label("다음 도전에 가져갈 장비를 슬롯별로 선택하세요. 해체는 해당 장비를 재로 바꿉니다.",16))
	var row := HBoxContainer.new();row.size_flags_vertical=Control.SIZE_EXPAND_FILL;row.add_theme_constant_override("separation",24);box.add_child(row)
	var scroll := ScrollContainer.new();scroll.custom_minimum_size.x=320;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;row.add_child(scroll)
	var list := VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(list)
	var selected: Dictionary={}
	for record in profile_state.get("items",[]):
		if _storage_selection<0:_storage_selection=record.storage_id
		var id_: int=record.storage_id;var item: Dictionary=record.item
		var active: bool=_stash_worn(id_)
		list.add_child(_button(("◆ " if active else "")+item.name,func():_storage_selection=id_;invalidate()))
		if id_==_storage_selection:selected=record
	var details := VBoxContainer.new();details.size_flags_horizontal=Control.SIZE_EXPAND_FILL;details.custom_minimum_size.x=250;row.add_child(details)
	if selected.is_empty():details.add_child(_label("새로 획득한 장비는 전투가 끝나면 여기에 보관됩니다.",18))
	else:
		var item: Dictionary=selected.item;var id_: int=selected.storage_id
		details.add_child(_label(item.name,23,Color("dfc695")))
		details.add_child(_label(SLOT_NAMES[item.slot]+" · "+QUALITY_NAMES[item.quality],16))
		details.add_child(_label(_stats(item.stats),16))
		if not item.description.is_empty():details.add_child(_label(item.description,16))
		details.add_child(_button("다음 도전에 장착",func():stash_equip.emit(id_)))
		details.add_child(_button("해체하여 재로 전환",func():_storage_selection=-1;stash_salvage.emit(id_)))
	box.add_child(_label("재 %d · 완료한 도전 %d · %s"%[profile_state.get("essence",0),profile_state.get("completed_runs",0),profile_note],14))
	box.add_child(_button("돌아가기",func():stash_open=false;invalidate()))

# ---- chapter1/view/chapter_hud_quality16.gd ----
func _card_description__q16(card: Dictionary,run: RefCounted) -> String:
	var text := _card_description__cloister(card,run)
	if card.get("skill_id","")=="chapter1.skill.frost":
		var effect: Dictionary=card.get("after",{})
		if int(effect.get("shatter_count",0))>0 and int(effect.get("radius_cm",0))>0:
			text=text.replace("범위 %.1fm"%(float(effect.radius_cm)/100),"파쇄3.5m · 최대%d대상"%int(effect.shatter_count))
		if card.get("kind","")=="evolve":text=text.replace("빙결된 적 처치 시 파쇄","냉기 처치 시 파쇄\n파편50% · 정예25%")
	return text

# ---- chapter1/view/chapter_hud_quality17.gd ----
const Sigil=preload("res://chapter1/view/equipment_sigil_quality17.gd")
const Palette=preload("res://chapter1/view/hud/palette.gd")
const QUALITY_COLORS=Palette.QUALITY_COLORS
const QUALITY_NAMES={"common":"일반","magic":"마법","rare":"희귀","legendary":"전설","unique":"고유"}
var _gear_scroll: ScrollContainer
var _scroll_position := 0
var _scroll_ready := false
var _victory_age := 0.0
var _previous_mode := ""
var _seen_gear: Dictionary={}
var _discovery: PanelContainer
var _discovery_left := 0.0
func setup__q17(view: Node3D) -> void:
	setup__chapter(view)
	_discovery=PanelContainer.new();_discovery.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_place_notice(_discovery,104.0)
	_discovery.add_theme_stylebox_override("panel",_style(Color(.07,.08,.08,.95),Color("c88b46")))
	_discovery.mouse_filter=Control.MOUSE_FILTER_IGNORE;_discovery.visible=false;root.add_child(_discovery)
func sync__q17(run: RefCounted,delta: float) -> void:
	if run.mode=="victory":
		if _previous_mode not in ["victory","inventory"]:_victory_age=0
		_victory_age+=maxf(delta,0)
	_previous_mode=run.mode
	sync__chapter(run,delta)
	if run.mode=="victory" and not stash_open:overlay.visible=_victory_age>=1.3
	if run.mode=="playing":
		_discovery_left=maxf(0,_discovery_left-delta)
		for item in run.inventory:
			if _seen_gear.has(item.uid):continue
			_seen_gear[item.uid]=true
			if item.quality in ["unique","legendary"]:_show_discovery(item)
	_discovery.visible=_discovery_left>0 and run.mode=="playing"
func _show_discovery__q17(item: Dictionary) -> void:
	for child in _discovery.get_children():_discovery.remove_child(child);child.queue_free()
	var row := HBoxContainer.new();row.add_theme_constant_override("separation",16);_discovery.add_child(row)
	row.add_child(_sigil(item));var text := VBoxContainer.new();row.add_child(text)
	text.add_child(_label("고유 장비 발견 · "+SLOT_NAMES[item.slot],14,Palette.QUALITY_UNIQUE))
	text.add_child(_label(item.name,23,Color("efd0a0")));_discovery_left=3.0
func _sigil__q17(item: Dictionary) -> Control:
	var icon := Sigil.new();icon.slot=item.get("slot","charm");icon.tint=QUALITY_COLORS.get(item.get("quality","common"),Color.WHITE);return icon
func _build_modal__q17(run: RefCounted) -> void:
	if is_instance_valid(_gear_scroll) and _scroll_ready:_scroll_position=_gear_scroll.scroll_vertical
	_scroll_ready=false
	_gear_scroll=null
	_build_modal__chapter(run)
	if run.mode=="victory" and not stash_open:
		var box: VBoxContainer=modal.get_child(0)
		for item in run.inventory:
			if int(item.uid)!=int(run._elite_reward_uid):continue
			var panel := PanelContainer.new();panel.add_theme_stylebox_override("panel",_style(Color("28231b"),Color("b98140")))
			var row := HBoxContainer.new();row.add_theme_constant_override("separation",16);panel.add_child(row);row.add_child(_sigil(item))
			var column := VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(column)
			column.add_child(_label("파수왕의 유산 · 고유 장비",14,Palette.QUALITY_UNIQUE))
			column.add_child(_label(item.name,24,Color("f0d3a0")))
			column.add_child(_label(item.get("description",""),16))
			box.add_child(panel);box.move_child(panel,2)
func _inventory__q17(box: VBoxContainer,run: RefCounted) -> void:
	box.add_child(_label("장비와 전투 선택",30,Color("e2d09c")))
	var rows := HBoxContainer.new();rows.add_theme_constant_override("separation",24);rows.size_flags_vertical=Control.SIZE_EXPAND_FILL;box.add_child(rows)
	_gear_scroll=ScrollContainer.new();_gear_scroll.custom_minimum_size.x=300;_gear_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;rows.add_child(_gear_scroll)
	_gear_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_gear_scroll.add_child(list)
	if run.inventory.is_empty():list.add_child(_label("장비를 발견하면 가까이 다가가 획득하세요.",18))
	for item in run.inventory:
		var uid: int=item.uid;var active: bool=not run.equip_slot_of(uid).is_empty()
		var b := _button(("◆ " if active else "")+item.name,func():_selected_item=uid;invalidate())
		b.alignment=HORIZONTAL_ALIGNMENT_LEFT;b.add_theme_color_override("font_color",QUALITY_COLORS.get(item.quality,Color.WHITE))
		b.add_theme_font_size_override("font_size",15);b.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		b.tooltip_text=SLOT_NAMES[item.slot]+" · "+QUALITY_NAMES[item.quality]+"\n"+item.name;list.add_child(b)
	_restore_scroll(_gear_scroll,_scroll_position)
	if _selected_item<0 and not run.inventory.is_empty():_selected_item=run.inventory[0].uid
	var comparison := HBoxContainer.new();comparison.add_theme_constant_override("separation",20);comparison.size_flags_horizontal=Control.SIZE_EXPAND_FILL;rows.add_child(comparison)
	var data: Dictionary=run.compare_item(_selected_item)
	if not data.is_empty():
		for pair in [["현재 장비",data.equipped],["선택한 장비",data.candidate]]:
			var column := VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.custom_minimum_size.x=235;comparison.add_child(column)
			var item: Dictionary=pair[1]
			column.add_child(_label(pair[0],16,Color("99b9b0")))
			if not item.is_empty():column.add_child(_sigil(item))
			column.add_child(_label(item.get("name","장착 장비 없음"),22,QUALITY_COLORS.get(item.get("quality","common"),Color.WHITE)))
			if not item.is_empty():column.add_child(_label(SLOT_NAMES[item.slot]+" · "+QUALITY_NAMES[item.quality],14,Color("b7b0a1")))
			column.add_child(_label(_stats(item.get("stats",{})),16))
			if not item.get("description","").is_empty():column.add_child(_label(item.description,16,Color("e6c48e")))
			if pair[0]=="선택한 장비" and not item.is_empty():
				var uid: int=item.uid;column.add_child(_button("장착",func():equip_item.emit(uid)))
	box.add_child(_button("돌아가기 [I]",func():close_equipment.emit()))
func _restore_scroll(scroll: ScrollContainer,position_: int) -> void:
	# A deferred property assignment can run before containers have computed
	# the new list range and get clamped to zero. Restore after layout settles.
	for i in 2:await root.get_tree().process_frame
	if is_instance_valid(scroll) and scroll==_gear_scroll:
		scroll.scroll_vertical=position_;_scroll_ready=true
func _stats(stats: Dictionary) -> String:
	return _stats__chapter(stats).replace("파쇄 파편 (빙결 필요)","파쇄 대상 (빙결 / 진화 냉기 처치)")
func reset__q17() -> void:
	reset__cloister();_gear_scroll=null;_scroll_position=0;_scroll_ready=false;_victory_age=0;_previous_mode="";_seen_gear.clear();_discovery_left=0

# ---- chapter1/view/chapter_hud_quality20.gd ----
## Discovery follows actual inventory receipts, without granting or auto-equipping.
## Starter gear is seeded silently; at most one magic and one rare per slot.
var _discovery20_seeded := false
var _discovery20_magic := false
var _discovery20_slots: Dictionary={}
var _discovery20_uids: Dictionary={}
var _discovery20_queue: Array[Dictionary]=[]
var _discovery20_gap := 0.0
var _discovery20_name := ""
var discovery20_history: Array[Dictionary]=[]
func sync__q20(run: RefCounted,delta: float) -> void:
	if run.mode=="playing":
		if _discovery20_seeded:
			for item in run.inventory:
				if not _seen_gear.has(item.uid):_queue_discovery20(item)
		else:
			_discovery20_seeded=true
			for item in run.inventory:_discovery20_uids[item.uid]=true
	sync__q17(run,delta)
	if run.mode!="playing":return
	_discovery20_gap=maxf(0,_discovery20_gap-delta)
	if _discovery_left<=0 and _discovery20_gap<=0 and not _discovery20_queue.is_empty():
		_present_discovery20(_discovery20_queue.pop_front())
	_discovery.visible=_discovery_left>0
	if _discovery.visible:
		_discovery.modulate.a=minf(clampf((3.2-_discovery_left)/.18,0,1),clampf(_discovery_left/.4,0,1))
		if toast.text.begins_with("획득:") and toast.text.contains(_discovery20_name):toast.visible=false
func _show_discovery(item: Dictionary) -> void:
	_queue_discovery20(item)
func _queue_discovery20(item: Dictionary) -> void:
	if _discovery20_uids.has(item.uid):return
	var quality: String=item.get("quality","common")
	if quality=="magic":
		if _discovery20_magic:return
		_discovery20_magic=true
	elif quality=="rare":
		if _discovery20_slots.has(item.slot):return
		_discovery20_slots[item.slot]=true
	elif not quality in ["unique","legendary"]:return
	_discovery20_uids[item.uid]=true
	if _discovery20_queue.size()>=4:
		if not quality in ["unique","legendary"]:return
		_discovery20_queue.pop_back()
	if quality in ["unique","legendary"]:_discovery20_queue.push_front(item.duplicate(true))
	else:_discovery20_queue.append(item.duplicate(true))
func _present_discovery20(item: Dictionary) -> void:
	for child in _discovery.get_children():_discovery.remove_child(child);child.queue_free()
	var color: Color=QUALITY_COLORS.get(item.quality,Color.WHITE)
	_place_notice(_discovery,104.0)
	_discovery.add_theme_stylebox_override("panel",_notice_style(color.darkened(.2)))
	var row := HBoxContainer.new();row.add_theme_constant_override("separation",12);_discovery.add_child(row)
	row.add_child(_sigil(item));var column := VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(column)
	var header := "고유 장비 획득" if item.quality=="unique" else ("전설 장비 획득" if item.quality=="legendary" else ("첫 희귀 장비" if item.quality=="rare" else "첫 마법 장비"))
	var header_label := _label(header+" · "+SLOT_NAMES[item.slot],14,color);header_label.autowrap_mode=TextServer.AUTOWRAP_OFF;column.add_child(header_label)
	var name_label := _label(item.name,20,Palette.INK);name_label.custom_minimum_size.x=NOTICE_TEXT_WIDTH;name_label.autowrap_mode=TextServer.AUTOWRAP_OFF;name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;name_label.tooltip_text=item.name;column.add_child(name_label)
	var hint := _label("[I] 장비 능력 비교 · 장착",14,Color("bcb5a5"));hint.autowrap_mode=TextServer.AUTOWRAP_OFF;column.add_child(hint)
	_settle_discovery20(row)
	_discovery_left=3.2;_discovery20_gap=4.4
	_discovery20_name=item.name
	discovery20_history.append({"uid":item.uid,"quality":item.quality,"slot":item.slot,"name":item.name})
func _settle_discovery20(row: Control) -> void:
	# A temporary wrapped-label minimum can enlarge a PanelContainer; smaller
	# children do not automatically shrink its previous rect after replacement.
	for i in 2:await root.get_tree().process_frame
	if is_instance_valid(row) and row.get_parent()==_discovery:_place_notice(_discovery,104.0)
func reset() -> void:
	clear_upgrade()
	reset__q17();_discovery20_seeded=false;_discovery20_magic=false;_discovery20_slots.clear();_discovery20_uids.clear();_discovery20_queue.clear();_discovery20_gap=0;_discovery20_name="";discovery20_history.clear()
	_reset_flow()

# ---- chapter1/view/chapter_hud_quality23.gd ----
## Stable two-line action status: never split a Korean word to fill spare width.
func setup__q23(view: Node3D) -> void:
	setup__q17(view)
	dash.autowrap_mode=TextServer.AUTOWRAP_OFF
	dash.custom_minimum_size=Vector2(150,46)
func sync__q23(run: RefCounted,delta: float) -> void:
	sync__q20(run,delta)
	if run.hero.is_empty():return
	var remaining := maxf(0,float(run.get_next_dash_tick()-run.tick)/60.0)
	var evade := "Space 회피 준비" if remaining<=0 else "Space 회피 %.1f초"%remaining
	dash.text=evade+"\nQ 회복약 %d / %d"%[run.potions,int(run.tuning.potion.carry_max)]

# ---- chapter1/view/chapter_hud_quality27.gd ----
## Keep temporary combat messages below the champion/boss health bar.
func sync__q27(run: RefCounted,delta: float) -> void:
	sync__q23(run,delta)
	if boss_bar==null or toast==null:return
	toast.position.y= maxf(80.0,boss_bar.get_rect().end.y+10.0) if boss_bar.visible else 80.0

# ---- chapter1/view/chapter_hud_quality35.gd ----
const PaintedSigil35=preload("res://chapter1/view/equipment_sigil_quality35.gd")
func _sigil(item: Dictionary) -> Control:
	var icon := PaintedSigil35.new()
	icon.slot=item.get("slot","charm")
	icon.tint=QUALITY_COLORS.get(item.get("quality","common"),Color.WHITE)
	return icon

# ---- chapter1/view/chapter_hud_quality36.gd ----
## Describe the new control and propagation at the growth decision itself.
func _card_description__q36(card: Dictionary,run: RefCounted) -> String:
	var text: String=_card_description__q16(card,run)
	if card.kind=="passive":return text
	var effect: Dictionary=card.get("after",{})
	match String(card.get("skill_id","")):
		"chapter1.skill.ember":
			text=text.replace("처치 시 추가 효과","처치한 적에서 폭발 전파")
		"chapter1.skill.frost":
			if int(effect.get("slow_bps",0))>0:text+="\n이동속도 -%d%%"%int(effect.slow_bps/100)
			if int(effect.get("freeze_stacks",0))>0:text=text.replace("냉각 누적으로 빙결","%d회 적중 시 빙결"%int(effect.freeze_stacks))
		"chapter1.skill.arc":
			text=text.replace("처치 시 추가 효과","처치 폭발로 주변 적 타격")
			text+="\n짧은 스턴 · 일반0.3초 / 정예0.1초\n재발동 간격 · 일반2초 / 정예3초"
	return text

# ---- chapter1/view/ui38/chapter_hud_quality38.gd ----
## Presentation successor only: inherited signals, saves, rewards and scrolling.
const LifeSeal38=preload("res://chapter1/view/ui38/life_seal.gd")
const ElementSeal38=preload("res://chapter1/view/ui38/element_seal.gd")
const BRASS38=Palette.BRASS
var life_seal38: Control
var level38: Label
var _focus_return38: WeakRef

func _style(color: Color, border: Color=BRASS38) -> StyleBoxFlat:
	# Normalize the inherited warm surfaces to carbonized stone; rarity remains.
	var surface := color
	if color.r>color.b*1.12 and color.r<0.34:surface=Palette.SURFACE
	var s := StyleBoxFlat.new()
	s.bg_color=surface;s.border_color=border;s.set_border_width_all(1)
	s.set_content_margin_all(20)
	s.border_width_top=2
	s.shadow_color=Color(0,0,0,.45);s.shadow_size=8;s.shadow_offset=Vector2(0,4)
	return s

func _button(text: String, action: Callable) -> Button:
	var b := Button.new();b.text=text;b.custom_minimum_size.y=48
	b.add_theme_font_size_override("font_size",18)
	b.add_theme_color_override("font_color",Palette.INK)
	b.add_theme_color_override("font_disabled_color",Color("777a78"))
	for entry in [["normal",Palette.SURFACE_RAISED,Palette.BRASS_DIM],["hover",Color("303a3d"),Palette.BRASS],["pressed",Color("111719"),Palette.INK],["disabled",Color("191d1f"),Color("3e4343")]]:
		var s := _style(entry[1],entry[2]);s.set_content_margin_all(12)
		b.add_theme_stylebox_override(entry[0],s)
	var focus := StyleBoxFlat.new();focus.bg_color=Color(0,0,0,0);focus.border_color=Palette.BRASS_HI;focus.set_border_width_all(3)
	b.add_theme_stylebox_override("focus",focus)
	b.pressed.connect(action)
	return b

func setup__q38(view: Node3D) -> void:
	setup__q23(view)
	root.theme.default_font_size=19
	# Reuse the live labels and bars; only replace their layout containers.
	var old_top := objective.get_parent().get_parent()
	var old_bottom := status.get_parent().get_parent().get_parent()
	var top := HBoxContainer.new();top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left=28;top.offset_right=-28;top.offset_top=22;top.add_theme_constant_override("separation",10)
	root.add_child(top)
	var goal_plate := _backplate38();goal_plate.custom_minimum_size.x=460
	top.add_child(goal_plate);objective.reparent(goal_plate);objective.custom_minimum_size.x=430
	objective.add_theme_color_override("font_color",Palette.INK)
	objective.add_theme_font_size_override("font_size",19)
	var top_space := Control.new();top_space.size_flags_horizontal=Control.SIZE_EXPAND_FILL;top.add_child(top_space)
	for child in old_top.get_child(0).get_children():
		if child is Button:
			child.reparent(top);child.custom_minimum_size.y=36;child.add_theme_font_size_override("font_size",15)
			child.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
			for state in ["normal","hover","pressed","disabled"]:
				var compact: StyleBoxFlat=child.get_theme_stylebox(state).duplicate()
				compact.content_margin_top=7;compact.content_margin_bottom=7
				child.add_theme_stylebox_override(state,compact)
	old_top.queue_free()
	var dock := HBoxContainer.new();dock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	dock.offset_left=28;dock.offset_right=-28;dock.offset_top=-142;dock.offset_bottom=-22
	dock.add_theme_constant_override("separation",22);root.add_child(dock)
	life_seal38=LifeSeal38.new();dock.add_child(life_seal38)
	var vital_plate := _backplate38();vital_plate.size_flags_vertical=Control.SIZE_SHRINK_CENTER;dock.add_child(vital_plate)
	var vital := VBoxContainer.new();vital.custom_minimum_size.x=230;vital.alignment=BoxContainer.ALIGNMENT_CENTER;vital_plate.add_child(vital)
	status.reparent(vital);status.add_theme_font_size_override("font_size",18)
	status.add_theme_color_override("font_color",Palette.INK)
	hp.reparent(vital);hp.custom_minimum_size.y=8
	level38=_label("",16,Color("d4cdbb"));vital.add_child(level38)
	xp.reparent(vital);xp.custom_minimum_size.y=5
	var sigils := old_bottom.get_child(0).get_child(1)
	var left_space := Control.new();left_space.size_flags_horizontal=Control.SIZE_EXPAND_FILL;dock.add_child(left_space)
	sigils.reparent(dock)
	sigils.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;sigils.alignment=BoxContainer.ALIGNMENT_CENTER
	sigils.add_theme_constant_override("separation",8)
	for chip in sigils.get_children():
		chip.custom_minimum_size=Vector2(160,58);chip.size_flags_horizontal=Control.SIZE_FILL
		var slot := PanelContainer.new();slot.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		var frame := _style(Color(.045,.06,.065,.94),Palette.BRASS_DIM);frame.set_content_margin_all(10);frame.border_width_bottom=3
		slot.add_theme_stylebox_override("panel",frame);sigils.add_child(slot);chip.reparent(slot)
		for child in chip.get_children():
			if child is Label:child.custom_minimum_size.x=115;child.add_theme_font_size_override("font_size",17)
	var right_space := Control.new();right_space.size_flags_horizontal=Control.SIZE_EXPAND_FILL;dock.add_child(right_space)
	var dash_plate := _backplate38();dash_plate.size_flags_vertical=Control.SIZE_SHRINK_CENTER;dock.add_child(dash_plate)
	dash.reparent(dash_plate);dash.custom_minimum_size.x=195;dash.add_theme_font_size_override("font_size",18)
	dash.add_theme_color_override("font_color",Palette.INK)
	toast.add_theme_color_override("font_color",Color("f3dfac"))
	var toast_back := _plate_style38();toast_back.content_margin_left=16;toast_back.content_margin_right=16
	toast.add_theme_stylebox_override("normal",toast_back)
	old_bottom.queue_free()
	# Keep overlays above the replacement dock, and retain boss/toast layering.
	root.move_child(overlay,root.get_child_count()-1)
	modal.offset_left=90;modal.offset_right=-90;modal.offset_top=104;modal.offset_bottom=-76
	modal.add_theme_stylebox_override("panel",_style(Palette.SURFACE,BRASS38))
	overlay.color=Color(.025,.035,.045,.87)

func _plate_style38() -> StyleBoxFlat:
	var frame := StyleBoxFlat.new()
	frame.bg_color=Color(.025,.038,.045,.88)
	frame.border_color=Color(.44,.40,.30,.8);frame.border_width_bottom=1
	frame.content_margin_left=12;frame.content_margin_right=12
	frame.content_margin_top=9;frame.content_margin_bottom=9
	return frame

func _backplate38() -> PanelContainer:
	var panel := PanelContainer.new();panel.add_theme_stylebox_override("panel",_plate_style38())
	# Presentation backing must never swallow a world movement click.
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return panel

func sync__q38(run: RefCounted,delta: float) -> void:
	sync__q27(run,delta)
	# The padded transient message must also clear the inherited discovery card.
	if is_instance_valid(_discovery) and _discovery.visible and toast.visible:
		toast.position.y=maxf(toast.position.y,_discovery.get_rect().end.y+10)
	if run.hero.is_empty():return
	life_seal38.fraction=float(run.hero.hp_raw)/maxf(1,float(run.hero.max_hp_raw))
	status.text="생명  %d / %d"%[ceili(float(run.hero.hp_raw)/256),ceili(float(run.hero.max_hp_raw)/256)]
	var growth: Dictionary=run.growth.snapshot()
	level38.text="레벨 %d    경험치 %d / %d"%[growth.level,int(xp.value),int(xp.max_value)]

func _build_modal__q38(run: RefCounted) -> void:
	var previous := overlay.visible
	if not previous:
		var owner := root.get_viewport().gui_get_focus_owner()
		if owner!=null:_focus_return38=weakref(owner)
	_build_modal__q17(run)
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.offset_left=90;modal.offset_right=-90;modal.offset_top=104;modal.offset_bottom=-76
	if overlay.visible:
		if run.mode=="choice" and not stash_open:
			modal.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
			modal.offset_left=-630;modal.offset_right=630;modal.offset_top=-250;modal.offset_bottom=250
			_growth_cards38(run)
		elif run.mode=="inventory" and not stash_open:
			modal.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
			modal.offset_left=-680;modal.offset_right=680;modal.offset_top=-300;modal.offset_bottom=300
		_decorate38(modal)
		_focus_modal38.call_deferred()
	elif previous and _focus_return38!=null:
		var owner = _focus_return38.get_ref()
		if is_instance_valid(owner):owner.grab_focus.call_deferred()

func _growth_cards38__q38(run: RefCounted) -> void:
	# Preserve the authoritative token/card callbacks built by the inherited HUD.
	var box := modal.get_child(0)
	var cards := box.get_child(2)
	var offer: Dictionary=run.get_offer()
	box.add_theme_constant_override("separation",10)
	for i in cards.get_child_count():
		var panel := cards.get_child(i)
		var card: Dictionary=offer.cards[i]
		var element := String(card.get("skill_id","")).get_slice(".",2)
		var tint: Color={"ember":Palette.FIRE_TEXT,"frost":Palette.FROST_TEXT,"arc":Palette.ARC_TEXT}.get(element,BRASS38)
		var frame := _style(Palette.SURFACE_RAISED,tint.darkened(.35));frame.border_width_top=4
		panel.add_theme_stylebox_override("panel",frame)
		var column := panel.get_child(0)
		column.add_theme_constant_override("separation",8)
		var old_icon := column.get_child(0)
		column.remove_child(old_icon);old_icon.queue_free()
		var crest := ElementSeal38.new();crest.element=element;crest.tint=tint
		crest.custom_minimum_size=Vector2(70,70)
		column.add_child(crest);column.move_child(crest,0)
		column.get_child(2).add_theme_color_override("font_color",tint)
		column.get_child(3).add_theme_font_size_override("font_size",18)
		var spacer := column.get_child(4)
		spacer.size_flags_vertical=Control.SIZE_FILL;spacer.custom_minimum_size.y=4
		var button := column.get_child(column.get_child_count()-1)
		button.text="서약 선택"

func _inventory(box: VBoxContainer,run: RefCounted) -> void:
	_inventory__q17(box,run)
	# One selected item is the visual subject; an empty current slot is a line.
	var comparison := box.get_child(1).get_child(1)
	var data: Dictionary=run.compare_item(_selected_item)
	for child in comparison.get_children():comparison.remove_child(child);child.queue_free()
	if data.is_empty():return
	var candidate_item: Dictionary=data.candidate
	var current_item: Dictionary=data.equipped
	var panel := PanelContainer.new();panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var rarity: Color=QUALITY_COLORS.get(candidate_item.quality,BRASS38)
	var frame := _style(Color("171e21"),rarity.darkened(.3));frame.border_width_top=3
	panel.add_theme_stylebox_override("panel",frame);comparison.add_child(panel)
	var scroll := ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var details := VBoxContainer.new();details.size_flags_horizontal=Control.SIZE_EXPAND_FILL;details.add_theme_constant_override("separation",16);scroll.add_child(details)
	var heading := HBoxContainer.new();heading.add_theme_constant_override("separation",18);details.add_child(heading)
	heading.add_child(_sigil(candidate_item))
	var title := VBoxContainer.new();title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;heading.add_child(title)
	var target_slot: String=data.get("slot",candidate_item.slot)
	var wearable: bool=data.get("can_equip",true)
	title.add_child(_label(SLOT_NAMES[target_slot]+" · "+QUALITY_NAMES[candidate_item.quality],16,rarity))
	title.add_child(_label(candidate_item.name,28,Palette.INK))
	if int(candidate_item.get("required_level",1))>1:
		title.add_child(_label("요구 레벨 %d"%int(candidate_item.required_level)+("" if wearable else " · 아직 착용할 수 없습니다"),15,Palette.INK_DIM if wearable else Color("d9735f")))
	var current_line: String="현재 "+String(SLOT_NAMES[target_slot])+" 슬롯이 비어 있습니다" if current_item.is_empty() else "현재 장비  "+String(current_item.name)
	details.add_child(_label(current_line,17,Palette.INK_DIM))
	var rule := HSeparator.new();details.add_child(rule)
	var stats_row := HBoxContainer.new();stats_row.add_theme_constant_override("separation",32);details.add_child(stats_row)
	var stats := VBoxContainer.new();stats.size_flags_horizontal=Control.SIZE_EXPAND_FILL;stats_row.add_child(stats)
	stats.add_child(_label("선택 장비의 효과",18,rarity));stats.add_child(_label(_stats(candidate_item.stats),19))
	if not candidate_item.get("description","").is_empty():stats.add_child(_label(candidate_item.description,17,Palette.INK_DIM))
	if not current_item.is_empty():
		var difference: Dictionary={}
		var current: Dictionary=current_item.get("stats",{})
		var candidate: Dictionary=candidate_item.get("stats",{})
		for key in candidate:
			var value := int(candidate[key])-int(current.get(key,0))
			if value!=0:difference[key]=value
		for key in current:
			if not candidate.has(key) and int(current[key])!=0:difference[key]=-int(current[key])
		var delta := VBoxContainer.new();delta.size_flags_horizontal=Control.SIZE_EXPAND_FILL;stats_row.add_child(delta)
		delta.add_child(_label("현재 장비에서 변화",18,Palette.INK_DIM));delta.add_child(_label(_delta_text38(difference),19))
	var uid: int=candidate_item.uid
	var active: bool=not run.equip_slot_of(uid).is_empty()
	var equip_button := _button("장착 중" if active else ("레벨 부족" if not wearable else "이 장비 장착"),func():equip_item.emit(uid))
	equip_button.disabled=active or not wearable;equip_button.size_flags_horizontal=Control.SIZE_SHRINK_END;equip_button.custom_minimum_size.x=220
	details.add_child(equip_button)

func _delta_text38(stats: Dictionary) -> String:
	if stats.is_empty():return "능력치 변화 없음"
	# Existing formatter owns units and vocabulary; normalize signed negative cases.
	var text := _stats(stats)
	text=text.replace("--","+").replace("+-","-")
	return text

func _decorate38(node: Node) -> void:
	# Inherited card/equipment structure and callbacks are retained verbatim.
	for child in node.get_children():
		if child is PanelContainer and child!=modal and not child.has_theme_stylebox_override("panel"):
			child.add_theme_stylebox_override("panel",_style(Palette.SURFACE_RAISED,BRASS38))
		_decorate38(child)

func _focus_modal38() -> void:
	if not overlay.visible:return
	# A confirm window or the refused-save notice owns the keyboard while it is open.
	if is_instance_valid(_flow_dialog):return
	# The skill-tree screen owns the keyboard while it is open; a rebuild of the menu beneath it must not take focus.
	if is_instance_valid(skill_panel) and skill_panel.visible:return
	var buttons: Array[Control]=[]
	_collect_focus38(modal,buttons)
	if buttons.is_empty():return
	# The menu's tree button sits left of the start buttons in the tree but should come after them in the focus chain.
	if is_instance_valid(_menu_tree_button) and buttons[0]==_menu_tree_button and buttons.size()>3:
		buttons.remove_at(0);buttons.insert(3,_menu_tree_button)
	for i in buttons.size():
		var b := buttons[i]
		b.focus_next=b.get_path_to(buttons[(i+1)%buttons.size()])
		b.focus_previous=b.get_path_to(buttons[(i+buttons.size()-1)%buttons.size()])
	var first: Control=buttons[0]
	# A rebuilt menu keeps looking at the witch that was selected, not at the first one.
	if _menu_witch>0 and _menu_witch<_menu_starts.size() and is_instance_valid(_menu_tree_button) and _menu_tree_button.is_inside_tree():
		var wanted: Button=_menu_starts[_menu_witch]
		if is_instance_valid(wanted) and not wanted.disabled:first=wanted
	first.grab_focus()

func _collect_focus38(node: Node,items: Array[Control]) -> void:
	for child in node.get_children():
		if child is BaseButton and not child.disabled:items.append(child)
		_collect_focus38(child,items)

# ---- chapter1/view/ui40/chapter_hud_quality40.gd ----
## Read-only presentation successor. All gear/save transitions retain the
## inherited signals; filters never change profile_state or run inventory.
var _stash_slot40 := ""
var _stash_quality40 := ""
var _stash_sort40 := 0
var _stash_scroll40: ScrollContainer
var _stash_offset40 := 0
var _stash_reset_scroll40 := false
var _route40: PanelContainer
var _route_labels40: Array[Label]=[]
var _route_hint40: Label

func setup__q40(view: Node3D) -> void:
	setup__q38(view)
	_route40=_backplate38();_route40.name="ChapterRoute40"
	_route40.position=Vector2(28,128);_route40.custom_minimum_size.x=500
	root.add_child(_route40)
	var column := VBoxContainer.new();column.add_theme_constant_override("separation",5);_route40.add_child(column)
	var row := HBoxContainer.new();row.add_theme_constant_override("separation",8);column.add_child(row)
	for i in 3:
		if i>0:
			var separator := _label("›",16,Color("716c60"));separator.autowrap_mode=TextServer.AUTOWRAP_OFF;row.add_child(separator)
		var entry := _label("",15);entry.mouse_filter=Control.MOUSE_FILTER_IGNORE
		entry.autowrap_mode=TextServer.AUTOWRAP_OFF
		row.add_child(entry);_route_labels40.append(entry)
	_route_hint40=_label("",14,Palette.INK_DIM);_route_hint40.autowrap_mode=TextServer.AUTOWRAP_OFF;column.add_child(_route_hint40)
	root.move_child(overlay,root.get_child_count()-1)

func sync__q40(run: RefCounted,delta: float) -> void:
	var overlay_was_visible := overlay.visible
	sync__q38(run,delta)
	# HUD17 reveals victory after 1.3s, after the initial deferred focus has
	# already returned while hidden. Focus once on the actual reveal edge.
	if run.mode=="victory" and not stash_open and overlay.visible and not overlay_was_visible:
		_focus_modal38.call_deferred()
	_route40.visible=not run.hero.is_empty() and run.mode=="playing"
	if not _route40.visible:return
	var goal: Dictionary=run.objective()
	for i in 3:
		var cleared: bool=i<run.seals.size() and bool(run.seals[i].get("cleared",false))
		var current: bool=i==int(goal.zone)
		_route_labels40[i].text=("✓ " if cleared else ("◆ " if current else "○ "))+Loc.t("zone.%d.name"%i)
		_route_labels40[i].add_theme_color_override("font_color",Color("a8baaa") if cleared else (Color("efdaa6") if current else Color("85877f")))
	if not bool(goal.entered):
		var destination: Vector2=goal.destination
		_route_hint40.text="다음 봉인까지 %.0fm · 열린 동쪽 회랑을 따라 이동"%run.hero.position.distance_to(destination)
	else:_route_hint40.text="마지막 봉인 · 회랑의 파수왕을 처치하세요" if int(goal.boss_phase)>0 else "현재 구역의 봉인을 돌파하세요"

func _build_modal__q40(run: RefCounted) -> void:
	_build_modal__q38(run)
	if not stash_open and run.mode in ["victory","defeat"]:
		_build_result40(run)
		modal.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		modal.offset_left=-620;modal.offset_right=620;modal.offset_top=-310;modal.offset_bottom=310
		_focus_modal38.call_deferred()

func _clear_modal40() -> VBoxContainer:
	for child in modal.get_children():modal.remove_child(child);child.queue_free()
	var box := VBoxContainer.new();box.add_theme_constant_override("separation",12);modal.add_child(box)
	return box

func _filter40(values: Array,names: Array,current: int,change: Callable) -> OptionButton:
	var option := OptionButton.new();option.custom_minimum_size=Vector2(170,42)
	for state in ["normal","hover","pressed","disabled"]:
		var compact := _style(Palette.SURFACE_RAISED,Palette.BRASS_DIM);compact.content_margin_top=8;compact.content_margin_bottom=8
		compact.content_margin_left=12;compact.content_margin_right=12
		option.add_theme_stylebox_override(state,compact)
	var focus := StyleBoxFlat.new();focus.bg_color=Color.TRANSPARENT
	focus.border_color=Palette.BRASS_HI;focus.set_border_width_all(3)
	option.add_theme_stylebox_override("focus",focus)
	for name_ in names:option.add_item(String(name_))
	option.select(current)
	option.item_selected.connect(func(index: int):change.call(values[index]))
	return option

func _stash_records40() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for record in profile_state.get("items",[]):
		var item: Dictionary=record.item
		if not _stash_slot40.is_empty() and item.slot!=_stash_slot40:continue
		if not _stash_quality40.is_empty() and item.quality!=_stash_quality40:continue
		result.append(record)
	result.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if _stash_sort40==1:
			var rarity := {"common":0,"magic":1,"rare":2,"legendary":3,"unique":4}
			var left: int=rarity.get(a.item.quality,0);var right: int=rarity.get(b.item.quality,0)
			if left!=right:return left>right
		elif _stash_sort40==2:
			var left: String=a.item.name;var right: String=b.item.name
			if left!=right:return left.naturalnocasecmp_to(right)<0
		return int(a.storage_id)>int(b.storage_id))
	return result

func _build_stash() -> void:
	if is_instance_valid(_stash_scroll40) and not _stash_reset_scroll40:_stash_offset40=_stash_scroll40.scroll_vertical
	_stash_reset_scroll40=false
	var box := _clear_modal40();overlay.visible=true
	box.add_child(_label("다음 도전의 장비",30,Palette.INK))
	box.add_child(_label("보유 장비 %d개 · 슬롯마다 하나씩, 반지는 둘까지 장착합니다"%profile_state.get("items",[]).size(),17,Palette.INK_DIM))
	var filters := HBoxContainer.new();filters.add_theme_constant_override("separation",10);box.add_child(filters)
	var slots: Array=["","weapon","head","body","hands","feet","charm","ring"]
	var qualities: Array=["","common","magic","rare","legendary","unique"]
	var slot_filter := _filter40(slots,["모든 슬롯","무기","머리","몸통","장갑","신발","목걸이","반지"],slots.find(_stash_slot40),func(value):_stash_slot40=value;_reset_stash_filter40())
	slot_filter.tooltip_text="장비 슬롯 필터";filters.add_child(slot_filter)
	var rarity_filter := _filter40(qualities,["모든 등급","일반","마법","희귀","전설","고유"],qualities.find(_stash_quality40),func(value):_stash_quality40=value;_reset_stash_filter40())
	rarity_filter.tooltip_text="장비 등급 필터";filters.add_child(rarity_filter)
	var order := _filter40([0,1,2],["최근 획득 순","등급 높은 순","이름 순"],_stash_sort40,func(value):_stash_sort40=int(value);_reset_stash_filter40())
	order.tooltip_text="보관함 정렬";filters.add_child(order)
	var records: Array[Dictionary]=_stash_records40()
	var count_label := _label("표시 %d개"%records.size(),15,Palette.INK_DIM);count_label.autowrap_mode=TextServer.AUTOWRAP_OFF
	count_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;filters.add_child(count_label)
	var row := HBoxContainer.new();row.size_flags_vertical=Control.SIZE_EXPAND_FILL;row.add_theme_constant_override("separation",20);box.add_child(row)
	_stash_scroll40=ScrollContainer.new();_stash_scroll40.custom_minimum_size.x=390
	_stash_scroll40.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;row.add_child(_stash_scroll40)
	var list := VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("separation",7);_stash_scroll40.add_child(list)
	var selected: Dictionary={}
	for record in records:
		if int(record.storage_id)==_storage_selection:selected=record
	if selected.is_empty() and not records.is_empty():selected=records[0];_storage_selection=int(selected.storage_id)
	for record in records:
		var id_: int=record.storage_id;var item: Dictionary=record.item
		var active: bool=_stash_worn(id_)
		var button := _button(("[장착] " if active else "")+String(item.name),func():_storage_selection=id_;invalidate())
		button.alignment=HORIZONTAL_ALIGNMENT_LEFT;button.add_theme_font_size_override("font_size",17)
		button.add_theme_color_override("font_color",QUALITY_COLORS.get(item.quality,Color.WHITE))
		button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text=String(SLOT_NAMES[item.slot])+" · "+String(QUALITY_NAMES[item.quality])+"\n"+String(item.name)
		if id_==_storage_selection:button.add_theme_stylebox_override("normal",_style(Color("303a3d"),BRASS38))
		list.add_child(button)
	if records.is_empty():list.add_child(_label("조건에 맞는 장비가 없습니다.\n슬롯이나 등급 필터를 바꿔 보세요." if not profile_state.get("items",[]).is_empty() else "전투에서 얻은 장비는 도전이 끝나면 여기에 보관됩니다.",17))
	var detail_frame := PanelContainer.new();detail_frame.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	detail_frame.add_theme_stylebox_override("panel",_style(Color("171e21"),BRASS38));row.add_child(detail_frame)
	var detail_scroll := ScrollContainer.new();detail_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;detail_frame.add_child(detail_scroll)
	var details := VBoxContainer.new();details.size_flags_horizontal=Control.SIZE_EXPAND_FILL;details.add_theme_constant_override("separation",14);detail_scroll.add_child(details)
	if not selected.is_empty():_stash_detail40(details,selected)
	else:details.add_child(_label("장비를 선택하면 효과와 장착 상태를 확인할 수 있습니다.",18))
	box.add_child(_label("재 %d · 완료한 도전 %d\n%s"%[profile_state.get("essence",0),profile_state.get("completed_runs",0),profile_note if not profile_note.is_empty() else "저장 상태 확인 중"],15,Palette.INK_DIM))
	box.add_child(_button("돌아가기 [Esc]",func():stash_open=false;invalidate()))
	_restore_stash40.call_deferred(_stash_scroll40,_stash_offset40)

func _stash_detail40(details: VBoxContainer,record: Dictionary) -> void:
	var item: Dictionary=record.item;var id_: int=record.storage_id
	var active: bool=_stash_worn(id_)
	var rarity: Color=QUALITY_COLORS.get(item.quality,BRASS38)
	var heading := HBoxContainer.new();heading.add_theme_constant_override("separation",16);details.add_child(heading)
	heading.add_child(_sigil(item));var title := VBoxContainer.new();title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;heading.add_child(title)
	title.add_child(_label(String(SLOT_NAMES[item.slot])+" · "+String(QUALITY_NAMES[item.quality]),16,rarity))
	title.add_child(_label(item.name,25,Palette.INK))
	details.add_child(_label("다음 도전에 장착 중" if active else "보관 중 · 다음 도전에 장착할 수 있습니다",17,Color("a8baaa") if active else Palette.INK_DIM))
	details.add_child(HSeparator.new());details.add_child(_label(_stats(item.get("stats",{})),18))
	if not String(item.get("description","")).is_empty():details.add_child(_label(item.description,17,Palette.INK_DIM))
	if int(item.get("required_level",1))>1:details.add_child(_label("요구 레벨 %d"%int(item.required_level),15,Palette.INK_DIM))
	var equip_button := _button("장착 중" if active else "다음 도전에 장착",func():stash_equip.emit(id_));equip_button.disabled=active;details.add_child(equip_button)
	details.add_child(_button("이 장비 해체",func():_storage_selection=-1;stash_salvage.emit(id_)))
	details.add_child(_label("해체하면 장비가 사라지고 재로 전환됩니다.",14,Color("bca58f")))

func _restore_stash40(scroll: ScrollContainer,position_: int) -> void:
	for i in 2:await root.get_tree().process_frame
	if is_instance_valid(scroll) and scroll==_stash_scroll40:scroll.scroll_vertical=position_

func _reset_stash_filter40() -> void:
	_stash_offset40=0;_stash_reset_scroll40=true;invalidate()

func _build_result40__q40(run: RefCounted) -> void:
	var box := _clear_modal40()
	var victorious: bool=run.mode=="victory"
	box.add_child(_label("회랑의 서약을 완수했습니다" if victorious else "이번 도전이 끝났습니다",32,Palette.INK))
	var growth: Dictionary=run.growth.snapshot()
	box.add_child(_label("%02d:%02d  ·  %d 처치  ·  레벨 %d"%[run.tick/3600,(run.tick/60)%60,run.kills,growth.level],19,Palette.INK_DIM))
	var columns := HBoxContainer.new();columns.size_flags_vertical=Control.SIZE_EXPAND_FILL;columns.add_theme_constant_override("separation",22);box.add_child(columns)
	var summary := VBoxContainer.new();summary.custom_minimum_size.x=350;summary.add_theme_constant_override("separation",12);columns.add_child(summary)
	summary.add_child(_label("이번 도전 장비",20,BRASS38))
	summary.add_child(_label("보유 %d개 · 보관 대기 %d개"%[run.inventory.size(),run.pending_rewards.size()],18))
	summary.add_child(_label("시작할 때 가져온 장비를 포함합니다.",14,Color("a4a597")))
	for slot in EQUIP_SLOTS:
		var equipped_name := "장착 없음"
		for item in run.inventory:
			if int(item.uid)==int(run.equipped.get(slot,-1)):equipped_name=String(item.name);break
		summary.add_child(_label(String(SLOT_NAMES[slot])+"  "+equipped_name,16))
	var rewards := VBoxContainer.new();rewards.size_flags_horizontal=Control.SIZE_EXPAND_FILL;rewards.add_theme_constant_override("separation",12);columns.add_child(rewards)
	rewards.add_child(_label("보상과 보관",20,BRASS38))
	var elite_item: Dictionary={}
	for item in run.inventory:
		if int(item.uid)==int(run._elite_reward_uid):elite_item=item;break
	if not elite_item.is_empty():
		var reward_frame := PanelContainer.new();reward_frame.add_theme_stylebox_override("panel",_style(Palette.SURFACE_RAISED,Color("b98140")));rewards.add_child(reward_frame)
		var reward_row := HBoxContainer.new();reward_row.add_theme_constant_override("separation",12);reward_frame.add_child(reward_row)
		reward_row.add_child(_sigil(elite_item));var names := VBoxContainer.new();names.size_flags_horizontal=Control.SIZE_EXPAND_FILL;reward_row.add_child(names)
		names.add_child(_label("파수왕의 유산",15,Palette.QUALITY_UNIQUE));names.add_child(_label(elite_item.name,23,Palette.INK))
	else:rewards.add_child(_label("보유 장비는 보관함에서 확인하고 다음 도전에 장착할 수 있습니다.",18))
	rewards.add_child(_label("저장 상태",17,Color("a8baaa")))
	rewards.add_child(_label(profile_note if not profile_note.is_empty() else "저장 상태 확인 중",17))
	rewards.add_child(_button("보상 저장 다시 확인",func():save_retry.emit()))
	var actions := HBoxContainer.new();actions.add_theme_constant_override("separation",14);box.add_child(actions)
	var stash_button := _button("보관함에서 다음 장비 선택",func():stash_show.emit());stash_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;actions.add_child(stash_button)
	if victorious:
		var inspect_button := _button("이번 도전 장비 확인",func():equipment.emit());inspect_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;actions.add_child(inspect_button)
	var retry_button := _button("다시 도전",func():retry.emit());retry_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;actions.add_child(retry_button)

# ---- chapter1/view/ui41/chapter_hud_quality41.gd ----
## Menu-only portrait successor. The inherited start/stash callbacks stay on
## their existing controls. This 2D concept does not replace the 3D actor.
const OathPortrait41=preload("res://chapter1/art/characters/frost_witch_v02.png")
## One witch per starting school, in the order of the three start buttons.
const WitchPortraits=[preload("res://chapter1/art/characters/ember_witch_v02.png"),OathPortrait41,preload("res://chapter1/art/characters/storm_witch_v02.png")]

func _build_modal__q41(run: RefCounted) -> void:
	_build_modal__q40(run)
	if run.mode!="menu" or stash_open or not overlay.visible:return
	var original := modal.get_child(0) as VBoxContainer
	if original==null or original.get_child_count()<7:return
	var inherited_starts := original.get_child(3) as HBoxContainer
	if inherited_starts==null or inherited_starts.get_child_count()!=3:return
	_build_menu41(original,inherited_starts)
	_focus_modal38.call_deferred()

## One start button, two inks: the skill name in its element's text colour, the summary line in the dim ink.
## The button's own text is emptied (it would take one colour); the start callback stays on the button.
func _two_line_choice(button: Button,name_text: String,summary: String,tint: Color) -> void:
	button.text="";button.tooltip_text=name_text+" · "+summary
	var holder := VBoxContainer.new();holder.name="ChoiceText";holder.mouse_filter=Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.offset_left=12;holder.offset_right=-12;holder.offset_top=6;holder.offset_bottom=-6
	holder.alignment=BoxContainer.ALIGNMENT_CENTER;holder.add_theme_constant_override("separation",4)
	for line in [[name_text,20,tint],[summary,17,Palette.INK_DIM]]:
		var label := _label(line[0],line[1],line[2]);label.autowrap_mode=TextServer.AUTOWRAP_OFF
		label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.mouse_filter=Control.MOUSE_FILTER_IGNORE
		holder.add_child(label)
	button.add_child(holder)

func _build_menu41(original: VBoxContainer,inherited_starts: HBoxContainer) -> void:
	# Keep the exact three inherited skill-id closures and the real profile
	# footer. Reparenting changes presentation, not the start/save contract.
	var title := original.get_child(0) as Label
	var description := original.get_child(1) as Label
	var controls := original.get_child(2) as Label
	var old_spacer := original.get_child(4)
	var motion := original.get_child(5) as CheckButton
	var scope := original.get_child(6) as Label
	if title==null or description==null or controls==null or motion==null or scope==null:return
	var starts: Array[Node]=inherited_starts.get_children()
	for child in starts:
		if not child is Button:return
	var original_children: Array[Node]=original.get_children()
	modal.remove_child(original)
	var row := HBoxContainer.new();row.name="OathMenu41"
	row.add_theme_constant_override("separation",34);modal.add_child(row)
	# Left column: the witch's portrait, then her permanent-growth summary and the skill-tree button (G1 P4).
	var left := VBoxContainer.new();left.name="WitchColumn";left.add_theme_constant_override("separation",8)
	left.size_flags_vertical=Control.SIZE_SHRINK_CENTER;row.add_child(left)
	var portrait_frame := PanelContainer.new();portrait_frame.name="OathPortrait41"
	portrait_frame.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	var portrait_style := _style(Color("111416"),Palette.BRASS_DIM)
	portrait_style.set_content_margin_all(12);portrait_style.border_width_top=1
	portrait_frame.add_theme_stylebox_override("panel",portrait_style);left.add_child(portrait_frame)
	var portrait := TextureRect.new();portrait.name="PortraitTexture41"
	portrait.texture=WitchPortraits[_menu_witch];portrait.custom_minimum_size=Vector2(280,420)
	# Official4.5 TextureRect: IGNORE_SIZE permits the source1024x1536 to
	# shrink; KEEP_ASPECT_CENTERED shows the whole portrait without distortion.
	# https://docs.godotengine.org/en/4.5/classes/class_texturerect.html
	portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE;portrait_frame.add_child(portrait)
	var body := VBoxContainer.new();body.name="StartChoices41"
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",12);row.add_child(body)
	title.reparent(body);title.add_theme_font_size_override("font_size",40)
	title.add_theme_color_override("font_color",Palette.INK)
	description.reparent(body);description.add_theme_font_size_override("font_size",19)
	description.add_theme_color_override("font_color",Color("d0c7b6"))
	controls.reparent(body);controls.add_theme_font_size_override("font_size",15)
	controls.add_theme_color_override("font_color",Color("aeb5ab"))
	body.add_child(_label("첫 기술을 선택하세요",17,Palette.INK_DIM))
	var choices := VBoxContainer.new();choices.name="PrimarySkillChoices41"
	choices.add_theme_constant_override("separation",8);body.add_child(choices)
	var tints := [Palette.FIRE_TEXT,Palette.FROST_TEXT,Palette.ARC_TEXT]
	# Rank1 base definitions: growth_quality37.json. Gear can modify these
	# later; rank1 frost slows but has freeze_stacks=0, so no freeze claim.
	var summaries := ["기본 피해 12 · 화염탄 1발","기본 피해 10 · 관통 2회 · 적 이동 속도 -20%","기본 피해 9 · 3대상 연쇄 · 짧은 기절"]
	for i in starts.size():
		var button := starts[i] as Button
		# The portrait follows whichever start the player is looking at.
		# Mouse-over and keyboard focus are one state: hovering takes the focus, and the focus selects the witch.
		button.focus_entered.connect(menu_select_skill.bind(START_SKILLS[i]))
		button.mouse_entered.connect(button.grab_focus)
		button.reparent(choices);button.custom_minimum_size.y=88
		_two_line_choice(button,String(button.text).replace("연쇄 전류으로 시작","연쇄 전류로 시작"),summaries[i],tints[i])
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_menu_portrait=portrait;_menu_starts.clear()
	for start_button in starts:_menu_starts.append(start_button as Button)
	_build_witch_summary(left)
	var space := Control.new();space.size_flags_vertical=Control.SIZE_EXPAND_FILL;body.add_child(space)
	var preferences := HBoxContainer.new();preferences.add_theme_constant_override("separation",20)
	body.add_child(preferences);motion.reparent(preferences)
	motion.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	preferences.add_child(_button("음소거 전환 [M]",func():mute_toggle.emit()))
	# Stash button, actual profile note, and any inherited production note keep
	# their original order and callbacks. The old layout spacer is discarded.
	for child in original_children:
		if child in [title,description,controls,inherited_starts,old_spacer,motion,scope]:continue
		child.reparent(body)
	scope.reparent(body);scope.add_theme_font_size_override("font_size",14)
	scope.add_theme_color_override("font_color",Palette.INK_FAINT)
	original.queue_free()
	modal.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	modal.offset_left=-680;modal.offset_right=680
	modal.offset_top=-350;modal.offset_bottom=350

# ---- chapter1/view/ui45/chapter_hud_quality45.gd ----
## Clarify enemy slow and keep pause controls compact; inherited callbacks stay.
func _card_description(card: Dictionary,run: RefCounted) -> String:
	var text: String=_card_description__q36(card,run)
	if card.get("skill_id","")=="chapter1.skill.frost":text=text.replace("이동속도 -","적 이동 속도 -")
	return text

func _growth_cards38(run: RefCounted) -> void:
	_growth_cards38__q38(run)
	var cards := modal.get_child(0).get_child(2)
	for panel in cards.get_children():
		var spacer := panel.get_child(0).get_child(4) as Control
		spacer.size_flags_vertical=Control.SIZE_EXPAND_FILL
		spacer.custom_minimum_size.y=8

func _build_modal__q45(run: RefCounted) -> void:
	_build_modal__q41(run)
	if not overlay.visible or stash_open:return
	if run.mode=="menu":
		var buttons: Array[Control]=[];_collect_focus38(modal,buttons)
		for control in buttons:
			if control is Button:control.text=control.text.replace("연쇄 전류으로 시작","연쇄 전류로 시작")
	elif run.mode=="paused":
		var box := modal.get_child(0) as VBoxContainer
		if box==null or box.get_child_count()!=4:return
		var resume := box.get_child(2) as Button
		modal.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		modal.offset_left=-420;modal.offset_right=420
		modal.offset_top=-220;modal.offset_bottom=220
		# Same frame as every other window: brass 1px, top 2px (it was 4px here only).
		modal.add_theme_stylebox_override("panel",_style(Palette.SURFACE,BRASS38))
		box.add_theme_constant_override("separation",18)
		var controls := _label("WASD / 좌클릭 이동 · Space 회피\nQ 회복약 · E 의식 · I 장비",18,Color("b9c3bb"))
		box.add_child(controls);box.move_child(controls,2)
		var hint := _label("회피 후에도 클릭한 목적지로 이동합니다.",16,Color("9ca9a1"))
		hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		box.add_child(hint);box.move_child(hint,3)
		resume.custom_minimum_size.x=260;resume.size_flags_horizontal=Control.SIZE_SHRINK_END

# ---- chapter1/view/ui46/chapter_hud_quality46.gd ----
## Presentation only; no gameplay, saving, timing, or input policy changes.
class HeroLocator46 extends Control:
	var feet := Vector2.ZERO
	var crown := Vector2.ZERO
	var danger := false
	func _draw() -> void:
		var ink := Color("ffb3a3") if danger else Color("f0d9a0")
		var shadow := Color("101315")
		# Open brackets keep the actor and nearby attack shapes unobscured.
		for side in [-1.0,1.0]:
			var points := PackedVector2Array([feet+Vector2(side*20,-8),feet+Vector2(side*24,0),feet+Vector2(side*20,8)])
			draw_polyline(points,shadow,5,true);draw_polyline(points,ink,2,true)
		var chevron := PackedVector2Array([crown+Vector2(-7,-7),crown,crown+Vector2(7,-7)])
		draw_polyline(chevron,shadow,5,true);draw_polyline(chevron,ink,2,true)
var _locator46: HeroLocator46
var _view46: WeakRef
func setup(view: Node3D) -> void:
	setup__q40(view)
	_build_upgrade_panel()
	_build_combat_bar()
	_top_row=objective.get_parent().get_parent() as Control
	_view46=weakref(view)
	_locator46=HeroLocator46.new();_locator46.name="HeroLocator46"
	_locator46.mouse_filter=Control.MOUSE_FILTER_IGNORE;_locator46.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_locator46);root.move_child(overlay,root.get_child_count()-1)

func _sync_locator46(run: RefCounted,low: bool) -> void:
	_locator46.visible=run.mode=="playing" and not overlay.visible and run.hero.hp_raw>0
	if not _locator46.visible:return
	var view := _view46.get_ref() as Node3D
	if view==null:_locator46.hide();return
	var camera := view.get_viewport().get_camera_3d()
	if camera==null:_locator46.hide();return
	var at: Vector3=view.actors.hero.global_position
	if camera.is_position_behind(at):_locator46.hide();return
	var inverse := root.get_global_transform_with_canvas().affine_inverse()
	_locator46.feet=inverse*camera.unproject_position(at+Vector3.UP*0.08)
	_locator46.crown=inverse*camera.unproject_position(at+Vector3.UP*2.15)
	_locator46.danger=low;_locator46.queue_redraw()

func sync__q46(run: RefCounted,delta: float) -> void:
	sync__q40(run,delta)
	if run.hero.is_empty():return
	var low: bool= run.hero.hp_raw>0 and float(run.hero.hp_raw)/maxf(1,float(run.hero.max_hp_raw))<=0.35
	_sync_locator46(run,low)
	status.text=("위험 · " if low else "")+status.text
	status.add_theme_color_override("font_color",Color("ffb3a3") if low else Palette.INK)
	if run.potions==0:dash.text+=" · 회복약 없음"
	elif low:dash.text+=" · Q로 회복"
	dash.add_theme_color_override("font_color",Color("ffcc9e") if low or run.potions==0 else Palette.INK)

func _build_result40(run: RefCounted) -> void:
	_build_result40__q40(run)
	_add_growth_box(run)
	_add_flow_actions(run)
	if profile_note!="검증 실행 · 저장 비활성":return
	var controls: Array[Control]=[];_collect_focus38(modal,controls)
	for control in controls:
		if control is Button and control.text in ["보상 저장 다시 확인","보관함에서 다음 장비 선택"]:
			control.hide();control.disabled=true;control.focus_mode=Control.FOCUS_NONE
	_rewrite_diagnostic46(modal)

func _rewrite_diagnostic46(node: Node) -> void:
	if node is Label and node.text=="보유 장비는 보관함에서 확인하고 다음 도전에 장착할 수 있습니다.":
		node.text="검증 실행에서 획득한 장비와 보상은 저장되지 않습니다."
	for child in node.get_children():_rewrite_diagnostic46(child)

# ---- chapter1/view/ui47/chapter_hud_quality47.gd ----
## Expose existing potion eligibility; never buffer input or alter cooldown.
func sync__q47(run: RefCounted,delta: float) -> void:
	sync__q46(run,delta)
	if run.hero.is_empty():return
	if run.mode=="playing" and run._champion_id>0 and run.enemies.has(run._champion_id):
		var champion: Dictionary=run.enemies[run._champion_id]
		boss_bar.visible=champion.hp_raw>0
		if champion.hp_raw>0:
			_route_hint40.text="봉인 수호자 · %s를 처치하세요"%_champion_title(champion,"수호자")
			objective.text="%s · %02d:%02d\n수호자 생명 %d / %d"%[_champion_title(champion,"봉인 수호자"),run.tick/3600,(run.tick/60)%60,ceili(float(champion.hp_raw)/256),ceili(float(champion.max_hp_raw)/256)]
	var remaining: int=maxi(0,int(run._next_potion)-int(run.tick))
	if run.potions>0 and remaining>0:
		dash.text=dash.text.replace(" · Q로 회복","")
		dash.text+=" · 회복 대기 %.1f초"%(float(remaining)/60.0)

func _build_modal(run: RefCounted) -> void:
	_build_modal__q45(run)
	if run.mode=="choice" and not stash_open:
		var box := modal.get_child(0) as VBoxContainer
		if box!=null and box.get_child_count()>1 and box.get_child(1) is Label:
			box.get_child(1).text="기술을 선택하세요. 선택 중에는 전투와 Q 회복이 멈춥니다."
	_add_flow_buttons(run)

# ---- chapter1/view/ui50/chapter_hud_quality50.gd ----
## Share the unchanged heading font within this HUD. No gameplay or callback changes.
var _heading50: SystemFont
func _label(text: String,size: int=18,color: Color=Color("e0d8c7")) -> Label:
	var label := Label.new()
	label.text=text
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	if size>=25:
		if _heading50==null:
			_heading50=SystemFont.new()
			_heading50.font_names=PackedStringArray(["Batang","바탕","Georgia"])
		label.add_theme_font_override("font",_heading50)
	return label

# ---- chapter1/view/ui51/chapter_hud_quality51.gd ----
const Route51=preload("res://chapter1/view/ui51/chapter_route51.gd")
func sync(run: RefCounted,delta: float) -> void:
	sync__q47(run,delta)
	_sync_flow(run,delta)
	if is_instance_valid(skill_panel) and skill_panel.visible and run.mode not in ["menu","victory","defeat"]:skill_panel.visible=false
	_sync_upgrade(run,delta)
	if is_instance_valid(combat_bar):combat_bar.sync(run,delta)
	_sync_chrome(run)
	if run.hero.is_empty() or run.mode!="playing" or run.objective().entered:return
	var waypoint_: Dictionary=Route51.waypoint(run)
	var target: Vector2=waypoint_.position
	_route_hint40.text="%s까지 %.0fm · 금빛 방향 표시를 따라 이동"%[waypoint_.stage,run.hero.position.distance_to(target)]

## Screen furniture that depends on the mode: the in-play plates are hidden on the title menu and the stash, the champion bar
## carries its name, and the toast keeps below the champion bar.
## The guardian's name from the key the core gives it (enemy.champion.<zone>.name); `fallback` when it has none.
func _champion_title(champion: Dictionary,fallback: String) -> String:
	var key := String(champion.get("title_key",""))
	return Loc.t(key) if not key.is_empty() else fallback

## The goal plate title and line from objective() (kind, numbers, title_key). The core makes no sentence.
func _goal_title(goal: Dictionary) -> String:
	if String(goal.kind)=="champion" and not String(goal.title_key).is_empty():return Loc.t(String(goal.title_key))
	return Loc.t("zone.%d.name"%int(goal.zone))

func _goal_text(goal: Dictionary) -> String:
	match String(goal.kind):
		"move":return Loc.t("hud.objective.move")
		"champion":return "%d / %d"%[int(goal.hp),int(goal.hp_max)]
	return Loc.t("hud.objective.seal_kills",{"done":str(int(goal.done)),"total":str(int(goal.total))})

func _sync_chrome(run: RefCounted) -> void:
	if is_instance_valid(_top_row):_top_row.visible=not (run.mode=="menu" or stash_open)
	if is_instance_valid(boss_name):
		boss_name.visible=boss_bar.visible and run.mode=="playing"
		if boss_name.visible and run._champion_id>0 and run.enemies.has(run._champion_id):
			boss_name.text=_champion_title(run.enemies[run._champion_id],"봉인 수호자")
	if is_instance_valid(boss_bar) and is_instance_valid(toast):
		toast.position.y=maxf(80.0,boss_bar.get_rect().end.y+10.0) if boss_bar.visible else 80.0

func _style_boss_bar() -> void:
	var fill := StyleBoxFlat.new();fill.bg_color=Palette.THREAT_DEEP
	fill.border_color=Palette.THREAT;fill.border_width_top=1
	var back := StyleBoxFlat.new();back.bg_color=Color(.03,.035,.04,.92)
	back.border_color=Palette.BRASS_DIM;back.set_border_width_all(1);back.set_content_margin_all(1)
	boss_bar.add_theme_stylebox_override("fill",fill);boss_bar.add_theme_stylebox_override("background",back)

# ---- loot grammar v2: stash helper and the better-item prompt ----
## True when any equip slot of the saved profile holds this stored item.
func _stash_worn(storage_id: int) -> bool:
	for slot in profile_state.get("equipped",{}):
		if int(profile_state.equipped[slot])==storage_id:return true
	return false

const UPGRADE_SECONDS := 9.0
## Notice slot (A2 3.5): bottom right, right of the combat bar (its right edge is x 1230 of 1600) and below y 720, so no
## notice ever covers the central 60 percent of the field. The first-gear notice and the better-gear prompt share it.
const NOTICE_WIDTH := 336.0
const NOTICE_HEIGHT := 152.0
const NOTICE_MARGIN := 24.0
const NOTICE_BOTTOM := 20.0
## Text column inside a notice: slot width - margins (14+14) - sigil (56) - gap (12).
const NOTICE_TEXT_WIDTH := 240.0
var upgrade_uid := -1
var _top_row: Control
var _upgrade_panel: PanelContainer
var _upgrade_left := 0.0

## Pins a notice panel to the slot; it grows up and left if its content is larger than the slot.
func _place_notice(panel: Control,height: float) -> void:
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.grow_horizontal=Control.GROW_DIRECTION_BEGIN;panel.grow_vertical=Control.GROW_DIRECTION_BEGIN
	panel.offset_right=-NOTICE_MARGIN;panel.offset_left=-NOTICE_MARGIN-NOTICE_WIDTH
	panel.offset_bottom=-NOTICE_BOTTOM;panel.offset_top=-NOTICE_BOTTOM-height

func _notice_style(border: Color) -> StyleBoxFlat:
	var frame := _style(Color(.055,.06,.065,.97),border);frame.set_content_margin_all(14)
	return frame

func _build_upgrade_panel() -> void:
	_upgrade_panel=PanelContainer.new();_upgrade_panel.name="UpgradePrompt"
	_upgrade_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_place_notice(_upgrade_panel,NOTICE_HEIGHT)
	_upgrade_panel.visible=false
	root.add_child(_upgrade_panel);root.move_child(overlay,root.get_child_count()-1)

## Announce a pickup that is better than what is worn. Ordinary pickups stay silent.
func offer_upgrade(candidate: Dictionary,current: Dictionary,slot: String) -> void:
	if not is_instance_valid(_upgrade_panel):return
	for child in _upgrade_panel.get_children():_upgrade_panel.remove_child(child);child.queue_free()
	var color: Color=QUALITY_COLORS.get(candidate.get("quality","common"),Color.WHITE)
	_upgrade_panel.add_theme_stylebox_override("panel",_notice_style(color.darkened(.15)))
	var row := HBoxContainer.new();row.add_theme_constant_override("separation",12);_upgrade_panel.add_child(row)
	row.add_child(_sigil(candidate))
	var column := VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(column)
	var header := _label("더 좋은 장비 · "+String(SLOT_NAMES.get(slot,slot))+" · "+String(QUALITY_NAMES.get(candidate.quality,"")),14,color)
	header.autowrap_mode=TextServer.AUTOWRAP_OFF;column.add_child(header)
	var name_label := _label(String(candidate.name),20,Palette.INK);name_label.autowrap_mode=TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;name_label.custom_minimum_size.x=NOTICE_TEXT_WIDTH;name_label.tooltip_text=String(candidate.name);column.add_child(name_label)
	var summary := "빈 슬롯에 착용" if current.is_empty() else _upgrade_delta(candidate,current)
	# Gains and losses both stay on screen: the line wraps instead of cutting the loss off (the slot grows upward, still below y 720 up to three lines).
	var change := _label(summary,14,Color("b9d4b0"));change.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	change.custom_minimum_size.x=NOTICE_TEXT_WIDTH;change.tooltip_text=summary;column.add_child(change)
	var hint := _label("[F] 바로 착용  ·  [I] 비교",14,Color("bcb5a5"));hint.autowrap_mode=TextServer.AUTOWRAP_OFF;column.add_child(hint)
	upgrade_uid=int(candidate.uid);_upgrade_left=UPGRADE_SECONDS;_upgrade_panel.visible=true

func _upgrade_delta(candidate: Dictionary,current: Dictionary) -> String:
	var difference: Dictionary={}
	var mine: Dictionary=candidate.get("stats",{});var worn: Dictionary=current.get("stats",{})
	for key in mine:
		var value := int(mine[key])-int(worn.get(key,0))
		if value!=0:difference[key]=value
	for key in worn:
		if not mine.has(key) and int(worn[key])!=0:difference[key]=-int(worn[key])
	if difference.is_empty():return "능력치 변화 없음"
	return _delta_text38(difference).replace("\n"," · ")

func clear_upgrade() -> void:
	upgrade_uid=-1;_upgrade_left=0.0
	if is_instance_valid(_upgrade_panel):_upgrade_panel.visible=false

func _sync_upgrade(run: RefCounted,delta: float) -> void:
	if upgrade_uid<0:return
	# One notice slot: while the first-gear notice is up, the better-gear prompt waits (its 9 s do not run down).
	var slot_busy: bool=is_instance_valid(_discovery) and _discovery.visible
	if run.mode=="playing" and not slot_busy:_upgrade_left-=delta
	# The prompt goes away once the item is worn, lost, or the offer has aged out.
	if _upgrade_left<=0 or not run.equip_slot_of(upgrade_uid).is_empty() or run.mode in ["menu","victory","defeat"]:
		clear_upgrade();return
	_upgrade_panel.visible=run.mode=="playing" and not slot_busy
	_upgrade_panel.modulate.a=clampf(_upgrade_left/.5,0,1)

# ---- layout A: bottom-centre combat bar ----
const CombatBar=preload("res://chapter1/view/hud/combat_bar.gd")
var combat_bar: Control

## Replace the scattered bottom boxes with one centred bar. The old dock stays in
## the tree, hidden, because earlier layers still write its labels every frame.
func _build_combat_bar() -> void:
	var old_dock: Node=life_seal38.get_parent()
	if old_dock is Control:old_dock.visible=false
	combat_bar=CombatBar.new();combat_bar.name="CombatBar"
	root.add_child(combat_bar)
	# Prompts sit above the bar, and modal screens above everything.
	# Top: a compact place-and-time plate on the left, the route and the current
	# goal under the buttons on the right, so the left half of the field stays open.
	var goal_plate: Control=objective.get_parent()
	goal_plate.custom_minimum_size.x=0;goal_plate.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	goal_plate.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	objective.custom_minimum_size.x=300;objective.add_theme_font_size_override("font_size",17)
	# Same brass frame as the bottom bar plate (ART-PLAN 2.4): brass edge, brighter top line.
	for plate in [goal_plate,_route40]:
		var brass_frame: StyleBoxFlat=plate.get_theme_stylebox("panel").duplicate()
		brass_frame.border_color=BRASS38;brass_frame.set_border_width_all(1);brass_frame.border_width_top=2
		plate.add_theme_stylebox_override("panel",brass_frame)
	_route40.custom_minimum_size.x=0
	_route40.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_route40.grow_horizontal=Control.GROW_DIRECTION_BEGIN
	_route40.offset_right=-28;_route40.offset_left=-28;_route40.offset_top=70;_route40.offset_bottom=70
	root.move_child(overlay,root.get_child_count()-1)

# ---- G1 permanent growth (P4): menu summary, skill-tree screen host, result growth box ----
## Read-only toward the core. The screen asks through signals; chapter_one.gd answers with the profile's public
## functions (commit_tree, respec) and pushes the fresh data back with show_skill_tree / update_skill_tree.
const SkillTreePanel=preload("res://chapter1/view/hud/skill_tree_panel.gd")
const ProfileData=preload("res://chapter1/core/chapter_profile.gd")
const START_SKILLS=["chapter1.skill.ember","chapter1.skill.frost","chapter1.skill.arc"]
const WITCH_NAMES=["잿불의 마녀","서리의 마녀","뇌우의 마녀"]
const PORTRAIT_KEYS=["ember","frost","storm"]
const GROWTH_FILL_SECONDS := 1.2
signal skill_tree_open(character_id: String)
signal skill_tree_commit(character_id: String,ranks: Dictionary)
signal skill_tree_respec(character_id: String)
## {character_id: profile.character_view(id)}; {} entries when the profile is off or not ready. Set by the app.
var character_views: Dictionary={}
var growth_result: Dictionary={}
var skill_panel: Control
var _skill_character := ""
var _menu_witch := 0
var _menu_starts: Array[Button]=[]
var _menu_portrait: TextureRect
var _menu_tree_button: Button
var _menu_badge: Label
var _menu_name: Label
var _menu_xp: Label
var _menu_bar: ProgressBar
var _menu_points: Label
var _growth_played := false

func _character_for_skill(skill_id: String) -> String:
	for entry in ProfileData.progression_doc().get("characters",[]):
		if String(entry.signature_skill_id)==skill_id:return String(entry.id)
	return ""

func _commas(n: int) -> String:
	var text := str(absi(n));var out := ""
	for i in text.length():
		if i>0 and (text.length()-i)%3==0:out+=","
		out+=text[i]
	return ("-" if n<0 else "")+out

## The witch the menu is looking at follows the start button that has focus or the mouse (same as the portrait).
func menu_select_skill(skill_id: String) -> void:
	var index := START_SKILLS.find(skill_id)
	if index<0:return
	_menu_witch=index
	if is_instance_valid(_menu_portrait):_menu_portrait.texture=WitchPortraits[index]
	_refresh_witch_summary()

func _build_witch_summary(column: VBoxContainer) -> void:
	var panel := PanelContainer.new();panel.name="WitchGrowth";panel.size_flags_horizontal=Control.SIZE_FILL
	var frame := _style(Color("111416"),Palette.BRASS_DIM);frame.set_content_margin_all(10);frame.border_width_top=1
	panel.add_theme_stylebox_override("panel",frame);column.add_child(panel)
	var box := VBoxContainer.new();box.add_theme_constant_override("separation",3);panel.add_child(box)
	_menu_name=_label("",18,Palette.INK);_menu_name.autowrap_mode=TextServer.AUTOWRAP_OFF;box.add_child(_menu_name)
	_menu_xp=_label("",14,Palette.INK_DIM);_menu_xp.autowrap_mode=TextServer.AUTOWRAP_OFF;box.add_child(_menu_xp)
	_menu_bar=_bar(Palette.GROWTH,6);_menu_bar.max_value=1;box.add_child(_menu_bar)
	_menu_points=_label("",15,Palette.GROWTH);_menu_points.autowrap_mode=TextServer.AUTOWRAP_OFF;box.add_child(_menu_points)
	_menu_tree_button=_button("스킬 트리",func():_request_tree(_character_for_skill(START_SKILLS[_menu_witch])))
	_menu_tree_button.name="SkillTreeButton";_menu_tree_button.custom_minimum_size.y=44
	column.add_child(_menu_tree_button)
	_menu_badge=_label("",18,Palette.GROWTH);_menu_badge.autowrap_mode=TextServer.AUTOWRAP_OFF
	_menu_badge.mouse_filter=Control.MOUSE_FILTER_IGNORE;_menu_badge.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	_menu_badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_menu_badge.offset_right=-14;_menu_badge.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	_menu_tree_button.add_child(_menu_badge)
	_refresh_witch_summary()

## Fills the summary and the tree button from character_views. Disabled states say why, in words.
func _refresh_witch_summary() -> void:
	if not is_instance_valid(_menu_tree_button):return
	var view: Dictionary=character_views.get(_character_for_skill(START_SKILLS[_menu_witch]),{})
	_menu_name.text=WITCH_NAMES[_menu_witch]
	_menu_badge.text=""
	if view.is_empty():
		# Nothing to show: one line, no empty bar, no empty points row, no dead button.
		_menu_xp.text="영구 성장 · 저장 비활성";_menu_bar.visible=false;_menu_points.text="";_menu_points.visible=false
		_menu_tree_button.text="스킬 트리 · 저장 비활성";_menu_tree_button.disabled=true;_menu_tree_button.visible=false
		return
	_menu_points.visible=true;_menu_tree_button.visible=true
	_menu_name.text="%s  Lv %d"%[WITCH_NAMES[_menu_witch],int(view.level)]
	var capped := int(view.xp_to_next)<=0
	_menu_xp.text="최대 레벨" if capped else "경험치 %s / %s"%[_commas(int(view.xp)),_commas(int(view.xp_for_next))]
	_menu_bar.visible=true;_menu_bar.max_value=1.0
	_menu_bar.value=1.0 if capped else clampf(float(int(view.xp)-int(view.xp_level_start))/maxf(1.0,float(int(view.xp_for_next)-int(view.xp_level_start))),0,1)
	var free := int(view.points_free)
	_menu_points.text="◆ 남은 포인트 %d"%free if free>0 else "남은 포인트 0"
	_menu_points.add_theme_color_override("font_color",Palette.GROWTH if free>0 else Palette.INK_DIM)
	if bool(view.has_tree):
		_menu_tree_button.text="스킬 트리";_menu_tree_button.disabled=false
		_menu_badge.text="◆ %d"%free if free>0 else ""
	else:
		_menu_tree_button.text="스킬 트리 · 준비 중";_menu_tree_button.disabled=true

func _request_tree(character_id: String) -> void:
	if not character_id.is_empty():skill_tree_open.emit(character_id)

func _ensure_skill_panel() -> void:
	if is_instance_valid(skill_panel):return
	skill_panel=SkillTreePanel.new();skill_panel.name="SkillTreePanel";skill_panel.visible=false
	root.add_child(skill_panel)
	skill_panel.commit_requested.connect(func(ranks: Dictionary):skill_tree_commit.emit(_skill_character,ranks))
	skill_panel.respec_requested.connect(func():skill_tree_respec.emit(_skill_character))
	skill_panel.closed.connect(func(_lost: int):_close_skill_tree())

## Opens the screen for one witch. tree = the tree document, view = profile.character_view(id), info = display data
## (name, portrait, xp, xp_floor, xp_next, essence, respec_cost).
func show_skill_tree(character_id: String,tree: Dictionary,view: Dictionary,info: Dictionary) -> void:
	_ensure_skill_panel()
	_skill_character=character_id
	skill_panel.set_data(tree,view.ranks,int(view.level),int(view.points_free),info)
	skill_panel.open()

## After a confirmed investment or a reset: fresh committed state, staged state cleared.
func update_skill_tree(view: Dictionary,info: Dictionary,notice: String="") -> void:
	if not is_instance_valid(skill_panel):return
	skill_panel.set_data(skill_panel.tree,view.ranks,int(view.level),int(view.points_free),info)
	if not notice.is_empty():skill_panel.show_notice(notice)

func skill_tree_error(text: String) -> void:
	if is_instance_valid(skill_panel):skill_panel.show_error(text)

func skill_tree_is_open() -> bool:
	return is_instance_valid(skill_panel) and skill_panel.visible

func _close_skill_tree() -> void:
	if not is_instance_valid(skill_panel):return
	skill_panel.visible=false
	# Back to the button that opened it (menu or result window); the modal may have been rebuilt meanwhile.
	var back := modal.find_child("SkillTreeButton",true,false) as Button
	if back!=null and not back.disabled:back.grab_focus.call_deferred()
	else:_focus_modal38.call_deferred()

## The app hands over what the finished run did to the witch: profile views before and after the save, and the
## core's progress_summary. after is {} when the save failed (the box then says the experience is not counted).
func set_growth_result(character_id: String,before: Dictionary,after: Dictionary,progress: Dictionary,replay: bool=true) -> void:
	growth_result={} if character_id.is_empty() else {"character_id":character_id,"before":before,"after":after,"progress":progress}
	if replay:_growth_played=false

func _amount(n: int) -> String:
	return "+%d"%n if n>0 else "—"

func _add_growth_box(run: RefCounted) -> void:
	var box := modal.get_child(0) as VBoxContainer
	if box==null or box.get_child_count()<3 or not box.get_child(2) is HBoxContainer:return
	var columns := box.get_child(2) as HBoxContainer
	if growth_result.is_empty() or growth_result.before.is_empty():
		# Nothing was recorded: one line instead of an empty box (the reason is spelled out).
		var why: String=profile_note if not profile_note.is_empty() else "영구 성장은 저장된 프로필에서만 기록됩니다."
		if profile_note=="검증 실행 · 저장 비활성":why="검증 실행에서는 경험치와 포인트가 기록되지 않습니다."
		var note := _label("영구 성장 · "+why,16,Palette.INK_DIM);note.name="GrowthNote"
		box.add_child(note);box.move_child(note,columns.get_index()+1)
		return
	var panel := PanelContainer.new();panel.name="GrowthBox";panel.custom_minimum_size.x=400
	var frame := _style(Color("141719"),Palette.BRASS_DIM);frame.border_width_top=3;frame.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel",frame);columns.add_child(panel)
	var column := VBoxContainer.new();column.add_theme_constant_override("separation",7);panel.add_child(column)
	var data: Dictionary=growth_result
	var index := -1
	if not data.is_empty():
		for i in START_SKILLS.size():
			if _character_for_skill(START_SKILLS[i])==String(data.character_id):index=i
	column.add_child(_label("영구 성장" if index<0 else "영구 성장 · "+WITCH_NAMES[index],20,Palette.GROWTH))
	var before: Dictionary=data.before
	var after: Dictionary=data.after
	var progress: Dictionary=data.progress
	var saved := not after.is_empty()
	var shown: Dictionary=after if saved else before
	var gained := int(progress.get("xp_gained",0))
	var level_before := int(before.level)
	var level_after := int(shown.level) if saved else int(progress.get("level_after",level_before))
	var head := "Lv %d"%level_before if level_after==level_before else "Lv %d → Lv %d"%[level_before,level_after]
	var title_row := HBoxContainer.new();title_row.add_theme_constant_override("separation",12);column.add_child(title_row)
	var level_label := _label(head,26,Palette.INK);level_label.autowrap_mode=TextServer.AUTOWRAP_OFF;title_row.add_child(level_label)
	if level_after>level_before:
		var up := _label("▲ 레벨업 +%d"%(level_after-level_before),17,Palette.GROWTH);up.autowrap_mode=TextServer.AUTOWRAP_OFF;up.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;title_row.add_child(up)
	var bar := _bar(Palette.GROWTH,14);bar.max_value=1.0;column.add_child(bar)
	var capped := int(shown.xp_to_next)<=0 if saved else false
	var start_x := int(shown.xp_level_start)
	var next_x := int(shown.xp_for_next)
	var shown_xp := int(shown.xp)
	var target := 1.0 if capped else clampf(float(shown_xp-start_x)/maxf(1.0,float(next_x-start_x)),0,1)
	var from := target
	if saved:
		var level_start_before := int(before.xp_level_start)
		from=0.0 if level_after>level_before else clampf(float(int(before.xp)-level_start_before)/maxf(1.0,float(int(before.xp_for_next)-level_start_before)),0,1)
	var xp_text := "최대 레벨" if capped else "%s / %s"%[_commas(shown_xp),_commas(next_x)]
	column.add_child(_label("경험치 %s · 이번 판 +%d"%[xp_text,gained],16,Color("d4cdbb")))
	var sources: Dictionary=progress.get("sources",{})
	var seals: Array=sources.get("seal",[0,0,0]);var champions: Array=sources.get("champion",[0,0])
	var champion_sum := 0
	for value in champions:champion_sum+=int(value)
	var seal_line := "봉인 1 %s   봉인 2 %s   봉인 3 %s"%[_amount(int(seals[0])),_amount(int(seals[1])),_amount(int(seals[2]))]
	column.add_child(_label(seal_line,15,Palette.INK_DIM))
	column.add_child(_label("수호자 %s   우두머리 %s   완주 %s"%[_amount(champion_sum),_amount(int(sources.get("boss",0))),_amount(int(sources.get("victory",0)))],15,Palette.INK_DIM))
	if saved:
		var per_level := int(ProfileData.progression_doc().get("points_per_level",1))
		var total_points := int(after.points_earned)-int(before.points_earned)
		var from_levels := (level_after-level_before)*per_level
		var line := "얻은 포인트 +%d"%total_points
		if total_points>0:line+=" (레벨 +%d · 첫 처치 +%d)"%[from_levels,total_points-from_levels]
		column.add_child(_label(line,16,Palette.INK))
		var free := int(after.points_free)
		column.add_child(_label("◆ 남은 포인트 %d"%free if free>0 else "남은 포인트 0",17,Palette.GROWTH if free>0 else Palette.INK_DIM))
	else:
		column.add_child(_label("▲ 경험치 미반영 · 보상 저장 다시 확인",16,Palette.WARN))
	var space := Control.new();space.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(space)
	var character_id := String(data.character_id)
	var tree_button := _button("스킬 트리",func():_request_tree(character_id))
	tree_button.name="SkillTreeButton"
	if not bool(before.has_tree):tree_button.text="스킬 트리 · 준비 중";tree_button.disabled=true
	elif not saved:tree_button.disabled=true
	elif int(after.points_free)>0:
		var badge := _label("◆ %d"%int(after.points_free),18,Palette.GROWTH);badge.autowrap_mode=TextServer.AUTOWRAP_OFF;badge.mouse_filter=Control.MOUSE_FILTER_IGNORE
		badge.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;badge.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);badge.offset_right=-14;tree_button.add_child(badge)
	column.add_child(tree_button)
	# The gold bar fills from the old value to the new one (1.2 s) once the window is on screen; reduced motion or a
	# rebuild of the same result shows the final value at once.
	if _growth_played or not motion_enabled or from>=target:
		bar.value=target
	else:
		bar.value=from
		var wait := .25
		if run.mode=="victory":wait=maxf(0.0,1.3-_victory_age)+.15
		elif _result_reason!="abandoned":wait=maxf(0.0,DEFEAT_REVEAL-_defeat_age)+.25
		var tween := bar.create_tween()
		tween.tween_interval(wait)
		tween.tween_property(bar,"value",target,GROWTH_FILL_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_growth_played=true

# ---- D4-U run flow (pause, result buttons, confirm windows) and D5-U refused-save notice ----
## Presentation only. Every button asks through a signal; chapter_one.gd decides and acts. All text here is a key (Loc.t).
const Loc=preload("res://chapter1/view/loc.gd")
const FlowDialog=preload("res://chapter1/view/hud/flow_dialog.gd")
## The defeat window comes up this long after the fall (the scene stays on screen). An abandoned run shows it at once.
const DEFEAT_REVEAL := 1.2
## Set by the app: the finished run's rewards are not saved although saving is on (F8).
var result_unsaved := false
var _result_reason := ""
var _defeat_age := 0.0
var _flow_prev_mode := ""
var _flow_dialog: Control
var _flow_kind := ""
var _flow_focus: WeakRef
var _notice_closed := false

func _reset_flow() -> void:
	_result_reason="";result_unsaved=false;_defeat_age=0.0;_flow_prev_mode="";_notice_closed=false;_flow_focus=null
	_close_dialog(false)

## "abandoned" after the player gave up the run; "" otherwise. Call before the core ends the run.
func set_result_reason(reason: String) -> void:
	_result_reason=reason;invalidate()

## True once the result window is on screen (before that the R key and the window's buttons do nothing).
func result_revealed() -> bool:
	return overlay.visible

func flow_dialog_open() -> bool:
	return is_instance_valid(_flow_dialog)

func _app() -> Object:
	return _view46.get_ref() if _view46!=null else null

func _sync_flow(run: RefCounted,delta: float) -> void:
	if run.mode!=_flow_prev_mode:
		if run.mode=="defeat":_defeat_age=0.0
		_flow_prev_mode=run.mode
	if run.mode=="defeat":
		_defeat_age+=maxf(delta,0.0)
		if not stash_open and _result_reason!="abandoned":
			var shown := _defeat_age>=DEFEAT_REVEAL
			if overlay.visible!=shown:
				overlay.visible=shown
				if shown:_focus_modal38.call_deferred()
	var app: Object=_app()
	var rejected: bool=app!=null and app.has_method("profile_rejected") and app.profile_rejected()
	if not rejected:_notice_closed=false
	if is_instance_valid(_flow_dialog):
		if _flow_kind in ["notice","fresh"]:
			if run.mode!="menu" or not rejected:_close_dialog(true)
		elif not _dialog_alive(_flow_kind,run.mode):_close_dialog(true)
	elif rejected and run.mode=="menu" and not _notice_closed and not stash_open and overlay.visible and not skill_tree_is_open():
		_open_notice()

# ---- windows over the modal ----

## Which run modes each window may live in (decided by what the window asks, not by when it was opened):
## abandon / quit confirmations only while paused; "unsaved:*" only on a result window. The refused-save windows
## (notice, fresh) are handled in _sync_flow (menu and a refused save).
func _dialog_alive(kind: String,mode: String) -> bool:
	if kind in ["abandon","quit"]:return mode=="paused"
	if kind.begins_with("unsaved:"):return mode in ["victory","defeat"]
	return true

func _dialog_text(text: String,size: int=19) -> Label:
	return _label(text,size,Palette.INK_DIM)

func _open_dialog(kind: String,spec: Dictionary) -> void:
	if not is_instance_valid(_flow_dialog):
		var owner := root.get_viewport().gui_get_focus_owner()
		_flow_focus=weakref(owner) if owner!=null else null
	_close_dialog(false)
	var dialog: Control=FlowDialog.new();dialog.name="FlowDialog"
	dialog.setup(self,spec)
	dialog.chosen.connect(_on_flow_chosen.bind(kind))
	root.add_child(dialog)
	_flow_dialog=dialog;_flow_kind=kind
	dialog.focus_default.call_deferred()

func _close_dialog(return_focus: bool) -> void:
	if is_instance_valid(_flow_dialog):
		var old: Control=_flow_dialog
		if old.get_parent()!=null:old.get_parent().remove_child(old)
		old.queue_free()
	_flow_dialog=null;_flow_kind=""
	if not return_focus:return
	var back: Object=_flow_focus.get_ref() if _flow_focus!=null else null
	_flow_focus=null
	if back is Control and is_instance_valid(back) and back.is_inside_tree() and back.is_visible_in_tree():back.grab_focus.call_deferred()
	else:_focus_modal38.call_deferred()

func _on_flow_chosen(id_: String,kind: String) -> void:
	match kind:
		"abandon":
			_close_dialog(id_!="go")
			if id_=="go":abandon_request.emit()
		"quit":
			_close_dialog(id_!="go")
			if id_=="go":quit_request.emit()
		"notice":
			match id_:
				"open":profile_open_folder.emit()
				"play":
					_close_dialog(false);profile_play_without_save.emit();_focus_modal38.call_deferred()
				"fresh":_open_fresh()
				"quit":quit_request.emit()
				_:
					_notice_closed=true;_close_dialog(true)
		"fresh":
			match id_:
				"resume":
					_close_dialog(false);profile_start_fresh.emit(true)
				"empty","go":
					_close_dialog(false);profile_start_fresh.emit(false)
				_:_open_notice()
		_:
			# "unsaved:<what comes next>": retry | menu | quit
			var next := kind.get_slice(":",1)
			match id_:
				"save":
					_close_dialog(true);save_retry.emit()
				"go":
					_close_dialog(false);_emit_leave(next)
				_:_close_dialog(true)

func _save_mode() -> String:
	var app: Object=_app()
	if app==null:return "on"
	if app.get("profile")!=null and bool(app.profile.available):return "on"
	return "verify" if bool(app.get("_profile_off")) else "off"

func _ask_abandon() -> void:
	var body_key: String={"on":"flow.abandon.body","verify":"flow.abandon.body_verify"}.get(_save_mode(),"flow.abandon.body_nosave")
	_open_dialog("abandon",{"width":720,"title":Loc.t("flow.abandon.title"),"content":_dialog_text(Loc.t(body_key)),
		"buttons":[{"id":"go","text":Loc.t("flow.abandon.confirm")},{"id":"cancel","text":Loc.t("flow.button.cancel")}],"default_id":"cancel","esc_id":"cancel"})

func _ask_quit() -> void:
	var saving := _save_mode()=="on"
	_open_dialog("quit",{"width":720,"title":Loc.t("flow.quit.title"),"content":_dialog_text(Loc.t("flow.quit.body" if saving else "flow.quit.body_nosave")),
		"buttons":[{"id":"go","text":Loc.t("flow.quit.confirm" if saving else "flow.quit.confirm_nosave")},{"id":"cancel","text":Loc.t("flow.button.cancel")}],"default_id":"cancel","esc_id":"cancel"})

## The rewards of the finished run are not saved. `next` is what the player wanted: "retry", "menu" or "quit".
## The app calls this too when the save fails during a quit.
func ask_unsaved(next: String="quit") -> void:
	_open_dialog("unsaved:"+next,{"width":760,"title":Loc.t("flow.unsaved.title"),"content":_dialog_text(Loc.t("flow.unsaved.body")),
		"buttons":[{"id":"save","text":Loc.t("flow.unsaved.retry")},{"id":"go","text":Loc.t("flow.unsaved.quit" if next=="quit" else "flow.unsaved.continue")},{"id":"cancel","text":Loc.t("flow.button.cancel")}],
		"default_id":"cancel","esc_id":"cancel"})

func _emit_leave(next: String) -> void:
	match next:
		"retry":retry.emit()
		"menu":menu_return.emit()
		"quit":quit_request.emit()

## From a result-window button. Nothing happens before the window is on screen (F10); unsaved rewards are asked about (F8).
func _leave(next: String) -> void:
	if not result_revealed() or flow_dialog_open():return
	if result_unsaved:ask_unsaved(next);return
	_emit_leave(next)

## The R key and the result buttons come here: what the player wants next is "retry", "menu" or "quit".
func request_leave(next: String) -> void:
	_leave(next)

func _add_flow_actions(_run: RefCounted) -> void:
	var box := modal.get_child(0) as VBoxContainer
	if box==null or box.get_child_count()<4:return
	var title := box.get_child(0) as Label
	var actions := box.get_child(box.get_child_count()-1) as HBoxContainer
	var old_retry: Button=null
	if actions!=null and actions.get_child_count()>=2:old_retry=actions.get_child(actions.get_child_count()-1) as Button
	if title==null or old_retry==null or old_retry is CheckButton:
		push_error("result window layout changed: flow buttons not added");return
	if _result_reason=="abandoned":title.text=Loc.t("result.title.abandoned")
	actions.remove_child(old_retry);old_retry.queue_free()
	var retry_button := _button(Loc.t("result.button.retry"),func():_leave("retry"));retry_button.name="RetrySameWitch"
	retry_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;actions.add_child(retry_button)
	var second := HBoxContainer.new();second.name="ResultFlowActions";second.add_theme_constant_override("separation",14);box.add_child(second)
	var menu_button := _button(Loc.t("result.button.menu"),func():_leave("menu"));menu_button.name="ReturnToMenu"
	menu_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;second.add_child(menu_button)
	var quit_button := _button(Loc.t("result.button.quit"),func():_leave("quit"));quit_button.name="QuitGame"
	quit_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;second.add_child(quit_button)

func _add_flow_buttons(run: RefCounted) -> void:
	if not overlay.visible or stash_open:return
	if run.mode=="paused":
		var box := modal.get_child(0) as VBoxContainer
		if box==null:return
		var after := -1
		for i in box.get_child_count():
			var child := box.get_child(i)
			if child is Button and not child is CheckButton:after=i;break # the first plain button of the pause window is "resume"
		if after<0:
			push_error("pause window layout changed: flow buttons not added");return
		var row := HBoxContainer.new();row.name="PauseFlowActions";row.add_theme_constant_override("separation",14)
		row.size_flags_horizontal=Control.SIZE_SHRINK_END
		var abandon_button := _button(Loc.t("hud.pause.abandon"),func():_ask_abandon());abandon_button.name="AbandonRun";row.add_child(abandon_button)
		var quit_button := _button(Loc.t("hud.pause.quit"),func():_ask_quit());quit_button.name="QuitGame";row.add_child(quit_button)
		box.add_child(row);box.move_child(row,after+1)
		modal.offset_top=-280;modal.offset_bottom=280
	elif run.mode=="menu":
		var body := modal.find_child("StartChoices41",true,false) as VBoxContainer
		if body==null:return
		for child in body.get_children():
			if child is HBoxContainer and child.get_child_count()>0 and child.get_child(0) is CheckButton:
				var quit_button := _button(Loc.t("menu.quit"),func():quit_request.emit());quit_button.name="QuitGame"
				child.add_child(quit_button);break

# ---- refused save notice (D5-U) ----

func show_profile_notice() -> void:
	_notice_closed=false
	_open_notice()

## One key/value pair as two grid cells; the grid aligns the columns, so no width is fixed to a text length.
func _fact_row(grid: GridContainer,key: String,value: String,anywhere: bool,size: int=18,color: Color=Palette.INK) -> void:
	var key_label := _label(key,size,Palette.INK_DIM);key_label.autowrap_mode=TextServer.AUTOWRAP_OFF
	grid.add_child(key_label)
	var value_label := _label(value,size,color);value_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	value_label.autowrap_mode=TextServer.AUTOWRAP_ARBITRARY if anywhere else TextServer.AUTOWRAP_WORD_SMART
	value_label.tooltip_text=value;grid.add_child(value_label)

## Local date and time of a Unix time, "2026-11-17 14:05".
func _local_stamp(unix: int) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias",0))
	var d := Time.get_datetime_dict_from_unix_time(unix+bias*60)
	return "%04d-%02d-%02d %02d:%02d"%[d.year,d.month,d.day,d.hour,d.minute]

func _open_notice() -> void:
	var app: Object=_app()
	if app==null or not app.has_method("profile_reject_info"):return
	var info: Dictionary=app.profile_reject_info()
	if info.is_empty():return
	var kind := String(info.get("kind",""))
	var resume: Dictionary=info.get("resume",{})
	var content := VBoxContainer.new();content.add_theme_constant_override("separation",10)
	content.add_child(_dialog_text(Loc.t("profile.reject.body")))
	var grid := GridContainer.new();grid.columns=2;grid.add_theme_constant_override("h_separation",16);grid.add_theme_constant_override("v_separation",8);content.add_child(grid)
	_fact_row(grid,Loc.t("profile.reject.place"),String(info.get("path","")),true)
	_fact_row(grid,Loc.t("profile.reject.cause"),Loc.t("profile.reject.cause."+(kind if kind in ["damaged","incompatible","legacy"] else "unknown")),false)
	var reason := String(info.get("reason",""))
	if not reason.is_empty():_fact_row(grid,"",Loc.t("profile.reject.detail",{"reason":reason}),true,15,Palette.INK_FAINT)
	if kind!="legacy":
		var copies := Loc.t("profile.reject.resume_none")
		if not resume.is_empty():copies=Loc.t("profile.reject.resume_found",{"n":Loc.num(int(resume.revision)),"date":_local_stamp(int(resume.unix))})
		_fact_row(grid,Loc.t("profile.reject.row.copies"),copies,false)
	_open_dialog("notice",{"width":900,"title":Loc.t("profile.reject.title"),"content":content,
		"buttons":[{"id":"open","text":Loc.t("profile.reject.open_folder")},{"id":"play","text":Loc.t("profile.reject.play_without")},
			{"id":"fresh","text":Loc.t("profile.reject.start_fresh")},{"id":"quit","text":Loc.t("profile.reject.quit")}],
		"default_id":"play","esc_id":"cancel"})

## Second window of "start a new save": says what is and is not carried over, then asks once more.
func _open_fresh() -> void:
	var app: Object=_app()
	if app==null or not app.has_method("profile_reject_info"):return
	var info: Dictionary=app.profile_reject_info()
	var kind := String(info.get("kind",""))
	var resume: Dictionary=info.get("resume",{})
	var has_resume := not resume.is_empty() and kind!="legacy"
	var body_key := "profile.fresh.body_legacy" if kind=="legacy" else ("profile.fresh.body_resume" if has_resume else "profile.fresh.body_empty")
	var args := {}
	if has_resume:args={"n":Loc.num(int(resume.revision)),"date":_local_stamp(int(resume.unix))}
	var buttons: Array=[]
	if has_resume:
		buttons.append({"id":"resume","text":Loc.t("profile.fresh.continue")});buttons.append({"id":"empty","text":Loc.t("profile.fresh.empty")})
	else:buttons.append({"id":"go","text":Loc.t("profile.fresh.go")})
	buttons.append({"id":"back","text":Loc.t("profile.fresh.back")})
	_open_dialog("fresh",{"width":820,"title":Loc.t("profile.fresh.title"),"content":_dialog_text(Loc.t(body_key,args)),
		"buttons":buttons,"default_id":"back","esc_id":"back"})
