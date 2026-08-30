extends SceneTree

## Exercises every decision the Quality of Life mod owns through the production
## host registration.

const MOD_ID: StringName = &"quality_of_life"
const KEYS: Array[StringName] = [
	&"field_moves", &"auto_repel", &"catch_exp", &"pc_access", &"run_shoes",
	&"move_guide", &"stat_stages", &"weather",
]
const EXP_SCALE: StringName = &"exp_scale"
const MULTI_EXP: StringName = &"multi_exp"

var _host: Gen2ModHost
var _original: Dictionary = {}
var _original_scale: Variant = null
var _original_share: Variant = null
var _ok: bool = true


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var cartridge: String = args[0] if not args.is_empty() else "crystal"
	Gen2ModHost.reset()
	var data: GameData = GameData.open_argument(cartridge)
	if data == null:
		print("no cache for %s" % cartridge)
		quit(1)
		return
	var game: StringName = data.id
	_host = Gen2ModHost.instance()
	_host.set_target_game(game)
	_host.discover()
	_host.load_discovered()
	for key: StringName in KEYS:
		_original[key] = _host.option(MOD_ID, key)
		_switch(key, false)
	_original_scale = _host.option(MOD_ID, EXP_SCALE)
	_scale(1.0)
	_original_share = _host.option(MOD_ID, MULTI_EXP)
	_share(0.0)

	_registration()
	_field_moves()
	_repel()
	_catch_experience()
	_pc()
	_run_shoes()
	_experience_scale()
	_multi_exp()
	_move_guide()
	_stages()
	_weather()

	for key: StringName in KEYS:
		_host.set_option(MOD_ID, key, _original[key])
	_host.set_option(MOD_ID, EXP_SCALE, _original_scale)
	_host.set_option(MOD_ID, MULTI_EXP, _original_share)
	print("%s: %s" % [game, "ok" if _ok else "FAILED"])
	quit(0 if _ok else 1)


func _registration() -> void:
	_expect(_host.failures().is_empty(), "the host reports no registration failures")
	_expect(_host.options(MOD_ID).size() == KEYS.size() + 2,
		"%d switches, the EXP rate and MULTI EXP registered" % KEYS.size())
	_expect(_host.field_move_source_ids().has(MOD_ID), "field-move source registered")
	_expect(_host.repel_renewal_ids().has(MOD_ID), "Repel renewal registered")
	_expect(_host.catch_experience_ids().has(MOD_ID), "catch EXP policy registered")
	_expect(_host.run_button_ids().has(MOD_ID), "run button registered")
	_expect(_host.experience_scale_ids().has(MOD_ID), "experience scale registered")
	_expect(_host.experience_bystander_ids().has(MOD_ID), "bystander share registered")
	_expect(_host.battle_info_ids().has(MOD_ID), "battle information registered")


func _field_moves() -> void:
	_expect(not Gen2ModHost.allows_item_field_move(57), "field moves are OFF")
	_switch(&"field_moves", true)
	_expect(Gen2ModHost.allows_item_field_move(57), "field moves are ON")
	_switch(&"field_moves", false)


func _repel() -> void:
	var bag: Dictionary = {0x14: 2, 0x2A: 2, 0x2B: 2}
	_expect(_host.repel_renewal_item(bag) == 0, "Repel renewal is OFF")
	_switch(&"auto_repel", true)
	_expect(_host.repel_renewal_item(bag) == 0x14, "ordinary REPEL is first")
	bag.erase(0x14)
	_expect(_host.repel_renewal_item(bag) == 0x2A, "SUPER REPEL is second")
	bag.erase(0x2A)
	_expect(_host.repel_renewal_item(bag) == 0x2B, "MAX REPEL is last")
	_expect(_host.repel_renewal_item({}) == 0, "an empty bag offers nothing")
	_switch(&"auto_repel", false)


func _catch_experience() -> void:
	_expect(not Gen2ModHost.awards_catch_experience(), "catch EXP is OFF")
	_switch(&"catch_exp", true)
	_expect(Gen2ModHost.awards_catch_experience(), "catch EXP is ON")
	_switch(&"catch_exp", false)


## `run_button_held` asks the provider only once B is down, so the button is held
## rather than the policy being read on its own. A script run installs no input
## map of its own, so the cartridge's eight are installed here first.
func _run_shoes() -> void:
	Gen2InputActions.install(Gen2InputActions.defaults())
	Input.action_press(&"gen2_b")
	_expect(not Gen2ModHost.run_button_held(), "running is OFF with B held")
	_switch(&"run_shoes", true)
	_expect(Gen2ModHost.run_button_held(), "running is ON with B held")
	Input.action_release(&"gen2_b")
	_expect(not Gen2ModHost.run_button_held(), "running is OFF with B up")
	_switch(&"run_shoes", false)


func _experience_scale() -> void:
	_expect(is_equal_approx(Gen2ModHost.experience_scale(), 1.0),
		"the EXP rate ships at x1")
	for rung: float in [0.5, 1.5, 2.0, 4.0]:
		_scale(rung)
		_expect(is_equal_approx(Gen2ModHost.experience_scale(), rung),
			"the EXP rate reaches x%s" % rung)
	_scale(1.0)


## The item is the gate, so every rung answers the cartridge with no living
## holder and its own fraction with one.
func _multi_exp() -> void:
	for rung: float in [0.0, 0.5, 1.0]:
		_share(rung)
		_expect(is_equal_approx(_bystander_share([]), 0.0),
			"MULTI EXP %s pays nothing without an EXP. SHARE" % rung)
		_expect(is_equal_approx(_bystander_share([2]), rung),
			"MULTI EXP reaches %s with a holder in the party" % rung)
	_share(0.0)


