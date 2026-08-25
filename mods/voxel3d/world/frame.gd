extends RefCounted

## The pass over the finished frame: the hour's tint, the grey, the flash, the
## depth of field and the letterbox. Everything in it reaches every pixel of the
## picture, which is why none of it can be expressed in the world.
##
## The hour is applied twice, in the light and here, and the reference says why
## (`lib/DayTint.lua`). A light's colour reaches only what it falls on, so a face
## turned away from the sun, a shadow and anything lit by ambient alone stay the
## colour they were at noon. A pass over the frame is what makes an hour read as
## weather over the whole picture rather than as a lamp in it.
##
## It runs on the SubViewportContainer's own material, once over the composited
## stage and before anything the screen draws on top: the panels, the bars and the
## text box are paper held in front of the world.
##
## The fourth palette row is not night. The host's rows are MORNING, DAY, NIGHT
## and DARK, and DARK is the blacked-out cave palette whose texels are already
## near black. Indoors is neutral, which is the same answer `sky.gd` gives the
## background and `diorama.gd` the sun.

## The colour the whole picture is multiplied by, per time of day.
##
## Read off the reference's table (`DayNight.TINTS`) and pulled toward white: it
## tints a flat composite the hour has not otherwise touched, where this one is
## already lit by a sun that moves with the hour. The hour is applied once in the
## light and once here, so here it is the smaller half.
const DAY_TINT: Array[Color] = [
	# Morning, off the reference's dawn. Warm and very slight: the sunrise is
	# mostly in the sun's own low bearing and long shadows already.
	Color(1.0, 0.96, 0.91),
	# Day is a multiply by white and is skipped rather than drawn.
	Color(1.0, 1.0, 1.0),
	# Night, off the reference's blue, halved toward white. A diorama at night is
	# already dark by its light; what this adds is that it is blue.
	Color(0.86, 0.90, 0.98),
	# The cartridge's dark cave row, which is already black in the palette.
	Color(1.0, 1.0, 1.0),
]

## The move animation's whole-screen flash.
##
## A Game Boy animation flashes by rewriting the background palette maps,
## `BattleAnim_SetBGPals` writing one DMG byte across all seven at once. That byte
## is a permutation, colour i drawn as colour `(byte >> i * 2) & 3`, so what the
## hardware has is not an overlay but a tone curve over four levels: `%00011011`
## goes photographically negative, `%01000000` sends three levels to white,
## `%11111100` sends three to black.
##
## Measured over all 259 move animations at 120 frames each: 3139 frames of 20956
## carry a whole-screen effect, in ten distinct bytes, and no animation reaches a
## uniform byte outside that set. It is a sixth of every move played.
##
## So the curve is what is restated. The four levels are the four luminances a
## Game Boy palette has, and a diorama has continuous tone, so the curve is read
## as a piecewise line through those four control points: exact at each level and
## continuous between. It moves luminance alone, added rather than scaled, so a
## picture's colour survives everything but the ends.
##
## This is the world's half only, and it is whole-screen only when all seven
## background palettes carry the same byte. A byte on one of the seven is
## `BGEffects_LoadPlayerPals` reaching one side of the field, and the thing there
## a diorama does have is the battler, which `battle/renderer.gd` permutes exactly.
## What is left with no answer is a fade of the background behind one battler.
const FLASH_PALETTES: int = 7
const PALETTE_IDENTITY: int = 0xE4
## The luminance of each of the four palette levels, brightest first, which is
## also the identity curve.
const FLASH_LEVELS := Vector4(1.0, 2.0 / 3.0, 1.0 / 3.0, 0.0)

