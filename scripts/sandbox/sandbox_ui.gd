class_name SandboxUI
extends CanvasLayer
## Interface técnica do Sandbox. Só exibe e emite sinais; não conhece Battle nem CombatSim.
## O SandboxController liga os sinais às ações.
##
## Layout (fica no céu da arte, acima de y=210, para não cobrir o campo):
##   ALIADOS (topo esquerdo) · controles + estado + unidade selecionada (topo centro) · INIMIGOS (topo direito)
## As listas vêm do UnitCatalog: nova UnitDef = novo botão, sem mudar este script.

signal spawn_requested(def: UnitDef, team: CombatUnit.Team)
signal start_pressed
signal reset_pressed
signal clear_pressed
signal menu_pressed
signal stat_edited(key: String, value: float)

const FONT_SIZE := 10
const TITLE_FONT_SIZE := 11
const SIDE_PANEL_WIDTH := 180.0
const CENTER_PANEL_WIDTH := 580.0
const MARGIN := 6.0
const COLOR_ALLY := Color(0.75, 0.88, 0.7)
const COLOR_ENEMY := Color(0.95, 0.66, 0.55)
const COLOR_TEXT := Color(0.92, 0.89, 0.97)
const COLOR_DIM := Color(0.7, 0.66, 0.78)

## [chave de UnitDef.to_stats, rótulo, mínimo, máximo, passo]
const EDIT_FIELDS := [
	["hp", "HP máx.", 1.0, 9999.0, 1.0],
	["dmg", "Dano", 0.0, 999.0, 1.0],
	["range", "Alcance", 1.0, 600.0, 1.0],
	["cd", "Intervalo", 0.05, 10.0, 0.05],
	["speed", "Velocidade", 0.0, 400.0, 1.0],
]

var start_button: Button
var reset_button: Button
var clear_button: Button
var menu_button: Button
var status_label: Label
var selected_title: Label
var selected_info: Label

var _ally_header: Label
var _enemy_header: Label
var _ally_list: VBoxContainer
var _enemy_list: VBoxContainer
var _spawn_buttons: Array[Button] = []
var _spins := {}   # chave → SpinBox
var _edit_row: HFlowContainer
var _shown_unit: CombatUnit


func _ready() -> void:
	layer = 50
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE   # cliques fora dos painéis vão para a arena
	root.theme = _make_theme()
	add_child(root)

	var allies := _side_panel("ALIADOS", COLOR_ALLY, "esquerdo")
	_ally_header = allies[1]
	_ally_list = allies[2]
	allies[0].set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	allies[0].position = Vector2(MARGIN, MARGIN)
	root.add_child(allies[0])

	var enemies := _side_panel("INIMIGOS", COLOR_ENEMY, "direito")
	_enemy_header = enemies[1]
	_enemy_list = enemies[2]
	enemies[0].set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	enemies[0].grow_horizontal = Control.GROW_DIRECTION_BEGIN
	enemies[0].offset_left = -SIDE_PANEL_WIDTH - MARGIN
	enemies[0].offset_right = -MARGIN
	enemies[0].offset_top = MARGIN
	root.add_child(enemies[0])

	root.add_child(_center_panel())


# --- API usada pelo SandboxController ---------------------------------------------------

func set_catalog(ally_defs: Array[UnitDef], enemy_defs: Array[UnitDef]) -> void:
	_fill_list(_ally_list, ally_defs, CombatUnit.Team.PLAYER)
	_fill_list(_enemy_list, enemy_defs, CombatUnit.Team.ENEMY)


func set_counts(allies: int, enemies: int) -> void:
	_ally_header.text = "ALIADOS · %d" % allies
	_enemy_header.text = "INIMIGOS · %d" % enemies


func set_controls(can_spawn: bool, can_start: bool, has_units: bool) -> void:
	for button in _spawn_buttons:
		button.disabled = not can_spawn
	start_button.disabled = not can_start
	reset_button.disabled = not has_units
	clear_button.disabled = not has_units


func set_status(text: String) -> void:
	status_label.text = text


