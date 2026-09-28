class_name SentinelSwords
extends RefCounted
## Habilidade da Sentinela Arcana: duas lâminas pairam sobre a unidade. Quem chega perto
## leva uma, depois a outra; cada lâmina volta sozinha depois da recarga.
## Porta fiel de SENTINEL_CONFIG / updateArcaneSwords / launchSword do HTML.
##
## Dado puro: a CombatSim chama update() a cada passo de uma unidade viva que tem a habilidade.
## O visual só LÊ `blades` (recarga e antecipação de cada lâmina).

# --- SENTINEL_CONFIG (HTML) --------------------------------------------------------------
const MAX_SWORDS := 2
const COOLDOWN := 10.0           # s para cada lâmina voltar
const TRIGGER_RANGE := 115.0     # distância em que ela se sente ameaçada
const REACTION_SLOW := 0.55      # demora para reagir a quem se aproxima devagar
const REACTION_FAST := 0.08      # e a quem vem em cima
const CLOSING_FAST := 55.0       # px/s de aproximação considerados "agressivo"
const GAP_BETWEEN := 0.35        # intervalo entre a primeira e a segunda lâmina
const DAMAGE_MULTIPLIER := 1.0   # dano = ataque básico × isto
const HOVER := 1.9               # altura das lâminas acima do centro (em raios)
const SPREAD := 0.82             # afastamento lateral (em raios)
const WINDUP := 0.10             # antecipação: a lâmina recua antes de partir


class Blade:
	## Recarga restante; 0 = pairando, pronta.
	var cooldown := 0.0
	## > 0 enquanto a lâmina antecipa o disparo (tempo restante até partir).
	var windup := 0.0

	func is_ready() -> bool:
		return cooldown <= 0.0


var blades: Array[Blade] = []
## Estado da ameaça (HTML: swordThreat, swordLastDist, swordTimer, swordGap).
var threat_id := -1
var last_dist := 0.0
var timer := 0.0                 # <= 0 = sem contagem (HTML: null ou 0)
var gap := 0.0


func _init() -> void:
	for i in MAX_SWORDS:
		blades.append(Blade.new())


func ready_count() -> int:
	return blades.filter(func(b: Blade) -> bool: return b.is_ready()).size()


## Ponto de partida da lâmina `index` no mundo (HTML: swordAnchor, sem a flutuação visual).
static func anchor(unit: CombatUnit, index: int) -> Vector2:
	var side := -1.0 if index == 0 else 1.0
	return unit.position + Vector2(side * unit.radius * SPREAD, -unit.radius * HOVER)


## Um passo da habilidade. Devolve [índice, alvo] se uma lâmina deve partir agora, senão [].
func update(unit: CombatUnit, sim: CombatSim, dt: float) -> Array:
	for blade in blades:
		if blade.cooldown > 0.0:
			blade.cooldown = maxf(0.0, blade.cooldown - dt)

	var foe := sim.nearest_foe(unit)
	var dist := unit.position.distance_to(foe.position) if foe else INF
	if foe == null or dist > TRIGGER_RANGE:
		threat_id = -1
		timer = 0.0
		gap = 0.0
		for blade in blades:
			blade.windup = 0.0   # (só visual) ninguém ameaçando: a lâmina volta ao lugar
		return []

	# quanto mais rápido ele fecha a distância, mais rápido a lâmina sai
	var previous := last_dist if threat_id == foe.id else dist
	var closing := maxf(0.0, (previous - dist) / maxf(dt, 1.0 / 120.0))
	threat_id = foe.id
	last_dist = dist
	if timer <= 0.0:
		var aggressive := clampf(closing / CLOSING_FAST, 0.0, 1.0)
		timer = REACTION_SLOW + (REACTION_FAST - REACTION_SLOW) * aggressive
	if gap > 0.0:   # uma de cada vez
		gap -= dt
		return []
	timer -= dt
	var index := -1
	for i in blades.size():
		if blades[i].is_ready():
			index = i
			break
	if index < 0:
		return []
	if timer <= WINDUP and timer > 0.0:   # recua antes
		blades[index].windup = timer
		return []
	if timer > 0.0:
		return []
	blades[index].cooldown = COOLDOWN
	blades[index].windup = 0.0
	timer = 0.0
	gap = GAP_BETWEEN
	return [index, foe]
