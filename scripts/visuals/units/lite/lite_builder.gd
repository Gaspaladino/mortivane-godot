class_name LiteBuilder
extends RefCounted
## Monta peças (LitePart) a partir de formas simples: preenchimento, contorno suavizado, círculo,
## linha e arco. Tudo vira triângulos com cor por vértice, UMA vez; depois a peça é só reposicionada.
##
## A suavização das bordas é a mesma técnica do Godot (canvas_item_add_polyline com antialias): uma
## faixa central na cor cheia e duas faixas de "pena" (FEATHER) que vão da cor a transparente. Assim a
## peça pronta tem a mesma borda macia do desenho direto, sem custo por quadro.
##
## `xf` transforma as coordenadas de entrada (para montar partes de uma peça em sub-espaços).

const FEATHER := 1.25        # largura da pena da borda (a mesma do motor)

var xf := Transform2D.IDENTITY
## A peça recebe o clarão de dano? (false: sombra no chão, névoa, aura.)
var flashes := true
var _pts := PackedVector2Array()
var _cols := PackedColorArray()


func build() -> LitePart:
	var p := LitePart.new()
	p.pts = _pts
	p.cols = _cols
	p.uvs.resize(_pts.size())
	p.uvs.fill(Vector2(1.0 if flashes else 0.0, 0.0))
	_pts = PackedVector2Array()
	_cols = PackedColorArray()
	return p


## Polígono preenchido (sem borda).
func fill(pts: PackedVector2Array, col: Color) -> void:
	if pts.size() < 3 or col.a <= 0.0:
		return
	var p := xf * pts
	var idx := Geometry2D.triangulate_polygon(p)
	if idx.is_empty():
		# forma que não triangula (auto-intersecção): leque a partir do centro, melhor que nada
		var c := Vector2.ZERO
		for v in p:
			c += v
		c /= p.size()
		for i in p.size():
			_tri(c, p[i], p[(i + 1) % p.size()], col, col, col)
		return
	for k in range(0, idx.size(), 3):
		_tri(p[idx[k]], p[idx[k + 1]], p[idx[k + 2]], col, col, col)


## Contorno suavizado. `closed` fecha o laço (o último ponto liga no primeiro).
func outline(pts: PackedVector2Array, col: Color, width: float, closed := true) -> void:
	if pts.size() < 2 or col.a <= 0.0 or width <= 0.0:
		return
	var p := xf * pts
	if closed:
		p.append(p[0])
	var n := p.size()
	var w := _compensated_width(width)
	var border := FEATHER if w >= 1.0 else FEATHER * w
	var half := w * 0.5
	var first_dir := Vector2.ZERO
	for i in range(1, n):
		first_dir = (p[i] - p[i - 1]).normalized()
		if not first_dir.is_zero_approx():
			break
	var last_dir := Vector2.ZERO
	for i in range(n - 1, 0, -1):
		last_dir = (p[i] - p[i - 1]).normalized()
		if not last_dir.is_zero_approx():
			break
	var mid := PackedVector2Array()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	mid.resize(n * 2)
	left.resize(n * 2)
	right.resize(n * 2)
	var prev := Vector2.ZERO
	for i in n:
		var seg := prev if i == n - 1 else (p[i + 1] - p[i]).normalized()
		if seg.is_zero_approx():
			seg = prev
		if i == 0:
			prev = last_dir if closed else seg
		elif i == n - 1 and closed:
			prev = first_dir
		var base := _edge_offset(seg, prev)
		var edge := base * half
		var b := base * border
		var j := i * 2
		mid[j] = p[i] + edge
		mid[j + 1] = p[i] - edge
		left[j] = p[i] + edge
		left[j + 1] = p[i] + edge + b
		right[j] = p[i] - edge
		right[j + 1] = p[i] - edge - b
		prev = seg
	var clear := Color(col, 0.0)
	_strip(mid, col, col)
	_strip(left, col, clear)
	_strip(right, col, clear)


## Polígono com contorno (o `_poly` dos visuais: preenche e contorna).
func poly(pts: PackedVector2Array, fill_col: Color, line_col: Color, width: float) -> void:
	fill(pts, fill_col)
	outline(pts, line_col, width, true)


## Pontos de um círculo (ou elipse) com `segments` lados.
static func ring(center: Vector2, radius: Vector2, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(segments)
	for i in segments:
		var a := i * TAU / segments
		pts[i] = center + Vector2(cos(a) * radius.x, sin(a) * radius.y)
	return pts


## Nº de lados de um círculo pelo raio (poucos lados em círculos pequenos: menos triângulos).
static func segments_for(radius: float) -> int:
	return clampi(int(radius * 3.0) + 8, 10, 32)


func disc(center: Vector2, radius: float, col: Color, segments := 0) -> void:
	fill(ring(center, Vector2(radius, radius), segments if segments > 0 else segments_for(radius)), col)


func circle(center: Vector2, radius: float, fill_col: Color, line_col: Color, width: float) -> void:
	var pts := ring(center, Vector2(radius, radius), segments_for(radius))
	fill(pts, fill_col)
	outline(pts, line_col, width, true)


func line(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	outline(PackedVector2Array([a, b]), col, width, false)


func polyline(pts: PackedVector2Array, col: Color, width: float) -> void:
	outline(pts, col, width, false)


func arc(center: Vector2, radius: float, start: float, end: float, segments: int, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in segments:
		var t := lerpf(start, end, float(i) / (segments - 1))
		pts.append(center + Vector2(cos(t), sin(t)) * radius)
	var full := absf(end - start) >= TAU - 0.001
	if full:
		pts.remove_at(pts.size() - 1)
	outline(pts, col, width, full)


# --- Interno --------------------------------------------------------------------------------

func _tri(a: Vector2, b: Vector2, c: Vector2, ca: Color, cb: Color, cc: Color) -> void:
	_pts.append(a)
	_pts.append(b)
	_pts.append(c)
	_cols.append(ca)
	_cols.append(cb)
	_cols.append(cc)


## Faixa de triângulos (v0 v1 v2 …, pares = lado A, ímpares = lado B).
func _strip(v: PackedVector2Array, col_a: Color, col_b: Color) -> void:
	for k in v.size() - 2:
		_tri(v[k], v[k + 1], v[k + 2],
			col_a if k % 2 == 0 else col_b, col_b if k % 2 == 0 else col_a, col_a if k % 2 == 0 else col_b)


## RendererCanvasCull::canvas_item_get_compensated_antialiasing_width
static func _compensated_width(w: float) -> float:
	if w <= FEATHER * 2.0:
		return w * 0.5
	elif w <= FEATHER * 4.0:
		return remap(w, FEATHER * 2.0, FEATHER * 4.0, w * 0.5, w - FEATHER * 0.5)
	return w - FEATHER * 0.5


## Deslocamento da borda num vértice (bissetriz com comprimento limitado), como o motor.
static func _edge_offset(seg: Vector2, prev: Vector2) -> Vector2:
	var length := 1.0
	var bisector := (prev * seg.length() - seg * prev.length()).normalized()
	var angle := atan2(bisector.cross(prev), bisector.dot(prev))
	var s := sin(angle)
	if not is_zero_approx(s) and not seg.is_equal_approx(prev):
		length = clampf(1.0 / s, -3.0, 3.0)
	else:
		bisector = seg.orthogonal()
	if bisector.is_zero_approx():
		bisector = seg.orthogonal()
	return bisector * length
