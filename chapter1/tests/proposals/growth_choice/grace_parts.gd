extends RefCounted
## A8 G2: the shared parts of the grace screen proposals (tests only; nothing in chapter1/view imports this).
## docs/specs/A8-grace-screen-redesign-20261120.ko.md 5.2 (card form), 5.6 (grades), 7.3 (intro lengths).
## Parts: GraceCard (a grade card), Knob + handles() (reroll / exclude / keep), OwnedBand (owned spells strip), SideNote (parchment),
## TitlePlaque, JackpotPlaque, Candle (iron stand, flame in code), board() (the contract board). One call each, see "HOW TO CALL" below.
##
## Material rule: the hand of the combat HUD (black leather, gold stitching, brass, rivets). Where a generated picture exists it is used;
## where it does not, the part falls back in two steps: (1) a piece of the HUD atlas (hud_atlas.png, the real HUD art) cut and tinted,
## (2) the code shapes of kit.gd. Which step each part took is in report() / report_line() (the sheet prints it on screen).
## Pictures are read at run time from the grace kit folder: --grace-kit=<folder> (absolute, or relative to the project folder; default
## _local/art/grace-kit found from the project folder upwards). KIT.json in it may name the files; without it <name>.png is tried, and
## without that the queue originals (_local/art/queue/<id>/<id>-a1.png, magenta ground keyed out by a shader).
##
## HOW TO CALL (G3 / G4)
##   var P = load("res://chapter1/tests/proposals/growth_choice/grace_parts.gd")
##   var card = P.card(parent, card_dict, idx, Vector2(300, 470), ui)          # GraceCard; card.set_focus_amount(0..1), card.leak, card.sweep (0..1)
##   var band = P.band(parent, Vector2(80, 820), 940.0, contract)              # OwnedBand: slot_centre / target_for / lit / lit_amount / pulse
##   var knobs = P.handles(parent, contract, Vector2(80, 700))                 # [Knob x3]; each has signal pressed(id)
##   var note = P.note(parent, Rect2(1130, 130, 340, 470), contract)           # SideNote; note.show_card(card_dict)
##   var plaque = P.title(parent, "은총", 520.0, "4 / 11")                      # TitlePlaque
##   var cand = P.candle(parent, Vector2(60, 40), 220.0, Palette.FIRE)         # Candle; cand.lit_amount 0..1, cand.animated
##   var jp = P.jackpot(parent, "기연!", Vector2(260, 110))                     # JackpotPlaque (the stamped word)
##   var b = P.board(parent, Rect2(...))                                       # leather board the cards lie on
##   P.intro_seconds(P.intro_kind(contract))                                   # 0.45 / 1.8 / 2.0 (the one place of the intro lengths)
const Kit = preload("res://chapter1/tests/proposals/growth_choice/kit.gd")
const Palette = preload("res://chapter1/view/hud/palette.gd")
const UiStyle = preload("res://chapter1/view/hud/ui_style.gd")
const AtlasBox = preload("res://chapter1/view/hud/atlas_box.gd")
const Loc = preload("res://chapter1/view/loc.gd")
const PARTS_PATH := "res://chapter1/tests/proposals/growth_choice/grace_parts.gd"

# ============================================================ intro lengths (director decision 2026-11-20; ONE place)
## Seconds until the cards can be picked. Normal 0.45; the long intro only for the FIRST grace of a run (1.6..1.9); a jackpot 2.0 or less.
const INTRO_NORMAL := 0.45
const INTRO_LONG := 1.8
const INTRO_LONG_MIN := 1.6
const INTRO_LONG_MAX := 1.9
const INTRO_JACKPOT_MAX := 2.0

static func intro_seconds(kind: String) -> float:
	match kind:
		"long": return INTRO_LONG
		"jackpot": return INTRO_JACKPOT_MAX
	return INTRO_NORMAL

## "jackpot" when any card is of the top grade, "long" for the first grace of a run (moment.kind "first"), else "normal".
static func intro_kind(contract: Dictionary) -> String:
	for c in contract.get("cards", []):
		if grade_key(String(c.get("grade", "common"))) == "jackpot": return "jackpot"
	if String(contract.get("moment", {}).get("kind", "normal")) == "first": return "long"
	return "normal"

# ============================================================ grades (spec 5.6)
const JACKPOT_GOLD := Color("ffc24d")
const FLAME_WARM := Color("ffb25a")

## Fixture words (common / scarce / fated) and core words (common / rare / jackpot) both map to the three keys.
static func grade_key(g: String) -> String:
	match g:
		"rare", "scarce", "magic": return "rare"
		"jackpot", "fated", "legendary": return "jackpot"
	return "common"

static func grade_rank(key: String) -> int:
	return {"common": 0, "rare": 1, "jackpot": 2}.get(key, 0)

## common = INK, rare = QUALITY_RARE (the same colour as the rare gear), jackpot = gold.
static func name_color(key: String) -> Color:
	match key:
		"rare": return Palette.QUALITY_RARE
		"jackpot": return JACKPOT_GOLD
	return Palette.INK

## The word kit.gd's code face knows (used only by the code fallback).
static func _kit_grade(key: String) -> String:
	return {"common": "common", "rare": "scarce", "jackpot": "fated"}.get(key, "common")

# ============================================================ picture loading
const QUEUE_FILES := {
	"frame_common": "grade-frame-common/grade-frame-common-a1.png", "frame_rare": "grade-frame-rare/grade-frame-rare-a1.png",
	"frame_jackpot": "grade-frame-jackpot/grade-frame-jackpot-a1.png",
	"bg_common": "grade-bg-common/grade-bg-common-a1.png", "bg_rare": "grade-bg-rare/grade-bg-rare-a1.png", "bg_jackpot": "grade-bg-jackpot/grade-bg-jackpot-a1.png",
	"sigil": "jackpot-light-sigil/jackpot-light-sigil-a1.png",
	"emblem_ember_new": "emblem-ember-new/emblem-ember-new-a1.png", "emblem_ember_upgrade": "emblem-ember-upgrade/emblem-ember-upgrade-a1.png",
	"emblem_ember_evolve": "emblem-ember-evolve/emblem-ember-evolve-a1.png", "emblem_ember_deal": "emblem-ember-deal/emblem-ember-deal-a1.png",
	"emblem_frost_new": "emblem-frost-new/emblem-frost-new-a1.png", "emblem_frost_upgrade": "emblem-frost-upgrade/emblem-frost-upgrade-a1.png",
	"emblem_frost_evolve": "emblem-frost-evolve/emblem-frost-evolve-a1.png",
	"spell_ember": "spell-ember/spell-ember-a1.png", "spell_frost": "spell-frost/spell-frost-a1.png", "spell_arc": "spell-arc/spell-arc-a1.png",
	"spell_ember_ring": "spell-ember-ring/spell-ember-ring-a1.png", "spell_frost_ring": "spell-frost-ring/spell-frost-ring-a1.png",
	"spell_arc_ring": "spell-arc-ring/spell-arc-ring-a2.png",
	"demon_ember": "pledge-ember-full/pledge-ember-full-a1.png", "demon_frost": "pledge-frost-full-c/pledge-frost-full-c-a1.png",
	"demon_arc": "pledge-arc-full/pledge-arc-full-a2.png",
}

static var _dir_ready := false
static var _kit_dir := ""
static var _queue_dir := ""
static var _index := {}      ## name -> {"file": abs path, ...meta from KIT.json}
static var _tex := {}        ## name -> Texture2D or null (looked up once)
static var _sources := {}    ## part -> "kit" | "queue" | "atlas" | "code"
static var _sh_normal: Shader
static var _sh_add: Shader

static func _find_dir(rel: String) -> String:
	var dir := ProjectSettings.globalize_path("res://").rstrip("/")
	for i in 6:
		var p := dir.path_join(rel)
		if DirAccess.dir_exists_absolute(p): return p
		dir = dir.get_base_dir()
	return ""

## Point the kit at another folder (tests / the director). Resets everything loaded so far.
static func use_kit_dir(path: String) -> void:
	_dir_ready = true
	_kit_dir = path
	_queue_dir = _find_dir("_local/art/queue")
	_index.clear()
	_tex.clear()
	_sources.clear()
	_load_index()

static func _init_dirs() -> void:
	if _dir_ready: return
	_dir_ready = true
	var given := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--grace-kit="): given = arg.trim_prefix("--grace-kit=")
	if given != "":
		_kit_dir = given if given.is_absolute_path() else ProjectSettings.globalize_path("res://").rstrip("/").path_join(given)
	else:
		_kit_dir = _find_dir("_local/art/grace-kit")
	_queue_dir = _find_dir("_local/art/queue")
	_load_index()

static func _add_entry(name_: String, v: Variant) -> void:
	if name_ == "": return
	var meta := {}
	if v is String: meta = {"file": String(v)}
	elif v is Dictionary: meta = (v as Dictionary).duplicate()
	var f := String(meta.get("file", meta.get("path", "")))
	if f == "": return
	meta["file"] = f if f.is_absolute_path() else _kit_dir.path_join(f)
	_index[name_] = meta

