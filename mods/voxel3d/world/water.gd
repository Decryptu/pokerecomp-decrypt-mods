extends RefCounted

## Water, which is the one surface in this view that is not opaque paint.
##
## Everything else here is a drawing stood up and lit. Water is a mirror, and the
## 2D view says so in the only way it can, by cycling the ripple art in place. A
## perspective view has the sky above the lake and none of it in the lake, which
## made a pond read as a blue floor with a lip round it.
##
## The reference's arrangement is in `.references/DRAMATIC_SHAPE/lib/Water.lua`,
## a full screen-space pass. The lifting out of the terrain mesh is done here, in
## `mesher.gd`'s water sink; the reflected-ray walk is not, because the host
## renders on `gl_compatibility`, where there is no screen-space reflection and no
## readable depth. So this takes the two the reference puts first:
##
##   The sky in the lake is the sky over it. `world/sky.gd` generates that ramp,
##   so the same two colours come here and the water mixes toward them by
##   Fresnel: a surface seen edge-on is nearly all reflection and one seen from
##   above nearly all water, which puts the bright band at the far shore.
##
##   The sun is in the lake, hung by ANGLE rather than screen position, which is
##   why it works here at all: the reflection of a sun 40 to 58 degrees up is
##   usually off the top of the frame, so a mirror showing only what the camera
##   sees would show no sun at any hour. What is asked is how nearly this water
##   is tilted to bounce the sun into the eye, which is a fact about the swell.
##
##   The surface is not flat: two travelling waves cross it, and their gradient
##   is the normal every term above is read through. It is done in the FRAGMENT
##   shader and moves no vertex, which is the only safe reading: a water quad
##   sits 8 px down in a recess whose walls are terrain, and lifting its corners
##   would tear it from its bank.
##
## The cartridge's own texel is still underneath, at nearest and unwarped. The
## atlas repaints the water slot frame by frame, so the drawing already ripples;
## what is added is the surface it ripples on.

## Every number below was picked off three built and photographed looks rather
## than described: a wide gentle swell under a calm sky.
##
## How far the wave tilts the surface, as a gradient. This is a normal and not a
## displacement, and a lake whose normal swings far enough to catch the sky at
## every point reads as crumpled foil rather than as water.
const WAVE_TILT: float = 0.22
## The two wavelengths that cross, in world pixels, and how fast each travels.
## Deliberately not a ratio of one another, or the two sum into one standing wave
## that pulses in place. Long, about four tiles and two: a slow swell under the
## whole lake rather than a chop on top of it.
const WAVE_LENGTH_A: float = 34.0
const WAVE_LENGTH_B: float = 19.0
const WAVE_SPEED_A: float = 7.0
const WAVE_SPEED_B: float = -4.5
## How much of the sky the flattest water takes, and the most it takes edge on.
## The floor is not zero: a lake lit only by its own texel is the blue floor this
## replaces. The ceiling is well under one: a sea that goes fully to the sky at
## grazing angles loses the cartridge's blue exactly where most of the sea is.
const REFLECT_LEAST: float = 0.10
const REFLECT_MOST: float = 0.45

## The sun's own disc in the water: how much of the light's colour the glint adds
## at its brightest, and how tightly it is gathered.
##
## Both are held down. A specular lobe wants to be a hard white star, and this is
## a Game Boy lake: what is wanted is the glitter that says a surface is tilting
## under a light, not a lens flare. The glint takes the sun's colour rather than
## white, so it deepens with the hour, and it is scaled by the light's energy,
## which is what puts it out at night.
const GLINT_STRENGTH: float = 0.30
const GLINT_TIGHTNESS: float = 8.0

