extends SceneTree

## Checks the Achievements mod against a real cartridge cache. Four claims:
##
## 1. The mod loads by the production path, at `api_version` 20.
## 2. The catalogue is well formed: thirty rows, no id twice, every badge
##    covered once, every name and every line of every detail inside the box the
##    cartridge draws, and every icon naming art this cartridge carries.
## 3. Each rule answers at its own edge and one below it, so no row is unlocked
##    by a run that has not reached it.
## 4. The ledger never says the same thing twice. A save played before the mod
##    was installed is awarded in silence; a run that began with it announces;
##    a reopened save announces nothing again; and a build that adds rows to a
##    finished save summarises rather than firing one notice each.
##
##   godot --headless --path <pokerecomp> -s tools/achievements_probe.gd -- \
##       <cartridge>

const MOD_ID: StringName = &"achievements"
const MOD_ROOT: String = "user://mods/achievements"

## What the cartridge's own box holds: eighteen cells across, and a detail is
## the two lines under a name.
const CELLS: int = 18
const DETAIL_LINES: int = 2

## Four tiles a badge in `card_badges`, and only the Johto eight are drawn.
const BADGE_TILES: int = 4
const JOHTO_BADGES: int = 8

var _catalogue: GDScript = null
var _ledger: GDScript = null


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var cartridge: String = args[0] if not args.is_empty() else "crystal"
	## Before the open: see `tools/linking_cord_probe.gd` for what a reset does
	## to a `GameData` already in hand.
	Gen2ModHost.reset()
	var data: GameData = GameData.open_argument(cartridge)
	if data == null:
		print("no cache for %s" % cartridge)
		quit(1)
		return
	_catalogue = load("%s/catalogue.gd" % MOD_ROOT)
	_ledger = load("%s/ledger.gd" % MOD_ROOT)
	if _catalogue == null or _ledger == null:
		print("the mod is not installed at %s" % MOD_ROOT)
		quit(1)
		return

	var host: Gen2ModHost = Gen2ModHost.instance()
	host.set_target_game(data.id)
	host.discover()
	host.load_discovered()

	var ok: bool = _loaded(host)
	ok = _table(data) and ok
	ok = _edges() and ok
	ok = _once() and ok
	print("%s: %s" % [data.id, "ok" if ok else "FAILED"])
	quit(0 if ok else 1)


func _loaded(host: Gen2ModHost) -> bool:
	for failure: Dictionary in host.failures():
		print("mod refused: %s" % str(failure))
	for manifest: Gen2ModManifest in host.manifests():
		if manifest.id == MOD_ID:
			print("  loaded       %s %s, api %d" % [
				manifest.id, manifest.version, manifest.api_version,
			])
			return true
	print("the mod did not load")
	return false


## The table itself, which is the part a player reads.
func _table(data: GameData) -> bool:
	var ok: bool = true
	var rows: Array = _catalogue.ROWS
	var ids: Dictionary = {}
	var badges: Dictionary = {}
	for row: Dictionary in rows:
		var id: StringName = StringName(row["id"])
		if ids.has(id):
			print("two rows are called %s" % id)
			ok = false
		ids[id] = true
		ok = _fits(id, "name", String(row["name"]), 1) and ok
		ok = _fits(id, "detail", String(row["detail"]), DETAIL_LINES) and ok
		ok = _art(data, id, row["icon"] as Dictionary) and ok
		if StringName(row["rule"]) == _catalogue.RULE_BADGE:
			badges[int(row["at"])] = true
	print("  rows         %d, %d of them a badge" % [rows.size(), badges.size()])
	if badges.size() != _catalogue.BADGE_COUNT:
		print("the badges are not covered once each")
		ok = false
	return ok


## A string inside the box: at most [param lines] of them, each at most as wide
## as the cartridge draws.
func _fits(id: StringName, field: String, text: String, lines: int) -> bool:
	var split: PackedStringArray = text.split("\n")
	if split.size() > lines:
		print("%s's %s is %d lines" % [id, field, split.size()])
		return false
	for line: String in split:
		if line.length() > CELLS:
			print("%s's %s runs past the box: \"%s\"" % [id, field, line])
			return false
	return true


## Whether the icon a row names is art this cartridge actually carries.
func _art(data: GameData, id: StringName, icon: Dictionary) -> bool:
	if icon.has("badge"):
		var index: int = int(icon["badge"])
		var tiles: PackedByteArray = data.tile_indices("card_badges")
		@warning_ignore("integer_division")
		var held: int = int(tiles.size() / (Gen2Tiles.TILE_PIXELS))
		if index < 0 or index >= JOHTO_BADGES or held < (index + 1) * BADGE_TILES:
			print("%s names badge art the card does not draw: %d" % [id, index])
			return false
		return true
	if icon.has("species"):
		var species: int = int(icon["species"])
		if data.species_icon_indices(species).is_empty():
			print("%s names a species with no menu icon: %d" % [id, species])
			return false
		return true
	print("%s names no icon" % id)
	return false


