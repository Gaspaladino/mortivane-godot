class_name UnitVisual
extends Node2D
## Base dos visuais de unidade: o "corpo" desenhado dentro de um UnitView.
## Só LÊ a CombatUnit; nunca altera a simulação. Não contém regra de combate.
##
## O UnitView cria o visual (script indicado em UnitDef.visual_script), chama setup() e,
## a cada quadro, update_visual(delta). Eventos puramente visuais chegam por:
##   on_attack_landed() — a CombatSim acabou de aplicar um golpe DESTA unidade
##   on_hit()           — esta unidade acabou de receber dano
## A morte é detectada pelo próprio visual (unit.state == DEAD).

var unit: CombatUnit
var def: UnitDef


func setup(p_unit: CombatUnit, p_def: UnitDef) -> void:
	unit = p_unit
	def = p_def


func update_visual(_delta: float) -> void:
	queue_redraw()


func on_attack_landed() -> void:
	pass


func on_hit() -> void:
	pass


## Altura (y local, negativa = acima do centro lógico) onde o UnitView põe a barra de HP.
func top_y() -> float:
	return -unit.radius - 9.0


## Área clicável, em coordenadas locais do UnitView.
func pick_rect() -> Rect2:
	var r := unit.radius
	return Rect2(-r, -r, 2.0 * r, 2.0 * r)


## Ponto do chão (local) sob a unidade: base do anel de seleção.
func ground_point() -> Vector2:
	return Vector2.ZERO
