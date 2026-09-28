extends SceneTree
## Teste headless da Sentinela Arcana (viva e Sombra): mecânica portada do HTML e visual.
## Rodar a partir da raiz do projeto:
##   godot --headless -s res://tests/sentinel_test.gd

const DT := CombatSim.STEP

var _failures := 0


func _initialize() -> void:
	_test_defs()
	_test_ranged_attack()
	_test_projectile_retarget_and_expire()
	_test_swords_slow_threat()
	_test_swords_fast_threat()
	_test_swords_out_of_range()
	_test_visuals(&"arc_battlemage")
	_test_visuals(&"u_arc_battlemage")
	print("sentinel_test: %s" % ("OK" if _failures == 0 else "%d falha(s)" % _failures))
	quit(1 if _failures > 0 else 0)


func _stats(id: StringName, overrides := {}) -> Dictionary:
	return UnitCatalog.get_def(id).to_stats(overrides)


## HTML: arc_battlemage (hp 43, dmg 18, range 150, cd 1.25, speed 54, r 13, proj orb, arcaneSwords)
## e u_arc_battlemage gerada por registerFactionUnits (hp = round(43 × 0,94) = 40).
func _test_defs() -> void:
	for id in [&"arc_battlemage", &"u_arc_battlemage"]:
		var d := UnitCatalog.get_def(id)
		_check(d != null, "%s existe no catálogo" % id)
		if d == null:
			continue
		_check(d.damage == 18.0 and d.attack_range == 150.0 and d.attack_interval == 1.25 and d.move_speed == 54.0 and d.radius == 13.0,
			"%s: stats do HTML" % id)
		_check(d.projectile_kind == &"orb" and &"arcane_swords" in d.abilities, "%s: orbe + lâminas" % id)
	_check(UnitCatalog.get_def(&"arc_battlemage").max_hp == 43.0 and UnitCatalog.get_def(&"u_arc_battlemage").max_hp == 40.0, "HP vivo 43 / Sombra 40")
	_check(UnitCatalog.get_def(&"arc_battlemage").side == CombatUnit.Team.ENEMY and UnitCatalog.get_def(&"u_arc_battlemage").side == CombatUnit.Team.PLAYER, "lados")
	_check(UnitCatalog.get_def(&"arc_battlemage").visual_script == SentinelVisual and UnitCatalog.get_def(&"u_arc_battlemage").visual_script == SentinelShadowVisual, "visuais dedicados")


func _test_ranged_attack() -> void:
	var sim := CombatSim.new(1)
	var s := sim.add_unit(CombatUnit.Team.PLAYER, _stats(&"u_arc_battlemage"), Vector2(200, 380))
	var dummy := sim.add_unit(CombatUnit.Team.ENEMY, _stats(&"warrior", {speed = 0.0, hp = 9999.0}), Vector2(700, 380))
	var fired: Array[CombatProjectile] = []
	var performed := [0]
	var hits: Array[float] = []
	var hp_at_fire := [0.0]
	sim.attack_performed.connect(func(a: CombatUnit, _t: CombatUnit) -> void:
		if a == s:
			performed[0] += 1
			hp_at_fire[0] = dummy.hp)
	sim.projectile_fired.connect(func(p: CombatProjectile) -> void: fired.append(p))
	sim.unit_attacked.connect(func(a: CombatUnit, _t: CombatUnit, amount: float) -> void:
		if a == s: hits.append(amount))
	while performed[0] == 0 and sim.time < 20.0:
		sim.step(DT)
	var dist := s.position.distance_to(dummy.position)
	_check(dist <= 150.0 and dist >= 150.0 * 0.92 - 1.0, "à distância: para em ~0,92 × alcance (%.1f)" % dist)
	_check(s.state == CombatUnit.State.ATTACKING, "ataca parada")
	_check(fired.size() == 1 and fired[0].kind == &"orb" and not fired[0].is_sword(), "ataque básico dispara um orbe")
	_check(hits.is_empty() and dummy.hp == hp_at_fire[0], "dano NÃO é aplicado no disparo")
	_check(is_equal_approx(fired[0].speed, 340.0), "orbe a 340 px/s (HTML)")
	while hits.is_empty() and sim.time < 20.0:
		sim.step(DT)
	_check(hits.size() == 1 and is_equal_approx(hits[0], 18.0), "orbe acerta e aplica 18 de dano")
	_check(sim.projectiles.is_empty(), "orbe some ao acertar")
	var t0 := sim.time
	while performed[0] < 2 and sim.time < t0 + 3.0:
		sim.step(DT)
	_check(performed[0] == 2, "segundo disparo depois da recarga")
	_dispose(sim)


