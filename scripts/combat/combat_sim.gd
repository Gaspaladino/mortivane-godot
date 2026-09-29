class_name CombatSim
extends RefCounted
## Simulação mínima de combate: aquisição de alvo, movimento, ataque básico, dano e morte.
## Não depende de nós nem de desenho; roda igual em jogo e em teste headless.
##
## Regras (subconjunto do updateUnit do HTML, sem IA avançada):
##   1. Alvo = inimigo vivo mais próximo (distância centro a centro). Reavaliado a cada passo.
##   2. Fora do alcance → MOVING: anda em linha reta até o alvo.
##   3. No alcance → ATTACKING: para; ataca quando a recarga zera.
##   4. HP chega a 0 → DEAD: deixa de agir e deixa de ser alvo válido.
##   5. Sem inimigo vivo → IDLE.
##
## Extensões por unidade (só valem para quem as declara; o corpo a corpo não muda):
##   - ataque à distância (`unit.projectile`): o ataque dispara um CombatProjectile e o dano
##     acontece quando ele acerta (HTML: fireProjectile/updateProjectiles);
##   - lâminas da Sentinela (`unit.swords`): SentinelSwords.update a cada passo;
##   - provocação + Escudo Sagrado do Paladino (`unit.paladin`): PaladinTaunt, numa passada
##     antes das unidades (HTML: tickPaladinCombat antes de updateUnit); o provocado tem o
##     Paladino como alvo forçado (HTML: tauntTarget em nearestFoe) e o escudo reduz o dano.

## O ataque básico ACONTECEU (golpe desferido ou projétil disparado). Só para apresentação.
signal attack_performed(attacker: CombatUnit, target: CombatUnit)
## Um projétil nasceu / terminou (victim = null se expirou sem acertar). Só para apresentação.
signal projectile_fired(projectile: CombatProjectile)
signal projectile_ended(projectile: CombatProjectile, victim: CombatUnit)
## Dano aplicado (corpo a corpo, projétil ou lâmina); `attacker` = quem causou.
signal unit_attacked(attacker: CombatUnit, target: CombatUnit, amount: float)
signal unit_died(unit: CombatUnit)
## Paladino provocou `foes` / ergueu o Escudo Sagrado / o escudo absorveu dano. Só apresentação.
signal paladin_taunted(paladin: CombatUnit, foes: Array)
signal paladin_shield_raised(paladin: CombatUnit)
signal paladin_shield_blocked(paladin: CombatUnit, prevented: float)

## Passo fixo da batalha (HTML: BATTLE_STEP = 1/120 s).
const STEP := 1.0 / 120.0

## Ao se aproximar, a unidade para um pouco dentro do alcance (HTML, corpo a corpo:
## avança enquanto dist > range × 0,85). Evita oscilar exatamente na borda do alcance.
const APPROACH_SHARE := 0.85
## À distância (HTML: avança enquanto dist > range × 0,92).
const RANGED_APPROACH_SHARE := 0.92

## Primeira recarga sorteada entre 0 e 40% do intervalo (HTML: cd = rnd(0, d.cd × 0,4)).
const INITIAL_COOLDOWN_SHARE := 0.4

## Trava de segurança (HTML: MAX_PROJECTILES).
const MAX_PROJECTILES := 200

var units: Array[CombatUnit] = []
var projectiles: Array[CombatProjectile] = []
var time := 0.0
var _next_projectile_id := 1

var _rng := RandomNumberGenerator.new()
var _next_id := 1

