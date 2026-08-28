extends RefCounted

## Two settings, both about the notice.

const MOD_ID: StringName = &"achievements"

const NOTICE: StringName = &"notice"
const SOUND: StringName = &"sound"

const NOTICE_OFF: int = 0
const NOTICE_ON: int = 1


static func register(host: Gen2ModHost, id: StringName) -> void:
	host.register_option(id, {
		"key": NOTICE,
		"label": "NOTICE",
		"values": [NOTICE_ON, NOTICE_OFF],
		"labels": ["ON", "OFF"],
		"default": NOTICE_ON,
	})
	host.register_option(id, {
		"key": SOUND,
		"label": "NOTICE SOUND",
		"values": [NOTICE_ON, NOTICE_OFF],
		"labels": ["ON", "OFF"],
		"default": NOTICE_ON,
	})


static func notice(host: Gen2ModHost) -> bool:
	return _on(host, NOTICE)


static func sound(host: Gen2ModHost) -> bool:
	return _on(host, SOUND)


static func _on(host: Gen2ModHost, key: StringName) -> bool:
	if host == null:
		return true
	var value: Variant = host.option(MOD_ID, key)
	return true if value == null else int(value) == NOTICE_ON
