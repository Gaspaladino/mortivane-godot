extends SceneTree
## Teste headless do Paladino Vivo em rig 2.5D (PaladinRigVisual) — ALTERNATIVA fora de uso (o visual
## padrão é o PaladinLiveVisual, testado em paladin_live_test). O visual só OBSERVA a simulação.
##   - stats, provocação, escudo e o resultado do combate são idênticos com e sem o visual;
##   - animações não aplicam dano, bloqueio visual não reduz dano, empurrão visual não desloca,
##     morte visual não mata; direção/giro não mudam gameplay;
##   - espada SEMPRE na mão direita e escudo SEMPRE no braço esquerdo, em todas as direções e
##     estados, sem arma extra; as direções da esquerda são giros de verdade (sem espelho);
##   - cada estado vem do estado real (idle, walk, ataque sincronizado, taunt → guarda → escudo,
##     bloqueio, hit, push, morte → cadáver);
##   - Sandbox: prévias só visuais, Reiniciar/Limpar recriam, sair não deixa nós nem vazamentos.
##   godot --headless -s res://tests/paladin_rig_test.gd

const VDT := 1.0 / 60.0
const D := PaladinPoseLibrary.Dir

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_def_and_stats()
	_test_model_semantics()
	await _test_equipment_every_direction_and_state()
	await _test_directions()
	await _test_states_from_sim()
	await _test_visual_never_writes_unit()
	await _test_performance_budget()
	print("paladin_rig_test: %s" % ("OK" if _failures == 0 else "%d falha(s)" % _failures))
	quit(1 if _failures > 0 else 0)


# --- Definição e stats -----------------------------------------------------------------------

func _test_def_and_stats() -> void:
	var def := UnitCatalog.get_def(&"sac_paladin")
	_check(load(RIG_SCENE) is PackedScene, "cena do rig 2.5D continua disponível como alternativa")
	var shadow := UnitCatalog.get_def(&"u_sac_paladin")
	_check(shadow.visual_scene == null and shadow.visual_script == ShadowPaladinVisual, "Paladino Sombra continua no visual anterior")
	_check(def.max_hp == 120.0 and def.damage == 13.0 and def.attack_range == 34.0 and def.attack_interval == 1.2 and def.move_speed == 44.0 and def.radius == 14.0,
		"stats do Paladino inalterados")
	_check(def.abilities == [&"paladin_taunt_shield"], "habilidade inalterada")
	_check(PaladinTaunt.TAUNT_RADIUS == 115.0 and PaladinTaunt.TAUNT_DURATION == 2.5 and PaladinTaunt.SHIELD_DELAY == 1.0
		and PaladinTaunt.SHIELD_DURATION == 1.5 and PaladinTaunt.SHIELD_DAMAGE_REDUCTION == 0.75 and PaladinTaunt.COOLDOWN == 15.0,
		"provocação e Escudo Sagrado inalterados (raio, duração, espera, redução, recarga)")
	var look: PaladinRigLook = load("res://data/visuals/paladin_rig_look.tres")
	_check(look != null and look is PaladinRigLook, "parâmetros do Inspector em data/visuals/paladin_rig_look.tres")


## Uma espada (lâmina, guarda, punho, pomo) e um escudo, presos aos encaixes certos.
func _test_model_semantics() -> void:
	var sword := PaladinModel.parts_of_kind(&"sword")
	var shield := PaladinModel.parts_of_kind(&"shield")
	_check(sword.size() == 4 and sword.all(func(p) -> bool: return p.bone == &"sword"), "uma espada só (4 peças no encaixe da espada)")
	_check(shield.size() == 1 and shield[0].bone == &"shield", "um escudo só")
	_check(PaladinModel.SWORD_CHAIN.has(&"r_hand") and not PaladinModel.SWORD_CHAIN.has(&"l_hand"), "espada pende da mão DIREITA")
	_check(PaladinModel.SHIELD_CHAIN.has(&"l_hand") and not PaladinModel.SHIELD_CHAIN.has(&"r_hand"), "escudo pende do braço ESQUERDO")
	_check(PaladinModel.RIGHT < 0.0 and PaladinModel.LEFT > 0.0, "lado direito = x negativo no espaço do corpo")


# --- Regra do equipamento em todas as direções e estados --------------------------------------

const RIG_SCENE := "res://scenes/units/paladin_rig_visual.tscn"


