extends RefCounted
## Flattened by tools/dev/flatten_chain.py from chapter1/view/ui51/chapter_hud_quality51.gd.
## Methods named x__tag are the earlier layers of x; calls between them were super calls.

# ---- chapter1/view/cloister_hud.gd ----
## UI consumes run state; only explicit signals request core transitions.
signal start(primary: String)
signal choice(token: String, card_id: String)
signal grace_reroll(token: String)
signal grace_banish(token: String, card_id: String)
signal grace_hold(token: String, card_id: String)
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
var victory_title := "티폰을 처치했습니다"
const SKILL_NAMES={"chapter1.skill.ember":"파이어볼","chapter1.skill.frost":"아이스 스피어","chapter1.skill.arc":"체인 라이트닝"}
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
	theme.default_font=Loc.font("body")
	theme.default_font_size=17
	root.theme=theme
	var top := MarginContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left=28;top.offset_right=-28;top.offset_top=24
	root.add_child(top)
	var row := HBoxContainer.new()
	top.add_child(row)
	objective=_label("카테나",20,Color("ded8c4"))
	objective.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(objective)
	var item_button := _button(Loc.t("hud.button.equipment"),func():equipment.emit())
	row.add_child(item_button)
	row.add_child(_button(Loc.t("hud.button.pause"),func():pause_toggle.emit()))
	row.add_child(_button(Loc.t("hud.button.mute"),func():mute_toggle.emit()))
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
	modal.add_theme_stylebox_override("panel",UiStyle.window())
	overlay.add_child(modal)

func _bar(color: Color, height: float) -> ProgressBar:
	return UiStyle.bar(color,height)

# ---- write-on-change helpers (T2b A-1) ----
# Setting a label's text, a theme colour or a position to the value it already has still costs the engine a layout pass
# (a theme override always announces "theme changed"). Every visible piece is composed once per frame in _compose_frame and
# goes through these, so an unchanged frame writes nothing.
var _frame_growth: Dictionary={}
var _toast_y_last := -1.0e9
var _route_state_last: Array[int]=[-1,-1,-1]
func _set_text(control: Control,value: String) -> void:
	if control.text!=value:control.text=value

func sync__cloister(run: RefCounted, delta: float) -> void:
	_toast_left=maxf(0,_toast_left-delta)
	var signature: String=run.mode
	if run.mode=="choice": signature+=_choice_signature(_frame_growth.get("offer",{}))
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
	# The old bottom dock (status, hp, xp, level38, life_seal38, dash and the skill chips) is hidden for good since the combat
	# bar replaced it (_build_combat_bar), and nothing shows it again, so it is no longer written. The hidden summary
	# label and the F1 diagnostic keep their six-tick refresh.
	var g: Dictionary=_frame_growth
	var texts: Array[String]=[]
	for id_ in g.ranks:
		var d: Dictionary=run.effective_skill(id_)
		texts.append((Loc.t(String(d.name_key)) if d.evolved else SKILL_NAMES.get(id_,id_))+" %d" % d.rank)
	_set_text(skills,"   /   ".join(texts))
	if debug.visible:_set_text(debug,"tick %d · alive %d · projectiles %d · XP %d\nF1 진단 화면" % [run.tick,run.alive_count(),run.projectiles.size(),g.xp])

## N1, the one-line band at the top (A10 1.7). A newer line replaces the one on screen; while a big band (N1+) is up the line waits for it.
const TOAST_TOTAL := Motion.NOTICE_IN+Motion.NOTICE_HOLD_BAND+Motion.NOTICE_OUT
var _pending_toast := ""
func notify(text: String) -> void:
	if is_instance_valid(_big_band) and not _big_band.finished:
		_pending_toast=text;return
	_show_toast(text)

func _show_toast(text: String) -> void:
	toast.text=text;_toast_left=TOAST_TOTAL
	var width := NoticeParts.band_width(text)
	toast.offset_left=-width*.5;toast.offset_right=width*.5

## N1+, the big band (A10 1.7): the title plaque with `title` and the taller band under it with `sub` (may be ""). kind "boss" lights the plaque once in the threat
## colour. One at a time: a newer one takes the older away at once; the one-line band is gone while it is up and the last line asked for comes back after it.
var _big_band: Control
func announce(kind: String,title: String,sub: String="") -> void:
	if not is_instance_valid(root):return
	_clear_big_band()
	_toast_left=0.0
	var band: Control=NoticeParts.BigBand.new()
	band.name="BigBand"
	band.build(title,sub,kind=="boss")
	var top := 96.0
	if is_instance_valid(boss_bar) and boss_bar.visible and is_instance_valid(boss_name):top=maxf(top,boss_name.get_rect().end.y+10.0)
	band.anchor_left=.5;band.anchor_right=.5
	band.offset_left=-band.size.x*.5;band.offset_right=band.size.x*.5
	band.offset_top=top;band.offset_bottom=top+band.size.y
	root.add_child(band)
	root.move_child(band,maxi(0,overlay.get_index()))
	band.play(not motion_enabled)
	band.done.connect(_on_big_band_done)
	_big_band=band

func _on_big_band_done() -> void:
	_big_band=null
	if _pending_toast!="":
		var text := _pending_toast;_pending_toast="";_show_toast(text)

func _clear_big_band() -> void:
	if is_instance_valid(_big_band):_big_band.dismiss()
	_big_band=null;_pending_toast=""

func _build_modal__cloister(run: RefCounted) -> void:
	for child in modal.get_children():modal.remove_child(child);child.queue_free()
	# The descent's cut-in (mode "descent") is the fx layer's picture, not a window: no modal panel for it.
	overlay.visible=run.mode!="playing" and run.mode!="descent"
	if not overlay.visible:return
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",16)
	modal.add_child(box)
	match run.mode:
		"inventory": _inventory(box,run)
		"victory","defeat":
			box.add_child(_label(victory_title if run.mode=="victory" else "카테나에 쓰러졌습니다",32,Color("e5ca94")))
			box.add_child(_label("%d 처치 · 레벨 %d · 획득 장비 %d개" % [run.kills,run.growth.snapshot().level,run.inventory.size()],20))
			box.add_child(_label("다른 기술과 장비 조합으로 다시 도전할 수 있습니다.",18))
			box.add_child(_button("다시 도전",func():retry.emit()))
			if run.mode=="victory":box.add_child(_button("획득 장비 확인",func():equipment.emit()))

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
			"chain_targets":result.append("체인 라이트닝 대상 +%d" % value)
			"shatter_count":result.append("아이스 스피어 랭크4 / 진화의 파쇄 파편 +%d" % value)
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
## Bound look: the bar is the glass of the kit's frame (385 x 16.5 inside a 550 x 58.75 frame), the name sits in the plate under it.
func _boss_width() -> float:return 385.0 if UiStyle.bound() else BOSS_BAR_WIDTH
func _boss_height() -> float:return 16.5 if UiStyle.bound() else BOSS_BAR_HEIGHT
func _boss_top() -> float:return 70.0 if UiStyle.bound() else BOSS_BAR_TOP
func _boss_name_shift() -> float:return 64.8
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
	victory_title="제1장 · "+Loc.t("enemy.champion.2.name")+"을 처치했습니다"
func setup__chapter(view: Node3D) -> void:
	setup__cloister(view)
	boss_bar=_bar(Palette.THREAT_DEEP,_boss_height());boss_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_style_boss_bar()
	boss_bar.offset_left=-_boss_width()*.5;boss_bar.offset_right=_boss_width()*.5;boss_bar.offset_top=_boss_top();boss_bar.offset_bottom=_boss_top()+_boss_height();boss_bar.visible=false;root.add_child(boss_bar)
	boss_name=_label("",18,Palette.INK);boss_name.autowrap_mode=TextServer.AUTOWRAP_OFF;boss_name.mouse_filter=Control.MOUSE_FILTER_IGNORE
	boss_name.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;boss_name.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	boss_name.add_theme_constant_override("outline_size",4);boss_name.add_theme_color_override("font_outline_color",Color(0,0,0,.85))
	boss_name.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	boss_name.offset_left=-_boss_width()*.5;boss_name.offset_right=_boss_width()*.5;boss_name.offset_top=_boss_top()-28.0+(_boss_name_shift() if UiStyle.bound() else 0.0);boss_name.offset_bottom=_boss_top()-3.0+(_boss_name_shift() if UiStyle.bound() else 0.0)
	boss_name.visible=false;root.add_child(boss_name)
func sync__chapter(run: RefCounted,delta: float) -> void:
	# The goal plate, the champion bar and the dock text are composed once per frame in _compose_frame (called from sync()).
	sync__cloister(run,delta)
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
	if run.mode in ["victory","defeat"]:
		var box: VBoxContainer=modal.get_child(0)
		box.add_child(_button("장비 보관함 · %d개"%profile_state.get("items",[]).size(),func():stash_show.emit()))
		if not profile_note.is_empty():box.add_child(_label(profile_note,14,Color("b4b49d")))
		if run.mode in ["victory","defeat"]:box.add_child(_button("보상 저장 다시 확인",func():save_retry.emit()))

