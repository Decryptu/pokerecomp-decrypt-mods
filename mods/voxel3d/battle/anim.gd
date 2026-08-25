extends RefCounted

## The move animation, drawn as the hardware drew it: `wShadowOAM` blitted into
## one 160x144 picture the renderer lays over the fight. Nothing here is authored:
## an OAM entry says which tile, where, which object palette and which flips, and
## every one of those answers is the host's.
##
## It can be drawn at the hardware's own coordinates, which is why it is cheap:
## an animation is authored against the two picture slots the cartridge draws its
## battlers in, and `arena.gd`'s rig is solved to land both battlers in those
## slots to within 0.013 px, so nothing has to be re-aimed.
##
## What is left over is the shot's drift, and it needs two offsets rather than
## one. The drift orbits, carrying the near battler one way and the far one the
## other: each ends up as much as 1.2 hardware pixels off its mark while the mean
## of the two peaks at 0.34, so one offset for the layer is almost no offset at
## all. Each sprite is placed against whichever mark it is nearer, lerped along
## the line joining them, which is exact at both battlers and continuous between,
## so an ember stream crossing the field bends rather than stepping.
##
## The animation's background half is not drawn: `bg_map` edits, background
## palette maps and the raster scroll are a flat screen's mechanisms, and this
## view has a diorama behind the battlers. The OAM layer is where the effect is.

const Arena: GDScript = preload("arena.gd")

const TILE: int = 8

## OAM attribute bits, as the host's own renderer reads them.
const OAM_YFLIP: int = 1 << 6
const OAM_XFLIP: int = 1 << 5
const OAM_PALETTE: int = 0x07

## `%11100100`, the DMG palette byte that maps every colour to itself, which is
## what an animation that has requested no permutation leaves behind.
const PALETTE_IDENTITY: int = 0xE4

var _data: GameData = null

## The two battler pictures padded to the boxes the tilemap addresses them in,
## 56x56 and 48x48, kept only for the effects that move a battler as objects
## (`anim_battlergfx_1row` and `..._2row`). Rebuilt when the species changes.
var _enemy_pixels := PackedByteArray()
var _player_pixels := PackedByteArray()
var _enemy_species: int = -1
var _player_species: int = -1


func _init(data: GameData) -> void:
	_data = data


## The whole OAM layer as one hardware-sized picture, or null on any frame
## outside a move.
##
## [param player_off] and [param enemy_off] are how far each battler has drifted
## off its mark, in hardware pixels, and are zero on a still shot.
##
## Sprites are blitted in the order written, so a later one draws over an earlier:
## the hardware's own priority between objects.
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
			drawn += 1 if _blit(into, entry as Dictionary, view, player_off, enemy_off) else 0
	return into if drawn > 0 else null


## How far along the line from the player's mark to the enemy's a point lies,
## clamped to the segment, which decides whose drift correction it takes. Along
## the line and not by nearest mark, so the correction is continuous.
static func _between(at: Vector2) -> float:
	var axis: Vector2 = Arena.ENEMY_MARK - Arena.PLAYER_MARK
	var span: float = axis.length_squared()
	if span <= 0.0:
		return 0.0
	return clampf((at - Arena.PLAYER_MARK).dot(axis) / span, 0.0, 1.0)


## One OAM entry. The stored y and x are the hardware's, which subtracts sixteen
## and eight before drawing, so a zero in either is off screen rather than at the
## corner: that is how an animation parks a sprite.
func _blit(
	into: Image, sprite: Dictionary, view: Dictionary,
	player_off: Vector2, enemy_off: Vector2
) -> bool:
	var pixels: PackedByteArray = _tile(int(sprite.get("tile", 0)), view)
	if pixels.is_empty():
		return false
	var attributes: int = int(sprite.get("attributes", 0))
	var palette: PackedColorArray = _remap(
		_object_palette(attributes & OAM_PALETTE, view),
		_palette_map(view, attributes & OAM_PALETTE)
	)
	# Index 0 is transparent, as OAM's colour 0 is: an object is a shape over the
	# field, never a square of background.
	var lookup: Image = Gen2PicImage.from_indices(pixels, TILE, TILE, palette, true)
	if (attributes & OAM_XFLIP) != 0:
		lookup.flip_x()
	if (attributes & OAM_YFLIP) != 0:
		lookup.flip_y()

	var left: int = int(sprite.get("x", 0)) - 8
	var top: int = int(sprite.get("y", 0)) - 16
	# Taken at the sprite's middle so a tile is weighed where it sits, and
	# rounded because half a hardware pixel cannot be blitted.
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


## One 8x8 animation tile, found through the window `anim_tiles` describes and
## counted from `Gen2BattleAnimObject.BASE_TILE`: an OAM tile id below that base
## is not an animation tile.
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


