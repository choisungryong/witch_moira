extends RefCounted
## When a bot uses the descent (D15 A6.5). MEASUREMENT ONLY: chapter_pilot.gd is not touched (the golden replay plays it as it is),
## and no game code calls this. A tool calls use() after pilot.decide(); it reads descent_view() / run_progress() only and then
## asks the core with request_descent() + release_descent() in the same frame (the core stands still in between, so the outcome
## does not depend on how long a screen would show the cut-in).
##   off    never
##   now    as soon as the gauge is ready
##   hold   save it for the trial's hold and the boss; use it earlier only when life is under 30 percent
##   panic  life under 40 percent, or the living enemies at 85 percent of the cap of the rule in force
## How close a person comes to either is unknown (unrated, only a playthrough tells).
const POLICIES := ["off", "now", "hold", "panic"]

static func valid(policy: String) -> bool:
	return policy in POLICIES

## The alive cap of the spawn rule in force (the beat's, the trial's, else the document's).
static func cap_now(run: RefCounted) -> int:
	var doc_cap := int(run.tuning.alive_cap)
	var progress: Dictionary = run.run_progress()
	if not run.tuning.has("rhythm") or not bool(run.tuning.rhythm.enabled): return doc_cap
	if String(progress.phase) == "trial": return mini(doc_cap, int(run.tuning.rhythm.trial.alive_cap))
	for beat in run.tuning.rhythm.beats:
		if String(beat.id) == String(progress.beat_id): return mini(doc_cap, int(beat.alive_cap))
	return doc_cap

static func wants(run: RefCounted, policy: String) -> bool:
	if policy == "off" or not valid(policy) or run.mode != "playing": return false
	var view: Dictionary = run.descent_view()
	if not bool(view.get("enabled", false)) or not bool(view.get("ready", false)): return false
	var life := float(run.hero.hp_raw) / maxf(1.0, float(run.hero.max_hp_raw))
	match policy:
		"now": return true
		"hold":
			if life < 0.30: return true
			return String(run.run_progress().phase) in ["trial", "boss"]
		"panic":
			if life < 0.40: return true
			return run.alive_count() * 100 >= cap_now(run) * 85
	return false

## Calls and releases the descent if the policy wants it this frame. Returns the events the two calls made (descent_called is
## emitted outside step(), and the next step() clears the event list, so a caller that wants it must take it here); [] when not used.
static func use(run: RefCounted, policy: String) -> Array:
	if not wants(run, policy): return []
	var before: int = int(run._event_sequence)
	if not run.request_descent(): return []
	run.release_descent()
	return run.events.filter(func(e): return int(e.seq) > before)
