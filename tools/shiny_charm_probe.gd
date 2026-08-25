extends SceneTree

## Checks the Shiny Charm against a real cartridge cache, on whichever of the
## three is named. Three claims, each measured rather than asserted: the item is
## a key item with no use, holding it is worth three rolls and not holding it is
## worth one, and three rolls actually multiply what comes out of the host's own
## wild builder.
##
## The last one is why this exists. A roll count is a number the mod returns and
## the host acts on, so the only honest test of it is the population: build
## enough wilds with the charm and without it and count the shinies. It runs
## `Gen2WorldBattleAdapter.prepare` itself, which is the one place every wild in
## the game is built.
##
## The diploma section is the fourth: it stands the player in front of the GAME
## designer on the real map with a finished Pokedex, runs his own script, and
## puts each result the runner produced through `Gen2ModHost.publish` the way
## the world screen does. Nothing is mocked but the publisher, because a headless
## run has no screen and screens are what publish.
##
##   godot --headless --path <pokerecomp> -s tools/shiny_charm_probe.gd -- \
##       <cartridge> [wilds per arm]
##
## The default arm is large enough for the two rates to separate and small
## enough to run in a few seconds. The measurement is a sample, so the test is
## the RATIO against three, with a wide band: a tight one would fail on a seed
## rather than on a defect.

const MOD_ID: StringName = &"shiny_charm"
const SHINY_CHARM: int = 257
const ROLLS: int = 3
## One in this many, which is `is_shiny`'s own share of the 65536 DV words: eight
## ATTACK values out of sixteen, and one exact value in each of the other three.
const VANILLA_ODDS: int = 8192
const DEFAULT_WILDS: int = 240000
## Under this the unmodded arm draws too few shinies for a ratio to mean
## anything, so a small arm reports and is not judged. A smaller run is still
## worth having: it is the whole probe in a second while the diploma section is
## being worked on.
const MINIMUM_ARM: int = VANILLA_ODDS * 8
## What the measured ratio has to sit inside. Three arms of a quarter of a
## million wilds land near 3.0; this fails a mod that stopped asking for rolls
## and passes a run that drew unluckily.
const RATIO_BAND := Vector2(2.0, 4.0)
## Any wild with a real table behind it. PIDGEY at 5 is what the host's own
## fixtures use.
const SPECIES: int = 16
const LEVEL: int = 5

## Celadon Condominiums' top floor, and the GAME designer standing on it. The
## player goes one cell south of him and looks up.
const DESIGNER_MAP := Vector2i(21, 14)
const DESIGNER_CELL := Vector2i(3, 6)
## `readvar` 5 against `ifgreater` 248 is the designer's own test, so a dex with
## every species caught is the one state that reaches the diploma.
const EVERY_SPECIES: int = 251
## The script prints four boxes before the certificate. A ceiling rather than a
## count, so a cartridge that words it differently still gets there.
const MAX_STEPS: int = 64


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var cartridge: String = args[0] if not args.is_empty() else "crystal"
	## Before the open: see `tools/linking_cord_probe.gd` for what a reset does to
	## a `GameData` already in hand.
	Gen2ModHost.reset()
	# Either form: see `GameData.open_argument`.
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


## Loaded by the production path, not by hand, so a manifest the host would
## refuse is a failure here rather than a surprise in the launcher.
func _loaded(host: Gen2ModHost) -> bool:
	for failure: Dictionary in host.failures():
		print("mod refused: %s" % str(failure))
	for manifest: Gen2ModManifest in host.manifests():
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
	# Both lines fit the box the pack draws them in, which is the one thing about
	# a description that is not a matter of taste.
	for line: String in String(row.get("description", "")).split("\n"):
		if line.length() > 18:
			print("description line is %d characters: %s" % [line.length(), line])
			ok = false
	return ok


## The roll count through the host's own join, not through the provider: what a
## wild is built with is `shiny_roll_count`, and that is what has to move when
## the bag does.
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


## The claim the README makes, measured: three arms of the host's own wild
## builder, counting what `is_shiny` accepts.
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
	# The unmodded rate is the hardware's and does not move with the mod, so it
	# is worth saying out loud when it drifts: a rate far off one in 8192 means
	# the host's own roll changed, not this mod.
	var vanilla: float = float(wilds) / float(plain)
	print("  vanilla      one in %.0f, the hardware's one in %d" % [vanilla, VANILLA_ODDS])
	return true


## [param stream] only has to differ between the two arms: one generator seeded
## the same way for both would draw the same words and the charm's extra rolls
## would be the only difference measured, which is the answer being assumed.
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


## The award, end to end: the designer's own script on his own map, every result
## published on the world channel, and the mod's ask waiting in the host's queue
## afterwards. The queue is what the world screen spends, so reaching it is the
## whole of what this mod does.
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
	# The bag the mod reads. Empty, which is the state a player who has never
	# been given the charm is in.
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
			# What `Gen2WorldScreen` does with every result before it shows it.
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

	# Twice is the fault worth testing: the designer offers to reprint on every
	# later visit, and a charm already in the bag must not be handed over again.
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
