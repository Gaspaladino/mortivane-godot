class_name PaladinMesh
extends RefCounted
## Malha low-poly de faces planas do rig 2.5D do Paladino (só apresentação).
##
## Cada face tem os próprios vértices (nada compartilhado): o sombreamento é por face, o que dá o
## visual facetado das referências. Faces convexas, em sentido anti-horário vistas de fora — o
## renderizador descarta as que estão de costas para a câmera (a peça é convexa, então não há
## ordenação dentro dela).
##
## Espaço do corpo: x = ESQUERDA do personagem, y = cima, z = frente. (Com x = esquerda a base
## fica destra: girar o corpo nunca espelha a geometria nem troca a mão da espada.)

var verts := PackedVector3Array()
var face_first := PackedInt32Array()
var face_size := PackedInt32Array()
var face_mat := PackedInt32Array()
## Tecido: as duas faces aparecem; a de trás usa `back_mat`.
var two_sided := false
var back_mat := -1
var center := Vector3.ZERO
## Normal (unitária) de cada face, no espaço da peça — para descartar faces de costas cedo.
var face_normal := PackedVector3Array()


## Adiciona uma face convexa. `outward` diz para onde fica o "fora" (a face é virada para lá).
func add_face(points: PackedVector3Array, mat: int, outward: Vector3) -> void:
	var clean := PackedVector3Array()
	for p in points:
		if clean.is_empty() or not clean[clean.size() - 1].is_equal_approx(p):
			clean.append(p)
	if clean.size() > 3 and clean[0].is_equal_approx(clean[clean.size() - 1]):
		clean.remove_at(clean.size() - 1)
	if clean.size() < 3:
		return
	var n := newell(clean)
	if n.length_squared() < 1e-10:
		return
	if n.dot(outward) < 0.0:
		clean.reverse()
	face_first.append(verts.size())
	face_size.append(clean.size())
	face_mat.append(mat)
	verts.append_array(clean)


func finish() -> PaladinMesh:
	var c := Vector3.ZERO
	for v in verts:
		c += v
	center = c / maxf(1.0, verts.size())
	face_normal.resize(face_first.size())
	for f in face_first.size():
		face_normal[f] = newell(verts.slice(face_first[f], face_first[f] + face_size[f])).normalized()
	return self


func transformed(t: Transform3D) -> PaladinMesh:
	var m := PaladinMesh.new()
	m.verts = t * verts
	m.face_first = face_first.duplicate()
	m.face_size = face_size.duplicate()
	m.face_mat = face_mat.duplicate()
	m.two_sided = two_sided
	m.back_mat = back_mat
	return m.finish()


func merged(other: PaladinMesh) -> PaladinMesh:
	var m := transformed(Transform3D.IDENTITY)
	var base := m.verts.size()
	m.verts.append_array(other.verts)
	for i in other.face_first.size():
		m.face_first.append(other.face_first[i] + base)
		m.face_size.append(other.face_size[i])
		m.face_mat.append(other.face_mat[i])
	return m.finish()


static func newell(p: PackedVector3Array) -> Vector3:
	var n := Vector3.ZERO
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		n += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
	return n


# --- Construtores ---------------------------------------------------------------------------

## Seção elíptica de `n` lados com uma face plana virada para a frente (+z).
static func ellipse(n: int, rx: float, rz: float, flat_front := true) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var off := PI / n if flat_front else 0.0
	for i in n:
		var a := off + i * TAU / n
		pts.append(Vector2(sin(a) * rx, cos(a) * rz))
	return pts


## Loft: liga seções horizontais (y, polígono em xz com o mesmo número de pontos; 1 ponto = ápice).
## `band_mats[k]` = material da faixa entre a seção k e k+1. Tampas opcionais (material < 0 = sem).
static func loft(sections: Array, band_mats: Array, cap_bottom := -1, cap_top := -1) -> PaladinMesh:
	var m := PaladinMesh.new()
	var n := 0
	for s in sections:
		n = maxi(n, (s[1] as PackedVector2Array).size())
	var rings: Array[PackedVector3Array] = []
	var centers: Array[Vector3] = []
	for s in sections:
		var y: float = s[0]
		var poly: PackedVector2Array = s[1]
		var ring := PackedVector3Array()
		var c := Vector2.ZERO
		for p in poly:
			c += p
		c /= poly.size()
		for i in n:
			var p := poly[i % poly.size()] if poly.size() > 1 else poly[0]
			ring.append(Vector3(p.x, y, p.y))
		rings.append(ring)
		centers.append(Vector3(c.x, y, c.y))
	for k in sections.size() - 1:
		var mat: int = band_mats[mini(k, band_mats.size() - 1)]
		for i in n:
			var j := (i + 1) % n
			var q := PackedVector3Array([rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]])
			var fc := (q[0] + q[1] + q[2] + q[3]) / 4.0
			var axis := centers[k].lerp(centers[k + 1], 0.5)
			var out := fc - Vector3(axis.x, fc.y, axis.z)
			if out.length_squared() < 1e-6:
				out = fc - axis
			m.add_face(q, mat, out)
	if cap_bottom >= 0:
		var r := rings[0].duplicate()
		m.add_face(r, cap_bottom, Vector3.DOWN)
	if cap_top >= 0:
		var r := rings[rings.size() - 1].duplicate()
		m.add_face(r, cap_top, Vector3.UP)
	return m.finish()


