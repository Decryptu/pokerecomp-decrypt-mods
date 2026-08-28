extends SceneTree

## Photographs the Achievements mod's two surfaces, through the real world
## screen, with the mod itself raising them.
##
##   Godot --path <pokerecomp> --resolution 800x720 \
##       -s tools/achievements_shot.gd -- \
##       <cartridge> <out.png> [kind] [badges] [group,number] [cell] [flags ...]
##
## THE RESOLUTION IS PART OF THE COMMAND, for the reason
## `tools/shiny_charm_shot.gd` gives: 800x720 is the hardware's 160x144 at a
## whole times five and any other size shears the art.
##
## `kind` is `notice` or `page`. `badges` is how many Johto badges the run has
## already won when the picture is taken; the notice is of the one after them,
## so `badges 0` photographs the ZEPHYRBADGE being won.
##
## `group,number` and `cell` say where the player is standing, and both default
## to the place the default badge is actually won: in front of FALKNER in the
## VIOLET GYM. THE CELL IS CHECKED. A cell the player could not be standing on
## is refused rather than photographed, because the screen puts the player
## wherever it is told and a picture of somebody inside a tree is a picture of
## nothing that ever happened. `start_cell` defaults to 4,4 and that is exactly
## how the first thumbnail was taken standing in the middle of a forest.
##
## Nothing is staged but the badge. The tool opens a save, which is what hands
## the mod its ledger, then sets one engine flag on the live run the way a gym
## script does. The host's own progress reading sees that field move, the mod
## asks for a banner, and the world screen raises it on the next frame it can.
## So the wording, the icon, the sound and the moment it lands are the mod's and
## the host's rather than this tool's.
##
## Flags, in any order after the cell:
##
## | `thumbnail` | Centre the shot on the 1280x720 white field a mod thumbnail is |
## | `framed` | The hardware's own 160x144 instead of SCREEN FILL. What a small
##   interior wants, since filling the surface with a map narrower than it only
##   buys more of the void past its edge |
## | `view=voxel3d` | Raise the banner over another registered view rather than
##   over the flat one. A notice is the world screen's own layer and a view is
##   the world under it, and whether the second covers the first is a question
##   only a picture answers |
##
## Rendering needs a display.

const MOD_ID: StringName = &"achievements"
const DEFAULT_WINDOW := Vector2i(800, 720)

## The white field a mod's thumbnail is, the hardware picture centred on it
## rather than stretched to fill.
const THUMBNAIL_SIZE := Vector2i(1280, 720)

## The VIOLET GYM, and the cell in front of FALKNER: where the ZEPHYRBADGE is
## actually won, which is `GameData.catalog()`'s own answer for badge 0. He
## stands on 5,1 and the row below him is the only way anybody reaches him.
const DEFAULT_MAP := Vector2i(10, 7)
const DEFAULT_CELL := Vector2i(5, 2)
const DEFAULT_BADGES: int = 0
const JOHTO_BADGES: int = 8

## The driver frame the run is staged on, by which time the screen has built its
## world.
const STAGE_ON: int = 6
## Driver frames between the staging and the shutter.
##
## THE SHUTTER HAS TO WAIT. Every world frame here is spent by hand, and a
## banner raised by one of them is not on screen until the renderer has drawn a
## frame of its own; driving and shooting inside one driver frame never gives it
## that. Four runs of this tool photographed an empty map that way, and the only
## thing that brought the banner back was a `print` slow enough to let a real
## frame through. `tools/preview_world.gd` waits the same way.
const SHUTTER_WAIT: int = 18
## World frames spent waiting for a banner before giving up.
const FRAME_CAP: int = 240
## World frames spent letting a change reach the host's reading, which the world
## screen takes once a pass.
const SETTLE_FRAMES: int = 6

