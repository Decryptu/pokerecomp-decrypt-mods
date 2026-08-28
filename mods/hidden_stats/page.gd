extends RefCounted

## What the fourth page says, as placements on the screen's own tile grid.

const DIVIDER_COLUMN: int = 10

const HEADER_ROW: int = 8
const FIRST_ROW: int = 9
const ROW_STEP: int = 2

const NAME_COLUMN: int = 0
const DV_COLUMN: int = 8
const EXP_COLUMN: int = 15
const HEADER_AT: Vector2i = Vector2i(DV_COLUMN, HEADER_ROW)
const EXP_HEADER_AT: Vector2i = Vector2i(12, HEADER_ROW)

const DV_LABEL: String = "DV"
const EXP_LABEL: String = "STAT EXP"

const DV_DIGITS: int = 2
const EXP_DIGITS: int = 5

const ROWS: Array[String] = ["HP", "ATTACK", "DEFENSE", "SPECIAL", "SPEED"]
const EXP_KEYS: Array[String] = ["hp", "attack", "defense", "special", "speed"]


static func build(page: Dictionary) -> Array:
	var dvs: int = int(page.get("dvs", 0))
	var trained: Dictionary = page.get("stat_exp", {})
	var out: Array = [
		{"divider": DIVIDER_COLUMN},
		{"text": DV_LABEL, "at": HEADER_AT},
		{"text": EXP_LABEL, "at": EXP_HEADER_AT},
	]
	var values: Array[int] = _dvs(dvs)
	for index: int in ROWS.size():
		var row: int = FIRST_ROW + index * ROW_STEP
		out.append({"text": ROWS[index], "at": Vector2i(NAME_COLUMN, row)})
		out.append({
			"text": str(values[index]).lpad(DV_DIGITS),
			"at": Vector2i(DV_COLUMN, row),
		})
		out.append({
			"text": str(int(trained.get(EXP_KEYS[index], 0))).lpad(EXP_DIGITS),
			"at": Vector2i(EXP_COLUMN, row),
		})
	return out


static func _dvs(word: int) -> Array[int]:
	return [
		Gen2Stats.hp_dv(word),
		Gen2Stats.attack_dv(word),
		Gen2Stats.defense_dv(word),
		Gen2Stats.special_dv(word),
		Gen2Stats.speed_dv(word),
	]
