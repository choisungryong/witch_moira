extends Node
## QA-only timestamp node for perf_probe.gd. Records the time its _process ran.
var stamp := 0

func _process(_delta: float) -> void:
	stamp = Time.get_ticks_usec()
