extends RefCounted

## Registers the settings, reads the cartridge the host is about to play, and
## patches it. Nothing here is a scene node and nothing here reads world or
## battle state: `plan.gd` decides every value and this file only carries them
## to [method Gen2ModHost.patch_content].
##
## The cartridge is known at this point because the host reloads every mod when
## one is chosen, with `target_game()` already set. At the launcher's own boot
## no cartridge is selected, so the settings register and nothing is patched,
## which is exactly what the launcher wants while the player is still choosing.

const Options := preload("options.gd")
const Plan := preload("plan.gd")

## The host builds the entry object, calls `register` and drops it, so a mod
## with nothing but a signal connection left is collected before the first
## change arrives. Holding the instance here is what keeps it alive; a reload
## runs `register` again and replaces it, so exactly one is ever kept.
static var _live: RefCounted = null

var _host: Gen2ModHost = null
var _id: StringName = &""
## The cartridge as it shipped, gathered once. A rebuild starts from this, so a
## seed always means the same thing however many times a setting was moved.
var _world: Dictionary = {}
## kind to the numbers this mod is currently patching, so a setting turned OFF
## puts its rows back rather than leaving the last seed's values behind.
var _applied: Dictionary = {}


func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	_host = host
	_id = manifest.id
	Options.register(host, manifest.id)
	_live = self
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
	for kind: StringName in [
		Gen2ContentOverlay.KIND_SPECIES,
		Gen2ContentOverlay.KIND_MOVE,
		Gen2ContentOverlay.KIND_TRAINER,
	]:
		_apply_kind(kind, patches[kind])


## One kind's patches, in ascending number order.
##
## The order is not the Dictionary's, and that matters: two machines have to
## agree on the game, and a plan walked in whatever order the keys came out in
## is a plan that agrees by luck.
func _apply_kind(kind: StringName, fields: Dictionary) -> void:
	var numbers: Array[int] = []
	for number: int in fields:
		numbers.append(number)
	numbers.sort()
	for number: int in numbers:
		_host.patch_content(kind, _id, number, fields[number])
	for number: int in (_applied.get(kind, [] as Array[int]) as Array[int]):
		if fields.has(number):
			continue
		var original: Dictionary = Plan.original_fields(_world, kind, number)
		if not original.is_empty():
			_host.patch_content(kind, _id, number, original)
	_applied[kind] = numbers
