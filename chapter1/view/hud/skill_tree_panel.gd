extends Control
## Skill-tree investment screen (G1 spec section 8). One self-contained control: menu, results
## screen and the later town altar all open this same panel. It never changes game state.
##
## Inputs (call set_data whenever the committed state changes):
##   tree        one tree document (spec 7.2 "trees[i]")
##   ranks       committed ranks {node_id: rank}
##   level       permanent character level
##   points_free unspent points (committed state, before any staged investment)
##   info        optional display data: name, xp, xp_floor, xp_next (-1 at the cap), essence, respec_cost
## Outputs (signals only):
##   commit_requested(ranks)   the player pressed Confirm; ranks = committed + staged, full dictionary
##   respec_requested()        the player confirmed "reset all"
##   closed(discarded_points)  the player left the screen (staged points already discarded)
##   staged_changed(staged, spent_delta)   informational, for a button badge or sound
## After commit_requested the owner answers with set_data(...) (success) or show_error(text) (failure,
## the staged state stays on screen). Legality and effect text go through the three _api_* functions
## below; they are the only place that must change when core/skill_tree.gd exists.

signal commit_requested(ranks: Dictionary)
signal respec_requested()
signal closed(discarded_points: int)
signal staged_changed(staged: Dictionary, spent_delta: int)

## Flip to true once chapter1/core/skill_tree.gd (spec 9, P1) exists; the _api_* functions then call it.
const USE_CORE_MODULE := true
const CORE_PATH := "res://chapter1/core/skill_tree.gd"
## Per-witch source art and face crop (original 1024x1536 pixels). info.portrait picks one; frost is the default.
## Derived face crops (art/characters/derived/) do not exist yet, so the face is cut from the original here.
const PORTRAITS := {
	"frost":{"path":"res://chapter1/art/characters/frost_witch_v02.png","face":Rect2(295,5,300,300)},
	"ember":{"path":"res://chapter1/art/characters/ember_witch_v02.png","face":Rect2(350,0,300,300)},
	"storm":{"path":"res://chapter1/art/characters/storm_witch_v02.png","face":Rect2(355,35,300,300)}}

const DESIGN := Vector2(1280,720)
const Palette := preload("res://chapter1/view/hud/palette.gd")
const BRASS := Palette.BRASS
const BRASS_DIM := Palette.BRASS_DIM
const BRASS_HI := Palette.BRASS_HI
const PLATE := Palette.PLATE
const SLOT := Palette.SLOT
const INK := Palette.INK
const INK_DIM := Palette.INK_DIM
const FROST := Palette.FROST
## Permanent growth (Lv, points, staged +n, staged pips). Fill, glyph and text only; the bright gold edge is selection.
const GOLD := Palette.GROWTH
const WARN := Palette.WARN
const BRANCH_COLORS := {"frost":Palette.FROST,"brass":Palette.BRASS}
const FRAME := Rect2(20,12,1240,696)
const GRID_X := 122.0
const COL_W := [160.0,160.0,160.0,280.0]
const COL_GAP := 6.0
const ROW_Y := 132.0
const ROW_PITCH := 130.0
const TILE_H := 82.0
const OPEN_GUARD_MS := 250

static var _fonts_ready := false
const Loc = preload("res://chapter1/view/loc.gd")
static var _body: Font
static var _bold: Font
static var _head: Font

var tree: Dictionary = {}
var committed: Dictionary = {}
var staged: Dictionary = {}
var level := 1
var points_free := 0
var info: Dictionary = {}
var selected := ""
var message := ""
var message_error := false
var confirm := ""
var confirm_focus := 1

var _scale := 1.0
var _origin := Vector2.ZERO
var _tiles: Dictionary = {}
var _btns: Dictionary = {}
var _btn_on: Dictionary = {}
var _hover := ""
var _opened_ms := 0
var _portrait: Texture2D
var _portrait_key := ""
var _art: Texture2D
var _core: GDScript

func _ready() -> void:
	_ensure_fonts()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_apply_portrait(String(info.get("portrait","frost")))
	resized.connect(queue_redraw)
	_opened_ms = Time.get_ticks_msec()

static func _ensure_fonts() -> void:
	if _fonts_ready: return
	_fonts_ready = true
	_body = Loc.font("body")
	_bold = Loc.font("bold")
	_head = Loc.font("heading")

func _apply_portrait(key: String) -> void:
	if not PORTRAITS.has(key): key = "frost"
	if key == _portrait_key and _art != null: return
	_portrait_key = key
	_art = _load_texture(String(PORTRAITS[key].path))
	_portrait = _art

func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path): return load(path) as Texture2D
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty(): return null
	return ImageTexture.create_from_image(image)

# ----------------------------------------------------------------- public API

## Replace the displayed state. Staged investments are discarded unless keep_staged is true.
func set_data(new_tree: Dictionary, ranks: Dictionary, new_level: int, free_points: int, new_info: Dictionary = {}, keep_staged := false) -> void:
	tree = new_tree
	committed = ranks.duplicate()
	level = new_level
	points_free = free_points
	info = new_info.duplicate()
	_apply_portrait(String(info.get("portrait","frost")))
	if not keep_staged: staged = committed.duplicate()
	confirm = ""
	if not _nodes_by_id().has(selected):
		var nodes: Array = tree.get("nodes",[])
		selected = String(nodes[0].id) if not nodes.is_empty() else ""
	queue_redraw()

## Call when the screen is shown. Takes keyboard focus and starts the accidental-key guard.
func open() -> void:
	visible = true
	_opened_ms = Time.get_ticks_msec()
	message = ""
	confirm = ""
	grab_focus()
	queue_redraw()

func show_error(text: String) -> void:
	message = text; message_error = true; queue_redraw()

func show_notice(text: String) -> void:
	message = text; message_error = false; queue_redraw()

func select_node(id: String) -> void:
	if _nodes_by_id().has(id):
		selected = id; message = ""; queue_redraw()

func staged_delta() -> int:
	return _sum(staged)-_sum(committed)

func invest_selected() -> bool:
	if selected.is_empty(): return false
	var verdict: Dictionary = _api_can_invest(selected)
	if not bool(verdict.get("ok",false)):
		show_notice("투자할 수 없음: "+_reasons_text(verdict.get("reasons",[])))
		message_error = true
		return false
	staged[selected] = int(staged.get(selected,0))+1
	message = ""
	staged_changed.emit(staged.duplicate(),staged_delta())
	queue_redraw()
	return true

