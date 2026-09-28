class_name ShadowStyle
extends Resource
## Regra visual do projeto para unidades revividas pelo necromante ("sombras"):
##   versão viva  = paleta normal da classe;
##   versão sombra = a MESMA paleta convertida por convert(): corpo puxado para preto/grafite
##                   violeta, conservando só um resto do tom original (a classe continua
##                   reconhecível), mais a energia roxa do necromante (contornos, fissuras,
##                   olhos, fumaça, aura).
## Acentos que definem a classe (ouro de paladino, runas arcanas, selo sagrado…) passam por
## convert(cor, keep) com `keep` > 0: escurecem menos e mantêm o matiz.
##
## Um único recurso (data/visuals/shadow_style.tres) vale para todas as sombras; uma UnitDef
## pode apontar outro em `shadow_style` para variar (ex.: sombra de elite).
## Os efeitos que usam estes valores ficam em ShadowFX.

const DEFAULT_PATH := "res://data/visuals/shadow_style.tres"

@export_group("Corpo")
## Tom mais escuro do corpo (partes escuras da viva caem aqui).
@export var body_dark := Color("0c0a12")
## Tom mais claro do corpo (partes claras da viva caem aqui).
@export var body_light := Color("564c70")
## Quanto do matiz/tom original sobrevive (0 = só grafite violeta).
@export_range(0.0, 1.0, 0.01) var keep_hue := 0.14
## Contorno interno das peças (violeta quase preto: mantém os detalhes legíveis).
@export var edge := Color("1c1030")
@export_range(0.5, 2.5, 0.05) var edge_width := 1.0
## Borda roxa só na silhueta externa (separa a unidade do chão e do fundo).
@export var rim := Color(0.58, 0.3, 0.95, 0.9)
@export_range(0.0, 2.0, 0.05) var rim_width := 0.75

@export_group("Energia necromântica")
@export var energy := Color("a95dff")
@export var energy_core := Color("f1e0ff")
@export var eye := Color("e9ccff")
## Fumaça/aura (a alfa é a opacidade máxima).
@export var smoke := Color(0.46, 0.22, 0.78, 0.5)

@export_group("Intensidades")
@export_range(0.0, 2.0, 0.05) var aura := 1.0
@export_range(0.0, 2.0, 0.05) var smoke_amount := 1.0
@export_range(0.0, 2.0, 0.05) var cracks := 1.0
## Velocidade da pulsação das fissuras e dos olhos.
@export_range(0.1, 3.0, 0.05) var pulse_speed := 1.0

static var _default: ShadowStyle


static func get_default() -> ShadowStyle:
	if _default == null:
		_default = load(DEFAULT_PATH) if ResourceLoader.exists(DEFAULT_PATH) else ShadowStyle.new()
	return _default


## Converte uma cor da versão viva para a versão sombra. `keep` (0..1) preserva acentos da
## classe: 0 = corpo sombrio; 1 = acento (escurecido, mas com o matiz original).
func convert(c: Color, keep := 0.0) -> Color:
	var l := clampf(c.get_luminance(), 0.0, 1.0)
	var base := body_dark.lerp(body_light, pow(l, 0.8))
	var accent := Color(c.r * 0.72, c.g * 0.66, c.b * 0.82)   # original levemente frio e escuro
	var out := base.lerp(accent, clampf(keep_hue + keep * (0.85 - keep_hue), 0.0, 1.0))
	out.a = c.a
	return out
