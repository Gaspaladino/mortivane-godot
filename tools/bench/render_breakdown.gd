extends SceneTree
## Custo de RENDER das unidades com a simulação PARADA (Sandbox em preparação), no fluxo real
## Main → Sandbox → Arena → Battle → UnitView. Só medição; não muda nada do jogo.
##
## Args (depois de --):  allies=<id>:<n>  enemies=<id>:<n>  mode=normal|frozen|squares|hidden
##                       warmup=<s>  seconds=<s>  count=0|1  skip=a,b  out=<arquivo.json>
##                       extra=<id>:<n>  (n unidades a mais direto pela Battle, sem o limite do Sandbox: medir CPU headless)
##   normal  — como o jogo desenha hoje
##   frozen  — mesmos desenhos, mas os UnitView param de redesenhar (sem _draw em GDScript por quadro):
##             separa o custo de MONTAR o desenho (CPU/GDScript) do custo de ENVIAR/RENDERIZAR
##   squares — as MESMAS CombatUnits e UnitView, mas cada unidade é um quadrado simples (1 draw_rect)
##   hidden  — nenhum visual de unidade (só o cenário)
##   merged  — SIMULA o desenho em lote: cada unidade vira UM triangle array com o mesmo número de
##             triângulos do visual real (tris_player= / tris_enemy=), refeito e reenviado todo quadro.
##             Mede o custo de render/envio da solução "1 draw call por unidade" antes de implementá-la.
## count=1 e skip= só funcionam na cópia instrumentada (tools/bench/render_probe/make_probe_copy.py).

var main: Node
var args := {}
var t := 0.0
var phase := 0
var frames := 0
var acc := 0.0
var worst := 0.0
var dc := 0.0
var objs := 0.0
var prims := 0.0
var probe: GDScript = null
var views: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if ResourceLoader.exists("res://scripts/debug/draw_probe.gd"):
		probe = load("res://scripts/debug/draw_probe.gd")
		if args.get("skip", "") != "":
			probe.skip = PackedStringArray(args["skip"].split(","))
		probe.refresh()
	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)


func _spawn(spec: String, team: int, sb: SandboxController) -> void:
	if spec == "":
		return
	var p := spec.split(":")
	var def := UnitCatalog.get_def(StringName(p[0]))
	for i in int(p[1]):
		sb.add_unit(def, team)


func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 0.3:
		phase = 1
		main._arena_debug = false
		main.show_sandbox()
		var sb: SandboxController = main.current_screen
		_spawn(args.get("allies", ""), CombatUnit.Team.PLAYER, sb)
		_spawn(args.get("enemies", ""), CombatUnit.Team.ENEMY, sb)
		if args.get("extra", "") != "":
			var p: PackedStringArray = args["extra"].split(":")
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			for i in int(p[1]):
				sb.arena.battle.spawn(UnitCatalog.get_def(StringName(p[0])), CombatUnit.Team.ENEMY, Vector2(rng.randf_range(80, 920), rng.randf_range(260, 520)))
		t = 0.0
	elif phase == 1 and t > float(args.get("warmup", "1.5")):
		phase = 2
		var sb: SandboxController = main.current_screen
		views = sb.arena.battle.get_node(sb.arena.battle.entities_path).get_children().filter(func(n): return n is UnitView)
		_apply_mode(args.get("mode", "normal"))
		t = 0.0
	elif phase == 2 and t > 0.5:
		phase = 3   # deixa o modo assentar; mede a partir daqui
		t = 0.0
	elif phase == 3:
		frames += 1
		acc += delta
		worst = maxf(worst, delta)
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		if probe and args.get("count", "0") == "1" and frames == 3:
			probe.counts = {}
			probe.counting = true
			probe.refresh()
		elif probe and probe.counting:
			probe.counting = false
			probe.refresh()
		if t > float(args.get("seconds", "3")):
			_finish()
			return true
	return false


func _apply_mode(mode: String) -> void:
	for v in views:
		var uv: UnitView = v
		match mode:
			"frozen":
				uv.set_process(false)
			"squares", "hidden", "merged":
				uv.visual.visible = false
				uv.get_node("Overlay").visible = false
				uv.set_process(false)
				uv.visual.set_process(false)
				if mode == "merged":
					var tris := int(args.get("tris_player" if uv.unit.team == CombatUnit.Team.PLAYER else "tris_enemy", "2000"))
					uv.add_child(_merged_node(tris, uv.unit.id))
				if mode == "squares":
					var sq := Node2D.new()
					sq.name = "Square"
					var col := Color(0.4, 0.8, 0.5) if uv.unit.team == CombatUnit.Team.PLAYER else Color(0.9, 0.4, 0.35)
					sq.draw.connect(func(): sq.draw_rect(Rect2(-8, -24, 16, 24), col))
					uv.add_child(sq)


## Um nó que redesenha todo quadro UM triangle array (sem índices) de `tris` triângulos pequenos,
## espalhados na área do corpo (≈ 20×34 px), com cor por vértice: o mesmo volume de geometria de um
## visual real, num único comando.
func _merged_node(tris: int, seed: int) -> Node2D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in tris:
		var c := Vector2(rng.randf_range(-10, 10), rng.randf_range(-34, 0))
		var col := Color(rng.randf(), rng.randf(), rng.randf(), 1.0)
		for k in 3:
			pts.append(c + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)))
			cols.append(col)
	var n := Node2D.new()
	n.name = "Merged"
	n.draw.connect(func():
		RenderingServer.canvas_item_add_triangle_array(n.get_canvas_item(), PackedInt32Array(), pts, cols))
	process_frame.connect(n.queue_redraw)   # redesenha todo quadro, como um visual animado
	return n


func _finish() -> void:
	var n := maxi(frames, 1)
	var res := {
		allies = args.get("allies", ""), enemies = args.get("enemies", ""), mode = args.get("mode", "normal"),
		skip = args.get("skip", ""), units = views.size(), frames = frames,
		fps = frames / acc, frame_ms = acc / n * 1000.0, worst_ms = worst * 1000.0,
		draw_calls = dc / n, objects = objs / n, primitives = prims / n,
		renderer = DisplayServer.get_name(),
	}
	if probe and args.get("count", "0") == "1":
		res["commands"] = probe.counts
	var txt := JSON.stringify(res, "  ")
	if args.has("out"):
		var f := FileAccess.open(args["out"], FileAccess.WRITE)
		f.store_string(txt)
	print("RESULT ", JSON.stringify({mode = res.mode, allies = res.allies, enemies = res.enemies, skip = res.skip,
		fps = snappedf(res.fps, 0.1), frame_ms = snappedf(res.frame_ms, 0.01), dc = snappedf(res.draw_calls, 0.1),
		objects = snappedf(res.objects, 0.1)}))
	quit()
