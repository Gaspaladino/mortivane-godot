class_name PaladinFx
extends RefCounted
## Efeitos da habilidade do Paladino (só apresentação), comuns ao visual por código
## (PaladinVisual / ShadowPaladinVisual) e ao visual de sprites (PaladinSpriteVisual):
##   barrier()     — Escudo Sagrado à frente, na direção travada (HTML: drawPaladinBarrier)
##   taunt_ring()  — anel no raio real da provocação (115), abrindo e sumindo
##   shield_ring() — anel curto quando o escudo sobe
## Desenham no CanvasItem dado, no espaço do UnitView (sem espelhar).

const TAUNT_RING_TIME := 0.38
const SHIELD_RING_TIME := 0.28
# HTML: PALADIN_SHIELD_VISUAL
const BARRIER_WIDTH := 1.4
const BARRIER_HEIGHT := 2.55
const BARRIER_FORWARD := 1.72
const BARRIER_VERTICAL := -0.5
const BARRIER_ENTER := 0.2
const BARRIER_EXIT := 0.16


## `age` = segundos desde que o escudo subiu; `fallback_dir` = direção se ainda não houver trava.
static func barrier(ci: CanvasItem, pal: PaladinTaunt, radius: float, age: float, glow: float,
		fill: Color, edge: Color, fallback_dir: Vector2) -> void:
	var f := pal.facing if pal.facing != Vector2.ZERO else fallback_dir
	var pos := Vector2(f.x * radius * BARRIER_FORWARD, radius * BARRIER_VERTICAL + f.y * radius * BARRIER_FORWARD)
	var w := radius * BARRIER_WIDTH
	var h := radius * BARRIER_HEIGHT
	var enter := clampf(age / BARRIER_ENTER, 0.0, 1.0)
	var ez := 1.0 - pow(1.0 - enter, 3.0)
	var fade := clampf(pal.shield_t / BARRIER_EXIT, 0.0, 1.0)
	var hit := clampf(pal.shield_hit / PaladinTaunt.SHIELD_IMPACT, 0.0, 1.0)
	var a := ez * fade * (0.88 + 0.06 * sin(age * 7.0)) * glow
	var s := 0.7 + 0.3 * ez
	ci.draw_set_transform(pos, 0.0, Vector2(s, s))
	var path := PackedVector2Array()
	# HTML: holyShieldPath (escudo heráldico com curvas)
	for i in 9:
		var u := i / 8.0
		path.append(Vector2(lerpf(0.0, w * 0.5, u), lerpf(-h * 0.5, -h * 0.38, u * u)))
	for i in 7:
		var u := i / 6.0
		path.append(Vector2(lerpf(w * 0.47, 0.0, u * u), lerpf(h * 0.0, h * 0.5, u)))
	var n := path.size()
	for i in range(n - 2, 0, -1):
		path.append(Vector2(-path[i].x, path[i].y))
	ci.draw_colored_polygon(path, Color(fill, (0.13 + hit * 0.23) * a))
	var outline := path.duplicate()
	outline.append(path[0])
	ci.draw_polyline(outline, Color(edge.lerp(Color("fff6cb"), hit), 0.9 * a), 1.8, true)
	star(ci, Vector2(0, -h * 0.05), h * 0.16, Color(edge, 0.55 * a))
	ci.draw_set_transform(Vector2.ZERO)


## `t` = segundos desde a provocação (−1 = nada).
static func taunt_ring(ci: CanvasItem, t: float, glow: float, color: Color) -> void:
	if t < 0.0 or t > TAUNT_RING_TIME:
		return
	var k := clampf(t / TAUNT_RING_TIME, 0.0, 1.0)
	var r := PaladinTaunt.TAUNT_RADIUS * lerpf(0.35, 1.0, 1.0 - (1.0 - k) * (1.0 - k))
	# círculo no mundo: é a área real da provocação (a simulação mede distância euclidiana)
	ci.draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(color, 0.55 * (1.0 - k) * glow), 1.6, true)


static func shield_ring(ci: CanvasItem, t: float, radius: float, glow: float, color: Color) -> void:
	if t < 0.0 or t > SHIELD_RING_TIME:
		return
	var k := clampf(t / SHIELD_RING_TIME, 0.0, 1.0)
	ci.draw_arc(Vector2(0, -6), radius * 1.8 * lerpf(0.6, 1.0, k), 0.0, TAU, 40, Color(color, 0.8 * (1.0 - k) * glow), 1.4, true)


static func star(ci: CanvasItem, c: Vector2, s: float, col: Color, rot := 0.0) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := rot + i * TAU / 8.0 - PI / 2.0
		var r := s if i % 2 == 0 else s * 0.3
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	ci.draw_colored_polygon(pts, col)