## Alvo morre em voo: o orbe segue reto e acerta outro inimigo no caminho (HTML).
func _test_projectile_retarget_and_expire() -> void:
	var sim := CombatSim.new(1)
	var s := sim.add_unit(CombatUnit.Team.PLAYER, _stats(&"arc_battlemage"), Vector2(300, 380))
	var a := sim.add_unit(CombatUnit.Team.ENEMY, _stats(&"warrior", {speed = 0.0}), Vector2(420, 380))
	var b := sim.add_unit(CombatUnit.Team.ENEMY, _stats(&"warrior", {speed = 0.0, hp = 999.0}), Vector2(480, 380))
	var p := sim._fire(&"orb", s, a, 10.0)
	a.take_damage(a.max_hp)   # morre antes do impacto
	var ended := [null, false]
	sim.projectile_ended.connect(func(_p: CombatProjectile, v: CombatUnit) -> void:
		ended[0] = v
		ended[1] = true)
	var hp_b := b.hp
	for i in 240:
		sim.units.erase(s)   # sem novos disparos
		sim._update_projectiles(DT)
		if ended[1]:
			break
	_check(ended[0] == b and b.hp == hp_b - 10.0, "com o alvo morto, o orbe acerta quem estiver no caminho")
	# sem ninguém no caminho: expira
	var p2 := sim._fire(&"orb", s, b, 5.0)
	b.take_damage(9999.0)
	ended[1] = false
	for i in 400:
		sim._update_projectiles(DT)
		if ended[1]:
			break
	_check(ended[1] and ended[0] == null, "orbe sem alvo expira (vida %.2f)" % p2.life)
	_dispose(sim)


## Inimigo parado a 100: reação lenta (0,55 s), 0,10 s de antecipação, uma lâmina de cada vez
## (0,35 s entre elas), dano = ataque básico, recarga de 10 s.
func _test_swords_slow_threat() -> void:
	var sim := CombatSim.new(1)
	var s := sim.add_unit(CombatUnit.Team.PLAYER, _stats(&"u_arc_battlemage", {range = 1.0, speed = 0.0}), Vector2(400, 380))
	s.cooldown = 999.0
	var e := sim.add_unit(CombatUnit.Team.ENEMY, _stats(&"warrior", {speed = 0.0, hp = 9999.0, range = 1.0}), Vector2(500, 380))
	var launches: Array = []
	var saw_windup := [false]
	var dmg: Array[float] = []
	sim.projectile_fired.connect(func(p: CombatProjectile) -> void:
		if p.is_sword():
			launches.append([sim.time, p.sword_index, p.position, p.speed]))
	sim.unit_attacked.connect(func(_a: CombatUnit, _t: CombatUnit, amount: float) -> void: dmg.append(amount))
	while sim.time < 12.5:
		s.cooldown = 999.0   # isola a habilidade do ataque básico
		sim.step(DT)
		if s.swords.blades[0].windup > 0.0 or s.swords.blades[1].windup > 0.0:
			saw_windup[0] = true
	_check(launches.size() >= 2, "duas lâminas disparam")
	if launches.size() < 2:
		_dispose(sim)
		return
	_check(absf(launches[0][0] - 0.55) < 0.03, "reação lenta ≈ 0,55 s (%.3f)" % launches[0][0])
	_check(saw_windup[0], "antecipação (windup) antes de partir")
	_check(launches[0][1] == 0 and launches[1][1] == 1, "lâmina 0 e depois lâmina 1")
	var gap: float = launches[1][0] - launches[0][0]
	_check(gap >= 0.35 and gap < 0.95, "uma de cada vez (intervalo %.2f s)" % gap)
	_check((launches[0][2] as Vector2).distance_to(SentinelSwords.anchor(s, 0)) < 0.01, "lâmina parte da âncora (HTML: swordAnchor)")
	_check(is_equal_approx(launches[0][3], 520.0), "lâmina a 520 px/s")
	_check(dmg.size() >= 2 and is_equal_approx(dmg[0], 18.0), "dano da lâmina = ataque básico")
	_check(launches.size() >= 3 and absf(launches[2][0] - launches[0][0] - 10.0) < 0.8, "lâmina volta depois de 10 s")
	_dispose(sim)


