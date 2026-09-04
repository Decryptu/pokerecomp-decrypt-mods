extends SceneTree

## Checks the Shiny Charm against a real cartridge cache, on whichever of the
## three is named.

const MOD_ID: StringName = &"shiny_charm"
const SHINY_CHARM: int = 257
const ROLLS: int = 3
const VANILLA_ODDS: int = 8192
const DEFAULT_WILDS: int = 240000
const MINIMUM_ARM: int = VANILLA_ODDS * 8
const RATIO_BAND := Vector2(2.0, 4.0)
const SPECIES: int = 16
const LEVEL: int = 5

const DESIGNER_MAP := Vector2i(21, 14)
const DESIGNER_CELL := Vector2i(3, 6)
const EVERY_SPECIES: int = 251
const MAX_STEPS: int = 64


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
	var wilds: int = int(args[1]) if args.size() > 1 else DEFAULT_WILDS
	var host: Gen2ModHost = Gen2ModHost.instance()
	host.set_target_game(game)
	host.discover()
	host.load_discovered()

	var ok: bool = _loaded(host)
	ok = _item(data) and ok
	ok = _policy(host) and ok
	ok = _population(data, host, wilds) and ok
	ok = _diploma(data, host) and ok
	print("%s: %s" % [game, "ok" if ok else "FAILED"])
	quit(0 if ok else 1)


func _loaded(host: Gen2ModHost) -> bool:
	for failure: Dictionary in host.failures():
		print("mod refused: %s" % str(failure))
	for manifest: PokeModManifest in host.manifests():
		if manifest.id == MOD_ID:
			return host.failures().is_empty()
	print("%s did not load" % MOD_ID)
	return false


func _item(data: GameData) -> bool:
	var row: Dictionary = data.item(SHINY_CHARM)
	if row.is_empty():
		print("item %d is not defined" % SHINY_CHARM)
		return false
	var ok: bool = true
	for field: String in ["name", "pocket", "field_menu", "permissions"]:
		print("  %-12s %s" % [field, str(row.get(field, "-"))])
	print("  description  %s" % String(row.get("description", "")).replace("\n", " / "))
	if int(row.get("pocket", 0)) != Gen2WorldPack.TYPE_KEY_ITEM:
		print("the charm is not in the KEY ITEMS pocket")
		ok = false
	if Gen2WorldPack.field_use_kind(data, SHINY_CHARM) != Gen2WorldPack.ITEMMENU_NOUSE:
		print("the charm offers a USE, and it is worth something by being owned")
		ok = false
	if Gen2WorldPack.can_toss(data, SHINY_CHARM):
		print("the charm can be tossed, and the roll count reads the bag")
		ok = false
	for line: String in String(row.get("description", "")).split("\n"):
		if line.length() > 18:
			print("description line is %d characters: %s" % [line.length(), line])
			ok = false
	return ok


func _policy(host: Gen2ModHost) -> bool:
	var ok: bool = true
	var context: Dictionary = {
		"species": SPECIES, "level": LEVEL, "method": &"grass",
		"map_group": -1, "map_number": -1,
	}
	host.set_inventory_source(func() -> Dictionary: return {})
	var without: int = Gen2ModHost.shiny_roll_count(context)
	host.set_inventory_source(func() -> Dictionary: return {SHINY_CHARM: 1})
	var with_charm: int = Gen2ModHost.shiny_roll_count(context)
	print("  rolls        %d without the charm, %d with it" % [without, with_charm])
	if without != 1:
		print("a bag with no charm in it is not the cartridge's single roll")
		ok = false
	if with_charm != ROLLS:
		print("holding the charm is not worth %d rolls" % ROLLS)
		ok = false
	return ok


