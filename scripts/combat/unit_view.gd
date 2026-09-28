class_name UnitView
extends Node2D
## Apresentação de uma CombatUnit. Só lê o estado da unidade; nunca altera a simulação.
##
## Camadas (de trás para frente):
##   este nó (_draw)   — anel de seleção e, com F4, alcance e linha até o alvo (no chão)
##   Body (UnitVisual) — o corpo: o script de UnitDef.visual_script, ou o círculo padrão
##   Overlay           — barra de HP e, com F4, o texto de debug (sempre por cima do corpo)
##
## Eventos visuais repassados pela Battle: on_hit() e on_attack_landed().

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
		queue_redraw()
## Destaque de seleção (Sandbox).
var selected := false:
	set(value):
		selected = value
		queue_redraw()

var _overlay: Node2D
var _font: Font


func _init(p_unit: CombatUnit, def: UnitDef) -> void:
	unit = p_unit
	name = "Unit%d" % unit.id
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


func on_attack_landed() -> void:
	visual.on_attack_landed()


## O ponto (coordenadas do mundo) está sobre o corpo desta unidade?
func contains_point(world_point: Vector2) -> bool:
	return visual.pick_rect().has_point(world_point - position)


func _process(delta: float) -> void:
	position = unit.position
	visual.update_visual(delta)
	queue_redraw()
	_overlay.queue_redraw()


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
