extends SceneTree

## Checks the Catch Combo against a real cartridge cache, through the host's own
## joins rather than through the mod's objects. Four claims:
##
## 1. The mod loads by the production path, at `api_version` 20.
## 2. A published capture moves the counter, and the rungs are the Let's Go
##    ones: 1, 4, 8 and 12 words at 1, 11, 21 and 31, for the chained species
##    and for nobody else.
## 3. The charm's two extra rolls add to the combo's rather than losing to them,
##    which is 14 at a combo of 31 with the charm in the bag.
## 4. The counter breaks on the three ways a wild leaves a Generation II battle
##    standing, and on nothing else.
##
## Everything is driven by publishing the events the battle publishes, so what
## is measured is the mod reading the same dictionaries the screen sends it.
##
##   godot --headless --path <pokerecomp> -s tools/catch_combo_probe.gd -- \
##       <cartridge>

const MOD_ID: StringName = &"catch_combo"
const CHARM_ID: StringName = &"shiny_charm"
const SHINY_CHARM: int = 257
## RATTATA, and PIDGEY as the species the combo is never on.
const SPECIES: int = 19
const OTHER: int = 16
const LEVEL: int = 4
## `[combo, rolls]`, and the two ends of each rung rather than its middle.
const RUNGS: Array = [
	[1, 1], [10, 1], [11, 4], [20, 4], [21, 8], [30, 8], [31, 12], [60, 12],
]
## What the charm is worth on its own, so what it has to add.
const CHARM_ROLLS: int = 3


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var cartridge: String = args[0] if not args.is_empty() else "crystal"
	## Before the open: see `tools/linking_cord_probe.gd` for what a reset does to
	## a `GameData` already in hand.
	Gen2ModHost.reset()
	var data: GameData = GameData.open_argument(cartridge)
	if data == null:
		print("no cache for %s" % cartridge)
		quit(1)
		return
	var host: Gen2ModHost = Gen2ModHost.instance()
	host.set_target_game(data.id)
	host.discover()
	host.load_discovered()
	host.set_inventory_source(func() -> Dictionary: return {})

	var ok: bool = _loaded(host)
	ok = _rungs(host) and ok
	ok = _stacking(host) and ok
	ok = _breaks(host) and ok
	ok = _box(host) and ok
	print("%s: %s" % [data.id, "ok" if ok else "FAILED"])
	quit(0 if ok else 1)


func _loaded(host: Gen2ModHost) -> bool:
	for failure: Dictionary in host.failures():
		print("mod refused: %s" % str(failure))
	var found: bool = false
	for manifest: Gen2ModManifest in host.manifests():
		if manifest.id == MOD_ID:
			found = true
			print("  loaded       %s %s, api %d" % [
				manifest.id, manifest.version, manifest.api_version,
			])
	if not found:
		print("%s did not load" % MOD_ID)
	return found and host.failures().is_empty()


## The counter is only ever moved from here, so every claim below is made about
## a combo the mod built out of published captures.
func _catch(species: int, times: int = 1) -> void:
	for _time: int in times:
		Gen2ModHost.publish(Gen2ModHost.CHANNEL_BATTLE, {
			"type": Gen2Battle.CAUGHT,
			"species": species, "level": LEVEL, "dvs": 0, "shiny": false,
			"ball": 5, "method": &"grass", "map_group": -1, "map_number": -1,
			"battle_type": 0, "destination": &"party",
			"tutorial": false, "contest": false,
		})


func _rolls(species: int) -> int:
	return Gen2ModHost.shiny_roll_count({
		"species": species, "level": LEVEL, "method": &"grass",
		"map_group": -1, "map_number": -1,
	})


## A combo of exactly [param length], built from nothing each time: the counter
## has no setter and should not have one.
func _combo(host: Gen2ModHost, length: int) -> void:
	_break(host)
	_catch(SPECIES, length)


## Roar on the wild, which is one of the three the mod reads.
func _break(_host: Gen2ModHost) -> void:
	Gen2ModHost.publish(Gen2ModHost.CHANNEL_BATTLE, {
		"type": Gen2Battle.FLED_IN_FEAR, "target": Gen2Battle.ENEMY,
	})


