extends SceneTree
## STRESS TEST / PROFILING do combate (só medição — não muda regra, IA, stats nem visual).
##
## Roda UM cenário no jogo real (Main → Sandbox → Arena → Battle → UnitView) e grava:
##   <out>/frames_<label>.csv   — uma linha por quadro medido
##   <out>/summary.jsonl        — uma linha JSON por execução (médias, picos, contadores/s)
##
## Uso (ver tools/bench/README.md e run_matrix.sh):
##   godot --headless --path . --fixed-fps 60 -s res://tools/bench/stress_bench.gd -- \
##       allies=40 enemies=40 profile=warriors phase=full visual=normal seconds=8 out=/tmp/bench
##
## Parâmetros (chave=valor):
##   allies, enemies   quantidade por lado (acima de 40 usa as colunas seguintes da mesma grade)
##   profile           warriors | sentinels | mixed (Guerreiro+Sentinela) | paladins | all (os 3)
##   phase             spawn (parado) | move (só anda) | target (alvo, sem ataque) | full (combate)
##   visual            normal | nodraw (anima mas não desenha o corpo) | minimal (marcador fixo) |
##                     hidden (nenhum visual de unidade)
##   sim               bench (BenchCombatSim, com contadores) | real (CombatSim do jogo, sem contadores)
##   timing            1 | 0  (cronômetros dentro da simulação)
##   probes            1 | 0  (cronômetro do _draw de cada nó via sinal `draw`)
##   seconds, warmup   segundos de jogo medidos / descartados no início
##   realtime          0 = passo fixo (use --fixed-fps 60: cada quadro = 1/60 s de jogo, reproduzível)
##                     1 = tempo real (dt do relógio; a Battle faz até 6 passos por quadro quando cai)
##   dead_enemies      1 = mata todos os inimigos (pela simulação) antes de começar: N vivos × 0 + N cadáveres
##   label, out        nome da execução / pasta de saída

const PROFILES := {
	warriors = [&"warrior"],
	sentinels = [&"arc_battlemage"],
	mixed = [&"warrior", &"arc_battlemage"],
	paladins = [&"sac_paladin"],
	all = [&"warrior", &"arc_battlemage", &"sac_paladin"],
}

var cfg := {
	allies = 40, enemies = 40, profile = "warriors", phase = "full", visual = "normal", sim = "bench",
	timing = 1, probes = 1, dead_enemies = 0, seconds = 8.0, warmup = 1.0, realtime = 0, label = "", out = "user://bench",
}

var main: Node
var sandbox: SandboxController
var battle: Battle
var driver: BenchDriver


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=", true, 1)
		if kv.size() == 2 and cfg.has(kv[0]):
			cfg[kv[0]] = type_convert(kv[1], typeof(cfg[kv[0]]))
	if cfg.label == "":
		cfg.label = "%s_%dx%d_%s_%s_%s" % [cfg.profile, cfg.allies, cfg.enemies, cfg.phase, cfg.visual, cfg.sim]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cfg.out))
	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	_setup.call_deferred()


func _setup() -> void:
	await process_frame
	main.show_sandbox()
	await process_frame
	sandbox = main.current_screen
	battle = sandbox.get_arena().battle
	var mode: int = {spawn = BenchCombatSim.Mode.FULL, move = BenchCombatSim.Mode.MOVE_ONLY,
		target = BenchCombatSim.Mode.TARGET_ONLY, full = BenchCombatSim.Mode.FULL}[cfg.phase]
	BenchCombatSim.next_mode = mode as BenchCombatSim.Mode
	BenchCombatSim.next_timing = cfg.timing == 1
	battle.sim_script = BenchCombatSim if cfg.sim == "bench" else null
	battle.clear()
	var defs: Array = PROFILES[cfg.profile]
	for side in 2:
		var team := CombatUnit.Team.PLAYER if side == 0 else CombatUnit.Team.ENEMY
		var n: int = cfg.allies if side == 0 else cfg.enemies
		for i in n:
			var def := UnitCatalog.get_def(defs[i % defs.size()])
			if i < SandboxController.MAX_PER_SIDE:
				sandbox.add_unit(def, team)
			else:   # acima do limite do Sandbox: mesma grade, colunas seguintes
				battle.spawn(def, team, SandboxController.slot_position(team, i))
	driver = BenchDriver.new()
	driver.setup(self)
	root.add_child(driver)
	if cfg.dead_enemies == 1:
		# cenário "N sobreviventes × 0 inimigos vivos + N cadáveres": mata pela própria simulação
		var killer: CombatUnit = null
		for u in battle.sim.units:
			if u.team == CombatUnit.Team.PLAYER:
				killer = u
				break
		for u in battle.sim.units:
			if u.team == CombatUnit.Team.ENEMY:
				battle.sim._apply_damage(killer, u, u.hp)
	if cfg.phase != "spawn":
		sandbox.start_combat()


