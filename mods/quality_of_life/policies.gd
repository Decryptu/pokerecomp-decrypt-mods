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

	const REPEL: int = 0x14
	const SUPER_REPEL: int = 0x2A
	const MAX_REPEL: int = 0x2B
	const WEAKEST_FIRST: Array[int] = [REPEL, SUPER_REPEL, MAX_REPEL]

	var _host: Gen2ModHost

	func _init(host: Gen2ModHost) -> void:
		_host = host

	func repel_to_use(inventory: Dictionary) -> int:
		if not Options.enabled(_host, Options.AUTO_REPEL):
			return 0
		for item: int in WEAKEST_FIRST:
			if int(inventory.get(item, 0)) > 0:
				return item
		return 0


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