## Inimigo avançando rápido. Fiel ao HTML: no quadro em que a ameaça ENTRA nos 115 a
## aproximação medida é 0 (anterior = distância atual), então a 1ª lâmina usa a reação lenta
## (0,55 s); a partir da 2ª a aproximação já é conhecida e a reação cai para ≈ 0,08 s.
func _test_swords_fast_threat() -> void:
	var sim := CombatSim.new(1)
	var s := sim.add_unit(CombatUnit.Team.PLAYER, _stats(&"arc_battlemage", {range = 1.0, speed = 0.0}), Vector2(300, 380))
	var e := sim.add_unit(CombatUnit.Team.ENEMY, _stats(&"warrior", {speed = 90.0, hp = 9999.0, range = 1.0}), Vector2(600, 380))
	var entered := [-1.0]
	var launches: Array[float] = []
	sim.projectile_fired.connect(func(p: CombatProjectile) -> void:
		if p.is_sword(): launches.append(sim.time))
	while sim.time < 6.0 and launches.size() < 2:
		s.cooldown = 999.0
		sim.step(DT)
		if entered[0] < 0.0 and s.position.distance_to(e.position) <= SentinelSwords.TRIGGER_RANGE:
			entered[0] = sim.time
	_check(launches.size() == 2, "avanço agressivo: duas lâminas")
	if launches.size() == 2:
		var first: float = launches[0] - entered[0]
		var second: float = launches[1] - launches[0]
		_check(absf(first - 0.55) < 0.03, "1ª lâmina: reação da entrada, como no HTML (%.3f s)" % first)
		_check(second < 0.35 + 0.08 + 0.05, "2ª lâmina: reação rápida após o intervalo (%.3f s)" % second)
	_dispose(sim)


func _test_swords_out_of_range() -> void:
	var sim := CombatSim.new(1)
	var s := sim.add_unit(CombatUnit.Team.PLAYER, _stats(&"arc_battlemage", {range = 1.0, speed = 0.0}), Vector2(300, 380))
	sim.add_unit(CombatUnit.Team.ENEMY, _stats(&"warrior", {speed = 0.0, range = 1.0}), Vector2(300 + 130, 380))
	var n := [0]
	sim.projectile_fired.connect(func(p: CombatProjectile) -> void: n[0] += 1)
	for i in 600:
		s.cooldown = 999.0
		sim.step(DT)
	_check(n[0] == 0, "sem ameaça a menos de 115, as lâminas não disparam")
	_dispose(sim)


