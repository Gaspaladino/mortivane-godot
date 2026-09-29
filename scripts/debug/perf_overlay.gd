class_name PerfOverlay
extends CanvasLayer
## Painel de desempenho do Sandbox (ferramenta de DEBUG; F6 liga/desliga — ver Main).
##
## Só LÊ: monitores oficiais do Godot (FPS, draw calls, objetos, nós), a simulação da Battle
## (vivos, cadáveres, contadores de busca de alvo) e dois cronômetros baratos (tempo da simulação
## por quadro, medido pela Battle; tempo de update dos visuais, medido pelos UnitView só enquanto o
## painel está ligado). Não muda nada do combate nem do desenho das unidades.
##
## Atualiza o texto 5×/s. Desligado, não processa (custo zero).

const REFRESH := 0.2
const BG := Color(0.03, 0.03, 0.05, 0.62)

var battle: Battle
## Comparação de render (F7): o painel mostra o modo em uso.
var render_compare: RenderCompare
var _label: Label
var _acc := 0.0
var _frames := 0
var _worst := 0.0
var _sim_us := 0
var _view_us := 0
var _steps := 0
var _queries0 := 0
var _scans0 := 0
var _cand0 := 0
var _sim_ref: CombatSim = null


func _init() -> void:
	name = "PerfOverlay"
	layer = 60   # acima da UI do Sandbox (50), abaixo dos avisos (110)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE   # não bloqueia cliques
	panel.position = Vector2(8, 8)
	var style := StyleBoxFlat.new()
	style.bg_color = BG
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_constant_override("line_spacing", -2)
	_label.add_theme_color_override("font_color", Color(0.93, 0.95, 0.88))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 2)
	_label.text = "PERF (F6)"
	panel.add_child(_label)
	add_child(panel)
	visible = false
	set_process(false)


func set_shown(value: bool) -> void:
	visible = value
	set_process(value)
	UnitView.profiling = value
	if value:
		_reset_window()
		_refresh()


func is_shown() -> bool:
	return visible


func _exit_tree() -> void:
	UnitView.profiling = false


func _process(delta: float) -> void:
	_acc += delta
	_frames += 1
	_worst = maxf(_worst, delta)
	if battle:
		_sim_us += battle.sim_usec_last_frame
		_steps += battle.steps_last_frame
	_view_us += UnitView.stat_usec
	UnitView.stat_usec = 0
	if _acc >= REFRESH:
		_refresh()
		_reset_window()


func _reset_window() -> void:
	_acc = 0.0
	_frames = 0
	_worst = 0.0
	_sim_us = 0
	_view_us = 0
	_steps = 0
	UnitView.stat_usec = 0
	var sim := battle.sim if battle else null
	_sim_ref = sim
	if sim:
		_queries0 = sim.stat_target_queries
		_scans0 = sim.stat_target_scans
		_cand0 = sim.stat_candidates


func _refresh() -> void:
	var lines := PackedStringArray()
	# FPS e quadro da mesma janela de 0,2 s (o monitor TIME_FPS do Godot é a média do último segundo
	# e fica atrasado em relação ao quadro); sem janela ainda (logo ao ligar), usa o monitor.
	var n := maxi(_frames, 1)
	var fps := _frames / _acc if _frames > 0 and _acc > 0.0 else Performance.get_monitor(Performance.TIME_FPS)
	var frame_ms := (_acc / n) * 1000.0 if _frames > 0 else (1000.0 / fps if fps > 0.0 else 0.0)
	lines.append("PERF (F6)")
	lines.append("FPS: %d   Quadro: %.1f ms (pior %.1f)" % [roundi(fps), frame_ms, _worst * 1000.0])
	var sim := battle.sim if battle else null
	if sim:
		var allies := sim.alive_count(CombatUnit.Team.PLAYER)
		var enemies := sim.alive_count(CombatUnit.Team.ENEMY)
		var total := sim.units.size()
		lines.append("Aliados: %d   Inimigos: %d" % [allies, enemies])
		lines.append("Vivos: %d   Cadáveres: %d   Total: %d" % [allies + enemies, total - allies - enemies, total])
		lines.append("Projéteis: %d" % sim.projectiles.size())
	lines.append("Draw calls: %s   Objetos: %s   Nós: %s" % [_render_stat(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), _render_stat(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), _fmt(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	if battle and battle.is_running():
		lines.append("Sim: %.2f ms/quadro  (%.1f passos)" % [_sim_us / 1000.0 / n, float(_steps) / n])
	else:
		lines.append("Sim: parada")
	if sim and sim == _sim_ref and _acc > 0.0:
		var q := (sim.stat_target_queries - _queries0) / _acc
		var sc := (sim.stat_target_scans - _scans0) / _acc
		var c := (sim.stat_candidates - _cand0) / _acc
		lines.append("Alvo/s: %s buscas · %s varreduras · %s candidatos" % [_fmt(q), _fmt(sc), _fmt(c)])
	lines.append("Visual (update): %.2f ms/quadro" % (_view_us / 1000.0 / n))
	if render_compare:
		lines.append("Visual (F7): %s" % render_compare.mode_name())
	_label.text = "\n".join(lines)


## Monitores de render: N/A quando não há render de verdade (headless / servidor nulo).
static func _render_stat(monitor: Performance.Monitor) -> String:
	if DisplayServer.get_name() == "headless":
		return "N/A"
	return _fmt(Performance.get_monitor(monitor))


static func _fmt(v: float) -> String:
	var i := roundi(v)
	if absi(i) < 1000:
		return str(i)
	var s := str(absi(i))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if i < 0 else "") + s + out
