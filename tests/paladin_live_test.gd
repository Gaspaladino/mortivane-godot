extends SceneTree
## Teste headless do Paladino Vivo PADRÃO (PaladinLiveVisual — mesma linguagem do Guerreiro e da
## Sentinela). O visual só OBSERVA a simulação:
##   - stats, provocação, escudo e o resultado do combate são idênticos com e sem o visual;
##   - animações não aplicam dano, bloqueio visual não reduz dano, empurrão visual não desloca,
##     morte visual não mata; direção não muda gameplay;
##   - espada SEMPRE na mão direita e escudo SEMPRE no braço esquerdo, em todas as direções e
##     estados; nenhuma direção usa espelho;
##   - família visual: um pouco mais alto e mais largo que o Guerreiro, sem virar chefe;
##   - cada estado vem do estado real; Sandbox: prévias só visuais, Reiniciar/Limpar, sem vazamento.
##   godot --headless -s res://tests/paladin_live_test.gd

const VDT := 1.0 / 60.0
const D := PaladinPoseLibrary.Dir

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_def_and_stats()
	await _test_family_proportions()
	await _test_equipment_every_direction_and_state()
	await _test_directions()
	await _test_states_from_sim()
	await _test_visual_never_writes_unit()
	await _test_gameplay_identical_with_visuals()
	await _test_sandbox()
	await _test_performance_budget()
	print("paladin_live_test: %s" % ("OK" if _failures == 0 else "%d falha(s)" % _failures))
	quit(1 if _failures > 0 else 0)


func _test_def_and_stats() -> void:
	var def := UnitCatalog.get_def(&"sac_paladin")
	_check(def.visual_scene != null and def.visual_scene.resource_path == "res://scenes/units/paladin_live_visual.tscn", "Paladino Vivo usa a cena do PaladinLiveVisual")
	_check(def.visual_script == PaladinLiveVisual, "visual_script também é o PaladinLiveVisual (funciona sem a cena)")
	var shadow := UnitCatalog.get_def(&"u_sac_paladin")
	_check(shadow.visual_scene == null and shadow.visual_script == ShadowPaladinVisual, "Paladino Sombra continua no visual anterior")
	_check(def.max_hp == 120.0 and def.damage == 13.0 and def.attack_range == 34.0 and def.attack_interval == 1.2 and def.move_speed == 44.0 and def.radius == 14.0,
		"stats do Paladino inalterados")
	_check(def.abilities == [&"paladin_taunt_shield"], "habilidade inalterada")
	_check(PaladinTaunt.TAUNT_RADIUS == 115.0 and PaladinTaunt.TAUNT_DURATION == 2.5 and PaladinTaunt.SHIELD_DELAY == 1.0
		and PaladinTaunt.SHIELD_DURATION == 1.5 and PaladinTaunt.SHIELD_DAMAGE_REDUCTION == 0.75 and PaladinTaunt.COOLDOWN == 15.0,
		"provocação e Escudo Sagrado inalterados")


func _make(team := CombatUnit.Team.PLAYER, pos := Vector2(400, 380), id := &"sac_paladin") -> UnitView:
	var def := UnitCatalog.get_def(id)
	var u := CombatUnit.new(1, team, def.to_stats(), pos)
	var view := UnitView.new(u, def)
	root.add_child(view)
	view.process_mode = Node.PROCESS_MODE_DISABLED   # o teste dirige o visual quadro a quadro
	return view


func _tick(v: UnitVisual, seconds: float, move := Vector2.ZERO) -> void:
	for i in int(round(seconds / VDT)):
		v.unit.position += move * VDT
		v.update_visual(VDT)


## Mesma família: pouco mais alto que o Guerreiro, ombros mais largos, sem virar chefe.
func _test_family_proportions() -> void:
	var pv := _make()
	var wv := _make(CombatUnit.Team.PLAYER, Vector2(400, 380), &"warrior")
	await process_frame
	var p := pv.visual as PaladinLiveVisual
	var w := wv.visual as WarriorVisual
	_tick(p, 0.2)
	var h_ratio := (p.ground_point().y - p.top_y()) / (w.ground_point().y - w.top_y())
	_check(h_ratio > 1.0 and h_ratio < 1.25, "um pouco mais alto que o Guerreiro (%.2f×)" % h_ratio)
	var span := absf(p.anchors.r_shoulder.x - p.anchors.l_shoulder.x) * PaladinLiveVisual.RIG_SCALE
	_check(span > 9.0, "ombros largos (%.1f unidades entre os ombros, na vista 3/4)" % span)
	_check(PaladinLiveVisual.RIG_SCALE == WarriorVisual.RIG_SCALE and PaladinLiveVisual.FOOT_Y == WarriorVisual.FOOT_Y, "mesma escala e mesmo chão do Guerreiro")
	_check(p.outline == w.outline, "mesmo contorno escuro do Guerreiro")
	pv.queue_free()
	wv.queue_free()
	await process_frame


