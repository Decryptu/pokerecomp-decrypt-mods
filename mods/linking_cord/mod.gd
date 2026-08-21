extends RefCounted

## Defines one item and puts it on one shelf, and returns. Nothing here draws
## and nothing here writes.
##
## THE EVOLUTION IS THE HOST'S, NOT THIS MOD'S. The item row NAMES a method and
## `Gen2WorldPartyHost` runs the same predicate a trade would, so the species,
## the held item it consumes, the Everstone refusal, the HP carried across and
## the moves the new species learns are all decided in the one place the
## cartridge's own stones are decided. A mod that evolved a Pokemon from a
## callback would be holding a party member in the middle of the host's own
## transaction.

## Past `Gen2ContentOverlay.FIRST_MOD_NUMBER`, so the number is unambiguously
## not the cartridge's and means the same thing on Gold, Silver and Crystal.
const LINKING_CORD: int = 256

## What every evolution stone costs on the cartridge, and what the later games
## price this item at. Two numbers agreeing is why it is not argued.
const PRICE: int = 2100

## Goldenrod Dept Store 2F, the floor that sells the cartridge's gadgets: the
## ESCAPE ROPE, the REPEL and the POKé DOLL. Mart 6 on all three cartridges,
## which is checked rather than assumed by `tools/linking_cord_probe.gd`.
const DEPT_STORE_GADGETS: int = 6


func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	host.register_content(Gen2ContentOverlay.KIND_ITEM, manifest.id, LINKING_CORD, {
		"name": "LINKING CORD",
		"description": "Evolves POKéMON\nthat need a trade.",
		"price": PRICE,
		"pocket": Gen2WorldPack.TYPE_ITEM,
		# ITEMMENU_PARTY is every evolution stone's own nibble: USE opens the
		# party list and the effect lands on whoever is picked.
		"field_menu": Gen2WorldPack.ITEMMENU_PARTY,
		# CANT_SELECT alone, which is also the stones': an item that needs a
		# Pokemon picked cannot be registered to SELECT, and it can be tossed.
		"permissions": Gen2WorldPack.CANT_SELECT,
		"evolution": {"method": RomLayout.EVOLVE_TRADE},
	})
	host.register_menu_entry(Gen2ModHost.MENU_MART, manifest.id, {
		"label": "LINKING CORD",
		"item": LINKING_CORD,
		"available": func(mart: Dictionary) -> bool:
			return int(mart.get("mart_id", -1)) == DEPT_STORE_GADGETS,
	})
