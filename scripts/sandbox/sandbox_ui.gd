class_name SandboxUI
extends CanvasLayer
## Interface do Sandbox (cena scenes/sandbox/sandbox_ui.tscn). Só exibe e emite sinais; não
## conhece Battle nem CombatSim. O SandboxController liga os sinais às ações.
##
## A estrutura é toda editável no editor: uma faixa inferior (BottomBar, ~22% da altura) com
## ALIADOS · CONTROLES · UNIDADE SELECIONADA · INIMIGOS. Painéis, botões, textos, fontes e
## margens são nós Control na cena; o tema fica em sandbox_theme.tres.
##
## Gerado por código só o que depende de dados: os botões das listas (um por UnitDef do
## UnitCatalog). Os campos de edição são os SpinBox de EditRow, identificados pelo metadado
## `stat_key` (hp, dmg, range, cd, speed) — dá para reordenar/remover no editor.

signal spawn_requested(def: UnitDef, team: CombatUnit.Team)
signal start_pressed
signal reset_pressed
signal clear_pressed
signal menu_pressed
signal stat_edited(key: String, value: float)
## A altura ocupada pela faixa inferior mudou (a Arena reenquadra o mundo acima dela).
signal layout_changed

const COLOR_ALLY := Color(0.75, 0.88, 0.7)
const COLOR_ENEMY := Color(0.95, 0.66, 0.55)
const COLOR_DIM := Color(0.7, 0.66, 0.78)

@onready var bottom_bar: PanelContainer = %BottomBar
@onready var start_button: Button = %StartButton
@onready var reset_button: Button = %ResetButton
@onready var clear_button: Button = %ClearButton
@onready var menu_button: Button = %MenuButton
@onready var status_label: Label = %StatusLabel
@onready var selected_title: Label = %SelectedTitle
@onready var selected_info: Label = %SelectedInfo
@onready var _edit_row: HFlowContainer = %EditRow
@onready var _ally_header: Label = %AlliesHeader
@onready var _enemy_header: Label = %EnemiesHeader
@onready var _ally_list: VBoxContainer = %AlliesList
@onready var _enemy_list: VBoxContainer = %EnemiesList

var _spawn_buttons: Array[Button] = []
var _spins := {}   # stat_key → SpinBox
var _shown_unit: CombatUnit


func _ready() -> void:
	start_button.pressed.connect(start_pressed.emit)
	reset_button.pressed.connect(reset_pressed.emit)
	clear_button.pressed.connect(clear_pressed.emit)
	menu_button.pressed.connect(menu_pressed.emit)
	for spin in _edit_row.get_children():
		if spin is SpinBox and spin.has_meta(&"stat_key"):
			var key := String(spin.get_meta(&"stat_key"))
			_spins[key] = spin
			spin.value_changed.connect(func(v: float) -> void: stat_edited.emit(key, v))
	bottom_bar.resized.connect(layout_changed.emit)
	show_unit(null, null, false)


## Altura da faixa inferior, em unidades do viewport (o que a Arena deve deixar livre).
func bottom_inset() -> float:
	if not visible or bottom_bar == null or not bottom_bar.visible:
		return 0.0
	return bottom_bar.size.y


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


func _fill_list(list: VBoxContainer, defs: Array[UnitDef], team: CombatUnit.Team) -> void:
	for child in list.get_children():
		_spawn_buttons.erase(child)
		child.queue_free()
	if defs.is_empty():
		var empty := Label.new()
		empty.text = "(nenhuma unidade)"
		list.add_child(empty)
	for def in defs:
		var button := Button.new()
		button.name = "Spawn_%s" % def.id
		button.text = "+ %s" % def.display_name
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE   # teclas (F3/F4/F9…) nunca "apertam" botões
		button.tooltip_text = "HP %s · Dano %s · Alcance %s · Intervalo %s s · Velocidade %s" % [
			_num(def.max_hp), _num(def.damage), _num(def.attack_range), _num(def.attack_interval), _num(def.move_speed)]
		button.pressed.connect(func() -> void: spawn_requested.emit(def, team))
		list.add_child(button)
		_spawn_buttons.append(button)


## 10.0 → "10", 0.95 → "0.95".
static func _num(value: float) -> String:
	var text := "%.2f" % value
	return text.rstrip("0").trim_suffix(".")
