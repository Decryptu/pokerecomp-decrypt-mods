extends RefCounted

## Ten switches, seven host-owned gameplay policies, one host-owned start-menu
## action and one cartridge-grid battle annotation provider.

const Options := preload("options.gd")
const Policies := preload("policies.gd")
const BattleInfo := preload("battle_info.gd")


func register(host: Gen2ModHost, manifest: Gen2ModManifest) -> void:
	Options.register(host, manifest.id)
	host.register_field_move_source(
		manifest.id, Policies.FieldMoveSource.new(host)
	)
	host.register_repel_renewal(
		manifest.id, Policies.RepelRenewal.new(host)
	)
	host.register_catch_experience(
		manifest, Policies.CatchExperience.new(host)
	)
	host.register_run_button(
		manifest.id, Policies.RunShoes.new(host)
	)
	host.register_experience_scale(
		manifest, Policies.ExperienceScale.new(host)
	)
	host.register_experience_bystanders(
		manifest, Policies.BystanderShare.new(host)
	)
	host.register_battle_info(manifest.id, BattleInfo.new(host))
	host.register_menu_entry(Gen2ModHost.MENU_START, manifest.id, {
		"label": "PC",
		"action": Gen2ModHost.START_ACTION_OPEN_BILLS_PC,
		"visible": func(_context: Dictionary) -> bool:
			return Options.enabled(host, Options.PC_ACCESS),
	})
