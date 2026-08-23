extends RefCounted

## The sky, generated rather than filled.
##
## The 2D view has no sky: past the edge of the map it fills with the palette's
## background colour and that is the end of it. A perspective view has a real
## horizon in the frame at any shallow pitch, and one flat colour up there reads
## as a backdrop rather than as air.
##
## THE RECIPE is the 8-bit skybox one, from `.references/DRAMATIC_SHAPE/lib/Sky.lua`:
## a short ramp of colours painted as flat horizontal bands, deepest overhead,
## with a CHECKERBOARD of the next band down dithered into the bottom of each.
## Alternating two colours on a pixel grid is how a machine with four colours to a
## palette got a fifth and a sixth out of them, and it is what makes four bands
## read as a gradient instead of as four stripes.
##
## THE COLOURS ARE THE CARTRIDGE'S. Generation II has no sky palette to read, so
## the ramp's two ends are read out of the hour's own background rows instead:
## `atlas.gd:sky_ramp` is what picks them and says why those rows. Handed none,
## which is what a room and the model turntable do, this falls back to the map's
## own background colour taken down twice. Nothing here is authored art.
##
## BANDED BY ELEVATION, not by frame row. The bands are a fact about the sky and
## the camera looks around inside it, so a pitch keypress slides the frame up a
## gradient that stays put. Gluing the zenith to the top edge instead drags the
## whole sky around with the camera, which is the one thing that gives away that
## it is painted on the inside of the window.

## How far down a band the checkerboard starts, as a fraction of that band. A band
## dithered all the way through averages into one flat colour and the step is
## gone; 0.6 leaves the top of each band clean and softens only its bottom edge.
const DITHER_START: float = 0.6
## The checkerboard cell, in screen pixels. Two keeps the sky's grain in the same
## register as the world's own texels at the framing this view opens at.
const DITHER_CELL: float = 2.0
## Bands in the ramp. Four is what the hardware's palettes hold and was right
## while both ends were one colour twice; six since they became the hour's own
## pair, because a four band ramp between two HUES shows every step it takes and
## lands one of them on the muddy middle of the two.
const BANDS: float = 6.0
## How much elevation the ramp spans before it is all zenith, in radians.
##
## MEASURED off the rig rather than picked: the eye sits between 12 and 88 degrees
## above the player and LOOKS DOWN by its own pitch, so with a 42 degree lens the
## shallowest shot in the ladder frames from 33 degrees below the horizon to 9
## above it, and every steeper one frames no sky at all. Sixteen degrees is the
## whole slice of sky this view can ever show, and a ramp spanning more than that
## puts three of its four bands where nobody can look: the first attempt spanned a
## right angle and drew one flat colour, which is what it replaced.
const ELEVATION_SPAN: float = 0.28

## How far the ramp's two ends are taken down when there is only the map's
## background colour to make one of. Their mean is about the single darkening the
## flat fill used, so a shot at the default pitch is neither brighter nor darker
## than it was, only graded.
const HORIZON_DARKEN: float = 0.12
const ZENITH_DARKEN: float = 0.52

const CODE: String = """
shader_type sky;

uniform vec3 horizon_color : source_color;
uniform vec3 zenith_color : source_color;
uniform float bands;
uniform float dither_start;
uniform float cell;
uniform float elevation_span;
uniform vec2 frame;

// Band 0 is the horizon and band `bands - 1` the zenith.
vec3 band_color(float index) {
	return mix(horizon_color, zenith_color, clamp(index / (bands - 1.0), 0.0, 1.0));
}

void sky() {
	float elevation = asin(clamp(EYEDIR.y, -1.0, 1.0));
	// Symmetric about the horizon. What is BELOW it is the void past the edge of
	// the ground, and painting that with the ramp's pale end puts the lightest
	// thing in the frame along its bottom, which reads as fog rolling in. Running
	// the same ramp downward instead leaves the pale band at the horizon, where
	// distance belongs, and takes the void back down to the same deep the zenith
	// is at.
	float up = clamp(abs(elevation) / elevation_span, 0.0, 1.0) * bands;
	float index = min(floor(up), bands - 1.0);
	// 0 at the band's own bottom edge, 1 at its top.
	float within = up - index;
	vec3 here = band_color(index);
	if (1.0 - within <= dither_start) {
		COLOR = here;
	} else {
		// The band BELOW, checkerboarded in: at the lowest band that is itself,
		// which is no dither at all rather than a special case.
		vec3 under = band_color(max(index - 1.0, 0.0));
		vec2 pixel = SCREEN_UV * frame;
		float check = mod(floor(pixel.x / cell) + floor(pixel.y / cell), 2.0);
		COLOR = mix(here, under, check);
	}
}
"""

var sky: Sky = null
## The ramp's two ends as they were last computed, so anything else that has to
## agree with the sky reads them rather than repeating the darkening. `water.gd`
## is what asks: the sky in the lake and the sky over it are one ramp.
var horizon: Color = Color.BLACK
var zenith: Color = Color.BLACK
var _material: ShaderMaterial = null


func _init() -> void:
	var shader := Shader.new()
	shader.code = CODE
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("bands", BANDS)
	_material.set_shader_parameter("dither_start", DITHER_START)
	_material.set_shader_parameter("cell", DITHER_CELL)
	_material.set_shader_parameter("elevation_span", ELEVATION_SPAN)
	_material.set_shader_parameter("frame", Vector2(640.0, 480.0))
	sky = Sky.new()
	sky.sky_material = _material
	# The sky is painted, not lit from: the ambient term is a metered colour and
	# a radiance cubemap of a four-colour gradient would only cost a pass.
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_32


## The two ends of the ramp: the hour's own pair where the caller has one, and
## the map's background colour taken down twice where it has not.
##
## INDOORS THERE IS NO SKY. A room or a cave ends at its walls and what shows
## past them is not air, so the ramp collapses to one colour and the bands and
## the dither vanish with it: both ends of a gradient being the same colour is a
## flat fill, and it needs no second path through the shader to say so. The
## caller passes the colour it wants there, which is `atlas.gd:void_color`, and
## the pair is ignored: a room takes no hour.
func set_background(
	color: Color, outside: bool = true, ramp: PackedColorArray = PackedColorArray()
) -> void:
	if not outside:
		horizon = color
		zenith = color
	elif ramp.size() == 2:
		horizon = ramp[0]
		zenith = ramp[1]
	else:
		horizon = color.darkened(HORIZON_DARKEN)
		zenith = color.darkened(ZENITH_DARKEN)
	_material.set_shader_parameter("horizon_color", horizon)
	_material.set_shader_parameter("zenith_color", zenith)


## The frame the checkerboard is measured against. A dither cell is screen pixels,
## so it has to be told when the window changes or the grain scales with the view.
func set_frame(size: Vector2) -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_material.set_shader_parameter("frame", size)
