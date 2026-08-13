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

const CODE: String = """
shader_type canvas_item;

uniform vec3 tint = vec3(1.0);

void fragment() {
	COLOR = texture(TEXTURE, UV);
	COLOR.rgb *= tint;
}
"""

var material: ShaderMaterial = null
var _time_of_day: int = 1
var _outside: bool = true


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


func _apply() -> void:
	var tint: Color = DAY_TINT[_time_of_day] if _outside else Color.WHITE
	material.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
