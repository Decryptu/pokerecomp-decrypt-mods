extends SceneTree

const Staging: GDScript = preload("staging.gd")

const MOD_ID: StringName = &"randomizer"
const DEFAULT_GAME: StringName = &"crystal"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	Gen2ModHost.reset()
	var data: GameData = GameData.open(StringName(args[0]) if args.size() > 0 else DEFAULT_GAME)
	if data == null:
		print("no cache for %s" % (args[0] if args.size() > 0 else String(DEFAULT_GAME)))
		quit(1)
		return
	var host: Gen2ModHost = Gen2ModHost.instance()
	if not Staging.mod_loaded(host, data, MOD_ID) or not host.save_lifecycle_ids().has(MOD_ID):
		print("randomizer save lifecycle not registered: %s" % str(host.failures()))
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
	var snapshotted: bool = int(created_data.get("algorithm", -1)) == 2 \
		and created_data.get("settings", null) is Dictionary
	print("same save twice is byte-identical: %s" % ("yes" if same else "NO"))
	print("two saves keep different runs: %s" % ("yes" if differ else "NO"))
	print("legacy save remains vanilla: %s" % ("yes" if legacy_clean else "NO"))
	print("new save snapshots compact inputs: %s" % ("yes" if snapshotted else "NO"))
	host.deactivate_save()
	quit(0 if same and differ and legacy_clean and snapshotted else 1)


func _snapshot(seed_value: int) -> Dictionary:
	return {
		"algorithm": 2,
		"settings": {
			"seed": seed_value,
			"stats": true, "types": true, "learnsets": true,
			"evolutions": true, "moves": true, "trainers": true,
			"encounters": true, "specials": true, "starters": true,
			"trades": true, "items": true, "badges": true, "shops": true,
		},
	}


func _fingerprint(data: GameData) -> String:
	var catalog: Gen2WorldCatalog = data.catalog()
	var starters: Array = catalog.rows(Gen2WorldCatalog.KIND_STARTER)
	return JSON.stringify({
		"species": data.species(1),
		"encounter": _first_grass(data),
		"fishing": data.world_fishing_group(1),
		"treemon": data.treemon_set(1),
		"starter": starters[0] if not starters.is_empty() else {},
	})


func _first_grass(data: GameData) -> Dictionary:
	for map: Gen2WorldMap in data.world_maps():
		var row: Dictionary = data.world_encounter(&"grass", map.group, map.number)
		if not row.is_empty():
			return row
	return {}
