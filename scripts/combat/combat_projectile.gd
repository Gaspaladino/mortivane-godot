class_name CombatProjectile
extends RefCounted
## Projétil da simulação (dado puro). Porta de fireProjectile/updateProjectiles do HTML,
## só com o que as unidades atuais usam (sem relíquias, perfuração, ricochete etc.).
##
## Regras (HTML):
##   - nasce na borda do corpo de quem atira, apontado para o alvo;
##   - persegue o alvo travado enquanto ele for um alvo válido (vivo, inimigo);
##   - acerta o alvo quando chega a (raio do alvo + 6), ou QUALQUER inimigo no caminho a (raio + 5);
##   - some depois de 2,6 s ou ao sair do mundo (com 40 de folga).

## Velocidades por tipo (HTML: PROJ_STYLE[kind].speed).
const SPEEDS := {&"orb": 340.0, &"arcanesword": 520.0}
const LIFE := 2.6
const TARGET_HIT_SLACK := 6.0
const PATH_HIT_SLACK := 5.0
const OUT_MARGIN := 40.0

var id: int
var kind: StringName
var owner: CombatUnit
var team: CombatUnit.Team
var target: CombatUnit
var position: Vector2
var direction: float
var speed: float
var damage: float
var life := LIFE
## Lâmina da Sentinela: índice da lâmina (0/1) que partiu; -1 = não é lâmina.
var sword_index := -1


func _init(p_id: int, p_kind: StringName, p_owner: CombatUnit, p_target: CombatUnit, p_damage: float) -> void:
	id = p_id
	kind = p_kind
	owner = p_owner
	team = p_owner.team
	target = p_target
	damage = p_damage
	speed = SPEEDS.get(p_kind, 340.0)
	direction = (p_target.position - p_owner.position).angle()
	position = p_owner.position + Vector2.from_angle(direction) * p_owner.radius


func is_sword() -> bool:
	return sword_index >= 0


## Alvo que ainda pode ser perseguido/atingido por este projétil.
func can_hit(unit: CombatUnit) -> bool:
	return unit != null and unit.team != team and unit.is_valid_target()
