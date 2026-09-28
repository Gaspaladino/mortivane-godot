// Neblina translúcida em faixa horizontal: véu constante (haze) + massas suaves que deslizam.
shader_type canvas_item;
#include "res://scripts/visuals/backdrop/shaders/noise.gdshaderinc"

uniform vec2 rect_origin = vec2(0.0, 150.0);
uniform vec2 rect_size = vec2(1672.0, 220.0);
uniform float t = 0.0;
uniform float speed = 2.0;                   // + = para a direita, − = para a esquerda
uniform float cell = 300.0;
uniform float stretch = 4.0;
uniform float coverage = 0.42;
uniform float softness = 0.32;
uniform float haze = 0.25;                   // parte constante do véu
uniform float opacity = 0.3;
uniform float band_top = 150.0;
uniform float band_peak = 300.0;             // onde é mais densa
uniform float band_bottom = 360.0;
uniform float seed = 0.0;
uniform vec4 fog_color : source_color = vec4(0.52, 0.59, 0.73, 1.0);

void fragment() {
	vec2 px = rect_origin + UV * rect_size;
	vec2 p = (px - vec2(t * speed, 0.0)) / cell;
	p.x /= stretch;
	p += vec2(seed, seed * 0.53);
	float n = bd_fbm(p + vec2(bd_fbm(p * 0.6 + t * 0.006), 0.0) * 0.6);
	float c = smoothstep(coverage, coverage + softness, n);
	float band = smoothstep(band_top, band_peak, px.y) * (1.0 - smoothstep(band_peak, band_bottom, px.y));
	COLOR = vec4(fog_color.rgb, (haze + (1.0 - haze) * c) * band * opacity);
}
