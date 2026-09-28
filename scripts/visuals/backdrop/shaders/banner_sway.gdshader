// Estandarte pesado ao vento: um balanço pendular lento a partir da haste, mais uma onda
// pequena que chega à ponta rasgada. A parte presa quase não se move.
shader_type canvas_item;

uniform vec2 tex_size = vec2(72.0, 200.0);
uniform float t = 0.0;
uniform float top_px = 8.0;          // onde o tecido encontra a haste
uniform float amp = 2.4;             // px na ponta
uniform float phase = 0.0;

void fragment() {
	vec2 px = UV * tex_size;
	float v = clamp((px.y - top_px) / (tex_size.y - top_px), 0.0, 1.0);
	float swing = sin(t * 0.85 + phase) * 0.7 + sin(t * 0.37 + phase * 1.7) * 0.3;   // pendular
	float wave = sin(t * 1.6 + phase - v * 4.4);                                   // onda que desce
	float dx = amp * (swing * v * 0.75 + wave * pow(v, 2.0) * 0.35);
	vec4 c = texture(TEXTURE, (px - vec2(dx, 0.0)) / tex_size);
	c.rgb *= 1.0 - 0.06 * pow(v, 1.5) * cos(t * 1.6 + phase - v * 4.4) * sign(amp);
	COLOR = c;
}
