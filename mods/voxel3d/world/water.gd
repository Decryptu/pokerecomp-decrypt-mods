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
##   THE SUN IS IN THE LAKE, hung BY ANGLE rather than by screen position, which
##   is the reference's own arrangement and the reason it works at all here: the
##   reflection of a sun 40 to 58 degrees up is usually off the top of the frame,
##   so a mirror that only shows what the camera can see would show no sun at any
##   hour. What is asked instead is how nearly this piece of water is tilted to
##   bounce the sun into the eye, which is a fact about the swell and not about
##   the frame, and the answer rides the waves as a moving band of glitter.
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

## EVERY NUMBER BELOW IS THE REVIEWER'S, picked in round nine off three built and
## photographed looks rather than described: a wide gentle swell under a calm sky.
## `answers_round9.txt`, and the three are `wat_a_sea.png`, `wat_b_sea.png` and
## `wat_c_sea.png` in the survey directory.
##
## How far the wave tilts the surface, as a gradient. This is a normal and not a
## displacement, and a lake whose normal swings far enough to catch the sky at
## every point reads as crumpled foil rather than as water.
const WAVE_TILT: float = 0.22
## The two wavelengths that cross, in world pixels, and how fast each travels.
## Deliberately not a ratio of one another, or the two sum into one standing wave
## that pulses in place instead of travelling.
##
## LONG, about four tiles and two: a slow swell running under the whole lake
## rather than a chop on top of it. A wavelength of two tiles was built and put
## up beside it and the reviewer did not take it.
const WAVE_LENGTH_A: float = 34.0
const WAVE_LENGTH_B: float = 19.0
const WAVE_SPEED_A: float = 7.0
const WAVE_SPEED_B: float = -4.5
## How much of the sky the flattest water takes, and the most it takes edge on.
## The floor is not zero: a lake lit only by its own texel is the blue floor this
## replaces, and a little sky everywhere is what makes it a surface at all. The
## ceiling is well under one: a sea that goes fully to the sky at grazing angles
## loses the cartridge's own blue exactly where most of the sea is. These are the
## calmest of the three that were offered, so the water stays the colour the
## cartridge painted it and the sky is what grades it toward the horizon.
const REFLECT_LEAST: float = 0.10
const REFLECT_MOST: float = 0.45

## The sun's own disc in the water: how much of the light's colour the glint adds
## at its brightest, and how tightly it is gathered.
##
## Both are held down deliberately. A specular lobe on water wants to be a hard
## white star, and this is a Game Boy lake whose every other colour comes off the
## cartridge's own palette: what is wanted is the glitter that says a surface is
## tilting under a light, not a lens flare. The glint takes the SUN's colour
## rather than white, so it deepens with the hour exactly as everything else in
## the picture does, and it is scaled by the light's own energy, which is what
## puts it out at night with nothing else to say so.
const GLINT_STRENGTH: float = 0.30
const GLINT_TIGHTNESS: float = 8.0

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
uniform vec3 sun_direction;
uniform vec3 sun_color : source_color;
uniform float glint_strength;
uniform float glint_tightness;

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

	// THE SUN'S DISC, off the half vector between the eye and the sun, which is
	// the same question as "does this facet bounce the sun at me" and needs no
	// screen-space anything. Both vectors are taken back into world space, since
	// the swell's normal is authored there and the camera moves.
	vec3 eye = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 half_way = normalize(sun_direction + eye);
	float glint = pow(clamp(dot(tilted, half_way), 0.0, 1.0), glint_tightness);

	ALBEDO = mix(water, sky, mirror) + sun_color * (glint * glint_strength);
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
	material.set_shader_parameter("glint_strength", GLINT_STRENGTH)
	material.set_shader_parameter("glint_tightness", GLINT_TIGHTNESS)
	set_sun(Vector3(0.0, 1.0, 0.0), Color.BLACK)


## Where the sun stands and what colour it is, both taken from the one light the
## diorama hangs: `diorama.gd:SUN_ROTATION` moves it by the hour and `DAY_LIGHT`
## and `DAY_ENERGY` colour it, so the glint is the same sun the rest of the
## picture is lit by rather than a second one authored here.
func set_sun(direction: Vector3, color: Color) -> void:
	material.set_shader_parameter("sun_direction", direction.normalized())
	material.set_shader_parameter("sun_color", color)


func set_atlas(texture: Texture2D) -> void:
	material.set_shader_parameter("atlas", texture)


## The same two colours `world/sky.gd` is given, taken down the same way, so the
## sky in the lake and the sky over it are one ramp and meet at the waterline.
## Indoors both ends are the one flat rock colour, which is what a cave pool
## should hold.
func set_sky(horizon: Color, zenith: Color) -> void:
	material.set_shader_parameter("horizon_color", horizon)
	material.set_shader_parameter("zenith_color", zenith)
