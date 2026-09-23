extends SceneTree

const Staging: GDScript = preload("staging.gd")

const MOD_ID: StringName = &"achievements"
const MOD_ROOT: String = "user://mods/achievements"

const EXTRA_ROWS: int = 1

var _catalogue: GDScript = null
var _ledger: GDScript = null
var _rows: Array[Dictionary] = []
var _kanto: bool = false


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var cartridge: String = args[0] if not args.is_empty() else "crystal"
	Gen2ModHost.reset()
	var data: GameData = GameData.open_argument(cartridge)
	if data == null:
		print("no cache for %s" % cartridge)
		quit(1)
		return
	_catalogue = load("%s/catalogue.gd" % MOD_ROOT)
	_ledger = load("%s/ledger.gd" % MOD_ROOT)
	if _catalogue == null or _ledger == null:
		print("the mod is not installed at %s" % MOD_ROOT)
		quit(1)
		return

	var host: Gen2ModHost = Gen2ModHost.instance()
	var ok: bool = Staging.mod_loaded(host, data, MOD_ID)
	_kanto = host.generation() == RomRegistry.GEN1
	_rows = _catalogue.rows(host.generation())
	ok = _registered(host) and ok
	ok = _table(data) and ok
	ok = _announceable(host, data) and ok
	ok = _edges() and ok
	ok = _once() and ok
	print("%s: %s" % [data.id, "ok" if ok else "FAILED"])
	quit(0 if ok else 1)


func _registered(host: Gen2ModHost) -> bool:
	var ok: bool = true
	if host.page(MOD_ID).is_empty():
		print("no page is registered")
		ok = false
	var opens: bool = false
	for entry: Dictionary in host.menu_entries(Gen2ModHost.MENU_START):
		if StringName(entry.get("action", &"")) == Gen2ModHost.START_ACTION_OPEN_MOD_PAGE \
			and StringName(entry.get("page", &"")) == MOD_ID:
			opens = true
	if not opens:
		print("no start-menu row opens the page")
		ok = false
	var rows: Array = host.page_rows(MOD_ID)
	if rows.size() != _rows.size() + EXTRA_ROWS:
		print("the page lists %d rows" % rows.size())
		ok = false
	print("  page         %s, %d rows, first is %s" % [
		host.page(MOD_ID).get("title", ""), rows.size(),
		rows[0].get("label", "") if not rows.is_empty() else "nothing",
	])
	return ok


func _table(data: GameData) -> bool:
	var ok: bool = true
	var ids: Dictionary = {}
	var badges: Array[int] = []
	for row: Dictionary in _rows:
		var id: StringName = StringName(row["id"])
		if ids.has(id):
			print("two rows are called %s" % id)
			ok = false
		ids[id] = true
		ok = _fits(id, "name", String(row["name"]),
			Gen2MapNameSignPage.NOTICE_COLUMNS) and ok
		ok = _fits(id, "detail", String(row["detail"]),
			Gen2ModPageScreen.TEXT_COLUMNS) and ok
		ok = _art(data, id, row["icon"] as Dictionary) and ok
		if StringName(row["rule"]) == _catalogue.RULE_BADGE:
			badges.append(int(row["at"]))
	print("  rows         %d, %d of them a badge, %d cells wide at most" % [
		_rows.size(), badges.size(), Gen2MapNameSignPage.NOTICE_COLUMNS,
	])
	badges.sort()
	var expected_badges: Array = range(8, 16) if _kanto else range(16)
	if badges != expected_badges:
		print("the badge positions are incomplete or misplaced")
		ok = false
	return ok


func _fits(id: StringName, field: String, text: String, cells: int) -> bool:
	if text.contains("\n"):
		print("%s's %s carries a newline" % [id, field])
		return false
	var width: int = Gen2Text.encode(text).size()
	if width > cells:
		print("%s's %s is %d cells: \"%s\"" % [id, field, width, text])
		return false
	return true


func _art(data: GameData, id: StringName, icon: Dictionary) -> bool:
	if Gen2MapNameSignPage.render_notice_icon(data, icon) == null:
		print("%s names art this cartridge does not carry: %s" % [id, str(icon)])
		return false
	return true


func _announceable(host: Gen2ModHost, _data: GameData) -> bool:
	var ok: bool = true
	var sounds: Dictionary = {}
	for row: Dictionary in _rows:
		var answer: Dictionary = host.request_notice(MOD_ID, {
			"title": "ACHIEVEMENT",
			"line": String(row["name"]),
			"icon": row["icon"],
			"sound": StringName(row["sound"]),
		})
		if not bool(answer.get("ok", false)):
			print("%s cannot be announced: %s" % [row["id"], str(answer)])
			ok = false
		sounds[StringName(row["sound"])] = true
		host.take_notice_request()
	var summary: Dictionary = host.request_notice(MOD_ID, {
		"title": "ACHIEVEMENT",
		"line": "%d UNLOCKED" % _rows.size(),
		"icon": _rows[0]["icon"],
	})
	if not bool(summary.get("ok", false)):
		print("the summary line does not fit: %s" % str(summary))
		ok = false
	host.take_notice_request()
	if sounds.has(&"shine") or Gen2ModHost.NOTICE_SOUNDS.has(&"shine"):
		print("a notice reaches the shiny sparkle")
		ok = false
	print("  notices      %d accepted, sounds %s" % [_rows.size(), str(sounds.keys())])
	return ok