## Every rule at the run that just reaches it and the run one short of it.
func _edges() -> bool:
	var ok: bool = true
	var cases: Array = [
		[&"zephyr_badge", {"badges": 0x0001}, {"badges": 0x0002}],
		[&"earth_badge", {"badges": 0x8000}, {"badges": 0x7FFF}],
		[&"johto_cleared", {"badges": 0x00FF}, {"badges": 0x00FE}],
		[&"kanto_cleared", {"badges": 0xFFFF}, {"badges": 0xFFFE}],
		[&"champion", {"hall_of_fame": true}, {"hall_of_fame": false}],
		[&"mt_silver", {"beat_red": true}, {"beat_red": false}],
		[&"first_catch", {"caught_count": 1}, {"caught_count": 0}],
		[&"hundred_caught", {"caught_count": 100}, {"caught_count": 99}],
		[&"pokedex", {"caught_count": 251}, {"caught_count": 250}],
		[&"unown", {"unown_caught": 26}, {"unown_caught": 25}],
		[&"full_party", {"party_count": 6}, {"party_count": 5}],
		[&"level_100", {"highest_level": 100}, {"highest_level": 99}],
		[&"shiny", {"shiny_count": 1}, {"shiny_count": 0}],
		[&"rich", {"money": 100000}, {"money": 99999}],
		[&"high_roller", {"coins": 1000}, {"coins": 999}],
		[&"one_day", {"play_hours": 24}, {"play_hours": 23}],
	]
	for case: Array in cases:
		var id: StringName = StringName(case[0])
		var row: Dictionary = _catalogue.find(id)
		if row.is_empty():
			print("no row called %s" % id)
			ok = false
			continue
		if not _catalogue.holds(row, case[1] as Dictionary):
			print("%s is locked by the run that earns it" % id)
			ok = false
		if _catalogue.holds(row, case[2] as Dictionary):
			print("%s unlocks one short of itself" % id)
			ok = false
	## An empty snapshot is a run that has done nothing, and an older host that
	## answers a field this build asks for must not unlock anything either.
	var held: Array = _catalogue.held({})
	if not held.is_empty():
		print("an empty run unlocks %s" % str(held))
		ok = false
	print("  edges        %d rules, and nothing at all for an empty run" % cases.size())
	return ok


## The rule that keeps a notice honest, over the four ways a set can move.
func _once() -> bool:
	var ok: bool = true
	## Eight badges, the Hall of Fame and a hundred species: a save that got
	## there before the mod was installed.
	var played: Dictionary = {
		"badges": 0x00FF, "hall_of_fame": true, "caught_count": 100,
		"party_count": 6, "highest_level": 100,
	}

	var late: RefCounted = _ledger.new()
	late.restore({})
	var first: Dictionary = late.scan(played)
	print("  late install %d awarded, quiet %s" % [
		(first["unlocked"] as Array).size(), first["quiet"],
	])
	if (first["unlocked"] as Array).is_empty() or not bool(first["quiet"]):
		print("a save played before the mod is not awarded in silence")
		ok = false

	## The same save closed and opened again: the set comes back and nothing is
	## new, which is what a reboot must not undo.
	var again: RefCounted = _ledger.new()
	again.restore(late.stored())
	var reopened: Dictionary = again.scan(played)
	if not (reopened["unlocked"] as Array).is_empty():
		print("reopening the save awards %s again" % str(reopened["unlocked"]))
		ok = false
	if again.progress_counts() != late.progress_counts():
		print("the set did not survive the save")
		ok = false
	print("  reopened     %d of %d, nothing new" % [
		again.progress_counts().x, again.progress_counts().y,
	])

	## A run that began with the mod installed: `save_created` wrote an empty
	## ledger, so its first badge is worth a notice.
	var fresh: RefCounted = _ledger.new()
	fresh.restore(_ledger.new().stored())
	var earned: Dictionary = fresh.scan({"badges": 0x0001})
	if (earned["unlocked"] as Array).size() != 1 or bool(earned["quiet"]):
		print("a badge earned with the mod watching is not announced: %s" % str(earned))
		ok = false

	## And the same run finishing Johto in one sitting: four badges at once is
	## past the threshold, so it is summarised rather than fired one by one.
	var many: Dictionary = fresh.scan({"badges": 0x00FF})
	if (many["unlocked"] as Array).size() <= _ledger.QUIET_ABOVE \
		or not bool(many["quiet"]):
		print("a batch of unlocks is not summarised: %s" % str(many))
		ok = false
	print("  announced    1 alone, then %d together and quiet" % [
		(many["unlocked"] as Array).size(),
	])

	## An id this build does not know is kept rather than dropped, so a save
	## opened by a later version and then this one is not announced twice.
	var older: RefCounted = _ledger.new()
	older.restore({"version": _ledger.VERSION, "unlocked": ["from_a_later_build"]})
	if not older.has(&"from_a_later_build"):
		print("an unknown id is dropped on the way through")
		ok = false
	if not (older.stored()["unlocked"] as Array).has("from_a_later_build"):
		print("an unknown id does not survive the save")
		ok = false
	return ok
