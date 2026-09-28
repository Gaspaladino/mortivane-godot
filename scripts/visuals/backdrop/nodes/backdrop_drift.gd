class_name BackdropDrift
extends Node2D
## Grupo de nuvens: no jogo, cada filho desliza na horizontal (`speed`, px/s) e reaparece do
## outro lado quando sai totalmente da faixa [wrap_left, wrap_right] — fora da tela, sem salto
## visível. Uma oscilação vertical mínima evita o ar mecânico. No editor nada se move:
## posicione cada nuvem livremente.

@export var speed := 3.0
@export var wrap_left := -420.0
@export var wrap_right := 2092.0
## Oscilação vertical (px) e período (s).
@export var bob := 1.5
@export var bob_period := 23.0

var global_intensity := 1.0
var moon_center := Vector2.ZERO
var moon_radius := 70.0
var _t := 0.0
var _base_y: Dictionary = {}


func _ready() -> void:
	add_to_group(BackdropAnimated.GROUP)
	for c in get_children():
		if c is Node2D:
			_base_y[c] = c.position.y


func _process(delta: float) -> void:
	if not BackdropAnimated.running():
		return
	_t += delta * global_intensity
	var span := wrap_right - wrap_left
	for c in get_children():
		if not c is Node2D:
			continue
		var n := c as Node2D
		n.position.x = wrap_left + fposmod(n.position.x + speed * delta * global_intensity - wrap_left, span)
		var phase := float(n.get_index()) * 1.9
		n.position.y = _base_y.get(n, n.position.y) + sin(TAU * _t / bob_period + phase) * bob
		if n is BackdropCloud:
			(n as BackdropCloud).moon_light = 1.0 - smoothstep(moon_radius * 1.2, moon_radius * 4.0, _local_dist(n))


func _local_dist(n: Node2D) -> float:
	# distância no espaço da arte (ancestral ArenaBackdrop), sem depender da escala da tela
	return (position + n.position - moon_center).length()
