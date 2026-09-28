class_name BannerSway
extends Sprite2D
## Estandarte (Sprite2D com o shader banner_sway): balanço pendular lento a partir da haste.
## `amplitude` = px na ponta; `speed` multiplica o tempo; `phase` desencontra os dois lados.

@export var amplitude := 2.4
@export var speed := 1.0
@export var phase := 0.0
## Onde o tecido encontra a haste (px a partir do topo da textura).
@export var top_px := 8.0

var global_intensity := 1.0
var _t := 0.0


func _ready() -> void:
	add_to_group(BackdropAnimated.GROUP)
	var mat := material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("tex_size", texture.get_size())
		mat.set_shader_parameter("top_px", top_px)
		mat.set_shader_parameter("phase", phase)
	_apply()


func _process(delta: float) -> void:
	if BackdropAnimated.running():
		_t += delta * speed
		_apply()


func _apply() -> void:
	var mat := material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("t", _t)
		mat.set_shader_parameter("amp", amplitude * global_intensity)
