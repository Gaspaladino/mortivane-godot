extends Node
## Raiz do jogo. Por enquanto só hospeda a Arena e atalhos de janela.


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var window := get_window()
		if window.mode == Window.MODE_FULLSCREEN:
			window.mode = Window.MODE_WINDOWED
		else:
			window.mode = Window.MODE_FULLSCREEN
