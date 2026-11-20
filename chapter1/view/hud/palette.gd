extends RefCounted
## Single source for HUD colours: item grades, UI inks, frame brass, surfaces, threat, life and element colours.
## Use via: const Palette = preload("res://chapter1/view/hud/palette.gd")
## One colour, one meaning (A2 section 2.3). A hex literal of any token below must not appear outside this file.

## ---- Item grades (ART-PLAN 6.3, director decision: grade colour values unchanged) ----
const QUALITY_COMMON := Color("c4c0ad")
const QUALITY_MAGIC := Color("91bbd4")
const QUALITY_RARE := Color("e0c47e")
## Legendary stays orange by director decision; change this one constant to recolour it everywhere.
const QUALITY_LEGENDARY := Color("e8703a")
const QUALITY_UNIQUE := Color("efac59")
## Set gear (not in the game yet; A3-U10 proposal, provisional until decided).
const QUALITY_SET := Color("7cc47a")
## The grace screen's top grade ("jackpot"): a grace grade, not a gear grade. Always shown with the crown-spike frame (A10 1.8).
const GRACE_JACKPOT := Color("ffc24d")
const QUALITY_COLORS :={"common":QUALITY_COMMON,"magic":QUALITY_MAGIC,"rare":QUALITY_RARE,"legendary":QUALITY_LEGENDARY,"unique":QUALITY_UNIQUE}

## ---- Text ----
const INK := Color("f2ebd8")            ## default text
const INK_DIM := Color("b9b2a1")        ## secondary text
const INK_FAINT := Color("97988e")      ## hints, sources
const TEXT_DISABLED := Color("777a78")  ## a disabled button's text
## Reading surface (a side note) and its dark ink.
const PARCHMENT := Color(0.75, 0.64, 0.46)
const PARCHMENT_INK := Color(0.13, 0.095, 0.06)
const PARCHMENT_INK_DIM := Color(0.27, 0.19, 0.11)
## A value that rises / falls (always with an arrow or a sign, never colour alone).
const GAIN := Color("8fd694")
const LOSS := Color("e07a6a")
## Candle flame base.
const FLAME_WARM := Color("ffb25a")
## ---- Frames ----
const BRASS := Color("aa8d58")          ## frame
const BRASS_DIM := Color("665343")      ## weak frame, inactive
const BRASS_HI := Color("ffd27a")       ## selection / focus ONLY (never a plain frame, never a confirm window edge)
const LINEN := Color("cbbf9f")          ## thread: connection, belonging, progress (reserved for the material pass)
## ---- Surfaces ----
const SURFACE := Color("17191b")        ## panel
const SURFACE_RAISED := Color("202628") ## button / card
## Dim behind a window that sits on another window (confirm windows, refused-save notice).
const SCRIM := Color(.01,.015,.02,.72)
const PLATE := Color(.035,.045,.05,.92) ## combat bar plate
const SLOT := Color(.075,.095,.105,1)   ## combat bar slot and tree tile
## Dim behind a full-screen scene (grace, character select, result, gear): black, plus a vignette whose edge alpha is SCRIM_SCENE_VIGNETTE (A10 1.3).
const SCRIM_SCENE := Color(0,0,0,.65)
const SCRIM_SCENE_VIGNETTE := 0.80
## ---- Threat and life ----
const THREAT := Color("ff2f4f")         ## enemy danger
const THREAT_DEEP := Color("7a1424")    ## boss health fill
const LIFE := Color("d04a5c")           ## life orb
const LIFE_DEEP := Color("571c2b")      ## life orb bottom
const LIFE_LOW := Color("ff5a48")       ## life orb pulse below 30 percent
## ---- Elements: effect colours and text colours (names, icons, the end of a thread only) ----
const FIRE := Color("ff943d")
const FROST := Color("9ce7ef")
const ARC := Color("b9caff")
const FIRE_TEXT := Color("e8a05a")
const FROST_TEXT := Color("7cc9d9")
const ARC_TEXT := Color("abb8ec")
## ---- Growth and warning ----
## Permanent growth: bar fills, the diamond glyph and text only. Never a border: a bright gold edge means selection.
const GROWTH := Color("e6c36a")
const WARN := Color("ffb08a")           ## error text only

static func quality_color(quality: Variant, fallback: Color = QUALITY_COMMON) -> Color:
	return QUALITY_COLORS.get(String(quality),fallback)

## Element colours by short id.
static func element_color(element: String, fallback: Color = BRASS) -> Color:
	return {"ember":FIRE,"frost":FROST,"arc":ARC}.get(element,fallback)

static func element_text_color(element: String, fallback: Color = BRASS) -> Color:
	return {"ember":FIRE_TEXT,"frost":FROST_TEXT,"arc":ARC_TEXT}.get(element,fallback)

## A6-RS RS1: a spell id (basic or ring) to its element short id. The run's own spell document wins (run.spells.spells[id].element);
## without it the three basic spells and the ring ids the core names (RunSpells.RING_IDS) answer. "" when the id is not a spell.
const _BASIC_SPELL_ELEMENTS := {"chapter1.skill.ember":"ember","chapter1.skill.frost":"frost","chapter1.skill.arc":"arc"}
const _RunSpells = preload("res://chapter1/core/run_spells.gd")

static func spell_element(skill_id: String, spells_doc: Dictionary = {}) -> String:
	var spells: Variant = spells_doc.get("spells",null)
	if spells is Dictionary and spells.has(skill_id): return String(spells[skill_id].get("element",""))
	return String(_BASIC_SPELL_ELEMENTS.get(skill_id,_RunSpells.RING_IDS.get(skill_id,"")))

static func is_ring_spell(skill_id: String) -> bool:
	return _RunSpells.RING_IDS.has(skill_id)

## The element colour of a spell id; `fallback` when the id is not a spell (an enemy skill, a seal, an empty id).
static func spell_color(skill_id: String, spells_doc: Dictionary = {}, fallback: Color = BRASS) -> Color:
	return element_color(spell_element(skill_id,spells_doc),fallback)
