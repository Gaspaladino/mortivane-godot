class_name MainMenu
extends Control
## Menu inicial. Só emite sinais; quem troca de tela é o Main.

signal play_pressed
signal sandbox_pressed

@onready var play_button: Button = %PlayButton
@onready var sandbox_button: Button = %SandboxButton
@onready var message_label: Label = %MessageLabel
## O mesmo fundo animado da arena, escurecido, cobrindo a tela (cover).
@onready var backdrop: ArenaBackdrop = $Backdrop


func _ready() -> void:
	play_button.pressed.connect(play_pressed.emit)
	sandbox_button.pressed.connect(sandbox_pressed.emit)
	message_label.text = ""
	sandbox_button.grab_focus()
	resized.connect(_fit_backdrop)
	_fit_backdrop()


func _fit_backdrop() -> void:
	var k := maxf(size.x / backdrop.art_size.x, size.y / backdrop.art_size.y)
	backdrop.scale = Vector2(k, k)
	backdrop.position = (size - backdrop.art_size * k) / 2.0


func show_message(text: String) -> void:
	message_label.text = text