## Unidades ATIVAS da simulação, por time (índice = CombatUnit.Team), na ordem de criação.
## Quem morre sai daqui na hora (_apply_damage); o cadáver continua em `units` (visual, contagem,
## Necromancia no futuro), mas não é mais varrido pela busca de alvo nem pelas habilidades.
## A ordem de criação é preservada: o desempate "primeiro da lista" continua o mesmo.
var _alive: Array = [[], []]
## Alguém morreu fora de _apply_damage (ex.: teste chamando take_damage direto): refaz as listas.
var _alive_dirty := false
## Conjunto de `units` (substitui a varredura `p in units` da provocação).
var _members := {}
## --- Cache da busca de alvo (etapa 4 da otimização; resultado IDÊNTICO — ver nearest_foe) ---
## unidade → [alvo, vizinhos, D_resto, deslocamento acumulado do time inimigo, odômetro da unidade],
## tudo no instante da última varredura. `vizinhos` = os TARGET_CACHE_NEAR inimigos mais próximos
## depois do alvo, cada um [unidade, distância, odômetro dela]; D_resto = distância do mais próximo
## entre os demais.
var _target_cache := {}
const TARGET_CACHE_NEAR := 3
## Odômetro de cada unidade (distância total que ela andou) e a última posição que a simulação deu a ela.
var _odometer := {}
var _known_pos := {}
## Por time: soma, passo a passo, do MAIOR deslocamento de uma unidade daquele time naquele passo
## (limite superior de quanto QUALQUER unidade do time andou desde um instante qualquer) e o maior
## deslocamento do passo em andamento.
var _team_move_acc: Array = [0.0, 0.0]
var _team_step_max: Array = [0.0, 0.0]
## Margem de segurança da comparação (unidades do mundo): só pula a busca com folga real.
const TARGET_CACHE_EPS := 1e-3

# --- Diagnóstico (contadores inteiros, custo desprezível; lidos pelo benchmark em tools/bench) ---
## Chamadas de nearest_foe (inclui as das lâminas da Sentinela e do escudo do Paladino).
var stat_target_queries := 0
## Quantas dessas fizeram uma varredura de candidatos (o resto saiu pela provocação ou pelo cache).
var stat_target_scans := 0
## Unidades examinadas nas varreduras.
var stat_candidates := 0


func _init(seed_value := 0) -> void:
	_rng.seed = seed_value


func add_unit(team: CombatUnit.Team, stats: Dictionary, position: Vector2) -> CombatUnit:
	var unit := CombatUnit.new(_next_id, team, stats, _clamp_to_battlefield(position, stats.r))
	_next_id += 1
	unit.cooldown = _rng.randf_range(0.0, unit.attack_interval * INITIAL_COOLDOWN_SHARE)
	units.append(unit)
	_members[unit] = true
	_odometer[unit] = 0.0
	_known_pos[unit] = unit.position
	_target_cache.clear()   # candidato novo: nenhuma garantia anterior vale mais
	if unit.is_alive():
		_alive[unit.team].append(unit)
	return unit


func step(dt: float) -> void:
	if _alive_dirty:
		_rebuild_alive()
	for t in 2:
		_team_move_acc[t] += _team_step_max[t]
		_team_step_max[t] = 0.0
	_check_external_moves()
	time += dt
	_tick_paladins(dt)
	for unit in units:
		if unit.is_alive():
			_update_unit(unit, dt)
	_update_projectiles(dt)


## Desfaz as referências entre unidades (alvo ↔ alvo formam ciclo de RefCounted).
## Chamar ao descartar a simulação.
func dispose() -> void:
	for unit in units:
		unit.target = null
		unit.taunted_by = null
	units.clear()
	projectiles.clear()
	_alive = [[], []]
	_members.clear()
	_target_cache.clear()
	_odometer.clear()
	_known_pos.clear()