## Chamado pelo driver no fim.
func finish(summary: Dictionary) -> void:
	var f := FileAccess.open(cfg.out.path_join("summary.jsonl"), FileAccess.READ_WRITE if FileAccess.file_exists(cfg.out.path_join("summary.jsonl")) else FileAccess.WRITE)
	f.seek_end()
	f.store_line(JSON.stringify(summary))
	f.close()
	print("BENCH %s  fps=%.1f  frame=%.2fms  p95=%.2fms  max=%.2fms  sim=%.2fms  views=%.2fms  draw=%.2fms" % [
		cfg.label, summary.fps_avg, summary.frame_ms_avg, summary.frame_ms_p95, summary.frame_ms_max,
		summary.sim_ms, summary.view_update_ms, summary.draw_ms_total])
	quit()


## Nó que mede cada quadro. Fica por último na ordem de processamento.
class BenchDriver extends Node:
	var bench
	var cfg: Dictionary
	var views: Array = []
	var frames := 0
	var measured := 0
	var warm_frames := 0
	var target_frames := 0
	var last_t := 0
	var wall_start := 0
	var game_t0 := 0.0
	var rows: Array = []
	var prev_counters := {}
	var start_counters := {}
	var physics_ticks := 0
	var draw_us := {}         # categoria → µs acumulados no quadro
	var draw_n := {}          # categoria → quantos _draw no quadro
	var draw_us_total := {}   # acumulados na janela medida
	var draw_n_total := {}
	var upd_us_total := {}    # classe do visual → µs de update_visual
	var upd_n_total := {}
	var _last_draw_t := 0
	var _last_draw_cat := ""
	var _vp_rid: RID
	var processing_nodes := 0          # nós com _process ligado (UnitView contado como no jogo)
	var physics_processing_nodes := 0
	var processing_by_class := {}

	func setup(p_bench) -> void:
		bench = p_bench
		cfg = bench.cfg
		name = "BenchDriver"
		process_priority = 1_000_000   # por último: os redesenhos pedidos antes já estão na fila
		warm_frames = int(cfg.warmup * 60.0)
		target_frames = int(cfg.seconds * 60.0)

	func _ready() -> void:
		var b: Battle = bench.battle
		views = b._views.values()
		var visual_mode: String = cfg.visual
		for v: UnitView in views:
			v.set_process(false)   # o driver chama o UnitView._process do jogo, cronometrado
			match visual_mode:
				"nodraw":
					v.visual.visible = false
				"minimal":
					v.visual.visible = false
					v._overlay.visible = false
					var m := Marker.new()
					m.color = Color(0.4, 0.8, 1.0) if v.unit.team == CombatUnit.Team.PLAYER else Color(1.0, 0.45, 0.4)
					v.add_child(m)
		if visual_mode in ["minimal", "hidden"]:
			b._effects.visible = false
		if visual_mode == "hidden":
			b._entities.visible = false
		_count_processing(get_tree().root)
		if cfg.probes == 1:
			_hook_tree(get_tree().root)
			get_tree().node_added.connect(_hook_node)
		get_tree().physics_frame.connect(func() -> void: physics_ticks += 1)
		_vp_rid = get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(_vp_rid, true)

	func _count_processing(n: Node) -> void:
		if n != self and (n.is_processing() or n is UnitView):
			processing_nodes += 1
			var s: Script = n.get_script()
			var k := String(s.get_global_name()) if s and s.get_global_name() != &"" else n.get_class()
			processing_by_class[k] = processing_by_class.get(k, 0) + 1
		if n.is_physics_processing():
			physics_processing_nodes += 1
		for c in n.get_children():
			_count_processing(c)

	func _hook_tree(n: Node) -> void:
		_hook_node(n)
		for c in n.get_children():
			_hook_tree(c)

	func _hook_node(n: Node) -> void:
		if n is CanvasItem and not n.draw.is_connected(_on_draw):
			n.draw.connect(_on_draw.bind(_category(n)))

	static func _category(n: Node) -> String:
		var s: Script = n.get_script()
		var cls := s.get_global_name() if s else StringName()
		if n is Control:
			return "UI"
		if n.name == &"Overlay" and n.get_parent() is UnitView:
			return "UnitView.Overlay(HP)"
		if n is UnitView:
			return "UnitView(anel/debug)"
		if n is UnitVisual:
			return "Visual:" + String(cls)
		if n is ProjectileView:
			return "ProjectileView"
		var p := n
		while p:
			if p is ArenaBackdrop:
				return "Backdrop"
			p = p.get_parent()
		if cls != &"":
			return String(cls)
		return n.get_class()

	func _on_draw(cat: String) -> void:
		var now := Time.get_ticks_usec()
		if _last_draw_cat != "":
			draw_us[_last_draw_cat] = draw_us.get(_last_draw_cat, 0) + now - _last_draw_t
		_last_draw_cat = cat
		_last_draw_t = now
		draw_n[cat] = draw_n.get(cat, 0) + 1

	func _end_draw_mark() -> void:
		if _last_draw_cat != "":
			draw_us[_last_draw_cat] = draw_us.get(_last_draw_cat, 0) + Time.get_ticks_usec() - _last_draw_t
		_last_draw_cat = ""

	func _sim_counters() -> Dictionary:
		var s = bench.battle.sim
		return s.counters() if s is BenchCombatSim else {}

	func _process(delta: float) -> void:
		var now := Time.get_ticks_usec()
		var frame_us := now - last_t if last_t > 0 else 0
		last_t = now
		# quadro anterior: redesenhos e monitores do motor (só ficam prontos depois do quadro)
		var prev_draw := draw_us.duplicate()
		var prev_draw_n := draw_n.duplicate()
		draw_us.clear()
		draw_n.clear()

		# --- o próprio UnitView._process (código do jogo), cronometrado por classe de visual ---
		var upd := {}
		var t_views := Time.get_ticks_usec()
		if cfg.visual in ["normal", "nodraw"]:
			for v: UnitView in views:
				var t0 := Time.get_ticks_usec()
				v._process(delta)
				var cls := String(v.visual.get_script().get_global_name())
				upd[cls] = upd.get(cls, 0) + Time.get_ticks_usec() - t0
		elif cfg.visual == "minimal":
			for v: UnitView in views:
				v.position = v.unit.position
		var views_us := Time.get_ticks_usec() - t_views
		if cfg.probes == 1:
			call_deferred("_end_draw_mark")

		frames += 1
		var c := _sim_counters()
		if frames == warm_frames:
			wall_start = now
			start_counters = c
			game_t0 = bench.battle.sim.time
			prev_counters = c
			physics_ticks = 0
			return
		if frames < warm_frames:
			return
		measured += 1
		var row := {
			frame = measured, frame_ms = frame_us / 1000.0,
			process_max_1s_ms = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,   # monitor do Godot: PICO do último segundo
			physics_max_1s_ms = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			render_cpu_ms = RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid) + RenderingServer.get_frame_setup_time_cpu(),
			render_gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid),
			draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			render_objects = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			primitives = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			objects = Performance.get_monitor(Performance.OBJECT_COUNT),
			view_update_ms = views_us / 1000.0,
			alive_p = bench.battle.sim.alive_count(CombatUnit.Team.PLAYER),
			alive_e = bench.battle.sim.alive_count(CombatUnit.Team.ENEMY),
			projectiles = bench.battle.sim.projectiles.size(),
		}
		var draw_total := 0
		var draw_units := 0
		var draw_n_units := 0
		for k in prev_draw:
			draw_total += prev_draw[k]
			draw_us_total[k] = draw_us_total.get(k, 0) + prev_draw[k]
			if k.begins_with("Visual:") or k.begins_with("UnitView"):
				draw_units += prev_draw[k]
		for k in prev_draw_n:
			draw_n_total[k] = draw_n_total.get(k, 0) + prev_draw_n[k]
			if k.begins_with("Visual:") or k.begins_with("UnitView"):
				draw_n_units += prev_draw_n[k]
		row.draw_ms_total = draw_total / 1000.0
		row.draw_ms_units = draw_units / 1000.0
		row.redraws = prev_draw_n.values().reduce(func(a, b): return a + b, 0)
		row.redraws_units = draw_n_units
		for k in upd:
			upd_us_total[k] = upd_us_total.get(k, 0) + upd[k]
			upd_n_total[k] = upd_n_total.get(k, 0) + 1
		for k in c:
			row[k] = c[k] - prev_counters.get(k, 0)
		prev_counters = c
		row.sim_ms = row.get("us_step", 0) / 1000.0
		rows.append(row)
		if measured >= target_frames:
			_finish(now)

	func _finish(now: int) -> void:
		var wall_s := (now - wall_start) / 1_000_000.0
		var game_s: float = bench.battle.sim.time - game_t0
		if game_s <= 0.0:
			game_s = measured / 60.0   # fase parada: a simulação não anda; 60 quadros = 1 s
		var ft := rows.map(func(r): return r.frame_ms)
		ft.sort()
		var n := ft.size()
		var s := {
			label = cfg.label, profile = cfg.profile, allies = cfg.allies, enemies = cfg.enemies,
			phase = cfg.phase, visual = cfg.visual, sim = cfg.sim, timing = cfg.timing, probes = cfg.probes,
			realtime = cfg.realtime, headless = DisplayServer.get_name() == "headless",
			frames = n, wall_s = wall_s, game_s = game_s,
			fps_avg = n / wall_s, fps_min = 1000.0 / ft[n - 1],
			frame_ms_avg = _mean(rows, "frame_ms"), frame_ms_p50 = ft[int(n / 2.0)], frame_ms_p95 = ft[int(n * 0.95)],
			frame_ms_p99 = ft[int(n * 0.99)], frame_ms_max = ft[n - 1],
			physics_ticks_per_s = physics_ticks / wall_s,
		}
		for k in ["process_max_1s_ms", "physics_max_1s_ms", "render_cpu_ms", "render_gpu_ms", "draw_calls", "render_objects",
				"primitives", "nodes", "objects", "view_update_ms", "draw_ms_total", "draw_ms_units", "redraws",
				"redraws_units", "alive_p", "alive_e", "projectiles", "sim_ms"]:
			s[k] = _mean(rows, k)
		s.sim_steps_per_frame = _mean(rows, "steps")
		for k in ["us_paladins", "us_target", "us_attack", "us_projectiles"]:
			s[k.replace("us_", "ms_")] = _mean(rows, k) / 1000.0   # ms por quadro
		for k in start_counters:
			if not k.begins_with("us_"):
				s[k + "_per_s"] = (prev_counters[k] - start_counters[k]) / game_s
		var dcat := {}
		for k in draw_us_total:
			dcat[k] = {ms_per_frame = draw_us_total[k] / 1000.0 / n, draws_per_frame = draw_n_total.get(k, 0) / float(n)}
		s.draw_by_category = dcat
		var ucat := {}
		for k in upd_us_total:
			ucat[k] = {ms_per_frame = upd_us_total[k] / 1000.0 / n}
		s.update_by_class = ucat
		s.views = views.size()
		s.processing_nodes = processing_nodes
		s.physics_processing_nodes = physics_processing_nodes
		s.processing_by_class = processing_by_class
		var f := FileAccess.open(cfg.out.path_join("frames_%s.csv" % cfg.label), FileAccess.WRITE)
		var keys: Array = rows[0].keys()
		f.store_line(",".join(keys))
		for r in rows:
			f.store_line(",".join(keys.map(func(k): return str(r.get(k, "")))))
		f.close()
		bench.finish(s)

	static func _mean(list: Array, k: String) -> float:
		if list.is_empty():
			return 0.0
		var t := 0.0
		for r in list:
			t += float(r.get(k, 0.0))
		return t / list.size()


## Marcador do modo `minimal`: um círculo desenhado uma vez (não é redesenhado a cada quadro).
class Marker extends Node2D:
	var color := Color.WHITE
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 5.0, color)
