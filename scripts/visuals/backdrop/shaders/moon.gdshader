// Lua cheia branco-azulada: disco com mares suaves e escurecimento de borda, halo atmosférico
// e uma pulsação de luz quase imperceptível (ciclo de `pulse_period` s).
shader_type canvas_item;
#include "res://scripts/visuals/backdrop/shaders/noise.gdshaderinc"

uniform float t = 0.0;
uniform float radius_uv = 0.25;              // raio do disco em UV (o retângulo tem 4 raios de lado)
uniform vec4 disc_color : source_color = vec4(0.88, 0.92, 0.99, 1.0);
uniform vec4 mare_color : source_color = vec4(0.66, 0.73, 0.86, 1.0);
uniform vec4 halo_color : source_color = vec4(0.62, 0.72, 0.95, 1.0);
uniform float halo_strength = 0.55;
uniform float pulse_amount = 0.035;          // 0,035 = ±3,5% de brilho
uniform float pulse_period = 6.5;

void fragment() {
	vec2 c = UV - 0.5;
	float d = length(c) / radius_uv;         // 1 = borda do disco
	float pulse = 1.0 + pulse_amount * sin(6.2831 * t / pulse_period);
	// superfície
	vec2 q = c / radius_uv;
	float m = bd_fbm(q * 2.3 + vec2(4.2, 1.7));
	float mare = smoothstep(0.5, 0.64, m) * 0.75;
	float craters = smoothstep(0.62, 0.7, bd_fbm(q * 7.0 + 9.0)) * 0.25;
	vec3 surf = mix(disc_color.rgb, mare_color.rgb, clamp(mare + craters, 0.0, 1.0));
	surf *= mix(1.0, 0.86, pow(clamp(d, 0.0, 1.0), 5.0));      // borda um pouco mais escura
	surf *= pulse;
	float disc = 1.0 - smoothstep(0.985, 1.0, d);
	// halo: núcleo curto + véu largo, some antes da borda do retângulo
	float g = d > 1.0 ? exp(-(d - 1.0) * 3.0) * 0.55 + exp(-(d - 1.0) * 0.9) * 0.3 : 0.85;
	g *= (1.0 - smoothstep(1.6, 2.0, d)) * halo_strength * pulse;
	vec3 col = mix(halo_color.rgb, surf, disc);
	COLOR = vec4(col, max(disc, g));
}
