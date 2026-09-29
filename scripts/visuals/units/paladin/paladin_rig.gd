class_name PaladinRig
extends Node2D
## Rig 2.5D do Paladino Vivo: esqueleto (cinemática direta a partir de uma pose), projeção com
## câmera levemente de cima e desenho das peças low-poly ordenadas por profundidade a cada quadro.
##
## Por que não uma árvore de Polygon2D: numa vista 2.5D a ordem das peças muda com a direção
## (de costas o escudo passa para trás do corpo, de lado o braço da espada passa para a frente…).
## Aqui cada peça é projetada e reordenada por profundidade a cada quadro; os ossos continuam
## sendo partes separadas com pivô próprio (PaladinModel.BONES) e transformações independentes.
##
## Só apresentação: lê a pose que o PaladinAnimator entrega; não conhece a simulação.
##
## Espaço do corpo (PaladinModel): x = ESQUERDA do personagem, y = cima, z = frente.
## Espaço do mundo 3D: X = direita da tela, Y = cima, Z = para a câmera (baixo da tela).
## `yaw` gira o corpo: 0 = olhando para a câmera (baixo), +90° = direita, 180° = de costas (cima).

const Mat := PaladinModel.Mat

var look: PaladinRigLook
## Direção do corpo em radianos (ver acima).
var yaw := 0.0
## Pose atual (chaves de PaladinPoseLibrary.neutral()).
var pose: Dictionary = {}
## Transformações dos ossos no espaço do corpo, calculadas por solve().
var bones: Dictionary = {}
## Ossos com transformação imposta (espada e escudo soltos na morte), espaço do corpo.
var overrides: Dictionary = {}
## Brilho sagrado do escudo/estrela (0..1): só aumenta a luz das cores (o efeito fica em PaladinEffects).
var emblem_glow := 0.0

# Resultado do último quadro (para efeitos, barra de HP, clique e testes)
var bounds := Rect2()
## > 0: a face do escudo está virada para a câmera.
var shield_facing := 0.0
var _anchors: Dictionary = {}
var _view := Basis.IDENTITY
var _light := Vector3(-0.62, 0.62, 0.48).normalized()


func _init() -> void:
	pose = PaladinPoseLibrary.neutral()


func set_frame(p_pose: Dictionary, p_yaw: float) -> void:
	pose = p_pose
	yaw = p_yaw
	solve()
	_cmds_dirty = true
	queue_redraw()


# --- Esqueleto --------------------------------------------------------------------------------

static func euler(v: Vector3) -> Basis:
	## (pitch para a frente, yaw para a esquerda, roll)
	return Basis(Vector3.UP, v.y) * Basis(Vector3.RIGHT, v.x) * Basis(Vector3.BACK, v.z)


## Membro pendurado (−y): balanço para a frente, abertura para fora, torção. `side`: −1 direito, +1 esquerdo.
static func limb(v: Vector3, side: float) -> Basis:
	return Basis(Vector3.BACK, v.y * side) * Basis(Vector3.RIGHT, -v.x) * Basis(Vector3.UP, v.z * side)


func _lk() -> PaladinRigLook:
	if look == null:
		look = PaladinRigLook.get_default()
	return look


