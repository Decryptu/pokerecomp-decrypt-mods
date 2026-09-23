extends RefCounted

const Charm := preload("charm.gd")

var _host: Gen2ModHost = null


func _init(host: Gen2ModHost) -> void:
	_host = host


func shiny_rolls(_context: Dictionary) -> int:
	if _host == null:
		return Charm.VANILLA_ROLLS
	if int(_host.inventory().get(Charm.NUMBER, 0)) > 0:
		return Charm.ROLLS
	return Charm.VANILLA_ROLLS
