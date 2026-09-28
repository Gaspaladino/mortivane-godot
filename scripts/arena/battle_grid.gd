class_name BattleGrid
extends RefCounted
## Geometria das grades de formação (HTML: buildBattleGrid / PLAYER_GRID_MASK).
## Nesta etapa é só leitura visual/debug: nenhuma ocupação, footprint ou arrasto.

enum Team { PLAYER, ENEMY }

const COLS := 11
const ROWS := 7

## A = livre, B = bloqueada, N = reservada ao Necromante. Linhas de cima para baixo.
const PLAYER_MASK := [
	"BBAAAAAAAAA",
	"BAAAAAAAAAA",
	"AAAAAAAAAAA",
	"NNAAAAAAAAA",
	"NNAAAAAAAAA",
	"AAAAAAAAAAA",
	"BAAAAAAAAAA",
]


## Retângulo da grade inteira de um lado, em coordenadas do mundo.
static func grid_rect(team: Team) -> Rect2:
	var full := WorldConfig.HEIGHT - WorldConfig.MARGIN - 15.0
	var cell_h := (full - (WorldConfig.BATTLEFIELD_TOP_Y + 38.0)) / 7.0
	var left: float
	var right: float
	var bottom: float
	if team == Team.ENEMY:
		left = WorldConfig.WIDTH / 2.0 + 12.0
		right = WorldConfig.WIDTH - WorldConfig.MARGIN - 12.0
		bottom = full
	else:
		left = WorldConfig.MARGIN + 12.0
		right = WorldConfig.WIDTH / 2.0 - 12.0
		# a última fileira do jogador (coberta pelos menus no HTML) foi removida
		bottom = full - (8 - ROWS) * cell_h
	var top := bottom - ROWS * cell_h
	return Rect2(left, top, right - left, bottom - top)


static func cell_size(team: Team) -> Vector2:
	return grid_rect(team).size / Vector2(COLS, ROWS)


static func cell_rect(team: Team, row: int, col: int) -> Rect2:
	var size := cell_size(team)
	return Rect2(grid_rect(team).position + Vector2(col, row) * size, size)


static func cell_state(team: Team, row: int, col: int) -> String:
	if row < 0 or row >= ROWS or col < 0 or col >= COLS:
		return "B"
	if team == Team.PLAYER:
		return PLAYER_MASK[row][col]
	return "A"
