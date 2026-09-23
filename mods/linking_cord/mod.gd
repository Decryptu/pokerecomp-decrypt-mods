extends RefCounted

const LINKING_CORD: int = 256

const PRICE: int = 2100

## Goldenrod Dept Store 2F's gadget counter, by the Generation II mart index.
const DEPT_STORE_GADGETS: int = 6
## Celadon Dept Store 4F, the one Generation I counter that sells evolution
## stones, by its map.
const CELADON_STONE_COUNTER: Vector2i = Vector2i(0, 125)


func register(host: Gen2ModHost, manifest: PokeModManifest) -> void:
	host.register_content(Gen2ContentOverlay.KIND_ITEM, manifest.id, LINKING_CORD, {
		"name": "LINKING CORD",
		"description": "Evolves POKéMON\nthat need a trade.",
		"price": PRICE,
		"pocket": Gen2WorldPack.TYPE_ITEM,
		"field_menu": Gen2WorldPack.ITEMMENU_PARTY,
		"permissions": Gen2WorldPack.CANT_SELECT,
		"evolution": {"method": Gen2Layout.EVOLVE_TRADE},
	})
	host.register_menu_entry(Gen2ModHost.MENU_MART, manifest.id, {
		"label": "LINKING CORD",
		"item": LINKING_CORD,
		"available": _sells_it,
	})


static func _sells_it(mart: Dictionary) -> bool:
	if int(mart.get("mart_id", -1)) == DEPT_STORE_GADGETS:
		return true
	var map := Vector2i(int(mart.get("map_group", -1)), int(mart.get("map_number", -1)))
	return map == CELADON_STONE_COUNTER