func _test_equipment_every_direction_and_state() -> void:
	var view := _make()
	await process_frame
	var v := view.visual as PaladinLiveVisual
	var states := [[&"idle", 0.6], [&"walk", 0.4], [&"attack", 0.2], [&"attack", 0.36], [&"attack", 0.5], [&"hit", 0.06],
		[&"push", 0.15], [&"taunt", 0.45], [&"shield", 0.6], [&"block", 0.06], [&"death", 0.2]]
	var ok := true
	for d in 8:
		for st in states:
			v.preview(st[0], d)
			_tick(v, st[1])
			v._build_parts(v._pose)
			var A: Dictionary = v.anchors
			# a espada nasce da mão DIREITA; o escudo, do braço ESQUERDO
			if (A.sword_grip3 as Vector3).distance_to(A.r_hand3) > 0.001:
				ok = false
			# o escudo fica à frente da mão esquerda (até ~6,5 quando avança na provocação/guarda)
			if (A.shield_c3 as Vector3).distance_to(A.l_hand3) > 7.0:
				ok = false
			if v.scale.x < 0.0 or view.scale.x < 0.0:
				ok = false
	_check(ok, "espada da mão direita e escudo do braço esquerdo em 8 direções × 11 estados, sem espelho")
	# ombro direito do lado direito do corpo (L < 0) em qualquer direção
	_check(PaladinLiveVisual.RIGHT < 0.0 and PaladinLiveVisual.LEFT > 0.0, "lado direito = L negativo")
	v.preview(&"death", D.RIGHT)
	_tick(v, 2.2)
	_check(not v._sword_drop.is_empty() and not v._shield_drop.is_empty(), "na morte a espada cai e o escudo tomba")
	view.queue_free()
	await process_frame


func _test_directions() -> void:
	var view := _make()
	await process_frame
	var v := view.visual as PaladinLiveVisual
	var ok := true
	var yaws := {}
	for d in 8:
		var a := d * PI / 4.0
		v.unit.state = CombatUnit.State.MOVING
		_tick(v, 0.8, Vector2(sin(a), cos(a)) * v.unit.move_speed)
		if v.animator.dir != d:
			ok = false
		yaws[d] = v._yaw
		if absf(wrapf(v._yaw - v._dir_yaw(d, v.animator.lateral), -180.0, 180.0)) > 1.0:
			ok = false
	_check(ok, "andar em cada uma das 8 direções vira o corpo para ela")
	_check(is_equal_approx(v._dir_yaw(D.LEFT, -1.0), -v._dir_yaw(D.RIGHT, 1.0)), "esquerda = mesmo giro para o outro lado (sem espelho)")
	_check(v._dir_yaw(D.DOWN, 1.0) < v._dir_yaw(D.DOWN_RIGHT, 1.0) and v._dir_yaw(D.DOWN_RIGHT, 1.0) < v._dir_yaw(D.RIGHT, 1.0)
		and v._dir_yaw(D.RIGHT, 1.0) < v._dir_yaw(D.UP_RIGHT, 1.0) and v._dir_yaw(D.UP_RIGHT, 1.0) < v._dir_yaw(D.UP, 1.0), "cada direção tem um giro próprio")
	view.queue_free()
	await process_frame


