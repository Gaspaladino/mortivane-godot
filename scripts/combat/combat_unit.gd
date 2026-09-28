class_name CombatUnit
extends RefCounted
## Estado de uma unidade em combate. Dado puro: nenhum nó, nenhum desenho.
## Posições em coordenadas do mundo 1000×560 (WorldConfig).
##
## Stats portados de UNIT_DEFS do HTML (hp, dmg, range, cd, speed, r).

enum Team { PLAYER, ENEMY }
enum State { IDLE, MOVING, ATTACKING, DEAD }

var id: int
var display_name: String
var team: Team
var position: Vector2
var radius: float
var max_hp: float
var hp: float
var damage: float
## Distância centro a centro até o alvo em que a unidade já pode atacar (HTML: dist(u,t) <= range).
var attack_range: float
## Segundos entre ataques (HTML: cd).
var attack_interval: float
## Unidades do mundo por segundo (HTML: speed).
var move_speed: float

## Tempo restante até o próximo ataque.
var cooldown := 0.0
var target: CombatUnit = null
var state := State.IDLE


func _init(p_id: int, p_team: Team, stats: Dictionary, p_position: Vector2) -> void:
	id = p_id
	team = p_team
	display_name = stats.name
	max_hp = stats.hp
	hp = max_hp
	damage = stats.dmg
	attack_range = stats.range
	attack_interval = stats.cd
	move_speed = stats.speed
	radius = stats.r
	position = p_position


func is_alive() -> bool:
	return state != State.DEAD


## Só unidades vivas podem ser escolhidas como alvo.
func is_valid_target() -> bool:
	return is_alive()


func is_enemy_of(other: CombatUnit) -> bool:
	return other.team != team


## Aplica dano e devolve quanto foi realmente tirado. Ao chegar a 0, morre.
func take_damage(amount: float) -> float:
	if not is_alive() or amount <= 0.0:
		return 0.0
	var applied := minf(amount, hp)
	hp -= applied
	if hp <= 0.0:
		die()
	return applied


func die() -> void:
	hp = 0.0
	state = State.DEAD
	target = null
	cooldown = 0.0


func label() -> String:
	return "%s #%d" % [display_name, id]


static func state_name(value: State) -> String:
	return State.keys()[value]
