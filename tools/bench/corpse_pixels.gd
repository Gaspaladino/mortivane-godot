extends SceneTree
## Validação visual da etapa 2 (cadáver estático), com render real.
## Para cada unidade: deixa morrer e assentar (UnitView congela) e captura A. Depois continua
## atualizando o visual "à moda antiga" (update_visual + redesenho) por mais 3 s e captura B.
## A − B = o que o congelamento deixa de mostrar. Saída: <out>/corpse_<id>_{frozen,old}.png e
## uma linha por unidade com a contagem de pixels diferentes.
## Uso: godot --path . --rendering-driver opengl3 -s res://tools/bench/corpse_pixels.gd -- <out>

const IDS := [&"warrior", &"u_warrior", &"arc_battlemage", &"u_arc_battlemage", &"sac_paladin", &"u_sac_paladin"]
const DT := 1.0 / 60.0
var out := "/tmp"


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
	var views := []
	for i in IDS.size():
		var def := UnitCatalog.get_def(IDS[i])
		var u := CombatUnit.new(i + 1, CombatUnit.Team.PLAYER if i % 2 == 0 else CombatUnit.Team.ENEMY, def.to_stats(), Vector2.ZERO)
		var stage := Node2D.new()
		stage.scale = Vector2(3, 3)
		stage.position = Vector2(140 + i * 265, 520)
		root.add_child(stage)
		var view := UnitView.new(u, def)
		view.set_process(false)
		stage.add_child(view)
		views.append(view)
	await process_frame
	for v: UnitView in views:
		for k in 20:
			v._process(DT)
		v.unit.take_damage(v.unit.hp)
	# morte até assentar: o próprio UnitView congela cada cadáver
	for k in int(3.2 / DT):
		for v: UnitView in views:
			v._process(DT)
		await process_frame
	await process_frame
	var frozen := root.get_texture().get_image()
	var all_frozen := views.all(func(v): return v.is_frozen())
	# comportamento antigo: continua atualizando e redesenhando o cadáver por mais 3 s
	for k in int(3.0 / DT):
		for v: UnitView in views:
			v.visual.update_visual(DT)
			v.visual.queue_redraw()
		await process_frame
	await process_frame
	var old := root.get_texture().get_image()
	frozen.save_png(out.path_join("corpses_frozen.png"))
	old.save_png(out.path_join("corpses_old.png"))
	print("CORPSE todos congelados: ", all_frozen)
	for i in IDS.size():
		var x0 := 140 + i * 265 - 130
		var diff := 0
		var maxd := 0.0
		for y in range(300, 700):
			for x in range(maxi(x0, 0), mini(x0 + 260, 1600)):
				var c1 := frozen.get_pixel(x, y)
				var c2 := old.get_pixel(x, y)
				var d := maxf(maxf(absf(c1.r - c2.r), absf(c1.g - c2.g)), absf(c1.b - c2.b))
				if d > 0.0:
					diff += 1
					maxd = maxf(maxd, d)
		print("CORPSE %s  pixels diferentes=%d  maior diferença=%.3f" % [IDS[i], diff, maxd])
	quit()
