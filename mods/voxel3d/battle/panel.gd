extends RefCounted

## THE FROST BEHIND A PANEL, which is the second pass over the finished picture.
##
## The cartridge draws its HUD as black glyphs straight onto the white field,
## with no box: the field IS the backing. This view takes the field away and puts
## a route under it, so each block gets a backing of its own, and it is
## deliberately a light one, because an opaque slab in the corner of the frame is
## the white field back again under another name. See `renderer.gd:PANEL_TINT`.
##
## A FLAT TINT IS NOT ENOUGH and the reference says why (`lib/BattleHud.lua`): a
## translucent rectangle over a dithered path shows every texel of that path
## through the writing, so the panel reads as dirt and the glyphs have to be
## picked out of it. Blurring what is behind it separates the two without making
## the backing any more solid than it was: the world is still visible, still the
## right colour and still moving, and it has stopped competing with the text.
##
## WHERE IT GOES is the backing's own material, which samples the SCREEN behind
## it. That works because the backing is drawn after the stage container and
## before every HUD layer, so what it reads is the composited world with the
## hour's tint already on it, and what it writes is under the glyphs.
##
## A REAL BLUR IS A MIP CHAIN and there is none to read here: the host renders on
## `gl_compatibility`, where the screen texture is a plain copy. So it is taps,
## twelve of them on two rings, which is cheap over two rectangles that cover an
## eighth of the frame and enough to dissolve an 8 px dither.
##
## THE TINT IS THE NODE'S OWN COLOUR rather than a uniform, so PANEL_TINT stays
## the one place that says how solid a panel is: a `ColorRect`'s colour arrives
## in the shader as COLOR, its alpha is how far to mix toward it, and the pass
## writes an opaque pixel either way.

## How far the taps reach, in HARDWARE pixels. Scaled by whatever whole-number
## factor the panels are drawn at, so the frost is the same strength at every
## window size rather than sharpening as the window grows.
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
