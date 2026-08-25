extends RefCounted

## Population policy for the host's visible-encounter seam. Sprites, collision,
## battle transfer, shiny palettes, animation and audio remain host work.

const Options := preload("options.gd")
const Plan := preload("plan.gd")
const Rng := preload("rng.gd")
## The turnover's own stream name, mixed into its seed so it cannot draw the same
## numbers the build did.
const REFRESH_DOMAIN: int = 0x52465348
const SHINY_PULSE_FRAMES: int = 600
## The glow a Pokemon with high DVs wears: its own four colours walked toward a
## light and back, not something drawn over it. See `README.md`. A shiny never
## wears one, which `plan.gd:is_excellent` decides.
##
## The curve is sent whole and the host rounds it: `Gen2WorldEncounters` bounds
## the sprite textures a glow may spend by snapping the amount onto its own
## `GLOW_RUNGS`. This peak walks half the way to the light, which the host's
## eighths carry as five distinct steps.
const GLOW_PERIOD_FRAMES: int = 48
const GLOW_PEAK: float = 0.45
const GLOW_COLOR := Color(1.0, 0.87, 0.35)
## A full cell every 1.6 seconds at 60 frames per second. The actor seam names
## integer cells, so moving faster reads as a chain of teleports and leaves no
## room to walk around one.
const MOVE_FRAMES: int = 96

## How long a wild stays before it leaves and another takes its place, in
## overworld frames. Thirty seconds to a minute, rolled per Pokemon: one span for
## all of them would empty a route in one moment and fill it again in the next,
## which reads as the map blinking rather than as a place with things coming and
## going.
##
## Frames and not seconds because `advance_frame` is only spent while the
## overworld is running (`docs/MODS.md`), so a fight, a menu, a text box and a
## fade all stand still: a countdown here is the time the player spent walking
## around, which is the only reading of it that is not a punishment for opening
## the pack.
const DESPAWN_MIN_FRAMES: int = 30 * 60
const DESPAWN_MAX_FRAMES: int = 60 * 60
## When the timer is stamped on the entry, and absent from one that never leaves.
const DESPAWN_AT: StringName = &"despawn_at"

## How often a short population looks for somewhere to put one more, in frames,
## and how many it adds when it does. Half a second and one at a time: a route
## that has just lost three refills over a second and a half instead of all at
## once, and the scan is the eligible sweep, which is not free.
const REFILL_FRAMES: int = 30

var _host: Gen2ModHost = null
var _id: StringName = &""
var _context: Dictionary = {}
var _entries: Array = []
var _frame: int = 0
## The turnover's own generator, kept apart from the build's so that how many
## Pokemon have come and gone does not move what the map was built with. Seeded
## from the same run, map and generation, so one seed still means one map.
var _refresh: RefCounted = null
## The next id number to issue. Never reused inside a map: an id is what a battle
## is reported under and what the host dedupes a pulse by, so a number handed to
## a second Pokemon would tie the two together.
var _next_number: int = 1


func configure(host: Gen2ModHost, id: StringName) -> void:
	_host = host
	_id = id
	host.option_changed.connect(_on_option_changed)


func set_context(context: Dictionary) -> void:
	var generation: int = int(context.get("generation", -1))
	var current_generation: int = int(_context.get("generation", -1))
	if generation < current_generation:
		return
	_context = context.duplicate(true)
	if generation == current_generation:
		return
	_rebuild()


func _rebuild() -> void:
	_frame = 0
	var seed_value: int = int(_context.get("run_seed", 1))
	var maximum: int = _maximum()
	_entries = Plan.build(_context, seed_value, maximum, _id)
	var map: Vector2i = Vector2i(_context.get("map", Vector2i.ZERO))
	_refresh = Rng.new(Rng.mix(seed_value, [
		map.x, map.y, int(_context.get("generation", 0)), REFRESH_DOMAIN
	]))
	_next_number = Plan.first_free_number(maximum)
	for entry: Dictionary in _entries:
		entry["pulse"] = true
		_stamp_despawn(entry)


## One overworld frame. Not one frame of the game: the host spends this only while
## the map is the thing running, so everything counted here is counted in the time
## the player spent on it.
func advance_frame() -> void:
	_frame += 1
	if _frame % MOVE_FRAMES == 0:
		_roam()
	var pulse: bool = _frame % SHINY_PULSE_FRAMES == 0
	var amount: float = _glow_amount()
	for entry: Dictionary in _entries:
		entry["pulse"] = pulse
		if Plan.is_excellent(int(entry.get("dvs", 0))):
			entry["glow"] = {"color": GLOW_COLOR, "amount": amount}
	_retire()
	_refill()


func encounters() -> Array:
	return _entries.duplicate(true)


## A fight or a capture is a departure like any other: the slot it held is freed
## and [method _refill] puts somebody else in it. Whatever the result, since a
## Pokemon that beat the player is no more still standing there than one that was
## caught.
func battle_finished(id: StringName, _result: Dictionary) -> void:
	for index: int in _entries.size():
		if StringName((_entries[index] as Dictionary).get("id", &"")) == id:
			_entries.remove_at(index)
			return


