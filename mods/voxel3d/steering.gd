extends RefCounted

## What a key or a wheel notch MEANS to a camera, in either view.
##
## The two rigs are different mechanisms and stay that way: the overworld's eye
## orbits the player at a distance it may change, and the battle's is a solved
## seat whose distance is not the player's to move. What they are not allowed to
## differ about is the binding, or a wheel means one thing walking around and
## another thing fighting. So the vocabulary is here, whole, and each rig answers
## only the commands it has an answer for and refuses the rest.
##
## Purely presentational. Nothing here reaches collision, movement, triggers or
## scripts, and the events it reads are the ones the screen did not claim.

const NONE: StringName = &""
## The lens. Both views zoom the LENS and never the distance: a rig derives its
## field of view from where the eye sits, so moving the eye instead changes the
## perspective without changing the framing.
const ZOOM_IN: StringName = &"zoom_in"
const ZOOM_OUT: StringName = &"zoom_out"
## Degrees above the horizon, and how far round the eye sits. The battle swings;
## the overworld's axis is the player and has nothing to swing about.
const PITCH_UP: StringName = &"pitch_up"
const PITCH_DOWN: StringName = &"pitch_down"
const SWING_LEFT: StringName = &"swing_left"
const SWING_RIGHT: StringName = &"swing_right"
## Where the eye sits, which only the overworld may change: the battle's seat is
## solved against the hardware's own picture slots and moving it breaks them.
const DOLLY_IN: StringName = &"dolly_in"
const DOLLY_OUT: StringName = &"dolly_out"

## Back to the framing each rig was built for. The one command that is not a
## nudge, and the one a player on a touchscreen needs most: a camera steered by
## thumb gets lost, and hunting the way back through the same pills that lost it
## is worse than a button saying so.
const RESET: StringName = &"reset"

## WHAT EACH COMMAND IS BOUND TO, DECLARED RATHER THAN READ.
##
## A screen turns every bound event into one of the cartridge's eight buttons and
## claims it before a renderer is offered anything, so a mod that reads keycodes
## out of the leftovers has controls that cannot be rebound, collide silently
## with the d-pad, and do not exist on a phone. `register_action` is the host's
## answer and this is the whole of what this mod declares: the key becomes the
## command, so nothing maps one onto the other.
##
## Bindings are the host's own three kinds. The keys are ones no button and no
## debug key claims in either view; the pad puts the two nudges a camera is most
## asked for on the right stick, which is where a stick camera lives, and the
## zoom on the shoulders. A default already bound to one of the eight is dropped
## by the host and reported, which is how the W and S this file used to read
## would have been caught the day they were written.
const ACTIONS: Array[Dictionary] = [
	{
		"key": ZOOM_IN, "label": "Zoom in",
		"default": [
			{"kind": &"key", "code": KEY_E},
			{"kind": &"pad_button", "code": JOY_BUTTON_RIGHT_SHOULDER},
		],
	},
	{
		"key": ZOOM_OUT, "label": "Zoom out",
		"default": [
			{"kind": &"key", "code": KEY_Q},
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
		"default": [{"kind": &"key", "code": KEY_MINUS}],
	},
	{
		"key": DOLLY_IN, "label": "Push in",
		"default": [{"kind": &"key", "code": KEY_EQUAL}],
	},
	{
		"key": RESET, "label": "Recentre the camera",
		"default": [
			{"kind": &"key", "code": KEY_O},
			{"kind": &"pad_button", "code": JOY_BUTTON_RIGHT_STICK},
		],
	},
]

## The zoom ladder, shared so a notch feels the same in both views. 1.0 is the
## framing each rig was built for.
const ZOOM_LIMITS := Vector2(0.55, 2.0)
const ZOOM_STEP: float = 0.12

## How long any steer takes to settle, in seconds.
const TWEEN_TIME: float = 0.22


## The command [param event] carries, or [constant NONE].
##
## [param wheel_sign] is the player's WHEEL setting: 1 for a notch forward
## zooming in, -1 for the other way round. It is the one part of the binding that
## is a preference rather than a decision, which is why it is the only part
## registered as an option.
## THE WHEEL, which is the one command that is not an action.
##
## Everything a player presses is declared in ACTIONS and arrives already
## resolved, bound and rebindable. A wheel notch is not: it is pointer motion,
## which is exactly what the screen has no opinion about and passes through, and
## it is the one part of the binding that is a PREFERENCE rather than a decision,
## which is why the direction is a setting.
static func command(event: InputEvent, wheel_sign: int = 1) -> StringName:
	var wheel := event as InputEventMouseButton
	if wheel != null and wheel.pressed:
		match wheel.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				return ZOOM_IN if wheel_sign >= 0 else ZOOM_OUT
			MOUSE_BUTTON_WHEEL_DOWN:
				return ZOOM_OUT if wheel_sign >= 0 else ZOOM_IN
	return NONE