func _test_visuals(id: StringName) -> void:
	var def := UnitCatalog.get_def(id)
	var foe := CombatUnit.new(90, CombatUnit.Team.ENEMY if def.side == CombatUnit.Team.PLAYER else CombatUnit.Team.PLAYER,
		_stats(&"warrior"), Vector2(600, 380))
	var u := CombatUnit.new(1, def.side, def.to_stats(), Vector2(400, 380))
	u.target = foe
	var v: SentinelVisual = def.visual_script.new()
	v.setup(u, def)
	root.add_child(v)
	var tag := String(id)
	var before := [u.hp, u.damage, u.attack_range, u.attack_interval, u.move_speed, u.cooldown, u.position]
	_tick(v, 0.5)
	_check(v._facing > 0.0, "%s: olha para o alvo" % tag)
	var a0 := v._blade_anchor(0)
	_tick(v, 0.3)
	_check(v._blade_anchor(0) != a0, "%s: IDLE — lâminas flutuam" % tag)
	# movimento: desliza e inclina; lâminas ficam para trás
	u.state = CombatUnit.State.MOVING
	for i in 20:
		u.position.x += 1.0
		v.update_visual(1.0 / 60.0)
	_check(v._walk_w > 0.8 and v.p_lean > 3.0 and v._sword_lag.x < -0.5, "%s: MOVIMENTO inclina e as lâminas atrasam" % tag)
	u.state = CombatUnit.State.ATTACKING
	# preparação pela recarga real
	u.cooldown = 0.02
	_tick(v, 0.2)
	_check(v.p_charge > 0.8 and absf(v.p_arm - SentinelVisual.WINDUP_ARM) < 3.0, "%s: PREPARA junta energia na mão" % tag)
	var muzzle := v.muzzle_point(CombatProjectile.new(1, &"orb", u, foe, 1.0))
	_check(muzzle.x > 5.0, "%s: orbe sai da mão, do lado do alvo (%.1f)" % [tag, muzzle.x])
	u.cooldown = u.attack_interval
	v.on_attack_performed()
	_tick(v, SentinelVisual.CAST_TIME)
	_check(absf(v.p_arm - v._cast_arm) < 6.0 and v.p_open > 0.5 and v._sword_kick > 0.0, "%s: DISPARO — braço aponta, manto abre, lâminas reagem" % tag)
	_tick(v, SentinelVisual.RECOVER_TIME + 0.1)
	_check(v._cast_t < 0.0 and v.p_charge == 0.0, "%s: retorno ao repouso" % tag)
	# habilidade: antecipação lida do estado real da lâmina, partida e recarga
	var rest := v._blade_anchor(1)
	u.swords.blades[1].windup = 0.05
	_tick(v, 1.0 / 60.0)
	_check(v._blade_windup(1) > 0.0 and v._blade_anchor(1).distance_to(rest) > 2.0 and v.p_gem > 0.6, "%s: LÂMINA recua, joia acende" % tag)
	u.swords.blades[1].windup = 0.0
	u.swords.blades[1].cooldown = SentinelSwords.COOLDOWN
	var sword := CombatProjectile.new(2, &"arcanesword", u, foe, 1.0)
	sword.sword_index = 1
	var sword_muzzle := v.muzzle_point(sword)
	v.on_projectile_fired(sword)
	_check(v._launch_t[1] == 0.0 and sword_muzzle.distance_to(v._blade_anchor(1)) < 3.0, "%s: lâmina parte de onde pairava" % tag)
	_tick(v, 0.5)
	_check(not v._blade_ready(1), "%s: lâmina em recarga (vulto)" % tag)
	u.swords.blades[1].cooldown = 0.0
	_tick(v, 1.0 / 60.0)
	_check(v._reform_t[1] >= 0.0, "%s: lâmina volta com clarão" % tag)
	# HIT
	v.on_hit()
	_tick(v, 1.0 / 60.0)
	_check(v.p_flash > 0.2 and v._sword_shake > 0.5 and v.p_offset.x < -0.5, "%s: HIT recua, clareia e desestabiliza as lâminas" % tag)
	_tick(v, 0.5)
	_check(v.p_flash == 0.0, "%s: HIT curto" % tag)
	var after := [u.hp, u.damage, u.attack_range, u.attack_interval, u.move_speed]
	_check(after == [before[0], before[1], before[2], before[3], before[4]], "%s: visual não altera stats" % tag)
	# morte
	u.die()
	_tick(v, 0.05)
	_check(v._death_blades.size() == 2, "%s: as duas lâminas pairando entram na morte" % tag)
	_tick(v, v.death_time + 1.5)
	_check(v.p_scale.y < 0.45 and v.p_hat_fall > 0.99, "%s: manto colapsa e o chapéu cai" % tag)
	var final_scale := v.p_scale
	_tick(v, 1.0)
	_check(v.p_scale.distance_to(final_scale) < 0.001 and v.p_hat_fall > 0.99, "%s: permanece no chão" % tag)
	if id == &"u_arc_battlemage":
		_check(v.p_alpha < 0.7, "%s: a Sombra fica translúcida ao se desfazer" % tag)
	_check(v.pick_rect().size.x > v.pick_rect().size.y, "%s: área clicável deitada" % tag)
	v.free()


## Lambdas que capturam `sim` ligadas aos sinais do próprio `sim` formam ciclo: desliga antes.
func _dispose(sim: CombatSim) -> void:
	for sig in sim.get_signal_list():
		for c in sim.get_signal_connection_list(sig.name):
			sim.disconnect(sig.name, c.callable)
	sim.dispose()


func _tick(v: SentinelVisual, seconds: float) -> void:
	for i in maxi(1, int(round(seconds * 60.0))):
		v.update_visual(1.0 / 60.0)


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures += 1
		printerr("  FALHOU: ", what)
