extends RefCounted

## Registers the settings, the page, the start-menu row that opens it, and a
## save lifecycle, then watches the run.

const Catalogue := preload("catalogue.gd")
const Ledger := preload("ledger.gd")
const Options := preload("options.gd")

const NOTICE_TITLE: String = "ACHIEVEMENT"
const PAGE_TITLE: String = "ACHIEVEMENTS"
const COUNT_LABEL: String = "UNLOCKED"
const SUMMARY_ICON: Dictionary = {"badge": Catalogue.BADGE_ZEPHYR}
const SOUND_NONE: StringName = &"none"

var _host: Gen2ModHost = null
var _manifest: Gen2ModManifest = null
var _id: StringName = &""
var _ledger: Ledger = Ledger.new()
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


func save_created(save: Gen2SaveData) -> void:
	if save == null:
		return
	_host.write_save_data(_manifest, save, Ledger.new().stored())


func save_activated(save: Gen2SaveData) -> void:
	_save = save
	if save == null:
		_ledger.closed()
		return
	_ledger.restore(_host.read_save_data(_manifest, save))
	_scan(_host.progress_for(save))


func save_deactivated() -> void:
	_save = null
	_ledger.closed()


func _on_progress_changed(progress: Dictionary) -> void:
	_scan(progress)


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


func _announce(title: String, line: String, icon: Dictionary, sound: StringName) -> void:
	_host.request_notice(_id, {
		"title": title,
		"line": line,
		"icon": icon,
		"sound": sound if Options.sound(_host) and sound != &"" else SOUND_NONE,
	})


## Every row names itself and what it asks, so the page is a list of what to go
## and do. The icon is the mark: the host draws one only where there is one, so
## an unearned row wears a blank icon column.
func _rows() -> Array:
	var counts: Vector2i = _ledger.progress_counts()
	var out: Array = [{
		"label": COUNT_LABEL,
		"detail": "%d OF %d" % [counts.x, counts.y],
	}]
	for row: Dictionary in Catalogue.ROWS:
		var line: Dictionary = {
			"label": String(row["name"]),
			"detail": String(row["detail"]),
		}
		if _ledger.has(StringName(row["id"])):
			line["icon"] = row["icon"]
		out.append(line)
	return out