## Paladino Vivo com o rig 2.5D escolhido (cópia da UnitDef; o catálogo não muda).
func _rig_def() -> UnitDef:
	var def: UnitDef = UnitCatalog.get_def(&"sac_paladin").duplicate()
	def.visual_scene = load(RIG_SCENE)
	def.visual_script = PaladinRigVisual
	return def


func _make(team := CombatUnit.Team.PLAYER, pos := Vector2(400, 380)) -> UnitView:
	var def := _rig_def()
	var u := CombatUnit.new(1, team, def.to_stats(), pos)
	var view := UnitView.new(u, def)
	root.add_child(view)
	view.process_mode = Node.PROCESS_MODE_DISABLED   # o teste dirige o visual quadro a quadro
	return view


func _tick(v: PaladinRigVisual, seconds: float, move := Vector2.ZERO) -> void:
	for i in int(round(seconds / VDT)):
		v.unit.position += move * VDT
		v.update_visual(VDT)


func _fist(rig: PaladinRig, hand: StringName) -> Vector3:
	return rig.bone(hand) * Vector3(0, -2.4, 0)


func _test_equipment_every_direction_and_state() -> void:
	var view := _make()
	await process_frame
	var v := view.visual as PaladinRigVisual
	var states := [[&"idle", 0.6], [&"walk", 0.4], [&"attack", 0.2], [&"attack", 0.36], [&"attack", 0.5], [&"hit", 0.06],
		[&"push", 0.15], [&"taunt", 0.45], [&"shield", 0.6], [&"block", 0.06], [&"death", 0.3]]
	var worst_sword := 0.0
	var worst_shield := 0.0
	var sides_ok := true
	var flips := 0
	for d in 8:
		for st in states:
			v.preview(st[0], d)
			_tick(v, st[1])
			var rig := v.rig
			var sw := rig.bone(&"sword").origin
			var sh := rig.bone(&"shield").origin
			worst_sword = maxf(worst_sword, sw.distance_to(_fist(rig, &"r_hand")))
			worst_shield = maxf(worst_shield, sh.distance_to(_fist(rig, &"l_hand")))
			# a espada fica mais perto da mão direita que da esquerda; o escudo, o contrário
			if sw.distance_to(_fist(rig, &"r_hand")) >= sw.distance_to(_fist(rig, &"l_hand")):
				sides_ok = false
			if sh.distance_to(_fist(rig, &"l_hand")) >= sh.distance_to(_fist(rig, &"r_hand")):
				sides_ok = false
			# o ombro direito continua do lado direito do tronco (no espaço do tronco)
			var torso := rig.bone(&"torso")
			if (torso.affine_inverse() * rig.bone(&"r_upper").origin).x >= 0.0 or (torso.affine_inverse() * rig.bone(&"l_upper").origin).x <= 0.0:
				sides_ok = false
			if rig.scale.x < 0.0 or v.scale.x < 0.0 or view.scale.x < 0.0:
				flips += 1
	_check(worst_sword < 1.0, "espada presa ao punho DIREITO em todas as direções e estados (desvio máx. %.2f)" % worst_sword)
	_check(worst_shield < 2.0 + 0.5, "escudo preso ao punho ESQUERDO em todas as direções e estados (desvio máx. %.2f)" % worst_shield)
	_check(sides_ok, "espada sempre mais perto da mão direita, escudo da esquerda; ombros nos lados certos")
	_check(flips == 0, "nenhuma direção usa espelho (flip): as da esquerda são giros de verdade")
	# na morte a arma e o escudo se SOLTAM (e continuam sendo uma espada e um escudo)
	v.preview(&"death", D.RIGHT)
	_tick(v, 2.2)
	_check(v.rig.overrides.has(&"sword") and v.rig.overrides.has(&"shield"), "na queda a espada e o escudo se soltam")
	_check(v.rig.bone(&"sword").origin.y < 3.0 and v.rig.bone(&"shield").origin.y < 3.0, "espada e escudo terminam no chão ao lado do corpo")
	view.queue_free()
	await process_frame


# --- Direções ---------------------------------------------------------------------------------

