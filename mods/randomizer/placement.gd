extends RefCounted

## Items and badges placed by assumed fill over the host's reachability, so a
## placement finishes by construction; shops remapped outside any proof.

const Rng := preload("rng.gd")

## A fill that spends the one site a later reward needed starts over. About two
## Gold, Silver and Crystal badge fills in three do, so all 64 failing is ~1e-12.
const FILL_ATTEMPTS: int = 64
const HANDS_NO_ITEM: Dictionary = {"item": 0}
const HANDS_NO_BADGE: Dictionary = {"badge": -1}
const SAVED_ITEMS: String = "items"
const SAVED_BADGES: String = "badges"


## `{checks, unplaced, restarts}`; [param reach] answers `reachable_checks`'
## `reached` for `(patches, held)`. Badges fill around the vanilla items and items
## around both badge arrangements, so every combination of settings finishes.
static func resolve(world: Dictionary, settings: Dictionary, reach: Callable) -> Dictionary:
	var out: Dictionary = {"checks": {}, "unplaced": [], "restarts": 0}
	var items: bool = bool(settings.get("items", false))
	var badges: bool = bool(settings.get("badges", false))
	if not (items or badges) or not reach.is_valid():
		return out
	var run: Dictionary = {"seed": int(settings.get("seed", 0)), "reach": reach}
	var rows: Dictionary = world[Gen2ContentOverlay.KIND_CHECK]
	var badge_spec: Dictionary = _badge_spec(rows)
	var badge_fill: Variant = _fill(badge_spec, "badge", [{}], run)
	if badges:
		_adopt(out, badge_spec, badge_fill, SAVED_BADGES)
	if items:
		var item_spec: Dictionary = _item_spec(rows, world["progression_items"])
		var arrangements: Array = [{}] if badge_fill == null else [{}, badge_fill]
		_adopt(out, item_spec, _fill(item_spec, "item", arrangements, run), SAVED_ITEMS)
	return out


static func _adopt(out: Dictionary, spec: Dictionary, fill: Variant, category: String) -> void:
	out["restarts"] = int(out["restarts"]) + int(spec["restarts"])
	if fill == null:
		(out["unplaced"] as Array).append(category)
		return
	(out["checks"] as Dictionary).merge(fill)


## One slot per badge: every site that gave it.
static func _badge_spec(rows: Dictionary) -> Dictionary:
	var groups: Dictionary = {}
	for id: int in site_ids(rows, Gen2WorldCatalog.KIND_BADGE):
		var badge: int = int((rows[id] as Dictionary).get("badge", 0))
		if not groups.has(badge):
			groups[badge] = []
		(groups[badge] as Array).append(id)
	var badges: Array = groups.keys()
	badges.sort()
	var spec: Dictionary = _spec(HANDS_NO_BADGE)
	for badge: int in badges:
		(spec["pool"] as Array).append({"badge": badge})
		(spec["slots"] as Array).append(groups[badge])
	return spec


## The items the story reads are placed; the rest are dealt into what is left.
static func _item_spec(rows: Dictionary, progression: Array) -> Dictionary:
	var spec: Dictionary = _spec(HANDS_NO_ITEM)
	for id: int in site_ids(rows, Gen2WorldCatalog.KIND_ITEM):
		var row: Dictionary = rows[id]
		var reward: Dictionary = {
			"item": int(row.get("item", 0)), "quantity": int(row.get("quantity", 1)),
		}
		(spec["pool" if progression.has(reward["item"]) else "filler"] as Array).append(reward)
		(spec["slots"] as Array).append([id])
	return spec


static func _spec(blank: Dictionary) -> Dictionary:
	return {"pool": [], "filler": [], "slots": [], "blank": blank, "restarts": 0}


static func _fill(spec: Dictionary, stream: String, arrangements: Array, run: Dictionary) -> Variant:
	var reach: Callable = run["reach"]
	var room: Dictionary = _room(spec, reach, arrangements)
	for attempt: int in FILL_ATTEMPTS:
		var rng := Rng.new()
		rng.begin(int(run["seed"]), "%s_fill" % stream, attempt)
		var order: Array = _ordered(rng.shuffled(spec["pool"]), room)
		var placed: Variant = _assumed_fill(spec, order, rng, reach, arrangements)
		if placed == null:
			spec["restarts"] = int(spec["restarts"]) + 1
			continue
		var filler := Rng.new()
		filler.begin(int(run["seed"]), "%s_filler" % stream, 0)
		_deal(spec, placed, filler)
		return placed
	return null


## How many slots each reward fits with every other in hand. The scarcest go
## first, before others take the few gyms they fit.
static func _room(spec: Dictionary, reach: Callable, arrangements: Array) -> Dictionary:
	var pool: Array = spec["pool"]
	var room: Dictionary = {}
	for index: int in pool.size():
		var key: String = str(pool[index])
		if room.has(key):
			continue
		var others: Array = pool.duplicate()
		others.remove_at(index)
		var fits: Array = _reached(spec, {}, spec["slots"], _held(others), reach, arrangements)
		room[key] = fits.size()
	return room


static func _ordered(shuffled: Array, room: Dictionary) -> Array:
	var positions: Array = range(shuffled.size())
	positions.sort_custom(func(first: int, second: int) -> bool:
		var first_room: int = room[str(shuffled[first])]
		var second_room: int = room[str(shuffled[second])]
		return first < second if first_room == second_room else first_room < second_room)
	return positions.map(func(at: int) -> Dictionary: return shuffled[at])


