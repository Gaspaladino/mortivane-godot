class_name CodeDrawnUnitVisual
extends UnitVisual
## Base dos visuais desenhados 100% por código: utilitários de desenho e o estado comum
## (tempo, semente, irregularidade, clarão de dano, escurecimento na morte).
## Não tem rig nem animação: cada unidade (WarriorVisual, SentinelVisual…) monta o seu.
##
## Versão sombra (revivida pelo necromante): a subclasse marca `shadow = true` em _init; o
## setup() resolve o ShadowStyle (o da UnitDef ou o padrão do projeto) e chama
## _apply_shadow_style(style), onde a unidade converte a SUA paleta viva (style.convert) e
## liga os efeitos de ShadowFX. Assim toda sombra segue a mesma regra visual.

## Contorno de todas as partes (escuro na viva; roxo na sombra).
var outline := Color("20232a")
var outline_w := 1.1
## Esta é a versão sombra da unidade?
var shadow := false
## Estilo da sombra em uso (null na versão viva).
var shadow_style: ShadowStyle
## Passada do contorno de silhueta (sombra): _poly/_circle/_line desenham só a borda roxa,
## engordada; a passada normal vem por cima e deixa aparecer só a silhueta externa.
var _rim_pass := false
## Cor para a qual as partes clareiam no HIT (branco = clarão limpo).
var flash_color := Color.WHITE
## Irregularidade geral do movimento (0 = limpo).
var jitter := 0.0
## Etapa 3 da otimização: formas que se repetem (mesmos pontos no espaço da peça) viram malhas
## cacheadas (DrawCache), desenhadas com `draw_mesh` — mesma geometria e mesmos pixels, sem triangular
## a cada quadro e com metade dos draw calls por contorno. false = sempre o caminho direto.
var use_draw_cache := true

var _time := 0.0
var _seed := 0.0
## 0..1: quanto clarear para flash_color (HIT).
var p_flash := 0.0
## 0..1: quanto escurecer (morte).
var p_dim := 0.0


func setup(p_unit: CombatUnit, p_def: UnitDef) -> void:
	super(p_unit, p_def)
	if shadow:
		shadow_style = p_def.shadow_style if p_def and p_def.shadow_style else ShadowStyle.get_default()
		outline = shadow_style.edge
		outline_w = shadow_style.edge_width
		_apply_shadow_style(shadow_style)


## Desenha `body` duas vezes na sombra: primeiro a silhueta roxa, depois o corpo normal.
func _draw_with_rim(body: Callable) -> void:
	if shadow_style and shadow_style.rim_width > 0.0:
		_rim_pass = true
		body.call()
		_rim_pass = false
	body.call()


## Ponto de extensão das sombras: converter a paleta viva e ajustar detalhes.
func _apply_shadow_style(_style: ShadowStyle) -> void:
	pass


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
	if _rim_pass:
		_rim_poly(pts)
		return
	_fill_poly(pts, fill)
	_outline_closed(pts, _c(outline), outline_w)


func _circle(center: Vector2, radius: float, fill: Color) -> void:
	if _rim_pass:
		_fill_circle(center, radius + shadow_style.rim_width, _rim_color())
		return
	_fill_circle(center, radius, fill)
	var m := DrawCache.arc_mesh(center, radius, 0.0, TAU, 16, outline_w) if use_draw_cache else null
	if m:
		draw_mesh(m, null, Transform2D.IDENTITY, _c(outline))
	else:
		draw_arc(center, radius, 0.0, TAU, 16, _c(outline), outline_w, true)


## = draw_colored_polygon(pts, col), pela malha cacheada quando a forma se repete.
func _fill_poly(pts: PackedVector2Array, col: Color) -> void:
	var m := DrawCache.fill_mesh(pts) if use_draw_cache else null
	if m:
		draw_mesh(m, null, Transform2D.IDENTITY, col)
	else:
		draw_colored_polygon(pts, col)


## = draw_polyline(pts + [pts[0]], col, width, true) (contorno fechado suavizado).
func _outline_closed(pts: PackedVector2Array, col: Color, width: float) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	var m := DrawCache.outline_mesh(closed, width) if use_draw_cache else null
	if m:
		draw_mesh(m, null, Transform2D.IDENTITY, col)
	else:
		draw_polyline(closed, col, width, true)


## = draw_circle(center, radius, col) (cheio, sem suavização).
func _fill_circle(center: Vector2, radius: float, col: Color) -> void:
	var m := DrawCache.circle_mesh(center, radius) if use_draw_cache else null
	if m:
		draw_mesh(m, null, Transform2D.IDENTITY, col)
	else:
		draw_circle(center, radius, col)


func _line(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	if _rim_pass:
		return
	draw_line(a, b, col, width, true)


func _rim_color() -> Color:
	var k := 1.0 - clampf(p_dim / 0.2, 0.0, 1.0)   # a borda se apaga com a morte
	var col := shadow_style.rim.lerp(shadow_style.edge, 1.0 - k)
	return _c(col)


func _rim_poly(pts: PackedVector2Array) -> void:
	var col := _rim_color()
	_fill_poly(pts, col)
	_outline_closed(pts, col, outline_w + shadow_style.rim_width * 2.0)


static func _ease_out(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x)


static func _ease_in_out(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)
