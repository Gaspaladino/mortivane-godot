extends SceneTree
## Teste headless dos visuais desenhados por código (Guerreiro e Guerreiro Sombra).
## Dirige os visuais quadro a quadro com CombatUnit reais e verifica a pose resultante.
## Rodar a partir da raiz do projeto:
##   godot --headless -s res://tests/visual_test.gd

const DT := 1.0 / 60.0

var _failures := 0


func _initialize() -> void:
	for id in [&"warrior", &"u_warrior"]:
		_test_visual(id)
	_test_fallback_circle()
	print("visual_test: %s" % ("OK" if _failures == 0 else "%d falha(s)" % _failures))
	quit(1 if _failures > 0 else 0)


func _make(id: StringName) -> WarriorVisual:
	var def := UnitCatalog.get_def(id)
	var unit := CombatUnit.new(1, def.side, def.to_stats(), Vector2(300, 380))
	var visual: WarriorVisual = def.visual_script.new()
	visual.setup(unit, def)
	root.add_child(visual)
	return visual


func _tick(v: WarriorVisual, seconds: float, move := Vector2.ZERO) -> void:
	for i in int(round(seconds / DT)):
		v.unit.position += move * DT
		v.update_visual(DT)


func _test_visual(id: StringName) -> void:
	var v := _make(id)
	var u := v.unit
	var tag := String(id)
	var expected: Script = WarriorVisual if id == &"warrior" else ShadowWarriorVisual
	_check(v.get_script() == expected, "%s: UnitDef aponta para o visual certo" % tag)
	var snapshot := [u.hp, u.max_hp, u.damage, u.attack_range, u.attack_interval, u.move_speed, u.cooldown, u.state, u.position]

	# IDLE: respira (a pose muda com o tempo), sem andar
	var y0 := v.p_offset.y
	_tick(v, 0.4)
	_check(v.p_offset.y != y0, "%s: IDLE anima" % tag)
	_check(absf(v.p_offset.y) < 2.0 and v._walk_w == 0.0, "%s: IDLE sutil e parado" % tag)

	# WALK: fase só avança com deslocamento real (não "desliza parado")
	u.state = CombatUnit.State.MOVING
	var phase := v._walk_phase
	_tick(v, 0.3, Vector2(u.move_speed, 0))
	_check(v._walk_phase > phase and v._walk_w > 0.9, "%s: WALK avança com a distância" % tag)
	var legs := [v.p_leg_f, v.p_leg_b]
	_tick(v, 0.12, Vector2(u.move_speed, 0))
	_check(legs != [v.p_leg_f, v.p_leg_b], "%s: WALK alterna as pernas" % tag)
	phase = v._walk_phase
	_tick(v, 0.2)   # MOVING mas sem deslocamento
	_check(v._walk_phase == phase, "%s: sem deslocamento, a fase não avança" % tag)

	# ATTACK: preparação lida da recarga real; golpe no evento
	u.state = CombatUnit.State.ATTACKING
	u.cooldown = 0.8
	_tick(v, 0.3)
	var rest_arm := v.p_arm_f
	u.cooldown = 0.0
	_tick(v, 0.05)
	_check(absf(v.p_arm_f - v.windup_arm) < 2.0, "%s: PREPARA leva o braço para trás (%.0f)" % [tag, v.p_arm_f])
	u.cooldown = u.attack_interval
	v.on_attack_performed()
	_tick(v, v.strike_time)
	_check(absf(v.p_arm_f - v.strike_arm) < 12.0 and v.p_offset.x > 0.5, "%s: GOLPE para frente com avanço (%.0f)" % [tag, v.p_arm_f])
	_tick(v, v.recover_time + 0.05)
	_check(v._strike_t < 0.0 and absf(v.p_arm_f - rest_arm) < 8.0, "%s: RETORNO ao repouso" % tag)

	# HIT: recuo + clarão curtos, sem mudar gameplay
	u.state = CombatUnit.State.IDLE
	v.on_hit()
	_tick(v, DT)
	_check(v.p_flash > 0.2 and v.p_offset.x < -0.5, "%s: HIT recua e clareia" % tag)
	_tick(v, 0.3)
	_check(v.p_flash == 0.0, "%s: HIT é curto" % tag)

	# o visual nunca altera a CombatUnit
	u.state = snapshot[7]
	u.cooldown = snapshot[6]
	_check([u.hp, u.max_hp, u.damage, u.attack_range, u.attack_interval, u.move_speed] == snapshot.slice(0, 6), "%s: visual não altera stats" % tag)

	# DEATH: cai e permanece no chão
	u.die()
	v.on_attack_performed()   # evento tardio não reanima
	_tick(v, v.death_time * 0.75)   # o morto-vivo primeiro cede os joelhos, depois tomba
	var mid := v.p_rot
	_tick(v, 2.0)
	var fallen := v.p_rot
	_check(absf(mid) > 5.0 and absf(fallen) > 80.0, "%s: DEATH cai (%.0f → %.0f)" % [tag, mid, fallen])
	_check((fallen < 0.0) == (id == &"warrior"), "%s: direção da queda (vivo de costas, morto-vivo para frente)" % tag)
	_tick(v, 1.0)
	_check(is_equal_approx(v.p_rot, fallen) and v._strike_t < 0.0, "%s: permanece no chão" % tag)
	_check(v.pick_rect().size.x > v.pick_rect().size.y, "%s: área clicável deitada" % tag)
	v.queue_free()


func _test_fallback_circle() -> void:
	var def := UnitDef.new()
	def.display_name = "Teste"
	var unit := CombatUnit.new(1, CombatUnit.Team.ENEMY, def.to_stats(), Vector2(500, 380))
	var view := UnitView.new(unit, def)
	_check(view.visual is CircleUnitVisual, "UnitDef sem visual_script usa o círculo padrão")
	view.free()


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures += 1
		printerr("  FALHOU: ", what)
