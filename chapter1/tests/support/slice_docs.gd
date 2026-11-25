extends RefCounted
## Check tool, not product code. The one door of the checks, goldens, captures and measurements to the "one run" trial (S1): it calls
## chapter1/app/trial_slice.gd and nothing else, so the run a tool plays is the run `--chapter1-trial=slice` plays. Do not write the trial's
## documents a second time anywhere else: call this.
const TrialSlice := preload("res://chapter1/app/trial_slice.gd")

## Hand the trial to a run before start(). "" when it worked, else one sentence. `slice` = a validated trial_slice document ({} = the shipped one).
static func enable_slice_problem(run: RefCounted, slice: Dictionary = {}) -> String:
	return TrialSlice.apply(run, slice)

## The pity armed for the account of this run (what the app does from a save's dry-run count): the next final boss's first guaranteed line is a
## legendary. Needs the run's loot tables from enable_slice_problem. Call before start().
static func arm_pity(run: RefCounted) -> void:
	if run.loot != null and run.loot.pity_on(): run.drop_dry_runs = run.loot.pity_runs()
