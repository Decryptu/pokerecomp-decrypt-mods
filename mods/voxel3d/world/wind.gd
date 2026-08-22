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
## AND THE PLAYER PARTS IT. The half of this a player feels rather than sees:
## walking into a meadow that does not answer is walking into scenery. The
## reference does it in the same vertex shader off one more uniform
## (`lib/Voxel3D.lua`, `grassPlayer`) and this is that mechanism, with one
## deliberate difference. It pushes a clump sideways as a whole; here the push is
## RADIAL, away from whoever is standing there, and weighted by the same square
## the wind uses, so the blades part around them and stay rooted where they grew.
## Sliding a whole clump aside is the fault the square was introduced to fix and
## it is no less a fault for having a player behind it instead of a breeze.
##
## Only the overworld sets it. A battle stages a fight on the map and has nobody
## walking about, so `walker` keeps its zero reach there and the shader's own
## multiply switches the whole term off.

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

## How far from someone the grass feels them, in world pixels, and how far a
## blade's tip is pushed out of their way. A walk cell is 16, so this parts about
## a cell of grass around a player who is themselves about a cell wide.
##
## The push is larger than the wind's own lean and it should be: a breeze is
## weather and a body is a body. It is still short of the blade's full 8 px, so
## the grass leans out of the way rather than lying down flat around a hole.
const WALKER_RADIUS: float = 14.0
const WALKER_REACH: float = 2.6

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
// Where the player is standing, in world pixels, then how far the grass feels
// them and how far it is pushed. A zero reach is nobody there.
uniform vec4 walker;
__BEND__

void vertex() {
	// UV2.x is how far up its own clump this row stands, 0 at the root and 1 at
	// the tip. UV2.y is the clump's own offset within the gust it is standing in.
	float up = UV2.x;
	vec3 at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// THE SQUARE: the root is pinned and the travel is in the top of the blade.
	float lean = up * up;
	VERTEX.xz += normalize(wind) * bend_at(at.xz, UV2.y) * reach * lean;
	// AND WHOEVER IS STANDING IN IT parts it, radially and by the same square.
	// The falloff holds full strength close in and eases out to nothing at the
	// radius, so a step does not snap the meadow.
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

## THE CARTRIDGE'S OWN DRAWING STOOD UP, for a model too far away to turn.
##
## Same bend as `FOLIAGE_CODE` and the same instance phase, so a stamp that
## crosses the detail ring keeps swaying exactly as it was. What differs is
## where the colour comes from: a solid bakes it into its vertices, and this
## reads the tileset pixels themselves, cut out of the drawing with everything
## that is not the thing left transparent.
##
## `cull_disabled` is what makes it four triangles a tree rather than eight: a
## plane has two sides and this way one quad serves both. `discard` on the alpha
## rather than a blend, so the pair of crossed planes needs no sorting and
## writes depth like everything else on this stage.
const SPRITE_CODE: String = """
shader_type spatial;
render_mode specular_disabled, diffuse_lambert, cull_disabled;

uniform sampler2D cutout : source_color, filter_nearest;
uniform float reach;
__BEND__

void vertex() {
	// UV carries the drawing here, so the sway weight moves to UV2.x. Same
	// meaning: zero at the foot, one at the top of the crown.
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
## One material per cut-out drawing, since each wears its own picture. There are
## tens of distinct drawings on a map, not hundreds, and a material is not a
## draw: the instances under one still batch as one.
var _sprites: Dictionary = {}


func _init() -> void:
	grass = _material(GRASS_CODE, GRASS_REACH)
	foliage = _material(FOLIAGE_CODE, FOLIAGE_REACH)
	# Nobody is standing anywhere until a view says so, and a zero reach is what
	# says it: a battle never calls `set_walker` at all.
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


## Where the one person walking through the grass is, in world pixels. Only the
## grass is parted: a tree does not notice being walked past.
func set_walker(at: Vector3) -> void:
	grass.set_shader_parameter(
		"walker", Vector4(at.x, at.z, WALKER_RADIUS, WALKER_REACH)
	)
