extends SceneTree
## Teste headless do Paladino (vivo e Sombra): stats e mecânica portados do HTML
## (PALADIN_CONFIG / tickPaladinCombat / paladinShieldDamage) e o visual.
##   godot --headless -s res://tests/paladin_test.gd

const DT := CombatSim.STEP
const VDT := 1.0 / 60.0

var _failures := 0


func _initialize() -> void:
	_test_defs()
	_test_taunt()
	_test_shield()
	_test_cooldown_and_radius()
	_test_death_clears_taunt()
	_test_many_paladins()
	_test_reference_fight_unchanged()
	for id in [&"sac_paladin", &"u_sac_paladin"]:   # sac_paladin: o visual por código (fallback)
		_test_visual(id)
	_test_shadow_rule()
	_run_sandbox.call_deferred()


# --- Stats (HTML: FACTION_UNITS.sac_paladin; u_sac_paladin por registerFactionUnits) -------

func _test_defs() -> void:
	var live := UnitCatalog.get_def(&"sac_paladin")
	var dead := UnitCatalog.get_def(&"u_sac_paladin")
	_check(live != null and dead != null, "sac_paladin e u_sac_paladin no catálogo")
	if live == null or dead == null:
		return
	for d in [live, dead]:
		_check(d.damage == 13.0 and d.attack_range == 34.0 and d.attack_interval == 1.2 and d.move_speed == 44.0 and d.radius == 14.0,
			"%s: dmg 13, range 34, cd 1,2, speed 44, r 14 (HTML)" % d.id)
		_check(d.projectile_kind == &"" and d.abilities == [&"paladin_taunt_shield"], "%s: corpo a corpo + paladin_taunt_shield" % d.id)
	_check(live.max_hp == 120.0 and dead.max_hp == 113.0, "HP 120 / Sombra round(120 × 0,94) = 113")
	_check(live.side == CombatUnit.Team.ENEMY and dead.side == CombatUnit.Team.PLAYER, "lados: vivo inimigo, Sombra aliada")
	_check(PaladinTaunt.TAUNT_RADIUS == 115.0 and PaladinTaunt.TAUNT_DURATION == 2.5 and PaladinTaunt.SHIELD_DELAY == 1.0
		and PaladinTaunt.SHIELD_DURATION == 1.5 and PaladinTaunt.SHIELD_DAMAGE_REDUCTION == 0.75 and PaladinTaunt.COOLDOWN == 15.0,
		"PALADIN_CONFIG do HTML (115 · 2,5 s · 1 s · 1,5 s · 75% · 15 s)")
	var u := CombatUnit.new(1, CombatUnit.Team.ENEMY, live.to_stats(), Vector2(500, 380))
	_check(u.paladin != null and u.swords == null, "CombatUnit do Paladino tem a habilidade (e só ela)")


func _pal_stats(id := &"sac_paladin") -> Dictionary:
	return UnitCatalog.get_def(id).to_stats()


func _war_stats(id := &"u_warrior") -> Dictionary:
	return UnitCatalog.get_def(id).to_stats()


