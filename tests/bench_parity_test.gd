extends SceneTree
## PARIDADE das otimizações de combate.
##
## A mesma luta roda na CombatSim do jogo (otimizada) e na ReferenceCombatSim (cópia congelada da
## CombatSim de antes das otimizações); nos casos pequenos também na BenchCombatSim (instrumentada).
## Exige IDÊNTICO:
##   - a cada 0,25 s: posição, HP, estado, alvo, recarga e provocação de toda unidade; projéteis;
##   - a sequência inteira de eventos: ataques, dano (valor), mortes, provocações, escudo, bloqueios,
##     disparos e fim de projéteis;
##   - vencedor, sobreviventes e instante do fim.
## Composições: Guerreiros, Sentinelas, Paladinos, sombras e mistas; 1×1 até 50×50; 40×2, 2×40.
## Também garante que a Battle do jogo usa a CombatSim quando ninguém pede outra coisa.

## Teto por luta; a comparação para 1 s depois do fim (sem projéteis no ar).
const SECONDS := 70.0
var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var comps := {
		warriors = [&"warrior"], sentinels = [&"arc_battlemage"], paladins = [&"sac_paladin"],
		mixed = [&"warrior", &"arc_battlemage"], all = [&"warrior", &"arc_battlemage", &"sac_paladin"],
		shadows = [&"u_warrior", &"u_arc_battlemage", &"u_sac_paladin"],
	}
	var sizes := [[1, 1], [3, 3], [12, 12], [40, 40], [40, 2], [2, 40]]
	var cases := 0
	for name in comps:
		var list: Array = sizes + ([[40, 20], [20, 40], [50, 50]] if name == "mixed" else [])
		for sz in list:
			_test_parity(comps[name], sz[0], sz[1], 97 + cases, name)
			cases += 1
	_test_parity([&"u_warrior", &"sac_paladin"], 40, 40, 5, "sombras×paladinos")
	_test_counters()
	_test_corpses_not_scanned()
	await _test_battle_default()
	print("bench_parity_test: %s (%d lutas comparadas)" % ["OK" if _failures == 0 else "%d falha(s)" % _failures, cases + 1])
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("  FALHOU: " + msg)


## Aliados usam a composição a partir do 1º tipo; inimigos, a partir do 2º (lados diferentes).
static func build(sim: CombatSim, defs: Array, allies: int, enemies: int) -> void:
	for side in 2:
		var team := CombatUnit.Team.PLAYER if side == 0 else CombatUnit.Team.ENEMY
		for i in (allies if side == 0 else enemies):
			var def := UnitCatalog.get_def(defs[(i + side) % defs.size()])
			sim.add_unit(team, def.to_stats(), SandboxController.slot_position(team, i))


static func record(sim: CombatSim, log: Array) -> void:
	sim.attack_performed.connect(func(a: CombatUnit, t: CombatUnit) -> void: log.append(["atk", sim.time, a.id, t.id]))
	sim.unit_attacked.connect(func(a: CombatUnit, t: CombatUnit, amt: float) -> void: log.append(["dmg", sim.time, a.id if a else -1, t.id, amt]))
	sim.unit_died.connect(func(u: CombatUnit) -> void: log.append(["die", sim.time, u.id]))
	sim.paladin_taunted.connect(func(u: CombatUnit, foes: Array) -> void: log.append(["taunt", sim.time, u.id, foes.map(func(f): return f.id)]))
	sim.paladin_shield_raised.connect(func(u: CombatUnit) -> void: log.append(["shield", sim.time, u.id]))
	sim.paladin_shield_blocked.connect(func(u: CombatUnit, p: float) -> void: log.append(["block", sim.time, u.id, p]))
	sim.projectile_fired.connect(func(p: CombatProjectile) -> void: log.append(["fire", sim.time, p.id, p.owner.id, p.target.id]))
	sim.projectile_ended.connect(func(p: CombatProjectile, v: CombatUnit) -> void: log.append(["end", sim.time, p.id, v.id if v else -1]))


static func snapshot(sim: CombatSim) -> Array:
	var out := []
	for u in sim.units:
		out.append([u.id, u.position, u.hp, u.state, u.target.id if u.target else -1, u.cooldown, u.taunt_t,
			u.taunted_by.id if u.taunted_by else -1])
	for p in sim.projectiles:
		out.append([p.id, p.position, p.life])
	return out