## Calcula `bones` (espaço do corpo) a partir de `pose`.
func solve() -> void:
	var L := _lk()
	var p := pose
	var T := {}
	var body := Transform3D(euler(p.body_rot), p.body_pos)
	var pel: Transform3D = body * Transform3D(euler(p.hips), Vector3(0, PaladinModel.PELVIS_Y * L.body_height, 0) + p.root)
	T[&"pelvis"] = pel
	var torso: Transform3D = pel * Transform3D(euler(p.spine), PaladinModel.SPINE)
	T[&"torso"] = torso
	var neck := PaladinModel.NECK
	neck.y *= L.body_height
	T[&"head"] = torso * Transform3D(euler(p.head), neck)
	T[&"halo"] = T[&"head"] * Transform3D(Basis(Vector3.RIGHT, p.halo.x), Vector3(0, 16.5 + p.halo.y, -9.5))
	for side in [PaladinModel.RIGHT, PaladinModel.LEFT]:
		var s := "r_" if side < 0 else "l_"
		var sh_pos := Vector3(PaladinModel.SHOULDER.x * side * L.shoulder_width * L.body_width, PaladinModel.SHOULDER.y * L.body_height, PaladinModel.SHOULDER.z)
		var arm: Vector3 = p[s + "arm"]
		var upper: Transform3D = torso * Transform3D(limb(arm, side), sh_pos)
		T[StringName(s + "upper")] = upper
		T[StringName(s + "pauldron")] = torso * Transform3D(limb(Vector3(arm.x * 0.3, arm.y * 0.5 + 0.05, 0.0), side), sh_pos)
		var fore: Transform3D = upper * Transform3D(Basis(Vector3.RIGHT, -float(p[s + "elbow"])), Vector3(0, -PaladinModel.UPPER_ARM, 0))
		T[StringName(s + "fore")] = fore
		var hand: Transform3D = fore * Transform3D(Basis.IDENTITY, Vector3(0, -PaladinModel.FOREARM, 0))
		T[StringName(s + "hand")] = hand
	# armas: posição = punho da mão; orientação = pose (relativa ao tronco). A espada é sempre da
	# mão DIREITA e o escudo sempre do braço ESQUERDO (PaladinModel.SWORD_CHAIN / SHIELD_CHAIN).
	var fist_r: Vector3 = (T[&"r_hand"] as Transform3D) * Vector3(0, -2.4, 0)
	var sword_b: Basis = torso.basis * euler(p.sword) * Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(Vector3.ONE * L.sword_scale)
	T[&"sword"] = Transform3D(sword_b, fist_r + torso.basis * L.sword_offset)
	var fist_l: Vector3 = (T[&"l_hand"] as Transform3D) * Vector3(0, -2.4, 0)
	var sh: Vector3 = p.shield
	var shield_b: Basis = torso.basis * euler(Vector3(sh.x, sh.y + deg_to_rad(L.shield_angle), sh.z)) * Basis.from_scale(Vector3.ONE * L.shield_scale)
	T[&"shield"] = Transform3D(shield_b, fist_l + torso.basis * (Vector3(0, 0, 1.6) + L.shield_offset))
	# pernas: o pé fica nivelado com o corpo inteiro (não com a coxa)
	for side in [PaladinModel.RIGHT, PaladinModel.LEFT]:
		var s := "r_" if side < 0 else "l_"
		var hip := PaladinModel.HIP
		hip.x *= side * L.body_width
		var leg: Vector3 = p[s + "leg"]
		var thigh: Transform3D = pel * Transform3D(limb(leg, side), hip)
		T[StringName(s + "thigh")] = thigh
		var shin: Transform3D = thigh * Transform3D(Basis(Vector3.RIGHT, float(p[s + "knee"])), Vector3(0, -PaladinModel.THIGH, 0))
		T[StringName(s + "shin")] = shin
		var ankle: Vector3 = shin * Vector3(0, -PaladinModel.SHIN, 0)
		var foot_b: Basis = body.basis * Basis(Vector3.UP, (p.hips as Vector3).y + leg.z * side * 0.8) * Basis(Vector3.RIGHT, float(p[s + "foot"]))
		T[StringName(s + "foot")] = Transform3D(foot_b, ankle)
	# tabardo (frente e trás): três segmentos em cadeia a partir do cinto
	var cloth: Vector3 = p.cloth
	var f1: Transform3D = pel * Transform3D(Basis(Vector3.BACK, cloth.z) * Basis(Vector3.RIGHT, -cloth.x), PaladinModel.TABARD_FRONT)
	var f2: Transform3D = f1 * Transform3D(Basis(Vector3.RIGHT, -cloth.x * 0.45 - 0.02), Vector3(0, -PaladinModel.TABARD_SEG - 0.8, 0))
	var f3: Transform3D = f2 * Transform3D(Basis(Vector3.RIGHT, -cloth.x * 0.3 - 0.02), Vector3(0, -PaladinModel.TABARD_SEG - 0.8, 0))
	T[&"tab_f1"] = f1
	T[&"tab_f2"] = f2
	T[&"tab_f3"] = f3
	var b1: Transform3D = pel * Transform3D(Basis(Vector3.BACK, -cloth.z) * Basis(Vector3.RIGHT, cloth.y + 0.06), PaladinModel.TABARD_BACK)
	var b2: Transform3D = b1 * Transform3D(Basis(Vector3.RIGHT, cloth.y * 0.5 + 0.03), Vector3(0, -PaladinModel.TABARD_SEG, 0))
	var b3: Transform3D = b2 * Transform3D(Basis(Vector3.RIGHT, cloth.y * 0.35 + 0.03), Vector3(0, -PaladinModel.TABARD_SEG, 0))
	T[&"tab_b1"] = b1
	T[&"tab_b2"] = b2
	T[&"tab_b3"] = b3
	for k in overrides:
		T[k] = overrides[k]
	# pés no chão: desloca tudo para a sola mais baixa tocar y = 0 (peso `ground` da pose)
	var ground: float = p.ground
	if ground > 0.0:
		var low := INF
		for f in [&"r_foot", &"l_foot"]:
			var ft: Transform3D = T[f]
			for q in [Vector3(0, -6.0, -3.4), Vector3(0, -6.0, 9.0)]:
				low = minf(low, (ft * q).y)
		for shin_bone in [&"r_shin", &"l_shin"]:   # ajoelhado: o joelho também apoia
			low = minf(low, ((T[shin_bone] as Transform3D) * Vector3(0, 0, 6.2)).y)
		var fix := Vector3(0, -low * ground, 0)
		for k in T:
			if not overrides.has(k):
				var t: Transform3D = T[k]
				T[k] = Transform3D(t.basis, t.origin + fix)
	bones = T


