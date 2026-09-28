class_name Battle
extends Node
## Teste mínimo de combate: 1 aliado (esquerda) × 1 inimigo (direita).
## Avança a CombatSim em passo fixo e cria os visuais temporários em Stage/World/Entities.
##
## Sem fases, ondas, formação nem HUD: a luta começa sozinha; quando um lado cai, `finished` avisa.

signal finished(winner: CombatUnit)

## Stats do HTML (UNIT_DEFS.u_warrior e UNIT_DEFS.warrior). Sem scaling de onda.
const ALLY_STATS := {name = "Guerreiro Morto-Vivo", hp = 74.0, dmg = 10.0, range = 32.0, cd = 1.0, speed = 56.0, r = 12.0}
const ENEMY_STATS := {name = "Guerreiro", hp = 70.0, dmg = 9.0, range = 32.0, cd = 1.0, speed = 56.0, r = 12.0}

## Posições iniciais: mesma linha, uma de cada lado da divisa (x=500).
const ALLY_START := Vector2(150, 380)
const ENEMY_START := Vector2(850, 380)

## Limite do dt de um quadro (HTML: frame() limita dt a 0,05 s).
const MAX_FRAME_DT := 0.05

@export var entities_path: NodePath
@export var rng_seed := 97

var sim: CombatSim
var _views: Dictionary = {}   # id → UnitView
var _accumulator := 0.0
var _debug_visible := false
var _finished := false

@onready var _entities: Node2D = get_node(entities_path)


func _ready() -> void:
	restart()


## Monta a mesma luta de teste usada pelo teste headless (tests/combat_test.gd).
static func build_test_sim(seed_value: int) -> CombatSim:
	var s := CombatSim.new(seed_value)
	s.add_unit(CombatUnit.Team.PLAYER, ALLY_STATS, ALLY_START)
	s.add_unit(CombatUnit.Team.ENEMY, ENEMY_STATS, ENEMY_START)
	return s


func restart() -> void:
	for view in _views.values():
		view.queue_free()
	_views.clear()
	if sim:
		sim.dispose()
	_accumulator = 0.0
	_finished = false

	sim = build_test_sim(rng_seed)
	sim.unit_attacked.connect(_on_unit_attacked)
	for unit in sim.units:
		var view := UnitView.new(unit)
		view.debug_visible = _debug_visible
		_entities.add_child(view)
		_views[unit.id] = view


func _exit_tree() -> void:
	if sim:
		sim.dispose()


func set_debug_visible(value: bool) -> void:
	_debug_visible = value
	for view in _views.values():
		view.debug_visible = value


func is_debug_visible() -> bool:
	return _debug_visible


## A simulação continua depois do fim (o sobrevivente passa a IDLE); `finished` sai uma vez só.
func _process(delta: float) -> void:
	_accumulator += minf(delta, MAX_FRAME_DT)
	while _accumulator >= CombatSim.STEP:
		_accumulator -= CombatSim.STEP
		sim.step(CombatSim.STEP)
	if not _finished and sim.is_finished():
		_finished = true
		finished.emit(_first_alive())


func _first_alive() -> CombatUnit:
	for unit in sim.units:
		if unit.is_alive():
			return unit
	return null


func _on_unit_attacked(_attacker: CombatUnit, target: CombatUnit, _amount: float) -> void:
	var view: UnitView = _views.get(target.id)
	if view:
		view.flash_hit()
