class_name Arena
extends Node2D
## Arena: enquadra o mundo 1000×560 na janela e ajusta o fundo.
##
## Camadas (de trás para frente):
##   Background — fundo animado (ArenaBackdrop, camadas recriadas da arte); nunca recebe
##                tremor de tela nem efeitos de gameplay.
##   Stage/World — gameplay (Ground, Entities com y-sort). Futuro tremor vai em Stage.
##   Stage/Effects — efeitos visuais do gameplay.
##   Debug — sobreposição de referência (atalho F3 tratado em Main).
##   Battle — executor do combate (CombatSim + UnitView em Stage/World/Entities).
##            A Arena não decide quem luta: o modo que a usa (Sandbox) chama battle.spawn/start/clear.

@onready var camera: Camera2D = $Camera2D
@onready var backdrop: ArenaBackdrop = $Background/Backdrop
@onready var debug_overlay: DebugOverlay = $Debug
@onready var battle: Battle = $Battle

## Parte do mundo visível na janela atual (coordenadas do mundo).
var visible_world_rect := Rect2(Vector2.ZERO, WorldConfig.SIZE)
## Faixa inferior da tela ocupada por interface (unidades do viewport). O mundo é enquadrado
## na área acima dela (com zoom < 1 se preciso); o fundo continua cobrindo a tela toda.
var bottom_inset := 0.0


func _ready() -> void:
	get_viewport().size_changed.connect(_update_framing)
	_update_framing()


func set_debug_visible(value: bool) -> void:
	debug_overlay.set_shown(value)


func is_debug_visible() -> bool:
	return debug_overlay.visible


func set_bottom_inset(value: float) -> void:
	bottom_inset = maxf(0.0, value)
	_update_framing()


func _update_framing() -> void:
	var view_size := get_viewport().get_visible_rect().size
	# Área útil acima da interface; se ela ficar mais baixa que o mínimo (490), afasta a câmera.
	var usable_h := maxf(1.0, view_size.y - bottom_inset)
	var zoom := minf(1.0, usable_h / WorldConfig.MIN_VISIBLE_HEIGHT)
	camera.zoom = Vector2(zoom, zoom)
	var usable_world_h := usable_h / zoom

	# Centraliza o mundo na área útil; se ela for baixa demais, corta 80% do céu e 20% do rodapé.
	var center_y := WorldConfig.HEIGHT / 2.0
	if usable_world_h < WorldConfig.HEIGHT:
		center_y = (WorldConfig.HEIGHT - usable_world_h) * WorldConfig.TOP_CROP_SHARE + usable_world_h / 2.0
	# o centro da área útil fica bottom_inset/2 acima do centro da tela
	camera.position = Vector2(WorldConfig.WIDTH / 2.0, center_y + bottom_inset / 2.0 / zoom)
	var world_view := view_size / zoom
	visible_world_rect = Rect2(camera.position - world_view / 2.0, world_view)

	_fit_background(visible_world_rect)
	debug_overlay.set_frame(visible_world_rect, get_window().size)


## Replica o HTML V68: uma caixa 1000:560 cobre a tela inteira (cover), ancorada
## ao mundo em y ≈ 380 e presa para nunca deixar faixa vazia. A textura cobre a caixa
## sem distorção, centralizada.
func _fit_background(view: Rect2) -> void:
	var tex_size := backdrop.art_size
	var box_w := maxf(view.size.x, view.size.y * WorldConfig.WIDTH / WorldConfig.HEIGHT)
	var box_h := box_w * WorldConfig.HEIGHT / WorldConfig.WIDTH
	var box_left := view.position.x + (view.size.x - box_w) / 2.0
	var box_top := (WorldConfig.HEIGHT - box_h) * (WorldConfig.ART_ANCHOR_Y / WorldConfig.HEIGHT)
	box_top = clampf(box_top, view.end.y - box_h, view.position.y)

	var k := maxf(box_w / tex_size.x, box_h / tex_size.y)
	var draw_size := tex_size * k
	backdrop.scale = Vector2(k, k)
	backdrop.position = Vector2(box_left, box_top) + (Vector2(box_w, box_h) - draw_size) / 2.0
