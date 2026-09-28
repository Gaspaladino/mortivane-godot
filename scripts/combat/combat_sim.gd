class_name CombatSim
extends RefCounted
## Simulação mínima de combate: aquisição de alvo, movimento, ataque básico, dano e morte.
## Não depende de nós nem de desenho; roda igual em jogo e em teste headless.
##
## Regras (subconjunto do updateUnit do HTML, sem IA avançada):
##   1. Alvo = inimigo vivo mais próximo (distância centro a centro). Reavaliado a cada passo.
##   2. Fora do alcance → MOVING: anda em linha reta até o alvo.
##   3. No alcance → ATTACKING: para; ataca quando a recarga zera.
##   4. HP chega a 0 → DEAD: deixa de agir e deixa de ser alvo válido.
##   5. Sem inimigo vivo → IDLE.

signal unit_attacked(attacker: CombatUnit, target: CombatUnit, amount: float)
signal unit_died(unit: CombatUnit)

## Passo fixo da batalha (HTML: BATTLE_STEP = 1/120 s).
const STEP := 1.0 / 120.0

## Ao se aproximar, a unidade para um pouco dentro do alcance (HTML, corpo a corpo:
## avança enquanto dist > range × 0,85). Evita oscilar exatamente na borda do alcance.
const APPROACH_SHARE := 0.85

## Primeira recarga sorteada entre 0 e 40% do intervalo (HTML: cd = rnd(0, d.cd × 0,4)).
const INITIAL_COOLDOWN_SHARE := 0.4

var units: Array[CombatUnit] = []
var time := 0.0

var _rng := RandomNumberGenerator.new()
var _next_id := 1


func _init(seed_value := 0) -> void:
	_rng.seed = seed_value


func add_unit(team: CombatUnit.Team, stats: Dictionary, position: Vector2) -> CombatUnit:
	var unit := CombatUnit.new(_next_id, team, stats, _clamp_to_battlefield(position, stats.r))
	_next_id += 1
	unit.cooldown = _rng.randf_range(0.0, unit.attack_interval * INITIAL_COOLDOWN_SHARE)
	units.append(unit)
	return unit


func step(dt: float) -> void:
	time += dt
	for unit in units:
		if unit.is_alive():
			_update_unit(unit, dt)


## Desfaz as referências entre unidades (alvo ↔ alvo formam ciclo de RefCounted).
## Chamar ao descartar a simulação.
func dispose() -> void:
	for unit in units:
		unit.target = null
	units.clear()


## Inimigo vivo mais próximo; empate fica com o primeiro da lista.
func nearest_foe(unit: CombatUnit) -> CombatUnit:
	var best: CombatUnit = null
	var best_dist := INF
	for other in units:
		if other == unit or not unit.is_enemy_of(other) or not other.is_valid_target():
			continue
		var d := unit.position.distance_to(other.position)
		if d < best_dist:
			best_dist = d
			best = other
	return best


func alive_count(team: CombatUnit.Team) -> int:
	var count := 0
	for unit in units:
		if unit.team == team and unit.is_alive():
			count += 1
	return count


## A luta acabou quando um dos lados não tem mais ninguém vivo.
func is_finished() -> bool:
	return alive_count(CombatUnit.Team.PLAYER) == 0 or alive_count(CombatUnit.Team.ENEMY) == 0


func _update_unit(unit: CombatUnit, dt: float) -> void:
	unit.cooldown = maxf(0.0, unit.cooldown - dt)

	unit.target = nearest_foe(unit)
	if unit.target == null:
		unit.state = CombatUnit.State.IDLE
		return

	var to_target := unit.target.position - unit.position
	var dist := to_target.length()
	if dist > unit.attack_range:
		unit.state = CombatUnit.State.MOVING
		var advance := minf(unit.move_speed * dt, dist - unit.attack_range * APPROACH_SHARE)
		unit.position = _clamp_to_battlefield(unit.position + to_target / dist * advance, unit.radius)
		return

	unit.state = CombatUnit.State.ATTACKING
	if unit.cooldown <= 0.0:
		_attack(unit, unit.target)


func _attack(attacker: CombatUnit, target: CombatUnit) -> void:
	attacker.cooldown = attacker.attack_interval
	var applied := target.take_damage(attacker.damage)
	unit_attacked.emit(attacker, target, applied)
	if not target.is_alive():
		unit_died.emit(target)


## Mantém o corpo inteiro dentro da área jogável (HTML: clampPointToBattlefield).
static func _clamp_to_battlefield(point: Vector2, radius: float) -> Vector2:
	var r := WorldConfig.BATTLEFIELD_RECT
	return Vector2(
		clampf(point.x, r.position.x + radius, r.end.x - radius),
		clampf(point.y, r.position.y + radius, r.end.y - radius))
