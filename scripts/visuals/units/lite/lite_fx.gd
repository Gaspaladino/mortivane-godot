class_name LiteFx
extends RefCounted
## Clarão de dano, escurecimento da morte e esmaecer (alfa) das peças prontas, por shader — sem
## refazer as cores dos vértices na CPU. Mesma conta do CodeDrawnUnitVisual._c():
##   cor = mix(cor, flash_color, flash); cor = mix(cor, ESCURO, dim); alfa *= alpha.
## O clarão só vale para as peças com UV.x = 1 (o corpo); sombra no chão, névoa e aura não piscam.
## Os materiais são COMPARTILHADOS entre unidades: valores arredondados em degraus pequenos
## (imperceptíveis), um material por combinação. Sem efeito = sem material (null).

const DIM_COLOR := Color(0.08, 0.07, 0.1)
const STEPS := 24.0
const MAX_MATERIALS := 2048

const SHADER_CODE := """
shader_type canvas_item;
uniform vec4 flash_color = vec4(1.0);
uniform float flash = 0.0;
uniform float dim = 0.0;
uniform float alpha = 1.0;
void fragment() {
	vec4 c = COLOR;
	c.rgb = mix(c.rgb, flash_color.rgb, flash * UV.x);   // UV.x = 0: peça que não pisca (chão, névoa)
	c.rgb = mix(c.rgb, vec3(0.08, 0.07, 0.1), dim);
	c.a *= alpha;
	COLOR = c;
}
"""

static var _shader: Shader
static var _materials := {}


## Material para os valores dados (null = sem efeito). `flash`, `dim` e `alpha` em 0..1.
static func material(flash_color: Color, flash: float, dim: float, alpha := 1.0) -> ShaderMaterial:
	var f := roundf(clampf(flash, 0.0, 1.0) * STEPS)
	var d := roundf(clampf(dim, 0.0, 1.0) * STEPS)
	var a := roundf(clampf(alpha, 0.0, 1.0) * STEPS)
	if f == 0.0 and d == 0.0 and a == STEPS:
		return null
	var key := "%s|%d|%d|%d" % [flash_color.to_html(), f, d, a]
	var m: ShaderMaterial = _materials.get(key)
	if m:
		return m
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	if _materials.size() >= MAX_MATERIALS:
		_materials.clear()
	m = ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter(&"flash_color", flash_color)
	m.set_shader_parameter(&"flash", f / STEPS)
	m.set_shader_parameter(&"dim", d / STEPS)
	m.set_shader_parameter(&"alpha", a / STEPS)
	_materials[key] = m
	return m


static func material_count() -> int:
	return _materials.size()