## KIT.json (written by the asset-producer): {"files": {name: "file.png" | {file, margins, wick, ...}}} or a list of {name, file}. Tolerant on purpose.
static func _load_index() -> void:
	if _kit_dir == "" or not FileAccess.file_exists(_kit_dir.path_join("KIT.json")): return
	var doc := Kit.read_json(_kit_dir.path_join("KIT.json"))
	var src: Variant = doc
	for k in ["files", "items", "assets", "parts"]:
		if doc.has(k):
			src = doc[k]
			break
	if src is Dictionary:
		for k in (src as Dictionary).keys(): _add_entry(String(k), (src as Dictionary)[k])
	elif src is Array:
		for e in src:
			if e is Dictionary: _add_entry(String(e.get("name", e.get("id", ""))), e)

static func meta(name_: String) -> Dictionary:
	_init_dirs()
	tex(name_)
	return _index.get(name_, {})

## The absolute path a name resolves to ("" when no picture exists) and where it came from.
static func _aliases(name_: String) -> Array:
	var alias := name_.replace("_", "-")
	var out: Array = [name_, alias]
	if name_.begins_with("frame_") or name_.begins_with("bg_"): out.append("grade-" + alias)
	if name_ == "sigil": out.append("jackpot-light-sigil")
	if name_ in ["board", "title_plaque", "jackpot_plaque", "reliquary", "parchment", "candle", "knobs"]: out.append("grace-" + alias)
	if name_.begins_with("knob_"): out.append("grace-" + alias)
	return out

static func path_of(name_: String) -> Array:
	_init_dirs()
	var names := _aliases(name_)
	for n in names:
		if _index.has(n) and FileAccess.file_exists(String(_index[n].file)):
			if n != name_: _index[name_] = _index[n]
			return [String(_index[n].file), "kit"]
	if _kit_dir != "":
		for n in names:
			var p: String = _kit_dir.path_join(String(n) + ".png")
			if FileAccess.file_exists(p): return [p, "kit"]
	if QUEUE_FILES.has(name_) and _queue_dir != "":
		var q: String = _queue_dir.path_join(String(QUEUE_FILES[name_]))
		if FileAccess.file_exists(q): return [q, "queue"]
	return ["", ""]

static func tex(name_: String) -> Texture2D:
	if _tex.has(name_): return _tex[name_]
	var found := path_of(name_)
	var t: Texture2D = null
	if String(found[0]) != "":
		var image := Image.load_from_file(String(found[0]))
		if image != null and not image.is_empty():
			if image.get_format() != Image.FORMAT_RGBA8: image.convert(Image.FORMAT_RGBA8)
			image.generate_mipmaps()
			t = ImageTexture.create_from_image(image)
	_tex[name_] = t
	return t

## The thickness of the frame band (the part text must stay inside) as fractions of the picture: Vector2(left / width, top / height).
## From KIT.json margins.band of the kit entry; without it a default that fits the three generated frames.
static func frame_band(key: String) -> Vector2:
	var m: Dictionary = meta("frame_" + key)
	var sz: Variant = m.get("size", null)
	var band: Variant = (m.get("margins", {}) as Dictionary).get("band", null) if m.get("margins", null) is Dictionary else null
	if band is Dictionary and sz is Array and (sz as Array).size() >= 2:
		return Vector2(float(band.left) / float(sz[0]), float(band.top) / float(sz[1]))
	return {"common": Vector2(0.105, 0.081), "rare": Vector2(0.10, 0.078), "jackpot": Vector2(0.13, 0.11)}.get(key, Vector2(0.115, 0.082))

static func source_of(name_: String) -> String:
	tex(name_)
	return String(path_of(name_)[1])

static func note_source(part: String, how: String) -> void:
	_sources[part] = how

static func report() -> Dictionary:
	return _sources.duplicate()

static func kit_folder() -> String:
	_init_dirs()
	return _kit_dir

## One line for the screen's own dev tag: which parts used the kit / queue originals / the HUD atlas / code shapes.
static func report_line() -> String:
	var by := {"kit": [], "queue": [], "atlas": [], "code": []}
	for k in _sources.keys(): by[_sources[k]].append(String(k))
	var out: Array = []
	for how in ["kit", "queue", "atlas", "code"]:
		if not (by[how] as Array).is_empty(): out.append("%s: %s" % [how, ", ".join(by[how])])
	return " · ".join(out)

## Keys magenta (#FF00FF) to transparent (soft edge + despill), and sets saturation / brightness / tint. `add` = additive blending.
static func art_material(sat := 1.0, bright := 1.0, add := false, tint := Color.WHITE) -> ShaderMaterial:
	if _sh_normal == null:
		var body := "uniform float sat = 1.0;\nuniform float bright = 1.0;\nuniform vec4 tint : source_color = vec4(1.0);\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tfloat mn = min(c.r, c.b);\n\tfloat k = smoothstep(0.62, 0.82, mn) * (1.0 - smoothstep(0.22, 0.45, c.g));\n\tfloat spill = max(0.0, mn - c.g) * smoothstep(0.35, 0.7, mn);\n\tvec3 rgb = c.rgb - vec3(spill * 0.85, 0.0, spill * 0.85);\n\tfloat l = dot(rgb, vec3(0.299, 0.587, 0.114));\n\trgb = mix(vec3(l), rgb, sat) * bright;\n\tCOLOR = vec4(rgb, c.a * (1.0 - k)) * tint;\n}\n"
		_sh_normal = Shader.new()
		_sh_normal.code = "shader_type canvas_item;\n" + body
		_sh_add = Shader.new()
		_sh_add.code = "shader_type canvas_item;\nrender_mode blend_add;\n" + body
	var m := ShaderMaterial.new()
	m.shader = _sh_add if add else _sh_normal
	m.set_shader_parameter("sat", sat)
	m.set_shader_parameter("bright", bright)
	m.set_shader_parameter("tint", tint)
	return m

## A picture child filling `rect` (null when the picture does not exist: the caller falls back). The picture is painted in the child's own
## _draw (not a TextureRect node), so layered art over text is not an "overlap" for tools/dev/hud_layout_check.py (it only sees content nodes).
class ArtLayer extends Control:
	var texture: Texture2D:
		set(v):
			texture = v
			queue_redraw()
	func _draw() -> void:
		if texture != null: draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)

class GlowLayer extends Control:
	func _draw() -> void:
		draw_texture_rect(Kit.glow(), Rect2(Vector2.ZERO, size), false)

static func art_rect(parent: Node, name_: String, rect: Rect2, o := {}) -> Control:
	var t := tex(name_)
	if t == null: return null
	var r := ArtLayer.new()
	r.name = name_
	r.texture = t
	r.position = rect.position
	r.size = rect.size
	r.pivot_offset = rect.size * 0.5
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.material = art_material(float(o.get("sat", 1.0)), float(o.get("bright", 1.0)), bool(o.get("add", false)), o.get("tint", Color.WHITE))
	parent.add_child(r)
	return r

## A soft round light (additive by default) painted in _draw; `color` carries its alpha.
static func glow_rect(parent: Node, centre: Vector2, radius: float, color: Color, additive := true) -> Control:
	var g := GlowLayer.new()
	g.position = centre - Vector2(radius, radius)
	g.size = Vector2(radius, radius) * 2.0
	g.modulate = color
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if additive:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		g.material = m
	parent.add_child(g)
	return g

# ============================================================ small helpers
## A child Control that is painted by `fn(control)` (drawn during the control's own draw signal).
static func layer(parent: Control, fn: Callable, rect := Rect2()) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.position = rect.position
	c.size = rect.size if rect.size != Vector2.ZERO else parent.size
	c.draw.connect(fn.bind(c))
	parent.add_child(c)
	return c

## The biggest font size (>= min_size) at which `text` fits `width` on one line. Never below min_size.
static func fit_size(text: String, size: int, width: float, role: String, min_size: int) -> int:
	var s := size
	while s > min_size and Kit.measure(text, s, 99999.0, role).x > width: s -= 1
	return s

## Text that has to fit one line: shrink first; if it still does not fit, cut at the first " · " (a whole word group, never mid-word).
static func fit_text(text: String, size: int, width: float, role: String, min_size: int) -> Dictionary:
	var s := fit_size(text, size, width, role, min_size)
	var t := text
	if Kit.measure(t, s, 99999.0, role).x > width and " · " in t:
		t = t.get_slice(" · ", 0)
		s = fit_size(t, size, width, role, min_size)
	return {"text": t, "size": s}

static func _is_dev_text(s: String) -> bool:
	return "시스템 요청" in s or "임시 값" in s or "임시 그림" in s

## Dev lines the proposals keep out of the screen (they go to the dev tag).
static func dev_notes(contract: Dictionary) -> String:
	var out: Array = []
	for c in contract.get("cards", []):
		for key in ["details", "stats"]:
			for line in c.get(key, []):
				if _is_dev_text(String(line)) and not String(line) in out: out.append(String(line))
	return " / ".join(out)