func _run(sim: CombatSim, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		sim.step(DT)


# --- Provocação -------------------------------------------------------------------------------

func _test_taunt() -> void:
	var sim := CombatSim.new(1)
	var pal := sim.add_unit(CombatUnit.Team.ENEMY, _pal_stats(), Vector2(560, 380))
	var near := sim.add_unit(CombatUnit.Team.ENEMY, _war_stats(&"warrior"), Vector2(470, 380))   # outro inimigo, mais perto
	var foe := sim.add_unit(CombatUnit.Team.PLAYER, _war_stats(), Vector2(460, 380))
	var far := sim.add_unit(CombatUnit.Team.PLAYER, _war_stats(), Vector2(300, 250))
	var events := {taunt = 0, shield = 0}
	sim.paladin_taunted.connect(func(_p: CombatUnit, _f: Array) -> void: events.taunt += 1)
	sim.paladin_shield_raised.connect(func(_p: CombatUnit) -> void: events.shield += 1)
	sim.step(DT)
	_check(events.taunt == 1 and foe.taunted_by == pal and is_equal_approx(foe.taunt_t, 2.5), "provoca no 1º passo quem está a ≤ 115 (taunt 2,5 s)")
	_check(foe.target == pal and sim.nearest_foe(foe) == pal, "o provocado mira o Paladino mesmo com outro inimigo mais perto")
	_check(far.taunted_by == null, "fora do raio não é provocado")
	_check(pal.paladin.is_preparing() and is_equal_approx(pal.paladin.cooldown, 15.0), "espera 1 s até o escudo; recarga 15 s")
	_run(sim, 2.3)
	_check(foe.target == pal or not foe.is_alive(), "continua preso ao Paladino durante a provocação")
	_run(sim, 0.3)
	_check(foe.taunted_by == null and foe.taunt_t == 0.0, "a provocação expira em 2,5 s")
	_check(events.shield == 1, "o escudo sobe uma vez")
	_check(near.is_alive(), "(controle) o outro inimigo segue no campo")
	_dispose(sim)


# --- Escudo Sagrado ---------------------------------------------------------------------------

func _test_shield() -> void:
	var sim := CombatSim.new(1)
	var pal := sim.add_unit(CombatUnit.Team.ENEMY, _pal_stats(), Vector2(560, 380))
	var foe := sim.add_unit(CombatUnit.Team.PLAYER, _war_stats(), Vector2(470, 380))
	var raised_at := [-1.0]
	sim.paladin_shield_raised.connect(func(_p: CombatUnit) -> void: raised_at[0] = sim.time)
	sim.step(DT)
	# antes do escudo: dano cheio
	var hp := pal.hp
	sim._apply_damage(foe, pal, 20.0)
	_check(is_equal_approx(pal.hp, hp - 20.0), "antes do escudo o dano é cheio")
	_run(sim, 1.0)
	_check(absf(raised_at[0] - (DT + 1.0)) < DT * 1.5 and pal.paladin.is_shielded(), "o escudo sobe 1 s depois da provocação (%.3f s)" % raised_at[0])
	_check(pal.paladin.facing.x < -0.9, "escudo travado na direção do inimigo")
	var blocked := [0.0]
	sim.paladin_shield_blocked.connect(func(_p: CombatUnit, prevented: float) -> void: blocked[0] += prevented)
	hp = pal.hp
	sim._apply_damage(foe, pal, 20.0)
	_check(is_equal_approx(pal.hp, hp - 5.0) and is_equal_approx(blocked[0], 15.0), "com o escudo: 20 de dano → 5 (75% bloqueado)")
	_check(pal.paladin.shield_hit > 0.0, "impacto no escudo marcado (só apresentação)")
	_run(sim, 1.55)
	_check(not pal.paladin.is_shielded(), "o escudo dura 1,5 s")
	hp = pal.hp
	sim._apply_damage(foe, pal, 20.0)
	_check(is_equal_approx(pal.hp, hp - 20.0), "depois do escudo o dano volta a ser cheio")
	# o escudo só protege o próprio Paladino
	var hp_foe := foe.hp
	sim._apply_damage(pal, foe, 7.0)
	_check(is_equal_approx(foe.hp, hp_foe - 7.0), "quem não é Paladino não tem redução")
	_dispose(sim)


func _test_cooldown_and_radius() -> void:
	var sim := CombatSim.new(1)
	var pal := sim.add_unit(CombatUnit.Team.ENEMY, _pal_stats(), Vector2(700, 380))
	var foe := sim.add_unit(CombatUnit.Team.PLAYER, _war_stats(), Vector2(700 - 116, 380))
	foe.move_speed = 0.0   # parado fora do raio
	pal.move_speed = 0.0
	var count := [0]
	sim.paladin_taunted.connect(func(_p: CombatUnit, _f: Array) -> void: count[0] += 1)
	_run(sim, 0.5)
	_check(count[0] == 0, "a 116 (> 115) não provoca")
	foe.position.x += 2.0   # entra no raio
	sim.step(DT)
	_check(count[0] == 1, "a 114 provoca")
	_run(sim, 14.9)
	_check(count[0] == 1, "não provoca de novo antes de 15 s")
	_run(sim, 0.2)
	_check(count[0] == 2, "provoca de novo depois de 15 s")
	_dispose(sim)


func _test_death_clears_taunt() -> void:
	var sim := CombatSim.new(1)
	var pal := sim.add_unit(CombatUnit.Team.ENEMY, _pal_stats(), Vector2(560, 380))
	var other := sim.add_unit(CombatUnit.Team.ENEMY, _war_stats(&"warrior"), Vector2(640, 380))
	var foe := sim.add_unit(CombatUnit.Team.PLAYER, _war_stats(), Vector2(470, 380))
	sim.step(DT)
	_check(foe.taunted_by == pal, "provocado")
	sim._apply_damage(foe, pal, 999.0)
	_check(not pal.is_alive() and foe.taunted_by == null and foe.taunt_t == 0.0, "Paladino morto libera os provocados")
	_check(not pal.paladin.is_shielded() and not pal.paladin.is_preparing(), "morto: escudo e espera zerados")
	sim.step(DT)
	_check(foe.target == other, "o provocado volta a escolher o inimigo mais próximo")
	_dispose(sim)


func _test_many_paladins() -> void:
	var sim := CombatSim.new(7)
	for i in 3:
		sim.add_unit(CombatUnit.Team.PLAYER, _pal_stats(&"u_sac_paladin"), Vector2(300, 300 + i * 50))
		sim.add_unit(CombatUnit.Team.ENEMY, _pal_stats(), Vector2(700, 300 + i * 50))
		sim.add_unit(CombatUnit.Team.ENEMY, _war_stats(&"warrior"), Vector2(760, 320 + i * 50))
	var taunts := [0]
	sim.paladin_taunted.connect(func(_p: CombatUnit, _f: Array) -> void: taunts[0] += 1)
	while not sim.is_finished() and sim.time < 120.0:
		sim.step(DT)
	_check(sim.is_finished() and taunts[0] >= 6, "vários Paladinos dos dois lados: a luta termina (%.1f s, %d provocações)" % [sim.time, taunts[0]])
	for u in sim.units:
		if not u.is_alive():
			_check(u.taunted_by == null, "mortos sem provocação pendurada")
	_dispose(sim)


## A luta de referência (Guerreiro Morto-Vivo × Guerreiro, semente 97) é a mesma de antes:
## o Paladino só entra em quem tem a habilidade.
func _test_reference_fight_unchanged() -> void:
	var sim := CombatSim.new(97)
	var ally := sim.add_unit(CombatUnit.Team.PLAYER, _war_stats(), Vector2(150, 380))
	var enemy := sim.add_unit(CombatUnit.Team.ENEMY, _war_stats(&"warrior"), Vector2(850, 380))
	var hits := [0]
	sim.unit_attacked.connect(func(_a: CombatUnit, _t: CombatUnit, _m: float) -> void: hits[0] += 1)
	while not sim.is_finished() and sim.time < 60.0:
		sim.step(DT)
	var line := "%s %.0f/%.0f %.3f %d" % ["ally" if ally.is_alive() else "enemy", maxf(ally.hp, enemy.hp), 74.0 if ally.is_alive() else 70.0, sim.time, hits[0]]
	_check(line == REFERENCE_FIGHT, "luta de referência idêntica (%s; antes: %s)" % [line, REFERENCE_FIGHT])
	_dispose(sim)


## Medido no commit anterior a esta etapa (88f32bf), mesma semente e posições.
const REFERENCE_FIGHT := "ally 20/74 12.025 13"


# --- Visual -----------------------------------------------------------------------------------

## O Paladino Vivo agora usa o PaladinLiveVisual (testado em paladin_live_test); o
## PaladinVisual por código continua existindo (é a base do Paladino Sombra) e segue testado aqui.
func _make(id: StringName) -> PaladinVisual:
	var def := UnitCatalog.get_def(id)
	var unit := CombatUnit.new(1, def.side, def.to_stats(), Vector2(300, 380))
	var script: Script = PaladinVisual if id == &"sac_paladin" else def.visual_script
	var v: PaladinVisual = script.new()
	v.setup(unit, def)
	root.add_child(v)
	return v


func _tick(v: PaladinVisual, seconds: float, move := Vector2.ZERO) -> void:
	for i in int(round(seconds / VDT)):
		v.unit.position += move * VDT
		v.update_visual(VDT)


func _test_visual(id: StringName) -> void:
	var v := _make(id)
	var u := v.unit
	var tag := String(id)
	if id == &"sac_paladin":
		_check(UnitCatalog.get_def(id).visual_script == PaladinLiveVisual, "%s: UnitDef aponta para o PaladinLiveVisual (o PaladinVisual segue como base do Sombra)" % tag)
	else:
		_check(v.get_script() == ShadowPaladinVisual, "%s: UnitDef aponta para o visual certo" % tag)
	_check(v.look == UnitCatalog.get_def(id).visual_look and v.look.resource_path == "res://data/visuals/paladin_look.tres", "%s: parâmetros do PaladinLook (Inspector)" % tag)
	var snapshot := [u.hp, u.max_hp, u.damage, u.attack_range, u.attack_interval, u.move_speed, u.radius]

	# IDLE: respira pouco (estável)
	var y0 := v.p_offset.y
	_tick(v, 0.5)
	_check(v.p_offset.y != y0 and absf(v.p_offset.y) < 0.6 and v._walk_w == 0.0, "%s: IDLE sutil e firme" % tag)
	# WALK: passada curta, fase pela distância real
	u.state = CombatUnit.State.MOVING
	var ph := v._walk_phase
	_tick(v, 0.3, Vector2(u.move_speed, 0))
	_check(v._walk_phase > ph and v._walk_w > 0.8, "%s: WALK avança com a distância" % tag)
	_check(absf(v.p_leg_f) <= v.leg_swing + 0.01 and v.leg_swing < 25.0, "%s: passada curta (≤ %.0f°)" % [tag, v.leg_swing])
	ph = v._walk_phase
	_tick(v, 0.2)
	_check(v._walk_phase == ph, "%s: parado não anda" % tag)
	# PREPARA pela recarga real e GOLPE no evento real
	var foe := CombatUnit.new(2, CombatUnit.Team.ENEMY if u.team == CombatUnit.Team.PLAYER else CombatUnit.Team.PLAYER, _war_stats(&"warrior"), u.position + Vector2(30, 0))
	u.target = foe
	u.state = CombatUnit.State.ATTACKING
	u.cooldown = 0.5
	_tick(v, 0.2)
	var rest := v.p_arm_s
	u.cooldown = 0.02
	_tick(v, 0.05)
	_check(v.p_wind > 0.8 and v.p_arm_s > rest + 60.0, "%s: PREPARA ergue a espada (%.0f°)" % [tag, v.p_arm_s])
	u.cooldown = u.attack_interval
	v.on_attack_performed()
	_tick(v, PaladinVisual.STRIKE_DOWN)
	_check(absf(v.p_arm_s - v.strike_arm) < 15.0 and v.p_offset.x > 0.5, "%s: GOLPE desce para frente com peso (%.0f°)" % [tag, v.p_arm_s])
	_tick(v, PaladinVisual.RECOVER_END)
	_check(v._strike_t < 0.0, "%s: volta à guarda" % tag)
	u.target = null
	u.state = CombatUnit.State.IDLE
	# PROVOCA / ESCUDO / BLOQUEIO (eventos reais da habilidade)
	_tick(v, 0.3)
	var push0 := v.p_shield_push
	v.on_ability_event(&"taunt")
	_tick(v, 0.15)
	_check(v.p_shield_push > push0 + 1.5, "%s: PROVOCA bate o escudo à frente" % tag)
	u.paladin.delay = 0.5
	_tick(v, 0.05)
	_check(v.p_guard > 0.2, "%s: na espera do escudo ele já ergue a guarda" % tag)
	u.paladin.delay = -1.0
	u.paladin.shield_t = 1.0
	u.paladin.facing = Vector2(1, 0)
	v.on_ability_event(&"shield")
	_tick(v, 0.25)
	_check(v.p_guard == 1.0 and v.p_crouch > 1.0 and v._barrier_age > 0.2, "%s: ESCUDO ativo: guarda firme + barreira" % tag)
	var arm_guard := v.p_arm_h
	v.on_ability_event(&"block")
	_tick(v, VDT)
	_check(v.p_shield_flash > 0.5 and v.p_arm_h > arm_guard, "%s: BLOQUEIO: o braço cede e o escudo brilha" % tag)
	u.paladin.shield_t = 0.0
	_tick(v, 0.4)
	# HIT
	v.on_hit()
	_tick(v, VDT)
	_check(v.p_flash > 0.2 and v.p_offset.x < -0.5, "%s: HIT recua e clareia" % tag)
	_tick(v, 0.3)
	_check(v.p_flash == 0.0, "%s: HIT curto" % tag)
	_check([u.hp, u.max_hp, u.damage, u.attack_range, u.attack_interval, u.move_speed, u.radius] == snapshot, "%s: visual não altera stats" % tag)
	# MORTE pesada: cai de costas, espada e escudo soltos, fica no chão
	u.die()
	v.on_attack_performed()
	v.on_ability_event(&"taunt")
	_tick(v, 0.35)
	var mid := v.p_rot
	_tick(v, 1.5)
	_check(absf(mid) > 3.0 and v.p_rot < -80.0, "%s: MORTE tomba de costas (%.0f → %.0f)" % [tag, mid, v.p_rot])
	_check(v.p_sword_drop == 1.0 and v.p_shield_drop == 1.0, "%s: espada e escudo caem soltos" % tag)
	var fallen := v.p_rot
	_tick(v, 1.0)
	_check(is_equal_approx(v.p_rot, fallen) and v._strike_t < 0.0 and v._taunt_t < 0.0, "%s: permanece no chão (sem reagir a eventos)" % tag)
	_check(v.pick_rect().size.x > v.pick_rect().size.y, "%s: área clicável deitada" % tag)
	v.queue_free()


func _test_shadow_rule() -> void:
	var live := _make(&"sac_paladin")
	var dead := _make(&"u_sac_paladin")
	_check(not live.shadow and dead.shadow and dead.shadow_style == ShadowStyle.get_default(), "Sombra usa a regra necromântica (ShadowStyle)")
	_check(dead.outline == dead.shadow_style.edge, "contorno da regra")
	_check(dead.ivory.get_luminance() < live.ivory.get_luminance() * 0.5, "armadura convertida para grafite (%.2f → %.2f)" % [live.ivory.get_luminance(), dead.ivory.get_luminance()])
	# dourado preservado: continua quente (vermelho > azul) e próximo do vivo
	var gd := dead.gold
	_check(gd.r - gd.b > 0.3 and gd.h > 0.08 and gd.h < 0.16 and absf(gd.h - live.gold.h) < 0.02, "dourado preservado na Sombra (matiz %.3f × %.3f)" % [gd.h, live.gold.h])
	_check(dead.emblem.b > dead.emblem.g and dead.emblem.r > dead.emblem.g, "sol do escudo vira energia roxa")
	_check(live.pick_rect() == dead.pick_rect() and live.top_y() == dead.top_y(), "mesma silhueta do vivo")
	var war := UnitCatalog.get_def(&"warrior")
	var wv: WarriorVisual = war.visual_script.new()
	wv.setup(CombatUnit.new(3, war.side, war.to_stats(), Vector2.ZERO), war)
	_check(live.pick_rect().size.x > wv.pick_rect().size.x * 1.15 and live.top_y() < wv.top_y(), "maior e mais largo que o Guerreiro")
	_check(live.pick_rect().size.y < wv.pick_rect().size.y * 1.4, "… sem virar chefe")
	wv.free()
	live.queue_free()
	dead.queue_free()


# --- Sandbox: Paladinos no fluxo real -----------------------------------------------------------

func _run_sandbox() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.show_sandbox()
	await process_frame
	var sb: SandboxController = main.current_screen
	var ui := sb.ui
	var live_btn: Button = ui.find_child("Spawn_sac_paladin", true, false)
	var dead_btn: Button = ui.find_child("Spawn_u_sac_paladin", true, false)
	_check(live_btn != null and dead_btn != null, "Sandbox lista Paladino e Paladino Sombra")
	if live_btn == null or dead_btn == null:
		_finish(main)
		return
	for i in 2:
		dead_btn.pressed.emit()
		live_btn.pressed.emit()
	sb.add_unit(UnitCatalog.get_def(&"warrior"), CombatUnit.Team.ENEMY)
	sb.add_unit(UnitCatalog.get_def(&"arc_battlemage"), CombatUnit.Team.ENEMY)
	sb.add_unit(UnitCatalog.get_def(&"u_warrior"), CombatUnit.Team.PLAYER)
	var battle := sb.arena.battle
	_check(battle.sim.units.size() == 7, "vários Paladinos + Guerreiros + Sentinela montados")
	for unit in battle.sim.units:
		var view := battle.view_of(unit)
		var d := UnitCatalog.get_def(unit.def_id)
		var expected: Script = d.visual_script
		if d.visual_scene:
			var probe := d.visual_scene.instantiate()
			expected = probe.get_script()
			probe.free()
		_check(view.visual.get_script() == expected, "%s: visual da UnitDef" % unit.def_id)
	sb.start_combat()
	var taunts := [0]
	battle.sim.paladin_taunted.connect(func(_p: CombatUnit, _f: Array) -> void: taunts[0] += 1)
	var t := 0.0
	while not battle.is_finished() and t < 90.0:
		await process_frame
		t += 1.0 / 60.0
		battle._process(1.0 / 20.0)   # acelera sem mudar o passo fixo
	_check(battle.is_finished() and taunts[0] > 0, "combate real no Sandbox termina, com provocações (%d)" % taunts[0])
	sb.reset_combat()
	_check(battle.sim.units.size() == 7 and not battle.is_running(), "Reiniciar recria a montagem")
	sb.clear_arena()
	_check(battle.sim.units.is_empty(), "Limpar esvazia")
	_finish(main)


func _finish(main: Node) -> void:
	main.queue_free()
	await process_frame
	await process_frame
	print("paladin_test: %s" % ("OK" if _failures == 0 else "%d falha(s)" % _failures))
	quit(1 if _failures > 0 else 0)


## Desfaz as conexões (lambdas que capturam a sim formam ciclo) e descarta a simulação.
func _dispose(sim: CombatSim) -> void:
	for sig in sim.get_signal_list():
		for c in sim.get_signal_connection_list(sig.name):
			sim.disconnect(sig.name, c.callable)
	sim.dispose()


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures += 1
		printerr("  FALHOU: ", what)
