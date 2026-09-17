extends SceneTree

## Checks the Linking Cord against a real cartridge cache, on whichever of the
## six is named.

const Staging: GDScript = preload("staging.gd")

const MOD_ID: StringName = &"linking_cord"
const LINKING_CORD: int = 256
const DEPT_STORE_GADGETS: int = 6
const CELADON_STONE_COUNTER: Vector2i = Vector2i(125, 1)
const GEN1_MAP_COUNT: int = 256
const FACINGS: Array[int] = [
	Gen2WorldSprite.FACING_DOWN, Gen2WorldSprite.FACING_UP,
	Gen2WorldSprite.FACING_LEFT, Gen2WorldSprite.FACING_RIGHT,
]
const PRICE: int = 2100
const NEW_BARK: Vector2i = Vector2i(24, 7)
const PALLET_TOWN: Vector2i = Vector2i(0, 0)
const EVERSTONE: int = 70
const KADABRA: int = 64
const ALAKAZAM: int = 65

const CASES: Array[Dictionary] = [
	{"what": "KADABRA, holding nothing", "species": 64, "becomes": 65},
	{"what": "HAUNTER, holding nothing", "species": 93, "becomes": 94},
	{"what": "PIKACHU, no trade evolution", "species": 25},
]
## Held items arrive with Generation II, and so do the six that ask for one.
const GEN2_CASES: Array[Dictionary] = [
	{"what": "ONIX holding METAL COAT", "species": 95, "held": 0x8F, "becomes": 208},
	{"what": "ONIX holding nothing", "species": 95},
	{"what": "KADABRA holding EVERSTONE", "species": 64, "held": EVERSTONE},
]

const NAME_CASES: Array[Dictionary] = [
	{
		"what": "un-nicknamed KADABRA",
		"nickname": "",
		"boxes": "What? KADABRA is evolving! " \
			+ "Congratulations! Your KADABRA evolved into ALAKAZAM!",
		"row": "ALAKAZAM",
	},
	{
		"what": "KADABRA nicknamed SPOONY",
		"nickname": "SPOONY",
		"boxes": "What? SPOONY is evolving! " \
			+ "Congratulations! Your SPOONY evolved into ALAKAZAM!",
		"row": "SPOONY",
	},
]


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var cartridge: String = args[0] if not args.is_empty() else "crystal"
	Gen2ModHost.reset()
	var data: GameData = GameData.open_argument(cartridge)
	if data == null:
		print("no cache for %s" % cartridge)
		quit(1)
		return
	var game: StringName = data.id
	var host: Gen2ModHost = Gen2ModHost.instance()
	var ok: bool = Staging.mod_loaded(host, data, MOD_ID)
	ok = _item(data) and ok
	ok = _shelf(host, data) and ok
	ok = _pocket(data) and ok
	ok = _evolves(data) and ok
	print("%s: %s" % [game, "ok" if ok else "FAILED"])
	quit(0 if ok else 1)


func _item(data: GameData) -> bool:
	var row: Dictionary = data.item(LINKING_CORD)
	if row.is_empty():
		print("item %d is not defined" % LINKING_CORD)
		return false
	var ok: bool = true
	for field: String in ["name", "price", "pocket", "field_menu", "permissions"]:
		print("  %-12s %s" % [field, str(row.get(field, "-"))])
	print("  description  %s" % String(row.get("description", "")).replace("\n", " / "))
	print("  evolution    %s" % str(row.get("evolution", {})))
	if int(row.get("price", 0)) != PRICE:
		print("price is not %d" % PRICE)
		ok = false
	if int(row.get("field_menu", 0)) != Gen2WorldPack.ITEMMENU_PARTY:
		print("field menu is not ITEMMENU_PARTY, so USE would not open the party list")
		ok = false
	if int(row.get("evolution", {}).get("method", 0)) != Gen2Layout.EVOLVE_TRADE:
		print("the row does not name the trade method")
		ok = false
	return ok


func _shelf(host: Gen2ModHost, data: GameData) -> bool:
	if data.generation == RomRegistry.GEN1:
		return _gen1_shelf(host, data)
	var sold_at: Array[int] = []
	for row: Dictionary in data.catalog().rows(Gen2WorldCatalog.KIND_SHOP):
		var mart: int = int(row.get("mart", -1))
		var entries: Array = host.mart_entries({
			"mart_id": mart,
			"dialog_id": int(row.get("dialog", 0)),
			"variant": int(row.get("variant", 0)),
		})
		for entry: Dictionary in entries:
			if int(entry.get("item", 0)) == LINKING_CORD and not sold_at.has(mart):
				sold_at.append(mart)
	print("  sold at marts %s" % str(sold_at))
	if sold_at != [DEPT_STORE_GADGETS]:
		print("the cord is not on mart %d alone" % DEPT_STORE_GADGETS)
		return false
	return true


