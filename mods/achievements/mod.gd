extends RefCounted

## Registers the settings and a save lifecycle, and carries one save's ledger
## between them. Nothing here is a scene node, nothing draws and nothing reads
## world or battle state: `catalogue.gd` says what an achievement is,
## `ledger.gd` says what one save has, and the host is asked for the rest.
##
## The ledger belongs to the save rather than to the installation, because two
## slots are two runs: a badge won in one is not won in the other, and a slot
## reopened has to find its own set and say nothing about it again.

const Ledger := preload("ledger.gd")
const Options := preload("options.gd")

var _host: Gen2ModHost = null
var _manifest: Gen2ModManifest = null
var _ledger: Ledger = Ledger.new()


func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	_host = host
	_manifest = manifest
	Options.register(host, manifest.id)
	host.register_save_lifecycle(manifest, self)


## A run that began with the mod installed is written an empty ledger, which is
## what tells activation apart from a save played before the mod existed: that
## one carries nothing, and everything already true of it is awarded without a
## notice, since it was earned while nothing was watching.
func save_created(save: Gen2SaveData) -> void:
	if save == null:
		return
	_host.write_save_data(_manifest, save, Ledger.new().stored())


func save_activated(save: Gen2SaveData) -> void:
	if save == null:
		## A development run has no slot to own a set, and awarding into one
		## that is never written would announce the same thing every boot.
		_ledger.closed()
		return
	_ledger.restore(_host.read_save_data(_manifest, save))


func save_deactivated() -> void:
	_ledger.closed()
