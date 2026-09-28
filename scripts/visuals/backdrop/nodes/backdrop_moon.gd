@tool
class_name BackdropMoon
extends Node2D
## Lua cheia: a posição do nó é o centro. O disco e o halo são o filho `Disc` (ColorRect com o
## shader da lua), redimensionado para 4 raios. No jogo, o brilho pulsa bem devagar e a lua
## oscila menos de 1 px.

@export var radius := 70.0:
	set(value):
		radius = value
		_layout()
@export_range(0.0, 0.2, 0.005) var pulse_amount := 0.035
@export var pulse_period := 6.5
@export_range(0.0, 2.0, 0.05) var halo_strength := 0.55
## Oscilação mínima (px).
@export var drift := 0.6

var global_intensity := 1.0
var _t := 0.0


func _ready() -> void:
	add_to_group(BackdropAnimated.GROUP)
	_layout()


func _layout() -> void:
	var disc := get_node_or_null("Disc") as ColorRect
	if disc == null:
		return
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.size = Vector2.ONE * radius * 4.0
	disc.position = -disc.size / 2.0


func _process(delta: float) -> void:
	var disc := get_node_or_null("Disc") as ColorRect
	if disc == null or not BackdropAnimated.running():
		return
	_t += delta
	var mat := disc.material as ShaderMaterial
	mat.set_shader_parameter("t", _t)
	mat.set_shader_parameter("pulse_amount", pulse_amount * global_intensity)
	mat.set_shader_parameter("pulse_period", pulse_period)
	mat.set_shader_parameter("halo_strength", halo_strength)
	disc.position = -disc.size / 2.0 + Vector2(sin(_t * 0.05), cos(_t * 0.04)) * drift * global_intensity
