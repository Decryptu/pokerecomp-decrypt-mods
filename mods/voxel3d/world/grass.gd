extends RefCounted

## The grass, bending. The first thing on LAND in this diorama that moves.
##
## A still world is what most gives a diorama away as geometry rather than as a
## place, and the reference says so with the cheapest possible motion: one
## attribute per clump and a sway in the vertex shader, the root pinned and the
## tip bending by the SQUARE of its height (`lib/Voxel3D.lua`, the grass shader).
## Nothing is simulated and nothing is stored between frames.
##
## WHY THE SQUARE. A blade bending linearly slides sideways, which reads as the
## whole clump sliding off its own roots. Squaring it holds the bottom still and
## puts nearly all of the travel in the top third, which is what a stalk hinged
## at the ground actually does.
##
## WHY A GUST RATHER THAN A PHASE PER CLUMP. Both were built and photographed.
## One wave over the whole field moves it as a single sheet, which is worse than
## not moving it, because a sheet is obviously one object where a field is
## obviously many. But a phase hashed per clump and left at that is worse again:
## neighbours lean opposite ways at the same instant and the meadow reads as
## static noise rather than as weather.
##
## What reads as wind is a wave TRAVELLING along the wind's own direction, with
## the per-clump hash as a small offset on top rather than as the whole phase. So
## a gust visibly crosses the field, and inside it every clump is a little ahead
## of or behind its neighbour. `mesher.gd:_tufts` hashes the TILE position, not
## the cell, so even the two rows of one walk cell differ, which is the same
## separation the cartridge's own overdraw implies when the player walks between
## them.
##
## WHAT IT DOES NOT DO, and the reference does: push the tufts aside as the
## player walks through them, swept between last frame's position and this one.
## That needs the player's position per frame and this material has no idea where
## anyone is. It is open work, and it is the half of this that a player actually
## feels rather than sees.

## How far the tip travels, in world pixels. A walk cell is 16 and a blade is 8,
## so this is a lean rather than a flattening: grass that lies down in a breeze
## reads as wind damage.
const SWAY_REACH: float = 1.6
## How long one bend takes, in seconds, and how long the gust crossing the field
## is, in world pixels. Sixteen cells is about what the default shot frames, so a
## gust of about that is one wave in the frame at a time rather than a ripple.
const SWAY_PERIOD: float = 2.9
const GUST_LENGTH: float = 260.0
## How far a clump may run ahead of or behind the gust it is in, as a fraction of
## one cycle. Small: at 1.0 this is the random phase that reads as noise, and at
## 0 the field is a sheet.
const CLUMP_JITTER: float = 0.22
## Which way the wind blows, as a direction in the world's own plane. East and a
## little south, which is across the default shot rather than into it: a sway
## aimed at the eye is a sway nobody can see.
const WIND: Vector2 = Vector2(0.92, 0.39)

const CODE: String = """
shader_type spatial;
render_mode specular_disabled, diffuse_lambert;

uniform sampler2D atlas : source_color, filter_nearest;
uniform vec2 wind;
uniform float reach;
uniform float period;
uniform float gust_length;
uniform float jitter;

void vertex() {
	// UV2.x is how far up its own clump this row stands, 0 at the root and 1 at
	// the tip. UV2.y is the clump's own offset within the gust it is standing in.
	float up = UV2.x;
	float phase = UV2.y;
	vec2 along = normalize(wind);
	vec3 at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// ONE WAVE TRAVELLING ALONG THE WIND, which is what reads as weather, plus a
	// small per-clump offset so the field is many things rather than one sheet.
	float bend = sin((
		TIME / period - dot(at.xz, along) / gust_length + phase * jitter
	) * 6.2831853);
	// THE SQUARE is the whole of it: the root is pinned and the travel is in the
	// top of the blade.
	VERTEX.xz += along * bend * reach * up * up;
}

void fragment() {
	vec4 texel = texture(atlas, UV);
	ALBEDO = texel.rgb * COLOR.rgb;
}
"""

var material: ShaderMaterial = null


func _init() -> void:
	var shader := Shader.new()
	shader.code = CODE
	material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("wind", WIND)
	material.set_shader_parameter("reach", SWAY_REACH)
	material.set_shader_parameter("period", SWAY_PERIOD)
	material.set_shader_parameter("gust_length", GUST_LENGTH)
	material.set_shader_parameter("jitter", CLUMP_JITTER)


func set_atlas(texture: Texture2D) -> void:
	material.set_shader_parameter("atlas", texture)
