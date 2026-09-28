class_name ArenaBackdrop
extends Node2D
## Fundo animado da arena, recriado em camadas a partir da própria arte (novocenario.png).
## As camadas foram separadas por tools/arena_backdrop/build_layers.py; as animações são
## nativas (shaders + script), sem vídeo nem sprite sheet.
##
## Espaço local = pixels da arte (1672×941). A Arena escala/posiciona este nó (cover), como
## fazia com o Sprite2D estático; o enquadramento não mudou.
##
## Camadas (de trás para frente):
##   Sky           a arte original: céu, lua e nuvens pintadas (fluem devagar; a lua respira)
##   MoonHalo      halo aditivo da lua (pulsa e deriva quase nada)
##   CloudsFar     nuvens procedurais distantes (lentas, menores, mais ralas)
##   CloudsNear    nuvens procedurais próximas (mais rápidas, maiores) — parallax
##   Scenery       tudo que não é céu: montanhas, castelos, ruínas, árvores e o CHÃO (estático)
##   CastleLights  luzes roxas do castelo pulsando/tremulando
##   FogBack/Front neblina fria no vale, duas velocidades (atrás do muro de ruínas)
##   BannerLeft/Right  estandartes recortados, balançando a partir da haste
##   CandlesLeft/Right chamas e reflexos das velas tremulando
##   CandleGlows   halos das velas (um por chama, oscilando)
##
## O chão e a área de combate não têm nenhuma animação: nada compete com as tropas.
## Intensidades/velocidades: propriedades exportadas abaixo (Inspector ou código).

## Liga/desliga todas as animações (desligado = o quadro fica parado, como a arte original).
@export var animated := true
## Multiplica todas as intensidades (0 = fundo estático idêntico à arte).
@export_range(0.0, 2.0, 0.05) var master_intensity := 1.0

@export_group("Nuvens")
@export_range(0.0, 4.0, 0.05) var clouds_speed := 1.0
@export_range(0.0, 2.0, 0.05) var clouds_opacity := 1.0
## Deslocamento das nuvens pintadas da arte (px).
@export_range(0.0, 3.0, 0.05) var painted_clouds_flow := 1.0

@export_group("Neblina")
@export_range(0.0, 4.0, 0.05) var fog_speed := 1.0
@export_range(0.0, 2.0, 0.05) var fog_opacity := 1.0

@export_group("Estandartes")
@export_range(0.0, 3.0, 0.05) var banner_strength := 1.0
@export_range(0.0, 3.0, 0.05) var banner_speed := 1.0

@export_group("Velas")
@export_range(0.0, 2.0, 0.05) var candle_strength := 1.0
@export_range(0.0, 3.0, 0.05) var candle_speed := 1.0

@export_group("Castelo")
@export_range(0.0, 2.0, 0.05) var castle_strength := 1.0
@export_range(0.0, 3.0, 0.05) var castle_speed := 1.0

@export_group("Lua")
@export_range(0.0, 3.0, 0.05) var moon_strength := 1.0

## Valores de base de cada material (multiplicados pelas propriedades acima).
const BASE := {
	sky_flow = 7.0, moon_pulse = 0.05,
	clouds_far_opacity = 0.22, clouds_near_opacity = 0.3,
	fog_back_opacity = 0.18, fog_front_opacity = 0.16,
	banner_amp = 2.6, candle_strength = 0.7, castle_strength = 0.45,
	halo_alpha = 0.2,
}
const HALO_SIZE := 3.4        # diâmetro do halo em raios da lua
const CANDLE_GLOW_SCALE := 2.4

var art_size := Vector2(ArenaLayersData.DATA.size[0], ArenaLayersData.DATA.size[1])
var time := 0.0

@onready var sky: Sprite2D = $Sky
@onready var moon_halo: Sprite2D = $MoonHalo
@onready var clouds_far: ColorRect = $CloudsFar
@onready var clouds_near: ColorRect = $CloudsNear
@onready var scenery: Sprite2D = $Scenery
@onready var castle_lights: ColorRect = $CastleLights
@onready var fog_back: ColorRect = $FogBack
@onready var fog_front: ColorRect = $FogFront
@onready var banners: Array[Sprite2D] = [$BannerLeft, $BannerRight]
@onready var candles: Array[Sprite2D] = [$CandlesLeft, $CandlesRight]
@onready var candle_glows: Node2D = $CandleGlows

var _glows: Array[Sprite2D] = []
var _glow_base: Array[float] = []
var _moon_center: Vector2
var _moon_radius: float


