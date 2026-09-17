extends RefCounted

## The decisions the mod owns.

const Options := preload("options.gd")


class FieldMoveSource:
	extends RefCounted

	var _host: Gen2ModHost

	func _init(host: Gen2ModHost) -> void:
		_host = host

	func allows_field_move(_move: int) -> bool:
		return Options.enabled(_host, Options.FIELD_MOVES)


class RepelRenewal:
	extends RefCounted

	var _host: Gen2ModHost

	func _init(host: Gen2ModHost) -> void:
		_host = host

	## The fewest steps of the Repels the cartridge names and the bag holds.
	func repel_to_use(context: Dictionary) -> int:
		if not Options.enabled(_host, Options.AUTO_REPEL):
			return 0
		var repels: Dictionary = context.get("repels", {})
		var inventory: Dictionary = context.get("inventory", {})
		var weakest: int = 0
		for item: int in repels:
			if int(inventory.get(item, 0)) <= 0:
				continue
			if weakest == 0 or int(repels[item]) < int(repels[weakest]):
				weakest = item
		return weakest


class CatchExperience:
	extends RefCounted

	var _host: Gen2ModHost

	func _init(host: Gen2ModHost) -> void:
		_host = host

	func awards_catch_experience() -> bool:
		return Options.enabled(_host, Options.CATCH_EXP)


class RunShoes:
	extends RefCounted

	var _host: Gen2ModHost

	func _init(host: Gen2ModHost) -> void:
		_host = host

	func runs_while_held() -> bool:
		return Options.enabled(_host, Options.RUN_SHOES)


class ExperienceScale:
	extends RefCounted

	var _host: Gen2ModHost

	func _init(host: Gen2ModHost) -> void:
		_host = host

	func experience_scale() -> float:
		return Options.scale(_host)


class BystanderShare:
	extends RefCounted

	var _host: Gen2ModHost

	func _init(host: Gen2ModHost) -> void:
		_host = host

	## A living Exp. Share holder anywhere in the party is what turns this on, so
	## the item stays the object behind the setting rather than the setting alone.
	func experience_bystander_share(context: Dictionary) -> float:
		var holders: Array = context.get("exp_share_holders", [])
		if holders.is_empty():
			return Options.NO_SHARE
		return Options.bystander_share(_host)
