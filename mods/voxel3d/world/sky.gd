extends RefCounted

## The sky, generated rather than filled.
##
## The 2D view has no sky: past the edge of the map it fills with the palette's
## background colour and that is the end of it. A perspective view has a real
## horizon in the frame at any shallow pitch, and one flat colour up there reads
## as a backdrop rather than as air.
##
## The 8-bit skybox recipe, from `.references/DRAMATIC_SHAPE/lib/Sky.lua`: a
## short ramp painted as flat horizontal bands, deepest overhead, with a
## checkerboard of the next band down dithered into the bottom of each. That
## dither is how a machine with four colours to a palette got a fifth and a sixth
## out of them, and it is what makes bands read as a gradient.
##
## The colours are the cartridge's. Generation II has no sky palette, so the
## ramp's two ends come out of the hour's own background rows; `atlas.gd:sky_ramp`
## picks them and says why. Handed none, which is what a room and the model
## turntable do, this falls back to the background colour taken down twice.
##
## Banded by ELEVATION, not by frame row, so a pitch keypress slides the frame up
## a gradient that stays put. Gluing the zenith to the top edge drags the whole
## sky around with the camera.

## How far down a band the checkerboard starts, as a fraction of that band. A band
## dithered all the way through averages into one flat colour and the step is
## gone; 0.6 leaves the top of each band clean and softens only its bottom edge.
const DITHER_START: float = 0.6
## The checkerboard cell, in screen pixels. Two keeps the sky's grain in the same
## register as the world's own texels at the framing this view opens at.
const DITHER_CELL: float = 2.0
## Bands in the ramp. Four while both ends were one colour twice; six since they
## became the hour's own pair, because four bands between two hues shows every
## step and lands one on the muddy middle.
const BANDS: float = 6.0
## How much elevation the ramp spans before it is all zenith, in radians.
##
## Measured off the rig rather than picked: the eye sits 12 to 88 degrees above
## the player and looks down by its own pitch, so with a 42 degree lens the
## shallowest shot frames 33 degrees below the horizon to 9 above it and every
## steeper one frames none. A ramp spanning more than that puts most of its bands
## where nobody can look, which is what the first attempt did.
const ELEVATION_SPAN: float = 0.28

## How far the two ends are taken down when there is only the background colour
## to make a ramp of. Their mean is about the flat fill's own darkening.
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
	// Symmetric about the horizon. Below it is the void past the edge of the
	// ground, and the ramp's pale end there reads as fog rolling in. Running the
	// ramp downward keeps the pale band at the horizon, where distance belongs.
	float up = clamp(abs(elevation) / elevation_span, 0.0, 1.0) * bands;
	float index = min(floor(up), bands - 1.0);
	// 0 at the band's own bottom edge, 1 at its top.
	float within = up - index;
	vec3 here = band_color(index);
	if (1.0 - within <= dither_start) {
		COLOR = here;
	} else {
		// The band below, checkerboarded in. At the lowest band that is itself,
		// which is no dither rather than a special case.
		vec3 under = band_color(max(index - 1.0, 0.0));
		vec2 pixel = SCREEN_UV * frame;
		float check = mod(floor(pixel.x / cell) + floor(pixel.y / cell), 2.0);
		COLOR = mix(here, under, check);
	}
}
"""

var sky: Sky = null
## The two ends as last computed, so anything that has to agree with the sky
## reads them rather than repeating the darkening. `water.gd` asks.
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
	# Painted, not lit from: the ambient term is a metered colour, so a radiance
	# cubemap of a flat gradient would only cost a pass.
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_32


## The two ends of the ramp: the hour's own pair where the caller has one, and
## the map's background colour taken down twice where it has not.
##
## Indoors there is no sky: the ramp collapses to one colour and the bands and
## dither go with it, since both ends being one colour is a flat fill and needs
## no second path through the shader. The caller passes `atlas.gd:void_color`,
## and the pair is ignored because a room takes no hour.
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


## The frame the checkerboard is measured against. A dither cell is screen
## pixels, so the grain would scale with the view if this were not told.
func set_frame(size: Vector2) -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_material.set_shader_parameter("frame", size)
