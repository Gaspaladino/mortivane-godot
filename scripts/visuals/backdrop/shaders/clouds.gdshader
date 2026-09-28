// Nuvens estilizadas (ilustração 2D): bancos longos com topo em "escamas" arredondadas e base
// quase reta, contorno definido e 3 tons — corpo, borda de cima iluminada, barriga escura.
// Os bancos vivem numa grade que desliza devagar da esquerda para a direita (nada salta:
// a grade é contínua e cada banco só entra/sai pelas bordas do céu).
// Perto da lua, a borda de cima fica prateada.
shader_type canvas_item;
#include "res://scripts/visuals/backdrop/shaders/noise.gdshaderinc"

uniform vec2 rect_origin = vec2(0.0);
uniform vec2 rect_size = vec2(1672.0, 400.0);
uniform float t = 0.0;
uniform float speed = 3.0;                   // px da arte por segundo (+ = para a direita)
uniform float cell_w = 420.0;                // largura de uma célula da grade (px)
uniform float density = 0.7;                 // chance de uma célula ter nuvem
uniform float length_min = 0.45;             // comprimento do banco (em células)
uniform float length_max = 0.95;
uniform float height = 26.0;                 // altura típica do banco (px)
uniform vec3 rows = vec3(60.0, 120.0, 190.0); // alturas (y) das fileiras; −1 = fileira desligada
uniform float row_jitter = 22.0;
uniform float opacity = 0.6;
uniform float seed = 0.0;
uniform float rim_px = 4.0;                  // espessura da borda iluminada (px)
uniform vec4 body_color : source_color = vec4(0.18, 0.22, 0.32, 1.0);
uniform vec4 top_color : source_color = vec4(0.4, 0.47, 0.61, 1.0);
uniform vec4 belly_color : source_color = vec4(0.12, 0.15, 0.23, 1.0);
uniform vec4 rim_color : source_color = vec4(0.82, 0.88, 1.0, 1.0);
uniform vec2 moon_center = vec2(1228.0, 92.0);
uniform float moon_radius = 66.0;
uniform float moon_light = 1.0;

// Distância assinada (px, + = dentro) até o banco da célula (i, fileira r); também devolve
// a distância até o topo e até a base.
vec3 bank(vec2 q, float i, float r, float row_y) {
	vec2 id = vec2(i, r) + seed;
	if (bd_hash(id) > density) {
		return vec3(-1e3);
	}
	float len = cell_w * mix(length_min, length_max, bd_hash(id + 3.1));
	float cx = (i + 0.5 + (bd_hash(id + 1.7) - 0.5) * 0.5) * cell_w;
	float cy = row_y + (bd_hash(id + 5.3) - 0.5) * 2.0 * row_jitter;
	float h = height * mix(0.65, 1.35, bd_hash(id + 7.9));
	float u = (q.x - cx) / (len * 0.5);
	if (abs(u) >= 1.0) {
		return vec3(-1e3);
	}
	float env = pow(1.0 - u * u, 1.15);                       // pontas longas e finas
	// escamas: arcos de largura variável ao longo do topo
	float w = h * mix(0.9, 1.5, bd_hash(id + 9.1));
	float k = fract((q.x - cx) / w + bd_hash(id + 2.2));
	float arch = sqrt(max(0.0, 1.0 - (2.0 * k - 1.0) * (2.0 * k - 1.0)));
	float wobble = (bd_noise(vec2(q.x / 23.0, id.x * 3.0 + id.y)) - 0.5) * 0.35;
	float lump = bd_noise(vec2(q.x / (w * 2.7), id.x + id.y * 5.0));  // partes mais cheias
	float top = cy - h * env * (0.45 + 0.5 * lump + 0.16 * arch + wobble);
	float bottom = cy + h * 0.2 * pow(env, 0.6) + (bd_noise(vec2(q.x / 31.0, id.y + 9.0)) - 0.5) * h * 0.12 * env;
	return vec3(min(q.y - top, bottom - q.y), q.y - top, bottom - q.y);
}

vec3 clouds(vec2 px) {
	vec2 q = vec2(px.x - t * speed, px.y);
	float ci = floor(q.x / cell_w);
	vec3 best = vec3(-1e3);
	for (int r = 0; r < 3; r++) {
		float row_y = rows[r];
		if (row_y < 0.0) {
			continue;
		}
		for (int di = -1; di <= 1; di++) {   // um banco ocupa no máximo [i − 0,5, i + 1,5] células
			vec3 b = bank(q, ci + float(di), float(r), row_y);
			if (b.x > best.x) {
				best = b;
			}
		}
	}
	return best;
}

void fragment() {
	vec2 px = rect_origin + UV * rect_size;
	vec3 d = clamp(clouds(px), vec3(-8.0), vec3(1e3));
	float aa = clamp(fwidth(d.x), 0.5, 1.5);
	float c = smoothstep(-aa, aa, d.x);
	if (c <= 0.0) {
		discard;
	}
	float lit = 1.0 - smoothstep(rim_px * 0.5, rim_px * 1.5, d.y);
	float dark = 1.0 - smoothstep(rim_px, rim_px * 2.5, d.z);
	vec3 col = body_color.rgb;
	col = mix(col, belly_color.rgb, dark * 0.85);
	col = mix(col, top_color.rgb, lit);
	float dm = distance(px, moon_center);
	float near_moon = (1.0 - smoothstep(moon_radius * 0.9, moon_radius * 3.4, dm)) * moon_light;
	col = mix(col, rim_color.rgb, lit * near_moon);
	col = mix(col, top_color.rgb, near_moon * 0.25 * (1.0 - lit));
	COLOR = vec4(col, c * opacity);
}
