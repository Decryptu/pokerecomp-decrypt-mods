extends RefCounted

## What the fourth page says, as placements on the screen's own tile grid.
##
## The lower half is rows 8 to 17, and this page uses the blue page's shape: a
## divider down one column, labels beside it, and a list stepped two rows at a
## time. It carries two number columns instead of one, with the names printed
## once and read across.
##
## Five rows, because five is what the hardware stores. HP has no DV of its own
## and is assembled from the low bit of the other four
## ([method Gen2Stats.hp_dv]), and stat experience is one counter for SPECIAL
## that both special stats read.

## `LoadBluePage`'s own column, so the two pages line up when turned between.
const DIVIDER_COLUMN: int = 10

const HEADER_ROW: int = 8
const FIRST_ROW: int = 9
## `wListMovesLineSpacing`'s two rows, which every list on this screen steps.
const ROW_STEP: int = 2

const NAME_COLUMN: int = 0
## Eight and not seven: DEFENSE and SPECIAL are seven tiles wide, so a number at
## seven butts against the name. Both columns end where the cartridge's own
## numbers end, at the divider and at column 19.
const DV_COLUMN: int = 8
const EXP_COLUMN: int = 15
const HEADER_AT: Vector2i = Vector2i(DV_COLUMN, HEADER_ROW)
const EXP_HEADER_AT: Vector2i = Vector2i(12, HEADER_ROW)

const DV_LABEL: String = "DV"
const EXP_LABEL: String = "STAT EXP"

const DV_DIGITS: int = 2
const EXP_DIGITS: int = 5

## The five the hardware keeps, named and ordered as the stats screen does.
const ROWS: Array[String] = ["HP", "ATTACK", "DEFENSE", "SPECIAL", "SPEED"]
const EXP_KEYS: Array[String] = ["hp", "attack", "defense", "special", "speed"]


## [param page] is the stats screen's snapshot. An egg never reaches here, since
## `EggStatsScreen` replaces the pages rather than being one.
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


## In [constant ROWS]' order. HP's is derived, by the reading that also decides
## shininess.
static func _dvs(word: int) -> Array[int]:
	return [
		Gen2Stats.hp_dv(word),
		Gen2Stats.attack_dv(word),
		Gen2Stats.defense_dv(word),
		Gen2Stats.special_dv(word),
		Gen2Stats.speed_dv(word),
	]