func _build_stash__chapter() -> void:
	for child in modal.get_children():modal.remove_child(child);child.queue_free()
	overlay.visible=true
	var box := VBoxContainer.new();box.add_theme_constant_override("separation",12);modal.add_child(box)
	box.add_child(_label("장비 보관함 · %d / 256"%profile_state.get("items",[]).size(),29,Color("e3cd9d")))
	box.add_child(_label("다음 도전에 가져갈 장비를 슬롯별로 선택하세요. 해체는 해당 장비를 오리칼쿰으로 바꿉니다.",16))
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
		details.add_child(_button("해체하여 오리칼쿰으로 전환",func():_storage_selection=-1;stash_salvage.emit(id_)))
	box.add_child(_label(Loc.t("currency.essence")+" %d · 완료한 도전 %d · %s"%[profile_state.get("essence",0),profile_state.get("completed_runs",0),profile_note],14))
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
const UiStyle=preload("res://chapter1/view/hud/ui_style.gd")
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
	_place_notice(_discovery,NOTICE_HEIGHT_FIRST)
	_discovery.add_theme_stylebox_override("panel",_notice_style(Palette.QUALITY_UNIQUE))
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
	text.add_child(_label(Loc.t("hud.notice.unique_found",{"slot":SLOT_NAMES[item.slot]}),14,Palette.QUALITY_UNIQUE))
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
			column.add_child(_label(Loc.t("enemy.champion.2.name")+"의 전리품 · 고유 장비",14,Palette.QUALITY_UNIQUE))
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
		_discovery.modulate.a=minf(clampf((DISCOVERY_TOTAL-_discovery_left)/Motion.NOTICE_IN,0,1),clampf(_discovery_left/Motion.NOTICE_OUT,0,1))
		_notice_slide(_discovery,DISCOVERY_TOTAL-_discovery_left)
## N2 timing (A10 1.7): in 0.18 (sliding in 24 px from the right), the card holds 3.2, out 0.4.
const DISCOVERY_TOTAL := Motion.NOTICE_IN+Motion.NOTICE_HOLD_CARD+Motion.NOTICE_OUT
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
	_place_notice(_discovery,NOTICE_HEIGHT_FIRST)
	_discovery.add_theme_stylebox_override("panel",_notice_style(color.darkened(.2)))
	var row := HBoxContainer.new();row.add_theme_constant_override("separation",12);_discovery.add_child(row)
	row.add_child(NoticeParts.icon(item))
	var column := VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_theme_constant_override("separation",2);row.add_child(column)
	var header := "고유 장비 획득" if item.quality=="unique" else ("전설 장비 획득" if item.quality=="legendary" else ("첫 희귀 장비" if item.quality=="rare" else "첫 마법 장비"))
	var header_label := UiStyle.text_label(header+" · "+SLOT_NAMES[item.slot],"t7","bold");header_label.autowrap_mode=TextServer.AUTOWRAP_OFF;column.add_child(header_label)
	var name_label := UiStyle.text_label(item.name,"t4","body",NoticeParts.name_color(item));name_label.custom_minimum_size.x=NOTICE_TEXT_WIDTH;name_label.autowrap_mode=TextServer.AUTOWRAP_OFF;name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;name_label.tooltip_text=item.name;column.add_child(name_label)
	column.add_child(NoticeParts.key_hint("I",Loc.t("hud.notice.card_hint")))
	_settle_discovery20(row)
	_discovery_left=DISCOVERY_TOTAL;_discovery20_gap=DISCOVERY_TOTAL+1.2
	_discovery20_name=item.name
	discovery20_history.append({"uid":item.uid,"quality":item.quality,"slot":item.slot,"name":item.name})
## The 24 px slide of a card coming in: `elapsed` since it appeared. Offsets are only touched while it moves.
func _notice_slide(panel: Control,elapsed: float) -> void:
	if elapsed>Motion.NOTICE_IN+0.05:return
	var dx := (1.0-clampf(elapsed/Motion.NOTICE_IN,0.0,1.0))*24.0 if motion_enabled else 0.0
	panel.offset_right=-NOTICE_MARGIN+dx;panel.offset_left=-NOTICE_MARGIN-NOTICE_WIDTH+dx

func _settle_discovery20(row: Control) -> void:
	# A temporary wrapped-label minimum can enlarge a PanelContainer; smaller
	# children do not automatically shrink its previous rect after replacement.
	for i in 2:await root.get_tree().process_frame
	if is_instance_valid(row) and row.get_parent()==_discovery:_place_notice(_discovery,NOTICE_HEIGHT_FIRST)
func reset() -> void:
	clear_upgrade()
	_bf_clear()
	if _playlog!=null and _view46!=null and _view46.get_ref()!=null:_playlog.begin_run(_view46.get_ref().run)
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

# ---- chapter1/view/chapter_hud_quality27.gd ----
## Keep temporary combat messages below the champion/boss health bar.
func sync__q27(run: RefCounted,delta: float) -> void:
	sync__q23(run,delta)
	# The toast position is placed once per frame at the end of _sync_chrome.

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

## Frames, buttons and labels are built by ui_style.gd (A4 US); this class only asks.
func _style(color: Color, border: Color=BRASS38) -> StyleBoxFlat:
	return UiStyle.flat(color,border)

func _button(text: String, action: Callable) -> Button:
	return UiStyle.button(text,action)

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
			UiStyle.compact_button_faces(child)
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
	toast.add_theme_color_override("font_color",Palette.INK)
	toast.add_theme_font_size_override("font_size",20)
	toast.autowrap_mode=TextServer.AUTOWRAP_OFF
	toast.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	toast.custom_minimum_size.y=52
	toast.add_theme_stylebox_override("normal",NoticeParts.band_box())
	old_bottom.queue_free()
	# Keep overlays above the replacement dock, and retain boss/toast layering.
	root.move_child(overlay,root.get_child_count()-1)
	modal.offset_left=90;modal.offset_right=-90;modal.offset_top=104;modal.offset_bottom=-76
	modal.add_theme_stylebox_override("panel",UiStyle.window())
	overlay.color=Color(.025,.035,.045,.87)

func _plate_style38() -> StyleBox:
	return UiStyle.plate()

func _backplate38() -> PanelContainer:
	var panel := PanelContainer.new();panel.add_theme_stylebox_override("panel",_plate_style38())
	# Presentation backing must never swallow a world movement click.
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return panel

func sync__q38(run: RefCounted,delta: float) -> void:
	sync__q27(run,delta)
	# (The old dock's life seal, status and level lines are hidden and no longer written; the toast is placed once in _sync_chrome.)

func _build_modal__q38(run: RefCounted) -> void:
	var previous := overlay.visible
	if not previous:
		var owner := root.get_viewport().gui_get_focus_owner()
		if owner!=null:_focus_return38=weakref(owner)
	_build_modal__q17(run)
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.offset_left=90;modal.offset_right=-90;modal.offset_top=104;modal.offset_bottom=-76
	if overlay.visible:
		if run.mode=="inventory" and not stash_open:
			modal.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
			modal.offset_left=-680;modal.offset_right=680;modal.offset_top=-300;modal.offset_bottom=300
		_decorate38(modal)
		_focus_modal38.call_deferred()
	elif previous and _focus_return38!=null:
		var owner = _focus_return38.get_ref()
		if is_instance_valid(owner):owner.grab_focus.call_deferred()

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
	# The text scrolls; the equip button sits below the scroll area so it is always on screen.
	var outer := VBoxContainer.new();outer.add_theme_constant_override("separation",10);panel.add_child(outer)
	var scroll := ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
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
	outer.add_child(equip_button)

func _delta_text38(stats: Dictionary) -> String:
	if stats.is_empty():return Loc.t("hud.notice.no_change")
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
	for i in buttons.size():
		var b := buttons[i]
		b.focus_next=b.get_path_to(buttons[(i+1)%buttons.size()])
		b.focus_previous=b.get_path_to(buttons[(i+buttons.size()-1)%buttons.size()])
	var first: Control=buttons[0]
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
	# The route labels and the hint are composed in _compose_frame (only while this plate is visible).

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
	option.add_theme_stylebox_override("focus",UiStyle.focus_mark())
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
	box.add_child(_label(Loc.t("currency.essence")+" %d · 완료한 도전 %d\n%s"%[profile_state.get("essence",0),profile_state.get("completed_runs",0),profile_note if not profile_note.is_empty() else "저장 상태 확인 중"],15,Palette.INK_DIM))
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
	details.add_child(_label("해체하면 장비가 사라지고 오리칼쿰으로 전환됩니다.",14,Color("bca58f")))

