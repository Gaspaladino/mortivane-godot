class_name Battle
extends Node
## Executor de combate da Arena: dono da CombatSim, dos UnitView e do relógio de passo fixo.
##
## Não decide quem luta nem quando: quem usa a Arena (hoje, o Sandbox) chama
## spawn() para posicionar, start() para começar e clear() para esvaziar.
## Antes de start() as unidades ficam paradas (a simulação não avança).

## Um lado ficou sem ninguém vivo. `winner_team` é um CombatUnit.Team, ou -1 se ninguém sobrou.
signal finished(winner_team: int)

## Limite do dt de um quadro (HTML: frame() limita dt a 0,05 s).
const MAX_FRAME_DT := 0.05
## Proteção contra o efeito cascata (etapa 6 da otimização): no máximo este número de passos da
## simulação por quadro. A 60 FPS são 2 passos por quadro; 4 cobrem quadros de até 33 ms (30 FPS)
## sem perder tempo de jogo. Se o quadro demora mais, o que passar de 4 passos NÃO é recuperado de
## uma vez (antes: até 6, e cada passo a mais deixava o quadro seguinte ainda mais lento). A
## sobra fica guardada (no máximo MAX_SIM_STEPS_PER_FRAME passos) e é recuperada nos quadros
## seguintes, se eles forem rápidos; o que passar disso é descartado — o jogo fica em câmera
## lenta enquanto a máquina não dá conta, em vez de travar.
## O RESULTADO da luta não muda: a simulação é determinística por passo (STEP fixo de 1/120 s) e
## executa exatamente a mesma sequência de passos; só a relação com o relógio real muda.
const MAX_SIM_STEPS_PER_FRAME := 4

@export var entities_path: NodePath
## Onde ficam os ProjectileView (acima das unidades).
@export var effects_path: NodePath
## Semente da primeira recarga de cada unidade: a mesma montagem sempre produz a mesma luta.
@export var rng_seed := 97
## Só benchmark (tools/bench): script da simulação criada em clear(). null = CombatSim (o jogo).
var sim_script: Script = null

var sim: CombatSim
var _views: Dictionary = {}   # id da unidade → UnitView
var _projectile_views: Dictionary = {}   # id do projétil → ProjectileView
var _accumulator := 0.0
## Diagnóstico: passos executados no último quadro e tempo de jogo descartado (s) desde o início.
var steps_last_frame := 0
var dropped_time := 0.0
var _running := false
var _finished := false
var _debug_visible := false

@onready var _entities: Node2D = get_node(entities_path)
@onready var _effects: Node2D = get_node(effects_path)


func _ready() -> void:
	clear()


func _exit_tree() -> void:
	if sim:
		sim.dispose()


## Remove todas as unidades e começa uma simulação nova, parada.
func clear() -> void:
	for view in _views.values():
		view.queue_free()
	_views.clear()
	for view in _projectile_views.values():
		if is_instance_valid(view):
			view.queue_free()
	_projectile_views.clear()
	if sim:
		sim.dispose()
	sim = sim_script.new(rng_seed) if sim_script else CombatSim.new(rng_seed)
	sim.attack_performed.connect(_on_attack_performed)
	sim.unit_attacked.connect(_on_unit_attacked)
	sim.projectile_fired.connect(_on_projectile_fired)
	sim.projectile_ended.connect(_on_projectile_ended)
	sim.paladin_taunted.connect(func(u: CombatUnit, _foes: Array) -> void: _ability_event(u, &"taunt"))
	sim.paladin_shield_raised.connect(func(u: CombatUnit) -> void: _ability_event(u, &"shield"))
	sim.paladin_shield_blocked.connect(func(u: CombatUnit, _prevented: float) -> void: _ability_event(u, &"block"))
	_accumulator = 0.0
	dropped_time = 0.0
	_running = false
	_finished = false


