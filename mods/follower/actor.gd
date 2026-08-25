extends RefCounted

## The follower as the host drives it: one observation a frame in, one sprite
## out, no writes.
##
## The shape `register_world_actor` asks for. Everything it reads is public on
## `Gen2WorldAPI`, and a sprite here names the cartridge's own icon row and
## nothing else, so the host resolves the strip, the palette, the hour and the
## icon's two frames. An actor gets both frames; a mon-icon map object shows
## frame 0 forever, since `GetUsedSprite` copies an icon's eight tiles into both
## banks.
##
## All three optional actor methods are defined here: `interact` for the press,
## `sprites()` for the heart while it is up, and `take_requests` for the cry. The
## host owns the bubble's pixels and the cry's audio, so nothing is composed or
## played here.

const Options := preload("options.gd")
const Party := preload("party.gd")
const Trail := preload("trail.gd")
const Finder := preload("finder.gd")

## How long the heart stays up, in world frames. The mod owns the duration
## because the emote is a pose the host draws while it is asked for. This is the
## host's own `Gen2WorldAPI.TRAINER_SHOCK_FRAMES`.
const HEART_FRAMES: int = 60

var _host: Gen2ModHost = null
var _id: StringName = &"follower"
var _world: Gen2WorldAPI = null
var _trail: RefCounted = Trail.new()
## What the player last chose, read on a change rather than every frame.
var _settings: Dictionary = Options.settings(null)
## Whether the recall control has put the follower away. Per session: an actor
## is handed a world rather than a save.
var _recalled: bool = false
var _pose: Dictionary = {}
## Frames of heart left, counted down a frame at a time.
var _heart: int = 0
## Drained once a world frame. A cry is an edge and belongs here; the heart is a
## pose and belongs in `sprites()`.
var _outbox: Array = []
## The cell the follower was last looked at on, which is what makes one ARRIVAL
## one attempt. The host collapses a cell already queued and one whose flag is
## already set, so nothing here has to remember which cells have been named, and
## what is left is the cartridge's own unit: a step. It has to be where the
## follower STANDS and not where an ask was made, or walking away and back would
## match the cell of the last ask and say nothing. A pack that was full when the
## follower walked on is therefore asked again the next time it walks on, which
## a set of every cell already named could never do.
var _stood_at := Vector2i.MAX


func configure(host: Gen2ModHost, id: StringName) -> void:
	_host = host
	_id = id
	_settings = Options.settings(host)
	host.option_changed.connect(_on_option_changed)
	host.action_changed.connect(_on_action_changed)


## The map changed, or the view was created.
func set_world(world: Gen2WorldAPI) -> void:
	_world = world
	_pose = {}
	_heart = 0
	_stood_at = Vector2i.MAX


## One world frame, after the player's own step has advanced.
func advance_frame() -> void:
	if _world == null:
		return
	_heart = maxi(0, _heart - 1)
	_pose = _trail.observe({
		"map": _world.map_id(),
		"cell": _world.player_cell,
		"facing": _world.player_facing,
		"offset": _world.player_step_offset_cells(),
		"allowed": _allowed(),
	})
	_look_for_an_item()


## What to draw. A read, so two views asking in one frame get the same answer.
func sprites() -> Array:
	if _world == null or _pose.is_empty() or not bool(_pose.get("out", false)):
		return []
	var member: Dictionary = _member()
	if not bool(member.get("out", false)):
		return []
	var entry: Dictionary = {
		"icon": int(member["icon"]),
		"facing": int(_pose["facing"]),
		"position_cells": Vector2(_pose["cell"] as Vector2i) + (_pose["offset"] as Vector2),
	}
	if _heart > 0:
		entry["emote"] = Gen2WorldActors.EMOTE_HEART
	return [entry]


