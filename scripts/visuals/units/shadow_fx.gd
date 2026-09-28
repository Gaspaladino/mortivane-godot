class_name ShadowFX
extends RefCounted
## Efeitos da "sombra necromântica", comuns a todas as unidades revividas. Funções estáticas
## que desenham num CanvasItem (o visual da unidade), no transform que estiver ativo:
##   aura()        — halo roxo suave atrás do corpo (separa a silhueta do cenário)
##   ground_mist() — poça de névoa roxa no lugar da sombra comum
##   smoke()       — fiapos que sobem de pontos do corpo e se desfazem (poucos, lentos)
##   crack()       — fissura de energia (linha larga translúcida + núcleo claro)
##   eye()         — olho brilhando
## Tudo é determinístico pelo tempo (sem partículas nem nós): barato com dezenas de unidades.
## `k` = intensidade geral (0 = apagado; a morte e o HIT modulam).


## Halo atrás do corpo: elipses concêntricas com alfa decrescente.
static func aura(ci: CanvasItem, center: Vector2, radii: Vector2, style: ShadowStyle, time: float, k := 1.0) -> void:
	var a := 0.09 * style.aura * k * (0.85 + 0.15 * sin(time * 1.7 * style.pulse_speed))
	if a <= 0.0:
		return
	for i in 4:
		var s := 1.0 - i * 0.2
		ci.draw_set_transform(center, 0.0, Vector2(radii.x * s, radii.y * s))
		ci.draw_circle(Vector2.ZERO, 1.0, Color(style.energy, a * (0.55 + i * 0.35)))
	ci.draw_set_transform(Vector2.ZERO)


## Névoa roxa no chão (substitui a sombra preta): núcleo escuro + borda roxa que respira.
static func ground_mist(ci: CanvasItem, foot: Vector2, width: float, style: ShadowStyle, time: float, k := 1.0) -> void:
	var b := 0.9 + 0.1 * sin(time * 1.3)
	ci.draw_set_transform(foot, 0.0, Vector2(width * 1.35 * b, width * 0.42))
	ci.draw_circle(Vector2.ZERO, 1.0, Color(style.smoke, style.smoke.a * 0.35 * k * style.smoke_amount))
	ci.draw_set_transform(foot, 0.0, Vector2(width, width * 0.3))
	ci.draw_circle(Vector2.ZERO, 1.0, Color(0.02, 0.0, 0.05, 0.42))
	ci.draw_set_transform(Vector2.ZERO)


## Fiapos de fumaça subindo de `sources` (pontos no espaço atual). Cada fiapo nasce, sobe
## `rise` px desviando de lado e some; `count` fiapos por ponto, defasados.
static func smoke(ci: CanvasItem, sources: PackedVector2Array, style: ShadowStyle, time: float, seed: float,
		rise := 9.0, size := 1.6, count := 2, k := 1.0) -> void:
	var amount := style.smoke_amount * k
	if amount <= 0.0:
		return
	for s in sources.size():
		for j in count:
			var h := _hash(s * 7.0 + j, seed)
			var u := fposmod(time * (0.32 + 0.18 * h) + h + float(j) / count, 1.0)
			var p := sources[s] + Vector2(sin(u * 5.0 + h * 9.0) * 1.6 + u * 1.2, -rise * u)
			var r := size * (1.0 - 0.55 * u) * (0.8 + 0.4 * h)
			var a := style.smoke.a * amount * sin(u * PI) * 0.8
			ci.draw_colored_polygon(PackedVector2Array([
				p + Vector2(-r, 0.4 * r), p + Vector2(-0.4 * r, -1.2 * r), p + Vector2(0.2 * r, -2.4 * r),
				p + Vector2(0.7 * r, -0.9 * r), p + Vector2(r, 0.5 * r), p + Vector2(0, r),
			]), Color(style.smoke, a))


## Fissura de energia ao longo de `pts`. `pulse` 0..1 (brilho extra).
static func crack(ci: CanvasItem, pts: PackedVector2Array, style: ShadowStyle, pulse := 0.5, k := 1.0) -> void:
	var a := clampf(style.cracks * k, 0.0, 1.5)
	if a <= 0.0 or pts.size() < 2:
		return
	ci.draw_polyline(pts, Color(style.energy, 0.28 * a * (0.7 + 0.3 * pulse)), 1.7, true)
	ci.draw_polyline(pts, Color(style.energy.lerp(style.energy_core, 0.35 + 0.3 * pulse), 0.95 * minf(a, 1.0)), 0.55, true)


## Olho brilhando: halo + ponto claro.
static func eye(ci: CanvasItem, pos: Vector2, radius: float, style: ShadowStyle, pulse := 1.0, k := 1.0) -> void:
	if k <= 0.0:
		return
	ci.draw_circle(pos, radius * 2.4, Color(style.energy, 0.22 * k * pulse))
	ci.draw_circle(pos, radius * 1.3, Color(style.energy, 0.55 * k))
	ci.draw_circle(pos, radius * 0.7, Color(style.eye, 0.95 * k))


## Pulsação lenta (0..1) usada por fissuras e olhos.
static func pulse(style: ShadowStyle, time: float, seed: float) -> float:
	return 0.5 + 0.5 * sin(time * 2.4 * style.pulse_speed + seed) * (0.7 + 0.3 * sin(time * 0.9 + seed * 2.0))


static func _hash(i: float, s: float) -> float:
	var v := sin(i * 127.1 + s * 311.7) * 43758.5453
	return v - floorf(v)
