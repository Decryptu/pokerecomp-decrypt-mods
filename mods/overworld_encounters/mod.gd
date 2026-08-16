extends RefCounted

const Options := preload("options.gd")
const Provider := preload("provider.gd")

var _provider: RefCounted = null


func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	Options.register(host, manifest.id)
	_provider = Provider.new()
	_provider.configure(host, manifest.id)
	host.call("register_visible_encounters", manifest.id, _provider)