## Transformação do osso no espaço do corpo (após solve()).
func bone(name: StringName) -> Transform3D:
	return bones.get(name, Transform3D.IDENTITY)


## Ponto no espaço do corpo → posição local deste nó (2D).
func to_screen(model_point: Vector3) -> Vector2:
	var v := _view_basis() * model_point
	var k := _lk().scale
	return Vector2(v.x * k, -v.y * k)


## Profundidade (maior = mais perto da câmera) de um ponto do espaço do corpo.
func depth_of(model_point: Vector3) -> float:
	return (_view_basis() * model_point).z


## Pontos de referência do último desenho (posição local): shield_center, sword_tip, sword_grip,
## r_hand, l_hand, head_top, halo, chest, feet.
func anchor(name: StringName) -> Vector2:
	return _anchors.get(name, Vector2.ZERO)


func _view_basis() -> Basis:
	return Basis(Vector3.RIGHT, _lk().view_tilt) * Basis(Vector3.UP, yaw)


# --- Desenho ----------------------------------------------------------------------------------

func _draw() -> void:
	if _cmds_dirty or _cmds.is_empty():
		build_commands()
	var ci := get_canvas_item()
	var L := _lk()
	var ow := L.outline_width * 2.0
	for c in _cmds:
		match c[0]:
			CMD_HULL:
				draw_colored_polygon(c[1], L.outline)
				draw_polyline(c[1], L.outline, ow, true)
			CMD_TRIS:
				RenderingServer.canvas_item_add_triangle_array(ci, c[1], c[2], c[3])
			CMD_POLY:
				draw_colored_polygon(c[1], c[2])
			CMD_LINE:
				draw_polyline(c[1], c[2], c[3], true)


const CMD_HULL := 0
const CMD_TRIS := 1
const CMD_POLY := 2
const CMD_LINE := 3
## Lista de desenho do último quadro: [tipo, dados…] (montada em build_commands, enviada em _draw).
var _cmds: Array = []
var _cmds_dirty := true


