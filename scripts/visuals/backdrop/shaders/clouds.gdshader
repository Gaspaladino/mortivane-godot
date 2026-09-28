// Nuvens procedurais que atravessam o céu devagar (parallax: cada camada com escala/velocidade).
// Recortadas pelo céu (masks.a), então passam ATRÁS das montanhas e castelos.
shader_type canvas_item;
#include "res://scripts/visuals/backdrop/shaders/noise.gdshaderinc"

uniform sampler2D masks : filter_linear;
uniform vec2 art_size = vec2(1672.0, 941.0);
uniform float t = 0.0;
uniform float speed = 4.0;              // px da arte por segundo (para a direita)
uniform float cell = 260.0;             // tamanho típico de uma nuvem (px)
uniform float stretch = 2.4;            // alongamento horizontal
uniform float coverage = 0.56;          // maior = menos nuvem
uniform float softness = 0.12;
uniform float opacity = 0.3;
uniform float band_top = 0.0;
uniform float band_bottom = 260.0;
uniform float seed = 0.0;
uniform vec4 shadow_color : source_color = vec4(0.16, 0.2, 0.31, 1.0);
uniform vec4 light_color : source_color = vec4(0.5, 0.58, 0.76, 1.0);
uniform vec2 moon_center = vec2(1222.0, 70.0);
uniform float moon_radius = 72.0;

void fragment() {
	vec2 px = UV * art_size;
	vec2 p = (px - vec2(t * speed, 0.0)) / cell;
	p.x /= stretch;
	p += vec2(seed, seed * 0.37);
	vec2 warp = vec2(bd_fbm(p * 0.6 + t * 0.01), bd_fbm(p * 0.6 + 7.3 - t * 0.008));
	float n = bd_fbm(p + warp * 0.8);
	float c = smoothstep(coverage, coverage + softness, n);
	float up = bd_fbm(p + warp * 0.8 - vec2(0.0, 0.09));
	float shade = clamp(0.5 + (n - up) * 6.0, 0.0, 1.0);          // borda de cima mais clara
	float lit = 1.0 - smoothstep(moon_radius * 0.6, moon_radius * 3.2, distance(px, moon_center));
	vec3 col = mix(shadow_color.rgb, light_color.rgb, shade);
	col = mix(col, vec3(0.86, 0.9, 1.0), lit * 0.5 * shade);      // lua ilumina quem passa perto
	float band = smoothstep(band_top, band_top + 50.0, px.y) * (1.0 - smoothstep(band_bottom - 80.0, band_bottom, px.y));
	COLOR = vec4(col, c * band * texture(masks, UV).a * opacity);
}
