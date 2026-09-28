// Estandarte ao vento: preso na haste (topo), a onda cresce para a ponta rasgada.
// Desloca a amostragem na horizontal e sombreia as dobras de leve.
shader_type canvas_item;

uniform vec2 tex_size = vec2(72.0, 200.0);
uniform float t = 0.0;
uniform float top_px = 8.0;           // onde o tecido encontra a haste
uniform float amp = 2.6;              // px na ponta
uniform float waves = 1.1;            // ondas ao longo do comprimento
uniform float phase = 0.0;

void fragment() {
	vec2 px = UV * tex_size;
	float v = clamp((px.y - top_px) / (tex_size.y - top_px), 0.0, 1.0);
	float k = pow(v, 1.6);
	float gust = 0.72 + 0.28 * sin(t * 0.23 + phase);
	float w = t + phase - v * waves * 6.2831;
	float dx = amp * gust * k * (sin(w) + 0.3 * sin(w * 2.3 + 1.7));
	vec4 c = texture(TEXTURE, (px - vec2(dx, 0.0)) / tex_size);
	c.rgb *= 1.0 - 0.08 * k * gust * cos(w) * sign(amp);
	COLOR = c;
}
