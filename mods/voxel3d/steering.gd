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
## KEYS THE HOST HAS NOT ALREADY CLAIMED, WHICH IS NOT A STYLE CHOICE.
##
## A screen resolves every bound event into a `Gen2Button` and takes it before a
## renderer is offered anything, so a mod key that is also a binding never
## arrives at all. This view asked for W, S, A and D, which are the host's own
## default d-pad, and its pitch and swing had therefore never once fired on a
## keyboard. Nothing warned: the mod read a keycode that the screen had already
## eaten, and both sides were behaving correctly.
##
## So the cluster is IJKL, which no button and no debug key claims in either
## view, and Q/E and the +/- pair keep what they had for the same reason.
## Checked against `Gen2InputActions.DEFAULTS` and the debug keys of both
## screens; a player who REBINDS onto these takes them back, and there is
## nothing this file can do about that. The fix for all of it is a mod declaring
## its actions to the host and being bound like anything else, which is an
## engine request, and it is also what puts these on a phone at all.
static func command(event: InputEvent, wheel_sign: int = 1) -> StringName:
	var key := event as InputEventKey
	if key != null and key.pressed:
		match key.keycode:
			KEY_Q:
				return ZOOM_OUT
			KEY_E:
				return ZOOM_IN
			KEY_I:
				return PITCH_UP
			KEY_K:
				return PITCH_DOWN
			KEY_J:
				return SWING_LEFT
			KEY_L:
				return SWING_RIGHT
			KEY_MINUS, KEY_KP_SUBTRACT:
				return DOLLY_OUT
			KEY_EQUAL, KEY_KP_ADD:
				return DOLLY_IN
			_:
				return NONE

	var wheel := event as InputEventMouseButton
	if wheel != null and wheel.pressed:
		match wheel.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				return ZOOM_IN if wheel_sign >= 0 else ZOOM_OUT
			MOUSE_BUTTON_WHEEL_DOWN:
				return ZOOM_OUT if wheel_sign >= 0 else ZOOM_IN
	return NONE
