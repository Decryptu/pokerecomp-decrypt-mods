extends RefCounted

## Which Pokemon is out, read off the party the world already mirrors.
##
## The mod keeps no copy of the party and no table of its own: the world screen
## writes `set_party_summary()` on every refresh, and `GameData.mon_menu_icon()`
## is `ReadMonMenuIcon`, the same table the party screen draws its icons from. So
## the follower wears the cartridge's own picture and this mod ships no art.

## The party is six slots; a setting names one of them.
const SLOTS: int = 6


## The chosen slot as `{ out, species, name, icon }`, or `out` false with the
## reason nothing is walking behind the player.
##
## `icon` is the `IconPointers` row a renderer resolves the strip and palette
## from. A species the cartridge does not have answers zero and stays in its
## ball: a Pokemon nothing can draw is not one to put on the map.
static func member(summary: Dictionary, data: GameData, slot: int) -> Dictionary:
	if summary.is_empty() or data == null:
		return _in_ball(&"no_party")
	var species: Array = summary.get("species", [])
	var index: int = clampi(slot, 1, SLOTS) - 1
	if index >= species.size():
		return _in_ball(&"empty_slot")
	# An egg does not walk; the summary carries the flag per slot the way
	# `CheckPartyMove` reads it. API 2 answers fainted the same way, and API 1
	# named only the lead, kept as a fallback.
	var eggs: Array = summary.get("eggs", [])
	if index < eggs.size() and bool(eggs[index]):
		return _in_ball(&"egg")
	var fainted: Array = summary.get("fainted", [])
	if (index < fainted.size() and bool(fainted[index])) \
		or (fainted.is_empty() and index == 0 and bool(summary.get("lead_fainted", false))):
		return _in_ball(&"fainted")
	var number: int = int(species[index])
	var icon: int = data.mon_menu_icon(number)
	if icon <= 0:
		return _in_ball(&"no_icon")
	var names: Array = summary.get("names", [])
	return {
		"out": true,
		"species": number,
		"name": String(names[index]) if index < names.size() else "",
		"icon": icon,
	}


static func _in_ball(reason: StringName) -> Dictionary:
	return {"out": false, "reason": reason, "species": 0, "name": "", "icon": 0}
