extends SceneTree

## Checks the Linking Cord against a real cartridge cache, on whichever of the
## three is named. Everything here is the reachable half of the mod: the item
## row, the shelf it sits on, the pocket it lands in and the submenu it opens.
##
## The last section RUNS the evolution, against a real save and a real world,
## over the five axes the item has: the plain trade evolution, the one that
## wants a held item, the same one without it, a species with no trade
## evolution at all, and an EVERSTONE. Each also asserts whether the cord was
## spent, since an item consumed by a refusal is the expensive way to be wrong.
##
##   godot --headless --path <pokerecomp> -s tools/linking_cord_probe.gd \
##       -- <cartridge>

const MOD_ID: StringName = &"linking_cord"
const LINKING_CORD: int = 256
const DEPT_STORE_GADGETS: int = 6
const PRICE: int = 2100
const NEW_BARK_GROUP: int = 24
const NEW_BARK_MAP: int = 7
const EVERSTONE: int = 70
const KADABRA: int = 64
const ALAKAZAM: int = 65

## The five axes the cord has, each named by what it proves. The species are
## the cartridge's own numbers and the held items come from its evolution rows.
const CASES: Array[Dictionary] = [
	{"what": "KADABRA, holding nothing", "species": 64, "becomes": 65},
	{"what": "ONIX holding METAL COAT", "species": 95, "held": 0x8F, "becomes": 208},
	{"what": "ONIX holding nothing", "species": 95},
	{"what": "PIKACHU, no trade evolution", "species": 25},
	{"what": "KADABRA holding EVERSTONE", "species": 64, "held": EVERSTONE},
]

## The two boxes, which no axis above covers and which were wrong once. Both
## read the name the Pokemon came in under, so the un-nicknamed row is the one
## that matters: the party list says ALAKAZAM by the time they print, and they
## must still say KADABRA.
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
	## BEFORE the cartridge is opened. `reset()` replaces the shared content
	## overlay, and a `GameData` opened ahead of it holds the one it is replacing,
	## so the mod's own item would be missing from every row this probe reads.
	Gen2ModHost.reset()
	# Either form: a cache directory or a cartridge id. `GameData` answers which
	# of the two an argument is, and fills `id` off the manifest either way, so
	# the host is told the same cartridge whichever was typed.
	var data: GameData = GameData.open_argument(cartridge)
	if data == null:
		print("no cache for %s" % cartridge)
		quit(1)
		return
	var game: StringName = data.id
	var host: Gen2ModHost = Gen2ModHost.instance()
	host.set_target_game(game)
	host.discover()
	host.load_discovered()
	var ok: bool = _loaded(host)
	ok = _item(data) and ok
	ok = _shelf(host, data) and ok
	ok = _pocket(data) and ok
	ok = _evolves(data) and ok
	print("%s: %s" % [game, "ok" if ok else "FAILED"])
	quit(0 if ok else 1)


## The mod is loaded by the production path, not by hand, so a manifest the host
## would refuse is a failure here rather than a surprise in the launcher.
func _loaded(host: Gen2ModHost) -> bool:
	for failure: Dictionary in host.failures():
		print("mod refused: %s" % str(failure))
	for manifest: Gen2ModManifest in host.manifests():
		if manifest.id == MOD_ID:
			return host.failures().is_empty()
	print("%s did not load" % MOD_ID)
	return false


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
	if int(row.get("evolution", {}).get("method", 0)) != RomLayout.EVOLVE_TRADE:
		print("the row does not name the trade method")
		ok = false
	return ok


## The shelf, through the host's own mart entries rather than through the
## registration: the filter is what decides which counter carries the row, and
## a filter that answered everywhere would sell the cord in every town.
func _shelf(host: Gen2ModHost, data: GameData) -> bool:
	var ok: bool = true
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
		ok = false
	return ok


## The pack, with one owned, which is the list the player actually reads.
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


## The USE itself, end to end. Each case opens its own world and save so a
## spent cord or an evolved party cannot leak into the next one.
func _evolves(data: GameData) -> bool:
	var ok: bool = true
	for case: Dictionary in CASES:
		ok = _case(data, case) and ok
	for case: Dictionary in NAME_CASES:
		ok = _names(data, case) and ok
	var trade_evolutions: Array[String] = []
	for species: int in range(1, RomLayout.SPECIES_COUNT + 1):
		for row: Dictionary in data.evolutions(species):
			if int(row.get("method", 0)) != RomLayout.EVOLVE_TRADE:
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


## One USE against its own world and save. `becomes` is 0 for a case that has to
## be refused, and the cord is expected to survive exactly those.
func _case(data: GameData, case: Dictionary) -> bool:
	var species: int = int(case["species"])
	var held: int = int(case.get("held", 0))
	var becomes: int = int(case.get("becomes", 0))
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, NEW_BARK_GROUP, NEW_BARK_MAP, Vector2i.ZERO,
		Gen2WorldState.new({}, {}, {LINKING_CORD: 1}, {})
	)
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

	## `persist` false: a probe never writes a slot on this machine.
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
	## `evolve.asm` adds the max-HP delta rather than refilling, so damage
	## carries across; a species that grew cannot come out with less than it had.
	if save.party[0].hp < before_hp:
		print("%s FAILED: HP fell from %d to %d" % [line, before_hp, save.party[0].hp])
		return false
	## The held item is consumed by the evolution that asked for it, and only by
	## that one. The host zeroes it; this checks that it did.
	if held != 0 and save.party[0].item != 0:
		print("%s FAILED: %s was not consumed" % [
			line, String(data.item(held).get("name", "?")),
		])
		return false
	print("%s, cord spent" % line)
	return true


## What the pack prints, assembled the way `_use_summary` assembles it, and the
## name the party list is left holding. The Pokedex is asserted with them
## because a Pokemon the cord made has to be entered the way one made by a stone
## is; `use_item` writes it onto live state and does not return it, so the read
## is the dex itself.
func _names(data: GameData, case: Dictionary) -> bool:
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, NEW_BARK_GROUP, NEW_BARK_MAP, Vector2i.ZERO,
		Gen2WorldState.new({}, {}, {LINKING_CORD: 1}, {})
	)
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
