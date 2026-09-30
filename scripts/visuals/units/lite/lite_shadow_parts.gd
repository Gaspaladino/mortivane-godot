class_name LiteShadowParts
extends RefCounted
## Efeitos da "sombra necromântica" no desenho leve (mesmas formas do ShadowFX):
##   eye() / crack() — entram na PEÇA pronta (chamados durante a montagem, via utilitários do visual).
## A fumaça, a névoa e a aura são peças com ossos em cada visual de sombra (o esmaecer vira encolher).


## Olho brilhando (halo + ponto claro), na peça que está sendo montada.
static func eye(v: CodeDrawnUnitVisual, pos: Vector2, radius: float, style: ShadowStyle) -> void:
	v._disc(pos, radius * 2.4, Color(style.energy, 0.22))
	v._disc(pos, radius * 1.3, Color(style.energy, 0.55))
	v._disc(pos, radius * 0.7, Color(style.eye, 0.95))


## Fissura de energia (linha larga translúcida + núcleo claro), na peça que está sendo montada.
static func crack(v: CodeDrawnUnitVisual, pts: PackedVector2Array, style: ShadowStyle, k := 1.0, pulse := 0.5) -> void:
	var a := clampf(style.cracks * k, 0.0, 1.5)
	if a <= 0.0 or pts.size() < 2:
		return
	v._pline(pts, Color(style.energy, 0.28 * a * (0.7 + 0.3 * pulse)), 1.7)
	v._pline(pts, Color(style.energy.lerp(style.energy_core, 0.35 + 0.3 * pulse), 0.95 * minf(a, 1.0)), 0.55)
