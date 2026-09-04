extends RefCounted

## Defines one key item, says what holding it is worth, and watches for the
## moment the game hands it over.

const Charm := preload("charm.gd")
const Policy := preload("policy.gd")

var _policy: Policy = null
var _host: Gen2ModHost = null


func register(host: Gen2ModHost, manifest: PokeModManifest) -> void:
	_host = host
	host.register_content(Gen2ContentOverlay.KIND_ITEM, manifest.id, Charm.NUMBER, {
		"name": "SHINY CHARM",
		"description": Charm.DESCRIPTION,
		"pocket": Gen2WorldPack.TYPE_KEY_ITEM,
		"field_menu": Gen2WorldPack.ITEMMENU_NOUSE,
		"permissions": Gen2WorldPack.CANT_SELECT | Gen2WorldPack.CANT_TOSS,
	})
	_policy = Policy.new(host)
	host.register_shiny_rolls(manifest.id, _policy)
	host.subscribe(Gen2ModHost.CHANNEL_WORLD, manifest.id, _on_world_event)


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
	_host.request_item_gift(Charm.NUMBER, 1)
