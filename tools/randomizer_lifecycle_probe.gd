extends SceneTree

const Staging: GDScript = preload("staging.gd")

const MOD_ID: StringName = &"randomizer"
const DEFAULT_GAME: StringName = &"crystal"
const ALGORITHM: int = 3
const SEEDS: Array[int] = [1234, 5678]


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	Gen2ModHost.reset()
	var data: GameData = GameData.open_argument(args[0] if args.size() > 0 else String(DEFAULT_GAME))
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
	var saves: Array = _created(host)
	var first: Gen2SaveData = saves[0]
	var tampered: Gen2SaveData = _tampered(first)
	var older := Gen2SaveData.new()
	older.set_mod_data(MOD_ID, {"algorithm": ALGORITHM - 1, "settings": _snapshot_settings(first)})

	host.activate_save(first)
	var first_once: String = _fingerprint(data)
	host.activate_save(saves[1])
	var second_once: String = _fingerprint(data)
	host.activate_save(first)
	var first_again: String = _fingerprint(data)
	host.activate_save(Gen2SaveData.new())
	var legacy_view: String = _fingerprint(data)
	host.activate_save(older)
	var older_view: String = _fingerprint(data)
	host.activate_save(tampered)
	var stored: bool = _plays_stored(data, tampered)
	host.deactivate_save()

	var passed: bool = true
	for check: Array in [
		["same save twice is byte-identical", first_once == first_again],
		["two saves keep different runs", first_once != second_once],
		["a save with no snapshot remains vanilla", legacy_view == vanilla],
		["a save from the previous algorithm remains vanilla", older_view == vanilla],
		["a new save snapshots its settings and placement", _snapshotted(first)],
		["a save plays the placement it stored", stored],
	]:
		print("%s  %s" % ["ok  " if check[1] else "FAIL", check[0]])
		passed = passed and bool(check[1])
	quit(0 if passed else 1)


## One save per seed, made through the host with the installation set to that
## seed and given back after.
func _created(host: Gen2ModHost) -> Array:
	var before: Variant = host.option(MOD_ID, &"seed")
	var out: Array = []
	for seed_value: int in SEEDS:
		host.set_option(MOD_ID, &"seed", seed_value)
		var save := Gen2SaveData.new()
		var start: int = Time.get_ticks_msec()
		host.created_save(save)
		print("seed %04d  save created in %d ms, snapshot %d bytes" % [
			seed_value, Time.get_ticks_msec() - start, JSON.stringify(save.mod_data(MOD_ID)).length(),
		])
		out.append(save)
	if before != null:
		host.set_option(MOD_ID, &"seed", before)
	return out


func _snapshot_settings(save: Gen2SaveData) -> Dictionary:
	return save.mod_data(MOD_ID).get("settings", {})


func _snapshotted(save: Gen2SaveData) -> bool:
	var snapshot: Dictionary = save.mod_data(MOD_ID)
	var placement: Variant = snapshot.get("placement", null)
	return int(snapshot.get("algorithm", -1)) == ALGORITHM \
		and snapshot.get("settings", null) is Dictionary \
		and placement is Dictionary \
		and not ((placement as Dictionary).get("items", []) as Array).is_empty() \
		and not ((placement as Dictionary).get("badges", []) as Array).is_empty()


## [param save]'s snapshot through JSON, numbers as floats the way a save file
## hands them back, with the first two differing items of its stored placement
## exchanged: a placement no fill of this host would answer.
func _tampered(save: Gen2SaveData) -> Gen2SaveData:
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(save.mod_data(MOD_ID)))
	var items: Array = (snapshot["placement"] as Dictionary)["items"]
	for at: int in range(3, items.size() - 2, 3):
		if int(items[at + 1]) != int(items[1]):
			var held: Variant = items[1]
			items[1] = items[at + 1]
			items[at + 1] = held
			break
	var out := Gen2SaveData.new()
	out.set_mod_data(MOD_ID, snapshot)
	return out


func _plays_stored(data: GameData, save: Gen2SaveData) -> bool:
	var items: Array = (save.mod_data(MOD_ID)["placement"] as Dictionary)["items"]
	var catalog: Gen2WorldCatalog = data.catalog()
	for at: int in range(0, items.size() - 2, 3):
		if int(catalog.check(int(items[at])).get("item", -1)) != int(items[at + 1]):
			return false
	return not items.is_empty()


func _fingerprint(data: GameData) -> String:
	var catalog: Gen2WorldCatalog = data.catalog()
	var starters: Array = catalog.rows(Gen2WorldCatalog.KIND_STARTER)
	return JSON.stringify({
		"species": data.species(1),
		"encounter": _first_grass(data),
		"fishing": data.world_fishing_group(1),
		"treemon": data.treemon_set(1),
		"starter": starters[0] if not starters.is_empty() else {},
		"items": _field_of(catalog, Gen2WorldCatalog.KIND_ITEM, "item"),
		"badges": _field_of(catalog, Gen2WorldCatalog.KIND_BADGE, "badge"),
	})


func _field_of(catalog: Gen2WorldCatalog, kind: StringName, field: String) -> Array:
	var out: Array = []
	for row: Dictionary in catalog.rows(kind):
		out.append(int(row.get(field, 0)))
	return out


func _first_grass(data: GameData) -> Dictionary:
	for map: Gen2WorldMap in data.world_maps():
		var row: Dictionary = data.world_encounter(&"grass", map.group, map.number)
		if not row.is_empty():
			return row
	return {}
