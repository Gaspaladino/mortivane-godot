// Céu: a própria arte, com as nuvens pintadas fluindo devagar (deslocamento suave só onde
// masks.r > 0, longe das montanhas e da lua) e a lua respirando de brilho.
shader_type canvas_item;

uniform sampler2D masks : filter_linear;
uniform vec2 art_size = vec2(1672.0, 941.0);
uniform float t = 0.0;                 // tempo (s), dado pelo ArenaBackdrop
uniform float flow_amp = 7.0;          // px da arte
uniform vec2 moon_center = vec2(1222.0, 70.0);
uniform float moon_radius = 72.0;
uniform float moon_pulse = 0.05;       // variação de brilho do disco

void fragment() {
	vec2 px = UV * art_size;
	float w = texture(masks, UV).r;
	vec2 d = vec2(
		sin(t * 0.11 + px.y * 0.021) * 0.7 + sin(t * 0.07 + px.y * 0.047 + px.x * 0.003) * 0.3,
		sin(t * 0.09 + px.x * 0.012) * 0.2) * flow_amp * w;
	vec4 c = texture(TEXTURE, UV - d / art_size);
	float moon = 1.0 - smoothstep(moon_radius - 3.0, moon_radius + 2.0, distance(px, moon_center));
	c.rgb *= 1.0 + moon * moon_pulse * (0.5 + 0.5 * sin(t * 0.55));
	COLOR = c;
}
