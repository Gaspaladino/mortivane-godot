// Chamas e reflexos das velas: brilho somado que oscila como chama viva.
shader_type canvas_item;
render_mode blend_add;
#include "res://scripts/visuals/backdrop/shaders/noise.gdshaderinc"

uniform float t = 0.0;
uniform float strength = 0.7;
uniform float seed = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float a = bd_noise(vec2(t * 7.0 + seed, UV.x * 6.0));
	float b = bd_noise(vec2(t * 13.0 + seed * 2.0, UV.y * 3.0 + 5.0));
	float f = strength * (0.15 + 0.85 * a * mix(0.6, 1.0, b));
	COLOR = vec4(c.rgb, c.a * f);
}
