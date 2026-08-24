extends RefCounted

## The decisions the mod owns. Inventory mutation, badge checks, field actions,
## Repel prompts and capture awards remain transactions in the host.

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

	## Generation II item numbers, ordered from the shortest effect to the
	## longest so automatic renewal preserves stronger Repels when it can.
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