## The letterbox.
##
## A screen laid out in the hardware's 160x144 takes the whole picture: the pack,
## the party, the PC, the dex, an evolution, `DoBattleTransition`. For a view drawn
## in hardware pixels the host paints the bars itself inside the viewport. This one
## is not in that viewport, because a letterbox around a rectangle it never used
## would crop a view that had already filled the surface, so the host says so and
## this view closes the surround. See
## `Gen2ModHost.RENDERER_INTERFACE_MASK_METHOD`.
##
## Black and not a dim, and the transition is why: `DoBattleTransition` can only
## write twenty by eighteen cells, so a dimmed world around a rectangle going
## black is the picture breaking in half rather than the screen closing.
const CODE: String = """
shader_type canvas_item;

uniform vec3 tint = vec3(1.0);
uniform vec4 flash = vec4(1.0, 0.6666667, 0.3333333, 0.0);
uniform bool flashing = false;
uniform vec4 screen_uv = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool masking = false;

// `LoadBattleGrayscalePals`, which the cartridge writes over every background
// palette for the length of the intro. Its four levels are 2bpp and this picture
// is not, so the world takes the continuous grey. It reaches the battlers as
// well as the ground, because they are cards inside this surface.
uniform bool graying = false;

// Depth of field. The distance is worked out rather than sampled: a canvas
// shader has no depth buffer, but it has a camera looking down at a world that
// is mostly a plane, so where the eye stands, how far it is tilted and how wide
// it sees give every row of the picture a distance across the ground. Two trig
// calls a pixel, on a pass measured as costing nothing.
//
// It is the ground's distance and not the pixel's, so a tall thing close by
// wears the blur of the ground behind its head. It does not show: what this is
// spent on is the far field, which lies on the plane the reading is exact for.
uniform int dof_mode = 0;
uniform float dof_radius = 0.0;
uniform float dof_near = 900.0;
uniform float dof_far = 2600.0;
uniform float eye_height = 100.0;
uniform float eye_pitch = 0.6;
uniform float eye_fov = 0.7;

const int DOF_OFF = 0;
const int DOF_PIXELS = 1;
const int DOF_BLUR = 2;

// How far out across the ground the row under [param uv] lands, in world pixels.
float ground_reach(vec2 uv) {
	float ndc = 1.0 - 2.0 * uv.y;
	float up = atan(ndc * tan(eye_fov * 0.5));
	float below = eye_pitch - up;
	// At or above the horizon there is no ground, so the sky takes the maximum
	// rather than a number that runs away.
	if (below <= 0.002) {
		return 1.0e9;
	}
	return eye_height / tan(below);
}

// How near an end a level has to be before the picture is taken to it flat
// rather than lifted toward it. A third of the gap between two of the four
// levels, so nothing inside the range is touched and the two bytes meaning
// "wash the screen out" arrive at white and at black.
const float PINNED_BAND = 0.11;

void fragment() {
	if (dof_mode == DOF_OFF || dof_radius <= 0.0) {
		COLOR = texture(TEXTURE, UV);
	} else {
		float reach = ground_reach(UV);
		float amount = clamp(
			(reach - dof_near) / max(dof_far - dof_near, 1.0), 0.0, 1.0
		);
		float spread = dof_radius * amount;
		if (dof_mode == DOF_PIXELS) {
			// Coarser pixels and not softer ones, which is the one soft focus a
			// Game Boy could have had. The grid is in the viewport's own pixels,
			// so it follows RES and a step is a whole number of them.
			vec2 grid = TEXTURE_PIXEL_SIZE * max(floor(spread), 1.0);
			COLOR = texture(TEXTURE, clamp(
				(floor(UV / grid) + 0.5) * grid, vec2(0.0), vec2(1.0)
			));
		} else {
			vec4 gathered = vec4(0.0);
			for (int y = -1; y <= 1; y++) {
				for (int x = -1; x <= 1; x++) {
					gathered += texture(TEXTURE, clamp(
						UV + vec2(float(x), float(y)) * TEXTURE_PIXEL_SIZE * spread,
						vec2(0.0), vec2(1.0)
					));
				}
			}
			COLOR = gathered / 9.0;
		}
	}
	COLOR.rgb *= tint;
	if (graying) {
		COLOR.rgb = vec3(dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722)));
	}
	if (flashing) {
		float luma = dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
		// Where this pixel sits on the hardware's four levels, brightest first,
		// and the curve read as a line between the two it falls between.
		float at = clamp((1.0 - luma) * 3.0, 0.0, 3.0);
		float step_index = floor(min(at, 2.0));
		float blend = at - step_index;
		float low = flash[int(step_index)];
		float high = flash[int(step_index) + 1];
		float target = mix(low, high, blend);
		vec3 lifted = clamp(COLOR.rgb + (target - luma), 0.0, 1.0);
		// A level pinned at either end has no colour left in it. Adding the
		// difference is right in the middle of the range and not at the ends: a
		// fade to white left a saturated yellow at its own hue, since its
		// luminance was already nearly one. So the last of the range is a mix to
		// the level rather than a lift toward it.
		float pinned = clamp(
			(PINNED_BAND - (0.5 - abs(target - 0.5))) / PINNED_BAND, 0.0, 1.0
		);
		COLOR.rgb = mix(lifted, vec3(target), pinned);
	}
	// Last, and over the flash too: a screen that owns the picture owns the
	// flash. `return` is not allowed in a fragment processor here.
	if (masking && (UV.x < screen_uv.x || UV.y < screen_uv.y
		|| UV.x >= screen_uv.z || UV.y >= screen_uv.w)) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	}
}
"""

