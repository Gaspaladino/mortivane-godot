class_name PaladinRigLook
extends Resource
## Parâmetros do Paladino Vivo 2.5D, editáveis no Inspector (data/visuals/paladin_rig_look.tres).
## Só apresentação: nada aqui muda stats, alcance, colisão ou tempos da simulação.

@export_group("Corpo")
## Unidades do mundo por unidade do rig (0,5 → elmo a ~47 unidades do chão; Guerreiro ~35).
@export_range(0.2, 1.0, 0.005) var scale := 0.5
## Largura do tronco/pelve e distância entre os ombros e os quadris.
@export_range(0.7, 1.4, 0.01) var body_width := 1.0
## Altura do tronco (pelve → pescoço).
@export_range(0.8, 1.25, 0.01) var body_height := 1.0
@export_range(0.7, 1.4, 0.01) var head_scale := 0.97
## Largura dos ombros e tamanho das ombreiras.
@export_range(0.7, 1.4, 0.01) var shoulder_width := 1.0
## Inclinação da câmera (rad): quanto se vê de cima (ombros, auréola, escudo em perspectiva).
@export_range(0.0, 0.8, 0.01) var view_tilt := 0.24
## Espessura do contorno escuro (unidades do rig).
@export_range(0.0, 2.0, 0.05) var outline_width := 0.75
## Degraus de luz nas facetas (mais = mais suave).
@export_range(2.0, 12.0, 1.0) var facet_steps := 5.0

@export_group("Escudo")
@export_range(0.6, 1.5, 0.01) var shield_scale := 1.0
## Deslocamento do escudo em relação ao punho esquerdo (unidades do rig; x = esquerda, z = frente).
@export var shield_offset := Vector3.ZERO
## Giro extra do escudo (graus, em torno do eixo vertical).
@export_range(-45.0, 45.0, 0.5) var shield_angle := 0.0

@export_group("Espada")
@export_range(0.6, 1.5, 0.01) var sword_scale := 1.0
@export var sword_offset := Vector3.ZERO
## Inclinação da lâmina em repouso (graus: + = ponta mais baixa).
@export_range(-60.0, 90.0, 0.5) var sword_rest_angle := 38.0

@export_group("Movimento")
## Segundos por ciclo de passada na velocidade de referência (44).
@export_range(0.6, 1.4, 0.01) var walk_cycle := 0.95
@export var walk_reference_speed := 44.0
## Amplitude da passada (balanço das pernas, rad).
@export_range(0.1, 0.9, 0.01) var stride := 0.42
## Quique vertical extra (o peso já vem da geometria das pernas).
@export_range(0.0, 3.0, 0.05) var vertical_bounce := 0.6
## Balanço dos braços e do tronco ao andar.
@export_range(0.0, 2.0, 0.05) var walk_amplitude := 1.0
## Atraso/inércia de espada, escudo, auréola (0 = rígido).
@export_range(0.0, 2.0, 0.05) var secondary_motion := 1.0
## Velocidade de giro do corpo (rad/s) entre direções.
@export_range(2.0, 30.0, 0.5) var turn_speed := 9.0

@export_group("Idle")
@export_range(0.0, 3.0, 0.05) var breathing := 1.0
## Segundos por ciclo do idle.
@export_range(1.2, 3.5, 0.05) var idle_cycle := 2.2

@export_group("Ataque")
## Quanto a espada recua na antecipação (1 = padrão).
@export_range(0.3, 1.6, 0.05) var windup := 1.0
## Rotação do quadril/tronco no golpe.
@export_range(0.3, 1.6, 0.05) var body_rotation := 1.0
## Abertura do arco da espada.
@export_range(0.5, 1.5, 0.05) var sword_arc := 1.0
@export_range(0.3, 1.6, 0.05) var follow_through := 1.0

@export_group("Tecido")
@export_range(0.0, 2.0, 0.05) var cloth_inertia := 1.0
@export_range(0.0, 2.0, 0.05) var cloth_amplitude := 1.0

@export_group("Efeitos")
@export_range(0.0, 2.0, 0.05) var glow := 1.0
@export_range(0.0, 2.0, 0.05) var block_flash := 1.0
@export_range(0.0, 2.0, 0.05) var taunt_intensity := 1.0
## Anel no raio real da provocação (115) quando provoca.
@export var show_taunt_ring := true
@export_range(0.0, 1.0, 0.05) var hit_flash := 0.55

@export_group("Cores (claro, médio, sombra)")
@export var outline := Color("1b1612")
@export var ivory := PackedColorArray([Color("f3ede0"), Color("d3c9b5"), Color("9b907c")])
@export var ivory_deep := PackedColorArray([Color("ddd4c2"), Color("bbb09b"), Color("857a66")])
@export var gold := PackedColorArray([Color("f8d35c"), Color("dca42c"), Color("9c6612")])
@export var dark := PackedColorArray([Color("4a4247"), Color("2e282c"), Color("1c171a")])
@export var brown := PackedColorArray([Color("a0705f"), Color("7a5242"), Color("50342a")])
@export var steel := PackedColorArray([Color("f2f5f8"), Color("c4cad2"), Color("878e99")])
@export var grip := PackedColorArray([Color("6a4630"), Color("47301f"), Color("2c1c12")])
@export var visor := Color("141012")
@export var wood := PackedColorArray([Color("80603f"), Color("5f452d"), Color("3f2d1e")])
@export var cloth := PackedColorArray([Color("f6f0e3"), Color("ddd3bf"), Color("a99d87")])
@export var cloth_back := PackedColorArray([Color("cdc3ae"), Color("aa9f89"), Color("7d7361")])
@export var glove := PackedColorArray([Color("3d3538"), Color("262023"), Color("161214")])
@export var holy_light := Color("fff2b8")

static var _default: PaladinRigLook


static func get_default() -> PaladinRigLook:
	if _default == null:
		var path := "res://data/visuals/paladin_rig_look.tres"
		_default = load(path) if ResourceLoader.exists(path) else PaladinRigLook.new()
	return _default


## [claro, médio, sombra] do material (PaladinModel.Mat).
func tones(mat: int) -> PackedColorArray:
	match mat:
		PaladinModel.Mat.IVORY:
			return ivory
		PaladinModel.Mat.IVORY_DEEP:
			return ivory_deep
		PaladinModel.Mat.GOLD:
			return gold
		PaladinModel.Mat.DARK:
			return dark
		PaladinModel.Mat.BROWN:
			return brown
		PaladinModel.Mat.STEEL:
			return steel
		PaladinModel.Mat.GRIP:
			return grip
		PaladinModel.Mat.VISOR:
			return PackedColorArray([visor, visor, visor])
		PaladinModel.Mat.WOOD:
			return wood
		PaladinModel.Mat.CLOTH:
			return cloth
		PaladinModel.Mat.CLOTH_BACK:
			return cloth_back
		PaladinModel.Mat.GLOVE:
			return glove
	return ivory