## The medallion picture of a card kind, or null. kind: new / upgrade / evolve / trade|prep -> deal.
static func emblem_name(element: String, kind: String) -> String:
	var k: String = {"new": "new", "upgrade": "upgrade", "evolve": "evolve", "trade": "deal", "prep": "deal", "deal": "deal"}.get(kind, "new")
	return "emblem_%s_%s" % [element, k]

## A round spell mark: the spell picture (basic or ring) when it exists, else the code emblem of kit.gd.
static func spell_icon(parent: Control, emblem: String, element: String, box: Rect2) -> Control:
	var name_ := "spell_%s%s" % [element, "_ring" if emblem == "ring" else ""]
	if emblem == "ring" and tex(name_ + "_v2") != null: name_ += "_v2"   ## the redrawn orbiting ring (kit); the old walled ring stays as the fallback
	var a := art_rect(parent, name_, box)
	if a != null:
		note_source("spell icons", source_of(name_))
		return a
	var e = Kit.Emblem.new(emblem, element, box.size)
	e.position = box.position
	parent.add_child(e)
	note_source("spell icons", "code")
	return e

# ============================================================ GraceCard
## The shape of one card (spec 5.2) on a 300 x 470 reference; every size scales with min(w/300, h/470) but no text goes below 14.
##   top row: element badge + header .......... grade diamonds + grade name   (rare / jackpot only; the common card has no grade word)
##   emblem (46% of the height)  ->  name 26  ->  tag 15  ->  number 30 "before -> after ^" (or the one-line text of a new card)  ->  combo row
## Grade reads by FORM first (steel straight / bronze with spikes / gold with crown spikes), then the ground brightness, then the name colour.
class GraceCard extends Control:
	signal clicked(i: int)
	signal hovered(i: int)
	var P = load(PARTS_PATH)
	var idx := 0
	var data := {}
	var gkey := "common"
	var art_face := false
	var focus := 0.0:
		set(v):
			focus = v
			if _fx != null: _fx.queue_redraw()
			if _under != null and not art_face: _under.queue_redraw()
	var leak := 0.0:
		set(v):
			leak = v
			if _fx != null: _fx.queue_redraw()
	var sweep := -1.0:
		set(v):
			sweep = v
			if _fx != null: _fx.queue_redraw()
	var face_up := true:
		set(v):
			face_up = v
			for n in _front: n.visible = v
			if _back != null: _back.visible = not v
			if _fx != null: _fx.queue_redraw()
	var animated := true
	var emblem_box := Rect2()   ## the medallion, in card coordinates (a flying mark starts here)
	var row_y := 0.0
	var grade_text_w := 0.0
	var _under: Control
	var _fx: Control
	var _back: Control
	var _sigil: Control
	var _front: Array = []
	var _art_nodes: Array = []   ## the picture layers (dimmed by set_focus_amount); the TEXT keeps its full colour so it stays readable on a dimmed card

	func build(card: Dictionary, i: int, sz: Vector2, ui: Dictionary) -> void:
		idx = i
		data = card
		size = sz
		custom_minimum_size = sz
		pivot_offset = sz * 0.5
		mouse_filter = Control.MOUSE_FILTER_STOP
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		gkey = P.grade_key(String(card.get("grade", "common")))
		var el := String(card.get("element", "frost"))
		var w := sz.x
		var h := sz.y
		var s := minf(w / 300.0, h / 470.0)
		var band: Vector2 = P.frame_band(gkey) if P.tex("frame_" + gkey) != null else Vector2(0.115, 0.082)
		var inset := w * band.x + 8.0
		var inner := w - inset * 2.0
		var rank: int = P.grade_rank(gkey)
		art_face = P.tex("frame_" + gkey) != null and P.tex("bg_" + gkey) != null
		_under = P.layer(self, Callable(self, "_paint_under"))
		if art_face:
			var bg: Control = P.art_rect(self, "bg_" + gkey, Rect2(Vector2.ZERO, sz), {"bright": [0.92, 1.28, 1.08][rank], "tint": [Color.WHITE, Color(1.1, 1.0, 0.84), Color.WHITE][rank]})
			_front.append(bg)
			_art_nodes.append(bg)
			P.note_source("card ground", P.source_of("bg_" + gkey))
			var shade: Control = P.layer(self, Callable(self, "_paint_shade"))
			_front.append(shade)
			_art_nodes.append(shade)
		else:
			P.note_source("card ground", "code")
		_front.append(_under)
		_art_nodes.append(_under)
		# medallion: behind it the grade light (rare: a thin warm rim; jackpot: the turning sigil, additive)
		var emb := minf(w * 0.70, h * 0.44)
		emblem_box = Rect2(Vector2((w - emb) * 0.5, h * 0.145), Vector2(emb, emb))
		var ec := emblem_box.get_center()
		if rank >= 1:
			var halo: Control = P.glow_rect(self, ec, emb * (0.62 if rank == 1 else 0.78), Color(Palette.BRASS_HI.r, Palette.BRASS_HI.g, Palette.BRASS_HI.b, 0.22 if rank == 1 else 0.40))
			_front.append(halo)
		if rank >= 2:
			_sigil = P.art_rect(self, "sigil", Rect2(ec - Vector2(emb, emb) * 0.62, Vector2(emb, emb) * 1.24), {"add": true, "tint": Color(1, 1, 1, 0.55)})
			if _sigil != null:
				_front.append(_sigil)
				_art_nodes.append(_sigil)
				P.note_source("jackpot sigil", P.source_of("sigil"))
			else:
				P.note_source("jackpot sigil", "code")
		var en: String = P.emblem_name(el, String(card.get("kind", "new")))
		var sat: float = [0.8, 1.0, 1.1][rank]
		var emb_art: Control = P.art_rect(self, en, emblem_box, {"sat": sat, "bright": [0.92, 1.0, 1.06][rank]})
		if emb_art != null:
			_front.append(emb_art)
			_art_nodes.append(emb_art)
			P.note_source("card emblems", P.source_of(en))
		else:
			var ce = Kit.Emblem.new(String(card.get("emblem", "ring")), el, emblem_box.size, false)
			ce.position = emblem_box.position
			ce.tone = [0.6, 1.0, 1.0][rank]
			add_child(ce)
			_front.append(ce)
			_art_nodes.append(ce)
			P.note_source("card emblems (missing ones)", "code")
		if art_face:
			var fr: Control = P.art_rect(self, "frame_" + gkey, Rect2(Vector2.ZERO, sz))
			_front.append(fr)
			_art_nodes.append(fr)
			P.note_source("card frames", P.source_of("frame_" + gkey))
		else:
			P.note_source("card frames", "code")
		# text
		row_y = h * 0.115
		var small := maxi(14, int(round(15.0 * s)))
		var grade_name := String(card.get("grade_name", ""))
		var gw := 0.0
		if rank >= 1 and grade_name != "":
			gw = Kit.measure(grade_name, small, 9999.0, "bold").x
			var gl: Label = Kit.lbl(self, grade_name, Vector2(w - inset - gw - 2.0, row_y), gw + 4.0, small, P.name_color(gkey), "bold", HORIZONTAL_ALIGNMENT_RIGHT, false, true)
			_front.append(gl)
		grade_text_w = gw
		var head_x := inset + 24.0 * s
		var head_w := inner - 24.0 * s - (gw + 14.0 + 12.0 * rank if gw > 0.0 else 0.0)
		var header := String(card.get("header", ""))
		if header != "":
			var hf: Dictionary = P.fit_text(header, maxi(14, int(round(14.0 * s))), head_w, "bold", 14)
			var hl: Label = Kit.lbl(self, String(hf.text), Vector2(head_x, row_y), head_w, int(hf.size), Palette.INK_DIM, "bold", HORIZONTAL_ALIGNMENT_LEFT, false, true)
			_front.append(hl)
		var y := emblem_box.end.y + h * 0.006
		var nf: Dictionary = P.fit_text(String(card.get("name", "")), maxi(16, int(round(26.0 * s))), inner, "heading", 16)
		var nl: Label = Kit.lbl(self, String(nf.text), Vector2(inset, y), inner, int(nf.size), P.name_color(gkey), "heading", HORIZONTAL_ALIGNMENT_CENTER, false, true)
		_front.append(nl)
		y += nl.size.y - 2.0
		var tag := String(card.get("kind_label", ""))
		if String(card.get("tier", "")) != "" and String(card.tier) != grade_name: tag += "  " + String(card.tier)
		var tf: Dictionary = P.fit_text(tag, small, inner, "bold", 14)
		var tl: Label = Kit.lbl(self, String(tf.text), Vector2(inset, y), inner, int(tf.size), Kit.el_text(el), "bold", HORIZONTAL_ALIGNMENT_CENTER, false, true)
		_front.append(tl)
		y += tl.size.y + 2.0
		var d: Variant = card.get("delta", null)
		if d is Dictionary:
			var num := "%s → %s ▲" % [d.before, d.after]
			var xf: Dictionary = P.fit_text(num, maxi(18, int(round(30.0 * s))), inner, "number", 18)
			var vl: Label = Kit.lbl(self, String(xf.text), Vector2(inset, y), inner, int(xf.size), Kit.GAIN, "number", HORIZONTAL_ALIGNMENT_CENTER, false, true)
			_front.append(vl)
			y += vl.size.y + 2.0
		else:
			var line := String(card.get("line", card.get("headline", "")))
			# a one-line summary of a new card; when it does not fit the room left (a small card) it is left to the side note, never cut
			var need: float = Kit.measure(line, small, inner, "body").y + 4.0
			if need <= h * 0.885 - y - (24.0 if card.get("combo", []).size() > 0 else 0.0):
				var ll: Label = Kit.lbl(self, line, Vector2(inset, y), inner, small, Palette.INK, "body", HORIZONTAL_ALIGNMENT_CENTER, true, true)
				_front.append(ll)
				y += ll.size.y + 2.0
		var combo: Array = card.get("combo", [])
		y += 10.0   ## a clear step above the combo row (a tilted card's text boxes must not touch in the layout check)
		var room := h * 0.885 - y
		if combo.size() > 0 and room >= 22.0 * s:
			var cw := Kit.measure(String(ui.get("combo", "")), small, 9999.0, "bold").x
			var ic := minf(24.0 * s + 2.0, 26.0)
			var total := cw + 8.0 + ic * 2.0 + 14.0
			var x0 := (w - total) * 0.5
			var cl: Label = Kit.lbl(self, String(ui.get("combo", "")), Vector2(x0, y + 1.0), cw + 4.0, small, Kit.el_text(el), "bold", HORIZONTAL_ALIGNMENT_LEFT, false, true)
			_front.append(cl)
			var c0: Dictionary = combo[0]
			var a: Control = P.spell_icon(self, String(c0["from"]), String(c0.from_element), Rect2(Vector2(x0 + cw + 8.0, y), Vector2(ic, ic)))
			var arrow: Label = Kit.lbl(self, "→", Vector2(x0 + cw + 8.0 + ic, y), 14.0, 14, Palette.LINEN, "bold", HORIZONTAL_ALIGNMENT_CENTER, false, true)
			var b: Control = P.spell_icon(self, String(c0["to"]), String(c0.to_element), Rect2(Vector2(x0 + cw + 8.0 + ic + 14.0, y), Vector2(ic, ic)))
			_front.append_array([cl, a, arrow, b])
		_back = _make_back()
		_back.visible = false
		_fx = P.layer(self, Callable(self, "_paint_fx"))
		_fx.name = "Fx"
		gui_input.connect(_on_gui_input)
		mouse_entered.connect(func(): hovered.emit(idx))
		set_process(_sigil != null)

	func _process(delta: float) -> void:
		if _sigil != null and animated: _sigil.rotation += delta * 0.18

	## The card's back: the HUD's leather plate with the brass cross medal (the seal), tinted by the element. (Used by the fan proposal.)
	func _make_back() -> Control:
		var back := Control.new()
		back.size = size
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var plate := Panel.new()
		plate.size = size
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := AtlasBox.new()
		box.piece = "notice_card"
		box.margins_px = Vector4(70, 70, 70, 70)
		box.line_color = Palette.BRASS_DIM
		plate.add_theme_stylebox_override("panel", box)
		back.add_child(plate)
		P.layer(back, Callable(self, "_paint_back"))
		add_child(back)
		return back

	func _paint_back(c: Control) -> void:
		var el := String(data.get("element", "frost"))
		UiStyle.blit_centered(c, "medal_cross", c.size * 0.5, minf(c.size.x / 184.0, c.size.y / 300.0) * 1.6)
		c.draw_arc(c.size * 0.5, minf(c.size.x, c.size.y) * 0.3, 0, TAU, 48, Kit.with_alpha(Kit.el_color(el), 0.55), 2.0, true)

	func _paint_under(c: Control) -> void:
		if art_face: return
		Kit.draw_face(c, Rect2(Vector2.ZERO, size), P._kit_grade(gkey), focus, 0.0)

	## A dark reading ground under the lower text so 4.5:1 holds on every grade ground.
	func _paint_shade(c: Control) -> void:
		var r := Rect2(Vector2(0, size.y * 0.5), Vector2(size.x, size.y * 0.5))
		Kit.quad(c, r, Color(0.02, 0.015, 0.01, 0.0), Color(0.02, 0.015, 0.01, 0.62))
		Kit.quad(c, Rect2(Vector2.ZERO, Vector2(size.x, size.y * 0.14)), Color(0.02, 0.015, 0.01, 0.45), Color(0.02, 0.015, 0.01, 0.0))

	## Top row marks (element badge, grade diamonds), the focus ring, the seeping grade light, the sweep.
	func _paint_fx(c: Control) -> void:
		if not face_up:
			_paint_back_fx(c)
			return
		var el := String(data.get("element", "frost"))
		var s := minf(size.x / 300.0, size.y / 470.0)
		var fb: Vector2 = P.frame_band(gkey) if art_face else Vector2(0.115, 0.082)
		var inset := size.x * fb.x + 8.0
		var rank: int = P.grade_rank(gkey)
		Kit.draw_badge(c, el, Vector2(inset + 9.0 * s, row_y + 10.0), 7.0 * s + 1.0, Kit.el_color(el))
		var gc: Color = P.name_color(gkey)
		for k in rank:
			Kit.diamond(c, Vector2(size.x - inset - grade_text_w - 12.0 - float(k) * 13.0, row_y + 10.0), 5.0, gc, true)
		if leak > 0.0:
			for k in 7:
				c.draw_rect(Rect2(Vector2.ZERO, size).grow(float(k) * 3.0), Kit.with_alpha(gc, 0.30 * leak * (1.0 - float(k) / 7.0)), false, 3.0)
		if focus > 0.0:
			for k in 6:
				c.draw_rect(Rect2(Vector2.ZERO, size).grow(float(k) * 3.0 + 1.0), Kit.with_alpha(Palette.BRASS_HI, 0.26 * focus * (1.0 - float(k) / 6.0)), false, 3.0)
			c.draw_rect(Rect2(Vector2.ZERO, size), Kit.with_alpha(Palette.BRASS_HI, focus), false, 3.0)
		if sweep >= 0.0 and sweep <= 1.0:
			var x := -50.0 + (size.x + 100.0) * sweep
			var band := PackedVector2Array([Vector2(x, 0), Vector2(x + 34, 0), Vector2(x - 20, size.y), Vector2(x - 54, size.y)])
			c.draw_colored_polygon(band, Kit.with_alpha(gc.lightened(0.3), 0.20))

	func _paint_back_fx(c: Control) -> void:
		if leak > 0.0:
			for k in 7:
				c.draw_rect(Rect2(Vector2.ZERO, size).grow(float(k) * 3.0), Kit.with_alpha(P.name_color(gkey), 0.36 * leak * (1.0 - float(k) / 7.0)), false, 3.0)

	## One call sets the whole reaction of a card: focus 0..1 -> ring, brightness, a small lift (scale <= 1.03).
	func set_focus_amount(f: float, mult := 1.0) -> void:
		focus = f
		var tone := lerpf(0.68, 1.0, f) * mult
		for n in _art_nodes: n.modulate = Color(tone, tone, tone * 1.03, 1.0)
		scale = Vector2.ONE * (1.0 + 0.03 * f)

	## Where the mark of this card starts a flight (global coordinates).
	func emblem_center() -> Vector2:
		return get_global_transform() * emblem_box.get_center()

	func _on_gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: clicked.emit(idx)

