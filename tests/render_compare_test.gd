extends SceneTree
## Comparação de render do Sandbox (F7, ferramenta de diagnóstico).
##   - F7 (tecla física real) cicla normal → congelado → quadrados → lote simulado → normal;
##   - congelado: os UnitView param de atualizar; quadrados/lote: o corpo e a barra somem e cada
##     unidade ganha UM nó simples; voltar ao normal desfaz tudo;
##   - unidades recriadas (Reiniciar) recebem o modo em uso;
##   - o painel F6 mostra o modo;
##   - não muda o combate: a mesma luta termina igual em qualquer modo.

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
	var rc := sb.render_compare
	for i in 6:
		sb.add_unit(UnitCatalog.get_def([&"warrior", &"u_warrior", &"sac_paladin"][i % 3]), CombatUnit.Team.PLAYER)
		sb.add_unit(UnitCatalog.get_def([&"arc_battlemage", &"u_arc_battlemage", &"u_sac_paladin"][i % 3]), CombatUnit.Team.ENEMY)
	await process_frame
	_check(rc.mode == RenderCompare.Mode.NORMAL and not rc.is_processing(), "começa no normal, sem processar")
	await _press(KEY_F7)
	var views := _views(sb)
	_check(rc.mode == RenderCompare.Mode.FROZEN and views.all(func(v): return not v.is_processing() and v.visual.visible), "F7 → congelado")
	await _press(KEY_F7)
	views = _views(sb)
	_check(rc.mode == RenderCompare.Mode.SQUARES and views.all(func(v): return not v.visual.visible and not v.get_node("Overlay").visible and v.get_node_or_null(RenderCompare.NODE_NAME) != null and v.is_processing()),
		"F7 → quadrados (corpo e barra escondidos, 1 nó simples por unidade)")
	sb.reset_combat()
	for i in 2:
		await process_frame
	views = _views(sb)
	_check(views.size() == 12 and views.all(func(v): return not v.visual.visible and v.get_node_or_null(RenderCompare.NODE_NAME) != null), "Reiniciar: unidades novas recebem o modo")
	await _press(KEY_F7)
	views = _views(sb)
	_check(rc.mode == RenderCompare.Mode.MERGED and views.all(func(v): return v.get_node_or_null(RenderCompare.NODE_NAME) != null), "F7 → lote simulado")
	sb.perf_overlay.set_shown(true)
	for i in 15:
		await process_frame
	_check((sb.perf_overlay.get_node("Panel").get_child(0) as Label).text.contains("Visual (F7): lote simulado"), "o painel mostra o modo")
	sb.perf_overlay.set_shown(false)
	await _press(KEY_F7)
	for i in 2:
		await process_frame
	views = _views(sb)
	_check(rc.mode == RenderCompare.Mode.NORMAL and views.all(func(v): return v.visual.visible and v.get_node("Overlay").visible and v.is_processing() and v.get_node_or_null(RenderCompare.NODE_NAME) == null),
		"F7 → normal: tudo restaurado")
	_check(not rc.is_processing(), "no normal, para de processar")
	main.queue_free()
	await process_frame
	await _test_same_fight()
	print("render_compare_test: %s" % ("OK" if _failures == 0 else "%d falha(s)" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("  FALHOU: " + msg)


func _views(sb: SandboxController) -> Array:
	return sb.arena.battle.get_node(sb.arena.battle.entities_path).get_children().filter(func(n): return n is UnitView)


func _press(key: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		ev.keycode = key
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame
	await process_frame   # o modo é aplicado no _process seguinte


## A mesma luta (passos fixos) em cada modo: mesmo resultado.
func _test_same_fight() -> void:
	var results := []
	for m in RenderCompare.Mode.size():
		var main: Node = load("res://scenes/main/main.tscn").instantiate()
		root.add_child(main)
		await process_frame
		main.show_sandbox()
		await process_frame
		var sb: SandboxController = main.current_screen
		for i in 8:
			sb.add_unit(UnitCatalog.get_def([&"warrior", &"sac_paladin"][i % 2]), CombatUnit.Team.PLAYER)
			sb.add_unit(UnitCatalog.get_def([&"arc_battlemage", &"u_warrior"][i % 2]), CombatUnit.Team.ENEMY)
		sb.render_compare.set_mode(m)
		sb.start_combat()
		var battle := sb.arena.battle
		battle.set_process(false)
		for k in 3000:
			battle._process(1.0 / 60.0)
			if k % 30 == 0:
				await process_frame
		var snap := []
		for u in battle.sim.units:
			snap.append([u.id, u.hp, u.position, u.state])
		results.append(snap)
		main.queue_free()
		await process_frame
	_check(results.all(func(r): return r == results[0]), "mesma luta em todos os modos")
