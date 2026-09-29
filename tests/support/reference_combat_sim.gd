class_name ReferenceCombatSim
extends CombatSim
## SÓ TESTES. Cópia CONGELADA da CombatSim anterior à 1ª rodada de otimização (commit 77ba8b9):
## busca de alvo varrendo a lista inteira a cada passo, sem listas de vivos nem cache.
## Os testes de paridade rodam a mesma luta aqui e na CombatSim otimizada e exigem resultado
## idêntico (posições, HP, alvos, recargas, projéteis e eventos). Não otimizar este arquivo.


func step(dt: float) -> void:
	time += dt
	_tick_paladins(dt)
	for unit in units:
		if unit.is_alive():
			_update_unit(unit, dt)
	_update_projectiles(dt)


func nearest_foe(unit: CombatUnit) -> CombatUnit:
	var forced := taunt_target(unit)
	if forced:
		return forced
	var best: CombatUnit = null
	var best_dist := INF
	for other in units:
		if other == unit or not unit.is_enemy_of(other) or not other.is_valid_target():
			continue
		var d := unit.position.distance_to(other.position)
		if d < best_dist:
			best_dist = d
			best = other
	return best


func taunt_target(unit: CombatUnit) -> CombatUnit:
	var p := unit.taunted_by
	if unit.taunt_t > 0.0 and p and p.is_valid_target() and p.team != unit.team and p in units:
		return p
	if p:
		_clear_taunt(unit)
	return null


## Inimigos vivos na ordem da lista (o que os laços antigos das habilidades percorriam).
func foes_alive(unit: CombatUnit) -> Array[CombatUnit]:
	var out: Array[CombatUnit] = []
	for v in units:
		if v.is_valid_target() and unit.is_enemy_of(v):
			out.append(v)
	return out


func alive_count(team: CombatUnit.Team) -> int:
	var count := 0
	for unit in units:
		if unit.team == team and unit.is_alive():
			count += 1
	return count


func _update_unit(unit: CombatUnit, dt: float) -> void:
	unit.cooldown = maxf(0.0, unit.cooldown - dt)
	if unit.swords:
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
		unit.position = _clamp_to_battlefield(unit.position + to_target / dist * advance, unit.radius)
		return

	unit.state = CombatUnit.State.ATTACKING
	if unit.cooldown <= 0.0:
		_attack(unit, unit.target)


func _apply_damage(attacker: CombatUnit, target: CombatUnit, amount: float) -> void:
	if target.paladin and target.is_alive():
		var reduced := target.paladin.shield_damage(target, amount)
		if reduced < amount:
			paladin_shield_blocked.emit(target, amount - reduced)
		amount = reduced
	var applied := target.take_damage(amount)
	unit_attacked.emit(attacker, target, applied)
	if not target.is_alive():
		for v in units:
			if v.taunted_by == target:
				_clear_taunt(v)
		unit_died.emit(target)


func _tick_paladins(dt: float) -> void:
	for u in units:
		u.taunt_t = maxf(0.0, u.taunt_t - dt)
		taunt_target(u)
		if u.paladin and u.paladin.tick(u, self, dt):
			paladin_shield_raised.emit(u)
	for u in units:
		if u.paladin == null:
			continue
		var foes := u.paladin.try_taunt(u, self)
		if not foes.is_empty():
			paladin_taunted.emit(u, foes)


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
			for unit in units:
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
