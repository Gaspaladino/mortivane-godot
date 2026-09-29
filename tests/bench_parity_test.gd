extends SceneTree
## A BenchCombatSim (só benchmark) em modo FULL reproduz EXATAMENTE a CombatSim do jogo:
## mesmas posições, HP, estados, alvos e projéteis a cada segundo de uma luta mista (Guerreiro,
## Sentinela com lâminas, Paladino com provocação/escudo). Também garante que a Battle usa a
## CombatSim de verdade quando ninguém pede outra coisa.

var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_parity(&"mixed", 12, 12)
	_test_parity(&"mixed", 40, 40)
	_test_parity(&"mixed", 40, 3)
	_test_counters()
	await _test_battle_default()
	print("bench_parity_test: %s" % ("OK" if _failures == 0 else "%d falha(s)" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("  FALHOU: " + msg)


static func build(sim: CombatSim, allies: int, enemies: int) -> void:
	var ids := [&"warrior", &"arc_battlemage", &"sac_paladin"]
	for side in 2:
		var team := CombatUnit.Team.PLAYER if side == 0 else CombatUnit.Team.ENEMY
		for i in (allies if side == 0 else enemies):
			var def := UnitCatalog.get_def(ids[i % ids.size()])
			sim.add_unit(team, def.to_stats(), SandboxController.slot_position(team, i))


func _snapshot(sim: CombatSim) -> Array:
	var out := []
	for u in sim.units:
		out.append([u.id, u.position, u.hp, u.state, u.target.id if u.target else -1, u.cooldown, u.taunt_t])
	for p in sim.projectiles:
		out.append([p.id, p.position, p.life])
	return out


func _test_parity(_profile: StringName, allies: int, enemies: int) -> void:
	var real := CombatSim.new(97)
	BenchCombatSim.next_mode = BenchCombatSim.Mode.FULL
	var bench := BenchCombatSim.new(97)
	build(real, allies, enemies)
	build(bench, allies, enemies)
	var same := true
	var steps := 0
	for second in 40:
		for k in 120:
			real.step(CombatSim.STEP)
			bench.step(CombatSim.STEP)
			steps += 1
		if _snapshot(real) != _snapshot(bench):
			same = false
			print("    divergiu em t=%ds" % (second + 1))
			break
	_check(same, "%d×%d misto: BenchCombatSim FULL == CombatSim por 40 s" % [allies, enemies])
	_check(bench.steps == steps and bench.nearest_calls > 0, "%d×%d: contadores andaram" % [allies, enemies])
	real.dispose()
	bench.dispose()


## Sem ataques no TARGET_ONLY e sem alvo no MOVE_ONLY; nearest_foe varre N unidades por chamada.
func _test_counters() -> void:
	BenchCombatSim.next_mode = BenchCombatSim.Mode.TARGET_ONLY
	var t := BenchCombatSim.new(1)
	build(t, 10, 10)
	for k in 600:
		t.step(CombatSim.STEP)
	_check(t.attacks == 0 and t.damage_events == 0, "TARGET_ONLY não ataca")
	_check(t.examined == t.nearest_calls * 20, "nearest_foe olha as 20 unidades a cada chamada (%d / %d)" % [t.examined, t.nearest_calls])
	BenchCombatSim.next_mode = BenchCombatSim.Mode.MOVE_ONLY
	var m := BenchCombatSim.new(1)
	build(m, 10, 10)
	for k in 600:
		m.step(CombatSim.STEP)
	_check(m.nearest_calls == 0 and m.moves > 0, "MOVE_ONLY anda sem procurar alvo")
	BenchCombatSim.next_mode = BenchCombatSim.Mode.FULL
	t.dispose()
	m.dispose()


func _test_battle_default() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/combat/battle.gd")
	_check(src.contains("sim_script.new(rng_seed) if sim_script else CombatSim.new(rng_seed)"), "Battle cria CombatSim quando sim_script é null")
	var arena: Node = load("res://scenes/arena/arena.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	var battle: Battle = arena.get_node("Battle")
	_check(battle.sim_script == null and battle.sim.get_script() == CombatSim, "a Battle do jogo usa a CombatSim real")
	arena.queue_free()
	await process_frame
