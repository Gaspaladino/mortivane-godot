extends SceneTree
## Roteiro FIXO de poses do Paladino (Vivo e Sombra) para comparar pixels entre commits (etapa 5).
## 24 células: andando nas 8 direções, golpes (3 variantes, preparo e impacto), provocação, escudo,
## bloqueio, dano, empurrão, morte (queda e cadáver) e parado. Tudo por prévias e passos fixos de
## 1/60 s, sem relógio real: o mesmo commit sempre gera a mesma imagem.
## Uso: godot --path . --rendering-driver opengl3 --resolution 1600x896 -s res://tools/bench/paladin_pixels.gd -- <saida.png>

const D := PaladinPoseLibrary.Dir
const DT := 1.0 / 60.0
const CELLS := [
	[&"sac_paladin", &"idle", D.RIGHT, 0.9], [&"sac_paladin", &"walk", D.DOWN, 0.4],
	[&"sac_paladin", &"walk", D.DOWN_RIGHT, 0.4], [&"sac_paladin", &"walk", D.RIGHT, 0.4],
	[&"sac_paladin", &"walk", D.UP_RIGHT, 0.4], [&"sac_paladin", &"walk", D.UP, 0.4],
	[&"sac_paladin", &"walk", D.UP_LEFT, 0.4], [&"sac_paladin", &"walk", D.LEFT, 0.4],
	[&"sac_paladin", &"walk", D.DOWN_LEFT, 0.4], [&"sac_paladin", &"attack", D.RIGHT, 0.2],
	[&"sac_paladin", &"attack", D.RIGHT, 0.36], [&"sac_paladin", &"attack", D.UP_RIGHT, 0.36],
	[&"sac_paladin", &"attack", D.DOWN_RIGHT, 0.36], [&"sac_paladin", &"attack", D.LEFT, 0.5],
	[&"sac_paladin", &"taunt", D.RIGHT, 0.45], [&"sac_paladin", &"shield", D.RIGHT, 0.7],
	[&"sac_paladin", &"block", D.RIGHT, 0.06], [&"sac_paladin", &"hit", D.RIGHT, 0.06],
	[&"sac_paladin", &"push", D.RIGHT, 0.14], [&"sac_paladin", &"death", D.RIGHT, 0.8],
	[&"sac_paladin", &"death", D.LEFT, 2.4], [&"u_sac_paladin", &"idle", D.RIGHT, 0.9],
	[&"u_sac_paladin", &"walk", D.RIGHT, 0.4], [&"u_sac_paladin", &"death", D.RIGHT, 2.4],
]


func _initialize() -> void:
	_run(OS.get_cmdline_user_args()[0])


func _run(out: String) -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var bg := ColorRect.new()
	bg.color = Color(0.34, 0.35, 0.38)
	bg.size = Vector2(1600, 896)
	root.add_child(bg)
	var views := []
	for i in CELLS.size():
		var c: Array = CELLS[i]
		var def := UnitCatalog.get_def(c[0])
		var u := CombatUnit.new(i + 1, CombatUnit.Team.PLAYER, def.to_stats(), Vector2.ZERO)
		var stage := Node2D.new()
		stage.scale = Vector2(2.6, 2.6)
		stage.position = Vector2(100 + (i % 8) * 200, 200 + (i / 8) * 290)
		root.add_child(stage)
		var view := UnitView.new(u, def)
		stage.add_child(view)
		views.append(view)
	await process_frame
	for i in views.size():
		var v: UnitView = views[i]
		v.set_process(false)
		var c: Array = CELLS[i]
		if v.visual.has_method("preview"):
			v.visual.preview(c[1], c[2])
		for k in int(round(c[3] / DT)):
			v.visual.update_visual(DT)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out)
	print("PALADIN_PIXELS salvo ", out)
	quit()