var _screen: Gen2WorldScreen = null
var _out: String = ""
var _kind: StringName = &"notice"
var _badges: int = DEFAULT_BADGES
var _thumbnail: bool = false
var _frames: int = 0
var _waited: int = 0
var _staged: bool = false
var _framed: bool = false
## The registered view to raise the banner over, empty for the screen's own.
var _view: StringName = &""
var _cell := DEFAULT_CELL
var _data: GameData = null


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -- <cartridge> <out.png> [kind] [badges] [group,number] [cell] [thumbnail]")
		quit(2)
		return
	_out = args[1]
	if Gen2ToolPath.refuses(_out):
		quit(2)
		return
	_kind = StringName(args[2]) if args.size() > 2 else &"notice"
	if _kind != &"notice" and _kind != &"page":
		print("kind is notice or page, not ", _kind)
		quit(2)
		return
	_badges = clampi(int(args[3]) if args.size() > 3 else DEFAULT_BADGES, 0, JOHTO_BADGES)
	var map: Vector2i = _pair(args[4] if args.size() > 4 else "", DEFAULT_MAP)
	_cell = _pair(args[5] if args.size() > 5 else "", DEFAULT_CELL)
	for index: int in range(6, args.size()):
		match String(args[index]):
			"thumbnail":
				_thumbnail = true
			"framed":
				_framed = true
			_:
				if String(args[index]).begins_with("view="):
					_view = StringName(String(args[index]).substr(5))
					continue
				print("no flag called ", args[index])
				quit(2)
				return

	_data = GameData.open_argument(args[0])
	if _data == null:
		print("no cache for ", args[0])
		quit(1)
		return
	## A `-s` run loads no mods of its own, so the tool loads them the way the
	## other shot tools do: the production path, against this cartridge.
	##
	## No setting of this mod's is touched anywhere here. A tool that turned one
	## off to get its picture would leave the player's own choice changed, and
	## the page covers the screen, so a banner under it is not in the shot.
	var host: Gen2ModHost = Gen2ModHost.instance()
	host.set_target_game(_data.id)
	host.discover()
	host.load_discovered()
	var loaded: bool = false
	for manifest: Gen2ModManifest in host.manifests():
		loaded = loaded or manifest.id == MOD_ID
	if not loaded:
		print("the mod is not installed")
		quit(1)
		return
	if not _view.is_empty():
		print("view       ", String(_view), " ", str(host.select_view(_view)))
	if not host.failures().is_empty():
		print("failures   ", str(host.failures()))

	## In memory for this process: nothing here writes the options file, and the
	## screen takes the option again whenever it applies its own share of it, so
	## this means the same thing whichever order it is set in.
	if _framed:
		Gen2OptionsStore.current().screen_fill = false
	DisplayServer.window_set_size(DEFAULT_WINDOW)
	root.set_content_scale_size(DEFAULT_WINDOW)
	root.size = DEFAULT_WINDOW
	var packed: PackedScene = load("res://game/world/world_screen.tscn")
	_screen = packed.instantiate() as Gen2WorldScreen
	_screen.map_group = map.x
	_screen.map_number = map.y
	## Without this the screen uses `start_cell`'s own 4,4, which is a cell on no
	## map in particular and was in the middle of a wood on the first one tried.
	_screen.start_cell = _cell
	## Pinned so two captures of one map are one picture: the seed the screen
	## resolves is what a wandering NPC's own generator is built from.
	_screen.encounter_seed = 1
	_screen.set_data(_data)
	root.add_child(_screen)
	current_scene = _screen


func _process(_delta: float) -> bool:
	## Taken away on EVERY driver frame rather than once: Godot turns `_process`
	## back on for a node whose script has one, and a screen counting hardware
	## frames off wall-clock delta photographs a different frame of every
	## animation each run. `tools/shiny_charm_shot.gd` lost three runs to this.
	_screen.set_process(false)
	_frames += 1
	if _frames < STAGE_ON:
		return false
	if _frames == STAGE_ON:
		_stage()
		return false
	if not _staged:
		return false
	_waited += 1
	if _waited < SHUTTER_WAIT:
		return false
	## The window rather than the hardware buffer: a banner raised over the map
	## is an interface node the screen adds while it runs, and the sub-viewport
	## a clean capture reads does not carry it.
	##
	## SCREEN FILL is left where it ships unless `framed` says otherwise. On, an
	## outdoor map fills the surface with more map, which is the picture it is
	## for; a map smaller than the surface just shows more of the void past its
	## own edge, which `tools/preview_world.gd` draws the same way and which no
	## flag here can crop away.
	var image: Image = Gen2ToolPath.capture(root)
	if image == null:
		quit(1)
		return true
	if not _write(image):
		quit(1)
		return true
	print("wrote ", _out, " (", image.get_width(), "x", image.get_height(),
		"), ", _kind, " over map ", _screen.map_group, ",", _screen.map_number)
	quit(0)
	return true


