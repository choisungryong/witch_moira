extends RefCounted
## Dev trial switch "pace" (D19 C1, docs/specs/D19-growth-pace-and-combat-thrill-20261120.ko.md 6.2): the FIRST values [hypothesis] of the
## growth-pace keys of the rhythm block, put into the in-memory copy of the tuning document that a trial hands to the core. No data file
## carries these keys (they stay off in the shipped game); the numbers live here only so that a trial run (`--chapter1-trial=pace`, which
## also turns the rhythm on) and the tools that build the same run (chapter1/tests/support/trial_docs.gd) read them from ONE place.
## Not product code: the balance owner moves these into a tuning copy and then into the data file; this file goes away with that.

## Level table (16 levels), seal kills per zone, the guardian's level, and the sweep bonus. `xp_bps` per beat stays 1x (absent).
const FIRST_VALUES := {
	"xp_thresholds": [0, 27, 50, 72, 114, 263, 442, 600, 820, 1070, 1330, 1580, 1840, 2160, 2560, 9000],
	"seal_kills": [365, 975, 540],
	"guardian_grace": true,
	"kill_burst": {"window_ticks": 30, "min_kills": 10, "xp_bonus_bps": 5000, "descent_bonus_bps": 10000},
}

## Put the first values into `doc` (a parsed combat_tuning.json). Nothing happens when the document has no rhythm block.
static func apply(doc: Dictionary) -> void:
	if not doc.get("rhythm") is Dictionary:
		return
	for key in FIRST_VALUES:
		var value: Variant = FIRST_VALUES[key]
		doc["rhythm"][key] = value.duplicate(true) if (value is Array or value is Dictionary) else value