func _restore_stash40(scroll: ScrollContainer,position_: int) -> void:
	for i in 2:await root.get_tree().process_frame
	if is_instance_valid(scroll) and scroll==_stash_scroll40:scroll.scroll_vertical=position_

func _reset_stash_filter40() -> void:
	_stash_offset40=0;_stash_reset_scroll40=true;invalidate()

func _build_result40__q40(run: RefCounted) -> void:
	var box := _clear_modal40()
	var victorious: bool=run.mode=="victory"
	box.add_child(_label("카테나의 서약을 완수했습니다" if victorious else "이번 도전이 끝났습니다",32,Palette.INK))
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
		names.add_child(_label(Loc.t("enemy.champion.2.name")+"의 전리품",15,Palette.QUALITY_UNIQUE));names.add_child(_label(elite_item.name,23,Palette.INK))
	else:rewards.add_child(_label("보유 장비는 보관함에서 확인하고 다음 도전에 장착할 수 있습니다.",18))
	rewards.add_child(_label("저장 상태",17,Color("a8baaa")))
	rewards.add_child(_label(profile_note if not profile_note.is_empty() else "저장 상태 확인 중",17))
	rewards.add_child(_button("보상 저장 다시 확인",func():save_retry.emit()))
	var actions := HBoxContainer.new();actions.add_theme_constant_override("separation",14);box.add_child(actions)
	var stash_button := _button("보관함에서 다음 장비 선택",func():stash_show.emit());stash_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;actions.add_child(stash_button)
	if victorious:
		var inspect_button := _button("이번 도전 장비 확인",func():equipment.emit());inspect_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;actions.add_child(inspect_button)
	var retry_button := _button("다시 도전",func():retry.emit());retry_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;actions.add_child(retry_button)

# ---- chapter1/view/ui45/chapter_hud_quality45.gd ----
## Clarify enemy slow and keep pause controls compact; inherited callbacks stay.
func _card_description(card: Dictionary,run: RefCounted) -> String:
	var text: String=_card_description__q36(card,run)
	if card.get("skill_id","")=="chapter1.skill.frost":text=text.replace("이동속도 -","적 이동 속도 -")
	return text

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
const PlayRecorder=preload("res://chapter1/view/hud/play_recorder.gd")
var _playlog: Node
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
	# Play log (off unless --chapter1-playlog is given): a read-only child node, see play_recorder.gd.
	_playlog=PlayRecorder.attach(root,view)

func _sync_locator46(run: RefCounted,low: bool) -> void:
	var was_shown := _locator46.visible
	_locator46.visible=run.mode=="playing" and not overlay.visible and run.hero.hp_raw>0
	if not _locator46.visible:return
	if not was_shown:_locator46.queue_redraw()
	var view := _view46.get_ref() as Node3D
	if view==null:_locator46.hide();return
	var camera := view.get_viewport().get_camera_3d()
	if camera==null:_locator46.hide();return
	var at: Vector3=view.actors.hero.global_position
	if camera.is_position_behind(at):_locator46.hide();return
	var inverse := root.get_global_transform_with_canvas().affine_inverse()
	var feet: Vector2=inverse*camera.unproject_position(at+Vector3.UP*0.08)
	var crown: Vector2=inverse*camera.unproject_position(at+Vector3.UP*2.15)
	# Redraw only when a mark moved or the danger colour flipped.
	if feet==_locator46.feet and crown==_locator46.crown and low==_locator46.danger:return
	_locator46.feet=feet;_locator46.crown=crown;_locator46.danger=low;_locator46.queue_redraw()

func sync__q46(run: RefCounted,delta: float) -> void:
	sync__q40(run,delta)
	if run.hero.is_empty():return
	var low: bool= run.hero.hp_raw>0 and float(run.hero.hp_raw)/maxf(1,float(run.hero.max_hp_raw))<=0.35
	_sync_locator46(run,low)
	# (The old dock's status and dash lines, and their colours, are hidden and no longer written.)

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
	# (The potion wait text belonged to the hidden dash label; the visible plates are composed in _compose_frame.)

func _build_modal(run: RefCounted) -> void:
	if run.mode=="choice" and not stash_open:
		_build_grace_screen(run);return
	if run.mode=="paused" and not stash_open:
		# the pause window is up and nothing about it changed: keep it (a rebuild would replay its opening)
		if not (is_instance_valid(_pause_screen) and not _pause_screen.closing):_build_pause_screen()
		return
	# The first screen (T13): one screen for the whole menu; a stash window over the menu hides it (it comes back when the stash is closed).
	if run.mode=="menu" and not stash_open:
		_build_title_screen();return
	if run.mode!="menu":_free_title_screen()
	_free_grace_screen()
	if run.mode!="paused":_grace_token_shown=""   # a pause keeps it: the same offer shown again after Esc has no second intro
	_build_modal__q40(run)

# ---- the grace screen (A8 G6): the choice window is chapter1/view/hud/screens/growth_choice.gd on a contract ----
## The host's part only (T8 3): ask the adapter for the contract when the window is rebuilt, apply it, hand the signals on. Nothing here decides anything.
var _grace_screen: Control
var _grace_token_shown := ""
var _overlay_base := Color(0,0,0,-1)

## Window identity: the offer token and the cards standing in it (a card taken out and refilled changes it).
func _choice_signature(offer: Dictionary) -> String:
	var out: String=String(offer.get("token",""))
	for card in offer.get("cards",[]):out+="|"+String(card.id)
	return out

func _free_grace_screen() -> void:
	if is_instance_valid(_grace_screen):_grace_screen.queue_free()
	_grace_screen=null
	_close_pause_screen()
	if _overlay_base.a>=0.0:
		overlay.color=_overlay_base;modal.visible=true;_overlay_base=Color(0,0,0,-1)

func _build_grace_screen(run: RefCounted) -> void:
	if is_instance_valid(_grace_screen):_grace_screen.queue_free()
	_grace_screen=null
	if _overlay_base.a<0.0:_overlay_base=overlay.color
	# the overlay stays (it stops clicks reaching the world and other layers read it as "a window is open"); the screen draws its own dark stage
	overlay.visible=true;overlay.color=Color(0,0,0,0);modal.visible=false
	for child in modal.get_children():modal.remove_child(child);child.queue_free()
	var describe:=func(card: Dictionary) -> String:return _card_description(card,run)
	var contract: Dictionary=GraceContract.build(run,{"growth":_frame_growth,"describe":describe})
	# The adapter may have drawn the offer just now: the window's identity is the one the next frame will read.
	_last_signature="choice"+_choice_signature(run.growth.snapshot().get("offer",{}))
	if contract.get("cards",[]).is_empty():return
	var screen := GraceScreen.new()
	screen.apply(contract)
	screen.reduce_motion=not motion_enabled
	var token: String=String(contract.offer_ref)
	screen.chosen.connect(func(card_ref: String):choice.emit(token,card_ref))
	screen.reroll.connect(func():grace_reroll.emit(token))
	screen.exclude.connect(func(card_ref: String):grace_banish.emit(token,card_ref))
	screen.keep.connect(func(card_ref: String):grace_hold.emit(token,card_ref))
	root.add_child(screen)
	_grace_screen=screen
	# the same offer shown again (a card refilled, the pause closed): no second intro
	if token==_grace_token_shown:screen.show_settled()
	else:screen.play_intro()
	_grace_token_shown=token

# ---- the pause window (A10 W2): chapter1/view/hud/pause_window.gd ----
## The host's part only, like the grace screen: build it, hand its signals on. The overlay stays (it stops clicks reaching the world and other layers read it as
## "a window is open"); the window draws its own dim.
var _pause_screen: Control

func _build_pause_screen() -> void:
	_close_pause_screen()
	if _overlay_base.a<0.0:_overlay_base=overlay.color
	overlay.visible=true;overlay.color=Color(0,0,0,0);modal.visible=false
	for child in modal.get_children():modal.remove_child(child);child.queue_free()
	var screen := PauseWindow.new()
	screen.apply(motion_enabled,not motion_enabled)
	screen.resume.connect(func():pause_toggle.emit())
	screen.equipment.connect(func():equipment.emit())
	screen.abandon.connect(func():_ask_abandon())
	screen.quit_game.connect(func():_ask_quit())
	screen.motion_changed.connect(func(on: bool):motion_enabled=on;motion_toggle.emit(on))
	root.add_child(screen)
	root.move_child(screen,root.get_child_count()-1)
	_pause_screen=screen
	screen.open()
	screen.focus_default.call_deferred()

## The window goes at once as far as clicks and keys go and fades over Motion.WINDOW_OUT.
func _close_pause_screen() -> void:
	if is_instance_valid(_pause_screen):_pause_screen.close()
	_pause_screen=null