## Opens the slot, which is what hands the mod its ledger, wins the badges the
## run already has, and drives the surface being photographed up.
func _stage() -> void:
	## The map and cell readout and the shortcut legend are the harness's, not
	## the game's, and belong in no picture of it.
	_screen.hide_debug_readout()
	var save: Gen2SaveData = _screen.active_save()
	if save == null:
		save = Gen2SaveStore.create_development_save(_data, 0)
		_screen.set_save(save)
	Gen2ModHost.instance().activate_save(save)
	var world: Gen2WorldAPI = _screen.get("_world") as Gen2WorldAPI
	if world == null or world.state == null:
		print("the screen opened no world")
		quit(1)
		return
	if not _standable(world):
		return
	_face_the_leader()
	var crystal: bool = Gen2WorldState.is_crystal_profile(_data)
	for badge: int in _badges:
		world.state.set_engine_flag(Gen2WorldState.badge_flag(badge, crystal))
	_spend_map_banner()
	if _kind == &"page":
		_screen.advance_frames(SETTLE_FRAMES)
		_screen.call("_open_mod_page", MOD_ID)
		_screen.advance_frame()
		_staged = true
		return
	## The badge this picture is of, won only now: the map raises its OWN
	## landmark banner as it opens and a notice is drawn through that same one,
	## so a badge won any earlier is photographed as the name of the town.
	world.state.set_engine_flag(
		Gen2WorldState.badge_flag(mini(_badges, JOHTO_BADGES - 1), crystal)
	)
	_staged = _raise_notice()


## Refuses a cell the player could not be standing on.
##
## The screen puts the player wherever `start_cell` says, walkable or not, and a
## picture of somebody inside a tree is a picture of nothing that ever happened.
## The question is the cartridge's own: `CollisionPermissionTable` through
## `Gen2WorldCollision.is_walkable`, which is what the overworld asks of a cell
## before it lets a step onto it.
func _standable(world: Gen2WorldAPI) -> bool:
	var map: Gen2WorldMap = world.current_map
	if map == null:
		print("the screen opened no map")
		quit(1)
		return false
	if _cell.x < 0 or _cell.y < 0 \
		or _cell.x >= map.collision_width or _cell.y >= map.collision_height:
		print("cell ", _cell, " is off map ", _screen.map_group, ",",
			_screen.map_number, ", which is ", map.collision_width, "x",
			map.collision_height, " cells")
		quit(1)
		return false
	if not Gen2WorldCollision.is_walkable(world.collision_code_at(_cell)):
		print("cell ", _cell, " on map ", _screen.map_group, ",",
			_screen.map_number, " is not a cell the player can stand on")
		quit(1)
		return false
	for object: Dictionary in map.events.get("objects", []):
		if Vector2i(int(object.get("x", -1)), int(object.get("y", -1))) == _cell:
			print("cell ", _cell, " is where one of the map's own people stands")
			quit(1)
			return false
	return true


## Turns the player to face whoever is standing on the cell above, which is how
## a gym leader is talked to. The press is refused as a step because that cell
## is occupied, and a refused step is exactly what turns the sprite.
func _face_the_leader() -> void:
	_screen.move_up()
	_screen.advance_frames(SETTLE_FRAMES)


## Runs the map's own name sign out, so the next banner up is the mod's.
func _spend_map_banner() -> void:
	for frame: int in FRAME_CAP:
		if frame >= SETTLE_FRAMES and _screen.map_name_sign_passes() <= 0:
			return
		_screen.advance_frame()


## Spends world frames until the mod's banner is up and settled.
func _raise_notice() -> bool:
	for _frame: int in FRAME_CAP:
		_screen.advance_frame()
		var passes: int = _screen.map_name_sign_passes()
		## Up, and past the frame it was raised on: the banner is brought down
		## one frame after the ask, the way `PlaceMapNameSign` leaves it.
		if passes > 0 and passes < Gen2WorldAPI.MAP_NAME_SIGN_PASSES - 1:
			_screen.advance_frames(SETTLE_FRAMES)
			return true
	print("no banner was raised in ", FRAME_CAP, " frames")
	quit(1)
	return false


## A `x,y` argument, or [param fallback] where it is absent or malformed.
func _pair(text: String, fallback: Vector2i) -> Vector2i:
	var parts: PackedStringArray = text.split(",", false)
	if parts.size() != 2:
		return fallback
	return Vector2i(int(parts[0]), int(parts[1]))


func _write(image: Image) -> bool:
	if not _thumbnail:
		if image.save_png(_out) != OK:
			print("could not write ", _out)
			return false
		return true
	if image.get_width() > THUMBNAIL_SIZE.x or image.get_height() > THUMBNAIL_SIZE.y:
		print("a ", image.get_width(), "x", image.get_height(),
			" shot does not fit ", THUMBNAIL_SIZE)
		return false
	var canvas := Image.create(
		THUMBNAIL_SIZE.x, THUMBNAIL_SIZE.y, false, image.get_format()
	)
	canvas.fill(Color.WHITE)
	@warning_ignore("integer_division")
	var at := Vector2i(
		int((THUMBNAIL_SIZE.x - image.get_width()) / 2),
		int((THUMBNAIL_SIZE.y - image.get_height()) / 2)
	)
	canvas.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), at)
	if canvas.save_webp(_out, true) != OK:
		print("could not write ", _out)
		return false
	return true
