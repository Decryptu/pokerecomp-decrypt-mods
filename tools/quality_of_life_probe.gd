extends SceneTree

## Exercises every decision the Quality of Life mod owns through the production
## host registration. The engine tests own the transactions behind these
## answers; this probe proves the seven switches reach the right contracts.
##
##   godot --headless --path <pokerecomp> -s tools/quality_of_life_probe.gd \
##       --mods -- <gold|silver|crystal>

const MOD_ID: StringName = &"quality_of_life"
const KEYS: Array[StringName] = [
	&"field_moves", &"auto_repel", &"catch_exp", &"pc_access",
	&"move_guide", &"stat_stages", &"weather",
]

var _host: Gen2ModHost
var _original: Dictionary = {}
var _ok: bool = true


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var game: StringName = StringName(args[0]) if not args.is_empty() else &"crystal"
	Gen2ModHost.reset()
	_host = Gen2ModHost.instance()
	_host.set_target_game(game)
	_host.discover()
	_host.load_discovered()
	for key: StringName in KEYS:
		_original[key] = _host.option(MOD_ID, key)
		_switch(key, false)

	_registration()
	_field_moves()
	_repel()
	_catch_experience()
	_pc()
	_move_guide()
	_stages()
	_weather()

	for key: StringName in KEYS:
		_host.set_option(MOD_ID, key, _original[key])
	print("%s: %s" % [game, "ok" if _ok else "FAILED"])
	quit(0 if _ok else 1)


func _registration() -> void:
	_expect(_host.failures().is_empty(), "the host reports no registration failures")
	_expect(_host.options(MOD_ID).size() == KEYS.size(), "seven options registered")
	_expect(_host.field_move_source_ids().has(MOD_ID), "field-move source registered")
	_expect(_host.repel_renewal_ids().has(MOD_ID), "Repel renewal registered")
	_expect(_host.catch_experience_ids().has(MOD_ID), "catch EXP policy registered")
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
	snapshot["hud_visible"] = false
	_expect(_placements(snapshot).is_empty(), "stages hide with the battle HUD")
	_switch(&"stat_stages", false)


func _weather() -> void:
	var snapshot: Dictionary = _snapshot()
	_switch(&"weather", true)
	for weather: int in [Gen2Weather.RAIN, Gen2Weather.SUN, Gen2Weather.SANDSTORM]:
		snapshot["weather"] = weather
		_expect(_placements(snapshot).size() == 1, "weather %d has one icon" % weather)
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
	var result: Dictionary = _host.set_option(MOD_ID, key, 1 if enabled else 0)
	_expect(bool(result.get("ok", false)), "%s can be switched" % key)


func _expect(condition: bool, message: String) -> void:
	print("  %s %s" % ["ok" if condition else "FAIL", message])
	_ok = condition and _ok