func undo_selected() -> bool:
	if selected.is_empty() or not _api_can_refund(selected): return false
	var rank := int(staged.get(selected,0))-1
	if rank <= 0: staged.erase(selected)
	else: staged[selected] = rank
	message = ""
	staged_changed.emit(staged.duplicate(),staged_delta())
	queue_redraw()
	return true

func request_commit() -> void:
	if staged_delta() <= 0:
		show_notice("확정할 예정 투자가 없습니다."); return
	commit_requested.emit(staged.duplicate())

func request_close() -> void:
	if staged_delta() > 0:
		confirm = "discard"; confirm_focus = 1; queue_redraw(); return
	closed.emit(0)

func request_respec() -> void:
	if _sum(committed) <= 0:
		show_notice("초기화할 투자가 없습니다."); return
	if int(info.get("essence",0)) < int(info.get("respec_cost",0)):
		show_error("오리칼쿰이 모자랍니다. 필요 %d · 보유 %d" % [int(info.get("respec_cost",0)),int(info.get("essence",0))]); return
	confirm = "respec"; confirm_focus = 1; queue_redraw()

# ------------------------------------------------- data access (swap point)
## The three functions below are the only ones that know where legality and wording come from.
## With USE_CORE_MODULE they forward to the P1 module; until then a thin stand-in reads the tree document.

func _api_can_invest(node_id: String) -> Dictionary:
	if USE_CORE_MODULE:
		return _core_module().can_invest(tree,staged,node_id,level,_free_after())
	return _stub_can_invest(node_id)

func _api_can_refund(node_id: String) -> bool:
	if USE_CORE_MODULE:
		return _core_module().can_refund_staged(tree,committed,staged,node_id)
	return _stub_can_refund(node_id)

const TreeText = preload("res://chapter1/view/hud/tree_text.gd")

func _api_describe(node_id: String, rank: int) -> Array:
	if USE_CORE_MODULE:
		return Array(TreeText.describe(tree,node_id,rank))
	return _stub_describe(node_id,rank)

func _core_module() -> GDScript:
	if _core == null: _core = load(CORE_PATH)
	return _core

## Core reasons are machine codes ("level:6", "requires:<node>:<rank>", ...); the stand-in already speaks Korean.
func _reasons_text(reasons: Array) -> String:
	var by_id := _nodes_by_id()
	var out: PackedStringArray = []
	for code in reasons:
		var c := String(code)
		var p := c.split(":")
		match p[0]:
			"max_rank": out.append("최대 랭크")
			"level": out.append("요구 레벨 %s" % p[1])
			"requires": out.append("%s %s랭크 필요" % [String(by_id[p[1]].name) if by_id.has(p[1]) else p[1],p[2]])
			"min_spent": out.append("트리 전체 %s포인트 필요" % p[1])
			"no_points": out.append("남은 포인트 없음")
			"unknown_node": out.append("알 수 없는 노드")
			_: out.append(c)
	return " · ".join(out)

func _stub_can_invest(node_id: String) -> Dictionary:
	var node: Dictionary = _nodes_by_id().get(node_id,{})
	if node.is_empty(): return {"ok":false,"reasons":["알 수 없는 노드"]}
	var reasons: Array = []
	var rank := int(staged.get(node_id,0))
	if rank >= int(node.max_rank): reasons.append("최대 랭크")
	if level < _tier_level(node): reasons.append("요구 레벨 %d" % _tier_level(node))
	var by_id := _nodes_by_id()
	for need_id in node.requires:
		if int(staged.get(need_id,0)) < int(node.requires[need_id]):
			reasons.append("%s %d랭크 필요" % [String(by_id[need_id].name),int(node.requires[need_id])])
	if int(node.get("min_spent",0)) > _sum(staged):
		reasons.append("트리 전체 %d포인트 필요" % int(node.min_spent))
	if _free_after() < 1: reasons.append("남은 포인트 없음")
	return {"ok":reasons.is_empty(),"reasons":reasons}

func _stub_can_refund(node_id: String) -> bool:
	if int(staged.get(node_id,0)) <= int(committed.get(node_id,0)): return false
	var trial := staged.duplicate()
	trial[node_id] = int(trial[node_id])-1
	if int(trial[node_id]) <= 0: trial.erase(node_id)
	var by_id := _nodes_by_id()
	for id in trial:
		var node: Dictionary = by_id.get(id,{})
		for need_id in node.get("requires",{}):
			if int(trial.get(need_id,0)) < int(node.requires[need_id]): return false
		if int(node.get("min_spent",0)) > _sum(trial)-int(trial[id]): return false
	return true

func _stub_describe(node_id: String, rank: int) -> Array:
	var node: Dictionary = _nodes_by_id().get(node_id,{})
	if node.is_empty() or rank <= 0 or rank > node.ranks.size(): return []
	return _block_lines(node.ranks[rank-1],false)

