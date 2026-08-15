extends RefCounted

## Registers the settings, reads the cartridge the host is about to play, and
## patches it. Nothing here is a scene node and nothing here reads world or
## battle state: `plan.gd` decides every value and this file only carries them
## to the host's own patch calls.
##
## The cartridge is known at this point because the host reloads every mod when
## one is chosen, with `target_game()` already set. At the launcher's own boot
## no cartridge is selected, so the settings register and nothing is patched,
## which is exactly what the launcher wants while the player is still choosing.
##
## The host keeps this object for as long as the mod is loaded, so connecting
## `option_changed` to it is safe and it holds no reference to itself.

const Options := preload("options.gd")
const Plan := preload("plan.gd")

## The kinds patched by number, in the order they are applied.
const NUMBERED_KINDS: Array[StringName] = [
	Gen2ContentOverlay.KIND_SPECIES,
	Gen2ContentOverlay.KIND_MOVE,
	Gen2ContentOverlay.KIND_TRAINER,
]

var _host: Gen2ModHost = null
var _id: StringName = &""
## The cartridge as it shipped, gathered once. A rebuild starts from this, so a
## seed always means the same thing however many times a setting was moved.
var _world: Dictionary = {}
## kind to the entries this mod is currently patching, so a setting turned OFF
## puts its rows back rather than leaving the last seed's values behind.
var _applied: Dictionary = {}


func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	_host = host
	_id = manifest.id
	Options.register(host, manifest.id)
	host.option_changed.connect(_on_option_changed)
	_apply()


## Rebuilds when one of this mod's own settings moves. A patch is what the
## overlay holds and a read goes through it live, so the tables change under a
## running game at once; a Pokemon already in the party keeps the stats it was
## created with, which is the cartridge's own rule and not this mod's.
func _on_option_changed(id: StringName, key: StringName, _value: Variant) -> void:
	if id != _id or not Options.owns(key):
		return
	_apply()


func _apply() -> void:
	if _world.is_empty():
		var game: StringName = _host.target_game()
		if String(game).is_empty():
			return
		var data: GameData = GameData.open(game)
		if data == null:
			return
		_world = Plan.gather(data)
	var patches: Dictionary = Plan.build(_world, Options.settings(_host))
	for kind: StringName in NUMBERED_KINDS:
		_carry(kind, patches[kind], _patch_numbered)
	_carry(Gen2ContentOverlay.KIND_ENCOUNTER,
		patches[Gen2ContentOverlay.KIND_ENCOUNTER], _patch_encounter)
	_carry(Gen2ContentOverlay.KIND_FISHING,
		patches[Gen2ContentOverlay.KIND_FISHING], _patch_fishing)


## One kind's entries, applied in the order the plan listed them, and then the
## entries the last plan had and this one does not, put back to the cartridge's
## own values. A patch is what the overlay holds, so a row is restored by
## patching it with what it was rather than by dropping anything.
func _carry(kind: StringName, entries: Array, patch: Callable) -> void:
	var covered: Dictionary = {}
	for entry: Dictionary in entries:
		covered[_address(kind, entry)] = true
		patch.call(kind, entry, entry["fields"])
	for entry: Dictionary in (_applied.get(kind, []) as Array):
		if covered.has(_address(kind, entry)):
			continue
		var original: Dictionary = Plan.original_fields(
			_world, kind, _address(kind, entry)
		)
		if not original.is_empty():
			patch.call(kind, entry, original)
	_applied[kind] = entries


## Where an entry is patched, which is also where its baseline is kept: a
## content number for the three numbered kinds, the host's own packed table
## coordinate for an encounter.
func _address(kind: StringName, entry: Dictionary) -> int:
	return int(entry.get("at", entry["number"])) \
		if kind == Gen2ContentOverlay.KIND_ENCOUNTER else int(entry["number"])


func _patch_numbered(kind: StringName, entry: Dictionary, fields: Dictionary) -> void:
	_host.patch_content(kind, _id, int(entry["number"]), fields)


func _patch_encounter(_kind: StringName, entry: Dictionary, fields: Dictionary) -> void:
	_host.patch_encounter(
		_id, StringName(entry["method"]), int(entry["group"]), int(entry["number"]), fields
	)


func _patch_fishing(_kind: StringName, entry: Dictionary, fields: Dictionary) -> void:
	_host.patch_fishing_group(_id, int(entry["number"]), fields)