# ---- the first screen (T13 R2): chapter1/view/hud/screens/title.gd on a contract ----
## The host's part only, like the grace screen: ask the adapter for the contract when the menu is built or its words change, apply it, hand the signals on. Nothing here decides.
## One screen lives for the whole menu: a rebuild (invalidate) only applies the contract again (the focus, the clock and the portraits stay), a new screen plays its intro.
## The overlay stays (it stops clicks reaching the world and other layers read it as "a window is open", the refused-save notice reads it); the screen draws its own stage.
const TitleScreen=preload("res://chapter1/view/hud/screens/title.gd")
const TitleContract=preload("res://chapter1/view/contracts/title_contract.gd")
const TITLE_TOAST_Z := 35
const TITLE_WINDOW_Z := 40
var _title_screen: Control
var _title_menu: Control
var _title_on := false
## How often the contract of the first screen was made: when the menu is built or its words change, never per frame (a test reads it).
var title_contract_builds := 0

## What the adapter takes (title_contract.gd head). Public so that a capture tool can ask the adapter the same question.
func title_app_state() -> Dictionary:
	return {"focus_index":_menu_witch,"save":_save_mode(),"note":profile_note,"items":profile_state.get("items",[]).size(),"motion_on":motion_enabled,"character_views":character_views}

func _build_title_screen() -> void:
	if _overlay_base.a<0.0:_overlay_base=overlay.color
	overlay.visible=true;overlay.color=Color(0,0,0,0);modal.visible=false
	for child in modal.get_children():modal.remove_child(child);child.queue_free()
	title_contract_builds+=1
	var contract: Dictionary=TitleContract.build(null,title_app_state())
	if is_instance_valid(_title_screen):
		_title_screen.apply(contract)
		return
	var screen := TitleScreen.new()
	screen.apply(contract)
	screen.start.connect(_on_title_start)
	screen.witch_focused.connect(_on_title_witch)
	screen.stash.connect(func():stash_show.emit())
	screen.skill_tree.connect(_request_tree)
	screen.menu.connect(_open_title_menu)
	root.add_child(screen)
	_title_screen=screen;_title_on=true
	screen.play_intro()

func _free_title_screen() -> void:
	_close_title_menu()
	if is_instance_valid(_title_screen):_title_screen.queue_free()
	_title_screen=null;_title_on=false
	if is_instance_valid(toast) and toast.z_index!=0:toast.z_index=0

## The start came out of the confirm beat. The app may refuse it (a full stash, a refused save): then the screen opens its doors again.
func _on_title_start(skill_ref: String) -> void:
	start.emit(skill_ref)
	var app: Object=_app()
	if is_instance_valid(_title_screen) and (app==null or String(app.run.mode)=="menu"):_title_screen.show_settled()

func _on_title_witch(index: int) -> void:
	_menu_witch=index

func _open_title_menu() -> void:
	if is_instance_valid(_title_menu):return
	if is_instance_valid(_title_screen):_title_screen.set_interactive(false);_title_on=false
	var window := PauseWindow.new()
	window.z_index=TITLE_WINDOW_Z
	window.apply(motion_enabled,not motion_enabled,"title")
	window.resume.connect(_close_title_menu)
	window.quit_game.connect(func():quit_request.emit())
	window.motion_changed.connect(func(on: bool):motion_enabled=on;motion_toggle.emit(on);invalidate())
	root.add_child(window)
	root.move_child(window,root.get_child_count()-1)
	_title_menu=window
	window.open()
	window.focus_default.call_deferred()

func _close_title_menu() -> void:
	if is_instance_valid(_title_menu):_title_menu.close()
	_title_menu=null

## Once per frame: the screen is shown in the menu (not over the stash window) and takes keys and mouse only when nothing is over it (the skill tree, a notice or
## confirm window, its own Esc window). The notice band (toast) is lifted over it. The screen draws up to z 30 (its flash 25, its blackout 28, a few parts 30), the skill
## tree sits at z 20: the band goes to z 35 and the windows that open over the screen (Esc window, notice and confirm windows) to z 40.
func _sync_title(run: RefCounted) -> void:
	if not is_instance_valid(_title_screen):return
	var shown: bool=run.mode=="menu" and not stash_open
	if _title_screen.visible!=shown:_title_screen.visible=shown
	var want: bool=shown and not skill_tree_is_open() and not flow_dialog_open() and not is_instance_valid(_title_menu)
	if want!=_title_on:
		_title_screen.set_interactive(want);_title_on=want
	var lift := TITLE_TOAST_Z if shown else 0
	if is_instance_valid(toast) and toast.z_index!=lift:toast.z_index=lift

## The witch the first screen looks at follows the start of this skill (the app's first focus, a capture tool). A screen that stands answers with its focus.
func menu_select_skill(skill_id: String) -> void:
	var index := START_SKILLS.find(skill_id)
	if index<0:return
	_menu_witch=index
	if is_instance_valid(_title_screen):
		_title_screen.set_focus(index)
		_menu_witch=_title_screen.focused_index()

func menu_witch_index() -> int:
	return _menu_witch

## The character the screen looks at ("" for an index outside the three).
func menu_character_id() -> String:
	if _menu_witch<0 or _menu_witch>=START_SKILLS.size():return ""
	return _character_for_skill(START_SKILLS[_menu_witch])

## The screen at once in its settled state, no intro (a capture or test tool; also the way back after the app refused a start).
func title_settle() -> void:
	if is_instance_valid(_title_screen):_title_screen.show_settled()

func title_screen() -> Control:
	return _title_screen if is_instance_valid(_title_screen) else null

# ---- chapter1/view/ui50/chapter_hud_quality50.gd ----
## Share the unchanged heading font within this HUD. No gameplay or callback changes.
func _label(text: String,size: int=18,color: Color=Color("e0d8c7")) -> Label:
	return UiStyle.label(text,size,color)

# ---- chapter1/view/ui51/chapter_hud_quality51.gd ----
const Route51=preload("res://chapter1/view/ui51/chapter_route51.gd")
func sync(run: RefCounted,delta: float) -> void:
	# One growth snapshot (a deep copy) per frame, shared with the combat bar and the six-tick summary.
	_frame_growth=run.growth.snapshot() if not run.hero.is_empty() else {}
	sync__q47(run,delta)
	_bf_tick(run,delta)
	if _playlog!=null:_playlog.observe(run,_frame_growth)
	_compose_frame(run)
	_sync_flow(run,delta)
	if is_instance_valid(skill_panel) and skill_panel.visible and run.mode not in ["menu","victory","defeat"]:skill_panel.visible=false
	_sync_upgrade(run,delta)
	if is_instance_valid(combat_bar):combat_bar.sync(run,delta,_frame_growth)
	_sync_chrome(run)

## The visible plates, composed once per frame from the final values and written only when they differ from what is
## on screen: the goal plate, the champion bar, the route labels and hint. The text and the priority between the old
## layers are the ones the stacked sync__q* functions used to produce (a later layer overrode an earlier one):
## goal plate: goal line, plus the ritual prompt and the pending-rewards note, replaced by the champion line (playing,
## champion alive); route hint: seal distance or last-seal line < champion line (playing, champion alive) < waypoint
## (playing, zone not entered).
func _compose_frame(run: RefCounted) -> void:
	if run.hero.is_empty():return
	var goal: Dictionary=run.objective()
	var playing: bool=run.mode=="playing"
	var champion: Dictionary={}
	var champion_here: bool=run._champion_id>0 and run.enemies.has(run._champion_id)
	if champion_here:champion=run.enemies[run._champion_id]
	var champion_live: bool=playing and champion_here and champion.hp_raw>0
	var minutes: String="%02d:%02d"%[run.tick/3600,(run.tick/60)%60]
	# Goal plate.
	var objective_text: String
	if champion_live and String(goal.kind)!="boss":
		objective_text=Loc.t("hud.objective.champion_status",{"title":_champion_title(champion,Loc.t("hud.champion.fallback")),"time":minutes,"hp":str(ceili(float(champion.hp_raw)/256)),"max":str(ceili(float(champion.max_hp_raw)/256))})
	else:
		objective_text="%s · %s\n%s"%[_goal_title(goal),minutes,_goal_text(goal)]
		for def in run.RITUALS:
			if def.zone==run.zone and run.rituals[def.id].state=="ready" and run.hero.position.distance_squared_to(def.position)<=3*3:
				objective_text+="\n[E] "+Loc.t("ritual.%s.name"%def.id)+" · 선택 보상"
		if not run.pending_rewards.is_empty():objective_text+=" · 보관 대기 %d"%run.pending_rewards.size()
	_set_text(objective,objective_text)
	# Champion bar: the visible flag and the value are final here (the champion's hp is zero for a moment before it is removed).
	var bar_visible: bool=champion_here and (champion.hp_raw>0 if playing else true)
	if boss_bar.visible!=bar_visible:boss_bar.visible=bar_visible
	if champion_here:
		if boss_bar.max_value!=champion.max_hp_raw:boss_bar.max_value=champion.max_hp_raw
		if boss_bar.value!=champion.hp_raw:boss_bar.value=champion.hp_raw
	# Route plate: three names (text and colour change only when a seal opens or the zone changes) and the hint line.
	if not _route40.visible:return
	for i in 3:
		var cleared: bool=i<run.seals.size() and bool(run.seals[i].get("cleared",false))
		var current: bool=i==int(goal.zone)
		var state: int=2 if cleared else (1 if current else 0)
		if state!=_route_state_last[i]:
			_route_state_last[i]=state
			_route_labels40[i].text=("✓ " if cleared else ("◆ " if current else "○ "))+Loc.t("zone.%d.name"%i)
			_route_labels40[i].add_theme_color_override("font_color",Color("a8baaa") if cleared else (Color("efdaa6") if current else Palette.INK_DIM))
	var hint: String
	if playing and not bool(goal.entered):
		var waypoint_: Dictionary=Route51.waypoint(run)
		var target: Vector2=waypoint_.position
		hint=Loc.t("hud.route.waypoint",{"stage":String(waypoint_.stage),"meters":"%.0f"%run.hero.position.distance_to(target)})
	elif champion_live:
		hint=Loc.t("hud.route.champion",{"name":_champion_title(champion,Loc.t("hud.champion.short"))})
	elif not bool(goal.entered):
		var destination: Vector2=goal.destination
		hint=Loc.t("hud.route.next_seal",{"meters":"%.0f"%run.hero.position.distance_to(destination)})
	else:hint=Loc.t("hud.route.last_seal") if int(goal.boss_phase)>0 else Loc.t("hud.route.break_seal")
	_set_text(_route_hint40,hint)

