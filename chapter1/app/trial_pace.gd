extends RefCounted
## Dev trial switch "pace" (D19 C1, docs/specs/D19-growth-pace-and-combat-thrill-20261120.ko.md 6.2) - since S1-A (docs/specs/T14-slice-s1-20261125.ko.md,
## director's ruling 3) a path to the DATA FILE's rhythm values, no longer a layer over them. The growth-pace keys of the rhythm block (`xp_thresholds`,
## `seal_kills`, `guardian_grace`, `kill_burst`) are what chapter1/data/combat_tuning.json says; the balance owner measured those (RC-A, BF-B, RC-B, the kit's 140 runs),
## nobody ever measured the D19 first values below. `apply` therefore leaves the document as it is. The public name and arguments stay because the app
## (`--chapter1-trial=pace` / `boss_finale`) and chapter1/tests/support/trial_docs.gd call it; the S1 trial (chapter1/app/trial_slice.gd) does not call it.
## Not product code: this file goes away when its callers drop the call.

## Unused old D19 first values [hypothesis]. No game path reads them any more (`apply` below does not write them); chapter1/tests/test_growth_pace.gd still
## takes them as a fixture table for its validator and level checks, which is the only reason they are kept.
const FIRST_VALUES := {
	"xp_thresholds": [0, 27, 50, 72, 114, 263, 442, 600, 820, 1070, 1330, 1580, 1840, 2160, 2560, 9000],
	"seal_kills": [365, 975, 540],
	"guardian_grace": true,
	"kill_burst": {"window_ticks": 30, "min_kills": 10, "xp_bonus_bps": 5000, "descent_bonus_bps": 10000},
}

## The growth-pace values of a tuning document: the data file's own. Nothing is overwritten (the document `doc` is a parsed combat_tuning.json).
static func apply(_doc: Dictionary) -> void:
	return
