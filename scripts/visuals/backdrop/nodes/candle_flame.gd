@tool
class_name CandleFlame
extends Node2D
## Chama calma de uma vela (visível no editor). A origem é a base da chama.
## No jogo: flicker sutil — altura, largura e brilho variam pouco e devagar; a ponta balança pouco.

@export var flame_height := 9.0:
	set(v):
		flame_height = v
		queue_redraw()
@export var core_color := Color(1.0, 0.9, 1.0)
@export var flame_color := Color(0.74, 0.48, 1.0)
@export_range(0.0, 2.0, 0.05) var strength := 1.0
@export var speed := 1.0

var global_intensity := 1.0
var _t := 0.0


func _ready() -> void:
	add_to_group(BackdropAnimated.GROUP)
	_t = position.x * 0.37


func _process(delta: float) -> void:
	if BackdropAnimated.running():
		_t += delta * speed * global_intensity
		queue_redraw()


func _draw() -> void:
	var h := flame_height
	var k := global_intensity if BackdropAnimated.running() else 0.0
	# flicker sutil: variações pequenas e lentas (a chama não "pisca")
	var hh := h * 0.62 * (1.0 + (0.05 * sin(_t * 1.9) + 0.02 * sin(_t * 4.3)) * k)
	var ww := maxf(1.4, h * 0.2) * (1.0 + 0.04 * sin(_t * 1.4) * k)
	var sway := 0.3 * sin(_t * 1.5) * k
	var glow := 0.92 + 0.06 * sin(_t * 1.1) * k + 0.02 * sin(_t * 3.7) * k
	draw_circle(Vector2(0, -hh * 0.4), h * 1.3, Color(flame_color, 0.06 * strength * glow))
	draw_colored_polygon(_tongue(ww, hh, sway), Color(flame_color, 0.38 * strength))
	draw_colored_polygon(_tongue(ww * 0.5, hh * 0.62, sway * 0.6), Color(core_color, 0.55 * strength))


func _tongue(w: float, h: float, sway: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-w, 0), Vector2(-w * 0.75, -h * 0.45), Vector2(sway, -h),
		Vector2(w * 0.75, -h * 0.45), Vector2(w, 0), Vector2(0, w * 0.55),
	])
