class_name ArenaBackdrop
extends Node2D
## Fundo da arena (cena arena_backdrop.tscn). Cada elemento é um nó próprio, editável no
## editor: montanhas, torres e ruínas são Polygon2D; nuvens, lua, janelas e chamas são nós
## @tool desenhados por código (aparecem no editor); névoa e céu são ColorRect com shader.
## Cada nó animado tem sua própria velocidade/força no Inspector.
##
## Este script só coordena:
##   - intensidade global (`master_intensity`, `animated`) para todos os nós do grupo
##     "backdrop_animated";
##   - a posição da lua para a borda prateada das nuvens;
##   - parallax: cada grupo filho com metadado `parallax_depth` (0 = infinito, 1 = acompanha a
##     arena) é deslocado por `view_offset × (1 − profundidade)` a partir da posição do editor.
##
## Espaço local = pixels da arte (1672×941). A Arena escala/posiciona este nó (cover).

@export var animated := true
@export_range(0.0, 2.0, 0.05) var master_intensity := 1.0
## Deslocamento da vista (px da arte), para uma câmera futura.
@export var view_offset := Vector2.ZERO
## Só para visualizar o parallax sem câmera: amplitude (px) de um vaivém lento. 0 = desligado.
@export var parallax_preview := 0.0

var art_size := Vector2(ArenaLayersData.DATA.size[0], ArenaLayersData.DATA.size[1])
var time := 0.0

@onready var moon: BackdropMoon = $Moon

var _base_pos: Dictionary = {}


func _ready() -> void:
	for layer in parallax_layers():
		_base_pos[layer] = layer.position
	_apply()


func _process(delta: float) -> void:
	if animated:
		time += delta
	_apply()


## Grupos com profundidade de parallax, na ordem de desenho.
func parallax_layers() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for c in get_children():
		if c is Node2D and c.has_meta(&"parallax_depth"):
			out.append(c)
	return out


func _apply() -> void:
	var k := master_intensity if animated else 0.0
	for n in get_tree().get_nodes_in_group(BackdropAnimated.GROUP):
		if is_ancestor_of(n):
			n.global_intensity = k
	for drift in find_children("*", "BackdropDrift", false, false):
		drift.moon_center = moon.position
		drift.moon_radius = moon.radius
	var offset := view_offset
	if parallax_preview > 0.0:
		offset += Vector2(sin(time * 0.25) * parallax_preview, 0.0)
	for layer in _base_pos:
		layer.position = _base_pos[layer] + offset * (1.0 - float(layer.get_meta(&"parallax_depth")))