static func card(parent: Control, data: Dictionary, idx: int, size: Vector2, ui: Dictionary) -> GraceCard:
	var c := GraceCard.new()
	c.build(data, idx, size, ui)
	parent.add_child(c)
	return c

# ============================================================ Knob (the three hand-wheels: reroll / exclude / keep)
## A round brass button: the HUD's ring (slot_normal), a dark disc, a drawn glyph, the count on a small brass badge (level_badge, top right),
## the key on a leather plate (key_tag) under it, the word under that. Shape = glyph, so the three differ without colour.
## glyph: swirl (reroll) / slash (exclude) / latch (keep). The kit may give a picture per knob (name "knob_<id>") or one strip "knobs" (thirds).
class Knob extends Control:
	signal pressed(id: String)
	var P = load(PARTS_PATH)
	var id := ""
	var glyph := "swirl"
	var enabled := true
	var disc := Vector2(0, 0)
	var hot := 0.0:
		set(v):
			hot = v
			if _over != null: _over.queue_redraw()
	var down := false
	var _over: Control
	var _art: Control

	## spec: {id, glyph, key, label, count}. Width is fixed (118); height 150.
	func build(spec: Dictionary, order: int) -> void:
		id = String(spec.id)
		glyph = String(spec.glyph)
		enabled = String(spec.get("count", "1")) != "0"
		size = Vector2(118.0, 150.0)
		mouse_filter = Control.MOUSE_FILTER_STOP
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		disc = Vector2(size.x * 0.5, 50.0)
		var d := 84.0
		var drect := Rect2(disc - Vector2(d, d) * 0.5, Vector2(d, d))
		var how := "code"
		var per: String = "knob_" + id
		if P.tex(per) != null:
			_art = P.art_rect(self, per, drect.grow(6.0))
			how = P.source_of(per)
		elif P.tex("knobs") != null:
			_art = P.art_rect(self, "knobs", drect.grow(6.0))
			var t: Texture2D = P.tex("knobs")
			var at := AtlasTexture.new()
			at.atlas = t
			at.region = Rect2(t.get_width() * order / 3.0, 0, t.get_width() / 3.0, t.get_height())
			_art.texture = at
			how = P.source_of("knobs")
		P.note_source("knobs", how if how != "code" else "atlas")
		var base: Control = P.layer(self, Callable(self, "_paint_base"))
		move_child(base, 0)
		_over = P.layer(self, Callable(self, "_paint_over"))
		var badge_c := disc + Vector2(32.0, -30.0)
		var cnt := Kit.lbl(self, String(spec.get("count", "")), badge_c - Vector2(16.0, 12.0), 32.0, 18, Palette.INK, "number", HORIZONTAL_ALIGNMENT_CENTER, false, true)
		cnt.name = "Count"
		var key := String(spec.get("key", ""))
		if key != "":
			var kl := Kit.lbl(self, key, Vector2(size.x * 0.5 - 30.0, 98.0), 60.0, 15, Palette.INK, "number", HORIZONTAL_ALIGNMENT_CENTER, false, true)
			kl.name = "Key"
		var wl := Kit.lbl(self, String(spec.get("label", "")), Vector2(0.0, 124.0), size.x, 15, Palette.INK if enabled else Palette.INK_FAINT, "bold", HORIZONTAL_ALIGNMENT_CENTER, false, true)
		wl.name = "Label"
		modulate = Color.WHITE if enabled else Color(1, 1, 1, 0.55)
		gui_input.connect(func(e):
			if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
				down = e.pressed
				if e.pressed and enabled: pressed.emit(id)
				_over.queue_redraw())
		mouse_entered.connect(func(): hot = 1.0)
		mouse_exited.connect(func(): hot = 0.0)

	func _paint_base(c: Control) -> void:
		if _art != null: return
		c.draw_circle(disc + Vector2(0, 3), 40.0, Color(0, 0, 0, 0.5))
		c.draw_circle(disc, 36.0, Palette.SLOT)
		c.draw_circle(disc, 30.0, Color(0.035, 0.04, 0.045))

	func _paint_over(c: Control) -> void:
		var dc := disc + (Vector2(0, 2) if down else Vector2.ZERO)
		if _art == null:
			UiStyle.blit_centered(c, "slot_normal", dc, 84.0 / 80.0)
			_glyph(c, dc, 21.0)
		if hot > 0.0 and enabled:
			c.draw_arc(dc, 44.0, 0, TAU, 40, Kit.with_alpha(Palette.BRASS_HI, 0.9 * hot), 3.0, true)
		UiStyle.blit_centered(c, "level_badge", disc + Vector2(32.0, -30.0), 1.2)
		if _has_key():
			UiStyle.blit_centered(c, "key_tag", Vector2(size.x * 0.5, 108.0), 1.45)

	func _has_key() -> bool:
		return get_node_or_null("Key") != null

	## The three glyphs, drawn in brass-light: a spiral that winds back (reroll), crossed cuts (exclude), a clasp (keep).
	func _glyph(c: Control, ctr: Vector2, r: float) -> void:
		var col := Palette.BRASS_HI if enabled else Palette.BRASS_DIM
		match glyph:
			"swirl":
				var pts := PackedVector2Array()
				for k in 30:
					var t := float(k) / 29.0
					pts.append(ctr + Vector2.from_angle(-1.2 + t * 4.6 * PI * 0.62) * r * (1.0 - 0.78 * t))
				c.draw_polyline(pts, col, 3.0, true)
				var tip := pts[pts.size() - 1]
				var back := (pts[pts.size() - 2] - tip).normalized()
				c.draw_colored_polygon(PackedVector2Array([tip + back.rotated(0.7) * 8.0, tip, tip + back.rotated(-0.7) * 8.0 + back * 2.0]), col)
			"slash":
				for sgn in [-1.0, 1.0]:
					var a := ctr + Vector2(-r * 0.8, -r * 0.8 * sgn)
					var b := ctr + Vector2(r * 0.8, r * 0.8 * sgn)
					c.draw_line(a, b, col, 4.0, true)
					c.draw_line(a, b, Palette.INK, 1.2, true)
			_:
				c.draw_arc(ctr + Vector2(0, -4), r * 0.5, PI, TAU, 16, col, 3.5, true)
				c.draw_line(ctr + Vector2(-r * 0.5, -4), ctr + Vector2(-r * 0.5, 4), col, 3.5)
				c.draw_line(ctr + Vector2(r * 0.5, -4), ctr + Vector2(r * 0.5, 4), col, 3.5)
				c.draw_rect(Rect2(ctr + Vector2(-r * 0.72, 4), Vector2(r * 1.44, r * 0.9)), col)
				c.draw_circle(ctr + Vector2(0, 4 + r * 0.45), 2.6, Color(0.05, 0.05, 0.06))

