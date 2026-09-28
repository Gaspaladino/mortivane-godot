extends SceneTree
## Teste de regressão: cliques de MOUSE de verdade no menu (não `pressed.emit()`).
## Os eventos entram pelo viewport raiz como os do sistema operacional (coordenadas de janela,
## hit-test da GUI, mouse_filter, ordem das camadas), com pressionar e soltar em quadros
## separados. Abre main.tscn → clica Sandbox → volta ao menu → clica Sandbox de novo.
##   godot --headless -s res://tests/menu_click_test.gd

var _failures := 0
var main: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	_check(main.current_screen is MainMenu, "jogo abre no menu")

	for attempt in 2:
		var menu: MainMenu = main.current_screen
		await _click(menu.sandbox_button)
		_check(main.current_screen is SandboxController, "%dª vez: clicar em Sandbox abre o Sandbox" % (attempt + 1))
		if not main.current_screen is SandboxController:
			break
		var sandbox: SandboxController = main.current_screen
		await _frames(2)   # a faixa inferior se ajusta
		await _click(sandbox.ui.menu_button)
		_check(main.current_screen is MainMenu, "%dª vez: Voltar ao menu volta ao menu" % (attempt + 1))
		if not main.current_screen is MainMenu:
			break

	# Jogar: o clique chega (mostra o aviso) e continua no menu
	if main.current_screen is MainMenu:
		var menu: MainMenu = main.current_screen
		await _click(menu.play_button)
		_check(main.current_screen == menu and menu.message_label.text.contains("construção"), "clicar em Jogar mostra o aviso")

	main.free()
	print("menu_click_test: %s" % ("OK" if _failures == 0 else "%d falha(s)" % _failures))
	quit(1 if _failures > 0 else 0)


## Move o mouse até o centro do botão, pressiona e solta em quadros diferentes.
func _click(button: Button) -> void:
	var at := root.get_final_transform() * button.get_global_rect().get_center()   # coordenadas de janela
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion)
	await _frames(2)
	_check(root.gui_get_hovered_control() == button, "mouse sobre %s (sob o mouse: %s)" % [button.name, root.gui_get_hovered_control()])
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		root.push_input(ev)
		await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures += 1
		printerr("  FALHOU: ", what)
