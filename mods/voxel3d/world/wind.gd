extends RefCounted

## The wind, and everything that bends in it.

const WIND: Vector2 = Vector2(0.92, 0.39)
const SWAY_PERIOD: float = 2.9
const GUST_LENGTH: float = 260.0
const CLUMP_JITTER: float = 0.22

const GRASS_REACH: float = 1.6
const FOLIAGE_REACH: float = 2.6

const WALKER_RADIUS: float = 14.0
const WALKER_REACH: float = 2.6

const BEND: String = """
uniform vec2 wind;
uniform float period;
uniform float gust_length;
uniform float jitter;

// One wave travelling along the wind, plus a small per-thing offset so the
// world is many things rather than one sheet.
float bend_at(vec2 at, float phase) {
	return sin((
		TIME / period - dot(at, normalize(wind)) / gust_length + phase * jitter
	) * 6.2831853);
}
"""

const GRASS_CODE: String = """
shader_type spatial;
render_mode specular_disabled, diffuse_lambert;

uniform sampler2D atlas : source_color, filter_nearest;
uniform float reach;
// Where the player is standing, in world pixels, then how far the grass feels
// them and how far it is pushed. A zero reach is nobody there.
uniform vec4 walker;
__BEND__

void vertex() {
	// UV2.x is how far up its own clump this row stands, 0 at the root and 1 at
	// the tip. UV2.y is the clump's own offset within the gust it is standing in.
	float up = UV2.x;
	vec3 at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// The square: the root is pinned and the travel is in the top of the blade.
	float lean = up * up;
	VERTEX.xz += normalize(wind) * bend_at(at.xz, UV2.y) * reach * lean;
	// Whoever is standing in it parts it, radially and by the same square. The
	// falloff eases out to nothing at the radius so a step does not snap it.
	vec2 away = at.xz - walker.xy;
	float span = length(away);
	vec2 side = span > 0.001 ? away / span : normalize(wind);
	VERTEX.xz += side * (1.0 - smoothstep(walker.z * 0.45, walker.z, span))
		* walker.w * lean;
}

void fragment() {
	ALBEDO = texture(atlas, UV).rgb * COLOR.rgb;
}
"""

const FOLIAGE_CODE: String = """
shader_type spatial;
render_mode specular_disabled, diffuse_lambert;

uniform float reach;
__BEND__

void vertex() {
	// A model carries no texture: its colour is baked into vertex colour, so UV
	// is free and UV.x is the sway weight `model.gd` wrote there.
	float up = UV.x;
	// The phase is per INSTANCE, since one mesh is stamped across a whole forest.
	float phase = INSTANCE_CUSTOM.x;
	vec3 at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.xz += normalize(wind) * bend_at(at.xz, phase) * reach * up * up;
}

void fragment() {
	ALBEDO = COLOR.rgb;
}
"""

const SPRITE_CODE: String = """
shader_type spatial;
render_mode specular_disabled, diffuse_lambert, cull_disabled;

uniform sampler2D cutout : source_color, filter_nearest;
uniform float reach;
__BEND__

void vertex() {
	// UV carries the drawing here, so the sway weight moves to UV2.x.
	float up = UV2.x;
	float phase = INSTANCE_CUSTOM.x;
	vec3 at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.xz += normalize(wind) * bend_at(at.xz, phase) * reach * up * up;
}

void fragment() {
	vec4 drawn = texture(cutout, UV);
	if (drawn.a < 0.5) {
		discard;
	}
	ALBEDO = drawn.rgb;
}
"""

var grass: ShaderMaterial = null
var foliage: ShaderMaterial = null
var _sprites: Dictionary = {}


func _init() -> void:
	grass = _material(GRASS_CODE, GRASS_REACH)
	foliage = _material(FOLIAGE_CODE, FOLIAGE_REACH)
	grass.set_shader_parameter("walker", Vector4.ZERO)


func _material(code: String, reach: float) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = code.replace("__BEND__", BEND)
	var made := ShaderMaterial.new()
	made.shader = shader
	made.set_shader_parameter("wind", WIND)
	made.set_shader_parameter("period", SWAY_PERIOD)
	made.set_shader_parameter("gust_length", GUST_LENGTH)
	made.set_shader_parameter("jitter", CLUMP_JITTER)
	made.set_shader_parameter("reach", reach)
	return made


func sprite_material(cutout: Texture2D) -> ShaderMaterial:
	if _sprites.has(cutout):
		return _sprites[cutout]
	var made: ShaderMaterial = _material(SPRITE_CODE, FOLIAGE_REACH)
	made.set_shader_parameter("cutout", cutout)
	_sprites[cutout] = made
	return made


func set_atlas(texture: Texture2D) -> void:
	grass.set_shader_parameter("atlas", texture)


func set_walker(at: Vector3) -> void:
	grass.set_shader_parameter(
		"walker", Vector4(at.x, at.z, WALKER_RADIUS, WALKER_REACH)
	)
