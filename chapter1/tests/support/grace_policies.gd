extends RefCounted
## Check tool, not product code. The growth (grace) pick policies of sim_builds.gd, moved here so that measure_rhythm.gd can borrow them (D19 V0).
## The numbers and the order of the rules are the ones sim_builds.gd had; sim_builds.gd now calls these. The policy RNG is the caller's own
## RandomNumberGenerator (never the core's streams). `snap` is run.growth.snapshot().
## "synergy_now" is appended LAST on purpose: the policy RNG seed uses the index in this list, so inserting earlier would change the old runs.
const ALL_POLICIES := ["pilot", "random", "worst", "narrow", "greedy_area", "greedy_single", "greedy_chain", "spread", "synergy_now"]
const ROLE_OF := {"chapter1.skill.ember": "area", "chapter1.skill.frost": "single", "chapter1.skill.arc": "chain"}
const KIND_ORDER := {"evolve": 4, "rank": 3, "unlock": 2, "passive": 1}

static func pilot_score(card: Dictionary, primary: String) -> int:
	# Same numbers as chapter_pilot.gd decide() (copied; the pilot file is not touched).
	var score := 10
	if card.skill_id == primary: score = 100 if card.kind == "evolve" else (90 if card.kind == "rank" else 80)
	elif card.kind == "unlock": score = 65
	elif card.kind == "evolve": score = 60
	elif card.kind == "rank": score = 50
	return score

static func argmin_pilot(cards: Array, primary: String) -> int:
	var best := 0
	var bs := 1 << 30
	for i in cards.size():
		var s := pilot_score(cards[i], primary)
		if s < bs:
			bs = s
			best = i
	return best

static func argmax_pilot(cards: Array, primary: String) -> int:
	var best := 0
	var bs := -1
	for i in cards.size():
		var s := pilot_score(cards[i], primary)
		if s > bs:
			bs = s
			best = i
	return best

## Policy "synergy_now": plays the synergies the CURRENT data really has. There are exactly two (read from the data, not invented):
##  (1) Mark resonance (combat_tuning.json marks {mark_bps 9000, mark_ticks 360}; chapter_core.gd hit logic): a hit of the primary on an enemy
##      that a secondary skill marked in the last 6 s deals +90% per live mark. A secondary only marks once it has been unlocked (a card) and
##      it marks as many enemies as it hits, so a ranked secondary keeps more marks alive. Both secondaries unlocked = up to +180%.
##  (2) Crystal card + evolution (growth_quality37.json passive_id / evolution): evolve:<skill> needs rank 4 AND that skill's passive card.
## There is no skill tree in the baseline state (no permanent tree) and no cross-skill rule beyond these two.
## Order: evolve the primary > primary rank 2 (the base) > unlock a secondary (opens a mark) > the primary's crystal card > primary rank 3-4
##        > the lowest-ranked secondary's rank card (keeps marks alive) > pilot score.
## ---- Place for the new skill composition (run_spells.json does NOT exist yet; not created here) ----
## When docs/specs/D12 B0's run_spells.json arrives, build this policy from its fields instead of the table above: read each spell's role
## (single / around-hero circle / other), its pair field (which spell/element it combos with) and its axis (damage / range) from the file,
## and score a card by "fills a missing role" + "adds to the axis the pair needs" + "completes a pair". Keep the old two-rule version as
## "synergy_now" so the old numbers stay reproducible; name the new one e.g. "synergy_spells".
static func pick_synergy_now(cards: Array, snap: Dictionary, primary: String) -> int:
	var best := 0
	var bs := -1
	for i in cards.size():
		var c: Dictionary = cards[i]
		var sk: String = String(c.skill_id)
		var rk: int = int(snap.ranks.get(sk, 0))
		var prim_rk: int = int(snap.ranks.get(primary, 1))
		var score := 10
		if sk == primary:
			if c.kind == "evolve": score = 100
			elif c.kind == "rank" and int(c.rank) == 2: score = 90
			elif c.kind == "passive": score = 70
			elif c.kind == "rank": score = 60
			else: score = 50
		else:
			if c.kind == "unlock": score = 80 if prim_rk >= 2 else 55
			elif c.kind == "rank": score = 55 - rk * 3
			else: score = 20
		if score > bs:
			bs = score
			best = i
	return best

static func pick(policy: String, cards: Array, snap: Dictionary, rng: RandomNumberGenerator) -> int:
	var primary: String = String(snap.primary)
	match policy:
		"random":
			return rng.randi_range(0, cards.size() - 1)
		"worst":
			return argmin_pilot(cards, primary)
		"narrow":
			# Only the primary's own cards (rank / passive / evolve); when none is offered take the pilot's lowest score.
			var best := -1
			var bs := -1
			for i in cards.size():
				if cards[i].skill_id == primary:
					var s := pilot_score(cards[i], primary)
					if s > bs:
						bs = s
						best = i
			return best if best >= 0 else argmin_pilot(cards, primary)
		"spread":
			# The card of the skill with the fewest ranks so far (unlock = 0), ties by the pilot score.
			var best2 := 0
			var key := Vector2i(1 << 30, -1)
			for i in cards.size():
				var rk: int = int(snap.ranks.get(cards[i].skill_id, 0))
				var k := Vector2i(rk, -pilot_score(cards[i], primary))
				if k.x < key.x or (k.x == key.x and k.y < key.y):
					key = k
					best2 = i
			return best2
		"synergy_now":
			return pick_synergy_now(cards, snap, primary)
		"greedy_area", "greedy_single", "greedy_chain":
			var role := policy.trim_prefix("greedy_")
			var best3 := -1
			var bo := -1
			for i in cards.size():
				if String(ROLE_OF.get(cards[i].skill_id, "")) == role:
					var o: int = int(KIND_ORDER.get(cards[i].kind, 0))
					if o > bo:
						bo = o
						best3 = i
			return best3 if best3 >= 0 else argmax_pilot(cards, primary)
	return argmax_pilot(cards, primary)
