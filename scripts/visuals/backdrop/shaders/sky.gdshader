// Céu noturno: gradiente frio (escuro em cima, mais claro no horizonte), ruído leve contra
// faixas de cor e poucas estrelas muito discretas que cintilam devagar.
shader_type canvas_item;
#include "res://scripts/visuals/backdrop/shaders/noise.gdshaderinc"

uniform vec2 rect_origin = vec2(0.0);        // posição do retângulo no espaço da arte
uniform vec2 rect_size = vec2(1672.0, 941.0);
uniform float t = 0.0;
uniform vec4 top_color : source_color = vec4(0.09, 0.12, 0.19, 1.0);
uniform vec4 mid_color : source_color = vec4(0.25, 0.31, 0.43, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.42, 0.49, 0.62, 1.0);
uniform float mid_y = 170.0;
uniform float horizon_y = 320.0;
uniform float star_amount = 0.35;            // 0 = sem estrelas
uniform vec2 moon_center = vec2(1228.0, 92.0);

void fragment() {
	vec2 px = rect_origin + UV * rect_size;
	float y = px.y;
	vec3 col = mix(top_color.rgb, mid_color.rgb, smoothstep(0.0, mid_y, y));
	col = mix(col, horizon_color.rgb, smoothstep(mid_y, horizon_y, y));
	// variação larga e suave (céu não chapado) + pontilhado contra faixas
	col *= 0.94 + 0.08 * bd_fbm(px / 420.0 + vec2(3.1, 7.7));
	col += (bd_hash(px) - 0.5) / 255.0;
	// estrelas: poucas, pequenas, só no alto e longe da lua
	vec2 cell = floor(px / 26.0);
	float h = bd_hash(cell + 13.7);
	if (h > 0.93) {
		vec2 sp = (cell + vec2(bd_hash(cell + 1.3), bd_hash(cell + 7.9))) * 26.0;
		float d = distance(px, sp);
		float tw = 0.55 + 0.45 * sin(t * (0.6 + h * 1.4) + h * 40.0);
		float fade = (1.0 - smoothstep(60.0, 230.0, y)) * smoothstep(150.0, 260.0, distance(px, moon_center));
		col += vec3(0.75, 0.82, 1.0) * (1.0 - smoothstep(0.0, 1.3, d)) * tw * fade * star_amount * (h - 0.93) * 14.0;
	}
	COLOR = vec4(col, 1.0);
}
