extends RefCounted

## The wind, and everything that bends in it. Nothing is simulated and nothing is
## stored between frames: one attribute per clump and a sway in the vertex
## shader, following the reference's grass shader in `lib/Voxel3D.lua`.
##
## Both shaders live in one file because grass and foliage bend by different
## mechanisms, the grass being mesh geometry and a tree a stamped instance, but
## they bend in the same weather: one direction, one period, one gust length. Two
## files would drift apart the first time one was tuned.
##
## The bend goes by the SQUARE of height. Bending linearly slides the whole clump
## off its own roots; squaring it pins the bottom and puts the travel in the top
## third, which is what a stalk hinged at the ground does. A tree is the same rule
## with the hinge higher: zero through the trunk, rising through the crown.
##
## It is a gust rather than a phase per thing, and both were photographed. One
## wave over the whole field moves it as a single sheet; a phase hashed per clump
## makes neighbours lean opposite ways and reads as static noise. What reads as
## wind is a wave travelling along the wind's direction with the per-thing hash as
## a small offset on top. `mesher.gd:_tufts` hashes the TILE position so the two
## rows of one walk cell differ; `_place_model` hashes the anchor so a tree keeps
## its phase however often the window is rebuilt.
##
## And the player parts it, radially and by the same square, so the blades part
## around them and stay rooted. Pushing a whole clump sideways is the fault the
## square exists to fix, and a body behind it is no better than a breeze. Only the
## overworld sets it: a battle has nobody walking about, so `walker` keeps its
## zero reach and the shader's multiply switches the term off.

## East and a little south, which is across the default shot rather than into it:
## a sway aimed at the eye is a sway nobody can see.
const WIND: Vector2 = Vector2(0.92, 0.39)
## How long one bend takes, in seconds.
const SWAY_PERIOD: float = 2.9
## How long the gust crossing the world is, in world pixels. About what the
## default shot frames, so it is one wave in the frame rather than a ripple.
const GUST_LENGTH: float = 260.0
## How far one clump may run ahead of or behind its gust, as a fraction of a
## cycle. At 1.0 it is the random phase that reads as noise; at 0 it is a sheet.
const CLUMP_JITTER: float = 0.22

## How far a blade's tip travels, in world pixels. A blade is 8, so this is a
## lean rather than a flattening.
const GRASS_REACH: float = 1.6
## How far a crown's top travels. Larger than a blade, and slower in proportion
## by being spread over the crown's whole height.
const FOLIAGE_REACH: float = 2.6

## How far from someone the grass feels them, in world pixels, and how far a
## blade's tip is pushed. A walk cell is 16, so this parts about a cell of grass.
## The push is larger than the wind's lean and still short of the blade's 8 px, so
## the grass leans aside rather than lying flat around a hole.
const WALKER_RADIUS: float = 14.0
const WALKER_REACH: float = 2.6

## The bend, shared verbatim by both shaders so the two cannot drift apart.
## [param at] is the world position, [param phase] the thing's own offset.
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

## The cartridge's own drawing stood up, for a model too far away to turn.
##
## Same bend and same instance phase as `FOLIAGE_CODE`, so a stamp crossing the
## detail ring keeps swaying as it was. Only the colour differs: this reads the
## tileset pixels, cut out with everything that is not the thing transparent.
##
## `cull_disabled` makes it four triangles a tree rather than eight, one quad
## serving both sides. `discard` on the alpha rather than a blend, so the crossed
## planes need no sorting and write depth like everything else.
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
## One per cut-out drawing, since each wears its own picture. Tens of drawings a
## map, and a material is not a draw: the instances under one still batch.
var _sprites: Dictionary = {}


func _init() -> void:
	grass = _material(GRASS_CODE, GRASS_REACH)
	foliage = _material(FOLIAGE_CODE, FOLIAGE_REACH)
	# A zero reach is nobody there. A battle never calls `set_walker`.
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


## The material a cut-out drawing is stamped with, made once per picture.
func sprite_material(cutout: Texture2D) -> ShaderMaterial:
	if _sprites.has(cutout):
		return _sprites[cutout]
	var made: ShaderMaterial = _material(SPRITE_CODE, FOLIAGE_REACH)
	made.set_shader_parameter("cutout", cutout)
	_sprites[cutout] = made
	return made


## Only the grass wears the atlas. A model's colour is baked into its vertices.
func set_atlas(texture: Texture2D) -> void:
	grass.set_shader_parameter("atlas", texture)


## Where the player is, in world pixels. Only the grass is parted.
func set_walker(at: Vector3) -> void:
	grass.set_shader_parameter(
		"walker", Vector4(at.x, at.z, WALKER_RADIUS, WALKER_REACH)
	)
