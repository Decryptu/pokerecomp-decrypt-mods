extends RefCounted

## Which Pokemon is out, read off the party the world already mirrors.

const SLOTS: int = 6


static func member(summary: Dictionary, data: GameData, slot: int) -> Dictionary:
	if summary.is_empty() or data == null:
		return _in_ball(&"no_party")
	var species: Array = summary.get("species", [])
	var index: int = clampi(slot, 1, SLOTS) - 1
	if index >= species.size():
		return _in_ball(&"empty_slot")
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
