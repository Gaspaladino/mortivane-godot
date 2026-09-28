// Estandarte pesado ao vento. O vento chega pela haste e PROPAGA tecido abaixo: cada altura
// repete o movimento de cima com atraso (fase cai com v), então a barra acompanha a haste
// como um pano, não como uma placa rígida. Rajadas lentas (ruído de baixa frequência)
// variam a força; uma ondulação menor corre até a ponta; a barra sobe um pouco quando
// o pano se afasta (comprimento constante). A parte presa não se move.
shader_type canvas_item;

uniform vec2 tex_size = vec2(72.0, 200.0);
uniform float t = 0.0;
uniform float top_px = 8.0;          // onde o tecido encontra a haste
uniform float amp = 2.4;             // px na ponta
uniform float phase = 0.0;

float gust(float x) {                // 0..1, suave: soma de senos lentos incomensuráveis
	return 0.5 + 0.3 * sin(x * 0.23 + 1.3) + 0.2 * sin(x * 0.61 + 4.1);
}

void fragment() {
	vec2 px = UV * tex_size;
	float v = clamp((px.y - top_px) / (tex_size.y - top_px), 0.0, 1.0);
	float lag = v * 1.25;                                              // atraso ao descer
	float tt = t + phase;
	float g = mix(0.55, 1.0, gust(tt - lag));
	float sway = sin(tt * 0.9 - lag) * 0.75 + sin(tt * 0.47 - lag * 0.6 + 2.0) * 0.25;
	float ripple = sin(tt * 2.1 - v * 6.0) * 0.18 * smoothstep(0.25, 1.0, v);
	float dx = amp * g * (sway * pow(v, 1.35) + ripple * v);
	float dy = -abs(dx) * 0.12 * v;                                   // pano se afasta → barra sobe
	vec4 c = texture(TEXTURE, (px - vec2(dx, dy)) / tex_size);
	// dobras: lado que vira para o vento clareia, o outro escurece (bem de leve)
	float fold = cos(tt * 0.9 - lag) * pow(v, 1.35) + cos(tt * 2.1 - v * 6.0) * 0.3 * v;
	c.rgb *= 1.0 - 0.07 * fold * sign(amp);
	COLOR = c;
}
