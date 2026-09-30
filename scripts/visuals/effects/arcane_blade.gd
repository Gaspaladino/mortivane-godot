class_name ArcaneBlade
extends RefCounted
## Desenho da lâmina arcana da Sentinela, usado tanto PAIRANDO (SentinelVisual) quanto em
## VOO (ProjectileView): é a mesma lâmina que parte. Forma portada de drawSwordBlade do HTML.
## A lâmina aponta para +x no seu espaço local; `length` é o comprimento total.

## Contorno da lâmina em unidades de comprimento (ponta em +0,95; guarda em -0,32..-0,44).
const SHAPE := [
	Vector2(0.95, 0.0), Vector2(0.2, 0.18), Vector2(-0.22, 0.1), Vector2(-0.32, 0.34),
	Vector2(-0.44, 0.19), Vector2(-0.33, 0.0), Vector2(-0.44, -0.19), Vector2(-0.32, -0.34),
	Vector2(-0.22, -0.1), Vector2(0.2, -0.18),
]


## `style`: {dark, glow, core, trim, shadow}. `energy` 0..1 intensifica o brilho (antecipação).
static func draw(ci: CanvasItem, xf: Transform2D, length: float, style: Dictionary, alpha: float, time: float, energy := 0.0) -> void:
	if alpha <= 0.0:
		return
	ci.draw_set_transform_matrix(xf)
	var pts := PackedVector2Array()
	for v in SHAPE:
		pts.append(v * length)
	var closed := pts.duplicate()
	closed.append(pts[0])
	var glow: Color = style.glow
	var shadow: bool = style.get("shadow", false)
	# halo (brilho sem shader: contornos largos translúcidos)
	var halo := 0.16 + 0.22 * energy
	ci.draw_polyline(closed, Color(glow, halo * 0.6 * alpha), 4.2 + 2.0 * energy, true)
	ci.draw_polyline(closed, Color(glow, halo * alpha), 2.2 + energy, true)
	if shadow:
		# energia sombria instável saindo do fio
		for k in 3:
			var f := 0.5 + 0.5 * sin(time * (7.0 + k * 2.3) + k * 1.9)
			var base := Vector2(lerpf(0.55, -0.1, k / 2.0) * length, 0.0)
			var side := 1.0 if k % 2 == 0 else -1.0
			ci.draw_colored_polygon(PackedVector2Array([
				base + Vector2(-0.12 * length, side * 0.1 * length),
				base + Vector2(0.1 * length, side * 0.1 * length),
				base + Vector2(-0.05 * length, side * (0.22 + 0.16 * f) * length),
			]), Color(glow, (0.25 + 0.35 * f) * alpha))
	ci.draw_colored_polygon(pts, Color(style.dark, alpha))
	ci.draw_polyline(closed, Color(glow, alpha), 0.9, true)
	ci.draw_line(Vector2(0.83, 0) * length, Vector2(-0.23, 0) * length, Color(style.core, alpha * (0.8 + 0.2 * energy)), 0.6, true)
	ci.draw_line(Vector2(-0.34, 0) * length, Vector2(-0.62, 0) * length, Color(style.trim, alpha), 1.5, true)
	ci.draw_circle(Vector2(-0.66, 0) * length, 0.9, Color(style.trim, alpha))


## A mesma lâmina como PEÇA PRONTA (desenho leve): montada uma vez num LiteBuilder, no espaço da
## lâmina (+x). `energy` fixa a intensidade do halo; a fumaça sombria fica parada no meio do ciclo.
static func bake(b: LiteBuilder, length: float, style: Dictionary, alpha: float, energy := 0.0) -> void:
	var pts := PackedVector2Array()
	for v in SHAPE:
		pts.append(v * length)
	var glow: Color = style.glow
	var halo := 0.16 + 0.22 * energy
	b.outline(pts, Color(glow, halo * 0.6 * alpha), 4.2 + 2.0 * energy)
	b.outline(pts, Color(glow, halo * alpha), 2.2 + energy)
	if style.get("shadow", false):
		for k in 3:
			var f := 0.5
			var base := Vector2(lerpf(0.55, -0.1, k / 2.0) * length, 0.0)
			var side := 1.0 if k % 2 == 0 else -1.0
			b.fill(PackedVector2Array([
				base + Vector2(-0.12 * length, side * 0.1 * length),
				base + Vector2(0.1 * length, side * 0.1 * length),
				base + Vector2(-0.05 * length, side * (0.22 + 0.16 * f) * length),
			]), Color(glow, (0.25 + 0.35 * f) * alpha))
	b.fill(pts, Color(style.dark, alpha))
	b.outline(pts, Color(glow, alpha), 0.9)
	b.line(Vector2(0.83, 0) * length, Vector2(-0.23, 0) * length, Color(style.core, alpha * (0.8 + 0.2 * energy)), 0.6)
	b.line(Vector2(-0.34, 0) * length, Vector2(-0.62, 0) * length, Color(style.trim, alpha), 1.5)
	b.disc(Vector2(-0.66, 0) * length, 0.9, Color(style.trim, alpha), 10)

