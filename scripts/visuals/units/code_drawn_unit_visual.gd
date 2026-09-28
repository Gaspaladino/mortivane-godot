class_name CodeDrawnUnitVisual
extends UnitVisual
## Base dos visuais desenhados 100% por código: utilitários de desenho e o estado comum
## (tempo, semente, irregularidade, clarão de dano, escurecimento na morte).
## Não tem rig nem animação: cada unidade (WarriorVisual, SentinelVisual…) monta o seu.

const OUTLINE_W := 1.1

## Contorno escuro de todas as partes.
var outline := Color("20232a")
## Cor para a qual as partes clareiam no HIT (branco = clarão limpo).
var flash_color := Color.WHITE
## Irregularidade geral do movimento (0 = limpo).
var jitter := 0.0

var _time := 0.0
var _seed := 0.0
## 0..1: quanto clarear para flash_color (HIT).
var p_flash := 0.0
## 0..1: quanto escurecer (morte).
var p_dim := 0.0


## Irregularidade: soma de senos com frequências incomensuráveis (0 quando jitter = 0).
func _wobble() -> float:
	if jitter <= 0.0:
		return 0.0
	return jitter * (sin(_time * 1.3 + _seed) * 0.6 + sin(_time * 3.7 + _seed * 2.0) * 0.4)


# --- Utilitários de desenho --------------------------------------------------------------

func _with(xf: Transform2D) -> void:
	draw_set_transform_matrix(xf)


static func _tf(pos: Vector2, deg: float) -> Transform2D:
	return Transform2D(deg_to_rad(deg), pos)


## Cor final: sombreada (partes de trás), clareada no HIT, escurecida após a morte.
func _c(col: Color, shade := 1.0) -> Color:
	var out := Color(col.r * shade, col.g * shade, col.b * shade, col.a)
	if p_flash > 0.0:
		out = out.lerp(Color(flash_color, out.a), p_flash)
	if p_dim > 0.0:
		out = out.lerp(Color(0.08, 0.07, 0.1, out.a), p_dim)
	return out


func _poly(pts: PackedVector2Array, fill: Color) -> void:
	draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, _c(outline), OUTLINE_W, true)


func _circle(center: Vector2, radius: float, fill: Color) -> void:
	draw_circle(center, radius, fill)
	draw_arc(center, radius, 0.0, TAU, 16, _c(outline), OUTLINE_W, true)


func _line(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	draw_line(a, b, col, width, true)


static func _ease_out(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x)


static func _ease_in_out(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)
