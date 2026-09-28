class_name CastleLights
extends Node2D
## Luzes roxas das janelas do castelo (filho do CastleLayer, mistura aditiva).
## Cada janela tem seu ritmo lento: umas ficam quase sempre apagadas, outras acendem e apagam
## suavemente ao longo de dezenas de segundos, com uma cintilação mínima. Nunca todas juntas.

@export var light_color := Color(0.72, 0.46, 1.0)
@export_range(0.0, 2.0, 0.05) var intensity := 1.0
## Fração das janelas que podem acender.
@export_range(0.0, 1.0, 0.05) var lit_share := 0.55

var t := 0.0
var _windows: Array[Rect2] = []
var _params: Array = []    # [viés, f1, f2, fase1, fase2]


func setup(windows: Array[Rect2]) -> void:
	_windows = windows
	_params.clear()
	for i in windows.size():
		var h := BackdropSilhouette.hash1(float(i), 17.0)
		var bias := lerpf(0.4, 1.2, BackdropSilhouette.hash1(float(i), 29.0)) if h < lit_share else -2.0
		_params.append([bias, lerpf(0.05, 0.16, BackdropSilhouette.hash1(float(i), 3.0)),
			lerpf(0.11, 0.3, BackdropSilhouette.hash1(float(i), 7.0)), h * 40.0, h * 91.0])
	queue_redraw()


func _draw() -> void:
	for i in _windows.size():
		var p: Array = _params[i]
		var s: float = sin(t * p[1] + p[3]) + 0.6 * sin(t * p[2] + p[4]) + p[0] - 0.6
		var level := smoothstep(-0.45, 0.45, s)
		if level <= 0.01:
			continue
		var flick := 0.9 + 0.1 * sin(t * 5.3 + p[3] * 3.0)
		var a := level * flick * intensity
		var r := _windows[i]
		draw_circle(r.get_center(), 6.0, Color(light_color, 0.1 * a))
		draw_circle(r.get_center(), 3.2, Color(light_color, 0.22 * a))
		draw_rect(r.grow(-0.3), Color(light_color, 0.85 * a))
