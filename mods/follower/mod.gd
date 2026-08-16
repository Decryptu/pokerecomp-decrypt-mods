extends RefCounted

## Registers the settings, the recall control and the follower itself, and
## returns. Nothing here is a scene node and nothing here writes world state.
##
## The follower is a world ACTOR: the host drives it a frame at a time and draws
## what it asks for, the same way it drives its own map objects. Registration is
## refused by name if the actor is a Node or is missing one of its three
## methods, so a mistake here is reported before a frame is drawn rather than on
## one.

const Options := preload("options.gd")
const Actor := preload("actor.gd")

var _actor: RefCounted = null


func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	Options.register(host, manifest.id)
	_actor = Actor.new()
	_actor.configure(host, manifest.id)
	host.register_world_actor(manifest.id, _actor)