func _block_lines(block: Dictionary, per_rank: bool) -> Array:
	var out: Array = []
	var sk: Dictionary = block.get("skill",{})
	var add: Dictionary = sk.get("add",{})
	var pct := "%p" if per_rank else "%"
	if add.has("pierce"): out.append("관통 +%d" % int(add.pierce))
	if add.has("projectiles"): out.append("스피어 +%d발" % int(add.projectiles))
	if sk.get("mul_bps",{}).has("damage_raw"): out.append("피해 +%d%s" % [(int(sk.mul_bps.damage_raw)-10000)/100,pct])
	if sk.has("cooldown_bps"): out.append("시전 간격 −%d%%" % ((10000-int(sk.cooldown_bps))/100))
	if add.has("slow_bps"): out.append("감속 +%d%%p" % (int(add.slow_bps)/100))
	if sk.get("at_most",{}).has("freeze_stacks"): out.append("%d번 맞으면 빙결" % int(sk.at_most.freeze_stacks))
	if sk.get("at_least",{}).has("shatter_count"): out.append("파쇄 파편 최소 %d" % int(sk.at_least.shatter_count))
	if add.has("shatter_count"): out.append("파편 +%d" % int(add.shatter_count))
	var rules: Dictionary = block.get("rules",{})
	if rules.has("elite_damage_bps"): out.append("수호자·우두머리 피해 +%d%s" % [int(rules.elite_damage_bps)/100,pct])
	if rules.has("shatter_radius_cm"): out.append("파쇄 반경 +%s m" % _num(float(rules.shatter_radius_cm)/100.0))
	if rules.has("frost_field"):
		var f: Dictionary = rules.frost_field
		out.append("서리 지대: 반경 %s m · %s초 · 감속 %d%%" % [_num(float(f.radius_cm)/100.0),_num(float(f.duration_ticks)/60.0),int(f.slow_bps)/100])
	if rules.has("frost_field_add"):
		var a: Dictionary = rules.frost_field_add
		if a.has("radius_cm"): out.append("지대 반경 +%s m" % _num(float(a.radius_cm)/100.0))
		if int(a.get("max_fields",0)) > 0: out.append("동시 지대 +%d" % int(a.max_fields))
		if int(a.get("pulse_damage_bps",0)) > 0: out.append("0.5초마다 스피어 피해의 %d%%" % (int(a.pulse_damage_bps)/100))
		if a.has("slow_bps_at_least"): out.append("지대 감속 %d%%" % (int(a.slow_bps_at_least)/100))
	var hero: Dictionary = block.get("hero",{})
	if hero.has("max_hp"): out.append("최대 생명 +%d" % int(hero.max_hp))
	if hero.has("damage_reduction_bps"): out.append("받는 피해 −%d%%" % (int(hero.damage_reduction_bps)/100))
	if hero.has("potion_start"): out.append("시작 회복약 +%d" % int(hero.potion_start))
	if rules.has("grace_rerolls"): out.append("권능 다시 청하기 %d회" % int(rules.grace_rerolls))
	if rules.has("start_rank"): out.append("아이스 스피어 랭크 %d로 시작" % int(rules.start_rank))
	if bool(rules.get("evolve_without_passive",false)): out.append("하갈라즈 룬 없이 진화")
	return out

# ------------------------------------------------------------ small helpers

static func _num(x: float) -> String:
	return ("%.1f" % x).trim_suffix(".0")

func _sum(ranks: Dictionary) -> int:
	var total := 0
	for id in ranks: total += int(ranks[id])
	return total

func _free_after() -> int:
	return points_free-staged_delta()

func _nodes_by_id() -> Dictionary:
	var out: Dictionary = {}
	for node in tree.get("nodes",[]): out[String(node.id)] = node
	return out

func _tier_level(node: Dictionary) -> int:
	var tiers: Array = tree.get("tiers",[])
	var index := int(node.tier)-1
	return int(tiers[index].level) if index >= 0 and index < tiers.size() else 1

func _branch_index(branch_id: String) -> int:
	var branches: Array = tree.get("branches",[])
	for i in branches.size():
		if String(branches[i].id) == branch_id: return i
	return 0

func _is_brass(node: Dictionary) -> bool:
	for branch in tree.get("branches",[]):
		if String(branch.id) == String(node.branch): return String(branch.get("color","frost")) == "brass"
	return false

func _branch_color(node: Dictionary) -> Color:
	for branch in tree.get("branches",[]):
		if String(branch.id) == String(node.branch): return BRANCH_COLORS.get(String(branch.get("color","frost")),FROST)
	return FROST

## Display-only checklist for the detail pane: what the node needs and whether it is met right now.
func _requirements(node: Dictionary) -> Array:
	var rows: Array = []
	var need_level := _tier_level(node)
	rows.append({"text":"요구 레벨 %d (현재 %d)" % [need_level,level],"met":level >= need_level,"short":"Lv %d 필요" % need_level})
	var by_id := _nodes_by_id()
	for need_id in node.requires:
		var have := int(staged.get(need_id,0))
		var need := int(node.requires[need_id])
		var pre_name := String(by_id[need_id].name)
		rows.append({"text":"%s %d랭크 (현재 %d)" % [pre_name,need,have],"met":have >= need,"short":"%s %d 필요" % [pre_name,need]})
	if int(node.get("min_spent",0)) > 0:
		var spent := _sum(staged)
		rows.append({"text":"트리 전체 %d포인트 (현재 %d)" % [int(node.min_spent),spent],"met":spent >= int(node.min_spent),"short":"총 %d포인트 필요" % int(node.min_spent)})
	return rows

func _short_reason(node: Dictionary) -> String:
	for row in _requirements(node):
		if not bool(row.met): return String(row.short)
	if int(staged.get(String(node.id),0)) >= int(node.max_rank): return "최대 랭크"
	if _free_after() < 1: return "포인트 없음"
	return ""

# ------------------------------------------------------------------- layout

func _layout() -> void:
	_scale = minf(size.x/DESIGN.x,size.y/DESIGN.y)
	_origin = (size-DESIGN*_scale)*.5
	_tiles.clear()
	var col_x: Array = []
	var x := GRID_X
	for w in COL_W:
		col_x.append(x); x += float(w)+COL_GAP
	var cells: Dictionary = {}
	for node in tree.get("nodes",[]):
		var key := "%d|%d" % [_branch_index(String(node.branch)),int(node.tier)]
		if not cells.has(key): cells[key] = []
		cells[key].append(node)
	for key in cells:
		var parts: PackedStringArray = key.split("|")
		var col := int(parts[0]); var tier := int(parts[1])
		var list: Array = cells[key]
		var y := ROW_Y+float(tier-1)*ROW_PITCH
		var cell_w: float = COL_W[mini(col,COL_W.size()-1)]
		var each := (cell_w-COL_GAP*float(list.size()-1))/float(list.size())
		for i in list.size():
			_tiles[String(list[i].id)] = Rect2(col_x[col]+float(i)*(each+COL_GAP),y,each,TILE_H)
	_btns = {
		"invest":Rect2(928,516,150,34),"undo":Rect2(1086,516,150,34),
		"respec":Rect2(770,628,150,34),"cancel":Rect2(932,628,140,34),"commit":Rect2(1084,628,160,34),
		"ok":Rect2(420,408,210,40),"no":Rect2(650,408,210,40)}
	var on_selected: Dictionary = _nodes_by_id().get(selected,{})
	_btn_on = {
		"invest":not on_selected.is_empty() and bool(_api_can_invest(selected).get("ok",false)),
		"undo":not on_selected.is_empty() and _api_can_refund(selected),
		"respec":_sum(committed) > 0,"cancel":true,"commit":staged_delta() > 0,"ok":true,"no":true}