## Three knobs from the contract (reroll / exclude / keep; counts from reroll.left_label, exclude.left_label, keep.left_label).
## `gap` is the clear space between two knobs (>= 24 required; the knobs are 118 wide so the pitch is 118 + gap).
static func handles(parent: Control, contract: Dictionary, pos: Vector2, gap := 28.0) -> Array:
	var ui: Dictionary = contract.get("strings", {})
	var specs := [
		{"id": "reroll", "glyph": "swirl", "key": String(ui.get("key_reroll", "")), "label": String(ui.get("reroll", "")), "count": String(contract.get("reroll", {}).get("left_label", ""))},
		{"id": "exclude", "glyph": "slash", "key": String(ui.get("key_exclude", "")), "label": String(ui.get("exclude", "")), "count": String(contract.get("exclude", {}).get("left_label", ""))},
		{"id": "keep", "glyph": "latch", "key": String(ui.get("key_keep", "")), "label": String(ui.get("keep", "")), "count": String(contract.get("keep", {}).get("left_label", ""))},
	]
	var out: Array = []
	for i in specs.size():
		var k := Knob.new()
		k.build(specs[i], i)
		k.position = pos + Vector2(float(i) * (118.0 + gap), 0.0)
		parent.add_child(k)
		out.append(k)
	return out

