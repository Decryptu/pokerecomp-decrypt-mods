extends SceneTree

## Checks the Hidden Stats page against a real cartridge cache: the snapshot
## carries the two hidden words, the page says them, and the screen turns to it.

const Staging: GDScript = preload("staging.gd")

const MOD_ID: StringName = &"hidden_stats"
const SPECIES: int = 25
const LEVEL: int = 34
const DVS: int = 0xB7D9
const STAT_EXP: Dictionary = {
	"hp": 21760, "attack": 40960, "defense": 8704,
	"special": 15104, "speed": 33280,
}
const DV_KEYS: Array[String] = ["hp", "attack", "defense", "special", "speed"]
const LOWER_FIRST_ROW: int = 8
const LOWER_ROWS: int = 10
const GEN1_TURNS: Array[int] = [PokeButton.A, PokeButton.A]
const GEN2_TURNS: Array[int] = [PokeButton.RIGHT, PokeButton.RIGHT, PokeButton.RIGHT]


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var cartridge: String = args[0] if not args.is_empty() else "crystal"
	Gen2ModHost.reset()
	var data: GameData = GameData.open_argument(cartridge)
	if data == null:
		print("no cache for %s" % cartridge)
		quit(1)
		return
	var host: Gen2ModHost = Gen2ModHost.instance()
	var ok: bool = Staging.mod_loaded(host, data, MOD_ID)
	var mon: Gen2SaveMon = _stage(data)
	if mon == null:
		print("no species %d on %s" % [SPECIES, data.id])
		quit(1)
		return
	var screen: Gen2MonStatsScreen = Gen2MonStatsScreen.create(data, [mon])
	ok = _snapshot(screen.snapshot()) and ok
	ok = _page(host, screen.snapshot()) and ok
	ok = _turns(data, screen) and ok
	print("%s: %s" % [data.id, "ok" if ok else "FAILED"])
	quit(0 if ok else 1)


func _stage(data: GameData) -> Gen2SaveMon:
	var battle_mon: Gen2BattleMon = Gen2BattleMon.create(
		data, SPECIES, LEVEL, data.moves_at_level(SPECIES, LEVEL)
	)
	if battle_mon == null:
		return null
	var mon: Gen2SaveMon = Gen2SaveBattleAdapter.from_battle_mon(battle_mon)
	mon.dvs = DVS
	mon.stat_exp = STAT_EXP.duplicate()
	return mon


func _snapshot(page: Dictionary) -> bool:
	var ok: bool = true
	if int(page.get("dvs", -1)) != DVS:
		print("snapshot dvs %s, wanted %d" % [str(page.get("dvs")), DVS])
		ok = false
	var trained: Dictionary = page.get("stat_exp", {})
	for key: String in DV_KEYS:
		if int(trained.get(key, -1)) != int(STAT_EXP[key]):
			print("snapshot stat_exp %s %s, wanted %d" % [
				key, str(trained.get(key)), int(STAT_EXP[key]),
			])
			ok = false
	return ok


## The registered page, built through the host's own registry, says every DV
## and every counter inside the lower half.
func _page(host: Gen2ModHost, snapshot: Dictionary) -> bool:
	var pages: Array = host.stats_pages()
	if pages.size() != 1 or StringName(pages[0].get("kind", &"")) != MOD_ID:
		print("stats pages registered: %s" % str(pages))
		return false
	var placements: Variant = (pages[0]["build"] as Callable).call(snapshot)
	if not placements is Array:
		print("page built %s, not placements" % str(placements))
		return false
	var texts: Array[String] = []
	var ok: bool = true
	for placement: Dictionary in placements as Array:
		if placement.has("divider"):
			continue
		var at: Vector2i = placement.get("at", Vector2i.ZERO)
		if at.y < LOWER_FIRST_ROW or at.y >= LOWER_FIRST_ROW + LOWER_ROWS:
			print("placement %s is outside the lower half" % str(placement))
			ok = false
		texts.append(String(placement.get("text", "")).strip_edges())
	for wanted: String in _expected():
		if not texts.has(wanted):
			print("page never says %s" % wanted)
			ok = false
	return ok


func _expected() -> Array[String]:
	var out: Array[String] = [
		str(Gen2Stats.hp_dv(DVS)), str(Gen2Stats.attack_dv(DVS)),
		str(Gen2Stats.defense_dv(DVS)), str(Gen2Stats.special_dv(DVS)),
		str(Gen2Stats.speed_dv(DVS)),
	]
	for key: String in DV_KEYS:
		out.append(str(int(STAT_EXP[key])))
	return out


## The screen turns to the page: RIGHT past the blue page on Generation II, A
## past the cartridge's second page on Generation I, and A there is the exit.
func _turns(data: GameData, screen: Gen2MonStatsScreen) -> bool:
	var one: bool = data.generation == RomRegistry.GEN1
	var cartridge_pages: int = Gen2StatsScreenPage.GEN1_PAGES if one \
		else Gen2StatsScreenPage.NUM_PAGES
	var wanted: int = Gen2StatsScreenPage.PINK_PAGE + cartridge_pages
	var closed: Array[bool] = [false]
	screen.closed.connect(func() -> void: closed[0] = true)
	for button: int in (GEN1_TURNS if one else GEN2_TURNS):
		screen.handle_button(button)
	var page: int = int(screen.snapshot().get("page", 0))
	if closed[0] or page != wanted:
		print("turned to page %d%s, wanted %d" % [
			page, " and closed" if closed[0] else "", wanted,
		])
		return false
	screen.handle_button(PokeButton.A)
	if not closed[0]:
		print("A on the last page did not close the screen")
		return false
	return true
