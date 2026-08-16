extends SceneTree

## Exercises the randomizer through the real host save lifecycle. Two saves
## carry different compact inputs, a legacy save carries none, and reactivating
## one slot must rebuild its byte-identical view without leaking another's run.

const MOD_ID: StringName = &"randomizer"


func _initialize() -> void:
	Gen2ModHost.reset()
	var host: Gen2ModHost = Gen2ModHost.instance()
	host.set_target_game(&"crystal")
	host.discover()
	host.load_discovered()
	if not host.save_lifecycle_ids().has(MOD_ID):
		print("randomizer save lifecycle not registered: %s" % host.failures())
		quit(1)
		return
	var data: GameData = GameData.open(&"crystal")
	if data == null:
		print("no Crystal cache")
		quit(1)
		return
	var vanilla: String = _fingerprint(data)
	var first := Gen2SaveData.new()
	var second := Gen2SaveData.new()
	var legacy := Gen2SaveData.new()
	first.set_mod_data(MOD_ID, _snapshot(1234))
	second.set_mod_data(MOD_ID, _snapshot(5678))

	host.activate_save(first)
	var first_once: String = _fingerprint(data)
	host.activate_save(second)
	var second_once: String = _fingerprint(data)
	host.activate_save(first)
	var first_again: String = _fingerprint(data)
	host.activate_save(legacy)
	var legacy_view: String = _fingerprint(data)

	var created := Gen2SaveData.new()
	host.created_save(created)
	var created_data: Dictionary = created.mod_data(MOD_ID)
	var same: bool = first_once == first_again
	var differ: bool = first_once != second_once
	var legacy_clean: bool = legacy_view == vanilla
	var snapshotted: bool = int(created_data.get("algorithm", -1)) == 1 \
		and created_data.get("settings", null) is Dictionary
	print("same save twice is byte-identical: %s" % ("yes" if same else "NO"))
	print("two saves keep different runs: %s" % ("yes" if differ else "NO"))
	print("legacy save remains vanilla: %s" % ("yes" if legacy_clean else "NO"))
	print("new save snapshots compact inputs: %s" % ("yes" if snapshotted else "NO"))
	host.deactivate_save()
	quit(0 if same and differ and legacy_clean and snapshotted else 1)


func _snapshot(seed_value: int) -> Dictionary:
	return {
		"algorithm": 1,
		"settings": {
			"seed": seed_value,
			"stats": true, "types": true, "learnsets": true,
			"evolutions": true, "moves": true, "trainers": true,
			"encounters": true, "specials": true,
		},
	}


func _fingerprint(data: GameData) -> String:
	var catalog: Gen2WorldCatalog = data.catalog()
	var starters: Array = catalog.rows(Gen2WorldCatalog.KIND_STARTER)
	return JSON.stringify({
		"species": data.species(1),
		"encounter": data.world_encounter(&"grass", 1, 12),
		"treemon": data.treemon_set(1),
		"starter": starters[0] if not starters.is_empty() else {},
	})
