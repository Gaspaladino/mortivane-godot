class_name BenchCombatSim
extends CombatSim
## SÓ PARA BENCHMARK (tools/bench). Não é usada pelo jogo: a Battle só a cria quando alguém
## põe `battle.sim_script = BenchCombatSim` (o stress test faz isso).
##
## Mesma lógica da CombatSim — `step`, `nearest_foe`, `taunt_target`, `_update_unit` e
## `_update_projectiles` são cópias fiéis — com contadores e cronômetros por seção. O modo FULL
## produz exatamente a mesma luta da CombatSim (garantido por tests/bench_parity_test.gd).
##
## Modos (só para isolar custos no benchmark):
##   FULL        — regras normais (alvo, movimento, ataque, dano, morte, habilidades).
##   TARGET_ONLY — aquisição de alvo e aproximação iguais ao FULL, mas sem ataque, dano nem
##                 habilidades (quem chega ao alcance fica em ATTACKING sem bater).
##   MOVE_ONLY   — sem alvo: cada unidade anda de ida e volta entre a posição inicial e o ponto
##                 espelhado do outro lado da arena (custo de movimento/animação puro).

enum Mode { FULL, TARGET_ONLY, MOVE_ONLY }

## Modo das próximas instâncias (o runner escolhe antes de a Battle recriar a simulação).
static var next_mode := Mode.FULL
## false = só contadores, sem Time.get_ticks_usec (mede o custo da própria instrumentação).
static var next_timing := true

var mode := Mode.FULL
var timing := true

# --- Contadores (acumulados; o runner lê a diferença por quadro) --------------------------
var steps := 0
var unit_updates := 0            # _update_unit de unidades vivas
var nearest_calls := 0           # chamadas de nearest_foe (alvo + lâminas da Sentinela + escudo)
var nearest_calls_swords := 0    # das quais vieram das lâminas da Sentinela
var nearest_forced := 0          # resolvidas pela provocação (sem varrer a lista)
var examined := 0                # unidades olhadas dentro de nearest_foe
var dist_checks := 0             # distâncias calculadas dentro de nearest_foe
var target_kept := 0             # recálculo deu o MESMO alvo de antes (trabalho sem necessidade)
var target_changed := 0          # recálculo trocou de alvo (inclui null → alguém)
var target_lost := 0             # ficou sem alvo
var range_checks := 0            # distância até o alvo comparada com o alcance
var moves := 0                   # passos de movimento
var attacks := 0                 # ataques básicos executados
var damage_events := 0
var deaths := 0
var taunt_scans := 0             # varreduras `p in units` do taunt_target (até N cada)
var taunt_target_calls := 0
var paladin_taunt_checks := 0    # distâncias testadas por try_taunt (N por Paladino pronto)
var projectile_updates := 0
var projectile_hit_checks := 0   # distâncias projétil × unidade

# --- Cronômetros (µs acumulados) ----------------------------------------------------------
var us_step := 0
var us_paladins := 0
var us_swords := 0
var us_target := 0
var us_move := 0
var us_attack := 0
var us_projectiles := 0

# MOVE_ONLY: ponto de ida/volta de cada unidade
var _waypoints := {}


func _init(seed_value := 0) -> void:
	super(seed_value)
	mode = next_mode
	timing = next_timing


func counters() -> Dictionary:
	return {
		steps = steps, unit_updates = unit_updates, nearest_calls = nearest_calls,
		nearest_calls_swords = nearest_calls_swords, nearest_forced = nearest_forced, examined = examined,
		dist_checks = dist_checks, target_kept = target_kept, target_changed = target_changed,
		target_lost = target_lost, range_checks = range_checks, moves = moves, attacks = attacks,
		damage_events = damage_events, deaths = deaths, taunt_scans = taunt_scans,
		taunt_target_calls = taunt_target_calls, paladin_taunt_checks = paladin_taunt_checks,
		projectile_updates = projectile_updates, projectile_hit_checks = projectile_hit_checks,
		us_step = us_step, us_paladins = us_paladins, us_swords = us_swords, us_target = us_target,
		us_move = us_move, us_attack = us_attack, us_projectiles = us_projectiles,
	}


static func _now() -> int:
	return Time.get_ticks_usec()


func step(dt: float) -> void:
	var t0 := _now() if timing else 0
	steps += 1
	time += dt
	if mode == Mode.FULL:
		var tp := _now() if timing else 0
		_tick_paladins(dt)
		if timing:
			us_paladins += _now() - tp
	for unit in units:
		if unit.is_alive():
			_update_unit(unit, dt)
	if mode == Mode.FULL:
		var tq := _now() if timing else 0
		_update_projectiles(dt)
		if timing:
			us_projectiles += _now() - tq
	if timing:
		us_step += _now() - t0


func nearest_foe(unit: CombatUnit) -> CombatUnit:
	nearest_calls += 1
	var forced := taunt_target(unit)
	if forced:
		nearest_forced += 1
		return forced
	var best: CombatUnit = null
	var best_dist := INF
	for other in units:
		examined += 1
		if other == unit or not unit.is_enemy_of(other) or not other.is_valid_target():
			continue
		dist_checks += 1
		var d := unit.position.distance_to(other.position)
		if d < best_dist:
			best_dist = d
			best = other
	return best


