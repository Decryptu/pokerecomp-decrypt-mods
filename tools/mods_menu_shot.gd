extends SceneTree

## Photographs the start menu's MODS entry, which is where a player meets a
## mod's settings.

const NEW_BARK_GROUP: int = 24
const NEW_BARK_MAP: int = 7

const BUTTONS: Dictionary = {
	"u": PokeButton.UP, "d": PokeButton.DOWN,
	"l": PokeButton.LEFT, "r": PokeButton.RIGHT,
	"a": PokeButton.A, "b": PokeButton.B,
}


func _process(_delta: float) -> bool:
	_capture()
	return true


func _capture() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -- <game> <out.png> [presses] [scale]")
		quit(2)
		return
	if PokeToolPath.refuses(args[1]):
		quit(2)
		return
	Gen2ModHost.reset()
	var mods: Gen2ModHost = Gen2ModHost.instance()
	mods.set_target_game(StringName(args[0]))
	mods.discover()
	mods.load_discovered()
	if not mods.failures().is_empty():
		print("mods refused: %s" % str(mods.failures()))
		quit(1)
		return
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache for %s" % args[0])
		quit(1)
		return
	var scale: int = maxi(int(args[3]) if args.size() > 3 else 1, 1)

	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, NEW_BARK_GROUP, NEW_BARK_MAP, Vector2i.ZERO,
		Gen2WorldState.new({}, {}, {}, {})
	)
	var screen := Gen2StartMenuScreen.new()
	root.add_child(screen)
	var save: Gen2SaveData = Gen2SaveStore.create_development_save(data, 0)
	if save != null:
		save.world = world.snapshot()
		screen.set_party_context(save, false)
	if not screen.open(world, data, func() -> Dictionary: return {"ok": true}):
		print("the %s cache holds no start menu" % args[0])
		quit(1)
		return

	var menu: Gen2WorldStartMenu = screen.get("_menu")
	var rows: Array = menu.items()
	var at: int = -1
	for index: int in rows.size():
		if StringName((rows[index] as Dictionary).get("kind", &"")) \
			== Gen2WorldStartMenu.ITEM_MODS:
			at = index
			break
	if at < 0:
		print("no MODS row: no installed mod registered a setting")
		quit(1)
		return
	for _step: int in at - menu.cursor:
		screen.handle_button(PokeButton.DOWN)
	screen.handle_button(PokeButton.A)
	for token: String in (args[2] if args.size() > 2 else "").split(",", false):
		var key: String = token.strip_edges().to_lower()
		if BUTTONS.has(key):
			screen.handle_button(int(BUTTONS[key]))

	var image: Image = screen.call("_hardware_image") as Image
	if image == null:
		print("mode %d has no cartridge screen to photograph" % int(screen.get("_mode")))
		quit(1)
		return
	if scale > 1:
		image.resize(
			image.get_width() * scale, image.get_height() * scale,
			Image.INTERPOLATE_NEAREST
		)
	if image.save_png(args[1]) != OK:
		print("could not write %s" % args[1])
		quit(1)
		return
	print("wrote %s: mode %d (%dx%d)" % [
		args[1], int(screen.get("_mode")), image.get_width(), image.get_height(),
	])
	quit(0)
