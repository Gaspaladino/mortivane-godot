class_name BackdropSilhouette
extends Node2D
## Base das camadas de silhueta do fundo (montanhas, castelo, ruínas), desenhadas 100% por código.
##
## A geometria é montada UMA vez (build) como triângulos com cor por vértice — o que dá o
## gradiente vertical (topo mais escuro, base clareando na neblina) — e desenhada em _draw.
## Por cima vão linhas antialiasadas: contorno suave e a luz de borda da lua (as arestas
## voltadas para a lua clareiam). Nada disso é redesenhado por quadro.
##
## Espaço local = pixels da arte da arena (1672×941).

## Centro da lua (a luz de borda aponta para ela).
@export var moon_center := Vector2(1228, 92)

var _points := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
var _lines: Array = []     # [PackedVector2Array, PackedColorArray, largura]


func _ready() -> void:
	rebuild()


## Recria a geometria (chamar depois de mudar parâmetros exportados).
func rebuild() -> void:
	_points.clear()
	_colors.clear()
	_indices.clear()
	_lines.clear()
	_build()
	queue_redraw()


## Implementado pelas subclasses.
func _build() -> void:
	pass


func _draw() -> void:
	if not _indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _indices, _points, _colors)
	for line in _lines:
		draw_polyline_colors(line[0], line[1], line[2], true)


# --- Construção --------------------------------------------------------------------------

## Polígono simples qualquer, cor pela altura de cada vértice (gradiente vertical).
func add_polygon(poly: PackedVector2Array, top: Color, bottom: Color, y_top: float, y_bottom: float) -> void:
	var tri := Geometry2D.triangulate_polygon(poly)
	var start := _points.size()
	for p in poly:
		_points.append(p)
		_colors.append(top.lerp(bottom, clampf((p.y - y_top) / maxf(1.0, y_bottom - y_top), 0.0, 1.0)))
	for i in tri:
		_indices.append(start + i)


## Faixa de colunas: da linha `ridge` (esquerda→direita) até `base_y`, com gradiente vertical.
func add_ridge_fill(ridge: PackedVector2Array, base_y: float, top: Color, bottom: Color, y_top: float) -> void:
	for i in ridge.size() - 1:
		var a := ridge[i]
		var b := ridge[i + 1]
		var start := _points.size()
		for p in [a, b, Vector2(b.x, base_y), Vector2(a.x, base_y)]:
			_points.append(p)
			_colors.append(top.lerp(bottom, clampf((p.y - y_top) / maxf(1.0, base_y - y_top), 0.0, 1.0)))
		_indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))


func add_line(points: PackedVector2Array, colors: PackedColorArray, width: float) -> void:
	_lines.append([points, colors, width])


func add_solid_line(points: PackedVector2Array, color: Color, width: float) -> void:
	var cols := PackedColorArray()
	cols.resize(points.size())
	cols.fill(color)
	_lines.append([points, cols, width])


## Luz de borda: ao longo de uma aresta (percorrida com o "lado de fora" à esquerda),
## clareia os trechos cuja normal aponta para a lua.
func add_rim(points: PackedVector2Array, color: Color, width: float, strength: float, sharp := 0.55) -> void:
	var cols := PackedColorArray()
	for i in points.size():
		var a := points[maxi(i - 1, 0)]
		var b := points[mini(i + 1, points.size() - 1)]
		var d := (b - a).normalized()
		var n := Vector2(d.y, -d.x)                       # normal "para fora" (para cima numa crista)
		var to_moon := (moon_center - points[i]).normalized()
		var f := smoothstep(sharp, 0.98, n.dot(to_moon))
		cols.append(Color(color, color.a * f * strength))
	_lines.append([points, cols, width])


# --- Ruído determinístico (1D) -----------------------------------------------------------

static func hash1(i: float, s: float) -> float:
	var v := sin(i * 127.1 + s * 311.7) * 43758.5453
	return v - floorf(v)


static func noise1(x: float, s: float) -> float:
	var i := floorf(x)
	var f := x - i
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(hash1(i, s), hash1(i + 1.0, s), f)


static func fbm1(x: float, s: float) -> float:
	return noise1(x, s) * 0.55 + noise1(x * 2.1, s + 3.0) * 0.3 + noise1(x * 4.3, s + 7.0) * 0.15