## Projeta, ordena e sombreia todas as peças para o quadro atual (sem desenhar). Separado do
## _draw para ser medido e testado; também atualiza `bounds` e as âncoras.
func build_commands() -> void:
	if bones.is_empty():
		solve()
	var L := _lk()
	_view = _view_basis()
	_build_tone_table(L)
	var k := L.scale
	var screen := Transform3D(Basis.from_scale(Vector3(k, -k, 1.0)), Vector3.ZERO)
	var view_t := Transform3D(_view, Vector3.ZERO)
	var items := []   # [profundidade, parte, transformação de vista]
	for part in PaladinModel.parts():
		var bt: Transform3D = bones.get(part.bone, Transform3D.IDENTITY)
		var vt := view_t * bt * _group_scale(part.scale_group, L)
		var d: float
		if part.kind == &"halo":
			d = vt.origin.z - 1.5
		else:
			# o viés empurra o ponto de ordenação para a FRENTE do osso (+z local): uma peça da frente
			# do corpo passa na frente quando o corpo olha para a câmera e fica atrás quando está de costas
			d = (vt * (part.mesh.center + Vector3(0, 0, part.bias))).z
		items.append([d, part, vt])
	items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var cmds: Array = []
	var bmin := Vector2(INF, INF)
	var bmax := Vector2(-INF, -INF)
	for it in items:
		var part: PaladinModel.Part = it[1]
		var vt: Transform3D = it[2]
		if part.kind == &"halo":
			_halo_commands(cmds, vt, k)
			continue
		var mesh := part.mesh
		var st := screen * vt
		var vv: PackedVector3Array = st * mesh.verts   # x, y já na tela; z = profundidade
		var nb := vt.basis
		var nz_row := Vector3(nb.x.z, nb.y.z, nb.z.z)   # z da normal na vista = n · esta linha
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		var idx := PackedInt32Array()
		var ff := mesh.face_first
		var fs := mesh.face_size
		var fm := mesh.face_mat
		var fn := mesh.face_normal
		for f in ff.size():
			var n0 := fn[f]
			var mat := fm[f]
			var flip := false
			if n0.dot(nz_row) <= 0.0:
				if not mesh.two_sided:
					continue
				flip = true
				mat = mesh.back_mat
			var nrm := (nb * n0).normalized()
			if flip:
				nrm = -nrm
			var col := _shade(mat, nrm, L)
			var a := ff[f]
			var c := fs[f]
			var base := pts.size()
			for j in c:
				var v := vv[a + j]
				pts.append(Vector2(v.x, v.y))
				cols.append(col)
			for j in range(1, c - 1):
				idx.append(base)
				idx.append(base + j)
				idx.append(base + j + 1)
		if idx.is_empty():
			continue
		var hull := Geometry2D.convex_hull(pts)
		if hull.size() >= 3:
			cmds.append([CMD_HULL, hull])
			for q in hull:
				bmin = bmin.min(q)
				bmax = bmax.max(q)
		cmds.append([CMD_TRIS, idx, pts, cols])
		for dc in part.decals:
			var dn: Vector3 = vt.basis * dc.normal
			if dn.z <= 0.06:
				continue
			var dv: PackedVector3Array = st * dc.points
			var dp := PackedVector2Array()
			dp.resize(dv.size())
			for i in dv.size():
				dp[i] = Vector2(dv[i].x, dv[i].y)
			cmds.append([CMD_POLY, dp, _shade(dc.mat, dn.normalized(), L)])
	_cmds = cmds
	_cmds_dirty = false
	bounds = Rect2(bmin, bmax - bmin) if bmin.x < INF else Rect2()
	_store_anchors()


func _group_scale(group: StringName, L: PaladinRigLook) -> Transform3D:
	match group:
		&"head":
			return Transform3D(Basis.from_scale(Vector3.ONE * L.head_scale), Vector3.ZERO)
		&"shoulder":
			return Transform3D(Basis.from_scale(Vector3.ONE * L.shoulder_width), Vector3.ZERO)
		&"body":
			return Transform3D(Basis.from_scale(Vector3(L.body_width, L.body_height, 1.0)), Vector3.ZERO)
	return Transform3D.IDENTITY


## Cor facetada: luz fixa em relação à câmera (as facetas mudam quando o corpo gira = volume).
## As cores de cada degrau de luz ficam numa tabela por material (montada uma vez por quadro).
func _shade(mat: int, n: Vector3, _L: PaladinRigLook) -> Color:
	var t := clampf(n.dot(_light) * 0.78 + 0.2 + n.z * 0.08, 0.0, 1.0)
	var row: PackedColorArray = _tone_table[mat]
	return row[int(roundf(t * (row.size() - 1)))]


var _tone_table: Array = []


func _build_tone_table(L: PaladinRigLook) -> void:
	var steps := int(L.facet_steps)
	_tone_table.resize(PaladinModel.Mat.size())
	for mat in PaladinModel.Mat.size():
		var tones := L.tones(mat)
		var row := PackedColorArray()
		for i in steps + 1:
			var t := float(i) / steps
			var c: Color = tones[2].lerp(tones[1], t * 2.0) if t < 0.5 else tones[1].lerp(tones[0], (t - 0.5) * 2.0)
			if emblem_glow > 0.0 and mat == Mat.GOLD:
				c = c.lerp(L.holy_light, emblem_glow * 0.45)
			row.append(c)
		_tone_table[mat] = row


