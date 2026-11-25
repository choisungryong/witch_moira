extends RefCounted
## The adapter of the first screen (T13 R1, T8 3): what the host knows about the menu -> the contract chapter1/view/hud/screens/title.gd reads
## (schema chapter1/tests/contracts/title.contract.json). Called when the menu screen is built or its words are rebuilt (never every frame).
## It writes nothing: it reads app_state (copied, never changed), the .po texts and the character document (ChapterProfile.progression_doc).
## `run` is not read (the first screen has no run); the signature only matches the other adapters.
##
## app_state: {"focus_index": int 0..2, "save": "on"|"off"|"verify", "note": String, "items": int (the stash size), "motion_on": bool,
##             "character_views": {character id: profile.character_view(id)}}. A missing key takes its empty value:
##             focus 0, save "off", note "", stash_count null, motion_on true, level null.
const CONTRACT_VERSION := 1
const Loc = preload("res://chapter1/view/loc.gd")
const ChapterProfile = preload("res://chapter1/core/chapter_profile.gd")
## One entry per door, left to right: [portrait id, element key, start skill].
const WITCHES := [["ember", "ember", "chapter1.skill.ember"], ["frost", "frost", "chapter1.skill.frost"], ["storm", "arc", "chapter1.skill.arc"]]
const SAVE_MODES := ["on", "off", "verify"]
const NOTE_MAX := 80

static func build(_run: RefCounted, app_state: Dictionary = {}) -> Dictionary:
	var state: Dictionary = app_state.duplicate(true)
	var save := String(state.get("save", "off"))
	if not save in SAVE_MODES: save = "off"
	var views: Dictionary = state.get("character_views", {}) if state.get("character_views", {}) is Dictionary else {}
	var witches: Array = []
	for entry in WITCHES:
		witches.append(_witch(String(entry[0]), String(entry[1]), String(entry[2]), views))
	var note := String(state.get("note", ""))
	var result := {"screen": "title", "contract_version": CONTRACT_VERSION, "focus_index": clampi(int(state.get("focus_index", 0)), 0, 2), "save": save,
		"note": note.substr(0, NOTE_MAX), "stash_count": null, "motion_on": bool(state.get("motion_on", true)), "witches": witches}
	# A stash count is a fact only of a saved profile; with the save off the host's number means nothing and the screen hides the handle.
	if save == "on" and state.has("items"): result.stash_count = clampi(int(state.items), 0, 9999)
	return result

static func _witch(id_: String, element: String, start_ref: String, views: Dictionary) -> Dictionary:
	var character_ref := _character_for_skill(start_ref)
	return {"id": id_, "element": element, "start_ref": start_ref, "character_ref": character_ref,
		"title": "%s · %s" % [Loc.t("character.%s.name" % element), Loc.t("character.%s.class" % element)],
		"skill_name": Loc.t("skill.%s.name" % start_ref), "skill_summary": Loc.t("title.witch.%s.summary" % element),
		"line": Loc.t("title.witch.%s.line" % element), "traits": [], "level": _level(views.get(character_ref, {}))}

## The character whose signature skill is the start skill (the same rule the host's tree button uses). "" when the document has none.
static func _character_for_skill(skill_id: String) -> String:
	for entry in ChapterProfile.progression_doc().get("characters", []):
		if String(entry.get("signature_skill_id", "")) == skill_id: return String(entry.get("id", ""))
	return ""

## profile.character_view(id) -> {value, bar, capped, points, has_tree}; null when the view is empty (no profile, so no level band).
static func _level(view: Variant) -> Variant:
	if not view is Dictionary or (view as Dictionary).is_empty(): return null
	var capped := int(view.get("xp_to_next", 1)) <= 0
	var span := maxf(1.0, float(int(view.get("xp_for_next", 0)) - int(view.get("xp_level_start", 0))))
	var bar := 1.0 if capped else clampf(float(int(view.get("xp", 0)) - int(view.get("xp_level_start", 0))) / span, 0.0, 1.0)
	return {"value": clampi(int(view.get("level", 1)), 1, 99), "bar": bar, "capped": capped, "points": clampi(int(view.get("points_free", 0)), 0, 999), "has_tree": bool(view.get("has_tree", false))}