func _to_design(p: Vector2) -> Vector2:
	return (p-_origin)/_scale

func _u(v: Vector2) -> Vector2:
	return _origin+v*_scale

func _ur(r: Rect2) -> Rect2:
	return Rect2(_origin+r.position*_scale,r.size*_scale)

func _fs(sz: float) -> int:
	return maxi(10,roundi(sz*_scale))

func _lw(w: float) -> float:
	return maxf(1.0,w*_scale)

func _tw(s: String, sz: float, font: Font = null) -> float:
	return (font if font != null else _body).get_string_size(s,HORIZONTAL_ALIGNMENT_LEFT,-1,_fs(sz)).x/_scale

func _text(pos: Vector2, s: String, sz: float, col: Color, font: Font = null, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var f: Font = font if font != null else _body
	draw_string(f,_u(pos),s,align,width*_scale if width > 0.0 else -1.0,_fs(sz),col)

## Shrinks the font until the text fits, but never below 11 design px.
func _text_fit(pos: Vector2, s: String, sz: float, col: Color, max_w: float, font: Font = null) -> void:
	var use := sz
	while use > 11.0 and _tw(s,use,font) > max_w: use -= 1.0
	_text(pos,s,use,col,font)

func _wrapped(pos: Vector2, s: String, sz: float, col: Color, width: float, max_lines: int, font: Font = null) -> float:
	var f: Font = font if font != null else _body
	var lines := _wrap_words(s,sz,width,f)
	var pitch := f.get_height(_fs(sz))/_scale
	for i in mini(lines.size(),max_lines):
		draw_string(f,_u(pos+Vector2(0,pitch*float(i))),lines[i],HORIZONTAL_ALIGNMENT_LEFT,-1.0,_fs(sz),col)
	return pitch*float(mini(lines.size(),max_lines))

## Greedy wrap on spaces so Korean words are never split mid-word; a single word wider than the line is cut by character.
func _wrap_words(s: String, sz: float, width: float, f: Font) -> Array[String]:
	var lines: Array[String] = []
	var current := ""
	for word in s.split(" "):
		var trial := word if current.is_empty() else current+" "+word
		if _tw(trial,sz,f) <= width:
			current = trial; continue
		if not current.is_empty(): lines.append(current)
		current = ""
		for ch in word:
			if not current.is_empty() and _tw(current+ch,sz,f) > width:
				lines.append(current); current = ""
			current += ch
	if not current.is_empty(): lines.append(current)
	return lines

func _line(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	draw_line(_u(a),_u(b),col,_lw(w),true)

func _dashed(a: Vector2, b: Vector2, col: Color, w: float, dash := 5.0) -> void:
	draw_dashed_line(_u(a),_u(b),col,_lw(w),maxf(2.0,dash*_scale),true,true)

func _rect_line(r: Rect2, col: Color, w: float) -> void:
	draw_rect(_ur(r),col,false,_lw(w))

func _rect_dashed(r: Rect2, col: Color, w: float) -> void:
	var tl := r.position; var tr := Vector2(r.end.x,r.position.y)
	var bl := Vector2(r.position.x,r.end.y); var br := r.end
	_dashed(tl,tr,col,w); _dashed(tr,br,col,w); _dashed(br,bl,col,w); _dashed(bl,tl,col,w)

func _poly(points: Array, col: Color, w: float, closed_shape := false) -> void:
	var pts := PackedVector2Array()
	for p in points: pts.append(_u(p))
	if closed_shape: pts.append(_u(points[0]))
	draw_polyline(pts,col,_lw(w),true)

func _fill_poly(points: Array, col: Color) -> void:
	var pts := PackedVector2Array()
	for p in points: pts.append(_u(p))
	draw_colored_polygon(pts,col)

# --------------------------------------------------------------------- draw

func _draw() -> void:
	_ensure_fonts()
	_layout()
	draw_rect(Rect2(Vector2.ZERO,size),Color(0,0,0,.74))
	draw_rect(_ur(FRAME),Color(.03,.038,.045,.97))
	_draw_art()
	_rect_line(FRAME,BRASS_DIM,2.0)
	_rect_line(FRAME.grow(-5),Color(BRASS_DIM,.5),1.0)
	_line(FRAME.position+Vector2(14,0),Vector2(FRAME.end.x-14,FRAME.position.y),BRASS,2.0)
	_draw_header()
	_draw_branch_titles()
	_draw_tier_stripes()
	_draw_edges()
	for node in tree.get("nodes",[]): _draw_tile(node)
	_draw_detail()
	_draw_bottom()
	if not confirm.is_empty(): _draw_confirm()

func _draw_art() -> void:
	if _art == null: return
	var h := (FRAME.size.y-12.0)
	var w := h*float(_art.get_width())/float(_art.get_height())
	var dst := Rect2(Vector2(FRAME.end.x-w*.62-6,FRAME.position.y+6),Vector2(w,h))
	draw_texture_rect(_art,_ur(dst),false,Color(1,1,1,.10))

func _draw_header() -> void:
	var box := Rect2(32,22,64,64)
	draw_rect(_ur(box),SLOT)
	if _portrait != null:
		draw_texture_rect_region(_portrait,_ur(box),PORTRAITS[_portrait_key].face)
	_rect_line(box,BRASS,2.0)
	_text(Vector2(110,52),String(info.get("name","서리의 마녀")),24,INK,_head)
	_text(Vector2(110,76),"스킬 트리 · 영구 성장",13,INK_DIM)
	_text(Vector2(300,64),"Lv %d" % level,28,GOLD,_head)
	var xp := int(info.get("xp",0)); var floor_xp := int(info.get("xp_floor",0)); var next_xp := int(info.get("xp_next",-1))
	var bar := Rect2(392,50,360,14)
	draw_rect(_ur(bar),Color(.02,.025,.03,1))
	var fraction := 1.0 if next_xp < 0 else clampf(float(xp-floor_xp)/maxf(1.0,float(next_xp-floor_xp)),0,1)
	draw_rect(_ur(Rect2(bar.position+Vector2(1,1),Vector2((bar.size.x-2.0)*fraction,bar.size.y-2.0))),GOLD)
	_rect_line(bar,BRASS,1.5)
	_text(Vector2(392,44),"경험치",12,INK_DIM)
	var xp_text := "최대 레벨" if next_xp < 0 else "%s / %s" % [_commas(xp),_commas(next_xp)]
	_text(Vector2(392,80),xp_text,13,INK,null,360.0,HORIZONTAL_ALIGNMENT_RIGHT)
	# Points box: the free count after staged spending is the headline number.
	var pts := Rect2(916,22,332,64)
	draw_rect(_ur(pts),PLATE)
	_rect_line(pts,BRASS,2.0)
	var free := _free_after()
	_text(Vector2(930,46),"남은 포인트",14,INK_DIM)
	_diamond(Vector2(1038,40),9.0,GOLD,free > 0)
	_text(Vector2(930,76),("예정 −%d · 확정 상태 %d" % [staged_delta(),points_free]) if staged_delta() > 0 else "확정 상태 %d" % points_free,12,INK_DIM)
	_text(Vector2(1140,74),str(free),38,GOLD if free > 0 else INK_DIM,_bold,96.0,HORIZONTAL_ALIGNMENT_RIGHT)

func _commas(n: int) -> String:
	var s := str(n)
	var out := ""
	for i in s.length():
		if i > 0 and (s.length()-i) % 3 == 0: out += ","
		out += s[i]
	return out

func _diamond(c: Vector2, r: float, col: Color, filled: bool) -> void:
	var pts := [c+Vector2(0,-r),c+Vector2(r,0),c+Vector2(0,r),c+Vector2(-r,0)]
	if filled: _fill_poly(pts,col)
	_poly(pts,col if filled else INK_DIM,1.5,true)

func _draw_branch_titles() -> void:
	var x := GRID_X
	var branches: Array = tree.get("branches",[])
	for i in branches.size():
		var w: float = COL_W[mini(i,COL_W.size()-1)]
		var col: Color = BRANCH_COLORS.get(String(branches[i].get("color","frost")),FROST)
		var r := Rect2(x,98,w,26)
		draw_rect(_ur(r),Color(col,.12))
		_line(Vector2(x,124),Vector2(x+w,124),col,2.0)
		_glyph(String(branches[i].id),Rect2(x+6,102,18,18),col,false)
		_text(Vector2(x+30,117),String(branches[i].name),15,INK,_bold)
		x += w+COL_GAP

func _draw_tier_stripes() -> void:
	var tiers: Array = tree.get("tiers",[])
	for i in tiers.size():
		var y := ROW_Y+float(i)*ROW_PITCH
		var t := float(i)/3.0
		# Deeper tiers only get a little darker. A red tint reads as enemy threat, so the plate stays neutral (art review 5.4).
		var tint := Color(.04,.05,.057,.9).lerp(Color(.028,.036,.042,.95),t)
		var stripe := Rect2(34,y-8,872,TILE_H+16)
		draw_rect(_ur(stripe),tint)
		_line(Vector2(34,y-8),Vector2(906,y-8),Color(BRASS_DIM,.55+.3*t),1.0)
		var tier: Dictionary = tiers[i]
		_text(Vector2(42,y+14),"단 %d" % (i+1),15,GOLD if level >= int(tier.level) else INK_DIM,_bold)
		_wrapped(Vector2(42,y+34),String(tier.name),13,INK,72.0,2)
		var gate := "Lv %d" % int(tier.level)
		if i == 3: gate += " · 15포인트"
		_text_fit(Vector2(42,y+TILE_H-6),gate,13,INK if level >= int(tier.level) else INK_DIM,72.0)
		if level < int(tier.level): _lock_icon(Vector2(106,y+6),INK_DIM)

func _draw_edges() -> void:
	var by_id := _nodes_by_id()
	for node in tree.get("nodes",[]):
		var to: Rect2 = _tiles[String(node.id)]
		for need_id in node.requires:
			var from: Rect2 = _tiles[need_id]
			var met := int(staged.get(need_id,0)) >= int(node.requires[need_id])
			var a := Vector2(from.get_center().x,from.end.y)
			var b := Vector2(to.get_center().x,to.position.y)
			var mid_y := (a.y+b.y)*.5
			var path := [a,Vector2(a.x,mid_y),Vector2(b.x,mid_y),b]
			var col: Color = _branch_color(by_id[need_id])
			for i in path.size()-1:
				if met: _line(path[i],path[i+1],col,3.0)
				else: _dashed(path[i],path[i+1],Color(INK_DIM,.55),2.0,6.0)
			var tag := Vector2(b.x,(mid_y+b.y)*.5)
			var tag_rect := Rect2(tag-Vector2(11,9),Vector2(22,18))
			draw_rect(_ur(tag_rect),Color(.03,.04,.045,1))
			if met: _rect_line(tag_rect,col,2.0)
			else: _rect_dashed(tag_rect,INK_DIM,1.5)
			_text(Vector2(tag.x-11,tag.y+5),str(int(node.requires[need_id])),13,INK if met else INK_DIM,_bold,22.0,HORIZONTAL_ALIGNMENT_CENTER)

func _tile_state(node: Dictionary) -> String:
	var id := String(node.id)
	var rank := int(staged.get(id,0))
	if rank >= int(node.max_rank): return "max"
	var can := bool(_api_can_invest(id).get("ok",false))
	if rank > 0: return "invested_open" if can else "invested"
	return "available" if can else "locked"

func _draw_tile(node: Dictionary) -> void:
	var id := String(node.id)
	var r: Rect2 = _tiles[id]
	var state := _tile_state(node)
	var rank := int(staged.get(id,0))
	var base := int(committed.get(id,0))
	var col := _branch_color(node)
	var edge := BRASS_DIM if _is_brass(node) else col
	var locked := state == "locked"
	var plate := SLOT if not locked else Color(.05,.058,.064,1)
	if _hover == id and not locked: plate = plate.lightened(.08)
	draw_rect(_ur(r),plate)
	if state == "max": draw_rect(_ur(r),Color(col,.10))
	var dim := .5 if locked else 1.0
	# Border form tells the state without colour: dashed = locked, solid = open or invested, double = maxed, bright = staged.
	if locked:
		_rect_dashed(r,Color(INK_DIM,.6),1.5)
	else:
		# One solid border colour for open, invested and staged alike (staged shows in the +n tag and the pip dots).
		# The oath column keeps its brass only in the header band and glyph; its tiles use the dim frame brass.
		_rect_line(r,edge,2.0)
		if state == "max": _rect_line(r.grow(-4),Color(edge,.8),1.5)
	# Glyph, name.
	_glyph(String(node.branch) if int(node.tier) < 4 else "deep",Rect2(r.position+Vector2(8,8),Vector2(28,28)),Color(col,dim),locked)
	var narrow := r.size.x < 150.0
	var text_x := r.position.x+42.0
	var avail := r.size.x-42.0-38.0
	var name_size := 13.0
	_wrapped(Vector2(text_x,r.position.y+22),String(node.name),name_size,Color(INK,dim+(.3 if locked else 0.0)),avail,2,_bold)
	# Corner mark: lock = locked, plus = can invest, +n tag = staged.
	var corner := Vector2(r.end.x-20,r.position.y+6)
	if rank > base:
		var tag := Rect2(r.end.x-34,r.position.y+6,28,18)
		draw_rect(_ur(tag),GOLD)
		_rect_line(tag,BRASS_DIM,1.5)
		_text(Vector2(tag.position.x,tag.position.y+14),"+%d" % (rank-base),13,Color(.05,.04,.02),_bold,28.0,HORIZONTAL_ALIGNMENT_CENTER)
	elif locked: _lock_icon(corner,INK_DIM)
	elif state == "available" or state == "invested_open": _plus_icon(corner+Vector2(7,7),col)
	# Pips: filled = committed, boxed with dot = staged, hollow = empty.
	var pip_y := r.position.y+48.0
	for p in int(node.max_rank):
		var pr := Rect2(r.position.x+8.0+float(p)*13.0,pip_y,10,10)
		if p < base: draw_rect(_ur(pr),Color(col,dim))
		elif p < rank:
			draw_rect(_ur(pr),Color(GOLD,.25)); _rect_line(pr,GOLD,2.0)
			draw_rect(_ur(Rect2(pr.position+Vector2(3.5,3.5),Vector2(3,3))),GOLD)
		else: _rect_line(pr,Color(INK_DIM,.6),1.0)
	_text(Vector2(r.end.x-8-60,pip_y+13),"%d/%d" % [rank,int(node.max_rank)],16,Color(INK,dim+(.3 if locked else 0.0)),_bold,60.0,HORIZONTAL_ALIGNMENT_RIGHT)
	var status := ""
	match state:
		"max": status = "최대 랭크"
		"locked": status = _short_reason(node)
		"available": status = "투자 가능"
		"invested_open": status = "예정 +%d" % (rank-base) if rank > base else "투자 가능"
		"invested":
			if rank > base: status = "+%d 예정" % (rank-base) if narrow else "예정 +%d · %s" % [rank-base,_short_reason(node)]
			else: status = _short_reason(node)
	_text_fit(Vector2(r.position.x+8,r.end.y-8),status,13,Color(INK,.85) if not locked else INK_DIM,r.size.x-16.0)
	if id == selected:
		_rect_line(r.grow(4),BRASS_HI,3.0)
		for corner_dir in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
			var c := r.get_center()+Vector2(corner_dir.x*(r.size.x*.5+4),corner_dir.y*(r.size.y*.5+4))
			_fill_poly([c,c+Vector2(-corner_dir.x*9,0),c+Vector2(0,-corner_dir.y*9)],BRASS_HI)

func _glyph(kind: String, r: Rect2, col: Color, locked: bool) -> void:
	var c := r.get_center(); var h := r.size.x*.5
	var w := 2.0
	match kind:
		"lance":
			_poly([c+Vector2(0,h),c+Vector2(0,-h)],col,w)
			_poly([c+Vector2(-h*.6,-h*.3),c+Vector2(0,-h),c+Vector2(h*.6,-h*.3)],col,w)
			_poly([c+Vector2(-h*.5,h*.4),c+Vector2(0,h*.1),c+Vector2(h*.5,h*.4)],col,w)
		"field":
			draw_arc(_u(c),h*_scale,0,TAU,32,col,_lw(w),true)
			draw_arc(_u(c),h*.5*_scale,0,TAU,24,col,_lw(w),true)
			if not locked: draw_circle(_u(c),h*.16*_scale,col)
		"shatter":
			_poly([c+Vector2(-h,h*.7),c+Vector2(-h*.2,-h),c+Vector2(h*.1,h*.2)],col,w,true)
			_poly([c+Vector2(h*.1,h*.2),c+Vector2(h*.6,-h*.6),c+Vector2(h,h*.8)],col,w,true)
		"deep":
			var pts := []
			for i in 8:
				var rr := h if i % 2 == 0 else h*.38
				pts.append(c+Vector2.from_angle(float(i)*PI*.25-PI*.5)*rr)
			if not locked: _fill_poly(pts,Color(col,.45))
			_poly(pts,col,w,true)
		_:
			var pts2 := [c+Vector2(0,-h),c+Vector2(h,0),c+Vector2(0,h),c+Vector2(-h,0)]
			_poly(pts2,col,w,true)
			if not locked: draw_circle(_u(c),h*.2*_scale,col)

func _lock_icon(at: Vector2, col: Color) -> void:
	draw_rect(_ur(Rect2(at+Vector2(1,7),Vector2(12,9))),col)
	draw_arc(_u(at+Vector2(7,7)),4.0*_scale,PI,TAU,12,col,_lw(2.0),true)

func _plus_icon(c: Vector2, col: Color) -> void:
	var r := Rect2(c-Vector2(7,7),Vector2(14,14))
	_rect_line(r,col,1.5)
	_line(c+Vector2(-4,0),c+Vector2(4,0),col,2.0)
	_line(c+Vector2(0,-4),c+Vector2(0,4),col,2.0)

func _check_icon(at: Vector2, ok: bool) -> void:
	if ok:
		_poly([at+Vector2(0,6),at+Vector2(4,10),at+Vector2(11,0)],FROST,2.5)
	else:
		_poly([at+Vector2(0,0),at+Vector2(10,10)],WARN,2.5)
		_poly([at+Vector2(10,0),at+Vector2(0,10)],WARN,2.5)

# ------------------------------------------------------------------- detail

func _draw_detail() -> void:
	var panel := Rect2(916,100,332,508)
	draw_rect(_ur(panel),PLATE)
	_rect_line(panel,BRASS,2.0)
	_line(panel.position+Vector2(8,0),Vector2(panel.end.x-8,panel.position.y),BRASS,2.0)
	var node: Dictionary = _nodes_by_id().get(selected,{})
	if node.is_empty():
		_text(Vector2(932,140),"노드를 고르세요",16,INK_DIM); return
	var x := 932.0
	var width := 300.0
	var y := 128.0
	var id := String(node.id)
	var rank := int(staged.get(id,0))
	var max_rank := int(node.max_rank)
	var col := _branch_color(node)
	_text_fit(Vector2(x,y+4),String(node.name),22,INK,196.0,_head)
	_text(Vector2(x+width-90,y+4),"%d/%d" % [rank,max_rank],22,GOLD if rank > 0 else INK_DIM,_bold,90.0,HORIZONTAL_ALIGNMENT_RIGHT)
	y += 24
	var branch_name := ""
	for branch in tree.get("branches",[]):
		if String(branch.id) == String(node.branch): branch_name = String(branch.name)
	var tier: Dictionary = tree.get("tiers",[])[int(node.tier)-1]
	_text(Vector2(x,y),"%s · 단 %d %s" % [branch_name,int(node.tier),String(tier.name)],13,INK_DIM)
	if node.get("new_rule") != null:
		var tag := Rect2(x+width-84,y-14,84,19)
		_rect_line(tag,BRASS_DIM,1.5)
		_diamond(Vector2(tag.position.x+11,tag.position.y+9.5),5.0,GOLD,true)
		_text(Vector2(tag.position.x+20,tag.position.y+14),"새 효과",13,GOLD,_bold)
	y += 10
	_line(Vector2(x,y),Vector2(x+width,y),Color(BRASS_DIM,.8),1.0)
	y += 20
	# Now / next rank. Rank text counts staged investment, so the player sees what confirming gives.
	_text(Vector2(x,y),"지금 (랭크 %d)" % rank,13,col,_bold)
	y += 18
	var now_lines: Array = _api_describe(id,rank)
	if now_lines.is_empty(): now_lines = ["아직 투자하지 않음"]
	for line in now_lines:
		y += _wrapped(Vector2(x+8,y),String(line),14,INK if rank > 0 else INK_DIM,width-8.0,2)
	y += 8
	if rank < max_rank:
		_text(Vector2(x,y),"다음 랭크 (%d)" % (rank+1),13,col,_bold)
		y += 18
		for line in _api_describe(id,rank+1):
			y += _wrapped(Vector2(x+8,y),String(line),14,INK,width-8.0,2)
	else:
		_text(Vector2(x,y),"최대 랭크입니다",13,GOLD,_bold)
		y += 18
	y += 8
	_text(Vector2(x,y),"필요 조건",13,col,_bold)
	y += 20
	for row in _requirements(node):
		_check_icon(Vector2(x+4,y-10),bool(row.met))
		_text_fit(Vector2(x+24,y),String(row.text),13,INK if bool(row.met) else WARN,width-26.0)
		y += 19
	y += 6
	y += _wrapped(Vector2(x,y),String(node.get("lore","")),13,INK_DIM,width,2,_head)+6
	for syn in tree.get("synergies",[]):
		if String(syn.target) != id: continue
		var src: Dictionary = _nodes_by_id().get(String(syn.source),{})
		var src_rank := int(staged.get(String(syn.source),0))
		var parts: Array = _block_lines(syn.per_rank,true)
		if parts.is_empty() or src.is_empty(): continue
		var syn_text := "시너지: %s 1랭크마다 %s%s" % [String(src.name),", ".join(PackedStringArray(parts)),"" if src_rank > 0 else " (비활성)"]
		y += _wrapped(Vector2(x,y),syn_text,13,FROST if src_rank > 0 else INK_DIM,width,3)
	_draw_button("invest","+ 투자 (Enter)")
	_draw_button("undo","− 되돌리기 (Bksp)")
	var verdict: Dictionary = _api_can_invest(id)
	var verdict_text := "투자 가능 · 포인트 1 사용" if bool(verdict.ok) else "투자 불가: "+_reasons_text(verdict.reasons)
	_wrapped(Vector2(x,574),verdict_text,13,INK if bool(verdict.ok) else WARN,width,2)

func _draw_button(key: String, label: String) -> void:
	var r: Rect2 = _btns[key]
	var on := bool(_btn_on.get(key,false))
	var hot := _hover == "btn:"+key and on
	draw_rect(_ur(r),(Color(.13,.15,.16,1) if hot else SLOT) if on else Color(.04,.045,.05,1))
	if on: _rect_line(r,BRASS_HI if key == "commit" else BRASS,2.0)
	else: _rect_dashed(r,Color(INK_DIM,.55),1.5)
	_text(Vector2(r.position.x,r.position.y+r.size.y*.5+5),label,14,INK if on else INK_DIM,_bold,r.size.x,HORIZONTAL_ALIGNMENT_CENTER)

func _draw_bottom() -> void:
	var bar := Rect2(34,616,1214,50)
	draw_rect(_ur(bar),PLATE)
	_rect_line(bar,BRASS_DIM,1.5)
	var essence := int(info.get("essence",0)); var cost := int(info.get("respec_cost",0))
	_text(Vector2(46,646),Loc.t("currency.essence")+" %d · 초기화 비용 %d" % [essence,cost],14,INK)
	if not message.is_empty():
		var col := WARN if message_error else INK
		if message_error:
			_fill_poly([Vector2(250,630),Vector2(262,654),Vector2(238,654)],WARN)
			_line(Vector2(250,637),Vector2(250,646),Color(.05,.03,.02),2.0)
		else:
			draw_arc(_u(Vector2(250,642)),8.0*_scale,0,TAU,20,INK,_lw(1.5),true)
			_line(Vector2(250,642),Vector2(250,648),INK,2.0)
			_line(Vector2(250,636),Vector2(250,637),INK,2.0)
		_wrapped(Vector2(270,639),message,13,col,486.0,2)
	_draw_button("respec","전체 초기화 (R)")
	_draw_button("cancel","취소 (Esc)")
	_draw_button("commit","확정 (F)"+((" · %d" % staged_delta()) if staged_delta() > 0 else ""))
	_text(Vector2(34,694),"방향키/WASD 이동 · Enter/좌클릭 투자 · Backspace/우클릭 되돌리기 · F 확정 · Esc 취소 · R 전체 초기화",12,INK_DIM,null,1214.0,HORIZONTAL_ALIGNMENT_CENTER)

func _draw_confirm() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color(0,0,0,.6))
	var box := Rect2(390,250,500,220)
	draw_rect(_ur(box),Color(.04,.05,.056,1))
	_rect_line(box,BRASS,2.0)
	var title := ""; var body := ""; var yes := ""; var no := ""
	if confirm == "discard":
		title = "확정하지 않은 투자가 있습니다"
		body = "예정 투자 %d개를 버리고 닫을까요? 버리면 포인트는 그대로 남습니다." % staged_delta()
		yes = "버리고 닫기"; no = "계속 편집 (Esc)"
	else:
		title = "전체 초기화"
		body = "확정한 %d포인트를 모두 돌려받습니다. 비용: 오리칼쿰 %d (보유 %d). 되돌릴 수 없습니다." % [_sum(committed),int(info.get("respec_cost",0)),int(info.get("essence",0))]
		yes = "초기화"; no = "취소 (Esc)"
	_text(Vector2(box.position.x,box.position.y+40),title,22,INK,_head,box.size.x,HORIZONTAL_ALIGNMENT_CENTER)
	_wrapped(Vector2(box.position.x+30,box.position.y+78),body,15,INK,box.size.x-60.0,4)
	var ok_r: Rect2 = _btns["ok"]
	var no_r: Rect2 = _btns["no"]
	for entry in [[ok_r,yes,0],[no_r,no,1]]:
		var r: Rect2 = entry[0]
		draw_rect(_ur(r),SLOT)
		_rect_line(r,BRASS_HI if confirm_focus == int(entry[2]) else BRASS_DIM,3.0 if confirm_focus == int(entry[2]) else 1.5)
		if confirm_focus == int(entry[2]):
			_fill_poly([r.position+Vector2(8,r.size.y*.5-6),r.position+Vector2(8,r.size.y*.5+6),r.position+Vector2(16,r.size.y*.5)],BRASS_HI)
		_text(Vector2(r.position.x,r.position.y+r.size.y*.5+5),String(entry[1]),15,INK,_bold,r.size.x,HORIZONTAL_ALIGNMENT_CENTER)

# -------------------------------------------------------------------- input

func _guard_open() -> bool:
	return Time.get_ticks_msec()-_opened_ms < OPEN_GUARD_MS

func _gui_input(event: InputEvent) -> void:
	_layout()
	if event is InputEventMouseMotion:
		var hit := _hit(_to_design(event.position))
		if hit != _hover:
			_hover = hit; queue_redraw()
		return
	if event is InputEventMouseButton and event.pressed:
		_on_mouse(event)
		accept_event(); return
	if event is InputEventKey and event.pressed:
		_on_key(event)
		accept_event()

func _hit(p: Vector2) -> String:
	if not confirm.is_empty():
		for key in ["ok","no"]:
			if _btns[key].has_point(p): return "btn:"+key
		return ""
	for key in ["invest","undo","respec","cancel","commit"]:
		if _btns[key].has_point(p): return "btn:"+key
	for id in _tiles:
		if _tiles[id].has_point(p): return id
	return ""

func _on_mouse(event: InputEventMouseButton) -> void:
	var hit := _hit(_to_design(event.position))
	if not confirm.is_empty():
		if event.button_index == MOUSE_BUTTON_LEFT:
			if hit == "btn:ok": _resolve_confirm(true)
			elif hit == "btn:no": _resolve_confirm(false)
		return
	if hit.begins_with("btn:"):
		if event.button_index != MOUSE_BUTTON_LEFT or not bool(_btn_on.get(hit.substr(4),false)): return
		match hit.substr(4):
			"invest": invest_selected()
			"undo": undo_selected()
			"respec": request_respec()
			"cancel": request_close()
			"commit": request_commit()
		return
	if hit.is_empty(): return
	if event.button_index == MOUSE_BUTTON_LEFT:
		selected = hit
		invest_selected()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		selected = hit
		undo_selected()
	queue_redraw()

func _on_key(event: InputEventKey) -> void:
	var key: int = event.keycode
	if not confirm.is_empty():
		match key:
			KEY_LEFT, KEY_RIGHT, KEY_A, KEY_D, KEY_TAB: confirm_focus = 1-confirm_focus; queue_redraw()
			KEY_ESCAPE: _resolve_confirm(false)
			KEY_ENTER, KEY_KP_ENTER:
				if not event.echo and not _guard_open(): _resolve_confirm(confirm_focus == 0)
		return
	match key:
		KEY_LEFT, KEY_A: _move(Vector2.LEFT)
		KEY_RIGHT, KEY_D: _move(Vector2.RIGHT)
		KEY_UP, KEY_W: _move(Vector2.UP)
		KEY_DOWN, KEY_S: _move(Vector2.DOWN)
		KEY_ENTER, KEY_KP_ENTER:
			# Input48: a held or just-opened Enter must not invest by accident; Space never acts here.
			if not event.echo and not _guard_open(): invest_selected()
		KEY_BACKSPACE, KEY_DELETE: undo_selected()
		KEY_F: request_commit()
		KEY_R: request_respec()
		KEY_ESCAPE: request_close()

func _resolve_confirm(yes: bool) -> void:
	var kind := confirm
	confirm = ""
	if yes:
		if kind == "discard":
			var lost := staged_delta()
			staged = committed.duplicate()
			closed.emit(lost)
		elif kind == "respec":
			staged = {}
			respec_requested.emit()
	queue_redraw()

func _move(dir: Vector2) -> void:
	if not _tiles.has(selected): return
	var c: Vector2 = _tiles[selected].get_center()
	var best := ""
	var best_score := INF
	for id in _tiles:
		if id == selected: continue
		var d: Vector2 = _tiles[id].get_center()-c
		var along := d.dot(dir)
		if along <= 4.0: continue
		var cross := absf(d.x*dir.y-d.y*dir.x)
		var score := along+cross*2.0
		if score < best_score:
			best_score = score; best = id
	if not best.is_empty():
		selected = best; message = ""; queue_redraw()