## Auréola: anel dourado atrás do elmo, meio voltado para a câmera (continua legível de lado), com
## três estrelas (topo maior, laterais menores). É um anel — por isso não é uma malha convexa.
## Auréola: anel dourado atrás do elmo, meio voltado para a câmera (continua legível de lado), com
## três estrelas (topo maior, laterais menores). É um anel — por isso não é uma malha convexa.
func _halo_commands(cmds: Array, vt: Transform3D, k: float) -> void:
	var L := _lk()
	var c := vt.origin
	var fwd := vt.basis.z.normalized()
	var up := vt.basis.y.normalized()
	var n := fwd.lerp(Vector3(0, 0, 1.0 if fwd.z >= -0.2 else -1.0), 0.62).normalized()
	var u := up.cross(n).normalized()
	var v := n.cross(u).normalized()
	var sc := vt.basis.get_scale().x
	var R := 11.8 * sc
	var ring := PackedVector2Array()
	for i in 25:
		var a := i * TAU / 24.0
		var p := c + (u * cos(a) + v * sin(a)) * R
		ring.append(Vector2(p.x * k, -p.y * k))
	var gold := L.tones(Mat.GOLD)
	cmds.append([CMD_LINE, ring, L.outline, (2.3 + L.outline_width * 2.0) * k * sc])
	cmds.append([CMD_LINE, ring, gold[1], 1.9 * k * sc])
	cmds.append([CMD_LINE, ring.slice(2, 11), gold[0], 0.8 * k * sc])
	for spec in [[v, 7.5, 1.0], [u, 4.6, 0.75], [-u, 4.6, 0.75]]:
		var dir: Vector3 = spec[0]
		var tip := c + dir * (R + float(spec[1]) * sc)
		var base := c + dir * R
		var side := dir.cross(n).normalized()
		var w := 2.1 * float(spec[2]) * sc
		var star := PackedVector2Array()
		for q in [tip, base + side * w + dir * w * 0.2, base + side * float(spec[1]) * 0.55 * sc, base - dir * w * 0.25 + side * w,
				base - dir * float(spec[1]) * 0.45 * sc, base - dir * w * 0.25 - side * w, base - side * float(spec[1]) * 0.55 * sc, base + dir * w * 0.2 - side * w]:
			star.append(Vector2(q.x * k, -q.y * k))
		cmds.append([CMD_HULL, star])
		cmds.append([CMD_POLY, star, gold[1]])
		cmds.append([CMD_POLY, PackedVector2Array([star[0], star[1], star[2], star[3], star[4]]), gold[0]])


func _store_anchors() -> void:
	var A := {}
	var sb: Transform3D = bones.get(&"shield", Transform3D.IDENTITY)
	A[&"shield_center"] = to_screen(sb * Vector3(PaladinModel.SHIELD_CENTER.x, PaladinModel.SHIELD_CENTER.y, PaladinModel.SHIELD_BOSS_Z))
	shield_facing = (_view_basis() * sb.basis.z).z
	var sw: Transform3D = bones.get(&"sword", Transform3D.IDENTITY)
	A[&"sword_tip"] = to_screen(sw * Vector3(0, 45.5, 0))
	A[&"sword_grip"] = to_screen(sw * Vector3(0, 0, 0))
	A[&"r_hand"] = to_screen(bone(&"r_hand") * Vector3(0, -2.4, 0))
	A[&"l_hand"] = to_screen(bone(&"l_hand") * Vector3(0, -2.4, 0))
	A[&"head_top"] = to_screen(bone(&"head") * Vector3(0, 24.4, 0))
	A[&"halo"] = to_screen(bone(&"halo").origin)
	A[&"chest"] = to_screen(bone(&"torso") * Vector3(0, 12, 8))
	A[&"feet"] = to_screen((bone(&"r_foot").origin + bone(&"l_foot").origin) / 2.0 - Vector3(0, 6, 0))
	_anchors = A
