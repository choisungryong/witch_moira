extends RefCounted
## The one place that turns the element kit (D-element-trees) on for a process: the app's `--chapter1-trial=element_kit`
## (chapter_one.gd `_apply_trial`) and the tools (tests/support/kit_docs.gd) both call this, so "the document with enabled = true" is
## written once. Nothing here changes a data file: the shipped element_kit.json stays "enabled": false; an enabled copy is handed to the
## core's own public functions (set_element_kit, set_kit_open) before the run starts.
const Kit := preload("res://chapter1/core/element_kit.gd")

## `--chapter1-kit-tree=` values: "all" (every card a tree node opens, the default), "none" (a new account), or card ids "A19,A21".
const TREE_DEFAULT := "all"

## `path`: "" = the shipped element_kit.json; else a res:// copy of it with other values (a tool's own document, _local/).
static func document(elements: Array = ["arc"], path: String = "") -> Dictionary:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Kit.DEFAULT_PATH if path.is_empty() else "res://" + path))
	doc["enabled"] = true
	doc["enabled_elements"] = elements
	return doc

## "all", "none" or a list of card ids from the argument text. "" = the default.
static func tree_mode(text: String) -> Variant:
	var wanted := text.strip_edges()
	if wanted.is_empty() or wanted == "all": return "all"
	if wanted == "none": return "none"
	var ids: Array = []
	for part in wanted.split(",", false): ids.append(part.strip_edges())
	return ids

## The kit on, the permanent tree open as `tree` says. "" when it worked, else one sentence.
static func problem(run: RefCounted, tree: Variant = "all", elements: Array = ["arc"], path: String = "") -> String:
	if not run.set_element_kit(document(elements, path)): return "element kit refused: " + str(run.errors)
	if not run.set_kit_open(tree): return "kit tree mode refused: " + str(run.errors)
	return ""
