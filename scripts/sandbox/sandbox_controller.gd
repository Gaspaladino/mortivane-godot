class_name SandboxController
extends Node
## Modo Sandbox: monta lutas na Arena real usando o combate real (Battle → CombatSim).
##
## O Sandbox só coordena:
##   - guarda a MONTAGEM (lista de Placement: qual unidade, que lado, onde, atributos editados);
##   - pede à Battle para criar/limpar/iniciar;
##   - liga a SandboxUI às ações.
## Nenhuma regra de combate mora aqui.
##
## Fluxo: PREPARAÇÃO (monta, edita, nada se move) → Iniciar → COMBATE → FIM.
## Reiniciar recria a montagem e volta à PREPARAÇÃO. Limpar apaga a montagem.

signal exit_requested

enum Mode { PREP, RUNNING, FINISHED }

## Posições automáticas: colunas a partir da divisa, linhas do centro para fora.
const SLOT_ROWS_Y := [380.0, 330.0, 430.0, 280.0, 480.0]
const SLOT_FIRST_OFFSET_X := 100.0   # distância da primeira coluna até x=500
const SLOT_STEP_X := 45.0
const SLOT_COLUMNS := 8
const MAX_PER_SIDE := SLOT_COLUMNS * 5


## Uma unidade da montagem. Sobrevive a Reiniciar; a CombatUnit é recriada a partir dela.
class Placement:
	var def: UnitDef
	var team: CombatUnit.Team
	var position: Vector2
	var overrides := {}
	var unit: CombatUnit   # instância viva na Battle atual

	func _init(p_def: UnitDef, p_team: CombatUnit.Team, p_position: Vector2) -> void:
		def = p_def
		team = p_team
		position = p_position


@onready var arena: Arena = $Arena
@onready var ui: SandboxUI = $SandboxUI

var mode := Mode.PREP
## Painel de desempenho (debug; F6 via Main). Nasce desligado.
var perf_overlay := PerfOverlay.new()
var placements: Array[Placement] = []
var selected: Placement = null


func _ready() -> void:
	perf_overlay.battle = arena.battle
	add_child(perf_overlay)
	arena.battle.finished.connect(_on_battle_finished)
	ui.spawn_requested.connect(add_unit)
	ui.start_pressed.connect(start_combat)
	ui.reset_pressed.connect(reset_combat)
	ui.clear_pressed.connect(clear_arena)
	ui.menu_pressed.connect(func() -> void: exit_requested.emit())
	ui.stat_edited.connect(edit_selected_stat)
	ui.preview_requested.connect(preview_selected)
	ui.set_catalog(UnitCatalog.for_side(CombatUnit.Team.PLAYER), UnitCatalog.for_side(CombatUnit.Team.ENEMY))
	# a faixa inferior da UI não cobre o campo: a Arena reenquadra o mundo acima dela
	ui.layout_changed.connect(_fit_arena_to_ui)
	_fit_arena_to_ui.call_deferred()
	_refresh_ui()


func _fit_arena_to_ui() -> void:
	arena.set_bottom_inset(ui.bottom_inset())


func get_arena() -> Arena:
	return arena


# --- Ações (chamadas pela UI e pelos testes) -------------------------------------------

## Cria uma unidade do lado indicado na próxima posição livre. Só na preparação.
func add_unit(def: UnitDef, team: CombatUnit.Team) -> Placement:
	if mode != Mode.PREP:
		return null
	var index := count_side(team)
	if index >= MAX_PER_SIDE:
		ui.set_status("Limite de %d unidades por lado nesta versão." % MAX_PER_SIDE)
		return null
	var placement := Placement.new(def, team, slot_position(team, index))
	placements.append(placement)
	placement.unit = arena.battle.spawn(def, team, placement.position, placement.overrides)
	_refresh_ui()
	return placement


func start_combat() -> void:
	if mode != Mode.PREP or not can_start():
		return
	mode = Mode.RUNNING
	for placement in placements:   # prévias só visuais não entram no combate
		var view := arena.battle.view_of(placement.unit)
		if view and view.visual.has_method("preview"):
			view.visual.preview(&"", 0)
	arena.battle.start()
	_refresh_ui()


## Recria todas as unidades da montagem no estado inicial (HP cheio, posição original) e para.
func reset_combat() -> void:
	arena.battle.clear()
	for placement in placements:
		placement.unit = arena.battle.spawn(placement.def, placement.team, placement.position, placement.overrides)
	mode = Mode.PREP
	_select(selected)   # a seleção segue a mesma entrada da montagem
	_refresh_ui()


func clear_arena() -> void:
	placements.clear()
	selected = null
	reset_combat()


## Clique no mundo: seleciona a unidade sob o ponto (ou nenhuma).
func select_at(world_point: Vector2) -> void:
	var unit := arena.battle.unit_at(world_point)
	_select(_placement_of(unit))


