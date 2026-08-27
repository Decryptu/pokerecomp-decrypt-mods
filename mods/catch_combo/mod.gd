extends RefCounted

## A Catch Combo: catch the same species over and over and the wild Pokemon of
## that species are drawn with more DV words, so a shiny comes sooner.
##
## The mod holds a counter and answers two questions with it. It rolls no DV,
## draws no box and touches no save: the host rolls the words, the battle draws
## the line, and the combo lives as long as the game is open, which is the rule
## the later games have.

const Combo := preload("combo.gd")
const Options := preload("options.gd")

## The rungs a RUNGS box speaks at: where a combo is worth more words than it
## was one catch ago. Taken from the ladder rather than written twice.
const SPOKEN: Array = Combo.RUNGS

var _combo: Combo = null
var _host: Gen2ModHost = null
var _id: StringName = &""


func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	_host = host
	_id = manifest.id
	_combo = Combo.new()
	Options.register(host, manifest.id)
	## The host keeps both providers, so they have to outlive `register`.
	host.register_shiny_rolls(manifest.id, Rolls.new(_combo))
	host.register_save_lifecycle(manifest, Session.new(_combo))
	host.subscribe(Gen2ModHost.CHANNEL_BATTLE, manifest.id, _on_battle_event)


## Every event this mod reads is one the battle already shows the player, in the
## order they read it, so the counter moves on the line that says why.
func _on_battle_event(event: Dictionary) -> void:
	match StringName(event.get("type", &"")):
		&"caught":
			_on_caught(event)
		## Roar, Whirlwind and a wild's own Teleport are the three ways a wild
		## leaves a Generation II battle standing. Against a trainer the first
		## two are `dragged_out` and Teleport fails, so an enemy on any of these
		## is a wild that got away.
		&"fled_in_fear", &"blown_away":
			if int(event.get("target", Gen2Battle.PLAYER)) == Gen2Battle.ENEMY:
				_combo.broke()
		&"fled_from_battle":
			if int(event.get("side", Gen2Battle.PLAYER)) == Gen2Battle.ENEMY:
				_combo.broke()


## The tutorial catch and a Bug Contest catch are not kept Pokemon, and the host
## excludes both from catch experience for the same reason.
func _on_caught(event: Dictionary) -> void:
	if bool(event.get("tutorial", false)) or bool(event.get("contest", false)):
		return
	_combo.caught(int(event.get("species", 0)))
	var line: String = _line()
	if line != "":
		_host.request_battle_message(_id, line)


## The box, or an empty string for a catch this setting has nothing to say about.
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


## How many DV words one wild is drawn with. Read on every wild the host builds,
## so a combo that moved between two steps is worth its new rung on the next one.
class Rolls extends RefCounted:
	var _combo: RefCounted = null

	func _init(combo: RefCounted) -> void:
		_combo = combo

	func shiny_rolls(context: Dictionary) -> int:
		return _combo.rolls_for(int(context.get("species", 0)))


## A combo belongs to the session and not to the save, the way it is lost when
## the Let's Go games are closed. Opening a slot and leaving one both start from
## nothing, so a combo can never be reloaded and never reaches a save file.
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
