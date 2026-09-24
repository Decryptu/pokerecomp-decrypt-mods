extends RefCounted

## The host's draw list as cards: rows sharing an owner compose one picture,
## stood with the owner's `ground` on its cell.

## The flat view's stand-ins for depth, which the diorama has in geometry: the
## map's grass over a sprite's feet and the ledge shadow under a jump.
const FLAT_ONLY: Array[StringName] = [&"grass", &"shadow"]
## Rows that are light rather than a body, and so cast no shadow.
const LIGHT: Array[StringName] = [&"emote", &"pulse"]
const MAX_TEXTURES: int = 1024

var _textures: Dictionary = {}


func clear() -> void:
	_textures.clear()


## `{texture, caster, anchor, owner, position_cells, span}` per owner: `anchor` is the
## texture pixel on the ground, and `caster` is null for light alone.
func cards(list: Gen2WorldDrawList) -> Array:
	var groups: Dictionary = {}
	for row: Dictionary in list.sprites():
		if StringName(row["role"]) in FLAT_ONLY:
			continue
		var owner: Array = [
			row["owner"], row["anchor"], row["origin"], row["ground"], row["position_cells"],
		]
		if not groups.has(owner):
			groups[owner] = []
		(groups[owner] as Array).append(row)
	var out: Array = []
	for rows: Array in groups.values():
		var card: Dictionary = _card(list, rows)
		if not card.is_empty():
			out.append(card)
	return out


func _card(list: Gen2WorldDrawList, rows: Array) -> Dictionary:
	var first: Dictionary = rows[0]
	var ground: Vector2 = first["ground"]
	var key: Array = _key(rows, ground)
	if not _textures.has(key):
		if _textures.size() >= MAX_TEXTURES:
			_textures.clear()
		_textures[key] = _compose(list, rows, ground)
	var drawn: Dictionary = _textures[key]
	if drawn.is_empty():
		return {}
	var out: Dictionary = drawn.duplicate()
	out["owner"] = int(first["owner"])
	out["position_cells"] = Vector2(first["position_cells"])
	out["span"] = first.get("span", {})
	return out


## Everything a card's picture depends on, measured from its ground so a walker
## keeps its card from one pass to the next.
func _key(rows: Array, ground: Vector2) -> Array:
	var parts: Array = []
	for row: Dictionary in rows:
		var at: Vector2 = Vector2(row["origin"]) + Vector2(row["offset"]) - ground
		match StringName(row["kind"]):
			Gen2WorldDrawList.KIND_SPRITE:
				var sprite: Gen2WorldSprite = row["sprite"]
				parts.append([
					at, row["role"], _sprite_id(sprite), row["colors"], row["facing"],
					row["frame"], row["big_shape"], row["flip_x"], row["region"],
				])
			Gen2WorldDrawList.KIND_TILES:
				parts.append([at, row["role"], row["sheet"], row["colors"], row["tiles"]])
			Gen2WorldDrawList.KIND_PULSE:
				parts.append([at, row["gfx"], row["tile"], row["attributes"], row["pair"]])
	return parts


static func _sprite_id(sprite: Gen2WorldSprite) -> Array:
	if sprite == null:
		return []
	return [sprite.sprite_type, sprite.number, sprite.icon_number]


func _compose(list: Gen2WorldDrawList, rows: Array, ground: Vector2) -> Dictionary:
	var pieces: Array = []
	for row: Dictionary in rows:
		_pieces_of(list, row, pieces)
	if pieces.is_empty():
		return {}
	var bounds := Rect2i((pieces[0] as Dictionary)["at"], Vector2i.ZERO)
	for piece: Dictionary in pieces:
		bounds = bounds.merge(Rect2i(piece["at"], (piece["image"] as Image).get_size()))
	var card: Image = _canvas(bounds.size)
	var caster: Image = null
	for piece: Dictionary in pieces:
		var image: Image = piece["image"]
		var to: Vector2i = Vector2i(piece["at"]) - bounds.position
		card.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), to)
		if bool(piece["light"]):
			continue
		if caster == null:
			caster = _canvas(bounds.size)
		caster.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), to)
	return {
		"texture": ImageTexture.create_from_image(card),
		"caster": ImageTexture.create_from_image(caster) if caster != null else null,
		"anchor": ground - Vector2(bounds.position),
	}


func _pieces_of(list: Gen2WorldDrawList, row: Dictionary, into: Array) -> void:
	var at: Vector2i = Vector2i((Vector2(row["origin"]) + Vector2(row["offset"])).round())
	var light: bool = StringName(row["role"]) in LIGHT
	match StringName(row["kind"]):
		Gen2WorldDrawList.KIND_SPRITE:
			_add_piece(into, _sprite_picture(list, row), at + _region_start(row), light)
		Gen2WorldDrawList.KIND_TILES:
			for tile: Dictionary in row["tiles"]:
				_add_piece(into, list.tile_image(
					String(row["sheet"]), int(tile["tile"]), row["colors"],
					bool(tile["flip_x"]), bool(tile["flip_y"])
				), at + Vector2i(tile["offset"]), light)
		Gen2WorldDrawList.KIND_PULSE:
			_add_piece(into, list.pulse_image(row), at, light)


func _add_piece(into: Array, image: Image, at: Vector2i, light: bool) -> void:
	if image != null and not image.is_empty():
		if image.get_format() != Image.FORMAT_RGBA8:
			image.convert(Image.FORMAT_RGBA8)
		into.append({"image": image, "at": at, "light": light})


func _sprite_picture(list: Gen2WorldDrawList, row: Dictionary) -> Image:
	var image: Image = list.sprite_image(row, row["colors"])
	if image == null:
		return null
	var region: Rect2 = row["region"]
	if region.has_area():
		image = image.get_region(Rect2i(region))
	if bool(row["flip_x"]):
		image.flip_x()
	return image


static func _region_start(row: Dictionary) -> Vector2i:
	var region: Rect2 = row["region"]
	return Vector2i(region.position) if region.has_area() else Vector2i.ZERO


static func _canvas(size: Vector2i) -> Image:
	return Image.create_empty(maxi(size.x, 1), maxi(size.y, 1), false, Image.FORMAT_RGBA8)
