class_name MainMenu
extends Control
## Menu inicial. Só emite sinais; quem troca de tela é o Main.

signal play_pressed
signal sandbox_pressed

@onready var play_button: Button = %PlayButton
@onready var sandbox_button: Button = %SandboxButton
@onready var message_label: Label = %MessageLabel


func _ready() -> void:
	play_button.pressed.connect(play_pressed.emit)
	sandbox_button.pressed.connect(sandbox_pressed.emit)
	message_label.text = ""
	sandbox_button.grab_focus()


func show_message(text: String) -> void:
	message_label.text = text
