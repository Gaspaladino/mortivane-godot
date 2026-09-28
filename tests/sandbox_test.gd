extends SceneTree
## Teste headless de ponta a ponta do Menu + Sandbox, usando a cena real (main.tscn).
## Rodar a partir da raiz do projeto:
##   godot --headless -s res://tests/sandbox_test.gd
## Sai com código 0 se tudo passar, 1 se alguma verificação falhar.

const MAX_FIGHT_SECONDS := 90.0

var _failures := 0
var main: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await _frames(2)

	# 1. abre no menu; Jogar só avisa
	_check(main.current_screen is MainMenu, "jogo abre no menu")
	var menu: MainMenu = main.current_screen
	_press(menu.play_button)
	_check(main.current_screen == menu and menu.message_label.text.contains("construção"), "Jogar mostra aviso e fica no menu")

	# 2. Sandbox abre, parado e vazio
	_press(menu.sandbox_button)
	await _frames(2)
	_check(main.current_screen is SandboxController, "Sandbox abre")
	var sandbox: SandboxController = main.current_screen
	var battle := sandbox.arena.battle
	var ui := sandbox.ui
	_check(battle.sim.units.is_empty() and not battle.is_running(), "Sandbox começa vazio e parado")
	_check(ui.start_button.disabled, "Iniciar desabilitado sem tropas")
	# UI numa faixa inferior (cena editável) e o campo inteiro visível acima dela
	_check(ui.bottom_bar.anchor_top >= 0.7 and ui.bottom_bar.anchor_bottom == 1.0, "UI na faixa inferior")
	var bar_h := ui.bottom_inset() / ui.get_viewport().get_visible_rect().size.y
	_check(bar_h > 0.15 and bar_h < 0.3, "faixa ocupa 15–30%% da altura (%.0f%%)" % (bar_h * 100.0))
	_check(sandbox.arena.bottom_inset == ui.bottom_inset(), "a Arena reserva a faixa da UI")
	var ct := sandbox.arena.get_viewport().get_canvas_transform()
	var field_bottom := (ct * Vector2(500, WorldConfig.BATTLEFIELD_RECT.end.y)).y
	var field_top := (ct * Vector2(500, WorldConfig.BATTLEFIELD_TOP_Y)).y
	_check(field_top >= 0.0 and field_bottom <= ui.bottom_bar.global_position.y + 0.5, "campo inteiro acima da faixa (y %.0f–%.0f, faixa em %.0f)" % [field_top, field_bottom, ui.bottom_bar.global_position.y])

	# 3–5. criar aliados e inimigos (botões gerados pelo catálogo)
	var ally_button: Button = ui.find_child("Spawn_u_warrior", true, false)
	var enemy_button: Button = ui.find_child("Spawn_warrior", true, false)
	_check(ally_button != null and enemy_button != null, "listas geradas a partir do UnitCatalog")
	_press(ally_button)
	_check(battle.sim.units.size() == 1 and battle.sim.units[0].team == CombatUnit.Team.PLAYER
		and battle.sim.units[0].position.x < WorldConfig.DEPLOY_X, "aliado criado do lado esquerdo")
	_check(ui.start_button.disabled, "Iniciar exige os dois lados")
	_press(enemy_button)
	_check(battle.sim.units.size() == 2 and battle.sim.units[1].team == CombatUnit.Team.ENEMY
		and battle.sim.units[1].position.x > WorldConfig.DEPLOY_X, "inimigo criado do lado direito")
	_press(ally_button)
	_press(ally_button)
	_press(enemy_button)
	_check(battle.sim.units.size() == 5 and sandbox.placements.size() == 5, "múltiplas unidades")
	var positions := {}
	for p in sandbox.placements:
		positions[p.position] = true
	_check(positions.size() == 5, "posições automáticas distintas")
	_check(sandbox.arena.find_child("Entities", true, false).get_child_count() == 5, "um UnitView por unidade")

	# 6. nada se move antes de Iniciar
	var before := sandbox.placements.map(func(p): return p.unit.position)
	await _frames(30)
	_check(battle.sim.time == 0.0 and sandbox.placements.map(func(p): return p.unit.position) == before,
		"combate não inicia antes do botão")

	# 12. seleção (clique real no viewport) e painel
	var ally0: SandboxController.Placement = sandbox.placements[0]
	_click_world(sandbox, ally0.unit.position)
	await _frames(1)
	_check(sandbox.selected == ally0, "clique seleciona a unidade")
	_check(ui.selected_title.text.contains("Guerreiro Sombra") and ui.selected_title.text.contains("Aliado"), "painel: nome e lado")
	_check(ui.selected_info.text.contains("HP 74/74") and ui.selected_info.text.contains("Alcance 32")
		and ui.selected_info.text.contains("Intervalo 1 s") and ui.selected_info.text.contains("Velocidade 56"), "painel: atributos")
	_check(battle.view_of(ally0.unit).selected, "unidade selecionada destacada")

	# edição por instância (só na preparação); vale para esta instância e sobrevive a Reiniciar
	ui._spins["dmg"].value = 25.0
	await _frames(1)
	_check(ally0.unit.damage == 25.0 and sandbox.placements[1].unit.damage == 9.0, "edição altera só a instância")
	_check(UnitCatalog.get_def(&"u_warrior").damage == 10.0, "edição não altera a UnitDef")
	_check(sandbox.selected == ally0 and ui.selected_info.text.contains("Dano 25"), "seleção e painel seguem após editar")

	# 7–8. Iniciar: roda o combate real
	_press(ui.start_button)
	_check(battle.is_running() and sandbox.mode == SandboxController.Mode.RUNNING, "Iniciar combate")
	_check(ui.start_button.disabled and ally_button.disabled, "sem iniciar de novo nem criar tropas durante o combate")
	_check(ui._spins["dmg"].editable == false, "edição bloqueada durante o combate")
	await _frames(20)
	_check(battle.sim.time > 0.0, "simulação avança depois de Iniciar")
	for p in sandbox.placements:
		_check(p.unit in battle.sim.units and p.unit is CombatUnit, "unidade pertence à CombatSim da Arena")
		_check(p.unit.target != null and p.unit.target.team != p.unit.team, "alvo real adquirido (%s)" % p.unit.label())
	_check(sandbox.placements.any(func(p): return p.unit.state == CombatUnit.State.MOVING), "unidades se movem")
	# o evento real de dano dispara o golpe no visual do atacante no mesmo passo
	var strikes := [0]
	battle.sim.unit_attacked.connect(func(attacker: CombatUnit, _t: CombatUnit, _a: float) -> void:
		if battle.view_of(attacker).visual._strike_t == 0.0:
			strikes[0] += 1)
	var start := Time.get_ticks_msec()
	while sandbox.mode != SandboxController.Mode.FINISHED and Time.get_ticks_msec() - start < MAX_FIGHT_SECONDS * 1000:
		await _frames(1)
	_check(sandbox.mode == SandboxController.Mode.FINISHED, "combate termina")
	await _frames(1)   # os visuais leem o estado no quadro seguinte ao passo da simulação
	var dead := sandbox.placements.filter(func(p): return not p.unit.is_alive())
	_check(dead.size() >= 2, "houve mortes (%d)" % dead.size())
	for p in dead:
		_check(p.unit.hp == 0.0 and p.unit.state == CombatUnit.State.DEAD, "morto com HP 0 e DEAD")
		_check(battle.view_of(p.unit).visual._death_t > 0.0, "visual executa a queda (%s)" % p.unit.label())
	for p in sandbox.placements:
		var vis := battle.view_of(p.unit).visual
		var expected: Script = ShadowWarriorVisual if p.def.id == &"u_warrior" else WarriorVisual
		_check(vis.get_script() == expected, "visual desenhado por código da UnitDef (%s)" % p.unit.label())
	_check(strikes[0] > 0, "golpes reais chegam ao visual do atacante (%d)" % strikes[0])
	_check(ui.status_label.text.begins_with("FIM"), "estado mostra o resultado")

	# 9. Reiniciar restaura a montagem
	_press(ui.reset_button)
	await _frames(1)
	_check(sandbox.mode == SandboxController.Mode.PREP and not battle.is_running() and battle.sim.time == 0.0, "Reiniciar volta à preparação")
	var restored := true
	for p in sandbox.placements:
		restored = restored and p.unit.is_alive() and p.unit.hp == p.unit.max_hp and p.unit.position == p.position
	_check(restored and battle.sim.units.size() == 5, "Reiniciar restaura HP e posições")
	_check(ally0.unit.damage == 25.0, "Reiniciar mantém a edição por instância")
	_check(sandbox.arena.find_child("Entities", true, false).get_child_count() == 5, "Reiniciar não acumula visuais")

	# F9 (atalho secundário) também reinicia
	_press(ui.start_button)
	await _frames(5)
	_action("combat_restart")
	await _frames(1)
	_check(sandbox.mode == SandboxController.Mode.PREP and battle.sim.time == 0.0, "F9 reinicia o combate")

	# 13. F3/F4
	var arena_debug := sandbox.arena.is_debug_visible()
	_action("debug_toggle")
	_check(sandbox.arena.is_debug_visible() != arena_debug, "F3 alterna o debug da arena")
	_action("combat_debug_toggle")
	_check(battle.is_debug_visible() and battle.view_of(ally0.unit).debug_visible, "F4 liga o debug de combate")

	# 10. Limpar arena
	_press(ui.clear_button)
	await _frames(1)
	_check(sandbox.placements.is_empty() and battle.sim.units.is_empty() and sandbox.selected == null, "Limpar remove tudo")
	_check(sandbox.arena.find_child("Entities", true, false).get_child_count() == 0, "Limpar remove os visuais")

	# 11. Voltar ao menu; 14. entrar e sair de novo sem acumular nós
	_press(ally_button)
	_press(enemy_button)
	_press(ui.menu_button)
	await _frames(2)
	_check(main.current_screen is MainMenu, "Voltar ao menu")
	_check(not is_instance_valid(sandbox), "Sandbox anterior liberado")
	var nodes_in_menu := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	for i in 3:
		_press(main.current_screen.sandbox_button)
		await _frames(2)
		var sb: SandboxController = main.current_screen
		_check(sb.arena.is_debug_visible() != arena_debug and sb.arena.battle.is_debug_visible(), "F3/F4 lembrados ao reentrar")
		_press(sb.ui.find_child("Spawn_u_warrior", true, false))
		_press(sb.ui.find_child("Spawn_warrior", true, false))
		_press(sb.ui.start_button)
		await _frames(10)
		_press(sb.ui.menu_button)
		await _frames(2)
	_check(Performance.get_monitor(Performance.OBJECT_NODE_COUNT) == nodes_in_menu, "entrar/sair do Sandbox não acumula nós")

	# Sentinelas (viva e Sombra) no fluxo real: aparecem, disparam, e os projéteis são limpos
	_press(main.current_screen.sandbox_button)
	await _frames(2)
	var ss: SandboxController = main.current_screen
	var effects := ss.arena.find_child("Effects", true, false)
	_press(ss.ui.find_child("Spawn_u_arc_battlemage", true, false))
	_press(ss.ui.find_child("Spawn_arc_battlemage", true, false))
	_check(ss.arena.battle.view_of(ss.placements[0].unit).visual is SentinelShadowVisual
		and ss.arena.battle.view_of(ss.placements[1].unit).visual is SentinelVisual, "Sentinelas com visual próprio no Sandbox")
	_press(ss.ui.start_button)
	var t_start := Time.get_ticks_msec()
	while effects.get_child_count() == 0 and Time.get_ticks_msec() - t_start < 20000:
		await _frames(1)
	_check(effects.get_child_count() > 0, "disparo real cria ProjectileView")
	_press(ss.ui.reset_button)
	await _frames(1)
	_check(effects.get_child_count() == 0 and ss.arena.battle.sim.projectiles.is_empty(), "Reiniciar limpa os projéteis")
	_press(ss.ui.start_button)
	await _frames(40)
	_press(ss.ui.clear_button)
	await _frames(1)
	_check(effects.get_child_count() == 0, "Limpar remove os projéteis")
	_press(ss.ui.find_child("Spawn_u_arc_battlemage", true, false))
	_press(ss.ui.find_child("Spawn_warrior", true, false))
	_press(ss.ui.start_button)
	await _frames(30)
	_press(ss.ui.menu_button)
	await _frames(2)
	_check(Performance.get_monitor(Performance.OBJECT_NODE_COUNT) == nodes_in_menu, "sair com projéteis em voo não vaza nós")

	print("sandbox_test: %s" % ("OK" if _failures == 0 else "%d falha(s)" % _failures))
	main.queue_free()
	await _frames(1)
	quit(1 if _failures > 0 else 0)


func _press(button: Button) -> void:
	if button == null or button.disabled:
		_check(false, "botão %s disponível" % (button.text if button else "<nulo>"))
		return
	button.pressed.emit()


func _action(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


## Clique de mouse de verdade, passando pelo viewport (UI → _unhandled_input do Sandbox).
func _click_world(sandbox: SandboxController, world_point: Vector2) -> void:
	var screen := sandbox.arena.get_viewport().get_canvas_transform() * world_point
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	root.push_input(motion, true)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = screen
		root.push_input(ev, true)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures += 1
		printerr("  FALHOU: ", what)
