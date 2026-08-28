extends RefCounted

## What a key or a wheel notch means to a camera, in either view.

const NONE: StringName = &""
const ZOOM_IN: StringName = &"zoom_in"
const ZOOM_OUT: StringName = &"zoom_out"
const PITCH_UP: StringName = &"pitch_up"
const PITCH_DOWN: StringName = &"pitch_down"
const SWING_LEFT: StringName = &"swing_left"
const SWING_RIGHT: StringName = &"swing_right"
const DOLLY_IN: StringName = &"dolly_in"
const DOLLY_OUT: StringName = &"dolly_out"

const RESET: StringName = &"reset"

const ACTIONS: Array[Dictionary] = [
	{
		"key": ZOOM_IN, "label": "Zoom in",
		"default": [
			{"kind": &"key", "code": KEY_EQUAL},
			{"kind": &"key", "code": KEY_PLUS},
			{"kind": &"key", "code": KEY_KP_ADD},
			{"kind": &"pad_button", "code": JOY_BUTTON_RIGHT_SHOULDER},
		],
	},
	{
		"key": ZOOM_OUT, "label": "Zoom out",
		"default": [
			{"kind": &"key", "code": KEY_MINUS},
			{"kind": &"key", "code": KEY_KP_SUBTRACT},
			{"kind": &"pad_button", "code": JOY_BUTTON_LEFT_SHOULDER},
		],
	},
	{
		"key": PITCH_UP, "label": "Camera up",
		"default": [
			{"kind": &"key", "code": KEY_I},
			{"kind": &"pad_axis", "code": JOY_AXIS_RIGHT_Y, "sign": -1},
		],
	},
	{
		"key": PITCH_DOWN, "label": "Camera down",
		"default": [
			{"kind": &"key", "code": KEY_K},
			{"kind": &"pad_axis", "code": JOY_AXIS_RIGHT_Y, "sign": 1},
		],
	},
	{
		"key": SWING_LEFT, "label": "Swing left",
		"default": [
			{"kind": &"key", "code": KEY_J},
			{"kind": &"pad_axis", "code": JOY_AXIS_RIGHT_X, "sign": -1},
		],
	},
	{
		"key": SWING_RIGHT, "label": "Swing right",
		"default": [
			{"kind": &"key", "code": KEY_L},
			{"kind": &"pad_axis", "code": JOY_AXIS_RIGHT_X, "sign": 1},
		],
	},
	{
		"key": DOLLY_OUT, "label": "Pull back",
		"default": [{"kind": &"key", "code": KEY_Q}],
	},
	{
		"key": DOLLY_IN, "label": "Push in",
		"default": [{"kind": &"key", "code": KEY_E}],
	},
	{
		"key": RESET, "label": "Recentre the camera",
		"default": [
			{"kind": &"key", "code": KEY_0},
			{"kind": &"key", "code": KEY_KP_0},
			{"kind": &"pad_button", "code": JOY_BUTTON_RIGHT_STICK},
		],
	},
]

const ZOOM_LIMITS := Vector2(0.55, 2.0)
const ZOOM_STEP: float = 0.12

const TWEEN_TIME: float = 0.22

const HELD: Array[StringName] = [
	PITCH_UP, PITCH_DOWN, SWING_LEFT, SWING_RIGHT,
	ZOOM_IN, ZOOM_OUT, DOLLY_IN, DOLLY_OUT,
]
const GLIDE_DELAY: float = 0.2
const GLIDE_RATE: float = 7.0


class Glide extends RefCounted:
	var _held: Dictionary = {}

	func notches(delta: float, strength: Callable) -> Dictionary:
		var out: Dictionary = {}
		for command: StringName in HELD:
			var pushed: float = clampf(float(strength.call(command)), 0.0, 1.0)
			if pushed <= 0.0:
				_held[command] = 0.0
				continue
			var since: float = float(_held.get(command, 0.0)) + delta
			_held[command] = since
			var gliding: float = minf(delta, since - GLIDE_DELAY)
			if gliding <= 0.0:
				continue
			out[command] = pushed * GLIDE_RATE * gliding
		return out


static func command(event: InputEvent, wheel_sign: int = 1) -> StringName:
	var wheel := event as InputEventMouseButton
	if wheel != null and wheel.pressed:
		match wheel.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				return ZOOM_IN if wheel_sign >= 0 else ZOOM_OUT
			MOUSE_BUTTON_WHEEL_DOWN:
				return ZOOM_OUT if wheel_sign >= 0 else ZOOM_IN
	return NONE
