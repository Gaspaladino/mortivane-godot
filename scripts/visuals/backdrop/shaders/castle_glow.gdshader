// Luzes roxas do castelo: pulsam e tremulam de leve (soma, por cima do cenário).
shader_type canvas_item;
render_mode blend_add;
#include "res://scripts/visuals/backdrop/shaders/noise.gdshaderinc"

uniform sampler2D masks : filter_linear;
uniform vec2 art_size = vec2(1672.0, 941.0);
uniform float t = 0.0;
uniform float strength = 0.45;
uniform vec4 glow_color : source_color = vec4(0.62, 0.36, 1.0, 1.0);

void fragment() {
	vec2 px = UV * art_size;
	float m = texture(masks, UV).b;
	float n = bd_noise(px * 0.045 + vec2(t * 0.9, t * 0.35));
	float slow = 0.5 + 0.5 * sin(t * 0.8 + px.x * 0.02);
	float flick = mix(0.25, 1.0, n) * mix(0.65, 1.0, slow);
	COLOR = vec4(glow_color.rgb, m * strength * flick);
}
