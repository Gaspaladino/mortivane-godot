class_name Arena
extends Node2D
## Arena: enquadra o mundo 1000×560 na janela e ajusta o fundo.
##
## Camadas (de trás para frente):
##   Background — arte fixa; nunca recebe tremor de tela nem efeitos de gameplay.
##   Stage/World — gameplay (Ground, Entities com y-sort). Futuro tremor vai em Stage.
##   Stage/Effects — efeitos visuais do gameplay.
##   Debug — sobreposição de referência (atalho F3 tratado em Main).

@onready var camera: Camera2D = $Camera2D
@onready var arena_art: Sprite2D = $Background/ArenaArt
@onready var debug_overlay: DebugOverlay = $Debug

## Parte do mundo visível na janela atual (coordenadas do mundo).
var visible_world_rect := Rect2(Vector2.ZERO, WorldConfig.SIZE)


func _ready() -> void:
	get_viewport().size_changed.connect(_update_framing)
	_update_framing()


func set_debug_visible(value: bool) -> void:
	debug_overlay.set_shown(value)


func is_debug_visible() -> bool:
	return debug_overlay.visible


func _update_framing() -> void:
	var view_size := get_viewport().get_visible_rect().size

	# Centraliza o mundo; se a janela for larga demais, corta 80% do céu e 20% do rodapé.
	var center_y := WorldConfig.HEIGHT / 2.0
	if view_size.y < WorldConfig.HEIGHT:
		center_y = (WorldConfig.HEIGHT - view_size.y) * WorldConfig.TOP_CROP_SHARE + view_size.y / 2.0
	camera.position = Vector2(WorldConfig.WIDTH / 2.0, center_y)
	visible_world_rect = Rect2(camera.position - view_size / 2.0, view_size)

	_fit_background(visible_world_rect)
	debug_overlay.set_frame(visible_world_rect, get_window().size)


## Replica o HTML V68: uma caixa 1000:560 cobre a tela inteira (cover), ancorada
## ao mundo em y ≈ 380 e presa para nunca deixar faixa vazia. A textura cobre a caixa
## sem distorção, centralizada.
func _fit_background(view: Rect2) -> void:
	var tex_size := arena_art.texture.get_size()
	var box_w := maxf(view.size.x, view.size.y * WorldConfig.WIDTH / WorldConfig.HEIGHT)
	var box_h := box_w * WorldConfig.HEIGHT / WorldConfig.WIDTH
	var box_left := view.position.x + (view.size.x - box_w) / 2.0
	var box_top := (WorldConfig.HEIGHT - box_h) * (WorldConfig.ART_ANCHOR_Y / WorldConfig.HEIGHT)
	box_top = clampf(box_top, view.end.y - box_h, view.position.y)

	var k := maxf(box_w / tex_size.x, box_h / tex_size.y)
	var draw_size := tex_size * k
	arena_art.scale = Vector2(k, k)
	arena_art.position = Vector2(box_left, box_top) + (Vector2(box_w, box_h) - draw_size) / 2.0
