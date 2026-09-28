class_name CastleLayer
extends BackdropSilhouette
## Castelo principal (à esquerda, sobre um penhasco) e forte menor (à direita), desenhados por
## código a partir de peças: rocha, torres com pináculos finos, torrinhas, muralhas com ameias,
## janelas góticas. Massa escura contra o céu; a borda voltada para a lua recebe luz fria.
## As luzes roxas das janelas ficam no filho CastleLights (animado); aqui as janelas são escuras.

@export var wall_top := Color(0.05, 0.058, 0.095)
@export var wall_base := Color(0.11, 0.13, 0.2)
@export var rock_top := Color(0.085, 0.1, 0.155)
@export var rock_base := Color(0.2, 0.24, 0.33)
@export var rim_color := Color(0.62, 0.7, 0.92)
@export var window_color := Color(0.12, 0.13, 0.22)

## Rochas: contornos (sentido horário) — penhasco do castelo e colina do forte.
const ROCKS := [
	[Vector2(200, 372), Vector2(236, 268), Vector2(272, 226), Vector2(318, 196), Vector2(356, 178),
		Vector2(430, 172), Vector2(528, 173), Vector2(566, 186), Vector2(594, 214), Vector2(616, 252),
		Vector2(642, 300), Vector2(672, 350), Vector2(690, 372)],
	[Vector2(1250, 372), Vector2(1268, 318), Vector2(1292, 272), Vector2(1318, 250), Vector2(1400, 244),
		Vector2(1440, 256), Vector2(1478, 290), Vector2(1500, 372)],
]
## Torres: [x esquerdo, largura, topo, base, altura do pináculo]
const TOWERS := [
	[350, 16, 134, 178, 24], [378, 28, 98, 178, 42], [438, 62, 66, 178, 62], [520, 28, 90, 178, 48],
	[560, 15, 126, 180, 22], [406, 11, 112, 178, 30], [505, 10, 104, 178, 34],
	[1300, 13, 176, 252, 18], [1326, 26, 116, 252, 42], [1366, 19, 146, 252, 26],
]
## Torrinhas nos cantos da menagem: [x, largura, topo, base, pináculo]
const TURRETS := [[431, 10, 60, 104, 26], [497, 10, 58, 104, 30]]
## Muralhas: [x0, x1, topo, base] (com ameias)
const WALLS := [[352, 575, 130, 180], [1298, 1392, 180, 254]]
## Janelas (centro); tamanho padrão 3×7, arco no topo.
const WINDOWS := [
	Vector2(447, 92), Vector2(461, 92), Vector2(476, 92), Vector2(490, 92),
	Vector2(454, 124), Vector2(483, 124), Vector2(468, 150),
	Vector2(387, 116), Vector2(397, 116), Vector2(392, 148),
	Vector2(529, 108), Vector2(539, 108), Vector2(534, 142),
	Vector2(412, 150), Vector2(424, 150), Vector2(508, 152), Vector2(548, 152),
	Vector2(357, 150), Vector2(566, 146),
	Vector2(1334, 138), Vector2(1344, 138), Vector2(1339, 172), Vector2(1375, 166), Vector2(1318, 206),
]
const WINDOW_SIZE := Vector2(3, 7)


func _build() -> void:
	for rock in ROCKS:
		_add_rock(PackedVector2Array(rock))
	for w in WALLS:
		_add_wall(w[0], w[1], w[2], w[3])
	for t in TOWERS:
		_add_tower(t[0], t[1], t[2], t[3], t[4])
	for t in TURRETS:
		_add_tower(t[0], t[1], t[2], t[3], t[4])
	for c in WINDOWS:
		_add_window(c, window_color)


## Janelas (para o CastleLights acender).
func window_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for c in WINDOWS:
		out.append(Rect2(c - WINDOW_SIZE / 2.0, WINDOW_SIZE))
	return out


