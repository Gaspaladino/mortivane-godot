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

@export var entities_path: NodePath
## Semente da primeira recarga de cada unidade: a mesma montagem sempre produz a mesma luta.
@export var rng_seed := 97

var sim: CombatSim
var _views: Dictionary = {}   # id da unidade → UnitView
var _accumulator := 0.0
var _running := false
var _finished := false
var _debug_visible := false

@onready var _entities: Node2D = get_node(entities_path)


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
	if sim:
		sim.dispose()
	sim = CombatSim.new(rng_seed)
	sim.unit_attacked.connect(_on_unit_attacked)
	_accumulator = 0.0
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
	while _accumulator >= CombatSim.STEP:
		_accumulator -= CombatSim.STEP
		sim.step(CombatSim.STEP)
	if not _finished and sim.is_finished():
		_finished = true
		finished.emit(_winner_team())


func _winner_team() -> int:
	if sim.alive_count(CombatUnit.Team.PLAYER) > 0:
		return CombatUnit.Team.PLAYER
	if sim.alive_count(CombatUnit.Team.ENEMY) > 0:
		return CombatUnit.Team.ENEMY
	return -1


## Eventos puramente visuais, no instante exato em que a CombatSim aplica o golpe:
## o atacante executa o golpe da espada e o alvo reage ao dano.
func _on_unit_attacked(attacker: CombatUnit, target: CombatUnit, _amount: float) -> void:
	var attacker_view := view_of(attacker)
	if attacker_view:
		attacker_view.on_attack_landed()
	var target_view := view_of(target)
	if target_view:
		target_view.on_hit()
