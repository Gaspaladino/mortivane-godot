class_name ProjectileView
extends Node2D
## Apresentação de um CombatProjectile (orbe da Sentinela, lâmina arcana…). Só lê o projétil.
##
## - Partida: nos primeiros LAUNCH_BLEND s, desenha a partir do ponto em que o visual do dono
##   diz que o projétil sai (mão, lâmina pairando) e converge para a posição real da simulação
##   (HTML: sentinelHand). A simulação não muda.
## - Voo: orbe com halo e rastro, ou a própria lâmina (ArcaneBlade) com rastro.
## - Fim: finish() toca o impacto (ou a dissipação, se expirou) e o nó se libera sozinho.

const LAUNCH_BLEND := 0.12
const IMPACT_TIME := 0.34
const TRAIL_POINTS := 7
const SWORD_LENGTH := 11.0

var projectile: CombatProjectile
var style: Dictionary

var _start_offset := Vector2.ZERO
var _age := 0.0
var _impact_t := -1.0
var _hit := false
var _trail: Array[Vector2] = []
var _seed := 0.0


func _init(p: CombatProjectile, p_style: Dictionary, muzzle_world: Vector2) -> void:
	projectile = p
	style = p_style
	name = "Projectile%d" % p.id
	_start_offset = muzzle_world - p.position
	_seed = float(p.id) * 2.39
	position = muzzle_world


func finish(victim: CombatUnit) -> void:
	_hit = victim != null
	_impact_t = 0.0
	position = projectile.position
	queue_redraw()


func is_finished() -> bool:
	return _impact_t >= 0.0


func _process(delta: float) -> void:
	if _impact_t >= 0.0:
		_impact_t += delta
		if _impact_t > IMPACT_TIME:
			queue_free()
	else:
		_age += delta
		var k := clampf(_age / LAUNCH_BLEND, 0.0, 1.0)
		position = projectile.position + _start_offset * (1.0 - k * k * (3.0 - 2.0 * k))
		_trail.push_front(position)
		if _trail.size() > TRAIL_POINTS:
			_trail.pop_back()
	queue_redraw()


func _draw() -> void:
	if _impact_t >= 0.0:
		_draw_impact()
	elif projectile.is_sword():
		_draw_sword()
	else:
		_draw_orb()


func _draw_orb() -> void:
	var glow: Color = style.glow
	var shadow: bool = style.get("shadow", false)
	for i in range(_trail.size() - 1, 0, -1):
		var a := 1.0 - float(i) / TRAIL_POINTS
		draw_circle(_trail[i] - position, 2.6 * a, Color(glow, 0.28 * a))
	var pulse := 0.5 + 0.5 * sin(_age * 30.0 + _seed)
	draw_circle(Vector2.ZERO, 6.0 + pulse, Color(glow, 0.16))
	draw_circle(Vector2.ZERO, 3.9, Color(glow, 0.45))
	if shadow:
		# núcleo escuro com borda violeta e espinhos instáveis: pressão, não luz limpa
		for k in 4:
			var ang := _age * 9.0 + k * TAU / 4.0 + _seed
			var reach := 5.0 + 2.5 * (0.5 + 0.5 * sin(_age * 23.0 + k))
			draw_line(Vector2.from_angle(ang) * 2.5, Vector2.from_angle(ang) * reach, Color(glow, 0.7), 1.0, true)
		draw_circle(Vector2.ZERO, 2.6, style.dark)
		draw_arc(Vector2.ZERO, 2.6, 0.0, TAU, 16, style.core, 1.0, true)
	else:
		draw_circle(Vector2.ZERO, 2.5, style.core)
		draw_circle(Vector2(-0.7, -0.7), 0.9, Color.WHITE)


func _draw_sword() -> void:
	var glow: Color = style.glow
	var dir := Vector2.from_angle(projectile.direction)
	# rastro de energia atrás da lâmina
	if _trail.size() > 1:
		var pts := PackedVector2Array()
		for p in _trail:
			pts.append(p - position - dir * SWORD_LENGTH * 0.3)
		draw_polyline(pts, Color(glow, 0.22), 4.0, true)
		draw_polyline(pts, Color(glow, 0.5), 1.4, true)
	ArcaneBlade.draw(self, Transform2D(projectile.direction, Vector2.ZERO), SWORD_LENGTH, style, 1.0, _age + _seed, 0.6)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_impact() -> void:
	var k := _impact_t / IMPACT_TIME
	var glow: Color = style.glow
	var shadow: bool = style.get("shadow", false)
	var big := projectile.is_sword()
	var ring_r := lerpf(3.0, 16.0 if big else 11.0, sqrt(k))
	var a := 1.0 - k
	if not _hit:
		# expirou sem acertar: só se dissipa
		draw_arc(Vector2.ZERO, ring_r * 0.6, 0.0, TAU, 20, Color(glow, 0.4 * a), 1.0, true)
		return
	draw_circle(Vector2.ZERO, ring_r * 0.55, Color(glow, 0.25 * a))
	draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 24, Color(glow, 0.9 * a), 1.6, true)
	var n := 9 if big else 5
	for i in n:
		var ang := _seed + i * TAU / n
		var d := Vector2.from_angle(ang)
		draw_line(d * ring_r * 0.5, d * ring_r * (1.0 + 0.3 * (i % 2)), Color(style.core if not shadow else glow, a), 1.1, true)
	if big:   # corte da lâmina
		var dir := Vector2.from_angle(projectile.direction)
		draw_line(-dir.orthogonal() * 9.0 * (1.0 - k * 0.3), dir.orthogonal() * 9.0 * (1.0 - k * 0.3), Color(style.core, a), 1.4, true)