## The bank, which a fragment cannot see and the mesher can. `mesher.gd` walks its
## water test outward from every piece of land and bakes how far each tile of
## water is from the nearest; what arrives is that field as a texture, in tiles.
## Handed none, which is a cave pool and the model turntable, `bank_ready` is zero
## and every term reading it switches off.
##
## Foam is the reach in tiles at which the line sits, how far the swell's crest
## carries it in and out, and the two ends of the fade across it. It is
## thresholded against a checkerboard rather than faded: the hardware has two
## colours to put on that line and so does this.
const FOAM_REACH: float = 0.60
const FOAM_SWELL: float = 0.30
const FOAM_INNER: float = -0.35
const FOAM_OUTER: float = 0.55
## Shallow and deep, in tiles and as a share. Both are held well under full
## strength and the shallow reach is short: a canal and a river are two tiles
## wide, so a shallow reaching three turns every one of them to sand.
const SHALLOW_REACH: float = 1.5
const SHALLOW_STRENGTH: float = 0.45
const DEEP_BEGIN: float = 2.5
const DEEP_REACH: float = 4.0
const DEEP_STRENGTH: float = 0.60

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
uniform sampler2D bank_field : filter_linear, repeat_disable;
// The field's extent and origin in WORLD pixels, so the lookup is one divide.
uniform vec2 bank_world;
uniform vec2 bank_origin;
uniform float bank_span;
uniform float bank_ready;
uniform vec3 foam_color : source_color;
uniform vec3 shallow_color : source_color;
uniform vec3 deep_color : source_color;
uniform float foam_reach;
uniform float foam_swell;
uniform float foam_inner;
uniform float foam_outer;
uniform float shallow_reach;
uniform float shallow_strength;
uniform float deep_begin;
uniform float deep_reach;
uniform float deep_strength;

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
	// The swell is the world's and not the camera's. In `fragment()` VERTEX is
	// the fragment in VIEW space, so reading it directly tied every crest to
	// where the player was standing. INV_VIEW_MATRIX takes it back into world
	// space, which is where `wave_length` and `wave_speed` are expressed.
	vec3 world_at = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// The crest's own height, which the foam line rides: see `bank` below.
	float height = swell(world_at.xz, slope);
	// How far this water is from its bank, in tiles. Open sea where there is no
	// field, so a caller handing none gets the water it had before.
	float bank = bank_span;
	if (bank_ready > 0.5) {
		vec2 bank_uv = (world_at.xz + bank_origin) / bank_world;
		// Past the field is open water and not the other edge of the map. Left to
		// wrap, the sampler answered the far side: a camera outside the mesh read
		// land under the sea behind it and foamed the whole of it.
		if (bank_uv == clamp(bank_uv, vec2(0.0), vec2(1.0))) {
			bank = texture(bank_field, bank_uv).r * bank_span;
		}
	}
	// The wave's normal in view space. The surface is flat and horizontal, so its
	// tangent frame is the world axes and the tilt goes straight in.
	vec3 tilted = normalize(vec3(-slope.x * wave_tilt, 1.0, -slope.y * wave_tilt));
	NORMAL = normalize((VIEW_MATRIX * vec4(tilted, 0.0)).xyz);

	vec4 texel = texture(atlas, UV);
	vec3 water = texel.rgb * COLOR.rgb;
	// Shallow over its bank and deep away from it, in the water row's own palest
	// and deepest colours rather than in a tint.
	float near = 1.0 - clamp(bank / shallow_reach, 0.0, 1.0);
	water = mix(water, shallow_color, near * shallow_strength * bank_ready);
	water = mix(
		water, deep_color,
		clamp((bank - deep_begin) / deep_reach, 0.0, 1.0) * deep_strength * bank_ready
	);

	// Fresnel off the tilted normal, so the reflection travels with the swell.
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float mirror = mix(reflect_most, reflect_least, facing);
	// Which band of the sky this piece of water is looking at. A surface seen
	// edge-on reflects the horizon and one seen from above reflects the zenith,
	// which is the same ramp `world/sky.gd` paints and read the same way round.
	vec3 sky = mix(horizon_color, zenith_color, facing);

	// The sun's disc, off the half vector between the eye and the sun: the same
	// question as "does this facet bounce the sun at me", with no screen-space
	// anything. Both vectors go back into world space, where the normal is.
	vec3 eye = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 half_way = normalize(sun_direction + eye);
	float glint = pow(clamp(dot(tilted, half_way), 0.0, 1.0), glint_tightness);

	ALBEDO = mix(water, sky, mirror) + sun_color * (glint * glint_strength);
	// The line the swell draws on the bank: the crest carries it up the beach and
	// the trough takes it back, and the checkerboard keeps it two colours wide.
	float edge = bank - foam_reach - height * foam_swell;
	float band = 1.0 - smoothstep(foam_inner, foam_outer, edge);
	float cell = mod(floor(FRAGCOORD.x / 2.0) + floor(FRAGCOORD.y / 2.0), 2.0);
	ALBEDO = mix(ALBEDO, foam_color, step(0.30 + cell * 0.30, band) * bank_ready);
}
"""

var material: ShaderMaterial = null
## What [method set_bank] was last handed, so a look changing under a standing
## map needs no rebuild of anything.
var _field: Texture2D = null
var _world: Vector2 = Vector2.ZERO
var _origin: Vector2 = Vector2.ZERO
var _span: float = 0.0


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
	material.set_shader_parameter("foam_reach", FOAM_REACH)
	material.set_shader_parameter("foam_swell", FOAM_SWELL)
	material.set_shader_parameter("foam_inner", FOAM_INNER)
	material.set_shader_parameter("foam_outer", FOAM_OUTER)
	material.set_shader_parameter("shallow_reach", SHALLOW_REACH)
	material.set_shader_parameter("shallow_strength", SHALLOW_STRENGTH)
	material.set_shader_parameter("deep_begin", DEEP_BEGIN)
	material.set_shader_parameter("deep_reach", DEEP_REACH)
	material.set_shader_parameter("deep_strength", DEEP_STRENGTH)
	material.set_shader_parameter("bank_ready", 0.0)
	set_sun(Vector3(0.0, 1.0, 0.0), Color.BLACK)


## Where the sun stands and its colour, both from the one light the diorama
## hangs, so the glint is the same sun the picture is lit by.
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


## The bank field and where it lies, in world pixels, with the tile span the
## texture's 0 to 1 stands for. A null texture switches every term reading it off.
func set_bank(
	field: Texture2D, world: Vector2, origin: Vector2, span: float
) -> void:
	_field = field
	_world = world
	_origin = origin
	_span = span
	material.set_shader_parameter("bank_field", field)
	material.set_shader_parameter("bank_world", world)
	material.set_shader_parameter("bank_origin", origin)
	material.set_shader_parameter("bank_span", span)
	material.set_shader_parameter("bank_ready", _bank_ready())


## Whether the terms reading the field are on: a cave pool and the model
## turntable are handed none.
func _bank_ready() -> float:
	return 1.0 if _field != null and _world.x > 0.0 and _world.y > 0.0 else 0.0


## The three colours the bank is drawn in: the foam's, which is the hardware's own
## white, and the water row's palest and deepest. All three come off `atlas.gd`,
## so they move with the hour and the foam goes out with the light.
func set_shore_colors(foam: Color, shallow: Color, deep: Color) -> void:
	material.set_shader_parameter("foam_color", foam)
	material.set_shader_parameter("shallow_color", shallow)
	material.set_shader_parameter("deep_color", deep)
