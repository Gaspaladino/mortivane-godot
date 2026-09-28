extends SceneTree
## Teste headless do núcleo de combate (sem janela, sem cena).
## Rodar a partir da raiz do projeto:
##   godot --headless -s res://tests/combat_test.gd
## Sai com código 0 se tudo passar, 1 se alguma verificação falhar.

const MAX_SECONDS := 60.0

var _failures := 0


func _initialize() -> void:
	_test_full_fight()
	_test_dead_unit_is_not_a_target()
	_test_damage_clamps_at_zero()
	print("combat_test: %s" % ("OK" if _failures == 0 else "%d falha(s)" % _failures))
	quit(1 if _failures > 0 else 0)


func _test_full_fight() -> void:
	var sim := Battle.build_test_sim(97)
	var ally := sim.units[0]
	var enemy := sim.units[1]
	_check(ally.team == CombatUnit.Team.PLAYER and ally.position.x < WorldConfig.DEPLOY_X, "aliado começa à esquerda")
	_check(enemy.team == CombatUnit.Team.ENEMY and enemy.position.x > WorldConfig.DEPLOY_X, "inimigo começa à direita")

	sim.step(CombatSim.STEP)
	_check(ally.target == enemy and enemy.target == ally, "cada um mira o outro")
	_check(ally.state == CombatUnit.State.MOVING and enemy.state == CombatUnit.State.MOVING, "ambos começam MOVING")

	var hits := [0]   # lambdas copiam variáveis locais; um Array é compartilhado
	var last_hp := {ally.id: ally.hp, enemy.id: enemy.hp}
	sim.unit_attacked.connect(func(attacker: CombatUnit, target: CombatUnit, amount: float) -> void:
		hits[0] += 1
		var dist := attacker.position.distance_to(target.position)
		_check(dist <= attacker.attack_range + 0.001, "ataque só dentro do alcance (dist %.2f)" % dist)
		_check(attacker.state == CombatUnit.State.ATTACKING, "quem ataca está ATTACKING")
		var expected := minf(attacker.damage, last_hp[target.id])
		_check(is_equal_approx(amount, expected), "dano aplicado = %.1f (esperado %.1f)" % [amount, expected])
		_check(is_equal_approx(target.hp, last_hp[target.id] - expected), "HP reduzido corretamente")
		last_hp[target.id] = target.hp)

	var saw_attacking := false
	while not sim.is_finished() and sim.time < MAX_SECONDS:
		var before := ally.position
		var was_attacking := ally.state == CombatUnit.State.ATTACKING
		sim.step(CombatSim.STEP)
		if was_attacking and ally.state == CombatUnit.State.ATTACKING:
			saw_attacking = true
			_check(ally.position == before, "ATTACKING não se move")

	_check(sim.is_finished(), "a luta termina em até %d s (durou %.2f s)" % [MAX_SECONDS, sim.time])
	_check(saw_attacking and hits[0] > 0, "houve ataques")
	var dead := ally if not ally.is_alive() else enemy
	var survivor := enemy if dead == ally else ally
	_check(dead.hp == 0.0 and dead.state == CombatUnit.State.DEAD, "morto tem HP 0 e estado DEAD")
	_check(dead.target == null, "morto não tem alvo")
	sim.step(CombatSim.STEP)
	_check(survivor.target == null and survivor.state == CombatUnit.State.IDLE, "sobrevivente fica sem alvo (IDLE)")
	print("  luta: %s venceu com %.0f/%.0f HP em %.2f s, %d golpes" % [survivor.label(), survivor.hp, survivor.max_hp, sim.time, hits[0]])
	sim.dispose()


func _test_dead_unit_is_not_a_target() -> void:
	var sim := CombatSim.new(1)
	var ally := sim.add_unit(CombatUnit.Team.PLAYER, Battle.ALLY_STATS, Vector2(200, 380))
	var near := sim.add_unit(CombatUnit.Team.ENEMY, Battle.ENEMY_STATS, Vector2(300, 380))
	var far := sim.add_unit(CombatUnit.Team.ENEMY, Battle.ENEMY_STATS, Vector2(700, 380))
	_check(sim.nearest_foe(ally) == near, "alvo = inimigo mais próximo")
	near.take_damage(near.max_hp)
	_check(not near.is_valid_target(), "morto não é alvo válido")
	_check(sim.nearest_foe(ally) == far, "com o mais próximo morto, mira o seguinte")
	var near_pos := near.position
	sim.step(CombatSim.STEP)
	_check(ally.target == far and near.position == near_pos and near.target == null, "morto não age nem é mirado")
	sim.dispose()


func _test_damage_clamps_at_zero() -> void:
	var unit := CombatUnit.new(1, CombatUnit.Team.ENEMY, Battle.ENEMY_STATS, Vector2(600, 380))
	_check(is_equal_approx(unit.take_damage(25.0), 25.0) and is_equal_approx(unit.hp, 45.0), "dano parcial")
	_check(is_equal_approx(unit.take_damage(100.0), 45.0), "dano excedente limitado ao HP restante")
	_check(unit.hp == 0.0 and not unit.is_alive(), "HP 0 → morto")
	_check(unit.take_damage(10.0) == 0.0 and unit.hp == 0.0, "morto não recebe dano")


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures += 1
		printerr("  FALHOU: ", what)
