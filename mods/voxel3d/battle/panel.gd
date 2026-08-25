extends RefCounted

## The frost behind a panel, which is the second pass over the finished picture.
##
## The cartridge draws its HUD as black glyphs straight onto the white field, with
## no box: the field is the backing. This view puts a route under it, so each
## block gets a light backing of its own, light because an opaque slab is the
## white field again under another name. See `renderer.gd:PANEL_TINT`.
##
## A flat tint is not enough, and the reference says why (`lib/BattleHud.lua`): a
## translucent rectangle over a dithered path shows every texel through the
## writing, so the two compete. Blurring what is behind separates them without
## making the backing more solid.
##
## It is the backing's own material, sampling the screen behind it. That works
## because the backing is drawn after the stage container and before every HUD
## layer, so it reads the composited world with the hour's tint already on it.
##
## A real blur is a mip chain and there is none here: the host renders on
## `gl_compatibility`, where the screen texture is a plain copy. So it is twelve
## taps on two rings, cheap over an eighth of the frame and enough to dissolve an
## 8 px dither.
##
## The tint is the node's own colour rather than a uniform, so `PANEL_TINT` stays
## the one place that says how solid a panel is.

## How far the taps reach, in hardware pixels, scaled by the factor the panels
## are drawn at, so the frost is the same strength at every window size.
const BLUR_RADIUS: float = 2.5

const CODE: String = """
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float radius = 5.0;

const vec2 RING[6] = {
	vec2(1.0, 0.0), vec2(0.5, 0.866), vec2(-0.5, 0.866),
	vec2(-1.0, 0.0), vec2(-0.5, -0.866), vec2(0.5, -0.866)
};

void fragment() {
	vec2 step = SCREEN_PIXEL_SIZE * radius;
	vec3 sum = texture(screen, SCREEN_UV).rgb;
	for (int i = 0; i < 6; i++) {
		sum += texture(screen, SCREEN_UV + RING[i] * step).rgb;
		sum += texture(screen, SCREEN_UV + RING[i] * step * 2.0).rgb;
	}
	COLOR = vec4(mix(sum / 13.0, COLOR.rgb, COLOR.a), 1.0);
}
"""

var material: ShaderMaterial = null


func _init() -> void:
	var shader := Shader.new()
	shader.code = CODE
	material = ShaderMaterial.new()
	material.shader = shader
	set_scale(1)


## The whole-number factor the hardware screen is drawn at.
func set_scale(factor: int) -> void:
	material.set_shader_parameter("radius", BLUR_RADIUS * float(maxi(factor, 1)))