# ============================================================ OwnedBand (owned spells strip)
## HUD leather strip (strip_left + tiled strip_tile + strip_right) with brass ring slots (slot_normal). Slots: the run's spells (picture + level),
## empty slots ("+"), the grace slots (smaller rings, a diamond when owned), the odds line at the right end. Same helpers as kit.gd's OwnedRow
## (slot_centre / target_for / link_slots / lit / lit_amount / pulse) so a chosen mark can fly to its slot.
class OwnedBand extends Control:
	const H := 66.0
	var P = load(PARTS_PATH)
	var owned := {}
	var ui := {}
	var chip := 52.0
	var centres := {"spell": [], "grace": []}
	var lit: Array = []
	var lit_amount := 0.0:
		set(v):
			lit_amount = v
			if _over != null: _over.queue_redraw()
	var pulse := 0.0:
		set(v):
			pulse = v
			if _over != null: _over.queue_redraw()
	var _over: Control
	var _under: Control

	func build(o: Dictionary, strings: Dictionary, odds: String, w: float) -> void:
		owned = o
		ui = strings
		size = Vector2(w, H)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_under = P.layer(self, Callable(self, "_paint_strip"))
		var x := 118.0
		var lb := Kit.lbl(self, String(ui.get("owned", "")), Vector2(x, H * 0.5 - 11.0), 100.0, 15, Palette.INK, "bold", HORIZONTAL_ALIGNMENT_LEFT, false, true)
		x += Kit.measure(String(ui.get("owned", "")), 15, 9999.0, "bold").x + 14.0
		centres.spell = []
		var spells: Array = o.get("spells", [])
		for i in int(o.get("slots", 3)):
			var c := Vector2(x + chip * 0.5, H * 0.5)
			centres.spell.append(c)
			if i < spells.size():
				P.spell_icon(self, String(spells[i].emblem), String(spells[i].element), Rect2(c - Vector2(chip, chip) * 0.43, Vector2(chip, chip) * 0.86))
				var lv := Kit.lbl(self, String(spells[i].level), c + Vector2(chip * 0.18, chip * 0.14), 22.0, 14, Palette.INK, "number", HORIZONTAL_ALIGNMENT_CENTER, false, true)
				lv.name = "Level%d" % i
			x += chip + 8.0
		x += 14.0
		var gtext := String(ui.get("graces", ""))
		Kit.lbl(self, gtext, Vector2(x, H * 0.5 - 11.0), 70.0, 15, Palette.INK, "bold", HORIZONTAL_ALIGNMENT_LEFT, false, true)
		x += Kit.measure(gtext, 15, 9999.0, "bold").x + 12.0
		centres.grace = []
		for i in int(o.get("grace_slots", 2)):
			centres.grace.append(Vector2(x + chip * 0.3, H * 0.5))
			x += chip * 0.6 + 8.0
		if odds != "":
			var ow := Kit.measure(odds, 15, 9999.0, "body").x + 6.0
			var ox := maxf(x + 12.0, w - 96.0 - ow)
			Kit.lbl(self, odds, Vector2(ox, H * 0.5 - 11.0), ow, 15, Palette.INK_DIM, "body", HORIZONTAL_ALIGNMENT_RIGHT, false, true).name = "Odds"
		_over = P.layer(self, Callable(self, "_paint_rings"))
		P.note_source("owned band", "atlas")

	func _paint_strip(c: Control) -> void:
		var tile := UiStyle.piece_size("strip_tile") * (H / UiStyle.piece_size("strip_tile").y)
		var cap_l := UiStyle.piece_size("strip_left") * (H / UiStyle.piece_size("strip_left").y)
		var cap_r := UiStyle.piece_size("strip_right") * (H / UiStyle.piece_size("strip_right").y)
		c.draw_rect(Rect2(Vector2(0, 6), Vector2(size.x, H - 8.0)), Color(0, 0, 0, 0.35))
		var x := cap_l.x - 2.0
		while x < size.x - cap_r.x + 2.0:
			var wdt := minf(tile.x, size.x - cap_r.x + 2.0 - x)
			UiStyle.blit_part(c, "strip_tile", Rect2(x, 0, wdt, H), wdt / tile.x)
			x += tile.x
		UiStyle.blit(c, "strip_left", Rect2(Vector2.ZERO, cap_l))
		UiStyle.blit(c, "strip_right", Rect2(Vector2(size.x - cap_r.x, 0), cap_r))
		var spells: Array = owned.get("spells", [])
		for i in centres.spell.size():
			var ctr: Vector2 = centres.spell[i]
			c.draw_circle(ctr, chip * 0.44, Color(0.015, 0.018, 0.02, 0.95))
			if i >= spells.size():
				c.draw_string(Loc.font("number"), ctr + Vector2(-5.0, 7.0), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Kit.with_alpha(Palette.BRASS, 0.8))
		for i in centres.grace.size():
			c.draw_circle(centres.grace[i], chip * 0.27, Color(0.015, 0.018, 0.02, 0.95))

	func _paint_rings(c: Control) -> void:
		for i in centres.spell.size():
			UiStyle.blit_centered(c, "slot_normal", centres.spell[i], chip / 80.0)
			if i in lit and lit_amount > 0.0:
				UiStyle.blit_centered(c, "slot_selected", centres.spell[i], chip / 80.0 * 1.12, Color(1, 1, 1, lit_amount))
		var graces: Array = owned.get("graces", [])
		for i in centres.grace.size():
			UiStyle.blit_centered(c, "slot_normal", centres.grace[i], chip * 0.6 / 80.0)
			if i < graces.size() and bool(graces[i].owned): Kit.diamond(c, centres.grace[i], chip * 0.16, Palette.GROWTH)
		if pulse > 0.0 and not centres.spell.is_empty():
			var tgt: Vector2 = centres.spell[mini((owned.get("spells", []) as Array).size(), centres.spell.size() - 1)]
			c.draw_arc(tgt, chip * (0.5 + 0.6 * (1.0 - pulse)), 0, TAU, 32, Kit.with_alpha(Palette.BRASS_HI, pulse), 3.0, true)

	func link_slots(card: Dictionary) -> Array:
		var out: Array = []
		for cb in card.get("combo", []):
			for end in ["from", "to"]:
				var k := String(cb[end])
				var e := String(cb[end + "_element"])
				if k == String(card.get("emblem", "")) and e == String(card.get("element", "")): continue
				for i in (owned.get("spells", []) as Array).size():
					var sp: Dictionary = owned.spells[i]
					if String(sp.emblem) == k and String(sp.element) == e and not i in out: out.append(i)
		return out

	func slot_centre(kind: String, index: int) -> Vector2:
		var arr: Array = centres[kind]
		if arr.is_empty(): return size * 0.5
		return arr[clampi(index, 0, arr.size() - 1)]

	## Where a chosen card lands (global): a new spell takes the first free slot, an upgrade its own chip, a grace the grace row.
	func target_for(card: Dictionary) -> Vector2:
		var spells: Array = owned.get("spells", [])
		if String(card.get("kind", "")) == "prep":
			var gi := 0
			for g in owned.get("graces", []):
				if bool(g.owned): gi += 1
			return global_position + slot_centre("grace", gi)
		if String(card.get("kind", "")) in ["new", "trade"]:
			return global_position + slot_centre("spell", spells.size())
		var si := 0
		for i in spells.size():
			if String(spells[i].name) == String(card.get("name", "")): si = i
		return global_position + slot_centre("spell", si)

static func band(parent: Control, pos: Vector2, width: float, contract: Dictionary) -> OwnedBand:
	var b := OwnedBand.new()
	b.build(contract.get("owned", {}), contract.get("strings", {}), String(contract.get("odds", "")), width)
	b.position = pos
	parent.add_child(b)
	return b

# ============================================================ SideNote (parchment, dark ink)
## The only place with explanation: name, headline, combo rows (marks + text), the path to evolution (beads), term glosses. Nothing is written
## twice (a line equal to an earlier one is dropped) and dev lines are left out. A block that does not fit is dropped whole, never cut.
class SideNote extends Control:
	const INK_PAPER := Color(0.13, 0.095, 0.06)
	const INK_PAPER_DIM := Color(0.27, 0.19, 0.11)
	var P = load(PARTS_PATH)
	var ui := {}
	var _holder: Control
	var _paper_art: Control

	func build(w: float, h: float, strings: Dictionary) -> void:
		ui = strings
		size = Vector2(w, h)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		# the paper's mean colour as a plain node under the picture: the layout dump reads it as the colour under the ink (the picture itself is invisible to it)
		var base := ColorRect.new()
		base.color = Color(0.75, 0.64, 0.46)
		base.size = size
		base.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(base)
		_paper_art = P.art_rect(self, "parchment", Rect2(Vector2.ZERO, size))
		if _paper_art != null: P.note_source("side note", P.source_of("parchment"))
		else:
			P.layer(self, Callable(self, "_paint_paper"))
			P.note_source("side note", "code")
		_holder = Control.new()
		_holder.size = size
		_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_holder)

	func _paint_paper(c: Control) -> void:
		var r := Rect2(Vector2.ZERO, size)
		c.draw_rect(r.grow(5.0), Color(0, 0, 0, 0.42))
		Kit.quad(c, r, Color(0.80, 0.70, 0.52), Color(0.70, 0.58, 0.40))
		var rng := RandomNumberGenerator.new()
		rng.seed = 41
		for i in int(size.x * size.y / 320.0):
			var p := Vector2(rng.randf() * size.x, rng.randf() * size.y)
			c.draw_rect(Rect2(p, Vector2(rng.randf_range(1.0, 3.0), 1.0)), Color(0.35, 0.25, 0.12, rng.randf_range(0.04, 0.12)))
		for k in 10:
			var a := 0.34 * (1.0 - float(k) / 10.0)
			c.draw_rect(r.grow(-float(k) * 1.8), Color(0.18, 0.10, 0.04, a), false, 2.0)
		for sx in [0.3, 0.7]:
			var stud := Vector2(size.x * sx, 14.0)
			c.draw_circle(stud + Vector2(0, 1.5), 7.0, Color(0, 0, 0, 0.4))
			c.draw_circle(stud, 6.5, Palette.BRASS_DIM)
			c.draw_circle(stud, 5.0, Palette.BRASS)
			c.draw_circle(stud + Vector2(-1.5, -1.5), 1.8, Color(Palette.LINEN, 0.85))

	func show_card(card: Dictionary) -> void:
		for ch in _holder.get_children():
			_holder.remove_child(ch)
			ch.queue_free()
		var art := _paper_art != null
		var pad := (size.x * 0.098 + 12.0) if art else 26.0
		var w := size.x - pad * 2.0
		var bottom := size.y - (size.y * 0.09 + 6.0 if art else 22.0)
		var y := (size.y * 0.11) if art else 34.0
		var seen: Array = []
		var el := String(card.get("element", "frost"))
		var nl: Label = Kit.lbl(_holder, String(card.get("name", "")), Vector2(pad, y), w, 22, INK_PAPER, "heading", HORIZONTAL_ALIGNMENT_LEFT, false)
		seen.append(String(card.get("name", "")))
		y += nl.size.y + 4.0
		var headline := String(card.get("headline", ""))
		if headline != "" and not P._is_dev_text(headline):
			var hl: Label = Kit.lbl(_holder, headline, Vector2(pad, y), w, 15, INK_PAPER, "body")
			seen.append(headline)
			y += hl.size.y + 8.0
		var lines: Array = []
		for line in card.get("details", []):
			var t := String(line)
			if t in seen or P._is_dev_text(t): continue
			seen.append(t)
			lines.append(t)
		for t in lines:
			var need: float = Kit.measure(String(t), 14, w).y + 4.0
			if y + need > bottom: break
			var dl: Label = Kit.lbl(_holder, String(t), Vector2(pad, y), w, 14, INK_PAPER_DIM, "body")
			y += dl.size.y + 2.0
		var combo: Array = card.get("combo", [])
		if combo.size() > 0:
			var need0 := 24.0 + 30.0 + Kit.measure(String(combo[0].text), 14, w).y
			if y + 8.0 + need0 <= bottom:
				y += 8.0
				Kit.lbl(_holder, String(ui.get("combo", "")), Vector2(pad, y), w, 14, INK_PAPER, "bold", HORIZONTAL_ALIGNMENT_LEFT, false)
				y += 22.0
				for cb in combo:
					var tl: float = Kit.measure(String(cb.text), 14, w).y
					if y + 30.0 + tl + 4.0 > bottom: break
					P.spell_icon(_holder, String(cb["from"]), String(cb.from_element), Rect2(Vector2(pad, y), Vector2(28, 28)))
					Kit.lbl(_holder, "→", Vector2(pad + 30.0, y + 3.0), 22.0, 18, INK_PAPER, "bold", HORIZONTAL_ALIGNMENT_CENTER, false)
					P.spell_icon(_holder, String(cb["to"]), String(cb.to_element), Rect2(Vector2(pad + 54.0, y), Vector2(28, 28)))
					y += 31.0
					var ct: Label = Kit.lbl(_holder, String(cb.text), Vector2(pad, y), w, 14, INK_PAPER_DIM, "body")
					y += ct.size.y + 5.0
		var path: Variant = card.get("path", null)
		if path is Dictionary and y + 62.0 <= bottom:
			y += 6.0
			Kit.lbl(_holder, String(path.label), Vector2(pad, y), w, 14, INK_PAPER, "bold", HORIZONTAL_ALIGNMENT_LEFT, false)
			y += 22.0
			var pips := Control.new()
			pips.position = Vector2(pad, y)
			pips.size = Vector2(w, 20.0)
			pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pips.draw.connect(func():
				for k in int(path.total):
					var p := Vector2(10.0 + float(k) * 24.0, 10.0)
					if k < int(path.filled): UiStyle.blit_centered(pips, "bead_gold", p, 0.85)
					else: UiStyle.blit_centered(pips, "bead_empty", p, 0.85))
			_holder.add_child(pips)
			y += 24.0
		var terms: Array = card.get("terms", [])
		for tm in terms:
			var gtxt := "%s  %s" % [tm.word, tm.gloss]
			var gn: float = Kit.measure(gtxt, 14, w).y + 4.0
			if y + gn > bottom: break
			if gtxt in seen: continue
			seen.append(gtxt)
			var tl2: Label = Kit.lbl(_holder, gtxt, Vector2(pad, y), w, 14, INK_PAPER, "body")
			y += tl2.size.y + 2.0