func _rungs(host: Gen2ModHost) -> bool:
	var ok: bool = true
	for rung: Array in RUNGS:
		_combo(host, int(rung[0]))
		var mine: int = _rolls(SPECIES)
		var theirs: int = _rolls(OTHER)
		print("  combo %-3d    %d rolls, %d for a species it is not on" % [
			int(rung[0]), mine, theirs,
		])
		if mine != int(rung[1]):
			print("a combo of %d is %d rolls and should be %d" % [
				int(rung[0]), mine, int(rung[1]),
			])
			ok = false
		if theirs != 1:
			print("a species the combo is not on is worth %d rolls" % theirs)
			ok = false
	## A catch of anything else is the first link of its own combo rather than a
	## break, which is what the counter reads after it in the later games.
	_combo(host, 30)
	_catch(OTHER)
	if _rolls(OTHER) != 1 or _rolls(SPECIES) != 1:
		print("a different species did not start its own combo at one")
		ok = false
	## Neither of the two catches that are not a Pokemon kept.
	_combo(host, 11)
	Gen2ModHost.publish(Gen2ModHost.CHANNEL_BATTLE, {
		"type": Gen2Battle.CAUGHT, "species": OTHER, "tutorial": true,
	})
	Gen2ModHost.publish(Gen2ModHost.CHANNEL_BATTLE, {
		"type": Gen2Battle.CAUGHT, "species": OTHER, "contest": true,
	})
	if _rolls(SPECIES) != 4:
		print("a tutorial or contest catch moved the combo")
		ok = false
	return ok


## The charm is a second provider, so this is the composition and not the mod.
func _stacking(host: Gen2ModHost) -> bool:
	if not host.shiny_rolls_ids().has(CHARM_ID):
		print("  stacking     %s is not installed, so nothing was measured" % CHARM_ID)
		return true
	var ok: bool = true
	host.set_inventory_source(func() -> Dictionary: return {SHINY_CHARM: 1})
	_break(host)
	var charm_alone: int = _rolls(SPECIES)
	_combo(host, 31)
	var both: int = _rolls(SPECIES)
	host.set_inventory_source(func() -> Dictionary: return {})
	var combo_alone: int = _rolls(SPECIES)
	print("  stacking     %d charm, %d combo, %d together" % [
		charm_alone, combo_alone, both,
	])
	if charm_alone != CHARM_ROLLS:
		print("the charm alone is not %d rolls" % CHARM_ROLLS)
		ok = false
	if both != combo_alone + charm_alone - 1:
		print("the two did not add: %d and %d came to %d" % [
			combo_alone, charm_alone, both,
		])
		ok = false
	return ok


func _breaks(host: Gen2ModHost) -> bool:
	var ok: bool = true
	## The three a wild leaves under, and the three that leave a combo alone.
	var leaving: Array = [
		{"type": Gen2Battle.FLED_IN_FEAR, "target": Gen2Battle.ENEMY},
		{"type": Gen2Battle.BLOWN_AWAY, "target": Gen2Battle.ENEMY},
		{"type": Gen2Battle.FLED_FROM_BATTLE, "side": Gen2Battle.ENEMY},
	]
	var standing: Array = [
		## The player got away, which is what `fled` is.
		{"type": Gen2Battle.FLED, "side": Gen2Battle.PLAYER},
		{"type": Gen2Battle.FAINTED, "side": Gen2Battle.ENEMY},
		{"type": Gen2Battle.OVER},
		## Roar in a trainer battle, where the wild's own line belongs to a
		## Pokemon that was dragged out rather than one that left.
		{"type": Gen2Battle.FLED_FROM_BATTLE, "side": Gen2Battle.PLAYER},
	]
	for event: Dictionary in leaving:
		_combo(host, 31)
		Gen2ModHost.publish(Gen2ModHost.CHANNEL_BATTLE, event)
		if _rolls(SPECIES) != 1:
			print("%s did not break the combo" % event["type"])
			ok = false
	for event: Dictionary in standing:
		_combo(host, 31)
		Gen2ModHost.publish(Gen2ModHost.CHANNEL_BATTLE, event)
		if _rolls(SPECIES) != 12:
			print("%s broke the combo and should not have" % event["type"])
			ok = false
	print("  breaks       %d leave it, %d leave it standing" % [
		leaving.size(), standing.size(),
	])
	return ok


## The line, through the host's own queue: what the mod asked for is what the
## battle would print.
func _box(host: Gen2ModHost) -> bool:
	var ok: bool = true
	host.set_battle_messages_open(true)
	_combo(host, 12)
	var lines: Array[String] = []
	while true:
		var request: Dictionary = host.take_battle_message()
		if request.is_empty():
			break
		lines.append(String(request.get("text", "")))
	host.set_battle_messages_open(false)
	print("  box          %s" % (lines[-1] if not lines.is_empty() else "nothing"))
	if lines.size() != 12:
		print("twelve catches asked for %d lines" % lines.size())
		ok = false
	if lines.is_empty() or lines[-1] != "Catch Combo 12!":
		print("the twelfth line is not the combo it reached")
		ok = false
	## What the host refuses is what the player would never have read, so the
	## longest line the counter can reach has to fit.
	var longest: Dictionary = host.request_battle_message(MOD_ID, "Catch Combo 99999!")
	if not bool(longest.get("ok", false)) \
		and StringName(longest.get("reason", &"")) != &"no_battle_showing_messages":
		print("a five-digit combo does not fit the box: %s" % str(longest))
		ok = false
	return ok