func _test_directions() -> void:
	var yaws := {}
	for d in 8:
		yaws[d] = PaladinPoseLibrary.dir_yaw(d, 1.0)
	_check(is_equal_approx(yaws[D.LEFT], -yaws[D.RIGHT]) and is_equal_approx(yaws[D.UP_LEFT], -yaws[D.UP_RIGHT]) and is_equal_approx(yaws[D.DOWN_LEFT], -yaws[D.DOWN_RIGHT]),
		"esquerda = mesmo giro para o outro lado")
	_check(yaws[D.DOWN] < yaws[D.DOWN_RIGHT] and yaws[D.DOWN_RIGHT] < yaws[D.RIGHT] and yaws[D.RIGHT] < yaws[D.UP_RIGHT] and yaws[D.UP_RIGHT] < yaws[D.UP],
		"DOWN → DOWN_RIGHT → RIGHT → UP_RIGHT → UP giram em ordem (cada uma com leitura própria)")
	_check(PaladinPoseLibrary.attack_variant(D.RIGHT) != PaladinPoseLibrary.attack_variant(D.UP_RIGHT)
		and PaladinPoseLibrary.attack_variant(D.RIGHT) != PaladinPoseLibrary.attack_variant(D.DOWN_RIGHT), "ataques diagonais não são o ataque lateral")
	# movimento real em 8 direções → direção do corpo (cabeça e tronco giram com ela)
	var view := _make()
	await process_frame
	var v := view.visual as PaladinRigVisual
	var ok := true
	for d in 8:
		var a := d * PI / 4.0
		var move := Vector2(sin(a), cos(a)) * v.unit.move_speed
		v.unit.state = CombatUnit.State.MOVING
		_tick(v, 0.8, move)
		if v.animator.dir != d:
			ok = false
			printerr("   direção %d → %d" % [d, v.animator.dir])
		if absf(wrapf(v.animator.yaw - PaladinPoseLibrary.dir_yaw(d, v.animator.lateral), -PI, PI)) > 0.05:
			ok = false
	_check(ok, "andar em cada uma das 8 direções vira o corpo para ela")
	# a cabeça e o tronco acompanham o corpo (não ficam olhando para a câmera)
	var head_fwd: Vector3 = v.rig.bone(&"head").basis.z
	_check(head_fwd.z > 0.5, "a cabeça aponta para a frente do corpo")
	view.queue_free()
	await process_frame


# --- Estados a partir da simulação -------------------------------------------------------------

