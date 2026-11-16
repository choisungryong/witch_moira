extends RefCounted
## Read-only presentation waypoint for existing east corridors (half-width3.6).
static func waypoint(run: RefCounted) -> Dictionary:
	var goal: Dictionary=run.objective()
	var destination: Vector2=goal.destination
	if goal.entered or int(goal.zone)<=0:return {"position":destination,"stage":"봉인"}
	var hero: Vector2=run.hero.position
	var previous: Vector2=run.ZONES[int(goal.zone)-1]
	# Align within the previous room before pointing through its narrow exit.
	if hero.x<=previous.x+19.0 and absf(hero.y)>2.5:
		return {"position":previous+Vector2(18,0),"stage":"회랑 입구"}
	if hero.x<destination.x-18.0:
		return {"position":destination-Vector2(18,0),"stage":"회랑 출구"}
	return {"position":destination,"stage":"다음 봉인"}
