extends RefCounted
## Walker (skeleton outlaw) bake specification: the model, the baked clips and the code-side pose overrides.
## Values are copied from chapter_actors.gd (quality34b / quality42 layers). If those constants change, change them here too.

const MODEL_PATH := "res://chapter1/art/skeleton_outlaw/v02/skeleton_outlaw_merged.glb"
const FPS := 30.0
const HEAD_BONE := "ORG-head"
const HEAD_SCALE := .72                       # _update_pose: set_bone_pose_scale(_head34, .72)
const TRACKED_BONES: Array[String] = ["ORG-spine", "ORG-head"]   # for the hero-overlap test
const HIT_BONES: Array[String] = ["ORG-spine", "ORG-chest", "ORG-neck", "ORG-head", "ORG-shoulder_L", "ORG-upper_arm_L", "ORG-forearm_L", "ORG-shoulder_R", "ORG-upper_arm_R", "ORG-forearm_R"]
## Head and neck vertices do not take part in the hit blend (B-b decision: a straight vertex blend deformed the head).
const HIT_EXCLUDE_BONES: Array[String] = ["ORG-neck", "ORG-head"]
const TINT :=Color(.58, .54, .46)            # _materials34 albedo tint
const RIM := .18
const RIM_TINT := .12
const HIT_DURATION := 46.0 / 60.0
const HIT_INTERVALS := 12                     # 13 samples, as _hit34_frames
const STRIKE := 25.0 / 60.0
const SWING := 68.0 / 60.0

## Clips in table order. "intervals" overrides round(duration * fps).
static func clips() -> Array:
	return [
		{"name": "idle", "anim": "idle", "duration": 128.0 / 60.0, "loop": true},
		{"name": "walk", "anim": "walk", "duration": 56.0 / 60.0, "loop": true},
		{"name": "attack_slam", "anim": "attack_slam", "duration": SWING, "loop": false},
		{"name": "death", "anim": "death", "duration": 1.60, "loop": false},
		{"name": "hit", "anim": "hit", "duration": HIT_DURATION, "loop": false, "intervals": HIT_INTERVALS},
	]

## Applied to the skeleton after every seek (the game does the same after its own seek).
static func apply_overrides(skeleton: Skeleton3D) -> void:
	var head := skeleton.find_bone(HEAD_BONE)
	if head >= 0:
		skeleton.set_bone_pose_scale(head, Vector3.ONE * HEAD_SCALE)
