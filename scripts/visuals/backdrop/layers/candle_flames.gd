class_name CandleFlames
extends Node2D
## Chamas calmas das velas (mistura aditiva): uma língua de fogo que varia de leve na altura e na
## largura, com a ponta balançando pouco, e um brilho local pequeno. Nada de flicker nervoso.

@export var core_color := Color(1.0, 0.9, 1.0)
@export var flame_color := Color(0.74, 0.48, 1.0)
@export_range(0.0, 2.0, 0.05) var intensity := 1.0
@export_range(0.0, 3.0, 0.05) var speed := 1.0

var t := 0.0
var flames: Array = []     # [Vector2 centro, altura]


func _draw() -> void:
	for i in flames.size():
		var c: Vector2 = flames[i][0]
		var h: float = flames[i][1]
		var s := float(i) * 1.73
		var hh := h * 0.62 * (1.0 + 0.1 * sin(t * 2.1 * speed + s) + 0.04 * sin(t * 4.7 * speed + s * 2.0))
		var ww := maxf(1.4, h * 0.2) * (1.0 + 0.08 * sin(t * 1.6 * speed + s * 1.3))
		var sway := 0.45 * sin(t * 1.8 * speed + s) * intensity
		var base := c + Vector2(0, h * 0.3)
		var glow := 0.85 + 0.15 * sin(t * 1.3 * speed + s)
		draw_circle(base - Vector2(0, hh * 0.4), h * 1.3, Color(flame_color, 0.06 * intensity * glow))
		draw_colored_polygon(_tongue(base, ww, hh, sway), Color(flame_color, 0.38 * intensity))
		draw_colored_polygon(_tongue(base, ww * 0.5, hh * 0.62, sway * 0.6), Color(core_color, 0.55 * intensity))


func _tongue(base: Vector2, w: float, h: float, sway: float) -> PackedVector2Array:
	return PackedVector2Array([
		base + Vector2(-w, 0), base + Vector2(-w * 0.75, -h * 0.45), base + Vector2(sway, -h),
		base + Vector2(w * 0.75, -h * 0.45), base + Vector2(w, 0), base + Vector2(0, w * 0.55),
	])
