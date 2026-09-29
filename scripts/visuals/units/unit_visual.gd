class_name UnitVisual
extends Node2D
## Base dos visuais de unidade: o "corpo" desenhado dentro de um UnitView.
## Só LÊ a CombatUnit; nunca altera a simulação. Não contém regra de combate.
##
## O UnitView cria o visual (cena de UnitDef.visual_scene ou script de UnitDef.visual_script), chama setup() e,
## a cada quadro, update_visual(delta). Eventos puramente visuais chegam por:
##   on_attack_performed()  — esta unidade executou o ataque básico (golpe desferido ou projétil
##                            disparado), no mesmo passo em que a CombatSim o executou
##   on_projectile_fired(p) — um projétil desta unidade nasceu (inclui as lâminas da Sentinela)
##   on_hit()               — esta unidade acabou de receber dano
##   on_ability_event(kind) — evento de habilidade desta unidade (ex.: Paladino: taunt, shield, block)
## A morte é detectada pelo próprio visual (unit.state == DEAD).

## Cores padrão de projétil (ProjectileView): {core, glow, dark, trim, shadow}.
const DEFAULT_PROJECTILE_STYLE := {
	core = Color(0.92, 0.96, 1.0), glow = Color(0.6, 0.85, 1.0), dark = Color(0.1, 0.15, 0.25),
	trim = Color(0.75, 0.8, 0.85), shadow = false,
}

var unit: CombatUnit
var def: UnitDef


func setup(p_unit: CombatUnit, p_def: UnitDef) -> void:
	unit = p_unit
	def = p_def


func update_visual(_delta: float) -> void:
	queue_redraw()


func on_attack_performed() -> void:
	pass


func on_projectile_fired(_projectile: CombatProjectile) -> void:
	pass


func on_hit() -> void:
	pass


func on_ability_event(_kind: StringName) -> void:
	pass


## De onde o projétil deve PARECER sair (local ao UnitView). O projétil real nasce onde a
## CombatSim manda; o ProjectileView só desenha a partida a partir daqui nos primeiros 0,12 s
## (mesma técnica do HTML: sentinelHand / necroMuzzle).
func muzzle_point(projectile: CombatProjectile) -> Vector2:
	return projectile.position - unit.position


## Cores do projétil desta unidade (usadas pelo ProjectileView).
func projectile_style(_projectile: CombatProjectile) -> Dictionary:
	return DEFAULT_PROJECTILE_STYLE


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


# --- Cadáver estático ------------------------------------------------------------------------
## Segundos desde que ESTE visual viu a morte (−1 = vivo, ou prévia da morte no Sandbox).
func death_elapsed() -> float:
	return -1.0


## Segundos depois da morte a partir dos quais nada mais muda no desenho: queda terminada, quique
## amortecido, escurecimento completo, armas no chão e efeitos acabados. INF = nunca assenta.
func corpse_settle_time() -> float:
	return INF


## Cadáver assentado: o UnitView para de atualizar e de redesenhar este visual (ver UnitView).
func is_settled_corpse() -> bool:
	var t := death_elapsed()
	return t >= 0.0 and t >= corpse_settle_time()
