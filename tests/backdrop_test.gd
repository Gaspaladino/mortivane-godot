extends SceneTree
## Teste headless do fundo animado da arena (ArenaBackdrop).
##   godot --headless -s res://tests/backdrop_test.gd

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bd: ArenaBackdrop = load("res://scenes/arena/arena_backdrop.tscn").instantiate()
	root.add_child(bd)
	await process_frame
	var names := ["Sky", "MoonHalo", "CloudsFar", "CloudsNear", "Scenery", "CastleLights", "FogBack", "FogFront",
		"BannerLeft", "BannerRight", "CandlesLeft", "CandlesRight", "CandleGlows"]
	var order := bd.get_children().map(func(n: Node) -> String: return n.name)
	_check(order == names, "camadas na ordem certa (%s)" % ", ".join(order))
	_check(bd.art_size == Vector2(1672, 941) and bd.sky.texture.get_size() == bd.art_size and bd.scenery.texture.get_size() == bd.art_size,
		"camadas alinhadas à arte 1672×941")
	for rect in [bd.clouds_far, bd.clouds_near, bd.castle_lights, bd.fog_back, bd.fog_front]:
		_check(rect.size == bd.art_size and rect.mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s cobre a arte e não captura cliques" % rect.name)
	var data := ArenaLayersData.DATA
	_check(bd.banners[0].position == Vector2(data.banners.left.pos[0], data.banners.left.pos[1]), "estandarte na posição gerada")
	_check(bd.candle_glows.get_child_count() == data.candles.left.lights.size() + data.candles.right.lights.size(), "um halo por chama")
	var mask_import := FileAccess.get_file_as_string("res://assets/art/arena_layers/masks.png.import")
	_check(mask_import.contains("process/fix_alpha_border=false"), "masks.png sem fix_alpha_border (canais são dados)")
	# tempo avança e chega aos shaders
	var t0: float = (bd.clouds_near.material as ShaderMaterial).get_shader_parameter("t")
	for i in 30:
		await process_frame
	var t1: float = (bd.clouds_near.material as ShaderMaterial).get_shader_parameter("t")
	_check(t1 > t0, "o tempo das animações avança")
	# intensidade 0 = arte estática
	bd.master_intensity = 0.0
	await process_frame
	_check(_p(bd.sky, "flow_amp") == 0.0 and _p(bd.clouds_near, "opacity") == 0.0 and _p(bd.fog_back, "opacity") == 0.0
		and _p(bd.banners[0], "amp") == 0.0 and _p(bd.castle_lights, "strength") == 0.0 and bd.moon_halo.modulate.a == 0.0,
		"master_intensity 0 desliga todas as animações")
	bd.master_intensity = 1.0
	bd.animated = false
	var t2 := bd.time
	for i in 10:
		await process_frame
	_check(bd.time == t2 and _p(bd.banners[1], "amp") == 0.0, "animated = false congela o fundo")
	bd.animated = true
	bd.banner_strength = 2.0
	await process_frame
	_check(is_equal_approx(_p(bd.banners[0], "amp"), ArenaBackdrop.BASE.banner_amp * 2.0), "ajuste de intensidade por elemento")
	bd.free()
	print("backdrop_test: %s" % ("OK" if _failures == 0 else "%d falha(s)" % _failures))
	quit(1 if _failures > 0 else 0)


func _p(ci: CanvasItem, name: StringName) -> float:
	return (ci.material as ShaderMaterial).get_shader_parameter(name)


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures += 1
		printerr("  FALHOU: ", what)
