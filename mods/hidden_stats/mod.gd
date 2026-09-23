extends RefCounted

const Page := preload("page.gd")


func register(host: Gen2ModHost, manifest: PokeModManifest) -> void:
	host.register_stats_page(manifest.id, {"build": Page.build})
