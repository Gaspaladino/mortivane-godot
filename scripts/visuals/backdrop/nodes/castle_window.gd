@tool
class_name CastleWindow
extends Node2D
## Uma janela do castelo (arco gótico). `level` 0..1 = apagada..acesa; no jogo o
## CastleLights anima o nível. No editor aparece com `preview_level`.

@export var size := Vector2(3, 7):
	set(v):
		size = v
		queue_redraw()
@export var dark_color := Color(0.1, 0.11, 0.18)
@export var light_color := Color(0.74, 0.5, 1.0)
## Pode acender? (desmarque para uma janela sempre escura)
@export var can_light := true
@export_range(0.0, 1.0) var preview_level := 0.7

var level := -1.0:
	set(v):
		if absf(v - level) > 0.01:
			level = v
			queue_redraw()


func _draw() -> void:
	var l := preview_level if level < 0.0 else level
	var h := size / 2.0
	var shape := PackedVector2Array([
		Vector2(-h.x, h.y), Vector2(-h.x, -h.y + 1.5), Vector2(0, -h.y), Vector2(h.x, -h.y + 1.5), Vector2(h.x, h.y),
	])
	draw_colored_polygon(shape, dark_color)
	if l <= 0.01 or not can_light:
		return
	draw_circle(Vector2.ZERO, 6.0, Color(light_color, 0.08 * l))
	draw_circle(Vector2.ZERO, 3.2, Color(light_color, 0.18 * l))
	draw_colored_polygon(shape, Color(light_color, 0.85 * l))
