// Neblina fria e lenta no vale, entre as montanhas e o muro de ruínas (masks.g).
shader_type canvas_item;
#include "res://scripts/visuals/backdrop/shaders/noise.gdshaderinc"

uniform sampler2D masks : filter_linear;
uniform vec2 art_size = vec2(1672.0, 941.0);
uniform float t = 0.0;
uniform float speed = 3.0;
uniform float cell = 320.0;
uniform float stretch = 4.0;
uniform float coverage = 0.42;
uniform float softness = 0.3;
uniform float opacity = 0.25;
uniform float band_top = 150.0;
uniform float band_bottom = 350.0;
uniform float seed = 0.0;
uniform vec4 fog_color : source_color = vec4(0.68, 0.74, 0.88, 1.0);

void fragment() {
	vec2 px = UV * art_size;
	vec2 p = (px - vec2(t * speed, 0.0)) / cell;
	p.x /= stretch;
	p += vec2(seed, seed * 0.53);
	float n = bd_fbm(p + vec2(bd_fbm(p * 0.7 + t * 0.012), 0.0) * 0.6);
	float c = smoothstep(coverage, coverage + softness, n);
	// mais densa embaixo do vale, rala no alto das encostas
	float band = smoothstep(band_top, band_top + 70.0, px.y) * (1.0 - smoothstep(band_bottom - 20.0, band_bottom, px.y));
	band *= mix(0.45, 1.0, smoothstep(band_top, band_bottom, px.y));
	COLOR = vec4(fog_color.rgb, c * band * texture(masks, UV).g * opacity);
}
