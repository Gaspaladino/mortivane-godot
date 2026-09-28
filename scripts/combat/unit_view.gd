class_name UnitView
extends Node2D
## Visual TEMPORÁRIO de uma CombatUnit: círculo nas cores da UnitDef + barra de HP.
## Só lê o estado da unidade; nunca altera a simulação.
##
## Debug de combate (F4): alcance, linha até o alvo atual, HP e estado.

const COLOR_SELECTED := Color(1.0, 0.92, 0.55)
const COLOR_HP_BACK := Color(0.05, 0.03, 0.06, 0.85)
const COLOR_HP_FULL := Color(0.49, 0.88, 0.54)
const COLOR_HP_LOW := Color(0.9, 0.3, 0.25)
const COLOR_RANGE := Color(1.0, 0.85, 0.4, 0.8)
const COLOR_TARGET := Color(1.0, 0.45, 0.35, 0.9)

const HP_BAR_SIZE := Vector2(30, 4)
const HIT_FLASH_SECONDS := 0.12
const DEATH_FADE_SECONDS := 0.5
const FONT_SIZE := 9
const DEBUG_TEXT_WIDTH := 170.0
const DEBUG_TEXT_INSET := 6.0

var unit: CombatUnit
var debug_visible := false:
	set(value):
		debug_visible = value
		queue_redraw()
## Destaque de seleção (Sandbox).
var selected := false:
	set(value):
		selected = value
		queue_redraw()

var _body_color: Color
var _trim_color: Color

var _flash := 0.0
var _body_alpha := 1.0
var _font: Font


func _init(p_unit: CombatUnit, def: UnitDef) -> void:
	unit = p_unit
	_body_color = def.body_color
	_trim_color = def.trim_color
	name = "Unit%d" % unit.id


func _ready() -> void:
	_font = ThemeDB.fallback_font
	position = unit.position


func flash_hit() -> void:
	_flash = HIT_FLASH_SECONDS


func _process(delta: float) -> void:
	position = unit.position
	_flash = maxf(0.0, _flash - delta)
	if not unit.is_alive():
		_body_alpha = maxf(0.0, _body_alpha - delta / DEATH_FADE_SECONDS)
	queue_redraw()


func _draw() -> void:
	if selected:
		draw_arc(Vector2.ZERO, unit.radius + 5.0, 0.0, TAU, 40, COLOR_SELECTED, 2.0, true)
	if debug_visible:
		_draw_debug_under()
	if _body_alpha > 0.0:
		_draw_body()
		if unit.is_alive():
			_draw_hp_bar()
	if debug_visible:
		_draw_debug_text()


func _draw_body() -> void:
	var is_player := unit.team == CombatUnit.Team.PLAYER
	var body := _body_color
	var trim := _trim_color
	if _flash > 0.0:
		body = body.lerp(Color.WHITE, 0.7)
	body.a *= _body_alpha
	trim.a *= _body_alpha
	var r := unit.radius
	draw_circle(Vector2(0, r * 0.35), r * 0.9, Color(0, 0, 0, 0.3 * _body_alpha))  # sombra
	draw_circle(Vector2.ZERO, r, body)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, trim, 1.5, true)
	# marca de direção: aponta para o alvo, ou para o lado inimigo
	var facing := Vector2.RIGHT if is_player else Vector2.LEFT
	if unit.target != null:
		facing = (unit.target.position - unit.position).normalized()
	draw_line(facing * r * 0.3, facing * r * 1.25, trim, 2.0, true)


func _draw_hp_bar() -> void:
	var ratio := clampf(unit.hp / unit.max_hp, 0.0, 1.0)
	var top_left := Vector2(-HP_BAR_SIZE.x / 2.0, -unit.radius - 9.0)
	draw_rect(Rect2(top_left - Vector2.ONE, HP_BAR_SIZE + Vector2(2, 2)), COLOR_HP_BACK, true)
	draw_rect(Rect2(top_left, Vector2(HP_BAR_SIZE.x * ratio, HP_BAR_SIZE.y)), COLOR_HP_LOW.lerp(COLOR_HP_FULL, ratio), true)


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
	var y := unit.radius + 14.0
	for line in lines:
		var pos := Vector2(x, y)
		draw_string_outline(_font, pos, line, align, DEBUG_TEXT_WIDTH, FONT_SIZE, 3, Color(0, 0, 0, 0.85))
		draw_string(_font, pos, line, align, DEBUG_TEXT_WIDTH, FONT_SIZE, Color(1, 0.95, 0.85))
		y += FONT_SIZE + 2