## Mostra (ou esconde, com unit = null) a unidade selecionada. Chamado a cada quadro.
func show_unit(unit: CombatUnit, def: UnitDef, editable: bool) -> void:
	if unit == null:
		_shown_unit = null
		selected_title.text = "Nenhuma tropa selecionada — clique numa unidade na arena"
		selected_title.add_theme_color_override("font_color", COLOR_DIM)
		selected_info.visible = false
		_edit_row.visible = false
		return
	var is_player := unit.team == CombatUnit.Team.PLAYER
	selected_title.text = "%s  ·  %s  ·  %s" % [unit.label(), "Aliado" if is_player else "Inimigo", CombatUnit.state_name(unit.state)]
	selected_title.add_theme_color_override("font_color", COLOR_ALLY if is_player else COLOR_ENEMY)
	selected_info.visible = true
	selected_info.text = "HP %d/%d  ·  Dano %s  ·  Alcance %s  ·  Intervalo %s s  ·  Velocidade %s  ·  Alvo: %s" % [
		ceili(unit.hp), roundi(unit.max_hp), _num(unit.damage), _num(unit.attack_range),
		_num(unit.attack_interval), _num(unit.move_speed),
		unit.target.label() if unit.target else "—"]
	_edit_row.visible = true
	if unit != _shown_unit:   # não sobrescreve o que o usuário está digitando
		_shown_unit = unit
		var values := {hp = unit.max_hp, dmg = unit.damage, range = unit.attack_range, cd = unit.attack_interval, speed = unit.move_speed}
		for key in _spins:
			_spins[key].set_value_no_signal(values[key])
	for spin in _spins.values():
		spin.editable = editable
	_edit_row.tooltip_text = "" if editable else "Edição só na preparação (Reiniciar volta para ela)."


# --- Construção -------------------------------------------------------------------------

func _center_panel() -> Control:
	var panel := _panel()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_left = -CENTER_PANEL_WIDTH / 2.0
	panel.offset_right = CENTER_PANEL_WIDTH / 2.0
	panel.offset_top = MARGIN
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	start_button = _button("Iniciar combate", start_pressed.emit)
	reset_button = _button("Reiniciar combate", reset_pressed.emit)
	clear_button = _button("Limpar arena", clear_pressed.emit)
	menu_button = _button("Voltar ao menu", menu_pressed.emit)
	reset_button.tooltip_text = "Restaura a montagem ao estado inicial (atalho: F9)."
	for b in [start_button, reset_button, clear_button, menu_button]:
		buttons.add_child(b)
	box.add_child(buttons)

	status_label = _label("", COLOR_TEXT)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status_label)

	box.add_child(HSeparator.new())
	selected_title = _label("", COLOR_DIM, TITLE_FONT_SIZE)
	box.add_child(selected_title)
	selected_info = _label("", COLOR_TEXT)
	selected_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(selected_info)

	_edit_row = HFlowContainer.new()
	for field in EDIT_FIELDS:
		var key: String = field[0]
		_edit_row.add_child(_label(field[1], COLOR_DIM))
		var spin := SpinBox.new()
		spin.min_value = field[2]
		spin.max_value = field[3]
		spin.step = field[4]
		spin.custom_minimum_size.x = 62
		spin.select_all_on_focus = true
		spin.value_changed.connect(func(v: float) -> void: stat_edited.emit(key, v))
		_spins[key] = spin
		_edit_row.add_child(spin)
	box.add_child(_edit_row)

	show_unit(null, null, false)
	return panel


## Devolve [painel, cabeçalho, lista].
func _side_panel(title: String, color: Color, side_text: String) -> Array:
	var panel := _panel()
	panel.custom_minimum_size.x = SIDE_PANEL_WIDTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	var header := _label(title, color, TITLE_FONT_SIZE)
	box.add_child(header)
	box.add_child(_label("Clique para criar do lado %s" % side_text, COLOR_DIM))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	box.add_child(list)
	return [panel, header, list]


func _fill_list(list: VBoxContainer, defs: Array[UnitDef], team: CombatUnit.Team) -> void:
	for child in list.get_children():
		_spawn_buttons.erase(child)
		child.queue_free()
	if defs.is_empty():
		list.add_child(_label("(nenhuma unidade)", COLOR_DIM))
	for def in defs:
		var button := _button("+ %s" % def.display_name, func() -> void: spawn_requested.emit(def, team))
		button.name = "Spawn_%s" % def.id
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.tooltip_text = "HP %s · Dano %s · Alcance %s · Intervalo %s s · Velocidade %s" % [
			_num(def.max_hp), _num(def.damage), _num(def.attack_range), _num(def.attack_interval), _num(def.move_speed)]
		list.add_child(button)
		_spawn_buttons.append(button)


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.09, 0.82)
	style.border_color = Color(0.47, 0.34, 0.66, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE   # teclas (F3/F4/F9…) nunca "apertam" botões
	button.pressed.connect(on_pressed)
	return button


func _label(text: String, color: Color, size := FONT_SIZE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	return label


func _make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = FONT_SIZE
	return theme


## 10.0 → "10", 0.95 → "0.95".
static func _num(value: float) -> String:
	var text := "%.2f" % value
	return text.rstrip("0").trim_suffix(".")