func _add_rock(outline: PackedVector2Array) -> void:
	# borda irregular: subdivide as arestas de cima e sacode um pouco
	var pts := PackedVector2Array()
	for i in outline.size() - 1:
		var a := outline[i]
		var b := outline[i + 1]
		var n := maxi(1, int(a.distance_to(b) / 7.0))
		for k in n:
			var p := a.lerp(b, float(k) / n)
			if k > 0 and i > 0 and i < outline.size() - 2:
				p.y += (noise1(p.x / 6.0, 3.0) - 0.5) * 5.0
				p.x += (noise1(p.y / 6.0, 5.0) - 0.5) * 3.0
			pts.append(p)
	pts.append(outline[outline.size() - 1])
	var y_top := 1e9
	for p in pts:
		y_top = minf(y_top, p.y)
	add_polygon(pts, rock_top, rock_base, y_top, 372.0)
	var top_edge := pts.slice(1, pts.size() - 1)
	add_rim(top_edge, rim_color, 1.5, 0.55)
	add_solid_line(top_edge, rock_top, 1.0)


func _add_wall(x0: float, x1: float, top: float, base: float) -> void:
	add_polygon(PackedVector2Array([Vector2(x0, top), Vector2(x1, top), Vector2(x1, base), Vector2(x0, base)]),
		wall_top, wall_base, top - 10.0, base + 40.0)
	var x := x0 + 1.0
	while x + 4.0 <= x1:   # ameias
		add_polygon(PackedVector2Array([Vector2(x, top - 4), Vector2(x + 4, top - 4), Vector2(x + 4, top + 0.5), Vector2(x, top + 0.5)]),
			wall_top, wall_top, 0.0, 1.0)
		x += 7.0


func _add_tower(x: float, w: float, top: float, base: float, spire: float) -> void:
	var cx := x + w / 2.0
	var lit_right := moon_center.x > cx
	add_polygon(PackedVector2Array([Vector2(x, top), Vector2(x + w, top), Vector2(x + w, base), Vector2(x, base)]),
		wall_top, wall_base, top - spire, base + 40.0)
	# beiral + pináculo fino com lados côncavos + haste no topo
	add_polygon(PackedVector2Array([Vector2(x - 1.5, top - 3), Vector2(x + w + 1.5, top - 3), Vector2(x + w + 1.5, top + 1), Vector2(x - 1.5, top + 1)]),
		wall_top, wall_top, 0.0, 1.0)
	# torre larga (menagem): telhado baixo + pináculo esguio no meio (silhueta gótica, não pirâmide)
	var sx := x
	var sw := w
	var roof_top := top - 3
	if w > 36.0:
		roof_top = top - 12
		add_polygon(PackedVector2Array([Vector2(x - 1.5, top - 3), Vector2(x + w * 0.25, roof_top), Vector2(x + w * 0.75, roof_top),
			Vector2(x + w + 1.5, top - 3)]), wall_top, wall_top, 0.0, 1.0)
		sw = 22.0
		sx = cx - sw / 2.0
	var apex := Vector2(cx, roof_top - spire)
	var spire_pts := PackedVector2Array([
		Vector2(sx - 1.0, roof_top), Vector2(sx + sw * 0.2, roof_top - spire * 0.42), apex,
		Vector2(sx + sw * 0.8, roof_top - spire * 0.42), Vector2(sx + sw + 1.0, roof_top),
	])
	add_polygon(spire_pts, wall_top, wall_top, 0.0, 1.0)
	add_solid_line(PackedVector2Array([apex, apex - Vector2(0, 5)]), wall_top, 1.0)
	add_solid_line(spire_pts, wall_top, 1.0)
	# luz de borda: aresta do pináculo e lateral da torre voltadas para a lua
	var edge_x := x + w if lit_right else x
	var spire_edge := PackedVector2Array([apex, spire_pts[3] if lit_right else spire_pts[1], spire_pts[4] if lit_right else spire_pts[0]])
	add_solid_line(spire_edge, Color(rim_color, 0.55), 1.2)
	add_line(PackedVector2Array([Vector2(edge_x, top + 1), Vector2(edge_x, lerpf(top, base, 0.6))]),
		PackedColorArray([Color(rim_color, 0.45), Color(rim_color, 0.0)]), 1.2)


func _add_window(c: Vector2, col: Color) -> void:
	var r := Rect2(c - WINDOW_SIZE / 2.0, WINDOW_SIZE)
	add_polygon(PackedVector2Array([
		Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.position.y + 1.5), Vector2(c.x, r.position.y),
		Vector2(r.end.x, r.position.y + 1.5), Vector2(r.end.x, r.end.y),
	]), col, col, 0.0, 1.0)
