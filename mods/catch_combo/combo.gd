extends RefCounted

## The combo itself: which species it is on, how long it is, and every rule that
## moves it. Nothing here draws or writes anything; `mod.gd` owns both.
##
## The rungs are the Let's Go games' own. A combo is worth extra DV words rather
## than a multiplier, because that is what the later games do and what the host
## already offers: `register_shiny_rolls` draws that many words and keeps the
## first shiny one, so 4 rolls is very nearly four times the chance.

## `[length, rolls]`, longest first. Read in order, so the first rung a combo
## reaches is its answer.
const RUNGS: Array = [[31, 12], [21, 8], [11, 4]]

## The species this combo is on, 0 when there is none.
var species: int = 0
var length: int = 0


## A wild was caught. A different species is not a broken combo: it is the first
## link of that species' own, which is what the counter reads after it.
func caught(caught_species: int) -> void:
	if caught_species <= 0:
		return
	length = length + 1 if caught_species == species else 1
	species = caught_species


## The wild left the field under its own power: Roar, Whirlwind or its own
## Teleport. That is the games' one break, and the only one this cartridge can
## show. Running, fainting it, losing and walking away all leave the combo alone.
func broke() -> void:
	species = 0
	length = 0


## How many DV words a wild of [param for_species] is drawn with. The boost is
## the chained species' alone, so a Rattata combo does not shine the Pidgey that
## interrupts it.
func rolls_for(for_species: int) -> int:
	if for_species != species or species <= 0:
		return 1
	for rung: Array in RUNGS:
		if length >= int(rung[0]):
			return int(rung[1])
	return 1