## Cria uma unidade na simulação real e o visual dela. `overrides` troca stats desta instância.
func spawn(def: UnitDef, team: CombatUnit.Team, position: Vector2, overrides := {}) -> CombatUnit:
	var unit := sim.add_unit(team, def.to_stats(overrides), position)
	var view := UnitView.new(unit, def)
	view.debug_visible = _debug_visible
	_entities.add_child(view)
	_views[unit.id] = view
	return unit


func start() -> void:
	_running = true


func is_running() -> bool:
	return _running


func is_finished() -> bool:
	return _finished


func view_of(unit: CombatUnit) -> UnitView:
	return _views.get(unit.id) if unit else null


## Unidade sob o ponto (coordenadas do mundo), pela área clicável do visual.
## Vivas têm prioridade sobre mortas; entre iguais, a de centro mais próximo.
func unit_at(point: Vector2) -> CombatUnit:
	var best: CombatUnit = null
	var best_score := INF
	for unit in sim.units:
		var view := view_of(unit)
		if view == null or not view.contains_point(point):
			continue
		var d := unit.position.distance_to(point)
		var score := d + (0.0 if unit.is_alive() else 1000.0)
		if score < best_score:
			best_score = score
			best = unit
	return best


func set_debug_visible(value: bool) -> void:
	_debug_visible = value
	for view in _views.values():
		view.debug_visible = value


func is_debug_visible() -> bool:
	return _debug_visible


## Depois do fim a simulação continua (sobreviventes passam a IDLE); `finished` sai uma vez só.
func _process(delta: float) -> void:
	if not _running:
		return
	_accumulator += minf(delta, MAX_FRAME_DT)
	steps_last_frame = 0
	while _accumulator >= CombatSim.STEP and steps_last_frame < MAX_SIM_STEPS_PER_FRAME:
		steps_last_frame += 1
		_accumulator -= CombatSim.STEP
		sim.step(CombatSim.STEP)
	var max_debt := CombatSim.STEP * MAX_SIM_STEPS_PER_FRAME
	if _accumulator > max_debt:
		dropped_time += _accumulator - max_debt
		_accumulator = max_debt
	if not _finished and sim.is_finished():
		_finished = true
		finished.emit(_winner_team())


func _winner_team() -> int:
	if sim.alive_count(CombatUnit.Team.PLAYER) > 0:
		return CombatUnit.Team.PLAYER
	if sim.alive_count(CombatUnit.Team.ENEMY) > 0:
		return CombatUnit.Team.ENEMY
	return -1


func projectile_view_of(p: CombatProjectile) -> ProjectileView:
	return _projectile_views.get(p.id)


# --- Eventos da simulação → apresentação (nenhum altera a simulação) --------------------

## O atacante executou o ataque básico (golpe corpo a corpo ou disparo), no mesmo passo.
func _on_attack_performed(attacker: CombatUnit, _target: CombatUnit) -> void:
	var view := view_of(attacker)
	if view:
		view.on_attack_performed()


## Dano aplicado: o alvo reage.
func _on_unit_attacked(_attacker: CombatUnit, target: CombatUnit, _amount: float) -> void:
	var view := view_of(target)
	if view:
		view.on_hit()


## Evento de habilidade (provocação, escudo…): só apresentação.
func _ability_event(unit: CombatUnit, kind: StringName) -> void:
	var view := view_of(unit)
	if view:
		view.on_ability_event(kind)


func _on_projectile_fired(p: CombatProjectile) -> void:
	var owner_view := view_of(p.owner)
	var muzzle := p.position
	var style := UnitVisual.DEFAULT_PROJECTILE_STYLE
	if owner_view:
		owner_view.on_projectile_fired(p)
		muzzle = owner_view.position + owner_view.visual.muzzle_point(p)
		style = owner_view.visual.projectile_style(p)
	var view := ProjectileView.new(p, style, muzzle)
	_effects.add_child(view)
	_projectile_views[p.id] = view


func _on_projectile_ended(p: CombatProjectile, victim: CombatUnit) -> void:
	var view: ProjectileView = _projectile_views.get(p.id)
	_projectile_views.erase(p.id)
	if view and is_instance_valid(view):
		view.finish(victim)
