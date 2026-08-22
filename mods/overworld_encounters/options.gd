extends RefCounted

const MAXIMUM: StringName = &"maximum"
## How many wild Pokemon one map may hold at once.
##
## THE TOP TWO RUNGS ARE THE SEAMLESS WORLD'S. The ladder stopped at eight when
## the screen was ten walk cells by nine and a route was walked a screen at a
## time: eight spread over a whole route was more than a player ever saw at once.
## The overworld now draws to the edge of the window and zooms out past that, so
## the same eight read as an empty route with a few Pokemon on it. Twelve and
## sixteen are for the window a player is actually looking at, and the default
## does not move: a population is a rebalance, and choosing one is theirs.
##
## `plan.gd:build` clamps at 32, which is the host's own ceiling and where this
## ladder must stop.
const MAXIMUM_VALUES: Array = [2, 4, 6, 8, 12, 16]
const MAXIMUM_DEFAULT: int = 6


static func register(host: Gen2ModHost, id: StringName) -> void:
	host.register_option(id, {
		"key": MAXIMUM, "label": "VISIBLE",
		"values": MAXIMUM_VALUES, "labels": ["2", "4", "6", "8", "12", "16"],
		"default": MAXIMUM_DEFAULT,
	})


static func maximum(host: Gen2ModHost, id: StringName) -> int:
	if host == null:
		return MAXIMUM_DEFAULT
	var value: Variant = host.option(id, MAXIMUM)
	if value == null:
		return MAXIMUM_DEFAULT
	return clampi(int(value), MAXIMUM_VALUES[0], MAXIMUM_VALUES[-1])
