class_name DrawCache
extends RefCounted
## Cache de geometria dos visuais por código (etapa 3 da otimização).
##
## Problema medido: cada `draw_colored_polygon` / `draw_polyline` suavizado / `draw_circle` / `draw_arc`
## triangula e cria buffers de GPU A CADA QUADRO, e o contorno suavizado vira 3 draw calls.
## Aqui cada FORMA (os mesmos pontos, no espaço local da peça) vira uma malha branca construída uma
## vez e reutilizada por todos os quadros e unidades: o desenho passa a ser `draw_mesh(malha, cor)`
## (a cor entra pelo `modulate`: branco × cor = cor, exato).
##
## A geometria é a MESMA que o Godot 4.7 gera (portada de servers/rendering/renderer_canvas_cull.cpp
## e scene/main/canvas_item.cpp: canvas_item_add_polygon, canvas_item_add_polyline com antialias,
## canvas_item_add_ellipse, draw_ellipse_arc), com a mesma aritmética de float32. Os três trechos do
## contorno (faixa central + duas bordas de suavização) viram UMA malha, na mesma ordem de desenho.
## Resultado: pixels idênticos (validado por tools/bench/draw_cache_pixels.gd) com metade dos draw
## calls por peça e sem triangulação por quadro.
##
## Formas que mudam todo quadro (capa balançando, polígonos projetados do Paladino) não se repetem:
## só viram malha na 2ª vez em que aparecem idênticas; até lá seguem pelo caminho normal.

const FEATHER_SIZE := 1.25          # renderer_canvas_cull.cpp
const ELLIPSE_SEGMENTS := 64        # canvas_item_add_ellipse
const CMP_EPSILON := 0.00001
## Limites de memória (formas distintas guardadas / vistas uma vez).
const MAX_MESHES := 8192
const MAX_SEEN := 32768

static var _fill := {}              # PackedVector2Array → ArrayMesh
static var _outline := {}           # largura → {PackedVector2Array fechado → ArrayMesh}
static var _circle := {}            # Vector3(cx, cy, r) → ArrayMesh
static var _arc := {}               # [cx, cy, r, n, largura] → ArrayMesh
static var _seen := {}
## Diagnóstico
static var stat_hits := 0
static var stat_misses := 0
static var stat_built := 0


## Arredonda para float32 (o motor faz estas contas em `float`; o GDScript, em double).
static func f32(x: float) -> float:
	return Vector2(x, 0.0).x


static func clear() -> void:
	_fill.clear()
	_outline.clear()
	_circle.clear()
	_arc.clear()
	_seen.clear()


## Malha do polígono preenchido (null = ainda não vale a pena: forma vista pela 1ª vez).
static func fill_mesh(pts: PackedVector2Array) -> ArrayMesh:
	var m: ArrayMesh = _fill.get(pts)
	if m:
		stat_hits += 1
		return m
	if not _second_sight(["f", pts]):
		return null
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		return null
	var cols := PackedColorArray()
	cols.resize(pts.size())
	cols.fill(Color.WHITE)
	m = _make_mesh(pts, cols, idx)
	_store(_fill, pts, m)
	return m


## Malha do contorno FECHADO suavizado (`draw_polyline(fechado, cor, largura, true)`).
static func outline_mesh(closed: PackedVector2Array, width: float) -> ArrayMesh:
	var by_w: Dictionary = _outline.get(width, {})
	var m: ArrayMesh = by_w.get(closed)
	if m:
		stat_hits += 1
		return m
	if not _second_sight(["o", width, closed]):
		return null
	m = _polyline_mesh(closed, width)
	if m == null:
		return null
	if by_w.is_empty():
		_outline[width] = by_w
	_store(by_w, closed, m)
	return m


## Malha do círculo cheio sem suavização (`draw_circle(centro, raio, cor)`).
static func circle_mesh(center: Vector2, radius: float) -> ArrayMesh:
	var key := Vector3(center.x, center.y, radius)
	var m: ArrayMesh = _circle.get(key)
	if m:
		stat_hits += 1
		return m
	if not _second_sight(["c", key]):
		return null
	var major := f32(radius)
	var pts := PackedVector2Array()
	pts.resize(ELLIPSE_SEGMENTS + 2)
	pts[ELLIPSE_SEGMENTS + 1] = center
	var step := f32(TAU / ELLIPSE_SEGMENTS)
	for i in ELLIPSE_SEGMENTS + 1:
		var angle := f32(i * step)
		pts[i] = Vector2(f32(f32(cos(angle)) * major), f32(f32(sin(angle)) * major)) + center
	var idx := PackedInt32Array()
	idx.resize(ELLIPSE_SEGMENTS * 3)
	for i in ELLIPSE_SEGMENTS:
		idx[i * 3] = ELLIPSE_SEGMENTS + 1
		idx[i * 3 + 1] = i
		idx[i * 3 + 2] = i + 1
	var cols := PackedColorArray()
	cols.resize(pts.size())
	cols.fill(Color.WHITE)
	m = _make_mesh(pts, cols, idx)
	_store(_circle, key, m)
	return m


