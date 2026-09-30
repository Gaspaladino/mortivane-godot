class_name PaladinModel
extends RefCounted
## Modelo do Paladino Vivo para o rig 2.5D: ossos (pivôs e comprimentos) e peças (malhas low-poly
## presas a um osso). Construído uma vez e compartilhado por todos os Paladinos.
##
## Proporções tiradas das três referências oficiais (unidades do rig "u"; pés em y = 0):
##   elmo 70 → 93 (grande, heroico: ~1/4 da altura) · auréola até ~106 · ombreiras largas (~56 u de
##   ponta a ponta) · peitoral 48 → 72 · cinto ~46 · tabardo até ~13 · escudo ~70 u de altura
##   (quase a altura do corpo até o ombro) · espada larga ~44 u de lâmina.
## Espaço do corpo: x = ESQUERDA do personagem, y = cima, z = frente. Lado direito = x negativo:
## BRAÇO DIREITO = espada, BRAÇO ESQUERDO = escudo (a regra vale em qualquer direção — o corpo gira,
## nunca espelha).

enum Mat { IVORY, GOLD, DARK, BROWN, STEEL, GRIP, VISOR, WOOD, CLOTH, CLOTH_BACK, IVORY_DEEP, GLOVE }

const RIGHT := -1.0   # sinal de x do lado direito do personagem
const LEFT := 1.0

# --- Esqueleto (pivôs em repouso, unidades do rig) -----------------------------------------
const PELVIS_Y := 47.0
const SPINE := Vector3(0, 3.5, 0)          # pelve → base do tronco
const NECK := Vector3(0, 22.0, 0.6)        # tronco → base do elmo
const SHOULDER := Vector3(17.2, 21.0, -0.8)   # tronco → ombro (x × lado)
const UPPER_ARM := 12.5
const FOREARM := 11.5
const HIP := Vector3(6.6, -2.5, 0.0)       # pelve → quadril (x × lado)
const THIGH := 19.2
const SHIN := 19.3
const TABARD_FRONT := Vector3(0, -0.6, 10.0)
const TABARD_BACK := Vector3(0, 1.5, -8.6)
const TABARD_SEG := 11.4

## Ordem dos ossos (pais antes dos filhos). "sword"/"shield" são os encaixes das armas.
const BONES: Array[StringName] = [
	&"pelvis", &"torso", &"head", &"halo",
	&"r_pauldron", &"r_upper", &"r_fore", &"r_hand", &"sword",
	&"l_pauldron", &"l_upper", &"l_fore", &"l_hand", &"shield",
	&"r_thigh", &"r_shin", &"r_foot", &"l_thigh", &"l_shin", &"l_foot",
	&"tab_f1", &"tab_f2", &"tab_f3", &"tab_b1", &"tab_b2", &"tab_b3",
]
## Cadeia semântica das armas: a espada SEMPRE pende da mão direita e o escudo do braço esquerdo.
const SWORD_CHAIN: Array[StringName] = [&"torso", &"r_upper", &"r_fore", &"r_hand", &"sword"]
const SHIELD_CHAIN: Array[StringName] = [&"torso", &"l_upper", &"l_fore", &"l_hand", &"shield"]


class Part:
	var name: StringName
	var bone: StringName
	var mesh: PaladinMesh
	var decals: Array = []
	## &"body", &"sword", &"shield", &"halo" (a auréola é desenhada à parte: é um anel).
	var kind := &"body"
	## Desloca o ponto de ordenação ao longo da frente do osso (+z local, unidades do rig): peças da
	## frente do corpo (+) passam à frente quando ele olha para a câmera e atrás quando está de costas.
	var bias := 0.0
	## Grupo de escala do Inspector (&"body" = tronco/pelve, &"head", &"shoulder", &"none").
	## Escudo e espada são escalados no próprio osso (PaladinRig.solve).
	var scale_group := &"none"

	func _init(p_name: StringName, p_bone: StringName, p_mesh: PaladinMesh, p_kind := &"body", p_bias := 0.0) -> void:
		name = p_name
		bone = p_bone
		mesh = p_mesh
		kind = p_kind
		bias = p_bias


