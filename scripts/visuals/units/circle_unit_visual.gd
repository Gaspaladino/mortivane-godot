class_name CircleUnitVisual
extends UnitVisual
## Visual padrão (o círculo das etapas anteriores), usado por UnitDef sem visual_script.

const HIT_FLASH_SECONDS := 0.12
const DEATH_FADE_SECONDS := 0.5

var _flash := 0.0
var _alpha := 1.0


func update_visual(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	if not unit.is_alive():
		_alpha = maxf(0.0, _alpha - delta / DEATH_FADE_SECONDS)
	queue_redraw()


func on_hit() -> void:
	_flash = HIT_FLASH_SECONDS


func _draw() -> void:
	if _alpha <= 0.0:
		return
	var body := def.body_color
	var trim := def.trim_color
	if _flash > 0.0:
		body = body.lerp(Color.WHITE, 0.7)
	body.a *= _alpha
	trim.a *= _alpha
	var r := unit.radius
	draw_circle(Vector2(0, r * 0.35), r * 0.9, Color(0, 0, 0, 0.3 * _alpha))
	draw_circle(Vector2.ZERO, r, body)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, trim, 1.5, true)
	var facing := Vector2.RIGHT if unit.team == CombatUnit.Team.PLAYER else Vector2.LEFT
	if unit.target != null:
		facing = (unit.target.position - unit.position).normalized()
	draw_line(facing * r * 0.3, facing * r * 1.25, trim, 2.0, true)
