// Chamas e reflexos das velas: brilho somado que respira devagar, como chama calma.
shader_type canvas_item;
render_mode blend_add;
#include "res://scripts/visuals/backdrop/shaders/noise.gdshaderinc"

uniform float t = 0.0;
uniform float strength = 0.35;
uniform float seed = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float a = bd_noise(vec2(t * 1.9 + seed, UV.x * 3.0));
	float b = bd_noise(vec2(t * 3.1 + seed * 2.0, UV.y * 2.0 + 5.0));
	COLOR = vec4(c.rgb, c.a * strength * (0.45 + 0.4 * a + 0.15 * b));
}
