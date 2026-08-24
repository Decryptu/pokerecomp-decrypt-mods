extends SceneTree

## Photographs the start menu's own list with the installed mods loaded, on a
## save that has unlocked every row the cartridge gates.
##
## The list is where a mod's `MENU_START` entry lands, and it holds more rows
## than the screen has room for: eight fit and a fully unlocked save with MODS
## and one mod row is ten. The host makes the box a window over them, so what
## has to be photographed is not one screen but two, the top of the list and the
## bottom, which is why `presses` exists. One press of UP from the top row wraps
## to EXIT, which is the shortest proof that the last row is reachable.
##
##   godot --headless --path <pokerecomp> -s tools/start_menu_shot.gd --mods -- \
##       <game> <out.png> [presses] [scale] [settings]
##
## `presses` is a comma-separated button list driven into the list: `u` `d`.
## `settings` is a comma-separated `<mod id>:<key>=<value>` list applied after
## the mods load, since a row behind an off-by-default switch is a row nothing
## photographs. The values are not written back: the store is left as it was.

const NEW_BARK_GROUP: int = 24
const NEW_BARK_MAP: int = 7
## `Gen2WorldStartMenu`'s own two, which gate the #DEX and <POKEGEAR> rows.
const ENGINE_POKEGEAR: int = 4
const ENGINE_POKEDEX: int = 11

const BUTTONS: Dictionary = {"u": Gen2Button.UP, "d": Gen2Button.DOWN}


## The screen builds its panel in `_ready`, which does not run until the tree has
## processed a frame, so the shot is taken from here rather than `_initialize`.
func _process(_delta: float) -> bool:
	_capture()
	return true


func _capture() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -- <game> <out.png> [presses] [scale]")
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
	var data: GameData = GameData.open(StringName(args[0]))
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
	## No slot on disk, so nothing this photographs is written anywhere.
	var save: Gen2SaveData = Gen2SaveStore.create_development_save(data, 0)
	if save == null:
		print("the %s cache builds no development save" % args[0])
		quit(1)
		return
	## The #MON row and a mod's PC row are both gated on a party, and the menu
	## reads the world's summary rather than the save's, so the party is
	## mirrored into it the way a running game does.
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
