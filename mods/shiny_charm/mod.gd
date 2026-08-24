extends RefCounted

## Defines one key item, says what holding it is worth, and watches for the one
## moment the game hands it over. Nothing here rolls a DV, writes a bag or draws
## a box.
##
## THE AWARD IS THE HOST'S TRANSACTION, NOT THIS MOD'S. The mod names an item
## and the host runs `verbosegiveitem`'s own fanfare, its
## `<PLAYER> received SHINY CHARM!`, its pocket line and its pack-full branch,
## the same bargain `request_hidden_item` has with a hidden item. A mod that
## wrote the bag itself would be writing world state, and it would have to
## reproduce a screen it cannot see.

const Charm := preload("charm.gd")
const Policy := preload("policy.gd")

## Kept for as long as the mod is loaded, because the host holds this entry
## object and the provider has to outlive `register`.
var _policy: Policy = null
var _host: Gen2ModHost = null


func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	_host = host
	host.register_content(Gen2ContentOverlay.KIND_ITEM, manifest.id, Charm.NUMBER, {
		"name": "SHINY CHARM",
		"description": Charm.DESCRIPTION,
		"pocket": Gen2WorldPack.TYPE_KEY_ITEM,
		# The CLEAR BELL's own row: nothing to use it on, nothing to register to
		# SELECT, nothing to toss it for. A key item that is worth something by
		# being owned has no field effect at all.
		"field_menu": Gen2WorldPack.ITEMMENU_NOUSE,
		"permissions": Gen2WorldPack.CANT_SELECT | Gen2WorldPack.CANT_TOSS,
	})
	_policy = Policy.new(host)
	host.register_shiny_rolls(manifest.id, _policy)
	host.subscribe(Gen2ModHost.CHANNEL_WORLD, manifest.id, _on_world_event)


## The GAME designer's diploma, on Celadon Condominiums' top floor: the one
## script in the game that answers a finished Pokedex, and therefore the one
## place a charm for finishing it belongs.
##
## Either of the two specials counts. `Diploma` is the branch a first
## completion reaches and `PrintDiploma` is what every visit after it offers, so
## a save that finished its dex before this mod was installed is given the charm
## the next time it asks to see the certificate it already earned.
func _on_world_event(event: Dictionary) -> void:
	var staged: Variant = event.get("event", {})
	if not staged is Dictionary:
		return
	if StringName((staged as Dictionary).get("type", &"")) != &"runtime_request":
		return
	var request: Variant = (staged as Dictionary).get("request", {})
	if not request is Dictionary:
		return
	if StringName((request as Dictionary).get("kind", &"")) != &"diploma_requested":
		return
	if _host == null or int(_host.inventory().get(Charm.NUMBER, 0)) > 0:
		return
	# Spent on the first world frame the diploma page is no longer holding, the
	# way a hidden item's ask waits for a frame nothing else owns.
	_host.request_item_gift(Charm.NUMBER, 1)