## Edição por instância; só na preparação. Recria a montagem para valer desde o início.
func edit_selected_stat(key: String, value: float) -> void:
	if mode != Mode.PREP or selected == null or key not in UnitDef.EDITABLE_STATS:
		return
	selected.overrides[key] = value
	reset_combat()


## Prévia só visual na tropa selecionada (ex.: animações do Paladino). Só na preparação: a unidade
## não se move nem luta, e nada da CombatUnit muda. Reiniciar/Limpar recriam o visual (a prévia some).
func preview_selected(kind: StringName, dir: int) -> void:
	if mode != Mode.PREP or selected == null or selected.unit == null:
		return
	var view := arena.battle.view_of(selected.unit)
	if view and view.visual.has_method("preview"):
		view.visual.preview(kind, dir)


func can_start() -> bool:
	return count_side(CombatUnit.Team.PLAYER) > 0 and count_side(CombatUnit.Team.ENEMY) > 0


func count_side(team: CombatUnit.Team) -> int:
	return placements.filter(func(p: Placement) -> bool: return p.team == team).size()


static func slot_position(team: CombatUnit.Team, index: int) -> Vector2:
	var rows := SLOT_ROWS_Y.size()
	var column := index / rows
	var dir := -1.0 if team == CombatUnit.Team.PLAYER else 1.0
	var x := WorldConfig.DEPLOY_X + dir * (SLOT_FIRST_OFFSET_X + column * SLOT_STEP_X)
	return Vector2(x, SLOT_ROWS_Y[index % rows])


# --- Interno ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Cliques em botões/painéis são consumidos pela UI antes de chegar aqui.
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		# posição do próprio evento convertida para o mundo (a Arena está na origem)
		var local := arena.make_input_local(click) as InputEventMouseButton
		select_at(local.position)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if selected:
		ui.show_unit(selected.unit, selected.def, mode == Mode.PREP)
	_refresh_preview_controls()
	if mode == Mode.RUNNING:
		ui.set_status(_status_text())


func _select(placement: Placement) -> void:
	if selected and selected.unit:
		var old_view := arena.battle.view_of(selected.unit)
		if old_view:
			old_view.selected = false
	selected = placement if placement in placements else null
	if selected:
		arena.battle.view_of(selected.unit).selected = true
		ui.show_unit(selected.unit, selected.def, mode == Mode.PREP)
	else:
		ui.show_unit(null, null, false)


func _refresh_preview_controls() -> void:
	var view := arena.battle.view_of(selected.unit) if selected and selected.unit else null
	ui.show_preview_controls(view != null and view.visual.has_method("preview"), mode == Mode.PREP)


func _placement_of(unit: CombatUnit) -> Placement:
	if unit == null:
		return null
	for placement in placements:
		if placement.unit == unit:
			return placement
	return null


func _on_battle_finished(_winner_team: int) -> void:
	mode = Mode.FINISHED
	_refresh_ui()


func _refresh_ui() -> void:
	ui.set_counts(count_side(CombatUnit.Team.PLAYER), count_side(CombatUnit.Team.ENEMY))
	ui.set_controls(mode == Mode.PREP, mode == Mode.PREP and can_start(), not placements.is_empty())
	ui.set_status(_status_text())
	if selected:
		ui.show_unit(selected.unit, selected.def, mode == Mode.PREP)


func _status_text() -> String:
	var allies := count_side(CombatUnit.Team.PLAYER)
	var enemies := count_side(CombatUnit.Team.ENEMY)
	match mode:
		Mode.RUNNING:
			var sim := arena.battle.sim
			return "COMBATE · %.1f s · vivos: %d aliados × %d inimigos" % [
				sim.time, sim.alive_count(CombatUnit.Team.PLAYER), sim.alive_count(CombatUnit.Team.ENEMY)]
		Mode.FINISHED:
			var sim := arena.battle.sim
			var result := "Empate: ninguém sobreviveu"
			if sim.alive_count(CombatUnit.Team.PLAYER) > 0:
				result = "Aliados venceram (%d vivos)" % sim.alive_count(CombatUnit.Team.PLAYER)
			elif sim.alive_count(CombatUnit.Team.ENEMY) > 0:
				result = "Inimigos venceram (%d vivos)" % sim.alive_count(CombatUnit.Team.ENEMY)
			return "FIM · %s em %.1f s · Reiniciar restaura a montagem" % [result, sim.time]
		_:
			if allies == 0 and enemies == 0:
				return "PREPARAÇÃO · adicione aliados e inimigos pelas listas"
			if not can_start():
				return "PREPARAÇÃO · %d aliados × %d inimigos · precisa de pelo menos um de cada lado" % [allies, enemies]
			return "PREPARAÇÃO · %d aliados × %d inimigos · clique numa tropa para inspecionar" % [allies, enemies]
