extends SceneTree
## The user plays the game with a trial glb in the hero's place (no pilot, no capture). Product files are untouched.
##
##   $env:MOIRA_GODOT_TIMEOUT_S='0'
##   python tools/dev/godot.py --resolution 1920x1080 --path . --script res://chapter1/tests/play_with_model.gd -- \
##       --model-glb=<absolute.glb> [--model-texture=<absolute.png>] [--hero-boost=0..1] [--hero-look=<json>] \
##       --chapter1-profile-off [--chapter1-start --chapter1-primary=chapter1.skill.frost] [--chapter1-trial=spells,rhythm,descent]
##
## --hero-boost (default 0): how much of the game's hero material boost stays (see model_swap.gd). The game's arguments pass through.
## --hero-look=<json>: the hero look override of model_swap.gd (rim, emission mask, the two hero lights ...), applied every frame after the boost.
const ModelSwap := preload("res://chapter1/tests/model_swap.gd")
var _held: Array = []
var _view: Node
var _boost := 0.0
var _look: Dictionary = {}
## --cam-size=<m>: the orthographic camera's size (the game ships 19.5). Smaller = closer: the hero covers more pixels, less of the field shows.
## Forced every frame, so the game's own camera size effects (if any) are overridden while it is set.
var _cam_size := 0.0

func _initialize() -> void:
	var glb := ""
	var texture := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--model-glb="): glb = arg.trim_prefix("--model-glb=")
		elif arg.begins_with("--model-texture="): texture = arg.trim_prefix("--model-texture=")
		elif arg.begins_with("--hero-boost="): _boost = float(arg.trim_prefix("--hero-boost="))
		elif arg.begins_with("--cam-size="): _cam_size = float(arg.trim_prefix("--cam-size="))
		elif arg.begins_with("--hero-look="):
			_look = ModelSwap.load_look(arg.trim_prefix("--hero-look="))
			print("PLAY_LOOK ", JSON.stringify({"file": arg.trim_prefix("--hero-look="), "cells": _look.keys()}))
	if glb.is_empty():
		push_error("play_with_model: --model-glb is required"); quit(2); return
	_held = ModelSwap.swap(glb, texture)
	if _held.is_empty():
		quit(5); return
	var scene: PackedScene = load("res://chapter1/ChapterOne.tscn")
	_view = scene.instantiate()
	root.add_child(_view)
	RenderingServer.frame_pre_draw.connect(_apply)

func _apply() -> void:
	if _view == null or not is_instance_valid(_view): return
	ModelSwap.apply_boost(_view.get("actors"), _boost)
	ModelSwap.apply_look(_view.get("actors"), _look)
	if _cam_size > 0.0:
		var world = _view.get("world")
		if world != null and world.get("camera") != null: world.camera.size = _cam_size
