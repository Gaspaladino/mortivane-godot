extends SceneTree
## Painel de desempenho do Sandbox (F6, ferramenta de debug).
##   - nasce desligado e sem processar; F6 (tecla física real) liga e desliga;
##   - mostra FPS, quadro, aliados/inimigos, vivos/cadáveres/total, draw calls (N/A sem render),
##     nós, simulação, busca de alvo e update visual, com os números da batalha real;
##   - não bloqueia cliques (mouse_filter IGNORE) e fica acima da UI do Sandbox;
##   - o estado é lembrado ao sair e voltar ao Sandbox;
##   - não altera o combate: a mesma luta termina igual com o painel ligado e desligado.

var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.show_sandbox()
	await process_frame
	var sb: SandboxController = main.current_screen
	var ov: PerfOverlay = sb.perf_overlay
	_check(ov != null and not ov.is_shown() and not ov.is_processing(), "nasce desligado e sem processar")
	await _press_f6()
	_check(ov.is_shown() and ov.is_processing() and UnitView.profiling, "F6 liga")
	var panel := ov.get_node("Panel") as Control
	_check(panel.mouse_filter == Control.MOUSE_FILTER_IGNORE and ov.layer > 50, "não bloqueia cliques e fica acima da UI (camada %d)" % ov.layer)
	for i in 10:
		sb.add_unit(UnitCatalog.get_def(&"warrior"), CombatUnit.Team.PLAYER)
		sb.add_unit(UnitCatalog.get_def(&"arc_battlemage"), CombatUnit.Team.ENEMY)
	sb.start_combat()
	for i in 90:
		await process_frame
	var text: String = (ov.get_node("Panel").get_child(0) as Label).text
	var sim := sb.arena.battle.sim
	for key in ["FPS:", "Quadro:", "Aliados:", "Inimigos:", "Vivos:", "Cadáveres:", "Total: 20", "Draw calls: N/A", "Objetos:", "Nós:", "Sim:", "Alvo/s:", "Visual (update):"]:
		_check(text.contains(key), "mostra '%s'" % key)
	_check(text.contains("Total: %d" % sim.units.size()), "total da batalha real")
	_check(not text.contains("Sim: parada"), "tempo da simulação com o combate rodando")
	await _press_f6()
	_check(not ov.is_shown() and not ov.is_processing() and not UnitView.profiling, "F6 desliga (sem processar nem medir)")
	await _press_f6()
	main.show_menu()
	await process_frame
	main.show_sandbox()
	await process_frame
	_check((main.current_screen as SandboxController).perf_overlay.is_shown(), "estado lembrado ao voltar ao Sandbox")
	await _press_f6()
	main.queue_free()
	await process_frame
	await _test_same_fight()
	print("perf_overlay_test: %s" % ("OK" if _failures == 0 else "%d falha(s)" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("  FALHOU: " + msg)


func _press_f6() -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F6
		ev.keycode = KEY_F6
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame


## A mesma luta (passos fixos) com o painel ligado e desligado: mesmo resultado.
func _test_same_fight() -> void:
	var results := []
	for shown in [false, true]:
		var main: Node = load("res://scenes/main/main.tscn").instantiate()
		root.add_child(main)
		await process_frame
		main.show_sandbox()
		await process_frame
		var sb: SandboxController = main.current_screen
		sb.perf_overlay.set_shown(shown)
		for i in 8:
			sb.add_unit(UnitCatalog.get_def([&"warrior", &"sac_paladin"][i % 2]), CombatUnit.Team.PLAYER)
			sb.add_unit(UnitCatalog.get_def([&"arc_battlemage", &"warrior"][i % 2]), CombatUnit.Team.ENEMY)
		sb.start_combat()
		var battle := sb.arena.battle
		battle.set_process(false)
		for k in 3000:
			battle._process(1.0 / 60.0)
			if k % 30 == 0:
				await process_frame   # deixa o painel e os visuais rodarem
		var snap := []
		for u in battle.sim.units:
			snap.append([u.id, u.hp, u.position, u.state])
		results.append(snap)
		sb.perf_overlay.set_shown(false)
		main.queue_free()
		await process_frame
	_check(results[0] == results[1], "mesma luta com o painel ligado e desligado")