## Every Generation I counter is walked up to and asked, the way the game asks,
## so the shelf is judged on the mart the host resolves and not on a guess at it.
func _gen1_shelf(host: Gen2ModHost, data: GameData) -> bool:
	var sold_at: Array[Vector2i] = []
	var counters: int = 0
	for number: int in GEN1_MAP_COUNT:
		var map: Gen2WorldMap = data.world_map(0, number)
		if map == null:
			continue
		for event: Dictionary in map.events.get("objects", []):
			var text_id: int = int(event.get("text", 0))
			if not map.text_at(text_id).has("items"):
				continue
			var mart: Dictionary = _counter_mart(data, number, event)
			if mart.is_empty():
				print("  no mart request at map 0,%d text %d" % [number, text_id])
				return false
			counters += 1
			for entry: Dictionary in host.mart_entries(mart):
				if int(entry.get("item", 0)) == LINKING_CORD:
					sold_at.append(Vector2i(number, text_id))
	print("  sold at %s of %d counters, as map number and text" % [str(sold_at), counters])
	if sold_at != [CELADON_STONE_COUNTER]:
		print("the cord is not on Celadon Dept Store 4F's counter alone")
		return false
	return true


## The mart the clerk at [param event] resolves when faced across the counter,
## or from the next cell where there is none, from whichever side answers.
func _counter_mart(data: GameData, number: int, event: Dictionary) -> Dictionary:
	var clerk := Vector2i(int(event.get("x", 0)), int(event.get("y", 0)))
	for facing: int in FACINGS:
		for distance: int in [2, 1]:
			var cell: Vector2i = clerk - Gen2WorldAPI.SIGHT_STEPS[facing] * distance
			var world: Gen2WorldAPI = Gen2WorldAPI.open(
				data, 0, number, cell, Gen2WorldState.new({}, {}, {}, {})
			)
			if world == null:
				return {}
			world.player_facing = facing
			world.interact()
			var pending: Dictionary = world.pending_runtime_request()
			if StringName(pending.get("kind", &"")) != &"mart_requested":
				continue
			var resolved: Dictionary = Gen2WorldHost.resolve_runtime_request(world, pending)
			return resolved.get("data", {}).get("mart", {})
	return {}


func _pocket(data: GameData) -> bool:
	var state := Gen2WorldState.new()
	state.apply_changes({}, {}, {"items": {LINKING_CORD: 1}})
	var ok: bool = false
	for pocket: Dictionary in Gen2WorldPack.build(data, state):
		for item: Dictionary in pocket.get("items", []):
			if int(item.get("item", 0)) != LINKING_CORD:
				continue
			print("  pocket %s row %s" % [String(pocket.get("name", "")), str(item)])
			ok = int(pocket.get("pocket", 0)) == Gen2WorldPack.TYPE_ITEM
	if not ok:
		print("the cord is not in the Items pocket")
		return false
	var actions: Array = []
	for entry: Dictionary in Gen2WorldPack.item_submenu(data, LINKING_CORD):
		actions.append(String(entry.get("action", "")))
	print("  submenu %s" % str(actions))
	if not actions.has("use"):
		print("the submenu has no USE")
		return false
	return true


func _evolves(data: GameData) -> bool:
	var ok: bool = true
	var cases: Array[Dictionary] = CASES.duplicate()
	if data.generation != RomRegistry.GEN1:
		cases.append_array(GEN2_CASES)
	for case: Dictionary in cases:
		ok = _case(data, case) and ok
	for case: Dictionary in NAME_CASES:
		ok = _names(data, case) and ok
	var trade_evolutions: Array[String] = []
	for species: int in range(1, data.species_count() + 1):
		for row: Dictionary in data.evolutions(species):
			if int(row.get("method", 0)) != Gen2Layout.EVOLVE_TRADE:
				continue
			var held: int = int(row.get("parameter", Gen2Evolution.TRADE_NO_ITEM))
			trade_evolutions.append("%s -> %s%s" % [
				String(data.species(species).get("name", "?")),
				String(data.species(int(row.get("target", 0))).get("name", "?")),
				"" if held == Gen2Evolution.TRADE_NO_ITEM \
					else " holding %s" % String(data.item(held).get("name", "?")),
			])
	print("  %d trade evolutions: %s" % [trade_evolutions.size(), ", ".join(trade_evolutions)])
	return ok


