extends RefCounted

const Options := preload("options.gd")
const Placement := preload("placement.gd")
const Plan := preload("plan.gd")
const ALGORITHM_VERSION: int = 3
const SAVE_ALGORITHM: String = "algorithm"
const SAVE_SETTINGS: String = "settings"
const SAVE_PLACEMENT: String = "placement"

const NUMBERED_KINDS: Array[StringName] = [
	Gen2ContentOverlay.KIND_SPECIES,
	Gen2ContentOverlay.KIND_MOVE,
	Gen2ContentOverlay.KIND_TRAINER,
]

var _host: Gen2ModHost = null
var _id: StringName = &""
var _manifest: PokeModManifest = null
var _world: Dictionary = {}
var _data: GameData = null


func register(host: Gen2ModHost, manifest: PokeModManifest) -> void:
	_host = host
	_id = manifest.id
	_manifest = manifest
	Options.register(host, manifest.id)
	host.register_save_lifecycle(manifest, self)


## The item and badge placement is resolved here and saved beside the settings,
## so a later host whose proof answers differently cannot move a run in progress.
func save_created(save: Gen2SaveData) -> void:
	var settings: Dictionary = Options.settings(_host)
	if not _gathered_for(_host.target_game()):
		return
	_host.write_save_data(_manifest, save, {
		SAVE_ALGORITHM: ALGORITHM_VERSION,
		SAVE_SETTINGS: settings,
		SAVE_PLACEMENT: Placement.packed(_resolved(settings)),
	})


func save_activated(save: Gen2SaveData) -> void:
	if save == null:
		var settings: Dictionary = Options.settings(_host)
		if _gathered_for(_host.target_game()):
			_apply(settings, _resolved(settings))
		return
	var snapshot: Dictionary = _host.read_save_data(_manifest, save)
	if int(snapshot.get(SAVE_ALGORITHM, -1)) != ALGORITHM_VERSION \
		or not snapshot.get(SAVE_SETTINGS, null) is Dictionary \
		or not snapshot.get(SAVE_PLACEMENT, null) is Dictionary \
		or not _gathered_for(_host.target_game()):
		return
	_apply(snapshot[SAVE_SETTINGS], Placement.unpacked(snapshot[SAVE_PLACEMENT]))


func save_deactivated() -> void:
	pass


## The fill answers a placement that finishes by construction; the host's proof
## is the assertion, and a fill that ran out of sites or a placement the proof
## rejects is said rather than hidden.
func _resolved(settings: Dictionary) -> Dictionary:
	var reach := func(patches: Dictionary, held: Dictionary) -> Array:
		return _host.reachable_checks(_data, patches, held)["reached"]
	var resolved: Dictionary = Placement.resolve(_world, settings, reach)
	var seed_text: String = Options.seed_text(int(settings.get("seed", 0)))
	for category: String in resolved["unplaced"]:
		push_warning("Randomizer seed %s: no %s fill finished on %s, so they stay vanilla" % [
			seed_text, category, String(_data.id),
		])
	var verdict: Dictionary = _host.validate_placement(_data, resolved["checks"])
	if not bool(verdict.get("ok", false)):
		push_warning("Randomizer seed %s: the host rejects the placement on %s: %s" % [
			seed_text, String(_data.id), str(verdict.get("missing", verdict)),
		])
	return resolved["checks"]


func _apply(settings: Dictionary, placement: Dictionary) -> void:
	var patches: Dictionary = Plan.build(_world, settings, placement)
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


## The cartridge's own tables, read once per cartridge: a plan built from another
## game's rows would patch this one with that game's numbers.
func _gathered_for(game: StringName) -> bool:
	if String(game).is_empty():
		return false
	if _data != null and _data.id == game and not _world.is_empty():
		return true
	_data = GameData.open(game)
	_world = Plan.gather(_data) if _data != null else {}
	return not _world.is_empty()


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
