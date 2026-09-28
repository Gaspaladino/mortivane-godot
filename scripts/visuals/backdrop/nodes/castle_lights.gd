class_name CastleLights
extends Node2D
## Anima as janelas (filhos CastleWindow): cada uma com ritmo lento próprio (dezenas de
## segundos), acendendo e apagando suavemente — poucas acesas por vez (tipicamente 3 a 7).

@export_range(0.0, 2.0, 0.05) var intensity := 1.0
@export var speed := 1.0
## Fração das janelas que podem acender.
@export_range(0.0, 1.0, 0.05) var lit_share := 0.45

var global_intensity := 1.0
var t := 0.0


func _ready() -> void:
	add_to_group(BackdropAnimated.GROUP)
	_update()


func _process(delta: float) -> void:
	if BackdropAnimated.running():
		t += delta * speed
		_update()


func window_level(i: int, time: float) -> float:
	var h := _hash(float(i), 17.0)
	if h >= lit_share:
		return 0.0
	var bias := lerpf(-0.1, 0.7, _hash(float(i), 29.0))
	var f1 := lerpf(0.05, 0.16, _hash(float(i), 3.0))
	var f2 := lerpf(0.11, 0.3, _hash(float(i), 7.0))
	var s := sin(time * f1 + h * 40.0) + 0.6 * sin(time * f2 + h * 91.0) + bias - 0.6
	return smoothstep(-0.45, 0.45, s) * (0.95 + 0.05 * sin(time * 2.2 + h * 120.0))   # tremor leve de chama


func windows() -> Array[CastleWindow]:
	var out: Array[CastleWindow] = []
	for c in get_children():
		if c is CastleWindow and c.can_light:
			out.append(c)
	return out


func _update() -> void:
	var ws := windows()
	for i in ws.size():
		ws[i].level = window_level(i, t) * intensity * global_intensity


static func _hash(i: float, s: float) -> float:
	var v := sin(i * 127.1 + s * 311.7) * 43758.5453
	return v - floorf(v)
