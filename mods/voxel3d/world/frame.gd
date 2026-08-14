extends RefCounted

## THE PASS OVER THE FINISHED FRAME, and the hour's own colour in it.
##
## Everything else in this view colours the WORLD: the sun's bearing and energy,
## the ambient term, the sky's ramp, the palette the cartridge itself supplies per
## time of day. What none of them does is colour the PICTURE. The reference does
## both and says why (`lib/DayTint.lua`): the clock reaches its 3D pass through
## shader uniforms, and the frame is multiplied by the hour on top of that, so an
## evening is warm in the light AND warm in the image.
##
## The difference is not decoration. A light's colour reaches only what the light
## falls on, so a face turned away from the sun, a shadow, and anything lit by
## ambient alone all stay the colour they were at noon. A pass over the frame
## reaches every pixel, which is what makes an hour read as weather over the whole
## picture rather than as a lamp somewhere in it.
##
## WHERE IT GOES is the SubViewportContainer's own material, so it runs once over
## the composited stage and before anything the screen draws on top. The panels,
## the bars and the text box are paper held in front of the world, not part of it,
## and the reference makes exactly the same cut for exactly the same reason.
##
## THE FOURTH ROW IS NOT NIGHT. The host's palette rows are MORNING, DAY, NIGHT
## and DARK, and DARK is the blacked-out cave palette whose every texel is already
## near black. Tinting that is tinting nothing, twice.
##
## INDOORS IS NEUTRAL. A room has no sky to take its colour from, which is the
## same answer `sky.gd` gives the background and `diorama.gd` gives the sun.

## The colour the whole picture is multiplied by, per time of day.
##
## Read off the reference's own table (`DayNight.TINTS`) and then pulled toward
## white, because the two views are not in the same place: it tints a flat
## composite that the hour has otherwise not touched, where this one is already
## lit by a sun whose colour and energy MOVE with the hour and metered so the
## brightest thing in the frame sits just under the top. The hour is applied
## once in the light and once here, so here it is the smaller half.
const DAY_TINT: Array[Color] = [
	# Morning, off the reference's dawn. Warm and very slight: the sunrise is
	# mostly in the sun's own low bearing and long shadows already.
	Color(1.0, 0.96, 0.91),
	# Day is a multiply by white and is SKIPPED rather than drawn.
	Color(1.0, 1.0, 1.0),
	# Night, off the reference's own blue, halved toward white. A diorama at
	# night is already dark by its light; what this adds is that it is BLUE.
	Color(0.86, 0.90, 0.98),
	# The cartridge's dark cave row, which is already black in the palette.
	Color(1.0, 1.0, 1.0),
]

## THE OTHER PASS OVER THE FINISHED FRAME IS THE MOVE ANIMATION'S FLASH, and it
## is the same shader for the same reason: it reaches every pixel of the picture
## and nothing in the world can express it.
##
## A Game Boy animation flashes the screen by rewriting the BACKGROUND palette
## maps, `BattleAnim_SetBGPals` writing one DMG byte across all seven of them at
## once. That byte is a permutation, colour i of every palette drawn as colour
## `(byte >> i * 2) & 3`, so what the hardware has is not an overlay but a TONE
## CURVE over four levels: `%00011011` swaps 0 with 3 and 1 with 2 and the screen
## goes photographically negative, `%01000000` sends three of the four levels to
## white, `%11111100` sends three of them to black.
##
## Measured over all 259 of the cartridge's own move animations, 120 frames each:
## 3139 frames of 20956 carry a whole-screen effect, in TEN distinct bytes, and
## no animation ever reaches a uniform byte outside that set. It is not a rare
## flourish and it is not one white flash; it is a sixth of every move played.
##
## SO THE CURVE IS WHAT IS RESTATED, not the flash. The four levels are the four
## luminances a Game Boy palette has, brightest first, and a diorama has
## continuous tone rather than four steps, so the curve is read as a piecewise
## line through those four control points: exact at each of the hardware's own
## levels and continuous between them. What it moves is LUMINANCE alone, added
## rather than scaled, so a picture's colour survives everything but the ends,
## where a flash is meant to wash it out.
##
## THIS IS THE WORLD'S HALF ONLY, and it is a whole-screen effect only when all
## SEVEN background palettes carry the same byte. The eighth is left at identity
## by the hardware and is not part of it. A byte on ONE of the seven is
## `BGEffects_LoadPlayerPals` reaching one side of the field, and the thing on
## that side a diorama does have is the BATTLER: the cartridge draws both pics on
## the background layer, so slots 0 and 1 are their palettes and
## `battle/renderer.gd` permutes each pic exactly rather than approximating it
## here. What is left with no answer is a fade of the background BEHIND one
## battler, which in a diorama is a hillside.
const FLASH_PALETTES: int = 7
const PALETTE_IDENTITY: int = 0xE4
## The luminance of each of the four palette levels, brightest first, which is
## also the identity curve.
const FLASH_LEVELS := Vector4(1.0, 2.0 / 3.0, 1.0 / 3.0, 0.0)

const CODE: String = """
shader_type canvas_item;

uniform vec3 tint = vec3(1.0);
uniform vec4 flash = vec4(1.0, 0.6666667, 0.3333333, 0.0);
uniform bool flashing = false;

void fragment() {
	COLOR = texture(TEXTURE, UV);
	COLOR.rgb *= tint;
	if (flashing) {
		float luma = dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
		// Where this pixel sits on the hardware's four levels, brightest first,
		// and the curve read as a line between the two it falls between.
		float at = clamp((1.0 - luma) * 3.0, 0.0, 3.0);
		float step_index = floor(min(at, 2.0));
		float blend = at - step_index;
		float low = flash[int(step_index)];
		float high = flash[int(step_index) + 1];
		COLOR.rgb = clamp(COLOR.rgb + (mix(low, high, blend) - luma), 0.0, 1.0);
	}
}
"""

var material: ShaderMaterial = null
var _time_of_day: int = 1
var _outside: bool = true
var _flash: Vector4 = FLASH_LEVELS
var _flashing: bool = false


func _init() -> void:
	var shader := Shader.new()
	shader.code = CODE
	material = ShaderMaterial.new()
	material.shader = shader
	_apply()


func set_time_of_day(time_of_day: int) -> void:
	_time_of_day = clampi(time_of_day, 0, DAY_TINT.size() - 1)
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