static func note(parent: Control, rect: Rect2, contract: Dictionary) -> SideNote:
	var n := SideNote.new()
	n.build(rect.size.x, rect.size.y, contract.get("strings", {}))
	n.position = rect.position
	parent.add_child(n)
	return n

# ============================================================ TitlePlaque / JackpotPlaque / board
## Brass name plate on leather. The art (N2) is used when it is in the kit; otherwise the HUD's name plate (boss_name) nine-sliced.
class TitlePlaque extends Control:
	var P = load(PARTS_PATH)
	func build(text: String, w: float, sub: String) -> void:
		var art: Texture2D = P.tex("title_plaque")
		var h := w / 3.0 if art != null else maxf(96.0, w * 0.19)
		size = Vector2(w, h)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if art != null:
			P.art_rect(self, "title_plaque", Rect2(Vector2.ZERO, size))
			P.note_source("title plaque", P.source_of("title_plaque"))
		else:
			var panel := Panel.new()
			panel.size = size
			panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var box := AtlasBox.new()
			box.piece = "boss_name"
			box.margins_px = Vector4(80, 34, 80, 34)
			panel.add_theme_stylebox_override("panel", box)
			add_child(panel)
			P.layer(self, Callable(self, "_paint_rim"))
			P.note_source("title plaque", "atlas")
		var ty := h * (0.20 if sub == "" else 0.14)
		var tl: Label = Kit.lbl(self, text, Vector2(w * 0.12, ty), w * 0.76, P.fit_size(text, 36, w * 0.76, "heading", 20), Palette.INK, "heading", HORIZONTAL_ALIGNMENT_CENTER, false, true)
		tl.name = "Title"
		if sub != "":
			var sl: Label = Kit.lbl(self, sub, Vector2(w * 0.12, ty + tl.size.y), w * 0.76, 15, Palette.INK_DIM, "body", HORIZONTAL_ALIGNMENT_CENTER, false, true)
			sl.name = "Sub"

	func _paint_rim(c: Control) -> void:
		c.draw_rect(Rect2(Vector2(7, 7), size - Vector2(14, 14)), Kit.with_alpha(Palette.BRASS, 0.55), false, 1.5)

static func title(parent: Control, text: String, width: float, sub := "") -> TitlePlaque:
	var p := TitlePlaque.new()
	p.build(text, width, sub)
	parent.add_child(p)
	return p

## The stamped "jackpot" word: a cast plate with amber inlay. Art N3, else the HUD name plate in amber with a crown of spikes drawn in code.
class JackpotPlaque extends Control:
	var P = load(PARTS_PATH)
	func build(text: String, sz: Vector2) -> void:
		size = sz
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		pivot_offset = sz * 0.5
		if P.tex("jackpot_plaque") != null:
			P.art_rect(self, "jackpot_plaque", Rect2(Vector2.ZERO, sz))
			P.note_source("jackpot plaque", P.source_of("jackpot_plaque"))
		else:
			var panel := Panel.new()
			panel.size = sz
			panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var box := AtlasBox.new()
			box.piece = "boss_name"
			box.margins_px = Vector4(80, 34, 80, 34)
			box.tint = Color(1.15, 0.78, 0.42)
			panel.add_theme_stylebox_override("panel", box)
			add_child(panel)
			P.layer(self, Callable(self, "_paint_crown"))
			P.note_source("jackpot plaque", "atlas")
		var fs: int = P.fit_size(text, 38, sz.x * 0.8, "heading", 22)
		var tl: Label = Kit.lbl(self, text, Vector2(sz.x * 0.1, sz.y * 0.5 - Kit.line_height(fs, "heading") * 0.5 + 2.0), sz.x * 0.8, fs, P.JACKPOT_GOLD, "heading", HORIZONTAL_ALIGNMENT_CENTER, false, true)
		tl.name = "Word"

	func _paint_crown(c: Control) -> void:
		var col: Color = P.JACKPOT_GOLD
		c.draw_rect(Rect2(Vector2(6, 6), size - Vector2(12, 12)), Kit.with_alpha(col, 0.8), false, 2.0)
		for k in 5:
			var x := size.x * (0.18 + 0.16 * float(k))
			var hgt := 16.0 if k == 2 else 10.0
			c.draw_colored_polygon(PackedVector2Array([Vector2(x - 9, 7), Vector2(x, 7 - hgt), Vector2(x + 9, 7)]), col)

static func jackpot(parent: Control, text: String, sz: Vector2) -> JackpotPlaque:
	var p := JackpotPlaque.new()
	p.build(text, sz)
	parent.add_child(p)
	return p

## The leather board the cards lie on (kit "board"): nine-sliced at scale `k` (corner 150 source px * k, margins_by_eye 150), the buckle of the top edge
## cut out of the stretched slice (leather copied over it) and drawn again unstretched on top. Fallback: the HUD notice card nine-sliced.
class BoardLayer extends Control:
	var P = load(PARTS_PATH)
	var patched: Texture2D
	var orig: Texture2D
	var margin := 150.0
	var k := 0.347
	func _draw() -> void:
		var tw := float(patched.get_width())
		var th := float(patched.get_height())
		var cm := margin * k
		var xs := [0.0, margin, tw - margin, tw]
		var ys := [0.0, margin, th - margin, th]
		var xd := [0.0, cm, size.x - cm, size.x]
		var yd := [0.0, cm, size.y - cm, size.y]
		for j in 3:
			for i in 3:
				draw_texture_rect_region(patched, Rect2(xd[i], yd[j], xd[i + 1] - xd[i], yd[j + 1] - yd[j]), Rect2(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j]))
		draw_texture_rect_region(orig, Rect2(Vector2(size.x * 0.5 - 70.0 * k, 0), Vector2(140.0 * k, 90.0 * k)), Rect2(700, 0, 140, 90))

static var _board_patched: Texture2D