## Inimigo vivo mais próximo; empate fica com o primeiro da lista.
## Provocado por um Paladino: o Paladino (HTML: nearestFoe → tauntTarget).
func nearest_foe(unit: CombatUnit) -> CombatUnit:
	stat_target_queries += 1
	var forced := taunt_target(unit)
	if forced:
		return forced
	# só os inimigos VIVOS (mortos saíram da lista); nenhum aliado, nenhum cadáver
	var foes: Array = _alive[1 - unit.team]
	if foes.is_empty():
		return null

	# Cache com GARANTIA (resultado idêntico à varredura completa):
	# na última varredura guardamos o alvo, os 3 inimigos vivos seguintes (distância e odômetro de
	# cada um) e D_resto, a distância do mais próximo entre todos os outros. Desde então esta unidade
	# andou `a` (odômetro); cada vizinho i andou `b_i` (odômetro dele); e nenhum inimigo andou mais
	# que `b` (soma dos maiores deslocamentos do time inimigo em cada passo, incluindo o passo em
	# andamento). Então, agora: vizinho i está a pelo menos d_i − a − b_i, e qualquer outro a pelo
	# menos D_resto − a − b. Se o alvo guardado está mais perto que todos esses limites (com folga),
	# ele continua sendo ESTRITAMENTE o mais próximo: a varredura daria o mesmo alvo, inclusive no
	# desempate. No corpo a corpo, quem ataca fica parado e o alvo se mantém até morrer. Se o alvo
	# morreu ou a folga acabou, varre de novo. Mortes só tiram candidatos (nunca criam um mais
	# próximo); unidade nova ou teleporte limpam o cache.
	var cache: Array = _target_cache.get(unit, [])
	var enemy := 1 - unit.team
	if not cache.is_empty():
		var cached: CombatUnit = cache[0]
		if cached.is_valid_target():
			var moved_self: float = float(_odometer[unit]) - float(cache[4])
			var moved_foes: float = float(_team_move_acc[enemy]) + float(_team_step_max[enemy]) - float(cache[3])
			var limit: float = float(cache[2]) - moved_self - moved_foes
			for nb: Array in cache[1]:
				var other: CombatUnit = nb[0]
				if other.is_valid_target():
					limit = minf(limit, float(nb[1]) - moved_self - (float(_odometer[other]) - float(nb[2])))
			if unit.position.distance_to(cached.position) < limit - TARGET_CACHE_EPS:
				return cached

	stat_target_scans += 1
	stat_candidates += foes.size()
	var best: CombatUnit = null
	var best_dist := INF
	# os TARGET_CACHE_NEAR + 1 seguintes, em ordem de distância: [[unidade, distância], ...]
	var near: Array = []
	for other: CombatUnit in foes:
		if not other.is_valid_target():   # morto por fora de _apply_damage: ignora e refaz as listas
			_alive_dirty = true
			continue
		var d := unit.position.distance_to(other.position)
		if d < best_dist:
			if best:
				_keep_near(near, best, best_dist)
			best_dist = d
			best = other
		else:
			_keep_near(near, other, d)
	if best:
		var rest := INF
		if near.size() > TARGET_CACHE_NEAR:
			rest = near[TARGET_CACHE_NEAR][1]
			near.resize(TARGET_CACHE_NEAR)
		for nb: Array in near:
			nb.append(float(_odometer[nb[0]]))
		_target_cache[unit] = [best, near, rest, float(_team_move_acc[enemy]), float(_odometer[unit])]
	return best


## Mantém `near` com as TARGET_CACHE_NEAR + 1 menores distâncias (inserção ordenada, lista curta).
static func _keep_near(near: Array, u: CombatUnit, d: float) -> void:
	var n := near.size()
	if n > TARGET_CACHE_NEAR and d >= near[n - 1][1]:
		return
	var i := n
	while i > 0 and near[i - 1][1] > d:
		i -= 1
	near.insert(i, [u, d])
	if near.size() > TARGET_CACHE_NEAR + 1:
		near.resize(TARGET_CACHE_NEAR + 1)


## Toda mudança de posição feita pela simulação passa por aqui (odômetro + limite do time).
func _move_unit(unit: CombatUnit, to: Vector2) -> void:
	var d := unit.position.distance_to(to)
	unit.position = to
	_known_pos[unit] = to
	_odometer[unit] = float(_odometer[unit]) + d
	if d > _team_step_max[unit.team]:
		_team_step_max[unit.team] = d


