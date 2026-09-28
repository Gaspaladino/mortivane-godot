class_name ArenaBackdrop
extends Node2D
## Fundo da arena RECONSTRUÍDO do zero no Godot, em camadas, com animações sutis.
## Só o primeiro plano vem da arte antiga (chão/muro e elementos laterais: pilares, árvores,
## estandartes, velas — extraídos por tools/arena_backdrop/build_layers.py). Todo o resto é
## desenhado aqui: céu, lua e nuvens em shader; montanhas, castelo e ruínas por código.
##
## Espaço local = pixels da arte (1672×941). A Arena escala/posiciona este nó (cover).
##
## Camadas (de trás para frente) e profundidade de parallax (0 = infinito, 1 = acompanha a arena):
##   SkyLayer 0 · MoonLayer 0,03 · FarCloudLayer 0,06 · MidCloudLayer 0,12 · MountainBackLayer 0,2
##   FogLayerFar 0,25 · MountainFrontLayer 0,35 · CastleLayer 0,45 · RuinsLayer 0,5 · FogLayerMid 0,55
##   FogLayerNear 0,7 · SideElementsLayer 0,95 · ArenaLayer 1
##
## Movimento: nuvens (esquerda→direita, a distante mais lenta) · neblina (a do meio no sentido
## contrário) · estandartes (pendular, pesado) · velas (chama calma) · janelas do castelo
## (acendem/apagam devagar, uma a uma) · lua (pulsação de brilho quase imperceptível) · estrelas
## (poucas, cintilando devagar). Montanhas, castelo, ruínas e o CHÃO não se mexem.

## Liga/desliga todas as animações (o quadro congela).
@export var animated := true
## Multiplica todas as intensidades de animação (0 = nada se mexe nem pulsa).
@export_range(0.0, 2.0, 0.05) var master_intensity := 1.0

@export_group("Lua")
@export var moon_center := Vector2(1228, 92)
@export var moon_radius := 66.0
@export_range(0.0, 3.0, 0.05) var moon_pulse := 1.0
@export_range(0.0, 2.0, 0.05) var moon_glow := 1.0

@export_group("Céu")
@export_range(0.0, 2.0, 0.05) var stars := 1.0

@export_group("Nuvens")
@export_range(0.0, 4.0, 0.05) var clouds_speed := 1.0
@export_range(0.0, 2.0, 0.05) var clouds_opacity := 1.0

@export_group("Neblina")
@export_range(0.0, 4.0, 0.05) var fog_speed := 1.0
@export_range(0.0, 2.0, 0.05) var fog_opacity := 1.0

@export_group("Castelo")
@export_range(0.0, 2.0, 0.05) var castle_lights := 1.0
@export_range(0.0, 4.0, 0.05) var castle_lights_speed := 1.0

@export_group("Estandartes")
@export_range(0.0, 3.0, 0.05) var banner_strength := 1.0
@export_range(0.0, 3.0, 0.05) var banner_speed := 1.0

@export_group("Velas")
@export_range(0.0, 2.0, 0.05) var candle_strength := 1.0
@export_range(0.0, 3.0, 0.05) var candle_speed := 1.0

@export_group("Parallax")
## Deslocamento da vista (px da arte) — para uma câmera futura. Cada camada compensa pela profundidade.
@export var view_offset := Vector2.ZERO
## Só para pré-visualizar o parallax sem câmera: amplitude (px) de um vaivém lento. 0 = desligado.
@export var parallax_preview := 0.0

const DEPTHS := {
	SkyLayer = 0.0, MoonLayer = 0.03, FarCloudLayer = 0.06, MidCloudLayer = 0.12, MountainBackLayer = 0.2,
	FogLayerFar = 0.25, MountainFrontLayer = 0.35, CastleLayer = 0.45, RuinsLayer = 0.5, FogLayerMid = 0.55,
	FogLayerNear = 0.7, SideElementsLayer = 0.95, ArenaLayer = 1.0,
}
## Valores de base (multiplicados pelas propriedades acima).
const BASE := {
	far_clouds = 0.55, mid_clouds = 0.9, fog_far = 0.32, fog_mid = 0.26, fog_near = 0.3,
	banner_amp = 2.4, candle_add = 0.35, stars = 0.35, moon_pulse = 0.035,
}

var art_size := Vector2(ArenaLayersData.DATA.size[0], ArenaLayersData.DATA.size[1])
var time := 0.0

