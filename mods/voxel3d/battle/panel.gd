extends RefCounted

## The frost behind a panel, which is the second pass over the finished
## picture.

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


func set_scale(factor: int) -> void:
	material.set_shader_parameter("radius", BLUR_RADIUS * float(maxi(factor, 1)))