## Alguém mudou a posição de uma unidade por fora da simulação (teste, editor): nenhuma garantia
## de distância vale mais — limpa o cache (a próxima consulta varre de novo).
func _check_external_moves() -> void:
	for u in units:
		if u.position != _known_pos.get(u, u.position):
			_known_pos[u] = u.position
			_target_cache.clear()


## HTML: tauntTarget — o Paladino que provocou esta unidade, se a provocação ainda vale.
func taunt_target(unit: CombatUnit) -> CombatUnit:
	var p := unit.taunted_by
	if unit.taunt_t > 0.0 and p and p.is_valid_target() and p.team != unit.team and _members.has(p):
		return p
	if p:
		_clear_taunt(unit)
	return null


## Inimigos vivos de `unit`, na ordem de criação (usado pelas habilidades). É a lista interna:
## só leitura, e quem percorre ainda confere is_valid_target() (mortes feitas por fora).
func foes_alive(unit: CombatUnit) -> Array:
	if _alive_dirty:
		_rebuild_alive()
	return _alive[1 - unit.team]


func alive_count(team: CombatUnit.Team) -> int:
	var count := 0
	for unit: CombatUnit in _alive[team]:
		if unit.is_alive():
			count += 1
	return count


## Refaz as listas de ativos a partir de `units` (mesma ordem). Só quando alguém morreu por fora.
func _rebuild_alive() -> void:
	_alive = [[], []]
	for u in units:
		if u.is_alive():
			_alive[u.team].append(u)
	_alive_dirty = false
	_target_cache.clear()   # alguém morreu ou voltou por fora: refaz as garantias


## A luta acabou quando um dos lados não tem mais ninguém vivo.
func is_finished() -> bool:
	return alive_count(CombatUnit.Team.PLAYER) == 0 or alive_count(CombatUnit.Team.ENEMY) == 0


func _update_unit(unit: CombatUnit, dt: float) -> void:
	unit.cooldown = maxf(0.0, unit.cooldown - dt)
	if unit.swords:   # lâminas pairando (HTML: updateArcaneSwords, antes do alvo)
		var launch := unit.swords.update(unit, self, dt)
		if not launch.is_empty():
			_launch_sword(unit, launch[0], launch[1])

	unit.target = nearest_foe(unit)
	if unit.target == null:
		unit.state = CombatUnit.State.IDLE
		return

	var to_target := unit.target.position - unit.position
	var dist := to_target.length()
	if dist > unit.attack_range:
		unit.state = CombatUnit.State.MOVING
		var advance := minf(unit.move_speed * dt, dist - unit.attack_range * unit.approach_share)
		_move_unit(unit, _clamp_to_battlefield(unit.position + to_target / dist * advance, unit.radius))
		return

	unit.state = CombatUnit.State.ATTACKING
	if unit.cooldown <= 0.0:
		_attack(unit, unit.target)


func _attack(attacker: CombatUnit, target: CombatUnit) -> void:
	attacker.cooldown = attacker.attack_interval
	attack_performed.emit(attacker, target)
	if attacker.is_ranged():
		_fire(attacker.projectile, attacker, target, attacker.damage)
		return
	_apply_damage(attacker, target, attacker.damage)


func _apply_damage(attacker: CombatUnit, target: CombatUnit, amount: float) -> void:
	if target.paladin and target.is_alive():   # HTML: damage → paladinShieldDamage
		var reduced := target.paladin.shield_damage(target, amount)
		if reduced < amount:
			paladin_shield_blocked.emit(target, amount - reduced)
		amount = reduced
	var was_alive := target.is_alive()
	var applied := target.take_damage(amount)
	unit_attacked.emit(attacker, target, applied)
	if not target.is_alive():
		if was_alive:
			_alive[target.team].erase(target)   # sai das estruturas ativas NA HORA
		for v: CombatUnit in _alive[1 - target.team]:   # HTML: killUnit → clearTaunt (só inimigos vivos podem estar provocados por ele)
			if v.taunted_by == target:
				_clear_taunt(v)
		unit_died.emit(target)


