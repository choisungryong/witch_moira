extends RefCounted
## Single source for item grade colours. HUD, ground labels and drop pillars all read this table.
## Use via: const Palette = preload("res://chapter1/view/hud/palette.gd")
## Values are the HUD's (ART-PLAN 6.3, director decision: grade colour values unchanged).
const QUALITY_COMMON := Color("c4c0ad")
const QUALITY_MAGIC := Color("91bbd4")
const QUALITY_RARE := Color("e0c47e")
## Legendary stays orange by director decision; change this one constant to recolour it everywhere.
const QUALITY_LEGENDARY := Color("e8703a")
const QUALITY_UNIQUE := Color("efac59")
const QUALITY_COLORS := {"common":QUALITY_COMMON,"magic":QUALITY_MAGIC,"rare":QUALITY_RARE,"legendary":QUALITY_LEGENDARY,"unique":QUALITY_UNIQUE}

static func quality_color(quality: Variant, fallback: Color = QUALITY_COMMON) -> Color:
	return QUALITY_COLORS.get(String(quality),fallback)