@onready var sky: ColorRect = $SkyLayer/Sky
@onready var moon: ColorRect = $MoonLayer/Moon
@onready var far_clouds: ColorRect = $FarCloudLayer/Clouds
@onready var mid_clouds: ColorRect = $MidCloudLayer/Clouds
@onready var mountains_back: MountainLayer = $MountainBackLayer
@onready var mountains_front: MountainLayer = $MountainFrontLayer
@onready var castle: CastleLayer = $CastleLayer
@onready var castle_window_lights: CastleLights = $CastleLayer/CastleLights
@onready var ruins: RuinsLayer = $RuinsLayer
@onready var fog_far: ColorRect = $FogLayerFar/Fog
@onready var fog_mid: ColorRect = $FogLayerMid/Fog
@onready var fog_near: ColorRect = $FogLayerNear/Fog
@onready var banners: Array[Sprite2D] = [$SideElementsLayer/BannerLeft, $SideElementsLayer/BannerRight]
@onready var candles: Array[Sprite2D] = [$SideElementsLayer/CandlesLeft, $SideElementsLayer/CandlesRight]
@onready var candle_flames: CandleFlames = $SideElementsLayer/CandleFlames


func _ready() -> void:
	var data := ArenaLayersData.DATA
	for rect in [sky, far_clouds, mid_clouds, fog_far, fog_mid, fog_near]:
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_param(rect, "rect_origin", rect.position)
		_param(rect, "rect_size", rect.size)
	moon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place_moon()
	var sides := ["left", "right"]
	for i in 2:
		var b: Dictionary = data.banners[sides[i]]
		banners[i].position = Vector2(b.pos[0], b.pos[1])
		_param(banners[i], "tex_size", Vector2(b.size[0], b.size[1]))
		_param(banners[i], "top_px", float(b.top))
		var c: Dictionary = data.candles[sides[i]]
		candles[i].position = Vector2(c.pos[0], c.pos[1])
		for f in c.flames:
			candle_flames.flames.append([Vector2(f[0], f[1]), float(f[2])])
	castle_window_lights.setup(castle.window_rects())
	_apply()


func _process(delta: float) -> void:
	if animated:
		time += delta
	_apply()


## Lua (e quem depende da posição dela: céu, nuvens, luz de borda das silhuetas).
func _place_moon() -> void:
	moon.size = Vector2.ONE * moon_radius * 4.0
	moon.position = moon_center - moon.size / 2.0
	_param(sky, "moon_center", moon_center)
	for rect in [far_clouds, mid_clouds]:
		_param(rect, "moon_center", moon_center)
		_param(rect, "moon_radius", moon_radius)
	for layer in [mountains_back, mountains_front, castle, ruins]:
		layer.moon_center = moon_center


func _apply() -> void:
	var k := master_intensity if animated else 0.0
	var t := time
	_param(sky, "t", t)
	_param(sky, "star_amount", BASE.stars * stars)
	_param(moon, "t", t)
	_param(moon, "pulse_amount", BASE.moon_pulse * moon_pulse * k)
	_param(moon, "halo_strength", 0.55 * moon_glow)
	_param(far_clouds, "t", t * clouds_speed * k)
	_param(far_clouds, "opacity", BASE.far_clouds * clouds_opacity)
	_param(mid_clouds, "t", t * clouds_speed * k)
	_param(mid_clouds, "opacity", BASE.mid_clouds * clouds_opacity)
	_param(fog_far, "t", t * fog_speed * k)
	_param(fog_far, "opacity", BASE.fog_far * fog_opacity)
	_param(fog_mid, "t", t * fog_speed * k)
	_param(fog_mid, "opacity", BASE.fog_mid * fog_opacity)
	_param(fog_near, "t", t * fog_speed * k)
	_param(fog_near, "opacity", BASE.fog_near * fog_opacity)
	castle_window_lights.t = t * castle_lights_speed
	castle_window_lights.intensity = castle_lights
	castle_window_lights.queue_redraw()
	for b in banners:
		_param(b, "t", t * banner_speed)
		_param(b, "amp", BASE.banner_amp * banner_strength * k)
	for c in candles:
		_param(c, "t", t * candle_speed)
		_param(c, "strength", BASE.candle_add * candle_strength)
	candle_flames.t = t * candle_speed * (1.0 if k > 0.0 else 0.0)
	candle_flames.intensity = candle_strength
	candle_flames.queue_redraw()
	_apply_parallax(t)


func _apply_parallax(t: float) -> void:
	var offset := view_offset
	if parallax_preview > 0.0:
		offset += Vector2(sin(t * 0.25) * parallax_preview, 0.0)
	for layer_name in DEPTHS:
		var layer := get_node_or_null(NodePath(layer_name)) as Node2D
		if layer:
			layer.position = offset * (1.0 - float(DEPTHS[layer_name]))


static func _param(ci: CanvasItem, name: StringName, value: Variant) -> void:
	(ci.material as ShaderMaterial).set_shader_parameter(name, value)