## Each reward goes to a random open slot reached, in every arrangement, with the
## rewards after it in hand and every open slot handing nothing.
static func _assumed_fill(
	spec: Dictionary, order: Array, rng: RefCounted, reach: Callable, arrangements: Array
) -> Variant:
	var open: Array = (spec["slots"] as Array).duplicate()
	var placed: Dictionary = {}
	for index: int in order.size():
		var held: Dictionary = _held(order.slice(index + 1))
		var reached: Array = _reached(spec, placed, open, held, reach, arrangements)
		if reached.is_empty():
			return null
		var slot: Array = reached[rng.below(reached.size())]
		open.erase(slot)
		for id: int in slot:
			placed[id] = (order[index] as Dictionary).duplicate()
	return placed


static func _reached(
	spec: Dictionary, placed: Dictionary, open: Array, held: Dictionary,
	reach: Callable, arrangements: Array
) -> Array:
	var reached: Array = open
	for arrangement: Dictionary in arrangements:
		var patches: Dictionary = _with_open(arrangement, placed, open, spec["blank"])
		reached = _slots_within(reached, reach.call(patches, held))
	return reached


static func _held(rewards: Array) -> Dictionary:
	var held: Dictionary = {"items": [], "badges": []}
	for reward: Dictionary in rewards:
		if reward.has("badge"):
			(held["badges"] as Array).append(int(reward["badge"]))
		else:
			(held["items"] as Array).append(int(reward["item"]))
	return held


static func _with_open(
	arrangement: Dictionary, placed: Dictionary, open: Array, blank: Dictionary
) -> Dictionary:
	var patches: Dictionary = arrangement.duplicate()
	patches.merge(placed, true)
	for slot: Array in open:
		for id: int in slot:
			patches[id] = blank
	return patches


static func _slots_within(slots: Array, reached_ids: Array) -> Array:
	var reached: Dictionary = {}
	for id: Variant in reached_ids:
		reached[int(id)] = true
	return slots.filter(func(slot: Array) -> bool:
		return slot.all(func(id: int) -> bool: return reached.has(id)))


static func _deal(spec: Dictionary, placed: Dictionary, rng: RefCounted) -> void:
	var filler: Array = rng.shuffled(spec["filler"])
	var index: int = 0
	for slot: Array in spec["slots"]:
		if placed.has(slot[0]):
			continue
		for id: int in slot:
			placed[id] = (filler[index] as Dictionary).duplicate()
		index += 1


## A permutation of the item ids on shelves keeps sizes, prices and no repeats.
static func shops(rows: Dictionary, seed_value: int) -> Dictionary:
	var sites: Array[int] = site_ids(rows, Gen2WorldCatalog.KIND_SHOP)
	var mapping: Dictionary = _shop_mapping(rows, sites, seed_value)
	var out: Dictionary = {}
	for id: int in sites:
		var shelf: Array = ((rows[id] as Dictionary).get("items", []) as Array).duplicate(true)
		for entry: Dictionary in shelf:
			entry["item"] = int(mapping[int(entry.get("item", 0))])
		out[id] = {"items": shelf}
	return out


static func _shop_mapping(rows: Dictionary, sites: Array[int], seed_value: int) -> Dictionary:
	var stock: Array[int] = []
	for id: int in sites:
		for entry: Dictionary in ((rows[id] as Dictionary).get("items", []) as Array):
			if not stock.has(int(entry.get("item", 0))):
				stock.append(int(entry.get("item", 0)))
	stock.sort()
	var rng := Rng.new()
	rng.begin(seed_value, "shop_placement", 0)
	var replacements: Array = rng.shuffled(stock)
	var mapping: Dictionary = {}
	for index: int in stock.size():
		mapping[stock[index]] = int(replacements[index])
	return mapping


static func site_ids(rows: Dictionary, kind: StringName) -> Array[int]:
	var out: Array[int] = []
	for id: int in rows:
		if StringName((rows[id] as Dictionary).get("kind", &"")) == kind:
			out.append(id)
	out.sort()
	return out


## Flat lists for a save: `items` as id, item, quantity; `badges` as id, badge.
static func packed(checks: Dictionary) -> Dictionary:
	var out: Dictionary = {SAVED_ITEMS: [], SAVED_BADGES: []}
	var ids: Array = checks.keys()
	ids.sort()
	for id: int in ids:
		var fields: Dictionary = checks[id]
		if fields.has("badge"):
			(out[SAVED_BADGES] as Array).append_array([id, int(fields["badge"])])
		else:
			(out[SAVED_ITEMS] as Array).append_array(
				[id, int(fields["item"]), int(fields["quantity"])]
			)
	return out


static func unpacked(saved: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var items: Array = saved.get(SAVED_ITEMS, [])
	for at: int in range(0, items.size() - 2, 3):
		out[int(items[at])] = {"item": int(items[at + 1]), "quantity": int(items[at + 2])}
	var badges: Array = saved.get(SAVED_BADGES, [])
	for at: int in range(0, badges.size() - 1, 2):
		out[int(badges[at])] = {"badge": int(badges[at + 1])}
	return out
