extends RefCounted
## Check tool, not product code. How an automatic player picks a card of the element kit (D-element-trees 8.2 (3)): three policies for the
## measurement. They read only the hand (card dictionaries of the growth offer) and a random stream the tool owns; the core's own stream is never touched.
##   link    the meshing order: the burst skill first, then the lay skill, then the cards that answer the big body, the burst skill's ranks, the
##           signature skill's ranks / rune / evolution, then the rest. The order is a table per element (below); a card it does not name comes after, by kind.
##   main    the signature skill only: its ranks, rune and evolution, survival cards and fillers; never an unlock or a variant (unless nothing else is in the hand).
##   random  one card of the hand, evenly.
const ALL := ["link", "main", "random", "link_rank", "link_safe"]
## First order tried (burst, lay, big-body variants, burst ranks, then the signature ranks last) left the signature skill at rank 1 and lost 3 of 4 runs at 317-401 s
## (_local/et-a/linkon_*); the table below keeps the doors first and takes the signature ranks up to 3 right after them.
const LINK_ORDER := {"arc": ["A02", "A01", "A03", "A04", "A12", "A23", "A05", "A10", "A11", "A22", "A18", "A14", "A24", "A20", "A09", "A08", "A06", "A07", "A17", "A16", "A19", "A15", "A13", "A21", "A26", "A25", "A27", "A28"]}
## ET-B: `link_rank` = the same meshing order with the signature skill's ranks (A03, A04, A05) taken before the doors and the rest (rune and evolution after them, as in `link`). It asks whether taking the signature rank first when it shows is the choice that survives.
const LINK_RANK_ORDER := {"arc": ["A03", "A04", "A02", "A01", "A05", "A12", "A23", "A10", "A11", "A22", "A18", "A14", "A24", "A20", "A09", "A08", "A06", "A07", "A17", "A16", "A19", "A15", "A13", "A21", "A26", "A25", "A27", "A28"]}
## ET-D: `link_safe` = `link`, but a hand that carries a survival card is taken from when the hero's life is under 50 % (the human reply the plain `link` never gives: it ranks the survival cards last
## and so never took one in the two lost runs of the 40-seed read). The life comes in as a fifth argument; with it left out every other policy reads exactly as before.
const SAFE_HP_BPS := 5000
const KIND_ORDER := ["evolve", "rune", "rank", "unlock", "variant", "survival", "filler"]

static func valid(name: String) -> bool:
	return name in ALL

static func pick(policy: String, cards: Array, element: String, rng: RandomNumberGenerator, hp_bps: int = 10000) -> int:
	if cards.is_empty(): return 0
	if policy == "link_safe" and hp_bps < SAFE_HP_BPS:
		for i in cards.size():
			if String(cards[i].kind) == "survival": return i
	match policy:
		"random":
			return rng.randi_range(0, cards.size() - 1)
		"main":
			var best := -1
			var best_score := -1
			for i in cards.size():
				var c: Dictionary = cards[i]
				var score := 0
				var primary_card: bool = String(c.kind) in ["rank", "rune", "evolve"] and not String(c.get("skill_id", "")).is_empty() and not String(c.skill_id).contains("_")
				if primary_card: score = 100 - KIND_ORDER.find(String(c.kind))
				elif String(c.kind) == "survival": score = 40
				elif String(c.kind) == "filler": score = 30
				else: score = 1
				if score > best_score:
					best = i
					best_score = score
			return best
		_:
			var order: Array = (LINK_RANK_ORDER if policy == "link_rank" else LINK_ORDER).get(element, [])
			var best := 0
			var best_rank := 1 << 30
			for i in cards.size():
				var c: Dictionary = cards[i]
				var rank: int = order.find(String(c.id))
				if rank < 0: rank = 100 + KIND_ORDER.find(String(c.kind))
				if rank < best_rank:
					best = i
					best_rank = rank
			return best
