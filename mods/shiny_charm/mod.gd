extends RefCounted

## Defines one key item, says what holding it is worth, and watches for the
## moment the game hands it over. It rolls no DV, writes no bag and draws no box:
## the mod names an item and the host runs `verbosegiveitem`, with its own
## fanfare, receipt box and pack-full branch.

const Charm := preload("charm.gd")
const Policy := preload("policy.gd")

## The host holds this object, so the provider has to outlive `register`.
var _policy: Policy = null
var _host: Gen2ModHost = null


func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	_host = host
	host.register_content(Gen2ContentOverlay.KIND_ITEM, manifest.id, Charm.NUMBER, {
		"name": "SHINY CHARM",
		"description": Charm.DESCRIPTION,
		"pocket": Gen2WorldPack.TYPE_KEY_ITEM,
		# The CLEAR BELL's own row: worth something by being owned, so it has no
		# field effect at all.
		"field_menu": Gen2WorldPack.ITEMMENU_NOUSE,
		"permissions": Gen2WorldPack.CANT_SELECT | Gen2WorldPack.CANT_TOSS,
	})
	_policy = Policy.new(host)
	host.register_shiny_rolls(manifest.id, _policy)
	host.subscribe(Gen2ModHost.CHANNEL_WORLD, manifest.id, _on_world_event)


## The GAME designer's diploma on Celadon Condominiums' top floor: the one script
## that answers a finished Pokedex.
##
## Either special counts. `Diploma` is the first-completion branch and
## `PrintDiploma` is what later visits offer, so a save that finished its dex
## before the mod was installed gets the charm the next time it asks to see the
## certificate.
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
	# Waits for a world frame the diploma page is not holding, the way a hidden
	# item's request does.
	_host.request_item_gift(Charm.NUMBER, 1)
