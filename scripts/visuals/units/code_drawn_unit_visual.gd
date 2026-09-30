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

## --- Desenho leve --------------------------------------------------------------------------
## As peças do visual são montadas UMA vez por tipo (LiteBuilder → LitePart, cache estático) e viram a
## MALHA estática do tipo, com um osso por peça (LiteSkin). A cada quadro a pose só move os ossos:
## nada é redesenhado nem reenviado (1 draw call por unidade). Clarão/escurecimento/esmaecer vão por
## material compartilhado (LiteFx). Ver `_part`, `_skin_setup`, `_apply_fx`.
## Montando uma peça? Os utilitários (_poly, _circle, _line, _fill, _disc…) desenham NELE.
var _bake: LiteBuilder = null
## Prefixo das chaves do cache de peças: script + estilo da sombra + variação da instância.
var _bake_prefix := ""
var _fx_material: ShaderMaterial = null
## Corpo como malha estática com ossos (LiteSkin): criado por _skin_setup; null = desenho direto.
var _skin: LiteSkin = null
var _mesh: ArrayMesh = null
static var _part_cache := {}

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
	_bake_prefix = "%s|%s|%s|" % [get_script().resource_path, shadow_style.get_instance_id() if shadow_style else 0, _bake_salt()]


# --- Peças prontas e lote ------------------------------------------------------------------

## Variação do visual que muda a geometria das peças (ex.: parâmetros do Inspector). "" = nenhuma.
func _bake_salt() -> String:
	return ""


## Peça pronta `key` deste tipo de unidade; na 1ª vez, monta chamando `body` no modo de montagem.
## `rim` = versão silhueta da sombra (preenchimento + borda larga na cor da borda roxa).
func _part(key: String, body: Callable, rim := false, flashes := true) -> LitePart:
	var k := _bake_prefix + ("rim:" if rim else "") + key
	var part: LitePart = _part_cache.get(k)
	if part == null:
		part = _bake_part(body, rim, flashes)
		_part_cache[k] = part
	return part


func _bake_part(body: Callable, rim := false, flashes := true) -> LitePart:
	var saved := [p_flash, p_dim, _rim_pass]
	p_flash = 0.0
	p_dim = 0.0
	_rim_pass = rim
	_bake_begin()
	_bake = LiteBuilder.new()
	_bake.flashes = flashes
	body.call()
	var part := _bake.build()
	_bake = null
	_bake_end()
	p_flash = saved[0]
	p_dim = saved[1]
	_rim_pass = saved[2]
	return part


## Pontos de extensão da montagem: neutralizar estado do quadro que não deve entrar na peça.
func _bake_begin() -> void:
	pass


func _bake_end() -> void:
	pass


static func clear_part_cache() -> void:
	_part_cache.clear()


static func part_cache_size() -> int:
	return _part_cache.size()


## Malha do tipo (cache) + esqueleto desta unidade. `layout` = [[LitePart, osso], ...] em ordem de
## desenho; `bones` = nº de ossos. Depois: _draw chama _skin_draw() e a pose vai por _skin.set_bone().
func _skin_setup(layout: Array, bones: int) -> void:
	_mesh = LiteSkin.mesh(_bake_prefix + "mesh", layout)
	_skin = LiteSkin.new(bones)
	_skin.attach(self)
	set_notify_transform(true)
	if is_inside_tree():
		_skin.set_base(get_global_transform())
	queue_redraw()


## O único comando do CanvasItem: a malha (os ossos fazem o resto).
func _skin_draw() -> void:
	if _mesh:
		RenderingServer.canvas_item_add_mesh(get_canvas_item(), _mesh.get_rid())


func _notification(what: int) -> void:
	if _skin == null:
		return
	match what:
		NOTIFICATION_ENTER_TREE, NOTIFICATION_TRANSFORM_CHANGED:
			_skin.set_base(get_global_transform())
		NOTIFICATION_PREDELETE:
			_skin.release()


## Osso de uma peça "segmento" unitário (0,0)→(1,0) esticado de `a` até `b`; a largura da peça é
## mantida (× `width`).
static func _seg_bone(a: Vector2, b: Vector2, width := 1.0) -> Transform2D:
	var d := b - a
	var n := d.orthogonal().normalized() if d.length() > 0.001 else Vector2(0, 1)
	return Transform2D(d, n * width, a)


