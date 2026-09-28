extends SceneTree
## Teste headless do fundo da arena (arena_backdrop.tscn): estrutura editável e animações.
##   godot --headless -s res://tests/backdrop_test.gd

const LAYERS := ["Sky", "Moon", "FarClouds", "MidClouds", "NearClouds", "FarMountains", "FarFog", "MidMountains",
	"MidFog", "CastleBack", "CastleLights", "Ruins", "NearMountains", "NearFog", "LeftArchitecture", "RightArchitecture",
	"LeftBanner", "RightBanner", "LeftCandles", "RightCandles", "ArenaFloor"]

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bd: ArenaBackdrop = load("res://scenes/arena/arena_backdrop.tscn").instantiate()
	root.add_child(bd)
	await process_frame

	# --- estrutura: cada parte é um nó da própria cena (editável), na ordem de profundidade
	var order := bd.get_children().map(func(n: Node) -> String: return n.name)
	_check(order == LAYERS, "camadas na ordem certa (%s)" % ", ".join(order))
	var depths := bd.parallax_layers().map(func(n: Node2D) -> float: return n.get_meta(&"parallax_depth"))
	_check(depths.size() == LAYERS.size(), "toda camada tem metadado parallax_depth")
	var sorted := depths.duplicate()
	sorted.sort()
	_check(depths == sorted, "profundidade cresce de trás para frente")
	var all := bd.find_children("*", "", true, false)
	_check(all.all(func(n: Node) -> bool: return n.owner == bd), "todos os nós pertencem à cena (nada criado em runtime)")
	_check(not FileAccess.get_file_as_string("res://scenes/arena/arena_backdrop.tscn").contains("novocenario"), "o fundo antigo não é usado")

	# montanhas / castelo / ruínas: Polygon2D editáveis, um nó por peça
	for group in ["FarMountains", "MidMountains", "NearMountains"]:
		var peaks := bd.get_node(group).get_children().filter(func(n: Node) -> bool: return n is Polygon2D)
		_check(peaks.size() >= 5 and peaks.all(func(p: Polygon2D) -> bool: return p.polygon.size() > 10 and p.vertex_colors.size() == p.polygon.size()),
			"%s: picos como Polygon2D com gradiente (%d)" % [group, peaks.size()])
	var far_col: Color = bd.get_node("FarMountains").get_child(0).vertex_colors[0]
	var near_col: Color = bd.get_node("NearMountains").get_child(0).vertex_colors[0]
	_check(far_col.get_luminance() > near_col.get_luminance(), "montanhas distantes mais claras que as próximas")
	var towers := bd.get_node("CastleBack").find_children("Tower*", "Polygon2D", true, false)
	_check(towers.size() >= 8, "castelo: torres como nós separados (%d)" % towers.size())
	_check(bd.get_node("Ruins").get_child_count() >= 4, "ruínas: pontes e torres partidas")

	# nuvens: 3 grupos com nuvens individuais, mais rápidas quanto mais perto
	var speeds := []
	for group in ["FarClouds", "MidClouds", "NearClouds"]:
		var g: BackdropDrift = bd.get_node(group)
		_check(g.get_child_count() >= 3 and g.get_children().all(func(c: Node) -> bool: return c is BackdropCloud), "%s: nuvens individuais" % group)
		speeds.append(g.speed)
	_check(speeds[0] > 0.0 and speeds[0] < speeds[1] and speeds[1] < speeds[2] and speeds[2] < 8.0, "nuvens → direita, parallax de velocidade (%s)" % str(speeds))

	# névoa: 3 faixas, uma no sentido contrário; nenhuma entra no campo
	var fog_speeds := []
	for group in ["FarFog", "MidFog", "NearFog"]:
		var band: BackdropFog = bd.get_node(group).get_child(0)
		fog_speeds.append(band.speed)
		_check(band.position.y + band.size.y <= 385.0 and band.mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s não entra no campo" % group)
		_check(band.breath > 0.0, "%s respira" % group)
	_check(fog_speeds.any(func(s: float) -> bool: return s < 0.0) and fog_speeds.any(func(s: float) -> bool: return s > 0.0), "névoa em sentidos opostos")

	# lua, janelas, estandartes, velas
	_check(bd.moon.position.x > bd.art_size.x * 0.6 and bd.moon.position.y < bd.art_size.y * 0.2 and bd.moon.radius >= 60.0, "lua grande no alto à direita")
	_check(bd.moon.pulse_period >= 5.0 and bd.moon.pulse_period <= 8.0 and bd.moon.pulse_amount <= 0.05, "pulsação da lua lenta e sutil")
	var lights: CastleLights = bd.get_node("CastleLights")
	var windows := lights.windows()
	_check(windows.size() >= 15, "janelas do castelo como nós (%d)" % windows.size())
	var max_lit := 0
	var total_lit := 0
	var any_lit := false
	for step in 300:
		var lit := 0
		for i in windows.size():
			if lights.window_level(i, step * 1.7) > 0.5:
				lit += 1
		max_lit = maxi(max_lit, lit)
		total_lit += lit
		any_lit = any_lit or lit > 0
	var avg := total_lit / 300.0
	_check(any_lit and avg <= 8.0 and max_lit <= windows.size() / 2, "poucas janelas acesas por vez (média %.1f, máx. %d de %d)" % [avg, max_lit, windows.size()])
	_check(bd.get_node("LeftBanner") is BannerSway and bd.get_node("RightBanner") is BannerSway, "estandartes com balanço")
	_check(bd.get_node("LeftCandles").find_children("*", "CandleFlame", false, false).size() >= 3, "velas: chamas como nós")

	# --- animação no jogo
	var cloud: BackdropCloud = bd.get_node("MidClouds").get_child(0)
	var x0 := cloud.position.x
	var fog: BackdropFog = bd.get_node("MidFog").get_child(0)
	for i in 30:
		await process_frame
	_check(cloud.position.x != x0, "nuvens deslizam")
	_check(fog._t > 0.0 and lights.t > 0.0, "névoa e janelas animam")
	# a nuvem reaparece do outro lado sem sair da faixa
	var drift: BackdropDrift = bd.get_node("NearClouds")
	cloud = drift.get_child(0)
	cloud.position.x = drift.wrap_right + 1.0
	await process_frame
	_check(cloud.position.x >= drift.wrap_left and cloud.position.x < drift.wrap_left + 20.0, "nuvem dá a volta fora da tela (x=%.1f)" % cloud.position.x)

	# --- controles
	bd.master_intensity = 0.0
	await process_frame
	var x1 := cloud.position.x
	for i in 5:
		await process_frame
	_check(cloud.position.x == x1 and fog.global_intensity == 0.0, "master_intensity 0 = nada se mexe")
	bd.master_intensity = 1.0
	bd.view_offset = Vector2(100, 0)
	await process_frame
	var sky: Node2D = bd.get_node("Sky")
	var castle: Node2D = bd.get_node("CastleBack")
	_check(is_equal_approx(sky.position.x, 100.0) and bd.get_node("ArenaFloor").position.x == 0.0
		and is_equal_approx(castle.position.x, 100.0 * (1.0 - castle.get_meta(&"parallax_depth"))),
		"parallax: camadas compensam pela profundidade; o chão não se move")

	bd.free()
	print("backdrop_test: %s" % ("OK" if _failures == 0 else "%d falha(s)" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures += 1
		printerr("  FALHOU: ", what)