func _test_parity(defs: Array, allies: int, enemies: int, seed_value: int, label: String) -> void:
	var t_start := Time.get_ticks_msec()
	BenchCombatSim.next_mode = BenchCombatSim.Mode.FULL
	var sims: Array[CombatSim] = [ReferenceCombatSim.new(seed_value), CombatSim.new(seed_value)]
	# a BenchCombatSim só envolve a CombatSim (super + cronômetros): basta conferi-la nos casos pequenos
	if allies + enemies <= 24:
		sims.append(BenchCombatSim.new(seed_value))
	var n := sims.size()
	var logs := []
	var end_t := []
	for i in n:
		logs.append([])
		end_t.append(-1.0)
		build(sims[i], defs, allies, enemies)
		record(sims[i], logs[i])
	var same := true
	var where := ""
	for k in int(SECONDS * 4):
		for s in 30:
			for i in n:
				sims[i].step(CombatSim.STEP)
				if end_t[i] < 0.0 and sims[i].is_finished():
					end_t[i] = sims[i].time
		var ref := snapshot(sims[0])
		for i in range(1, n):
			if snapshot(sims[i]) != ref:
				same = false
				where = "estado em t=%.2f s (%s)" % [sims[0].time, sims[i].get_script().get_global_name()]
		if not same:
			break
		var all_done := true
		for i in n:
			if end_t[i] < 0.0 or not sims[i].projectiles.is_empty():
				all_done = false
		if all_done and sims[0].time > end_t[0] + 1.0:
			break
	if same:
		for i in range(1, n):
			if logs[i] != logs[0]:
				same = false
				where = "eventos (%d × %d)" % [logs[i].size(), logs[0].size()]
			elif end_t[i] != end_t[0] or sims[i].alive_count(CombatUnit.Team.PLAYER) != sims[0].alive_count(CombatUnit.Team.PLAYER) \
					or sims[i].alive_count(CombatUnit.Team.ENEMY) != sims[0].alive_count(CombatUnit.Team.ENEMY):
				same = false
				where = "fim/vencedor"
	print("  %s %d×%d: %s (%.1f s de luta, %d eventos, %d ms)" % [label, allies, enemies, "idêntico" if same else "DIVERGIU",
		sims[0].time, logs[0].size(), Time.get_ticks_msec() - t_start])
	_check(same, "%s %d×%d: idêntico à referência — divergiu em %s" % [label, allies, enemies, where])
	for x in sims:
		x.dispose()


## Etapa 1: 40 vivos × 0 inimigos vivos + 40 cadáveres ⇒ a busca de alvo não examina ninguém.
func _test_corpses_not_scanned() -> void:
	var sim := CombatSim.new(3)
	build(sim, [&"warrior"], 40, 40)
	var killer: CombatUnit = sim.units[0]
	for u in sim.units:
		if u.team == CombatUnit.Team.ENEMY:
			sim._apply_damage(killer, u, u.hp)
	var c0 := sim.stat_candidates
	var s0 := sim.stat_target_scans
	for k in 240:
		sim.step(CombatSim.STEP)
	_check(sim.stat_candidates == c0 and sim.stat_target_scans == s0,
		"40 vivos × 40 cadáveres: 0 candidatos examinados (%d) e 0 varreduras (%d) em 2 s" % [sim.stat_candidates - c0, sim.stat_target_scans - s0])
	_check(sim.alive_count(CombatUnit.Team.ENEMY) == 0 and sim.alive_count(CombatUnit.Team.PLAYER) == 40, "contagem de vivos")
	# morte feita por fora da simulação (take_damage direto) também sai da busca
	var sim2 := CombatSim.new(3)
	build(sim2, [&"warrior"], 2, 2)
	var victim: CombatUnit = sim2.units[2]
	victim.take_damage(victim.hp)
	sim2.step(CombatSim.STEP)
	sim2.step(CombatSim.STEP)
	_check(sim2.units[0].target != victim and sim2.units[1].target != victim, "morto por fora não vira alvo")
	sim.dispose()
	sim2.dispose()


## Contadores do benchmark: TARGET_ONLY não ataca, MOVE_ONLY não procura alvo.
func _test_counters() -> void:
	BenchCombatSim.next_mode = BenchCombatSim.Mode.TARGET_ONLY
	var t := BenchCombatSim.new(1)
	build(t, [&"warrior"], 10, 10)
	for k in 600:
		t.step(CombatSim.STEP)
	_check(t.attacks == 0 and t.damage_events == 0, "TARGET_ONLY não ataca")
	_check(t.stat_target_queries > 0, "TARGET_ONLY procura alvo")
	BenchCombatSim.next_mode = BenchCombatSim.Mode.MOVE_ONLY
	var m := BenchCombatSim.new(1)
	build(m, [&"warrior"], 10, 10)
	for k in 600:
		m.step(CombatSim.STEP)
	_check(m.stat_target_queries == 0, "MOVE_ONLY anda sem procurar alvo")
	BenchCombatSim.next_mode = BenchCombatSim.Mode.FULL
	t.dispose()
	m.dispose()


func _test_battle_default() -> void:
	var arena: Node = load("res://scenes/arena/arena.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	var battle: Battle = arena.get_node("Battle")
	_check(battle.sim_script == null and battle.sim.get_script() == CombatSim, "a Battle do jogo usa a CombatSim real")
	arena.queue_free()
	await process_frame
