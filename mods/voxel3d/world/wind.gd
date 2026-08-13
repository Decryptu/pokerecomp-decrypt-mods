extends RefCounted

## THE WIND, and everything that bends in it.
##
## A still world is what most gives a diorama away as geometry rather than as a
## place, and the reference answers that with the cheapest possible motion: one
## attribute per clump and a sway in the vertex shader, root pinned and the tip
## bending by the SQUARE of its height (`lib/Voxel3D.lua`, the grass shader).
## Nothing is simulated and nothing is stored between frames.
##
## ONE FILE FOR BOTH SHADERS, and that is the point of it. The grass and the
## foliage bend by different mechanisms, because the grass is geometry in a mesh
## and a tree is a stamped instance, but they are bending in the SAME WEATHER: one
## direction, one period, one gust length, one wave crossing the map. Two files
## would each hold their own copy of that and the world's wind would quietly come
## apart the first time one of them was tuned.
##
## WHY THE SQUARE. A blade bending linearly slides sideways, which reads as the
## whole clump sliding off its own roots. Squaring it holds the bottom still and
## puts nearly all of the travel in the top third, which is what a stalk hinged at
## the ground actually does. A tree is the same rule with the hinge higher up: the
## weight is zero through the trunk, because a trunk that sways is a tree falling
## over, and rises through the crown.
##
## WHY A GUST RATHER THAN A PHASE PER THING. Both were built and photographed. One
## wave over the whole field moves it as a single sheet, which is worse than not
## moving it, because a sheet is obviously one object where a field is obviously
## many. But a phase hashed per clump and left at that is worse again: neighbours
## lean opposite ways at the same instant and the meadow reads as static noise
## rather than as weather.
##
## What reads as wind is a wave TRAVELLING along the wind's own direction, with
## the per-thing hash as a small offset on top rather than as the whole phase. So
## a gust visibly crosses the field, and inside it every clump is a little ahead
## of or behind its neighbour. For grass `mesher.gd:_tufts` hashes the TILE
## position, not the cell, so even the two rows of one walk cell differ, which is
## the separation the cartridge's own overdraw implies when the player walks
## between them; for a stamped model `_place_model` hashes the anchor, so a tree
## keeps the same phase however often the window is rebuilt.
##
## WHAT IT DOES NOT DO, and the reference does: push the tufts aside as the player
## walks through them, swept between last frame's position and this one. That
## needs the player's position per frame and these materials have no idea where
## anyone is. It is open work, and it is the half of this that a player feels
## rather than sees.

## Which way the wind blows, as a direction in the world's own plane. East and a
## little south, which is ACROSS the default shot rather than into it: a sway
## aimed at the eye is a sway nobody can see.
const WIND: Vector2 = Vector2(0.92, 0.39)
## How long one bend takes, in seconds.
const SWAY_PERIOD: float = 2.9
## How long the gust crossing the world is, in world pixels. Sixteen cells is
## about what the default shot frames, so a gust of about that is one wave in the
## frame at a time rather than a ripple running through it.
const GUST_LENGTH: float = 260.0
## How far one clump or one tree may run ahead of or behind the gust it stands in,
## as a fraction of one cycle. Small: at 1.0 this is the random phase that reads
## as noise, and at 0 the world is a sheet.
const CLUMP_JITTER: float = 0.22

## How far a blade's tip travels, in world pixels. A walk cell is 16 and a blade
## is 8, so this is a lean rather than a flattening: grass that lies down in a
## breeze reads as wind damage.
const GRASS_REACH: float = 1.6
## How far a CROWN's top travels. Larger than a blade because a tree is larger,
## and slower in proportion by being spread over the crown's whole height rather
## than over eight pixels.
const FOLIAGE_REACH: float = 2.6

## The bend, shared verbatim by both shaders so the two cannot drift apart.
## [param at] is the world position, [param phase] the thing's own offset.
const BEND: String = """
uniform vec2 wind;
uniform float period;
uniform float gust_length;
uniform float jitter;

// ONE WAVE TRAVELLING ALONG THE WIND, which is what reads as weather, plus a
// small per-thing offset so the world is many things rather than one sheet.
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
__BEND__

void vertex() {
	// UV2.x is how far up its own clump this row stands, 0 at the root and 1 at
	// the tip. UV2.y is the clump's own offset within the gust it is standing in.
	float up = UV2.x;
	vec3 at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// THE SQUARE: the root is pinned and the travel is in the top of the blade.
	VERTEX.xz += normalize(wind) * bend_at(at.xz, UV2.y) * reach * up * up;
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
	// A MODEL CARRIES NO TEXTURE: its colour is baked into vertex colour at build
	// time, so UV is free and UV.x is the sway weight `model.gd` wrote there,
	// zero through the trunk and rising through the crown.
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

var grass: ShaderMaterial = null
var foliage: ShaderMaterial = null


func _init() -> void:
	grass = _material(GRASS_CODE, GRASS_REACH)
	foliage = _material(FOLIAGE_CODE, FOLIAGE_REACH)


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


## Only the grass wears the atlas. A model's colour is baked into its vertices.
func set_atlas(texture: Texture2D) -> void:
	grass.set_shader_parameter("atlas", texture)
