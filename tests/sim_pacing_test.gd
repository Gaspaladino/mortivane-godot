extends SceneTree
## Etapa 6 da otimização: limite de passos de recuperação por quadro (Battle).
##   - quadros normais (60 FPS): 2 passos por quadro, sem perder tempo de jogo;
##   - quadros de até 33 ms (30 FPS): tempo de jogo = tempo real;
##   - quadros lentos: nunca mais que MAX_SIM_STEPS_PER_FRAME passos num quadro; a sobra curta é
##     recuperada depois; a longa é descartada (câmera lenta), sem acelerar o jogo;
##   - o resultado da luta é IDÊNTICO ao da simulação passo a passo, qualquer que seja o ritmo.

var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await _test_pacing()
	await _test_same_outcome()
	print("sim_pacing_test: %s" % ("OK" if _failures == 0 else "%d falha(s)" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("  FALHOU: " + msg)


func _arena() -> Node:
	var arena: Node = load("res://scenes/arena/arena.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	var battle: Battle = arena.get_node("Battle")
	battle.set_process(false)   # o teste chama o _process com o dt que quiser
	return arena


func _test_pacing() -> void:
	var arena: Node = await _arena()
	var battle: Battle = arena.get_node("Battle")
	battle.spawn(UnitCatalog.get_def(&"warrior"), CombatUnit.Team.PLAYER, Vector2(300, 380))
	battle.spawn(UnitCatalog.get_def(&"warrior"), CombatUnit.Team.ENEMY, Vector2(700, 380))
	battle.start()
	var t0 := battle.sim.time
	for i in 60:
		battle._process(1.0 / 60.0)
		_check(battle.steps_last_frame <= 3, "60 FPS: 2 (ou 3 no arredondamento) passos por quadro")
	_check(absf(battle.sim.time - t0 - 1.0) < CombatSim.STEP * 1.01, "60 FPS: 1 s de jogo em 1 s real (%.4f)" % (battle.sim.time - t0))
	t0 = battle.sim.time
	for i in 30:
		battle._process(1.0 / 30.0)
	_check(absf(battle.sim.time - t0 - 1.0) < CombatSim.STEP * 1.01, "30 FPS: 1 s de jogo em 1 s real (%.4f)" % (battle.sim.time - t0))
	var max_steps := 0
	t0 = battle.sim.time
	for i in 10:
		battle._process(0.2)   # 5 FPS
		max_steps = maxi(max_steps, battle.steps_last_frame)
	_check(max_steps == Battle.MAX_SIM_STEPS_PER_FRAME, "5 FPS: no máximo %d passos por quadro (%d)" % [Battle.MAX_SIM_STEPS_PER_FRAME, max_steps])
	_check(battle.sim.time - t0 <= 10 * Battle.MAX_SIM_STEPS_PER_FRAME * CombatSim.STEP + 1e-6, "quadro lento: o jogo não acelera")
	_check(battle.dropped_time > 0.0, "quadro lento: o atraso longo é descartado (câmera lenta)")
	# um soluço isolado é recuperado nos quadros seguintes (antes, drena a dívida do trecho lento)
	for i in 5:
		battle._process(1.0 / 60.0)
	var dropped := battle.dropped_time
	t0 = battle.sim.time
	battle._process(0.045)   # 5,4 passos: faz 4, guarda o resto
	for i in 10:
		battle._process(1.0 / 60.0)
	_check(absf(battle.sim.time - t0 - (0.045 + 10.0 / 60.0)) < CombatSim.STEP * 1.01 and battle.dropped_time == dropped,
		"soluço de 45 ms: recuperado nos quadros seguintes, sem descarte")
	arena.queue_free()
	await process_frame


## A mesma luta em ritmos diferentes (60 FPS, 30 FPS, 5 FPS, soluços) termina exatamente igual.
func _test_same_outcome() -> void:
	var results := []
	for pattern in [[1.0 / 60.0], [1.0 / 30.0], [0.2], [1.0 / 60.0, 0.12, 1.0 / 60.0, 1.0 / 60.0, 0.05]]:
		var arena: Node = await _arena()
		var battle: Battle = arena.get_node("Battle")
		for i in 12:
			battle.spawn(UnitCatalog.get_def([&"warrior", &"arc_battlemage", &"sac_paladin"][i % 3]), CombatUnit.Team.PLAYER, SandboxController.slot_position(CombatUnit.Team.PLAYER, i))
			battle.spawn(UnitCatalog.get_def([&"arc_battlemage", &"warrior", &"sac_paladin"][i % 3]), CombatUnit.Team.ENEMY, SandboxController.slot_position(CombatUnit.Team.ENEMY, i))
		battle.start()
		var k := 0
		while not battle.sim.is_finished() and k < 20000:
			battle._process(pattern[k % pattern.size()])
			k += 1
		# encerra no mesmo passo lógico: completa até 60 s de jogo exatos
		var snap := []
		for u in battle.sim.units:
			snap.append([u.id, u.hp, u.is_alive(), u.position])   # estado IDLE/ATTACKING muda 1 passo depois do fim
		results.append([snappedf(battle.sim.time, 1e-9), battle.sim.alive_count(CombatUnit.Team.PLAYER), battle.sim.alive_count(CombatUnit.Team.ENEMY), snap])
		arena.queue_free()
		await process_frame
	var same := true
	for r in results:
		if r[1] != results[0][1] or r[2] != results[0][2] or r[3] != results[0][3] or absf(r[0] - results[0][0]) > 0.05:
			same = false
	_check(same, "mesmo vencedor, sobreviventes, HP e posições em 60/30/5 FPS e com soluços (%s)" % [results.map(func(r): return [r[0], r[1], r[2]])])
