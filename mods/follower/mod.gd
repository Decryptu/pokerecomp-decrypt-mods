extends RefCounted

## Registers the settings, the recall control and the follower, and returns.

const Options := preload("options.gd")
const Actor := preload("actor.gd")

var _actor: RefCounted = null
var _host: Gen2ModHost = null
var _id: StringName = &""


func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	_host = host
	_id = manifest.id
	Options.register(host, manifest.id)
	_actor = Actor.new()
	_actor.configure(host, manifest.id)
	host.register_world_actor(manifest.id, _actor)
	host.register_party_member_menu(manifest.id, {
		"label": _party_label,
		"handler": _follow_slot,
	})


func _party_label(slot: int) -> String:
	return "FOLLOWING" if int(Options.settings(_host)[Options.SLOT]) == slot else "FOLLOW"


func _follow_slot(slot: int) -> void:
	_host.set_option(_id, Options.SLOT, slot)
