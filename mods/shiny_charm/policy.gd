extends RefCounted

## How many times the host rolls a wild Pokemon's DV word. Read only: the roll
## itself, the RNG it comes off and the shininess test are the host's, and this
## answers one number.

const Charm := preload("charm.gd")

var _host: Gen2ModHost = null


func _init(host: Gen2ModHost) -> void:
	_host = host


## The bag is the whole of the question. A key item cannot be tossed, so holding
## the charm is a fact a player can only gain, and there is no second flag to
## keep in step with it.
func shiny_rolls(_context: Dictionary) -> int:
	if _host == null:
		return Charm.VANILLA_ROLLS
	if int(_host.inventory().get(Charm.NUMBER, 0)) > 0:
		return Charm.ROLLS
	return Charm.VANILLA_ROLLS