## The frame each Pokemon leaves on, or none at all for a shiny.
##
## A SHINY NEVER COUNTS DOWN. The turnover exists so that a player standing on a
## route keeps rolling for one; taking one away again on a timer would mean the
## roll a player was waiting for could land and be gone while they were reading a
## sign. Only a map change takes a shiny away, which is the reset a warp, a Fly
## and a teleport already are.
##
## `Gen2Stats.is_shiny` through `plan.gd`, which is the host's own answer and the
## same one the sparkle is drawn from, so what is exempt here and what a player
## sees marked cannot come apart.
func _stamp_despawn(entry: Dictionary) -> void:
	if Plan.is_shiny(int(entry.get("dvs", 0))):
		entry.erase(DESPAWN_AT)
		return
	entry[DESPAWN_AT] = _frame + DESPAWN_MIN_FRAMES + _refresh.below(
		DESPAWN_MAX_FRAMES - DESPAWN_MIN_FRAMES + 1
	)


## Everybody whose time is up, taken off the map. Walked backwards so a removal
## does not move the entry after it out from under the loop.
func _retire() -> void:
	for index: int in range(_entries.size() - 1, -1, -1):
		var entry: Dictionary = _entries[index]
		if entry.has(DESPAWN_AT) and _frame >= int(entry[DESPAWN_AT]):
			_entries.remove_at(index)


## One more Pokemon where there is room for one, which is what keeps a route
## alive: a player standing still sees the population turn over and rolls its DVs
## and its shininess again without leaving the map.
##
## One at a time and twice a second, so a route that has just lost three fills
## over a second and a half rather than in one frame, and so the eligible sweep
## `plan.gd:mint` walks is not spent on every frame of a map that is already full.
##
## Nowhere to stand answers nothing, which is the honest reading of a script that
## has switched wilds off or a map whose free cells are all occupied: the
## population stays short and fills when there is somewhere to fill it.
func _refill() -> void:
	if _refresh == null or _frame % REFILL_FRAMES != 0:
		return
	if _entries.size() >= _maximum():
		return
	var taken: Array[Vector2i] = []
	for entry: Dictionary in _entries:
		taken.append(Vector2i(entry["cell"]))
	var entry: Dictionary = Plan.mint(_context, _refresh, taken, _next_number, _id)
	if entry.is_empty():
		return
	_next_number += 1
	## Asked for on the frame it appears, so a shiny that arrives while the player
	## is standing there announces itself the way one does on a map change. The
	## host draws nothing for an ordinary Pokemon.
	entry["pulse"] = true
	_stamp_despawn(entry)
	_entries.append(entry)


func _on_option_changed(id: StringName, key: StringName, _value: Variant) -> void:
	if id == _id and key == Options.MAXIMUM and not _context.is_empty():
		_rebuild()


## One frame of the breath: a raised cosine, so a Pokemon spends most of the
## cycle near its own colours and only passes through the top of it.
func _glow_amount() -> float:
	var phase: float = TAU * float(_frame % GLOW_PERIOD_FRAMES) / float(GLOW_PERIOD_FRAMES)
	return GLOW_PEAK * 0.5 * (1.0 - cos(phase))


## The ladder is `options.gd`'s and is read from it, so a rung added there is a
## rung the population actually reaches.
func _maximum() -> int:
	return Options.maximum(_host, _id)


## One step each, into a cell that is eligible and empty.
##
## The host answers who is standing where and this file does the refusing:
## `occupied` holds the map's own objects, NPCs and item balls alike, both cells
## of one mid-step and all four of a big one. A wild an NPC walks onto is left
## where it is and steps off on its own at the next move.
func _roam() -> void:
	var eligible: Dictionary = _context.get("eligible", {})
	var player: Dictionary = _context.get("player", {})
	var player_cell: Vector2i = Vector2i(player.get("cell", Vector2i(-1, -1)))
	var occupied: PackedVector2Array = _context.get("occupied", PackedVector2Array())
	for index: int in _entries.size():
		var entry: Dictionary = _entries[index]
		var method: StringName = StringName(entry.get("method", &""))
		if method == &"":
			continue
		var cells: PackedVector2Array = eligible.get(method, PackedVector2Array())
		var here: Vector2i = Vector2i(entry["cell"])
		var choices: Array[Vector2i] = []
		for delta: Vector2i in [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = here + delta
			if next != player_cell and cells.has(next) \
					and not occupied.has(Vector2(next)) and not _standing_at(next):
				choices.append(next)
		if choices.is_empty():
			continue
		var pick: int = (index + 1 + _frame / MOVE_FRAMES) % choices.size()
		entry["cell"] = choices[pick]
		entry["facing"] = _facing(choices[pick] - here)


## Whether one of this provider's own wilds is already there. The map's objects
## are the host's answer and arrive in the context; see `_roam`.
func _standing_at(cell: Vector2i) -> bool:
	for entry: Dictionary in _entries:
		if Vector2i(entry["cell"]) == cell:
			return true
	return false


func _facing(delta: Vector2i) -> int:
	if delta == Vector2i.UP:
		return 1
	if delta == Vector2i.LEFT:
		return 2
	if delta == Vector2i.RIGHT:
		return 3
	return 0
