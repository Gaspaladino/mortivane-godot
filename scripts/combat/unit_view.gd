class_name UnitView
extends Node2D
## Apresentação de uma CombatUnit. Só lê o estado da unidade; nunca altera a simulação.
##
## Camadas (de trás para frente):
##   este nó (_draw)   — anel de seleção e, com F4, alcance e linha até o alvo (no chão)
##   Body (UnitVisual) — o corpo: a cena de UnitDef.visual_scene, ou o script de visual_script, ou o círculo padrão
##   Overlay           — barra de HP e, com F4, o texto de debug (sempre por cima do corpo)
##
## Eventos visuais repassados pela Battle: on_hit(), on_attack_performed() e on_projectile_fired().

const COLOR_SELECTED := Color(1.0, 0.92, 0.55)
const COLOR_HP_BACK := Color(0.05, 0.03, 0.06, 0.85)
const COLOR_HP_FULL := Color(0.49, 0.88, 0.54)
const COLOR_HP_LOW := Color(0.9, 0.3, 0.25)
const COLOR_RANGE := Color(1.0, 0.85, 0.4, 0.8)
const COLOR_TARGET := Color(1.0, 0.45, 0.35, 0.9)

const HP_BAR_SIZE := Vector2(30, 4)
const FONT_SIZE := 9
const DEBUG_TEXT_WIDTH := 170.0
const DEBUG_TEXT_INSET := 6.0

var unit: CombatUnit
var visual: UnitVisual
var debug_visible := false:
	set(value):
		debug_visible = value
		_frozen = false   # o debug de um morto também é redesenhado; volta a congelar depois
		queue_redraw()
		if _overlay:
			_overlay.queue_redraw()
## Destaque de seleção (Sandbox).
var selected := false:
	set(value):
		selected = value
		queue_redraw()

var _overlay: Node2D
var _font: Font
## Cadáver assentado: não atualiza nem redesenha mais (a última pose desenhada fica no RenderingServer).
## Só sai daqui se a unidade voltar a viver (Necromancia) ou se o debug for ligado.
var _frozen := false
## Painel de desempenho (F6): enquanto ligado, soma o tempo de _process de todos os UnitView (µs);
## o painel lê e zera. Desligado, não mede nada.
static var profiling := false
static var stat_usec := 0
## Etapa 3: o anel de seleção e a barra de HP só são redesenhados quando o que mostram muda
## (antes: os dois, todo quadro, para todas as unidades). Com o debug ligado, todo quadro.
var _hp_drawn := -1.0
var _alive_drawn := true
var _top_drawn := 0.0


func _init(p_unit: CombatUnit, def: UnitDef) -> void:
	unit = p_unit
	name = "Unit%d" % unit.id
	if def.visual_scene:
		visual = def.visual_scene.instantiate() as UnitVisual
	if visual == null:
		var script: Script = def.visual_script if def.visual_script else CircleUnitVisual
		visual = script.new()
	visual.name = "Body"
	visual.setup(unit, def)
	add_child(visual)
	_overlay = Node2D.new()
	_overlay.name = "Overlay"
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


func _ready() -> void:
	_font = ThemeDB.fallback_font
	position = unit.position


func on_hit() -> void:
	visual.on_hit()


func on_attack_performed() -> void:
	visual.on_attack_performed()


func on_projectile_fired(p: CombatProjectile) -> void:
	visual.on_projectile_fired(p)


func on_ability_event(kind: StringName) -> void:
	visual.on_ability_event(kind)


## O ponto (coordenadas do mundo) está sobre o corpo desta unidade?
func contains_point(world_point: Vector2) -> bool:
	return visual.pick_rect().has_point(world_point - position)


func _process(delta: float) -> void:
	if profiling:
		var t0 := Time.get_ticks_usec()
		_update(delta)
		stat_usec += Time.get_ticks_usec() - t0
	else:
		_update(delta)


