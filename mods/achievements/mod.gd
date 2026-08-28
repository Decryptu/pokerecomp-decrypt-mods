extends RefCounted

## Registers the settings, the page, the start-menu row that opens it, and a
## save lifecycle, then watches the run.
##
## Nothing here is a scene node, nothing draws and nothing reads world or battle
## state: `catalogue.gd` says what an achievement is, `ledger.gd` says what one
## save has, and the host answers everything else. The reading it answers is
## state the run has reached rather than a moment it passed, which is exactly
## what a save installed onto late can still be asked.
##
## The ledger belongs to the save rather than to the installation, because two
## slots are two runs: a badge won in one is not won in the other, and a slot
## reopened has to find its own set and say nothing about it again.

const Catalogue := preload("catalogue.gd")
const Ledger := preload("ledger.gd")
const Options := preload("options.gd")

## The banner says what kind of thing happened and then which one, the way the
## host's own example says `BADGE WON` and then the badge.
const NOTICE_TITLE: String = "ACHIEVEMENT"
const PAGE_TITLE: String = "ACHIEVEMENTS"
## The row the count sits on, above the list.
const COUNT_LABEL: String = "UNLOCKED"
## What a summary wears, which is the mod's own face.
const SUMMARY_ICON: Dictionary = {"badge": Catalogue.BADGE_ZEPHYR}
## `Gen2ModHost.NOTICE_SOUNDS`' silence, for a player who wanted the banner and
## not the jingle.
const SOUND_NONE: StringName = &"none"

var _host: Gen2ModHost = null
var _manifest: Gen2ModManifest = null
var _id: StringName = &""
var _ledger: Ledger = Ledger.new()
## The slot being played. Held because a scan writes the ledger back into it, and
## null between one being closed and the next opening.
var _save: Gen2SaveData = null


func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	_host = host
	_manifest = manifest
	_id = manifest.id
	Options.register(host, manifest.id)
	host.register_page(manifest.id, {"title": PAGE_TITLE, "rows": _rows})
	host.register_menu_entry(Gen2ModHost.MENU_START, manifest.id, {
		"label": PAGE_TITLE,
		"action": Gen2ModHost.START_ACTION_OPEN_MOD_PAGE,
		"page": manifest.id,
	})
	host.register_save_lifecycle(manifest, self)
	host.progress_changed.connect(_on_progress_changed)


## A run that began with the mod installed is written an empty ledger, which is
## what tells activation apart from a save played before the mod existed: that
## one carries nothing, and everything already true of it is awarded under one
## line rather than thirty, since it was earned while nothing was watching.
func save_created(save: Gen2SaveData) -> void:
	if save == null:
		return
	_host.write_save_data(_manifest, save, Ledger.new().stored())


func save_activated(save: Gen2SaveData) -> void:
	_save = save
	if save == null:
		## A development run has no slot to own a set, and awarding into one
		## that is never written would announce the same thing every boot.
		_ledger.closed()
		return
	_ledger.restore(_host.read_save_data(_manifest, save))
	## The reading off the save rather than off the world: the slot has been
	## chosen and no world exists yet, and this is the one that answers for a
	## save the mod was installed onto. The save names its own cartridge, so the
	## badge table is the right one without this mod holding any cache.
	_scan(_host.progress_for(save))


func save_deactivated() -> void:
	_save = null
	_ledger.closed()


## The run moved. Only the fields that moved bring us here, so this is as often
## as the host reads and no more.
func _on_progress_changed(progress: Dictionary) -> void:
	_scan(progress)


## Awards whatever the reading makes true, keeps it in the save, and says so.
func _scan(progress: Dictionary) -> void:
	var answer: Dictionary = _ledger.scan(progress)
	var fresh: Array = answer["unlocked"]
	if fresh.is_empty():
		return
	if _save != null:
		_host.write_save_data(_manifest, _save, _ledger.stored())
	if not Options.notice(_host):
		return
	if bool(answer["quiet"]):
		_announce(NOTICE_TITLE, "%d UNLOCKED" % fresh.size(), SUMMARY_ICON, "")
		return
	for id: Variant in fresh:
		var row: Dictionary = Catalogue.find(StringName(id))
		if row.is_empty():
			continue
		_announce(
			NOTICE_TITLE, String(row["name"]), row["icon"] as Dictionary,
			StringName(row.get("sound", &""))
		)


## One banner. The host holds it while a battle, a menu, a script or a warp owns
## the world and raises it on the next frame that is free, so nothing here waits
## for a moment of its own.
func _announce(title: String, line: String, icon: Dictionary, sound: StringName) -> void:
	_host.request_notice(_id, {
		"title": title,
		"line": line,
		"icon": icon,
		"sound": sound if Options.sound(_host) and sound != &"" else SOUND_NONE,
	})


## What the page lists, asked fresh every time it is drawn. The count sits above
## the rows because the page's title is fixed at registration and a run's tally
## is not.
func _rows() -> Array:
	var counts: Vector2i = _ledger.progress_counts()
	var out: Array = [{
		"label": COUNT_LABEL,
		"detail": "%d OF %d" % [counts.x, counts.y],
		"locked": false,
	}]
	for row: Dictionary in Catalogue.ROWS:
		var held: bool = _ledger.has(StringName(row["id"]))
		out.append({
			"label": String(row["name"]),
			"detail": String(row["detail"]),
			"icon": row["icon"],
			## The host draws a locked row the way the Pokedex draws an unseen
			## entry, which is this cartridge's own answer to the question.
			"locked": not held,
		})
	return out