static func board(parent: Control, rect: Rect2, corner := 52.0) -> Control:
	var t := tex("board")
	if t != null:
		if _board_patched == null:
			var img: Image = t.get_image()
			img.clear_mipmaps()
			img.blit_rect(img, Rect2i(560, 0, 140, 90), Vector2i(700, 0))
			img.generate_mipmaps()
			_board_patched = ImageTexture.create_from_image(img)
		var n := BoardLayer.new()
		n.patched = _board_patched
		n.orig = t
		n.k = corner / n.margin
		n.position = rect.position
		n.size = rect.size
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		n.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		parent.add_child(n)
		note_source("board", source_of("board"))
		return n
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := AtlasBox.new()
	box.piece = "notice_card"
	box.margins_px = Vector4(70, 70, 70, 70)
	box.line_color = Palette.BRASS_DIM
	panel.add_theme_stylebox_override("panel", box)
	parent.add_child(panel)
	note_source("board", "atlas")
	return panel

static var _rel_windows := []

## The three window holes of the reliquary picture in SOURCE pixels (found by scanning its alpha once): [Rect2, Rect2, Rect2].
static func reliquary_windows() -> Array:
	if not _rel_windows.is_empty(): return _rel_windows
	var t := tex("reliquary")
	if t == null: return []
	var img: Image = t.get_image()
	img.clear_mipmaps()
	var w := img.get_width()
	var h := img.get_height()
	var xr: Array = []
	var st := -1
	for x in w:
		var clear := img.get_pixel(x, h / 2).a < 0.08
		if clear and st < 0: st = x
		if not clear and st >= 0:
			if x - st > 100: xr.append([st, x - 1])
			st = -1
	for r in xr:
		var cx := (int(r[0]) + int(r[1])) / 2
		var y0 := h / 2
		var y1 := h / 2
		while y0 > 0 and img.get_pixel(cx, y0 - 1).a < 0.08: y0 -= 1
		while y1 < h - 1 and img.get_pixel(cx, y1 + 1).a < 0.08: y1 += 1
		_rel_windows.append(Rect2(r[0], y0, int(r[1]) - int(r[0]) + 1, y1 - y0 + 1))
	return _rel_windows

## The reliquary placed with its left top at `pos`, `width` wide (aspect of the picture kept). Returns {"node", "rect", "windows": [Rect2 in parent coordinates]}.
## Without the picture: {"node": null, windows: three even rects} so a scene still lays out.
static func reliquary(parent: Control, pos: Vector2, width: float) -> Dictionary:
	var t := tex("reliquary")
	if t == null:
		note_source("reliquary", "code")
		var hh := width * 0.667
		var out: Array = []
		for i in 3: out.append(Rect2(pos + Vector2(width * (0.07 + 0.31 * i), hh * 0.25), Vector2(width * 0.22, hh * 0.5)))
		return {"node": null, "rect": Rect2(pos, Vector2(width, hh)), "windows": out}
	var sc := width / float(t.get_width())
	var node := art_rect(parent, "reliquary", Rect2(pos, Vector2(width, float(t.get_height()) * sc)))
	var wins: Array = []
	for r in reliquary_windows(): wins.append(Rect2(pos + (r as Rect2).position * sc, (r as Rect2).size * sc))
	note_source("reliquary", source_of("reliquary"))
	return {"node": node, "rect": Rect2(pos, Vector2(width, float(t.get_height()) * sc)), "windows": wins}

# ============================================================ Candle (iron stand + wax from art or code; the flame is code)
## `lit_amount` 0..1 scales the flame and its light (a jackpot can raise it). `animated` false = a still flame (reduced motion). The flame is built
## from three layers (a wide additive light, the body, the hot core) and flickers with two sines of unrelated periods plus a slow random drift,
## so it never repeats in step with the other candle (each has its own phase).
class Candle extends Control:
	var P = load(PARTS_PATH)
	var flame_color := FLAME_WARM
	var lit_amount := 1.0
	var animated := true
	var wick := Vector2(0.5, 0.2)  ## where the flame sits, as a fraction of the candle's size
	var _t := 0.0
	var _phase := 0.0
	var _art: Control
	var _flame: Control
	var _light: Control

	func build(sz: Vector2, color: Color, phase := 0.0) -> void:
		size = sz
		flame_color = color
		_phase = phase
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if P.tex("candle") != null:
			# the kit candle has no flame: the control grows upward by `room` so the code flame has space above the wick
			var room := sz.y * 0.22
			size = Vector2(sz.x, sz.y + room)
			_art = P.art_rect(self, "candle", Rect2(Vector2(0, room), sz))
			wick = Vector2(0.5, (room + sz.y * 0.035) / size.y)
			P.note_source("candle", P.source_of("candle"))
		else:
			P.layer(self, Callable(self, "_paint_stand"))
			P.note_source("candle", "code")
		_light = P.glow_rect(self, wick * sz, sz.y * 0.34, Kit.with_alpha(color, 0.30))
		_flame = P.layer(self, Callable(self, "_paint_flame"))
		set_process(true)

	func _process(delta: float) -> void:
		if animated: _t += delta
		_flame.queue_redraw()
		var f := _flick()
		_light.modulate = Kit.with_alpha(flame_color, (0.22 + 0.16 * f) * lit_amount)

	func _flick() -> float:
		var t := _t + _phase
		return clampf(0.62 + 0.20 * sin(t * 7.3) + 0.12 * sin(t * 12.9 + 1.7) + 0.08 * sin(t * 3.1 + 0.4), 0.0, 1.0)

	## Iron stand and wax in code: a dish on a foot, a stem, a drip-edged candle.
	func _paint_stand(c: Control) -> void:
		var w := size.x
		var h := size.y
		var iron := Color(0.10, 0.10, 0.115)
		var iron_hi := Color(0.30, 0.28, 0.26)
		var wick_y := h * wick.y
		var wx := w * 0.5
		c.draw_colored_polygon(PackedVector2Array([Vector2(wx - w * 0.07, h * 0.52), Vector2(wx + w * 0.07, h * 0.52), Vector2(wx + w * 0.16, h * 0.93), Vector2(wx - w * 0.16, h * 0.93)]), iron)
		c.draw_rect(Rect2(wx - w * 0.36, h * 0.93, w * 0.72, h * 0.04), iron)
		c.draw_rect(Rect2(wx - w * 0.36, h * 0.93, w * 0.72, 2.0), iron_hi)
		c.draw_rect(Rect2(wx - w * 0.30, h * 0.49, w * 0.60, h * 0.035), iron)
		c.draw_rect(Rect2(wx - w * 0.30, h * 0.49, w * 0.60, 2.0), iron_hi)
		var wax_top := wick_y + h * 0.06
		var wax := Rect2(wx - w * 0.17, wax_top, w * 0.34, h * 0.49 - wax_top)
		Kit.quad(c, wax, Color(0.86, 0.80, 0.66), Color(0.62, 0.55, 0.42))
		c.draw_rect(Rect2(wax.position.x, wax.position.y, wax.size.x * 0.22, wax.size.y), Color(1, 1, 1, 0.10))
		for k in 3:
			var dx := wax.position.x + wax.size.x * (0.2 + 0.3 * float(k))
			c.draw_rect(Rect2(dx, wax.position.y, w * 0.045, h * (0.07 + 0.04 * float((k * 2) % 3))), Color(0.9, 0.84, 0.70, 0.9))
		c.draw_line(Vector2(wx, wick_y + h * 0.015), Vector2(wx, wick_y + h * 0.06), Color(0.08, 0.06, 0.05), 2.0)

	func _paint_flame(c: Control) -> void:
		var f := _flick() * lit_amount
		var base := Vector2(size.x * wick.x, size.y * wick.y + size.y * 0.015)
		var sway := sin((_t + _phase) * 2.3) * 2.0 * f
		var ht := size.y * (0.21 + 0.06 * f)
		var wd := size.x * (0.13 + 0.014 * f)
		var tip := base + Vector2(sway, -ht)
		var body := PackedVector2Array([base + Vector2(-wd, 0), base + Vector2(-wd * 0.9, -ht * 0.35), tip + Vector2(-wd * 0.2, ht * 0.2), tip, tip + Vector2(wd * 0.2, ht * 0.2), base + Vector2(wd * 0.9, -ht * 0.35), base + Vector2(wd, 0)])
		c.draw_colored_polygon(body, Kit.with_alpha(flame_color.darkened(0.15), 0.92))
		var s2 := PackedVector2Array([base + Vector2(-wd * 0.55, 0), base + Vector2(-wd * 0.5, -ht * 0.3), tip.lerp(base, 0.45) + Vector2(sway * 0.3, 0), base + Vector2(wd * 0.5, -ht * 0.3), base + Vector2(wd * 0.55, 0)])
		c.draw_colored_polygon(s2, Kit.with_alpha(flame_color.lightened(0.35), 0.95))
		c.draw_circle(base + Vector2(0, -ht * 0.12), wd * 0.32, Color(1.0, 0.93, 0.78, 0.95))

static func candle(parent: Control, pos: Vector2, height: float, color := FLAME_WARM) -> Candle:
	var c := Candle.new()
	c.build(Vector2(height * 0.5, height), color, fmod(absf(pos.x) * 0.0137, 6.0))  ## own phase per position, deterministic
	c.position = pos
	parent.add_child(c)
	return c