func _test_states_from_sim() -> void:
	var view := _make()
	await process_frame
	var v := view.visual as PaladinLiveVisual
	var u := v.unit
	var an := v.animator
	_tick(v, 0.3)
	_check(an.debug_state == &"IDLE", "parado → IDLE")
	u.state = CombatUnit.State.MOVING
	_tick(v, 0.6, Vector2(u.move_speed, 0))
	_check(an.debug_state == &"WALK", "andando → WALK")
	var foe := CombatUnit.new(2, CombatUnit.Team.ENEMY, UnitCatalog.get_def(&"warrior").to_stats(), u.position + Vector2(30, 0))
	u.target = foe
	u.state = CombatUnit.State.ATTACKING
	u.cooldown = 0.25
	_tick(v, VDT)
	_check(an.attack_active and an.attack_p < PaladinPoseLibrary.ATTACK_IMPACT, "preparação do golpe pela recarga real")
	u.cooldown = 0.001
	_tick(v, 0.2)
	_check(not an.attack_struck, "segura antes do impacto até o dano real")
	u.cooldown = u.attack_interval
	v.on_attack_performed()
	_check(an.attack_struck and an.attack_p >= PaladinPoseLibrary.ATTACK_IMPACT, "impacto no evento real de dano")
	_tick(v, PaladinPoseLibrary.ATTACK_TIME)
	u.target = null
	u.state = CombatUnit.State.IDLE
	_tick(v, 0.5)
	_check(an.debug_state == &"IDLE", "depois do golpe volta ao idle")
	v.on_hit()
	_tick(v, VDT)
	_check(String(an.debug_state).contains("HIT") and v.p_flash > 0.0, "dano → HIT curto com clarão")
	_tick(v, 0.3)
	_check(not String(an.debug_state).contains("HIT") and v.p_flash == 0.0, "HIT volta ao estado anterior")
	v.on_ability_event(&"taunt")
	u.paladin.delay = PaladinTaunt.SHIELD_DELAY
	_tick(v, 0.3)
	_check(an.debug_state == &"TAUNT", "provocação real → TAUNT")
	_tick(v, 0.6)
	_check(an.debug_state == &"GUARD_READY", "espera do escudo → guarda pronta")
	u.paladin.delay = -1.0
	u.paladin.shield_t = PaladinTaunt.SHIELD_DURATION
	u.paladin.facing = Vector2(1, 0)
	v.on_ability_event(&"shield")
	_tick(v, 0.4)
	_check(an.debug_state == &"SHIELD_ACTIVE", "escudo real → SHIELD_ACTIVE")
	v.on_ability_event(&"block")
	v.on_hit()
	_tick(v, VDT)
	_check(String(an.debug_state).contains("BLOCK") and not String(an.debug_state).contains("HIT"), "bloqueio real → BLOCK")
	u.paladin.shield_t = 0.0
	_tick(v, 0.8)
	_check(an.debug_state == &"IDLE", "escudo acabou → idle")
	var after_sim := u.position + Vector2(-6, 0)
	u.position = after_sim
	_tick(v, VDT)
	_check(String(an.debug_state).contains("PUSH") and u.position == after_sim, "deslocamento real sem andar → PUSH (a animação não move)")
	_tick(v, 0.6)
	u.die()
	_tick(v, 0.5)
	_check(an.debug_state == &"DEATH", "morto → DEATH")
	_tick(v, 1.5)
	_check(an.debug_state == &"CORPSE" and v.pick_rect().size.x > v.pick_rect().size.y, "cadáver deitado")
	view.queue_free()
	await process_frame


func _test_visual_never_writes_unit() -> void:
	var view := _make()
	await process_frame
	var v := view.visual as PaladinLiveVisual
	var u := v.unit
	var foe := CombatUnit.new(2, CombatUnit.Team.ENEMY, UnitCatalog.get_def(&"warrior").to_stats(), u.position + Vector2(30, 0))
	u.target = foe
	u.state = CombatUnit.State.ATTACKING
	u.cooldown = 0.4
	u.paladin.cooldown = 7.0
	var snap := _snapshot(u)
	for kind in [&"idle", &"walk", &"attack", &"hit", &"push", &"taunt", &"shield", &"block", &"death"]:
		v.preview(kind, D.UP_RIGHT)
		_tick(v, 0.3)
	v.on_attack_performed()
	v.on_hit()
	v.on_ability_event(&"taunt")
	v.on_ability_event(&"shield")
	v.on_ability_event(&"block")
	v.on_pushed(Vector2(-1, 0))
	_tick(v, 2.0)
	_check(_snapshot(u) == snap, "visual não altera a CombatUnit")
	_check(u.is_alive() and foe.hp == foe.max_hp, "animações não matam nem aplicam dano")
	view.queue_free()
	await process_frame


func _snapshot(u: CombatUnit) -> Array:
	var p := u.paladin
	return [u.hp, u.max_hp, u.damage, u.attack_range, u.attack_interval, u.move_speed, u.radius, u.position,
		u.state, u.cooldown, u.target, u.team, p.cooldown, p.delay, p.shield_t, p.shield_hit, p.facing]


