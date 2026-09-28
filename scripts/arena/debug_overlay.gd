extends Node2D
## Sobreposição de referência da arena. Só desenho: não participa de lógica.
## F3 liga/desliga.

const COLOR_WORLD := Color(1.0, 1.0, 1.0, 0.35)
const COLOR_CROP := Color(1.0, 1.0, 1.0, 0.22)
const COLOR_FIELD := Color(0.49, 0.88, 0.54)       # --bile
const COLOR_TOP_Y := Color(1.0, 0.72, 0.3)
const COLOR_DEPLOY := Color(0.63, 0.42, 0.96)      # --violet
const COLOR_PORTAL := Color(0.94, 0.78, 0.45)      # --gold
const COLOR_PLAYER_GRID := Color(0.75, 0.65, 0.95, 0.35)
const COLOR_ENEMY_GRID := Color(0.95, 0.5, 0.5, 0.3)
const COLOR_BLOCKED := Color(0.05, 0.03, 0.08, 0.45)
const COLOR_NECRO := Color(0.47, 0.34, 0.66, 0.35)

const FONT_SIZE := 10

@onready var info_layer: CanvasLayer = $InfoLayer
@onready var info_label: Label = $InfoLayer/InfoLabel

var _view := Rect2(Vector2.ZERO, WorldConfig.SIZE)
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		visible = not visible
		info_layer.visible = visible


## Chamado pela Arena a cada resize.
func set_frame(view: Rect2, window_size: Vector2i) -> void:
	_view = view
	info_label.text = "Janela: %d×%d   ·   Mundo visível: %.0f×%.0f a partir de (%.0f, %.0f)   ·   Escala: %.2f\nF3: debug   ·   F11: tela cheia" % [
		window_size.x, window_size.y, view.size.x, view.size.y,
		view.position.x, view.position.y, window_size.x / view.size.x]
	queue_redraw()


func _draw() -> void:
	_draw_world_bounds()
	_draw_grid(BattleGrid.Team.PLAYER, COLOR_PLAYER_GRID)
	_draw_grid(BattleGrid.Team.ENEMY, COLOR_ENEMY_GRID)
	_draw_battlefield()
	_draw_top_line()
	_draw_deploy_line()
	_draw_portal()


