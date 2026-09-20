extends RefCounted

## The move animation, drawn as the hardware drew it: `wShadowOAM` blitted into
## one 160x144 picture the renderer lays over the fight.

const Arena: GDScript = preload("arena.gd")

const TILE: int = 8

var _data: GameData = null
var _colors: Gen2BattleColors = null

var _enemy_pixels := PackedByteArray()
var _player_pixels := PackedByteArray()
var _enemy_species: int = -1
var _player_species: int = -1


func _init(data: GameData, colors: Gen2BattleColors) -> void:
	_data = data
	_colors = colors


func image(
	view: Dictionary, player_off := Vector2.ZERO, enemy_off := Vector2.ZERO
) -> Image:
	if _data == null:
		return null
	var sprites: Array = view.get("anim_sprites", [])
	if sprites.is_empty():
		return null
	_ensure_pixels(view)

	var into: Image = Image.create_empty(
		Gen2Screen.WIDTH, Gen2Screen.HEIGHT, false, Image.FORMAT_RGBA8
	)
	var drawn: int = 0
	for entry: Variant in sprites:
		if entry is Dictionary:
			drawn += int(_blit(into, entry as Dictionary, view, player_off, enemy_off))
	return into if drawn > 0 else null


static func _between(at: Vector2) -> float:
	var axis: Vector2 = Arena.ENEMY_MARK - Arena.PLAYER_MARK
	var span: float = axis.length_squared()
	if span <= 0.0:
		return 0.0
	return clampf((at - Arena.PLAYER_MARK).dot(axis) / span, 0.0, 1.0)


func _blit(
	into: Image, sprite: Dictionary, view: Dictionary,
	player_off: Vector2, enemy_off: Vector2
) -> bool:
	var pixels: PackedByteArray = _tile(int(sprite.get("tile", 0)), view)
	if pixels.is_empty():
		return false
	var attributes: int = int(sprite.get("attributes", 0))
	var left: int = int(sprite.get("x", 0)) - 8
	var top: int = int(sprite.get("y", 0)) - 16
	var lookup: Image = _colors.object_image(pixels, attributes, left, top)
	var shift: Vector2 = player_off.lerp(
		enemy_off, _between(Vector2(float(left) + 4.0, float(top) + 4.0))
	).round()
	left += int(shift.x)
	top += int(shift.y)
	var clip := Rect2i(0, 0, TILE, TILE)
	if left < 0:
		clip.position.x = -left
		clip.size.x += left
		left = 0
	if top < 0:
		clip.position.y = -top
		clip.size.y += top
		top = 0
	clip.size.x = mini(clip.size.x, Gen2Screen.WIDTH - left)
	clip.size.y = mini(clip.size.y, Gen2Screen.HEIGHT - top)
	if clip.size.x <= 0 or clip.size.y <= 0:
		return false
	into.blend_rect(lookup, clip, Vector2i(left, top))
	return true


func _tile(tile: int, view: Dictionary) -> PackedByteArray:
	var window: Array = view.get("anim_tiles", [])
	var at: int = tile - Gen2BattleAnimObject.BASE_TILE
	if at < 0 or at >= window.size() or not window[at] is Dictionary:
		return PackedByteArray()
	var entry: Dictionary = window[at]
	if entry.has("battler_tile"):
		return _battler_tile(int(entry["battler_tile"]))

	var strip: PackedByteArray = _data.battle_anim_gfx_indices(int(entry.get("gfx", 0)))
	var index: int = int(entry.get("tile", 0))
	@warning_ignore("integer_division")
	var width: int = strip.size() / TILE if strip.size() > 0 else 0
	if width <= 0 or (index + 1) * TILE > width:
		return PackedByteArray()
	var out := PackedByteArray()
	out.resize(TILE * TILE)
	for row: int in TILE:
		var from: int = row * width + index * TILE
		for column: int in TILE:
			out[row * TILE + column] = strip[from + column]
	return out


## One tile of a battler's box, numbered the way `PlaceGraphic` numbers it.
func _battler_tile(vram: int) -> PackedByteArray:
	var enemy: bool = vram < Gen2BattleScreenMap.PLAYER_BASE_TILE
	var side: int = Gen2BattleScreenMap.ENEMY_SIDE if enemy \
		else Gen2BattleScreenMap.player_box_side(_data.generation)
	var base: int = Gen2BattleScreenMap.ENEMY_BASE_TILE if enemy \
		else Gen2BattleScreenMap.PLAYER_BASE_TILE
	return Gen2BattleRenderer.pic_tile(
		_enemy_pixels if enemy else _player_pixels, side, vram - base
	)


func _ensure_pixels(view: Dictionary) -> void:
	var enemy: int = int(view.get("enemy_species", 0))
	if enemy != _enemy_species:
		_enemy_pixels = Gen2BattleRenderer.padded_pic(
			_data, _data.species_pic(enemy), Gen2BattleScreenMap.ENEMY_SIDE
		)
		_enemy_species = enemy
	var player: int = int(view.get("player_species", 0))
	if player != _player_species:
		_player_pixels = Gen2BattleRenderer.back_pixels(_data, _data.species_pic(player, true))
		_player_species = player