## Screen furniture that depends on the mode: the in-play plates are hidden on the title menu and the stash, the champion bar
## carries its name, and the toast keeps below the champion bar.
## The guardian's name from the key the core gives it (enemy.champion.<zone>.name); `fallback` when it has none.
func _champion_title(champion: Dictionary,fallback: String) -> String:
	var key := String(champion.get("title_key",""))
	return Loc.t(key) if not key.is_empty() else fallback

## The goal plate title and line from objective() (kind, numbers, title_key). The core makes no sentence.
func _goal_title(goal: Dictionary) -> String:
	var kind := String(goal.kind)
	if kind=="trial":return Loc.t("hud.objective.trial.title")
	if (kind=="champion" or kind=="boss") and not String(goal.title_key).is_empty():return Loc.t(String(goal.title_key))
	return Loc.t("zone.%d.name"%int(goal.zone))

func _goal_text(goal: Dictionary) -> String:
	match String(goal.kind):
		"move":return Loc.t("hud.objective.move")
		"champion","boss":return "%d / %d"%[int(goal.hp),int(goal.hp_max)]
		"trial":return Loc.t("hud.objective.trial_left",{"sec":str(ceili(float(goal.done)/60.0))})
	return Loc.t("hud.objective.seal_kills",{"done":str(int(goal.done)),"total":str(int(goal.total))})

func _sync_chrome(run: RefCounted) -> void:
	_sync_title(run)
	var mark := 0
	if run.seals.size()>2 and bool(run.seals[2].get("cleared",false)):mark=2
	elif run._champion_id>0 and run.zone==2 and run.enemies.has(run._champion_id):mark=1
	if mark!=_boss_mark:
		_boss_mark=mark
		if is_instance_valid(_route40):_route40.queue_redraw()
	if is_instance_valid(_top_row):_top_row.visible=not (run.mode=="menu" or stash_open)
	if is_instance_valid(boss_name):
		boss_name.visible=boss_bar.visible and run.mode=="playing"
		if boss_name.visible and run._champion_id>0 and run.enemies.has(run._champion_id):
			_set_text(boss_name,_champion_title(run.enemies[run._champion_id],Loc.t("hud.champion.fallback")))
	if is_instance_valid(toast):
		# The toast: shown while its time runs, except when it only repeats the discovery card; kept below the champion bar.
		var toast_shown: bool=_toast_left>0
		if toast.visible!=toast_shown:toast.visible=toast_shown
		if toast_shown:toast.modulate.a=minf(clampf((TOAST_TOTAL-_toast_left)/Motion.NOTICE_IN,0.0,1.0),clampf(_toast_left/Motion.NOTICE_OUT,0.0,1.0))
		if is_instance_valid(boss_bar):
			var toast_y: float=maxf(80.0,(boss_name.get_rect().end.y+12.0 if UiStyle.bound() else boss_bar.get_rect().end.y+10.0)) if boss_bar.visible else 80.0
			if toast_y!=_toast_y_last:
				_toast_y_last=toast_y;toast.position.y=toast_y

func _style_boss_bar() -> void:
	boss_bar.add_theme_stylebox_override("fill",UiStyle.boss_fill());boss_bar.add_theme_stylebox_override("background",UiStyle.boss_back())

# ---- loot grammar v2: stash helper and the better-item prompt ----
## True when any equip slot of the saved profile holds this stored item.
func _stash_worn(storage_id: int) -> bool:
	for slot in profile_state.get("equipped",{}):
		if int(profile_state.equipped[slot])==storage_id:return true
	return false

const UPGRADE_SECONDS := Motion.NOTICE_HOLD_CARD_BEST
## Notice slot (A2 3.5): bottom right, right of the combat bar (its right edge is x 1230 of 1600) and below y 720, so no
## notice ever covers the central 60 percent of the field. The first-gear notice and the better-gear prompt share it.
const NOTICE_WIDTH := 380.0
const NOTICE_HEIGHT := 168.0
const NOTICE_HEIGHT_FIRST := 116.0
const NOTICE_MARGIN := 24.0
var NOTICE_BOTTOM := 130.0 if UiStyle.bound() else 20.0
## Text column inside a notice: slot width - margins (14+14) - sigil (56) - gap (12).
const NOTICE_TEXT_WIDTH := 248.0
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

func _notice_style(border: Color) -> StyleBox:
	return UiStyle.notice(border)

func _build_upgrade_panel() -> void:
	_upgrade_panel=PanelContainer.new();_upgrade_panel.name="UpgradePrompt"
	_upgrade_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_place_notice(_upgrade_panel,NOTICE_HEIGHT)
	_upgrade_panel.visible=false
	root.add_child(_upgrade_panel);root.move_child(overlay,root.get_child_count()-1)

## Announce a pickup the core's pickup_verdict() says to show (react card, open or auto_equip). Ordinary pickups stay silent. `verdict` is that answer: its top_rows
## are the changed numbers, each line with its arrow (gains and losses side by side); an empty verdict falls back to the text of the difference.
func offer_upgrade(candidate: Dictionary,current: Dictionary,slot: String,verdict: Dictionary={}) -> void:
	if not is_instance_valid(_upgrade_panel):return
	for child in _upgrade_panel.get_children():_upgrade_panel.remove_child(child);child.queue_free()
	var color: Color=QUALITY_COLORS.get(candidate.get("quality","common"),Color.WHITE)
	_upgrade_panel.add_theme_stylebox_override("panel",_notice_style(color.darkened(.15)))
	var row := HBoxContainer.new();row.add_theme_constant_override("separation",12);_upgrade_panel.add_child(row)
	row.add_child(NoticeParts.icon(candidate))
	var column := VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_theme_constant_override("separation",2);row.add_child(column)
	var header := UiStyle.text_label(Loc.t("hud.notice.better_gear",{"slot":String(SLOT_NAMES.get(slot,slot)),"quality":String(QUALITY_NAMES.get(candidate.quality,""))}),"t7","bold")
	header.autowrap_mode=TextServer.AUTOWRAP_OFF;column.add_child(header)
	var name_label := UiStyle.text_label(String(candidate.name),"t4","body",NoticeParts.name_color(candidate));name_label.autowrap_mode=TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;name_label.custom_minimum_size.x=NOTICE_TEXT_WIDTH;name_label.tooltip_text=String(candidate.name);column.add_child(name_label)
	var rows_box: Control=NoticeParts.change_rows(verdict.get("top_rows",[]),NOTICE_TEXT_WIDTH) if not verdict.is_empty() else null
	if rows_box!=null:column.add_child(rows_box)
	elif current.is_empty():column.add_child(UiStyle.text_label(Loc.t("hud.notice.empty_slot"),"t7","body",Palette.INK_DIM))
	elif verdict.is_empty():
		# no verdict (the pickup flow is off): the text of the difference, one wrapped line (gain and loss both stay on screen)
		var summary := _upgrade_delta(candidate,current)
		var change := UiStyle.text_label(summary,"t7","body",Palette.INK_DIM);change.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		change.custom_minimum_size.x=NOTICE_TEXT_WIDTH;change.tooltip_text=summary;column.add_child(change)
	var keys := HBoxContainer.new();keys.add_theme_constant_override("separation",14);keys.mouse_filter=Control.MOUSE_FILTER_IGNORE
	keys.add_child(NoticeParts.key_hint("F",Loc.t("hud.notice.key_wear")));keys.add_child(NoticeParts.key_hint("I",Loc.t("hud.notice.key_compare")))
	column.add_child(keys)
	upgrade_uid=int(candidate.uid);_upgrade_left=UPGRADE_SECONDS;_upgrade_panel.visible=true
	_place_notice(_upgrade_panel,NOTICE_HEIGHT)