func taunt_target(unit: CombatUnit) -> CombatUnit:
	taunt_target_calls += 1
	var p := unit.taunted_by
	if unit.taunt_t > 0.0 and p and p.is_valid_target() and p.team != unit.team:
		taunt_scans += units.size()   # `p in units`: varredura linear (até N)
		if p in units:
			return p
	if p:
		_clear_taunt(unit)
	return null


func _tick_paladins(dt: float) -> void:
	for u in units:
		if u.paladin and u.is_alive() and u.paladin.cooldown - dt <= PaladinTaunt.EPS:
			paladin_taunt_checks += units.size()
	super(dt)


func _update_unit(unit: CombatUnit, dt: float) -> void:
	unit_updates += 1
	unit.cooldown = maxf(0.0, unit.cooldown - dt)
	if mode == Mode.MOVE_ONLY:
		var tw := _now() if timing else 0
		_bench_walk(unit, dt)
		if timing:
			us_move += _now() - tw
		return
	if unit.swords and mode == Mode.FULL:   # lâminas pairando (HTML: updateArcaneSwords, antes do alvo)
		var ts := _now() if timing else 0
		var before := nearest_calls
		var launch := unit.swords.update(unit, self, dt)
		nearest_calls_swords += nearest_calls - before
		if not launch.is_empty():
			_launch_sword(unit, launch[0], launch[1])
		if timing:
			us_swords += _now() - ts

	var previous := unit.target
	var tt := _now() if timing else 0
	unit.target = nearest_foe(unit)
	if timing:
		us_target += _now() - tt
	if unit.target == null:
		if previous != null:
			target_lost += 1
		unit.state = CombatUnit.State.IDLE
		return
	if unit.target == previous:
		target_kept += 1
	else:
		target_changed += 1

	var tm := _now() if timing else 0
	var to_target := unit.target.position - unit.position
	var dist := to_target.length()
	range_checks += 1
	if dist > unit.attack_range:
		unit.state = CombatUnit.State.MOVING
		var advance := minf(unit.move_speed * dt, dist - unit.attack_range * unit.approach_share)
		unit.position = _clamp_to_battlefield(unit.position + to_target / dist * advance, unit.radius)
		moves += 1
		if timing:
			us_move += _now() - tm
		return

	unit.state = CombatUnit.State.ATTACKING
	if timing:
		us_move += _now() - tm
	if mode != Mode.FULL:
		return
	if unit.cooldown <= 0.0:
		var ta := _now() if timing else 0
		attacks += 1
		_attack(unit, unit.target)
		if timing:
			us_attack += _now() - ta


func _apply_damage(attacker: CombatUnit, target: CombatUnit, amount: float) -> void:
	damage_events += 1
	var was_alive := target.is_alive()
	super(attacker, target, amount)
	if was_alive and not target.is_alive():
		deaths += 1


func _update_projectiles(dt: float) -> void:
	var i := projectiles.size() - 1
	while i >= 0:
		var p := projectiles[i]
		projectile_updates += 1
		p.life -= dt
		var tgt: CombatUnit = p.target if p.can_hit(p.target) else null
		if tgt:
			p.direction = (tgt.position - p.position).angle()
		p.position += Vector2.from_angle(p.direction) * p.speed * dt
		var victim: CombatUnit = null
		if tgt and p.position.distance_to(tgt.position) < tgt.radius + CombatProjectile.TARGET_HIT_SLACK:
			victim = tgt
		else:
			for unit in units:
				projectile_hit_checks += 1
				if p.can_hit(unit) and p.position.distance_to(unit.position) < unit.radius + CombatProjectile.PATH_HIT_SLACK:
					victim = unit
					break
		if victim:
			projectiles.remove_at(i)
			_apply_damage(p.owner, victim, p.damage)
			projectile_ended.emit(p, victim)
		elif p.life <= 0.0 or not Rect2(Vector2.ZERO, WorldConfig.SIZE).grow(CombatProjectile.OUT_MARGIN).has_point(p.position):
			projectiles.remove_at(i)
			projectile_ended.emit(p, null)
		i -= 1


## MOVE_ONLY: ida e volta em linha reta entre a posição inicial e o ponto espelhado (x → 1000 − x).
func _bench_walk(unit: CombatUnit, dt: float) -> void:
	if not _waypoints.has(unit.id):
		_waypoints[unit.id] = [unit.position, Vector2(WorldConfig.WIDTH - unit.position.x, unit.position.y), 1]
	var w: Array = _waypoints[unit.id]
	var goal: Vector2 = w[w[2]]
	var to_goal := goal - unit.position
	var dist := to_goal.length()
	if dist < 2.0:
		w[2] = 1 - int(w[2])
		return
	unit.state = CombatUnit.State.MOVING
	unit.position = _clamp_to_battlefield(unit.position + to_goal / dist * minf(unit.move_speed * dt, dist), unit.radius)
	moves += 1
