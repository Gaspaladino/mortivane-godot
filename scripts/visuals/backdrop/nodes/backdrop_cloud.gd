@tool
class_name BackdropCloud
extends Node2D
## Uma nuvem estilizada, desenhada por código e visível no editor: banco comprido com topo em
## volumes arredondados e base quase reta, em 3 tons (corpo, topo iluminado, barriga escura).
## A origem do nó é o centro da base. Mude comprimento/altura/semente no Inspector.
## `moon_light` (0..1) é ajustado no jogo pela distância até a lua (borda prateada).

@export var length := 320.0:
	set(v):
		length = v
		_rebuild()
@export var height := 34.0:
	set(v):
		height = v
		_rebuild()
## Quantos "volumes" no topo (mais = nuvem mais encaroçada).
@export_range(1, 16) var lumps := 6:
	set(v):
		lumps = v
		_rebuild()
@export var seed := 1.0:
	set(v):
		seed = v
		_rebuild()
@export var body_color := Color(0.27, 0.32, 0.44):
	set(v):
		body_color = v
		queue_redraw()
@export var top_color := Color(0.46, 0.53, 0.67):
	set(v):
		top_color = v
		queue_redraw()
@export var belly_color := Color(0.18, 0.22, 0.32):
	set(v):
		belly_color = v
		queue_redraw()
@export var rim_color := Color(0.86, 0.91, 1.0):
	set(v):
		rim_color = v
		queue_redraw()

var moon_light := 0.0:
	set(v):
		if absf(v - moon_light) > 0.02:
			moon_light = v
			queue_redraw()

var _top := PackedVector2Array()
var _bottom := PackedVector2Array()
var _belly := PackedVector2Array()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	_top.clear()
	_bottom.clear()
	var half := length * 0.5
	var n := maxi(8, int(length / 3.0))
	# centros e raios dos volumes do topo (determinísticos pela semente)
	var bumps: Array[Vector3] = []
	for i in lumps:
		var f := (i + 0.5) / lumps
		var bx := lerpf(-half * 0.8, half * 0.8, f) + (_h(i, 1.0) - 0.5) * length / lumps * 0.5
		var env := 1.0 - pow(absf(bx) / half, 2.0)
		var r := height * (0.5 + 0.5 * _h(i, 2.0)) * (0.45 + 0.55 * env)
		var lift := height * 0.3 * env * _h(i, 5.0)
		bumps.append(Vector3(bx, r, lift))
	for k in n + 1:
		var x := lerpf(-half, half, float(k) / n)
		var u := x / half
		var env := pow(maxf(0.0, 1.0 - u * u), 0.7)
		var y := -height * 0.42 * env            # corpo cheio, pontas afinando
		for b in bumps:
			var dx := x - b.x
			if absf(dx) < b.y:
				y = minf(y, -height * 0.3 * env - b.z - sqrt(b.y * b.y - dx * dx))
		_top.append(Vector2(x, y))
		_bottom.append(Vector2(x, height * 0.14 * pow(maxf(0.0, 1.0 - u * u), 0.5)))
	_bottom.reverse()
	# as pontas de cima e de baixo coincidem: tira as de baixo (polígono simples)
	_bottom.remove_at(_bottom.size() - 1)
	_bottom.remove_at(0)
	# barriga: faixa escura logo acima da base
	_belly.clear()
	for p in _bottom:
		_belly.append(p)
	for i in range(_bottom.size() - 1, -1, -1):
		var p := _bottom[i]
		_belly.append(Vector2(p.x, p.y - 1.0 - height * 0.3 * pow(clampf(1.0 - absf(p.x) / half, 0.0, 1.0), 0.6)))
	queue_redraw()


func _draw() -> void:
	if _top.size() < 2:
		return
	var outline := _top.duplicate()
	outline.append_array(_bottom)
	draw_colored_polygon(outline, body_color)
	var belly_ok := Geometry2D.triangulate_polygon(_belly).size() > 0
	if belly_ok:
		draw_colored_polygon(_belly, belly_color)
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, body_color, 1.0, true)
	# faixa iluminada logo abaixo do topo (volume); a lua a deixa prateada
	var lit := top_color.lerp(rim_color, clampf(moon_light, 0.0, 1.0) * 0.7)
	var band := _top.duplicate()
	for i in range(_top.size() - 1, -1, -1):
		var p := _top[i]
		band.append(Vector2(p.x, lerpf(p.y, 0.0, 0.3) + 0.5))
	if Geometry2D.triangulate_polygon(band).size() > 0:
		draw_colored_polygon(band, Color(lit, 0.55))
	draw_polyline(_top, top_color.lerp(rim_color, clampf(moon_light, 0.0, 1.0)), 1.3 + moon_light * 0.6, true)


func _h(i: int, s: float) -> float:
	var v := sin((i + seed * 17.0) * 127.1 + s * 311.7) * 43758.5453
	return v - floorf(v)