func _upgrade_delta(candidate: Dictionary,current: Dictionary) -> String:
	var difference: Dictionary={}
	var mine: Dictionary=candidate.get("stats",{});var worn: Dictionary=current.get("stats",{})
	for key in mine:
		var value := int(mine[key])-int(worn.get(key,0))
		if value!=0:difference[key]=value
	for key in worn:
		if not mine.has(key) and int(worn[key])!=0:difference[key]=-int(worn[key])
	if difference.is_empty():return Loc.t("hud.notice.no_change")
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
	_upgrade_panel.modulate.a=minf(clampf((UPGRADE_SECONDS-_upgrade_left)/Motion.NOTICE_IN,0,1),clampf(_upgrade_left/Motion.NOTICE_OUT,0,1))
	_notice_slide(_upgrade_panel,UPGRADE_SECONDS-_upgrade_left)

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
	goal_plate.add_theme_stylebox_override("panel",UiStyle.zone_plate(goal_plate.get_theme_stylebox("panel").duplicate()))
	if UiStyle.bound():
		# The route has no plate: a rope with beads drawn on its own space, labels outlined to read on the field.
		_route40.add_theme_stylebox_override("panel",UiStyle.route_back())
		var route_texts: Array[Label]=_route_labels40.duplicate();route_texts.append(_route_hint40)
		for label in route_texts:
			label.add_theme_constant_override("outline_size",4);label.add_theme_color_override("font_outline_color",Color(0,0,0,.85))
		root.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var buttons_row: Control=objective.get_parent().get_parent()
		var pieces: Array[String]=["btn_bag","btn_book","btn_speaker"];var at_button:=0
		for child in buttons_row.get_children():
			if child is Button and at_button<pieces.size():
				UiStyle.icon_button(child,pieces[at_button],child.text);at_button+=1
	else:
		_route40.add_theme_stylebox_override("panel",UiStyle.chrome_plate(_route40.get_theme_stylebox("panel").duplicate()))
	_route40.custom_minimum_size.x=0
	_route40.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_route40.grow_horizontal=Control.GROW_DIRECTION_BEGIN
	var route_top:=96.0 if UiStyle.bound() else 70.0
	_route40.offset_right=-28;_route40.offset_left=-28;_route40.offset_top=route_top;_route40.offset_bottom=route_top
	if UiStyle.bound():
		# Pieces drawn on top of two existing controls: no node is added for them.
		boss_bar.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		boss_bar.draw.connect(_draw_boss_caps)
		_route40.draw.connect(_draw_route_marker)
	root.move_child(overlay,root.get_child_count()-1)

# ---- the final boss's finale on the champion bar (docs/specs/A-boss-finale-screen-20261125.ko.md 2, 8.2) ----
## Read only. Drawn only while the core says the finale is on (a run without it draws nothing and changes no pixel): phase ticks from the data's
## thresholds, the current segment lit, the bar locked (a chain mark, a hatch, the time strip and the seconds) while the boss is out of play
## (entrance and breaks). Shape carries the state, the colour only helps. No new palette token.
var _bf_over: Control
var _bf_secs: Label
var _bfv: Dictionary={"on":false}
var _bf_tick_now := 0
var _bf_total := 0
var _bf_lock := 0.0
var _bf_chip_t := 0.0
var _bf_chip_bps := 0
var _bf_block_t := 0.0
var _bf_struck_t := 0.0
const BF_CHIP_TIME := 0.3
const BF_BLOCK_TIME := 0.15
const BF_STRUCK_TIME := 0.4
const BF_LOCK_TIME := 0.2
## Built the first time a run with the finale shows the bar, so a run without it has no extra node on the screen.
func _build_bf_over() -> void:
	if is_instance_valid(_bf_over):return
	_bf_over=Control.new();_bf_over.name="FinaleOverlay";_bf_over.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_bf_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_bf_over.visible=false
	_bf_over.draw.connect(_draw_bf);boss_bar.add_child(_bf_over)
	_bf_secs=_label("",14,Palette.INK_DIM);_bf_secs.mouse_filter=Control.MOUSE_FILTER_IGNORE;_bf_secs.autowrap_mode=TextServer.AUTOWRAP_OFF
	_bf_secs.visible=false;_bf_over.add_child(_bf_secs)
func _bf_clear() -> void:
	_bfv={"on":false};_bf_total=0;_bf_lock=0.0;_bf_chip_t=0.0;_bf_block_t=0.0;_bf_struck_t=0.0
	if is_instance_valid(_bf_over):_bf_over.visible=false
## The finale's read-only state: the core's own view function when it has one, else the finale's fields (the same names the core keeps).
func _bf_read(run: RefCounted) -> Dictionary:
	if run.has_method("boss_finale_view"):
		var view: Variant=run.boss_finale_view()
		return view if view is Dictionary else {"on":false}
	if not bool(run.get("_bf_on")):return {"on":false}
	var th: Array=[]
	var doc: Variant=run.get("_bf")
	if doc is Dictionary:
		for rule in doc.get("phases",[]):th.append(int(rule.to_hp_bps))
	return {"on":true,"state":String(run.get("_bf_state")),"phase_index":int(run.get("_bf_phase")),"break_index":int(run.get("_bf_break")),
		"break_until_tick":int(run.get("_bf_until")),"to":run.get("_bf_to"),"chip_bps":int(run.get("_bf_chip")),"thresholds_bps":th,"shielded":int(run.get("_shield_id"))>0}
func _bf_tick(run: RefCounted,delta: float) -> void:
	if run.hero.is_empty():return
	_bfv=_bf_read(run)
	_bf_tick_now=run.tick
	var on: bool=bool(_bfv.get("on",false)) and boss_bar.visible
	if on:_build_bf_over()
	if not is_instance_valid(_bf_over):return
	if _bf_over.visible!=on:_bf_over.visible=on
	if not on:
		_bf_lock=0.0;return
	var locked: bool=String(_bfv.get("state","")) in ["entrance","break"]
	_bf_lock=move_toward(_bf_lock,1.0 if locked else 0.0,delta/BF_LOCK_TIME)
	_bf_chip_t=maxf(0.0,_bf_chip_t-delta);_bf_block_t=maxf(0.0,_bf_block_t-delta);_bf_struck_t=maxf(0.0,_bf_struck_t-delta)
	var remaining: int=maxi(0,int(_bfv.get("break_until_tick",0))-_bf_tick_now) if locked else 0
	if locked and remaining>_bf_total:_bf_total=remaining
	if is_instance_valid(_bf_secs):
		_bf_secs.visible=locked
		if locked:
			_set_text(_bf_secs,str(ceili(float(remaining)/60.0)))
			_bf_secs.position=Vector2(boss_bar.size.x+8.0,boss_bar.size.y*.5-_bf_secs.size.y*.5+3.0)
	_bf_over.queue_redraw()
## The core events the bar answers (chapter_one.gd hands them over). boss_break_struck: only its moment is used, so a later field change does not matter.
func boss_event(event: Dictionary) -> void:
	match String(event.get("type","")):
		"boss_entrance","boss_break_started":_bf_total=int(event.get("ticks",0))
		"boss_hit_blocked":_bf_block_t=BF_BLOCK_TIME
		"boss_chip":_bf_chip_t=BF_CHIP_TIME;_bf_chip_bps=int(event.get("bps",0))
		"boss_break_struck":_bf_struck_t=BF_STRUCK_TIME;_bf_block_t=0.0
