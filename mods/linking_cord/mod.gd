extends RefCounted

## Defines one item, puts it on one shelf and returns. It draws nothing and
## writes nothing: the item row names an evolution method and
## `Gen2WorldPartyHost` runs the same check a trade would, so the species, the
## consumed held item, the Everstone refusal, the HP carried across and the new
## moves are decided where the cartridge's own stones decide them.

## Past `Gen2ContentOverlay.FIRST_MOD_NUMBER`, so it is not a cartridge number
## and means the same thing on all three games.
const LINKING_CORD: int = 256

## What every evolution stone costs here, and what the later games charge for
## this item.
const PRICE: int = 2100

## Goldenrod Dept Store 2F, which sells the ESCAPE ROPE, the REPEL and the POKé
## DOLL. Mart 6 on all three cartridges, checked by
## `tools/linking_cord_probe.gd`.
const DEPT_STORE_GADGETS: int = 6


func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	host.register_content(Gen2ContentOverlay.KIND_ITEM, manifest.id, LINKING_CORD, {
		"name": "LINKING CORD",
		"description": "Evolves POKéMON\nthat need a trade.",
		"price": PRICE,
		"pocket": Gen2WorldPack.TYPE_ITEM,
		# Every evolution stone's own nibble: USE opens the party list.
		"field_menu": Gen2WorldPack.ITEMMENU_PARTY,
		# The stones' own permissions: an item needing a Pokemon picked cannot be
		# registered to SELECT, and it can be tossed.
		"permissions": Gen2WorldPack.CANT_SELECT,
		"evolution": {"method": RomLayout.EVOLVE_TRADE},
	})
	host.register_menu_entry(Gen2ModHost.MENU_MART, manifest.id, {
		"label": "LINKING CORD",
		"item": LINKING_CORD,
		"available": func(mart: Dictionary) -> bool:
			return int(mart.get("mart_id", -1)) == DEPT_STORE_GADGETS,
	})
