// Chamas e reflexos das velas: brilho somado com flicker sutil — pequena variação de
// intensidade (±12%), lenta, sem piscar.
shader_type canvas_item;
render_mode blend_add;
#include "res://scripts/visuals/backdrop/shaders/noise.gdshaderinc"

uniform float t = 0.0;
uniform float strength = 0.35;
uniform float seed = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float a = bd_noise(vec2(t * 1.2 + seed, UV.x * 3.0));
	float b = bd_noise(vec2(t * 2.3 + seed * 2.0, UV.y * 2.0 + 5.0));
	COLOR = vec4(c.rgb, c.a * strength * (0.8 + 0.16 * a + 0.08 * b));
}
