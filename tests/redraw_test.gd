extends SceneTree
## Etapa 3 da otimização: redesenho dos vivos.
##   - anel de seleção e barra de HP só são redesenhados quando o que mostram muda (ou com debug);
##   - o corpo continua sendo redesenhado todo quadro (animação);
##   - DrawCache: forma vista 1× segue o caminho direto; na 2ª vira malha; formas diferentes não
##     colidem; o contorno aberto e o polígono degenerado ficam no caminho direto.
## (A igualdade de pixels do DrawCache é validada com render real por tools/bench/draw_cache_pixels.gd.)

const DT := 1.0 / 60.0
var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await _test_overlays()
	_test_cache()
	print("redraw_test: %s" % ("OK" if _failures == 0 else "%d falha(s)" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("  FALHOU: " + msg)


func _test_overlays() -> void:
	var def := UnitCatalog.get_def(&"warrior")
	var u := CombatUnit.new(1, CombatUnit.Team.PLAYER, def.to_stats(), Vector2(300, 300))
	var view := UnitView.new(u, def)
	root.add_child(view)
	await process_frame
	view.set_process(false)
	var n := {view = 0, body = 0, overlay = 0}
	view.draw.connect(func() -> void: n.view += 1)
	view.visual.draw.connect(func() -> void: n.body += 1)
	view._overlay.draw.connect(func() -> void: n.overlay += 1)
	for i in 5:
		view._process(DT)
		await process_frame
	n.view = 0
	n.body = 0
	n.overlay = 0
	for i in 60:
		u.position += Vector2(0.5, 0)   # andando: o corpo anima
		view._process(DT)
		await process_frame
	_check(n.body >= 60, "corpo redesenhado todo quadro (%d)" % n.body)
	_check(n.view == 0 and n.overlay == 0, "anel e barra sem mudança: nenhum redesenho (%d, %d)" % [n.view, n.overlay])
	u.take_damage(5.0)
	view._process(DT)
	await process_frame
	_check(n.overlay == 1, "dano: a barra é redesenhada uma vez (%d)" % n.overlay)
	view.selected = true
	await process_frame
	_check(n.view == 1, "seleção: o anel é redesenhado (%d)" % n.view)
	view.debug_visible = true
	n.view = 0
	n.overlay = 0
	for i in 10:
		view._process(DT)
		await process_frame
	_check(n.view >= 10 and n.overlay >= 10, "debug ligado: anel/debug e texto todo quadro")
	view.queue_free()
	await process_frame


func _test_cache() -> void:
	DrawCache.clear()
	var a := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 3), Vector2(0, 3)])
	var b := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 3.5), Vector2(0, 3)])
	_check(DrawCache.fill_mesh(a) == null, "1ª vez: caminho direto")
	var m := DrawCache.fill_mesh(a)
	_check(m != null and DrawCache.fill_mesh(a) == m, "2ª vez: malha; depois, a mesma malha")
	_check(DrawCache.fill_mesh(b) == null, "forma diferente não colide")
	var arrays := m.surface_get_arrays(0)
	_check(arrays[Mesh.ARRAY_INDEX] == Geometry2D.triangulate_polygon(a), "mesma triangulação do draw_colored_polygon")
	var closed := a.duplicate()
	closed.append(a[0])
	DrawCache.outline_mesh(closed, 1.1)
	var o := DrawCache.outline_mesh(closed, 1.1)
	_check(o != null and o.surface_get_array_len(0) == closed.size() * 2 * 3, "contorno: 3 faixas numa malha só")
	var open := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 3)])
	DrawCache.outline_mesh(open, 1.1)
	_check(DrawCache.outline_mesh(open, 1.1) == null, "contorno aberto fica no caminho direto")
	DrawCache.clear()
