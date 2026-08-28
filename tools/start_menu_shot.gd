extends SceneTree

## Photographs the start menu's own list with the installed mods loaded, on a
## save that has unlocked every row the cartridge gates.

const NEW_BARK_GROUP: int = 24
const NEW_BARK_MAP: int = 7
const ENGINE_POKEGEAR: int = 4
const ENGINE_POKEDEX: int = 11

const BUTTONS: Dictionary = {"u": Gen2Button.UP, "d": Gen2Button.DOWN}


func _process(_delta: float) -> bool:
	_capture()
	return true


func _capture() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -- <game> <out.png> [presses] [scale]")
		quit(2)
		return
	if Gen2ToolPath.refuses(args[1]):
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
	var restore: Array = []
	for token: String in (args[4] if args.size() > 4 else "").split(",", false):
		var pair: PackedStringArray = token.strip_edges().split("=", false)
		var name: PackedStringArray = pair[0].split(":", false) if not pair.is_empty() \
			else PackedStringArray()
		if pair.size() != 2 or name.size() != 2:
			print("a setting is <mod id>:<key>=<value>, not %s" % token)
			quit(2)
			return
		var id := StringName(name[0])
		var key := StringName(name[1])
		restore.append([id, key, mods.option(id, key)])
		if not bool(mods.set_option(id, key, int(pair[1])).get("ok", false)):
			print("%s has no %s to set" % [id, key])
			quit(1)
			return

	var state := Gen2WorldState.new({}, {}, {}, {})
	state.set_engine_flag(ENGINE_POKEDEX)
	state.set_engine_flag(ENGINE_POKEGEAR)
	var world: Gen2WorldAPI = Gen2WorldAPI.open(
		data, NEW_BARK_GROUP, NEW_BARK_MAP, Vector2i.ZERO, state
	)
	var save: Gen2SaveData = Gen2SaveStore.create_development_save(data, 0)
	if save == null:
		print("the %s cache builds no development save" % args[0])
		quit(1)
		return
	var species: Array[int] = [] as Array[int]
	for member: Gen2SaveMon in save.party:
		species.append(member.species)
	world.set_party_summary(species.size(), false, species)
	var screen := Gen2StartMenuScreen.new()
	root.add_child(screen)
	save.world = world.snapshot()
	screen.set_party_context(save, false)
	if not screen.open(world, data, func() -> Dictionary: return {"ok": true}):
		print("the %s cache holds no start menu" % args[0])
		quit(1)
		return
	for token: String in (args[2] if args.size() > 2 else "").split(",", false):
		var key: String = token.strip_edges().to_lower()
		if BUTTONS.has(key):
			screen.handle_button(int(BUTTONS[key]))

	var menu: Gen2WorldStartMenu = screen.get("_menu")
	var labels: PackedStringArray = PackedStringArray()
	for row: Dictionary in menu.items():
		labels.append(String(row.get("label", "")))
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
	for held: Array in restore:
		mods.set_option(held[0], held[1], held[2])
	print("wrote %s: %d rows %s, cursor on %s" % [
		args[1], labels.size(), str(labels), String(menu.selected_item().get("label", "")),
	])
	quit(0)