## A press of A the cartridge answered nothing for, offered because the player is
## facing [param cell]. True consumes it, and the host re-reads `sprites()` on
## the same frame, so the turn and the heart are up on the frame of the press.
##
## Petting needs no setting: the press only reaches here when the world had no
## answer of its own for that cell.
func interact(cell: Vector2i, facing: int) -> bool:
	if _world == null or _pose.is_empty() or not bool(_pose.get("out", false)):
		return false
	if cell != (_pose["cell"] as Vector2i):
		return false
	var member: Dictionary = _member()
	if not bool(member.get("out", false)):
		return false
	_trail.face_back(facing)
	## `sprites()` answers from `_pose`, so the turn has to land there too.
	_pose["facing"] = int(_trail.facing())
	_heart = HEART_FRAMES
	## A mod may not play a sound. The host spends it through the same player
	## `Script_cry` and the Pokedex's CRY button use.
	_outbox.append({
		"kind": Gen2WorldActors.REQUEST_CRY, "species": int(member["species"]),
	})
	return true


## The outbox, drained once a world frame and emptied by the drain.
func take_requests() -> Array:
	var out: Array = _outbox
	_outbox = []
	return out


## A hidden item under the follower, or one cardinal step into something it could
## not have walked into. `finder.gd` owns the rule; this owns the asking.
##
## It is a request and never the act: taking one writes the bag, the event flag
## and the save and runs the site's own `verbosegiveitem`, all the host's.
##
## Once per arrival. The host drops an ask for a cell already in its queue and
## one whose flag is already set, so the only repeat left to rule on is a site
## that ran and gave nothing, which is the full pack: asking again on the frame
## after would put its box up forever, and never asking again would leave the
## item unreachable for the rest of the map. A step is the line between the two
## and it is the cartridge's own.
func _look_for_an_item() -> void:
	if _host == null or not bool(_settings[Options.PICKUP]):
		return
	if _pose.is_empty() or not bool(_pose.get("out", false)):
		return
	## Mid-step it has not arrived, and a record found now would be asked for
	## eight frames running.
	if (_pose["offset"] as Vector2) != Vector2.ZERO:
		return
	var cell: Vector2i = _pose["cell"]
	if cell == _stood_at:
		return
	# Spent on arrival whatever is found, so a cell with nothing on it is not
	# searched again every frame either.
	_stood_at = cell
	var record: Dictionary = Finder.reach(
		_world.hidden_items(), cell, _world.can_walk_to
	)
	if record.is_empty():
		return
	_host.request_hidden_item(record["cell"])


## The recall control, the two movement settings, and a party with someone in
## it.
func _allowed() -> bool:
	if _recalled:
		return false
	var mode: StringName = _world.movement_mode
	if mode == Gen2WorldAPI.MOVEMENT_BIKE and not bool(_settings[Options.CYCLING]):
		return false
	if mode == Gen2WorldAPI.MOVEMENT_SURF and not bool(_settings[Options.SURFING]):
		return false
	return bool(_member().get("out", false))


func _member() -> Dictionary:
	return Party.member(
		_world.party_summary(), _world.data, int(_settings[Options.SLOT])
	)


## A slot or a movement setting moved.
func _on_option_changed(id: StringName, key: StringName, _value: Variant) -> void:
	if id != _id:
		return
	# The MODS menu row is the same press the control makes, and has to stay so,
	# or the two paths could disagree about whether the follower is out. A button
	# setting carries a null value and stores nothing.
	if key == Options.PUT_AWAY:
		_toggle_recall()
		return
	if not Options.owns(key):
		return
	_settings = Options.settings(_host)
	if key == Options.SLOT:
		_trail.reset()


func _on_action_changed(id: StringName, key: StringName, pressed: bool) -> void:
	if id != _id or key != Options.RECALL or not pressed:
		return
	_toggle_recall()


## Away, or back out from under the player rather than sliding across the map.
func _toggle_recall() -> void:
	_recalled = not _recalled
	_heart = 0
	if not _recalled:
		_trail.reset()
