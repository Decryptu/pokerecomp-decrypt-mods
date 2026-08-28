extends RefCounted

## The combo itself: which species it is on, how long it is, and every rule
## that moves it.

const RUNGS: Array = [[31, 12], [21, 8], [11, 4]]

var species: int = 0
var length: int = 0


func caught(caught_species: int) -> void:
	if caught_species <= 0:
		return
	length = length + 1 if caught_species == species else 1
	species = caught_species


func broke() -> void:
	species = 0
	length = 0


func rolls_for(for_species: int) -> int:
	if for_species != species or species <= 0:
		return 1
	for rung: Array in RUNGS:
		if length >= int(rung[0]):
			return int(rung[1])
	return 1