## One tile of the battler boxes, out of the padding the tilemap addresses them
## through, so an effect carrying a battler across the screen carries the picture
## that was on the field.
func _battler_tile(vram: int) -> PackedByteArray:
	var enemy: bool = vram < Gen2BattleScreenMap.PLAYER_BASE_TILE
	var side: int = Gen2BattleScreenMap.ENEMY_SIDE if enemy \
		else Gen2BattleScreenMap.PLAYER_SIDE
	var base: int = Gen2BattleScreenMap.ENEMY_BASE_TILE if enemy \
		else Gen2BattleScreenMap.PLAYER_BASE_TILE
	var pixels: PackedByteArray = _enemy_pixels if enemy else _player_pixels
	var index: int = vram - base
	var box: int = side * TILE
	if index < 0 or index >= side * side or pixels.size() < box * box:
		return PackedByteArray()

	# The tilemap walks a box down its columns, which is how the hardware numbers
	# the tiles of a picture.
	@warning_ignore("integer_division")
	var left: int = (index / side) * TILE
	var top: int = (index % side) * TILE
	var out := PackedByteArray()
	out.resize(TILE * TILE)
	for row: int in TILE:
		var from: int = (top + row) * box + left
		for column: int in TILE:
			out[row * TILE + column] = pixels[from + column]
	return out


func _ensure_pixels(view: Dictionary) -> void:
	var enemy: int = int(view.get("enemy_species", 0))
	if enemy != _enemy_species:
		_enemy_pixels = _padded(
			_data.species_pic(enemy), Gen2BattleScreenMap.ENEMY_SIDE
		)
		_enemy_species = enemy
	var player: int = int(view.get("player_species", 0))
	if player != _player_species:
		_player_pixels = _padded(
			_data.species_pic(player, true), Gen2BattleScreenMap.PLAYER_SIDE
		)
		_player_species = player


## A pic laid into the top-left of its box, where the tilemap expects it: a
## picture smaller than its slot leaves the rest blank rather than being centred.
func _padded(pic: Dictionary, side: int) -> PackedByteArray:
	var box: int = side * TILE
	var out := PackedByteArray()
	out.resize(box * box)
	if pic.is_empty():
		return out
	var atlas: Dictionary = _data.atlas(String(pic["atlas"]))
	var indices: PackedByteArray = _data.atlas_indices(String(pic["atlas"]))
	var cell: int = int(atlas.get("cell", 0))
	var columns: int = int(atlas.get("columns", 0))
	var atlas_width: int = int(atlas.get("width", 0))
	var slot: int = int(pic.get("slot", -1))
	if cell <= 0 or columns <= 0 or atlas_width <= 0 or slot < 0:
		return out

	var width: int = mini(int(pic.get("width", cell)), mini(cell, box))
	var height: int = mini(int(pic.get("height", cell)), mini(cell, box))
	var left: int = (slot % columns) * cell
	@warning_ignore("integer_division")
	var top: int = (slot / columns) * cell
	for y: int in height:
		var from: int = (top + y) * atlas_width + left
		if from + width > indices.size():
			break
		for x: int in width:
			out[y * box + x] = indices[from + x]
	return out


## `PAL_BATTLE_OB_*`. Slots 0 and 1 are the two battlers' own palettes rather
## than `BattleObjectPals` rows, which is what the layout code fills them with,
## so a beam tinted to the animal it comes out of stays tinted to it.
func _object_palette(slot: int, view: Dictionary) -> PackedColorArray:
	return _data.battle_object_palette(
		slot,
		_pair(int(view.get("enemy_species", 0))),
		_pair(int(view.get("player_species", 0)))
	)


func _pair(species: int) -> Array:
	var entry: Dictionary = _data.species(species)
	if entry.is_empty():
		return []
	var stored: Variant = (entry.get("palette", {}) as Dictionary).get("normal", [])
	return stored if stored is Array else []


## Whatever DMG byte the animation's last palette request left on this object
## slot, identity when it has asked for none.
func _palette_map(view: Dictionary, slot: int) -> int:
	var maps: Variant = view.get("ob_palette_maps", [])
	if maps is PackedByteArray:
		var bytes: PackedByteArray = maps
		return bytes[slot] if slot < bytes.size() else PALETTE_IDENTITY
	if maps is Array:
		var list: Array = maps
		return int(list[slot]) if slot < list.size() else PALETTE_IDENTITY
	return PALETTE_IDENTITY


## `CopyPals`: colour i of the result is colour `(byte >> i * 2) & 3` of the
## pristine palette, which is why a remap never compounds.
static func _remap(palette: PackedColorArray, dmg: int) -> PackedColorArray:
	if dmg == PALETTE_IDENTITY or palette.is_empty():
		return palette
	var out := PackedColorArray()
	for index: int in palette.size():
		out.append(palette[mini((dmg >> (index * 2)) & 3, palette.size() - 1)])
	return out