## Sólido de revolução facetado: anéis [y, rx, rz], `n` lados.
static func lathe(rings: Array, n: int, band_mats: Array, cap_bottom := -1, cap_top := -1, flat_front := true) -> PaladinMesh:
	var sections := []
	for r in rings:
		if r[1] <= 0.001 and r[2] <= 0.001:
			sections.append([r[0], PackedVector2Array([Vector2.ZERO])])
		else:
			sections.append([r[0], ellipse(n, r[1], r[2], flat_front)])
	return loft(sections, band_mats, cap_bottom, cap_top)


## Prisma: polígono convexo no plano xy extrudado de z0 (trás) a z1 (frente).
static func prism(poly: PackedVector2Array, z0: float, z1: float, mat_front: int, mat_back: int, mat_side: int) -> PaladinMesh:
	var m := PaladinMesh.new()
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= poly.size()
	var front := PackedVector3Array()
	var back := PackedVector3Array()
	for p in poly:
		front.append(Vector3(p.x, p.y, z1))
		back.append(Vector3(p.x, p.y, z0))
	m.add_face(front, mat_front, Vector3.BACK)
	m.add_face(back, mat_back, Vector3.FORWARD)
	for i in poly.size():
		var j := (i + 1) % poly.size()
		var mid := (poly[i] + poly[j]) / 2.0 - c
		m.add_face(PackedVector3Array([back[i], back[j], front[j], front[i]]), mat_side, Vector3(mid.x, mid.y, 0.0))
	return m.finish()


## Caixa alinhada (centro, tamanho).
static func box(center_pos: Vector3, size: Vector3, mat: int, mat_front := -1) -> PaladinMesh:
	var h := size / 2.0
	var poly := PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)])
	return prism(poly, -h.z, h.z, mat if mat_front < 0 else mat_front, mat, mat).transformed(Transform3D(Basis.IDENTITY, center_pos))


## Painel de tecido (quadrilátero no plano xy, z = 0), visível dos dois lados.
static func panel(poly: PackedVector2Array, mat_front: int, mat_back: int) -> PaladinMesh:
	var m := PaladinMesh.new()
	var pts := PackedVector3Array()
	for p in poly:
		pts.append(Vector3(p.x, p.y, 0.0))
	m.add_face(pts, mat_front, Vector3.BACK)
	m.two_sided = true
	m.back_mat = mat_back
	return m.finish()


## Estrela de 4 pontas (x = braços horizontais, y = verticais), plano xy.
static func star4(c: Vector2, arm_x: float, arm_up: float, arm_down: float, waist: float) -> PackedVector2Array:
	return PackedVector2Array([
		c + Vector2(0, arm_up), c + Vector2(waist, waist), c + Vector2(arm_x, 0), c + Vector2(waist, -waist),
		c + Vector2(0, -arm_down), c + Vector2(-waist, -waist), c + Vector2(-arm_x, 0), c + Vector2(-waist, waist)])


static func circle(c: Vector2, r: float, n := 12) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := i * TAU / n
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


## Decalque: polígono plano desenhado por cima da peça quando a sua normal olha para a câmera
## (visor, estrelas, fivela…). Pontos em coordenadas da peça.
class MeshDecal:
	var points: PackedVector3Array
	var normal: Vector3
	var mat: int
	var name: StringName

	func _init(p_points: PackedVector3Array, p_normal: Vector3, p_mat: int, p_name := &"") -> void:
		points = p_points
		normal = p_normal.normalized()
		mat = p_mat
		name = p_name

	## Decalque de um polígono 2D posto num plano (origem, eixo u, eixo v, normal).
	static func on_plane(poly: PackedVector2Array, origin: Vector3, u: Vector3, v: Vector3, mat: int, p_name := &"") -> MeshDecal:
		var pts := PackedVector3Array()
		for p in poly:
			pts.append(origin + u * p.x + v * p.y)
		return MeshDecal.new(pts, u.cross(v), mat, p_name)