static var _parts: Array = []


static func parts() -> Array:
	if _parts.is_empty():
		_parts = _build()
	return _parts


static func parts_of_kind(kind: StringName) -> Array:
	return parts().filter(func(p: Part) -> bool: return p.kind == kind)


# --- Construção das peças -------------------------------------------------------------------

static func _build() -> Array:
	var M := PaladinMesh
	var list: Array = []

	# PELVE: saia escura por baixo da armadura, faixas de placa (fraldão) e cinto marrom
	var skirt := M.lathe([[2.0, 9.0, 7.2], [-16.0, 12.4, 9.4]], 8, [Mat.DARK], -1, -1)
	list.append(_body(Part.new(&"skirt", &"pelvis", skirt, &"body", -0.6)))
	# túnica escura por baixo (aparece entre as pernas e dos lados do tabardo, até a canela)
	var robe := M.lathe([[-8.0, 9.0, 5.6], [-33.0, 11.2, 6.4]], 6, [Mat.DARK], -1, -1)
	list.append(Part.new(&"robe", &"pelvis", robe, &"body", -3.0))
	var hips := M.lathe([[4.5, 9.6, 7.6], [0.5, 10.6, 8.2], [-5.0, 11.8, 8.8]], 8, [Mat.IVORY, Mat.IVORY_DEEP], -1, -1)
	list.append(_body(Part.new(&"hip_plates", &"pelvis", hips)))
	var belt := M.lathe([[5.0, 9.8, 7.9], [2.6, 10.2, 8.2], [0.4, 10.0, 8.1]], 8, [Mat.BROWN, Mat.BROWN], -1, -1)
	var belt_part := Part.new(&"belt", &"pelvis", belt, &"body", 0.4)
	var buckle_z := 8.2 * cos(PI / 8.0) + 0.15
	belt_part.decals.append(M.MeshDecal.on_plane(M.circle(Vector2.ZERO, 3.0, 12), Vector3(0, 2.6, buckle_z), Vector3.RIGHT, Vector3.UP, Mat.GOLD, &"buckle"))
	belt_part.decals.append(M.MeshDecal.on_plane(M.circle(Vector2.ZERO, 1.6, 10), Vector3(0, 2.6, buckle_z + 0.05), Vector3.RIGHT, Vector3.UP, Mat.BROWN, &"buckle_hole"))
	list.append(_body(belt_part))

	# TRONCO: peitoral largo com quilha central (facetado), gola dourada, costas
	var chest_sections := []
	for s in [[0.0, 9.8, 7.6, 1.00], [4.0, 11.4, 8.6, 1.10], [8.4, 13.2, 9.4, 1.14], [8.8, 12.8, 9.0, 1.10], [9.6, 14.2, 10.2, 1.16], [15.0, 17.2, 11.0, 1.18], [19.5, 17.6, 10.2, 1.12], [22.6, 14.2, 8.4, 1.04], [24.2, 8.0, 6.2, 1.0]]:
		var poly := M.ellipse(8, s[1], s[2], false)   # vértice na frente = quilha do peitoral
		poly[0] = Vector2(0, s[2] * s[3])
		chest_sections.append([s[0], poly])
	var chest := M.loft(chest_sections, [Mat.IVORY_DEEP, Mat.IVORY_DEEP, Mat.DARK, Mat.GOLD, Mat.IVORY, Mat.IVORY, Mat.IVORY, Mat.GOLD], Mat.DARK, Mat.DARK)
	list.append(_body(Part.new(&"chest", &"torso", chest)))
	var gorget := M.lathe([[22.0, 6.4, 5.2], [26.0, 5.6, 4.6]], 8, [Mat.DARK], -1, -1)
	list.append(_body(Part.new(&"gorget", &"torso", gorget, &"body", -0.8)))

	# CABEÇA: elmo fechado hexagonal (face plana na frente), topo em ponta, visor em T
	var helm_rings := [[-1.0, 7.7, 7.9], [3.0, 8.5, 8.7], [11.5, 8.8, 9.0], [18.0, 8.6, 8.8], [21.6, 7.6, 7.8], [23.6, 5.4, 5.6], [24.6, 0.0, 0.0]]
	var helm := M.lathe(helm_rings, 6, [Mat.IVORY, Mat.IVORY, Mat.IVORY, Mat.IVORY, Mat.IVORY, Mat.IVORY], Mat.DARK, -1)
	var helm_part := Part.new(&"helmet", &"head", helm, &"body", 0.3)
	helm_part.scale_group = &"head"
	var fz := func(y: float) -> float:   # z da face frontal plana do elmo na altura y
		for i in helm_rings.size() - 1:
			var a: Array = helm_rings[i]
			var b: Array = helm_rings[i + 1]
			if y >= a[0] and y <= b[0]:
				return lerpf(a[2], b[2], (y - a[0]) / (b[0] - a[0])) * cos(PI / 6.0) + 0.12
		return 7.0
	var visor_gold := PackedVector2Array([Vector2(-6.4, 16.4), Vector2(6.4, 16.4), Vector2(6.4, 12.0), Vector2(2.0, 12.0),
		Vector2(2.0, 3.6), Vector2(-2.0, 3.6), Vector2(-2.0, 12.0), Vector2(-6.4, 12.0)])
	var visor_slit := PackedVector2Array([Vector2(-5.3, 15.3), Vector2(5.3, 15.3), Vector2(5.3, 13.1), Vector2(0.85, 13.1),
		Vector2(0.85, 4.8), Vector2(-0.85, 4.8), Vector2(-0.85, 13.1), Vector2(-5.3, 13.1)])
	var crest := PackedVector2Array([Vector2(-1.1, 22.6), Vector2(1.1, 22.6), Vector2(1.1, 16.4), Vector2(-1.1, 16.4)])
	for spec in [[visor_gold, Mat.GOLD, &"visor_trim", 0.0], [visor_slit, Mat.VISOR, &"visor", 0.05], [crest, Mat.GOLD, &"crest", 0.0]]:
		var pts := PackedVector3Array()
		for p in spec[0] as PackedVector2Array:
			pts.append(Vector3(p.x, p.y, fz.call(p.y) + spec[3]))
		helm_part.decals.append(M.MeshDecal.new(pts, Vector3.BACK, spec[1], spec[2]))
	list.append(helm_part)
	var halo := Part.new(&"halo", &"halo", PaladinMesh.new(), &"halo", -2.0)
	halo.scale_group = &"head"
	list.append(halo)

	# OMBREIRAS: grandes cúpulas facetadas, borda dourada larga, rebite dourado na frente
	for side in [RIGHT, LEFT]:
		var s := &"r_" if side < 0 else &"l_"
		var dome := M.lathe([[-3.4, 10.8, 10.3], [-2.0, 11.9, 11.3], [-0.2, 12.2, 11.6], [2.0, 12.0, 11.4], [5.6, 10.0, 9.6], [8.6, 5.6, 5.4], [10.0, 0.0, 0.0]], 7,
			[Mat.GOLD, Mat.IVORY, Mat.GOLD, Mat.IVORY, Mat.IVORY, Mat.IVORY], Mat.DARK, -1, false)
		# eixo da cúpula para fora e para cima (cobre o ombro por cima e pelo lado)
		var axis := Vector3(side * 0.6, 0.8, 0.0).normalized()
		var bx := axis.cross(Vector3(0, 0, 1)).normalized()
		var b := Basis(bx, axis, bx.cross(axis)).orthonormalized()   # y = eixo, z = frente
		var pd := Part.new(StringName(s + "pauldron"), StringName(s + "pauldron"), dome.transformed(Transform3D(b, Vector3(side * 0.6, -1.2, 0.0))), &"body", 1.2)
		pd.scale_group = &"shoulder"
		# rebite: na frente-lado da cúpula
		var sp := (b * Vector3(0, 4.2, 10.6)) + Vector3(side * 0.6, -1.2, 0.0)
		var sn := (b * Vector3(0, 0.45, 1.0)).normalized()
		var su := sn.cross(Vector3.UP).normalized()
		var sv := sn.cross(su).normalized()
		pd.decals.append(M.MeshDecal.on_plane(M.circle(Vector2.ZERO, 3.0, 12), sp, su, sv, Mat.GOLD, &"stud"))
		pd.decals.append(M.MeshDecal.on_plane(M.circle(Vector2.ZERO, 1.6, 10), sp + sn * 0.05, su, sv, Mat.IVORY, &"stud_core"))
		list.append(pd)
		# braço: manga escura, braçal de placa, cotoveleira dourada, antebraço, manopla escura
		list.append(Part.new(StringName(s + "sleeve"), StringName(s + "upper"),
			M.lathe([[0.0, 4.8, 4.8], [-6.0, 4.6, 4.6], [-12.5, 4.2, 4.2]], 6, [Mat.DARK, Mat.DARK], -1, -1), &"body", 0.2))
		list.append(Part.new(StringName(s + "rerebrace"), StringName(s + "upper"),
			M.lathe([[-5.6, 5.5, 5.5], [-9.4, 5.2, 5.2], [-11.8, 4.9, 4.9]], 6, [Mat.IVORY, Mat.GOLD], -1, -1), &"body", 0.3))
		list.append(Part.new(StringName(s + "couter"), StringName(s + "fore"),
			M.lathe([[2.6, 0.0, 0.0], [-0.6, 5.4, 5.4], [-2.6, 4.4, 4.4]], 6, [Mat.IVORY, Mat.GOLD], -1, -1), &"body", 0.6))
		list.append(Part.new(StringName(s + "vambrace"), StringName(s + "fore"),
			M.lathe([[-1.5, 5.0, 5.0], [-9.6, 4.5, 4.5], [-11.2, 4.6, 4.6]], 6, [Mat.IVORY, Mat.GOLD], -1, -1), &"body", 0.4))
		list.append(Part.new(StringName(s + "gauntlet"), StringName(s + "hand"),
			M.lathe([[1.0, 3.6, 3.9], [-1.5, 4.1, 4.4], [-5.2, 2.6, 2.9]], 5, [Mat.GLOVE, Mat.GLOVE], -1, Mat.GLOVE), &"body", 0.5))

	# PERNAS: coxote de placa, joelheira facetada com friso dourado, grevas, sabatons pontudos
	for side in [RIGHT, LEFT]:
		var s := &"r_" if side < 0 else &"l_"
		# aba escura da túnica na frente da coxa (entre o tabardo e a joelheira, como nas referências)
		var flap := M.panel(PackedVector2Array([Vector2(-4.6, 3.0), Vector2(5.0, 3.0), Vector2(5.6, -13.5), Vector2(-4.2, -14.5)]), Mat.DARK, Mat.DARK)
		list.append(Part.new(StringName(s + "robe_flap"), StringName(s + "thigh"), flap.transformed(Transform3D(Basis(Vector3.UP, side * 0.35), Vector3(side * 0.6, 0, 7.6))), &"body", 0.4))
		list.append(Part.new(StringName(s + "cuisse"), StringName(s + "thigh"),
			M.lathe([[1.0, 6.8, 7.0], [-8.0, 6.3, 6.5], [-15.0, 5.3, 5.5]], 6, [Mat.IVORY, Mat.IVORY], -1, -1), &"body", 0.0))
		var knee := M.lathe([[2.2, 3.0, 3.0], [0.6, 6.0, 6.4], [-0.6, 6.6, 7.0], [-5.0, 4.4, 4.4]], 6, [Mat.IVORY, Mat.GOLD, Mat.IVORY], -1, -1)
		# cotovelo da joelheira: bico para a frente
		knee = knee.transformed(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.9)))
		list.append(Part.new(StringName(s + "poleyn"), StringName(s + "shin"), knee, &"body", 0.7))
		list.append(Part.new(StringName(s + "greave"), StringName(s + "shin"),
			M.lathe([[-2.0, 5.9, 6.3], [-13.6, 4.9, 5.2], [-15.0, 5.4, 5.7], [-16.4, 5.4, 5.7]], 6, [Mat.IVORY, Mat.GOLD, Mat.GOLD], -1, -1), &"body", 0.3))
		# sabaton: cunha com bico para a frente (sola em y = -PELVIS… : o pé fica na origem do osso do pé)
		var foot := M.loft([
			[-6.0, PackedVector2Array([Vector2(-4.2, -4.0), Vector2(4.2, -4.0), Vector2(4.4, 3.4), Vector2(1.4, 11.0), Vector2(-1.4, 11.0), Vector2(-4.4, 3.4)])],
			[-3.0, PackedVector2Array([Vector2(-4.2, -3.6), Vector2(4.2, -3.6), Vector2(4.3, 3.0), Vector2(1.2, 9.2), Vector2(-1.2, 9.2), Vector2(-4.3, 3.0)])],
			[0.4, PackedVector2Array([Vector2(-4.6, -3.0), Vector2(4.6, -3.0), Vector2(4.6, 1.8), Vector2(1.4, 3.8), Vector2(-1.4, 3.8), Vector2(-4.6, 1.8)])],
		], [Mat.IVORY, Mat.IVORY], Mat.DARK, Mat.GOLD)
		list.append(Part.new(StringName(s + "sabaton"), StringName(s + "foot"), foot, &"body", 0.2))

	# TABARDO: painel da frente (3 segmentos, o último em duas caudas) com a estrela; painel de trás
	var w := [[5.4, 5.9], [5.9, 6.4], [6.4, 6.9]]
	for i in 3:
		var bone := StringName("tab_f%d" % (i + 1))
		var top: float = w[i][0]
		var bot: float = w[i][1]
		var L := TABARD_SEG + (0.8 if i < 2 else 0.0)
		if i < 2:
			var pnl := M.panel(PackedVector2Array([Vector2(-top, 0), Vector2(top, 0), Vector2(bot, -L), Vector2(-bot, -L)]), Mat.CLOTH, Mat.CLOTH_BACK)
			var tp := Part.new(StringName("tabard_front_%d" % (i + 1)), bone, pnl, &"body", 1.6)
			if i == 0:
				tp.decals.append(M.MeshDecal.on_plane(M.star4(Vector2(0, -3.0), 1.6, 1.6, 1.6, 0.5), Vector3(0, 0, 0.06), Vector3.RIGHT, Vector3.UP, Mat.GOLD, &"tabard_trim"))
			if i == 1:
				tp.decals.append(M.MeshDecal.on_plane(M.star4(Vector2(0, -4.6), 2.6, 3.6, 4.6, 0.9), Vector3(0, 0, 0.06), Vector3.RIGHT, Vector3.UP, Mat.GOLD, &"tabard_star"))
			list.append(tp)
		else:
			for tail in [-1.0, 1.0]:
				var inner: float = 0.35 * tail
				var pnl := M.panel(PackedVector2Array([Vector2(inner, 0), Vector2(top * tail, 0), Vector2(bot * tail, -L), Vector2(1.2 * tail, -L + 2.6)]) if tail > 0 else
					PackedVector2Array([Vector2(top * tail, 0), Vector2(inner, 0), Vector2(1.2 * tail, -L + 2.6), Vector2(bot * tail, -L)]), Mat.CLOTH, Mat.CLOTH_BACK)
				list.append(Part.new(StringName("tabard_front_3%s" % ("l" if tail > 0 else "r")), bone, pnl, &"body", 1.6))
		var back := M.panel(PackedVector2Array([Vector2(top + 4.2, 0), Vector2(-top - 4.2, 0), Vector2(-bot - 5.0, -L), Vector2(bot + 5.0, -L)]), Mat.CLOTH, Mat.CLOTH_BACK)
		list.append(Part.new(StringName("tabard_back_%d" % (i + 1)), StringName("tab_b%d" % (i + 1)), back, &"body", -1.4))

	# ESPADA (mão direita): lâmina larga facetada, guarda dourada, punho, pomo
	var blade_sections := []
	for s in [[5.0, 3.5, 0.8], [33.0, 3.3, 0.75], [40.0, 2.8, 0.65], [45.5, 0.0, 0.0]]:
		if s[1] <= 0.0:
			blade_sections.append([s[0], PackedVector2Array([Vector2.ZERO])])
		else:
			blade_sections.append([s[0], PackedVector2Array([Vector2(s[1], 0), Vector2(0, s[2]), Vector2(-s[1], 0), Vector2(0, -s[2])])])
	var blade := M.loft(blade_sections, [Mat.STEEL, Mat.STEEL, Mat.STEEL], Mat.STEEL, -1)
	var bp := Part.new(&"blade", &"sword", blade, &"sword", 0.0)
	list.append(bp)
	var guard := M.loft([[3.6, PackedVector2Array([Vector2(-7.0, -1.1), Vector2(7.0, -1.1), Vector2(7.6, 0.0), Vector2(7.0, 1.1), Vector2(-7.0, 1.1), Vector2(-7.6, 0.0)])],
		[5.4, PackedVector2Array([Vector2(-6.4, -0.9), Vector2(6.4, -0.9), Vector2(7.2, 0.0), Vector2(6.4, 0.9), Vector2(-6.4, 0.9), Vector2(-7.2, 0.0)])]],
		[Mat.GOLD], Mat.GOLD, Mat.GOLD)
	var gp := Part.new(&"guard", &"sword", guard, &"sword", 0.2)
	list.append(gp)
	var grip := M.lathe([[-5.5, 1.2, 1.2], [3.6, 1.1, 1.1]], 6, [Mat.GRIP], -1, -1)
	var hp := Part.new(&"grip", &"sword", grip, &"sword", -0.2)
	list.append(hp)
	var pommel := M.lathe([[-8.6, 0.0, 0.0], [-6.8, 2.0, 2.0], [-5.2, 0.0, 0.0]], 5, [Mat.GOLD, Mat.GOLD], -1, -1)
	var pp := Part.new(&"pommel", &"sword", pommel, &"sword", 0.1)
	list.append(pp)

	# ESCUDO (braço esquerdo): escudo de cavaleiro facetado, aro dourado, estrela sagrada
	list.append(_shield_part())
	return list


