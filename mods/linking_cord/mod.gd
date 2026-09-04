extends RefCounted

## Defines one item, puts it on one shelf and returns.

const LINKING_CORD: int = 256

const PRICE: int = 2100

const DEPT_STORE_GADGETS: int = 6


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
		"available": func(mart: Dictionary) -> bool:
			return int(mart.get("mart_id", -1)) == DEPT_STORE_GADGETS,
	})
