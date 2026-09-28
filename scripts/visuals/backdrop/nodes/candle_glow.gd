class_name CandleGlow
extends Sprite2D
## Brilho das chamas e reflexos pintados das velas (Sprite2D com o shader candle_flicker,
## aditivo): respira devagar.

@export_range(0.0, 2.0, 0.05) var strength := 0.35
@export var speed := 1.0
@export var seed := 3.0

var global_intensity := 1.0
var _t := 0.0


func _ready() -> void:
	add_to_group(BackdropAnimated.GROUP)
	_apply()


func _process(delta: float) -> void:
	if BackdropAnimated.running():
		_t += delta * speed * global_intensity
		_apply()


func _apply() -> void:
	var mat := material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("t", _t)
		mat.set_shader_parameter("strength", strength)
		mat.set_shader_parameter("seed", seed)