## A mesma luta só na CombatSim e no Sandbox real com os visuais (e perturbações visuais): idêntica.
func _test_gameplay_identical_with_visuals() -> void:
	var lineup := [[&"sac_paladin", CombatUnit.Team.PLAYER], [&"sac_paladin", CombatUnit.Team.PLAYER], [&"u_warrior", CombatUnit.Team.PLAYER],
		[&"warrior", CombatUnit.Team.ENEMY], [&"sac_paladin", CombatUnit.Team.ENEMY], [&"arc_battlemage", CombatUnit.Team.ENEMY]]
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.show_sandbox()
	await process_frame
	var sb: SandboxController = main.current_screen
	var battle := sb.arena.battle
	var counts := {CombatUnit.Team.PLAYER: 0, CombatUnit.Team.ENEMY: 0}
	var pure := CombatSim.new(battle.rng_seed)
	for e in lineup:
		sb.add_unit(UnitCatalog.get_def(e[0]), e[1])
		pure.add_unit(e[1], UnitCatalog.get_def(e[0]).to_stats(), SandboxController.slot_position(e[1], counts[e[1]]))
		counts[e[1]] += 1
	sb.start_combat()
	var same := true
	var taunts := [0, 0]
	var blocks := [0, 0]
	pure.paladin_taunted.connect(func(_p, _f) -> void: taunts[0] += 1)
	battle.sim.paladin_taunted.connect(func(_p, _f) -> void: taunts[1] += 1)
	pure.paladin_shield_blocked.connect(func(_p, _a) -> void: blocks[0] += 1)
	battle.sim.paladin_shield_blocked.connect(func(_p, _a) -> void: blocks[1] += 1)
	var steps := 0
	while steps < 120 * 45 and not pure.is_finished():
		pure.step(CombatSim.STEP)
		battle._process(CombatSim.STEP)
		for view in battle._views.values():
			view._process(CombatSim.STEP)
		steps += 1
		if steps % 90 == 0:
			for view in battle._views.values():
				if view.visual is PaladinLiveVisual:
					view.visual.on_pushed(Vector2(1, 0))
					view.visual.on_hit()
					view.visual.on_ability_event(&"block")
		for i in pure.units.size():
			var a: CombatUnit = pure.units[i]
			var b: CombatUnit = battle.sim.units[i]
			if a.hp != b.hp or a.position != b.position or a.state != b.state or a.cooldown != b.cooldown:
				same = false
		if not same:
			break
	_check(same, "HP, posição, estado e recarga idênticos com e sem os visuais (%d passos)" % steps)
	_check(taunts[0] == taunts[1] and taunts[0] > 0 and blocks[0] == blocks[1], "mesmas provocações (%d) e bloqueios (%d)" % [taunts[0], blocks[0]])
	_check(pure.is_finished() and battle.sim.is_finished(), "as duas lutas terminam")
	pure.dispose()
	main.queue_free()
	await _frames(3)


func _test_sandbox() -> void:
	var nodes0 := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var orphans0 := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.show_sandbox()
	await process_frame
	var sb: SandboxController = main.current_screen
	var battle := sb.arena.battle
	var pal := sb.add_unit(UnitCatalog.get_def(&"sac_paladin"), CombatUnit.Team.PLAYER)
	sb.add_unit(UnitCatalog.get_def(&"warrior"), CombatUnit.Team.ENEMY)
	await process_frame
	var view := battle.view_of(pal.unit)
	_check(view.visual is PaladinLiveVisual, "Paladino Vivo no Sandbox usa o PaladinLiveVisual")
	sb.select_at(pal.unit.position + Vector2(0, -8))
	_check(sb.selected == pal, "clique seleciona o Paladino")
	await process_frame
	var row: Control = sb.ui.find_child("PreviewRow", true, false)
	_check(row != null and row.visible, "fileira de prévia aparece para o Paladino selecionado")
	var btn: Button = sb.ui.find_child("Preview_attack_3", true, false)
	var snap := _snapshot(pal.unit)
	btn.pressed.emit()
	await _frames(5)
	var v := view.visual as PaladinLiveVisual
	_check(v.animator.preview_kind == &"attack" and v.animator.attack_active, "botão dispara a prévia de ataque UP_RIGHT")
	for b in row.get_children():
		if b is Button:
			b.pressed.emit()
			await _frames(2)
	_check(_snapshot(pal.unit) == snap, "prévias não alteram a unidade")
	sb.start_combat()
	await process_frame
	_check(v.animator.preview_kind == &"" and not v.animator.dead and v._sword_drop.is_empty(), "Iniciar combate desliga a prévia")
	_check(btn.disabled, "prévia desabilitada durante o combate")
	sb.reset_combat()
	await process_frame
	_check(battle.view_of(pal.unit).visual != v, "Reiniciar recria o visual")
	sb.clear_arena()
	await _frames(3)
	_check(battle.sim.units.is_empty() and battle._views.is_empty(), "Limpar esvazia")
	main.show_menu()
	await _frames(3)
	main.queue_free()
	await _frames(4)
	var nodes1 := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var orphans1 := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	_check(nodes1 <= nodes0 and orphans1 <= orphans0, "sair do Sandbox não deixa nós (%d → %d, órfãos %d → %d)" % [nodes0, nodes1, orphans0, orphans1])


func _test_performance_budget() -> void:
	var view := _make()
	await process_frame
	var v := view.visual as PaladinLiveVisual
	v.preview(&"walk", D.DOWN_RIGHT)
	var n := 200
	var t0 := Time.get_ticks_usec()
	for i in n:
		v.update_visual(VDT)
		v._build_parts(v._pose)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
	_check(ms < 1.0, "um Paladino custa %.3f ms por quadro de CPU (pose + partes)" % ms)
	print("  custo por Paladino: %.3f ms/quadro" % ms)
	view.queue_free()
	await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures += 1
		printerr("  FALHOU: ", what)