func _ready() -> void:
	var data := ArenaLayersData.DATA
	_moon_center = Vector2(data.moon.center[0], data.moon.center[1])
	_moon_radius = data.moon.radius
	for rect in [clouds_far, clouds_near, castle_lights, fog_back, fog_front]:
		rect.size = art_size
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for mat_owner in [sky, clouds_far, clouds_near, castle_lights, fog_back, fog_front]:
		var mat: ShaderMaterial = mat_owner.material
		mat.set_shader_parameter("art_size", art_size)
	for mat_owner in [sky, clouds_far, clouds_near]:
		mat_owner.material.set_shader_parameter("moon_center", _moon_center)
		mat_owner.material.set_shader_parameter("moon_radius", _moon_radius)
	var sides := ["left", "right"]
	for i in 2:
		var b: Dictionary = data.banners[sides[i]]
		banners[i].position = Vector2(b.pos[0], b.pos[1])
		banners[i].material.set_shader_parameter("tex_size", Vector2(b.size[0], b.size[1]))
		banners[i].material.set_shader_parameter("top_px", float(b.top))
		var c: Dictionary = data.candles[sides[i]]
		candles[i].position = Vector2(c.pos[0], c.pos[1])
		for light in c.lights:
			_add_candle_glow(Vector2(light[0], light[1]), float(light[2]))
	var halo_px := _moon_radius * HALO_SIZE
	moon_halo.position = _moon_center
	moon_halo.scale = Vector2.ONE * halo_px / moon_halo.texture.get_width()
	_apply(0.0)


func _process(delta: float) -> void:
	if animated:
		time += delta
	_apply(delta)


## Aplica tempo e intensidades a todas as camadas.
func _apply(_delta: float) -> void:
	var k := master_intensity if animated else 0.0
	var t := time
	_param(sky, "t", t)
	_param(sky, "flow_amp", BASE.sky_flow * painted_clouds_flow * k)
	_param(sky, "moon_pulse", BASE.moon_pulse * moon_strength * k)
	_param(clouds_far, "t", t * clouds_speed)
	_param(clouds_far, "opacity", BASE.clouds_far_opacity * clouds_opacity * k)
	_param(clouds_near, "t", t * clouds_speed)
	_param(clouds_near, "opacity", BASE.clouds_near_opacity * clouds_opacity * k)
	_param(fog_back, "t", t * fog_speed)
	_param(fog_back, "opacity", BASE.fog_back_opacity * fog_opacity * k)
	_param(fog_front, "t", t * fog_speed)
	_param(fog_front, "opacity", BASE.fog_front_opacity * fog_opacity * k)
	_param(castle_lights, "t", t * castle_speed)
	_param(castle_lights, "strength", BASE.castle_strength * castle_strength * k)
	for b in banners:
		_param(b, "t", t * 1.35 * banner_speed)
		_param(b, "amp", BASE.banner_amp * banner_strength * k)
	for c in candles:
		_param(c, "t", t * candle_speed)
		_param(c, "strength", BASE.candle_strength * candle_strength * k)
	# lua: halo respira devagar e deriva menos de 1 px
	var breath := 0.5 + 0.5 * sin(t * 0.45)
	moon_halo.modulate.a = BASE.halo_alpha * (0.8 + 0.4 * breath) * moon_strength * k
	moon_halo.position = _moon_center + Vector2(sin(t * 0.05), cos(t * 0.04)) * 0.6 * k
	# halos das velas: cada um com seu ritmo
	for i in _glows.size():
		var s := float(i) * 1.71
		var f := 0.62 + 0.22 * sin(t * 9.0 * candle_speed + s) + 0.16 * sin(t * 14.3 * candle_speed + s * 2.3)
		_glows[i].modulate.a = clampf(f, 0.0, 1.0) * 0.55 * candle_strength * k
		var sc := _glow_base[i] * (1.0 + 0.06 * sin(t * 7.3 * candle_speed + s) * k)
		_glows[i].scale = Vector2(sc, sc)


func _add_candle_glow(pos: Vector2, size: float) -> void:
	var glow := Sprite2D.new()
	glow.name = "Glow%d" % _glows.size()
	glow.texture = moon_halo.texture
	glow.material = moon_halo.material     # aditivo
	glow.self_modulate = Color(0.72, 0.42, 1.0)
	glow.position = pos
	var base := size * CANDLE_GLOW_SCALE / glow.texture.get_width()
	glow.scale = Vector2(base, base)
	candle_glows.add_child(glow)
	_glows.append(glow)
	_glow_base.append(base)


static func _param(ci: CanvasItem, param: StringName, value: Variant) -> void:
	(ci.material as ShaderMaterial).set_shader_parameter(param, value)
