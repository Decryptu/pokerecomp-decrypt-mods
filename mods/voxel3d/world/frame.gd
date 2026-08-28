extends RefCounted

## The pass over the finished frame: the hour's tint, the grey, the flash, the
## depth of field and the letterbox.

const DAY_TINT: Array[Color] = [
	Color(1.0, 0.96, 0.91),
	Color(1.0, 1.0, 1.0),
	Color(0.86, 0.90, 0.98),
	Color(1.0, 1.0, 1.0),
]

const FLASH_PALETTES: int = 7
const PALETTE_IDENTITY: int = 0xE4
const FLASH_LEVELS := Vector4(1.0, 2.0 / 3.0, 1.0 / 3.0, 0.0)

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


func set_interface_mask(bounds: Vector4, masked: bool) -> void:
	if masked == _masking and bounds.is_equal_approx(_screen_uv):
		return
	_screen_uv = bounds
	_masking = masked
	_apply()


func set_depth_of_field(
	mode: int, radius: float, near: float = 900.0, far: float = 2600.0
) -> void:
	_dof_mode = clampi(mode, 0, 2)
	_dof_radius = maxf(radius, 0.0)
	_dof_near = near
	_dof_far = far
	_apply()


func wants_eye() -> bool:
	return _dof_mode != 0 and _dof_radius > 0.0


func set_eye(height: float, pitch: float, fov: float) -> void:
	_eye_height = maxf(height, 1.0)
	_eye_pitch = pitch
	_eye_fov = fov
	_apply()


func set_grayscale(graying: bool) -> void:
	if graying == _graying:
		return
	_graying = graying
	_apply()


func set_outside(outside: bool) -> void:
	_outside = outside
	_apply()


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