## HTML: tickPaladinCombat — uma passada antes de qualquer unidade agir (independe da ordem).
func _tick_paladins(dt: float) -> void:
	for u in units:
		if not u.is_alive():   # morto: taunt_t = 0, sem provocador e Paladino já resetado (die)
			continue
		u.taunt_t = maxf(0.0, u.taunt_t - dt)
		taunt_target(u)
		if u.paladin and u.paladin.tick(u, self, dt):
			paladin_shield_raised.emit(u)
	for u in units:
		if u.paladin == null or not u.is_alive():
			continue
		var foes := u.paladin.try_taunt(u, self)
		if not foes.is_empty():
			paladin_taunted.emit(u, foes)


## HTML: clearTaunt.
func _clear_taunt(u: CombatUnit) -> void:
	if u.taunted_by and u.target == u.taunted_by:
		u.target = null
	u.taunted_by = null
	u.taunt_t = 0.0


func _fire(kind: StringName, owner: CombatUnit, target: CombatUnit, damage: float) -> CombatProjectile:
	if projectiles.size() > MAX_PROJECTILES:
		return null
	var p := CombatProjectile.new(_next_projectile_id, kind, owner, target, damage)
	_next_projectile_id += 1
	projectiles.append(p)
	projectile_fired.emit(p)
	return p


## A MESMA lâmina que pairava parte da âncora, já apontada para o alvo (HTML: launchSword).
func _launch_sword(unit: CombatUnit, index: int, target: CombatUnit) -> void:
	var from := SentinelSwords.anchor(unit, index)
	if projectiles.size() > MAX_PROJECTILES:
		return
	var p := CombatProjectile.new(_next_projectile_id, &"arcanesword", unit, target,
		unit.damage * SentinelSwords.DAMAGE_MULTIPLIER)
	_next_projectile_id += 1
	p.position = from
	p.direction = (target.position - from).angle()
	p.sword_index = index
	projectiles.append(p)
	projectile_fired.emit(p)


## HTML: updateProjectiles — persegue o alvo travado; acerta o alvo ou quem estiver no caminho.
func _update_projectiles(dt: float) -> void:
	var i := projectiles.size() - 1
	while i >= 0:
		var p := projectiles[i]
		p.life -= dt
		var tgt: CombatUnit = p.target if p.can_hit(p.target) else null
		if tgt:
			p.direction = (tgt.position - p.position).angle()
		p.position += Vector2.from_angle(p.direction) * p.speed * dt
		var victim: CombatUnit = null
		if tgt and p.position.distance_to(tgt.position) < tgt.radius + CombatProjectile.TARGET_HIT_SLACK:
			victim = tgt
		else:
			for unit: CombatUnit in _alive[1 - p.team]:   # can_hit = vivo e do outro time
				if p.can_hit(unit) and p.position.distance_to(unit.position) < unit.radius + CombatProjectile.PATH_HIT_SLACK:
					victim = unit
					break
		if victim:
			projectiles.remove_at(i)
			_apply_damage(p.owner, victim, p.damage)
			projectile_ended.emit(p, victim)
		elif p.life <= 0.0 or not Rect2(Vector2.ZERO, WorldConfig.SIZE).grow(CombatProjectile.OUT_MARGIN).has_point(p.position):
			projectiles.remove_at(i)
			projectile_ended.emit(p, null)
		i -= 1


## Mantém o corpo inteiro dentro da área jogável (HTML: clampPointToBattlefield).
static func _clamp_to_battlefield(point: Vector2, radius: float) -> Vector2:
	var r := WorldConfig.BATTLEFIELD_RECT
	return Vector2(
		clampf(point.x, r.position.x + radius, r.end.x - radius),
		clampf(point.y, r.position.y + radius, r.end.y - radius))
