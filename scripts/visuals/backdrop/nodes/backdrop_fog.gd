@tool
class_name BackdropFog
extends BackdropShaderRect
## Faixa de névoa: desliza na horizontal (`speed`, px/s; negativo = para a esquerda) e
## "respira" (a opacidade oscila devagar). Forma, cor e densidade: parâmetros do material.

@export var speed := 2.0
@export_range(0.0, 1.0, 0.01) var opacity := 0.3
## Amplitude da respiração (fração da opacidade) e período (s).
@export_range(0.0, 0.8, 0.01) var breath := 0.18
@export var breath_period := 11.0

var global_intensity := 1.0
var _t := 0.0


func _ready() -> void:
	super()
	add_to_group(BackdropAnimated.GROUP)
	_apply()


func _process(delta: float) -> void:
	if BackdropAnimated.running():
		_t += delta * global_intensity
	_apply()


func _apply() -> void:
	var mat := material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("t", _t)
	mat.set_shader_parameter("speed", speed)
	var b := 1.0 + breath * global_intensity * sin(TAU * _t / maxf(breath_period, 0.1) + position.y * 0.05)
	mat.set_shader_parameter("opacity", opacity * b)
