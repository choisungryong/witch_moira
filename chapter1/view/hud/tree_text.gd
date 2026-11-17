extends RefCounted
## Turns the key lines of SkillTree.describe_keys() into text. Presentation side; the core only gives keys and numbers.
const Loc = preload("res://chapter1/view/loc.gd")
const SkillTree = preload("res://chapter1/core/skill_tree.gd")

## One line per entry of `entries` ([{key, args}]).
static func lines(entries: Array) -> Array[String]:
	var out: Array[String] = []
	for entry in entries:
		out.append(Loc.t(String(entry.key), entry.args))
	return out

## Text lines of the cumulative effect of one node at `rank`.
static func describe(tree: Dictionary, node_id: String, rank: int) -> Array[String]:
	return lines(SkillTree.describe_keys(tree, node_id, rank))