func _population(data: GameData, host: Gen2ModHost, wilds: int) -> bool:
	var party: Gen2Party = Gen2WorldBattleAdapter.fallback_party(data)
	host.set_inventory_source(func() -> Dictionary: return {})
	var plain: int = _shinies(data, party, wilds, 1)
	host.set_inventory_source(func() -> Dictionary: return {SHINY_CHARM: 1})
	var charmed: int = _shinies(data, party, wilds, 2)
	print("  %d wilds     %d shiny without the charm, %d with it" % [wilds, plain, charmed])
	print("  one in       %s without, %s with" % [
		"never" if plain == 0 else str(wilds / plain),
		"never" if charmed == 0 else str(wilds / charmed),
	])
	if wilds < MINIMUM_ARM:
		print("an arm under %d wilds cannot separate the two rates; not judged" % MINIMUM_ARM)
		return true
	if plain == 0:
		print("no wild was shiny at all, so the host is not rolling DVs")
		return false
	var ratio: float = float(charmed) / float(plain)
	print("  ratio        %.2f, wanted %s to %s" % [ratio, RATIO_BAND.x, RATIO_BAND.y])
	if ratio < RATIO_BAND.x or ratio > RATIO_BAND.y:
		print("the charm is not worth about %d times the chance" % ROLLS)
		return false
	var vanilla: float = float(wilds) / float(plain)
	print("  vanilla      one in %.0f, the hardware's one in %d" % [vanilla, VANILLA_ODDS])
	return true


func _shinies(data: GameData, party: Gen2Party, wilds: int, stream: int) -> int:
	var random := RandomNumberGenerator.new()
	random.seed = hash("shiny_charm_probe:%d" % stream)
	var request: Dictionary = {"values": {
		"kind": &"wild", "pokemon": SPECIES, "level": LEVEL,
	}}
	var found: int = 0
	for _wild: int in wilds:
		var prepared: Dictionary = Gen2WorldBattleAdapter.prepare(data, request, party, random)
		if not bool(prepared.get("ok", false)):
			print("could not build a wild: %s" % str(prepared))
			return -1
		if Gen2Stats.is_shiny((prepared["enemy_party"] as Gen2Party).active_mon().dvs):
			found += 1
	return found


func _diploma(data: GameData, host: Gen2ModHost) -> bool:
	var caught: Dictionary = {}
	for species: int in range(1, EVERY_SPECIES + 1):
		caught[species] = true
	var state := Gen2WorldState.new(
		{}, {}, {}, {}, 0, {}, 0, Vector2i(-1, -1), 0, [], false, 0, 0, 0, {}, {}, {}, caught
	)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, DESIGNER_MAP.x, DESIGNER_MAP.y, DESIGNER_CELL + Vector2i.DOWN, state
	)
	if world == null:
		print("no world on map %s" % str(DESIGNER_MAP))
		return false
	world.player_facing = Gen2WorldSprite.FACING_UP
	host.set_inventory_source(func() -> Dictionary: return world.state.items())
	host.take_item_gift_requests()

	print("  dex          %d caught, the designer wants over 248" % state.caught_count())
	var found: bool = false
	var boxes: int = 0
	var results: Array = world.interact()
	for _step: int in MAX_STEPS:
		if results.is_empty():
			break
		for result: Dictionary in results:
			var published: Dictionary = Gen2ModHost.publish(Gen2ModHost.CHANNEL_WORLD, result)
			var staged: Variant = published.get("event", {})
			if not staged is Dictionary:
				continue
			var request: Variant = (staged as Dictionary).get("request", {})
			if not request is Dictionary:
				continue
			var kind: StringName = StringName((request as Dictionary).get("kind", &""))
			if kind == &"diploma_requested":
				found = true
			elif kind != &"":
				boxes += 1
		if found:
			break
		results = world.run_event_queue(true)
	if not found:
		print("the designer never reached the diploma after %d boxes" % boxes)
		return false

	var asked: Array[Dictionary] = host.take_item_gift_requests()
	print("  asked for    %s" % str(asked))
	if asked.size() != 1 or int(asked[0].get("item", 0)) != SHINY_CHARM \
		or int(asked[0].get("quantity", 0)) != 1:
		print("the diploma did not queue exactly one charm")
		return false

	world.inventory.change_item_quantity(SHINY_CHARM, 1)
	Gen2ModHost.publish(Gen2ModHost.CHANNEL_WORLD, {
		"ok": true, "status": &"waiting",
		"event": {"type": &"runtime_request", "request": {
			"kind": &"diploma_requested", "values": {"special": 108, "printing": true},
		}},
	})
	var again: Array[Dictionary] = host.take_item_gift_requests()
	print("  holding one  %s" % ("asked again" if not again.is_empty() else "asked for nothing"))
	if not again.is_empty():
		print("the charm would be handed over twice")
		return false
	return true
