extends Node
## Raiz do jogo. Troca de tela (Menu ↔ Sandbox) e trata os atalhos globais de janela/debug.
##
## Telas: uma por vez, filha de Main (`current_screen`). Uma tela que tem Arena expõe get_arena().
##   MainMenu — Jogar (em construção) / Sandbox
##   Sandbox  — Arena + SandboxUI + SandboxController
##
## Atalhos (InputMap em project.godot, tecla física):
##   debug_toggle        F3  — liga/desliga a camada de debug da arena
##   combat_debug_toggle F4  — liga/desliga o debug de combate (alvo, alcance, HP, estado)
##   combat_restart      F9  — atalho secundário de "Reiniciar combate" no Sandbox
##   perf_overlay_toggle F6  — painel de desempenho do Sandbox (FPS, quadro, vivos, draw calls, tempos)
##   fullscreen_toggle   F11 — alterna janela ↔ tela cheia
## O estado de F3/F4 é lembrado aqui e reaplicado a cada Arena nova.
##
## Rodando embutido na aba "Game" do editor (padrão da Godot 4.4+), o jogo só
## recebe teclado quando a área do jogo está focada, e a janela embutida não pode
## entrar em tela cheia. Nesse caso um aviso explica o que fazer.

const MENU_SCENE := preload("res://scenes/menu/main_menu.tscn")
const SANDBOX_SCENE := preload("res://scenes/sandbox/sandbox.tscn")
const NOTICE_SECONDS := 4.0

@onready var notice_label: Label = $NoticeLayer/NoticeLabel

var current_screen: Node
var _arena_debug := true      # a Arena nasce com o debug ligado (Etapa 1)
var _combat_debug := false
var _perf_overlay := false    # painel de desempenho do Sandbox (F6); começa desligado
var _notice_tween: Tween


func _ready() -> void:
	notice_label.modulate.a = 0.0
	show_menu()
	if Engine.is_embedded_in_editor():
		show_notice("Jogo embutido no editor: clique na área do jogo para ele receber o teclado.\n"
			+ "F11 (tela cheia) só funciona com o jogo em janela própria.", 6.0)


func show_menu() -> void:
	var menu: MainMenu = _switch_to(MENU_SCENE)
	menu.play_pressed.connect(func() -> void:
		menu.show_message("O fluxo principal (campanha) ainda está em construção.\nUse o Sandbox para testar o combate."))
	menu.sandbox_pressed.connect(show_sandbox)


func show_sandbox() -> void:
	var sandbox: SandboxController = _switch_to(SANDBOX_SCENE)
	sandbox.exit_requested.connect(show_menu)
	var arena := sandbox.get_arena()
	arena.set_debug_visible(_arena_debug)
	arena.battle.set_debug_visible(_combat_debug)
	sandbox.perf_overlay.set_shown(_perf_overlay)


func _switch_to(scene: PackedScene) -> Node:
	if current_screen:
		# remove já da árvore (a Arena antiga não pode disputar a câmera) e libera no fim do quadro
		remove_child(current_screen)
		current_screen.queue_free()
	current_screen = scene.instantiate()
	add_child(current_screen)
	move_child(current_screen, 0)   # NoticeLayer continua por cima
	return current_screen


func _current_arena() -> Arena:
	if current_screen and current_screen.has_method("get_arena"):
		return current_screen.get_arena()
	return null


# _input (e não _unhandled_input): atalhos globais não podem ser engolidos por
# controles de interface.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle", false, true):
		get_viewport().set_input_as_handled()
		_arena_debug = not _arena_debug
		var arena := _current_arena()
		if arena:
			arena.set_debug_visible(_arena_debug)
	elif event.is_action_pressed("combat_debug_toggle", false, true):
		get_viewport().set_input_as_handled()
		_combat_debug = not _combat_debug
		var arena := _current_arena()
		if arena:
			arena.battle.set_debug_visible(_combat_debug)
	elif event.is_action_pressed("perf_overlay_toggle", false, true):
		get_viewport().set_input_as_handled()
		_perf_overlay = not _perf_overlay
		if current_screen is SandboxController:
			current_screen.perf_overlay.set_shown(_perf_overlay)
	elif event.is_action_pressed("combat_restart", false, true):
		get_viewport().set_input_as_handled()
		if current_screen is SandboxController:
			current_screen.reset_combat()
	elif event.is_action_pressed("fullscreen_toggle", false, true):
		get_viewport().set_input_as_handled()
		_toggle_fullscreen()


func _toggle_fullscreen() -> void:
	if Engine.is_embedded_in_editor():
		show_notice("Tela cheia indisponível com o jogo embutido no editor.\n"
			+ "Na aba Game, menu ⋮ → desmarque \"Embed Game on Next Play\" e rode de novo (F5).")
		return
	var window := get_window()
	if window.mode == Window.MODE_FULLSCREEN or window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		window.mode = Window.MODE_WINDOWED
	else:
		window.mode = Window.MODE_FULLSCREEN


func show_notice(text: String, seconds := NOTICE_SECONDS) -> void:
	notice_label.text = text
	if _notice_tween:
		_notice_tween.kill()
	notice_label.modulate.a = 1.0
	_notice_tween = create_tween()
	_notice_tween.tween_interval(seconds)
	_notice_tween.tween_property(notice_label, "modulate:a", 0.0, 0.6)