func _draw_bf() -> void:
	if not bool(_bfv.get("on",false)):return
	var w:=boss_bar.size.x;var h:=boss_bar.size.y
	if w<=0.0 or boss_bar.max_value<=0.0:return
	var ratio:=clampf(float(boss_bar.value)/float(boss_bar.max_value),0.0,1.0)
	var hp_bps:=ratio*10000.0
	var ticks: Array=[]
	for t in _bfv.get("thresholds_bps",[]):
		if int(t)>0 and int(t)<10000:ticks.append(int(t))
	# The current segment is one step lighter.
	var idx: int=int(_bfv.get("phase_index",0))
	var upper: int=10000 if idx<=0 or idx-1>=ticks.size() else int(ticks[idx-1])
	var lower: int=int(ticks[idx]) if idx<ticks.size() else 0
	_bf_over.draw_rect(Rect2(w*float(lower)/10000.0,0.0,w*float(upper-lower)/10000.0,h),Color(Palette.INK.r,Palette.INK.g,Palette.INK.b,.1))
	# Locked: the filled part goes grey and is hatched (a mark that does not depend on colour).
	if _bf_lock>0.01 and ratio>0.0:
		var grey:=Palette.THREAT_DEEP.lerp(Palette.SURFACE_RAISED,.5)
		var fill_w:=w*ratio
		_bf_over.draw_rect(Rect2(0,0,fill_w,h),Color(grey.r,grey.g,grey.b,.85*_bf_lock))
		var x:=0.0
		while x+h<=fill_w:
			_bf_over.draw_line(Vector2(x,h),Vector2(x+h,0.0),Color(Palette.LINEN.r,Palette.LINEN.g,Palette.LINEN.b,.28*_bf_lock),1.0)
			x+=7.0
	# The last hit that cut the bar (boss_chip): a linen spark at the fill's end.
	if _bf_chip_t>0.0:
		var cw:=maxf(2.0,w*float(_bf_chip_bps)/10000.0)
		_bf_over.draw_rect(Rect2(w*ratio,0.0,cw,h),Color(Palette.LINEN.r,Palette.LINEN.g,Palette.LINEN.b,_bf_chip_t/BF_CHIP_TIME))
	# Phase ticks: the ones not yet passed are brass, the passed ones dim; they stand 3px out of the bar.
	for t in ticks:
		var tx:=w*float(t)/10000.0
		_bf_over.draw_rect(Rect2(tx-1.0,-3.0,2.0,h+6.0),Palette.BRASS_DIM if hp_bps<=float(t) else Palette.BRASS)
	# The chain mark at the left end while locked: two linked rings; a blocked hit lights it, a hit that got through (struck) pulls the rings apart.
	if _bf_lock>0.01:
		var spread:=3.0+(4.0*sin(PI*(1.0-_bf_struck_t/BF_STRUCK_TIME)) if _bf_struck_t>0.0 else 0.0)
		var tone:=Palette.INK if _bf_block_t>0.0 else Palette.LINEN
		var col:=Color(tone.r,tone.g,tone.b,_bf_lock)
		var c:=Vector2(-13.0,h*.5)
		_bf_over.draw_arc(c+Vector2(-spread,0),4.5,0.0,TAU,16,col,2.0,true)
		_bf_over.draw_arc(c+Vector2(spread,0),4.5,0.0,TAU,16,col,2.0,true)
		# The time strip under the bar.
		var remaining: int=maxi(0,int(_bfv.get("break_until_tick",0))-_bf_tick_now)
		var share:=clampf(float(remaining)/float(maxi(1,_bf_total)),0.0,1.0)
		_bf_over.draw_rect(Rect2(0,h+4.0,w,4.0),Color(Palette.PLATE.r,Palette.PLATE.g,Palette.PLATE.b,.9*_bf_lock))
		_bf_over.draw_rect(Rect2(0,h+4.0,w*share,4.0),Color(Palette.LINEN.r,Palette.LINEN.g,Palette.LINEN.b,_bf_lock))
		_bf_over.draw_rect(Rect2(0,h+4.0,w,4.0),Color(Palette.BRASS_DIM.r,Palette.BRASS_DIM.g,Palette.BRASS_DIM.b,_bf_lock),false,1.0)

## The kit's champion frame around the bar and the name plate under it.
func _draw_boss_caps() -> void:
	var frame := UiStyle.piece_size("boss_frame");var plate := UiStyle.piece_size("boss_name")
	var inner_top := frame.y*.36
	UiStyle.blit(boss_bar,"boss_frame",Rect2(Vector2(boss_bar.size.x*.5-frame.x*.5,-inner_top),frame))
	UiStyle.blit_centered(boss_bar,"boss_name",Vector2(boss_bar.size.x*.5,frame.y-inner_top+11.7+plate.y*.5-plate.y*.5))

## The champion's mark above the last route entry: hollow diamond = not met, filled with a ring = on the field,
## diamond with a tick = defeated. Shape carries the state; colour only helps.
var _boss_mark := 0
func _draw_route_marker() -> void:
	if _route_labels40.size()<3:return
	var entry: Label=_route_labels40[2]
	var centres: Array[float]=[]
	for label in _route_labels40:centres.append(label.global_position.x-_route40.global_position.x+label.size.x*.5)
	_route40.draw_line(Vector2(centres[0],8.0),Vector2(centres[2],8.0),Palette.BRASS_DIM,2.5,true)
	for i in 3:
		var text: String=_route_labels40[i].text
		var piece:="bead_empty"
		if text.begins_with("✓"):piece="bead_brass"
		elif text.begins_with("◆"):piece="bead_gold"
		UiStyle.blit_centered(_route40,piece,Vector2(centres[i],8.0),1.0)
	var at := entry.global_position-_route40.global_position+Vector2(entry.size.x*.5,-9.0)
	var diamond := PackedVector2Array([at+Vector2(0,-8),at+Vector2(8,0),at+Vector2(0,8),at+Vector2(-8,0)])
	match _boss_mark:
		1:
			_route40.draw_colored_polygon(diamond,Palette.THREAT)
			_route40.draw_polyline(diamond+PackedVector2Array([diamond[0]]),Palette.BRASS_HI,2.0,true)
			for side in [-1.0,1.0]:_route40.draw_line(at+Vector2(side*12,-3),at+Vector2(side*17,-7),Palette.BRASS_HI,2.0,true)
		2:
			_route40.draw_polyline(diamond+PackedVector2Array([diamond[0]]),Palette.BRASS,2.0,true)
			_route40.draw_polyline(PackedVector2Array([at+Vector2(-3,0),at+Vector2(-1,3),at+Vector2(4,-3)]),Palette.BRASS,2.0,true)
		_:
			_route40.draw_polyline(diamond+PackedVector2Array([diamond[0]]),Palette.BRASS_DIM,2.0,true)

# ---- G1 permanent growth (P4): skill-tree screen host, result growth box (the menu's summary is the first screen's: title.gd) ----
## Read-only toward the core. The screen asks through signals; chapter_one.gd answers with the profile's public
## functions (commit_tree, respec) and pushes the fresh data back with show_skill_tree / update_skill_tree.
const SkillTreePanel=preload("res://chapter1/view/hud/skill_tree_panel.gd")
const ProfileData=preload("res://chapter1/core/chapter_profile.gd")
const START_SKILLS=["chapter1.skill.ember","chapter1.skill.frost","chapter1.skill.arc"]
const WITCH_KEYS=["ember","frost","arc"]  # po keys character.<key>.name / .class, same order as START_SKILLS
static func _witch_name(index: int) -> String:return Loc.t("character.%s.name"%WITCH_KEYS[index])
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
## The witch the first screen looks at (the one that starts), by START_SKILLS index. The screen tells it through witch_focused; the app reads it through menu_character_id().
var _menu_witch := 0
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

func _request_tree(character_id: String) -> void:
	if not character_id.is_empty():skill_tree_open.emit(character_id)

func _ensure_skill_panel() -> void:
	if is_instance_valid(skill_panel):return
	skill_panel=SkillTreePanel.new();skill_panel.name="SkillTreePanel";skill_panel.visible=false
	# The menu portrait draws its veil, effects and snow at z 7..10; the panel has to sit above them.
	skill_panel.z_index=20
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
	column.add_child(_label("영구 성장" if index<0 else "영구 성장 · "+_witch_name(index),20,Palette.GROWTH))
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
const GraceScreen=preload("res://chapter1/view/hud/screens/growth_choice.gd")
const GraceContract=preload("res://chapter1/view/contracts/growth_choice_contract.gd")
const FlowDialog=preload("res://chapter1/view/hud/flow_dialog.gd")
const PauseWindow=preload("res://chapter1/view/hud/pause_window.gd")
const NoticeParts=preload("res://chapter1/view/hud/notice_parts.gd")
const Motion=preload("res://chapter1/view/hud/ui_motion.gd")
const CombatRecordView=preload("res://chapter1/view/hud/combat_record_view.gd")
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
	_close_pause_screen()
	_close_title_menu()
	_clear_big_band()

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
	if run.mode in ["menu","playing"] and not run_record.is_empty():run_record={}
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
	if kind.begins_with("unsaved:") or kind=="record":return mode in ["victory","defeat"]
	return true

func _dialog_text(text: String,size: int=17) -> Label:
	var label := UiStyle.text_label(text,"t5","body",Palette.INK_DIM)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	if size!=17:label.add_theme_font_size_override("font_size",size)
	return label