func _case(data: GameData, case: Dictionary) -> bool:
	var species: int = int(case["species"])
	var held: int = int(case.get("held", 0))
	var becomes: int = int(case.get("becomes", 0))
	var world: Gen2WorldAPI = _open(data)
	var save: Gen2SaveData = Gen2SaveStore.create_development_save(data, 0)
	if world == null or save == null:
		print("  no world or save for %s" % String(case["what"]))
		return false
	save.world = world.snapshot()
	var mon: Gen2SaveMon = Gen2SaveBattleAdapter.from_battle_mon(
		Gen2BattleMon.create(data, species, 30, data.moves_at_level(species, 30))
	)
	mon.item = held
	save.party[0] = mon
	var before_hp: int = mon.hp

	var result: Dictionary = Gen2WorldPartyHost.use_item(world, save, LINKING_CORD, 0, false)

	var evolved: int = save.party[0].species
	var kept: int = world.state.item_quantity(LINKING_CORD)
	var line: String = "  %-34s %s" % [String(case["what"]), _outcome(data, result, evolved)]
	if becomes == 0:
		if bool(result.get("ok", false)) or evolved != species or kept != 1:
			print("%s FAILED: expected a refusal that spends nothing" % line)
			return false
		print("%s, cord kept" % line)
		return true
	if not bool(result.get("ok", false)) or evolved != becomes:
		print("%s FAILED: expected %s" % [line, String(data.species(becomes).get("name", "?"))])
		return false
	if kept != 0:
		print("%s FAILED: the cord was not spent" % line)
		return false
	if save.party[0].hp < before_hp:
		print("%s FAILED: HP fell from %d to %d" % [line, before_hp, save.party[0].hp])
		return false
	if held != 0 and save.party[0].item != 0:
		print("%s FAILED: %s was not consumed" % [
			line, String(data.item(held).get("name", "?")),
		])
		return false
	print("%s, cord spent" % line)
	return true


func _names(data: GameData, case: Dictionary) -> bool:
	var world: Gen2WorldAPI = _open(data)
	var save: Gen2SaveData = Gen2SaveStore.create_development_save(data, 0)
	if world == null or save == null:
		print("  no world or save for %s" % String(case["what"]))
		return false
	save.world = world.snapshot()
	var mon: Gen2SaveMon = Gen2SaveBattleAdapter.from_battle_mon(
		Gen2BattleMon.create(data, KADABRA, 30, data.moves_at_level(KADABRA, 30))
	)
	mon.nickname = String(case["nickname"])
	save.party[0] = mon

	var result: Dictionary = Gen2WorldPartyHost.use_item(world, save, LINKING_CORD, 0, false)

	if not bool(result.get("ok", false)):
		print("  %-34s FAILED: refused (%s)" % [
			String(case["what"]), String(result.get("reason", "?")),
		])
		return false
	var evolving: String = String(result.get("evolving_name", ""))
	var boxes: String = "%s %s" % [
		Gen2Evolution.evolving_text(evolving),
		Gen2Evolution.evolved_text(evolving, String(
			data.species(int(result.get("new_species", 0))).get("name", "")
		)),
	]
	var line: String = "  %-34s %s" % [String(case["what"]), boxes]
	if boxes != String(case["boxes"]):
		print("%s\n%swanted %s" % [line, " ".repeat(37), String(case["boxes"])])
		return false
	if save.party[0].nickname != String(case["row"]):
		print("%s FAILED: the party row says %s, wanted %s" % [
			line, save.party[0].nickname, String(case["row"]),
		])
		return false
	if not world.state.has_caught_species(ALAKAZAM):
		print("%s FAILED: ALAKAZAM did not reach the Pokedex" % line)
		return false
	print("%s, row %s" % [line, save.party[0].nickname])
	return true


func _outcome(data: GameData, result: Dictionary, species: int) -> String:
	if bool(result.get("ok", false)):
		return "-> %s" % String(data.species(species).get("name", "?"))
	return "refused (%s)" % String(result.get("reason", "?"))


func _open(data: GameData) -> Gen2WorldAPI:
	var home: Vector2i = PALLET_TOWN if data.generation == RomRegistry.GEN1 else NEW_BARK
	return Gen2WorldAPI.open(
		data, home.x, home.y, Vector2i.ZERO, Gen2WorldState.new({}, {}, {LINKING_CORD: 1}, {})
	)
