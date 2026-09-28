extends Node
## Raiz do jogo. Hospeda a Arena e trata os atalhos globais de janela/debug.
##
## Atalhos (InputMap em project.godot, tecla física):
##   debug_toggle      F3  — liga/desliga a camada de debug da arena
##   fullscreen_toggle F11 — alterna janela ↔ tela cheia
##   combat_debug_toggle F4 — liga/desliga o debug de combate (alvo, alcance, HP, estado)
##   combat_restart    F9  — reinicia a luta de teste
##
## Rodando embutido na aba "Game" do editor (padrão da Godot 4.4+), o jogo só
## recebe teclado quando a área do jogo está focada, e a janela embutida não pode
## entrar em tela cheia. Nesse caso um aviso explica o que fazer.

const NOTICE_SECONDS := 4.0

@onready var arena: Arena = $Arena
@onready var notice_label: Label = $NoticeLayer/NoticeLabel

var _notice_tween: Tween


func _ready() -> void:
	notice_label.modulate.a = 0.0
	arena.battle.finished.connect(_on_battle_finished)
	if Engine.is_embedded_in_editor():
		show_notice("Jogo embutido no editor: clique na área do jogo para ele receber o teclado.\n"
			+ "F11 (tela cheia) só funciona com o jogo em janela própria.", 6.0)


# _input (e não _unhandled_input): atalhos globais não podem ser engolidos por
# controles de interface que venham a existir.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle", false, true):
		get_viewport().set_input_as_handled()
		arena.set_debug_visible(not arena.is_debug_visible())
	elif event.is_action_pressed("fullscreen_toggle", false, true):
		get_viewport().set_input_as_handled()
		_toggle_fullscreen()
	elif event.is_action_pressed("combat_debug_toggle", false, true):
		get_viewport().set_input_as_handled()
		arena.battle.set_debug_visible(not arena.battle.is_debug_visible())
	elif event.is_action_pressed("combat_restart", false, true):
		get_viewport().set_input_as_handled()
		arena.battle.restart()


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


func _on_battle_finished(winner: CombatUnit) -> void:
	var result := "%s venceu" % winner.label() if winner else "Ninguém sobreviveu"
	show_notice("Fim do teste de combate: %s. F9 reinicia." % result)


func show_notice(text: String, seconds := NOTICE_SECONDS) -> void:
	notice_label.text = text
	if _notice_tween:
		_notice_tween.kill()
	notice_label.modulate.a = 1.0
	_notice_tween = create_tween()
	_notice_tween.tween_interval(seconds)
	_notice_tween.tween_property(notice_label, "modulate:a", 0.0, 0.6)
