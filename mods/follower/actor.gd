extends RefCounted

## The follower as the host drives it: one observation a frame in, one sprite
## out, and no writes at all.
##
## This is the shape `register_world_actor` asks for. Everything it reads is
## public on `Gen2WorldAPI` and everything it draws with is the host's: a sprite
## here names the cartridge's own icon row and nothing else, so the host
## resolves the strip, the palette, the time of day and the icon's own two
## frames. An actor gets both of those; a mon-icon MAP object shows frame 0
## forever, because `GetUsedSprite` copies an icon's eight tiles into both
## banks and the walking rows of `Facings` land on the same picture.
##
## Not a scene node and never one. A follower is a pose, and the pose layer is
## `docs/MODS.md`'s own answer to a mod that wants one.
##
## Three of the actor contract's methods are optional and this one defines all
## three: `interact` is the press a player facing it spends, `sprites()` carries
## the heart while it is up, and `take_requests` is the outbox the cry is asked
## for through. The host owns the bubble's pixels and the cry's audio, as it owns
## the icon's, so this file still composes nothing and plays nothing.

const Options := preload("options.gd")
const Party := preload("party.gd")
const Trail := preload("trail.gd")
const Finder := preload("finder.gd")

## How long the heart stays up after a press, in world frames. The mod owns the
## duration because the emote is a POSE the host draws while it is asked for
## rather than an edge the host times, and this is the host's own
## `Gen2WorldAPI.TRAINER_SHOCK_FRAMES`, the one `showemote` the engine spends
## without a script behind it.
const HEART_FRAMES: int = 60

var _host: Gen2ModHost = null
var _id: StringName = &"follower"
var _world: Gen2WorldAPI = null
var _trail: RefCounted = Trail.new()
## What the player last chose, read on a change rather than every frame.
var _settings: Dictionary = Options.settings(null)
## Whether the recall control has put the follower away. Per session and not per
## save: the host hands a mod its own save namespace through the manifest, and
## an actor is handed a world, so a recall that outlives a reload is a thing to
## ask for once anything wants it.
var _recalled: bool = false
var _pose: Dictionary = {}
## Frames of heart left, counted down a frame at a time.
var _heart: int = 0
## The one-shot outbox the host drains once a world frame. A cry is an edge and
## belongs here; the heart is a pose and belongs in `sprites()`.
var _outbox: Array = []
## Cells asked for on this map, so a pack that is full is not asked to hold one
## more item on every frame the follower stands there. A successful take sets the
## site's own event flag and the record answers `taken` forever after, so this
## only ever holds the asks the world refused.
var _asked: Dictionary = {}


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
	_asked = {}


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


## What to draw, in the order to draw it. A read, so a second view asking again
## in the same frame gets the same answer.
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
## Petting is not a setting: it costs a player nothing they did not go looking
## for, since the press only ever reaches here when the world had no answer of
## its own for the cell the follower happens to be standing on.
func interact(cell: Vector2i, facing: int) -> bool:
	if _world == null or _pose.is_empty() or not bool(_pose.get("out", false)):
		return false
	if cell != (_pose["cell"] as Vector2i):
		return false
	var member: Dictionary = _member()
	if not bool(member.get("out", false)):
		return false
	_trail.face_back(facing)
	## The pose is answered from `_pose` rather than from the trail, and the read
	## the host is about to take is this frame's, so the turn lands in both.
	_pose["facing"] = int(_trail.facing())
	_heart = HEART_FRAMES
	## A mod may not play a sound. It asks, and the host spends it through the
	## same player `Script_cry` and the Pokedex's own CRY button use.
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
## The ask is a REQUEST and never the act: taking one writes the bag, the event
## flag and the save and runs the site's own `verbosegiveitem`, all of which is
## the host's. The mod names a cell, exactly as a visible-encounter provider
## names the entry the host starts a battle from.
func _look_for_an_item() -> void:
	if _host == null or not bool(_settings[Options.PICKUP]):
		return
	if _pose.is_empty() or not bool(_pose.get("out", false)):
		return
	## Mid-step it is drawn between two cells and has not arrived yet, and a
	## record found now would be asked for eight frames running.
	if (_pose["offset"] as Vector2) != Vector2.ZERO:
		return
	var cell: Vector2i = _pose["cell"]
	var record: Dictionary = Finder.reach(
		_world.hidden_items(), cell, _world.can_walk_to
	)
	if record.is_empty():
		return
	var found: Vector2i = record["cell"]
	if _asked.has(found):
		return
	_asked[found] = true
	_host.request_hidden_item(found)


## Whether anything should be out at all: the recall control, the two movement
## settings, and a party that has someone to send.
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


## A slot or a movement setting moved. The follower comes back out from under
## the player rather than sliding across the map from where the last one stood.
func _on_option_changed(id: StringName, key: StringName, _value: Variant) -> void:
	if id != _id or not Options.owns(key):
		return
	_settings = Options.settings(_host)
	if key == Options.SLOT:
		_trail.reset()


func _on_action_changed(id: StringName, key: StringName, pressed: bool) -> void:
	if id != _id or key != Options.RECALL or not pressed:
		return
	_recalled = not _recalled
	_heart = 0
	if not _recalled:
		_trail.reset()
