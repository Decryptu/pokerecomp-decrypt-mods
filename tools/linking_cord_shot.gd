extends SceneTree

## Photographs the cord where a player meets it: the bag row that lists it, its
## own submenu, and the party list USE opens. The evolution scene runs on the
## world screen; `evolution_shot.gd` photographs that.

const Staging: GDScript = preload("staging.gd")

const MOD_ID: StringName = &"linking_cord"
const LINKING_CORD: int = 256
const NEW_BARK: Vector2i = Vector2i(24, 7)
const PALLET_TOWN: Vector2i = Vector2i(0, 0)

const BUTTONS: Dictionary = {
	"u": PokeButton.UP, "d": PokeButton.DOWN,
	"l": PokeButton.LEFT, "r": PokeButton.RIGHT,
	"a": PokeButton.A, "b": PokeButton.B,
}

## Four cartridge items ahead of the cord, so the list scrolls to it: potions
## and an antidote on Generation II, balls, potions and a rope on Generation I.
const ITEMS: Dictionary = {17: 3, 18: 2, 19: 1, 20: 5, LINKING_CORD: 1}
const GEN1_ITEMS: Dictionary = {4: 3, 19: 2, 20: 1, 29: 5, LINKING_CORD: 1}

const ROUTES: Dictionary = {
	"list": "d,d,d,d",
	"menu": "d,d,d,d,a",
	"party": "d,d,d,d,a,a",
}


func _stage_party(data: GameData, save: Gen2SaveData, spec: String) -> void:
	var members: Array = []
	for token: String in spec.split("/", false):
		var halves: PackedStringArray = token.strip_edges().split(":")
		var species: int = int(halves[0])
		var mon: Gen2BattleMon = Gen2BattleMon.create(
			data, species, 30, data.moves_at_level(species, 30)
		)
		if mon == null:
			push_error("No species %d on this cartridge." % species)
			continue
		var member: Gen2SaveMon = Gen2SaveBattleAdapter.from_battle_mon(mon)
		member.item = int(halves[1]) if halves.size() > 1 else 0
		members.append(member)
	if not members.is_empty():
		save.party = members


func _process(_delta: float) -> bool:
	_capture()
	return true


func _capture() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: linking_cord_shot.gd -- <game> <output.png> [list|menu|party] [presses]")
		quit(1)
		return
	if PokeToolPath.refuses(args[1]):
		quit(2)
		return
	Gen2ModHost.reset()
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		push_error("No cache for %s." % args[0])
		quit(1)
		return
	if not Staging.mod_loaded(Gen2ModHost.instance(), data, MOD_ID):
		quit(1)
		return

	var tokens: String = String(ROUTES.get(args[2] if args.size() > 2 else "list", ""))
	if args.size() > 3 and not args[3].is_empty():
		tokens = "%s,%s" % [tokens, args[3]]

	var gen1: bool = data.generation == RomRegistry.GEN1
	var home: Vector2i = PALLET_TOWN if gen1 else NEW_BARK
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, home.x, home.y, Vector2i.ZERO,
		Gen2WorldState.new({}, {}, GEN1_ITEMS if gen1 else ITEMS, {})
	)
	var screen := Gen2StartMenuScreen.new()
	root.add_child(screen)
	var save: Gen2SaveData = Gen2SaveStore.create_development_save(data, 0)
	if save != null and args.size() > 4 and not args[4].is_empty():
		_stage_party(data, save, args[4])
	if save != null:
		save.world = world.snapshot()
		screen.set_party_context(save, false)
	if not screen.open(world, data, func() -> Dictionary: return {"ok": true}):
		push_error("The %s cache holds no start menu." % args[0])
		quit(1)
		return
	var menu: Gen2WorldStartMenu = screen.get("_menu")
	var rows: Array = menu.items()
	for index: int in rows.size():
		if StringName((rows[index] as Dictionary).get("kind", &"")) \
			== Gen2WorldStartMenu.ITEM_PACK:
			for _step: int in index - menu.cursor:
				screen.handle_button(PokeButton.DOWN)
			break
	screen.handle_button(PokeButton.A)
	for token: String in tokens.split(",", false):
		var key: String = token.strip_edges().to_lower()
		if BUTTONS.has(key):
			screen.handle_button(int(BUTTONS[key]))

	var image: Image = screen.call("_hardware_image") as Image
	if image == null:
		push_error("Mode %d has no cartridge screen to photograph." % int(screen.get("_mode")))
		quit(1)
		return
	if image.save_png(args[1]) != OK:
		push_error("Could not write %s" % args[1])
		quit(1)
		return
	print("Wrote %s: pocket %s, cursor %d, mode %d" % [
		args[1], String(screen.call("_current_pocket").get("name", "?")),
		int(screen.get("_pack_cursor")), int(screen.get("_mode")),
	])
	quit(0)