var material: ShaderMaterial = null
var _time_of_day: int = 1
var _outside: bool = true
var _flash: Vector4 = FLASH_LEVELS
var _flashing: bool = false
var _graying: bool = false
## The hardware screen's rectangle in this surface's own 0 to 1, and whether the
## surround is closed around it. See CODE.
var _screen_uv := Vector4(0.0, 0.0, 1.0, 1.0)
var _masking: bool = false
var _dof_mode: int = 0
var _dof_radius: float = 0.0
var _dof_near: float = 900.0
var _dof_far: float = 2600.0
var _eye_height: float = 100.0
var _eye_pitch: float = 0.6
var _eye_fov: float = 0.7


func _init() -> void:
	var shader := Shader.new()
	shader.code = CODE
	material = ShaderMaterial.new()
	material.shader = shader
	_apply()


func set_time_of_day(time_of_day: int) -> void:
	_time_of_day = clampi(time_of_day, 0, DAY_TINT.size() - 1)
	_apply()


## [param bounds] is the hardware screen as `x, y, x end, y end` in this
## surface's own 0 to 1.
func set_interface_mask(bounds: Vector4, masked: bool) -> void:
	if masked == _masking and bounds.is_equal_approx(_screen_uv):
		return
	_screen_uv = bounds
	_masking = masked
	_apply()


## Which depth of field this view wears, and how much.
##
## `1` is coarser pixels with distance and `2` an ordinary soft blur. The radius
## is in the viewport's own pixels at the far end of the ramp, which runs from
## [param near] to [param far] in world pixels.
##
## A look and not a saving: drawing the whole frame at a quarter resolution,
## sixteen times fewer fragments, changed the frame time by nothing at all. It is
## here because a far field of flat trees reads better slightly out of focus.
func set_depth_of_field(
	mode: int, radius: float, near: float = 900.0, far: float = 2600.0
) -> void:
	_dof_mode = clampi(mode, 0, 2)
	_dof_radius = maxf(radius, 0.0)
	_dof_near = near
	_dof_far = far
	_apply()


## Whether anything is being spent that needs to know where the eye is.
func wants_eye() -> bool:
	return _dof_mode != 0 and _dof_radius > 0.0


## Where the eye stands, so the shader can tell how far out each row of the
## picture lands. See CODE.
func set_eye(height: float, pitch: float, fov: float) -> void:
	_eye_height = maxf(height, 1.0)
	_eye_pitch = pitch
	_eye_fov = fov
	_apply()


## Whether the whole picture is drawn in grey, which is the battle intro and
## nothing else. See CODE.
func set_grayscale(graying: bool) -> void:
	if graying == _graying:
		return
	_graying = graying
	_apply()


func set_outside(outside: bool) -> void:
	_outside = outside
	_apply()


## The whole-screen flash a move animation is asking for, off the view's own
## `bg_palette_maps`. Anything that is not one leaves the picture alone.
func set_flash(maps: Variant) -> void:
	var bytes: PackedByteArray = _bytes(maps)
	var flashing: bool = bytes.size() >= FLASH_PALETTES and bytes[0] != PALETTE_IDENTITY
	if flashing:
		for slot: int in FLASH_PALETTES:
			if bytes[slot] != bytes[0]:
				flashing = false
				break
	var flash: Vector4 = FLASH_LEVELS
	if flashing:
		var byte: int = bytes[0]
		for level: int in 4:
			flash[level] = FLASH_LEVELS[(byte >> (level * 2)) & 3]
	if flashing == _flashing and flash.is_equal_approx(_flash):
		return
	_flashing = flashing
	_flash = flash
	_apply()


static func _bytes(maps: Variant) -> PackedByteArray:
	if maps is PackedByteArray:
		return maps
	if maps is Array:
		var out := PackedByteArray()
		for value: Variant in maps as Array:
			out.append(int(value) & 0xFF)
		return out
	return PackedByteArray()


func _apply() -> void:
	var tint: Color = DAY_TINT[_time_of_day] if _outside else Color.WHITE
	material.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	material.set_shader_parameter("flash", _flash)
	material.set_shader_parameter("flashing", _flashing)
	material.set_shader_parameter("graying", _graying)
	material.set_shader_parameter("screen_uv", _screen_uv)
	material.set_shader_parameter("masking", _masking)
	material.set_shader_parameter("dof_mode", _dof_mode)
	material.set_shader_parameter("dof_radius", _dof_radius)
	material.set_shader_parameter("dof_near", _dof_near)
	material.set_shader_parameter("dof_far", _dof_far)
	material.set_shader_parameter("eye_height", _eye_height)
	material.set_shader_parameter("eye_pitch", _eye_pitch)
	material.set_shader_parameter("eye_fov", _eye_fov)
