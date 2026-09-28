extends SceneTree
## Teste headless do fundo da arena reconstruído (ArenaBackdrop).
##   godot --headless -s res://tests/backdrop_test.gd

const LAYERS := ["SkyLayer", "MoonLayer", "FarCloudLayer", "MidCloudLayer", "MountainBackLayer", "FogLayerFar",
	"MountainFrontLayer", "CastleLayer", "RuinsLayer", "FogLayerMid", "FogLayerNear", "SideElementsLayer", "ArenaLayer"]

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bd: ArenaBackdrop = load("res://scenes/arena/arena_backdrop.tscn").instantiate()
	root.add_child(bd)
	await process_frame

	# estrutura em camadas, na ordem de profundidade
	var order := bd.get_children().map(func(n: Node) -> String: return n.name)
	_check(order == LAYERS, "camadas na ordem certa (%s)" % ", ".join(order))
	_check(ArenaBackdrop.DEPTHS.keys().map(func(k: StringName) -> String: return String(k)) == LAYERS, "cada camada tem profundidade de parallax")
	var depths := LAYERS.map(func(n: String) -> float: return ArenaBackdrop.DEPTHS[n])
	var sorted := depths.duplicate()
	sorted.sort()
	_check(depths == sorted, "profundidade cresce de trás para frente")

	# o fundo antigo não é mais usado em lugar nenhum da cena
	var scene_text := FileAccess.get_file_as_string("res://scenes/arena/arena_backdrop.tscn")
	_check(not scene_text.contains("novocenario"), "a cena não usa a arte antiga")
	_check(bd.find_children("*", "Sprite2D", true, false).all(func(s: Sprite2D) -> bool:
		return s.texture.resource_path.begins_with("res://assets/art/arena_layers/")), "só sprites do primeiro plano extraído")

	# silhuetas desenhadas por código têm geometria
	for layer in [bd.mountains_back, bd.mountains_front, bd.castle, bd.ruins]:
		_check(layer._indices.size() > 30, "%s tem geometria (%d índices)" % [layer.name, layer._indices.size()])
	_check(bd.castle.window_rects().size() >= 15 and bd.castle_window_lights._windows.size() == bd.castle.window_rects().size(),
		"janelas do castelo ligadas às luzes")
	var back_peak := INF
	for p in bd.mountains_back.peaks:
		back_peak = minf(back_peak, bd.mountains_back.ridge_y(p.x))
	_check(back_peak > 60.0 and back_peak < 250.0, "montanhas do fundo na faixa do horizonte (pico em y=%.0f)" % back_peak)
	_check(bd.moon_center.x > bd.art_size.x * 0.6 and bd.moon_center.y < bd.art_size.y * 0.2, "lua no alto, à direita")

	# retângulos de shader cobrem a largura da arte e não capturam cliques
	for rect in [bd.sky, bd.far_clouds, bd.mid_clouds, bd.fog_far, bd.fog_mid, bd.fog_near]:
		_check(rect.position.x <= 0.0 and rect.position.x + rect.size.x >= bd.art_size.x and rect.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"%s/%s cobre a largura e ignora cliques" % [rect.get_parent().name, rect.name])
	# nada animado do fundo desce para o campo de batalha (y > 380 na arte = chão; o céu só
	# passa um pouco por trás da borda do chão, que é opaca)
	for rect in [bd.far_clouds, bd.mid_clouds, bd.fog_far, bd.fog_mid, bd.fog_near, bd.moon]:
		_check(rect.position.y + rect.size.y <= 385.0, "%s não entra no campo" % rect.get_parent().name)

	# direção do movimento: nuvens da esquerda para a direita; uma neblina no sentido contrário
	_check(_p(bd.far_clouds, "speed") > 0.0 and _p(bd.mid_clouds, "speed") > _p(bd.far_clouds, "speed"),
		"nuvens → direita, a do meio mais rápida que a distante")
	_check(_p(bd.fog_mid, "speed") < 0.0 and _p(bd.fog_far, "speed") > 0.0, "neblina em sentidos opostos")
	_check(absf(_p(bd.fog_far, "speed")) < 5.0 and absf(_p(bd.mid_clouds, "speed")) < 8.0, "velocidades baixas (sutis)")
	_check(_p(bd.moon, "pulse_period") >= 5.0 and _p(bd.moon, "pulse_period") <= 8.0 and _p(bd.moon, "pulse_amount") <= 0.05,
		"pulsação da lua lenta (5–8 s) e quase imperceptível")

	# o tempo avança e chega aos shaders e às luzes
	var t0: float = _p(bd.mid_clouds, "t")
	for i in 20:
		await process_frame
	_check(_p(bd.mid_clouds, "t") > t0 and bd.castle_window_lights.t > 0.0, "o tempo das animações avança")

	# luzes do castelo: nunca todas acesas ao mesmo tempo
	var max_lit := 0
	var any_lit := false
	for step in 200:
		var lit := _lit_windows(bd.castle_window_lights, step * 1.7)
		max_lit = maxi(max_lit, lit)
		any_lit = any_lit or lit > 0
	_check(any_lit and max_lit < bd.castle.window_rects().size(), "janelas acendem, mas nunca todas (máx. %d de %d)" % [max_lit, bd.castle.window_rects().size()])

	# controles
	bd.master_intensity = 0.0
	await process_frame
	_check(_p(bd.banners[0], "amp") == 0.0 and _p(bd.moon, "pulse_amount") == 0.0 and _p(bd.mid_clouds, "t") == 0.0,
		"master_intensity 0 = nada se mexe")
	bd.master_intensity = 1.0
	bd.animated = false
	var t1 := bd.time
	for i in 5:
		await process_frame
	_check(bd.time == t1, "animated = false congela")
	bd.animated = true
	bd.view_offset = Vector2(100, 0)
	await process_frame
	_check(bd.get_node("SkyLayer").position.x == 100.0 and bd.get_node("ArenaLayer").position.x == 0.0
		and is_equal_approx(bd.get_node("CastleLayer").position.x, 100.0 * (1.0 - ArenaBackdrop.DEPTHS.CastleLayer)),
		"parallax: camadas compensam pela profundidade; a arena não se move")
	bd.view_offset = Vector2.ZERO

	bd.free()
	print("backdrop_test: %s" % ("OK" if _failures == 0 else "%d falha(s)" % _failures))
	quit(1 if _failures > 0 else 0)


func _lit_windows(lights: CastleLights, t: float) -> int:
	var n := 0
	for p in lights._params:
		var s: float = sin(t * p[1] + p[3]) + 0.6 * sin(t * p[2] + p[4]) + p[0] - 0.6
		if smoothstep(-0.45, 0.45, s) > 0.5:
			n += 1
	return n


func _p(ci: CanvasItem, name: StringName) -> Variant:
	return (ci.material as ShaderMaterial).get_shader_parameter(name)


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures += 1
		printerr("  FALHOU: ", what)