func _test_states_from_sim() -> void:
	var view := _make()
	await process_frame
	var v := view.visual as PaladinRigVisual
	var u := v.unit
	var an := v.animator
	_tick(v, 0.3)
	_check(an.debug_state == &"IDLE", "parado → IDLE (%s)" % an.debug_state)
	u.state = CombatUnit.State.MOVING
	_tick(v, 0.6, Vector2(u.move_speed, 0))
	_check(an.debug_state == &"WALK" and an.dir == D.RIGHT, "andando → WALK RIGHT (%s)" % an.debug_state)
	# ataque: a preparação começa pela recarga real e o impacto espera o evento real
	var foe := CombatUnit.new(2, CombatUnit.Team.ENEMY, UnitCatalog.get_def(&"warrior").to_stats(), u.position + Vector2(30, 0))
	u.target = foe
	u.state = CombatUnit.State.ATTACKING
	u.cooldown = 0.8
	_tick(v, 0.1)
	_check(not an.attack_active, "fora da janela de preparação ainda não ataca")
	u.cooldown = 0.25
	_tick(v, VDT)
	_check(an.attack_active and an.attack_p < PaladinPoseLibrary.ATTACK_IMPACT, "preparação começa pela recarga real (%.2f)" % an.attack_p)
	_check(an.move_w < 1.0, "ao decidir atacar ele para de andar (a caminhada sai)")
	u.cooldown = 0.001
	_tick(v, 0.2)
	_check(an.attack_active and not an.attack_struck and an.attack_p < PaladinPoseLibrary.ATTACK_IMPACT, "segura antes do impacto até o dano real (%.3f)" % an.attack_p)
	u.cooldown = u.attack_interval
	v.on_attack_performed()
	_check(an.attack_struck and an.attack_p >= PaladinPoseLibrary.ATTACK_IMPACT, "o impacto acontece no evento real de dano")
	_tick(v, PaladinPoseLibrary.ATTACK_TIME)
	_check(not an.attack_active, "ataque → recuperação → termina")
	u.target = null
	u.state = CombatUnit.State.IDLE
	_tick(v, 0.5)
	_check(an.debug_state == &"IDLE" and an.attack_w < 0.01, "depois do golpe volta ao idle sem salto")
	# hit curto
	v.on_hit()
	_tick(v, VDT)
	_check(String(an.debug_state).contains("HIT"), "dano → HIT")
	_tick(v, 0.3)
	_check(not String(an.debug_state).contains("HIT"), "HIT é curto e volta ao estado anterior")
	# provocação → espera → escudo → bloqueio → fim
	v.on_ability_event(&"taunt")
	u.paladin.delay = PaladinTaunt.SHIELD_DELAY
	_tick(v, 0.3)
	_check(an.debug_state == &"TAUNT", "provocação real → TAUNT")
	_tick(v, 0.6)
	_check(an.debug_state == &"GUARD_READY", "espera do escudo → guarda pronta (%s)" % an.debug_state)
	u.paladin.delay = -1.0
	u.paladin.shield_t = PaladinTaunt.SHIELD_DURATION
	u.paladin.facing = Vector2(1, 0)
	v.on_ability_event(&"shield")
	_tick(v, 0.4)
	_check(an.debug_state == &"SHIELD_ACTIVE", "escudo real → SHIELD_ACTIVE (%s)" % an.debug_state)
	v.on_ability_event(&"block")
	v.on_hit()
	_tick(v, VDT)
	_check(String(an.debug_state).contains("BLOCK") and not String(an.debug_state).contains("HIT"), "bloqueio real → BLOCK (o golpe no escudo não vira HIT)")
	u.paladin.shield_t = 0.0
	_tick(v, 0.8)
	_check(an.debug_state == &"IDLE", "escudo acabou → volta ao idle (%s)" % an.debug_state)
	# empurrão: a SIMULAÇÃO desloca a unidade sem estar andando → reação de PUSH (sem mover nada)
	u.state = CombatUnit.State.IDLE
	var before := u.position
	u.position += Vector2(-6, 0)
	var after_sim := u.position
	_tick(v, VDT)
	_check(String(an.debug_state).contains("PUSH"), "deslocamento real sem andar → PUSH")
	_check(u.position == after_sim and u.position != before, "a animação de push não desloca a unidade (só a simulação moveu)")
	_tick(v, 0.6)
	_check(not String(an.debug_state).contains("PUSH"), "push recupera a postura")
	# morte → cadáver
	u.die()
	_tick(v, 0.5)
	_check(an.debug_state == &"DEATH", "morto → DEATH")
	_tick(v, 1.5)
	_check(an.debug_state == &"CORPSE" and v.pick_rect().size.x > v.pick_rect().size.y, "queda termina no cadáver deitado (área clicável deitada)")
	v.on_attack_performed()
	v.on_ability_event(&"taunt")
	v.on_hit()
	_tick(v, 0.3)
	_check(an.debug_state == &"CORPSE", "eventos tardios não levantam o cadáver")
	view.queue_free()
	await process_frame


## Nenhum método do visual (eventos, prévias, empurrão) escreve na CombatUnit.
func _test_visual_never_writes_unit() -> void:
	var view := _make()
	await process_frame
	var v := view.visual as PaladinRigVisual
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
	_check(_snapshot(u) == snap, "visual (eventos, prévias, empurrão, morte prévia) não altera a CombatUnit")
	_check(u.is_alive() and foe.hp == foe.max_hp, "animações não matam nem aplicam dano")
	view.queue_free()
	await process_frame


func _snapshot(u: CombatUnit) -> Array:
	var p := u.paladin
	return [u.hp, u.max_hp, u.damage, u.attack_range, u.attack_interval, u.move_speed, u.radius, u.position,
		u.state, u.cooldown, u.target, u.team, p.cooldown, p.delay, p.shield_t, p.shield_hit, p.facing]


# --- Orçamento de desempenho ------------------------------------------------------------------

func _test_performance_budget() -> void:
	var view := _make()
	await process_frame
	var v := view.visual as PaladinRigVisual
	v.preview(&"walk", D.DOWN_RIGHT)
	var n := 120
	var t0 := Time.get_ticks_usec()
	for i in n:
		v.update_visual(VDT)
		v.rig.build_commands()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
	_check(ms < 4.0, "um Paladino custa %.2f ms por quadro de CPU (animação + montagem do desenho)" % ms)
	print("  custo por Paladino: %.2f ms/quadro" % ms)
	view.queue_free()
	await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures += 1
		printerr("  FALHOU: ", what)
