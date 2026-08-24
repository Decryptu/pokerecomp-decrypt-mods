extends RefCounted

## Small monochrome marks on the cartridge's own 20x18 battle interface. The
## host supplies exact effectiveness and live state, so this file owns layout
## and iconography only.

const Options := preload("options.gd")

## Official later-game meanings: circle with a centre dot for an advantage,
## triangle for a resisted move and X for no effect. Eight 1bpp rows, bit 7 on
## the left, are the API's native one-tile form.
const MARK_SUPER: Array[int] = [0x3C, 0x42, 0x81, 0x99, 0x99, 0x81, 0x42, 0x3C]
const MARK_RESISTED: Array[int] = [0x00, 0x10, 0x38, 0x38, 0x7C, 0x7C, 0xFE, 0x00]
const MARK_IMMUNE: Array[int] = [0x00, 0x42, 0x24, 0x18, 0x18, 0x24, 0x42, 0x00]

## The cartridges have no weather HUD tiles. These use the same one-bit weight
## as their battle symbols: a ray-ring sun, a cloud with drops and blowing sand.
const WEATHER_SUN: Array[int] = [0x24, 0x18, 0x7E, 0xDB, 0xDB, 0x7E, 0x18, 0x24]
const WEATHER_RAIN: Array[int] = [0x00, 0x38, 0x7C, 0xFE, 0x7C, 0x00, 0x52, 0x24]
const WEATHER_SAND: Array[int] = [0x00, 0x7C, 0x02, 0x3C, 0x40, 0x3E, 0x00, 0x6A]
const WEATHER_AT: Vector2i = Vector2i(0, 5)

const STAGE_ORDER: Array[StringName] = [
	&"attack", &"defense", &"speed", &"sp_attack", &"sp_defense",
	&"accuracy", &"evasion",
]
const STAGE_LABELS: Dictionary = {
	&"attack": "ATK",
	&"defense": "DEF",
	&"speed": "SPD",
	&"sp_attack": "SP.A",
	&"sp_defense": "SP.D",
	&"accuracy": "ACC",
	&"evasion": "EVA",
}
## With the command menu open, these are the cartridge's two unused regions:
## above the enemy picture and inside the blank lower-left panel. The summaries
## yield those cells to the move list, whose type box occupies the lower panel.
const ENEMY_STAGES_AT: Vector2i = Vector2i(13, 0)
const PLAYER_STAGES_AT: Vector2i = Vector2i(1, 12)

var _host: Gen2ModHost


func _init(host: Gen2ModHost) -> void:
	_host = host


func annotate_battle(snapshot: Dictionary) -> Array:
	var out: Array = []
	if Options.enabled(_host, Options.MOVE_GUIDE):
		out.append_array(_effectiveness(snapshot))
	if Options.enabled(_host, Options.STAT_STAGES):
		out.append_array(_stages(snapshot))
	if Options.enabled(_host, Options.WEATHER):
		out.append_array(_weather(snapshot))
	return out


func _effectiveness(snapshot: Dictionary) -> Array:
	var out: Array = []
	if String(snapshot.get("menu_stage", "")) != "move" \
		or not bool(snapshot.get("enemy_seen_before", false)):
		return out
	var rows: Array = snapshot.get("move_rows", []) as Array
	var neutral: int = int(snapshot.get("neutral", 10))
	var rows_at: Vector2i = snapshot.get("move_rows_at", Vector2i.ZERO) as Vector2i
	var step: Vector2i = snapshot.get("move_rows_step", Vector2i(0, 1)) as Vector2i
	var right: int = int(snapshot.get("move_rows_right", 18))
	for index: int in rows.size():
		var against: int = int((rows[index] as Dictionary).get("effectiveness", neutral))
		if against == neutral:
			continue
		var mark: Array[int] = MARK_IMMUNE if against == 0 else (
			MARK_SUPER if against > neutral else MARK_RESISTED
		)
		var at: Vector2i = rows_at + step * index
		out.append({"tile": mark, "at": Vector2i(right, at.y)})
	return out


func _stages(snapshot: Dictionary) -> Array:
	if not bool(snapshot.get("hud_visible", false)) \
		or String(snapshot.get("menu_stage", "")) == "move":
		return []
	var out: Array = []
	if bool(snapshot.get("enemy_hud_visible", false)):
		out.append_array(_stage_side(
			snapshot.get("enemy_stages", {}) as Dictionary, ENEMY_STAGES_AT
		))
	if bool(snapshot.get("player_hud_visible", false)):
		out.append_array(_stage_side(
			snapshot.get("player_stages", {}) as Dictionary, PLAYER_STAGES_AT
		))
	return out


func _stage_side(stages: Dictionary, start: Vector2i) -> Array:
	var out: Array = []
	var at: Vector2i = start
	for key: StringName in STAGE_ORDER:
		var stage: int = int(stages.get(key, stages.get(String(key), 0)))
		if stage == 0:
			continue
		## The cartridge font has no plus sign. A bare positive number and a
		## printed minus preserve one compact, unambiguous row per active stage.
		out.append({
			"text": "%s%d" % [String(STAGE_LABELS[key]), stage],
			"at": at,
		})
		at += Vector2i(0, 1)
	return out


func _weather(snapshot: Dictionary) -> Array:
	if not bool(snapshot.get("hud_visible", false)):
		return []
	var tile: Array[int] = []
	match int(snapshot.get("weather", 0)):
		Gen2Weather.RAIN:
			tile = WEATHER_RAIN
		Gen2Weather.SUN:
			tile = WEATHER_SUN
		Gen2Weather.SANDSTORM:
			tile = WEATHER_SAND
	if tile.is_empty():
		return []
	return [{"tile": tile, "at": WEATHER_AT}]
