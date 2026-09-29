extends SceneTree
## Validação visual da etapa 3 (DrawCache), com render real.
## As mesmas unidades, na MESMA pose (o visual não é atualizado entre as capturas), desenhadas pelo
## caminho direto (use_draw_cache = false) e pelas malhas cacheadas (true). Compara pixel a pixel.
## Poses: parado, andando, golpe, dano (clarão), morte em andamento — vivas e sombras.
## Uso: godot --path . --rendering-driver opengl3 --resolution 1600x896 -s res://tools/bench/draw_cache_pixels.gd -- <out>

const IDS := [&"warrior", &"u_warrior", &"arc_battlemage", &"u_arc_battlemage", &"u_sac_paladin", &"sac_paladin"]
const DT := 1.0 / 60.0
var out := "/tmp"
var views := []


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	_run()


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var bg := ColorRect.new()
	bg.color = Color(0.36, 0.38, 0.44)
	bg.size = Vector2(1600, 896)
	root.add_child(bg)
	# 6 tipos × 5 poses, em grade
	for row in 5:
		for i in IDS.size():
			var def := UnitCatalog.get_def(IDS[i])
			var u := CombatUnit.new(row * 10 + i + 1, CombatUnit.Team.PLAYER if (i + row) % 2 == 0 else CombatUnit.Team.ENEMY, def.to_stats(), Vector2(0, 0))
			var stage := Node2D.new()
			stage.scale = Vector2(2.2, 2.2)
			stage.position = Vector2(130 + i * 260, 120 + row * 170)
			root.add_child(stage)
			var view := UnitView.new(u, def)
			view.set_process(false)
			stage.add_child(view)
			views.append([view, row])
	await process_frame
	# poses: 0 parado · 1 andando · 2 golpe · 3 dano · 4 morte em andamento
	for k in 40:
		for e in views:
			var v: UnitView = e[0]
			var row: int = e[1]
			if row == 1:
				v.unit.state = CombatUnit.State.MOVING
				v.unit.position += Vector2(0.7, 0.0)
			if row == 2 and k == 30:
				v.unit.state = CombatUnit.State.ATTACKING
				v.on_attack_performed()
			if row == 3 and k == 36:
				v.on_hit()
			if row == 4 and k == 20:
				v.unit.take_damage(v.unit.hp)
			v.visual.update_visual(DT)
	for e in views:
		(e[0] as UnitView).position = Vector2.ZERO
	var totals := {}
	var shots := []
	for mode in [false, true]:
		for e in views:
			var vis = (e[0] as UnitView).visual
			if vis is CodeDrawnUnitVisual:
				vis.use_draw_cache = mode and not (vis is PaladinLiveVisual)
		# 3 redesenhos da mesma pose: com cache, o 1º registra a forma, o 2º cria a malha, o 3º usa
		for rep in 3:
			for e in views:
				(e[0] as UnitView).visual.queue_redraw()
			await process_frame
		await process_frame
		shots.append(root.get_texture().get_image())
		totals[mode] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	shots[0].save_png(out.path_join("draw_cache_off.png"))
	shots[1].save_png(out.path_join("draw_cache_on.png"))
	var diff := 0
	var maxd := 0.0
	for y in 896:
		for x in 1600:
			var c1: Color = shots[0].get_pixel(x, y)
			var c2: Color = shots[1].get_pixel(x, y)
			var d := maxf(maxf(absf(c1.r - c2.r), absf(c1.g - c2.g)), absf(c1.b - c2.b))
			if d > 0.0:
				diff += 1
				maxd = maxf(maxd, d)
	print("DRAWCACHE pixels diferentes=%d  maior diferença=%.4f  draw calls: sem cache=%d  com cache=%d  malhas=%d/%d/%d/%d" % [
		diff, maxd, totals[false], totals[true], DrawCache._fill.size(), DrawCache._outline.size(), DrawCache._circle.size(), DrawCache._arc.size()])
	quit()