static func _body(p: Part) -> Part:
	p.scale_group = &"body"
	return p


## Contorno do escudo (plano xy, alça na origem; frente = +z). Convexo.
const SHIELD_OUTLINE := [Vector2(-10.5, 33.0), Vector2(10.5, 33.0), Vector2(16.5, 27.5), Vector2(16.8, 3.0),
	Vector2(12.0, -17.0), Vector2(0.0, -38.0), Vector2(-12.0, -17.0), Vector2(-16.8, 3.0), Vector2(-16.5, 27.5)]
const SHIELD_CENTER := Vector2(0.0, 2.0)
const SHIELD_FRONT_Z := 2.4
const SHIELD_BOSS_Z := 5.0
const SHIELD_RIM := 0.84     # escala do contorno interno (o aro dourado fica entre os dois)


static func _shield_part() -> Part:
	var m := PaladinMesh.new()
	var outer := PackedVector3Array()
	var inner := PackedVector3Array()
	var back := PackedVector3Array()
	for p in SHIELD_OUTLINE:
		outer.append(Vector3(p.x, p.y, SHIELD_FRONT_Z))
		var q: Vector2 = SHIELD_CENTER + (p - SHIELD_CENTER) * SHIELD_RIM
		inner.append(Vector3(q.x, q.y, SHIELD_FRONT_Z + 0.9))
		back.append(Vector3(p.x, p.y, -0.6))
	var boss := Vector3(SHIELD_CENTER.x, SHIELD_CENTER.y, SHIELD_BOSS_Z)
	var n := outer.size()
	for i in n:
		var j := (i + 1) % n
		var mid := (outer[i] + outer[j]) / 2.0
		var out := Vector3(mid.x - SHIELD_CENTER.x, mid.y - SHIELD_CENTER.y, 0.0)
		# aro dourado (frente, inclinado), lateral dourada, faces internas em leque (facetado)
		m.add_face(PackedVector3Array([outer[i], outer[j], inner[j], inner[i]]), Mat.GOLD, out * 0.2 + Vector3(0, 0, 1))
		m.add_face(PackedVector3Array([back[i], back[j], outer[j], outer[i]]), Mat.GOLD, out)
		m.add_face(PackedVector3Array([inner[i], inner[j], boss]), Mat.IVORY, Vector3(0, 0, 1))
	m.add_face(back, Mat.WOOD, Vector3(0, 0, -1))
	var part := Part.new(&"shield", &"shield", m.finish(), &"shield", 0.0)
	# estrela sagrada: pontos colados na superfície do leque (a face é abaulada)
	var surf := func(p: Vector2) -> Vector3:
		var d := p - SHIELD_CENTER
		# fração radial até o contorno interno (aprox. pela elipse que o envolve)
		var k := clampf(sqrt(pow(d.x / (16.8 * SHIELD_RIM), 2.0) + pow(d.y / (36.0 * SHIELD_RIM), 2.0)), 0.0, 1.0)
		return Vector3(p.x, p.y, lerpf(SHIELD_BOSS_Z, SHIELD_FRONT_Z + 0.9, k) + 0.15)
	var star := PaladinMesh.star4(SHIELD_CENTER, 11.5, 20.0, 24.0, 3.0)
	var disc := PaladinMesh.circle(SHIELD_CENTER, 3.4, 12)
	var ring := PaladinMesh.circle(SHIELD_CENTER, 4.6, 12)
	for spec in [[star, Mat.GOLD, &"shield_star"], [ring, Mat.GOLD, &"shield_ring"], [disc, Mat.IVORY, &"shield_disc"]]:
		var pts := PackedVector3Array()
		for p in spec[0] as PackedVector2Array:
			pts.append(surf.call(p))
		part.decals.append(PaladinMesh.MeshDecal.new(pts, Vector3.BACK, spec[1], spec[2]))
	# alças atrás (vistas por trás)
	var strap_a := PackedVector3Array([Vector3(-9, 8, -0.7), Vector3(9, 8, -0.7), Vector3(9, 5, -0.7), Vector3(-9, 5, -0.7)])
	var strap_b := PackedVector3Array([Vector3(-9, -6, -0.7), Vector3(9, -6, -0.7), Vector3(9, -9, -0.7), Vector3(-9, -9, -0.7)])
	part.decals.append(PaladinMesh.MeshDecal.new(strap_a, Vector3.FORWARD, Mat.BROWN, &"strap"))
	part.decals.append(PaladinMesh.MeshDecal.new(strap_b, Vector3.FORWARD, Mat.BROWN, &"strap"))
	return part
