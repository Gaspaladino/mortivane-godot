class_name PaladinTaunt
extends RefCounted
## Habilidade do Paladino (HTML: ability 'paladin_taunt_shield'): provoca os inimigos próximos
## e, 1 s depois, ergue o Escudo Sagrado, que reduz o dano recebido.
## Porta fiel de PALADIN_CONFIG / tickPaladinCombat / paladinShieldDamage / lockPaladinShieldFacing.
##
## Dado puro: a CombatSim chama pre_step() para todas as unidades ANTES de atualizar qualquer
## uma (HTML: tickPaladinCombat roda antes de updateUnit) e shield_damage() no dano.
## O visual só LÊ os campos abaixo.

# --- PALADIN_CONFIG (HTML) ---------------------------------------------------------------
const TAUNT_RADIUS := 115.0      # provoca inimigos até esta distância
const TAUNT_DURATION := 2.5      # s em que o inimigo fica preso ao Paladino
const SHIELD_DELAY := 1.0        # s entre a provocação e o escudo
const SHIELD_DURATION := 1.5     # s de escudo
const SHIELD_DAMAGE_REDUCTION := 0.75
const COOLDOWN := 15.0
## Só apresentação (HTML: PALADIN_SHIELD_VISUAL.impact): duração do "tranco" quando o escudo absorve.
const SHIELD_IMPACT := 0.16
const EPS := 1e-8

## Recarga da provocação (HTML: abCd). Começa em 0: provoca assim que alguém chega perto.
var cooldown := 0.0
## Contagem até o escudo (HTML: holyDelay); < 0 = nenhuma (null no HTML).
var delay := -1.0
## Escudo ativo restante (HTML: holyShieldT).
var shield_t := 0.0
## Só apresentação (HTML: holyShieldHit): > 0 logo depois de o escudo absorver dano.
var shield_hit := 0.0
## Direção do escudo, travada na ativação (HTML: holyShieldFacing).
var facing := Vector2.ZERO


func is_preparing() -> bool:
	return delay >= 0.0


func is_shielded() -> bool:
	return shield_t > EPS


## 0..1: quanto da espera até o escudo já passou (HTML: prepare, no desenho).
func prepare_progress() -> float:
	return clampf(1.0 - delay / SHIELD_DELAY, 0.0, 1.0) if delay >= 0.0 else 0.0


## HTML: resetPaladinCombat (sem o clearTaunt, que a CombatSim faz).
func reset() -> void:
	cooldown = 0.0
	delay = -1.0
	shield_t = 0.0
	shield_hit = 0.0
	facing = Vector2.ZERO


## Primeira passada do HTML para ESTE paladino: timers e ativação do escudo.
## Devolve true se o escudo acabou de subir.
func tick(unit: CombatUnit, sim: CombatSim, dt: float) -> bool:
	if not unit.is_alive():
		delay = -1.0
		shield_t = 0.0
		return false
	cooldown = maxf(0.0, cooldown - dt)
	shield_t = maxf(0.0, shield_t - dt)
	shield_hit = maxf(0.0, shield_hit - dt)
	if delay >= 0.0:
		delay -= dt
		if delay <= EPS:
			shield_t = maxf(0.0, SHIELD_DURATION + minf(0.0, delay))
			delay = -1.0
			_lock_facing(unit, sim)
			return true
	return false


## Segunda passada do HTML: provoca se estiver pronto e houver inimigos no raio.
## Devolve os inimigos provocados (vazio = nada aconteceu).
func try_taunt(unit: CombatUnit, sim: CombatSim) -> Array[CombatUnit]:
	var foes: Array[CombatUnit] = []
	if not unit.is_alive() or cooldown > EPS:
		return foes
	for v in sim.foes_alive(unit):
		if unit.position.distance_to(v.position) <= TAUNT_RADIUS:
			foes.append(v)
	if foes.is_empty():
		return foes
	cooldown = COOLDOWN
	delay = SHIELD_DELAY
	for v in foes:
		v.taunted_by = unit
		v.taunt_t = TAUNT_DURATION
		v.target = unit
	return foes


## HTML: paladinShieldDamage — com o escudo ativo, reduz o dano em 75%.
func shield_damage(unit: CombatUnit, amount: float) -> float:
	if not unit.is_alive() or not is_shielded():
		return amount
	shield_hit = SHIELD_IMPACT
	return amount - amount * SHIELD_DAMAGE_REDUCTION


## HTML: lockPaladinShieldFacing — alvo atual, senão um provocado, senão o inimigo mais próximo.
func _lock_facing(unit: CombatUnit, sim: CombatSim) -> void:
	var target: CombatUnit = null
	if unit.target and unit.target.is_valid_target() and unit.is_enemy_of(unit.target):
		target = unit.target
	if target == null:
		for v in sim.foes_alive(unit):
			if v.taunted_by == unit:
				target = v
				break
	if target == null:
		target = sim.nearest_foe(unit)
	var d := (target.position - unit.position) if target else Vector2(1.0 if unit.team == CombatUnit.Team.PLAYER else -1.0, 0.0)
	facing = d / maxf(d.length(), 1e-6) if d.length() > 0.0 else Vector2(1.0 if unit.team == CombatUnit.Team.PLAYER else -1.0, 0.0)