func _update(delta: float) -> void:
	if _frozen:
		if not unit.is_alive():
			if position != unit.position:
				position = unit.position   # só a transformação do nó; o desenho não muda
			return
		_frozen = false   # voltou a viver: anima de novo
	position = unit.position
	visual.update_visual(delta)
	if debug_visible:
		queue_redraw()   # alcance e linha até o alvo mudam todo quadro
		_overlay.queue_redraw()
	else:
		var alive := unit.is_alive()
		var top := visual.top_y()
		if unit.hp != _hp_drawn or alive != _alive_drawn or top != _top_drawn:
			_hp_drawn = unit.hp
			_alive_drawn = alive
			_top_drawn = top
			_overlay.queue_redraw()
	if not unit.is_alive() and not debug_visible and visual.is_settled_corpse():
		_frozen = true   # este quadro já pediu o último redesenho da pose final


## Cadáver congelado (sem atualização nem redesenho por quadro)?
func is_frozen() -> bool:
	return _frozen


func _draw() -> void:
	if selected:
		var ground := visual.ground_point()
		draw_set_transform(ground, 0.0, Vector2(1.0, 0.42))
		draw_arc(Vector2.ZERO, unit.radius + 5.0, 0.0, TAU, 40, COLOR_SELECTED, 2.5, true)
		draw_set_transform(Vector2.ZERO)
	if debug_visible:
		_draw_debug_under()


func _draw_overlay() -> void:
	if unit.is_alive():
		_draw_hp_bar()
	if debug_visible:
		_draw_debug_text()


func _draw_hp_bar() -> void:
	var ratio := clampf(unit.hp / unit.max_hp, 0.0, 1.0)
	var top_left := Vector2(-HP_BAR_SIZE.x / 2.0, visual.top_y() - HP_BAR_SIZE.y - 2.0)
	_overlay.draw_rect(Rect2(top_left - Vector2.ONE, HP_BAR_SIZE + Vector2(2, 2)), COLOR_HP_BACK, true)
	_overlay.draw_rect(Rect2(top_left, Vector2(HP_BAR_SIZE.x * ratio, HP_BAR_SIZE.y)), COLOR_HP_LOW.lerp(COLOR_HP_FULL, ratio), true)


func _draw_debug_under() -> void:
	if not unit.is_alive():
		var s := 5.0
		draw_line(Vector2(-s, -s), Vector2(s, s), COLOR_TARGET, 1.5)
		draw_line(Vector2(-s, s), Vector2(s, -s), COLOR_TARGET, 1.5)
		return
	draw_arc(Vector2.ZERO, unit.attack_range, 0.0, TAU, 48, COLOR_RANGE, 1.0, true)
	if unit.target != null:
		var to_target := unit.target.position - unit.position
		draw_dashed_line(Vector2.ZERO, to_target, COLOR_TARGET, 1.0, 4.0)
		draw_circle(to_target, 2.5, COLOR_TARGET)


func _draw_debug_text() -> void:
	var target_text := unit.target.label() if unit.target != null else "—"
	var lines := PackedStringArray([
		"%s · %s" % [unit.label(), CombatUnit.state_name(unit.state)],
		"HP %d/%d · alcance %d" % [ceili(unit.hp), unit.max_hp, unit.attack_range],
		"alvo: %s" % target_text,
	])
	# aliado escreve para a esquerda, inimigo para a direita: no corpo a corpo os textos não se sobrepõem
	var is_player := unit.team == CombatUnit.Team.PLAYER
	var align := HORIZONTAL_ALIGNMENT_RIGHT if is_player else HORIZONTAL_ALIGNMENT_LEFT
	var x := -DEBUG_TEXT_WIDTH + DEBUG_TEXT_INSET if is_player else -DEBUG_TEXT_INSET
	var y := maxf(unit.radius, visual.ground_point().y) + 14.0
	for line in lines:
		var pos := Vector2(x, y)
		_overlay.draw_string_outline(_font, pos, line, align, DEBUG_TEXT_WIDTH, FONT_SIZE, 3, Color(0, 0, 0, 0.85))
		_overlay.draw_string(_font, pos, line, align, DEBUG_TEXT_WIDTH, FONT_SIZE, Color(1, 0.95, 0.85))
		y += FONT_SIZE + 2