## Material de clarão/escurecimento/alfa (compartilhado; troca só quando muda).
func _apply_fx(alpha := 1.0) -> void:
	var m := LiteFx.material(flash_color, p_flash, p_dim, alpha)
	if m != _fx_material:
		_fx_material = m
		material = m


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
	if _bake:
		_bake.xf = xf
		return
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
	if _bake:
		_bake.poly(pts, fill, _c(outline), outline_w)
		return
	_fill_poly(pts, fill)
	_outline_closed(pts, _c(outline), outline_w)


func _circle(center: Vector2, radius: float, fill: Color) -> void:
	if _rim_pass:
		_fill_circle(center, radius + shadow_style.rim_width, _rim_color())
		return
	if _bake:
		_bake.circle(center, radius, fill, _c(outline), outline_w)
		return
	_fill_circle(center, radius, fill)
	var m := DrawCache.arc_mesh(center, radius, 0.0, TAU, 16, outline_w) if use_draw_cache else null
	if m:
		draw_mesh(m, null, Transform2D.IDENTITY, _c(outline))
	else:
		draw_arc(center, radius, 0.0, TAU, 16, _c(outline), outline_w, true)


## = draw_colored_polygon(pts, col), pela malha cacheada quando a forma se repete.
func _fill_poly(pts: PackedVector2Array, col: Color) -> void:
	if _bake:
		_bake.fill(pts, col)
		return
	var m := DrawCache.fill_mesh(pts) if use_draw_cache else null
	if m:
		draw_mesh(m, null, Transform2D.IDENTITY, col)
	else:
		draw_colored_polygon(pts, col)


## = draw_polyline(pts + [pts[0]], col, width, true) (contorno fechado suavizado).
func _outline_closed(pts: PackedVector2Array, col: Color, width: float) -> void:
	if _bake:
		_bake.outline(pts, col, width, true)
		return
	var closed := pts.duplicate()
	closed.append(pts[0])
	var m := DrawCache.outline_mesh(closed, width) if use_draw_cache else null
	if m:
		draw_mesh(m, null, Transform2D.IDENTITY, col)
	else:
		draw_polyline(closed, col, width, true)


## = draw_circle(center, radius, col) (cheio, sem suavização).
func _fill_circle(center: Vector2, radius: float, col: Color) -> void:
	if _bake:
		_bake.disc(center, radius, col)
		return
	var m := DrawCache.circle_mesh(center, radius) if use_draw_cache else null
	if m:
		draw_mesh(m, null, Transform2D.IDENTITY, col)
	else:
		draw_circle(center, radius, col)


func _line(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	if _rim_pass:
		return
	if _bake:
		_bake.line(a, b, col, width)
		return
	draw_line(a, b, col, width, true)


## = draw_colored_polygon (sem contorno). Na silhueta da sombra, não desenha.
func _fill(pts: PackedVector2Array, col: Color) -> void:
	if _rim_pass:
		return
	if _bake:
		_bake.fill(pts, col)
		return
	draw_colored_polygon(pts, col)


## = draw_circle (cheio, sem contorno). Na silhueta da sombra, não desenha.
func _disc(center: Vector2, radius: float, col: Color) -> void:
	if _rim_pass:
		return
	if _bake:
		_bake.disc(center, radius, col)
		return
	draw_circle(center, radius, col)


## = draw_polyline suavizado (aberto). Na silhueta da sombra, não desenha.
func _pline(pts: PackedVector2Array, col: Color, width: float) -> void:
	if _rim_pass:
		return
	if _bake:
		_bake.polyline(pts, col, width)
		return
	draw_polyline(pts, col, width, true)


## = draw_arc suavizado. Na silhueta da sombra, não desenha.
func _arc_line(center: Vector2, radius: float, start: float, end: float, segments: int, col: Color, width: float) -> void:
	if _rim_pass:
		return
	if _bake:
		_bake.arc(center, radius, start, end, segments, col, width)
		return
	draw_arc(center, radius, start, end, segments, col, width, true)


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
