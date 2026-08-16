extends RefCounted

## Registers the settings, the recall control and the follower itself, and
## returns. Nothing here is a scene node and nothing here writes world state.
##
## The follower is a world ACTOR: the host drives it a frame at a time and draws
## what it asks for, the same way it drives its own map objects. That seam is
## `register_world_actor` and it is the one thing this mod needs that the host
## does not have yet, so it is registered where it exists and skipped where it
## does not; the request is with the engine. The settings and the control
## register either way, because a mod that is installed and says nothing about
## itself is worse than one waiting on a seam.

const Options := preload("options.gd")
const Actor := preload("actor.gd")

var _actor: RefCounted = null


func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	Options.register(host, manifest.id)
	if not host.has_method("register_world_actor"):
		return
	_actor = Actor.new()
	_actor.configure(host, manifest.id)
	host.call("register_world_actor", manifest.id, _actor)
