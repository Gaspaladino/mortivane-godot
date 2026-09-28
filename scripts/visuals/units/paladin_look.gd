class_name PaladinLook
extends Resource
## Parâmetros visuais do Paladino, editáveis no Inspector (data/visuals/paladin_look.tres).
## O PaladinVisual lê este recurso via UnitDef.visual_look; a versão Sombra usa o mesmo e
## converte as cores pela regra ShadowStyle (o dourado é preservado).
## Só apresentação: nada aqui muda stats nem colisão.

@export_group("Escala e posições")
## Escala do desenho (1 = ~41 unidades do mundo de altura, ~14% maior que o Guerreiro).
@export_range(0.6, 1.6, 0.01) var scale := 1.0
## Deslocamento do escudo em relação à mão (unidades do rig; +x = para frente).
@export var shield_offset := Vector2.ZERO
## Deslocamento da espada em relação à mão.
@export var sword_offset := Vector2.ZERO

@export_group("Cores (versão viva)")
@export var ivory := Color("e6ddca")
@export var ivory_light := Color("fff3dd")
@export var steel_shade := Color("9b948a")
@export var under_armor := Color("2a2833")
@export var gold := Color("d9ad52")
@export var gold_light := Color("ffe39a")
@export var cloth := Color("f1ead8")
@export var cape := Color("c7bea9")
@export var blade := Color("dfe4ea")
@export var holy_light := Color("fff0b3")

@export_group("Brilho e animação")
## Força dos efeitos sagrados (auréola, rastro do golpe, barreira, anel da provocação).
@export_range(0.0, 2.0, 0.05) var glow := 1.0
## Mostra o anel do raio de provocação (HTML: ring no raio de 115) quando provoca.
@export var show_taunt_ring := true
## Velocidade das animações secundárias (capa, respiração, brilho da auréola).
@export_range(0.2, 3.0, 0.05) var secondary_speed := 1.0

static var _default: PaladinLook


static func get_default() -> PaladinLook:
	if _default == null:
		_default = load("res://data/visuals/paladin_look.tres") if ResourceLoader.exists("res://data/visuals/paladin_look.tres") else PaladinLook.new()
	return _default