func _draw_world_bounds() -> void:
	draw_rect(Rect2(Vector2.ZERO, WorldConfig.SIZE), COLOR_WORLD, false, 1.0)
	_label(Vector2(WorldConfig.WIDTH - 4, WorldConfig.HEIGHT - 4), "1000,560", COLOR_WORLD, HORIZONTAL_ALIGNMENT_RIGHT)
	# faixas que podem ser cortadas em telas muito largas (56 do céu, 14 do rodapé)
	var crop_top := (WorldConfig.HEIGHT - WorldConfig.MIN_VISIBLE_HEIGHT) * WorldConfig.TOP_CROP_SHARE
	var crop_bottom := WorldConfig.HEIGHT - (WorldConfig.HEIGHT - WorldConfig.MIN_VISIBLE_HEIGHT) * (1.0 - WorldConfig.TOP_CROP_SHARE)
	draw_dashed_line(Vector2(0, crop_top), Vector2(WorldConfig.WIDTH, crop_top), COLOR_CROP, 1.0, 4.0)
	draw_dashed_line(Vector2(0, crop_bottom), Vector2(WorldConfig.WIDTH, crop_bottom), COLOR_CROP, 1.0, 4.0)
	_label(Vector2(WorldConfig.WIDTH - 4, crop_top - 3), "y=%d · corte máx. em tela larga" % crop_top, COLOR_CROP, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_grid(team: BattleGrid.Team, line_color: Color) -> void:
	for row in BattleGrid.ROWS:
		for col in BattleGrid.COLS:
			var cell := BattleGrid.cell_rect(team, row, col).grow(-1.0)
			match BattleGrid.cell_state(team, row, col):
				"B":
					draw_rect(cell, COLOR_BLOCKED, true)
				"N":
					draw_rect(cell, COLOR_NECRO, true)
			draw_rect(cell, line_color, false, 1.0)
	var rect := BattleGrid.grid_rect(team)
	var label_color := line_color * Color(1, 1, 1, 2.5)
	if team == BattleGrid.Team.ENEMY:
		_label(Vector2(rect.end.x, rect.position.y - 4), "grade inimiga %d×%d" % [BattleGrid.COLS, BattleGrid.ROWS], label_color, HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		_label(Vector2(rect.position.x + 2, rect.end.y + 11), "grade do jogador %d×%d" % [BattleGrid.COLS, BattleGrid.ROWS], label_color)
		var necro := BattleGrid.cell_rect(team, 3, 0).merge(BattleGrid.cell_rect(team, 4, 1))
		_label(necro.get_center() + Vector2(0, 4), "N", Color(0.85, 0.75, 1.0), HORIZONTAL_ALIGNMENT_CENTER)


func _draw_battlefield() -> void:
	var r := WorldConfig.BATTLEFIELD_RECT
	draw_rect(r, Color(COLOR_FIELD, 0.05), true)
	draw_rect(r, COLOR_FIELD, false, 1.5)
	_label(Vector2(r.position.x + 3, r.end.y - 4), "x=%d" % r.position.x, COLOR_FIELD)
	_label(Vector2(r.end.x - 3, r.end.y - 4), "x=%d" % r.end.x, COLOR_FIELD, HORIZONTAL_ALIGNMENT_RIGHT)
	_label(Vector2(r.end.x - 3, r.end.y + 11), "y=%d · limite inferior" % r.end.y, COLOR_FIELD, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_top_line() -> void:
	var y := WorldConfig.BATTLEFIELD_TOP_Y
	draw_line(Vector2(_view.position.x, y), Vector2(_view.end.x, y), COLOR_TOP_Y, 1.5)
	_label(Vector2(WorldConfig.MARGIN + 3, y - 4), "y=%d · topo do campo (acima: céu)" % y, COLOR_TOP_Y)


func _draw_deploy_line() -> void:
	var x := WorldConfig.DEPLOY_X
	draw_dashed_line(Vector2(x, _view.position.y), Vector2(x, _view.end.y), COLOR_DEPLOY, 1.5, 7.0)
	_label(Vector2(x + 5, WorldConfig.BATTLEFIELD_TOP_Y + 14), "x=%d · divisa (jogador ◀ ▶ inimigo)" % x, COLOR_DEPLOY)


func _draw_portal() -> void:
	var p := WorldConfig.PORTAL_POSITION
	var r := WorldConfig.PORTAL_RADIUS
	draw_circle(p, r, Color(COLOR_PORTAL, 0.10))
	draw_arc(p, r, 0.0, TAU, 64, COLOR_PORTAL, 1.5, true)
	draw_line(p - Vector2(6, 0), p + Vector2(6, 0), COLOR_PORTAL, 1.0)
	draw_line(p - Vector2(0, 6), p + Vector2(0, 6), COLOR_PORTAL, 1.0)
	var gy := WorldConfig.PORTAL_GROUND_BREAK_Y
	draw_line(Vector2(p.x - 60, gy), Vector2(p.x + 60, gy), COLOR_PORTAL, 2.0)
	_label(p + Vector2(r + 6, -2), "portal (%d, %d) r=%d" % [p.x, p.y, r], COLOR_PORTAL)
	_label(Vector2(p.x + 64, gy + 4), "rompe o chão y=%d" % gy, COLOR_PORTAL)


func _label(pos: Vector2, text: String, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var width := -1.0
	if align != HORIZONTAL_ALIGNMENT_LEFT:
		# draw_string alinha dentro de uma largura; ancora o texto pela direita/centro de pos
		width = 400.0
		pos.x -= width if align == HORIZONTAL_ALIGNMENT_RIGHT else width / 2.0
	draw_string_outline(_font, pos, text, align, width, FONT_SIZE, 3, Color(0, 0, 0, 0.85))
	draw_string(_font, pos, text, align, width, FONT_SIZE, color)
