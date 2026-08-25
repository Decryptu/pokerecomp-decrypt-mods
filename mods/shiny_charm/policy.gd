extends RefCounted

## How many times the host rolls a wild Pokemon's DV word. The roll, its RNG and
## the shininess test are all the host's; this answers one number.

const Charm := preload("charm.gd")

var _host: Gen2ModHost = null


func _init(host: Gen2ModHost) -> void:
	_host = host


## The bag is the whole question. A key item cannot be tossed, so there is no
## second flag to keep in step with it.
func shiny_rolls(_context: Dictionary) -> int:
	if _host == null:
		return Charm.VANILLA_ROLLS
	if int(_host.inventory().get(Charm.NUMBER, 0)) > 0:
		return Charm.ROLLS
	return Charm.VANILLA_ROLLS