const EDGES: Array = [
	[&"earth_badge", {&"badges": 0x8000}, {&"badges": 0x7FFF}],
	[&"champion", {&"hall_of_fame": true}, {&"hall_of_fame": false}],
	[&"first_catch", {&"caught_count": 1}, {&"caught_count": 0}],
	[&"hundred_caught", {&"caught_count": 100}, {&"caught_count": 99}],
	[&"full_party", {&"party_count": 6}, {&"party_count": 5}],
	[&"level_100", {&"highest_level": 100}, {&"highest_level": 99}],
	[&"shiny", {&"shiny_count": 1}, {&"shiny_count": 0}],
	[&"rich", {&"money": 100000}, {&"money": 99999}],
	[&"high_roller", {&"coins": 1000}, {&"coins": 999}],
	[&"one_day", {&"play_hours": 24}, {&"play_hours": 23}],
]
const JOHTO_EDGES: Array = [
	[&"zephyr_badge", {&"badges": 0x0001}, {&"badges": 0x0002}],
	[&"johto_cleared", {&"badges": 0x00FF}, {&"badges": 0x00FE}],
	[&"kanto_cleared", {&"badges": 0xFFFF}, {&"badges": 0xFF00}],
	[&"mt_silver", {&"beat_red": true}, {&"beat_red": false}],
	[&"pokedex", {&"caught_count": 251}, {&"caught_count": 250}],
	[&"unown", {&"unown_caught": 26}, {&"unown_caught": 25}],
]
const KANTO_EDGES: Array = [
	[&"boulder_badge", {&"badges": 0x0100}, {&"badges": 0x0200}],
	[&"kanto_cleared", {&"badges": 0xFF00}, {&"badges": 0xFE00}],
	[&"pokedex", {&"caught_count": 150}, {&"caught_count": 149}],
]


func _edges() -> bool:
	var ok: bool = true
	var cases: Array = EDGES + (KANTO_EDGES if _kanto else JOHTO_EDGES)
	if cases.size() != _rows.size() - _rows_of(_catalogue.RULE_BADGE).size() + 2:
		print("%d edge cases for %d rows" % [cases.size(), _rows.size()])
		ok = false
	for case: Array in cases:
		var id: StringName = StringName(case[0])
		var row: Dictionary = _catalogue.find(_rows, id)
		if row.is_empty():
			print("no row called %s" % id)
			ok = false
			continue
		if not _catalogue.holds(row, case[1] as Dictionary):
			print("%s is locked by the run that earns it" % id)
			ok = false
		if _catalogue.holds(row, case[2] as Dictionary):
			print("%s unlocks one short of itself" % id)
			ok = false
	var held: Array = _catalogue.held(_rows, {})
	if not held.is_empty():
		print("an empty reading unlocks %s" % str(held))
		ok = false
	print("  edges        %d rules, and nothing at all for an empty reading" % cases.size())
	return ok


func _rows_of(rule: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in _rows:
		if StringName(row["rule"]) == rule:
			out.append(row)
	return out


func _once() -> bool:
	var ok: bool = true
	var masks := Vector2i(0xFF00, 0x0100) if _kanto else Vector2i(0xFFFF, 0x0001)
	var played: Dictionary = {
		&"badges": masks.x, &"hall_of_fame": true, &"caught_count": 100,
		&"party_count": 6, &"highest_level": 100,
	}

	var late: RefCounted = _ledger.new(_rows)
	late.restore({})
	var first: Dictionary = late.scan(played)
	print("  late install %d awarded, quiet %s" % [
		(first["unlocked"] as Array).size(), first["quiet"],
	])
	if (first["unlocked"] as Array).is_empty() or not bool(first["quiet"]):
		print("a save played before the mod is announced one at a time")
		ok = false

	var again: RefCounted = _ledger.new(_rows)
	again.restore(late.stored())
	var reopened: Dictionary = again.scan(played)
	if not (reopened["unlocked"] as Array).is_empty():
		print("reopening the save awards %s again" % str(reopened["unlocked"]))
		ok = false
	if again.progress_counts() != late.progress_counts():
		print("the set did not survive the save")
		ok = false
	print("  reopened     %d of %d, nothing new" % [
		again.progress_counts().x, again.progress_counts().y,
	])

	var fresh: RefCounted = _ledger.new(_rows)
	fresh.restore(_ledger.new(_rows).stored())
	var earned: Dictionary = fresh.scan({&"badges": masks.y})
	if (earned["unlocked"] as Array).size() != 1 or bool(earned["quiet"]):
		print("a badge earned with the mod watching is not announced: %s" % str(earned))
		ok = false

	var many: Dictionary = fresh.scan({&"badges": masks.x})
	if (many["unlocked"] as Array).size() <= _ledger.QUIET_ABOVE \
		or not bool(many["quiet"]):
		print("a batch of unlocks is not summarised: %s" % str(many))
		ok = false
	print("  announced    1 alone, then %d together and quiet" % [
		(many["unlocked"] as Array).size(),
	])

	var older: RefCounted = _ledger.new(_rows)
	older.restore({"version": _ledger.VERSION, "unlocked": ["from_a_later_build"]})
	if not older.has(&"from_a_later_build"):
		print("an unknown id is dropped on the way through")
		ok = false
	if not (older.stored()["unlocked"] as Array).has("from_a_later_build"):
		print("an unknown id does not survive the save")
		ok = false
	return ok
