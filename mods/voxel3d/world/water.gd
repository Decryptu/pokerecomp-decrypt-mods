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

## THE BANK, which a fragment cannot see and the mesher can. `mesher.gd` walks
## its own water test outward from every piece of land and bakes how far each
## tile of water is from the nearest one; what arrives here is that field as a
## texture, in tiles, and the three terms below are what read it. Handed none,
## which is a cave pool and the model turntable, `bank_ready` is zero and every
## one of them switches off.
##
## FOAM is the reach in tiles at which the line sits, how far the swell's own
## crest carries it in and out, and the two ends of the fade across it. It is
## then THRESHOLDED against a checkerboard rather than drawn faded, because a
## soft white edge on a Game Boy lake is the one thing here that would read as a
## modern effect: the hardware has two colours to put on that line and so does
## this.
const FOAM_REACH: float = 0.60
const FOAM_SWELL: float = 0.30
const FOAM_INNER: float = -0.35
const FOAM_OUTER: float = 0.55
## SHALLOW AND DEEP, in tiles and as a share. Both are held well under full
## strength and the shallow reach is short, and that is the reviewer's own
## reading of the pair built at full: a canal and a river are two tiles wide, so
## a shallow that reaches three turns every one of them to sand.
const SHALLOW_REACH: float = 1.5
const SHALLOW_STRENGTH: float = 0.45
const DEEP_BEGIN: float = 2.5
const DEEP_REACH: float = 4.0
const DEEP_STRENGTH: float = 0.60

