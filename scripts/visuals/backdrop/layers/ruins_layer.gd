class_name RuinsLayer
extends BackdropSilhouette
## Estruturas secundárias do horizonte: pontes/aquedutos em arco (com vãos quebrados) e torres
## partidas. Enriquecem o horizonte e preenchem o espaço entre montanhas e castelo.

@export var top_color := Color(0.075, 0.09, 0.14)
@export var base_color := Color(0.2, 0.24, 0.33)
@export var rim_color := Color(0.6, 0.68, 0.9)

## Pontes: {x0, x1, topo, tabuleiro, base, vãos, largura do pilar, quebrada no início/fim}
const BRIDGES := [
	{x0 = 574.0, x1 = 712.0, top = 150.0, deck = 13.0, base = 272.0, spans = 3, pier = 11.0, broken_start = false, broken_end = true},
	{x0 = 1156.0, x1 = 1242.0, top = 206.0, deck = 11.0, base = 300.0, spans = 2, pier = 10.0, broken_start = false, broken_end = true},
	{x0 = 1270.0, x1 = 1318.0, top = 214.0, deck = 11.0, base = 300.0, spans = 1, pier = 10.0, broken_start = true, broken_end = false},
]
## Torres partidas: [x, largura, topo, base]
const BROKEN_TOWERS := [[900, 18, 246, 318], [1098, 15, 262, 318], [766, 13, 272, 318]]


func _build() -> void:
	for b in BRIDGES:
		_add_bridge(b)
	for t in BROKEN_TOWERS:
		_add_broken_tower(t[0], t[1], t[2], t[3])


func _add_bridge(b: Dictionary) -> void:
	var x0: float = b.x0
	var x1: float = b.x1
	var top: float = b.top
	var deck: float = b.deck
	var base: float = b.base
	var spans: int = b.spans
	var pier: float = b.pier
	var span_w := (x1 - x0 - pier) / spans
	var r := (span_w - pier) / 2.0
	var spring := top + deck + r
	# borda de cima (com a ponta quebrada, se for o caso)
	var top_edge := PackedVector2Array()
	var x := x0
	while x <= x1 + 0.01:
		var y := top
		if b.broken_end and x > x1 - pier - 14.0:
			y = top + (x - (x1 - pier - 14.0)) * 0.35 + (hash1(x, 2.0) - 0.5) * 5.0
		if b.broken_start and x < x0 + pier + 14.0:
			y = top + ((x0 + pier + 14.0) - x) * 0.35 + (hash1(x, 4.0) - 0.5) * 5.0
		top_edge.append(Vector2(x, minf(y, top + deck * 0.9)))
		x += 3.0
	var outline := PackedVector2Array([Vector2(x0, base)])
	outline.append_array(top_edge)
	outline.append(Vector2(x1, base))
	# de baixo, da direita para a esquerda: pilar, arco, pilar…
	var right := x1
	for s in spans:
		var pier_left := right - pier
		outline.append(Vector2(pier_left, base))
		outline.append(Vector2(pier_left, spring))
		var mid := pier_left - r
		for k in range(1, 12):
			var a := PI * k / 12.0
			outline.append(Vector2(mid + r * cos(a), spring - r * sin(a)))
		outline.append(Vector2(mid - r, spring))
		outline.append(Vector2(mid - r, base))
		right = mid - r
	add_polygon(outline, top_color, base_color, top - 5.0, base + 20.0)
	add_rim(top_edge, rim_color, 1.3, 0.5, 0.3)


func _add_broken_tower(x: float, w: float, top: float, base: float) -> void:
	var pts := PackedVector2Array([Vector2(x, base), Vector2(x, top + 3.0)])
	var n := 4
	for i in range(1, n):
		pts.append(Vector2(x + w * i / n, top + hash1(x + i, 9.0) * 7.0))
	pts.append(Vector2(x + w, top + 5.0))
	pts.append(Vector2(x + w, base))
	add_polygon(pts, top_color, base_color, top, base + 20.0)
	var lit_x := x + w if moon_center.x > x else x
	add_line(PackedVector2Array([Vector2(lit_x, top + 5.0), Vector2(lit_x, lerpf(top, base, 0.5))]),
		PackedColorArray([Color(rim_color, 0.4), Color(rim_color, 0.0)]), 1.1)
	add_polygon(PackedVector2Array([Vector2(x + w / 2 - 1, top + 14), Vector2(x + w / 2 + 1, top + 14),
		Vector2(x + w / 2 + 1, top + 20), Vector2(x + w / 2 - 1, top + 20)]), Color(0.03, 0.035, 0.06), Color(0.03, 0.035, 0.06), 0.0, 1.0)
