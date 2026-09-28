// Ruído de valor + fbm, usado pelas nuvens, neblina e brilhos do fundo da arena.
float bd_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float bd_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(bd_hash(i), bd_hash(i + vec2(1.0, 0.0)), u.x),
		mix(bd_hash(i + vec2(0.0, 1.0)), bd_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float bd_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 m = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));
	for (int i = 0; i < 5; i++) {
		v += a * bd_noise(p);
		p = m * p;
		a *= 0.5;
	}
	return v;
}
