extends RefCounted

## What one save has unlocked, and the two rules that keep a notice honest.
##
## An achievement is awarded once and stays awarded. The set lives in the save's
## own namespace, so closing the game and opening it again finds the same set
## and says nothing about it a second time.
##
## Nothing here reads the world or draws anything: it is handed a progress
## snapshot and answers which ids are new and whether they are worth announcing.

const Catalogue := preload("catalogue.gd")

## The shape stored in the save. Bumping it starts a save's ledger over, which
## is silent, so only bump it for a change that makes the old set meaningless.
const VERSION: int = 1
const KEY_VERSION: String = "version"
const KEY_UNLOCKED: String = "unlocked"

## A scan handing over more than this at once is summarised rather than
## announced one by one. It is what stops a mod update that adds rows from
## firing a dozen notices at a save that already earned all of them.
const QUIET_ABOVE: int = 3

## id -> true. Ids this build does not know are kept rather than dropped, so a
## save opened by an older version and then a newer one is not announced twice.
var unlocked: Dictionary = {}

## Whether the save carried a ledger. A save that did not is a save played
## before the mod was installed: everything already true of it was earned
## without the mod watching, so the first scan grants it and stays quiet.
var _recorded: bool = false


## Takes the value `read_save_data` answered for this save.
func restore(saved: Dictionary) -> void:
	unlocked = {}
	_recorded = int(saved.get(KEY_VERSION, 0)) == VERSION
	if not _recorded:
		return
	var stored_ids: Variant = saved.get(KEY_UNLOCKED, [])
	if not stored_ids is Array:
		return
	for id: Variant in stored_ids as Array:
		unlocked[StringName(id)] = true


## The value to hand `write_save_data`.
func stored() -> Dictionary:
	var ids: Array = []
	for id: StringName in unlocked:
		ids.append(String(id))
	ids.sort()
	return {KEY_VERSION: VERSION, KEY_UNLOCKED: ids}


## Forgets the save. An installation holds no achievements of its own: two slots
## are two runs and neither can see the other's.
func closed() -> void:
	unlocked = {}
	_recorded = false


## Awards everything [param progress] makes true and answers what was new.
##
## `quiet` is the mod's instruction, not a preference: the ids are awarded
## either way, and it says whether announcing them one at a time would be
## telling the player about work they did while nothing was watching.
func scan(progress: Dictionary) -> Dictionary:
	var fresh: Array[StringName] = []
	for id: StringName in Catalogue.held(progress):
		if unlocked.has(id):
			continue
		unlocked[id] = true
		fresh.append(id)
	var quiet: bool = not _recorded or fresh.size() > QUIET_ABOVE
	_recorded = true
	return {"unlocked": fresh, "quiet": quiet}


## How many of this build's own rows are unlocked, and how many there are.
func progress_counts() -> Vector2i:
	var held: int = 0
	for row: Dictionary in Catalogue.ROWS:
		if unlocked.has(StringName(row["id"])):
			held += 1
	return Vector2i(held, Catalogue.ROWS.size())


func has(id: StringName) -> bool:
	return unlocked.has(id)