## Malha do arco suavizado (`draw_arc(centro, raio, início, fim, n, cor, largura, true)`).
static func arc_mesh(center: Vector2, radius: float, start: float, end: float, count: int, width: float) -> ArrayMesh:
	var key := [center, radius, start, end, count, width]
	var m: ArrayMesh = _arc.get(key)
	if m:
		stat_hits += 1
		return m
	if not _second_sight(["a", key]):
		return null
	# CanvasItem::draw_ellipse_arc
	var r := f32(radius)
	var delta := f32(clampf(f32(f32(end) - f32(start)), f32(-TAU), f32(TAU)))
	var pts := PackedVector2Array()
	pts.resize(count)
	for i in count:
		var theta := f32(f32(f32(i / f32(count - 1.0)) * delta) + f32(start))
		pts[i] = center + Vector2(f32(r * f32(cos(theta))), f32(r * f32(sin(theta))))
	m = _polyline_mesh(pts, width)
	if m == null:
		return null
	_store(_arc, key, m)
	return m


# --- Interno --------------------------------------------------------------------------------

static func _second_sight(key: Variant) -> bool:
	if _seen.has(key):
		_seen.erase(key)
		stat_built += 1
		return true
	stat_misses += 1
	if _seen.size() >= MAX_SEEN:
		_seen.clear()
	_seen[key] = true
	return false


static func _store(d: Dictionary, key: Variant, m: ArrayMesh) -> void:
	if d.size() >= MAX_MESHES:
		d.clear()
	d[key] = m


static func _make_mesh(pts: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## RendererCanvasCull::canvas_item_get_compensated_antialiasing_width
static func _compensated_width(w: float) -> float:
	w = f32(w)
	if w > 0.0:
		if w <= f32(FEATHER_SIZE * 2.0 + CMP_EPSILON):
			return f32(w * 0.5)
		elif w <= f32(FEATHER_SIZE * 4.0 + CMP_EPSILON):
			return f32(remap(w, FEATHER_SIZE * 2.0, FEATHER_SIZE * 4.0, f32(w * 0.5), f32(w - FEATHER_SIZE * 0.5)))
		return f32(w - FEATHER_SIZE * 0.5)
	return w


## compute_polyline_segment_dir
static func _segment_dir(p: PackedVector2Array, i: int, prev: Vector2) -> Vector2:
	if i == p.size() - 1:
		return prev
	var d := (p[i + 1] - p[i]).normalized()
	return prev if d.is_zero_approx() else d


## compute_polyline_edge_offset_clamped
static func _edge_offset_clamped(seg: Vector2, prev: Vector2) -> Vector2:
	var length := 1.0
	var bisector := (prev * seg.length() - seg * prev.length()).normalized()
	var angle := f32(atan2(bisector.cross(prev), bisector.dot(prev)))
	var sin_angle := f32(sin(angle))
	if not is_zero_approx(sin_angle) and not seg.is_equal_approx(prev):
		length = f32(1.0 / sin_angle)
		length = clampf(length, -3.0, 3.0)
	else:
		bisector = seg.orthogonal()
	if bisector.is_zero_approx():
		bisector = seg.orthogonal()
	return bisector * length


## RendererCanvasCull::canvas_item_add_polyline(antialias = true), só o caso FECHADO (loop).
## As 3 faixas (central, borda esquerda, borda direita) viram triângulos numa malha só, na ordem.
static func _polyline_mesh(p: PackedVector2Array, width: float) -> ArrayMesh:
	var n := p.size()
	if n < 3 or not p[0].is_equal_approx(p[n - 1]):
		return null   # contorno aberto: fica no caminho normal
	var w := _compensated_width(width)
	if w < 0.0:
		return null
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
	var border_size := FEATHER_SIZE
	if w < 1.0:
		border_size = f32(border_size * w)
	var half := f32(w * 0.5)
	var mid := PackedVector2Array()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	mid.resize(n * 2)
	left.resize(n * 2)
	right.resize(n * 2)
	var prev := Vector2.ZERO
	for i in n:
		var seg := _segment_dir(p, i, prev)
		if i == 0:
			prev = last_dir
		elif i == n - 1:
			prev = first_dir
		var base := _edge_offset_clamped(seg, prev)
		var edge := base * half
		var border := base * border_size
		var pos := p[i]
		var j := i * 2
		mid[j] = pos + edge
		mid[j + 1] = pos - edge
		left[j] = pos + edge
		left[j + 1] = pos + edge + border
		right[j] = pos - edge
		right[j + 1] = pos - edge - border
		prev = seg
	# a ordem de desenho do motor: faixa central, depois esquerda, depois direita
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var clear_white := Color(1, 1, 1, 0)
	for strip_i in 3:
		var strip: PackedVector2Array = [mid, left, right][strip_i]
		var base_i := pts.size()
		for k in strip.size():
			pts.append(strip[k])
			cols.append(Color.WHITE if strip_i == 0 or k % 2 == 0 else clear_white)
		for k in strip.size() - 2:
			idx.append(base_i + k)
			idx.append(base_i + k + 1)
			idx.append(base_i + k + 2)
	return _make_mesh(pts, cols, idx)
