extends RefCounted

## Water, which is the one surface in this view that is not opaque paint.
##
## Everything else here is a drawing stood up and lit. Water is a MIRROR, and the
## 2D view says so in the only way it can: it animates the tile, cycling the
## ripple art in place. A perspective view has the sky in the frame above the
## lake and nothing of it in the lake, which is what made a pond read as a blue
## floor with a lip round it.
##
## THE REFERENCE'S OWN ARRANGEMENT is in `.references/DRAMATIC_SHAPE/lib/Water.lua`
## and it is a full screen-space pass: the surface lifted out of the terrain mesh,
## drawn between the world and the characters, reflecting the sky through the
## frame's own matrix, then the sun's disc by angle, then the world by walking the
## reflected ray against the depth buffer. The lifting out is done here and is
## `mesher.gd`'s water sink. The rest is not, and the reason is the host: it
## renders on `gl_compatibility`, where there is no screen-space reflection and no
## readable depth to walk. So this takes the two the reference itself puts first,
## which are the two a still picture shows:
##
##   THE SKY IN THE LAKE IS THE SKY OVER IT. `world/sky.gd` already generates that
##   ramp out of the map's own background colour, so the same two colours come
##   here and the water mixes toward them by FRESNEL: a surface seen edge-on is
##   nearly all reflection and one seen from above is nearly all water, which is
##   what puts the bright band at the far shore and keeps the near water dark.
##
##   THE SURFACE IS NOT FLAT. Two travelling waves cross it, and their gradient is
##   the normal every term above is then read through, so the light, the sky and
##   the glint all ride the swell. It is done in the FRAGMENT shader and moves no
##   vertex, which is not a shortcut but the only safe reading: a water quad sits
##   8 px down in a recess whose walls are terrain, and lifting its corners would
##   tear it away from its own bank.
##
## THE CARTRIDGE'S OWN TEXEL IS STILL UNDERNEATH, at NEAREST and unwarped. The
## atlas repaints the water slot from `Gen2WorldAnimation` frame by frame, so the
## drawing already ripples; what is added is the surface it ripples on.

## How far the wave tilts the surface, as a gradient. This is a normal and not a
## displacement, and a lake whose normal swings far enough to catch the sky at
## every point reads as crumpled foil rather than as water.
const WAVE_TILT: float = 0.34
## The two wavelengths that cross, in world pixels, and how fast each travels.
## Deliberately not a ratio of one another, or the two sum into one standing wave
## that pulses in place instead of travelling.
##
## SHORT, about two tiles and one. Four tiles and one and a half was built and
## photographed first and it is not water: at that size the swell is wider than
## anything else in the frame and reads as haze lying over the sea rather than as
## its surface. The picture is `wat_a_sea.png` beside `wat_c_sea.png`.
const WAVE_LENGTH_A: float = 17.0
const WAVE_LENGTH_B: float = 11.0
const WAVE_SPEED_A: float = 7.0
const WAVE_SPEED_B: float = -4.5
## How much of the sky the flattest water takes, and the most it takes edge on.
## The floor is not zero: a lake lit only by its own texel is the blue floor this
## replaces, and a little sky everywhere is what makes it a surface at all. The
## ceiling is well under one: a sea that goes fully to the sky at the horizon
## loses the cartridge's own blue exactly where most of the sea is.
const REFLECT_LEAST: float = 0.14
const REFLECT_MOST: float = 0.55

const CODE: String = """
shader_type spatial;
render_mode specular_disabled, diffuse_lambert;

uniform sampler2D atlas : source_color, filter_nearest;
uniform vec3 horizon_color : source_color;
uniform vec3 zenith_color : source_color;
uniform float wave_tilt;
uniform vec2 wave_length;
uniform vec2 wave_speed;
uniform float reflect_least;
uniform float reflect_most;

// The surface's own height field, in world pixels, and its slope. Two travelling
// waves crossing at an angle: one alone lays parallel bars across a lake.
float swell(vec2 at, out vec2 slope) {
	vec2 dir_a = normalize(vec2(1.0, 0.35));
	vec2 dir_b = normalize(vec2(-0.4, 1.0));
	float phase_a = (dot(at, dir_a) / wave_length.x + TIME * wave_speed.x / wave_length.x) * 6.2831853;
	float phase_b = (dot(at, dir_b) / wave_length.y + TIME * wave_speed.y / wave_length.y) * 6.2831853;
	slope = dir_a * cos(phase_a) + dir_b * cos(phase_b) * 0.6;
	return sin(phase_a) + sin(phase_b) * 0.6;
}

void fragment() {
	vec2 slope;
	swell(VERTEX.xz + NODE_POSITION_WORLD.xz, slope);
	// The wave's normal in view space. The surface is flat and horizontal, so its
	// tangent frame is the world axes and the tilt goes straight in.
	vec3 tilted = normalize(vec3(-slope.x * wave_tilt, 1.0, -slope.y * wave_tilt));
	NORMAL = normalize((VIEW_MATRIX * vec4(tilted, 0.0)).xyz);

	vec4 texel = texture(atlas, UV);
	vec3 water = texel.rgb * COLOR.rgb;

	// FRESNEL off the tilted normal, so the reflection travels with the swell
	// rather than sitting in a fixed band across the lake.
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float mirror = mix(reflect_most, reflect_least, facing);
	// Which band of the sky this piece of water is looking at. A surface seen
	// edge-on reflects the horizon and one seen from above reflects the zenith,
	// which is the same ramp `world/sky.gd` paints and read the same way round.
	vec3 sky = mix(horizon_color, zenith_color, facing);

	ALBEDO = mix(water, sky, mirror);
}
"""

var material: ShaderMaterial = null


func _init() -> void:
	var shader := Shader.new()
	shader.code = CODE
	material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("wave_tilt", WAVE_TILT)
	material.set_shader_parameter(
		"wave_length", Vector2(WAVE_LENGTH_A, WAVE_LENGTH_B)
	)
	material.set_shader_parameter(
		"wave_speed", Vector2(WAVE_SPEED_A, WAVE_SPEED_B)
	)
	material.set_shader_parameter("reflect_least", REFLECT_LEAST)
	material.set_shader_parameter("reflect_most", REFLECT_MOST)


func set_atlas(texture: Texture2D) -> void:
	material.set_shader_parameter("atlas", texture)


## The same two colours `world/sky.gd` is given, taken down the same way, so the
## sky in the lake and the sky over it are one ramp and meet at the waterline.
## Indoors both ends are the one flat rock colour, which is what a cave pool
## should hold.
func set_sky(horizon: Color, zenith: Color) -> void:
	material.set_shader_parameter("horizon_color", horizon)
	material.set_shader_parameter("zenith_color", zenith)
