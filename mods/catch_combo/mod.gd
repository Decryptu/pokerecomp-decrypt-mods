extends RefCounted

## A Catch Combo: catch the same species over and over and the wild Pokemon of
## that species are drawn with more DV words, so a shiny comes sooner.

const Combo := preload("combo.gd")
const Options := preload("options.gd")

const SPOKEN: Array = Combo.RUNGS

var _combo: Combo = null
var _host: Gen2ModHost = null
var _id: StringName = &""


func register(host: Gen2ModHost, manifest: PokeModManifest) -> void:
	_host = host
	_id = manifest.id
	_combo = Combo.new()
	Options.register(host, manifest.id)
	host.register_shiny_rolls(manifest.id, Rolls.new(_combo))
	host.register_save_lifecycle(manifest, Session.new(_combo))
	host.subscribe(Gen2ModHost.CHANNEL_BATTLE, manifest.id, _on_battle_event)


func _on_battle_event(event: Dictionary) -> void:
	match StringName(event.get("type", &"")):
		&"caught":
			_on_caught(event)
		&"fled_in_fear", &"blown_away":
			if int(event.get("target", Gen2Battle.PLAYER)) == Gen2Battle.ENEMY:
				_combo.broke()
		&"fled_from_battle":
			if int(event.get("side", Gen2Battle.PLAYER)) == Gen2Battle.ENEMY:
				_combo.broke()


func _on_caught(event: Dictionary) -> void:
	if bool(event.get("tutorial", false)) or bool(event.get("contest", false)):
		return
	_combo.caught(int(event.get("species", 0)))
	var line: String = _line()
	if line != "":
		_host.request_battle_message(_id, line)


func _line() -> String:
	var box: int = Options.box(_host)
	if box == Options.BOX_OFF or _combo.length <= 0:
		return ""
	if box == Options.BOX_RUNGS and not _is_rung(_combo.length):
		return ""
	return "Catch Combo %d!" % _combo.length


static func _is_rung(length: int) -> bool:
	for rung: Array in SPOKEN:
		if length == int(rung[0]):
			return true
	return false


class Rolls extends RefCounted:
	var _combo: RefCounted = null

	func _init(combo: RefCounted) -> void:
		_combo = combo

	func shiny_rolls(context: Dictionary) -> int:
		return _combo.rolls_for(int(context.get("species", 0)))


class Session extends RefCounted:
	var _combo: RefCounted = null

	func _init(combo: RefCounted) -> void:
		_combo = combo

	func save_created(_save: Variant) -> void:
		pass

	func save_activated(_save: Variant) -> void:
		_combo.broke()

	func save_deactivated() -> void:
		_combo.broke()
