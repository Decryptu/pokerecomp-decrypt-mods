extends SceneTree

## Photographs the battle marks: a wild battle with MOVE GUIDE and STAT STAGES
## on, at the main menu and at the move list.

const Staging: GDScript = preload("staging.gd")

const MOD_ID: StringName = &"quality_of_life"
const WINDOW := Vector2i(1152, 648)
const SEED: int = 7
const SETTLE_FRAMES: int = 4
const MENU_PRESSES: int = 40
const PRESS_FRAMES: int = 12
const ENEMY: int = 74
const LEVEL: int = 8
## What a fight has done by the time the picture is taken.
const STAGES: Array = [[Gen2Battle.PLAYER, "speed", 1], [Gen2Battle.PLAYER, "sp_attack", -1],
	[Gen2Battle.ENEMY, "defense", 2]]

var _screen: Gen2BattleScreen = null
var _out: String = ""
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -- <cartridge> <out.png>")
		quit(2)
		return
	Gen2ModHost.reset()
	var data: GameData = GameData.open_argument(args[0])
	if data == null:
		print("no cache for %s" % args[0])
		quit(1)
		return
	_out = args[1]
	if PokeToolPath.refuses(_out):
		quit(2)
		return
	var host: Gen2ModHost = Gen2ModHost.instance()
	if not Staging.mod_loaded(host, data, MOD_ID):
		quit(1)
		return
	for key: StringName in [&"move_guide", &"stat_stages"]:
		host.set_option(MOD_ID, key, 1)
	root.set_content_scale_size(WINDOW)
	root.size = WINDOW
	_screen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	_screen.set_data(data)
	_screen.set_random_seed(SEED)
	root.add_child(_screen)
	current_scene = _screen
	_screen.set_process(false)


func _process(_delta: float) -> bool:
	if _screen == null:
		return true
	_screen.set_process(false)
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	match _frames - SETTLE_FRAMES:
		0:
			return _stage()
		1:
			_write(_out.get_basename() + "_menu.png")
			_press(PokeButton.A)
		2:
			_write(_out)
			quit()
			return true
	return false


## The annotation layer redraws on a menu push, so the stages are followed by a
## list opened and closed.
func _stage() -> bool:
	if not _screen.start_world_battle({"values": {
		"kind": &"wild", "pokemon": ENEMY, "level": LEVEL,
	}}):
		print("could not stage a wild battle")
		quit(1)
		return true
	_screen.set_dex_context(true, false, true)
	while _screen.intro_running():
		_screen.advance_frame()
	for _pass: int in MENU_PRESSES:
		if String(_screen.info_snapshot().get("menu_stage", "")) == "main":
			break
		_press(PokeButton.A)
	var battle: Gen2Battle = _screen.get("_battle")
	for stage: Array in STAGES:
		battle.mon(int(stage[0])).change_stage(String(stage[1]), int(stage[2]))
	_press(PokeButton.A)
	_press(PokeButton.B)
	return false


func _press(button: int) -> void:
	_screen.press_button(button)
	for _frame: int in PRESS_FRAMES:
		_screen.advance_frame()


func _write(path: String) -> void:
	var error: Error = root.get_texture().get_image().save_png(path)
	print("%s %s" % ["wrote" if error == OK else "could not write", path])