func _bystander_share(holders: Array) -> float:
	return Gen2ModHost.experience_bystander_share({
		"participants": [0],
		"exp_share_holders": holders,
		"living": [0, 1, 2],
		"is_trainer_battle": false,
	})


func _pc() -> void:
	_expect(not _pc_row(1), "PC row is OFF")
	_switch(&"pc_access", true)
	_expect(not _pc_row(0), "PC row is hidden without a Pokemon")
	_expect(_pc_row(1), "PC row is visible with a Pokemon")
	_switch(&"pc_access", false)


func _move_guide() -> void:
	var snapshot: Dictionary = _snapshot()
	_switch(&"move_guide", true)
	snapshot["enemy_seen_before"] = false
	_expect(_placements(snapshot).is_empty(), "an unseen opponent reveals nothing")
	snapshot["enemy_seen_before"] = true
	var marks: Array = _placements(snapshot)
	_expect(marks.size() == 3, "advantage, resistance and immunity are marked")
	_expect((marks[0] as Dictionary).get("at", Vector2i.ZERO) == Vector2i(18, 13),
		"the guide uses the host's move-row column")
	_switch(&"move_guide", false)


func _stages() -> void:
	var snapshot: Dictionary = _snapshot()
	snapshot["menu_stage"] = "main"
	snapshot["enemy_stages"] = {&"attack": 2, &"defense": -1}
	snapshot["player_stages"] = {&"speed": 1}
	_switch(&"stat_stages", true)
	var rows: Array = _placements(snapshot)
	_expect(rows.size() == 3, "only three non-zero stat stages are shown")
	_expect((rows[0] as Dictionary).get("text", "") == "ATK2", "positive stage text")
	_expect((rows[1] as Dictionary).get("text", "") == "DEF-1", "negative stage text")
	_expect(bool((rows[0] as Dictionary).get("field", false)),
		"enemy stages ask for an interface field")
	_expect((rows[2] as Dictionary).get("at", Vector2i.ZERO) == Vector2i(1, 13),
		"player stages stay inside the lower-left panel")
	_expect(not bool((rows[2] as Dictionary).get("field", false)),
		"player stages reuse the command panel field")
	snapshot["hud_visible"] = false
	_expect(_placements(snapshot).is_empty(), "stages hide with the battle HUD")
	_full_stages()
	_switch(&"stat_stages", false)


func _full_stages() -> void:
	var every: Dictionary = {}
	for key: StringName in [
		&"attack", &"defense", &"speed", &"sp_attack", &"sp_defense",
		&"accuracy", &"evasion",
	]:
		every[key] = -1
	var snapshot: Dictionary = _snapshot()
	snapshot["menu_stage"] = "main"
	snapshot["enemy_stages"] = every
	snapshot["player_stages"] = every
	var inside: bool = true
	for placement: Dictionary in _placements(snapshot):
		var at: Vector2i = placement.get("at", Vector2i.ZERO)
		var wide: int = String(placement.get("text", "")).length()
		inside = inside and at.y >= 0 and at.y < 18 and at.x >= 0 and at.x + wide <= 20
	_expect(inside, "seven stages a side stay on the screen's own grid")
	_expect(
		_host.failures().is_empty(),
		"the host refused none of this mod's annotations"
	)


func _weather() -> void:
	var snapshot: Dictionary = _snapshot()
	_switch(&"weather", true)
	for weather: int in [Gen2Weather.RAIN, Gen2Weather.SUN, Gen2Weather.SANDSTORM]:
		snapshot["weather"] = weather
		var placements: Array = _placements(snapshot)
		_expect(placements.size() == 1, "weather %d has one icon" % weather)
		_expect(bool((placements[0] as Dictionary).get("field", false)),
			"weather %d asks for an interface field" % weather)
	snapshot["weather"] = 0
	_expect(_placements(snapshot).is_empty(), "clear weather has no icon")
	_switch(&"weather", false)


func _snapshot() -> Dictionary:
	return {
		"player_stages": {},
		"enemy_stages": {},
		"enemy_seen_before": true,
		"weather": 0,
		"hud_visible": true,
		"enemy_hud_visible": true,
		"player_hud_visible": true,
		"menu_stage": "move",
		"move_rows": [
			{"effectiveness": 20}, {"effectiveness": 5},
			{"effectiveness": 0}, {"effectiveness": 10},
		],
		"move_rows_at": Vector2i(2, 13),
		"move_rows_step": Vector2i(0, 1),
		"move_rows_right": 18,
		"neutral": 10,
	}


func _placements(snapshot: Dictionary) -> Array:
	return _host.battle_info_placements(snapshot)


func _pc_row(party_count: int) -> bool:
	for entry: Dictionary in _host.start_menu_entries({
		"party_count": party_count, "pokedex": false, "pokegear": false,
	}):
		if StringName(entry.get("kind", &"")) == MOD_ID:
			return StringName(entry.get("action", &"")) \
				== Gen2ModHost.START_ACTION_OPEN_BILLS_PC
	return false


func _switch(key: StringName, enabled: bool) -> void:
	var result: Dictionary = _host.set_option(MOD_ID, key, int(enabled))
	_expect(bool(result.get("ok", false)), "%s can be switched" % key)


func _scale(rung: float) -> void:
	var result: Dictionary = _host.set_option(MOD_ID, EXP_SCALE, rung)
	_expect(bool(result.get("ok", false)), "the EXP rate can be set to x%s" % rung)


func _share(rung: float) -> void:
	var result: Dictionary = _host.set_option(MOD_ID, MULTI_EXP, rung)
	_expect(bool(result.get("ok", false)), "MULTI EXP can be set to %s" % rung)


func _expect(condition: bool, message: String) -> void:
	print("  %s %s" % ["ok" if condition else "FAIL", message])
	_ok = condition and _ok
