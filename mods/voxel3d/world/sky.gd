extends RefCounted

## The sky, generated rather than filled.
## The sky, generated rather than filled.

const DITHER_START: float = 0.6
const DITHER_CELL: float = 2.0
const BANDS: float = 6.0
const ELEVATION_SPAN: float = 0.28

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
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_32


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


func set_frame(size: Vector2) -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_material.set_shader_parameter("frame", size)