## THE THREE THE MENU OFFERS, as one column each: see `options.gd:WATER`.
##
## CALM is every number above, which is the reviewer's own reading of three built
## looks and stays the default. ROUGH and GLASS are the two ends they were shown
## beside it afterwards and asked to keep as CHOICES rather than as replacements:
## a shorter, steeper swell that reads as open sea with weather in it, and a
## flatter one that takes far more of the sky into the water and lets the sun
## gather to a harder point.
##
## A rung sets every one of them, so no press can leave half a look standing.
const STYLE_CALM: int = 0
const STYLE_ROUGH: int = 1
const STYLE_GLASS: int = 2
const STYLE_TILT: Array[float] = [WAVE_TILT, 0.38, 0.10]
const STYLE_LENGTH: Array[Vector2] = [
	Vector2(WAVE_LENGTH_A, WAVE_LENGTH_B),
	Vector2(14.0, 9.0),
	Vector2(WAVE_LENGTH_A, WAVE_LENGTH_B),
]
const STYLE_SPEED: Array[Vector2] = [
	Vector2(WAVE_SPEED_A, WAVE_SPEED_B),
	Vector2(9.0, -6.0),
	Vector2(WAVE_SPEED_A, WAVE_SPEED_B),
]
const STYLE_REFLECT_LEAST: Array[float] = [REFLECT_LEAST, REFLECT_LEAST, 0.25]
const STYLE_REFLECT_MOST: Array[float] = [REFLECT_MOST, REFLECT_MOST, 0.78]
const STYLE_GLINT_STRENGTH: Array[float] = [GLINT_STRENGTH, GLINT_STRENGTH, 0.50]
const STYLE_GLINT_TIGHTNESS: Array[float] = [GLINT_TIGHTNESS, GLINT_TIGHTNESS, 16.0]

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
	// THE SWELL IS THE WORLD'S AND NOT THE CAMERA'S. In `fragment()` VERTEX is
	// the fragment in VIEW space, so reading it directly tied every crest to
	// where the player was standing: walking moved the whole sea and turning
	// swung it, which is a thing water does not do. INV_VIEW_MATRIX takes the
	// fragment back into world space, which is where `wave_length` and
	// `wave_speed` are already expressed and where the sun's own half vector
	// below is already worked out.
	vec3 world_at = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// The crest's own height, which the foam line rides: see `bank` below.
	float height = swell(world_at.xz, slope);
	// HOW FAR THIS WATER IS FROM ITS BANK, in tiles. Open sea where there is no
	// field, so a caller that hands none gets the water it had before.
	float bank = bank_span;
	if (bank_ready > 0.5) {
		vec2 bank_uv = (world_at.xz + bank_origin) / bank_world;
		// PAST THE FIELD IS OPEN WATER AND NOT THE OTHER EDGE OF THE MAP. A
		// sampler answers something for every coordinate, and left to wrap it
		// answered the far side of the map: a shot standing outside the mesh read
		// LAND under the sea behind the camera and foamed the whole of it. What is
		// off the field is unknown, and the honest answer to unknown here is the
		// one that draws nothing.
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
	// SHALLOW OVER ITS BANK AND DEEP AWAY FROM IT, in the water row's own palest
	// and deepest colours rather than in a tint of this one.
	float near = 1.0 - clamp(bank / shallow_reach, 0.0, 1.0);
	water = mix(water, shallow_color, near * shallow_strength * bank_ready);
	water = mix(
		water, deep_color,
		clamp((bank - deep_begin) / deep_reach, 0.0, 1.0) * deep_strength * bank_ready
	);

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
	// THE LINE THE SWELL DRAWS ON THE BANK. The crest carries it up the beach and
	// the trough takes it back, and the checkerboard is what keeps it two colours
	// wide instead of a soft modern edge.
	float edge = bank - foam_reach - height * foam_swell;
	float band = 1.0 - smoothstep(foam_inner, foam_outer, edge);
	float cell = mod(floor(FRAGCOORD.x / 2.0) + floor(FRAGCOORD.y / 2.0), 2.0);
	ALBEDO = mix(ALBEDO, foam_color, step(0.30 + cell * 0.30, band) * bank_ready);
}
"""

var material: ShaderMaterial = null
## Whether the FLAT look is up: see [method set_look].
var _flat: bool = false
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
	set_style(STYLE_CALM)
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


## The bank field and where it lies, both in world pixels, with the tile span the
## texture's 0 to 1 stands for. A null texture switches every term that reads it
## off, which is what a cave pool and every tool that meshes without one get.
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


## THE FLAT LOOK IS THE WATER WITHOUT ITS BANK: the swell, the sky in it and the
## sun on it, which is every term this file had before the field existed, and no
## foam and no shallows. It is the same switch a cave pool and the model
## turntable already take, so nothing here is a look built only to be offered.
func set_look(flat: bool) -> void:
	if _flat == flat:
		return
	_flat = flat
	material.set_shader_parameter("bank_ready", _bank_ready())


## Whether the terms that read the field are switched on at all: there has to be
## a field, and the look has to be the one that draws a bank.
func _bank_ready() -> float:
	var have: bool = _field != null and _world.x > 0.0 and _world.y > 0.0
	return 1.0 if have and not _flat else 0.0


## The three colours the bank is drawn in: the foam's, which is the hardware's own
## white and the same colour the 2D view fills a margin with, and the water row's
## palest and deepest. All three come off `atlas.gd`, so they move with the hour
## and the foam goes out with the light.
func set_shore_colors(foam: Color, shallow: Color, deep: Color) -> void:
	material.set_shader_parameter("foam_color", foam)
	material.set_shader_parameter("shallow_color", shallow)
	material.set_shader_parameter("deep_color", deep)


## Which of the three the surface wears. Every knob the rung owns is set here, so
## the file states each of them once and a rung cannot half-apply.
func set_style(style: int) -> void:
	var rung: int = clampi(style, 0, STYLE_TILT.size() - 1)
	material.set_shader_parameter("wave_tilt", STYLE_TILT[rung])
	material.set_shader_parameter("wave_length", STYLE_LENGTH[rung])
	material.set_shader_parameter("wave_speed", STYLE_SPEED[rung])
	material.set_shader_parameter("reflect_least", STYLE_REFLECT_LEAST[rung])
	material.set_shader_parameter("reflect_most", STYLE_REFLECT_MOST[rung])
	material.set_shader_parameter("glint_strength", STYLE_GLINT_STRENGTH[rung])
	material.set_shader_parameter("glint_tightness", STYLE_GLINT_TIGHTNESS[rung])