func _open_dialog(kind: String,spec: Dictionary) -> void:
	if not is_instance_valid(_flow_dialog):
		var owner := root.get_viewport().gui_get_focus_owner()
		_flow_focus=weakref(owner) if owner!=null else null
	_close_dialog(false,true)
	var dialog: Control=FlowDialog.new();dialog.name="FlowDialog"
	dialog.setup(self,spec)
	dialog.chosen.connect(_on_flow_chosen.bind(kind))
	dialog.reduce_motion=not motion_enabled
	if is_instance_valid(_title_screen):dialog.z_index=TITLE_WINDOW_Z   # the first screen draws up to z 30: a window over it has to sit above
	root.add_child(dialog)
	_flow_dialog=dialog;_flow_kind=kind
	# a confirm window asked from the pause window takes its place (one window on the screen, not a window on a window)
	if is_instance_valid(_pause_screen) and kind in ["abandon","quit"]:_pause_screen.visible=false
	dialog.open()
	dialog.focus_default.call_deferred()

func _close_dialog(return_focus: bool,instant: bool=false) -> void:
	if is_instance_valid(_flow_dialog):
		# the window leaves over Motion.WINDOW_OUT (at once when another window takes its place); from this line on it takes no click and no key
		var old: Control=_flow_dialog
		old.close(instant)
		if is_instance_valid(_pause_screen):_pause_screen.visible=true
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
		"record":_close_dialog(true)
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
	_open_dialog("abandon",{"width":600,"title":Loc.t("flow.abandon.title"),"content":_dialog_text(Loc.t(body_key)),
		"buttons":[{"id":"go","text":Loc.t("flow.abandon.confirm"),"kind":"danger"},{"id":"cancel","text":Loc.t("flow.button.cancel")}],"default_id":"cancel","esc_id":"cancel"})

func _ask_quit() -> void:
	var saving := _save_mode()=="on"
	_open_dialog("quit",{"width":600,"title":Loc.t("flow.quit.title"),"content":_dialog_text(Loc.t("flow.quit.body" if saving else "flow.quit.body_nosave")),
		"buttons":[{"id":"go","text":Loc.t("flow.quit.confirm" if saving else "flow.quit.confirm_nosave"),"kind":"danger"},{"id":"cancel","text":Loc.t("flow.button.cancel")}],"default_id":"cancel","esc_id":"cancel"})

## The rewards of the finished run are not saved. `next` is what the player wanted: "retry", "menu" or "quit".
## The app calls this too when the save fails during a quit.
func ask_unsaved(next: String="quit") -> void:
	_open_dialog("unsaved:"+next,{"width":680,"title":Loc.t("flow.unsaved.title"),"content":_dialog_text(Loc.t("flow.unsaved.body")),
		"buttons":[{"id":"save","text":Loc.t("flow.unsaved.retry"),"kind":"primary"},{"id":"go","text":Loc.t("flow.unsaved.quit" if next=="quit" else "flow.unsaved.continue"),"kind":"danger"},{"id":"cancel","text":Loc.t("flow.button.cancel")}],
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

# ---- battle record (W7 / A6-11): read-only view of the finished run's record, opened from the result window ----
## The app hands over its `run_record_view` once the run has ended ({} or {"ready":false} = nothing to show).
var run_record: Dictionary={}
var _record_level := 0

func set_run_record(view: Dictionary) -> void:
	run_record=view.duplicate(true)
	invalidate()

func has_run_record() -> bool:
	return bool(run_record.get("ready",false))

func combat_record_open() -> bool:
	return flow_dialog_open() and _flow_kind=="record"

## Opens the record over the result window. Nothing happens before the window is on screen or while another window is open.
func open_combat_record() -> void:
	if not has_run_record() or not result_revealed() or flow_dialog_open():return
	var size := root.get_viewport_rect().size
	var width := minf(size.x-140.0,1420.0)
	var body: VBoxContainer=CombatRecordView.new()
	body.setup(run_record,_record_level,width-130.0)
	# A record taller than the screen scrolls (mouse wheel); the usual record fits without.
	var scroll := ScrollContainer.new();scroll.name="RecordScroll";scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true;scroll.add_child(body)
	scroll.custom_minimum_size=Vector2(width-120.0,minf(body.get_combined_minimum_size().y,size.y-360.0))
	_fit_record_scroll.call_deferred(scroll,body,size.y-360.0)
	_open_dialog("record",{"width":width,"title":Loc.t("record.title"),"content":scroll,
		"buttons":[{"id":"close","text":Loc.t("record.close"),"kind":"primary"}],"default_id":"close","esc_id":"close"})
	# The close button keeps the focus; the arrow keys, page keys and the d-pad scroll a tall record (the mouse wheel works too).
	if is_instance_valid(_flow_dialog) and not _flow_dialog.buttons.is_empty():
		_flow_dialog.buttons[0].gui_input.connect(_scroll_record.bind(scroll))

func _scroll_record(event: InputEvent,scroll: ScrollContainer) -> void:
	if not (event is InputEventKey or event is InputEventJoypadButton) or not event.pressed or not is_instance_valid(scroll):return
	var step := 0
	if event.is_action("ui_down"):step=60
	elif event.is_action("ui_up"):step=-60
	elif event.is_action("ui_page_down"):step=int(scroll.size.y*.8)
	elif event.is_action("ui_page_up"):step=-int(scroll.size.y*.8)
	if step!=0:
		scroll.scroll_vertical+=step
		scroll.get_viewport().set_input_as_handled()

## Text that wraps only knows its height once it is in the tree, so the window is fitted to its content after the first layout.
func _fit_record_scroll(scroll: ScrollContainer,body: Control,limit: float) -> void:
	for i in 2:
		if not is_instance_valid(scroll) or not is_instance_valid(body):return
		await scroll.get_tree().process_frame
		if not is_instance_valid(scroll) or not is_instance_valid(body):return
		scroll.custom_minimum_size.y=minf(body.get_combined_minimum_size().y,limit)

func _add_flow_actions(run: RefCounted) -> void:
	_record_level=int(run.growth.snapshot().get("level",0)) if run!=null and run.growth!=null else 0
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
	# T15: what the fall was, at the top of the right column of a defeat (not shown for a victory or an abandoned run).
	# The right column is the emptier one, so the window keeps its height.
	if run!=null and run.mode=="defeat" and _result_reason!="abandoned" and box.get_child_count()>2 and box.get_child(2) is HBoxContainer and box.get_child(2).get_child_count()>1:
		var right := (box.get_child(2) as HBoxContainer).get_child(1) as VBoxContainer
		if right!=null:
			var at := 0
			for line in CombatRecordView.death_lines(run_record.get("loss",{})):
				var reason := _label(line,17,Palette.INK);reason.name="DeathReason%d"%(at+1);reason.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
				right.add_child(reason);right.move_child(reason,at);at+=1
	var retry_button := _button(Loc.t("result.button.retry"),func():_leave("retry"));retry_button.name="RetrySameWitch"
	retry_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;actions.add_child(retry_button)
	var second := HBoxContainer.new();second.name="ResultFlowActions";second.add_theme_constant_override("separation",14);box.add_child(second)
	if has_run_record():
		var record_button := _button(Loc.t("record.open"),func():open_combat_record());record_button.name="CombatRecord"
		record_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;second.add_child(record_button)
	var menu_button := _button(Loc.t("result.button.menu"),func():_leave("menu"));menu_button.name="ReturnToMenu"
	menu_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;second.add_child(menu_button)
	var quit_button := _button(Loc.t("result.button.quit"),func():_leave("quit"));quit_button.name="QuitGame"
	quit_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;second.add_child(quit_button)

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
		"buttons":[{"id":"open","text":Loc.t("profile.reject.open_folder")},{"id":"play","text":Loc.t("profile.reject.play_without"),"kind":"primary"},
			{"id":"fresh","text":Loc.t("profile.reject.start_fresh"),"kind":"danger"},{"id":"quit","text":Loc.t("profile.reject.quit"),"kind":"danger"}],
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
		buttons.append({"id":"resume","text":Loc.t("profile.fresh.continue"),"kind":"primary"});buttons.append({"id":"empty","text":Loc.t("profile.fresh.empty"),"kind":"danger"})
	else:buttons.append({"id":"go","text":Loc.t("profile.fresh.go"),"kind":"danger"})
	buttons.append({"id":"back","text":Loc.t("profile.fresh.back")})
	_open_dialog("fresh",{"width":820,"title":Loc.t("profile.fresh.title"),"content":_dialog_text(Loc.t(body_key,args)),
		"buttons":buttons,"default_id":"back","esc_id":"back"})

## A11 12.3.3: the descent's cut-scene covers the whole screen, so the HUD (the combat bar included) fades out in 0.2 s and comes back in 0.15 s.
## The presenter calls this; the HUD only changes its own opacity (the core is paused and the hero cannot be hurt while the cut-scene runs).
var _hud_fade: Tween
func set_hud_hidden(hidden: bool) -> void:
	if root == null: return
	if _hud_fade != null: _hud_fade.kill()
	_hud_fade = root.create_tween()
	_hud_fade.tween_property(root,"modulate:a",0.0 if hidden else 1.0,0.2 if hidden else 0.15)
