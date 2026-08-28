extends RefCounted

## Registers the settings and a save lifecycle.

const Options := preload("options.gd")
const Plan := preload("plan.gd")
const ALGORITHM_VERSION: int = 2
const SAVE_ALGORITHM: String = "algorithm"
const SAVE_SETTINGS: String = "settings"

const NUMBERED_KINDS: Array[StringName] = [
	Gen2ContentOverlay.KIND_SPECIES,
	Gen2ContentOverlay.KIND_MOVE,
	Gen2ContentOverlay.KIND_TRAINER,
]

var _host: Gen2ModHost = null
var _id: StringName = &""
var _manifest: Gen2ModManifest = null
var _world: Dictionary = {}
var _data: GameData = null


func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	_host = host
	_id = manifest.id
	_manifest = manifest
	Options.register(host, manifest.id)
	host.register_save_lifecycle(manifest, self)


func save_created(save: Gen2SaveData) -> void:
	_host.write_save_data(_manifest, save, {
		SAVE_ALGORITHM: ALGORITHM_VERSION,
		SAVE_SETTINGS: Options.settings(_host),
	})


func save_activated(save: Gen2SaveData) -> void:
	if save == null:
		_apply(Options.settings(_host))
		return
	var snapshot: Dictionary = _host.read_save_data(_manifest, save)
	if int(snapshot.get(SAVE_ALGORITHM, -1)) != ALGORITHM_VERSION \
		or not snapshot.get(SAVE_SETTINGS, null) is Dictionary:
		return
	_apply(snapshot[SAVE_SETTINGS])


func save_deactivated() -> void:
	pass


func _apply(settings: Dictionary) -> void:
	if _world.is_empty():
		var game: StringName = _host.target_game()
		if String(game).is_empty():
			return
		_data = GameData.open(game)
		if _data == null:
			return
		_world = Plan.gather(_data)
	var validate := func(candidate: Dictionary) -> Dictionary:
		return _host.validate_placement(_data, candidate)
	var patches: Dictionary = Plan.build(_world, settings, validate)
	for kind: StringName in NUMBERED_KINDS:
		_apply_entries(kind, patches[kind], _patch_numbered)
	_apply_entries(Gen2ContentOverlay.KIND_ENCOUNTER,
		patches[Gen2ContentOverlay.KIND_ENCOUNTER], _patch_encounter)
	_apply_entries(Gen2ContentOverlay.KIND_FISHING,
		patches[Gen2ContentOverlay.KIND_FISHING], _patch_fishing)
	for kind: StringName in [
		Gen2ContentOverlay.KIND_TREEMON,
		Gen2ContentOverlay.KIND_BUG_CONTEST,
		Gen2ContentOverlay.KIND_ROAMING,
		Gen2ContentOverlay.KIND_FISHING_TIME,
		Gen2ContentOverlay.KIND_CHECK,
	]:
		_apply_entries(kind, patches[kind], _patch_table)


func _apply_entries(kind: StringName, entries: Array, patch: Callable) -> void:
	for entry: Dictionary in entries:
		patch.call(kind, entry, entry["fields"])


func _patch_numbered(kind: StringName, entry: Dictionary, fields: Dictionary) -> void:
	_host.patch_content(kind, _id, int(entry["number"]), fields)


func _patch_encounter(_kind: StringName, entry: Dictionary, fields: Dictionary) -> void:
	_host.patch_encounter(
		_id, StringName(entry["method"]), int(entry["group"]), int(entry["number"]), fields
	)


func _patch_fishing(_kind: StringName, entry: Dictionary, fields: Dictionary) -> void:
	_host.patch_fishing_group(_id, int(entry["number"]), fields)


func _patch_table(kind: StringName, entry: Dictionary, fields: Dictionary) -> void:
	var number: int = int(entry["number"])
	match kind:
		Gen2ContentOverlay.KIND_TREEMON:
			_host.patch_treemon_set(_id, number, fields)
		Gen2ContentOverlay.KIND_BUG_CONTEST:
			_host.patch_bug_contest_mon(_id, number, fields)
		Gen2ContentOverlay.KIND_ROAMING:
			_host.patch_roaming_mon(_id, number, fields)
		Gen2ContentOverlay.KIND_FISHING_TIME:
			_host.patch_fishing_time_group(_id, number, fields)
		Gen2ContentOverlay.KIND_CHECK:
			_host.patch_check(_id, number, fields)
