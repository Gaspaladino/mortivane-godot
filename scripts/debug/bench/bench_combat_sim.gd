class_name BenchCombatSim
extends CombatSim
## SÓ PARA BENCHMARK (tools/bench). Não é usada pelo jogo: a Battle só a cria quando alguém
## põe `battle.sim_script = BenchCombatSim` (o stress test faz isso).
##
## Em modo FULL não copia regra nenhuma: cada método sobrescrito chama o da CombatSim (`super`)
## e só cronometra/conta em volta. Assim o benchmark mede exatamente o código do jogo, inclusive
## depois das otimizações. Os contadores de busca de alvo vêm da própria CombatSim (stat_*).
##
## Modos (só para isolar custos no benchmark):
##   FULL        — regras normais (alvo, movimento, ataque, dano, morte, habilidades).
##   TARGET_ONLY — aquisição de alvo e aproximação do jogo, sem ataque, dano nem habilidades
##                 (quem chega ao alcance fica em ATTACKING sem bater).
##   MOVE_ONLY   — sem alvo: cada unidade anda de ida e volta entre a posição inicial e o ponto
##                 espelhado do outro lado da arena (custo de movimento/animação puro).

enum Mode { FULL, TARGET_ONLY, MOVE_ONLY }

## Modo das próximas instâncias (o runner escolhe antes de a Battle recriar a simulação).
static var next_mode := Mode.FULL
## false = só contadores, sem Time.get_ticks_usec (mede o custo da própria instrumentação).
static var next_timing := true

var mode := Mode.FULL
var timing := true

# --- Contadores próprios do benchmark (os de alvo vêm de CombatSim.stat_*) ----------------
var steps := 0
var unit_updates := 0
var target_kept := 0             # depois do passo, a unidade tem o MESMO alvo de antes
var target_changed := 0          # trocou de alvo (inclui null → alguém)
var target_lost := 0             # ficou sem alvo
var attacks := 0
var damage_events := 0
var deaths := 0
var paladin_taunt_checks := 0    # candidatos testados por try_taunt (inimigos vivos por Paladino pronto)

# --- Cronômetros (µs acumulados) ----------------------------------------------------------
var us_step := 0
var us_paladins := 0
var us_target := 0               # dentro de nearest_foe (inclui as chamadas das lâminas e do escudo)
var us_attack := 0
var us_projectiles := 0

var _in_target := 0              # nearest_foe pode ser chamada de dentro de outra seção
var _waypoints := {}             # MOVE_ONLY: ponto de ida/volta de cada unidade


func _init(seed_value := 0) -> void:
	super(seed_value)
	mode = next_mode
	timing = next_timing


func counters() -> Dictionary:
	return {
		steps = steps, unit_updates = unit_updates,
		nearest_calls = stat_target_queries, target_scans = stat_target_scans, examined = stat_candidates,
		target_kept = target_kept, target_changed = target_changed, target_lost = target_lost,
		attacks = attacks, damage_events = damage_events, deaths = deaths,
		paladin_taunt_checks = paladin_taunt_checks,
		us_step = us_step, us_paladins = us_paladins, us_target = us_target, us_attack = us_attack,
		us_projectiles = us_projectiles,
	}


static func _now() -> int:
	return Time.get_ticks_usec()


func step(dt: float) -> void:
	steps += 1
	if not timing:
		super(dt)
		return
	var t0 := _now()
	super(dt)
	us_step += _now() - t0


func nearest_foe(unit: CombatUnit) -> CombatUnit:
	if not timing or _in_target > 0:
		return super(unit)
	_in_target += 1
	var t0 := _now()
	var r := super(unit)
	us_target += _now() - t0
	_in_target -= 1
	return r


func _tick_paladins(dt: float) -> void:
	if mode != Mode.FULL:
		return
	for u in units:
		if u.paladin and u.is_alive() and u.paladin.cooldown - dt <= PaladinTaunt.EPS:
			paladin_taunt_checks += alive_count(CombatUnit.Team.ENEMY if u.team == CombatUnit.Team.PLAYER else CombatUnit.Team.PLAYER)
	if not timing:
		super(dt)
		return
	var t0 := _now()
	super(dt)
	us_paladins += _now() - t0


func _update_projectiles(dt: float) -> void:
	if not timing:
		super(dt)
		return
	var t0 := _now()
	super(dt)
	us_projectiles += _now() - t0


func _attack(attacker: CombatUnit, target: CombatUnit) -> void:
	attacks += 1
	if not timing:
		super(attacker, target)
		return
	var t0 := _now()
	super(attacker, target)
	us_attack += _now() - t0


func _apply_damage(attacker: CombatUnit, target: CombatUnit, amount: float) -> void:
	damage_events += 1
	var was_alive := target.is_alive()
	super(attacker, target, amount)
	if was_alive and not target.is_alive():
		deaths += 1


func _update_unit(unit: CombatUnit, dt: float) -> void:
	unit_updates += 1
	var previous := unit.target
	match mode:
		Mode.FULL:
			super(unit, dt)
		Mode.MOVE_ONLY:
			unit.cooldown = maxf(0.0, unit.cooldown - dt)
			_bench_walk(unit, dt)
			return
		Mode.TARGET_ONLY:
			_bench_target_only(unit, dt)
	if unit.target == null:
		if previous != null:
			target_lost += 1
	elif unit.target == previous:
		target_kept += 1
	else:
		target_changed += 1


## TARGET_ONLY: o mesmo alvo e a mesma aproximação da CombatSim, sem lâminas, ataque nem dano.
func _bench_target_only(unit: CombatUnit, dt: float) -> void:
	unit.cooldown = maxf(0.0, unit.cooldown - dt)
	unit.target = nearest_foe(unit)
	if unit.target == null:
		unit.state = CombatUnit.State.IDLE
		return
	var to_target := unit.target.position - unit.position
	var dist := to_target.length()
	if dist > unit.attack_range:
		unit.state = CombatUnit.State.MOVING
		var advance := minf(unit.move_speed * dt, dist - unit.attack_range * unit.approach_share)
		unit.position = _clamp_to_battlefield(unit.position + to_target / dist * advance, unit.radius)
		return
	unit.state = CombatUnit.State.ATTACKING


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
